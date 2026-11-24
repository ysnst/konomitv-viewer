import Foundation
import UIKit

#if canImport(libaribcaption)
import libaribcaption
#endif

/// 字幕の重ね物。映像の枠 (surfaceView) の中に入れて使う。
/// 字幕の絵は字幕の画面 (例: 960x540) の寸法で作られ、映像の表示範囲に
/// 合わせて引き伸ばして出す (Web 版が字幕の Canvas を映像に重ねるのと同じ)。
/// 操作は受けない。
final class CaptionOverlayView: UIView {
    private let imageView = UIImageView()

    /// 字幕を出す範囲の指定 (この重ね物の大きさに対する割合の四角)。
    /// nil のときは全体に出す。生放送でデータ放送を表示している間は、
    /// データ放送の文書が映像用に開けている穴の割合が入り、字幕と
    /// 文字スーパーはその穴の中だけに出る (本物のテレビで、字幕が
    /// 映像と一緒に縮んで窓の中に出る扱いに合わせる)。録画側は
    /// 指定しないので、今までどおり全体に出る。
    var displayRectFractions: CGRect? {
        didSet { setNeedsLayout() }
    }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let fractions = displayRectFractions, fractions.width > 0, fractions.height > 0 {
            imageView.frame = CGRect(
                x: bounds.minX + bounds.width * fractions.minX,
                y: bounds.minY + bounds.height * fractions.minY,
                width: bounds.width * fractions.width,
                height: bounds.height * fractions.height
            )
        } else {
            imageView.frame = bounds
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 出す字幕の絵を差し替える。nil なら何も出さない。
    func setImage(_ image: UIImage?) {
        imageView.image = image
    }
}

#if canImport(libaribcaption)

/// 字幕表示の本体。字幕の包み (再生位置つき) を受け取って蓄え、
/// 再生位置に合わせて文字化の部品 (libaribcaption) へ流し込み、
/// その時刻の字幕を1枚の絵にして返す。
///
/// 包みの入り口は3つあるが、蓄えた後の扱いは共通:
/// - 通常画質: AVPlayer から届く時刻つきデータ (位置はそのまま使える)。
/// - H.265 / HEVC: アプリ内の中継が区切りファイルから取り出した包み。
///   位置は「プレイリストの区切りの長さの累計 + 区切り内の差分」で決める
///   (ingestRelayPlaylist / ingestRelaySegment)。
/// - 生放送: アプリ内の中継が流れから取り出した包み。位置は「流れの
///   最初の映像の時刻印との差」で決める (ingestLivePackets)。
///
/// 字幕 (0x80) と文字スーパー (0x81) は別の読み解き・描画の組で扱い、
/// 最後に重ねて1枚にする。描画の設定 (フォント・縁取り・背景・
/// 文字スーパーの表示) は、設定の「字幕」画面の値 (利用者設定と共通、
/// SyncedSettingsStore) から取る。DRCS の置き換えは有効。
/// 背景の濃さは、部品に「背景の濃さを指定する」口が無いため、
/// 濃さ 0 のときだけ「背景を出さない」として効かせる (途中の値は
/// データどおりのまま)。フォントは、設定の選択肢を iOS のフォントへ
/// 対応づけたもの (SyncedClientSettings.iosFontFamilies) を使う。
final class CaptionDisplayEngine {
    /// 蓄えた字幕の包み1つ分。
    private struct Packet {
        var position: Double
        var payload: Data
    }

    /// 描画の層 (字幕 / 文字スーパー) ごとの状態。
    private struct LayerState {
        /// いま出している絵 (字幕の画面の寸法)。無いときは nil。
        var image: UIImage?
        /// 絵があるかどうか (無い→有る・有る→無いの切り替わりを拾うため)。
        var hasImage = false
    }

    // MARK: 蓄え

    private var packets: [Packet] = []
    /// 重複の受け取りを弾くための控え (位置・長さ・先頭バイトの組み合わせ)。
    private var seenKeys: Set<String> = []
    /// どこまで部品へ流し込んだか (packets の添字)。
    private var feedIndex = 0
    /// 前回の更新で見た再生位置。飛び (シーク等) の検出に使う。
    private var lastPosition: Double?
    /// 既に流し込んだ範囲より前の包みが後から届いた印。
    /// 次の更新で、部品の中身を空にして先頭から流し直す。
    private var needsRefill = false

    // MARK: H.265 側の物差し (プレイリストの区切りの長さ)

    /// 区切りの番号ごとの開始位置 (区切りの長さの累計)。
    private var segmentStarts: [Double] = []
    /// 物差しが届く前に来た区切りの控え (番号 → 包みと映像の先頭の時刻印)。
    private var pendingSegments: [Int: (packets: [TSID3Extractor.Packet], videoFirstPTS: Int64?)] = [:]

    // MARK: 文字化の部品 (libaribcaption)

    private var context: OpaquePointer?
    private var captionDecoder: OpaquePointer?
    private var superimposeDecoder: OpaquePointer?
    private var captionRenderer: OpaquePointer?
    private var superimposeRenderer: OpaquePointer?
    /// 部品の用意ができたかどうか (できなければ字幕は出さない)。
    private var available = false
    /// 描画の画面の寸法を部品へ伝えたかどうか (層ごと)。
    private var captionFrameReady = false
    private var superimposeFrameReady = false
    /// 字幕の画面の寸法 (最初に読み解けた字幕から決める。層ごと)。
    /// 部品の中身を空にしても寸法は変わらないため、状態とは別に持つ。
    private var captionPlaneWidth = 0
    private var captionPlaneHeight = 0
    private var superimposePlaneWidth = 0
    private var superimposePlaneHeight = 0
    private var captionState = LayerState()
    private var superimposeState = LayerState()
    /// 文字スーパーを出すかどうか (設定の「ビデオの文字スーパー」)。
    /// 部品の用意のときに読み、再生の途中では変えない。
    private var showSuperimpose = false
    /// 文字スーパーの設定を、テレビ側 (tv_show_superimpose) から取るか
    /// どうか。生放送では true にする (Web 版の生放送では、字幕の設定の
    /// 「テレビをみるときに文字スーパーを表示する」が効くため)。
    /// 録画では false のまま (video_show_superimpose が効く)。
    /// 部品の用意より前に決めること。
    var useTVSuperimposeSetting = false

    /// いま出すべき字幕の絵 (字幕の画面の寸法のまま)。無いときは nil。
    private(set) var currentImage: UIImage?

    deinit {
        if let captionRenderer { aribcc_renderer_free(captionRenderer) }
        if let superimposeRenderer { aribcc_renderer_free(superimposeRenderer) }
        if let captionDecoder { aribcc_decoder_free(captionDecoder) }
        if let superimposeDecoder { aribcc_decoder_free(superimposeDecoder) }
        if let context { aribcc_context_free(context) }
    }

    // MARK: - 部品の用意

    private func ensureCreated() {
        guard context == nil else { return }
        context = aribcc_context_alloc()
        guard let context else { return }
        captionDecoder = aribcc_decoder_alloc(context)
        superimposeDecoder = aribcc_decoder_alloc(context)
        captionRenderer = aribcc_renderer_alloc(context)
        superimposeRenderer = aribcc_renderer_alloc(context)
        guard let captionDecoder, let superimposeDecoder,
              let captionRenderer, let superimposeRenderer else { return }
        let captionOK = aribcc_decoder_initialize(
            captionDecoder, ARIBCC_ENCODING_SCHEME_AUTO, ARIBCC_CAPTIONTYPE_CAPTION,
            ARIBCC_PROFILE_DEFAULT, ARIBCC_LANGUAGEID_DEFAULT)
        let superimposeOK = aribcc_decoder_initialize(
            superimposeDecoder, ARIBCC_ENCODING_SCHEME_AUTO, ARIBCC_CAPTIONTYPE_SUPERIMPOSE,
            ARIBCC_PROFILE_DEFAULT, ARIBCC_LANGUAGEID_DEFAULT)
        let captionRendererOK = aribcc_renderer_initialize(
            captionRenderer, ARIBCC_CAPTIONTYPE_CAPTION,
            ARIBCC_FONTPROVIDER_TYPE_AUTO, ARIBCC_TEXTRENDERER_TYPE_AUTO)
        let superimposeRendererOK = aribcc_renderer_initialize(
            superimposeRenderer, ARIBCC_CAPTIONTYPE_SUPERIMPOSE,
            ARIBCC_FONTPROVIDER_TYPE_AUTO, ARIBCC_TEXTRENDERER_TYPE_AUTO)
        guard captionOK, superimposeOK, captionRendererOK, superimposeRendererOK else { return }
        // 描画の設定は、設定の「字幕」画面の値 (利用者設定と共通) から取る。
        // DRCS (外字) は対応する文字への置き換えを有効にする (固定)。
        let captionSettings = SyncedSettingsStore.shared.current
        showSuperimpose = useTVSuperimposeSetting
            ? captionSettings.tvShowSuperimpose
            : captionSettings.videoShowSuperimpose
        for renderer in [captionRenderer, superimposeRenderer] {
            aribcc_renderer_set_force_stroke_text(
                renderer, captionSettings.alwaysBorderCaptionText)
            aribcc_renderer_set_replace_drcs(renderer, true)
            // 背景の濃さは部品に直接の口が無いため、濃さ 0 の指定のとき
            // だけ「背景を出さない」として効かせる。
            if captionSettings.specifyCaptionOpacity, captionSettings.captionOpacity == 0 {
                aribcc_renderer_set_force_no_background(renderer, true)
            }
            // フォントは設定の選択肢を iOS のフォントへ対応づけたもの。
            // 対応が空 (sans-serif) のときは部品の既定のままにする。
            let families = SyncedClientSettings.iosFontFamilies(
                forCaptionFont: captionSettings.captionFont)
            if !families.isEmpty {
                let cStrings = families.map { strdup($0) }
                defer { cStrings.forEach { free($0) } }
                let pointers: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
                _ = pointers.withUnsafeBufferPointer { buffer in
                    aribcc_renderer_set_default_font_family(
                        renderer, buffer.baseAddress, buffer.count, false)
                }
            }
        }
        available = true
    }

    // MARK: - 再生の作り直し

    /// 新しい再生が始まるときに、蓄えと部品の中身を空にする。
    func resetForNewPlayback() {
        packets = []
        seenKeys = []
        feedIndex = 0
        lastPosition = nil
        needsRefill = false
        segmentStarts = []
        pendingSegments = [:]
        captionFrameReady = false
        superimposeFrameReady = false
        captionPlaneWidth = 0
        captionPlaneHeight = 0
        superimposePlaneWidth = 0
        superimposePlaneHeight = 0
        flushPipelines()
    }

    /// 部品の中身 (読み解きと描画の状態) を空にする。
    /// 蓄えた包みは残るので、次の更新でその位置まで流し直される。
    private func flushPipelines() {
        if let captionDecoder { aribcc_decoder_flush(captionDecoder) }
        if let superimposeDecoder { aribcc_decoder_flush(superimposeDecoder) }
        if let captionRenderer { aribcc_renderer_flush(captionRenderer) }
        if let superimposeRenderer { aribcc_renderer_flush(superimposeRenderer) }
        captionState = LayerState()
        superimposeState = LayerState()
        currentImage = nil
    }

    // MARK: - 包みの受け取り

    /// 字幕の包みを1つ受け取る (位置が分かっている経路用)。
    /// 中身の形 (先頭が 0x80/0x81、続く2バイトが 0xFF 0xF0) に合うもの
    /// だけを蓄える。同じ包みが重なって届いた場合は1つにまとめる。
    func ingest(position: Double, payload: Data) {
        guard position.isFinite, Self.isCaptionPayload(payload) else { return }
        let key = Self.dedupeKey(position: position, payload: payload)
        guard !seenKeys.contains(key) else { return }
        seenKeys.insert(key)
        let packet = Packet(position: position, payload: payload)
        if let last = packets.last, last.position <= position {
            packets.append(packet)
        } else {
            let index = packets.firstIndex { $0.position > position } ?? packets.count
            packets.insert(packet, at: index)
            if index < feedIndex {
                needsRefill = true
            }
        }
        // 既に通り過ぎた位置の包みが後から来た場合は、流し直しが必要。
        if let lastPosition, position <= lastPosition, feedIndex > 0 {
            needsRefill = true
        }
    }

    /// H.265 側の物差し: プレイリストから読んだ区切りの長さ (順番どおり)。
    /// 区切りの開始位置はこの累計で決まる。プレイリストが取り直された
    /// ときは、新しい値で置き換える。
    func ingestRelayPlaylist(durations: [Double]) {
        var starts: [Double] = []
        starts.reserveCapacity(durations.count)
        var sum = 0.0
        for duration in durations {
            starts.append(sum)
            sum += duration
        }
        segmentStarts = starts
        // 物差しより先に届いていた区切りがあれば、ここで流し込む。
        let pending = pendingSegments
        pendingSegments = [:]
        for (sequence, entry) in pending {
            ingestRelaySegment(sequence: sequence, packets: entry.packets,
                               videoFirstPTS: entry.videoFirstPTS)
        }
    }

    /// H.265 側の包みの受け取り: 区切りファイルから取り出した包み一式。
    /// 各包みの位置は「区切りの開始位置 (累計) + 区切り内の差分」で決める。
    /// 区切り内の差分は、字幕の包みの時刻印と区切りの先頭の映像の
    /// 時刻印との差 (90kHz の時刻印は一回りすることがあるため、
    /// 差は一回り分を考慮して取る)。
    /// 映像の先頭の時刻印が取れていない区切りでは、最初の字幕の包みの
    /// 時刻印を代わりに使う (ずれは最大で包み1つ分ほど)。
    func ingestRelaySegment(sequence: Int, packets: [TSID3Extractor.Packet], videoFirstPTS: Int64?) {
        guard segmentStarts.indices.contains(sequence) else {
            pendingSegments[sequence] = (packets, videoFirstPTS)
            return
        }
        guard let reference = videoFirstPTS ?? packets.first?.pts90 else { return }
        let base = segmentStarts[sequence]
        for packet in packets {
            let offset = Self.ptsDifferenceSeconds(packet.pts90, reference)
            ingest(position: base + offset, payload: packet.payload)
        }
    }

    /// 生放送側の包みの受け取り: 流れの最初の映像の時刻印を基準に、
    /// 字幕の包みの時刻印との差を再生位置に読み替えて蓄える
    /// (生放送にはプレイリストの物差しが無いため、使える物差しは
    /// この差だけになる)。
    func ingestLivePackets(_ packets: [TSID3Extractor.Packet], firstVideoPTS: Int64) {
        for packet in packets {
            let position = Self.ptsDifferenceSeconds(packet.pts90, firstVideoPTS)
            ingest(position: position, payload: packet.payload)
        }
        pruneOldPackets()
    }

    /// 生放送では包みが際限なく増え続けるため、既に流し込み済みで
    /// 再生位置より十分に前の包みを捨て、蓄えが膨らまないようにする。
    /// 捨てる分は重複よけの控えからも落とす。
    private func pruneOldPackets() {
        guard packets.count > 4000, feedIndex > 0 else { return }
        let cutoff = packets[feedIndex - 1].position - 120
        var dropCount = 0
        while dropCount < feedIndex, packets[dropCount].position < cutoff {
            dropCount += 1
        }
        guard dropCount > 0 else { return }
        packets.removeFirst(dropCount)
        feedIndex -= dropCount
        let cutoffMs = Int((cutoff * 1000).rounded())
        seenKeys = seenKeys.filter { key in
            guard let msText = key.split(separator: "/").first,
                  let ms = Int(msText) else { return false }
            return ms >= cutoffMs
        }
    }

    /// 90kHz の時刻印同士の差 (秒)。時刻印は 33 ビットで一回りする
    /// (約26.5時間) ため、差が半周を超えたら一回り分を戻して解釈する。
    private static func ptsDifferenceSeconds(_ a: Int64, _ b: Int64) -> Double {
        let modulus: Int64 = 1 << 33
        var diff = (a - b) & (modulus - 1)
        if diff >= modulus / 2 {
            diff -= modulus
        }
        return Double(diff) / 90000.0
    }

    /// 中身が字幕の包みの形かどうか (先頭 0x80/0x81 + 0xFF 0xF0)。
    private static func isCaptionPayload(_ payload: Data) -> Bool {
        guard payload.count >= 3 else { return false }
        let head = [UInt8](payload.prefix(3))
        return (head[0] == 0x80 || head[0] == 0x81) && head[1] == 0xFF && head[2] == 0xF0
    }

    private static func dedupeKey(position: Double, payload: Data) -> String {
        let ms = Int((position * 1000).rounded())
        let head = payload.prefix(8).map { String(format: "%02x", Int($0)) }.joined()
        return "\(ms)/\(payload.count)/\(head)"
    }

    // MARK: - 再生位置に合わせた更新

    /// 再生位置に合わせて、包みを部品へ流し込み、その時刻の字幕の絵を
    /// 更新する。戻り値は、出す絵が変わったかどうか。
    /// 位置が飛んだ (シーク・CM自動スキップ・速度変更直後の大きなずれ)
    /// ときは、部品の中身を空にして、その位置までの包みを流し直す
    /// (字幕の内容は「その時刻までに届いた包み」の積み重ねで決まるため)。
    @discardableResult
    func update(position: Double) -> Bool {
        ensureCreated()
        guard available, position.isFinite else { return false }
        if needsRefill {
            flushPipelines()
            feedIndex = 0
            needsRefill = false
        } else if let last = lastPosition, position < last - 1.5 || position - last > 2.0 {
            // 逆向きの飛び・大きな前向きの飛びは、移動 (シーク等) とみなす。
            // 通常の再生では 0.5 秒ごとの更新で、速度2倍でも進みは約1秒。
            // 逆向きの幅を広めに取るのは、再生部品の時刻の小さな揺れ
            // (数百ミリ秒の前後) で流し直しを繰り返さないため
            // (操作での戻しは最小でも5秒なので、1.5秒で十分に拾える)。
            flushPipelines()
            feedIndex = 0
        }
        lastPosition = position
        while feedIndex < packets.count, packets[feedIndex].position <= position + 0.05 {
            feed(packets[feedIndex])
            feedIndex += 1
        }
        let ptsMs = Int64((position * 1000).rounded())
        var changed = false
        if captionFrameReady, let captionRenderer {
            changed = renderLayer(captionRenderer, state: &captionState, atMs: ptsMs,
                                  planeWidth: captionPlaneWidth, planeHeight: captionPlaneHeight) || changed
        }
        if superimposeFrameReady, let superimposeRenderer {
            changed = renderLayer(superimposeRenderer, state: &superimposeState, atMs: ptsMs,
                                  planeWidth: superimposePlaneWidth, planeHeight: superimposePlaneHeight) || changed
        }
        if changed {
            recomposite()
        }
        return changed
    }

    /// 包みを1つ、種類に応じた読み解き側へ渡す。字幕として読み解けたら、
    /// 描画側へ追加する (描画の画面の寸法は、最初の字幕で決める)。
    private func feed(_ packet: Packet) {
        let isSuperimpose = packet.payload.first == 0x81
        // 設定で文字スーパーを出さないときは、包み自体を流さない。
        if isSuperimpose, !showSuperimpose { return }
        guard let decoder = isSuperimpose ? superimposeDecoder : captionDecoder,
              let renderer = isSuperimpose ? superimposeRenderer : captionRenderer else { return }
        let ptsMs = Int64((packet.position * 1000).rounded())
        packet.payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var caption = aribcc_caption_t()
            let status = aribcc_decoder_decode(decoder, base, packet.payload.count, ptsMs, &caption)
            guard status == ARIBCC_DECODE_STATUS_GOT_CAPTION else { return }
            let frameReady = isSuperimpose ? superimposeFrameReady : captionFrameReady
            if !frameReady, caption.plane_width > 0, caption.plane_height > 0 {
                aribcc_renderer_set_frame_size(renderer, caption.plane_width, caption.plane_height)
                if isSuperimpose {
                    superimposeFrameReady = true
                    superimposePlaneWidth = Int(caption.plane_width)
                    superimposePlaneHeight = Int(caption.plane_height)
                } else {
                    captionFrameReady = true
                    captionPlaneWidth = Int(caption.plane_width)
                    captionPlaneHeight = Int(caption.plane_height)
                }
            }
            if isSuperimpose ? superimposeFrameReady : captionFrameReady {
                aribcc_renderer_append_caption(renderer, &caption)
            }
            aribcc_caption_cleanup(&caption)
        }
    }

    /// 層1つ分を、その時刻で描く。出す絵が変わったら true。
    private func renderLayer(_ renderer: OpaquePointer, state: inout LayerState, atMs: Int64,
                             planeWidth: Int, planeHeight: Int) -> Bool {
        var result = aribcc_render_result_t()
        let status = aribcc_renderer_render(renderer, atMs, &result)
        defer { aribcc_render_result_cleanup(&result) }
        switch status {
        case ARIBCC_RENDER_STATUS_GOT_IMAGE:
            state.image = Self.compositeImage(
                from: result, planeWidth: planeWidth, planeHeight: planeHeight)
            state.hasImage = state.image != nil
            return true
        case ARIBCC_RENDER_STATUS_NO_IMAGE:
            if state.hasImage {
                state.image = nil
                state.hasImage = false
                return true
            }
            return false
        default:
            // GOT_IMAGE_UNCHANGED (前と同じ) と ERROR は、絵を変えない。
            return false
        }
    }

    /// 字幕と文字スーパーの層を重ねて、出す絵を組み直す。
    /// 画布の寸法は字幕の層を優先し、無ければ文字スーパーの層に合わせる。
    private func recomposite() {
        guard let base = captionState.image ?? superimposeState.image else {
            currentImage = nil
            return
        }
        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        currentImage = renderer.image { _ in
            captionState.image?.draw(in: CGRect(origin: .zero, size: size))
            superimposeState.image?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 描画結果 (小さな画像の集まり) を、字幕の画面の寸法の1枚絵にする。
    /// 部品が出す画像は「透明度を掛けていない」色なので、重ね合わせは
    /// 透明度を考慮した通常の合成で計算する。
    private static func compositeImage(from result: aribcc_render_result_t,
                                       planeWidth: Int, planeHeight: Int) -> UIImage? {
        guard result.image_count > 0, let images = result.images,
              planeWidth > 0, planeHeight > 0 else { return nil }
        let width = planeWidth
        let height = planeHeight
        var canvas = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<Int(result.image_count) {
            let image = images[index]
            guard let bitmap = image.bitmap else { continue }
            let imgWidth = Int(image.width)
            let imgHeight = Int(image.height)
            let stride = Int(image.stride)
            let dstX = Int(image.dst_x)
            let dstY = Int(image.dst_y)
            for y in 0..<imgHeight {
                let cy = dstY + y
                guard cy >= 0, cy < height else { continue }
                for x in 0..<imgWidth {
                    let cx = dstX + x
                    guard cx >= 0, cx < width else { continue }
                    let src = bitmap + y * stride + x * 4
                    let sa = Double(src[3]) / 255.0
                    if sa <= 0 { continue }
                    let dstOffset = (cy * width + cx) * 4
                    let da = Double(canvas[dstOffset + 3]) / 255.0
                    let outA = sa + da * (1 - sa)
                    if outA <= 0 { continue }
                    for channel in 0..<3 {
                        let s = Double(src[channel]) / 255.0
                        let d = Double(canvas[dstOffset + channel]) / 255.0
                        let out = (s * sa + d * da * (1 - sa)) / outA
                        canvas[dstOffset + channel] = UInt8(max(0, min(255, (out * 255).rounded())))
                    }
                    canvas[dstOffset + 3] = UInt8(max(0, min(255, (outA * 255).rounded())))
                }
            }
        }
        let data = Data(canvas)
        let provider = CGDataProvider(data: data as CFData)
        guard let provider,
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#endif
