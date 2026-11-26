# 再構築 段階0の基準記録

## 固定した本家と差分

- 本家main：`a2de08583aec2ea66c31ba9605acc84e394c5e15`
- ブランチ：`codex/rebuild-stage0`（既存フォーク内。mainへ未統合）
- IPAのビルド元：`684c880e9b0012b8d48aace3a20bed3a84be9989`
- 本家/ビルド元の `KonomiTV-Viewer` 全tree：双方 `7cda8e18229f4158adc18365f9012dddab977c09`
- アプリ、project、Podfile、Vendor、UITest、SmokeTestsの素材は本家と同一。差分はCI3ファイル、成果物検証script2ファイル、gitignoreと今回の文書だけ。
- CHANGELOGは本家0.92、project既定は0.1/build1。取得IPAはフォークのCI採番による0.34/build34で、同じ意味の番号ではない。

ビルド時のGit比較とローカルのtree照合で一致を確認した。検証script単独が確認するのは内外来歴の自己整合で、Git比較とは区別する。版/build・来歴ファイルとInfo.plistの来歴キーはpackaging時だけ追加した。アプリ機能の変更ではない。

ユーザーが実機成功した本家IPAの正確な版・SHAは不明。この固定SHAとの同一性は確認できないため、基準IPAを実機確認用に生成した。実機の生放送成功や旧フォークの不具合解消は、まだ主張しない。

## 再生・認証・依存

生放送はMPEG-TSの連続配信をMobileVLCKitで再生する。録画の通常経路はAVPlayer、HEVCは認証付きplaylistでfMP4対応を確認してAVPlayerへ、非対応時はVLCへ戻る。fMP4開始前の実進行・12秒監視・3秒後の1回再試行・VLC復帰は本家実装のまま。

PiPはAVPlayerLayer経路。本家にはVLCのPiPはなく、VLCKit4と独自PiPはまだ接合していない。CFサービスToken、その他の認証、非同期中継・開始、同じ画面での全画面表示は本家既存を使用する。

CocoaPodsは宣言を変更せず解決し、Release/UI双方でMobileVLCKit **3.7.5**、libaribcaption **1.1.2**、CocoaPods **1.17.0**だった。原本にはPodfile.lockがないため、今回のlockをArtifactへ保存した。今後は依存解決差分も段階の比較に含める。

## 検証結果

| 項目 | 結果・範囲 |
| --- | --- |
| [Release](https://github.com/ysnst/konomitv-viewer/actions/runs/45787058230) | 成功。macos-26-intel、Xcode26.6/17F113、Release iphoneos、未署名 |
| 警告 | **86件**。本家基準の今回ログから集計した新しい比較基準。旧フォークの86件と同一内容という意味ではない。後続段階の新規警告をこのログと比較する |
| 成果物検証Python | 既存9＋段階0来歴3＝12件成功。改変IPA・来歴・版・SHA・上流情報の不一致を拒否 |
| [本家UIスモーク](https://github.com/ysnst/konomitv-viewer/actions/runs/45787063216) | 1件成功・失敗0、30.175秒。macos-latest、Xcode26.6。上流の試験と素材を変更せず実行 |
| UIが判定した範囲 | 録画一覧からの開始、時刻表示が0:00以外になること、全画面往復、字幕/実況overlayの存在。本家の判定を強化・緩和していない |
| UIの未検証範囲 | 生放送、連続番組/局切り替え、実認証、AV単独、PiP、字幕の実画像/同期・音声・長時間の実機性能。全画面中と復帰後の時計増加を個別にassertする試験でもない |
| 画像確認 | 通常・全画面の本家UI画像を確認。既存の大型ヘッダー/操作UI・ステータスバー表示も基準のまま。指定5ボタン等は後続段階 |
| CI後片付け | 専用stubのプロセス群終了、18080の解放、専用simulator削除を確認 |
| actionlint / diff | 成功 |
| 旧Swift7群・HTTP7件 | 段階0の本家には対応する独自状態モデル/テストがないため未実施。採用段階で必要なものを接合する。テストのためだけにアプリへモデルを追加しない |
| JPEG/EXIF/Pillow | 独自キャプチャは対象外のため、新構築の必須検証として実施しない |
| 独立レビュー | CI・公開操作の除去・来歴境界・文書を別担当で確認。必須文書指摘を修正済み。アプリtreeのGit実行は主担当とCIで確認し、子レビューでは権限制約により実行できなかった |
| 実機 | **未確認**。[チェックリスト](../testing/rebuild-stage0.md)に結果を記録する |

## 基準IPA

- 段階：0（本家アプリ機能無変更）
- 版：**0.34 / build 34**
- [Actions](https://github.com/ysnst/konomitv-viewer/actions/runs/45787058230)のArtifact `KonomiTV-Viewer-unsigned-ipa`から取得
- 名前：`KonomiTV-Viewer-unsigned-0.34-684c880e9b00.ipa`
- SHA-256：`0efdfa508f05cb208776d78be213859c78945094de6a53e05bf75c7e480afa6e`
- ビルド元：`684c880e9b0012b8d48aace3a20bed3a84be9989`
- IPA内外JSON、Info.plist、チェックサム、版/build、ActionsのSHA、上流SHA・treeの一致を照合済み。mainアプリの署名なしも確認。

Bundle IDは既存と同じ `jp.tatsuya0902.konomitv.viewer`。Keychain serviceも同じで、CF・接続先・同期の既存キーを使用する。保存データの削除・初期化・移行コードは追加していない。ただしLiveContainerの実際の更新方法によるcontainer保持は未確認であり、同じIDだけで保持を保証しない。

## 保全・次の工程

旧作業ディレクトリの開始時336ファイル、22本のIPAのhash、HEAD、main、ローカルref、既存の未コミット状態を照合して不変を確認した。旧mainの `12b75d7992909c0ad9aed91faaed5753c9548a09` とintegration/upstream-nextを維持する。タグ・リリース・既存履歴は変更していない。

[機能比較](feature-matrix.md)は本家実装、独自差分、対象外、新規、既知問題に分けた。[段階別計画](plan.md)は0〜4を独立IPA・実機ゲートで分離する。[オフライン調査](offline-research.md)では原ファイル取得を推奨するが、実装・実サーバー変更は行っていない。

**ここで実機結果を待つ。** 基準IPAで生放送と連続切り替えを確認した後、段階1の本家認証の検証へ進む。新たな本家更新があっても基準SHAを自動更新しない。今回の成功は、旧フォークの停止問題・字幕同期ずれ・fMP4実機互換性の原因解消を意味しない。

