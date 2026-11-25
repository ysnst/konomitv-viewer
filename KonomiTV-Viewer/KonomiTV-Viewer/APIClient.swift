import AVFoundation
import Foundation

enum APIError: Error {
    case notConfigured
    case badStatus(Int)
    /// 送る内容を JSON の形にできなかった。送信自体を行っていない
    /// ため、サーバーへは届いていないことが明らかな失敗。
    case encodingFailed
    /// 応答の形が想定と違った (JSON の辞書でないなど)。
    case invalidResponse
    /// サーバー側で保護の仕組みが無効なため切り替えられない。
    case protectionUnavailable
    /// サーバーからの応答内容をもとに作った、ユーザー向けの文が入っている失敗。
    case message(String)
    /// ログインの応答が返るまでの間に、接続先の変更・ログアウト・
    /// 別のログインがあり、この試行が古くなった (応答は保存しない)。
    case loginSuperseded
    /// 処理の途中でログインや接続先が変わり、この操作が古くなった。
    /// 応答が成功でも、結果は今のログインのものとして扱わない
    /// (アカウント編集の遅れて届いた応答が、別のアカウントの
    /// 端末内の資格情報を上書きしないため)。
    case staleSession

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

    /// ゴミ箱への移動に失敗した理由を、ユーザー向けの文にする。
    var moveToTrashFailureMessage: String {
        switch self {
        case .badStatus(401):
            return "ログインの有効期限が切れています。設定タブでログインし直してください。"
        case .badStatus(404):
            return "この録画は見つかりませんでした。一覧を更新してください。"
        case .badStatus(409):
            return "録画中の番組はゴミ箱に移動できません。"
        default:
            return "ゴミ箱に移動できませんでした。"
        }
    }

    /// ゴミ箱からの復元に失敗した理由を、ユーザー向けの文にする。
    var restoreFromTrashFailureMessage: String {
        switch self {
        case .badStatus(401):
            return "ログインの有効期限が切れています。設定タブでログインし直してください。"
        case .badStatus(404):
            return "この録画はすでにゴミ箱にありません。一覧を更新してください。"
        default:
            return "ゴミ箱から復元できませんでした。"
        }
    }

    /// 完全削除に失敗した理由を、ユーザー向けの文にする。
    var deleteVideoFailureMessage: String {
        switch self {
        case .badStatus(401):
            return "ログインの有効期限が切れています。設定タブでログインし直してください。"
        case .badStatus(404):
            return "この録画は見つかりませんでした。一覧を更新してください。"
        case .badStatus(409):
            return "録画中の番組は削除できません。録画が終わってから操作してください。"
        default:
            return "完全に削除できませんでした。"
        }
    }
}

/// KonomiTV サーバーへの通信をまとめたもの。
/// 認証方式が選ばれていれば、全リクエストにその方式のヘッダーを付ける。
final class APIClient {
    static let shared = APIClient()

    /// 認証の求め (Digest認証) への応答を受け持つ受け手。
    /// 受け手付きのセッションでも、通常の読み書きは今までどおり行える。
    private let authDelegate = ServerAuthSessionDelegate()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: authDelegate, delegateQueue: nil)
    }

    /// URL のパスやクエリへ埋め込む値を、区切りの記号 (? # / & = 等) が
    /// そのまま解釈されないよう逃がす。ID は通常、数字や英字だけだが、
    /// 想定外の値が来ても URL の形が壊れないようにするための守り。
    static func escapedURLComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func url(forPath path: String) -> URL? {
        guard let base = SettingsStore.shared.baseURL else { return nil }
        guard let url = URL(string: base.absoluteString + path) else { return nil }
        // 認証方式が「URLパラメータ (合言葉)」のときは、ここで合言葉を
        // 付ける (API・画像・再生の URL はすべてこの口を通る)。
        return SettingsStore.shared.urlByApplyingAuthParameter(to: url)
    }

    private func request(forPath path: String, method: String = "GET", authorized: Bool = false) throws -> URLRequest {
        guard let url = url(forPath: path) else { throw APIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in SettingsStore.shared.serverAuthHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // 管理者ログインが必要な口には、ログイン済みのときだけ Bearer トークンを付ける。
        // (Authorization は1つしか付けられないため、ログインが要る口では
        // こちらを優先する。Basic認証のヘッダーは他の口に付く。)
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
    func fetchVideos(page: Int, order: String = "desc", searchQuery: String = "") async throws -> RecordedProgramsResponse {
        var components = URLComponents()
        components.path = searchQuery.isEmpty ? "/api/videos" : "/api/videos/search"
        components.queryItems = [URLQueryItem(name: "order", value: order),
                                 URLQueryItem(name: "page", value: String(page))]
        if !searchQuery.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "query", value: searchQuery))
        }
        // FastAPI のクエリ解釈では + は空白になるため、リテラルの + は明示的に符号化する。
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let path = components.string else { throw APIError.invalidResponse }
        let request = try request(forPath: path)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(RecordedProgramsResponse.self, from: data)
    }

    /// 視聴履歴用。order = "ids" で、渡した ID の並びを保ったまま
    /// ページ分だけ返る (Web 版の視聴履歴と同じ取り方)。
    /// ID は Web 版と同じく ids=1&ids=2&... の形で繰り返して渡す。
    func fetchVideos(page: Int, ids: [Int]) async throws -> RecordedProgramsResponse {
        try await fetchVideos(page: page, order: "ids", ids: ids)
    }

    /// ID を指定して録画番組を取る。order = "ids" のときは渡した ID の
    /// 並びを保ち、"desc" / "asc" のときは渡した ID の範囲内で録画日時の
    /// 順に並べ替えて返る (Web 版のマイリストと同じ取り方)。
    func fetchVideos(page: Int, order: String, ids: [Int]) async throws -> RecordedProgramsResponse {
        let idsQuery = ids.map { "ids=\($0)" }.joined(separator: "&")
        let request = try request(forPath: "/api/videos?order=\(order)&page=\(page)&\(idsQuery)")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(RecordedProgramsResponse.self, from: data)
    }

    /// 録画番組1件を単体で取得する。改造サーバーはこの応答にだけ
    /// 前の話・次の話の ID を付けるため、前後移動の確認に使う。
    /// 失敗時は nil。
    func fetchVideo(videoID: Int) async -> RecordedProgram? {
        guard let request = try? request(forPath: "/api/videos/\(videoID)") else { return nil }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(RecordedProgram.self, from: data)
    }

    /// しおりの一覧を取得する (改造サーバー用。ログインは不要で世帯共有)。
    /// 失敗時は空の並びを返す (呼び出し側は「しおりなし」として扱う)。
    func fetchBookmarks(videoID: Int) async -> [VideoBookmark] {
        guard let request = try? request(forPath: "/api/videos/\(videoID)/bookmarks") else { return [] }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return [] }
        let bookmarks = (try? JSONDecoder().decode([VideoBookmark].self, from: data)) ?? []
        return bookmarks.sorted { $0.position < $1.position }
    }

    /// しおりを追加する (改造サーバー用。ログインは不要)。
    /// 成功時は作られたしおり、失敗時は nil を返す。
    func createBookmark(videoID: Int, position: Double, label: String) async -> VideoBookmark? {
        guard var request = try? request(forPath: "/api/videos/\(videoID)/bookmarks", method: "POST") else { return nil }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["position": position, "label": label]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(VideoBookmark.self, from: data)
    }

    /// しおりを削除する (改造サーバー用。ログインは不要)。
    /// 成功したら true を返す。
    func deleteBookmark(videoID: Int, bookmarkID: String) async -> Bool {
        guard let request = try? request(
            forPath: "/api/videos/\(videoID)/bookmarks/\(Self.escapedURLComponent(bookmarkID))", method: "DELETE")
        else { return false }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
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

    /// ログインの試行の通し番号。新しい試行のたびに進む。
    /// 応答が返るまでの間に別の試行が始まっていたら、古い試行の
    /// 応答は保存しない (遅れて届いた応答が、新しいログインを
    /// 上書きしてしまうため)。
    /// 番号の加算と読み取りは鍵で守る。同時に2つのログインが
    /// 走ると、守りがないと同じ番号を両方が掴んでしまい、古い
    /// 応答まで「最新の試行」として通ってしまうため。
    private var latestLoginAttempt = 0
    private let loginAttemptLock = NSLock()

    /// 次のログイン試行の番号を取り、最新の試行として記録する。
    private func nextLoginAttempt() -> Int {
        loginAttemptLock.lock()
        defer { loginAttemptLock.unlock() }
        latestLoginAttempt += 1
        return latestLoginAttempt
    }

    /// 渡された番号が、今も最新のログイン試行かどうか。
    private func isLatestLoginAttempt(_ attempt: Int) -> Bool {
        loginAttemptLock.lock()
        defer { loginAttemptLock.unlock() }
        return attempt == latestLoginAttempt
    }

    /// ユーザー名とパスワードでアクセストークンを取り、ログイン情報として保存する。
    /// トークンの口は OAuth2 形式 (フォーム送信) で、応答は JSON。
    func login(username: String, password: String) async throws {
        // 始めた時点の接続先・認証の世代・試行の番号を控える。
        // 応答が返るまでの間に接続先の変更 (前のログインの失効) や
        // ログアウト・別のログインがあったら、この応答は古い試行の
        // ものなので保存しない。保存してしまうと、接続先変更で
        // 消したはずのログインが復活してしまう。
        let store = SettingsStore.shared
        let baseURLAtStart = store.baseURL
        let generationAtStart = store.authGeneration
        let attempt = nextLoginAttempt()
        var request = try request(forPath: "/api/users/token", method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(Self.formEncode(username))&password=\(Self.formEncode(password))"
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try check(response)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard isLatestLoginAttempt(attempt),
              store.authGeneration == generationAtStart,
              store.baseURL == baseURLAtStart else {
            throw APIError.loginSuperseded
        }
        store.saveLogin(username: username, password: password, token: token.access_token)
        // まだ同期したことのない端末では、サーバーに保存済みの
        // 設定があればログインのついでに自動で取り込む (Web 版と同じ
        // 動き)。アプリだけで完結するため常時有効。
        Task { await SyncedSettingsStore.shared.adoptServerSettingsOnLogin() }
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
    /// 始めた時点の認証の世代と接続先を控え、応答が返るまでの間に
    /// ログアウト・別のログイン・接続先の変更があったら、成功でも
    /// 古い操作として失敗 (staleSession) にする。呼び出し側は成功を
    /// 前提に、入力値を端末内の資格情報へ書き込むため、遅れて届いた
    /// 応答をそのまま成功として扱うと、別のアカウントの保存値が
    /// 前のアカウントの値で上書きされてしまう。
    func updateCurrentUser(username: String?, password: String?) async throws {
        let store = SettingsStore.shared
        let generationAtStart = store.authGeneration
        let baseURLAtStart = store.baseURL
        var body: [String: Any] = [:]
        if let username { body["username"] = username }
        if let password { body["password"] = password }
        var request = try request(forPath: "/api/users/me", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        try check(response)
        guard store.authGeneration == generationAtStart,
              store.baseURL == baseURLAtStart else {
            throw APIError.staleSession
        }
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
    /// expectedAuthGeneration を渡すと、送信の応答が返るまでの間に
    /// 認証の世代が変わっていた場合、同期した時刻の控えは進めない
    /// (別のアカウントの同期として数えないため)。
    func updateClientSettings(
        _ settings: [String: Any], expectedAuthGeneration: Int? = nil
    ) async throws {
        var request = try request(forPath: "/api/settings/client", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 形にできない場合は送信前の失敗として分ける (送信したのに
        // 応答が無かった失敗と混ざると、届いていない変更まで
        // 「届いたかもしれない」扱いになってしまうため)。
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: settings)
        } catch {
            throw APIError.encodingFailed
        }
        let (_, response) = try await session.data(for: request)
        try check(response)
        // 送れた時点で、この端末はサーバーと同期したことになる
        // (ログイン時の自動取り込みの判定に使う端末側の控え)。
        if let expectedAuthGeneration,
           SettingsStore.shared.authGeneration != expectedAuthGeneration {
            return
        }
        if let syncedAt = (settings["last_synced_at"] as? NSNumber)?.doubleValue {
            SettingsStore.shared.lastSyncedAt = syncedAt
        }
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

    /// 切り替え中の録画 ID (同じ録画への切り替えが重なって、両方が同じ
    /// 現在値を読んでしまうのを防ぐ)。
    private var protectionTogglesInFlight: Set<Int> = []
    private let protectionToggleLock = NSLock()

    /// 保護状態を切り替えて、切り替え後の状態を返す (管理者ログイン必須)。
    /// epgstation_id は取得した値をそのまま返す (管理外の録画では null)。
    func toggleProtection(videoID: Int) async throws -> Bool {
        // 同じ録画への切り替えが実行中なら、終わるまで待ってから
        // 現在値を取り直す (重なると2回切り替えても1回分しか変わらない)。
        while true {
            protectionToggleLock.lock()
            let busy = protectionTogglesInFlight.contains(videoID)
            if !busy { protectionTogglesInFlight.insert(videoID) }
            protectionToggleLock.unlock()
            if !busy { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        defer {
            protectionToggleLock.lock()
            protectionTogglesInFlight.remove(videoID)
            protectionToggleLock.unlock()
        }
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

    /// 保護状態を指定した状態にする (管理者ログイン必須)。
    /// 切り替え (toggleProtection) と同じ受け口で、まとめて保護する
    /// ときのように目的の状態が決まっている場合に使う。
    /// すでに目的の状態なら通信しない。
    func setProtection(videoID: Int, protected: Bool) async throws {
        let current = try await fetchProtection(videoID: videoID)
        if current.enabled == false {
            throw APIError.protectionUnavailable
        }
        if (current.is_protected ?? false) == protected {
            return
        }
        var request = try request(forPath: "/api/videos/\(videoID)/protection", method: "PUT", authorized: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let epgstationID: Any = current.epgstation_id.map { $0 as Any } ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "epgstation_id": epgstationID,
            "is_protected": protected,
        ])
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    // MARK: - ゴミ箱 (ローカル改造の口、拡張版だけが使う)

    /// ゴミ箱の中身を取る (ログイン必須)。
    /// 並びはサーバー側で完全に削除される予定の早い順になっている。
    func fetchTrashList() async throws -> TrashListResponse {
        let request = try request(forPath: "/api/recorder/trash", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(TrashListResponse.self, from: data)
    }

    /// 録画をゴミ箱へ移動する (管理者ログイン必須、成功は 204)。
    /// ファイルや録画情報は消えず、一覧や検索から隠れるだけ。
    /// 録画中の番組と、すでにゴミ箱に入っている録画は 409 で拒否される。
    func moveToTrash(videoID: Int) async throws {
        let request = try request(forPath: "/api/recorder/trash/\(videoID)", method: "POST", authorized: true)
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    /// 録画をゴミ箱から復元する (管理者ログイン必須、成功は 204)。
    /// ゴミ箱に入っていない録画は 404 で拒否される。
    func restoreFromTrash(videoID: Int) async throws {
        let request = try request(
            forPath: "/api/recorder/trash/\(videoID)/restore", method: "POST", authorized: true)
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    /// 完全削除の事前確認を取る (管理者ログイン必須)。
    /// 管理元と削除対象の確認で、応答の確認用の合言葉は削除のときに使う。
    func fetchDeletePreview(videoID: Int) async throws -> RecordingDeletePreview {
        let request = try request(forPath: "/api/videos/\(videoID)/delete-preview", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(RecordingDeletePreview.self, from: data)
    }

    /// 録画を完全に削除する (管理者ログイン必須、成功は 204)。
    /// EPGStation が管理元の構成では、事前確認で受け取った合言葉を
    /// ヘッダーに付けないとサーバーが受け付けない (Web 版と同じ手順)。
    /// 戻り値は、Jellyfin の一覧更新が後回しになったかどうか
    /// (応答ヘッダー X-Recording-Sync が "JellyfinPending" のとき true)。
    func deleteVideo(videoID: Int, confirmationToken: String?) async throws -> Bool {
        var request = try request(forPath: "/api/videos/\(videoID)", method: "DELETE", authorized: true)
        if let confirmationToken {
            request.setValue(confirmationToken, forHTTPHeaderField: "X-Recording-Confirmation")
        }
        let (_, response) = try await session.data(for: request)
        try check(response)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.value(forHTTPHeaderField: "X-Recording-Sync") == "JellyfinPending"
    }

    // MARK: - 録画結果 (ローカル改造の口、拡張版だけが使う)

    /// 予約録画の結果の一覧を取る (新しい順)。
    /// サーバー側で予約・録画と照合して記録されているものが返る。
    func fetchRecordingResults() async throws -> [RecordingResult] {
        let request = try request(forPath: "/api/videos/recording-results")
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(RecordingResultsResponse.self, from: data).results
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

    // MARK: - 生放送の実況コメント

    /// 実況コメントの接続先情報を取る。ログインしていると、ニコニコ
    /// アカウントとの連携の状態に応じた接続先も一緒に返る。
    func fetchJikkyoWebSocketInfo(channelID: String) async throws -> JikkyoWebSocketInfo {
        let encoded = channelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? channelID
        let request = try request(forPath: "/api/channels/\(encoded)/jikkyo", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONDecoder().decode(JikkyoWebSocketInfo.self, from: data)
    }

    // MARK: - ニコニコアカウントとの連携

    /// ニコニコアカウントと連携するための認証用の URL を取る
    /// (ログイン必須)。認証情報はサーバー側が持つため、アプリは
    /// この URL をブラウザで開くだけで、認証情報には触れない。
    func fetchNiconicoAuthURL() async throws -> String {
        let request = try request(forPath: "/api/niconico/auth", authorized: true)
        let (data, response) = try await session.data(for: request)
        try check(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["authorization_url"] as? String else {
            throw APIError.invalidResponse
        }
        return url
    }

    /// ニコニコアカウントとの連携を解除する (ログイン必須)。
    func logoutNiconico() async throws {
        let request = try request(forPath: "/api/niconico/logout", method: "DELETE", authorized: true)
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    // MARK: - 録画再生 (HLS)

    // 画質名はここで実際にサーバーへ渡す形に直す (区分ごとの設定に応じて
    // "-hevc" や "-24fps" が付く)。プレイリストと keep-alive で同じ形を使う
    // 必要があるため、変換はこの3つの窓口に集約してある。
    // 区分 (profile) は再生を始めるときに決めたものを呼び出し側が渡す
    // (再生の途中で回線が変わっても画質は変えないため)。

    func playlistURL(videoID: Int, quality: String, profile: PlaybackProfile, sessionID: String) -> URL? {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .video, profile: profile)
        return url(forPath: "/api/streams/video/\(videoID)/\(apiQuality)/playlist?session_id=\(Self.escapedURLComponent(sessionID))")
    }

    /// 再生中、定期的に呼んでセッションを維持する (サーバー側の分割ファイル生成を止めないため)。
    func keepAlive(videoID: Int, quality: String, profile: PlaybackProfile, sessionID: String) async {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .video, profile: profile)
        guard let request = try? request(
            forPath: "/api/streams/video/\(videoID)/\(apiQuality)/keep-alive?session_id=\(Self.escapedURLComponent(sessionID))",
            method: "PUT"
        ) else { return }
        _ = try? await session.data(for: request)
    }

    // MARK: - 番組表

    /// 番組表を取る。Web 版と同じく、種別を絞って 4:00 起点の1日分ずつ取る。
    /// 日時はタイムゾーン付きの ISO 8601 で渡す (Web 版の送信形式と同じ)。
    /// ピン留め中のチャンネルの ID を渡したときは、種別より優先して
    /// そのチャンネルだけの番組表が返る (Web 版の送信形式と同じ)。
    func fetchTimeTable(start: Date, end: Date, channelType: String?,
                        pinnedChannelIDs: [String]? = nil) async throws -> TimeTableResponse {
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
        if let pinnedChannelIDs, !pinnedChannelIDs.isEmpty {
            path += "&pinned_channel_ids=\(escape(pinnedChannelIDs.joined(separator: ",")))"
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
        if case .backend(let backend) = await fetchServerBackendResult() {
            return backend
        }
        return nil
    }

    /// 土台確認の結果。「取れた (値つき)」と「取れなかった」を分ける。
    /// 通信の失敗と「EDCB でない」を取り違えないよう、呼び出し側で
    /// 案内を出し分けるときはこちらを使う。
    enum ServerBackendResult {
        case backend(String)
        case unavailable
    }

    /// サーバーの土台を取り、通信の失敗や読み解きの失敗は
    /// 「取れなかった」として返す (値が無いことと区別する)。
    func fetchServerBackendResult() async -> ServerBackendResult {
        guard let request = try? request(forPath: "/api/settings/server") else {
            return .unavailable
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let backend = try? JSONDecoder().decode(
                ServerBackendResponse.self, from: data).general.backend else {
            return .unavailable
        }
        return .backend(backend)
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
    /// 取れなかった場合は失敗として返す。アプリ内の既定値で代用すると、
    /// 利用者の設定と違う保存先・優先度・録画方式で予約が作られてしまう
    /// ため、呼び出し側は失敗したら予約自体を作らないこと。
    /// プリセットの一覧は取れたが id 0 が無い場合も、代用できる設定が
    /// 無いため失敗として扱う。
    func fetchDefaultRecordSettings() async throws -> RecordSettings {
        let request = try request(forPath: "/api/recording/presets")
        let (data, response) = try await session.data(for: request)
        try check(response)
        let presets = try JSONDecoder().decode(RecordSettingsPresetsResponse.self, from: data)
        guard let preset = presets.presets.first(where: { $0.id == 0 }) else {
            throw APIError.invalidResponse
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

    /// 番組を検索する (「次回を予約」の候補探しに使う)。
    /// 失敗したら、サーバーの応答をもとにした文で失敗を返す。
    func searchPrograms(condition: ProgramSearchCondition) async throws -> ProgramSearchResponse {
        var request = try request(forPath: "/api/programs/search", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(condition)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.programSearchFailureMessage(data: data))
        }
        return try JSONDecoder().decode(ProgramSearchResponse.self, from: data)
    }

    /// キーワード自動予約の条件の一覧を取る。
    func fetchReservationConditions() async throws -> ReservationConditionsResponse {
        let request = try request(forPath: "/api/recording/conditions")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationConditionFailureMessage(data: data, operation: .list))
        }
        return try JSONDecoder().decode(ReservationConditionsResponse.self, from: data)
    }

    /// キーワード自動予約の条件を追加する。
    func addReservationCondition(
        condition: ProgramSearchCondition, recordSettings: RecordSettings
    ) async throws {
        var request = try request(forPath: "/api/recording/conditions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ReservationConditionAddRequest(
                program_search_condition: condition, record_settings: recordSettings))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationConditionFailureMessage(data: data, operation: .add))
        }
    }

    /// キーワード自動予約の条件を削除する。
    /// 条件を消しても、その条件で作られた予約は残る (サーバー側の仕様)。
    func deleteReservationCondition(id: Int) async throws {
        let request = try request(forPath: "/api/recording/conditions/\(id)", method: "DELETE")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.message(Self.reservationConditionFailureMessage(data: data, operation: .delete))
        }
    }

    /// 番組検索の失敗応答を、Web 版と同じ日本語の文に直す。
    private static func programSearchFailureMessage(data: Data) -> String {
        if detailString(data: data) == "This API is only available when the backend is EDCB" {
            return "番組検索機能は EDCB バックエンド選択時のみ利用できます。"
        }
        return "番組情報の検索に失敗しました。"
    }

    private enum ReservationConditionOperation {
        case list, add, delete
    }

    /// キーワード自動予約の条件まわりの失敗応答を、Web 版と同じ
    /// 日本語の文に直す。
    private static func reservationConditionFailureMessage(
        data: Data, operation: ReservationConditionOperation
    ) -> String {
        let detail = detailString(data: data)
        if detail == "This API is only available when the backend is EDCB" {
            return "キーワード自動予約機能は EDCB バックエンド選択時のみ利用できます。"
        }
        switch operation {
        case .list:
            if detail == "Failed to get the list of reserve conditions" {
                return "キーワード自動予約条件一覧の取得に失敗しました。"
            }
            return "キーワード自動予約条件一覧を取得できませんでした。"
        case .add:
            if detail == "Failed to register the reserve condition" {
                return "キーワード自動予約条件の登録に失敗しました。"
            }
            return "キーワード自動予約条件の追加に失敗しました。"
        case .delete:
            switch detail {
            case "Specified reservation_condition_id was not found":
                return "指定されたキーワード自動予約条件が見つかりませんでした。"
            case "Failed to delete the specified reserve condition":
                return "キーワード自動予約条件の削除に失敗しました。"
            default:
                return "キーワード自動予約条件の削除に失敗しました。"
            }
        }
    }

    /// 失敗応答の JSON から detail の文を取り出す (取れなければ nil)。
    private static func detailString(data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary["detail"] as? String
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
        return url(forPath: "/api/streams/live/\(Self.escapedURLComponent(displayChannelID))/\(apiQuality)/mpegts")
    }

    /// データ放送の材料 (PSI/SI アーカイブデータ) の口。
    /// 映像とは別の流れで、番組情報とデータ放送の中身だけが届き続ける。
    func psiArchivedDataURL(displayChannelID: String, quality: String, profile: PlaybackProfile) -> URL? {
        let apiQuality = SettingsStore.shared.apiQuality(base: quality, media: .tv, profile: profile)
        return url(forPath: "/api/streams/live/\(Self.escapedURLComponent(displayChannelID))/\(apiQuality)/psi-archived-data")
    }

    // MARK: - AVPlayer 用

    /// 認証のヘッダーを付けた AVURLAsset を作る (プレイリストと分割ファイルの両方に同じヘッダーが付く)。
    /// 中継が必須の方式で中継の用意ができていない場合は nil を返す
    /// (中継なしで始めても認証を通せないため。呼び出し側で失敗として
    /// 知らせ、やり直せるようにする)。
    func playerAsset(url: URL) -> AVURLAsset? {
        // Digest認証とクライアント証明書は、サーバーからの求めへの
        // 応答が要るため、AVPlayer 単独では通せない。アプリ内の
        // 中継経由にすると、中継側の通信が求めに応答する
        // (中継側の relayURL は、用意ができるまで少し待つ。起動直後の
        // 最初の再生で中継なしに始めて認証が通らず失敗するのを避ける
        // ため)。
        // URLパラメータ (合言葉) も同じく中継経由にする。プレイリストの
        // URL に付けても、中の分割ファイルの URL には付かないため、
        // 中継側で取り分ごとに付け直す必要がある。
        if SettingsStore.shared.avPlaybackRequiresRelay {
            guard let relayed = StreamRelayServer.shared.relayURL(for: url) else { return nil }
            return AVURLAsset(url: relayed)
        }
        return AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": SettingsStore.shared.serverAuthHeaders,
        ])
    }
}

/// 利用者設定の保存 (サーバーの設定を丸ごと取ってきて、自分の項目だけ
/// 直して、丸ごと送り返すやり方) を、1つずつ順番に行うための受け口。
/// 視聴履歴の保存・各種設定の保存・番組表の設定の保存が重なると、
/// 後から送った方が古い控えを土台にしていて、先の変更を黙って
/// 上書きしてしまうため、保存どうしはここで直列に並べる。
actor ClientSettingsSaveQueue {
    static let shared = ClientSettingsSaveQueue()

    private var lastTask: Task<Void, Never>?

    /// 処理を順番待ちの最後に足し、その処理が終わるまで待つ。
    func run(_ operation: @escaping @Sendable () async -> Void) async {
        let previous = lastTask
        let task = Task {
            await previous?.value
            await operation()
        }
        lastTask = task
        await task.value
    }
}

/// 直列化した保存処理の結果 (真偽値) を受け渡すための箱。
final class BoolResultBox: @unchecked Sendable {
    var value = false
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

    /// 視聴履歴の番組 ID を、最後に見た順 (updated_at の新しい順) で返す。
    /// 視聴履歴の画面が一覧の元として使う (Web 版の視聴履歴と同じ並び)。
    /// 同期が効いていない・取得に失敗した場合は nil (呼び出し側で
    /// 案内や失敗の表示に分ける)。
    static func historyVideoIDs() async -> [Int]? {
        guard isEnabled else { return nil }
        let store = await WatchedHistoryStore.shared
        return await store.refreshedSnapshot()?.videoIDs
    }

    /// 視聴履歴から1件を外す。成功したら true。
    /// 手順は syncPosition と同じ「送る直前に最新を取得 → watched_history の
    /// 該当項目だけ外す → last_synced_at を今に更新して PUT」で、
    /// 422 が返ったら1回だけ取り直してやり直す。既に履歴に無い場合は
    /// 「消えた状態」として成功扱いにする。
    static func removeEntry(videoID: Int) async -> Bool {
        // 他の設定保存と重なって互いを上書きしないよう、保存の順番待ちに並ぶ。
        // 認証の世代は、並ぶ前の (操作が起きた) 時点で確定させる。
        // 実行が始まってから読むと、待ちの間にログインが切り替わった
        // ときに、前のログインの削除を次のログインの世代として扱い、
        // 次のログインへ書き込んでしまうため。同期の世代も同じ理由で、
        // 操作時点で確定させる (待ちの間や取得の間に同期を切られたら、
        // この削除は送らない)。
        let generation = SettingsStore.shared.authGeneration
        let syncGeneration = SettingsStore.shared.syncGeneration
        let box = BoolResultBox()
        await ClientSettingsSaveQueue.shared.run {
            box.value = await Self.removeEntrySerial(
                videoID: videoID, expectedGeneration: generation,
                expectedSyncGeneration: syncGeneration)
        }
        return box.value
    }

    private static func removeEntrySerial(
        videoID: Int, expectedGeneration: Int, expectedSyncGeneration: Int
    ) async -> Bool {
        guard isEnabled else { return false }
        // 順番待ちの間にログインが変わっていたら、前のログインの
        // 削除なので打ち切る。以後の照合も、操作時点の世代で行う。
        // 同期が切り替わっていた場合も打ち切る。
        let generation = expectedGeneration
        guard SettingsStore.shared.authGeneration == generation,
              SettingsStore.shared.syncGeneration == expectedSyncGeneration else { return false }
        for _ in 0..<2 {
            do {
                var settings = try await APIClient.shared.fetchClientSettings()
                guard SettingsStore.shared.authGeneration == generation,
                      SettingsStore.shared.syncGeneration == expectedSyncGeneration,
                      SettingsStore.shared.syncSettings,
                      SettingsStore.shared.isLoggedIn else { return false }
                // 履歴は生の配列のまま扱い、辞書の形の要素だけを
                // 対象にする (形の違う要素が1件あるだけで全体が
                // 空扱いになり、書き戻しで履歴が消えるのを防ぐ)。
                // 配列自体の形が違うときは、この回の書き込みをやめる。
                guard var history = rawHistoryArray(in: settings) else { return false }
                guard history.contains(where: {
                    (($0 as? [String: Any])?["video_id"] as? NSNumber)?.intValue == videoID
                }) else {
                    return true
                }
                history.removeAll {
                    (($0 as? [String: Any])?["video_id"] as? NSNumber)?.intValue == videoID
                }
                settings["watched_history"] = history
                settings["last_synced_at"] = Date().timeIntervalSince1970
                try await APIClient.shared.updateClientSettings(
                    settings, expectedAuthGeneration: generation)
                await WatchedHistoryStore.shared.invalidate(keepingSnapshot: true)
                return true
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch {
                return false
            }
        }
        return false
    }

    /// 視聴履歴に残っている前回の再生位置 (秒)。
    /// 同期が効いていない・履歴に無い・位置が取れない・取得に失敗した場合は nil
    /// (呼び出し側は今までの元データに落ちる)。
    static func lastPlaybackPosition(videoID: Int) async -> Double? {
        guard isEnabled else { return nil }
        // 読み取りの開始時点の認証と同期の状態を控え、応答が返って
        // きたときに照合する (historyVideoIDs と同じ理由。古い応答の
        // 位置が、切り替え後の再生位置に反映されないため)。
        let authGenerationAtStart = SettingsStore.shared.authGeneration
        let syncGenerationAtStart = SettingsStore.shared.syncGeneration
        guard let settings = try? await APIClient.shared.fetchClientSettings() else { return nil }
        guard isEnabled,
              SettingsStore.shared.authGeneration == authGenerationAtStart,
              SettingsStore.shared.syncGeneration == syncGenerationAtStart else { return nil }
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
        // 他の設定保存と重なって互いを上書きしないよう、保存の順番待ちに並ぶ。
        // 認証の世代は、並ぶ前の (操作が起きた) 時点で確定させる
        // (removeEntry と同じ理由)。同期の世代も同じく操作時点で
        // 確定させる (同期を切った後に、この更新が送られないため)。
        let generation = SettingsStore.shared.authGeneration
        let syncGeneration = SettingsStore.shared.syncGeneration
        await ClientSettingsSaveQueue.shared.run {
            await Self.syncPositionSerial(
                videoID: videoID, position: position, registerIfNeeded: registerIfNeeded,
                expectedGeneration: generation, expectedSyncGeneration: syncGeneration)
        }
    }

    private static func syncPositionSerial(
        videoID: Int, position: Double, registerIfNeeded: Bool, expectedGeneration: Int,
        expectedSyncGeneration: Int
    ) async {
        guard isEnabled else { return }
        // 順番待ちの間にログインが変わっていたら、前のログインの
        // 更新なので打ち切る。以後の照合も、操作時点の世代で行う。
        // 同期が切り替わっていた場合も打ち切る。
        let generation = expectedGeneration
        guard SettingsStore.shared.authGeneration == generation,
              SettingsStore.shared.syncGeneration == expectedSyncGeneration else { return }
        // 1回だけやり直す (初回 + 再試行1回)。
        for _ in 0..<2 {
            do {
                var settings = try await APIClient.shared.fetchClientSettings()
                guard SettingsStore.shared.authGeneration == generation,
                      SettingsStore.shared.syncGeneration == expectedSyncGeneration,
                      SettingsStore.shared.syncSettings,
                      SettingsStore.shared.isLoggedIn else { return }
                // 履歴は生の配列のまま扱い、辞書の形の要素だけを
                // 対象にする (形の違う要素はそのまま残す)。
                // 配列自体の形が違うときは、この回の書き込みをやめる。
                guard var history = rawHistoryArray(in: settings) else { return }
                let now = Date().timeIntervalSince1970
                if let index = history.firstIndex(where: {
                    (($0 as? [String: Any])?["video_id"] as? NSNumber)?.intValue == videoID
                }), var entry = history[index] as? [String: Any] {
                    entry["last_playback_position"] = position
                    entry["updated_at"] = now
                    history[index] = entry
                } else if registerIfNeeded {
                    let maxCount = (settings["video_watched_history_max_count"] as? NSNumber)?.intValue
                        ?? defaultMaxCount
                    // 上限が 0 のときは追加しない (空の履歴に1件増えてしまう)。
                    guard maxCount > 0 else { return }
                    // 上限まで戻るよう、はみ出しの分だけ古いものから落とす
                    // (1件だけ落とすと、はみ出しが大きいときに上限へ戻らない)。
                    // 落とす対象は辞書の形の要素だけ (形の違う要素は残す)。
                    while history.count >= maxCount {
                        var oldestIndex: Int?
                        var oldestCreated = Double.greatestFiniteMagnitude
                        for i in history.indices {
                            guard let entry = history[i] as? [String: Any] else { continue }
                            let created = (entry["created_at"] as? NSNumber)?.doubleValue ?? 0
                            if created < oldestCreated {
                                oldestCreated = created
                                oldestIndex = i
                            }
                        }
                        guard let index = oldestIndex else { break }
                        history.remove(at: index)
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
                try await APIClient.shared.updateClientSettings(
                    settings, expectedAuthGeneration: generation)
                await WatchedHistoryStore.shared.invalidate(keepingSnapshot: true)
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

    /// 視聴履歴の生の配列。キーが無いときは空の配列、キーはあるが
    /// 配列の形でないときは nil (書き込みをやめる合図)。
    /// 読み取り専用の用途は historyArray のままでよいが、書き戻す
    /// 用途ではこちらを使い、辞書でない要素を落とさない。
    private static func rawHistoryArray(in settings: [String: Any]) -> [Any]? {
        guard let value = settings["watched_history"] else { return [] }
        return value as? [Any]
    }

    private static func entryIndex(in settings: [String: Any], videoID: Int) -> Int? {
        historyArray(in: settings).firstIndex(where: {
            ($0["video_id"] as? NSNumber)?.intValue == videoID
        })
    }
}
