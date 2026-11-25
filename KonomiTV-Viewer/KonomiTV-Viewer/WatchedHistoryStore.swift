import Foundation

extension Notification.Name {
    static let watchedHistoryDidChange = Notification.Name("WatchedHistoryDidChange")
    static let historyContextDidChange = Notification.Name("HistoryContextDidChange")
    static let mylistDidChange = Notification.Name("MylistDidChange")
}

/// PWA の最終再生位置。改造サーバーの最大到達位置 watched_ratio は扱わない。
struct WatchedHistorySnapshot: Equatable {
    struct Entry: Equatable {
        let videoID: Int
        let position: Double?
        let updatedAt: Double
    }

    let entries: [Int: Entry]
    let videoIDs: [Int]
    static let empty = WatchedHistorySnapshot(settings: [:])

    init(settings: [String: Any]) {
        var values: [Int: Entry] = [:]
        // 不正な要素が一つあっても、他の番組の履歴まで消さない。
        for raw in settings["watched_history"] as? [Any] ?? [] {
            guard let item = raw as? [String: Any],
                  let number = item["video_id"] as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue < Double(Int.max),
                  number.doubleValue.rounded(.towardZero) == number.doubleValue else { continue }
            let id = number.intValue
            let position = (item["last_playback_position"] as? NSNumber)?.doubleValue
            let timestamp = (item["updated_at"] as? NSNumber)?.doubleValue ?? 0
            let entry = Entry(videoID: id, position: position.flatMap { $0.isFinite ? $0 : nil },
                              updatedAt: timestamp.isFinite ? timestamp : 0)
            if let old = values[id], old.updatedAt > entry.updatedAt { continue }
            values[id] = entry
        }
        entries = values
        videoIDs = values.values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.videoID < $1.videoID : $0.updatedAt > $1.updatedAt
        }.map(\.videoID)
    }

    func ratio(videoID: Int, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0,
              let position = entries[videoID]?.position else { return nil }
        // 割り算前に端を判定し、極小の尺でもオーバーフローを起こさない。
        if position <= 0 { return 0 }
        if position >= duration { return 1 }
        return position / duration
    }
}

/// 表示用の一括履歴キャッシュ。保存処理の「直前の GET → PUT」は置き換えない。
@MainActor
final class WatchedHistoryStore {
    struct Context: Equatable {
        let auth: Int
        let sync: Int
        let configuration: Int
        let baseURL: String?
        let enabled: Bool

        static var current: Context {
            let store = SettingsStore.shared
            return Context(auth: store.authGeneration, sync: store.syncGeneration,
                           configuration: store.authConfigGeneration,
                           baseURL: store.baseURL?.absoluteString,
                           enabled: store.isLoggedIn && store.syncSettings)
        }
    }

    static let shared = WatchedHistoryStore()
    private let contextProvider: () -> Context
    private let fetch: () async throws -> [String: Any]
    private var context: Context
    private var snapshot = WatchedHistorySnapshot.empty
    private var revision = 0
    private var request: Task<Bool, Never>?
    private var lastRefresh: Date?
    private var contextObserver: NSObjectProtocol?
    private let consumers = NSHashTable<AnyObject>.weakObjects()
    private var timer: Timer?
    private var isActive = true

    init(contextProvider: @escaping () -> Context = { Context.current },
         fetch: @escaping () async throws -> [String: Any] = {
             try await APIClient.shared.fetchClientSettings()
         }) {
        self.contextProvider = contextProvider
        self.fetch = fetch
        context = contextProvider()
        contextObserver = NotificationCenter.default.addObserver(
            forName: .historyContextDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.contextProvider() != self.context else { return }
                self.invalidate()
            }
        }
    }

    deinit {
        timer?.invalidate()
        request?.cancel()
        if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
    }

    var currentSnapshot: WatchedHistorySnapshot {
        // 通知が届く前のフレームでも、別利用者・別サーバーの履歴を返さない。
        contextProvider() == context && context.enabled ? snapshot : .empty
    }

    func observe(_ consumer: AnyObject) {
        consumers.add(consumer)
        startTimerIfNeeded()
        Task { await refresh() }
    }

    func stopObserving(_ consumer: AnyObject) {
        consumers.remove(consumer)
        if consumers.allObjects.isEmpty { stopTimer() }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            startTimerIfNeeded()
            if !consumers.allObjects.isEmpty { Task { await refresh(force: true) } }
        } else {
            stopTimer()
        }
    }

    private func startTimerIfNeeded() {
        guard isActive, timer == nil, !consumers.allObjects.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.consumers.allObjects.isEmpty { self.stopTimer(); return }
                await self.refresh(force: true)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 書き戻し成功時にも呼び、保存前に始まった古い読み取りを無効にする。
    func invalidate(keepingSnapshot: Bool = false) {
        revision += 1
        request?.cancel()
        request = nil
        let nextContext = contextProvider()
        if !keepingSnapshot || nextContext != context { snapshot = .empty }
        context = nextContext
        lastRefresh = nil
        NotificationCenter.default.post(name: .watchedHistoryDidChange, object: self)
        if isActive, !consumers.allObjects.isEmpty { Task { await refresh() } }
    }

    /// 最終 PUT と一覧表示が重なった場合は、無効化後の読み取りへ一度だけ合流する。
    /// 実際の通信失敗やアカウント変更を、成功した空履歴とは扱わない。
    func refreshedSnapshot() async -> WatchedHistorySnapshot? {
        let expected = contextProvider()
        guard expected.enabled else { return nil }
        for _ in 0..<2 {
            let version = revision
            let success = await refresh(force: true)
            guard contextProvider() == expected else { return nil }
            if success { return currentSnapshot }
            if revision == version { return nil }
        }
        return nil
    }

    @discardableResult
    func refresh(force: Bool = false) async -> Bool {
        if contextProvider() != context { invalidate() }
        guard context.enabled else { return true }
        if let request { return await request.value }
        // ホーム・各一覧が同時に要求した直後は、同じスナップショットを使う。
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 2 { return true }
        let expected = context
        let version = revision
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            do {
                let settings = try await self.fetch()
                guard !Task.isCancelled, self.revision == version,
                      self.contextProvider() == expected else { return false }
                self.snapshot = WatchedHistorySnapshot(settings: settings)
                self.lastRefresh = Date()
                self.request = nil
                NotificationCenter.default.post(name: .watchedHistoryDidChange, object: self)
                return true
            } catch {
                if self.revision == version { self.request = nil }
                return false
            }
        }
        request = task
        return await task.value
    }
}

/// 本家の数値入力(min=1、上限指定なし)へ合わせる。Intで表現できない値は送信しない。
enum WatchedHistoryLimitInput {
    static func parse(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let count = Int(value), count > 0 else { return nil }
        return count
    }
}

/// 新しい履歴を追加する直前だけ上限を適用する。設定の編集中・保存時は呼ばない。
enum WatchedHistoryRetention {
    static func preparingForInsertion(_ history: [Any], maximumCount: Int) -> [Any] {
        guard maximumCount > 0, history.count >= maximumCount else { return history }
        let candidates: [(index: Int, created: Double)] = history.enumerated().compactMap { item -> (index: Int, created: Double)? in
            let (index, raw) = item
            guard let entry = raw as? [String: Any] else { return nil }
            let created = (entry["created_at"] as? NSNumber)?.doubleValue ?? 0
            // 従来の最小値探索が選ばなかったNaN/+inf/最大有限値を、新たな削除対象にしない。
            guard created < Double.greatestFiniteMagnitude else { return nil }
            return (index, created)
        }.sorted {
            $0.created == $1.created ? $0.index < $1.index : $0.created < $1.created
        }
        let removedCount = min(history.count - maximumCount + 1, candidates.count)
        let removed = Set(candidates.prefix(removedCount).map(\.index))
        // 元の順序と辞書以外の要素は保持し、最大1万件からの削減でも二重走査を繰り返さない。
        return history.enumerated().compactMap { removed.contains($0.offset) ? nil : $0.element }
    }
}
