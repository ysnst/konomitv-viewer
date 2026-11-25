import XCTest

/// 自動テスト (スモークテスト)。仮サーバー (SmokeTests/stub_server.py) の
/// 材料でアプリを起動し、「録画一覧 → 再生開始 → 全画面 → 通常画面へ戻る」
/// を一巡して、再生の開始と、全画面でも流れるコメントと字幕の重ね物が
/// 付いて来ていることを確認する。
///
/// 接続先は起動時の引数で仮サーバーへ向ける (設定の保存キー viewer_url と
/// 同じ仕組み。通常の起動には影響しない)。
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
        let timeLabel = app.descendants(matching: .any)["player.currentTime"]
        XCTAssertTrue(
            timeLabel.waitForExistence(timeout: 15),
            "再生位置の表示が見つかりません")
        let advanced = expectation(
            for: NSPredicate(format: "label != '0:00'"),
            evaluatedWith: timeLabel, handler: nil)
        wait(for: [advanced], timeout: 30)
        attachScreenshot("02-再生中")

        // 全画面へ移る。移ったあとも重ね物がある。
        let enterButton = app.buttons["全画面にする"]
        XCTAssertTrue(
            enterButton.waitForExistence(timeout: 10),
            "全画面ボタンが見つかりません")
        tapElement(enterButton)
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
        tapElement(exitButton)
        XCTAssertTrue(
            enterButton.waitForExistence(timeout: 15),
            "通常画面へ戻れませんでした")
        XCTAssertTrue(
            commentOverlay.exists,
            "通常画面にコメントの重ね物が戻っていません")
        XCTAssertTrue(
            captionOverlay.exists,
            "通常画面に字幕の重ね物が戻っていません")
        attachScreenshot("04-通常画面へ復帰")
    }

    /// 操作帯が隠れていてボタンが押せないときは、映像をタップして
    /// 操作帯を出してから押す。
    private func tapElement(_ element: XCUIElement) {
        if !element.isHittable {
            tapVideoArea()
            let hittable = expectation(
                for: NSPredicate(format: "hittable == true"),
                evaluatedWith: element, handler: nil)
            wait(for: [hittable], timeout: 8)
        }
        element.tap()
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
