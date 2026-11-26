import Foundation

/// fMP4の開始前失敗だけを、一度の待機再試行→従来VLCへ限定する。
/// 接続/開始世代はPlaybackStartState、実AV項目の同一性は所有元で照合する。
struct FMP4PlaybackState {
    enum Route: Equatable { case avPlayer, vlc }
    enum Failure: Equatable { case ignored, retry, fallback }
    struct Attempt: Equatable { fileprivate let id: UInt64 }

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

    init(position: Double) { latestPosition = position.isFinite ? max(0, position) : 0 }

    mutating func makeAttempt() -> Attempt {
        nextID &+= 1
        let result = Attempt(id: nextID)
        attempt = result
        failureHandled = false
        awaitingRetry = false
        pendingRecovery = nil
        return result
    }

    func accepts(_ candidate: Attempt) -> Bool { attempt == candidate && !failureHandled }
    func isWaiting(after candidate: Attempt) -> Bool { attempt == candidate && awaitingRetry }

    mutating func noteSeek(to position: Double) {
        // readyで保留seekを取り出した後も、最初のplayingまで最新の指定位置を控える。
        if !didPlay, position.isFinite { latestPosition = max(0, position) }
    }

    mutating func markPlaying(_ candidate: Attempt) {
        guard accepts(candidate) else { return }
        didPlay = true
        awaitingRetry = false
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
        guard !retried else { pendingRecovery = .fallback; return .fallback }
        retried = true
        awaitingRetry = true
        pendingRecovery = .retry
        return .retry
    }
}
