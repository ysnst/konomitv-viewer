import Foundation

@main
struct PlaybackStartTests {
    static func main() {
        var state = PlaybackStartState<String>()
        let first = state.begin(context: "server-A")
        state.pauseRequested = true
        precondition(state.complete(first, context: "server-A"))
        precondition(state.pauseRequested && !state.inFlight)
        // 完了済み通知を重ねて適用しない。
        precondition(!state.complete(first, context: "server-A"))

        let old = state.begin(context: "server-A")
        let newest = state.begin(context: "server-A")
        state.pauseRequested = true
        precondition(!state.complete(old, context: "server-A"))
        precondition(state.inFlight && state.pauseRequested)
        precondition(state.complete(newest, context: "server-A"))
        precondition(state.pauseRequested)

        let stopped = state.begin(context: "server-A")
        state.invalidate()
        precondition(!state.complete(stopped, context: "server-A"))
        precondition(!state.inFlight && !state.pauseRequested)

        let changed = state.begin(context: "server-A")
        precondition(!state.complete(changed, context: "server-B"))
        precondition(!state.inFlight)
        let resumed = state.begin(context: "server-B")
        state.pauseRequested = true
        state.pauseRequested = false // 開始待ち中に明示的な再生操作を受けた場合。
        precondition(state.complete(resumed, context: "server-B"))
        precondition(!state.pauseRequested)
        let toggled = state.begin(context: "server-B")
        precondition(state.togglePauseWhilePending() == false)
        precondition(state.pauseRequested && state.inFlight)
        precondition(state.togglePauseWhilePending() == true)
        precondition(!state.pauseRequested && state.inFlight)
        precondition(state.togglePauseWhilePending() == false)
        precondition(state.complete(toggled, context: "server-B"))
        precondition(state.pauseRequested)
        precondition(state.togglePauseWhilePending() == nil)
        print("Playback start state tests passed")
    }
}
