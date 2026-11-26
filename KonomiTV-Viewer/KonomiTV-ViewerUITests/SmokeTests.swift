import XCTest

/// 録画ホームから fixture を再生し、各表示状態で時計の進行と overlay の存在を確かめる。
/// 字幕の描画内容やコメントの移動そのものを保証するテストではない。
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // 既存の設定キーだけで HEVC 経路を選ぶ。通信種別や保存済み設定に依存させない。
        app.launchArguments += [
            "-viewer_url", "http://127.0.0.1:18080",
            "-viewer_video_data_saver_mode", "YES",
            "-viewer_video_data_saver_mode_cellular", "YES",
            "-viewer_show_captions", "YES",
            "-viewer_show_comments", "YES",
            "-viewer_repeat_video_playback", "NO",
            "-viewer_playback_diagnostics",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        // tearDown中は実行結果が未確定のため、終了画像の名前で失敗と断定しない。
        if app != nil {
            attachScreenshot("final-state")
        }
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
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
        tapControlsButton("全画面", timeout: 20)
        let exitButton = app.buttons["全画面を解除"]
        // 端末は縦向きのまま、ボタン自身による画面回転を確認する。
        XCTAssertTrue(waitForVideoGeometry(landscape: true, timeout: 15), "Fullscreen geometry did not settle")
        XCTAssertTrue(waitForExistenceWithControls(exitButton, timeout: 15), "Fullscreen did not open")
        assertOverlays()
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback clock did not advance in fullscreen")
        attachScreenshot("03-fullscreen")

        tapControlsButton("全画面を解除", timeout: 20)
        // 解除状態と縦画面復帰を確認し、端末の回転操作で復帰不良を隠さない。
        XCTAssertTrue(enterButton.waitForExistence(timeout: 15), "Fullscreen did not close")
        XCTAssertTrue(app.staticTexts["番組情報"].waitForExistence(timeout: 15), "Info tabs did not return")
        XCTAssertTrue(waitForVideoGeometry(landscape: false, timeout: 15), "Portrait automation geometry did not settle")
        XCTAssertTrue(waitForExistenceWithControls(enterButton, timeout: 15), "Normal view did not return")
        assertOverlays()
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback clock did not advance after returning")
        attachScreenshot("04-returned-normal")
        // 3.5秒の非表示期限と1秒の診断観測を超えて保持し、長押し中の入力取消しを検出する。
        tapControlsButton("player.skipForwardButton", timeout: 20, holdDuration: 6)
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback did not resume after forward long press")
        tapControlsButton("player.skipBackButton", timeout: 20, holdDuration: 6)
        XCTAssertTrue(waitForPlaybackToAdvance(timeout: 15), "Playback did not resume after backward long press")
        attachScreenshot("05-after-held-seek")
    }

    private func assertOverlays() {
        XCTAssertTrue(app.otherElements["player.commentOverlay"].waitForExistence(timeout: 15), "Comment overlay missing")
        XCTAssertTrue(app.otherElements["player.captionOverlay"].exists, "Caption overlay missing")
    }

    /// windowと映像が実際に画面内へ収まり、連続したsnapshotで寸法が一致するまで待つ。
    private func waitForVideoGeometry(landscape: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: (CGRect, CGRect)?
        while Date() < deadline {
            if let window = try? app.windows.firstMatch.snapshot().frame,
               let video = try? app.otherElements["player.captionOverlay"].snapshot().frame,
               window.width > 0, window.height > 0, video.width > 0, video.height > 0,
               (window.width > window.height) == landscape, window.contains(video) {
                if let previous = previous, previous.0 == window, previous.1 == video {
                    print("Settled video geometry: landscape=\(landscape), device=\(XCUIDevice.shared.orientation.rawValue), window=\(window), video=\(video)")
                    return true
                }
                previous = (window, video)
            } else {
                previous = nil
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
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
        let deadline = Date().addingTimeInterval(timeout)
        var baseline: Int?
        while Date() < deadline {
            // 消えたlabelの検索リトライで長時間待たず、同じapp snapshotから有無と値を読む。
            var text: String?
            if let snapshot = try? app.snapshot() {
                var pending: [any XCUIElementSnapshot] = [snapshot]
                while let element = pending.popLast() {
                    if element.identifier == "player.currentTime" { text = element.label; break }
                    pending.append(contentsOf: element.children)
                }
            }
            if let text = text, let seconds = playbackSeconds(text) {
                print("Playback clock sample: seconds=\(seconds), baseline=\(String(describing: baseline))")
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

    private func tapControlsButton(_ label: String, timeout: TimeInterval, holdDuration: TimeInterval? = nil) {
        let deadline = Date().addingTimeInterval(timeout)
        let button = app.buttons[label]
        while Date() < deadline {
            // AX階層に残るボタンもあるため、存在やframeを実表示と混同しない。
            // isHittableは要素が無い場合もfalseを返す公開API。
            if button.isHittable {
                Thread.sleep(forTimeInterval: 0.4)
                continue
            }
            // 再表示後は追加照会を挟まない。native tapが最新ボタンの解決と操作可否を確認する。
            tapVideoArea()
            print("Tap freshly revealed native control: \(label)")
            if let holdDuration { button.press(forDuration: holdDuration) }
            else { button.tap() }
            return
        }
        XCTFail("Controls did not auto-hide before tapping the requested button")
    }

    private func tapVideoArea() {
        if let snapshot = try? app.snapshot(),
           let windowFrame = snapshot.children.first(where: { $0.elementType == .window })?.frame {
            var pending: [any XCUIElementSnapshot] = [snapshot]
            var video: CGRect?
            while let element = pending.popLast() {
                if element.identifier == "player.captionOverlay" { video = element.frame; break }
                pending.append(contentsOf: element.children)
            }
            guard let video, video.width > 0, video.height > 0, windowFrame.contains(video) else { return }
            // 中央の再生ボタン・ヘッダー・下端バーを避け、親surfaceの表示切替を操作する。
            let point = CGPoint(x: video.minX + video.width * 0.08, y: video.midY)
            print("Reveal controls: window=\(windowFrame), video=\(video), point=\(point)")
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: point.x - windowFrame.minX, dy: point.y - windowFrame.minY)).tap()
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
