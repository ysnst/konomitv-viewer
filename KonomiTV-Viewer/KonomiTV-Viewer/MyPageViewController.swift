import UIKit

/// マイページ化の第1回で作る、3つ目のタブの先頭画面。
/// Web 版のマイページ (client/src/views/MyPage.vue) のスマホ縦表示を写した
/// 「入口一覧」画面: アカウント表示のカード、その下に設定・マイリスト・
/// 視聴履歴の入口ボタン、一番下にバージョン表示 (アプリの版とサーバーの版)。
///
/// 実測値 (MyPage.vue、スマホ縦):
/// - 画面の余白は 16px、見出し「マイページ」は 24px (上に 8px の余白)
/// - アカウント表示: 地は background-lighten-1、角丸 6px、中の余白は
///   縦 16px・横 12px、アイコンは丸く 70px、名前は太字 20px、
///   管理者バッジは 45x24px・角丸 4px・地は secondary、
///   「User ID: 番号」は 14.5px・text-darken-1
/// - 入口ボタン: 高さ 54px、角丸 6px、地は background-lighten-1、
///   アイコン 26px + 16px 空けて文字 16px、ボタンの間隔は 6px
///   (マイリストとバージョンの前だけ 12px 多い)
/// - Web 版のスマホ縦では上部のロゴ帯 (SPHeaderBar) は出ないため、
///   この画面にも帯は置かず、見出しは中身の先頭に置く
///
/// 行き先: 「設定」は今の設定画面 (SettingsViewController) をそのまま押し込む。
/// 視聴履歴は専用画面 (WatchedHistoryViewController)、マイリストは専用画面
/// (MylistViewController) に繋ぐ。アカウント表示の
/// カードはアカウントの設定画面へ繋いである。
final class MyPageViewController: UIViewController {
    private let iconPhotoView = UIImageView()
    private let iconGlyphView = UIImageView()
    private let nameLabel = UILabel()
    private let adminBadge = UILabel()
    private let idLabel = UILabel()

    /// 取得できたアカウント情報。未ログイン・取得前は nil。
    private var currentUser: UserInfo?

    /// サーバーの版の行。開くたびに取り直して文字を差し替えるため保持する。
    private var serverVersionRow: EntryButtonView?

    /// App version の行のタップ回数 (拡張オプションの区分の解放用)。
    /// 解放できたら数え直す。解放の状態そのものは端末ごとに保存される。
    private var appVersionTapCount = 0
    /// 最後に App version の行をタップした時刻 (間が空いたら数え直し)。
    private var appVersionLastTapAt: Date?
    /// 短い知らせ (解放までの残り回数・解放の完了) を出している間の保持。
    private var briefNoticeView: UIView?
    private var briefNoticeLabel: UILabel?
    private var briefNoticeGeneration = 0

    init() {
        super.init(nibName: nil, bundle: nil)
        // ナビゲーションバーは隠すため見出しには出ないが、押し込んだ先の
        // 戻るボタンの文字として残る。
        title = "マイページ"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        showLoggedOut()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Web 版のスマホ縦ではマイページに上部の帯は出ない。それに合わせ、
        // ナビゲーションバーは隠し、見出しは中身の先頭に置く (他のタブの
        // 先頭画面と同じ扱い)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // ログイン状態が設定画面側で変わっている場合もあるため、開くたびに取り直す。
        refreshAccount()
        // サーバーの版も、接続先が変わっている場合があるため開くたびに取り直す。
        refreshServerVersion()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 隠すのはこの画面の間だけ。遷移先ではナビゲーションバーを元に戻す。
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - 並び

    private func buildLayout() {
        // 見出し (24px、上に 8px の余白)。Web 版は h1 で太さの指定は無いが、
        // ブラウザの見出し既定に近い semibold で近似する (設定画面の見出し帯と同じ)。
        let heading = UILabel()
        heading.text = "マイページ"
        heading.font = .scaledSystemFont(ofSize: 24, weight: .semibold)
        heading.textColor = AppPalette.text

        let settingsButton = makeEntryButton(
            iconName: "ic_fluent_settings_20_regular", fallbackSystemName: "gearshape",
            title: "設定")
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let mylistButton = makeEntryButton(
            iconName: "ic_round_playlist_play", fallbackSystemName: "list.bullet",
            title: "マイリスト")
        mylistButton.addTarget(self, action: #selector(openMyList), for: .touchUpInside)
        let historyButton = makeEntryButton(
            iconName: "ic_fluent_history_20_regular", fallbackSystemName: "clock.arrow.circlepath",
            title: "視聴履歴")
        historyButton.addTarget(self, action: #selector(openWatchedHistory), for: .touchUpInside)

        // バージョン表示。Web 版のこの行は、サーバーと一体で配られる
        // クライアント自身の版を出す (言い回しは "version 番号")。
        // アプリでは、アプリ自身の版と接続中のサーバーの版は別物なので、
        // 2行に分けて出す。サーバーの版の行は押せない表示として置く。
        // アプリの版の行は行き先は無いが、「拡張オプション」の
        // 区分の解放用にタップを受け付ける (7回タップで解放。Android の
        // 開発者向けオプションと同じ出し方)。
        // アプリの版は、ビルド時にアプリへ入った値 (Info.plist の版) から取る。
        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let appVersionRow = makeEntryButton(
            iconName: "ic_fluent_info_20_regular", fallbackSystemName: "info.circle",
            title: "App version \(appVersion)")
        appVersionRow.addTarget(self, action: #selector(appVersionRowTapped), for: .touchUpInside)
        // サーバーの版は開くたびに取り直して差し替える (refreshServerVersion)。
        let serverVersionRow = makeEntryButton(
            iconName: "ic_fluent_info_20_regular", fallbackSystemName: "info.circle",
            title: "Server version 取得中…")
        serverVersionRow.isEnabled = false
        self.serverVersionRow = serverVersionRow

        // 版表示の真下に、使っている部品のライセンスへの入口を置く。
        let licenseButton = makeEntryButton(
            iconName: "ic_fluent_document_20_regular", fallbackSystemName: "doc.text",
            title: "ライセンス")
        licenseButton.addTarget(self, action: #selector(openLicenses), for: .touchUpInside)

        // 並びと間隔: 見出し → 24px 空けてアカウント表示 → 6px ごとに
        // 入口ボタン (マイリストとバージョンの前だけ 12px 多い)。
        let stack = UIStackView(arrangedSubviews: [
            heading,
            makeAccountCard(),
            settingsButton,
            mylistButton,
            historyButton,
            appVersionRow,
            serverVersionRow,
            licenseButton,
        ])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(24, after: heading)
        stack.setCustomSpacing(18, after: settingsButton)
        stack.setCustomSpacing(18, after: historyButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            // 中身の余白は Web 版のスマホ縦と同じ左右 16px。
            // 上は見出しの上の余白 8px ぶんを見て 16 + 8 とする。
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    /// アカウント表示のカード (地は background-lighten-1、角丸 6px)。
    /// 押すとアカウントの設定画面 (AccountSettingsViewController) へ進む。
    private func makeAccountCard() -> UIView {
        // 押したときの反応として、共通部品の波紋を出す (行き先の処理は
        // 付けられたタップのしぐさ側で行う)。
        let card = RippleSurfaceView()
        card.backgroundColor = AppPalette.panel
        card.layer.cornerRadius = 6
        card.rippleCornerRadius = 6

        // アイコン (丸、70px)。読み込まれるまでの地は Web 版では
        // グラデーションだが、ここでは background-lighten-2 のベタで近似する。
        // 写真が無い間は人の形の標準アイコンを薄く出す。
        let iconContainer = UIView()
        iconContainer.backgroundColor = AppPalette.pressed
        iconContainer.layer.cornerRadius = 35
        iconContainer.clipsToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconGlyphView.image = UIImage(systemName: "person.fill")?
            .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal)
        iconGlyphView.contentMode = .center
        iconGlyphView.translatesAutoresizingMaskIntoConstraints = false
        iconPhotoView.contentMode = .scaleAspectFill
        iconPhotoView.clipsToBounds = true
        iconPhotoView.isHidden = true
        iconPhotoView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconGlyphView)
        iconContainer.addSubview(iconPhotoView)

        // 名前 (太字 20px、1行、はみ出たら省略) と管理者バッジ (45x24px、
        // 角丸 4px、地は secondary、文字 11.5px)。
        nameLabel.font = .scaledSystemFont(ofSize: 20, weight: .bold)
        nameLabel.textColor = AppPalette.text
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        adminBadge.text = "管理者"
        adminBadge.font = .scaledSystemFont(ofSize: 11.5, weight: .medium)
        adminBadge.textColor = AppPalette.text
        adminBadge.textAlignment = .center
        adminBadge.backgroundColor = AppPalette.secondary
        adminBadge.layer.cornerRadius = 4
        adminBadge.clipsToBounds = true
        adminBadge.isHidden = true
        adminBadge.translatesAutoresizingMaskIntoConstraints = false
        let nameRow = UIStackView(arrangedSubviews: [nameLabel, adminBadge])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 10

        // 「User ID: 番号」(14.5px、text-darken-1、名前の 2px 下)。
        idLabel.font = .scaledSystemFont(ofSize: 14.5)
        idLabel.textColor = AppPalette.metaText

        let infoStack = UIStackView(arrangedSubviews: [nameRow, idLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconContainer)
        card.addSubview(infoStack)
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            iconContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconContainer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            iconContainer.widthAnchor.constraint(equalToConstant: 70),
            iconContainer.heightAnchor.constraint(equalToConstant: 70),
            iconGlyphView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconGlyphView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconGlyphView.widthAnchor.constraint(equalToConstant: 34),
            iconGlyphView.heightAnchor.constraint(equalToConstant: 34),
            iconPhotoView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconPhotoView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            iconPhotoView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            iconPhotoView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            infoStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            infoStack.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            adminBadge.widthAnchor.constraint(equalToConstant: 45),
            adminBadge.heightAnchor.constraint(equalToConstant: 24),
        ])

        // カード全体が押せる (行き先は今のところ「準備中」画面)。
        let tap = UITapGestureRecognizer(target: self, action: #selector(openAccount))
        card.addGestureRecognizer(tap)
        return card
    }

    /// 入口ボタン1つ分 (高さ 54px、角丸 6px、地は background-lighten-1、
    /// アイコン 26px + 16px 空けて文字 16px)。
    /// アイコンは Web 版と同じ素材 (Fluent 公式 / Iconify の ic) を
    /// Assets.xcassets に取り込んだもので、色は文字色に合わせる。
    private func makeEntryButton(iconName: String, fallbackSystemName: String, title: String) -> EntryButtonView {
        let image = (UIImage(named: iconName)
            ?? UIImage(systemName: fallbackSystemName))?
            .withRenderingMode(.alwaysTemplate)
        let button = EntryButtonView(icon: image, title: title)
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    // MARK: - アカウント表示の更新

    /// ログインしていれば GET /api/users/me で取り直して表示する。
    /// 未ログインなら、その旨の表示にする (設定の入口はそのまま使える)。
    private var accountRefreshGeneration = 0
    private var serverVersionRefreshGeneration = 0

    private func refreshAccount() {
        accountRefreshGeneration += 1
        let generation = accountRefreshGeneration
        guard SettingsStore.shared.isLoggedIn else {
            currentUser = nil
            showLoggedOut()
            return
        }
        Task { [weak self] in
            guard let self, generation == self.accountRefreshGeneration else { return }
            do {
                let user = try await APIClient.shared.fetchCurrentUser()
                guard generation == self.accountRefreshGeneration else { return }
                self.currentUser = user
                self.nameLabel.text = user.name
                self.adminBadge.isHidden = !user.is_admin
                self.idLabel.text = "User ID: \(user.id)"
                self.idLabel.isHidden = false
                // アイコンは取れたら差し替える。失敗したら placeholder のまま。
                if let data = try? await APIClient.shared.fetchCurrentUserIcon(),
                   let image = UIImage(data: data) {
                    self.iconPhotoView.image = image
                    self.iconPhotoView.isHidden = false
                    self.iconGlyphView.isHidden = true
                }
            } catch {
                guard generation == self.accountRefreshGeneration else { return }
                // 期限切れ・接続不可などで取れなかったときは、保存済みの
                // ユーザー名だけ出して ID は出さない (「未ログイン」と
                // 決めつけると、単なる接続失敗のときに誤解を招くため)。
                self.currentUser = nil
                let stored = SettingsStore.shared.username
                self.nameLabel.text = stored.isEmpty ? "ログインしていません" : stored
                self.adminBadge.isHidden = true
                self.idLabel.isHidden = true
                self.iconPhotoView.isHidden = true
                self.iconGlyphView.isHidden = false
            }
        }
    }

    /// 接続中のサーバーの版を取り直して、サーバーの版の行に反映する。
    /// バージョン情報の取得口はログイン不要なので、未ログインでも取れる。
    /// 取れなかったとき (接続先未設定・接続失敗など) は、その旨の控えめな
    /// 表示にする。アプリの版の行はそのまま残る。
    private func refreshServerVersion() {
        serverVersionRefreshGeneration += 1
        let generation = serverVersionRefreshGeneration
        Task { [weak self] in
            guard let self else { return }
            if let version = await APIClient.shared.fetchServerVersion() {
                guard generation == self.serverVersionRefreshGeneration else { return }
                self.serverVersionRow?.updateTitle("Server version \(version)")
            } else {
                guard generation == self.serverVersionRefreshGeneration else { return }
                self.serverVersionRow?.updateTitle("Server version 取得できませんでした")
            }
        }
    }

    /// 未ログイン時の表示 (Web 版と同じ文言)。
    private func showLoggedOut() {
        nameLabel.text = "ログインしていません"
        adminBadge.isHidden = true
        idLabel.text = "Not logged in"
        idLabel.isHidden = false
        iconPhotoView.image = nil
        iconPhotoView.isHidden = true
        iconGlyphView.isHidden = false
    }

    // MARK: - 行き先

    @objc private func openSettings() {
        // 設定は階層化したため、まず分類一覧を開く (Web 版と同じ構造)。
        navigationController?.pushViewController(SettingsCategoryViewController(), animated: true)
    }

    @objc private func openLicenses() {
        navigationController?.pushViewController(LicenseViewController(), animated: true)
    }

    @objc private func openAccount() {
        navigationController?.pushViewController(AccountSettingsViewController(), animated: true)
    }

    @objc private func openMyList() {
        navigationController?.pushViewController(MylistViewController(), animated: true)
    }

    @objc private func openWatchedHistory() {
        navigationController?.pushViewController(WatchedHistoryViewController(), animated: true)
    }

    // MARK: - 拡張オプションの解放

    /// App version の行のタップ。7回タップで「拡張オプション」の
    /// 区分 (「このアプリの設定」の中) が解放される。残り3回からは
    /// 「あと○ステップ」と知らせ、解放できたらその旨を知らせる。
    /// 知らせの文面は、Android の開発者向けオプションの実物の
    /// 言い回しに合わせた短い文にしている。解放済みのときに
    /// タップしたら、すでに有効な旨を知らせる (Android の
    /// 「開発者向けオプションはすでに有効です」と同じ)。
    /// 解放の状態は端末ごとに保存される。専用画面の全体トグルを
    /// オフにすると解放が戻るため、そのときはここから解放を
    /// やり直す形になる。
    @objc private func appVersionRowTapped() {
        if SettingsStore.shared.customizedServerFeaturesUnlocked {
            showBriefNotice("拡張オプションはすでに有効です")
            return
        }
        // 前のタップから時間が空いていたら、最初から数え直す
        // (長い期間に分けたタップの合計では解放しない)。
        if let last = appVersionLastTapAt, Date().timeIntervalSince(last) > 3 {
            appVersionTapCount = 0
        }
        appVersionLastTapAt = Date()
        appVersionTapCount += 1
        let remaining = 7 - appVersionTapCount
        if remaining <= 0 {
            appVersionTapCount = 0
            SettingsStore.shared.customizedServerFeaturesUnlocked = true
            showBriefNotice("拡張オプションが有効になりました")
        } else if remaining <= 3 {
            showBriefNotice("あと \(remaining) ステップで拡張オプションが有効になります。")
        }
    }

    /// 画面の下の方 (下段バーの上あたり) に、小さい丸みのある帯の
    /// 知らせを出し、少し経ったら自動で消す。Android の開発者向け
    /// オプションの出し方と同じ、下に出る小さい知らせ (トースト) の形。
    /// 連続タップのときは、出ている知らせの文を差し替えて出し直さない。
    private func showBriefNotice(_ message: String) {
        briefNoticeGeneration += 1
        let generation = briefNoticeGeneration
        if let toast = briefNoticeView, let label = briefNoticeLabel {
            label.text = message
            // 消えかけていたら、見える状態に戻す。
            toast.layer.removeAllAnimations()
            toast.alpha = 1
        } else {
            let toast = UIView()
            toast.backgroundColor = AppPalette.pressed
            toast.layer.cornerRadius = 18
            toast.layer.shadowColor = UIColor.black.cgColor
            toast.layer.shadowOpacity = 0.3
            toast.layer.shadowRadius = 8
            toast.layer.shadowOffset = CGSize(width: 0, height: 2)
            toast.isUserInteractionEnabled = false
            toast.translatesAutoresizingMaskIntoConstraints = false
            let label = UILabel()
            label.text = message
            label.font = .scaledSystemFont(ofSize: 13)
            label.textColor = AppPalette.text
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            toast.addSubview(label)
            view.addSubview(toast)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16),
                toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
                toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            ])
            briefNoticeView = toast
            briefNoticeLabel = label
            toast.alpha = 0
            UIView.animate(withDuration: 0.2) { toast.alpha = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.briefNoticeGeneration == generation,
                  let toast = self.briefNoticeView else { return }
            UIView.animate(withDuration: 0.25, animations: {
                toast.alpha = 0
            }) { [weak self] _ in
                guard let self, self.briefNoticeGeneration == generation else { return }
                toast.removeFromSuperview()
                self.briefNoticeView = nil
                self.briefNoticeLabel = nil
            }
        }
    }
}

/// マイページの入口ボタン (Web 版の .settings-navigation__button の写し)。
/// アイコン 26px と文字 16px を左寄せで並べ、押している間だけ
/// 地を background-lighten-2 にする。
final class EntryButtonView: UIControl {
    private let backgroundView = UIView()
    /// 押したときの波紋 (共通部品の RippleSurface)。地の上に重ねて描く。
    private let ripple = RippleSurface()
    /// 行の文字。サーバーの版のように、後から差し替える行があるため保持する。
    private let titleLabel = UILabel()

    init(icon: UIImage?, title: String) {
        super.init(frame: .zero)
        backgroundView.backgroundColor = AppPalette.panel
        backgroundView.layer.cornerRadius = 6
        backgroundView.isUserInteractionEnabled = false
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        ripple.container.frame = bounds
        ripple.container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(ripple.container)

        let iconView = UIImageView(image: icon)
        iconView.tintColor = AppPalette.text
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .scaledSystemFont(ofSize: 16)
        titleLabel.textColor = AppPalette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(iconView)
        backgroundView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: backgroundView.trailingAnchor, constant: -16),
        ])
    }

    /// 行の文字を差し替える (サーバーの版のように、開いてから値が届く行用)。
    func updateTitle(_ title: String) {
        titleLabel.text = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: bounds, cornerRadius: 6)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let tracking = super.beginTracking(touch, with: event)
        if tracking, isEnabled {
            ripple.startRipple(at: touch.location(in: self))
        }
        return tracking
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        ripple.endRipple()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        ripple.cancelRipple()
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundView.backgroundColor = isHighlighted ? AppPalette.pressed : AppPalette.panel
        }
    }

    override var isEnabled: Bool {
        didSet {
            // バージョン表示のように押せない行は、見た目を変えず操作だけ止める。
            backgroundView.backgroundColor = AppPalette.panel
        }
    }
}
