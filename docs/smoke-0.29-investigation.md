# IPA 0.29のUI停止調査

実機検証済み基準は[0.26](testing/device-0.26.md)。mainは`12b75d7992909c0ad9aed91faaed5753c9548a09`を維持し、調査・修正は`integration/upstream-next`だけで行う。0.29は安定版ではない。既知のシーク後字幕同期ずれとは別の調査である。

## 再現と原因

[元の失敗](https://github.com/ysnst/konomitv-viewer/actions/runs/45752116278)は通常画面の時計4秒で停止したが、当時の画面だけではUI表示と再生エンジンの停止を区別できなかった。

[診断付き比較](https://github.com/ysnst/konomitv-viewer/actions/runs/45762476214)では、同じ180秒の連続HEVC/TS素材、同じUI操作・診断、Xcode 26.6、iOS 26.5 simulatorで以下を比較した。Podfile.lockとVLCKit実バイナリのSHA-256も一致した。

| 対象 | ソース・差分 | 結果 |
| --- | --- | --- |
| 0.27相当 | `1256f686f3989ab339bf003e9052be0e17acd0c2`。0.26とのアプリ差分はAX識別子10行 | 全画面で操作帯を再表示するタップ後、VLCがpausedへ移行。実時計12.766秒で停止し、復帰後の進行確認に失敗 |
| 0.29相当 | 診断ハーネス`a1241b0`。アプリ本体は0.29の`ee300e0b6daccfe3595f711f792fe607bc2c666c`と同一 | 同じタップ後にVLCがpausedへ移行。実時計13.433秒で停止し、全画面の進行確認に失敗 |

両方で`intent=true`、scrubなし、アプリの`pauseEngine`・`togglePlayPause`・親の`toggleControls`呼出なしのまま停止した。0.29だけの回帰ではなく、時計表示だけの停止でもない。状態通知と0.5秒の更新処理は停止後も届いていた。仮サーバーはsegment・keep-aliveへ200を返していた。映像のみの素材なので音声の停止・同期は評価していない。

固定libVLC [`f7caf7922478f6cb7f1654b813d0c462d3e86f4a`](https://github.com/videolan/vlc/tree/f7caf7922478f6cb7f1654b813d0c462d3e86f4a)には次の経路がある。

1. [media_player.c](https://github.com/videolan/vlc/blob/f7caf7922478f6cb7f1654b813d0c462d3e86f4a/lib/media_player.c)がmouse-eventsを有効にする。
2. [VLCVideoUIView.m](https://github.com/videolan/vlc/blob/f7caf7922478f6cb7f1654b813d0c462d3e86f4a/modules/video_output/apple/VLCVideoUIView.m)の独自タップ認識器が左クリックの押下・解放を送る。
3. [es_out.c](https://github.com/videolan/vlc/blob/f7caf7922478f6cb7f1654b813d0c462d3e86f4a/src/input/es_out.c)の既定mouse-pause-policy=autoが解放時のイベントへつなぐ。
4. [player/input.c](https://github.com/videolan/vlc/blob/f7caf7922478f6cb7f1654b813d0c462d3e86f4a/src/player/input.c)が`vlc_player_TogglePause`を実行する。

アプリはPiP用drawableが追加するVLCVideoUIViewの入力を有効なままにしていた。この構造は`0d4c64a8470a0ad43ec5c68acc9f5bb885038672`から存在し、0.28のfMP4追加で導入されたものではない。今回、全画面往復と操作帯再表示を含む自動操作で再現した。実機での発生頻度は未確認。

## 最小修正

`PlaybackPiPController.addSubview`でVLC描画ビューの`isUserInteractionEnabled`をfalseにし、入力を既存の親surfaceへ集約する。映像layer、ハードウェアデコード、PiP所有者、音声、認証、字幕、撮影処理は変更しない。通常・生放送で同じwrapperを使うが、生放送と実機PiPは別途確認が必要。

修正は`d04ba867e9c619db2d0262bda47b299cb6831d58`。独立レビューに修正必須指摘なし。[最初の再試験](https://github.com/ysnst/konomitv-viewer/actions/runs/45764099007)は以下の別の試験操作の問題で失敗し、最終のTS試験は成功した。時計増加の判定は緩和せず、停止後の強制再生も追加していない。

最初の修正後UI実行では、VLC描画ビューの入力がfalse、親`toggleControls`の呼出と実時計26.9秒までの進行を確認した。以前の一時停止は再発していない。ただしケース全体は、全画面のgeometry確認に失敗した。操作帯を出した後にテストがexists・hittable・window frame・button frameを順に取得し、3.5秒の自動非表示を超えてからタップしたため、隠れたボタンでなく親surfaceへ届いていた。

`b4ef5fa0a170daf7b8a6e227fb6ce7ee0e744d76`では、同じapp snapshotからwindowとボタンの座標を取り、hittable確認を残して重複照会を除いた。アプリの非表示時間、geometry・時計の判定、試験期限は変えない。以降の再実行の成否は別に記録する。

その後の試験でも、再表示後の照会と画像採取を挟むと実タップが遅れること、AXノードが存在していても操作帯が見えているとは限らないことが判明した。最終ハーネスは既存の20秒以内で`isHittable`による自然な非表示を待ち、映像タップ直後にネイティブのボタン操作を送る。正常再生40秒・全画面15秒・復帰後15秒の既存期限、位置進行・geometryの条件は維持した。[AppleのisHittable仕様](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable)に従い、存在と操作可能性を分けている。

さらに、非同期開始直後の自動非表示予約は、まだエンジンがplayingではないため成立せず、その後も再予約されない実装上の漏れを確認した。`33ecc8f691cbbeb028d57417a5eeb80884c7b65e`で、実際の再生状態更新時に「表示中かつ有効なタイマーがない」場合だけ既存の3.5秒タイマーを予約する。一時停止時は解除して操作帯を表示する。0.5秒の更新ごとに期限を延ばす方式にはしない。長押しスキップ中は非表示と項目再構築を抑止し、両方向の操作終了後に通常の予約と保留復旧へ戻す。通常・全画面共通の処理で、中央ボタンや操作帯の寸法は変更していない。

最終試験では、前後の長押しを各6秒追加した。診断上も両方向で3.5秒を超えて操作が続き、その間は操作帯が表示され、終了後は再生位置が進むことを確認した。画面画像は`XCUIScreen.main.screenshot()`で採取する。以前のアプリ単位の全画面画像には回転・切り取りの不整合があったが、同時刻の録画ではUI全体が収まっていた。最終画像でも確認済み。終了画像のラベルは、tearDown時点で未確定の成否から「failure」と名付けず、後続のテスト専用コミットで「final-state」へ変更した。判定やアプリ本体には影響しない。

## fMP4とTSの区別

ViewerはHEVC要求に`segment_format=fmp4`を付けて認証付きprobeを行い、MAP行がある場合だけAVPlayerを選ぶ。MAPなし・probe失敗は従来のVLCKit 4.0.0a26へ戻る。

公開KonomiTV master [`af98b172eb7a0e9df7683435c706c84bedd9231e`](https://github.com/tsukumijima/KonomiTV/tree/af98b172eb7a0e9df7683435c706c84bedd9231e)では、[Router](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/routers/VideoStreamsRouter.py)にsegment_format引数がなく、[Stream](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/streams/VideoStream.py)はMAPなしのTS playlistを生成する。segment応答はvideo/mp2t、[Encoder](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/streams/VideoEncodingTask.py)もMPEG-TS出力とID3字幕変換である。[公式クライアント](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/client/src/services/player/PlayerController.ts)もこのHLS経路を使う。

公開customizations [`ebeab8abc59dda18151af6d16d72c63a016177b8`](https://github.com/tatsuya0902/konomitv-customizations/tree/ebeab8abc59dda18151af6d16d72c63a016177b8)の38patchと説明文書にもfMP4実装を確認できなかった。「公開パッチを適用すれば利用できる」とは案内しない。実サーバーで使うには、MAP・init・fragment、字幕metadata、同一セッションのTS復帰を提供する追加実装が必要。配布元や適用手順は確認できていない。

[別のfMP4試験](https://github.com/ysnst/konomitv-viewer/actions/runs/45763097175)ではAV経路を選び、initと全fragmentを200で取得したが、通常画面の実時計0秒から進まず失敗した。これはTSのタップ停止と異なる現象で、AVPlayerの開始停止の原因やsimulator固有性は未確定。成功扱いにしない。固定素材は元TSと全デコードフレームが一致し、30区間のDTS連続・先頭キーフレーム・180秒全体デコードを確認済み。[生成方法と検証範囲](../SmokeTests/README.md)を参照。

## 診断と確認範囲

診断は一時的なCI checkoutだけへ適用する。DEBUGかつsimulatorかつ明示起動フラグがある場合に限り、既存更新・状態変更と試験専用の1秒観測（最大120回）から最大800行をアプリDocumentsへ保存し、アプリ終了後、専用simulator削除前にartifactへ取り出す。通常IPAには診断処理を追加しない。記録は単調時計、実再生時刻、状態・意図、AV項目とtimebaseの公開状態、操作イベント、描画ビューの入力状態に限定し、接続先・トークン・番組内容は含めない。実際に取得していない映像・音声PTSは記録しない。

仮サーバー終了・ポート解放・専用simulator削除も各実行で確認する。シミュレーターの映像試験は、実機HEVCハードウェアデコード、音画同期、字幕実画像、PiP、撮影、Cloudflare AccessやLiveContainerでの成功を証明しない。[実機チェックリスト](testing/upstream-next.md)の未確認範囲を維持する。

## 本家の開始監視との接合

保留していた`a2de08583aec2ea66c31ba9605acc84e394c5e15`を、`bb814137b8214cbe67b789289d466e911cda617f`で通常mergeした。Playerの競合は、本家の実進行判定・12秒監視の目的を保ち、フォークの要求・試行・AV項目・字幕世代・PiP所有管理へ接合して解消した。依存関係は変更していない。

一般のplaying通知は既存UIのために維持する一方、fMP4の開始成功は実時計が確定済み基準から2秒を超えて進んだ場合に限る。シーク要求位置や表示専用の先行時刻は使わない。初期位置合わせは完了前の進行確認を止めつつ、12秒の開始待機へ含める。後続シークは最新の完了まで監視を止め、実位置から基準を作り直す。失敗した完了は要求位置を保持し、古い実位置で成功扱いにしない。

監視は単調時計で有効時間を数える。一時停止、scrub、PiP pending/active、所有画面の非表示、アプリ非アクティブ中は消費せず、再開後に残り時間で一つの期限を予約する。bufferingは開始停止の検出対象として数える。成功・取消・項目破棄で期限を失効し、古い要求・試行・項目・タイマー世代は復旧を始めない。開始成功後の通常seekで開始監視へ戻さない。

期限切れは既存の「3秒待って一回retry、それでも失敗すれば同じセッションのTS/VLCへ戻る」処理へ渡す。停止意図、最新シーク先、認証、中継必須条件を保持し、PiP所有中や非表示中の項目置換は保留する。scrub終了後にも保留復旧を再評価する。

別のレビューで、keep-aliveの3回目失敗が開始retryを取り消し、実時計0から新しいセッションを作る競合を確認した。`844258f`で即時・保留の両keep-alive復旧へ共通の許可条件を設けた。keep-alive通信は続け、未確定fMP4・開始解決中・経路解決中の再構築だけを止める。実進行確認またはVLC復帰後は通常のセッション復旧へ戻す。開始前の復旧位置も、保留seek、未確定fMP4の最新指定位置、VLC準備中の開始位置、実時計の順で選ぶ。

状態テストには、進行閾値、停止中の時間除外、buffering、前後・連続・失敗seek、古い完了、ready前の保留seek、重複失敗、PiP/scrub保留、開始監視とkeep-aliveの競合を追加した。独立レビューの必須指摘（旧期待値、失敗seekの誤採用、scrub後の保留解除漏れ、復旧処理の競合）を修正し、再レビューで追加必須指摘なし。実行結果はCI記録で区別する。

本家の更新は開始停止からの復旧であり、AVPlayerが最初に停止する内部原因や、既知のシーク後字幕同期ずれを解消する変更とは扱わない。UIKitの表示・アプリactive/PiP通知の実順序、単一sceneのinactiveとアプリ全体のinactiveの差、実機での開始・seek・PiP・認証はチェックリストで確認する。

## 最終結果と残るfMP4の問題

すべて同じアプリソース`ff3ac274ff96c8e62d8d8e26de87d51e54877014`で実行した。テスト用の観測以外はReleaseと同じソースである。

| 試験 | 結果 | 確認できた範囲 |
| --- | --- | --- |
| [TS/VLC UI](https://github.com/ysnst/konomitv-viewer/actions/runs/45771881750) | 成功 | 通常の実位置進行、全画面往復、自然な非表示後の再表示、前後長押し中の表示維持と終了後の進行。1テスト・失敗0 |
| [fMP4停止からの復旧](https://github.com/ysnst/konomitv-viewer/actions/runs/45771885060) | 成功 | 初回約12.044秒、再試行約12.009秒で停止を検出。約3.115秒待って一度だけAV再試行、異なる2項目の後にVLCへ復帰。同一サーバーセッション、TS/fMP4双方の要求、復帰後のUI・再生継続も検証 |
| [fMP4/AAC・AV経路](https://github.com/ysnst/konomitv-viewer/actions/runs/45771888213) | **失敗** | UI自体は復旧後に通ったが、AV経路が進まずVLCへ戻ったため、経路検証が拒否。AV再生成功とは扱わない |
| [Release・状態テスト](https://github.com/ysnst/konomitv-viewer/actions/runs/45771877714) | 成功 | Python9件、Swift7群、Release、IPA来歴検証。警告86件、0.29比で新規0・解消0 |

映像のみのfMP4とAAC付きのfMP4は、映像packetのSHA-256・PTS・DTS・durationが全5,400枚で一致する。旧ソースを使った[AAC比較](https://github.com/ysnst/konomitv-viewer/actions/runs/45766930770)でも停止したため、音声がないことだけでは説明できない。最終試験でもready、180秒分取得済み、描画可能、errorなしのまま、rate・media timebase rate・実位置は0だった。host clockだけは進んでいる。playing状態通知だけでは成功判定できない具体例である。

AVPlayer内部で進行しない理由、simulator固有かどうかは未特定。fixtureの全体デコード・時刻連続性・HTTP応答に異常は確認していないが、実サーバーとの同等性を証明するものでもない。固定の時刻補正、強制再生、音声クロック指定などの推測による修正は加えなかった。今後は同じ素材の実機AV再生、実対応サーバーのplaylist/init/fragmentとmetadata契約、AVPlayerの公開状態・エラーログを対照する必要がある。字幕・PiP・撮影のfMP4実動作は未確認のままである。

Cloudflare AccessのfMP4経路は既存のAVURLAsset用認証ヘッダーを使う。Digest・クライアント証明書・URLパラメーター認証では既存中継を必須とする。TS/VLCは認証付きの場合に中継を必須とし、中継失敗を無認証直結で回避しない。今回の仮サーバーは実際のCloudflare Accessを再現していないので、この整理はコード確認であり接続成功の報告ではない。

各最終CIで専用サーバーのプロセス群終了、ポート解放、専用simulator削除を確認した。HTTP/CLIテスト7件、actionlint、差分チェック、PillowによるJPEG・EXIF互換照合も成功。独立レビューの必須指摘は修正して再レビュー済みで、未修正の必須指摘はない。AV開始停止は未解決事項として残す。

## 実機確認用IPA

- 0.33 / build 33、ビルド元`ff3ac274ff96c8e62d8d8e26de87d51e54877014`
- [Release Actions](https://github.com/ysnst/konomitv-viewer/actions/runs/45771877714)のArtifact `KonomiTV-Viewer-unsigned-ipa`
- ファイル名：`KonomiTV-Viewer-unsigned-0.33-ff3ac274ff96.ipa`
- SHA-256：`375a02d678345907cb4b8b23b46327e6050b48d5d8fe693ee4efa3c1315d64a6`
- 取得したIPAの内部・外部build-info、Info.plist、Actionsの完全SHA、版・build番号、checksumsを照合済み。Bundle ID・VLCKit・既存設定形式は変更していない。

これは**実機未確認の候補版**であり、fMP4のAV単独再生試験に未解決の失敗を含む。安定版や全試験成功版とは扱わない。段階別の0.30・0.32も別保存し、0.31の中間ビルドは後続修正に置き換えたため取り消した。過去のIPAは上書きしていない。[実機チェックリスト](testing/upstream-next.md)を使い、TS/VLCとfMP4を分けて記録する。mainは0.26のままで、新版の実機確認・了承まで統合しない。
