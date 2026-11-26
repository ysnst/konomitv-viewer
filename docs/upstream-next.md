# IPA 0.26以降の本家更新

## 実機基準版とmain

[0.26の実機結果](testing/device-0.26.md)は主要9項目すべて成功。ビルド元は`60ae8789dc3ec4e97b7a8853582667fcd90a5e98`、SHA-256は`117f9dc806755770fa1f3395001a0c21e779525418d5a17c7266be4df11c638c`。

統合前mainは`a64bdb40004368be248645a02a62e93b1ac7b9fd`、統合後mainは`22c8a5636a8aca1a4c0eda1241f8aef06da57d3a`。0.26のビルド元以降は文書変更だけと確認し、20コミットをfast-forwardで統合した。競合なし、mainへpush済み。デフォルトブランチmain、GitHubトップのREADMEと検証記録リンクを確認した。先頭の文書コミットでCIをskipし、この統合では新IPAを生成していない。

後続更新は`integration/upstream-next`で扱い、新しい実機確認・了承まではmainへ統合しない。0.26の成功を後続版へ流用せず、字幕同期ずれの原因解消とも扱わない。

## 調査した14コミット

取得時の本家mainは`8d333ab3c1f81d69a16c2810a34ec0dae4c0840a`、共通祖先は`3cf89e3fe9f5732a05d06e9d6b823635923ab70c`。mainは本家に対して53 ahead / 14 behind。件数は最新取得時の履歴から数えた。

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

独立レビューで、18秒fixtureが画面遷移中に終了する問題と、存在するが押せない操作帯を再表示しない問題を修正した。素材の再エンコードは行わず、3つの既存HEVC segmentをdiscontinuityで区切って180秒のfixtureにする。番組の尺も合わせる。専用サーバー/シミュレーターだけを終了し、ポート/デバイスの解放を確認するworkflowとした。macos-26-intel/Xcode26.6を使い、既存IPA workflowと版番号生成には触れない。

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
