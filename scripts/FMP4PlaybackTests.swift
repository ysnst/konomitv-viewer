import Foundation

@main
struct FMP4PlaybackTests {
    static func main() {
        precondition(FMP4PlaybackState.route(playlist: nil) == .vlc)
        precondition(FMP4PlaybackState.route(playlist: "#EXTM3U\n#EXTINF:6,\n0.ts") == .vlc)
        precondition(FMP4PlaybackState.route(playlist: "#EXTM3U\n# comment EXT-X-MAP\n") == .vlc)
        precondition(FMP4PlaybackState.route(playlist: "#EXTM3U\r\n#EXT-X-MAP:URI=\"init.mp4\"\r\n") == .avPlayer)
        // 先頭0秒と途中再生で、同じく一度だけretry→fallbackへ進む。
        for initial in [0.0, 900.0] {
            var state = FMP4PlaybackState(position: initial)
            let first = state.makeAttempt()
            precondition(state.latestPosition == initial)
            precondition(state.failed(first) == .retry)
            precondition(state.failed(first) == .ignored) // 同じfailed通知で3秒待ちを飛ばさない。
            precondition(state.isWaiting(after: first))
            precondition(state.claimRecovery(canReplace: false) == nil) // PiP/非表示のownerを壊さない。
            precondition(state.awaitingRecovery)
            state.noteSeek(to: 1200) // readyでPendingPlaybackSeekを消費済みでも保持する。
            precondition(state.latestPosition == 1200)
            precondition(state.claimRecovery(canReplace: true) == .retry)
            precondition(state.claimRecovery(canReplace: true) == nil)
            let second = state.makeAttempt()
            precondition(!state.accepts(first) && state.accepts(second))
            precondition(state.failed(first) == .ignored)
            precondition(state.failed(second) == .fallback)
            precondition(state.failed(second) == .ignored)
            precondition(state.claimRecovery(canReplace: false) == nil)
            precondition(state.claimRecovery(canReplace: true) == .fallback)
            precondition(state.claimRecovery(canReplace: true) == nil)
        }
        var playing = FMP4PlaybackState(position: 50)
        let success = playing.makeAttempt()
        precondition(playing.observeStartup(success, position: 50, now: 0, canMonitor: true) == 12)
        _ = playing.observeStartup(success, position: 52.01, now: 3, canMonitor: true)
        precondition(playing.didPlay)
        playing.noteSeek(to: 100) // 開始後の失敗は今回の復旧対象にしない。
        precondition(playing.latestPosition == 52.01)
        precondition(playing.failed(success) == .ignored)
        precondition(!playing.awaitingRecovery)

        // probe中の操作はcontext作成前にPendingPlaybackSeekへ入り、readyで消費される。
        var pending = PendingPlaybackSeek()
        pending.replace(target: 345, completion: nil)
        var probed = FMP4PlaybackState(position: 0)
        probed.noteSeek(to: pending.target ?? 0) // 実際のAV項目の開始位置でseedする。
        let probedAttempt = probed.makeAttempt()
        precondition(pending.take()?.target == 345)
        precondition(probed.failed(probedAttempt) == .retry)
        precondition(probed.latestPosition == 345)
        precondition(probed.claimRecovery(canReplace: true) == .retry)
        probed.deferClaimedRecovery(.retry) // relay待機中にPiPが開始した場合。
        precondition(probed.claimRecovery(canReplace: false) == nil)
        precondition(probed.claimRecovery(canReplace: true) == .retry)
        precondition(probed.claimRecovery(canReplace: true) == nil)
        let retryAttempt = probed.makeAttempt()
        precondition(probed.failed(retryAttempt) == .fallback)
        precondition(probed.claimRecovery(canReplace: true) == .fallback)
        probed.deferClaimedRecovery(.fallback)
        precondition(probed.claimRecovery(canReplace: false) == nil)
        precondition(probed.claimRecovery(canReplace: true) == .fallback)
        precondition(probed.latestPosition == 345)

        // 解決完了後のretryも同じtokenで照合し、stop/新開始/認証変更で無効化する。
        var gate = PlaybackStartState<String>()
        let request = gate.begin(context: "auth-A")
        gate.pauseRequested = true
        precondition(gate.complete(request, context: "auth-A"))
        precondition(!gate.inFlight && gate.pauseRequested)
        precondition(gate.isCurrent(request, context: "auth-A"))
        precondition(!gate.isCurrent(request, context: "auth-B"))
        precondition(!gate.complete(request, context: "auth-A"))
        gate.invalidate()
        precondition(!gate.isCurrent(request, context: "auth-A"))
        let oldProbe = gate.begin(context: "auth-A")
        let newProbe = gate.begin(context: "auth-A")
        precondition(!gate.isCurrent(oldProbe, context: "auth-A"))
        precondition(gate.isCurrent(newProbe, context: "auth-A"))
        precondition(!gate.complete(oldProbe, context: "auth-A"))
        precondition(gate.inFlight)
        precondition(gate.complete(newProbe, context: "auth-A"))
        precondition(!gate.invalidateIfContextChanged(oldProbe, context: "auth-B"))
        precondition(gate.isCurrent(newProbe, context: "auth-A"))
        precondition(gate.invalidateIfContextChanged(newProbe, context: "auth-B"))
        precondition(!gate.inFlight && !gate.isCurrent(newProbe, context: "auth-A"))
        startupProgressTests()
        startupBudgetTests()
        startupSeekTests()
        print("FMP4 playback state tests passed")
    }
    static func startupProgressTests() {
        for initial in [0.0, 900.0] {
            var state = FMP4PlaybackState(position: initial)
            let attempt = state.makeAttempt()
            // playing通知の有無によらず、実時計が止まっていれば未確定のまま。
            precondition(state.observeStartup(attempt, position: initial, now: 0, canMonitor: true) == 12)
            precondition(state.observeStartup(attempt, position: initial, now: 8, canMonitor: true) == 4)
            precondition(!state.didPlay)
            _ = state.observeStartup(attempt, position: initial + 2, now: 9, canMonitor: true)
            precondition(!state.didPlay) // 上流と同じく2秒「超」を要求する。
            precondition(state.observeStartup(attempt, position: initial + 2.001, now: 9.1, canMonitor: true) == nil)
            precondition(state.didPlay)
            precondition(state.failed(attempt) == .ignored)
            precondition(state.beginSeek(to: 0) == nil) // 成功後の通常seekで開始監視へ戻さない。
            precondition(state.observeStartup(attempt, position: 0, now: 10000, canMonitor: true) == nil)
        }
        var invalid = FMP4PlaybackState(position: .nan)
        let attempt = invalid.makeAttempt()
        precondition(invalid.latestPosition == 0)
        precondition(invalid.observeStartup(attempt, position: .infinity, now: 0, canMonitor: true) == 12)
        precondition(invalid.observeStartup(attempt, position: 10, now: .nan, canMonitor: true) == nil)
        precondition(!invalid.didPlay && invalid.latestPosition == 0)
        precondition(invalid.beginSeek(to: .infinity) == nil)
    }

    static func startupBudgetTests() {
        // canMonitor=falseは明示停止/scrub/PiP/非表示/非アクティブの共通境界。
        // 11秒で停止し、長時間後に再開しても残り1秒だけを監視する。
        var state = FMP4PlaybackState(position: 10)
        let first = state.makeAttempt()
        precondition(state.observeStartup(first, position: 10, now: 0, canMonitor: true) == 12)
        precondition(state.observeStartup(first, position: 10, now: 11, canMonitor: false) == nil)
        precondition(state.observeStartup(first, position: 10, now: 1000, canMonitor: false) == nil)
        precondition(state.observeStartup(first, position: 10, now: 1000, canMonitor: true) == 1)
        precondition(state.observeStartup(first, position: 10, now: 1001, canMonitor: true) == 0)
        // timeoutと項目failedが競合しても、待機再試行は一度だけ。
        precondition(state.failed(first) == .retry)
        precondition(state.failed(first) == .ignored)
        precondition(state.claimRecovery(canReplace: false) == nil)
        precondition(state.claimRecovery(canReplace: true) == .retry)
        let retry = state.makeAttempt()
        precondition(state.observeStartup(first, position: 100, now: 1001, canMonitor: true) == nil)
        precondition(state.observeStartup(retry, position: 10, now: 1001, canMonitor: true) == 12)
        // bufferingでも再生意図が有効なら、時計の進行なしで期限へ達する。
        precondition(state.observeStartup(retry, position: 10, now: 1013, canMonitor: true) == 0)
        precondition(state.failed(retry) == .fallback)
        precondition(state.failed(first) == .ignored && state.failed(retry) == .ignored)
        precondition(state.claimRecovery(canReplace: false) == nil)
        precondition(state.claimRecovery(canReplace: true) == .fallback)
        precondition(state.claimRecovery(canReplace: true) == nil)

        // 停止中の発火相当では復旧せず、再開したときに残り時間を予約し直せる。
        var paused = FMP4PlaybackState(position: 0)
        let attempt = paused.makeAttempt()
        _ = paused.observeStartup(attempt, position: 0, now: 0, canMonitor: true)
        _ = paused.observeStartup(attempt, position: 0, now: 5, canMonitor: false)
        precondition(paused.observeStartup(attempt, position: 0, now: 12, canMonitor: false) == nil)
        precondition(paused.observeStartup(attempt, position: 0, now: 100, canMonitor: true) == 7)
        _ = paused.observeStartup(attempt, position: 0, now: 102, canMonitor: false)
        precondition(paused.observeStartup(attempt, position: 0, now: 200, canMonitor: true) == 5)
    }

    static func startupSeekTests() {
        var state = FMP4PlaybackState(position: 10)
        let attempt = state.makeAttempt()
        _ = state.observeStartup(attempt, position: 10, now: 0, canMonitor: true)
        _ = state.observeStartup(attempt, position: 10, now: 11, canMonitor: true)
        let forward = state.beginSeek(to: 900)!
        precondition(state.observeStartup(attempt, position: 900, now: 12, canMonitor: true) == nil)
        precondition(!state.didPlay)
        let backward = state.beginSeek(to: 100)!
        precondition(!state.completeSeek(forward, position: 900, now: 20))
        precondition(state.latestPosition == 100)
        precondition(state.observeStartup(attempt, position: 900, now: 200, canMonitor: true) == nil)
        precondition(state.completeSeek(backward, position: 99.5, now: 200))
        precondition(!state.completeSeek(backward, position: 900, now: 200))
        precondition(state.observeStartup(attempt, position: 99.5, now: 200, canMonitor: true) == 12)
        _ = state.observeStartup(attempt, position: 101.5, now: 202, canMonitor: true)
        precondition(!state.didPlay)
        _ = state.observeStartup(attempt, position: 101.6, now: 202.1, canMonitor: true)
        precondition(state.didPlay)

        // 初期seek中は成功を誤認しないが、開始待機そのものは有界にする。
        var initial = FMP4PlaybackState(position: 900)
        let first = initial.makeAttempt()
        let seek = initial.beginSeek(to: 900, initial: true)!
        precondition(initial.observeStartup(first, position: 0, now: 0, canMonitor: true) == 12)
        precondition(initial.observeStartup(first, position: 950, now: 11, canMonitor: true) == 1)
        precondition(!initial.didPlay)
        precondition(initial.completeSeek(seek, position: 900, now: 11))
        precondition(initial.observeStartup(first, position: 900, now: 12, canMonitor: true) == 0)
        precondition(initial.failed(first) == .retry)
        precondition(initial.latestPosition == 900)
        precondition(initial.claimRecovery(canReplace: true) == .retry)
        let second = initial.makeAttempt()
        precondition(!initial.completeSeek(seek, position: 0, now: 12))
        precondition(initial.observeStartup(second, position: 900, now: 12, canMonitor: true) == 12)
        precondition(initial.latestPosition == 900)

        // 失敗した最新seekは実位置0で要求900を上書きせず、停止/PiP中には復旧しない。
        for isInitial in [false, true] {
            var failedSeek = FMP4PlaybackState(position: 50)
            let attempt = failedSeek.makeAttempt()
            let stale = failedSeek.beginSeek(to: 100, initial: isInitial)!
            let latest = failedSeek.beginSeek(to: 900, initial: isInitial)!
            precondition(!failedSeek.completeSeek(stale, completed: false, position: 0, now: 1))
            precondition(failedSeek.completeSeek(latest, completed: false, position: 0, now: 2))
            precondition(failedSeek.latestPosition == 900)
            precondition(failedSeek.observeStartup(attempt, position: 1000, now: 3, canMonitor: false) == nil)
            precondition(failedSeek.observeStartup(attempt, position: 1000, now: 4, canMonitor: true) == 0)
            precondition(!failedSeek.didPlay && failedSeek.latestPosition == 900)
            precondition(failedSeek.failed(attempt) == .retry)
            precondition(failedSeek.claimRecovery(canReplace: false) == nil) // scrub中のretry到着。
            precondition(failedSeek.claimRecovery(canReplace: true) == .retry) // 操作終了後に再評価。
            let next = failedSeek.makeAttempt()
            precondition(failedSeek.observeStartup(next, position: 900, now: 5, canMonitor: true) == 12)
            precondition(!failedSeek.completeSeek(latest, completed: true, position: 0, now: 6))
            precondition(failedSeek.latestPosition == 900)
        }

        // ready前に位置変更が保留されても、項目の準備停止を無期限に待たない。
        var notReady = FMP4PlaybackState(position: 900)
        let notReadyAttempt = notReady.makeAttempt()
        notReady.noteSeek(to: 100)
        _ = notReady.observeStartup(notReadyAttempt, position: 950, now: 0, canMonitor: true, canConfirmProgress: false)
        precondition(notReady.observeStartup(notReadyAttempt, position: 950, now: 12, canMonitor: true, canConfirmProgress: false) == 0)
        precondition(!notReady.didPlay && notReady.latestPosition == 100)
        precondition(notReady.failed(notReadyAttempt) == .retry)

        // 未完了の初期seekでも12秒後に回復可能。取得データや字幕タイムラインはこの状態へ含めない。
        var stuck = FMP4PlaybackState(position: 50)
        let stuckAttempt = stuck.makeAttempt()
        _ = stuck.beginSeek(to: 50, initial: true)
        _ = stuck.observeStartup(stuckAttempt, position: 0, now: 0, canMonitor: true)
        precondition(stuck.observeStartup(stuckAttempt, position: 0, now: 12, canMonitor: true) == 0)
        precondition(stuck.failed(stuckAttempt) == .retry)
        precondition(stuck.latestPosition == 50)
    }

}
