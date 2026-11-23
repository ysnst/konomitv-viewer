import UIKit

/// 接続先 URL と Cloudflare Access のサービストークン、KonomiTV ログインを設定する画面。
/// 画質まわりは別画面 (「画質」) に分け、入口は設定の分類一覧
/// (SettingsCategoryViewController) 側に置く (この画面と重複させない)。
/// 初回起動時 (URL 未設定) の入力画面と、分類一覧の「このアプリの設定」の先で使う。
/// ログインと「設定をデバイス間で同期する」は、分類一覧から開いたときは
/// 「アカウント」の画面 (AccountSettingsViewController) へ移したため
/// ここでは出さない。初回入力のときだけ、この画面にも出す。
///
/// 見た目は Web 版の設定詳細画面 (views/Settings/Base.vue のスマホ縦) に
/// 合わせてある: 画面地はテーマの background、上部に高さ 60px・地が
/// background-lighten-1 の見出し帯、項目は「見出し (16.5px) → 14px 空けて
/// 入力欄」の並び、項目どうしの間隔は 24px、グループの区切りは
/// background-lighten-2 の 2px 線、ボタンは高さ 45px・地が
/// background-lighten-2。項目そのものはアプリ専用のまま変えていない。
final class SettingsViewController: UIViewController {
    enum Mode {
        case setup  // 初回入力用。保存できたら onComplete が呼ばれる。
        case tab    // 設定タブ用。
    }

    private let mode: Mode
    private let onComplete: (() -> Void)?

    private let urlField = UITextField()
    private let cfIDField = UITextField()
    private let cfSecretField = UITextField()
    private let statusLabel = UILabel()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = RippleButton()
    private let logoutButton = RippleButton()
    private let loginStatusLabel = UILabel()
    /// 「設定をデバイス間で同期する」のスイッチ (Web 版の sync_settings に相当)。
    private let syncSettingsSwitch = WebToggle()
    /// 見出し帯の戻るボタン。マイページから押し込まれたときだけ出す
    /// (この画面はナビゲーションバーを隠すため、帯側で戻り口を用意する)。
    private let backButton = RippleButton()

    /// リターンキーで移動する順番の入力欄。
    private var orderedFields: [UITextField] {
        [urlField, cfIDField, cfSecretField, usernameField, passwordField]
    }

    // ログイン状態で出し分けるため、ユーザー名とパスワードの欄のグループを保持する。
    private var usernameFieldGroup: UIStackView?
    private var passwordFieldGroup: UIStackView?
    /// ログインと同期まわりの表示物のまとまり。分類一覧から開いたときは
    /// 「アカウント」の画面へ移したため、まとめて隠すのに使う。
    private var accountRelatedViews: [UIView] = []

    /// 入力欄が実際に表示されているか (欄そのものと、欄を含むグループの両方を見る)。
    private func isShown(_ field: UITextField) -> Bool {
        !field.isHidden && !(field.superview?.isHidden ?? false)
    }

    /// 表示中の入力欄の並びに合わせて、リターンキーの表示 (次へ／完了) を付け直す。
    private func refreshReturnKeyTypes() {
        let visible = orderedFields.filter { isShown($0) }
        for (index, field) in visible.enumerated() {
            field.returnKeyType = index + 1 < visible.count ? .next : .done
        }
    }

    init(mode: Mode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        // この画面ではナビゲーションバーを隠すため見出しには出ない (後述)。
        title = "設定"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        // 入力欄の外側をタップしたらキーボードを閉じる (ボタン等の操作は妨げない)。
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        // 左端からの横スワイプでも前の画面へ戻れるようにする
        // (先頭の画面として出ているときは戻り先が無く、押しても何も起きない)。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// 見出し帯の戻るボタン (マイページから押し込まれたときだけ表示される)。
    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Web 版のスマホ縦では、設定系のページは上部のヘッダー自体が出ない
        // (SPHeaderBar の hide-on-smartphone-vertical)。それに合わせ、
        // この画面ではナビゲーションバーを隠し、代わりのヘッダーも置かない。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 戻るボタンは、タブの先頭画面ではなく押し込まれた先として
        // 開かれたときだけ出す。
        backButton.isHidden = navigationController?.viewControllers.first === self
        // 設定アプリ側で変更された場合も含め、現在の保存値を表示する。
        loadValues()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 隠すのはこの画面の間だけ。遷移先ではナビゲーションバーを元に戻す。
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - 見た目の部品 (Web 版の設定画面の値)

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

    /// グループの区切り線 (2px、background-lighten-2)。
    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AppPalette.pressed
        divider.heightAnchor.constraint(equalToConstant: 2).isActive = true
        return divider
    }

    /// 固定の高さの余白 (項目内の見出しと入力欄の間隔などに使う)。
    private func makeSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    /// Web 版の保存ボタンと同じ形 (高さ 45px、地は background-lighten-2、
    /// 文字 15.5px、角丸 4px) をボタンに付ける。
    private func styleActionButton(_ button: UIButton) {
        button.backgroundColor = AppPalette.pressed
        button.setTitleColor(AppPalette.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15.5)
        button.layer.cornerRadius = 4
        button.heightAnchor.constraint(equalToConstant: 45).isActive = true
    }

    /// 設定項目1つ分のまとまり。Web 版の並び (見出し → 14px 空けて入力欄)。
    private func itemGroup(title: String, field: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [
            makeItemHeading(title),
            makeSpacer(14),
            field,
        ])
        stack.axis = .vertical
        return stack
    }

    private func buildLayout() {
        // 上部の見出し帯。Web 版の設定詳細画面 (スマホ縦) では、画面上部に
        // 高さ 60px・地が background-lighten-1 の帯が固定され、ページ名が
        // 22px で出る (帯には下向きの薄い影も付く)。それに合わせた自前の
        // 帯を置く。Web 版の帯には戻るボタンもあり、マイページから
        // 押し込まれたときはそれに合わせて帯の左に戻るボタンを出す
        // (先頭画面として開かれたときは戻り先が無いため出さない)。
        let headingBar = UIView()
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        // 初回の入力画面では「設定」、分類一覧から開いたときは分類名を出す。
        headingLabel.text = mode == .setup ? "設定" : "このアプリの設定"
        headingLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        // 戻るボタンは本家に合わせて矢印だけ (文字は付けない)。
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.isHidden = true
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)

        let note = makeDescriptionLabel(
            "KonomiTV サーバーの URL を入力してください。Cloudflare Access のサービストークンは、外から接続する場合に必要です (任意)。")

        configure(urlField, placeholder: "https://example.com:7000", keyboard: .URL)
        configure(cfIDField, placeholder: "Client ID", keyboard: .asciiCapable)
        configure(cfSecretField, placeholder: "Client Secret", keyboard: .asciiCapable)
        cfSecretField.isSecureTextEntry = true

        // リターンキーの表示は、表示中の欄に合わせて refreshReturnKeyTypes() で付ける。

        // KonomiTV ログイン (保護の切り替えに必要)。パスワードはキーチェーンに保存される。
        configure(usernameField, placeholder: "ユーザー名", keyboard: .asciiCapable)
        configure(passwordField, placeholder: "パスワード", keyboard: .asciiCapable)
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password

        loginButton.setTitle("ログイン", for: .normal)
        loginButton.addTarget(self, action: #selector(login), for: .touchUpInside)
        styleActionButton(loginButton)
        logoutButton.setTitle("ログアウト", for: .normal)
        logoutButton.addTarget(self, action: #selector(logout), for: .touchUpInside)
        styleActionButton(logoutButton)

        loginStatusLabel.font = .systemFont(ofSize: 13.5)
        loginStatusLabel.textColor = AppPalette.metaText
        loginStatusLabel.numberOfLines = 0

        let saveButton = RippleButton()
        saveButton.setTitle(mode == .setup ? "保存して開始" : "保存", for: .normal)
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        styleActionButton(saveButton)

        statusLabel.font = .systemFont(ofSize: 13.5)
        statusLabel.textColor = AppPalette.metaText
        statusLabel.numberOfLines = 0

        // 一般版では保護の機能が無いので、ログインの目的は設定の同期だけになる。
        let usernameGroup = itemGroup(
            title: AppEdition.isHousehold ? "KonomiTV ユーザー名 (保護の切り替え用)" : "KonomiTV ユーザー名",
            field: usernameField)
        let passwordGroup = itemGroup(title: "KonomiTV パスワード", field: passwordField)
        usernameFieldGroup = usernameGroup
        passwordFieldGroup = passwordGroup

        // 設定をデバイス間で同期する (Web 版の sync_settings に相当)。
        // オンで視聴履歴などの利用者設定がサーバー経由で Web 版と共通になり、
        // 録画の再開位置も Web 版と共通の視聴履歴から取るようになる。
        // 切り替えはその場で保存する (画質画面の作りと同じ)。
        // ログインが前提なので、未ログインの間は操作できないようにする
        // (出し分けは updateLoginUI で行う)。
        syncSettingsSwitch.addTarget(
            self, action: #selector(syncSettingsChanged), for: .valueChanged)
        // 説明文とスイッチの行は、画質画面のスイッチ行と同じ直しを
        // 入れる: 文の横方向の圧縮への強さを下げ、スイッチ側を固定にして、
        // 文が残りの幅で折り返し、スイッチが右端の外へ押し出されないようにする。
        let syncDescription = makeDescriptionLabel("オンにすると、視聴履歴などの設定をサーバーに保存して Web 版など他の端末と共通にします。録画の続きから再開する位置も、Web 版と共通になります。")
        syncDescription.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        syncDescription.setContentHuggingPriority(.defaultLow, for: .horizontal)
        syncSettingsSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)
        syncSettingsSwitch.setContentHuggingPriority(.required, for: .horizontal)
        let syncRow = UIStackView(arrangedSubviews: [
            syncDescription,
            syncSettingsSwitch,
        ])
        syncRow.axis = .horizontal
        syncRow.alignment = .center
        syncRow.spacing = 12
        let syncGroup = itemGroup(title: "設定をデバイス間で同期する", field: syncRow)

        // 項目どうしの間隔は Web 版の項目の margin-top と同じ 24px。
        // 接続先のグループとログインのグループの間には区切り線を引く。
        let connectionDivider = makeDivider()
        let stack = UIStackView(arrangedSubviews: [
            note,
            itemGroup(title: "KonomiTV の URL", field: urlField),
            itemGroup(title: "Access Client ID (任意)", field: cfIDField),
            itemGroup(title: "Access Client Secret (任意)", field: cfSecretField),
            connectionDivider,
            usernameGroup,
            passwordGroup,
            loginButton,
            logoutButton,
            loginStatusLabel,
            syncGroup,
            makeDivider(),
            saveButton,
            statusLabel,
        ])
        accountRelatedViews = [
            connectionDivider, usernameGroup, passwordGroup,
            loginButton, logoutButton, loginStatusLabel, syncGroup,
        ]
        if mode == .tab {
            // ログインと同期は「アカウント」の画面へ移したため、
            // 分類一覧から開いたときはここでは出さない。
            accountRelatedViews.forEach { $0.isHidden = true }
        }
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
            // 中身の余白は Web 版のスマホ縦と同じ左右 16px、上は説明文の
            // margin-top に合わせて 24px。
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        refreshReturnKeyTypes()
    }

    private func configure(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        // Web 版の入力欄 (Vuetify の outlined) に合わせ、地はページ地と
        // 同じ、枠線は background-lighten-3、角丸 4px の箱にする。
        field.borderStyle = .none
        field.backgroundColor = AppPalette.background
        field.layer.borderWidth = 1
        field.layer.borderColor = AppPalette.fieldBorder.cgColor
        field.layer.cornerRadius = 4
        field.textColor = AppPalette.text
        field.font = .systemFont(ofSize: 16)
        field.tintColor = AppPalette.accent
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: AppPalette.secondaryText])
        // 枠の内側に左 12px の余白を作る。
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.delegate = self
    }

    private func loadValues() {
        let store = SettingsStore.shared
        urlField.text = store.rawURLString
        cfIDField.text = store.cfClientID
        cfSecretField.text = store.cfClientSecret
        usernameField.text = store.username
        passwordField.text = store.password
        syncSettingsSwitch.isOn = store.syncSettings
        updateLoginUI()
    }

    private func updateLoginUI() {
        let store = SettingsStore.shared
        let loggedIn = store.isLoggedIn
        if loggedIn {
            loginStatusLabel.text = "ログイン中: \(store.username)"
        } else {
            loginStatusLabel.text = AppEdition.isHousehold
                ? "未ログインです。保護の切り替えにはログインが必要です。"
                : "未ログインです。設定の同期にはログインが必要です。"
        }
        // ログイン中は入力欄と「ログイン」を隠し、「ログアウト」だけを出す。
        // 未ログインではその逆にする。
        usernameFieldGroup?.isHidden = loggedIn
        passwordFieldGroup?.isHidden = loggedIn
        loginButton.isHidden = loggedIn
        logoutButton.isHidden = !loggedIn
        // 同期はログインが前提なので、未ログインの間はスイッチを操作できないようにする。
        syncSettingsSwitch.isEnabled = loggedIn
        if mode == .tab {
            // 分類一覧から開いたときは、ログインと同期は「アカウント」の
            // 画面側の担当なので、上の出し分けに関わらず隠したままにする。
            accountRelatedViews.forEach { $0.isHidden = true }
        }
        // 隠れた欄はリターンキーの移動先からも外れるため、表示を付け直す。
        refreshReturnKeyTypes()
    }

    @objc private func login() {
        let username = (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            loginStatusLabel.text = "ユーザー名とパスワードを入力してください。"
            return
        }
        // ログインの前に接続先 URL を保存しておく (未保存のまま押された場合の取りこぼし防止)。
        let store = SettingsStore.shared
        store.rawURLString = urlField.text ?? ""
        guard store.isConfigured else {
            loginStatusLabel.text = "先に KonomiTV の URL を入力してください。"
            return
        }
        view.endEditing(true)
        loginButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.login(username: username, password: password)
                self.loginStatusLabel.text = "ログインしました。"
            } catch {
                self.loginStatusLabel.text = "ログインできませんでした。ユーザー名とパスワード、接続先を確認してください。"
            }
            self.loginButton.isEnabled = true
            self.updateLoginUI()
        }
    }

    @objc private func logout() {
        SettingsStore.shared.clearLogin()
        passwordField.text = ""
        updateLoginUI()
        loginStatusLabel.text = "ログアウトしました。"
    }

    /// 同期の切り替えはその場で保存する (「保存」ボタンは待たない)。
    @objc private func syncSettingsChanged() {
        SettingsStore.shared.syncSettings = syncSettingsSwitch.isOn
    }

    @objc private func save() {
        let store = SettingsStore.shared
        store.rawURLString = urlField.text ?? ""
        store.cfClientID = cfIDField.text ?? ""
        store.cfClientSecret = cfSecretField.text ?? ""
        view.endEditing(true)

        guard store.isConfigured else {
            statusLabel.text = "URL が正しくありません。入力を見直してください。"
            return
        }
        if mode == .setup {
            onComplete?()
        } else {
            statusLabel.text = "保存しました。"
        }
    }
}

extension SettingsViewController: UITextFieldDelegate {
    /// リターンキーで次の入力欄へ進み、最後の欄ではキーボードを閉じる。
    /// ログイン中で隠れている欄は移動先に含めない。
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let visible = orderedFields.filter { isShown($0) }
        if let index = visible.firstIndex(of: textField), index + 1 < visible.count {
            visible[index + 1].becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }
}
