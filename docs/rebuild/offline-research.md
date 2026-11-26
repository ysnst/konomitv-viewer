# 0.26開発への引継ぎ

方式Aの基本承認を維持。現在は段階Aの修正/実機ゲート前で、offline未実装。以下は0.34案で調べた固定サーバー版/API/Apple/LiveContainerの調査を引き継いだもの。旧資料自体は変更しない。VLC4既存PiPと履歴モデルへ接合を再評価し、VLC3前提・独自PiP禁止の記述を本開発へ適用しない。ローカルPiPはVLC4/AVの双方が候補だが未検証。サーバー追加改造は禁止。

標準download、Range/validator、大容量CF転送、原本形式/ARIB PES、ローカル字幕/実況、outbox競合、LiveContainer背景/更新保持の実環境確認は残る。現在利用するサーバー版・非公開接続先・原本情報が未提供なので、ソース調査を実環境成功と扱わない。[現行計画](../development-0.26.md)を優先する。

## 0.34案での技術調査（当時の方式比較を保持）

# オフライン保存・再生の技術調査

**方式Aはユーザーの基本承認済み。保存機能は未実装、サーバー追加改造は行わない。** 標準APIによる原ファイル取得で進め、再エンコードを必須にしない。利用中Docker/NASのKonomiTV版・変更点、Amatsukaze出力のコンテナ・字幕/音声の保持状態は未照合である。

## 固定した調査対象

- KonomiTV master：`af98b172eb7a0e9df7683435c706c84bedd9231e`、0.15.0-dev。
- 最新公開版として調べたv0.14.1：`0a32188274b81c1e7bed642474b208bd2a543a6b`。開発版だけのAPIを正式版に存在すると扱わない。
- Viewer基準：`a2de08583aec2ea66c31ba9605acc84e394c5e15`。
- LiveContainer公開ソース：`b0f53e8934df325970e9b6ff52932a43b585c424`。ユーザーが利用する版・署名・実行モードとの一致は不明。

## 標準APIで取得できるもの

| API | 確認した契約と制約 |
| --- | --- |
| GET /api/videos/{id}/download | master・v0.14.1双方に存在。登録された録画原ファイルをFileResponseで返す。NASの任意パスを指定するAPIではない。masterは録画中422・消失404。正式版には同じ録画中ガードがなく、クライアントでも取得対象を完了済み録画に制限する必要がある |
| GET /api/videos/{id} | 番組・録画情報の保存に使用。サーバーから後で削除されてもローカルのメタデータを保持する |
| GET /api/videos/{id}/thumbnail、thumbnail/tiled、局logo | 代表画像・必要ならプレビューの付随保存。失敗は動画の完全性と別管理 |
| GET /api/videos/{id}/jikkyo | 過去ログコメントの時刻付きデータを別JSONとして保存する候補。取得不可/失敗を「コメントなし取得成功」と混同しない |
| GET /api/streams/video/{id}/{quality}/offline-stream | 調べたmasterに存在、v0.14.1にはない。KTVODLP独自形式のJSONメタデータ＋長さ付きTS区間＋終端件数。先頭からエンコードし、内部keep-alive・同時実行制限・切断cleanupあり。Range再開ではない |
| 通常HLS playlist/segment | masterもMPEG-TS出力。MAP/fMP4出力は確認できない。playlistだけ保存してもオフライン再生にはならない |

原ファイルの実装：[master VideosRouter.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/routers/VideosRouter.py#L798)、[v0.14.1](https://github.com/tsukumijima/KonomiTV/blob/0a32188274b81c1e7bed642474b208bd2a543a6b/server/app/routers/VideosRouter.py)。オフライン配信：[VideoStreamsRouter.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/routers/VideoStreamsRouter.py#L317)。付随保存の参考：[公式OfflineVideos.ts](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/client/src/services/OfflineVideos.ts#L279)。

調べた両版のdownload API自体にはKonomiTVログイン/Bearer/管理者権限の要求はないが、Cloudflare Access等の外側認証とカスタム版の認可は別である。既存の正規認証経路を使い、外側認証を回避しない。ファイル名は原本basenameのままで、Content-DispositionはUTF-8名にも対応する。拡張子を.tsへ固定しない。

### Range・識別・完全性

調査版の依存Starlette（v0.14.1は0.46.2、masterは1.10.0）のFileResponseはAccept-Ranges、Content-Length、Last-Modified、ETag、Rangeの206/416とIf-Rangeを実装する。[0.46.2の実装](https://github.com/Kludex/starlette/blob/0.46.2/starlette/responses.py#L289)、[1.10.0](https://github.com/Kludex/starlette/blob/1.10.0/starlette/responses.py#L300)。

ただしdownloadルートはGET定義で、HEAD成功は保証されない。利用サーバーとCloudflare Accessを通して、認証付きGET Range: bytes=0-0の206・Content-Range・validatorを確認する。プロキシやカスタム版の挙動を標準ソースだけで保証しない。大容量転送の持続性・帯域・サービスToken期限も実環境では未確認。

ETagはmtimeとsize由来で、原ファイル全体の内容hashではない。再開では強いvalidatorと元の全長を控え、Range＋If-Rangeを使う。206の開始offset/全長を検査し、200へ戻った応答をpartialへ追記しない。416を無条件に完了としない。識別が変わった場合は別原本として安全に最初から取得する。録画中や差替え中のファイルは取得しない。

完了後のローカルSHA-256は、保存後の破損検知には使えるが、サーバーが内容hashを返さない限り原本との暗号学的な同一性を証明しない。全長・HTTP終端・ローカルhash・実際のコンテナ読み取りを別々に記録する。

## 方式A〜Eの比較

| 方式 | 互換性・改造 | 負荷/容量/画質 | 音声・字幕・実況 | 再開・認証・PiP・保守 |
| --- | --- | --- | --- | --- |
| A 原ファイル | 調査した正式版/開発版に標準APIあり。原則サーバー改造不要 | サーバーは原本読み出し。再encodeのCPU/GPU負荷なし。NAS/I/O・通信量は原本サイズ。画質は維持 | 原本に入った音声/字幕はバイトとして保持。別ファイルや削除済み字幕は取得できない。実況は別JSON | Range/validatorを実測。認証付き原URLを使用。MobileVLCKit 3.7.5のローカル再生とAVPlayer/PiPを別検証。第一候補 |
| B HLS保存 | 通常API利用だがsession/keep-aliveと全segmentの管理が必要 | 原本保存とは異なりオンデマンドencodeが発生し得る。容量は選択品質、画質変化あり | HLSのtimed ID3字幕を保存できる候補。副音声等は出力設定依存。実況別保存 | segment単位再取得可能だがsession失効/再生成の同一性が課題。AV offline APIは対応HLSに限り、TS-VLC用HLSにそのまま使える保証なし |
| C 無劣化remux | 原本取得後にローカルでstream copyする案。公開APIだけで全入力形式に対応する汎用変換器は別途選定が必要 | 再encodeなし。ただし一時容量・I/O・電力が必要。追加依存のサイズ/ライセンスも評価 | 音声やARIB字幕が出力コンテナへ収まらない場合がある。MP4化だけで字幕維持とはしない | Apple互換性改善の可能性はあるが、原本/変換物の二重管理。初期必須にしない |
| D 最小サーバー追加 | 対象版で標準API不足や契約不足が判明した場合だけ | 単純なFileResponseならencode不要。変換を含めれば負荷増 | 原本・sidecarの明示契約が必要 | 認可・path traversal防止・Range・帯域/同時数・監査が必要。今回は対象外で、追加改造しない |
| E 再encode保存 | masterのoffline-streamまたは通常encodeを利用。正式版には前者なし | CPU/GPU・電力・待ち時間増、サイズ調整可能、非可逆変化 | 出力字幕/音声設定を別検証。実況別保存 | KTVODLPはRange再開ではない。原本が再生できない場合の任意代替候補で、必須にしない |

オンラインfMP4経路を保存の前提にしない。本家のネットワークAV時計停止の調査ecc50a8とフォークの失敗は同一原因か不明であり、ローカルMP4へその結論を流用しない。

## 字幕・文字スーパー・実況

本家ViewerのTSID3Extractorは、HLS向けに変換されたID3 PRIV字幕を取り出す。サーバーの[VideoEncodingTask.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/streams/VideoEncodingTask.py#L826)もこの変換を行う。原放送TSのARIB PESを既存HLS入力へ渡すだけで正しく表示できるとは確認できていない。コンテナに字幕が残ることと、字幕表示・シーク時の状態復元が可能なことを区別する。

原本の形式・音声トラック・字幕/スーパーの有無をまず調べる。VLCの内部字幕を利用する案と、ローカルTSからARIBデータ・PTSを抽出して既存描画へ渡す案を比較する。必要なら位置索引を逐次構築するが、動画全体をメモリへ読み込まない。Amatsukaze出力が字幕を除去している、または外部sidecarだけの場合、標準download APIから自動で復元できるとは案内しない。

実況JSON、コメント密度用データ、番組情報、画像は動画と別ファイルで保存する。再生位置をローカル時計へ同期し、offline中にサーバーへコメント再取得しない。PiP内字幕/実況は今回必須外であり、通常画面・全画面の表示と分ける。

## iOSとLiveContainer

- MobileVLCKit 3.7.5の[ローカルpath/URL入力](https://github.com/videolan/vlckit/blob/a213fd113c5c014556b40765966e77d439f0ddf9/Headers/Public/VLCMedia.h)、AVPlayerの[AVURLAsset](https://developer.apple.com/documentation/avfoundation/avurlasset)が候補。HEVCというcodec名だけで全コンテナの再生可否を決めず、isPlayableと実再生・音声・seekを確認する。
- ローカルPiPは既存AVPlayerLayerで実現できるか検証する。VLC3には独自PiPを追加せず、ローカルPiPだけのためにVLC4へ更新しない。対応できない原本形式は制約として報告する。[Appleのメディア再生設定](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)に従い、背景音声・所有者寿命・復帰を検証する。ローカル原本でのPiP成功は未確認。
- [背景URLSession](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)は通常の署名アプリで別process転送・OS終了後の再接続を扱える。一方、[ユーザーによる強制終了](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))では取消しとなり、自動再起動しない。
- LiveContainerの[GuestHooks](https://github.com/LiveContainer/LiveContainer/blob/b0f53e8934df325970e9b6ff52932a43b585c424/LiveContainer/Tweaks/NSURLSessionConfiguration%2BGuestHooks.m)にはLiveProcessの背景download対策としてsharedContainerIdentifierをhostのapp groupへ補正する処理がある。「LCでは不可能」とは断定しない。ただし[guest entitlementの制約](https://github.com/LiveContainer/LiveContainer/blob/b0f53e8934df325970e9b6ff52932a43b585c424/README.md#limitations)、HOME/Bundle補正があり、host再起動・別guest中のdelegate配送・container移動の保証は未確認。
- background転送にguest内の127.0.0.1 relayを使わない。guest停止でrelayも止まるため、正規のorigin HTTPSへ認証付きdownloadTaskを使う案を優先する。背景sessionではredirect callbackの制約があり、foregroundの認証・転送先検査をそのまま保証できない。転送先契約を確認できない場合はforeground方式から始める。
- [resumeData](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask/cancel(byproducingresumedata:))は常に得られるとは限らない。opaqueとして保持し、失効時は検証して再取得する。独自に内部内容を書き換えない。

背景転送の確実な継続、アプリ終了後の完了通知、更新後のcontainer保持は実機検証の課題である。まず前景中の安全な中断/再開を成立させ、背景機能を別の確認項目にする。

## 保存・認証・容量の設計案（未実装）

Application Supportの専用領域へmanifest、partial、完成動画、画像、コメントを分ける。一度に取得する本数を制限し、重複をserver/account・番組ID・原本識別情報で防ぐ。保存先はUUID等で構成し、サーバーの絶対pathや認証付きURLをmanifest/ログへ残さない。接続情報はKeychain等の既存管理を参照する。

downloadTaskまたは逐次ファイル書込みを使い、Dataで原本全体を取得しない。完成検証→同一volume内移動→manifest更新を回復可能な状態遷移として設計する。削除はアプリのローカル保存領域だけを対象にし、サーバーDELETE APIを呼ばない。

再取得可能な大容量動画は[バックアップ除外](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)にする。[ファイル保護](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)とロック中アクセスの要件を両立させる。容量事前確認後のENOSPCも処理し、既存完成ファイルを巻き込まない。容量API採用時は[required-reason宣言](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey)も確認する。

総長が取れなければ進捗率・残り時間は不明表示にする。速度と残り時間は推定であることを区別する。Wi-Fi専用を既定候補にし、モバイル利用は明示設定で制御する。local再生失敗から無断でモバイルstreamingを始めない。

## 履歴同期の設計案（未実装）

サーバーのwatched_historyにはvideo_id、last_playback_position、created_at、updated_at（Unix秒）がある。[SettingsRouter](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/routers/SettingsRouter.py#L35)のPUTはlast_synced_atが古いと422だが、設定全体の置換であり原子的CAS/If-Match/revisionはない。同時更新や同値timestampで競合が残る。

offline outboxにはaccount/server、操作ID、ローカル位置、同期前に読んだ履歴値、ローカル変更順序を保存する。復帰時は最新GETを行い、サーバー側の対象履歴が基準値から変わっていなければ既存保存queueで対象だけを反映する。古い設定全体の再送や位置max統合をしない。端末時計が正しい保証もないため、日時の大小だけで競合解消しない。

別端末更新、履歴削除/リセットと競合した場合は自動上書きを保留し、利用者が採用する位置を選べる方式を推奨する。確認後の同時書込みまで完全に防ぐ保証は現APIだけではないことを明示する。番組404ならローカル履歴を保持してそのIDの自動同期を止め、無限retryやローカル動画の自動削除をしない。

## 実装前の確認・了承事項

1. 利用サーバーの版とdownload/Range/validator、ファイル変更時の挙動、Token・大容量転送条件を照合する。個人の接続先や認証情報を公開資料へ出さない。
2. 方式Aの基本承認は取得済み。原本の音声/字幕形式、必要容量、API契約を確認する。サーバー側の追加改造は禁止し、標準APIで実現できない部分は理由・制約・代替案を提示して判断を待つ。
3. online基盤の実機確認後、前景転送→ローカル再生→字幕/実況/PiP→背景/履歴の順で試す。機内モード、強制終了、再起動、破損、200/206/416、容量不足、認証切れを試験する。
4. 履歴競合時の利用者選択、account切替時の保存一覧分離・保持/削除方針を確定する。ローカル削除とサーバー録画削除を明確に分ける。

方式Aの基本承認により、オンライン基盤の実機ゲート後は実装へ進める。ただし現在は段階1/2の残存条件確認中で、オフライン本実装へは進んでいない。対象サーバーへのアクセス試験、アプリ保存・再生、背景転送、オフライン字幕/実況/PiP、履歴競合の実装は未実施。

