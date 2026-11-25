import Foundation

@main
struct PaginationTests {
    static func main() {
        func restore(current: Double = 1000, saved: Double = 1000, inset: Double = 0,
                     delta: Double? = nil, top: Bool = false, minimum: Double = -20, maximum: Double = 3000) -> Double {
            PaginationGeometry.restoredOffset(currentOffset: current, savedOffset: saved,
                insetDifference: inset, anchorDelta: delta, scrollToTop: top, minimum: minimum, maximum: maximum)
        }
        // ONは操作元が上下どちらでも、番組行ではなく一覧全体の最上部。
        precondition(restore(delta: 500, top: true) == -20)
        precondition(restore(current: -20, saved: -20, delta: 0, top: true) == -20)
        // OFFはpagerの実際の画面内移動分だけを補正する。
        precondition(restore(delta: 0) == 1000)
        precondition(restore(delta: 120) == 1120)
        precondition(restore(delta: -180) == 820)
        // UIKitが高さの差分を既に補正済みなら、同じ差分を再び足さない。
        precondition(restore(current: 1120, saved: 1000, delta: 0) == 1120)
        precondition(restore(current: 1060, saved: 1000, delta: 60) == 1120)
        // 上下限と短い末尾ページは有効範囲だけに制限する。
        precondition(restore(delta: 4000) == 3000)
        precondition(restore(delta: -4000) == -20)
        precondition(restore(delta: 120, maximum: 200) == 200)
        precondition(restore(delta: 120, maximum: -100) == -20)
        // 自動更新/復帰はsourceなしで、保存offsetとインセット差を使う。
        precondition(restore(current: 900, saved: 1000) == 1000)
        precondition(restore(saved: 1000, inset: 24) == 1024)
        precondition(restore(saved: 1000, inset: -24) == 976)

        let pages = PaginationGeometry.pageCount(totalItems: 9615, pageSize: 30)
        precondition(pages == 321)
        precondition(PaginationGeometry.pageCount(totalItems: 9600, pageSize: 30) == 320)
        precondition(PaginationGeometry.pageCount(totalItems: 0, pageSize: 30) == 1)
        precondition(PaginationGeometry.pageCount(totalItems: 1, pageSize: 30) == 1)
        precondition(PaginationGeometry.pageWindow(currentPage: 1, totalPages: pages) == [1, 2, 3, 4, 5])
        precondition(PaginationGeometry.pageWindow(currentPage: 161, totalPages: pages) == [159, 160, 161, 162, 163])
        precondition(PaginationGeometry.pageWindow(currentPage: pages, totalPages: pages) == [317, 318, 319, 320, 321])
        precondition(PaginationGeometry.pageWindow(currentPage: 99, totalPages: 3) == [1, 2, 3])
        precondition(PaginationGeometry.pageWindow(currentPage: 1, totalPages: 0).isEmpty)
        precondition(PaginationGeometry.pageWindow(currentPage: Int.max, totalPages: Int.max).last == Int.max)
        print("Pagination tests passed: whole-page top, source anchor, UIKit correction, bounds, refresh insets, and direct last-page window")
    }
}
