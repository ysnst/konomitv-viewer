import XCTest

/// 自動テスト (スモークテスト)。仮サーバー (SmokeTests/stub_server.py) の
/// 材料でアプリを起動し、「録画一覧 → 再生開始 → 全画面 → 通常画面へ戻る」
/// を一巡して、再生の開始と、全画面でも流れるコメントと字幕の重ね物が
/// 付いて来ていることを確認する。
///
/// 接続先は起動時の引数で仮サーバーへ向ける (設定の保存キー viewer_url と
/// 同じ仕組み。通常の起動には影響しない)。
///
/// 注意: 再生画面の操作帯は、再生中に数秒で自動的に隠れる。隠れている間、
/// その中身 (再生位置の表示や全画面ボタン) は画面操作テストの要素として
/// 見つからなくなるため、見つからないときは映像をタップして操作帯を
/// 出し直しながら確かめる作りにしている。
final class SmokeTests: XCTestCase {

    /// 仮サーバーの接続先 (ワークフローが同じポートで起動する)。
    private let stubBaseURL = "http://127.0.0.1:18080"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-viewer_url", stubBaseURL]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testRecordedPlaybackAndFullscreenOverlays() throws {
        // 起動 → 録画一覧に、仮サーバーの番組が出る。
        let programTitle = app.staticTexts["スモークテスト番組"]
        XCTAssertTrue(
            programTitle.waitForExistence(timeout: 30),
            "録画一覧に番組が表示されませんでした")
        attachScreenshot("01-録画一覧")

        // 番組をタップ → 再生画面。通常画面に重ね物がある。
        programTitle.tap()
        let commentOverlay = app.otherElements["player.commentOverlay"]
        let captionOverlay = app.otherElements["player.captionOverlay"]
        XCTAssertTrue(
            commentOverlay.waitForExistence(timeout: 15),
            "通常画面にコメントの重ね物がありません")
        XCTAssertTrue(
            captionOverlay.exists,
            "通常画面に字幕の重ね物がありません")

        // 再生が始まる (再生位置の表示が 0:00 から進む)。
        XCTAssertTrue(
            waitForPlaybackToAdvance(timeout: 40),
            "再生位置が 0:00 から進みませんでした")
        attachScreenshot("02-再生中")

        // 全画面へ移る。移ったあとも重ね物がある。
        let enterButton = app.buttons["全画面にする"]
        tapControlsButton(enterButton, timeout: 20)
        let exitButton = app.buttons["全画面を終了する"]
        XCTAssertTrue(
            exitButton.waitForExistence(timeout: 15),
            "全画面へ移れませんでした")
        XCTAssertTrue(
            commentOverlay.exists,
            "全画面にコメントの重ね物がありません")
        XCTAssertTrue(
            captionOverlay.exists,
            "全画面に字幕の重ね物がありません")
        attachScreenshot("03-全画面")

        // 全画面を終える。通常画面に重ね物が戻っている。
        tapControlsButton(exitButton, timeout: 20)
        XCTAssertTrue(
            waitForExistenceWithControls(enterButton, timeout: 15),
            "通常画面へ戻れませんでした")
        XCTAssertTrue(
            commentOverlay.exists,
            "通常画面にコメントの重ね物が戻っていません")
        XCTAssertTrue(
            captionOverlay.exists,
            "通常画面に字幕の重ね物が戻っていません")
        attachScreenshot("04-通常画面へ復帰")
    }

    /// 再生位置の表示が 0:00 から進むまで待つ。表示は操作帯の中にあり、
    /// 操作帯が隠れている間は要素として見つからないため、そのときは
    /// 映像をタップして操作帯を出し直す。
    private func waitForPlaybackToAdvance(timeout: TimeInterval) -> Bool {
        let timeLabel = app.descendants(matching: .any)["player.currentTime"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if timeLabel.exists {
                if timeLabel.label != "0:00" { return true }
            } else {
                tapVideoArea()
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        return false
    }

    /// 要素が出るまで待つ。出ない間は、操作帯が隠れているせいとみて
    /// 映像をタップして出し直す。
    private func waitForExistenceWithControls(
        _ element: XCUIElement, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            tapVideoArea()
            Thread.sleep(forTimeInterval: 0.7)
        }
        return element.exists
    }

    /// 操作帯のボタンを押す。隠れていて押せないときは、映像をタップ
    /// して操作帯を出してから押し直す。
    private func tapControlsButton(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            if !element.exists {
                tapVideoArea()
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        XCTFail("ボタンが押せる状態になりませんでした")
    }

    /// 映像の上の方をタップする (操作帯の出し入れの切り替え)。
    /// 字幕の重ね物は映像の枠いっぱいに広がっているので、その枠を
    /// 基準にすると通常画面でも全画面でも映像の内側を指せる。
    private func tapVideoArea() {
        let overlay = app.otherElements["player.captionOverlay"]
        overlay.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    /// 失敗したときの切り分け用に、節目で画面写真を残す。
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
