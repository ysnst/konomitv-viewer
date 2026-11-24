import SafariServices
import UIKit

/// 「ニコニコ実況」の設定画面。Web 版の設定 → ニコニコ実況 (Jikkyo.vue)
/// の並びに合わせたもの: ニコニコアカウントとの連携、可能であれば
/// ニコニコ実況にコメントする、コメント送信後にコメント入力フォームを
/// 閉じる、コメントのミュート設定への入口、コメントを表示、
/// コメントを無制限に表示、全画面でも盛り上がり波形を表示する、
/// コメントの不透明度、コメントの速さ、コメントの文字サイズ。
///
/// ニコニコ連携の認証情報はサーバー側が持ち、アプリは連携用の
/// ページをアプリ内ブラウザで開くだけで、認証情報を持たない。
/// 「コメントを表示」「無制限に表示」「不透明度」は Web 版でも端末
/// ごとに持つ項目 (同期の対象外) で、アプリでも端末に保存する。
/// 「全画面でも盛り上がり波形を表示する」はアプリ側の項目で、
/// こちらも端末に保存する (同期の対象外)。
/// 連携以外の項目とミュート設定は利用者設定と共通で、
/// 読み書きは SyncedSettingsStore が担う。
/// 変更はその場で保存され、次に再生を始めるときから効く。
final class JikkyoSettingsViewController: SettingsDetailViewController {
    private let niconicoStatusLabel = UILabel()
    private let niconicoDescriptionLabel = UILabel()
    private let niconicoActionButton = RippleButton()
    private let preferSwitch = WebToggle()
    private let closeFormSwitch = WebToggle()
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
        refreshNiconicoState()
    }

    private func buildItems() {
        // ニコニコ連携のまとまり (状態の文 + 説明 + ボタン)。
        niconicoStatusLabel.font = .scaledSystemFont(ofSize: 14.5, weight: .medium)
        niconicoStatusLabel.textColor = AppPalette.text
        niconicoStatusLabel.numberOfLines = 0
        niconicoDescriptionLabel.font = .scaledSystemFont(ofSize: 13.5)
        niconicoDescriptionLabel.textColor = AppPalette.metaText
        niconicoDescriptionLabel.numberOfLines = 0
        niconicoActionButton.addTarget(
            self, action: #selector(niconicoActionTapped), for: .touchUpInside)
        styleActionButton(niconicoActionButton)
        let niconicoField = UIStackView(arrangedSubviews: [
            niconicoStatusLabel, niconicoDescriptionLabel, niconicoActionButton,
        ])
        niconicoField.axis = .vertical
        niconicoField.spacing = 14
        preferSwitch.addTarget(self, action: #selector(preferChanged), for: .valueChanged)
        closeFormSwitch.addTarget(self, action: #selector(closeFormChanged), for: .valueChanged)
        refreshNiconicoState()
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

        // 並びは本家 (Jikkyo.vue) に合わせ、ニコニコ連携と投稿の
        // 設定を先頭に置き、続けてミュート設定、表示の項目を並べる。
        for view in [
            itemGroup(title: "ニコニコアカウントとの連携", field: niconicoField),
            itemGroup(title: "可能であればニコニコ実況にコメントする", field: makeSwitchRow(
                text: "オンにすると、ニコニコ実況にコメントできる場合はニコニコ実況へ、できない場合は NX-Jikkyo へコメントします。オフにすると、常に NX-Jikkyo へコメントします。",
                toggle: preferSwitch)),
            itemGroup(title: "コメント送信後にコメント入力フォームを閉じる", field: makeSwitchRow(
                text: "オンにすると、生放送のコメントを送信したあとに、コメントの入力欄 (キーボード) を自動で閉じます。",
                toggle: closeFormSwitch)),
            makeDivider(),
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
        preferSwitch.isOn = synced.preferPostingToNicolive
        closeFormSwitch.isOn = synced.closeCommentFormAfterSending
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

    // MARK: - ニコニコ連携

    /// 連携の状態 (未ログイン/確認中/未連携/連携済み)。
    private enum NiconicoLinkState {
        case notLoggedIn
        case loading
        case unlinked
        case linked(name: String)
        /// 状態確認自体が失敗したとき (連携しているかどうか分からない)。
        case checkFailed
    }
    private var niconicoState: NiconicoLinkState = .loading {
        didSet { applyNiconicoState() }
    }

    /// サーバーからユーザー情報を取り直して、連携の状態を更新する。
    private var niconicoRefreshGeneration = 0

    private func refreshNiconicoState() {
        niconicoRefreshGeneration += 1
        let generation = niconicoRefreshGeneration
        guard SettingsStore.shared.isLoggedIn else {
            niconicoState = .notLoggedIn
            return
        }
        niconicoState = .loading
        Task { [weak self] in
            do {
                let user = try await APIClient.shared.fetchCurrentUser()
                guard let self, generation == self.niconicoRefreshGeneration else { return }
                if let userID = user.niconico_user_id {
                    let name = user.niconico_user_name ?? "\(userID)"
                    self.niconicoState = .linked(name: name)
                } else {
                    self.niconicoState = .unlinked
                }
            } catch {
                guard let self, generation == self.niconicoRefreshGeneration else { return }
                // 確認できなかっただけでは「未連携」とは言えない。
                // 連携済みの人が不要な連携のやり直しを始めないよう、
                // 失敗と分かる表示に分ける。
                self.niconicoState = .checkFailed
            }
        }
    }

    /// 連携の状態を、文とボタンへ反映する。
    private func applyNiconicoState() {
        switch niconicoState {
        case .notLoggedIn:
            niconicoStatusLabel.text = "ログインしていません"
            niconicoDescriptionLabel.text = "ニコニコアカウントとの連携には、アプリへのログインが必要です。"
            niconicoActionButton.isHidden = true
        case .loading:
            niconicoStatusLabel.text = "連携の状態を確認中…"
            niconicoDescriptionLabel.text = nil
            niconicoActionButton.isHidden = true
        case .unlinked:
            niconicoStatusLabel.text = "ニコニコアカウントと連携していません"
            niconicoDescriptionLabel.text = "ニコニコアカウントと連携すると、テレビを見ながらニコニコ実況にコメントできるようになります。"
            niconicoActionButton.setTitle("ニコニコアカウントと連携する", for: .normal)
            niconicoActionButton.isHidden = false
        case .linked(let name):
            niconicoStatusLabel.text = "\(name) と連携しています"
            niconicoDescriptionLabel.text = "連携を解除すると、コメントは NX-Jikkyo への投稿に戻ります。"
            niconicoActionButton.setTitle("連携を解除する", for: .normal)
            niconicoActionButton.isHidden = false
        case .checkFailed:
            niconicoStatusLabel.text = "連携の状態を確認できませんでした"
            niconicoDescriptionLabel.text = "通信に失敗しました。接続先とネットワークを確認して、画面を開き直してください。"
            niconicoActionButton.isHidden = true
        }
    }

    @objc private func niconicoActionTapped() {
        switch niconicoState {
        case .unlinked:
            openNiconicoAuth()
        case .linked:
            confirmNiconicoLogout()
        case .notLoggedIn, .loading, .checkFailed:
            break
        }
    }

    /// 連携用のページをアプリ内ブラウザで開く。認証情報はサーバー側が
    /// 持ち、アプリはページを開くだけ (パスワード等は扱わない)。
    private func openNiconicoAuth() {
        Task { [weak self] in
            do {
                let urlString = try await APIClient.shared.fetchNiconicoAuthURL()
                guard let self, let url = URL(string: urlString) else { return }
                let browser = SFSafariViewController(url: url)
                browser.delegate = self
                self.present(browser, animated: true)
            } catch {
                self?.showNiconicoError("連携用のページを開けませんでした。")
            }
        }
    }

    private func confirmNiconicoLogout() {
        let alert = UIAlertController(
            title: "ニコニコアカウントとの連携を解除しますか？",
            message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "連携を解除する", style: .destructive) { [weak self] _ in
            Task { [weak self] in
                do {
                    try await APIClient.shared.logoutNiconico()
                    self?.refreshNiconicoState()
                } catch {
                    self?.showNiconicoError("連携を解除できませんでした。")
                }
            }
        })
        present(alert, animated: true)
    }

    private func showNiconicoError(_ message: String) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func preferChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.preferPostingToNicolive = preferSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func closeFormChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.closeCommentFormAfterSending = closeFormSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
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

extension JikkyoSettingsViewController: SFSafariViewControllerDelegate {
    /// 連携用のブラウザを閉じたら、連携の状態を取り直す。
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        refreshNiconicoState()
    }
}
