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
        playing.markPlaying(success)
        playing.noteSeek(to: 100) // 開始後の失敗は今回の復旧対象にしない。
        precondition(playing.latestPosition == 50)
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
        print("FMP4 playback state tests passed")
    }
}
