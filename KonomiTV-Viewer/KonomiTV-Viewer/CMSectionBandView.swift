import UIKit

/// シークバーの上に CM 区間の帯を重ねて描く部品。
/// Web 版 KonomiTV のシークバーの CM 帯と同じ考え方で、帯自体は操作を受けず、
/// シーク操作は下にあるスライダーがそのまま受ける。
final class CMSectionBandView: UIView {
    /// 位置合わせの基準にするスライダー (トラックの矩形を借りる)。
    weak var slider: UISlider?
    /// CM 区間の一覧。空なら何も描かない。
    var sections: [CMSection] = [] {
        didSet { setNeedsDisplay() }
    }
    /// バーの全体の長さ (秒)。0 以下なら何も描かない。
    var duration: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    /// 帯の色。控えめだが暗いバーの上でも判別できる濃さにする。
    private let bandColor = UIColor(red: 0.85, green: 0.35, blue: 0.50, alpha: 0.55)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let slider, duration > 0, !sections.isEmpty else { return }
        let track = slider.trackRect(forBounds: slider.bounds)
        guard track.width > 0 else { return }
        // 表示の高さも実トラックに合わせ、区間表示のために太い帯を作らない。
        let bandHeight = track.height
        let y = track.midY - bandHeight / 2
        bandColor.setFill()
        for section in sections {
            let start = max(0, min(section.start_time, duration))
            let end = max(0, min(section.end_time, duration))
            guard end > start else { continue }
            let x0 = track.minX + CGFloat(start / duration) * track.width
            let x1 = track.minX + CGFloat(end / duration) * track.width
            let bandRect = CGRect(x: x0, y: y, width: max(2, x1 - x0), height: bandHeight)
            UIBezierPath(roundedRect: bandRect, cornerRadius: 2).fill()
        }
    }
}
