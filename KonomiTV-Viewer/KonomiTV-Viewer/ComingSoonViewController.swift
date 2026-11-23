import UIKit

/// まだ中身が無い画面の受け皿。マイページ化の第1回では、マイリスト・
/// 視聴履歴・アカウント設定の行き先として使う (中身は第4回以降)。
/// 空の画面や壊れた遷移にせず、「準備中」と分かる表示だけを出す。
/// ナビゲーションバーは出したままにし、戻るボタンで戻れるようにする。
final class ComingSoonViewController: UIViewController {
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        let label = UILabel()
        label.text = "準備中です"
        label.font = .systemFont(ofSize: 16)
        label.textColor = AppPalette.metaText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
