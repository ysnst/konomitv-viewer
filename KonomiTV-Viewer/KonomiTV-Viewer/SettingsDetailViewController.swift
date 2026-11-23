import UIKit

extension UIView {
    /// このビューの中 (自分を含む) で、入力中 (ファーストレスポンダ) の
    /// 欄を探す。キーボードに隠れないよう寄せるときに使う。
    func firstResponderDescendant() -> UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let found = subview.firstResponderDescendant() { return found }
        }
        return nil
    }
}

extension UIViewController {
    /// 画面の左端からの横スワイプで前の画面へ戻る受け口を足す。
    /// 自前の見出し帯を使う設定まわりの画面では標準の戻る動きが
    /// 効かないため、端スワイプ専用の受け口を用意する
    /// (見出し帯の矢印ボタンの戻りと両立させる)。
    func installEdgeSwipeBack(action: Selector) {
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: action)
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

/// 設定の分類ごとの詳細画面の土台。
///
/// 見た目は Web 版の設定詳細画面 (views/Settings/Base.vue のスマホ縦) に
/// 合わせてある: 画面地はテーマの background、上部に高さ 60px・地が
/// background-lighten-1 の見出し帯 (左端は矢印だけの戻るボタン、
/// ページ名 22px)、項目は「見出し (16.5px) → 14px 空けて入力欄」の
/// 並び、項目どうしの間隔は 24px。
/// 分類ごとの画面は、この土台を受け継いで項目を足す。
class SettingsDetailViewController: UIViewController {
    /// 見出し帯に出すページ名。
    private let headingTitle: String
    /// 見出し帯の戻るボタン。本家に合わせて矢印だけ (文字は付けない)。
    private let backButton = RippleButton()
    /// 項目を積む縦並び。受け継いだ側が viewDidLoad で項目を足す。
    let contentStack = UIStackView()
    /// 土台のスクロール。キーボードへの追随で使うため保持する。
    private var scaffoldScrollView: UIScrollView?

    init(headingTitle: String) {
        self.headingTitle = headingTitle
        super.init(nibName: nil, bundle: nil)
        title = headingTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildScaffold()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Web 版のスマホ縦では、設定系のページは上部のヘッダー自体が出ない。
        // それに合わせ、この画面ではナビゲーションバーを隠し、
        // 代わりに自前の見出し帯を出す (他の設定画面と同じ)。
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 端からの横スワイプで戻る動きも生かしておく (見出し帯の
        // 矢印ボタンと両立させる)。
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        installKeyboardAvoidance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardAvoidance()
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    /// 見出し帯とスクロールの土台を組み立てる。
    private func buildScaffold() {
        let headingBar = UIView()
        headingBar.backgroundColor = AppPalette.panel
        headingBar.translatesAutoresizingMaskIntoConstraints = false
        headingBar.layer.shadowColor = UIColor.black.cgColor
        headingBar.layer.shadowOpacity = 0.12
        headingBar.layer.shadowOffset = CGSize(width: 0, height: 3)
        headingBar.layer.shadowRadius = 7
        let headingLabel = UILabel()
        headingLabel.text = headingTitle
        headingLabel.font = .scaledSystemFont(ofSize: 22, weight: .semibold)
        headingLabel.textColor = AppPalette.text
        backButton.setImage(
            UIImage(systemName: "chevron.left")?
                .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal),
            for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        // 矢印だけでも押しやすいよう、当たり判定は広めに取る。
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let headingStack = UIStackView(arrangedSubviews: [backButton, headingLabel])
        headingStack.axis = .horizontal
        headingStack.alignment = .center
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false
        headingBar.addSubview(headingStack)
        view.addSubview(headingBar)

        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(contentStack)
        view.addSubview(scroll)
        scaffoldScrollView = scroll
        NSLayoutConstraint.activate([
            headingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headingBar.heightAnchor.constraint(equalToConstant: 60),
            headingStack.leadingAnchor.constraint(equalTo: headingBar.leadingAnchor, constant: 8),
            headingStack.centerYAnchor.constraint(equalTo: headingBar.centerYAnchor),
            headingStack.trailingAnchor.constraint(lessThanOrEqualTo: headingBar.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: headingBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // 下端は画面の最下端ではなくセーフエリアの下端に留める。
            // 最下端まで伸ばすと、末尾が下部バーの裏に入り込み、
            // 中身が少しだけはみ出す画面ではスクロール量が足りず
            // 最後の項目に届かなくなる (マイページと同じ留め方)。
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        // 画面の左端からの横スワイプでも前の画面へ戻れるようにする。
        installEdgeSwipeBack(action: #selector(goBack))
    }

    // MARK: - キーボードへの追随

    /// キーボードの開閉への追随を始める。入力欄のある画面
    /// (アカウント、ミュート設定など) で編集中の欄がキーボードに
    /// 隠れないようにするため、土台側で面倒を見る。入力欄の無い
    /// 画面では、通知が来ても欄が見つからず何も起きない。
    private func installKeyboardAvoidance() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func removeKeyboardAvoidance() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let scrollView = scaffoldScrollView,
              let userInfo = notification.userInfo,
              let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }
        // キーボードの枠 (画面全体の座標) をこの画面の座標に直し、
        // スクロール範囲と重なる分だけ下に余白を足す。
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(scrollView.frame.maxY - keyboardFrame.minY, 0)
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            scrollView.contentInset.bottom = overlap
            scrollView.verticalScrollIndicatorInsets.bottom = overlap
        }
        // 編集中の欄が見える位置まで寄せる。欄の位置は中身の座標
        // (スクロール量を含む) に直してから渡す。
        if let field = scrollView.firstResponderDescendant() {
            var rect = field.convert(field.bounds, to: scrollView)
            rect.origin.x += scrollView.contentOffset.x
            rect.origin.y += scrollView.contentOffset.y
            scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -16), animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let scrollView = scaffoldScrollView else { return }
        let duration = (notification.userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            scrollView.contentInset.bottom = 0
            scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    // MARK: - 見た目の部品 (Web 版の設定画面の値)

    /// 項目の見出し (16.5px、テーマの text 色)。
    func makeItemHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .scaledSystemFont(ofSize: 16.5)
        label.textColor = AppPalette.text
        label.numberOfLines = 0
        return label
    }

    /// 説明文 (13.5px、text-darken-1、行の高さ 1.6 倍)。
    func makeDescriptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 13.5)
        label.textColor = AppPalette.metaText
        label.numberOfLines = 0
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 13.5 * 1.6
        style.maximumLineHeight = 13.5 * 1.6
        label.attributedText = NSAttributedString(
            string: text, attributes: [.paragraphStyle: style])
        return label
    }

    /// グループの区切り線 (2px、background-lighten-2)。
    func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AppPalette.pressed
        divider.heightAnchor.constraint(equalToConstant: 2).isActive = true
        return divider
    }

    /// 固定の高さの余白。
    func makeSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    /// 「デバイス間同期無効」の印の幅 (全項目で共通)。
    /// 表示の大きさに合わせて文字の幅も変わるため、固定値にせず
    /// その都度測り直す。
    private static var syncDisabledBadgeWidth: CGFloat {
        let font = UIFont.scaledSystemFont(ofSize: 11)
        let textWidth = ("デバイス間同期無効" as NSString)
            .size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 8
    }

    /// 「デバイス間同期無効」の印 (Web 版 Base.vue の作り: 地は
    /// background-lighten-2、文字 11px、角丸 4px、余白は上下 2px・
    /// 左右 4px、見出し行の右端に寄せて置く)。Web 版でデバイス間
    /// 同期の対象外になっている項目にだけ付ける。
    func makeSyncDisabledBadge() -> UIView {
        let label = UILabel()
        label.text = "デバイス間同期無効"
        label.font = .scaledSystemFont(ofSize: 11)
        label.textColor = AppPalette.text
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let badge = UIView()
        badge.backgroundColor = AppPalette.pressed
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.syncDisabledBadgeWidth),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -4),
        ])
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        return badge
    }

    /// 設定項目1つ分のまとまり (見出し → 14px 空けて入力欄)。
    /// syncDisabled が true の項目は、見出しの右端に Web 版と同じ
    /// 「デバイス間同期無効」の印を付ける。
    func itemGroup(title: String, field: UIView, syncDisabled: Bool = false) -> UIStackView {
        let heading = makeItemHeading(title)
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var headingViews: [UIView] = [heading]
        if syncDisabled {
            headingViews.append(makeSyncDisabledBadge())
        }
        let headingRow = UIStackView(arrangedSubviews: headingViews)
        headingRow.axis = .horizontal
        headingRow.alignment = .center
        headingRow.spacing = 8
        let stack = UIStackView(arrangedSubviews: [
            headingRow,
            makeSpacer(14),
            field,
        ])
        stack.axis = .vertical
        return stack
    }

    /// 説明文とスイッチを横に並べた行。文が残りの幅で折り返し、
    /// スイッチが右端に収まる組み方 (他の設定画面と同じ)。
    func makeSwitchRow(text: String, toggle: WebToggle) -> UIStackView {
        let label = makeDescriptionLabel(text)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    /// 選択ボタンに、設定画面の入力欄と同じ箱の見た目を付ける
    /// (地はページ地、枠線は background-lighten-3、角丸 4px、高さ 50px、
    /// 右端に下向きの矢印)。メニューは呼び出し側で付ける。
    func styleSelectButton(_ button: UIButton) {
        button.contentHorizontalAlignment = .leading
        button.showsMenuAsPrimaryAction = true
        button.backgroundColor = AppPalette.background
        button.layer.borderWidth = 1
        button.layer.borderColor = AppPalette.fieldBorder.cgColor
        button.layer.cornerRadius = 4
        button.setTitleColor(AppPalette.text, for: .normal)
        button.titleLabel?.font = .scaledSystemFont(ofSize: 16)
        // 右の余白は、右端に留める矢印の分 (12 + 12 + 8) を空ける。
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 32)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        addSelectChevron(to: button)
    }

    /// 選択ボタンの右端に、下向きの矢印を留める。
    /// ボタン標準の画像の並べ方 (semanticContentAttribute の
    /// forceRightToLeft) は、左寄せの指定と干渉して文字まで右寄せに
    /// なってしまう (実機確認)。番組表の種別ボタンと同じく、
    /// 画像を右端に留める形にする。
    func addSelectChevron(to button: UIButton) {
        let tag = 0x5E1EC7
        if button.viewWithTag(tag) != nil { return }
        let chevron = UIImageView(
            image: UIImage(systemName: "chevron.down")?
                .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal))
        chevron.tag = tag
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    /// Web 版の保存ボタンと同じ形 (高さ 45px、地は background-lighten-2、
    /// 文字 15.5px、角丸 4px) をボタンに付ける。
    func styleActionButton(_ button: UIButton) {
        button.backgroundColor = AppPalette.pressed
        button.setTitleColor(AppPalette.text, for: .normal)
        button.titleLabel?.font = .scaledSystemFont(ofSize: 15.5)
        button.layer.cornerRadius = 4
        button.heightAnchor.constraint(equalToConstant: 45).isActive = true
    }

    /// 入力欄に Web 版の入力欄 (outlined) と同じ見た目を付ける。
    func styleTextField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .none
        field.backgroundColor = AppPalette.background
        field.layer.borderWidth = 1
        field.layer.borderColor = AppPalette.fieldBorder.cgColor
        field.layer.cornerRadius = 4
        field.textColor = AppPalette.text
        field.font = .scaledSystemFont(ofSize: 16)
        field.tintColor = AppPalette.accent
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: AppPalette.secondaryText])
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
    }

    /// つまみの値を横に出すスライダーの行 (スライダー + 右に値の表示)。
    func makeSliderRow(slider: UISlider, valueLabel: UILabel) -> UIStackView {
        slider.minimumTrackTintColor = AppPalette.accent
        slider.maximumTrackTintColor = AppPalette.pressed
        slider.thumbTintColor = AppPalette.accent
        valueLabel.font = .scaledSystemFont(ofSize: 14)
        valueLabel.textColor = AppPalette.text
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let row = UIStackView(arrangedSubviews: [slider, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }
}
