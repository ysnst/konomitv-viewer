import Foundation
import Security

extension Notification.Name {
    /// 表示の大きさ (SettingsStore.uiScalePercent) が変わったときの通知。
    /// タブバー (MainTabBarController) と設定画面 (SettingsViewController)
    /// が受けて、表示を新しい大きさで組み直す。
    static let uiScaleDidChange = Notification.Name("ViewerUIScaleDidChange")
}

/// 機密な値 (パスワード、アクセストークン) の保存先。端末のキーチェーンを使う。
enum KeychainStore {
    private static let service = "jp.tatsuya0902.konomitv.viewer"

    static func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 値を保存する。nil または空文字なら削除する。
    static func setString(_ value: String?, forKey key: String) {
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            SecItemDelete(baseQuery(forKey: key) as CFDictionary)
            return
        }
        let query = baseQuery(forKey: key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// 再生の対象。Web 版の設定の分け方に対応する (テレビ = 生放送、ビデオ = 録画)。
enum PlaybackMedia {
    case tv
    case video
}

/// 回線の区分。Web 版の画質の分け方 (Wi-Fi 回線時 / モバイル回線時) に対応する。
/// 再生を始めるときに NetworkMonitor で判定し、その再生の間は固定する。
enum PlaybackProfile {
    case wifi
    case cellular
}

/// 接続先などの設定を UserDefaults に保存する。
/// キーは Settings.bundle (設定アプリ側の編集画面) と共用する。
/// パスワードとアクセストークンだけはキーチェーンに置く。
final class SettingsStore {
    static let shared = SettingsStore()

    private enum Key {
        static let url = "viewer_url"
        static let cfClientID = "viewer_cf_client_id"
        static let cfClientSecret = "viewer_cf_client_secret"
        static let quality = "viewer_quality"
        static let dataSaverMode = "viewer_data_saver_mode"
        static let username = "viewer_username"
        // 画質・再生まわりの正式な設定 (Web 版のキー名に viewer_ を付けたもの)。
        static let tvQuality = "viewer_tv_streaming_quality"
        static let tvQualityCellular = "viewer_tv_streaming_quality_cellular"
        static let tvDataSaverMode = "viewer_tv_data_saver_mode"
        static let tvDataSaverModeCellular = "viewer_tv_data_saver_mode_cellular"
        static let tv24fpsMode = "viewer_tv_24fps_mode"
        static let tv24fpsModeCellular = "viewer_tv_24fps_mode_cellular"
        static let tvLowLatencyMode = "viewer_tv_low_latency_mode"
        static let tvLowLatencyModeCellular = "viewer_tv_low_latency_mode_cellular"
        static let lastQualityProfileType = "viewer_last_quality_profile_type"
        static let videoQuality = "viewer_video_streaming_quality"
        static let videoQualityCellular = "viewer_video_streaming_quality_cellular"
        static let videoDataSaverMode = "viewer_video_data_saver_mode"
        static let videoDataSaverModeCellular = "viewer_video_data_saver_mode_cellular"
        static let video24fpsMode = "viewer_video_24fps_mode"
        static let video24fpsModeCellular = "viewer_video_24fps_mode_cellular"
        static let playbackSettingsMigrated = "viewer_playback_settings_migrated"
        // 再生まわりの正式な設定 (Web 版のキー名に viewer_ を付けたもの。
        // 回線やテレビ/ビデオでは分かれない、録画再生だけの設定)。
        static let seekBackwardSeconds = "viewer_video_seek_backward_seconds"
        static let seekForwardSeconds = "viewer_video_seek_forward_seconds"
        static let playbackRate = "viewer_video_playback_rate"
        static let cmAutoSkip = "viewer_video_cm_auto_skip"
        static let resumeRewindSeconds = "viewer_video_resume_rewind_seconds"
        // コメント (ニコニコ実況の過去ログ) を表示するか。Web 版の
        // dplayer-danmaku-show に相当し、Web 版と同じく端末ごとに持つ。
        static let showComments = "viewer_show_comments"
        // 字幕を表示するか。Web 版プレイヤーの操作帯にある字幕の切り替えに
        // 相当し、Web 版と同じく端末ごとに持つ。
        static let showCaptions = "viewer_show_captions"
        // 設定をデバイス間で同期するか (Web 版の sync_settings に相当する
        // アプリ側の値そのもの。同期される中身ではないので端末に置く)。
        static let syncSettings = "viewer_sync_settings"
        // この端末が最後に設定を同期した時刻 (ログイン時の自動取り込みの
        // 判定に使う、端末だけの控え)。
        static let lastSyncedAt = "viewer_last_synced_at"
        // 番組表の表示設定 (Web 版の利用者設定と同じ項目名に viewer_ を
        // 付けたもの)。端末内の控えで、サーバーとの同期が入っているときは
        // TimeTableSettingsStore がサーバー側の値をここへ写し、変更時は
        // ここへ書いてからサーバーへも送る。
        static let timeTableChannelWidth = "viewer_timetable_channel_width"
        static let timeTableHourHeight = "viewer_timetable_hour_height"
        static let timeTableDimShoppingPrograms = "viewer_timetable_dim_shopping_programs"
        static let timeTableReservationHighlight = "viewer_timetable_reservation_highlight"
        static let timeTableGenreColors = "viewer_timetable_genre_colors"
        // 字幕・ニコニコ実況・全般のうち、サーバーに保存される利用者設定と
        // 共通の項目 (Web 版の項目名に viewer_ を付けたもの)。端末内の控えで、
        // サーバーとの同期が入っているときは SyncedSettingsStore がサーバー側の
        // 値をここへ写し、変更時はここへ書いてからサーバーへも送る
        // (番組表の表示設定と同じ作り)。
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
        static let mutedCommentKeywords = "viewer_muted_comment_keywords"
        static let mutedNiconicoUserIDs = "viewer_muted_niconico_user_ids"
        static let pinnedChannelIDs = "viewer_pinned_channel_ids"
        static let mylist = "viewer_mylist"
        static let videoWatchedHistoryMaxCount = "viewer_video_watched_history_max_count"
        static let videoPanelActiveTab = "viewer_video_panel_active_tab"
        // コメント表示のうち、Web 版でも端末ごとに持つ項目
        // (dplayer-danmaku-unlimited / dplayer-danmaku-opacity に相当)。
        static let showCommentsUnlimited = "viewer_show_comments_unlimited"
        static let showExcitementInFullscreen = "viewer_show_excitement_in_fullscreen"
        static let commentOpacity = "viewer_comment_opacity"
        // 表示の大きさ (Web 版うち改造の ui_scale に相当)。Web 版と同じく
        // 端末ごとに持つ設定で、デバイス間同期の対象にはしない。
        static let uiScale = "viewer_ui_scale"
        // 改造版サーバーの機能の区分の解放状態と、機能ごとのトグル。
        // どれも端末ごとに持つ設定で、デバイス間同期の対象にはしない。
        // customizedFeaturesEnabled は旧まとめトグルの値で、個別トグルへ
        // 引き継いだあとは読み書きしない (切り戻し用に残す)。
        static let customizedFeaturesEnabled = "viewer_customized_features_enabled"
        static let customizedFeaturesUnlocked = "viewer_customized_features_unlocked"
        static let customizedProtectionEnabled = "viewer_customized_protection_enabled"
        static let customizedTrashEnabled = "viewer_customized_trash_enabled"
        static let customizedEpisodesEnabled = "viewer_customized_episodes_enabled"
        static let customizedBookmarksScenesEnabled = "viewer_customized_bookmarks_scenes_enabled"
        static let customizedRecordingResultsEnabled = "viewer_customized_recording_results_enabled"
        static let customizedTunerInUseEnabled = "viewer_customized_tuner_in_use_enabled"
        static let customizedFeaturesSplitDone = "viewer_customized_features_split_done"
        // データ放送の設定 (Web 版の設定 → データ放送の項目)。Web 版でも
        // どれもデバイス間同期の対象外 (端末ごとに持つ) のため、
        // こちらも端末にだけ置く。
        static let dataBroadcastingEnabled = "viewer_data_broadcasting_enabled"
        static let dataBroadcastingInternetEnabled = "viewer_data_broadcasting_internet_enabled"
        static let dataBroadcastingZipCode = "viewer_data_broadcasting_zip_code"
        static let dataBroadcastingPrefecture = "viewer_data_broadcasting_prefecture"
        // データ放送の保存データ (NVRAM) のアプリ側の控え。データ放送の
        // 画面 (WebView) の中の保存領域がアプリの再起動をまたいで残る
        // 保証が無いため、つなぎ (bml-main.js) が読み書きを写してきて、
        // ここに控える。キーが無い = まだ控えが無い (初回は画面側の
        // 保存領域から吸い上げる)。
        static let dataBroadcastingNvram = "viewer_data_broadcasting_nvram"
    }

    private enum KeychainKey {
        static let password = "konomi_password"
        static let accessToken = "konomi_access_token"
    }

    private let defaults = UserDefaults.standard

    private init() {
        migratePlaybackSettingsIfNeeded()
        migrateCustomizedFeaturesIfNeeded()
    }

    /// 旧まとめトグル「改造版サーバーの機能を使う」から、機能ごとの
    /// 個別トグルへの引き継ぎ。初回だけ行う。まとめトグルをオンにして
    /// 使ってきた端末では、個別トグルが全部オンの状態で引き継がれる
    /// (設定が消えたように見せないため)。旧キーは切り戻し用に残す。
    private func migrateCustomizedFeaturesIfNeeded() {
        guard !defaults.bool(forKey: Key.customizedFeaturesSplitDone) else { return }
        let wasEnabled = defaults.bool(forKey: Key.customizedFeaturesEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedProtectionEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedTrashEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedEpisodesEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedBookmarksScenesEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedRecordingResultsEnabled)
        defaults.set(wasEnabled, forKey: Key.customizedTunerInUseEnabled)
        defaults.set(true, forKey: Key.customizedFeaturesSplitDone)
    }

    /// 旧「既定の画質」と旧通信節約トグル (仮版) から、正式な画質設定への引き継ぎ。
    /// 初回だけ行う。旧キーは切り戻し用に当面残す (読み書きはしなくなる)。
    /// - 旧「既定の画質」は、テレビ/ビデオの Wi-Fi 回線時の初期値にする
    ///   (Web 版の既定 1080p に寄せて勝手に上げることはしない)。
    /// - モバイル回線時の画質は Web 版の既定 (480p) から始める。
    /// - 旧通信節約トグルの値は、4つの通信節約すべてにそのまま写す
    ///   (オンにして使ってきた人の設定を移行で変えないため)。
    /// - 24fps は Web 版の既定どおりオフ (キーを作らず、読み取り側の既定で受ける)。
    private func migratePlaybackSettingsIfNeeded() {
        guard !defaults.bool(forKey: Key.playbackSettingsMigrated) else { return }
        let legacyQuality = quality
        let legacyDataSaver = dataSaverMode
        defaults.set(legacyQuality, forKey: Key.tvQuality)
        defaults.set(legacyQuality, forKey: Key.videoQuality)
        defaults.set("480p", forKey: Key.tvQualityCellular)
        defaults.set("480p", forKey: Key.videoQualityCellular)
        for key in [Key.tvDataSaverMode, Key.tvDataSaverModeCellular,
                    Key.videoDataSaverMode, Key.videoDataSaverModeCellular] {
            defaults.set(legacyDataSaver, forKey: key)
        }
        defaults.set(true, forKey: Key.playbackSettingsMigrated)
    }

    /// 選べる画質 (サーバー側の画質名)。
    /// 一覧に出すのは通常版 (H.264) のみ。H.265 / HEVC 版は、通信節約モードが
    /// オンのときに apiQuality(base:media:profile:) が裏で名前の末尾に
    /// "-hevc" を付けて要求する (サーバー側には全画質に HEVC 版がある)。
    static let qualities = ["1080p-60fps", "1080p", "810p", "720p", "540p", "480p", "360p", "240p"]
    static let defaultQuality = "720p"

    /// 画質の選択肢に出すデータ量と平均ビットレート (本家 Web 版の設定画面
    /// (Quality.vue の QUALITY_H264 / QUALITY_H265) の固定文字列そのまま)。
    /// 本家では計算式ではなく画質ごとに固定で持たれている値で、表示上の
    /// Mbps から GB/h を単純計算した値とはわずかにずれるものもあるため、
    /// ここでも文字列をそのまま写す。通信節約モード (H.265 / HEVC) の
    /// 有無で表が切り替わり、24fps モードは本家でも表示に影響しない。
    private static let qualityDataH264: [String: String] = [
        "1080p-60fps": "約4.50GB/h / 平均10.0Mbps",
        "1080p": "約4.50GB/h / 平均10.0Mbps",
        "810p": "約2.62GB/h / 平均5.8Mbps",
        "720p": "約2.18GB/h / 平均4.9Mbps",
        "540p": "約1.52GB/h / 平均3.4Mbps",
        "480p": "約1.06GB/h / 平均2.3Mbps",
        "360p": "約0.60GB/h / 平均1.3Mbps",
        "240p": "約0.35GB/h / 平均0.8Mbps",
    ]
    private static let qualityDataH265: [String: String] = [
        "1080p-60fps": "約1.80GB/h / 平均4.0Mbps",
        "1080p": "約1.37GB/h / 平均3.0Mbps",
        "810p": "約1.05GB/h / 平均2.3Mbps",
        "720p": "約0.82GB/h / 平均1.8Mbps",
        "540p": "約0.53GB/h / 平均1.2Mbps",
        "480p": "約0.46GB/h / 平均1.0Mbps",
        "360p": "約0.30GB/h / 平均0.7Mbps",
        "240p": "約0.20GB/h / 平均0.4Mbps",
    ]

    /// 画質の選択肢の表示名。本家 Web 版の設定画面と同じ
    /// 「480p (約0.46GB/h / 平均1.0Mbps)」の形で、1080p-60fps だけは
    /// 本家と同じく「1080p (60fps)」と出す。qualities に無い名前は
    /// そのまま返す。
    static func qualityDisplayName(_ base: String, dataSaverMode: Bool) -> String {
        let table = dataSaverMode ? qualityDataH265 : qualityDataH264
        guard let data = table[base] else { return base }
        let name = base == "1080p-60fps" ? "1080p (60fps)" : base
        return "\(name) (\(data))"
    }
    /// 音声のみ再生のときに使う最小画質 (映像も一緒に来るが一番軽い)。
    static let audioOnlyQuality = "240p"

    var rawURLString: String {
        get { defaults.string(forKey: Key.url) ?? "" }
        set { defaults.set(newValue, forKey: Key.url) }
    }

    var cfClientID: String {
        get { defaults.string(forKey: Key.cfClientID) ?? "" }
        set { defaults.set(newValue, forKey: Key.cfClientID) }
    }

    var cfClientSecret: String {
        get { defaults.string(forKey: Key.cfClientSecret) ?? "" }
        set { defaults.set(newValue, forKey: Key.cfClientSecret) }
    }

    /// 旧「既定の画質」(仮版までの単一の画質設定)。正式な設定への引き継ぎ元
    /// としてだけ残し、実際の再生では streamingQuality(media:profile:) を使う。
    var quality: String {
        get {
            let q = defaults.string(forKey: Key.quality) ?? ""
            return Self.qualities.contains(q) ? q : Self.defaultQuality
        }
        set { defaults.set(newValue, forKey: Key.quality) }
    }

    /// 通信節約モード。オンのときは H.265 / HEVC の画質で受ける。
    /// Web 版でも端末ごとに持つ設定 (デバイス間同期の対象外) なので、
    /// このアプリでも端末ローカルに保存する。既定はオフ。
    /// これは仮版の単一トグルの保存先で、正式な設定への引き継ぎ元としてだけ残す。
    /// 実際の再生では下の区分ごとの設定 (dataSaverMode(media:profile:)) を使う。
    var dataSaverMode: Bool {
        get { defaults.bool(forKey: Key.dataSaverMode) }
        set { defaults.set(newValue, forKey: Key.dataSaverMode) }
    }

    // MARK: - 画質まわりの正式な設定 (テレビ/ビデオ × Wi-Fi/モバイル回線)

    private func qualityKey(media: PlaybackMedia, profile: PlaybackProfile) -> String {
        switch (media, profile) {
        case (.tv, .wifi): return Key.tvQuality
        case (.tv, .cellular): return Key.tvQualityCellular
        case (.video, .wifi): return Key.videoQuality
        case (.video, .cellular): return Key.videoQualityCellular
        }
    }

    private func dataSaverKey(media: PlaybackMedia, profile: PlaybackProfile) -> String {
        switch (media, profile) {
        case (.tv, .wifi): return Key.tvDataSaverMode
        case (.tv, .cellular): return Key.tvDataSaverModeCellular
        case (.video, .wifi): return Key.videoDataSaverMode
        case (.video, .cellular): return Key.videoDataSaverModeCellular
        }
    }

    private func lowLatencyKey(profile: PlaybackProfile) -> String {
        // 低遅延はテレビ (生放送) だけの項目 (ビデオ側には無い)。
        profile == .cellular ? Key.tvLowLatencyModeCellular : Key.tvLowLatencyMode
    }

    private func fps24Key(media: PlaybackMedia, profile: PlaybackProfile) -> String {
        switch (media, profile) {
        case (.tv, .wifi): return Key.tv24fpsMode
        case (.tv, .cellular): return Key.tv24fpsModeCellular
        case (.video, .wifi): return Key.video24fpsMode
        case (.video, .cellular): return Key.video24fpsModeCellular
        }
    }

    /// 区分ごとの画質 (サーバー側の画質名)。値が無い・不正なときの受け値は、
    /// Wi-Fi 回線時はアプリの既定画質、モバイル回線時は Web 版の既定 (480p)。
    func streamingQuality(media: PlaybackMedia, profile: PlaybackProfile) -> String {
        let q = defaults.string(forKey: qualityKey(media: media, profile: profile)) ?? ""
        if Self.qualities.contains(q) { return q }
        return profile == .cellular ? "480p" : Self.defaultQuality
    }

    func setStreamingQuality(_ value: String, media: PlaybackMedia, profile: PlaybackProfile) {
        defaults.set(value, forKey: qualityKey(media: media, profile: profile))
    }

    /// 区分ごとの通信節約モード。オンのときは H.265 / HEVC の画質で受ける。
    func dataSaverMode(media: PlaybackMedia, profile: PlaybackProfile) -> Bool {
        defaults.bool(forKey: dataSaverKey(media: media, profile: profile))
    }

    func setDataSaverMode(_ value: Bool, media: PlaybackMedia, profile: PlaybackProfile) {
        defaults.set(value, forKey: dataSaverKey(media: media, profile: profile))
    }

    /// 区分ごとの 24fps 化。オンのときは映像を 24fps 化して受ける。
    func fps24Mode(media: PlaybackMedia, profile: PlaybackProfile) -> Bool {
        defaults.bool(forKey: fps24Key(media: media, profile: profile))
    }

    func setFps24Mode(_ value: Bool, media: PlaybackMedia, profile: PlaybackProfile) {
        defaults.set(value, forKey: fps24Key(media: media, profile: profile))
    }

    /// テレビ (生放送) の低遅延。オンのときは受け取りの溜めを減らして、
    /// 放送との遅れを小さくする。既定値は Web 版と同じで、Wi-Fi 回線時は
    /// オン、モバイル回線時はオフ (キーが無いときはその値で受ける)。
    func lowLatencyMode(profile: PlaybackProfile) -> Bool {
        let key = lowLatencyKey(profile: profile)
        guard defaults.object(forKey: key) != nil else {
            return profile == .wifi
        }
        return defaults.bool(forKey: key)
    }

    func setLowLatencyMode(_ value: Bool, profile: PlaybackProfile) {
        defaults.set(value, forKey: lowLatencyKey(profile: profile))
    }

    /// 最後に手動で切り替えた画質の区分 (Web 版の last_quality_profile_type)。
    /// 保存する値は Web 版と同じ文字列 ('Wi-Fi' / 'Cellular') で、未指定は
    /// キー自体が無い状態 (nil)。書き込まれるのは、再生画面でプロファイルを
    /// 手で切り替えた瞬間だけ (画質の変更では書かない)。
    var lastQualityProfileType: PlaybackProfile? {
        get {
            switch defaults.string(forKey: Key.lastQualityProfileType) {
            case "Wi-Fi": return .wifi
            case "Cellular": return .cellular
            default: return nil
            }
        }
        set {
            switch newValue {
            case .wifi:
                defaults.set("Wi-Fi", forKey: Key.lastQualityProfileType)
            case .cellular:
                defaults.set("Cellular", forKey: Key.lastQualityProfileType)
            case nil:
                defaults.removeObject(forKey: Key.lastQualityProfileType)
            }
        }
    }

    /// 再生を始めるときに使う回線の区分を決める。優先順位は Web 版の
    /// プレイヤー作成時と同じで、手動切り替えの記憶 (lastQualityProfileType)
    /// があればそれを優先し、無ければ現在の回線から決める。
    /// (Web 版にはこの上に「同じ視聴画面の中での手動変更」がもう一段あるが、
    /// アプリでは再生画面がその単位なので、画面が持つ区分がそれにあたる。)
    func initialPlaybackProfile() -> PlaybackProfile {
        if let last = lastQualityProfileType { return last }
        return NetworkMonitor.shared.currentProfile
    }

    /// サーバーへ実際に渡す画質名を組み立てる。末尾の付け方と順番は Web 版と同じ:
    /// 画質名 → 通信節約がオンなら "-hevc" → 24fps がオンなら "-24fps"。
    /// ただし 1080p-60fps のときは 60fps を優先して "-24fps" を付けない
    /// (サーバー側でも同じ扱いで無効化される)。HEVC 10bit ("-10bit") は付けない。
    /// 対象は qualities にある画質だけ (それ以外はそのまま返す)。
    func apiQuality(base: String, media: PlaybackMedia, profile: PlaybackProfile) -> String {
        guard Self.qualities.contains(base) else { return base }
        var name = base
        if dataSaverMode(media: media, profile: profile) {
            name += "-hevc"
        }
        if fps24Mode(media: media, profile: profile), base != "1080p-60fps" {
            name += "-24fps"
        }
        return name
    }

    // MARK: - 再生まわりの正式な設定 (録画再生だけ・回線では分かれない)

    /// スキップ秒数 (戻し) の選択肢と既定値。Web 版 (改造) と同じ。
    static let seekBackwardChoices = [5, 10, 15, 30]
    static let defaultSeekBackwardSeconds = 10
    /// スキップ秒数 (送り) の選択肢と既定値。Web 版 (改造) と同じ。
    static let seekForwardChoices = [10, 15, 30, 60]
    static let defaultSeekForwardSeconds = 30
    /// 再生速度の選択肢と既定値。Web 版 (改造) と同じ。
    static let playbackRateChoices: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    static let defaultPlaybackRate = 1.0
    /// 再開時の巻き戻し秒数の選択肢と既定値。改造側の仕様確認済み。
    static let resumeRewindChoices = [0, 5, 10, 15, 30]
    static let defaultResumeRewindSeconds = 10

    /// スキップ秒数 (戻し)。再生画面の戻しボタンがこの秒数だけ戻る。
    var seekBackwardSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.seekBackwardSeconds)
            return Self.seekBackwardChoices.contains(value) ? value : Self.defaultSeekBackwardSeconds
        }
        set { defaults.set(newValue, forKey: Key.seekBackwardSeconds) }
    }

    /// スキップ秒数 (送り)。再生画面の送りボタンがこの秒数だけ進む。
    var seekForwardSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.seekForwardSeconds)
            return Self.seekForwardChoices.contains(value) ? value : Self.defaultSeekForwardSeconds
        }
        set { defaults.set(newValue, forKey: Key.seekForwardSeconds) }
    }

    /// 録画再生の再生速度 (前回の速度の記憶を兼ねる)。
    /// 再生を始めるときはこの速度で始め、再生中に変えたらその場でここへ書き戻す
    /// (Web 版 (改造) の効き方と同じ)。
    var playbackRate: Double {
        get {
            let value = defaults.double(forKey: Key.playbackRate)
            return Self.playbackRateChoices.contains(value) ? value : Self.defaultPlaybackRate
        }
        set { defaults.set(newValue, forKey: Key.playbackRate) }
    }

    /// 再生速度の表示文 ("1倍" / "1.25倍" など)。
    static func playbackRateText(_ rate: Double) -> String {
        if rate == rate.rounded() {
            return "\(Int(rate))倍"
        }
        return "\(rate)倍"
    }

    /// CM自動スキップ。オンのとき、録画の再生中に CM 区間の開始を跨ぐと
    /// 自動で区間の終わりまで飛ばす。既定はオフ (改造側の仕様確認済み)。
    var cmAutoSkip: Bool {
        get { defaults.bool(forKey: Key.cmAutoSkip) }
        set { defaults.set(newValue, forKey: Key.cmAutoSkip) }
    }

    /// 再開時の巻き戻し秒数。前回見た位置から再開するとき、この秒数だけ
    /// 戻してから始める。0秒も正規の選択肢なので、未設定 (既定値で受ける)
    /// とはキーの有無で区別する。
    var resumeRewindSeconds: Int {
        get {
            guard defaults.object(forKey: Key.resumeRewindSeconds) != nil else {
                return Self.defaultResumeRewindSeconds
            }
            let value = defaults.integer(forKey: Key.resumeRewindSeconds)
            return Self.resumeRewindChoices.contains(value) ? value : Self.defaultResumeRewindSeconds
        }
        set { defaults.set(newValue, forKey: Key.resumeRewindSeconds) }
    }

    /// 録画再生でコメント (ニコニコ実況の過去ログ) を表示するか
    /// (Web 版の dplayer-danmaku-show に相当)。既定は Web 版と同じオン
    /// (キーが無いときはオンで受ける)。
    var showComments: Bool {
        get {
            guard defaults.object(forKey: Key.showComments) != nil else { return true }
            return defaults.bool(forKey: Key.showComments)
        }
        set { defaults.set(newValue, forKey: Key.showComments) }
    }

    /// 録画再生の全画面でも、シークバーの上に盛り上がりの波形を
    /// 出すか。設定の「ニコニコ実況」の表示の項目に置く専用スイッチで
    /// 切り替える。端末だけに保存し、同期の対象にしない。既定はオン
    /// (キーが無いときはオンで受ける)。
    var showExcitementInFullscreen: Bool {
        get {
            guard defaults.object(forKey: Key.showExcitementInFullscreen) != nil else { return true }
            return defaults.bool(forKey: Key.showExcitementInFullscreen)
        }
        set { defaults.set(newValue, forKey: Key.showExcitementInFullscreen) }
    }

    /// 録画再生で字幕を表示するか (Web 版プレイヤーの字幕の切り替えに相当)。
    /// Web 版では字幕は最初から出るのが既定のため、こちらも既定はオン
    /// (キーが無いときはオンで受ける)。
    var showCaptions: Bool {
        get {
            guard defaults.object(forKey: Key.showCaptions) != nil else { return true }
            return defaults.bool(forKey: Key.showCaptions)
        }
        set { defaults.set(newValue, forKey: Key.showCaptions) }
    }

    /// 設定をデバイス間で同期する (Web 版の sync_settings に相当)。
    /// オンで、サーバーに保存されている利用者設定 (視聴履歴など) を
    /// 取得・書き戻しして Web 版など他の端末と共通にする。
    /// 既定は Web 版と同じオフ (キーが無いときはオフで受ける)。
    var syncSettings: Bool {
        get { defaults.bool(forKey: Key.syncSettings) }
        set { defaults.set(newValue, forKey: Key.syncSettings) }
    }

    /// この端末が最後にサーバーと設定を同期した時刻 (UNIX 秒)。
    /// サーバーへ利用者設定を送れたときと、サーバーから取り込んだときに
    /// 更新される。0 のままなら、この端末ではまだ一度も同期していない
    /// という意味になる (Web 版の端末側の last_synced_at と同じ物差しで、
    /// ログイン時の自動取り込みの判定に使う)。端末だけに置く値で、
    /// サーバーへ送る利用者設定の中身ではない。
    var lastSyncedAt: Double {
        get { defaults.double(forKey: Key.lastSyncedAt) }
        set { defaults.set(newValue, forKey: Key.lastSyncedAt) }
    }

    // MARK: - 番組表の表示設定 (端末内の控え)

    /// 番組表の表示幅・密度の選択肢 (Web 版の値の形そのまま)。
    static let timeTableSizeOptions = ["Wide", "Normal", "Narrow"]

    /// 各チャンネルの表示幅 (Web 版の timetable_channel_width)。
    /// 値が無い・不正なときは Web 版の既定 (標準) で受ける。
    var timeTableChannelWidth: String {
        get {
            let value = defaults.string(forKey: Key.timeTableChannelWidth) ?? ""
            return Self.timeTableSizeOptions.contains(value) ? value : "Normal"
        }
        set { defaults.set(newValue, forKey: Key.timeTableChannelWidth) }
    }

    /// 時間軸の表示密度 (Web 版の timetable_hour_height)。既定は標準。
    var timeTableHourHeight: String {
        get {
            let value = defaults.string(forKey: Key.timeTableHourHeight) ?? ""
            return Self.timeTableSizeOptions.contains(value) ? value : "Normal"
        }
        set { defaults.set(newValue, forKey: Key.timeTableHourHeight) }
    }

    /// ショッピング・通販番組を控えめに表示するか
    /// (Web 版の timetable_dim_shopping_programs)。既定は Web 版と同じ
    /// オンなので、キーが無いときはオンで受ける。
    var timeTableDimShoppingPrograms: Bool {
        get {
            guard defaults.object(forKey: Key.timeTableDimShoppingPrograms) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.timeTableDimShoppingPrograms)
        }
        set { defaults.set(newValue, forKey: Key.timeTableDimShoppingPrograms) }
    }

    /// 番組表で、予約のある番組のセルの塗りとチューナーの使用帯を
    /// 出すか。改造版サーバーの機能のトグルからは外し、番組表の
    /// 表示設定の中の専用スイッチで切り替える (2026-11-24 の分類の
    /// 見直し)。端末だけに保存し、同期の対象にしない。既定はオン
    /// (キーが無いときはオンで受ける)。
    var timeTableReservationHighlightEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.timeTableReservationHighlight) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.timeTableReservationHighlight)
        }
        set { defaults.set(newValue, forKey: Key.timeTableReservationHighlight) }
    }

    /// ジャンル別のハイライト色 (Web 版の timetable_genre_colors)。
    /// ジャンル名 → 色名の辞書をそのまま端末に置く。保存が無いときは
    /// 空を返し、既定の割り当てへの置き換えは TimeTableDisplaySettings
    /// 側で行う。
    var timeTableGenreColors: [String: String] {
        get { defaults.dictionary(forKey: Key.timeTableGenreColors) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.timeTableGenreColors) }
    }

    // MARK: - 字幕・実況・全般の共通設定の端末内の控え
    //
    // ここは生の保存だけを担う。既定値の適用と、サーバーとの同期が
    // 入っているときの取り込み・送信は SyncedSettingsStore 側で行う
    // (番組表の表示設定で TimeTableSettingsStore が担っているのと同じ分担)。
    // キーが無いときは nil を返す形にし、既定値への置き換えは読み手に任せる。

    /// 生の文字列の控え。キーが無ければ nil。
    func syncedString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setSyncedString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 生の真偽値の控え。キーが無ければ nil。
    func syncedBool(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    func setSyncedBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// 生の小数値の控え。キーが無ければ nil。
    func syncedDouble(forKey key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    func setSyncedDouble(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// 生の整数値の控え。キーが無ければ nil。
    func syncedInt(forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    func setSyncedInt(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// ミュートするコメントのキーワードの控え (Web 版の
    /// muted_comment_keywords と同じ形: match と pattern の組の配列を、
    /// JSON 文字列にして保存する)。
    var mutedCommentKeywordEntries: [[String: String]] {
        get {
            guard let raw = defaults.string(forKey: Key.mutedCommentKeywords),
                  let data = raw.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
            else { return [] }
            return entries
        }
        set {
            if let data = try? JSONSerialization.data(withJSONObject: newValue),
               let raw = String(data: data, encoding: .utf8) {
                defaults.set(raw, forKey: Key.mutedCommentKeywords)
            }
        }
    }

    /// ミュートするニコニコユーザー ID の控え (Web 版の
    /// muted_niconico_user_ids と同じ文字列の配列)。
    var mutedNiconicoUserIDs: [String] {
        get { defaults.stringArray(forKey: Key.mutedNiconicoUserIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.mutedNiconicoUserIDs) }
    }

    /// ピン留め中のチャンネルの ID の控え (Web 版の pinned_channel_ids と
    /// 同じ文字列の配列、並びがそのまま表示順になる)。
    var pinnedChannelIDs: [String] {
        get { defaults.stringArray(forKey: Key.pinnedChannelIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.pinnedChannelIDs) }
    }

    /// マイリストの控え (Web 版の mylist と同じ形: 種類・番号・追加した
    /// 時刻の組の配列を、JSON 文字列にして保存する)。
    var mylistEntries: [[String: Any]] {
        get {
            guard let raw = defaults.string(forKey: Key.mylist),
                  let data = raw.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return entries
        }
        set {
            if let data = try? JSONSerialization.data(withJSONObject: newValue),
               let raw = String(data: data, encoding: .utf8) {
                defaults.set(raw, forKey: Key.mylist)
            }
        }
    }

    // MARK: - コメント表示の端末ごとの設定

    /// コメントを無制限に表示するか (Web 版の dplayer-danmaku-unlimited に
    /// 相当し、Web 版と同じく端末ごとに持つ)。オンのときは、流れる
    /// コメントの置き場所が空いていなくても重なりを許して出す。
    /// 既定は Web 版と同じオフ。
    var showCommentsUnlimited: Bool {
        get { defaults.bool(forKey: Key.showCommentsUnlimited) }
        set { defaults.set(newValue, forKey: Key.showCommentsUnlimited) }
    }

    /// 流れるコメントの不透明度 (Web 版の dplayer-danmaku-opacity に相当し、
    /// Web 版と同じく端末ごとに持つ)。既定は Web 版と同じ 0.5。
    var commentOpacity: Double {
        get {
            guard defaults.object(forKey: Key.commentOpacity) != nil else { return 0.5 }
            return min(1, max(0, defaults.double(forKey: Key.commentOpacity)))
        }
        set { defaults.set(newValue, forKey: Key.commentOpacity) }
    }

    // MARK: - 表示の大きさ (端末ごとの設定)

    /// 表示の大きさのプリセット (Web 版うち改造の ui_scale と同じ並び)。
    static let uiScalePresets = [80, 90, 100, 110]
    /// 表示の大きさの範囲 (Web 版と同じ 50% 〜 150%)。
    static let uiScaleRange = 50...150

    /// 表示の大きさ (パーセント)。画面全体の文字や共通部品の寸法に
    /// 倍率として効く (効き方は WebControls の UIScale 側)。
    /// Web 版の ui_scale と同じく端末ごとに持つ設定で、同期対象ではない。
    /// 既定は 100 (従来とまったく同じ表示)。範囲外の値は範囲内に丸める。
    /// 変更すると .uiScaleDidChange が通知され、タブバーや開き直した
    /// 画面から順に新しい大きさで組み直される。
    var uiScalePercent: Int {
        get {
            guard defaults.object(forKey: Key.uiScale) != nil else { return 100 }
            return min(Self.uiScaleRange.upperBound,
                       max(Self.uiScaleRange.lowerBound, defaults.integer(forKey: Key.uiScale)))
        }
        set {
            let clamped = min(Self.uiScaleRange.upperBound,
                              max(Self.uiScaleRange.lowerBound, newValue))
            guard clamped != uiScalePercent else { return }
            defaults.set(clamped, forKey: Key.uiScale)
            NotificationCenter.default.post(name: .uiScaleDidChange, object: nil)
        }
    }

    /// 表示の大きさの倍率 (100% で 1.0)。
    var uiScaleFactor: CGFloat {
        CGFloat(uiScalePercent) / 100
    }

    // MARK: - 改造版サーバーの機能 (端末ごとの設定)

    /// 旧まとめトグル「改造版サーバーの機能を使う」の値。機能ごとの
    /// 個別トグルに組み替えたため、今は引き継ぎ (上の
    /// migrateCustomizedFeaturesIfNeeded) でのみ読み、画面からは
    /// 読み書きしない。切り戻し用に残してある。
    var customizedServerFeaturesEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedFeaturesEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedFeaturesEnabled) }
    }

    /// 改造版サーバーの機能ごとのトグル (録画の保護・ゴミ箱など、
    /// konomitv-customizations を適用したサーバーが持つ受け口を使う
    /// 機能)。端末ごとに持つ設定で、同期対象ではない。既定はどれも
    /// オフ。出し分けの参照は AppEdition 側。置き場所は「このアプリの
    /// 設定」の「改造版サーバーの機能」の行から入る専用画面で、
    /// その行自体は下の解放が済むまで設定画面に出ない。

    /// 録画の保護を使うかどうか。
    var customizedProtectionEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedProtectionEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedProtectionEnabled) }
    }

    /// ゴミ箱を使うかどうか。
    var customizedTrashEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedTrashEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedTrashEnabled) }
    }

    /// 前の話・次の話ボタンと、次の話の自動再生を使うかどうか。
    var customizedEpisodesEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedEpisodesEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedEpisodesEnabled) }
    }

    /// しおりと場面一覧を使うかどうか。
    var customizedBookmarksScenesEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedBookmarksScenesEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedBookmarksScenesEnabled) }
    }

    /// 録画結果一覧を使うかどうか。
    var customizedRecordingResultsEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedRecordingResultsEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedRecordingResultsEnabled) }
    }

    /// チューナー使用中のチャンネル表示を使うかどうか。
    var customizedTunerInUseEnabled: Bool {
        get { defaults.bool(forKey: Key.customizedTunerInUseEnabled) }
        set { defaults.set(newValue, forKey: Key.customizedTunerInUseEnabled) }
    }

    /// 「改造版サーバーの機能」の区分が解放済みかどうか。
    /// マイページの App version の行を7回タップすると解放され、一度解放
    /// したら残り続ける。端末ごとに持つ状態で、同期対象ではない。
    var customizedServerFeaturesUnlocked: Bool {
        get { defaults.bool(forKey: Key.customizedFeaturesUnlocked) }
        set { defaults.set(newValue, forKey: Key.customizedFeaturesUnlocked) }
    }

    // MARK: - データ放送 (端末ごとの設定)

    /// テレビをみるときにデータ放送機能を利用するか
    /// (Web 版の tv_show_data_broadcasting)。Web 版と同じく既定はオン
    /// (キーが無いときはオンで受ける)。オフのときは、生放送の再生画面に
    /// リモコンの入り口自体を出さない。
    var dataBroadcastingEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.dataBroadcastingEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.dataBroadcastingEnabled)
        }
        set { defaults.set(newValue, forKey: Key.dataBroadcastingEnabled) }
    }

    /// データ放送からのインターネットアクセス (双方向) を有効にするか
    /// (Web 版の enable_internet_access_from_data_broadcasting)。
    /// 既定は Web 版と同じオフ。オフのときは、データ放送の画面から
    /// ネット接続の受け口へ一切つながない。
    var dataBroadcastingInternetEnabled: Bool {
        get { defaults.bool(forKey: Key.dataBroadcastingInternetEnabled) }
        set { defaults.set(newValue, forKey: Key.dataBroadcastingInternetEnabled) }
    }

    /// お住まいの郵便番号 (「000-0000」の形で持つ。未設定は空)。
    /// Web 版はデータ放送の保存データへ直接書いているが、アプリでは
    /// 設定画面を開いた時点でデータ放送の画面が存在しないため、
    /// ここに値を持ち、データ放送を始めるときに保存データへ流し込む。
    var dataBroadcastingZipCode: String {
        get { defaults.string(forKey: Key.dataBroadcastingZipCode) ?? "" }
        set { defaults.set(newValue, forKey: Key.dataBroadcastingZipCode) }
    }

    /// お住まいの都道府県 (Web 版の選択肢の値の形「番号-0b地域コード」で
    /// 持つ。未設定は空)。郵便番号と同じく、データ放送を始めるときに
    /// 保存データへ流し込む。
    var dataBroadcastingPrefecture: String {
        get { defaults.string(forKey: Key.dataBroadcastingPrefecture) ?? "" }
        set { defaults.set(newValue, forKey: Key.dataBroadcastingPrefecture) }
    }

    /// データ放送の保存データ (NVRAM) のアプリ側の控え。
    /// 保存領域のキー → 値の辞書そのまま。nil は「まだ控えが無い」
    /// (初回の開始時に画面側から吸い上げる)。空の辞書は
    /// 「リセット済みで中身が無い」という意味になる。
    var dataBroadcastingNvram: [String: String]? {
        get { defaults.dictionary(forKey: Key.dataBroadcastingNvram) as? [String: String] }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.dataBroadcastingNvram)
            } else {
                defaults.removeObject(forKey: Key.dataBroadcastingNvram)
            }
        }
    }

    /// 前後の空白を取り除き、方式 (https:// 等) が無ければ https:// を補う。
    /// 末尾のスラッシュも取り除く (API のパスを後ろに足すため)。
    static func normalizeURLString(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 正規化済みの接続先 URL。未設定・不正なら nil。
    var baseURL: URL? {
        let s = Self.normalizeURLString(rawURLString)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var isConfigured: Bool { baseURL != nil }

    // MARK: - KonomiTV ログイン (保護の切り替えに必要)

    var username: String {
        get { defaults.string(forKey: Key.username) ?? "" }
        set { defaults.set(newValue, forKey: Key.username) }
    }

    /// パスワードはキーチェーンに保存する (UserDefaults には置かない)。
    var password: String {
        get { KeychainStore.string(forKey: KeychainKey.password) ?? "" }
        set { KeychainStore.setString(newValue, forKey: KeychainKey.password) }
    }

    var accessToken: String {
        get { KeychainStore.string(forKey: KeychainKey.accessToken) ?? "" }
        set { KeychainStore.setString(newValue, forKey: KeychainKey.accessToken) }
    }

    var isLoggedIn: Bool { !accessToken.isEmpty }

    func saveLogin(username: String, password: String, token: String) {
        self.username = username
        self.password = password
        self.accessToken = token
    }

    /// ログアウトする。ユーザー名は次回の入力の手間を減らすため残す。
    func clearLogin() {
        accessToken = ""
        password = ""
    }

    /// Cloudflare Access のサービストークンが両方そろっていれば、付けるべきヘッダーを返す。
    var cfAccessHeaders: [String: String] {
        let id = cfClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = cfClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return [:] }
        return [
            "CF-Access-Client-Id": id,
            "CF-Access-Client-Secret": secret,
        ]
    }
}
