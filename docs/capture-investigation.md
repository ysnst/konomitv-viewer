# フェーズFのキャプチャ内容調査

0.17実機結果はサーバー保存成功・内容失敗。具体的症状は未確定であり、字幕欠落、実況欠落、画質低下などと断定しない。元JPEG・期待した時刻・通常/実況付き・生成枚数・字幕保存モード・字幕/実況のON/OFF・通常/全画面・停止/シーク直後かを追加で確認すると切り分けに役立つ。回答や画像を他の改修の開始条件にしない。

## 確認した経路

HEVC/生放送はNativeVideoSnapshotの公開VLC snapshot(width/height=0)、H.264は一時AVPlayerItemVideoOutputを使う。0.16→0.17でフレーム取得や基本の画像合成はほぼ維持され、主な追加はJPEG/EXIF、字幕保存モード、保存先である。

実況Viewだけを控えて、元フレームの画素寸法へ映像・必要な字幕/実況を合成する。画面全体や操作UIは取得しない。アップロードはJPEG Dataをmultipartへそのまま追加し、本家CapturesRouterも受信Dataをそのまま保存する。正常な認証・アップロードを変更する根拠は見つからなかった。

既存のCI合成JPEGはPillowで復号でき、XPCommentも読み取れる。ただしこれは形式の検証で、実機の映像フレームやUIKit合成の成功証明ではない。

## ソースで特定できた仕様差と修正

AribCaption.currentImageは字幕と文字スーパーの合成画像だった。この1枚を字幕としてキャプチャへ渡すと、VideoOnlyで文字スーパーも除かれ、スーパーだけの場合も字幕ありの二枚目やcaptionフラグを作る。

本家は字幕と文字スーパーを別取得し、映像→文字スーパー→字幕→実況の順に描く。Fでは既存画像の読み取り専用getterを追加し、通常表示用currentImageは変更せず撮影入力だけ分けた。字幕保存モードを字幕だけへ適用し、スーパーのみならBothでも1枚・captionフラグfalseとする。映像取得、サーバー保存、認証、JPEG/EXIF、一時出力解放の経路は維持する。

通常のHEVC録画では文字スーパー初期OFFなので、この修正を報告された失敗原因の解決とは扱わない。字幕保存3モード×字幕有無の本番分岐を既存JPEGテストへ追加した。実画素の合成は実機未確認。

## 未確認と残る差異

- VLC snapshotにPTSがなく、押下時に控えた字幕/実況/EXIFと取得フレームには時間差があり得る。撮影のために再生を止めない。
- AV取得は回転メタデータのpreferredTransformを適用していない。合成もcgImageを再生成するため向き付きUIImageへの対応は不足しているが、報告されたHEVC素材が該当する証拠はない。
- 明示的な色空間変換はなくEXIFはsRGB。実画像ICC・色再現は未確認で、色不良とは断定しない。
- 解像度は現在の再生ストリームの画素寸法であり、サーバーの録画ファイル原寸を保証する意味ではない。
- caption_textはnull、カスタム命名マクロは未対応。JPEG品質0.99、日時命名、字幕suffix、XPComment UTF-16LE、番組開始基準の位置は維持する。
- PhotoKit直接保存と両方保存は0.17でも実機未確認。長時間・4K時のメモリ、発熱、電力も未計測。

## 出典

本家の現在参照SHAは `af98b172eb7a0e9df7683435c706c84bedd9231e`。

- [CaptureManager.ts](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/client/src/services/player/managers/CaptureManager.ts): 367〜404行の表示層分離と映像取得。
- [CaptureCompositor.ts](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/client/src/workers/CaptureCompositor.ts): 239〜252/280〜296行の合成順序とフラグ。
- [CapturesRouter.py](https://github.com/tsukumijima/KonomiTV/blob/af98b172eb7a0e9df7683435c706c84bedd9231e/server/app/routers/CapturesRouter.py): 945〜953行の受信データ保存。

## IPA 0.19での追加実機確認

フェーズG開始時のユーザー報告で、0.19のキャプチャ内容とサーバー保存は成功した。写真/両方保存は未確認。過去の失敗症状を推測せず、最新版の確認として[device-0.19.md](testing/device-0.19.md)へ保存した。フェーズGではシーク開始時に表示用と撮影用の字幕/スーパー画像を一緒に無効化し、旧字幕が撮影へ混入しないようにする。保存先/API/JPEG/EXIF自体は変更しない。新版の撮影結果は実機未確認。
