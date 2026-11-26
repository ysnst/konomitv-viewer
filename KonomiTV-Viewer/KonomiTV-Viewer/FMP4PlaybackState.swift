import Foundation

/// fMP4の開始前失敗だけを、一度の待機再試行→従来VLCへ限定する。
/// 接続/開始世代はPlaybackStartState、実AV項目の同一性は所有元で照合する。
struct FMP4PlaybackState {
    enum Route: Equatable { case avPlayer, vlc }
    enum Failure: Equatable { case ignored, retry, fallback }
    struct Attempt: Equatable { fileprivate let id: UInt64 }
    struct Seek: Equatable { fileprivate let attempt: Attempt; fileprivate let id: UInt64 }

    // 本家a2de085の開始判定幅・待機時間。字幕の時刻補正には用いない。
    static let progressThreshold: TimeInterval = 2
    static let startupTimeout: TimeInterval = 12

    static func route(playlist: String?) -> Route {
        guard let playlist, playlist.split(whereSeparator: \.isNewline).contains(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#EXT-X-MAP:")
        }) else { return .vlc }
        return .avPlayer
    }

    private var nextID: UInt64 = 0
    private var attempt: Attempt?
    private var failureHandled = false
    private(set) var awaitingRetry = false
    private var pendingRecovery: Failure?
    var awaitingRecovery: Bool { pendingRecovery != nil }
    private(set) var didPlay = false
    private var retried = false
    private(set) var latestPosition: Double
    var currentAttempt: Attempt? { attempt }
    private var progressBaseline: Double = 0
    private var remainingStartupTime = FMP4PlaybackState.startupTimeout
    private var previousClock: TimeInterval?
    private var wasMonitoring = false
    private var nextSeekID: UInt64 = 0
    private var pendingSeek: Seek?
    private var initialSeekPending = false
    private var seekNeedsRecovery = false

    init(position: Double) { latestPosition = position.isFinite ? max(0, position) : 0 }

    mutating func makeAttempt() -> Attempt {
        nextID &+= 1
        let result = Attempt(id: nextID)
        attempt = result
        failureHandled = false
        awaitingRetry = false
        pendingRecovery = nil
        didPlay = false
        progressBaseline = latestPosition
        remainingStartupTime = Self.startupTimeout
        previousClock = nil
        wasMonitoring = false
        pendingSeek = nil
        initialSeekPending = false
        seekNeedsRecovery = false
        return result
    }

    func accepts(_ candidate: Attempt) -> Bool { attempt == candidate && !failureHandled }
    func isWaiting(after candidate: Attempt) -> Bool { attempt == candidate && awaitingRetry }

    mutating func noteSeek(to position: Double) {
        // readyで保留seekを取り出した後も、実際の進行確認まで最新の指定位置を控える。
        if !didPlay, position.isFinite { latestPosition = max(0, position) }
    }

    /// シークによる位置の飛びを、再生開始の進行と誤認しない。
    /// 初期の位置合わせは監視時間に含めるが、後続操作の完了待ちは時間を消費しない。
    mutating func beginSeek(to position: Double, initial: Bool = false) -> Seek? {
        guard !didPlay, position.isFinite, let attempt, accepts(attempt) else { return nil }
        nextSeekID &+= 1
        let token = Seek(attempt: attempt, id: nextSeekID)
        latestPosition = max(0, position)
        progressBaseline = latestPosition
        remainingStartupTime = Self.startupTimeout
        previousClock = nil
        wasMonitoring = false
        pendingSeek = token
        initialSeekPending = initial
        seekNeedsRecovery = false
        return token
    }

    @discardableResult
    mutating func completeSeek(_ token: Seek, completed: Bool = true, position: Double, now: TimeInterval) -> Bool {
        guard accepts(token.attempt), pendingSeek == token, !didPlay else { return false }
        consumeMonitoringTime(now: now)
        pendingSeek = nil
        initialSeekPending = false
        // 中断・失敗した移動先を現在の古い実位置で上書きしない。
        // 再生可能な状態へ戻った時点で、既存の有界な復旧へつなぐ。
        guard completed, position.isFinite, position >= 0 else {
            seekNeedsRecovery = true
            wasMonitoring = false
            return true
        }
        // 要求位置でなく、最新の完了で観測した実位置を進行判定の基準にする。
        latestPosition = position
        progressBaseline = latestPosition
        return true
    }

    /// 実時計だけで開始成功を決め、監視可能な残り時間を返す。
    /// playing通知だけでは呼び出し元もdidPlayを立てない。bufferingは監視時間に含める。
    mutating func observeStartup(_ candidate: Attempt, position: Double, now: TimeInterval,
                                 canMonitor: Bool, canConfirmProgress: Bool = true) -> TimeInterval? {
        guard accepts(candidate), !didPlay, now.isFinite else { return nil }
        consumeMonitoringTime(now: now)
        wasMonitoring = canMonitor && (pendingSeek == nil || initialSeekPending)
        if seekNeedsRecovery { return canMonitor ? 0 : nil }
        if canMonitor, canConfirmProgress, pendingSeek == nil, position.isFinite, position >= 0 {
            latestPosition = position
            if position > progressBaseline + Self.progressThreshold {
                didPlay = true
                awaitingRetry = false
                wasMonitoring = false
                return nil
            }
        }
        return wasMonitoring ? remainingStartupTime : nil
    }

    private mutating func consumeMonitoringTime(now: TimeInterval) {
        guard now.isFinite else { return }
        if wasMonitoring, let previousClock {
            remainingStartupTime = max(0, remainingStartupTime - max(0, now - previousClock))
        }
        previousClock = now
    }

    /// PiPのowner/drawableを維持し、表示可能な復帰後に一度だけ置換を開始する。
    mutating func claimRecovery(canReplace: Bool) -> Failure? {
        guard canReplace, let action = pendingRecovery else { return nil }
        pendingRecovery = nil
        awaitingRetry = false
        return action
    }

    /// 中継待ちの間にPiPへ移った場合、回数を消費せず同じ置換を復帰後へ戻す。
    mutating func deferClaimedRecovery(_ action: Failure) {
        guard !didPlay, failureHandled, action != .ignored else { return }
        pendingRecovery = action
    }

    mutating func failed(_ candidate: Attempt) -> Failure {
        guard accepts(candidate), !didPlay else { return .ignored }
        failureHandled = true
        wasMonitoring = false
        previousClock = nil
        pendingSeek = nil
        guard !retried else { pendingRecovery = .fallback; return .fallback }
        retried = true
        awaitingRetry = true
        pendingRecovery = .retry
        return .retry
    }
}
