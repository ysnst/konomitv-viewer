import UIKit

/// なぞり選択専用の指の動きの受け口 (ゴミ箱・録画一覧で共用)。
///
/// なぞり選択の始め方の判定を、受け口が始まる前に済ませるための
/// もの。項目の上で指を少し (0.25秒ほど) 止めてから動き出した
/// ときだけ、なぞり選択として取り込む。止まらずにそのまま動かした
/// ドラッグは、速さによらず全部スクロールとして扱い、受け口を
/// 失敗で終わらせる (失敗を待っていた一覧のスクロールが始められる)。
/// 止めている間は指の動きを親に渡さず手元に留めるが、その間は指が
/// ほとんど動いていないので、一覧のスクロールはこの受け口が
/// 失敗するか始まるかするまで始めないよう頼んであっても
/// (require(toFail:))、決まった瞬間に一覧の位置が跳ぶことはない。
/// 以前は「指が少し動くまでの速さ」で判定していたが、中くらいの
/// 速さのドラッグが選択側に倒れてしまい、選択中に眺めるための
/// スクロールがしにくかったため、止めたかどうかで決める形に変えた。
final class DragSelectionPanGestureRecognizer: UIPanGestureRecognizer {
    /// なぞり選択として取り込むまでに、指を止めておく時間。
    private static let holdDuration: TimeInterval = 0.25
    /// 止めている間に指がこれ以上動いたら、止めたとはみなさず
    /// スクロールとして扱う移動量。
    private static let holdSlop: CGFloat = 10

    /// 指が触れた位置 (受け口の付いている画面での座標)。
    /// 判定で受け口が始まる頃には指が少し動いているため、なぞり
    /// 選択の起点には、現在の位置ではなく この位置を使う。
    private(set) var startLocation: CGPoint = .zero
    /// 指が触れた時刻 (判定に使う、タッチの時刻)。
    private var startTime: TimeInterval = 0
    /// 判定が出たかどうか。
    private var decided = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        decided = false
        if let touch = touches.first, let view {
            startLocation = touch.location(in: view)
            startTime = touch.timestamp
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if decided {
            super.touchesMoved(touches, with: event)
            return
        }
        guard let touch = touches.first, let view else {
            super.touchesMoved(touches, with: event)
            return
        }
        let point = touch.location(in: view)
        if touch.timestamp - startTime >= Self.holdDuration {
            // 少し止めてから動き出した。なぞり選択として取り込む。
            decided = true
            super.touchesMoved(touches, with: event)
            return
        }
        let distance = hypot(
            point.x - startLocation.x, point.y - startLocation.y)
        if distance >= Self.holdSlop {
            // 止まらずに動き出したドラッグは、速さによらず
            // スクロール。受け口を失敗で終わらせる。
            decided = true
            state = .failed
            return
        }
        // まだ止めている最中。親に渡さないので、受け口は始まらない。
    }

    override func reset() {
        super.reset()
        decided = false
    }
}

/// ゴミ箱の画面。録画一覧の「ゴミ箱を開く」から開く (拡張版だけ)。
///
/// 本家 Web 版のゴミ箱 (views/Videos/Trash.vue) と同じ作り:
/// - 中身は GET /recorder/trash で取る。並びは見出し右のボタンで
///   切り替えられ (録画が新しい順・古い順・削除が近い順・遠い順)、
///   既定は録画が新しい順。並び替えは表示の写しにだけ効かせ、
///   取得した元の並びは変えない。並び順は開くたびに既定に戻る。
/// - 管理者は「選択する」から複数選択に入れ、選んだ分をまとめて
///   復元・完全削除できる。まとめて削除も1件のときと同じ流儀で、
///   確認を挟み、項目ごとに事前確認を取ってから削除する。
///   選択中は、カードの上で指を少し止めてから動かすと、通った
///   カードを連続で選べる (なぞって選択)。止めずにそのまま
///   動かしたドラッグは、速さによらずスクロールになる。
/// - 一覧の先頭に保持期間の説明を出し (一覧と一緒にスクロール
///   する)、各カードには録画一覧と同じカード部品 (VideoCell) に
///   「あと○日で完全に削除されます」の行と、「復元する」
///   「完全に削除」のボタンの行を足して出す。
/// - 操作ボタンは Web 版と同じく管理者だけに出す (一覧自体は
///   ログインしていれば見られる)。
/// - 完全削除は取り返しがつかないため、Web 版と同じ手順で
///   事前確認 (delete-preview) を取ってから確認を出し、確認用の
///   合言葉を付けて削除する。
/// - カードを押しても再生画面へは移らない (Web 版のゴミ箱の行にも
///   再生へのリンクは無い)。
///
/// 見出し帯は設定まわりの画面・視聴履歴と同じ形: 高さ 60px・地は
/// background-lighten-1、左端は矢印だけの戻るボタン、ページ名 22px。
/// 端からの横スワイプでも戻れる。
final class TrashViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    /// 並び順 (Web 版のゴミ箱の並び替えと同じ4通り)。
    /// 既定は「録画が新しい順」で、画面を開くたびに既定に戻る
    /// (端末への保存はしない。Web 版と同じ)。
    private enum SortKind: CaseIterable {
        case newest
        case oldest
        case purgeNear
        case purgeFar

        var title: String {
            switch self {
            case .newest: return "録画が新しい順"
            case .oldest: return "録画が古い順"
            case .purgeNear: return "削除が近い順"
            case .purgeFar: return "削除が遠い順"
            }
        }
    }

    private let backButton = RippleButton()
    /// 見出し帯。一覧まわりはこの帯の下端に留めて組むため保持する。
    private let headingBar = UIView()
    /// 並び替えのボタン (見出しの右。Web 版のプルダウンに相当)。
    private let sortButton = RippleButton()
    /// 「選択する」のピルの行 (見出し帯の下、右寄せ)。
    private let selectRowView = UIView()
    private let selectButton = RippleButton()
    private var selectRowHeightConstraint: NSLayoutConstraint?
    /// 保持期間の説明 (Web 版の見出し下の説明と同じ文面)。
    /// 一覧の先頭に置いて、一覧と一緒にスクロールさせる
    /// (以前は一覧の上に固定していたため、スクロールすると
    /// カードが説明文の下に滑り込んで、文字と重なって見えた)。
    private let noteLabel = UILabel()
    /// 説明文を一覧の先頭に載せるための入れ物。
    private let noteContainerView = UIView()
    /// 説明文の入れ物の高さを合わせたときの一覧の幅。
    /// 幅が変わったら合わせ直すために持つ。
    private var noteHeaderWidth: CGFloat = 0
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()
    /// 選択中の下部に固定で出す操作帯とその中身。
    private let bulkBar = UIView()
    private let bulkCountLabel = UILabel()
    private let bulkSelectAllButton = RippleButton()
    private let bulkClearButton = RippleButton()
    private let bulkRestoreButton = RippleButton()
    private let bulkDeleteButton = RippleButton()
    /// 操作帯の高さ (2段組み)。
    private static let bulkBarHeight: CGFloat = 104

    /// ゴミ箱の中身 (サーバーから返った並びのまま)。
    private var items: [TrashItem] = []
    /// 表示用の並び (並び替えを適用した写し。元の並びは変えない)。
    private var displayItems: [TrashItem] = []
    /// いまの並び順。
    private var sortKind: SortKind = .newest
    /// 複数選択の状態 (この画面の中だけに持ち、保存はしない)。
    private var isSelectionMode = false
    private var selectedIDs: Set<Int> = []
    /// なぞって選択の途中経過。選択中にカードへ触れたまま指を動かした
    /// とき、触れた行を起点に範囲で選択を付け外しするための控え。
    private var dragAnchorRow: Int?
    /// なぞり始めた行が未選択なら選択に、選択済みなら解除にそろえる。
    private var dragSelecting = true
    /// いま指の範囲に入っている項目 (番組 id)。
    private var dragRangeIDs: Set<Int> = []
    /// なぞり始める前に各項目が選択されていたかどうか。範囲から
    /// 外れたときに、なぞる前の状態へ戻すために持つ。
    private var dragBaseline: [Int: Bool] = [:]
    /// なぞり選択専用の指の動きの受け口。選択中だけ有効にし、
    /// 選択中でないときは一覧のスクロールに一切触れない (有効なまま
    /// だと、選択中でないときでも受け口が指の動きを横取りして、
    /// 普通のスクロールができなくなった)。
    /// スクロールか なぞり選択かの判定は受け口の中で済ませる
    /// (DragSelectionPanGestureRecognizer を参照)。指を少し
    /// 止めてから動かしたときだけ受け口が始まり、ここに来たものは
    /// なぞり選択として取り込む。止めずに動かしたドラッグは
    /// 受け口が失敗してスクロールになる。一覧のスクロールは、
    /// 受け口が失敗するまで始めないよう頼んであるが、判定の間は
    /// 指がほとんど動いていないので、決まった瞬間に一覧の位置が
    /// 跳ぶこともない。
    private let dragSelectionGesture = DragSelectionPanGestureRecognizer()
    /// この指の動きをなぞり選択として取り込んだかどうか。
    private var dragCommitted = false
    /// 指の位置 (画面全体での座標)。端に近いかの判定に使う。
    private var dragFingerPoint: CGPoint?
    /// 端での自動スクロールが、いま効いている向き (-1 = 上へ、
    /// 1 = 下へ、0 = 止まっている)。端の境目から少し外れるまで
    /// 向きを保ち、境目での入ったり止まったりの繰り返しで
    /// 小刻みに跳ねて見えないようにする。
    private var dragAutoScrollDirection = 0
    /// 端の境目から、向きを保つ幅。
    private static let dragEdgeHysteresis: CGFloat = 16
    /// 端での自動スクロールを進めるための、表示の刻み。
    private var dragScrollLink: CADisplayLink?
    private var dragScrollLastTime: CFTimeInterval = 0
    /// 自動スクロールが効く端の幅と、端に指があるときの速さの
    /// 上限 (1秒あたり)。指が端を超えて外側にあるときは、上限の
    /// 1.5倍までもう一段速くなる (dragScrollSpeed(forDepth:))。
    private static let dragEdgeLength: CGFloat = 72
    private static let dragMaxScrollSpeed: CGFloat = 420
    /// なぞり選択の最中かどうか。
    private var isDragSelecting: Bool { dragAnchorRow != nil }
    /// まとめて操作の実行中かどうか (二重実行の防止)。
    private var isBulkRunning = false
    /// 保持期間 (日)。取得前はサーバーの既定値 30 で仮置きし、
    /// 取得できたら実際の値で説明を出し直す。
    private var retentionDays = 30
    /// ログイン中の利用者が管理者かどうか (操作ボタンの出し分け)。
    private var isAdminUser = false
    private var isLoading = false

    private let thumbnailCache = NSCache<NSNumber, UIImage>()
    /// サムネイルを取得中の番組 ID と、失敗して取り直し待ちの番組 ID。
    /// 同じ番組への取得を重ねないことと、失敗したままにしないために使う。
    private var thumbnailLoadingIDs: Set<Int> = []
    private var thumbnailRetryingIDs: Set<Int> = []
    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (録画一覧と同じ方式)。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "ゴミ箱"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildHeadingBar()
        buildSelectRow()
        buildBulkBar()

        noteLabel.font = .scaledSystemFont(ofSize: 13.5)
        noteLabel.textColor = AppPalette.text.withAlphaComponent(0.8)
        noteLabel.numberOfLines = 0
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteContainerView.addSubview(noteLabel)
        NSLayoutConstraint.activate([
            noteLabel.topAnchor.constraint(
                equalTo: noteContainerView.topAnchor, constant: 10),
            noteLabel.leadingAnchor.constraint(
                equalTo: noteContainerView.leadingAnchor, constant: 16),
            noteLabel.trailingAnchor.constraint(
                equalTo: noteContainerView.trailingAnchor, constant: -16),
            noteLabel.bottomAnchor.constraint(
                equalTo: noteContainerView.bottomAnchor, constant: -6),
        ])

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 125
        tableView.backgroundColor = AppPalette.background
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        // 選択中になぞって連続で選べるよう、なぞり選択専用の
        // 指の動きの受け口を付ける。選択中だけ有効にし、それ以外
        // では一覧のスクロールに触れない。スクロールか なぞり
        // 選択かの判定は受け口の中で済ませ、一覧のスクロールは
        // 受け口が失敗するまで始めない (判定が出るまで一覧は
        // 動かない。handleDragSelection を参照)。
        dragSelectionGesture.addTarget(
            self, action: #selector(handleDragSelection(_:)))
        dragSelectionGesture.delegate = self
        dragSelectionGesture.isEnabled = false
        tableView.addGestureRecognizer(dragSelectionGesture)
        tableView.panGestureRecognizer.require(toFail: dragSelectionGesture)
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: selectRowView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 一覧の幅が変わったら、説明文の入れ物の高さを合わせ直す。
        if tableView.bounds.width != noteHeaderWidth {
            layoutNoteHeader()
        }
    }

    /// 説明文を一覧の先頭 (一緒にスクロールする側) へ載せる。
    /// 文が変わったときと、一覧の幅が変わったときに呼ぶ。
    /// 文が無いときは高さを 0 にして、先頭を詰める。
    private func layoutNoteHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        noteHeaderWidth = width
        if (noteLabel.text ?? "").isEmpty {
            noteContainerView.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        } else {
            let size = noteContainerView.systemLayoutSizeFitting(
                CGSize(width: width,
                       height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel)
            noteContainerView.frame = CGRect(
                x: 0, y: 0, width: width, height: size.height)
        }
        tableView.tableHeaderView = noteContainerView
    }

    /// 見出し帯 (設定まわりの画面・視聴履歴と同じ形)。
    private func buildHeadingBar() {
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = "ゴミ箱"
        headingLabel.font = .scaledSystemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        // 並び替えのボタンは見出しの右に置く (Web 版のプルダウンと同じ
        // 置き場所)。いまの並び順の名前を出し、押すとメニューが開く。
        sortButton.setTitleColor(AppPalette.text, for: .normal)
        sortButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        sortButton.backgroundColor = AppPalette.pressed
        sortButton.layer.cornerRadius = 6
        sortButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 8)
        sortButton.setImage(
            UIImage(systemName: "chevron.down",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        // 絵は文字の右に置く (プルダウンの見た目に合わせる)。
        sortButton.semanticContentAttribute = .forceRightToLeft
        sortButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(sortButton)
        view.addSubview(headingBar)
        NSLayoutConstraint.activate([
            headingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headingBar.heightAnchor.constraint(equalToConstant: 60),
            headingStack.leadingAnchor.constraint(equalTo: headingBar.leadingAnchor, constant: 8),
            headingStack.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: sortButton.leadingAnchor, constant: -8),
            sortButton.trailingAnchor.constraint(equalTo: headingBar.trailingAnchor, constant: -12),
            sortButton.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
        ])
        updateSortButton()
        // 画面の左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    /// 並び替えボタンの表示 (題名とメニュー) をいまの並び順に合わせる。
    private func updateSortButton() {
        sortButton.setTitle(sortKind.title, for: .normal)
        sortButton.menu = UIMenu(children: SortKind.allCases.map { kind in
            UIAction(title: kind.title, state: kind == sortKind ? .on : .off) { [weak self] _ in
                guard let self, kind != self.sortKind else { return }
                self.sortKind = kind
                self.updateSortButton()
                self.applyItems()
            }
        })
    }

    /// 「選択する」のピルの行を作る。管理者で、ゴミ箱が空でない
    /// ときだけ出す (出し分けは updateControlsVisibility)。
    private func buildSelectRow() {
        selectRowView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectRowView)
        selectButton.setTitle("選択する", for: .normal)
        selectButton.setTitleColor(AppPalette.text, for: .normal)
        selectButton.titleLabel?.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        selectButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        selectButton.layer.cornerRadius = 15
        selectButton.layer.borderWidth = 1
        selectButton.layer.borderColor = AppPalette.fieldBorder.cgColor
        selectButton.addTarget(self, action: #selector(toggleSelectionMode), for: .touchUpInside)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectRowView.addSubview(selectButton)
        selectRowHeightConstraint = selectRowView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            selectRowView.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
            selectRowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectRowView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectRowHeightConstraint!,
            selectButton.trailingAnchor.constraint(equalTo: selectRowView.trailingAnchor, constant: -16),
            selectButton.centerYAnchor.constraint(equalTo: selectRowView.centerYAnchor),
        ])
        selectRowView.isHidden = true
    }

    /// 選択中の操作帯を作る (画面の下部に固定、タブバーの上)。
    /// 並びは Web 版と同じ: 選んだ件数・すべて選択・選択を解除・
    /// 復元する・完全に削除。幅の都合で2段に分ける。
    private func buildBulkBar() {
        bulkBar.backgroundColor = AppPalette.panel
        bulkBar.translatesAutoresizingMaskIntoConstraints = false
        bulkBar.isHidden = true
        let topBorder = UIView()
        topBorder.backgroundColor = AppPalette.pressed
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        bulkBar.addSubview(topBorder)

        bulkCountLabel.font = .scaledSystemFont(ofSize: 13.5, weight: .semibold)
        bulkCountLabel.textColor = AppPalette.text
        bulkSelectAllButton.setTitle("すべて選択", for: .normal)
        bulkClearButton.setTitle("選択を解除", for: .normal)
        for button in [bulkSelectAllButton, bulkClearButton] {
            button.setTitleColor(AppPalette.text, for: .normal)
            button.titleLabel?.font = .scaledSystemFont(ofSize: 13)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        }
        bulkSelectAllButton.addTarget(self, action: #selector(selectAllItems), for: .touchUpInside)
        bulkClearButton.addTarget(self, action: #selector(clearSelection), for: .touchUpInside)
        // 復元・完全削除の見た目は、カードのボタンと揃える。
        bulkRestoreButton.setTitle("復元する", for: .normal)
        bulkRestoreButton.setTitleColor(AppPalette.text, for: .normal)
        bulkRestoreButton.titleLabel?.font = .scaledSystemFont(ofSize: 13.5, weight: .semibold)
        bulkRestoreButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        bulkRestoreButton.layer.cornerRadius = 4
        bulkRestoreButton.layer.borderWidth = 1
        bulkRestoreButton.layer.borderColor = AppPalette.fieldBorder.cgColor
        bulkRestoreButton.addTarget(self, action: #selector(bulkRestore), for: .touchUpInside)
        bulkDeleteButton.setTitle("完全に削除", for: .normal)
        bulkDeleteButton.setTitleColor(.white, for: .normal)
        bulkDeleteButton.titleLabel?.font = .scaledSystemFont(ofSize: 13.5, weight: .semibold)
        bulkDeleteButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        bulkDeleteButton.layer.cornerRadius = 4
        bulkDeleteButton.backgroundColor = AppPalette.error
        bulkDeleteButton.addTarget(self, action: #selector(bulkDelete), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [
            bulkCountLabel, UIView(), bulkSelectAllButton, bulkClearButton,
        ])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 4
        let bottomRow = UIStackView(arrangedSubviews: [
            UIView(), bulkRestoreButton, bulkDeleteButton,
        ])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = 8
        let stack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bulkBar.addSubview(stack)
        view.addSubview(bulkBar)
        NSLayoutConstraint.activate([
            bulkBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bulkBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bulkBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bulkBar.heightAnchor.constraint(equalToConstant: Self.bulkBarHeight),
            topBorder.topAnchor.constraint(equalTo: bulkBar.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: bulkBar.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: bulkBar.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
            stack.topAnchor.constraint(equalTo: bulkBar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bulkBar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bulkBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bulkBar.trailingAnchor),
        ])
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 見出し帯を自前で出すため、ナビゲーションバーは隠す
        // (設定まわりの画面・視聴履歴と同じ扱い)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        reloadTrash()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func refresh() {
        reloadTrash()
    }

    // MARK: - 読み込み

    /// ゴミ箱の中身を取り直す。未ログインのときは通信せず案内だけ出す
    /// (ゴミ箱の口はログイン必須)。
    private func reloadTrash() {
        // ロゴの取り直し: 一度失敗した局も、読み直しのたびに試し直す。
        failedLogoIDs.removeAll()
        // なぞり選択の最中は読み直さない (並びが入れ替わると
        // 選択の範囲が崩れるため)。更新の表示だけ止めて戻る。
        guard !isDragSelecting else {
            refreshControl.endRefreshing()
            return
        }
        // まとめて操作の実行中も読み直さない (実行中の処理が使って
        // いる一覧の中身が入れ替わり、表示や件数が食い違うため)。
        guard !isBulkRunning else {
            refreshControl.endRefreshing()
            return
        }
        guard !isLoading else {
            refreshControl.endRefreshing()
            return
        }
        guard SettingsStore.shared.isLoggedIn else {
            items = []
            displayItems = []
            selectedIDs = []
            if isSelectionMode { exitSelectionMode() }
            updateControlsVisibility()
            statusLabel.text = "ゴミ箱を使うには、ログインが必要です。\n"
                + "アカウントの設定でログインしてください。"
            noteLabel.text = nil
            layoutNoteHeader()
            tableView.reloadData()
            refreshControl.endRefreshing()
            return
        }
        isLoading = true
        if items.isEmpty {
            statusLabel.text = "読み込み中です…"
        }
        Task { [weak self] in
            guard let self else { return }
            // 管理者かどうかも一緒に取り直す (操作ボタンの出し分け)。
            if let user = try? await APIClient.shared.fetchCurrentUser() {
                self.isAdminUser = user.is_admin
            }
            do {
                let response = try await APIClient.shared.fetchTrashList()
                self.items = response.items
                self.retentionDays = response.retention_days
                self.applyItems()
            } catch let error as APIError {
                if case .badStatus(401) = error {
                    self.items = []
                    self.displayItems = []
                    self.selectedIDs = []
                    if self.isSelectionMode { self.exitSelectionMode() }
                    self.updateControlsVisibility()
                    self.statusLabel.text = "ログインの有効期限が切れています。\n"
                        + "アカウントの設定でログインし直してください。"
                    self.noteLabel.text = nil
                    self.layoutNoteHeader()
                    self.tableView.reloadData()
                } else if self.items.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
                }
            } catch {
                if self.items.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。"
                }
            }
            self.isLoading = false
            self.refreshControl.endRefreshing()
        }
    }

    /// 取得した中身を画面へ反映する (説明文・空の表示・一覧)。
    /// 一覧は並び替えを適用した写しで出し、取得した元の並びは変えない。
    private func applyItems() {
        noteLabel.text = "ゴミ箱に移動した録画は \(retentionDays) 日間保持され、"
            + "期間を過ぎると自動的に完全に削除されます。"
        statusLabel.text = items.isEmpty ? "ゴミ箱は空です" : nil
        displayItems = Self.sorted(items, by: sortKind)
        // 消えた録画が選択に残っていたら取り除く。
        selectedIDs.formIntersection(Set(items.map { $0.program.id }))
        if items.isEmpty, isSelectionMode {
            exitSelectionMode()
        }
        updateControlsVisibility()
        layoutNoteHeader()
        tableView.reloadData()
    }

    /// 並び替えを適用した写しを作る (Web 版と同じ規則)。
    private static func sorted(_ items: [TrashItem], by kind: SortKind) -> [TrashItem] {
        switch kind {
        case .newest:
            return items.sorted { ($0.program.startDate ?? .distantPast) > ($1.program.startDate ?? .distantPast) }
        case .oldest:
            return items.sorted { ($0.program.startDate ?? .distantPast) < ($1.program.startDate ?? .distantPast) }
        case .purgeNear:
            return items.sorted { ($0.purgeDate ?? .distantFuture) < ($1.purgeDate ?? .distantFuture) }
        case .purgeFar:
            return items.sorted { ($0.purgeDate ?? .distantPast) > ($1.purgeDate ?? .distantPast) }
        }
    }

    /// 並び替え・選択まわりの出し分けを現在の状態に合わせる。
    /// 「選択する」のピルは管理者で、ゴミ箱が空でないときだけ出す。
    private func updateControlsVisibility() {
        let showsSelectRow = isAdminUser && !items.isEmpty
        selectRowView.isHidden = !showsSelectRow
        selectRowHeightConstraint?.constant = showsSelectRow ? 38 : 0
        bulkBar.isHidden = !isSelectionMode
        if isSelectionMode {
            // 操作帯は一覧より前面に出す (組み立て順では一覧が後から
            // 重なっているため)。
            view.bringSubviewToFront(bulkBar)
        }
        // 選択中は、操作帯の分だけ一覧の下に余白を空ける (Web 版と同じ)。
        tableView.contentInset.bottom = isSelectionMode ? Self.bulkBarHeight + 10 : 10
        updateBulkBar()
    }

    /// 操作帯の表示 (件数と各ボタンの有効・無効) を合わせる。
    /// 1件も選んでいないときは復元・削除を押せない (Web 版と同じ)。
    private func updateBulkBar() {
        bulkCountLabel.text = "\(selectedIDs.count) 件選択中"
        let hasSelection = !selectedIDs.isEmpty
        bulkRestoreButton.isEnabled = hasSelection && !isBulkRunning
        bulkDeleteButton.isEnabled = hasSelection && !isBulkRunning
        bulkRestoreButton.alpha = bulkRestoreButton.isEnabled ? 1 : 0.5
        bulkDeleteButton.alpha = bulkDeleteButton.isEnabled ? 1 : 0.5
        bulkSelectAllButton.isEnabled = !isBulkRunning
        bulkClearButton.isEnabled = hasSelection && !isBulkRunning
        bulkClearButton.alpha = bulkClearButton.isEnabled ? 1 : 0.5
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        let item = displayItems[indexPath.row]
        cell.configure(with: item.program)
        cell.configureTrash(
            notice: "あと \(item.remainingDays) 日で完全に削除されます",
            // 選択中はカードごとのボタンを隠す (Web 版と同じ)。
            showsActions: isAdminUser && !isSelectionMode,
            onRestore: { [weak self] in self?.restore(item: item) },
            onDelete: { [weak self] in self?.confirmDelete(item: item) }
        )
        cell.configureSelection(
            active: isSelectionMode,
            selected: selectedIDs.contains(item.program.id))
        loadThumbnail(for: item.program, into: cell)
        if let channelID = item.program.channel?.id {
            if let cached = logoCache.object(forKey: channelID as NSString) {
                cell.setLogo(cached)
            } else {
                loadLogo(channelID: channelID, at: indexPath)
            }
        }
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 選択中は、カードを選ぶと選択の付け外しになる。
    /// 選択中でないときは今までどおり何もしない (再生画面へは移らない)。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard isSelectionMode, displayItems.indices.contains(indexPath.row) else { return }
        let id = displayItems[indexPath.row].program.id
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        if let cell = tableView.cellForRow(at: indexPath) as? VideoCell {
            cell.configureSelection(active: true, selected: selectedIDs.contains(id))
        }
        updateBulkBar()
    }

    /// 選択中に、カードの上で指を少し止めてから動かしたときの処理
    /// (なぞって選択)。指の下にある行と、なぞり始めの行の間の
    /// 範囲をまとめて選択／解除する。逆向きに戻れば、範囲から外れた分は
    /// なぞる前の状態へ戻る。
    ///
    /// なぞっている間、一覧自体のスクロール (指に付いて動く動き) は
    /// 止める。以前は一覧のスクロールに相乗りしていたため、指を動かすと
    /// 一覧も一緒に動いて指の下の項目が変わらず、範囲が広げられな
    /// かったうえ、指の下の行が境目で小刻みに切り替わって、表示が
    /// 震えて見えた。今は指が項目の上を移動した分だけで範囲を広げ、
    /// 画面の端に指を持っていったときだけ、端からの近さに応じた
    /// 速さで一覧が少しずつ流れる (stepDragAutoScroll)。
    ///
    /// スクロールか なぞり選択かの判定は、受け口が始まる前に
    /// 受け口の中で済ませる (DragSelectionPanGestureRecognizer)。
    /// 指を少し止めてから動かしたときだけ受け口が始まるので、
    /// ここに来たものは そのまま なぞり選択として取り込める。
    /// 止めずに動かしたドラッグは受け口が失敗してスクロールに
    /// なるため、選択中に眺めるためのスクロールは速さによらず
    /// そのままできる。
    @objc private func handleDragSelection(_ gesture: DragSelectionPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard isSelectionMode, !isBulkRunning, !isLoading else { return }
            // 起点は、指が触れた位置の行 (判定の間に指は少し動いて
            // いるため、受け口に残してある触れた位置を使う)。
            guard let row = dragRow(at: gesture.startLocation) else { return }
            dragCommitted = true
            dragAnchorRow = row
            dragSelecting = !selectedIDs.contains(displayItems[row].program.id)
            dragRangeIDs = []
            dragBaseline = [:]
            dragAutoScrollDirection = 0
            dragFingerPoint = gesture.location(in: view)
            // 一覧が指に付いて動かないようにする (この指については
            // 一覧のスクロール側が既に外れているが、別の指で
            // 流れたりしないための用心)。引っ張って更新も、
            // 最中は止める。
            tableView.isScrollEnabled = false
            refreshControl.isEnabled = false
            // なぞっている間は、操作帯のボタンが指の動きに割り込ま
            // ないよう、操作帯へのタッチを止める。指が操作帯の上に
            // 行っても、端での流れが止まらないようにするため。
            bulkBar.isUserInteractionEnabled = false
            applyDragSelection(toRow: row)
            startDragAutoScroll()
        case .changed:
            guard isSelectionMode, dragCommitted, dragAnchorRow != nil else { return }
            dragFingerPoint = gesture.location(in: view)
            // 端での自動スクロールの刻みが何かの都合で止まって
            // いたら、指の動きに合わせて再開する (同じドラッグの
            // 間は、端に入るたびに流れが始まるように)。
            if dragScrollLink == nil { startDragAutoScroll() }
            if let row = dragRow(at: gesture.location(in: tableView)) {
                applyDragSelection(toRow: row)
            }
        default:
            finishDragSelection()
        }
    }

    /// なぞり選択を終える。一覧のスクロールと引っ張って更新を
    /// 元に戻し、途中の控えを片付ける。
    private func finishDragSelection() {
        dragScrollLink?.invalidate()
        dragScrollLink = nil
        dragAnchorRow = nil
        dragCommitted = false
        dragRangeIDs = []
        dragBaseline = [:]
        dragFingerPoint = nil
        dragAutoScrollDirection = 0
        tableView.isScrollEnabled = true
        refreshControl.isEnabled = true
        bulkBar.isUserInteractionEnabled = true
    }

    /// なぞり選択の受け口とは同時に動かさない。一覧のスクロールは、
    /// なぞり選択の受け口が失敗するまで始めないよう頼んである
    /// (require(toFail:))。同時に動くことを許すと、その頼みが
    /// 効かなくなってしまう。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// 端での自動スクロールの刻みを始める。
    private func startDragAutoScroll() {
        dragScrollLink?.invalidate()
        dragScrollLastTime = 0
        let link = CADisplayLink(
            target: self, selector: #selector(stepDragAutoScroll(_:)))
        link.add(to: .main, forMode: .common)
        dragScrollLink = link
    }

    /// 端の領域に指が入っている深さから、自動スクロールの速さ
    /// (1秒あたり) を決める。深さは、端の領域の内側の境目から
    /// 指までの距離。領域の中では近さの二乗で効かせるので、入口では
    /// ごくゆっくり、端そのもので上限の速さになる。指が端を超えて
    /// 一覧の外側にあるときは、超えた分でもう一段速くなり、超えた分が
    /// 端の幅の半分 (36pt) 以上で上限の1.5倍に頭打ちする。
    private static func dragScrollSpeed(forDepth depth: CGFloat) -> CGFloat {
        let ratio = max(0, depth) / dragEdgeLength
        if ratio <= 1 {
            return dragMaxScrollSpeed * ratio * ratio
        }
        return dragMaxScrollSpeed * (1 + min(ratio - 1, 0.5))
    }

    /// 表示の刻みごとに、指が画面の端にあれば一覧を少し流す。
    /// 端に近いほど速くなり、端から離れれば止まる。速さの決め方は
    /// dragScrollSpeed(forDepth:) のとおりで、端そのものでは1秒に
    /// 420pt、指が端の外側まで出ればその1.5倍まで速くなる。
    @objc private func stepDragAutoScroll(_ link: CADisplayLink) {
        guard dragAnchorRow != nil else { return }
        // 指の位置は、刻みのたびに受け口から取り直す。指の動きの
        // 通知だけを頼りにすると、通知が止まったときに最後の位置で
        // 固まって、同じドラッグの間は流れが再開しなくなるため。
        if dragSelectionGesture.state == .began
            || dragSelectionGesture.state == .changed {
            dragFingerPoint = dragSelectionGesture.location(in: view)
        }
        guard let finger = dragFingerPoint else { return }
        defer { dragScrollLastTime = link.timestamp }
        guard dragScrollLastTime > 0 else { return }
        let dt = min(link.timestamp - dragScrollLastTime, 0.05)
        // 一覧の見えている範囲 (画面全体での座標)。下の端は操作帯の
        // 上端に置く。指が操作帯の上にあるときは「一番下の端に
        // いる」扱いで、深さが端の幅を超えた分だけ速くなり、
        // 流れは止まらない。
        let visibleTop = tableView.frame.minY
        let visibleBottom = tableView.frame.maxY
            - (isSelectionMode ? Self.bulkBarHeight : 0)
        // 端に入った向きは、境目から少し (16pt) 外れるまで保つ。
        // 境目ぎりぎりで指がわずかに揺れるたび、流れが入ったり
        // 止まったりを繰り返して、小刻みに跳ねて見えるのを防ぐ。
        // 向きを保っている間も、端の領域の外では深さが無いので
        // 実際には流れない。
        let topEdge = visibleTop + Self.dragEdgeLength
        let bottomEdge = visibleBottom - Self.dragEdgeLength
        var depth: CGFloat = 0
        if finger.y < topEdge {
            dragAutoScrollDirection = -1
            depth = topEdge - finger.y
        } else if finger.y > bottomEdge {
            dragAutoScrollDirection = 1
            depth = finger.y - bottomEdge
        } else if dragAutoScrollDirection < 0,
                  finger.y < topEdge + Self.dragEdgeHysteresis {
            depth = 0
        } else if dragAutoScrollDirection > 0,
                  finger.y > bottomEdge - Self.dragEdgeHysteresis {
            depth = 0
        } else {
            dragAutoScrollDirection = 0
        }
        let delta = CGFloat(dragAutoScrollDirection)
            * Self.dragScrollSpeed(forDepth: depth) * CGFloat(dt)
        guard delta != 0 else { return }
        let minOffset = -tableView.contentInset.top
        let maxOffset = max(minOffset,
            tableView.contentSize.height + tableView.contentInset.bottom
                - tableView.bounds.height)
        let newY = min(maxOffset, max(minOffset, tableView.contentOffset.y + delta))
        guard newY != tableView.contentOffset.y else { return }
        tableView.contentOffset = CGPoint(x: tableView.contentOffset.x, y: newY)
        // 流れた分、止まっている指の下の行が変わるので、範囲を取り直す。
        if let row = dragRow(at: tableView.convert(finger, from: view)) {
            applyDragSelection(toRow: row)
        }
    }

    /// 指の位置にある行。行の外 (上下の端の外側) にあるときは一番近い
    /// 行に寄せる (端までなぞったときに範囲が端まで届くように)。
    private func dragRow(at point: CGPoint) -> Int? {
        guard !displayItems.isEmpty else { return nil }
        if let indexPath = tableView.indexPathForRow(at: point) {
            return indexPath.row
        }
        let firstRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        return point.y < firstRect.minY ? 0 : displayItems.count - 1
    }

    /// なぞった範囲へ選択の状態を反映する。範囲に入った項目はなぞり
    /// 始めに決めた向き (選択／解除) にそろえ、範囲から外れた項目は
    /// なぞる前の状態へ戻す。
    private func applyDragSelection(toRow row: Int) {
        guard let anchor = dragAnchorRow else { return }
        var newRange: Set<Int> = []
        for index in min(anchor, row)...max(anchor, row)
        where displayItems.indices.contains(index) {
            newRange.insert(displayItems[index].program.id)
        }
        for id in dragRangeIDs.union(newRange) {
            if dragBaseline[id] == nil {
                dragBaseline[id] = selectedIDs.contains(id)
            }
            let target = newRange.contains(id)
                ? dragSelecting : (dragBaseline[id] ?? false)
            guard selectedIDs.contains(id) != target else { continue }
            if target {
                selectedIDs.insert(id)
            } else {
                selectedIDs.remove(id)
            }
            if let index = displayItems.firstIndex(where: { $0.program.id == id }),
               let cell = tableView.cellForRow(
                   at: IndexPath(row: index, section: 0)) as? VideoCell {
                cell.configureSelection(active: true, selected: target)
            }
        }
        dragRangeIDs = newRange
        updateBulkBar()
    }

    /// 局ロゴを取ってきて、表示中の行がまだ同じ番組ならその場で反映する
    /// (録画一覧と同じ方式)。
    private func loadLogo(channelID: String, at indexPath: IndexPath) {
        guard !failedLogoIDs.contains(channelID) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channelID),
                  let image = UIImage(data: data) else {
                self.failedLogoIDs.insert(channelID)
                return
            }
            self.logoCache.setObject(image, forKey: channelID as NSString)
            if let cell = self.tableView.cellForRow(at: indexPath) as? VideoCell,
               self.displayItems.indices.contains(indexPath.row),
               self.displayItems[indexPath.row].program.channel?.id == channelID {
                cell.setLogo(image)
            }
        }
    }

    /// サムネイルをセルへ出す。端末に控えがあれば、その場でこのセルへ
    /// 即座に出す。選択モードに入るなどでセルが作り直されても、控えの
    /// ある番組は仮の絵のままにならない。控えが無いときだけサーバーへ
    /// 取りに行く。
    private func loadThumbnail(for program: RecordedProgram, into cell: VideoCell) {
        if let cached = thumbnailCache.object(forKey: NSNumber(value: program.id)) {
            cell.setThumbnail(cached)
            return
        }
        fetchThumbnail(videoID: program.id, isRetry: false)
    }

    /// サムネイルをサーバーから取る。同じ番組への取得は重ねない。
    /// 取れたら控えに入れ、いまその番組を表示しているセルへ出す
    /// (行の位置は取得が終わった時点で探し直すので、途中で一覧が
    /// 作り直されたり並びが変わったりしても取りこぼさない)。
    /// 失敗したら、少し置いて1回だけ取り直す。
    private func fetchThumbnail(videoID: Int, isRetry: Bool) {
        guard !thumbnailLoadingIDs.contains(videoID) else { return }
        thumbnailLoadingIDs.insert(videoID)
        Task { [weak self] in
            guard let self else { return }
            var image: UIImage?
            if let data = try? await APIClient.shared.fetchThumbnail(videoID: videoID) {
                image = UIImage(data: data)
            }
            self.thumbnailLoadingIDs.remove(videoID)
            if let image {
                self.thumbnailCache.setObject(image, forKey: NSNumber(value: videoID))
                self.applyThumbnail(image, videoID: videoID)
            } else if !isRetry {
                self.scheduleThumbnailRetry(videoID: videoID)
            }
        }
    }

    /// 失敗したサムネイルの取り直しを、少し置いて1回だけ行う。
    /// その番組がもう画面に出ていないときは取り直さない。
    private func scheduleThumbnailRetry(videoID: Int) {
        guard !thumbnailRetryingIDs.contains(videoID),
              thumbnailRow(videoID: videoID) != nil else { return }
        thumbnailRetryingIDs.insert(videoID)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.thumbnailRetryingIDs.remove(videoID)
            guard self.thumbnailCache.object(forKey: NSNumber(value: videoID)) == nil,
                  self.thumbnailRow(videoID: videoID) != nil else { return }
            self.fetchThumbnail(videoID: videoID, isRetry: true)
        }
    }

    /// 取れたサムネイルを、いまその番組を表示しているセルへ出す。
    /// セルが使い回されて別の番組に変わっていたら出さない。
    private func applyThumbnail(_ image: UIImage, videoID: Int) {
        guard let row = thumbnailRow(videoID: videoID),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? VideoCell,
              cell.thumbnailProgramID == videoID else { return }
        cell.setThumbnail(image)
    }

    /// いま表示しているデータの中で、その番組の行を探す。
    private func thumbnailRow(videoID: Int) -> Int? {
        displayItems.firstIndex { $0.program.id == videoID }
    }

    // MARK: - 復元と完全削除

    /// ゴミ箱から復元する。成功したらその行を取り除く。
    private func restore(item: TrashItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.restoreFromTrash(videoID: item.program.id)
                self.items.removeAll { $0.program.id == item.program.id }
                self.applyItems()
            } catch let error as APIError {
                self.showAlert(title: error.restoreFromTrashFailureMessage, message: nil)
            } catch {
                self.showAlert(title: "ゴミ箱から復元できませんでした", message: nil)
            }
        }
    }

    /// 完全削除の確認を出す。Web 版と同じく、まず事前確認を取って
    /// 管理元と削除対象を確かめる。取れなければ削除自体を中止する。
    private func confirmDelete(item: TrashItem) {
        Task { [weak self] in
            guard let self else { return }
            let preview: RecordingDeletePreview
            do {
                preview = try await APIClient.shared.fetchDeletePreview(videoID: item.program.id)
            } catch {
                self.showAlert(
                    title: "管理元と削除対象を確認できないため、削除を中止しました。", message: nil)
                return
            }
            self.presentDeleteConfirmation(item: item, preview: preview)
        }
    }

    private func presentDeleteConfirmation(item: TrashItem, preview: RecordingDeletePreview) {
        var message = item.program.title
        if preview.enabled, let plan = preview.plan {
            message += "\n\n管理元: EPGStation / 録画ID: \(plan.epgstation_id)\n"
                + "録画本体はEPGStationで削除し、KonomiTVとJellyfinの一覧も更新します。"
        }
        message += "\n\nゴミ箱からも消え、元に戻すことはできません。"
        let alert = UIAlertController(
            title: "本当に完全に削除しますか？",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "完全に削除", style: .destructive) { [weak self] _ in
            self?.performDelete(item: item, preview: preview)
        })
        present(alert, animated: true)
    }

    /// 完全に削除する。削除には時間がかかることがあるため、実行中は
    /// 進み具合の表示を出す (Web 版の「削除を開始します」の知らせに相当)。
    private func performDelete(item: TrashItem, preview: RecordingDeletePreview) {
        let progress = UIAlertController(title: "削除しています…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let jellyfinPending = try await APIClient.shared.deleteVideo(
                    videoID: item.program.id, confirmationToken: preview.confirmation_token)
                progress.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    self.items.removeAll { $0.program.id == item.program.id }
                    self.applyItems()
                    if jellyfinPending {
                        self.showAlert(
                            title: "完全に削除しました",
                            message: "Jellyfinの一覧更新はバックグラウンドで再試行しています。")
                    }
                }
            } catch let error as APIError {
                progress.dismiss(animated: true) { [weak self] in
                    self?.showAlert(title: error.deleteVideoFailureMessage, message: nil)
                }
            } catch {
                progress.dismiss(animated: true) { [weak self] in
                    self?.showAlert(title: "完全に削除できませんでした", message: nil)
                }
            }
        }
    }

    // MARK: - 複数選択とまとめて操作

    /// 「選択する／選択を終える」のピルの切り替え。
    /// まとめて操作の実行中は切り替えない。
    @objc private func toggleSelectionMode() {
        guard !isBulkRunning else { return }
        if isSelectionMode {
            exitSelectionMode()
        } else {
            isSelectionMode = true
            // なぞり選択の受け口は、選択中だけ有効にする。
            dragSelectionGesture.isEnabled = true
            selectButton.setTitle("選択を終える", for: .normal)
            updateControlsVisibility()
            tableView.reloadData()
        }
    }

    /// 選択中を終える。選んでいた内容は破棄する。
    private func exitSelectionMode() {
        isSelectionMode = false
        dragSelectionGesture.isEnabled = false
        finishDragSelection()
        selectedIDs = []
        selectButton.setTitle("選択する", for: .normal)
        updateControlsVisibility()
        tableView.reloadData()
    }

    @objc private func selectAllItems() {
        guard !isBulkRunning else { return }
        selectedIDs = Set(items.map { $0.program.id })
        tableView.reloadData()
        updateBulkBar()
    }

    @objc private func clearSelection() {
        guard !isBulkRunning else { return }
        selectedIDs = []
        tableView.reloadData()
        updateBulkBar()
    }

    /// 選んだ分をまとめて復元する。1件ずつのときと同じ受け口を
    /// 順に使う (Web 版と同じ)。成功分だけ一覧と選択から取り除き、
    /// 失敗分は残して件数と題名入りの警告を出す。全部成功したら
    /// 選択中を終える。
    @objc private func bulkRestore() {
        guard !isBulkRunning, !selectedIDs.isEmpty else { return }
        let targets = items.filter { selectedIDs.contains($0.program.id) }
        guard !targets.isEmpty else { return }
        isBulkRunning = true
        updateBulkBar()
        Task { [weak self] in
            guard let self else { return }
            var failed: [TrashItem] = []
            for item in targets {
                do {
                    try await APIClient.shared.restoreFromTrash(videoID: item.program.id)
                    self.items.removeAll { $0.program.id == item.program.id }
                    self.selectedIDs.remove(item.program.id)
                } catch {
                    failed.append(item)
                }
            }
            self.isBulkRunning = false
            self.applyItems()
            if failed.isEmpty {
                self.exitSelectionMode()
            } else {
                self.showAlert(
                    title: "\(failed.count) 件を復元できませんでした",
                    message: failed.map { $0.program.title }.joined(separator: "\n"))
            }
        }
    }

    /// 選んだ分をまとめて完全に削除する。まず対象の件数と題名を
    /// 出して確認し、実行時は項目ごとに事前確認を取ってから
    /// 削除する (事前確認が取れない項目は削除しない。1件のときと
    /// 同じ流儀)。一部失敗時は成功分だけ取り除き、失敗分は残して
    /// 警告を出す。全部成功したら選択中を終える。
    @objc private func bulkDelete() {
        guard !isBulkRunning, !selectedIDs.isEmpty else { return }
        let targets = items.filter { selectedIDs.contains($0.program.id) }
        guard !targets.isEmpty else { return }
        let message = "対象: \(targets.count) 件\n"
            + targets.map { $0.program.title }.joined(separator: "\n")
            + "\n\nゴミ箱からも消え、元に戻すことはできません。"
        let alert = UIAlertController(
            title: "本当に完全に削除しますか？",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "完全に削除", style: .destructive) { [weak self] _ in
            self?.performBulkDelete(targets: targets)
        })
        present(alert, animated: true)
    }

    private func performBulkDelete(targets: [TrashItem]) {
        guard !isBulkRunning else { return }
        isBulkRunning = true
        updateBulkBar()
        let progress = UIAlertController(title: "削除しています…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)
        Task { [weak self] in
            guard let self else { return }
            var failed: [TrashItem] = []
            var jellyfinPending = false
            for item in targets {
                guard let preview = try? await APIClient.shared.fetchDeletePreview(
                    videoID: item.program.id) else {
                    failed.append(item)
                    continue
                }
                do {
                    let pending = try await APIClient.shared.deleteVideo(
                        videoID: item.program.id, confirmationToken: preview.confirmation_token)
                    jellyfinPending = jellyfinPending || pending
                    self.items.removeAll { $0.program.id == item.program.id }
                    self.selectedIDs.remove(item.program.id)
                } catch {
                    failed.append(item)
                }
            }
            self.isBulkRunning = false
            progress.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.applyItems()
                if failed.isEmpty {
                    self.exitSelectionMode()
                    if jellyfinPending {
                        self.showAlert(
                            title: "完全に削除しました",
                            message: "Jellyfinの一覧更新はバックグラウンドで再試行しています。")
                    }
                } else {
                    self.showAlert(
                        title: "\(failed.count) 件を完全に削除できませんでした",
                        message: failed.map { $0.program.title }.joined(separator: "\n"))
                }
            }
        }
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
