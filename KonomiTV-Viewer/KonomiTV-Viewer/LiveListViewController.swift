import UIKit

/// 生放送のチャンネル一覧。上部のカテゴリ切り替え (地デジ／BS／CS など) で絞り込み、
/// 各カードに局ロゴと局名、今の番組 (時刻・説明つき) と次の番組を出す。
/// 見た目は Web 版のテレビ一覧 (views/TV/Home.vue、スマホ縦) の実測どおり:
/// 番組ごとに独立した角丸カードが間隔を空けて並び、カード下端に
/// 放送中番組の進み具合のバーが付く。
///
/// 画面の組み立て:
/// - ロゴ帯とカテゴリ帯は画面側の重ね物 (headerContainer) に置き、横には動かさない。
///   縦スクロールでは、ロゴ帯が上に流れていきカテゴリ帯が上端に残る今の動きを、
///   重ね物全体の位置をスクロール量でずらして再現する (ロゴ帯の高さぶんまで)。
/// - 一覧はカテゴリごとに1台ずつ用意する。横ドラッグでは今のページと隣のページを
///   横に並べ、指に付いて一緒に滑らせる (透けて重なることはない)。
///   離した位置 (半分超え) と勢いで、隣へ進むか元に戻るかが決まる。
///   カテゴリ帯の下線はドラッグの進み具合に連動して滑る。
final class LiveListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UIGestureRecognizerDelegate {
    private let headerView = SPHeaderView()
    /// ロゴ帯とカテゴリ帯をまとめた画面側の重ね物。縦スクロールに合わせて
    /// 上へずらし、カテゴリ帯だけが上端に残る形にする。横には動かさない。
    private let headerContainer = UIView()
    private var headerTopConstraint: NSLayoutConstraint?
    private var headerHeightConstraint: NSLayoutConstraint?
    private let categoryBar = UIView()
    private var categoryBarHeightConstraint: NSLayoutConstraint?
    private let categoryScrollView = UIScrollView()
    private let categoryContentView = UIView()
    private let categoryStack = UIStackView()
    private let categoryLine = UIView()
    private let categoryHighlight = UIView()
    private var categoryButtons: [UIButton] = []
    private var highlightLeadingConstraint: NSLayoutConstraint?
    /// ページ (カテゴリごとの一覧) を並べる受け枠。中身は横に滑るため切り抜く。
    private let pagerContainer = UIView()
    /// 横ドラッグでページを移るためのしぐさ。受け枠に1つだけ付け、
    /// どのページが出ていても、カードの上からでも、同じ条件で拾えるようにする
    /// (以前は一覧ごとに付けていて、向きの判定も不安定だった)。
    private let pagePan = UIPanGestureRecognizer()
    /// いま出ているページの一覧。tag にカテゴリの順番を持たせ、
    /// データの出し分けに使う。
    private var currentTableView: UITableView!
    /// 横ドラッグ・タップ切り替えの最中だけ隣に並ぶページの一覧。
    private var neighborTableView: UITableView?
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()
    /// 番組表への浮きボタン (Web 版のテレビ画面と同じ置き方)。
    private let timetableButton = RippleButton()

    private var groups: [(type: String, channels: [LiveChannel])] = []
    private var selectedGroupIndex = 0
    private var isLoading = false
    private var loadedBaseURLString: String?

    /// ページ切り替え (ドラッグ／タップのアニメーション) の最中かどうか。
    /// この間は縦スクロールでヘッダーを動かさない (ドラッグ側が受け持つ)。
    private var isPageTransitioning = false
    /// ドラッグ中の控え。隣のページが無い端では targetIndex が nil になる。
    private struct PageDrag {
        var targetIndex: Int?
        /// 進む向き (+1 = 次のカテゴリ、-1 = 前のカテゴリ)。
        var step: Int
        /// ドラッグ開始時点でロゴ帯が隠れていた量 (0〜ロゴ帯の高さ)。
        var startHeaderHidden: CGFloat
    }
    private var pageDrag: PageDrag?

    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (再取得を避ける)。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []

    /// カテゴリ帯の高さ (Web 版の channels-tab と同じ 64px)。
    /// カテゴリが無い (読み込み前・0件) ときは 0 にして帯自体を出さない。
    private var categoryBarHeight: CGFloat { groups.isEmpty ? 0 : 64 }
    /// 一覧の上端に空ける量 (ロゴ帯 + カテゴリ帯)。ページの先頭では
    /// この分だけ下からカードが始まり、重ね物と重ならない。
    private var tablesTopInset: CGFloat { SPHeaderView.height + categoryBarHeight }

    /// 指定したカテゴリのチャンネル。
    private func channels(forGroupAt index: Int) -> [LiveChannel] {
        guard groups.indices.contains(index) else { return [] }
        return groups[index].channels
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        // この画面ではナビゲーションバーを隠すため見出しには出ない。
        // 押し込んだ先の画面の戻るボタンの文字としてだけ残してある。
        title = "生放送"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        // 並びは Web 版のスマホ縦どおり、ロゴ帯 → カテゴリ帯 → カードの順。
        // ロゴ帯とカテゴリ帯は画面側の重ね物に置く。ページ (一覧) の先頭では
        // 重ね物の下にカードが来て、縦スクロールでロゴ帯が流れ終わると
        // カテゴリ帯だけが上端に残る (重ね物の位置をスクロールでずらす)。
        // ロゴのタップでは Web 版のリンク先 (/tv/ = この画面) に合わせて生放送タブへ移る。
        headerView.onLogoTap = { [weak self] in
            self?.mainTabBarController?.selectedIndex = 0
        }

        setupCategoryBar()

        // ページの受け枠は、今までの一覧と同じ場所 (画面の上端から下端まで) に敷く。
        pagerContainer.backgroundColor = AppPalette.background
        pagerContainer.clipsToBounds = true
        pagerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerContainer)

        // 横ドラッグのしぐさは受け枠に付ける (一覧より先に用意し、
        // 一覧側のスクロールには、このしぐさが不成立になるまで待ってもらう)。
        pagePan.addTarget(self, action: #selector(handlePagePan(_:)))
        pagePan.delegate = self
        pagerContainer.addGestureRecognizer(pagePan)

        currentTableView = makeTableView(groupIndex: 0)
        pagerContainer.addSubview(currentTableView)
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        currentTableView.refreshControl = refreshControl

        setupHeader()

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        setupTimetableButton()

        NSLayoutConstraint.activate([
            pagerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pagerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    /// ロゴ帯とカテゴリ帯の重ね物を画面の上に置く。
    /// 上端の位置は縦スクロールに合わせてずらす (ロゴ帯の高さぶんまで)。
    private func setupHeader() {
        headerContainer.backgroundColor = AppPalette.background
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerView)
        headerContainer.addSubview(categoryBar)

        headerTopConstraint = headerContainer.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor)
        // 読み込み前はカテゴリが無いため、高さはロゴ帯だけにしておく。
        // カテゴリが届いたら updateHeaderMetrics で広げる。
        headerHeightConstraint = headerContainer.heightAnchor.constraint(
            equalToConstant: SPHeaderView.height)
        NSLayoutConstraint.activate([
            headerTopConstraint!,
            headerHeightConstraint!,
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: SPHeaderView.height),
            categoryBar.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            categoryBar.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            categoryBarHeightConstraint!,
        ])
    }

    /// カテゴリごとのページ (一覧) を作る。先頭の位置は重ね物の下に合わせる。
    /// 横ドラッグのしぐさ自体は受け枠側に1つだけある (pagePan) ため、
    /// ここでは縦スクロールに、そのしぐさの成否を待つ決まりだけを付ける。
    private func makeTableView(groupIndex: Int) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.tag = groupIndex
        table.dataSource = self
        table.delegate = self
        table.register(LiveChannelCell.self, forCellReuseIdentifier: LiveChannelCell.reuseID)
        // 行の高さはカードの中身 (説明文の行数など) に合わせて自動で決める。
        // 推定値は Web 版カードのスマホ縦の intrinsic height (162.25px) + カード間隔 (10px)。
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 172
        table.backgroundColor = AppPalette.background
        table.separatorStyle = .none
        // 一覧の下端の余白は Web 版 (スマホ縦) の padding-bottom 12px。
        table.contentInset = UIEdgeInsets(top: tablesTopInset, left: 0, bottom: 12, right: 0)
        table.scrollIndicatorInsets = UIEdgeInsets(top: tablesTopInset, left: 0, bottom: 0, right: 0)
        table.contentOffset = CGPoint(x: 0, y: -tablesTopInset)
        // 縦スクロールは、横ドラッグのしぐさ (受け枠の pagePan) が
        // 不成立になるまで待つ。横方向のときはページ送りが先に拾い、
        // 縦方向のときはこのしぐさが即座に不成立になってスクロールが始まる。
        // どのページが表示中になっても同じ決まりが要るため、作るたびに付ける。
        table.panGestureRecognizer.require(toFail: pagePan)
        return table
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // ページ切り替えの最中は枠をドラッグ／アニメーション側が動かすため触らない。
        guard !isPageTransitioning else { return }
        currentTableView.frame = pagerContainer.bounds
    }

    /// 番組表への浮きボタン。Web 版のテレビ画面 (TV/Home.vue) の
    /// floating-button と同じ置き方: 画面右下、下部バーの上に 16px 浮かせ、
    /// 右端から 20px。地は background-lighten-2、角丸 12px、影つき。
    /// 中身はカレンダーの絵 (26px) +「番組表」(16px)、色は text。
    /// 押すと番組表が画面の上に重なって開く (番組表・予約の第2段で
    /// タブから外れたため)。戻る導線は番組表側の「閉じる」ボタンと
    /// ロゴのタップが担う。
    private func setupTimetableButton() {
        timetableButton.setTitle("番組表", for: .normal)
        timetableButton.setTitleColor(AppPalette.text, for: .normal)
        timetableButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        timetableButton.tintColor = AppPalette.text
        timetableButton.setImage(Self.timetableButtonIcon(), for: .normal)
        timetableButton.backgroundColor = AppPalette.pressed
        timetableButton.layer.cornerRadius = 12
        timetableButton.layer.shadowColor = UIColor.black.cgColor
        timetableButton.layer.shadowOpacity = 0.61
        timetableButton.layer.shadowRadius = 7.5
        timetableButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        // Web 版の余白は上下 12px・左右 16px、絵と文字の間は 8px
        // (文字の右にも 2px の余りがあるため、右側は 18px にする)。
        timetableButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)
        timetableButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        timetableButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        timetableButton.accessibilityLabel = "番組表"
        timetableButton.addTarget(self, action: #selector(timetableButtonTapped), for: .touchUpInside)
        timetableButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timetableButton)
        NSLayoutConstraint.activate([
            timetableButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // 下部バーの分 (56px) はセーフエリアに含まれているため、
            // セーフエリアの下端から 16px 上が Web 版の
            // 「72px + セーフエリア」と同じ位置になる。
            timetableButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    /// 浮きボタンの絵。Fluent のカレンダーの素材を
    /// Web 版の大きさ (26px) に合わせて出す。素材が無いときは
    /// 標準のカレンダーで受ける。
    private static func timetableButtonIcon() -> UIImage? {
        let base = UIImage(named: "ic_fluent_calendar_ltr_20_regular")
            ?? UIImage(systemName: "calendar",
                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 24))
        guard let base else { return nil }
        let target = CGSize(width: 26, height: 26)
        let scaled = UIGraphicsImageRenderer(size: target).image { _ in
            let scale = min(target.width / base.size.width, target.height / base.size.height)
            let size = CGSize(width: base.size.width * scale, height: base.size.height * scale)
            let origin = CGPoint(
                x: (target.width - size.width) / 2, y: (target.height - size.height) / 2)
            base.draw(in: CGRect(origin: origin, size: size))
        }
        return scaled.withRenderingMode(.alwaysTemplate)
    }

    @objc private func timetableButtonTapped() {
        // 番組表はタブではなく、この画面の上に重ねて開く。
        // 閉じる動作は番組表側 (onCloseRequested) が受け持つ。
        let timetable = TimeTableViewController()
        timetable.onCloseRequested = { [weak self] in
            self?.dismiss(animated: true)
        }
        // 詳細で「視聴」が押されたら、番組表を閉じてから、この画面の
        // ナビゲーションへ再生画面を積む (戻ると生放送一覧に戻る)。
        timetable.onWatchRequested = { [weak self] channel in
            guard let self else { return }
            self.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                let player = LivePlayerViewController(channel: channel)
                self.navigationController?.pushViewController(player, animated: true)
            }
        }
        let navigation = UINavigationController(rootViewController: timetable)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    /// 上部のカテゴリ切り替え。Web 版の channels-tab (スマホ縦) の実測どおり:
    /// 高さ 64px、下に 10px の余白を空けて 3px の線 (background-lighten-1) が走り、
    /// 選択中の項目の下に 3px の primary の帯が重なる。
    /// ボタンは幅 90px・文字 15px で、色は選択中でも変わらない (帯だけが動く)。
    /// 帯そのものは画面側の重ね物 (headerContainer) の下段に置かれ、横には動かない。
    private func setupCategoryBar() {
        categoryBar.backgroundColor = AppPalette.background
        categoryBar.translatesAutoresizingMaskIntoConstraints = false
        categoryBarHeightConstraint = categoryBar.heightAnchor.constraint(equalToConstant: 0)

        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        categoryBar.addSubview(categoryScrollView)

        categoryContentView.translatesAutoresizingMaskIntoConstraints = false
        categoryScrollView.addSubview(categoryContentView)

        // ボタン群は中央寄せ。収まらないときは横スクロールで端まで届くようにする。
        categoryStack.axis = .horizontal
        categoryStack.alignment = .fill
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryContentView.addSubview(categoryStack)

        // 下線 (Web 版のグラデーションで描かれる background-lighten-1 の 3px の帯)。
        categoryLine.backgroundColor = AppPalette.panel
        categoryLine.translatesAutoresizingMaskIntoConstraints = false
        // 線はスクロール側 (帯を含む) より下に置く。帯が線に隠れないようにするため。
        categoryBar.insertSubview(categoryLine, belowSubview: categoryScrollView)

        // 選択中の帯。ボタン群の左端から、項目の幅 (90px) × 順番だけずらす。
        categoryHighlight.backgroundColor = AppPalette.accent
        categoryHighlight.translatesAutoresizingMaskIntoConstraints = false
        categoryContentView.addSubview(categoryHighlight)
        highlightLeadingConstraint = categoryHighlight.leadingAnchor.constraint(
            equalTo: categoryStack.leadingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            categoryHighlight.bottomAnchor.constraint(equalTo: categoryContentView.bottomAnchor, constant: -10),
            categoryHighlight.heightAnchor.constraint(equalToConstant: 3),
            categoryHighlight.widthAnchor.constraint(equalToConstant: 90),
            highlightLeadingConstraint!,
        ])

        let contentWidth = categoryContentView.widthAnchor.constraint(equalTo: categoryStack.widthAnchor)
        contentWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            categoryScrollView.topAnchor.constraint(equalTo: categoryBar.topAnchor),
            categoryScrollView.leadingAnchor.constraint(equalTo: categoryBar.leadingAnchor),
            categoryScrollView.trailingAnchor.constraint(equalTo: categoryBar.trailingAnchor),
            categoryScrollView.bottomAnchor.constraint(equalTo: categoryBar.bottomAnchor),
            categoryContentView.leadingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.leadingAnchor),
            categoryContentView.trailingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.trailingAnchor),
            categoryContentView.topAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.topAnchor),
            categoryContentView.bottomAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.bottomAnchor),
            categoryContentView.heightAnchor.constraint(equalTo: categoryScrollView.frameLayoutGuide.heightAnchor),
            categoryContentView.widthAnchor.constraint(
                greaterThanOrEqualTo: categoryScrollView.frameLayoutGuide.widthAnchor),
            contentWidth,
            categoryStack.centerXAnchor.constraint(equalTo: categoryContentView.centerXAnchor),
            categoryStack.topAnchor.constraint(equalTo: categoryContentView.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryContentView.bottomAnchor, constant: -10),
            categoryLine.leadingAnchor.constraint(equalTo: categoryBar.leadingAnchor),
            categoryLine.trailingAnchor.constraint(equalTo: categoryBar.trailingAnchor),
            categoryLine.bottomAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: -10),
            categoryLine.heightAnchor.constraint(equalToConstant: 3),
        ])
        categoryBar.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 先頭画面ではシステムのナビゲーションバー (ページ名の見出し) を隠し、
        // Web 版のスマホ縦と同じく自前のヘッダーだけを出す。
        // 押し込んだ先の再生画面では戻るボタンが要るため、隠すのはこの画面の間だけ。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        let current = SettingsStore.shared.baseURL?.absoluteString
        if groups.isEmpty || current != loadedBaseURLString {
            refresh()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 再生画面など、押し込んだ先ではナビゲーションバーを元に戻す。
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - カテゴリ切り替え (タップと横ドラッグ)

    @objc private func categoryButtonTapped(_ sender: UIButton) {
        let target = sender.tag
        guard !isPageTransitioning, target != selectedGroupIndex,
              groups.indices.contains(target) else { return }
        // タップでも、ドラッグと同じ滑る動きで移る。新しいページは先頭から出す。
        let step = target > selectedGroupIndex ? 1 : -1
        isPageTransitioning = true
        currentTableView.isScrollEnabled = false
        let width = pagerContainer.bounds.width
        let neighbor = makeTableView(groupIndex: target)
        neighbor.isScrollEnabled = false
        neighbor.frame = CGRect(
            x: CGFloat(step) * width, y: 0,
            width: width, height: pagerContainer.bounds.height)
        pagerContainer.addSubview(neighbor)
        neighborTableView = neighbor
        pageDrag = PageDrag(
            targetIndex: target, step: step, startHeaderHidden: currentHeaderHidden())
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.currentTableView.frame.origin.x = -CGFloat(step) * width
            neighbor.frame.origin.x = 0
            self.highlightLeadingConstraint?.constant = CGFloat(target) * 90
            // 新しいページは先頭から出るため、ロゴ帯も先頭の位置に戻す。
            self.headerTopConstraint?.constant = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.finalizeCategorySwitch(toTable: neighbor, index: target)
            self.pageDrag = nil
        })
    }

    /// 横ドラッグのしぐさが成立するかどうか。横方向の動きのときだけ true を返し、
    /// 縦方向のときは false で即座に不成立にすることで、縦スクロールが
    /// 遅れずに始まるようにする (一覧側のスクロールはこの判定を待つ)。
    /// 向きの判定は、速度が出ていれば速度、無ければ移動量という具合に、
    /// 1つのベクトルでそろえて行う。以前は軸ごとに移動量と速度を
    /// 混ぜて比べていたため、横へ引いても縦の速度の揺れに負けて
    /// 「縦」と判定され、特に右向きやカードの上で拾えないことがあった。
    /// 左右どちらの向きでも、判定はこの1か所で同じ条件にしている。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === pagePan else {
            return true
        }
        guard !isPageTransitioning, groups.count > 1 else {
            return false
        }
        let velocity = pan.velocity(in: pagerContainer)
        let translation = pan.translation(in: pagerContainer)
        let useVelocity = abs(velocity.x) > 1 || abs(velocity.y) > 1
        let dx = useVelocity ? velocity.x : translation.x
        let dy = useVelocity ? velocity.y : translation.y
        return abs(dx) > abs(dy)
    }

    @objc private func handlePagePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            startPageDrag(
                initialTranslationX: pan.translation(in: pagerContainer).x,
                initialVelocity: pan.velocity(in: pagerContainer))
        case .changed:
            updatePageDrag(translationX: pan.translation(in: pagerContainer).x)
        case .ended, .cancelled:
            finishPageDrag(
                translationX: pan.translation(in: pagerContainer).x,
                velocity: pan.velocity(in: pagerContainer))
        default:
            break
        }
    }

    /// ドラッグの開始。進む向きに隣のページがあれば、そのページを横に並べておく。
    /// 端で隣が無い場合はページを用意せず、抵抗付きの小さな動きだけにする。
    private func startPageDrag(initialTranslationX: CGFloat, initialVelocity: CGPoint) {
        // 左へ払う動きで次のカテゴリ、右で前のカテゴリ。
        // 向きは、開始時点までの移動量が読み取れればそちらを優先し、
        // 読み取れないときは速度で決める (ゆっくりしたドラッグでは
        // 開始時点の速度がほぼ 0 になり、向きを取り違えるため)。
        let directionX = abs(initialTranslationX) > 2 ? initialTranslationX : initialVelocity.x
        let step = directionX < 0 ? 1 : -1
        let target = selectedGroupIndex + step
        isPageTransitioning = true
        currentTableView.isScrollEnabled = false
        var drag = PageDrag(
            targetIndex: nil, step: step, startHeaderHidden: currentHeaderHidden())
        if groups.indices.contains(target) {
            let width = pagerContainer.bounds.width
            let neighbor = makeTableView(groupIndex: target)
            neighbor.isScrollEnabled = false
            neighbor.frame = CGRect(
                x: CGFloat(step) * width, y: 0,
                width: width, height: pagerContainer.bounds.height)
            pagerContainer.addSubview(neighbor)
            neighborTableView = neighbor
            drag.targetIndex = target
        }
        pageDrag = drag
    }

    /// ドラッグ中の追随。今のページと隣のページを指の移動量そのままで動かし、
    /// カテゴリ帯の下線とロゴ帯の位置も進み具合に連動させる。
    /// 隣が無い端では、移動量を小さく抑えて「これ以上行けない」感触にする。
    private func updatePageDrag(translationX rawX: CGFloat) {
        guard let drag = pageDrag else { return }
        let width = pagerContainer.bounds.width
        guard width > 0 else { return }
        var tx = rawX
        if drag.targetIndex != nil {
            // 進む方向への移動量 (正で前進)。逆向きへは抵抗を付ける。
            let toward = -CGFloat(drag.step) * rawX
            if toward >= 0 {
                tx = max(-width, min(width, rawX))
            } else {
                tx = rawX * 0.25
            }
            let progress = min(max(toward / width, 0), 1)
            currentTableView.frame.origin.x = tx
            neighborTableView?.frame.origin.x = CGFloat(drag.step) * width + tx
            // 下線は今の項目と隣の項目の間を、進み具合に応じて滑る。
            highlightLeadingConstraint?.constant =
                (CGFloat(selectedGroupIndex) + CGFloat(drag.step) * progress) * 90
            // 隣のページは先頭 (ロゴ帯が見える状態) から来るため、
            // ロゴ帯の隠れ具合も進み具合に合わせて戻していく。
            headerTopConstraint?.constant = -(drag.startHeaderHidden * (1 - progress))
        } else {
            // 端: 隣が無いので、少しだけ動いて止まる。
            tx = max(-44, min(44, rawX * 0.2))
            currentTableView.frame.origin.x = tx
        }
    }

    /// ドラッグの終わり。半分以上引いていたら隣へ進み、勢いが付いていれば
    /// 少ない移動でも進む。それ以外は元のページへ戻る。
    private func finishPageDrag(translationX rawX: CGFloat, velocity: CGPoint) {
        guard let drag = pageDrag else { return }
        let width = pagerContainer.bounds.width
        var shouldComplete = false
        if drag.targetIndex != nil {
            let toward = -CGFloat(drag.step) * rawX
            let progress = toward / max(width, 1)
            let towardVelocity = -CGFloat(drag.step) * velocity.x
            shouldComplete = progress > 0.5 || (towardVelocity > 550 && progress > 0.12)
        }
        animatePageSlide(complete: shouldComplete, drag: drag)
    }

    /// ドラッグの締めのアニメーション。進む場合は隣のページを所定の位置まで、
    /// 戻る場合は今のページと下線・ロゴ帯を開始時点の状態まで、それぞれ滑らせる。
    private func animatePageSlide(complete: Bool, drag: PageDrag) {
        let width = pagerContainer.bounds.width
        let neighbor = neighborTableView
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            if complete, let neighbor, let target = drag.targetIndex {
                self.currentTableView.frame.origin.x = -CGFloat(drag.step) * width
                neighbor.frame.origin.x = 0
                self.highlightLeadingConstraint?.constant = CGFloat(target) * 90
                self.headerTopConstraint?.constant = 0
            } else {
                self.currentTableView.frame.origin.x = 0
                if let neighbor {
                    neighbor.frame.origin.x = CGFloat(drag.step) * width
                }
                self.highlightLeadingConstraint?.constant = CGFloat(self.selectedGroupIndex) * 90
                self.headerTopConstraint?.constant = -(drag.startHeaderHidden)
            }
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if complete, let neighbor, let target = drag.targetIndex {
                self.finalizeCategorySwitch(toTable: neighbor, index: target)
            } else {
                neighbor?.removeFromSuperview()
                self.neighborTableView = nil
                self.currentTableView.isScrollEnabled = true
                self.isPageTransitioning = false
            }
            self.pageDrag = nil
        })
    }

    /// ページの入れ替えの後片付け。隣だったページを今のページにし、
    /// 引っ張り直しの下準備と、帯の中で選ばれている項目が見える位置への
    /// スクロールを付け直す。
    private func finalizeCategorySwitch(toTable newTable: UITableView, index: Int) {
        let old = currentTableView
        old?.refreshControl = nil
        old?.removeFromSuperview()
        currentTableView = newTable
        neighborTableView = nil
        selectedGroupIndex = index
        newTable.isScrollEnabled = true
        newTable.refreshControl = refreshControl
        newTable.frame = pagerContainer.bounds
        updateCategoryHighlight(animated: false)
        scrollCategoryBarToSelected()
        updateHeaderPosition()
        isPageTransitioning = false
    }

    /// カテゴリ帯が横スクロールできる並びのとき、選ばれている項目が
    /// 帯の中に見えるよう位置を合わせる。
    private func scrollCategoryBarToSelected() {
        guard categoryButtons.indices.contains(selectedGroupIndex) else { return }
        let button = categoryButtons[selectedGroupIndex]
        let frameInContent = button.convert(button.bounds, to: categoryContentView)
        let target = frameInContent.insetBy(dx: -10, dy: 0)
        UIView.animate(withDuration: 0.3) {
            self.categoryScrollView.scrollRectToVisible(target, animated: false)
        }
    }

    /// 選択中の帯を選ばれている項目の下へ移す。Web 版は 0.3 秒で滑らかに動く。
    private func updateCategoryHighlight(animated: Bool) {
        highlightLeadingConstraint?.constant = CGFloat(selectedGroupIndex) * 90
        categoryHighlight.isHidden = groups.isEmpty
        guard animated else { return }
        UIView.animate(withDuration: 0.3) {
            self.categoryBar.layoutIfNeeded()
        }
    }

    // MARK: - ヘッダー (ロゴ帯 + カテゴリ帯) の位置

    /// いまのページのスクロールで、ロゴ帯がどれだけ隠れているか (0〜ロゴ帯の高さ)。
    private func currentHeaderHidden() -> CGFloat {
        let scrolled = currentTableView.contentOffset.y + tablesTopInset
        return min(max(scrolled, 0), SPHeaderView.height)
    }

    /// 重ね物の位置を、いまのページのスクロールに合わせる。
    /// ロゴ帯が流れ終わるまでは一緒に上がり、それ以降はカテゴリ帯が上端に残る。
    private func updateHeaderPosition() {
        headerTopConstraint?.constant = -currentHeaderHidden()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // ページ切り替えの最中は、ヘッダーの位置はドラッグ／アニメーション側が受け持つ。
        guard scrollView === currentTableView, !isPageTransitioning else { return }
        updateHeaderPosition()
    }

    /// カテゴリの有無に合わせて、重ね物の高さとページの上端の空きを直す。
    /// 先頭にいたページは、先頭のまま見えるよう位置も合わせ直す。
    private func updateHeaderMetrics() {
        categoryBar.isHidden = groups.isEmpty
        categoryBarHeightConstraint?.constant = categoryBarHeight
        headerHeightConstraint?.constant = SPHeaderView.height + categoryBarHeight
        for table in [currentTableView, neighborTableView].compactMap({ $0 }) {
            let oldTop = table.contentInset.top
            let newTop = tablesTopInset
            guard oldTop != newTop else { continue }
            let wasAtTop = table.contentOffset.y <= -oldTop + 0.5
            table.contentInset.top = newTop
            table.scrollIndicatorInsets.top = newTop
            if wasAtTop {
                table.contentOffset.y = -newTop
            }
        }
        updateHeaderPosition()
    }

    /// カテゴリ切り替えの並びを、取得できたカテゴリだけで組み直す。
    private func rebuildCategoryControl() {
        for button in categoryButtons {
            categoryStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        categoryButtons.removeAll()
        for (index, group) in groups.enumerated() {
            // 押したときの波紋も付ける (共通部品の波紋つきボタン)。
            // 選ばれている印の下線は帯側の別の部品で、ボタンの中の
            // 波紋とは重ならない。
            let button = RippleButton()
            button.tag = index
            button.setTitle(Self.prettyTypeName(group.type), for: .normal)
            // Web 版のボタンは文字 15px、色は text (選択中でも同じ)。
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.setTitleColor(AppPalette.text, for: .normal)
            button.addTarget(self, action: #selector(categoryButtonTapped(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 90).isActive = true
            categoryStack.addArrangedSubview(button)
            categoryButtons.append(button)
        }
        if !groups.indices.contains(selectedGroupIndex) {
            selectedGroupIndex = 0
        }
        updateCategoryHighlight(animated: false)
    }

    /// API の種別名を表示用の名前にする (Web 版の表現に合わせる)。
    private static func prettyTypeName(_ type: String) -> String {
        switch type {
        case "GR": return "地デジ"
        case "BS": return "BS"
        case "CS": return "CS"
        case "CATV": return "CATV"
        case "SKY": return "SKY"
        case "BS4K": return "BS4K"
        default: return type
        }
    }

    @objc private func refresh() {
        guard !isLoading else { return }
        guard SettingsStore.shared.isConfigured else {
            statusLabel.text = "設定タブで接続先 URL を設定してください。"
            refreshControl.endRefreshing()
            return
        }
        // 接続先が変わっていたら、前の接続先のロゴは使い回さない。
        if SettingsStore.shared.baseURL?.absoluteString != loadedBaseURLString {
            logoCache.removeAllObjects()
            failedLogoIDs.removeAll()
        }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await APIClient.shared.fetchChannels()
                self.loadedBaseURLString = SettingsStore.shared.baseURL?.absoluteString
                // Web 版で表示対象になっているチャンネルだけに絞る (印が無い場合は全部出す)。
                // 設定が入っていれば、各分類の中で実況の勢いが強い順に並び替える
                // (Web 版の「実況勢いが強い順」と同じ。勢いが同じか無い局は
                // チャンネル番号の順を保つ)。
                let sortByForce = SyncedSettingsStore.shared.current.tvChannelSortByJikkyoForce
                self.groups = response.groups.map { group in
                    var channels = group.channels.filter { $0.is_display ?? true }
                    if sortByForce {
                        channels = channels.enumerated().sorted { lhs, rhs in
                            let lhsForce = lhs.element.jikkyo_force ?? 0
                            let rhsForce = rhs.element.jikkyo_force ?? 0
                            if lhsForce != rhsForce { return lhsForce > rhsForce }
                            return lhs.offset < rhs.offset
                        }.map(\.element)
                    }
                    return (type: group.type, channels: channels)
                }.filter { !$0.channels.isEmpty }
                self.statusLabel.text = self.groups.isEmpty ? "チャンネルがありません。" : nil
                self.rebuildCategoryControl()
                // カテゴリの並びが変わっていた場合に備え、表示中のページの
                // 番号を選択中の項目に付け直してから読み直す。
                self.currentTableView.tag = self.selectedGroupIndex
                self.currentTableView.reloadData()
                self.updateHeaderMetrics()
            } catch {
                if self.groups.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。\n(\(error.localizedDescription))"
                }
            }
            self.isLoading = false
            self.refreshControl.endRefreshing()
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        channels(forGroupAt: tableView.tag).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: LiveChannelCell.reuseID, for: indexPath) as! LiveChannelCell
        let channel = channels(forGroupAt: tableView.tag)[indexPath.row]
        cell.configure(with: channel)
        // ロゴはキャッシュにあればその場で出し、無ければ行ごとに後から読み込む
        // (一覧の表示をロゴの取得で待たせない)。
        if let logo = logoCache.object(forKey: channel.id as NSString) {
            cell.setLogo(logo)
        } else {
            loadLogo(for: channel, at: indexPath, in: tableView)
        }
        return cell
    }

    /// 局ロゴを取ってきて、表示中の行がまだ同じ局ならその場で反映する。
    /// 取れなかった局 (ロゴ無しなど) は文字だけの行のままにし、再取得もしない。
    private func loadLogo(for channel: LiveChannel, at indexPath: IndexPath, in tableView: UITableView) {
        guard !failedLogoIDs.contains(channel.id) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channel.id),
                  let image = UIImage(data: data) else {
                self.failedLogoIDs.insert(channel.id)
                return
            }
            self.logoCache.setObject(image, forKey: channel.id as NSString)
            // カテゴリ切り替えなどで行の対応が変わっていたら反映しない
            // (次にその行が表示されるときにキャッシュから出る)。
            let channels = self.channels(forGroupAt: tableView.tag)
            guard channels.indices.contains(indexPath.row),
                  channels[indexPath.row].id == channel.id,
                  let cell = tableView.cellForRow(at: indexPath) as? LiveChannelCell else { return }
            cell.setLogo(image)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channels(forGroupAt: tableView.tag)[indexPath.row]
        let player = LivePlayerViewController(channel: channel)
        navigationController?.pushViewController(player, animated: true)
    }
}

/// カード下端の進み具合バー。Web 版の channel__progressbar と同じ:
/// 下地は gray、進んだ分は primary、高さ 4px。
final class LiveProgressView: UIView {
    var ratio: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        AppPalette.placeholder.setFill()
        UIRectFill(rect)
        let clamped = min(max(ratio, 0), 1)
        guard clamped > 0 else { return }
        AppPalette.accent.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: rect.width * CGFloat(clamped), height: rect.height))
    }
}

/// 生放送一覧の1件。Web 版のチャンネルカード (TV/Home.vue、スマホ縦) の寸法に
/// 合わせた、独立した角丸カード。
/// 中身の並びは Web 版カードどおり: 局ロゴ (69x40) の右に「Ch: 番号 局名」と
/// 勢い・視聴数、その下に放送中番組の題名 → 時刻 → 説明文、
/// 続けて「NEXT 次の番組の題名」→ 時刻。カード下端に進み具合のバー。
final class LiveChannelCell: UITableViewCell {
    static let reuseID = "LiveChannelCell"

    private let cardView = UIView()
    private let logoView = UIImageView()
    private let nameLabel = UILabel()
    private let forceIconView = UIImageView()
    private let forceLabel = UILabel()
    private let viewersIconView = UIImageView()
    private let viewersLabel = UILabel()
    private let presentTitleLabel = UILabel()
    private let presentTimeLabel = UILabel()
    private let presentDescriptionLabel = UILabel()
    private let followingNextLabel = UILabel()
    private let followingIconView = UIImageView()
    private let followingTitleLabel = UILabel()
    private let followingTimeLabel = UILabel()
    private let progressView = LiveProgressView()
    /// 押したときの波紋 (共通部品)。本家 Web 版のカードと同じく、
    /// カード全体を対象に、触れた位置から広げる。
    private let ripple = RippleSurface()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        // セル自体は透明にし、カードだけを見せる。押したときはカードの面が
        // 一段明るくなる (Web 版カードの hover = background-lighten-2。
        // タッチ機器では Web 版も hover を無効化しているが、押下の手応えとして残す)。
        backgroundColor = .clear
        selectionStyle = .none

        // カードは Web 版 (スマホ縦) どおり角丸 11px、面は background-lighten-1。
        // 進み具合バーを下端で切り抜くため clipsToBounds が要る。
        cardView.backgroundColor = AppPalette.panel
        cardView.layer.cornerRadius = 11
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        // 局ロゴは Web 版 (スマホ縦) どおり 69x40px、角丸 4px。
        // 読み込まれるまでの地は Web 版では gray → lighten-2 のグラデーションだが、
        // ここでは gray のベタで近似する。
        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.backgroundColor = AppPalette.placeholder
        logoView.layer.cornerRadius = 4
        logoView.translatesAutoresizingMaskIntoConstraints = false

        // 局名は Web 版 (スマホ縦) どおり 15.5px、色は text、1行で省略。
        nameLabel.font = .systemFont(ofSize: 15.5)
        nameLabel.textColor = AppPalette.text
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        // 勢い・視聴数は Web 版 (スマホ縦) どおり 11px、色は text-darken-1。
        forceLabel.font = .systemFont(ofSize: 11)
        forceLabel.textColor = AppPalette.metaText
        viewersLabel.font = .systemFont(ofSize: 11)
        viewersLabel.textColor = AppPalette.metaText
        // アイコンは Web 版では勢いが炎 (10.5x12px)、視聴数が目 (15.75x14px)。
        // 字形の近い SF Symbol で近似する。
        forceIconView.contentMode = .scaleAspectFit
        viewersIconView.contentMode = .scaleAspectFit

        let forceGroup = UIStackView(arrangedSubviews: [forceIconView, forceLabel])
        forceGroup.axis = .horizontal
        forceGroup.alignment = .center
        forceGroup.spacing = 4
        let viewersGroup = UIStackView(arrangedSubviews: [viewersIconView, viewersLabel])
        viewersGroup.axis = .horizontal
        viewersGroup.alignment = .center
        viewersGroup.spacing = 4
        // 2つの並びの間は Web 版の ml-4 = 16px。
        let statusRow = UIStackView(arrangedSubviews: [forceGroup, viewersGroup])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 16

        // 局名と状態の間は Web 版の status の margin-top 2px。
        let broadcasterContent = UIStackView(arrangedSubviews: [nameLabel, statusRow])
        broadcasterContent.axis = .vertical
        broadcasterContent.spacing = 2
        broadcasterContent.translatesAutoresizingMaskIntoConstraints = false

        // ロゴと本文の間は Web 版 (スマホ縦) の margin-left 14px。
        let broadcasterRow = UIStackView(arrangedSubviews: [logoView, broadcasterContent])
        broadcasterRow.axis = .horizontal
        broadcasterRow.alignment = .center
        broadcasterRow.spacing = 14

        // 放送中番組の題名は Web 版 (スマホ縦) どおり 14px 太字、1行で省略
        // (縦画面では Web 版も display:block + nowrap で1行に制限している)。
        presentTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        presentTitleLabel.textColor = AppPalette.text
        presentTitleLabel.numberOfLines = 1
        presentTitleLabel.lineBreakMode = .byTruncatingTail

        // 放送中番組の時刻は Web 版 (スマホ縦) どおり 12px、text-darken-1。
        presentTimeLabel.font = .systemFont(ofSize: 12)
        presentTimeLabel.textColor = AppPalette.metaText
        presentTimeLabel.numberOfLines = 1

        // 説明文は Web 版 (スマホ縦) どおり 10px、text-darken-1、最大2行。
        presentDescriptionLabel.font = .systemFont(ofSize: 10)
        presentDescriptionLabel.textColor = AppPalette.metaText
        presentDescriptionLabel.numberOfLines = 2
        presentDescriptionLabel.lineBreakMode = .byTruncatingTail

        // 次の番組は Web 版 (スマホ縦) どおり 12px。「NEXT」は太字、
        // 続く二重三角のアイコン (16x16px) は SF Symbol で近似する。
        followingNextLabel.text = "NEXT"
        followingNextLabel.font = .systemFont(ofSize: 12, weight: .bold)
        followingNextLabel.textColor = AppPalette.text
        // Web 版では「NEXT」とアイコンは縮まず (flex-shrink: 0)、番組名が残りの幅を
        // 受け持って左に続き、はみ出す分は省略される。横並びのスタックでは
        // 優先度を付けないと「NEXT」側が伸びて番組名が右端へ飛んでしまうため、
        // 「NEXT」とアイコンは幅を固定する側、番組名は伸び縮みする側に振り分ける。
        followingNextLabel.setContentHuggingPriority(.required, for: .horizontal)
        followingNextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        followingIconView.setContentHuggingPriority(.required, for: .horizontal)
        followingTitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        followingTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        followingIconView.contentMode = .scaleAspectFit
        followingIconView.image = UIImage(
            systemName: "forward.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)
        )?.withTintColor(AppPalette.text, renderingMode: .alwaysOriginal)
        followingTitleLabel.font = .systemFont(ofSize: 12)
        followingTitleLabel.textColor = AppPalette.text
        followingTitleLabel.numberOfLines = 1
        followingTitleLabel.lineBreakMode = .byTruncatingTail

        // アイコンの前は 3px、題名の前は 2px (Web 版の margin-left)。
        let followingRow = UIStackView(arrangedSubviews: [followingNextLabel, followingIconView, followingTitleLabel])
        followingRow.axis = .horizontal
        followingRow.alignment = .center
        followingRow.setCustomSpacing(3, after: followingNextLabel)
        followingRow.setCustomSpacing(2, after: followingIconView)

        // 次の番組の時刻は Web 版 (スマホ縦) どおり 11.5px、text-darken-1。
        followingTimeLabel.font = .systemFont(ofSize: 11.5)
        followingTimeLabel.textColor = AppPalette.metaText
        followingTimeLabel.numberOfLines = 1

        // Web 版の並び: 局の行 → 題名 → 時刻 → 説明文 → 次の番組 → その時刻。
        // 間隔は、題名の上 8px (title-wrapper の margin-top)、時刻の上 1px、
        // 説明文の上 4px、次の番組の上 4px (いずれもスマホ縦の値)。
        let mainStack = UIStackView(arrangedSubviews: [
            broadcasterRow, presentTitleLabel, presentTimeLabel,
            presentDescriptionLabel, followingRow, followingTimeLabel,
        ])
        mainStack.axis = .vertical
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.setCustomSpacing(8, after: broadcasterRow)
        mainStack.setCustomSpacing(1, after: presentTitleLabel)
        mainStack.setCustomSpacing(4, after: presentTimeLabel)
        mainStack.setCustomSpacing(4, after: presentDescriptionLabel)
        cardView.addSubview(mainStack)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(progressView)

        // 波紋の入れ物はカードの一番上に重ねる (操作は受けない)。
        cardView.addSubview(ripple.container)

        // カード間の余白は Web 版 (スマホ縦) の行間 10px、
        // 画面の左右は同コンテナの左右パディング 8px。
        // カード内は Web 版 (スマホ縦) の padding: 上 10px、左右 14px、下 12px。
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 69),
            logoView.heightAnchor.constraint(equalToConstant: 40),
            forceIconView.widthAnchor.constraint(equalToConstant: 11),
            forceIconView.heightAnchor.constraint(equalToConstant: 12),
            viewersIconView.widthAnchor.constraint(equalToConstant: 16),
            viewersIconView.heightAnchor.constraint(equalToConstant: 14),
            followingIconView.widthAnchor.constraint(equalToConstant: 16),
            followingIconView.heightAnchor.constraint(equalToConstant: 16),
            mainStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            mainStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            mainStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            progressView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 押したときの反応は波紋だけにする。本家ではカードの地が
    // 明るくなるのはホバー向けの決まりで、タッチでは無効にする
    // 上書きまで入っているため、地の変化は付けない。
    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: cardView.bounds, cornerRadius: cardView.layer.cornerRadius)
    }

    // カードへのタッチで波紋を出す。タッチは中身の部品 (文字や絵) では
    // 受けず、カード面を通してセルまで届く。スクロールが始まると
    // 「取り消し」が届くので、そこで波紋を取り消す。
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        ripple.startRipple(at: touch.location(in: cardView))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        ripple.endRipple()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        ripple.cancelRipple()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        logoView.image = nil
        presentDescriptionLabel.text = nil
        progressView.ratio = 0
    }

    func configure(with channel: LiveChannel) {
        // 局名行は Web 版どおり「Ch: 番号 局名」。番号が無い応答では局名だけにする。
        if let number = channel.channel_number, !number.isEmpty {
            nameLabel.text = "Ch: \(number) \(channel.name)"
        } else {
            nameLabel.text = channel.name
        }
        // 勢い。対応する実況が無い局では Web 版どおり「--」を出す。
        // 勢いの段階で色が変わる (ChannelUtils.getChannelForceType):
        // 500以上は祭 #E7556E、200以上は #E76B55、100以上は #E7A355。
        let force = channel.jikkyo_force
        forceLabel.text = "勢い: \(force.map(String.init) ?? "--") コメ/分"
        let forceColor: UIColor
        switch force ?? 0 {
        case 500...: forceColor = UIColor(red: 0xE7 / 255, green: 0x55 / 255, blue: 0x6E / 255, alpha: 1)
        case 200...: forceColor = UIColor(red: 0xE7 / 255, green: 0x6B / 255, blue: 0x55 / 255, alpha: 1)
        case 100...: forceColor = UIColor(red: 0xE7 / 255, green: 0xA3 / 255, blue: 0x55 / 255, alpha: 1)
        default: forceColor = AppPalette.metaText
        }
        forceLabel.textColor = forceColor
        forceIconView.image = UIImage(
            systemName: "flame.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)
        )?.withTintColor(forceColor, renderingMode: .alwaysOriginal)
        viewersLabel.text = "視聴数: \(channel.viewer_count ?? 0)"
        viewersIconView.image = UIImage(
            systemName: "eye.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)
        )?.withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal)

        // 放送中の番組。無い (放送休止中など) ときは行ごと隠す。
        if let present = channel.program_present {
            // 題名の [字] [再] などは、Web 版のテレビ一覧のカードと同じく
            // ピンク地の印に描き分ける (再生画面の情報欄と同じ部品を使う)。
            presentTitleLabel.attributedText = decoratedProgramTitle(
                present.title, font: presentTitleLabel.font, textColor: AppPalette.text)
            presentTitleLabel.isHidden = false
            presentTimeLabel.text = Self.programTimeText(present)
            presentTimeLabel.isHidden = presentTimeLabel.text?.isEmpty ?? true
            let description = present.description ?? ""
            presentDescriptionLabel.text = description
            presentDescriptionLabel.isHidden = description.isEmpty
            progressView.isHidden = false
            progressView.ratio = Self.programProgress(present)
        } else {
            presentTitleLabel.isHidden = true
            presentTimeLabel.isHidden = true
            presentDescriptionLabel.isHidden = true
            progressView.isHidden = true
        }

        // 次の番組。無いときは行ごと隠す。
        if let following = channel.program_following {
            followingNextLabel.isHidden = false
            followingIconView.isHidden = false
            followingTitleLabel.attributedText = decoratedProgramTitle(
                following.title, font: followingTitleLabel.font, textColor: AppPalette.text)
            followingTitleLabel.isHidden = false
            followingTimeLabel.text = Self.programTimeText(following)
            followingTimeLabel.isHidden = followingTimeLabel.text?.isEmpty ?? true
        } else {
            followingNextLabel.isHidden = true
            followingIconView.isHidden = true
            followingTitleLabel.isHidden = true
            followingTimeLabel.isHidden = true
        }
    }

    /// Web 版の ProgramUtils.getProgramTime (時刻のみ) と同じ形: "HH:mm ～ HH:mm"。
    /// 設定が入っていれば 28 時間表記の置き換えも行う (Web 版と同じ)。
    private static func programTimeText(_ program: LiveProgram) -> String {
        guard let start = program.startDate, let end = program.endDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return TimeFormat.apply28HourClock("\(formatter.string(from: start)) ～ \(formatter.string(from: end))")
    }

    /// Web 版の ProgramUtils.getProgramProgress と同じ計算:
    /// 開始からの経過秒 ÷ 番組の長さ (秒) × 100 を、0〜1 の割合で返す。
    private static func programProgress(_ program: LiveProgram) -> Double {
        guard let start = program.startDate, let end = program.endDate, end > start else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(max(elapsed / end.timeIntervalSince(start), 0), 1)
    }

    /// 局ロゴを出す。取れなかった局では呼ばれず、地だけのままになる。
    func setLogo(_ image: UIImage) {
        logoView.image = image
    }
}
