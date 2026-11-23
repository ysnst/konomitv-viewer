import UIKit

/// 「画質」の設定画面。テレビ (生放送) とビデオ (録画) の画質まわりを、
/// 回線の区分 (Wi-Fi 回線時 / モバイル回線時) ごとに設定する。
/// Web 版の「画質」画面の並びに寄せてある。
///
/// 設定は端末だけに保存され (Web 版でもデバイス間同期の対象外)、変更は
/// その場で保存される。効くのは次に再生を始めるときからで、再生中の
/// 画質は変わらない。
/// 再生まわりの項目 (スキップ秒数、再生速度、CM自動スキップ、
/// 再開時の巻き戻し) は、Web 版の分類に合わせて「全般」の画面へ
/// 移した (GeneralSettingsViewController)。
/// テレビのグループには低遅延もある (生放送だけの項目)。
final class PlaybackSettingsViewController: UIViewController {
    /// いま画面で編集中の回線の区分。上の切り替えで変える。
    private var selectedProfile: PlaybackProfile = .wifi

    private let wifiProfileButton = RippleButton()
    private let cellularProfileButton = RippleButton()
    private let tvQualityButton = RippleButton()
    private let tvDataSaverSwitch = WebToggle()
    private let tvLowLatencySwitch = WebToggle()
    private let tv24fpsSwitch = WebToggle()
    private let videoQualityButton = RippleButton()
    private let videoDataSaverSwitch = WebToggle()
    private let video24fpsSwitch = WebToggle()
    private let backButton = RippleButton()

    init() {
        super.init(nibName: nil, bundle: nil)
        // この画面ではナビゲーションバーを隠すため見出しには出ない。
        title = "画質"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        reloadValues()
        // 左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 設定画面と同じく、この画面ではナビゲーションバーを隠し、
        // 代わりに自前の見出し帯を出す。
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - 見た目の部品 (設定画面と共通の値)

    /// 項目の見出し (16.5px、テーマの text 色)。
    private func makeItemHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16.5)
        label.textColor = AppPalette.text
        label.numberOfLines = 0
        return label
    }

    /// 説明文 (13.5px、text-darken-1、行の高さ 1.6 倍)。
    private func makeDescriptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13.5)
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

    /// 設定項目1つ分のまとまり (見出し → 14px 空けて入力欄)。
    /// この画面の項目は全部、端末だけに保存される (Web 版でもデバイス間
    /// 同期の対象外) ため、見出しの右端に Web 版と同じ
    /// 「デバイス間同期無効」の印を付ける。
    private func itemGroup(title: String, field: UIView) -> UIStackView {
        let heading = makeItemHeading(title)
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headingRow = UIStackView(arrangedSubviews: [
            heading,
            makeSyncDisabledBadge(),
        ])
        headingRow.axis = .horizontal
        headingRow.alignment = .center
        headingRow.spacing = 8
        let stack = UIStackView(arrangedSubviews: [
            headingRow,
            makeSpacer(14),
            field,
        ])
        stack.axis = .vertical
        return stack
    }

    /// 「デバイス間同期無効」の印の幅 (全項目で共通)。
    /// 文字の幅 (11px のフォントで測った値) に左右 4px ずつの余白を足した
    /// 固定幅にする。項目ごとに長さが変わらないようにするための決め打ちで、
    /// フォントの大きさから都度測るので、文字が切れる心配は無い。
    private static let syncDisabledBadgeWidth: CGFloat = {
        let font = UIFont.systemFont(ofSize: 11)
        let textWidth = ("デバイス間同期無効" as NSString)
            .size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 8
    }()

    /// 「デバイス間同期無効」の印 (Web 版 Base.vue の作り: 地は
    /// background-lighten-2、文字 11px、角丸 4px、余白は上下 2px・左右 4px、
    /// 見出し行の右端に寄せて置く)。
    /// 以前は入れ物の幅が定まらず、横並びの組み立ての中で行の余りの幅に
    /// 引き伸ばされて、項目ごとに長さがバラバラになっていた (0.25 で
    /// 実機確認)。幅を全項目共通の固定にして、見出し側が残りの幅を
    /// 受け持つ (長い見出しは折り返す) ように直した。
    private func makeSyncDisabledBadge() -> UIView {
        let label = UILabel()
        label.text = "デバイス間同期無効"
        label.font = .systemFont(ofSize: 11)
        label.textColor = AppPalette.text
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let badge = UIView()
        badge.backgroundColor = AppPalette.pressed
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.syncDisabledBadgeWidth),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -4),
        ])
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        return badge
    }

    /// 区切りの見出し (Web 版の settings__content-heading: アイコン 22px +
    /// 文字 18px・text-darken-1、下に 10px 空けて 2px の線)。
    private func makeSectionHeading(iconName: String, fallbackSystemName: String, title: String) -> UIView {
        let icon = (UIImage(named: iconName) ?? UIImage(systemName: fallbackSystemName))?
            .withRenderingMode(.alwaysTemplate)
        let iconView = UIImageView(image: icon)
        iconView.tintColor = AppPalette.metaText
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 18)
        label.textColor = AppPalette.metaText
        let row = UIStackView(arrangedSubviews: [iconView, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let border = UIView()
        border.backgroundColor = AppPalette.pressed
        border.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(row)
        container.addSubview(border)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            border.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 10),
            border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 2),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// 画質の選択ボタンに、設定画面の入力欄と同じ箱の見た目を付ける。
    private func styleQualityButton(_ button: UIButton) {
        button.contentHorizontalAlignment = .leading
        button.showsMenuAsPrimaryAction = true
        button.backgroundColor = AppPalette.background
        button.layer.borderWidth = 1
        button.layer.borderColor = AppPalette.fieldBorder.cgColor
        button.layer.cornerRadius = 4
        button.setTitleColor(AppPalette.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        // 右の余白は、右端に留める矢印の分 (12 + 12 + 8) を空ける。
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 32)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        addSelectChevron(to: button)
    }

    /// 選択ボタンの右端に、下向きの矢印を留める。
    /// ボタン標準の画像の並べ方 (semanticContentAttribute の
    /// forceRightToLeft) は、左寄せの指定と干渉して文字まで右寄せに
    /// なってしまう (実機確認)。設定の共通部品 (SettingsDetailViewController)
    /// と同じく、画像を右端に留める形にする。
    private func addSelectChevron(to button: UIButton) {
        let tag = 0x5E1EC7
        if button.viewWithTag(tag) != nil { return }
        let chevron = UIImageView(
            image: UIImage(systemName: "chevron.down")?
                .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal))
        chevron.tag = tag
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    /// 説明文とスイッチを横に並べた行。
    /// 説明文は「1行に広がったときの幅」を主張するため、そのままだと
    /// スイッチが画面の右端の外へ押し出されて切れる (0.24 で実機確認)。
    /// 文の横方向の圧縮への強さを下げ、スイッチ側を固定にすることで、
    /// 文が残りの幅で折り返し、スイッチは右端に余白を持って収まる
    /// (Web 版のスイッチ項目が、右にスイッチ分の余白を確保する組み方と
    /// 同じ考え方)。
    private func makeSwitchRow(text: String, toggle: WebToggle) -> UIStackView {
        let label = makeDescriptionLabel(text)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [
            label,
            toggle,
        ])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func buildLayout() {
        // 上部の見出し帯 (設定画面と同じ: 高さ 60px、地が background-lighten-1、
        // ページ名 22px)。この画面は必ず押し込まれた先として開くので、
        // 戻るボタンは常に出す。
        let headingBar = UIView()
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "画質"
        headingLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        // 戻るボタンは本家に合わせて矢印だけ (文字は付けない)。
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)

        let note = makeDescriptionLabel(
            "回線の種類は再生を始めるときに判定します。再生の途中で回線が変わっても、画質は次に再生するときから変わります。")

        // 回線の切り替え (Web 版のタブと同じ2択)。選んだ区分の値が下に出る。
        for (button, title) in [(wifiProfileButton, "Wi-Fi回線時"), (cellularProfileButton, "モバイル回線時")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15.5)
            button.layer.borderWidth = 1
            button.layer.borderColor = AppPalette.fieldBorder.cgColor
            button.layer.cornerRadius = 4
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        wifiProfileButton.addTarget(self, action: #selector(selectWifiProfile), for: .touchUpInside)
        cellularProfileButton.addTarget(self, action: #selector(selectCellularProfile), for: .touchUpInside)
        let profileRow = UIStackView(arrangedSubviews: [wifiProfileButton, cellularProfileButton])
        profileRow.axis = .horizontal
        profileRow.distribution = .fillEqually
        profileRow.spacing = 8

        styleQualityButton(tvQualityButton)
        styleQualityButton(videoQualityButton)

        tvDataSaverSwitch.addTarget(self, action: #selector(tvDataSaverChanged), for: .valueChanged)
        tvLowLatencySwitch.addTarget(self, action: #selector(tvLowLatencyChanged), for: .valueChanged)
        tv24fpsSwitch.addTarget(self, action: #selector(tv24fpsChanged), for: .valueChanged)
        videoDataSaverSwitch.addTarget(self, action: #selector(videoDataSaverChanged), for: .valueChanged)
        video24fpsSwitch.addTarget(self, action: #selector(video24fpsChanged), for: .valueChanged)

        // 並びは Web 版の画質ページに寄せる: 区切りの見出しごとに
        // 「テレビのライブストリーミング」「ビデオのオンデマンド
        // ストリーミング」の2つのまとまりに分ける。
        let stack = UIStackView(arrangedSubviews: [
            note,
            profileRow,
            makeSectionHeading(iconName: "ic_fluent_tv_20_regular",
                               fallbackSystemName: "tv",
                               title: "テレビのライブストリーミング"),
            itemGroup(title: "テレビの画質", field: tvQualityButton),
            itemGroup(title: "テレビの通信節約モード", field: makeSwitchRow(
                text: "映像を H.265 / HEVC で受けて、データ量を減らします。",
                toggle: tvDataSaverSwitch)),
            itemGroup(title: "テレビの低遅延", field: makeSwitchRow(
                text: "生放送の受け取りの溜めを減らして、放送との遅れを小さくします。回線が不安定なときは映像が止まりやすくなります。次に生放送を開いたときから効きます。",
                toggle: tvLowLatencySwitch)),
            itemGroup(title: "テレビの24fpsモード", field: makeSwitchRow(
                text: "映像を 24fps 化して受けます。サーバーの変換方式によっては使えないことがあります。",
                toggle: tv24fpsSwitch)),
            makeSectionHeading(iconName: "ic_fluent_movies_and_tv_20_regular",
                               fallbackSystemName: "film",
                               title: "ビデオのオンデマンドストリーミング"),
            itemGroup(title: "ビデオの画質", field: videoQualityButton),
            itemGroup(title: "ビデオの通信節約モード", field: makeSwitchRow(
                text: "映像を H.265 / HEVC で受けて、データ量を減らします。",
                toggle: videoDataSaverSwitch)),
            itemGroup(title: "ビデオの24fpsモード", field: makeSwitchRow(
                text: "映像を 24fps 化して受けます。サーバーの変換方式によっては使えないことがあります。",
                toggle: video24fpsSwitch)),
        ])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            headingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headingBar.heightAnchor.constraint(equalToConstant: 60),
            headingStack.leadingAnchor.constraint(equalTo: headingBar.leadingAnchor, constant: 16),
            headingStack.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: headingBar.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    /// 選んでいる回線の区分に合わせて、全項目の表示を保存値に合わせ直す。
    private func reloadValues() {
        let store = SettingsStore.shared
        updateProfileButtons()
        updateQualityButton(tvQualityButton, media: .tv,
                            selected: store.streamingQuality(media: .tv, profile: selectedProfile))
        updateQualityButton(videoQualityButton, media: .video,
                            selected: store.streamingQuality(media: .video, profile: selectedProfile))
        tvDataSaverSwitch.isOn = store.dataSaverMode(media: .tv, profile: selectedProfile)
        tvLowLatencySwitch.isOn = store.lowLatencyMode(profile: selectedProfile)
        tv24fpsSwitch.isOn = store.fps24Mode(media: .tv, profile: selectedProfile)
        videoDataSaverSwitch.isOn = store.dataSaverMode(media: .video, profile: selectedProfile)
        video24fpsSwitch.isOn = store.fps24Mode(media: .video, profile: selectedProfile)
    }

    private func updateProfileButtons() {
        for (button, isSelected) in [(wifiProfileButton, selectedProfile == .wifi),
                                     (cellularProfileButton, selectedProfile == .cellular)] {
            button.backgroundColor = isSelected ? AppPalette.pressed : AppPalette.background
            button.setTitleColor(isSelected ? AppPalette.text : AppPalette.metaText, for: .normal)
        }
    }

    private func updateQualityButton(_ button: UIButton, media: PlaybackMedia, selected: String) {
        button.setTitle(selected, for: .normal)
        button.menu = UIMenu(children: SettingsStore.qualities.map { quality in
            UIAction(title: quality, state: quality == selected ? .on : .off) { [weak self] _ in
                guard let self else { return }
                SettingsStore.shared.setStreamingQuality(
                    quality, media: media, profile: self.selectedProfile)
                self.updateQualityButton(button, media: media, selected: quality)
            }
        })
    }

    @objc private func selectWifiProfile() {
        selectedProfile = .wifi
        reloadValues()
    }

    @objc private func selectCellularProfile() {
        selectedProfile = .cellular
        reloadValues()
    }

    @objc private func tvDataSaverChanged() {
        SettingsStore.shared.setDataSaverMode(
            tvDataSaverSwitch.isOn, media: .tv, profile: selectedProfile)
    }

    @objc private func tvLowLatencyChanged() {
        SettingsStore.shared.setLowLatencyMode(
            tvLowLatencySwitch.isOn, profile: selectedProfile)
    }

    @objc private func tv24fpsChanged() {
        SettingsStore.shared.setFps24Mode(
            tv24fpsSwitch.isOn, media: .tv, profile: selectedProfile)
    }

    @objc private func videoDataSaverChanged() {
        SettingsStore.shared.setDataSaverMode(
            videoDataSaverSwitch.isOn, media: .video, profile: selectedProfile)
    }

    @objc private func video24fpsChanged() {
        SettingsStore.shared.setFps24Mode(
            video24fpsSwitch.isOn, media: .video, profile: selectedProfile)
    }
}
