import Foundation

/// 中継URLの非同期解決を、再生開始・停止・認証設定の世代に結び付ける。
/// メインスレッドだけで使い、古い完了通知が新しい開始意図を変更しないようにする。
struct PlaybackStartState<Context: Equatable> {
    struct Request {
        fileprivate let generation: UInt64
        fileprivate let context: Context
    }

    private var generation: UInt64 = 0
    private(set) var inFlight = false
    var pauseRequested = false

    mutating func begin(context: Context) -> Request {
        generation &+= 1
        inFlight = true
        pauseRequested = false
        return Request(generation: generation, context: context)
    }

    /// 開始待ちのボタンは要求を作り直さず、同じ要求の再生意図だけを反転する。
    mutating func togglePauseWhilePending() -> Bool? {
        guard inFlight else { return nil }
        pauseRequested.toggle()
        return !pauseRequested
    }

    mutating func invalidate() {
        generation &+= 1
        inFlight = false
        pauseRequested = false
    }

    /// 解決完了後の項目再試行でも、停止・別の開始・認証変更で古い要求を識別する。
    func isCurrent(_ request: Request, context: Context) -> Bool {
        request.generation == generation && request.context == context
    }

    /// 同じ要求の認証変更だけを無効化する。遅着した旧世代から新しい開始を取り消さない。
    mutating func invalidateIfContextChanged(_ request: Request, context: Context) -> Bool {
        guard request.generation == generation, request.context != context else { return false }
        invalidate()
        return true
    }

    /// 同じ接続先・認証設定で最新の開始要求が返ったときだけ、開始待ちを解く。
    /// 古い通知では現在のpause意図もinFlightも触らない。
    mutating func complete(_ request: Request, context: Context) -> Bool {
        guard inFlight, request.generation == generation else { return false }
        guard request.context == context else {
            invalidate()
            return false
        }
        inFlight = false
        return true
    }
}
