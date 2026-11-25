import Foundation

/// セッション維持通信は一つずつ送り、古い再生・接続先の応答を現在の失敗へ加算しない。
struct PlaybackKeepAliveState<Context: Equatable> {
    struct Request {
        fileprivate let generation: UInt64
        fileprivate let context: Context
    }
    enum Result: Equatable { case ignored, accepted, failed, deferred, recover, disconnected }
    private var generation: UInt64 = 0
    private var context: Context?
    private var inFlight = false
    private var failures = 0
    private var recoveryAttempted = false
    private var disconnectedNotified = false
    private var recoveryDeferred = false

    mutating func start(context: Context, isRecovery: Bool) {
        generation &+= 1
        self.context = context
        inFlight = false
        failures = 0
        recoveryDeferred = false
        if !isRecovery { recoveryAttempted = false; disconnectedNotified = false }
    }

    mutating func stop() {
        generation &+= 1
        context = nil
        inFlight = false
        recoveryDeferred = false
    }

    mutating func request(context: Context) -> Request? {
        guard self.context == context, !inFlight else { return nil }
        inFlight = true
        return Request(generation: generation, context: context)
    }

    mutating func complete(_ request: Request, context: Context, accepted: Bool, canRecover: Bool) -> Result {
        guard inFlight, request.generation == generation, request.context == context,
              self.context == context else { return .ignored }
        inFlight = false
        if accepted {
            failures = 0
            recoveryDeferred = false
            return .accepted
        }
        failures += 1
        guard failures >= 3 else { return .failed }
        guard !recoveryAttempted else {
            guard !disconnectedNotified else { return .failed }
            disconnectedNotified = true
            return .disconnected
        }
        guard canRecover else { recoveryDeferred = true; return .deferred }
        recoveryAttempted = true
        return .recover
    }

    mutating func takeDeferredRecovery(context: Context, canRecover: Bool) -> Bool {
        guard self.context == context, recoveryDeferred, !recoveryAttempted, canRecover else { return false }
        recoveryDeferred = false
        recoveryAttempted = true
        return true
    }
}

/// 再生部品が準備できる前の移動は最新一件だけ保持する。
/// 置換・破棄された要求にも外部完了を一度返し、PiP等の呼び出し元を待たせない。
struct PendingPlaybackSeek {
    private(set) var target: Double?
    private var completion: (() -> Void)?

    mutating func replace(target: Double, completion: (() -> Void)?) {
        let old = self.completion
        self.target = target
        self.completion = completion
        old?()
    }

    mutating func take() -> (target: Double, completion: (() -> Void)?)? {
        guard let target else { return nil }
        let result = (target, completion)
        self.target = nil
        completion = nil
        return result
    }

    mutating func cancel() {
        let old = completion
        target = nil
        completion = nil
        old?()
    }
}

/// シーク直後の表示位置だけを補う。映像・字幕・履歴の時計には使用しない。
/// 本家af52の2秒以内/20秒上限を、実時計の巻戻りに影響されない単調時刻で判定する。
struct SeekDisplayState {
    private var target: Double?
    private var deadline: TimeInterval?

    mutating func begin(target: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard target.isFinite else { clear(); return }
        self.target = target
        deadline = now + 20
    }

    mutating func clear() {
        target = nil
        deadline = nil
    }

    mutating func activeTarget(realPosition: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        guard let target else { return nil }
        if (realPosition.isFinite && abs(realPosition - target) <= 2) || now >= (deadline ?? now) {
            clear()
            return nil
        }
        return target
    }
}
