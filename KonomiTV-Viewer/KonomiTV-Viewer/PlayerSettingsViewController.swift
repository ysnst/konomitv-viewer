import UIKit

/// 映像に重ねる操作。iOS 26 の標準ボタンの大きな塗りを避け、高さ44pt の操作領域を持たせる。
func styleVideoOverlayButton(_ button: UIButton, symbol: String, title: String, adaptive: Bool = false) {
    button.configuration = nil
    button.setTitle(nil, for: .normal)
    let configuration = UIImage.SymbolConfiguration(pointSize: 20)
    button.setPreferredSymbolConfiguration(configuration, forImageIn: .normal)
    let icon = UIImage(systemName: symbol, withConfiguration: configuration)
    button.setImage(icon, for: .normal)
    button.tintColor = .white
    button.backgroundColor = .clear
    button.accessibilityLabel = title
    if symbol == "captions.bubble" { button.accessibilityHint = "字幕データのある番組で表示します" }
    if !adaptive { button.widthAnchor.constraint(equalToConstant: 44).isActive = true }
    if adaptive {
        // 描画を下へ寄せ、シークの操作領域を侵さず視覚的な空白を減らす。
        button.contentVerticalAlignment = .bottom
    }
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
    // 全画面を別VCで提示しないため、現在の再生所有元へシステムUIを委譲する。
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    override var shouldAutorotate: Bool { topViewController?.shouldAutorotate ?? true }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}

/// サブメニューから閉じた場合とスワイプ終了も、提示元へ一度だけ返す。
final class PlayerSettingsNavigationController: ViewerNavigationController {
    var onClose: (() -> Void)?
    private var notified = false
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppPalette.panel
        appearance.titleTextAttributes = [.foregroundColor: AppPalette.text]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = AppPalette.accent
    }
    private weak var hiddenTabs: UIView?
    private var tabsWereHidden = false

    /// sheetの拡張ではなく、実際の映像下端から利用可能な領域へ固定する。
    func mount(in owner: UIViewController, below video: UIView? = nil, hiding tabs: UIView? = nil) {
        hiddenTabs = tabs
        tabsWereHidden = tabs?.isHidden ?? false
        tabs?.isHidden = true
        owner.addChild(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        owner.view.addSubview(view)
        if let video {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: video.bottomAnchor),
                view.bottomAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor),
            ])
        } else {
            // PWAの右側パネルを基準に、iOSの文字/トグルの幅を確保する。
            let width = view.widthAnchor.constraint(equalToConstant: 320)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.topAnchor, constant: 8),
                view.bottomAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.bottomAnchor, constant: -64),
                view.trailingAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.trailingAnchor),
                view.widthAnchor.constraint(lessThanOrEqualTo: owner.view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.5),
                width,
            ])
        }
        didMove(toParent: owner)
    }

    func closePanel() {
        if parent != nil {
            willMove(toParent: nil)
            view.removeFromSuperview()
            removeFromParent()
            finishClosing()
        } else { dismiss(animated: true) { [weak self] in self?.finishClosing() } }
    }
    private func finishClosing() {
        guard !notified else { return }
        notified = true
        hiddenTabs?.isHidden = tabsWereHidden
        onClose?()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if parent == nil && (isBeingDismissed || presentingViewController == nil) { finishClosing() }
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
        var isEnabled = true
    }
    private let rowsProvider: () -> [Row]
    private var rows: [Row] = []
    init(title: String = "プレイヤー設定", rows: @escaping () -> [Row]) {
        rowsProvider = rows
        super.init(style: .plain)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = AppPalette.background
        tableView.backgroundColor = AppPalette.background
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
    func refreshRows() {
        guard isViewLoaded else { return }
        rows = rowsProvider()
        tableView.reloadData()
    }
    @objc private func close() { (navigationController as? PlayerSettingsNavigationController)?.closePanel() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let row = rows[path.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = AppPalette.panel
        cell.isUserInteractionEnabled = row.isEnabled
        if !row.isEnabled { cell.accessibilityTraits.insert(.notEnabled) }
        cell.contentView.alpha = row.isEnabled ? 1 : 0.45
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
            control.isEnabled = row.isEnabled
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

/// 見た目はDPlayerの4pt/11pt、操作は映像内の24pt領域で受ける。
/// 下端基準なので、波形表示や操作行の高さにトラック位置が影響されない。
final class PlayerSeekSlider: UISlider {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 11, height: 11)).image { _ in
            AppPalette.accent.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 11, height: 11)).fill()
        }
        setThumbImage(image, for: .normal)
        setThumbImage(image, for: .highlighted)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: 0, y: bounds.maxY - 4, width: bounds.width, height: 4)
    }
    override func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let ratio = maximumValue > minimumValue ? CGFloat((value - minimumValue) / (maximumValue - minimumValue)) : 0
        return CGRect(x: rect.minX + min(1, max(0, ratio)) * rect.width - 5.5,
                      y: rect.midY - 5.5, width: 11, height: 11)
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        // トラックの任意位置を押してからドラッグできる。再生への反映は所有元の終了処理で行う。
        let rect = trackRect(forBounds: bounds)
        guard rect.width > 0 else { return false }
        let ratio = min(1, max(0, (touch.location(in: self).x - rect.minX) / rect.width))
        value = minimumValue + Float(ratio) * (maximumValue - minimumValue)
        let tracking = super.beginTracking(touch, with: event)
        sendActions(for: .valueChanged)
        return tracking
    }
}

// プレイヤー所有元から、子パネルの有無・終了を共有する。再生状態は所有しない。
extension UIViewController {
    var playerSettingsPanel: PlayerSettingsNavigationController? {
        children.compactMap { $0 as? PlayerSettingsNavigationController }.first
    }
}

/// PWAの40px幅を基準に、時間と操作ボタンを同じ高さへ収める。
/// 狭幅では横だけ調整し、文字とボタンを重ねたり行数を増やしたりしない。
final class PlayerActionRow: UIStackView {
    private let actions: UIStackView
    private let actionWidth: NSLayoutConstraint
    init(time: UIView, buttons: [UIButton]) {
        let group = UIStackView(arrangedSubviews: buttons)
        actions = group
        actionWidth = group.widthAnchor.constraint(equalToConstant: CGFloat(buttons.count) * 40)
        super.init(frame: .zero)
        group.distribution = .fillEqually
        axis = .horizontal
        alignment = .bottom
        spacing = 4
        // 横向きの余剰幅は時刻ラベルでなくスペーサーへ渡し、時間表記を左でまとめる。
        time.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let timeContainer = UIStackView(arrangedSubviews: [time, UIView()])
        timeContainer.alignment = .bottom
        addArrangedSubview(timeContainer)
        addArrangedSubview(actions)
        actionWidth.isActive = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        let count = actions.arrangedSubviews.filter { !$0.isHidden }.count
        if count > 0, bounds.width > 0 {
            let timeWidth = min(80, bounds.width * 0.23)
            let target = CGFloat(count) * min(40, max(0, bounds.width - timeWidth - spacing) / CGFloat(count))
            if abs(actionWidth.constant - target) > 0.5 { actionWidth.constant = target }
        }
        super.layoutSubviews()
    }
}

// 全画面専用VCに置かれていた向きの復元を、残る共通UIへ移す。
extension UIViewController {
    /// 退出後に窓が外れていても、所有元が控えたシーンへ端末の向きを戻す。
    func restoreOrientation(on scene: UIWindowScene?) {
        let mask: UIInterfaceOrientationMask
        // 端末の向きと画面の向きは横向きで左右が逆になる。
        switch UIDevice.current.orientation {
        case .landscapeLeft: mask = .landscapeRight
        case .landscapeRight: mask = .landscapeLeft
        default: mask = .portrait
        }
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
