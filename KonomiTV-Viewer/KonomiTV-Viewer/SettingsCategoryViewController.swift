import UIKit

/// 設定の分類一覧 (マイページの「設定」の先)。
///
/// たつやさんの指示で、設定を Web 版と同じ階層にした: この画面が分類の
/// 一覧 (大きな入口ボタン) で、分類ごとに別の画面を開く。
/// 分類は Web 版の設定の並びに合わせた「全般」「画質」「字幕」
/// 「アカウント」「ニコニコ実況」と、アプリ専用の「このアプリの設定」。
/// Web 版にある「データ放送」「キャプチャ」「Twitter / Bluesky 連携」
/// 「サーバー設定」は、アプリに土台が無い (サーバー設定は出さない
/// 決まり) ため置いていない。
/// 見た目は他の設定画面と同じ: 上部に高さ 60px・地が
/// background-lighten-1 の見出し帯、入口ボタンはマイページと同じ
/// EntryButtonView (高さ 54px、地は background-lighten-1)。
final class SettingsCategoryViewController: UIViewController {
    /// 見出し帯の戻るボタン (この画面はナビゲーションバーを隠すため、
    /// 帯側で戻り口を用意する。他の設定画面と同じ作り)。
    private let backButton = RippleButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        // 左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 見出しは自前の帯で出すため、ナビゲーションバーは隠す
        // (他の設定画面と同じ)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 同期が入っていれば、開くときにサーバー側の共通設定を
        // 取り込んでおく (各分類の画面が最新の値で開けるように)。
        Task {
            _ = await SyncedSettingsStore.shared.refreshFromServer()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 隠すのはこの画面の間だけ。遷移先ではナビゲーションバーを元に戻す。
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    private func buildLayout() {
        // 上部の見出し帯 (高さ 60px、地が background-lighten-1、
        // ページ名 22px。他の設定画面と同じ)。
        let headingBar = UIView()
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "設定"
        headingLabel.font = .scaledSystemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        // 戻るボタンは本家に合わせて矢印だけ (文字は付けない)。
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)

        // 入口の並びは Web 版の設定一覧と同じ順 (全般 → 画質 → 字幕 →
        // アカウント → ニコニコ実況)。アプリ専用の「このアプリの設定」
        // は最後に置く。
        let generalButton = makeEntryButton(
            iconName: "", fallbackSystemName: "slider.horizontal.3",
            title: "全般")
        generalButton.addTarget(self, action: #selector(openGeneralSettings), for: .touchUpInside)
        let playbackButton = makeEntryButton(
            iconName: "ic_fluent_movies_and_tv_20_regular", fallbackSystemName: "film",
            title: "画質")
        playbackButton.addTarget(self, action: #selector(openPlaybackSettings), for: .touchUpInside)
        let captionButton = makeEntryButton(
            iconName: "", fallbackSystemName: "captions.bubble",
            title: "字幕")
        captionButton.addTarget(self, action: #selector(openCaptionSettings), for: .touchUpInside)
        let accountButton = makeEntryButton(
            iconName: "ic_fluent_person_20_regular", fallbackSystemName: "person",
            title: "アカウント")
        accountButton.addTarget(self, action: #selector(openAccountSettings), for: .touchUpInside)
        let jikkyoButton = makeEntryButton(
            iconName: "", fallbackSystemName: "text.bubble",
            title: "ニコニコ実況")
        jikkyoButton.addTarget(self, action: #selector(openJikkyoSettings), for: .touchUpInside)
        let appSettingsButton = makeEntryButton(
            iconName: "ic_fluent_settings_20_regular", fallbackSystemName: "gearshape",
            title: "このアプリの設定")
        appSettingsButton.addTarget(self, action: #selector(openAppSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            generalButton,
            playbackButton,
            captionButton,
            accountButton,
            jikkyoButton,
            appSettingsButton,
        ])
        stack.axis = .vertical
        stack.spacing = 6
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
            // 下端はセーフエリアの下端に留める (他の設定画面と同じ)。
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            // 中身の余白は他の設定画面と同じ左右 16px、上は 24px。
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    /// 入口ボタン1つ分 (マイページと同じ EntryButtonView、高さ 54px)。
    private func makeEntryButton(iconName: String, fallbackSystemName: String, title: String) -> EntryButtonView {
        let image = (UIImage(named: iconName)
            ?? UIImage(systemName: fallbackSystemName))?
            .withRenderingMode(.alwaysTemplate)
        let button = EntryButtonView(icon: image, title: title)
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    // MARK: - 行き先

    @objc private func openGeneralSettings() {
        navigationController?.pushViewController(
            GeneralSettingsViewController(), animated: true)
    }

    @objc private func openPlaybackSettings() {
        navigationController?.pushViewController(
            PlaybackSettingsViewController(), animated: true)
    }

    @objc private func openCaptionSettings() {
        navigationController?.pushViewController(
            CaptionSettingsViewController(), animated: true)
    }

    @objc private func openAccountSettings() {
        navigationController?.pushViewController(
            AccountSettingsViewController(), animated: true)
    }

    @objc private func openJikkyoSettings() {
        navigationController?.pushViewController(
            JikkyoSettingsViewController(), animated: true)
    }

    @objc private func openAppSettings() {
        navigationController?.pushViewController(
            SettingsViewController(mode: .tab), animated: true)
    }
}
