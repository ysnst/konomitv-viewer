import UIKit

/// 視聴履歴の画面。マイページの「視聴履歴」の入口から開く。
///
/// 本家 Web 版の視聴履歴 (views/WatchedHistory.vue) と同じ作り:
/// - 実体は利用者設定の watched_history (Web 版と共通で、世帯で共有される)。
///   最後に見た順 (updated_at の新しい順) に並べ、番組情報は ID 指定
///   (order=ids) でサーバーから取る。並び替えの選択は出さない。
/// - 並びは録画一覧と同じカード (VideoCell) で、30件ごとのページ分け、
///   ページ送りは一覧の上と下の両方に置く (録画一覧と同じ)。
/// - カードを押すと再生画面へ移る。続きの位置は再生画面側が履歴から取る
///   ため、この画面では位置を渡さない。
/// - 長押しメニューに「視聴履歴から削除」を置く (Web 版ではカード右端の
///   ゴミ箱ボタン。アプリのカードには端のボタンが無いため、録画一覧と
///   同じ長押しメニューに寄せた)。録画一覧と同じ「視聴済みにする」と
///   「保護する／外す」(拡張版だけ) も一緒に出す。
///
/// 履歴は、ログイン中かつ「設定をデバイス間で同期する」がオンのときだけ
/// 記録・共有される (再生画面の書き戻しと同じ条件)。その条件を満たさない
/// ときは一覧の代わりに案内を出す。端末だけに残す履歴は持たない
/// (Web 版と二重管理にしないため)。
///
/// 見出し帯は設定まわりの画面 (SettingsDetailViewController) と同じ形:
/// 高さ 60px・地は background-lighten-1、左端は矢印だけの戻るボタン、
/// ページ名 22px。端からの横スワイプでも戻れる。
final class WatchedHistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    /// 1ページの件数。サーバー側の固定値 (PAGE_SIZE = 30) に合わせる。
    private static let pageSize = 30

    private let backButton = RippleButton()
    /// 見出し帯。一覧まわりはこの帯の下端に留めて組むため保持する。
    private let headingBar = UIView()
    private let topPaginationView = PaginationView()
    /// 上のページ送りの高さ。番組が無いときは隠すだけでなく高さも畳む
    /// (帯状の空白が残らないように)。
    private var topPaginationHeightConstraint: NSLayoutConstraint?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let bottomPaginationView = PaginationView()
    private var bottomPaginationFooter: UIView?
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()

    /// 最後に見た順に並べた履歴の番組 ID。ページ取得の元になる。
    private var historyIDs: [Int] = []
    /// いま表示しているページの番組 (最大で pageSize 件)。
    private var programs: [RecordedProgram] = []
    /// 表示上の全件数 (サーバー応答の total。履歴のうち実在する録画の件数)。
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

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "視聴履歴"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildHeadingBar()

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
            topPaginationView.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
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
    }

    /// 見出し帯 (設定まわりの画面と同じ形)。
    private func buildHeadingBar() {
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "視聴履歴"
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
        // (設定まわりの画面と同じ扱い)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // 再生画面から戻ったときは、見た番組が先頭に来るよう取り直す。
        // 並びが最後に見た順なので、開くたびに1ページ目から読み直す。
        reloadHistory(page: 1)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func refresh() {
        reloadHistory(page: 1)
    }

    // MARK: - 読み込み

    /// 履歴の ID を取り直してから、指定ページの番組を取る。
    /// 同期が効いていないときは通信せず、案内だけを出す。
    /// 読み込み中に来た読み直しの控え (捨てず、終わったあとで行う)。
    private var pendingReloadPage: Int?

    /// 読み込みを始めた時点の認証・同期の世代。一覧の読み込み全体
    /// (履歴 ID の取得と、その後の録画情報の取得) を通して保持し、
    /// 各取得の後と、画面へ反映する前に照合する。間に同期の
    /// 切り替えやアカウントの変更、接続先の変更 (ログインの失効を
    /// 伴う) があったら、その読み込みの結果は今の状態のものでは
    /// ないため反映しない。
    private var loadAuthGeneration = 0
    private var loadSyncGeneration = 0

    private func reloadHistory(page: Int) {
        guard !isLoading else {
            pendingReloadPage = page
            refreshControl.endRefreshing()
            return
        }
        guard WatchedHistorySync.isEnabled else {
            historyIDs = []
            programs = []
            total = 0
            currentPage = 1
            statusLabel.text = Self.guidanceText
            tableView.reloadData()
            refreshControl.endRefreshing()
            updatePagination()
            return
        }
        failedLogoIDs.removeAll()
        isLoading = true
        loadAuthGeneration = SettingsStore.shared.authGeneration
        loadSyncGeneration = SettingsStore.shared.syncGeneration
        updatePagination()
        Task { [weak self] in
            guard let self else { return }
            guard let ids = await WatchedHistorySync.historyVideoIDs() else {
                // 取れなかった理由が「取得の間に状態が変わって無効に
                // なった」のか「通信の失敗」なのかを区別する。無効化の
                // ときは失敗の表示を出さず、今の状態で読み直す
                // (同期が切れていれば案内になり、別のログインなら
                // その履歴が読み込まれる)。
                if SettingsStore.shared.authGeneration != self.loadAuthGeneration
                    || SettingsStore.shared.syncGeneration != self.loadSyncGeneration
                    || !WatchedHistorySync.isEnabled {
                    self.isLoading = false
                    self.refreshControl.endRefreshing()
                    self.updatePagination()
                    let next = self.pendingReloadPage ?? page
                    self.pendingReloadPage = nil
                    self.reloadHistory(page: next)
                    return
                }
                self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
                self.isLoading = false
                self.refreshControl.endRefreshing()
                self.updatePagination()
                return
            }
            self.historyIDs = ids
            if ids.isEmpty {
                self.programs = []
                self.total = 0
                self.currentPage = 1
                self.statusLabel.text = Self.emptyText
                self.tableView.reloadData()
                self.isLoading = false
                self.refreshControl.endRefreshing()
                self.updatePagination()
                return
            }
            await self.loadPage(page)
        }
    }

    /// 読み込みが今の状態のまま有効か (ログイン・同期・接続先が
    /// 読み込み開始時点と同じで、履歴 ID の並びも差し替わっていないか)。
    private func isLoadValid(authGeneration: Int, syncGeneration: Int, ids: [Int]) -> Bool {
        WatchedHistorySync.isEnabled
            && SettingsStore.shared.authGeneration == authGeneration
            && SettingsStore.shared.syncGeneration == syncGeneration
            && historyIDs == ids
    }

    /// 読み込みの途中で状態が変わって、この読み込みが無効になった
    /// ときの後始末。結果は反映せず、今の状態で読み直す (同期が
    /// 切れていれば案内になり、別のログインならその履歴になる)。
    private func abandonLoad() {
        isLoading = false
        refreshControl.endRefreshing()
        updatePagination()
        let next = pendingReloadPage ?? 1
        pendingReloadPage = nil
        reloadHistory(page: next)
    }

    /// 履歴の ID の並びのまま、指定ページの番組を取る。
    private func loadPage(_ page: Int) async {
        // 取得の間に状態が変わっていたら、返ってきた番組は今の
        // 状態のものではないため、反映する前に照合する。
        let authAtStart = loadAuthGeneration
        let syncAtStart = loadSyncGeneration
        let idsAtStart = historyIDs
        do {
            var response = try await APIClient.shared.fetchVideos(page: page, ids: idsAtStart)
            guard isLoadValid(authGeneration: authAtStart, syncGeneration: syncAtStart,
                              ids: idsAtStart) else {
                abandonLoad()
                return
            }
            // 指定ページが総ページ数を超えていたら、最後のページを取り直す
            // (履歴から消してページが無くなっている場合。録画一覧と同じ)。
            let lastPage = max(1, Int(ceil(Double(response.total) / Double(Self.pageSize))))
            if page > lastPage {
                response = try await APIClient.shared.fetchVideos(page: lastPage, ids: idsAtStart)
                guard isLoadValid(authGeneration: authAtStart, syncGeneration: syncAtStart,
                                  ids: idsAtStart) else {
                    abandonLoad()
                    return
                }
                currentPage = lastPage
            } else {
                currentPage = page
            }
            total = response.total
            programs = response.recorded_programs
            // 履歴の ID はあるのに録画自体が残っていない場合は、空の表示にする。
            statusLabel.text = programs.isEmpty ? Self.emptyText : nil
            tableView.reloadData()
            tableView.setContentOffset(.zero, animated: false)
        } catch {
            guard isLoadValid(authGeneration: authAtStart, syncGeneration: syncAtStart,
                              ids: idsAtStart) else {
                abandonLoad()
                return
            }
            if programs.isEmpty {
                statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
            }
        }
        isLoading = false
        refreshControl.endRefreshing()
        updatePagination()
        if let pending = pendingReloadPage {
            pendingReloadPage = nil
            reloadHistory(page: pending)
        }
    }

    /// ページ送りから指定されたページへ移る。ID の並びは取り直さず、
    /// 取得済みの並びでページだけ取り直す。
    private func goToPage(_ page: Int) {
        guard page != currentPage, !isLoading, !historyIDs.isEmpty else { return }
        isLoading = true
        loadAuthGeneration = SettingsStore.shared.authGeneration
        loadSyncGeneration = SettingsStore.shared.syncGeneration
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

    /// 履歴が空のときの文 (Web 版の視聴履歴の空表示と同じ文面)。
    private static let emptyText =
        "まだ視聴履歴がありません。\n録画番組を30秒以上みると、視聴履歴に追加されます。"

    /// 同期が効いていないときの案内。状態 (未ログイン／同期オフ) で出し分ける。
    private static var guidanceText: String {
        if !SettingsStore.shared.isLoggedIn {
            return "視聴履歴を使うには、ログインが必要です。\n"
                + "アカウントの設定でログインして、「設定をデバイス間で同期する」をオンにしてください。\n"
                + "録画番組を30秒以上みると、視聴履歴に追加されます。"
        }
        return "視聴履歴を使うには、「設定をデバイス間で同期する」をオンにしてください。\n"
            + "アカウントの設定で切り替えられます。\n"
            + "録画番組を30秒以上みると、視聴履歴に追加されます。"
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
        guard !failedLogoIDs.contains(channelID) else { return }
        Task { [weak self] in
            guard let self else { return }
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
    /// (保護の項目は拡張版だけ) に、この画面固有の「視聴履歴から削除」を足す。
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
                title: "視聴履歴から削除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.removeFromHistory(program: program)
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
                self.reloadHistory(page: self.currentPage)
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
                self.reloadHistory(page: self.currentPage)
            } catch let error as APIError {
                self.showAlert(title: error.protectionFailureMessage, message: nil)
            } catch {
                self.showAlert(title: "保護を切り替えられませんでした", message: nil)
            }
        }
    }

    /// 視聴履歴から1件を外す。成功したら、いまのページを取り直す
    /// (ページ自体が無くなっていたら最後のページに落ちる)。
    private func removeFromHistory(program: RecordedProgram) {
        Task { [weak self] in
            guard let self else { return }
            if await WatchedHistorySync.removeEntry(videoID: program.id) {
                self.reloadHistory(page: self.currentPage)
            } else {
                self.showAlert(title: "視聴履歴から削除できませんでした", message: nil)
            }
        }
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
