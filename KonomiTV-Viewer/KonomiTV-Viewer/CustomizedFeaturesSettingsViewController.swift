import UIKit

/// 「改造版サーバーの機能」の設定画面。「このアプリの設定」の
/// 「改造版サーバーの機能」の行から入る、1つ下の階層の画面。
///
/// konomitv-customizations を適用した改造版サーバーが持つ受け口を
/// 使う機能を、機能ごとのトグルで切り替える。以前はまとめトグル
/// 「改造版サーバーの機能を使う」1つだったものを、機能ごとに
/// 切り替えられるよう組み替えた (まとめトグルの値は、初回に
/// 個別トグル全部へ引き継がれる。SettingsStore 側)。
/// 各トグルの下には、その機能に必要なサーバー側のカスタマイズ
/// (konomitv-customizations の機能とパッチの名前) の案内を出す。
/// 名前の対応は konomitv-customizations の README の表による。
///
/// 値はいずれも端末ごとに持つ設定で、デバイス間同期の対象には
/// しない。切り替えはその場で保存する。
final class CustomizedFeaturesSettingsViewController: SettingsDetailViewController {
    private let protectionSwitch = WebToggle()
    private let trashSwitch = WebToggle()
    private let episodesSwitch = WebToggle()
    private let bookmarksScenesSwitch = WebToggle()
    private let recordingResultsSwitch = WebToggle()
    private let tunerInUseSwitch = WebToggle()

    init() {
        super.init(headingTitle: "改造版サーバーの機能")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
    }

    private func buildItems() {
        protectionSwitch.addTarget(self, action: #selector(protectionChanged), for: .valueChanged)
        trashSwitch.addTarget(self, action: #selector(trashChanged), for: .valueChanged)
        episodesSwitch.addTarget(self, action: #selector(episodesChanged), for: .valueChanged)
        bookmarksScenesSwitch.addTarget(self, action: #selector(bookmarksScenesChanged), for: .valueChanged)
        recordingResultsSwitch.addTarget(self, action: #selector(recordingResultsChanged), for: .valueChanged)
        tunerInUseSwitch.addTarget(self, action: #selector(tunerInUseChanged), for: .valueChanged)

        for view in [
            makeDescriptionLabel("konomitv-customizations を適用した改造版サーバー向けの機能を、機能ごとに切り替えます。素の KonomiTV サーバーでは使えません。この設定はこの端末だけに保存されます。"),
            itemGroup(
                title: "録画の保護",
                field: makeFeatureField(
                    text: "録画を保護したり、保護中の録画だけを表示したりできるようになります。",
                    guidance: "サーバー側に konomitv-customizations の「EPGStation/Jellyfin 連携（base-integration）」が入っているときに使えます。",
                    toggle: protectionSwitch),
                syncDisabled: true),
            itemGroup(
                title: "ゴミ箱",
                field: makeFeatureField(
                    text: "録画をゴミ箱へ移動したり、ゴミ箱を開いたりできるようになります。ゴミ箱は管理者だけに表示されます。",
                    guidance: "サーバー側に konomitv-customizations の「ゴミ箱（recorder-features）」が入っているときに使えます。",
                    toggle: trashSwitch),
                syncDisabled: true),
            itemGroup(
                title: "前の話・次の話ボタンと、次の話の自動再生",
                field: makeFeatureField(
                    text: "再生画面に前の話・次の話のボタンが出て、再生が終わると次の話が自動で始まるようになります。",
                    guidance: "サーバー側に konomitv-customizations の「前の話・次の話ボタン（playback）」と「次話の自動再生（recorder-features）」が入っているときに使えます。",
                    toggle: episodesSwitch),
                syncDisabled: true),
            itemGroup(
                title: "しおりと場面一覧",
                field: makeFeatureField(
                    text: "再生画面に、しおりを追加するボタンと場面一覧のボタンが出ます。",
                    guidance: "サーバー側に konomitv-customizations の「場面一覧（comment-highlights）」と「しおり（recorder-features）」が入っているときに使えます。",
                    toggle: bookmarksScenesSwitch),
                syncDisabled: true),
            itemGroup(
                title: "録画結果一覧",
                field: makeFeatureField(
                    text: "録画番組一覧の容量の行に、録画結果一覧への入口が出ます。",
                    guidance: "サーバー側に konomitv-customizations の「録画結果一覧（recorder-features）」が入っているときに使えます。",
                    toggle: recordingResultsSwitch),
                syncDisabled: true),
            itemGroup(
                title: "チューナー使用中のチャンネル表示",
                field: makeFeatureField(
                    text: "チューナーに空きがなく視聴できないチャンネルが、生放送の一覧で薄く表示されるようになります。",
                    guidance: "サーバー側に konomitv-customizations の「ライブ視聴のチューナー連動（live-tuner-gating）」が入っているときに使えます。",
                    toggle: tunerInUseSwitch),
                syncDisabled: true),
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    /// 機能1つ分の入力欄。説明文とスイッチの行の下に、サーバー側に
    /// 必要なカスタマイズの案内を置く。
    private func makeFeatureField(text: String, guidance: String, toggle: WebToggle) -> UIStackView {
        let field = UIStackView(arrangedSubviews: [
            makeSwitchRow(text: text, toggle: toggle),
            makeDescriptionLabel(guidance),
        ])
        field.axis = .vertical
        field.spacing = 14
        return field
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let store = SettingsStore.shared
        protectionSwitch.isOn = store.customizedProtectionEnabled
        trashSwitch.isOn = store.customizedTrashEnabled
        episodesSwitch.isOn = store.customizedEpisodesEnabled
        bookmarksScenesSwitch.isOn = store.customizedBookmarksScenesEnabled
        recordingResultsSwitch.isOn = store.customizedRecordingResultsEnabled
        tunerInUseSwitch.isOn = store.customizedTunerInUseEnabled
    }

    @objc private func protectionChanged() {
        SettingsStore.shared.customizedProtectionEnabled = protectionSwitch.isOn
    }

    @objc private func trashChanged() {
        SettingsStore.shared.customizedTrashEnabled = trashSwitch.isOn
    }

    @objc private func episodesChanged() {
        SettingsStore.shared.customizedEpisodesEnabled = episodesSwitch.isOn
    }

    @objc private func bookmarksScenesChanged() {
        SettingsStore.shared.customizedBookmarksScenesEnabled = bookmarksScenesSwitch.isOn
    }

    @objc private func recordingResultsChanged() {
        SettingsStore.shared.customizedRecordingResultsEnabled = recordingResultsSwitch.isOn
    }

    @objc private func tunerInUseChanged() {
        SettingsStore.shared.customizedTunerInUseEnabled = tunerInUseSwitch.isOn
    }
}
