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
/// 読み書きは SyncedSettingsStore が担う。変更はその場で保存される。
final class GeneralSettingsViewController: SettingsDetailViewController {
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
    private let maxCountButton = RippleButton()
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            if await SyncedSettingsStore.shared.refreshFromServer() {
                self?.reloadValues()
            }
        }
    }

    private func buildItems() {
        for button in [seekBackwardButton, seekForwardButton, playbackRateButton,
                       resumeRewindButton, maxCountButton, panelTabButton] {
            styleSelectButton(button)
        }
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
            itemGroup(title: "視聴履歴の保持件数", field: maxCountButton),
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
        updateMaxCountButton(selected: synced.videoWatchedHistoryMaxCount)
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

    private func updateMaxCountButton(selected: Int) {
        maxCountButton.setTitle("\(selected)件", for: .normal)
        maxCountButton.menu = UIMenu(children: SyncedClientSettings.watchedHistoryMaxCountOptions.map { count in
            UIAction(title: "\(count)件", state: count == selected ? .on : .off) { [weak self] _ in
                var settings = SyncedSettingsStore.shared.current
                settings.videoWatchedHistoryMaxCount = count
                SyncedSettingsStore.shared.update(settings)
                self?.reloadValues()
            }
        })
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
