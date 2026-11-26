import XCTest

/// 録画ホームから fixture を再生し、各表示状態で時計の進行と overlay の存在を確かめる。
/// 字幕の描画内容やコメントの移動そのものを保証するテストではない。
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 既存の設定キーだけで HEVC 経路を選ぶ。通信種別や保存済み設定に依存させない。
        app.launchArguments += [
            "-viewer_url", "http://127.0.0.1:18080",
            "-viewer_video_data_saver_mode", "YES",
            "-viewer_video_data_saver_mode_cellular", "YES",
            "-viewer_show_captions", "YES",
            "-viewer_show_comments", "YES",
            "-viewer_repeat_video_playback", "NO",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let app = app, testRun?.hasSucceeded == false {
            attachScreenshot("failure")
        }
        app?.terminate()
        app = nil
    }

    func testRecordedPlaybackAndFullscreenOverlays() throws {
        // SceneDelegate は録画ホームを初期選択する。新着カードから直接再生する。
        let programTitle = app.staticTexts["スモークテスト番組"].firstMatch
        XCTAssertTrue(programTitle.waitForExistence(timeout: 30), "Fixture missing from recording home")
        attachScreenshot("01-recording-home")
        programTitle.tap()
        assertOverlays()
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 40), "Playback clock did not advance in normal view")
        attachScreenshot("02-normal-playback")

        let enterButton = app.buttons["全画面"]
        tapControlsButton(enterButton, timeout: 20)
        let exitButton = app.buttons["全画面を解除"]
        XCTAssertTrue(waitForExistenceWithControls(exitButton, timeout: 15), "Fullscreen did not open")
        assertOverlays()
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback clock did not advance in fullscreen")
        attachScreenshot("03-fullscreen")

        tapControlsButton(exitButton, timeout: 20)
        XCTAssertTrue(waitForExistenceWithControls(enterButton, timeout: 15), "Normal view did not return")
        assertOverlays()
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback clock did not advance after returning")
        attachScreenshot("04-returned-normal")
    }

    private func assertOverlays() {
        XCTAssertTrue(app.otherElements["player.commentOverlay"].waitForExistence(timeout: 15), "Comment overlay missing")
        XCTAssertTrue(app.otherElements["player.captionOverlay"].exists, "Caption overlay missing")
    }

    /// 空文字や任意のラベルを再生成功とみなさず、m:ss / h:mm:ss の数値だけを読む。
    private func playbackSeconds(_ text: String) -> Int? {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2 || fields.count == 3,
              fields.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }) else { return nil }
        let values = fields.compactMap { Int($0) }
        guard values.count == fields.count,
              fields.last?.count == 2, values.last! < 60 else { return nil }
        if fields.count == 3 {
            guard fields[1].count == 2, values[1] < 60 else { return nil }
        }
        // 表示値は小さいが、不正な巨大値でも整数オーバーフローを起こさない。
        var seconds = 0
        for value in values {
            let multiplied = seconds.multipliedReportingOverflow(by: 60)
            let added = multiplied.partialValue.addingReportingOverflow(value)
            guard !multiplied.overflow && !added.overflow else { return nil }
            seconds = added.partialValue
        }
        return seconds
    }

    /// 各状態で新たに基準値を取り、正の秒数へ実際に増加するまで待つ。
    private func waitForPlaybackToAdvance(timeout: TimeInterval) -> Bool {
        let timeLabel = app.descendants(matching: .any)["player.currentTime"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var baseline: Int?
        while Date() < deadline {
            if timeLabel.exists, let seconds = playbackSeconds(timeLabel.label) {
                if let baseline = baseline, seconds > 0 && seconds > baseline { return true }
                if baseline == nil { baseline = seconds }
            } else {
                tapVideoArea()
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    private func waitForExistenceWithControls(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            tapVideoArea()
            Thread.sleep(forTimeInterval: 0.4)
        }
        return element.exists && element.isHittable
    }

    private func tapControlsButton(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            // 回転中の一時的な非操作状態を待ってから、alpha で隠れた操作帯も出し直す。
            Thread.sleep(forTimeInterval: 0.5)
            if element.exists && element.isHittable { continue }
            tapVideoArea()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTFail("Control did not become hittable")
    }

    private func tapVideoArea() {
        let overlay = app.otherElements["player.captionOverlay"]
        if overlay.exists {
            overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
