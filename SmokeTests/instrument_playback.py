"""Opt-in simulator diagnostics applied only to disposable CI source checkouts."""
import argparse
from pathlib import Path

METHOD = r'''
#if DEBUG && targetEnvironment(simulator)
    private var smokeDiagnosticCount = 0
    private var smokeDiagnosticTimer: Timer?
    private var smokeWallSamples = 0
    private func smokeBeginDiagnostics() {
        guard ProcessInfo.processInfo.arguments.contains("-viewer_playback_diagnostics"),
              smokeDiagnosticTimer == nil else { return }
        smokeDiagnosticTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.smokeWallSamples < 120 else { timer.invalidate(); return }
            self.smokeWallSamples += 1
            self.smokeDiagnostic("wall-tick")
        }
    }
    private func smokeDiagnostic(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-viewer_playback_diagnostics"),
              smokeDiagnosticCount < 400 else { return }
        smokeDiagnosticCount += 1
        var engine = "av ready=\(player?.currentItem?.status == .readyToPlay) playing=\(player?.timeControlStatus == .playing) rate=\(player?.rate ?? 0) control=\(player?.timeControlStatus.rawValue ?? -1) playerStatus=\(player?.status.rawValue ?? -1)"
#if canImport(VLCKit)
        if let vlcPlayer {
            engine = "vlc state=\(vlcPlayer.state) playing=\(vlcPlayer.isPlaying) id=\(ObjectIdentifier(vlcPlayer))"
        }
#endif
        if let item = player?.currentItem {
            let errors = (item.errorLog()?.events.suffix(3) ?? []).map { "\($0.errorDomain):\($0.errorStatusCode)" }.joined(separator: ",")
            let error = item.error as NSError?
            let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
            engine += " itemStatus=\(item.status.rawValue) error=\(error?.domain ?? "nil"):\(error?.code ?? 0) underlying=\(underlying?.domain ?? "nil"):\(underlying?.code ?? 0) errors=\(errors) waiting=\(player?.reasonForWaitingToPlay?.rawValue ?? "nil") empty=\(item.isPlaybackBufferEmpty) full=\(item.isPlaybackBufferFull) likely=\(item.isPlaybackLikelyToKeepUp) duration=\(item.duration.seconds) size=\(item.presentationSize) rendered=\(playerLayer?.isReadyForDisplay ?? false) loaded=\(item.loadedTimeRanges.map { $0.timeRangeValue.start.seconds.description + ":" + $0.timeRangeValue.duration.seconds.description })"
        }
        let children = surfaceView.subviews.map {
            "\(type(of: $0)):input=\($0.isUserInteractionEnabled):gestures=\(($0.gestureRecognizers ?? []).map { String(describing: type(of: $0)) })"
        }.joined(separator: ";")
        let line = "SMOKE \(ProcessInfo.processInfo.systemUptime) \(event) \(engine) time=\(currentPosition()) ui=\(currentTimeLabel.text ?? "nil") intent=\(playbackIntentPlaying) pendingPause=\(playbackStart.pauseRequested) scrub=\(isScrubbing) controls=\(controlsVisible) children=\(children)\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("smoke-playback.log")
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
#else
    private func smokeBeginDiagnostics() {}
    private func smokeDiagnostic(_ event: String) {}
#endif
'''

def instrument(text):
    anchors = {
        "    private func playAtCurrentRate() {": 'play-request',
        "    private func pauseEngine(isUserInitiated: Bool = true) {": 'pause-request',
        "    private func updateProgress() {": 'tick',
        "    private func teardownAVPlayback() {": 'teardown-av',
        "    private func handlePlaybackEnded() {": 'ended',
        "    @objc private func toggleControls() {": 'toggle-controls',
        "    @objc private func togglePlayPause() {": 'toggle-play-pause',
    }
    for anchor, event in anchors.items():
        if text.count(anchor) != 1:
            raise ValueError(f"Expected one diagnostic anchor: {anchor}")
        extra = '\n        smokeBeginDiagnostics()' if event == 'play-request' else ''
        if event == 'pause-request':
            extra = '\n        smokeDiagnostic("pause-stack " + Thread.callStackSymbols.prefix(8).joined(separator: " | "))'
        text = text.replace(anchor, anchor + f'\n        smokeDiagnostic("{event}")' + extra)
    anchor = '            guard source === vlcPlayer else { return }'
    if text.count(anchor) != 1:
        raise ValueError('Expected VLC state guard')
    text = text.replace(anchor, anchor + '\n            self.smokeDiagnostic("vlc-notification \\(state)")')
    return text.replace('    private func playAtCurrentRate() {', METHOD + '\n    private func playAtCurrentRate() {', 1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    target = args.source / 'KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift'
    target.write_text(instrument(target.read_text()), encoding='utf-8')
