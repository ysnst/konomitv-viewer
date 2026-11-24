import UIKit
import WebKit

/// データ放送の重ね合わせを担う係。
///
/// 同梱した土台のページ (DataBroadcast/index.html) を透明な WebView で開き、
/// その中で Web 版と同じデータ放送ブラウザ (web-bml) を動かす。映像の要素は
/// 空にしておくため、映像の場所は切り抜かれて透明な穴になり、下に置いた
/// ネイティブの映像が見える (重ね合わせの検証で実機確認済み)。
/// 材料 (PSI/SI アーカイブデータ) の受け取りと解き方はページ側のつなぎ
/// (bml-main.js) が行い、材料の口はアプリ内の中継経由の URL を渡す。
/// 双方向 (ネット接続) も、つなぎがアプリ内の中継経由でサーバー側の
/// 代理の口へつなぐ。
///
/// データ放送の保存データ (NVRAM) は、画面側の保存領域がアプリの
/// 再起動をまたいで残る保証が無いため、つなぎが読み書きを写してきて、
/// アプリ側 (SettingsStore) に控える。開始時には控えを渡して画面側へ
/// 流し込む。
///
/// 呼び出し側 (生放送の再生画面) は、prepareWebView() で得た WebView を
/// 映像の真上に組み込み、開始・終了とリモコンのキー送信をここへ頼む。
/// 状態 (読み込み中・データ放送の有無・失敗) は onStatus にキー文字列で
/// 届くので、表示は呼び出し側の知らせ表示に任せる。
/// 映像の窓 (データ放送の文書が映像用に開けている穴) の場所は
/// onVideoRect に、WebView の表示範囲に対する割合の四角で届く。
/// 呼び出し側はこれで字幕の重ね物を窓の中に収める。nil は
/// 「窓の指定なし (字幕は映像全体に戻す)」。
final class DataBroadcastOverlay: NSObject {
    /// 状態の知らせ。届く値は "loading" / "loaded" / "available" /
    /// "unavailable" / "error" / "netbusy" / "netidle" のいずれか。
    var onStatus: ((String) -> Void)?

    /// 映像の窓の場所の知らせ。届く四角は、WebView の表示範囲に
    /// 対する割合 (左・上・幅・高さがそれぞれ 0〜1)。
    /// 文書が開くたびと窓が変わるたびに届き、データ放送を止めた
    /// ときと見えなくなったときは nil が届く。
    var onVideoRect: ((CGRect?) -> Void)?

    /// 開始時にページ側のつなぎへ渡す決め事。
    struct StartConfig {
        /// 双方向 (ネット接続) の許可。オフのときは一切つながない。
        var internetEnabled: Bool
        /// お住まいの郵便番号 (「000-0000」。未設定は空)。
        var zipCode: String
        /// お住まいの都道府県 (Web 版の選択肢の値。未設定は空)。
        var prefecture: String
        /// 双方向の通信に使うアプリ内の中継の向き先
        /// (「http://127.0.0.1:ポート」まで)。中継が使えないときは nil で、
        /// その場合は双方向の通信は失敗の形になる。
        var proxyBase: String?
        /// 保存データのアプリ側の控え。nil は「まだ控えが無い」
        /// (初回は画面側の保存領域から吸い上げる)。
        var nvram: [String: String]?
    }

    deinit {
        // 後片付けの呼び忘れへの備え: 受け口の登録だけは外しておく
        // (現行の呼び出し側は必ず teardown() を呼ぶ)。
        if let webView {
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlStatus")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlNvram")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlVideoRect")
        }
    }

    private(set) var webView: WKWebView?
    private var pageLoaded = false
    private var pendingStart: (psiURL: URL, serviceID: Int?, config: StartConfig)?

    /// WebView を用意する (まだなら作って土台のページを読み込む)。
    /// 透明化し、タッチは受けない (操作はリモコンのパネルから行うため、
    /// 映像へのタップの邪魔をしない)。
    func prepareWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "bmlStatus")
        configuration.userContentController.add(self, name: "bmlNvram")
        configuration.userContentController.add(self, name: "bmlVideoRect")
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
    func start(psiURL: URL, serviceID: Int?, config: StartConfig) {
        _ = prepareWebView()
        pendingStart = (psiURL, serviceID, config)
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
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlNvram")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "bmlVideoRect")
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
        let start = pendingStart.config
        var config: [String: Any] = [
            "psiUrl": pendingStart.psiURL.absoluteString,
            "internetEnabled": start.internetEnabled,
            "zipCode": start.zipCode,
            "prefecture": start.prefecture,
        ]
        if let serviceID = pendingStart.serviceID {
            config["serviceId"] = serviceID
        }
        if let proxyBase = start.proxyBase {
            config["proxyBase"] = proxyBase
        }
        if let nvram = start.nvram {
            config["nvram"] = nvram
            config["hasNvram"] = true
        } else {
            config["hasNvram"] = false
        }
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            // 変換に失敗したら、無言で始めないままにせず失敗を知らせる。
            onStatus?("error")
            return
        }
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
        if message.name == "bmlStatus", let status = message.body as? String {
            onStatus?(status)
            return
        }
        // 保存データの写し (キー → 値の辞書が丸ごと届く)。アプリ側の
        // 控えとして保存する。
        if message.name == "bmlNvram", let raw = message.body as? [String: Any] {
            // 文字列でない値が混じっていても、その値だけを除いて
            // 保存する (保存全体を黙って捨てないため)。
            var nvram: [String: String] = [:]
            for (key, value) in raw {
                if let string = value as? String { nvram[key] = string }
            }
            SettingsStore.shared.dataBroadcastingNvram = nvram
            return
        }
        // 映像の窓の場所 (割合の四角)。本文が辞書でないとき
        // (ページ側が null を送ったとき) は、指定なしとして渡す。
        if message.name == "bmlVideoRect" {
            if let rect = message.body as? [String: Any],
               let left = (rect["left"] as? NSNumber)?.doubleValue,
               let top = (rect["top"] as? NSNumber)?.doubleValue,
               let width = (rect["width"] as? NSNumber)?.doubleValue,
               let height = (rect["height"] as? NSNumber)?.doubleValue {
                onVideoRect?(CGRect(x: left, y: top, width: width, height: height))
            } else {
                onVideoRect?(nil)
            }
        }
    }
}
