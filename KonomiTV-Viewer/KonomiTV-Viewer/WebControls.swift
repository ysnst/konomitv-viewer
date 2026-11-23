import UIKit

/// Web 版 KonomiTV の部品の形を写した、アプリ共通の操作部品。
/// iPhone 標準の部品 (UISwitch や UISegmentedControl) は形が大きく
/// 丸すぎて Web 版と見た目がそろわないため、寸法と色を Web 版の
/// 実物 (Vuetify の部品) に合わせて自前で作ったもの。
/// 形の値はすべて Web 版の実測で、根拠は各部品のコメントに書く。
/// 今後ボタンや切り替えを足すときも、形はここに集めてぶれないようにする。

// MARK: - トグル (Web 版のスイッチ)

/// 小さめで平たいレールに丸いつまみが乗る、Web 版のスイッチの形のトグル。
/// 実測 (Vuetify の v-switch、inset でない通常形、color は primary):
/// レールは幅 36px・高さ 14px で両端が半円、切のときは surface-variant
/// (#786968) の 60% の濃さ、入のときは primary (#E64F97)。
/// つまみは直径 20px の円で、レールの中心から左右 10px ずれた位置に来る
/// (切は左、入は右)。切のときのつまみは surface-bright (#786968)、
/// 入のときは明るい色 (on-surface-bright: #FFEAEA) で、影が付く。
/// 全体の大きさは 40x24 として、レールとつまみより少し広く触れるようにする。
/// 状態が変わるときは、本家のスイッチと同じく、つまみの移動とレールの
/// 色の変化を 0.2 秒かけて滑らかに行う (画面に出ていない初期設定の
/// ときは滑らせず、その場で合わせる)。
/// 使い方は UISwitch と同じで、isOn の読み書きと .valueChanged で足りる。
final class WebToggle: UIControl {
    private let railView = UIView()
    /// 押している間だけ、つまみの周りに出す薄い輪 (本家 Web 版の
    /// スイッチの押下の反応)。正体はスイッチの入力部分に付いた
    /// 中央寄せ・円形の波紋で、色はその状態の色 (入はピンク、
    /// 切は周りの文字色) の 0.25 の濃さ。動きも波紋の決まりに
    /// 合わせ、0.15 倍から 0.25 秒かけて広がり、離すと 0.3 秒で
    /// 消える (触れてから 250 ミリ秒までは消し始めない)。
    /// 切り替えは今までどおり離したときに行う (長押しでは切り替わらない)。
    private let haloView = UIView()
    private let knobView = UIView()
    /// つまみを滑らせている最中かどうか。滑らせている間に画面の
    /// 組み直しが走ると、つまみの位置が最後の場所へ跳んでしまうため、
    /// その間は組み直し側でつまみの置き場所を触らない。
    private var isKnobAnimating = false
    /// つまみの滑る動きを進めているアニメーション。途中で状態が
    /// 変わったら止めて今の位置から進め直すために持っておく。
    private var knobAnimator: UIViewPropertyAnimator?
    /// 押され始めた時刻。輪を消し始める下限 (250 ミリ秒) の判定用。
    private var pressStartedAt: TimeInterval = 0

    /// レールの幅と高さ、つまみの直径 (Web 版の実測値)。
    private static let railSize = CGSize(width: 36, height: 14)
    private static let knobDiameter: CGFloat = 20
    /// 押している間の輪の直径。本家では入力部分の大きさそのままで、
    /// 標準の場所では 40px、密度が詰まった場所 (予約カードの中)
    /// では 28px。置く場所に合わせて使う側で変えられる。
    var haloDiameter: CGFloat = 40 {
        didSet {
            haloView.layer.cornerRadius = haloDiameter / 2
            setNeedsLayout()
        }
    }
    /// つまみの中心がレールの中心からずれる量 (Web 版の実測値)。
    private static let knobTravel: CGFloat = 10

    var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            // 画面に出ているときだけ滑らせる。まだ出ていないとき
            // (初期設定で値を入れるとき) は、滑らせずその場で合わせる。
            // 以前はここで即時に合わせていたため、触ったときの滑る
            // 動きが先に上書きされて見えなくなっていた。
            refreshAppearance(animated: window != nil && bounds.width > 0)
            updateAccessibilityValue()
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.38 }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 24) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        railView.layer.cornerRadius = Self.railSize.height / 2
        railView.clipsToBounds = true
        addSubview(railView)
        // 輪はレールの上、つまみの下に置く。最初は消しておく。
        haloView.layer.cornerRadius = haloDiameter / 2
        haloView.isUserInteractionEnabled = false
        haloView.alpha = 0
        addSubview(haloView)
        knobView.layer.cornerRadius = Self.knobDiameter / 2
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOpacity = 0.25
        knobView.layer.shadowRadius = 4
        knobView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(knobView)
        isAccessibilityElement = true
        accessibilityTraits = .button
        refreshAppearance(animated: false)
        updateAccessibilityValue()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let railFrame = CGRect(
            x: (bounds.width - Self.railSize.width) / 2,
            y: (bounds.height - Self.railSize.height) / 2,
            width: Self.railSize.width, height: Self.railSize.height)
        railView.frame = railFrame
        // 滑らせている最中は、つまみの置き場所はアニメーション側に任せる。
        if !isKnobAnimating {
            knobView.frame = knobFrame(in: railFrame)
        }
        // 輪はつまみの中心に合わせる (押している間はつまみは動かない)。
        haloView.frame = CGRect(
            x: knobView.frame.midX - haloDiameter / 2,
            y: knobView.frame.midY - haloDiameter / 2,
            width: haloDiameter, height: haloDiameter)
    }

    /// いまの状態での、つまみの置き場所。
    private func knobFrame(in railFrame: CGRect) -> CGRect {
        let centerX = railFrame.midX + (isOn ? Self.knobTravel : -Self.knobTravel)
        return CGRect(
            x: centerX - Self.knobDiameter / 2,
            y: bounds.midY - Self.knobDiameter / 2,
            width: Self.knobDiameter, height: Self.knobDiameter)
    }

    private func refreshAppearance(animated: Bool) {
        // 輪の色は、その状態の色の薄いもの (滑る動きとは別に、その場で合わせる)。
        // 切のときは本家どおり、色の指定が外れて周りの文字色になる。
        haloView.backgroundColor = (isOn ? AppPalette.accent : AppPalette.text)
            .withAlphaComponent(0.25)
        let apply = { [self] in
            if isOn {
                railView.backgroundColor = AppPalette.accent
                railView.alpha = 1
                knobView.backgroundColor = AppPalette.text
            } else {
                railView.backgroundColor = AppPalette.surfaceVariant
                railView.alpha = 0.6
                knobView.backgroundColor = AppPalette.surfaceVariant
            }
            knobView.frame = knobFrame(in: railView.frame)
        }
        // 進みかけの滑る動きがあれば、今の位置で止めてから進め直す。
        if let animator = knobAnimator {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            knobAnimator = nil
        }
        if animated {
            isKnobAnimating = true
            // 緩急は本家のスイッチの決まり (cubic-bezier(0.4, 0, 0.2, 1))。
            let animator = UIViewPropertyAnimator(
                duration: 0.2,
                timingParameters: UICubicTimingParameters(
                    controlPoint1: CGPoint(x: 0.4, y: 0),
                    controlPoint2: CGPoint(x: 0.2, y: 1)))
            animator.addAnimations(apply)
            animator.addCompletion { [weak self] position in
                if position == .end {
                    self?.isKnobAnimating = false
                }
            }
            knobAnimator = animator
            animator.startAnimation()
        } else {
            isKnobAnimating = false
            apply()
        }
    }

    private func updateAccessibilityValue() {
        accessibilityValue = isOn ? "オン" : "オフ"
    }

    /// 押している間の輪を出す・消す。本家のスイッチと同じく、
    /// 押している間だけ出て、離すと消える。動きは波紋の決まりに
    /// 合わせる: 出すときは 0.15 倍から 0.25 秒かけて広がり
    /// (濃さは 0.1 秒で上がりきる)、消すときは 0.3 秒かける。
    /// ただし触れてから 250 ミリ秒までは消し始めない。
    private func setHaloVisible(_ visible: Bool) {
        if visible {
            // 輪の置き場所は、出し直す前に今のつまみの位置へ合わせ直す。
            haloView.frame = CGRect(
                x: knobView.frame.midX - haloDiameter / 2,
                y: knobView.frame.midY - haloDiameter / 2,
                width: haloDiameter, height: haloDiameter)
            haloView.transform = CGAffineTransform(scaleX: 0.15, y: 0.15)
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut]) { [weak self] in
                self?.haloView.alpha = 1
            }
            UIView.animate(
                withDuration: 0.25, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) { [weak self] in
                self?.haloView.transform = .identity
            }
        } else {
            let delay = max(0, pressStartedAt + 0.25 - CACurrentMediaTime())
            UIView.animate(
                withDuration: 0.3, delay: delay,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) { [weak self] in
                self?.haloView.alpha = 0
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isEnabled else { return }
        pressStartedAt = CACurrentMediaTime()
        setHaloVisible(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setHaloVisible(false)
        guard isEnabled,
              let touch = touches.first,
              bounds.contains(touch.location(in: self)) else { return }
        // 見た目と読み上げの更新は isOn の didSet 側で行う。
        isOn.toggle()
        sendActions(for: .valueChanged)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setHaloVisible(false)
    }
}

// MARK: - 3段階などの切り替え (Web 版のトグルボタン)

/// 横に並んだ選択肢から1つを選ぶ切り替え。Web 版の設定画面の
/// トグルボタン (v-btn-toggle) の形: 高さ 36px、角丸 4px、地は
/// background-lighten-1 (#2F221F)、選ばれている分節は secondary
/// (#E33157) で塗り、文字は 14px。分節の間には画面の地の色の
/// 1px の区切りが入る。
/// 使い方は UISegmentedControl に寄せてあり、selectedIndex の
/// 読み書きと .valueChanged で足りる。
final class WebSegmentedControl: UIControl {
    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private let stack = UIStackView()

    var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            refreshSelection()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 36)
    }

    init(items: [String]) {
        super.init(frame: .zero)
        layer.cornerRadius = 4
        clipsToBounds = true
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for (index, item) in items.enumerated() {
            if index > 0 {
                // 区切り線は等分する並びの邪魔にならないよう、重ねて描く。
                let divider = UIView()
                divider.backgroundColor = AppPalette.background
                dividers.append(divider)
                addSubview(divider)
            }
            let button = RippleButton()
            button.setTitle(item, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14)
            button.tag = index
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        refreshSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttons.isEmpty else { return }
        for (index, divider) in dividers.enumerated() {
            let x = bounds.width * CGFloat(index + 1) / CGFloat(buttons.count)
            divider.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: bounds.height)
        }
    }

    private func refreshSelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            button.backgroundColor = isSelected ? AppPalette.secondary : AppPalette.panel
            button.setTitleColor(AppPalette.text, for: .normal)
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        sendActions(for: .valueChanged)
    }
}

// MARK: - 波紋 (押したときの反応)

/// 本家 Web 版のボタン (Vuetify のボタン) の、押したときの反応を写す
/// ための入れ物。触れた位置から円が広がって薄く消える波紋を、
/// 部品の内側に描く。押したときの反応は本家では波紋だけで、
/// 押している間の重なりは無い (以前入れていた文字色 0.10 の膜は
/// 本家に定義が無いため外した)。
/// 数値は本家の波紋の定義そのまま: 濃さは 0.25 (0.1 秒で上がる)、
/// 広がる時間は 0.25 秒、最後の半径は面の対角線の半分で、出だしは
/// その 0.3 倍から。緩急は cubic-bezier(0, 0, 0.2, 1)。
/// タッチでは 80 ミリ秒待ってから出し (スクロールのつもりで
/// 触れたときにちらつかせないため)、消え始めは触れてから
/// 250 ミリ秒が下限で、消えるのに 0.3 秒かける。
/// 波紋の色は、押す部品の文字色 (text) を使う (本家も文字色で描く)。
/// 明るい地の面 (番組表の番組の枠など) では、使う側が色を差し替えられる。
final class RippleSurface {
    /// 波紋を描く入れ物。使う側の角丸に合わせて切り取る。
    let container = UIView()
    /// 波紋の色。既定は文字色 (text)。
    var color: UIColor = AppPalette.text

    /// 1回分の波紋の状態。出るまでの遅れや、消し始めの下限を
    /// 数えるために持つ。
    private final class Ripple {
        let point: CGPoint
        let startedAt: TimeInterval
        var view: UIView?
        var released = false
        var showWork: DispatchWorkItem?
        var fadeWork: DispatchWorkItem?
        init(point: CGPoint, startedAt: TimeInterval) {
            self.point = point
            self.startedAt = startedAt
        }
    }
    private var ripples: [Ripple] = []

    /// 本家の波紋の決まりの数値。
    private static let showDelay: TimeInterval = 0.08
    private static let minimumDuration: TimeInterval = 0.25
    private static let expandDuration: TimeInterval = 0.25
    private static let fadeDuration: TimeInterval = 0.3
    private static let peakOpacity: CGFloat = 0.25

    /// 本家の波紋の緩急 (cubic-bezier(0, 0, 0.2, 1))。
    private static func stockTiming() -> UITimingCurveProvider {
        UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0, y: 0),
            controlPoint2: CGPoint(x: 0.2, y: 1))
    }

    init() {
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        container.backgroundColor = .clear
    }

    /// 置き場所の大きさと角丸に合わせ直す。
    func update(bounds: CGRect, cornerRadius: CGFloat) {
        container.frame = bounds
        container.layer.cornerRadius = cornerRadius
    }

    /// 触れた位置から波紋を広げる。実際に出るのは 80 ミリ秒後で、
    /// それまでに取り消されれば出ない。
    func startRipple(at point: CGPoint) {
        let ripple = Ripple(point: point, startedAt: CACurrentMediaTime())
        ripples.append(ripple)
        let work = DispatchWorkItem { [weak self, weak ripple] in
            guard let self, let ripple else { return }
            self.show(ripple)
        }
        ripple.showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    private func show(_ ripple: Ripple) {
        let size = container.bounds.size
        guard size.width > 0, size.height > 0 else {
            ripples.removeAll { $0 === ripple }
            return
        }
        // 最後の半径は面の対角線の半分 (触れた位置にはよらない)。
        let radius = ceil(sqrt(size.width * size.width + size.height * size.height) / 2)
        guard radius > 0 else {
            ripples.removeAll { $0 === ripple }
            return
        }
        let view = UIView()
        view.backgroundColor = color
        view.layer.cornerRadius = radius
        view.frame = CGRect(
            x: ripple.point.x - radius, y: ripple.point.y - radius,
            width: radius * 2, height: radius * 2)
        view.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        container.addSubview(view)
        ripple.view = view
        let expand = UIViewPropertyAnimator(
            duration: Self.expandDuration, timingParameters: Self.stockTiming())
        expand.addAnimations { view.transform = .identity }
        expand.startAnimation()
        let fadeIn = UIViewPropertyAnimator(
            duration: 0.1, timingParameters: Self.stockTiming())
        fadeIn.addAnimations { view.alpha = Self.peakOpacity }
        fadeIn.startAnimation()
        // 出るまでの間に指が離れていたら、消す段取りを続ける。
        if ripple.released {
            scheduleFade(ripple)
        }
    }

    /// 指が離れたときに呼ぶ。波紋が出ていれば、触れてから
    /// 250 ミリ秒までは消し始めずに 0.3 秒かけて消す。
    /// まだ出ていない波紋は、予定どおり出してから消す。
    func endRipple() {
        guard let ripple = ripples.last(where: { !$0.released }) else { return }
        ripple.released = true
        scheduleFade(ripple)
    }

    /// スクロールなどで取り消されたときに呼ぶ。まだ出ていない
    /// 波紋は出さず、出ているものは指が離れたときと同じく消す。
    func cancelRipple() {
        for ripple in ripples where !ripple.released {
            ripple.released = true
            if ripple.view == nil {
                ripple.showWork?.cancel()
                ripple.showWork = nil
            } else {
                scheduleFade(ripple)
            }
        }
        ripples.removeAll { $0.released && $0.view == nil }
    }

    private func scheduleFade(_ ripple: Ripple) {
        guard ripple.released, ripple.view != nil, ripple.fadeWork == nil else { return }
        let delay = max(0, ripple.startedAt + Self.minimumDuration - CACurrentMediaTime())
        let work = DispatchWorkItem { [weak self, weak ripple] in
            guard let ripple, let view = ripple.view else { return }
            let animator = UIViewPropertyAnimator(
                duration: Self.fadeDuration, timingParameters: Self.stockTiming())
            animator.addAnimations { view.alpha = 0 }
            animator.addCompletion { [weak self] _ in
                view.removeFromSuperview()
                self?.ripples.removeAll { $0 === ripple }
            }
            animator.startAnimation()
        }
        ripple.fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// 波紋の反応を持つボタン。色・形・高さは今までどおり呼び出し側の
/// 形付けで決め、この部品は押したときの動きだけを足す。
/// 波紋の入れ物は文字や絵より下に置く。
final class RippleButton: UIButton {
    private let ripple = RippleSurface()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ripple.container.frame = bounds
        ripple.container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(ripple.container, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: bounds, cornerRadius: effectiveRippleCornerRadius)
        // 文字や絵が後から足されて入れ物が上に出ていたら、下に戻す。
        if subviews.first !== ripple.container {
            insertSubview(ripple.container, at: 0)
        }
    }

    /// 波紋を切り取る角丸。呼び出し側が角丸を付けていればそのまま使う。
    /// 角丸が無く、正方形に近い小さなボタン (再生画面の絵だけのボタン
    /// など) は、本家の絵のボタンと同じく丸い波紋にする。地が透明な
    /// ボタンでは、この角丸は波紋の切り取りにだけ効き、見た目の形は
    /// 変えない。
    private var effectiveRippleCornerRadius: CGFloat {
        if layer.cornerRadius > 0 { return layer.cornerRadius }
        let size = bounds.size
        if size.width > 0, size.width <= 64, abs(size.width - size.height) <= 2 {
            return size.width / 2
        }
        return 0
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let tracking = super.beginTracking(touch, with: event)
        if tracking, isEnabled {
            ripple.startRipple(at: touch.location(in: self))
        }
        return tracking
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        ripple.endRipple()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        ripple.cancelRipple()
    }
}

/// ボタンではない面 (カードやロゴのタップの受け口など) に波紋を付ける
/// ための土台。面そのものがタッチを受け、触れた位置から波紋を広げる。
/// 行き先の処理は、使う側が付けるタップのしぐさ
/// (UITapGestureRecognizer) 側で行う (この土台は見た目の反応だけを持つ)。
/// しぐさがタップを確定させると、こちらには触れた指が離れた代わりに
/// 「取り消し」が届くため、両方を「指が離れた」と同じ扱いにする。
/// 触れたまま大きく動いたとき (スクロール) は、まだ出ていない
/// 波紋を取り消す。
class RippleSurfaceView: UIView {
    /// 波紋の入れ物。使う側で色と角丸を合わせられる。
    let ripple = RippleSurface()
    /// 波紋を切り取る角丸 (面の角丸に合わせる)。
    var rippleCornerRadius: CGFloat = 0
    /// 触れ始めた位置。大きく動いたらスクロールとみなす判定用。
    private var touchStartPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        ripple.container.frame = bounds
        ripple.container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(ripple.container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: bounds, cornerRadius: rippleCornerRadius)
        // 波紋は中身の上に重ねて描く (半透明で、中身の邪魔はしない)。
        if subviews.last !== ripple.container {
            bringSubviewToFront(ripple.container)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        touchStartPoint = point
        ripple.startRipple(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let start = touchStartPoint, let touch = touches.first else { return }
        let point = touch.location(in: self)
        // 10pt 以上動いたらスクロールのつもりとみなし、まだ出ていない
        // 波紋は出さない (本家の「動かしたら出さない」と同じ考え方)。
        if hypot(point.x - start.x, point.y - start.y) > 10 {
            touchStartPoint = nil
            ripple.cancelRipple()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchStartPoint = nil
        ripple.endRipple()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchStartPoint = nil
        ripple.endRipple()
    }
}

// MARK: - 番組表の操作帯のボタンの形

extension UIButton {
    /// 番組表の操作帯の文字ボタン (種別・日付・時刻) の形。
    /// Web 版のスマホ用コントロールの実測: 高さ 36px、角丸 6px、
    /// 地は background-lighten-1。枠線は呼び出し側で色だけ決める
    /// (選択欄は on-surface の 38%、日付ボタンは 26%)。
    func styleAsTimeTableBarTextButton(borderColor: UIColor) {
        backgroundColor = AppPalette.panel
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor
        titleLabel?.font = .systemFont(ofSize: 14)
        setTitleColor(AppPalette.text, for: .normal)
        tintColor = AppPalette.text
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    /// 番組表の操作帯の絵のボタン (現在時刻・表示設定) の形。
    /// Web 版のスマホ用コントロールの実測: 34x34px、角丸 6px、
    /// 地は background-lighten-2、枠線なし、絵は 18px。
    func styleAsTimeTableBarIconButton() {
        backgroundColor = AppPalette.pressed
        layer.cornerRadius = 6
        layer.borderWidth = 0
        tintColor = AppPalette.text
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
}
