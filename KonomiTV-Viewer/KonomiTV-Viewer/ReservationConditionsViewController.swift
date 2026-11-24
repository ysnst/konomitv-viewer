import UIKit

/// 自動予約の条件 (キーワード自動予約の条件) の一覧と削除の画面。
/// 録画予約タブの「自動予約の条件」の入口から開く (拡張版だけに出る入口)。
///
/// Web 版の ReservationConditionsDialog と同じ役割:
/// - 条件は「キーワード + チャンネル」の並びで出し、各行に
///   「チャンネル名 ・ これまでの予約追加 N 件」と、無効の印を出す。
/// - 削除は確認を挟んでから行う。条件を削除しても、その条件で
///   すでに作られた録画予約はそのまま残る。
/// - 条件の作成はこの画面では行わない (再生画面の情報欄と予約詳細の
///   「シリーズ予約」から作る。Web 版と同じ)。
///
/// Web 版はダイアログだが、アプリでは予約タブから開く画面として作り、
/// 見出し帯は設定まわりの画面と同じ形 (SettingsDetailViewController の土台)。
final class ReservationConditionsViewController: SettingsDetailViewController {
    private let noteLabel = UILabel()
    private let stateLabel = UILabel()
    private let rowsStack = UIStackView()

    /// 表示中の条件。
    private var conditions: [ReservationCondition] = []
    /// チャンネル名の解決用 (全チャンネルを平らに持つ)。
    private var channels: [LiveChannel] = []
    /// 取得が済んだか (取得前と、条件が無い場合の文面を出し分けるため)。
    private var didLoad = false
    /// 取得に失敗したときの文 (APIError.message の文をそのまま出す)。
    private var loadFailureText: String?
    /// 削除の実行中フラグ。
    private var isDeleting = false

    init() {
        super.init(headingTitle: "自動予約の条件")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        load()
    }

    private func buildItems() {
        // Web 版ダイアログの先頭の注記と同じ文。
        noteLabel.font = .scaledSystemFont(ofSize: 13)
        noteLabel.textColor = AppPalette.metaText
        noteLabel.numberOfLines = 0
        noteLabel.text = "条件に一致する番組は、番組表が更新されるたびに自動で録画予約されます。条件を削除しても、すでに作成された録画予約はそのまま残ります。"
        stateLabel.font = .scaledSystemFont(ofSize: 13.5)
        stateLabel.textColor = AppPalette.metaText
        stateLabel.numberOfLines = 0
        rowsStack.axis = .vertical
        rowsStack.spacing = 0
        contentStack.addArrangedSubview(noteLabel)
        contentStack.addArrangedSubview(stateLabel)
        contentStack.addArrangedSubview(rowsStack)
        updateStateViews()
    }

    /// 条件の一覧と、チャンネル名の解決用のチャンネル一覧を取り直す。
    private func load() {
        Task { [weak self] in
            guard let self else { return }
            async let channelsResponse = APIClient.shared.fetchChannels()
            do {
                let response = try await APIClient.shared.fetchReservationConditions()
                self.conditions = response.reservation_conditions
                self.loadFailureText = nil
            } catch {
                self.conditions = []
                if let apiError = error as? APIError, case .message(let text) = apiError {
                    self.loadFailureText = text
                } else {
                    self.loadFailureText = "キーワード自動予約条件一覧を取得できませんでした。"
                }
            }
            if let response = try? await channelsResponse {
                self.channels = response.groups.flatMap { $0.channels }
            }
            self.didLoad = true
            self.rebuildRows()
        }
    }

    /// 状態に合わせて、状態の文面の出し分けをする。
    private func updateStateViews() {
        let hasConditions = !conditions.isEmpty
        rowsStack.isHidden = !hasConditions
        if hasConditions {
            stateLabel.isHidden = true
        } else if !didLoad {
            stateLabel.isHidden = false
            stateLabel.text = "読み込み中です…"
        } else if let loadFailureText {
            stateLabel.isHidden = false
            stateLabel.text = loadFailureText
        } else {
            // Web 版の、条件が無いときの文面。
            stateLabel.isHidden = false
            stateLabel.text = "自動予約の条件はまだありません"
        }
    }

    /// 行を組み直す。削除のたびに呼び、区切り線の有無を現在の並びに合わせる。
    private func rebuildRows() {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, condition) in conditions.enumerated() {
            rowsStack.addArrangedSubview(
                makeRow(for: condition, isLast: index == conditions.count - 1))
        }
        updateStateViews()
    }

    /// 条件1行分。並びは Web 版のダイアログどおり:
    /// キーワード (太字) の下に「チャンネル名 ・ これまでの予約追加 N 件」、
    /// 無効のときは「無効」の印、右端に削除ボタン。
    /// 行の下端に区切り線を引く (最後の行だけ引かない)。
    private func makeRow(for condition: ReservationCondition, isLast: Bool) -> UIView {
        let search = condition.program_search_condition

        let keywordLabel = UILabel()
        keywordLabel.text = search.keyword.isEmpty ? "（キーワード指定なし）" : search.keyword
        keywordLabel.font = .scaledSystemFont(ofSize: 16.5, weight: .bold)
        keywordLabel.textColor = AppPalette.text
        keywordLabel.numberOfLines = 1
        keywordLabel.lineBreakMode = .byTruncatingTail

        let metaLabel = UILabel()
        metaLabel.text = "\(channelLabel(for: search)) ・ これまでの予約追加 \(condition.reservation_count) 件"
        metaLabel.font = .scaledSystemFont(ofSize: 13)
        metaLabel.textColor = AppPalette.metaText
        metaLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [keywordLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var rowSubviews: [UIView] = [textStack]
        if !search.is_enabled {
            let disabledLabel = UILabel()
            disabledLabel.text = "無効"
            disabledLabel.font = .scaledSystemFont(ofSize: 13)
            disabledLabel.textColor = AppPalette.error
            disabledLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            rowSubviews.append(disabledLabel)
        }
        let deleteButton = RippleButton()
        deleteButton.setTitle("削除", for: .normal)
        deleteButton.titleLabel?.font = .scaledSystemFont(ofSize: 14)
        deleteButton.setTitleColor(AppPalette.error, for: .normal)
        deleteButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        deleteButton.addAction(
            UIAction { [weak self] _ in self?.askDelete(condition) }, for: .touchUpInside)
        rowSubviews.append(deleteButton)

        let row = UIStackView(arrangedSubviews: rowSubviews)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        if !isLast {
            let divider = UIView()
            divider.backgroundColor = AppPalette.pressed
            divider.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                divider.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        return container
    }

    /// 条件のチャンネル指定を名前に直す (Web 版の metaLine と同じ照合:
    /// ネットワーク ID・伝送路 ID・サービス ID の3つで探し、
    /// 見つからなければ「SID 番号」、指定が無ければ「全チャンネル」)。
    private func channelLabel(for search: ProgramSearchCondition) -> String {
        guard let ranges = search.service_ranges, !ranges.isEmpty else {
            return "全チャンネル"
        }
        return ranges.map { range in
            let channel = channels.first {
                $0.network_id == range.network_id
                    && $0.transport_stream_id == range.transport_stream_id
                    && $0.service_id == range.service_id
            }
            return channel?.name ?? "SID \(range.service_id)"
        }.joined(separator: "、")
    }

    // MARK: - 削除

    /// 削除の確認を出す (Web 版の確認ダイアログと同じ文面)。
    private func askDelete(_ condition: ReservationCondition) {
        let keyword = condition.program_search_condition.keyword
        let alert = UIAlertController(
            title: "この自動予約を削除しますか？",
            message: "「\(keyword)」の自動予約をやめます。\nすでに作成された録画予約はそのまま残ります。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "削除する", style: .destructive) { [weak self] _ in
            self?.performDelete(condition)
        })
        present(alert, animated: true)
    }

    private func performDelete(_ condition: ReservationCondition) {
        guard !isDeleting else { return }
        isDeleting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.deleteReservationCondition(id: condition.id)
                self.isDeleting = false
                self.conditions.removeAll { $0.id == condition.id }
                self.rebuildRows()
                // Web 版は画面下の知らせで伝えるが、この画面にはその
                // 仕組みが無いため、状態の文の場所に一時的に出す。
                self.stateLabel.isHidden = false
                self.stateLabel.text = "自動予約の条件を削除しました。"
                // 知らせは出しっぱなしにせず、少し経ったら消す
                // (一覧が空のときの案内表示へ戻す)。
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.stateLabel.text == "自動予約の条件を削除しました。" else { return }
                    self.updateStateViews()
                }
            } catch {
                self.isDeleting = false
                let message: String
                if let apiError = error as? APIError, case .message(let text) = apiError {
                    message = text
                } else {
                    message = "キーワード自動予約条件の削除に失敗しました。"
                }
                let alert = UIAlertController(
                    title: "自動予約の条件を削除できませんでした",
                    message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}
