import Foundation

// 純粋な履歴処理と非同期競合を macOS 上で実行するための境界。
// 本番ストアへ注入した通信だけを制御し、UIKit や実サーバーの動作とは区別する。
final class SettingsStore {
    static let shared = SettingsStore()
    var authGeneration = 0
    var syncGeneration = 0
    var authConfigGeneration = 0
    var baseURL: URL? = nil
    var isLoggedIn = false
    var syncSettings = false
}

final class APIClient {
    static let shared = APIClient()
    func fetchClientSettings() async throws -> [String: Any] { [:] }
}

@main
struct HistoryStoreTests {
    @MainActor
    static func main() async {
        func settings(_ position: Double, updated: Double = 1) -> [String: Any] {
            ["watched_history": [["video_id": 1, "last_playback_position": position,
                                  "updated_at": updated]]]
        }
        let snapshot = WatchedHistorySnapshot(settings: settings(20))
        precondition(snapshot.ratio(videoID: 1, duration: 100) == 0.2)
        precondition(snapshot.ratio(videoID: 2, duration: 100) == nil)
        for duration in [0, -1, Double.nan, .infinity] {
            precondition(snapshot.ratio(videoID: 1, duration: duration) == nil)
        }
        for position in [-1.0, 0] {
            precondition(WatchedHistorySnapshot(settings: settings(position)).ratio(videoID: 1, duration: 100) == 0)
        }
        precondition(WatchedHistorySnapshot(settings: settings(200)).ratio(videoID: 1, duration: 100) == 1)
        for position in [Double.nan, .infinity] {
            precondition(WatchedHistorySnapshot(settings: settings(position)).ratio(videoID: 1, duration: 100) == nil)
        }
        let mixed = WatchedHistorySnapshot(settings: ["watched_history": [
            "bad", ["video_id": 1, "last_playback_position": 80, "updated_at": 1],
            ["video_id": 1, "last_playback_position": 20, "updated_at": 2],
            ["video_id": 2, "last_playback_position": 5, "updated_at": 3],
        ]])
        precondition(mixed.videoIDs == [2, 1])
        precondition(mixed.ratio(videoID: 1, duration: 100) == 0.2)

        var scope = WatchedHistoryStore.Context(auth: 1, sync: 1, configuration: 1,
                                               baseURL: "https://a.example", enabled: true)
        var calls = 0
        var pending: [CheckedContinuation<[String: Any], Error>] = []
        let store = WatchedHistoryStore(contextProvider: { scope }, fetch: {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        })
        func waitFor(_ count: Int) async {
            for _ in 0..<10000 {
                if pending.count >= count { return }
                await Task.yield()
            }
            preconditionFailure("Request did not reach the controlled transport")
        }
        let first = Task { await store.refresh(force: true) }
        await waitFor(1)
        let second = Task { await store.refresh(force: true) }
        for _ in 0..<10 { await Task.yield() }
        precondition(calls == 1, "Concurrent reads must share one request")
        pending[0].resume(returning: settings(20))
        let firstOK = await first.value
        let secondOK = await second.value
        precondition(firstOK && secondOK)

        // 保存成功等による無効化後は、遅い旧応答が新しい位置を上書きしない。
        let stale = Task { await store.refresh(force: true) }
        await waitFor(2)
        store.invalidate()
        let fresh = Task { await store.refresh(force: true) }
        await waitFor(3)
        pending[2].resume(returning: settings(10, updated: 3))
        let freshOK = await fresh.value
        precondition(freshOK)
        pending[1].resume(returning: settings(90, updated: 2))
        let staleOK = await stale.value
        precondition(!staleOK)
        precondition(store.currentSnapshot.ratio(videoID: 1, duration: 100) == 0.1)

        // 同じ URL へ戻っても世代が進んでいれば旧サーバーの応答を受け付けない。
        let oldContext = Task { await store.refresh(force: true) }
        await waitFor(4)
        scope = .init(auth: 2, sync: 3, configuration: 4, baseURL: "https://a.example", enabled: true)
        precondition(store.currentSnapshot.videoIDs.isEmpty)
        store.invalidate()
        pending[3].resume(returning: settings(80))
        let oldContextOK = await oldContext.value
        precondition(!oldContextOK)

        // 通信失敗のタスクを使い回さず、次の更新で再試行する。
        let failed = Task { await store.refresh(force: true) }
        await waitFor(5)
        pending[4].resume(throwing: NSError(domain: "HistoryTest", code: 1))
        let failedOK = await failed.value
        precondition(!failedOK)
        let retry = Task { await store.refresh(force: true) }
        await waitFor(6)
        pending[5].resume(returning: [:])
        let retryOK = await retry.value
        precondition(retryOK && store.currentSnapshot.videoIDs.isEmpty)

        let historyList = Task { await store.refreshedSnapshot() }
        await waitFor(7)
        store.invalidate(keepingSnapshot: true)
        pending[6].resume(returning: settings(80))
        await waitFor(8)
        pending[7].resume(returning: settings(25))
        let listSnapshot = await historyList.value
        precondition(listSnapshot?.videoIDs == [1])
        precondition(listSnapshot?.ratio(videoID: 1, duration: 100) == 0.25)

        scope = .init(auth: 2, sync: 4, configuration: 4, baseURL: "https://a.example", enabled: false)
        let callsBefore = calls
        let disabledOK = await store.refresh(force: true)
        precondition(disabledOK && calls == callsBefore && store.currentSnapshot.videoIDs.isEmpty)
        let initial = WatchedHistoryStore.Context(auth: 1, sync: 1, configuration: 1,
                                                 baseURL: "https://a.example", enabled: true)
        let transitions = [
            WatchedHistoryStore.Context(auth: 2, sync: 1, configuration: 1, baseURL: initial.baseURL, enabled: true),
            WatchedHistoryStore.Context(auth: 1, sync: 2, configuration: 1, baseURL: initial.baseURL, enabled: true),
            WatchedHistoryStore.Context(auth: 1, sync: 1, configuration: 2, baseURL: initial.baseURL, enabled: true),
            WatchedHistoryStore.Context(auth: 1, sync: 1, configuration: 1, baseURL: "https://b.example", enabled: true),
            WatchedHistoryStore.Context(auth: 1, sync: 1, configuration: 1, baseURL: initial.baseURL, enabled: false),
        ]
        for transition in transitions {
            var context = initial
            let reader = WatchedHistoryStore(contextProvider: { context }, fetch: { settings(20) })
            let loaded = await reader.refresh()
            precondition(loaded && reader.currentSnapshot.videoIDs == [1])
            context = transition
            precondition(reader.currentSnapshot.videoIDs.isEmpty, "Context change must hide old history before notification")
        }
        print("HistoryStoreTests passed: ratios, invalid data, ordering, coalescing, stale responses, context changes, retry, disabled sync")
    }
}
