import Foundation
import Network

/// 現在の接続がモバイル回線かどうかを見張る部品。
///
/// 使い方: 再生を始めるときに `SettingsStore.initialPlaybackProfile()` 経由で
/// 読み、その再生で使う画質の区分 (Wi-Fi 回線時 / モバイル回線時) を決める
/// (手動切り替えの記憶があれば、そちらが優先される)。
/// 再生の途中で回線が切り替わっても、再生中の画質は変えない
/// (録画再生はサーバー側のセッションと画質がひも付いていて、途中で画質だけ
/// 変える要求はエラーになるため。切り替わった回線は次に再生を始めるときから効く)。
/// これは Web 版の動き (画質の区分はプレイヤーを作るときに決まる) と同じ。
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    /// モバイル回線でつながっているか。経路がまだ取れていない間は false
    /// (Wi-Fi 扱い。Web 版でも判定できない環境は Wi-Fi 扱い)。
    /// 書き込みは見張り用のキューから、読み取りは主にメインスレッドから。
    /// 真偽値1つの受け渡しなので、そのまま読む形にしている。
    private(set) var isCellular = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Web 版の「モバイル回線以外は全部 Wi-Fi 扱い」に合わせ、
            // cellular のときだけモバイル回線側、それ以外は Wi-Fi 側に寄せる
            // (Wi-Fi が無く有線だけのときも Wi-Fi 側)。
            self?.isCellular = path.usesInterfaceType(.cellular)
        }
        monitor.start(queue: DispatchQueue(
            label: "jp.tatsuya0902.konomitv.viewer.network-monitor"))
    }

    /// いま再生を始めるときに使う回線の区分。
    var currentProfile: PlaybackProfile {
        isCellular ? .cellular : .wifi
    }
}
