import UIKit

/// 本家の動画ホーム。録画全体ではなく、三つの先頭セクションだけを保持する。
final class VideoHomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Section {
        let title: String
        let emptyMessage: String
        var programs: [RecordedProgram] = []
        var loaded = false
        var error: String?
    }

    private var sections = [
        Section(title: "新着の録画番組", emptyMessage: "録画番組がありません。"),
        Section(title: "マイリスト", emptyMessage: "あとで観たい番組を\nマイリストに保存できます。"),
        Section(title: "視聴履歴", emptyMessage: "まだ視聴履歴がありません。\n録画番組を30秒以上みると追加されます。"),
    ]
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let headerView = SPHeaderView()
    private let refreshControl = UIRefreshControl()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var visible = false
    private var active = true
    private var updating = false
    private var pendingUpdate = false
    private var pendingForceHistory = false
    private var generation = 0
    private var updateTask: Task<Void, Never>?
    private var scope: WatchedHistoryStore.Context?
    private var displayedHistoryIDs: [Int] = []
    private let thumbnailCache = NSCache<NSNumber, UIImage>()
    private let logoCache = NSCache<NSString, UIImage>()
    private var imageTasks: [String: Task<Void, Never>] = [:]
    private var failedImages: Set<String> = []
    private var imageGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ビデオをみる"
        view.backgroundColor = AppPalette.background
        tableView.backgroundColor = AppPalette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.estimatedRowHeight = 115
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseID)
        tableView.register(HomeStatusCell.self, forCellReuseIdentifier: "status")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        headerView.onLogoTap = { [weak self] in self?.mainTabBarController?.selectedIndex = 0 }
        tableView.tableHeaderView = headerView
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        thumbnailCache.countLimit = 60
        thumbnailCache.totalCostLimit = 24 * 1024 * 1024
        logoCache.countLimit = 64
        logoCache.totalCostLimit = 4 * 1024 * 1024

        observe(.historyContextDidChange) { [weak self] in
            self?.clearChangedContext()
            self?.requestUpdate()
        }
        observe(.watchedHistoryDidChange) { [weak self] in
            guard let self, !self.updating,
                  self.displayedHistoryIDs != WatchedHistoryStore.shared.currentSnapshot.videoIDs else { return }
            self.requestUpdate()
        }
        observe(.mylistDidChange) { [weak self] in
            guard let self, !self.updating else { return }
            self.requestUpdate()
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] in
            self?.active = true
            self?.startTimer()
            self?.requestUpdate()
        }
        observe(UIApplication.willResignActiveNotification) { [weak self] in
            self?.active = false
            self?.suspend()
        }
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visible = true
        navigationController?.setNavigationBarHidden(true, animated: animated)
        clearChangedContext()
        WatchedHistoryStore.shared.observe(self)
        startTimer()
        requestUpdate(forceHistory: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        suspend()
        WatchedHistoryStore.shared.stopObserving(self)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = CGSize(width: tableView.bounds.width, height: SPHeaderView.height)
        if headerView.frame.size != size {
            headerView.frame = CGRect(origin: .zero, size: size)
            tableView.tableHeaderView = headerView
        }
    }

    deinit {
        timer?.invalidate()
        updateTask?.cancel()
        for task in imageTasks.values { task.cancel() }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func startTimer() {
        guard visible, active, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.requestUpdate() }
    }

    private func suspend() {
        timer?.invalidate()
        timer = nil
        generation += 1
        updateTask?.cancel()
        updateTask = nil
        updating = false
        pendingUpdate = false
        pendingForceHistory = false
        refreshControl.endRefreshing()
        cancelImageLoads()
    }

    private func clearChangedContext() {
        let current = WatchedHistoryStore.Context.current
        guard scope != current else { return }
        suspend()
        scope = current
        displayedHistoryIDs = []
        for index in sections.indices {
            sections[index].programs = []
            sections[index].loaded = false
            sections[index].error = nil
        }
        thumbnailCache.removeAllObjects()
        logoCache.removeAllObjects()
        tableView.reloadData()
        startTimer()
    }

    @objc private func refresh() { requestUpdate(forceHistory: true) }

    private var mylistIDs: [Int] {
        guard WatchedHistoryStore.Context.current.enabled else { return [] }
        var seen: Set<Int> = []
        return SyncedSettingsStore.shared.current.mylist.filter(\.isRecordedProgram).sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }.compactMap { seen.insert($0.id).inserted ? $0.id : nil }
    }

    private func personalizedPrograms(ids: [Int]) async -> Result<[RecordedProgram], Error> {
        // 空の ids を送ると通常の録画一覧になるため、必ず通信前に止める。
        guard !ids.isEmpty else { return .success([]) }
        do {
            let response = try await APIClient.shared.fetchVideos(page: 1, ids: ids)
            return .success(Array(response.recorded_programs.prefix(4)))
        } catch { return .failure(error) }
    }

    private func requestUpdate(forceHistory: Bool = false) {
        guard visible, active else { return }
        clearChangedContext()
        if updating {
            pendingUpdate = true
            pendingForceHistory = pendingForceHistory || forceHistory
            return
        }
        updating = true
        pendingUpdate = false
        let token = generation
        let expected = WatchedHistoryStore.Context.current
        updateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token {
                    self.updating = false
                    self.updateTask = nil
                    self.refreshControl.endRefreshing()
                    if self.pendingUpdate {
                        let force = self.pendingForceHistory
                        self.pendingForceHistory = false
                        self.requestUpdate(forceHistory: force)
                    }
                }
            }
            // 各応答は最大30番組。全録画のページ走査や全画像の先読みは行わない。
            async let recent = APIClient.shared.fetchVideos(page: 1, order: "desc")
            async let synced = SyncedSettingsStore.shared.refreshFromServer()
            async let history = WatchedHistoryStore.shared.refresh(force: forceHistory)
            let recentResult: Result<[RecordedProgram], Error>
            do { recentResult = .success(Array(try await recent.recorded_programs.prefix(10))) }
            catch { recentResult = .failure(error) }
            _ = await synced
            let historyOK = await history
            guard !Task.isCancelled, token == self.generation,
                  expected == WatchedHistoryStore.Context.current else { return }
            let listIDs = self.mylistIDs
            let historyIDs = WatchedHistoryStore.shared.currentSnapshot.videoIDs
            async let listResult = self.personalizedPrograms(ids: listIDs)
            async let watchedResult = self.personalizedPrograms(ids: historyIDs)
            let list = await listResult
            let watched = await watchedResult
            guard !Task.isCancelled, token == self.generation,
                  expected == WatchedHistoryStore.Context.current else { return }
            // 通信中に保存が完了した場合は、古い並びを一瞬表示せず一度だけ取り直す。
            guard listIDs == self.mylistIDs,
                  historyIDs == WatchedHistoryStore.shared.currentSnapshot.videoIDs else {
                self.pendingUpdate = true
                return
            }
            self.displayedHistoryIDs = historyIDs
            self.apply(recentResult, section: 0)
            self.apply(list, section: 1)
            self.apply(watched, section: 2)
            if SyncedSettingsStore.shared.lastRefreshFailed {
                self.sections[1].error = "マイリストの設定を更新できませんでした。タップして再試行"
            }
            if !historyOK { self.sections[2].error = "視聴履歴を更新できませんでした。タップして再試行" }
            self.failedImages.removeAll()
            self.reloadPreservingPosition()
        }
    }

    private func apply(_ result: Result<[RecordedProgram], Error>, section: Int) {
        switch result {
        case .success(let programs):
            sections[section].programs = programs
            sections[section].loaded = true
            sections[section].error = nil
        case .failure:
            sections[section].error = "読み込めませんでした。タップして再試行"
        }
    }

    private func reloadPreservingPosition() {
        let oldOffset = tableView.contentOffset.y
        let first = tableView.indexPathsForVisibleRows?.first
        let anchor = first.flatMap { path in
            (tableView.cellForRow(at: path) as? VideoCell)?.thumbnailProgramID.map { ($0, path.section) }
        }
        let delta = first.map { oldOffset - tableView.rectForRow(at: $0).minY } ?? 0
        tableView.reloadData()
        tableView.layoutIfNeeded()
        var offset = oldOffset
        if let (id, section) = anchor,
           let row = sections[section].programs.firstIndex(where: { $0.id == id }) {
            offset = tableView.rectForRow(at: IndexPath(row: row, section: section)).minY + delta
        }
        let minimum = -tableView.adjustedContentInset.top
        let maximum = max(minimum, tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
        tableView.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, offset))), animated: false)
    }

    private func program(at path: IndexPath) -> RecordedProgram? {
        guard sections.indices.contains(path.section), sections[path.section].programs.indices.contains(path.row) else { return nil }
        return sections[path.section].programs[path.row]
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].programs.count + (sections[section].programs.isEmpty || sections[section].error != nil ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let program = program(at: indexPath) else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "status", for: indexPath) as! HomeStatusCell
            let section = sections[indexPath.section]
            let enabled = indexPath.section == 0 || WatchedHistoryStore.Context.current.enabled
            let message = section.error ?? (!enabled ? "アカウントでログインし、\n設定の同期をオンにしてください。" :
                section.loaded ? section.emptyMessage : "読み込んでいます…")
            cell.configure(message: message, loading: enabled && !section.loaded && section.error == nil)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        cell.configure(with: program)
        cell.configureHomeGrouping(first: indexPath.row == 0, last: indexPath.row == sections[indexPath.section].programs.count - 1)
        if let image = thumbnailCache.object(forKey: NSNumber(value: program.id)) { cell.setThumbnail(image) }
        else { loadImage(videoID: program.id) }
        if let channel = program.channel?.id {
            if let logo = logoCache.object(forKey: channel as NSString) { cell.setLogo(logo) }
            else { loadImage(channelID: channel) }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        program(at: indexPath) == nil ? UIScale.value(sections[indexPath.section].programs.isEmpty ? 200 : 64) : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let program = program(at: indexPath) {
            navigationController?.pushViewController(PlayerViewController(program: program), animated: true)
        } else { requestUpdate(forceHistory: true) }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard let program = program(at: indexPath), WatchedHistoryStore.Context.current.enabled else { return nil }
        let expected = WatchedHistoryStore.Context.current
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let saved = SyncedSettingsStore.shared.isInMylist(videoID: program.id)
            var actions = [UIAction(title: saved ? "マイリストから削除" : "マイリストに追加",
                                    image: UIImage(systemName: saved ? "minus.circle" : "plus.circle")) { _ in
                guard expected == WatchedHistoryStore.Context.current else { return }
                SyncedSettingsStore.shared.toggleMylist(videoID: program.id)
            }]
            if indexPath.section == 2 {
                actions.append(UIAction(title: "視聴履歴から削除", image: UIImage(systemName: "trash"),
                                        attributes: .destructive) { _ in
                    guard expected == WatchedHistoryStore.Context.current else { return }
                    Task {
                        if !(await WatchedHistorySync.removeEntry(videoID: program.id)) {
                            guard let self, self.visible,
                                  expected == WatchedHistoryStore.Context.current else { return }
                            self.sections[2].error = "視聴履歴を削除できませんでした。"
                            self.reloadPreservingPosition()
                        }
                    }
                })
            }
            return UIMenu(children: actions)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        let title = UILabel()
        title.text = sections[section].title
        title.textColor = AppPalette.text
        title.font = .scaledSystemFont(ofSize: 22, weight: .bold)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let more = RippleButton()
        more.setTitle("もっと見る ›", for: .normal)
        more.setTitleColor(AppPalette.accent, for: .normal)
        more.titleLabel?.font = .scaledSystemFont(ofSize: 15)
        more.setContentCompressionResistancePriority(.required, for: .horizontal)
        more.addAction(UIAction { [weak self] _ in self?.openMore(section) }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        if section == 0 {
            let search = RippleButton()
            search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            search.tintColor = AppPalette.secondaryText
            search.accessibilityLabel = "録画番組を検索"
            search.widthAnchor.constraint(equalToConstant: UIScale.value(36)).isActive = true
            search.addAction(UIAction { [weak self] _ in self?.openSearch() }, for: .touchUpInside)
            stack.addArrangedSubview(search)
        }
        stack.addArrangedSubview(more)
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: UIScale.value(16)),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -UIScale.value(16)),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: UIScale.value(8)),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -UIScale.value(8)),
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { UIScale.value(60) }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { UIScale.value(16) }

    private func openMore(_ section: Int) {
        let controller: UIViewController
        switch section {
        case 0: controller = VideoListViewController()
        case 1: controller = MylistViewController()
        default: controller = WatchedHistoryViewController()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openSearch() {
        let controller = VideoListViewController(opensSearch: true)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func cancelImageLoads() {
        imageGeneration += 1
        for task in imageTasks.values { task.cancel() }
        imageTasks.removeAll()
        failedImages.removeAll()
    }

    private func loadImage(videoID: Int? = nil, channelID: String? = nil) {
        let key = videoID.map { "thumbnail:\($0)" } ?? "logo:\(channelID ?? "")"
        guard imageTasks[key] == nil, !failedImages.contains(key) else { return }
        let token = imageGeneration
        imageTasks[key] = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let videoID { data = try await APIClient.shared.fetchThumbnail(videoID: videoID) }
                else if let channelID { data = try await APIClient.shared.fetchChannelLogo(channelID: channelID) }
                else { return }
                guard !Task.isCancelled, token == self.imageGeneration,
                      self.scope == WatchedHistoryStore.Context.current else { return }
                guard let image = UIImage(data: data) else { throw APIError.invalidResponse }
                if let videoID { self.thumbnailCache.setObject(image, forKey: NSNumber(value: videoID), cost: data.count) }
                if let channelID { self.logoCache.setObject(image, forKey: channelID as NSString, cost: data.count) }
                self.imageTasks.removeValue(forKey: key)
                // 同じ番組が複数セクションにあっても、一つの取得で可視セルを更新する。
                for path in self.tableView.indexPathsForVisibleRows ?? [] {
                    guard let program = self.program(at: path),
                          let cell = self.tableView.cellForRow(at: path) as? VideoCell,
                          cell.thumbnailProgramID == program.id else { continue }
                    if program.id == videoID { cell.setThumbnail(image) }
                    if let channelID, program.channel?.id == channelID { cell.setLogo(image) }
                }
            } catch {
                guard token == self.imageGeneration else { return }
                self.imageTasks.removeValue(forKey: key)
                self.failedImages.insert(key)
            }
        }
    }
}

private final class HomeStatusCell: UITableViewCell {
    private let box = UIView()
    private let message = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        box.backgroundColor = AppPalette.panel
        box.layer.cornerRadius = 8
        message.font = .scaledSystemFont(ofSize: 15)
        message.textColor = AppPalette.secondaryText
        message.textAlignment = .center
        message.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [spinner, message])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        for view in [box, stack] { view.translatesAutoresizingMaskIntoConstraints = false }
        contentView.addSubview(box)
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            box.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            box.topAnchor.constraint(equalTo: contentView.topAnchor),
            box.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(message: String, loading: Bool) {
        self.message.text = message
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        spinner.isHidden = !loading
    }
}
