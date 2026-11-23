import UIKit

/// 「ライセンス」の画面。アプリが実際に使っている部品を、
/// 部品名とライセンス名の行で並べる。行を押すと全文の画面へ進む。
/// 全文はアプリに同梱した文書 (Licenses フォルダの各ファイル) から
/// 読み込む (部品の置き場所にある実物から取り込んだもの)。
///
/// 並べている部品と根拠:
/// - MobileVLCKit: Podfile で入れている映像再生の部品 (LGPL 2.1)。
/// - libaribcaption: 字幕の描画に使っている同梱の部品 (MIT)。
///   全文は同梱先にある LICENSE の実物。
/// - Fluent UI System Icons: 画面のアイコン素材 (MIT)。
/// - Material Icons: マイリストのアイコン素材 (Apache License 2.0)。
final class LicenseViewController: SettingsDetailViewController {
    struct Component {
        let name: String
        let licenseName: String
        /// 全文の文書ファイル名 (拡張子なし)。
        let resourceName: String
    }

    static let components: [Component] = [
        Component(name: "MobileVLCKit",
                  licenseName: "GNU Lesser General Public License 2.1",
                  resourceName: "MobileVLCKit"),
        Component(name: "libaribcaption",
                  licenseName: "MIT License",
                  resourceName: "libaribcaption"),
        Component(name: "Fluent UI System Icons",
                  licenseName: "MIT License",
                  resourceName: "FluentUISystemIcons"),
        Component(name: "Material Icons",
                  licenseName: "Apache License 2.0",
                  resourceName: "MaterialIcons"),
    ]

    init() {
        super.init(headingTitle: "ライセンス")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.spacing = 6
        for component in Self.components {
            contentStack.addArrangedSubview(makeRow(component))
        }
        contentStack.addArrangedSubview(makeSpacer(6))
        contentStack.addArrangedSubview(
            makeDescriptionLabel("行を押すと、その部品のライセンス全文が読めます。"))
    }

    /// 部品名 (16px) とライセンス名 (12.5px) を重ねた行。
    /// 見た目はマイページの入口ボタンと同じ面と角丸にそろえる。
    private func makeRow(_ component: Component) -> UIButton {
        let button = RippleButton()
        button.backgroundColor = AppPalette.panel
        button.layer.cornerRadius = 6
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 12)
        button.heightAnchor.constraint(equalToConstant: 62).isActive = true
        let title = NSMutableAttributedString(
            string: component.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: AppPalette.text,
            ])
        title.append(NSAttributedString(
            string: "\n" + component.licenseName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.5),
                .foregroundColor: AppPalette.secondaryText,
            ]))
        button.setAttributedTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.setImage(
            UIImage(systemName: "chevron.right")?
                .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal),
            for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(
                LicenseDetailViewController(component: component), animated: true)
        }, for: .touchUpInside)
        return button
    }

    /// 全文の文書を読み込む。同梱の置き方に合わせて、フォルダ内と
    /// 直下の両方を探す。
    static func licenseText(resourceName: String) -> String? {
        let url = Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Licenses")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "txt")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}

/// ライセンス全文の画面。部品名を見出し帯に出し、本文をそのまま出す。
final class LicenseDetailViewController: SettingsDetailViewController {
    private let component: LicenseViewController.Component

    init(component: LicenseViewController.Component) {
        self.component = component
        super.init(headingTitle: component.name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = LicenseViewController.licenseText(resourceName: component.resourceName)
            ?? "ライセンス文書を読み込めませんでした。"
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = AppPalette.metaText
        label.numberOfLines = 0
        contentStack.addArrangedSubview(label)
    }
}
