import UIKit

/// 録画予約タブの中身。Web 版の録画予約一覧 (/reservations/) を写したもの:
/// 見出し「録画予約一覧 ○件」、並び替え (放送が近い順が既定)、
/// 優先度と有効/無効の切り替えが付いたカードの一覧。
/// 土台が EDCB でないサーバーでは、一覧の代わりに利用できない案内を出す
/// (Web 版の「取得エラー + 予約なしの見た目」は真似しない)。
final class ReservationListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = SPHeaderView()
    private let listHeaderView = UIView()
    private let countLabel = UILabel()
    private let sortButton = RippleButton()
    /// 「自動予約の条件」への入口のボタン (拡張版だけ、見出し行の下の行)。
    private let conditionsButton = RippleButton()
    private let statusLabel = UILabel()
    private let refreshControl = UIRefreshControl()

    /// 表示中の予約 (並び替え済み)。
    private var reservations: [Reservation] = []
    /// 並び順。true = 放送が近い順 (Web 版の既定)、false = 放送が遠い順。
    private var sortAscending = true
    /// 土台が EDCB でないことが分かったら true (案内表示)。
    private var isBackendUnavailable = false
    private var isLoading = false

    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs = Set<String>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        headerView.onLogoTap = { [weak self] in
            self?.mainTabBarController?.selectedIndex = 0
        }

        // 見出し行: 「録画予約一覧」+「○件」、右端に並び替えボタン。
        let titleLabel = UILabel()
        titleLabel.text = "録画予約一覧"
        titleLabel.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = AppPalette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(titleLabel)

        countLabel.font = .scaledSystemFont(ofSize: 13)
        countLabel.textColor = AppPalette.metaText
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(countLabel)

        sortButton.setTitle("放送が近い順", for: .normal)
        sortButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        sortButton.setTitleColor(AppPalette.text, for: .normal)
        sortButton.setImage(
            UIImage(systemName: "chevron.down")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
            for: .normal)
        sortButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        sortButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        sortButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        sortButton.layer.cornerRadius = 14
        sortButton.layer.borderWidth = 1
        sortButton.layer.borderColor = AppPalette.outlineBorder.cgColor
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.menu = makeSortMenu()
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(sortButton)

        // 「自動予約の条件」への入口。Web 版の録画予約一覧では
        // 見出しの上にこの入口の行がある。アプリでは見出し行の下に置く。
        // 拡張オプションのトグルからは外し、予約機能と同じ条件
        // (後ろ側が EDCB のとき) に寄せた。この画面自体が、土台が
        // EDCB でないときは利用できない案内を出す作りなので、入口は
        // 常時出す。
        let headerHeight: CGFloat = 86
        conditionsButton.setTitle("自動予約の条件", for: .normal)
        conditionsButton.titleLabel?.font = .scaledSystemFont(ofSize: 14)
        conditionsButton.setTitleColor(AppPalette.text, for: .normal)
        conditionsButton.setImage(
            UIImage(systemName: "calendar.badge.plus")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)),
            for: .normal)
        conditionsButton.tintColor = AppPalette.text
        conditionsButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 2)
        conditionsButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: -2)
        conditionsButton.contentHorizontalAlignment = .leading
        conditionsButton.addTarget(
            self, action: #selector(conditionsTapped), for: .touchUpInside)
        conditionsButton.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(conditionsButton)
        NSLayoutConstraint.activate([
            conditionsButton.leadingAnchor.constraint(
                equalTo: listHeaderView.leadingAnchor, constant: 16),
            conditionsButton.topAnchor.constraint(
                equalTo: listHeaderView.topAnchor, constant: 46),
            conditionsButton.heightAnchor.constraint(equalToConstant: 40),
            conditionsButton.trailingAnchor.constraint(
                lessThanOrEqualTo: listHeaderView.trailingAnchor, constant: -16),
        ])
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: listHeaderView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: listHeaderView.topAnchor, constant: 13),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 7),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: listHeaderView.trailingAnchor, constant: -12),
            sortButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            sortButton.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
        ])
        listHeaderView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight)

        // ロゴ帯と見出し行は一覧と一緒に流れる (Web 版のスマホ表示と同じ)。
        let tableHeader = UIView(
            frame: CGRect(x: 0, y: 0, width: view.bounds.width,
                          height: SPHeaderView.height + listHeaderView.frame.height))
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: SPHeaderView.height)
        listHeaderView.frame = CGRect(
            x: 0, y: SPHeaderView.height, width: view.bounds.width, height: listHeaderView.frame.height)
        tableHeader.addSubview(headerView)
        tableHeader.addSubview(listHeaderView)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 132
        tableView.register(ReservationCell.self, forCellReuseIdentifier: ReservationCell.reuseID)
        tableView.tableHeaderView = tableHeader
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        refreshControl.tintColor = AppPalette.metaText
        tableView.refreshControl = refreshControl

        // 中央の状態表示 (読み込み中・案内・空・失敗)。
        statusLabel.font = .scaledSystemFont(ofSize: 14)
        statusLabel.textColor = AppPalette.metaText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // 下端はセーフエリアの下端に留める (録画一覧と同じ。
            // 最下端まで伸ばすと最後の行が下部バーの裏に入る)。
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        load()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - 読み込み

    @objc private func refreshPulled() {
        load()
    }

    private func load() {
        guard !isLoading else {
            refreshControl.endRefreshing()
            return
        }
        guard SettingsStore.shared.isConfigured else {
            refreshControl.endRefreshing()
            showStatus("設定タブで接続先 URL を設定してください。")
            return
        }
        isLoading = true
        if reservations.isEmpty && !isBackendUnavailable {
            showStatus("読み込み中…")
        }
        Task { [weak self] in
            guard let self else { return }
            // まず土台を確認する。EDCB でない値が返ってきたら案内を出す。
            let backend = await APIClient.shared.fetchServerBackend()
            if let backend, backend != "EDCB" {
                self.isBackendUnavailable = true
                self.reservations = []
                self.finishLoad()
                self.showStatus("録画予約機能は EDCB バックエンド選択時のみ利用できます。")
                return
            }
            do {
                let response = try await APIClient.shared.fetchReservations()
                self.isBackendUnavailable = false
                self.reservations = response.reservations
                self.applySort()
                self.finishLoad()
                if self.reservations.isEmpty {
                    self.showStatus("まだ録画予約がありません。\n番組表から録画予約を追加できます。")
                } else {
                    self.hideStatus()
                }
            } catch let APIError.badStatus(code) where code == 422 {
                // 一覧の口が 422 を返した場合も、土台が EDCB でない案内にする。
                self.isBackendUnavailable = true
                self.reservations = []
                self.finishLoad()
                self.showStatus("録画予約機能は EDCB バックエンド選択時のみ利用できます。")
            } catch {
                self.finishLoad()
                if self.reservations.isEmpty {
                    self.showStatus("録画予約一覧を取得できませんでした。\n下に引いて再読み込みしてください。")
                }
            }
        }
    }

    private func finishLoad() {
        isLoading = false
        refreshControl.endRefreshing()
        countLabel.text = isBackendUnavailable ? "" : "\(reservations.count)件"
        tableView.reloadData()
    }

    private func applySort() {
        reservations.sort { lhs, rhs in
            let l = lhs.program.startDate ?? .distantFuture
            let r = rhs.program.startDate ?? .distantFuture
            return sortAscending ? l < r : l > r
        }
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.isHidden = false
    }

    private func hideStatus() {
        statusLabel.isHidden = true
    }

    // MARK: - 自動予約の条件

    /// 「自動予約の条件」の画面を開く (拡張版だけに出る入口)。
    @objc private func conditionsTapped() {
        let conditions = ReservationConditionsViewController()
        navigationController?.pushViewController(conditions, animated: true)
    }

    // MARK: - 並び替え

    private func makeSortMenu() -> UIMenu {
        let ascending = UIAction(
            title: "放送が近い順",
            state: sortAscending ? .on : .off
        ) { [weak self] _ in self?.setSort(ascending: true) }
        let descending = UIAction(
            title: "放送が遠い順",
            state: sortAscending ? .off : .on
        ) { [weak self] _ in self?.setSort(ascending: false) }
        return UIMenu(title: "並び替え", children: [ascending, descending])
    }

    private func setSort(ascending: Bool) {
        guard sortAscending != ascending else { return }
        sortAscending = ascending
        sortButton.setTitle(ascending ? "放送が近い順" : "放送が遠い順", for: .normal)
        sortButton.menu = makeSortMenu()
        applySort()
        tableView.reloadData()
    }

    // MARK: - 有効/無効の切り替え

    /// カード上の切り替え。設定一式の is_enabled だけを反転させて送る
    /// (Web 版のカードと同じ)。失敗したら切り替えを元に戻して知らせる。
    private func toggleReservation(_ reservation: Reservation, toggle: WebToggle) {
        // 手動予約の無効化は録画側に対応する状態が無いため、送らずに
        // 案内する (Web 版の保存時の守りと同じ)。切り替え自体は手動予約
        // のカードでは出していないため、通常はここへは来ない。
        if reservation.isManualReservation {
            toggle.isOn = reservation.record_settings.is_enabled
            let alert = UIAlertController(
                title: "手動予約は無効化できません",
                message: "予約を取りやめる場合は「予約を削除」を使ってください。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        var settings = reservation.record_settings
        settings.is_enabled = toggle.isOn
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await APIClient.shared.updateReservation(
                    id: reservation.id, recordSettings: settings)
                if let index = self.reservations.firstIndex(where: { $0.id == updated.id }) {
                    self.reservations[index] = updated
                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                }
            } catch {
                toggle.isOn = reservation.record_settings.is_enabled
                let message: String
                if let apiError = error as? APIError, case .message(let text) = apiError {
                    message = text
                } else {
                    message = "録画予約の更新に失敗しました。"
                }
                let alert = UIAlertController(
                    title: "録画予約を更新できませんでした", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: - テーブル

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        reservations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReservationCell.reuseID, for: indexPath) as! ReservationCell
        let reservation = reservations[indexPath.row]
        cell.configure(reservation: reservation)
        cell.onToggle = { [weak self] reservation, toggle in
            self?.toggleReservation(reservation, toggle: toggle)
        }
        loadLogo(for: reservation, into: cell)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let reservation = reservations[indexPath.row]
        let detail = ReservationDetailViewController(reservation: reservation)
        detail.onChanged = { [weak self] in self?.load() }
        // 放送中の番組の詳細で「視聴」が押されたら、同じナビゲーションへ
        // 再生画面を積む (戻ると詳細に戻る)。
        detail.onWatchRequested = { [weak self] channel in
            guard let self else { return }
            let player = LivePlayerViewController(channel: channel)
            self.navigationController?.pushViewController(player, animated: true)
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    /// 局ロゴを取る (録画一覧と同じキャッシュの作り)。
    private func loadLogo(for reservation: Reservation, into cell: ReservationCell) {
        let channelID = reservation.channel.display_channel_id
        if let cached = logoCache.object(forKey: channelID as NSString) {
            cell.setLogo(cached)
            return
        }
        if failedLogoIDs.contains(channelID) { return }
        Task { [weak self, weak cell] in
            guard let self else { return }
            do {
                let data = try await APIClient.shared.fetchChannelLogo(channelID: channelID)
                guard let image = UIImage(data: data) else { return }
                self.logoCache.setObject(image, forKey: channelID as NSString)
                cell?.setLogo(image)
            } catch {
                self.failedLogoIDs.insert(channelID)
            }
        }
    }
}

/// 予約カード1件。Web 版の予約カード (スマホ縦) の並び:
/// 左の列に優先度の印と有効/無効の切り替え、右に題名 → 状態の印 →
/// 局ロゴと局名 → 時刻 → 説明 → コメントと録画予定サイズ。
/// 無効な予約は切り替え以外を薄く表示する (Web 版と同じ)。
final class ReservationCell: UITableViewCell {
    static let reuseID = "ReservationCell"

    var onToggle: ((Reservation, WebToggle) -> Void)?

    private let cardView = UIView()
    private let priorityBox = UIView()
    private let priorityLabel = UILabel()
    private let toggle = WebToggle()
    private let toggleStateLabel = UILabel()
    private let recordingStack = UIStackView()
    private let recordingDot = UIView()
    private let recordingLabel = UILabel()
    private let textStack = UIStackView()
    private let titleLabel = UILabel()
    private let statusChip = BadgeLabel()
    private let logoView = UIImageView()
    private let channelLabel = UILabel()
    private let timeLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let commentLabel = UILabel()
    private let sizeLabel = UILabel()
    private var currentReservation: Reservation?
    /// 押したときの波紋 (共通部品)。本家 Web 版のカードと同じく、
    /// カード全体を対象に、触れた位置から広げる。
    private let ripple = RippleSurface()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = AppPalette.panel
        cardView.layer.cornerRadius = 11
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        // 左の列: 優先度の箱と、その下の切り替え。
        priorityBox.layer.cornerRadius = 4
        priorityBox.layer.borderWidth = 1
        priorityBox.layer.borderColor = AppPalette.outlineBorder.cgColor
        priorityBox.translatesAutoresizingMaskIntoConstraints = false
        priorityLabel.font = .scaledSystemFont(ofSize: 15, weight: .bold)
        priorityLabel.textColor = AppPalette.text
        priorityLabel.textAlignment = .center
        priorityLabel.translatesAutoresizingMaskIntoConstraints = false
        priorityBox.addSubview(priorityLabel)
        let priorityCaption = UILabel()
        priorityCaption.text = "優先度"
        priorityCaption.font = .scaledSystemFont(ofSize: 9.5)
        priorityCaption.textColor = AppPalette.metaText
        priorityCaption.textAlignment = .center
        priorityCaption.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        // 予約カードの中のトグルは、本家では密度が詰まった扱いで、
        // 押している間の輪も小さい (28px)。
        toggle.haloDiameter = 28
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggleStateLabel.font = .scaledSystemFont(ofSize: 10)
        toggleStateLabel.textColor = AppPalette.metaText
        toggleStateLabel.textAlignment = .center
        toggleStateLabel.translatesAutoresizingMaskIntoConstraints = false

        recordingDot.backgroundColor = AppPalette.recordingDot
        recordingDot.layer.cornerRadius = 5
        recordingDot.translatesAutoresizingMaskIntoConstraints = false
        recordingLabel.text = "録画中"
        recordingLabel.font = .scaledSystemFont(ofSize: 10)
        recordingLabel.textColor = AppPalette.metaText
        recordingLabel.textAlignment = .center
        recordingLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingStack.addArrangedSubview(recordingDot)
        recordingStack.addArrangedSubview(recordingLabel)
        recordingStack.axis = .vertical
        recordingStack.alignment = .center
        recordingStack.spacing = 4
        recordingStack.isHidden = true
        recordingStack.translatesAutoresizingMaskIntoConstraints = false
        recordingDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        recordingDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let leftColumn = UIStackView(arrangedSubviews: [
            priorityBox, priorityCaption, toggle, toggleStateLabel, recordingStack,
        ])
        leftColumn.axis = .vertical
        leftColumn.alignment = .center
        leftColumn.spacing = 4
        leftColumn.setCustomSpacing(2, after: priorityBox)
        leftColumn.setCustomSpacing(10, after: priorityCaption)
        leftColumn.setCustomSpacing(2, after: toggle)
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        // 録画中は切り替えの代わりに録画中の印を出すため、両方を同じ列に
        // 入れて出し分ける (録画中は toggle 側を隠す)。
        cardView.addSubview(leftColumn)

        // 右の本文。
        titleLabel.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppPalette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        statusChip.font = .scaledSystemFont(ofSize: 10.5, weight: .semibold)
        statusChip.textColor = .white
        statusChip.layer.cornerRadius = 4
        statusChip.clipsToBounds = true
        statusChip.textInsets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
        statusChip.translatesAutoresizingMaskIntoConstraints = false
        let chipRow = UIStackView(arrangedSubviews: [statusChip, UIView()])
        chipRow.axis = .horizontal
        chipRow.translatesAutoresizingMaskIntoConstraints = false

        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.backgroundColor = AppPalette.placeholder
        logoView.layer.cornerRadius = 2
        logoView.isHidden = true
        logoView.translatesAutoresizingMaskIntoConstraints = false
        channelLabel.font = .scaledSystemFont(ofSize: 11.5)
        channelLabel.textColor = AppPalette.metaText
        channelLabel.numberOfLines = 1
        channelLabel.lineBreakMode = .byTruncatingTail
        let metaRow = UIStackView(arrangedSubviews: [logoView, channelLabel])
        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .scaledSystemFont(ofSize: 11)
        timeLabel.textColor = AppPalette.metaText
        timeLabel.numberOfLines = 1
        timeLabel.lineBreakMode = .byTruncatingTail

        descriptionLabel.font = .scaledSystemFont(ofSize: 10)
        descriptionLabel.textColor = AppPalette.metaText
        descriptionLabel.numberOfLines = 2
        descriptionLabel.lineBreakMode = .byTruncatingTail

        commentLabel.font = .scaledSystemFont(ofSize: 10.5)
        commentLabel.textColor = AppPalette.metaText
        commentLabel.numberOfLines = 1
        commentLabel.lineBreakMode = .byTruncatingTail
        sizeLabel.font = .scaledSystemFont(ofSize: 10.5)
        sizeLabel.textColor = AppPalette.metaText
        sizeLabel.textAlignment = .right
        let bottomRow = UIStackView(arrangedSubviews: [commentLabel, sizeLabel])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        commentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(chipRow)
        textStack.addArrangedSubview(metaRow)
        textStack.addArrangedSubview(timeLabel)
        textStack.addArrangedSubview(descriptionLabel)
        textStack.addArrangedSubview(bottomRow)
        textStack.axis = .vertical
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setCustomSpacing(5, after: titleLabel)
        textStack.setCustomSpacing(5, after: chipRow)
        textStack.setCustomSpacing(1, after: metaRow)
        textStack.setCustomSpacing(4, after: timeLabel)
        textStack.setCustomSpacing(5, after: descriptionLabel)
        cardView.addSubview(textStack)

        // 波紋の入れ物はカードの一番上に重ねる (操作は受けないため、
        // 左の列の切り替えは今までどおり直接触れる)。
        cardView.addSubview(ripple.container)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            priorityBox.widthAnchor.constraint(equalToConstant: 38),
            priorityBox.heightAnchor.constraint(equalToConstant: 30),
            priorityLabel.centerXAnchor.constraint(equalTo: priorityBox.centerXAnchor),
            priorityLabel.centerYAnchor.constraint(equalTo: priorityBox.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 24),
            logoView.heightAnchor.constraint(equalToConstant: 14),
            leftColumn.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 9),
            leftColumn.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            leftColumn.widthAnchor.constraint(equalToConstant: 46),
            textStack.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -9),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: cardView.bounds, cornerRadius: cardView.layer.cornerRadius)
    }

    // カードへのタッチで波紋を出す。押したときの反応は波紋だけで、
    // 地の変化は付けない (他のカードとそろえる)。タッチは中身の
    // 部品 (文字や絵) では受けず、カード面を通してセルまで届く。
    // 左の列の切り替えへのタッチは切り替え側が受け取るため、
    // こちらには届かない。スクロールが始まると「取り消し」が
    // 届くので、そこで波紋を取り消す。
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
        logoView.isHidden = true
        onToggle = nil
        currentReservation = nil
    }

    func configure(reservation: Reservation) {
        currentReservation = reservation
        let isRecording = reservation.is_recording_in_progress
        let isEnabled = reservation.record_settings.is_enabled

        priorityLabel.text = "\(reservation.record_settings.priority)"
        toggle.isOn = isEnabled
        // 手動予約には録画側に「無効」の状態が無いため、切り替え自体を
        // 出さず「有効」の固定表示にする (Web 版の予約カードと同じ)。
        // 切り替えを出してしまうと、押したときにサーバー側で失敗する。
        let isManual = reservation.isManualReservation
        toggleStateLabel.text = isManual ? "有効" : (isEnabled ? "有効" : "無効")
        // 録画中は切り替えを出さない (Web 版と同じ)。
        toggle.isHidden = isRecording || isManual
        toggleStateLabel.isHidden = isRecording
        recordingStack.isHidden = !isRecording

        // 題名の [字] [再] などは、Web 版の予約カードと同じくピンク地の印に
        // 描き分ける (再生画面の情報欄と同じ部品を使う)。
        titleLabel.attributedText = decoratedProgramTitle(
            reservation.program.title, font: titleLabel.font, textColor: AppPalette.text)
        statusChip.text = ReservationStatusDisplay.text(
            isRecording: isRecording, availability: reservation.recording_availability)
        statusChip.backgroundColor = ReservationStatusDisplay.color(
            isRecording: isRecording, availability: reservation.recording_availability)
        let channelNumber = reservation.channel.channel_number.map { "Ch: \($0) " } ?? ""
        channelLabel.text = channelNumber + reservation.channel.name
        timeLabel.text = TimeFormat.recordingTimeText(
            start: reservation.program.startDate,
            end: reservation.program.endDate,
            durationSeconds: reservation.program.duration)
        descriptionLabel.text = reservation.program.description
        descriptionLabel.isHidden = (reservation.program.description ?? "").isEmpty
        commentLabel.text = reservation.comment.isEmpty ? "" : "コメント: \(reservation.comment)"
        sizeLabel.text = ReservationStatusDisplay.sizeText(
            bytes: reservation.estimated_recording_file_size)

        // 無効な予約は本文を薄くする (切り替えだけははっきり見せる)。
        let dimmed: CGFloat = isEnabled ? 1 : 0.45
        textStack.alpha = dimmed
        priorityBox.alpha = dimmed
    }

    func setLogo(_ image: UIImage) {
        logoView.image = image
        logoView.isHidden = false
    }

    @objc private func toggleChanged() {
        guard let currentReservation else { return }
        onToggle?(currentReservation, toggle)
    }
}
