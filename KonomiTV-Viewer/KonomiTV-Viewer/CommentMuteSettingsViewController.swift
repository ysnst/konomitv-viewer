import UIKit

/// コメントのミュート設定の画面。Web 版のミュート設定
/// (CommentMuteSettings.vue) のうち、録画の過去ログコメントの表示に
/// そのまま効く項目を写したもの: 文字サイズ・固定・色付き・同じ文字の
/// 連続のミュート、キーワードのミュート (一覧の追加・削除と照合の
/// 正規化)、ニコニコユーザー ID のミュート (一覧の追加・削除)。
///
/// 露骨な表現・差別的な表現のパターンによるミュートは、Web 版が持つ
/// 大きなパターンの表に依存するため、アプリではまだ入れていない。
/// 値はいずれも利用者設定と共通で、読み書きは SyncedSettingsStore が
/// 担う。変更はその場で保存され、次に録画再生を始めるときから効く。
final class CommentMuteSettingsViewController: SettingsDetailViewController {
    private let bigSizeSwitch = WebToggle()
    private let fixedSwitch = WebToggle()
    private let coloredSwitch = WebToggle()
    private let consecutiveSwitch = WebToggle()
    private let normalizeSwitch = WebToggle()

    private let keywordField = UITextField()
    private let keywordAddButton = RippleButton()
    private let keywordListStack = UIStackView()
    private let userIDField = UITextField()
    private let userIDAddButton = RippleButton()
    private let userIDListStack = UIStackView()

    init() {
        super.init(headingTitle: "コメントのミュート設定")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
        // 入力欄の外側をタップしたらキーボードを閉じる。
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func buildItems() {
        bigSizeSwitch.addTarget(self, action: #selector(bigSizeChanged), for: .valueChanged)
        fixedSwitch.addTarget(self, action: #selector(fixedChanged), for: .valueChanged)
        coloredSwitch.addTarget(self, action: #selector(coloredChanged), for: .valueChanged)
        consecutiveSwitch.addTarget(self, action: #selector(consecutiveChanged), for: .valueChanged)
        normalizeSwitch.addTarget(self, action: #selector(normalizeChanged), for: .valueChanged)

        keywordListStack.axis = .vertical
        keywordListStack.spacing = 6
        userIDListStack.axis = .vertical
        userIDListStack.spacing = 6

        let keywordField2 = makeAddRow(
            field: keywordField, placeholder: "キーワード",
            addButton: keywordAddButton, action: #selector(addKeyword))
        let keywordGroup = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("入力したキーワードを含むコメントをミュートします (部分一致)。Web 版で前方一致・後方一致・完全一致・正規表現として登録されたキーワードも、ここに表示され、そのまま効きます。"),
            keywordField2,
            keywordListStack,
        ])
        keywordGroup.axis = .vertical
        keywordGroup.spacing = 14

        let userIDRow = makeAddRow(
            field: userIDField, placeholder: "ニコニコユーザー ID",
            addButton: userIDAddButton, action: #selector(addUserID))
        let userIDGroup = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("入力したユーザー ID のコメントをミュートします。Web 版で登録した ID もここに表示され、そのまま効きます。"),
            userIDRow,
            userIDListStack,
        ])
        userIDGroup.axis = .vertical
        userIDGroup.spacing = 14

        for view in [
            makeDescriptionLabel("デフォルトでは、文字サイズが大きいコメントのミュートがオンになっています。これらのコメントも表示したい方は、適宜オフに設定してください。"),
            itemGroup(title: "文字サイズが大きいコメントをミュートする", field: makeSwitchRow(
                text: "文字サイズを大きくして投稿されたコメントを表示しません。",
                toggle: bigSizeSwitch)),
            itemGroup(title: "映像の上下に固定表示されるコメントをミュートする", field: makeSwitchRow(
                text: "画面の上端・下端に固定して表示されるコメントを表示しません。",
                toggle: fixedSwitch)),
            itemGroup(title: "色付きのコメントをミュートする", field: makeSwitchRow(
                text: "白以外の色で投稿されたコメントを表示しません。",
                toggle: coloredSwitch)),
            itemGroup(title: "同じ文字が連続しているコメントをミュートする", field: makeSwitchRow(
                text: "同じ文字が8文字以上連続しているコメントを表示しません。",
                toggle: consecutiveSwitch)),
            makeDivider(),
            itemGroup(title: "ミュートするキーワード", field: keywordGroup),
            itemGroup(title: "キーワード内の英数字・記号を、大文字小文字や全角半角の違いを無視して判定する", field: makeSwitchRow(
                text: "オンにすると、キーワードとコメントを比べるときに、英数字・記号の大文字小文字や全角半角の違いを無視します (正規表現のキーワードは対象外)。",
                toggle: normalizeSwitch)),
            makeDivider(),
            itemGroup(title: "ミュートするニコニコユーザー ID", field: userIDGroup),
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    /// 入力欄と追加ボタンの横並び。
    private func makeAddRow(field: UITextField, placeholder: String,
                            addButton: RippleButton, action: Selector) -> UIStackView {
        styleTextField(field, placeholder: placeholder)
        field.returnKeyType = .done
        field.delegate = self
        addButton.setTitle("追加", for: .normal)
        addButton.addTarget(self, action: action, for: .touchUpInside)
        styleActionButton(addButton)
        addButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let row = UIStackView(arrangedSubviews: [field, addButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let settings = SyncedSettingsStore.shared.current
        bigSizeSwitch.isOn = settings.muteBigSizeComments
        fixedSwitch.isOn = settings.muteFixedComments
        coloredSwitch.isOn = settings.muteColoredComments
        consecutiveSwitch.isOn = settings.muteConsecutiveSameCharactersComments
        normalizeSwitch.isOn = settings.muteCommentKeywordsNormalize
        rebuildKeywordList(settings)
        rebuildUserIDList(settings)
    }

    private func rebuildKeywordList(_ settings: SyncedClientSettings) {
        for view in keywordListStack.arrangedSubviews {
            keywordListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if settings.mutedCommentKeywords.isEmpty {
            keywordListStack.addArrangedSubview(makeDescriptionLabel("登録されているキーワードはありません。"))
            return
        }
        for (index, keyword) in settings.mutedCommentKeywords.enumerated() {
            keywordListStack.addArrangedSubview(makeListRow(
                text: keyword.pattern, subText: keyword.matchTitle,
                deleteAction: #selector(deleteKeyword(_:)), index: index))
        }
    }

    private func rebuildUserIDList(_ settings: SyncedClientSettings) {
        for view in userIDListStack.arrangedSubviews {
            userIDListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if settings.mutedNiconicoUserIDs.isEmpty {
            userIDListStack.addArrangedSubview(makeDescriptionLabel("登録されているユーザー ID はありません。"))
            return
        }
        for (index, userID) in settings.mutedNiconicoUserIDs.enumerated() {
            userIDListStack.addArrangedSubview(makeListRow(
                text: userID, subText: nil,
                deleteAction: #selector(deleteUserID(_:)), index: index))
        }
    }

    /// 一覧の1行分 (登録済みの値 + 照合の種類 + 削除ボタン)。
    private func makeListRow(text: String, subText: String?,
                             deleteAction: Selector, index: Int) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = AppPalette.text
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var views: [UIView] = [label]
        if let subText {
            let sub = UILabel()
            sub.text = subText
            sub.font = .systemFont(ofSize: 12)
            sub.textColor = AppPalette.metaText
            sub.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(sub)
        }
        let deleteButton = RippleButton()
        deleteButton.setTitle("削除", for: .normal)
        deleteButton.setTitleColor(AppPalette.text, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 14)
        deleteButton.backgroundColor = AppPalette.pressed
        deleteButton.layer.cornerRadius = 4
        deleteButton.tag = index
        deleteButton.addTarget(self, action: deleteAction, for: .touchUpInside)
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)
        deleteButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        views.append(deleteButton)
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.backgroundColor = AppPalette.panel
        row.layer.cornerRadius = 6
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return row
    }

    @objc private func bigSizeChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.muteBigSizeComments = bigSizeSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func fixedChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.muteFixedComments = fixedSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func coloredChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.muteColoredComments = coloredSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func consecutiveChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.muteConsecutiveSameCharactersComments = consecutiveSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func normalizeChanged() {
        var settings = SyncedSettingsStore.shared.current
        settings.muteCommentKeywordsNormalize = normalizeSwitch.isOn
        SyncedSettingsStore.shared.update(settings)
    }

    @objc private func addKeyword() {
        let pattern = (keywordField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        var settings = SyncedSettingsStore.shared.current
        guard !settings.mutedCommentKeywords.contains(where: {
            $0.match == "partial" && $0.pattern == pattern
        }) else { return }
        settings.mutedCommentKeywords.append(
            MutedCommentKeyword(match: "partial", pattern: pattern))
        SyncedSettingsStore.shared.update(settings)
        keywordField.text = ""
        reloadValues()
    }

    @objc private func deleteKeyword(_ sender: UIButton) {
        var settings = SyncedSettingsStore.shared.current
        guard settings.mutedCommentKeywords.indices.contains(sender.tag) else { return }
        settings.mutedCommentKeywords.remove(at: sender.tag)
        SyncedSettingsStore.shared.update(settings)
        reloadValues()
    }

    @objc private func addUserID() {
        let userID = (userIDField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { return }
        var settings = SyncedSettingsStore.shared.current
        guard !settings.mutedNiconicoUserIDs.contains(userID) else { return }
        settings.mutedNiconicoUserIDs.append(userID)
        SyncedSettingsStore.shared.update(settings)
        userIDField.text = ""
        reloadValues()
    }

    @objc private func deleteUserID(_ sender: UIButton) {
        var settings = SyncedSettingsStore.shared.current
        guard settings.mutedNiconicoUserIDs.indices.contains(sender.tag) else { return }
        settings.mutedNiconicoUserIDs.remove(at: sender.tag)
        SyncedSettingsStore.shared.update(settings)
        reloadValues()
    }
}

extension CommentMuteSettingsViewController: UITextFieldDelegate {
    /// リターンキーでキーボードを閉じる。
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
}
