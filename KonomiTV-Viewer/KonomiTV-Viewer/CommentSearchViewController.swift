import UIKit

/// コメント検索の画面 (Web 版 CommentSearchDialog の写し)。
///
/// 録画の実況コメント (過去ログ) をキーワードで探し (最大100件)、
/// 選ぶとその場面へ移動して画面を閉じる。検索の対象は、再生画面が
/// すでに取得しているコメントの一覧 (ミュート設定で取り除いた分は
/// 含まれない。Web 版は取り除く前のコメントから探す)。
final class CommentSearchViewController: UIViewController {
    /// 検索対象のコメント (時刻の昇順)。
    private let comments: [JikkyoComment]
    /// 場面が選ばれたときの知らせ先 (引数は再生位置 (秒))。
    var onSeek: ((Double) -> Void)?

    private let searchField = UITextField()
    private let summaryLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    /// 現在のキーワードで絞り込んだ結果 (最大100件)。
    private var filteredComments: [JikkyoComment] = []

    init(comments: [JikkyoComment]) {
        self.comments = comments
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        updateResults()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Web 版は開いたらすぐ入力できる状態にする (autofocus)。
        searchField.becomeFirstResponder()
    }

    // MARK: - 画面の組み立て

    private func buildLayout() {
        // 先頭の帯 (Web 版ダイアログの題名行: 絵 24px + 題名太字、右端に閉じるボタン)。
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let iconView = UIImageView(image: UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "コメント検索"
        titleLabel.font = .scaledSystemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = AppPalette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        let closeButton = RippleButton()
        closeButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
            for: .normal)
        closeButton.tintColor = AppPalette.text
        closeButton.accessibilityLabel = "閉じる"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(closeButton)

        // 検索の入力欄。
        searchField.backgroundColor = AppPalette.panel
        searchField.layer.cornerRadius = 6
        searchField.textColor = AppPalette.text
        searchField.font = .scaledSystemFont(ofSize: 14)
        searchField.attributedPlaceholder = NSAttributedString(
            string: "実況コメントを検索 (例: 選手名・実況の言葉)",
            attributes: [.foregroundColor: AppPalette.metaText])
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        searchField.leftViewMode = .always
        searchField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        searchField.rightViewMode = .always
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        // 件数の案内 (Web 版の summary と同じ文)。
        summaryLabel.font = .scaledSystemFont(ofSize: 12.5)
        summaryLabel.textColor = AppPalette.metaText
        summaryLabel.numberOfLines = 0
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryLabel)

        tableView.backgroundColor = AppPalette.background
        tableView.separatorColor = AppPalette.pressed
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 36
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(CommentSearchCell.self, forCellReuseIdentifier: CommentSearchCell.reuseIdentifier)
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // 一致なしの案内 (Web 版と同じ文)。
        emptyLabel.text = "一致するコメントがありません"
        emptyLabel.font = .scaledSystemFont(ofSize: 13.5)
        emptyLabel.textColor = AppPalette.metaText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 60),
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            searchField.heightAnchor.constraint(equalToConstant: 40),
            summaryLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 32),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func searchTextChanged() {
        updateResults()
    }

    /// キーワードで絞り込み、案内の文と結果を合わせ直す (Web 版と同じ)。
    private func updateResults() {
        let keyword = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if comments.isEmpty {
            summaryLabel.text = "この録画には実況コメントがありません"
            filteredComments = []
        } else if keyword.isEmpty {
            summaryLabel.text = "コメント \(comments.count) 件 (キーワードを入力すると絞り込めます)"
            filteredComments = []
        } else {
            filteredComments = Array(
                comments.filter { $0.text.lowercased().contains(keyword) }.prefix(100))
            summaryLabel.text = "\(filteredComments.count) 件ヒット (クリックでその場面へ移動)"
        }
        emptyLabel.isHidden = keyword.isEmpty || comments.isEmpty || !filteredComments.isEmpty
        tableView.reloadData()
    }
}

// MARK: - 結果の表の受け口

extension CommentSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredComments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: CommentSearchCell.reuseIdentifier, for: indexPath) as! CommentSearchCell
        let comment = filteredComments[indexPath.row]
        cell.configure(text: comment.text, timeText: TimeFormat.hms(comment.time))
        return cell
    }

    /// 行を押したら、そのコメントの時刻へ移動して閉じる。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard filteredComments.indices.contains(indexPath.row) else { return }
        onSeek?(filteredComments[indexPath.row].time)
        dismiss(animated: true)
    }
}

/// コメント検索の結果1行 (Web 版と同じ: 時刻 (ピンク・太字) + 本文)。
private final class CommentSearchCell: UITableViewCell {
    static let reuseIdentifier = "CommentSearchCell"

    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppPalette.background
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = AppPalette.pressed
        selectedBackgroundView = selectedBackground

        timeLabel.font = .scaledMonospacedDigitSystemFont(ofSize: 12.5, weight: .bold)
        timeLabel.textColor = AppPalette.accent
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bodyLabel.font = .scaledSystemFont(ofSize: 13.5)
        bodyLabel.textColor = AppPalette.text
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [timeLabel, bodyLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
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
