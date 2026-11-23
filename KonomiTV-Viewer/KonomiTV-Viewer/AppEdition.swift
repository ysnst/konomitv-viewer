import Foundation

/// ビルドの版分け。
///
/// うちの改造サーバーが前提の機能 (録画の保護まわり) は「拡張版」だけで出し、
/// 一般の KonomiTV サーバー向けの「一般版」では出さない。
/// 切り替えはビルド設定 APP_EDITION で行い、Info.plist の AppEdition に入る。
/// 値が "general" のときだけ一般版で、それ以外 (未設定を含む) は拡張版になる
/// (これまでのビルドは全部拡張版として扱う)。
enum AppEdition {
    static var isGeneral: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AppEdition") as? String) == "general"
    }

    static var isHousehold: Bool { !isGeneral }
}
