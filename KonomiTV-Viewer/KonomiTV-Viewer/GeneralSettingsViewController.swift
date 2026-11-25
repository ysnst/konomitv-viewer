import UIKit

/// 「全般」の設定画面。Web 版の設定 → 全般 (General.vue) の並びに
/// 合わせてある: ピン留め中チャンネルの並び替えへの入口、番組表の
/// 表示設定への入口、実況勢い順の並び替え、28 時間表記、元の放送
/// 時刻の表示、ビデオのパネルのタブ、視聴履歴の保持件数、スキップ
/// 秒数、再生速度。アプリ側の再生まわり (再開時の巻き戻し、
/// CM自動スキップ) は、本家に無い項目として末尾に置く。
/// 本家の全般のうち、アプリに土台が無い項目 (背景写真、完全な黒、
/// リモコン準拠の方向、キーボードショートカット、パネルの表示状態、
/// テレビのパネルのタブ、設定の出し入れ) は置かない。
///
/// スキップ秒数と再生速度は Web 版 (改造) でも端末ごとに持つ項目で、
/// アプリでも端末に保存する。それ以外の項目は利用者設定と共通で、
/// 読み書きは SyncedSettingsStore が担う。件数は入力確定時、それ以外はその場で保存する。
final class GeneralSettingsViewController: SettingsDetailViewController, UITextFieldDelegate {
    private let pinnedChannelsButton = RippleButton()
    private let timeTableButton = RippleButton()
    private let jikkyoForceSwitch = WebToggle()
    private let use28HourClockSwitch = WebToggle()
    private let originalTimeSwitch = WebToggle()
    private let seekBackwardButton = RippleButton()
    private let seekForwardButton = RippleButton()
    private let playbackRateButton = RippleButton()
    private let resumeRewindButton = RippleButton()
    private let cmAutoSkipSwitch = WebToggle()
    private let maxCountField = UITextField()
    private var maxCountOriginal: Int?
    private var maxCountContext: WatchedHistoryStore.Context?
    private var maxCountEditGeneration = 0
    private var maxCountIsSaving = false
    private let panelTabButton = RippleButton()

    init() {
        super.init(headingTitle: "全般")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
    }

    private var appearRefreshGeneration = 0

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearRefreshGeneration += 1
        let generation = appearRefreshGeneration
        Task { [weak self] in
            if await SyncedSettingsStore.shared.refreshFromServer() {
                guard let self, generation == self.appearRefreshGeneration else { return }
                self.reloadValues()
            }
        }
    }

    private func buildItems() {
        for button in [seekBackwardButton, seekForwardButton, playbackRateButton,
                       resumeRewindButton, panelTabButton] {
            styleSelectButton(button)
        }
        styleTextField(maxCountField, placeholder: "1以上の整数")
        maxCountField.keyboardType = .numberPad
        maxCountField.textAlignment = .right
        maxCountField.accessibilityLabel = "視聴履歴の保持件数"
        maxCountField.delegate = self
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(title: "キャンセル", style: .plain, target: self, action: #selector(cancelMaxCountEdit)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "確定", style: .done, target: self, action: #selector(confirmMaxCountEdit)),
        ]
        toolbar.sizeToFit()
        maxCountField.inputAccessoryView = toolbar
        let unit = makeDescriptionLabel("件")
        unit.setContentHuggingPriority(.required, for: .horizontal)
        unit.setContentCompressionResistancePriority(.required, for: .horizontal)
        let maxCountRow = UIStackView(arrangedSubviews: [maxCountField, unit])
        maxCountRow.spacing = 8
        maxCountRow.alignment = .center
        cmAutoSkipSwitch.addTarget(self, action: #selector(cmAutoSkipChanged), for: .valueChanged)
        jikkyoForceSwitch.addTarget(self, action: #selector(jikkyoForceChanged), for: .valueChanged)
        use28HourClockSwitch.addTarget(self, action: #selector(use28HourClockChanged), for: .valueChanged)
        originalTimeSwitch.addTarget(self, action: #selector(originalTimeChanged), for: .valueChanged)

        pinnedChannelsButton.setTitle("ピン留め中チャンネルの並び替え設定を開く", for: .normal)
        pinnedChannelsButton.addTarget(self, action: #selector(openPinnedChannels), for: .touchUpInside)
        styleActionButton(pinnedChannelsButton)
        let pinnedField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("ピン留め中のチャンネルの表示順序を変更できます。よくみるチャンネルは先頭に配置しておくと便利です。ピン留め中のチャンネルの追加・削除は、別途 テレビをみる画面のチャンネル一覧から行えます。"),
            pinnedChannelsButton,
        ])
        pinnedField.axis = .vertical
        pinnedField.spacing = 14

        timeTableButton.setTitle("番組表の表示設定を開く", for: .normal)
        timeTableButton.addTarget(self, action: #selector(openTimeTableSettings), for: .touchUpInside)
        styleActionButton(timeTableButton)
        let timeTableField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("各チャンネルの表示幅や時間軸の表示密度、ジャンル別のハイライト色を設定します。番組表の歯車から開く表示設定と同じものです。"),
            timeTableButton,
        ])
        timeTableField.axis = .vertical
        timeTableField.spacing = 14

        let playbackRateField = UIStackView(arrangedSubviews: [
            playbackRateButton,
            makeDescriptionLabel("録画の再生を始めるときの速度です。再生中に変えると、次回もその速度で始まります。"),
        ])
        playbackRateField.axis = .vertical
        playbackRateField.spacing = 14
        let resumeRewindField = UIStackView(arrangedSubviews: [
            resumeRewindButton,
            makeDescriptionLabel("前回見た位置から再開するとき、この秒数だけ戻して始めます。"),
        ])
        resumeRewindField.axis = .vertical
        resumeRewindField.spacing = 14

        // 並びは本家の全般 (General.vue) に合わせる。本家に無い
        // アプリ側の項目 (再開時の巻き戻し、CM自動スキップ) は末尾。
        for view in [
            itemGroup(title: "ピン留め中チャンネルの並び替え", field: pinnedField),
            itemGroup(title: "番組表の表示設定", field: timeTableField),
            makeDivider(),
            itemGroup(title: "チャンネル一覧を実況勢いが強い順に並び替える", field: makeSwitchRow(
                text: "オンにすると、チャンネル一覧を実況勢い (ニコニコ実況に1分間に投稿されたコメント数) が強い順に並べ替えます。デフォルトはオフです。実況勢いが同じ場合や、ニコニコ実況が存在しないチャンネル、実況勢いの取得に失敗したチャンネルは、通常通りチャンネル番号順で表示されます。",
                toggle: jikkyoForceSwitch)),
            itemGroup(title: "時刻を 28 時間表記で表示する", field: makeSwitchRow(
                text: "深夜番組でよく使われる 28 時間表記 (24 時 〜 27 時) で時刻を表示します。デフォルトはオフです。オンにすると、午前 0 時 〜 3 時が前日の 24 時 〜 27 時と表示され、深夜番組の放送時間がよりわかりやすくなります。",
                toggle: use28HourClockSwitch)),
            itemGroup(title: "録画番組の再生中に元の放送時刻を表示する", field: makeSwitchRow(
                text: "オンにすると、録画番組の再生中に現在時刻ではなく、元の放送時刻を再生位置に合わせて表示します。デフォルトはオフです。元の放送時刻が表示されているときは、タイムシフト再生中であることを示すアイコンが時刻の左側に表示されます。",
                toggle: originalTimeSwitch)),
            makeDivider(),
            itemGroup(title: "ビデオをみるときにデフォルトで表示されるパネルのタブ", field: panelTabButton),
            itemGroup(title: "視聴履歴の保持件数", field: maxCountRow),
            itemGroup(title: "スキップ秒数 (戻し)", field: seekBackwardButton, syncDisabled: true),
            itemGroup(title: "スキップ秒数 (送り)", field: seekForwardButton, syncDisabled: true),
            itemGroup(title: "録画再生の再生速度", field: playbackRateField, syncDisabled: true),
            itemGroup(title: "再開時の巻き戻し", field: resumeRewindField, syncDisabled: true),
            itemGroup(title: "CM自動スキップ", field: makeSwitchRow(
                text: "録画の再生中に CM 区間の開始を跨ぐと、自動で CM の終わりまで飛ばします。シークで CM の途中へ移ったときは飛ばしません。",
                toggle: cmAutoSkipSwitch), syncDisabled: true),
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let store = SettingsStore.shared
        updateSecondsButton(seekBackwardButton, choices: SettingsStore.seekBackwardChoices,
                            selected: store.seekBackwardSeconds) {
            SettingsStore.shared.seekBackwardSeconds = $0
        }
        updateSecondsButton(seekForwardButton, choices: SettingsStore.seekForwardChoices,
                            selected: store.seekForwardSeconds) {
            SettingsStore.shared.seekForwardSeconds = $0
        }
        updateSecondsButton(resumeRewindButton, choices: SettingsStore.resumeRewindChoices,
                            selected: store.resumeRewindSeconds) {
            SettingsStore.shared.resumeRewindSeconds = $0
        }
        updatePlaybackRateButton(selected: store.playbackRate)
        cmAutoSkipSwitch.isOn = store.cmAutoSkip
        let synced = SyncedSettingsStore.shared.current
        jikkyoForceSwitch.isOn = synced.tvChannelSortByJikkyoForce
        use28HourClockSwitch.isOn = synced.use28HourClock
        originalTimeSwitch.isOn = synced.showOriginalBroadcastTimeDuringPlayback
        // 非同期の設定読込や他項目の変更で、入力途中のドラフトを上書きしない。
        if maxCountOriginal == nil { maxCountField.text = String(synced.videoWatchedHistoryMaxCount) }
        updatePanelTabButton(selected: synced.videoPanelActiveTab)
    }

    /// 秒数の選択ボタンの表示とメニューを、保存値に合わせて作り直す。
    private func updateSecondsButton(_ button: UIButton, choices: [Int], selected: Int,
                                     setter: @escaping (Int) -> Void) {
        button.setTitle("\(selected)秒", for: .normal)
        button.menu = UIMenu(children: choices.map { choice in
            UIAction(title: "\(choice)秒", state: choice == selected ? .on : .off) { [weak self] _ in
                setter(choice)
                self?.reloadValues()
            }
        })
    }

    /// 再生速度の選択ボタンの表示とメニューを、保存値に合わせて作り直す。
    private func updatePlaybackRateButton(selected: Double) {
        playbackRateButton.setTitle(SettingsStore.playbackRateText(selected), for: .normal)
        playbackRateButton.menu = UIMenu(children: SettingsStore.playbackRateChoices.map { rate in
            UIAction(title: SettingsStore.playbackRateText(rate),
                     state: rate == selected ? .on : .off) { [weak self] _ in
                SettingsStore.shared.playbackRate = rate
                self?.reloadValues()
            }
        })
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard textField === maxCountField, maxCountOriginal == nil else { return }
        maxCountOriginal = SyncedSettingsStore.shared.current.videoWatchedHistoryMaxCount
        maxCountContext = WatchedHistoryStore.Context.current
        maxCountEditGeneration += 1
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // キーボードを閉じるだけでは確定しない。明示的な確定処理中だけドラフトを保持する。
        if textField === maxCountField, maxCountOriginal != nil, !maxCountIsSaving { cancelMaxCountEdit() }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === maxCountField { confirmMaxCountEdit() }
        return false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelMaxCountEdit()
    }

    @objc private func cancelMaxCountEdit() {
        maxCountEditGeneration += 1
        maxCountOriginal = nil
        maxCountContext = nil
        maxCountIsSaving = false
        maxCountField.isEnabled = true
        maxCountField.resignFirstResponder()
        maxCountField.text = String(SyncedSettingsStore.shared.current.videoWatchedHistoryMaxCount)
    }

    @objc private func confirmMaxCountEdit() {
        guard !maxCountIsSaving, let original = maxCountOriginal, let context = maxCountContext else { return }
        guard let value = WatchedHistoryLimitInput.parse(maxCountField.text ?? "") else {
            showMaxCountMessage("1以上の整数を入力してください。小数・記号・端末で表現できない大きな数値は保存できません。")
            return
        }
        maxCountIsSaving = true
        maxCountField.resignFirstResponder()
        maxCountField.isEnabled = false
        let generation = maxCountEditGeneration
        Task { [weak self] in
            let verified: Bool
            if SyncedSettingsStore.isSyncEnabled {
                verified = await SyncedSettingsStore.shared.refreshFromServer(requireFresh: true)
            } else { verified = true }
            guard let self, generation == self.maxCountEditGeneration else { return }
            guard context == WatchedHistoryStore.Context.current else {
                self.cancelMaxCountEdit()
                self.showMaxCountMessage("接続先またはアカウントが変更されたため、保存を取り消しました。")
                return
            }
            guard verified else {
                self.cancelMaxCountEdit()
                self.showMaxCountMessage("設定の同期中、または最新の設定を確認できませんでした。現在の値は変更していません。少し待ってから再度お試しください。")
                return
            }
            self.reviewMaxCount(value, original: original, context: context, generation: generation)
        }
    }

    private func reviewMaxCount(_ value: Int, original: Int, context: WatchedHistoryStore.Context, generation: Int) {
        guard generation == maxCountEditGeneration, context == WatchedHistoryStore.Context.current else { return }
        let current = SyncedSettingsStore.shared.current.videoWatchedHistoryMaxCount
        if value == current { cancelMaxCountEdit(); return }
        if value < current || current != original {
            var message = current != original ? "編集中に保持件数が\(current)件へ変更されました。\(value)件へ変更しますか？" : "保持件数を\(current)件から\(value)件へ減らしますか？"
            if value < current { message += "\n次回の新しい履歴追加時に、上限を超える古い履歴が削除される場合があります。" }
            let alert = UIAlertController(title: "視聴履歴の保持件数", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { [weak self] _ in self?.cancelMaxCountEdit() })
            alert.addAction(UIAlertAction(title: "変更する", style: .default) { [weak self, weak alert] _ in
                // 確認中の同期変更で再確認が必要でも、古いalertと同時に表示しない。
                alert?.dismiss(animated: true) {
                    self?.saveMaxCount(value, reviewedCount: current, context: context, generation: generation)
                }
            })
            present(alert, animated: true)
        } else { saveMaxCount(value, reviewedCount: current, context: context, generation: generation) }
    }

    private func saveMaxCount(_ value: Int, reviewedCount: Int, context: WatchedHistoryStore.Context, generation: Int) {
        guard generation == maxCountEditGeneration else { return }
        guard context == WatchedHistoryStore.Context.current else { cancelMaxCountEdit(); return }
        // 確認中の同期更新も見直す。最後のコピーから対象項目だけ変え、他設定を巻き戻さない。
        var settings = SyncedSettingsStore.shared.current
        guard settings.videoWatchedHistoryMaxCount == reviewedCount else {
            reviewMaxCount(value, original: reviewedCount, context: context, generation: generation)
            return
        }
        settings.videoWatchedHistoryMaxCount = value
        SyncedSettingsStore.shared.update(settings)
        cancelMaxCountEdit()
    }

    private func showMaxCountMessage(_ message: String) {
        let alert = UIAlertController(title: "視聴履歴の保持件数", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .default))
        present(alert, animated: true)
    }

    private func updatePanelTabButton(selected: String) {
        let options: [(value: String, title: String)] = [
            ("RecordedProgram", "番組情報タブ"),
            ("Comment", "コメントタブ"),
        ]
        panelTabButton.setTitle(
            options.first { $0.value == selected }?.title ?? "番組情報タブ", for: .normal)
        panelTabButton.menu = UIMenu(children: options.map { option in
            UIAction(title: option.title, state: option.value == selected ? .on : .off) { [weak self] _ in
                var settings = SyncedSettingsStore.shared.current
                settings.videoPanelActiveTab = option.value
                SyncedSettingsStore.shared.update(settings)
                self?.reloadValues()
            }
        })
    }

    @objc private func cmAutoSkipChanged() {
        SettingsStore.shared.cmAutoSkip = cmAutoSkipSwitch.isOn
    }

    @objc private func jikkyoForceChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.tvChannelSortByJikkyoForce = jikkyoForceSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func use28HourClockChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.use28HourClock = use28HourClockSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func originalTimeChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.showOriginalBroadcastTimeDuringPlayback = originalTimeSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    /// ピン留め中チャンネルの並び替えは、設定の詳細画面として押し込む
    /// (Web 版では全般の中のダイアログだが、アプリの設定は画面遷移で
    /// 統一しているため、それに合わせた)。
    @objc private func openPinnedChannels() {
        navigationController?.pushViewController(
            PinnedChannelsViewController(), animated: true)
    }

    /// 番組表の表示設定は、番組表から開くときと同じシートで開く。
    @objc private func openTimeTableSettings() {
        let settingsController = TimeTableSettingsViewController()
        if let sheet = settingsController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(settingsController, animated: true)
    }
}
