import Foundation

/// ハイライト横断再生の再生キュー (Web 版 HighlightReel.ts の写し)。
///
/// 「今日のハイライト」の画面がキューを作り、再生画面が順に再生する。
/// Web 版は sessionStorage で引き継ぐが、アプリでは画面同士が同じ
/// プロセスの中で受け渡すため、メモリ上の共有の置き場で受ける
/// (アプリを閉じれば消える点は Web 版のタブを閉じた場合と同じ)。
final class HighlightReelStore {
    static let shared = HighlightReelStore()

    /// ハイライトの1区間。
    struct Item {
        /// 録画の ID。
        let videoID: Int
        /// 番組の題名 (表示用)。
        let title: String
        /// 再生を始める位置 (秒)。
        let start: Double
        /// 再生を終える位置 (秒)。
        let end: Double
        /// 区間内の実況コメントの件数 (一覧の表示用)。
        let commentCount: Int
    }

    /// 順に再生する区間の並び。
    private(set) var items: [Item] = []
    /// いま再生中の区間の番号。
    private(set) var index = 0

    private init() {}

    /// キューが有効か (区間が残っているか)。
    var isActive: Bool {
        !items.isEmpty && index < items.count
    }

    /// いま再生中の区間。キューが無ければ nil。
    var currentItem: Item? {
        isActive ? items[index] : nil
    }

    /// ハイライト再生を始める (キューを作り直す)。
    func start(items: [Item]) {
        self.items = items
        index = 0
    }

    /// 次の区間へ進む。進んだ先の区間を返し、もう無ければ nil を返す
    /// (その場合はキューも破棄する)。
    @discardableResult
    func advance() -> Item? {
        index += 1
        guard isActive else {
            clear()
            return nil
        }
        return items[index]
    }

    /// キューを破棄する。
    func clear() {
        items = []
        index = 0
    }
}
