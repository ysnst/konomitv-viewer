import XCTest

/// native入力と実VLC時計を確認する。字幕画像・実サーバー・実機PiPの試験とは区別する。
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var preparedSeekFrame = CGRect.zero
    private var preparedWindowOrigin = CGPoint.zero
    private var preparedButtonFrame = CGRect.zero
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-viewer_url", "http://127.0.0.1:18080",
                               "-viewer_video_data_saver_mode", "YES", "-viewer_video_data_saver_mode_cellular", "YES",
                               "-viewer_show_captions", "YES", "-viewer_show_comments", "YES",
                               "-viewer_repeat_video_playback", "NO", "-stage_a_diagnostics"]
        if name.contains("CancelTracking") { app.launchArguments += ["-stage_a_cancel_contract"] }
        if name.contains("LatestPause") { app.launchArguments += ["-stage_a_latest_pause"] }
        if name.contains("LatestPlay") { app.launchArguments += ["-stage_a_latest_play"] }
        app.launch()
    }
    override func tearDownWithError() throws {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "final-state"
        image.lifetime = .keepAlways
        add(image)
        app?.terminate()
        app = nil
    }
    func testRecordedNativeSeekAndTap() throws {
        openRecording()
        XCTAssertTrue(waitForClock(timeout: 40), "Actual VLC clock did not advance")
        tapVideo()
        XCTAssertTrue(waitForClock(timeout: 15), "Video tap paused actual playback")
        // thumbから離れた操作領域上部でも開始/終了が揃うこと。
        performSeek(targetRatio: 0.25) { self.seekPoint(0.25, y: 0.2).tap() }
        performSeek(targetRatio: 0.7) { self.seekPoint(0.7).tap() }
        performSeek(targetRatio: 0.6) {
            self.seekPoint(0.3).press(forDuration: 0.2, thenDragTo: self.seekPoint(0.6))
        }
        performSeek(targetRatio: 0.5) {
            let start = self.seekPoint(0.5)
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -80)))
        }
        tapControl("全画面")
        XCTAssertTrue(waitForGeometry(landscape: true), "Fullscreen did not settle")
        performSeek(targetRatio: 0.35) { self.seekPoint(0.35).tap() }
        tapControl("全画面を解除")
        XCTAssertTrue(waitForGeometry(landscape: false), "Portrait did not return")
        XCTAssertTrue(waitForClock(timeout: 15), "Recorded playback stopped after fullscreen")
    }
    func testLatestPauseDuringScrubContract() throws {
        openRecording()
        XCTAssertTrue(app.buttons["stage.playPause"].waitForExistence(timeout: 40))
        XCTAssertTrue(waitForSeekEnd(begin: 1, end: 1, timeout: 40))
        waitForEngineSeekCompletion(1)
        assertClockPaused()
    }
    func testLatestPlayDuringScrubContract() throws {
        openRecording()
        XCTAssertTrue(waitForClock(timeout: 40))
        XCTAssertTrue(waitForSeekEnd(begin: 1, end: 1))
        XCTAssertTrue(snapshot("stage.video")?.1.contains("intent=true ") == true)
    }
    func testSeekPreservesPlaybackIntent() throws {
        openRecording()
        XCTAssertTrue(waitForClock(timeout: 40))
        // 再生中のtap/dragは既存試験でも実時計の継続を確認する。
        performSeek(targetRatio: 0.3) { self.seekPoint(0.3).tap() }
        XCTAssertTrue(snapshot("stage.video")?.1.contains("temporaryPauses=0 ") == true,
                      "Scrubbing issued an asynchronous temporary pause")
        tapControl("stage.playPause")
        assertClockPaused()
        performPausedSeek(targetRatio: 0.65) { self.seekPoint(0.65).tap() }
        performPausedSeek(targetRatio: 0.4) {
            self.seekPoint(0.6).press(forDuration: 0.2, thenDragTo: self.seekPoint(0.4))
        }
        // 最新の明示的な再生操作の後、連続したnative入力でも継続する。
        tapControl("stage.playPause")
        XCTAssertTrue(waitForClock(timeout: 15))
        guard let counts = prepareSeekInput() else { XCTFail("Seek geometry unavailable"); return }
        seekPoint(0.5).tap()
        seekPoint(0.7).tap()
        XCTAssertTrue(waitForSeekEnd(begin: counts.0 + 2, end: counts.1 + 2))
        XCTAssertTrue(waitForClock(timeout: 15), "Consecutive seeks did not continue playback")
        XCTAssertTrue(snapshot("stage.video")?.1.contains("temporaryPauses=0 ") == true)
    }
    private func performPausedSeek(targetRatio: CGFloat, action: () -> Void) {
        guard let counts = prepareSeekInput() else { XCTFail("Seek geometry unavailable"); return }
        action()
        XCTAssertTrue(waitForSeekEnd(begin: counts.0 + 1, end: counts.1 + 1))
        let deadline = Date().addingTimeInterval(15)
        var reached = false
        while Date() < deadline {
            if let actual = actualClock(), abs(actual - Double(targetRatio) * 180) <= 6 {
                reached = true; break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(reached, "Paused engine did not reach seek target")
        waitForEngineSeekCompletion(counts.1 + 1)
        assertClockPaused()
    }
    private func waitForEngineSeekCompletion(_ count: Int) {
        // setTime直後の仮時刻ではなく、実エンジンの完了通知まで待つ。
        // 既存の移動先判定と同じ15秒以内。停止時計の3秒/0.25秒は変更しない。
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if snapshot("stage.video")?.1.contains("completed=\(count) ") == true { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Actual engine seek completion missing")
    }
    private func actualClock() -> Double? {
        guard let label = snapshot("stage.video")?.1,
              let field = label.split(separator: " ").first else { return nil }
        return Double(field.dropFirst(5))
    }
    private func assertClockPaused() {
        // 既存clock観測と同じ実時計を3秒観測し、表示用の先行位置を使用しない。
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, snapshot("stage.video")?.1.contains("playing=false intent=false ") != true {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(snapshot("stage.video")?.1.contains("playing=false intent=false ") == true)
        guard let start = actualClock() else { XCTFail("Actual clock missing"); return }
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            guard let actual = actualClock() else { XCTFail("Actual clock missing"); return }
            XCTAssertLessThanOrEqual(abs(actual - start), 0.25, "Paused playback advanced")
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
    func testSliderCancelTrackingContract() throws {
        // 公開API cancelTrackingを直接呼ぶ別契約。実OSのtouchCancelが起きたという主張はしない。
        openRecording()
        XCTAssertTrue(waitForClock(timeout: 40), "Cancel contract stopped actual playback")
        XCTAssertTrue(waitForSeekEnd(begin: 1, end: 1), "cancelTracking did not finish owner scrub state")
    }
    func testLiveNativeVideoTap() throws {
        let tab = app.descendants(matching: .any)["テレビをみる"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let channel = app.staticTexts["Ch: 001 段階A生放送"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30))
        channel.tap()
        XCTAssertTrue(waitForClock(timeout: 40), "Live VLC clock did not advance")
        tapVideo()
        XCTAssertTrue(waitForClock(timeout: 15), "Live video tap stopped playback")
        tapControl("全画面")
        XCTAssertTrue(waitForGeometry(landscape: true), "Live fullscreen did not settle")
        tapVideo()
        XCTAssertTrue(waitForClock(timeout: 15), "Fullscreen live video tap stopped playback")
        tapControl("全画面を解除")
        XCTAssertTrue(waitForGeometry(landscape: false), "Live portrait did not return")
        XCTAssertTrue(waitForClock(timeout: 15), "Live playback stopped after fullscreen")
    }
    private func openRecording() {
        let card = app.staticTexts["スモークテスト番組"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        card.tap()
    }
    private func snapshot(_ identifier: String) -> (CGRect, String)? {
        guard let tree = try? app.snapshot() else { return nil }
        var pending: [any XCUIElementSnapshot] = [tree]
        while let item = pending.popLast() {
            if item.identifier == identifier { return (item.frame, item.label) }
            pending.append(contentsOf: item.children)
        }
        return nil
    }
    private func waitForClock(timeout: TimeInterval) -> Bool {
        var first: Double?
        var previous: Double?
        var increases = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let (_, label) = snapshot("stage.video"), let timeField = label.split(separator: " ").first, let actual = Double(timeField.dropFirst(5)), actual.isFinite {
                print("Actual clock sample: \(actual)")
                if let previous, actual > previous { increases += 1 }
                if let first, actual >= first + 1, increases >= 2 { return true }
                if first == nil { first = actual }
                previous = actual
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }
    private func waitForSeekEnd(begin: Int, end: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let (_, state) = snapshot("stage.video"),
               state.hasSuffix("scrub=false preview=false density=false begin=\(begin) end=\(end)") { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
    private func performSeek(targetRatio: CGFloat, action: () -> Void) {
        guard let counts = prepareSeekInput() else { XCTFail("Tracking geometry/counters unavailable"); return }
        action()
        XCTAssertTrue(waitForSeekEnd(begin: counts.0 + 1, end: counts.1 + 1), "Native seek did not begin/end exactly once or left UI visible")
        let deadline = Date().addingTimeInterval(15)
        var reached = false
        while Date() < deadline {
            if let (_, label) = snapshot("stage.video"), let timeField = label.split(separator: " ").first, let actual = Double(timeField.dropFirst(5)), abs(actual - Double(targetRatio) * 180) <= 6 {
                reached = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        // fixtureの閉GOPは6秒間隔。表示専用の先行位置でなく実時計が移動したことを確認する。
        XCTAssertTrue(reached, "Actual engine clock did not reach the seek target")
        XCTAssertTrue(waitForClock(timeout: 15), "Playback did not continue after seek")
    }
    private func tapControl(_ name: String) {
        if snapshot("stage.video")?.1.contains("controls=") == true {
            guard prepareSeekInput(controlName: name) != nil else { XCTFail("Control geometry unavailable"); return }
            let point = CGVector(dx: preparedButtonFrame.midX - preparedWindowOrigin.x,
                                 dy: preparedButtonFrame.midY - preparedWindowOrigin.y)
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
            return
        }
        // 生放送にはrecorded用の状態ラベルを追加せず、従来の操作を維持する。
        let button = app.buttons[name]
        if !button.isHittable { tapVideo() }
        button.tap()
    }
    private func waitForGeometry(landscape: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let window = app.windows.firstMatch.frame
            // 通常の映像も16:9。向きはwindowで判断し、映像の占有率で復帰を区別する。
            if let (video, _) = snapshot("stage.video"), video.width > 0, video.height > 0,
               (window.width > window.height) == landscape, window.contains(video),
               (video.height > window.height * 0.65) == landscape { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
    private func tapVideo() {
        guard let (video, _) = snapshot("stage.video") else { XCTFail("Video geometry missing"); return }
        let window = app.windows.firstMatch
        let origin = window.frame.origin
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: video.minX + video.width * 0.08 - origin.x, dy: video.midY - origin.y)).tap()
    }
    private func prepareSeekInput(controlName: String? = nil) -> (Int, Int)? {
        // 実タップを含む準備は最大3回。結果の待機秒数を延ばさず、表示後の
        // 重いAX再取得をなくす。終了5秒・移動先15秒の判定は別途維持する。
        for _ in 0..<3 {
            guard let tree = try? app.snapshot() else { continue }
            var pending: [any XCUIElementSnapshot] = [tree]
            var slider: CGRect?
            var button: CGRect?
            var window: CGRect?
            var video: (CGRect, String)?
            while let item = pending.popLast() {
                if item.elementType == .window, window == nil { window = item.frame }
                if item.identifier == "stage.seekSlider" { slider = item.frame }
                if let controlName, item.elementType == .button,
                   item.identifier == controlName || item.label == controlName { button = item.frame }
                if item.identifier == "stage.video" { video = (item.frame, item.label) }
                pending.append(contentsOf: item.children)
            }
            guard let window, let video else { continue }
            let point = CGVector(dx: video.0.minX + video.0.width * 0.08 - window.minX,
                                 dy: video.0.midY - window.minY)
            let videoPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(point)
            if let slider, slider.width > 0, slider.height > 0,
               video.1.contains("controls=true "),
               controlName == nil || (button?.width ?? 0) > 0 {
                let fields = Dictionary(uniqueKeysWithValues: video.1.split(separator: " ").compactMap { field -> (String, String)? in
                    let pair = field.split(separator: "=", maxSplits: 1)
                    return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
                })
                guard let begin = Int(fields["begin"] ?? ""), let end = Int(fields["end"] ?? "") else { continue }
                preparedSeekFrame = slider
                preparedButtonFrame = button ?? .zero
                preparedWindowOrigin = window.origin
                // 停止中は操作帯が自動で隠れない。表示中の保存座標へ直接入力する。
                if fields["intent"] == "false" { return (begin, end) }
                // 再生中は非表示を確認してから実タップで表示し、直ちに保存座標へ入力。
                // opacity変更ではframe/counterが変わらない。表示後にはAX取得を挟まない。
                for _ in 0..<3 {
                    videoPoint.tap()
                    guard let state = snapshot("stage.video")?.1 else { return nil }
                    if state.contains("controls=false ") {
                        videoPoint.tap()
                        return (begin, end)
                    }
                }
                return nil
            }
            videoPoint.tap()
        }
        return nil
    }

    private func seekPoint(_ ratio: CGFloat, y: CGFloat = 0.92) -> XCUICoordinate {
        // Sliderを再検索せず、直前の同一snapshotの絶対座標を使う。
        let point = CGVector(dx: preparedSeekFrame.minX + preparedSeekFrame.width * ratio - preparedWindowOrigin.x,
                             dy: preparedSeekFrame.minY + preparedSeekFrame.height * y - preparedWindowOrigin.y)
        return app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(point)
    }
}
