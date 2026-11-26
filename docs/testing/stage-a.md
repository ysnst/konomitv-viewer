# 0.26開発・段階Aの次版実機チェック

候補は **0.36 / build 36**。ビルド元 `eef1a0793ecc53247b30fc86993df20ef3b0660e`、SHA-256 `ad723d6315a5a18a72be4ec2d99ef505925ac731393b0fc8361d98ef24e41cb8`。

[Release成功](https://github.com/ysnst/konomitv-viewer/actions/runs/45813722359)、[UI/relay成功](https://github.com/ysnst/konomitv-viewer/actions/runs/45817268258)。UI3件/失敗0、通常/全画面live tap、録画の上部tap・track tap・drag・領域外終了・全画面seekと復帰・直接cancel契約を確認。遅着spriteも非表示。UI試験harnessは別コミットだがアプリ本体はIPA元と同一。実OSによるtouchCancelやPiPの実機成功を意味しない。

Release警告87件・新規0。既存Swift6群、Python9件、合成HTTP fixture2件、実relay HTTP契約、JPEG/EXIF・Pillow、actionlint/diffが成功。0.35は途中案がnative seek試験で不十分だったため不採用で、既存成果物として保存した。**全項目は新版として実機未確認**。0.26の31件を新版へ転記しない。0.26の既存IPA・LiveContainer containerを削除せず、既存データ保持も別に確認する。

- [ ] 生放送を開始し映像/音声を確認。映像tapで操作帯だけ切り替わり再生継続。
- [ ] 通常/全画面で複数回tap、操作帯の自動非表示/再表示、一時停止/再開。
- [ ] 連続局切替と切替後の継続、録画↔live、読込中退出→別番組、短時間切替。
- [ ] HEVC録画の通常/全画面tapで意図せず停止しない。長押し/前後skipを維持。
- [ ] seekのthumb/track/操作領域上部を短tap。preview/密度は終了時に消える。
- [ ] drag中は表示、指離し/領域外/取消で消え、後から復活しない。
- [ ] 連続/停止中/全画面seek、操作中の退出/回転/PiP。停止意図は勝手に再開しない。
- [ ] 未取得/取得済み区間の字幕・文字スーパー・実況、字幕残留が再発しない。
- [ ] 過去の字幕同期ずれが出た場合は早い/遅い・概算秒・前後位置・tap/drag/skip・継続後・通常/全画面・停止/再生を記録。再現なしは原因解消としない。
- [ ] HEVC PiPの開始/背景継続/復帰、PiP復帰後別番組、視聴位置同期。
- [ ] 撮影を含む6ボタンの順序、通常/全画面の設定panel、下部tab、中央操作、BML/remote。
- [ ] 通常/字幕付きcapture、server保存。写真/両方は実施した場合だけ成功にする。UI/実況混入なし、設定/権限/保存方式維持。
- [ ] ホーム10/4/4・進捗・30秒位置保持・もっと見る・履歴入力・9pager・scroll ON/OFF。
- [ ] **未確認だった復帰**：もっと見る→5page→途中scroll→別tab→戻る→録画再生→一覧復帰。同page/位置/検索/絞込/並び順を確認。
- [ ] PWAとの双方向履歴、Cloudflare Access、再起動後の認証/設定、既存container内データ保持。
- [ ] repeat/restart、利用している番組操作・予約/拡張機能を維持。

成功/失敗/未確認/対象外と操作順・エラー文言を記録する。秘密URL/tokenを共有しない。simulatorの合成HTTPやVLC clock成功は実機/実CF/PiP成功とは別。OSの実touchCancel、回転/背景/PiPの組合せは自動試験で未確認の範囲が残る。**段階Aの実機完了まで段階B以降を重ねない。**
