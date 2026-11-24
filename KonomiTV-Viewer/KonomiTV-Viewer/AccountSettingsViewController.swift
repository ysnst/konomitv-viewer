import UIKit

/// 「アカウント」の設定画面。Web 版の設定 → アカウント (Account.vue)
/// の並びに合わせたもの: アカウントのカード (アイコン・名前・User ID・
/// ログアウトボタン入り)、設定をデバイス間で同期する、ユーザー名の
/// 変更、新しいパスワードの設定。
///
/// ログインの仕組み自体はこれまでのもの (ユーザー名とパスワードで
/// トークンを取り、パスワードはキーチェーンに保存) をそのまま使う。
/// これまで「このアプリの設定」にあったログイン欄と同期のスイッチは、
/// Web 版の分類に合わせてこちらへ移した。
/// アイコン画像の変更とアカウントの削除は、アプリではまだ入れていない。
final class AccountSettingsViewController: SettingsDetailViewController {
    // ログイン前
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = RippleButton()
    private var loginFormGroup: UIStackView?
    // ログイン後
    private let userIconView = UIImageView()
    private let userNameLabel = UILabel()
    private let userAdminLabel = UILabel()
    private let userIDLabel = UILabel()
    private var userInfoGroup: UIView?
    private let logoutButton = RippleButton()
    private let newUsernameField = UITextField()
    private let updateUsernameButton = RippleButton()
    private var usernameEditGroup: UIStackView?
    private let newPasswordField = UITextField()
    private let updatePasswordButton = RippleButton()
    private var passwordEditGroup: UIStackView?
    // 共通
    private let syncSettingsSwitch = WebToggle()
    private let statusLabel = UILabel()

    init() {
        super.init(headingTitle: "アカウント")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadValues()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func buildItems() {
        // ログイン前の入力欄。
        styleTextField(usernameField, placeholder: "ユーザー名")
        usernameField.keyboardType = .asciiCapable
        usernameField.textContentType = .username
        styleTextField(passwordField, placeholder: "パスワード")
        passwordField.keyboardType = .asciiCapable
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        loginButton.setTitle("ログイン", for: .normal)
        loginButton.addTarget(self, action: #selector(login), for: .touchUpInside)
        styleActionButton(loginButton)
        let loginForm = UIStackView(arrangedSubviews: [
            itemGroup(title: "KonomiTV ユーザー名", field: usernameField),
            itemGroup(title: "KonomiTV パスワード", field: passwordField),
            loginButton,
        ])
        loginForm.axis = .vertical
        loginForm.spacing = 24
        loginFormGroup = loginForm

        // ログイン後のユーザー表示 (アイコン + ユーザー名 + 管理者バッジ)。
        userIconView.backgroundColor = AppPalette.placeholder
        userIconView.contentMode = .scaleAspectFill
        userIconView.clipsToBounds = true
        userIconView.layer.cornerRadius = 20
        userIconView.translatesAutoresizingMaskIntoConstraints = false
        userIconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        userIconView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        userNameLabel.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        userNameLabel.textColor = AppPalette.text
        userAdminLabel.text = "管理者"
        userAdminLabel.font = .scaledSystemFont(ofSize: 11)
        userAdminLabel.textColor = .white
        userAdminLabel.textAlignment = .center
        userAdminLabel.backgroundColor = AppPalette.secondary
        userAdminLabel.layer.cornerRadius = 4
        userAdminLabel.clipsToBounds = true
        userAdminLabel.translatesAutoresizingMaskIntoConstraints = false
        userAdminLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        userAdminLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true
        userIDLabel.font = .scaledSystemFont(ofSize: 12.5)
        userIDLabel.textColor = AppPalette.secondaryText
        let nameRow = UIStackView(arrangedSubviews: [userNameLabel, userAdminLabel, UIView()])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 8
        let nameStack = UIStackView(arrangedSubviews: [nameRow, userIDLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 3
        let userRow = UIStackView(arrangedSubviews: [userIconView, nameStack])
        userRow.axis = .horizontal
        userRow.alignment = .center
        userRow.spacing = 12
        // ログアウトボタンは本家と同じくカードの中に収め、
        // 目立つ色 (secondary) の地にする。
        logoutButton.setTitle("ログアウト", for: .normal)
        logoutButton.addTarget(self, action: #selector(logout), for: .touchUpInside)
        logoutButton.backgroundColor = AppPalette.secondary
        logoutButton.setTitleColor(.white, for: .normal)
        logoutButton.titleLabel?.font = .scaledSystemFont(ofSize: 14.5, weight: .medium)
        logoutButton.layer.cornerRadius = 4
        logoutButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        logoutButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let logoutRow = UIStackView(arrangedSubviews: [UIView(), logoutButton])
        logoutRow.axis = .horizontal
        let cardStack = UIStackView(arrangedSubviews: [userRow, logoutRow])
        cardStack.axis = .vertical
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        let userInfo = UIView()
        userInfo.backgroundColor = AppPalette.panel
        userInfo.layer.cornerRadius = 8
        userInfo.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: userInfo.topAnchor, constant: 16),
            cardStack.leadingAnchor.constraint(equalTo: userInfo.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: userInfo.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: userInfo.bottomAnchor, constant: -16),
        ])
        userInfoGroup = userInfo

        // ユーザー名の変更。
        styleTextField(newUsernameField, placeholder: "ユーザー名")
        newUsernameField.textContentType = .username
        updateUsernameButton.setTitle("ユーザー名を更新", for: .normal)
        updateUsernameButton.addTarget(self, action: #selector(updateUsername), for: .touchUpInside)
        styleActionButton(updateUsernameButton)
        let usernameEditField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("KonomiTV アカウントのユーザー名を設定します。アルファベットだけでなく日本語や記号も使えます。同じ KonomiTV サーバー上の他のアカウントと同じユーザー名には変更できません。"),
            newUsernameField,
            updateUsernameButton,
        ])
        usernameEditField.axis = .vertical
        usernameEditField.spacing = 14
        let usernameEdit = itemGroup(title: "ユーザー名", field: usernameEditField)
        usernameEditGroup = usernameEdit

        // パスワードの変更。
        styleTextField(newPasswordField, placeholder: "新しいパスワード")
        newPasswordField.isSecureTextEntry = true
        newPasswordField.textContentType = .newPassword
        updatePasswordButton.setTitle("パスワードを更新", for: .normal)
        updatePasswordButton.addTarget(self, action: #selector(updatePassword), for: .touchUpInside)
        styleActionButton(updatePasswordButton)
        let passwordEditField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("KonomiTV アカウントの新しいパスワードを設定します。"),
            newPasswordField,
            updatePasswordButton,
        ])
        passwordEditField.axis = .vertical
        passwordEditField.spacing = 14
        let passwordEdit = itemGroup(title: "新しいパスワード", field: passwordEditField)
        passwordEditGroup = passwordEdit

        // 設定をデバイス間で同期する (Web 版の sync_settings に相当)。
        // 切り替えはその場で保存する。
        syncSettingsSwitch.addTarget(
            self, action: #selector(syncSettingsChanged), for: .valueChanged)
        let syncGroup = itemGroup(title: "設定をデバイス間で同期する", field: makeSwitchRow(
            text: "オンにすると、視聴履歴などの設定をサーバーに保存して Web 版など他の端末と共通にします。録画の続きから再開する位置も、Web 版と共通になります。",
            toggle: syncSettingsSwitch))

        statusLabel.font = .scaledSystemFont(ofSize: 13.5)
        statusLabel.textColor = AppPalette.metaText
        statusLabel.numberOfLines = 0

        // 並びは本家 (Account.vue) に合わせる: カード → 同期 →
        // ユーザー名 → 新しいパスワード。
        for view in [
            makeDescriptionLabel(AppEdition.protectionEnabled
                ? "KonomiTV アカウントにログインすると、録画の保護の切り替えや、設定・視聴履歴のデバイス間同期が使えるようになります。"
                : "KonomiTV アカウントにログインすると、設定・視聴履歴のデバイス間同期が使えるようになります。"),
            loginForm,
            userInfo,
            syncGroup,
            usernameEdit,
            passwordEdit,
            statusLabel,
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    // MARK: - 表示の更新

    private func loadValues() {
        let store = SettingsStore.shared
        usernameField.text = store.username
        passwordField.text = store.password
        syncSettingsSwitch.isOn = store.syncSettings
        updateLoginUI()
        if store.isLoggedIn {
            refreshUserInfo()
        }
    }

    private func updateLoginUI() {
        let loggedIn = SettingsStore.shared.isLoggedIn
        loginFormGroup?.isHidden = loggedIn
        userInfoGroup?.isHidden = !loggedIn
        usernameEditGroup?.isHidden = !loggedIn
        passwordEditGroup?.isHidden = !loggedIn
        // 同期はログインが前提なので、未ログインの間は操作できないようにする。
        syncSettingsSwitch.isEnabled = loggedIn
        if loggedIn {
            userNameLabel.text = SettingsStore.shared.username
            newUsernameField.text = SettingsStore.shared.username
        }
    }

    /// サーバーからユーザー情報を取り直して、表示 (名前・管理者・
    /// アイコン) に反映する。取れなければ保存済みのユーザー名で受ける。
    private func refreshUserInfo() {
        Task { [weak self] in
            guard let self else { return }
            if let user = try? await APIClient.shared.fetchCurrentUser() {
                self.userNameLabel.text = user.name
                self.userAdminLabel.isHidden = !user.is_admin
                self.userIDLabel.text = "User ID: \(user.id)"
                SettingsStore.shared.username = user.name
            }
            if let iconData = try? await APIClient.shared.fetchCurrentUserIcon(),
               let image = UIImage(data: iconData) {
                self.userIconView.image = image
            }
        }
    }

    // MARK: - 操作

    @objc private func login() {
        let username = (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            statusLabel.text = "ユーザー名とパスワードを入力してください。"
            return
        }
        guard SettingsStore.shared.isConfigured else {
            statusLabel.text = "先に「このアプリの設定」で KonomiTV の URL を入力してください。"
            return
        }
        view.endEditing(true)
        loginButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.login(username: username, password: password)
                self.statusLabel.text = "ログインしました。"
            } catch {
                self.statusLabel.text = "ログインできませんでした。ユーザー名とパスワード、接続先を確認してください。"
            }
            self.loginButton.isEnabled = true
            self.updateLoginUI()
            if SettingsStore.shared.isLoggedIn {
                self.refreshUserInfo()
            }
        }
    }

    @objc private func logout() {
        SettingsStore.shared.clearLogin()
        passwordField.text = ""
        userIconView.image = nil
        userIDLabel.text = nil
        updateLoginUI()
        statusLabel.text = "ログアウトしました。"
    }

    @objc private func updateUsername() {
        let username = (newUsernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            statusLabel.text = "ユーザー名を入力してください。"
            return
        }
        view.endEditing(true)
        updateUsernameButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.updateCurrentUser(username: username, password: nil)
                SettingsStore.shared.username = username
                self.userNameLabel.text = username
                self.statusLabel.text = "ユーザー名を更新しました。"
            } catch {
                self.statusLabel.text = "ユーザー名を更新できませんでした。すでに使われているユーザー名かもしれません。"
            }
            self.updateUsernameButton.isEnabled = true
        }
    }

    @objc private func updatePassword() {
        let password = newPasswordField.text ?? ""
        guard !password.isEmpty else {
            statusLabel.text = "新しいパスワードを入力してください。"
            return
        }
        view.endEditing(true)
        updatePasswordButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.updateCurrentUser(username: nil, password: password)
                // 次回のログインで使えるよう、保存済みのパスワードも差し替える。
                SettingsStore.shared.password = password
                self.newPasswordField.text = ""
                self.statusLabel.text = "パスワードを更新しました。"
            } catch {
                self.statusLabel.text = "パスワードを更新できませんでした。"
            }
            self.updatePasswordButton.isEnabled = true
        }
    }

    /// 同期の切り替えはその場で保存する (「保存」ボタンは待たない)。
    @objc private func syncSettingsChanged() {
        SettingsStore.shared.syncSettings = syncSettingsSwitch.isOn
        // 同期を入れた直後は、サーバー側の値を取り込んでおく。
        if syncSettingsSwitch.isOn {
            Task {
                _ = await SyncedSettingsStore.shared.refreshFromServer()
                _ = await TimeTableSettingsStore.shared.refreshFromServer()
            }
        }
    }
}
