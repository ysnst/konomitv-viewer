import UIKit

/// 録画結果一覧の画面 (Web 版 RecordingResultsDialog の写し。拡張版だけ)。
///
/// 録画一覧の容量行の「録画結果」から開く。サーバーが記録している
/// 予約録画の結果 (録れた・一部のみ・失敗) を新しい順に並べ、
/// 失敗の理由の案内と、受信の乱れ (ドロップなど) の件数も出す。
/// 録画が残っている結果は、選ぶとその録画の再生画面へ移る。
///
/// 見出し帯はゴミ箱の画面と同じ形: 高さ 60px・地は
/// background-lighten-1、左端は矢印だけの戻るボタン、ページ名 22px。
/// 端からの横スワイプでも戻れる。
final class RecordingResultsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let backButton = RippleButton()
    private let headingBar = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()

    private var results: [RecordingResult] = []
    private var isLoading = false

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "録画結果"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildHeadingBar()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RecordingResultCell.self, forCellReuseIdentifier: RecordingResultCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.backgroundColor = AppPalette.background
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    /// 見出し帯 (ゴミ箱の画面と同じ形)。
    private func buildHeadingBar() {
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "録画結果"
        headingLabel.font = .scaledSystemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)
        NSLayoutConstraint.activate([
            headingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headingBar.heightAnchor.constraint(equalToConstant: 60),
            headingStack.leadingAnchor.constraint(equalTo: headingBar.leadingAnchor, constant: 8),
            headingStack.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: headingBar.trailingAnchor, constant: -16),
        ])
        // 画面の左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        reloadResults()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func refresh() {
        reloadResults()
    }

    // MARK: - 読み込み

    private func reloadResults() {
        guard !isLoading else {
            refreshControl.endRefreshing()
            return
        }
        isLoading = true
        if results.isEmpty {
            statusLabel.text = "読み込み中です…"
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.results = try await APIClient.shared.fetchRecordingResults()
                self.statusLabel.text = self.results.isEmpty ? "まだ録画結果がありません" : nil
                self.tableView.reloadData()
            } catch {
                if self.results.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
                }
            }
            self.isLoading = false
            self.refreshControl.endRefreshing()
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: RecordingResultCell.reuseID, for: indexPath) as! RecordingResultCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 録画が残っている結果は、録画データを取り直してから再生画面へ移る
    /// (開き先でも番組情報の表示に材料が要るため)。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let recordedID = results[indexPath.row].recorded_id else { return }
        Task { [weak self] in
            guard let self else { return }
            if let program = await APIClient.shared.fetchVideo(videoID: recordedID) {
                self.navigationController?.pushViewController(
                    PlayerViewController(program: program), animated: true)
            }
        }
    }
}

/// 録画結果1件分の行。Web 版の並びどおり: 状態の印 (20px) の右に
/// 番組名・日時と尺の行・案内文、右端に結果の文字。
private final class RecordingResultCell: UITableViewCell {
    static let reuseID = "RecordingResultCell"

    private let statusIconView = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let noteLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        statusIconView.contentMode = .scaleAspectFit
        statusIconView.translatesAutoresizingMaskIntoConstraints = false

        // 番組名は Web 版どおり 14px 太字、1行で省略。
        nameLabel.font = .scaledSystemFont(ofSize: 14, weight: .bold)
        nameLabel.textColor = AppPalette.text
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        // 日時と尺の行は 12px・不透明度 0.75。
        metaLabel.font = .scaledSystemFont(ofSize: 12)
        metaLabel.textColor = AppPalette.text.withAlphaComponent(0.75)
        metaLabel.numberOfLines = 0
        // 案内文 (失敗の理由・受信の乱れ) は 12px、色は状態で変える。
        noteLabel.font = .scaledSystemFont(ofSize: 12)
        noteLabel.numberOfLines = 0

        let bodyStack = UIStackView(arrangedSubviews: [nameLabel, metaLabel, noteLabel])
        bodyStack.axis = .vertical
        bodyStack.spacing = 2
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        // 結果の文字は Web 版どおり 13px 太字で、状態の色にする。
        statusLabel.font = .scaledSystemFont(ofSize: 13, weight: .bold)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 行の下端の区切り線 (Web 版の 1px の薄い線)。
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 0.5, alpha: 0.25)
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(statusIconView)
        contentView.addSubview(bodyStack)
        contentView.addSubview(statusLabel)
        contentView.addSubview(separator)
        NSLayoutConstraint.activate([
            statusIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusIconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            statusIconView.widthAnchor.constraint(equalToConstant: 20),
            statusIconView.heightAnchor.constraint(equalToConstant: 20),
            bodyStack.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 10),
            bodyStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            bodyStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            statusLabel.leadingAnchor.constraint(equalTo: bodyStack.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with result: RecordingResult) {
        let style = Self.style(for: result.status)
        statusIconView.image = UIImage(
            systemName: style.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))?
            .withTintColor(style.color, renderingMode: .alwaysOriginal)
        statusLabel.text = style.label
        statusLabel.textColor = style.color
        nameLabel.text = result.name
        metaLabel.text = Self.metaLine(result)
        // 失敗のときは理由の案内、それ以外は受信の乱れがあればその行を出す。
        if result.status == "failed" {
            noteLabel.text = "録画ファイルが作成されませんでした（チューナー不足や受信不良の可能性があります）"
            noteLabel.textColor = Self.failedColor
            noteLabel.isHidden = false
        } else if let dropLine = Self.dropLine(result) {
            noteLabel.text = dropLine
            noteLabel.textColor = Self.partialColor
            noteLabel.isHidden = false
        } else {
            noteLabel.text = nil
            noteLabel.isHidden = true
        }
    }

    // MARK: - 状態ごとの見た目 (Web 版の対応表どおり)

    private static let successColor = UIColor(red: 0x66 / 255, green: 0xBB / 255, blue: 0x6A / 255, alpha: 1)
    private static let partialColor = UIColor(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255, alpha: 1)
    private static let failedColor = UIColor(red: 0xEF / 255, green: 0x53 / 255, blue: 0x50 / 255, alpha: 1)

    private static func style(for status: String) -> (label: String, symbol: String, color: UIColor) {
        switch status {
        case "partial":
            return ("一部のみ", "exclamationmark.triangle.fill", partialColor)
        case "failed":
            return ("失敗", "xmark.circle.fill", failedColor)
        default:
            return ("録画できた", "checkmark.circle.fill", successColor)
        }
    }

    /// 「チャンネル名 ・ M/D(曜) HH:mm〜HH:mm」の行。尺が取れている
    /// 結果では「 ・ 尺 ○ / 予定 ○」を続ける (Web 版と同じ)。
    private static func metaLine(_ result: RecordingResult) -> String {
        let startFormatter = DateFormatter()
        startFormatter.locale = Locale(identifier: "ja_JP")
        startFormatter.dateFormat = "M/d(EEE) HH:mm"
        let endFormatter = DateFormatter()
        endFormatter.locale = Locale(identifier: "ja_JP")
        endFormatter.dateFormat = "HH:mm"
        var line = "\(result.channel_name) ・ \(startFormatter.string(from: result.startDate))"
            + "〜\(endFormatter.string(from: result.endDate))"
        if let duration = result.duration {
            line += " ・ 尺 \(playbackTime(duration)) / 予定 \(playbackTime(result.end_at - result.start_at))"
        }
        return line
    }

    /// 受信の乱れの行。0 でない項目だけを「 ・ 」でつなぐ。
    /// どれも無ければ nil (行自体を出さない)。
    private static func dropLine(_ result: RecordingResult) -> String? {
        var parts: [String] = []
        if let count = result.drop_count, count > 0 { parts.append("ドロップ \(count) 件") }
        if let count = result.error_count, count > 0 { parts.append("エラー \(count) 件") }
        if let count = result.scrambling_count, count > 0 { parts.append("スクランブル \(count) 件") }
        return parts.isEmpty ? nil : "受信の乱れ: \(parts.joined(separator: " ・ "))"
    }

    /// 秒数を "m:ss" / "h:mm:ss" の形にする (Web 版 formatPlaybackTime と
    /// 同じく、秒は切り捨て)。
    private static func playbackTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
