import UIKit

/// 「今日のハイライト」の画面 (Web 版 HighlightsDialog の写し。拡張版だけ)。
///
/// 今日の録画から実況コメントの盛り上がり区間を抽出して一覧で出し、
/// 「ハイライトを再生」で複数の録画をまたいで続けて再生する
/// (再生の受け渡しは HighlightReelStore、再生画面側が順に進める)。
/// 抽出の計算は Web 版と寸分違わない CommentHighlights の部品を使う。
final class HighlightsViewController: UIViewController {
    /// 再生が始まるときの知らせ先 (最初の区間の録画)。
    /// 呼び出し側 (録画一覧) が再生画面を開く。
    var onStartPlayback: ((RecordedProgram) -> Void)?

    private let summaryLabel = UILabel()
    private let listStack = UIStackView()
    private let playButton = RippleButton()

    /// 抽出した区間と、区間の録画 (再生画面を開くときに使う)。
    private var items: [HighlightReelStore.Item] = []
    private var programsByID: [Int: RecordedProgram] = [:]
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        computeHighlights()
    }

    // MARK: - 画面の組み立て

    private func buildLayout() {
        // 先頭の帯 (Web 版ダイアログの題名行: 絵 24px + 題名太字、右端に閉じるボタン)。
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let iconView = UIImageView(image: UIImage(
            systemName: "flame.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "今日のハイライト"
        titleLabel.font = .scaledSystemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = AppPalette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        let closeButton = RippleButton()
        closeButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
            for: .normal)
        closeButton.tintColor = AppPalette.text
        closeButton.accessibilityLabel = "閉じる"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(closeButton)

        // 概要の文 (Web 版は 12.5px・不透明度 0.8)。
        summaryLabel.font = .scaledSystemFont(ofSize: 12.5)
        summaryLabel.textColor = AppPalette.text.withAlphaComponent(0.8)
        summaryLabel.numberOfLines = 0
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryLabel)

        // 区間の一覧。行は Web 版どおり、開始位置 (ピンクの太字)・
        // 番組の題名・コメントの件数の並び。
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        listStack.axis = .vertical
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(listStack)

        // 再生のボタンは Web 版と同じく右下に置く。区間が無い間と
        // 抽出中は押せない。
        playButton.setTitle("ハイライトを再生", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.titleLabel?.font = .scaledSystemFont(ofSize: 14, weight: .semibold)
        playButton.backgroundColor = AppPalette.accent
        playButton.layer.cornerRadius = 4
        playButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.isEnabled = false
        playButton.alpha = 0.5
        playButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 60),
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            summaryLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            listStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            listStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -20),
            playButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - ハイライトの抽出

    /// 今日の録画 (放送開始が今日のもの) から盛り上がり区間を抽出する
    /// (Web 版 computeHighlights と同じ手順)。
    private func computeHighlights() {
        isLoading = true
        summaryLabel.text = "今日の録画から盛り上がり区間を探しています…"
        Task { [weak self] in
            guard let self else { return }
            let todayStart = Calendar.current.startOfDay(for: Date())
            // 今日の録画を新しい順に集める (今日より古い番組が出たら打ち切る)。
            // 取得に失敗したかどうかは控えておく (失敗を「盛り上がりが
            // 無かった」と取り違えないよう、表示を分けるため)。
            var todaysPrograms: [RecordedProgram] = []
            var listLoadFailed = false
            var page = 1
            var total = Int.max
            while todaysPrograms.count < total, page <= 10 {
                guard let response = try? await APIClient.shared.fetchVideos(page: page, order: "desc") else {
                    listLoadFailed = true
                    break
                }
                total = response.total
                var reachedOlder = false
                for program in response.recorded_programs {
                    guard let start = program.startDate else { continue }
                    if start < todayStart {
                        reachedOlder = true
                        break
                    }
                    if program.recorded_video.status == "Recorded" {
                        todaysPrograms.append(program)
                    }
                }
                if reachedOlder { break }
                page += 1
            }
            // 古い順に、各録画から盛り上がりの強い区間を最大3つまで拾う
            // (コメント取得の負荷を抑えるため対象は12件まで)。
            var found: [HighlightReelStore.Item] = []
            var programs: [Int: RecordedProgram] = [:]
            var commentFetchAttempts = 0
            var commentFetchFailures = 0
            for program in todaysPrograms.reversed().prefix(12) {
                programs[program.id] = program
                commentFetchAttempts += 1
                // 取れなかった (通信の失敗) 場合だけ失敗として数える。
                // 取れたが「コメントなし」の応答だった録画は、失敗では
                // なく対象外として飛ばす。
                guard let comments = await APIClient.shared.fetchJikkyoComments(videoID: program.id) else {
                    commentFetchFailures += 1
                    continue
                }
                guard comments.is_success else { continue }
                let density = computeCommentDensity(
                    positions: comments.comments.map { $0.time },
                    duration: program.recorded_video.duration)
                guard density.total >= minCommentsForHighlights else { continue }
                let segments = extractHighlightSegments(density: density)
                let topSegments = segments
                    .sorted { $0.peakDensity > $1.peakDensity }
                    .prefix(3)
                    .sorted { $0.start < $1.start }
                for segment in topSegments {
                    found.append(HighlightReelStore.Item(
                        videoID: program.id,
                        title: program.title,
                        start: max(0, segment.start - 3),
                        end: segment.end,
                        commentCount: segment.commentCount))
                }
            }
            self.items = found
            self.programsByID = programs
            self.isLoading = false
            // 失敗と「盛り上がりが無かった」を区別する。一覧が取れ
            // なかった場合と、対象の録画すべてのコメント取得に失敗
            // した場合は、失敗と分かる文にする。
            let loadFailed = listLoadFailed
                || (commentFetchAttempts > 0 && commentFetchFailures == commentFetchAttempts)
            self.applyResults(loadFailed: loadFailed)
        }
    }

    /// 抽出結果を画面へ反映する。
    private func applyResults(loadFailed: Bool) {
        for arranged in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        if items.isEmpty {
            summaryLabel.text = loadFailed
                ? "読み込めませんでした。\n接続先とネットワークを確認してください。"
                : "今日の録画に、コメントの盛り上がり区間は見つかりませんでした"
        } else {
            let totalSeconds = items.reduce(0.0) { $0 + ($1.end - $1.start) }
            summaryLabel.text = "\(items.count) 区間・合計 \(Self.playbackTime(totalSeconds)) "
                + "(実況コメントの盛り上がりから自動抽出)"
            for item in items {
                listStack.addArrangedSubview(makeRow(item: item))
            }
        }
        playButton.isEnabled = !items.isEmpty
        playButton.alpha = items.isEmpty ? 0.5 : 1
    }

    /// 区間1件分の行 (開始位置・題名・件数)。
    private func makeRow(item: HighlightReelStore.Item) -> UIView {
        let row = UIView()
        let timeLabel = UILabel()
        timeLabel.text = Self.playbackTime(item.start)
        timeLabel.font = .scaledSystemFont(ofSize: 12.5, weight: .bold)
        timeLabel.textColor = AppPalette.accent
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .scaledSystemFont(ofSize: 13.5)
        titleLabel.textColor = AppPalette.text
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        let countLabel = UILabel()
        countLabel.text = "\(item.commentCount) 件"
        countLabel.font = .scaledSystemFont(ofSize: 12)
        countLabel.textColor = AppPalette.text.withAlphaComponent(0.75)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [timeLabel, titleLabel, countLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -7),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
        ])
        return row
    }

    /// 再生を始める。キューを作って画面を閉じ、呼び出し側に
    /// 最初の録画を知らせる。
    @objc private func playTapped() {
        guard let first = items.first, let program = programsByID[first.videoID] else { return }
        HighlightReelStore.shared.start(items: items)
        dismiss(animated: true) { [weak self] in
            self?.onStartPlayback?(program)
        }
    }

    /// 秒数を "m:ss" / "h:mm:ss" の形にする (Web 版 formatPlaybackTime と
    /// 同じく、秒は切り捨て)。
    private static func playbackTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
