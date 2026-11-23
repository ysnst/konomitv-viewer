import UIKit
import WebKit

/// データ放送の重ね合わせ (検証用) を担う係。
///
/// 同梱した土台のページ (DataBroadcast/index.html) を透明な WebView で開き、
/// その中で Web 版と同じデータ放送ブラウザ (web-bml) を動かす。映像の要素は
/// 空にしておくため、映像の場所は切り抜かれて透明な穴になり、下に置いた
/// ネイティブの映像が見えるはず、という仮説を実機で確かめるための作り。
/// 材料 (PSI/SI アーカイブデータ) の受け取りと解き方はページ側のつなぎ
/// (bml-main.js) が行い、材料の口はアプリ内の中継経由の URL を渡す。
///
/// 呼び出し側 (生放送の再生画面) は、prepareWebView() で得た WebView を
/// 映像の真上に組み込み、開始・終了とリモコンのキー送信をここへ頼む。
/// 状態 (読み込み中・データ放送の有無・失敗) は onStatus にキー文字列で
/// 届くので、表示は呼び出し側の知らせ表示に任せる。
final class DataBroadcastOverlay: NSObject {
    /// 状態の知らせ。届く値は "loading" / "loaded" / "available" /
    /// "unavailable" / "error" のいずれか。
    var onStatus: ((String) -> Void)?

    private(set) var webView: WKWebView?
    private var pageLoaded = false
    private var pendingStart: (psiURL: URL, serviceID: Int?)?

    /// WebView を用意する (まだなら作って土台のページを読み込む)。
    /// 透明化し、タッチは受けない (操作はリモコンのパネルから行うため、
    /// 映像へのタップの邪魔をしない)。
    func prepareWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "bmlStatus")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView = webView
        if let folderURL = Bundle.main.url(forResource: "DataBroadcast", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "DataBroadcast") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: folderURL)
        } else {
            onStatus?("error")
        }
        return webView
    }

    /// データ放送を始める。土台のページの読み込みが終わっていなければ、
    /// 終わり次第始める。
    func start(psiURL: URL, serviceID: Int?) {
        _ = prepareWebView()
        pendingStart = (psiURL, serviceID)
        runPendingStartIfReady()
    }

    /// データ放送を止める (ページ側の解読と描画を破棄する)。
    func stop() {
        pendingStart = nil
        webView?.evaluateJavaScript("window.BMLSpike && window.BMLSpike.stop()")
    }

    /// WebView を手放す (画面を離れるときに呼ぶ)。
    func teardown() {
        stop()
        if let webView {
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlStatus")
            webView.removeFromSuperview()
        }
        webView = nil
        pageLoaded = false
    }

    /// リモコンのキーを送る (ARIB のキーコード)。
    func sendKey(_ aribKeyCode: Int) {
        webView?.evaluateJavaScript("window.BMLSpike && window.BMLSpike.sendKey(\(aribKeyCode))")
    }

    private func runPendingStartIfReady() {
        guard pageLoaded, let pendingStart, let webView else { return }
        self.pendingStart = nil
        var config: [String: Any] = ["psiUrl": pendingStart.psiURL.absoluteString]
        if let serviceID = pendingStart.serviceID {
            config["serviceId"] = serviceID
        }
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.BMLSpike && window.BMLSpike.start(\(json))")
    }
}

extension DataBroadcastOverlay: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        runPendingStartIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onStatus?("error")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onStatus?("error")
    }
}

extension DataBroadcastOverlay: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bmlStatus", let status = message.body as? String else { return }
        onStatus?(status)
    }
}
