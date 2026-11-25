import Foundation

extension Notification.Name {
    /// 共通設定のサーバー保存に失敗し、自動の送り直しでも届かなかった
    /// ときの通知 (番組表の表示設定の timeTableSettingsSaveFailed と同じ作り)。
    static let syncedSettingsSaveFailed = Notification.Name("SyncedSettingsSaveFailed")
}

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

    /// サーバーへの送信待ちと、送信中かどうかの控え。
    /// 変更が短時間に重なっても、古い内容の送信が新しい内容を
    /// 上書きしないよう、送信は1つずつ順番に行う。
    /// 送信待ちには、編集の前後の値 (差分の元と先) と、変更が起きた
    /// 時点の認証の世代と同期の世代を持たせる。保存のときは、編集の
    /// 前後で変わった項目だけを、直前に取得した最新のサーバー値へ
    /// 適用する。触っていない項目は最新の値のまま残るため、他の
    /// 端末がその間に追加・変更した内容が、無関係な保存で消えたり、
    /// 向こうで消したものがこちらから復活したりしない。
    /// 認証の世代が今と違う送信待ちは、前のログインの変更なので
    /// 送らない。同期の世代が違う送信待ちは、同期のオン・オフが
    /// 切り替わる前の変更なので送らない (同期を切った後に待ち分が
    /// 送られたり、入れ直したときに前の待ち分が復活したりしないため)。
    private struct PendingSave {
        /// 通し番号。送り直しの待ちの間に、新しい変更に置き換わった
        /// かどうかの判定に使う。
        let id: Int
        /// 編集が起きる直前の値 (差分の元)。
        let base: SyncedClientSettings
        /// 編集後の値 (差分の先)。
        let desired: SyncedClientSettings
        /// 変更が起きた時点の認証の世代。
        let generation: Int
        /// 変更が起きた時点の同期の世代。
        let syncGeneration: Int
        /// 結果が分からない送信 (サーバーへ届いたかもしれないのに
        /// 応答が返らなかった送信) に含まれていた項目 (サーバー側の
        /// 項目名)。サーバーに残っているかもしれない値と、最終的な
        /// 意図が食い違うときに送り直すための控えで、送信が成功
        /// するか、届かなかったことが明らかになれば役目を終える。
        var uncertainKeys: Set<String> = []
        /// 結果が分からない送信で生じたかもしれない、サーバー側の
        /// 値と最終的な意図の食い違い (配列の要素単位の控え)。
        var uncertain = UncertainRecord()
        /// 利用者が明示的に行ったピン留めの並び替えの対象と、その
        /// 並び (対象の要素を、並び替え後の相対的な順序で並べたもの)。
        /// 編集を合成すると差分の元が古い値へ戻るため、その編集で
        /// 追加された要素は差分の元に無く、並び替えの対象から漏れて
        /// しまう。並び替えは1操作ごとの編集として届くので、編集の
        /// 単位で対象を記録し、合成しても引き継ぐ。並び替えを
        /// していない変更では空で、その場合は従来どおり、追加・削除
        /// だけでは他の端末の並び順を保つ。
        var pinnedOrderIntent: [String] = []
    }

    /// 結果が分からない送信 (サーバーへ届いたかもしれないのに応答が
    /// 返らなかった送信) が残したかもしれない、サーバー側の値と
    /// 最終的な意図の食い違いを、配列の要素ごとに積み上げた控え。
    /// 1回分の送信の値一式を控えにすると、次の結果が分からない送信で
    /// 上書きされて前の回の操作が消えてしまうため、要素ごとの集合
    /// として持ち、増える方向にだけ更新する。スカラーの項目は
    /// uncertainKeys と最終的な意図の値だけで照合できるため、
    /// ここには含めない。
    private struct UncertainRecord {
        /// その送信で増えたかもしれない要素の鍵 (ミュートキーワード)。
        var addedKeywordKeys: Set<String> = []
        /// その送信で減ったかもしれない要素の鍵 (ミュートキーワード)。
        var removedKeywordKeys: Set<String> = []
        /// その送信で増えたかもしれない要素 (ミュートするユーザー ID)。
        var addedUserIDs: Set<String> = []
        /// その送信で減ったかもしれない要素 (ミュートするユーザー ID)。
        var removedUserIDs: Set<String> = []
        /// その送信で増えたかもしれない要素 (ピン留めチャンネル)。
        var addedPinnedIDs: Set<String> = []
        /// その送信で減ったかもしれない要素 (ピン留めチャンネル)。
        var removedPinnedIDs: Set<String> = []
        /// ピン留めの並び順が、その送信で変わったかもしれない。
        var pinnedOrderMayDiffer = false
        /// その送信で増えたかもしれない要素の鍵 (マイリスト)。
        var addedMylistKeys: Set<String> = []
        /// その送信で減ったかもしれない要素の鍵 (マイリスト)。
        var removedMylistKeys: Set<String> = []

        /// もう一方の控えと合わせる (要素は合算し、並び順の印は
        /// どちらかに立っていれば立てる)。
        mutating func formUnion(_ other: UncertainRecord) {
            addedKeywordKeys.formUnion(other.addedKeywordKeys)
            removedKeywordKeys.formUnion(other.removedKeywordKeys)
            addedUserIDs.formUnion(other.addedUserIDs)
            removedUserIDs.formUnion(other.removedUserIDs)
            addedPinnedIDs.formUnion(other.addedPinnedIDs)
            removedPinnedIDs.formUnion(other.removedPinnedIDs)
            pinnedOrderMayDiffer = pinnedOrderMayDiffer || other.pinnedOrderMayDiffer
            addedMylistKeys.formUnion(other.addedMylistKeys)
            removedMylistKeys.formUnion(other.removedMylistKeys)
        }

        /// 1回分の送信 (base → desired) の差分を、結果が分からない
        /// 場合の控えとして取り込む。増えた要素は「サーバーに残って
        /// いるかもしれない」、減った要素は「サーバーから消えている
        /// かもしれない」として積み上げる。その要素を最終的にどう
        /// するかは、適用のときに最終的な意図と照合して決める
        /// (その間に利用者が消した要素を戻したり、並び替えを
        /// 取り消したりした場合も、意図どおりにできるように)。
        mutating func absorb(
            base: SyncedClientSettings, desired: SyncedClientSettings
        ) {
            let baseKeywordKeys = Set(base.mutedCommentKeywords.map(
                SyncedSettingsStore.keywordKey))
            let desiredKeywordKeys = Set(desired.mutedCommentKeywords.map(
                SyncedSettingsStore.keywordKey))
            addedKeywordKeys.formUnion(desiredKeywordKeys.subtracting(baseKeywordKeys))
            removedKeywordKeys.formUnion(baseKeywordKeys.subtracting(desiredKeywordKeys))
            addedUserIDs.formUnion(Set(desired.mutedNiconicoUserIDs)
                .subtracting(Set(base.mutedNiconicoUserIDs)))
            removedUserIDs.formUnion(Set(base.mutedNiconicoUserIDs)
                .subtracting(Set(desired.mutedNiconicoUserIDs)))
            let basePinned = Set(base.pinnedChannelIDs)
            let desiredPinned = Set(desired.pinnedChannelIDs)
            addedPinnedIDs.formUnion(desiredPinned.subtracting(basePinned))
            removedPinnedIDs.formUnion(basePinned.subtracting(desiredPinned))
            // ピン留めの並び順が変わったかもしれないのは、編集前後で
            // 共通する要素の相対的な順序が変わった場合。
            let keptPinned = basePinned.intersection(desiredPinned)
            if base.pinnedChannelIDs.filter({ keptPinned.contains($0) })
                != desired.pinnedChannelIDs.filter({ keptPinned.contains($0) }) {
                pinnedOrderMayDiffer = true
            }
            let baseMylistKeys = Set(base.mylist.map(SyncedSettingsStore.mylistKey))
            let desiredMylistKeys = Set(desired.mylist.map(SyncedSettingsStore.mylistKey))
            addedMylistKeys.formUnion(desiredMylistKeys.subtracting(baseMylistKeys))
            removedMylistKeys.formUnion(baseMylistKeys.subtracting(desiredMylistKeys))
        }
    }

    /// ミュートキーワードの要素の照合鍵 (照合の種類と文の組)。
    fileprivate static func keywordKey(_ keyword: MutedCommentKeyword) -> String {
        keyword.match + "\u{1}" + keyword.pattern
    }

    /// マイリストの要素の照合鍵 (種類と番号の組)。
    fileprivate static func mylistKey(_ entry: MylistEntry) -> String {
        entry.type + "#" + String(entry.id)
    }

    /// 1回分の編集が、ピン留めの明示的な並び替えかどうかと、その
    /// 対象を返す。編集の前後に共通する要素の相対的な順序が変わって
    /// いれば並び替えで、対象 (共通する要素) を編集後の相対的な
    /// 順序で返す。追加・削除だけの編集では順序は変わらないため空を
    /// 返し、その場合は他の端末の並び順を保つ対象になる。
    fileprivate static func pinnedOrderIntent(
        from base: SyncedClientSettings, to desired: SyncedClientSettings
    ) -> [String] {
        let kept = Set(base.pinnedChannelIDs)
            .intersection(Set(desired.pinnedChannelIDs))
        let inBase = base.pinnedChannelIDs.filter { kept.contains($0) }
        let inDesired = desired.pinnedChannelIDs.filter { kept.contains($0) }
        return inBase == inDesired ? [] : inDesired
    }

    /// サーバーへの送信の結果。届かなかったことが明らかな失敗と、
    /// 届いたかどうか分からない失敗を区別する (応答が返って
    /// こなかった送信は、サーバー側で保存が済んでいることがある)。
    private enum SaveOutcome {
        /// 送れて、サーバー側の保存が確認できた。
        case success
        /// 送信がサーバーに適用されていないことが分かる失敗
        /// (送信前の取得の失敗、サーバーからの拒否の応答など)。
        case notApplied
        /// 送信が届いたかどうか分からない失敗 (応答が返って
        /// こなかったものと、サーバー側の都合による失敗 (5xx)。
        /// 保存が済んだ後に返ってくることがある)。サーバー側に
        /// 値が残っている可能性がある。
        case unknown
    }

    private var pendingSave: PendingSave?
    /// いま送っている最中の変更。送信の結果が分かるまでは、端末への
    /// 控えの対象として送信待ちと同じに扱う (送信の途中でアプリが
    /// 終わっても、変更が消えないようにするため)。
    private var inFlightSave: PendingSave?
    /// 自動の送り直しの上限に達して、まだサーバーへ届いていない変更。
    /// 捨ててしまうと、その項目はサーバーへ二度と送られず、次の
    /// 取り込みで端末の値まで巻き戻ってしまうため、保持しておいて
    /// 次の変更や取り込みのときに差分へ合成して送り直す。
    /// 世代が変わったら (ログアウト・同期の切り替え) 前の状態の
    /// 変更なので、その時点で捨てる。
    private var unsentSave: PendingSave?

    /// サーバーへ届いていない変更が残っているか (世代が今と合う分だけ)。
    var hasUnsentChanges: Bool {
        guard let unsent = unsentSave else { return false }
        return unsent.generation == SettingsStore.shared.authGeneration
            && unsent.syncGeneration == SettingsStore.shared.syncGeneration
    }

    /// 送信待ちの通し番号の払い出し用。
    private var pendingSaveSequence = 0
    private var isSaving = false
    /// 送信に続けて失敗した回数 (自動で試し直す回数の上限に使う)。
    private var consecutiveSaveFailures = 0

    /// 取り込みの通し番号。取り込みが重なったとき、遅れて届いた
    /// 古い応答が、新しい応答で取り込んだ値を上書きしないために使う。
    private var refreshSequence = 0

    /// ログアウトで端末内の控えが消されたあと、今の値を控えから
    /// 読み直す (控えが無くなった項目は既定値に戻る)。送信待ちの
    /// 変更も取り下げる (前のログインの変更を、次のログインで
    /// 送らないため)。
    func reloadFromLocalAfterLogout() {
        pendingSave = nil
        inFlightSave = nil
        unsentSave = nil
        // 端末に残した未送信の変更の控えも消す (前のログインの変更を、
        // 次のログインで送らないため)。
        restoredUnsent = nil
        SettingsStore.shared.unsentSyncedSettingsData = nil
        current = Self.loadFromLocal()
    }

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗しても握りつぶす)。
    func update(_ settings: SyncedClientSettings) {
        let previous = current
        current = settings
        saveToLocal(settings)
        // 前回の起動で送れずに端末へ残した変更があれば、ここで
        // 引き継ぐ (条件が合わなければ破棄する)。
        adoptRestoredUnsentIfNeeded()
        guard Self.isSyncEnabled else { return }
        // 世代は変更が起きたこの時点で確定させる。送る係の開始時点や
        // 共有の順番待ちの実行時点で読むと、待ちの間にログインが
        // 切り替わったときに、前のログインの変更を次のログインの
        // 世代として扱ってしまうため。
        let generation = SettingsStore.shared.authGeneration
        let syncGeneration = SettingsStore.shared.syncGeneration
        pendingSaveSequence += 1
        // まだ送れていない変更が残っていれば、差分の元はその変更の
        // 直前の値のまま引き継ぐ (間の編集も含めた差分にするため)。
        // 世代の違う残りは前の状態のものなので引き継がない。
        // 送り直しの上限に達して未送信として残っている分も同じ扱いで、
        // ここで差分の元として引き継ぎ、新しい変更と一緒に送る
        // (引き継がないと、未送信分の項目がサーバーへ届かないままになる)。
        var carriedBase: SyncedClientSettings?
        var carriedUncertainKeys: Set<String> = []
        var carriedUncertain = UncertainRecord()
        // ピン留めの並び替えの対象は、この編集が並び替えならこの
        // 編集のものを使う。並び替えでない編集では、まだ送れて
        // いない変更に並び替えが含まれていれば、その対象を引き継ぐ
        // (合成で差分の元が古い値へ戻ると、並び替えた要素が差分の
        // 元に無くなり、対象から漏れてしまうため)。
        var carriedPinnedOrderIntent = Self.pinnedOrderIntent(
            from: previous, to: settings)
        if let unsent = unsentSave {
            unsentSave = nil
            if unsent.generation == generation,
               unsent.syncGeneration == syncGeneration {
                carriedBase = unsent.base
                carriedUncertainKeys = unsent.uncertainKeys
                carriedUncertain = unsent.uncertain
                if carriedPinnedOrderIntent.isEmpty {
                    carriedPinnedOrderIntent = unsent.pinnedOrderIntent
                }
            }
        }
        let base: SyncedClientSettings
        if let pending = pendingSave,
           pending.generation == generation,
           pending.syncGeneration == syncGeneration {
            base = pending.base
            carriedUncertainKeys.formUnion(pending.uncertainKeys)
            carriedUncertain.formUnion(pending.uncertain)
            if carriedPinnedOrderIntent.isEmpty {
                carriedPinnedOrderIntent = pending.pinnedOrderIntent
            }
        } else if let carriedBase {
            base = carriedBase
        } else {
            base = previous
        }
        // 送信中の変更に含まれていた並び替えも、送信待ち・未送信に
        // 無ければ引き継ぐ (送信中の分は差分の元の引き継ぎ対象では
        // ないが、並び替えの対象は送信の成否によらず残す必要がある)。
        if carriedPinnedOrderIntent.isEmpty,
           let inFlight = inFlightSave,
           inFlight.generation == generation,
           inFlight.syncGeneration == syncGeneration {
            carriedPinnedOrderIntent = inFlight.pinnedOrderIntent
        }
        pendingSave = PendingSave(
            id: pendingSaveSequence, base: base, desired: settings,
            generation: generation, syncGeneration: syncGeneration,
            uncertainKeys: carriedUncertainKeys,
            uncertain: carriedUncertain,
            pinnedOrderIntent: carriedPinnedOrderIntent)
        syncPersistedRecord()
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
        while let pendingItem = pendingSave {
            pendingSave = nil
            var item = pendingItem
            inFlightSave = item
            syncPersistedRecord()
            // 前のログインの変更と、同期の切り替え前の変更は送らない。
            guard item.generation == SettingsStore.shared.authGeneration,
                  item.syncGeneration == SettingsStore.shared.syncGeneration
            else {
                inFlightSave = nil
                syncPersistedRecord()
                continue
            }
            let outcome = await saveToServer(
                base: item.base, desired: item.desired,
                uncertainKeys: item.uncertainKeys,
                uncertain: item.uncertain,
                pinnedOrderIntent: item.pinnedOrderIntent,
                expectedGeneration: item.generation,
                expectedSyncGeneration: item.syncGeneration)
            inFlightSave = nil
            if outcome == .success {
                consecutiveSaveFailures = 0
                syncPersistedRecord()
                continue
            }
            if outcome == .unknown {
                // 届いたかどうか分からない送信。サーバー側にこの変更の
                // 値が残っているかもしれないので、含まれていた項目と、
                // 配列については要素ごとの食い違いを控えに積み上げる。
                // 後から取り込んだ値と最終的な意図が食い違えば、送り
                // 直して意図どおりにする (その間に利用者が値を元へ
                // 戻していた場合も、値の差分だけでは「変更なし」に
                // なってしまうため、差分とは別に持つ)。
                item.uncertainKeys.formUnion(
                    Self.changedKeys(base: item.base, desired: item.desired))
                item.uncertain.absorb(base: item.base, desired: item.desired)
            }
            // 送信の途中でログインが変わっていたら、この変更は
            // 前のログインのものなので戻さない。
            guard SettingsStore.shared.authGeneration == item.generation else {
                syncPersistedRecord()
                continue
            }
            // 同期が切り替わって無効になった変更も戻さない。戻すと、
            // 送り直しの待ち時間を無効な分が占有して、新しい保存が
            // その間ずっと待たされてしまうため。
            guard item.syncGeneration == SettingsStore.shared.syncGeneration,
                  Self.isSyncEnabled else {
                syncPersistedRecord()
                continue
            }
            consecutiveSaveFailures += 1
            // その間に新しい変更が来ていたら、失敗した分の差分を
            // 新しい分の差分へ合成してから送る。新しい分の差分の元は
            // 「失敗した変更が入った後の値」なので、そのまま送ると
            // 失敗した分の項目は差分に現れず、サーバーへ届かない。
            // 元を失敗した分の元へ差し替えると、両方の編集を含めた
            // 差分になる。ただし、失敗した送信が実は届いていた場合は、
            // 送信中に値を元へ戻す編集があると差分が「変更なし」に
            // なってしまうため、その分の項目は結果が分からない送信の
            // 控え (uncertainKeys) で別に追い、適用のときに最新の値と
            // 照合して意図どおりにする。
            if let pending = pendingSave {
                if pending.generation == item.generation,
                   pending.syncGeneration == item.syncGeneration {
                    // 結果が分からない送信の控えは、失敗した分と新しい
                    // 分の両方から引き継ぐ (要素ごとの控えは合算する)。
                    var mergedUncertain = item.uncertain
                    mergedUncertain.formUnion(pending.uncertain)
                    let merged = PendingSave(
                        id: pending.id, base: item.base, desired: pending.desired,
                        generation: pending.generation,
                        syncGeneration: pending.syncGeneration,
                        uncertainKeys: item.uncertainKeys.union(pending.uncertainKeys),
                        uncertain: mergedUncertain,
                        // 並び替えの対象は新しい分を優先し、無ければ
                        // 失敗した分のものを引き継ぐ。
                        pinnedOrderIntent: pending.pinnedOrderIntent.isEmpty
                            ? item.pinnedOrderIntent : pending.pinnedOrderIntent)
                    if consecutiveSaveFailures > 3 {
                        // 試し直しの上限。合成した分は捨てずに未送信
                        // として残し、失敗したことを画面側へ知らせる。
                        unsentSave = merged
                        pendingSave = nil
                        syncPersistedRecord()
                        await notifySaveFailed()
                        continue
                    }
                    pendingSave = merged
                }
                // 世代の違う新しい変更がある場合は、失敗した分は
                // 前の状態のものなので合成せず、新しい分を続けて送る。
                syncPersistedRecord()
                continue
            }
            guard consecutiveSaveFailures <= 3 else {
                // 試し直しの上限。諦めた分は捨てずに未送信として
                // 残し、次の変更や取り込みのときに送り直す。
                // あわせて、失敗したことを画面側へ知らせる (端末内に
                // は保存されているため、黙っていると他の端末で
                // 変わっていないことに気づけない)。
                unsentSave = item
                syncPersistedRecord()
                await notifySaveFailed()
                continue
            }
            pendingSave = item
            syncPersistedRecord()
            // 少し間を置いてから試し直す (通信が戻るのを待つ)。
            // 待ちは取り消せる形にし、待っている間に新しい変更が
            // 来たり、状態が変わったりしたら、待ちを打ち切って
            // 次の周で新しい状態に合わせて扱う (状態が変わっても
            // 待ちが終わるまで新しい保存が始まらない、ということが
            // ないようにするため)。
            await waitBeforeRetry(of: item)
        }
        isSaving = false
        restartDrainIfNeeded()
    }

    /// 保存に失敗して、自動の送り直しでも届かなかったことを画面側へ
    /// 知らせる (番組表の表示設定と同じ作り)。
    private func notifySaveFailed() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .syncedSettingsSaveFailed, object: nil)
        }
    }

    /// 送り直しまでの待ち (最長15秒)。細切れに眠り、そのたびに
    /// 状態を確かめる。待ちの対象が新しい変更に置き換わっていたり、
    /// ログインや同期の状態が変わっていたりしたら、すぐに起きて
    /// 呼び出し側の次の周に任せる。
    private func waitBeforeRetry(of item: PendingSave) async {
        // 15秒を 0.2秒 × 75回に分ける。
        for _ in 0..<75 {
            if pendingSave?.id != item.id { return }
            if SettingsStore.shared.authGeneration != item.generation { return }
            if SettingsStore.shared.syncGeneration != item.syncGeneration { return }
            if !Self.isSyncEnabled { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
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

    // MARK: - 未送信の変更の端末への保存

    /// 端末に保存した未送信の変更の控え (読み出した形)。
    private struct RestoredUnsent {
        /// どのアカウント・接続先の変更かを示す目印。
        let identity: String
        let base: SyncedClientSettings
        let desired: SyncedClientSettings
        let uncertainKeys: Set<String>
        let uncertain: UncertainRecord
        /// 明示的な並び替えの対象と並び (以前の版の控えには無い
        /// ため、その場合は空として読む)。
        let pinnedOrderIntent: [String]
    }

    /// 端末から読み出した控え。引き継ぐかどうかは、使う時点で
    /// ログインと同期の状態と照合して決める。
    private var restoredUnsent: RestoredUnsent?
    private var restoredUnsentLoaded = false

    /// いま未送信の変更全体 (古い分から新しい分へ合成した形)。
    /// 端末への控えはこの形で残す。
    /// 送信中の変更は、結果がまだ分からないので、端末への控えでは
    /// 最初から「結果が分からないかもしれないもの」として差分を
    /// 控えに取り込んでおく。送信の応答を待っている間にアプリが
    /// 終わっても、次に起動したときに、サーバー側に残っているかも
    /// しれない値と最終的な意図を照合して送り直せるようにするため。
    /// 送信の結果が分かれば、その時点で控えは正しい内容に残し直す
    /// (成功すれば控え自体が消え、届かなかったことが明らかなら、
    /// 取り込んだ差分は控えから外れる)。
    private func outstandingSave() -> PendingSave? {
        var result: PendingSave?
        func accumulate(_ item: PendingSave, inFlight: Bool) {
            var composed = item
            if inFlight {
                // 送信中の差分は、結果が分からない場合の控えとして
                // 先に取り込んでおく (控え専用の写しで、本体の送信
                // 待ちの控えは結果が分かってから更新する)。
                composed.uncertainKeys.formUnion(
                    Self.changedKeys(base: item.base, desired: item.desired))
                composed.uncertain.absorb(base: item.base, desired: item.desired)
            }
            if let accumulated = result {
                var uncertain = accumulated.uncertain
                uncertain.formUnion(composed.uncertain)
                result = PendingSave(
                    id: composed.id, base: accumulated.base, desired: composed.desired,
                    generation: composed.generation,
                    syncGeneration: composed.syncGeneration,
                    uncertainKeys: accumulated.uncertainKeys.union(composed.uncertainKeys),
                    uncertain: uncertain,
                    // 並び替えの対象は新しい分を優先し、無ければ
                    // 古い分のものを引き継ぐ。
                    pinnedOrderIntent: composed.pinnedOrderIntent.isEmpty
                        ? accumulated.pinnedOrderIntent : composed.pinnedOrderIntent)
            } else {
                result = composed
            }
        }
        if let unsentSave { accumulate(unsentSave, inFlight: false) }
        if let inFlightSave { accumulate(inFlightSave, inFlight: true) }
        if let pendingSave { accumulate(pendingSave, inFlight: false) }
        return result
    }

    /// 未送信の変更を端末へ残す (アプリを終了しても消えないように
    /// するため)。残すのは、アカウントと接続先の目印と、変更の
    /// 前後の値だけで、認証の秘密は含めない。未送信分が無くなった
    /// ら控えも消す。状態が変わるたびに呼び直す。
    private func syncPersistedRecord() {
        let store = SettingsStore.shared
        guard let item = outstandingSave(),
              item.generation == store.authGeneration,
              item.syncGeneration == store.syncGeneration else {
            store.unsentSyncedSettingsData = nil
            return
        }
        let record: [String: Any] = [
            "identity": store.unsentSettingsIdentity,
            "base": Self.clientSettingsDictionary(from: item.base),
            "desired": Self.clientSettingsDictionary(from: item.desired),
            "uncertainKeys": Array(item.uncertainKeys),
            "uncertain": Self.uncertainRecordDictionary(from: item.uncertain),
            "pinnedOrderIntent": item.pinnedOrderIntent,
        ]
        store.unsentSyncedSettingsData =
            try? JSONSerialization.data(withJSONObject: record)
    }

    /// 結果が分からない送信の控えを、端末への保存の形 (辞書) に写す。
    private static func uncertainRecordDictionary(
        from record: UncertainRecord
    ) -> [String: Any] {
        [
            "addedKeywordKeys": Array(record.addedKeywordKeys),
            "removedKeywordKeys": Array(record.removedKeywordKeys),
            "addedUserIDs": Array(record.addedUserIDs),
            "removedUserIDs": Array(record.removedUserIDs),
            "addedPinnedIDs": Array(record.addedPinnedIDs),
            "removedPinnedIDs": Array(record.removedPinnedIDs),
            "pinnedOrderMayDiffer": record.pinnedOrderMayDiffer,
            "addedMylistKeys": Array(record.addedMylistKeys),
            "removedMylistKeys": Array(record.removedMylistKeys),
        ]
    }

    /// 端末への保存の形 (辞書) から、結果が分からない送信の控えを
    /// 読み戻す。
    private static func uncertainRecord(
        fromDictionary dict: [String: Any]
    ) -> UncertainRecord {
        var record = UncertainRecord()
        record.addedKeywordKeys = Set(dict["addedKeywordKeys"] as? [String] ?? [])
        record.removedKeywordKeys = Set(dict["removedKeywordKeys"] as? [String] ?? [])
        record.addedUserIDs = Set(dict["addedUserIDs"] as? [String] ?? [])
        record.removedUserIDs = Set(dict["removedUserIDs"] as? [String] ?? [])
        record.addedPinnedIDs = Set(dict["addedPinnedIDs"] as? [String] ?? [])
        record.removedPinnedIDs = Set(dict["removedPinnedIDs"] as? [String] ?? [])
        record.pinnedOrderMayDiffer = dict["pinnedOrderMayDiffer"] as? Bool ?? false
        record.addedMylistKeys = Set(dict["addedMylistKeys"] as? [String] ?? [])
        record.removedMylistKeys = Set(dict["removedMylistKeys"] as? [String] ?? [])
        return record
    }

    /// 端末に残した未送信の変更を読み出し、条件が合えば未送信分と
    /// して引き継ぐ。条件は、ログイン中かつ同期が入っていて、控えの
    /// 目印 (接続先とユーザー名) が今と一致すること。
    /// 同期が切れているとき (ログイン中の場合) と、目印が違うときは、
    /// その控えはもう送るべきでないものとして破棄する (同期を切った
    /// あとの変更や、別のアカウントの変更を送らないため。メモリ上の
    /// 送信待ちの扱いと同じ方針)。ログインしていないだけのときは、
    /// 次にログインした時点で照合し直すため残しておく。ログアウトの
    /// ときは、ログアウトの処理側で消す。
    private func adoptRestoredUnsentIfNeeded() {
        if !restoredUnsentLoaded {
            restoredUnsentLoaded = true
            restoredUnsent = Self.loadPersistedRecord()
        }
        guard let restored = restoredUnsent else { return }
        let store = SettingsStore.shared
        guard Self.isSyncEnabled else {
            if store.isLoggedIn {
                restoredUnsent = nil
                store.unsentSyncedSettingsData = nil
            }
            return
        }
        guard restored.identity == store.unsentSettingsIdentity else {
            restoredUnsent = nil
            store.unsentSyncedSettingsData = nil
            return
        }
        restoredUnsent = nil
        // すでに未送信分がある場合は、そちらの方が新しい状態なので
        // 控えは取り込まずに消す (通常は起きない)。
        guard unsentSave == nil, pendingSave == nil, inFlightSave == nil else {
            syncPersistedRecord()
            return
        }
        unsentSave = PendingSave(
            id: 0, base: restored.base, desired: restored.desired,
            generation: store.authGeneration,
            syncGeneration: store.syncGeneration,
            uncertainKeys: restored.uncertainKeys,
            uncertain: restored.uncertain,
            pinnedOrderIntent: restored.pinnedOrderIntent)
        syncPersistedRecord()
    }

    /// 端末に残した控えを読み出す。形が違う・読めないときは nil。
    private static func loadPersistedRecord() -> RestoredUnsent? {
        guard let data = SettingsStore.shared.unsentSyncedSettingsData,
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let identity = record["identity"] as? String,
              let baseDict = record["base"] as? [String: Any],
              let desiredDict = record["desired"] as? [String: Any]
        else { return nil }
        let base = settings(fromClientSettings: baseDict, fallback: .defaults)
        let uncertain: UncertainRecord
        if let uncertainDict = record["uncertain"] as? [String: Any] {
            uncertain = uncertainRecord(fromDictionary: uncertainDict)
        } else if let legacyDict = record["uncertainDesired"] as? [String: Any] {
            // 以前の版の控え (結果が分からない送信の時点の値一式) からは、
            // 土台との差分を、要素ごとの控えへ移し替える。
            var migrated = UncertainRecord()
            migrated.absorb(
                base: base,
                desired: settings(fromClientSettings: legacyDict, fallback: .defaults))
            uncertain = migrated
        } else {
            uncertain = UncertainRecord()
        }
        return RestoredUnsent(
            identity: identity,
            base: base,
            desired: settings(fromClientSettings: desiredDict, fallback: .defaults),
            uncertainKeys: Set(record["uncertainKeys"] as? [String] ?? []),
            uncertain: uncertain,
            pinnedOrderIntent: record["pinnedOrderIntent"] as? [String] ?? [])
    }

    /// 設定一式を、サーバーの利用者設定と同じ形の辞書に写す
    /// (端末への控えの保存に使う。読み戻しは
    /// settings(fromClientSettings:) で行う)。
    private static func clientSettingsDictionary(
        from settings: SyncedClientSettings
    ) -> [String: Any] {
        [
            "caption_font": settings.captionFont,
            "always_border_caption_text": settings.alwaysBorderCaptionText,
            "specify_caption_opacity": settings.specifyCaptionOpacity,
            "caption_opacity": settings.captionOpacity,
            "tv_show_superimpose": settings.tvShowSuperimpose,
            "video_show_superimpose": settings.videoShowSuperimpose,
            "comment_speed_rate": settings.commentSpeedRate,
            "comment_font_size": settings.commentFontSize,
            "prefer_posting_to_nicolive": settings.preferPostingToNicolive,
            "close_comment_form_after_sending": settings.closeCommentFormAfterSending,
            "mute_big_size_comments": settings.muteBigSizeComments,
            "mute_fixed_comments": settings.muteFixedComments,
            "mute_colored_comments": settings.muteColoredComments,
            "mute_consecutive_same_characters_comments":
                settings.muteConsecutiveSameCharactersComments,
            "mute_comment_keywords_normalize_alphanumeric_width_case":
                settings.muteCommentKeywordsNormalize,
            "muted_comment_keywords": settings.mutedCommentKeywords.map {
                ["match": $0.match, "pattern": $0.pattern] as [String: Any]
            },
            "muted_niconico_user_ids": settings.mutedNiconicoUserIDs,
            "video_watched_history_max_count": settings.videoWatchedHistoryMaxCount,
            "video_panel_active_tab": settings.videoPanelActiveTab,
            "tv_panel_active_tab": settings.tvPanelActiveTab,
            "tv_channel_sort_by_jikkyo_force": settings.tvChannelSortByJikkyoForce,
            "use_28hour_clock": settings.use28HourClock,
            "show_original_broadcast_time_during_playback":
                settings.showOriginalBroadcastTimeDuringPlayback,
            "pinned_channel_ids": settings.pinnedChannelIDs,
            "mylist": settings.mylist.map { $0.dictionary },
        ]
    }

    /// サーバー側の値を取り込んで、現在の値と違えば差し替える。
    /// 差し替えたかどうかを返す。同期が効いていない・取得に失敗した
    /// ときは何もせず false を返す。
    func refreshFromServer() async -> Bool {
        // 前回の起動で送れずに端末へ残した変更があれば、ここで
        // 引き継ぐ (条件が合わなければ破棄する)。
        adoptRestoredUnsentIfNeeded()
        guard Self.isSyncEnabled else { return false }
        // 未送信の変更が残っていたら、先に送り直す。取り込みを先に
        // すると、届いていない端末の値がサーバーの古い値で上書き
        // されてしまうため、取り込み自体は送り直しの後の回に回す。
        // 世代の違う未送信分は前の状態のものなので捨てる。
        if let unsent = unsentSave {
            unsentSave = nil
            if unsent.generation == SettingsStore.shared.authGeneration,
               unsent.syncGeneration == SettingsStore.shared.syncGeneration {
                if let pending = pendingSave,
                   pending.generation == unsent.generation,
                   pending.syncGeneration == unsent.syncGeneration {
                    // 送信待ちがある間は、その差分の元へ合成して引き継ぐ。
                    // 結果が分からない送信の控えも合わせて引き継ぐ
                    // (要素ごとの控えは合算する)。
                    var mergedUncertain = unsent.uncertain
                    mergedUncertain.formUnion(pending.uncertain)
                    pendingSave = PendingSave(
                        id: pending.id, base: unsent.base, desired: pending.desired,
                        generation: pending.generation,
                        syncGeneration: pending.syncGeneration,
                        uncertainKeys: unsent.uncertainKeys.union(pending.uncertainKeys),
                        uncertain: mergedUncertain,
                        pinnedOrderIntent: pending.pinnedOrderIntent.isEmpty
                            ? unsent.pinnedOrderIntent : pending.pinnedOrderIntent)
                } else if pendingSave == nil {
                    pendingSave = unsent
                    if !isSaving {
                        isSaving = true
                        consecutiveSaveFailures = 0
                        Task { await self.drainSaveQueue() }
                    }
                }
                syncPersistedRecord()
                return false
            }
            syncPersistedRecord()
        }
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
        // 同期が切れている間に端末へ残した未送信の変更があれば、
        // ここで破棄しておく (同期を入れ直したあとで、切る前の変更が
        // 復活して送られないようにするため。番組表分も同じ)。
        adoptRestoredUnsentIfNeeded()
        TimeTableSettingsStore.shared.adoptRestoredUnsentIfNeeded()
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

    /// 送信の結果を受け渡すための箱 (順番待ちの中から書き戻すため)。
    private final class SaveOutcomeBox: @unchecked Sendable {
        var value = SaveOutcome.notApplied
    }

    /// 変更をサーバーへ送る。結果 (送れた／届いていないことが明らか／
    /// 結果が分からない) を返す。
    /// 実際の送信は、他の保存 (視聴履歴・番組表の設定) と重なって
    /// 互いを上書きしないよう、保存の順番待ちに並んでから行う。
    /// 世代は呼び出し側が変更の時点で確定させたものを受け取る
    /// (順番待ちの実行時点で読み直さない)。
    private func saveToServer(
        base: SyncedClientSettings, desired: SyncedClientSettings,
        uncertainKeys: Set<String>, uncertain: UncertainRecord,
        pinnedOrderIntent: [String],
        expectedGeneration: Int, expectedSyncGeneration: Int
    ) async -> SaveOutcome {
        let box = SaveOutcomeBox()
        await ClientSettingsSaveQueue.shared.run {
            box.value = await self.saveToServerSerial(
                base: base, desired: desired,
                uncertainKeys: uncertainKeys, uncertain: uncertain,
                pinnedOrderIntent: pinnedOrderIntent,
                expectedGeneration: expectedGeneration,
                expectedSyncGeneration: expectedSyncGeneration)
        }
        return box.value
    }

    /// 変更をサーバーへ送る本体。手順は番組表・視聴履歴と同じ:
    /// 送る直前に最新を取得 → 編集で変わった項目だけを最新の値へ
    /// 適用する → last_synced_at を今に更新して送る。422 (その間に
    /// 他の端末が先に更新した) が返ったら、1回だけ取り直して、
    /// 同じ差分を新しい最新へ適用し直す。
    /// 失敗は、送信が適用されていないことが分かるもの (送信前の
    /// 取得の失敗、サーバーからの拒否の応答) と、結果が分からない
    /// もの (応答が返ってこなかった失敗と、サーバー側の都合による
    /// 失敗 (5xx)。保存が済んだ後に返ってくることがあるため) に
    /// 分けて返す。
    private func saveToServerSerial(
        base: SyncedClientSettings, desired: SyncedClientSettings,
        uncertainKeys: Set<String>, uncertain: UncertainRecord,
        pinnedOrderIntent: [String],
        expectedGeneration: Int, expectedSyncGeneration: Int
    ) async -> SaveOutcome {
        // 照合は、変更が起きた時点の世代で行う。順番待ちの間に
        // ログインし直していたら、取得は前のログイン・送信は
        // 新しいログインになってしまうため、この回の保存は打ち切る。
        // 同期の世代も同じで、順番待ちの間に同期を切られていたら、
        // この回の保存は打ち切る (切った後に送られてしまわないため)。
        let generation = expectedGeneration
        guard SettingsStore.shared.authGeneration == generation,
              SettingsStore.shared.syncGeneration == expectedSyncGeneration,
              SettingsStore.shared.syncSettings,
              SettingsStore.shared.isLoggedIn else { return .notApplied }
        for _ in 0..<2 {
            // 送信前の取得が失敗した場合は、送信自体を行っていない
            // ので、届いていないことが明らかな失敗として扱う。
            let fetched: [String: Any]
            do {
                fetched = try await APIClient.shared.fetchClientSettings()
            } catch {
                return .notApplied
            }
            guard SettingsStore.shared.authGeneration == generation,
                  SettingsStore.shared.syncGeneration == expectedSyncGeneration,
                  SettingsStore.shared.syncSettings,
                  SettingsStore.shared.isLoggedIn else { return .notApplied }
            var clientSettings = fetched
            Self.applyEdits(base: base, desired: desired,
                            uncertainKeys: uncertainKeys,
                            uncertain: uncertain,
                            pinnedOrderIntent: pinnedOrderIntent,
                            to: &clientSettings)
            clientSettings["last_synced_at"] = Date().timeIntervalSince1970
            do {
                try await APIClient.shared.updateClientSettings(
                    clientSettings, expectedAuthGeneration: generation)
                return .success
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch let APIError.badStatus(code) where (500..<600).contains(code) {
                // サーバー側の都合による失敗 (5xx) は、保存が済んだ
                // 後に返ってくることもある (中継の都合で 504 が返る
                // 間に保存が終わっている場合など) ため、適用されて
                // いないとは断定できない。結果が分からないものとして
                // 扱い、次回の保存で意図と照合して送り直す。
                return .unknown
            } catch is APIError {
                // サーバーから応答が返ってきた失敗 (拒否など) と、
                // 送信前に止まった失敗は、適用されていないことが
                // 分かる失敗として扱う。
                return .notApplied
            } catch {
                // 応答が返ってこなかった失敗。サーバー側で保存が
                // 済んでいるかもしれないので、結果は分からない。
                return .unknown
            }
        }
        // 422 が続いた = サーバーが受け付けなかった。
        return .notApplied
    }

    /// 編集の前後で変わった項目の、サーバー側の項目名の一覧。
    /// 結果が分からない送信に含まれていた項目を特定するために使う
    /// (applyEdits の判定と揃える)。
    private static func changedKeys(
        base: SyncedClientSettings, desired: SyncedClientSettings
    ) -> [String] {
        var keys: [String] = []
        if base.captionFont != desired.captionFont { keys.append("caption_font") }
        if base.alwaysBorderCaptionText != desired.alwaysBorderCaptionText {
            keys.append("always_border_caption_text")
        }
        if base.specifyCaptionOpacity != desired.specifyCaptionOpacity {
            keys.append("specify_caption_opacity")
        }
        if base.captionOpacity != desired.captionOpacity { keys.append("caption_opacity") }
        if base.tvShowSuperimpose != desired.tvShowSuperimpose {
            keys.append("tv_show_superimpose")
        }
        if base.videoShowSuperimpose != desired.videoShowSuperimpose {
            keys.append("video_show_superimpose")
        }
        if base.commentSpeedRate != desired.commentSpeedRate {
            keys.append("comment_speed_rate")
        }
        if base.commentFontSize != desired.commentFontSize {
            keys.append("comment_font_size")
        }
        if base.preferPostingToNicolive != desired.preferPostingToNicolive {
            keys.append("prefer_posting_to_nicolive")
        }
        if base.closeCommentFormAfterSending != desired.closeCommentFormAfterSending {
            keys.append("close_comment_form_after_sending")
        }
        if base.muteBigSizeComments != desired.muteBigSizeComments {
            keys.append("mute_big_size_comments")
        }
        if base.muteFixedComments != desired.muteFixedComments {
            keys.append("mute_fixed_comments")
        }
        if base.muteColoredComments != desired.muteColoredComments {
            keys.append("mute_colored_comments")
        }
        if base.muteConsecutiveSameCharactersComments
            != desired.muteConsecutiveSameCharactersComments {
            keys.append("mute_consecutive_same_characters_comments")
        }
        if base.muteCommentKeywordsNormalize != desired.muteCommentKeywordsNormalize {
            keys.append("mute_comment_keywords_normalize_alphanumeric_width_case")
        }
        if base.mutedCommentKeywords != desired.mutedCommentKeywords {
            keys.append("muted_comment_keywords")
        }
        if base.mutedNiconicoUserIDs != desired.mutedNiconicoUserIDs {
            keys.append("muted_niconico_user_ids")
        }
        if base.videoWatchedHistoryMaxCount != desired.videoWatchedHistoryMaxCount {
            keys.append("video_watched_history_max_count")
        }
        if base.videoPanelActiveTab != desired.videoPanelActiveTab {
            keys.append("video_panel_active_tab")
        }
        if base.tvPanelActiveTab != desired.tvPanelActiveTab {
            keys.append("tv_panel_active_tab")
        }
        if base.tvChannelSortByJikkyoForce != desired.tvChannelSortByJikkyoForce {
            keys.append("tv_channel_sort_by_jikkyo_force")
        }
        if base.use28HourClock != desired.use28HourClock {
            keys.append("use_28hour_clock")
        }
        if base.showOriginalBroadcastTimeDuringPlayback
            != desired.showOriginalBroadcastTimeDuringPlayback {
            keys.append("show_original_broadcast_time_during_playback")
        }
        if base.pinnedChannelIDs != desired.pinnedChannelIDs {
            keys.append("pinned_channel_ids")
        }
        if base.mylist != desired.mylist { keys.append("mylist") }
        return keys
    }

    /// 編集の前後で変わった項目だけを、取得した最新のサーバー値へ
    /// 適用する。変わっていない項目は最新の値のまま触らない。
    /// 字幕フォントも同じ扱いで、利用者が選び直したときだけ送る値で
    /// 置き換えるため、サーバー側にあるアプリの知らない名前の
    /// フォントが、無関係な保存で消えることはない。
    /// 結果が分からない送信に含まれていた項目 (uncertainKeys) は、
    /// 編集の前後で値が同じでも、取得した最新の値と最終的な意図が
    /// 食い違えば意図の値で送り直す。サーバー側にその送信の値が
    /// 残っているかもしれず、値の差分だけでは「変更なし」になって
    /// しまうため (その間に利用者が値を元へ戻した場合など)。
    /// 配列は、要素ごとの控え (uncertain) も使う。その送信で増えた
    /// かもしれない要素は、最終的な意図に無ければ落とす対象に足し、
    /// 減ったかもしれない要素は、最終的な意図にあれば戻す対象に足す
    /// (その間に利用者が消した要素を登録し直したり、並び替えを
    /// 取り消したりした場合に、意図どおりにするため)。
    private static func applyEdits(
        base: SyncedClientSettings, desired: SyncedClientSettings,
        uncertainKeys: Set<String>, uncertain: UncertainRecord,
        pinnedOrderIntent: [String],
        to clientSettings: inout [String: Any]
    ) {
        if base.captionFont != desired.captionFont
            || (uncertainKeys.contains("caption_font")
                && !jsonEquals(clientSettings["caption_font"], desired.captionFont)) {
            clientSettings["caption_font"] = desired.captionFont
        }
        if base.alwaysBorderCaptionText != desired.alwaysBorderCaptionText
            || (uncertainKeys.contains("always_border_caption_text")
                && !jsonEquals(clientSettings["always_border_caption_text"],
                               desired.alwaysBorderCaptionText)) {
            clientSettings["always_border_caption_text"] = desired.alwaysBorderCaptionText
        }
        if base.specifyCaptionOpacity != desired.specifyCaptionOpacity
            || (uncertainKeys.contains("specify_caption_opacity")
                && !jsonEquals(clientSettings["specify_caption_opacity"],
                               desired.specifyCaptionOpacity)) {
            clientSettings["specify_caption_opacity"] = desired.specifyCaptionOpacity
        }
        if base.captionOpacity != desired.captionOpacity
            || (uncertainKeys.contains("caption_opacity")
                && !jsonEquals(clientSettings["caption_opacity"], desired.captionOpacity)) {
            clientSettings["caption_opacity"] = desired.captionOpacity
        }
        if base.tvShowSuperimpose != desired.tvShowSuperimpose
            || (uncertainKeys.contains("tv_show_superimpose")
                && !jsonEquals(clientSettings["tv_show_superimpose"],
                               desired.tvShowSuperimpose)) {
            clientSettings["tv_show_superimpose"] = desired.tvShowSuperimpose
        }
        if base.videoShowSuperimpose != desired.videoShowSuperimpose
            || (uncertainKeys.contains("video_show_superimpose")
                && !jsonEquals(clientSettings["video_show_superimpose"],
                               desired.videoShowSuperimpose)) {
            clientSettings["video_show_superimpose"] = desired.videoShowSuperimpose
        }
        if base.commentSpeedRate != desired.commentSpeedRate
            || (uncertainKeys.contains("comment_speed_rate")
                && !jsonEquals(clientSettings["comment_speed_rate"],
                               desired.commentSpeedRate)) {
            clientSettings["comment_speed_rate"] = desired.commentSpeedRate
        }
        if base.commentFontSize != desired.commentFontSize
            || (uncertainKeys.contains("comment_font_size")
                && !jsonEquals(clientSettings["comment_font_size"],
                               desired.commentFontSize)) {
            clientSettings["comment_font_size"] = desired.commentFontSize
        }
        if base.preferPostingToNicolive != desired.preferPostingToNicolive
            || (uncertainKeys.contains("prefer_posting_to_nicolive")
                && !jsonEquals(clientSettings["prefer_posting_to_nicolive"],
                               desired.preferPostingToNicolive)) {
            clientSettings["prefer_posting_to_nicolive"] = desired.preferPostingToNicolive
        }
        if base.closeCommentFormAfterSending != desired.closeCommentFormAfterSending
            || (uncertainKeys.contains("close_comment_form_after_sending")
                && !jsonEquals(clientSettings["close_comment_form_after_sending"],
                               desired.closeCommentFormAfterSending)) {
            clientSettings["close_comment_form_after_sending"] =
                desired.closeCommentFormAfterSending
        }
        if base.muteBigSizeComments != desired.muteBigSizeComments
            || (uncertainKeys.contains("mute_big_size_comments")
                && !jsonEquals(clientSettings["mute_big_size_comments"],
                               desired.muteBigSizeComments)) {
            clientSettings["mute_big_size_comments"] = desired.muteBigSizeComments
        }
        if base.muteFixedComments != desired.muteFixedComments
            || (uncertainKeys.contains("mute_fixed_comments")
                && !jsonEquals(clientSettings["mute_fixed_comments"],
                               desired.muteFixedComments)) {
            clientSettings["mute_fixed_comments"] = desired.muteFixedComments
        }
        if base.muteColoredComments != desired.muteColoredComments
            || (uncertainKeys.contains("mute_colored_comments")
                && !jsonEquals(clientSettings["mute_colored_comments"],
                               desired.muteColoredComments)) {
            clientSettings["mute_colored_comments"] = desired.muteColoredComments
        }
        if base.muteConsecutiveSameCharactersComments
            != desired.muteConsecutiveSameCharactersComments
            || (uncertainKeys.contains("mute_consecutive_same_characters_comments")
                && !jsonEquals(
                    clientSettings["mute_consecutive_same_characters_comments"],
                    desired.muteConsecutiveSameCharactersComments)) {
            clientSettings["mute_consecutive_same_characters_comments"] =
                desired.muteConsecutiveSameCharactersComments
        }
        if base.muteCommentKeywordsNormalize != desired.muteCommentKeywordsNormalize
            || (uncertainKeys.contains(
                    "mute_comment_keywords_normalize_alphanumeric_width_case")
                && !jsonEquals(
                    clientSettings[
                        "mute_comment_keywords_normalize_alphanumeric_width_case"],
                    desired.muteCommentKeywordsNormalize)) {
            clientSettings["mute_comment_keywords_normalize_alphanumeric_width_case"] =
                desired.muteCommentKeywordsNormalize
        }
        if base.mutedCommentKeywords != desired.mutedCommentKeywords
            || uncertainKeys.contains("muted_comment_keywords") {
            // 結果が分からない送信で増えたかもしれないキーワードが
            // 最終的な意図では消えている場合は、その分も落とす対象に
            // 足す。逆に、その送信で消えたかもしれないキーワードが
            // 最終的な意図では戻っている場合は、戻す対象に足す。
            let desiredKeys = Set(desired.mutedCommentKeywords.map(Self.keywordKey))
            let extraRemoved = uncertain.addedKeywordKeys.subtracting(desiredKeys)
            let extraAdded = uncertain.removedKeywordKeys.intersection(desiredKeys)
            clientSettings["muted_comment_keywords"] = mergedKeywordEntries(
                latest: clientSettings["muted_comment_keywords"],
                base: base.mutedCommentKeywords, desired: desired.mutedCommentKeywords,
                extraRemovedKeys: extraRemoved, extraAddedKeys: extraAdded)
        }
        if base.mutedNiconicoUserIDs != desired.mutedNiconicoUserIDs
            || uncertainKeys.contains("muted_niconico_user_ids") {
            let desiredIDs = Set(desired.mutedNiconicoUserIDs)
            let extraRemoved = uncertain.addedUserIDs.subtracting(desiredIDs)
            let extraAdded = uncertain.removedUserIDs.intersection(desiredIDs)
            clientSettings["muted_niconico_user_ids"] = mergedStringEntries(
                latest: clientSettings["muted_niconico_user_ids"],
                base: base.mutedNiconicoUserIDs, desired: desired.mutedNiconicoUserIDs,
                extraRemoved: extraRemoved, extraAdded: extraAdded)
        }
        if base.videoWatchedHistoryMaxCount != desired.videoWatchedHistoryMaxCount
            || (uncertainKeys.contains("video_watched_history_max_count")
                && !jsonEquals(clientSettings["video_watched_history_max_count"],
                               desired.videoWatchedHistoryMaxCount)) {
            clientSettings["video_watched_history_max_count"] =
                desired.videoWatchedHistoryMaxCount
        }
        if base.videoPanelActiveTab != desired.videoPanelActiveTab
            || (uncertainKeys.contains("video_panel_active_tab")
                && !jsonEquals(clientSettings["video_panel_active_tab"],
                               desired.videoPanelActiveTab)) {
            clientSettings["video_panel_active_tab"] = desired.videoPanelActiveTab
        }
        if base.tvPanelActiveTab != desired.tvPanelActiveTab
            || (uncertainKeys.contains("tv_panel_active_tab")
                && !jsonEquals(clientSettings["tv_panel_active_tab"],
                               desired.tvPanelActiveTab)) {
            clientSettings["tv_panel_active_tab"] = desired.tvPanelActiveTab
        }
        if base.tvChannelSortByJikkyoForce != desired.tvChannelSortByJikkyoForce
            || (uncertainKeys.contains("tv_channel_sort_by_jikkyo_force")
                && !jsonEquals(clientSettings["tv_channel_sort_by_jikkyo_force"],
                               desired.tvChannelSortByJikkyoForce)) {
            clientSettings["tv_channel_sort_by_jikkyo_force"] = desired.tvChannelSortByJikkyoForce
        }
        if base.use28HourClock != desired.use28HourClock
            || (uncertainKeys.contains("use_28hour_clock")
                && !jsonEquals(clientSettings["use_28hour_clock"],
                               desired.use28HourClock)) {
            clientSettings["use_28hour_clock"] = desired.use28HourClock
        }
        if base.showOriginalBroadcastTimeDuringPlayback
            != desired.showOriginalBroadcastTimeDuringPlayback
            || (uncertainKeys.contains("show_original_broadcast_time_during_playback")
                && !jsonEquals(
                    clientSettings["show_original_broadcast_time_during_playback"],
                    desired.showOriginalBroadcastTimeDuringPlayback)) {
            clientSettings["show_original_broadcast_time_during_playback"] =
                desired.showOriginalBroadcastTimeDuringPlayback
        }
        if base.pinnedChannelIDs != desired.pinnedChannelIDs
            || uncertainKeys.contains("pinned_channel_ids") {
            let desiredIDs = Set(desired.pinnedChannelIDs)
            let extraRemoved = uncertain.addedPinnedIDs.subtracting(desiredIDs)
            let extraAdded = uncertain.removedPinnedIDs.intersection(desiredIDs)
            clientSettings["pinned_channel_ids"] = mergedPinnedChannelIDs(
                latest: clientSettings["pinned_channel_ids"],
                base: base.pinnedChannelIDs, desired: desired.pinnedChannelIDs,
                extraRemoved: extraRemoved, extraAdded: extraAdded,
                forceDesiredOrder: uncertain.pinnedOrderMayDiffer,
                orderIntent: pinnedOrderIntent)
        }
        if base.mylist != desired.mylist
            || uncertainKeys.contains("mylist") {
            let desiredKeys = Set(desired.mylist.map(Self.mylistKey))
            let extraRemoved = uncertain.addedMylistKeys.subtracting(desiredKeys)
            let extraAdded = uncertain.removedMylistKeys.intersection(desiredKeys)
            // 削除して登録し直した要素は、新しい登録として扱う
            // (Web 版も、追加のたびにその時点の時刻で登録する)。
            // 編集の前後に同じ要素があり、登録した時刻だけが
            // 変わっている場合は再登録なので、その要素の時刻を
            // 新しい値へ更新する対象として渡す。
            var reRegistered: [String: Double] = [:]
            let baseByKey = Dictionary(
                base.mylist.map { (Self.mylistKey($0), $0) },
                uniquingKeysWith: { first, _ in first })
            for entry in desired.mylist {
                let entryKey = Self.mylistKey(entry)
                if let before = baseByKey[entryKey],
                   before.createdAt != entry.createdAt {
                    reRegistered[entryKey] = entry.createdAt
                }
            }
            clientSettings["mylist"] = mergedMylistEntries(
                latest: clientSettings["mylist"],
                base: base.mylist, desired: desired.mylist,
                extraRemovedKeys: extraRemoved, extraAddedKeys: extraAdded,
                reRegisteredCreatedAt: reRegistered)
        }
    }

    /// 取得したサーバー側の値と、送りたい値が一致するか
    /// (JSON から読んだ値同士の比較)。結果が分からない送信の項目を、
    /// 意図どおりになっているか照合するために使う。
    private static func jsonEquals(_ raw: Any?, _ value: Bool) -> Bool {
        (raw as? NSNumber)?.boolValue == value
    }

    private static func jsonEquals(_ raw: Any?, _ value: Double) -> Bool {
        (raw as? NSNumber)?.doubleValue == value
    }

    private static func jsonEquals(_ raw: Any?, _ value: Int) -> Bool {
        (raw as? NSNumber)?.intValue == value
    }

    private static func jsonEquals(_ raw: Any?, _ value: String) -> Bool {
        (raw as? String) == value
    }

    /// ミュートキーワードの配列へ、編集の差分 (追加と削除) だけを
    /// 適用する。土台は最新のサーバー値で、利用者がこの端末で
    /// 消した要素だけを落とし、足した要素だけを末尾に加える。
    /// 編集に含まれない要素 (他の端末が足した正常な形の要素も、
    /// 形の違う要素も) はそのまま残る。
    private static func mergedKeywordEntries(
        latest: Any?, base: [MutedCommentKeyword], desired: [MutedCommentKeyword],
        extraRemovedKeys: Set<String> = [], extraAddedKeys: Set<String> = []
    ) -> [Any] {
        func key(match: String, pattern: String) -> String { match + "\u{1}" + pattern }
        let baseKeys = Set(base.map { key(match: $0.match, pattern: $0.pattern) })
        let desiredKeys = Set(desired.map { key(match: $0.match, pattern: $0.pattern) })
        // 結果が分からない送信で入った分 (extraRemovedKeys) も、
        // 最終的な意図に無いものは落とす対象に含める。
        let removedKeys = baseKeys.subtracting(desiredKeys).union(extraRemovedKeys)
        var result: [Any] = []
        var presentKeys = Set<String>()
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
                if removedKeys.contains(entryKey) { continue }
                result.append(raw)
                presentKeys.insert(entryKey)
            }
        }
        // 土台に無い要素は足す。土台にある要素は通常は最新の値に
        // 残っている前提だが、結果が分からない送信で消えたかも
        // しれない要素 (extraAddedKeys) は、最新の値に無ければ
        // 最終的な意図の要素で戻す。
        for keyword in desired
        where (!baseKeys.contains(key(match: keyword.match, pattern: keyword.pattern))
                || extraAddedKeys.contains(key(match: keyword.match, pattern: keyword.pattern)))
            && !presentKeys.contains(key(match: keyword.match, pattern: keyword.pattern)) {
            result.append(["match": keyword.match, "pattern": keyword.pattern] as [String: Any])
        }
        return result
    }

    /// マイリストの配列へ、編集の差分だけを適用する。
    /// キーワードと同じ考え方で、照合の鍵は種類と番号の組。
    /// 利用者がこの端末で消した登録は復活せず、他の端末が足した
    /// 登録は消えない。
    /// 削除して登録し直した要素 (reRegisteredCreatedAt に鍵がある
    /// 要素) は、新しい登録として扱い、最新の値に残っている要素の
    /// 登録した時刻だけを新しい値へ差し替える (他の項目や、アプリの
    /// 知らない項目はそのまま残す)。最新の値に残っていない場合も、
    /// 再登録は利用者の明示的な操作なので、最終的な意図の要素で
    /// 復元する (他の端末の削除より再登録を優先する仕様)。
    private static func mergedMylistEntries(
        latest: Any?, base: [MylistEntry], desired: [MylistEntry],
        extraRemovedKeys: Set<String> = [], extraAddedKeys: Set<String> = [],
        reRegisteredCreatedAt: [String: Double] = [:]
    ) -> [Any] {
        func key(type: String, id: Int) -> String { type + "#" + String(id) }
        let baseKeys = Set(base.map { key(type: $0.type, id: $0.id) })
        let desiredKeys = Set(desired.map { key(type: $0.type, id: $0.id) })
        let removedKeys = baseKeys.subtracting(desiredKeys).union(extraRemovedKeys)
        var result: [Any] = []
        var presentKeys = Set<String>()
        if let rawEntries = latest as? [Any] {
            for raw in rawEntries {
                guard let entry = raw as? [String: Any],
                      let parsed = MylistEntry(dictionary: entry)
                else {
                    result.append(raw)
                    continue
                }
                let entryKey = key(type: parsed.type, id: parsed.id)
                if removedKeys.contains(entryKey) { continue }
                if let newCreatedAt = reRegisteredCreatedAt[entryKey],
                   parsed.createdAt != newCreatedAt {
                    var updated = entry
                    updated["created_at"] = newCreatedAt
                    result.append(updated)
                } else {
                    result.append(raw)
                }
                presentKeys.insert(entryKey)
            }
        }
        // キーワードと同じく、結果が分からない送信で消えたかも
        // しれない要素 (extraAddedKeys) は、最新の値に無ければ
        // 最終的な意図の要素で戻す。
        // この端末で明示的に登録し直した要素 (reRegisteredCreatedAt
        // に鍵がある要素) も、最新の値に無ければ最終的な意図の
        // 要素で戻す。再登録は利用者の明示的な操作なので、他の
        // 端末の削除や、以前の削除の適用でサーバー側から消えて
        // いても、再登録を優先して復元する。自分が触っていない
        // 要素は対象にならないため、無関係な削除が復活することは
        // ない。
        for entry in desired
        where (!baseKeys.contains(key(type: entry.type, id: entry.id))
                || extraAddedKeys.contains(key(type: entry.type, id: entry.id))
                || reRegisteredCreatedAt[key(type: entry.type, id: entry.id)] != nil)
            && !presentKeys.contains(key(type: entry.type, id: entry.id)) {
            result.append(entry.dictionary as Any)
        }
        return result
    }

    /// 文字列の配列 (ミュートするユーザー ID) へ、編集の差分だけを
    /// 適用する。文字列でない要素はそのまま残す。
    private static func mergedStringEntries(
        latest: Any?, base: [String], desired: [String],
        extraRemoved: Set<String> = [], extraAdded: Set<String> = []
    ) -> [Any] {
        let removed = Set(base).subtracting(Set(desired)).union(extraRemoved)
        var result: [Any] = []
        var present = Set<String>()
        if let rawEntries = latest as? [Any] {
            for raw in rawEntries {
                guard let value = raw as? String else {
                    result.append(raw)
                    continue
                }
                if removed.contains(value) { continue }
                result.append(raw)
                present.insert(value)
            }
        }
        // キーワードと同じく、結果が分からない送信で消えたかも
        // しれない要素 (extraAdded) は、最新の値に無ければ戻す。
        for value in desired
        where (!base.contains(value) || extraAdded.contains(value))
            && !present.contains(value) {
            result.append(value)
        }
        return result
    }

    /// ピン留めチャンネルの配列へ、編集の差分だけを適用する。
    /// 土台は最新のサーバー値で、利用者がこの端末で消した要素だけを
    /// 落とし、足した要素だけを末尾に加える。
    /// 並び替えは、この端末で実際に並び替えた場合だけ適用する。
    /// 編集前と編集後で、共通する要素の相対的な順序が同じなら
    /// (追加・削除だけの場合)、最新の並び順はそのまま保つ (自分の
    /// 古い並びで並べ直すと、他の端末の並び替えを取り消してしまう
    /// ため)。並び替えた場合は、最新の並びの上で、共通する要素が
    /// 占めている枠の中でだけ順序を入れ替える。他の端末が足した
    /// 要素や、他の端末が消した要素、文字列でない要素は、そのまま
    /// の位置に残る。
    /// 結果が分からない送信で並び順が変わったかもしれない場合
    /// (forceDesiredOrder) は、編集前後の相対的な順序が同じでも、
    /// 最終的な意図の並びを適用する。その送信で並び替えた後に
    /// 利用者が並びを取り消すと、編集前後の順序が同じになって
    /// しまい、サーバーに残った並びを意図どおりに戻せないため。
    /// 明示的な並び替えの対象 (orderIntent) に含まれる要素は、
    /// 編集の合成で差分の元に無くなった (その編集で追加された)
    /// 要素でも、並び替えの対象に含める。追加された要素を明示的に
    /// 動かした場合に、その移動が合成の対象から漏れて効かなく
    /// なるのを防ぐため。対象でない追加要素は従来どおり末尾に
    /// 加わるだけで、他の端末の並び順は保たれる。
    /// 対象の追加要素が、まだサーバー側に無い (追加の保存がまだ
    /// 届いていない) 場合も、最終的な並びの中で既存の要素より前に
    /// 置かれているものは、先に結果へ入れてから対象の枠を並べ
    /// 替えて、意図どおりの位置に置く。結果が分からない送信で
    /// 消えたかもしれない要素を登録し直した場合も、明示的に
    /// 戻す対象であれば同じ扱いにする。サーバー側で削除された
    /// 既存の要素は、対象に含まれていても結果には無いため、
    /// 復活することはない。
    /// サーバー側の値が配列の形でないときは、受け皿として利用者の
    /// 並びそのものを返す。
    private static func mergedPinnedChannelIDs(
        latest: Any?, base: [String], desired: [String],
        extraRemoved: Set<String> = [], extraAdded: Set<String> = [],
        forceDesiredOrder: Bool = false,
        orderIntent: [String] = []
    ) -> [Any] {
        guard let rawEntries = latest as? [Any] else { return desired }
        let baseSet = Set(base)
        let desiredSet = Set(desired)
        // 結果が分からない送信で入った分 (extraRemoved) も、最終的な
        // 意図に無いものは落とす対象に含める。
        let removed = baseSet.subtracting(desiredSet).union(extraRemoved)
        // 並び替えの対象 (編集前からあって編集後も残る要素) と、
        // 編集後の並びにおける順位。明示的に並び替えた対象に
        // 含まれる要素は、差分の元に無い (追加された) 要素でも
        // 対象に含める。落とす対象になった要素は除く。
        let keptSet = baseSet.intersection(desiredSet)
        let targetSet = keptSet
            .union(Set(orderIntent).intersection(desiredSet))
            .subtracting(removed)
        var rank: [String: Int] = [:]
        for (index, value) in desired.enumerated() where targetSet.contains(value) {
            if rank[value] == nil { rank[value] = index }
        }
        // 最新の並びから、この端末で消した要素だけを落とす。
        var result: [Any] = rawEntries.filter { raw in
            guard let value = raw as? String else { return true }
            return !removed.contains(value)
        }
        // この端末で実際に並び替えたかどうかは、共通する要素の
        // 相対的な順序が編集前後で変わったかで判定する。変わって
        // いなければ、最新の並び順をそのまま保つ。結果が分からない
        // 送信で並び順が変わったかもしれない場合だけは、編集前後が
        // 同じでも最終的な意図の並びを適用する。差分の元に無い
        // 要素 (追加された要素) を明示的に動かした場合は、その要素が
        // 最新の並びの中にあれば、並び替えの対象として扱う。
        let keptInBaseOrder = base.filter { keptSet.contains($0) }
        let keptInDesiredOrder = desired.filter { keptSet.contains($0) }
        let presentValues = Set(result.compactMap { $0 as? String })
        let addedTargets = targetSet.subtracting(baseSet)
        let movedAddedPresent = addedTargets.intersection(presentValues)
        // 並び替えの対象で、この編集で追加する要素が最新の並びに
        // 無い場合、その要素には並べ替えの枠が無いため、このまま
        // では最後に末尾へ追加されるだけになり、明示的な並び替えが
        // 効かない。その要素が、最終的な並びの中で既存の要素より
        // 前に置かれている場合 (末尾への追加では意図どおりに
        // ならない場合) に限り、並び替えの対象として扱う。追加する
        // 要素がすべて既存の要素より後ろにある場合は、従来どおり
        // 末尾への追加で意図どおりになるため、並び替えは行わない
        // (他の端末の並び順を保つため)。
        let desiredTargets = desired.filter { targetSet.contains($0) }
        var addedTargetBeforeKept = false
        if let lastKeptIndex = desiredTargets.lastIndex(where: {
            keptSet.contains($0)
        }) {
            addedTargetBeforeKept = desiredTargets[..<lastKeptIndex]
                .contains { addedTargets.contains($0) }
        }
        // 先に結果へ入れる対象は、この編集で追加された要素に加え、
        // 結果が分からない送信で消えたかもしれない要素のうち、
        // 明示的に戻す対象で並び替えの対象にも含まれるものも
        // 含める。元の並びにあった要素は追加の対象から漏れるため、
        // そのままでは並び替えが効かず、最後に末尾へ戻されて
        // しまう。落とす対象になった要素は並び替えの対象から
        // 除かれているため、ここには含まれない。
        let preInsertTargets = addedTargets.union(
            extraAdded.intersection(targetSet))
        if keptInBaseOrder != keptInDesiredOrder || forceDesiredOrder
            || !movedAddedPresent.isEmpty || addedTargetBeforeKept {
            // 並び替えの対象で、最新の並びにまだ無い追加要素を、
            // 対象の枠を並べ替える前に結果へ入れておく。入れる位置は
            // この後の並べ替えで決まるため、ここでは末尾に入れる。
            for value in desired
            where preInsertTargets.contains(value)
                && !presentValues.contains(value) {
                result.append(value)
            }
            // 対象の要素が占めている枠の中でだけ、順序を入れ替える。
            // 枠の位置そのものは動かさないため、対象でない要素 (他の
            // 端末の追加分や文字列でない要素) の位置は変わらない。
            let keptSlots = result.indices.filter {
                (result[$0] as? String).map { targetSet.contains($0) } ?? false
            }
            let keptValues = keptSlots.compactMap { result[$0] as? String }
            let sortedKept = keptValues.sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            for (slot, value) in zip(keptSlots, sortedKept) {
                result[slot] = value
            }
        }
        // この端末で足した要素を、末尾に加える。結果が分からない
        // 送信で消えたかもしれない要素 (extraAdded) は、土台に
        // あっても、最新の値に無ければ末尾に戻す。
        var present = Set(result.compactMap { $0 as? String })
        for value in desired
        where (!baseSet.contains(value) || extraAdded.contains(value))
            && !present.contains(value) {
            result.append(value)
            present.insert(value)
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
