import UIKit

/// 高速シーク中の消音の持ち主を一元化する置き場。送りと戻しの
/// 2つの操作が同時に進んでも、音の状態が壊れないようにするためのもの。
///
/// 以前は操作ごとに「消音前の状態」を別々に控えていたため、元が
/// 非消音のときに、戻し開始→送り開始→戻し終了→送り終了の順になると、
/// 最後に送り側の控え (消音) が戻されて、消音が残ってしまっていた。
/// ここでは、最初に持ち始めた操作が消音前の状態を控えて消音し、
/// 最後の操作が手放したときにだけ元へ戻す。
final class FastSeekMuteKeeper {
    /// いま音が消えているかどうかを読む口。
    var isMutedProvider: (() -> Bool)?
    /// 音の消去・復帰を行う口 (引数が true で消す)。
    var setMutedHandler: ((Bool) -> Void)?

    /// 消音を持っている操作の数。
    private var holderCount = 0
    /// 最初の操作が持ち始める直前の、音が消えていたかどうか。
    private var wasMutedBefore = false

    /// 消音を持ち始める。最初の1つだけが、状態を控えて実際に消音する。
    func acquire() {
        if holderCount == 0 {
            wasMutedBefore = isMutedProvider?() ?? false
            setMutedHandler?(true)
        }
        holderCount += 1
    }

    /// 消音を手放す。最後の1つが手放したときにだけ、控えた状態へ戻す。
    func release() {
        guard holderCount > 0 else { return }
        holderCount -= 1
        if holderCount == 0 {
            setMutedHandler?(wasMutedBefore)
        }
    }
}

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
    /// 消音の持ち主 (muteKeeper) を使うときは、そちら側に付ける。
    var isMutedProvider: (() -> Bool)?
    /// 音の消去・復帰を行う口 (引数が true で消す)。
    /// 消音の持ち主 (muteKeeper) を使うときは、そちら側に付ける。
    var setMutedHandler: ((Bool) -> Void)?
    /// 消音の持ち主。送りと戻しで同じものを共有すると、同時に
    /// 長押ししても消音が残らなくなる。付けないときは、この操作
    /// だけで消音前の状態を控えて出し入れする (従来の動き)。
    var muteKeeper: FastSeekMuteKeeper?
    /// 高速シークが始まったときの知らせ先 (引数は方向: 1 = 早送り、-1 = 巻き戻し)。
    var onStart: ((Int) -> Void)?
    /// 操作帯を消さずに出し続けるための知らせ先 (開始時に呼ぶ)。
    var onKeepControlsVisible: (() -> Void)?
    /// 高速シークが終わったときの知らせ先 (離したときに呼ぶ)。
    var onEnd: (() -> Void)?

    private let direction: Int
    private var timer: Timer?
    // 操作帯の持ち主は両方向の終了を確認する。開始・終了の変更はこのクラスだけが行う。
    private(set) var isFastSeeking = false
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
            releaseMute()
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

    /// 消音を持ち始める。持ち主がいればそちらへ任せ、いなければ
    /// この操作だけで消音前の状態を控えて消音する。
    private func acquireMute() {
        if let muteKeeper {
            muteKeeper.acquire()
        } else {
            wasMutedBefore = isMutedProvider?() ?? false
            setMutedHandler?(true)
        }
    }

    /// 消音を手放す。持ち主がいればそちらへ任せ、いなければ
    /// 控えた状態へ戻す。
    private func releaseMute() {
        if let muteKeeper {
            muteKeeper.release()
        } else {
            setMutedHandler?(wasMutedBefore)
        }
    }

    /// 高速シークを始める (音を消し、まず1回分移動してから一定間隔で繰り返す)。
    private func start() {
        guard !isFastSeeking else { return }
        isFastSeeking = true
        acquireMute()
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
        releaseMute()
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
