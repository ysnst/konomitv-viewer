import UIKit

/// ピン留め中チャンネルの並び替えの画面。Web 版の設定 → 全般から開く
/// 「ピン留め中チャンネルの並び替え」と同じ役割で、ピン留め中の
/// チャンネルの表示順序の変更と、ピン留めを外す操作を行う。
/// 並び順は利用者設定の pinned_channel_ids そのもので、変更は
/// その場で保存され、同期が入っていれば Web 版ともやり取りされる。
///
/// Web 版はつまみをドラッグして並べ替えるが、アプリでは各行の
/// 上下ボタンで並べ替える形にしてある (設定画面の土台が縦スクロール
/// のため、ドラッグだとスクロールと取り合うのを避けた)。
/// 行の見た目は Web 版の並び替え画面に合わせる: 局ロゴ (64x36)、
/// 「Ch: 番号 局名」(16.5px)、右に並び替えと削除のボタン、
/// 行の下に区切り線。
final class PinnedChannelsViewController: SettingsDetailViewController {
    private let descriptionLabel = UILabel()
    private let stateLabel = UILabel()
    private let rowsStack = UIStackView()

    /// 表示中のピン留めチャンネル (ピン留めした順)。
    /// チャンネル情報を取得できたものだけを並べる (Web 版の並び替え
    /// 画面と同じで、取得できなかったチャンネルは行に出ない)。
    private var entries: [LiveChannel] = []
    /// チャンネル情報の取得が済んだか (取得前と、ピン留めが無い場合の
    /// 文面を出し分けるため)。
    private var didLoad = false
    /// チャンネル情報の取得に失敗したか。
    private var loadFailed = false

    /// 局ロゴのキャッシュと、ロゴが無かった局の控え (生放送一覧と同じ扱い)。
    private let logoCache = NSCache<NSString, UIImage>()
    private var failedLogoIDs: Set<String> = []

    init() {
        super.init(headingTitle: "ピン留め中チャンネルの並び替え")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildItems()
        load()
    }

    private func buildItems() {
        descriptionLabel.font = .scaledSystemFont(ofSize: 13.5)
        descriptionLabel.textColor = AppPalette.metaText
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "各チャンネルの矢印ボタンで並べ替えできます。"
        stateLabel.font = .scaledSystemFont(ofSize: 13.5)
        stateLabel.textColor = AppPalette.metaText
        stateLabel.numberOfLines = 0
        rowsStack.axis = .vertical
        rowsStack.spacing = 0
        contentStack.addArrangedSubview(descriptionLabel)
        contentStack.addArrangedSubview(stateLabel)
        contentStack.addArrangedSubview(rowsStack)
        updateStateViews()
    }

    /// チャンネル情報を取り、ピン留め中のチャンネルの行を組み立てる。
    /// 同期が入っていれば、利用者設定を先に取り込んでおく。
    private func load() {
        Task { [weak self] in
            guard let self else { return }
            _ = await SyncedSettingsStore.shared.refreshFromServer()
            do {
                let response = try await APIClient.shared.fetchChannels()
                let allChannels = response.groups.flatMap { $0.channels }
                self.entries = SyncedSettingsStore.shared.current.pinnedChannelIDs
                    .compactMap { id in allChannels.first { $0.id == id } }
                self.loadFailed = false
            } catch {
                self.entries = []
                self.loadFailed = true
            }
            self.didLoad = true
            self.rebuildRows()
        }
    }

    /// 状態に合わせて、説明と状態の文面の出し分けをする。
    private func updateStateViews() {
        let hasEntries = !entries.isEmpty
        descriptionLabel.isHidden = !hasEntries
        rowsStack.isHidden = !hasEntries
        if hasEntries {
            stateLabel.isHidden = true
        } else if !didLoad {
            stateLabel.isHidden = false
            stateLabel.text = "読み込み中です。"
        } else if loadFailed {
            stateLabel.isHidden = false
            stateLabel.text = "チャンネル情報を読み込めませんでした。\n接続先とネットワークを確認してください。"
        } else {
            // Web 版の並び替え画面の、ピン留めが無いときの文面。
            // 「TV ホーム画面」はアプリのタブの名前に置き換えてある。
            stateLabel.isHidden = false
            stateLabel.text = "ピン留めされているチャンネルがありません。\nテレビをみる画面のチャンネル一覧のピン アイコンから、よくみるチャンネルをピン留めできます。"
        }
    }

    /// 行を組み直す。並べ替え・削除のたびに呼び、ボタンの有効・無効と
    /// 区切り線の有無を現在の並びに合わせる。
    private func rebuildRows() {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, channel) in entries.enumerated() {
            rowsStack.addArrangedSubview(makeRow(for: channel, at: index))
        }
        updateStateViews()
    }

    /// チャンネル1行分。並びは Web 版の並び替え画面どおり:
    /// 局ロゴ →「Ch: 番号 局名」→ 上へ・下へ・削除のボタン。
    /// 行の下端に区切り線を引く (最後の行だけ引かない)。
    private func makeRow(for channel: LiveChannel, at index: Int) -> UIView {
        let logoView = UIImageView()
        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.backgroundColor = AppPalette.placeholder
        logoView.layer.cornerRadius = 4
        logoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 64),
            logoView.heightAnchor.constraint(equalToConstant: 36),
        ])
        if let logo = logoCache.object(forKey: channel.id as NSString) {
            logoView.image = logo
        } else {
            loadLogo(for: channel, into: logoView)
        }

        let nameLabel = UILabel()
        if let number = channel.channel_number, !number.isEmpty {
            nameLabel.text = "Ch: \(number) \(channel.name)"
        } else {
            nameLabel.text = channel.name
        }
        nameLabel.font = .scaledSystemFont(ofSize: 16.5)
        nameLabel.textColor = AppPalette.text
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let upButton = makeRowButton(systemName: "chevron.up", label: "上へ移す")
        upButton.tag = index
        upButton.isEnabled = index > 0
        upButton.addTarget(self, action: #selector(moveUp(_:)), for: .touchUpInside)
        let downButton = makeRowButton(systemName: "chevron.down", label: "下へ移す")
        downButton.tag = index
        downButton.isEnabled = index < entries.count - 1
        downButton.addTarget(self, action: #selector(moveDown(_:)), for: .touchUpInside)
        let deleteButton = makeRowButton(systemName: "trash", label: "ピン留めを外す")
        deleteButton.tag = index
        deleteButton.addTarget(self, action: #selector(deleteRow(_:)), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [logoView, nameLabel, upButton, downButton, deleteButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.setCustomSpacing(16, after: logoView)
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        if index < entries.count - 1 {
            let divider = UIView()
            divider.backgroundColor = AppPalette.pressed
            divider.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                divider.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        return container
    }

    /// 行の右側のボタン (当たり判定は Web 版の並び替え画面と同じ 35x40)。
    /// 使えないとき (先頭行の上へ、など) は薄く出す。
    private func makeRowButton(systemName: String, label: String) -> RippleButton {
        let button = RippleButton()
        button.setImage(
            UIImage(systemName: systemName,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))?
                .withRenderingMode(.alwaysTemplate),
            for: .normal)
        button.tintColor = AppPalette.text
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 35),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        return button
    }

    /// 局ロゴを取ってきて行へ反映する。取れなかった局は地だけのままにし、
    /// 再取得もしない (生放送一覧と同じ扱い)。
    private func loadLogo(for channel: LiveChannel, into logoView: UIImageView) {
        guard !failedLogoIDs.contains(channel.id) else { return }
        Task { [weak self, weak logoView] in
            guard let self else { return }
            guard let data = try? await APIClient.shared.fetchChannelLogo(channelID: channel.id),
                  let image = UIImage(data: data) else {
                self.failedLogoIDs.insert(channel.id)
                return
            }
            self.logoCache.setObject(image, forKey: channel.id as NSString)
            logoView?.image = image
        }
    }

    // MARK: - 並べ替えと削除 (変更はその場で保存する)

    @objc private func moveUp(_ sender: UIButton) {
        move(from: sender.tag, by: -1)
    }

    @objc private func moveDown(_ sender: UIButton) {
        move(from: sender.tag, by: 1)
    }

    private func move(from index: Int, by delta: Int) {
        let target = index + delta
        guard entries.indices.contains(index), entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
        saveOrder()
        rebuildRows()
    }

    @objc private func deleteRow(_ sender: UIButton) {
        guard entries.indices.contains(sender.tag) else { return }
        entries.remove(at: sender.tag)
        saveOrder()
        rebuildRows()
    }

    /// 現在の並びを利用者設定へ保存する。行に出ていないピン留め
    /// (チャンネル情報を取得できなかったもの) は、Web 版の並び替え
    /// 画面で変更したときと同じく、この時点で取り除かれる。
    private func saveOrder() {
        var settings = SyncedSettingsStore.shared.current
        settings.pinnedChannelIDs = entries.map { $0.id }
        SyncedSettingsStore.shared.update(settings)
    }
}
