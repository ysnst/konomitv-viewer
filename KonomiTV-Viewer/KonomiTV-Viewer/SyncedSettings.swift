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
    /// チャンネル一覧を実況勢いが強い順に並び替えるか。
    var tvChannelSortByJikkyoForce: Bool
    /// 時刻を 28 時間表記で表示するか。
    var use28HourClock: Bool
    /// 録画番組の再生中に元の放送時刻を表示するか。
    var showOriginalBroadcastTimeDuringPlayback: Bool
    /// ピン留め中のチャンネルの ID (Web 版の pinned_channel_ids)。
    /// 並びがそのままピン留め一覧の表示順になる。
    var pinnedChannelIDs: [String]

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
        muteBigSizeComments: true,
        muteFixedComments: false,
        muteColoredComments: false,
        muteConsecutiveSameCharactersComments: false,
        muteCommentKeywordsNormalize: true,
        mutedCommentKeywords: [],
        mutedNiconicoUserIDs: [],
        videoWatchedHistoryMaxCount: 50,
        videoPanelActiveTab: "RecordedProgram",
        tvChannelSortByJikkyoForce: false,
        use28HourClock: false,
        showOriginalBroadcastTimeDuringPlayback: false,
        pinnedChannelIDs: [])

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
        static let muteBigSizeComments = "viewer_mute_big_size_comments"
        static let muteFixedComments = "viewer_mute_fixed_comments"
        static let muteColoredComments = "viewer_mute_colored_comments"
        static let muteConsecutiveSameCharactersComments = "viewer_mute_consecutive_same_characters_comments"
        static let muteCommentKeywordsNormalize = "viewer_mute_comment_keywords_normalize_alphanumeric_width_case"
        static let videoWatchedHistoryMaxCount = "viewer_video_watched_history_max_count"
        static let videoPanelActiveTab = "viewer_video_panel_active_tab"
        static let tvChannelSortByJikkyoForce = "viewer_tv_channel_sort_by_jikkyo_force"
        static let use28HourClock = "viewer_use_28hour_clock"
        static let showOriginalBroadcastTimeDuringPlayback =
            "viewer_show_original_broadcast_time_during_playback"
        static let pinnedChannelIDs = "viewer_pinned_channel_ids"
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
    private var pendingSave: SyncedClientSettings?
    private var isSaving = false

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗しても握りつぶす)。
    func update(_ settings: SyncedClientSettings) {
        current = settings
        saveToLocal(settings)
        guard Self.isSyncEnabled else { return }
        pendingSave = settings
        guard !isSaving else { return }
        isSaving = true
        Task { await self.drainSaveQueue() }
    }

    /// 送信待ちの値を、古い順に1つずつ送る。
    private func drainSaveQueue() async {
        while let settings = pendingSave {
            pendingSave = nil
            await saveToServer(settings)
        }
        isSaving = false
    }

    /// サーバー側の値を取り込んで、現在の値と違えば差し替える。
    /// 差し替えたかどうかを返す。同期が効いていない・取得に失敗した
    /// ときは何もせず false を返す。
    func refreshFromServer() async -> Bool {
        guard Self.isSyncEnabled else { return false }
        guard let settings = try? await APIClient.shared.fetchClientSettings() else {
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
        guard let settings = try? await APIClient.shared.fetchClientSettings() else { return }
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
        store.setSyncedBool(settings.tvChannelSortByJikkyoForce, forKey: LocalKey.tvChannelSortByJikkyoForce)
        store.setSyncedBool(settings.use28HourClock, forKey: LocalKey.use28HourClock)
        store.setSyncedBool(settings.showOriginalBroadcastTimeDuringPlayback,
                            forKey: LocalKey.showOriginalBroadcastTimeDuringPlayback)
        store.pinnedChannelIDs = settings.pinnedChannelIDs
    }

    // MARK: - サーバーとのやり取り

    /// 変更をサーバーへ送る。手順は番組表・視聴履歴と同じ:
    /// 送る直前に最新を取得 → この設定一式の項目だけ差し替え →
    /// last_synced_at を今に更新して送る。422 (その間に他の端末が先に
    /// 更新した) が返ったら、1回だけ取り直してやり直す。
    private func saveToServer(_ settings: SyncedClientSettings) async {
        for _ in 0..<2 {
            do {
                var clientSettings = try await APIClient.shared.fetchClientSettings()
                clientSettings["caption_font"] = settings.captionFont
                clientSettings["always_border_caption_text"] = settings.alwaysBorderCaptionText
                clientSettings["specify_caption_opacity"] = settings.specifyCaptionOpacity
                clientSettings["caption_opacity"] = settings.captionOpacity
                clientSettings["tv_show_superimpose"] = settings.tvShowSuperimpose
                clientSettings["video_show_superimpose"] = settings.videoShowSuperimpose
                clientSettings["comment_speed_rate"] = settings.commentSpeedRate
                clientSettings["comment_font_size"] = settings.commentFontSize
                clientSettings["mute_big_size_comments"] = settings.muteBigSizeComments
                clientSettings["mute_fixed_comments"] = settings.muteFixedComments
                clientSettings["mute_colored_comments"] = settings.muteColoredComments
                clientSettings["mute_consecutive_same_characters_comments"] =
                    settings.muteConsecutiveSameCharactersComments
                clientSettings["mute_comment_keywords_normalize_alphanumeric_width_case"] =
                    settings.muteCommentKeywordsNormalize
                clientSettings["muted_comment_keywords"] = settings.mutedCommentKeywords.map {
                    ["match": $0.match, "pattern": $0.pattern]
                }
                clientSettings["muted_niconico_user_ids"] = settings.mutedNiconicoUserIDs
                clientSettings["video_watched_history_max_count"] = settings.videoWatchedHistoryMaxCount
                clientSettings["video_panel_active_tab"] = settings.videoPanelActiveTab
                clientSettings["tv_channel_sort_by_jikkyo_force"] = settings.tvChannelSortByJikkyoForce
                clientSettings["use_28hour_clock"] = settings.use28HourClock
                clientSettings["show_original_broadcast_time_during_playback"] =
                    settings.showOriginalBroadcastTimeDuringPlayback
                clientSettings["pinned_channel_ids"] = settings.pinnedChannelIDs
                clientSettings["last_synced_at"] = Date().timeIntervalSince1970
                try await APIClient.shared.updateClientSettings(clientSettings)
                return
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch {
                return  // それ以外の失敗は、この回の送信を諦める。
            }
        }
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
        if let entries = clientSettings["muted_comment_keywords"] as? [[String: Any]] {
            result.mutedCommentKeywords = entries.compactMap { entry in
                guard let pattern = entry["pattern"] as? String, !pattern.isEmpty else { return nil }
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
        return result
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
    private static func matches(_ text: String, keyword: MutedCommentKeyword, normalize: Bool) -> Bool {
        if keyword.match == "regex" {
            // 正規表現はそのままの式で照合する (壊れた式は無視する)。
            guard let regex = try? NSRegularExpression(pattern: keyword.pattern) else {
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
