import AVFoundation
import Foundation

enum APIError: Error {
    case notConfigured
    case badStatus(Int)
    /// 応答の形が想定と違った (JSON の辞書でないなど)。
    case invalidResponse
    /// サーバー側で保護の仕組みが無効なため切り替えられない。
    case protectionUnavailable
    /// サーバーからの応答内容をもとに作った、ユーザー向けの文が入っている失敗。
    case message(String)

    /// 保護の切り替えに失敗した理由を、ユーザー向けの文にする。
    var protectionFailureMessage: String {
        switch self {
        case .badStatus(401):
            return "ログインの有効期限が切れています。設定タブでログインし直してください。"
        case .badStatus(409):
            return "録画中の番組は保護を切り替えられません。"
        case .protectionUnavailable:
            return "この録画では保護を切り替えられません。"
        default:
            return "保護を切り替えられませんでした。"
        }
    }
}

/// KonomiTV サーバーへの通信をまとめたもの。
/// Cloudflare Access のサービストークンが設定されていれば、全リクエストにヘッダーを付ける。
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private func url(forPath path: String) -> URL? {
        guard let base = SettingsStore.shared.baseURL else { return nil }
        return URL(string: base.absoluteString + path)
    }

    private func request(forPath path: String, method: String = "GET", authorized: Bool = false) throws -> URLRequest {
        guard let url = url(forPath: path) else { throw APIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in SettingsStore.shared.cfAccessHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // 管理者ログインが必要な口には、ログイン済みのときだけ Bearer トークンを付ける。
        if authorized, SettingsStore.shared.isLoggedIn {
            request.setValue("Bearer \(SettingsStore.shared.accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }
    }

    // MARK: - 録画一覧

    /// 30件ずつ。並び順はサーバー側の指定 (order = "desc" が新しい順、"asc" が古い順)。
    func fetchVideos(page: Int, order: String = "desc") async throws -> RecordedProgramsResponse {
        let request = try request(forPath: "/api/videos?order=\(order)&page=\(page)")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(RecordedProgramsResponse.self, from: data)
    }

    /// 録画ストレージの容量情報 (ローカル改造の口)。
    /// Web 版と同じく、取得に失敗した場合は表示自体を出さないため nil を返す。
    func fetchStorageStatus() async -> StorageStatus? {
        guard let request = try? request(forPath: "/api/videos/storage-status") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(StorageStatus.self, from: data)
    }

    /// 録画の放送中に投稿されたニコニコ実況の過去ログコメントを取る (ログイン不要)。
    /// コメントが無い・取れない場合は表示自体を出さないため、失敗したら nil を返す
    /// (Web 版も取得できなければコメントなしで再生を続ける)。
    func fetchJikkyoComments(videoID: Int) async -> JikkyoCommentsResponse? {
        guard let request = try? request(forPath: "/api/videos/\(videoID)/jikkyo") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(JikkyoCommentsResponse.self, from: data)
    }

    func fetchThumbnail(videoID: Int) async throws -> Data {
        let request = try request(forPath: "/api/videos/\(videoID)/thumbnail")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return data
    }

    /// シーク中のプレビュー用のタイル画像 (サムネイルを並べた1枚絵) を取る。
    /// 録画中やタイル画像が無い録画ではサーバーが既定の画像を返すため、
    /// 絵の寸法が番組データのタイル情報と合うかは呼び出し側で確かめる。
    /// 取れなければプレビュー自体を出さないため、失敗したら nil を返す。
    func fetchTiledThumbnail(videoID: Int) async -> Data? {
        guard let request = try? request(forPath: "/api/videos/\(videoID)/thumbnail/tiled") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    // MARK: - ログイン

    /// ユーザー名とパスワードでアクセストークンを取り、ログイン情報として保存する。
    /// トークンの口は OAuth2 形式 (フォーム送信) で、応答は JSON。
    func login(username: String, password: String) async throws {
        var request = try request(forPath: "/api/users/token", method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(Self.formEncode(username))&password=\(Self.formEncode(password))"
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try check(response)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        SettingsStore.shared.saveLogin(username: username, password: password, token: token.access_token)
    }

    // MARK: - アカウント情報 (マイページ用)

    /// ログイン中のユーザー自身の情報を取る (ログイン必須)。
    func fetchCurrentUser() async throws -> UserInfo {
        let request = try request(forPath: "/api/users/me", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    /// ログイン中のユーザーのアイコン画像を取る (ログイン必須)。
    /// アイコン未設定でもサーバーは既定の画像を返す想定だが、失敗したら呼び出し側で placeholder 表示にする。
    func fetchCurrentUserIcon() async throws -> Data {
        let request = try request(forPath: "/api/users/me/icon", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return data
    }

    /// ログイン中のユーザーの情報 (ユーザー名・パスワード) を更新する
    /// (ログイン必須)。渡した項目だけが更新される。ユーザー名が他の
    /// アカウントと重なる場合などはサーバーが 422 を返す。
    func updateCurrentUser(username: String?, password: String?) async throws {
        var body: [String: Any] = [:]
        if let username { body["username"] = username }
        if let password { body["password"] = password }
        var request = try request(forPath: "/api/users/me", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    // MARK: - 利用者設定 (クライアント設定)

    /// サーバーに保存されている利用者設定を丸ごと取る (ログイン必須)。
    /// 中身は型で定義し直さず、JSON の辞書のまま返す。アプリが知らない
    /// キーを落とさないためで、書き戻しのときもこの辞書を土台にする。
    func fetchClientSettings() async throws -> [String: Any] {
        let request = try request(forPath: "/api/settings/client", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let settings = object as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return settings
    }

    /// 利用者設定を丸ごと送る (ログイン必須、成功は 204)。
    /// サーバーに保存されている分の last_synced_at より古い内容は
    /// 422 で拒否される。
    func updateClientSettings(_ settings: [String: Any]) async throws {
        var request = try request(forPath: "/api/settings/client", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: settings)
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - 視聴状態・保護

    /// 再生位置をサーバーへ報告する。サーバーは到達した最大位置だけを残し、
    /// 一覧の見た割合 (watched_ratio) として全端末へ返す (認証なし)。
    /// 再生中の定期報告と、視聴済みにする操作の両方から使う。
    func reportWatched(videoID: Int, position: Double) async throws {
        var request = try request(forPath: "/api/videos/\(videoID)/watched", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["position": position])
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    /// 視聴済みにする。サーバーは到達した最大位置だけを残すので、
    /// 尺いっぱいの位置を送れば見た割合が 1.0 になる (認証なし)。
    func markWatched(videoID: Int, duration: Double) async throws {
        try await reportWatched(videoID: videoID, position: duration)
    }

    /// 現在の保護状態を取る (管理者ログイン必須)。
    func fetchProtection(videoID: Int) async throws -> ProtectionState {
        let request = try request(forPath: "/api/videos/\(videoID)/protection", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(ProtectionState.self, from: data)
    }

    /// 保護状態を切り替えて、切り替え後の状態を返す (管理者ログイン必須)。
    /// epgstation_id は取得した値をそのまま返す (管理外の録画では null)。
    func toggleProtection(videoID: Int) async throws -> Bool {
        let current = try await fetchProtection(videoID: videoID)
        if current.enabled == false {
            throw APIError.protectionUnavailable
        }
        let next = !(current.is_protected ?? false)
        var request = try request(forPath: "/api/videos/\(videoID)/protection", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let epgstationID: Any = current.epgstation_id.map { $0 as Any } ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "epgstation_id": epgstationID,
            "is_protected": next,
        ])
        let (data, response) = try await session.data(for: request)
        try check(response)
        let result = try JSONDecoder().decode(ProtectionState.self, from: data)
        return result.is_protected ?? next
    }

    // MARK: - 生放送のチャンネル一覧

    func fetchChannels() async throws -> LiveChannelsResponse {
        let request = try request(forPath: "/api/channels")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(LiveChannelsResponse.self, from: data)
    }

    /// 局ロゴの PNG を取る。ロゴが無い局では 404 になる。
    /// 窓口はチャンネル ID (id または display_channel_id) を受け付ける。
    func fetchChannelLogo(channelID: String) async throws -> Data {
        let encoded = channelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? channelID
        let request = try request(forPath: "/api/channels/\(encoded)/logo")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return data
    }

    // MARK: - 録画再生 (HLS)

    // 画質名はここで実際にサーバーへ渡す形に直す (区分ごとの設定に応じて
    // "-hevc" や "-24fps" が付く)。プレイリストと keep-alive で同じ形を使う
    // 必要があるため、変換はこの3つの窓口に集約してある。
    // 区分 (profile) は再生を始めるときに決めたものを呼び出し側が渡す
    // (再生の途中で回線が変わっても画質は変えないため)。

    func playlistURL(videoID: Int, quality: String, profile: PlaybackProfile, sessionID: String) -> URL? {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .video, profile: profile)
        return url(forPath: "/api/streams/video/\(videoID)/\(apiQuality)/playlist?session_id=\(sessionID)")
    }

    /// 再生中、定期的に呼んでセッションを維持する (サーバー側の分割ファイル生成を止めないため)。
    func keepAlive(videoID: Int, quality: String, profile: PlaybackProfile, sessionID: String) async {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .video, profile: profile)
        guard let request = try? request(
            forPath: "/api/streams/video/\(videoID)/\(apiQuality)/keep-alive?session_id=\(sessionID)",
            method: "PUT"
        ) else { return }
        _ = try? await session.data(for: request)
    }

    // MARK: - 番組表

    /// 番組表を取る。Web 版と同じく、種別を絞って 4:00 起点の1日分ずつ取る。
    /// 日時はタイムゾーン付きの ISO 8601 で渡す (Web 版の送信形式と同じ)。
    func fetchTimeTable(start: Date, end: Date, channelType: String?) async throws -> TimeTableResponse {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        // "+" を空白と解釈されないよう、クエリの値は自前でエスケープする
        // (Web 版の URLSearchParams も "+" を %2B にする)。
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+")
        func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        var path = "/api/programs/timetable?start_time=\(escape(formatter.string(from: start)))"
            + "&end_time=\(escape(formatter.string(from: end)))"
        if let channelType {
            path += "&channel_type=\(escape(channelType))"
        }
        let request = try request(forPath: path)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(TimeTableResponse.self, from: data)
    }

    // MARK: - バージョン情報

    /// 接続中のサーバーの KonomiTV の版を取る。
    /// バージョン情報の取得口はログイン不要 (Web 版もログインなしで取っている)。
    /// 取れなかった場合は nil (呼び出し側で「取得できませんでした」の表示にする)。
    func fetchServerVersion() async -> String? {
        guard let request = try? request(forPath: "/api/version") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(ServerVersionResponse.self, from: data).version
    }

    // MARK: - 録画予約

    /// サーバーの土台 ('EDCB' か 'Mirakurun') を取る。
    /// サーバー設定の取得口はログイン不要。取れなかった場合は nil。
    /// 録画予約が使えるかどうかの判定はこの値で行う (Web 版と同じ)。
    func fetchServerBackend() async -> String? {
        guard let request = try? request(forPath: "/api/settings/server") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(ServerBackendResponse.self, from: data).general.backend
    }

    /// 予約一覧を取る。
    func fetchReservations() async throws -> ReservationsResponse {
        let request = try request(forPath: "/api/recording/reservations")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(ReservationsResponse.self, from: data)
    }

    /// 予約1件を取り直す。
    func fetchReservation(id: Int) async throws -> Reservation {
        let request = try request(forPath: "/api/recording/reservations/\(id)")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(Reservation.self, from: data)
    }

    /// 既定の録画設定を取る (プリセットの id 0)。
    /// プリセットが取れなかった場合は Web 版の既定値に落ちる (Web 版と同じ)。
    func fetchDefaultRecordSettings() async -> RecordSettings {
        guard let request = try? request(forPath: "/api/recording/presets"),
              let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let presets = try? JSONDecoder().decode(RecordSettingsPresetsResponse.self, from: data),
              let preset = presets.presets.first(where: { $0.id == 0 }) else {
            return .webDefault
        }
        return preset.record_settings
    }

    /// 予約を追加する。失敗したら、サーバーの応答をもとにした文で失敗を返す
    /// (黙って成功扱いにしない)。
    func addReservation(programID: String, recordSettings: RecordSettings) async throws {
        var request = try request(forPath: "/api/recording/reservations", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ReservationAddRequest(program_id: programID, record_settings: recordSettings))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationFailureMessage(
                data: data, operation: .add))
        }
    }

    /// 予約の録画設定を送り直して、更新後の予約を返す。
    /// 有効/無効の切り替えは、設定一式の is_enabled だけを反転させて送る。
    func updateReservation(id: Int, recordSettings: RecordSettings) async throws -> Reservation {
        var request = try request(forPath: "/api/recording/reservations/\(id)", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ReservationUpdateRequest(record_settings: recordSettings))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationFailureMessage(
                data: data, operation: .update))
        }
        return try JSONDecoder().decode(Reservation.self, from: data)
    }

    /// 予約を削除する。
    func deleteReservation(id: Int) async throws {
        let request = try request(forPath: "/api/recording/reservations/\(id)", method: "DELETE")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationFailureMessage(
                data: data, operation: .delete))
        }
    }

    private enum ReservationOperation {
        case add, update, delete
    }

    /// サーバーの失敗応答 (detail の英語文) を、Web 版と同じ日本語の文に直す。
    private static func reservationFailureMessage(data: Data, operation: ReservationOperation) -> String {
        var detail: String?
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            detail = dictionary["detail"] as? String
        }
        if detail == "This API is only available when the backend is EDCB" {
            return "録画予約機能は EDCB バックエンド選択時のみ利用できます。"
        }
        switch operation {
        case .add:
            switch detail {
            case "Specified program was not found":
                return "指定された番組が見つかりませんでした。"
            case "Specified channel was not found":
                return "指定されたチャンネルが見つかりませんでした。"
            case "Specified program duration is unknown":
                return "この番組は放送時間が未定のため、録画予約できません。"
            case "Program payload does not match channel":
                return "番組情報とチャンネル情報が一致しないため、録画予約できません。"
            case "Specified channel does not have transport_stream_id":
                return "チャンネル情報に TSID がないため、録画予約できません。"
            case "Specified program has already ended":
                return "すでに終了した番組のため、録画予約できません。"
            case "The same program_id is already reserved":
                return "この番組は既に録画予約されています。"
            default:
                return "録画予約の追加に失敗しました。"
            }
        case .update:
            if detail == "Specified reservation_id was not found" {
                return "指定された録画予約が見つかりませんでした。"
            }
            return "録画予約の更新に失敗しました。"
        case .delete:
            if detail == "Specified reservation_id was not found" {
                return "指定された録画予約が見つかりませんでした。"
            }
            return "録画予約の削除に失敗しました。"
        }
    }

    // MARK: - 生放送 (MPEG-TS)

    func liveStreamURL(displayChannelID: String, quality: String, profile: PlaybackProfile) -> URL? {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .tv, profile: profile)
        return url(forPath: "/api/streams/live/\(displayChannelID)/\(apiQuality)/mpegts")
    }

    // MARK: - AVPlayer 用

    /// CF ヘッダーを付けた AVURLAsset を作る (プレイリストと分割ファイルの両方に同じヘッダーが付く)。
    func playerAsset(url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": SettingsStore.shared.cfAccessHeaders,
        ])
    }
}

/// Web 版と共通の視聴履歴 (利用者設定の watched_history) への読み書き。
///
/// 取得した利用者設定はキー単位でそのまま保持し、触るのは watched_history と
/// last_synced_at だけにする。アプリが知らないキーを落として送ると、その設定が
/// サーバー側から消えてしまうため (PUT は丸ごと差し替え)。
/// 失敗しても利用者には見せず、再生はそのまま続ける前提の作りにしてある。
final class WatchedHistorySync {

    /// 視聴履歴の最大件数の既定値 (サーバー・Web 版の既定と同じ)。
    /// 取得した設定に video_watched_history_max_count があればそちらを使う。
    private static let defaultMaxCount = 50

    /// 同期が効く状態か (ログイン中かつ「設定をデバイス間で同期する」がオン)。
    static var isEnabled: Bool {
        SettingsStore.shared.isLoggedIn && SettingsStore.shared.syncSettings
    }

    /// 視聴履歴に残っている前回の再生位置 (秒)。
    /// 同期が効いていない・履歴に無い・位置が取れない・取得に失敗した場合は nil
    /// (呼び出し側は今までの元データに落ちる)。
    static func lastPlaybackPosition(videoID: Int) async -> Double? {
        guard isEnabled else { return nil }
        guard let settings = try? await APIClient.shared.fetchClientSettings() else { return nil }
        guard let index = entryIndex(in: settings, videoID: videoID) else { return nil }
        let history = historyArray(in: settings)
        return (history[index]["last_playback_position"] as? NSNumber)?.doubleValue
    }

    /// 再生位置を視聴履歴へ書き戻す。
    /// 手順は厳密に「送る直前に最新を取得 → watched_history の該当項目だけ
    /// 差し替え → last_synced_at を今に更新して PUT」。
    /// 422 (その間に Web 版などで先に更新された) が返ったら、1回だけ取り直して
    /// やり直す。それでも駄目なら、この回の更新は諦める。
    /// - registerIfNeeded: 履歴にまだ無い録画を新規登録してよいか。
    ///   Web 版は視聴画面を開いて30秒経ってから登録するので、呼び出し側が
    ///   経過時間を見て決める。登録時は最大件数を超える分を、最も古い
    ///   (created_at が最小の) ものから落とす (Web 版の動きと同じ)。
    static func syncPosition(videoID: Int, position: Double, registerIfNeeded: Bool) async {
        guard isEnabled else { return }
        // 1回だけやり直す (初回 + 再試行1回)。
        for _ in 0..<2 {
            do {
                var settings = try await APIClient.shared.fetchClientSettings()
                var history = historyArray(in: settings)
                let now = Date().timeIntervalSince1970
                if let index = history.firstIndex(where: {
                    ($0["video_id"] as? NSNumber)?.intValue == videoID
                }) {
                    history[index]["last_playback_position"] = position
                    history[index]["updated_at"] = now
                } else if registerIfNeeded {
                    let maxCount = (settings["video_watched_history_max_count"] as? NSNumber)?.intValue
                        ?? defaultMaxCount
                    if history.count >= maxCount, !history.isEmpty {
                        var oldest = 0
                        for i in history.indices {
                            let created = (history[i]["created_at"] as? NSNumber)?.doubleValue ?? 0
                            let oldestCreated = (history[oldest]["created_at"] as? NSNumber)?.doubleValue ?? 0
                            if created < oldestCreated { oldest = i }
                        }
                        history.remove(at: oldest)
                    }
                    history.append([
                        "video_id": videoID,
                        "last_playback_position": position,
                        "created_at": now,
                        "updated_at": now,
                    ])
                } else {
                    // 触る項目が無いので送らない (last_synced_at も進めない)。
                    return
                }
                settings["watched_history"] = history
                settings["last_synced_at"] = now
                try await APIClient.shared.updateClientSettings(settings)
                return
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch {
                return  // それ以外の失敗は、この回の更新を諦める。
            }
        }
    }

    private static func historyArray(in settings: [String: Any]) -> [[String: Any]] {
        settings["watched_history"] as? [[String: Any]] ?? []
    }

    private static func entryIndex(in settings: [String: Any], videoID: Int) -> Int? {
        historyArray(in: settings).firstIndex(where: {
            ($0["video_id"] as? NSNumber)?.intValue == videoID
        })
    }
}
