# IPA 0.26以降の本家更新

## 実機基準版とmain

[0.26の実機結果](testing/device-0.26.md)は主要9項目すべて成功。ビルド元は`60ae8789dc3ec4e97b7a8853582667fcd90a5e98`、SHA-256は`117f9dc806755770fa1f3395001a0c21e779525418d5a17c7266be4df11c638c`。

統合前mainは`a64bdb40004368be248645a02a62e93b1ac7b9fd`、統合後mainは`22c8a5636a8aca1a4c0eda1241f8aef06da57d3a`。0.26のビルド元以降は文書変更だけと確認し、20コミットをfast-forwardで統合した。競合なし、mainへpush済み。デフォルトブランチmain、GitHubトップのREADMEと検証記録リンクを確認した。先頭の文書コミットでCIをskipし、この統合では新IPAを生成していない。

後続更新は`integration/upstream-next`で扱い、新しい実機確認・了承まではmainへ統合しない。0.26の成功を後続版へ流用せず、字幕同期ずれの原因解消とも扱わない。

導入手順に残っていた0.20へのリンクも0.26へ統一し、文書1コミットだけを追加fast-forwardした。最終main・切り戻し基準は`12b75d7992909c0ad9aed91faaed5753c9548a09`。アプリの内容は最初の統合後と同じで、新しい再生経路は含まない。

## 調査した14コミット

取得時の本家mainは`8d333ab3c1f81d69a16c2810a34ec0dae4c0840a`、共通祖先は`3cf89e3fe9f5732a05d06e9d6b823635923ab70c`。最初の統合後main（22c8a563）は本家に対して53 ahead / 14 behind、導入リンクの文書修正後main（12b75d79）は54 ahead / 14 behind。件数は取得時の履歴から数えた。

| 完全SHA | 変更内容 | 主な対象・注意 |
| --- | --- | --- |
| `86e27f8fb73d73a5cdae210fd80adb22a8e37d62` | simulator smoke test追加 | workflow、UITest/scheme、pbx、stub/素材、Player識別子 |
| `93d05f497b4b53fdf913f28d94e909f31dfb5ce1` | SDKROOT明記 | アプリ/UITestのビルド設定 |
| `67cfc95df764f1e785e09f828c8c4997233265fc` | 非表示コントロールの再表示、局ロゴ応答 | UITest/stub |
| `7fb7336124b420e0f5d990461ed786cfd9ff9682` | HLSテスト素材をffmpeg出力へ変更 | stub/TS素材 |
| `317476dc4e2a50b4dbb4f7dfc782ad6628c7a080` | 暫定AV状態診断 | Player。後続で送信処理を削除 |
| `70600fdc70a9f31e0e7a07bc5393a0834d870777` | 暫定診断のプロパティ修正 | Player。後続で削除 |
| `7afddb09799856ec36d720bde4be6a558f04fea9` | 暫定診断削除、映像のみの素材へ | Player/TS素材 |
| `ff02c8b9d37e14d88eacc4fbaeea7320dcec1022` | 直接AV再生の診断テスト | 後続で削除 |
| `3c6518c06672284716e6ffaed29a363158105827` | macos-15でテスト切り分け | workflow。後続で戻す |
| `ecc50a8cab500b281fb02bd92b8dff47681796c5` | HEVC/VLCのfixture試験へ | workflow/UITest/素材 |
| `176e3143e3f14d187f077b17f43ed4d6fadd3774` | 診断テスト削除、codec整合 | 最初11件の完成点 |
| `52545e76c996646ae04d493b712697536824f0f0` | HEVC fMP4/AVPlayer判定とAV専用PiP | APIClient/Player/Relay説明/README/CHANGELOG |
| `2f5684474ebd7af815eabf7bb1d18b638ae429ad` | AVKit importのビルド修正 | Player/CHANGELOG |
| `8d333ab3c1f81d69a16c2810a34ec0dae4c0840a` | fMP4開始前失敗の一度再試行→VLC fallback | Player/CHANGELOG |

14件にPodfile/lock/SPM依存の更新や、既存のIPAビルド/公開workflow変更はない。明示的な脆弱性修正は確認していない。日時・全変更ファイルは各SHAの履歴で確認できる。途中の診断を残したSHAを完成点にせず、通常アプリからの診断送信を取り込まない。

## 段階的な接合方針

最初11件はテスト基盤とPlayerのaccessibility識別子が中心で、再生エンジンを変えない。フォークの録画ホーム、6操作、全画面ボタン名へテストを合わせる。空の時刻ラベルを再生成功と扱わず、実際の数値の進行を確認する。overlayコンテナの存在確認は字幕の実描画や実況の流動を証明しない。既存のPython/Swift/未署名IPA/来歴検証を維持し、新テストの結果は別に記録する。

後半3件は別のIPA段階とする。既存のVLCKit4と共通PlaybackPiPController、字幕Gの世代・シーク直列化、開始の認証/接続範囲照合、停止意図・保留シーク、履歴・撮影を維持して接合する。本家のAV専用PiPで既存のHEVC/VLC・生放送PiPを置き換えない。EXT-X-MAPは既存の汎用URI書き換えで中継対象になっている。

fMP4のemsg/ID3がAVPlayerのmetadata outputへ届く形式・時刻、HEVCフレームの撮影、同じセッションからVLCへ戻る挙動は実機未確認。本家のfallbackは開始前のAV項目失敗を対象とし、字幕だけ届かない場合を検出する保証はない。字幕のない区間と区別できないため、固定時間で字幕欠落と決め付けない。対応サーバーでHEVC字幕・通常/字幕付き撮影・PiP・シークを確認するまでは、後半を実機検証済み基準版へ昇格させない。0.26と再生経路を変えない段階のIPAを切り戻し用に残す。

## 段階A: テスト基盤

`176e3143`までの11件を通常mergeし、アプリ側は字幕/実況/時刻の識別子追加だけに限定した。既存6操作や録画ホーム、再生経路を置き換えていない。UIテストはホームの新着から開き、「全画面」「全画面を解除」を使い、通常/全画面/復帰後に数値の時刻が増えることを検証する。写真はアプリ画面のみを採取する。

独立レビューで、18秒fixtureが画面遷移中に終了する問題と、存在するが押せない操作帯を再表示しない問題を修正した。当初は3つの既存HEVC segmentをdiscontinuityで区切って180秒に延長したが、後述の切り分けで連続した新しいテスト素材へ置き換えた。専用サーバー/シミュレーターだけを終了し、ポート/デバイスの解放を確認するworkflowとした。既存IPA workflowと版番号生成には触れない。

UI試験は最初macos-26-intel/Xcode26.6で実行したが、初回起動に約7分、テスト用ビルドに12分以上かかった。本家の[成功済み実行13](https://github.com/tatsuya0902/konomitv-viewer/actions/runs/45725336702)がmacos-latest（macos-26-arm64）/Xcode26.6で約8分だったため、UI試験だけ同じラベルとXcodeへ切り替えた。起動/ビルド/テストに個別の上限を設け、無制限の待機を避ける。IPAのReleaseは従来のIntel環境を維持する。この切替によるアプリコードの変更はない。

ローカルでPython既存9件、新しいHTTP契約テスト3件（全30segment/404/サーバー終了とポート再利用）、actionlint、workflow内Python構文、差分チェックが成功。独立再レビューの修正必須指摘なし。Swift/Release/実シミュレーターはCIで別途確認する。シミュレーターのoverlay存在確認が成功しても、実字幕の描画や実況コメントの流動まで確認済みとしない。

## 段階B: fMP4選択と開始前復旧

後半3件を通常mergeし、AV専用PiP/旧MobileVLCKitへ戻す競合部分を、現在の共通PiPとVLCKit4へ接合した。metadata受信・撮影は既存AVの処理を使い、Gのシーク直列化、字幕世代、開始・認証世代、実時計を保持する。新たなエンジン設定UI、字幕トグル時の強制再接続、サーバー改造は加えない。本家のCHANGELOG版番号は本家の履歴であり、フォークのIPA番号や実機確認結果へ読み替えない。

独立レビューで次を修正した。

- probe中/relay中の最新seekを、readyで保留要求を消費した後も保持する。
- 失敗したAV項目のmetadata出力と撮影を直ちに失効し、古い字幕の再投入を防ぐ。
- retry/fallbackのrelay完了直前にもPiP/表示状態を確認し、遅れて始まったPiPの所有者を破棄しない。
- 接続/認証変更時に現在要求の待機だけを解除し、旧世代から新要求を取り消さない。
- retry成功時に専用の失敗表示を消し、失敗項目が残った場合も最新位置から手動再試行できるようにする。

route判定、0秒/途中開始、一度だけのretry→fallback、重複通知/古い試行、最新seek、PiP保留/relay中再保留、認証/開始世代のFoundationテストを追加した。ローカルPython9件・fixture3件・actionlint・差分チェックは成功。独立再レビューの修正必須指摘なし。SwiftとReleaseはCIで確認し、実際のfMP4字幕/スーパー/撮影/PiP/同じセッションでのTS復帰は[実機チェックリスト](testing/upstream-next.md)で未確認として扱う。

## 生成したIPAと品質確認

| 段階・版/build | ビルド元の完全SHA | Actions・SHA-256 |
| --- | --- | --- |
| A: 0.27 / 27（再生経路変更前） | `1256f686f3989ab339bf003e9052be0e17acd0c2` | [実行27](https://github.com/ysnst/konomitv-viewer/actions/runs/45738941562) / `1baa62091d70e323af5a9ce90ea5aafc4990ae5edcc9db3dd6b1882c05415ce6` |
| B: 0.28 / 28（fMP4接合） | `34d926c97628a2f3bfc2e465ec08b1eecd42ba47` | [実行28](https://github.com/ysnst/konomitv-viewer/actions/runs/45740355971) / `87bf92901667fe2d9eef454a84cad3271888e78e32d7354b4991618b18ca23db` |
| B: 0.29 / 29（UI試験環境調整） | `ee300e0b6daccfe3595f711f792fe607bc2c666c` | [実行29](https://github.com/ysnst/konomitv-viewer/actions/runs/45742195471) / `a3d2d03600d774564c06de0aeb8a7d4273a8ff10407526e04193530e0a9bea2e` |

3版ともReleaseと既存Python9件・Swift履歴/ページ位置/字幕タイムライン/非同期開始/ライフサイクル/撮影メタデータが成功。Bでは追加のfMP4状態テストも成功。各IPAを別ディレクトリへ取得し、内外の来歴、run/Info.plistの完全SHA・版・build、未署名、Bundle ID、Podfile.lock、JPEG・EXIF/Pillowを照合した。0.29のアプリコードは0.28と同じで、その後の文書コミットもIPAのビルド元とは区別する。

各Release警告は86件、新規0件。比較基準87件に対してNo App Category警告1件が減った（SDKROOT明記取り込み後に観測）。既存警告は解消済みとは扱わない。既存16個のIPAをハッシュ・サイズで再照合し、0.26を含め変更なし。依存ライブラリ、Bundle ID、字幕Gの処理、共通PiP、撮影生成/保存、生放送プレイヤーも基準mainから変更していない。

UI試験の最初のIntel実行2回は環境の待機が長いため中止し、いずれも専用プロセス終了・ポート解放・専用simulator削除をログで確認した。ARMでの[実行3](https://github.com/ysnst/konomitv-viewer/actions/runs/45742195452)はビルド成功後、時刻ラベルのexists確認とlabel読み取りの間に操作帯が自動非表示となり失敗した。失敗画面にはfixture映像と実況が表示されているが、再生全体の成功とは扱わない。

テスト側だけを[Apple公開APIのsnapshot](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot%28%29)で同時点の属性を読む形へ修正した。取得中に要素が消えた場合は期限内で操作帯を再表示し、厳密な時刻解析と各状態の時計増加の条件は緩めない。この変更はアプリコード・IPA 0.29の内容を変えない。再実行はUI試験だけを起動し、不要なIPAを作らない。

[実行4](https://github.com/ysnst/konomitv-viewer/actions/runs/45743960933)では通常/全画面の時計増加は通過したが、復帰後の時計増加に失敗した。録画を確認すると全画面終了前の操作帯再表示タップ付近で一時停止になっており、横向きAX座標（874×402）と縦向きevent orientationの組合せが保存されていた。アプリの全画面処理に停止呼び出しはなく、アプリの不具合と断定する根拠にはしない。

テストでは、まず全画面ボタンによる横長window/映像の配置確定を確認し、その後に自動操作端末の向きを同期する。解除後もボタン状態・情報タブの復帰を確認してから端末を縦へ戻す。通常画面は端末の向きに追従する契約を保ち、画面内の映像座標が安定するまで次の座標操作をしない。[端末と画面の左右対応](https://developer.apple.com/documentation/UIKit/UIInterfaceOrientation)に従い、テスト側だけに向き・window/映像の寸法を出力する。時計が止まった後に再生を押して成功扱いにする処理は追加していない。

[実行5](https://github.com/ysnst/konomitv-viewer/actions/runs/45746020534)では向き・配置の確認は通過したが、全画面前から映像が静止しており時計増加に失敗した。縦画面の再表示タップは期待座標と一致していたため、誤タップと断定しない。反復素材では映像時刻の巻き戻りがあり、単純なstream copyでの接続にも参照フレーム欠落が出た。この影響を除外するため、テスト専用に連続180秒のHEVCパターンを生成し、全30個の先頭キーフレーム、全packetのDTS連続性、全体デコードのエラー0を確認した。仮サーバーは実playlistの尺と各TSを返す。範囲外segmentの404を含むHTTP3テストも成功した。

消えた時刻要素の検索リトライを避けるため、時刻は1回のapp snapshot内から探す。各状態で新たな基準値を取り、時計増加・回転の条件を維持する。[素材の生成方法と制約](../SmokeTests/README.md)も保存した。素材・検索方法の切替はテスト側だけであり、今回の静止原因を特定した修正やアプリの不具合修正とは扱わない。

[実行6](https://github.com/ysnst/konomitv-viewer/actions/runs/45748584392)でも通常の時計0→1は通過し、再表示操作後に全画面の時計が7秒で進まなくなった。連続素材への切替だけで解消したとは扱わない。追加の切り分けでは非操作の字幕AX要素を座標の基準にせず、実window/映像のframeから中央再生ボタン・ヘッダー・シークバーを避けた位置へ操作する。これもテスト側だけの変更であり、アプリやVLCKitの不具合と断定していない。
