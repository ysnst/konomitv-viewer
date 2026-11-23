import UIKit

/// 「ニコニコ実況」の設定画面。Web 版の設定 → ニコニコ実況 (Jikkyo.vue)
/// の並びに合わせ、ミュート設定への入口を先頭に置き、続けて録画の
/// 過去ログコメントの表示に効く項目を並べたもの: コメントを表示、
/// コメントを無制限に表示、全画面でも盛り上がり波形を表示する、
/// コメントの不透明度、コメントの速さ、コメントの文字サイズ。
///
/// コメント投稿まわりの項目 (ニコニコアカウントとの連携、コメントの
/// 送信先、送信後にフォームを閉じる) は、アプリにコメント投稿が
/// 無いため置いていない。
/// 「コメントを表示」「無制限に表示」「不透明度」は Web 版でも端末
/// ごとに持つ項目 (同期の対象外) で、アプリでも端末に保存する。
/// 「全画面でも盛り上がり波形を表示する」はアプリ側の項目で、
/// こちらも端末に保存する (同期の対象外)。
/// 「速さ」「文字サイズ」とミュート設定は利用者設定と共通で、
/// 読み書きは SyncedSettingsStore が担う。
/// 変更はその場で保存され、次に録画再生を始めるときから効く。
final class JikkyoSettingsViewController: SettingsDetailViewController {
    private let showSwitch = WebToggle()
    private let unlimitedSwitch = WebToggle()
    private let excitementFullscreenSwitch = WebToggle()
    private let opacitySlider = UISlider()
    private let opacityValueLabel = UILabel()
    private let speedSlider = UISlider()
    private let speedValueLabel = UILabel()
    private let fontSizeSlider = UISlider()
    private let fontSizeValueLabel = UILabel()
    private let muteButton = RippleButton()

    init() {
        super.init(headingTitle: "ニコニコ実況")
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
        Task { [weak self] in
            if await SyncedSettingsStore.shared.refreshFromServer() {
                self?.reloadValues()
            }
        }
    }

    private func buildItems() {
        showSwitch.addTarget(self, action: #selector(showChanged), for: .valueChanged)
        unlimitedSwitch.addTarget(self, action: #selector(unlimitedChanged), for: .valueChanged)
        excitementFullscreenSwitch.addTarget(
            self, action: #selector(excitementFullscreenChanged), for: .valueChanged)
        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 1
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        speedSlider.minimumValue = 0.5
        speedSlider.maximumValue = 2
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        fontSizeSlider.minimumValue = 20
        fontSizeSlider.maximumValue = 60
        fontSizeSlider.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)

        muteButton.setTitle("コメントのミュート設定を開く", for: .normal)
        muteButton.addTarget(self, action: #selector(openMuteSettings), for: .touchUpInside)
        styleActionButton(muteButton)

        let opacityField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("プレイヤーに流れるコメントの不透明度を設定します。0% に設定するとコメントが完全に透明になり、100% に設定すると完全に不透明になります。"),
            makeSliderRow(slider: opacitySlider, valueLabel: opacityValueLabel),
        ])
        opacityField.axis = .vertical
        opacityField.spacing = 14
        let speedField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("プレイヤーに流れるコメントの速さを設定します。たとえば 1.2 に設定すると、コメントが 1.2 倍速く流れます。"),
            makeSliderRow(slider: speedSlider, valueLabel: speedValueLabel),
        ])
        speedField.axis = .vertical
        speedField.spacing = 14
        let fontSizeField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("プレイヤーに流れるコメントの文字サイズの基準値を設定します。実際の文字サイズは画面サイズに合わせて調整されます。デフォルトの文字サイズは 34px です。"),
            makeSliderRow(slider: fontSizeSlider, valueLabel: fontSizeValueLabel),
        ])
        fontSizeField.axis = .vertical
        fontSizeField.spacing = 14

        let muteField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("表示したくないコメントを、映像上やコメントリストに表示しないようにミュートできます。"),
            muteButton,
        ])
        muteField.axis = .vertical
        muteField.spacing = 14

        // 並びは本家 (Jikkyo.vue) に合わせ、ミュート設定を先頭に置く。
        // 本家の先頭にあるコメント投稿の項目は、アプリに投稿の
        // 土台が無いため置いていない。
        for view in [
            itemGroup(title: "コメントのミュート設定", field: muteField),
            makeDivider(),
            itemGroup(title: "コメントを表示", field: makeSwitchRow(
                text: "プレイヤーにニコニコ実況 / NX-Jikkyo のコメントを流すかどうかを設定します。再生画面の操作帯にあるコメントの切り替えと同じ設定です。",
                toggle: showSwitch), syncDisabled: true),
            itemGroup(title: "コメントを無制限に表示", field: makeSwitchRow(
                text: "オンにすると、コメントの重なりを許容し、可能な限り多くのコメントを表示します。コメントが多い番組でオンにすると、映像が見づらくなる可能性があります。",
                toggle: unlimitedSwitch), syncDisabled: true),
            itemGroup(title: "全画面でも盛り上がり波形を表示する", field: makeSwitchRow(
                text: "オンにすると、録画の再生を全画面で見るときも、シークバーの上に実況コメントの盛り上がりの波形を表示します。",
                toggle: excitementFullscreenSwitch), syncDisabled: true),
            itemGroup(title: "コメントの不透明度", field: opacityField, syncDisabled: true),
            makeDivider(),
            itemGroup(title: "コメントの速さ", field: speedField),
            itemGroup(title: "コメントの文字サイズ", field: fontSizeField),
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let store = SettingsStore.shared
        let synced = SyncedSettingsStore.shared.current
        showSwitch.isOn = store.showComments
        unlimitedSwitch.isOn = store.showCommentsUnlimited
        excitementFullscreenSwitch.isOn = store.showExcitementInFullscreen
        opacitySlider.value = Float(store.commentOpacity)
        opacityValueLabel.text = "\(Int((store.commentOpacity * 100).rounded()))%"
        speedSlider.value = Float(synced.commentSpeedRate)
        speedValueLabel.text = Self.speedText(synced.commentSpeedRate)
        fontSizeSlider.value = Float(synced.commentFontSize)
        fontSizeValueLabel.text = "\(Int(synced.commentFontSize.rounded()))px"
    }

    private static func speedText(_ rate: Double) -> String {
        if rate == rate.rounded() {
            return "\(Int(rate))倍"
        }
        return String(format: "%.1f倍", rate)
    }

    @objc private func showChanged() {
        SettingsStore.shared.showComments = showSwitch.isOn
    }

    @objc private func unlimitedChanged() {
        SettingsStore.shared.showCommentsUnlimited = unlimitedSwitch.isOn
    }

    @objc private func excitementFullscreenChanged() {
        SettingsStore.shared.showExcitementInFullscreen = excitementFullscreenSwitch.isOn
    }

    @objc private func opacityChanged() {
        let stepped = (Double(opacitySlider.value) / 0.05).rounded() * 0.05
        let value = min(1, max(0, stepped))
        SettingsStore.shared.commentOpacity = value
        opacityValueLabel.text = "\(Int((value * 100).rounded()))%"
    }

    @objc private func speedChanged() {
        // Web 版の刻み (0.1) に合わせて値を丸めてから保存する。
        let stepped = (Double(speedSlider.value) / 0.1).rounded() * 0.1
        var settings = SyncedSettingsStore.shared.current
        settings.commentSpeedRate = min(2, max(0.5, stepped))
        SyncedSettingsStore.shared.update(settings)
        speedValueLabel.text = Self.speedText(settings.commentSpeedRate)
    }

    @objc private func fontSizeChanged() {
        let stepped = Double(fontSizeSlider.value).rounded()
        var settings = SyncedSettingsStore.shared.current
        settings.commentFontSize = min(60, max(20, stepped))
        SyncedSettingsStore.shared.update(settings)
        fontSizeValueLabel.text = "\(Int(settings.commentFontSize.rounded()))px"
    }

    @objc private func openMuteSettings() {
        navigationController?.pushViewController(
            CommentMuteSettingsViewController(), animated: true)
    }
}
