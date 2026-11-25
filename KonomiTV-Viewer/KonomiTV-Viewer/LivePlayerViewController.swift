import UIKit

#if canImport(VLCKit)
import VLCKit
#endif

/// 生放送の再生画面。サーバーは MPEG-TS の流しっぱなし形式しか出していないため、
/// AVPlayer ではなく VLCKit (VLCKit) で再生する。
/// VLCKit が組み込まれていないビルドでは、その旨を表示するだけになる。
final class LivePlayerViewController: UIViewController {
    private let channel: LiveChannel
    private var audioOnly = false
    /// 再生を始めるときに決めた回線の区分。この再生の間は固定する
    /// (途中で回線が変わっても画質は変えない)。ただし、再生画面での
    /// 手動切り替え (モバイル回線向け画質) のときだけ、その場で変える。
    private var profile: PlaybackProfile
    /// 再生中の画質。初期値は設定のテレビ側の画質 (そのときの回線の区分の値)。
    private var quality: String
    /// 画質の切り替えが完了した時点で設定へ書き戻すための控え (録画再生と同じ)。
    private var pendingQualityWriteBack: String?

    /// 映像の枠。描画先と操作の重ね物を兄弟として持つ。
    private let videoArea = UIView()
    private let videoView = UIView()
    /// 映像の下辺に重ねる操作帯 (グラデーション + 放送中の番組の時刻)。
    private let bottomGradient = GradientView(direction: .bottom)
    private let controlsContainer = UIView()
    /// 操作ボタンは共通部品の波紋つきボタン (押したときの反応)。
    private let playPauseButton = RippleButton()
    private let liveTimeLabel = UILabel()
    /// 映像の下の情報欄 (Web 版パネルに相当)。
    private let scrollView = UIScrollView()
    private let logoImageView = UIImageView()
    private let channelNumberLabel = UILabel()
    private let channelNameLabel = UILabel()
    private let infoTitleLabel = UILabel()
    private let infoTimeLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let statusLabel = UILabel()
    private let nextHeaderLabel = UILabel()
    private let nextTitleLabel = UILabel()
    private let nextTimeLabel = UILabel()
    private let qualityButton = RippleButton()
    private let profileButton = RippleButton()
    private let audioOnlyButton = RippleButton()
    private let fullscreenButton = RippleButton()
    private let settingsButton = RippleButton()
    private let pipButton = RippleButton()
    private let captureButton = RippleButton()
    private let commentCaptureButton = RippleButton()
    private let captureController = VideoCaptureController()
    private var pipController: PlaybackPiPController?
    private var vlcStateObserver: VLCStateObserver?
    private weak var playbackNavigation: UINavigationController?
    private weak var playbackTabs: MainTabBarController?
    private var playbackTabIndex = 0
    private weak var activeFullscreen: LiveFullscreenViewController?
    private let overlayTopGradient = GradientView(direction: .top)
    private lazy var overlayHeader = PlayerOverlayHeader(title: channel.name) { [weak self] in
        self?.navigationController?.popViewController(animated: true)
    }
    private let messageLabel = NoticeLabel()
    private var videoHeightConstraint: NSLayoutConstraint?
    /// 映像の枠を通常画面に固定する決まり (制約) の控え。全画面へ貸し出す
    /// ときに外し、戻すときに付け直すために持っておく。
    private var videoViewHomeConstraints: [NSLayoutConstraint] = []
    /// 全画面へ貸し出し中に、映像の枠を全画面側へ固定する決まり (制約)。
    private var videoViewBorrowConstraints: [NSLayoutConstraint] = []
    /// 映像タップの受け口。貸し出し中は止める (全画面側のタップと二重に
    /// 効かないようにするため)。
    private weak var videoTapRecognizer: UITapGestureRecognizer?
    /// 操作帯の出し入れ (録画再生と同じ作り)。
    private var controlsVisible = true
    private var hideTimer: Timer?

#if canImport(VLCKit)
    private var vlcPlayer: VLCMediaPlayer?
#endif
    private var nowPlayingBegun = false
    /// 開始の見張り (録画側と同じ作り)。再生が始まったら止める。
    private var startWatchdog: Timer?
    private var didStartPlaying = false

    // MARK: - 字幕 (生放送)
    /// 字幕の本体 (録画と同じ部品)。生放送では、流れの中の時刻印の差を
    /// 再生位置に読み替えて蓄える (AribCaption.swift の ingestLivePackets)。
    private let captionEngine = CaptionDisplayEngine()
    /// 字幕の重ね物。映像の枠 (videoArea) の中に入れ、全画面では映像の
    /// 枠と一緒に貸し出す (データ放送の重ね合わせと同じ扱い)。
    private let captionOverlayView = CaptionOverlayView()
    private var captionHomeConstraints: [NSLayoutConstraint] = []
    private var captionBorrowConstraints: [NSLayoutConstraint] = []
    /// 字幕表示のオン/オフ (操作帯の中。録画と同じ置き場所・同じ設定)。
    private let captionButton = RippleButton()
    /// 字幕の更新タイマー (0.25秒ごと)。再生部品の時計に合わせて字幕の
    /// 絵を進める。
    private var captionTimer: Timer?
    /// 字幕の位置合わせの基準 (この接続での最初の映像の時刻印)。
    /// 接続が替わって基準が変わったら、蓄えを作り直す。
    private var liveCaptionBasePTS: Int64?
    /// 字幕の時刻合わせの補正 (秒)。実機の確認でずれが無いことが
    /// 分かったため、0 のままで確定。
    private static let liveCaptionTimeOffset = 0.0

    // MARK: - パネル (番組情報/チャンネル/コメント) と実況コメント
    /// パネルのタブ (Web 版と同じ3つ。値は利用者設定の保存名と同じ)。
    private enum PanelTab: String {
        case program = "Program"
        case channel = "Channel"
        case comment = "Comment"
    }
    private var selectedPanelTab: PanelTab = .program
    private let panelTabBar = UIView()
    private let programTabButton = RippleButton()
    private let programTabIconView = UIImageView()
    private let programTabTitleLabel = UILabel()
    private let channelTabButton = RippleButton()
    private let channelTabIconView = UIImageView()
    private let channelTabTitleLabel = UILabel()
    private let commentTabButton = RippleButton()
    private let commentTabIconView = UIImageView()
    private let commentTabTitleLabel = UILabel()

    // チャンネルパネル
    private let channelPanel = UIView()
    private let channelCategoryScrollView = UIScrollView()
    private let channelCategoryStack = UIStackView()
    private let channelStatusLabel = UILabel()
    private var channelPanelStatusWrap: UIView?
    private let channelTableView = UITableView(frame: .zero, style: .plain)
    private var channelGroups: [(type: String, channels: [LiveChannel])] = []
    private var channelResponse: LiveChannelsResponse?
    private var selectedChannelGroupIndex = 0
    private var channelPanelLoaded = false
    private var channelPanelLoading = false
    /// 一覧の左右スワイプで分類を切り替えるためのしぐさ (生放送一覧と
    /// 同じ考え方で、横の動きだけを拾う)。
    private let channelGroupSwipePan = UIPanGestureRecognizer()

    // コメントパネルと実況コメント
    private let commentPanel = UIView()
    private let commentStatusLabel = UILabel()
    private var commentPanelStatusWrap: UIView?
    private let commentTableView = UITableView(frame: .zero, style: .plain)
    private let commentEmptyLabel = UILabel()
    private let commentJumpButton = RippleButton()
    private let commentTextField = UITextField()
    private let commentSendButton = RippleButton()
    private var commentFormBottomConstraint: NSLayoutConstraint?
    private var postColorButtons: [RippleButton] = []
    private var selectedPostColorName = "white"
    private let postPositionSegment = UISegmentedControl(items: ["上", "流れ", "下"])
    private let postSizeSegment = UISegmentedControl(items: ["大", "中", "小"])
    /// 届いた実況コメント (一覧の元。初回のまとめも含む)。
    private var liveComments: [LiveJikkyoComment] = []
    /// コメントの初期化に失敗したときの文 (無ければ nil)。
    private var commentInitFailure: String?
    /// 一覧が新しいコメントへ追随するかどうか (手で遡っている間は切る)。
    private var commentFollow = true
    private var commentTabHasBeenShown = false
    /// 実況コメントの土台 (2本の窓口の管理)。
    private var commentSession: LiveCommentSession?
    /// コメントを映像の上に流す重ね物 (録画と同じ描き手)。
    private let commentOverlay = JikkyoCommentOverlayView()
    private var commentHomeConstraints: [NSLayoutConstraint] = []
    private var commentBorrowConstraints: [NSLayoutConstraint] = []
    /// コメント表示のオン/オフ (操作帯の中。録画と同じ置き場所・設定)。
    private let commentButton = RippleButton()
    /// 流れる表示の仮想の時計 (秒)。再生中だけ進む (止まっている間は
    /// コメントも止めるため)。liveCommentNow() で読む。
    private var liveCommentClockOffset: Double = 0
    private var liveCommentClockStart: Date?
    /// 流れる表示を遅らせる量 (秒)。映像の溜めの量 (低遅延の設定で
    /// 変わる) から startStream で決める。
    private var liveCommentDelaySeconds: Double = 4

    // MARK: - データ放送 (重ね合わせ)
    /// リモコンの浮きボタン (情報欄の右下に浮かせ、押すとリモコンの
    /// パネルが出る。Web 版の浮きボタンと同じ置き場所)。
    /// 設定でデータ放送機能がオフのときは出さない。
    private let remoteFloatingButton = RippleButton()
    private var dataBroadcastOverlay: DataBroadcastOverlay?
    private var isDataBroadcastActive = false
    /// 知らせ欄にデータ放送の状態を出しているかどうか。
    private var showingDataBroadcastStatus = false
    /// 「データ」を押して開始したとき、常駐文書が開けたところで
    /// データボタンの合図 (20) を送るための控え。
    private var pendingDataKey = false
    /// 常駐文書まで開けたかどうか (読み込み中かどうかの判定に使う)。
    private var dataBroadcastLoaded = false
    /// 開始が失敗したままかどうか。失敗のままなら、次の「データ」で
    /// 作り直して開始し直す。
    private var dataBroadcastStartFailed = false
    /// リモコンのパネル (Web 版と同じ顔ぶれ) と、その後ろの幕。
    /// 置き場所は出すたびに決める (通常画面では映像の下、全画面では
    /// 右端) ため、置き場所の決まりは控えに分けて付け替える。
    private var remoteBackdrop: UIView?
    private var remotePanel: UIView?
    private var remotePlacementConstraints: [NSLayoutConstraint] = []
    private var remoteSpinner: UIActivityIndicatorView?
    /// 双方向の通信中かどうか (つなぎからの知らせで切り替わる)。
    /// リモコンの読み込み中のぐるぐるの判定に使う。
    private var dataBroadcastNetworkBusy = false
    /// 「データ」以外のデータ放送キー (十字・戻る・色・数字) の置き場。
    /// 始まっていない間と読み込み中は薄くして押せなくする
    /// (Web 版の使えない間の見せ方と同じ)。
    private var remoteDimmableViews: [UIView] = []
    /// 重ね合わせを通常画面に固定する決まり (制約) の控え。
    private var bmlHomeConstraints: [NSLayoutConstraint] = []
    /// 全画面へ貸し出し中に、重ね合わせを全画面側へ固定する決まり (制約)。
    private var bmlBorrowConstraints: [NSLayoutConstraint] = []

    init(channel: LiveChannel) {
        self.channel = channel
        // 回線の区分はこの時点で決める。手動切り替えの記憶があればそれを
        // 優先し、無ければ現在の回線から決める (Web 版の優先順位と同じ)。
        // 画質はテレビ側のその区分の値から始める。
        let profile = SettingsStore.shared.initialPlaybackProfile()
        self.profile = profile
        self.quality = SettingsStore.shared.streamingQuality(media: .tv, profile: profile)
        super.init(nibName: nil, bundle: nil)
        title = channel.name
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        PlaybackPiPController.stopCurrentPlayback()
        captureController.onStateChanged = { [weak self] in self?.updateCaptureControls() }
        captureController.onError = { [weak self] message in self?.showCaptureError(message) }
        captureController.onResult = { [weak self] message in self?.showCaptureError(message) }
        view.backgroundColor = AppPalette.background
        // 生放送の文字スーパーは、字幕の設定のテレビ側の項目に従う
        // (Web 版の生放送の扱いと同じ)。
        captionEngine.useTVSuperimposeSetting = true
        // パネルのタブは、前回開いていたものを引き継ぐ (利用者設定)。
        selectedPanelTab = PanelTab(
            rawValue: SyncedSettingsStore.shared.current.tvPanelActiveTab) ?? .program
        buildLayout()
        applyCaptionDisplayState()
        applyPanelTab(selectedPanelTab, save: false)
        // 実況コメントの流れる表示の用意 (録画と同じ描き手・同じ設定)。
        commentOverlay.positionProvider = { [weak self] in self?.liveCommentNow() ?? 0 }
        let synced = SyncedSettingsStore.shared.current
        commentOverlay.displayOpacity = SettingsStore.shared.commentOpacity
        commentOverlay.speedRate = synced.commentSpeedRate
        commentOverlay.fontSizeReference = synced.commentFontSize
        commentOverlay.unlimited = SettingsStore.shared.showCommentsUnlimited
        commentOverlay.setDisplayEnabled(SettingsStore.shared.showComments && !audioOnly)
        commentOverlay.start()
        startStream()
        // 実況コメントの接続は、画面が開ききってから始める
        // (startCommentSession は viewDidAppear 側。開く処理の最中に
        // 接続や一覧の更新が重なると、落ちる原因になりうるため)。
    }

    /// 実況コメントの接続を始めたかどうか (1回だけ始める)。
    private var commentSessionStarted = false
    /// 画面を離れるときに再生とコメント接続を止めたかどうか。
    /// 戻ってきたときに再開するために使う (全画面で覆われただけの
    /// ときは止めないため、その場合は印も付かない)。
    private var stoppedOnDisappear = false
    /// 離れる直前に再生中だったかどうか。戻ってきたときに、止めて
    /// いた場合は作り直したあとも止めたままにするため。
    private var wasPlayingBeforeStop = true

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if stoppedOnDisappear {
            // 上に重ねた画面 (ミュート設定など) から戻ってきたときは、
            // 離れるときに止めた再生と実況コメントを再開する。
            // コメントの接続は、止めた側を使い回さず新しく張り直す
            // (止めた側に残っている張り直しの予約と重ならないため)。
            stoppedOnDisappear = false
            commentOverlay.start()
            startStream()
            if !wasPlayingBeforeStop {
                pauseStream()
            }
            startCommentSession()
            return
        }
        guard !commentSessionStarted else { return }
        commentSessionStarted = true
        startCommentSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        playbackNavigation = navigationController
        playbackTabs = mainTabBarController
        playbackTabIndex = playbackTabs?.selectedIndex ?? playbackTabIndex
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 設定でデータ放送機能のオン/オフが変わっていたら、入り口の
        // 出し分けと実行中の重ね合わせに反映する。
        refreshDataBroadcastAvailability()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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
        if pipController?.isActive == true || pipController?.isPending == true { return }
        // フルスクリーン表示で覆われただけのときは再生を止めない。
        // それ以外で画面を離れるときは今までどおり止める。
#if canImport(VLCKit)
        if presentedViewController is LiveFullscreenViewController {
            return
        }
#endif
        if (presentedViewController is ViewerNavigationController || presentedViewController is UIActivityViewController), !isBeingDismissed { return }
        hideRemotePanelImmediately()
        stopDataBroadcast()
        // 戻ってきたときに再開できるよう、止めることと、再生中だった
        // かどうかを控えておく。
        stoppedOnDisappear = true
#if canImport(VLCKit)
        wasPlayingBeforeStop = vlcPlayer?.isPlaying ?? false
#else
        wasPlayingBeforeStop = false
#endif
        // 実況コメントの接続と流れる表示も止める。
        commentSession?.stop()
        commentOverlay.stop()
        stopStream()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 映像の高さ: 幅なりの 16:9 が下の領域の最低限 (タブ 50pt +
        // パネル 120pt) を残して収まるならそのまま、収まらない
        // (主に横向き) なら収まる高さまで縮める。
        // 映像は VLC 側で全体が収まるように描かれるため、切れることはない。
        if let heightConstraint = videoHeightConstraint {
            let ideal = view.bounds.width * 9.0 / 16.0
            let available = view.bounds.height
                - view.safeAreaInsets.top
                - view.safeAreaInsets.bottom
                - 170
            let target = max(120, min(ideal, available))
            if abs(heightConstraint.constant - target) > 0.5 {
                heightConstraint.constant = target
            }
        }
    }

    private func buildLayout() {
        // MARK: 映像まわり (映像 + 下辺に重ねる操作帯)
        videoArea.backgroundColor = .black
        videoArea.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoArea)

        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoArea.addSubview(videoView)
        overlayTopGradient.translatesAutoresizingMaskIntoConstraints = false
        overlayHeader.translatesAutoresizingMaskIntoConstraints = false
        // 描画面より上、操作帯より後ろに置く。映像の借用にはヘッダーを含めない。

        // 映像をタップしたら操作帯を出し入れする (Web 版と同じ作り)。
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        videoView.addGestureRecognizer(tap)
        videoTapRecognizer = tap

        // 再生・一時停止は下の帯から出し、映像の真ん中に置く
        // (本家 Web 版の中央の並びと同じ置き場所。生放送には少し戻る/
        // 少し進むの土台が無いため、真ん中に置くのはこの1つだけ)。
        // 絵は 36、当たり判定は 64x64。
        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false

        // 操作帯には、放送中の番組の時刻 (左) と字幕・コメントの
        // 切り替え (右) を置く (Web 版の操作帯の並びに相当。
        // 字幕・コメントのボタンは録画と同じ顔ぶれ)。
        liveTimeLabel.text = channel.program_present.map { programTimeText($0) } ?? ""
        liveTimeLabel.textColor = AppPalette.text
        liveTimeLabel.font = .scaledSystemFont(ofSize: 13, weight: .medium)
        captionButton.addTarget(self, action: #selector(toggleCaptions), for: .touchUpInside)
        updateCaptionButton()
        commentButton.addTarget(self, action: #selector(toggleComments), for: .touchUpInside)
        updateCommentButton()
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
        styleVideoOverlayButton(commentCaptureButton, symbol: "camera.badge.ellipsis", title: "コメント付きキャプチャ", adaptive: true)
        captureButton.addAction(UIAction { [weak self] _ in guard let self else { return }; self.captureVideo(comments: false, presenter: self) }, for: .touchUpInside)
        commentCaptureButton.addAction(UIAction { [weak self] _ in guard let self else { return }; self.captureVideo(comments: true, presenter: self) }, for: .touchUpInside)
        liveTimeLabel.adjustsFontSizeToFitWidth = true
        liveTimeLabel.minimumScaleFactor = 0.65
        liveTimeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let controlsRow = PlayerActionRow(time: liveTimeLabel, buttons: [captureButton, commentCaptureButton, commentButton, captionButton, settingsButton, pipButton, fullscreenButton])
        controlsRow.translatesAutoresizingMaskIntoConstraints = false

        bottomGradient.translatesAutoresizingMaskIntoConstraints = false
        videoArea.addSubview(bottomGradient)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsRow)
        videoArea.addSubview(controlsContainer)
        // 真ん中の再生・一時停止は操作帯より上に置く (映像が低いときでも
        // 帯に触れて押せなくならないように)。
        videoArea.addSubview(playPauseButton)

        // 字幕の重ね物 (映像の上に重ねる。操作は受けない)。
        // 置き場所の決まりは貸し出し・返却で付け替えるため控えに持つ
        // (データ放送の重ね合わせと同じ作り)。
        captionOverlayView.translatesAutoresizingMaskIntoConstraints = false
        videoArea.addSubview(captionOverlayView)
        captionHomeConstraints = [
            captionOverlayView.topAnchor.constraint(equalTo: videoArea.topAnchor),
            captionOverlayView.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            captionOverlayView.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            captionOverlayView.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
        ]
        NSLayoutConstraint.activate(captionHomeConstraints)

        // 実況コメントの流れる表示の重ね物 (映像の上に重ねる。
        // 操作は受けない)。字幕より下に置く (字幕が一番上)。
        commentOverlay.translatesAutoresizingMaskIntoConstraints = false
        videoArea.addSubview(commentOverlay)
        commentHomeConstraints = [
            commentOverlay.topAnchor.constraint(equalTo: videoArea.topAnchor),
            commentOverlay.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            commentOverlay.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            commentOverlay.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
        ]
        NSLayoutConstraint.activate(commentHomeConstraints)
        // 字幕をコメントより上に戻す (この後ろに足した分だけ)。
        videoArea.bringSubviewToFront(captionOverlayView)

        // MARK: 映像の下の情報欄 (Web 版パネル)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = AppPalette.background
        view.addSubview(scrollView)

        messageLabel.textColor = .systemYellow
        messageLabel.font = .scaledSystemFont(ofSize: 12.5)
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true

        // 局の並び (生放送パネルでは先頭): ロゴ 58x32 (角丸 3pt) + Ch 番号 16.5pt + 局名 18pt。
        logoImageView.backgroundColor = AppPalette.placeholder
        logoImageView.contentMode = .scaleAspectFill
        logoImageView.clipsToBounds = true
        logoImageView.layer.cornerRadius = 3
        channelNumberLabel.text = channel.channel_number.map { "Ch: \($0)" } ?? "Ch: --"
        channelNumberLabel.textColor = AppPalette.text
        channelNumberLabel.font = .scaledSystemFont(ofSize: 16.5)
        channelNumberLabel.setContentHuggingPriority(.required, for: .horizontal)
        channelNameLabel.text = channel.name
        channelNameLabel.textColor = AppPalette.text
        channelNameLabel.font = .scaledSystemFont(ofSize: 18)
        channelNameLabel.numberOfLines = 1
        channelNameLabel.lineBreakMode = .byTruncatingTail
        let broadcasterRow = UIStackView(arrangedSubviews: [logoImageView, channelNumberLabel, channelNameLabel])
        broadcasterRow.axis = .horizontal
        broadcasterRow.spacing = 5
        broadcasterRow.alignment = .center
        broadcasterRow.setCustomSpacing(12, after: logoImageView)
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 58),
            logoImageView.heightAnchor.constraint(equalToConstant: 32),
        ])
        loadChannelLogo()

        // 番組名: パネルの見出し (19pt 太字)。
        infoTitleLabel.text = channel.program_present?.title
        infoTitleLabel.textColor = AppPalette.text
        infoTitleLabel.font = .scaledSystemFont(ofSize: 19, weight: .bold)
        infoTitleLabel.numberOfLines = 0

        // 番組の時刻: 14pt、色は text-darken-1。
        infoTimeLabel.text = channel.program_present.map { programTimeText($0) } ?? ""
        infoTimeLabel.textColor = AppPalette.metaText
        infoTimeLabel.font = .scaledSystemFont(ofSize: 14)

        // 説明: 12pt、行間 168% 相当、色は text-darken-1。
        if let description = channel.program_present?.description, !description.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 12 * 0.68
            descriptionLabel.attributedText = NSAttributedString(string: description, attributes: [
                .font: UIFont.scaledSystemFont(ofSize: 12),
                .foregroundColor: AppPalette.metaText,
                .paragraphStyle: paragraph,
            ])
        }
        descriptionLabel.numberOfLines = 0

        // 勢い・視聴数: 12.5pt、色は text-darken-1。
        var statusParts: [String] = []
        statusParts.append("勢い: \(channel.jikkyo_force.map(String.init) ?? "--") コメ/分")
        statusParts.append("視聴数: \(channel.viewer_count.map(String.init) ?? "--")")
        statusLabel.text = statusParts.joined(separator: "　")
        statusLabel.textColor = AppPalette.metaText
        statusLabel.font = .scaledSystemFont(ofSize: 12.5)
        statusLabel.numberOfLines = 0

        // 次の番組 (NEXT): 見出し + 題名 + 時刻。
        nextHeaderLabel.text = "NEXT"
        nextHeaderLabel.textColor = AppPalette.text
        nextHeaderLabel.font = .scaledSystemFont(ofSize: 12.5, weight: .bold)
        nextTitleLabel.text = channel.program_following?.title
        nextTitleLabel.textColor = AppPalette.text
        nextTitleLabel.font = .scaledSystemFont(ofSize: 13.5)
        nextTitleLabel.numberOfLines = 0
        nextTimeLabel.text = channel.program_following.map { programTimeText($0) } ?? ""
        nextTimeLabel.textColor = AppPalette.metaText
        nextTimeLabel.font = .scaledSystemFont(ofSize: 12)
        let hasNext = channel.program_following != nil
        for label in [nextHeaderLabel, nextTitleLabel, nextTimeLabel] {
            label.isHidden = !hasNext
        }

        // 操作の小さなボタン群 (Web 版パネルのボタンの形)。
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.showsMenuAsPrimaryAction = true
        qualityButton.menu = makeQualityMenu()
        // 画質プロファイルの手動切り替え (Web 版プレイヤーの設定パネルにある
        // 「モバイル回線向け画質」のトグルにあたる)。オン = モバイル回線向け。
        profileButton.addTarget(self, action: #selector(toggleProfile), for: .touchUpInside)
        updateProfileButtonTitle()
        audioOnlyButton.setTitle("音声のみ: OFF", for: .normal)
        audioOnlyButton.addTarget(self, action: #selector(toggleAudioOnly), for: .touchUpInside)
        // 全画面は映像内の専用アイコンを使う。
        fullscreenButton.addTarget(self, action: #selector(showFullscreen), for: .touchUpInside)
        for button in [qualityButton, profileButton, audioOnlyButton] {
            stylePlayerChip(button)
        }
        videoArea.addSubview(overlayTopGradient)
        videoArea.addSubview(overlayHeader)
        NSLayoutConstraint.activate([
            overlayTopGradient.topAnchor.constraint(equalTo: videoArea.topAnchor),
            overlayTopGradient.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            overlayTopGradient.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
            overlayTopGradient.heightAnchor.constraint(equalToConstant: 52),
            overlayHeader.topAnchor.constraint(equalTo: videoArea.topAnchor),
            overlayHeader.leadingAnchor.constraint(equalTo: videoArea.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            overlayHeader.trailingAnchor.constraint(equalTo: videoArea.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            overlayHeader.heightAnchor.constraint(equalToConstant: 44),
        ])

        // データ放送の重ね合わせ。入り口は情報欄の右下に浮かせた丸ボタン
        // (Web 版の浮きボタンと同じ: 48x48 の円、地は panel、余白 16)。
        // 押すとリモコンのパネルが出る。データ放送の開始はパネルの
        // 「データ」ボタンから行う (テレビで dボタンを押して開くのと
        // 同じ入り口)。パネル本体は buildRemotePanel() で作る。
        // データ放送は素のサーバーの機能なので、改造版サーバーの
        // 機能のトグルの対象にはしない。ただし設定 (設定 → データ放送)
        // でデータ放送機能がオフのときは、入り口自体を出さない。
        remoteFloatingButton.setImage(
            UIImage(systemName: "appletvremote.gen4.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))
                ?? UIImage(systemName: "tv", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25)),
            for: .normal
        )
        remoteFloatingButton.tintColor = AppPalette.text
        remoteFloatingButton.backgroundColor = AppPalette.panel
        remoteFloatingButton.layer.cornerRadius = 24
        remoteFloatingButton.layer.shadowColor = UIColor.black.cgColor
        remoteFloatingButton.layer.shadowOpacity = 0.3
        remoteFloatingButton.layer.shadowRadius = 6
        remoteFloatingButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        remoteFloatingButton.accessibilityLabel = "リモコン"
        remoteFloatingButton.addTarget(self, action: #selector(showRemotePanel), for: .touchUpInside)
        remoteFloatingButton.translatesAutoresizingMaskIntoConstraints = false
        remoteFloatingButton.isHidden = !SettingsStore.shared.dataBroadcastingEnabled

        let infoStack = UIStackView(arrangedSubviews: [
            messageLabel, broadcasterRow, infoTitleLabel, infoTimeLabel, descriptionLabel,
            statusLabel, nextHeaderLabel, nextTitleLabel, nextTimeLabel,

        ])
        infoStack.axis = .vertical
        infoStack.spacing = 12
        infoStack.isLayoutMarginsRelativeArrangement = true
        infoStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        // Web 版パネルの余白: 番組名は局の並びから 16pt、時刻は 8pt、説明は 12pt。
        infoStack.setCustomSpacing(16, after: broadcasterRow)
        infoStack.setCustomSpacing(8, after: infoTitleLabel)
        infoStack.setCustomSpacing(16, after: statusLabel)
        infoStack.setCustomSpacing(4, after: nextHeaderLabel)
        infoStack.setCustomSpacing(2, after: nextTitleLabel)
        infoStack.setCustomSpacing(16, after: nextTimeLabel)
        scrollView.addSubview(infoStack)

        // 映像の高さは viewDidLayoutSubviews で決める (16:9 と画面に収まる高さの小さい方)。
        let heightConstraint = videoArea.heightAnchor.constraint(equalToConstant: 200)
        videoHeightConstraint = heightConstraint

        // 映像の枠の固定は、貸し出し・返却で付け外しできるよう別に持つ。
        videoViewHomeConstraints = [
            videoView.topAnchor.constraint(equalTo: videoArea.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
        ]
        NSLayoutConstraint.activate(videoViewHomeConstraints)

        // MARK: パネルのタブと、チャンネル/コメントのパネル
        // パネル本体は、置き場所の決まり (この後の activate) より先に
        // 画面へ足しておく。足す前に決まりだけを有効にすると、共通の
        // 親を持たない部品同士の決まりとして例外になり、画面を開いた
        // 直後に落ちる (0.17〜0.20 で発生した不具合の原因)。
        buildPanelTabBar()
        buildChannelPanel()
        buildCommentPanel()

        NSLayoutConstraint.activate([
            videoArea.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            videoArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightConstraint,
            bottomGradient.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            bottomGradient.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
            bottomGradient.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            bottomGradient.heightAnchor.constraint(equalToConstant: 64),
            controlsContainer.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            controlsContainer.heightAnchor.constraint(equalToConstant: 52),
            controlsRow.leadingAnchor.constraint(equalTo: videoArea.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            controlsRow.trailingAnchor.constraint(equalTo: videoArea.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            controlsRow.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: videoArea.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: videoArea.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 64),
            playPauseButton.heightAnchor.constraint(equalToConstant: 64),
            panelTabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            panelTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelTabBar.heightAnchor.constraint(equalToConstant: 50),
            scrollView.topAnchor.constraint(equalTo: videoArea.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panelTabBar.topAnchor),
            channelPanel.topAnchor.constraint(equalTo: videoArea.bottomAnchor),
            channelPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            channelPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelPanel.bottomAnchor.constraint(equalTo: panelTabBar.topAnchor),
            commentPanel.topAnchor.constraint(equalTo: videoArea.bottomAnchor),
            commentPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentPanel.bottomAnchor.constraint(equalTo: panelTabBar.topAnchor),
            infoStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            infoStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            infoStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            infoStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // リモコンの浮きボタンは情報欄の右下に浮かせる (映像には重ねない)。
        view.addSubview(remoteFloatingButton)
        NSLayoutConstraint.activate([
            remoteFloatingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            remoteFloatingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            remoteFloatingButton.widthAnchor.constraint(equalToConstant: 48),
            remoteFloatingButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        // リモコンのパネルと幕は、開いたときに一番上へ来るよう最後に足す。
        buildRemotePanel()
        restoreControlLayerOrder()
    }

    /// 局ロゴを読み込む (取れなければ読み込み前の地のまま)。
    private func loadChannelLogo() {
        let channelID = channel.id
        Task { [weak self] in
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channelID),
                  let image = UIImage(data: data) else { return }
            self?.logoImageView.image = image
        }
    }

    /// 番組の時刻表示 (Web 版パネルの時刻と同じ形)。
    private func programTimeText(_ program: LiveProgram) -> String {
        guard let start = program.startDate, let end = program.endDate else {
            return program.timeRangeText
        }
        return "\(TimeFormat.dateTime(start)) ～ \(TimeFormat.hourMinute(end))"
    }

    // MARK: - パネルのタブ (番組情報/チャンネル/コメント)

    /// パネルのタブの帯を作る (録画再生の情報欄のタブと同じ形:
    /// 絵の上に文字の縦並び、選択中は primary の色)。
    private func buildPanelTabBar() {
        panelTabBar.backgroundColor = AppPalette.background
        panelTabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelTabBar)
        buildPanelTabButton(programTabButton, iconView: programTabIconView,
                            titleLabel: programTabTitleLabel,
                            symbol: "info.circle", title: "番組情報",
                            action: #selector(selectProgramTab))
        buildPanelTabButton(channelTabButton, iconView: channelTabIconView,
                            titleLabel: channelTabTitleLabel,
                            symbol: "antenna.radiowaves.left.and.right", title: "チャンネル",
                            action: #selector(selectChannelTab))
        buildPanelTabButton(commentTabButton, iconView: commentTabIconView,
                            titleLabel: commentTabTitleLabel,
                            symbol: "text.bubble.fill", title: "コメント",
                            action: #selector(selectCommentTab))
        let stack = UIStackView(arrangedSubviews: [programTabButton, channelTabButton, commentTabButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelTabBar.addSubview(stack)
        let divider = UIView()
        divider.backgroundColor = AppPalette.pressed
        divider.translatesAutoresizingMaskIntoConstraints = false
        panelTabBar.addSubview(divider)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panelTabBar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panelTabBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panelTabBar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: panelTabBar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: panelTabBar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: panelTabBar.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: panelTabBar.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    /// パネルのタブボタンの中身 (絵の上に文字の縦並び) を作る。
    private func buildPanelTabButton(_ button: RippleButton, iconView: UIImageView,
                                     titleLabel: UILabel, symbol: String, title: String,
                                     action: Selector) {
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

    /// タブの色を選択状態に合わせる (選択中は primary、他は通常の文字色)。
    private func updatePanelTabButtons() {
        let tabs: [(PanelTab, UIImageView, UILabel)] = [
            (.program, programTabIconView, programTabTitleLabel),
            (.channel, channelTabIconView, channelTabTitleLabel),
            (.comment, commentTabIconView, commentTabTitleLabel),
        ]
        for (tab, iconView, titleLabel) in tabs {
            let color = tab == selectedPanelTab ? AppPalette.accent : AppPalette.text
            iconView.tintColor = color
            titleLabel.textColor = color
        }
    }

    @objc private func selectProgramTab() { applyPanelTab(.program) }
    @objc private func selectChannelTab() { applyPanelTab(.channel) }
    @objc private func selectCommentTab() { applyPanelTab(.comment) }

    /// パネルを切り替える。切り替えの状態は利用者設定に保存し、
    /// 次に開いたとき (と Web 版) に引き継ぐ。
    private func applyPanelTab(_ tab: PanelTab, save: Bool = true) {
        selectedPanelTab = tab
        if save {
            var settings = SyncedSettingsStore.shared.current
            if settings.tvPanelActiveTab != tab.rawValue {
                settings.tvPanelActiveTab = tab.rawValue
                SyncedSettingsStore.shared.update(settings)
            }
        }
        scrollView.isHidden = tab != .program
        channelPanel.isHidden = tab != .channel
        commentPanel.isHidden = tab != .comment
        updatePanelTabButtons()
        updateRemoteButtonVisibility()
        if tab == .channel {
            loadChannelPanelIfNeeded()
        }
        if tab == .comment, !commentTabHasBeenShown {
            // 初回だけ末尾へ合わせ、再訪時は手動で遡った位置と追随状態を保つ。
            commentTabHasBeenShown = true
            commentFollow = true
            commentJumpButton.isHidden = true
            scrollCommentListToBottom(animated: false)
        }
    }

    /// リモコンの浮きボタンの出し分け。Web 版と同じく、番組情報か
    /// チャンネルのパネルを開いているときだけ出す (コメントのパネル
    /// では出さない)。データ放送機能がオフのときは常に出さない。
    private func updateRemoteButtonVisibility() {
        remoteFloatingButton.isHidden =
            !(SettingsStore.shared.dataBroadcastingEnabled && selectedPanelTab != .comment)
    }

    // MARK: - チャンネルパネル

    private func buildChannelPanel() {
        channelPanel.backgroundColor = AppPalette.background
        channelPanel.isHidden = true
        channelPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(channelPanel)

        channelCategoryScrollView.showsHorizontalScrollIndicator = false
        channelCategoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        channelCategoryStack.axis = .horizontal
        channelCategoryStack.spacing = 8
        channelCategoryStack.alignment = .center
        channelCategoryStack.isLayoutMarginsRelativeArrangement = true
        channelCategoryStack.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        channelCategoryStack.translatesAutoresizingMaskIntoConstraints = false
        channelCategoryScrollView.addSubview(channelCategoryStack)

        channelStatusLabel.textColor = AppPalette.metaText
        channelStatusLabel.font = .scaledSystemFont(ofSize: 12.5)
        channelStatusLabel.numberOfLines = 0
        let statusWrap = UIView()
        statusWrap.isHidden = true
        statusWrap.translatesAutoresizingMaskIntoConstraints = false
        channelStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusWrap.addSubview(channelStatusLabel)
        NSLayoutConstraint.activate([
            channelStatusLabel.topAnchor.constraint(equalTo: statusWrap.topAnchor, constant: 4),
            channelStatusLabel.bottomAnchor.constraint(equalTo: statusWrap.bottomAnchor, constant: -4),
            channelStatusLabel.leadingAnchor.constraint(equalTo: statusWrap.leadingAnchor, constant: 16),
            channelStatusLabel.trailingAnchor.constraint(equalTo: statusWrap.trailingAnchor, constant: -16),
        ])
        channelPanelStatusWrap = statusWrap

        channelTableView.dataSource = self
        channelTableView.delegate = self
        channelTableView.register(LiveChannelCell.self, forCellReuseIdentifier: LiveChannelCell.reuseID)
        channelTableView.rowHeight = UITableView.automaticDimension
        channelTableView.estimatedRowHeight = 172
        channelTableView.backgroundColor = AppPalette.background
        channelTableView.separatorStyle = .none
        channelTableView.translatesAutoresizingMaskIntoConstraints = false

        // 一覧の左右スワイプでも分類を切り替えられるようにする
        // (生放送一覧と揃える)。しぐさは一覧に付け、縦スクロールは
        // このしぐさが不成立になるまで待つ (横のときだけ成立する
        // 判定は gestureRecognizerShouldBegin 側)。
        channelGroupSwipePan.addTarget(self, action: #selector(handleChannelGroupSwipe(_:)))
        channelGroupSwipePan.delegate = self
        channelTableView.addGestureRecognizer(channelGroupSwipePan)
        channelTableView.panGestureRecognizer.require(toFail: channelGroupSwipePan)

        let stack = UIStackView(arrangedSubviews: [
            channelCategoryScrollView, statusWrap, channelTableView,
        ])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        channelPanel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: channelPanel.topAnchor),
            stack.bottomAnchor.constraint(equalTo: channelPanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: channelPanel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: channelPanel.trailingAnchor),
            channelCategoryScrollView.heightAnchor.constraint(equalToConstant: 44),
            channelCategoryStack.topAnchor.constraint(
                equalTo: channelCategoryScrollView.contentLayoutGuide.topAnchor),
            channelCategoryStack.bottomAnchor.constraint(
                equalTo: channelCategoryScrollView.contentLayoutGuide.bottomAnchor),
            channelCategoryStack.leadingAnchor.constraint(
                equalTo: channelCategoryScrollView.contentLayoutGuide.leadingAnchor),
            channelCategoryStack.trailingAnchor.constraint(
                equalTo: channelCategoryScrollView.contentLayoutGuide.trailingAnchor),
            channelCategoryStack.heightAnchor.constraint(
                equalTo: channelCategoryScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    /// チャンネルパネルの状態の文を出す (nil で消す)。
    private func setChannelStatus(_ text: String?) {
        channelStatusLabel.text = text
        channelPanelStatusWrap?.isHidden = text == nil
    }

    /// チャンネルパネルを初めて開いたときに、一覧を取りに行く。
    /// 取得済みの印は成功したときにだけ立てる。失敗しても取得済みに
    /// してしまうと、この画面を開いている間は二度と取り直せず、
    /// パネルが空のままになるため。取得中の重なりは別の印で防ぐ。
    private func loadChannelPanelIfNeeded() {
        guard !channelPanelLoaded, !channelPanelLoading else { return }
        channelPanelLoading = true
        setChannelStatus("読み込み中…")
        Task { [weak self] in
            do {
                let response = try await APIClient.shared.fetchChannels()
                guard let self else { return }
                self.channelPanelLoading = false
                self.channelPanelLoaded = true
                self.channelResponse = response
                self.setChannelStatus(nil)
                self.rebuildChannelGroups()
            } catch {
                self?.channelPanelLoading = false
                self?.setChannelStatus("チャンネルを取得できませんでした。")
            }
        }
    }

    /// 取得したチャンネルを、ピン留め + 放送の種類ごとの分類に組み直す
    /// (生放送一覧の画面と同じ並び・絞り込み)。
    private func rebuildChannelGroups() {
        guard let response = channelResponse else { return }
        let synced = SyncedSettingsStore.shared.current
        let sortByForce = synced.tvChannelSortByJikkyoForce
        let allChannels = response.groups.flatMap { $0.channels }
        var pinned = synced.pinnedChannelIDs.compactMap { id in
            allChannels.first { $0.id == id }
        }
        if sortByForce {
            pinned = pinned.enumerated().sorted { lhs, rhs in
                let lhsForce = lhs.element.jikkyo_force ?? 0
                let rhsForce = rhs.element.jikkyo_force ?? 0
                if lhsForce != rhsForce { return lhsForce > rhsForce }
                return lhs.offset < rhs.offset
            }.map(\.element)
        }
        var newGroups: [(type: String, channels: [LiveChannel])] = [("PINNED", pinned)]
        for group in response.groups {
            var channels = group.channels.filter { $0.is_display ?? true }
            if sortByForce {
                channels = channels.enumerated().sorted { lhs, rhs in
                    let lhsForce = lhs.element.jikkyo_force ?? 0
                    let rhsForce = rhs.element.jikkyo_force ?? 0
                    if lhsForce != rhsForce { return lhsForce > rhsForce }
                    return lhs.offset < rhs.offset
                }.map(\.element)
            }
            if !channels.isEmpty {
                newGroups.append((type: group.type, channels: channels))
            }
        }
        // 表示中の分類はなるべく保つ。最初は、今見ているチャンネルの
        // 分類を出す。
        let previousType = channelGroups.indices.contains(selectedChannelGroupIndex)
            ? channelGroups[selectedChannelGroupIndex].type : nil
        channelGroups = newGroups
        if let previousType, let index = newGroups.firstIndex(where: { $0.type == previousType }) {
            selectedChannelGroupIndex = index
        } else if let index = newGroups.firstIndex(where: { group in
            group.channels.contains { $0.id == channel.id }
        }) {
            selectedChannelGroupIndex = index
        } else {
            selectedChannelGroupIndex = 0
        }
        rebuildChannelCategoryChips()
        channelTableView.reloadData()
    }

    /// 分類の切り替えの帯を作り直す。
    private func rebuildChannelCategoryChips() {
        for arranged in channelCategoryStack.arrangedSubviews {
            channelCategoryStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for (index, group) in channelGroups.enumerated() {
            let button = RippleButton()
            button.setTitle(Self.channelGroupTitle(group.type), for: .normal)
            button.titleLabel?.font = .scaledSystemFont(ofSize: 13.5, weight: .medium)
            button.setTitleColor(
                index == selectedChannelGroupIndex ? AppPalette.accent : AppPalette.text,
                for: .normal)
            button.backgroundColor =
                index == selectedChannelGroupIndex ? AppPalette.pressed : .clear
            button.layer.cornerRadius = 16
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.tag = index
            button.addTarget(self, action: #selector(selectChannelGroup(_:)), for: .touchUpInside)
            channelCategoryStack.addArrangedSubview(button)
        }
    }

    @objc private func selectChannelGroup(_ sender: RippleButton) {
        applyChannelGroupSelection(sender.tag)
    }

    /// 分類の切り替えを反映する (タップとスワイプで共用)。
    /// 帯を作り直して一覧を読み直し、先頭から出す (生放送一覧で
    /// ページを移ったときと同じ)。
    private func applyChannelGroupSelection(_ index: Int) {
        guard channelGroups.indices.contains(index) else { return }
        selectedChannelGroupIndex = index
        rebuildChannelCategoryChips()
        channelTableView.reloadData()
        channelTableView.contentOffset = CGPoint(
            x: 0, y: -channelTableView.adjustedContentInset.top)
        // 帯の中で、選んだ分類が見える位置まで寄せる。
        if channelCategoryStack.arrangedSubviews.indices.contains(index) {
            let chip = channelCategoryStack.arrangedSubviews[index]
            channelCategoryScrollView.scrollRectToVisible(
                chip.frame.insetBy(dx: -12, dy: 0), animated: true)
        }
    }

    /// 一覧の左右スワイプ。左へ払えば次の分類、右へ払えば前の分類で、
    /// 端ではそれ以上進まない (生放送一覧と同じ)。切り替えは、指を
    /// 離したときに移動量と勢いで決める。
    @objc private func handleChannelGroupSwipe(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let translation = pan.translation(in: channelTableView)
        let velocity = pan.velocity(in: channelTableView)
        // ある程度の移動か勢いがあるときだけ切り替える
        // (触れただけで切り替わらないように)。
        guard abs(translation.x) > 40 || abs(velocity.x) > 300 else { return }
        // 向きは移動量を優先し、読み取れないときは速度で決める。
        let directionX = abs(translation.x) > 2 ? translation.x : velocity.x
        let step = directionX < 0 ? 1 : -1
        let target = selectedChannelGroupIndex + step
        guard channelGroups.indices.contains(target) else { return }
        applyChannelGroupSelection(target)
        // 新しい分類の一覧が、進む向きから滑り込んでくるように見せる
        // (生放送一覧のページ送りに寄せた動き)。
        channelTableView.transform = CGAffineTransform(
            translationX: CGFloat(step) * 40, y: 0)
        channelTableView.alpha = 0.35
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.channelTableView.transform = .identity
            self.channelTableView.alpha = 1
        }
    }

    /// API の種別名を表示用の名前にする (生放送一覧と同じ)。
    private static func channelGroupTitle(_ type: String) -> String {
        switch type {
        case "PINNED": return "ピン留め"
        case "GR": return "地デジ"
        default: return type
        }
    }

    /// チャンネルのピン留めを付け外しする (生放送一覧と同じ動き)。
    private func toggleChannelPin(_ target: LiveChannel) {
        var settings = SyncedSettingsStore.shared.current
        if settings.pinnedChannelIDs.contains(target.id) {
            settings.pinnedChannelIDs.removeAll { $0 == target.id }
        } else {
            settings.pinnedChannelIDs.append(target.id)
        }
        SyncedSettingsStore.shared.update(settings)
        rebuildChannelGroups()
    }

    /// その場で別のチャンネルへ切り替える。今の再生画面を、新しい
    /// チャンネルの再生画面に入れ替える (再生は作り直しになる)。
    private func switchChannel(to target: LiveChannel) {
        guard target.id != channel.id else { return }
        if AppEdition.tunerInUseEnabled, !target.isTunerViewable {
            setChannelStatus("チューナーに空きがないため、このチャンネルは視聴できません。録画中のチャンネルは視聴できます。")
            return
        }
        setChannelStatus(nil)
        let next = LivePlayerViewController(channel: target)
        guard let navigationController else { return }
        var stack = navigationController.viewControllers
        guard let index = stack.firstIndex(of: self) else { return }
        stack[index] = next
        navigationController.setViewControllers(stack, animated: false)
    }

    // MARK: - コメントパネル

    private func buildCommentPanel() {
        commentPanel.backgroundColor = AppPalette.background
        commentPanel.isHidden = true
        commentPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commentPanel)

        // 見出しの行: 「コメント」 + ミュート設定への入口 (Web 版と同じ)。
        let titleLabel = UILabel()
        titleLabel.text = "コメント"
        titleLabel.textColor = AppPalette.text
        titleLabel.font = .scaledSystemFont(ofSize: 15, weight: .bold)
        let muteButton = RippleButton()
        muteButton.setTitle("ミュート設定", for: .normal)
        muteButton.addTarget(self, action: #selector(openCommentMuteSettings), for: .touchUpInside)
        stylePlayerChip(muteButton)
        let headerRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), muteButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.isLayoutMarginsRelativeArrangement = true
        headerRow.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        commentStatusLabel.textColor = .systemYellow
        commentStatusLabel.font = .scaledSystemFont(ofSize: 12.5)
        commentStatusLabel.numberOfLines = 0
        commentStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        let statusWrap = UIView()
        statusWrap.isHidden = true
        statusWrap.translatesAutoresizingMaskIntoConstraints = false
        statusWrap.addSubview(commentStatusLabel)
        NSLayoutConstraint.activate([
            commentStatusLabel.topAnchor.constraint(equalTo: statusWrap.topAnchor, constant: 2),
            commentStatusLabel.bottomAnchor.constraint(equalTo: statusWrap.bottomAnchor, constant: -2),
            commentStatusLabel.leadingAnchor.constraint(equalTo: statusWrap.leadingAnchor, constant: 16),
            commentStatusLabel.trailingAnchor.constraint(equalTo: statusWrap.trailingAnchor, constant: -16),
        ])
        commentPanelStatusWrap = statusWrap

        commentTableView.dataSource = self
        commentTableView.delegate = self
        commentTableView.register(
            LiveCommentListCell.self, forCellReuseIdentifier: LiveCommentListCell.reuseID)
        commentTableView.rowHeight = UITableView.automaticDimension
        commentTableView.estimatedRowHeight = 34
        commentTableView.backgroundColor = AppPalette.background
        commentTableView.separatorStyle = .none
        commentTableView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [headerRow, statusWrap, commentTableView])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        commentPanel.addSubview(stack)

        // 一覧を遡っているときに出る「最新へ戻る」ボタン。
        commentJumpButton.setImage(
            UIImage(systemName: "arrow.down",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
            for: .normal)
        commentJumpButton.tintColor = AppPalette.text
        commentJumpButton.backgroundColor = AppPalette.panel
        commentJumpButton.layer.cornerRadius = 20
        commentJumpButton.layer.shadowColor = UIColor.black.cgColor
        commentJumpButton.layer.shadowOpacity = 0.3
        commentJumpButton.layer.shadowRadius = 6
        commentJumpButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        commentJumpButton.isHidden = true
        commentJumpButton.addTarget(self, action: #selector(jumpToLatestComments), for: .touchUpInside)
        commentJumpButton.translatesAutoresizingMaskIntoConstraints = false
        commentPanel.addSubview(commentJumpButton)

        let form = buildCommentForm()
        commentPanel.addSubview(form)

        let formBottom = form.bottomAnchor.constraint(equalTo: commentPanel.bottomAnchor)
        commentFormBottomConstraint = formBottom
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: commentPanel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: commentPanel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: commentPanel.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: form.topAnchor),
            form.leadingAnchor.constraint(equalTo: commentPanel.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: commentPanel.trailingAnchor),
            formBottom,
            commentJumpButton.trailingAnchor.constraint(
                equalTo: commentPanel.trailingAnchor, constant: -12),
            commentJumpButton.bottomAnchor.constraint(equalTo: form.topAnchor, constant: -12),
            commentJumpButton.widthAnchor.constraint(equalToConstant: 40),
            commentJumpButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        updateCommentEmptyState()
        updateCommentFormState()
        // キーボードの出し入れに投稿欄を追随させる。
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    /// 投稿欄 (入力欄 + 送信ボタン + 色・位置・大きさの選択) を作る。
    private func buildCommentForm() -> UIView {
        let form = UIView()
        form.backgroundColor = AppPalette.background
        form.translatesAutoresizingMaskIntoConstraints = false

        commentTextField.placeholder = "コメントを入力"
        commentTextField.textColor = AppPalette.text
        commentTextField.font = .scaledSystemFont(ofSize: 14)
        commentTextField.backgroundColor = AppPalette.panel
        commentTextField.layer.cornerRadius = 8
        commentTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        commentTextField.leftViewMode = .always
        commentTextField.returnKeyType = .send
        commentTextField.delegate = self
        commentTextField.translatesAutoresizingMaskIntoConstraints = false

        commentSendButton.setTitle("送信", for: .normal)
        commentSendButton.addTarget(self, action: #selector(sendCommentTapped), for: .touchUpInside)
        stylePlayerChip(commentSendButton)

        let inputRow = UIStackView(arrangedSubviews: [commentTextField, commentSendButton])
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        inputRow.alignment = .center

        // 色の選択 (Web 版の入力欄と同じ8色)。
        let colorsStack = UIStackView()
        colorsStack.axis = .horizontal
        colorsStack.spacing = 8
        colorsStack.alignment = .center
        for (index, color) in NicoCommentCommand.postingColors.enumerated() {
            let button = RippleButton()
            button.backgroundColor = Self.colorFromHex(color.hex)
            button.layer.cornerRadius = 13
            button.tag = index
            button.addTarget(self, action: #selector(postColorTapped(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 26),
                button.heightAnchor.constraint(equalToConstant: 26),
            ])
            colorsStack.addArrangedSubview(button)
            postColorButtons.append(button)
        }
        updatePostColorSelection()

        postPositionSegment.selectedSegmentIndex = 1
        postSizeSegment.selectedSegmentIndex = 1
        let optionsRow = UIStackView(arrangedSubviews: [
            colorsStack, UIView(), postPositionSegment, postSizeSegment,
        ])
        optionsRow.axis = .horizontal
        optionsRow.spacing = 10
        optionsRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [inputRow, optionsRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        form.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: form.topAnchor),
            stack.bottomAnchor.constraint(equalTo: form.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            commentTextField.heightAnchor.constraint(equalToConstant: 38),
        ])
        return form
    }

    /// "#RRGGBB" を UIColor に直す。解釈できなければ白。
    private static func colorFromHex(_ hex: String) -> UIColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }

    @objc private func postColorTapped(_ sender: RippleButton) {
        guard NicoCommentCommand.postingColors.indices.contains(sender.tag) else { return }
        selectedPostColorName = NicoCommentCommand.postingColors[sender.tag].name
        updatePostColorSelection()
    }

    /// 色の選択の見た目 (選んでいる色に枠を付ける)。
    private func updatePostColorSelection() {
        for (index, button) in postColorButtons.enumerated() {
            let selected = NicoCommentCommand.postingColors.indices.contains(index)
                && NicoCommentCommand.postingColors[index].name == selectedPostColorName
            button.layer.borderWidth = selected ? 2.5 : 0
            button.layer.borderColor = AppPalette.accent.cgColor
        }
    }

    @objc private func openCommentMuteSettings() {
        navigationController?.pushViewController(
            CommentMuteSettingsViewController(), animated: true)
    }

    /// コメントパネルの知らせを出す (nil で消す)。
    private func showCommentStatus(_ text: String?) {
        commentStatusLabel.text = text
        commentPanelStatusWrap?.isHidden = text == nil
    }

    /// コメント一覧の空表示を、状態に合わせて出し分ける
    /// (Web 版コメントパネルの案内の文に合わせる)。
    private func updateCommentEmptyState() {
        guard liveComments.isEmpty else {
            commentTableView.backgroundView = nil
            return
        }
        if let failure = commentInitFailure {
            commentEmptyLabel.text = "コメントがありません。\n\(failure)"
        } else {
            commentEmptyLabel.text = "まだコメントがありません。\nこのチャンネルに対応するニコニコ実況のコメントが、リアルタイムで表示されます。"
        }
        if commentTableView.backgroundView == nil {
            let container = UIView()
            commentEmptyLabel.textColor = AppPalette.metaText
            commentEmptyLabel.font = .scaledSystemFont(ofSize: 13)
            commentEmptyLabel.numberOfLines = 0
            commentEmptyLabel.textAlignment = .center
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

    /// 投稿欄の有効・無効を、初期化の成否に合わせる。
    private func updateCommentFormState() {
        let failed = commentInitFailure != nil
        commentTextField.isEnabled = !failed
        commentSendButton.isEnabled = !failed
        commentTextField.placeholder = failed
            ? "このチャンネルではコメントできません"
            : "コメントを入力"
    }

    /// コメントを送信する。成否は知らせに出し、成功したら入力を消す。
    /// 「送信後にフォームを閉じる」設定がオンなら、キーボードも閉じる。
    @objc private func sendCommentTapped() {
        let text = commentTextField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, let session = commentSession else { return }
        let position = ["ue", "naka", "shita"][postPositionSegment.selectedSegmentIndex]
        let size = ["big", "medium", "small"][postSizeSegment.selectedSegmentIndex]
        commentSendButton.isEnabled = false
        session.postComment(
            text: text, colorName: selectedPostColorName,
            position: position, size: size
        ) { [weak self] error in
            guard let self else { return }
            self.commentSendButton.isEnabled = true
            if let error {
                self.showCommentStatus(error)
            } else {
                self.commentTextField.text = ""
                self.showCommentStatus(nil)
                if SyncedSettingsStore.shared.current.closeCommentFormAfterSending {
                    self.commentTextField.resignFirstResponder()
                }
            }
        }
    }

    @objc private func jumpToLatestComments() {
        commentFollow = true
        commentJumpButton.isHidden = true
        scrollCommentListToBottom(animated: true)
    }

    private func scrollCommentListToBottom(animated: Bool) {
        guard !liveComments.isEmpty, commentTableView.bounds.height > 0 else { return }
        commentTableView.scrollToRow(
            at: IndexPath(row: liveComments.count - 1, section: 0),
            at: .bottom, animated: animated)
    }

    /// キーボードの出し入れに合わせて、投稿欄の位置を持ち上げる。
    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let constraint = commentFormBottomConstraint else { return }
        let overlap = max(
            0, view.bounds.height - frame.origin.y - view.safeAreaInsets.bottom)
        constraint.constant = -overlap
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// コメント1件の操作 (Web 版のコメント一覧のドロップダウンと同じ顔ぶれ)。
    private func showCommentMenu(for comment: LiveJikkyoComment) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "クリップボードにコピー", style: .default) { _ in
            UIPasteboard.general.string = comment.text
        })
        sheet.addAction(UIAlertAction(title: "このコメントのユーザー ID をコピー", style: .default) { _ in
            UIPasteboard.general.string = comment.userID
        })
        sheet.addAction(UIAlertAction(title: "このコメントをミュート", style: .default) { [weak self] _ in
            self?.muteComment(comment)
        })
        sheet.addAction(UIAlertAction(title: "このコメントの投稿者をミュート", style: .default) { [weak self] _ in
            self?.muteCommentAuthor(comment)
        })
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(sheet, animated: true)
    }

    /// コメント本文を、そのままの完全一致のキーワードとしてミュートに足す
    /// (Web 版の「このコメントをミュート」と同じ)。
    private func muteComment(_ comment: LiveJikkyoComment) {
        var settings = SyncedSettingsStore.shared.current
        guard !settings.mutedCommentKeywords.contains(
            where: { $0.match == "exact" && $0.pattern == comment.text }) else { return }
        settings.mutedCommentKeywords.append(
            MutedCommentKeyword(match: "exact", pattern: comment.text))
        SyncedSettingsStore.shared.update(settings)
        showCommentStatus("このコメントをミュートしました。")
    }

    /// 投稿者の ID をミュートに足す (Web 版と同じ)。
    private func muteCommentAuthor(_ comment: LiveJikkyoComment) {
        var settings = SyncedSettingsStore.shared.current
        guard !settings.mutedNiconicoUserIDs.contains(comment.userID) else { return }
        settings.mutedNiconicoUserIDs.append(comment.userID)
        SyncedSettingsStore.shared.update(settings)
        showCommentStatus("このコメントの投稿者をミュートしました。")
    }

    // MARK: - 実況コメントの土台と時計

    /// 実況コメントの接続を始める (画面を開いたときに1回だけ)。
    private func startCommentSession() {
        let session = LiveCommentSession(channelID: channel.id)
        session.nowProvider = { [weak self] in self?.liveCommentNow() ?? 0 }
        session.delayProvider = { [weak self] in self?.liveCommentDelaySeconds ?? 0 }
        session.onComments = { [weak self] comments, isInitial in
            self?.receiveLiveComments(comments, isInitial: isInitial)
        }
        session.onNotice = { [weak self] text in
            // 知らせは、番組情報パネルの知らせ欄とコメントパネルの
            // 両方に出す (開いているパネルで気付けるように)。
            self?.messageLabel.text = text
            self?.showCommentStatus(text)
        }
        session.onInitFailure = { [weak self] message in
            self?.commentInitFailure = message
            self?.updateCommentEmptyState()
            self?.updateCommentFormState()
        }
        commentSession = session
        session.start()
    }

    /// 届いたコメントを、一覧と流れる表示へ回す。
    /// 初回のまとめは一覧にだけ出す (Web 版と同じ)。
    private func receiveLiveComments(_ comments: [LiveJikkyoComment], isInitial: Bool) {
        var incoming = comments
        if isInitial {
            // 再接続などで初回のまとめが届いたとき、すでに一覧にある
            // コメントと重なる分は足さない。コメント番号があるものは
            // 番号で、番号が無いものは投稿者・時刻・本文の組み合わせで
            // 照合する。
            let knownIDs = Set(liveComments.map { $0.id }.filter { $0 != 0 })
            let knownKeys = Set(liveComments.map {
                "\($0.userID)|\($0.date.timeIntervalSince1970)|\($0.text)"
            })
            incoming = incoming.filter { comment in
                if comment.id != 0, knownIDs.contains(comment.id) { return false }
                return !knownKeys.contains(
                    "\(comment.userID)|\(comment.date.timeIntervalSince1970)|\(comment.text)")
            }
            // 初回のまとめの中どうしの重なりも落とす。
            var seenIDs = Set<Int>()
            var seenKeys = Set<String>()
            incoming = incoming.filter { comment in
                let key = "\(comment.userID)|\(comment.date.timeIntervalSince1970)|\(comment.text)"
                if comment.id != 0, !seenIDs.insert(comment.id).inserted { return false }
                return seenKeys.insert(key).inserted
            }
        }
        liveComments.append(contentsOf: incoming)
        // 一覧が際限なく伸びないよう、古い分から少しずつ落とす。
        if liveComments.count > 1200 {
            liveComments.removeFirst(liveComments.count - 1000)
        }
        if !isInitial {
            commentOverlay.appendComments(comments.map { $0.asJikkyoComment })
            commentOverlay.pruneSpawnedComments(before: liveCommentNow() - 30)
        }
        // 一覧の更新は、行を1つずつ足す形ではなく、まとめて読み直す形に
        // 統一する。行数の帳尻が合わないとアプリが落ちる事故が起きるため、
        // その余地自体を無くす (実機で生放送の再生画面へ入ると落ちる
        // 症状への守り)。
        commentTableView.reloadData()
        updateCommentEmptyState()
        if commentFollow {
            scrollCommentListToBottom(animated: false)
        } else if selectedPanelTab == .comment {
            commentJumpButton.isHidden = false
        }
    }

    /// 流れる表示の仮想の時計 (秒)。再生中だけ進む。
    private func liveCommentNow() -> Double {
        var now = liveCommentClockOffset
        if let start = liveCommentClockStart {
            now += Date().timeIntervalSince(start)
        }
        return now
    }

    /// 再生の状態に合わせて、仮想の時計の進みを切り替える
    /// (再生部品の状態変化の合図から呼ばれる)。
    private func updateCommentClock() {
#if canImport(VLCKit)
        let playing = vlcPlayer?.isPlaying ?? false
#else
        let playing = false
#endif
        if playing, liveCommentClockStart == nil {
            liveCommentClockStart = Date()
        } else if !playing, let start = liveCommentClockStart {
            liveCommentClockOffset += Date().timeIntervalSince(start)
            liveCommentClockStart = nil
        }
    }

    /// コメント表示の切り替え (録画と同じ。設定は端末に保存する)。
    @objc private func toggleComments() {
        SettingsStore.shared.showComments.toggle()
        updateCaptureControls()
        updateCommentButton()
        applyCommentDisplayState()
        scheduleHideControls()
    }

    /// コメント切り替えボタンの見た目を、現在の設定に合わせる (録画と同じ)。
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
    /// 音声のみの間は映像が出ていないので、コメントも流さない (録画と同じ)。
    private func applyCommentDisplayState() {
        commentOverlay.setDisplayEnabled(SettingsStore.shared.showComments && !audioOnly)
    }

    // MARK: - 操作帯の出し入れ

    @objc private func toggleControls() {
        setControlsVisible(!controlsVisible)
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        // 状態が変わるときだけ動かす。
        guard visible != controlsVisible else { return }
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) {
            self.overlayHeader.alpha = visible ? 1 : 0
            self.overlayTopGradient.alpha = visible ? 1 : 0
            self.bottomGradient.alpha = visible ? 1 : 0
            self.controlsContainer.alpha = visible ? 1 : 0
            self.playPauseButton.alpha = visible ? 1 : 0
        }
        overlayHeader.isUserInteractionEnabled = visible
        controlsContainer.isUserInteractionEnabled = visible
        playPauseButton.isUserInteractionEnabled = visible
        if !visible {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    /// 再生中だけ、しばらく触らなければ操作帯を消すタイマーを仕掛け直す。
    private func scheduleHideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
#if canImport(VLCKit)
        guard vlcPlayer?.isPlaying ?? false, presentedViewController == nil, playerSettingsPanel == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.setControlsVisible(false)
        }
#endif
    }

    private func startStream() {
        if pipController?.isActive != true, pipController?.isPending != true { PlaybackPiPController.stopCurrentPlayback() }
#if canImport(VLCKit)
        guard let url = APIClient.shared.liveStreamURL(
            displayChannelID: channel.display_channel_id,
            quality: quality,
            profile: profile
        ) else {
            messageLabel.text = "接続先が設定されていません。"
            return
        }
        stopStream()
        // 中継が必須の構成 (認証方式が「なし」以外) では、中継の用意が
        // できていないときに直接再生へ落ちない (合言葉が届かず、どうせ
        // 弾かれるため)。失敗として知らせ、再生ボタンでやり直せる
        // ようにする (この場合は再生部品を作らないため、再生ボタンが
        // 始め直しの受け口になる)。
        let relayedURL = StreamRelayServer.shared.relayURL(for: url)
        if relayedURL == nil && SettingsStore.shared.vlcPlaybackRequiresRelay {
            messageLabel.text = "中継の用意ができず、再生を開始できませんでした。再生ボタンでもう一度お試しください。"
            return
        }
        let player = VLCMediaPlayer()
        let observer = VLCStateObserver { [weak self, weak player] state in
            guard let player else { return }
            self?.handleVLCState(state, source: player)
        }
        vlcStateObserver = observer
        player.delegate = observer
        let pip = makePiPController()
        pipController = pip
        player.drawable = pip
        // 渡す URL は、アプリ内の中継 (StreamRelayServer) 経由にする。
        // VLCKit には再生の取りに行く処理へ任意のヘッダーを付ける公式の
        // 入口が無く、Cloudflare Access の合言葉が届かないため、外回線
        // では開始すらできない (0.25 で実機確認済み。録画の H.265 と
        // 同じ弱点で、直し方も同じ)。中継が合言葉付きで取りに行き、
        // 届いた分からそのまま流す。中継が必須でない構成で中継が
        // 使えないときは元の URL に落ちる。録画側の扱いに揃え、接続先が
        // 内・外どちらでも中継を通す (合言葉が未設定なら、中継は素通しになる)。
        guard let media = VLCMedia(url: relayedURL ?? url) else { return }
        // 受け取りの溜め (ネットワークキャッシュ) の量で、低遅延の設定を
        // 近づける。Web 版の低遅延は再生バッファを 0.9 秒 / 通常 4.0 秒に
        // 切り替える仕組みで、VLCKit には同じ仕組みが無いため、受け取りの
        // 溜めを 低遅延オン = 1000ms / オフ = 4000ms に切り替えて近づける。
        // 効き具合 (遅れの減り方と止まりやすさ) は実機確認が要る。
        let networkCaching = SettingsStore.shared.lowLatencyMode(profile: profile) ? 1000 : 4000
        // 実況コメントを流れる表示へ出すまでの遅れは、再生の溜めの量に
        // 合わせる (Web 版と同じ考え方)。
        liveCommentDelaySeconds = Double(networkCaching) / 1000
        media.addOption(":network-caching=\(networkCaching)")
        if audioOnly {
            media.addOption(":no-video")
        }
        // 認証の合言葉をヘッダーとして付ける
        // (中継を使わない場合の補い。単独では届かないことが分かっている)。
        for (key, value) in SettingsStore.shared.serverAuthHeaders {
            media.addOption(":http-header=\(key): \(value)")
        }
        player.media = media
        vlcPlayer = player
        // 開始の見張り: 30秒たっても再生が始まらなければ、その旨を表示する
        // (エラーの合図が来ないまま止まる場合でも無言にしないため。
        // 録画側と同じ30秒。生放送はサーバー側の用意に時間がかかることが
        // あるため、短すぎる見張りは避ける)。
        didStartPlaying = false
        startWatchdog?.invalidate()
        startWatchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self, let vlcPlayer = self.vlcPlayer, !self.didStartPlaying else { return }
            if vlcPlayer.state != .playing && vlcPlayer.state != .paused {
                self.messageLabel.text = "再生を開始できませんでした。"
            }
        }
        player.play()
        beginNowPlaying()
        startLiveCaptions()
#else
        messageLabel.text = "このビルドには生放送の再生部品 (VLCKit) が組み込まれていません。"
#endif
    }

    private func stopStream() {
        captureController.cancel()
        startWatchdog?.invalidate()
        startWatchdog = nil
        // 字幕の抜き取り口と更新タイマーも止める (中継は他の再生と共用の
        // ため、残しておくと関係ない経路でも読み取りが続いてしまう)。
        StreamRelayServer.shared.setLiveCaptionTap(nil)
        captionTimer?.invalidate()
        captionTimer = nil
#if canImport(VLCKit)
        let pip = pipController
        pipController = nil
        pip?.dispose()
        let previous = vlcPlayer
        vlcPlayer = nil
        previous?.delegate = nil
        previous?.stop()
        vlcStateObserver = nil
#endif
        if nowPlayingBegun {
            NowPlayingManager.shared.end(owner: self)
            nowPlayingBegun = false
        }
    }

    // MARK: - 字幕 (生放送)

    /// 字幕の用意: 蓄えを空にし直し、アプリ内の中継へ生放送用の
    /// 抜き取り口を登録して、更新タイマーを回し始める
    /// (録画の H.265 経路と同じ作り)。
    private func startLiveCaptions() {
        captionEngine.resetForNewPlayback()
        liveCaptionBasePTS = nil
        let marker = "/api/streams/live/\(channel.display_channel_id)/"
        StreamRelayServer.shared.setLiveCaptionTap(StreamRelayServer.LiveCaptionTap(
            pathMarker: marker,
            onPackets: { [weak self] packets, firstVideoPTS, latestVideoPTS in
                DispatchQueue.main.async {
                    self?.ingestLiveCaptionPackets(
                        packets, firstVideoPTS: firstVideoPTS, latestVideoPTS: latestVideoPTS)
                }
            }))
        captionTimer?.invalidate()
        captionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshLiveCaptions()
        }
        applyCaptionDisplayState()
    }

    /// 中継から届いた字幕の包みを蓄える。接続が替わって基準の時刻印が
    /// 変わっていたら、蓄えを作り直してから受ける。
    private func ingestLiveCaptionPackets(
        _ packets: [TSID3Extractor.Packet], firstVideoPTS: Int64?, latestVideoPTS: Int64?
    ) {
        guard let firstVideoPTS else { return }
        if liveCaptionBasePTS != firstVideoPTS {
            captionEngine.resetForNewPlayback()
            liveCaptionBasePTS = firstVideoPTS
        }
        guard !packets.isEmpty else { return }
        captionEngine.ingestLivePackets(packets, firstVideoPTS: firstVideoPTS)
    }

    /// 再生部品の時計に合わせて字幕の絵を進める
    /// (0.25秒ごとのタイマーから呼ばれる)。
    private func refreshLiveCaptions() {
        let vlcSeconds = currentVLCTimeSeconds()
        if !captionOverlayView.isHidden {
            if captionEngine.update(position: vlcSeconds + Self.liveCaptionTimeOffset) {
                captionOverlayView.setImage(captionEngine.currentImage)
            }
            // 映像の描画側が字幕より上に重なることがあるため、通常画面
            // では字幕を映像の枠の中で一番上に保つ (録画と同じ扱い)。
            if captionOverlayView.superview === videoArea {
                videoArea.bringSubviewToFront(captionOverlayView)
                restoreControlLayerOrder()
            }
        }
    }

    /// 再生部品 (VLCKit) の時計 (秒)。取れないときは 0。
    private func currentVLCTimeSeconds() -> Double {
#if canImport(VLCKit)
        guard let vlcPlayer else { return 0 }
        let ms = vlcPlayer.time.intValue
        return ms > 0 ? Double(ms) / 1000 : 0
#else
        return 0
#endif
    }

    /// 字幕表示の切り替え (録画と同じ。設定は端末に保存する)。
    @objc private func toggleCaptions() {
        SettingsStore.shared.showCaptions.toggle()
        updateCaptionButton()
        applyCaptionDisplayState()
        scheduleHideControls()
    }

    /// 字幕切り替えボタンの見た目を、現在の設定に合わせる (録画と同じ)。
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
    /// 音声のみの間は映像が出ていないので、字幕も出さない (録画と同じ)。
    private func applyCaptionDisplayState() {
        captionOverlayView.isHidden = !(SettingsStore.shared.showCaptions && !audioOnly)
        if !captionOverlayView.isHidden {
            refreshLiveCaptions()
        }
    }

    // MARK: - ロック画面の「再生中」表示

    /// ロック画面やコントロールセンターへの表示と、そちらからの操作の受け付けを始める。
    /// 生放送では位置や長さは出さず、再生・一時停止だけを受け付ける。
    private func beginNowPlaying() {
        if !nowPlayingBegun {
            NowPlayingManager.shared.begin(owner: self, handlers: .init(
                play: { [weak self] in
                    self?.playStream()
                },
                pause: { [weak self] in
                    self?.pauseStream()
                },
                togglePlayPause: { [weak self] in
                    self?.togglePlayPause()
                },
                skipForward: nil,
                skipBackward: nil,
                seekTo: nil,
                nextChapter: nil,
                previousChapter: nil
            ))
            nowPlayingBegun = true
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard nowPlayingBegun else { return }
        let playing: Bool = {
#if canImport(VLCKit)
            return vlcPlayer?.isPlaying ?? false
#else
            return false
#endif
        }()
        NowPlayingManager.shared.updateLive(
            owner: self,
            title: channel.name,
            subtitle: channel.program_present?.title,
            isPlaying: playing
        )
    }

    private func playStream() {
#if canImport(VLCKit)
        vlcPlayer?.play()
        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        NowPlayingManager.shared.updateLive(
            owner: self, title: channel.name,
            subtitle: channel.program_present?.title, isPlaying: true
        )
#endif
    }

    private func pauseStream() {
#if canImport(VLCKit)
        vlcPlayer?.pause()
        playPauseButton.setImage(
            UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        NowPlayingManager.shared.updateLive(
            owner: self, title: channel.name,
            subtitle: channel.program_present?.title, isPlaying: false
        )
#endif
    }

    @objc private func togglePlayPause() {
#if canImport(VLCKit)
        guard let player = vlcPlayer else {
            // 再生部品が無い (中継の用意ができずに始められなかった等)
            // 場合は、再生ボタンで始め直す。
            startStream()
            return
        }
        if player.isPlaying {
            pauseStream()
        } else {
            playStream()
        }
        scheduleHideControls()
#endif
    }

    private func makeQualityMenu() -> UIMenu {
        // 選択肢の表示は設定画面と同じく、データ量と平均ビットレート付き。
        // 数値は現在の区分の通信節約モードの有無で切り替わる。
        let dataSaver = SettingsStore.shared.dataSaverMode(media: .tv, profile: profile)
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
    /// 切り替えが完了して再生が始まった時点の両方で行う
    /// (本番 Web 版の追加の直しに合わせた)。音声のみの切り替えのような
    /// 内部の画質変更は、ここを通らないので書き戻しの対象にならない。
    private func userSwitchQuality(_ newQuality: String) {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            messageLabel.text = "PiP を終了してから再生設定を変更してください。"
            return
        }
        guard newQuality != quality else { return }
        SettingsStore.shared.setStreamingQuality(newQuality, media: .tv, profile: profile)
        pendingQualityWriteBack = newQuality
        switchQuality(newQuality)
    }

    /// 画質プロファイルの手動切り替えボタンの表示を、現在の区分に合わせる。
    private func updateProfileButtonTitle() {
        profileButton.setTitle(
            profile == .cellular ? "モバイル回線向け画質: ON" : "モバイル回線向け画質: OFF",
            for: .normal)
    }

    @objc private func toggleProfile() {
        switchProfile(to: profile == .cellular ? .wifi : .cellular)
    }

    /// 画質プロファイルを手で切り替える (Web 版プレイヤーの設定パネルの
    /// 「モバイル回線向け画質」トグルと同じ)。切り替えた瞬間に選択を
    /// 端末へ保存し (last_quality_profile_type)、次に開くときも引き継ぐ。
    /// 再生は、切り替え後の区分の既定画質でつなぎ直す (再生中の画質は
    /// 引き継がない。Web 版の should_resume_quality: false と同じ)。
    /// 低遅延の効き方も区分ごとに違うため、つなぎ直しで一緒に切り替わる。
    private func switchProfile(to newProfile: PlaybackProfile) {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            messageLabel.text = "PiP を終了してから再生設定を変更してください。"
            return
        }
        guard newProfile != profile else { return }
        // 止めている間の切り替えで勝手に再開しないよう、つなぎ直す前に
        // 再生中だったかを控える (画質・音声のみの切り替えと同じ)。
#if canImport(VLCKit)
        let wasPlaying = vlcPlayer?.isPlaying ?? false
#else
        let wasPlaying = false
#endif
        profile = newProfile
        SettingsStore.shared.lastQualityProfileType = newProfile
        updateProfileButtonTitle()
        // プロファイル切り替え自体は画質の変更ではないので、書き戻しの
        // 控えは持たない。
        pendingQualityWriteBack = nil
        quality = SettingsStore.shared.streamingQuality(media: .tv, profile: newProfile)
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.menu = makeQualityMenu()
        startStream()
        if wasPlaying {
            playPauseButton.setImage(
                UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
                for: .normal
            )
        } else {
            // 止めていた場合は、つなぎ直した後も止めたままにする。
            pauseStream()
        }
        messageLabel.text = newProfile == .cellular
            ? "モバイル回線向けの画質プロファイルに切り替えました。"
            : "Wi-Fi 回線向けの画質プロファイルに切り替えました。"
    }

    /// 画質の切り替え: VLC の読み込み先を新しい画質の流れに替えて再生し直す。
    /// 音声のみの最中でも、映像を止めたまま切り替わる (startStream が状態を見て付ける)。
    private func switchQuality(_ newQuality: String) {
        guard newQuality != quality else { return }
        // 止めている間の切り替えで勝手に再開しないよう、つなぎ直す前に
        // 再生中だったかを控える。
#if canImport(VLCKit)
        let wasPlaying = vlcPlayer?.isPlaying ?? false
#else
        let wasPlaying = false
#endif
        quality = newQuality
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.menu = makeQualityMenu()
        startStream()
        if wasPlaying {
            playPauseButton.setImage(
                UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
                for: .normal
            )
        } else {
            pauseStream()
        }
    }

    /// 音声のみ: 映像の通り道を止めて繋ぎ直す (通信量も減る)。
    @objc private func toggleAudioOnly() {
        guard pipController?.isActive != true, pipController?.isPending != true else {
            messageLabel.text = "PiP を終了してから再生設定を変更してください。"
            return
        }
        // 止めている間の切り替えで勝手に再開しないよう、つなぎ直す前に
        // 再生中だったかを控える (画質の切り替えと同じ)。
#if canImport(VLCKit)
        let wasPlaying = vlcPlayer?.isPlaying ?? false
#else
        let wasPlaying = false
#endif
        audioOnly.toggle()
        updateCommentButton()
        audioOnlyButton.setTitle(audioOnly ? "音声のみ: ON" : "音声のみ: OFF", for: .normal)
        videoView.isHidden = audioOnly
        applyCaptionDisplayState()
        updateCaptionButton()
        applyCommentDisplayState()
        startStream()
        if wasPlaying {
            playPauseButton.setImage(
                UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
                for: .normal
            )
        } else {
            pauseStream()
        }
    }

    // MARK: - データ放送 (重ね合わせ)

    /// リモコンのパネルを作る (Web 版の Remocon.vue と同じ顔ぶれ)。
    /// 十字キーは円形、操作キーと数字キーの送る合図 (ARIB のキーコード)
    /// は Web 版と同一。パネルと幕の置き場所は、作る時点では仮置きし、
    /// 出すたびに applyRemotePanelPlacement で決め直す (通常画面では
    /// 映像の下、全画面では右端)。
    /// 「データ」ボタンがデータ放送の入り口で、それ以外のキーは
    /// dataBroadcastRemoteKey がそのまま合図を送る。
    private func buildRemotePanel() {
        // パネルのボタン1つを作る (tag に ARIB のキーコードを入れる)。
        func makePanelButton(_ title: String, _ keyCode: Int, fontSize: CGFloat) -> RippleButton {
            let button = RippleButton()
            button.setTitle(title, for: .normal)
            button.setTitleColor(AppPalette.text, for: .normal)
            button.titleLabel?.font = .scaledSystemFont(ofSize: fontSize, weight: .bold)
            button.backgroundColor = AppPalette.panel
            button.layer.cornerRadius = 5
            button.tag = keyCode
            button.addTarget(self, action: #selector(dataBroadcastRemoteKey(_:)), for: .touchUpInside)
            return button
        }
        // 色ボタンは Web 版の色 (Vuetify の blue-darken-3 など) に寄せる。
        func makeColorButton(_ title: String, _ keyCode: Int, _ color: UIColor) -> RippleButton {
            let button = makePanelButton(title, keyCode, fontSize: 15)
            button.backgroundColor = color
            button.setTitleColor(.white, for: .normal)
            return button
        }
        // 横1列の並びを作る (中身は同じ幅で広がる)。
        func makePanelRow(_ buttons: [UIView], height: CGFloat) -> UIStackView {
            let row = UIStackView(arrangedSubviews: buttons)
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: height).isActive = true
            return row
        }

        // 十字キー: 160x160 の円形の台に、矢印4つと中央の「決定」 (90x90)。
        let dPad = UIView()
        dPad.backgroundColor = AppPalette.panel
        dPad.layer.cornerRadius = 80
        dPad.clipsToBounds = true
        dPad.translatesAutoresizingMaskIntoConstraints = false
        func makeArrowButton(_ symbol: String, _ keyCode: Int) -> RippleButton {
            let button = RippleButton()
            button.setImage(
                UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)),
                for: .normal
            )
            button.tintColor = AppPalette.text
            button.tag = keyCode
            button.addTarget(self, action: #selector(dataBroadcastRemoteKey(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
        let upButton = makeArrowButton("chevron.up", 1)
        let downButton = makeArrowButton("chevron.down", 2)
        let leftButton = makeArrowButton("chevron.left", 3)
        let rightButton = makeArrowButton("chevron.right", 4)
        let selectButton = RippleButton()
        selectButton.setTitle("決定", for: .normal)
        selectButton.setTitleColor(AppPalette.text, for: .normal)
        selectButton.titleLabel?.font = .scaledSystemFont(ofSize: 14, weight: .bold)
        selectButton.backgroundColor = AppPalette.background
        selectButton.layer.cornerRadius = 45
        selectButton.tag = 18
        selectButton.addTarget(self, action: #selector(dataBroadcastRemoteKey(_:)), for: .touchUpInside)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        for button in [upButton, downButton, leftButton, rightButton, selectButton] {
            dPad.addSubview(button)
        }
        NSLayoutConstraint.activate([
            dPad.widthAnchor.constraint(equalToConstant: 160),
            dPad.heightAnchor.constraint(equalToConstant: 160),
            upButton.topAnchor.constraint(equalTo: dPad.topAnchor),
            upButton.centerXAnchor.constraint(equalTo: dPad.centerXAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 90),
            upButton.heightAnchor.constraint(equalToConstant: 35),
            downButton.bottomAnchor.constraint(equalTo: dPad.bottomAnchor),
            downButton.centerXAnchor.constraint(equalTo: dPad.centerXAnchor),
            downButton.widthAnchor.constraint(equalToConstant: 90),
            downButton.heightAnchor.constraint(equalToConstant: 35),
            leftButton.leadingAnchor.constraint(equalTo: dPad.leadingAnchor),
            leftButton.centerYAnchor.constraint(equalTo: dPad.centerYAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: 35),
            leftButton.heightAnchor.constraint(equalToConstant: 90),
            rightButton.trailingAnchor.constraint(equalTo: dPad.trailingAnchor),
            rightButton.centerYAnchor.constraint(equalTo: dPad.centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 35),
            rightButton.heightAnchor.constraint(equalToConstant: 90),
            selectButton.centerXAnchor.constraint(equalTo: dPad.centerXAnchor),
            selectButton.centerYAnchor.constraint(equalTo: dPad.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 90),
            selectButton.heightAnchor.constraint(equalToConstant: 90),
        ])

        // 「データ」ボタン: Web 版と同じ「d」のロゴを左に置く。
        // ロゴは Web 版の Remocon.vue に埋め込まれた SVG をそのまま
        // 素材化したもの (data_broadcast_d_logo)。
        let dataButton = RippleButton()
        dataButton.setTitle("データ", for: .normal)
        dataButton.setTitleColor(AppPalette.text, for: .normal)
        dataButton.titleLabel?.font = .scaledSystemFont(ofSize: 15, weight: .bold)
        dataButton.backgroundColor = AppPalette.panel
        dataButton.layer.cornerRadius = 5
        dataButton.tintColor = AppPalette.text
        dataButton.setImage(UIImage(named: "data_broadcast_d_logo"), for: .normal)
        dataButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        dataButton.addTarget(self, action: #selector(remoteDataKeyPressed), for: .touchUpInside)
        // 「戻る」ボタン: Web 版と同じく、小さい矢印+文字。
        let backButton = RippleButton()
        backButton.setTitle("戻る", for: .normal)
        backButton.setTitleColor(AppPalette.text, for: .normal)
        backButton.titleLabel?.font = .scaledSystemFont(ofSize: 15, weight: .bold)
        backButton.backgroundColor = AppPalette.panel
        backButton.layer.cornerRadius = 5
        backButton.tintColor = AppPalette.text
        backButton.setImage(
            UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)),
            for: .normal
        )
        backButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        backButton.tag = 19
        backButton.addTarget(self, action: #selector(dataBroadcastRemoteKey(_:)), for: .touchUpInside)

        let controlRow1 = makePanelRow([dataButton, backButton], height: 35)
        let controlRow2 = makePanelRow([
            makeColorButton("青", 21, UIColor(red: 0x15 / 255, green: 0x65 / 255, blue: 0xC0 / 255, alpha: 1)),
            makeColorButton("赤", 22, UIColor(red: 0xC6 / 255, green: 0x28 / 255, blue: 0x28 / 255, alpha: 1)),
            makeColorButton("緑", 23, UIColor(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255, alpha: 1)),
            makeColorButton("黄", 24, UIColor(red: 0xF9 / 255, green: 0xA8 / 255, blue: 0x25 / 255, alpha: 1)),
        ], height: 35)
        for row in [controlRow1, controlRow2] {
            row.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }

        // 数字キー (Web 版は 1〜12 を3列に並べる。送る合図は 6〜17)。
        let numberStack = UIStackView()
        numberStack.axis = .vertical
        numberStack.spacing = 8
        numberStack.translatesAutoresizingMaskIntoConstraints = false
        let numberTitles = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"]
        for startIndex in stride(from: 0, to: numberTitles.count, by: 3) {
            let rowButtons = (0 ..< 3).map { offset in
                makePanelButton(numberTitles[startIndex + offset], 6 + startIndex + offset, fontSize: 26)
            }
            numberStack.addArrangedSubview(makePanelRow(rowButtons, height: 44))
        }
        numberStack.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // データ放送の部分 (十字+操作キー)。読み込み中のぐるぐるは
        // この部分の真ん中に重ねる (Web 版と同じ置き場所)。
        let broadcastSection = UIStackView(arrangedSubviews: [dPad, controlRow1, controlRow2])
        broadcastSection.axis = .vertical
        broadcastSection.alignment = .center
        broadcastSection.setCustomSpacing(12, after: dPad)
        broadcastSection.setCustomSpacing(8, after: controlRow1)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = AppPalette.secondaryText
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        broadcastSection.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: broadcastSection.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: broadcastSection.centerYAnchor),
        ])
        remoteSpinner = spinner
        // 「データ」以外のキーは、始まっていない間と読み込み中は
        // 薄くして押せなくする。
        remoteDimmableViews = [dPad, backButton, controlRow2, numberStack]

        // パネルの中身 (縦の並び)。画面が低いときはパネルの中で滑らせる。
        let contentStack = UIStackView(arrangedSubviews: [broadcastSection, numberStack])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.setCustomSpacing(16, after: broadcastSection)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let panelScroll = UIScrollView()
        panelScroll.backgroundColor = .clear
        panelScroll.showsVerticalScrollIndicator = false
        panelScroll.translatesAutoresizingMaskIntoConstraints = false
        panelScroll.addSubview(contentStack)

        let panel = UIView()
        panel.backgroundColor = AppPalette.background
        panel.layer.cornerRadius = 8
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.35
        panel.layer.shadowRadius = 12
        panel.layer.shadowOffset = CGSize(width: 0, height: 6)
        panel.isHidden = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(panelScroll)

        // 閉じるボタン (パネルの右上、Web 版と同じ)。
        let closeButton = RippleButton()
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)),
            for: .normal
        )
        closeButton.tintColor = AppPalette.text
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(hideRemotePanel), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(closeButton)

        // 幕: 画面全体に薄くかぶさり、押すとパネルを閉じる (Web 版と同じ)。
        let backdrop = UIView()
        backdrop.backgroundColor = UIColor(red: 0x1E / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 0.5)
        backdrop.isHidden = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideRemotePanel)))

        view.addSubview(backdrop)
        view.addSubview(panel)
        // パネルの高さは Web 版と同じ 514pt を目安にし、置き場所側の
        // 上限 (画面に収まる高さ) で縮む場合は中身を滑らせて見せる。
        // 幅は置き場所によらず 234pt で固定する。
        let panelHeight = panel.heightAnchor.constraint(equalToConstant: 514)
        panelHeight.priority = .defaultHigh
        panelHeight.isActive = true
        panel.widthAnchor.constraint(equalToConstant: 234).isActive = true
        NSLayoutConstraint.activate([
            panelScroll.topAnchor.constraint(equalTo: panel.topAnchor),
            panelScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panelScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            panelScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: panelScroll.frameLayoutGuide.widthAnchor),
            closeButton.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        remoteBackdrop = backdrop
        remotePanel = panel
        // 仮置き (通常画面の置き場所)。出すたびに決め直す。
        applyRemotePanelPlacement(host: view, mode: .belowVideo)
        updateRemotePanelState()
    }

    /// リモコンのパネルの置き場所の種類。
    /// - belowVideo: 縦向きの通常画面。幕は映像の下の領域だけに敷き、
    ///   パネルは画面の下端に寄せる (映像には被せない)。
    /// - rightEdge: 全画面と、横向きの通常画面。幕は曇らせない (透明) で、
    ///   パネルは画面の右端に寄せる。
    private enum RemotePanelMode {
        case belowVideo
        case rightEdge
    }

    /// リモコンのパネルと幕の置き場所を決める。今までの置き場所の
    /// 決まりは外し、置き先のビューへ移してから新しい決まりを付ける。
    private func applyRemotePanelPlacement(host: UIView, mode: RemotePanelMode) {
        guard let backdrop = remoteBackdrop, let panel = remotePanel else { return }
        NSLayoutConstraint.deactivate(remotePlacementConstraints)
        remotePlacementConstraints = []
        if backdrop.superview !== host {
            backdrop.removeFromSuperview()
            host.addSubview(backdrop)
        }
        if panel.superview !== host {
            panel.removeFromSuperview()
            host.addSubview(panel)
        }
        switch mode {
        case .belowVideo:
            backdrop.backgroundColor = UIColor(red: 0x1E / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 0.5)
            remotePlacementConstraints = [
                backdrop.topAnchor.constraint(equalTo: videoArea.bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                backdrop.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                panel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                panel.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -12),
                panel.topAnchor.constraint(greaterThanOrEqualTo: videoArea.bottomAnchor, constant: 12),
            ]
        case .rightEdge:
            backdrop.backgroundColor = .clear
            remotePlacementConstraints = [
                backdrop.topAnchor.constraint(equalTo: host.topAnchor),
                backdrop.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                backdrop.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                panel.trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                panel.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                panel.topAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.topAnchor, constant: 12),
                panel.bottomAnchor.constraint(lessThanOrEqualTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            ]
        }
        NSLayoutConstraint.activate(remotePlacementConstraints)
    }

    /// リモコンのパネルを出す。データ放送が始まっていなくても出せる
    /// (開始はパネルの「データ」ボタンから行うため)。
    /// 通常画面では、縦向きなら映像の下に、横向きなら右端に出す。
    @objc private func showRemotePanel() {
        let landscape = view.bounds.width > view.bounds.height
        presentRemotePanel(in: view, mode: landscape ? .rightEdge : .belowVideo)
    }

    /// 指定の置き場所でリモコンのパネルを出す (全画面側からも使う)。
    private func presentRemotePanel(in host: UIView, mode: RemotePanelMode) {
        guard let backdrop = remoteBackdrop, let panel = remotePanel else { return }
        applyRemotePanelPlacement(host: host, mode: mode)
        updateRemotePanelState()
        backdrop.isHidden = false
        panel.isHidden = false
        backdrop.alpha = 0
        panel.alpha = 0
        UIView.animate(withDuration: 0.2) {
            backdrop.alpha = 1
            panel.alpha = 1
        }
    }

    /// リモコンのパネルを、動きなしで隠す。全画面側に置いていた場合は
    /// 通常画面側へ戻しておく (全画面が閉じたあとも残らないように)。
    private func hideRemotePanelImmediately() {
        guard let backdrop = remoteBackdrop, let panel = remotePanel else { return }
        backdrop.layer.removeAllAnimations()
        panel.layer.removeAllAnimations()
        backdrop.isHidden = true
        panel.isHidden = true
        if backdrop.superview !== view || panel.superview !== view {
            applyRemotePanelPlacement(host: view, mode: .belowVideo)
        }
    }

    /// 設定 (設定 → データ放送) の「データ放送機能を利用する」に
    /// 合わせて、入り口の出し分けと実行中の重ね合わせを切り替える。
    /// 画面に戻ってくるたびに確かめる。
    private func refreshDataBroadcastAvailability() {
        let enabled = SettingsStore.shared.dataBroadcastingEnabled
        updateRemoteButtonVisibility()
        if !enabled {
            hideRemotePanelImmediately()
            if isDataBroadcastActive {
                stopDataBroadcast()
            }
        }
    }

    @objc private func hideRemotePanel() {
        guard let backdrop = remoteBackdrop, let panel = remotePanel, !panel.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            backdrop.alpha = 0
            panel.alpha = 0
        }, completion: { _ in
            backdrop.isHidden = true
            panel.isHidden = true
        })
    }

    /// パネルの状態の見せ方を今の状態に合わせる。
    /// 始まっていて常駐文書まで開けていればキーをそのまま、
    /// それ以外は「データ」以外のキーを薄くして押せなくし、
    /// 読み込み中はぐるぐるを出す (Web 版の見せ方と同じ)。
    private func updateRemotePanelState() {
        let running = isDataBroadcastActive && dataBroadcastLoaded && !dataBroadcastStartFailed
        let loading = isDataBroadcastActive && !dataBroadcastLoaded && !dataBroadcastStartFailed
        for target in remoteDimmableViews {
            target.alpha = running ? 1 : 0.4
            target.isUserInteractionEnabled = running
        }
        // 読み込み中と、双方向の通信中はぐるぐるを出す (Web 版は
        // 通信中もリモコンの読み込み表示にしている)。
        if loading || dataBroadcastNetworkBusy {
            remoteSpinner?.startAnimating()
        } else {
            remoteSpinner?.stopAnimating()
        }
    }

    /// 「データ」ボタン。まだ始まっていなければ材料の受け取りから
    /// 始めて、常駐文書が開けたところでデータボタンの合図 (20) を
    /// 送って中身の画面を開く。すでに開いているときの再押しは、
    /// 合図を送るだけにして文書側の作法に任せる (Web 版・テレビと同じ)。
    @objc private func remoteDataKeyPressed() {
        if isDataBroadcastActive && dataBroadcastLoaded {
            dataBroadcastOverlay?.sendKey(20)
        } else if isDataBroadcastActive && !dataBroadcastStartFailed {
            // 読み込み中にもう一度押されたら、開けたところで送り直す。
            pendingDataKey = true
        } else {
            // まだ始まっていないか、開始が失敗したままのときは、
            // 作り直して開始する。
            if dataBroadcastOverlay != nil {
                stopDataBroadcast()
            }
            pendingDataKey = true
            startDataBroadcast()
        }
    }

    /// データ放送の重ね合わせを始める。透明な WebView を映像の真上に置き、
    /// 中のデータ放送ブラウザへ、材料の口 (アプリ内の中継経由) を渡す。
    private func startDataBroadcast() {
        guard let originURL = APIClient.shared.psiArchivedDataURL(
            displayChannelID: channel.display_channel_id,
            quality: quality,
            profile: profile
        ) else {
            messageLabel.text = "接続先が設定されていません。"
            pendingDataKey = false
            return
        }
        let overlay = DataBroadcastOverlay()
        // 知らせが、どの重ね合わせからのものか照合してから扱う。
        // 止めて間を置かずに始め直した場合、古い方の遅れた知らせが
        // 新しい方に効いてしまわないようにするため。
        overlay.onStatus = { [weak self, weak overlay] status in
            guard let self, self.dataBroadcastOverlay === overlay else { return }
            self.handleDataBroadcastStatus(status)
        }
        overlay.onVideoRect = { [weak self, weak overlay] rect in
            guard let self, self.dataBroadcastOverlay === overlay else { return }
            self.applyDataBroadcastVideoRect(rect)
        }
        dataBroadcastOverlay = overlay
        let webView = overlay.prepareWebView()
        videoArea.insertSubview(webView, aboveSubview: videoView)
        bmlHomeConstraints = [
            webView.topAnchor.constraint(equalTo: videoArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: videoArea.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: videoArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: videoArea.trailingAnchor),
        ]
        NSLayoutConstraint.activate(bmlHomeConstraints)
        // 材料の口は映像と同じくアプリ内の中継を通す (外回線の合言葉が付く)。
        // 中継が使えないときは元の URL に落ちる (映像と同じ扱い)。
        let psiURL = StreamRelayServer.shared.relayURL(for: originURL) ?? originURL
        // 双方向の通信先は、中継の向き先 (サーバー本体ではなく中継) を
        // 渡す。中継が使えず元の URL に落ちた場合は向き先を渡さない
        // (その場合は通信は失敗の形になる)。
        var proxyBase: String? = nil
        if psiURL != originURL,
           let components = URLComponents(url: psiURL, resolvingAgainstBaseURL: false),
           let host = components.host, let port = components.port {
            proxyBase = "\(components.scheme ?? "http")://\(host):\(port)"
        }
        let store = SettingsStore.shared
        let config = DataBroadcastOverlay.StartConfig(
            internetEnabled: store.dataBroadcastingInternetEnabled,
            zipCode: store.dataBroadcastingZipCode,
            prefecture: store.dataBroadcastingPrefecture,
            proxyBase: proxyBase,
            nvram: store.dataBroadcastingNvram
        )
        isDataBroadcastActive = true
        dataBroadcastLoaded = false
        dataBroadcastStartFailed = false
        overlay.start(psiURL: psiURL, serviceID: channel.service_id, config: config)
        updateRemotePanelState()
    }

    /// データ放送を止める。止めるのは、チャンネルを離れるときと、
    /// データ放送が無い局と分かったときだけ (「戻る」や「データ」の
    /// 再押しでは止めない。文書側の作法に任せる)。
    /// clearStatusMessage が false のときは、知らせ欄の文面を残す
    /// (「データ放送はありません」を消さないため)。
    private func stopDataBroadcast(clearStatusMessage: Bool = true) {
        guard isDataBroadcastActive || dataBroadcastOverlay != nil else { return }
        isDataBroadcastActive = false
        pendingDataKey = false
        dataBroadcastLoaded = false
        dataBroadcastStartFailed = false
        dataBroadcastNetworkBusy = false
        if clearStatusMessage, showingDataBroadcastStatus {
            messageLabel.text = nil
            showingDataBroadcastStatus = false
        }
        NSLayoutConstraint.deactivate(bmlHomeConstraints)
        NSLayoutConstraint.deactivate(bmlBorrowConstraints)
        bmlHomeConstraints = []
        bmlBorrowConstraints = []
        dataBroadcastOverlay?.teardown()
        dataBroadcastOverlay = nil
        // データ放送を閉じたら、字幕は映像全体の表示に戻す。
        captionOverlayView.displayRectFractions = nil
        updateRemotePanelState()
    }

    /// データ放送の文書が映像用に開けている穴に、字幕の重ね物を
    /// 合わせる。rect は映像の枠に対する割合の四角 (ページ側から
    /// 届く)。字幕と文字スーパーは穴の中だけに出し、データ放送の
    /// 画面の上には重ならないようにする。nil は指定なし
    /// (映像全体に戻す)。ほぼ全体を覆う穴も、全体表示と同じ
    /// として扱う。
    private func applyDataBroadcastVideoRect(_ rect: CGRect?) {
        guard isDataBroadcastActive else { return }
        guard let rect, rect.width > 0.01, rect.height > 0.01 else {
            captionOverlayView.displayRectFractions = nil
            return
        }
        if rect.minX <= 0.005, rect.minY <= 0.005, rect.width >= 0.995, rect.height >= 0.995 {
            captionOverlayView.displayRectFractions = nil
            return
        }
        captionOverlayView.displayRectFractions = rect
    }

    /// リモコンのボタン。ボタンの tag に ARIB のキーコードが入っている。
    @objc private func dataBroadcastRemoteKey(_ sender: UIButton) {
        dataBroadcastOverlay?.sendKey(sender.tag)
    }

    /// ページ側から届く状態を、知らせ欄の文面に直す。
    private func handleDataBroadcastStatus(_ status: String) {
        guard isDataBroadcastActive else { return }
        switch status {
        case "loading":
            messageLabel.text = "データ放送を読み込んでいます…"
            showingDataBroadcastStatus = true
        case "loaded":
            dataBroadcastLoaded = true
            dataBroadcastStartFailed = false
            // 「データ」を押して開始したときは、常駐文書が開けた
            // ところでデータボタンの合図を送り、中身の画面を開く。
            if pendingDataKey {
                pendingDataKey = false
                dataBroadcastOverlay?.sendKey(20)
            }
            if showingDataBroadcastStatus {
                messageLabel.text = nil
                showingDataBroadcastStatus = false
            }
        case "available":
            if showingDataBroadcastStatus {
                messageLabel.text = nil
                showingDataBroadcastStatus = false
            }
        case "unavailable":
            messageLabel.text = "このチャンネルにデータ放送はありません。"
            showingDataBroadcastStatus = true
            pendingDataKey = false
            // データ放送が無い局と分かったら、重ね合わせは止める
            // (知らせの文面は残す)。
            stopDataBroadcast(clearStatusMessage: false)
        case "netbusy":
            // 双方向の通信が始まった (ぐるぐるの表示だけに効く)。
            dataBroadcastNetworkBusy = true
        case "netidle":
            dataBroadcastNetworkBusy = false
        case "error":
            if dataBroadcastLoaded {
                // 読み込みが終わったあとに届いたエラーは、開始の失敗
                // ではない (材料の受け取りが途中で切れた場合や、文書側
                // から知らされる場合がある)。開始できているのに
                // 「開始できませんでした」とは出さず、別の文面にする。
                messageLabel.text = "データ放送でエラーが発生しました。"
                showingDataBroadcastStatus = true
            } else {
                messageLabel.text = "データ放送を開始できませんでした。"
                showingDataBroadcastStatus = true
                pendingDataKey = false
                dataBroadcastStartFailed = true
            }
        default:
            break
        }
        updateRemotePanelState()
    }

    /// フルスクリーン表示へ移る。映像の枠ごと全画面側へ貸し出すだけで、
    /// 受信そのものは止めない。
    private var canCaptureVideo: Bool {
        !audioOnly && !isDataBroadcastActive && !captureController.isCapturing
            && pipController?.isActive != true && pipController?.isPending != true
            && (vlcPlayer?.hasVideoOut ?? false)
    }

    private func updateCaptureControls() {
        captureButton.isEnabled = canCaptureVideo
        commentCaptureButton.isEnabled = canCaptureVideo && SettingsStore.shared.showComments
        captureButton.alpha = captureButton.isEnabled ? 1 : 0.35
        commentCaptureButton.alpha = commentCaptureButton.isEnabled ? 1 : 0.35
        activeFullscreen?.refreshCaptureControls()
    }

    private func captureVideo(comments: Bool, presenter: UIViewController) {
        guard canCaptureVideo, !comments || SettingsStore.shared.showComments else { return }
        let engine = vlcPlayer
        let context = WatchedHistoryStore.Context.current
        let capturedAt = Date()
        let program = channel.program_present
        let fallbackTime = ISO8601DateFormatter().string(from: capturedAt)
        let metadata = CaptureMetadata(capturedAt: capturedAt,
            playbackPosition: program?.startDate.map { capturedAt.timeIntervalSince($0) } ?? 0,
            networkID: channel.network_id, serviceID: channel.service_id, eventID: program?.event_id,
            title: program?.title ?? channel.name, description: program?.description,
            startTime: program?.start_time ?? fallbackTime, endTime: program?.end_time ?? fallbackTime,
            duration: program?.duration ?? 0)
        captureController.capture(vlcPlayer: engine, playerItem: nil,
            caption: SettingsStore.shared.showCaptions ? captionEngine.currentCaptionImage : nil,
            superimpose: SettingsStore.shared.showCaptions ? captionEngine.currentSuperimposeImage : nil,
            comments: comments ? commentOverlay : nil, metadata: metadata, capturedAt: capturedAt, presenter: presenter,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.pipController?.isActive != true && self.pipController?.isPending != true
                    && self.vlcPlayer === engine && context == WatchedHistoryStore.Context.current && !self.isDataBroadcastActive
            })
    }

    private func showCaptureError(_ message: String) {
        let presenter = presentedViewController ?? self
        guard presenter.viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: "キャプチャ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .default))
        presenter.present(alert, animated: true)
    }

    private func restartPlayer() {
        guard pipController?.isActive != true, pipController?.isPending != true else { return }
        let playing = vlcPlayer?.isPlaying ?? false
        startStream()
        if !playing { pauseStream() }
    }

    private func makePiPController() -> PlaybackPiPController {
        let pip = PlaybackPiPController(videoView: videoView, isLive: true,
            currentTime: { 0 }, duration: { 0 },
            isPlaying: { [weak self] in self?.vlcPlayer?.isPlaying ?? false },
            play: { [weak self] in self?.playStream() }, pause: { [weak self] in self?.pauseStream() },
            seek: { _, completion in completion() })
        pip.onStateChanged = { [weak self] in
            guard let self else { return }
            self.pipButton.isHidden = !(self.pipController?.isReady == true && !self.audioOnly)
            self.pipButton.isEnabled = self.pipController?.isPending != true
            self.pipButton.setImage(UIImage(systemName: self.pipController?.isActive == true ? "pip.exit" : "pip.enter"), for: .normal)
            self.activeFullscreen?.refreshPiPControl()
            self.updateCaptureControls()
            if self.pipController?.isActive == false, self.pipController?.isPending == false,
               self.navigationController == nil {
                self.hideRemotePanelImmediately()
                self.stopDataBroadcast()
                self.commentSession?.stop()
                self.commentOverlay.stop()
                self.stopStream()
            }
        }
        pip.onRestoreInterface = { [weak self] in
            guard let self, let navigation = self.playbackNavigation else { return }
            self.playbackTabs?.selectedIndex = self.playbackTabIndex
            if navigation.viewControllers.contains(where: { $0 === self }) {
                navigation.popToViewController(self, animated: false)
            } else { navigation.pushViewController(self, animated: false) }
        }
        pip.onSuperseded = { [weak self] in
            guard let self else { return }
            self.wasPlayingBeforeStop = self.vlcPlayer?.isPlaying ?? false
            self.stoppedOnDisappear = true
            self.hideRemotePanelImmediately()
            self.stopDataBroadcast()
            self.commentSession?.stop()
            self.commentOverlay.stop()
            self.stopStream()
        }
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

    @objc private func togglePiP() {
        playerSettingsPanel?.closePanel()
        activeFullscreen?.playerSettingsPanel?.closePanel()
        captureController.cancel()
        guard let pip = pipController, !audioOnly else { return }
        if pip.isActive || pip.isPending { pip.stop() } else { pip.start(owner: self) }
    }

    @objc private func openPlayerSettings() { showPlayerSettings(from: self) }

    private func showPlayerSettings(from presenter: UIViewController) {
        if let panel = presenter.playerSettingsPanel { panel.closePanel(); return }
        hideTimer?.invalidate()
        let menu = PlayerSettingsViewController { [weak self] in
            guard let self else { return [] }
            let store = SettingsStore.shared
            let saver = store.dataSaverMode(media: .tv, profile: self.profile)
            var rows: [PlayerSettingsViewController.Row] = [
                .init(title: "画質", value: self.quality, choices: SettingsStore.qualities.map { q in
                    .init(title: SettingsStore.qualityDisplayName(q, dataSaverMode: saver), selected: q == self.quality,
                          select: { [weak self] in self?.userSwitchQuality(q) })
                }),
                .init(title: "モバイル回線向け画質", toggle: self.profile == .cellular, change: { [weak self] on in
                    _ = self?.switchProfile(to: on ? .cellular : .wifi)
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
            ]
            if self.pipController?.isActive == true || self.pipController?.isPending == true {
                for index in rows.indices where ["画質", "モバイル回線向け画質", "音声のみ再生"].contains(rows[index].title) {
                    rows[index].isEnabled = false
                }
            } else { rows.append(.init(title: "プレイヤーを再起動", action: { [weak self] in self?.restartPlayer() })) }
            return rows
        }
        let navigation = PlayerSettingsNavigationController(rootViewController: menu)
        navigation.onClose = { [weak self, weak presenter] in
            self?.scheduleHideControls()
            self?.updateCaptureControls()
#if canImport(VLCKit)
            (presenter as? LiveFullscreenViewController)?.resumeControlAutoHide()
#endif
        }
        if presenter === self {
            navigation.mount(in: self, below: videoArea, hiding: panelTabBar)
        } else { navigation.mount(in: presenter) }
    }

    @objc private func showFullscreen() {
        playerSettingsPanel?.closePanel()
#if canImport(VLCKit)
        guard vlcPlayer != nil else { return }
        let fullscreen = LiveFullscreenViewController(channelName: channel.name)
        activeFullscreen = fullscreen
        fullscreen.pipAvailable = { [weak self] in self?.pipController?.isReady == true && self?.audioOnly == false }
        fullscreen.onTogglePiP = { [weak self] in self?.togglePiP() }
        fullscreen.captureAvailable = { [weak self] in self?.canCaptureVideo == true }
        fullscreen.commentCaptureAvailable = { [weak self] in self?.canCaptureVideo == true && SettingsStore.shared.showComments }
        fullscreen.onCapture = { [weak self] comments, presenter in self?.captureVideo(comments: comments, presenter: presenter) }
        fullscreen.pipActive = { [weak self] in self?.pipController?.isActive == true }
        fullscreen.pipPending = { [weak self] in self?.pipController?.isPending == true }
        fullscreen.commentsEnabled = { SettingsStore.shared.showComments }
        fullscreen.commentAvailable = { [weak self] in self?.audioOnly == false }
        fullscreen.onToggleComments = { [weak self] in self?.toggleComments() }
        fullscreen.captionsEnabled = { SettingsStore.shared.showCaptions }
        fullscreen.captionAvailable = { [weak self] in self?.audioOnly == false }
        fullscreen.onToggleCaptions = { [weak self] in self?.toggleCaptions() }
        fullscreen.onShowSettings = { [weak self] presenter in self?.showPlayerSettings(from: presenter) }
        fullscreen.onWillAppear = { [weak self] fullscreenVideoView in
            self?.borrowVideoView(into: fullscreenVideoView)
        }
        fullscreen.onWillDisappear = { [weak self] in
            guard let self else { return }
            // 全画面側に出していたリモコンのパネルは隠して戻す。
            self.hideRemotePanelImmediately()
            self.returnVideoView()
            self.refreshPlayPauseIcon()
        }
        // 全画面にもリモコンの浮きボタンを出す (設定でデータ放送機能が
        // オフのときは出さない)。押されたら、全画面側の画面にパネルを
        // 右端寄せで出す。
        fullscreen.remoteButtonVisible = SettingsStore.shared.dataBroadcastingEnabled
        fullscreen.onShowRemotePanel = { [weak self, weak fullscreen] in
            guard let self, let fullscreen else { return }
            self.presentRemotePanel(in: fullscreen.view, mode: .rightEdge)
        }
        fullscreen.onTogglePlayPause = { [weak self] in
            self?.togglePlayPause()
        }
        fullscreen.isPlayingProvider = { [weak self] in
            self?.vlcPlayer?.isPlaying ?? false
        }
        present(fullscreen, animated: true)
#endif
    }

    /// 全画面表示の間、映像の枠 (videoView) そのものを全画面側へ貸し出す。
    /// VLC の描き先は videoView のまま変えず、枠の置き場所だけを移す。
    /// 再生中に描き先を別のビューへ差し替えると、全画面で音だけ出て映像が
    /// 出なくなる (録画側で実機確認済みの弱点) ため、この形にしている。
    /// 枠の中の描画は枠と一緒にそのまま付いてくるので、受信は途切れない。
    private func borrowVideoView(into container: UIView) {
        guard videoView.superview !== container else { return }
        NSLayoutConstraint.deactivate(videoViewHomeConstraints)
        videoView.removeFromSuperview()
        container.addSubview(videoView)
        videoViewBorrowConstraints = [
            videoView.topAnchor.constraint(equalTo: container.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ]
        NSLayoutConstraint.activate(videoViewBorrowConstraints)
        // 貸し出し中は、通常画面側のタップ (操作帯の出し入れ) を止める
        // (全画面側のタップと二重に効かないように)。
        videoTapRecognizer?.isEnabled = false
        // データ放送の重ね合わせも、映像の枠と一緒に貸し出す。
        if let webView = dataBroadcastOverlay?.webView, webView.superview === videoArea {
            NSLayoutConstraint.deactivate(bmlHomeConstraints)
            webView.removeFromSuperview()
            container.addSubview(webView)
            bmlBorrowConstraints = [
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ]
            NSLayoutConstraint.activate(bmlBorrowConstraints)
        }
        // 実況コメントの流れる表示も、映像の枠と一緒に貸し出す
        // (データ放送の上、字幕の下)。
        if commentOverlay.superview === videoArea {
            NSLayoutConstraint.deactivate(commentHomeConstraints)
            commentOverlay.removeFromSuperview()
            container.addSubview(commentOverlay)
            commentBorrowConstraints = [
                commentOverlay.topAnchor.constraint(equalTo: container.topAnchor),
                commentOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                commentOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                commentOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ]
            NSLayoutConstraint.activate(commentBorrowConstraints)
        }
        // 字幕の重ね物も、映像の枠と一緒に貸し出す (一番上に置く)。
        if captionOverlayView.superview === videoArea {
            NSLayoutConstraint.deactivate(captionHomeConstraints)
            captionOverlayView.removeFromSuperview()
            container.addSubview(captionOverlayView)
            captionBorrowConstraints = [
                captionOverlayView.topAnchor.constraint(equalTo: container.topAnchor),
                captionOverlayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                captionOverlayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                captionOverlayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ]
            NSLayoutConstraint.activate(captionBorrowConstraints)
        }
    }

    /// 貸し出した映像の枠を通常画面へ戻す。
    private func returnVideoView() {
        guard videoView.superview !== videoArea else { return }
        NSLayoutConstraint.deactivate(videoViewBorrowConstraints)
        videoViewBorrowConstraints = []
        videoView.removeFromSuperview()
        videoArea.addSubview(videoView)
        // 重ね物 (操作帯など) より後ろへ戻す。
        videoArea.sendSubviewToBack(videoView)
        NSLayoutConstraint.activate(videoViewHomeConstraints)
        videoTapRecognizer?.isEnabled = true
        // データ放送の重ね合わせも、映像の枠と一緒に通常画面へ戻す。
        if let webView = dataBroadcastOverlay?.webView, webView.superview !== videoArea {
            NSLayoutConstraint.deactivate(bmlBorrowConstraints)
            bmlBorrowConstraints = []
            webView.removeFromSuperview()
            videoArea.insertSubview(webView, aboveSubview: videoView)
            NSLayoutConstraint.activate(bmlHomeConstraints)
        }
        // 実況コメントの流れる表示も通常画面へ戻す。
        if commentOverlay.superview !== videoArea {
            NSLayoutConstraint.deactivate(commentBorrowConstraints)
            commentBorrowConstraints = []
            commentOverlay.removeFromSuperview()
            videoArea.addSubview(commentOverlay)
            NSLayoutConstraint.activate(commentHomeConstraints)
        }
        // 字幕の重ね物も通常画面へ戻す (一番上に置く)。
        if captionOverlayView.superview !== videoArea {
            NSLayoutConstraint.deactivate(captionBorrowConstraints)
            captionBorrowConstraints = []
            captionOverlayView.removeFromSuperview()
            videoArea.addSubview(captionOverlayView)
            NSLayoutConstraint.activate(captionHomeConstraints)
        }
        restoreControlLayerOrder()
    }

    /// 字幕・実況の更新や全画面からの返却でも、操作を映像の上に保つ。
    private func restoreControlLayerOrder() {
        for control in [controlsContainer, playPauseButton, overlayTopGradient, overlayHeader] where control.superview === videoArea {
            videoArea.bringSubviewToFront(control)
        }
    }

    private func refreshPlayPauseIcon() {
#if canImport(VLCKit)
        let playing = vlcPlayer?.isPlaying ?? false
        playPauseButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        // 止まっている間は操作帯を出したままにする (録画再生と同じ)。
        if !playing {
            setControlsVisible(true)
        } else {
            scheduleHideControls()
        }
#endif
    }
}

#if canImport(VLCKit)
extension LivePlayerViewController {
    /// VLC 側の状態変化 (再生開始・停止・終了など) に、画面内のボタンと
    /// ロック画面の表示を追随させる。
    func handleVLCState(_ state: VLCMediaPlayerState, source: VLCMediaPlayer) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard source === self.vlcPlayer else { return }
            self.pipController?.invalidatePlaybackState()
            self.updateCaptureControls()
            // 開始に失敗したら、真っ黒のまま無言にせず、その旨を表示する
            // (録画側と同じ扱い。再生の仕組み自体は変えていない)。
            if self.vlcPlayer?.state == .error {
                self.messageLabel.text = "再生を開始できませんでした。"
            } else if self.vlcPlayer?.state == .playing {
                // 再生が始まったので、開始の見張りは止める。
                self.didStartPlaying = true
                self.startWatchdog?.invalidate()
                self.startWatchdog = nil
                if self.messageLabel.text == "再生を開始できませんでした。" {
                    self.messageLabel.text = nil
                }
            }
            self.refreshPlayPauseIcon()
            self.updateCommentClock()
            self.updateNowPlaying()
            // 画質の切り替え後に再生が始まったら、切り替え完了時点の
            // 書き戻しを行う (開始時点で書き戻したのと同じ値を、
            // 完了の合図としてもう一度保存する)。
            if self.vlcPlayer?.state == .playing,
               let pending = self.pendingQualityWriteBack,
               pending == self.quality {
                SettingsStore.shared.setStreamingQuality(pending, media: .tv, profile: self.profile)
                self.pendingQualityWriteBack = nil
            }
        }
    }
}

/// 生放送のフルスクリーン画面。映像だけの全画面表示に、
/// 終了ボタンと再生・一時停止だけを重ねて出す。
/// 操作類はタップで出し、再生中はしばらく触らなければ自動で消える。
final class LiveFullscreenViewController: UIViewController {
    private let channelName: String

    /// 表示されたら呼ばれる (引数は映像の枠の貸し出し先)。
    var onWillAppear: ((UIView) -> Void)?
    /// 閉じられる前に呼ばれる (貸し出した枠を通常画面へ戻すため)。
    var onWillDisappear: (() -> Void)?
    /// 再生・一時停止の切り替えを呼び出し元へ委ねる。
    var onTogglePlayPause: (() -> Void)?
    /// 現在再生中かどうかを呼び出し元へ聞く。
    var isPlayingProvider: (() -> Bool)?
    /// リモコンの浮きボタンが押されたときに呼ばれる (パネル自体は
    /// 呼び出し元がこの画面の上に出す)。
    var onShowRemotePanel: (() -> Void)?
    /// リモコンの浮きボタンを出すかどうか (設定でデータ放送機能が
    /// オフのときは出さない)。表示前に呼び出し元が決める。
    var remoteButtonVisible = true

    private let videoView = UIView()
    /// 上部の帯のグラデーション (Web 版ヘッダーと同じ、黒から透明へ)。
    private let topGradient = GradientView(direction: .top)
    private let topBar = UIStackView()
    private let nameLabel = UILabel()
    private let exitButton = RippleButton()
    private let playPauseButton = RippleButton()
    /// リモコンの浮きボタン (通常画面と同じ顔ぶれ: 48x48 の円)。
    /// 操作類と一緒に現れて、一緒に消える。
    private let remoteButton = RippleButton()
    private var optionsRow: PlayerActionRow!
    private let captionButton = RippleButton()
    private let pipButton = RippleButton()
    var pipAvailable: (() -> Bool)?
    var pipActive: (() -> Bool)?
    var pipPending: (() -> Bool)?
    private let captureButton = RippleButton()
    private let commentCaptureButton = RippleButton()
    var captureAvailable: (() -> Bool)?
    var commentCaptureAvailable: (() -> Bool)?
    var onCapture: ((Bool, UIViewController) -> Void)?
    var onTogglePiP: (() -> Void)?
    private let commentButton = RippleButton()
    var commentsEnabled: (() -> Bool)?
    var commentAvailable: (() -> Bool)?
    var onToggleComments: (() -> Void)?
    var captionsEnabled: (() -> Bool)?
    var captionAvailable: (() -> Bool)?
    var onToggleCaptions: (() -> Void)?
    var onShowSettings: ((UIViewController) -> Void)?
    private var controlsVisible = true
    private var hideTimer: Timer?

    init(channelName: String) {
        self.channelName = channelName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { !controlsVisible }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()
        updatePlayPauseIcon()
        scheduleHideControls()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onWillAppear?(videoView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if (presentedViewController is ViewerNavigationController || presentedViewController is UIActivityViewController), !isBeingDismissed { return }
        hideTimer?.invalidate()
        hideTimer = nil
        onWillDisappear?()
    }

    private func buildLayout() {
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        videoView.addGestureRecognizer(tap)

        // 終了ボタンは丸い地をやめ、グラデーションの帯の上にアイコンだけを置く
        // (Web 版ヘッダーの戻るアイコンと同じ考え方。当たり判定の 44x44 は保つ)。
        exitButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal
        )
        exitButton.tintColor = .white
        exitButton.addTarget(self, action: #selector(exitFullscreen), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            exitButton.widthAnchor.constraint(equalToConstant: 44),
            exitButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        nameLabel.text = channelName
        nameLabel.textColor = .white
        nameLabel.font = .scaledSystemFont(ofSize: 16, weight: .bold)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        nameLabel.shadowOffset = CGSize(width: 0, height: 1)

        topGradient.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topGradient)

        topBar.axis = .horizontal
        topBar.spacing = 12
        topBar.alignment = .center
        topBar.addArrangedSubview(exitButton)
        topBar.addArrangedSubview(nameLabel)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playPauseButton)

        // リモコンの浮きボタンは画面の右下 (余白 16)。地は通常画面と
        // 同じ panel 色で、操作類と一緒に現れて消える。
        remoteButton.setImage(
            UIImage(systemName: "appletvremote.gen4.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))
                ?? UIImage(systemName: "tv", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25)),
            for: .normal
        )
        remoteButton.tintColor = AppPalette.text
        remoteButton.backgroundColor = AppPalette.panel
        remoteButton.layer.cornerRadius = 24
        remoteButton.layer.shadowColor = UIColor.black.cgColor
        remoteButton.layer.shadowOpacity = 0.3
        remoteButton.layer.shadowRadius = 6
        remoteButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        remoteButton.accessibilityLabel = "リモコン"
        remoteButton.addTarget(self, action: #selector(showRemotePanelFromFullscreen), for: .touchUpInside)
        remoteButton.translatesAutoresizingMaskIntoConstraints = false
        remoteButton.isHidden = !remoteButtonVisible
        view.addSubview(remoteButton)
        let settings = RippleButton()
        let fullscreen = RippleButton()
        styleVideoOverlayButton(captionButton, symbol: "captions.bubble", title: "字幕の表示を切り替え", adaptive: true)
        styleVideoOverlayButton(settings, symbol: "gearshape.fill", title: "プレイヤー設定", adaptive: true)
        styleVideoOverlayButton(fullscreen, symbol: "arrow.down.right.and.arrow.up.left", title: "全画面を解除", adaptive: true)
        captionButton.addAction(UIAction { [weak self] _ in
            self?.onToggleCaptions?()
            self?.updateCaptionControl()
            self?.scheduleHideControls()
        }, for: .touchUpInside)
        updateCaptionControl()
        settings.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.hideTimer?.invalidate()
            self.onShowSettings?(self)
        }, for: .touchUpInside)
        fullscreen.addTarget(self, action: #selector(exitFullscreen), for: .touchUpInside)
        styleVideoOverlayButton(commentButton, symbol: "text.bubble", title: "実況コメントの表示を切り替え", adaptive: true)
        commentButton.addAction(UIAction { [weak self] _ in
            self?.onToggleComments?()
            self?.updateCaptionControl()
            self?.scheduleHideControls()
        }, for: .touchUpInside)
        styleVideoOverlayButton(pipButton, symbol: "pip.enter", title: "ピクチャ・イン・ピクチャ", adaptive: true)
        pipButton.addAction(UIAction { [weak self] _ in self?.onTogglePiP?() }, for: .touchUpInside)
        refreshPiPControl()
        styleVideoOverlayButton(captureButton, symbol: "camera", title: "キャプチャ", adaptive: true)
        styleVideoOverlayButton(commentCaptureButton, symbol: "camera.badge.ellipsis", title: "コメント付きキャプチャ", adaptive: true)
        captureButton.addAction(UIAction { [weak self] _ in guard let self else { return }; self.onCapture?(false, self) }, for: .touchUpInside)
        commentCaptureButton.addAction(UIAction { [weak self] _ in guard let self else { return }; self.onCapture?(true, self) }, for: .touchUpInside)
        optionsRow = PlayerActionRow(time: UIView(), buttons: [captureButton, commentCaptureButton, commentButton, captionButton, settings, pipButton, fullscreen])
        optionsRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(optionsRow)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topGradient.topAnchor.constraint(equalTo: view.topAnchor),
            topGradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topGradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topGradient.heightAnchor.constraint(equalToConstant: 66),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            // 再生・一時停止は下辺ではなく画面の真ん中に置く
            // (本家 Web 版の中央の並びと同じ置き場所)。
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 60),
            playPauseButton.heightAnchor.constraint(equalToConstant: 60),
            remoteButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            remoteButton.bottomAnchor.constraint(equalTo: optionsRow.topAnchor, constant: -8),
            optionsRow.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            optionsRow.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            optionsRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            remoteButton.widthAnchor.constraint(equalToConstant: 48),
            remoteButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    @objc private func showRemotePanelFromFullscreen() {
        onShowRemotePanel?()
    }

    @objc private func toggleControls() {
        setControlsVisible(!controlsVisible)
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) {
            self.optionsRow.alpha = visible ? 1 : 0
            self.topBar.alpha = visible ? 1 : 0
            self.topGradient.alpha = visible ? 1 : 0
            self.playPauseButton.alpha = visible ? 1 : 0
            self.remoteButton.alpha = visible ? 1 : 0
        }
        optionsRow.isUserInteractionEnabled = visible
        topBar.isUserInteractionEnabled = visible
        playPauseButton.isUserInteractionEnabled = visible
        remoteButton.isUserInteractionEnabled = visible
        setNeedsStatusBarAppearanceUpdate()
        if !visible {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    func refreshCaptureControls() {
        captureButton.isEnabled = captureAvailable?() ?? false
        commentCaptureButton.isEnabled = commentCaptureAvailable?() ?? false
        captureButton.alpha = captureButton.isEnabled ? 1 : 0.35
        commentCaptureButton.alpha = commentCaptureButton.isEnabled ? 1 : 0.35
    }

    private func updateCaptionControl() {
        refreshCaptureControls()
        let commentsOn = commentsEnabled?() ?? false
        commentButton.isEnabled = commentAvailable?() ?? false
        commentButton.setImage(UIImage(systemName: commentsOn ? "text.bubble.fill" : "text.bubble"), for: .normal)
        commentButton.alpha = commentButton.isEnabled ? (commentsOn ? 1 : 0.4) : 0.25
        commentButton.accessibilityValue = commentsOn ? "オン" : "オフ"
        let on = captionsEnabled?() ?? false
        captionButton.isEnabled = captionAvailable?() ?? false
        captionButton.setImage(UIImage(systemName: on ? "captions.bubble.fill" : "captions.bubble"), for: .normal)
        captionButton.alpha = captionButton.isEnabled ? (on ? 1 : 0.45) : 0.25
        captionButton.accessibilityValue = on ? "オン" : "オフ"
    }

    func refreshPiPControl() {
        pipButton.isHidden = !(pipAvailable?() ?? false)
        pipButton.isEnabled = !(pipPending?() ?? false)
        pipButton.setImage(UIImage(systemName: pipActive?() == true ? "pip.exit" : "pip.enter"), for: .normal)
        pipButton.accessibilityValue = pipActive?() == true ? "再生中" : "停止中"
    }

    func resumeControlAutoHide() {
        updateCaptionControl()
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard isPlayingProvider?() ?? false, presentedViewController == nil, playerSettingsPanel == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.setControlsVisible(false)
        }
    }

    private func updatePlayPauseIcon() {
        let playing = isPlayingProvider?() ?? false
        playPauseButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
    }

    @objc private func exitFullscreen() {
        let presenter = presentingViewController
        dismiss(animated: true) {
            // 入るときの横向きへの要求 (requestGeometryUpdate) は閉じただけでは
            // 戻らないため、閉じ終わったあとに向きの戻しを明示的に行う。
            presenter?.restoreOrientationAfterFullscreen()
        }
    }

    @objc private func togglePlayPause() {
        onTogglePlayPause?()
        updatePlayPauseIcon()
        scheduleHideControls()
    }
}
#endif

// MARK: - パネルの一覧 (チャンネル/コメント)

extension LivePlayerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === channelTableView {
            guard channelGroups.indices.contains(selectedChannelGroupIndex) else { return 0 }
            return channelGroups[selectedChannelGroupIndex].channels.count
        }
        return liveComments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === channelTableView {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: LiveChannelCell.reuseID, for: indexPath) as! LiveChannelCell
            // 並びが組み直された直後など、行の対応が合わないときは
            // 無理に読まず、空の行を返す (落ちないための守り)。
            guard channelGroups.indices.contains(selectedChannelGroupIndex),
                  channelGroups[selectedChannelGroupIndex].channels.indices.contains(indexPath.row)
            else { return UITableViewCell() }
            let target = channelGroups[selectedChannelGroupIndex].channels[indexPath.row]
            let isPinned = SyncedSettingsStore.shared.current.pinnedChannelIDs.contains(target.id)
            cell.configure(with: target, isPinned: isPinned)
            cell.onPinToggle = { [weak self] in self?.toggleChannelPin(target) }
            return cell
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: LiveCommentListCell.reuseID, for: indexPath) as! LiveCommentListCell
        // 使い回しのセルをそのまま返すと前の行の表示が残るため、
        // 対応が合わないときは空のセルを返す。
        guard liveComments.indices.contains(indexPath.row) else { return UITableViewCell() }
        let comment = liveComments[indexPath.row]
        cell.configure(with: comment)
        cell.onMenu = { [weak self] in self?.showCommentMenu(for: comment) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard tableView === channelTableView,
              channelGroups.indices.contains(selectedChannelGroupIndex) else { return }
        let channels = channelGroups[selectedChannelGroupIndex].channels
        guard channels.indices.contains(indexPath.row) else { return }
        let target = channels[indexPath.row]
        // 選局は次の回しへ回す。触れた処理の最中に今の画面を入れ替えると、
        // 一覧側の残りの処理が、壊れた後の画面や一覧に触れてしまい、
        // アプリが落ちる (実機で発生したため、この形に変えた)。
        DispatchQueue.main.async { [weak self] in
            self?.switchChannel(to: target)
        }
    }

    /// コメント一覧を手で動かしているときは、一番下にいるかどうかで
    /// 「最新に追いかける」状態を切り替える。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === commentTableView,
              scrollView.isDragging || scrollView.isDecelerating else { return }
        let distanceToBottom = scrollView.contentSize.height
            - scrollView.contentOffset.y - scrollView.bounds.height
        let atBottom = distanceToBottom < 60
        if atBottom != commentFollow {
            commentFollow = atBottom
            commentJumpButton.isHidden = atBottom
        }
    }
}

extension LivePlayerViewController: UIGestureRecognizerDelegate {
    /// チャンネルパネルの左右スワイプのしぐさが成立するかどうか。
    /// 横方向の動きのときだけ true を返し、縦方向のときは false で
    /// 即座に不成立にすることで、縦スクロールが遅れずに始まるように
    /// する (生放送一覧と同じ判定の仕方)。向きの判定は、速度が出て
    /// いれば速度、無ければ移動量という具合に、1つのベクトルで
    /// そろえて行う。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan === channelGroupSwipePan else { return true }
        guard selectedPanelTab == .channel, channelGroups.count > 1 else { return false }
        let velocity = pan.velocity(in: channelTableView)
        let translation = pan.translation(in: channelTableView)
        let useVelocity = abs(velocity.x) > 1 || abs(velocity.y) > 1
        let dx = useVelocity ? velocity.x : translation.x
        let dy = useVelocity ? velocity.y : translation.y
        return abs(dx) > abs(dy)
    }
}

extension LivePlayerViewController: UITextFieldDelegate {
    /// 送信キーでもコメントを送る。
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === commentTextField {
            sendCommentTapped()
        }
        return true
    }
}

/// 生放送のコメント一覧の1行 (本文 + 時刻 + 操作ボタン)。
/// 自分の投稿は、地の色を変えて目印にする。
final class LiveCommentListCell: UITableViewCell {
    static let reuseID = "LiveCommentListCell"

    var onMenu: (() -> Void)?

    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()
    private let menuButton = RippleButton()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        bodyLabel.textColor = AppPalette.text
        bodyLabel.font = .scaledSystemFont(ofSize: 13)
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyLabel)

        timeLabel.textColor = AppPalette.metaText
        timeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeLabel)

        menuButton.setImage(
            UIImage(systemName: "ellipsis",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)),
            for: .normal)
        menuButton.tintColor = AppPalette.metaText
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(menuButton)

        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            bodyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            timeLabel.centerYAnchor.constraint(equalTo: bodyLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: bodyLabel.trailingAnchor, constant: 10),
            menuButton.centerYAnchor.constraint(equalTo: bodyLabel.centerYAnchor),
            menuButton.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 4),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            menuButton.widthAnchor.constraint(equalToConstant: 32),
            menuButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with comment: LiveJikkyoComment) {
        bodyLabel.text = comment.text
        timeLabel.text = comment.timeText
        contentView.backgroundColor = comment.myPost
            ? AppPalette.panel.withAlphaComponent(0.6) : .clear
    }

    @objc private func menuTapped() {
        onMenu?()
    }
}
