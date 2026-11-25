import Foundation

@main
struct PlaybackLifecycleTests {
    static func main() {
        var health = PlaybackKeepAliveState<String>()
        health.start(context: "session-A-quality-A", isRecovery: false)
        let old = health.request(context: "session-A-quality-A")!
        precondition(health.request(context: "session-A-quality-A") == nil)
        health.start(context: "session-A-quality-B", isRecovery: false)
        let newest = health.request(context: "session-A-quality-B")!
        precondition(health.complete(old, context: "session-A-quality-B", accepted: false, canRecover: true) == .ignored)
        precondition(health.request(context: "session-A-quality-B") == nil)
        precondition(health.complete(newest, context: "session-A-quality-B", accepted: true, canRecover: true) == .accepted)
        // 3回連続失敗。PiP中は既存ownerを保ち、復帰するまで作り直さない。
        for expected in [PlaybackKeepAliveState<String>.Result.failed, .failed, .deferred] {
            let request = health.request(context: "session-A-quality-B")!
            precondition(health.complete(request, context: "session-A-quality-B", accepted: false, canRecover: false) == expected)
        }
        precondition(!health.takeDeferredRecovery(context: "session-A-quality-B", canRecover: false))
        precondition(health.takeDeferredRecovery(context: "session-A-quality-B", canRecover: true))
        precondition(!health.takeDeferredRecovery(context: "session-A-quality-B", canRecover: true))
        health.start(context: "session-B-quality-B", isRecovery: true)
        for expected in [PlaybackKeepAliveState<String>.Result.failed, .failed, .disconnected, .failed] {
            let request = health.request(context: "session-B-quality-B")!
            precondition(health.complete(request, context: "session-B-quality-B", accepted: false, canRecover: true) == expected)
        }
        // 成功を挟むと連続失敗を数え直す。
        health.start(context: "session-C", isRecovery: false)
        for accepted in [false, false, true, false, false] {
            let request = health.request(context: "session-C")!
            let result = health.complete(request, context: "session-C", accepted: accepted, canRecover: true)
            precondition(result == (accepted ? .accepted : .failed))
        }
        let stopped = health.request(context: "session-C")!
        health.stop()
        precondition(health.complete(stopped, context: "session-C", accepted: false, canRecover: true) == .ignored)
        precondition(health.request(context: "session-C") == nil)
        // 認証contextが変わった応答も、新しいセッションの失敗へ加算しない。
        health.start(context: "auth-A", isRecovery: false)
        let authOld = health.request(context: "auth-A")!
        precondition(health.complete(authOld, context: "auth-B", accepted: false, canRecover: true) == .ignored)

        health.start(context: "visible-session", isRecovery: false)
        for expected in [PlaybackKeepAliveState<String>.Result.failed, .failed, .recover] {
            let request = health.request(context: "visible-session")!
            precondition(health.complete(request, context: "visible-session", accepted: false, canRecover: true) == expected)
        }

        var pending = PendingPlaybackSeek()
        var completions = [Int]()
        pending.replace(target: 10, completion: { completions.append(1) })
        pending.replace(target: 30, completion: { completions.append(2) })
        precondition(completions == [1])
        precondition(pending.target == 30)
        // ready通知はplayingだけでなくpausedでも同じtakeを使用する。
        let pausedReady = pending.take()!
        precondition(pausedReady.target == 30)
        pausedReady.completion?()
        precondition(pending.take() == nil)
        precondition(completions == [1, 2])
        pending.replace(target: 50, completion: { completions.append(3) })
        pending.cancel()
        pending.cancel()
        precondition(pending.target == nil && completions == [1, 2, 3])
        print("Playback lifecycle tests passed")
    }
}
