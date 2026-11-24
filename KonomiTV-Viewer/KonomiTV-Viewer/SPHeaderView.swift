import UIKit

/// Web 版クライアントのスマホ縦画面で各ページの上部に出るヘッダー
/// (client/src/components/SPHeaderBar.vue) を写したもの。
/// 実測値 (スマホ縦): 高さ 48px (上に 14px の余白を含む)、左右の余白 16px、
/// 地の色はテーマの background (AppPalette.background)。
/// 中身は左端の KonomiTV ロゴだけで、ページ名の文字は出ない。
/// Web 版では右端に検索ボタンも出るが、この共通部品には置いていない
/// (録画一覧だけ、画面側でロゴ帯に重ねて検索の入り口を足している)。
/// ロゴは Web 版ではテレビ画面 (/tv/) へのリンクなので、タップで生放送タブへ移る。
final class SPHeaderView: UIView {
    /// Web 版の .header の高さ (48px)。表示の大きさに合わせて拡縮する
    /// (ロゴ自体の大きさは Web 版の指定どおり 21px のまま)。
    static var height: CGFloat { UIScale.value(48) }

    /// ロゴがタップされたときの動作。呼び出し側 (各一覧画面) が生放送タブへの
    /// 切り替えを入れる。
    var onLogoTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppPalette.background

        // ロゴの絵は Web 版の公式ロゴ (public/assets/images/logo.svg) そのもの。
        // Assets.xcassets の konomitv_logo.imageset に取り込んである。
        // ロゴ自体に色が付いているため、Fluent アイコンのような template 指定はしない。
        let logoView = UIImageView(image: UIImage(named: "konomitv_logo"))
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false

        // タップの受け口。Web 版のリンクの余白 (上下 12px、左右 8px) ぶんだけ
        // ロゴより広く取る。押したときの反応として、共通部品の波紋を出す
        // (行き先の処理は付けられたタップのしぐさ側で行う)。
        let logoTapArea = RippleSurfaceView()
        logoTapArea.translatesAutoresizingMaskIntoConstraints = false
        logoTapArea.isUserInteractionEnabled = true
        logoTapArea.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(logoTapped)))
        logoTapArea.addSubview(logoView)
        addSubview(logoTapArea)

        // ロゴの大きさは Web 版の指定どおり高さ 21px。
        // 幅は原画の縦横比 (viewBox 1256.394 x 186.177) から 21 * 1256.394 / 186.177 ≒ 141.7px。
        // 左端の位置は、ヘッダーの余白 16px − リンクのはみ出し 6px + リンクの余白 8px = 18px。
        // 縦位置は、上 14px の余白を除いた残り 34px の中央 (上端から 31px) に
        // ロゴの中央が来る (Web 版は align-items: center)。
        NSLayoutConstraint.activate([
            logoTapArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            logoTapArea.centerYAnchor.constraint(equalTo: topAnchor, constant: 31),
            logoTapArea.widthAnchor.constraint(equalToConstant: 141.7 + 16),
            logoTapArea.heightAnchor.constraint(equalToConstant: 21 + 24),
            logoView.centerXAnchor.constraint(equalTo: logoTapArea.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: logoTapArea.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 141.7),
            logoView.heightAnchor.constraint(equalToConstant: 21),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func logoTapped() {
        onLogoTap?()
    }
}
