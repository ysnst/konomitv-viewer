import Foundation
import CoreGraphics

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
    private var pendingSave: TimeTableDisplaySettings?
    private var isSaving = false

    /// ログアウトで端末内の控えが消されたあと、今の値を既定値に戻す
    /// (控えが消えた状態は、初期化のときに既定値で受けるのと同じ)。
    /// 送信待ちの変更も取り下げる。
    func reloadFromLocalAfterLogout() {
        pendingSave = nil
        current = TimeTableDisplaySettings.defaults
    }

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗しても握りつぶす)。
    func update(_ settings: TimeTableDisplaySettings) {
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
    /// 差し替えたかどうかを返す (呼び出し側は true のときだけ組み直す)。
    /// 同期が効いていない・取得に失敗したときは何もせず false を返す。
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
    private func saveToServer(_ settings: TimeTableDisplaySettings) async {
        // 他の保存 (視聴履歴・各種設定) と重なって互いを上書きしないよう、
        // 保存の順番待ちに並んでから本体を行う。
        await ClientSettingsSaveQueue.shared.run {
            await self.saveToServerSerial(settings)
        }
    }

    private func saveToServerSerial(_ settings: TimeTableDisplaySettings) async {
        for _ in 0..<2 {
            do {
                var clientSettings = try await APIClient.shared.fetchClientSettings()
                clientSettings["timetable_channel_width"] = settings.channelWidth
                clientSettings["timetable_hour_height"] = settings.hourHeight
                clientSettings["timetable_dim_shopping_programs"] = settings.dimShoppingPrograms
                var genreColors = clientSettings["timetable_genre_colors"] as? [String: Any] ?? [:]
                for (genre, name) in settings.genreColors {
                    genreColors[genre] = name
                }
                clientSettings["timetable_genre_colors"] = genreColors
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
