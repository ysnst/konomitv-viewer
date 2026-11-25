import AVFoundation
import UIKit

/// 録画再生のフルスクリーン画面。映像だけの全画面表示に、操作類を重ねて出す。
/// 操作類はタップで出し、再生中はしばらく触らなければ自動で消える。
/// 再生の仕組みが2通りある: AVPlayer のときは呼び出し元と同じプレイヤーを
/// 共有し、映像の層も呼び出し元のものをそのまま借りる (同じプレイヤーに
/// 層を2つ作ると、映像が出るのはどちらか1つだけになるため)。
/// VLCKit (H.265 / HEVC の画質) のときは下の PlaybackHooks 経由で
/// 呼び出し元に操作を委ね、映像の枠ごとこちらへ貸し出してもらう
/// (生放送の全画面と同じ考え方)。
final class FullscreenPlayerViewController: UIViewController {
    /// VLCKit 経路で全画面を使うときの、再生の受け渡し口。
    /// 映像の枠の貸し出しと、位置・長さ・再生状態の読み取り、
    /// 再生・停止・移動の委譲を、呼び出し元 (再生画面) から受け取る。
    struct PlaybackHooks {
        /// 映像の枠を、引数のビュー (全画面側の受け入れ先) の中へ貸し出す。
        var attachVideo: (UIView) -> Void
        /// 貸し出した映像の枠を、呼び出し元の通常画面へ返す。
        var detachVideo: () -> Void
        /// 現在の再生位置 (秒)。
        var currentTime: () -> Double
        /// 再生側が読み取った全体の長さ (秒)。定まらないときは NaN。
        var itemDuration: () -> Double
        /// いま再生中かどうか。
        var isPlaying: () -> Bool
        /// 設定されている再生速度で再生を始める。
        var play: () -> Void
        /// 再生を止める。
        var pause: () -> Void
        /// 指定した位置 (秒) へ移動する。
        var seek: (Double) -> Void
        /// いま音が消えているかどうか (長押しの高速シーク用)。
        var isMuted: () -> Bool
        /// 音を消す・戻す (長押しの高速シーク用)。
        var setMuted: (Bool) -> Void
        /// 表示用の再生位置 (秒)。移動の確定直後など、再生部品の実位置が
        /// まだ飛び先へ移っていない間だけ、表示に使う位置を返す。
        /// 合わせが不要なときは nil (実位置を表示する)。
        var displayTime: (() -> Double?)? = nil
    }

    /// AVPlayer 経路のときの共有プレイヤー。VLCKit 経路では nil。
    private let player: AVPlayer?
    /// AVPlayer 経路で呼び出し元から借りる映像の層。呼び出し元が通常画面で
    /// 使っている層そのもの (全画面用に別の層は作らない)。渡されないときは nil。
    private let sharedPlayerLayer: AVPlayerLayer?
    /// 借りた層を呼び出し元へ返すための知らせ先 (全画面を閉じるときに呼ぶ)。
    private let onReturnPlayerLayer: ((AVPlayerLayer) -> Void)?
    /// 字幕の重ね物 (AVPlayer 経路で呼び出し元から借りる。映像の層と同じく、
    /// 字幕の更新は呼び出し元が続けるため、こちらは置き場所だけを提供する)。
    /// 渡されないときは nil。VLCKit 経路では映像の枠の中に字幕も入って
    /// いるため、こちらは使わない。
    var borrowedCaptionView: UIView?
    /// 借りた字幕の重ね物を返すための知らせ先 (全画面を閉じるときに呼ぶ)。
    var onReturnCaptionView: (() -> Void)?
    /// 全画面へ貸し出し中に、字幕の重ね物を固定する決まり (制約)。
    private var captionBorrowConstraints: [NSLayoutConstraint] = []
    /// コメントの重ね物 (AVPlayer 経路で呼び出し元から借りる。字幕と同じく、
    /// 流れる表示の更新は呼び出し元が続けるため、こちらは置き場所だけを
    /// 提供する)。映像の上・字幕の下に重ねる。渡されないときは nil。
    /// VLCKit 経路では映像の枠と一緒に貸し出されるため、こちらは使わない。
    var borrowedCommentView: UIView?
    /// 借りたコメントの重ね物を返すための知らせ先 (全画面を閉じるときに呼ぶ)。
    var onReturnCommentView: (() -> Void)?
    /// 全画面へ貸し出し中に、コメントの重ね物を固定する決まり (制約)。
    private var commentBorrowConstraints: [NSLayoutConstraint] = []
    /// 映像と重ね物の付け替えが済んだかどうか。付け替えは開く動きが
    /// 終わってから行い、返すのは閉じる動きが終わってからにする
    /// (切り替わりの先頭で同期して行うと、その間ずっと画面が
    /// 固まってしまうため)。
    private var borrowedViewsAttached = false
    /// VLCKit 経路のときの受け渡し口。AVPlayer 経路では nil。
    private let hooks: PlaybackHooks?
    private let program: RecordedProgram
    private var quality: String
    /// 現在の画質プロファイルがモバイル回線向けかどうか。
    private var isCellularProfile: Bool

    /// 画質が選ばれたときに呼び出し元へ知らせる (実際の切り替えは呼び出し元が行う)。
    var onQualitySelected: ((String) -> Void)?
    /// 画質プロファイルが切り替えられたときに呼び出し元へ知らせる
    /// (引数は切り替え後の「モバイル回線向けかどうか」。実際の切り替えは
    /// 呼び出し元が行い、切り替え後に実際に使われる画質を戻り値で返すので、
    /// こちらの画質表示はそれに合わせる)。
    var onProfileSelected: ((Bool) -> String)?

    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    /// VLCKit 経路で進み具合を 0.5 秒ごとに見るためのタイマー
    /// (AVPlayer 経路の定期観測にあたる)。
    private var progressTimer: Timer?
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    private var controlsVisible = true
    private var hideTimer: Timer?
    /// 長押しの高速シーク (送り・戻し)。
    private let fastSeekBackController = FastSeekController(direction: -1)
    private let fastSeekForwardController = FastSeekController(direction: 1)
    /// 高速シーク中の消音の持ち主 (送り・戻しで共有し、同時に
    /// 長押ししても消音が残らないようにする)。
    private let fastSeekMuteKeeper = FastSeekMuteKeeper()

    private let videoView = UIView()
    /// 上部・下部の帯のグラデーション (Web 版のヘッダー帯・操作帯と同じ、黒から透明へ)。
    private let topGradient = GradientView(direction: .top)
    private let topBar = UIStackView()
    private let titleLabel = UILabel()
    private let exitButton = RippleButton()
    private let bottomPanel = GradientView(direction: .bottom)
    /// 画面の真ん中に置く操作の並び (前の場面へ・少し戻る・再生/一時停止・
    /// 少し進む・次の場面へ)。本家 Web 版の中央の並びと同じ置き場所で、
    /// 上帯・下パネルと一緒に透明度で出し入れする。
    private let centerControls = UIStackView()
    /// 操作ボタンはすべて共通部品の波紋つきボタン (押したときの反応)。
    private let playPauseButton = RippleButton()
    private let skipBackButton = RippleButton()
    private let skipForwardButton = RippleButton()
    private let prevChapterButton = RippleButton()
    private let nextChapterButton = RippleButton()
    private let seekSlider = UISlider()
    private let bandView = CMSectionBandView()
    /// 盛り上がりの波形の帯 (通常画面と同じ部品)。シークバーの上に
    /// 置き、材料 (密度と区間) が呼び出し元から渡されたときだけ出す。
    /// 出すかどうかは設定「全画面でも盛り上がり波形を表示する」
    /// (端末保存、既定オン) でも切り替えられる。
    private let excitementStrip = ExcitementStripView()
    /// 波形の材料が渡っているかどうか。
    private var hasExcitementData = false
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let qualityButton = RippleButton()
    private let profileButton = RippleButton()

    init(player: AVPlayer, program: RecordedProgram, quality: String, isCellularProfile: Bool,
         sharedPlayerLayer: AVPlayerLayer? = nil,
         onReturnPlayerLayer: ((AVPlayerLayer) -> Void)? = nil) {
        self.player = player
        self.hooks = nil
        self.sharedPlayerLayer = sharedPlayerLayer
        self.onReturnPlayerLayer = onReturnPlayerLayer
        self.program = program
        self.quality = quality
        self.isCellularProfile = isCellularProfile
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    /// VLCKit 経路用。映像の枠はこちらへ貸し出してもらい、操作は受け渡し口
    /// 経由で呼び出し元が行う。
    init(program: RecordedProgram, quality: String, isCellularProfile: Bool, hooks: PlaybackHooks) {
        self.player = nil
        self.hooks = hooks
        self.sharedPlayerLayer = nil
        self.onReturnPlayerLayer = nil
        self.program = program
        self.quality = quality
        self.isCellularProfile = isCellularProfile
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 全画面は横向きで見るものとして、横向きだけに寄せる。
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { !controlsVisible }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()
        // 長押しの高速シークはアプリだけで完結するため常時有効
        // (通常画面の再生画面と同じ扱い)。
        setupFastSeek()

        // 映像と重ね物の付け替えは、開く動きが終わってから
        // attachBorrowedViews で行う (ここでは行わない)。
        if hooks != nil {
            // VLCKit 経路: 進み具合の見張りは 0.5 秒ごとのタイマーで行う。
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateProgress()
            }
        } else if let player {
            // 映像の層は呼び出し元のものをそのまま借りる。同じプレイヤーに
            // 層を2つ作ると映像が出るのはどちらか1つだけになり、全画面側が
            // 真っ暗になる (実機確認済み)。層を映像の枠へ載せるのは
            // attachBorrowedViews で行う (addSublayer で前の親 (通常画面)
            // からは自動で外れる)。
            let layer = sharedPlayerLayer ?? AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            layer.frame = videoView.bounds
            playerLayer = layer

            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                queue: .main
            ) { [weak self] _ in
                self?.updateProgress()
            }
        }
        updateProgress()
        scheduleHideControls()
    }

    /// 映像と重ね物を、呼び出し元から借りてこちらへ付け替える。
    /// 開く動きが終わってから (viewDidAppear) 行う。以前は開く前と
    /// 切り替わりの先頭で行っていて、VLC が描いている最中の映像の枠や
    /// 重ね物の付け替えが画面側の処理を止め、切り替わりごと固まって
    /// いた (実機では、閉じるボタンが押されたままの見た目で固まり、
    /// 映像だけ流れ続ける症状が出ていた)。動きの間は映像の枠が
    /// 空になるが、操作は止まらない方を優先する。
    private func attachBorrowedViews() {
        guard !borrowedViewsAttached else { return }
        borrowedViewsAttached = true
        // VLCKit 経路: 映像の枠をこちらへ貸し出してもらう
        // (生放送の全画面と同じ作り)。
        hooks?.attachVideo(videoView)
        // AVPlayer 経路: 借りた映像の層を映像の枠へ載せる。
        if let playerLayer {
            playerLayer.frame = videoView.bounds
            videoView.layer.addSublayer(playerLayer)
        }
        // コメントの重ね物を借りている場合は、映像の上・操作類の下に重ねる
        // (流れる表示の更新は呼び出し元が続ける)。
        if let commentView = borrowedCommentView {
            commentView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(commentView, aboveSubview: videoView)
            commentBorrowConstraints = [
                commentView.topAnchor.constraint(equalTo: view.topAnchor),
                commentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                commentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                commentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ]
            NSLayoutConstraint.activate(commentBorrowConstraints)
        }
        // 字幕の重ね物を借りている場合は、コメントの上・操作類の下に重ねる
        // (字幕の絵の更新は呼び出し元が続ける)。
        if let captionView = borrowedCaptionView {
            captionView.translatesAutoresizingMaskIntoConstraints = false
            if let commentView = borrowedCommentView {
                view.insertSubview(captionView, aboveSubview: commentView)
            } else {
                view.insertSubview(captionView, aboveSubview: videoView)
            }
            captionBorrowConstraints = [
                captionView.topAnchor.constraint(equalTo: view.topAnchor),
                captionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                captionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                captionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ]
            NSLayoutConstraint.activate(captionBorrowConstraints)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 映像と重ね物の付け替えは、開く動きが終わってから行う
        // (attachBorrowedViews のコメント参照)。
        attachBorrowedViews()
        // 横向きへの回転を明示的に促す (iOS 16 以降の作法)。
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideTimer?.invalidate()
        hideTimer = nil
        fastSeekBackController.invalidate()
        fastSeekForwardController.invalidate()
        progressTimer?.invalidate()
        progressTimer = nil
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        // 借りた映像と重ね物を返すのは、閉じる動きが終わってから
        // viewDidDisappear で行う (下のコメント参照)。
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 借りた映像と重ね物は、閉じる動きが終わってから呼び出し元へ
        // 返す。以前は viewWillDisappear (切り替わりの先頭) で返して
        // いて、付け替えが画面側の処理を止め、閉じるボタンが押された
        // ままの見た目で固まっていた。動きの間は通常画面側の映像が
        // 戻っていないが、操作が止まらない方を優先する。
        guard borrowedViewsAttached else { return }
        borrowedViewsAttached = false
        // VLCKit 経路: 貸し出してもらった映像の枠を呼び出し元へ返す。
        hooks?.detachVideo()
        // AVPlayer 経路: 借りた映像の層を呼び出し元へ返す
        // (通常画面で映像が戻るように)。
        if let sharedPlayerLayer, let onReturnPlayerLayer {
            sharedPlayerLayer.removeFromSuperlayer()
            onReturnPlayerLayer(sharedPlayerLayer)
        }
        // 字幕の重ね物を呼び出し元へ返す (通常画面で字幕が戻るように)。
        if let captionView = borrowedCaptionView {
            NSLayoutConstraint.deactivate(captionBorrowConstraints)
            captionBorrowConstraints = []
            captionView.removeFromSuperview()
            onReturnCaptionView?()
        }
        // コメントの重ね物を呼び出し元へ返す (通常画面でコメントが戻るように)。
        if let commentView = borrowedCommentView {
            NSLayoutConstraint.deactivate(commentBorrowConstraints)
            commentBorrowConstraints = []
            commentView.removeFromSuperview()
            onReturnCommentView?()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoView.bounds
        bandView.setNeedsDisplay()
    }

    // MARK: - 画面構成

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

        titleLabel.text = program.title
        titleLabel.textColor = .white
        titleLabel.font = .scaledSystemFont(ofSize: 16, weight: .bold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)

        topGradient.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topGradient)

        topBar.axis = .horizontal
        topBar.spacing = 12
        topBar.alignment = .center
        topBar.addArrangedSubview(exitButton)
        topBar.addArrangedSubview(titleLabel)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        // 真ん中の並びの絵の大きさと当たり判定は、通常画面とそろえる
        // (絵は再生/一時停止 40、少し戻る/少し進む 30、場面移動 26。
        // 当たり判定は再生/一時停止 64x64、それ以外 52x52)。
        configure(playPauseButton, symbol: "pause.fill", pointSize: 40, action: #selector(togglePlayPause))
        // スキップ秒数とボタンの数字は、設定値に合わせる (再生画面と同じ)。
        let store = SettingsStore.shared
        configure(skipBackButton, symbol: "gobackward.\(store.seekBackwardSeconds)", pointSize: 30, action: #selector(skipBack))
        configure(skipForwardButton, symbol: "goforward.\(store.seekForwardSeconds)", pointSize: 30, action: #selector(skipForward))
        configure(prevChapterButton, symbol: "backward.end.fill", pointSize: 26, action: #selector(prevChapter))
        configure(nextChapterButton, symbol: "forward.end.fill", pointSize: 26, action: #selector(nextChapter))
        for button in [playPauseButton, skipBackButton, skipForwardButton, prevChapterButton, nextChapterButton] {
            button.tintColor = .white
            let hitSize: CGFloat = button === playPauseButton ? 64 : 52
            button.widthAnchor.constraint(equalToConstant: hitSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: hitSize).isActive = true
        }
        let hasChapters = !program.chapterBoundaries.isEmpty
        prevChapterButton.isEnabled = hasChapters
        nextChapterButton.isEnabled = hasChapters
        prevChapterButton.alpha = hasChapters ? 1 : 0.35
        nextChapterButton.alpha = hasChapters ? 1 : 0.35

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
        durationLabel.text = TimeFormat.hms(program.duration)
        for label in [currentTimeLabel, durationLabel] {
            label.textColor = AppPalette.text
            label.font = .scaledMonospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.setTitleColor(AppPalette.text, for: .normal)
        qualityButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        qualityButton.showsMenuAsPrimaryAction = true
        qualityButton.menu = makeQualityMenu()

        // 画質プロファイルの手動切り替え (再生画面の情報欄にあるのと同じ)。
        profileButton.setTitleColor(AppPalette.text, for: .normal)
        profileButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        profileButton.addTarget(self, action: #selector(toggleProfile), for: .touchUpInside)
        updateProfileButtonTitle()

        // 盛り上がりの波形の帯は、シークバーの真上に置く (通常画面と
        // 同じ置き場所)。材料が渡るまでは隠しておく (材料が先に
        // 渡っている場合は、その状態を引き継ぐ)。
        excitementStrip.heightAnchor.constraint(equalToConstant: 26).isActive = true
        excitementStrip.isHidden =
            !(hasExcitementData && SettingsStore.shared.showExcitementInFullscreen)
        excitementStrip.onTapped = { [weak self] ratio in
            guard let self else { return }
            self.seek(to: ratio * self.effectiveDuration)
            self.resumePlayback()
            self.setControlsVisible(true)
            self.scheduleHideControls()
        }

        let seekRow = UIStackView(arrangedSubviews: [currentTimeLabel, seekContainer, durationLabel])
        seekRow.axis = .horizontal
        seekRow.spacing = 10
        seekRow.alignment = .center

        // 操作の5つは下のパネルから出し、画面の真ん中に置く
        // (本家 Web 版の中央の並びと同じ顔ぶれと置き場所)。
        centerControls.addArrangedSubview(prevChapterButton)
        centerControls.addArrangedSubview(skipBackButton)
        centerControls.addArrangedSubview(playPauseButton)
        centerControls.addArrangedSubview(skipForwardButton)
        centerControls.addArrangedSubview(nextChapterButton)
        centerControls.axis = .horizontal
        centerControls.spacing = 28
        centerControls.alignment = .center
        centerControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(centerControls)

        let optionsRow = UIStackView(arrangedSubviews: [qualityButton, profileButton, UIView()])
        optionsRow.spacing = 16
        optionsRow.axis = .horizontal

        let panelStack = UIStackView(arrangedSubviews: [excitementStrip, seekRow, optionsRow])
        panelStack.axis = .vertical
        panelStack.spacing = 10
        panelStack.translatesAutoresizingMaskIntoConstraints = false

        // 下部の帯は、角丸の浮いたパネルをやめて画面幅いっぱいのグラデーションにする
        // (Web 版の操作帯と同じ形)。
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.isUserInteractionEnabled = true
        bottomPanel.addSubview(panelStack)
        view.addSubview(bottomPanel)

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
            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            centerControls.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerControls.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            panelStack.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 18),
            panelStack.bottomAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            panelStack.leadingAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            panelStack.trailingAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func configure(_ button: UIButton, symbol: String, pointSize: CGFloat, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeQualityMenu() -> UIMenu {
        // 選択肢の表示は設定画面と同じく、データ量と平均ビットレート付き。
        // 数値は現在の区分 (録画=ビデオ) の通信節約モードの有無で切り替わる。
        let dataSaver = SettingsStore.shared.dataSaverMode(
            media: .video, profile: isCellularProfile ? .cellular : .wifi)
        return UIMenu(children: SettingsStore.qualities.map { q in
            UIAction(title: SettingsStore.qualityDisplayName(q, dataSaverMode: dataSaver),
                     state: q == quality ? .on : .off) { [weak self] _ in
                guard let self, q != self.quality else { return }
                self.quality = q
                self.qualityButton.setTitle("画質: \(q)", for: .normal)
                self.qualityButton.menu = self.makeQualityMenu()
                self.onQualitySelected?(q)
                self.scheduleHideControls()
            }
        })
    }

    private func updateProfileButtonTitle() {
        profileButton.setTitle(
            isCellularProfile ? "モバイル回線向け画質: ON" : "モバイル回線向け画質: OFF",
            for: .normal)
    }

    /// プロファイルの切り替え。実際の切り替え (再生の作り直し) は呼び出し元が
    /// 行い、画質も切り替え後の区分の既定に変わる。こちらの画質表示は、
    /// 呼び出し元が返した「実際に使われる画質」に合わせる (音声のみ再生中
    /// など、表示と実態がずれうる場合でも呼び出し元が正になる)。
    @objc private func toggleProfile() {
        isCellularProfile.toggle()
        updateProfileButtonTitle()
        if let newQuality = onProfileSelected?(isCellularProfile) {
            quality = newQuality
            qualityButton.setTitle("画質: \(newQuality)", for: .normal)
            qualityButton.menu = makeQualityMenu()
        }
        scheduleHideControls()
    }

    // MARK: - 操作類の出し入れ

    @objc private func toggleControls() {
        setControlsVisible(!controlsVisible)
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        UIView.animate(withDuration: 0.25) {
            self.topBar.alpha = visible ? 1 : 0
            self.topGradient.alpha = visible ? 1 : 0
            self.bottomPanel.alpha = visible ? 1 : 0
            self.centerControls.alpha = visible ? 1 : 0
        }
        topBar.isUserInteractionEnabled = visible
        bottomPanel.isUserInteractionEnabled = visible
        centerControls.isUserInteractionEnabled = visible
        setNeedsStatusBarAppearanceUpdate()
        if !visible {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    /// 再生中だけ、しばらく触らなければ操作類を消すタイマーを仕掛け直す。
    private func scheduleHideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard isPlayingNow else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.setControlsVisible(false)
        }
    }

    // MARK: - 盛り上がりの波形

    /// 盛り上がりの波形の材料を呼び出し元 (再生画面) から受け取る。
    /// 通常画面の帯と同じ材料で、密度が空でないときにだけ帯を出す。
    /// 設定「全画面でも盛り上がり波形を表示する」がオフのときは
    /// 材料があっても出さない。
    func setExcitement(densities: [Double], segments: [HighlightSegment], duration: Double) {
        excitementStrip.densities = densities
        excitementStrip.segments = segments
        excitementStrip.duration = duration
        hasExcitementData = !densities.isEmpty
        excitementStrip.isHidden =
            !(hasExcitementData && SettingsStore.shared.showExcitementInFullscreen)
    }

    // MARK: - 進み具合の表示

    /// 現在の再生位置 (秒)。再生の仕組みによらない読み取り口。
    private var currentSeconds: Double {
        if let hooks { return hooks.currentTime() }
        return player?.currentTime().seconds ?? 0
    }

    /// いま再生中かどうか。
    private var isPlayingNow: Bool {
        if let hooks { return hooks.isPlaying() }
        return (player?.rate ?? 0) != 0
    }

    /// 再生側が読み取った全体の長さ (秒)。定まらないときは NaN。
    private var itemDurationSeconds: Double {
        if let hooks { return hooks.itemDuration() }
        return player?.currentItem?.duration.seconds ?? .nan
    }

    private var effectiveDuration: Double {
        let d = itemDurationSeconds
        if d.isFinite, d > 0 {
            return d
        }
        return program.duration
    }

    private func updateProgress() {
        // 移動の確定直後は、再生部品の実位置がまだ飛び先へ移っていない
        // ことがある。その間は表示だけ飛び先に合わせる (呼び出し元が
        // 表示用の位置を用意していれば、それを使う。通常画面と同じ直し)。
        let current = hooks?.displayTime?() ?? currentSeconds
        if current.isFinite {
            currentTimeLabel.text = TimeFormat.hms(current)
            if !isScrubbing {
                let duration = effectiveDuration
                seekSlider.value = duration > 0 ? Float(current / duration) : 0
            }
        }
        let duration = effectiveDuration
        let itemDuration = itemDurationSeconds
        durationLabel.text = program.isRecording && !itemDuration.isFinite
            ? "録画中"
            : TimeFormat.hms(duration)
        bandView.duration = duration
        bandView.setNeedsDisplay()
        updatePlayPauseIcon()
    }

    private func updatePlayPauseIcon() {
        let playing = isPlayingNow
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        playPauseButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill", withConfiguration: config),
            for: .normal
        )
    }

    // MARK: - 長押しの高速シーク (拡張版)

    /// 送り・戻しボタンへ長押しの高速シークを取り付ける。
    /// 移動と音の操作は、再生の仕組みごとに既存の操作口へ委ねる
    /// (VLCKit 経路は受け渡し口、AVPlayer 経路は共有プレイヤー)。
    private func setupFastSeek() {
        fastSeekBackController.attach(to: skipBackButton)
        fastSeekForwardController.attach(to: skipForwardButton)
        // 消音は持ち主へ一元化する (送り・戻しが同時に進んでも、
        // 最後の1つが終わるまで音は戻らない)。
        fastSeekMuteKeeper.isMutedProvider = { [weak self] in self?.isMutedNow ?? false }
        fastSeekMuteKeeper.setMutedHandler = { [weak self] muted in self?.setMutedNow(muted) }
        for controller in [fastSeekBackController, fastSeekForwardController] {
            controller.muteKeeper = fastSeekMuteKeeper
            controller.positionProvider = { [weak self] in self?.currentSeconds ?? 0 }
            controller.seekHandler = { [weak self] position in self?.seek(to: position) }
            controller.isMutedProvider = { [weak self] in self?.isMutedNow ?? false }
            controller.setMutedHandler = { [weak self] muted in self?.setMutedNow(muted) }
            controller.onKeepControlsVisible = { [weak self] in
                guard let self else { return }
                self.hideTimer?.invalidate()
                self.hideTimer = nil
                self.setControlsVisible(true)
            }
            controller.onEnd = { [weak self] in self?.scheduleHideControls() }
        }
    }

    /// いま音が消えているかどうか。
    private var isMutedNow: Bool {
        if let hooks { return hooks.isMuted() }
        return player?.isMuted ?? false
    }

    /// 音を消す・戻す。
    private func setMutedNow(_ muted: Bool) {
        if let hooks {
            hooks.setMuted(muted)
            return
        }
        player?.isMuted = muted
    }

    // MARK: - 操作

    @objc private func exitFullscreen() {
        let presenter = presentingViewController
        dismiss(animated: true) {
            // 入るときの横向きへの要求 (requestGeometryUpdate) は閉じただけでは
            // 戻らないため、閉じ終わったあとに向きの戻しを明示的に行う。
            presenter?.restoreOrientationAfterFullscreen()
        }
    }

    @objc private func togglePlayPause() {
        if isPlayingNow {
            pausePlayback()
        } else {
            resumePlayback()
        }
        updatePlayPauseIcon()
        scheduleHideControls()
    }

    /// 再生を止める。VLCKit 経路では呼び出し元へ委ねる。
    private func pausePlayback() {
        if let hooks {
            hooks.pause()
            return
        }
        player?.pause()
    }

    /// 設定されている再生速度で再生を再開する (再生画面と同じ速度で揃える)。
    /// VLCKit 経路では、速度の適用まで含めて呼び出し元へ委ねる。
    private func resumePlayback() {
        if let hooks {
            hooks.play()
            return
        }
        guard let player else { return }
        player.play()
        let rate = SettingsStore.shared.playbackRate
        if rate != 1 {
            player.rate = Float(rate)
        }
    }

    private func seek(to seconds: Double) {
        // VLCKit 経路では、移動の実行と CM自動スキップの判定の基準位置の
        // 更新を呼び出し元へ委ねる (呼び出し元の移動と同じ扱いにするため)。
        if let hooks {
            hooks.seek(seconds)
            return
        }
        guard let player else { return }
        let clamped = max(0, min(seconds, effectiveDuration))
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        )
    }

    @objc private func skipBack() {
        seek(to: currentSeconds - Double(SettingsStore.shared.seekBackwardSeconds))
        scheduleHideControls()
    }

    @objc private func skipForward() {
        seek(to: currentSeconds + Double(SettingsStore.shared.seekForwardSeconds))
        scheduleHideControls()
    }

    @objc private func prevChapter() {
        let current = currentSeconds
        let target = program.chapterBoundaries.filter { $0 < current - 1.0 }.last ?? 0
        seek(to: target)
        scheduleHideControls()
    }

    @objc private func nextChapter() {
        let current = currentSeconds
        if let target = program.chapterBoundaries.first(where: { $0 > current + 0.5 }) {
            seek(to: target)
        }
        scheduleHideControls()
    }

    @objc private func scrubBegan() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlayingNow
        pausePlayback()
        hideTimer?.invalidate()
        hideTimer = nil
    }

    @objc private func scrubChanged() {
        let target = Double(seekSlider.value) * effectiveDuration
        currentTimeLabel.text = TimeFormat.hms(target)
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        let target = Double(seekSlider.value) * effectiveDuration
        seek(to: target)
        if wasPlayingBeforeScrub {
            resumePlayback()
        }
        scheduleHideControls()
    }
}

extension UIViewController {
    /// 横向き固定のフルスクリーンを閉じたあと、向きを端末の向きへ戻す。
    /// 入るときの横向きへの要求 (requestGeometryUpdate) はシーン側に残り続け、
    /// 閉じただけでは誰も戻しを要求しないため、アプリ全体が横向きのままになる。
    /// そこで、閉じ終わったあとの画面側で、許可する向きの再評価と、
    /// 現在の端末の向きに合った向きの要求を行う。
    func restoreOrientationAfterFullscreen() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        // 端末の向きと画面の向きは、横向きでは左右が逆に対応する。
        // それ以外 (縦・うつ伏せ等) は縦へ戻す。
        let mask: UIInterfaceOrientationMask
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            mask = .landscapeRight
        case .landscapeRight:
            mask = .landscapeLeft
        default:
            mask = .portrait
        }
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
