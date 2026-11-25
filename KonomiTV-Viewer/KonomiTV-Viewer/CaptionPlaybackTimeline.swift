import Foundation

/// 字幕の取得済み範囲とシーク世代を管理する。字幕の待ち時間を推測するタイマーは使わない。
/// 範囲の穴では消去イベントを未取得の可能性があるため、穴より前の表示を持ち越さない。
struct CaptionPlaybackTimeline {
    private(set) var ranges: [Range<Double>] = []
    private(set) var generation: UInt64 = 0
    private(set) var isSeeking = false

    mutating func reset() {
        ranges.removeAll()
        generation &+= 1
        isSeeking = false
    }

    @discardableResult
    mutating func beginSeek() -> UInt64 {
        generation &+= 1
        isSeeking = true
        return generation
    }

    /// 古いシークの完了では、新しいシークの描画待機を解除しない。
    mutating func completeSeek(_ token: UInt64) -> Bool {
        guard token == generation, isSeeking else { return false }
        isSeeking = false
        return true
    }

    /// 完全に受け取った区間、またはシークを挟まない観測済み再生範囲だけを追加する。
    mutating func include(start: Double, end: Double) {
        guard start.isFinite, end.isFinite, start < end else { return }
        var lower = start
        var upper = end
        var merged: [Range<Double>] = []
        var inserted = false
        for range in ranges {
            if range.upperBound < lower {
                merged.append(range)
            } else if upper < range.lowerBound {
                if !inserted { merged.append(lower..<upper); inserted = true }
                merged.append(range)
            } else {
                lower = min(lower, range.lowerBound)
                upper = max(upper, range.upperBound)
            }
        }
        if !inserted { merged.append(lower..<upper) }
        ranges = merged
    }

    func replayStart(at position: Double, includingUpperBound: Bool = false) -> Double? {
        // HEVC segmentは半開区間。AVの観測済み時計だけは観測した終端も含めてよい。
        ranges.first { $0.contains(position) || (includingUpperBound && position == $0.upperBound) }?.lowerBound
    }

    /// 古い包みもデコーダーへは渡して管理データ/DRCSを復元するが、表示へは追加しない。
    static func shouldPresent(packetPosition: Double, replayStart: Double) -> Bool {
        packetPosition >= replayStart
    }
}

/// VLCKitはシーク完了の保管先が1つなので、同時に渡す要求を1つに制限する。
/// メインスレッドで使用し、待機中は最新の絶対位置だけを残す。通知は各要求へ一度返す。
final class CaptionSeekCoordinator {
    typealias Operation = (Double, @escaping () -> Void) -> Bool
    private struct Request {
        let id: UInt64
        let target: Double
        let operation: Operation
        let completion: (Bool) -> Void
    }
    private var nextID: UInt64 = 0
    private var epoch: UInt64 = 0
    private var active: Request?
    private var pending: Request?

    /// completionのfalseは、後続要求への置換/再生終了で失効したことを表す。
    /// 外部への完了通知は返すが、その要求によって字幕や再生を再開してはならない。
    func submit(target: Double, operation: @escaping Operation, completion: @escaping (Bool) -> Void) {
        nextID &+= 1
        let request = Request(id: nextID, target: target, operation: operation, completion: completion)
        if active != nil {
            let superseded = pending
            pending = request
            superseded?.completion(false)
        } else {
            start(request)
        }
    }

    /// 古いVLCのコールバックが届かなくても、PiP等の外部完了通知を残さない。
    func reset() {
        epoch &+= 1
        let cancelledActive = active
        let cancelledPending = pending
        active = nil
        pending = nil
        cancelledActive?.completion(false)
        cancelledPending?.completion(false)
    }

    private func start(_ request: Request) {
        active = request
        let requestEpoch = epoch
        let accepted = request.operation(request.target) { [weak self] in
            self?.finish(id: request.id, epoch: requestEpoch)
        }
        // 受付失敗やno-opで完了が呼ばれなくても、待機を解除する。
        if !accepted { finish(id: request.id, epoch: requestEpoch) }
    }

    private func finish(id: UInt64, epoch requestEpoch: UInt64) {
        guard requestEpoch == epoch, let finished = active, finished.id == id else { return }
        active = nil
        let next = pending
        pending = nil
        // 次を先に登録し、完了通知から再入された場合も同時実行しない。
        if let next { start(next) }
        finished.completion(true)
    }
}
