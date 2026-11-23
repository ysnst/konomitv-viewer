import UIKit

/// 「字幕」の設定画面。Web 版の設定 → 字幕 (Caption.vue) の項目を
/// そのまま写したもの: 字幕のフォント、字幕の文字を常に縁取りする、
/// 字幕の不透明度を指定する + 字幕の不透明度、テレビ・ビデオそれぞれの
/// 文字スーパーの表示。
///
/// 値はいずれもサーバーに保存される利用者設定と共通で、読み書きは
/// SyncedSettingsStore が担う (同期が入っていればサーバーへも送られる)。
/// 変更はその場で保存され、次に録画再生を始めるときから字幕の描画に
/// 効く。テレビ側の文字スーパーは、生放送の字幕表示がまだ無いため、
/// いまは Web 版と共通の値の置き場所として働く (生放送の字幕が入った
/// ときにそのまま効く)。
final class CaptionSettingsViewController: SettingsDetailViewController {
    private let fontButton = RippleButton()
    private let borderSwitch = WebToggle()
    private let specifyOpacitySwitch = WebToggle()
    private let opacitySlider = UISlider()
    private let opacityValueLabel = UILabel()
    private var opacityGroup: UIStackView?
    private let tvSuperimposeSwitch = WebToggle()
    private let videoSuperimposeSwitch = WebToggle()

    init() {
        super.init(headingTitle: "字幕")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 同期が入っていれば、開くときにサーバー側の値を取り込んで
        // 表示を合わせ直す (番組表の設定と同じ考え方)。
        Task { [weak self] in
            if await SyncedSettingsStore.shared.refreshFromServer() {
                self?.reloadValues()
            }
        }
    }

    private func buildItems() {
        styleSelectButton(fontButton)

        borderSwitch.addTarget(self, action: #selector(borderChanged), for: .valueChanged)
        specifyOpacitySwitch.addTarget(self, action: #selector(specifyOpacityChanged), for: .valueChanged)
        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 1
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        tvSuperimposeSwitch.addTarget(self, action: #selector(tvSuperimposeChanged), for: .valueChanged)
        videoSuperimposeSwitch.addTarget(self, action: #selector(videoSuperimposeChanged), for: .valueChanged)

        let opacityRow = makeSliderRow(slider: opacitySlider, valueLabel: opacityValueLabel)
        let opacityField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("上の [字幕の不透明度を指定する] をオンに設定したときのみ有効です。不透明度を 0 に設定すれば、字幕の背景を非表示にできます。"),
            opacityRow,
        ])
        opacityField.axis = .vertical
        opacityField.spacing = 14
        let opacityGroup = itemGroup(title: "字幕の不透明度", field: opacityField)
        self.opacityGroup = opacityGroup

        let fontField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("プレイヤーで字幕表示をオンにしているときの、字幕のフォントを設定します。端末に無いフォントは、近い形のフォントで代用されます。"),
            fontButton,
        ])
        fontField.axis = .vertical
        fontField.spacing = 14

        for view in [
            itemGroup(title: "字幕のフォント", field: fontField),
            itemGroup(title: "字幕の文字を常に縁取りする", field: makeSwitchRow(
                text: "オンにすると、字幕の文字が縁取りされてより見やすくなります。とくに理由がなければ、オンにしておくのがおすすめです。オフのときも、字幕データから明示的に縁取りを指定されている場合には、オンのときと同様に字幕の文字が縁取りされます。",
                toggle: borderSwitch)),
            itemGroup(title: "字幕の不透明度を指定する", field: makeSwitchRow(
                text: "オフのときは、字幕データから指定されている不透明度で描画します。とくに理由がなければ、オフにしておくのがおすすめです。",
                toggle: specifyOpacitySwitch)),
            opacityGroup,
            makeDivider(),
            itemGroup(title: "テレビをみるときに文字スーパーを表示する", field: makeSwitchRow(
                text: "文字スーパーは、緊急地震速報の赤テロップや、NHK BS のニュース速報のテロップなどで利用されています。とくに理由がなければ、オンにしておくのがおすすめです。",
                toggle: tvSuperimposeSwitch)),
            itemGroup(title: "ビデオをみるときに文字スーパーを表示する", field: makeSwitchRow(
                text: "文字スーパーは、緊急地震速報の赤テロップや、NHK BS のニュース速報のテロップなどで利用されています。録画当時の文字スーパーによるニュース速報を確認したい方以外は、オフにしておくのがおすすめです。",
                toggle: videoSuperimposeSwitch)),
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let settings = SyncedSettingsStore.shared.current
        updateFontButton(selected: settings.captionFont)
        borderSwitch.isOn = settings.alwaysBorderCaptionText
        specifyOpacitySwitch.isOn = settings.specifyCaptionOpacity
        opacitySlider.value = Float(settings.captionOpacity)
        opacityValueLabel.text = "\(Int((settings.captionOpacity * 100).rounded()))%"
        opacityGroup?.alpha = settings.specifyCaptionOpacity ? 1 : 0.45
        opacitySlider.isEnabled = settings.specifyCaptionOpacity
        tvSuperimposeSwitch.isOn = settings.tvShowSuperimpose
        videoSuperimposeSwitch.isOn = settings.videoShowSuperimpose
    }

    private func updateFontButton(selected: String) {
        let title = SyncedClientSettings.captionFontOptions
            .first { $0.value == selected }?.title ?? selected
        fontButton.setTitle(title, for: .normal)
        fontButton.menu = UIMenu(children: SyncedClientSettings.captionFontOptions.map { option in
            UIAction(title: option.title, state: option.value == selected ? .on : .off) { [weak self] _ in
                var settings = SyncedSettingsStore.shared.current
                settings.captionFont = option.value
                SyncedSettingsStore.shared.update(settings)
                self?.reloadValues()
            }
        })
    }

    @objc private func borderChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.alwaysBorderCaptionText = borderSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func specifyOpacityChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.specifyCaptionOpacity = specifyOpacitySwitch.isOn
        SyncedSettingsStore.shared.update(settings)
        reloadValues()
    }

    @objc private func opacityChanged() {
        // Web 版の刻み (0.05) に合わせて値を丸めてから保存する。
        let stepped = (Double(opacitySlider.value) / 0.05).rounded() * 0.05
        var settings = SyncedSettingsStore.shared.current
        settings.captionOpacity = min(1, max(0, stepped))
        SyncedSettingsStore.shared.update(settings)
        opacityValueLabel.text = "\(Int((settings.captionOpacity * 100).rounded()))%"
    }

    @objc private func tvSuperimposeChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.tvShowSuperimpose = tvSuperimposeSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func videoSuperimposeChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.videoShowSuperimpose = videoSuperimposeSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }
}
