# フェーズH 調査報告

## 結論

IPA0.20の実機成功16件を記録した。シーク時の字幕残留は実機で解消済みだが、シーク後の字幕同期ずれは別の残存不具合である。今回、実機現象の原因を特定できなかった。安全な時刻変換変更を裏付ける観測もないため、推測による修正、固定補正、Gの取り消し、診断機能追加、新しい通常版/診断版IPA生成は行っていない。

本書はフェーズHの調査結果を公開用にまとめたもの。IPA 0.20 / build 20を実機検証済み基準版として維持し、追加の実機情報が得られるまで同期ずれの修正を保留する。実行コード・依存関係・設定・UI・認証・PiP・キャプチャ保存経路は変更していない。IPAビルド元の完全SHAは `8ed991fd334f56685bf57fc2c80654eb5fa2b4df`。文書確定コミットはIPAのビルド元とは別である。

## 実機記録

[device-0.20.md](testing/device-0.20.md)に全16項目を記録。成功16、失敗0、未確認0。通常字幕、字幕あり→なし/別あり、なし→あり、後方/未知区間、10秒/30秒、連続/停止中/全画面seek、ON/OFF、字幕付き撮影、実況、PiP、UI、接続と保存が成功。写真/両方保存は個別報告がないため別途未確認を維持する。

追加報告は「若干字幕がずれた。再生しなおすと直った」、発生は「シークしたとき」。早い/遅い・秒数・一定/増大・自然回復・頻度・操作種別・移動距離/方向・既知/未知区間・停止/バッファ・全画面/PiPとの関係・G以前からかは不明。

## 調査したローカルソース

- AribCaption.swift: packetの位置変換、segment範囲、更新/flush、caption/superimpose別renderer、clear/有限有効期間。
- CaptionPlaybackTimeline.swift: 受信範囲、シーク世代、要求の直列化。
- PlayerViewController.swift: currentPosition、updateProgress/refreshCaptions、VLC/AVのseek、開始/停止/品質/速度/再起動/全画面/PiPの経路。
- FullscreenPlayerViewController.swift: owner共通seek/時計、字幕ビューの共有。
- StreamRelayServer.swift / TSID3Extractor.swift: EXTINF取得、TSの字幕/先頭映像PTS抜き取り、完了通知。
- VideoCaptureController.swift: 撮影はその時点の字幕層を使い、字幕時計を変更しない。
- LivePlayerViewController.swift: 生放送は別の最初の映像PTS基準/0.25秒更新で、録画のsegment変換とは異なる。今回のHEVC録画の原因へ転用しない。
- scripts/CaptionTimelineTests.swift: 範囲選択/世代/要求管理の検証であり、実映像と字幕の同期を測るテストではない。
- フェーズG差分/履歴、docs/architecture.md、phase-f/g-report、device-0.19、phase-gチェックリスト。

## 確認できた時計の扱い

`currentPosition`は録画VLCならVLCMediaPlayer.time、AVならplayer.currentTimeを返す。lastVLCPositionはstopped時の最終位置保持だけで、再生中の字幕オフセットではない。通常字幕は0.5秒のupdateProgress、segment受信、seek完了から同じcurrentPositionで更新する。要求位置をそのまま描画時計へ代入する処理や、seekごとに積み重なる独自の字幕補正値はない。

Gは明示seekで画像を消し、最新完了後に同じ時計で再構築するよう変更した。PTS変換式と通常0.5秒更新はG以前から同じ。position指定→jump(time)へ変わったが、公式実装上どちらもfast=NOであり高速seekへの変更ではない。要求位置と実際の到達位置が同じとは保証せず、完了後も現在時計を読む。

VLCKit.timeは表示映像のPTSを直接取得するAPIではなく、補間済みのキャッシュ。watchと補間の周期差は更新粒度/ジッタの候補だが、通常再生にもある既存挙動なので今回の持続ずれを説明する確定原因ではない。seek完了はwatchのseek状態解除で、最初の映像/音声フレームが提示された時刻という契約ではない。VLCの状態/不連続通知が時計を止め直す/再開するが、実機のバッファ中にどの値を返したかは未観測。

## PTS変換と本家PWAとの差

Viewerは `ΣEXTINF + wrap補正(字幕PTS − 当該segment先頭videoPTS)/90000` で字幕位置を作る。先頭videoPTSは受信TSで最初に見つけた映像PESのPTSであり、実際の表示フレームPTSでも最初のDTSでもない。videoPTSを得られなければ最初の字幕PTSを代用する。このfallbackでは最初の字幕をsegment先頭へ割り当てるが、発生時に使われた証拠はない。式はG以前から存在する。

本家サーバーは仮想の等間隔segmentとEXTINFを用意する一方、実分割はDTSを優先しランダムアクセスフレームまで待つ。従ってEXTINF累計の先頭と実先頭PTSは必ずしも同一でない。本家PWAはhls.jsで映像と共有する_initPTSを使って調整済みのID3 sample.ptsをaribb24へ渡す。Viewerのsegmentごとの再アンカーとは違う。

ただしnative libVLCもplaylist時間とdemux時間を別管理する。seekはplaylist時間で行い、最初の実DTSとsegment開始を結び付け、以後はDTS差でmedia時計を作る。seek時にはこの対応を再構築する。したがって、PWAに似せて字幕を単純なglobalPTS差へ変更しても、VLC映像の時計へ整合する保証がない。今回の実際のserver版・TS・時計対応がないまま変更すれば同期を悪化させ得る。

## 再生し直すと戻る理由の境界

再生開始は字幕packet/cache・EXTINF/受信範囲・世代・描画状態を初期化し、VLCインスタンス/時計状態も作り直す。seekはGの取得済みデータを保持しつつ表示を無効化し、native側のseek時刻対応を更新する。ここまではソースで確認できる。しかしどの状態が発生時にずれ、どの初期化によって戻ったかは特定できない。再起動で戻ることだけから、残ったオフセットやcache破損を原因と断定しない。

## 原因候補と不足情報

| 候補 | 確認できた事実 | 未確認事項 |
| --- | --- | --- |
| segment別再アンカー | ViewerとPWAの式/基準が異なる | 発生segmentのPTS差とVLC映像時計への実影響 |
| 映像PTS fallback | コードに代用経路がある | 発生時の使用有無 |
| 時計の更新粒度 | VLC補間cache、Viewer0.5秒更新 | ずれ方向/量/持続と相関 |
| 完了後のbuffer | 完了は提示フレーム到達の通知ではない | 完了/映像再開/時計更新の実測順序 |
| Gの変更 | seek完了管理/復元候補選別を変更 | 今回の現象との因果、G以前の有無 |

未取得字幕の欠落、解消済みの旧字幕残留、今回の表示タイミングずれは別問題として扱う。Gの範囲管理を変更したり全編取得で埋めたりしない。

## 診断方法と性能

現在0.20には字幕時刻の診断モード/共有機能がない。アプリ起動・実映像PTS取得・LiveContainer上のログ採取は調査環境では行っていない。まず[phase-h.md](testing/phase-h.md)の条件整理で、方向/秒数/継続性・操作・前後位置・buffer状態を揃える。

内部観測が必要なら別の診断版を検討する。初期OFF、既存イベントだけで採取、512件リング/128KiB出力上限の案、認証/URL/タイトル/字幕本文なし、背景で書式化、共有シートでファイル出力と削除を想定する。現在は未実装で、0.20にその操作があると誤解させない。必要値は要求/完了/再開の単調時刻、VLC報告位置と状態、世代、segment番号/範囲、TS抽出PTS・字幕変換値・fallback有無。提示映像/音声PTSは未取得として扱い、TS先頭PTSや要求位置を代用しない。LiveContainerでの出力/権限/性能は診断版を作った段階で実機検証が必要。

今回はログ追加もないため通常時CPU/メモリ/通信量/保存量に新たなランタイム負荷を加えない。性能の実測はしていない。

## 参照した公式ソース

- [KonomiTV af98b172… VideoStream.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/streams/VideoStream.py): 403〜421、468付近。
- [VideoEncodingTask.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/streams/VideoEncodingTask.py): 429、1208〜1295付近。
- [DPlayer v1.33.4 player.ts](https://github.com/tsukumijima/DPlayer/blob/v1.33.4/src/ts/player.ts): FRAG_PARSING_METADATA。
- [hls.js v1.7.3 mp4-remuxer.ts](https://github.com/video-dev/hls.js/blob/v1.7.3/src/remux/mp4-remuxer.ts): 1247〜1266付近。
- [aribb24.js 99f5e90b… canvas-renderer.ts](https://github.com/monyone/aribb24.js/blob/99f5e90b3bfd899a3f96708f46a617619925dc7a/src/canvas-renderer.ts): seeking/seeked/cuechange、Gで確認した残留抑止を維持。
- [VLCKit 4.0.0-a26 VLCMediaPlayer.m](https://github.com/videolan/vlckit/blob/4.0.0-a26/Sources/Playback/VLCMediaPlayer.m): 166〜188、991〜1011、1368〜1404、1517〜1526、1606〜1609、1761〜1810付近。
- [libVLC f7caf7922 PlaylistManager.cpp](https://github.com/videolan/vlc/blob/f7caf7922/modules/demux/adaptive/PlaylistManager.cpp): 346〜355、816〜875。
- [FakeESOut.cpp](https://github.com/videolan/vlc/blob/f7caf7922/modules/demux/adaptive/plumbing/FakeESOut.cpp): 634〜661。
- [Streams.cpp](https://github.com/videolan/vlc/blob/f7caf7922/modules/demux/adaptive/Streams.cpp): resetForNewPosition/segmentStartTimes。

## 検証・成果物・保全

ローカルで既存Python9件、actionlint、git diff --checkは成功。実行コードは変更していないため、新しいSwiftテスト/Releaseビルド/Actionsを実行せず、新IPAも生成していない。調査環境にiOSビルド環境がなかったため、実機・iOS実行検証は行っていない。既存0.20のSwift/JPEG/EXIF/Pillow/Release成功と警告87件はGの履歴であり、今回の新検証とは扱わない。

IPA 0.20の保存済みファイルはSHA-256を再照合し、`d1eded43b3d3f295d84b1e9dd5a2502eeb17d4df3eb728007e72d0165f24c0f5`と一致した。基準版のビルドは[run45650873099](https://github.com/ysnst/konomitv-viewer/actions/runs/45650873099)。この調査で新しいIPA、バージョン、build番号は作成していない。文書のみの確定に伴うコミットは基準版IPAの完全SHAやバージョンを変更しない。

残るブロッカーは再現時の時刻観測不足であり、字幕同期ずれの解決を宣言しない。明確な原因が得られた段階で小さな修正と実機/自動検証を進める。

## 独立レビュー結果

別担当の読み取りレビューで、文書3件とローカルの時計/PTS変換/seek/G範囲管理の整合性を確認し、修正必須の指摘はなかった。成功16件と同期ずれの別扱い、写真/両方の未確認、診断案の未実装、原因未特定で修正を見送る判断は明確との結果だった。この文書レビューでは外部ソースと実機挙動を再確認しておらず、外部資料の調査は時刻変換/時計を分けた2担当の調査に基づく。実機原因の特定や解決を意味しない。
