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

    /// サーバーへの送信待ちと、送信中かどうかの控え。
    /// 変更が短時間に重なっても、古い内容の送信が新しい内容を
    /// 上書きしないよう、送信は1つずつ順番に行う。
    /// 送信待ちには、編集の前後の値 (差分の元と先) と、変更が起きた
    /// 時点の認証の世代と同期の世代を持たせる。保存のときは、編集で
    /// 変わった項目だけを最新のサーバー値へ適用する (共通設定の
    /// 同期と同じ差分方式)。認証の世代が今と違う送信待ちは、前の
    /// ログインの変更なので送らない。同期の世代が違う送信待ちは、
    /// 同期のオン・オフが切り替わる前の変更なので送らない (共通設定
    /// の同期と同じ扱い)。通し番号は、送り直しの待ちの間に新しい
    /// 変更に置き換わったかどうかの判定に使う。
    private struct PendingSave {
        /// 通し番号。送り直しの待ちの間に、新しい変更に置き換わった
        /// かどうかの判定に使う。
        let id: Int
        /// 編集が起きる直前の値 (差分の元)。
        let base: TimeTableDisplaySettings
        /// 編集後の値 (差分の先)。
        let settings: TimeTableDisplaySettings
        /// 変更が起きた時点の認証の世代。
        let generation: Int
        /// 変更が起きた時点の同期の世代。
        let syncGeneration: Int
        /// 結果が分からない送信 (サーバーへ届いたかもしれないのに
        /// 応答が返らなかった送信) に含まれていた項目 (サーバー側の
        /// 項目名)。サーバーに残っているかもしれない値と、最終的な
        /// 意図が食い違うときに送り直すための控え (共通設定の同期と
        /// 同じ扱い)。
        var uncertainKeys: Set<String> = []
        /// 結果が分からない送信の時点の編集後の値。ジャンル色の
        /// ような項目ごとの値で、最終的な意図と食い違う分を特定
        /// するために使う。
        var uncertainDesired: TimeTableDisplaySettings?
    }

    /// サーバーへの送信の結果。届かなかったことが明らかな失敗と、
    /// 届いたかどうか分からない失敗を区別する (共通設定の同期と
    /// 同じ扱い)。
    private enum SaveOutcome {
        case success
        case notApplied
        case unknown
    }

    private var pendingSave: PendingSave?
    /// いま送っている最中の変更。送信の結果が分かるまでは、端末への
    /// 控えの対象として送信待ちと同じに扱う (共通設定の同期と同じ)。
    private var inFlightSave: PendingSave?
    /// 自動の送り直しの上限に達して、まだサーバーへ届いていない変更。
    /// 捨てずに保持し、次の変更や取り込みのときに差分へ合成して
    /// 送り直す (共通設定の同期と同じ扱い)。世代が変わったら前の
    /// 状態の変更なので、その時点で捨てる。
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

    /// 取り込みの通し番号。取り込みが重なったとき、遅れて届いた
    /// 古い応答が、新しい応答で取り込んだ値を上書きしないために使う。
    private var refreshSequence = 0

    /// ログアウトで端末内の控えが消されたあと、今の値を既定値に戻す
    /// (控えが消えた状態は、初期化のときに既定値で受けるのと同じ)。
    /// 送信待ちの変更も取り下げる。
    func reloadFromLocalAfterLogout() {
        pendingSave = nil
        inFlightSave = nil
        unsentSave = nil
        // 端末に残した未送信の変更の控えも消す (共通設定の同期と同じ)。
        restoredUnsent = nil
        SettingsStore.shared.unsentTimeTableSettingsData = nil
        consecutiveSaveFailures = 0
        current = TimeTableDisplaySettings.defaults
    }

    /// 連続で保存に失敗した回数 (自動の送り直しの上限の判定に使う)。
    private var consecutiveSaveFailures = 0

    /// 値を差し替える。端末内の控えへはその場で書き、同期が効いている
    /// ときはサーバーへも送る (送信は裏で行い、失敗したら通知で知らせる)。
    func update(_ settings: TimeTableDisplaySettings) {
        let previous = current
        current = settings
        saveToLocal(settings)
        // 前回の起動で送れずに端末へ残した変更があれば、ここで
        // 引き継ぐ (条件が合わなければ破棄する)。
        adoptRestoredUnsentIfNeeded()
        guard Self.isSyncEnabled else { return }
        // 世代は変更が起きたこの時点で確定させる (設定の同期と同じ理由)。
        let generation = SettingsStore.shared.authGeneration
        let syncGeneration = SettingsStore.shared.syncGeneration
        pendingSaveSequence += 1
        // まだ送れていない変更が残っていれば、差分の元はその変更の
        // 直前の値のまま引き継ぐ (間の編集も含めた差分にするため。
        // 共通設定の同期と同じ扱い)。送り直しの上限に達して未送信
        // として残っている分も同じく、ここで差分の元として引き継ぐ。
        // 世代の違う残りは前の状態のものなので引き継がない。
        // 結果が分からない送信の控えも合わせて引き継ぐ。
        var carriedBase: TimeTableDisplaySettings?
        var carriedUncertainKeys: Set<String> = []
        var carriedUncertainDesired: TimeTableDisplaySettings?
        if let unsent = unsentSave {
            unsentSave = nil
            if unsent.generation == generation,
               unsent.syncGeneration == syncGeneration {
                carriedBase = unsent.base
                carriedUncertainKeys = unsent.uncertainKeys
                carriedUncertainDesired = unsent.uncertainDesired
            }
        }
        let base: TimeTableDisplaySettings
        if let pending = pendingSave,
           pending.generation == generation,
           pending.syncGeneration == syncGeneration {
            base = pending.base
            carriedUncertainKeys.formUnion(pending.uncertainKeys)
            carriedUncertainDesired = pending.uncertainDesired
                ?? carriedUncertainDesired
        } else if let carriedBase {
            base = carriedBase
        } else {
            base = previous
        }
        pendingSave = PendingSave(
            id: pendingSaveSequence, base: base, settings: settings,
            generation: generation, syncGeneration: syncGeneration,
            uncertainKeys: carriedUncertainKeys,
            uncertainDesired: carriedUncertainDesired)
        syncPersistedRecord()
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
                base: item.base, desired: item.settings,
                uncertainKeys: item.uncertainKeys,
                uncertainDesired: item.uncertainDesired,
                expectedGeneration: item.generation,
                expectedSyncGeneration: item.syncGeneration)
            inFlightSave = nil
            if outcome == .success {
                consecutiveSaveFailures = 0
                syncPersistedRecord()
                continue
            }
            if outcome == .unknown {
                // 届いたかどうか分からない送信。サーバー側にこの変更
                // の値が残っているかもしれないので、含まれていた項目
                // とその時点の値を控える (共通設定の同期と同じ扱い)。
                item.uncertainKeys.formUnion(
                    Self.changedKeys(base: item.base, desired: item.settings))
                item.uncertainDesired = item.settings
            }
            // 送信の途中でログインが変わっていたら、この変更は
            // 前のログインのものなので戻さない。
            guard SettingsStore.shared.authGeneration == item.generation else {
                syncPersistedRecord()
                continue
            }
            // 同期が切り替わって無効になった変更も戻さない。戻すと、
            // 送り直しの待ち時間 (15秒) を無効な分が占有して、
            // 新しい保存がその間ずっと待たされてしまうため
            // (共通設定の同期と同じ扱い)。
            guard item.syncGeneration == SettingsStore.shared.syncGeneration,
                  Self.isSyncEnabled else {
                syncPersistedRecord()
                continue
            }
            consecutiveSaveFailures += 1
            // その間に新しい変更が来ていたら、失敗した分の差分を
            // 新しい分の差分へ合成してから送る。新しい分の差分の元は
            // 「失敗した変更が入った後の値」なので、そのまま送ると
            // 失敗した分の項目は差分に現れず、サーバーへ届かない
            // (共通設定の同期と同じ扱い)。
            if let pending = pendingSave {
                if pending.generation == item.generation,
                   pending.syncGeneration == item.syncGeneration {
                    // 結果が分からない送信の控えは、失敗した分と新しい
                    // 分の両方から引き継ぐ (共通設定の同期と同じ扱い)。
                    let merged = PendingSave(
                        id: pending.id, base: item.base, settings: pending.settings,
                        generation: pending.generation,
                        syncGeneration: pending.syncGeneration,
                        uncertainKeys: item.uncertainKeys.union(pending.uncertainKeys),
                        uncertainDesired: pending.uncertainDesired
                            ?? item.uncertainDesired)
                    if consecutiveSaveFailures > 3 {
                        // 送り直しの上限。合成した分は捨てずに未送信
                        // として残し、失敗したことは画面側へ知らせる。
                        unsentSave = merged
                        pendingSave = nil
                        syncPersistedRecord()
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .timeTableSettingsSaveFailed, object: nil)
                        }
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
                // 送り直しの上限。諦めた分は捨てずに未送信として
                // 残し、次の変更や取り込みのときに送り直す。
                // あわせて、失敗したことは画面側へ知らせる (端末内に
                // は保存されているため、黙っていると他の端末で
                // 変わっていないことに気づけない)。
                unsentSave = item
                syncPersistedRecord()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .timeTableSettingsSaveFailed, object: nil)
                }
                continue
            }
            pendingSave = item
            syncPersistedRecord()
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
    /// 共通設定の同期と同じ作り・方針。
    private struct RestoredUnsent {
        /// どのアカウント・接続先の変更かを示す目印。
        let identity: String
        let base: TimeTableDisplaySettings
        let desired: TimeTableDisplaySettings
        let uncertainKeys: Set<String>
        let uncertainDesired: TimeTableDisplaySettings?
    }

    /// 端末から読み出した控え。引き継ぐかどうかは、使う時点で
    /// ログインと同期の状態と照合して決める。
    private var restoredUnsent: RestoredUnsent?
    private var restoredUnsentLoaded = false

    /// いま未送信の変更全体 (古い分から新しい分へ合成した形)。
    /// 端末への控えはこの形で残す。
    private func outstandingSave() -> PendingSave? {
        var result: PendingSave?
        for item in [unsentSave, inFlightSave, pendingSave].compactMap({ $0 }) {
            if let accumulated = result {
                result = PendingSave(
                    id: item.id, base: accumulated.base, settings: item.settings,
                    generation: item.generation,
                    syncGeneration: item.syncGeneration,
                    uncertainKeys: accumulated.uncertainKeys.union(item.uncertainKeys),
                    uncertainDesired: item.uncertainDesired
                        ?? accumulated.uncertainDesired)
            } else {
                result = item
            }
        }
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
            store.unsentTimeTableSettingsData = nil
            return
        }
        var record: [String: Any] = [
            "identity": store.unsentSettingsIdentity,
            "base": Self.displaySettingsDictionary(from: item.base),
            "desired": Self.displaySettingsDictionary(from: item.settings),
            "uncertainKeys": Array(item.uncertainKeys),
        ]
        if let uncertainDesired = item.uncertainDesired {
            record["uncertainDesired"] =
                Self.displaySettingsDictionary(from: uncertainDesired)
        }
        store.unsentTimeTableSettingsData =
            try? JSONSerialization.data(withJSONObject: record)
    }

    /// 端末に残した未送信の変更を読み出し、条件が合えば未送信分と
    /// して引き継ぐ。条件と破棄の方針は共通設定の同期と同じ
    /// (ログイン中かつ同期が入っていて目印が一致すれば引き継ぎ、
    /// 同期が切れているとき (ログイン中の場合) と目印が違うときは
    /// 破棄、ログインしていないだけのときは残しておく)。
    /// ログイン時の自動取り込み (同期を後から有効にする経路) からも、
    /// 有効にする前に破棄の判定だけ行うために呼ばれる。
    func adoptRestoredUnsentIfNeeded() {
        if !restoredUnsentLoaded {
            restoredUnsentLoaded = true
            restoredUnsent = Self.loadPersistedRecord()
        }
        guard let restored = restoredUnsent else { return }
        let store = SettingsStore.shared
        guard Self.isSyncEnabled else {
            if store.isLoggedIn {
                restoredUnsent = nil
                store.unsentTimeTableSettingsData = nil
            }
            return
        }
        guard restored.identity == store.unsentSettingsIdentity else {
            restoredUnsent = nil
            store.unsentTimeTableSettingsData = nil
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
            id: 0, base: restored.base, settings: restored.desired,
            generation: store.authGeneration,
            syncGeneration: store.syncGeneration,
            uncertainKeys: restored.uncertainKeys,
            uncertainDesired: restored.uncertainDesired)
        syncPersistedRecord()
    }

    /// 端末に残した控えを読み出す。形が違う・読めないときは nil。
    private static func loadPersistedRecord() -> RestoredUnsent? {
        guard let data = SettingsStore.shared.unsentTimeTableSettingsData,
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let identity = record["identity"] as? String,
              let baseDict = record["base"] as? [String: Any],
              let desiredDict = record["desired"] as? [String: Any]
        else { return nil }
        let uncertainDesired = (record["uncertainDesired"] as? [String: Any]).map {
            settings(fromClientSettings: $0, fallback: .defaults)
        }
        return RestoredUnsent(
            identity: identity,
            base: settings(fromClientSettings: baseDict, fallback: .defaults),
            desired: settings(fromClientSettings: desiredDict, fallback: .defaults),
            uncertainKeys: Set(record["uncertainKeys"] as? [String] ?? []),
            uncertainDesired: uncertainDesired)
    }

    /// 表示設定一式を、サーバーの利用者設定と同じ形の辞書に写す
    /// (端末への控えの保存に使う。読み戻しは
    /// settings(fromClientSettings:) で行う)。
    private static func displaySettingsDictionary(
        from settings: TimeTableDisplaySettings
    ) -> [String: Any] {
        [
            "timetable_channel_width": settings.channelWidth,
            "timetable_hour_height": settings.hourHeight,
            "timetable_dim_shopping_programs": settings.dimShoppingPrograms,
            "timetable_genre_colors": settings.genreColors,
        ]
    }

    /// サーバー側の値を取り込んで、現在の値と違えば差し替える。
    /// 差し替えたかどうかを返す (呼び出し側は true のときだけ組み直す)。
    /// 同期が効いていない・取得に失敗したときは何もせず false を返す。
    /// 送信待ちの変更があるとき・取り込みの最中に利用者が変更した
    /// とき・認証や同期の世代が変わったときは取り込まない (送る前の
    /// 変更や別のログインの値を、古いサーバー値で上書きしないため。
    /// 同期を切った後に取得済みの値が反映されてしまうのも防ぐ)。
    func refreshFromServer() async -> Bool {
        // 前回の起動で送れずに端末へ残した変更があれば、ここで
        // 引き継ぐ (条件が合わなければ破棄する)。
        adoptRestoredUnsentIfNeeded()
        guard Self.isSyncEnabled else { return false }
        // 未送信の変更が残っていたら、先に送り直す。取り込みを先に
        // すると、届いていない端末の値がサーバーの古い値で上書き
        // されてしまうため、取り込み自体は送り直しの後の回に回す
        // (共通設定の同期と同じ扱い)。世代の違う未送信分は前の
        // 状態のものなので捨てる。
        if let unsent = unsentSave {
            unsentSave = nil
            if unsent.generation == SettingsStore.shared.authGeneration,
               unsent.syncGeneration == SettingsStore.shared.syncGeneration {
                if let pending = pendingSave,
                   pending.generation == unsent.generation,
                   pending.syncGeneration == unsent.syncGeneration {
                    // 送信待ちがある間は、その差分の元へ合成して引き継ぐ。
                    // 結果が分からない送信の控えも合わせて引き継ぐ。
                    pendingSave = PendingSave(
                        id: pending.id, base: unsent.base, settings: pending.settings,
                        generation: pending.generation,
                        syncGeneration: pending.syncGeneration,
                        uncertainKeys: unsent.uncertainKeys.union(pending.uncertainKeys),
                        uncertainDesired: pending.uncertainDesired
                            ?? unsent.uncertainDesired)
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

    /// 送信の結果を受け渡すための箱 (順番待ちの中から書き戻すため)。
    private final class SaveOutcomeBox: @unchecked Sendable {
        var value = SaveOutcome.notApplied
    }

    /// 変更をサーバーへ送る。結果 (送れた／届いていないことが明らか／
    /// 結果が分からない) を返す。手順は視聴履歴の書き戻しと同じ:
    /// 送る直前に最新を取得 → 編集で変わった項目だけを最新の値へ
    /// 適用する → last_synced_at を今に更新して送る。422 (その間に
    /// 他の端末が先に更新した) が返ったら、1回だけ取り直して、
    /// 同じ差分を新しい最新へ適用し直す。
    /// ジャンル色はジャンルごとに比べ、変わった分だけをサーバー側の
    /// 割り当てへ上書きする (知らないジャンルがあっても落とさない)。
    /// 結果が分からない送信に含まれていた項目は、編集の前後で値が
    /// 同じでも、取得した最新の値と最終的な意図が食い違えば意図の
    /// 値で送り直す (共通設定の同期と同じ扱い)。
    private func saveToServer(
        base: TimeTableDisplaySettings, desired: TimeTableDisplaySettings,
        uncertainKeys: Set<String>, uncertainDesired: TimeTableDisplaySettings?,
        expectedGeneration: Int, expectedSyncGeneration: Int
    ) async -> SaveOutcome {
        // 他の保存 (視聴履歴・各種設定) と重なって互いを上書きしないよう、
        // 保存の順番待ちに並んでから本体を行う。
        // 世代は呼び出し側が変更の時点で確定させたものを受け取る
        // (順番待ちの実行時点で読み直さない)。
        let box = SaveOutcomeBox()
        await ClientSettingsSaveQueue.shared.run {
            box.value = await self.saveToServerSerial(
                base: base, desired: desired,
                uncertainKeys: uncertainKeys, uncertainDesired: uncertainDesired,
                expectedGeneration: expectedGeneration,
                expectedSyncGeneration: expectedSyncGeneration)
        }
        return box.value
    }

    private func saveToServerSerial(
        base: TimeTableDisplaySettings, desired: TimeTableDisplaySettings,
        uncertainKeys: Set<String>, uncertainDesired: TimeTableDisplaySettings?,
        expectedGeneration: Int, expectedSyncGeneration: Int
    ) async -> SaveOutcome {
        // 照合は、変更が起きた時点の世代で行う。順番待ちの間に
        // ログインし直していたら、この回の保存は打ち切る。
        // 同期の世代も同じで、順番待ちの間に同期を切られていたら
        // 打ち切る (共通設定の同期と同じ扱い)。
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
            // 編集の前後で変わった項目だけを、取得した最新の
            // サーバー値へ適用する。変わっていない項目は最新の
            // 値のまま触らないため、他の端末が変えた幅・高さ・
            // ジャンル色が、無関係な保存で消えることはない。
            if base.channelWidth != desired.channelWidth
                || (uncertainKeys.contains("timetable_channel_width")
                    && (clientSettings["timetable_channel_width"] as? String)
                        != desired.channelWidth) {
                clientSettings["timetable_channel_width"] = desired.channelWidth
            }
            if base.hourHeight != desired.hourHeight
                || (uncertainKeys.contains("timetable_hour_height")
                    && (clientSettings["timetable_hour_height"] as? String)
                        != desired.hourHeight) {
                clientSettings["timetable_hour_height"] = desired.hourHeight
            }
            if base.dimShoppingPrograms != desired.dimShoppingPrograms
                || (uncertainKeys.contains("timetable_dim_shopping_programs")
                    && (clientSettings["timetable_dim_shopping_programs"] as? NSNumber)?
                        .boolValue != desired.dimShoppingPrograms) {
                clientSettings["timetable_dim_shopping_programs"] =
                    desired.dimShoppingPrograms
            }
            // ジャンル色はジャンルごとに比べる。結果が分からない
            // 送信に含まれていたジャンルは、その送信の値と最終的な
            // 意図が食い違い、かつ最新の値も意図と違えば送り直す。
            let latestGenreColors =
                clientSettings["timetable_genre_colors"] as? [String: Any] ?? [:]
            var changedGenreColors: [String: String] = [:]
            for (genre, name) in desired.genreColors {
                if base.genreColors[genre] != name {
                    changedGenreColors[genre] = name
                } else if uncertainKeys.contains("timetable_genre_colors"),
                          let uncertainDesired,
                          uncertainDesired.genreColors[genre] != name,
                          (latestGenreColors[genre] as? String) != name {
                    changedGenreColors[genre] = name
                }
            }
            if !changedGenreColors.isEmpty {
                var genreColors = latestGenreColors
                for (genre, name) in changedGenreColors {
                    genreColors[genre] = name
                }
                clientSettings["timetable_genre_colors"] = genreColors
            }
            clientSettings["last_synced_at"] = Date().timeIntervalSince1970
            do {
                try await APIClient.shared.updateClientSettings(
                    clientSettings, expectedAuthGeneration: generation)
                return .success
            } catch let APIError.badStatus(code) where code == 422 {
                continue  // 取り直して1回だけやり直す。
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
    /// 結果が分からない送信に含まれていた項目を特定するために使う。
    private static func changedKeys(
        base: TimeTableDisplaySettings, desired: TimeTableDisplaySettings
    ) -> [String] {
        var keys: [String] = []
        if base.channelWidth != desired.channelWidth {
            keys.append("timetable_channel_width")
        }
        if base.hourHeight != desired.hourHeight {
            keys.append("timetable_hour_height")
        }
        if base.dimShoppingPrograms != desired.dimShoppingPrograms {
            keys.append("timetable_dim_shopping_programs")
        }
        if base.genreColors != desired.genreColors {
            keys.append("timetable_genre_colors")
        }
        return keys
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
