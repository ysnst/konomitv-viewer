import UIKit

/// 録画一覧と下部タブバーで使う配色。Web 版 KonomiTV のテーマ定義
/// (client の vuetify.ts) の実値そのまま。
enum AppPalette {
    /// 画面全体の背景 (テーマの background: #1E1310)。
    static let background = UIColor(red: 0x1E / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 1)
    /// カードとタブバーの面 (background-lighten-1: #2F221F)。
    static let panel = UIColor(red: 0x2F / 255, green: 0x22 / 255, blue: 0x1F / 255, alpha: 1)
    /// 押したときの面 (background-lighten-2: #433532)。
    static let pressed = UIColor(red: 0x43 / 255, green: 0x35 / 255, blue: 0x32 / 255, alpha: 1)
    /// 主な文字 (text: #FFEAEA)。
    static let text = UIColor(red: 0xFF / 255, green: 0xEA / 255, blue: 0xEA / 255, alpha: 1)
    /// 局名・時刻・説明の文字 (text-darken-1: #D9C7C7)。
    static let metaText = UIColor(red: 0xD9 / 255, green: 0xC7 / 255, blue: 0xC7 / 255, alpha: 1)
    /// 状態表示などの補助の文字 (text-darken-2: #8E7F7E)。
    static let secondaryText = UIColor(red: 0x8E / 255, green: 0x7F / 255, blue: 0x7E / 255, alpha: 1)
    /// アクセント (primary: #E64F97)。未視聴ピルや選択中のタブの色。
    static let accent = UIColor(red: 0xE6 / 255, green: 0x4F / 255, blue: 0x97 / 255, alpha: 1)
    /// 見た割合バーの色 (secondary-lighten-1: #FF526F)。
    static let progress = UIColor(red: 0xFF / 255, green: 0x52 / 255, blue: 0x6F / 255, alpha: 1)
    /// 管理者バッジの地 (secondary: #E33157)。
    static let secondary = UIColor(red: 0xE3 / 255, green: 0x31 / 255, blue: 0x57 / 255, alpha: 1)
    /// 保護中バッジの文字と枠の色 (warning: #FB8C00)。
    static let warning = UIColor(red: 0xFB / 255, green: 0x8C / 255, blue: 0x00 / 255, alpha: 1)
    /// 録画中ドットの色 (Web 版の #FF4444)。
    static let recordingDot = UIColor(red: 0xFF / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
    /// 警告・完全削除の色 (テーマの error: #FF5252)。ゴミ箱の
    /// 「あと○日で完全に削除されます」の文字と「完全に削除」ボタンで使う。
    static let error = UIColor(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255, alpha: 1)
    /// サムネイルやロゴが読み込まれるまでの地 (gray: #66514C)。
    static let placeholder = UIColor(red: 0x66 / 255, green: 0x51 / 255, blue: 0x4C / 255, alpha: 1)
    /// 入力欄の枠線 (background-lighten-3: #4C3C38)。設定画面で使う。
    static let fieldBorder = UIColor(red: 0x4C / 255, green: 0x3C / 255, blue: 0x38 / 255, alpha: 1)
    /// トグルのレールとつまみの色 (surface-variant / surface-bright /
    /// text-darken-3 と同値の #786968)。Web 版のスイッチで使う色。
    static let surfaceVariant = UIColor(red: 0x78 / 255, green: 0x69 / 255, blue: 0x68 / 255, alpha: 1)
    /// 選択欄の枠線 (Web 版 Vuetify の outlined の枠: on-surface #FFEAEA の
    /// 38% の濃さ、1px)。番組表の操作帯の種別・時刻の選択ボタンと、
    /// 番組表の表示設定の色の選択ボタンで使う。
    static let outlineBorder = UIColor(red: 0xFF / 255, green: 0xEA / 255, blue: 0xEA / 255, alpha: 0.38)
    /// 日付ボタンの枠線 (Web 版の日付ボタンが内側の影で描く枠:
    /// on-surface #FFEAEA の 26% の濃さ、1px)。
    static let outlineBorderSoft = UIColor(red: 0xFF / 255, green: 0xEA / 255, blue: 0xEA / 255, alpha: 0.26)
}

/// 録画番組の一覧。Web 版と同じく30件ごとのページ分けで、番号付きの
/// ページ送りを一覧の上と下の両方に置く。
/// 並びは Web 版と同じく、番組ごとに独立した角丸カードが間隔を空けて並ぶ形。
/// フィルタと並び替えは Web 版のスマホ縦の形に合わせ、「フィルタ」
/// ボタンから開くメニューで切り替える。ボタンの置き場所は、ゴミ箱の
/// 入口が出るときは見出し行の下の行の右端、出ないときは見出し行の右端。
/// 検索は Web 版のヘッダーと同じく、ロゴ帯の右端の虫眼鏡から開く欄で
/// 題名とシリーズ名をその場で絞り込む (絞り込みの扱いはフィルタと同じ)。
final class VideoListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    /// 1ページの件数。サーバー側の固定値 (PAGE_SIZE = 30) に合わせる。
    private static let pageSize = 30
    /// 表示状態 (ページ・並び順・両フィルタ) の保存先のキー。
    /// Web 版の端末ローカル保存と同じキー名にしてある。
    private static let viewStateKey = "KonomiTV-RecordedProgramsViewState"

    private let headerView = SPHeaderView()
    /// 先頭まわり一式 (ロゴ帯・容量行・見出し行・上のページ送り) をまとめる枠。
    /// テーブルの先頭に付けて、一覧と一緒にスクロールして流れる形にする
    /// (Web 版のスマホ縦でページ全体がスクロールするのと同じ)。
    private let headContainerView = UIView()
    /// 容量行 (「録画 ○ GB / ○ TB（空き ○ TB）」)。Web 版の StorageStatusText に相当。
    /// 容量が取得できたときだけ出し、取得できないときは行自体を消す (Web 版と同じ)。
    private let storageRowView = UIView()
    private let storageIconView = UIImageView()
    private let storageLabel = UILabel()
    /// 録画結果への入口 (Web 版の「ビデオをみる」先頭の左側のボタンに
    /// 相当)。容量行の左端に置く。録画結果一覧のトグルがオンのとき
    /// だけに出すため、容量情報が取れていないときでもオンなら
    /// 容量行自体を出す。
    private let recordingResultsButton = RippleButton()
    /// 容量行を出すかどうか。容量が取れたとき、または録画結果一覧の
    /// トグルがオン (録画結果の入口を出すため) のとき。
    private var showsStorageRow: Bool { storageStatus != nil || AppEdition.recordingResultsEnabled }
    /// 取得できた容量情報。nil の間は容量行を出さない。
    private var storageStatus: StorageStatus?
    /// 容量情報の定期取得 (Web 版と同じ30秒間隔) 用。
    private var storageTimer: Timer?
    /// 見出し行 (「録画番組一覧 ○件」と、右端の「ゴミ箱を開く」)。
    private let listHeaderView = UIView()
    private let listTitleLabel = UILabel()
    private let countLabel = UILabel()
    /// 見出し行の下の行。左端に複数選択の入り口のピルを置く。フィルタの
    /// ボタンは、ゴミ箱の入口が出るときだけこの行の右端に置き、出ない
    /// ときは見出し行の右端に置く。ピルもフィルタもこの行に出ない
    /// ときは、行自体をなくす。
    private let selectFilterRowView = UIView()
    private let filterButton = RippleButton()
    /// フィルタボタン右上の、ON になっているフィルタの件数の印。
    private let filterBadgeLabel = UILabel()
    /// フィルタのボタンの置き場所の制約。見出し行に置くときと、その下の
    /// 行に置くときの2組を用意し、出し分けに合わせて切り替える
    /// (用意は viewDidLoad、切り替えは refreshHeadContainer)。
    private var filterInHeaderConstraints: [NSLayoutConstraint] = []
    private var filterInRowConstraints: [NSLayoutConstraint] = []
    /// フィルタの印の制約。ボタンと一緒に付け替えるため、組にして持つ。
    private var filterBadgeConstraints: [NSLayoutConstraint] = []
    /// 検索の入り口 (虫眼鏡のボタン)。Web 版のヘッダーと同じく、ロゴ帯の
    /// 右端に置く。この画面だけの部品なので、共通のロゴ帯 (SPHeaderView)
    /// には足さず、先頭まわり一式の上に重ねる。
    private let searchButton = RippleButton()
    /// 開いた検索欄。ロゴ帯の行全体を覆う形で出す (Web 版のヘッダーが
    /// 検索中は欄だけの姿になるのと同じ)。中身は虫眼鏡の印・入力欄・
    /// 閉じる印 (×)。
    private let searchBarView = UIView()
    private let searchIconView = UIImageView()
    private let searchField = UITextField()
    private let searchCloseButton = RippleButton()
    /// 検索欄が開いているか。
    private var isSearchBarOpen = false
    /// 検索中に画面左端から右へなぞると検索を閉じるための受け口。
    /// 一覧の縦スクロールとはぶつからない形 (画面端からの横の動き)。
    private let searchEdgePanGesture = UIScreenEdgePanGestureRecognizer()
    /// ゴミ箱への入口 (Web 版の録画番組一覧にある「ゴミ箱を開く」の
    /// リンクに相当)。見出し行の右端に置く。拡張版かつ管理者で
    /// ログインしているときだけ出す。
    private let trashLinkButton = RippleButton()
    /// ログイン中の利用者が管理者かどうか。ゴミ箱の入口と、長押し
    /// メニューの「ゴミ箱に移動する」の出し分けに使う (Web 版と同じく、
    /// ゴミ箱まわりは管理者だけに出す)。
    private var isAdminUser = false
    /// ゴミ箱の入口を出すかどうか。
    private var showsTrashLink: Bool { AppEdition.trashEnabled && isAdminUser }
    /// 選択とフィルタの行の高さ。
    private static let selectFilterRowHeight: CGFloat = 38
    /// 複数選択の入り口のピル (見出し行の下の行の左端。
    /// ゴミ箱の「選択する」のピルと同じ見た目)。
    private let selectButton = RippleButton()
    /// 「選択する」のピルを出すかどうか。複数選択で使える操作が
    /// 1つでもあるとき (保護のトグルがオン、またはゴミ箱のトグルが
    /// オンで管理者) に、一覧が空でないときだけ出す。選択中は、
    /// 終えるためのピルが要るため常に出す。
    private var showsSelectButton: Bool {
        isSelectionMode
            || ((AppEdition.protectionEnabled || (AppEdition.trashEnabled && isAdminUser))
                && !programs.isEmpty)
    }
    /// 見出し行の下の行を出すかどうか。ゴミ箱の入口が出るときは
    /// フィルタをこの行に置くため常に出し、出ないときは選択のピルが
    /// 出るときだけ出す。
    private var showsSelectFilterRow: Bool { showsTrashLink || showsSelectButton }
    /// 選択中の下部に固定で出す操作帯とその中身 (ゴミ箱と同じ作り)。
    private let bulkBar = UIView()
    private let bulkCountLabel = UILabel()
    private let bulkSelectAllButton = RippleButton()
    private let bulkClearButton = RippleButton()
    private let bulkProtectButton = RippleButton()
    private let bulkUnprotectButton = RippleButton()
    private let bulkTrashButton = RippleButton()
    /// 操作帯の高さ (2段組み。ゴミ箱と同じ)。
    private static let bulkBarHeight: CGFloat = 104
    /// 複数選択の状態 (この画面の中だけに持ち、保存はしない)。
    /// ページをまたいで選べるよう、選んだ録画そのものを ID で
    /// 引ける形で持つ。
    private var isSelectionMode = false
    private var selectedProgramsByID: [Int: RecordedProgram] = [:]
    /// なぞって選択の途中経過。選択中にカードへ触れたまま指を動かした
    /// とき、触れた行を起点に範囲で選択を付け外しするための控え。
    /// なぞれるのは表示中のページの中だけ (ページまたぎの選択は
    /// 今までどおりタップと「すべて選択」で行う)。
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
    /// 選択中は一覧のスクロールと同時に動きを見て、指の勢いで
    /// 使い分ける: 速い動き (フリック) はスクロールに譲り、
    /// ゆっくりした動きはなぞり選択として取り込む。なぞり選択に
    /// 決まったら一覧を指に付いて動かさず、指が画面の端に来た
    /// ときだけ自動で少しずつ流す (ゴミ箱と同じ)。
    private let dragSelectionGesture = UIPanGestureRecognizer()
    /// 触れた行の控え。スクロールか なぞり選択か決まるまで、
    /// 起点の行はここに置く (決まった時点で dragAnchorRow へ移す)。
    private var dragPendingAnchorRow: Int?
    /// この指の動きをなぞり選択として取り込んだかどうか。
    private var dragCommitted = false
    /// この指の動きをスクロールに譲ったかどうか。譲ったあとは
    /// 指を離すまで、なぞり選択には切り替えない。
    private var dragAbandoned = false
    /// スクロールか なぞり選択かを決めるまでの、指の移動量。
    private static let dragDecisionDistance: CGFloat = 16
    /// これより速い指の動きはスクロールとして扱う速さ (1秒あたり)。
    private static let dragScrollSpeedThreshold: CGFloat = 600
    /// 指の位置 (画面全体での座標)。端に近いかの判定に使う。
    private var dragFingerPoint: CGPoint?
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
    /// 一覧の上に置くページ送り (見出し行の下に固定表示)。
    private let topPaginationView = PaginationView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    /// 一覧の下に置くページ送り (テーブルの末尾に付ける)。
    private let bottomPaginationView = PaginationView()
    private var bottomPaginationFooter: UIView?
    private let refreshControl = UIRefreshControl()
    private let statusLabel = UILabel()

    /// いま表示しているページの番組 (最大で pageSize 件)。
    private var programs: [RecordedProgram] = []
    /// 表示上の全件数 (フィルタ中は絞り込み後の件数。Web 版と同じ)。
    private var total = 0
    private var currentPage = 1
    private var isLoading = false
    private var loadedBaseURLString: String?
    /// 「未視聴のみ」フィルタが有効か。
    private var unwatchedOnly = false
    /// 「保護中のみ」フィルタが有効か。
    private var protectedOnly = false
    /// 並び順。サーバー側の指定で、"desc" が新しい順、"asc" が古い順 (既定は新しい順)。
    private var sortOrder = "desc"
    /// 起動直後の最初の読み込みで復元するページ。復元が済んだら nil にする。
    private var pendingRestorePage: Int?

    // MARK: スクロール位置の保存と復元

    /// スクロール位置の目印: 画面の上端付近に見えている録画の ID と、
    /// その録画の上端から画面の上端までの距離 (Web 版と同じ持ち方)。
    /// 目印がどのページのものかも一緒に持つ。
    private var scrollMarkerProgramID: Int?
    private var scrollMarkerOffset: CGFloat = 0
    private var scrollMarkerPage: Int?
    /// 目印が使えないときのための、ピクセルの控え。
    private var scrollFallbackTop: CGFloat = 0
    /// 起動時に読み戻した復元待ちのスクロール位置と、その保存時点の
    /// 表示条件 (ページ・並び順・両フィルタ)。最初の読み込みの後に
    /// 条件が一致するときだけ戻す。
    private var pendingScrollRestore: (programID: Int, offset: CGFloat, fallbackTop: CGFloat,
                                       page: Int, order: String,
                                       unwatchedOnly: Bool, protectedOnly: Bool)?
    /// スクロール位置の保存が有効か。最初の読み込みと復元が終わるまで
    /// 無効にしておき、読み込み中の先頭への移動で保存済みの位置を
    /// 潰さないようにする。
    private var scrollSaveEnabled = false
    /// 復元の合わせ直しが動いているか (その間は保存しない)。
    private var isScrollRestoring = false
    private var scrollRestoreTimer: Timer?
    private var scrollRestoreTicks = 0
    /// スクロール中の保存の間引き用。
    private var lastScrollSaveAt: TimeInterval = 0
    /// フィルタか検索が1つでも有効か。有効なときは全件取得して
    /// 端末側で絞り込む (サーバー側のページ分けは使わない)。
    private var isFilterActive: Bool { unwatchedOnly || protectedOnly || !searchText.isEmpty }
    /// フィルタ中に全件取得して絞り込んだ結果。ページ表示はここから切り出す。
    private var filteredPrograms: [RecordedProgram] = []
    /// 検索の言葉 (前後の空白を除いたもの)。空なら検索していない。
    /// 画面の中だけに持ち、保存はしない (Web 版の一覧の検索欄と同じ)。
    private var searchText = ""
    /// 絞り込み用に取得した全件の控え。検索の言葉が変わるたびに
    /// 通信し直さず、この控えから絞り直すために持つ。
    private var allCollectedPrograms: [RecordedProgram] = []
    /// 全件の控えが今の並び順で使えるか。並び替えや読み直しでは
    /// 並びが変わるため、そのたびに false に戻す。
    private var hasCollectedAllPrograms = false
    /// 読み込み中に検索の言葉が変わったときの控え。読み込みが終わって
    /// から絞り直す。
    private var pendingSearchReload = false

    private let thumbnailCache = NSCache<NSNumber, UIImage>()

    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (再取得を避ける)。
    /// 生放送一覧と同じ方式。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []

    init() {
        super.init(nibName: nil, bundle: nil)
        // この画面ではナビゲーションバーを隠すため見出しには出ない。
        // 押し込んだ先の画面の戻るボタンの文字としてだけ残してある。
        title = "録画番組"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        // 先頭まわり (ロゴ帯・容量行・見出し行・上のページ送り) は、Web 版の
        // スマホ縦と同じくページの先頭にあるだけで固定はされず、一覧と一緒に
        // スクロールして流れていく。そのため一式をテーブルの先頭に付ける
        // (下の installHeadContainer)。並びは Web 版と同じ
        // ロゴ帯 → 容量行 → 見出し行 → ページ送り → 一覧。
        // ロゴのタップでは Web 版のリンク先 (/tv/) に合わせて生放送タブへ移る。
        headerView.onLogoTap = { [weak self] in
            self?.mainTabBarController?.selectedIndex = 0
        }

        // 容量行。Web 版ではロゴ帯の下・見出し行の上に右寄せで出る
        // (StorageStatusText、文字 13.5px、不透明度 0.75、下に 4px の余白)。
        // アイコンは Web 版の database (16px) で、字形の近い SF Symbol で近似する。
        storageIconView.image = UIImage(
            systemName: "cylinder",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)
        )?.withTintColor(AppPalette.text.withAlphaComponent(0.75), renderingMode: .alwaysOriginal)
        storageIconView.contentMode = .scaleAspectFit
        storageRowView.addSubview(storageIconView)
        storageLabel.font = .scaledSystemFont(ofSize: 13.5)
        storageLabel.textColor = AppPalette.text.withAlphaComponent(0.75)
        storageLabel.numberOfLines = 1
        storageLabel.lineBreakMode = .byTruncatingTail
        storageRowView.addSubview(storageLabel)
        // 録画結果の入口は容量行の左端に置く (Web 版の並びと同じ:
        // 左に録画結果、右に容量)。文字は容量行に合わせて 13.5px。
        // 絵は Web 版のクリップボードの印に近い標準アイコンで近似する。
        recordingResultsButton.setTitle("録画結果", for: .normal)
        recordingResultsButton.setTitleColor(AppPalette.text.withAlphaComponent(0.85), for: .normal)
        recordingResultsButton.titleLabel?.font = .scaledSystemFont(ofSize: 13.5)
        recordingResultsButton.setImage(
            UIImage(systemName: "doc.on.clipboard",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))?
                .withTintColor(AppPalette.text.withAlphaComponent(0.85), renderingMode: .alwaysOriginal),
            for: .normal)
        recordingResultsButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        recordingResultsButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        recordingResultsButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        recordingResultsButton.addTarget(self, action: #selector(openRecordingResults), for: .touchUpInside)
        recordingResultsButton.isHidden = !AppEdition.recordingResultsEnabled
        storageRowView.addSubview(recordingResultsButton)

        // 見出し行。Web 版と同じく「録画番組一覧」の右に全件数を出し、
        // 右端にはゴミ箱への入口を置く (出すときだけ)。見出しの横に
        // Web 版にある戻る印 (＜) は、たつやさんの判断で付けない。
        // その下の行に、左端の選択のピルを置く。フィルタのボタンは
        // 最初はこの行に付けておき、置き場所は refreshHeadContainer で
        // ゴミ箱の入口の出し分けに合わせて決め直す。
        headContainerView.addSubview(listHeaderView)
        headContainerView.addSubview(selectFilterRowView)
        listTitleLabel.text = "録画番組一覧"
        listTitleLabel.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        listTitleLabel.textColor = AppPalette.text
        listTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(listTitleLabel)
        countLabel.font = .scaledSystemFont(ofSize: 13)
        countLabel.textColor = AppPalette.metaText
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        listHeaderView.addSubview(countLabel)
        // フィルタのボタンは Web 版のスマホ縦と同じく、漏斗の印＋「フィルタ」の
        // 文字＋ON 件数の印で、押すとメニューが開く丸いボタン。
        // フィルタが1つでも ON のときは Web 版と同じくアクセント色で塗る。
        filterButton.setTitle("フィルタ", for: .normal)
        filterButton.titleLabel?.font = .scaledSystemFont(ofSize: 13)
        let filterSymbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        filterButton.setImage(
            UIImage(systemName: "line.3.horizontal.decrease.circle.fill", withConfiguration: filterSymbol),
            for: .normal)
        filterButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        filterButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        filterButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        filterButton.layer.cornerRadius = 14
        filterButton.layer.borderWidth = 1
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        selectFilterRowView.addSubview(filterButton)
        // ON 件数の印はボタンの右上に重ねる小さな丸。0件のときは出さない。
        filterBadgeLabel.font = .scaledSystemFont(ofSize: 10, weight: .bold)
        filterBadgeLabel.textAlignment = .center
        filterBadgeLabel.backgroundColor = .white
        filterBadgeLabel.textColor = AppPalette.accent
        filterBadgeLabel.layer.cornerRadius = 8
        filterBadgeLabel.clipsToBounds = true
        filterBadgeLabel.isHidden = true
        filterBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        selectFilterRowView.addSubview(filterBadgeLabel)
        // ゴミ箱への入口。見出し行の右端に置く小さなリンクで、
        // アイコン (アーカイブの箱) +「ゴミ箱を開く」、文字 14px。
        trashLinkButton.setTitle("ゴミ箱を開く", for: .normal)
        trashLinkButton.setTitleColor(AppPalette.text.withAlphaComponent(0.85), for: .normal)
        trashLinkButton.titleLabel?.font = .scaledSystemFont(ofSize: 14)
        let trashSymbol = UIImage.SymbolConfiguration(pointSize: 13)
        trashLinkButton.setImage(
            UIImage(systemName: "archivebox", withConfiguration: trashSymbol)?
                .withTintColor(AppPalette.text.withAlphaComponent(0.85), renderingMode: .alwaysOriginal),
            for: .normal)
        trashLinkButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        trashLinkButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        trashLinkButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        trashLinkButton.addTarget(self, action: #selector(openTrash), for: .touchUpInside)
        trashLinkButton.translatesAutoresizingMaskIntoConstraints = false
        trashLinkButton.isHidden = true
        listHeaderView.addSubview(trashLinkButton)
        // 複数選択の入り口。ゴミ箱の「選択する」のピルと同じ見た目で、
        // 見出し行の下の行の左端に置く (並びの制約は下の
        // NSLayoutConstraint.activate、出し分けは refreshHeadContainer)。
        selectButton.setTitle("選択する", for: .normal)
        selectButton.setTitleColor(AppPalette.text, for: .normal)
        selectButton.titleLabel?.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        selectButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        selectButton.layer.cornerRadius = 15
        selectButton.layer.borderWidth = 1
        selectButton.layer.borderColor = AppPalette.fieldBorder.cgColor
        selectButton.addTarget(self, action: #selector(toggleSelectionMode), for: .touchUpInside)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.isHidden = true
        selectFilterRowView.addSubview(selectButton)
        // 前回保存した表示状態 (ページ・並び順・両フィルタ) を復元する。
        restoreViewState()
        updateFilterButtonAppearance()

        // 上のページ送りは見出し行の下に置き、先頭まわり一式と一緒にスクロールさせる。
        topPaginationView.onPageSelected = { [weak self] page in
            self?.goToPage(page)
        }
        headContainerView.addSubview(topPaginationView)
        // 下のページ送りはテーブルの末尾に付ける。幅はレイアウト時に合わせ直す。
        bottomPaginationView.onPageSelected = { [weak self] page in
            self?.goToPage(page)
        }
        let footer = UIView()
        footer.addSubview(bottomPaginationView)
        bottomPaginationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomPaginationView.topAnchor.constraint(equalTo: footer.topAnchor),
            bottomPaginationView.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            bottomPaginationView.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            bottomPaginationView.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
        ])
        bottomPaginationFooter = footer
        tableView.tableFooterView = footer

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseID)
        // 行の高さはカードの中身 (題名・説明の行数) に合わせて自動で決める。
        // 推定値は Web 版カードのスマホ縦の intrinsic height (115px) + カード間隔 (10px)。
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 125
        tableView.backgroundColor = AppPalette.background
        tableView.separatorStyle = .none
        // 一覧の下端にもカード間隔と同じ余白を置く。
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.tintColor = AppPalette.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        // 選択中になぞって連続で選べるよう、なぞり選択専用の
        // 指の動きの受け口を付ける。選択中だけ有効にし、それ以外
        // では一覧のスクロールに触れない。選択中は一覧のスクロール
        // と同時に動きを見て、勢いで使い分ける
        // (handleDragSelection を参照)。
        dragSelectionGesture.addTarget(
            self, action: #selector(handleDragSelection(_:)))
        dragSelectionGesture.delegate = self
        dragSelectionGesture.isEnabled = false
        tableView.addGestureRecognizer(dragSelectionGesture)
        view.addSubview(tableView)
        // フィルタのボタンの置き場所の制約を用意する。有効化の切り替えは
        // refreshHeadContainer で行う (installHeadContainer から呼ばれる
        // ため、呼ばれる前に用意しておく)。
        filterInHeaderConstraints = [
            filterButton.trailingAnchor.constraint(equalTo: listHeaderView.trailingAnchor, constant: -12),
            filterButton.centerYAnchor.constraint(equalTo: listHeaderView.centerYAnchor),
            filterButton.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
        ]
        filterInRowConstraints = [
            filterButton.trailingAnchor.constraint(equalTo: selectFilterRowView.trailingAnchor, constant: -12),
            filterButton.centerYAnchor.constraint(equalTo: selectFilterRowView.centerYAnchor),
            filterButton.leadingAnchor.constraint(greaterThanOrEqualTo: selectButton.trailingAnchor, constant: 8),
        ]
        filterBadgeConstraints = [
            filterBadgeLabel.widthAnchor.constraint(equalToConstant: 16),
            filterBadgeLabel.heightAnchor.constraint(equalToConstant: 16),
            filterBadgeLabel.centerXAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: -2),
            filterBadgeLabel.centerYAnchor.constraint(equalTo: filterButton.topAnchor, constant: 2),
        ]
        installHeadContainer()
        buildSearchBar()

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        buildBulkBar()

        NSLayoutConstraint.activate([
            listTitleLabel.leadingAnchor.constraint(equalTo: listHeaderView.leadingAnchor, constant: 12),
            listTitleLabel.centerYAnchor.constraint(equalTo: listHeaderView.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: listTitleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: listHeaderView.centerYAnchor),
            trashLinkButton.trailingAnchor.constraint(equalTo: listHeaderView.trailingAnchor, constant: -12),
            trashLinkButton.centerYAnchor.constraint(equalTo: listHeaderView.centerYAnchor),
            trashLinkButton.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
            selectButton.leadingAnchor.constraint(equalTo: selectFilterRowView.leadingAnchor, constant: 12),
            selectButton.centerYAnchor.constraint(equalTo: selectFilterRowView.centerYAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        updatePagination()
    }

    /// 選択中の操作帯を作る (画面の下部に固定、タブバーの上。ゴミ箱と同じ作り)。
    /// 並びはゴミ箱と同じ: 上の段に選んだ件数・すべて選択・選択を解除、
    /// 下の段に操作のボタン。操作のボタンは、使える機能のものだけを出す
    /// (出し分けは updateBulkBar)。幅の都合で2段に分ける。
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
        // 操作のボタンの見た目は、ゴミ箱の操作帯のボタンと揃える。
        bulkProtectButton.setTitle("保護する", for: .normal)
        bulkUnprotectButton.setTitle("保護を外す", for: .normal)
        bulkTrashButton.setTitle("ゴミ箱に移動する", for: .normal)
        for button in [bulkProtectButton, bulkUnprotectButton, bulkTrashButton] {
            button.setTitleColor(AppPalette.text, for: .normal)
            button.titleLabel?.font = .scaledSystemFont(ofSize: 13.5, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            button.layer.cornerRadius = 4
            button.layer.borderWidth = 1
            button.layer.borderColor = AppPalette.fieldBorder.cgColor
        }
        bulkProtectButton.addTarget(self, action: #selector(bulkProtect), for: .touchUpInside)
        bulkUnprotectButton.addTarget(self, action: #selector(bulkUnprotect), for: .touchUpInside)
        bulkTrashButton.addTarget(self, action: #selector(bulkMoveToTrash), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [
            bulkCountLabel, UIView(), bulkSelectAllButton, bulkClearButton,
        ])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 4
        let bottomRow = UIStackView(arrangedSubviews: [
            UIView(), bulkProtectButton, bulkUnprotectButton, bulkTrashButton,
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

    /// 検索の入り口と検索欄を作る。入り口 (虫眼鏡) はロゴ帯の右端に重ね、
    /// 検索欄はロゴ帯の行全体を覆う形で重ねる (並びは
    /// refreshHeadContainer で決める)。検索欄の中身は Web 版のヘッダーと
    /// 同じ並び: 左に虫眼鏡の印、入力欄、右端に閉じる印 (×)。
    private func buildSearchBar() {
        searchButton.setImage(
            UIImage(systemName: "magnifyingglass",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 24))?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        searchButton.accessibilityLabel = "検索"
        searchButton.addTarget(self, action: #selector(openSearch), for: .touchUpInside)
        headContainerView.addSubview(searchButton)

        searchBarView.backgroundColor = AppPalette.background
        searchBarView.isHidden = true
        searchIconView.image = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal)
        searchIconView.contentMode = .scaleAspectFit
        searchBarView.addSubview(searchIconView)
        // 案内文は Web 版と同じ「録画番組やシリーズを検索...」。
        searchField.attributedPlaceholder = NSAttributedString(
            string: "録画番組やシリーズを検索...",
            attributes: [.foregroundColor: AppPalette.secondaryText])
        searchField.font = .scaledSystemFont(ofSize: 15)
        searchField.textColor = AppPalette.text
        searchField.tintColor = AppPalette.accent
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchFieldChanged), for: .editingChanged)
        searchBarView.addSubview(searchField)
        searchCloseButton.setImage(
            UIImage(systemName: "xmark",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        searchCloseButton.accessibilityLabel = "検索を閉じる"
        searchCloseButton.addTarget(self, action: #selector(closeSearch), for: .touchUpInside)
        searchBarView.addSubview(searchCloseButton)
        headContainerView.addSubview(searchBarView)

        // 検索中は、画面左端からの右へのなぞりでも検索を閉じられる
        // ようにする (「×」と同じ動き)。検索欄が開いている間だけ有効。
        searchEdgePanGesture.edges = .left
        searchEdgePanGesture.addTarget(self, action: #selector(searchEdgePanned(_:)))
        searchEdgePanGesture.isEnabled = false
        tableView.addGestureRecognizer(searchEdgePanGesture)
    }

    /// 先頭まわり一式の高さ。容量行は取得できたときだけ 22 (文字の行 18 + 下の余白 4)。
    /// 見出し行は 44、その下の選択とフィルタの行は出すときだけ高さを取る。
    private var headContainerHeight: CGFloat {
        SPHeaderView.height + (showsStorageRow ? 22 : 0)
            + 44 + (showsSelectFilterRow ? Self.selectFilterRowHeight : 0)
            + PaginationView.preferredHeight
    }

    /// 先頭まわり一式をテーブルの先頭に付ける。テーブルの先頭に付けたビューは
    /// 一覧と一緒にスクロールする (tableHeaderView の仕組み) ため、Web 版の
    /// スマホ縦と同じく先頭まわりがスクロールで流れていく形になる。
    private func installHeadContainer() {
        headContainerView.addSubview(headerView)
        headContainerView.addSubview(storageRowView)
        refreshHeadContainer()
    }

    /// 先頭まわり一式の並びと大きさを決め直して、テーブルへ付け直す。
    /// 並びは ロゴ帯 → 容量行 → 見出し行 → 選択とフィルタの行 → 上の
    /// ページ送り。ゴミ箱の入口は見出し行の右端に置く。フィルタの
    /// ボタンは、ゴミ箱の入口が出るときは下の行の右端、出ないときは
    /// 見出し行の右端に置く。下の行は、出すものが無いときは無くす。
    private func refreshHeadContainer() {
        let width = tableView.bounds.width
        let storageHeight: CGFloat = showsStorageRow ? 22 : 0
        headerView.frame = CGRect(x: 0, y: 0, width: width, height: SPHeaderView.height)
        storageRowView.frame = CGRect(x: 0, y: SPHeaderView.height, width: width, height: storageHeight)
        // 録画結果の入口は容量行の左端 (左に 8px)。容量の表示は右寄せで、
        // 容量が取れていないときは容量側だけ隠す。
        if AppEdition.recordingResultsEnabled {
            recordingResultsButton.sizeToFit()
            let buttonWidth = recordingResultsButton.frame.width
            recordingResultsButton.frame = CGRect(
                x: 8, y: 0, width: buttonWidth, height: storageHeight)
        }
        storageIconView.isHidden = storageStatus == nil
        storageLabel.isHidden = storageStatus == nil
        // ゴミ箱の入口は見出し行の右端 (並びは組み立て時の制約)。
        // 出すときだけ見せる。
        trashLinkButton.isHidden = !showsTrashLink
        // フィルタのボタンの置き場所。ゴミ箱の入口が出るときは見出し行の
        // 下の行の右端、出ないときは見出し行の右端に置く。ON 件数の印も
        // 一緒に付け替える。
        let filterParent: UIView = showsTrashLink ? selectFilterRowView : listHeaderView
        if filterButton.superview !== filterParent {
            filterButton.removeFromSuperview()
            filterParent.addSubview(filterButton)
            filterBadgeLabel.removeFromSuperview()
            filterParent.addSubview(filterBadgeLabel)
        }
        NSLayoutConstraint.deactivate(
            filterInHeaderConstraints + filterInRowConstraints + filterBadgeConstraints)
        NSLayoutConstraint.activate(filterBadgeConstraints)
        NSLayoutConstraint.activate(
            showsTrashLink ? filterInRowConstraints : filterInHeaderConstraints)
        // 容量行の中身は右寄せ (Web 版と同じ)。右端はカードの余白 (8px) に合わせ、
        // アイコン (16px) と文字の間は 6px。
        storageLabel.sizeToFit()
        let labelWidth = min(storageLabel.frame.width, max(0, width - 8 - 16 - 6 - 8))
        storageLabel.frame = CGRect(x: width - 8 - labelWidth, y: 0, width: labelWidth, height: 18)
        storageIconView.frame = CGRect(x: width - 8 - labelWidth - 6 - 16, y: 1, width: 16, height: 16)
        storageRowView.isHidden = !showsStorageRow
        let listHeaderY = SPHeaderView.height + storageHeight
        listHeaderView.frame = CGRect(x: 0, y: listHeaderY, width: width, height: 44)
        // 見出し行の下の行。左に複数選択のピルを置き、フィルタのボタンは
        // ゴミ箱の入口が出るときだけ右に置く (並びは組み立て時の制約)。
        // 行に出すものが無いときは、行自体をなくす。
        let selectFilterRowY = listHeaderY + 44
        let selectFilterRowHeight: CGFloat = showsSelectFilterRow ? Self.selectFilterRowHeight : 0
        selectFilterRowView.frame = CGRect(
            x: 0, y: selectFilterRowY, width: width, height: selectFilterRowHeight)
        selectFilterRowView.isHidden = !showsSelectFilterRow
        selectButton.isHidden = !showsSelectButton
        topPaginationView.frame = CGRect(
            x: 0, y: selectFilterRowY + selectFilterRowHeight,
            width: width, height: PaginationView.preferredHeight)
        // 検索の入り口はロゴ帯の右端 (Web 版のヘッダーと同じ位置)。
        // 縦位置はロゴの中央 (上端から 31px) に合わせる。
        searchButton.frame = CGRect(x: width - 16 - 44, y: 31 - 22, width: 44, height: 44)
        searchButton.isHidden = isSearchBarOpen
        // 検索欄はロゴ帯の行全体を覆う。左の虫眼鏡の印 (20px)、
        // 右端の閉じる印、その間が入力欄。
        searchBarView.frame = CGRect(x: 0, y: 0, width: width, height: SPHeaderView.height)
        searchBarView.isHidden = !isSearchBarOpen
        searchIconView.frame = CGRect(x: 18, y: 31 - 10, width: 20, height: 20)
        searchCloseButton.frame = CGRect(x: width - 16 - 44, y: 31 - 22, width: 44, height: 44)
        searchField.frame = CGRect(
            x: 46, y: 31 - 18, width: max(0, width - 16 - 44 - 46 - 4), height: 36)
        // 端からのなぞりで閉じる受け口は、検索欄が開いている間だけ。
        searchEdgePanGesture.isEnabled = isSearchBarOpen
        headContainerView.frame = CGRect(x: 0, y: 0, width: width, height: headContainerHeight)
        tableView.tableHeaderView = headContainerView
    }

    /// 管理者かどうかを取り直す。ゴミ箱まわり (改造サーバー前提の機能) の
    /// 出し分けに使うため、ゴミ箱のトグルがオンでログインしているとき
    /// だけ通信する。
    /// 変わっていたら先頭まわりを組み直して、入口の行の出し隠しを反映する。
    private func refreshAdminState() {
        guard AppEdition.trashEnabled, SettingsStore.shared.isLoggedIn else {
            if isAdminUser {
                isAdminUser = false
                refreshHeadContainer()
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let user = try? await APIClient.shared.fetchCurrentUser()
            let isAdmin = user?.is_admin ?? false
            if isAdmin != self.isAdminUser {
                self.isAdminUser = isAdmin
                self.refreshHeadContainer()
            }
        }
    }

    /// ゴミ箱の画面を開く。
    @objc private func openTrash() {
        navigationController?.pushViewController(TrashViewController(), animated: true)
    }

    /// 録画結果一覧の画面を開く (拡張版だけ)。
    @objc private func openRecordingResults() {
        navigationController?.pushViewController(RecordingResultsViewController(), animated: true)
    }

    /// 容量情報を取り直して容量行に反映する。取得できないときは Web 版と同じく
    /// 容量行自体を出さない。
    private func refreshStorageStatus() {
        guard SettingsStore.shared.isConfigured else {
            applyStorageStatus(nil)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let status = await APIClient.shared.fetchStorageStatus()
            self.applyStorageStatus(status)
        }
    }

    private func applyStorageStatus(_ status: StorageStatus?) {
        storageStatus = status
        if let status {
            storageLabel.text = "録画 \(Self.formatBytes(status.recordings_bytes)) / "
                + "\(Self.formatBytes(status.total_bytes))（空き \(Self.formatBytes(status.free_bytes))）"
        }
        refreshHeadContainer()
    }

    /// バイト数を人が読みやすい単位にする (Web 版の formatBytes と同じ:
    /// 1TB 以上は TB、1GB 以上は GB、1MB 以上は MB、いずれも小数1桁)。
    private static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        let tb = 1024.0 * 1024 * 1024 * 1024
        let gb = 1024.0 * 1024 * 1024
        let mb = 1024.0 * 1024
        if value >= tb { return String(format: "%.1f TB", value / tb) }
        if value >= gb { return String(format: "%.1f GB", value / gb) }
        if value >= mb { return String(format: "%.1f MB", value / mb) }
        return "\(bytes) B"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // テーブルの先頭に付けた先頭まわり一式は、幅と高さをテーブル幅に合わせ直す
        // (tableHeaderView は枠の大きさで幅と高さが決まるため)。
        let headSize = CGSize(width: tableView.bounds.width, height: headContainerHeight)
        if headContainerView.frame.size != headSize {
            refreshHeadContainer()
        }
        // テーブルの末尾に付けたページ送りは、幅と高さをテーブル幅に合わせ直す
        // (tableFooterView は枠の大きさで高さが決まるため)。
        guard let footer = bottomPaginationFooter else { return }
        let size = CGSize(width: tableView.bounds.width, height: PaginationView.preferredHeight)
        if footer.frame.size != size {
            footer.frame = CGRect(origin: .zero, size: size)
            tableView.tableFooterView = footer
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Web 版のスマホ縦と同じく、画面幅 380 以下では「フィルタ」の文字を
        // 隠して印と ON 件数だけにする。
        let title = view.bounds.width <= 380 ? nil : "フィルタ"
        if filterButton.title(for: .normal) != title {
            filterButton.setTitle(title, for: .normal)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 先頭画面ではシステムのナビゲーションバー (ページ名の見出し) を隠し、
        // Web 版のスマホ縦と同じく自前のヘッダーだけを出す。
        // 押し込んだ先の再生画面では戻るボタンが要るため、隠すのはこの画面の間だけ。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 接続先が変わっていたら読み直す。初回は必ず読む。
        let current = SettingsStore.shared.baseURL?.absoluteString
        if programs.isEmpty || current != loadedBaseURLString {
            refresh()
        }
        // ゴミ箱まわりの出し分けのため、管理者かどうかも開くたびに取り直す。
        refreshAdminState()
        // 容量情報は開くたびに取り直し、開いている間は Web 版と同じ30秒間隔で更新する。
        refreshStorageStatus()
        storageTimer?.invalidate()
        storageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshStorageStatus()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 再生画面など、押し込んだ先ではナビゲーションバーを元に戻す。
        navigationController?.setNavigationBarHidden(false, animated: animated)
        // 検索欄を開いたまま離れたら、キーボードだけは閉じる
        // (検索欄と絞り込みは戻ってきたときのために残す)。
        searchField.resignFirstResponder()
        storageTimer?.invalidate()
        storageTimer = nil
        // 離れる前に、いまのスクロール位置を目印として保存する
        // (Web 版の画面を離れるときの保存と同じ)。
        scrollRestoreTimer?.invalidate()
        scrollRestoreTimer = nil
        isScrollRestoring = false
        if scrollSaveEnabled {
            captureScrollMarker()
            saveViewState()
        }
    }

    @objc private func refresh() {
        // なぞり選択の最中は読み直さない (並びが入れ替わると
        // 選択の範囲が崩れるため)。更新の表示だけ止めて戻る。
        guard !isDragSelecting else {
            refreshControl.endRefreshing()
            return
        }
        // 読み込み中なら二重に始めない (更新中の表示だけ止めて戻る)。
        guard !isLoading else {
            refreshControl.endRefreshing()
            return
        }
        // 読み直しでは選択中を終える (選んでいた録画が残っているとは
        // 限らないため)。
        if isSelectionMode { exitSelectionMode() }
        // 接続先が変わっていたら、前の接続先のロゴは使い回さない (生放送一覧と同じ)。
        if SettingsStore.shared.baseURL?.absoluteString != loadedBaseURLString {
            logoCache.removeAllObjects()
            failedLogoIDs.removeAll()
        }
        // 最初の読み込みだけは、保存しておいたページを復元する。
        // それ以外 (引っ張って更新など) は、フィルタと並び順の状態を保ったまま
        // 1ページ目に戻る (Web 版と同じ)。
        let page = pendingRestorePage ?? 1
        pendingRestorePage = nil
        loadPage(page)
    }

    /// ページ送りから指定されたページへ移る。
    private func goToPage(_ page: Int) {
        guard page != currentPage, !isLoading else { return }
        if isFilterActive {
            // フィルタ中は取得済みの結果から切り出すだけなので、通信はしない。
            currentPage = page
            showFilteredPage()
            saveViewState()
        } else {
            loadPage(page)
        }
    }

    /// 指定ページを読み込む (フィルタ中は全件取得して絞り込んでから切り出す)。
    private func loadPage(_ page: Int) {
        guard !isLoading else { return }
        guard SettingsStore.shared.isConfigured else {
            statusLabel.text = "設定タブで接続先 URL を設定してください。"
            return
        }
        isLoading = true
        updatePagination()
        if isFilterActive {
            loadAllForFilter(targetPage: page)
        } else {
            Task { [weak self] in
                guard let self else { return }
                do {
                    var response = try await APIClient.shared.fetchVideos(page: page, order: self.sortOrder)
                    // 復元したページが総ページ数を超えていたら、最後のページを取り直す
                    // (録画が減ってページが無くなっている場合)。
                    let lastPage = max(1, Int(ceil(Double(response.total) / Double(Self.pageSize))))
                    if page > lastPage {
                        response = try await APIClient.shared.fetchVideos(page: lastPage, order: self.sortOrder)
                        self.currentPage = lastPage
                    } else {
                        self.currentPage = page
                    }
                    self.loadedBaseURLString = SettingsStore.shared.baseURL?.absoluteString
                    self.total = response.total
                    self.programs = response.recorded_programs
                    // サーバー側のページ分けで読んだので、全件の控えは使えない。
                    self.hasCollectedAllPrograms = false
                    self.allCollectedPrograms = []
                    self.applyLoadedPage()
                    self.saveViewState()
                    self.restoreScrollPositionIfNeeded()
                } catch {
                    if self.programs.isEmpty {
                        self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。\n(\(error.localizedDescription))"
                    }
                }
                self.isLoading = false
                self.refreshControl.endRefreshing()
                self.updatePagination()
                self.applyPendingSearchReloadIfNeeded()
            }
        }
    }

    /// フィルタ用に全ページ (Web 版と同じ最大50ページ) を、サーバーの並び順の
    /// まま取得して絞り込み、指定ページを表示する。
    /// 絞り込みは端末側で、並びはサーバーの並びをそのまま保つ (Web 版と同じ)。
    private func loadAllForFilter(targetPage: Int) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var collected: [RecordedProgram] = []
                var page = 1
                var allTotal = Int.max
                while collected.count < allTotal, page <= 50 {
                    let response = try await APIClient.shared.fetchVideos(page: page, order: self.sortOrder)
                    self.loadedBaseURLString = SettingsStore.shared.baseURL?.absoluteString
                    allTotal = response.total
                    collected += response.recorded_programs
                    if response.recorded_programs.isEmpty { break }
                    page += 1
                }
                // 取得した全件は控えておき、検索の言葉が変わったときは
                // 通信し直さず手元で絞り直せるようにする。
                self.allCollectedPrograms = collected
                self.hasCollectedAllPrograms = true
                self.filteredPrograms = collected.filter {
                    self.matchesFilters($0) && self.matchesSearch($0)
                }
                // Web 版と同じく、件数表示は絞り込み後の件数にする。
                self.total = self.filteredPrograms.count
                // 復元したページが絞り込み後のページ数を超えていたら、最後のページにする。
                self.currentPage = min(max(targetPage, 1), self.totalPages)
                self.showFilteredPage()
                self.saveViewState()
                self.restoreScrollPositionIfNeeded()
            } catch {
                if self.programs.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。\n(\(error.localizedDescription))"
                }
            }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            self.updatePagination()
            self.applyPendingSearchReloadIfNeeded()
        }
    }

    /// 絞り込み済みの結果から、いまのページの分を切り出して表示する。
    private func showFilteredPage() {
        let start = (currentPage - 1) * Self.pageSize
        if start < filteredPrograms.count {
            programs = Array(filteredPrograms[start ..< min(start + Self.pageSize, filteredPrograms.count)])
        } else {
            programs = []
        }
        applyLoadedPage()
    }

    /// 読み込み後の共通の反映。一覧を先頭に戻し、件数表示を更新する。
    private func applyLoadedPage() {
        if programs.isEmpty {
            // 検索中で1件も無いときは、Web 版の検索結果と同じ文面にする。
            statusLabel.text = searchText.isEmpty
                ? "録画番組がありません。"
                : "「\(searchText)」に一致する録画番組は見つかりませんでした。"
        } else {
            statusLabel.text = nil
        }
        countLabel.text = total > 0 ? "\(total)件" : nil
        // 一覧の中身が変わると「選択する」のピルの出し分けも変わるため、
        // 先頭まわりを組み直す。
        refreshHeadContainer()
        tableView.reloadData()
        // ページの切り替えでは一覧の先頭に戻る。
        tableView.setContentOffset(.zero, animated: false)
        updatePagination()
    }

    /// 総ページ数 (最低1)。
    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(Self.pageSize))))
    }

    /// 上下両方のページ送りに、いまのページ状態を反映する。
    private func updatePagination() {
        for pagination in [topPaginationView, bottomPaginationView] {
            pagination.update(currentPage: currentPage, totalPages: totalPages, isEnabled: !isLoading)
            // Web 版と同じく、番組が1件も無いときはページ送りを出さない。
            pagination.isHidden = total == 0
        }
    }

    // MARK: - フィルタと並び替え

    /// フィルタボタンのメニューを、いまの状態に合わせて作り直す。
    /// 中身は Web 版のスマホ縦のメニューと同じ並び:
    /// 未視聴のみ／保護中のみ (トグル) → 区切り → 新しい順／古い順 (並び替え)。
    /// 拡張版ではさらに区切りの下に「今日のハイライト」を足す
    /// (Web 版では録画一覧の見出し横のチップボタンだが、アプリでは
    /// このメニューに寄せる。絞り込みではなく別の画面が開く)。
    private func makeFilterMenu() -> UIMenu {
        let unwatchedAction = UIAction(
            title: "未視聴のみ",
            state: unwatchedOnly ? .on : .off
        ) { [weak self] _ in
            self?.toggleUnwatchedOnly()
        }
        // トグルは押してもメニューを閉じない (Web 版のメニューと同じ)。
        unwatchedAction.attributes.insert(.keepsMenuPresented)
        let protectedAction = UIAction(
            title: "保護中のみ",
            state: protectedOnly ? .on : .off
        ) { [weak self] _ in
            self?.toggleProtectedOnly()
        }
        protectedAction.attributes.insert(.keepsMenuPresented)
        let newestAction = UIAction(
            title: "新しい順",
            state: sortOrder == "desc" ? .on : .off
        ) { [weak self] _ in
            self?.changeSortOrder("desc")
        }
        let oldestAction = UIAction(
            title: "古い順",
            state: sortOrder == "asc" ? .on : .off
        ) { [weak self] _ in
            self?.changeSortOrder("asc")
        }
        // まとまりごとに区切りを入れるため、内側のメニューで分ける。
        // 「保護中のみ」は録画の保護のトグルがオンのときだけ
        // (オフでは保護の機能自体を出さない)。
        let filterActions: [UIAction] = AppEdition.protectionEnabled
            ? [unwatchedAction, protectedAction]
            : [unwatchedAction]
        var groups: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: filterActions),
            UIMenu(options: .displayInline, children: [newestAction, oldestAction]),
        ]
        // 「今日のハイライト」はアプリだけで完結するため常時出す
        // (拡張オプションのトグルからは外した)。
        let highlightsAction = UIAction(
            title: "今日のハイライト",
            image: UIImage(systemName: "flame")
        ) { [weak self] _ in
            self?.showHighlights()
        }
        groups.append(UIMenu(options: .displayInline, children: [highlightsAction]))
        return UIMenu(children: groups)
    }

    /// 「今日のハイライト」の画面を開く。再生が始まったら、
    /// 最初の区間の録画の再生画面へ移る (続きの区間は再生画面側が
    /// 順に進める)。
    private func showHighlights() {
        let highlights = HighlightsViewController()
        highlights.onStartPlayback = { [weak self] program in
            self?.navigationController?.pushViewController(
                PlayerViewController(program: program), animated: true)
        }
        present(highlights, animated: true)
    }

    /// 「未視聴のみ」フィルタの切り替え。変えたら1ページ目に戻る。
    private func toggleUnwatchedOnly() {
        guard !isLoading else { return }
        unwatchedOnly.toggle()
        reloadFromFirstPage()
    }

    /// 「保護中のみ」フィルタの切り替え。変えたら1ページ目に戻る。
    private func toggleProtectedOnly() {
        guard !isLoading else { return }
        protectedOnly.toggle()
        reloadFromFirstPage()
    }

    /// 並び替えの切り替え。変えたら1ページ目に戻る (Web 版と同じ)。
    private func changeSortOrder(_ order: String) {
        guard !isLoading, order != sortOrder else { return }
        sortOrder = order
        reloadFromFirstPage()
    }

    /// フィルタや並び順を変えたあとの共通の手続き。
    /// ボタンの見た目とメニューを作り直し、状態を保存して、1ページ目から読み直す。
    private func reloadFromFirstPage() {
        if isSelectionMode { exitSelectionMode() }
        updateFilterButtonAppearance()
        filteredPrograms = []
        // 並び順が変わると全件の控えの並びも合わなくなるため、捨てる。
        allCollectedPrograms = []
        hasCollectedAllPrograms = false
        total = 0
        pendingRestorePage = nil
        saveViewState(page: 1)
        loadPage(1)
    }

    /// フィルタボタンの見た目とメニューを、いまの状態に合わせる。
    /// ON のフィルタがあるときは Web 版と同じくボタンをアクセント色で塗り、
    /// 右上に ON の件数の印を出す。
    private func updateFilterButtonAppearance() {
        let onCount = (unwatchedOnly ? 1 : 0) + (protectedOnly ? 1 : 0)
        if onCount > 0 {
            filterButton.backgroundColor = AppPalette.accent
            filterButton.layer.borderColor = AppPalette.accent.cgColor
            filterButton.setTitleColor(.white, for: .normal)
            filterButton.tintColor = .white
            filterBadgeLabel.text = "\(onCount)"
            filterBadgeLabel.isHidden = false
        } else {
            filterButton.backgroundColor = .clear
            filterButton.layer.borderColor = AppPalette.fieldBorder.cgColor
            filterButton.setTitleColor(AppPalette.text, for: .normal)
            filterButton.tintColor = AppPalette.text
            filterBadgeLabel.isHidden = true
        }
        filterButton.menu = makeFilterMenu()
    }

    // MARK: - 検索

    /// 検索欄を開く。開いたらそのまま入力に移る (Web 版と同じ)。
    @objc private func openSearch() {
        guard !isSearchBarOpen else { return }
        isSearchBarOpen = true
        refreshHeadContainer()
        searchField.becomeFirstResponder()
    }

    /// 検索欄を閉じる。Web 版の「×」と同じく、入れた言葉を消して
    /// 欄を閉じる。アプリでは言葉そのものが絞り込みなので、
    /// 絞り込みも解けて全件に戻る。
    @objc private func closeSearch() {
        guard isSearchBarOpen else { return }
        isSearchBarOpen = false
        searchField.text = ""
        searchField.resignFirstResponder()
        refreshHeadContainer()
        if !searchText.isEmpty {
            searchText = ""
            applySearchChange()
        }
    }

    /// 画面左端からの右へのなぞり。検索を閉じる (「×」と同じ)。
    @objc private func searchEdgePanned(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .began else { return }
        closeSearch()
    }

    /// 入力のたびに呼ばれる。今の言葉でその場で絞り直す。
    /// 日本語の変換中は、確定してから反映する。
    @objc private func searchFieldChanged() {
        guard searchField.markedTextRange == nil else { return }
        let newText = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard newText != searchText else { return }
        searchText = newText
        applySearchChange()
    }

    /// 検索の言葉が変わったあとの共通の手続き。読み直しやフィルタの
    /// 変更と同じく、選択中なら終える。全件の控えが使えるときは
    /// 通信せず手元で絞り直し、無いときは1ページ目から読み直す。
    private func applySearchChange() {
        if isSelectionMode { exitSelectionMode() }
        pendingRestorePage = nil
        guard !isLoading else {
            pendingSearchReload = true
            return
        }
        if hasCollectedAllPrograms, isFilterActive {
            filteredPrograms = allCollectedPrograms.filter {
                matchesFilters($0) && matchesSearch($0)
            }
            total = filteredPrograms.count
            currentPage = 1
            showFilteredPage()
            updatePagination()
        } else {
            hasCollectedAllPrograms = false
            allCollectedPrograms = []
            loadPage(1)
        }
    }

    /// 読み込みが終わった時点で、読み込み中に変わった検索が残って
    /// いたら絞り直す (読み込みの完了側から呼ばれる)。
    private func applyPendingSearchReloadIfNeeded() {
        guard pendingSearchReload else { return }
        pendingSearchReload = false
        applySearchChange()
    }

    /// 検索の判定。題名とシリーズ名への部分一致 (大文字と小文字は
    /// 区別しない)。シリーズ名は、題名とは別に持っている番組だけ。
    private func matchesSearch(_ program: RecordedProgram) -> Bool {
        guard !searchText.isEmpty else { return true }
        if program.title.localizedCaseInsensitiveContains(searchText) { return true }
        if let seriesTitle = program.series_title,
           seriesTitle.localizedCaseInsensitiveContains(searchText) { return true }
        return false
    }

    // MARK: - 表示状態の保存と復元

    /// 表示状態 (ページ・並び順・両フィルタ) を端末ローカルに保存する。
    /// Web 版も端末ローカル保存で、開くたびに復元する。
    private func saveViewState() {
        saveViewState(page: currentPage)
    }

    private func saveViewState(page: Int) {
        var state: [String: Any] = [
            "page": page,
            "order": sortOrder,
            "unwatched_only": unwatchedOnly,
            "protected_only": protectedOnly,
        ]
        // スクロール位置は、そのページで取れた目印があるときだけ
        // 一緒に保存する (別のページの目印を持ち越さないため)。
        if let markerID = scrollMarkerProgramID, scrollMarkerPage == page {
            state["scroll_program_id"] = markerID
            state["scroll_offset"] = Double(scrollMarkerOffset)
            state["scroll_top"] = Double(scrollFallbackTop)
        }
        UserDefaults.standard.set(state, forKey: Self.viewStateKey)
    }

    /// 保存しておいた表示状態を読み戻す。最初の読み込みは、保存ページから始める。
    /// スクロール位置 (目印の録画とずれ、ピクセルの控え) も読み戻し、
    /// 最初の読み込みの後に条件が一致すれば戻す (Web 版と同じ)。
    /// アプリは再生画面から戻っても一覧を作り直さないため、戻す場面は
    /// 起動し直したときと読み直したときになる。
    private func restoreViewState() {
        guard let state = UserDefaults.standard.dictionary(forKey: Self.viewStateKey) else { return }
        if let order = state["order"] as? String, order == "desc" || order == "asc" {
            sortOrder = order
        }
        unwatchedOnly = state["unwatched_only"] as? Bool ?? false
        // 録画の保護がオフでは、保護中のみフィルタは無いものとして扱う。
        protectedOnly = AppEdition.protectionEnabled && (state["protected_only"] as? Bool ?? false)
        if let page = state["page"] as? Int, page > 1 {
            pendingRestorePage = page
        }
        if let markerID = state["scroll_program_id"] as? Int {
            pendingScrollRestore = (
                programID: markerID,
                offset: CGFloat((state["scroll_offset"] as? NSNumber)?.doubleValue ?? 0),
                fallbackTop: CGFloat((state["scroll_top"] as? NSNumber)?.doubleValue ?? 0),
                page: state["page"] as? Int ?? 1,
                order: sortOrder,
                unwatchedOnly: unwatchedOnly,
                protectedOnly: protectedOnly)
        }
    }

    // MARK: - スクロール位置の保存と復元

    /// いまのスクロール位置を目印として取り込む (画面の上端付近に
    /// 見えている先頭の録画と、その上端からのずれ)。
    private func captureScrollMarker() {
        guard let first = tableView.indexPathsForVisibleRows?.first,
              programs.indices.contains(first.row) else { return }
        let rowTop = tableView.rectForRow(at: first).origin.y
        scrollMarkerProgramID = programs[first.row].id
        scrollMarkerOffset = tableView.contentOffset.y - rowTop
        scrollMarkerPage = currentPage
        scrollFallbackTop = tableView.contentOffset.y
    }

    /// スクロールに合わせて目印を取り直して保存する (間引きつき)。
    /// 読み込み中と復元の合わせ直し中は保存しない。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView, scrollSaveEnabled, !isScrollRestoring else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastScrollSaveAt >= 0.25 else { return }
        lastScrollSaveAt = now
        captureScrollMarker()
        saveViewState()
    }

    /// 利用者がスクロールを始めたら、復元の合わせ直しは取り消す。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === tableView, isScrollRestoring else { return }
        scrollRestoreTimer?.invalidate()
        scrollRestoreTimer = nil
        isScrollRestoring = false
    }

    /// 最初の読み込みの後、保存しておいたスクロール位置へ戻す。
    /// ページ・並び順・絞り込みが保存時点と一致するときだけ戻し、
    /// サムネイルの高さが落ち着くまで約1.5秒の間、少しずつ
    /// 合わせ直す (Web 版と同じ)。目印の録画が見つからなければ
    /// ピクセルの控えで戻す。
    private func restoreScrollPositionIfNeeded() {
        scrollSaveEnabled = true
        guard let pending = pendingScrollRestore else { return }
        pendingScrollRestore = nil
        guard pending.page == currentPage, pending.order == sortOrder,
              pending.unwatchedOnly == unwatchedOnly,
              pending.protectedOnly == protectedOnly else { return }
        isScrollRestoring = true
        applyScrollRestore(pending)
        scrollRestoreTicks = 0
        scrollRestoreTimer?.invalidate()
        scrollRestoreTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.scrollRestoreTicks += 1
            self.applyScrollRestore(pending)
            if self.scrollRestoreTicks >= 15 {
                timer.invalidate()
                self.scrollRestoreTimer = nil
                self.isScrollRestoring = false
            }
        }
    }

    /// 復元先の位置へ実際に送る (目印の録画の上端 + ずれ、
    /// 無ければピクセルの控え。どちらも収まる範囲に丸める)。
    private func applyScrollRestore(
        _ pending: (programID: Int, offset: CGFloat, fallbackTop: CGFloat,
                    page: Int, order: String, unwatchedOnly: Bool, protectedOnly: Bool)
    ) {
        var target: CGFloat?
        if let row = programs.firstIndex(where: { $0.id == pending.programID }) {
            target = tableView.rectForRow(at: IndexPath(row: row, section: 0)).origin.y + pending.offset
        } else if pending.fallbackTop > 0 {
            target = pending.fallbackTop
        }
        guard let target else { return }
        let maxY = max(tableView.contentSize.height - tableView.bounds.height, 0)
        tableView.setContentOffset(
            CGPoint(x: 0, y: min(max(target, 0), maxY)), animated: false)
    }

    /// フィルタの判定 (Web 版の物差し)。ON の条件はすべて満たすものだけ残す (AND)。
    /// 未視聴: 見た割合が取れない (null) ものと、0.9 未満のもの。
    /// 保護中: 保護の状態が「保護中」(true) のものだけ。状態不明 (null) は含めない。
    private func matchesFilters(_ program: RecordedProgram) -> Bool {
        if unwatchedOnly {
            if let ratio = program.watched_ratio, ratio >= 0.9 { return false }
        }
        if protectedOnly, program.is_protected != true { return false }
        return true
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        programs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseID, for: indexPath) as! VideoCell
        let program = programs[indexPath.row]
        cell.configure(with: program)
        cell.configureSelection(
            active: isSelectionMode,
            selected: selectedProgramsByID[program.id] != nil)
        loadThumbnail(for: program, at: indexPath)
        // 局ロゴはキャッシュにあればその場で出し、無ければ行ごとに後から読み込む
        // (一覧の表示をロゴの取得で待たせない)。
        if let channelID = program.channel?.id {
            if let cached = logoCache.object(forKey: channelID as NSString) {
                cell.setLogo(cached)
            } else {
                loadLogo(channelID: channelID, at: indexPath)
            }
        }
        return cell
    }

    /// 局ロゴを取ってきて、表示中の行がまだ同じ番組ならその場で反映する。
    /// 取れなかった局 (ロゴ無しなど) は文字だけのままにし、再取得もしない。
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
               self.programs.indices.contains(indexPath.row),
               self.programs[indexPath.row].channel?.id == channelID {
                cell.setLogo(image)
            }
        }
    }

    private func loadThumbnail(for program: RecordedProgram, at indexPath: IndexPath) {
        let key = NSNumber(value: program.id)
        if let cached = thumbnailCache.object(forKey: key) {
            (tableView.cellForRow(at: indexPath) as? VideoCell)?.setThumbnail(cached)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard let data = try? await APIClient.shared.fetchThumbnail(videoID: program.id),
                  let image = UIImage(data: data) else { return }
            self.thumbnailCache.setObject(image, forKey: key)
            if let cell = self.tableView.cellForRow(at: indexPath) as? VideoCell,
               self.programs.indices.contains(indexPath.row),
               self.programs[indexPath.row].id == program.id {
                cell.setThumbnail(image)
            }
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard programs.indices.contains(indexPath.row) else { return }
        let program = programs[indexPath.row]
        if isSelectionMode {
            // 選択中は、カードを選ぶと選択の付け外しになる (ゴミ箱と同じ)。
            if selectedProgramsByID[program.id] != nil {
                selectedProgramsByID[program.id] = nil
            } else {
                selectedProgramsByID[program.id] = program
            }
            if let cell = tableView.cellForRow(at: indexPath) as? VideoCell {
                cell.configureSelection(
                    active: true, selected: selectedProgramsByID[program.id] != nil)
            }
            updateBulkBar()
            return
        }
        let player = PlayerViewController(program: program)
        navigationController?.pushViewController(player, animated: true)
    }

    /// 選択中にカードへ触れたまま指を動かしたときの処理 (写真アプリの
    /// なぞって選択と同じ感覚。ゴミ箱と同じ作り)。指の下にある行と、
    /// なぞり始めの行の間の範囲をまとめて選択／解除する。逆向きに
    /// 戻れば、範囲から外れた分はなぞる前の状態へ戻る。
    /// 範囲は表示中のページの中だけ。
    ///
    /// なぞっている間、一覧自体のスクロール (指に付いて動く動き) は
    /// 止める。以前は一覧のスクロールに相乗りしていたため、指を動かすと
    /// 一覧も一緒に動いて指の下の項目が変わらず、範囲が広げられな
    /// かったうえ、指の下の行が境目で小刻みに切り替わって、表示が
    /// 震えて見えた。今は指が項目の上を移動した分だけで範囲を広げ、
    /// 画面の端に指を持っていったときだけ、端からの近さに応じた
    /// 速さで一覧が少しずつ流れる (stepDragAutoScroll)。
    ///
    /// ただし、触れた直後はスクロールか なぞり選択か決めない。
    /// 一覧のスクロールと同時に指の動きを見て (同時の見守りは
    /// gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) で
    /// 許可)、指がある程度動いた時点で勢いを見る。速ければ
    /// スクロールに譲ってこの指には最後まで関わらず、ゆっくりなら
    /// なぞり選択として取り込む。取り込むまでは一覧が指に付いて
    /// 少し流れるが、決まるまでの動きはわずかなので、範囲の起点は
    /// 触れた行のまま保てる。
    @objc private func handleDragSelection(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard isSelectionMode, !isBulkRunning, !isLoading else { return }
            guard let row = dragRow(at: gesture.location(in: tableView)) else { return }
            // ここでは起点の行を控えるだけにし、スクロールは止めない。
            dragPendingAnchorRow = row
            dragCommitted = false
            dragAbandoned = false
        case .changed:
            guard isSelectionMode else { return }
            if dragCommitted {
                guard dragAnchorRow != nil else { return }
                dragFingerPoint = gesture.location(in: view)
                // 端での自動スクロールの刻みが何かの都合で止まって
                // いたら、指の動きに合わせて再開する (同じドラッグの
                // 間は、端に入るたびに流れが始まるように)。
                if dragScrollLink == nil { startDragAutoScroll() }
                if let row = dragRow(at: gesture.location(in: tableView)) {
                    applyDragSelection(toRow: row)
                }
                return
            }
            guard !dragAbandoned, let anchorRow = dragPendingAnchorRow else { return }
            let translation = gesture.translation(in: view)
            guard hypot(translation.x, translation.y) >= Self.dragDecisionDistance
            else { return }
            let velocity = gesture.velocity(in: view)
            if hypot(velocity.x, velocity.y) > Self.dragScrollSpeedThreshold {
                // 速い動きはスクロール。一覧側がそのまま流すので、
                // この指にはもう関わらない。
                dragAbandoned = true
                dragPendingAnchorRow = nil
                return
            }
            // ゆっくりした動きは、なぞり選択として取り込む。
            dragCommitted = true
            dragPendingAnchorRow = nil
            dragAnchorRow = anchorRow
            dragSelecting = selectedProgramsByID[programs[anchorRow].id] == nil
            dragRangeIDs = []
            dragBaseline = [:]
            dragFingerPoint = gesture.location(in: view)
            // 一覧が指に付いて動かないようにし、流れかけていた
            // 勢いも止める。引っ張って更新と、スクロール位置の
            // 復元の合わせ直しも、最中は止める。
            tableView.isScrollEnabled = false
            tableView.setContentOffset(tableView.contentOffset, animated: false)
            refreshControl.isEnabled = false
            scrollRestoreTimer?.invalidate()
            scrollRestoreTimer = nil
            isScrollRestoring = false
            // なぞっている間は、操作帯のボタンが指の動きに割り込ま
            // ないよう、操作帯へのタッチを止める。指が操作帯の上に
            // 行っても、端での流れが止まらないようにするため。
            bulkBar.isUserInteractionEnabled = false
            if let row = dragRow(at: gesture.location(in: tableView)) {
                applyDragSelection(toRow: row)
            }
            startDragAutoScroll()
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
        dragPendingAnchorRow = nil
        dragCommitted = false
        dragAbandoned = false
        dragRangeIDs = []
        dragBaseline = [:]
        dragFingerPoint = nil
        tableView.isScrollEnabled = true
        refreshControl.isEnabled = true
        bulkBar.isUserInteractionEnabled = true
    }

    /// なぞり選択の受け口は、一覧のスクロールと同時に指の動きを
    /// 見られるようにする (スクロールかどうかの見分けに使う)。
    /// それ以外の受け口とは同時に動かさない。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === dragSelectionGesture
            && otherGestureRecognizer === tableView.panGestureRecognizer
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
        var delta: CGFloat = 0
        if finger.y < visibleTop + Self.dragEdgeLength {
            let depth = visibleTop + Self.dragEdgeLength - finger.y
            delta = -Self.dragScrollSpeed(forDepth: depth) * CGFloat(dt)
        } else if finger.y > visibleBottom - Self.dragEdgeLength {
            let depth = finger.y - (visibleBottom - Self.dragEdgeLength)
            delta = Self.dragScrollSpeed(forDepth: depth) * CGFloat(dt)
        }
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
        guard !programs.isEmpty else { return nil }
        if let indexPath = tableView.indexPathForRow(at: point) {
            return indexPath.row
        }
        let firstRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        return point.y < firstRect.minY ? 0 : programs.count - 1
    }

    /// なぞった範囲へ選択の状態を反映する。範囲に入った項目はなぞり
    /// 始めに決めた向き (選択／解除) にそろえ、範囲から外れた項目は
    /// なぞる前の状態へ戻す。
    private func applyDragSelection(toRow row: Int) {
        guard let anchor = dragAnchorRow else { return }
        var newRange: Set<Int> = []
        for index in min(anchor, row)...max(anchor, row)
        where programs.indices.contains(index) {
            newRange.insert(programs[index].id)
        }
        for id in dragRangeIDs.union(newRange) {
            if dragBaseline[id] == nil {
                dragBaseline[id] = selectedProgramsByID[id] != nil
            }
            let target = newRange.contains(id)
                ? dragSelecting : (dragBaseline[id] ?? false)
            guard (selectedProgramsByID[id] != nil) != target else { continue }
            if target {
                if let program = programs.first(where: { $0.id == id }) {
                    selectedProgramsByID[id] = program
                }
            } else {
                selectedProgramsByID[id] = nil
            }
            if let index = programs.firstIndex(where: { $0.id == id }),
               let cell = tableView.cellForRow(
                   at: IndexPath(row: index, section: 0)) as? VideoCell {
                cell.configureSelection(active: true, selected: target)
            }
        }
        dragRangeIDs = newRange
        updateBulkBar()
    }

    /// 長押しメニュー。「視聴済みにする」「マイリストに追加／から削除」と
    /// 「保護する／外す」を出す (保護の項目は拡張版だけ)。「ゴミ箱に移動する」は
    /// Web 版のカードのメニューと同じく、拡張版かつ管理者のときだけ出し、
    /// 録画中と保護中は押せなくする。マイリストは Web 版ではカード右上の
    /// 「＋」ボタンだが、アプリのカードにはボタンの置き場が無いため、
    /// このメニューに寄せた (両版に出す)。
    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        // 選択中は長押しメニューを出さない (タップでの付け外しに一本化する)。
        guard !isSelectionMode else { return nil }
        let program = programs[indexPath.row]
        let isAdmin = isAdminUser
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = []
            if !program.isRecording, (program.watched_ratio ?? 0) < 1 {
                actions.append(UIAction(
                    title: "視聴済みにする",
                    image: UIImage(systemName: "checkmark.circle")
                ) { _ in
                    self?.markWatched(program: program)
                })
            }
            let inMylist = SyncedSettingsStore.shared.isInMylist(videoID: program.id)
            actions.append(UIAction(
                title: inMylist ? "マイリストから削除" : "マイリストに追加",
                image: UIImage(systemName: inMylist ? "bookmark.fill" : "bookmark")
            ) { _ in
                self?.toggleMylist(program: program)
            })
            if AppEdition.protectionEnabled {
                let protected = program.isProtected
                actions.append(UIAction(
                    title: protected ? "保護を外す" : "保護する",
                    image: UIImage(systemName: protected ? "lock.open" : "lock")
                ) { _ in
                    self?.toggleProtection(program: program)
                })
            }
            if AppEdition.trashEnabled, isAdmin {
                let trashAction = UIAction(
                    title: "ゴミ箱に移動する",
                    image: UIImage(systemName: "archivebox")
                ) { _ in
                    self?.moveToTrash(program: program)
                }
                // 録画中と保護中は Web 版と同じく押せなくする
                // (サーバー側でも録画中は 409 で拒否される)。
                if program.isRecording || program.isProtected {
                    trashAction.attributes.insert(.disabled)
                }
                actions.append(trashAction)
            }
            return UIMenu(children: actions)
        }
    }

    // MARK: - 番組への操作

    private func markWatched(program: RecordedProgram) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.markWatched(videoID: program.id, duration: program.duration)
                self.refresh()
            } catch {
                self.showAlert(title: "視聴済みにできませんでした", message: nil)
            }
        }
    }

    /// マイリストへの追加・削除を切り替える。マイリストは視聴履歴と揃えて、
    /// ログイン中かつ「設定をデバイス間で同期する」がオンのときだけ働く。
    /// その条件を満たさないときは切り替えず、案内を出す。
    /// カードにはマイリストの状態が出ていないため、一覧の読み直しはしない。
    private func toggleMylist(program: RecordedProgram) {
        guard SyncedSettingsStore.isSyncEnabled else {
            let loggedIn = SettingsStore.shared.isLoggedIn
            let alert = UIAlertController(
                title: loggedIn ? "同期をオンにしてください" : "ログインが必要です",
                message: loggedIn
                    ? "マイリストを使うには、アカウントの設定で「設定をデバイス間で同期する」をオンにしてください。"
                    : "マイリストを使うには、ログインして「設定をデバイス間で同期する」をオンにしてください。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { [weak self] _ in
                self?.mainTabBarController?.selectedIndex = 3
            })
            present(alert, animated: true)
            return
        }
        Task {
            // 他の画面や Web 版での変更に追いついてから切り替える
            // (古い控えで切り替えると、別の登録を巻き戻しかねないため)。
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            SyncedSettingsStore.shared.toggleMylist(videoID: program.id)
        }
    }

    private func toggleProtection(program: RecordedProgram) {
        guard SettingsStore.shared.isLoggedIn else {
            // 未ログインなら、切り替えはせずログインへ案内する。
            let alert = UIAlertController(
                title: "ログインが必要です",
                message: "保護の切り替えには、設定タブで KonomiTV へのログインが必要です。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { [weak self] _ in
                self?.mainTabBarController?.selectedIndex = 3
            })
            present(alert, animated: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await APIClient.shared.toggleProtection(videoID: program.id)
                self.refresh()
            } catch let error as APIError {
                self.showAlert(title: error.protectionFailureMessage, message: nil)
            } catch {
                self.showAlert(title: "保護を切り替えられませんでした", message: nil)
            }
        }
    }

    /// 録画をゴミ箱へ移動する。Web 版と同じく、実行前に確認を出す。
    /// ファイル自体は削除されず、保持期間内はゴミ箱から復元できる。
    private func moveToTrash(program: RecordedProgram) {
        let alert = UIAlertController(
            title: "ゴミ箱に移動しますか？",
            message: "\(program.title)\n\n"
                + "一覧や検索から隠します。ファイル自体は削除されず、保持期間内はゴミ箱から復元できます。\n"
                + "期間を過ぎると自動的に完全に削除されます。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "ゴミ箱に移動", style: .default) { [weak self] _ in
            self?.performMoveToTrash(program: program)
        })
        present(alert, animated: true)
    }

    private func performMoveToTrash(program: RecordedProgram) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.moveToTrash(videoID: program.id)
                // ゴミ箱へ移した録画は一覧から消えるため、読み直す。
                self.refresh()
            } catch let error as APIError {
                self.showAlert(title: error.moveToTrashFailureMessage, message: nil)
            } catch {
                self.showAlert(title: "ゴミ箱に移動できませんでした", message: nil)
            }
        }
    }

    // MARK: - 複数選択とまとめて操作

    /// 「選択する／選択を終える」のピルの切り替え。
    /// まとめて操作の実行中は切り替えない (ゴミ箱と同じ)。
    @objc private func toggleSelectionMode() {
        guard !isBulkRunning else { return }
        if isSelectionMode {
            exitSelectionMode()
        } else {
            isSelectionMode = true
            // なぞり選択の受け口は、選択中だけ有効にする。
            dragSelectionGesture.isEnabled = true
            selectButton.setTitle("選択を終える", for: .normal)
            updateSelectionChrome()
            tableView.reloadData()
        }
    }

    /// 選択中を終える。選んでいた内容は破棄する。
    private func exitSelectionMode() {
        guard isSelectionMode else { return }
        isSelectionMode = false
        dragSelectionGesture.isEnabled = false
        finishDragSelection()
        selectedProgramsByID = [:]
        selectButton.setTitle("選択する", for: .normal)
        updateSelectionChrome()
        tableView.reloadData()
    }

    /// 選択まわりの出し分け (操作帯と一覧下の余白) を現在の状態に合わせる。
    /// ピルの出し分けは先頭まわりの組み直しで反映する。
    private func updateSelectionChrome() {
        refreshHeadContainer()
        bulkBar.isHidden = !isSelectionMode
        if isSelectionMode {
            // 操作帯は一覧より前面に出す。
            view.bringSubviewToFront(bulkBar)
        }
        // 選択中は、操作帯の分だけ一覧の下に余白を空ける (ゴミ箱と同じ)。
        tableView.contentInset.bottom = isSelectionMode ? Self.bulkBarHeight + 10 : 10
        updateBulkBar()
    }

    /// 操作帯の表示 (件数・各ボタンの出し分けと有効・無効) を合わせる。
    /// 操作のボタンは、使える機能のものだけを出す: 保護する／保護を
    /// 外すは保護のトグルがオンのとき、ゴミ箱に移動はゴミ箱のトグルが
    /// オンで管理者のとき (1件のときの出し分けと同じ)。
    private func updateBulkBar() {
        bulkCountLabel.text = "\(selectedProgramsByID.count) 件選択中"
        let selected = Array(selectedProgramsByID.values)
        bulkProtectButton.isHidden = !AppEdition.protectionEnabled
        bulkUnprotectButton.isHidden = !AppEdition.protectionEnabled
        bulkTrashButton.isHidden = !(AppEdition.trashEnabled && isAdminUser)
        // 保護するは未保護の録画が、保護を外すは保護中の録画が
        // 選ばれているときだけ押せる。
        bulkProtectButton.isEnabled = !isBulkRunning && selected.contains { !$0.isProtected }
        bulkUnprotectButton.isEnabled = !isBulkRunning && selected.contains { $0.isProtected }
        bulkTrashButton.isEnabled = !isBulkRunning && !selected.isEmpty
        for button in [bulkProtectButton, bulkUnprotectButton, bulkTrashButton] {
            button.alpha = button.isEnabled ? 1 : 0.5
        }
        bulkSelectAllButton.isEnabled = !isBulkRunning
        bulkClearButton.isEnabled = !selected.isEmpty && !isBulkRunning
        bulkClearButton.alpha = bulkClearButton.isEnabled ? 1 : 0.5
    }

    /// 表示中のページの録画をすべて選択に加える。
    @objc private func selectAllItems() {
        guard !isBulkRunning else { return }
        for program in programs {
            selectedProgramsByID[program.id] = program
        }
        tableView.reloadData()
        updateBulkBar()
    }

    @objc private func clearSelection() {
        guard !isBulkRunning else { return }
        selectedProgramsByID = [:]
        tableView.reloadData()
        updateBulkBar()
    }

    /// 選んだ録画を、録画が新しい順に整えたもの (結果の表示用)。
    private var selectedProgramsInOrder: [RecordedProgram] {
        selectedProgramsByID.values.sorted {
            ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast)
        }
    }

    @objc private func bulkProtect() {
        bulkSetProtection(toProtected: true)
    }

    @objc private func bulkUnprotect() {
        bulkSetProtection(toProtected: false)
    }

    /// 選んだ分をまとめて保護する／保護を外す。1件ずつのときと同じ
    /// 受け口を、目的の状態に合わせて順に使う。すでに目的の状態の
    /// 録画は対象から外す。終わったら選択中を終えて読み直し、
    /// 失敗分は件数と題名入りの警告を出す (ゴミ箱のまとめて操作と同じ)。
    private func bulkSetProtection(toProtected: Bool) {
        guard !isBulkRunning else { return }
        let targets = selectedProgramsInOrder.filter { $0.isProtected != toProtected }
        guard !targets.isEmpty else { return }
        guard SettingsStore.shared.isLoggedIn else {
            // 未ログインなら、実行せずログインへ案内する (1件のときと同じ)。
            let alert = UIAlertController(
                title: "ログインが必要です",
                message: "保護の切り替えには、設定タブで KonomiTV へのログインが必要です。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { [weak self] _ in
                self?.mainTabBarController?.selectedIndex = 3
            })
            present(alert, animated: true)
            return
        }
        isBulkRunning = true
        updateBulkBar()
        Task { [weak self] in
            guard let self else { return }
            var failed: [RecordedProgram] = []
            for program in targets {
                do {
                    try await APIClient.shared.setProtection(
                        videoID: program.id, protected: toProtected)
                } catch {
                    failed.append(program)
                }
            }
            self.isBulkRunning = false
            self.exitSelectionMode()
            self.refresh()
            if !failed.isEmpty {
                self.showAlert(
                    title: toProtected
                        ? "\(failed.count) 件を保護できませんでした"
                        : "\(failed.count) 件の保護を外せませんでした",
                    message: failed.map { $0.title }.joined(separator: "\n"))
            }
        }
    }

    /// 選んだ分をまとめてゴミ箱へ移動する。まず対象の件数と題名を
    /// 出して確認する (説明文は1件のときと同じ)。録画中と保護中は
    /// 1件のときと同じく移動できないため対象から外し、結果の
    /// 警告で分かるようにする。
    @objc private func bulkMoveToTrash() {
        guard !isBulkRunning, !selectedProgramsByID.isEmpty else { return }
        let targets = selectedProgramsInOrder
        let ineligible = targets.filter { $0.isRecording || $0.isProtected }
        let eligible = targets.filter { !($0.isRecording || $0.isProtected) }
        guard !eligible.isEmpty else {
            showAlert(
                title: "ゴミ箱に移動できません",
                message: "選択した録画はすべて録画中または保護中です。\n"
                    + ineligible.map { $0.title }.joined(separator: "\n"))
            return
        }
        var message = "\(eligible.count) 件の録画をゴミ箱に移動します。\n\n"
            + eligible.map { $0.title }.joined(separator: "\n")
            + "\n\n一覧や検索から隠します。ファイル自体は削除されず、保持期間内はゴミ箱から復元できます。\n"
            + "期間を過ぎると自動的に完全に削除されます。"
        if !ineligible.isEmpty {
            message += "\n\n録画中または保護中の \(ineligible.count) 件は移動できません。"
        }
        let alert = UIAlertController(
            title: "ゴミ箱に移動しますか？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "ゴミ箱に移動", style: .default) { [weak self] _ in
            self?.performBulkMoveToTrash(eligible: eligible, ineligible: ineligible)
        })
        present(alert, animated: true)
    }

    private func performBulkMoveToTrash(
        eligible: [RecordedProgram], ineligible: [RecordedProgram]
    ) {
        guard !isBulkRunning else { return }
        isBulkRunning = true
        updateBulkBar()
        Task { [weak self] in
            guard let self else { return }
            var failed: [RecordedProgram] = []
            for program in eligible {
                do {
                    try await APIClient.shared.moveToTrash(videoID: program.id)
                } catch {
                    failed.append(program)
                }
            }
            self.isBulkRunning = false
            self.exitSelectionMode()
            self.refresh()
            let notMoved = failed + ineligible
            if !notMoved.isEmpty {
                self.showAlert(
                    title: "\(notMoved.count) 件をゴミ箱に移動できませんでした",
                    message: notMoved.map { $0.title }.joined(separator: "\n"))
            }
        }
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// 番号付きのページ送り。Web 版のページ送り (前へ・番号・次へ、いまのページは
/// アクセント色で強調) に合わせた形。番号は Web 版のスマホ縦と同じく最大5個まで出し、
/// ページ数が多いときはいまのページの前後を表示する。
final class PaginationView: UIView {
    /// 上下の余白込みの高さ。
    static let preferredHeight: CGFloat = 56

    var onPageSelected: ((Int) -> Void)?

    private let stack = UIStackView()
    private var currentPage = 1
    private var totalPages = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    /// 表示を最新のページ状態に作り直す。
    func update(currentPage: Int, totalPages: Int, isEnabled: Bool) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        for arranged in stack.arrangedSubviews {
            stack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        stack.addArrangedSubview(makeChevronButton(
            systemName: "chevron.left", page: currentPage - 1,
            isEnabled: isEnabled && currentPage > 1, label: "前のページ"))
        for page in pageWindow() {
            stack.addArrangedSubview(makeNumberButton(page: page, isEnabled: isEnabled))
        }
        stack.addArrangedSubview(makeChevronButton(
            systemName: "chevron.right", page: currentPage + 1,
            isEnabled: isEnabled && currentPage < totalPages, label: "次のページ"))
    }

    /// 出す番号の範囲。最大5個で、いまのページがなるべく真ん中に来るようにする。
    private func pageWindow() -> [Int] {
        let count = min(totalPages, 5)
        let start = min(max(currentPage - 2, 1), max(totalPages - count + 1, 1))
        return Array(start ..< start + count)
    }

    private func makeNumberButton(page: Int, isEnabled: Bool) -> UIButton {
        let button = RippleButton()
        button.setTitle("\(page)", for: .normal)
        button.accessibilityLabel = "\(page) ページ"
        let isCurrent = page == currentPage
        button.titleLabel?.font = .scaledSystemFont(ofSize: 14, weight: isCurrent ? .bold : .regular)
        button.setTitleColor(isCurrent ? .white : AppPalette.text, for: .normal)
        button.backgroundColor = isCurrent ? AppPalette.accent : AppPalette.panel
        button.layer.cornerRadius = 4
        button.isEnabled = isEnabled && !isCurrent
        button.alpha = isEnabled ? 1 : 0.5
        button.tag = page
        button.addTarget(self, action: #selector(pageButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38),
        ])
        return button
    }

    private func makeChevronButton(systemName: String, page: Int, isEnabled: Bool, label: String) -> UIButton {
        let button = RippleButton()
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.accessibilityLabel = label
        button.tintColor = AppPalette.text
        button.backgroundColor = AppPalette.panel
        button.layer.cornerRadius = 4
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.5
        button.tag = page
        button.addTarget(self, action: #selector(pageButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38),
        ])
        return button
    }

    @objc private func pageButtonTapped(_ sender: UIButton) {
        onPageSelected?(sender.tag)
    }
}

/// 内側の余白を持つ小さなバッジ用のラベル。余白はバッジごとに変えられる。
final class BadgeLabel: UILabel {
    var textInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6) {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }

    /// sizeToFit / sizeThatFits でも intrinsicContentSize と同じく余白を含める。
    /// UILabel の sizeThatFits は intrinsicContentSize の上書きを見ないため、
    /// これが無いと「余白なしの文字だけの大きさ」が返り、sizeToFit で
    /// 大きさを決める使い方 (題名の印の画像化など) で、描くときに余白の分だけ
    /// 文字の場所が狭くなり、文字が潰れて欠けて見える。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(size)
        return CGSize(
            width: fitted.width + textInsets.left + textInsets.right,
            height: fitted.height + textInsets.top + textInsets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}

/// サムネイル下端に重ねる、見た割合の細いバー。
final class WatchedProgressView: UIView {
    var ratio: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        // Web 版の進み具合バーと同じ (下地は黒の半透明、バーは secondary-lighten-1)。
        UIColor.black.withAlphaComponent(0.6).setFill()
        UIRectFill(rect)
        let clamped = min(max(ratio, 0), 1)
        guard clamped > 0 else { return }
        AppPalette.progress.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: rect.width * CGFloat(clamped), height: rect.height))
    }
}

/// 録画一覧の1件。Web 版の録画カード (RecordedProgram.vue、スマホ縦) と
/// テレビ一覧のカードの寸法に合わせた、独立した角丸カード。
/// 中身の並びは Web 版カードどおり: サムネイル (120x80) の右に、
/// 題名 → 局ロゴ+「Ch: 番号 局名」→ 時刻 → 説明文。
/// 状態の印はサムネイルへの重ね表示 (右上に状態、右下に長さ、
/// 左下に保護中・未視聴、下端に見た割合バー)。
final class VideoCell: UITableViewCell {
    static let reuseID = "VideoCell"

    private let cardView = UIView()
    private let thumbnailView = UIImageView()
    private let textStackView = UIStackView()
    private let titleLabel = UILabel()
    private let logoView = UIImageView()
    private let channelLabel = UILabel()
    private let timeLabel = UILabel()
    /// 容量の表示。チャンネル名の行の右端に出す (値が無い番組では隠す)。
    private let fileSizeLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let statusBadge = BadgeLabel()
    private let durationBadge = BadgeLabel()
    private let protectBadge = BadgeLabel()
    private let unwatchedBadge = BadgeLabel()
    private let progressView = WatchedProgressView()
    private var unwatchedBottomConstraint: NSLayoutConstraint?
    /// ゴミ箱の画面だけで出す追加の行 (「あと○日で完全に削除されます」)。
    /// 通常の一覧では隠したままで、見た目には影響しない。
    private let noticeLabel = UILabel()
    /// ゴミ箱の画面だけで出す操作の行 (復元する／完全に削除のボタン)。
    /// 通常の一覧では隠したままで、見た目には影響しない。
    private let actionRow = UIStackView()
    private let restoreButton = RippleButton()
    private let deleteButton = RippleButton()
    /// ゴミ箱の操作ボタンを押したときの受け先。再利用時に外す。
    private var onTrashRestore: (() -> Void)?
    private var onTrashDelete: (() -> Void)?
    /// 複数選択のときにカードの左上に出す選択の印
    /// (Web 版のチェックボックスに相当)。選択中でないときは隠したまま。
    private let selectionMarkView = UIView()
    private let selectionCheckView = UIImageView()
    /// 押したときの波紋 (共通部品)。本家 Web 版のカードと同じく、
    /// カード全体を対象に、触れた位置から広げる。
    private let ripple = RippleSurface()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        // セル自体は透明にし、カードだけを見せる。押したときはカードの面が
        // 一段明るくなる (Web 版カードの hover = background-lighten-2)。
        backgroundColor = .clear
        selectionStyle = .none

        // カードの角丸はテレビ一覧のカード (スマホ縦) の 11px。
        // 面の色は録画カードと同じ background-lighten-1。
        cardView.backgroundColor = AppPalette.panel
        cardView.layer.cornerRadius = 11
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        // Web 版 (スマホ縦) の寸法: サムネイルは幅 120px・縦横比 3:2、角丸 4px。
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = AppPalette.placeholder
        thumbnailView.layer.cornerRadius = 4
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        // 題名は Web 版 (スマホ縦) に合わせ 13px の太字 (600)、行間 1.4、最大2行。
        titleLabel.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppPalette.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        // 局ロゴは Web 版 (スマホ縦) に合わせ 24x14px、角丸 2px。
        // 取れない局では隠して文字だけにする。
        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.backgroundColor = AppPalette.placeholder
        logoView.layer.cornerRadius = 2
        logoView.isHidden = true
        logoView.translatesAutoresizingMaskIntoConstraints = false

        // 局名は Web 版 (スマホ縦) に合わせ 11.5px。
        channelLabel.font = .scaledSystemFont(ofSize: 11.5)
        channelLabel.textColor = AppPalette.metaText
        channelLabel.numberOfLines = 1
        channelLabel.lineBreakMode = .byTruncatingTail

        // 時刻は Web 版 (スマホ縦) に合わせ 11px。
        timeLabel.font = .scaledSystemFont(ofSize: 11)
        timeLabel.textColor = AppPalette.metaText
        timeLabel.numberOfLines = 1
        timeLabel.lineBreakMode = .byTruncatingTail

        // 容量はチャンネル名の行の右端に出す。
        // 行が窮屈なときは容量を落とさず、チャンネル名側を末尾で省略する。
        fileSizeLabel.font = .scaledSystemFont(ofSize: 11)
        fileSizeLabel.textColor = AppPalette.metaText
        fileSizeLabel.numberOfLines = 1
        fileSizeLabel.isHidden = true
        fileSizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        fileSizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        channelLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 説明文は Web 版 (スマホ縦) に合わせ 10px、最大2行。
        descriptionLabel.font = .scaledSystemFont(ofSize: 10)
        descriptionLabel.textColor = AppPalette.metaText
        descriptionLabel.numberOfLines = 2
        descriptionLabel.lineBreakMode = .byTruncatingTail

        configureStatusBadge()
        configureDurationBadge()
        configureProtectBadge()
        configureUnwatchedBadge()
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false

        // 局ロゴと局名の間隔は Web 版どおり (アイコン右 4px + 局名左 4px = 8px)。
        // 容量はこの行の右端に置く (局名が伸びて右端まで届く並び)。
        let metaRow = UIStackView(arrangedSubviews: [logoView, channelLabel, fileSizeLabel])
        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.translatesAutoresizingMaskIntoConstraints = false

        // 局名行と時刻行の間は Web 版どおり 1px (時刻の margin-top)。
        let metaStack = UIStackView(arrangedSubviews: [metaRow, timeLabel])
        metaStack.axis = .vertical
        metaStack.spacing = 1
        metaStack.translatesAutoresizingMaskIntoConstraints = false

        // ゴミ箱用の追加行 (通常の一覧では両方とも隠したまま)。
        // 日数の行は Web 版のゴミ箱と同じく error 色の文字。
        noticeLabel.font = .scaledSystemFont(ofSize: 11.5)
        noticeLabel.textColor = AppPalette.error
        noticeLabel.numberOfLines = 1
        noticeLabel.lineBreakMode = .byTruncatingTail
        noticeLabel.isHidden = true
        // 操作の行は右寄せで、Web 版のゴミ箱のボタン (小さいボタン2つ) に
        // 合わせる。復元は枠線だけ、完全削除は error 色で塗る。
        restoreButton.setTitle("復元する", for: .normal)
        restoreButton.setTitleColor(AppPalette.text, for: .normal)
        restoreButton.titleLabel?.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        restoreButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        restoreButton.layer.cornerRadius = 4
        restoreButton.layer.borderWidth = 1
        restoreButton.layer.borderColor = AppPalette.fieldBorder.cgColor
        restoreButton.addTarget(self, action: #selector(trashRestoreTapped), for: .touchUpInside)
        deleteButton.setTitle("完全に削除", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.titleLabel?.font = .scaledSystemFont(ofSize: 13, weight: .semibold)
        deleteButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        deleteButton.layer.cornerRadius = 4
        deleteButton.backgroundColor = AppPalette.error
        deleteButton.addTarget(self, action: #selector(trashDeleteTapped), for: .touchUpInside)
        let actionSpacer = UIView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionRow.addArrangedSubview(actionSpacer)
        actionRow.addArrangedSubview(restoreButton)
        actionRow.addArrangedSubview(deleteButton)
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 8
        actionRow.isHidden = true

        // Web 版の並び: 題名 → 局名行 → 時刻 → 説明文。
        // 間隔は題名の下 4px (meta の margin-top)、説明の上 2.5px。
        // ゴミ箱用の行は説明文の下に続ける (隠れているときは間隔も消える)。
        let textStack = textStackView
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(metaStack)
        textStack.addArrangedSubview(descriptionLabel)
        textStack.addArrangedSubview(noticeLabel)
        textStack.addArrangedSubview(actionRow)
        textStack.axis = .vertical
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setCustomSpacing(4, after: titleLabel)
        textStack.setCustomSpacing(2.5, after: metaStack)
        textStack.setCustomSpacing(4, after: descriptionLabel)
        textStack.setCustomSpacing(8, after: noticeLabel)

        // 選択の印はカードの左上に重ねる丸 (26px)。選ばれているときは
        // アクセント色で塗って白いチェックを出し、そうでないときは
        // 黒の半透明に白い枠だけにする。
        selectionMarkView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        selectionMarkView.layer.cornerRadius = 13
        selectionMarkView.layer.borderWidth = 1.5
        selectionMarkView.layer.borderColor = UIColor.white.cgColor
        selectionMarkView.isHidden = true
        selectionMarkView.translatesAutoresizingMaskIntoConstraints = false
        selectionCheckView.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        selectionCheckView.contentMode = .center
        selectionCheckView.isHidden = true
        selectionCheckView.translatesAutoresizingMaskIntoConstraints = false
        selectionMarkView.addSubview(selectionCheckView)

        cardView.addSubview(thumbnailView)
        cardView.addSubview(textStack)
        cardView.addSubview(selectionMarkView)
        cardView.addSubview(statusBadge)
        cardView.addSubview(durationBadge)
        cardView.addSubview(progressView)
        cardView.addSubview(unwatchedBadge)
        cardView.addSubview(protectBadge)

        // 波紋の入れ物はカードの一番上に重ねる (操作は受けない)。
        cardView.addSubview(ripple.container)

        // カード間の余白はテレビ一覧 (スマホ縦) の行間 10px、
        // 画面の左右は同コンテナの左右パディング 8px。
        // カード内は録画カード (スマホ縦) の寸法: 左右 9px、上下 8px、
        // サムネイルと本文の間 12px。
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 9),
            thumbnailView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 120),
            thumbnailView.heightAnchor.constraint(equalToConstant: 80),
            selectionMarkView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 6),
            selectionMarkView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            selectionMarkView.widthAnchor.constraint(equalToConstant: 26),
            selectionMarkView.heightAnchor.constraint(equalToConstant: 26),
            selectionCheckView.centerXAnchor.constraint(equalTo: selectionMarkView.centerXAnchor),
            selectionCheckView.centerYAnchor.constraint(equalTo: selectionMarkView.centerYAnchor),
            selectionCheckView.widthAnchor.constraint(equalToConstant: 16),
            selectionCheckView.heightAnchor.constraint(equalToConstant: 16),
            logoView.widthAnchor.constraint(equalToConstant: 24),
            logoView.heightAnchor.constraint(equalToConstant: 14),
            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -9),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),
            statusBadge.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: 4),
            statusBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -4),
            durationBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -4),
            durationBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -4),
            unwatchedBadge.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: 4),
            protectBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -4),
            protectBadge.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: 4),
            progressView.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),
        ])
        // 未視聴ピルの下端は、保護中ピルと重なるときだけ持ち上がる (Web 版の stacked)。
        unwatchedBottomConstraint = unwatchedBadge.bottomAnchor.constraint(
            equalTo: thumbnailView.bottomAnchor, constant: -8)
        unwatchedBottomConstraint?.isActive = true
    }

    /// 状態ピル (サムネイル右上)。Web 版の thumbnail-status と同じ寸法:
    /// 余白は縦 4px・横 6px、角丸 2px、地は background-lighten-1 の 90%、
    /// 文字は 10.5px 太字・白の 85%。
    private func configureStatusBadge() {
        statusBadge.font = .scaledSystemFont(ofSize: 10.5, weight: .bold)
        statusBadge.textColor = AppPalette.text.withAlphaComponent(0.85)
        statusBadge.backgroundColor = AppPalette.panel.withAlphaComponent(0.9)
        statusBadge.layer.cornerRadius = 2
        statusBadge.clipsToBounds = true
        statusBadge.textInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        statusBadge.textAlignment = .center
        statusBadge.isHidden = true
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 長さの表示 (サムネイル右下)。Web 版の thumbnail-duration と同じ寸法:
    /// 余白は縦 3px・横 4px、角丸 2px、地は黒の 70%、文字は 10.5px。
    private func configureDurationBadge() {
        durationBadge.font = .scaledSystemFont(ofSize: 10.5)
        durationBadge.textColor = .white
        durationBadge.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        durationBadge.layer.cornerRadius = 2
        durationBadge.clipsToBounds = true
        durationBadge.textInsets = UIEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        durationBadge.textAlignment = .center
        durationBadge.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 保護中ピル (サムネイル左下)。本番 Web 版の protection と同じ寸法:
    /// 余白は縦 3px・横 5px、角丸 3px、地は黒の 82%、
    /// 枠は warning の 45%、文字と鍵は warning 色、11px 太字。
    private func configureProtectBadge() {
        protectBadge.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        protectBadge.layer.cornerRadius = 3
        protectBadge.layer.borderWidth = 1
        protectBadge.layer.borderColor = AppPalette.warning.withAlphaComponent(0.45).cgColor
        protectBadge.clipsToBounds = true
        protectBadge.textInsets = UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        protectBadge.textAlignment = .center
        protectBadge.isHidden = true
        protectBadge.translatesAutoresizingMaskIntoConstraints = false

        let font = UIFont.scaledSystemFont(ofSize: 11, weight: .bold)
        let attributed = NSMutableAttributedString()
        // Web 版の鍵アイコンは 14px。SF Symbol はポイント指定のため近似値。
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        if let lock = UIImage(systemName: "lock.fill", withConfiguration: symbolConfig)?
            .withTintColor(AppPalette.warning, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = lock
            attachment.bounds = CGRect(x: 0, y: -1.5, width: 11, height: 13)
            attributed.append(NSAttributedString(attachment: attachment))
            attributed.append(NSAttributedString(string: " "))
        }
        attributed.append(NSAttributedString(string: "保護中", attributes: [
            .font: font,
            .foregroundColor: AppPalette.warning,
        ]))
        protectBadge.attributedText = attributed
    }

    /// 未視聴ピル (サムネイル左下)。本番 Web 版の unwatched と同じ寸法:
    /// 余白は縦 4px・横 6px、角丸 3px、地は primary、文字は 11px 太字・白。
    private func configureUnwatchedBadge() {
        unwatchedBadge.text = "未視聴"
        unwatchedBadge.font = .scaledSystemFont(ofSize: 11, weight: .bold)
        unwatchedBadge.textColor = .white
        unwatchedBadge.backgroundColor = AppPalette.accent
        unwatchedBadge.layer.cornerRadius = 3
        unwatchedBadge.clipsToBounds = true
        unwatchedBadge.textInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        unwatchedBadge.textAlignment = .center
        unwatchedBadge.isHidden = true
        unwatchedBadge.translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 押したときの反応は波紋だけにする。本家ではカードの地が
    // 明るくなるのはホバー向けの決まりで、タッチでは無効にする
    // 上書きまで入っているため、地の変化は付けない。
    override func layoutSubviews() {
        super.layoutSubviews()
        ripple.update(bounds: cardView.bounds, cornerRadius: cardView.layer.cornerRadius)
    }

    // カードへのタッチで波紋を出す。タッチは中身の部品 (文字や絵) では
    // 受けず、カード面を通してセルまで届く。スクロールが始まると
    // 「取り消し」が届くので、そこで波紋を取り消す。
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        ripple.startRipple(at: touch.location(in: cardView))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        ripple.endRipple()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        ripple.cancelRipple()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        logoView.image = nil
        logoView.isHidden = true
        statusBadge.isHidden = true
        durationBadge.text = nil
        protectBadge.isHidden = true
        unwatchedBadge.isHidden = true
        progressView.isHidden = true
        fileSizeLabel.text = nil
        fileSizeLabel.isHidden = true
        descriptionLabel.text = nil
        noticeLabel.text = nil
        noticeLabel.isHidden = true
        actionRow.isHidden = true
        onTrashRestore = nil
        onTrashDelete = nil
        selectionMarkView.isHidden = true
        selectionCheckView.isHidden = true
    }

    /// 複数選択の印を設定する (録画一覧とゴミ箱の両方で使う)。
    /// active が false のときは印自体を出さない。
    func configureSelection(active: Bool, selected: Bool) {
        selectionMarkView.isHidden = !active
        selectionCheckView.isHidden = !(active && selected)
        selectionMarkView.backgroundColor = selected
            ? AppPalette.accent : UIColor.black.withAlphaComponent(0.45)
        selectionMarkView.layer.borderColor = selected
            ? AppPalette.accent.cgColor : UIColor.white.cgColor
    }

    /// ゴミ箱の画面用の追加表示を設定する (通常の一覧では呼ばない)。
    /// notice は「あと○日で完全に削除されます」の文。showsActions が
    /// true のときだけ操作ボタンの行を出す (Web 版と同じく管理者だけ)。
    func configureTrash(
        notice: String?,
        showsActions: Bool,
        onRestore: (() -> Void)?,
        onDelete: (() -> Void)?
    ) {
        noticeLabel.text = notice
        noticeLabel.isHidden = notice == nil
        actionRow.isHidden = !showsActions
        onTrashRestore = onRestore
        onTrashDelete = onDelete
    }

    @objc private func trashRestoreTapped() {
        onTrashRestore?()
    }

    @objc private func trashDeleteTapped() {
        onTrashDelete?()
    }

    func configure(with program: RecordedProgram) {
        // 題名の [字] [再] などは、Web 版の録画カードと同じくピンク地の印に
        // 描き分ける (再生画面の情報欄と同じ部品を使う)。
        titleLabel.attributedText = decoratedProgramTitle(
            program.title, font: titleLabel.font, textColor: AppPalette.text)
        // 局名行は Web 版どおり「Ch: 番号 局名」。番号が無い応答では局名だけにする。
        if let channel = program.channel {
            if let number = channel.channel_number, !number.isEmpty {
                channelLabel.text = "Ch: \(number) \(channel.name)"
            } else {
                channelLabel.text = channel.name
            }
        } else {
            channelLabel.text = "チャンネル情報なし"
        }
        // 時刻行は本番 Web 版どおり、録画期間 (無ければ放送時刻) + 長さ (分)。
        timeLabel.text = TimeFormat.recordingTimeText(
            start: program.recorded_video.recordingStartDate ?? program.startDate,
            end: program.recorded_video.recordingEndDate ?? program.endDate,
            durationSeconds: program.recorded_video.duration
        )
        // 容量はチャンネル名の行の右端に出す (常時表示)。
        // 値が取れない番組では出さない。録画中はその時点の値になる。
        if let fileSizeText = program.recorded_video.fileSizeText {
            fileSizeLabel.text = fileSizeText
            fileSizeLabel.isHidden = false
        } else {
            fileSizeLabel.text = nil
            fileSizeLabel.isHidden = true
        }
        // 説明文。無い番組では行ごと隠す。
        let description = program.description ?? ""
        descriptionLabel.text = description
        descriptionLabel.isHidden = description.isEmpty
        // 状態ピル (右上)。録画中 → 解析失敗 → 一部のみ録画 の優先順は Web 版どおり。
        if program.isRecording {
            statusBadge.attributedText = Self.recordingStatusText
            statusBadge.isHidden = false
        } else if program.recorded_video.status == "AnalysisFailed" {
            statusBadge.attributedText = nil
            statusBadge.text = "メタデータ解析失敗"
            statusBadge.isHidden = false
        } else if program.isPartiallyRecorded {
            statusBadge.attributedText = nil
            statusBadge.text = "⚠️ 一部のみ録画"
            statusBadge.isHidden = false
        } else {
            statusBadge.isHidden = true
        }
        // 長さ (右下) は recorded_video.duration の H:MM:SS (Web 版の getProgramDuration)。
        durationBadge.text = TimeFormat.hms(program.recorded_video.duration)
        // 録画中と解析失敗のときは、Web 版どおりサムネイルと本文を薄くする (opacity .65)。
        // 状態ピルなどの重ね表示は薄くしない。
        let dimmed = program.isRecording || program.recorded_video.status == "AnalysisFailed"
        thumbnailView.alpha = dimmed ? 0.65 : 1
        textStackView.alpha = dimmed ? 0.65 : 1
        // 保護中ピルは録画の保護のトグルがオンのときだけ出す
        // (オフでは保護の機能自体を出さない)。
        let showsProtected = AppEdition.protectionEnabled && program.isProtected
        protectBadge.isHidden = !showsProtected
        unwatchedBadge.isHidden = !program.isUnwatched
        // 未視聴ピルは、保護中ピルがあるときはその上に積む (Web 版: bottom 8px → 30px)。
        unwatchedBottomConstraint?.constant = showsProtected ? -30 : -8
        if let ratio = program.watched_ratio, ratio > 0 {
            progressView.ratio = ratio
            progressView.isHidden = false
        } else {
            progressView.isHidden = true
        }
    }

    /// 録画中の状態表示 (赤い丸 7px + 間隔 4px + 「録画中・追いかけ再生」)。
    /// 文言は本番 Web 版のカードに合わせた。
    private static let recordingStatusText: NSAttributedString = {
        let font = UIFont.scaledSystemFont(ofSize: 10.5, weight: .bold)
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "●", attributes: [
            .font: UIFont.scaledSystemFont(ofSize: 7, weight: .bold),
            .foregroundColor: AppPalette.recordingDot,
        ]))
        attributed.append(NSAttributedString(string: " 録画中・追いかけ再生", attributes: [
            .font: font,
            .foregroundColor: AppPalette.text.withAlphaComponent(0.85),
        ]))
        return attributed
    }()

    func setThumbnail(_ image: UIImage) {
        thumbnailView.image = image
    }

    /// 局ロゴを出す。取れなかった局では呼ばれず、文字だけのままになる。
    func setLogo(_ image: UIImage) {
        logoView.image = image
        logoView.isHidden = false
    }
}
