import MediaPlayer
import UIKit

/// ロック画面やコントロールセンターに出る「再生中」表示 (MPNowPlayingInfoCenter) と、
/// そちらからの操作 (MPRemoteCommandCenter) をまとめて扱う。
/// 再生画面 (録画・生放送) が再生を始めるときに所有権を取り、終わるときに手放す。
/// 操作は所有中の画面へそのまま渡すので、アプリ内の表示とずれない。
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    /// 所有中の画面が受け付ける操作。録画だけが持つ操作は任意 (生放送は nil)。
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        /// イヤホンのボタンなど、再生と停止が1つの操作になっているもの用。
        var togglePlayPause: () -> Void
        var skipForward: (() -> Void)?
        var skipBackward: (() -> Void)?
        var seekTo: ((Double) -> Void)?
        /// 車のナビやイヤホンの「次へ／前へ」。録画ではチャプター移動につなぐ。
        var nextChapter: (() -> Void)?
        var previousChapter: (() -> Void)?
    }

    private var owner: ObjectIdentifier?
    private var handlers: Handlers?
    private var artwork: MPMediaItemArtwork?

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        center.playCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.skipForward?() }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.skipBackward?() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            self?.dispatch { $0.seekTo?(position) }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.nextChapter?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.dispatch { $0.previousChapter?() }
            return .success
        }
        updateCommandAvailability()
    }

    private func dispatch(_ action: @escaping (Handlers) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let handlers = self?.handlers else { return }
            action(handlers)
        }
    }

    // MARK: - 所有権

    /// 再生を始める画面が呼ぶ。前の所有者が残っていれば引き継ぐ。
    func begin(owner: AnyObject, handlers: Handlers) {
        self.owner = ObjectIdentifier(owner)
        self.handlers = handlers
        artwork = nil
        // リモート操作のスキップ間隔は、録画再生の設定値に合わせておく
        // (実際の移動は所有中の画面の設定値どおりの処理で行われる)。
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: SettingsStore.shared.seekForwardSeconds)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: SettingsStore.shared.seekBackwardSeconds)]
        updateCommandAvailability()
    }

    /// 再生を終える画面が呼ぶ。所有者でない画面から呼ばれても何もしない
    /// (録画と生放送を行き来したときに、新しい方の表示を消してしまわないため)。
    func end(owner: AnyObject) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        self.owner = nil
        handlers = nil
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateCommandAvailability()
    }

    private func updateCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let active = handlers != nil
        center.playCommand.isEnabled = active
        center.pauseCommand.isEnabled = active
        center.togglePlayPauseCommand.isEnabled = active
        center.skipForwardCommand.isEnabled = handlers?.skipForward != nil
        center.skipBackwardCommand.isEnabled = handlers?.skipBackward != nil
        center.changePlaybackPositionCommand.isEnabled = handlers?.seekTo != nil
        center.nextTrackCommand.isEnabled = handlers?.nextChapter != nil
        center.previousTrackCommand.isEnabled = handlers?.previousChapter != nil
    }

    // MARK: - 表示の更新

    /// 録画再生の表示。位置と長さを持ち、再生の進行に合わせて呼び直す。
    func updateRecorded(owner: AnyObject, title: String, subtitle: String?, elapsed: Double, duration: Double, rate: Double) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let subtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 生放送の表示。位置や長さは出さず、再生中かどうかだけを持つ。
    func updateLive(owner: AnyObject, title: String, subtitle: String?, isPlaying: Bool) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if let subtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// サムネイル画像をアートワークとして差し込む (録画用)。
    func setArtwork(owner: AnyObject, image: UIImage) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.artwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
