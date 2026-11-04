#!/usr/bin/env bash
# tools/build-android.sh — build Yantra's Android APK (arm64-v8a) from this repo's
# own sources. One command, no Gradle: the SDK's aapt2/d8/apksigner are enough.
#
# WHAT IT PRODUCES
#   yantra-os/bin/yantra.apk   (or $OUT_DIR/yantra.apk)
#   containing
#     lib/arm64-v8a/libSDL3.so      real SDL3 3.2.16, cross-built from its release tarball
#     lib/arm64-v8a/libmain.so      the Yantra host: this repo's Nim engine+host,
#                                   compiled for aarch64-linux-android (API 24)
#     classes.dex                   SDL's own Java glue (SDLActivity, 11 files) + MainActivity
#     assets/apps/<id>/app.wasm     the desktop's app modules, BYTE-IDENTICAL
#   and the host inside links, statically, the real Skia (chrome/m143), Yoga,
#   wasmtime (v19.0.2, the same version the desktop host uses), miniaudio,
#   FFmpeg, Jolt and (via its own .so) libcurl. See docs/ANDROID.md for the table
#   of what is in the APK and what each piece cost to build.
#
# WHY THE `third_party` SYMLINK
#   The desktop Nim wrappers (libs/nimskia, libs/nimsdl3, libs/nimav, libs/nimjolt,
#   libs/nimcurl) compute their library paths as
#       <repo>/third_party/<name>
#   at COMPILE TIME from their own source location, and they are shared with the
#   desktop build (this lane may not edit them). So this script points
#   <repo>/third_party at <repo>/android/third_party, which is where the Android
#   builds of exactly those libraries live. Nothing in the wrappers is forked.
#   `third_party/` is gitignored, so the symlink never enters a commit.
#
# USAGE
#   bash tools/build-android.sh                 # build everything, verify, print sha256
#   bash tools/build-android.sh --clean         # wipe android/app/build first
#   ANDROID_HOME=/opt/android-sdk bash tools/build-android.sh
#   JOBS=64 bash tools/build-android.sh
#
# ENV
#   ANDROID_HOME / ANDROID_SDK_ROOT   SDK root (default /home/ubuntu/android-sdk)
#   ANDROID_NDK_HOME                  pin an NDK (default: newest under $SDK/ndk)
#   JAVA_HOME                         JDK 17 (default: whatever `javac` is on PATH)
#   NIM                               nim binary (default: `nim` on PATH, else
#                                     /home/ubuntu/tools/nim-2.2.4/bin/nim)
#   DEP                               dependency install root (default android/third_party)
#   OUT_DIR                           APK output dir (default yantra-os/bin)
#   API                               android API level (default 24)
#   SOURCE_DATE_EPOCH                 fixed mtime for the zip stage (default 1700000000)
#   SKIP_HOST=1                       only repackage (reuse the existing libmain.so)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/android/app"
OSROOT="$ROOT/yantra-os"
DEP="${DEP:-$ROOT/android/third_party}"
OUT_DIR="${OUT_DIR:-$OSROOT/bin}"
API="${API:-28}"   # NDK declares glob() only from API 28; host.nim uses glob
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
ABI=arm64-v8a
TARGET="aarch64-linux-android$API"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

# ---------------------------------------------------------------- toolchains ---
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/home/ubuntu/android-sdk}}"
[ -d "$SDK" ] || die "no Android SDK at $SDK — set ANDROID_HOME"
if [ -n "${ANDROID_NDK_HOME:-}" ]; then NDK="$ANDROID_NDK_HOME"; else
  NDK="$(ls -d "$SDK"/ndk/*/ 2>/dev/null | sort -V | tail -1)"; NDK="${NDK%/}"
fi
[ -d "$NDK" ] || die "no NDK under $SDK/ndk — sdkmanager --install \"ndk;27.2.12479018\""
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
CC="$TC/clang"
[ -x "$CC" ] || die "no clang at $CC"
BT="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"; BT="${BT%/}"
[ -x "$BT/aapt2" ] || die "no aapt2 under $SDK/build-tools"
JAR="$(ls "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)"
[ -f "$JAR" ] || die "no android.jar under $SDK/platforms"
NIM="${NIM:-$(command -v nim || echo /home/ubuntu/tools/nim-2.2.4/bin/nim)}"
[ -x "$NIM" ] || die "no nim (set NIM=...)"

# nim's android target invokes `clang`; give it the NDK one with the right triple.
CFLAGS_TARGET="--target=$TARGET"
LDFLAGS_TARGET="--target=$TARGET"

say "toolchain"
echo "   SDK      $SDK"
echo "   NDK      $NDK (r$(grep -oP 'Pkg.Revision = \K.*' "$NDK/source.properties" 2>/dev/null || echo ?))"
echo "   build-tools $(basename "$BT")   platform $(basename "$(dirname "$JAR")")"
echo "   nim      $("$NIM" --version 2>/dev/null | head -1)"
echo "   java     $("${JAVA_HOME:+$JAVA_HOME/bin/}javac" -version 2>&1 | head -1)"

if [ "${1:-}" = "--clean" ]; then rm -rf "$APP/build"; echo "   cleaned $APP/build"; fi

mkdir -p "$DEP" "$OUT_DIR"

# The wrappers' expected roots, all inside gitignored third_party/. The symlink is
# what makes libs/nimskia + libs/nimsdl3 + libs/nimav + libs/nimjolt find these.
if [ -e "$ROOT/third_party" ] && [ ! -L "$ROOT/third_party" ]; then
  [ -d "$ROOT/third_party" ] && [ -z "$(ls -A "$ROOT/third_party" 2>/dev/null)" ] && rmdir "$ROOT/third_party" \
    || die "$ROOT/third_party exists and is not a symlink — move it aside (this script points it at android/third_party)"
fi
ln -sfn "android/third_party" "$ROOT/third_party"
# host.nim pulls yantra-os/libs/nimminiaudio, whose header path is <yantra-os>/third_party/miniaudio
ln -sfn "../android/third_party" "$OSROOT/third_party"

# ------------------------------------------------------------------- shims -----
# nimskia's Linux branch passes `-lEGL -lGL` (the desktop Skia had a Ganesh GL
# backend). Android's NDK ships libEGL.so but no libGL.so, and our Skia is CPU
# raster (skia_use_gl=false), so nothing references GL: an empty archive satisfies
# the link line. Measured in docs/ANDROID.md: 0 symbols.
mkdir -p "$DEP/stublib"
[ -f "$DEP/stublib/libGL.a" ] || "$TC/llvm-ar" rcs "$DEP/stublib/libGL.a"
# bionic folds pthread into libc: the NDK has no libpthread.so, but the wrappers
# (nimskia, nimav) all pass -lpthread. An empty archive is the correct answer.
[ -f "$DEP/stublib/libpthread.a" ] || "$TC/llvm-ar" rcs "$DEP/stublib/libpthread.a"

# nimjolt's wrapper compiles its shim with -mavx2 -mfma, which clang rejects for
# aarch64 ("unsupported option '-mavx2' for target 'aarch64-linux-android24'").
# android/src/androidlibs/nimjolt.nim is the same C API declared with arm64 flags;
# it is put first on the path so it shadows libs/nimjolt/src/nimjolt.nim.
#
# Two more Android-only seams, both outside the shared wrappers (see
# docs/ANDROID.md "what had to change, and what did not"):
#   -include android/src/skia_android_fonts.h
#        skia_shim.cpp's __linux__ branch looks for fonts in /usr/share/fonts; the
#        prelude points Skia's real directory font manager at /system/fonts.
#   android/src/skia_gl_stubs.cpp
#        skia_shim's GPU block is guarded by #ifndef __EMSCRIPTEN__, so it is
#        compiled on Android even though our Skia is CPU-raster; three Ganesh-GL
#        factories are satisfied by null-returning stubs (yk_gpu_new() -> nullptr,
#        which the shim already handles).
# The linker wrapper exists for one reason: `-lGL`/`-lpthread` appear in the link
# line BEFORE any -L we can add from the command line (Nim appends --passL last),
# and ld resolves -l at the point it appears. The wrapper puts the stub dir first.
LINKSH="$APP/build/bin/ld-clang.sh"
mkdir -p "$(dirname "$LINKSH")"
cat > "$LINKSH" <<LDSH
#!/bin/sh
exec "$CC" --target=$TARGET -L"$DEP/stublib" "\$@"
LDSH
chmod +x "$LINKSH"

SKIA_PRELUDE="$ROOT/android/src/skia_android_fonts.h"
STUB_O="$APP/build/obj/skia_gl_stubs.o"
mkdir -p "$APP/build/obj"
if [ ! -f "$STUB_O" ] || [ "$ROOT/android/src/skia_gl_stubs.cpp" -nt "$STUB_O" ]; then
  "$CC" --target=$TARGET -std=c++17 -O2 -fPIC -DNDEBUG -DSK_RELEASE \
    -I"$DEP/skia-m143" -c "$ROOT/android/src/skia_gl_stubs.cpp" -o "$STUB_O" \
    || die "could not compile skia_gl_stubs.cpp"
fi

# Nim searches --path in REVERSE order (measured: the LAST --path wins), so the
# shadowing module goes last.
NIMPATH=(
  --path:"$ROOT/libs/nimsdl3/src"
  --path:"$ROOT/libs/nimskia/src"
  --path:"$ROOT/libs/nimyoga/src"
  --path:"$ROOT/yantra-os/libs/nimwasmtime/src"   # host/wasmmath.nim imports this copy
  --path:"$ROOT/libs/nimav/src"
  --path:"$ROOT/libs/nimcurl/src"
  --path:"$ROOT/libs/nimfilament/src"
  --path:"$ROOT/libs/nimjolt/src"
  --path:"$ROOT/libs/nimspell/src"
  --path:"$ROOT/libs/nimrtc/src"
  --path:"$ROOT/yantra-os/libs/nimminiaudio/src"
  --path:"$ROOT/android/src/androidlibs"
)

# ------------------------------------------------------- deps that are cheap ---
# Yoga and miniaudio are small enough to (re)build here if they are missing, so a
# fresh clone with just SDK+NDK+ffmpeg/skia can still produce an APK.
say "[1/8] deps: checking the cross-built C/C++ libraries"
miss=0
check() { if [ -e "$2" ]; then echo "   ok      $1"; else echo "   MISSING $1 -> $2"; miss=$((miss+1)); fi; }
check "SDL3 3.2.16 (libSDL3.so)"          "$DEP/sdl3-local/lib/libSDL3.so"
check "Skia chrome/m143 (libskia.a)"      "$DEP/skia-m143/out/Static/libskia.a"
check "Skia paragraphs (libskparagraph.a)" "$DEP/skia-m143/out/Static/libskparagraph.a"
check "wasmtime 19.0.2 (libwasmtime.a)"   "$DEP/wasmtime-android/lib/libwasmtime.a"
check "FFmpeg 7.1.1 (libavformat.a)"      "$DEP/ffmpeg-local/lib/libavformat.a"
check "Jolt 5.3.0 (libJolt.a)"            "$DEP/jolt-local/lib/libJolt.a"
check "libcurl (libcurl.a)"               "$DEP/curl-local/lib/libcurl.a"
check "Yoga (libyoga.a)"                  "$ROOT/libs/nimyoga/build/libyoga.a"
check "miniaudio (libminiaudio.a)"        "$OSROOT/libs/nimminiaudio/build/libminiaudio.a"
check "Filament (libyfilament)"           "$ROOT/libs/nimfilament/build/libyfilament.so"
if [ "$miss" -gt 0 ]; then
  echo
  echo "   $miss dependenc(ies) missing. Each is built by the recipe in its report"
  echo "   (android/third_party/reports/*.md). Yoga and miniaudio are rebuilt here"
  echo "   automatically; the rest must exist before an APK can link."
  if [ ! -f "$ROOT/libs/nimyoga/build/libyoga.a" ]; then
    say "[1a] building Yoga ($ROOT/third_party/yoga) for $TARGET"
    YSRC="$(ls -d "$DEP"/yoga/yoga-* 2>/dev/null | head -1)"
    [ -n "$YSRC" ] || die "no Yoga source at $DEP/yoga/yoga-* (copy third_party/yoga/yoga-3.1.0 there)"
    cmake -S "$YSRC" -B "$YSRC/build-android" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=$ABI -DANDROID_PLATFORM="android-$API" -DCMAKE_BUILD_TYPE=Release \
      -DYOGA_BUILD_UNIT_TEST=OFF -DYOGA_BUILD_UNIT_TEST_SHARED=OFF >/dev/null
    cmake --build "$YSRC/build-android" --parallel "$JOBS" >/dev/null
    mkdir -p "$ROOT/libs/nimyoga/build"
    cp "$(find "$YSRC/build-android" -name 'libyoga.a' | head -1)" "$ROOT/libs/nimyoga/build/libyoga.a"
    echo "   built   libyoga.a ($(stat -Lc%s "$ROOT/libs/nimyoga/build/libyoga.a") B)"
  fi
  [ -f "$ROOT/libs/nimyoga/build/libyoga.a" ] || die "stop: see the missing rows above"
fi

# wasmtime: libs/nimwasmtime/src/nimwasmtime/raw.nim finds its C API by scanning
# <root>/yantra-os/libs/nimwasmtime/vendor for a dir ending "-linux-c-api".
# raw.nim scans vendor/ with walkDir and accepts only pcDir entries, so the
# versioned dir must be REAL; its include/ and lib/ are symlinks into $DEP.
WTV="$OSROOT/libs/nimwasmtime/vendor/wasmtime-v19.0.2-$([ "$(uname -s)" = Darwin ] && echo macos || echo linux)-c-api"
mkdir -p "$WTV"
ln -sfn "$DEP/wasmtime-android/include" "$WTV/include"
ln -sfn "$DEP/wasmtime-android/lib" "$WTV/lib"

# ------------------------------------------------------------- the Nim host ----
say "[2/8] compiling the host (Nim -> $TARGET): android/src/yantra_android.nim"
HOSTLIB="$APP/build/lib/$ABI/libmain.so"
mkdir -p "$(dirname "$HOSTLIB")"
start=$(date +%s)
[ "${SKIP_HOST:-0}" = "1" ] && [ -f "$HOSTLIB" ] && echo "   skipped (SKIP_HOST=1)" || {
  "$NIM" c \
    -d:release --app:lib --opt:speed --threads:on --hints:off \
    --os:android --cpu:arm64 --cc:clang \
    --clang.exe="$CC" --clang.linkerexe="$LINKSH" \
    --passC:"$CFLAGS_TARGET -include $SKIA_PRELUDE" \
    --passL:"$LDFLAGS_TARGET -Wl,--export-dynamic -Wl,-z,max-page-size=16384 -Wl,--gc-sections -Wl,--icf=all -Wl,-s" \
    -d:curlPrefix="$DEP/curl-local" \
    --passL:"-L$DEP/stublib" \
    --passL:"$STUB_O $DEP/skia-m143/out/Static/libexpat.a -llog -landroid -lGLESv2 -lEGL -lm -ldl -lz -latomic" \
    --passL:"$DEP/ffmpeg-local/lib/libavfilter.a -lmediandk -lcamera2ndk" \
    --nimcache:"$APP/build/nimcache-android" \
    --out:"$HOSTLIB" \
    "${NIMPATH[@]}" \
    "$ROOT/android/src/yantra_android.nim"
}
hostsecs=$(( $(date +%s) - start ))
[ -f "$HOSTLIB" ] || die "libmain.so was not produced"
echo "   $HOSTLIB  $(stat -Lc%s "$HOSTLIB") B  sha256 $(sha256sum "$HOSTLIB" | cut -c1-16)…  in ${hostsecs}s"
# (piped through a file: `grep -q` + `set -o pipefail` trips over llvm-nm's SIGPIPE)
"$TC/llvm-nm" -D "$HOSTLIB" > "$APP/build/obj/dynsyms.txt" 2>/dev/null || true
grep -q ' T SDL_main' "$APP/build/obj/dynsyms.txt" || die "libmain.so does not export SDL_main"
grep -q ' T SDL_main' "$APP/build/obj/dynsyms.txt" && echo "   exports SDL_main (dlsym target for SDLActivity)"

# --------------------------------------------------------- SDL3 .so into libs ---
say "[3/8] native libs"
cp -f "$DEP/sdl3-local/lib/libSDL3.so" "$APP/build/lib/$ABI/libSDL3.so"
# libyfilament.so is a real DT_NEEDED of libmain.so (3D), so it must ship too.
cp -f "$ROOT/libs/nimfilament/build/libyfilament.so" "$APP/build/lib/$ABI/libyfilament.so"
for so in "$APP/build/lib/$ABI"/*.so; do
  echo "   $(basename "$so") $(stat -Lc%s "$so") B  sha256 $(sha256sum "$so" | cut -c1-16)…"
done

# ------------------------------------------------------------------- java -----
say "[4/8] Java: SDL's own glue (org.libsdl.app) + MainActivity"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
rm -rf "$APP/build/classes" "$APP/build/dex"; mkdir -p "$APP/build/classes" "$APP/build/dex"
mapfile -t JSRC < <(find "$DEP/sdl3-android/java" "$APP/java" -name '*.java')
"$JAVAC" -source 17 -target 17 -nowarn -classpath "$JAR" -d "$APP/build/classes" "${JSRC[@]}"
"$BT/d8" --min-api "$API" --lib "$JAR" --output "$APP/build/dex" \
  $(find "$APP/build/classes" -name '*.class')
echo "   classes.dex $(stat -Lc%s "$APP/build/dex/classes.dex") B from ${#JSRC[@]} .java files"

# ----------------------------------------------------------------- assets -----
say "[5/8] assets/apps: the desktop's modules, byte for byte"
ASSETS="$APP/build/assets"
rm -rf "$ASSETS"; mkdir -p "$ASSETS/apps"
n=0
for d in "$OSROOT"/apps/*/; do
  id="$(basename "$d")"
  [ -f "$d/app.wasm" ] || continue
  mkdir -p "$ASSETS/apps/$id"
  cp "$d/app.wasm" "$ASSETS/apps/$id/app.wasm"
  [ -f "$d/app.json" ] && cp "$d/app.json" "$ASSETS/apps/$id/app.json"
  [ -d "$d/brand" ] && cp -a "$d/brand" "$ASSETS/apps/$id/"
  n=$((n+1))
done
echo "   $n apps, $(du -sh "$ASSETS" | cut -f1) total"
[ "$n" -gt 0 ] || die "no app.wasm under $OSROOT/apps — run tools/build-wasm.sh first"

# --------------------------------------------------------------- package ------
say "[6/8] aapt2 + dex + libs -> unsigned APK"
STAGE="$APP/build/stage"; rm -rf "$STAGE" "$APP/build/res"; mkdir -p "$APP/build/res" "$STAGE"
"$BT/aapt2" compile --dir "$APP/res" -o "$APP/build/res" >/dev/null
FLATS=(); while IFS= read -r f; do FLATS+=(-R "$f"); done < <(find "$APP/build/res" -name '*.flat' | sort)
"$BT/aapt2" link -o "$APP/build/base.apk" --manifest "$APP/AndroidManifest.xml" \
  -I "$JAR" --min-sdk-version "$API" --target-sdk-version 34 --auto-add-overlay \
  "${FLATS[@]}"

cp "$APP/build/base.apk" "$APP/build/unsigned.apk"
cp "$APP/build/dex/classes.dex" "$STAGE/classes.dex"
mkdir -p "$STAGE/lib/$ABI" && cp "$APP/build/lib/$ABI"/*.so "$STAGE/lib/$ABI/"
mkdir -p "$STAGE/assets" && cp -a "$ASSETS/apps" "$STAGE/assets/apps"
# fixed mtimes so a rebuild on the same inputs produces the same archive
find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
( cd "$STAGE" && zip -q -X -r "$APP/build/unsigned.apk" . -x '.*' )
echo "   unsigned $(stat -Lc%s "$APP/build/unsigned.apk") B"

# ------------------------------------------------------------------ sign -----
say "[7/8] zipalign + sign"
KS="$APP/build/yantra-debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -alias yantra -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass yantra -keypass yantra -dname "CN=Yantra, O=SVAROG SYSTEMS, C=IN" >/dev/null 2>&1
fi
"$BT/zipalign" -f -p 4 "$APP/build/unsigned.apk" "$APP/build/aligned.apk"
APK="$OUT_DIR/yantra.apk"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias yantra --ks-pass pass:yantra --key-pass pass:yantra \
  --min-sdk-version "$API" --max-sdk-version 34 --v4-signing-enabled false \
  --v2-signing-enabled true --v3-signing-enabled true \
  --out "$APK" "$APP/build/aligned.apk"

# ----------------------------------------------------------------- verify -----
say "[8/8] verify"
"$BT/apksigner" verify --verbose "$APK" | sed 's/^/   /' | head -6
"$BT/aapt2" dump badging "$APK" | head -4 | sed 's/^/   /'
echo "   entries:"
unzip -l "$APK" | grep -E "lib/|classes.dex|assets/apps/[a-z0-9]*/app.wasm" | sed 's/^/   /' | head -30
# interchangeability: the module in the APK vs the desktop's, sha256 both ways
say "interchangeability (APK asset vs desktop module)"
bad=0
TMPX="$APP/build/x"; rm -rf "$TMPX"; mkdir -p "$TMPX"
( cd "$TMPX" && unzip -q "$APK" 'assets/apps/*/app.wasm' )
for f in "$TMPX"/assets/apps/*/app.wasm; do
  id="$(basename "$(dirname "$f")")"
  a=$(sha256sum "$f" | cut -d' ' -f1)
  b=$(sha256sum "$OSROOT/apps/$id/app.wasm" | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then printf '   %-10s %s  identical\n' "$id" "$a"
  else printf '   %-10s APK %s != desktop %s\n' "$id" "$a" "$b"; bad=$((bad+1)); fi
done
[ "$bad" -eq 0 ] || die "$bad module(s) differ between the APK and the desktop"
echo
echo "   APK     $APK"
echo "   size    $(stat -Lc%s "$APK") B"
echo "   sha256  $(sha256sum "$APK" | cut -d' ' -f1)"
echo
echo "install:"
echo "   adb install -r \"$APK\""
echo "   adb shell am start -n com.svarogsystems.yantra/.MainActivity"
echo "   adb logcat -s YantraHost"
