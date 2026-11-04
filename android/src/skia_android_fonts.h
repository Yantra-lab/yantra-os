// android/src/skia_android_fonts.h — pre-included (clang -include) into
// libs/nimskia/src/skia_shim.cpp so its font manager finds Android's fonts.
//
// THE GAP THIS CLOSES (measured, docs/ANDROID.md §parity / §fonts)
//   skia_shim.cpp picks its font manager with a preprocessor chain:
//       #ifdef __EMSCRIPTEN__ ... /fonts
//       #elif defined(__linux__)  SkFontMgr_New_Custom_Directory("/usr/share/fonts")
//       #else                     SkFontMgr_New_DirectWrite()
//   Android's clang defines __linux__, so the shim takes the desktop branch and
//   asks Skia for every font under /usr/share/fonts — a directory that does not
//   exist on a phone. Result would be: no typeface, every text width 0.
//
// WHAT IT DOES
//   Skia's real directory font manager (SkFontMgr_New_Custom_Directory, declared in
//   include/ports/SkFontMgr_directory.h) is kept — only the directory argument is
//   chosen at runtime: $YANTRA_FONTS if the app set one, else /system/fonts, which
//   is where every Android device keeps Roboto and friends, readable by the app.
//   Nothing is re-implemented; Skia still parses the directory with FreeType.
//
// WHY A MACRO
//   libs/nimskia is shared with the desktop build and this lane may not edit it;
//   libs/nimskia/src/nimskia.nim already passes include flags for its shim, so the
//   prelude rides the same compile.
#ifndef YANTRA_SKIA_ANDROID_FONTS_H
#define YANTRA_SKIA_ANDROID_FONTS_H

#include <stdlib.h>

// The prelude is added to EVERY compile in the host (Nim passes one --passC for
// all of them), and only skia_shim.cpp is compiled with -I<skia tree>. So the
// Skia header is included only where it resolves; elsewhere the macro stays off.
#if defined(__has_include)
#  if __has_include("include/ports/SkFontMgr_directory.h")
#    define YANTRA_SKIA_ON_ANDROID 1
#  endif
#endif

#ifdef YANTRA_SKIA_ON_ANDROID
// include the declaration FIRST, so the macro below cannot break it
#include "include/ports/SkFontMgr_directory.h"

static inline const char* yantra_font_dir() {
  const char* e = getenv("YANTRA_FONTS");
  return (e && *e) ? e : "/system/fonts";
}

// A self-referential function-like macro: the inner name is not re-expanded.
#define SkFontMgr_New_Custom_Directory(_ignored_dir) \
  SkFontMgr_New_Custom_Directory(yantra_font_dir())
#endif  // YANTRA_SKIA_ON_ANDROID

#endif  // YANTRA_SKIA_ANDROID_FONTS_H
