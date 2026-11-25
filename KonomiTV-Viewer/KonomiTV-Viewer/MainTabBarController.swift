import UIKit

/// アプリ共通の下部バーと、4つのタブ画面を束ねるコンテナ画面。
///
/// 以前は UITabBarController を使い、標準の UITabBar を
/// `tabBar.isHidden = true` で隠して自前バーを重ねていた。しかし
/// 「隠す」方式は、タブコントローラ自身が持つタブバーの表示状態の
/// 管理と競合し、第7弾で SceneDelegate に起動時のタブ指定
/// (selectedIndex の事前代入) が入ったのをきっかけに、標準バーが
/// 再び描かれるようになってしまった (版0.19 で実機確認)。
/// そのため UITabBarController ごとやめ、ただの UIViewController に
/// 3つのナビゲーション画面を子として持たせ、下部の自前バーで
/// 切り替える作りに置き換えた。標準タブバーは存在自体が無い。
///
/// バーの見た目は Web 版の BottomNavigation.vue どおり:
/// 画面幅いっぱいのベタ塗り (background-lighten-1、半透明なし、角丸なし) で、
/// 下端のホームインジケータ部分まで面が届く。項目はアイコン+文字 (太字
/// 10.5pt)、通常時 text-darken-1、選択中は primary。
/// 選択中の見分けは Web 版どおり色のみ (アイコンと文字が primary に
/// なる)。版0.40 で一時、選択中はタブの領域いっぱいに primary の薄い
/// 地を敷く形にしたが、2026-11-23 に本人の訂正で色のみに戻した。
/// 切り替えはアニメーションなしの即時切り替えにする
/// (滑らせる動きは付けない)。
final class MainTabBarController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    /// バーの中身の高さ。Vuetify の v-bottom-navigation の標準高さ 56px を
    /// そのまま使う。バーの実高さは、これに下端のセーフエリア
    /// (ホームインジケータ分) を加えたものになる。
    /// 表示の大きさに合わせて拡縮するため、固定値ではなくその都度求める。
    private static var barContentHeight: CGFloat { UIScale.value(56) }

    /// タブ1つ分。中身のナビゲーション画面と、バーに出す題名・アイコン、
    /// 先頭画面を作り直すための手順。表示の大きさが変わったとき、
    /// 先頭画面だけのタブは作り直して新しい大きさを反映する。
    private struct Tab {
        let controller: UINavigationController
        let title: String?
        let image: UIImage?
        let makeRoot: () -> UIViewController
        /// 現在の先頭画面が作られた時点の表示の大きさ (パーセント)。
        var builtScalePercent: Int
    }

    private var tabs: [Tab] = []
    private var currentTabController: UINavigationController?

    private let customBar = UIView()
    private var barHeightConstraint: NSLayoutConstraint?
    private var itemsStackHeightConstraint: NSLayoutConstraint?
    private var itemsStack: UIStackView?
    private var itemViews: [TabBarItemView] = []

    /// 選択中のタブ番号。代入すると表示する子画面を切り替え、項目の色と
    /// バーの表示状態を追随させる (旧 UITabBarController の selectedIndex
    /// と同じ使い方)。タブ番号の意味は SceneDelegate の並びで決まる
    /// (テレビをみる = 0、ビデオをみる = 1、録画予約 = 2、マイページ = 3)。
    var selectedIndex: Int = 0 {
        didSet {
            if isViewLoaded, oldValue != selectedIndex {
                showSelectedTab()
            }
            refreshBarState()
        }
    }

    /// 選択中のタブのナビゲーション画面。
    var selectedTabViewController: UINavigationController? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].controller : nil
    }

    /// タブの並びと、起動時に開くタブを設定する。view が読み込まれる前に
    /// 呼ばれる前提 (SceneDelegate から生成直後に呼ぶ)。
    /// makeRoot は、表示の大きさが変わったときに先頭画面を作り直すための
    /// 手順 (初期表示の先頭画面と同じものを新規に作る)。
    func setTabs(
        _ tabs: [(controller: UINavigationController, title: String?, image: UIImage?,
                  makeRoot: () -> UIViewController)],
        initialIndex: Int
    ) {
        let currentScale = SettingsStore.shared.uiScalePercent
        self.tabs = tabs.map {
            Tab(controller: $0.controller, title: $0.title, image: $0.image,
                makeRoot: $0.makeRoot, builtScalePercent: currentScale)
        }
        selectedIndex = initialIndex
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 録画の H.265 再生で使うアプリ内の中継を、先に立ち上げておく
        // (最初に再生するときに間に合わず、元の URL に落ちるのを避ける)。
        StreamRelayServer.shared.startIfNeeded()
        // ログイン済みでまだ同期したことのない端末では、サーバーに
        // 保存済みの設定の自動取り込みを試す (ログイン直後の取り込みと
        // 同じもの。Web 版はログイン中ずっと見張っているため、起動時にも
        // 試して近づける)。アプリだけで完結するため常時有効。
        Task { await SyncedSettingsStore.shared.adoptServerSettingsOnLogin() }
        // 各タブのナビゲーションの出入り (再生画面への push など) で、
        // バーの表示・非表示を追随させるためにデリゲートを受ける。
        for tab in tabs {
            tab.controller.delegate = self
        }
        // 選択中のタブの画面を子として組み込む。自前バーより先に入れて、
        // バーが前面に来るようにする。
        showSelectedTab()
        setUpCustomBar()
        refreshBarState()
        // 表示の大きさが変わったら、バーを作り直し、先頭画面だけのタブは
        // 先頭画面も作り直す (画面が積まれているタブは、一番上まで
        // 戻った時点で作り直す)。
        NotificationCenter.default.addObserver(
            self, selector: #selector(uiScaleDidChange),
            name: .uiScaleDidChange, object: nil)
        // 共通設定のサーバー保存に失敗したら知らせる (端末内には
        // 保存されるため、黙っていると気づけない)。設定の各画面に
        // 共通の親であるここで受け、一番手前の画面から出す
        // (番組表の表示設定の失敗通知と同じ考え方)。
        NotificationCenter.default.addObserver(
            forName: .syncedSettingsSaveFailed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let presenter = self.topmostViewController(),
                  presenter.view.window != nil else { return }
            let alert = UIAlertController(
                title: "設定をサーバーへ保存できませんでした",
                message: "この端末には保存されていますが、他の端末や Web 版には反映されていません。接続先とネットワークを確認してください。次に設定を変更したときや、一覧を開いたときに送り直します。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: true)
        }
    }

    /// いま一番手前にいる画面 (選択中のタブの画面から、重ねて
    /// 開かれた画面の順にたどる)。
    private func topmostViewController() -> UIViewController? {
        var candidate: UIViewController = selectedTabViewController ?? self
        while true {
            if let presented = candidate.presentedViewController {
                candidate = presented
            } else if let navigation = candidate as? UINavigationController,
                      let top = navigation.topViewController {
                candidate = top
            } else {
                return candidate
            }
        }
    }

    /// 表示の大きさの変更を受けたときの追随。
    /// バーの項目はその場で作り直し、各タブは作り直し可能な状態
    /// (先頭画面だけ) のものから反映する。
    @objc private func uiScaleDidChange() {
        for itemView in itemViews {
            itemView.removeFromSuperview()
        }
        itemViews = []
        rebuildItemsIfNeeded()
        refreshBarState()
        for index in tabs.indices {
            rebuildTabRootIfNeeded(index: index)
        }
        view.setNeedsLayout()
    }

    /// 表示の大きさが変わっていたら、そのタブの先頭画面を作り直す。
    /// 画面が積まれている (再生画面などを開いている) 間は触らず、
    /// 一番上まで戻った時点で作り直す (呼び出し側の didShow など)。
    private func rebuildTabRootIfNeeded(index: Int) {
        guard tabs.indices.contains(index) else { return }
        let currentScale = SettingsStore.shared.uiScalePercent
        guard tabs[index].builtScalePercent != currentScale else { return }
        let navigation = tabs[index].controller
        guard navigation.viewControllers.count == 1 else { return }
        navigation.setViewControllers([tabs[index].makeRoot()], animated: false)
        tabs[index].builtScalePercent = currentScale
        if index == selectedIndex {
            refreshBarState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 項目の組み立ては viewDidLoad だけに頼らない (下記の
        // rebuildItemsIfNeeded のコメント参照)。表示直前にもそろえる。
        rebuildItemsIfNeeded()
        refreshBarState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // バーの高さは「中身 56 + 機器の下端セーフエリア」。回転などで
        // セーフエリアが変わっても追随する。
        // 注意: view.safeAreaInsets.bottom は、自前バーのために自分で
        // 加算した additionalSafeAreaInsets.bottom (56) を含んだ値が
        // 返ってくる。そのまま使うと高さが 56 + (34 + 56) = 146pt に
        // 膨らんでしまう (版0.14 の実機で実際にそうなっていた) ため、
        // 機器本来の下端分は自分の加算分を差し引いて求める。
        let target = Self.barContentHeight + systemBottomSafeAreaInset
        if let constraint = barHeightConstraint, abs(constraint.constant - target) > 0.5 {
            constraint.constant = target
        }
        // 項目の並びの高さも、バーの中身の高さに合わせておく
        // (表示の大きさが変わったときに追随させるため)。
        if let constraint = itemsStackHeightConstraint,
           abs(constraint.constant - Self.barContentHeight) > 0.5 {
            constraint.constant = Self.barContentHeight
        }
        // 子画面が後から重なっても、バーが最前面に残るようにする。
        view.bringSubviewToFront(customBar)
        rebuildItemsIfNeeded()
    }

    /// 機器本来の下端セーフエリア (ホームインジケータ分)。
    /// view.safeAreaInsets.bottom から、自分の加算分
    /// (additionalSafeAreaInsets.bottom) を差し引いた値。
    private var systemBottomSafeAreaInset: CGFloat {
        max(view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom, 0)
    }

    // MARK: - 子画面の切り替え

    /// 選択中のタブのナビゲーション画面を子として表示する。
    /// 外れたタブの画面は階層から外すが、ナビゲーション画面の実体は
    /// tabs に残るため、積まれた画面やスクロール位置は保持される
    /// (旧 UITabBarController の切り替えと同じ)。
    private func showSelectedTab() {
        // 表示する前に、表示の大きさの変更が残っていれば先頭画面を
        // 作り直しておく (画面が積まれているタブは戻った時点で直す)。
        rebuildTabRootIfNeeded(index: selectedIndex)
        guard isViewLoaded,
              let next = selectedTabViewController,
              currentTabController !== next else {
            refreshBarState()
            return
        }
        if let current = currentTabController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        // バーより後ろに入れる (バーが前面に残るように)。
        if customBar.superview === view {
            view.insertSubview(next.view, belowSubview: customBar)
        } else {
            view.addSubview(next.view)
        }
        NSLayoutConstraint.activate([
            next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            next.view.topAnchor.constraint(equalTo: view.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        next.didMove(toParent: self)
        currentTabController = next
        refreshBarState()
    }

    // MARK: - 自前バーの組み立て

    private func setUpCustomBar() {
        // 地は background-lighten-1 のベタ塗り。角丸・半透明は付けない。
        customBar.backgroundColor = AppPalette.panel
        customBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(customBar)

        // Web 版は elevation の影で浮き上がらせる。ここでは第2弾の標準バーと
        // 同じく、background-lighten-2 の細い線で近似する。
        let topBorder = UIView()
        topBorder.backgroundColor = AppPalette.pressed
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        customBar.addSubview(topBorder)

        // 項目の並び。Web 版のコンテナと同じく左右に 8px の余白を取り、
        // 項目は均等割り (flex-basis: 0 + grow) にする。
        let itemsStack = UIStackView()
        itemsStack.axis = .horizontal
        itemsStack.distribution = .fillEqually
        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        customBar.addSubview(itemsStack)
        self.itemsStack = itemsStack

        barHeightConstraint = customBar.heightAnchor.constraint(
            equalToConstant: Self.barContentHeight + systemBottomSafeAreaInset)
        itemsStackHeightConstraint = itemsStack.heightAnchor.constraint(
            equalToConstant: Self.barContentHeight)
        NSLayoutConstraint.activate([
            customBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            barHeightConstraint!,
            topBorder.topAnchor.constraint(equalTo: customBar.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: customBar.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: customBar.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),
            itemsStack.topAnchor.constraint(equalTo: customBar.topAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: customBar.leadingAnchor, constant: 8),
            itemsStack.trailingAnchor.constraint(equalTo: customBar.trailingAnchor, constant: -8),
            itemsStackHeightConstraint!,
        ])

        // 項目は setTabs で渡された題名とアイコンから作る。
        // アイコンの形・大きさの指定は SceneDelegate 側が持つ。
        rebuildItemsIfNeeded()
    }

    /// バーの項目を、現在の tabs に合わせて作る。
    ///
    /// 版0.14 では項目を viewDidLoad の中で一度だけ作っていたが、実機では
    /// バーの地色だけが描かれ、項目が1つも描かれなかった。組み立ての
    /// タイミングに結果が左右される作りだったため、個数が合って
    /// いなければ作り直す形にし、表示直前とレイアウトのたびに呼んで
    /// 不足を補う。個数が合っている間は何もしない。
    private func rebuildItemsIfNeeded() {
        guard let itemsStack else { return }
        guard itemViews.count != tabs.count else { return }
        for itemView in itemViews {
            itemView.removeFromSuperview()
        }
        itemViews = tabs.enumerated().map { index, tab in
            let item = TabBarItemView(
                image: tab.image,
                title: tab.title
            )
            item.tag = index
            item.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            itemsStack.addArrangedSubview(item)
            return item
        }
        refreshBarState()
    }

    @objc private func itemTapped(_ sender: TabBarItemView) {
        // 選択中のタブをもう一度押したら、そのタブの一番上の画面まで
        // 戻る (マイページならマイページのトップ)。標準のタブバーの
        // 振る舞いと同じ。
        if sender.tag == selectedIndex, tabs.indices.contains(sender.tag) {
            tabs[sender.tag].controller.popToRootViewController(animated: true)
            return
        }
        // selectedIndex の didSet で子画面の切り替えと色・表示状態の
        // 追随が走る。
        selectedIndex = sender.tag
    }

    // MARK: - バーの表示状態

    /// 項目の選択表示 (色) と、バーの表示・非表示、子画面へ渡す
    /// 下部の余白を現在の状態に合わせる。
    private func refreshBarState() {
        guard isViewLoaded else { return }
        for (index, itemView) in itemViews.enumerated() {
            itemView.isSelectedTab = (index == selectedIndex)
        }
        // 選択中タブの一番上の画面が「バーを隠す」指定 (hidesBottomBarWhenPushed、
        // 再生画面が付けている) なら、旧標準タブバーと同じくバーを隠す。
        let shouldHide: Bool
        if let navigation = selectedTabViewController,
           navigation.viewControllers.count > 1 {
            shouldHide = navigation.topViewController?.hidesBottomBarWhenPushed ?? false
        } else {
            shouldHide = false
        }
        applyBarVisibility(shouldHide: shouldHide)
    }

    /// バーの表示・非表示と、子画面の下部セーフエリアへの加算を切り替える。
    /// バーが見えている間は中身の高さ (56) 分を加算し、各画面のスクロール
    /// 末尾や下端の要素がバーに隠れないようにする。バーが隠れている間は
    /// 加算を 0 にし、旧標準タブバーが隠れたときと同じ状態に戻す。
    /// (コンテナの additionalSafeAreaInsets は子画面にも伝わる。)
    private func applyBarVisibility(shouldHide: Bool) {
        customBar.isHidden = shouldHide
        additionalSafeAreaInsets.bottom = shouldHide ? 0 : Self.barContentHeight
    }
}

// MARK: - ナビゲーションの出入りへの追随

extension MainTabBarController: UINavigationControllerDelegate {
    /// 画面遷移が始まる時点で、遷移先に合わせてバーの表示を切り替える。
    /// (旧標準タブバーは遷移と同時に隠れるため、それに合わせる。)
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        guard navigationController === selectedTabViewController else { return }
        let isRoot = navigationController.viewControllers.first === viewController
        applyBarVisibility(shouldHide: !isRoot && viewController.hidesBottomBarWhenPushed)
    }

    /// 遷移が終わった時点でもう一度そろえる。スワイプで戻る操作が
    /// 途中でキャンセルされた場合に、willShow だけでは状態がずれるため。
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // 一番上の画面まで戻ってきたら、残っていた表示の大きさの
        // 変更をそのタブの先頭画面に反映する。
        if navigationController.viewControllers.count == 1,
           let index = tabs.firstIndex(where: { $0.controller === navigationController }) {
            rebuildTabRootIfNeeded(index: index)
        }
        refreshBarState()
    }
}

// MARK: - タブの中の画面からコンテナを引く

extension UIViewController {
    /// 親をたどって、タブを束ねるコンテナ画面 (MainTabBarController) を返す。
    /// タブの中の画面 (ナビゲーション配下や、その先の再生画面) から
    /// タブ切り替えを指示するために使う (旧 tabBarController の置き換え)。
    var mainTabBarController: MainTabBarController? {
        var current: UIViewController? = self
        while let controller = current {
            if let main = controller as? MainTabBarController { return main }
            current = controller.parent
        }
        return nil
    }
}

// MARK: - バーの項目

/// 下部バーの項目1つ分。アイコン (30px) の下に文字 (太字 10.5pt) を置く
/// Web 版の並び (アイコンと文字の間は mt-1 = 4px)。
/// 選択中はアイコンと文字の色だけが変わる (本家 Web 版どおり)。
/// 切り替えにアニメーションは付けない。
private final class TabBarItemView: UIControl {
    /// 押したときの波紋。本家 Web 版の下部バーの項目は通常のボタン
    /// (角丸 0) で、押したときの反応は全面の波紋だけ。「押している
    /// 間だけ出る地」の定義は本家に無いため、以前入れていた丸い地は
    /// 外した。
    private let ripple = RippleSurface()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(image: UIImage?, title: String?) {
        super.init(frame: .zero)
        addSubview(ripple.container)
        // アイコンは色で塗り替える (テンプレート) 形にし、状態色を tint で出す。
        iconView.image = image?.withRenderingMode(.alwaysTemplate)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = .scaledSystemFont(ofSize: 10.5, weight: .bold)
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        // タップはこの項目ビュー自身が受ける (中身は素通しにする)。
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: UIScale.value(30)),
            iconView.heightAnchor.constraint(equalToConstant: UIScale.value(30)),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        accessibilityLabel = title
        isAccessibilityElement = true
        isSelectedTab = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 選択中かどうか。アイコンと文字の色だけが変わる。色の切り替えは
    /// アニメーションなしで即時に行う。
    var isSelectedTab: Bool = false {
        didSet {
            let color = isSelectedTab ? AppPalette.accent : AppPalette.metaText
            iconView.tintColor = color
            titleLabel.textColor = color
            accessibilityTraits = isSelectedTab ? [.button, .selected] : [.button]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 波紋は項目の全面に、角丸 0 で出す (本家のボタンどおり)。
        ripple.update(bounds: bounds, cornerRadius: 0)
        // 重なり順は、波紋 → 絵と文字。
        sendSubviewToBack(ripple.container)
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
}
