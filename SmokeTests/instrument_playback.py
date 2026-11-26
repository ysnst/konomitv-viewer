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
              smokeDiagnosticCount < 800 else { return }
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
            engine += " itemID=\(ObjectIdentifier(item)) itemStatus=\(item.status.rawValue) error=\(error?.domain ?? "nil"):\(error?.code ?? 0) underlying=\(underlying?.domain ?? "nil"):\(underlying?.code ?? 0) errors=\(errors) waiting=\(player?.reasonForWaitingToPlay?.rawValue ?? "nil") empty=\(item.isPlaybackBufferEmpty) full=\(item.isPlaybackBufferFull) likely=\(item.isPlaybackLikelyToKeepUp) duration=\(item.duration.seconds) size=\(item.presentationSize) rendered=\(playerLayer?.isReadyForDisplay ?? false) loaded=\(item.loadedTimeRanges.map { $0.timeRangeValue.start.seconds.description + ":" + $0.timeRangeValue.duration.seconds.description })"
        }
        if let timebase = player?.currentItem?.timebase {
            engine += " baseRate=\(CMTimebaseGetRate(timebase)) baseEffectiveRate=\(CMTimebaseGetEffectiveRate(timebase)) baseTime=\(CMTimebaseGetTime(timebase).seconds) hostTime=\(CMClockGetTime(CMClockGetHostTimeClock()).seconds)"
        }
        engine += " fmp4Confirmed=\(fmp4StartContext?.state.didPlay ?? false) recoveryPending=\(fmp4StartContext?.state.awaitingRecovery ?? false)"
        func held(_ button: UIButton) -> Bool {
            (button.gestureRecognizers ?? []).contains { recognizer in
                recognizer is UILongPressGestureRecognizer && (recognizer.state == .began || recognizer.state == .changed)
            }
        }
        let holdingBack = held(skipBackButton)
        let holdingForward = held(skipForwardButton)
        let holdingSeek = holdingBack || holdingForward
        let children = surfaceView.subviews.map {
            "\(type(of: $0)):input=\($0.isUserInteractionEnabled):gestures=\(($0.gestureRecognizers ?? []).map { String(describing: type(of: $0)) })"
        }.joined(separator: ";")
        let line = "SMOKE \(ProcessInfo.processInfo.systemUptime) \(event) \(engine) time=\(currentPosition()) ui=\(currentTimeLabel.text ?? "nil") intent=\(playbackIntentPlaying) pendingPause=\(playbackStart.pauseRequested) scrub=\(isScrubbing) heldBack=\(holdingBack) heldForward=\(holdingForward) heldSeek=\(holdingSeek) controls=\(controlsVisible) program=\(program.id) owner=\(ObjectIdentifier(self)) children=\(children)\n"
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
    has_fmp4 = "private var fmp4StartContext:" in text
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
    if has_fmp4:
        anchor = '        if action == .ignored { return true }'
        if text.count(anchor) != 1:
            raise ValueError('Expected accepted fMP4 failure guard')
        text = text.replace(anchor, anchor + '\n        smokeDiagnostic("fmp4-start-failure")')
    # 長押しの実UI操作用IDは使い捨ての試験checkoutにだけ付ける。
    import re
    for button in ('skipForwardButton', 'skipBackButton'):
        pattern = r'(?m)^( +configure\(' + button + r',.*)$'
        text, count = re.subn(pattern, lambda match: match.group(0) + '\n        ' + button + '.accessibilityIdentifier = "player.' + button + '"', text)
        if count != 1:
            raise ValueError('Expected skip button configuration')
    anchor = '            guard source === vlcPlayer else { return }'
    if text.count(anchor) != 1:
        raise ValueError('Expected VLC state guard')
    text = text.replace(anchor, anchor + '\n            self.smokeDiagnostic("vlc-notification \\(state)")')
    method = METHOD
    if not has_fmp4:
        method = '\n'.join(line for line in method.split('\n') if 'fmp4Confirmed=' not in line)
    return text.replace('    private func playAtCurrentRate() {', method + '\n    private func playAtCurrentRate() {', 1)


LIVE_METHOD = r'''
#if DEBUG && targetEnvironment(simulator)
    private var smokeLiveTimer: Timer?
    private var smokeLiveCount = 0
    private func smokeLiveDiagnostic(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-viewer_playback_diagnostics"),
              smokeLiveCount < 240 else { return }
        smokeLiveCount += 1
        var state = "missing"
        var time: Double = 0
#if canImport(VLCKit)
        if let vlcPlayer {
            time = Double(vlcPlayer.time.intValue) / 1000
            state = "state=\(vlcPlayer.state) playing=\(vlcPlayer.isPlaying) video=\(vlcPlayer.hasVideoOut) player=\(ObjectIdentifier(vlcPlayer))"
        }
#endif
        liveTimeLabel.isAccessibilityElement = true
        liveTimeLabel.accessibilityIdentifier = "live.currentTime." + channel.display_channel_id
        liveTimeLabel.accessibilityLabel = String(time)
        liveTimeLabel.accessibilityValue = channel.display_channel_id
        captionOverlayView.isAccessibilityElement = true
        captionOverlayView.accessibilityIdentifier = "player.captionOverlay"
        channelTabButton.accessibilityIdentifier = "live.channelTab"
        let line = "LIVE \(ProcessInfo.processInfo.systemUptime) \(event) owner=\(ObjectIdentifier(self)) channel=\(channel.display_channel_id) \(state) time=\(time) pending=\(streamStart.inFlight) controls=\(controlsVisible)\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("smoke-playback.log")
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
    private func smokeBeginLiveDiagnostics() {
        guard ProcessInfo.processInfo.arguments.contains("-viewer_playback_diagnostics"), smokeLiveTimer == nil else { return }
        smokeLiveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.smokeLiveCount < 240 else { timer.invalidate(); return }
            self.smokeLiveDiagnostic("tick")
        }
    }
#else
    private func smokeLiveDiagnostic(_ event: String) {}
    private func smokeBeginLiveDiagnostics() {}
#endif
'''


def instrument_live(text):
    for anchor, event in {
        '    private func startStream() {': 'start',
        '    private func stopStream() {': 'stop',
        '    private func beginStreamPlayback(originURL url: URL, relayedURL: URL?) {': 'begin',
        '    private func playStream() {': 'play',
        '    private func pauseStream() {': 'pause',
    }.items():
        if text.count(anchor) != 1:
            raise ValueError('Expected one live diagnostic anchor: ' + anchor)
        extra = '\n        smokeBeginLiveDiagnostics()' if event == 'start' else ''
        text = text.replace(anchor, anchor + '\n        smokeLiveDiagnostic("' + event + '")' + extra)
    anchor = '            guard source === self.vlcPlayer else { return }'
    if text.count(anchor) != 1:
        raise ValueError('Expected live VLC source guard')
    text = text.replace(anchor, anchor + '\n            self.smokeLiveDiagnostic("notification \\(state)")')
    return text.replace('    private func startStream() {', LIVE_METHOD + '\n    private func startStream() {', 1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    target = args.source / 'KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift'
    target.write_text(instrument(target.read_text()), encoding='utf-8')
    live = args.source / 'KonomiTV-Viewer/KonomiTV-Viewer/LivePlayerViewController.swift'
    live.write_text(instrument_live(live.read_text()), encoding='utf-8')
