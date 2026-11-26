"""使い捨てsimulator checkoutへの観測だけを追加する。再生・シーク処理は置換しない。"""
import argparse
from pathlib import Path

RECORD = r'''
#if DEBUG && targetEnvironment(simulator)
    private var stageSamples = 0
    private var stageBeginCount = 0
    private var stageEndCount = 0
    private var stageTemporaryPauses = 0
    private var stageCancellationApplied = false
    private func stageState(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-stage_a_diagnostics"), stageSamples < 400 else { return }
        stageSamples += 1
        let actual = currentPosition()
        currentTimeLabel.isAccessibilityElement = true
        currentTimeLabel.accessibilityIdentifier = "stage.actualClock"
        currentTimeLabel.accessibilityLabel = String(actual.isFinite ? actual : -1)
        captionOverlayView.isAccessibilityElement = true
        captionOverlayView.accessibilityIdentifier = "stage.video"
        seekSlider.accessibilityIdentifier = "stage.seekSlider"
        seekSlider.accessibilityLabel = "scrub=\(isScrubbing) preview=\(!seekPreviewView.isHidden) density=\(!excitementStrip.isHidden) begin=\(stageBeginCount) end=\(stageEndCount)"
        playPauseButton.accessibilityIdentifier = "stage.playPause"
        playPauseButton.accessibilityValue = playbackIntentPlaying ? "playing" : "paused"
        seekPreviewView.isAccessibilityElement = true
        seekPreviewView.accessibilityIdentifier = "stage.preview"
        excitementStrip.isAccessibilityElement = true
        excitementStrip.accessibilityIdentifier = "stage.density"
        var playing = false
        var video = false
#if canImport(VLCKit)
        playing = vlcPlayer?.isPlaying ?? false
        video = vlcPlayer?.hasVideoOut ?? false
#endif
        captionOverlayView.accessibilityLabel = "time=\(actual.isFinite ? actual : -1) playing=\(playing) intent=\(playbackIntentPlaying) temporaryPauses=\(stageTemporaryPauses) controls=\(controlsVisible) " + (seekSlider.accessibilityLabel ?? "")
        stageWrite(["kind":"recorded", "event":event,"time":actual.isFinite ? actual : -1,
                    "playing":playing,"intent":playbackIntentPlaying,"temporaryPauses":stageTemporaryPauses,"video":video,"scrub":isScrubbing,
                    "preview":!seekPreviewView.isHidden,"density":!excitementStrip.isHidden,"begin":stageBeginCount,"end":stageEndCount])
    }
    private func stageMaybeCancelContract() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !stageCancellationApplied, currentPosition() > 1 else { return }
        if arguments.contains("-stage_a_latest_pause") || arguments.contains("-stage_a_latest_play") {
            stageCancellationApplied = true
            // nativeタッチとは別の契約。実所有元へ開始→最新操作→終了を同じturnで渡す。
            if arguments.contains("-stage_a_latest_play") { pauseEngine() }
            scrubBegan()
            seekSlider.value = 0.5
            if arguments.contains("-stage_a_latest_pause") { pauseEngine() }
            else { playAtCurrentRate() }
            scrubEnded()
            stageState("latest-intent-contract")
            return
        }
        guard arguments.contains("-stage_a_cancel_contract") else { return }
        stageCancellationApplied = true
        // 実OSのtouchCancelではなく、実UIKit overrideと所有元の結線を直接検証する別契約。
        scrubBegan()
        seekSlider.cancelTracking(with: nil)
        stageState("cancel-contract")
    }
#else
    private func stageState(_ event: String) {}
    private func stageMaybeCancelContract() {}
#endif
'''
LIVE = r'''
#if DEBUG && targetEnvironment(simulator)
    private var stageLiveTimer: Timer?
    private var stageLiveCount = 0
    private func stageLiveState(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-stage_a_diagnostics"), stageLiveCount < 240 else { return }
        stageLiveCount += 1
        let actual = currentVLCTimeSeconds()
        liveTimeLabel.isAccessibilityElement = true
        liveTimeLabel.accessibilityIdentifier = "stage.actualClock"
        liveTimeLabel.accessibilityLabel = String(actual)
        captionOverlayView.isAccessibilityElement = true
        captionOverlayView.accessibilityIdentifier = "stage.video"
        captionOverlayView.accessibilityLabel = "time=\(actual)"
        var playing = false
        var video = false
#if canImport(VLCKit)
        playing = vlcPlayer?.isPlaying ?? false
        video = vlcPlayer?.hasVideoOut ?? false
#endif
        stageWrite(["kind":"live","event":event,"time":actual,"playing":playing,"video":video])
    }
    private func stageBeginLiveObservation() {
        guard ProcessInfo.processInfo.arguments.contains("-stage_a_diagnostics"), stageLiveTimer == nil else { return }
        stageLiveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, self.stageLiveCount < 240 else { timer.invalidate(); return }
            self.stageLiveState("tick")
        }
    }
#else
    private func stageLiveState(_ event: String) {}
    private func stageBeginLiveObservation() {}
#endif
'''
LOGGER = r'''
#if DEBUG && targetEnvironment(simulator)
private func stageWrite(_ fields: [String: Any]) {
    var fields = fields
    fields["uptime"] = ProcessInfo.processInfo.systemUptime
    guard let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
          var line = String(data: body, encoding: .utf8) else { return }
    line += "\n"
    let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stage-a.jsonl")
    if !FileManager.default.fileExists(atPath: path.path) { _ = FileManager.default.createFile(atPath: path.path, contents: nil) }
    if let handle = try? FileHandle(forWritingTo: path) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
#endif
'''

def instrument_recorded(text):
    anchor = '    private func updateProgress() {'
    assert text.count(anchor) == 1
    text = text.replace(anchor, RECORD + '\n' + anchor + '\n        defer { stageState("tick"); stageMaybeCancelContract() }', 1)
    for method, event in [('scrubBegan', 'scrub-began'), ('scrubChanged', 'scrub-changed'), ('scrubEnded', 'scrub-ended')]:
        anchor = '    @objc private func ' + method + '() {'
        assert text.count(anchor) == 1
        counter = '\n        stageBeginCount += 1' if method == 'scrubBegan' else ('\n        if isScrubbing { stageEndCount += 1 }' if method == 'scrubEnded' else '')
        text = text.replace(anchor, anchor + counter + '\n        defer { stageState("' + event + '") }', 1)
    anchor = '    private func pauseEngine(isUserInitiated: Bool = true) {'
    assert text.count(anchor) == 1
    text = text.replace(anchor, anchor + '\n#if DEBUG && targetEnvironment(simulator)\n        if !isUserInitiated { stageTemporaryPauses += 1 }\n#endif', 1)
    anchor = '            self.spriteLoadState = .loaded'
    assert text.count(anchor) == 1
    text = text.replace(anchor, anchor + '\n            self.stageState("sprite-loaded")', 1)
    return text + LOGGER


def instrument_live(text):
    anchor = '    private func startStream() {'
    assert text.count(anchor) == 1
    text = text.replace(anchor, LIVE + '\n' + anchor + '\n        stageBeginLiveObservation()', 1)
    # 同じファイルにloggerを重複定義せず、recordedのファイルprivateをinternalへ変更して共有する。
    return text


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    args = parser.parse_args()
    # 0.26はSDKROOT未指定のためscheme解決がMacとなる。試験コピーだけに明示する。
    project = args.checkout / 'KonomiTV-Viewer/KonomiTV-Viewer.xcodeproj/project.pbxproj'
    project.write_text(project.read_text().replace('PRODUCT_NAME = "$(TARGET_NAME)";',
                       'PRODUCT_NAME = "$(TARGET_NAME)";\n\t\t\t\tSDKROOT = iphoneos;'), encoding='utf8')
    app = args.checkout / 'KonomiTV-Viewer/KonomiTV-Viewer'
    path = app / 'PlayerViewController.swift'
    path.write_text(instrument_recorded(path.read_text()).replace('private func stageWrite(', 'func stageWrite('), encoding='utf8')
    path = app / 'LivePlayerViewController.swift'
    path.write_text(instrument_live(path.read_text()), encoding='utf8')
