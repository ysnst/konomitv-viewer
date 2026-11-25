# 本家更新の取り込み（フェーズI・J）

## mainの検証済み改修統合

統合前mainは `52c9468db032ea7252fe6f13cbeb70da268de8fb`。作業ブランチ `fix/fullscreen-comments-ci` の基準 `565e6e3ee03aaf621afe38e361a9e92937368c8a` へ追加実機報告の文書コミットを加え、40コミットをfast-forwardでmainへ統合した。競合なし、アプリ機能は変更していない。統合後main（本家取り込み前の切り戻し基準）は `a64bdb40004368be248645a02a62e93b1ac7b9fd`。作業ブランチは削除していない。

0.20の16項目成功を残し、後から分かった実況コメント付きキャプチャの正常動作しない問題を追加記録した。原因/条件は不明。字幕同期ずれも別件として保留する。両件は過去の成功結果を遡って書き換えるものではない。

mainをdefault branchとしてREADME/実装/検証文書を公開した。文書コミットのskip指定でこの工程の新IPA生成を抑止。実機検証済み基準版は0.20/build20、ビルド元 `8ed991fd334f56685bf57fc2c80654eb5fa2b4df` のまま。

## 未取り込み7コミットの監査

作業開始時の本家mainは `3cf89e3fe9f5732a05d06e9d6b823635923ab70c`。共通祖先は上記52c9468。フォークは本家に対して作業開始時39 ahead / 7 behind、フェーズIの追加記録後は40 ahead / 7 behind。

安全な最初2コミットを `integration/upstream-sync` へ通常mergeし、元の履歴を維持する。残り5件は保留。全7件の取り込みには全画面方式の大規模移植が必要であり、ユーザーの確認なしに実施しない。behindの数字を消すために検証済み機能を置き換えない。

### 94f9a31eeedac25e81fabb370d2314a1ee5aac3e

- 日時（UTC）: 2026-11-25T10:13:23Z
- 内容: カードの三点メニューと録画ファイル情報画面を追加
- 判断: 取り込み。一覧/モデル/新情報画面/project/変更履歴。30件ページ送り、進捗、ホーム、行高測定を保持。新規API取得なし。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer.xcodeproj/project.pbxproj`、`KonomiTV-Viewer/KonomiTV-Viewer/Models.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/MylistViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/RecordedFileInfoViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/VideoListViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/WatchedHistoryViewController.swift`

### ed073d62a145da865f6f7728dcf222e02f6100fb

- 日時（UTC）: 2026-11-25T10:21:37Z
- 内容: 録画ファイル情報の見出しアイコン比率を固定
- 判断: 取り込み。情報画面の20×20ptアイコン固定。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer/RecordedFileInfoViewController.swift`

### 5c890dd338d1c3c6b426311f19584c8831ae28cd

- 日時（UTC）: 2026-11-25T14:07:57Z
- 内容: 全画面の実況コメント借用・返却を修正
- 判断: 保留。フォークで実装・実機確認済みの処理と重複。通常mergeでは後続の再設計とまとめて慎重な調整が必要。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer/FullscreenPlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift`

### 3d9bba2cee02ea283ecbb299f32bc065567d40fd

- 日時（UTC）: 2026-11-25T14:20:22Z
- 内容: 中継準備の非同期化、再生開始意図/AV待機方式の変更
- 判断: 保留。認証/品質変更/PiPの開始状態へ広く影響。現行方式へ単純に上書きしない。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer/APIClient.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/LivePlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/StreamRelayServer.swift`

### 84011e97d19260e963e8ad0d9a9f2fd5b81987f7

- 日時（UTC）: 2026-11-25T14:47:30Z
- 内容: keepAlive監視・再接続、開始前seek、背景stop、付替時期とキャッシュ量変更
- 判断: 保留。Gのseek直列化/世代/停止/復帰と個別調整が必要。録画キャッシュ30→10秒を無検証適用しない。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer/APIClient.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/FullscreenPlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/LivePlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift`

### af52d1983352bc6d22cf4bc56d7f51e374c8f9ad

- 日時（UTC）: 2026-11-25T17:30:02Z
- 内容: シーク後の時刻とバー表示を要求位置へ先行追従
- 判断: 保留。表示専用値と実時計の分離が必要。字幕同期ずれの修正ではない。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer/FullscreenPlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift`

### 3cf89e3fe9f5732a05d06e9d6b823635923ab70c

- 日時（UTC）: 2026-11-25T20:54:28Z
- 内容: 全画面を別VCから同一VCの状態へ置換
- 判断: 保留。Fullscreen削除とPlayer/Live大幅変更。PiP復帰/設定/借用ビューの大規模移植が必要なため独断取り込み不可。
- 変更ファイル: `CHANGELOG.md`、`KonomiTV-Viewer/KonomiTV-Viewer.xcodeproj/project.pbxproj`、`KonomiTV-Viewer/KonomiTV-Viewer/FullscreenPlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/LivePlayerViewController.swift`、`KonomiTV-Viewer/KonomiTV-Viewer/PlayerViewController.swift`

## 統合判断と影響

7件とも依存関係・Actions設定・新規テスト・サーバーAPIエンドポイントの変更はない。明示的なセキュリティ脆弱性修正は確認していない。後続の内部APIではplayerAsset/relayURL/keepAliveの返却/完了方式が変わるが、今回は取り込まない。字幕PTS変換やAribCaption/Gタイムラインの修正はなく、今回の統合で字幕同期ずれが解消したとは扱わない。

最初2件のmerge競合はVideoCell内の2箇所。フォークのホーム罫線/カード上余白と本家の本文幅制約を両立し、確定行高測定と三点メニュー関数を両方保持した。実セルのメニューあり本文幅（右40pt）を測定セルにも反映し、折り返しの差がスクロール保持を壊さないようにした。選択中はメニューなし（右9pt）、ホーム/ゴミ箱の既存表示も維持する。新モデル値はOptionalで、一覧取得済みデータを表示する。

## 新版の扱い

本家2件の取り込みと実況コメント付きキャプチャ削除は別コミットとする。通常/字幕付き撮影、保存先・認証・JPEG/EXIF・PWA同期、実況の描画/一覧/検索/密度/透過率は維持する。6ボタン構成は通常撮影→実況→字幕→設定→PiP→全画面。詳しい実機確認項目は[phase-j.md](testing/phase-j.md)を参照。

新版はユーザーの実機確認と了承まで専用ブランチに保持し、mainへ統合しない。残り5件を再開する場合も、再設計方針と影響を確認してから別工程として進める。
