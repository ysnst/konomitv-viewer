import Foundation

/// 改造版サーバーの機能の出し分け。
///
/// 録画の保護まわり・ゴミ箱など、konomitv-customizations を適用した
/// 改造版サーバーが持つ受け口を使う機能は、端末ごとのトグル
/// 「改造版サーバーの機能を使う」
/// (SettingsStore.customizedServerFeaturesEnabled、既定オフ) が
/// オンのときだけ出す。以前はビルドの版分け (一般版 / 拡張版) で
/// 切り替えていたが、版を1本にまとめたため、このトグルに移した。
/// トグルがオフのときの動きは以前の一般版と同じ、オンのときは
/// 以前の拡張版と同じになる。
///
/// トグルの置き場所は「このアプリの設定」の「改造版サーバーの機能」の
/// 区分で、区分自体はマイページの App version の行を7回タップすると
/// 解放される (解放の状態も端末ごとに保存される)。
///
/// 呼び出し側の名前 (isHousehold / isGeneral) は版分けの頃のままだが、
/// 意味は「トグルがオン / オフ」に読み替える。データ放送は素の
/// サーバーの機能なので、この出し分けの対象にはしない。
enum AppEdition {
    /// 改造版サーバーの機能を使う (トグルがオン) かどうか。
    static var isHousehold: Bool {
        SettingsStore.shared.customizedServerFeaturesEnabled
    }

    static var isGeneral: Bool { !isHousehold }
}
