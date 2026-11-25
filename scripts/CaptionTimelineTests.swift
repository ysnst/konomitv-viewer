import Foundation

@main
struct CaptionTimelineTests {
    static func main() {
        var timeline = CaptionPlaybackTimeline()
        timeline.include(start: 0, end: 10)
        timeline.include(start: 20, end: 30)
        assert(timeline.replayStart(at: 5) == 0)
        assert(timeline.replayStart(at: 25) == 20)
        assert(timeline.replayStart(at: 15) == nil)
        assert(timeline.replayStart(at: 10) == nil)
        assert(timeline.replayStart(at: 10, includingUpperBound: true) == 0)
        assert(timeline.replayStart(at: 20) == 20)
        assert(timeline.replayStart(at: 30) == nil)
        // 未取得区間を挟んだ旧字幕を追加しない。移動先区間の字幕/消去は同じ順序で追加する。
        let positions: [Double] = [2, 8, 21, 23, 27]
        let start = timeline.replayStart(at: 25)!
        let appended = positions.filter { $0 <= 25 && CaptionPlaybackTimeline.shouldPresent(packetPosition: $0, replayStart: start) }
        assert(appended == [21, 23])
        // 後方シークで受信済み範囲に戻れば、その範囲の有効字幕が再び復元候補になる。
        let backwardStart = timeline.replayStart(at: 9)!
        assert(positions.filter { $0 <= 9 && CaptionPlaybackTimeline.shouldPresent(packetPosition: $0, replayStart: backwardStart) } == [2, 8])
        // 空のsegmentでも受信完了なら範囲がつながり、前区間から有効な字幕を持ち越せる。
        timeline.include(start: 10, end: 20)
        assert(timeline.ranges == [0.0..<30.0])
        assert(timeline.replayStart(at: 25) == 0)
        // 順不同/重複到着や、完全に内側の区間は範囲を壊さない。
        timeline.include(start: 12, end: 18)
        timeline.include(start: 40, end: 50)
        timeline.include(start: 30, end: 40)
        assert(timeline.ranges == [0.0..<50.0])
        timeline.include(start: .nan, end: 100)
        timeline.include(start: 5, end: .infinity)
        timeline.include(start: 10, end: 5)
        assert(timeline.ranges == [0.0..<50.0])
        // 時間差の閾値に依存せず、短い移動・一時停止中も同じ状態遷移を使う。
        let first = timeline.beginSeek()
        assert(timeline.isSeeking)
        let latest = timeline.beginSeek()
        assert(!timeline.completeSeek(first))
        assert(timeline.isSeeking)
        assert(timeline.completeSeek(latest))
        assert(!timeline.isSeeking)
        assert(!timeline.completeSeek(latest))
        let pending = timeline.beginSeek()
        timeline.reset()
        assert(!timeline.completeSeek(pending))
        assert(!timeline.isSeeking && timeline.ranges.isEmpty)
        testSerialSeeks()
        print("Caption timeline tests passed: seek generations, packet selection, ranges, serial VLC requests, coalescing, cancellation, and exactly-once completions")
    }

    static func testSerialSeeks() {
        let coordinator = CaptionSeekCoordinator()
        var clock = 0.0
        var operations: [(target: Double, offset: Double)] = []
        var callbacks: [Double: () -> Void] = [:]
        var notifications: [String: [Bool]] = [:]
        let operation: CaptionSeekCoordinator.Operation = { target, done in
            operations.append((target, target - clock))
            callbacks[target] = done
            return true
        }
        func submit(_ name: String, _ target: Double) {
            coordinator.submit(target: target, operation: operation) { resumed in
                notifications[name, default: []].append(resumed)
            }
        }
        submit("A", 10)
        submit("B", 20)
        submit("C", 30)
        assert(operations.map { $0.target } == [10])
        assert(notifications["B"] == [false])
        clock = 11
        callbacks[10]!()
        assert(operations.map { $0.target } == [10, 30])
        assert(operations[1].offset == 19)
        assert(notifications["A"] == [true])
        callbacks[10]!() // 重複/古い完了は最新要求を終わらせない。
        assert(notifications["C"] == nil)
        callbacks[30]!()
        assert(notifications["C"] == [true])
        submit("D", 40)
        submit("E", 50)
        coordinator.reset()
        assert(notifications["D"] == [false])
        assert(notifications["E"] == [false])
        submit("F", 60)
        callbacks[40]!() // reset前の完了を新しい再生へ適用しない。
        assert(notifications["F"] == nil)
        callbacks[60]!()
        assert(notifications["F"] == [true])
        var rejected = 0
        coordinator.submit(target: 60, operation: { _, _ in false }) { resumed in
            assert(resumed); rejected += 1
        }
        assert(rejected == 1)
        var synchronous = 0
        coordinator.submit(target: 70, operation: { _, done in done(); return false }) { resumed in
            assert(resumed); synchronous += 1
        }
        assert(synchronous == 1)
        coordinator.reset()
        assert(synchronous == 1)
    }

}
