import Foundation

/// 改造版サーバーの機能の出し分け。
///
/// 録画の保護・ゴミ箱など、konomitv-customizations を適用した
/// 改造版サーバーが持つ受け口を使う機能は、機能ごとのトグル
/// (SettingsStore の customized…Enabled、どれも既定オフ) が
/// オンのときだけ出す。以前はビルドの版分け (一般版 / 拡張版) で
/// 切り替え、次にまとめトグル「改造版サーバーの機能を使う」へ
/// 移したが、機能ごとに切り替えられるよう専用画面の個別トグルに
/// 組み替えた。まとめトグルの値は、初回に個別トグル全部へ
/// 引き継がれる (SettingsStore 側の引き継ぎ処理)。
///
/// 個別トグルの対象は、改造版サーバーが要るものだけ: 録画の保護、
/// ゴミ箱、前の話・次の話と自動再生、しおりと場面一覧、
/// 録画結果一覧、チューナー使用中のチャンネル表示。次回を予約と
/// シリーズ予約・自動予約の条件はトグルの対象ではなく、予約機能と
/// 同じ条件 (後ろ側が EDCB のとき) で出す。アプリだけで完結する
/// もの (長押しの高速シーク、追いかけ再生の先端追従、ログイン時の
/// 設定の自動取り込み、番組表と録画一覧の見ていた場所の復元、
/// 盛り上がり波形とダイジェスト再生、コメント検索、今日の
/// ハイライトと横断再生) は常時有効。番組表の予約セルの塗りと
/// チューナー使用帯は、番組表の表示設定の中の専用スイッチ
/// (SettingsStore.timeTableReservationHighlightEnabled) で切り替える。
///
/// トグルの置き場所は「このアプリの設定」の「改造版サーバーの
/// 機能」の行から入る専用画面で、その行自体はマイページの
/// App version の行を7回タップすると解放される (解放の状態も
/// 端末ごとに保存される)。
///
/// 全体の有効・無効は解放の状態と一体になっている。専用画面の
/// 「拡張機能を無効にする」を実行すると解放が戻り、入口の行自体が
/// 消えて、機能も全部止まる (Android の開発者向けオプションの
/// オフと同じ扱い)。個別トグルの状態は保持されるため、解放し直せば
/// そのままの状態で復帰する。データ放送は素のサーバーの機能
/// なので、この出し分けの対象にはしない。
enum AppEdition {
    /// 全体が有効かどうか (解放済みかどうかと一体)。
    private static var overallEnabled: Bool {
        SettingsStore.shared.customizedServerFeaturesUnlocked
    }

    /// 録画の保護のトグルがオンかどうか。
    static var protectionEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedProtectionEnabled
    }

    /// ゴミ箱のトグルがオンかどうか。
    static var trashEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedTrashEnabled
    }

    /// 前の話・次の話ボタンと、次の話の自動再生のトグルがオンかどうか。
    static var episodeNavigationEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedEpisodesEnabled
    }

    /// しおりと場面一覧のトグルがオンかどうか。
    static var bookmarksAndScenesEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedBookmarksScenesEnabled
    }

    /// 録画結果一覧のトグルがオンかどうか。
    static var recordingResultsEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedRecordingResultsEnabled
    }

    /// チューナー使用中のチャンネル表示のトグルがオンかどうか。
    static var tunerInUseEnabled: Bool {
        overallEnabled && SettingsStore.shared.customizedTunerInUseEnabled
    }
}
