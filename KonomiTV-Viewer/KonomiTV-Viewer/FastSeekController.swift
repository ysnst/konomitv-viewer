import UIKit

/// 送り・戻しボタンの長押しによる高速シーク (Web 版 SeekControlManager の写し)。
///
/// 長押し (480ミリ秒以上) が始まったら、0.25秒ごとに2秒ずつ移動し続ける
/// (8倍相当)。その間は音を消し、離したら止めて音を元に戻す。
/// 短い押しは通常のスキップ (ボタンの本来の操作) に任せるため、
/// 長押しの判定にはタッチを打ち切るジェスチャー認識を使い、
/// 長押しになった押しでは通常のスキップが発動しないようにしている。
/// 移動・再生位置・音の操作は、再生の仕組みごとに違うため呼び出し側へ委ねる。
final class FastSeekController {
    /// 高速シークとみなす長押し時間 (秒)。Web 版の 480ミリ秒と同じ。
    private static let holdThresholdSeconds = 0.48
    /// 高速シークの移動間隔 (秒)。
    private static let fastSeekIntervalSeconds = 0.25
    /// 1回あたりの移動量 (秒)。0.25秒ごとに2秒 = 8倍相当。
    private static let fastSeekStepSeconds: Double = 2

    /// 現在の再生位置 (秒) を返す口。
    var positionProvider: (() -> Double)?
    /// 指定した位置 (秒) へ移動する口。
    var seekHandler: ((Double) -> Void)?
    /// いま音が消えているかどうかを読む口。
    var isMutedProvider: (() -> Bool)?
    /// 音の消去・復帰を行う口 (引数が true で消す)。
    var setMutedHandler: ((Bool) -> Void)?
    /// 高速シークが始まったときの知らせ先 (引数は方向: 1 = 早送り、-1 = 巻き戻し)。
    var onStart: ((Int) -> Void)?
    /// 操作帯を消さずに出し続けるための知らせ先 (開始時に呼ぶ)。
    var onKeepControlsVisible: (() -> Void)?
    /// 高速シークが終わったときの知らせ先 (離したときに呼ぶ)。
    var onEnd: (() -> Void)?

    private let direction: Int
    private var timer: Timer?
    private var isFastSeeking = false
    private var wasMutedBefore = false

    /// - Parameter direction: 1 = 早送り、-1 = 巻き戻し。
    init(direction: Int) {
        self.direction = direction
    }

    deinit {
        // 呼び出し側が片付けを忘れても、タイマーが残り続けないための受け口。
        // 音を消したまま終わらないよう、高速シーク中なら音も元に戻す。
        timer?.invalidate()
        if isFastSeeking {
            setMutedHandler?(wasMutedBefore)
        }
    }

    /// ボタンへ長押しの判定を取り付ける。
    func attach(to button: UIButton) {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = Self.holdThresholdSeconds
        button.addGestureRecognizer(recognizer)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            start()
        case .ended, .cancelled, .failed:
            stop()
        default:
            break
        }
    }

    /// 高速シークを始める (音を消し、まず1回分移動してから一定間隔で繰り返す)。
    private func start() {
        guard !isFastSeeking else { return }
        isFastSeeking = true
        wasMutedBefore = isMutedProvider?() ?? false
        setMutedHandler?(true)
        onStart?(direction)
        onKeepControlsVisible?()
        applyStep()
        timer = Timer.scheduledTimer(withTimeInterval: Self.fastSeekIntervalSeconds, repeats: true) { [weak self] _ in
            self?.applyStep()
        }
    }

    /// 高速シークを終え、音を元に戻す。
    private func stop() {
        timer?.invalidate()
        timer = nil
        guard isFastSeeking else { return }
        isFastSeeking = false
        setMutedHandler?(wasMutedBefore)
        onEnd?()
    }

    /// 1回分の移動 (範囲の端では呼び出し側の移動が端で止める)。
    private func applyStep() {
        guard let position = positionProvider?(), position.isFinite else { return }
        seekHandler?(position + Double(direction) * Self.fastSeekStepSeconds)
    }

    /// 画面を離れるときなどに、タイマーと音の状態を片付ける。
    func invalidate() {
        stop()
    }
}
