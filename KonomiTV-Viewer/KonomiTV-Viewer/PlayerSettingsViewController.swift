import UIKit

/// 映像に重ねる操作。iOS 26 の標準ボタンの大きな塗りを避け、44pt の当たりを持たせる。
func styleVideoOverlayButton(_ button: UIButton, symbol: String, title: String) {
    button.configuration = nil
    button.setTitle(nil, for: .normal)
    button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .clear
    button.accessibilityLabel = title
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
}

/// 戻る・題名・既存時計を映像の上へまとめる。Safe Area 内の映像上端へ配置する。
final class PlayerOverlayHeader: UIStackView {
    let clock = UIStackView()
    init(title: String, onBack: @escaping () -> Void) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 6
        let back = RippleButton()
        styleVideoOverlayButton(back, symbol: "chevron.left", title: "戻る")
        back.addAction(UIAction { _ in onBack() }, for: .touchUpInside)
        let label = UILabel()
        label.text = title
        label.font = .scaledSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        clock.axis = .horizontal
        clock.spacing = 3
        clock.alignment = .center
        addArrangedSubview(back)
        addArrangedSubview(label)
        addArrangedSubview(clock)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 現在のアプリ背景は固定の濃色。コンテナが標準の黒文字へ戻さないよう明示する。
class ViewerNavigationController: UINavigationController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var childForStatusBarStyle: UIViewController? { nil }
}

/// サブメニューから閉じた場合とスワイプ終了も、提示元へ一度だけ返す。
final class PlayerSettingsNavigationController: ViewerNavigationController {
    var onClose: (() -> Void)?
    private var notified = false
    override func viewDidLoad() {
        super.viewDidLoad()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppPalette.panel
        appearance.titleTextAttributes = [.foregroundColor: AppPalette.text]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = AppPalette.accent
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if (isBeingDismissed || presentingViewController == nil), !notified {
            notified = true
            onClose?()
        }
    }
}

/// プレイヤーの実処理は所有元に残す。通常・全画面で同じ設定と操作を使う。
final class PlayerSettingsViewController: UITableViewController {
    struct Choice {
        let title: String
        let selected: Bool
        let select: () -> Void
    }
    struct Row {
        let title: String
        var value: String = ""
        var toggle: Bool? = nil
        var change: ((Bool) -> Void)? = nil
        var choices: [Choice] = []
        var action: (() -> Void)? = nil
    }
    private let rowsProvider: () -> [Row]
    private var rows: [Row] = []
    init(title: String = "プレイヤー設定", rows: @escaping () -> [Row]) {
        rowsProvider = rows
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        tableView.separatorColor = AppPalette.pressed
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "閉じる", style: .done, target: self, action: #selector(close))
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rows = rowsProvider()
        tableView.reloadData()
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let row = rows[path.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = AppPalette.panel
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = AppPalette.text
        cell.textLabel?.font = .scaledSystemFont(ofSize: 15)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = row.value
        cell.detailTextLabel?.textColor = AppPalette.secondaryText
        cell.detailTextLabel?.font = .scaledSystemFont(ofSize: 14)
        if let value = row.toggle {
            let control = UISwitch()
            control.isOn = value
            control.onTintColor = AppPalette.accent
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let control else { return }
                row.change?(control.isOn)
                self?.rows = self?.rowsProvider() ?? []
                self?.tableView.reloadData()
            }, for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none
        } else if !row.choices.isEmpty { cell.accessoryType = .disclosureIndicator }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        let row = rows[path.row]
        if !row.choices.isEmpty {
            let submenu = PlayerSettingsViewController(title: row.title) { [weak self] in
                guard let current = self?.rowsProvider().first(where: { $0.title == row.title }) else { return [] }
                return current.choices.map { choice in
                    Row(title: choice.title, value: choice.selected ? "✓" : "", action: { [weak self] in
                        choice.select()
                        self?.navigationController?.popViewController(animated: true)
                    })
                }
            }
            navigationController?.pushViewController(submenu, animated: true)
        } else if let action = row.action {
            action()
            rows = rowsProvider()
            tableView.reloadData()
        }
    }
}
