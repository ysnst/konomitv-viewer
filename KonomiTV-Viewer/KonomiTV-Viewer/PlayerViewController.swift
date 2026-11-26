import AVFoundation
import UIKit

#if canImport(VLCKit)
import VLCKit
#endif

/// 再生画面共通の部品 (録画・生放送の両方から使う)。
/// Web 版の再生画面は、操作類を映像に重ねて出し、しばらく触らなければ消す作り。
/// その重ね物の土台になるグラデーションと、通知ラベル、シークバーの色付けをここに置く。

/// 上端または下端に向けて黒へ抜けるグラデーションの板。
/// Web 版のヘッダー帯・操作帯と同じく、黒 (不透明度 0.81) から透明へ抜ける。
final class GradientView: UIView {
    enum Direction {
        /// 上が黒く、下へ向けて透明 (画面上部の帯用)。
        case top
        /// 上が透明で、下へ向けて黒く (画面下部の帯用)。
        case bottom
    }

    private let direction: Direction

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let gradient = layer as? CAGradientLayer else { return }
        let black = UIColor.black.withAlphaComponent(0.81).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        gradient.colors = direction == .top ? [black, clear] : [clear, black]
        gradient.locations = [0, 1]
    }
}

/// 通知文のラベル。文が無いときは自分を隠し、下の情報欄で場所を取らない。
final class NoticeLabel: UILabel {
    override var text: String? {
        didSet { isHidden = (text ?? "").isEmpty }
    }
}

/// シークバーの色を Web 版のプレイヤーに合わせる。
/// 再生済みの部分はテーマのピンク (DPlayer の theme = primary #E64F97)、
/// 残りは白20%、つまみも本家と同じアクセント色。
func stylePlayerSeekSlider(_ slider: UISlider) {
    slider.minimumTrackTintColor = AppPalette.accent
    slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
    slider.thumbTintColor = AppPalette.accent
}

/// Web 版パネルの小さな操作ボタン (program-info__button) の形にボタンを整える。
/// 地は background-lighten-1、角丸 4pt、文字は text-darken-1 の 12.7pt、
/// 内側の余白は上下 5pt・左右 8pt。
func stylePlayerChip(_ button: UIButton) {
    button.setTitleColor(AppPalette.metaText, for: .normal)
    button.titleLabel?.font = .scaledSystemFont(ofSize: 12.7)
    button.backgroundColor = AppPalette.panel
    button.layer.cornerRadius = 4
    button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
}

/// 小さな印やボタンを左から並べ、幅に収まらなければ次の行へ折り返す入れ物。
/// Web 版パネルのジャンルの印とボタンの並び (横に流して折り返す) を再現する。
/// 中身の大きさに合わせて高さが決まる (縦の並びの中では、その高さで場所を取る)。
final class ChipFlowView: UIView {
    /// 横の間隔 (印同士・ボタン同士)。
    var horizontalSpacing: CGFloat = 10 { didSet { setNeedsLayout() } }
    /// 行の間隔。
    var verticalSpacing: CGFloat = 16 { didSet { setNeedsLayout() } }
    /// 直近の配置で決まった中身の高さ。
    private var contentHeight: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews where !subview.isHidden {
            let size = subview.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let height = y + rowHeight
        if abs(height - contentHeight) > 0.5 {
            contentHeight = height
            invalidateIntrinsicContentSize()
        }
    }
}

/// 番組名の中の [字] [再] などの印を、Web 版と同じピンク地の印に描き分けた
/// 属性付き文字列を作る (Web 版 ProgramUtils.decorateProgramInfo の写し)。
/// 対象の印の一覧と、通常の括弧で囲まれた (二) (字) (再) の扱いも Web 版どおり。
func decoratedProgramTitle(_ title: String, font: UIFont, textColor: UIColor) -> NSAttributedString {
    // 本来 ARIB 外字である記号の一覧 (Web 版の定義そのまま)。
    let marks = ["新", "終", "再", "交", "映", "手", "声", "多", "副", "字", "文", "CC", "OP", "二", "S", "B", "SS", "無", "無料",
                 "C", "S1", "S2", "S3", "MV", "双", "デ", "D", "N", "W", "P", "H", "HV", "SD", "天", "解", "料", "前", "後初", "生", "販", "吹", "PPV",
                 "演", "移", "他", "収", "・", "英", "韓", "中", "字/日", "字/日英", "3D", "2ndScr", "2K", "4K", "8K", "5.1", "7.1", "22.2", "60P", "120P", "d", "HC", "HDR", "Hi-Res", "Lossless", "SHV", "UHD", "VOD", "配", "初"]
    let alternation = marks.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    let pattern = "\\[(\(alternation))\\]|\\((二|字|再)\\)"
    let baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return NSAttributedString(string: title, attributes: baseAttributes)
    }
    let result = NSMutableAttributedString()
    let fullRange = NSRange(title.startIndex..., in: title)
    var cursor = title.startIndex
    for match in regex.matches(in: title, range: fullRange) {
        guard let matchRange = Range(match.range, in: title),
              let markRange = Range(match.range(at: 1), in: title) ?? Range(match.range(at: 2), in: title)
        else { continue }
        if cursor < matchRange.lowerBound {
            result.append(NSAttributedString(string: String(title[cursor..<matchRange.lowerBound]), attributes: baseAttributes))
        }
        // 印は画像として差し込む (ピンク地に文字色の字、角丸 4pt、左右に 2.5pt の余白)。
        let mark = String(title[markRange])
        let image = programMarkChipImage(mark, baseFont: font)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - image.size.height) / 2,
            width: image.size.width,
            height: image.size.height
        )
        result.append(NSAttributedString(attachment: attachment))
        cursor = matchRange.upperBound
    }
    if cursor < title.endIndex {
        result.append(NSAttributedString(string: String(title[cursor...]), attributes: baseAttributes))
    }
    return result
}

/// 印1つ分の画像を描く。Web 版の .decorate-symbol と同じ見た目:
/// 地は primary (#E64F97)、字は text (#FFEAEA)、字の大きさは題名の 0.94 倍、
/// 内側の余白は左右 3pt、角丸 4pt、両脇に 2.5pt の透明な余白。
private func programMarkChipImage(_ mark: String, baseFont: UIFont) -> UIImage {
    let label = BadgeLabel()
    label.text = mark
    // baseFont は呼び出し側の題名のフォント (表示の大きさは反映済み) なので、
    // ここで倍率を掛け直すと二重に効いてしまう。そのまま使う。
    label.font = .systemFont(ofSize: baseFont.pointSize * 0.94, weight: .bold)
    label.textColor = AppPalette.text
    label.backgroundColor = AppPalette.accent
    label.layer.cornerRadius = 4
    label.clipsToBounds = true
    label.textInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
    label.sizeToFit()
    let sideMargin: CGFloat = 2.5
    let size = CGSize(width: label.bounds.width + sideMargin * 2, height: label.bounds.height)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        label.frame = CGRect(x: sideMargin, y: 0, width: label.bounds.width, height: label.bounds.height)
        if let context = UIGraphicsGetCurrentContext() {
            label.layer.render(in: context)
        }
    }
}

/// 録画番組の再生画面。HLS を再生する。
/// 通常(H.264)はAVPlayer。HEVCは認証付きprobeでEXT-X-MAPを確認できれば
/// fMP4/AVPlayerを試し、未対応または開始前の再試行失敗時は従来のVLCKitを使う。
/// 既存サーバーは録画の映像を
/// MPEG-TS の分割ファイルで送っており、AVPlayer は HEVC を MP4 形式の
/// 分割でしか映像として出せない (TS に入った HEVC は音だけ出て映像が
/// 出ない) ため。VLCKit は TS に入った HEVC を読み解ける。
/// CM チャプター移動、前後スキップ (秒数は設定値)、シークバー、画質切り替え、
/// 音声のみ切り替え、再生速度の切り替え、CM自動スキップ、前回見た位置からの
/// 再開 (巻き戻し付き) を持つ (どちらの仕組みでも同じに効かせる)。
final class PlayerViewController: UIViewController {
    private let program: RecordedProgram

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    /// AVPlayer 経路で、読み込みの失敗を拾うための観測。
    private var itemStatusObservation: NSKeyValueObservation?
#if canImport(VLCKit)
    /// H.265 / HEVC の画質のときに使う VLCKit のプレイヤー。
    /// H.264 のときは AVPlayer を使うので、こちらは nil のまま。
    private var vlcPlayer: VLCMediaPlayer?
    /// VLCKit 経路で進み具合を 0.5 秒ごとに見るためのタイマー
    /// (AVPlayer の定期観測にあたる)。
    private var vlcTimeTimer: Timer?
    /// VLCKit 経路で、開始位置の控え。開始位置はメディアの指定
    /// (":start-time") で最初から渡すのが本筋で、こちらは、その指定が
    /// 効かずに先頭から始まってしまったときの受け皿 (再生開始の合図で、
    /// 現在位置が控えと大きく違う場合だけ移る)。
    private var vlcPendingStartPosition: Double?
    /// VLCKit 経路で、再生が始まる前に届いた開始位置の補正の保留分。
    /// 準備が終わる前に位置を送っても再生部品に届かないことがある
    /// ため、再生が始まった合図で効かせる。手動の移動・画質の
    /// 切り替え・後片付けのときは破棄する。
    private var vlcPendingStartCorrection: Double?
    /// VLCKit 経路で、移動 (シーク) の直前に再生していたことを示す印。
    /// 移動先で止まった状態になってしまった場合に、状態の知らせ側で
    /// 拾って再生を再開するために使う。利用者が自分で止めたときは
    /// 印を消すため、勝手に再開することはない。
    private var vlcResumeAfterSeek = false
    /// VLCKit 経路で、開始の見張り用タイマー。一定時間たっても再生が
    /// 始まらなければ、真っ黒のまま無言にせず、その旨を表示する。
    private var vlcStartWatchdog: Timer?
    /// VLCKit 経路で、一度でも再生が始まったかどうか (見張りの判定用)。
    private var vlcDidStartPlaying = false
#endif
    /// 録画再生で VLCKit を使うときの受け取りの溜め (ミリ秒)。
    /// 生放送 (低遅延オン 1000 / オフ 4000ms) と違い、録画は放送との
    /// 遅れが問題にならず、先読みを厚くして止まりにくくする方が大事。
    /// 以前は 30 秒分にしていたが、VLC ではこの値が開始時の貯め待ちの
    /// 長さも決めるため、出だしと移動 (シーク) のたびに待ちが目立って
    /// いた。標準の仕組み (AVPlayer) 側は届いた分から再生を始める形に
    /// したため、こちらも見直して 10 秒分にした。HLS の分割ファイルは
    /// 数秒単位で届くため、10 秒分は分割ファイル 2 個弱の余裕になり、
    /// 外回線の多少の揺れでは止まりにくい。代わりに、回線が大きく
    /// 揺れたときは以前より止まりやすくなる (止まりが目立つようなら、
    /// 15 秒分へ戻す余地がある)。
    private static let vlcRecordedNetworkCaching = 10000
    private var keepAliveTimer: Timer?
    /// セッション維持の合図の、最初の1回用のタイマー。開始直後はまだ
    /// セッションができていない (合図が無効になる) ため、少し置いて
    /// から送り、その後は繰り返し用に切り替える。
    private var keepAliveFirstTimer: Timer?
    /// 合図の最初の遅れと繰り返しの間隔、失敗が何回続いたらセッションが
    /// 切れたとみなすか。間隔はサーバー側の持ち時間 (約10秒) の半分に
    /// し、1回の失敗や遅れがあっても次が持ち時間のうちに届くように
    /// している。
    private static let keepAliveFirstDelay: TimeInterval = 3
    private static let keepAliveInterval: TimeInterval = 5
    private struct KeepAliveContext: Equatable {
        let start: Int
        let sessionID: String
        let quality: String
        let profile: PlaybackProfile
        let authentication: WatchedHistoryStore.Context
    }
    private var keepAliveState = PlaybackKeepAliveState<KeepAliveContext>()
    private var keepAliveContext: KeepAliveContext {
        KeepAliveContext(start: startPlaybackCount, sessionID: sessionID, quality: quality,
                         profile: profile, authentication: .current)
    }
    /// 利用者の意図として再生中かどうか (再生・停止の集約口で更新する)。
    /// セッションを作り直すときに、止めていたものを勝手に再生し
    /// 始めないために使う。
    private var playbackIntentPlaying = true
    /// この開始で、再生が実際に始まったかどうか。始まる前の移動
    /// (シーク) は再生部品へ送っても届かないため、その判定に使う。
    private var playbackDidStart = false
    /// 再生が始まる前に利用者が指定した移動先。控えておき、再生が
    /// 始まったときに反映する。開始位置の復元 (受け皿・補正) より
    /// 優先する。
    private var pendingPlaybackSeek = PendingPlaybackSeek()
    private var playbackReadyForSeek = false
    private var seekDisplay = SeekDisplayState()
    private var sessionID = UUID().uuidString
    /// 再生を始めるときに決めた回線の区分。この再生の間は固定する
    /// (途中で回線が変わっても画質は変えない)。ただし、再生画面での
    /// 手動切り替え (モバイル回線向け画質) のときだけ、その場で変える。
    private var profile: PlaybackProfile
    private var quality: String
    /// 画質の切り替えが完了した時点で設定へ書き戻すための控え。
    /// 切り替え開始時点でも書き戻すが (本番 Web 版の追加の直しに合わせた)、
    /// 完了時点の書き戻しはこの控えを使って、再生が再開したタイミングで行う。
    private var pendingQualityWriteBack: String?
    private var qualityBeforeAudioOnly: String?
    private var audioOnly = false
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    /// CM自動スキップの判定用。前回の時刻チェックで見た再生位置。
    /// 「CM 区間の開始を跨いだ瞬間」だけを拾うため、シークしたときは
    /// 移動先の位置で上書きする (区間の真ん中へ移った直後は発動させない)。
    private var lastObservedPosition: Double = 0
    /// 視聴進捗の報告用。サーバーへ報告できた位置と、最後に報告を
    /// 試みた位置・時刻を分けて持つ。失敗した報告を「報告済み」に
    /// してしまうと、その位置が二度と送られなくなるため。
    private var lastReportedPosition: Double = -1
    private var lastReportAttemptPosition: Double = -1
    private var lastReportedAt: TimeInterval = 0
    /// まだ送れていない到達最大位置。報告が失敗した位置はここに残し、
    /// 巻き戻して見直しても、到達した最大位置が後の報告や画面を
    /// 離れるときの最後の報告で送られるようにする。
    private var maxUnreportedPosition: Double = -1
    /// 共通の視聴履歴 (利用者設定の watched_history) への書き戻し用。
    /// 再生を始めた時刻 (履歴への登録は30秒後、Web 版と同じ)、
    /// 最後に書き戻した時刻、書き戻し中かどうか、登録用のタイマー。
    private var playbackOpenedAt: TimeInterval = 0
    private var lastHistorySyncAt: TimeInterval = 0
    private var historySyncInFlight = false
    private var historyRegistrationTimer: Timer?
    /// 視聴履歴の書き戻しの世代。画面を離れるときの最後の保存で進め、
    /// まだ送られていない古い定期保存を無効にする (古い位置が最後の
    /// 位置を上書きしないため)。
    private var historySyncEpoch = 0
    /// 録画中かどうか (開いた時点の値から、録画の完了に合わせて更新する)。
    /// 番組の控えは開いた時点のまま変わらないため、履歴の書き戻しや
    /// ボタンの表示はこちらで判定する。
    private var recordingInProgress = false
    /// 再生の世代。画面を離れるたびに進め、離れる前に始めた非同期の
    /// 処理が、戻ってきた後や別の再生へ影響しないようにする。
    private var playbackGeneration = 0
    /// 「再生が終わった」出来事の通し番号。終わった直後に次の話を
    /// 取りに行っている間、利用者が巻き戻して再生を再開したり、
    /// 別の話へ移ったりしたら、その出来事は古くなる。取りに行く前に
    /// 控えた番号と応答時の番号が食い違っていたら、自動再生の
    /// 数え下げは始めない。
    private var playbackEndEventID = 0
    /// 前の話・次の話への移動が進んでいるかどうか (連打で複数の
    /// 再生画面が積まれないようにする)。
    private var isNavigatingToEpisode = false
    /// 画面を離れる処理が済んだかどうか。開始位置の取得 (非同期) が
    /// 離れた後に返ってきた場合、再生を始め直さないための印。
    private var didLeaveScreen = false
    /// 再生開始の通し番号。開始のたびに進める。並行して確かめている
    /// 続きの位置が返ってきたとき、別の開始に切り替わっていたら
    /// その確認は古いものとして移らないために使う。
    private var startPlaybackCount = 0
    /// 中継の用意ができずに開始できなかったときの開始位置の控え。
    /// 再生ボタンで始め直すときに使う (開始できたら消す)。
    private var pendingRelayRetryPosition: Double?
    private var playbackStart = PlaybackStartState<WatchedHistoryStore.Context>()
    /// 開始の用意を待っている間の知らせ文。
    private static let startLoadingMessage = "読み込んでいます…"
    private typealias PlaybackRequest = PlaybackStartState<WatchedHistoryStore.Context>.Request
    private struct FMP4StartContext {
        let request: PlaybackRequest
        let fmp4URL: URL
        let fallbackURL: URL
        var state: FMP4PlaybackState
    }
    private var fmp4StartContext: FMP4StartContext?
    private var playlistProbeTask: Task<Void, Never>?
    private var fmp4RetryWorkItem: DispatchWorkItem?
    private var fmp4StartWatchdog: Timer?
    private var fmp4WatchdogGeneration: UInt64 = 0
    private var fmp4OwnerVisible = false
    private var fmp4ApplicationActive = true
    private var routeResolutionPending = false
    private static let fmp4RetryMessage = "再生の開始に失敗しました。少し待ってからもう一度試します。"
    /// 開始の後に、利用者が自分で位置を動かしたかどうか。動かして
    /// いたら、遅れて返ってきた続きの位置の確認では移らない。
    private var userSeekedSinceStart = false
    /// 画面を離れるときに控えた再生位置と、再生中だったかどうか。
    /// 次の話などへ進んでから戻ってきたとき、片付け済みの再生を
    /// 同じ位置から作り直すために使う。
    private var positionBeforeLeave: Double = 0
    private var wasPlayingBeforeLeave = true

    private let videoContainer = UIView()
    // 全画面は同じ所有元の制約だけを切り替え、再生・字幕・実況の時計を共有する。
    private var isFullscreen = false
    private var normalVideoConstraints: [NSLayoutConstraint] = []
    private var fullscreenVideoConstraints: [NSLayoutConstraint] = []
    /// 情報欄は通常映像の下端を基準に保ち、全画面の映像下端で負の高さにしない。
    private let normalVideoLayoutGuide = UILayoutGuide()
    private weak var fullscreenWindowScene: UIWindowScene?
    private var normalSeekConstraints: [NSLayoutConstraint] = []
    private var fullscreenSeekConstraints: [NSLayoutConstraint] = []
    /// 映像の描画先。操作類の重ね物と兄弟にし、タップの受け口を映像だけに分ける。
    private let surfaceView = UIView()
    /// 映像の下辺に重ねる操作帯 (グラデーション + 操作類)。
    private let bottomGradient = GradientView(direction: .bottom)
    /// 操作類の入れ物。グラデーションと一緒に透明度で出し入れする。
    private let controlsContainer = UIView()
    /// 映像の真ん中に置く操作の並び (前の場面へ・少し戻る・再生/一時停止・
    /// 少し進む・次の場面へ)。本家 Web 版の中央の並びと同じ置き場所で、
    /// 下の帯とは別に、操作帯と一緒に透明度で出し入れする。
    private let centerTransport = UIStackView()
    // 操作ボタンはすべて共通部品の波紋つきボタン (押したときの反応)。
    private let playPauseButton = RippleButton()
    private let skipBackButton = RippleButton()
    private let skipForwardButton = RippleButton()
    private let prevChapterButton = RippleButton()
    private let nextChapterButton = RippleButton()
    private let seekSlider = PlayerSeekSlider(frame: .zero)
    private let bandView = CMSectionBandView()
    /// コメント (ニコニコ実況の過去ログ) を映像の上に流す重ね物。
    private let commentOverlay = JikkyoCommentOverlayView()
    /// コメント表示のオン/オフ (操作帯の中。Web 版プレイヤーの操作帯にある
    /// コメント表示の切り替えと同じ置き場所)。
    private let commentButton = RippleButton()
    /// 取得できたコメントの件数。取れなかったときは nil で、
    /// 情報欄の「コメント数:」の行は出さない。
    private var commentCount: Int?
    // MARK: 字幕
    /// 字幕の本体 (包みの蓄え・文字化・描画)。包みの入り口は経路ごとに
    /// 違うが、蓄えた後の扱いは共通 (AribCaption.swift)。
    private let captionEngine = CaptionDisplayEngine()
    private let captionSeekCoordinator = CaptionSeekCoordinator()
    /// 字幕の重ね物。映像の枠 (surfaceView) の中に入れる。
    /// 全画面でも同じ枠のまま、映像の拡大に追随する。
    private let captionOverlayView = CaptionOverlayView()
    /// 字幕表示のオン/オフ (操作帯の中。Web 版プレイヤーの操作帯にある
    /// 字幕の切り替えと同じ置き場所で、コメント切り替えの隣に置く)。
    private let captionButton = RippleButton()
    /// AVPlayer 経路で、字幕データ (時刻つきデータ) の受け取り口。
    private var captionMetadataOutput: AVPlayerItemMetadataOutput?
    // MARK: シーク中のプレビュー (Web 版プレイヤーのシークバー上のプレビューと同じ仕組み)
    /// サーバーが用意するタイル画像 (サムネイルを並べた1枚絵) を切り出して出す。
    /// 映像の再生の仕組み (AVPlayer / VLCKit) には寄らないため、どちらの経路でも
    /// 同じように出せる。絵はシークを始めたときに初めて取りに行き、
    /// 切り出しはタイルが切り替わったときだけ行う (再生そのものには触れない)。
    private let seekPreviewView = UIView()
    private let seekPreviewImageView = UIImageView()
    private let seekPreviewTimeLabel = UILabel()
    /// プレビューの横位置 (映像の枠の中央からのずれ)。指の位置に合わせて動かす。
    private var seekPreviewCenterConstraint: NSLayoutConstraint?
    /// タイル画像の読み込み状態。
    private enum SpriteLoadState {
        case idle, loading, loaded, failed
    }
    private var spriteLoadState: SpriteLoadState = .idle
    /// 読み込んだタイル画像一式。切り出しの材料に CGImage も持つ。
    private var spriteImage: UIImage?
    private var spriteCGImage: CGImage?
    /// いまプレビューに出しているタイルの番号。切り替わったときだけ切り出し直す。
    private var seekPreviewTileIndex = -1
    // MARK: 情報欄のタブとコメント一覧 (Web 版パネルの下部ナビと同じ考え方)
    /// 情報欄のタブ (番組情報 / コメント)。Web 版パネル下部のナビにあたる。
    private let infoTabBar = UIView()
    private var commentTabHasBeenShown = false
    private let infoTabButton = RippleButton()
    private let commentTabButton = RippleButton()
    /// タブの中の絵と文字。選択状態に合わせて色を変えるため控えを持つ。
    private let infoTabIconView = UIImageView()
    private let infoTabTitleLabel = UILabel()
    private let commentTabIconView = UIImageView()
    private let commentTabTitleLabel = UILabel()
    /// 選択中のタブ。開いたときの既定は、設定の「全般」にある
    /// 「ビデオをみるときにデフォルトで表示されるパネルのタブ」の値。
    private enum InfoTab {
        case info, comment
    }
    private var selectedInfoTab: InfoTab =
        SyncedSettingsStore.shared.current.videoPanelActiveTab == "Comment" ? .comment : .info
    /// コメント一覧の表。情報欄のスクロールと場所を取り合って切り替える。
    private let commentTableView = UITableView(frame: .zero, style: .plain)
    private let commentEmptyLabel = UILabel()
    /// 取得した過去ログコメント一式 (時刻の昇順)。流れる表示と一覧で共用する。
    private var jikkyoComments: [JikkyoComment] = []
    /// コメント取得の状態。一覧の空表示の文を出し分けるために持つ。
    private enum JikkyoLoadState {
        case loading
        case loaded
        case failed(String)
    }
    private var jikkyoLoadState: JikkyoLoadState = .loading
    /// 一覧が追随しているコメントの番号 (再生位置を過ぎた最後のコメント)。
    private var commentFollowIndex = -1
    /// 利用者が一覧を手でスクロールした最後の時刻。しばらくは追随を止める
    /// (Web 版も手動スクロール中は自動で動かさない)。
    private var commentListManualScrollAt: Date?
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    /// 見出し帯の右端に出す時計 (Web 版の上部帯の時計に相当)。
    /// 設定「録画番組の再生中に元の放送時刻を表示する」が入っているときは、
    /// 今の時刻ではなく、録画の開始時刻に再生位置を足した時刻を出す。
    private let headerClockLabel = UILabel()
    private let headerClockIconView = UIImageView()
    private var headerClockTimer: Timer?
    /// 映像の下の情報欄 (Web 版パネルに相当)。中身が長いときはスクロールする。
    private let scrollView = UIScrollView()
    private let infoTitleLabel = UILabel()
    private let logoImageView = UIImageView()
    private let channelLabel = UILabel()
    private let programTimeLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let statusLabel = UILabel()
    /// 操作の小さなボタン群 (Web 版パネルのボタンの形)。
    /// 波紋つきボタン (共通部品) で、押したときの反応もそろえる。
    private let qualityButton = RippleButton()
    private let profileButton = RippleButton()
    private let rateButton = RippleButton()
    private let audioOnlyButton = RippleButton()
    private let fullscreenButton = RippleButton()
    private let settingsButton = RippleButton()
    private let pipButton = RippleButton()
    private let captureButton = RippleButton()
    private let captureController = VideoCaptureController()
    private var pipController: PlaybackPiPController?
    private var vlcStateObserver: VLCStateObserver?
    private weak var playbackNavigation: UINavigationController?
    private weak var playbackTabs: MainTabBarController?
    private var playbackTabIndex = 1
    private var pipWasActive = false
    private var lastVLCPosition: Double = 0
    private let overlayTopGradient = GradientView(direction: .top)
    private lazy var overlayHeader = PlayerOverlayHeader(title: program.title) { [weak self] in
        guard let self else { return }
        if self.isFullscreen { self.setFullscreen(false) }
        else { self.navigationController?.popViewController(animated: true) }
    }
    private let protectButton = RippleButton()
    /// マイリストへの追加・削除ボタン (両版)。状態で文面と印を変える。
    private let mylistButton = RippleButton()
    private let watchedButton = RippleButton()
    private let sleepTimerButton = RippleButton()
    // MARK: 拡張版の再生画面まわりの機能 (改造サーバー前提)
    /// 前の話・次の話ボタン。前後が有るかどうかは、開いたあとに単体取得で
    /// 確かめてから出し分ける (一覧の応答には前後の情報が無いため)。
    private let prevEpisodeButton = RippleButton()
    private let nextEpisodeButton = RippleButton()
    /// 場面一覧を開くボタン。場面の画像の材料が無い録画では出さない。
    private let sceneListButton = RippleButton()
    /// いまの再生位置にしおりを足すボタン。
    private let addBookmarkButton = RippleButton()
    /// ダイジェスト再生の切り替え。見どころ区間が取れたときだけ出す。
    private let digestButton = RippleButton()
    /// コメント検索を開くボタン。
    private let commentSearchButton = RippleButton()
    /// 次回の放送を探して予約するボタン。
    private let nextReserveButton = RippleButton()
    /// シリーズ予約 (キーワード自動予約の条件) を作るボタン。
    private let seriesReserveButton = RippleButton()
    /// 次回予約・シリーズ予約の実行中フラグ (二重実行の防止)。
    private var isReservingNext = false
    private var isCreatingSeries = false
    /// ジャンルの印の並び (Web 版パネルの genre-container に相当)。材料が無いときは隠す。
    private let genreFlowView = ChipFlowView()
    /// ボタン群の並び (Web 版パネルのボタンの流し並べに相当)。
    private let buttonsFlowView = ChipFlowView()
    /// 詳細情報の節の並び (Web 版パネルの program-detail-container に相当)。
    /// 材料が無いときは隠す。
    private let detailStack = UIStackView()
    /// おやすみタイマーの状態 (Web 版 SleepTimerManager の写し)。
    /// 押すたびに オフ → 15分 → 30分 → 60分 → 番組の終わりで停止 → オフ と巡る。
    private enum SleepTimerMode {
        case off
        case minutes
        case end
    }
    /// 巡回の現在位置 (["off", "15", "30", "60", "end"] の添字)。
    private var sleepTimerModeIndex = 0
    private var sleepTimerMode: SleepTimerMode = .off
    /// 分モードの残り秒数。分モードでないときは nil。
    private var sleepTimerRemainingSeconds: Int?
    /// 分モードの残り時間を1秒ごとに減らすタイマー。
    private var sleepTimerTicker: Timer?
    /// 保護の現在状態。切り替えたら手元の表示も追いつかせるため、番組データとは別に持つ。
    private lazy var currentProtected: Bool = program.isProtected
    private let messageLabel = NoticeLabel()
    private var videoHeightConstraint: NSLayoutConstraint?
    /// 操作帯の出し入れ (Web 版と同じく、再生中はしばらく触らなければ消える)。
    private var controlsVisible = true
    private var hideTimer: Timer?
    /// 操作帯の並び (映像の下辺)。盛り上がりの帯を差し込むために控えを持つ。
    private let controlsStackView = UIStackView()
    /// 操作帯の高さの決まり。盛り上がりの帯を差し込んだときに広げる。
    private var controlsHeightConstraint: NSLayoutConstraint?
    // MARK: 拡張版の再生画面まわりの状態
    /// 単体取得で分かった前の話・次の話の録画 ID。無い間は nil。
    private var previousEpisodeID: Int?
    private var nextEpisodeID: Int?
    /// 実況コメントから計算した盛り上がりの密度と見どころ区間。
    private var excitementDensity: CommentDensity?
    private var highlightSegments: [HighlightSegment] = []
    /// シークバーの上に重ねる盛り上がりの波形の帯。
    /// 材料が揃った時点で操作帯の並びへ差し込む。
    private let excitementStrip = ExcitementStripView()
    /// ダイジェスト再生 (見どころ区間だけを続けて再生) が入っているか。
    private var digestPlaybackEnabled = false
    /// ダイジェスト再生の見張りの間引き用 (Web 版と同じ 300ミリ秒間隔)。
    private var lastDigestCheckAt: TimeInterval = 0
    /// 映像の上に短く出す知らせ (Web 版の画面下のお知らせと同じ役割)。
    /// 情報欄の文 (messageLabel) は映像の上では見えないため、再生中の
    /// 知らせはこちらに出す。
    private let playerNoticeView = UIView()
    private let playerNoticeLabel = UILabel()
    private var playerNoticeDismissWork: DispatchWorkItem?
    /// ハイライト横断再生の印 (映像の左上に出す「ハイライト再生中 n/m」
    /// と取り消しのボタン) と、その状態。
    private let reelBadgeView = UIView()
    private let reelBadgeLabel = UILabel()
    /// この再生画面がハイライト横断再生の対象になっているか。
    private var reelActive = false
    /// 横断再生で別の録画を取りに行っている最中かどうか。見張りが
    /// 0.5秒ごとに呼ばれるため、印が無いと取り込みが終わるまでの間に
    /// 同じ区間の取得が重なって走ってしまう。
    private var reelFetchInFlight = false
    /// 横断再生の見張りの間引き用 (Web 版と同じ 500ミリ秒間隔)。
    private var lastReelCheckAt: TimeInterval = 0
    /// 次の話の自動再生の数え下げカードと、その材料。
    private let autoplayCard = UIView()
    private let autoplayTitleLabel = UILabel()
    private let autoplayCountdownLabel = UILabel()
    private var autoplayTimer: Timer?
    private var autoplayRemainingSeconds = 0
    private var autoplayNextProgram: RecordedProgram?
    /// 長押しの高速シーク (送り・戻し)。
    private let fastSeekBackController = FastSeekController(direction: -1)
    private let fastSeekForwardController = FastSeekController(direction: 1)
    /// 高速シーク中の消音の持ち主 (送り・戻しで共有し、同時に
    /// 長押ししても消音が残らないようにする)。
    private let fastSeekMuteKeeper = FastSeekMuteKeeper()
    /// VLCKit 経路で高速シークのために音を消す前の音量の控え。
    private var savedVLCVolume: Int32?
    /// AVPlayer 経路で、再生が終わったことを知るための見張りの控え。
    private var itemEndObserver: NSObjectProtocol?
    /// 追いかけ再生の先端追従が効いているか (録画中の番組を開いたときだけ)。
    private var chaseFollowActive = false
    /// 先端に追いついた知らせを出したかどうか (出すのは1回だけ)。
    private var chaseEdgeNoticeShown = false
    /// 利用者が自分で止めたかどうか。止めた場合は先端へ戻して再開しない。
    private var chaseUserPaused = false
    /// 追従の見張りの間引き用 (Web 版と同じ: 確認は2秒ごと、
    /// 録画が続いているかの確認は30秒ごと)。
    private var chaseLastTickAt: TimeInterval = 0
    private var chaseLastStatusPollAt: TimeInterval = 0
    /// 先端で止まったままの検出用 (位置の控えと、止まり始めた時刻)。
    private var chaseStallPosition: Double = -1
    private var chaseStallSince: TimeInterval = 0
    /// 先端への復帰が続けて起きすぎないための間引き用。
    private var chaseLastRecoveryAt: TimeInterval = 0

    init(program: RecordedProgram) {
        self.program = program
        self.recordingInProgress = program.isRecording
        // 回線の区分はこの時点で決める。手動切り替えの記憶があればそれを
        // 優先し、無ければ現在の回線から決める (Web 版の優先順位と同じ)。
        // 画質はビデオ側のその区分の値から始める。
        let profile = SettingsStore.shared.initialPlaybackProfile()
        self.profile = profile
        self.quality = SettingsStore.shared.streamingQuality(media: .video, profile: profile)
        super.init(nibName: nil, bundle: nil)
        title = program.title
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        PlaybackPiPController.stopCurrentPlayback()
        buildLayout()
        setupHeaderClock()
        fmp4ApplicationActive = UIApplication.shared.applicationState == .active
        // AVの時計が止まっていても、非アクティブ中の時間は開始監視へ加算しない。
        NotificationCenter.default.addObserver(self, selector: #selector(fmp4ApplicationWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(fmp4ApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        captureController.onStateChanged = { [weak self] in self?.updateCaptureControls() }
        captureController.onError = { [weak self] message in self?.showCaptureError(message) }
        captureController.onResult = { [weak self] message in self?.showCaptureError(message) }
        // 情報欄のタブの既定 (設定の「全般」の値) に、表示側も合わせる。
        applyInfoTab(selectedInfoTab)
        // コメントの重ね物に再生位置の読み取り口を渡し、見張りを始める。
        // 過去ログコメントの取得は再生と並行して行う (取れた時点で流れ始める)。
        commentOverlay.positionProvider = { [weak self] in self?.currentPosition() ?? 0 }
        // 表示の濃さ・速さ・字の大きさ・無制限表示は、設定の
        // 「ニコニコ実況」の値を開くときに読み込む。
        commentOverlay.displayOpacity = SettingsStore.shared.commentOpacity
        commentOverlay.unlimited = SettingsStore.shared.showCommentsUnlimited
        commentOverlay.speedRate = SyncedSettingsStore.shared.current.commentSpeedRate
        commentOverlay.fontSizeReference = SyncedSettingsStore.shared.current.commentFontSize
        commentOverlay.start()
        applyCommentDisplayState()
        applyCaptionDisplayState()
        loadJikkyoComments()
        // 再生画面まわりの用意。前の話・次の話 (と自動再生) は改造版
        // サーバーが要るため個別トグルの対象。それ以外 (長押しの
        // 高速シーク、ハイライト横断再生の用意、追いかけ再生の先端
        // 追従) はアプリだけで完結するため常時有効。
        if AppEdition.episodeNavigationEnabled {
            loadEpisodeNeighbors()
        }
        setupFastSeek()
        setupHighlightReel()
        // 録画中の番組は追いかけ再生として、先端追従を効かせる。
        chaseFollowActive = recordingInProgress
        beginNowPlaying()
        beginInitialPlayback()
    }

    /// 最初の再生を始める。
    /// ハイライト横断再生の対象なら、続きの位置ではなく区間の開始
    /// から始める (Web 版と同じ)。
    /// 続きの位置をサーバーへ確かめに行く場合 (同期が効く状態) は、
    /// 確認の通信を待たずに、手元の材料 (一覧の応答に含まれる見た
    /// 割合) で先に再生を始める。プレイリストの取り込みも再生の
    /// 開始と一緒に走り出すため、開始がその分速くなる。確認が
    /// 返ってきたら、位置が大きく違う場合だけ移る。
    /// 録画中の番組 (追いかけ再生) は開始位置の決め方が大事なため、
    /// 今までどおり確かめてから始める。
    private func beginInitialPlayback() {
        if reelActive, let item = HighlightReelStore.shared.currentItem {
            startPlayback(at: item.start)
            return
        }
        guard WatchedHistorySync.isEnabled, !recordingInProgress else {
            resolveInitialStartPosition { [weak self] position in
                guard let self, !self.didLeaveScreen else { return }
                self.startPlayback(at: position)
            }
            return
        }
        let provisionalPosition = initialStartPosition()
        userSeekedSinceStart = false
        startPlayback(at: provisionalPosition)
        let startCount = startPlaybackCount
        Task { [weak self] in
            guard let self else { return }
            guard let saved = await WatchedHistorySync.lastPlaybackPosition(videoID: program.id)
            else { return }
            // 画面を離れた・別の開始に切り替わった・利用者が自分で
            // 位置を動かした場合は、遅れてきた確認では移らない。
            guard !self.didLeaveScreen,
                  self.startPlaybackCount == startCount,
                  !self.userSeekedSinceStart else { return }
            let target = self.startPosition(savedPosition: saved)
            // 仮の開始位置と、確定した開始位置を比べる。今の再生位置と
            // 比べると、応答が遅れた分だけ再生が進んだ状態と比べることに
            // なり、開始位置が同じでも差が開いて、再生が巻き戻ってしまう
            // (通信が遅いだけで起きる)。比べるのは位置同士にする。
            guard abs(target - provisionalPosition) > 5 else { return }
            self.applyStartPositionCorrection(target)
        }
    }

    /// 遅れて確定した開始位置への補正を効かせる。
    /// VLCKit 経路で、再生部品の準備がまだ終わっていないときに位置を
    /// 送っても、部品側に届かず補正が失われることがある。その場合は
    /// 準備が終わるまで補正を保留し、再生が始まった合図で効かせる
    /// (開始位置の指定と、こちらの補正で一元化する)。
    private func applyStartPositionCorrection(_ target: Double) {
#if canImport(VLCKit)
        if vlcPlayer != nil, !vlcDidStartPlaying {
            vlcPendingStartCorrection = target
            return
        }
#endif
        seek(to: target)
    }

    /// 再生を始める位置を決める。
    /// 同期が効く状態 (ログイン中かつ「設定をデバイス間で同期する」がオン) で、
    /// Web 版と共通の視聴履歴に前回位置が残っていれば、それを元にする
    /// (使う直前にサーバーから取り直す)。履歴が無い・位置が取れない・
    /// 取得に失敗した場合は、今までどおりサーバー側の視聴状態を元にする。
    private func resolveInitialStartPosition(completion: @escaping (Double) -> Void) {
        guard WatchedHistorySync.isEnabled else {
            completion(initialStartPosition())
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if let saved = await WatchedHistorySync.lastPlaybackPosition(videoID: program.id) {
                completion(startPosition(savedPosition: saved))
            } else {
                completion(initialStartPosition())
            }
        }
    }

    /// 今までの元データ (サーバーが一元管理する視聴状態) からの開始位置。
    /// 一覧の応答に含まれる見た割合 × 尺 が「到達した最大位置」にあたる
    /// (ログイン不要で取れる)。
    private func initialStartPosition() -> Double {
        guard let ratio = program.watched_ratio, ratio > 0 else { return 0 }
        return startPosition(savedPosition: ratio * program.duration)
    }

    /// 保存された前回位置から、再開する位置を計算する。
    /// 前回見た位置から、設定の秒数だけ巻き戻して始める (改造側の仕様確認済み)。
    /// - 下限は録画開始マージン + 2秒 (Web 版が履歴なしのときに始める位置と同じ)。
    /// - 最後まで見終わっている (残り10秒以内) ものと、録画中のものは先頭から。
    private func startPosition(savedPosition saved: Double) -> Double {
        guard !program.isRecording else { return 0 }
        let floor = program.recordingStartMargin + 2
        guard saved > floor, saved < program.duration - 10 else { return 0 }
        let target = max(saved - Double(SettingsStore.shared.resumeRewindSeconds), floor)
        if target > floor {
            messageLabel.text = "前回視聴した続きから再生します。"
        }
        return target
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        isFullscreen ? .landscape : super.supportedInterfaceOrientations
    }

    override var prefersStatusBarHidden: Bool {
        isFullscreen && !controlsVisible
    }

    override var prefersHomeIndicatorAutoHidden: Bool { isFullscreen }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        playbackNavigation = navigationController
        playbackTabs = mainTabBarController
        playbackTabIndex = playbackTabs?.selectedIndex ?? playbackTabIndex
        // 戻る・題名・時計は映像へ重ね、独立した大型ナビゲーション帯を使わない。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 別の画面から戻ってきたとき用に、消えるタイマーを仕掛け直す。
        if hasActiveEngine {
            scheduleHideControls()
        }
        // マイリストの登録状態をサーバー側の最新に追いつかせる
        // (同期が効いていないときは何もしない)。
        if SyncedSettingsStore.isSyncEnabled {
            Task { [weak self] in
                guard let self else { return }
                if await SyncedSettingsStore.shared.refreshFromServer() {
                    self.updateMylistButtonTitle()
                }
            }
        }
        // ハイライト横断再生の対象だった画面に戻ってきたとき、順番が
        // すでに先の録画へ進んでいたら、この画面は対象から外れたもの
        // として扱い、横断再生自体も取り消す (Web 版で別の録画を
        // 開いたときにキューが消えるのと同じ扱い)。
        if reelActive, HighlightReelStore.shared.currentItem?.videoID != program.id {
            HighlightReelStore.shared.clear()
            reelActive = false
            updateReelBadge()
        }
        // 見出し帯の時計を毎秒進める。
        headerClockTimer?.invalidate()
        headerClockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateHeaderClock()
        }
        updateHeaderClock()
        // 次の話など別の画面へ進んで戻ってきたときは、離れるときに
        // 片付けた再生を作り直す (この画面が閉じられた場合はここへは
        // 来ない)。同じVC内の全画面切替では離れる通知自体が発生しない。
        if didLeaveScreen, !hasActiveEngine {
            didLeaveScreen = false
            resumePlaybackAfterReturn()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fmp4OwnerVisible = true
        refreshFMP4StartWatchdog()
        resumeDeferredSessionRecovery()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fmp4OwnerVisible = false
        refreshFMP4StartWatchdog()
        if isFullscreen { fullscreenWindowScene = view.window?.windowScene }
        // 映像内ヘッダーはこの画面だけ。標準バーを使う遷移先へ非表示状態を持ち込まない。
        if presentedViewController == nil, navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
        // ナビゲーションバーの見た目を標準へ戻す (この画面の間だけ変えているため)。
        let bar = navigationController?.navigationBar
        bar?.tintColor = nil
        bar?.titleTextAttributes = nil
        hideTimer?.invalidate()
        hideTimer = nil
        headerClockTimer?.invalidate()
        headerClockTimer = nil
        // 再生の後片付けは、離れることが確定してから viewDidDisappear で
        // 行う (下のコメント参照)。ここでは切り替わりの先頭で固まらない
        // よう、軽い片付けだけ行う。
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // PiPの所有元が一覧へ戻る場合も、制約と情報欄を先に通常状態へ戻す。
        if presentedViewController == nil || isBeingDismissed {
            setFullscreen(false, restoringOn: fullscreenWindowScene)
        }
        if pipController?.isActive == true || pipController?.isPending == true { return }
        if presentedViewController is ViewerNavigationController || presentedViewController is UIActivityViewController {
            return
        }
        // 離れることが確定してから後片付けする。以前は viewWillDisappear
        // (切り替わりの先頭) で行っていて、VLC を止める呼び出し (終わる
        // まで処理が返ってこない) が先頭で走るため、スワイプで戻る操作
        // ごと固まっていた。また、スワイプを途中でやめて戻ってきた場合
        // でも片付けが済んでしまい、再生が作り直しになっていた。
        // 確定後なら、やめた場合はここへ来ず、再生は壊れない。
        didLeaveScreen = true
        stopPlayback()
    }

    // MARK: - 画面構成

    private func buildLayout() {
        // MARK: 映像まわり (映像 + 下辺に重ねる操作帯)
        videoContainer.backgroundColor = .black
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoContainer)

        surfaceView.backgroundColor = .black
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(surfaceView)
        // 字幕の重ね物は映像の枠の中に入れる (映像の上・コメントより下)。
        // 全画面でも同じ枠を拡大するため、字幕の付け替えは行わない。
        captionOverlayView.translatesAutoresizingMaskIntoConstraints = false
        // 自動テストから重ね物を見つけるための目印 (見た目・動きは変えない)。
        captionOverlayView.isAccessibilityElement = true
        captionOverlayView.accessibilityIdentifier = "player.captionOverlay"
        captionOverlayView.accessibilityLabel = "字幕表示"
        surfaceView.addSubview(captionOverlayView)
        // コメントの重ね物は映像の上・操作帯の下に置く (操作は受けない)。
        commentOverlay.translatesAutoresizingMaskIntoConstraints = false
        // 自動テストから重ね物を見つけるための目印 (見た目・動きは変えない)。
        commentOverlay.isAccessibilityElement = true
        commentOverlay.accessibilityIdentifier = "player.commentOverlay"
        commentOverlay.accessibilityLabel = "コメント表示"
        videoContainer.addSubview(commentOverlay)
        // 映像をタップしたら操作帯を出し入れする (Web 版と同じ作り)。
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        surfaceView.addGestureRecognizer(tap)

        // 真ん中の並びの絵の大きさは本家の比率に寄せる (再生/一時停止が
        // 一番大きく、少し戻る/少し進む、場面移動の順に小さく)。
        // 当たり判定は絵より広く取る (再生/一時停止56x56、それ以外44x44)。
        configure(playPauseButton, symbol: "play.fill", pointSize: 40, action: #selector(togglePlayPause))
        // スキップ秒数は設定値に合わせ、ボタンの数字もその秒数のものにする
        // (選択肢の秒数はすべて SF Symbols に用意がある)。
        let store = SettingsStore.shared
        configure(skipBackButton, symbol: "gobackward.\(store.seekBackwardSeconds)", pointSize: 30, action: #selector(skipBack))
        configure(skipForwardButton, symbol: "goforward.\(store.seekForwardSeconds)", pointSize: 30, action: #selector(skipForward))
        configure(prevChapterButton, symbol: "backward.end.fill", pointSize: 26, action: #selector(prevChapter))
        configure(nextChapterButton, symbol: "forward.end.fill", pointSize: 26, action: #selector(nextChapter))
        for button in [playPauseButton, skipBackButton, skipForwardButton, prevChapterButton, nextChapterButton] {
            button.tintColor = .white
            let hitSize: CGFloat = button === playPauseButton ? 56 : 44
            button.widthAnchor.constraint(equalToConstant: hitSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: hitSize).isActive = true
        }
        let hasChapters = !program.chapterBoundaries.isEmpty
        prevChapterButton.isEnabled = hasChapters
        nextChapterButton.isEnabled = hasChapters
        prevChapterButton.alpha = hasChapters ? 1 : 0.35
        nextChapterButton.alpha = hasChapters ? 1 : 0.35

        // コメント表示の切り替え (Web 版プレイヤーの操作帯にある切り替えと同じ置き場所)。
        commentButton.addTarget(self, action: #selector(toggleComments), for: .touchUpInside)
        updateCommentButton()

        // 字幕表示の切り替え (Web 版プレイヤーの操作帯にある字幕の切り替えと
        // 同じ置き場所で、コメント切り替えの隣に置く)。
        captionButton.addTarget(self, action: #selector(toggleCaptions), for: .touchUpInside)
        updateCaptionButton()

        seekSlider.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        stylePlayerSeekSlider(seekSlider)

        // シークバーの上に CM 区間の帯を重ねる (帯は操作を受けない)。
        let seekContainer = UIView()
        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        bandView.translatesAutoresizingMaskIntoConstraints = false
        seekContainer.addSubview(seekSlider)
        seekContainer.addSubview(bandView)
        NSLayoutConstraint.activate([
            seekSlider.topAnchor.constraint(equalTo: seekContainer.topAnchor),
            seekSlider.bottomAnchor.constraint(equalTo: seekContainer.bottomAnchor),
            seekSlider.leadingAnchor.constraint(equalTo: seekContainer.leadingAnchor),
            seekSlider.trailingAnchor.constraint(equalTo: seekContainer.trailingAnchor),
            bandView.topAnchor.constraint(equalTo: seekContainer.topAnchor),
            bandView.bottomAnchor.constraint(equalTo: seekContainer.bottomAnchor),
            bandView.leadingAnchor.constraint(equalTo: seekContainer.leadingAnchor),
            bandView.trailingAnchor.constraint(equalTo: seekContainer.trailingAnchor),
        ])
        bandView.slider = seekSlider
        bandView.sections = program.cmSections

        currentTimeLabel.text = "0:00"
        // 自動テストから再生位置を見つけるための目印 (見た目・動きは変えない)。
        currentTimeLabel.accessibilityIdentifier = "player.currentTime"
        durationLabel.text = TimeFormat.hms(program.duration)
        for label in [currentTimeLabel, durationLabel] {
            label.textColor = AppPalette.text
            label.font = .scaledMonospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.65
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        durationLabel.textAlignment = .right

        // 真ん中の並び: [前の場面へ] [少し戻る] [再生/一時停止] [少し進む]
        // [次の場面へ]。本家 Web 版の中央の並びと同じ顔ぶれで、映像の
        // 真ん中に置く (下の帯には置かない)。
        centerTransport.addArrangedSubview(prevChapterButton)
        centerTransport.addArrangedSubview(skipBackButton)
        centerTransport.addArrangedSubview(playPauseButton)
        centerTransport.addArrangedSubview(skipForwardButton)
        centerTransport.addArrangedSubview(nextChapterButton)
        centerTransport.axis = .horizontal
        centerTransport.spacing = 8
        centerTransport.alignment = .center
        centerTransport.translatesAutoresizingMaskIntoConstraints = false

        // 下の帯の並び: [現在時刻] ... [全体の長さ・字幕切り替え・コメント切り替え]。
        styleVideoOverlayButton(commentButton, symbol: "text.bubble", title: "実況コメントの表示を切り替え", adaptive: true)
        updateCommentButton()
        styleVideoOverlayButton(captionButton, symbol: "captions.bubble", title: "字幕の表示を切り替え", adaptive: true)
        updateCaptionButton()
        styleVideoOverlayButton(settingsButton, symbol: "gearshape.fill", title: "プレイヤー設定", adaptive: true)
        styleVideoOverlayButton(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", title: "全画面", adaptive: true)
        settingsButton.addTarget(self, action: #selector(openPlayerSettings), for: .touchUpInside)
        styleVideoOverlayButton(pipButton, symbol: "pip.enter", title: "ピクチャ・イン・ピクチャ", adaptive: true)
        pipButton.isHidden = true
        pipButton.addTarget(self, action: #selector(togglePiP), for: .touchUpInside)
        styleVideoOverlayButton(captureButton, symbol: "camera", title: "キャプチャ", adaptive: true)
        captureButton.addAction(UIAction { [weak self] _ in guard let self else { return }; self.captureVideo(presenter: self) }, for: .touchUpInside)
        let separator = UILabel()
        separator.text = "/"
        separator.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        separator.textColor = .white
        let timeGroup = UIStackView(arrangedSubviews: [currentTimeLabel, separator, durationLabel])
        timeGroup.spacing = 2
        let transportRow = PlayerActionRow(time: timeGroup, buttons: [captureButton, commentButton, captionButton, settingsButton, pipButton, fullscreenButton])

        // 操作帯: グラデーションの上に、操作の並びとシークバーを載せる。
        // シークバーは Web 版スマホ縦と同じく、映像の下辺いっぱいに置く。
        bottomGradient.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(bottomGradient)
        controlsStackView.addArrangedSubview(transportRow)
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 2
        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsStackView)
        controlsContainer.addSubview(seekContainer)
        seekContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(controlsContainer)
        // 真ん中の並びは操作帯より上に置く (映像が低いときでも帯に
        // 触れて押せなくならないように)。
        videoContainer.addSubview(centerTransport)
        overlayTopGradient.translatesAutoresizingMaskIntoConstraints = false
        overlayHeader.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(overlayTopGradient)
        videoContainer.addSubview(overlayHeader)
        // 中央操作は見出しと下部の操作行の間へ置き、タップ領域を重ねない。
        let transportGuide = UILayoutGuide()
        videoContainer.addLayoutGuide(transportGuide)
        NSLayoutConstraint.activate([
            transportGuide.topAnchor.constraint(equalTo: overlayHeader.bottomAnchor),
            transportGuide.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor),
            transportGuide.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            transportGuide.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            overlayTopGradient.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            overlayTopGradient.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            overlayTopGradient.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            overlayTopGradient.heightAnchor.constraint(equalToConstant: 52),
            overlayHeader.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor),
            overlayHeader.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            overlayHeader.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            overlayHeader.heightAnchor.constraint(equalToConstant: 44),
        ])

        // シーク中のプレビュー: 操作帯のすぐ上に、指の位置の時刻の映像と
        // 時刻を出す (Web 版プレイヤーのシークバーのプレビューと同じ出方)。
        // シーク中だけ出し、タイル画像が届くまでは時刻だけ出す。
        seekPreviewView.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        seekPreviewView.layer.cornerRadius = 6
        seekPreviewView.clipsToBounds = true
        seekPreviewView.isHidden = true
        seekPreviewView.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(seekPreviewView)
        seekPreviewImageView.contentMode = .scaleToFill
        seekPreviewImageView.clipsToBounds = true
        seekPreviewImageView.isHidden = true
        seekPreviewTimeLabel.textColor = .white
        seekPreviewTimeLabel.font = .scaledMonospacedDigitSystemFont(ofSize: 11, weight: .regular)
        seekPreviewTimeLabel.textAlignment = .center
        let seekPreviewStack = UIStackView(arrangedSubviews: [seekPreviewImageView, seekPreviewTimeLabel])
        seekPreviewStack.axis = .vertical
        seekPreviewStack.spacing = 3
        seekPreviewStack.isLayoutMarginsRelativeArrangement = true
        seekPreviewStack.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        seekPreviewStack.translatesAutoresizingMaskIntoConstraints = false
        seekPreviewView.addSubview(seekPreviewStack)
        let seekPreviewCenter = seekPreviewView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor)
        seekPreviewCenterConstraint = seekPreviewCenter
        NSLayoutConstraint.activate([
            seekPreviewView.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -8),
            seekPreviewCenter,
            seekPreviewStack.topAnchor.constraint(equalTo: seekPreviewView.topAnchor),
            seekPreviewStack.leadingAnchor.constraint(equalTo: seekPreviewView.leadingAnchor),
            seekPreviewStack.trailingAnchor.constraint(equalTo: seekPreviewView.trailingAnchor),
            seekPreviewStack.bottomAnchor.constraint(equalTo: seekPreviewView.bottomAnchor),
            // タイル1枚は 320x180 (16:9)。表示は幅 128pt に合わせる。
            seekPreviewImageView.widthAnchor.constraint(equalToConstant: 128),
            seekPreviewImageView.heightAnchor.constraint(equalToConstant: 72),
        ])

        // 盛り上がりの波形の帯: 高さだけ決めておき、実況コメントから
        // 密度が計算できた時点で操作帯の並び (シークバーの上) へ差し込む。
        // 密度はシーク中だけ描く。レイアウトから独立したオーバーレイにする。
        excitementStrip.translatesAutoresizingMaskIntoConstraints = false
        excitementStrip.isUserInteractionEnabled = false
        excitementStrip.backgroundColor = .clear
        excitementStrip.isHidden = true
        controlsContainer.insertSubview(excitementStrip, belowSubview: controlsStackView)
        NSLayoutConstraint.activate([
            excitementStrip.heightAnchor.constraint(equalToConstant: 26),
            excitementStrip.leadingAnchor.constraint(equalTo: seekContainer.leadingAnchor),
            excitementStrip.trailingAnchor.constraint(equalTo: seekContainer.trailingAnchor),
            excitementStrip.bottomAnchor.constraint(equalTo: seekContainer.bottomAnchor, constant: -4),
        ])
        excitementStrip.onTapped = { [weak self] ratio in
            guard let self, self.hasActiveEngine else { return }
            self.seek(to: ratio * self.effectiveDuration)
            self.playAtCurrentRate()
            self.setControlsVisible(true)
            self.scheduleHideControls()
        }

        // 映像の上に短く出す知らせ (生放送一覧の知らせと同じ見た目)。
        // 操作帯のすぐ上に置く。
        playerNoticeView.backgroundColor = AppPalette.pressed
        playerNoticeView.layer.cornerRadius = 8
        playerNoticeView.layer.shadowColor = UIColor.black.cgColor
        playerNoticeView.layer.shadowOpacity = 0.4
        playerNoticeView.layer.shadowRadius = 6
        playerNoticeView.layer.shadowOffset = CGSize(width: 0, height: 2)
        playerNoticeView.alpha = 0
        playerNoticeView.isUserInteractionEnabled = false
        playerNoticeView.translatesAutoresizingMaskIntoConstraints = false
        playerNoticeLabel.font = .scaledSystemFont(ofSize: 14)
        playerNoticeLabel.textColor = AppPalette.text
        playerNoticeLabel.numberOfLines = 0
        playerNoticeLabel.translatesAutoresizingMaskIntoConstraints = false
        playerNoticeView.addSubview(playerNoticeLabel)
        videoContainer.addSubview(playerNoticeView)
        NSLayoutConstraint.activate([
            playerNoticeView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            playerNoticeView.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -12),
            playerNoticeView.leadingAnchor.constraint(greaterThanOrEqualTo: videoContainer.leadingAnchor, constant: 24),
            playerNoticeView.trailingAnchor.constraint(lessThanOrEqualTo: videoContainer.trailingAnchor, constant: -24),
            playerNoticeLabel.topAnchor.constraint(equalTo: playerNoticeView.topAnchor, constant: 10),
            playerNoticeLabel.bottomAnchor.constraint(equalTo: playerNoticeView.bottomAnchor, constant: -10),
            playerNoticeLabel.leadingAnchor.constraint(equalTo: playerNoticeView.leadingAnchor, constant: 16),
            playerNoticeLabel.trailingAnchor.constraint(equalTo: playerNoticeView.trailingAnchor, constant: -16),
        ])

        // 次の話の自動再生の数え下げカード (Web 版の右下のカードと同じ置き場所)。
        // 数え下げが始まるまで隠しておく。
        autoplayCard.backgroundColor = AppPalette.panel.withAlphaComponent(0.95)
        autoplayCard.layer.cornerRadius = 8
        autoplayCard.layer.shadowColor = UIColor.black.cgColor
        autoplayCard.layer.shadowOpacity = 0.4
        autoplayCard.layer.shadowRadius = 6
        autoplayCard.layer.shadowOffset = CGSize(width: 0, height: 2)
        autoplayCard.isHidden = true
        autoplayCard.translatesAutoresizingMaskIntoConstraints = false
        let autoplayHeaderLabel = UILabel()
        autoplayHeaderLabel.text = "次の話を再生します"
        autoplayHeaderLabel.font = .scaledSystemFont(ofSize: 12)
        autoplayHeaderLabel.textColor = AppPalette.metaText
        autoplayTitleLabel.font = .scaledSystemFont(ofSize: 14, weight: .bold)
        autoplayTitleLabel.textColor = AppPalette.text
        autoplayTitleLabel.numberOfLines = 1
        autoplayTitleLabel.lineBreakMode = .byTruncatingTail
        autoplayCountdownLabel.font = .scaledSystemFont(ofSize: 13)
        autoplayCountdownLabel.textColor = AppPalette.text
        let autoplayPlayButton = UIButton(type: .system)
        autoplayPlayButton.setTitle("今すぐ再生", for: .normal)
        autoplayPlayButton.setTitleColor(.white, for: .normal)
        autoplayPlayButton.titleLabel?.font = .scaledSystemFont(ofSize: 13, weight: .bold)
        autoplayPlayButton.backgroundColor = AppPalette.accent
        autoplayPlayButton.layer.cornerRadius = 14
        autoplayPlayButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        autoplayPlayButton.addTarget(self, action: #selector(autoplayNowTapped), for: .touchUpInside)
        let autoplayCancelButton = UIButton(type: .system)
        autoplayCancelButton.setTitle("キャンセル", for: .normal)
        autoplayCancelButton.setTitleColor(AppPalette.text, for: .normal)
        autoplayCancelButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        autoplayCancelButton.layer.cornerRadius = 14
        autoplayCancelButton.layer.borderWidth = 1
        autoplayCancelButton.layer.borderColor = AppPalette.metaText.cgColor
        autoplayCancelButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        autoplayCancelButton.addTarget(self, action: #selector(autoplayCancelTapped), for: .touchUpInside)
        let autoplayButtonRow = UIStackView(arrangedSubviews: [
            autoplayCountdownLabel, UIView(), autoplayPlayButton, autoplayCancelButton,
        ])
        autoplayButtonRow.axis = .horizontal
        autoplayButtonRow.spacing = 10
        autoplayButtonRow.alignment = .center
        let autoplayStack = UIStackView(arrangedSubviews: [
            autoplayHeaderLabel, autoplayTitleLabel, autoplayButtonRow,
        ])
        autoplayStack.axis = .vertical
        autoplayStack.spacing = 8
        autoplayStack.isLayoutMarginsRelativeArrangement = true
        autoplayStack.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        autoplayStack.translatesAutoresizingMaskIntoConstraints = false
        autoplayCard.addSubview(autoplayStack)
        videoContainer.addSubview(autoplayCard)
        NSLayoutConstraint.activate([
            autoplayCard.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -16),
            autoplayCard.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -16),
            autoplayCard.leadingAnchor.constraint(greaterThanOrEqualTo: videoContainer.leadingAnchor, constant: 16),
            autoplayCard.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            autoplayStack.topAnchor.constraint(equalTo: autoplayCard.topAnchor),
            autoplayStack.bottomAnchor.constraint(equalTo: autoplayCard.bottomAnchor),
            autoplayStack.leadingAnchor.constraint(equalTo: autoplayCard.leadingAnchor),
            autoplayStack.trailingAnchor.constraint(equalTo: autoplayCard.trailingAnchor),
        ])

        // ハイライト横断再生の印 (Web 版と同じく映像の左上)。
        // 横断再生の対象になっている間だけ出す。
        reelBadgeView.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        reelBadgeView.layer.cornerRadius = 6
        reelBadgeView.isHidden = true
        reelBadgeView.translatesAutoresizingMaskIntoConstraints = false
        reelBadgeLabel.font = .scaledSystemFont(ofSize: 12.5, weight: .semibold)
        reelBadgeLabel.textColor = .white
        reelBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        reelBadgeView.addSubview(reelBadgeLabel)
        let reelCloseButton = UIButton(type: .system)
        reelCloseButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)),
            for: .normal)
        reelCloseButton.tintColor = .white
        reelCloseButton.accessibilityLabel = "ハイライト再生を終了する"
        reelCloseButton.addTarget(self, action: #selector(reelAbortTapped), for: .touchUpInside)
        reelCloseButton.translatesAutoresizingMaskIntoConstraints = false
        reelBadgeView.addSubview(reelCloseButton)
        videoContainer.addSubview(reelBadgeView)
        NSLayoutConstraint.activate([
            reelBadgeView.topAnchor.constraint(equalTo: videoContainer.topAnchor, constant: 12),
            reelBadgeView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: 12),
            reelBadgeLabel.topAnchor.constraint(equalTo: reelBadgeView.topAnchor, constant: 6),
            reelBadgeLabel.bottomAnchor.constraint(equalTo: reelBadgeView.bottomAnchor, constant: -6),
            reelBadgeLabel.leadingAnchor.constraint(equalTo: reelBadgeView.leadingAnchor, constant: 10),
            reelCloseButton.leadingAnchor.constraint(equalTo: reelBadgeLabel.trailingAnchor, constant: 2),
            reelCloseButton.trailingAnchor.constraint(equalTo: reelBadgeView.trailingAnchor, constant: -2),
            reelCloseButton.centerYAnchor.constraint(equalTo: reelBadgeView.centerYAnchor),
            reelCloseButton.widthAnchor.constraint(equalToConstant: 28),
            reelCloseButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // MARK: 映像の下の情報欄 (Web 版パネル)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = AppPalette.background
        view.addSubview(scrollView)

        // 情報欄のタブ (Web 版パネルの下部ナビにあたる)。番組情報とコメント
        // 一覧を切り替える。絵の上に文字の縦並び、選択中は primary の色、
        // という Web 版ナビの形に合わせる (アプリでは置き場所だけ映像の下に移す)。
        infoTabBar.backgroundColor = AppPalette.background
        infoTabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoTabBar)
        buildInfoTabButton(infoTabButton, iconView: infoTabIconView, titleLabel: infoTabTitleLabel,
                            symbol: "info.circle", title: "番組情報", action: #selector(selectInfoTab))
        buildInfoTabButton(commentTabButton, iconView: commentTabIconView, titleLabel: commentTabTitleLabel,
                           symbol: "text.bubble.fill", title: "コメント", action: #selector(selectCommentTab))
        let infoTabStack = UIStackView(arrangedSubviews: [infoTabButton, commentTabButton])
        infoTabStack.axis = .horizontal
        infoTabStack.distribution = .fillEqually
        infoTabStack.translatesAutoresizingMaskIntoConstraints = false
        infoTabBar.addSubview(infoTabStack)
        let infoTabDivider = UIView()
        infoTabDivider.backgroundColor = AppPalette.pressed
        infoTabDivider.translatesAutoresizingMaskIntoConstraints = false
        infoTabBar.addSubview(infoTabDivider)
        NSLayoutConstraint.activate([
            infoTabStack.topAnchor.constraint(equalTo: infoTabBar.topAnchor),
            infoTabStack.leadingAnchor.constraint(equalTo: infoTabBar.leadingAnchor),
            infoTabStack.trailingAnchor.constraint(equalTo: infoTabBar.trailingAnchor),
            infoTabStack.bottomAnchor.constraint(equalTo: infoTabBar.bottomAnchor),
            infoTabDivider.leadingAnchor.constraint(equalTo: infoTabBar.leadingAnchor),
            infoTabDivider.trailingAnchor.constraint(equalTo: infoTabBar.trailingAnchor),
            infoTabDivider.bottomAnchor.constraint(equalTo: infoTabBar.bottomAnchor),
            infoTabDivider.heightAnchor.constraint(equalToConstant: 1),
        ])
        updateInfoTabButtons()

        // コメント一覧の表。情報欄のスクロールと場所を取り合う。
        // 行は本文 (13pt) + 右端に時刻 (Web 版コメント一覧の並び)。
        commentTableView.backgroundColor = AppPalette.background
        commentTableView.separatorColor = AppPalette.pressed
        commentTableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        commentTableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        commentTableView.rowHeight = UITableView.automaticDimension
        commentTableView.estimatedRowHeight = 34
        commentTableView.dataSource = self
        commentTableView.delegate = self
        commentTableView.register(CommentListCell.self, forCellReuseIdentifier: CommentListCell.reuseIdentifier)
        commentTableView.isHidden = true
        commentTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commentTableView)
        // 空表示 (取得中・0件・失敗で文を出し分ける)。
        commentEmptyLabel.textColor = AppPalette.metaText
        commentEmptyLabel.font = .scaledSystemFont(ofSize: 13)
        commentEmptyLabel.numberOfLines = 0
        commentEmptyLabel.textAlignment = .center
        updateCommentEmptyState()

        messageLabel.textColor = .systemYellow
        messageLabel.font = .scaledSystemFont(ofSize: 12.5)
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true

        // 番組名: パネルの見出し (19pt 太字)。[字] [再] などの印は、
        // Web 版と同じピンク地の印に描き分ける (題名の文字列のままにはしない)。
        infoTitleLabel.font = .scaledSystemFont(ofSize: 19, weight: .bold)
        infoTitleLabel.attributedText = decoratedProgramTitle(
            program.title, font: infoTitleLabel.font, textColor: AppPalette.text)
        infoTitleLabel.numberOfLines = 0

        // 局の並び: ロゴ 44x36 (角丸 3pt) + 「Ch: 番号 局名」14pt + 時刻 12.5pt。
        logoImageView.backgroundColor = AppPalette.placeholder
        logoImageView.contentMode = .scaleAspectFill
        logoImageView.clipsToBounds = true
        logoImageView.layer.cornerRadius = 3
        if let channel = program.channel {
            channelLabel.text = channel.channel_number.map { "Ch: \($0) \(channel.name)" } ?? channel.name
        } else {
            channelLabel.text = "チャンネル情報なし"
        }
        channelLabel.textColor = AppPalette.text
        channelLabel.font = .scaledSystemFont(ofSize: 14)
        channelLabel.numberOfLines = 1
        channelLabel.lineBreakMode = .byTruncatingTail
        programTimeLabel.text = programTimeText()
        programTimeLabel.textColor = AppPalette.metaText
        programTimeLabel.font = .scaledSystemFont(ofSize: 12.5)
        let channelTexts = UIStackView(arrangedSubviews: [channelLabel, programTimeLabel])
        channelTexts.axis = .vertical
        channelTexts.spacing = 2
        let broadcasterRow = UIStackView(arrangedSubviews: [logoImageView, channelTexts])
        broadcasterRow.axis = .horizontal
        broadcasterRow.spacing = 12
        broadcasterRow.alignment = .center
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 44),
            logoImageView.heightAnchor.constraint(equalToConstant: 36),
        ])
        loadChannelLogo()

        // 説明: 12pt、行間 168% 相当、色は text-darken-1。
        if let description = program.description, !description.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 12 * 0.68
            descriptionLabel.attributedText = NSAttributedString(string: description, attributes: [
                .font: UIFont.scaledSystemFont(ofSize: 12),
                .foregroundColor: AppPalette.metaText,
                .paragraphStyle: paragraph,
            ])
        }
        descriptionLabel.numberOfLines = 0

        // ジャンルの印: Web 版パネルと同じく「大分類 / 中分類」の印を流して並べる。
        // 地は background-lighten-2、角丸 4pt、字は 10.5pt、内側の余白は 3pt、
        // 印の間隔は横 4pt・行間 4pt。材料が無ければ行ごと出さない。
        genreFlowView.horizontalSpacing = 4
        genreFlowView.verticalSpacing = 4
        if let genres = program.genres, !genres.isEmpty {
            for genre in genres {
                let chip = BadgeLabel()
                chip.text = "\(genre.major) / \(genre.middle)"
                chip.font = .scaledSystemFont(ofSize: 10.5)
                chip.textColor = AppPalette.text
                chip.backgroundColor = AppPalette.pressed
                chip.layer.cornerRadius = 4
                chip.clipsToBounds = true
                chip.textInsets = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
                genreFlowView.addSubview(chip)
            }
        } else {
            genreFlowView.isHidden = true
        }

        // 録画期間とコメント数の状態行: 12.5pt、色は text-darken-1。
        // コメント数は、過去ログコメントが取得できたときに後から足される。
        statusLabel.textColor = AppPalette.metaText
        statusLabel.font = .scaledSystemFont(ofSize: 12.5)
        statusLabel.numberOfLines = 0
        updateStatusText()

        // 詳細情報の節: Web 版パネルと同じく、見出し (18pt) と本文 (12pt、
        // 行間 168% 相当、色は text-darken-1) の組を並べる。
        // 並びは見出しの順 (材料は辞書で届くため順序を保てない。予約詳細と同じ扱い)。
        // 材料が無い・本文が空の節は出さない。
        detailStack.axis = .vertical
        detailStack.spacing = 16
        if let detail = program.detail {
            for heading in detail.keys.sorted() {
                guard let body = detail[heading], !body.isEmpty else { continue }
                let headingLabel = UILabel()
                headingLabel.text = heading
                headingLabel.font = .scaledSystemFont(ofSize: 18, weight: .bold)
                headingLabel.textColor = AppPalette.text
                headingLabel.numberOfLines = 0
                let bodyLabel = UILabel()
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 12 * 0.68
                bodyLabel.attributedText = NSAttributedString(string: body, attributes: [
                    .font: UIFont.scaledSystemFont(ofSize: 12),
                    .foregroundColor: AppPalette.metaText,
                    .paragraphStyle: paragraph,
                ])
                bodyLabel.numberOfLines = 0
                let section = UIStackView(arrangedSubviews: [headingLabel, bodyLabel])
                section.axis = .vertical
                section.spacing = 8
                detailStack.addArrangedSubview(section)
            }
        }
        detailStack.isHidden = detailStack.arrangedSubviews.isEmpty

        // 操作の小さなボタン群 (旧「その他」メニューの中身も、ここへ直接並べる)。
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.showsMenuAsPrimaryAction = true
        qualityButton.menu = makeQualityMenu()
        // 画質プロファイルの手動切り替え (Web 版プレイヤーの設定パネルにある
        // 「モバイル回線向け画質」のトグルにあたる)。オン = モバイル回線向け。
        profileButton.addTarget(self, action: #selector(toggleProfile), for: .touchUpInside)
        updateProfileButtonTitle()
        rateButton.setTitle("速度: \(SettingsStore.playbackRateText(SettingsStore.shared.playbackRate))", for: .normal)
        rateButton.showsMenuAsPrimaryAction = true
        rateButton.menu = makePlaybackRateMenu()
        audioOnlyButton.setTitle("音声のみ: OFF", for: .normal)
        audioOnlyButton.addTarget(self, action: #selector(toggleAudioOnly), for: .touchUpInside)
        // 全画面は映像内の専用アイコンとして配置する。
        fullscreenButton.addTarget(self, action: #selector(showFullscreen), for: .touchUpInside)
        protectButton.setTitle(currentProtected ? "保護を外す" : "保護する", for: .normal)
        protectButton.addTarget(self, action: #selector(toggleProtection), for: .touchUpInside)
        mylistButton.addTarget(self, action: #selector(toggleMylist), for: .touchUpInside)
        updateMylistButtonTitle()
        watchedButton.setTitle("視聴済みにする", for: .normal)
        watchedButton.addTarget(self, action: #selector(markWatched), for: .touchUpInside)
        watchedButton.isHidden = recordingInProgress || (program.watched_ratio ?? 0) >= 1
        // おやすみタイマー (Web 版パネルのボタンと同じ)。タイマーの絵つきで、
        // 文と色は状態に合わせて updateSleepTimerButton で合わせる。
        sleepTimerButton.setImage(
            UIImage(systemName: "timer", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)),
            for: .normal)
        sleepTimerButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        sleepTimerButton.addTarget(self, action: #selector(cycleSleepTimer), for: .touchUpInside)
        // 拡張版の再生画面まわりのボタン (Web 版パネルの並びに合わせ、
        // 前の話・次の話・場面一覧・しおりを追加・ダイジェスト再生・
        // コメント検索の順)。前後は有無が分かるまで隠し、場面一覧は
        // 場面の画像の材料が無い録画では出さず、ダイジェスト再生は
        // 見どころ区間が取れるまで出さない。
        prevEpisodeButton.setTitle("前の話", for: .normal)
        prevEpisodeButton.addTarget(self, action: #selector(goToPreviousEpisode), for: .touchUpInside)
        prevEpisodeButton.isHidden = true
        nextEpisodeButton.setTitle("次の話", for: .normal)
        nextEpisodeButton.addTarget(self, action: #selector(goToNextEpisode), for: .touchUpInside)
        nextEpisodeButton.isHidden = true
        sceneListButton.setTitle("場面一覧", for: .normal)
        sceneListButton.addTarget(self, action: #selector(showSceneList), for: .touchUpInside)
        sceneListButton.isHidden = seekTileInfo == nil
        addBookmarkButton.setTitle("しおりを追加", for: .normal)
        addBookmarkButton.addTarget(self, action: #selector(addBookmark), for: .touchUpInside)
        digestButton.setTitle("ダイジェスト再生", for: .normal)
        digestButton.addTarget(self, action: #selector(toggleDigestPlayback), for: .touchUpInside)
        digestButton.isHidden = true
        commentSearchButton.setTitle("コメント検索", for: .normal)
        commentSearchButton.addTarget(self, action: #selector(showCommentSearch), for: .touchUpInside)
        nextReserveButton.setTitle("次回を予約", for: .normal)
        nextReserveButton.addTarget(self, action: #selector(reserveNextBroadcast), for: .touchUpInside)
        seriesReserveButton.setTitle("シリーズ予約", for: .normal)
        seriesReserveButton.addTarget(self, action: #selector(createSeriesReservation), for: .touchUpInside)
        for button in [qualityButton, profileButton, rateButton, audioOnlyButton, protectButton, mylistButton, watchedButton, sleepTimerButton,
                       prevEpisodeButton, nextEpisodeButton, sceneListButton, addBookmarkButton, digestButton, commentSearchButton,
                       nextReserveButton, seriesReserveButton] {
            stylePlayerChip(button)
        }
        updateSleepTimerButton()
        // ボタン群は Web 版パネルと同じ流し並べ: 中身なりの幅で左から並び、
        // 収まらなければ次の行へ。横の間隔 10pt、行の間隔 16pt。
        buttonsFlowView.horizontalSpacing = 10
        buttonsFlowView.verticalSpacing = 16
        // ボタンの出し分け (2026-11-24 の分類の見直し後):
        // 前の話・次の話、場面一覧、しおり、保護は改造版サーバーが
        // 要るため、それぞれの個別トグルの対象。ダイジェスト再生と
        // コメント検索はアプリだけで完結するため常時出す。次回を予約と
        // シリーズ予約は予約機能と同じ条件 (後ろ側が EDCB のとき) に
        // 寄せ、常時出す (EDCB でないときは、実行時に予約機能と同じ
        // 知らせ文が出る)。並び順は見直し前と変えない。
        var infoButtons: [UIButton] = []
        if AppEdition.episodeNavigationEnabled {
            infoButtons += [prevEpisodeButton, nextEpisodeButton]
        }
        if AppEdition.bookmarksAndScenesEnabled {
            infoButtons += [sceneListButton, addBookmarkButton]
        }
        infoButtons += [commentSearchButton,
                        nextReserveButton, seriesReserveButton]
        if AppEdition.protectionEnabled {
            infoButtons += [protectButton]
        }
        infoButtons += [mylistButton, watchedButton]
        for button in infoButtons {
            buttonsFlowView.addSubview(button)
        }

        let infoStack = UIStackView(arrangedSubviews: [
            messageLabel, infoTitleLabel, broadcasterRow, descriptionLabel, genreFlowView, statusLabel, buttonsFlowView, detailStack,
        ])
        infoStack.axis = .vertical
        infoStack.spacing = 12
        infoStack.isLayoutMarginsRelativeArrangement = true
        infoStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        // Web 版パネルの余白: 局の並びは番組名から 16pt、説明は局から 12pt、
        // ジャンルは説明から 10pt、状態行はその下、ボタン群は状態行から 16pt、
        // 詳細の節はボタン群から 24pt。
        infoStack.setCustomSpacing(16, after: infoTitleLabel)
        infoStack.setCustomSpacing(12, after: broadcasterRow)
        infoStack.setCustomSpacing(10, after: descriptionLabel)
        infoStack.setCustomSpacing(16, after: statusLabel)
        infoStack.setCustomSpacing(24, after: buttonsFlowView)
        scrollView.addSubview(infoStack)

        // 16:9を基本とし、見出し44・中央操作56・下部76が重ならない最小高さだけ保つ。
        // 映像自体はaspect-fitで収め、実際の高さはviewDidLayoutSubviewsで更新する。
        let heightConstraint = normalVideoLayoutGuide.heightAnchor.constraint(equalToConstant: 176)
        videoHeightConstraint = heightConstraint
        view.addLayoutGuide(normalVideoLayoutGuide)
        NSLayoutConstraint.activate([
            normalVideoLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            normalVideoLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            normalVideoLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightConstraint,
        ])
        normalVideoConstraints = [
            videoContainer.topAnchor.constraint(equalTo: normalVideoLayoutGuide.topAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: normalVideoLayoutGuide.bottomAnchor),
        ]
        fullscreenVideoConstraints = [
            videoContainer.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(normalVideoConstraints)

        // 映像・字幕・実況は通常と全画面で同じ親と固定制約を使う。
        let surfaceViewHomeConstraints = [
            surfaceView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
        ]
        NSLayoutConstraint.activate(surfaceViewHomeConstraints)

        // 字幕の重ね物は映像の枠いっぱいに広げる。
        let captionHomeConstraints = [
            captionOverlayView.topAnchor.constraint(equalTo: surfaceView.topAnchor),
            captionOverlayView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor),
            captionOverlayView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor),
            captionOverlayView.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor),
        ]
        NSLayoutConstraint.activate(captionHomeConstraints)

        // 実況も映像の入れ物に固定し、表示状態だけを切り替える。
        let commentHomeConstraints = [
            commentOverlay.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            commentOverlay.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            commentOverlay.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            commentOverlay.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
        ]
        NSLayoutConstraint.activate(commentHomeConstraints)

        // 操作行44ptとシーク操作24ptは既存の76pt内へ収め、波形で高さを増やさない。
        controlsHeightConstraint = controlsContainer.heightAnchor.constraint(equalToConstant: 76)
        normalSeekConstraints = [
            seekContainer.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            seekContainer.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            seekContainer.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
        ]
        fullscreenSeekConstraints = [
            seekContainer.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor),
            seekContainer.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor),
            seekContainer.bottomAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.bottomAnchor),
        ]
        NSLayoutConstraint.activate(normalSeekConstraints)
        NSLayoutConstraint.activate([
            videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomGradient.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            bottomGradient.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            bottomGradient.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            bottomGradient.heightAnchor.constraint(equalToConstant: 76),
            controlsContainer.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.bottomAnchor),
            controlsHeightConstraint!,
            centerTransport.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            centerTransport.centerYAnchor.constraint(equalTo: transportGuide.centerYAnchor),
            controlsStackView.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            controlsStackView.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            controlsStackView.bottomAnchor.constraint(equalTo: seekContainer.topAnchor),
            seekContainer.heightAnchor.constraint(equalToConstant: 24),
            infoTabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            infoTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoTabBar.heightAnchor.constraint(equalToConstant: 50),
            scrollView.topAnchor.constraint(equalTo: normalVideoLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: infoTabBar.topAnchor),
            commentTableView.topAnchor.constraint(equalTo: normalVideoLayoutGuide.bottomAnchor),
            commentTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentTableView.bottomAnchor.constraint(equalTo: infoTabBar.topAnchor),
            infoStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            infoStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            infoStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            infoStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    /// 局ロゴを読み込む (取れなければ読み込み前の地のまま)。
    private func loadChannelLogo() {
        guard let channel = program.channel else { return }
        let channelID = channel.id
        Task { [weak self] in
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channelID),
                  let image = UIImage(data: data) else { return }
            self?.logoImageView.image = image
        }
    }

    /// 見出し帯の右端に時計を置く (Web 版の上部帯の時計に相当)。
    private func setupHeaderClock() {
        headerClockIconView.image = UIImage(systemName: "clock.arrow.circlepath")
        headerClockIconView.tintColor = AppPalette.secondary
        headerClockIconView.contentMode = .scaleAspectFit
        headerClockIconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        headerClockIconView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        headerClockLabel.font = .scaledMonospacedDigitSystemFont(ofSize: 11, weight: .medium)
        headerClockLabel.textColor = AppPalette.text
        let stack = UIStackView(arrangedSubviews: [headerClockIconView, headerClockLabel])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        headerClockLabel.textColor = .white
        overlayHeader.clock.addArrangedSubview(stack)
        updateHeaderClock()
    }

    /// 時計の表示を更新する。元の放送時刻の表示が入っているときは
    /// アイコンを添えて、録画開始時刻 (取れなければ番組の開始時刻) に
    /// 再生位置を足した時刻を出す。止めている間は再生位置が動かないので
    /// 表示もそのまま止まる (Web 版と同じ)。普段は今の時刻を出す。
    private func updateHeaderClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        if SyncedSettingsStore.shared.current.showOriginalBroadcastTimeDuringPlayback,
           let base = program.recorded_video.recordingStartDate ?? program.startDate {
            headerClockIconView.isHidden = false
            let position = currentPosition()
            let shown = base.addingTimeInterval(position.isFinite ? position : 0)
            headerClockLabel.text = TimeFormat.apply28HourClock(formatter.string(from: shown))
        } else {
            headerClockIconView.isHidden = true
            headerClockLabel.text = TimeFormat.apply28HourClock(formatter.string(from: Date()))
        }
    }

    /// 放送時刻の表示 (Web 版パネルの局の並びの時刻と同じ形。分数まで出す)。
    private func programTimeText() -> String {
        guard let start = program.startDate, let end = program.endDate else { return "" }
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "yyyy/MM/dd (E) HH:mm"
        startFormatter.locale = Locale(identifier: "ja_JP")
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        endFormatter.locale = Locale(identifier: "ja_JP")
        let minutes = TimeFormat.minutesText(durationSeconds: program.duration)
        return TimeFormat.apply28HourClock("\(startFormatter.string(from: start)) ～ \(endFormatter.string(from: end)) (\(minutes)分)")
    }

    /// 「録画期間: 〜」の状態行 (Web 版パネルと同じく秒まで出す)。
    /// 録画の開始・終了が取れないときは空 (行ごと隠す)。
    private func recordingStatusText() -> String? {
        guard let start = program.recorded_video.recordingStartDate else { return nil }
        let text = TimeFormat.recordingPeriodText(
            start: start,
            end: program.recorded_video.recordingEndDate ?? program.endDate,
            durationSeconds: program.recorded_video.duration
        )
        guard !text.isEmpty else { return nil }
        let partial = program.isPartiallyRecorded ? "(一部のみ録画)" : ""
        return "録画期間: \(partial)\n\(text)"
    }

    private func configure(_ button: UIButton, symbol: String, pointSize: CGFloat, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeQualityMenu() -> UIMenu {
        // 選択肢の表示は設定画面と同じく、データ量と平均ビットレート付き。
        // 数値は現在の区分の通信節約モードの有無で切り替わる。
        let dataSaver = SettingsStore.shared.dataSaverMode(media: .video, profile: profile)
        return UIMenu(children: SettingsStore.qualities.map { q in
            UIAction(title: SettingsStore.qualityDisplayName(q, dataSaverMode: dataSaver),
                     state: q == quality ? .on : .off) { [weak self] _ in
                self?.userSwitchQuality(q)
            }
        })
    }

    /// 利用者が画質を選んだときの切り替え。切り替えた画質は、現在の区分の
    /// 既定画質として設定へ書き戻す (次回も最後に選んだ画質で始まるように
    /// するため。Web 版 (改造) の効き方と同じ)。書き戻しは切り替え開始時点と、
    /// 切り替えが完了して再生が再開した時点の両方で行う
    /// (本番 Web 版の追加の直しに合わせた)。
    /// 音声のみの切り替えのような内部の画質変更は、ここを通らないので
    /// 書き戻しの対象にならない。
    private func userSwitchQuality(_ newQuality: String) {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            showPlayerNotice("PiP を終了してから再生設定を変更してください。")
            return
        }
        guard newQuality != quality else { return }
        playerSettingsPanel?.closePanel()
        SettingsStore.shared.setStreamingQuality(newQuality, media: .video, profile: profile)
        pendingQualityWriteBack = newQuality
        switchQuality(newQuality)
    }

    /// 画質プロファイルの手動切り替えボタンの表示を、現在の区分に合わせる。
    private func updateProfileButtonTitle() {
        profileButton.setTitle(
            profile == .cellular ? "モバイル回線向け画質: ON" : "モバイル回線向け画質: OFF",
            for: .normal)
        buttonsFlowView.setNeedsLayout()
    }

    @objc private func toggleProfile() {
        _ = switchProfile(to: profile == .cellular ? .wifi : .cellular)
    }

    /// 画質プロファイルを手で切り替える (Web 版プレイヤーの設定パネルの
    /// 「モバイル回線向け画質」トグルと同じ)。切り替えた瞬間に選択を
    /// 端末へ保存し (last_quality_profile_type)、次に開くときも引き継ぐ。
    /// 再生は、切り替え後の区分の既定画質で作り直す (再生中の画質は
    /// 引き継がない。Web 版の should_resume_quality: false と同じ)。
    /// 録画の位置は引き継ぐ。
    /// 戻り値は切り替え後に実際に使う画質。
    @discardableResult
    private func switchProfile(to newProfile: PlaybackProfile) -> String {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            showPlayerNotice("PiP を終了してから再生設定を変更してください。")
            return quality
        }
        guard newProfile != profile else { return quality }
        playerSettingsPanel?.closePanel()
        // 画質の切り替えと同じく、止めていた場合は作り直した後も止めたままにする。
        let wasPlaying = isCurrentlyPlaying()
        profile = newProfile
        SettingsStore.shared.lastQualityProfileType = newProfile
        updateProfileButtonTitle()
        let current = currentPosition()
        // プロファイル切り替え自体は画質の変更ではないので、書き戻しの
        // 控えは持たない。
        pendingQualityWriteBack = nil
        if audioOnly {
            // 音声のみの最中は、映像を戻したときの画質だけ新しい区分の
            // 既定に差し替え、流れ自体は最小画質のまま作り直す。
            qualityBeforeAudioOnly = SettingsStore.shared.streamingQuality(media: .video, profile: newProfile)
        } else {
            quality = SettingsStore.shared.streamingQuality(media: .video, profile: newProfile)
        }
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.menu = makeQualityMenu()
        buttonsFlowView.setNeedsLayout()
        // 画質が変わるのでセッションも作り直す (画質切り替えと同じ)。
        sessionID = UUID().uuidString
        startPlayback(at: current.isFinite ? current : 0)
        if !wasPlaying {
            pauseEngine()
            updatePlayPauseIcon()
        }
        messageLabel.text = newProfile == .cellular
            ? "モバイル回線向けの画質プロファイルに切り替えました。"
            : "Wi-Fi 回線向けの画質プロファイルに切り替えました。"
        return quality
    }

    private func makePlaybackRateMenu() -> UIMenu {
        let current = SettingsStore.shared.playbackRate
        return UIMenu(children: SettingsStore.playbackRateChoices.map { rate in
            UIAction(
                title: SettingsStore.playbackRateText(rate),
                state: rate == current ? .on : .off
            ) { [weak self] _ in
                self?.setPlaybackRate(rate)
            }
        })
    }

    /// 再生速度を変える。再生中ならその場で効かせ、設定へ書き戻す
    /// (次回も同じ速度で始まる。Web 版 (改造) の効き方と同じ)。
    private func setPlaybackRate(_ rate: Double) {
        SettingsStore.shared.playbackRate = rate
        rateButton.setTitle("速度: \(SettingsStore.playbackRateText(rate))", for: .normal)
        rateButton.menu = makePlaybackRateMenu()
        buttonsFlowView.setNeedsLayout()
#if canImport(VLCKit)
        if let vlcPlayer, vlcPlayer.isPlaying {
            vlcPlayer.rate = Float(rate)
        }
#endif
        if let player, player.rate != 0 {
            player.rate = Float(rate)
        }
        updateNowPlaying()
        scheduleHideControls()
    }

    /// 設定されている再生速度で再生を始める。
    /// AVPlayer の play() は速度が 1倍に戻るため、再生の開始はここへ集約する
    /// (VLCKit 経路でも、再生を始めてから速度を合わせる順番は同じにする)。
    private func playAtCurrentRate() {
        defer { refreshFMP4StartWatchdog() }
        playbackIntentPlaying = true
        // 明示的に再生する操作が来たら、開始待ちへの「止める」印は消す
        // (開始の用意ができたときに、そのまま再生が始まるように)。
        playbackStart.pauseRequested = false
        // 再生が再開されたら、次の話の自動再生の数え下げは取り消す
        // (Web 版も、再生が再開されたら数え下げを取り消す)。
        // 数え下げ前の「次の話の取り込み」がまだ終わっていない場合も、
        // 終わった出来事を古くして、応答が来ても数え下げを始めない。
        playbackEndEventID += 1
        cancelAutoplayCountdown()
#if canImport(VLCKit)
        if let vlcPlayer {
            vlcPlayer.play()
            let rate = SettingsStore.shared.playbackRate
            if rate != 1 {
                vlcPlayer.rate = Float(rate)
            }
            updatePlayPauseIcon()
            return
        }
#endif
        guard let player else { return }
        player.play()
        let rate = SettingsStore.shared.playbackRate
        if rate != 1 {
            player.rate = Float(rate)
        }
        updatePlayPauseIcon()
    }

    /// 再生を止める (再生の仕組みによらない)。
    private func pauseEngine(isUserInitiated: Bool = true) {
        defer { refreshFMP4StartWatchdog() }
        if isUserInitiated { playbackIntentPlaying = false }
#if canImport(VLCKit)
        // 利用者が止めたら、移動後の自動再開の印は消す
        // (止めたのに勝手に再開しないため)。
        vlcResumeAfterSeek = false
#endif
        // 開始の用意 (中継の URL の解決) を待っている間に止める操作が
        // 来たら、印を残す。仕組みがまだ無いのでここで止める対象は
        // まだ無く、開始の締め側で再生を始めないようにするために使う。
        if playbackStart.inFlight {
            playbackStart.pauseRequested = true
        }
#if canImport(VLCKit)
        if let vlcPlayer {
            vlcPlayer.pause()
            return
        }
#endif
        player?.pause()
    }

    @objc private func markWatched() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.markWatched(videoID: program.id, duration: program.duration)
                self.watchedButton.isHidden = true
                self.buttonsFlowView.setNeedsLayout()
                self.messageLabel.text = "視聴済みにしました。一覧に戻ると表示が更新されます。"
            } catch {
                self.messageLabel.text = "視聴済みにできませんでした。"
            }
        }
    }

    // MARK: - コメント (ニコニコ実況の過去ログ)

    /// 過去ログコメントを取りに行く (画面を開いたときに1回だけ)。
    /// 取れたら、件数を情報欄に出し、その時点の再生位置から流し始める。
    /// 取れなかった録画 (チャンネル情報が無い等) では、コメントなしのまま
    /// 再生を続ける (Web 版も取得できなければコメントなしで続ける)。
    private func loadJikkyoComments() {
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            guard let result = await APIClient.shared.fetchJikkyoComments(videoID: videoID) else {
                self.jikkyoLoadState = .failed("コメントを取得できませんでした。")
                self.updateCommentEmptyState()
                return
            }
            guard result.is_success else {
                let detail = result.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                self.jikkyoLoadState = .failed(detail.isEmpty ? "コメントを取得できませんでした。" : detail)
                self.updateCommentEmptyState()
                return
            }
            // 盛り上がりの計算は、ミュートで取り除く前のコメント全体から
            // 行う (Web 版も同じ材料で計算する)。アプリだけで完結する
            // ため常時有効。
            self.buildExcitement(from: result.comments)
            // 一覧と流れる表示で共用する。時刻の昇順に並べ直しておく。
            // 設定のミュート (キーワード・ユーザー ID・機械的な判定) に
            // かかるコメントは、ここで取り除いてから両方へ渡す。
            let sorted = SyncedSettingsStore.shared.filteredComments(
                result.comments.sorted { $0.time < $1.time })
            self.jikkyoComments = sorted
            self.jikkyoLoadState = .loaded
            self.commentCount = sorted.count
            self.commentFollowIndex = -1
            self.updateStatusText()
            self.commentOverlay.setComments(sorted)
            self.commentTableView.reloadData()
            self.updateCommentEmptyState()
        }
    }

    /// 情報欄の状態行 (録画期間・コメント数) を組み直す。
    /// 材料が無い行は出さず、全部なければ行ごと隠す。
    private func updateStatusText() {
        var lines: [String] = []
        if let recording = recordingStatusText() {
            lines.append(recording)
        }
        if let count = commentCount {
            lines.append("コメント数: \(count)")
        }
        statusLabel.text = lines.isEmpty ? nil : lines.joined(separator: "\n")
        statusLabel.isHidden = statusLabel.text == nil
    }

    /// コメント表示の切り替え。設定は端末に保存し、次回も同じ状態で始める
    /// (Web 版も端末側に保存する)。
    @objc private func toggleComments() {
        SettingsStore.shared.showComments.toggle()
        updateCaptureControls()
        updateCommentButton()
        applyCommentDisplayState()
        scheduleHideControls()
    }

    /// コメント切り替えボタンの見た目を、現在の設定に合わせる。
    /// オンは吹き出しが塗られた絵で明るく、オフは輪郭だけの絵で薄く出す。
    private func updateCommentButton() {
        let on = SettingsStore.shared.showComments
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        commentButton.setImage(
            UIImage(systemName: on ? "text.bubble.fill" : "text.bubble", withConfiguration: config),
            for: .normal)
        commentButton.tintColor = .white
        commentButton.isEnabled = !audioOnly
        commentButton.alpha = audioOnly ? 0.25 : (on ? 1 : 0.4)
        commentButton.accessibilityValue = on ? "オン" : "オフ"
        commentButton.accessibilityLabel = on ? "コメント表示オン" : "コメント表示オフ"
    }

    /// コメントを流すかどうかを、重ね物へ反映する。
    /// 音声のみの間は映像が出ていないので、コメントも流さない。
    private func applyCommentDisplayState() {
        commentOverlay.setDisplayEnabled(SettingsStore.shared.showComments && !audioOnly)
    }

    // MARK: - 字幕

    /// 字幕表示の切り替え。設定は端末に保存し、次回も同じ状態で始める
    /// (コメント表示の切り替えと同じ考え方)。
    @objc private func toggleCaptions() {
        SettingsStore.shared.showCaptions.toggle()
        updateCaptionButton()
        applyCaptionDisplayState()
        scheduleHideControls()
    }

    /// 字幕切り替えボタンの見た目を、現在の設定に合わせる。
    /// オンは吹き出しが塗られた絵で明るく、オフは輪郭だけの絵で薄く出す
    /// (コメント切り替えと同じ出し分け)。
    private func updateCaptionButton() {
        let on = SettingsStore.shared.showCaptions
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        captionButton.setImage(
            UIImage(systemName: on ? "captions.bubble.fill" : "captions.bubble", withConfiguration: config),
            for: .normal)
        captionButton.tintColor = .white
        captionButton.isEnabled = !audioOnly
        captionButton.alpha = audioOnly ? 0.25 : (on ? 1 : 0.4)
        captionButton.accessibilityLabel = on ? "字幕表示オン" : "字幕表示オフ"
    }

    /// 字幕を出すかどうかを、重ね物へ反映する。
    /// 音声のみの間は映像が出ていないので、字幕も出さない。
    private func applyCaptionDisplayState() {
        captionOverlayView.isHidden = !(SettingsStore.shared.showCaptions && !audioOnly)
        if !captionOverlayView.isHidden {
            refreshCaptions()
            captionOverlayView.setImage(captionEngine.currentImage)
        }
    }

    /// シーク中は通常/全画面で共有する描画と撮影用画像を同時に消す。
    @discardableResult
    private func beginCaptionSeek() -> UInt64 {
        captureController.cancel()
        let token = captionEngine.beginSeek()
        captionOverlayView.setImage(nil)
        return token
    }

    /// 字幕の絵を、いまの再生位置に合わせて更新する。
    /// 進み具合の更新 (0.5秒ごと) と、字幕の包みが届いたときに呼ばれる。
    private func refreshCaptions() {
        guard !captionOverlayView.isHidden else { return }
        if captionEngine.update(position: currentPosition()) {
            captionOverlayView.setImage(captionEngine.currentImage)
        }
        // 映像の描画側が字幕より上に重なることがあるため、通常画面では
        // 字幕を映像の枠の中で一番上に保つ。
        if captionOverlayView.superview === surfaceView {
            surfaceView.bringSubviewToFront(captionOverlayView)
        }
    }

    // MARK: - 情報欄のタブとコメント一覧

    /// 情報欄のタブボタンの中身 (絵の上に文字の縦並び、Web 版パネル下部の
    /// ナビと同じ形) を作る。
    private func buildInfoTabButton(_ button: RippleButton, iconView: UIImageView, titleLabel: UILabel,
                                    symbol: String, title: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        iconView.image = UIImage(systemName: symbol, withConfiguration: config)
        iconView.contentMode = .scaleAspectFit
        titleLabel.text = title
        titleLabel.font = .scaledSystemFont(ofSize: 10.5)
        titleLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// タブの色を選択状態に合わせる (選択中は primary、他は通常の文字色。
    /// Web 版パネルのナビと同じ)。
    private func updateInfoTabButtons() {
        infoTabIconView.tintColor = selectedInfoTab == .info ? AppPalette.accent : AppPalette.text
        infoTabTitleLabel.textColor = selectedInfoTab == .info ? AppPalette.accent : AppPalette.text
        commentTabIconView.tintColor = selectedInfoTab == .comment ? AppPalette.accent : AppPalette.text
        commentTabTitleLabel.textColor = selectedInfoTab == .comment ? AppPalette.accent : AppPalette.text
    }

    @objc private func selectInfoTab() { applyInfoTab(.info) }

    @objc private func selectCommentTab() { applyInfoTab(.comment) }

    /// 情報欄のタブを切り替える。コメントを開いたときは、その時点の
    /// 再生位置のコメントが見えるよう追随し直す。
    private func applyInfoTab(_ tab: InfoTab) {
        selectedInfoTab = tab
        scrollView.isHidden = isFullscreen || tab != .info
        commentTableView.isHidden = isFullscreen || tab != .comment
        updateInfoTabButtons()
        if tab == .comment, !commentTabHasBeenShown {
            // 初回だけ現在位置へ追随する。再訪時は保持した位置と既存の追随ルールを使う。
            commentTabHasBeenShown = true
            commentFollowIndex = -1
            commentListManualScrollAt = nil
            // 表のレイアウトが確定してから追随させる (確定前だと位置が合わない)。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedInfoTab == .comment else { return }
                self.updateCommentListFollow(current: self.currentPosition(), force: true)
            }
        }
    }

    /// コメント一覧の空表示を、取得の状態に合わせて出し分ける
    /// (Web 版コメントパネルの案内の文に合わせる)。
    private func updateCommentEmptyState() {
        guard jikkyoComments.isEmpty else {
            commentTableView.backgroundView = nil
            return
        }
        switch jikkyoLoadState {
        case .loading:
            commentEmptyLabel.text = "まだコメントがありません。\nこの録画番組に対応する、ニコニコ実況の過去ログコメントを取得しています..."
        case .failed(let message):
            commentEmptyLabel.text = "コメントがありません。\n\(message)"
        case .loaded:
            commentEmptyLabel.text = "まだコメントがありません。\nこの録画番組に対応する、ニコニコ実況の過去ログコメントはありませんでした。"
        }
        if commentTableView.backgroundView == nil {
            let container = UIView()
            commentEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(commentEmptyLabel)
            NSLayoutConstraint.activate([
                commentEmptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                commentEmptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                commentEmptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            ])
            commentTableView.backgroundView = container
        }
    }

    /// コメント一覧の追随 (Web 版コメントパネルと同じ考え方: 再生位置を
    /// 過ぎた最後のコメントが一覧の下端に来るよう、自動でスクロールする)。
    /// 利用者が手でスクロールしている間と、その後しばらくは動かさない。
    private func updateCommentListFollow(current: Double, force: Bool = false) {
        guard selectedInfoTab == .comment, !jikkyoComments.isEmpty,
              commentTableView.bounds.height > 0,
              !commentTableView.isDragging, !commentTableView.isDecelerating else { return }
        if !force, let manualAt = commentListManualScrollAt,
           Date().timeIntervalSince(manualAt) < 4 { return }
        guard current.isFinite else { return }
        var target = -1
        for (index, comment) in jikkyoComments.enumerated() {
            if comment.time <= current { target = index } else { break }
        }
        guard target >= 0, target != commentFollowIndex else { return }
        let isJump = commentFollowIndex < 0 || abs(target - commentFollowIndex) > 20
        commentFollowIndex = target
        commentTableView.scrollToRow(
            at: IndexPath(row: target, section: 0), at: .bottom, animated: !isJump)
    }

    // MARK: - おやすみタイマー

    /// おやすみタイマーの切り替え (Web 版 SleepTimerManager の写し)。
    /// 押すたびに オフ → 15分 → 30分 → 60分 → 番組の終わりで停止 → オフ と巡り、
    /// 切り替えるたびに知らせを出す。分モードは残り時間を1秒ごとに減らし、
    /// 0 になったら再生を止める (Web 版と同じく、止めている間も減り続ける)。
    /// 「番組の終わりで停止」は Web 版では次の話の自動再生を止めるための印で、
    /// アプリには自動再生が無いため、番組の終わりで止まる通常の終わり方と
    /// 結果は同じになる (印と表示だけが Web 版どおりに働く)。
    @objc private func cycleSleepTimer() {
        let modes = ["off", "15", "30", "60", "end"]
        sleepTimerModeIndex = (sleepTimerModeIndex + 1) % modes.count
        let mode = modes[sleepTimerModeIndex]
        stopSleepTimerTicker()
        sleepTimerRemainingSeconds = nil
        switch mode {
        case "15", "30", "60":
            sleepTimerMode = .minutes
            sleepTimerRemainingSeconds = Int(mode)! * 60
            sleepTimerTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tickSleepTimer()
            }
            messageLabel.text = "おやすみタイマー: \(mode) 分後に停止します"
        case "end":
            sleepTimerMode = .end
            messageLabel.text = "おやすみタイマー: この番組の終わりで停止します"
        default:
            sleepTimerMode = .off
            messageLabel.text = "おやすみタイマーをオフにしました"
        }
        updateSleepTimerButton()
        applyRepeatPlayback()
        buttonsFlowView.setNeedsLayout()
    }

    /// 分モードの1秒ごとの処理。残り時間を減らし、0 になったら再生を止めて
    /// オフに戻す (Web 版の onTick と同じ)。
    private func tickSleepTimer() {
        guard var remaining = sleepTimerRemainingSeconds else { return }
        remaining -= 1
        if remaining <= 0 {
            sleepTimerRemainingSeconds = nil
            sleepTimerMode = .off
            sleepTimerModeIndex = 0
            stopSleepTimerTicker()
            pauseEngine()
            updatePlayPauseIcon()
            messageLabel.text = "おやすみタイマーで停止しました"
        } else {
            sleepTimerRemainingSeconds = remaining
        }
        updateSleepTimerButton()
        buttonsFlowView.setNeedsLayout()
    }

    private func stopSleepTimerTicker() {
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil
    }

    /// おやすみタイマーのボタンの文と色を、現在の状態に合わせる。
    /// 文は Web 版パネルと同じ: オフは「おやすみタイマー」、分モードは
    /// 「おやすみ (残り M:SS)」、終わりで停止は「おやすみ (番組の終わりで停止)」。
    /// 有効な間は Web 版と同じく primary の地に白い文字にする。
    private func updateSleepTimerButton() {
        switch sleepTimerMode {
        case .off:
            sleepTimerButton.setTitle("おやすみタイマー", for: .normal)
        case .minutes:
            let remaining = sleepTimerRemainingSeconds ?? 0
            sleepTimerButton.setTitle(
                String(format: "おやすみ (残り %d:%02d)", remaining / 60, remaining % 60),
                for: .normal)
        case .end:
            sleepTimerButton.setTitle("おやすみ (番組の終わりで停止)", for: .normal)
        }
        if sleepTimerMode == .off {
            sleepTimerButton.backgroundColor = AppPalette.panel
            sleepTimerButton.setTitleColor(AppPalette.metaText, for: .normal)
            sleepTimerButton.tintColor = AppPalette.metaText
        } else {
            sleepTimerButton.backgroundColor = AppPalette.accent
            sleepTimerButton.setTitleColor(.white, for: .normal)
            sleepTimerButton.tintColor = .white
        }
    }

    @objc private func toggleProtection() {
        guard SettingsStore.shared.isLoggedIn else {
            // 未ログインなら、切り替えはせずログインへ案内する。
            let alert = UIAlertController(
                title: "ログインが必要です",
                message: "保護の切り替えには、設定タブで KonomiTV へのログインが必要です。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { [weak self] _ in
                self?.mainTabBarController?.selectedIndex = 3
            })
            present(alert, animated: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let next = try await APIClient.shared.toggleProtection(videoID: program.id)
                self.currentProtected = next
                self.protectButton.setTitle(next ? "保護を外す" : "保護する", for: .normal)
                self.buttonsFlowView.setNeedsLayout()
                self.messageLabel.text = next ? "保護しました。" : "保護を外しました。"
            } catch let error as APIError {
                self.messageLabel.text = error.protectionFailureMessage
            } catch {
                self.messageLabel.text = "保護を切り替えられませんでした。"
            }
        }
    }

    // MARK: - 再生

    /// 再生を始める (作り直す)。いま効いている画質が H.265 / HEVC かどうかで
    /// 再生の仕組みを出し分ける。画質の切り替えで H.264 ⇄ HEVC が切り替わったら、
    /// 仕組みごと作り直す (呼び出し側が位置を引き継いで渡す)。
    /// 中継の URL が要る経路では、解決を非同期に行い、画面を止めずに
    /// 待つ (用意ができたら開始する)。中継が必須の構成で用意が
    /// できなかった場合は、直接再生に落ちず失敗として知らせ、
    /// 再生ボタンで始め直せるようにする。
    private func startPlayback(at seconds: Double, isSessionRecovery: Bool = false) {
        cancelFMP4Start()
        captureController.cancel()
        if pipController?.isActive != true, pipController?.isPending != true { PlaybackPiPController.stopCurrentPlayback() }
        startPlaybackCount += 1
        let startRequest = playbackStart.begin(context: .current)
        updatePiPButton()
        // 新しい開始では、再生はまだ始まっていないものとして扱う
        // (開始前の移動の控えと、その反映の判定に使う)。
        playbackDidStart = false
        playbackReadyForSeek = false
        // 古いkeep-aliveと未完了の移動を新しい再生へ持ち越さない。
        stopKeepAlive()
        keepAliveState.start(context: keepAliveContext, isRecovery: isSessionRecovery)
        pendingPlaybackSeek.cancel()
        seekDisplay.clear()
        guard let url = APIClient.shared.playlistURL(videoID: program.id, quality: quality, profile: profile, sessionID: sessionID) else {
            playbackStart.invalidate()
            messageLabel.text = "接続先が設定されていません。"
            return
        }
        // 新しい開始が来たら、前の開始待ちへの「止める」印は引き継がない
        // (この開始の後に来た止める操作だけが、この開始に効く)。
        playbackStart.pauseRequested = !playbackIntentPlaying
        if isHEVCQuality(quality, profile: profile),
           let fmp4URL = APIClient.shared.playlistURL(videoID: program.id, quality: quality,
               profile: profile, sessionID: sessionID, fmp4: true) {
            showStartLoadingMessage()
            let context = WatchedHistoryStore.Context.current
            let id = program.id, selectedQuality = quality, selectedProfile = profile, session = sessionID
            playlistProbeTask = Task { [weak self] in
                guard let self, !Task.isCancelled,
                      self.acceptsPlaybackRequest(startRequest) else { return }
                let playlist = await APIClient.shared.fetchPlaylist(videoID: id, quality: selectedQuality,
                    profile: selectedProfile, sessionID: session, fmp4: true, expectedContext: context)
                guard !Task.isCancelled, !self.didLeaveScreen,
                      self.acceptsPlaybackRequest(startRequest) else { return }
                self.playlistProbeTask = nil
                if FMP4PlaybackState.route(playlist: playlist) == .avPlayer {
                    self.fmp4StartContext = FMP4StartContext(request: startRequest,
                        fmp4URL: fmp4URL, fallbackURL: url, state: FMP4PlaybackState(position: seconds))
                    self.startAVPlaybackFlow(url: fmp4URL, at: seconds, request: startRequest,
                        initialResolution: true, isFMP4: true)
                } else {
                    self.startVLCPlaybackFlow(url: url, at: seconds, request: startRequest, initialResolution: true)
                }
            }
            return
        }
        startAVPlaybackFlow(url: url, at: seconds, request: startRequest, initialResolution: true, isFMP4: false)
    }

    /// 中継の解決は初回だけ開始待ちを完了させる。内部再試行は同じ開始世代のまま照合する。
    private func startAVPlaybackFlow(url: URL, at seconds: Double, request: PlaybackRequest,
                                     initialResolution: Bool, isFMP4: Bool) {
        guard !didLeaveScreen, acceptsPlaybackRequest(request) else { return }
        routeResolutionPending = true
        let begin: (URL?) -> Void = { [weak self] relayedURL in
            guard let self, !self.didLeaveScreen,
                  self.acceptsPlaybackRequest(request) else { return }
            if initialResolution, !self.playbackStart.complete(request, context: .current) { return }
            if !initialResolution, !self.canRebuildFMP4 {
                self.fmp4StartContext?.state.deferClaimedRecovery(.retry)
                self.routeResolutionPending = false
                return
            }
            self.routeResolutionPending = false
            self.clearStartLoadingMessage()
            if SettingsStore.shared.avPlaybackRequiresRelay, relayedURL == nil {
                self.pendingRelayRetryPosition = seconds
                self.messageLabel.text = "中継の用意ができず、再生を開始できませんでした。再生ボタンでもう一度お試しください。"
                return
            }
            let position = self.pendingPlaybackSeek.target ?? (isFMP4 ? self.fmp4StartContext?.state.latestPosition : nil) ?? seconds
            if isFMP4 { self.fmp4StartContext?.state.noteSeek(to: position) }
            let attempt = isFMP4 ? self.fmp4StartContext?.state.makeAttempt() : nil
            if isFMP4, attempt == nil { return }
#if canImport(VLCKit)
            self.teardownVLCPlayback()
#endif
            let asset = relayedURL.map { AVURLAsset(url: $0) } ?? APIClient.shared.playerAsset(url: url)
            self.startAVPlayback(asset: asset, at: position, request: request, fmp4Attempt: attempt)
            self.pendingRelayRetryPosition = nil
            self.finishStartPlayback(at: position)
            self.refreshFMP4StartWatchdog()
        }
        if SettingsStore.shared.avPlaybackRequiresRelay {
            showStartLoadingMessage()
            StreamRelayServer.shared.relayURL(for: url, completion: begin)
        } else { begin(nil) }
    }

    private func startVLCPlaybackFlow(url: URL, at seconds: Double, request: PlaybackRequest, initialResolution: Bool) {
        guard !didLeaveScreen, acceptsPlaybackRequest(request) else { return }
#if canImport(VLCKit)
        routeResolutionPending = true
        showStartLoadingMessage()
        StreamRelayServer.shared.relayURL(for: url) { [weak self] relayedURL in
            guard let self, !self.didLeaveScreen,
                  self.acceptsPlaybackRequest(request) else { return }
            if initialResolution, !self.playbackStart.complete(request, context: .current) { return }
            if !initialResolution, !self.canRebuildFMP4 {
                self.fmp4StartContext?.state.deferClaimedRecovery(.fallback)
                self.routeResolutionPending = false
                return
            }
            self.routeResolutionPending = false
            self.clearStartLoadingMessage()
            if relayedURL == nil, SettingsStore.shared.vlcPlaybackRequiresRelay {
                self.pendingRelayRetryPosition = seconds
                self.messageLabel.text = "中継の用意ができず、再生を開始できませんでした。再生ボタンでもう一度お試しください。"
                return
            }
            let position = self.pendingPlaybackSeek.target ?? seconds
            self.captureController.cancel()
            self.playbackReadyForSeek = false
            guard self.startVLCPlayback(url: url, relayedURL: relayedURL, at: position) else {
                self.pendingRelayRetryPosition = position
                return
            }
            self.fmp4StartContext = nil
            self.pendingRelayRetryPosition = nil
            self.finishStartPlayback(at: position)
        }
#else
        if initialResolution { _ = playbackStart.complete(request, context: .current) }
        clearStartLoadingMessage()
        messageLabel.text = "このビルドには H.265 / HEVC 再生の部品が組み込まれていません。"
#endif
    }

    private func acceptsPlaybackRequest(_ request: PlaybackRequest) -> Bool {
        guard !didLeaveScreen else { return false }
        if playbackStart.invalidateIfContextChanged(request, context: .current) {
            cancelFMP4Start()
            pendingPlaybackSeek.cancel()
            pendingRelayRetryPosition = nil
            clearStartLoadingMessage()
            if messageLabel.text == Self.fmp4RetryMessage { messageLabel.text = nil }
            return false
        }
        return playbackStart.isCurrent(request, context: .current)
    }

    private func cancelFMP4Start() {
        cancelFMP4StartWatchdog()
        playlistProbeTask?.cancel()
        playlistProbeTask = nil
        fmp4RetryWorkItem?.cancel()
        fmp4RetryWorkItem = nil
        fmp4StartContext = nil
        routeResolutionPending = false
    }

    /// 初回と再試行の各AV項目から一度だけ失敗を受け付ける。先頭0秒も同じ対象とする。
    private func handleFMP4StartFailure(item: AVPlayerItem, attempt: FMP4PlaybackState.Attempt?) -> Bool {
        guard let attempt, let context = fmp4StartContext, !context.state.didPlay,
              player?.currentItem === item,
              acceptsPlaybackRequest(context.request) else { return false }
        guard let action = fmp4StartContext?.state.failed(attempt) else { return false }
        if action == .ignored { return true }
        cancelFMP4StartWatchdog()
        captureController.cancel()
        player?.pause() // 準備失敗の停止は、利用者の再生/停止意図を書き換えない。
        playbackReadyForSeek = false
        captionMetadataOutput = nil // 失敗した項目の遅着metadataは、次の字幕世代へ入れない。
        captionEngine.resetForNewPlayback(at: fmp4StartContext?.state.latestPosition ?? 0)
        captionOverlayView.setImage(nil)
        if action == .retry {
            messageLabel.text = Self.fmp4RetryMessage
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.didLeaveScreen, let current = self.fmp4StartContext,
                      self.acceptsPlaybackRequest(current.request),
                      current.state.isWaiting(after: attempt) else { return }
                self.fmp4RetryWorkItem = nil
                _ = self.resumeDeferredFMP4Recovery()
            }
            fmp4RetryWorkItem = work
            // 本家8d333abの開始前セグメント生成待ち。字幕の時刻補正には使わない。
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        } else {
            _ = resumeDeferredFMP4Recovery()
        }
        updatePlayPauseIcon()
        return true
    }

    @discardableResult
    private func resumeDeferredFMP4Recovery() -> Bool {
        guard fmp4RetryWorkItem == nil, !didLeaveScreen, let context = fmp4StartContext,
              acceptsPlaybackRequest(context.request),
              let action = fmp4StartContext?.state.claimRecovery(canReplace: canRebuildFMP4) else { return false }
        let position = pendingPlaybackSeek.target ?? context.state.latestPosition
        if action == .retry {
            startAVPlaybackFlow(url: context.fmp4URL, at: position, request: context.request,
                initialResolution: false, isFMP4: true)
        } else {
            messageLabel.text = "新しい再生方式で開始できなかったため、従来の方式で再生します。"
            startVLCPlaybackFlow(url: context.fallbackURL, at: position, request: context.request, initialResolution: false)
        }
        return true
    }

    /// 復旧で現在のAV項目を置き換えてよい状態。PiP所有者と停止意図はそのまま保持する。
    private var canRebuildFMP4: Bool {
        canRebuildSession && fmp4OwnerVisible && fmp4ApplicationActive && !isScrubbing
    }

    private func cancelFMP4StartWatchdog() {
        fmp4StartWatchdog?.invalidate()
        fmp4StartWatchdog = nil
        // invalidate前にmainへ届いた発火も、新しい期限/試行へ作用させない。
        fmp4WatchdogGeneration &+= 1
    }

    /// 上流a2de085の「playingでも進まない」開始失敗を、既存の一度だけの復旧へつなぐ。
    /// 一時停止/seek/PiP/非表示中は有効時間を止め、再開時には残り時間だけを予約する。
    private func refreshFMP4StartWatchdog() {
        cancelFMP4StartWatchdog()
        guard let context = fmp4StartContext, let attempt = context.state.currentAttempt,
              let item = player?.currentItem, acceptsPlaybackRequest(context.request),
              context.state.accepts(attempt), !context.state.didPlay else { return }
        let canMonitor = playbackIntentPlaying && !playbackStart.pauseRequested && canRebuildFMP4
        // ready前の保留seekでも開始待機は有界にする。位置差による成功判定だけを止める。
        guard let remaining = fmp4StartContext?.state.observeStartup(attempt,
            position: currentPosition(), now: ProcessInfo.processInfo.systemUptime, canMonitor: canMonitor,
            canConfirmProgress: pendingPlaybackSeek.target == nil) else { return }
        if remaining <= 0 {
            _ = handleFMP4StartFailure(item: item, attempt: attempt)
            return
        }
        let generation = fmp4WatchdogGeneration
        fmp4StartWatchdog = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self, weak item] _ in
            guard let self, let item, self.fmp4WatchdogGeneration == generation,
                  self.player?.currentItem === item,
                  self.fmp4StartContext?.state.accepts(attempt) == true,
                  self.acceptsPlaybackRequest(context.request) else { return }
            self.refreshFMP4StartWatchdog()
        }
    }

    @objc private func fmp4ApplicationWillResignActive() {
        fmp4ApplicationActive = false
        refreshFMP4StartWatchdog()
    }

    @objc private func fmp4ApplicationDidBecomeActive() {
        fmp4ApplicationActive = true
        refreshFMP4StartWatchdog()
        _ = resumeDeferredFMP4Recovery()
    }

    /// 中継の用意を待つ間、知らせ欄が空いていれば読み込み中を出す
    /// (続きから再生する等の知らせが出ているときは、そちらを優先する)。
    private func showStartLoadingMessage() {
        if (messageLabel.text ?? "").isEmpty {
            messageLabel.text = Self.startLoadingMessage
        }
    }

    /// 読み込み中の知らせを出していたら消す
    /// (他の知らせに替わっていたら触らない)。
    private func clearStartLoadingMessage() {
        if messageLabel.text == Self.startLoadingMessage {
            messageLabel.text = nil
        }
    }

    /// 開始の締め (どちらの仕組みでも共通)。
    /// CM自動スキップの判定はこの開始位置から見張り、再生を始めて、
    /// ロック画面の表示とセッション維持を仕掛ける。
    private func finishStartPlayback(at seconds: Double) {
        lastObservedPosition = seconds
        // コメントの表示も開始位置に合わせる (その位置より前のコメントは流さない)。
        commentOverlay.reset(to: seconds)
        // 共通の視聴履歴への書き戻しの起点を、この開始に合わせる
        // (Web 版もプレイヤーを作るたびに30秒の数え直しになる)。
        let now = Date().timeIntervalSince1970
        playbackOpenedAt = now
        lastHistorySyncAt = now
        scheduleHistoryRegistration()
        // 開始の用意を待つ間に止める操作があった場合は、再生を始めず
        // 止めたままにする (画質の切り替えなどで、止めていたものを
        // 作り直したときの扱いを、開始が非同期になっても保つため)。
        if playbackStart.pauseRequested || !playbackIntentPlaying || isScrubbing {
            playbackStart.pauseRequested = false
#if canImport(VLCKit)
            // :start-paused付きの入力を開き、停止したままseek可能なready通知を受ける。
            // playしてから音声を止める方式ではなく、libVLC自身が最初のフレームで停止する。
            vlcPlayer?.play()
#endif
        } else {
            playAtCurrentRate()
        }
        updatePlayPauseIcon()
        updateNowPlaying()
        startKeepAlive()
        scheduleHideControls()
    }

    /// 視聴履歴への登録用タイマー。Web 版と同じく、視聴画面を開いて
    /// 30秒経ったら履歴に登録する (登録自体は WatchedHistorySync 側で、
    /// 既に項目があれば位置の更新として処理される)。
    private func scheduleHistoryRegistration() {
        historyRegistrationTimer?.invalidate()
        historyRegistrationTimer = nil
        guard WatchedHistorySync.isEnabled, !recordingInProgress else { return }
        historyRegistrationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            let current = currentPosition()
            guard current.isFinite else { return }
            runHistorySync(current: current, registerIfNeeded: true)
        }
    }

    /// 指定した画質・区分の組み合わせが H.265 / HEVC かどうか。
    /// 判定は、サーバーへ実際に渡す画質名の組み立て (SettingsStore.apiQuality)
    /// を正本にし、"-hevc" が付く経路かどうかで見る (通信節約がオンのとき)。
    private func isHEVCQuality(_ base: String, profile: PlaybackProfile) -> Bool {
        SettingsStore.shared.apiQuality(base: base, media: .video, profile: profile)
            .contains("-hevc")
    }

    /// AVPlayer 経路の開始 (従来どおり)。
    /// 渡す材料 (asset) は呼び出し側で用意する。中継が必須の方式では、
    /// 中継の URL を非同期に解決してから材料を作って渡す (用意が
    /// できなかった場合は、呼び出し側が失敗として知らせる)。
    private func startAVPlayback(asset: AVURLAsset, at seconds: Double, request: PlaybackRequest,
                                 fmp4Attempt: FMP4PlaybackState.Attempt?) {
        captureController.cancel()
        captionSeekCoordinator.reset()
        playbackReadyForSeek = false
        captionOverlayView.setImage(nil)
        let item = AVPlayerItem(asset: asset)
        // 字幕データの受け取り口を、この再生項目へ付ける。
        attachCaptionMetadataOutput(to: item, at: seconds)
        // 再生が終わったことを知る見張り (次の話の自動再生と、
        // 追いかけ再生の先端到達の扱いに使う)。項目を作り直すたびに
        // 見張りも付け替える。
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            guard let self, let item, self.player?.currentItem === item,
                  self.acceptsPlaybackRequest(request) else { return }
            self.handlePlaybackEnded()
        }
        // 読み込みに失敗したら、真っ黒のまま無言にせず、その旨を表示する。
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                // 実行される時点で今の再生項目が別のものに替わっていたら、
                // 古い項目の失敗を今の再生の失敗として表示しない。
                guard let self, !self.didLeaveScreen,
                      self.player?.currentItem === item,
                      self.acceptsPlaybackRequest(request) else { return }
                if item.status == .readyToPlay {
                    if let fmp4Attempt, self.fmp4StartContext?.state.accepts(fmp4Attempt) != true { return }
                    self.playbackReadyForSeek = true
                    self.applyPendingPlaybackSeek()
                    self.refreshFMP4StartWatchdog()
                } else if item.status == .failed {
                    if self.handleFMP4StartFailure(item: item, attempt: fmp4Attempt) { return }
                    self.messageLabel.text = "再生を開始できませんでした。"
                }
            }
        }
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            // 既定の動きでは、止まりにくくなるまで映像がたまるのを
            // 待ってから再生が始まるため、出だしが遅くなる。届いた
            // 分から再生を始め、貯めは再生と同時に進める形にする
            // (貯めの量そのものは変えていない)。
            newPlayer.automaticallyWaitsToMinimizeStalling = false
            newPlayer.actionAtItemEnd = .pause
            player = newPlayer
            let layer = AVPlayerLayer(player: newPlayer)
            layer.videoGravity = .resizeAspect
            layer.frame = surfaceView.bounds
            // 音声のみの最中に仕組みが切り替わって作り直された場合も、
            // 映像を出したままにしない (切り替え側が隠すのは既存の層だけのため)。
            layer.isHidden = audioOnly
            surfaceView.layer.addSublayer(layer)
            playerLayer = layer
            // 字幕の重ね物は、後から足した映像の層より上に保つ。
            surfaceView.bringSubviewToFront(captionOverlayView)
            timeObserver = newPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                queue: .main
            ) { [weak self] _ in
                self?.updateProgress()
            }
        }
        timeControlObservation?.invalidate()
        if let currentPlayer = player {
            timeControlObservation = currentPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self, weak currentPlayer, weak item] _, _ in
                DispatchQueue.main.async {
                    guard let self, let currentPlayer, let item, self.player === currentPlayer,
                          currentPlayer.currentItem === item,
                          self.acceptsPlaybackRequest(request) else { return }
                    // failed済み項目や旧attemptのplaying通知を再試行成功として扱わない。
                    if let fmp4Attempt, self.fmp4StartContext?.state.accepts(fmp4Attempt) != true { return }
                    self.updatePlayPauseIcon()
                    self.updateNowPlaying()
                    defer { self.refreshFMP4StartWatchdog() }
                    if currentPlayer.timeControlStatus == .playing {
                        self.playbackDidStart = true
                        if self.messageLabel.text == "再生を開始できませんでした。"
                            || self.messageLabel.text == Self.fmp4RetryMessage {
                            self.messageLabel.text = nil
                        }
                        if let pending = self.pendingQualityWriteBack, pending == self.quality {
                            SettingsStore.shared.setStreamingQuality(pending, media: .video, profile: self.profile)
                            self.pendingQualityWriteBack = nil
                        }
                    }
                }
            }
        }
        if seconds > 0 {
            // 初期位置合わせの待機も開始監視の対象。ただし完了前の位置差で成功とは判定しない。
            let startupSeek = fmp4StartContext?.state.beginSeek(to: seconds, initial: true)
            player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self, weak item] completed in
                DispatchQueue.main.async {
                    guard let self, let item, let startupSeek, let fmp4Attempt,
                          self.player?.currentItem === item,
                          self.fmp4StartContext?.state.accepts(fmp4Attempt) == true,
                          self.acceptsPlaybackRequest(request) else { return }
                    self.fmp4StartContext?.state.completeSeek(startupSeek, completed: completed, position: self.currentPosition(),
                        now: ProcessInfo.processInfo.systemUptime)
                    self.refreshFMP4StartWatchdog()
                }
            }
        }
        if let layer = playerLayer {
            pipController?.dispose()
            let pip = makePiPController()
            pipController = pip
            pip.configureAVPlayerLayer(layer)
        }
    }

#if canImport(VLCKit)
    /// VLCKit 経路の開始。プレイリストを VLC に渡す
    /// (TS に入った HEVC を読み解けるのはこちら)。
    /// 描き先はPiPコントローラが保ち、通常/全画面は同じsurfaceViewへ表示する。
    ///
    /// 渡す URL は、アプリ内の中継 (StreamRelayServer) 経由にする。
    /// VLCKit には再生の取りに行く処理へ任意のヘッダーを付ける公式の
    /// 入口が無く、Cloudflare Access の合言葉が HLS の分割ファイルに
    /// 付かないため、外回線では開始すらできない (0.24 で実機確認済み)。
    /// 中継が合言葉付きで取りに行き、プレイリスト内の URL も中継経由に
    /// 書き換える。中継の URL の解決は、呼び出し側 (startPlayback) が
    /// 非同期に行ってから渡す。中継が必須でない構成で中継が使えない
    /// ときは元の URL (url) に落ち、中継が必須の構成で用意ができて
    /// いないときは、呼び出し側が失敗として知らせる (ここへは来ない)。
    /// メディアオプションの ":http-header" は、中継を使わない場合の
    /// 補いとして残す (効くかどうかは libVLC 側の実装次第で、単独では
    /// 分割ファイルまで届かないことが分かっている)。
    private func startVLCPlayback(url: URL, relayedURL: URL?, at seconds: Double) -> Bool {
        // 同じHEVC経路の作り直しはteardownVLCPlaybackを通らないため、旧要求をここでも解放する。
        captionSeekCoordinator.reset()
        captionEngine.resetForNewPlayback(at: seconds)
        captionOverlayView.setImage(nil)
        teardownAVPlayback()
        let oldPiP = pipController
        pipController = nil
        oldPiP?.retireRenderer()
        if let oldPlayer = vlcPlayer {
            vlcPlayer = nil
            oldPlayer.delegate = nil
            vlcStateObserver = nil
            stopVLCPlayerInBackground(oldPlayer, drawable: oldPiP)
        } else {
            oldPiP?.dispose()
        }
        vlcTimeTimer?.invalidate()
        vlcStartWatchdog?.invalidate()
        vlcStartWatchdog = nil
        vlcDidStartPlaying = false
        lastVLCPosition = seconds.isFinite ? max(0, seconds) : 0
        vlcResumeAfterSeek = false
        let vlc = VLCMediaPlayer()
        let observer = VLCStateObserver { [weak self, weak vlc] state in
            guard let vlc else { return }
            self?.handleVLCState(state, source: vlc)
        }
        vlcStateObserver = observer
        vlc.delegate = observer
        // PiPの描画先を保持し、通常/全画面の切替では付け替えない。
        let pip = makePiPController()
        pipController = pip
        vlc.drawable = pip
        guard let media = VLCMedia(url: relayedURL ?? url) else { return false }
        // 受け取りの溜めは録画用の多めの値にする (先読みを厚くして
        // 止まりにくくするため。値の根拠は vlcRecordedNetworkCaching の定義側)。
        media.addOption(":network-caching=\(Self.vlcRecordedNetworkCaching)")
        // VLCKit4a26固定libVLC(f7caf7922)のinput.cはstart-pausedを入力開始時に適用する。
        // 一時停止中の画質変更でも入力を解析し、.paused通知で保留seekを反映できるようにする。
        if playbackStart.pauseRequested || !playbackIntentPlaying || isScrubbing {
            media.addOption(":start-paused")
        }
        // 続きの開始位置は、再生が始まってから移るのではなく、最初から
        // 再生部品へ渡す (先頭から一瞬再生されてから飛ぶ、という
        // 動きがなくなる)。字幕は、中継が区切りファイルから取り出す
        // 映像の時刻印で位置を合わせる作りのため、途中から始めても
        // 合い方は崩れない (プレイリストは今までどおり先頭から
        // 中継を通り、区切りの長さも全部渡る)。
        if seconds > 0 {
            media.addOption(":start-time=\(seconds)")
        }
        if audioOnly {
            media.addOption(":no-video")
        }
        // 認証の合言葉をヘッダーとして付ける
        // (中継を使わない場合の補い。上のコメント参照)。
        for (key, value) in SettingsStore.shared.serverAuthHeaders {
            media.addOption(":http-header=\(key): \(value)")
        }
        vlc.media = media
        vlcPlayer = vlc
        // 字幕: 蓄えを空にし直し、アプリ内の中継へ抜き取り口を登録する。
        // 中継は、プレイリストを通すときに区切りの長さを、区切りファイルを
        // 通すときに中身から取り出した字幕の包みを、こちらへ渡してくれる
        // (再生そのものには触れない)。渡し先ではメイン側で受ける。
        let captionVideoID = program.id
        let captionPlaybackGeneration = captionEngine.playbackGeneration
        StreamRelayServer.shared.setCaptionTap(StreamRelayServer.CaptionTap(
            pathMarker: "/api/streams/video/\(captionVideoID)/",
            onPlaylist: { [weak self] durations in
                DispatchQueue.main.async {
                    guard let self, self.captionEngine.playbackGeneration == captionPlaybackGeneration else { return }
                    self.captionEngine.ingestRelayPlaylist(durations: durations)
                }
            },
            onSegment: { [weak self] sequence, packets, videoFirstPTS, complete in
                DispatchQueue.main.async {
                    guard let self, self.captionEngine.playbackGeneration == captionPlaybackGeneration else { return }
                    self.captionEngine.ingestRelaySegment(
                        sequence: sequence, packets: packets, videoFirstPTS: videoFirstPTS, complete: complete)
                    self.refreshCaptions()
                }
            }))
        // 開始の見張り: 30秒たっても再生が始まらなければ、その旨を表示する
        // (エラー状態になった場合はデリゲート側でもっと早く表示する)。
        // サーバーが混んでいて最初の分割ファイルが遅いことがあるため、
        // 短すぎる見張りは誤って表示してしまう。30秒はその境目。
        vlcStartWatchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self, let vlcPlayer = self.vlcPlayer, !self.vlcDidStartPlaying else { return }
            if vlcPlayer.state != .playing && vlcPlayer.state != .paused {
                self.messageLabel.text = "再生を開始できませんでした。"
            }
        }
        // 開始位置の控え (デリゲート側で、":start-time" の指定が効いて
        // いなかった場合の受け皿として使う)。
        vlcPendingStartPosition = seconds > 0 ? seconds : nil
        // 前の再生で保留していた開始位置の補正は、新しい開始では
        // 意味を持たないため破棄する。
        vlcPendingStartCorrection = nil
        // 進み具合の見張りは 0.5 秒ごとのタイマーで行う
        // (AVPlayer の定期観測にあたる)。
        vlcTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
        return true
    }

    /// VLC の再生部品を止める。止める呼び出しは、終わるまで呼び出し側の
    /// 処理が返ってこない形のため、画面の切り替わりや作り直しの最中など
    /// 画面側の処理の中で呼ぶと、その間ずっと画面が固まってしまう。
    /// 部品への参照を呼び出し側で先に手放したうえで、止める処理自体は
    /// 裏へ渡し、画面側はすぐ返るようにする。
    private func stopVLCPlayerInBackground(_ player: VLCMediaPlayer, drawable: PlaybackPiPController?) {
        // libVLCのdrawable問い合わせはmainへ同期するため、mainでstop完了を待たない。
        // 旧drawableはstop中も生存させ、旧通知はdelegateを外して無効化しておく。
        DispatchQueue.global(qos: .userInitiated).async {
            player.stop()
            DispatchQueue.main.async {
                drawable?.dispose()
                withExtendedLifetime(player) {}
            }
        }
    }

    /// VLCKit 経路の後片付け。
    private func teardownVLCPlayback() {
        captionSeekCoordinator.reset()
        // 字幕の抜き取り口も解除する (中継は他の再生と共用ため、
        // 残しておくと関係ない経路でも読み取りが続いてしまう)。
        StreamRelayServer.shared.setCaptionTap(nil)
        vlcTimeTimer?.invalidate()
        vlcTimeTimer = nil
        vlcStartWatchdog?.invalidate()
        vlcStartWatchdog = nil
        vlcPendingStartPosition = nil
        vlcPendingStartCorrection = nil
        let oldPiP = pipController
        pipController = nil
        oldPiP?.retireRenderer()
        if let oldPlayer = vlcPlayer {
            vlcPlayer = nil
            oldPlayer.delegate = nil
            vlcStateObserver = nil
            stopVLCPlayerInBackground(oldPlayer, drawable: oldPiP)
        } else {
            oldPiP?.dispose()
        }
        vlcResumeAfterSeek = false
    }

    /// VLC が読み取った全体の長さ (秒)。取れないときは NaN。
    private var vlcLengthSeconds: Double {
        guard let vlcPlayer, let media = vlcPlayer.media else { return .nan }
        let ms = media.length.intValue
        return ms > 0 ? Double(ms) / 1000 : .nan
    }
#endif

    /// 字幕データの受け取り口を、AVPlayer の再生項目へ付ける。
    /// 届いた包みはファイル末尾の受け取り側で字幕の本体へ渡す。
    /// 再生を作り直すたびに、字幕の蓄えも空にし直す。
    private func attachCaptionMetadataOutput(to item: AVPlayerItem, at seconds: Double) {
        captionEngine.resetForNewPlayback(at: seconds)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        captionMetadataOutput = output
    }

    /// AVPlayer 経路の後片付け。
    private func teardownAVPlayback() {
        cancelFMP4StartWatchdog()
        if player != nil { pipController?.dispose(); pipController = nil }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        // 字幕データの受け取り口も外す (蓄えは次の再生の開始で空にする)。
        captionMetadataOutput = nil
    }

    /// 別の画面へ進んで戻ってきたときに、片付け済みの再生を作り直す。
    /// 離れる直前の位置から再開し、離れる前に止めていた場合は
    /// 作り直したあとも止めたままにする。コメントの流れる表示と
    /// ロック画面の受け口も、画面を開いたときと同じように用意し直す。
    private func resumePlaybackAfterReturn() {
        commentOverlay.start()
        beginNowPlaying()
        // 追いかけ再生の先端追従は、離れるときに止めている。戻ってきたら
        // 最新の録画状態を取り直し、まだ録画中なら追従を復旧する。
        // 離れている間に録画が終わっていたら、通常の録画へ移行する。
        let generation = playbackGeneration
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            let latest = await APIClient.shared.fetchVideo(videoID: videoID)
            // 取り直しの間にまた画面を離れていたら、何もしない
            // (離れた先の状態は、戻ったときの取り直しが扱う)。
            guard !self.didLeaveScreen, self.playbackGeneration == generation else { return }
            if let latest {
                if latest.isRecording {
                    if self.recordingInProgress {
                        self.chaseFollowActive = true
                        self.chaseLastStatusPollAt = Date().timeIntervalSince1970
                        self.chaseStallSince = 0
                    }
                } else if self.recordingInProgress {
                    self.handleRecordingFinished()
                }
            } else if self.recordingInProgress {
                // 状態を取り直せなかったときは、録画中だった見込みの
                // まま追従を暫定で戻す。そのままでは通常の状態確認が
                // 追従を前提にしていて二度と試されず、追従が戻らない
                // ままになるため。次の状態確認 (間隔を待たずに行う)
                // で、録画が終わっていれば通常の録画へ移行する。
                self.chaseFollowActive = true
                self.chaseLastStatusPollAt = 0
                self.chaseStallSince = 0
            }
        }
        startPlayback(at: positionBeforeLeave)
        if !wasPlayingBeforeLeave {
            pauseEngine()
            updatePlayPauseIcon()
        }
        // おやすみタイマー (分数指定) の刻みが止まっていたら回し直す。
        if sleepTimerRemainingSeconds != nil, sleepTimerTicker == nil {
            sleepTimerTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tickSleepTimer()
            }
        }
    }

    private func stopPlayback() {
        cancelFMP4Start()
        playbackStart.invalidate()
        clearStartLoadingMessage()
        captureController.cancel()
        // VLCの描き先はteardownVLCPlaybackがstop完了まで保持する。
#if canImport(VLCKit)
        let retainsVLCDrawable = vlcPlayer != nil
#else
        let retainsVLCDrawable = false
#endif
        if !retainsVLCDrawable {
            let pip = pipController
            pipController = nil
            pip?.dispose()
        }
        playbackGeneration += 1
        captionEngine.resetForNewPlayback()
        captionOverlayView.setImage(nil)
        commentOverlay.stop()
        cancelAutoplayCountdown()
        fastSeekBackController.invalidate()
        fastSeekForwardController.invalidate()
        chaseFollowActive = false
        stopSleepTimerTicker()
        stopKeepAlive()
        keepAliveState.stop()
        pendingPlaybackSeek.cancel()
        playbackReadyForSeek = false
        seekDisplay.clear()
        historyRegistrationTimer?.invalidate()
        historyRegistrationTimer = nil
        // 離れるときは最後の再生位置を報告する (Web 版が破棄時に報告するのと同じ)。
        if hasActiveEngine {
            let current = currentPosition()
            // 戻ってきたときの作り直し用に、位置と再生中だったかを控える。
            if current.isFinite {
                positionBeforeLeave = current
                wasPlayingBeforeLeave = isCurrentlyPlaying()
            }
            // 送るのは、いまの位置と、まだ送れていない到達最大位置の
            // 大きい方。定期報告が失敗したあと巻き戻して離れても、
            // 到達した最大位置が失われないようにするため。
            let reportTarget = max(current, maxUnreportedPosition)
            if current.isFinite, reportTarget > lastReportedPosition {
                // 送れたときだけ「報告済みの位置」を進める。定期報告が
                // 失敗していた場合も、ここで最後の位置が送り直される。
                let videoID = program.id
                Task { [weak self] in
                    if (try? await APIClient.shared.reportWatched(
                        videoID: videoID, position: reportTarget)) != nil {
                        guard let self else { return }
                        self.lastReportedPosition = max(self.lastReportedPosition, reportTarget)
                        if self.maxUnreportedPosition <= reportTarget {
                            self.maxUnreportedPosition = -1
                        }
                    }
                }
            }
            // 共通の視聴履歴にも最後の位置を書き戻す (Web 版が破棄時に
            // 履歴の位置を更新するのと同じ)。視聴状態への報告とは別系統。
            if current.isFinite, WatchedHistorySync.isEnabled, !recordingInProgress {
                // まだ送られていない古い定期保存が、この最後の保存より
                // 後から送られて上書きしないよう、世代を進めて無効にする。
                historySyncEpoch += 1
                let videoID = program.id
                let registerIfNeeded = Date().timeIntervalSince1970 - playbackOpenedAt >= 30
                Task {
                    await WatchedHistorySync.syncPosition(
                        videoID: videoID, position: current, registerIfNeeded: registerIfNeeded)
                }
            }
        }
#if canImport(VLCKit)
        teardownVLCPlayback()
#endif
        teardownAVPlayback()
        NowPlayingManager.shared.end(owner: self)
    }

    /// 再生中は定期的に keep-alive を送り、サーバー側のセッションを維持する。
    /// 最初の1回は少し置いてから送る。開始直後は、再生部品がまだ再生
    /// リストを取りに行っておらず、サーバー側にセッションができて
    /// いないため、その時点で送っても無効になる。以前は開始直後＋
    /// 10秒ごとで、実質の初回がサーバー側の持ち時間 (約10秒) とほぼ
    /// 重なり、サーバー側の用意が遅れたときにセッションが先に切れて
    /// 再生が固まっていた。間隔は持ち時間の半分 (5秒) にし、1回の
    /// 失敗や遅れがあっても、次が持ち時間のうちに届くようにしている。
    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveFirstTimer = Timer.scheduledTimer(
            withTimeInterval: Self.keepAliveFirstDelay, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.sendKeepAlive()
            self.keepAliveTimer = Timer.scheduledTimer(
                withTimeInterval: Self.keepAliveInterval, repeats: true
            ) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }

    /// セッション維持の合図を止める。
    private func stopKeepAlive() {
        keepAliveFirstTimer?.invalidate()
        keepAliveFirstTimer = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private var canRebuildSession: Bool {
        // PiP所有中は描き先とownerを失わない。復帰して表示可能になってから再構築する。
        !didLeaveScreen && pipController?.isActive != true && pipController?.isPending != true
            && viewIfLoaded?.window != nil
    }

    /// 開始専用の復旧とセッション全体の復旧で、同じ項目を二重に作り直さない。
    /// 通信は続け、fMP4の進行確認かVLC復帰が済むまでセッション再構築だけを保留する。
    private var canRecoverKeepAlive: Bool {
        canRebuildSession && !routeResolutionPending && !playbackStart.inFlight
            && (fmp4StartContext?.state.didPlay != false)
    }

    private func sendKeepAlive() {
        let context = keepAliveContext
        guard !didLeaveScreen, let request = keepAliveState.request(context: context) else { return }
        let videoID = program.id
        Task { [weak self] in
            let accepted = await APIClient.shared.keepAlive(
                videoID: videoID, quality: context.quality, profile: context.profile, sessionID: context.sessionID)
            // 通信の復帰先を明示し、再生UI・世代・タイマーを同じmain上で扱う。
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didLeaveScreen else { return }
                let result = self.keepAliveState.complete(request, context: self.keepAliveContext,
                    accepted: accepted, canRecover: self.canRecoverKeepAlive)
                switch result {
                case .recover: self.rebuildDeadSession()
                case .disconnected:
                    self.messageLabel.text = self.playbackDidStart
                        ? "再生中にサーバーとの接続が切れました。" : "再生を開始できませんでした。"
                default: break
                }
            }
        }
    }

    private func resumeDeferredSessionRecovery() {
        if resumeDeferredFMP4Recovery() { return }
        guard keepAliveState.takeDeferredRecovery(context: keepAliveContext, canRecover: canRecoverKeepAlive) else { return }
        rebuildDeadSession()
    }

    /// 切れたセッションを作り直して、再生をやり直す。
    /// 位置は、いまの再生位置 (開始前なら、利用者が指定した移動先が
    /// あればそちら) を使う。止めていた場合は、作り直した後も止めた
    /// ままにする。
    private func rebuildDeadSession() {
        let intentPlaying = playbackIntentPlaying
        var pendingPosition = fmp4StartContext.flatMap { !$0.state.didPlay ? $0.state.latestPosition : nil }
#if canImport(VLCKit)
        // VLC復帰の最初のready前も、まだ0の実時計で指定済みの開始位置を失わない。
        if pendingPosition == nil, !playbackReadyForSeek {
            pendingPosition = vlcPendingStartCorrection ?? vlcPendingStartPosition
        }
#endif
        let position = pendingPlaybackSeek.target ?? pendingPosition ?? currentPosition()
        pendingPlaybackSeek.cancel()
        // 古いセッション向けの合図は止める (新しい開始の締めで、新しい
        // セッション向けに仕掛け直される)。
        stopKeepAlive()
        sessionID = UUID().uuidString
        // 前の失敗表示は消し、開始側の読み込み表示に任せる。
        messageLabel.text = nil
        startPlayback(at: position.isFinite ? position : 0, isSessionRecovery: true)
        if !intentPlaying {
            pauseEngine()
            updatePlayPauseIcon()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 原則は16:9と情報欄の余地で決める。狭幅では下記の操作領域を優先する。
        // 映像自体は resizeAspect で全体が収まるため、切れることはない。
        if let heightConstraint = videoHeightConstraint {
            let ideal = view.bounds.width * 9.0 / 16.0
            let available = view.bounds.height
                - view.safeAreaInsets.top
                - view.safeAreaInsets.bottom
                - 120
            // 波形の有無によって映像や番組情報の領域を変えない。
            let target = max(176, min(ideal, available))
            if abs(heightConstraint.constant - target) > 0.5 {
                heightConstraint.constant = target
            }
        }
        // AVの映像も同じ枠を使い、回転・全画面の制約更新後の寸法へ合わせる。
        playerLayer?.frame = surfaceView.bounds
        bandView.setNeedsDisplay()
    }

    // MARK: - 再生の仕組みによらない読み取り口

    /// どちらかの仕組みで再生の用意ができているか。
    private var hasActiveEngine: Bool {
        if player != nil { return true }
#if canImport(VLCKit)
        if vlcPlayer != nil { return true }
#endif
        return false
    }

    /// 現在の再生位置 (秒)。
    private func currentPosition() -> Double {
#if canImport(VLCKit)
        if let vlcPlayer {
            let ms = vlcPlayer.time.intValue
            // 4系では終端で時計が0へ戻ることがあるため、最終表示・保存に直前位置を使う。
            if vlcPlayer.state == .stopped { return lastVLCPosition }
            let position = ms > 0 ? Double(ms) / 1000 : 0
            lastVLCPosition = position
            return position
        }
#endif
        return player?.currentTime().seconds ?? 0
    }

    /// いま再生中かどうか。
    private func isCurrentlyPlaying() -> Bool {
#if canImport(VLCKit)
        if let vlcPlayer { return vlcPlayer.isPlaying }
#endif
        return (player?.rate ?? 0) != 0
    }

    /// ロック画面の表示に渡す再生速度 (止まっているときは 0)。
    private func currentRateValue() -> Double {
#if canImport(VLCKit)
        if let vlcPlayer {
            return vlcPlayer.isPlaying ? Double(vlcPlayer.rate) : 0
        }
#endif
        return Double(player?.rate ?? 0)
    }

    /// 再生側が読み取った全体の長さ (秒)。定まらないときは NaN
    /// (録画中の追いかけ再生では HLS 側の長さが定まらないため)。
    private var currentItemDurationSeconds: Double {
#if canImport(VLCKit)
        if vlcPlayer != nil { return vlcLengthSeconds }
#endif
        return player?.currentItem?.duration.seconds ?? .nan
    }

    // MARK: - 進み具合の表示

    /// シークバーの最大値。HLS 側の長さが取れればそれ、取れなければ番組の長さを使う
    /// (録画中の追いかけ再生では HLS 側の長さが定まらないため)。
    private var effectiveDuration: Double {
        let d = currentItemDurationSeconds
        if d.isFinite, d > 0 {
            return d
        }
        return program.duration
    }

    /// 表示を飛び先に合わせる控えが効いている間は、その位置を返す。
    /// 再生部品の実位置が飛び先へ近づいたら (または待ちの期限が
    /// 過ぎたら) 控えを解いて nil を返す (実位置を表示する)。
    private func activeSeekDisplayTarget(realPosition: Double) -> Double? {
        seekDisplay.activeTarget(realPosition: realPosition)
    }

    private func updateProgress() {
        updateCaptureControls()
        pipController?.invalidatePlaybackState()
        updatePiPButton()
        guard hasActiveEngine else { return }
        refreshFMP4StartWatchdog()
        let current = currentPosition()
        if current.isFinite {
            // 移動先は表示専用。字幕・履歴・自動スキップには下の実位置currentを渡す。
            let displayPosition = (!playbackReadyForSeek ? pendingPlaybackSeek.target : nil)
                ?? activeSeekDisplayTarget(realPosition: current) ?? current
            currentTimeLabel.text = TimeFormat.hms(displayPosition)
            if !isScrubbing {
                let duration = effectiveDuration
                seekSlider.value = duration > 0 ? Float(displayPosition / duration) : 0
            }
            applyCMAutoSkipIfNeeded(current: current)
            applyDigestSkipIfNeeded(current: current)
            updateHighlightReel(current: current)
            updateChaseFollow(current: current)
            updateCommentListFollow(current: current)
            reportWatchedPositionIfNeeded(current: current)
            syncWatchedHistoryIfNeeded(current: current)
            refreshCaptions()
        }
        let duration = effectiveDuration
        let itemDuration = currentItemDurationSeconds
        durationLabel.text = recordingInProgress && !itemDuration.isFinite
            ? "録画中"
            : TimeFormat.hms(duration)
        bandView.duration = duration
        bandView.setNeedsDisplay()
        updatePlayPauseIcon()
        updateNowPlaying()
    }

    /// CM自動スキップ。再生中に CM 区間の開始を跨いだ瞬間だけ、区間の終わりへ飛ばす
    /// (改造側の仕様確認済み)。シークで区間の真ん中へ入った直後や、区間の中から
    /// 再開した場合は発動しない。番組最後の区間への特別扱いもしない。
    private func applyCMAutoSkipIfNeeded(current: Double) {
        let previous = lastObservedPosition
        lastObservedPosition = current
        guard SettingsStore.shared.cmAutoSkip,
              isCurrentlyPlaying(), !isScrubbing else { return }
        for section in program.cmSections {
            // 開始を跨いでいて、区間の中にいて、位置の進みが連続している
            // (シークの飛びではない) ときだけ発動する。0.5秒間隔のチェックで
            // 速度2倍でも進みは約1秒なので、2秒を上限にしている。
            if previous < section.start_time,
               current >= section.start_time,
               current < section.end_time,
               current - previous <= 2.0 {
                seek(to: section.end_time)
                break
            }
        }
    }

    /// 共通の視聴履歴への定期的な書き戻し。Web 版のリズムに合わせ、
    /// 再生中は10秒間隔で位置を更新する (登録は30秒後のタイマー側)。
    /// 30秒より前は、履歴に項目がある場合だけ更新し、無い場合は
    /// 手順側で送らずに終わる。失敗しても再生は続ける (利用者には見せない)。
    private func syncWatchedHistoryIfNeeded(current: Double) {
        guard WatchedHistorySync.isEnabled, !recordingInProgress else { return }
        guard isCurrentlyPlaying() else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastHistorySyncAt >= 10 else { return }
        runHistorySync(current: current, registerIfNeeded: now - playbackOpenedAt >= 30)
    }

    /// 書き戻しを1回分動かす。動いている間は重ねて動かさない
    /// (次の間隔で、その時点の位置で送り直される)。
    /// lastHistorySyncAt は、動かした時点で進める。
    private func runHistorySync(current: Double, registerIfNeeded: Bool) {
        guard !historySyncInFlight else { return }
        historySyncInFlight = true
        lastHistorySyncAt = Date().timeIntervalSince1970
        let videoID = program.id
        let epoch = historySyncEpoch
        Task { [weak self] in
            guard let self else { return }
            // 画面を離れるときの最後の保存で世代が進んでいたら、この
            // 古い位置の保存は送らない (保存自体は共通の順番待ちで
            // 直列化されているが、順番待ちに入る前の取りこぼしを防ぐ)。
            if self.historySyncEpoch == epoch {
                await WatchedHistorySync.syncPosition(
                    videoID: videoID, position: current, registerIfNeeded: registerIfNeeded)
            }
            self.historySyncInFlight = false
        }
    }

    /// 視聴進捗の定期報告。Web 版の報告の間隔に合わせる
    /// (10秒以上進んだら最大5秒に1回、それ以外も20秒に1回は送る)。
    /// サーバーは到達した最大位置だけを残すので、戻し見をしても状態は後退しない。
    private func reportWatchedPositionIfNeeded(current: Double) {
        // 到達した最大位置は、送れたかどうかによらず控えておく。
        // 報告が失敗したあと巻き戻すと、いまの位置だけでは最大位置が
        // 分からなくなり、二度と送られなくなってしまうため。
        if current.isFinite, current > maxUnreportedPosition {
            maxUnreportedPosition = current
        }
        // 送る位置は、いまの位置ではなく、まだ送れていない最大位置。
        let target = maxUnreportedPosition
        guard target > lastReportedPosition else { return }
        let now = Date().timeIntervalSince1970
        let advanced = target - lastReportAttemptPosition
        let elapsed = now - lastReportedAt
        guard (advanced >= 10 && elapsed >= 5) || (advanced > 0 && elapsed >= 20) else { return }
        lastReportAttemptPosition = target
        lastReportedAt = now
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            if (try? await APIClient.shared.reportWatched(videoID: videoID, position: target)) != nil {
                // 送れたときだけ「報告済みの位置」を進める。失敗した
                // 位置は報告済みにならないため、次回の報告や画面を
                // 離れるときの最後の報告で送り直される。
                self.lastReportedPosition = max(self.lastReportedPosition, target)
                if self.maxUnreportedPosition <= target {
                    self.maxUnreportedPosition = -1
                }
            } else {
                // 失敗したら、試みた位置を送れた位置まで戻しておく。
                // そうしないと「進んだ量」の判定で進んだことになり、
                // 間隔が開いても同じ位置が送り直されなくなる。
                self.lastReportAttemptPosition = self.lastReportedPosition
            }
        }
    }

    private var isPlayingForControls: Bool {
        // 位置表示とアイコンだけを再生意図へ合わせる。実再生状態の読み取りは変更しない。
        (playbackStart.inFlight || routeResolutionPending || fmp4StartContext?.state.awaitingRecovery == true)
            ? (playbackIntentPlaying && !playbackStart.pauseRequested)
            : (playbackIntentPlaying && (isCurrentlyPlaying()
                || activeSeekDisplayTarget(realPosition: currentPosition()) != nil))
    }

    private func updatePlayPauseIcon() {
        let playing = isPlayingForControls
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        playPauseButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill", withConfiguration: config),
            for: .normal
        )
        // 止まっている間は操作帯を出したままにする (Web 版も停止中は消えない)。
        if !playing {
            setControlsVisible(true)
        }
    }

    // MARK: - 操作帯の出し入れ

    @objc private func toggleControls() {
        setControlsVisible(!controlsVisible)
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        // 進み具合の更新のたびに呼ばれるため、状態が変わるときだけ動かす。
        guard visible != controlsVisible else { return }
        controlsVisible = visible
        setNeedsStatusBarAppearanceUpdate()
        navigationController?.setNeedsStatusBarAppearanceUpdate()
        mainTabBarController?.setNeedsStatusBarAppearanceUpdate()
        UIView.animate(withDuration: 0.25) {
            self.overlayHeader.alpha = visible ? 1 : 0
            self.overlayTopGradient.alpha = visible ? 1 : 0
            self.bottomGradient.alpha = visible ? 1 : 0
            self.controlsContainer.alpha = visible ? 1 : 0
            self.centerTransport.alpha = visible ? 1 : 0
        }
        overlayHeader.isUserInteractionEnabled = visible
        controlsContainer.isUserInteractionEnabled = visible
        centerTransport.isUserInteractionEnabled = visible
        if !visible {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    /// 再生中だけ、しばらく触らなければ操作帯を消すタイマーを仕掛け直す。
    private func scheduleHideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard isCurrentlyPlaying(), !isScrubbing, presentedViewController == nil, playerSettingsPanel == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.setControlsVisible(false)
        }
    }

    // MARK: - 拡張版の再生画面まわりの機能

    /// 映像の上に知らせを出して、少し経ったら消す (生放送一覧の知らせと同じ出方)。
    private func showPlayerNotice(_ text: String) {
        playerNoticeLabel.text = text
        playerNoticeDismissWork?.cancel()
        UIView.animate(withDuration: 0.2) { self.playerNoticeView.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.playerNoticeView.alpha = 0 }
        }
        playerNoticeDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    // MARK: 前の話・次の話

    /// 前の話・次の話の有無を、単体取得の応答で確かめる
    /// (改造サーバーは単体取得の応答にだけ前後の ID を付ける)。
    /// ボタンは、有ることが分かったものだけ出す。
    private func loadEpisodeNeighbors() {
        let videoID = program.id
        Task { [weak self] in
            guard let self,
                  let latest = await APIClient.shared.fetchVideo(videoID: videoID) else { return }
            self.previousEpisodeID = latest.previous_episode_id
            self.nextEpisodeID = latest.next_episode_id
            self.prevEpisodeButton.isHidden = latest.previous_episode_id == nil
            self.nextEpisodeButton.isHidden = latest.next_episode_id == nil
            self.buttonsFlowView.setNeedsLayout()
        }
    }

    @objc private func goToPreviousEpisode() {
        navigateToEpisode(id: previousEpisodeID)
    }

    @objc private func goToNextEpisode() {
        navigateToEpisode(id: nextEpisodeID)
    }

    /// 指定した録画の再生画面へ移る。番組データを取り直してから開く
    /// (開き先でも前後の確認などが要るため)。
    private func navigateToEpisode(id: Int?) {
        guard let id, !isNavigatingToEpisode else { return }
        // 手で別の話へ移る操作でも「終わった」出来事は古くなる
        // (取り込み中の次の話で自動再生を始めないため)。
        playbackEndEventID += 1
        // 移動が終わるまでは前後のボタンを押せないようにし、連打で
        // 複数の再生画面が積まれないようにする。
        isNavigatingToEpisode = true
        prevEpisodeButton.isEnabled = false
        nextEpisodeButton.isEnabled = false
        let generation = playbackGeneration
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isNavigatingToEpisode = false
                self.prevEpisodeButton.isEnabled = true
                self.nextEpisodeButton.isEnabled = true
            }
            if let target = await APIClient.shared.fetchVideo(videoID: id) {
                // 取得の間に画面を離れていたら、古い画面からは移らない。
                guard !self.didLeaveScreen, self.playbackGeneration == generation else { return }
                self.navigationController?.pushViewController(
                    PlayerViewController(program: target), animated: true)
            } else if !self.didLeaveScreen {
                self.messageLabel.text = "番組を取得できませんでした。"
            }
        }
    }

    // MARK: マイリスト

    /// マイリストボタンの文面と印を、いまの登録状態に合わせる
    /// (Web 版パネルと同じ: 追加済みはチェックの印で「マイリストに追加済み」、
    /// 未追加は＋の印で「マイリストに追加」)。
    private func updateMylistButtonTitle() {
        let inMylist = SyncedSettingsStore.shared.isInMylist(videoID: program.id)
        mylistButton.setTitle(inMylist ? "マイリストに追加済み" : "マイリストに追加", for: .normal)
        mylistButton.setImage(
            UIImage(systemName: inMylist ? "checkmark" : "plus",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)),
            for: .normal)
        mylistButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
    }

    /// マイリストへの追加・削除を切り替える。マイリストは視聴履歴と揃えて、
    /// ログイン中かつ「設定をデバイス間で同期する」がオンのときだけ働く。
    /// その条件を満たさないときは切り替えず、知らせで案内する。
    @objc private func toggleMylist() {
        guard SyncedSettingsStore.isSyncEnabled else {
            showPlayerNotice(SettingsStore.shared.isLoggedIn
                ? "マイリストを使うには、「設定をデバイス間で同期する」をオンにしてください。"
                : "マイリストを使うには、ログインが必要です。")
            return
        }
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            // 他の画面や Web 版での変更に追いついてから切り替える
            // (古い控えで切り替えると、別の登録を巻き戻しかねないため)。
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            let added = SyncedSettingsStore.shared.toggleMylist(videoID: videoID)
            self.updateMylistButtonTitle()
            self.showPlayerNotice(added ? "マイリストに追加しました。" : "マイリストから削除しました。")
        }
    }

    // MARK: しおり

    /// いまの再生位置にしおりを足す (表示名は付けない。Web 版と同じ)。
    @objc private func addBookmark() {
        let position = currentPosition()
        guard position.isFinite else { return }
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            if await APIClient.shared.createBookmark(
                videoID: videoID, position: position, label: "") != nil {
                self.showPlayerNotice("しおりを追加しました (\(TimeFormat.hms(position)))")
            } else {
                self.showPlayerNotice("しおりの追加に失敗しました。")
            }
        }
    }

    // MARK: 場面一覧・コメント検索

    @objc private func showSceneList() {
        let sceneList = SceneListViewController(
            program: program, highlightSegments: highlightSegments)
        sceneList.onSeek = { [weak self] time in
            self?.seek(to: time)
        }
        present(sceneList, animated: true)
    }

    @objc private func showCommentSearch() {
        // 検索の対象は、再生画面が取得済みのコメントの一覧
        // (ミュート設定で取り除いた分は含まれない)。
        let search = CommentSearchViewController(comments: jikkyoComments)
        search.onSeek = { [weak self] time in
            self?.seek(to: time)
        }
        present(search, animated: true)
    }

    // MARK: 次回を予約・シリーズ予約

    /// 次回の放送を番組表から探し、既定の録画設定でそのまま予約する
    /// (Web 版パネルの「次回を予約」と同じ手順)。
    /// 検索キーワードは番組名からマークと話数表記を除いたもの、
    /// チャンネルはこの番組のものに固定する。候補は未来の放送で、
    /// この録画と同じ放送でないものから、開始が一番早いものを選ぶ。
    @objc private func reserveNextBroadcast() {
        guard !isReservingNext else { return }
        isReservingNext = true
        let source = program
        Task { [weak self] in
            guard let self else { return }
            defer { self.isReservingNext = false }
            let condition = ReservationConditions.buildSeriesSearchCondition(
                title: source.title, seriesTitle: source.series_title,
                networkID: source.network_id, serviceID: source.service_id,
                transportStreamID: source.channel?.transport_stream_id)
            do {
                let result = try await APIClient.shared.searchPrograms(condition: condition)
                let now = Date()
                let candidates = result.programs
                    .filter { candidate in
                        guard let start = candidate.startDate, start > now else { return false }
                        // この録画と同じ放送 (イベント) は次回ではないため除く。
                        if let eventID = source.event_id, let candidateEventID = candidate.event_id {
                            return candidateEventID != eventID
                        }
                        return true
                    }
                    .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
                guard let next = candidates.first else {
                    self.showPlayerNotice("次回の放送が見つかりませんでした。")
                    return
                }
                // 既定の録画設定が取れなかったら、代用の設定では作らず
                // 失敗として知らせる (下の catch で表示される)。
                let recordSettings = try await APIClient.shared.fetchDefaultRecordSettings()
                try await APIClient.shared.addReservation(
                    programID: next.id, recordSettings: recordSettings)
                if let start = next.startDate {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "ja_JP")
                    formatter.dateFormat = "M/d H:mm"
                    self.showPlayerNotice(
                        "次回「\(next.title)」(\(formatter.string(from: start))〜) を予約しました。")
                } else {
                    self.showPlayerNotice("次回「\(next.title)」を予約しました。")
                }
            } catch {
                self.showPlayerNotice(Self.noticeMessage(
                    from: error, fallback: "次回の放送を予約できませんでした。"))
            }
        }
    }

    /// シリーズ予約 (キーワード自動予約の条件) を作る。以後は同じ
    /// シリーズが自動で予約される (Web 版パネルの「シリーズ予約」と同じ)。
    @objc private func createSeriesReservation() {
        guard !isCreatingSeries else { return }
        isCreatingSeries = true
        let source = program
        Task { [weak self] in
            guard let self else { return }
            defer { self.isCreatingSeries = false }
            let recordSettings: RecordSettings
            do {
                recordSettings = try await APIClient.shared.fetchDefaultRecordSettings()
            } catch {
                // 既定の録画設定が取れなかったら、代用の設定では
                // 作らず、その旨を知らせて終わる。
                self.showPlayerNotice("録画設定を取得できなかったため、シリーズ予約は作成していません。")
                return
            }
            let result = await ReservationConditions.addSeriesReservation(
                title: source.title, seriesTitle: source.series_title,
                networkID: source.network_id, serviceID: source.service_id,
                transportStreamID: source.channel?.transport_stream_id,
                recordSettings: recordSettings)
            switch result {
            case .created(let keyword):
                self.showPlayerNotice(
                    "シリーズ予約を作成しました。以後の「\(keyword)」は自動で予約されます。")
            case .duplicate:
                self.showPlayerNotice("このシリーズの自動予約はすでに作成されています。")
            case .failed(let error):
                self.showPlayerNotice(Self.noticeMessage(
                    from: error, fallback: "シリーズ予約を作成できませんでした。"))
            }
        }
    }

    /// サーバーからの文が入っている失敗はその文を、それ以外は予備の文を返す。
    private static func noticeMessage(from error: Error, fallback: String) -> String {
        if let apiError = error as? APIError, case .message(let text) = apiError {
            return text
        }
        return fallback
    }

    // MARK: 盛り上がりの波形とダイジェスト再生

    /// 実況コメント (ミュートで取り除く前の全体) から盛り上がりの密度と
    /// 見どころ区間を計算し、波形の帯を操作帯へ差し込む。
    /// コメントが50件に満たない録画では、帯も見どころも出さない (Web 版と同じ)。
    private func buildExcitement(from rawComments: [JikkyoComment]) {
        guard rawComments.count >= minCommentsForHighlights else { return }
        let density = computeCommentDensity(
            positions: rawComments.map { $0.time }, duration: program.duration)
        let segments = extractHighlightSegments(density: density)
        excitementDensity = density
        highlightSegments = segments
        excitementStrip.densities = density.densities
        excitementStrip.segments = segments
        excitementStrip.duration = density.duration
        excitementStrip.isHidden = !isScrubbing || (isFullscreen && !SettingsStore.shared.showExcitementInFullscreen)
        if !segments.isEmpty {
            digestButton.isHidden = false
            buttonsFlowView.setNeedsLayout()
        }
    }

    @objc private func toggleDigestPlayback() {
        setDigestPlayback(!digestPlaybackEnabled)
        showPlayerNotice(digestPlaybackEnabled
            ? "ダイジェスト再生を開始しました"
            : "ダイジェスト再生を終了しました")
    }

    /// ダイジェスト再生の入り切りと、ボタンの見た目 (入っている間は
    /// Web 版と同じくピンクの地に白い文字で、文にも (ON) を付ける)。
    private func setDigestPlayback(_ enabled: Bool) {
        digestPlaybackEnabled = enabled
        digestButton.setTitle(enabled ? "ダイジェスト再生（ON）" : "ダイジェスト再生", for: .normal)
        if enabled {
            digestButton.backgroundColor = AppPalette.accent
            digestButton.setTitleColor(.white, for: .normal)
        } else {
            digestButton.backgroundColor = AppPalette.panel
            digestButton.setTitleColor(AppPalette.metaText, for: .normal)
        }
        buttonsFlowView.setNeedsLayout()
    }

    /// ダイジェスト再生の見張り (Web 版と同じく 300ミリ秒に間引く)。
    /// 再生位置が見どころ区間の外にあれば、次の区間の開始へ飛ばす。
    /// 区間がもう無ければ、ダイジェスト再生を終える。
    private func applyDigestSkipIfNeeded(current: Double) {
        guard digestPlaybackEnabled, !highlightSegments.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastDigestCheckAt >= 0.3 else { return }
        lastDigestCheckAt = now
        guard isCurrentlyPlaying(), !isScrubbing else { return }
        if highlightSegments.contains(where: { current >= $0.start && current < $0.end }) {
            return
        }
        if let next = highlightSegments.first(where: { $0.start > current }) {
            seek(to: next.start)
            showPlayerNotice("盛り上がりシーンへスキップしました")
        } else {
            setDigestPlayback(false)
            showPlayerNotice("ダイジェスト再生が終了しました")
        }
    }

    // MARK: 長押しの高速シーク

    /// 送り・戻しボタンへ長押しの高速シークを取り付ける (拡張版だけ)。
    private func setupFastSeek() {
        fastSeekBackController.attach(to: skipBackButton)
        fastSeekForwardController.attach(to: skipForwardButton)
        // 消音は持ち主へ一元化する (送り・戻しが同時に進んでも、
        // 最後の1つが終わるまで音は戻らない)。
        fastSeekMuteKeeper.isMutedProvider = { [weak self] in self?.isEngineMuted ?? false }
        fastSeekMuteKeeper.setMutedHandler = { [weak self] muted in self?.setEngineMuted(muted) }
        for controller in [fastSeekBackController, fastSeekForwardController] {
            controller.muteKeeper = fastSeekMuteKeeper
            controller.positionProvider = { [weak self] in self?.currentPosition() ?? 0 }
            controller.seekHandler = { [weak self] position in self?.seek(to: position) }
            controller.isMutedProvider = { [weak self] in self?.isEngineMuted ?? false }
            controller.setMutedHandler = { [weak self] muted in self?.setEngineMuted(muted) }
            controller.onStart = { [weak self] direction in
                self?.showPlayerNotice(direction > 0 ? "高速早送り中 (長押し)" : "高速巻き戻し中 (長押し)")
            }
            controller.onKeepControlsVisible = { [weak self] in
                guard let self else { return }
                self.hideTimer?.invalidate()
                self.hideTimer = nil
                self.setControlsVisible(true)
            }
            controller.onEnd = { [weak self] in self?.scheduleHideControls() }
        }
    }

    /// いま音が消えているかどうか (再生の仕組みによらない読み取り口)。
    private var isEngineMuted: Bool {
#if canImport(VLCKit)
        if let vlcPlayer {
            return (vlcPlayer.audio?.volume ?? 100) == 0
        }
#endif
        return player?.isMuted ?? false
    }

    /// 音を消す・戻す (再生の仕組みによらない操作口)。
    /// VLCKit 経路には音を消す専用の入り口が無いため、音量を 0 にして
    /// 戻すときは元の音量へ戻す。
    private func setEngineMuted(_ muted: Bool) {
#if canImport(VLCKit)
        if let vlcPlayer {
            if muted {
                savedVLCVolume = vlcPlayer.audio?.volume ?? 100
                vlcPlayer.audio?.volume = 0
            } else {
                vlcPlayer.audio?.volume = savedVLCVolume ?? 100
                savedVLCVolume = nil
            }
            return
        }
#endif
        player?.isMuted = muted
    }

    // MARK: 再生の終わり (次の話の自動再生・追いかけ再生の先端到達)

    /// 再生できる範囲の末端 (秒)。録画中の追いかけ再生では、番組全体の
    /// 長さではなく「いま録れているところまで」が末端になる。
    private var seekableEndSeconds: Double {
#if canImport(VLCKit)
        if vlcPlayer != nil {
            let length = vlcLengthSeconds
            if length.isFinite, length > 0 { return length }
        }
#endif
        if let ranges = player?.currentItem?.seekableTimeRanges,
           let last = ranges.last?.timeRangeValue {
            let end = (last.start + last.duration).seconds
            if end.isFinite, end > 0 { return end }
        }
        let itemDuration = currentItemDurationSeconds
        if itemDuration.isFinite, itemDuration > 0 { return itemDuration }
        return program.duration
    }

    /// 再生が終わったときの扱い。
    /// 追いかけ再生の先端到達なら先端への復帰を、おやすみタイマーの
    /// 「番組の終わりで停止」が入っていれば停止の知らせを、
    /// それ以外で次の話があれば自動再生の数え下げを始める。
    /// 先端追従とおやすみタイマーは常時有効で、次の話の自動再生だけが
    /// 拡張オプションのトグルの対象 (前の話・次の話と同じ)。
    private func handlePlaybackEnded() {
        guard !didLeaveScreen, hasActiveEngine else { return }
        if chaseFollowActive {
            recoverChasePlayback()
            return
        }
        if sleepTimerMode == .end {
            showPlayerNotice("おやすみタイマーのため、ここで停止します")
            return
        }
        if SettingsStore.shared.repeatVideoPlayback, !recordingInProgress {
#if canImport(VLCKit)
            if vlcPlayer != nil { startPlayback(at: 0); return }
#endif
            let repeatGeneration = playbackGeneration
            // seek自身がイベントを1つ進める。後続操作や画面離脱後の完了で再生しない。
            let repeatEvent = playbackEndEventID + 1
            seek(to: 0, isUserInitiated: false) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !self.didLeaveScreen, self.playbackGeneration == repeatGeneration,
                          self.playbackEndEventID == repeatEvent else { return }
                    self.playAtCurrentRate()
                }
            }
            return
        }
        guard AppEdition.episodeNavigationEnabled, let nextID = nextEpisodeID else { return }
        let generation = playbackGeneration
        let endEventID = playbackEndEventID
        Task { [weak self] in
            guard let self else { return }
            guard let next = await APIClient.shared.fetchVideo(videoID: nextID) else { return }
            // 取得の間に画面を離れていたら、数え下げを始めない。
            // 取得の間に巻き戻して再生を再開したり、別の話へ移ったり
            // していた場合も、その「終わった」出来事は古くなっている
            // ので数え下げは始めない (終わりの扱いも応答時点で確かめる)。
            guard !self.didLeaveScreen, self.playbackGeneration == generation,
                  self.playbackEndEventID == endEventID,
                  self.sleepTimerMode != .end,
                  !self.isCurrentlyPlaying() else { return }
            self.startAutoplayCountdown(nextProgram: next)
        }
    }

    /// 次の話の自動再生の数え下げを始める (Web 版と同じ10秒)。
    private func startAutoplayCountdown(nextProgram: RecordedProgram) {
        guard !didLeaveScreen else { return }
        autoplayNextProgram = nextProgram
        autoplayRemainingSeconds = 10
        autoplayTitleLabel.text = nextProgram.title
        autoplayCountdownLabel.text = "あと \(autoplayRemainingSeconds) 秒"
        autoplayCard.isHidden = false
        setControlsVisible(true)
        autoplayTimer?.invalidate()
        autoplayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.didLeaveScreen else { return }
            self.autoplayRemainingSeconds -= 1
            if self.autoplayRemainingSeconds <= 0 {
                self.navigateToAutoplayNext()
            } else {
                self.autoplayCountdownLabel.text = "あと \(self.autoplayRemainingSeconds) 秒"
            }
        }
    }

    /// 数え下げを取り消してカードを隠す。
    private func cancelAutoplayCountdown() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil
        autoplayNextProgram = nil
        autoplayCard.isHidden = true
    }

    @objc private func autoplayNowTapped() {
        navigateToAutoplayNext()
    }

    @objc private func autoplayCancelTapped() {
        cancelAutoplayCountdown()
    }

    /// 数え下げの終わり (または「今すぐ再生」) で、次の話の再生画面へ移る。
    private func navigateToAutoplayNext() {
        guard !didLeaveScreen, let next = autoplayNextProgram else { return }
        cancelAutoplayCountdown()
        navigationController?.pushViewController(
            PlayerViewController(program: next), animated: true)
    }

    // MARK: ハイライト横断再生

    /// ハイライト横断再生の対象かどうかを開くときに確かめる。
    /// 順番の先頭がこの録画なら対象にし、別の録画が開かれた場合は
    /// 横断再生自体を取り消す (Web 版と同じ)。
    private func setupHighlightReel() {
        let store = HighlightReelStore.shared
        guard store.isActive, let item = store.currentItem else { return }
        if item.videoID == program.id {
            reelActive = true
            updateReelBadge()
        } else {
            store.clear()
        }
    }

    /// 左上の印の表示を、順番の進み具合に合わせる。
    private func updateReelBadge() {
        let store = HighlightReelStore.shared
        guard reelActive, store.isActive else {
            reelBadgeView.isHidden = true
            return
        }
        reelBadgeLabel.text = "ハイライト再生中 \(store.index + 1)/\(store.items.count)"
        reelBadgeView.isHidden = false
    }

    /// 印の取り消しボタン。横断再生をやめて、知らせを出す
    /// (Web 版と同じ文面)。再生自体はそのまま続ける。
    @objc private func reelAbortTapped() {
        HighlightReelStore.shared.clear()
        reelActive = false
        updateReelBadge()
        showPlayerNotice("ハイライト再生を終了しました")
    }

    /// 横断再生の見張り (進み具合の更新から呼ばれ、Web 版と同じ
    /// 500ミリ秒に間引く)。区間の終わり (0.25秒手前) に達したら
    /// 次の区間へ進む: 同じ録画ならその場で移動し、別の録画なら
    /// その再生画面を開く。最後の区間が終わったら、キューを破棄して
    /// 止め、終わったことを知らせる。
    private func updateHighlightReel(current: Double) {
        // 一時停止中は進めない (CM自動スキップ等の見張いと揃える)。
        // 条件が無いと、区間の終わり近くで止めただけで次へ進んでしまう。
        guard reelActive, isCurrentlyPlaying(), !didLeaveScreen else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastReelCheckAt >= 0.5 else { return }
        lastReelCheckAt = now
        let store = HighlightReelStore.shared
        guard let item = store.currentItem, item.videoID == program.id else { return }
        guard current >= item.end - 0.25 else { return }
        proceedToNextReelItem()
    }

    /// 横断再生を次の区間へ進める。別の録画の区間は、取り込めてから
    /// キューを進める。先にキューを進めてから取り込みに失敗すると、
    /// キューの指す録画と画面の録画が食い違い、見張りが「この画面の
    /// 区間ではない」として止まってしまうため。取り込めなかった区間は
    /// 飛ばして次へ進み、もう区間が無ければ横断再生を終える
    /// (知らせの文面と、キューや印の状態を食い違わせない)。
    private func proceedToNextReelItem() {
        let store = HighlightReelStore.shared
        guard let next = store.nextItem else {
            // 最後の区間が終わった。キューを破棄して止める。
            store.advance()
            reelActive = false
            updateReelBadge()
            pauseEngine()
            showPlayerNotice("ハイライト再生が終了しました")
            return
        }
        if next.videoID == program.id {
            store.advance()
            seek(to: next.start)
            updateReelBadge()
            return
        }
        // 取得中は重ねない。見張りは0.5秒ごとに呼ばれるため、
        // 印が無いと同じ区間の取得が繰り返し走り、遅れて返った
        // 応答が別の区間まで進めてしまうことがある。
        guard !reelFetchInFlight else { return }
        reelFetchInFlight = true
        let nextID = next.videoID
        // 照合は録画の ID だけでなく、キューの中での区間の番号まで
        // 含める (同じ録画の区間が続く場合、ID だけでは別の区間と
        // 見分けが付かないため)。
        let nextIndex = store.index + 1
        let generation = playbackGeneration
        Task { [weak self] in
            guard let self else { return }
            let nextProgram = await APIClient.shared.fetchVideo(videoID: nextID)
            self.reelFetchInFlight = false
            // 取得の間に画面を離れたり、世代が変わったり、横断再生が
            // 取り消されたり、キューの次の区間が別のものに変わって
            // いたら、この取得の結果では進めない (成功・失敗とも)。
            guard !self.didLeaveScreen, self.playbackGeneration == generation,
                  self.reelActive,
                  HighlightReelStore.shared.index + 1 == nextIndex,
                  HighlightReelStore.shared.nextItem?.videoID == nextID else { return }
            if let nextProgram {
                HighlightReelStore.shared.advance()
                self.navigationController?.pushViewController(
                    PlayerViewController(program: nextProgram), animated: true)
            } else {
                // 取り込めなかった区間は飛ばして、次へ進む。
                HighlightReelStore.shared.advance()
                self.showPlayerNotice("次の録画を取り込めなかったため、その区間を飛ばしました")
                self.proceedToNextReelItem()
            }
        }
    }

    // MARK: 追いかけ再生の先端追従

    /// 先端追従の見張り (進み具合の更新から呼ばれる)。
    /// 確認は2秒に間引き、録画が続いているかの確認は30秒ごとに行う。
    /// 先端 (いま録れているところ) に追いついたら1回だけ知らせ、
    /// 先端で止まったまま6秒続いたら、先端へ戻して再生を作り直す。
    private func updateChaseFollow(current: Double) {
        guard chaseFollowActive, hasActiveEngine, !didLeaveScreen else { return }
        let now = Date().timeIntervalSince1970
        if now - chaseLastStatusPollAt >= 30 {
            chaseLastStatusPollAt = now
            pollChaseRecordingStatus()
        }
        guard now - chaseLastTickAt >= 2 else { return }
        chaseLastTickAt = now
        let edge = seekableEndSeconds
        guard edge.isFinite, edge > 0 else { return }
        if current >= edge - 3 {
            if !chaseEdgeNoticeShown {
                chaseEdgeNoticeShown = true
                showPlayerNotice("録画の先端に追いつきました。そのまま流れ続けます")
            }
            // 再生中のはずなのに位置が進まない状態が続いたら、止まったものとみなす。
            if !chaseUserPaused, isCurrentlyPlaying() {
                if abs(current - chaseStallPosition) < 0.1 {
                    if chaseStallSince == 0 {
                        chaseStallSince = now
                    } else if now - chaseStallSince >= 6 {
                        recoverChasePlayback()
                    }
                } else {
                    chaseStallPosition = current
                    chaseStallSince = 0
                }
            }
        } else {
            chaseStallPosition = current
            chaseStallSince = 0
        }
    }

    /// 録画がまだ続いているかをサーバーへ確かめる。
    /// 終わっていたら先端追従をやめる (以降は通常の録画として扱う)。
    private func pollChaseRecordingStatus() {
        let videoID = program.id
        let generation = playbackGeneration
        Task { [weak self] in
            guard let self else { return }
            let latest = await APIClient.shared.fetchVideo(videoID: videoID)
            // 確かめている間に画面を離れていたら、応答は捨てる。
            // 離れるときに止めた履歴の登録タイマーが、録画の完了を
            // きっかけに裏で作り直されてしまうため。戻ってきた場合は
            // 復帰時の取り直しが録画の完了を扱う。
            guard !self.didLeaveScreen, self.playbackGeneration == generation else { return }
            if let latest, !latest.isRecording, self.recordingInProgress {
                self.handleRecordingFinished()
            }
        }
    }

    /// 録画が終わったときの移行を一か所にまとめる。先端追従をやめ、
    /// 録画中かどうかで止めていた視聴履歴の書き戻しや登録を始め、
    /// 「視聴済みにする」ボタンの表示も通常の録画に合わせる。
    private func handleRecordingFinished() {
        recordingInProgress = false
        chaseFollowActive = false
        watchedButton.isHidden = (program.watched_ratio ?? 0) >= 1
        // 登録用のタイマーはここから30秒で仕掛け直す。すでに30秒以上
        // 見ている場合は、定期の書き戻し側が登録も含めて行う。
        scheduleHistoryRegistration()
        if hasActiveEngine {
            let current = currentPosition()
            if current.isFinite {
                runHistorySync(current: current,
                               registerIfNeeded: Date().timeIntervalSince1970 - playbackOpenedAt >= 30)
            }
        }
    }

    /// 先端へ戻して再生を作り直す (Web 版の、先端へ戻して流れを
    /// 読み直す復帰にあたる)。利用者が自分で止めている間は再開しない。
    /// 続けて起きすぎないよう、復帰は5秒に1回までに間引く。
    private func recoverChasePlayback() {
        if pipController?.isActive == true || pipController?.isPending == true {
            showPlayerNotice("追いかけ再生を復旧するため PiP を終了します。")
            pipController?.stop()
            return
        }
        let now = Date().timeIntervalSince1970
        guard now - chaseLastRecoveryAt >= 5 else { return }
        chaseLastRecoveryAt = now
        chaseStallSince = 0
        guard !chaseUserPaused, !didLeaveScreen else { return }
        let edge = seekableEndSeconds
        let target = (edge.isFinite && edge > 1.5) ? edge - 0.5 : currentPosition()
        startPlayback(at: target)
    }

    // MARK: - ロック画面の「再生中」表示

    /// ロック画面やコントロールセンターへの表示と、そちらからの操作の受け付けを始める。
    /// 操作は画面内のボタンと同じ処理へつなぐので、状態がずれない。
    private func beginNowPlaying() {
        NowPlayingManager.shared.begin(owner: self, handlers: .init(
            play: { [weak self] in
                self?.playAtCurrentRate()
                self?.chaseUserPaused = false
            },
            pause: { [weak self] in
                self?.pauseEngine()
                self?.updatePlayPauseIcon()
                self?.chaseUserPaused = true
            },
            togglePlayPause: { [weak self] in
                self?.togglePlayPause()
            },
            skipForward: { [weak self] in
                self?.skipForward()
            },
            skipBackward: { [weak self] in
                self?.skipBack()
            },
            seekTo: { [weak self] position in
                self?.seek(to: position)
            },
            // 車のナビやイヤホンの「次へ／前へ」は、画面のチャプター移動ボタンと同じ処理へつなぐ。
            // チャプターが無い録画ではボタンも押せないので、その場合は受け付けない。
            nextChapter: program.chapterBoundaries.isEmpty ? nil : { [weak self] in
                self?.nextChapter()
            },
            previousChapter: program.chapterBoundaries.isEmpty ? nil : { [weak self] in
                self?.prevChapter()
            }
        ))
        updateNowPlaying()
        // サムネイルをアートワークとして取りに行く (取れなければ無しで出す)。
        let videoID = program.id
        Task { [weak self] in
            guard let self,
                  let data = try? await APIClient.shared.fetchThumbnail(videoID: videoID),
                  let image = UIImage(data: data) else { return }
            NowPlayingManager.shared.setArtwork(owner: self, image: image)
        }
    }

    private func updateNowPlaying() {
        guard hasActiveEngine else { return }
        let current = currentPosition()
        NowPlayingManager.shared.updateRecorded(
            owner: self,
            title: program.title,
            subtitle: program.channel?.name,
            elapsed: current.isFinite ? max(0, current) : 0,
            duration: effectiveDuration,
            rate: currentRateValue()
        )
    }

    // MARK: - 操作

    @objc private func togglePlayPause() {
        if let shouldPlay = playbackStart.togglePauseWhilePending() {
            if shouldPlay { playAtCurrentRate() } else { pauseEngine() }
            chaseUserPaused = !shouldPlay
            updatePlayPauseIcon()
            scheduleHideControls()
            return
        }
        if routeResolutionPending || fmp4StartContext?.state.awaitingRecovery == true {
            if isPlayingForControls { pauseEngine() } else { playAtCurrentRate() }
            updatePlayPauseIcon()
            return
        }
        // 中継の用意ができずに開始できなかった場合は、再生ボタンで
        // 始め直す (開始位置は、失敗したときに控えたものを使う)。
        if let retryPosition = pendingRelayRetryPosition {
            pendingRelayRetryPosition = nil
            // 中継の失敗後も、待機中に利用者が指定した最新位置を優先する。
            let latest = pendingPlaybackSeek.target ?? fmp4StartContext?.state.latestPosition ?? retryPosition
            startPlayback(at: latest)
            return
        }
        guard hasActiveEngine else { return }
        if isPlayingForControls {
            pauseEngine()
            // 利用者が自分で止めた間は、追いかけ再生の先端追従で
            // 勝手に再開しない。
            chaseUserPaused = true
        } else {
            playAtCurrentRate()
            chaseUserPaused = false
        }
        updatePlayPauseIcon()
        scheduleHideControls()
    }

    /// 位置を動かす。
    /// isUserInitiated が false の移動は、開始位置の指定に伴う内部の
    /// 位置合わせ (再生部品が開始位置を効かせなかった場合の受け皿)
    /// で、「利用者が動かした」印は付けない。印が付くと、保留中の
    /// 確定した続き位置まで「利用者が動かした」扱いになり、捨て
    /// られてしまうため。
    private func seek(to seconds: Double, isUserInitiated: Bool = true, completion: (() -> Void)? = nil) {
        // 位置が動いたら「終わった」出来事は古くなる。終わった直後の
        // 次の話の取り込みが終わっても、自動再生は始めない。
        playbackEndEventID += 1
        // 利用者 (または自動の移動) が位置を動かした印。開始直後に
        // 並行して確かめている続きの位置が遅れて返ってきても、
        // 動かした後の位置を上書きしないために使う。
        if isUserInitiated {
            userSeekedSinceStart = true
        }
        let clamped = max(0, min(seconds, effectiveDuration))
        if isUserInitiated { fmp4StartContext?.state.noteSeek(to: clamped) }
        // 再生が始まる前の移動は、再生部品へ送っても届かず捨てられて
        // しまうため、移動先を控えておく。再生が始まったときに反映し、
        // 開始位置の復元 (受け皿・補正) より優先する。
        if !playbackReadyForSeek {
            pendingPlaybackSeek.replace(target: clamped, completion: completion)
            commentOverlay.reset(to: clamped)
            beginCaptionSeek()
            return
        }
        // 再生が始まってからの移動では、再生部品の位置が飛び先へ移る
        // までの間、表示だけ先に飛び先へ合わせる (古い位置で止まった
        // ままに見えないようにするため)。
        if isUserInitiated, playbackDidStart {
            seekDisplay.begin(target: clamped)
        }
        // CM自動スキップの判定は移動先から見張る
        // (シークで CM 区間の真ん中へ入った直後は発動させないため)。
        lastObservedPosition = clamped
        // コメントの表示も移動先に合わせる (移動先より前のコメントは流さない)。
        commentOverlay.reset(to: clamped)
        // 固定時間ではなく再生部品の完了で復元する。連続シークの古い完了は失効する。
        let captionToken = beginCaptionSeek()
        let startupRequest = fmp4StartContext?.request
        let startupAttempt = fmp4StartContext?.state.currentAttempt
        let startupItem = player?.currentItem
        let startupSeek = fmp4StartContext?.state.beginSeek(to: clamped)
        refreshFMP4StartWatchdog()
        let playbackToken = playbackGeneration
        let finished: (Bool) -> Void = { [weak self, weak startupItem] mayResumeCaptions in
            DispatchQueue.main.async {
                // PiP等の呼び出し元への完了通知は、字幕世代の失効とは別に必ず返す。
                defer { completion?() }
                if let self, let startupRequest, let startupAttempt, let startupItem, let startupSeek,
                   self.playbackGeneration == playbackToken,
                   self.player?.currentItem === startupItem,
                   self.fmp4StartContext?.state.accepts(startupAttempt) == true,
                   self.acceptsPlaybackRequest(startupRequest) {
                    self.fmp4StartContext?.state.completeSeek(startupSeek, completed: mayResumeCaptions, position: self.currentPosition(),
                        now: ProcessInfo.processInfo.systemUptime)
                    self.refreshFMP4StartWatchdog()
                }
                guard mayResumeCaptions, let self, self.playbackGeneration == playbackToken,
                      self.captionEngine.completeSeek(captionToken) else { return }
                self.refreshCaptions()
                // 字幕完了と同じ世代でのみ再開し、明示停止・スクラブ中は再開しない。
                if self.playbackIntentPlaying, !self.isScrubbing, !self.didLeaveScreen,
                   !self.isCurrentlyPlaying() { self.playAtCurrentRate() }
            }
        }
#if canImport(VLCKit)
        if let vlcPlayer {
            vlcResumeAfterSeek = playbackIntentPlaying && !isScrubbing
            captionSeekCoordinator.submit(target: clamped, operation: { [weak self, weak vlcPlayer] target, done in
                guard let self, let vlcPlayer, self.vlcPlayer === vlcPlayer else { return false }
                // 待機中にも時計が進むので、相対offsetは実行直前に計算する。
                let current = self.currentPosition()
                guard current.isFinite else { return false }
                let offset = min(Double(Int32.max), max(Double(Int32.min), (target - current) * 1000))
                // 同一位置はVLCの位置変化イベントが発生しないため、自分で完了させる。
                guard Int32(offset) != 0 else { return false }
                return vlcPlayer.jump(withOffset: Int32(offset)) {
                    DispatchQueue.main.async { done() }
                }
            }, completion: finished)
            return
        }
#endif
        guard let player else { finished(true); return }
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { completed in finished(completed) }
    }

    private func applyPendingPlaybackSeek() {
        guard playbackReadyForSeek, let pending = pendingPlaybackSeek.take() else { return }
        seekDisplay.begin(target: pending.target)
        seek(to: pending.target, isUserInitiated: false, completion: pending.completion)
    }

    @objc private func skipBack() {
        guard hasActiveEngine else { return }
        seek(to: currentPosition() - Double(SettingsStore.shared.seekBackwardSeconds))
        scheduleHideControls()
    }

    @objc private func skipForward() {
        guard hasActiveEngine else { return }
        seek(to: currentPosition() + Double(SettingsStore.shared.seekForwardSeconds))
        scheduleHideControls()
    }

    @objc private func prevChapter() {
        guard hasActiveEngine else { return }
        let current = currentPosition()
        // 現在位置より手前にある一番近い境目へ。無ければ先頭へ。
        let target = program.chapterBoundaries.filter { $0 < current - 1.0 }.last ?? 0
        seek(to: target)
        scheduleHideControls()
    }

    @objc private func nextChapter() {
        guard hasActiveEngine else { return }
        let current = currentPosition()
        if let target = program.chapterBoundaries.first(where: { $0 > current + 0.5 }) {
            seek(to: target)
        }
        scheduleHideControls()
    }

    @objc private func scrubBegan() {
        beginCaptionSeek()
        isScrubbing = true
        excitementStrip.isHidden = excitementDensity == nil || (isFullscreen && !SettingsStore.shared.showExcitementInFullscreen)
        wasPlayingBeforeScrub = playbackIntentPlaying
        pauseEngine(isUserInitiated: false)
        hideTimer?.invalidate()
        hideTimer = nil
        // プレビューを出し、タイル画像がまだなら取りに行く (初回だけ)。
        showSeekPreview()
        ensureSpriteLoading()
    }

    @objc private func scrubChanged() {
        let target = Double(seekSlider.value) * effectiveDuration
        currentTimeLabel.text = TimeFormat.hms(target)
        updateSeekPreview(target: target)
    }

    @objc private func scrubEnded() {
        defer {
            refreshFMP4StartWatchdog()
            // scrub中に到着した開始失敗の復旧は、操作終了後に最新位置から再評価する。
            _ = resumeDeferredFMP4Recovery()
        }
        isScrubbing = false
        excitementStrip.isHidden = true
        seekPreviewView.isHidden = true
        let target = Double(seekSlider.value) * effectiveDuration
        seek(to: target)
        if wasPlayingBeforeScrub, playbackIntentPlaying {
            playAtCurrentRate()
#if canImport(VLCKit)
            // バーを動かすために一時的に止めていただけなので、飛び先で
            // 止まったままになってしまった場合は、スキップと同じく
            // 再開の対象にする。
            vlcResumeAfterSeek = true
#endif
            chaseUserPaused = false
        }
        scheduleHideControls()
    }

    // MARK: - シーク中のプレビュー

    /// 番組データにタイル情報があるかどうか。無い録画 (解析前・録画中など)
    /// ではプレビューの映像は出さず、時刻だけ出す。
    private var seekTileInfo: ThumbnailTileInfo? {
        guard let tile = program.recorded_video.thumbnail_info?.tile,
              tile.isUsableForTiles
        else { return nil }
        return tile
    }

    /// プレビューを出し、いまの指の位置で中身を合わせる。
    private func showSeekPreview() {
        seekPreviewView.isHidden = false
        // 横位置の計算に使う幅を先に確定させる。
        videoContainer.layoutIfNeeded()
        updateSeekPreview(target: Double(seekSlider.value) * effectiveDuration)
    }

    /// プレビューの時刻・横位置・映像を、指の位置に合わせて直す。
    /// 映像の切り出しはタイルが切り替わったときだけ (指の動きのたびには
    /// 行わない)。タイル画像が届いていなければ時刻だけ出す。
    private func updateSeekPreview(target: Double) {
        seekPreviewTimeLabel.text = TimeFormat.hms(target)
        // 横位置: つまみの中心に合わせ、映像の枠からはみ出さない範囲に収める。
        let track = seekSlider.trackRect(forBounds: seekSlider.bounds)
        let thumb = seekSlider.thumbRect(forBounds: seekSlider.bounds, trackRect: track, value: seekSlider.value)
        let thumbCenter = seekSlider.convert(CGPoint(x: thumb.midX, y: 0), to: videoContainer).x
        let halfWidth = videoContainer.bounds.width / 2
        if halfWidth > 0 {
            let limit = max(0, halfWidth - seekPreviewView.bounds.width / 2 - 4)
            seekPreviewCenterConstraint?.constant = min(max(thumbCenter - halfWidth, -limit), limit)
        }
        // 映像: 対象のタイルが前回と違えば切り出し直す。
        guard let tile = seekTileInfo, let sprite = spriteCGImage else {
            seekPreviewImageView.isHidden = true
            return
        }
        // タイル番号は安全な計算で求める (間隔が極端に小さい値でも
        // 整数への変換で落ちない)。位置が使えない値なら映像は出さない。
        guard let index = tile.tileIndex(at: target) else {
            seekPreviewImageView.image = nil
            seekPreviewImageView.isHidden = true
            return
        }
        if index != seekPreviewTileIndex {
            seekPreviewTileIndex = index
            if let rect = tile.cropRect(
                tileIndex: index, imageWidth: sprite.width, imageHeight: sprite.height),
               let cropped = sprite.cropping(to: rect) {
                seekPreviewImageView.image = UIImage(
                    cgImage: cropped, scale: spriteImage?.scale ?? 1, orientation: .up)
            } else {
                // 切り出せなかったら、前のタイルの映像が残らないよう消す。
                seekPreviewImageView.image = nil
            }
        }
        seekPreviewImageView.isHidden = seekPreviewImageView.image == nil
    }

    /// タイル画像を取りに行く (シークを始めたときに1回だけ)。
    /// 取得と読み解きは裏で行い、再生そのものは止めない。
    /// 届いた絵の寸法がタイル情報と合わない場合 (サーバーが既定の画像を
    /// 返した場合など) は、プレビューの映像は出さない。
    private func ensureSpriteLoading() {
        guard let tile = seekTileInfo, spriteLoadState == .idle else { return }
        spriteLoadState = .loading
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            guard let data = await APIClient.shared.fetchTiledThumbnail(videoID: videoID) else {
                self.spriteLoadState = .failed
                return
            }
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let image, let cgImage = image.cgImage,
                  cgImage.width == tile.image_width, cgImage.height == tile.image_height
            else {
                self.spriteLoadState = .failed
                return
            }
            self.spriteImage = image
            self.spriteCGImage = cgImage
            self.spriteLoadState = .loaded
            self.seekPreviewTileIndex = -1
            // シークが続いていれば、その位置の映像をすぐ出す。
            if self.isScrubbing {
                self.updateSeekPreview(target: Double(self.seekSlider.value) * self.effectiveDuration)
            }
        }
    }

    private func switchQuality(_ newQuality: String) {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            showPlayerNotice("PiP を終了してから画質を変更してください。")
            return
        }
        guard newQuality != quality else { return }
        // 止めている間の切り替えで勝手に再開しないよう、作り直す前に
        // 再生中だったかを控え、止めていた場合は作り直した後も止める。
        let wasPlaying = isCurrentlyPlaying()
        let current = currentPosition()
        quality = newQuality
        // 画質が変わるとサーバー側のストリームが別物になるため、セッションも作り直す。
        sessionID = UUID().uuidString
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.menu = makeQualityMenu()
        buttonsFlowView.setNeedsLayout()
        startPlayback(at: current.isFinite ? current : 0)
        if !wasPlaying {
            pauseEngine()
            updatePlayPauseIcon()
        }
    }

    // MARK: - 同じ再生画面の全画面状態

    @objc private func showFullscreen() { setFullscreen(!isFullscreen) }

    /// 設定を先に閉じ、タブの復元と全画面の非表示状態を競合させない。
    /// 描画先・字幕世代・シーク直列化・各タイマーは既存の所有元に残す。
    private func setFullscreen(_ fullscreen: Bool, restoringOn scene: UIWindowScene? = nil) {
        guard isFullscreen != fullscreen else { return }
        playerSettingsPanel?.closePanel()
        let windowScene = scene ?? view.window?.windowScene ?? fullscreenWindowScene
        isFullscreen = fullscreen
        if fullscreen {
            fullscreenWindowScene = windowScene
            NSLayoutConstraint.deactivate(normalVideoConstraints)
            NSLayoutConstraint.activate(fullscreenVideoConstraints)
            NSLayoutConstraint.deactivate(normalSeekConstraints)
            NSLayoutConstraint.activate(fullscreenSeekConstraints)
        } else {
            NSLayoutConstraint.deactivate(fullscreenVideoConstraints)
            NSLayoutConstraint.activate(normalVideoConstraints)
            NSLayoutConstraint.deactivate(fullscreenSeekConstraints)
            NSLayoutConstraint.activate(normalSeekConstraints)
            fullscreenWindowScene = nil
        }
        infoTabBar.isHidden = fullscreen
        scrollView.isHidden = fullscreen || selectedInfoTab != .info
        commentTableView.isHidden = fullscreen || selectedInfoTab != .comment
        excitementStrip.isHidden = !isScrubbing || excitementDensity == nil
            || (isFullscreen && !SettingsStore.shared.showExcitementInFullscreen)
        fullscreenButton.setImage(UIImage(systemName: fullscreen
            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"), for: .normal)
        fullscreenButton.accessibilityLabel = fullscreen ? "全画面を解除" : "全画面"
        // 画面を離れたあとも、控えたコンテナへ向きの再評価を伝える。
        let navigation = navigationController ?? playbackNavigation
        if navigation?.topViewController === self {
            navigation?.setNavigationBarHidden(true, animated: false)
        }
        setControlsVisible(true)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfSupportedInterfaceOrientations()
        navigation?.setNeedsStatusBarAppearanceUpdate()
        navigation?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        navigation?.setNeedsUpdateOfSupportedInterfaceOrientations()
        playbackTabs?.setNeedsStatusBarAppearanceUpdate()
        playbackTabs?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        playbackTabs?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if fullscreen { windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) }
        else { restoreOrientation(on: windowScene) }
        view.setNeedsLayout()
        if navigation?.topViewController === self, viewIfLoaded?.window != nil {
            scheduleHideControls()
            resumeDeferredSessionRecovery()
        }
    }

    private var canCaptureVideo: Bool {
        if fmp4StartContext?.state.awaitingRecovery == true { return false }
        if fmp4StartContext != nil, player?.currentItem?.status == .failed { return false }
        guard !audioOnly, !captureController.isCapturing, pipController?.isActive != true, pipController?.isPending != true else { return false }
#if canImport(VLCKit)
        if let vlcPlayer { return vlcPlayer.hasVideoOut }
#endif
        return (player?.currentItem?.presentationSize.width ?? 0) > 0
    }

    private func updateCaptureControls() {
        captureButton.isEnabled = canCaptureVideo
        captureButton.alpha = captureButton.isEnabled ? 1 : 0.35
    }

    private func captureVideo(presenter: UIViewController) {
        guard canCaptureVideo else { return }
        let engine = vlcPlayer
        let item = player?.currentItem
        let event = playbackEndEventID
        let context = WatchedHistoryStore.Context.current
        let capturedAt = Date()
        // PWAと同じく、動画ファイルの秒ではなく放送番組開始からの秒をEXIFへ記録する。
        let recordingOffset = program.startDate.flatMap { start in
            program.recorded_video.recordingStartDate.map { start.timeIntervalSince($0) }
        } ?? program.recordingStartMargin
        let metadata = CaptureMetadata(capturedAt: capturedAt, playbackPosition: currentPosition() - recordingOffset,
            networkID: program.network_id, serviceID: program.service_id, eventID: program.event_id,
            title: program.title, description: program.description, startTime: program.start_time,
            endTime: program.end_time, duration: program.duration)
        captureController.capture(vlcPlayer: engine, playerItem: item,
            caption: SettingsStore.shared.showCaptions ? captionEngine.currentCaptionImage : nil,
            superimpose: SettingsStore.shared.showCaptions ? captionEngine.currentSuperimposeImage : nil,
            metadata: metadata, capturedAt: capturedAt, presenter: presenter,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.pipController?.isActive != true && self.pipController?.isPending != true
                    && self.vlcPlayer === engine && self.player?.currentItem === item
                    && self.playbackEndEventID == event && context == WatchedHistoryStore.Context.current
            })
    }

    private func showCaptureError(_ message: String) {
        let presenter = presentedViewController ?? self
        guard presenter.viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: "キャプチャ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .default))
        presenter.present(alert, animated: true)
    }

    private func applyRepeatPlayback() {
#if canImport(VLCKit)
        guard let vlcPlayer, vlcPlayer.state == .playing || vlcPlayer.state == .paused else { return }
        // 4系のA-Bループで同じ出力を維持する。終端の再接続とPiPの破棄を避ける。
        _ = KonomiTVConfigureRepeat(vlcPlayer,
            SettingsStore.shared.repeatVideoPlayback && !recordingInProgress && sleepTimerMode != .end)
#endif
    }

    private func restartPlayer() {
        guard pipController?.isActive != true, pipController?.isPending != true else { return }
        let position = currentPosition()
        let playing = isCurrentlyPlaying()
        sessionID = UUID().uuidString
        startPlayback(at: position.isFinite ? position : 0)
        if !playing { pauseEngine() }
    }

    private func makePiPController() -> PlaybackPiPController {
        let pip = PlaybackPiPController(videoView: surfaceView, isLive: false,
            currentTime: { [weak self] in self?.currentPosition() ?? 0 },
            duration: { [weak self] in self?.effectiveDuration ?? 0 },
            isPlaying: { [weak self] in self?.isCurrentlyPlaying() ?? false },
            play: { [weak self] in self?.playAtCurrentRate() }, pause: { [weak self] in self?.pauseEngine() },
            seek: { [weak self] target, completion in
                guard let self else { completion(); return }
                self.seek(to: target, completion: completion)
            })
        pip.onStateChanged = { [weak self] in
            guard let self else { return }
            guard let controller = self.pipController else {
                self.pipWasActive = false
                self.updatePiPButton()
                return
            }
            let active = controller.isActive
            if self.pipWasActive, !active {
                // PiP終了時も最終位置を保存する。最大到達位置とは別の既存同期経路を使う。
                let position = self.currentPosition()
                if WatchedHistorySync.isEnabled, !self.recordingInProgress, position.isFinite {
                    self.historySyncEpoch += 1
                    self.lastHistorySyncAt = Date().timeIntervalSince1970
                    let id = self.program.id
                    let register = self.lastHistorySyncAt - self.playbackOpenedAt >= 30
                    let context = WatchedHistoryStore.Context.current
                    Task {
                        guard context == WatchedHistoryStore.Context.current else { return }
                        await WatchedHistorySync.syncPosition(videoID: id, position: position, registerIfNeeded: register)
                    }
                }
            }
            // 開始失敗後に既に一覧へ戻っていた場合も、繰り返しTimer・通信を残さない。
            if self.pipController?.isActive == false, self.pipController?.isPending == false,
               self.navigationController == nil { self.didLeaveScreen = true; self.stopPlayback() }
            self.pipWasActive = active
            self.updatePiPButton()
            self.refreshFMP4StartWatchdog()
            DispatchQueue.main.async { [weak self] in self?.resumeDeferredSessionRecovery() }
        }
        pip.onRestoreInterface = { [weak self] in
            guard let self, let navigation = self.playbackNavigation else { return }
            self.playbackTabs?.selectedIndex = self.playbackTabIndex
            if navigation.viewControllers.contains(where: { $0 === self }) {
                navigation.popToViewController(self, animated: false)
            } else { navigation.pushViewController(self, animated: false) }
        }
        pip.onSuperseded = { [weak self] in self?.didLeaveScreen = true; self?.stopPlayback() }
        pip.onError = { [weak self] text in
            guard let self else { return }
            let alert = UIAlertController(title: "PiP", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "閉じる", style: .default))
            let visible = self.playbackTabs?.selectedTabViewController?.visibleViewController ?? self
            let presenter = visible.presentedViewController ?? visible
            if presenter.viewIfLoaded?.window != nil { presenter.present(alert, animated: true) }
            else { self.messageLabel.text = text }
        }
        return pip
    }

    private func updatePiPButton() {
        pipButton.isHidden = !(pipController?.isReady == true && !audioOnly)
        pipButton.isEnabled = pipController?.isPending != true
            && (pipController?.isActive == true || (!playbackStart.inFlight && !routeResolutionPending))
        pipButton.setImage(UIImage(systemName: pipController?.isActive == true ? "pip.exit" : "pip.enter"), for: .normal)
        pipButton.accessibilityValue = pipController?.isActive == true ? "再生中" : "停止中"
    }

    @objc private func togglePiP() {
        playerSettingsPanel?.closePanel()
        captureController.cancel()
        guard let pip = pipController, !audioOnly else { return }
        if pip.isActive || pip.isPending { pip.stop() }
        else if !playbackStart.inFlight && !routeResolutionPending { pip.start(owner: self) }
    }

    @objc private func openPlayerSettings() { showPlayerSettings() }

    private func showPlayerSettings() {
        if let panel = playerSettingsPanel { panel.closePanel(); return }
        hideTimer?.invalidate()
        let menu = PlayerSettingsViewController { [weak self] in
            guard let self else { return [] }
            let store = SettingsStore.shared
            let saver = store.dataSaverMode(media: .video, profile: self.profile)
            var rows: [PlayerSettingsViewController.Row] = [
                .init(title: "画質", value: self.quality, choices: SettingsStore.qualities.map { quality in
                    .init(title: SettingsStore.qualityDisplayName(quality, dataSaverMode: saver), selected: quality == self.quality,
                          select: { [weak self] in self?.userSwitchQuality(quality) })
                }),
                .init(title: "モバイル回線向け画質", toggle: self.profile == .cellular,
                      change: { [weak self] on in _ = self?.switchProfile(to: on ? .cellular : .wifi) }),
                .init(title: "再生速度", value: SettingsStore.playbackRateText(store.playbackRate), choices: SettingsStore.playbackRateChoices.map { rate in
                    .init(title: SettingsStore.playbackRateText(rate), selected: rate == store.playbackRate,
                          select: { [weak self] in self?.setPlaybackRate(rate) })
                }),
                .init(title: "コメントを表示", toggle: store.showComments, change: { [weak self] _ in self?.toggleComments() }),
                .init(title: "コメントを無制限に表示", toggle: store.showCommentsUnlimited, change: { [weak self] on in
                    store.showCommentsUnlimited = on
                    self?.commentOverlay.unlimited = on
                }),
                .init(title: "コメントの透明度", value: String(format: "%.1f", store.commentOpacity), choices: (0...10).map { step in
                    let value = Double(step) / 10
                    return .init(title: String(format: "%.1f", value), selected: abs(store.commentOpacity - value) < 0.01, select: { [weak self] in
                        store.commentOpacity = value
                        self?.commentOverlay.displayOpacity = value
                    })
                }),
                .init(title: "音声のみ再生", toggle: self.audioOnly, change: { [weak self] _ in self?.toggleAudioOnly() }),
                .init(title: "おやすみタイマー", value: self.sleepTimerMode == .off ? "オフ" : (self.sleepTimerButton.title(for: .normal) ?? ""),
                      choices: ["オフ", "15分", "30分", "60分", "番組の終わりで停止"].enumerated().map { index, title in
                    .init(title: title, selected: self.sleepTimerModeIndex == index, select: { [weak self] in
                        guard let self else { return }
                        // 既存のタイマー開始・停止・通知処理を、選択したモードから使う。
                        self.sleepTimerModeIndex = (index + 4) % 5
                        self.cycleSleepTimer()
                    })
                }),
            ]
            rows.insert(.init(title: "リピート再生", toggle: store.repeatVideoPlayback, change: { [weak self] on in
                store.repeatVideoPlayback = on
                self?.applyRepeatPlayback()
            }), at: 3)
            if !self.digestButton.isHidden {
                rows.append(.init(title: "ダイジェスト再生", toggle: self.digestPlaybackEnabled, change: { [weak self] _ in self?.toggleDigestPlayback() }))
            }
            if self.pipController?.isActive != true, self.pipController?.isPending != true {
                rows.append(.init(title: "プレイヤーを再起動", action: { [weak self] in self?.restartPlayer() }))
            }
            if self.pipController?.isActive == true || self.pipController?.isPending == true {
                for index in rows.indices where ["画質", "モバイル回線向け画質", "音声のみ再生"].contains(rows[index].title) {
                    rows[index].isEnabled = false
                }
            }
            return rows
        }
        let navigation = PlayerSettingsNavigationController(rootViewController: menu)
        navigation.onClose = { [weak self] in
            self?.updateCaptionButton()
            self?.scheduleHideControls()
        }
        if isFullscreen { navigation.mount(in: self) }
        else { navigation.mount(in: self, below: videoContainer, hiding: infoTabBar) }
    }

    /// 音声のみ: 映像だけを隠し、最小画質に切り替えて通信量を抑える。切ると元の画質に戻す。
    /// 操作帯は映像の上に重なっているため、隠すのは映像の描画だけにする
    /// (帯ごと隠すと、止める操作もできなくなる)。
    /// VLCKit 経路では、画質切り替えで作り直すときに映像なし (:no-video) で
    /// つなぎ直すので、描画自体が出ない (生放送の音声のみと同じ)。
    @objc private func toggleAudioOnly() {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            showPlayerNotice("PiP を終了してから再生設定を変更してください。")
            return
        }
        playerSettingsPanel?.closePanel()
        audioOnly.toggle()
        updateCommentButton()
        audioOnlyButton.setTitle(audioOnly ? "音声のみ: ON" : "音声のみ: OFF", for: .normal)
        buttonsFlowView.setNeedsLayout()
        playerLayer?.isHidden = audioOnly
        if audioOnly {
            qualityBeforeAudioOnly = quality
            switchQuality(SettingsStore.audioOnlyQuality)
        } else {
            switchQuality(qualityBeforeAudioOnly
                ?? SettingsStore.shared.streamingQuality(media: .video, profile: profile))
            qualityBeforeAudioOnly = nil
        }
        // 音声のみの間はコメントを流さず、戻したら再開する。
        applyCommentDisplayState()
        // 字幕も同じく、音声のみの間は出さず、戻したら再開する。
        applyCaptionDisplayState()
        updateCaptionButton()
    }
}

#if canImport(VLCKit)
extension PlayerViewController {
    /// VLC 側の状態変化に、画面内のボタンとロック画面の表示を追随させる
    /// (生放送と同じ作り)。再生が始まった合図では、開始位置の指定が
    /// 効いていなかった場合の受け皿の移動と、画質の切り替え完了時点の
    /// 書き戻しも行う (AVPlayer 経路の再生状態の観測にあたる)。
    func handleVLCState(_ state: VLCMediaPlayerState, source: VLCMediaPlayer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let vlcPlayer = self.vlcPlayer else { return }
            // 4系は通知引数に送信元がないため、各プレイヤー専用observerの参照で照合する。
            guard source === vlcPlayer else { return }
            if vlcPlayer.state == .playing || vlcPlayer.state == .paused {
                self.playbackReadyForSeek = true
                if self.pendingPlaybackSeek.target != nil {
                    self.vlcPendingStartCorrection = nil
                    self.vlcPendingStartPosition = nil
                    self.applyPendingPlaybackSeek()
                }
            }
            if vlcPlayer.state == .playing {
                self.vlcDidStartPlaying = true
                self.applyRepeatPlayback()
                self.playbackDidStart = true
                self.vlcResumeAfterSeek = false
                self.vlcStartWatchdog?.invalidate()
                self.vlcStartWatchdog = nil
                // 見張りが先に失敗を表示していた場合は、始まったので消す。
                if self.messageLabel.text == "再生を開始できませんでした。" {
                    self.messageLabel.text = nil
                }
                // 準備が終わった時点の移動は、どれか一方にまとめる
                // (全部効かせると何度も飛んで見えるため)。優先順位は、
                // 再生が始まる前に利用者が指定した移動先、保留していた
                // 開始位置の補正 (サーバーで確定した続き位置)、仮の
                // 開始位置の受け皿の順。
                if let correction = self.vlcPendingStartCorrection {
                    self.vlcPendingStartCorrection = nil
                    self.vlcPendingStartPosition = nil
                    // 保留の間に利用者が自分で位置を動かしていたら、
                    // その位置を優先して移らない。
                    if !self.userSeekedSinceStart {
                        self.seek(to: correction)
                    }
                } else if let start = self.vlcPendingStartPosition {
                    self.vlcPendingStartPosition = nil
                    // 開始位置はメディアの指定で最初から渡してある。
                    // 指定が効いて、その位置から始まっているときは
                    // 移り直さない (二重に飛んで見えるため)。指定が
                    // 効かず先頭から始まっているときだけ、今まで
                    // どおりここで移る。この移動は開始位置の指定に
                    // 伴う内部の位置合わせなので、「利用者が動かした」
                    // 印は付けない (後から届く確定した続き位置が、
                    // 利用者の操作と間違われて捨てられないため)。
                    if start > 0, abs(self.currentPosition() - start) > 3 {
                        self.seek(to: start, isUserInitiated: false)
                    }
                }
                if let pending = self.pendingQualityWriteBack,
                   pending == self.quality {
                    SettingsStore.shared.setStreamingQuality(pending, media: .video, profile: self.profile)
                    self.pendingQualityWriteBack = nil
                }
            } else if vlcPlayer.state == .paused {
                // 移動 (シーク) の直前に再生していたのに、移動先で
                // 止まったままになってしまった場合は、再生を再開する。
                // 利用者が自分で止めたときは印が消えているため、
                // ここには入らない。
                if self.vlcResumeAfterSeek, self.playbackIntentPlaying,
                   !self.didLeaveScreen {
                    self.vlcResumeAfterSeek = false
                    self.playAtCurrentRate()
                }
            } else if vlcPlayer.state == .stopped {
                self.vlcResumeAfterSeek = false
                // 再生が最後まで進んだ合図。ただし、途中の壊れた区間などで
                // 手前で止まっただけの場合は、終わったものとして扱わない
                // (追いかけ再生の先端到達は、先端付近での停止として扱う)。
                if self.chaseFollowActive
                    || self.currentPosition() >= self.effectiveDuration - 5 {
                    self.handlePlaybackEnded()
                }
            } else if vlcPlayer.state == .error {
                self.vlcResumeAfterSeek = false
                // 失敗の表示は、開始前と開始後で分ける。開始前は開始の
                // 失敗として、開始後は途中で止まったこととして知らせる
                // (真っ黒のまま無言にしない)。
                self.vlcStartWatchdog?.invalidate()
                self.vlcStartWatchdog = nil
                if !self.vlcDidStartPlaying {
                    self.messageLabel.text = "再生を開始できませんでした。"
                } else if !self.didLeaveScreen {
                    self.messageLabel.text = "再生中にエラーが発生し、再生が止まりました。"
                }
            }
            self.updatePlayPauseIcon()
            self.updateNowPlaying()
        }
    }
}
#endif

// MARK: - 字幕データの受け取り (通常画質)

extension PlayerViewController: AVPlayerItemMetadataOutputPushDelegate {
    /// AVPlayer から時刻つきデータが届いたときに呼ばれる (メイン側で受ける)。
    /// 配信の字幕データは ID3 の PRIV フレームで届き、再生部品が渡す値は
    /// 宛先名を含まない「字幕の中身」そのもの (識別子は id3/PRIV) という
    /// 届き方を実機で確認済み (2026-11-23、版0.41 で受信34件すべて一致)。
    /// 包みの位置は、届いた組の開始時刻をそのまま使う。
    /// 取り出した包みは字幕の本体へ渡し、その場で表示にも反映する。
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        guard output === captionMetadataOutput, !groups.isEmpty else { return }
        var ingested = false
        for group in groups {
            let start = group.timeRange.start.seconds
            let position = start.isFinite ? start : currentPosition()
            for item in group.items {
                if let payload = captionPayload(from: item) {
                    captionEngine.ingest(position: position, payload: payload)
                    ingested = true
                }
            }
        }
        if ingested {
            refreshCaptions()
        }
    }

    /// 受け取った項目から、字幕の中身を取り出す。
    /// 値は中身そのものが入っている形が実機で確定しているが、
    /// 宛先名が付いた形で届く場合に備え、先頭の宛先名は取り除く。
    /// 中身の形 (先頭 0x80/0x81 + 0xFF 0xF0) に合わないものは、
    /// 字幕ではないとして捨てる。
    private func captionPayload(from item: AVMetadataItem) -> Data? {
        guard let bytes = metadataItemBytes(item) else { return nil }
        var payload = bytes
        var ownerPrefix = Data()
        ownerPrefix.append(contentsOf: "aribb24.js".utf8)
        ownerPrefix.append(0)
        if payload.starts(with: ownerPrefix) {
            payload = Data(payload.dropFirst(ownerPrefix.count))
        }
        guard payload.count >= 3 else { return nil }
        let head = [UInt8](payload.prefix(3))
        guard (head[0] == 0x80 || head[0] == 0x81), head[1] == 0xFF, head[2] == 0xF0 else {
            return nil
        }
        return payload
    }

    /// 受け取った項目からバイト列を取り出す。
    /// データ値があればそれを、無ければ値そのもの (データとして入っている
    /// 場合) や文字列値を使う。
    private func metadataItemBytes(_ item: AVMetadataItem) -> Data? {
        if let dataValue = item.dataValue {
            return dataValue
        }
        if let valueData = item.value as? NSData {
            return valueData as Data
        }
        if let stringValue = item.stringValue {
            return stringValue.data(using: .utf8)
        }
        return nil
    }
}

// MARK: - コメント一覧の表の受け口

extension PlayerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        jikkyoComments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 行を選ぶ処理側と同じく、範囲の確認をしてから取り出す
        // (配列の差し替えと表の更新がずれたときに落ちないため)。
        guard jikkyoComments.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: CommentListCell.reuseIdentifier, for: indexPath) as! CommentListCell
        let comment = jikkyoComments[indexPath.row]
        cell.configure(text: comment.text, timeText: TimeFormat.hms(comment.time))
        return cell
    }

    /// 行を押したら、そのコメントの時刻へ移動する (Web 版コメント一覧と
    /// 同じ)。移動後は、その行から追随を続ける。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard jikkyoComments.indices.contains(indexPath.row) else { return }
        commentFollowIndex = indexPath.row
        commentListManualScrollAt = nil
        seek(to: jikkyoComments[indexPath.row].time)
    }

    /// 利用者が一覧を手でスクロールしたら、しばらく追随を止める
    /// (Web 版も手動スクロール中は自動で動かさない)。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView === commentTableView {
            commentListManualScrollAt = Date()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === commentTableView {
            commentListManualScrollAt = Date()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === commentTableView {
            commentListManualScrollAt = Date()
        }
    }
}

/// コメント一覧の1行 (Web 版コメント一覧と同じ: 本文 13pt の左寄せ +
/// 右端に時刻 13pt の薄い色)。本文は折り返して全部出す。
private final class CommentListCell: UITableViewCell {
    static let reuseIdentifier = "CommentListCell"

    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppPalette.background
        // 押したときの地は Web 版の hover に相当する一段明るい面にする。
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = AppPalette.pressed
        selectedBackgroundView = selectedBackground

        bodyLabel.font = .scaledSystemFont(ofSize: 13)
        bodyLabel.textColor = AppPalette.text
        bodyLabel.numberOfLines = 0
        timeLabel.font = .scaledMonospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timeLabel.textColor = AppPalette.metaText
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [bodyLabel, timeLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, timeText: String) {
        bodyLabel.text = text
        timeLabel.text = timeText
    }
}
