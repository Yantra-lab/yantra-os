#!/usr/bin/env bash
# yantra-os/run_yantra.sh — the double-click launcher.
#
#   Open Yantra without typing any flags: run this file, or double-click it.
#
# It does exactly three things, and prints one line for each:
#   1. makes sure the toolchain (Nim + clang) is on PATH, so the hot-reload watcher
#      inside the engine can rebuild your app without you configuring anything. This
#      matters: a program started from a desktop icon inherits a tiny PATH, and without
#      this line the rebuild would silently fail;
#   2. builds the engine and the desktop module if they are missing or stale (otherwise
#      it skips the build -- the fast path);
#   3. starts the real desktop window with hot reload ON (--watch): edit
#      apps/desktop/app.nim, save, and the running window rebuilds and swaps itself in.
#      No restart.
#
# The user passes no flags. Any extra flags you do pass are handed to the engine.
set -euo pipefail

# --------------------------------------------------------------------------------------
# Where things are. Derived from this script's own location, so a desktop shortcut or
# any working directory works (AGENTS rule 4).
# --------------------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../yantra-os
ROOT="$(cd "$HERE/.." && pwd)"                         # .../yantra   (repo root)
BIN="$HERE/bin/yantra"                                 # the engine this launcher starts
MODULE="$ROOT/apps/desktop/app.wasm"                   # the app it opens
MODULE_SRC="$ROOT/apps/desktop/app.nim"
LOG="$HERE/yantra-build.log"
# The engine's entrypoint is render/native/yantra_stage1.nim; the same source list the
# build uses decides whether the binary is stale.
ENTRY="render/native/yantra_stage1.nim"

# --------------------------------------------------------------------------------------
# 1. Toolchain on PATH. Nim and clang are NOT on PATH on a fresh shell on this box, so
#    find them ourselves and export their folders.
# --------------------------------------------------------------------------------------
find_nim() {
  local c
  if c="$(command -v nim 2>/dev/null)" && [ -x "$c" ]; then echo "$c"; return 0; fi
  for c in /home/ubuntu/tools/nim-2.2.4/bin/nim "$HOME"/tools/nim-*/bin/nim \
           "$ROOT"/third_party/nim*/bin/nim; do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  return 1
}
if ! NIM="$(find_nim)"; then
  echo "[Yantra] I could not find the Nim compiler, so I cannot build or hot-reload."
  echo "[Yantra] Install Nim 2.2.4, or run the full build once: bash $HERE/tools/build-all.sh"
  exit 1
fi
CLANG="${YANTRA_CLANG:-}"
if [ -z "$CLANG" ]; then CLANG="$(command -v clang 2>/dev/null || true)"; fi
if [ -z "$CLANG" ] && [ -x /usr/bin/clang ]; then CLANG=/usr/bin/clang; fi
if [ -z "$CLANG" ] || [ ! -x "$CLANG" ]; then
  echo "[Yantra] I could not find clang (needed to rebuild apps)."
  exit 1
fi
export PATH="$(cd "$(dirname "$NIM")" && pwd):$(cd "$(dirname "$CLANG")" && pwd):$PATH"
# Belt and braces for the shared libraries the engine links (its rpath is already
# absolute on this box, so this only helps if the tree is moved).
export LD_LIBRARY_PATH="$ROOT/third_party/ffmpeg-local/lib:$ROOT/libs/nimwasmtime/vendor/wasmtime-v50.0.1-x86_64-linux-c-api/lib:${LD_LIBRARY_PATH:-}"

# --------------------------------------------------------------------------------------
# 2. Build only if we have to: binary missing, or an engine source is newer than it.
# --------------------------------------------------------------------------------------
STALE=""
if [ ! -x "$BIN" ]; then
  STALE="there is no engine binary yet"
else
  NEWER="$(cd "$ROOT" && find render/native host protocol libs -newer "$BIN" \
             \( -name '*.nim' -o -name '*.nims' -o -name '*.h' -o -name '*.a' \) \
             -print -quit 2>/dev/null || true)"
  # The embedded module (yantra-os/apps/desktop/app.wasm) is compiled into the binary, so a
  # newer one means the binary carries stale app bytes: that counts as a changed source.
  EMBEDDED="$HERE/apps/desktop/app.wasm"
  if [ -z "$NEWER" ] && [ "$EMBEDDED" -nt "$BIN" ]; then NEWER="yantra-os/apps/desktop/app.wasm"; fi
  if [ -n "$NEWER" ]; then STALE="engine sources changed ($NEWER)"; fi
fi
if [ -n "$STALE" ]; then
  echo "[1/3] Building Yantra (this can take a few minutes the first time): $STALE"
  bash "$HERE/tools/build-all.sh"
else
  echo "[1/3] Engine is up to date ($(stat -c%s "$BIN") bytes) - skipping the build."
fi

# --------------------------------------------------------------------------------------
# 3. The app module. Build it from source if it is missing (~4 s, it is cheap).
# --------------------------------------------------------------------------------------
if [ -f "$MODULE" ]; then
  echo "[2/3] Desktop module already present: apps/desktop/app.wasm ($(stat -c%s "$MODULE") bytes, not rebuilt this run)"
else
  echo "[2/3] Desktop module missing - building it from apps/desktop/app.nim..."
  bash "$ROOT/tools/build-wasm.sh" "$MODULE_SRC" "$MODULE"
  echo "[2/3] Built apps/desktop/app.wasm from source just now ($(stat -c%s "$MODULE") bytes)"
fi

# --------------------------------------------------------------------------------------
# 4. Start the desktop. The watcher resolves apps/* from the working directory, so we
#    stand in the repo root before starting the engine (this is why the cd is here).
# --------------------------------------------------------------------------------------
echo "[3/3] Opening the Yantra desktop with hot reload ON (edit apps/desktop/app.nim and save)."
cd "$ROOT"
exec "$BIN" "apps/desktop/app.wasm" --watch --mcp-port=9229 "$@"
