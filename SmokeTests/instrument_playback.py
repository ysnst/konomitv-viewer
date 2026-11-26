"""Opt-in simulator diagnostics applied only to disposable CI source checkouts."""
import argparse
from pathlib import Path

METHOD = r'''
#if DEBUG && targetEnvironment(simulator)
    private var smokeDiagnosticCount = 0
    private func smokeDiagnostic(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-viewer_playback_diagnostics"),
              smokeDiagnosticCount < 400 else { return }
        smokeDiagnosticCount += 1
        var engine = "av ready=\(player?.currentItem?.status == .readyToPlay) playing=\(player?.timeControlStatus == .playing) rate=\(player?.rate ?? 0)"
#if canImport(VLCKit)
        if let vlcPlayer {
            engine = "vlc state=\(vlcPlayer.state) playing=\(vlcPlayer.isPlaying) id=\(ObjectIdentifier(vlcPlayer))"
        }
#endif
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
    private func smokeDiagnostic(_ event: String) {}
#endif
'''

def instrument(text):
    anchors = {
        "    private func playAtCurrentRate() {": 'play-request',
        "    private func pauseEngine(isUserInitiated: Bool = true) {": 'pause-request',
        "    private func updateProgress() {": 'tick',
        "    @objc private func toggleControls() {": 'toggle-controls',
        "    @objc private func togglePlayPause() {": 'toggle-play-pause',
    }
    for anchor, event in anchors.items():
        if text.count(anchor) != 1:
            raise ValueError(f"Expected one diagnostic anchor: {anchor}")
        extra = ''
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
