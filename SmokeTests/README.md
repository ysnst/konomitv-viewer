# シミュレーター用の固定素材

`media/index.m3u8`と30個のTSは、180秒・640×360・30fps・HEVC・映像のみの固定素材です。実ユーザーの録画や接続情報を含みません。アプリのIPAには同梱せず、仮サーバーだけが読みます。

FFmpeg 9.0.2のtestsrc2から新規生成したテストパターンです。短いTSを反復する方式は時刻が巻き戻り、単純なstream copyによる接続にもHEVC参照フレーム欠落があったため採用していません。固定間隔の閉じたGOPで生成し、出力TSのDTSが先頭から末尾まで連続することを確認しました。実際の録画番組の変換処理ではなく、アプリにエンコード処理を追加するものでもありません。CIでのFFmpeg追加インストールは不要です。

再生成する場合は出力先を作業用ディレクトリにします。

```text
ffmpeg -f lavfi -i "testsrc2=size=640x360:rate=30:duration=180" -map 0:v:0 -an -c:v libx265 -preset ultrafast -crf 35 -pix_fmt yuv420p -x265-params "keyint=180:min-keyint=180:scenecut=0:open-gop=0:pools=2:frame-threads=2:log-level=error" -f hls -hls_time 6 -hls_playlist_type vod -hls_flags independent_segments -hls_segment_filename "output/seg%d.ts" output/index.m3u8
```

生成後は全30個の先頭キーフレーム、30fpsでのDTS連続性、playlist全体のデコードをffprobe/ffmpegで確認してから置き換えます。HTTP契約テストは、実際の各TS・分割尺・別々のデータ・TS同期バイト・範囲外要求の404と、専用サーバー終了後のポート再利用を確認します。

この素材はTS/VLCの試験用です。fMP4/emsg、字幕の実描画、実際の音声同期、PiP、LiveContainerや端末性能の確認には使えません。
