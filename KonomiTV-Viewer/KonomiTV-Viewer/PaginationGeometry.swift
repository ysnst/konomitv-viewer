import Foundation

/// UIKitから受け取った確定座標でページ送りの位置を決める。通信や遅延には依存しない。
enum PaginationGeometry {
    static func restoredOffset(currentOffset: Double, savedOffset: Double, insetDifference: Double,
                               anchorDelta: Double?, scrollToTop: Bool, minimum: Double, maximum: Double) -> Double {
        let target: Double
        if scrollToTop {
            // Fの「先頭」は、先頭番組ではなくヘッダーを含む一覧全体の最上部。
            target = minimum
        } else if let anchorDelta {
            // footerまでの高さがページごとに違っても、操作元pagerの画面内位置を維持する。
            // UIKitが既にoffsetを補正した場合も、その後の実座標差を使うため二重補正しない。
            target = currentOffset + anchorDelta
        } else {
            // 通常更新や固定された上部pagerでは、従来の可視領域からの距離を保持する。
            target = savedOffset + insetDifference
        }
        return min(max(minimum, maximum), max(minimum, target))
    }

    static func pageCount(totalItems: Int, pageSize: Int) -> Int {
        guard totalItems > 0, pageSize > 0 else { return 1 }
        return totalItems / pageSize + (totalItems % pageSize == 0 ? 0 : 1)
    }

    static func pageWindow(currentPage: Int, totalPages: Int) -> [Int] {
        let total = max(0, totalPages)
        let count = min(total, 5)
        guard count > 0 else { return [] }
        let current = min(max(currentPage, 1), total)
        let start = min(max(current - 2, 1), total - count + 1)
        // 半開区間の上限をtotal+1で作らず、Int.maxでも最後の番号まで表現できる形にする。
        return (0..<count).map { start + $0 }
    }
}
