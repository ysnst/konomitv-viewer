import Foundation

/// 実況コメントの密度 (盛り上がり) の計算 (Web 版 CommentHighlights.ts の写し)。
///
/// 計算方法は Web 版とそろえてある: 5秒ビンに集計 → 3ビンの移動平均で
/// 平滑化 → 最大値で正規化し、最大値の40%以上の連続区間 (隙間2ビンまで
/// 連結、3ビン未満は除外) を盛り上がり区間とする。ただし区間の合計が
/// 全体の70%を超える場合は、盛り上がり区間としては扱わない。
/// 区間には前後の余白 (開始−15秒・終了＋10秒) が付く。実況コメントは
/// 映像より遅れて付くため開始側を長めに取り、瞬間的に決まる場面でも
/// 始まりから余韻まで含めるための Web 版の決め方である。

/// 1ビンの秒数。
let commentBinSeconds: Double = 5

/// 盛り上がりとして扱うために必要なコメント総数の下限。
let minCommentsForHighlights = 50

/// 盛り上がり区間とみなす密度の閾値 (最大値に対する比率)。
private let segmentThresholdRatio = 0.4
/// 連結を許す隙間の最大ビン数。
private let maxGapBins = 2
/// 区間として扱う最小ビン数。
private let minSegmentBins = 3
/// 区間の合計がこの比率を超えたら盛り上がり区間として扱わない。
private let maxCoverageRatio = 0.7
/// 区間の前後に付ける余白 (秒)。
private let segmentPadStartSeconds: Double = 15
private let segmentPadEndSeconds: Double = 10

/// 盛り上がり区間。
struct HighlightSegment {
    /// 開始位置 (秒、余白込み)。
    let start: Double
    /// 終了位置 (秒、余白込み)。
    let end: Double
    /// 区間内の最大密度 (0.0〜1.0)。
    let peakDensity: Double
    /// 区間内のコメント数。
    let commentCount: Int
}

/// コメント密度の計算結果。
struct CommentDensity {
    /// 正規化済み密度 (ビンごと)。
    let densities: [Double]
    /// 生のコメント数 (ビンごと)。
    let counts: [Int]
    /// コメント総数。
    let total: Int
    /// 計算に使った尺 (秒)。
    let duration: Double
}

/// コメントの再生位置の並びから密度を計算する (Web 版 computeCommentDensity の写し)。
/// - Parameters:
///   - positions: コメントの再生位置 (秒) の並び。
///   - duration: 録画の尺 (秒)。0 の場合はコメントの最大位置から推定する。
func computeCommentDensity(positions: [Double], duration: Double) -> CommentDensity {
    let maxPosition = positions.max() ?? 0
    let effectiveDuration = duration > 0 ? duration : maxPosition + commentBinSeconds

    let binCount = max(1, Int(ceil(effectiveDuration / commentBinSeconds)))
    var counts = [Int](repeating: 0, count: binCount)
    for position in positions {
        let index = min(binCount - 1, max(0, Int(floor(position / commentBinSeconds))))
        counts[index] += 1
    }
    // 3ビンの移動平均で平滑化し、最大値で正規化する。
    let smoothed = counts.indices.map { i -> Double in
        let prev = counts[max(0, i - 1)]
        let curr = counts[i]
        let next = counts[min(binCount - 1, i + 1)]
        return Double(prev + curr * 2 + next) / 4
    }
    let maxDensity = max(smoothed.max() ?? 0, 0.0001)
    let densities = smoothed.map { $0 / maxDensity }
    return CommentDensity(densities: densities, counts: counts, total: positions.count, duration: effectiveDuration)
}

/// 密度から盛り上がり区間を抽出する (Web 版 extractHighlightSegments の写し)。
func extractHighlightSegments(density: CommentDensity) -> [HighlightSegment] {
    var hot = density.densities.map { $0 >= segmentThresholdRatio }
    // 隙間埋め (前後が盛り上がっていて、隙間が許容量以下ならつなぐ)。
    var i = 0
    while i < hot.count {
        if hot[i] {
            i += 1
            continue
        }
        var gap = 0
        while i + gap < hot.count && !hot[i + gap] {
            gap += 1
        }
        let before = i > 0 && hot[i - 1]
        let after = i + gap < hot.count && hot[i + gap]
        if before && after && gap <= maxGapBins {
            for j in 0..<gap {
                hot[i + j] = true
            }
        }
        i += gap
    }
    // 連続区間の抽出と短い区間の除外。
    var segments: [HighlightSegment] = []
    var startBin: Int?
    for index in 0...hot.count {
        if index < hot.count && hot[index] {
            if startBin == nil {
                startBin = index
            }
        } else if let start = startBin {
            if index - start >= minSegmentBins {
                var peak: Double = 0
                var commentCount = 0
                for bin in start..<index {
                    peak = max(peak, density.densities[bin])
                    commentCount += density.counts[bin]
                }
                segments.append(HighlightSegment(
                    start: Double(start) * commentBinSeconds,
                    end: Double(index) * commentBinSeconds,
                    peakDensity: peak,
                    commentCount: commentCount))
            }
            startBin = nil
        }
    }
    // カバー率が高すぎる場合は盛り上がり区間として扱わない。
    let covered = segments.reduce(0.0) { $0 + ($1.end - $1.start) }
    if density.duration > 0 && covered / density.duration > maxCoverageRatio {
        return []
    }
    // 区間に前後の余白を付け、重なった区間はまとめる。
    var padded: [HighlightSegment] = []
    for segment in segments {
        let start = max(0, segment.start - segmentPadStartSeconds)
        let end = min(density.duration, segment.end + segmentPadEndSeconds)
        if let last = padded.last, start <= last.end {
            padded[padded.count - 1] = HighlightSegment(
                start: last.start,
                end: max(last.end, end),
                peakDensity: max(last.peakDensity, segment.peakDensity),
                commentCount: last.commentCount + segment.commentCount)
        } else {
            padded.append(HighlightSegment(
                start: start, end: end,
                peakDensity: segment.peakDensity, commentCount: segment.commentCount))
        }
    }
    return padded
}
