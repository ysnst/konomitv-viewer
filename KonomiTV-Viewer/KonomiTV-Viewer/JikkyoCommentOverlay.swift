import UIKit

/// 録画再生で、映像の上にニコニコ実況の過去ログコメントを流す重ね物。
///
/// Web 版 (DPlayer) のコメント表示の写し。右から左へ流れるコメントと、
/// 上・下に固定されるコメントを、再生位置に合わせて出す。
/// 個々のコメントの表示位置は「いまの再生位置」だけから計算するので、
/// 一時停止すればその場で止まり、再生速度を変えれば流れも追随する。
/// シークしたときは呼び出し側から reset(to:) を受けて、その位置より
/// 前のコメントは流さない (Web 版がシーク時にコメントを読み直す動きと同じ)。
/// 予期しない位置の飛び (検出できなかったシーク) は、毎フレームの
/// 位置の変化量から検出して追随する。
final class JikkyoCommentOverlayView: UIView {

    /// 上・下に固定されるコメントが表示され続ける秒数。
    private static let fixedDuration: Double = 3.5
    /// 流れるコメントが画面幅を横切る秒数の基準 (速さ 1 倍のとき)。
    /// コメント自身の幅の分だけ、画面に出ている時間はこれより長くなる。
    private static let baseCrossSeconds: Double = 3.5

    /// コメントの不透明度 (0〜1)。設定の「ニコニコ実況」の値。
    /// 既定は Web 版の既定値 (0.5)。
    var displayOpacity: Double = 0.5
    /// コメントの流れる速さの倍率。設定の「ニコニコ実況」の値。
    var speedRate: Double = 1
    /// コメントの字の基準の大きさ (px)。設定の「ニコニコ実況」の値。
    /// 既定は Web 版の既定値 (34)。
    var fontSizeReference: Double = 34
    /// 空いているレーンが無いときもコメントを出すかどうか
    /// (設定の「無制限に表示」)。出す場合は先頭のレーンへ重ねて出す。
    var unlimited = false

    /// 現在の再生位置 (秒) を返す口。再生画面が差し込む。
    var positionProvider: (() -> Double)?

    /// 表示するかどうか。切ると出ているコメントは消え、
    /// 入れ直すとその時点の再生位置から流し始める。
    private(set) var displayEnabled = true

    /// 時刻順に並んだコメント一式。
    private var comments: [JikkyoComment] = []
    /// 次に出現させるコメントの添字。
    private var nextIndex = 0
    /// 前フレームで見た再生位置。位置の飛び (シーク) の検出に使う。
    private var lastPosition: Double?

    /// 流れている途中のコメント1件分の控え。
    private struct FlowItem {
        let label: UILabel
        let comment: JikkyoComment
        let width: CGFloat
        let lane: Int
    }
    /// 上・下に固定表示中のコメント1件分の控え。
    private struct FixedItem {
        let label: UILabel
        let comment: JikkyoComment
    }
    private var flowItems: [FlowItem] = []
    private var fixedItems: [FixedItem] = []
    /// レーン (流れるコメントの行) ごとに、次のコメントを出せるように
    /// なる再生位置。前のコメントの末尾が画面に入りきった時点で出せる。
    private var laneReadyAt: [Double] = []

    private var displayLink: CADisplayLink?
    /// CADisplayLink の受け口 (リンク側が受け口を強く持つため、
    /// 弱い参照だけを持つ小さな仲介を挟む)。
    private lazy var linkTarget = DisplayLinkTarget(overlay: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - 呼び出し側からの操作

    /// コメント一式を受け取る。その時点の再生位置から流し始める。
    func setComments(_ newComments: [JikkyoComment]) {
        comments = newComments.sorted { $0.time < $1.time }
        reset(to: positionProvider?() ?? 0)
    }

    /// 生放送用: コメントを末尾へ足す。既に出ているコメントは消さない
    /// (setComments と違い、表示中のものはそのまま流れ続ける)。
    /// 時刻は届いた順に増えていく前提 (生放送の受け口がそう割り振る)。
    func appendComments(_ newComments: [JikkyoComment]) {
        guard !newComments.isEmpty else { return }
        comments.append(contentsOf: newComments)
    }

    /// 生放送用: 既に出し終えた古いコメントを蓄えから捨てる
    /// (長く見続けても蓄えが膨らまないように)。
    func pruneSpawnedComments(before position: Double) {
        var dropCount = 0
        while dropCount < nextIndex, comments[dropCount].time < position {
            dropCount += 1
        }
        guard dropCount > 0 else { return }
        comments.removeFirst(dropCount)
        nextIndex -= dropCount
    }

    /// 毎フレームの見張りを始める。
    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// 見張りを止め、出ているコメントも消す (画面を離れるとき)。
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        clearActiveItems()
        lastPosition = nil
    }

    /// 表示のオン/オフを切り替える。
    func setDisplayEnabled(_ enabled: Bool) {
        guard enabled != displayEnabled else { return }
        displayEnabled = enabled
        if enabled {
            reset(to: positionProvider?() ?? 0)
        } else {
            clearActiveItems()
        }
    }

    /// 指定した再生位置に表示を合わせ直す。シークのときに呼び出し側から受ける。
    /// その位置より前のコメントは流さない (Web 版のシーク時の動きと同じ)。
    func reset(to position: Double) {
        clearActiveItems()
        nextIndex = comments.firstIndex { $0.time >= position } ?? comments.count
        lastPosition = position
    }

    // MARK: - 毎フレームの処理

    fileprivate func tick() {
        guard displayEnabled, bounds.width > 0, bounds.height > 0,
              let provider = positionProvider else { return }
        let pos = provider()
        guard pos.isFinite else { return }
        if let last = lastPosition {
            // 位置が後ろへ戻った、または通常の再生ではありえない量だけ
            // 前へ飛んだ場合は、シークとして扱って表示を合わせ直す。
            // (通常の再生では1フレームの進みは 0.1 秒にもならない。
            //  2 秒の余裕は、表示の見張りが間引かれた場合の保険。)
            if pos < last - 0.25 || pos - last > 2.0 {
                reset(to: pos)
            }
        }
        lastPosition = pos
        spawnComments(upTo: pos)
        layoutActiveItems(at: pos)
    }

    /// 再生位置を過ぎたコメントを出現させる。
    /// 画面をすでに通り過ぎたものや、レーンに空きが無いものは出さない
    /// (Web 版の既定の動きと同じ)。
    private func spawnComments(upTo pos: Double) {
        while nextIndex < comments.count {
            let comment = comments[nextIndex]
            guard comment.time <= pos else { break }
            nextIndex += 1
            spawn(comment, at: pos)
        }
    }

    private func spawn(_ comment: JikkyoComment, at pos: Double) {
        let label = makeLabel(for: comment)
        let size = label.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(origin: .zero, size: size)
        switch comment.type {
        case "top", "bottom":
            // 固定コメントは、出現からの時間が残っているときだけ出す。
            guard pos - comment.time <= Self.fixedDuration else { return }
            addSubview(label)
            fixedItems.append(FixedItem(label: label, comment: comment))
        default:
            // "right" は流れるコメント (サーバー側の位置指定の既定)。
            // 画面をすでに通り過ぎていたら出さない。
            let elapsed = pos - comment.time
            guard elapsed * Double(velocity) <= Double(bounds.width + size.width) else { return }
            guard let lane = claimLane(at: pos, itemWidth: size.width) else { return }
            addSubview(label)
            flowItems.append(FlowItem(label: label, comment: comment, width: size.width, lane: lane))
        }
    }

    /// 流れるコメントの置き場所 (レーン) を確保する。
    /// 前のコメントの末尾が画面に入りきっているレーンだけが空いている。
    /// どのレーンも空いていなければ nil (そのコメントは出さない) で、
    /// 「無制限に表示」のときだけ先頭のレーンへ重ねて出す。
    private func claimLane(at pos: Double, itemWidth: CGFloat) -> Int? {
        let count = laneCount
        if laneReadyAt.count != count {
            laneReadyAt = Array(repeating: 0, count: count)
        }
        for lane in 0..<count where laneReadyAt[lane] <= pos {
            // このコメントの末尾が画面に入りきる (＋少しの間隔) まで、
            // このレーンは次のコメントに使えない。
            laneReadyAt[lane] = pos + Double((itemWidth + 8) / velocity)
            return lane
        }
        if unlimited, count > 0 {
            laneReadyAt[0] = pos + Double((itemWidth + 8) / velocity)
            return 0
        }
        return nil
    }

    /// 出ているコメントの位置を、いまの再生位置に合わせて置き直す。
    private func layoutActiveItems(at pos: Double) {
        let width = bounds.width
        let speed = velocity
        flowItems = flowItems.filter { item in
            let x = width - CGFloat(pos - item.comment.time) * speed
            guard pos >= item.comment.time, x + item.width >= 0 else {
                item.label.removeFromSuperview()
                return false
            }
            item.label.frame.origin = CGPoint(x: x, y: CGFloat(item.lane) * laneHeight)
            return true
        }
        // 固定コメントは出現順に積む (上は下へ、下は上へ)。積む位置は
        // 各ラベルの実測の高さで決め (大小の字が混ざっても重ならない)、
        // 上と下が中央でぶつかる・表示領域からはみ出す分は出さない
        // (「無制限に表示」のときだけ、収まらない分も従来どおり出す)。
        var topCursor: CGFloat = 0
        var bottomCursor: CGFloat = 0
        fixedItems = fixedItems.filter { item in
            let age = pos - item.comment.time
            guard age >= 0, age <= Self.fixedDuration else {
                item.label.removeFromSuperview()
                return false
            }
            let size = item.label.bounds.size
            let x = (width - size.width) / 2
            if item.comment.type == "top" {
                if !unlimited, topCursor + size.height > bounds.height - bottomCursor {
                    item.label.isHidden = true
                    return true
                }
                item.label.isHidden = false
                item.label.frame.origin = CGPoint(x: x, y: topCursor)
                topCursor += size.height + 2
            } else {
                if !unlimited, bottomCursor + size.height > bounds.height - topCursor {
                    item.label.isHidden = true
                    return true
                }
                item.label.isHidden = false
                item.label.frame.origin = CGPoint(
                    x: x, y: bounds.height - bottomCursor - size.height)
                bottomCursor += size.height + 2
            }
            return true
        }
    }

    private func clearActiveItems() {
        for item in flowItems { item.label.removeFromSuperview() }
        for item in fixedItems { item.label.removeFromSuperview() }
        flowItems = []
        fixedItems = []
        laneReadyAt = []
    }

    // MARK: - 見た目の寸法

    /// 流れる速さ (1秒あたりのポイント数)。画面幅を基準の秒数で
    /// 横切る速さに、設定の倍率を掛けたもの。どのコメントも同じ速さ
    /// (追いつきが起きない)。
    private var velocity: CGFloat {
        let cross = Self.baseCrossSeconds / max(0.1, speedRate)
        return bounds.width > 0 ? bounds.width / CGFloat(cross) : 0
    }

    /// コメントの字の基準の大きさ。設定の大きさを、映像の幅に
    /// 合わせて縮める (幅 700 以上で設定どおり、下限は 16)。
    private var baseFontSize: CGFloat {
        let reference = CGFloat(fontSizeReference)
        return min(reference, max(16, bounds.width * reference / 700))
    }

    /// レーン1行分の高さ。
    private var laneHeight: CGFloat {
        baseFontSize * 1.4
    }

    /// レーンの数 (映像の高さに収まるだけ)。
    private var laneCount: Int {
        max(1, Int(bounds.height / laneHeight))
    }

    private func makeLabel(for comment: JikkyoComment) -> UILabel {
        let label = UILabel()
        label.text = comment.text
        // 大きさの段階はニコニコ実況の比率 (大 1.5 倍・小 0.67 倍)。
        let scale: CGFloat
        switch comment.size {
        case "big": scale = 1.5
        case "small": scale = 0.67
        default: scale = 1
        }
        label.font = .boldSystemFont(ofSize: baseFontSize * scale)
        label.textColor = Self.color(fromHex: comment.color)
        // 明るい映像の上でも読めるよう、黒い影を付ける (Web 版の文字の影と同じ考え方)。
        label.shadowColor = UIColor.black.withAlphaComponent(0.75)
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.alpha = CGFloat(displayOpacity)
        label.isUserInteractionEnabled = false
        return label
    }

    /// "#RRGGBB" 形式の色を UIColor に直す。解釈できなければ白。
    private static func color(fromHex hex: String) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// CADisplayLink の受け口。リンクは受け口を強く保持するため、
/// 重ね物本体への弱い参照だけを持つ仲介を挟み、循環を避ける。
private final class DisplayLinkTarget: NSObject {
    weak var overlay: JikkyoCommentOverlayView?

    init(overlay: JikkyoCommentOverlayView) {
        self.overlay = overlay
    }

    @objc func tick() {
        overlay?.tick()
    }
}
