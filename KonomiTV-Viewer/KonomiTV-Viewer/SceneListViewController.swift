import UIKit

/// 場面一覧の画面 (Web 版 ChapterListDialog の写し)。
///
/// 上から「しおり」「CM区間」「見どころ（コメントの盛り上がり）」の欄と、
/// 場面の画像 (シークバー用タイル画像の切り出し) の並びでできていて、
/// どれを選んでもその場面へ移動して画面を閉じる。
/// しおりはサーバーで世帯共有されるため、開くたびに取り直す。
/// 削除もこの画面から行う (Web 版と同じ)。
final class SceneListViewController: UIViewController {
    private let program: RecordedProgram
    /// 見どころ区間 (呼び出し側がコメントから計算済みのもの)。
    private let highlightSegments: [HighlightSegment]
    /// 場面が選ばれたときの知らせ先 (引数は再生位置 (秒))。
    var onSeek: ((Double) -> Void)?

    /// サーバーから取ったしおり (再生位置の昇順)。
    private var bookmarks: [VideoBookmark] = []
    /// しおりの取得の世代 (取得のたびに進める)。返ってきた結果は
    /// 最新の取得のものだけを反映する。遅れて届いた古い取得結果で、
    /// 削除したしおりが表示に戻らないようにするため。
    private var bookmarkFetchGeneration = 0
    /// 読み込んだタイル画像 (切り出しの材料)。寸法が合わなければ nil のまま。
    private var spriteCGImage: CGImage?
    /// 場面の並び (タイル番号と時刻)。タイル情報が無ければ空。
    private var chapters: [(tileIndex: Int, time: Double)] = []

    private let contentStack = UIStackView()

    init(program: RecordedProgram, highlightSegments: [HighlightSegment]) {
        self.program = program
        self.highlightSegments = highlightSegments
        // 場面の並びは Web 版と同じく、12場面程度になるようタイルを間引く。
        if let tile = program.recorded_video.thumbnail_info?.tile, tile.total_tiles > 0 {
            let step = max(1, Int((Double(tile.total_tiles) / 12).rounded()))
            var index = 0
            while index < tile.total_tiles {
                chapters.append((tileIndex: index, time: Double(index) * tile.interval_sec))
                index += step
            }
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        rebuildContent()
        loadBookmarks()
        loadSprite()
    }

    // MARK: - 画面の組み立て

    private func buildLayout() {
        // 先頭の帯 (Web 版ダイアログの題名行: 絵 24px + 題名太字、右端に閉じるボタン)。
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let iconView = UIImageView(image: UIImage(
            systemName: "photo.on.rectangle.angled",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
            .withTintColor(AppPalette.text, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "場面一覧"
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

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 4, left: 20, bottom: 24, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
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
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 中身の組み直し

    /// 欄の並びを組み直す (しおりの取得・削除と、タイル画像の到着で呼ぶ)。
    private func rebuildContent() {
        for arranged in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        // しおり
        if !bookmarks.isEmpty {
            contentStack.addArrangedSubview(makeSectionTitle("しおり"))
            for bookmark in bookmarks {
                contentStack.addArrangedSubview(makeBookmarkRow(bookmark))
            }
        }
        // CM区間
        let cmSections = program.cmSections
        if !cmSections.isEmpty {
            contentStack.addArrangedSubview(makeSectionTitle("CM区間"))
            for section in cmSections {
                let row = makeListRow(
                    symbol: "megaphone.fill",
                    iconColor: UIColor(red: 0x6C / 255, green: 0xB2 / 255, blue: 0xF5 / 255, alpha: 1),
                    timeText: "\(TimeFormat.hms(section.start_time)) 〜 \(TimeFormat.hms(section.end_time))",
                    subText: "\(TimeFormat.safeSeconds(section.end_time - section.start_time)) 秒")
                attachSeek(to: row, time: section.start_time)
                contentStack.addArrangedSubview(row)
            }
        }
        // 見どころ
        if !highlightSegments.isEmpty {
            contentStack.addArrangedSubview(makeSectionTitle("見どころ（コメントの盛り上がり）"))
            for segment in highlightSegments {
                let row = makeListRow(
                    symbol: "flame.fill",
                    iconColor: AppPalette.accent,
                    timeText: "\(TimeFormat.hms(segment.start)) 〜 \(TimeFormat.hms(segment.end))",
                    subText: "コメント \(segment.commentCount) 件")
                attachSeek(to: row, time: segment.start)
                contentStack.addArrangedSubview(row)
            }
        }
        // 場面の画像の並び
        if chapters.isEmpty {
            let label = UILabel()
            label.text = "場面サムネイルがまだ生成されていません"
            label.font = .scaledSystemFont(ofSize: 13.5)
            label.textColor = AppPalette.metaText
            label.textAlignment = .center
            let container = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            contentStack.addArrangedSubview(container)
        } else {
            contentStack.addArrangedSubview(makeChapterGrid())
        }
    }

    /// 欄の見出し (Web 版と同じ 13px 太字)。
    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .scaledSystemFont(ofSize: 13, weight: .bold)
        label.textColor = AppPalette.text.withAlphaComponent(0.85)
        // 見出しと下の行の間は Web 版で 8px。スタックの間隔 (20) との差し引きで、
        // 見出し自体の下に詰め物は入れず、行側の余白で調整する代わりに
        // 見出しはそのまま置く (間隔はやや広めになる)。
        return label
    }

    /// しおり・CM区間・見どころで共通の行 (絵 + 時刻 (太字) + 補足)。
    private func makeListRow(symbol: String, iconColor: UIColor, timeText: String, subText: String?) -> SeekRowView {
        let row = SeekRowView()
        let iconView = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15))?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        let timeLabel = UILabel()
        timeLabel.text = timeText
        timeLabel.font = .scaledSystemFont(ofSize: 13.5, weight: .bold)
        timeLabel.textColor = AppPalette.text
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        var arranged: [UIView] = [iconView, timeLabel]
        if let subText, !subText.isEmpty {
            let subLabel = UILabel()
            subLabel.text = subText
            subLabel.font = .scaledSystemFont(ofSize: 12)
            subLabel.textColor = AppPalette.metaText
            arranged.append(subLabel)
        }
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -10),
        ])
        return row
    }

    /// しおりの行 (右端に削除ボタン付き)。
    private func makeBookmarkRow(_ bookmark: VideoBookmark) -> SeekRowView {
        let row = makeListRow(
            symbol: "bookmark.fill",
            iconColor: UIColor(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255, alpha: 1),
            timeText: TimeFormat.hms(bookmark.position),
            subText: bookmark.label.isEmpty ? nil : bookmark.label)
        let deleteButton = RippleButton()
        deleteButton.setImage(UIImage(
            systemName: "trash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))?
            .withTintColor(AppPalette.metaText, renderingMode: .alwaysOriginal),
            for: .normal)
        deleteButton.accessibilityLabel = "しおりを削除"
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            deleteButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -2),
            deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        let bookmarkID = bookmark.id
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.deleteBookmark(id: bookmarkID)
        }, for: .touchUpInside)
        attachSeek(to: row, time: bookmark.position)
        return row
    }

    /// 行全体を押せるようにし、押されたらその場面へ移動して閉じる。
    /// 行の中のボタン (しおりの削除) の上のタッチは、移動ではなく
    /// ボタンの操作として扱う (受け口側で振り分ける)。
    private func attachSeek(to row: UIView, time: Double) {
        row.isUserInteractionEnabled = true
        if let seekRow = row as? SeekRowView {
            seekRow.seekTime = time
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        tap.delegate = self
        row.addGestureRecognizer(tap)
    }

    @objc private func rowTapped(_ recognizer: UITapGestureRecognizer) {
        guard let row = recognizer.view as? SeekRowView else { return }
        onSeek?(row.seekTime)
        dismiss(animated: true)
    }

    /// 場面の画像の並び (2列)。タイル画像が届くまでは黒い枠だけ出す。
    private func makeChapterGrid() -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14
        var rowStack: UIStackView?
        for (offset, chapter) in chapters.enumerated() {
            if offset % 2 == 0 {
                rowStack = UIStackView()
                rowStack?.axis = .horizontal
                rowStack?.spacing = 14
                rowStack?.distribution = .fillEqually
                if let rowStack {
                    grid.addArrangedSubview(rowStack)
                }
            }
            rowStack?.addArrangedSubview(makeChapterItem(chapter))
        }
        // 奇数個で終わった行は、右半分を空けて左寄せにする。
        if chapters.count % 2 == 1 {
            rowStack?.addArrangedSubview(UIView())
        }
        return grid
    }

    /// 場面1つ分 (画像 16:9 + 下に時刻)。
    private func makeChapterItem(_ chapter: (tileIndex: Int, time: Double)) -> UIView {
        let container = SeekRowView()
        let imageView = UIImageView()
        imageView.backgroundColor = .black
        imageView.layer.cornerRadius = 6
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleToFill
        imageView.image = chapterImage(tileIndex: chapter.tileIndex)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let timeLabel = UILabel()
        timeLabel.text = TimeFormat.hms(chapter.time)
        timeLabel.font = .scaledSystemFont(ofSize: 12.5)
        timeLabel.textColor = AppPalette.text.withAlphaComponent(0.85)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        container.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0 / 16.0),
            timeLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        attachSeek(to: container, time: chapter.time)
        return container
    }

    /// タイル画像から場面1枚を切り出す。材料が無ければ nil。
    private func chapterImage(tileIndex: Int) -> UIImage? {
        guard let sprite = spriteCGImage,
              let tile = program.recorded_video.thumbnail_info?.tile,
              tile.column_count > 0, tile.tile_width > 0, tile.tile_height > 0
        else { return nil }
        let column = tileIndex % tile.column_count
        let row = tileIndex / tile.column_count
        let rect = CGRect(
            x: column * tile.tile_width, y: row * tile.tile_height,
            width: tile.tile_width, height: tile.tile_height)
        guard let cropped = sprite.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    // MARK: - サーバーとのやり取り

    /// しおりを取り直す (開くたびに最新にする。Web 版と同じ)。
    private func loadBookmarks() {
        let videoID = program.id
        bookmarkFetchGeneration += 1
        let generation = bookmarkFetchGeneration
        Task { [weak self] in
            guard let self else { return }
            let fetched = await APIClient.shared.fetchBookmarks(videoID: videoID)
            // 取得の間に新しい取得が始まっていたら、この結果は古い
            // ため反映しない (削除後の取り直しより前の結果が遅れて
            // 届き、消したしおりが表示に戻るのを防ぐ)。
            guard generation == self.bookmarkFetchGeneration else { return }
            self.bookmarks = fetched
            self.rebuildContent()
        }
    }

    /// しおりを削除する (成功・失敗によらずサーバーの状態に合わせ直すため、
    /// 削除後は一覧を取り直す)。
    private func deleteBookmark(id: String) {
        let videoID = program.id
        bookmarkFetchGeneration += 1
        let generation = bookmarkFetchGeneration
        Task { [weak self] in
            guard let self else { return }
            let deleted = await APIClient.shared.deleteBookmark(videoID: videoID, bookmarkID: id)
            let fetched = await APIClient.shared.fetchBookmarks(videoID: videoID)
            // 取得の間に新しい取得が始まっていたら、この結果は古い
            // ため反映しない (loadBookmarks と同じ)。
            if generation == self.bookmarkFetchGeneration {
                self.bookmarks = fetched
                self.rebuildContent()
            }
            if !deleted {
                // 失敗が分からないと「押したのに消えない」ままになるため知らせる。
                let alert = UIAlertController(
                    title: nil,
                    message: "しおりを削除できませんでした。接続先とネットワークを確認してください。",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    /// タイル画像を取りに行く。届いた絵の寸法がタイル情報と合わない場合は
    /// 場面の画像は出さない (シーク中のプレビューと同じ扱い)。
    private func loadSprite() {
        guard !chapters.isEmpty,
              let tile = program.recorded_video.thumbnail_info?.tile else { return }
        let videoID = program.id
        Task { [weak self] in
            guard let self else { return }
            guard let data = await APIClient.shared.fetchTiledThumbnail(videoID: videoID) else { return }
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let image, let cgImage = image.cgImage,
                  cgImage.width == tile.image_width, cgImage.height == tile.image_height
            else { return }
            self.spriteCGImage = cgImage
            self.rebuildContent()
        }
    }
}

/// 押されたら指定の場面へ移動する行・場面の入れ物。
/// 移動先の時刻を自分で持つ (組み直しで行が作り直されても対応がずれないように)。
final class SeekRowView: UIView {
    var seekTime: Double = 0
}

extension SceneListViewController: UIGestureRecognizerDelegate {
    /// 行の移動の受け口がタッチを受けるかどうか。
    /// ボタンの上のタッチは受けない (ボタンの操作を優先する)。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIButton { return false }
            view = current.superview
        }
        return true
    }
}
