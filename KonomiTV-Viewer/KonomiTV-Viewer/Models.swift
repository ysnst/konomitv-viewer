import Foundation

/// CM 区間 (サーバーの番組データに含まれる cm_sections の1要素)。
struct CMSection: Codable {
    let start_time: Double
    let end_time: Double
}

/// サムネイル情報 (サーバーの番組データに含まれる thumbnail_info)。
/// シーク中のプレビューで使うタイル画像の材料。
struct ThumbnailInfo: Codable {
    let version: Int?
    let tile: ThumbnailTileInfo?
}

/// タイル画像 (シークバー用サムネイルを並べた1枚絵) の寸法情報。
/// 絵そのものは GET /api/videos/{id}/thumbnail/tiled で取る。
/// interval_sec ごとに1枚、左上から横方向に column_count 枚ずつ並んでいる。
struct ThumbnailTileInfo: Codable {
    let format: String?
    let image_width: Int
    let image_height: Int
    let tile_width: Int
    let tile_height: Int
    let total_tiles: Int
    let column_count: Int
    let row_count: Int
    let interval_sec: Double
}

struct RecordedVideoInfo: Codable {
    let id: Int
    let status: String  // "Recording" / "Recorded" など
    let duration: Double
    let cm_sections: [CMSection]?
    /// 実際に録画された期間 (API が返す)。本番 Web 版カードの時刻表示はこちらを使う。
    let recording_start_time: String?
    let recording_end_time: String?
    /// サムネイル情報。解析が済んでいない録画や録画中は無い (null)。
    let thumbnail_info: ThumbnailInfo?

    var recordingStartDate: Date? { recording_start_time.flatMap(DateParser.parse) }
    var recordingEndDate: Date? { recording_end_time.flatMap(DateParser.parse) }
}

struct ChannelInfo: Codable {
    let id: String
    let display_channel_id: String
    let name: String
    let type: String?
    /// チャンネル番号 ("101" など)。Web 版カードの「Ch: 101 局名」表示に使う。
    let channel_number: String?
    /// 伝送路の識別子。シリーズ予約 (キーワード自動予約) の条件を
    /// 組み立てるときに、番組のチャンネル側の値として使う。
    /// 応答に無いことがあるため任意。
    let transport_stream_id: Int?
}

/// GET /api/videos の1件分。
struct RecordedProgram: Codable {
    let id: Int
    let recorded_video: RecordedVideoInfo
    let channel: ChannelInfo?
    let title: String
    /// 番組の説明文。Web 版カードの説明行に使う。
    let description: String?
    /// ジャンル (大分類・中分類)。再生画面の情報欄の印に使う (Web 版パネルと同じ材料)。
    let genres: [ProgramGenre]?
    /// 詳細情報 (見出し → 本文)。再生画面の情報欄の「お知らせ」「番組内容」
    /// などの節に使う (Web 版パネルと同じ材料)。
    let detail: [String: String]?
    /// 一部のみ録画された番組か。Web 版カードの状態表示に使う。
    let is_partially_recorded: Bool?
    let start_time: String
    let end_time: String
    let duration: Double
    /// 保護されているか。状態が取れないときは null。
    let is_protected: Bool?
    /// どこまで見たかの割合 (0.0〜1.0)。状態が無いときは null。
    let watched_ratio: Double?
    /// 録画開始マージン (秒)。番組の開始前に余分に録画されている長さ。
    /// 再開位置の下限 (マージン + 2秒) の計算に使う。取れないときは null。
    let recording_start_margin: Double?
    /// 番組の識別子 (ネットワーク・サービス・イベント)。
    /// 「次回を予約」の検索条件と「シリーズ予約」の条件の組み立てに使う。
    /// 取れないときは null。
    let network_id: Int?
    let service_id: Int?
    let event_id: Int?
    /// シリーズ名。次回検索とシリーズ予約のキーワードは、こちらが
    /// あればこちらを元にする (Web 版と同じ)。
    let series_title: String?
    /// 前の話の録画 ID (改造サーバーが単体取得の応答にだけ付ける)。
    /// 一覧の応答には無く、その場合は null。
    let previous_episode_id: Int?
    /// 次の話の録画 ID (改造サーバーが単体取得の応答にだけ付ける)。
    /// 一覧の応答には無く、その場合は null。
    let next_episode_id: Int?

    var recordingStartMargin: Double { recording_start_margin ?? 0 }

    var startDate: Date? { DateParser.parse(start_time) }
    var endDate: Date? { DateParser.parse(end_time) }
    var isRecording: Bool { recorded_video.status == "Recording" }
    var isPartiallyRecorded: Bool { is_partially_recorded == true }
    var cmSections: [CMSection] { recorded_video.cm_sections ?? [] }

    var isProtected: Bool { is_protected == true }

    /// 未視聴の判定 (Web 版の物差しに合わせる)。
    /// 録画が完了していて、見た割合が 0 のときだけ未視聴とする
    /// (少しでも再生が報告されていれば視聴済み扱い)。
    /// 割合が取れない (null) ときは状態不明として未視聴にはしない。
    var isUnwatched: Bool {
        guard recorded_video.status == "Recorded" else { return false }
        guard let ratio = watched_ratio else { return false }
        return ratio <= 0
    }

    /// チャプターの境目 (CM 区間の開始と終了) を時刻順に並べたもの。
    var chapterBoundaries: [Double] {
        var points = Set<Double>()
        for section in cmSections {
            points.insert(section.start_time)
            points.insert(section.end_time)
        }
        return points.sorted()
    }
}

struct RecordedProgramsResponse: Codable {
    let total: Int
    let recorded_programs: [RecordedProgram]
}

/// しおり1件 (改造サーバーの GET /api/videos/{id}/bookmarks の要素)。
/// サーバー側 (世帯共有の保存先) が採番した ID と、再生位置 (秒)、
/// 表示名 (空のこともある)、作られた時刻 (UNIX 秒) でできている。
struct VideoBookmark: Decodable {
    let id: String
    let position: Double
    let label: String
    let created_at: Double
}

/// GET /api/videos/storage-status の応答 (ローカル改造の口)。
/// 録画ファイルが置かれているストレージの容量情報。
struct StorageStatus: Codable {
    /// ストレージの全体容量 (バイト)。
    let total_bytes: Int64
    /// ストレージの使用量 (バイト)。
    let used_bytes: Int64
    /// ストレージの空き容量 (バイト)。
    let free_bytes: Int64
    /// 録画ファイル自体の合計サイズ (バイト)。
    let recordings_bytes: Int64
}

/// GET /api/recorder/trash の応答 (ローカル改造の口)。
/// ゴミ箱に入っている録画の一覧と、保持期間 (日)。
struct TrashListResponse: Codable {
    let retention_days: Int
    let items: [TrashItem]
}

/// ゴミ箱内の録画1件分 (ローカル改造の口)。
/// program は通常の録画番組と同じ形で返る。
struct TrashItem: Codable {
    let program: RecordedProgram
    /// ゴミ箱へ移動した日時 (ISO 8601、UTC)。
    let trashed_at: String
    /// 完全に削除される予定の日時 (ISO 8601、UTC)。
    let purge_at: String

    var purgeDate: Date? { DateParser.parse(purge_at) }

    /// 完全に削除されるまでの残り日数 (Web 版の Trash.vue と同じ計算:
    /// 残り時間を日単位で切り上げ、負にはしない)。
    var remainingDays: Int {
        guard let purgeDate else { return 0 }
        let millis = purgeDate.timeIntervalSinceNow * 1000
        return max(0, Int(ceil(millis / (24 * 60 * 60 * 1000))))
    }
}

/// GET /api/videos/recording-results の応答 (ローカル改造の口)。
/// 予約録画の結果 (録れた・一部のみ・失敗) の一覧。新しい順で返る。
struct RecordingResultsResponse: Codable {
    let results: [RecordingResult]
}

/// 録画結果1件分 (ローカル改造の口)。
struct RecordingResult: Codable {
    /// 予約の ID。
    let reserve_id: Int
    /// 録画できた録画の ID。失敗したときは null。
    let recorded_id: Int?
    /// 番組名。
    let name: String
    /// チャンネル名。
    let channel_name: String
    /// 放送開始時刻 (UNIX 秒)。
    let start_at: Double
    /// 放送終了時刻 (UNIX 秒)。
    let end_at: Double
    /// 結果 ("success" / "partial" / "failed")。
    let status: String
    /// 実際の録画の長さ (秒)。失敗したときは null。
    let duration: Double?
    /// 受信の乱れの件数。数えられていないときは null。
    let error_count: Int?
    let drop_count: Int?
    let scrambling_count: Int?

    var startDate: Date { Date(timeIntervalSince1970: start_at) }
    var endDate: Date { Date(timeIntervalSince1970: end_at) }
}

/// GET /api/videos/{id}/delete-preview の応答 (ローカル改造の口)。
/// 完全削除の確認画面を出す前に、管理元と削除対象を確認するためのもの。
/// EPGStation が管理元の構成では、ここで受け取る確認用の合言葉
/// (confirmation_token) を削除のリクエストに付けないとサーバーが受け付けない。
struct RecordingDeletePreview: Codable {
    /// 削除の事前確認の仕組み自体が有効か。
    let enabled: Bool
    /// 確認用の合言葉。確認画面の寿命だけ保持する。
    let confirmation_token: String
    /// 削除の計画。管理元が EPGStation でない場合などは null。
    let plan: Plan?

    struct Plan: Codable {
        let video_id: Int
        let epgstation_id: Int
        let title: String
        let expires_at: Double
    }
}

/// GET / PUT /api/videos/{id}/protection の応答。
struct ProtectionState: Codable {
    /// 保護の仕組み自体が有効か (取れないときは nil)。
    let enabled: Bool?
    /// EPGStation 側の録画 ID。EPGStation 管理外の録画では null。
    let epgstation_id: Int?
    let is_protected: Bool?
}

/// POST /api/users/token の応答。
struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
}

/// GET /api/users/me の応答のうち、マイページのアカウント表示に使う項目。
/// サーバーは連携アカウント情報なども返すが、アプリではこの3つだけ読む
/// (Web 版の IUser の id / name / is_admin に相当)。
struct UserInfo: Codable {
    let id: Int
    let name: String
    let is_admin: Bool
}

struct LiveProgram: Codable {
    let title: String
    /// 番組の説明文。Web 版の生放送カードの説明行に使う。
    let description: String?
    let start_time: String
    let end_time: String
    /// 番組の長さ (秒)。Web 版の番組情報 (IProgram) にある項目。
    let duration: Double?

    var startDate: Date? { DateParser.parse(start_time) }
    var endDate: Date? { DateParser.parse(end_time) }

    /// "19:00〜20:54" の形の時刻範囲。日付が取れなければ空文字。
    var timeRangeText: String {
        guard let start = startDate, let end = endDate else { return "" }
        return "\(TimeFormat.hourMinute(start))〜\(TimeFormat.hourMinute(end))"
    }
}

struct LiveChannel: Codable {
    let id: String
    let display_channel_id: String
    let name: String
    let type: String
    /// チャンネル番号 ("021" など)。Web 版カードの「Ch: 021 局名」表示に使う。
    let channel_number: String?
    /// ニコニコ実況の勢い (コメント/分)。対応する実況が無い局では null。
    let jikkyo_force: Int?
    /// そのチャンネルを見ている人数。
    let viewer_count: Int?
    let is_display: Bool?
    let is_watchable: Bool?
    /// チューナーに空きがあって (または受信中で共有できて) 視聴できるか
    /// (ローカル改造のサーバーが付ける項目)。空きが無く受信中でもない
    /// チャンネルでは false になる。項目自体が無い応答 (通常のサーバー)
    /// では視聴できるものとして扱う。
    let is_tuner_viewable: Bool?

    /// チューナーの空き具合から見て視聴できるか。項目が無い場合は true。
    var isTunerViewable: Bool { is_tuner_viewable ?? true }
    /// チャンネルの識別子。自動予約の条件の画面で、条件のチャンネルを
    /// 名前に直すときの照合に使う。応答に無いことがあるため任意。
    let network_id: Int?
    let service_id: Int?
    let transport_stream_id: Int?
    let program_present: LiveProgram?
    /// 次の番組。API が返さない場合は nil (その場合は表示しない)。
    let program_following: LiveProgram?
}

/// GET /api/channels の応答 (放送種別ごとの辞書)。
struct LiveChannelsResponse: Codable {
    let GR: [LiveChannel]
    let BS: [LiveChannel]
    let CS: [LiveChannel]
    let CATV: [LiveChannel]
    let SKY: [LiveChannel]
    let BS4K: [LiveChannel]

    var groups: [(type: String, channels: [LiveChannel])] {
        [("GR", GR), ("BS", BS), ("CS", CS), ("CATV", CATV), ("SKY", SKY), ("BS4K", BS4K)]
            .filter { !$0.channels.isEmpty }
    }
}

/// 番組のジャンル (大分類・中分類)。番組表の色分けと通販判定に使う。
struct ProgramGenre: Codable {
    let major: String
    let middle: String
}

/// 番組表の各番組に付く予約情報 (バックエンドが EDCB のときだけ付く)。
struct TimeTableProgramReservation: Codable {
    let id: Int
    /// "Reserved" (予約済み) / "Recording" (録画中) / "Disabled" (無効)。
    let status: String
    /// "Full" (全編可能) / "Partial" (一部のみ) / "Unavailable" (不可)。
    let recording_availability: String
}

/// 番組表の番組1件分。
struct TimeTableProgram: Codable {
    let id: String
    let channel_id: String
    let title: String
    let description: String?
    let start_time: String
    let end_time: String
    let duration: Double
    let genres: [ProgramGenre]?
    let reservation: TimeTableProgramReservation?
    // 番組詳細の表示に使う項目 (番組表・予約のどちらの応答にも入っている)。
    // 応答に無いことがあるため、すべて任意。
    let detail: [String: String]?
    let video_codec: String?
    let video_resolution: String?
    let primary_audio_type: String?
    let primary_audio_language: String?
    let primary_audio_sampling_rate: String?
    let secondary_audio_type: String?
    let secondary_audio_language: String?
    let secondary_audio_sampling_rate: String?
    let is_free: Bool?
    /// 番組の識別子 (ネットワーク・サービス・イベント)。
    /// 予約詳細から「シリーズ予約」の条件を組み立てるときに使う。
    /// 応答に無いことがあるため任意。
    let network_id: Int?
    let service_id: Int?
    let event_id: Int?

    var startDate: Date? { DateParser.parse(start_time) }
    var endDate: Date? { DateParser.parse(end_time) }

    /// ジャンル大分類 (先頭のジャンル)。色分けの元。
    var genreMajor: String? { genres?.first?.major }

    /// 通販番組か (Web 版の判定と同じく、中分類が「ショッピング・通販」)。
    var isShopping: Bool {
        genres?.contains { $0.middle == "ショッピング・通販" } ?? false
    }
}

/// 番組表のサブチャンネル分 (独立した列にならないサブチャンネル)。
struct TimeTableSubchannel: Codable {
    let channel: ChannelInfo
    let programs: [TimeTableProgram]
}

/// 番組表のチャンネル1列分。
struct TimeTableChannelEntry: Codable {
    let channel: ChannelInfo
    let programs: [TimeTableProgram]
    let subchannels: [TimeTableSubchannel]?
}

/// 番組データが存在する日時の範囲 (日付移動の上限・下限)。
struct TimeTableDateRange: Codable {
    let earliest: String
    let latest: String

    var earliestDate: Date? { DateParser.parse(earliest) }
    var latestDate: Date? { DateParser.parse(latest) }
}

/// 番組表の表示範囲でチューナーが使われる区間1つ分
/// (ローカル改造のサーバーが付ける項目)。
/// 同じ物理チャンネルの重なる予約は1台分として数えられている。
struct TimeTableTunerBusyInterval: Codable {
    let start_time: String
    let end_time: String
    /// 同時に使われるチューナーの台数。
    let tuner_count: Int

    var startDate: Date? { DateParser.parse(start_time) }
    var endDate: Date? { DateParser.parse(end_time) }
}

/// GET /api/programs/timetable の応答。
struct TimeTableResponse: Codable {
    let channels: [TimeTableChannelEntry]
    let date_range: TimeTableDateRange
    /// チューナーの使用区間 (ローカル改造のサーバーだけが付ける)。
    /// 予約の取得に失敗したときなどは空で返る。通常のサーバーの応答には
    /// 項目自体が無いため任意にしている。
    let tuner_busy_intervals: [TimeTableTunerBusyInterval]?
}

enum DateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

enum TimeFormat {
    /// 秒を "1:23:45" / "23:45" の形にする。
    static func hms(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(E) HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return apply28HourClock(formatter.string(from: date))
    }

    /// 28 時間表記の置き換え (Web 版の Utils.apply28HourClock と同じ)。
    /// 設定が入っているときだけ、文字列の中の時刻表記について
    /// 0〜3 時台を 24〜27 時台に置き換える。日付を含む表記では、
    /// 日付 (と曜日) も 1 日前に直す。設定が切れているときは素通し。
    static func apply28HourClock(_ text: String) -> String {
        guard SyncedSettingsStore.shared.current.use28HourClock else { return text }
        var result = text
        // 1) yyyy/MM/dd (曜) HH:mm[:ss]
        result = shiftDateTime(in: result,
            pattern: #"(\d{4})/(\d{1,2})/(\d{1,2})(\s*)\((.)\)(\s+)(\d{1,2}):(\d{2})(?::(\d{2}))?"#,
            hasWeekday: true)
        // 2) yyyy/MM/dd HH:mm[:ss]
        result = shiftDateTime(in: result,
            pattern: #"(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?"#,
            hasWeekday: false)
        // 3) M/d (曜) HH:mm[:ss] (年が無い形は月日だけを 1 日前に直す)
        result = shiftMonthDay(in: result)
        // 4) 単独の HH:mm[:ss]
        result = shiftStandaloneTime(in: result)
        return result
    }

    /// 日付つきの時刻表記を、日付を 1 日前に戻しつつ 0〜3 時台を
    /// 24〜27 時台に置き換える。数字の桁数は入力のまま保つ。
    private static func shiftDateTime(in text: String, pattern: String, hasWeekday: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            func group(_ index: Int) -> String? {
                guard index < match.numberOfRanges,
                      let range = Range(match.range(at: index), in: result) else { return nil }
                return String(result[range])
            }
            let hourIndex = hasWeekday ? 7 : 4
            guard let year = group(1).flatMap(Int.init),
                  let month = group(2).flatMap(Int.init),
                  let day = group(3).flatMap(Int.init),
                  let hour = group(hourIndex).flatMap(Int.init),
                  let minute = group(hourIndex + 1),
                  hour <= 3,
                  let whole = Range(match.range, in: result) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "ja_JP")
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date) else { continue }
            let pc = calendar.dateComponents([.year, .month, .day, .weekday], from: previous)
            let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
            let weekday = weekdays[(pc.weekday ?? 1) - 1]
            let monthText = padded(pc.month ?? month, width: group(2)?.count ?? 2)
            let dayText = padded(pc.day ?? day, width: group(3)?.count ?? 2)
            let seconds = group(hourIndex + 2).map { ":\($0)" } ?? ""
            var replacement = "\(pc.year ?? year)/\(monthText)/\(dayText)"
            if hasWeekday {
                replacement += "\(group(4) ?? " " )(\(weekday))\(group(6) ?? " ")"
            } else {
                replacement += " "
            }
            replacement += "\(hour + 24):\(minute)\(seconds)"
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    /// 年の無い "M/d (曜) HH:mm[:ss]" の月日を 1 日前に直す。
    /// 年が分からないため、曜日は入力のままでは合わなくなるので、
    /// その年の同じ月日として曜日を取り直す。
    private static func shiftMonthDay(in text: String) -> String {
        let pattern = #"(\d{1,2})/(\d{1,2})(\s*)\((.)\)(\s+)(\d{1,2}):(\d{2})(?::(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            func group(_ index: Int) -> String? {
                guard index < match.numberOfRanges,
                      let range = Range(match.range(at: index), in: result) else { return nil }
                return String(result[range])
            }
            guard let month = group(1).flatMap(Int.init),
                  let day = group(2).flatMap(Int.init),
                  let hour = group(6).flatMap(Int.init),
                  let minute = group(7),
                  hour <= 3,
                  let whole = Range(match.range, in: result) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "ja_JP")
            let year = calendar.component(.year, from: Date())
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date) else { continue }
            let pc = calendar.dateComponents([.month, .day, .weekday], from: previous)
            let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
            let weekday = weekdays[(pc.weekday ?? 1) - 1]
            let seconds = group(8).map { ":\($0)" } ?? ""
            let replacement = "\(pc.month ?? month)/\(pc.day ?? day)\(group(3) ?? "")(\(weekday))\(group(5) ?? " ")\(hour + 24):\(minute)\(seconds)"
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    /// 日付を含まない単独の "HH:mm[:ss]" の 0〜3 時台を 24〜27 時台にする。
    private static func shiftStandaloneTime(in text: String) -> String {
        let pattern = #"(^|[^0-9])(\d{1,2}):(\d{2})(?::(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            func group(_ index: Int) -> String? {
                guard index < match.numberOfRanges,
                      let range = Range(match.range(at: index), in: result) else { return nil }
                return String(result[range])
            }
            guard let prefix = group(1),
                  let hourText = group(2),
                  let hour = Int(hourText),
                  let minute = group(3),
                  hour <= 3,
                  let whole = Range(match.range, in: result) else { continue }
            let seconds = group(4).map { ":\($0)" } ?? ""
            let hourDisplay = hourText.count == 1 ? "\(hour + 24)" : String(format: "%02d", hour + 24)
            result.replaceSubrange(whole, with: "\(prefix)\(hourDisplay):\(minute)\(seconds)")
        }
        return result
    }

    private static func padded(_ value: Int, width: Int) -> String {
        width == 1 ? "\(value)" : String(format: "%02d", value)
    }

    /// 分単位の長さの表記。小数第2位で四捨五入し、末尾の 0 は落とす
    /// (Web 版の数値表示に合わせる。例: 32.09 / 90 / 90.5)。
    static func minutesText(durationSeconds: Double) -> String {
        let minutes = (durationSeconds / 60 * 100).rounded() / 100
        var text = String(format: "%.2f", minutes)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Web 版 (本番) カードの時刻表示。ProgramUtils.getRecordingTimeShort と同じ形で
    /// "2026/11/22 (日) 21:00 ～ 23:00 (120分)" を返す。
    /// 開始・終了は録画期間が取れていればそちら、無ければ番組の放送時刻を渡す。
    /// 設定が入っていれば 28 時間表記の置き換えも行う (Web 版と同じ)。
    static func recordingTimeText(start: Date?, end: Date?, durationSeconds: Double) -> String {
        guard let start, let end else { return "" }
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "yyyy/MM/dd (E) HH:mm"
        startFormatter.locale = Locale(identifier: "ja_JP")
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        endFormatter.locale = Locale(identifier: "ja_JP")
        return apply28HourClock("\(startFormatter.string(from: start)) ～ \(endFormatter.string(from: end)) (\(minutesText(durationSeconds: durationSeconds))分)")
    }

    /// Web 版パネルの「録画期間」の表記。ProgramUtils.getRecordingTime と同じ形で
    /// "2026/11/18 (水) 00:19:57 ～ 00:52:03 (32.09分)" を返す (秒まで出す)。
    /// 長さは録画そのものの長さ (recorded_video.duration) を渡すこと。
    /// 設定が入っていれば 28 時間表記の置き換えも行う (Web 版と同じ)。
    static func recordingPeriodText(start: Date?, end: Date?, durationSeconds: Double) -> String {
        guard let start, let end else { return "" }
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "yyyy/MM/dd (E) HH:mm:ss"
        startFormatter.locale = Locale(identifier: "ja_JP")
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm:ss"
        endFormatter.locale = Locale(identifier: "ja_JP")
        return apply28HourClock("\(startFormatter.string(from: start)) ～ \(endFormatter.string(from: end)) (\(minutesText(durationSeconds: durationSeconds))分)")
    }

    /// 時刻を "19:00" の形にする。設定が入っていれば 28 時間表記にする。
    static func hourMinute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return apply28HourClock(formatter.string(from: date))
    }
}

// MARK: - 録画予約

/// 録画フォルダの指定 (サーバーの RecordSettings.recording_folders の要素)。
struct RecordingFolder: Codable {
    var recording_folder_path: String
    var recording_file_name_template: String?
    var is_oneseg_separate_recording_folder: Bool
}

/// 録画設定一式 (サーバーの RecordSettings)。
/// 有効/無効の切り替えは、この一式をそのまま送り返して is_enabled だけを
/// 反転させる (Web 版と同じやり方) ため、読み書きの両方が要る。
/// 応答に項目が欠けていた場合は Web 版の既定値で補う。
struct RecordSettings: Codable {
    var is_enabled: Bool
    var priority: Int
    var recording_folders: [RecordingFolder]
    var recording_start_margin: Int?
    var recording_end_margin: Int?
    var recording_mode: String
    var caption_recording_mode: String
    var data_broadcasting_recording_mode: String
    var post_recording_mode: String
    var post_recording_bat_file_path: String?
    var is_event_relay_follow_enabled: Bool
    var is_exact_recording_enabled: Bool
    var is_oneseg_separate_output_enabled: Bool
    var is_sequential_recording_in_single_file_enabled: Bool
    var forced_tuner_id: Int?

    /// Web 版の既定の録画設定 (プリセットが取れなかったときの予備)。
    static let webDefault = RecordSettings(
        is_enabled: true,
        priority: 2,
        recording_folders: [],
        recording_start_margin: nil,
        recording_end_margin: nil,
        recording_mode: "SpecifiedService",
        caption_recording_mode: "Default",
        data_broadcasting_recording_mode: "Default",
        post_recording_mode: "Default",
        post_recording_bat_file_path: nil,
        is_event_relay_follow_enabled: true,
        is_exact_recording_enabled: false,
        is_oneseg_separate_output_enabled: false,
        is_sequential_recording_in_single_file_enabled: false,
        forced_tuner_id: nil
    )

    private enum CodingKeys: String, CodingKey {
        case is_enabled, priority, recording_folders, recording_start_margin,
             recording_end_margin, recording_mode, caption_recording_mode,
             data_broadcasting_recording_mode, post_recording_mode,
             post_recording_bat_file_path, is_event_relay_follow_enabled,
             is_exact_recording_enabled, is_oneseg_separate_output_enabled,
             is_sequential_recording_in_single_file_enabled, forced_tuner_id
    }

    init(is_enabled: Bool, priority: Int, recording_folders: [RecordingFolder],
         recording_start_margin: Int?, recording_end_margin: Int?,
         recording_mode: String, caption_recording_mode: String,
         data_broadcasting_recording_mode: String, post_recording_mode: String,
         post_recording_bat_file_path: String?, is_event_relay_follow_enabled: Bool,
         is_exact_recording_enabled: Bool, is_oneseg_separate_output_enabled: Bool,
         is_sequential_recording_in_single_file_enabled: Bool, forced_tuner_id: Int?) {
        self.is_enabled = is_enabled
        self.priority = priority
        self.recording_folders = recording_folders
        self.recording_start_margin = recording_start_margin
        self.recording_end_margin = recording_end_margin
        self.recording_mode = recording_mode
        self.caption_recording_mode = caption_recording_mode
        self.data_broadcasting_recording_mode = data_broadcasting_recording_mode
        self.post_recording_mode = post_recording_mode
        self.post_recording_bat_file_path = post_recording_bat_file_path
        self.is_event_relay_follow_enabled = is_event_relay_follow_enabled
        self.is_exact_recording_enabled = is_exact_recording_enabled
        self.is_oneseg_separate_output_enabled = is_oneseg_separate_output_enabled
        self.is_sequential_recording_in_single_file_enabled = is_sequential_recording_in_single_file_enabled
        self.forced_tuner_id = forced_tuner_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = RecordSettings.webDefault
        is_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_enabled) ?? fallback.is_enabled
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? fallback.priority
        recording_folders = try container.decodeIfPresent([RecordingFolder].self, forKey: .recording_folders) ?? fallback.recording_folders
        recording_start_margin = try container.decodeIfPresent(Int.self, forKey: .recording_start_margin)
        recording_end_margin = try container.decodeIfPresent(Int.self, forKey: .recording_end_margin)
        recording_mode = try container.decodeIfPresent(String.self, forKey: .recording_mode) ?? fallback.recording_mode
        caption_recording_mode = try container.decodeIfPresent(String.self, forKey: .caption_recording_mode) ?? fallback.caption_recording_mode
        data_broadcasting_recording_mode = try container.decodeIfPresent(String.self, forKey: .data_broadcasting_recording_mode) ?? fallback.data_broadcasting_recording_mode
        post_recording_mode = try container.decodeIfPresent(String.self, forKey: .post_recording_mode) ?? fallback.post_recording_mode
        post_recording_bat_file_path = try container.decodeIfPresent(String.self, forKey: .post_recording_bat_file_path)
        is_event_relay_follow_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_event_relay_follow_enabled) ?? fallback.is_event_relay_follow_enabled
        is_exact_recording_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_exact_recording_enabled) ?? fallback.is_exact_recording_enabled
        is_oneseg_separate_output_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_oneseg_separate_output_enabled) ?? fallback.is_oneseg_separate_output_enabled
        is_sequential_recording_in_single_file_enabled = try container.decodeIfPresent(Bool.self, forKey: .is_sequential_recording_in_single_file_enabled) ?? fallback.is_sequential_recording_in_single_file_enabled
        forced_tuner_id = try container.decodeIfPresent(Int.self, forKey: .forced_tuner_id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(is_enabled, forKey: .is_enabled)
        try container.encode(priority, forKey: .priority)
        try container.encode(recording_folders, forKey: .recording_folders)
        try container.encodeIfPresent(recording_start_margin, forKey: .recording_start_margin)
        try container.encodeIfPresent(recording_end_margin, forKey: .recording_end_margin)
        try container.encode(recording_mode, forKey: .recording_mode)
        try container.encode(caption_recording_mode, forKey: .caption_recording_mode)
        try container.encode(data_broadcasting_recording_mode, forKey: .data_broadcasting_recording_mode)
        try container.encode(post_recording_mode, forKey: .post_recording_mode)
        try container.encodeIfPresent(post_recording_bat_file_path, forKey: .post_recording_bat_file_path)
        try container.encode(is_event_relay_follow_enabled, forKey: .is_event_relay_follow_enabled)
        try container.encode(is_exact_recording_enabled, forKey: .is_exact_recording_enabled)
        try container.encode(is_oneseg_separate_output_enabled, forKey: .is_oneseg_separate_output_enabled)
        try container.encode(is_sequential_recording_in_single_file_enabled, forKey: .is_sequential_recording_in_single_file_enabled)
        try container.encodeIfPresent(forced_tuner_id, forKey: .forced_tuner_id)
    }
}

/// 録画予約1件 (サーバーの Reservation)。
/// recording_availability は 'Full' / 'Partial' / 'Unavailable'。
struct Reservation: Decodable {
    let id: Int
    let channel: ChannelInfo
    let program: TimeTableProgram
    let is_recording_in_progress: Bool
    let recording_availability: String
    let comment: String
    let scheduled_recording_file_name: String
    let estimated_recording_file_size: Int
    var record_settings: RecordSettings

    /// キーワード自動予約で作られた予約かどうか (Web 版と同じ判定:
    /// コメントに「EPG自動予約」が含まれる)。
    /// 手動予約には録画側に「無効」の状態が無いため、無効化できるのは
    /// キーワード自動予約で作られた予約だけ。
    var isKeywordAutoReservation: Bool { comment.contains("EPG自動予約") }

    /// 手動予約かどうか (キーワード自動予約でない予約)。
    /// 手動予約では有効/無効の切り替え自体を出さない。
    var isManualReservation: Bool { !isKeywordAutoReservation }
}

/// 予約一覧の応答。
struct ReservationsResponse: Decodable {
    let total: Int
    let reservations: [Reservation]
}

/// 録画設定プリセット1件 (一覧のうち id が 0 のものが既定の録画設定)。
struct RecordSettingsPreset: Decodable {
    let id: Int
    let name: String
    let record_settings: RecordSettings
}

/// プリセット一覧の応答 (global_defaults は使わないので受けない)。
struct RecordSettingsPresetsResponse: Decodable {
    let presets: [RecordSettingsPreset]
}

/// バージョン情報の応答のうち、サーバーの版 (version) だけを読むための型。
/// 応答には最新の版や稼働環境なども含まれるが、表示に使うのは version のみ。
struct ServerVersionResponse: Decodable {
    let version: String
}

/// サーバー設定のうち、土台 (general.backend) だけを読むための型。
/// backend は 'EDCB' か 'Mirakurun'。
struct ServerBackendResponse: Decodable {
    struct General: Decodable {
        let backend: String
    }
    let general: General
}

/// 予約追加の送信内容。番組はサーバー側の番組表にあるため program_id だけでよい
/// (Web 版の番組詳細からの追加と同じ)。
struct ReservationAddRequest: Encodable {
    let program_id: String
    let record_settings: RecordSettings
}

/// 予約更新の送信内容。
struct ReservationUpdateRequest: Encodable {
    let record_settings: RecordSettings
}

/// 番組検索条件 (Web 版の IProgramSearchCondition と同じ形)。
/// 「次回を予約」の番組表検索と、キーワード自動予約の条件の両方で使う。
struct ProgramSearchCondition: Codable {
    var is_enabled: Bool
    var keyword: String
    var exclude_keyword: String
    var note: String
    var is_title_only: Bool
    var is_case_sensitive: Bool
    var is_fuzzy_search_enabled: Bool
    var is_regex_search_enabled: Bool
    var service_ranges: [ProgramSearchServiceRange]?
    var genre_ranges: [ProgramSearchGenreRange]?
    var is_exclude_genre_ranges: Bool
    var date_ranges: [ProgramSearchDateRange]?
    var is_exclude_date_ranges: Bool
    var duration_range_min: Int?
    var duration_range_max: Int?
    /// "All" / "FreeOnly" / "PaidOnly"。
    var broadcast_type: String
    /// "None" / "SameChannelOnly" / "AllChannels"。
    var duplicate_title_check_scope: String
    var duplicate_title_check_period_days: Int
}

/// 番組検索条件のチャンネル指定。
struct ProgramSearchServiceRange: Codable {
    let network_id: Int
    let transport_stream_id: Int
    let service_id: Int
}

/// 番組検索条件のジャンル指定。
struct ProgramSearchGenreRange: Codable {
    let major: String
    let middle: String
}

/// 番組検索条件の曜日・時刻指定。
struct ProgramSearchDateRange: Codable {
    let start_day_of_week: Int
    let start_hour: Int
    let start_minute: Int
    let end_day_of_week: Int
    let end_hour: Int
    let end_minute: Int
}

/// 番組検索 (POST /api/programs/search) の結果1件分。
/// 次回の放送の候補として使うため、番組 ID・題名・時刻・イベント ID だけ受ける。
struct SearchedProgram: Decodable {
    let id: String
    let title: String
    let start_time: String
    let end_time: String
    let event_id: Int?

    var startDate: Date? { DateParser.parse(start_time) }
}

/// 番組検索の応答。
struct ProgramSearchResponse: Decodable {
    let total: Int
    let programs: [SearchedProgram]
}

/// キーワード自動予約の条件1件 (GET /api/recording/conditions の要素)。
struct ReservationCondition: Decodable {
    let id: Int
    /// この条件でこれまでに追加された予約の件数。
    let reservation_count: Int
    let program_search_condition: ProgramSearchCondition
    let record_settings: RecordSettings
}

/// キーワード自動予約の条件一覧の応答。
struct ReservationConditionsResponse: Decodable {
    let total: Int
    let reservation_conditions: [ReservationCondition]
}

/// キーワード自動予約の条件の追加の送信内容。
struct ReservationConditionAddRequest: Encodable {
    let program_search_condition: ProgramSearchCondition
    let record_settings: RecordSettings
}

/// ニコニコ実況の過去ログコメント1件分 (GET /api/videos/{id}/jikkyo の1要素)。
/// time は録画の開始からの秒数 (再生位置とそのまま合う)。
/// type は位置 ("top" = 上に固定、"right" = 右から左へ流れる、"bottom" = 下に固定)、
/// size は大きさ ("big" / "medium" / "small")、color は "#RRGGBB" 形式。
struct JikkyoComment: Codable {
    let time: Double
    let type: String
    let size: String
    let color: String
    let author: String
    let text: String
}

/// 録画の過去ログコメントの応答一式。
/// チャンネル情報が無い録画などでは is_success が false で返る。
struct JikkyoCommentsResponse: Codable {
    let is_success: Bool
    let comments: [JikkyoComment]
    let detail: String
}
