import Foundation

/// 生放送の実況コメント1件。一覧の表示と、映像の上に流れる表示の
/// 両方で使う (Web 版の ICommentData に相当)。
struct LiveJikkyoComment {
    /// コメント番号 (自分の投稿は番号が取れないため、時刻から作った値)。
    let id: Int
    /// コメント本文。
    let text: String
    /// 投稿された時刻 (一覧の時刻表示に使う)。
    let date: Date
    /// 投稿者の ID (ニコニコ実況から取り込まれた分は "nicolive:" が付く)。
    let userID: String
    /// プレミアム会員の印 (文字列化したもの。無ければ nil)。
    let premium: String?
    /// 自分が投稿したコメントかどうか。
    let myPost: Bool
    /// 流れる表示の色 ("#RRGGBB")。
    let colorHex: String
    /// 流れる表示の位置 ("top" = 上に固定 / "right" = 流れる / "bottom" = 下に固定)。
    let type: String
    /// 流れる表示の大きさ ("big" / "medium" / "small")。
    let size: String
    /// 流れる表示で出現する位置 (再生画面の仮想の時計の秒)。
    /// 初回にまとめて届く過去コメントでは使わない (一覧にだけ出す)。
    let displayTime: Double

    /// 録画の流れる表示と同じ形に写す (描き手とミュート判定で使う)。
    var asJikkyoComment: JikkyoComment {
        JikkyoComment(time: displayTime, type: type, size: size,
                      color: colorHex, author: userID, text: text)
    }

    /// 一覧の時刻表示 (HH:mm:ss。28時間表記は設定に従う)。
    var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return TimeFormat.apply28HourClock(formatter.string(from: date))
    }
}

/// ニコニコのコメントのコマンド (mail) の読み解きと、色の対応表。
/// Web 版の CommentUtils.parseCommentCommand と同じ読み方をする。
enum NicoCommentCommand {
    /// 色の名前 → "#RRGGBB" (Web 版の対応表どおり)。
    static let colorTable: [String: String] = [
        "white": "#FFEAEA", "red": "#F02840", "pink": "#FD7E80",
        "orange": "#FDA708", "yellow": "#FFE133", "green": "#64DD17",
        "cyan": "#00D4F5", "blue": "#4763FF", "purple": "#D500F9",
        "black": "#1E1310",
        "white2": "#CCCC99", "niconicowhite": "#CCCC99",
        "red2": "#CC0033", "truered": "#CC0033",
        "pink2": "#FF33CC",
        "orange2": "#FF6600", "passionorange": "#FF6600",
        "yellow2": "#999900", "madyellow": "#999900",
        "green2": "#00CC66", "elementalgreen": "#00CC66",
        "cyan2": "#00CCCC",
        "blue2": "#3399FF", "marineblue": "#3399FF",
        "purple2": "#6633CC", "nobleviolet": "#6633CC",
        "black2": "#666666",
    ]

    /// 投稿欄で選べる色 (Web 版の入力欄と同じ8色。名前がそのまま
    /// 送信時の色の指定になる)。
    static let postingColors: [(name: String, hex: String)] = [
        ("white", "#FFEAEA"), ("red", "#F02840"), ("pink", "#FD7E80"),
        ("orange", "#FDA708"), ("yellow", "#FFE133"), ("green", "#64DD17"),
        ("cyan", "#00D4F5"), ("blue", "#4763FF"),
    ]

    /// mail の文字列を、色・位置・大きさに読み解く。
    /// 既定は白・流れる・中 (Web 版と同じ)。
    static func parse(_ mail: String?) -> (colorHex: String, type: String, size: String) {
        var colorHex = "#FFEAEA"
        var type = "right"
        var size = "medium"
        guard let mail else { return (colorHex, type, size) }
        // "184" (匿名の指定) は読み解きの対象から外す (Web 版と同じ)。
        // ただし外すのは単独の語だけにする。文字列の一部として含まれる
        // 場合 (色の指定 "#123184" 等) まで取り除くと、指定が壊れるため。
        let commands = mail.split(separator: " ").filter { $0 != "184" }
        for command in commands {
            let token = String(command)
            if let hex = colorTable[token] {
                colorHex = hex
            } else if token.hasPrefix("#"), token.count == 7,
                      UInt32(token.dropFirst(), radix: 16) != nil {
                colorHex = token.uppercased()
            } else if token == "ue" {
                type = "top"
            } else if token == "naka" {
                type = "right"
            } else if token == "shita" {
                type = "bottom"
            } else if token == "big" || token == "medium" || token == "small" {
                size = token
            }
        }
        return (colorHex, type, size)
    }
}

/// 生放送の実況コメントの土台。サーバーから接続先をもらい、視聴セッション
/// (送信用) とコメントセッション (受信用) の2本の窓口 (WebSocket) を張る。
/// 受けたコメントは、ミュート設定で絞ってから、呼び出し側へ渡す。
/// 流れる表示へ出す分は、映像の遅れの分だけ遅らせて渡す (Web 版が
/// バッファの分だけ待ってから描くのと同じ考え方)。
/// 作りは Web 版の LiveCommentManager の写しで、切断時は3秒ほど待って
/// 張り直す。ニコニコの認証情報はサーバー側が持つため、ここには無い。
///
/// 受け口 (onComments など) はすべて主キューで呼ばれる。
final class LiveCommentSession {
    /// コメントが届いたとき (コメントの並び、初回のまとめかどうか)。
    /// 初回のまとめは一覧にだけ出す分で、流れる表示には出さない。
    var onComments: (([LiveJikkyoComment], Bool) -> Void)?
    /// 知らせ (接続の切断・再接続・送信先の代替の案内など)。
    var onNotice: ((String) -> Void)?
    /// 初期化の失敗の文 (コメントパネルの空表示と投稿欄の無効化に使う)。
    /// 解消したら nil で呼ばれる。
    var onInitFailure: ((String?) -> Void)?
    /// 再生画面の仮想の時計 (秒)。流れる表示の位置合わせに使う。
    var nowProvider: () -> Double = { 0 }
    /// 流れる表示を遅らせる量 (秒)。映像の溜めの量から呼び出し側が決める。
    var delayProvider: () -> Double = { 0 }

    private let channelID: String
    private let urlSession: URLSession
    private var watchTask: URLSessionWebSocketTask?
    private var commentTask: URLSessionWebSocketTask?
    private var keepSeatTimer: Timer?
    private var deliveryTimer: Timer?
    /// 接続先情報 (コメントセッションの向き先など、視聴セッションの
    /// 応答から組み立てるときに参照する)。
    private var websocketInfo: JikkyoWebSocketInfo?
    /// vpos (投稿時の位置) の基準時刻。
    private var vposBaseTime: Date?
    /// 視聴セッションがニコニコ実況側かどうか (制限と文面の出し分け)。
    private var isNicoliveWatchSession = false
    private var commentSessionStarted = false
    /// 初回にまとめて届く過去コメントを受け終えたかどうか。
    private var initialCommentsReceived = false
    private var initialBuffer: [LiveJikkyoComment] = []
    /// 遅らせて渡す待ち行列 (流れる表示の遅れ待ち)。
    private var deliveryQueue: [LiveJikkyoComment] = []
    /// 送信済みで結果待ちの投稿。結果の応答には投稿を識別する
    /// 材料が無いため、同時に結果待ちにできるのは1件だけにする
    /// (複数を待ち行列で対応付けると、遅れて届いた結果が別の
    /// 投稿のものとして扱われてしまうため)。
    private var pendingPost: PendingPost?
    /// まだ送っていない投稿の待ち行列。結果待ちが空いた順に送る。
    private var queuedPosts: [PendingPost] = []
    /// 投稿の結果が時間切れになった後、その接続では投稿しない印。
    /// 遅れて届く結果が残っている可能性のある接続では、それ以上
    /// 送らない。接続を張り直して、新しい接続が開けた時点で外す。
    private var postBlockedUntilReconnect = false
    /// 自分のニコニコユーザー ID とプレミアムかどうか (ユーザー情報から)。
    private var myNiconicoUserID: Int?
    private var myNiconicoPremium: Bool?
    /// 初期化に失敗したときの文。投稿のときにそのまま返す。
    private var initFailureMessage: String?
    private var started = false
    private var destroyed = false
    private var reconnecting = false
    /// 張り直しの途中で接続先情報の取得に失敗した回数
    /// (やり直しの間隔を広げるために数える)。
    private var reconnectFetchFailures = 0
    /// 接続の組み立ての世代。組み立てを始めるたびと止めるたびに進める。
    /// 接続先情報の取得中に画面を離れて戻ると、古い組み立てが後から
    /// 進んで接続が二重に張られてしまうため、古い世代の組み立ては
    /// 途中で打ち切る。
    private var connectGeneration = 0
    /// disconnect の知らせが届いた後かどうか (閉じた合図を二重に扱わない)。
    private var disconnectMessageReceived = false

    private struct PendingPost {
        /// 投稿ごとの印 (結果が来ない投稿の時間切れの判定に使う)。
        let id = UUID()
        let text: String
        /// 送信の材料 (待ち行列に入れてから実際に送るため、送る
        /// ための形のまま持つ)。
        let colorName: String
        let position: String
        /// 送信時に選んだ表示 (自分のコメントを一覧と流れる表示へ
        /// 足すときに使う)。
        let colorHex: String
        let type: String
        let size: String
        let completion: (String?) -> Void
    }

    init(channelID: String) {
        self.channelID = channelID
        // 受け取りの合図はすべて主キューで受ける (状態の扱いを単純にするため)。
        self.urlSession = URLSession(
            configuration: .default, delegate: nil, delegateQueue: .main)
    }

    // MARK: - 開始と終了

    /// 接続を始める。何度呼ばれてもよい (2回目以降は何もしない)。
    func start() {
        guard !started else { return }
        started = true
        destroyed = false
        Task { await self.connect() }
    }

    /// 接続を閉じて止める (画面を離れるとき)。
    func stop() {
        destroyed = true
        started = false
        reconnecting = false
        reconnectFetchFailures = 0
        postBlockedUntilReconnect = false
        // 進んでいる組み立てがあれば無効にする (後から接続が
        // 張られてしまわないため)。
        connectGeneration += 1
        teardownSockets()
    }

    /// 視聴セッションの種類の表示名 (知らせの文に使う)。
    private var sessionTypeName: String {
        isNicoliveWatchSession ? "ニコニコ実況" : "NX-Jikkyo"
    }

    // MARK: - 接続の組み立て

    /// ユーザー情報を取り、接続先情報を取って、視聴セッションを開く。
    private func connect() async {
        // この組み立ての世代を控える。取得の途中で止められたり、
        // 新しい組み立てが始まったりしたら、この組み立ては打ち切る
        // (古い組み立てが進んで接続が二重に張られるのを防ぐ)。
        connectGeneration += 1
        let generation = connectGeneration
        // ユーザー情報 (連携の状態) を先に取る。取れなくても続ける
        // (未ログインでも NX-Jikkyo 側は使えるため)。
        if SettingsStore.shared.isLoggedIn,
           let user = try? await APIClient.shared.fetchCurrentUser() {
            guard generation == connectGeneration, !destroyed else { return }
            myNiconicoUserID = user.niconico_user_id
            myNiconicoPremium = user.niconico_user_premium
        }
        let info: JikkyoWebSocketInfo
        do {
            info = try await APIClient.shared.fetchJikkyoWebSocketInfo(channelID: channelID)
        } catch {
            guard generation == connectGeneration, !destroyed else { return }
            if reconnecting {
                // 張り直しの途中の取得失敗は、一時的な通信の失敗と
                // して、間を広げながら自動でやり直す。ここで諦めると、
                // 窓口は既に片付けられていて次の切断の合図も来ないため、
                // 復旧の機会自体が無くなってしまう。
                reconnectFetchFailures += 1
                let delay = min(30.0, 3.0 * pow(2.0, Double(min(reconnectFetchFailures - 1, 3))))
                reconnecting = false
                scheduleReconnect(after: delay)
                return
            }
            setInitFailure("コメント受信用 WebSocket API の情報を取得できませんでした。")
            reconnecting = false
            return
        }
        guard generation == connectGeneration, !destroyed else { return }
        websocketInfo = info
        guard let nxWatchURL = info.watch_session_url else {
            setInitFailure("このチャンネルはニコニコ実況に対応していません。")
            reconnecting = false
            return
        }
        // 視聴セッションの向き先: 既定は NX-Jikkyo。「可能であれば
        // ニコニコ実況にコメントする」がオンで、ニコニコ実況側の
        // 接続先が取れているときだけ、そちらへ張る (Web 版と同じ)。
        var watchURLString = nxWatchURL
        isNicoliveWatchSession = false
        if SyncedSettingsStore.shared.current.preferPostingToNicolive {
            if let nicoliveURL = info.nicolive_watch_session_url {
                watchURLString = nicoliveURL
                isNicoliveWatchSession = true
            } else if let error = info.nicolive_watch_session_error,
                      SettingsStore.shared.isLoggedIn, myNiconicoUserID != nil {
                // 連携しているのに取れなかったときだけ知らせる
                // (未ログイン・未連携のときは Web 版も出さない)。
                onNotice?("\(error)代わりに NX-Jikkyo にコメントします。")
            }
        }
        guard let watchURL = URL(string: watchURLString) else {
            setInitFailure("コメント受信用 WebSocket API の情報を取得できませんでした。")
            reconnecting = false
            return
        }
        guard generation == connectGeneration, !destroyed else { return }
        openWatchSession(url: watchURL)
    }

    private func setInitFailure(_ message: String) {
        initFailureMessage = message
        onInitFailure?(message)
        // 接続が組み立てられなかったので、待ち行列に残っている
        // 投稿は送れる見込みが無い。失敗として片付ける
        // (結果待ちの分は、片付けの側で扱われる)。
        let posts = queuedPosts
        queuedPosts = []
        for post in posts {
            post.completion("コメントの送信に失敗しました。WebSocket 接続が確立されていません。")
        }
    }

    private func clearInitFailure() {
        guard initFailureMessage != nil else { return }
        initFailureMessage = nil
        onInitFailure?(nil)
    }

    // MARK: - 視聴セッション (送信用)

    private func openWatchSession(url: URL) {
        disconnectMessageReceived = false
        commentSessionStarted = false
        // 張り直しが実って接続が開けたので、予約の印はここで消す。
        // 消さないままだと、成功したあとの切断では「すでに予約済み」と
        // 誤判定されて、二度と張り直されなくなる。
        reconnecting = false
        reconnectFetchFailures = 0
        let task = urlSession.webSocketTask(with: url)
        watchTask = task
        task.resume()
        receiveWatchMessage()
        // 接続が開けたら視聴の開始を送る。URLSession の窓口には
        // 「開けた」の合図が無いため、resume の直後に送る
        // (送信は接続が確立してから実際に行われる)。
        sendWatchJSON(["type": "startWatching", "data": ["reconnect": false]])
        // 新しい接続が開けたので、時間切れによる投稿の停止を外し、
        // 待ち行列に残っている投稿の続きを送る。
        postBlockedUntilReconnect = false
        pumpPostQueue()
    }

    private func sendWatchJSON(_ object: [String: Any]) {
        guard let task = watchTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receiveWatchMessage() {
        guard let task = watchTask else { return }
        task.receive { [weak self] result in
            // 張り直した後の古い接続からの応答は無視する (受け口を
            // 持つ窓口そのもので照合する)。古い接続の結果が、新しい
            // 接続の投稿のものとして扱われてしまうのを防ぐため。
            guard let self, !self.destroyed, self.watchTask === task else { return }
            switch result {
            case .failure:
                self.handleWatchClosed()
            case .success(let message):
                if case .string(let text) = message {
                    self.handleWatchText(text)
                }
                self.receiveWatchMessage()
            }
        }
    }

    private func handleWatchClosed() {
        // disconnect の知らせが先に届いている場合は、そちらで
        // 張り直しの予約が済んでいるため何もしない。
        guard !disconnectMessageReceived else { return }
        let code = watchTask.map { String($0.closeCode.rawValue) } ?? "Error"
        onNotice?("\(sessionTypeName)との接続が切断されました。(Code: \(code))")
        scheduleReconnect(after: 3)
    }

    private func handleWatchText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = message["type"] as? String else { return }
        let payload = message["data"] as? [String: Any] ?? [:]
        switch type {
        case "seat":
            // 座席の維持: keepIntervalSec ごとに keepSeat を送る。
            guard keepSeatTimer == nil,
                  let seconds = (payload["keepIntervalSec"] as? NSNumber)?.doubleValue,
                  seconds > 0 else { return }
            keepSeatTimer = Timer.scheduledTimer(
                withTimeInterval: seconds, repeats: true) { [weak self] _ in
                guard let self, let task = self.watchTask, task.state == .running else {
                    self?.keepSeatTimer?.invalidate()
                    self?.keepSeatTimer = nil
                    return
                }
                self.sendWatchJSON(["type": "keepSeat"])
            }
        case "ping":
            sendWatchJSON(["type": "pong"])
        case "room":
            // NX-Jikkyo 側の応答。コメントセッションの向き先が入っている。
            vposBaseTime = Self.parseISODate(payload["vposBaseTime"] as? String)
            if let server = payload["messageServer"] as? [String: Any],
               let uri = server["uri"] as? String {
                openCommentSession(
                    url: uri,
                    threadID: payload["threadId"] as? String ?? "",
                    postKey: payload["yourPostKey"] as? String)
            }
        case "messageServer":
            // ニコニコ実況側の応答。コメントセッションは常に
            // NX-Jikkyo 側へ張る (Web 版と同じ)。
            vposBaseTime = Self.parseISODate(payload["vposBaseTime"] as? String)
            if let url = websocketInfo?.comment_session_url {
                let hashed = payload["hashedUserId"] as? String
                openCommentSession(
                    url: url, threadID: "",
                    postKey: hashed.map { "nicolive:\($0)" })
            }
        case "postCommentResult":
            resolvePendingPost(error: nil)
        case "error":
            let code = payload["code"] as? String ?? ""
            if code == "COMMENT_POST_NOT_ALLOWED" || code == "INVALID_MESSAGE" {
                // 投稿の失敗は投稿側で扱う (ここでは張り直さない)。
                resolvePendingPost(error: code == "COMMENT_POST_NOT_ALLOWED"
                    ? "コメントが許可されていません。"
                    : "コメント内容が無効です。")
                return
            }
            onNotice?(Self.watchErrorText(code: code, sessionTypeName: sessionTypeName))
            scheduleReconnect(after: 3)
        case "reconnect":
            scheduleReconnect(after: 0)
        case "disconnect":
            disconnectMessageReceived = true
            let reason = payload["reason"] as? String ?? ""
            onNotice?(Self.disconnectReasonText(reason: reason, sessionTypeName: sessionTypeName))
            scheduleReconnect(after: 3)
        default:
            break
        }
    }

    // MARK: - コメントセッション (受信用)

    private func openCommentSession(url: String, threadID: String, postKey: String?) {
        guard !commentSessionStarted, let wsURL = URL(string: url) else { return }
        commentSessionStarted = true
        initialCommentsReceived = false
        initialBuffer = []
        clearInitFailure()
        let task = urlSession.webSocketTask(with: wsURL)
        commentTask = task
        task.resume()
        // コメントの送信を求める (この並びを送らないと届かない。
        // Web 版と同じ内容・同じ順番)。
        let thread: [String: Any] = [
            "version": "20061206",
            "thread": threadID,
            "threadkey": postKey ?? NSNull(),
            "user_id": "",
            "res_from": -100,
        ]
        let request: [[String: Any]] = [
            ["ping": ["content": "rs:0"]],
            ["ping": ["content": "ps:0"]],
            ["thread": thread],
            ["ping": ["content": "pf:0"]],
            ["ping": ["content": "rf:0"]],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: request),
           let text = String(data: data, encoding: .utf8) {
            task.send(.string(text)) { _ in }
        }
        receiveCommentMessage()
    }

    private func receiveCommentMessage() {
        guard let task = commentTask else { return }
        task.receive { [weak self] result in
            // 視聴セッションと同じく、古い接続からの応答は無視する。
            guard let self, !self.destroyed, self.commentTask === task else { return }
            switch result {
            case .failure:
                let code = self.commentTask.map { String($0.closeCode.rawValue) } ?? "Error"
                self.onNotice?("NX-Jikkyo との接続が切断されました。(Code: \(code))")
                self.scheduleReconnect(after: 3)
            case .success(let message):
                if case .string(let text) = message {
                    self.handleCommentText(text)
                }
                self.receiveCommentMessage()
            }
        }
    }

    private func handleCommentText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        // スレッドへの接続結果。0 以外は失敗 (Web 版も記録だけで、
        // 閉じた合図の側で張り直しに任せる)。
        if let thread = message["thread"] as? [String: Any] {
            _ = thread["resultcode"]
            return
        }
        // 初回のまとめの終わりの合図。ここまでの分を一覧へ渡す。
        if let ping = message["ping"] as? [String: Any],
           (ping["content"] as? String) == "rf:0" {
            initialCommentsReceived = true
            let buffered = initialBuffer
            initialBuffer = []
            if !buffered.isEmpty {
                onComments?(buffered, true)
            }
            return
        }
        guard let chat = message["chat"] as? [String: Any] else { return }
        handleChat(chat)
    }

    /// コメント1件を受けて、絞り込みと振り分けを行う。
    private func handleChat(_ chat: [String: Any]) {
        guard let content = chat["content"] as? String, !content.isEmpty else { return }
        let userID = chat["user_id"] as? String ?? ""
        // 自分が投稿したコメントは弾く (投稿の結果の側で一覧へ足すため)。
        // 初回のまとめの中では、自分の分も通常どおり扱う (Web 版と同じ)。
        if (chat["yourpost"] as? NSNumber)?.intValue == 1, initialCommentsReceived {
            return
        }
        if let myID = myNiconicoUserID {
            // "nicolive:" は先頭の接頭辞としてだけ取り除いて比べる
            // (ID の途中に同じ文字列があっても壊さないため)。
            var strippedID = userID
            if strippedID.hasPrefix("nicolive:") {
                strippedID = String(strippedID.dropFirst("nicolive:".count))
            }
            if strippedID == String(myID) { return }
        }
        let parsed = NicoCommentCommand.parse(chat["mail"] as? String)
        // ミュート設定の絞り込み (録画のコメントと同じものを使う)。
        let candidate = JikkyoComment(
            time: 0, type: parsed.type, size: parsed.size,
            color: parsed.colorHex, author: userID, text: content)
        guard !SyncedSettingsStore.shared.filteredComments([candidate]).isEmpty else {
            return
        }
        let date = (chat["date"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        } ?? Date()
        let premium: String?
        if let number = chat["premium"] as? NSNumber {
            premium = number.stringValue
        } else {
            premium = chat["premium"] as? String
        }
        let comment = LiveJikkyoComment(
            id: (chat["no"] as? NSNumber)?.intValue ?? 0,
            text: content,
            date: date,
            userID: userID,
            premium: premium,
            myPost: false,
            colorHex: parsed.colorHex,
            type: parsed.type,
            size: parsed.size,
            displayTime: initialCommentsReceived ? nowProvider() + delayProvider() : 0)
        if !initialCommentsReceived {
            initialBuffer.append(comment)
            // 終わりの合図が来ない応答でも際限なく溜めないよう、
            // 上限を超えたら古いものから落とす。
            if initialBuffer.count > 5000 {
                initialBuffer.removeFirst(initialBuffer.count - 5000)
            }
            return
        }
        deliveryQueue.append(comment)
        // 一時停止が長く続いても際限なく溜めないよう、上限を超えたら
        // 古いものから落とす。
        if deliveryQueue.count > 1000 {
            deliveryQueue.removeFirst(deliveryQueue.count - 1000)
        }
        startDeliveryTimerIfNeeded()
    }

    // MARK: - 遅らせての受け渡し

    /// 流れる表示の遅れ待ちを進めるタイマー (0.25秒ごと)。
    /// 仮想の時計が displayTime に届いた分から呼び出し側へ渡す。
    private func startDeliveryTimerIfNeeded() {
        guard deliveryTimer == nil else { return }
        deliveryTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.deliverDueComments()
        }
    }

    private func deliverDueComments() {
        let now = nowProvider()
        var due: [LiveJikkyoComment] = []
        while let first = deliveryQueue.first, first.displayTime <= now {
            due.append(first)
            deliveryQueue.removeFirst()
        }
        if deliveryQueue.isEmpty {
            deliveryTimer?.invalidate()
            deliveryTimer = nil
        }
        if !due.isEmpty {
            onComments?(due, false)
        }
    }

    // MARK: - 投稿

    /// コメントを投稿する。結果は completion で返す (nil = 成功、
    /// 文字列 = 失敗の文)。色は名前 ("white" など)、位置は
    /// "ue" (上) / "naka" (流れる) / "shita" (下)、大きさは
    /// "big" / "medium" / "small" で渡す (Web 版の送信の形と同じ)。
    func postComment(text: String, colorName: String, position: String, size: String,
                     completion: @escaping (String?) -> Void) {
        // 初期化に失敗しているときは、その文をそのまま返す (Web 版と同じ)。
        if let initFailureMessage {
            completion(initFailureMessage)
            return
        }
        // 「可能であればニコニコ実況にコメントする」がオンでも、
        // ログイン・連携が無く NX-Jikkyo へ送る場合は、その旨を知らせる。
        if SyncedSettingsStore.shared.current.preferPostingToNicolive,
           !isNicoliveWatchSession {
            if !SettingsStore.shared.isLoggedIn {
                onNotice?("ニコニコ実況にコメントするには、KonomiTV アカウントにログインしてください。代わりに NX-Jikkyo にコメントします。")
            } else if myNiconicoUserID == nil {
                onNotice?("ニコニコ実況にコメントするには、ニコニコアカウントと連携してください。代わりに NX-Jikkyo にコメントします。")
            }
        }
        // ニコニコ実況側の視聴セッションのときだけの制限
        // (一般会員は上下の固定と大きな文字が使えない)。
        if isNicoliveWatchSession, myNiconicoPremium == false {
            if position == "ue" || position == "shita" {
                completion("ニコニコ実況でコメントを上下に固定するには、ニコニコアカウントのプレミアム会員登録が必要です。")
                return
            }
            if size == "big" {
                completion("ニコニコ実況でコメントサイズを大きめに設定するには、ニコニコアカウントのプレミアム会員登録が必要です。")
                return
            }
        }
        // 結果が時間切れになった接続では、張り直しが済むまで送らず
        // 待ち行列に留める (遅れて届く結果が、別の投稿のものとして
        // 扱われてしまうのを防ぐため)。接続そのものが無いときは、
        // 今までどおりその場で失敗を返す。
        if !postBlockedUntilReconnect {
            guard let watchTask, watchTask.state == .running else {
                completion("コメントの送信に失敗しました。WebSocket 接続が確立されていません。")
                return
            }
        }
        let pending = PendingPost(
            text: text,
            colorName: colorName,
            position: position,
            colorHex: NicoCommentCommand.colorTable[colorName] ?? "#FFEAEA",
            type: position == "ue" ? "top" : (position == "shita" ? "bottom" : "right"),
            size: size,
            completion: completion)
        queuedPosts.append(pending)
        pumpPostQueue()
    }

    /// 待ち行列の先頭を送る。結果待ちが空いていて、接続が生きて
    /// いて、時間切れによる停止中でないときだけ送る (結果待ちは
    /// 常に最大1件)。
    private func pumpPostQueue() {
        guard pendingPost == nil, !postBlockedUntilReconnect,
              let watchTask, watchTask.state == .running,
              !queuedPosts.isEmpty else { return }
        let post = queuedPosts.removeFirst()
        pendingPost = post
        // vpos: 番組開始時刻からの累計 (10ミリ秒単位、Web 版と同じ計算)。
        // 実際に送る時点で数える。
        let vpos: Int = {
            guard let base = vposBaseTime else { return 0 }
            return Int((Date().timeIntervalSince(base) * 100).rounded())
        }()
        sendWatchJSON([
            "type": "postComment",
            "data": [
                "text": post.text,
                "color": post.colorName,
                "position": post.position,
                "size": post.size,
                "vpos": vpos,
                "isAnonymous": true,
            ],
        ])
        // 15秒たっても結果が来なければ、その投稿は結果不明として
        // 片付ける。すでに投稿されている可能性があるため、自動では
        // 送り直さない。さらに、その接続には遅れて届く結果が残って
        // いる可能性があるため、この接続ではそれ以上送らず、接続を
        // 張り直して新しい接続が開けてから続きを送る。
        let pendingID = post.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.destroyed,
                  let expired = self.pendingPost, expired.id == pendingID
            else { return }
            self.pendingPost = nil
            expired.completion("コメントの送信結果が確認できませんでした。投稿されている可能性があります。")
            self.postBlockedUntilReconnect = true
            self.scheduleReconnect(after: 0)
        }
    }

    /// 送信の結果を受けて、結果待ちの投稿を片付ける。
    /// 成功したら、自分のコメントを一覧へ足す (Web 版と同じ)。
    /// 片付けたら、待ち行列の続きを送る。
    private func resolvePendingPost(error: String?) {
        guard let post = pendingPost else { return }
        pendingPost = nil
        post.completion(error)
        if error == nil {
            let own = LiveJikkyoComment(
                id: Int(Date().timeIntervalSince1970 * 1000),
                text: post.text,
                date: Date(),
                userID: myNiconicoUserID.map(String.init) ?? "Unknown",
                premium: nil,
                myPost: true,
                colorHex: post.colorHex,
                type: post.type,
                size: post.size,
                displayTime: nowProvider())
            onComments?([own], false)
        }
        pumpPostQueue()
    }

    // MARK: - 張り直しと後片付け

    /// 3秒ほど待ってから張り直す (Web 版と同じ間隔)。
    /// 既に予約済み・破棄済みのときは何もしない。
    private func scheduleReconnect(after seconds: Double) {
        guard !destroyed, !reconnecting else { return }
        reconnecting = true
        onNotice?("\(sessionTypeName)に再接続しています…")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.destroyed else { return }
            // まだ送っていない投稿は、新しい接続で続きを送るため
            // 残しておく。
            self.teardownSockets(keepQueuedPosts: true)
            Task { await self.connect() }
        }
    }

    /// 窓口とタイマーを片付ける。結果待ちの投稿は、結果が二度と
    /// 来ないため失敗として片付ける。まだ送っていない待ち行列は、
    /// 張り直しのときは残しておき (新しい接続が開けたら続きを
    /// 送る)、画面を離れるときだけ失敗として片付ける。
    private func teardownSockets(keepQueuedPosts: Bool = false) {
        keepSeatTimer?.invalidate()
        keepSeatTimer = nil
        deliveryTimer?.invalidate()
        deliveryTimer = nil
        deliveryQueue = []
        watchTask?.cancel(with: .normalClosure, reason: nil)
        watchTask = nil
        commentTask?.cancel(with: .normalClosure, reason: nil)
        commentTask = nil
        commentSessionStarted = false
        if let post = pendingPost {
            pendingPost = nil
            post.completion("コメントの送信に失敗しました。WebSocket 接続が確立されていません。")
        }
        if !keepQueuedPosts {
            let posts = queuedPosts
            queuedPosts = []
            for post in posts {
                post.completion("コメントの送信に失敗しました。WebSocket 接続が確立されていません。")
            }
        }
    }

    // MARK: - 文面と日時の読み解き

    /// 視聴セッションのエラーの文 (Web 版と同じ文面)。
    private static func watchErrorText(code: String, sessionTypeName: String) -> String {
        switch code {
        case "CONNECT_ERROR":
            return "\(sessionTypeName)のコメントサーバーに接続できません。"
        case "CONTENT_NOT_READY":
            return "\(sessionTypeName)が配信できない状態です。"
        case "NO_THREAD_AVAILABLE":
            return "\(sessionTypeName)のコメントスレッドを取得できません。"
        case "NO_ROOM_AVAILABLE":
            return "\(sessionTypeName)のコメント部屋を取得できません。"
        case "NO_PERMISSION":
            return "\(sessionTypeName)の API にアクセスする権限がありません。"
        case "NOT_ON_AIR":
            return "\(sessionTypeName)が放送中ではありません。"
        case "BROADCAST_NOT_FOUND":
            return "\(sessionTypeName)の配信情報を取得できません。"
        case "INTERNAL_SERVERERROR":
            return "\(sessionTypeName)でサーバーエラーが発生しています。"
        default:
            return "\(sessionTypeName)でエラーが発生しています。(Code: \(code))"
        }
    }

    /// disconnect の理由の文 (Web 版と同じ文面)。
    private static func disconnectReasonText(reason: String, sessionTypeName: String) -> String {
        switch reason {
        case "TAKEOVER":
            return "\(sessionTypeName)の番組から追い出されました。"
        case "NO_PERMISSION":
            return "\(sessionTypeName)の番組の座席を取得できませんでした。"
        case "END_PROGRAM":
            return "\(sessionTypeName)がリセットされたか、コミュニティの番組が終了しました。"
        case "PING_TIMEOUT":
            return "コメントサーバーとの接続生存確認に失敗しました。"
        case "TOO_MANY_CONNECTIONS":
            return "\(sessionTypeName)の同一ユーザからの接続数上限を越えています。"
        case "TOO_MANY_WATCHINGS":
            return "\(sessionTypeName)の同一ユーザからの視聴番組数上限を越えています。"
        case "CROWDED":
            return "\(sessionTypeName)の番組が満席です。"
        case "MAINTENANCE_IN":
            return "\(sessionTypeName)はメンテナンス中です。"
        case "SERVICE_TEMPORARILY_UNAVAILABLE":
            return "\(sessionTypeName)で一時的にサーバーエラーが発生しています。"
        default:
            return "\(sessionTypeName)との接続が切断されました。(\(reason))"
        }
    }

    /// ISO8601 の日時文字列を読む (小数秒の有無どちらでも)。
    private static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
