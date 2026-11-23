import UIKit

/// シークバーの上に重ねる、実況コメントの盛り上がりの波形 (Web 版
/// ExcitementManager の帯の写し)。5秒ごとの密度をピンクの棒で描き、
/// 盛り上がり区間の中は濃く、外は薄く出す。帯を押すとその位置へ移動する
/// (移動と再生の実行は呼び出し側へ委ねる)。
final class ExcitementStripView: UIView {
    /// 正規化済み密度 (ビンごと、最大 1.0)。空なら何も描かない。
    var densities: [Double] = [] {
        didSet { setNeedsDisplay() }
    }
    /// 盛り上がり区間 (秒)。棒の濃さの出し分けに使う。
    var segments: [HighlightSegment] = [] {
        didSet { setNeedsDisplay() }
    }
    /// 計算に使った尺 (秒)。区間の位置合わせに使う。
    var duration: Double = 0 {
        didSet { setNeedsDisplay() }
    }
    /// 帯が押されたときの知らせ先 (引数は 0.0〜1.0 の割合)。
    var onTapped: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Web 版の帯と同じ: 黒の薄い地 (不透明度 0.25)、角丸 4pt。
        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        layer.cornerRadius = 4
        clipsToBounds = true
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let width = bounds.width
        guard width > 0 else { return }
        let ratio = Double(recognizer.location(in: self).x / width)
        onTapped?(min(1, max(0, ratio)))
    }

    override func draw(_ rect: CGRect) {
        guard !densities.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let width = bounds.width
        let height = bounds.height
        let binWidth = width / CGFloat(densities.count)
        for (index, density) in densities.enumerated() {
            let binStart = Double(index) * commentBinSeconds
            let inSegment = segments.contains { binStart >= $0.start && binStart < $0.end }
            // Web 版と同じ色: 区間内は不透明度 0.95、区間外は 0.30。
            UIColor(red: 230 / 255, green: 79 / 255, blue: 151 / 255,
                    alpha: inSegment ? 0.95 : 0.30).setFill()
            let barHeight = max(1, CGFloat(density) * (height - 2))
            let barRect = CGRect(
                x: CGFloat(index) * binWidth,
                y: height - barHeight,
                width: max(1, binWidth.rounded(.up)),
                height: barHeight)
            UIBezierPath(rect: barRect).fill()
        }
    }
}
