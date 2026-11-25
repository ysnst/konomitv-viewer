import UIKit

/// 保存先は本家と同じ同期対象。BrowserはiOSでは写真ライブラリへの保存として扱う。
final class CaptureSettingsViewController: SettingsDetailViewController {
    private let saveModeButton = RippleButton()
    private let captionModeButton = RippleButton()
    private var refreshGeneration = 0

    init() { super.init(headingTitle: "キャプチャ") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        styleSelectButton(saveModeButton)
        styleSelectButton(captionModeButton)
        contentStack.addArrangedSubview(itemGroup(title: "キャプチャの保存先", field: saveModeButton))
        contentStack.addArrangedSubview(makeDescriptionLabel("サーバー保存ではKonomiTVサーバーのキャプチャ保存先設定を使用します。端末に保存する場合だけ、写真の追加権限を要求します。"))
        contentStack.addArrangedSubview(itemGroup(title: "字幕の保存方法", field: captionModeButton))
        reloadValues()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { [weak self] in
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            guard let self, generation == self.refreshGeneration else { return }
            self.reloadValues()
        }
    }
    private func reloadValues() {
        let current = SyncedSettingsStore.shared.current
        saveModeButton.setTitle(current.captureSaveMode.title, for: .normal)
        saveModeButton.menu = UIMenu(children: CaptureSaveMode.allCases.map { mode in
            UIAction(title: mode.title, state: mode == current.captureSaveMode ? .on : .off) { [weak self] _ in
                var settings = SyncedSettingsStore.shared.current
                settings.captureSaveMode = mode
                SyncedSettingsStore.shared.update(settings)
                self?.reloadValues()
            }
        })
        captionModeButton.setTitle(current.captureCaptionMode.title, for: .normal)
        captionModeButton.menu = UIMenu(children: CaptureCaptionMode.allCases.map { mode in
            UIAction(title: mode.title, state: mode == current.captureCaptionMode ? .on : .off) { [weak self] _ in
                var settings = SyncedSettingsStore.shared.current
                settings.captureCaptionMode = mode
                SyncedSettingsStore.shared.update(settings)
                self?.reloadValues()
            }
        })
    }
}
