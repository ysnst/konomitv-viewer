import Foundation
import Network

/// アプリ内の中継 (VLCKit で再生する経路用: 録画の H.265 / HEVC と生放送)。
///
/// VLCKit で行う再生には、取りに行く処理へ任意のヘッダーを付ける
/// 公式の入口が無い。メディアのオプションで付ける書き方
/// (":http-header") は、VLC 3.0 の HTTP の取りに行く部品 (新旧とも) の
/// 登録済みオプションに存在せず、HLS の分割ファイルを取る側
/// (adaptive) が読むのも http-user-agent と http-referrer だけのため、
/// Cloudflare Access の合言葉 (サービストークンのヘッダー) が届かない。
/// そのため、外回線では合言葉なしで弾かれて再生が始まらない
/// (録画の H.265 は 0.24 で、生放送は 0.25 で実機確認済み。通常画質の
/// AVPlayer 経路は、指定したヘッダーがプレイリストと分割ファイルの
/// 両方に付くため外でも流れる)。
///
/// そこで、端末内 (127.0.0.1) に小さな中継を置き、VLCKit には中継の
/// URL を渡す。中継は元のサーバーへ合言葉付きで取りに行き、
/// プレイリストの中の分割ファイルの URL を中継経由に書き換えてから
/// VLCKit に返す。これで分割ファイルも必ず合言葉付きで取られる。
/// 生放送 (MPEG-TS の流しっぱなし) はプレイリストではないので書き換えは
/// せず、届いた分からそのまま流し続ける。
/// 中継が立ち上がっていないときは nil を返し、呼び出し側は元の URL で
/// 再生する (従来の動きに落ちる)。
final class StreamRelayServer {
    static let shared = StreamRelayServer()

    /// 中継の待ち受けと接続処理を流すキュー (直列)。
    fileprivate let queue = DispatchQueue(
        label: "jp.tatsuya0902.konomitv.viewer.stream-relay")
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var connections: [ObjectIdentifier: RelayConnection] = [:]

    /// 字幕の抜き取り口 (録画の H.265 / HEVC 再生中だけ、再生画面が登録する)。
    /// 中継を通るプレイリストと区切りファイルから、字幕表示に必要な材料
    /// (区切りの長さと、区切りファイルの中の字幕の包み) を拾って渡す。
    /// 再生そのもの (VLCKit への受け渡し) には一切触れない。
    struct CaptionTap {
        /// 対象の録画の経路の目印 ("/api/streams/video/{録画ID}/")。
        let pathMarker: String
        /// プレイリストを受け取ったとき (区切りの長さの一覧、順番どおり)。
        let onPlaylist: ([Double]) -> Void
        /// 区切りファイルを受け取り終わったとき
        /// (区切りの番号・字幕の包み・区切りの先頭の映像の時刻印)。
        let onSegment: (Int, [TSID3Extractor.Packet], Int64?) -> Void
    }

    private var captionTap: CaptionTap?

    /// 字幕の抜き取り口 (生放送用。生放送の再生画面だけが登録する)。
    /// 生放送の流れは終わりが無いため、区切りファイルの形ではなく、
    /// 届いた字幕の包みを少しずつ渡す。あわせて、流れの最初の映像の
    /// 時刻印 (位置合わせの基準) と最新の映像の時刻印 (先端の位置) も渡す。
    struct LiveCaptionTap {
        /// 対象の生放送の経路の目印 ("/api/streams/live/{チャンネル}/")。
        let pathMarker: String
        /// 字幕の包みが取り出せたとき (包み・最初の映像の時刻印・
        /// 最新の映像の時刻印)。包みが空でも、先端の位置が進んだときは
        /// 呼ばれる (先端を知らせるため)。
        let onPackets: ([TSID3Extractor.Packet], Int64?, Int64?) -> Void
    }

    private var liveCaptionTap: LiveCaptionTap?

    private init() {}

    /// 字幕の抜き取り口を登録する (nil で解除)。
    /// 中継のキューの外から呼ぶこと。
    func setCaptionTap(_ tap: CaptionTap?) {
        queue.async { [weak self] in self?.captionTap = tap }
    }

    /// 現在の抜き取り口。中継のキューの上で呼ぶこと。
    fileprivate func currentCaptionTap() -> CaptionTap? { captionTap }

    /// 生放送用の字幕の抜き取り口を登録する (nil で解除)。
    /// 中継のキューの外から呼ぶこと。
    func setLiveCaptionTap(_ tap: LiveCaptionTap?) {
        queue.async { [weak self] in self?.liveCaptionTap = tap }
    }

    /// 現在の生放送用の抜き取り口。中継のキューの上で呼ぶこと。
    fileprivate func currentLiveCaptionTap() -> LiveCaptionTap? { liveCaptionTap }

    /// 中継を立ち上げる (まだなら)。何度呼ばれてもよい。
    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            let parameters = NWParameters.tcp
            // 端末の外からは受け付けない (同じ端末内だけ)。
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters, on: .any) else { return }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.port = listener.port
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: self.queue)
        }
    }

    /// 元の URL に対応する中継の URL。経路 (パスとクエリ) は元のまま、
    /// 向き先だけ 127.0.0.1 の中継に替えたもの。
    /// 中継がまだ立ち上がっていない・元の URL が http(s) でない場合は nil。
    /// 中継のキューの外から呼ぶこと (キュー内からは relayURLOnQueue を使う)。
    func relayURL(for originURL: URL) -> URL? {
        startIfNeeded()
        // port は中継のキューで書かれるため、同期して読む。
        return queue.sync { relayURLOnQueue(for: originURL) }
    }

    /// relayURL の中身。中継のキューの上で呼ぶこと。
    fileprivate func relayURLOnQueue(for originURL: URL) -> URL? {
        guard originURL.scheme == "http" || originURL.scheme == "https" else { return nil }
        guard let port,
              let originComponents = URLComponents(url: originURL, resolvingAgainstBaseURL: false)
        else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port.rawValue)
        components.percentEncodedPath = originComponents.percentEncodedPath
        components.percentEncodedQuery = originComponents.percentEncodedQuery
        return components.url
    }

    private func accept(_ connection: NWConnection) {
        let relay = RelayConnection(connection: connection, server: self, queue: queue)
        connections[ObjectIdentifier(relay)] = relay
        relay.start()
    }

    fileprivate func remove(_ relay: RelayConnection) {
        connections.removeValue(forKey: ObjectIdentifier(relay))
    }

    /// 中継が受けた経路 (パス+クエリ) から、元のサーバーの URL を組み立てる。
    /// 経路には接続先 URL のパス部分がそのまま入っているため、
    /// スキームとホストだけを接続先から補う。
    fileprivate static func originURL(base: URL, target: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let prefix = components.url?.absoluteString else { return nil }
        return URL(string: prefix + target)
    }
}

/// 中継の接続1つ分。VLCKit からの GET を受け、元のサーバーへ合言葉付きで
/// 取りに行き、応答をそのまま (プレイリストだけは中身を書き換えて) 返す。
/// 応答の区切りは、プレイリストは長さを明示し、それ以外はチャンク形式で
/// 流す。接続は1回ごとに閉じる (VLCKit は必要に応じて張り直す)。
/// GET のほかに POST も受ける (データ放送の双方向の送信が、サーバー側の
/// 代理の口へ POST で送るため)。POST は本体ごと元のサーバーへ渡す。
private final class RelayConnection: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let server: StreamRelayServer
    private let queue: DispatchQueue

    private var requestBuffer = Data()
    /// 要求の頭 (空行まで読み切った時点で確定する) と、本体の集まり具合。
    /// POST の本体は頭の後に続くため、長さがそろうまで受け続ける。
    private var requestHead: String?
    private var requestBody = Data()
    private var expectedBodyLength = 0
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var originURL: URL?
    private var isPlaylist = false
    private var isLiveStream = false
    /// 字幕の抜き取り (この接続が対象の経路のときだけ値が入る)。
    private var captionTap: StreamRelayServer.CaptionTap?
    private var captionSegmentSequence: Int?
    private var captionExtractor: TSID3Extractor?
    /// 字幕の抜き取り (生放送用。この接続が生放送の流れで、対象の
    /// チャンネルのときだけ値が入る)。
    private var liveCaptionTap: StreamRelayServer.LiveCaptionTap?
    private var liveCaptionExtractor: TSID3Extractor?
    /// 生放送の字幕で、最後に知らせた先端の映像の時刻印。
    private var liveCaptionLastEdge: Int64?
    private var playlistBody = Data()
    private var headSent = false
    private var finished = false
    /// 送り終わっていない量 (詰まり具合の目安)。受け取りを止める・再開する
    /// 判定に使う。
    private var pendingBytes = 0
    private var taskSuspended = false

    init(connection: NWConnection, server: StreamRelayServer, queue: DispatchQueue) {
        self.connection = connection
        self.server = server
        self.queue = queue
        super.init()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.cleanup()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest()
    }

    // MARK: - 要求の受け取り

    /// 要求の頭 (空行まで) を読み切り、POST の場合は本体 (頭に書かれた
    /// 長さの分) も読み切ってから処理する。
    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if self.requestHead == nil {
                    self.requestBuffer.append(data)
                    guard let headEnd = self.requestBuffer.range(of: Data("\r\n\r\n".utf8)) else {
                        if self.requestBuffer.count > 65536 {
                            self.finish()
                            return
                        }
                        if error != nil || isComplete {
                            self.finish()
                            return
                        }
                        self.receiveRequest()
                        return
                    }
                    let headData = self.requestBuffer.subdata(in: 0 ..< headEnd.lowerBound)
                    self.requestHead = String(decoding: headData, as: UTF8.self)
                    // 頭の後に同じ便で届いていた分は、本体の先頭として引き継ぐ。
                    self.requestBody = self.requestBuffer.subdata(in: headEnd.upperBound ..< self.requestBuffer.count)
                    self.requestBuffer = Data()
                    self.expectedBodyLength = Self.contentLength(from: self.requestHead ?? "")
                } else {
                    self.requestBody.append(data)
                }
                if self.requestBody.count >= self.expectedBodyLength, let head = self.requestHead {
                    let body = Data(self.requestBody.prefix(self.expectedBodyLength))
                    self.handleRequest(head: head, body: body)
                    return
                }
                // 本体が際限なく届くような要求は受け付けない (上限は概ね 1MB)。
                if self.requestBody.count > 1_000_000 {
                    self.finish()
                    return
                }
            }
            if error != nil || isComplete {
                self.finish()
                return
            }
            self.receiveRequest()
        }
    }

    /// 要求の頭から、本体の長さ (Content-Length) を取り出す。無ければ 0。
    private static func contentLength(from head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                return Int(lower.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func handleRequest(head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { finish(); return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { finish(); return }
        // GET は再生と材料の取りに行き、POST はデータ放送の双方向の
        // 送信 (サーバー側の代理の口宛て) で使う。それ以外は受けない。
        let method = String(parts[0])
        guard method == "GET" || method == "POST" else {
            respondSimple(status: 405)
            return
        }
        let target = String(parts[1])
        guard let base = SettingsStore.shared.baseURL,
              let origin = StreamRelayServer.originURL(base: base, target: target) else {
            respondSimple(status: 502)
            return
        }
        originURL = origin
        let pathPart = target.split(separator: "?").first.map(String.init) ?? target
        isPlaylist = pathPart.hasSuffix(".m3u8") || pathPart.contains("playlist")
        // 生放送の流れは終わりが無いので、受け取り全体の上限を付けると
        // 途中で切れてしまう (下の session の設定で使う)。
        isLiveStream = pathPart.contains("/api/streams/live/")

        // 字幕の抜き取り (登録があり、この接続が対象の録画の経路のときだけ)。
        // プレイリストでは区切りの長さを、区切りファイルでは中身から
        // 字幕の包みを拾う。どちらも受け渡しのついでに読むだけで、
        // 応答そのものは変えない。
        if let tap = server.currentCaptionTap(), target.contains(tap.pathMarker) {
            captionTap = tap
            if !isPlaylist, pathPart.hasSuffix("/segment") {
                captionSegmentSequence = Self.sequenceNumber(from: target)
                if captionSegmentSequence != nil {
                    captionExtractor = TSID3Extractor()
                }
            }
        }

        // 字幕の抜き取り (生放送用。登録があり、この接続が対象の
        // チャンネルの生放送の流れのときだけ)。流れのついでに読み取る
        // だけで、応答そのものは変えない。
        if isLiveStream, let liveTap = server.currentLiveCaptionTap(),
           target.contains(liveTap.pathMarker) {
            liveCaptionTap = liveTap
            liveCaptionExtractor = TSID3Extractor()
        }

        var request = URLRequest(url: origin)
        // POST の場合は、本体と中身の形式をそのまま元のサーバーへ渡す
        // (データ放送の双方向の送信)。
        if method == "POST" {
            request.httpMethod = "POST"
            request.httpBody = body
            if let typeLine = lines.first(where: { $0.lowercased().hasPrefix("content-type:") }) {
                let value = String(typeLine.dropFirst("content-type:".count))
                    .trimmingCharacters(in: .whitespaces)
                request.setValue(value, forHTTPHeaderField: "Content-Type")
            }
        }
        // 認証の合言葉はここで付ける (中継の肝)。
        for (key, value) in SettingsStore.shared.serverAuthHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // 範囲指定はそのまま元のサーバーへ渡す。
        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }) {
            let value = String(rangeLine.dropFirst("range:".count))
                .trimmingCharacters(in: .whitespaces)
            request.setValue(value, forHTTPHeaderField: "Range")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        // 受け取り全体の上限。録画は1時間で十分だが、生放送は終わりが
        // 無いので、上限が短いと見ている途中で切れてしまう。
        // 生放送だけ上限を1週間に広げる (実質、時間では切らない)。
        config.timeoutIntervalForResource = isLiveStream ? 7 * 24 * 3600 : 3600
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    // MARK: - URLSession の受け取り (元のサーバーから)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        if isPlaylist {
            // プレイリストは全部受けてから書き換えて返すので、頭は後で送る。
            completionHandler(.allow)
            return
        }
        sendHead(status: http.statusCode, headers: http.allHeaderFields, chunked: true)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isPlaylist {
            playlistBody.append(data)
            return
        }
        // 字幕の抜き取り: 区切りファイルの中身は、流すついでに読み取る。
        captionExtractor?.feed(data)
        // 字幕の抜き取り (生放送用): 流れのついでに読み取り、取り出せた
        // 包みを少しずつ渡す。
        if let liveCaptionExtractor {
            liveCaptionExtractor.feed(data)
            reportLiveCaptionPackets(final: false)
        }
        sendChunk(data)
        // 送りが追いついていないときは、受け取りを一時止めて溜め込みすぎない。
        if pendingBytes > 1_000_000, !taskSuspended {
            task?.suspend()
            taskSuspended = true
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let http = task.response as? HTTPURLResponse
        session.finishTasksAndInvalidate()
        self.session = nil
        // 字幕の抜き取り: 区切りファイルを受け取り終わったら、取り出した
        // 字幕の包みを渡す (失敗した受け取りでも、読めた分は渡す)。
        if let captionTap, let captionSegmentSequence, let captionExtractor {
            captionExtractor.finish()
            captionTap.onSegment(captionSegmentSequence,
                                 captionExtractor.captionPackets,
                                 captionExtractor.videoFirstPTS)
        }
        // 字幕の抜き取り (生放送用): 読みかけを確定させ、残りの包みを渡す。
        if liveCaptionExtractor != nil {
            liveCaptionExtractor?.finish()
            reportLiveCaptionPackets(final: true)
        }
        if isPlaylist {
            if error == nil, let http {
                // 字幕の抜き取り: 区切りの長さの一覧を渡す
                // (書き換え前の本文から読む)。
                if let captionTap {
                    captionTap.onPlaylist(Self.playlistDurations(from: playlistBody))
                }
                let rewritten = rewritePlaylist(playlistBody)
                sendHead(status: http.statusCode, headers: http.allHeaderFields,
                         chunked: false, contentLength: rewritten.count)
                sendData(rewritten) { [weak self] in self?.finish() }
            } else if !headSent {
                respondSimple(status: 502)
            } else {
                finish()
            }
            return
        }
        if headSent {
            sendData(Data("0\r\n\r\n".utf8)) { [weak self] in self?.finish() }
        } else if error != nil {
            respondSimple(status: 502)
        } else {
            finish()
        }
    }

    /// 生放送の字幕の抜き取り: 取り出せた包みと、流れの先端の位置を渡す。
    /// 包みが無いときは、先端が 0.5 秒以上進んだときだけ知らせる
    /// (映像の包みごとに知らせると、渡し先が追いつかなくなるため)。
    private func reportLiveCaptionPackets(final: Bool) {
        guard let liveCaptionTap, let liveCaptionExtractor else { return }
        let drained = liveCaptionExtractor.drainCaptionPackets()
        let edge = liveCaptionExtractor.videoLatestPTS
        var edgeAdvanced = false
        if let edge {
            if let last = liveCaptionLastEdge {
                edgeAdvanced = edge - last >= 45000 || edge < last
            } else {
                edgeAdvanced = true
            }
        }
        guard !drained.isEmpty || final || edgeAdvanced else { return }
        liveCaptionLastEdge = edge
        liveCaptionTap.onPackets(drained,
                                 liveCaptionExtractor.videoFirstPTS,
                                 edge)
    }

    // MARK: - 応答の送り出し (VLCKit へ)

    /// 応答の頭 (ステータス行とヘッダー) を送る。
    /// 区切り方は、流すときはチャンク形式、長さが分かるときはその明示。
    private func sendHead(status: Int, headers: [AnyHashable: Any], chunked: Bool, contentLength: Int = 0) {
        headSent = true
        var lines = ["HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))"]
        // 中継で付け替えるもの・区切りに使うものは、元の値を使わない。
        let skipped: Set<String> = [
            "connection", "keep-alive", "transfer-encoding", "content-length",
            "trailer", "te", "proxy-connection",
        ]
        var hasCORSHeader = false
        for (key, value) in headers {
            guard let name = key as? String, !skipped.contains(name.lowercased()) else { continue }
            if name.lowercased() == "access-control-allow-origin" {
                hasCORSHeader = true
            }
            lines.append("\(name): \(value)")
        }
        // データ放送の検証ページ (アプリ同梱の WebView) が材料の口を
        // fetch で取りに行けるよう、サーバー側に印が無いときは足す。
        // 中継は端末の中だけに閉じているため、相手を問わない印で問題ない。
        // 再生側 (VLCKit) はこの印を見ないので影響しない。
        if !hasCORSHeader {
            lines.append("Access-Control-Allow-Origin: *")
        }
        if chunked {
            lines.append("Transfer-Encoding: chunked")
        } else {
            lines.append("Content-Length: \(contentLength)")
        }
        lines.append("Connection: close")
        sendData(Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8))
    }

    /// チャンク形式で1塊送る。
    private func sendChunk(_ data: Data) {
        var frame = Data(String(format: "%x\r\n", data.count).utf8)
        frame.append(data)
        frame.append(Data("\r\n".utf8))
        sendData(frame)
    }

    private func sendData(_ data: Data, completion: (() -> Void)? = nil) {
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pendingBytes -= data.count
            if self.taskSuspended, self.pendingBytes < 500_000 {
                self.task?.resume()
                self.taskSuspended = false
            }
            if error != nil {
                self.finish()
                return
            }
            completion?()
        })
    }

    /// 短い固定の応答 (エラー時) を送って閉じる。
    private func respondSimple(status: Int) {
        guard !finished else { return }
        headSent = true
        let head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
            + "Content-Length: 0\r\nConnection: close\r\n\r\n"
        sendData(Data(head.utf8)) { [weak self] in self?.finish() }
    }

    // MARK: - 字幕の抜き取りの材料読み

    /// 要求の経路 (パス+クエリ) から、区切りの番号 (sequence=...) を取り出す。
    private static func sequenceNumber(from target: String) -> Int? {
        guard let query = target.split(separator: "?", maxSplits: 1).last else { return nil }
        for part in query.split(separator: "&") {
            if part.hasPrefix("sequence=") {
                return Int(part.dropFirst("sequence=".count))
            }
        }
        return nil
    }

    /// プレイリストの本文から、区切りの長さ (#EXTINF の値) を順番に取り出す。
    private static func playlistDurations(from body: Data) -> [Double] {
        guard let text = String(data: body, encoding: .utf8) else { return [] }
        var durations: [Double] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#EXTINF:") else { continue }
            let value = trimmed.dropFirst("#EXTINF:".count).split(separator: ",").first ?? ""
            if let seconds = Double(value) {
                durations.append(seconds)
            }
        }
        return durations
    }

    // MARK: - プレイリストの書き換え

    /// プレイリスト内の URL (行の URL と、タグの URI="..." の両方) を、
    /// 元のサーバー基準で絶対化してから中継経由に書き換える。
    /// これで分割ファイルも中継を通り、合言葉付きで取られる。
    private func rewritePlaylist(_ body: Data) -> Data {
        guard let originURL, let text = String(data: body, encoding: .utf8) else { return body }
        let lines = text.components(separatedBy: "\n").map { rawLine -> String in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") {
                return rewriteTagLine(line, base: originURL)
            }
            if line.isEmpty { return line }
            return relayMappedURL(line, base: originURL)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func rewriteTagLine(_ line: String, base: URL) -> String {
        var result = ""
        var rest = line[...]
        while let open = rest.range(of: "URI=\"") {
            guard let close = rest.range(of: "\"", range: open.upperBound..<rest.endIndex) else { break }
            result += rest[..<open.upperBound]
            result += relayMappedURL(String(rest[open.upperBound..<close.lowerBound]), base: base)
            rest = rest[close.lowerBound...]
        }
        result += rest
        return result
    }

    private func relayMappedURL(_ uri: String, base: URL) -> String {
        // この処理は中継のキューの上で動いているため、キューの外向けの
        // relayURL (同期読み) ではなくキュー内向けを使う。
        guard let resolved = URL(string: uri, relativeTo: base)?.absoluteURL,
              resolved.scheme == "http" || resolved.scheme == "https",
              let relay = server.relayURLOnQueue(for: resolved) else { return uri }
        return relay.absoluteString
    }

    // MARK: - 後片付け

    private func finish() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        connection.cancel()
        server.remove(self)
    }

    private func cleanup() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        server.remove(self)
    }
}
