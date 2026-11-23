import UIKit

/// 番組表の表示設定の画面。Web 版の「番組表の表示設定」ダイアログ
/// (TimeTableSettings.vue) の項目をそのまま写したもの:
/// 各チャンネルの表示幅 (広め／標準／狭め)、時間軸の表示密度
/// (広め／標準／狭め)、ショッピング・通販番組を控えめに表示するか、
/// ジャンル別のハイライト色。PC 向けの「カーソルを重ねた時に番組詳細を
/// 自動表示する」は、アプリには当てはまらないため置かない。
///
/// 値の保存は TimeTableSettingsStore が担う (端末内が基本で、同期が
/// 入っていればサーバーへも送られる)。値が変わるたびに呼び出し側へ
/// 知らせ、番組表の格子へその場で反映してもらう。
final class TimeTableSettingsViewController: UIViewController {
    /// 値が変わったときに、新しい値一式で呼ばれる。
    var onSettingsChanged: ((TimeTableDisplaySettings) -> Void)?

    /// 編集中の値一式。開いた時点の現在の値から始める。
    private var settings = TimeTableSettingsStore.shared.current

    private let channelWidthControl = WebSegmentedControl(items: ["広め", "標準", "狭め"])
    private let hourHeightControl = WebSegmentedControl(items: ["広め", "標準", "狭め"])
    private let dimShoppingSwitch = WebToggle()
    /// ジャンルごとの色ボタン (ジャンル名 → ボタン)。
    private var genreButtons: [String: UIButton] = [:]

    /// 幅・密度の選択肢の並び (分節の左から順)。
    private static let sizeOptionValues = ["Wide", "Normal", "Narrow"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        reloadValues()
    }

    // MARK: - 見た目の部品 (他の設定画面と共通の値)

    /// 項目の見出し (16.5px、テーマの text 色)。
    private func makeItemHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .scaledSystemFont(ofSize: 16.5)
        label.textColor = AppPalette.text
        label.numberOfLines = 0
        return label
    }

    /// 説明文 (13.5px、text-darken-1、行の高さ 1.6 倍)。
    private func makeDescriptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 13.5)
        label.textColor = AppPalette.metaText
        label.numberOfLines = 0
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 13.5 * 1.6
        style.maximumLineHeight = 13.5 * 1.6
        label.attributedText = NSAttributedString(
            string: text, attributes: [.paragraphStyle: style])
        return label
    }

    /// 固定の高さの余白。
    private func makeSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    // MARK: - 画面の組み立て

    private func buildLayout() {
        // 先頭の帯 (Web 版ダイアログの題名行: 歯車 26px + 題名 20px 太字、
        // 右端に閉じるボタン)。
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let gearView = UIImageView(image: UIImage(
            systemName: "gearshape",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        gearView.contentMode = .scaleAspectFit
        gearView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(gearView)
        let titleLabel = UILabel()
        titleLabel.text = "番組表の表示設定"
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
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 60),
            gearView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            gearView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            gearView.widthAnchor.constraint(equalToConstant: 26),
            gearView.heightAnchor.constraint(equalToConstant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: gearView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // 中身は縦スクロール。項目の並びと文言は Web 版ダイアログどおり。
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        // 各チャンネルの表示幅。
        channelWidthControl.addTarget(
            self, action: #selector(channelWidthChanged), for: .valueChanged)
        stack.addArrangedSubview(makeItemGroup(
            title: "各チャンネルの表示幅を調整",
            description: "各チャンネルの横方向の表示を調整します。広めにすると番組名が読みやすくなります。",
            field: channelWidthControl))

        // 時間軸の表示密度。
        hourHeightControl.addTarget(
            self, action: #selector(hourHeightChanged), for: .valueChanged)
        stack.addArrangedSubview(makeSpacer(24))
        stack.addArrangedSubview(makeItemGroup(
            title: "時間軸の表示密度を調整",
            description: "番組表の縦方向の表示密度を調整します。広めにすると番組詳細が読みやすくなります。",
            field: hourHeightControl))

        // ショッピング・通販番組を控えめに表示する。
        stack.addArrangedSubview(makeSpacer(24))
        stack.addArrangedSubview(makeItemHeading("ショッピング・通販番組を控えめに表示する"))
        stack.addArrangedSubview(makeSpacer(8))
        stack.addArrangedSubview(makeSwitchRow(
            text: "「ショッピング・通販」ジャンルの番組をグレーで表示し、番組表の視認性を高めます。",
            toggle: dimShoppingSwitch))
        dimShoppingSwitch.addTarget(
            self, action: #selector(dimShoppingChanged), for: .valueChanged)

        // ジャンル別のハイライト色。
        stack.addArrangedSubview(makeSpacer(24))
        stack.addArrangedSubview(makeItemHeading("ジャンル別のハイライト色"))
        stack.addArrangedSubview(makeSpacer(8))
        stack.addArrangedSubview(makeDescriptionLabel(
            "各ジャンルの番組セルに表示するハイライト色を設定します。\nよく見るジャンルに色を付けると、より番組を見つけやすくなります。"))
        stack.addArrangedSubview(makeSpacer(14))
        for genre in TimeTableDisplaySettings.genreList {
            stack.addArrangedSubview(makeGenreRow(genre: genre))
            stack.addArrangedSubview(makeSpacer(8))
        }
        stack.addArrangedSubview(makeSpacer(16))
    }

    /// 設定項目1つ分のまとまり (見出し → 8px 空けて説明 → 14px 空けて入力欄)。
    /// 説明の無い項目は説明を省く。
    private func makeItemGroup(title: String, description: String?, field: UIView) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.addArrangedSubview(makeItemHeading(title))
        if let description {
            stack.addArrangedSubview(makeSpacer(8))
            stack.addArrangedSubview(makeDescriptionLabel(description))
        }
        stack.addArrangedSubview(makeSpacer(14))
        stack.addArrangedSubview(field)
        return stack
    }

    /// 説明文とスイッチを横に並べた行 (他の設定画面と同じ組み方:
    /// 文が残りの幅で折り返し、スイッチは右端に固定で収まる)。
    private func makeSwitchRow(text: String, toggle: WebToggle) -> UIStackView {
        let label = makeDescriptionLabel(text)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    /// ジャンル1つ分の行 (左にジャンル名、右に色を選ぶボタン)。
    /// ボタンの見た目は Web 版の選択欄に寄せ、中身は色見本と色名と▽。
    /// 中身の部品はタップを受けず、ボタン自身が受ける。
    private func makeGenreRow(genre: String) -> UIStackView {
        let nameLabel = UILabel()
        nameLabel.text = genre
        nameLabel.font = .scaledSystemFont(ofSize: 14)
        nameLabel.textColor = AppPalette.text
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = RippleButton()
        button.backgroundColor = AppPalette.background
        button.layer.borderWidth = 1
        button.layer.borderColor = AppPalette.outlineBorder.cgColor
        button.layer.cornerRadius = 6
        button.showsMenuAsPrimaryAction = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let swatch = UIView()
        swatch.layer.cornerRadius = 4
        swatch.layer.borderWidth = 1
        swatch.layer.borderColor = UIColor.black.withAlphaComponent(0.2).cgColor
        swatch.clipsToBounds = true
        swatch.tag = 1
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 16).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let colorNameLabel = UILabel()
        colorNameLabel.font = .scaledSystemFont(ofSize: 13)
        colorNameLabel.textColor = AppPalette.text
        colorNameLabel.tag = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.down")?
            .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal))
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let inner = UIStackView(arrangedSubviews: [swatch, colorNameLabel, chevron])
        inner.axis = .horizontal
        inner.alignment = .center
        inner.spacing = 8
        inner.isUserInteractionEnabled = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            inner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        genreButtons[genre] = button

        let row = UIStackView(arrangedSubviews: [nameLabel, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    // MARK: - 値の反映

    /// 画面の表示を、編集中の値に合わせ直す。
    private func reloadValues() {
        channelWidthControl.selectedIndex =
            Self.sizeOptionValues.firstIndex(of: settings.channelWidth) ?? 1
        hourHeightControl.selectedIndex =
            Self.sizeOptionValues.firstIndex(of: settings.hourHeight) ?? 1
        dimShoppingSwitch.isOn = settings.dimShoppingPrograms
        for genre in TimeTableDisplaySettings.genreList {
            updateGenreButton(genre)
        }
    }

    /// ジャンル1つ分のボタンの表示 (色見本・色名・メニュー) を合わせ直す。
    private func updateGenreButton(_ genre: String) {
        guard let button = genreButtons[genre] else { return }
        let colorName = settings.genreColors[genre]
            ?? TimeTableDisplaySettings.defaultGenreColors[genre] ?? "White"
        if let swatch = button.viewWithTag(1) {
            swatch.backgroundColor = TimeTableGenre.swatchColor(forColorName: colorName)
        }
        if let label = button.viewWithTag(2) as? UILabel {
            label.text = TimeTableDisplaySettings.colorTitle(for: colorName)
        }
        button.menu = UIMenu(children: TimeTableDisplaySettings.colorOptions.map { option in
            UIAction(
                title: option.title,
                image: Self.swatchImage(forColorName: option.value),
                state: option.value == colorName ? .on : .off
            ) { [weak self] _ in
                self?.setGenreColor(option.value, for: genre)
            }
        })
    }

    /// メニューに出す色見本の画像 (16x16、角丸4、薄い枠つき)。
    private static func swatchImage(forColorName name: String) -> UIImage {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            TimeTableGenre.swatchColor(forColorName: name).setFill()
            path.fill()
            UIColor.black.withAlphaComponent(0.2).setStroke()
            path.stroke()
        }
    }

    /// 変更を保存し、呼び出し側へ知らせる。
    private func commit() {
        TimeTableSettingsStore.shared.update(settings)
        onSettingsChanged?(settings)
    }

    // MARK: - 操作

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func channelWidthChanged() {
        settings.channelWidth = Self.sizeOptionValues[channelWidthControl.selectedIndex]
        commit()
    }

    @objc private func hourHeightChanged() {
        settings.hourHeight = Self.sizeOptionValues[hourHeightControl.selectedIndex]
        commit()
    }

    @objc private func dimShoppingChanged() {
        settings.dimShoppingPrograms = dimShoppingSwitch.isOn
        commit()
    }

    private func setGenreColor(_ colorName: String, for genre: String) {
        settings.genreColors[genre] = colorName
        updateGenreButton(genre)
        commit()
    }
}
