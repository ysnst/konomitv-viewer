import UIKit

/// マイリストの画面。マイページの「マイリスト」の入口から開く。
///
/// 本家 Web 版のマイリスト (views/Mylist.vue) と同じ作り:
/// - 実体は利用者設定の mylist (Web 版と共通で、世帯で共有される)。
///   アプリで表示するのは録画番組の登録だけ (シリーズの登録は表示しないが、
///   保存のときに落とさない。SyncedSettings 側の読み書きで保持される)。
/// - 並び替えは4種 (追加が新しい順／古い順、録画が新しい順／古い順)。
///   追加順のときは、登録の並びを保つ取り方 (order=ids) でサーバーから取り、
///   録画順のときは、登録済みの番号の範囲内で録画日時の順に並べ替えて取る
///   (Web 版と同じ取り方)。
/// - 並びは録画一覧と同じカード (VideoCell) で、30件ごとのページ分け、
///   ページ送りは一覧の上と下の両方に置く (録画一覧・視聴履歴と同じ)。
/// - カードを押すと再生画面へ移る。長押しメニューに「マイリストから削除」を
///   置く。録画一覧と同じ「視聴済みにする」と「保護する／外す」(拡張版だけ)
///   も一緒に出す。
///
/// マイリストは、ログイン中かつ「設定をデバイス間で同期する」がオンのとき
/// だけ働く (視聴履歴と揃えた扱い)。その条件を満たさないときは一覧の代わりに
/// 案内を出す。端末だけに残す控えは持たない (Web 版と二重管理にしないため)。
///
/// 見出し帯は視聴履歴の画面と同じ形: 高さ 60px・地は background-lighten-1、
/// 左端は矢印だけの戻るボタン、ページ名 22px。端からの横スワイプでも戻れる。
final class MylistViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    /// 1ページの件数。サーバー側の固定値 (PAGE_SIZE = 30) に合わせる。
    private static let pageSize = 30

    /// 並び替えの種類 (Web 版の MylistSortOrder と同じ4種)。
    private enum SortOrder: CaseIterable {
        case addedDesc
        case addedAsc
        case recordedDesc
        case recordedAsc

        /// 画面に出す名前 (Web 版の選択肢と同じ文面)。
        var title: String {
            switch self {
            case .addedDesc: return "追加が新しい順"
            case .addedAsc: return "追加が古い順"
            case .recordedDesc: return "録画が新しい順"
            case .recordedAsc: return "録画が古い順"
            }
        }

        /// サーバーへ渡す並び順の指定。追加順は登録の並びを保つ "ids"、
        /// 録画順は録画日時の "desc" / "asc"。
        var apiOrder: String {
            switch self {
            case .addedDesc, .addedAsc: return "ids"
            case .recordedDesc: return "desc"
            case .recordedAsc: return "asc"
            }
        }
    }

    private let backButton = RippleButton()
    /// 見出し帯。一覧まわりはこの帯の下端に留めて組むため保持する。
    private let headingBar = UIView()
    /// 見出し行 (件数と並び替えボタン)。視聴履歴には無い、マイリスト固有の行。
    private let sortRowView = UIView()
    private let countLabel = UILabel()
    private let sortButton = RippleButton()
    private let topPaginationView = PaginationView()
    /// 上のページ送りの高さ。番組が無いときは隠すだけでなく高さも畳む
    /// (帯状の空白が残らないように)。
    private var topPaginationHeightConstraint: NSLayoutConstraint?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let bottomPaginationView = PaginationView()
    private var bottomPaginationFooter: UIView?
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()

    /// いまの並び替え (Web 版の既定と同じ「追加が新しい順」)。
    private var sortOrder: SortOrder = .addedDesc
    /// 並び替えに合わせて並べた、マイリストの録画番組の ID。
    /// ページ取得の元になる。
    private var mylistIDs: [Int] = []
    /// いま表示しているページの番組 (最大で pageSize 件)。
    private var programs: [RecordedProgram] = []
    /// 表示上の全件数 (サーバー応答の total。登録のうち実在する録画の件数)。
    private var total = 0
    private var currentPage = 1
    private var isLoading = false

    private let thumbnailCache = NSCache<NSNumber, UIImage>()
    /// サムネイルを取得中の番組 ID と、失敗して取り直し待ちの番組 ID。
    /// 同じ番組への取得を重ねないことと、失敗したままにしないために使う。
    private var thumbnailLoadingIDs: Set<Int> = []
    private var thumbnailRetryingIDs: Set<Int> = []
    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (録画一覧と同じ方式)。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []
    /// ロゴを取得中の局。同じロゴを何度も取りに行かないための
    /// 重ね防ぎ (録画一覧と同じ)。
    private var logoLoadingIDs: Set<String> = []

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "マイリスト"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildHeadingBar()
        buildSortRow()

        topPaginationView.onPageSelected = { [weak self] page in
            self?.goToPage(page)
        }
        view.addSubview(topPaginationView)
        topPaginationView.translatesAutoresizingMaskIntoConstraints = false

        // 下のページ送りはテーブルの末尾に付ける (録画一覧と同じ)。
        bottomPaginationView.onPageSelected = { [weak self] page in
            self?.goToPage(page)
        }
        let footer = UIView()
        footer.addSubview(bottomPaginationView)
        bottomPaginationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomPaginationView.topAnchor.constraint(equalTo: footer.topAnchor),
            bottomPaginationView.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            bottomPaginationView.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            bottomPaginationView.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
        ])
        bottomPaginationFooter = footer
        tableView.tableFooterView = footer

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 125
        tableView.backgroundColor = AppPalette.background
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        topPaginationHeightConstraint = topPaginationView.heightAnchor
            .constraint(equalToConstant: PaginationView.preferredHeight)
        NSLayoutConstraint.activate([
            topPaginationView.topAnchor.constraint(equalTo: sortRowView.bottomAnchor),
            topPaginationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topPaginationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topPaginationHeightConstraint!,
            tableView.topAnchor.constraint(equalTo: topPaginationView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        updatePagination()
        updateSortRow()
    }

    /// 見出し帯 (視聴履歴の画面と同じ形)。
    private func buildHeadingBar() {
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "マイリスト"
        headingLabel.font = .scaledSystemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)
        NSLayoutConstraint.activate([
            headingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headingBar.heightAnchor.constraint(equalToConstant: 60),
            headingStack.leadingAnchor.constraint(equalTo: headingBar.leadingAnchor, constant: 8),
            headingStack.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: headingBar.trailingAnchor, constant: -16),
        ])
        // 画面の左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    /// 見出し行 (左に件数、右端に並び替えボタン)。録画一覧の見出し行と
    /// フィルタボタンの形に寄せてある。
    private func buildSortRow() {
        countLabel.font = .scaledSystemFont(ofSize: 13)
        countLabel.textColor = AppPalette.metaText
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        sortRowView.addSubview(countLabel)
        sortButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        sortButton.setTitleColor(AppPalette.text, for: .normal)
        sortButton.setImage(
            UIImage(systemName: "arrow.up.arrow.down")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        sortButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        sortButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        sortButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        sortButton.layer.cornerRadius = 14
        sortButton.layer.borderWidth = 1
        sortButton.layer.borderColor = AppPalette.fieldBorder.cgColor
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        sortRowView.addSubview(sortButton)
        sortRowView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sortRowView)
        NSLayoutConstraint.activate([
            sortRowView.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
            sortRowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sortRowView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sortRowView.heightAnchor.constraint(equalToConstant: 44),
            countLabel.leadingAnchor.constraint(equalTo: sortRowView.leadingAnchor, constant: 16),
            countLabel.centerYAnchor.constraint(equalTo: sortRowView.centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: sortRowView.trailingAnchor, constant: -16),
            sortButton.centerYAnchor.constraint(equalTo: sortRowView.centerYAnchor),
        ])
    }

    /// 件数と並び替えボタンの表示を、いまの状態に合わせる。
    private func updateSortRow() {
        countLabel.text = total > 0 ? "\(total)件" : ""
        sortButton.setTitle(sortOrder.title, for: .normal)
        sortButton.menu = UIMenu(children: SortOrder.allCases.map { order in
            UIAction(title: order.title, state: order == sortOrder ? .on : .off) { [weak self] _ in
                self?.changeSortOrder(order)
            }
        })
    }

    /// 並び替えの切り替え。変えたら1ページ目から読み直す (Web 版と同じ)。
    private func changeSortOrder(_ order: SortOrder) {
        guard !isLoading, order != sortOrder else { return }
        sortOrder = order
        updateSortRow()
        reloadMylist(page: 1)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // テーブルの末尾に付けたページ送りは、幅と高さをテーブル幅に
        // 合わせ直す (録画一覧と同じ)。
        guard let footer = bottomPaginationFooter else { return }
        let size = CGSize(width: tableView.bounds.width, height: PaginationView.preferredHeight)
        if footer.frame.size != size {
            footer.frame = CGRect(origin: .zero, size: size)
            tableView.tableFooterView = footer
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 見出し帯を自前で出すため、ナビゲーションバーは隠す
        // (視聴履歴の画面と同じ扱い)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // 追加・削除が他の画面や Web 版であった場合に追いつくため、
        // 開くたびに1ページ目から読み直す。
        reloadMylist(page: 1)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func refresh() {
        reloadMylist(page: 1)
    }

    // MARK: - 読み込み

    /// マイリストの登録を取り直してから、指定ページの番組を取る。
    /// 同期が効いていないときは通信せず、案内だけを出す。
    /// refreshSettings が false のときは、設定の取り直しをせず手元の現在値で
    /// 組み立てる (この画面で削除した直後用。削除の保存がサーバーへ届く前に
    /// 取り直すと、消したはずの登録が戻って見えるため)。
    /// 読み込み中に来た読み直しの控え (捨てず、終わったあとで行う)。
    private var pendingReload: (page: Int, refreshSettings: Bool)?

    private func reloadMylist(page: Int, refreshSettings: Bool = true) {
        guard !isLoading else {
            // 操作後の反映のための読み直しが、別の読み込み中というだけで
            // 捨てられて画面が古いまま残らないよう、控えておく。
            pendingReload = (page, refreshSettings)
            refreshControl.endRefreshing()
            return
        }
        guard SyncedSettingsStore.isSyncEnabled else {
            mylistIDs = []
            programs = []
            total = 0
            currentPage = 1
            statusLabel.text = Self.guidanceText
            tableView.reloadData()
            refreshControl.endRefreshing()
            updatePagination()
            updateSortRow()
            return
        }
        failedLogoIDs.removeAll()
        isLoading = true
        updatePagination()
        Task { [weak self] in
            guard let self else { return }
            // サーバー側の最新を取り込んでから、登録の並びを組み立てる
            // (取り込みに失敗しても、手元の値で表示は続ける)。
            if refreshSettings {
                _ = await SyncedSettingsStore.shared.refreshFromServer()
            }
            let entries = SyncedSettingsStore.shared.current.mylist
                .filter { $0.isRecordedProgram }
            self.mylistIDs = Self.sortedIDs(entries: entries, sortOrder: self.sortOrder)
            if self.mylistIDs.isEmpty {
                self.programs = []
                self.total = 0
                self.currentPage = 1
                self.statusLabel.text = Self.emptyText
                self.tableView.reloadData()
                self.isLoading = false
                self.refreshControl.endRefreshing()
                self.updatePagination()
                self.updateSortRow()
                return
            }
            await self.loadPage(page)
        }
    }

    /// 登録の並びを、いまの並び替えに合わせて番組 ID の並びにする。
    /// 録画順のときは、Web 版と同じく追加の新しい順で渡し、
    /// 並べ替え自体はサーバー側に任せる。
    private static func sortedIDs(entries: [MylistEntry], sortOrder: SortOrder) -> [Int] {
        switch sortOrder {
        case .addedDesc, .recordedDesc, .recordedAsc:
            return entries.sorted { $0.createdAt > $1.createdAt }.map { $0.id }
        case .addedAsc:
            return entries.sorted { $0.createdAt < $1.createdAt }.map { $0.id }
        }
    }

    /// 並べた ID のまま、指定ページの番組を取る。
    private func loadPage(_ page: Int) async {
        do {
            var response = try await APIClient.shared.fetchVideos(
                page: page, order: sortOrder.apiOrder, ids: mylistIDs)
            // 指定ページが総ページ数を超えていたら、最後のページを取り直す
            // (登録を消してページが無くなっている場合。録画一覧と同じ)。
            let lastPage = max(1, Int(ceil(Double(response.total) / Double(Self.pageSize))))
            if page > lastPage {
                response = try await APIClient.shared.fetchVideos(
                    page: lastPage, order: sortOrder.apiOrder, ids: mylistIDs)
                currentPage = lastPage
            } else {
                currentPage = page
            }
            total = response.total
            programs = response.recorded_programs
            // 登録はあるのに録画自体が残っていない場合は、空の表示にする。
            statusLabel.text = programs.isEmpty ? Self.emptyText : nil
            tableView.reloadData()
            tableView.setContentOffset(.zero, animated: false)
        } catch {
            if programs.isEmpty {
                statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
            }
        }
        isLoading = false
        refreshControl.endRefreshing()
        updatePagination()
        updateSortRow()
        if let pending = pendingReload {
            pendingReload = nil
            reloadMylist(page: pending.page, refreshSettings: pending.refreshSettings)
        }
    }

    /// ページ送りから指定されたページへ移る。登録の並びは取り直さず、
    /// 取得済みの並びでページだけ取り直す。
    private func goToPage(_ page: Int) {
        guard page != currentPage, !isLoading, !mylistIDs.isEmpty else { return }
        isLoading = true
        updatePagination()
        Task { [weak self] in
            guard let self else { return }
            await self.loadPage(page)
        }
    }

    /// 総ページ数 (最低1)。
    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(Self.pageSize))))
    }

    /// 上下両方のページ送りに、いまのページ状態を反映する。
    private func updatePagination() {
        for pagination in [topPaginationView, bottomPaginationView] {
            pagination.update(currentPage: currentPage, totalPages: totalPages, isEnabled: !isLoading)
            // 録画一覧と同じく、番組が1件も無いときはページ送りを出さない。
            pagination.isHidden = total == 0
        }
        // 上のページ送りは、隠すときは高さも畳む。
        topPaginationHeightConstraint?.constant = total == 0 ? 0 : PaginationView.preferredHeight
    }

    /// マイリストが空のときの文 (Web 版のマイリストの空表示に、
    /// アプリの入り口の形を合わせたもの)。
    private static let emptyText =
        "あとで観たい番組をマイリストに保存できます。\n"
        + "録画番組の長押しメニューや再生画面のボタンから、番組をマイリストに追加できます。"

    /// 同期が効いていないときの案内。状態 (未ログイン／同期オフ) で出し分ける。
    private static var guidanceText: String {
        if !SettingsStore.shared.isLoggedIn {
            return "マイリストを使うには、ログインが必要です。\n"
                + "アカウントの設定でログインして、「設定をデバイス間で同期する」をオンにしてください。"
        }
        return "マイリストを使うには、「設定をデバイス間で同期する」をオンにしてください。\n"
            + "アカウントの設定で切り替えられます。"
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        programs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        let program = programs[indexPath.row]
        cell.configure(with: program)
        loadThumbnail(for: program, into: cell)
        if let channelID = program.channel?.id {
            if let cached = logoCache.object(forKey: channelID as NSString) {
                cell.setLogo(cached)
            } else {
                loadLogo(channelID: channelID, at: indexPath)
            }
        }
        return cell
    }

    /// 局ロゴを取ってきて、表示中の行がまだ同じ番組ならその場で反映する
    /// (録画一覧と同じ方式)。
    private func loadLogo(channelID: String, at indexPath: IndexPath) {
        guard !failedLogoIDs.contains(channelID),
              !logoLoadingIDs.contains(channelID) else { return }
        logoLoadingIDs.insert(channelID)
        Task { [weak self] in
            guard let self else { return }
            defer { self.logoLoadingIDs.remove(channelID) }
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channelID),
                  let image = UIImage(data: data) else {
                self.failedLogoIDs.insert(channelID)
                return
            }
            self.logoCache.setObject(image, forKey: channelID as NSString)
            if let cell = self.tableView.cellForRow(at: indexPath) as? VideoCell,
               self.programs.indices.contains(indexPath.row),
               self.programs[indexPath.row].channel?.id == channelID {
                cell.setLogo(image)
            }
        }
    }

    /// サムネイルをセルへ出す。端末に控えがあれば、その場でこのセルへ
    /// 即座に出す。セルが作り直されても、控えのある番組は仮の絵のままに
    /// ならない。控えが無いときだけサーバーへ取りに行く。
    private func loadThumbnail(for program: RecordedProgram, into cell: VideoCell) {
        if let cached = thumbnailCache.object(forKey: NSNumber(value: program.id)) {
            cell.setThumbnail(cached)
            return
        }
        fetchThumbnail(videoID: program.id, isRetry: false)
    }

    /// サムネイルをサーバーから取る。同じ番組への取得は重ねない。
    /// 取れたら控えに入れ、いまその番組を表示しているセルへ出す
    /// (行の位置は取得が終わった時点で探し直すので、途中で一覧が
    /// 作り直されたり並びが変わったりしても取りこぼさない)。
    /// 失敗したら、少し置いて1回だけ取り直す。
    private func fetchThumbnail(videoID: Int, isRetry: Bool) {
        guard !thumbnailLoadingIDs.contains(videoID) else { return }
        thumbnailLoadingIDs.insert(videoID)
        Task { [weak self] in
            guard let self else { return }
            var image: UIImage?
            if let data = try? await APIClient.shared.fetchThumbnail(videoID: videoID) {
                image = UIImage(data: data)
            }
            self.thumbnailLoadingIDs.remove(videoID)
            if let image {
                self.thumbnailCache.setObject(image, forKey: NSNumber(value: videoID))
                self.applyThumbnail(image, videoID: videoID)
            } else if !isRetry {
                self.scheduleThumbnailRetry(videoID: videoID)
            }
        }
    }

    /// 失敗したサムネイルの取り直しを、少し置いて1回だけ行う。
    /// その番組がもう画面に出ていないときは取り直さない。
    private func scheduleThumbnailRetry(videoID: Int) {
        guard !thumbnailRetryingIDs.contains(videoID),
              thumbnailRow(videoID: videoID) != nil else { return }
        thumbnailRetryingIDs.insert(videoID)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.thumbnailRetryingIDs.remove(videoID)
            guard self.thumbnailCache.object(forKey: NSNumber(value: videoID)) == nil,
                  self.thumbnailRow(videoID: videoID) != nil else { return }
            self.fetchThumbnail(videoID: videoID, isRetry: true)
        }
    }

    /// 取れたサムネイルを、いまその番組を表示しているセルへ出す。
    /// セルが使い回されて別の番組に変わっていたら出さない。
    private func applyThumbnail(_ image: UIImage, videoID: Int) {
        guard let row = thumbnailRow(videoID: videoID),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? VideoCell,
              cell.thumbnailProgramID == videoID else { return }
        cell.setThumbnail(image)
    }

    /// いま表示しているデータの中で、その番組の行を探す。
    private func thumbnailRow(videoID: Int) -> Int? {
        programs.firstIndex { $0.id == videoID }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard programs.indices.contains(indexPath.row) else { return }
        let program = programs[indexPath.row]
        let player = PlayerViewController(program: program)
        navigationController?.pushViewController(player, animated: true)
    }

    /// 長押しメニュー。録画一覧と同じ「視聴済みにする」「保護する／外す」
    /// (保護の項目は拡張版だけ) に、この画面固有の「マイリストから削除」を足す。
    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard programs.indices.contains(indexPath.row) else { return nil }
        let program = programs[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = []
            if !program.isRecording, (program.watched_ratio ?? 0) < 1 {
                actions.append(UIAction(
                    title: "視聴済みにする",
                    image: UIImage(systemName: "checkmark.circle")
                ) { _ in
                    self?.markWatched(program: program)
                })
            }
            if AppEdition.protectionEnabled {
                let protected = program.isProtected
                actions.append(UIAction(
                    title: protected ? "保護を外す" : "保護する",
                    image: UIImage(systemName: protected ? "lock.open" : "lock")
                ) { _ in
                    self?.toggleProtection(program: program)
                })
            }
            actions.append(UIAction(
                title: "マイリストから削除",
                image: UIImage(systemName: "bookmark.slash"),
                attributes: .destructive
            ) { _ in
                self?.removeFromMylist(program: program)
            })
            return UIMenu(children: actions)
        }
    }

    // MARK: - 番組への操作

    private func markWatched(program: RecordedProgram) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.markWatched(videoID: program.id, duration: program.duration)
                self.reloadMylist(page: self.currentPage)
            } catch {
                self.showAlert(title: "視聴済みにできませんでした", message: nil)
            }
        }
    }

    private func toggleProtection(program: RecordedProgram) {
        guard SettingsStore.shared.isLoggedIn else {
            let alert = UIAlertController(
                title: "ログインが必要です",
                message: "保護の切り替えには、設定タブで KonomiTV へのログインが必要です。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { [weak self] _ in
                self?.mainTabBarController?.selectedIndex = 3
            })
            present(alert, animated: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await APIClient.shared.toggleProtection(videoID: program.id)
                self.reloadMylist(page: self.currentPage)
            } catch let error as APIError {
                self.showAlert(title: error.protectionFailureMessage, message: nil)
            } catch {
                self.showAlert(title: "保護を切り替えられませんでした", message: nil)
            }
        }
    }

    /// マイリストから1件を外す。切り替えは SyncedSettings 側の手順
    /// (送る直前に最新を取得して、触る項目だけ差し替えて送る) に乗る。
    /// 成功したら、いまのページを取り直す (ページ自体が無くなっていたら
    /// 最後のページに落ちる)。
    private func removeFromMylist(program: RecordedProgram) {
        Task { [weak self] in
            guard let self else { return }
            // 他の画面や Web 版での変更に追いついてから切り替える
            // (古い控えで切り替えると、別の登録を巻き戻しかねないため)。
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            SyncedSettingsStore.shared.toggleMylist(videoID: program.id)
            self.reloadMylist(page: self.currentPage, refreshSettings: false)
        }
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
