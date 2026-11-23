import UIKit

/// 予約の状態の文と色 (Web 版の予約カードの状態表示と同じ)。
/// 予約一覧のカードと番組詳細の両方で使う。
enum ReservationStatusDisplay {
    static func text(isRecording: Bool, availability: String) -> String {
        if isRecording { return "録画中" }
        switch availability {
        case "Full": return "録画可能"
        case "Partial": return "一部のみ録画可能"
        default: return "チューナー不足"
        }
    }

    static func color(isRecording: Bool, availability: String) -> UIColor {
        if isRecording { return AppPalette.accent }
        switch availability {
        case "Full": return UIColor(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255, alpha: 1)
        case "Partial": return AppPalette.warning
        default: return UIColor(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255, alpha: 1)
        }
    }

    /// 容量の目安の文 (Web 版の「約 1.2 GB」形式)。
    static func sizeText(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "約 " + formatter.string(fromByteCount: Int64(bytes))
    }
}

/// 番組の詳細画面。番組表で番組を押したときと、予約一覧で予約を押したときの
/// 両方から開く (Web 版の予約詳細の引き出しにあたる画面)。
/// 中身は Web 版の番組情報の並び: 題名 → 局と時刻 → 説明 → ジャンル →
/// 映像・音声 → 詳細情報の節ごと。
/// 予約が無い番組では「予約を追加」、予約済みでは有効/無効の切り替えと
/// 「予約を削除」を出す。録画設定そのものの編集はこの画面では行わない。
final class ReservationDetailViewController: UIViewController {

    /// 追加・切り替え・削除が成功したときに、開いた側 (番組表・予約一覧) へ知らせる。
    var onChanged: (() -> Void)?
    /// 「視聴」が押されたときに、開いた側へ生放送の再生画面への
    /// 移り方を委ねる (番組表から開いた場合は番組表を閉じる必要があるため)。
    /// 未設定の場合は、この画面が属するナビゲーションへそのまま積む。
    var onWatchRequested: ((LiveChannel) -> Void)?

    private var program: TimeTableProgram
    private var channel: ChannelInfo
    /// 生放送の再生に使うチャンネル情報。番組のチャンネルと一致するものを
    /// チャンネル一覧から探して持つ。取れなければ「視聴」は出さない。
    private var liveChannel: LiveChannel?
    /// 予約の本体。nil は「予約が無い番組」として開かれた状態。
    /// 番組表から予約済みの番組を開いた場合は、予約の番号だけを先に持ち、
    /// 画面を開いたあとで本体を取り直す。
    private var reservation: Reservation?
    private var reservationID: Int?
    /// 土台が EDCB かどうか。nil はまだ分からない状態。
    private var backendIsEDCB: Bool?
    /// 予約本体の取り直しに失敗したかどうか。
    private var reservationLoadFailed = false
    private var isWorking = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    /// 画面の下端に固定する操作ボタンの帯 (Web 版の引き出しの下端の帯と同じ)。
    /// 中のボタンは rebuildActions で状態に合わせて作り直す。
    private let actionsBar = UIView()
    private let actionsStack = UIStackView()
    /// スクロール範囲の下端の決まり。帯が出ているときは帯の上端に、
    /// 帯が無いときは画面の下端に付ける (2本を持って切り替える)。
    private var scrollBottomToBarConstraint: NSLayoutConstraint?
    private var scrollBottomToViewConstraint: NSLayoutConstraint?
    private let logoView = UIImageView()
    private var logoSizeConstraintsConfigured = false
    private var toggle: WebToggle?
    private var watchButton: RippleButton?
    private var addButton: RippleButton?
    private var deleteButton: RippleButton?

    /// 予約一覧から開く場合。
    init(reservation: Reservation) {
        self.program = reservation.program
        self.channel = reservation.channel
        self.reservation = reservation
        self.reservationID = reservation.id
        super.init(nibName: nil, bundle: nil)
    }

    /// 番組表から開く場合。reservation は番組に付いてきた要約 (あれば)。
    init(program: TimeTableProgram, channel: ChannelInfo,
         reservationSummary: TimeTableProgramReservation?) {
        self.program = program
        self.channel = channel
        self.reservationID = reservationSummary?.id
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "番組詳細"
        view.backgroundColor = AppPalette.background

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // 操作ボタンの帯。Web 版の引き出しの下端と同じく、高さ 52、
        // 地は一段明るい面 (panel)、上端に 1px の線 (pressed)。
        // ボタンは右寄せの横並びで、帯の中身は rebuildActions が作る。
        actionsBar.backgroundColor = AppPalette.panel
        actionsBar.translatesAutoresizingMaskIntoConstraints = false
        actionsBar.isHidden = true
        view.addSubview(actionsBar)
        let actionsBarTopLine = UIView()
        actionsBarTopLine.backgroundColor = AppPalette.pressed
        actionsBarTopLine.translatesAutoresizingMaskIntoConstraints = false
        actionsBar.addSubview(actionsBarTopLine)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .center
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsBar.addSubview(actionsStack)
        NSLayoutConstraint.activate([
            actionsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionsBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionsBarTopLine.topAnchor.constraint(equalTo: actionsBar.topAnchor),
            actionsBarTopLine.leadingAnchor.constraint(equalTo: actionsBar.leadingAnchor),
            actionsBarTopLine.trailingAnchor.constraint(equalTo: actionsBar.trailingAnchor),
            actionsBarTopLine.heightAnchor.constraint(equalToConstant: 1),
            // 帯の高さはボタン (36) と上下の余白 (8 ずつ) で決まる 52 が基本。
            // ホームバーのある端末では、その分だけ帯が下へ伸びて
            // ボタンがホームバーに重ならないようにする。
            actionsStack.topAnchor.constraint(equalTo: actionsBar.topAnchor, constant: 8),
            actionsStack.bottomAnchor.constraint(equalTo: actionsBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionsStack.trailingAnchor.constraint(equalTo: actionsBar.trailingAnchor, constant: -16),
            actionsStack.leadingAnchor.constraint(greaterThanOrEqualTo: actionsBar.leadingAnchor, constant: 16),
        ])
        scrollBottomToBarConstraint = scrollView.bottomAnchor.constraint(equalTo: actionsBar.topAnchor)
        scrollBottomToViewConstraint = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        scrollBottomToViewConstraint?.isActive = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        rebuildContent()
        loadLogo()
        loadBackendAndReservation()
    }

    // MARK: - 読み込み

    private func loadLogo() {
        let channelID = channel.display_channel_id
        Task { [weak self] in
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channelID),
                  let image = UIImage(data: data) else { return }
            self?.logoView.image = image
            self?.logoView.isHidden = false
        }
    }

    /// 土台の確認と、予約本体の取り直し (番組表から開いた場合) を行う。
    /// あわせて「視聴」用に、番組のチャンネルと一致する生放送の
    /// チャンネル情報をチャンネル一覧から探す。
    private func loadBackendAndReservation() {
        Task { [weak self] in
            guard let self else { return }
            async let backend = APIClient.shared.fetchServerBackend()
            async let channels = APIClient.shared.fetchChannels()
            if let reservationID = self.reservationID, self.reservation == nil {
                if let fetched = try? await APIClient.shared.fetchReservation(id: reservationID) {
                    self.reservation = fetched
                } else {
                    self.reservationLoadFailed = true
                }
            }
            self.backendIsEDCB = await backend == "EDCB"
            if let response = try? await channels {
                self.liveChannel = response.groups
                    .flatMap { $0.channels }
                    .first { $0.id == self.program.channel_id }
            }
            self.rebuildContent()
        }
    }

    /// いま放送中かどうか (開始時刻は含み、終了時刻は含まない。本家と同じ)。
    private var isOnAirNow: Bool {
        guard let start = program.startDate, let end = program.endDate else { return false }
        let now = Date()
        return start <= now && now < end
    }

    /// 「視聴」を出せるかどうか。放送中で、チャンネル情報が取れていて、
    /// 視聴できないことが明示されていない場合だけ (本家の条件と同じ)。
    private var canWatchNow: Bool {
        guard isOnAirNow, let liveChannel else { return false }
        return liveChannel.is_watchable != false
    }

    // MARK: - 中身の組み立て

    /// 状態 (予約の有無・土台) が変わるたびに中身を作り直す。
    private func rebuildContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        toggle = nil
        watchButton = nil
        addButton = nil
        deleteButton = nil

        let isPast = (program.endDate ?? .distantFuture) < Date()
        let isRecording = reservation?.is_recording_in_progress ?? false

        // 注意の帯。Web 版の番組情報の先頭に出るものと同じ文。
        if let reservation {
            if reservation.recording_availability == "Partial" {
                contentStack.addArrangedSubview(makeBanner(
                    text: "チューナー不足のため、この番組は一部のみ録画されます。優先度を上げるか、重複する録画予約を調整してください。",
                    color: AppPalette.warning))
            } else if reservation.recording_availability == "Unavailable" {
                contentStack.addArrangedSubview(makeBanner(
                    text: "チューナー不足のため、この番組は録画できません。優先度を上げるか、重複する録画予約を削除してください。",
                    color: UIColor(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255, alpha: 1)))
            }
        }
        if backendIsEDCB == false && !isPast {
            contentStack.addArrangedSubview(makeBanner(
                text: "録画予約機能は EDCB バックエンド選択時のみ利用できます。",
                color: AppPalette.accent))
        }

        // 題名。
        let titleLabel = UILabel()
        titleLabel.text = program.title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = AppPalette.text
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        // 局ロゴ + 「Ch: 番号 局名」と時刻。
        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.backgroundColor = AppPalette.placeholder
        logoView.layer.cornerRadius = 2
        logoView.isHidden = logoView.image == nil
        logoView.translatesAutoresizingMaskIntoConstraints = false
        if !logoSizeConstraintsConfigured {
            logoSizeConstraintsConfigured = true
            logoView.widthAnchor.constraint(equalToConstant: 40).isActive = true
            logoView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }

        let channelLabel = UILabel()
        let channelNumber = channel.channel_number.map { "Ch: \($0) " } ?? ""
        channelLabel.text = channelNumber + channel.name
        channelLabel.font = .systemFont(ofSize: 13)
        channelLabel.textColor = AppPalette.text
        channelLabel.numberOfLines = 1
        channelLabel.lineBreakMode = .byTruncatingTail

        let timeLabel = UILabel()
        timeLabel.text = TimeFormat.recordingTimeText(
            start: program.startDate, end: program.endDate, durationSeconds: program.duration)
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = AppPalette.metaText
        timeLabel.numberOfLines = 0

        let channelStack = UIStackView(arrangedSubviews: [channelLabel, timeLabel])
        channelStack.axis = .vertical
        channelStack.spacing = 2
        let broadcasterRow = UIStackView(arrangedSubviews: [logoView, channelStack])
        broadcasterRow.axis = .horizontal
        broadcasterRow.alignment = .center
        broadcasterRow.spacing = 10
        contentStack.addArrangedSubview(broadcasterRow)

        // 説明文。
        if let description = program.description, !description.isEmpty {
            let descriptionLabel = UILabel()
            descriptionLabel.text = description
            descriptionLabel.font = .systemFont(ofSize: 13)
            descriptionLabel.textColor = AppPalette.text
            descriptionLabel.numberOfLines = 0
            contentStack.addArrangedSubview(descriptionLabel)
        }

        // ジャンルの印。
        if let genres = program.genres, !genres.isEmpty {
            let chipRow = UIStackView()
            chipRow.axis = .horizontal
            chipRow.spacing = 6
            chipRow.alignment = .leading
            for genre in genres {
                let chip = BadgeLabel()
                chip.text = "\(genre.major) / \(genre.middle)"
                chip.font = .systemFont(ofSize: 11)
                chip.textColor = AppPalette.text
                chip.backgroundColor = AppPalette.panel
                chip.layer.cornerRadius = 4
                chip.clipsToBounds = true
                chip.textInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
                chip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                chipRow.addArrangedSubview(chip)
            }
            contentStack.addArrangedSubview(chipRow)
        }

        // 映像・音声の情報。
        var statusLines: [String] = []
        if let codec = program.video_codec, let resolution = program.video_resolution {
            statusLines.append("映像: \(codec) / \(resolution)")
        }
        if let audioType = program.primary_audio_type {
            var line = "主音声: \(audioType)"
            if let rate = program.primary_audio_sampling_rate { line += " \(rate)" }
            if let language = program.primary_audio_language { line += " / \(language)" }
            statusLines.append(line)
        }
        if let audioType = program.secondary_audio_type {
            var line = "副音声: \(audioType)"
            if let rate = program.secondary_audio_sampling_rate { line += " \(rate)" }
            if let language = program.secondary_audio_language { line += " / \(language)" }
            statusLines.append(line)
        }
        for line in statusLines {
            let label = UILabel()
            label.text = line
            label.font = .systemFont(ofSize: 12)
            label.textColor = AppPalette.metaText
            label.numberOfLines = 0
            contentStack.addArrangedSubview(label)
        }

        // 詳細情報 (見出しと本文の組)。並びは見出しの順にそろえる
        // (Web 版はサーバーの返した順だが、こちらでは順序を保てないため)。
        if let detail = program.detail {
            for heading in detail.keys.sorted() {
                guard let body = detail[heading], !body.isEmpty else { continue }
                let headingLabel = UILabel()
                headingLabel.text = heading
                headingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
                headingLabel.textColor = AppPalette.text
                headingLabel.numberOfLines = 0
                let bodyLabel = UILabel()
                bodyLabel.text = body
                bodyLabel.font = .systemFont(ofSize: 12.5)
                bodyLabel.textColor = AppPalette.metaText
                bodyLabel.numberOfLines = 0
                let section = UIStackView(arrangedSubviews: [headingLabel, bodyLabel])
                section.axis = .vertical
                section.spacing = 4
                contentStack.addArrangedSubview(section)
            }
        }

        // 予約まわりの情報 (状態・コメント・サイズ・有効/無効の切り替え)。
        // 終了済みの番組には出さない (Web 版と同じ)。
        // 操作ボタンは本文ではなく、画面下端の帯にまとめる (rebuildActions)。
        if !isPast {
            if let reservation {
                contentStack.addArrangedSubview(makeDivider())
                buildReservationSection(reservation: reservation, isRecording: isRecording)
            } else if reservationID != nil {
                // 番組表から開いて予約本体を取り直している途中 (または失敗)。
                let label = UILabel()
                label.text = reservationLoadFailed
                    ? "予約の情報を読み込めませんでした。画面を開き直してください。"
                    : "読み込み中…"
                label.font = .systemFont(ofSize: 13)
                label.textColor = AppPalette.metaText
                label.numberOfLines = 0
                contentStack.addArrangedSubview(label)
            }
        }
        rebuildActions(isPast: isPast)
    }

    /// 予約済みの場合の部分: 状態と有効/無効の切り替え
    /// (削除ボタンは画面下端の帯に置く)。
    private func buildReservationSection(reservation: Reservation, isRecording: Bool) {
        let statusRow = UIStackView()
        statusRow.axis = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .center
        let statusTitle = UILabel()
        statusTitle.text = "予約の状態"
        statusTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        statusTitle.textColor = AppPalette.text
        let chip = BadgeLabel()
        chip.text = ReservationStatusDisplay.text(
            isRecording: isRecording, availability: reservation.recording_availability)
        chip.font = .systemFont(ofSize: 11, weight: .semibold)
        chip.textColor = .white
        chip.backgroundColor = ReservationStatusDisplay.color(
            isRecording: isRecording, availability: reservation.recording_availability)
        chip.layer.cornerRadius = 4
        chip.clipsToBounds = true
        chip.textInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        statusRow.addArrangedSubview(statusTitle)
        statusRow.addArrangedSubview(chip)
        statusRow.addArrangedSubview(UIView())
        contentStack.addArrangedSubview(statusRow)

        if !reservation.comment.isEmpty {
            let commentLabel = UILabel()
            commentLabel.text = "コメント: \(reservation.comment)"
            commentLabel.font = .systemFont(ofSize: 12)
            commentLabel.textColor = AppPalette.metaText
            commentLabel.numberOfLines = 0
            contentStack.addArrangedSubview(commentLabel)
        }
        let sizeLabel = UILabel()
        sizeLabel.text = "録画予定サイズ: "
            + ReservationStatusDisplay.sizeText(bytes: reservation.estimated_recording_file_size)
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = AppPalette.metaText
        contentStack.addArrangedSubview(sizeLabel)

        // 有効/無効の切り替え。録画中は切り替えられない (Web 版と同じ)。
        let toggleRow = UIStackView()
        toggleRow.axis = .horizontal
        toggleRow.alignment = .center
        toggleRow.spacing = 10
        let toggleLabel = UILabel()
        toggleLabel.text = "この予約を有効にする"
        toggleLabel.font = .systemFont(ofSize: 14)
        toggleLabel.textColor = AppPalette.text
        toggleRow.addArrangedSubview(toggleLabel)
        toggleRow.addArrangedSubview(UIView())
        if isRecording {
            let recordingLabel = UILabel()
            recordingLabel.text = "録画中"
            recordingLabel.font = .systemFont(ofSize: 13)
            recordingLabel.textColor = AppPalette.accent
            toggleRow.addArrangedSubview(recordingLabel)
        } else {
            let toggle = WebToggle()
            toggle.isOn = reservation.record_settings.is_enabled
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            self.toggle = toggle
            toggleRow.addArrangedSubview(toggle)
        }
        contentStack.addArrangedSubview(toggleRow)
    }

    // MARK: - 操作ボタンの帯

    /// 画面下端の帯の中身を、状態に合わせて作り直す。
    /// 並びは Web 版の引き出しの下端と同じで、左から「視聴」→
    /// 「予約を削除」→「予約を追加」の順の右寄せ横並び
    /// (削除と追加は同時には出ない)。
    /// 終了済みの番組と、予約本体の取り直し中・失敗時は帯ごと隠す。
    private func rebuildActions(isPast: Bool) {
        for view in actionsStack.arrangedSubviews {
            actionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        watchButton = nil
        addButton = nil
        deleteButton = nil

        let isLoadingReservation = reservation == nil && reservationID != nil
        guard !isPast, !isLoadingReservation else {
            setActionsBarVisible(false)
            return
        }

        // 「視聴」。いま放送中の番組のときだけ、並びの先頭に出す
        // (Web 版の番組詳細で、操作ボタンの先頭に「視聴」があるのと同じ)。
        if canWatchNow {
            let button = makeActionButton(
                title: "視聴", systemImage: "play.fill", filled: true,
                action: #selector(watchTapped))
            watchButton = button
            actionsStack.addArrangedSubview(button)
        }
        if reservation != nil {
            // 「予約を削除」。Web 版は地のないボタン (文字と絵だけ)。
            let button = makeActionButton(
                title: "予約を削除", systemImage: "trash", filled: false,
                action: #selector(deleteTapped))
            button.isEnabled = !isWorking
            deleteButton = button
            actionsStack.addArrangedSubview(button)
        } else {
            // 「予約を追加」。Web 版と同じく secondary の地つき。
            let button = makeActionButton(
                title: "予約を追加", systemImage: "timer", filled: true,
                action: #selector(addTapped))
            // 土台が EDCB でない間は押せない (Web 版と同じ)。
            button.isEnabled = backendIsEDCB == true && !isWorking
            button.alpha = button.isEnabled ? 1 : 0.5
            addButton = button
            actionsStack.addArrangedSubview(button)
        }
        setActionsBarVisible(true)
    }

    /// 帯の表示・非表示と、スクロール範囲の下端の付け替え。
    private func setActionsBarVisible(_ visible: Bool) {
        actionsBar.isHidden = !visible
        // 付け替えは外す方を先にする (一瞬でも両方が効いて
        // 制約がぶつかる状態を作らないため)。
        if visible {
            scrollBottomToViewConstraint?.isActive = false
            scrollBottomToBarConstraint?.isActive = true
        } else {
            scrollBottomToBarConstraint?.isActive = false
            scrollBottomToViewConstraint?.isActive = true
        }
    }

    /// 操作ボタンの共通の作り (Web 版のボタンの標準の形)。
    /// 高さ 36、角丸 4、文字は 14 の中太、左右の余白 12、
    /// 絵と文字の間は 4。地つきは secondary の地に白、
    /// 地なしは透明の地に通常の文字色。
    private func makeActionButton(
        title: String, systemImage: String, filled: Bool, action: Selector
    ) -> RippleButton {
        let button = RippleButton()
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        let icon = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        button.setImage(icon, for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        if filled {
            button.setTitleColor(.white, for: .normal)
            button.tintColor = .white
            button.backgroundColor = AppPalette.secondary
        } else {
            button.setTitleColor(AppPalette.text, for: .normal)
            button.tintColor = AppPalette.text
            button.backgroundColor = .clear
        }
        button.layer.cornerRadius = 4
        button.clipsToBounds = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeBanner(text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = AppPalette.text
        label.numberOfLines = 0
        let container = UIView()
        container.backgroundColor = color.withAlphaComponent(0.18)
        container.layer.cornerRadius = 6
        container.layer.borderWidth = 1
        container.layer.borderColor = color.withAlphaComponent(0.7).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AppPalette.panel
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    // MARK: - 操作

    /// 「視聴」が押されたら、そのチャンネルの生放送の再生画面へ移る。
    /// 移り方は開いた側に委ねる (番組表から開いた場合は番組表を閉じる)。
    /// 委ね先が無い場合は、この画面が属するナビゲーションへそのまま積む。
    @objc private func watchTapped() {
        guard let liveChannel else { return }
        if let onWatchRequested {
            onWatchRequested(liveChannel)
        } else {
            let player = LivePlayerViewController(channel: liveChannel)
            navigationController?.pushViewController(player, animated: true)
        }
    }

    @objc private func addTapped() {
        guard !isWorking else { return }
        isWorking = true
        rebuildContent()
        Task { [weak self] in
            guard let self else { return }
            do {
                let settings = await APIClient.shared.fetchDefaultRecordSettings()
                try await APIClient.shared.addReservation(
                    programID: self.program.id, recordSettings: settings)
                // 追加できた予約の本体を取り直して、状態表示に切り替える。
                var found = false
                if let list = try? await APIClient.shared.fetchReservations(),
                   let created = list.reservations.first(where: { $0.program.id == self.program.id }) {
                    self.reservation = created
                    self.reservationID = created.id
                    found = true
                }
                self.isWorking = false
                self.onChanged?()
                if found {
                    self.rebuildContent()
                    self.showAlert(title: "録画予約を追加しました", message: self.program.title)
                } else {
                    // 追加はできたが取り直せなかった場合は、一覧側の
                    // 再読み込みに任せて画面を戻す。
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                self.isWorking = false
                self.rebuildContent()
                self.showAlert(title: "録画予約を追加できませんでした",
                               message: Self.message(from: error, fallback: "録画予約の追加に失敗しました。"))
            }
        }
    }

    @objc private func toggleChanged(_ sender: WebToggle) {
        guard let reservation, !isWorking else { return }
        isWorking = true
        var settings = reservation.record_settings
        settings.is_enabled = sender.isOn
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await APIClient.shared.updateReservation(
                    id: reservation.id, recordSettings: settings)
                self.reservation = updated
                self.isWorking = false
                self.onChanged?()
                self.rebuildContent()
            } catch {
                self.isWorking = false
                sender.isOn = reservation.record_settings.is_enabled
                self.showAlert(title: "録画予約を更新できませんでした",
                               message: Self.message(from: error, fallback: "録画予約の更新に失敗しました。"))
            }
        }
    }

    @objc private func deleteTapped() {
        guard let reservation, !isWorking else { return }
        let isRecording = reservation.is_recording_in_progress
        let isKeywordAuto = reservation.comment.contains("EPG自動予約")
        var message = program.title + "\n"
            + TimeFormat.recordingTimeText(
                start: program.startDate, end: program.endDate, durationSeconds: program.duration)
            + "\n\n"
        if isRecording {
            message += "この番組は現在録画中です。\n予約を削除すると、現在までの録画ファイルは残りますが、残りの期間の録画は中断されます。"
        } else {
            message += "録画予約を削除すると、番組開始時刻までに再度予約を追加しない限り、この番組は録画されません。"
        }
        if isKeywordAuto {
            message += "\n\nこの予約はキーワード自動予約で追加されました。削除してもすぐに再追加される可能性があります。録画が不要な場合は削除ではなく「無効」にすることをおすすめします。"
        }
        let alert = UIAlertController(
            title: "録画予約を削除しますか？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "予約を削除", style: .destructive) { [weak self] _ in
            self?.performDelete(reservation: reservation)
        })
        present(alert, animated: true)
    }

    private func performDelete(reservation: Reservation) {
        isWorking = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.deleteReservation(id: reservation.id)
                self.isWorking = false
                self.onChanged?()
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.isWorking = false
                self.showAlert(title: "録画予約を削除できませんでした",
                               message: Self.message(from: error, fallback: "録画予約の削除に失敗しました。"))
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// サーバーからの文が入っている失敗はその文を、それ以外は予備の文を返す。
    private static func message(from error: Error, fallback: String) -> String {
        if let apiError = error as? APIError, case .message(let text) = apiError {
            return text
        }
        return fallback
    }
}
