import Foundation

/// シリーズ予約 (キーワード自動予約) の条件の組み立てと追加の手順。
/// Web 版の services/ReservationConditions.ts の写しで、キーワードの
/// 作り方・重複の判定・失敗の扱いをそろえてある。
///
/// シリーズ予約は改造サーバーではなく EDCB バックエンド側の仕組み
/// (キーワード自動予約) を使うが、入口は拡張版だけに出す
/// (「次回を予約」と対で、再生画面の情報欄と予約詳細に置くため)。
enum ReservationConditions {

    /// シリーズ予約の追加結果。
    enum AddResult {
        /// 新しく作成した。
        case created(keyword: String)
        /// 同じキーワード + 同じチャンネルの条件が既にあった。
        case duplicate
        /// 失敗した (文は APIError.message に入っている)。
        case failed(Error)
    }

    /// 番組名から検索キーワードを作る (Web 版 buildSeriesSearchCondition と
    /// 「次回を予約」のキーワードの作り方と同じ)。
    /// [字] [解] などのマークと、話数表記 (#5 / 第N話 / 第N回) を取り除く。
    /// 来週分の題名には話数表記が含まれないことが多く、そのままだと
    /// 検索に一致しないため。正規化して空になった場合は元の題名を使う。
    static func seriesKeyword(title: String, seriesTitle: String?) -> String {
        let source = (seriesTitle?.isEmpty == false ? seriesTitle! : title)
        var keyword = source
        keyword = replacingRegex(#"\[[^\]]*\]"#, in: keyword, with: "")
        keyword = replacingRegex(#"#\s*\d+"#, in: keyword, with: "")
        keyword = replacingRegex(#"第\s*\d+\s*[話回]"#, in: keyword, with: "")
        keyword = replacingRegex(#"\s+"#, in: keyword, with: " ")
        keyword = keyword.trimmingCharacters(in: .whitespaces)
        return keyword.isEmpty ? title : keyword
    }

    private static func replacingRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    /// 番組情報からシリーズ予約用の検索条件を組み立てる。
    /// キーワードは番組名から作り、チャンネルは番組のものに固定する
    /// (チャンネルの識別子が取れない場合はチャンネル指定なし)。
    static func buildSeriesSearchCondition(
        title: String, seriesTitle: String?,
        networkID: Int?, serviceID: Int?, transportStreamID: Int?
    ) -> ProgramSearchCondition {
        let serviceRanges: [ProgramSearchServiceRange]?
        if let networkID, let serviceID, let transportStreamID {
            serviceRanges = [ProgramSearchServiceRange(
                network_id: networkID,
                transport_stream_id: transportStreamID,
                service_id: serviceID)]
        } else {
            serviceRanges = nil
        }
        return ProgramSearchCondition(
            is_enabled: true,
            keyword: seriesKeyword(title: title, seriesTitle: seriesTitle),
            exclude_keyword: "",
            note: "",
            is_title_only: true,
            is_case_sensitive: false,
            is_fuzzy_search_enabled: false,
            is_regex_search_enabled: false,
            service_ranges: serviceRanges,
            genre_ranges: nil,
            is_exclude_genre_ranges: false,
            date_ranges: nil,
            is_exclude_date_ranges: false,
            duration_range_min: nil,
            duration_range_max: nil,
            broadcast_type: "All",
            duplicate_title_check_scope: "None",
            duplicate_title_check_period_days: 6)
    }

    /// シリーズ予約 (キーワード自動予約の条件) を追加する。
    /// まず既存の条件を取り、同じキーワード + 同じチャンネルの条件が
    /// 既にあれば追加しない (Web 版と同じ重複の判定: チャンネルは
    /// 先頭の指定同士をネットワーク ID とサービス ID で比べ、
    /// どちらも指定なしの場合も一致として扱う)。
    /// 既存の条件の取得に失敗した場合は、重複の確認を飛ばして追加を試みる
    /// (Web 版と同じ)。
    static func addSeriesReservation(
        title: String, seriesTitle: String?,
        networkID: Int?, serviceID: Int?, transportStreamID: Int?,
        recordSettings: RecordSettings
    ) async -> AddResult {
        let condition = buildSeriesSearchCondition(
            title: title, seriesTitle: seriesTitle,
            networkID: networkID, serviceID: serviceID,
            transportStreamID: transportStreamID)
        if let existing = try? await APIClient.shared.fetchReservationConditions() {
            let newRange = condition.service_ranges?.first
            let isDuplicate = existing.reservation_conditions.contains { existingCondition in
                let existingSearch = existingCondition.program_search_condition
                // 無効化された条件は自動予約されないため、重複とはしない
                // (無効な同名条件が残っていても新しく作れるようにする)。
                guard existingSearch.is_enabled else { return false }
                guard existingSearch.keyword == condition.keyword else { return false }
                let existingRange = existingSearch.service_ranges?.first
                switch (existingRange, newRange) {
                case (nil, nil):
                    return true
                case let (existingRange?, newRange?):
                    return existingRange.network_id == newRange.network_id
                        && existingRange.service_id == newRange.service_id
                default:
                    return false
                }
            }
            if isDuplicate {
                return .duplicate
            }
        }
        do {
            try await APIClient.shared.addReservationCondition(
                condition: condition, recordSettings: recordSettings)
            return .created(keyword: condition.keyword)
        } catch {
            return .failed(error)
        }
    }
}
