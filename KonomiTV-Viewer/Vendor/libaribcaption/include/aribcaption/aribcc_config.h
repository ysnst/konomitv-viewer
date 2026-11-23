/*
 * libaribcaption の設定ヘッダー (aribcc_config.h)。
 * 本来は CMake が aribcc_config.h.in から生成するもので、ここでは
 * iOS 向けの組み立て (CoreText のみ使用・版 1.1.2) に合わせて
 * 生成結果と同じ内容を置いている。部品を新しい版へ上げるときは、
 * この版番号も一緒に合わせること。
 */

#ifndef ARIBCAPTION_ARIBCC_CONFIG_H
#define ARIBCAPTION_ARIBCC_CONFIG_H

#define ARIBCC_VERSION    "1.1.2"

#define ARIBCC_VERSION_MAJOR    1
#define ARIBCC_VERSION_MINOR    1
#define ARIBCC_VERSION_PATCH    2

/* #undef ARIBCC_SHARED_LIBRARY */

/* #undef ARIBCC_NO_RENDERER */

/* #undef ARIBCC_IS_ANDROID */

#define ARIBCC_USE_CORETEXT     1
/* #undef ARIBCC_USE_DIRECTWRITE */
/* #undef ARIBCC_USE_FONTCONFIG */
/* #undef ARIBCC_USE_FREETYPE */
/* #undef ARIBCC_USE_GDI_FONT */

#endif  // ARIBCAPTION_ARIBCC_CONFIG_H
