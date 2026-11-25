# PiP の方式調査

## 版と採用候補

IPA 0.6の実ビルドはMobileVLCKit3.7.5、libaribcaption1.1.2。3.7.5の公開VLCMediaPlayer.hにはPiP/サンプルバッファ出力APIがない。同梱libVLC6de05adcのios.mはCAEAGLLayer/OpenGLESで描画し、バックグラウンドでEAGLを止める。既存UIViewをAVPictureInPictureControllerへ渡すことはできない。

公式 `VLCKit 4.0.0a26`（タグ `4.0.0-a26`）はalpha/unstable配布である。対応libVLCはビルドスクリプトで `f7caf7922` に固定され、VideoToolbox/CVPX→AVSampleBufferDisplayLayerを使い、同じlayerを標準PiPへ渡す。CPUフレームコピーを追加しない方式として、フェーズA保存後に別コミットで検証する。

- [3.7.5公開API](https://github.com/videolan/vlckit/blob/a213fd11/Headers/Public/VLCMediaPlayer.h)
- [3系描画](https://github.com/videolan/vlc/blob/6de05adc/modules/video_output/ios.m)
- [4系podspec](https://github.com/videolan/vlckit/blob/4.0.0-a26/Packaging/podspecs/VLCKit.podspec)
- [4系PiPプロトコル](https://github.com/videolan/vlckit/blob/4.0.0-a26/Headers/Public/Video/VLCDrawable.h)
- [公式iOSサンプル](https://github.com/videolan/vlckit/blob/4.0.0-a26/Examples/iOS/VLCPictureInPicture/VLCPictureInPicture/ViewController.m)
- [標準PiP接続](https://github.com/videolan/vlc/blob/f7caf7922/modules/video_output/apple/VLCPictureInPictureController.m)
- [実際の描画](https://github.com/videolan/vlc/blob/f7caf7922/modules/video_output/apple/VLCSampleBufferDisplay.m)

配布URL: `https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20261109-1916.zip`。podspec SHA256: `1fec7232f88e706f44d9a015133e08d742166eb2666cb44915c9f570bf339463`。

## 移行差分と制約

module名がMobileVLCKit→VLCKit、delegateのstate引数がNotification→enum、positionがFloat→Double、endedが削除される。track APIも変わるがViewerでは直接利用していない。明示stopと終端stopを混同しない世代/所有者判定が必要。既存の中継、認証、字幕エンジンは維持する。

公式PiPプロトコルはreadyブロックと開始/停止Bool通知だけで、isPossible/失敗delegate/UI復帰delegateを公開しない。タイムアウト、所有者の保持、画面遷移中の破棄防止、停止後の復帰はアプリ側で補う必要がある。

AVPlayer経路は既存AVPlayerLayerから標準PiPへ接続可能。ただしこれだけでHEVC対応完了とはしない。

## 字幕・コメント

4系でも映像のdisplayViewとVLCのspuViewは分離される。ViewerのARIB字幕と実況も別UIViewであり、映像layerのみのPiPへ自動では入らない。合成は別描画経路と性能検証が必要。基本HEVC PiPを先に検証し、通常/全画面の表示設定と同期を保持する。

### フェーズEの判断（0.16実機確認後）

ユーザーはHEVC PiPの開始・継続・復帰・履歴同期を確認した一方、字幕・実況がPiPに入らないことを確認した。今回もVLCKit4.0.0a26を維持し、映像出力を変更しない。字幕と実況を個別に調査した結果、どちらも現公開APIだけで既存のPiPバッファへ安全に合成する入口を確認できなかった。

実リビジョンの[VLCSampleBufferDisplay.m](https://github.com/videolan/vlc/blob/f7caf7922/modules/video_output/apple/VLCSampleBufferDisplay.m)では、1182〜1247行がCVPXからCVPixelBufferを取得し、CMSampleBufferとしてdisplayLayerへenqueueする。942〜950行がPiPへ渡すのはこのdisplayLayerだけ。983〜1002行で字幕spuViewを別の兄弟Viewとして作り、1375〜1403行のRenderSubpictureでそこへ描画する。VLC内部字幕へ切り替えるだけでも、PiPに渡る映像へは合成されない。

Viewerの字幕はAribCaption.swiftのUIImageView、実況はJikkyoCommentOverlay.swiftのUILabelとCADisplayLinkによる別View描画である。H.264もAVPlayerLayerの外側にあるこれらのViewはPiPへ入らない。[VLCDrawable.h](https://github.com/videolan/vlckit/blob/4.0.0-a26/Headers/Public/Video/VLCDrawable.h)の公開契約はaddSubview/boundsとPiPの開始・停止・状態通知で、CVPX加工や字幕画像入力を提供しない。[Appleの動画用ContentSource](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class)もAVPlayerLayerまたはAVSampleBufferDisplayLayerを入力とする。通常UIViewを追加するAPIではない。

| 方式 | 判断と理由 |
| --- | --- |
| 既存字幕/実況ViewをPiPへ渡す | 入力バッファに含まれず、公開追加APIなし |
| VLC内部字幕トラックへ切替 | 現出力もspuView分離。ARIB互換性にも影響し解決しない |
| CPUメモリコールバック | HWデコード停止または低速コピー・色変換・CPU字幕合成の制約があるため不採用 |
| GPU出力コールバック | 当該リビジョンのengineはOpenGL/GLES2/D3D/Androidで、Metal/CVPX加工フックではない。標準Apple出力の置換が必要 |
| CVPX→Metal/Core Image→新バッファ | 将来候補。ただしCVPX取得フックがなく、独自出力プラグイン、PTS・色空間/HDR・flush・seek・復帰を実装する大きな変更が必要 |
| snapshotの連続合成 | PTS不明、ファイルI/Oと画像デコード/CPU合成を毎フレーム繰り返すため不採用 |

CPU/GPUコールバックの根拠は実リビジョンの[libvlc_media_player.h](https://github.com/videolan/vlc/blob/f7caf7922/include/vlc/libvlc_media_player.h)958〜971行、1233〜1259行、1377〜1406行。静止画キャプチャから流用できるのは字幕画像や配置比率までで、正確なPTS、連続フレーム供給、背景合成処理は流用できない。

Metalが一律に背景実行不可能とはしない。[通常の背景GPU制約](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)とは別に、[BGContinuedProcessingTask向けGPU entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu)はあるが、端末条件とホストの署名権限が必要で、メディアPiPの権限と同じではない。利用中LiveContainerの版・署名は不明。ゲスト設定だけで利用可能とは判断できず、CADisplayLinkも背景実況更新を保証しない。

字幕・実況のPiP合成は未実装。HEVC基本PiPは0.16でユーザー確認済み、生放送・H.264 PiPは実機未確認のまま既存コードを維持する。出力・依存変更なしのため、新しい合成負荷やHW経路変更は加えない。CPU/GPU・メモリ・発熱・電力の実測値は不明。安全な実装差分がないフェーズEの別IPAは生成せず、フェーズDのIPAと本調査を分けて保存する。

## 不採用方式

- libvlc_video_set_callbacksでメモリ映像出力: [公式API](https://videolan.videolan.me/vlc/master/group__libvlc__media__player.html)がHW無効化または低速コピー/変換・CPU字幕合成の負担を明記。既存HEVC性能維持の要件に合わない。
- 連続スナップショット、画面スクリーンショット動画化: 正規映像出力ではなく同期/画質/負荷に問題。
- HEVC→H.264再エンコード、疑似フローティングウィンドウ、AVPlayerのみ: ユーザー要件を満たさない。

## LiveContainer と実機境界

[公式README](https://github.com/LiveContainer/LiveContainer)ではゲストentitlementsがホストに適用されず、権限がホスト全体へ作用する。ホストの[PiPManager](https://github.com/LiveContainer/LiveContainer/blob/main/LiveContainerSwiftUI/MultitaskSupport/PiPManager.m)はアプリ全体のactive-video-call PiPで、ViewerのメディアPiPとは別機能。ホスト側PiPの成功をViewerの成功根拠にはしない。

Viewerは既にbackground audioとAVAudioSession.playback/moviePlaybackを設定済み。追加entitlementsだけで解決するとはしない。利用中LiveContainer版は不明で、競合/バックグラウンド/復帰は実機確認する。

HWデコード、CPU、電力、発熱、AV同期、IPAサイズ、LiveContainer互換は移行前後の実測が必要。ソース上のHW経路維持と実性能は別の検証結果である。VLCKitはLGPL2.1系で、配布バイナリ同梱ライセンスも確認する。
