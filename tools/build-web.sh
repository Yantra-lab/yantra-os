#!/usr/bin/env bash
# The engine for the browser: render/web/web_main.nim + engine.nim built with emscripten into
# web/engine/build/ (engine.js, engine.wasm, engine.data with the fonts), plus the example apps.
# Serve web/engine/ and open index.html?app=<name>.
#
# Needs (all under third_party/, gitignored): emsdk (git clone emsdk; emsdk install/activate
# latest), Skia built for wasm (third_party/skia-build/src/skia/out/wasm, see WEB.md in
# render/web), and yoga sources (tools/setup.sh). Fonts are fetched once: Inter and JetBrains
# Mono, both SIL Open Font License.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TP="$HERE/third_party"
EM="$TP/emsdk/upstream/emscripten"
[ -x "$EM/emcc.exe" ] || [ -x "$EM/emcc" ] || { echo "build-web: no emsdk at $TP/emsdk"; exit 1; }
SKOUT="$TP/skia-build/src/skia/out/wasm"
[ -f "$SKOUT/libskia.a" ] || { echo "build-web: Skia for wasm is not built ($SKOUT)"; exit 1; }
EXT=""; [ -x "$EM/emcc.exe" ] && EXT=".exe"
OUT="$HERE/web/engine/build"
mkdir -p "$OUT/apps" "$TP/fonts"

# yoga for wasm
YB="$HERE/libs/nimyoga/build-web"
if [ ! -f "$YB/libyoga.a" ]; then
  mkdir -p "$YB/obj"
  YS="$TP/yoga/yoga-3.1.0"
  for f in $(cd "$YS" && find yoga -name '*.cpp'); do
    o="$YB/obj/$(echo "$f" | tr '/' '_').o"
    "$EM/em++$EXT" -std=c++20 -O2 -DNDEBUG -I"$YS" -c "$YS/$f" -o "$o"
  done
  "$EM/emar$EXT" rcs "$YB/libyoga.a" "$YB"/obj/*.o
  echo "build-web: yoga built"
fi

# fonts
F="$TP/fonts"
[ -f "$F/sans.ttf" ] || curl -sSLf -o "$F/sans.ttf" "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"
[ -f "$F/mono.ttf" ] || curl -sSLf -o "$F/mono.ttf" "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"

# the engine
W() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
EXPORTS="_main,_malloc,_free,_yw_start,_yw_resize,_yw_frame,_yw_pointer,_yw_wheel,_yw_key,_yw_text,_yw_focused,_yw_blink,_yw_title,_yw_invoke"
nim c --hints:off --warnings:off -d:release -d:emscripten --os:linux --cpu:wasm32 --mm:orc --threads:off \
  --cc:clang --clang.exe:"emcc$EXT" --clang.linkerexe:"em++$EXT" --clang.cpp.exe:"em++$EXT" --clang.cpp.linkerexe:"em++$EXT" \
  -p:"$(W "$HERE/libs/nimwasmtime/src")" -p:"$(W "$HERE/libs/nimskia/src")" -p:"$(W "$HERE/libs/nimyoga/src")" \
  -p:"$(W "$HERE/host")" -d:skiaSrc="$(W "$TP/skia-build/src/skia")" -d:yogaWebLib="$(W "$YB/libyoga.a")" --nimcache:"$(W "$HERE/web/engine/nimcache")" \
  --passL:"-sMODULARIZE=1 -sEXPORT_ES6=1 -sENVIRONMENT=web -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 -sEXPORTED_FUNCTIONS=$EXPORTS" \
  --passL:"-sEXPORTED_RUNTIME_METHODS=ccall,UTF8ToString,stringToUTF8,lengthBytesUTF8,HEAPU8,HEAP32,HEAPF32" \
  --passL:"--preload-file $(W "$F")@/fonts" \
  -o:"$(W "$OUT/engine.js")" "$(W "$HERE/render/web/web_main.nim")"
echo "build-web: wrote $OUT/engine.js ($(wc -c < "$OUT/engine.wasm") bytes wasm)"

# the example apps the page can open: names under examples/ (e.g. counter, shell/chat)
for n in ${@:-counter todo}; do
  bash "$HERE/tools/build-wasm.sh" "$HERE/examples/$n.nim" "$OUT/apps/$(basename "$n").wasm" --release | tail -1
done
