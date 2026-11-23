# 字幕の文字化の部品 libaribcaption (1.1.2) を、VLCKit と同じく
# CocoaPods 経由で取り込むための定義。公式の配布物には podspec が
# 無いため、部品のソースをこのフォルダに置き (include/ と src/)、
# ローカルの pod として組み込む。
# iOS では文字の描画に CoreText だけを使う (部品の CMake での
# Apple 向け既定と同じ) ため、他の描画方法のソースは含めていない
# (src/ 側にも置いていない)。設定ヘッダー (aribcc_config.h) は
# CMake の生成結果と同じ内容を include/aribcaption/ に置いてある。
Pod::Spec.new do |s|
  s.name = 'libaribcaption'
  s.version = '1.1.2'
  s.summary = 'ARIB STD-B24 字幕の読み解きと描画 (KonomiTV Viewer の字幕表示用)'
  s.description = '配信に含まれる字幕データ (ARIB STD-B24) を読み解き、' \
                  '文字の画像として描くための部品。Web 版が使う aribb24.js と同じ作者のもの。'
  s.homepage = 'https://github.com/xqq/libaribcaption'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'magicxqq'
  # 必須項目のため部品の出どころを書く。実際の取り込みは Podfile の
  # :path 指定でこのフォルダのソースを使う (この git の指定は使わない)。
  s.source = { :git => 'https://github.com/xqq/libaribcaption.git', :tag => 'v1.1.2' }
  s.ios.deployment_target = '16.0'

  # include/ には C 向け (.h) と C++ 向け (.hpp) の両方のヘッダーが
  # ある。部品のソースは .hpp 側を "aribcaption/..." と書いて参照する
  # ため、.hpp も対象に入れる (.h だけだと .hpp が取り込まれず、
  # ビルド実行43のように「ヘッダーが見つからない」で失敗する)。
  # ただし表に出すヘッダー (public_header_files) は C 向けの .h だけに
  # する。アプリ側は C 向けの口だけを使うためで、C++ のヘッダーを
  # 表に出すと Swift 側の取り込みで読めなくなる。
  s.source_files = 'include/aribcaption/*.h',
                   'include/aribcaption/*.hpp',
                   'src/**/*.{h,hpp,c,cpp}'
  # tinyxml2 は Android 向けのフォント取得でだけ使うため、対象から外す
  # (CMake でも Android のときだけ含まれる)。
  s.exclude_files = 'src/base/tinyxml2.{cpp,h}'
  s.public_header_files = 'include/aribcaption/*.h'

  s.frameworks = 'CoreFoundation', 'CoreGraphics', 'CoreText'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # 部品のソースは "aribcaption/..." と "base/..." のような書き方で
    # 互いを参照するため、include/ と src/ の両方を探し先に入れる。
    # あわせて include/aribcaption/ も入れる。設定ヘッダーを
    # "aribcc_config.h" と接頭辞なしで参照する箇所 (src/ の一部) が
    # あるため。
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/include" "${PODS_TARGET_SRCROOT}/include/aribcaption" "${PODS_TARGET_SRCROOT}/src"',
  }
end
