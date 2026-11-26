import Foundation

/// 実中継が参照する設定の供給だけを担当する。URL生成・中継・HTTP処理は本番コードを使う。
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()
    private let lock = NSLock()
    private var base: URL?
    private var headers: [String: String] = [:]
    private var generation = 0
    var baseURL: URL? { lock.lock(); defer { lock.unlock() }; return base }
    var serverAuthHeaders: [String: String] { lock.lock(); defer { lock.unlock() }; return headers }
    var authConfigGeneration: Int { lock.lock(); defer { lock.unlock() }; return generation }
    let isLoggedIn = false
    let accessToken = ""
    func configure(base: URL, headers: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        self.base = base
        self.headers = headers
        generation += 1
    }
    func urlByApplyingAuthParameter(to url: URL) -> URL { url }
}

enum ServerAuthChallengeResponder {
    static func respond(to challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // このfixtureはヘッダー認証だけ。実Digest/証明書認証の成功とは扱わない。
        completionHandler(.performDefaultHandling, nil)
    }
}
