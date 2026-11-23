import UIKit

/// 番組表のジャンル色。Web 版 (TimeTableUtils.ts と App.vue の CSS 変数) の
/// 表をそのまま写したもの。色名ごとに「帯の色」と「背景の色」の組が
/// 決まっていて、ジャンルへの割り当ては表示設定 (TimeTableDisplaySettings)
/// から渡る。
enum TimeTableGenre {
    struct Colors {
        let highlight: UIColor
        let background: UIColor
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// 色名 → 実際の色 (Web 版の --timetable-genre-highlight-* / -background-*)。
    private static let table: [String: Colors] = [
        "White": Colors(highlight: color(0xFFFFFF), background: color(0xF8F8F8)),
        "Pink": Colors(highlight: color(0xF50094), background: color(0xF6EAEF)),
        "Red": Colors(highlight: color(0xE1512D), background: color(0xFFECEC)),
        "Orange": Colors(highlight: color(0xFF9800), background: color(0xFFF3E0)),
        "Yellow": Colors(highlight: color(0xFFEB3B), background: color(0xFFFDE7)),
        "Lime": Colors(highlight: color(0x8BC34A), background: color(0xF1F8E9)),
        "Teal": Colors(highlight: color(0x009688), background: color(0xE0F2F1)),
        "Cyan": Colors(highlight: color(0x03A9F4), background: color(0xE1F5FE)),
        "Blue": Colors(highlight: color(0x4E7AC1), background: color(0xEFF3FB)),
        "Ochre": Colors(highlight: color(0xC59A2F), background: color(0xFDF5E2)),
        "Brown": Colors(highlight: color(0xA3421F), background: color(0xFFF2EB)),
    ]

    /// ジャンル大分類から色を引く。割り当て (ジャンル名 → 色名) は
    /// 表示設定から渡す (既定の割り当ては TimeTableDisplaySettings 側)。
    /// 色名への照合の fallback (「/」と「・」の入れ替え、白への帰着) も
    /// 表示設定側に寄せてあるので、ここでは色名を実際の色に直すだけ。
    static func colors(forMajor major: String?, settings: TimeTableDisplaySettings) -> Colors {
        let name = settings.genreColorName(forMajor: major)
        return table[name] ?? table["White"]!
    }

    /// 色名から帯の色だけを引く。表示設定の画面で色見本を出すために使う。
    static func swatchColor(forColorName name: String) -> UIColor {
        table[name]?.highlight ?? table["White"]!.highlight
    }

    /// 2色を混ぜる (Web 版の color-mix の近似)。baseRatio は base 側の割合。
    static func blended(_ base: UIColor, with other: UIColor, baseRatio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 * baseRatio + r2 * (1 - baseRatio),
            green: g1 * baseRatio + g2 * (1 - baseRatio),
            blue: b1 * baseRatio + b2 * (1 - baseRatio),
            alpha: 1)
    }
}

/// 番組表。Web 版と同じ格子状 (横がチャンネル、縦が時刻) で、
/// 上の操作の帯から種別と日付と時刻を切り替えられる。
/// 寸法は Web 版のスマホ用の換算表どおりで、表示設定 (幅と密度の3段階)
/// に追随する (標準: チャンネル幅 100pt、1時間の高さ 120pt、時刻軸の幅は
/// 縦画面で 30pt)。
/// 第2段からはタブではなく、生放送一覧から画面の上に重ねて開く形になり、
/// 番組を押すと詳細 (番組情報と予約の追加・切り替え・削除) が開く。
final class TimeTableViewController: UIViewController, UIScrollViewDelegate {
    /// 重ねて開かれた場合の「閉じる」動作。開いた側 (生放送一覧) が入れる。
    /// 入っていない場合は通常の画面として振る舞う。
    var onCloseRequested: (() -> Void)?
    /// 詳細で「視聴」が押されたときの移り方。開いた側 (生放送一覧) が入れ、
    /// 番組表を閉じてから再生画面を開く。詳細からはそのまま中継する。
    var onWatchRequested: ((LiveChannel) -> Void)?
    /// チャンネルの幅。表示設定の換算表から決まる。
    private var channelWidth: CGFloat { displaySettings.channelWidthPoints }
    /// 1時間分の高さ。表示設定の換算表から決まる。
    private var hourHeight: CGFloat { displaySettings.hourHeightPoints }
    /// チャンネルの見出し行の高さ。Web 版は幅から計算するが、スマホ用の
    /// 幅 (80〜120) ではどの段階でも 50 になるため、固定でよい。
    /// 見出しの中身 (ロゴ 32x24、番号 13、局名 10) も幅によらず同じ。
    private static let headerHeight: CGFloat = 50

    /// いま効いている表示設定。設定画面で変えられたら、その場で
    /// 組み直して反映する。
    private var displaySettings = TimeTableSettingsStore.shared.current
    /// 1日の長さ (4:00 起点の24時間)。
    private static let dayLength: TimeInterval = 24 * 3600

    /// 時刻軸の色 (Web 版 TimeTable.vue の REGZA 風の表、時刻ごと)。
    private static let timeScaleColors: [UIColor] = makeTimeScaleColors()

    private static func makeTimeScaleColors() -> [UIColor] {
        let hexValues: [UInt32] = [
            0x2A4068, 0x325080, 0x3A5C90, 0x4268A0,  // 0〜3時
            0x4A7AA0, 0x4D8898, 0x509690, 0x55A080,  // 4〜7時
            0x4C8860, 0x5C8A58, 0x6C8C52, 0x7A8C4C,  // 8〜11時
            0x7C8A48, 0x888848, 0x908248, 0x987A48,  // 12〜15時
            0x987048, 0x906248, 0x80564C, 0x6C4A50,  // 16〜19時
            0x5C4058, 0x4C3A54, 0x3C3850, 0x30384C,  // 20〜23時
        ]
        var colors: [UIColor] = []
        colors.reserveCapacity(hexValues.count)
        for hex in hexValues {
            let red = CGFloat((hex >> 16) & 0xFF) / 255
            let green = CGFloat((hex >> 8) & 0xFF) / 255
            let blue = CGFloat(hex & 0xFF) / 255
            colors.append(UIColor(red: red, green: green, blue: blue, alpha: 1))
        }
        return colors
    }

    /// 番組の無い領域の地の色 (Web 版の --timetable-empty-cell-background)。
    private static let emptyCellBackground = UIColor(
        red: 0x61 / 255, green: 0x61 / 255, blue: 0x61 / 255, alpha: 1)

    private let headerView = SPHeaderView()
    private let controlsBar = UIView()
    private let channelTypeButton = RippleButton()
    private let dateButton = RippleButton()
    private let timeButton = RippleButton()
    private let nowButton = RippleButton()
    private let settingsButton = RippleButton()
    /// 重ねて開かれた場合だけ出す「閉じる」ボタン。
    private let closeButton = RippleButton()
    /// 種別・時刻の選択ボタンの中の文字 (Web 版の選択欄と同じく、文字は
    /// 左寄せで ∨ は右端に置くため、ボタンの題名ではなく中の部品で持つ)。
    private let channelTypeTitleLabel = UILabel()
    private let timeTitleLabel = UILabel()
    private var channelTypeButtonWidth: NSLayoutConstraint?
    private var timeButtonWidth: NSLayoutConstraint?

    private let cornerView = UIView()
    private let headerScrollView = UIScrollView()
    private let headerContentView = UIView()
    private let timeScaleScrollView = UIScrollView()
    private let timeScaleContentView = UIView()
    private let gridScrollView = UIScrollView()
    private let gridContentView = UIView()
    private var headerLeadingConstraint: NSLayoutConstraint?
    private var cornerWidthConstraint: NSLayoutConstraint?
    private var timeScaleWidthConstraint: NSLayoutConstraint?
    private var gridLeadingConstraint: NSLayoutConstraint?
    private var gridTopConstraint: NSLayoutConstraint?

    private let statusLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var nowLineView: UIView?
    private var nowTimer: Timer?

    /// 表示中の放送日の開始 (その日の 4:00)。
    private var selectedDayStart = TimeTableViewController.broadcastDayStart(of: Date())
    /// ピン留めの種別を表す印 (API の種別名とは別の、アプリ内の値)。
    private static let pinnedType = "PINNED"
    /// 表示中の放送種別 ("GR" など。ピン留めのときは pinnedType)。
    private var selectedType = "GR"
    /// 切り替えに出す放送種別 (チャンネル一覧から分かる範囲)。
    private var availableTypes: [String] = []
    private var channels: [TimeTableChannelEntry] = []
    private var dateRange: TimeTableDateRange?
    /// チューナーの使用区間 (改造サーバーが番組表の応答に付けるもの)。
    /// 時刻軸の使用帯の描画に使う (拡張版だけ)。
    private var tunerBusyIntervals: [TimeTableTunerBusyInterval] = []
    /// 使用帯を「満杯」の濃さにする台数 (Web 版の固定値と同じ 2)。
    private static let maxTunerCount = 2
    private var isLoading = false

    // MARK: 表示位置の保存と復元 (拡張版だけ)

    /// 表示状態 (日付・表示位置・放送の種類) の保存先のキー。
    /// Web 版の端末ローカル保存と同じキー名にしてある。
    private static let viewStateKey = "KonomiTV-TimeTableViewState"
    /// 保存した表示状態をまだ読み戻していないか。復元は開いた直後の
    /// 最初の読み込みでだけ行う。
    private var viewStateRestorePending = true
    /// 復元する表示位置 (先頭の日時) と横スクロール量。日付の復元が
    /// できなかったときは nil のまま (位置は戻さない)。
    private var pendingRestoreTopTime: Date?
    private var pendingRestoreScrollLeft: CGFloat = 0
    /// 最初の読み込みが終わったか。終わるまでは保存しない
    /// (読み込み中の現在時刻への移動で、保存済みの位置を潰さないため)。
    private var hasCompletedInitialLoad = false
    /// スクロール中の保存を間引くための保留分。
    private var viewStateSaveWork: DispatchWorkItem?
    private var loadedBaseURLString: String?
    /// 組み立て済みの時刻軸の幅 (回転で変わったら組み直すため)。
    private var builtTimeScaleWidth: CGFloat = 0

    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (生放送一覧と同じ扱い)。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "番組表"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 時刻軸の幅。Web 版はスマホ縦画面で 30px、それ以外は 50px。
    private var timeScaleWidth: CGFloat {
        view.bounds.width > view.bounds.height ? 50 : 30
    }

    // MARK: - 画面の組み立て

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background

        // ロゴ帯は Web 版の番組表と同じく画面の先頭に固定で置く
        // (番組表は格子自体がスクロール領域を持つため、一覧画面のように
        // 中身と一緒に流す形にはしない)。
        // 重ねて開かれている場合はタップで閉じ、そうでない場合は
        // 生放送タブへ移る。
        headerView.onLogoTap = { [weak self] in
            guard let self else { return }
            if let onCloseRequested = self.onCloseRequested {
                onCloseRequested()
            } else {
                self.mainTabBarController?.selectedIndex = 0
            }
        }
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        setupControlsBar()

        // 格子の固定部分。左上の隅、チャンネルの見出し行 (横だけ追随)、
        // 時刻軸 (縦だけ追随) は、格子本体のスクロールに合わせてずらす。
        cornerView.backgroundColor = AppPalette.panel
        cornerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cornerView)

        for scrollView in [headerScrollView, timeScaleScrollView] {
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.isScrollEnabled = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
        }
        headerScrollView.addSubview(headerContentView)
        timeScaleScrollView.addSubview(timeScaleContentView)

        gridScrollView.delegate = self
        gridScrollView.backgroundColor = AppPalette.background
        gridScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridScrollView)
        gridScrollView.addSubview(gridContentView)

        statusLabel.textAlignment = .center
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        loadingIndicator.color = AppPalette.accent
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        headerLeadingConstraint = headerScrollView.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: timeScaleWidth)
        cornerWidthConstraint = cornerView.widthAnchor.constraint(
            equalToConstant: timeScaleWidth)
        timeScaleWidthConstraint = timeScaleScrollView.widthAnchor.constraint(
            equalToConstant: timeScaleWidth)
        gridLeadingConstraint = gridScrollView.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: timeScaleWidth)
        gridTopConstraint = gridScrollView.topAnchor.constraint(
            equalTo: controlsBar.bottomAnchor, constant: Self.headerHeight)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: SPHeaderView.height),
            controlsBar.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            controlsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsBar.heightAnchor.constraint(equalToConstant: 58),
            cornerView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            cornerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cornerWidthConstraint!,
            cornerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            headerScrollView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            headerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerScrollView.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            headerLeadingConstraint!,
            timeScaleScrollView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor, constant: Self.headerHeight),
            timeScaleScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timeScaleScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            timeScaleWidthConstraint!,
            gridTopConstraint!,
            gridLeadingConstraint!,
            gridScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            loadingIndicator.centerXAnchor.constraint(equalTo: gridScrollView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: gridScrollView.centerYAnchor),
        ])
        builtTimeScaleWidth = timeScaleWidth
    }

    /// 上の操作の帯。Web 版のスマホ用の並び (種別・日付・時刻・現在時刻・
    /// 表示設定) を写す。種別と時刻は押すとメニューが開くボタン、日付は
    /// 押すと日付を選ぶ画面が開くボタン、現在時刻は時計の絵のボタン、
    /// 表示設定は歯車の絵のボタン。
    /// 帯とボタンの形は Web 版のスマホ用コントロールバーの実測どおり:
    /// 帯の地は background-lighten-1 で下端に background-lighten-2 の
    /// 1px の線、内側の余白は 上 10px・下 12px・左右 10px、ボタン同士の
    /// 間隔は 6px。文字のボタンは高さ 36px・角丸 6px・地は
    /// background-lighten-1、絵のボタンは 34x34px・角丸 6px・地は
    /// background-lighten-2 で枠線なし (形の共通部品は WebControls)。
    private func setupControlsBar() {
        controlsBar.backgroundColor = AppPalette.panel
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsBar)
        // 帯の下端の線 (Web 版の border-bottom: 1px, background-lighten-2)。
        let bottomBorder = UIView()
        bottomBorder.backgroundColor = AppPalette.pressed
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.addSubview(bottomBorder)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlsBar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: controlsBar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: controlsBar.topAnchor, constant: 10),
            bottomBorder.leadingAnchor.constraint(equalTo: controlsBar.leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: controlsBar.trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
        ])

        // 種別と時刻は選択欄 (Web 版の v-select) なので、枠線は
        // on-surface の 38% の濃さ。文字は左寄せ (左の余白 12px) で、
        // ∨ は右端に置く (Web 版の選択欄の実物の並び)。
        let selectButtons: [(UIButton, UILabel, CGFloat)] = [
            (channelTypeButton, channelTypeTitleLabel, 88),
            (timeButton, timeTitleLabel, 64),
        ]
        for (button, label, minWidth) in selectButtons {
            button.styleAsTimeTableBarTextButton(borderColor: AppPalette.outlineBorder)
            button.showsMenuAsPrimaryAction = true
            setupSelectButtonContent(button, label: label)
            let width = button.widthAnchor.constraint(equalToConstant: minWidth)
            width.isActive = true
            if button === channelTypeButton {
                channelTypeButtonWidth = width
            } else {
                timeButtonWidth = width
            }
        }
        // 日付ボタンは Web 版では平たいボタンで、枠は内側の影で
        // on-surface の 26% の濃さ。文字は中央。
        dateButton.styleAsTimeTableBarTextButton(borderColor: AppPalette.outlineBorderSoft)
        dateButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        dateButton.showsMenuAsPrimaryAction = false
        dateButton.addTarget(self, action: #selector(dateButtonTapped), for: .touchUpInside)

        let clock = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        nowButton.setImage(UIImage(systemName: "clock", withConfiguration: clock), for: .normal)
        nowButton.styleAsTimeTableBarIconButton()
        nowButton.accessibilityLabel = "現在時刻に移動"
        nowButton.addTarget(self, action: #selector(nowButtonTapped), for: .touchUpInside)

        // 表示設定のボタン (Web 版のスマホ用コントロールバーの右端、
        // fluent:settings-20-regular 18px)。見た目は現在時刻ボタンと揃える。
        let gear = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gear), for: .normal)
        settingsButton.styleAsTimeTableBarIconButton()
        settingsButton.accessibilityLabel = "番組表の表示設定"
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)

        // 重ねて開かれた場合だけ、帯の先頭に「閉じる」ボタンを置く
        // (戻る導線)。形は他の絵のボタンと揃える。
        if onCloseRequested != nil {
            let close = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: close), for: .normal)
            closeButton.styleAsTimeTableBarIconButton()
            closeButton.accessibilityLabel = "番組表を閉じる"
            closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
            stack.addArrangedSubview(closeButton)
        }

        stack.addArrangedSubview(channelTypeButton)
        stack.addArrangedSubview(dateButton)
        stack.addArrangedSubview(timeButton)
        stack.addArrangedSubview(nowButton)
        stack.addArrangedSubview(settingsButton)
        updateControls()
    }

    /// 選択ボタン (種別・時刻) の中身を組み立てる。文字は左に寄せて
    /// (左の余白 12px)、∨ は右端に置く (右の余白 8px)。
    /// 中の部品はタップを受けず、ボタン自身が受ける (ジャンル色の
    /// 選択ボタンと同じ組み方)。
    private func setupSelectButtonContent(_ button: UIButton, label: UILabel) {
        label.font = .scaledSystemFont(ofSize: 14)
        label.textColor = AppPalette.text
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
        label.isUserInteractionEnabled = false
        chevron.isUserInteractionEnabled = false
    }

    /// 選択ボタンの幅を、中の文字に合わせて決め直す。
    /// 幅 = 左の余白 12 + 文字 + ∨ との間 4 + ∨ 12 + 右の余白 8 で、
    /// Web 版の固定幅 (種別 88px、時刻 64px) を下限にする。
    private func updateSelectButtonWidth(
        _ constraint: NSLayoutConstraint?, label: UILabel, minWidth: CGFloat) {
        let textWidth = ceil(label.intrinsicContentSize.width)
        constraint?.constant = max(minWidth, 12 + textWidth + 4 + 12 + 8)
    }

    /// 操作の帯の表示 (種別の名前、日付、時刻のメニュー) を現在の状態に合わせる。
    private func updateControls() {
        channelTypeTitleLabel.text = Self.prettyTypeName(selectedType)
        updateSelectButtonWidth(channelTypeButtonWidth, label: channelTypeTitleLabel, minWidth: 88)
        channelTypeButton.menu = UIMenu(children: availableTypes.map { type in
            UIAction(
                title: Self.prettyTypeName(type),
                state: type == selectedType ? .on : .off
            ) { [weak self] _ in
                guard let self, type != self.selectedType else { return }
                self.selectedType = type
                self.updateControls()
                self.saveViewState()
                self.load(scrollToNowAfter: Self.isToday(self.selectedDayStart))
            }
        })
        dateButton.setTitle(Self.dateLabel(for: selectedDayStart), for: .normal)
        setTimeButtonTitle(timeSlotLabel(for: gridScrollView.contentOffset.y))
        timeButton.menu = UIMenu(children: [4, 8, 12, 16, 20, 24].map { hour in
            UIAction(title: String(format: "%02d時", hour)) { [weak self] _ in
                self?.scrollToHour(hour)
            }
        })
    }

    /// 時刻の選択ボタンの文字と幅を合わせ直す。
    private func setTimeButtonTitle(_ title: String) {
        timeTitleLabel.text = title
        updateSelectButtonWidth(timeButtonWidth, label: timeTitleLabel, minWidth: 64)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 先頭画面ではシステムのナビゲーションバーを隠す (他のタブと同じ)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 現在時刻の線は表示中だけ進める。
        nowTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateNowLine()
        }
        let current = SettingsStore.shared.baseURL?.absoluteString
        if channels.isEmpty || current != loadedBaseURLString {
            loadInitial()
        }
        // 表示設定は、同期が入っていればサーバー側の値が正になる
        // (Web 版で変えた幅や色が、次にこの画面を開いたときに効く)。
        // 取り込みは裏で行い、変わっていたときだけ組み直す。
        Task { [weak self] in
            guard let self else { return }
            if await TimeTableSettingsStore.shared.refreshFromServer() {
                self.applyDisplaySettings(TimeTableSettingsStore.shared.current)
            }
        }
    }

    /// 表示設定を差し替えて、格子を組み直す。スクロールの位置は
    /// 組み直しの前後でなるべく保つ (寸法が変わるため、収まる範囲に
    /// 丸めて戻す)。
    private func applyDisplaySettings(_ settings: TimeTableDisplaySettings) {
        guard settings != displaySettings else { return }
        displaySettings = settings
        guard !channels.isEmpty else { return }
        let offset = gridScrollView.contentOffset
        buildGrid()
        let maxX = max(gridScrollView.contentSize.width - gridScrollView.bounds.width, 0)
        let maxY = max(gridScrollView.contentSize.height - gridScrollView.bounds.height, 0)
        gridScrollView.contentOffset = CGPoint(
            x: min(max(offset.x, 0), maxX), y: min(max(offset.y, 0), maxY))
        // 追随側のスクロール位置もそろえる (scrollViewDidScroll は
        // 組み直しの最中には呼ばれないため)。
        headerScrollView.contentOffset.x = gridScrollView.contentOffset.x
        timeScaleScrollView.contentOffset.y = gridScrollView.contentOffset.y
    }

    /// 表示設定の画面を開く。値が変わるたびに、その場で格子へ反映する。
    @objc private func settingsButtonTapped() {
        let settingsController = TimeTableSettingsViewController()
        settingsController.onSettingsChanged = { [weak self] settings in
            self?.applyDisplaySettings(settings)
        }
        // 塗りと使用帯のスイッチは、材料 (使用帯) の取り直しが要るため、
        // 番組表を読み直して反映する。読み直しのあとも見ていた場所が
        // 保たれるよう、今の表示位置を復元用の控えへ移してから読み直す。
        settingsController.onReservationHighlightChanged = { [weak self] in
            guard let self else { return }
            self.pendingRestoreTopTime = self.selectedDayStart.addingTimeInterval(
                Double(self.gridScrollView.contentOffset.y / self.hourHeight) * 3600)
            self.pendingRestoreScrollLeft = self.gridScrollView.contentOffset.x
            self.load(scrollToNowAfter: false)
        }
        if let sheet = settingsController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(settingsController, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        nowTimer?.invalidate()
        nowTimer = nil
        // 間引いて保留していた表示位置の保存があれば、離れる前に
        // その場で保存する (Web 版の画面を離れるときの保存と同じ)。
        viewStateSaveWork?.cancel()
        viewStateSaveWork = nil
        saveViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 回転で時刻軸の幅が変わったら、固定部分の幅と格子の組み直しを行う。
        let width = timeScaleWidth
        guard width != builtTimeScaleWidth, builtTimeScaleWidth != 0 else { return }
        builtTimeScaleWidth = width
        headerLeadingConstraint?.constant = width
        cornerWidthConstraint?.constant = width
        timeScaleWidthConstraint?.constant = width
        gridLeadingConstraint?.constant = width
        buildGrid()
    }

    // MARK: - 日付まわり

    /// 放送日の開始 (その日の 4:00)。4:00 より前は前日の放送日になる
    /// (Web 版の番組表の日付の切り替わりと同じ)。
    static func broadcastDayStart(of date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 4
        components.minute = 0
        components.second = 0
        var start = calendar.date(from: components) ?? date
        if date < start {
            start = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        }
        return start
    }

    private static func isToday(_ dayStart: Date) -> Bool {
        dayStart == broadcastDayStart(of: Date())
    }

    /// 日付ボタンの文字 (Web 版と同じ "M/D (曜)" の形)。
    private static func dateLabel(for dayStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d (E)"
        return formatter.string(from: dayStart)
    }

    /// 時刻ボタンの文字。今見えている先頭の時刻に一番近い区切り (4時間ごと)。
    private func timeSlotLabel(for offsetY: CGFloat) -> String {
        let hour = 4 + Int((max(offsetY, 0) / hourHeight / 4).rounded()) * 4
        return String(format: "%02d時", min(hour, 24))
    }

    /// API の種別名を表示用の名前にする (生放送一覧と同じ表現)。
    private static func prettyTypeName(_ type: String) -> String {
        switch type {
        case Self.pinnedType: return "ピン留め"
        case "GR": return "地デジ"
        case "BS": return "BS"
        case "CS": return "CS"
        case "CATV": return "CATV"
        case "SKY": return "SKY"
        case "BS4K": return "BS4K"
        default: return type
        }
    }

    // MARK: - 読み込み

    /// 初回の読み込み。切り替えに出す種別はチャンネル一覧から先に取り、
    /// そのあと番組表を取る。
    private func loadInitial() {
        guard SettingsStore.shared.isConfigured else {
            statusLabel.text = "設定タブで接続先 URL を設定してください。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            // 同期が入っていれば、利用者設定を取り込んでおく
            // (ピン留めの有無を種別の出し分けに使うため)。
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            if let response = try? await APIClient.shared.fetchChannels() {
                var types = response.groups.map { $0.type }
                if !types.isEmpty {
                    // ピン留め中のチャンネルがあれば、種別の先頭に
                    // ピン留めを足す (Web 版の番組表と同じ。ピン留めが
                    // 無いときは出さない)。
                    let allIDs = Set(response.groups.flatMap { $0.channels }.map { $0.id })
                    let hasPinned = SyncedSettingsStore.shared.current.pinnedChannelIDs
                        .contains { allIDs.contains($0) }
                    if hasPinned {
                        types.insert(Self.pinnedType, at: 0)
                    }
                    self.availableTypes = types
                    // 保存しておいた放送の種類があれば、最初の取得から
                    // その種類で開く (表示位置の復元の一部。拡張版だけ)。
                    if self.viewStateRestorePending {
                        self.consumeSavedViewState(availableTypes: types)
                    }
                    if !types.contains(self.selectedType) {
                        self.selectedType = types[0]
                    }
                    self.updateControls()
                }
            }
            self.load(scrollToNowAfter: true)
        }
    }

    /// 番組表を取り直して格子を組み直す。
    private func load(scrollToNowAfter: Bool) {
        guard !isLoading else { return }
        guard SettingsStore.shared.isConfigured else {
            statusLabel.text = "設定タブで接続先 URL を設定してください。"
            return
        }
        if SettingsStore.shared.baseURL?.absoluteString != loadedBaseURLString {
            logoCache.removeAllObjects()
            failedLogoIDs.removeAll()
        }
        isLoading = true
        loadingIndicator.startAnimating()
        let dayStart = selectedDayStart
        let type = selectedType
        Task { [weak self] in
            guard let self else { return }
            do {
                // ピン留めの種別では、種別の代わりにピン留め中の
                // チャンネルの ID を渡す (Web 版の番組表と同じ)。
                let isPinned = type == Self.pinnedType
                let response = try await APIClient.shared.fetchTimeTable(
                    start: dayStart,
                    end: dayStart.addingTimeInterval(Self.dayLength),
                    channelType: isPinned ? nil : type,
                    pinnedChannelIDs: isPinned
                        ? SyncedSettingsStore.shared.current.pinnedChannelIDs : nil)
                self.loadedBaseURLString = SettingsStore.shared.baseURL?.absoluteString
                self.channels = response.channels
                self.dateRange = response.date_range
                // チューナーの使用帯は、番組表の表示設定の専用スイッチが
                // オンのときだけ受け取る (トグルの対象からは外した)。
                self.tunerBusyIntervals = SettingsStore.shared.timeTableReservationHighlightEnabled
                    ? (response.tuner_busy_intervals ?? []) : []
                self.statusLabel.text = self.channels.isEmpty ? "番組表がありません。" : nil
                self.buildGrid()
                self.hasCompletedInitialLoad = true
                if self.pendingRestoreTopTime != nil {
                    // 保存しておいた表示位置へ戻す (最初の読み込みだけ)。
                    self.applyRestoredScrollPosition()
                    self.pendingRestoreTopTime = nil
                    self.pendingRestoreScrollLeft = 0
                } else if scrollToNowAfter {
                    self.pendingRestoreScrollLeft = 0
                    // 組み直した直後はレイアウトが済んでから現在時刻へ寄せる。
                    DispatchQueue.main.async { [weak self] in
                        self?.scrollToNow(animated: false)
                    }
                }
            } catch {
                if self.channels.isEmpty {
                    self.statusLabel.text = "読み込めませんでした。\n接続先とネットワークを確認してください。\n(\(error.localizedDescription))"
                }
            }
            self.isLoading = false
            self.loadingIndicator.stopAnimating()
            // 読み込み中に日付や種別が変わっていたら、古い条件の結果を
            // 出したままにせず、今の条件で取り直す。
            if self.selectedDayStart != dayStart || self.selectedType != type {
                self.load(scrollToNowAfter: Self.isToday(self.selectedDayStart))
            }
        }
    }

    // MARK: - 格子の組み立て

    /// 取得済みのチャンネルと番組から、見出し行・時刻軸・格子本体を作る。
    private func buildGrid() {
        for view in headerContentView.subviews { view.removeFromSuperview() }
        for view in timeScaleContentView.subviews { view.removeFromSuperview() }
        for view in gridContentView.subviews { view.removeFromSuperview() }
        nowLineView = nil

        let totalWidth = CGFloat(channels.count) * channelWidth
        let totalHeight = 24 * hourHeight
        headerContentView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: Self.headerHeight)
        headerScrollView.contentSize = headerContentView.frame.size
        timeScaleContentView.frame = CGRect(x: 0, y: 0, width: timeScaleWidth, height: totalHeight)
        timeScaleScrollView.contentSize = timeScaleContentView.frame.size
        gridContentView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        gridScrollView.contentSize = gridContentView.frame.size

        buildTimeScale(totalHeight: totalHeight)

        let now = Date()
        for (index, entry) in channels.enumerated() {
            let columnX = CGFloat(index) * channelWidth
            // 見出し (ロゴと局名)。
            let headerCell = TimeTableChannelHeaderView(
                channel: entry.channel,
                frame: CGRect(x: columnX, y: 0, width: channelWidth, height: Self.headerHeight))
            headerContentView.addSubview(headerCell)
            if let logo = logoCache.object(forKey: entry.channel.id as NSString) {
                headerCell.setLogo(logo)
            } else {
                loadLogo(for: entry.channel, into: headerCell)
            }
            // 列の地 (番組の無い領域)。
            let columnView = UIView(frame: CGRect(
                x: columnX, y: 0, width: channelWidth, height: totalHeight))
            columnView.backgroundColor = Self.emptyCellBackground
            let columnBorder = UIView(frame: CGRect(
                x: channelWidth - 1, y: 0, width: 1, height: totalHeight))
            columnBorder.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            columnView.addSubview(columnBorder)
            gridContentView.addSubview(columnView)
            // 番組の枠。サブチャンネルの番組は同じ列に重ね、重なる相手が
            // いる枠同士は列を半分ずつに分ける (Web 版と同じ分け方)。
            let subPrograms = (entry.subchannels ?? []).flatMap { $0.programs }
            for program in entry.programs {
                addProgramCell(
                    program, columnX: columnX, isSubchannel: false,
                    others: subPrograms, now: now, channel: entry.channel)
            }
            for subchannel in entry.subchannels ?? [] {
                for program in subchannel.programs {
                    addProgramCell(
                        program, columnX: columnX, isSubchannel: true,
                        others: entry.programs, now: now, channel: subchannel.channel)
                }
            }
        }
        updateNowLine()
        updateControls()
    }

    /// 時刻軸 (1時間ごとの色帯と時刻の文字) を作る。
    private func buildTimeScale(totalHeight: CGFloat) {
        let calendar = Calendar.current
        for hourIndex in 0..<24 {
            let hourDate = selectedDayStart.addingTimeInterval(Double(hourIndex) * 3600)
            let hour = calendar.component(.hour, from: hourDate)
            let block = UIView(frame: CGRect(
                x: 0, y: CGFloat(hourIndex) * hourHeight,
                width: timeScaleWidth, height: hourHeight))
            block.backgroundColor = Self.timeScaleColors[hour]
            // チューナーの使用帯 (改造版 Web の時刻軸の帯)。出すかどうかは
            // 番組表の表示設定の専用スイッチで決める。
            // 帯は台数によらず軸の全幅で出し、台数の違いは濃さだけで
            // 表す (一部使用は不透明度 0.8、満杯は 1.0)。過去の区間も
            // 同じ濃さ。帯は時刻・日付の文字より後ろに置くため、
            // この時点 (文字を足す前) に入れる。
            if SettingsStore.shared.timeTableReservationHighlightEnabled {
                let hourEnd = hourDate.addingTimeInterval(3600)
                for interval in tunerBusyIntervals {
                    guard let start = interval.startDate, let end = interval.endDate else { continue }
                    let segmentStart = max(start, hourDate)
                    let segmentEnd = min(end, hourEnd)
                    guard segmentEnd > segmentStart else { continue }
                    let band = UIView(frame: CGRect(
                        x: 0,
                        y: CGFloat(segmentStart.timeIntervalSince(hourDate) / 3600) * hourHeight,
                        width: timeScaleWidth,
                        height: CGFloat(segmentEnd.timeIntervalSince(segmentStart) / 3600) * hourHeight))
                    band.backgroundColor = AppPalette.secondary.withAlphaComponent(
                        interval.tuner_count >= Self.maxTunerCount ? 1.0 : 0.8)
                    block.addSubview(band)
                }
            }
            let border = UIView(frame: CGRect(
                x: 0, y: hourHeight - 1, width: timeScaleWidth, height: 1))
            border.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            block.addSubview(border)
            // 文字は帯の上部に寄せる (Web 版は上に張り付く形だが、ここでは
            // 各帯の上端に置くことで同じ見え方にする)。
            var labelY: CGFloat = 6
            // 28 時間表記が入っているときは、0〜3 時台の見出しを 24〜27 にし、
            // 日付の見出しも前日のものにする (Web 版と同じ)。
            let use28 = SyncedSettingsStore.shared.current.use28HourClock
            let displayHour = (use28 && hour < 4) ? hour + 24 : hour
            let displayDate = (use28 && hour < 4)
                ? (calendar.date(byAdding: .day, value: -1, to: hourDate) ?? hourDate) : hourDate
            // 日付の印は 4時間ごと (0/4/8/12/16/20時) に出す。
            // なお、番組表の中の文字 (時刻の帯・局名・番組の枠) は、
            // 升目の寸法 (番組表の表示設定の幅・密度) と一体のため、
            // 表示の大きさ (UIScale) の対象外として元の大きさのままにする。
            if [0, 4, 8, 12, 16, 20].contains(hour) {
                let dateLabel = UILabel(frame: CGRect(x: 1, y: labelY, width: timeScaleWidth - 2, height: 14))
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.dateFormat = "M/d"
                dateLabel.text = formatter.string(from: displayDate)
                dateLabel.font = .systemFont(ofSize: 10, weight: .bold)
                dateLabel.textColor = UIColor.white.withAlphaComponent(0.9)
                dateLabel.textAlignment = .center
                dateLabel.backgroundColor = UIColor.white.withAlphaComponent(0.15)
                dateLabel.layer.cornerRadius = 2
                dateLabel.clipsToBounds = true
                block.addSubview(dateLabel)
                labelY += 18
            }
            let hourLabel = UILabel(frame: CGRect(
                x: 0, y: labelY, width: timeScaleWidth, height: 20))
            hourLabel.text = String(format: "%02d", displayHour)
            hourLabel.font = .systemFont(ofSize: 17, weight: .bold)
            hourLabel.textColor = .white
            hourLabel.textAlignment = .center
            hourLabel.shadowColor = UIColor.black.withAlphaComponent(0.5)
            hourLabel.shadowOffset = CGSize(width: 0, height: 1)
            block.addSubview(hourLabel)
            let unitLabel = UILabel(frame: CGRect(
                x: 0, y: labelY + 20, width: timeScaleWidth, height: 12))
            unitLabel.text = "時"
            unitLabel.font = .systemFont(ofSize: 10)
            unitLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            unitLabel.textAlignment = .center
            block.addSubview(unitLabel)
            timeScaleContentView.addSubview(block)
        }
    }

    /// 番組の枠を1つ置く。表示範囲 (その日の 4:00〜翌 4:00) の外側は切り取る。
    /// 枠を押すと番組の詳細が開く (channel はその番組の属する局。
    /// サブチャンネルの番組ではサブチャンネル側の局になる)。
    private func addProgramCell(
        _ program: TimeTableProgram,
        columnX: CGFloat,
        isSubchannel: Bool,
        others: [TimeTableProgram],
        now: Date,
        channel: ChannelInfo
    ) {
        guard let start = program.startDate, let end = program.endDate else { return }
        let dayEnd = selectedDayStart.addingTimeInterval(Self.dayLength)
        let clippedStart = max(start, selectedDayStart)
        let clippedEnd = min(end, dayEnd)
        guard clippedEnd > clippedStart else { return }
        // 重なる相手がいる枠は列を半分にする。サブチャンネルは右半分。
        let isSplit = others.contains { other in
            guard let otherStart = other.startDate, let otherEnd = other.endDate else { return false }
            return otherStart < end && otherEnd > start
        }
        let width = isSplit ? channelWidth / 2 : channelWidth
        let x = columnX + (isSubchannel && isSplit ? channelWidth / 2 : 0)
        let y = CGFloat(clippedStart.timeIntervalSince(selectedDayStart) / 3600) * hourHeight
        let height = CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 3600) * hourHeight
        let cell = TimeTableProgramCellView(
            program: program, isPast: end <= now, settings: displaySettings)
        cell.frame = CGRect(x: x, y: y, width: width, height: height)
        cell.isUserInteractionEnabled = true
        let tap = ProgramCellTapGestureRecognizer(
            target: self, action: #selector(programCellTapped(_:)))
        tap.program = program
        tap.channel = channel
        tap.cancelsTouchesInView = false
        cell.addGestureRecognizer(tap)
        gridContentView.addSubview(cell)
    }

    /// 番組の枠が押されたら詳細を開く。詳細で予約が変わったら、
    /// 戻ってきたときに番組表を取り直して色分けへ反映する。
    @objc private func programCellTapped(_ gesture: ProgramCellTapGestureRecognizer) {
        guard let program = gesture.program, let channel = gesture.channel else { return }
        let detail = ReservationDetailViewController(
            program: program, channel: channel, reservationSummary: program.reservation)
        detail.onChanged = { [weak self] in
            self?.load(scrollToNowAfter: false)
        }
        detail.onWatchRequested = { [weak self] channel in
            self?.onWatchRequested?(channel)
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    @objc private func closeButtonTapped() {
        onCloseRequested?()
    }

    /// 局ロゴを取ってきて、見出しがまだ同じ局ならその場で反映する。
    private func loadLogo(for channel: ChannelInfo, into headerCell: TimeTableChannelHeaderView) {
        guard !failedLogoIDs.contains(channel.id) else { return }
        Task { [weak self, weak headerCell] in
            guard let self else { return }
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channel.id),
                  let image = UIImage(data: data) else {
                self.failedLogoIDs.insert(channel.id)
                return
            }
            self.logoCache.setObject(image, forKey: channel.id as NSString)
            headerCell?.setLogo(image)
        }
    }

    // MARK: - 現在時刻の線

    /// 現在時刻の線を引き直す。表示中の日付が今日の放送日のときだけ出す。
    private func updateNowLine() {
        nowLineView?.removeFromSuperview()
        nowLineView = nil
        let now = Date()
        let dayEnd = selectedDayStart.addingTimeInterval(Self.dayLength)
        guard now >= selectedDayStart, now < dayEnd, !channels.isEmpty else { return }
        let y = CGFloat(now.timeIntervalSince(selectedDayStart) / 3600) * hourHeight
        let line = UIView(frame: CGRect(
            x: 0, y: y - 1, width: gridContentView.bounds.width, height: 2))
        line.backgroundColor = AppPalette.secondary
        line.layer.shadowColor = AppPalette.secondary.cgColor
        line.layer.shadowOpacity = 0.5
        line.layer.shadowRadius = 4
        line.layer.shadowOffset = .zero
        // 左端の丸い印。
        let dot = UIView(frame: CGRect(x: 0, y: -5, width: 12, height: 12))
        dot.backgroundColor = AppPalette.secondary
        dot.layer.cornerRadius = 6
        line.addSubview(dot)
        gridContentView.addSubview(line)
        nowLineView = line
    }

    // MARK: - 表示位置の保存と復元

    /// 保存しておいた表示状態を読み戻す (最初の読み込みで1回だけ)。
    /// 放送の種類は、保存時の表示名と一致するものが今も選べるときだけ
    /// 戻す。日付は、保存した日が今日 (放送日基準) より前なら戻さず、
    /// その場合は表示位置も戻さない (種類だけは戻す。Web 版と同じ)。
    private func consumeSavedViewState(availableTypes: [String]) {
        viewStateRestorePending = false
        guard let state = UserDefaults.standard.dictionary(forKey: Self.viewStateKey) else { return }
        if let typeName = state["channel_type"] as? String,
           let matched = availableTypes.first(where: { Self.prettyTypeName($0) == typeName }) {
            selectedType = matched
        }
        let formatter = ISO8601DateFormatter()
        guard let dateText = state["date"] as? String, let savedDate = formatter.date(from: dateText),
              Self.broadcastDayStart(of: savedDate) >= Self.broadcastDayStart(of: Date()) else { return }
        selectedDayStart = Self.broadcastDayStart(of: savedDate)
        if let topText = state["display_top_time"] as? String, let topTime = formatter.date(from: topText) {
            pendingRestoreTopTime = topTime
        }
        pendingRestoreScrollLeft = CGFloat((state["scroll_left"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// 保存しておいた表示位置へ戻す。保存時の先頭日時が表示範囲の
    /// 外れていたら、現在時刻への移動に切り替える (Web 版と同じ)。
    private func applyRestoredScrollPosition() {
        guard let topTime = pendingRestoreTopTime else { return }
        let dayEnd = selectedDayStart.addingTimeInterval(Self.dayLength)
        guard topTime >= selectedDayStart, topTime < dayEnd else {
            scrollToNow(animated: false)
            return
        }
        let maxX = max(gridScrollView.contentSize.width - gridScrollView.bounds.width, 0)
        let maxY = max(gridScrollView.contentSize.height - gridScrollView.bounds.height, 0)
        let y = CGFloat(topTime.timeIntervalSince(selectedDayStart) / 3600) * hourHeight
        gridScrollView.contentOffset = CGPoint(
            x: min(max(pendingRestoreScrollLeft, 0), maxX),
            y: min(max(y, 0), maxY))
        headerScrollView.contentOffset.x = gridScrollView.contentOffset.x
        timeScaleScrollView.contentOffset.y = gridScrollView.contentOffset.y
    }

    /// 表示状態 (日付・表示位置・放送の種類) を端末ローカルに保存する。
    /// 表示位置はピクセルではなく日時で持つ (表示幅や1時間の高さが
    /// 変わっても意味が保たれるため。Web 版と同じ)。最初の読み込みが
    /// 終わるまでは保存しない。
    private func saveViewState() {
        guard hasCompletedInitialLoad else { return }
        let topTime = selectedDayStart.addingTimeInterval(
            Double(gridScrollView.contentOffset.y / hourHeight) * 3600)
        let formatter = ISO8601DateFormatter()
        UserDefaults.standard.set([
            "date": formatter.string(from: selectedDayStart),
            "display_top_time": formatter.string(from: topTime),
            "scroll_left": Double(gridScrollView.contentOffset.x),
            "channel_type": Self.prettyTypeName(selectedType),
        ], forKey: Self.viewStateKey)
    }

    /// スクロール中の保存を間引いて行う (Web 版の 300ms の間引きと同じ)。
    private func scheduleViewStateSave() {
        viewStateSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveViewState() }
        viewStateSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - スクロール

    /// 格子のスクロールに、見出し行 (横) と時刻軸 (縦) を追随させる。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === gridScrollView else { return }
        headerScrollView.contentOffset.x = scrollView.contentOffset.x
        timeScaleScrollView.contentOffset.y = scrollView.contentOffset.y
        setTimeButtonTitle(timeSlotLabel(for: scrollView.contentOffset.y))
        scheduleViewStateSave()
    }

    /// 指定した時刻 (4〜24時) が先頭に来るよう縦に送る。
    private func scrollToHour(_ hour: Int) {
        let targetY = CGFloat(hour - 4) * hourHeight
        let maxY = max(gridScrollView.contentSize.height - gridScrollView.bounds.height, 0)
        gridScrollView.setContentOffset(
            CGPoint(x: gridScrollView.contentOffset.x, y: min(targetY, maxY)), animated: true)
    }

    /// 現在時刻が少し上に見える位置へ送る (Web 版の初期表示と同じ考え方)。
    private func scrollToNow(animated: Bool) {
        let now = Date()
        guard now >= selectedDayStart, now < selectedDayStart.addingTimeInterval(Self.dayLength) else { return }
        let y = CGFloat(now.timeIntervalSince(selectedDayStart) / 3600) * hourHeight
        let maxY = max(gridScrollView.contentSize.height - gridScrollView.bounds.height, 0)
        let target = min(max(y - hourHeight / 2, 0), maxY)
        gridScrollView.setContentOffset(
            CGPoint(x: gridScrollView.contentOffset.x, y: target), animated: animated)
    }

    // MARK: - 操作

    @objc private func nowButtonTapped() {
        let todayStart = Self.broadcastDayStart(of: Date())
        if todayStart != selectedDayStart {
            selectedDayStart = todayStart
            updateControls()
            saveViewState()
            load(scrollToNowAfter: true)
        } else {
            scrollToNow(animated: true)
        }
    }

    /// 日付を選ぶ画面を開く。選べる範囲は番組データの範囲 (date_range) に
    /// 合わせる (Web 版の日付選択と同じ範囲)。
    @objc private func dateButtonTapped() {
        let pickerController = UIViewController()
        pickerController.view.backgroundColor = AppPalette.background
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale(identifier: "ja_JP")
        picker.calendar = Calendar(identifier: .gregorian)
        picker.date = selectedDayStart
        if let range = dateRange {
            if let earliest = range.earliestDate {
                picker.minimumDate = Self.broadcastDayStart(of: earliest)
            }
            if let latest = range.latestDate {
                picker.maximumDate = Self.broadcastDayStart(of: latest)
            }
        }
        picker.translatesAutoresizingMaskIntoConstraints = false
        pickerController.view.addSubview(picker)

        // 小さな文字ボタンにも、押したときの波紋を付ける (共通部品)。
        let cancelButton = RippleButton()
        cancelButton.setTitle("キャンセル", for: .normal)
        cancelButton.setTitleColor(AppPalette.metaText, for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        pickerController.view.addSubview(cancelButton)
        let doneButton = RippleButton()
        doneButton.setTitle("決定", for: .normal)
        doneButton.setTitleColor(AppPalette.accent, for: .normal)
        doneButton.titleLabel?.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        pickerController.view.addSubview(doneButton)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: pickerController.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: pickerController.view.topAnchor, constant: 24),
            cancelButton.leadingAnchor.constraint(equalTo: pickerController.view.leadingAnchor, constant: 20),
            cancelButton.topAnchor.constraint(equalTo: pickerController.view.topAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: pickerController.view.trailingAnchor, constant: -20),
            doneButton.topAnchor.constraint(equalTo: pickerController.view.topAnchor, constant: 16),
        ])
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self, weak picker] _ in
            guard let self, let picker else { return }
            // 選んだ日付の 4:00 を、その放送日の開始とする。
            var components = Calendar.current.dateComponents(
                [.year, .month, .day], from: picker.date)
            components.hour = 4
            components.minute = 0
            components.second = 0
            if let dayStart = Calendar.current.date(from: components), dayStart != self.selectedDayStart {
                self.selectedDayStart = dayStart
                self.updateControls()
                self.saveViewState()
                self.load(scrollToNowAfter: Self.isToday(dayStart))
            }
            self.dismiss(animated: true)
        }, for: .touchUpInside)
        if let sheet = pickerController.sheetPresentationController {
            sheet.detents = [.medium()]
        }
        present(pickerController, animated: true)
    }
}

/// 番組表のチャンネルの見出し1つ分。Web 版 (TimeTableChannelHeader.vue) どおり:
/// 左に局ロゴ (32x24、角丸4)、右にチャンネル番号 (太字13) と局名 (10)。
/// 地は background-lighten-1、右と下に background-lighten-2 の線。
private final class TimeTableChannelHeaderView: UIView {
    private let logoImageView = UIImageView()

    init(channel: ChannelInfo, frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppPalette.panel

        let rightBorder = UIView(frame: CGRect(x: frame.width - 1, y: 0, width: 1, height: frame.height))
        rightBorder.backgroundColor = AppPalette.pressed
        rightBorder.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
        addSubview(rightBorder)
        let bottomBorder = UIView(frame: CGRect(x: 0, y: frame.height - 1, width: frame.width, height: 1))
        bottomBorder.backgroundColor = AppPalette.pressed
        bottomBorder.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        addSubview(bottomBorder)

        // ロゴの受け。読み込まれるまでの地は background-lighten-2。
        let logoWrapper = UIView(frame: CGRect(x: 4, y: (frame.height - 24) / 2, width: 32, height: 24))
        logoWrapper.backgroundColor = AppPalette.pressed
        logoWrapper.layer.cornerRadius = 4
        logoWrapper.clipsToBounds = true
        logoImageView.frame = logoWrapper.bounds
        logoImageView.contentMode = .scaleAspectFill
        logoImageView.clipsToBounds = true
        logoWrapper.addSubview(logoImageView)
        addSubview(logoWrapper)

        // 番号と局名は縦に2段。
        let infoX: CGFloat = 4 + 32 + 6
        let infoWidth = frame.width - infoX - 4
        let numberLabel = UILabel(frame: CGRect(x: infoX, y: 9, width: infoWidth, height: 16))
        numberLabel.text = channel.channel_number
        numberLabel.font = .systemFont(ofSize: 13, weight: .bold)
        numberLabel.textColor = AppPalette.text
        addSubview(numberLabel)
        let nameLabel = UILabel(frame: CGRect(x: infoX, y: 27, width: infoWidth, height: 13))
        nameLabel.text = channel.name
        nameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        nameLabel.textColor = AppPalette.text
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLogo(_ image: UIImage) {
        logoImageView.image = image
    }
}

/// 番組表の番組の枠1つ分。Web 版 (TimeTableProgramCell.vue) どおり:
/// 地はジャンル色の背景、左端にジャンル色の帯 (5px)、中身は
/// 開始の分＋予約の印 → 題名 → 説明 の縦並び。
/// 過去の番組は色を灰色寄りに落とし、通販番組は控えめにする。
/// 予約がある枠には、状態に応じた色の破線の枠を付ける。
/// 押したときの反応は、共通部品の波紋の土台 (RippleSurfaceView) で出す。
/// 地が明るいジャンル色で文字が黒いため、波紋の色は黒にする
/// (本家もその面の文字色で波紋を描く)。
private final class TimeTableProgramCellView: RippleSurfaceView {
    private let program: TimeTableProgram
    private let isPast: Bool
    /// 通販番組を控えめにする扱いが効いているか (番組が通販で、かつ
    /// 表示設定の「控えめに表示する」が入っているときだけ true)。
    /// 設定が切れているときは、通販番組も通常のジャンル色で出す。
    private let dimmedShopping: Bool
    private var borderLayer: CAShapeLayer?

    init(program: TimeTableProgram, isPast: Bool, settings: TimeTableDisplaySettings) {
        self.program = program
        self.isPast = isPast
        self.dimmedShopping = program.isShopping && settings.dimShoppingPrograms
        super.init(frame: .zero)
        clipsToBounds = true
        ripple.color = .black

        // 地と帯の色。通販は灰色寄り (Web 版の color-mix の割合どおり)、
        // 過去は別の灰色寄りにする。両方に当たる場合は過去＋通販の割合。
        let genre = TimeTableGenre.colors(forMajor: program.genreMajor, settings: settings)
        var background = genre.background
        var highlight = genre.highlight
        // 予約のある番組は、ジャンルの地の上にテーマ色を薄く重ねて塗る
        // (改造版 Web の番組表の塗り)。出すかどうかは番組表の表示設定の
        // 専用スイッチで決める。割合は Web 版どおり:
        // 予約済みは secondary 22%、録画中は secondary 38%、
        // 一部のみは warning 30%、不可は error 32%。複数の状態に当たる
        // ときの優先は Web 版の CSS の並び順 (後に書かれたものが勝つ)
        // どおり、不可 → 一部のみ → 録画中 → 予約済み。無効化された
        // 予約では塗らない。
        if SettingsStore.shared.timeTableReservationHighlightEnabled,
           let reservation = program.reservation,
           reservation.status != "Disabled" {
            if reservation.recording_availability == "Unavailable" {
                background = TimeTableGenre.blended(background, with: Self.errorColor, baseRatio: 0.68)
            } else if reservation.recording_availability == "Partial" {
                background = TimeTableGenre.blended(background, with: AppPalette.warning, baseRatio: 0.70)
            } else if reservation.status == "Recording" {
                background = TimeTableGenre.blended(background, with: AppPalette.secondary, baseRatio: 0.62)
            } else {
                background = TimeTableGenre.blended(background, with: AppPalette.secondary, baseRatio: 0.78)
            }
        }
        if dimmedShopping && isPast {
            let gray = UIColor(red: 0xB7 / 255, green: 0xB7 / 255, blue: 0xB7 / 255, alpha: 1)
            background = TimeTableGenre.blended(background, with: gray, baseRatio: 0.45)
            highlight = TimeTableGenre.blended(highlight, with: gray, baseRatio: 0.45)
        } else if dimmedShopping {
            let gray = UIColor(red: 0xCF / 255, green: 0xCF / 255, blue: 0xCF / 255, alpha: 1)
            background = TimeTableGenre.blended(background, with: gray, baseRatio: 0.45)
            highlight = TimeTableGenre.blended(highlight, with: gray, baseRatio: 0.45)
        } else if isPast {
            let gray = UIColor(red: 0xC4 / 255, green: 0xC4 / 255, blue: 0xC4 / 255, alpha: 1)
            background = TimeTableGenre.blended(background, with: gray, baseRatio: 0.6)
            highlight = TimeTableGenre.blended(highlight, with: gray, baseRatio: 0.6)
        }
        backgroundColor = background

        let highlightView = UIView()
        highlightView.backgroundColor = highlight
        highlightView.tag = 1
        addSubview(highlightView)

        // 下端の区切り線。
        let bottomBorder = UIView()
        bottomBorder.backgroundColor = UIColor.black.withAlphaComponent(0.1)
        bottomBorder.tag = 2
        addSubview(bottomBorder)

        setUpLabels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 文字の濃さ。Web 版の指定どおり、通常／過去／通販で変える。
    private var minuteAlpha: CGFloat { isPast ? 0.6 : 0.7 }
    private var titleAlpha: CGFloat {
        if dimmedShopping && !isPast { return 0.7 }
        return isPast ? 0.6 : 0.9
    }
    private var descriptionAlpha: CGFloat {
        if dimmedShopping && !isPast { return 0.6 }
        return isPast ? 0.55 : 0.7
    }

    private let minuteLabel = UILabel()
    private let reservationIconView = UIImageView()
    private let recordingDotView = UIView()
    private let availabilityIconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()

    private func setUpLabels() {
        // 開始の分 (Web 版は分の数字だけを太字11pxで出す)。
        if let start = program.startDate {
            minuteLabel.text = String(format: "%02d", Calendar.current.component(.minute, from: start))
        }
        minuteLabel.font = .systemFont(ofSize: 11, weight: .bold)
        minuteLabel.textColor = UIColor.black.withAlphaComponent(minuteAlpha)
        addSubview(minuteLabel)

        // 予約の印と、状態に応じた小さな印 (録画中の点、一部のみ・不可の印)。
        if let reservation = program.reservation {
            let iconColor = Self.reservationIconColor(reservation)
            let symbolName = reservation.status == "Disabled" ? "pause.circle" : "timer"
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            reservationIconView.image = UIImage(systemName: symbolName, withConfiguration: config)
            reservationIconView.tintColor = iconColor
            reservationIconView.contentMode = .scaleAspectFit
            addSubview(reservationIconView)
            if reservation.status == "Recording" {
                recordingDotView.backgroundColor = UIColor(
                    red: 0xEF / 255, green: 0x53 / 255, blue: 0x50 / 255, alpha: 1)
                recordingDotView.layer.borderWidth = 3
                recordingDotView.layer.borderColor = UIColor(
                    red: 0x51 / 255, green: 0x51 / 255, blue: 0x51 / 255, alpha: 1).cgColor
                recordingDotView.layer.cornerRadius = 5.5
                addSubview(recordingDotView)
            }
            if reservation.recording_availability == "Partial" {
                let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                availabilityIconView.image = UIImage(
                    systemName: "exclamationmark.triangle.fill", withConfiguration: config)
                availabilityIconView.tintColor = AppPalette.warning
                addSubview(availabilityIconView)
            } else if reservation.recording_availability == "Unavailable" {
                let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                availabilityIconView.image = UIImage(
                    systemName: "xmark.circle.fill", withConfiguration: config)
                availabilityIconView.tintColor = Self.errorColor
                addSubview(availabilityIconView)
            }
        }

        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = UIColor.black.withAlphaComponent(titleAlpha)
        // 題名の [字] [再] などは、Web 版の番組表のセルと同じくピンク地の印に
        // 描き分ける (再生画面の情報欄と同じ部品を使う)。印の地色は Web 版
        // どおり、過去番組・通販で文字を薄くする対象にはしない。
        titleLabel.attributedText = decoratedProgramTitle(
            program.title, font: titleLabel.font, textColor: titleLabel.textColor)
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byCharWrapping
        addSubview(titleLabel)

        descriptionLabel.text = program.description
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = UIColor.black.withAlphaComponent(descriptionAlpha)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byCharWrapping
        addSubview(descriptionLabel)
    }

    /// 予約アイコンの色 (Web 版の優先順位どおり:
    /// 不可 → 一部のみ → 無効 → 通常は secondary)。
    private static func reservationIconColor(_ reservation: TimeTableProgramReservation) -> UIColor {
        if reservation.recording_availability == "Unavailable" { return errorColor }
        if reservation.recording_availability == "Partial" { return AppPalette.warning }
        if reservation.status == "Disabled" { return AppPalette.secondaryText }
        return AppPalette.secondary
    }

    /// 破線の枠の色 (Web 版の CSS の並び順で、後に書かれた状態が勝つ:
    /// 無効 → 不可 → 一部のみ → 予約済み・録画中)。
    private static func reservationBorderColor(_ reservation: TimeTableProgramReservation) -> UIColor {
        if reservation.status == "Disabled" { return AppPalette.secondaryText }
        if reservation.recording_availability == "Unavailable" { return errorColor }
        if reservation.recording_availability == "Partial" { return AppPalette.warning }
        return AppPalette.secondary
    }

    /// Web 版テーマの error (#FF5252)。
    private static var errorColor: UIColor {
        UIColor(red: 0xFF / 255, green: 0x52 / 255, blue: 0x52 / 255, alpha: 1)
    }

    override func layoutSubviews() {
        // 親 (RippleSurfaceView) 側で波紋の入れ物の置き場所も合わせる。
        super.layoutSubviews()
        // 帯と下端の線。
        if let highlightView = viewWithTag(1) {
            highlightView.frame = CGRect(x: 0, y: 0, width: 5, height: bounds.height)
        }
        if let bottomBorder = viewWithTag(2) {
            bottomBorder.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        }
        // 中身は帯の右に、上下2px・左右4pxの余白を取る。
        let contentX: CGFloat = 5 + 4
        let contentWidth = max(bounds.width - contentX - 4, 0)
        // 先頭の行 (開始の分＋予約の印)。
        minuteLabel.sizeToFit()
        let minuteWidth = minuteLabel.text == nil ? 0 : minuteLabel.bounds.width
        minuteLabel.frame = CGRect(x: contentX, y: 2, width: minuteWidth, height: 14)
        var iconX = contentX + minuteWidth + 4
        if program.reservation != nil {
            reservationIconView.frame = CGRect(x: iconX, y: 2, width: 14, height: 14)
            iconX += 14 + 2
            if program.reservation?.status == "Recording" {
                recordingDotView.frame = CGRect(x: iconX, y: 3.5, width: 11, height: 11)
                iconX += 11 + 2
            }
            if program.reservation?.recording_availability == "Partial"
                || program.reservation?.recording_availability == "Unavailable" {
                availabilityIconView.frame = CGRect(x: iconX, y: 3, width: 12, height: 12)
            }
        }
        // 題名 (折り返して全文を優先し、はみ出しは枠で切る)。
        let headerBottom: CGFloat = 2 + 14
        let titleSize = titleLabel.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let titleHeight = min(ceil(titleSize.height), max(bounds.height - headerBottom - 2, 0))
        titleLabel.frame = CGRect(
            x: contentX, y: headerBottom, width: contentWidth, height: titleHeight)
        // 説明 (題名の下に2px空けて、残りの高さいっぱい)。
        let descriptionY = headerBottom + titleHeight + 2
        descriptionLabel.frame = CGRect(
            x: contentX, y: descriptionY, width: contentWidth,
            height: max(bounds.height - descriptionY - 2, 0))
        // 予約の枠 (ごく短い番組では枠自体が収まらないため付けない)。
        // 改造版 Web では、無効化された予約だけが破線で、それ以外
        // (予約済み・録画中・一部のみ・不可) は実線になる。実線にする
        // かどうかは、セルの塗りと同じ専用スイッチで決める。
        if let reservation = program.reservation, bounds.width > 5, bounds.height > 5 {
            let layer = borderLayer ?? CAShapeLayer()
            layer.path = UIBezierPath(rect: bounds.insetBy(dx: 1.9, dy: 1.9)).cgPath
            layer.strokeColor = Self.reservationBorderColor(reservation).cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 3.8
            let isSolid = SettingsStore.shared.timeTableReservationHighlightEnabled
                && reservation.status != "Disabled"
            layer.lineDashPattern = isSolid ? nil : [7, 5]
            if layer.superlayer == nil {
                self.layer.addSublayer(layer)
            }
            borderLayer = layer
        }
    }
}

/// 番組の枠へのタップに、その番組と局を持たせるための受け口。
final class ProgramCellTapGestureRecognizer: UITapGestureRecognizer {
    var program: TimeTableProgram?
    var channel: ChannelInfo?
}
