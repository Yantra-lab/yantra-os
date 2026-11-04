#!/usr/bin/env bash
# yantra-os/tools/build-all.sh — ONE command that builds Yantra from source.
#
#   bash yantra-os/tools/build-all.sh
#
# What it does, in order (each stage prints one plain-English line):
#   [1/4] find Nim and clang on THIS machine (Nim is usually not on PATH),
#   [2/4] build the miniaudio C archive if it is missing,
#   [3/4] make sure the desktop app module (app.wasm) exists, and build it if not,
#   [4/4] compile the native engine from this repo's own sources -> yantra-os/bin/yantra,
#   then print the binary's path, its size, its sha256 and the exact flags used.
#
# Nothing is downloaded. Every artifact is compiled here, from the sources in this repo.
# Output also goes to yantra-os/yantra-build.log.
#
# Why the engine is built from the REPO ROOT and not from yantra-os/:
#   the root libs/ carry the Linux branches (linux skia from third_party/skia-m143, ...).
#   yantra-os/libs/ is a stale copy without them and does not compile on Linux.
set -euo pipefail

# --------------------------------------------------------------------------------------
# Where things are. Every path is derived from this script's own location, so the user
# may call it from any folder (AGENTS rule 4).
# --------------------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../yantra-os/tools
OS="$(cd "$HERE/.." && pwd)"                           # .../yantra-os
ROOT="$(cd "$OS/.." && pwd)"                           # .../yantra   (the repo root)
LOG="$OS/yantra-build.log"
BIN="$OS/bin/yantra"
ENTRY="render/native/yantra_stage1.nim"                # the engine's main program (root-relative)
DESKTOP_WASM="$OS/apps/desktop/app.wasm"               # module baked into the exe as a fallback

# --------------------------------------------------------------------------------------
# Everything this script prints is also written to $LOG (tear off, hand to a helper).
# The re-exec below is the standard way to tee a whole script, including Nim's own output.
# --------------------------------------------------------------------------------------
if [ "${YANTRA_BUILD_LOGGED:-0}" != "1" ]; then
  mkdir -p "$OS"
  export YANTRA_BUILD_LOGGED=1
  set +e
  bash "${BASH_SOURCE[0]}" "$@" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

# A beginner should never see a bare exit code: say which command failed.
trap 'code=$?; echo ""; echo "BUILD FAILED (exit $code)"; echo "  failing command: $BASH_COMMAND"; echo "  full log:        $LOG"; exit "$code"' ERR

say() { echo "$*"; }

# --------------------------------------------------------------------------------------
# [1/4] The toolchain: Nim 2.x and clang. Neither may be assumed to be on PATH.
# --------------------------------------------------------------------------------------
find_nim() {
  local c
  # 1. a nim already on PATH wins
  if c="$(command -v nim 2>/dev/null)" && [ -x "$c" ]; then echo "$c"; return 0; fi
  # 2. the Nim this box ships outside PATH
  for c in /home/ubuntu/tools/nim-2.2.4/bin/nim "$HOME"/tools/nim-*/bin/nim \
           "$ROOT"/third_party/nim*/bin/nim; do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}

if ! NIM="$(find_nim)"; then
  say "Yantra build: I could not find the Nim compiler on this machine."
  say "  Install Nim 2.2.4 (https://nim-lang.org/install.html) or put it at ~/tools/nim-*/bin/nim,"
  say "  then run this script again:  bash $0"
  exit 1
fi
NIM_DIR="$(cd "$(dirname "$NIM")" && pwd)"
NIM_VERSION="$("$NIM" --version 2>/dev/null | head -1)"
say "[1/4] Nim:   $NIM  ($NIM_VERSION)"

# clang, not gcc: this box has no gcc. Nim must be told exactly which compilers to use.
CLANG="${YANTRA_CLANG:-}"
if [ -z "$CLANG" ]; then CLANG="$(command -v clang 2>/dev/null || true)"; fi
if [ -z "$CLANG" ] && [ -x /usr/bin/clang ]; then CLANG=/usr/bin/clang; fi
CXX="${YANTRA_CLANGXX:-}"
if [ -z "$CXX" ]; then CXX="$(command -v clang++ 2>/dev/null || true)"; fi
if [ -z "$CXX" ] && [ -x /usr/bin/clang++ ]; then CXX=/usr/bin/clang++; fi
if [ -z "$CLANG" ] || [ ! -x "$CLANG" ]; then
  say "Yantra build: I could not find the clang C compiler (this box has no gcc)."
  say "  Install clang (e.g. 'sudo apt install clang') or set YANTRA_CLANG=/path/to/clang."
  exit 1
fi
if [ -z "$CXX" ] || [ ! -x "$CXX" ]; then
  say "Yantra build: I could not find the clang++ C++ compiler (needed by Skia and friends)."
  say "  Install clang (e.g. 'sudo apt install clang') or set YANTRA_CLANGXX=/path/to/clang++."
  exit 1
fi
CLANG_DIR="$(cd "$(dirname "$CLANG")" && pwd)"
say "       clang: $CLANG  ($("$CLANG" --version | head -1))"

# build-wasm.sh (and the hot-reload watcher inside the engine) call `nim` and `clang` by
# name, so both must be on PATH for the rest of this script.
export PATH="$NIM_DIR:$CLANG_DIR:$PATH"

# These flags are the whole contract with Nim on this box; they are printed again at the end.
DEFINES="-d:release --threads:on --hints:off"
CCFLAGS="--cc:clang --clang.exe:$CLANG --clang.linkerexe:$CLANG --clang.cpp.exe:$CXX"
# Private nimcache: lets this script run beside another lane's build without collisions.
NIMCACHE="${YANTRA_NIMCACHE:-/tmp/dh/nimcache-toolchain}"
mkdir -p "$NIMCACHE"
# The 16 library paths, relative to the repo root (exactly these).
LIBPATHS="--path:libs/nimaccesskit/src --path:libs/nimav/src --path:libs/nimblake3/src
--path:libs/nimcurl/src --path:libs/nimfilament/src --path:libs/nimjolt/src
--path:libs/nimminiaudio/src --path:libs/nimpg/src --path:libs/nimqt/src
--path:libs/nimrtc/src --path:libs/nimsdl3/src --path:libs/nimskia/src
--path:libs/nimspell/src --path:libs/nimsqlite/src --path:libs/nimwasmtime/src
--path:libs/nimyoga/src"
# --parallelBuild cap: this is a DELIBERATE choice, recorded per AGENTS rule 5.
# Why: the box has 192 CPU cores but only 4 GB of RAM (measured: /proc/meminfo MemTotal
# 4,206,766,360 KB = 4,011 MiB). Nim would otherwise start one clang job per core -- 192
# concurrent C compilations on 4 GB of RAM, which OOMs the machine and takes other agents'
# builds down with it. 8 is measured to be cheap: on a cold build (binary deleted, nimcache
# wiped) wall time was 9.576 s and memory never dipped below MemFree 2,585,674,812 KB /
# MemAvailable 4,077,398,316 KB (sampled every 0.2 s during the build, 48 samples).
# Override with YANTRA_BUILD_JOBS if the box ever gets more RAM.
JOBS="${YANTRA_BUILD_JOBS:-8}"

# --------------------------------------------------------------------------------------
# [2/4] The miniaudio archive.
# libs/nimminiaudio/src/nimminiaudio.nim tries to build it with `cmd /c ... gcc` (Windows
# only), so on Linux that step silently builds NOTHING and the link dies looking for
# libminiaudio.a. Build it here, with clang, if it is not there.
# --------------------------------------------------------------------------------------
MINIAUDIO_A="$ROOT/libs/nimminiaudio/build/libminiaudio.a"
if [ -f "$MINIAUDIO_A" ]; then
  say "[2/4] miniaudio C archive: already built ($(stat -c%s "$MINIAUDIO_A") bytes)"
else
  say "[2/4] miniaudio C archive: missing, building it with clang (one-time, ~10 s)..."
  mkdir -p "$ROOT/libs/nimminiaudio/build"
  "$CLANG" -O2 -c -DMINIAUDIO_IMPLEMENTATION -x c \
    "$ROOT/third_party/miniaudio/miniaudio.h" \
    -o "$ROOT/libs/nimminiaudio/build/miniaudio.o"
  ar rcs "$MINIAUDIO_A" "$ROOT/libs/nimminiaudio/build/miniaudio.o"
  say "      -> $MINIAUDIO_A ($(stat -c%s "$MINIAUDIO_A") bytes)"
fi

# --------------------------------------------------------------------------------------
# [3/4] The two desktop app modules. They are different files and the difference matters:
#   RUN      apps/desktop/app.wasm  (repo root)     -- what the launcher OPENS, and the one
#                                                      the hot-reload watcher can rebuild
#                                                      (it watches <repo-root>/apps/*/app.nim).
#   EMBEDDED yantra-os/apps/desktop/app.wasm        -- baked into the engine at compile time
#                                                      (staticRead) as a last-resort fallback.
# The embedded one must exist BEFORE stage 4, or the engine cannot link.
# --------------------------------------------------------------------------------------
build_wasm() {  # <src.nim> <out.wasm>; build-wasm.sh must be called by its real path
  PATH="$NIM_DIR:$CLANG_DIR:$PATH" bash "$ROOT/tools/build-wasm.sh" "$1" "$2"
}
RUN_WASM="$ROOT/apps/desktop/app.wasm"
RUN_SRC="$ROOT/apps/desktop/app.nim"
EMBEDDED_WASM="$DESKTOP_WASM"
WASM_LOG="${TMPDIR:-/tmp}/yantra-wasm-build.log"
RUN_NOTE="already present, not rebuilt this run"
EMB_NOTE="already present, not rebuilt this run"

if [ -f "$RUN_WASM" ]; then
  say "[3/4] desktop module the launcher opens: already built ($(stat -c%s "$RUN_WASM") bytes)"
else
  say "[3/4] desktop module the launcher opens: missing, building apps/desktop/app.nim..."
  build_wasm "$RUN_SRC" "$RUN_WASM"
  RUN_NOTE="built from source this run"
  say "      -> $RUN_WASM ($(stat -c%s "$RUN_WASM") bytes)"
fi

if [ -f "$EMBEDDED_WASM" ]; then
  say "      embedded fallback module: already present ($(stat -c%s "$EMBEDDED_WASM") bytes)"
else
  say "      embedded fallback module: missing, building it (stage 4 bakes it into the engine)"
  RELEASE_SRC="$OS/apps/desktop/app.nim"
  if build_wasm "$RELEASE_SRC" "$EMBEDDED_WASM" > "$WASM_LOG" 2>&1; then
    EMB_NOTE="built from $RELEASE_SRC"
    say "      -> built $EMBEDDED_WASM ($(stat -c%s "$EMBEDDED_WASM") bytes) from $RELEASE_SRC"
  else
    # Loud, never silent (the AGENTS "a build step that cannot run silently builds nothing"
    # class): the release app sources are Sutra, a different language, so `nim c` rejects
    # them. Print the REAL error line, then build the equivalent Nim-SDK desktop instead.
    say "      $RELEASE_SRC did not compile with nim; the real error was:"
    sed -n '1,4p' "$WASM_LOG" | sed 's/^/        /'
    say "      (that source is Sutra, not Nim) falling back to the Nim-SDK desktop $RUN_SRC"
    build_wasm "$RUN_SRC" "$EMBEDDED_WASM"
    EMB_NOTE="built from $RUN_SRC -- NIM-SDK DESKTOP, not the release source (which is Sutra)"
    say "      -> built $EMBEDDED_WASM ($(stat -c%s "$EMBEDDED_WASM") bytes) from $RUN_SRC"
  fi
fi

# --------------------------------------------------------------------------------------
# [4/4] The engine itself. Always fresh: rebuild whenever any engine source is newer than
# the binary (so a stale binary is impossible), or when the binary is missing.
# --------------------------------------------------------------------------------------
cd "$ROOT"                                   # the build MUST run from the repo root

if [ ! -x "$BIN" ]; then
  WHY="yantra-os/bin/yantra does not exist yet"
else
  NEWER="$(find render/native host protocol libs -newer "$BIN" \
             \( -name '*.nim' -o -name '*.nims' -o -name '*.h' -o -name '*.a' \) \
             -print -quit 2>/dev/null || true)"
  # The embedded module is compiled INTO the binary (staticRead), so a newer app.wasm means
  # the binary would carry stale app bytes: it counts as a changed source too.
  if [ -z "$NEWER" ] && [ "$DESKTOP_WASM" -nt "$BIN" ]; then NEWER="$DESKTOP_WASM"; fi
  if [ -n "$NEWER" ]; then
    WHY="a source file changed after the binary was built ($NEWER)"
  else
    WHY=""
  fi
fi

if [ -n "$WHY" ]; then
  say "[4/4] engine: rebuilding, because $WHY"
  mkdir -p "$OS/bin"
  # shellcheck disable=SC2086  # word splitting is intended: these are flag lists
  BUILD_CMD=("$NIM" c $DEFINES $CCFLAGS --nimcache:"$NIMCACHE" --parallelBuild:"$JOBS" \
             $LIBPATHS --out:"$BIN" "$ENTRY")
  echo "      command: ${BUILD_CMD[*]}"
  started=$SECONDS
  "${BUILD_CMD[@]}"
  say "      built in $((SECONDS - started)) s  [$DEFINES]"
else
  say "[4/4] engine: up to date, nothing to do ($(stat -c%s "$BIN") bytes)"
fi

# --------------------------------------------------------------------------------------
# Done. Print what was produced, so nobody has to trust a promise.
# --------------------------------------------------------------------------------------
if [ ! -x "$BIN" ]; then
  say "Yantra build: the compile step finished but $BIN is missing. Nothing was produced."
  exit 1
fi
say ""
say "================ Yantra built from source ================"
say "binary:  $BIN"
say "size:    $(stat -c%s "$BIN") bytes"
say "sha256:  $(sha256sum "$BIN" | cut -d' ' -f1)"
say "built:   $(date -u '+%Y-%m-%dT%H:%M:%SZ') (engine sources ${ENTRY})"
say "defines: $DEFINES"
say "cc:      clang via $CLANG, clang++ via $CXX"
say "run module:      $RUN_WASM"
say "                 $(stat -c%s "$RUN_WASM") bytes, sha256 $(sha256sum "$RUN_WASM" | cut -d' ' -f1)"
say "                 $RUN_NOTE"
say "embedded module: $EMBEDDED_WASM"
say "                 $(stat -c%s "$EMBEDDED_WASM") bytes, sha256 $(sha256sum "$EMBEDDED_WASM" | cut -d' ' -f1)"
say "                 $EMB_NOTE"
say "log:     $LOG"
say "next:    bash $OS/run_yantra.sh"
say "         opens apps/desktop/app.wasm in the real window with --watch (hot reload on)"
say "=========================================================="
