# 0.26を基準にした開発計画（現行）

0.26の実機再検証結果を受け、正式な開発基準を60ae8789dc3ec4e97b7a8853582667fcd90a5e98へ固定した。VLCKit 4.0.0a26 / libaribcaption 1.1.2、既存PiP・認証・保存キーを維持する。[再検証31項目](testing/device-0.26-recheck.md)は29成功・1失敗・1未確認、密度残留は追加不具合。0.34再構築は破棄せず代替経路として保留する。

## 撤回と維持

**キャプチャ削除・5ボタン化を完全撤回。** 通常/字幕付きキャプチャ、サーバー/写真/両方、保存設定/権限/同期、JPEG・EXIF、API、既存テストを維持する。0.26で既に削除済みの実況コメント付き撮影は復活させない。操作は通常撮影→実況→字幕→設定→PiP→全画面の6個のまま。

本家再構築のVLC3維持方針は0.34案だけの履歴であり、この開発へ適用しない。0.26以降のfMP4/開始監視/retry/fallback/keepalive回復を一括導入しない。本家更新も自動mergeしない。サーバー追加改造、依存更新、全面的な再生/設定/UI再設計は行わない。

## 機能比較表（現在の受け入れ状況）

| 群 | 0.26の状態・維持条件 | 0.34案 |
| --- | --- | --- |
| HEVC/音声/PiP | 今回実機成功。VLC4/AV・drawable所有を保持 | 10件の成功基準として保存 |
| 生放送/連続局切替/継続 | 今回実機成功。映像tap停止だけ段階Aで修正 | 実機成功。旧失敗の原因判定には使わない |
| 相互切替/読み込み中退出/短時間切替/PiP復帰後 | 今回実機成功。未報告組合せまで拡張しない | 段階1/2の実機ゲートは未確認のまま保存 |
| 字幕/実況/全画面/認証/履歴/再起動後設定 | 今回実機成功。字幕残留と同期ずれを区別、過去同期ずれの原因は未解明 | 本家基準として保存、独自字幕接合は未実装 |
| ホーム10/4/4・進捗・30秒位置保持・整数入力・9pager・ON/OFF・もっと見る | 今回実機成功、既存実装維持。50page/1500件filter走査制約は変更しない | 復元計画を保存・保留 |
| タブ/再生復帰の一覧位置 | **今回未確認**。段階Aのチェックリストで確認、先回り再実装しない | 保留 |
| seek/長押し/設定/repeat/restart | 連続/停止中seek・設定/repeat/restartは成功。tap後preview/密度残留は段階A | 独自UI計画は保留 |
| capture/6button | 既存実装・テストを維持。今回個別の新実機成功報告ではない | 除外計画はこの開発では撤回済み |
| オフライン | 方式A基本承認・未実装。オンライン不具合修正の実機合格後 | 技術調査を引継ぎ、アプリ再構築自体は保留 |

## 段階A〜F

| 段階 | 実施内容 | 次へ進む条件 |
| --- | --- | --- |
| A 最優先 | live映像tap停止、録画seek tap後preview/密度残留。必要な後続差分だけ採用 | 独立レビュー・回帰・Release・新IPA照合、**利用者の実機確認** |
| B seek省スペース | 通常2pt/つまみなし、操作中4pt/12pt、判定44pt程度。中心/映像/情報を動かさず6操作維持 | Aの実機完了後。Aの表示状態管理を再実装しない |
| C 原本保存基盤 | API/原本/認証/Rangeを実測、永続queue・progress・中断再開・容量/Wi-Fi・前景転送 | 標準API契約が成立。不可なら制約と代替案を提示し判断待ち |
| D local再生 | 機内モード/local優先、HEVC/seek/速度/全画面、字幕/スーパー/実況/PiP | 原本形式を実証。online成功をlocal成功と数えない |
| E 管理/同期/背景 | 保存一覧・削除/容量、履歴outbox/競合保留/選択、LiveContainer背景・強制終了・更新保持 | 個別IPAと実機ゲート。server削除や無条件履歴上書きは禁止 |
| F 最終回帰 | 既存全機能/capture/新offline/切替/PiP/認証/履歴/大規模一覧 | 全実機結果と利用者了承。main統合は別判断 |

現在はAのみ。B以降は未実装。今回4/11ptのseek描画と24pt判定を変更せず、見た目の段階Bを混ぜない。

## 段階Aの実装境界

live側はd04ba867e9c619db2d0262bda47b299cb6831d58の必要な3行に相当する描画子viewの入力抑止だけを採用。VLC独自tapの入力先を親の操作帯へ寄せる。layer、PiP owner、再生/通信/認証処理を変更しない。

seek側は、任意位置へvalueを変えつつsuper.beginTrackingの受理結果へ依存していた追跡を、公開UILongPressGestureRecognizer（minimumPressDuration=0）のbegan/changed/ended/cancelled/failedへ統一する。最初のtracking override案でもnative tapで開始だけが残ったため置換した。標準beginTrackingは拒否し二重入力を避ける。終了/cancelはonTrackingEndedからownerへ直接通知し、二重終了をguard。表示解除と実seekを分け、停止時は表示だけ解除。退出/回転/全画面/PiPは既存seekで現在の入力を確定して表示を終える。遅着sprite/密度更新は非操作中に表示を復活させない。VLC4完了通知、字幕世代・直列seek・履歴の位置基準は変更しない。

UIイベントの内部通知順序は実装確認だけでは保証せずnative入力試験で確認する。実OSのtouchCancel発生と、公開cancelTrackingの直接呼び出し契約は分ける。0.33の生放送開始失敗の原因解明とは扱わない。

## 品質・保護

独立コミット、別担当レビュー、Python/Swift/HTTP/relay/UI smoke、capture JPEG・EXIF、actionlint、差分チェック、Release、来歴/版/hash照合を行う。警告基準は**0.26 Releaseの87件**。旧0.33/0.34の86件と混同しない。simulator試験を実機HEVC/PiP/CF成功へ拡張しない。

旧main・integration/upstream-next・0.34ツリー・review-0.26の基準ref・旧IPA・タグ/リリースを維持。開発はcodex/0.26-stage-a。Bundle ID/Keychain service/保存キー/利用者データを変えない。既存LiveContainerを無断置換しない。

[オフライン引継ぎ](rebuild/offline-research.md) / [次版の実機確認](testing/stage-a.md)

## 段階Aの成果物

候補0.36/build36、source `eef1a0793ecc53247b30fc86993df20ef3b0660e`。Release/Swift各群・UI3件・HTTP/relay・Python・JPEG/EXIF/Pillow・lintが成功。警告は87件/新規0。UI試験基盤のSDK・geometry・局名・AX再探索の不備は個別に修正し、アプリコードと区別した。途中0.35はseek終了欠落で不採用・保存。

0.36のHEVC PiPは実機成功へ訂正された。シーク後の再生継続は失敗報告があり、段階Aで内部pause/先行playを除去した0.37を生成した。PiP処理は修正対象外。[追加報告](testing/device-0.36.md)と[調査結果](seek-resume-0.36.md)を参照。[次のチェックリスト](testing/stage-a.md)でAを確認し、完了前にB〜Fの変更を重ねない。0.34案と旧main/branch/IPAは保存したまま。
