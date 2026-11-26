// Objective-C の非Sendableオブジェクトは、以下の境界でメインキューへ集約して扱う。
@preconcurrency import AVKit
import UIKit
@preconcurrency import VLCKit

/// 同じ映像出力を標準 PiP へ渡す。再生・通信・履歴は元の画面が引き続き所有する。
/// VLCKit 4.0.0a26 の公開 drawable プロトコルと AVPlayerLayer の両経路に対応する。
@MainActor
final class PlaybackPiPController: NSObject, VLCDrawable, VLCPictureInPictureDrawable,
                                   VLCPictureInPictureMediaControlling, AVPictureInPictureControllerDelegate {
    private static weak var current: PlaybackPiPController?
    private static var retainedOwner: UIViewController?

    private weak var videoView: UIView?
    private let live: Bool
    private let timeProvider: () -> Double
    private let durationProvider: () -> Double
    private let playingProvider: () -> Bool
    private let playAction: () -> Void
    private let pauseAction: () -> Void
    private let seekAction: (Double, @escaping () -> Void) -> Void
    // VLC の描画側が所有する。こちらから強く循環保持しない。
    private weak var vlcWindow: (any VLCPictureInPictureWindowControlling)?
    private var avController: AVPictureInPictureController?
    private var possibleObserver: NSKeyValueObservation?
    private var startTimer: Timer?
    private var disposed = false
    private var rendererRetired = false
    private(set) var isActive = false
    private(set) var isPending = false

    var onStateChanged: (() -> Void)?
    var onError: ((String) -> Void)?
    var onRestoreInterface: (() -> Void)?
    var onSuperseded: (() -> Void)?

    var isReady: Bool {
        guard !disposed, !rendererRetired, AVPictureInPictureController.isPictureInPictureSupported() else { return false }
        if let avController { return avController.isPictureInPicturePossible }
        return vlcWindow != nil
    }

    init(videoView: UIView, isLive: Bool, currentTime: @escaping () -> Double,
         duration: @escaping () -> Double, isPlaying: @escaping () -> Bool,
         play: @escaping () -> Void, pause: @escaping () -> Void,
         seek: @escaping (Double, @escaping () -> Void) -> Void) {
        self.videoView = videoView
        live = isLive
        timeProvider = currentTime
        durationProvider = duration
        playingProvider = isPlaying
        playAction = play
        pauseAction = pause
        seekAction = seek
        super.init()
    }

    func configureAVPlayerLayer(_ layer: AVPlayerLayer) {
        guard !disposed, !isActive, !isPending,
              AVPictureInPictureController.isPictureInPictureSupported() else { return }
        vlcWindow?.stateChangeEventHandler = nil
        vlcWindow = nil
        possibleObserver = nil
        avController?.delegate = nil
        avController = AVPictureInPictureController(playerLayer: layer)
        avController?.delegate = self
        // 意図しないバックグラウンド移行で起動しない。専用ボタンから開始する。
        avController?.canStartPictureInPictureAutomaticallyFromInline = false
        possibleObserver = avController?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onStateChanged?() }
        }
        onStateChanged?()
    }

    /// 新しい番組の再生開始時に呼ぶ。古い PiP の所有者を残して二重再生しない。
    static func stopCurrentPlayback() {
        guard let old = current else { return }
        // 終了通知と所有元の stop 処理が再入しても、一度だけ処理する。
        current = nil
        let owner = retainedOwner
        retainedOwner = nil
        old.dispose()
        old.onSuperseded?()
        withExtendedLifetime(owner) {}
    }

    func start(owner: UIViewController) {
        guard isReady, !isActive, !isPending else { return }
        if Self.current !== self { Self.stopCurrentPlayback() }
        Self.current = self
        Self.retainedOwner = owner
        isPending = true
        onStateChanged?()
        // VLC は開始失敗 delegate を公開しないため、無反応を成功と扱わない。
        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPending, !self.isActive else { return }
                self.stop()
                self.onError?("PiP を開始できませんでした。通常再生を続けます。")
            }
        }
        if let avController { avController.startPictureInPicture() }
        else { vlcWindow?.startPictureInPicture() }
    }

    func stop() {
        let owner = Self.current === self ? Self.retainedOwner : nil
        defer { withExtendedLifetime(owner) {} }
        startTimer?.invalidate()
        startTimer = nil
        let wasPending = isPending
        isPending = false
        if let avController { avController.stopPictureInPicture() }
        else { vlcWindow?.stopPictureInPicture() }
        // 開始が成立していない場合は停止通知が来ないことがある。
        if wasPending, !isActive {
            releaseOwner()
            onStateChanged?()
        }
    }

    /// 旧VLCのstopは裏で完了するまでdrawableを必要とするが、新しい描画やUI通知は受け付けない。
    /// nativeのwindow停止とowner解放は、stop完了後のdisposeまで遅らせる。
    func retireRenderer() {
        rendererRetired = true
        startTimer?.invalidate()
        startTimer = nil
        vlcWindow?.stateChangeEventHandler = nil
        onStateChanged = nil
        onRestoreInterface = nil
        onError = nil
        onSuperseded = nil
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        startTimer?.invalidate()
        startTimer = nil
        possibleObserver = nil
        avController?.delegate = nil
        avController?.stopPictureInPicture()
        avController = nil
        vlcWindow?.stateChangeEventHandler = nil
        vlcWindow?.stopPictureInPicture()
        vlcWindow = nil
        isPending = false
        isActive = false
        releaseOwner()
        onStateChanged?()
    }

    func invalidatePlaybackState() { vlcWindow?.invalidatePlaybackState() }

    private func releaseOwner() {
        guard Self.current === self else { return }
        Self.current = nil
        Self.retainedOwner = nil
    }

    private func receivedState(_ started: Bool, restoreVLCInterface: Bool) {
        guard !disposed, !rendererRetired else { return }
        // タイムアウトや明示終了の後に届く遅延した開始通知で、PiP を復活させない。
        if started, (Self.current !== self || (!isPending && !isActive)) {
            avController?.stopPictureInPicture()
            vlcWindow?.stopPictureInPicture()
            return
        }
        let wasActive = isActive
        let owner = Self.current === self ? Self.retainedOwner : nil
        startTimer?.invalidate()
        startTimer = nil
        isPending = false
        isActive = started
        if !started {
            // VLC は停止理由を区別しない。PiP の終了後は元の画面を表示可能な状態へ戻す。
            // AVPlayer 経路の UI 復帰は専用 delegate が通知する。
            if wasActive, restoreVLCInterface { onRestoreInterface?() }
            releaseOwner()
        }
        onStateChanged?()
        withExtendedLifetime(owner) {}
    }

    // libVLC からの同期問い合わせも main へ寄せ、UIKit と再生状態を同時に読み書きしない。
    private nonisolated func readOnMain<T: Sendable>(_ action: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
        return DispatchQueue.main.sync { action() }
    }

    nonisolated func addSubview(_ view: UIView) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, !self.rendererRetired, let host = self.videoView else { return }
            view.frame = host.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            // VLCVideoUIView独自のtapはlibVLCのmouseイベントとなり、アプリを通らず停止する。
            // 描画は保ったまま入力を親surfaceの操作へ集約し、PiPへ渡す映像layerには触れない。
            view.isUserInteractionEnabled = false
            host.addSubview(view)
        }
    }

    nonisolated func bounds() -> CGRect { readOnMain { videoView?.bounds ?? .zero } }

    // libVLC は selector 不在を自動開始ONと解釈する。保持準備を伴う明示操作だけに限定する。
    @objc nonisolated func canStartPictureInPictureAutomaticallyFromInline() -> Bool { false }

    nonisolated func mediaController() -> any VLCPictureInPictureMediaControlling { self }

    nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        { [weak self] window in
            guard let window else { return }
            DispatchQueue.main.async {
                guard let self, !self.disposed, !self.rendererRetired else { return }
                self.vlcWindow?.stateChangeEventHandler = nil
                self.vlcWindow = window
                window.stateChangeEventHandler = { [weak self, weak window] started in
                    DispatchQueue.main.async {
                        guard let self, let window, self.vlcWindow === window else { return }
                        self.receivedState(started, restoreVLCInterface: true)
                    }
                }
                self.onStateChanged?()
            }
        }
    }

    nonisolated func play() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, !self.rendererRetired else { return }
            self.playAction()
        }
    }
    nonisolated func pause() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, !self.rendererRetired else { return }
            self.pauseAction()
        }
    }
    nonisolated func isMediaPlaying() -> Bool { readOnMain { playingProvider() } }
    nonisolated func isMediaSeekable() -> Bool {
        readOnMain { !live && durationProvider().isFinite && durationProvider() > 0 }
    }
    nonisolated func mediaTime() -> Int64 { readOnMain { Self.milliseconds(timeProvider()) } }
    nonisolated func mediaLength() -> Int64 { readOnMain { live ? 0 : Self.milliseconds(durationProvider()) } }

    private static func milliseconds(_ seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let value = seconds * 1000
        // Double(Int64.max) は範囲の外端へ丸まるため、変換前に厳密な上限で止める。
        guard value.isFinite, value < Double(Int64.max) else { return Int64.max }
        return Int64(value)
    }

    nonisolated func seek(by offset: Int64, completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, !self.rendererRetired, !self.live else { completion(); return }
            let duration = self.durationProvider()
            let time = self.timeProvider()
            guard duration.isFinite, duration > 0, time.isFinite else { completion(); return }
            let target = min(duration, max(0, time + Double(offset) / 1000))
            self.seekAction(target, completion)
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.avController === pictureInPictureController else { return }
            self.receivedState(true, restoreVLCInterface: false)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.avController === pictureInPictureController else { return }
            self.receivedState(false, restoreVLCInterface: false)
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                               failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.avController === pictureInPictureController else { return }
            self.receivedState(false, restoreVLCInterface: false)
            self.onError?("PiP を開始できませんでした。\(error.localizedDescription)")
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                               restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.disposed, self.avController === pictureInPictureController,
                  let restore = self.onRestoreInterface else { completionHandler(false); return }
            restore()
            completionHandler(true)
        }
    }
}

/// 4 系 delegate の状態通知には送信元が含まれないため、所有元がプレイヤーを捕捉して照合する。
final class VLCStateObserver: NSObject, VLCMediaPlayerDelegate {
    private let handler: (VLCMediaPlayerState) -> Void
    init(handler: @escaping (VLCMediaPlayerState) -> Void) { self.handler = handler }
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) { handler(newState) }
}
