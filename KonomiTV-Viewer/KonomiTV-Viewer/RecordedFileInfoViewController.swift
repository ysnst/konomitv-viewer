import UIKit

/// 録画ファイル情報の画面。Web 版の同名ダイアログと同じ内容を出す。
/// 録画一覧・マイリスト・視聴履歴のカードの「⋮」ボタンのメニューから開く。
///
/// 表示する値は、録画一覧の応答に含まれる録画ファイルの情報
/// (Web 版が使っているのと同じ値)。値が無い項目は行ごと出さず、
/// 項目が1つも無い区分は区分ごと出さない。
final class RecordedFileInfoViewController: UIViewController {

    private let program: RecordedProgram

    init(program: RecordedProgram) {
        self.program = program
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 地の色は Web 版ダイアログのカードと同じ面の色。
        view.backgroundColor = AppPalette.panel

        // 見出し行 (Web 版ダイアログの題名行と同じ並び):
        // 絵＋「録画ファイル情報」、右端に閉じるボタン。
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        let titleIcon = UIImageView(image: UIImage(
            systemName: "doc.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        titleIcon.setContentHuggingPriority(.required, for: .horizontal)
        let titleLabel = UILabel()
        titleLabel.text = "録画ファイル情報"
        titleLabel.font = .scaledSystemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = AppPalette.text
        let spacer = UIView()
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
            for: .normal)
        closeButton.tintColor = AppPalette.text
        closeButton.accessibilityLabel = "閉じる"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        header.addArrangedSubview(titleIcon)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(closeButton)
        view.addSubview(header)

        // 本文は縦スクロール (ファイルパスが長いと行が伸びるため)。
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let content = UIStackView()
        content.axis = .vertical
        // 区分どうしの間は Web 版の区分見出しの上の余白 (mt-3) 相当。
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        for section in makeSections() {
            content.addArrangedSubview(makeSectionView(
                title: section.title, symbol: section.symbol, rows: section.rows))
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            content.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 表示する内容

    private typealias InfoSection = (title: String, symbol: String, rows: [(String, String)])

    /// 区分の一覧。値が取れた項目だけを入れ、空の区分は落とす。
    private func makeSections() -> [InfoSection] {
        let video = program.recorded_video
        var sections: [InfoSection] = []
        let fileRows = fileInfoRows()
        if !fileRows.isEmpty {
            sections.append(("ファイル情報", "film", fileRows))
        }
        let videoRows = videoInfoRows()
        if !videoRows.isEmpty {
            sections.append(("映像情報", "video.fill", videoRows))
        }
        if video.primary_audio_codec != nil || video.primary_audio_channel != nil {
            sections.append(("音声情報（主音声）", "speaker.wave.2.fill", audioInfoRows(
                codec: video.primary_audio_codec,
                channel: video.primary_audio_channel,
                samplingRate: video.primary_audio_sampling_rate)))
        }
        // 副音声の区分は、Web 版と同じく副音声のコーデックがあるときだけ出す。
        if let codec = video.secondary_audio_codec, !codec.isEmpty {
            sections.append(("音声情報（副音声）", "speaker.wave.2.fill", audioInfoRows(
                codec: codec,
                channel: video.secondary_audio_channel,
                samplingRate: video.secondary_audio_sampling_rate)))
        }
        return sections
    }

    private func fileInfoRows() -> [(String, String)] {
        let video = program.recorded_video
        var rows: [(String, String)] = []
        if let path = video.file_path, !path.isEmpty {
            rows.append(("ファイルパス", path))
        }
        if let size = video.file_size {
            rows.append(("ファイルサイズ", FileSizeFormat.text(bytes: size)))
        }
        // 録画期間は Web 版と同じく、録画の開始・終了が両方取れたときだけ出す。
        if let start = video.recordingStartDate, let end = video.recordingEndDate {
            let period = TimeFormat.recordingPeriodText(
                start: start, end: end, durationSeconds: video.duration)
            if !period.isEmpty {
                rows.append(("録画期間", period))
            }
        }
        if let modified = video.fileModifiedDate {
            rows.append(("最終更新日時", Self.modifiedDateText(modified)))
        }
        return rows
    }

    private func videoInfoRows() -> [(String, String)] {
        let video = program.recorded_video
        var rows: [(String, String)] = []
        if let codec = video.video_codec, !codec.isEmpty {
            if let profile = video.video_codec_profile, !profile.isEmpty {
                rows.append(("コーデック", "\(codec) (\(profile))"))
            } else {
                rows.append(("コーデック", codec))
            }
        }
        if let width = video.video_resolution_width,
           let height = video.video_resolution_height {
            rows.append(("解像度", "\(width)×\(height)"))
        }
        if let rate = video.video_frame_rate, rate.isFinite {
            rows.append(("フレームレート", "\(Self.frameRateText(rate)) fps"))
        }
        if let scan = video.video_scan_type, !scan.isEmpty {
            rows.append(("スキャン方式", scan))
        }
        return rows
    }

    private func audioInfoRows(
        codec: String?, channel: String?, samplingRate: Int?
    ) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let codec, !codec.isEmpty {
            rows.append(("コーデック", codec))
        }
        if let channel, !channel.isEmpty {
            rows.append(("チャンネル", channel))
        }
        // サンプリングレートは、Web 版と同じく取れないときは「不明」と出す。
        if let samplingRate, samplingRate > 0 {
            rows.append(("サンプリングレート", "\(Self.samplingRateText(samplingRate))kHz"))
        } else {
            rows.append(("サンプリングレート", "不明"))
        }
        return rows
    }

    /// 最終更新日時の表記 (Web 版と同じ「2026/11/25 (火) 19:00:00」の形。
    /// 設定が入っていれば 28 時間表記への置き換えも Web 版と同じ)。
    private static func modifiedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd (E) HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        return TimeFormat.apply28HourClock(formatter.string(from: date))
    }

    /// フレームレートの表記。整数なら整数のまま、小数ならそのまま出す
    /// (Web 版の数値の出し方と同じ)。
    private static func frameRateText(_ rate: Double) -> String {
        if rate == rate.rounded(), abs(rate) < 100_000 {
            return String(Int(rate))
        }
        return String(rate)
    }

    /// サンプリングレートの kHz 表記 (48000 → "48"、44100 → "44.1")。
    private static func samplingRateText(_ rate: Int) -> String {
        let khz = Double(rate) / 1000
        if khz == khz.rounded() {
            return String(Int(khz))
        }
        return String(khz)
    }

    // MARK: - 部品の組み立て

    /// 区分 (見出し＋項目の並び)。
    private func makeSectionView(
        title: String, symbol: String, rows: [(String, String)]
    ) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        // アイコンは大きさを固定し、縦横比を保って出す。横の並びの中で
        // 余った幅をアイコンが吸って引き伸ばされないようにする
        // (他の画面の見出しのアイコンと同じく、幅と高さを固定する)。
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .scaledSystemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = AppPalette.text
        header.addArrangedSubview(icon)
        header.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(header)
        for (label, value) in rows {
            stack.addArrangedSubview(makeRow(label: label, value: value))
        }
        return stack
    }

    /// 項目の行 (Web 版と同じく、左に項目名の欄、右に値)。
    private func makeRow(label: String, value: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        let labelView = UILabel()
        labelView.text = label
        labelView.font = .scaledSystemFont(ofSize: 13)
        labelView.textColor = AppPalette.metaText
        labelView.numberOfLines = 1
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 126).isActive = true
        let valueView = UILabel()
        valueView.text = value
        valueView.font = .scaledSystemFont(ofSize: 13)
        valueView.textColor = AppPalette.text
        valueView.numberOfLines = 0
        row.addArrangedSubview(labelView)
        row.addArrangedSubview(valueView)
        return row
    }
}

extension UIViewController {
    /// 録画ファイル情報の画面を開く (カードの「⋮」ボタンのメニューから使う)。
    func presentRecordedFileInfo(program: RecordedProgram) {
        present(RecordedFileInfoViewController(program: program), animated: true)
    }
}
