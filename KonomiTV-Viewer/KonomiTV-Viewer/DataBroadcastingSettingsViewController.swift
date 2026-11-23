import UIKit

/// 「データ放送」の設定画面。Web 版の設定 → データ放送
/// (DataBroadcasting.vue) の項目をそのまま写したもの: データ放送機能を
/// 利用するか、データ放送からのインターネットアクセス (双方向) を
/// 有効にするか、お住まいの郵便番号・都道府県、保存データのリセット。
///
/// 値はいずれも Web 版でもデバイス間同期の対象外のため、端末保存
/// (SettingsStore) に置く。郵便番号と都道府県は、Web 版ではデータ放送の
/// 保存データへ直接書いているが、アプリでは設定画面を開いた時点で
/// データ放送の画面が存在しないため、端末側に値を持ち、データ放送を
/// 始めるときに保存データへ流し込む (流し込みはつなぎ側)。
/// 保存データのリセットは、アプリ側に控えた保存データと、郵便番号・
/// 都道府県の値を空に戻す。画面側の保存領域は、次にデータ放送を
/// 始めるときに控えと一致させるため、その時点で消える。
final class DataBroadcastingSettingsViewController: SettingsDetailViewController {
    private let enabledSwitch = WebToggle()
    private let internetSwitch = WebToggle()
    private let zipField = UITextField()
    private let prefectureButton = RippleButton()
    private let resetButton = RippleButton()

    /// 都道府県の選択肢 (Web 版 DataBroadcasting.vue と同じ並び・同じ値)。
    /// 値は「番号-0b地域コード」の形で、保存データへの流し込み時に
    /// つなぎ側で Web 版と同じ符号化に直される。先頭の未設定は空で表す。
    static let prefectureOptions: [(title: String, value: String)] = [
        ("未設定", ""),
        ("西北海道", "2-0b000101101011"),
        ("東北海道", "1-0b000101101011"),
        ("青森県", "3-0b010001100111"),
        ("岩手県", "4-0b010111010100"),
        ("宮城県", "5-0b011101011000"),
        ("秋田県", "6-0b101011000110"),
        ("山形県", "7-0b111001001100"),
        ("福島県", "8-0b000110101110"),
        ("茨城県", "9-0b110001101001"),
        ("栃木県", "10-0b111000111000"),
        ("群馬県", "11-0b100110001011"),
        ("埼玉県", "12-0b011001001011"),
        ("千葉県", "13-0b000111000111"),
        ("東京都 (島部を除く)", "14-0b101010101100"),
        ("東京都島部 (伊豆・小笠原諸島)", "49-0b101010101100"),
        ("神奈川県", "15-0b010101101100"),
        ("新潟県", "16-0b010011001110"),
        ("富山県", "17-0b010100111001"),
        ("石川県", "18-0b011010100110"),
        ("福井県", "19-0b100100101101"),
        ("山梨県", "20-0b110101001010"),
        ("長野県", "21-0b100111010010"),
        ("岐阜県", "22-0b101001100101"),
        ("静岡県", "23-0b101001011010"),
        ("愛知県", "24-0b100101100110"),
        ("三重県", "25-0b001011011100"),
        ("滋賀県", "26-0b110011100100"),
        ("京都府", "27-0b010110011010"),
        ("大阪府", "28-0b110010110010"),
        ("兵庫県", "29-0b011001110100"),
        ("奈良県", "30-0b101010010011"),
        ("和歌山県", "31-0b001110010110"),
        ("鳥取県", "32-0b110100100011"),
        ("島根県", "33-0b001100011011"),
        ("岡山県", "34-0b001010110101"),
        ("広島県", "35-0b101100110001"),
        ("山口県", "36-0b101110011000"),
        ("徳島県", "37-0b111001100010"),
        ("香川県", "38-0b100110110100"),
        ("愛媛県", "39-0b000110011101"),
        ("高知県", "40-0b001011100011"),
        ("福岡県", "41-0b011000101101"),
        ("佐賀県", "42-0b100101011001"),
        ("長崎県", "43-0b101000101011"),
        ("熊本県", "44-0b100010100111"),
        ("大分県", "45-0b110010001101"),
        ("宮崎県", "46-0b110100011100"),
        ("鹿児島県 (南西諸島を除く)", "47-0b110101000101"),
        ("鹿児島県島部 (南西諸島の鹿児島県域)", "50-0b110101000101"),
        ("沖縄県", "48-0b001101110010"),
    ]

    init() {
        super.init(headingTitle: "データ放送")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        reloadValues()
    }

    private func buildItems() {
        enabledSwitch.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)
        internetSwitch.addTarget(self, action: #selector(internetChanged), for: .valueChanged)

        // 郵便番号の入力欄 (Web 版の outlined の欄と同じ見た目)。
        // 入力し終えた時点で形を整えて保存する。
        styleTextField(zipField, placeholder: "郵便番号")
        zipField.keyboardType = .numberPad
        zipField.addTarget(self, action: #selector(zipEditingEnded), for: .editingDidEnd)

        styleSelectButton(prefectureButton)

        // リセットボタンは Web 版と同じく赤地 (bg-error)。
        resetButton.setTitle("保存データをリセット", for: .normal)
        resetButton.backgroundColor = AppPalette.error
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.titleLabel?.font = .scaledSystemFont(ofSize: 15.5)
        resetButton.layer.cornerRadius = 4
        resetButton.heightAnchor.constraint(equalToConstant: 45).isActive = true
        resetButton.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)

        let enabledField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("データ放送画面自体のオン/オフは、視聴画面でリモコンを表示した上で、リモコンの d ボタンから切り替えられます。"),
            makeSwitchRow(
                text: "データ放送機能をオンにすると、視聴時の負荷が若干高くなります。データ放送を利用しない場合や、性能の低いデバイスで動作が重い場合は、オフに設定してみてください。",
                toggle: enabledSwitch),
        ])
        enabledField.axis = .vertical
        enabledField.spacing = 14

        let internetField = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("オンにすると、データ放送機能を利用する際に、データ放送からインターネットにアクセスできるようになります。たとえば紅白歌合戦の視聴者投票をはじめとした双方向番組に参加したり、ネット接続時限定のミニゲームが遊べるようになります。"),
            makeSwitchRow(
                text: "その一方で、データ放送からのインターネットアクセスが有効な場合、あなたの視聴データがテレビ局に送信されることがあります。大半のチャンネルでは個別に視聴データの送信を無効化できますが、依然プライバシー上の問題が残ります。通常はオフにしておき、双方向コンテンツを使うときだけオンにすることをおすすめします。",
                toggle: internetSwitch),
        ])
        internetField.axis = .vertical
        internetField.spacing = 14

        let zipGroup = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("ここで設定した郵便番号をもとに、データ放送の地域情報（ニュース・天気予報など）が表示されます。設定しない場合、データ放送の一部のコンテンツが利用できないことがあります。"),
            zipField,
        ])
        zipGroup.axis = .vertical
        zipGroup.spacing = 14

        let prefectureGroup = UIStackView(arrangedSubviews: [
            makeDescriptionLabel("ここで設定した都道府県をもとに、データ放送の地域情報（ニュース・天気予報など）が表示されます。設定しない場合、データ放送の一部のコンテンツが利用できないことがあります。"),
            prefectureButton,
        ])
        prefectureGroup.axis = .vertical
        prefectureGroup.spacing = 14

        // リセットの項目は、見出しを Web 版と同じく注意の色にする。
        let resetHeading = makeItemHeading("データ放送の保存データをリセット")
        resetHeading.textColor = AppPalette.error
        let resetField = UIStackView(arrangedSubviews: [
            resetHeading,
            makeSpacer(14),
            makeDescriptionLabel("このデバイスに保存されているデータ放送の保存データを、初期状態にリセット (消去) できます。保存データには、データ放送内のミニゲームの得点、プレゼント企画のスタンプ個数、設定などが含まれます。保存データをリセットすると、元に戻すことはできません。十分ご注意ください。"),
            resetButton,
        ])
        resetField.axis = .vertical
        resetField.spacing = 14
        resetField.setCustomSpacing(14, after: resetHeading)

        for view in [
            itemGroup(title: "テレビをみるときにデータ放送機能を利用する", field: enabledField, syncDisabled: true),
            itemGroup(title: "データ放送からのインターネットアクセスを有効にする", field: internetField, syncDisabled: true),
            makeDivider(),
            itemGroup(title: "お住まいの郵便番号", field: zipGroup, syncDisabled: true),
            itemGroup(title: "お住まいの都道府県", field: prefectureGroup, syncDisabled: true),
            resetField,
        ] as [UIView] {
            contentStack.addArrangedSubview(view)
        }
    }

    // MARK: - 値の読み書き (変更はその場で保存する)

    private func reloadValues() {
        let store = SettingsStore.shared
        enabledSwitch.isOn = store.dataBroadcastingEnabled
        internetSwitch.isOn = store.dataBroadcastingInternetEnabled
        zipField.text = store.dataBroadcastingZipCode
        updatePrefectureButton(selected: store.dataBroadcastingPrefecture)
    }

    private func updatePrefectureButton(selected: String) {
        let title = Self.prefectureOptions.first { $0.value == selected }?.title ?? "未設定"
        prefectureButton.setTitle(title, for: .normal)
        prefectureButton.menu = UIMenu(children: Self.prefectureOptions.map { option in
            UIAction(title: option.title, state: option.value == selected ? .on : .off) { [weak self] _ in
                SettingsStore.shared.dataBroadcastingPrefecture = option.value
                self?.updatePrefectureButton(selected: option.value)
            }
        })
    }

    @objc private func enabledChanged() {
        SettingsStore.shared.dataBroadcastingEnabled = enabledSwitch.isOn
    }

    @objc private func internetChanged() {
        SettingsStore.shared.dataBroadcastingInternetEnabled = internetSwitch.isOn
    }

    /// 郵便番号の入力が終わった時点で、形を整えて保存する。
    /// 空なら未設定に戻し、形が違う場合は Web 版と同じ文面で知らせて
    /// 保存済みの値に戻す。
    @objc private func zipEditingEnded() {
        let raw = (zipField.text ?? "").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty {
            SettingsStore.shared.dataBroadcastingZipCode = ""
            zipField.text = ""
            return
        }
        // ハイフンなしの7桁は、3桁目と4桁目の間にハイフンを入れる。
        var candidate = raw
        if raw.count == 7, raw.allSatisfy({ $0.isNumber }) {
            candidate = String(raw.prefix(3)) + "-" + String(raw.suffix(4))
        }
        let parts = candidate.split(separator: "-")
        let isValid = parts.count == 2
            && parts[0].count == 3 && parts[1].count == 4
            && parts.allSatisfy { part in part.allSatisfy { $0.isNumber } }
        guard isValid else {
            zipField.text = SettingsStore.shared.dataBroadcastingZipCode
            let alert = UIAlertController(
                title: "郵便番号",
                message: "郵便番号は「000-0000」の形式で入力してください。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        SettingsStore.shared.dataBroadcastingZipCode = candidate
        zipField.text = candidate
    }

    /// 保存データのリセット。元に戻せないため、実行前に確認を出す。
    @objc private func resetPressed() {
        // 入力中の郵便番号があれば、先に確定させてから確認を出す
        // (確定できない値は reloadValues で保存済みの値に戻る)。
        zipField.resignFirstResponder()
        let alert = UIAlertController(
            title: "保存データをリセット",
            message: "データ放送の保存データを初期状態にリセットします。保存データをリセットすると、元に戻すことはできません。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "リセット", style: .destructive) { [weak self] _ in
            self?.performReset()
        })
        present(alert, animated: true)
    }

    private func performReset() {
        let store = SettingsStore.shared
        // アプリ側の控えを空にする (次にデータ放送を始めるときに、
        // 画面側の保存領域も控えと一致させるため、その時点で消える)。
        // 郵便番号と都道府県も Web 版のリセットと同じく未設定に戻す。
        store.dataBroadcastingNvram = [:]
        store.dataBroadcastingZipCode = ""
        store.dataBroadcastingPrefecture = ""
        reloadValues()
        let done = UIAlertController(
            title: nil,
            message: "データ放送の保存データをリセットしました。",
            preferredStyle: .alert)
        done.addAction(UIAlertAction(title: "OK", style: .default))
        present(done, animated: true)
    }
}
