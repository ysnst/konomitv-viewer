import Foundation
import CoreGraphics

extension Notification.Name {
    /// 番組表の表示設定のサーバー保存に失敗したときの通知。
    static let timeTableSettingsSaveFailed = Notification.Name("TimeTableSettingsSaveFailed")
}

/// 番組表の表示設定の値一式。項目名・値の形は Web 版の利用者設定
/// (timetable_channel_width など) とそのまま同じにしてある。
/// サーバーに保存される利用者設定の一部で、同期が入っているときは
/// サーバー側の値が正になり、入っていないときは端末内の値を使う。
struct TimeTableDisplaySettings: Equatable {
    /// 各チャンネルの表示幅 ("Wide" / "Normal" / "Narrow")。
    var channelWidth: String
    /// 時間軸の表示密度 ("Wide" / "Normal" / "Narrow")。
    var hourHeight: String
    /// ショッピング・通販番組を控えめに表示するか。
    var dimShoppingPrograms: Bool
    /// ジャンル名 → 色名の割り当て。
    var genreColors: [String: String]

    /// Web 版の既定値 (幅・密度は標準、通販は控えめがオン、
    /// ジャンル色は Web 版の既定の割り当て)。
    static let defaults = TimeTableDisplaySettings(
        channelWidth: "Normal",
        hourHeight: "Normal",
        dimShoppingPrograms: true,
        genreColors: defaultGenreColors)

    /// ジャンル色の既定の割り当て (Web 版の SettingsStore の既定値)。
    static let defaultGenreColors: [String: String] = [
        "ニュース・報道": "White",
        "情報・ワイドショー": "White",
        "ドキュメンタリー・教養": "Blue",
        "スポーツ": "Cyan",
        "ドラマ": "Pink",
        "アニメ・特撮": "Yellow",
        "バラエティ": "Lime",
        "音楽": "Orange",
        "映画": "Brown",
        "劇場・公演": "Ochre",
        "趣味・教育": "Teal",
        "福祉": "White",
        "その他": "White",
    ]

    /// ジャンルの並び (Web 版の表示設定ダイアログの並び順)。
    static let genreList: [String] = [
        "ニュース・報道",
        "情報・ワイドショー",
        "ドキュメンタリー・教養",
        "スポーツ",
        "ドラマ",
        "アニメ・特撮",
        "バラエティ",
        "音楽",
        "映画",
        "劇場・公演",
        "趣味・教育",
        "福祉",
        "その他",
    ]

    /// 色の選択肢 (Web 版の表示設定ダイアログの並び順)。
    /// 値はサーバーに保存される色名、題名は画面に出す日本語名。
    static let colorOptions: [(value: String, title: String)] = [
        ("White", "白"),
        ("Pink", "ピンク"),
        ("Red", "赤"),
        ("Orange", "オレンジ"),
        ("Yellow", "黄色"),
        ("Lime", "黄緑"),
        ("Teal", "青緑"),
        ("Cyan", "水色"),
        ("Blue", "青"),
        ("Ochre", "黄土色"),
        ("Brown", "茶色"),
    ]

    /// 色名が選択肢にあるか。
    static func isValidColorName(_ name: String) -> Bool {
        colorOptions.contains { $0.value == name }
    }

    /// 色名の画面表示用の名前。未知の色名はそのまま返す。
    static func colorTitle(for name: String) -> String {
        colorOptions.first { $0.value == name }?.title ?? name
    }

    /// チャンネルの幅 (pt)。Web 版の換算表 (スマホ用) どおり:
    /// 広め 120 / 標準 100 / 狭め 80。
    var channelWidthPoints: CGFloat {
        switch channelWidth {
        case "Wide": return 120
        case "Narrow": return 80
        default: return 100
        }
    }

    /// 1時間分の高さ (pt)。Web 版の換算表 (スマホ用) どおり:
    /// 広め 160 / 標準 120 / 狭め 80。
    var hourHeightPoints: CGFloat {
        switch hourHeight {
        case "Wide": return 160
        case "Narrow": return 80
        default: return 120
        }
    }

    /// ジャンル大分類に割り当てられた色名を引く。Web 版と同じく、
    /// そのまま一致しなければ「/」と「・」を入れ替えて照合し、
    /// それでも無ければ白にする。
    func genreColorName(forMajor major: String?) -> String {
        guard let major else { return "White" }
        if let name = genreColors[major], Self.isValidColorName(name) { return name }
        let withDot = major.replacingOccurrences(of: "/", with: "・")
        if let name = genreColors[withDot], Self.isValidColorName(name) { return name }
        let withSlash = major.replacingOccurrences(of: "・", with: "/")
        if let name = genreColors[withSlash], Self.isValidColorName(name) { return name }
        return "White"
    }
}

/// 番組表の表示設定の読み書きを担う。
///
/// 普段は端末内の控え (SettingsStore) を読み書きする。ログインしていて
/// 「設定をデバイス間で同期する」が入っているときは、マイページ第2段で
/// 作った利用者設定の手順 (送る直前に最新を取得 → 触る項目だけ差し替え
/// → last_synced_at を更新して送る。知らない項目は落とさない) に乗り、
/// サーバー側の値を正として取り込み、変更時はサーバーへも送る。
/// サーバーとのやり取りに失敗しても、端末内の値で表示は続けられる。
final class TimeTableSettingsStore {
    static let shared = TimeTableSettingsStore()

    /// いま効いている表示設定。端末内の控えから組み立てて保持する。
    private(set) var current: TimeTableDisplaySettings

    private init() {
        let store = SettingsStore.shared
        var colors = TimeTableDisplaySettings.defaultGenreColors
        // 端末内の控えにある分だけ、既定の割り当ての上から上書きする
        // (控えが欠けているジャンルは既定で受ける)。
        for (genre, name) in store.timeTableGenreColors
        where TimeTableDisplaySettings.isValidColorName(name) {
            colors[genre] = name
        }
        current = TimeTableDisplaySettings(
            channelWidth: store.timeTableChannelWidth,
            hourHeight: store.timeTableHourHeight,
            dimShoppingPrograms: store.timeTableDimShoppingPrograms,
            genreColors: colors)
    }

    /// 同期が効く状態か (ログイン中かつ「設定をデバイス間で同期する」がオン)。
    /// 視聴履歴の同期と同じ条件。
    static var isSyncEnabled: Bool {
        SettingsStore.shared.isLoggedIn && SettingsStore.shared.syncSettings
    }

    /// サーバーへの送信待ちの最新値と、送信中かどうかの控え。
    /// 変更が短時間に重なっても、古い内容の送信が新しい内容を
    /// 上書きしないよう、送信は1つずつ順番に行う。
    /// 送信待ちには、変更が起きた時点の認証の世代と同期の世代も
    /// 持たせる。認証の世代が今と違う送信待ちは、前のログインの
    /// 変更なので送らない。同期の世代が違う送信待ちは、同期の
    /// オン・オフが切り替わる前の変更なので送らない (共通設定の
    /// 同期と同じ扱い)。通し番号は、送り直しの待ちの間に新しい
    /// 変更に置き換わったかどうかの判定に使う。
    private var pendingSave: (id: Int, settings: TimeTableDisplaySettings, generation: Int, syncGeneration: Int)?
    /// 送信待ちの通し番号の払い出し用。
    private var pendingSaveSequence = 0
    private var isSaving = false

    /// 取り込みの通し番号。取り込みが重なったとき、遅れて届いた
    /// 古い応答が、新しい応答で取り込んだ値を上書きしないために使う。
    private var refreshSequence = 0

    /// ログアウトで端末内の控えが消されたあと、今の値を既定値に戻す
    /// (控えが消えた状態は、初期化のときに既定値で受けるのと同じ)。
    /// 送信待ちの変更も取り下げる。
    func reloadFromLocalAfterLogout() {
        pendingSave = nil
        consecutiveSaveFailures = 0
        current = TimeTableDisplaySettings.defaults
    }

    /// 連続で保存に失敗した回数 (自動の送り直しの上限の判定に使う)。
    private var consecutiveSaveFailures = 0

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗したら通知で知らせる)。
    func update(_ settings: TimeTableDisplaySettings) {
        current = settings
        saveToLocal(settings)
        guard Self.isSyncEnabled else { return }
        // 世代は変更が起きたこの時点で確定させる (設定の同期と同じ理由)。
        pendingSaveSequence += 1
        pendingSave = (pendingSaveSequence, settings, SettingsStore.shared.authGeneration,
                       SettingsStore.shared.syncGeneration)
        consecutiveSaveFailures = 0
        guard !isSaving else { return }
        isSaving = true
        Task { await self.drainSaveQueue() }
    }

    /// 送信待ちの値を、古い順に1つずつ送る。失敗した分は捨てずに
    /// 戻し、間を置いて送り直す (上限あり)。送り直しを諦めたときに
    /// だけ、失敗の通知を出す。
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
            // 新しい保存がその間ずっと待たされてしまうため
            // (共通設定の同期と同じ扱い)。
            guard item.syncGeneration == SettingsStore.shared.syncGeneration,
                  Self.isSyncEnabled else { continue }
            // その間に新しい変更が来ていたら、そちらが最新なので
            // 古い分は戻さず、新しい分を続けて送る。
            guard pendingSave == nil else { continue }
            pendingSave = item
            consecutiveSaveFailures += 1
            guard consecutiveSaveFailures <= 3 else {
                // 送り直しの上限。戻した分は取り下げ、失敗したことは
                // 画面側へ知らせる (端末内には保存されているため、
                // 黙っていると他の端末で変わっていないことに
                // 気づけない)。
                pendingSave = nil
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .timeTableSettingsSaveFailed, object: nil)
                }
                continue
            }
            // 少し間を置いてから送り直す (通信が戻るのを待つ)。
            // 待ちは取り消せる形にし、待っている間に新しい変更が
            // 来たり、状態が変わったりしたら、待ちを打ち切って
            // 次の周で新しい状態に合わせて扱う (状態が変わっても
            // 待ちが終わるまで新しい保存が始まらない、ということが
            // ないようにするため。共通設定の同期と同じ扱い)。
            // 無効になった分は、次の周の冒頭の照合で取り下げられる。
            await waitBeforeRetry(of: item)
        }
        isSaving = false
        restartDrainIfNeeded()
    }

    /// 送り直しまでの待ち (最長15秒)。細切れに眠り、そのたびに
    /// 状態を確かめる。待ちの対象が新しい変更に置き換わっていたり、
    /// ログインや同期の状態が変わっていたりしたら、すぐに起きて
    /// 呼び出し側の次の周に任せる。
    private func waitBeforeRetry(
        of item: (id: Int, settings: TimeTableDisplaySettings, generation: Int, syncGeneration: Int)
    ) async {
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

    /// サーバー側の値を取り込んで、現在の値と違えば差し替える。
    /// 差し替えたかどうかを返す (呼び出し側は true のときだけ組み直す)。
    /// 同期が効いていない・取得に失敗したときは何もせず false を返す。
    /// 送信待ちの変更があるとき・取り込みの最中に利用者が変更した
    /// とき・認証や同期の世代が変わったときは取り込まない (送る前の
    /// 変更や別のログインの値を、古いサーバー値で上書きしないため。
    /// 同期を切った後に取得済みの値が反映されてしまうのも防ぐ)。
    func refreshFromServer() async -> Bool {
        guard Self.isSyncEnabled else { return false }
        guard pendingSave == nil, !isSaving else { return false }
        let currentAtStart = current
        let generationAtStart = SettingsStore.shared.authGeneration
        let syncGenerationAtStart = SettingsStore.shared.syncGeneration
        refreshSequence += 1
        let sequence = refreshSequence
        guard let settings = try? await APIClient.shared.fetchClientSettings() else {
            return false
        }
        // 同期が切り替わっていたら、その取得はもう無効なので反映
        // しない (同期を切った後に、取得済みの値が端末へ反映されて
        // しまうのを防ぐ。切って入れ直した場合も、古い取得は
        // 受け付けない)。取り込みが重なったときは、新しい方の
        // 応答だけを反映する。
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

    /// 端末内の控えへ書く。
    private func saveToLocal(_ settings: TimeTableDisplaySettings) {
        let store = SettingsStore.shared
        store.timeTableChannelWidth = settings.channelWidth
        store.timeTableHourHeight = settings.hourHeight
        store.timeTableDimShoppingPrograms = settings.dimShoppingPrograms
        store.timeTableGenreColors = settings.genreColors
    }

    /// 変更をサーバーへ送る。手順は視聴履歴の書き戻しと同じ:
    /// 送る直前に最新を取得 → 番組表の4項目だけ差し替え →
    /// last_synced_at を今に更新して送る。422 (その間に他の端末が先に
    /// 更新した) が返ったら、1回だけ取り直してやり直す。
    /// ジャンル色は、サーバー側にある分を土台にアプリが知っている
    /// ジャンルだけを上書きする (知らないジャンルがあっても落とさない)。
    private func saveToServer(
        _ settings: TimeTableDisplaySettings, expectedGeneration: Int,
        expectedSyncGeneration: Int
    ) async -> Bool {
        // 他の保存 (視聴履歴・各種設定) と重なって互いを上書きしないよう、
        // 保存の順番待ちに並んでから本体を行う。
        // 世代は呼び出し側が変更の時点で確定させたものを受け取る
        // (順番待ちの実行時点で読み直さない)。
        let box = BoolResultBox()
        await ClientSettingsSaveQueue.shared.run {
            box.value = await self.saveToServerSerial(
                settings, expectedGeneration: expectedGeneration,
                expectedSyncGeneration: expectedSyncGeneration)
        }
        return box.value
    }

    private func saveToServerSerial(
        _ settings: TimeTableDisplaySettings, expectedGeneration: Int,
        expectedSyncGeneration: Int
    ) async -> Bool {
        // 照合は、変更が起きた時点の世代で行う。順番待ちの間に
        // ログインし直していたら、この回の保存は打ち切る。
        // 同期の世代も同じで、順番待ちの間に同期を切られていたら
        // 打ち切る (共通設定の同期と同じ扱い)。
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
                clientSettings["timetable_channel_width"] = settings.channelWidth
                clientSettings["timetable_hour_height"] = settings.hourHeight
                clientSettings["timetable_dim_shopping_programs"] = settings.dimShoppingPrograms
                var genreColors = clientSettings["timetable_genre_colors"] as? [String: Any] ?? [:]
                for (genre, name) in settings.genreColors {
                    genreColors[genre] = name
                }
                clientSettings["timetable_genre_colors"] = genreColors
                clientSettings["last_synced_at"] = Date().timeIntervalSince1970
                try await APIClient.shared.updateClientSettings(
                    clientSettings, expectedAuthGeneration: generation)
                return true
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
            } catch {
                return false  // それ以外の失敗は、この回の送信を諦める。
            }
        }
        return false
    }

    /// 利用者設定の辞書から表示設定を組み立てる。項目が無い・形が違う
    /// ところは fallback (現在の値) で受ける。ジャンル色は、サーバー側の
    /// 割り当てを既定の上から上書きする形で受ける (サーバー側に無い
    /// ジャンルは既定の割り当てのまま)。
    private static func settings(
        fromClientSettings clientSettings: [String: Any],
        fallback: TimeTableDisplaySettings
    ) -> TimeTableDisplaySettings {
        var result = fallback
        if let width = clientSettings["timetable_channel_width"] as? String,
           SettingsStore.timeTableSizeOptions.contains(width) {
            result.channelWidth = width
        }
        if let height = clientSettings["timetable_hour_height"] as? String,
           SettingsStore.timeTableSizeOptions.contains(height) {
            result.hourHeight = height
        }
        if let dim = clientSettings["timetable_dim_shopping_programs"] as? Bool {
            result.dimShoppingPrograms = dim
        }
        if let serverColors = clientSettings["timetable_genre_colors"] as? [String: Any] {
            var colors = TimeTableDisplaySettings.defaultGenreColors
            for (genre, value) in serverColors {
                if let name = value as? String,
                   TimeTableDisplaySettings.isValidColorName(name) {
                    colors[genre] = name
                }
            }
            result.genreColors = colors
        }
        return result
    }
}
