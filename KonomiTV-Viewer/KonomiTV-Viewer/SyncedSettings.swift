import Foundation

/// 字幕・ニコニコ実況・全般の設定のうち、サーバーに保存される利用者設定と
/// 共通の項目一式。項目名・値の形・既定値は Web 版の利用者設定
/// (caption_font など) とそのまま同じにしてある。
/// サーバーに保存される利用者設定の一部で、同期が入っているときは
/// サーバー側の値が正になり、入っていないときは端末内の値を使う
/// (番組表の表示設定の TimeTableDisplaySettings と同じ考え方)。
struct SyncedClientSettings: Equatable {
    // 字幕
    /// 字幕のフォント (Web 版の caption_font)。値の名前は Web 版のまま。
    var captionFont: String
    /// 字幕の文字を常に縁取りするか。
    var alwaysBorderCaptionText: Bool
    /// 字幕の不透明度を指定するか。
    var specifyCaptionOpacity: Bool
    /// 字幕の不透明度 (背景の濃さとして効く。0 で背景を出さない)。
    var captionOpacity: Double
    /// テレビをみるときに文字スーパーを表示するか。
    var tvShowSuperimpose: Bool
    /// ビデオをみるときに文字スーパーを表示するか。
    var videoShowSuperimpose: Bool
    // ニコニコ実況 (表示まわり)
    /// コメントの速さ (1 が等速)。
    var commentSpeedRate: Double
    /// コメントの文字サイズの基準値 (px)。
    var commentFontSize: Double
    // ニコニコ実況 (投稿まわり)
    /// 可能であればニコニコ実況にコメントするか (コメントの送信先)。
    var preferPostingToNicolive: Bool
    /// コメント送信後にコメント入力フォームを閉じるか。
    var closeCommentFormAfterSending: Bool
    // ニコニコ実況 (ミュート設定)
    /// 文字サイズが大きいコメントをミュートするか。
    var muteBigSizeComments: Bool
    /// 上下に固定表示されるコメントをミュートするか。
    var muteFixedComments: Bool
    /// 色付きのコメントをミュートするか。
    var muteColoredComments: Bool
    /// 同じ文字が8文字以上連続しているコメントをミュートするか。
    var muteConsecutiveSameCharactersComments: Bool
    /// キーワード判定で英数字・記号の大文字小文字や全角半角の違いを無視するか。
    var muteCommentKeywordsNormalize: Bool
    /// ミュートするキーワード (match の種類と pattern の組)。
    var mutedCommentKeywords: [MutedCommentKeyword]
    /// ミュートするニコニコユーザー ID。
    var mutedNiconicoUserIDs: [String]
    // 全般
    /// 視聴履歴の保持件数。
    var videoWatchedHistoryMaxCount: Int
    /// ビデオをみるときにデフォルトで表示されるパネルのタブ
    /// ("RecordedProgram" = 番組情報 / "Comment" = コメント)。
    var videoPanelActiveTab: String
    /// テレビをみるときにデフォルトで表示されるパネルのタブ
    /// ("Program" = 番組情報 / "Channel" = チャンネル / "Comment" = コメント)。
    var tvPanelActiveTab: String
    /// チャンネル一覧を実況勢いが強い順に並び替えるか。
    var tvChannelSortByJikkyoForce: Bool
    /// 時刻を 28 時間表記で表示するか。
    var use28HourClock: Bool
    /// 録画番組の再生中に元の放送時刻を表示するか。
    var showOriginalBroadcastTimeDuringPlayback: Bool
    /// ピン留め中のチャンネルの ID (Web 版の pinned_channel_ids)。
    /// 並びがそのままピン留め一覧の表示順になる。
    var pinnedChannelIDs: [String]
    /// マイリストの登録 (Web 版の mylist)。シリーズの登録も含めて
    /// そのまま保持する (アプリで表示するのは録画番組だけ)。
    var mylist: [MylistEntry]

    /// Web 版の既定値。
    static let defaults = SyncedClientSettings(
        captionFont: "Windows TV MaruGothic",
        alwaysBorderCaptionText: true,
        specifyCaptionOpacity: false,
        captionOpacity: 0.5,
        tvShowSuperimpose: true,
        videoShowSuperimpose: false,
        commentSpeedRate: 1,
        commentFontSize: 34,
        preferPostingToNicolive: true,
        closeCommentFormAfterSending: true,
        muteBigSizeComments: true,
        muteFixedComments: false,
        muteColoredComments: false,
        muteConsecutiveSameCharactersComments: false,
        muteCommentKeywordsNormalize: true,
        mutedCommentKeywords: [],
        mutedNiconicoUserIDs: [],
        videoWatchedHistoryMaxCount: 50,
        videoPanelActiveTab: "RecordedProgram",
        tvPanelActiveTab: "Program",
        tvChannelSortByJikkyoForce: false,
        use28HourClock: false,
        showOriginalBroadcastTimeDuringPlayback: false,
        pinnedChannelIDs: [],
        mylist: [])

    /// 字幕のフォントの選択肢 (Web 版の字幕設定と同じ並び)。
    /// 値はサーバーに保存される名前、題名は画面に出す名前。
    static let captionFontOptions: [(value: String, title: String)] = [
        ("Windows TV Gothic", "Windows TV ゴシック"),
        ("Windows TV MaruGothic", "Windows TV 丸ゴシック"),
        ("Windows TV FutoMaruGothic", "Windows TV 太丸ゴシック"),
        ("Hiragino TV Sans Rd S", "ヒラギノTV丸ゴ"),
        ("TT-ShinMGo-regular", "新丸ゴ ARIB"),
        ("Rounded M+ 1m for ARIB", "Rounded M+ 1m for ARIB"),
        ("BIZ UDGothic", "BIZ UDゴシック"),
        ("Noto Sans JP", "Noto Sans JP"),
        ("Yu Gothic", "游ゴシック"),
        ("sans-serif", "デフォルトのフォント"),
    ]

    /// 字幕のフォントの値を、iOS で使えるフォントの名前の並びに写す。
    /// 端末に無いフォントは描画側が読み飛ばすため、丸ゴシック系は
    /// ヒラギノ丸ゴ、ゴシック系はヒラギノ角ゴへ寄せてある。
    static func iosFontFamilies(forCaptionFont value: String) -> [String] {
        switch value {
        case "Windows TV Gothic", "BIZ UDGothic", "Noto Sans JP":
            return ["Hiragino Sans"]
        case "Yu Gothic":
            return ["YuGothic", "Hiragino Sans"]
        case "sans-serif":
            return []
        default:
            // 丸ゴシック系 (Windows TV 丸ゴシック・太丸ゴシック、
            // ヒラギノTV丸ゴ、新丸ゴ、Rounded M+) はヒラギノ丸ゴへ。
            return ["Hiragino Maru Gothic ProN", "Hiragino Sans"]
        }
    }

    /// 視聴履歴の保持件数の選択肢 (Web 版は数値入力だが、アプリでは
    /// 他の選択項目と同じく候補から選ぶ形にしてある)。
    static let watchedHistoryMaxCountOptions = [10, 20, 30, 50, 100, 200]
}

/// マイリストの登録1件分 (Web 版の mylist の要素と同じ形)。
/// 種類は "Series" (シリーズ) か "RecordedProgram" (録画番組)。
/// アプリにシリーズの画面は無いので、シリーズの登録は表示しないが、
/// 保存のときに落とさないよう、読み書きは種類ごとそのまま通す。
struct MylistEntry: Equatable {
    /// 種類 ("Series" / "RecordedProgram")。
    var type: String
    /// シリーズまたは録画番組の番号。
    var id: Int
    /// 追加した時刻 (秒単位。Web 版の created_at と同じ)。
    var createdAt: Double

    /// 録画番組の登録かどうか。
    var isRecordedProgram: Bool { type == "RecordedProgram" }

    /// 利用者設定の辞書の形に写す。
    var dictionary: [String: Any] {
        ["type": type, "id": id, "created_at": createdAt]
    }

    /// 利用者設定の辞書から組み立てる。形が違うものは nil。
    init?(dictionary: [String: Any]) {
        guard let type = dictionary["type"] as? String, !type.isEmpty,
              let id = (dictionary["id"] as? NSNumber)?.intValue else { return nil }
        self.type = type
        self.id = id
        self.createdAt = (dictionary["created_at"] as? NSNumber)?.doubleValue ?? 0
    }

    init(type: String, id: Int, createdAt: Double) {
        self.type = type
        self.id = id
        self.createdAt = createdAt
    }
}

/// ミュートするコメントのキーワード1件分 (Web 版の
/// IMutedCommentKeywords と同じ形)。
struct MutedCommentKeyword: Equatable {
    /// 照合の種類 ("partial" / "forward" / "backward" / "exact" / "regex")。
    var match: String
    /// キーワード (正規表現のときはその式)。
    var pattern: String

    /// 照合の種類の画面表示用の名前。未知の種類はそのまま返す。
    var matchTitle: String {
        switch match {
        case "partial": return "部分一致"
        case "forward": return "前方一致"
        case "backward": return "後方一致"
        case "exact": return "完全一致"
        case "regex": return "正規表現"
        default: return match
        }
    }
}

/// 字幕・ニコニコ実況・全般の共通設定の読み書きを担う。
///
/// 普段は端末内の控え (SettingsStore) を読み書きする。ログインしていて
/// 「設定をデバイス間で同期する」が入っているときは、利用者設定の手順
/// (送る直前に最新を取得 → 触る項目だけ差し替え → last_synced_at を
/// 更新して送る。知らない項目は落とさない) に乗り、サーバー側の値を
/// 正として取り込み、変更時はサーバーへも送る。番組表の表示設定の
/// TimeTableSettingsStore と同じ作りで、サーバーとのやり取りに
/// 失敗しても、端末内の値で表示は続けられる。
final class SyncedSettingsStore {
    static let shared = SyncedSettingsStore()

    /// 端末内の控えのキー名 (SettingsStore 側の保存名と一致させる)。
    private enum LocalKey {
        static let captionFont = "viewer_caption_font"
        static let alwaysBorderCaptionText = "viewer_always_border_caption_text"
        static let specifyCaptionOpacity = "viewer_specify_caption_opacity"
        static let captionOpacity = "viewer_caption_opacity"
        static let tvShowSuperimpose = "viewer_tv_show_superimpose"
        static let videoShowSuperimpose = "viewer_video_show_superimpose"
        static let commentSpeedRate = "viewer_comment_speed_rate"
        static let commentFontSize = "viewer_comment_font_size"
        static let preferPostingToNicolive = "viewer_prefer_posting_to_nicolive"
        static let closeCommentFormAfterSending = "viewer_close_comment_form_after_sending"
        static let muteBigSizeComments = "viewer_mute_big_size_comments"
        static let muteFixedComments = "viewer_mute_fixed_comments"
        static let muteColoredComments = "viewer_mute_colored_comments"
        static let muteConsecutiveSameCharactersComments = "viewer_mute_consecutive_same_characters_comments"
        static let muteCommentKeywordsNormalize = "viewer_mute_comment_keywords_normalize_alphanumeric_width_case"
        static let videoWatchedHistoryMaxCount = "viewer_video_watched_history_max_count"
        static let videoPanelActiveTab = "viewer_video_panel_active_tab"
        static let tvPanelActiveTab = "viewer_tv_panel_active_tab"
        static let tvChannelSortByJikkyoForce = "viewer_tv_channel_sort_by_jikkyo_force"
        static let use28HourClock = "viewer_use_28hour_clock"
        static let showOriginalBroadcastTimeDuringPlayback =
            "viewer_show_original_broadcast_time_during_playback"
        static let pinnedChannelIDs = "viewer_pinned_channel_ids"
        static let mylist = "viewer_mylist"
    }

    /// いま効いている設定。端末内の控えから組み立てて保持する。
    private(set) var current: SyncedClientSettings

    private init() {
        current = Self.loadFromLocal()
    }

    /// 同期が効く状態か (ログイン中かつ「設定をデバイス間で同期する」がオン)。
    /// 視聴履歴・番組表の同期と同じ条件。
    static var isSyncEnabled: Bool {
        SettingsStore.shared.isLoggedIn && SettingsStore.shared.syncSettings
    }

    /// サーバーへの送信待ちの最新値と、送信中かどうかの控え。
    /// 変更が短時間に重なっても、古い内容の送信が新しい内容を
    /// 上書きしないよう、送信は1つずつ順番に行う。
    /// 送信待ちには、変更が起きた時点の認証の世代と同期の世代も
    /// 持たせる。認証の世代が今と違う送信待ちは、前のログインの
    /// 変更なので送らない。同期の世代が違う送信待ちは、同期の
    /// オン・オフが切り替わる前の変更なので送らない (同期を切った
    /// 後に待ち分が送られたり、入れ直したときに前の待ち分が
    /// 復活したりしないため)。
    private var pendingSave: (settings: SyncedClientSettings, generation: Int, syncGeneration: Int)?
    private var isSaving = false
    /// 送信に続けて失敗した回数 (自動で試し直す回数の上限に使う)。
    private var consecutiveSaveFailures = 0

    /// 利用者が字幕フォントを自分で選び直したかどうか。
    /// サーバー側にアプリが知らない名前のフォントがあるときは、
    /// 利用者が明示的に選び直した場合だけ送る値で置き換える
    /// (保存のたびに、知らないフォントが端末側の値で消えないため)。
    /// 判定は保存の直前に取得した最新のサーバー値に対して行う。
    private var captionFontEditedByUser = false

    /// 取り込みの通し番号。取り込みが重なったとき、遅れて届いた
    /// 古い応答が、新しい応答で取り込んだ値を上書きしないために使う。
    private var refreshSequence = 0

    /// ログアウトで端末内の控えが消されたあと、今の値を控えから
    /// 読み直す (控えが無くなった項目は既定値に戻る)。送信待ちの
    /// 変更も取り下げる (前のログインの変更を、次のログインで
    /// 送らないため)。
    func reloadFromLocalAfterLogout() {
        pendingSave = nil
        captionFontEditedByUser = false
        current = Self.loadFromLocal()
    }

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗しても握りつぶす)。
    func update(_ settings: SyncedClientSettings) {
        // 利用者が字幕フォントを選び直したら、その印を立てる
        // (サーバー側の知らない名前のフォントを、保存時に置き換えて
        // よいのはこの場合だけ)。
        if settings.captionFont != current.captionFont {
            captionFontEditedByUser = true
        }
        current = settings
        saveToLocal(settings)
        guard Self.isSyncEnabled else { return }
        // 世代は変更が起きたこの時点で確定させる。送る係の開始時点や
        // 共有の順番待ちの実行時点で読むと、待ちの間にログインが
        // 切り替わったときに、前のログインの変更を次のログインの
        // 世代として扱ってしまうため。
        pendingSave = (settings, SettingsStore.shared.authGeneration,
                       SettingsStore.shared.syncGeneration)
        guard !isSaving else { return }
        isSaving = true
        consecutiveSaveFailures = 0
        Task { await self.drainSaveQueue() }
    }

    /// 送信待ちの値を、古い順に1つずつ送る。
    /// 送信に失敗した分は待ちに戻し、少し置いてから自動で試し直す
    /// (回数の上限あり)。戻さないと、その変更はサーバーへ二度と
    /// 送られなくなってしまうため。
    /// 送る係は、前のログインの分の処理で終わらないよう、世代の
    /// 違う送信待ちは取り下げ、今のログインの送信待ちが残って
    /// いれば続けて送る (古い係の終了処理が、新しいログインの
    /// 送信待ちを取り残したり消したりしないため)。
    private func drainSaveQueue() async {
        while let item = pendingSave {
            pendingSave = nil
            // 前のログインの変更と、同期の切り替え前の変更は送らない。
            guard item.generation == SettingsStore.shared.authGeneration,
                  item.syncGeneration == SettingsStore.shared.syncGeneration
            else { continue }
            if await saveToServer(item.settings, expectedGeneration: item.generation,
                                  expectedSyncGeneration: item.syncGeneration) {
                consecutiveSaveFailures = 0
                continue
            }
            // 送信の途中でログインが変わっていたら、この変更は
            // 前のログインのものなので戻さない。
            guard SettingsStore.shared.authGeneration == item.generation else { continue }
            // 同期が切り替わって無効になった変更も戻さない。戻すと、
            // 送り直しの待ち時間 (15秒) を無効な分が占有して、
            // 新しい保存がその間ずっと待たされてしまうため。
            guard item.syncGeneration == SettingsStore.shared.syncGeneration,
                  Self.isSyncEnabled else { continue }
            // その間に新しい変更が来ていたら、そちらが最新 (設定は
            // 一式の控えなので、新しい分に失敗した分の変更も含まれる)
            // ため、古い分は戻さず、新しい分を続けて送る。
            guard pendingSave == nil else { continue }
            pendingSave = item
            consecutiveSaveFailures += 1
            guard consecutiveSaveFailures <= 3 else {
                // 試し直しの上限。諦めた分は待ちに残さない。
                pendingSave = nil
                continue
            }
            // 少し間を置いてから試し直す (通信が戻るのを待つ)。
            // 待つ間も係は続ける。途中で別のログインの変更が来たら、
            // 次の周でそちらが扱われる。
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            // 待っている間にログアウトされていたり、同期が切り替わって
            // この分が無効になっていたら、送信待ちを取り下げて係を
            // 終える (同期が切れている間に来た変更は、待ちに残って
            // いないため、ここには来ない)。
            guard Self.isSyncEnabled,
                  SettingsStore.shared.syncGeneration == item.syncGeneration else {
                if pendingSave?.generation == item.generation,
                   pendingSave?.syncGeneration == item.syncGeneration {
                    pendingSave = nil
                }
                break
            }
        }
        isSaving = false
        restartDrainIfNeeded()
    }

    /// 送る係を終えるときの後始末。終わる間際に今のログインの
    /// 変更が来ていたら (係が動いていたため立て直せなかった分)、
    /// 続けて送る係を立てる。
    private func restartDrainIfNeeded() {
        guard let item = pendingSave,
              item.generation == SettingsStore.shared.authGeneration,
              item.syncGeneration == SettingsStore.shared.syncGeneration,
              !isSaving else { return }
        isSaving = true
        Task { await self.drainSaveQueue() }
    }

    /// サーバー側の値を取り込んで、現在の値と違えば差し替える。
    /// 差し替えたかどうかを返す。同期が効いていない・取得に失敗した
    /// ときは何もせず false を返す。
    func refreshFromServer() async -> Bool {
        guard Self.isSyncEnabled else { return false }
        // 送信待ちの変更があるときは取り込まない。取り込むと、送る前の
        // 変更までサーバーの古い値で上書きされてしまうため。
        guard pendingSave == nil, !isSaving else { return false }
        let currentAtStart = current
        let generationAtStart = SettingsStore.shared.authGeneration
        let syncGenerationAtStart = SettingsStore.shared.syncGeneration
        refreshSequence += 1
        let sequence = refreshSequence
        guard let settings = try? await APIClient.shared.fetchClientSettings() else {
            return false
        }
        // 取り込みの最中に利用者が変更していたら、その変更を古い
        // サーバー値で上書きしない (画面を開いた直後に字幕設定などを
        // 変えたときの巻き戻しを防ぐ)。開始時点の確かめだけでは、
        // 取得の合間に始まった変更を取りこぼすため、取得のあとでも
        // もう一度確かめる。
        // 同期が切り替わっていたら、その取得はもう無効なので反映
        // しない (同期を切った後に、取得済みの値が端末へ反映されて
        // しまうのを防ぐ。切って入れ直した場合も、古い取得は
        // 受け付けない)。取り込みが重なったときは、新しい方の
        // 応答だけを反映する (遅れて届いた古い応答に巻き戻されないため)。
        guard pendingSave == nil, !isSaving, current == currentAtStart,
              SettingsStore.shared.authGeneration == generationAtStart,
              Self.isSyncEnabled,
              SettingsStore.shared.syncGeneration == syncGenerationAtStart,
              sequence == refreshSequence else {
            return false
        }
        let server = Self.settings(fromClientSettings: settings, fallback: current)
        guard server != current else { return false }
        current = server
        saveToLocal(server)
        return true
    }

    /// 自動取り込みを試したアクセストークン (ログインごとに1回だけ試す)。
    private var lastAdoptAttemptedToken = ""

    /// ログイン時のサーバー設定の自動取り込み (Web 版の
    /// adoptServerSettingsOnLogin と同じ条件・動き)。拡張版だけが使う。
    ///
    /// 効くのは、ログインしていて同期がまだ有効でなく、かつこの端末が
    /// 一度も同期したことがない (端末側の控えが 0 の) ときだけ。
    /// サーバーに保存済みの設定があれば (サーバー側の同期時刻が 0 で
    /// なければ) 取り込んで、同期も有効にする。同期を意図的に切った
    /// 端末 (同期したことがある端末) では発動しない。試すのは
    /// アクセストークンごとに1回まで。
    func adoptServerSettingsOnLogin() async {
        let store = SettingsStore.shared
        guard store.isLoggedIn, !store.syncSettings else { return }
        let token = store.accessToken
        guard token != lastAdoptAttemptedToken else { return }
        lastAdoptAttemptedToken = token
        // この端末が一度でも同期していたら、同期を切ったのは意図的と
        // みなして何もしない。
        guard store.lastSyncedAt == 0 else { return }
        // 開始時点の状態を控える。取得の間に利用者が設定を編集したり、
        // 同期を自分で切り替えたりしたら、古いサーバー値での適用は
        // しない (利用者の操作を優先する)。
        let authGenerationAtStart = store.authGeneration
        let syncGenerationAtStart = store.syncGeneration
        let currentAtStart = current
        guard let settings = try? await APIClient.shared.fetchClientSettings() else {
            // 一時的な通信失敗で二度と試さなくならないよう、試した印を
            // 戻す (次の機会に試し直せる。アカウントが変わっていたら触らない)。
            if store.accessToken == token { lastAdoptAttemptedToken = "" }
            return
        }
        // 取得の途中でログアウトやアカウント切り替えがあったら、
        // 前の状態で取ってきた設定では上書きしない。同期の切り替え・
        // 設定の編集・他の経路での同期があった場合も同じで、開始時点
        // の状態と食い違っていたら適用しない。
        guard store.isLoggedIn, store.accessToken == token,
              store.authGeneration == authGenerationAtStart,
              store.syncGeneration == syncGenerationAtStart,
              !store.syncSettings,
              store.lastSyncedAt == 0,
              current == currentAtStart else { return }
        // サーバー側に保存済みの設定が無ければ何もしない。
        let serverSyncedAt = (settings["last_synced_at"] as? NSNumber)?.doubleValue ?? 0
        guard serverSyncedAt > 0 else { return }
        // サーバー側の値を正として取り込み、同期を有効にする
        // (Web 版の「強制的にサーバーから同期」と同じ扱い)。
        let server = Self.settings(fromClientSettings: settings, fallback: current)
        current = server
        saveToLocal(server)
        store.lastSyncedAt = serverSyncedAt
        store.syncSettings = true
        // 番組表の表示設定も、同期が有効になったので合わせて取り込む。
        _ = await TimeTableSettingsStore.shared.refreshFromServer()
    }

    // MARK: - 端末内の控え

    /// 端末内の控えから組み立てる。控えが無い項目は Web 版の既定値で受ける。
    private static func loadFromLocal() -> SyncedClientSettings {
        let store = SettingsStore.shared
        var result = SyncedClientSettings.defaults
        if let value = store.syncedString(forKey: LocalKey.captionFont),
           SyncedClientSettings.captionFontOptions.contains(where: { $0.value == value }) {
            result.captionFont = value
        }
        if let value = store.syncedBool(forKey: LocalKey.alwaysBorderCaptionText) {
            result.alwaysBorderCaptionText = value
        }
        if let value = store.syncedBool(forKey: LocalKey.specifyCaptionOpacity) {
            result.specifyCaptionOpacity = value
        }
        if let value = store.syncedDouble(forKey: LocalKey.captionOpacity) {
            result.captionOpacity = min(1, max(0, value))
        }
        if let value = store.syncedBool(forKey: LocalKey.tvShowSuperimpose) {
            result.tvShowSuperimpose = value
        }
        if let value = store.syncedBool(forKey: LocalKey.videoShowSuperimpose) {
            result.videoShowSuperimpose = value
        }
        if let value = store.syncedDouble(forKey: LocalKey.commentSpeedRate) {
            result.commentSpeedRate = min(2, max(0.5, value))
        }
        if let value = store.syncedDouble(forKey: LocalKey.commentFontSize) {
            result.commentFontSize = min(60, max(20, value))
        }
        if let value = store.syncedBool(forKey: LocalKey.preferPostingToNicolive) {
            result.preferPostingToNicolive = value
        }
        if let value = store.syncedBool(forKey: LocalKey.closeCommentFormAfterSending) {
            result.closeCommentFormAfterSending = value
        }
        if let value = store.syncedBool(forKey: LocalKey.muteBigSizeComments) {
            result.muteBigSizeComments = value
        }
        if let value = store.syncedBool(forKey: LocalKey.muteFixedComments) {
            result.muteFixedComments = value
        }
        if let value = store.syncedBool(forKey: LocalKey.muteColoredComments) {
            result.muteColoredComments = value
        }
        if let value = store.syncedBool(forKey: LocalKey.muteConsecutiveSameCharactersComments) {
            result.muteConsecutiveSameCharactersComments = value
        }
        if let value = store.syncedBool(forKey: LocalKey.muteCommentKeywordsNormalize) {
            result.muteCommentKeywordsNormalize = value
        }
        result.mutedCommentKeywords = store.mutedCommentKeywordEntries.map {
            MutedCommentKeyword(match: $0["match"] ?? "partial", pattern: $0["pattern"] ?? "")
        }.filter { !$0.pattern.isEmpty }
        result.mutedNiconicoUserIDs = store.mutedNiconicoUserIDs
        if let value = store.syncedInt(forKey: LocalKey.videoWatchedHistoryMaxCount), value > 0 {
            result.videoWatchedHistoryMaxCount = value
        }
        if let value = store.syncedString(forKey: LocalKey.videoPanelActiveTab),
           value == "RecordedProgram" || value == "Comment" {
            result.videoPanelActiveTab = value
        }
        if let value = store.syncedString(forKey: LocalKey.tvPanelActiveTab),
           value == "Program" || value == "Channel" || value == "Comment" {
            result.tvPanelActiveTab = value
        }
        if let value = store.syncedBool(forKey: LocalKey.tvChannelSortByJikkyoForce) {
            result.tvChannelSortByJikkyoForce = value
        }
        if let value = store.syncedBool(forKey: LocalKey.use28HourClock) {
            result.use28HourClock = value
        }
        if let value = store.syncedBool(forKey: LocalKey.showOriginalBroadcastTimeDuringPlayback) {
            result.showOriginalBroadcastTimeDuringPlayback = value
        }
        result.pinnedChannelIDs = store.pinnedChannelIDs
        result.mylist = store.mylistEntries.compactMap(MylistEntry.init(dictionary:))
        return result
    }

    /// 端末内の控えへ書く。
    private func saveToLocal(_ settings: SyncedClientSettings) {
        let store = SettingsStore.shared
        store.setSyncedString(settings.captionFont, forKey: LocalKey.captionFont)
        store.setSyncedBool(settings.alwaysBorderCaptionText, forKey: LocalKey.alwaysBorderCaptionText)
        store.setSyncedBool(settings.specifyCaptionOpacity, forKey: LocalKey.specifyCaptionOpacity)
        store.setSyncedDouble(settings.captionOpacity, forKey: LocalKey.captionOpacity)
        store.setSyncedBool(settings.tvShowSuperimpose, forKey: LocalKey.tvShowSuperimpose)
        store.setSyncedBool(settings.videoShowSuperimpose, forKey: LocalKey.videoShowSuperimpose)
        store.setSyncedDouble(settings.commentSpeedRate, forKey: LocalKey.commentSpeedRate)
        store.setSyncedDouble(settings.commentFontSize, forKey: LocalKey.commentFontSize)
        store.setSyncedBool(settings.preferPostingToNicolive, forKey: LocalKey.preferPostingToNicolive)
        store.setSyncedBool(settings.closeCommentFormAfterSending,
                            forKey: LocalKey.closeCommentFormAfterSending)
        store.setSyncedBool(settings.muteBigSizeComments, forKey: LocalKey.muteBigSizeComments)
        store.setSyncedBool(settings.muteFixedComments, forKey: LocalKey.muteFixedComments)
        store.setSyncedBool(settings.muteColoredComments, forKey: LocalKey.muteColoredComments)
        store.setSyncedBool(settings.muteConsecutiveSameCharactersComments,
                            forKey: LocalKey.muteConsecutiveSameCharactersComments)
        store.setSyncedBool(settings.muteCommentKeywordsNormalize,
                            forKey: LocalKey.muteCommentKeywordsNormalize)
        store.mutedCommentKeywordEntries = settings.mutedCommentKeywords.map {
            ["match": $0.match, "pattern": $0.pattern]
        }
        store.mutedNiconicoUserIDs = settings.mutedNiconicoUserIDs
        store.setSyncedInt(settings.videoWatchedHistoryMaxCount, forKey: LocalKey.videoWatchedHistoryMaxCount)
        store.setSyncedString(settings.videoPanelActiveTab, forKey: LocalKey.videoPanelActiveTab)
        store.setSyncedString(settings.tvPanelActiveTab, forKey: LocalKey.tvPanelActiveTab)
        store.setSyncedBool(settings.tvChannelSortByJikkyoForce, forKey: LocalKey.tvChannelSortByJikkyoForce)
        store.setSyncedBool(settings.use28HourClock, forKey: LocalKey.use28HourClock)
        store.setSyncedBool(settings.showOriginalBroadcastTimeDuringPlayback,
                            forKey: LocalKey.showOriginalBroadcastTimeDuringPlayback)
        store.pinnedChannelIDs = settings.pinnedChannelIDs
        store.mylistEntries = settings.mylist.map { $0.dictionary }
    }

    // MARK: - サーバーとのやり取り

    /// 変更をサーバーへ送る。送れたかどうかを返す。
    /// 実際の送信は、他の保存 (視聴履歴・番組表の設定) と重なって
    /// 互いを上書きしないよう、保存の順番待ちに並んでから行う。
    /// 世代は呼び出し側が変更の時点で確定させたものを受け取る
    /// (順番待ちの実行時点で読み直さない)。
    private func saveToServer(
        _ settings: SyncedClientSettings, expectedGeneration: Int,
        expectedSyncGeneration: Int
    ) async -> Bool {
        let box = BoolResultBox()
        await ClientSettingsSaveQueue.shared.run {
            box.value = await self.saveToServerSerial(
                settings, expectedGeneration: expectedGeneration,
                expectedSyncGeneration: expectedSyncGeneration)
        }
        return box.value
    }

    /// 変更をサーバーへ送る本体。手順は番組表・視聴履歴と同じ:
    /// 送る直前に最新を取得 → この設定一式の項目だけ差し替え →
    /// last_synced_at を今に更新して送る。422 (その間に他の端末が先に
    /// 更新した) が返ったら、1回だけ取り直してやり直す。
    private func saveToServerSerial(
        _ settings: SyncedClientSettings, expectedGeneration: Int,
        expectedSyncGeneration: Int
    ) async -> Bool {
        // 照合は、変更が起きた時点の世代で行う。順番待ちの間に
        // ログインし直していたら、取得は前のログイン・送信は
        // 新しいログインになってしまうため、この回の保存は打ち切る。
        // 同期の世代も同じで、順番待ちの間に同期を切られていたら、
        // この回の保存は打ち切る (切った後に送られてしまわないため)。
        let generation = expectedGeneration
        guard SettingsStore.shared.authGeneration == generation,
              SettingsStore.shared.syncGeneration == expectedSyncGeneration,
              SettingsStore.shared.syncSettings,
              SettingsStore.shared.isLoggedIn else { return false }
        for _ in 0..<2 {
            do {
                var clientSettings = try await APIClient.shared.fetchClientSettings()
                guard SettingsStore.shared.authGeneration == generation,
                      SettingsStore.shared.syncGeneration == expectedSyncGeneration,
                      SettingsStore.shared.syncSettings,
                      SettingsStore.shared.isLoggedIn else { return false }
                // 字幕フォント：サーバー側の値がアプリの知らない名前で、
                // 利用者が自分で選び直してもいないときは、そのまま
                // 残す (無関係な設定の保存で、他の端末が入れたフォントが
                // 端末側の値に置き換わって消えないため)。利用者が
                // 選び直したときだけ、送る値で置き換える。
                if let latestFont = clientSettings["caption_font"] as? String,
                   !SyncedClientSettings.captionFontOptions.contains(where: { $0.value == latestFont }),
                   !captionFontEditedByUser {
                    // 取得した値が既に入っているので、何もしない。
                } else {
                    clientSettings["caption_font"] = settings.captionFont
                }
                clientSettings["always_border_caption_text"] = settings.alwaysBorderCaptionText
                clientSettings["specify_caption_opacity"] = settings.specifyCaptionOpacity
                clientSettings["caption_opacity"] = settings.captionOpacity
                clientSettings["tv_show_superimpose"] = settings.tvShowSuperimpose
                clientSettings["video_show_superimpose"] = settings.videoShowSuperimpose
                clientSettings["comment_speed_rate"] = settings.commentSpeedRate
                clientSettings["comment_font_size"] = settings.commentFontSize
                clientSettings["prefer_posting_to_nicolive"] = settings.preferPostingToNicolive
                clientSettings["close_comment_form_after_sending"] =
                    settings.closeCommentFormAfterSending
                clientSettings["mute_big_size_comments"] = settings.muteBigSizeComments
                clientSettings["mute_fixed_comments"] = settings.muteFixedComments
                clientSettings["mute_colored_comments"] = settings.muteColoredComments
                clientSettings["mute_consecutive_same_characters_comments"] =
                    settings.muteConsecutiveSameCharactersComments
                clientSettings["mute_comment_keywords_normalize_alphanumeric_width_case"] =
                    settings.muteCommentKeywordsNormalize
                // 配列の項目は、以前に取得した控えではなく、いま取得した
                // 最新のサーバー値を土台に差し替える。形の違う要素は
                // そのまま残し、利用者が消した既知の要素は落とし、
                // 利用者が足した要素だけを加える (他の端末が保存の
                // 直前に追加した、形の違う登録が消えないため)。
                clientSettings["muted_comment_keywords"] = Self.mergedKeywordEntries(
                    latest: clientSettings["muted_comment_keywords"],
                    desired: settings.mutedCommentKeywords)
                clientSettings["muted_niconico_user_ids"] = Self.mergedStringEntries(
                    latest: clientSettings["muted_niconico_user_ids"],
                    desired: settings.mutedNiconicoUserIDs)
                clientSettings["video_watched_history_max_count"] = settings.videoWatchedHistoryMaxCount
                clientSettings["video_panel_active_tab"] = settings.videoPanelActiveTab
                clientSettings["tv_panel_active_tab"] = settings.tvPanelActiveTab
                clientSettings["tv_channel_sort_by_jikkyo_force"] = settings.tvChannelSortByJikkyoForce
                clientSettings["use_28hour_clock"] = settings.use28HourClock
                clientSettings["show_original_broadcast_time_during_playback"] =
                    settings.showOriginalBroadcastTimeDuringPlayback
                clientSettings["pinned_channel_ids"] = settings.pinnedChannelIDs
                clientSettings["mylist"] = Self.mergedMylistEntries(
                    latest: clientSettings["mylist"], desired: settings.mylist)
                clientSettings["last_synced_at"] = Date().timeIntervalSince1970
                try await APIClient.shared.updateClientSettings(
                    clientSettings, expectedAuthGeneration: generation)
                // 送れたら、フォントの「利用者が選び直した」印は下ろす
                // (より新しい編集が控えているときは、その編集の印を
                // 消さないよう、送った値と現在の値が同じときだけ)。
                if settings.captionFont == current.captionFont {
                    captionFontEditedByUser = false
                }
                return true
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch {
                return false  // それ以外の失敗は、この回の送信を諦める。
            }
        }
        return false
    }

    /// ミュートキーワードの配列を、最新のサーバー値を土台に組み直す。
    /// 形の違う要素 (辞書でない・キーワードが空など) はそのまま残す。
    /// 読み解ける要素は、利用者の一覧にあるものだけをサーバー側の
    /// 形のまま残し、一覧に無いものは利用者が消したものとして落とす。
    /// 利用者の一覧にあってサーバー側に無いものは、末尾に足す。
    private static func mergedKeywordEntries(
        latest: Any?, desired: [MutedCommentKeyword]
    ) -> [Any] {
        func key(match: String, pattern: String) -> String { match + "\u{1}" + pattern }
        let desiredKeys = Set(desired.map { key(match: $0.match, pattern: $0.pattern) })
        var result: [Any] = []
        var seen = Set<String>()
        if let rawEntries = latest as? [Any] {
            for raw in rawEntries {
                guard let entry = raw as? [String: Any],
                      let pattern = entry["pattern"] as? String, !pattern.isEmpty
                else {
                    result.append(raw)
                    continue
                }
                let entryKey = key(match: entry["match"] as? String ?? "partial",
                                   pattern: pattern)
                if desiredKeys.contains(entryKey) {
                    result.append(raw)
                    seen.insert(entryKey)
                }
            }
        }
        for keyword in desired
        where !seen.contains(key(match: keyword.match, pattern: keyword.pattern)) {
            result.append(["match": keyword.match, "pattern": keyword.pattern] as [String: Any])
        }
        return result
    }

    /// マイリストの配列を、最新のサーバー値を土台に組み直す。
    /// キーワードと同じ考え方で、照合の鍵は種類と番号の組。
    /// 読み解ける要素のうち利用者の一覧に無いものは、利用者が
    /// 消したものとして落とす (消した登録が復活しないため)。
    private static func mergedMylistEntries(
        latest: Any?, desired: [MylistEntry]
    ) -> [Any] {
        func key(type: String, id: Int) -> String { type + "#" + String(id) }
        let desiredKeys = Set(desired.map { key(type: $0.type, id: $0.id) })
        var result: [Any] = []
        var seen = Set<String>()
        if let rawEntries = latest as? [Any] {
            for raw in rawEntries {
                guard let entry = raw as? [String: Any],
                      let parsed = MylistEntry(dictionary: entry)
                else {
                    result.append(raw)
                    continue
                }
                let entryKey = key(type: parsed.type, id: parsed.id)
                if desiredKeys.contains(entryKey) {
                    result.append(raw)
                    seen.insert(entryKey)
                }
            }
        }
        for entry in desired where !seen.contains(key(type: entry.type, id: entry.id)) {
            result.append(entry.dictionary as Any)
        }
        return result
    }

    /// 文字列の配列 (ミュートするユーザー ID) を、最新のサーバー値を
    /// 土台に組み直す。文字列でない要素はそのまま残す。
    private static func mergedStringEntries(latest: Any?, desired: [String]) -> [Any] {
        guard let rawEntries = latest as? [Any] else { return desired }
        var result: [Any] = rawEntries.filter { raw in
            guard let value = raw as? String else { return true }
            return desired.contains(value)
        }
        for value in desired
        where !rawEntries.contains(where: { ($0 as? String) == value }) {
            result.append(value)
        }
        return result
    }

    /// 利用者設定の辞書から設定一式を組み立てる。項目が無い・形が違う
    /// ところは fallback (現在の値) で受ける。
    private static func settings(
        fromClientSettings clientSettings: [String: Any],
        fallback: SyncedClientSettings
    ) -> SyncedClientSettings {
        var result = fallback
        if let value = clientSettings["caption_font"] as? String,
           SyncedClientSettings.captionFontOptions.contains(where: { $0.value == value }) {
            result.captionFont = value
        }
        if let value = clientSettings["always_border_caption_text"] as? Bool {
            result.alwaysBorderCaptionText = value
        }
        if let value = clientSettings["specify_caption_opacity"] as? Bool {
            result.specifyCaptionOpacity = value
        }
        if let value = (clientSettings["caption_opacity"] as? NSNumber)?.doubleValue {
            result.captionOpacity = min(1, max(0, value))
        }
        if let value = clientSettings["tv_show_superimpose"] as? Bool {
            result.tvShowSuperimpose = value
        }
        if let value = clientSettings["video_show_superimpose"] as? Bool {
            result.videoShowSuperimpose = value
        }
        if let value = (clientSettings["comment_speed_rate"] as? NSNumber)?.doubleValue {
            result.commentSpeedRate = min(2, max(0.5, value))
        }
        if let value = (clientSettings["comment_font_size"] as? NSNumber)?.doubleValue {
            result.commentFontSize = min(60, max(20, value))
        }
        if let value = clientSettings["prefer_posting_to_nicolive"] as? Bool {
            result.preferPostingToNicolive = value
        }
        if let value = clientSettings["close_comment_form_after_sending"] as? Bool {
            result.closeCommentFormAfterSending = value
        }
        if let value = clientSettings["mute_big_size_comments"] as? Bool {
            result.muteBigSizeComments = value
        }
        if let value = clientSettings["mute_fixed_comments"] as? Bool {
            result.muteFixedComments = value
        }
        if let value = clientSettings["mute_colored_comments"] as? Bool {
            result.muteColoredComments = value
        }
        if let value = clientSettings["mute_consecutive_same_characters_comments"] as? Bool {
            result.muteConsecutiveSameCharactersComments = value
        }
        if let value = clientSettings["mute_comment_keywords_normalize_alphanumeric_width_case"] as? Bool {
            result.muteCommentKeywordsNormalize = value
        }
        if let rawEntries = clientSettings["muted_comment_keywords"] as? [Any] {
            // 1件ずつ読む (1件の形違いで全体を落とさないため)。
            // 読み解けなかったものは、保存のときに最新のサーバー値を
            // 土台にしてそのまま残す (送り返しで落とさない)。
            result.mutedCommentKeywords = rawEntries.compactMap { raw in
                guard let entry = raw as? [String: Any],
                      let pattern = entry["pattern"] as? String, !pattern.isEmpty
                else { return nil }
                return MutedCommentKeyword(
                    match: entry["match"] as? String ?? "partial", pattern: pattern)
            }
        }
        if let ids = clientSettings["muted_niconico_user_ids"] as? [String] {
            result.mutedNiconicoUserIDs = ids
        }
        if let value = (clientSettings["video_watched_history_max_count"] as? NSNumber)?.intValue,
           value > 0 {
            result.videoWatchedHistoryMaxCount = value
        }
        if let value = clientSettings["video_panel_active_tab"] as? String,
           value == "RecordedProgram" || value == "Comment" {
            result.videoPanelActiveTab = value
        }
        if let value = clientSettings["tv_panel_active_tab"] as? String,
           value == "Program" || value == "Channel" || value == "Comment" {
            result.tvPanelActiveTab = value
        }
        if let value = clientSettings["tv_channel_sort_by_jikkyo_force"] as? Bool {
            result.tvChannelSortByJikkyoForce = value
        }
        if let value = clientSettings["use_28hour_clock"] as? Bool {
            result.use28HourClock = value
        }
        if let value = clientSettings["show_original_broadcast_time_during_playback"] as? Bool {
            result.showOriginalBroadcastTimeDuringPlayback = value
        }
        if let ids = clientSettings["pinned_channel_ids"] as? [String] {
            result.pinnedChannelIDs = ids
        }
        if let rawEntries = clientSettings["mylist"] as? [Any] {
            // 形の違うものは読み飛ばすが、シリーズなど種類の違う登録は
            // そのまま保持する (保存のときに落とさないため)。
            // 読み飛ばしたものは、保存のときに最新のサーバー値を
            // 土台にしてそのまま残す。
            result.mylist = rawEntries.compactMap { raw in
                (raw as? [String: Any]).flatMap(MylistEntry.init(dictionary:))
            }
        }
        return result
    }

    // MARK: - マイリスト

    /// 録画番組がマイリストに入っているか (手元の現在値で判定する)。
    func isInMylist(videoID: Int) -> Bool {
        current.mylist.contains { $0.isRecordedProgram && $0.id == videoID }
    }

    /// マイリストへの追加・削除を切り替える。切り替え後の状態
    /// (入っていれば true) を返す。シリーズの登録には触れない。
    /// 同期が効いていないときは端末内の控えだけが変わるため、
    /// 呼び出し側は SyncedSettingsStore.isSyncEnabled を確かめてから使う。
    @discardableResult
    func toggleMylist(videoID: Int) -> Bool {
        var settings = current
        if isInMylist(videoID: videoID) {
            settings.mylist.removeAll { $0.isRecordedProgram && $0.id == videoID }
            update(settings)
            return false
        }
        settings.mylist.append(MylistEntry(
            type: "RecordedProgram", id: videoID,
            createdAt: Date().timeIntervalSince1970.rounded(.down)))
        update(settings)
        return true
    }

    // MARK: - コメントのミュート判定

    /// ミュート設定に照らして、表示するコメントだけに絞る。
    /// 流れる表示とコメント一覧の両方で使う (Web 版も両方に効く)。
    /// 露骨な表現・差別的な表現のパターン判定は、Web 版が持つ大きな
    /// パターンの表に依存するため、アプリではまだ入れていない
    /// (work-result-settings-expansion.md 参照)。
    func filteredComments(_ comments: [JikkyoComment]) -> [JikkyoComment] {
        let settings = current
        guard settings.muteBigSizeComments || settings.muteFixedComments
            || settings.muteColoredComments || settings.muteConsecutiveSameCharactersComments
            || !settings.mutedCommentKeywords.isEmpty || !settings.mutedNiconicoUserIDs.isEmpty
        else { return comments }
        return comments.filter { !isMuted($0, settings: settings) }
    }

    private func isMuted(_ comment: JikkyoComment, settings: SyncedClientSettings) -> Bool {
        if settings.muteBigSizeComments, comment.size == "big" { return true }
        if settings.muteFixedComments, comment.type == "top" || comment.type == "bottom" {
            return true
        }
        if settings.muteColoredComments, Self.isColored(comment.color) { return true }
        if settings.muteConsecutiveSameCharactersComments,
           Self.hasConsecutiveSameCharacters(comment.text) { return true }
        if settings.mutedNiconicoUserIDs.contains(comment.author) { return true }
        for keyword in settings.mutedCommentKeywords {
            if Self.matches(comment.text, keyword: keyword,
                            normalize: settings.muteCommentKeywordsNormalize) {
                return true
            }
        }
        return false
    }

    /// 色付きかどうか。Web 版はプレイヤーの文字色の既定 (#FFEAEA) と
    /// 一致しないものを色付きとみなす。
    private static func isColored(_ colorHex: String) -> Bool {
        var s = colorHex.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return false }
        return s != "FFEAEA" && s != "FFFFFF"
    }

    /// 同じ文字が8文字以上連続しているか (Web 版の判定と同じ)。
    private static func hasConsecutiveSameCharacters(_ text: String) -> Bool {
        var run = 0
        var previous: Character?
        for character in text {
            if character == previous {
                run += 1
            } else {
                run = 1
                previous = character
            }
            if run >= 8 { return true }
        }
        return false
    }

    /// キーワードとの照合。正規化がオンのときは、Web 版と同じく
    /// 英数字・記号の大文字小文字と全角半角の違いを無視して比べる。
    /// 正規表現の作り直しを避けるための控え (式の文字列が鍵)。
    private static var compiledRegexCache: [String: NSRegularExpression] = [:]
    private static var failedRegexPatterns: Set<String> = []

    private static func matches(_ text: String, keyword: MutedCommentKeyword, normalize: Bool) -> Bool {
        if keyword.match == "regex" {
            // 正規表現はそのままの式で照合する (壊れた式は無視する)。
            // コメントごとに作り直すと重いため、作ったものは控えて使い回す。
            if failedRegexPatterns.contains(keyword.pattern) { return false }
            let regex: NSRegularExpression
            if let cached = compiledRegexCache[keyword.pattern] {
                regex = cached
            } else if let made = try? NSRegularExpression(pattern: keyword.pattern) {
                compiledRegexCache[keyword.pattern] = made
                regex = made
            } else {
                failedRegexPatterns.insert(keyword.pattern)
                return false
            }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        let target = normalize ? normalizedForKeywordMatch(text) : text
        let pattern = normalize ? normalizedForKeywordMatch(keyword.pattern) : keyword.pattern
        guard !pattern.isEmpty else { return false }
        switch keyword.match {
        case "forward": return target.hasPrefix(pattern)
        case "backward": return target.hasSuffix(pattern)
        case "exact": return target == pattern
        default: return target.contains(pattern)
        }
    }

    /// キーワード照合用の正規化: 全角英数字・記号を半角にし、
    /// 英字を小文字にそろえる。
    private static func normalizedForKeywordMatch(_ text: String) -> String {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return halfwidth.lowercased()
    }
}
