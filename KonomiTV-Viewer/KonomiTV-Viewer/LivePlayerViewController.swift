import UIKit

#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// 生放送の再生画面。サーバーは MPEG-TS の流しっぱなし形式しか出していないため、
/// AVPlayer ではなく VLCKit (MobileVLCKit) で再生する。
/// MobileVLCKit が組み込まれていないビルドでは、その旨を表示するだけになる。
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

#if canImport(MobileVLCKit)
    private var vlcPlayer: VLCMediaPlayer?
#endif
    private var nowPlayingBegun = false
    /// 開始の見張り (録画側と同じ作り)。再生が始まったら止める。
    private var startWatchdog: Timer?
    private var didStartPlaying = false

    // MARK: - データ放送 (重ね合わせの検証、拡張版だけ)
    /// 情報欄の「リモコン」ボタン (浮き出るパネルを出す)。
    private let remoteButton = RippleButton()
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
    /// リモコンのパネル (Web 版と同じ浮き出る形) と、その後ろの幕。
    private var remoteBackdrop: UIView?
    private var remotePanel: UIView?
    private var remoteSpinner: UIActivityIndicatorView?
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
        view.backgroundColor = AppPalette.background
        buildLayout()
        startStream()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 題名の出し方だけ Web 版ヘッダー (14px 太字・テーマの文字色) に合わせる。
        // 戻る操作と題名の置き場所は、今までのナビゲーションバーのまま (録画再生と同じ判断)。
        let bar = navigationController?.navigationBar
        bar?.tintColor = AppPalette.text
        bar?.titleTextAttributes = [
            .font: UIFont.scaledSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: AppPalette.text,
        ]
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // ナビゲーションバーの見た目を標準へ戻す (この画面の間だけ変えているため)。
        let bar = navigationController?.navigationBar
        bar?.tintColor = nil
        bar?.titleTextAttributes = nil
        hideTimer?.invalidate()
        hideTimer = nil
        // フルスクリーン表示で覆われただけのときは再生を止めない。
        // それ以外で画面を離れるときは今までどおり止める。
#if canImport(MobileVLCKit)
        if presentedViewController is LiveFullscreenViewController {
            return
        }
#endif
        remoteBackdrop?.isHidden = true
        remotePanel?.isHidden = true
        stopDataBroadcast()
        stopStream()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 映像の高さ: 幅なりの 16:9 が情報欄の最低限 (120pt) を残して収まるならそのまま、
        // 収まらない (主に横向き) なら収まる高さまで縮める。
        // 映像は VLC 側で全体が収まるように描かれるため、切れることはない。
        if let heightConstraint = videoHeightConstraint {
            let ideal = view.bounds.width * 9.0 / 16.0
            let available = view.bounds.height
                - view.safeAreaInsets.top
                - view.safeAreaInsets.bottom
                - 120
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

        // 操作帯には、放送中の番組の時刻だけを置く
        // (Web 版の操作帯の左側の並びに相当)。
        liveTimeLabel.text = channel.program_present.map { programTimeText($0) } ?? ""
        liveTimeLabel.textColor = AppPalette.text
        liveTimeLabel.font = .scaledSystemFont(ofSize: 13, weight: .medium)
        let controlsRow = UIStackView(arrangedSubviews: [liveTimeLabel, UIView()])
        controlsRow.axis = .horizontal
        controlsRow.spacing = 10
        controlsRow.alignment = .center
        controlsRow.translatesAutoresizingMaskIntoConstraints = false

        bottomGradient.translatesAutoresizingMaskIntoConstraints = false
        videoArea.addSubview(bottomGradient)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsRow)
        videoArea.addSubview(controlsContainer)
        // 真ん中の再生・一時停止は操作帯より上に置く (映像が低いときでも
        // 帯に触れて押せなくならないように)。
        videoArea.addSubview(playPauseButton)

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
        fullscreenButton.setTitle("全画面", for: .normal)
        fullscreenButton.addTarget(self, action: #selector(showFullscreen), for: .touchUpInside)
        for button in [qualityButton, profileButton, audioOnlyButton, fullscreenButton] {
            stylePlayerChip(button)
        }
        let chipsRow = UIStackView(arrangedSubviews: [qualityButton, audioOnlyButton, fullscreenButton])
        chipsRow.axis = .horizontal
        chipsRow.spacing = 8
        let chipsRow2 = UIStackView(arrangedSubviews: [profileButton, UIView()])
        chipsRow2.axis = .horizontal
        chipsRow2.spacing = 8

        // データ放送の重ね合わせ (検証用、拡張版だけ)。入り口は情報欄の
        // 「リモコン」ボタンで、押すと Web 版と同じ浮き出るパネル型の
        // リモコンが出る。データ放送の開始はパネルの「データ」ボタン
        // から行う (テレビで dボタンを押して開くのと同じ入り口)。
        // パネル本体は buildRemotePanel() で画面全体の上に作る。
        if AppEdition.isHousehold {
            remoteButton.setTitle("リモコン", for: .normal)
            remoteButton.addTarget(self, action: #selector(showRemotePanel), for: .touchUpInside)
            stylePlayerChip(remoteButton)
        }
        let chipsRow3 = UIStackView(arrangedSubviews: [remoteButton, UIView()])
        chipsRow3.axis = .horizontal
        chipsRow3.spacing = 8

        let infoStack = UIStackView(arrangedSubviews: [
            messageLabel, broadcasterRow, infoTitleLabel, infoTimeLabel, descriptionLabel,
            statusLabel, nextHeaderLabel, nextTitleLabel, nextTimeLabel, chipsRow, chipsRow2,
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
        if AppEdition.isHousehold {
            infoStack.addArrangedSubview(chipsRow3)
        }
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
            controlsContainer.heightAnchor.constraint(equalToConstant: 64),
            controlsRow.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 16),
            controlsRow.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -16),
            controlsRow.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.centerXAnchor.constraint(equalTo: videoArea.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: videoArea.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 64),
            playPauseButton.heightAnchor.constraint(equalToConstant: 64),
            scrollView.topAnchor.constraint(equalTo: videoArea.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            infoStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            infoStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            infoStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            infoStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // リモコンのパネルは画面全体の上に浮かせるため、最後に足す
        // (拡張版だけ)。
        if AppEdition.isHousehold {
            buildRemotePanel()
        }
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
            self.bottomGradient.alpha = visible ? 1 : 0
            self.controlsContainer.alpha = visible ? 1 : 0
            self.playPauseButton.alpha = visible ? 1 : 0
        }
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
#if canImport(MobileVLCKit)
        guard vlcPlayer?.isPlaying ?? false else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.setControlsVisible(false)
        }
#endif
    }

    private func startStream() {
#if canImport(MobileVLCKit)
        guard let url = APIClient.shared.liveStreamURL(
            displayChannelID: channel.display_channel_id,
            quality: quality,
            profile: profile
        ) else {
            messageLabel.text = "接続先が設定されていません。"
            return
        }
        stopStream()
        let player = VLCMediaPlayer()
        player.delegate = self
        player.drawable = videoView
        // 渡す URL は、アプリ内の中継 (StreamRelayServer) 経由にする。
        // VLCKit には再生の取りに行く処理へ任意のヘッダーを付ける公式の
        // 入口が無く、Cloudflare Access の合言葉が届かないため、外回線
        // では開始すらできない (0.25 で実機確認済み。録画の H.265 と
        // 同じ弱点で、直し方も同じ)。中継が合言葉付きで取りに行き、
        // 届いた分からそのまま流す。中継が使えないときは元の URL に
        // 落ちる。録画側の扱いに揃え、接続先が内・外どちらでも中継を
        // 通す (合言葉が未設定なら、中継は素通しになる)。
        let media = VLCMedia(url: StreamRelayServer.shared.relayURL(for: url) ?? url)
        // 受け取りの溜め (ネットワークキャッシュ) の量で、低遅延の設定を
        // 近づける。Web 版の低遅延は再生バッファを 0.9 秒 / 通常 4.0 秒に
        // 切り替える仕組みで、VLCKit には同じ仕組みが無いため、受け取りの
        // 溜めを 低遅延オン = 1000ms / オフ = 4000ms に切り替えて近づける。
        // 効き具合 (遅れの減り方と止まりやすさ) は実機確認が要る。
        let networkCaching = SettingsStore.shared.lowLatencyMode(profile: profile) ? 1000 : 4000
        media.addOption(":network-caching=\(networkCaching)")
        if audioOnly {
            media.addOption(":no-video")
        }
        // Cloudflare Access のサービストークンをヘッダーとして付ける
        // (中継を使わない場合の補い。単独では届かないことが分かっている)。
        for (key, value) in SettingsStore.shared.cfAccessHeaders {
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
#else
        messageLabel.text = "このビルドには生放送の再生部品 (VLCKit) が組み込まれていません。"
#endif
    }

    private func stopStream() {
        startWatchdog?.invalidate()
        startWatchdog = nil
#if canImport(MobileVLCKit)
        vlcPlayer?.stop()
        vlcPlayer = nil
#endif
        if nowPlayingBegun {
            NowPlayingManager.shared.end(owner: self)
            nowPlayingBegun = false
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
                seekTo: nil
            ))
            nowPlayingBegun = true
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard nowPlayingBegun else { return }
        let playing: Bool = {
#if canImport(MobileVLCKit)
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
#if canImport(MobileVLCKit)
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
#if canImport(MobileVLCKit)
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
#if canImport(MobileVLCKit)
        guard let player = vlcPlayer else { return }
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
        guard newProfile != profile else { return }
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
        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
        messageLabel.text = newProfile == .cellular
            ? "モバイル回線向けの画質プロファイルに切り替えました。"
            : "Wi-Fi 回線向けの画質プロファイルに切り替えました。"
    }

    /// 画質の切り替え: VLC の読み込み先を新しい画質の流れに替えて再生し直す。
    /// 音声のみの最中でも、映像を止めたまま切り替わる (startStream が状態を見て付ける)。
    private func switchQuality(_ newQuality: String) {
        guard newQuality != quality else { return }
        quality = newQuality
        qualityButton.setTitle("画質: \(quality)", for: .normal)
        qualityButton.menu = makeQualityMenu()
        startStream()
        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
    }

    /// 音声のみ: 映像の通り道を止めて繋ぎ直す (通信量も減る)。
    @objc private func toggleAudioOnly() {
        audioOnly.toggle()
        audioOnlyButton.setTitle(audioOnly ? "音声のみ: ON" : "音声のみ: OFF", for: .normal)
        videoView.isHidden = audioOnly
        startStream()
        playPauseButton.setImage(
            UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)),
            for: .normal
        )
    }

    // MARK: - データ放送 (重ね合わせの検証、拡張版だけ)

    /// リモコンのパネルを作る (Web 版の Remocon.vue と同じ顔ぶれ)。
    /// 画面全体にかぶさる幕+中央のパネルで、十字キーは円形、操作キーと
    /// 数字キーの送る合図 (ARIB のキーコード) は Web 版と同一。
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
        // パネルの高さは Web 版と同じ 514pt を目安にし、画面が低い
        // ときは画面に収まる高さまで縮める (中身は滑らせて見せる)。
        let panelHeight = panel.heightAnchor.constraint(equalToConstant: 514)
        panelHeight.priority = .defaultHigh
        panelHeight.isActive = true
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant: 234),
            panel.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
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
        updateRemotePanelState()
    }

    /// リモコンのパネルを出す。データ放送が始まっていなくても出せる
    /// (開始はパネルの「データ」ボタンから行うため)。
    @objc private func showRemotePanel() {
        guard let backdrop = remoteBackdrop, let panel = remotePanel else { return }
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
        if loading {
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
        overlay.onStatus = { [weak self] status in
            self?.handleDataBroadcastStatus(status)
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
        isDataBroadcastActive = true
        dataBroadcastLoaded = false
        dataBroadcastStartFailed = false
        overlay.start(psiURL: psiURL, serviceID: channel.service_id)
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
        updateRemotePanelState()
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
        case "error":
            messageLabel.text = "データ放送を開始できませんでした。"
            showingDataBroadcastStatus = true
            pendingDataKey = false
            if !dataBroadcastLoaded {
                dataBroadcastStartFailed = true
            }
        default:
            break
        }
        updateRemotePanelState()
    }

    /// フルスクリーン表示へ移る。映像の枠ごと全画面側へ貸し出すだけで、
    /// 受信そのものは止めない。
    @objc private func showFullscreen() {
#if canImport(MobileVLCKit)
        guard vlcPlayer != nil else { return }
        let fullscreen = LiveFullscreenViewController(channelName: channel.name)
        fullscreen.onWillAppear = { [weak self] fullscreenVideoView in
            self?.borrowVideoView(into: fullscreenVideoView)
        }
        fullscreen.onWillDisappear = { [weak self] in
            guard let self else { return }
            self.returnVideoView()
            self.refreshPlayPauseIcon()
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
    }

    private func refreshPlayPauseIcon() {
#if canImport(MobileVLCKit)
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

#if canImport(MobileVLCKit)
extension LivePlayerViewController: VLCMediaPlayerDelegate {
    /// VLC 側の状態変化 (再生開始・停止・終了など) に、画面内のボタンと
    /// ロック画面の表示を追随させる。
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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

    private let videoView = UIView()
    /// 上部の帯のグラデーション (Web 版ヘッダーと同じ、黒から透明へ)。
    private let topGradient = GradientView(direction: .top)
    private let topBar = UIStackView()
    private let nameLabel = UILabel()
    private let exitButton = RippleButton()
    private let playPauseButton = RippleButton()
    private var controlsVisible = true
    private var hideTimer: Timer?

    init(channelName: String) {
        self.channelName = channelName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        ])
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
            self.topBar.alpha = visible ? 1 : 0
            self.topGradient.alpha = visible ? 1 : 0
            self.playPauseButton.alpha = visible ? 1 : 0
        }
        topBar.isUserInteractionEnabled = visible
        playPauseButton.isUserInteractionEnabled = visible
        setNeedsStatusBarAppearanceUpdate()
        if !visible {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    private func scheduleHideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard isPlayingProvider?() ?? false else { return }
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
