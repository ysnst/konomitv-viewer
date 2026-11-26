# 0.26と0.34の開発ベース比較

2026-11-26。0.34ベースの実装をいったん保留し、0.26の再採用可否を調査した。**追加の実機再検証により0.26を正式採用した。** [再検証結果](testing/device-0.26-recheck.md)と[現行開発計画](development-0.26.md)を参照。以下の差分調査は保持し、将来方針は最新指示に訂正した。 既存の再構築資料は代替経路として保存し、この文書を今回の比較判断の記録とする。

## 判断

必要な独自機能の復元工数は0.26の方が少ない。ホーム、履歴、一覧、字幕世代管理、省スペースUIが既にあり、旧実装の大部分を再接合せずに済む。一方、**今回0.26でも生放送・連続チャンネル切り替えが実機成功**。必要な独自機能が揃っている0.26を正式採用した。ただし全条件で0.34より安定すると保証するものではない。

0.26で生放送・連続切替・相互切替・読込中退出等が成功したため、0.26を採用する。生放送tap停止とseek表示残留を段階Aで修正し、実機完了まで後続を重ねない。キャプチャ除去は撤回し6ボタン・既存機能を維持する。0.34は代替として保存する。

## 対象と来歴

| 対象 | 固定したSHAと証拠 |
| --- | --- |
| 0.26 / build 26 | `60ae8789dc3ec4e97b7a8853582667fcd90a5e98`。ビルド時integration/upstream-sync |
| 0.33 / build 33 | `ff3ac274ff96c8e62d8d8e26de87d51e54877014`。比較対象、開発ベースにはしない |
| 0.34 / build 34 | IPA元 `684c880e9b0012b8d48aace3a20bed3a84be9989`。本家アプリ基準 `a2de08583aec2ea66c31ba9605acc84e394c5e15` |

0.26の既存IPAを読み取り専用で検証し、SHA-256は `117f9dc806755770fa1f3395001a0c21e779525418d5a17c7266be4df11c638c` に一致。ZIPのCRC、内外build-info.json、Info.plistの完全SHA・version/build・実行ファイルを既存verify-ipa.pyで照合した。[Actions 45726618175](https://github.com/ysnst/konomitv-viewer/actions/runs/45726618175)の成功とheadShaも再確認。新しいIPA・Releaseビルドは実行していない。

別のローカルcloneに `codex/review-0.26` を作成し、HEADを0.26の完全SHAに固定した。旧main、旧integrationブランチ、0.34の作業ツリーを切り替えたり編集したりしていない。この調査ブランチもcommit/pushしない。

## 依存関係

| 項目 | 0.26 | 0.34 |
| --- | --- | --- |
| VLC | VLCKit 4.0.0a26。Podfileの4.0.0-a26 podspecと実ビルドのPodfile.lockで一致 | MobileVLCKit 3.7.5。段階0実ビルドのlockで確認 |
| ARIBデコーダー | libaribcaption 1.1.2、vendorローカルpod | 同じ1.1.2 |
| 最低iOS | 16.0 | 16.0 |
| CocoaPods | 実ビルドlockは1.17.0 | 段階0lockは1.17.0 |
| Apple標準 | UIKit / AVFoundation / AVKit / Network / WebKit等 | 同じ標準フレームワーク群を使用 |
| BML等 | 同梱web-bml・アイコン等。独立した意味バージョンを確認できないものはソースcommitで識別 | 同梱資源を本家基準に固定 |

0.26のVLCKit.framework内Info.plistは1.0/1という汎用表記で、これだけから4.0.0a26とは判定しない。依存の根拠はPodfile、ビルド時lock、同一IPAの来歴である。0.26から0.33ではPodfileに変更なし。バージョン差だけで生放送の原因とは断定しない。

## 機能と実機証拠の比較

「実装」はソースに経路があること。「実機成功」は各版の報告範囲だけを指す。

| 項目 | 0.26 | 0.34 |
| --- | --- | --- |
| HEVC録画 | TS/VLC4経路。映像・シーク実機成功 | 本家VLC3/条件付きfMP4・AV。映像音声実機成功。実際の選択経路は未記録 |
| 生放送 | VLC4・独自PiP drawable。今回映像/音声が実機成功。tap停止は段階Aで修正 | 本家VLC3経路。映像音声実機成功 |
| 連続チャンネル切替 | 今回切替/継続が実機成功 | 切替・切替後の継続が実機成功 |
| 録画↔生放送・読込中離脱 | 今回相互切替/読込中退出が実機成功 | 実機未確認（当時のユーザー回答） |
| PiP | AVおよびVLC4 native drawable。HEVC録画の開始継続復帰が実機成功。H.264・生放送は未確認 | AVPlayerのPiPを実装、VLC独自PiPなし。HEVC録画の開始継続復帰が実機成功だが内部経路は未記録 |
| 字幕・文字スーパー | libaribcaption、取得範囲タイムラインとシーク世代。全画面字幕成功。文字スーパーの個別条件は未確認 | 基本表示は本家実装、字幕表示成功。旧版の取得範囲/直列化差分は未接合 |
| 実況 | 通常/全画面の表示設定共有、過去ログ・live受信・検索等。全画面表示成功 | 本家overlay/一覧/live実装、表示成功 |
| シーク | 直列処理・VLC4完了通知・最新世代、表示用先行位置。HEVC再生/シーク成功。同期ずれは未解明 | 本家表示追従・VLC3時間設定。直列化/残留防止の追加は未実装、今回の実機10件に個別シークは含まれない |
| 全画面 | 本家と同一VC方式へ移植済み、往復成功 | 本家同一VC方式、往復成功 |
| Cloudflare Access | 既存認証・必須relay・開始世代。実機成功 | 本家認証・relay。外部接続/再生・認証保持成功。追加合成HTTP契約試験成功 |
| 履歴・PWA同期 | 独自WatchedHistoryStoreの競合対処・位置同期。実機成功 | 本家同期あり、録画位置同期成功。独自履歴モデルは未接合 |
| 録画ホーム | 最近10/マイリスト4/履歴4、もっと見る・30秒更新 | 一覧はあるが独自ホーム10/4/4は未実装 |
| 視聴進捗 | 独自ホーム/カードのバーと履歴反映あり | 独自バー改善は未接合 |
| ページャー | 上下9ボタン・先頭末尾直行・サーバー側30件/page | 本家一覧のページ送り。独自9ボタンは未接合 |
| スクロール位置 | 上下操作元pager座標保持、ON/OFF、復帰と新規区別。録画一覧/位置保持は実機成功 | 旧実機成功仕様に対応する独自geometryは未接合 |
| プレイヤーUI | 下端操作・密度はseek中だけ・下部固定タブ・6ボタン。captureを含む6ボタンをそのまま維持 | 本家UI。指定5ボタン、下端細seek、省スペース等の独自差分は未接合 |
| 設定 | 映像を覆わない通常panel/全画面panel。実機成功。保持件数は整数入力/確定取消/減少確認 | 本家設定。固定panel、整数入力等の独自改善は未接合 |
| キャプチャ | 既存実装あり、通常/字幕付きserver保存が当時成功。削除方針は撤回し、今後も維持 | 本家基準に実装なし、追加しない |
| オフライン保存/再生 | 未実装 | 未実装。方式Aの調査と基本承認のみ |

### 0.26の機能棚卸し

0.26コミットのREADMEは0.20を基準とする記述が残るため、ソースと後続の[0.26実機記録](https://github.com/ysnst/konomitv-viewer/blob/22c8a5636a8aca1a4c0eda1241f8aef06da57d3a/docs/testing/device-0.26.md)を優先した。以下は機能群全体の実装確認であり、全操作の実機成功一覧ではない。

| 機能群 | 確認した実装と主なソース |
| --- | --- |
| 起動・タブ | Setup、4メインタブ、再タップroot、タブ内状態、回転/status bar委譲。SceneDelegate / MainTabBarController |
| ホーム | 最近10/マイリスト4/履歴4、検索/もっと見る、30秒更新、可視位置保持、要求合流・世代/認証範囲、画像cache。VideoHomeViewController |
| 録画一覧 | サーバー30件/page、検索debounce/日本語確定待ち、新旧順、未視聴/保護フィルタ、9ボタン、新規page1/復帰状態保持。VideoListViewController / PaginationGeometry |
| カード・一括操作 | ファイル情報、視聴済、mylist、保護、ゴミ箱、選択/ドラッグ選択/自動スクロール/一括操作。VideoListViewController。サーバー拡張・ログイン条件あり |
| マイリスト・履歴 | 一覧/ページ/位置、ファイル情報、履歴除去、双方向位置同期、保持件数正のInt入力/確定取消/減少確認。MylistViewController / WatchedHistoryViewController / WatchedHistoryStore / GeneralSettingsViewController |
| 管理拡張 | 容量、ゴミ箱/復元/完全削除/一括・削除preview token、録画結果。TrashViewController / RecordingResultsViewController / APIClient。対応サーバーが必要 |
| 録画基本操作 | AV通常/VLC HEVC、再生停止・秒skip・長押し、chapter/sprite preview、resume巻戻し、速度/画質/回線/音声のみ/副音声、CM skip、追いかけ/先端追従、次話。PlayerViewController / FastSeekController |
| 番組機能 | 前後話、mylist、しおり/場面、コメント検索/位置移動、盛り上がり、digest/ハイライト横断、今日のハイライト、次回/シリーズ予約。Player / SceneList / CommentSearch / Highlights |
| UI・設定panel | 同VC全画面、6ボタン、下部情報/コメントtab、通常下/全画面幅制限panel、repeat/restart/sleep。Player / PlayerSettingsViewController |
| 字幕/スーパー | font/縁取り/透明度/TV録画別設定、seek時無効化、完全受信範囲と最新世代復元・古いAV/relay通知排除。AribCaption / CaptionPlaybackTimeline / CaptionSettings |
| 実況 | 録画過去ログ/overlay/一覧/検索、live WebSocket受信/投稿/再接続、コピー、ID/keyword mute、サイズ/固定/色/連続文字mute、正規化/速度/font/透明度/無制限。LiveCommentSession / JikkyoCommentOverlay / 関連Settings |
| 生放送 | 局一覧/番組情報/logo、ピン順/勢い順、局切替、情報/局/コメントpanel、音声のみ、回線/画質、同VC全画面/restart。LiveList / LivePlayer / PinnedChannels |
| データ放送 | 同梱web-bml、WKWebView/TS中継、remote/映像配置、internet許可・郵便番号/地域・NVRAM保存/reset。DataBroadcastOverlay / DataBroadcastingSettings |
| 番組表・予約 | 格子/日付/種別、幅/時間高/通販減光/予約/genre、EDCB予約追加削除/有効無効・既定録画・シリーズ/自動予約。TimeTable / Reservation関連 / APIClient |
| 認証・account | CF token、Basic/Digest、独自header2組、browser cookie、p12、URL parameter、Keychain、KonomiTV login/logout・account変更/icon・ニコニコ連携。SettingsStore / APIClient / AccountSettings |
| 全般・拡張設定 | TV/録画×Wi-Fi/cellular画質/節約/24fps、live低遅延、28時間/放送時刻/初期panel/UI倍率/pager scroll。version7回tapで拡張解放、全体OFFで解除。端末限定toggle。各Settings VC |
| PiP・背景 | VLC4/AV PiP、背景/復帰、位置同期、Now Playing/remote、PiP owner保持。PlaybackPiPController / NowPlayingManager / 各Player |
| 旧キャプチャ | 通常/字幕・3保存先・同期・JPEG/EXIF・認証upload。実況付きは削除済。VideoCaptureController等。今後も維持 |
| 再生管理・品質 | 非同期relay/開始世代、無認証直結禁止、背景VLC停止、keepalive/回復、先行表示位置、署名なしIPA/来歴、履歴/位置/字幕/開始/寿命テスト。PlaybackStartState / PlaybackLifecycleState / scripts / workflows |

全録画の常時一括取得ではない。ただし0.26の未視聴/保護フィルタには最大50page/1500件のクライアント走査制約がある（VideoListViewControllerのfilter取得）。「数千件の全条件で無制限に絞れる」とは扱わない。

## 0.26から0.33までの変更

履歴上40コミット（mergeで入った本家履歴を含む）。アプリ配下では10ファイル変更、うち実行処理のSwiftは7ファイル。残りはproject、test scheme、UI test。全完全SHA・messageは同時出力の `artifacts/base-comparison/commits-0.26-to-0.33.tsv` に保存した。

| 変更 | 導入点・影響 |
| --- | --- |
| HEVC fMP4判定 | 本家52545e76c996646ae04d493b712697536824f0f0、接合34d926c97628a2f3bfc2e465ec08b1eecd42ba47。認証付きplaylistでEXT-X-MAPをprobe、対応ならAV、非対応/失敗ならVLC。0.26にはない |
| fMP4開始失敗復旧 | 本家8d333ab3c1f81d69a16c2810a34ec0dae4c0840a、同34d926cで接合。3秒後1回再試行後、同session/最新位置でVLCへ |
| 実進行監視 | 本家a2de08583aec2ea66c31ba9605acc84e394c5e15、接合bb814137b8214cbe67b789289d466e911cda617f。2秒超の進行と12秒watchdog。FMP4PlaybackState追加 |
| 回復の競合 | 844258fba671dfba1f2401fb09e84f1f69bb0e90。fMP4とkeepaliveの回復を直列化、準備前seekの最新位置を保持 |
| VLC入力 | d04ba867e9c619db2d0262bda47b299cb6831d58。共通PiP drawableの描画子view入力を抑止し親操作へ渡す。liveにも使う部品だが、これをlive失敗の原因とする証拠はない |
| 操作帯 | 33ecc8f691cbbeb028d57417a5eeb80884c7b65e。非同期開始後の自動非表示と長押し維持。fMP4監視との接合を含むため丸ごと移植しない |
| 試験基盤 | 元UI試験・AX識別子・連続TS/fMP4素材・native tap・runner・診断の追加/撤去。試験結果と実機結果は別 |
| 変わらないもの | LivePlayer本体、Podfile、AribCaption/CaptionPlaybackTimeline、共通認証設定、ホーム/一覧/履歴。StreamRelayServerの差分はMAP対応の説明コメントだけ |

0.33ではHEVC、操作帯、シーク、字幕、PiP、UI、履歴等18件成功、連続番組切替1件失敗。後にユーザーはその切替をリアルタイムのことだと思っていたと回答し、live開始は「再生に失敗しました」。録画番組切替の独立した失敗と断定しない。今回0.26liveは成功したが、0.33で生じた失敗の原因は未特定。fMP4差分があるだけで原因とはしない。

0.26へ後続変更を入れる場合、まず再検証で必要性を確認する。VLC tap抑止と操作帯改善は小さく分離する候補だが、録画/live/PiPの回帰確認が必要。fMP4一式は依存するretry/watchdog/seek/keepaliveまで大きいため初期採用を推奨しない。採用前調査ではいずれも適用していなかった。正式採用後の段階Aではd04ba86相当の入力抑止3行だけを個別採用した。

## 既知の問題と未確認

- シーク後の字幕同期ずれは原因未特定。0.26の9件や0.34の10件に新たな発生報告がないことは、原因解消の証拠ではない。残留と同期ずれは区別する。
- 0.26の字幕残留防止は実装済みで、先行版0.20に実機解消記録がある。ただし0.26で全シーク条件を個別再検証した記録はない。未取得直前区間の継続字幕は完全復元を保証しない。
- PiP内字幕/実況、L字クロップは未対応。今回は必須対象外。
- 0.26のlive/連続局切替、録画↔live、読込中退出は今回成功。H.264、live PiP、他認証、BML、長時間性能/発熱は個別未確認。0.33の成功を0.26へ流用しない。
- 0.34は10件成功だが、相互切替/取消と独自機能復元は残る。AV単独simulator時計停止は既知の試験制約で、VLC復帰をAV成功としない。
- キャプチャ除去指示は撤回済み。実装・権限・API・設定・既存テスト・6ボタンを維持し、段階Aでも回帰を確認する。

## 残工数とオフラインへの影響

規模は比較のための見積りで、日数や安全性の保証ではない。実機での追加不具合によって変わる。

| 作業 | 0.26採用 | 0.34採用 |
| --- | --- | --- |
| 再生基盤 | 今回liveも成功。確認されたtap停止/seek表示残留だけ段階Aで修正 | 10件成功基盤を保持、相互切替/取消の検証が残る |
| 字幕/seek | 既存VLC4完了通知・直列化を維持。同期ずれは別調査 | 大/高リスク。VLC3公開APIにVLC4完了callbackがなく観測方式の接合が必要 |
| UI | 小〜中。6ボタンを維持し、最新seek寸法は段階Bの独立変更 | 中〜大。5ボタン/下部tab/固定panel/省スペース等を再接合 |
| ホーム/履歴/一覧 | 既存維持・再検証中心。フィルタ制約は別判断 | 中。10/4/4・進捗・整数入力・geometry/9pager・状態保持を接合 |
| 本家追従 | 独自差分を多数維持する負担あり。後続一括mergeを避ける | 本家構造そのものから開始できる利点。独自差分追加後も継続確認が必要 |
| オフライン | 大/新規。既存履歴・VLC PiPは利用候補だがlocal対応済みではない | 大/新規。同じ取得/保存/outboxが必要。local PiPの形式制約あり |

方式A（標準GET /api/videos/{id}/downloadで原本取得）の基本承認は両案で維持する。既存offline-research.mdの固定版調査を引き継ぎ、利用サーバー/API/Range/validator・原本拡張子/字幕/音声を実測する。再エンコードやサーバー追加改造を前提にしない。

両案とも永続queue、partial/complete、200/206/416、If-Range、容量/通信制御、再起動復元、保存管理、コメントsidecar、履歴outbox/競合選択は新規。大容量全体をDataへ読まない。原本TSのARIB PESと現在のHLS向けID3抽出は別物で、字幕/スーパーがそのまま動くとは扱わない。

0.26のVLC4 PiPはローカルHEVCを扱う候補を持つが、実装はオンライン前提なので未検証。0.34のAV PiPはAVPlayerで原本形式を再生できる場合に限られ、VLCのlocal再生成功だけでPiP成功にはならない。どちらもローカルモードでkeepalive/再接続/再取得を止め、無断streaming切替を防ぐ必要がある。

履歴は既存同期モデルを利用できても、古いoffline履歴の無条件上書きや位置max統合を避けるoutboxが必要。サーバーの設定PUTには完全な原子的CASがなく、競合を検出して保留・選択する制約を維持する。LiveContainerの背景/強制終了/別guest/更新container保持も両案の実機課題。まず前景の安全な中断再開を対象とする。

## 再検証後の決定

0.26を正式採用し、0.34の再構築は保留。31件の再検証は29成功/1失敗/1未確認、密度残留は追加不具合。[現行計画](development-0.26.md)の段階Aだけを実装し、実機確認後にB以降へ進む。キャプチャ除去と5ボタン化は完全撤回。fMP4一式は採用しない。

比較表の実機未確認は調査当時の証拠範囲であり、今回更新された生放送/切替/独自機能は[今回の結果](testing/device-0.26-recheck.md)を優先する。過去9件と今回の31件を混同しない。0.33の失敗原因や過去の字幕同期ずれの原因は引き続き未特定。

## 今回の検証と保護

既存IPA照合とPython来歴検証9件が成功。今回、新しいSwift試験、UIスモーク、Release、依存の再解決、IPA生成は行っていない。0.26の過去Releaseは成功・警告87件（0.20比で新規0）。0.33と0.34の86件とは別ビルドの数であり、今回警告を減らした結果ではない。

比較の固定資料は本家SHA、各版のソース、既存Actions/lock/来歴、0.26・0.33・0.34の実機記録、0.34のplan/feature-matrix/offline-research。過去の文書は変更していない。保護対象2作業ツリーのHEAD/ref/statusと追跡/未追跡ファイルhash、全既存IPAのhashを開始/終了時に比較し、不変を確認した。旧作業ツリー336ファイル/IPA22本、0.34作業ツリー202ファイル/IPA1本が一致。独立レビューでも両新規文書と40件の履歴一覧に必須修正の指摘はなかった。Markdown相対リンク/フェンス、actionlint、差分チェックも成功。結果はartifacts/base-comparisonへ保存した。これは採用前調査の記録。現在の段階Aは別開発ブランチでcommit/push/IPA生成を行い、mainには統合しない。
