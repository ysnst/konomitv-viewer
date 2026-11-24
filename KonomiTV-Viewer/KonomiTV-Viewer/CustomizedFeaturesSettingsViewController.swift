import UIKit

/// 「拡張オプション」の設定画面。「このアプリの設定」の
/// 「拡張オプション」の行から入る、1つ下の階層の画面。
///
/// konomitv-customizations を適用した改造版サーバーが持つ受け口を
/// 使う機能を、機能ごとのトグルで切り替える。以前はまとめトグル
/// 1つだったものを、機能ごとに切り替えられるよう組み替えた
/// (まとめトグルの値は、初回に個別トグル全部へ引き継がれる。
/// SettingsStore 側)。
/// 各トグルの下には、その機能に必要なサーバー側のカスタマイズ
/// (konomitv-customizations の機能とパッチの名前) の案内を出す。
/// 名前の対応は konomitv-customizations の README の表による。
///
/// 値はいずれも端末ごとに持つ設定で、デバイス間同期の対象には
/// しない。切り替えはその場で保存する。
///
/// 画面の一番上には、全体のトグル「拡張オプションを使用」
/// を置く (Android の開発者向けオプションの一番上のトグルと
/// 同じ形)。オフにすると解放が戻り、「このアプリの設定」の中の
/// 入口の行自体が消えて、機能が全部止まる。個別トグルの状態は
/// 保持されるため、マイページの App version の行を7回タップして
/// 解放し直せば、そのままの状態で復帰する。
final class CustomizedFeaturesSettingsViewController: SettingsDetailViewController {
    private let masterSwitch = WebToggle()
    private let protectionSwitch = WebToggle()
    private let trashSwitch = WebToggle()
    private let episodesSwitch = WebToggle()
    private let bookmarksScenesSwitch = WebToggle()
    private let recordingResultsSwitch = WebToggle()
    private let tunerInUseSwitch = WebToggle()

    init() {
        super.init(headingTitle: "拡張オプション")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
    }

    private func buildItems() {
        masterSwitch.addTarget(self, action: #selector(masterChanged), for: .valueChanged)
        protectionSwitch.addTarget(self, action: #selector(protectionChanged), for: .valueChanged)
        trashSwitch.addTarget(self, action: #selector(trashChanged), for: .valueChanged)
        episodesSwitch.addTarget(self, action: #selector(episodesChanged), for: .valueChanged)
        bookmarksScenesSwitch.addTarget(self, action: #selector(bookmarksScenesChanged), for: .valueChanged)
        recordingResultsSwitch.addTarget(self, action: #selector(recordingResultsChanged), for: .valueChanged)
        tunerInUseSwitch.addTarget(self, action: #selector(tunerInUseChanged), for: .valueChanged)

        for view in [
            makeSwitchRow(text: "拡張オプションを使用", toggle: masterSwitch),
            makeDescriptionLabel("改造版サーバー向けの機能を、機能ごとに切り替えます。素のサーバーでは使えません。設定はこの端末だけに保存されます。"),
            makeDivider(),
            itemGroup(
                title: "録画の保護",
                field: makeFeatureField(
                    text: "録画の保護と、保護中だけの表示ができるようになります。",
                    guidance: "サーバー側に「EPGStation/Jellyfin 連携（base-integration）」が必要です。",
                    toggle: protectionSwitch),
                syncDisabled: true),
            itemGroup(
                title: "ゴミ箱",
                field: makeFeatureField(
                    text: "録画をゴミ箱へ移動できるようになります。管理者だけに表示されます。",
                    guidance: "サーバー側に「ゴミ箱（recorder-features）」が必要です。",
                    toggle: trashSwitch),
                syncDisabled: true),
            itemGroup(
                title: "前の話・次の話ボタンと、次の話の自動再生",
                field: makeFeatureField(
                    text: "再生画面に前の話・次の話ボタンが出て、終わると次が自動で始まります。",
                    guidance: "サーバー側に「前の話・次の話ボタン（playback）」と「次話の自動再生（recorder-features）」が必要です。",
                    toggle: episodesSwitch),
                syncDisabled: true),
            itemGroup(
                title: "しおりと場面一覧",
                field: makeFeatureField(
                    text: "再生画面にしおりと場面一覧のボタンが出ます。",
                    guidance: "サーバー側に「場面一覧（comment-highlights）」と「しおり（recorder-features）」が必要です。",
                    toggle: bookmarksScenesSwitch),
                syncDisabled: true),
            itemGroup(
                title: "録画結果一覧",
                field: makeFeatureField(
                    text: "録画番組一覧の容量の行に入口が出ます。",
                    guidance: "サーバー側に「録画結果一覧（recorder-features）」が必要です。",
                    toggle: recordingResultsSwitch),
                syncDisabled: true),
            itemGroup(
                title: "チューナー使用中のチャンネル表示",
                field: makeFeatureField(
                    text: "視聴できないチャンネルが、生放送の一覧で薄く表示されます。",
                    guidance: "サーバー側に「ライブ視聴のチューナー連動（live-tuner-gating）」が必要です。",
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

    /// 全体のトグル。オフにすると解放を戻し、機能が全部止まって
    /// 入口の行も消えるため、そのまま前の画面へ戻る (戻った先の
    /// 設定画面では、入口の行が消えた状態で表示される)。個別
    /// トグルの状態は触らない (解放し直せばそのまま復帰する)。
    /// この画面は解放済みのときしか開けないため、オンへの切り替え
    /// は実際には起きないが、値の対応として解放を立てる。
    @objc private func masterChanged() {
        if masterSwitch.isOn {
            SettingsStore.shared.customizedServerFeaturesUnlocked = true
        } else {
            SettingsStore.shared.customizedServerFeaturesUnlocked = false
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let store = SettingsStore.shared
        masterSwitch.isOn = store.customizedServerFeaturesUnlocked
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
