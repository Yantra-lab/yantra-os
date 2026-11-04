#!/usr/bin/env bash
# Build ONE Yantra app module from its own source, reproducibly, on this box.
#
#   bash yantra-os/apps/_build/build-app.sh <app-id> <out.wasm>
#
# Prints, as its last line, the module's byte size and sha256:
#
#   build-app: arcade (sutra) -> /tmp/arcade.wasm 193712 bytes sha256 1a2b...
#
# Exits non-zero on any failure. It deletes <out.wasm> BEFORE it builds, so a
# failed build can never leave an older module sitting at the output path
# looking fresh — the defect that once hid a broken SDK behind a stale
# hello.wasm (skills/yantra/reference/01-build-run-and-verify.md:77-95).
#
# TWO KINDS OF SOURCE, TWO TOOLCHAINS
#
#   sutra  a Sutra cell: `view Name` / `record Name` and no `import` lines.
#          Built by `nimony w` (the fork in third_party/nimony) after the
#          compiler's own `app.nim` is assembled: the prelude the Atlas writes,
#          then the app's source, then the engine's protocol (see below).
#
#   nim    a Nim 2 module: `import std/...` and its own `yantra_main`.
#          Built by yantra-os/tools/build-wasm.sh, unmodified.
#
# WHY THE PRELUDE AND THE EPILOGUE ARE HERE
# The app sources under apps/ are *cells*, not programs. host/atlas/build.nim
# wraps a cell in three things before the compiler ever sees it:
#   :14-20   the prelude — `#! sutra`, four imports, six feature switches
#   :489-491 the cell text
#   :500-511 the engine's protocol: one `{.exportc.}` proc per name the host
#            calls — yantra_main (mount), yantra_dispatch (an event),
#            sutra_refresh (redraw), sutra_param_changed (a live parameter).
# Compile the cell without them and `nimony w` SUCCEEDS, writes a module, and
# the module renders almost nothing: nothing calls the root view, so dead-code
# elimination drops every node-building call. The module is then missing
# `yantra_main` and the engine prints `crashed=[export not found: yantra_main]`.
# Measured on apps/arcade: 52,417 B with 19 exports and 4 imports vs the shipped
# 193,746 B with 23 exports and 21 imports.
#
# Environment (all optional):
#   YANTRA_VOCAB     the Sutra vocabulary directory (default: <repo>/sdk/sutra,
#                    else yantra-os/sdk/sutra)
#   YANTRA_ROOT_VIEW the view to mount, when the source has more than one and
#                    the last one is not the root
#   YANTRA_NIMCACHE  the compiler cache (default: /tmp/yantra-nimcache-sutra,
#                    shared by every app exactly as the Atlas shares one)
#   YANTRA_NIMONY    the nimony binary
#   YANTRA_KEEP=1    keep the assembled app.nim and print where it is
#
# `--kind <app-id>` prints `sutra` or `nim` and exits, for other scripts.

set -euo pipefail

SELF="$0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# YANTRA_APPS_DIR lets a caller build from a staged copy of the tree (parity.sh
# --pinned builds from `git archive HEAD`), while the toolchain below is always
# found relative to this script — the vocabulary and build-wasm.sh do not move.
APPS="${YANTRA_APPS_DIR:-$(cd "$HERE/.." && pwd)}"   # yantra-os/apps
OS="$(cd "$HERE/../.." && pwd)"         # yantra-os — always from THIS script,
REPO="$(cd "$HERE/../../.." && pwd)"    # the worktree root — never from $APPS

die() { echo "build-app: $*" >&2; exit 1; }

# ── the toolchain, found rather than assumed ─────────────────────────────────
# Nim is NOT on PATH on this box; nimony lives in the compiler fork's bin/.
NIM_BIN="${YANTRA_NIM_BIN:-/home/ubuntu/tools/nim-2.2.4/bin}"
[ -x "$NIM_BIN/nim" ] && export PATH="$NIM_BIN:$PATH"

find_nimony() {
  if [ -n "${YANTRA_NIMONY:-}" ]; then echo "$YANTRA_NIMONY"; return; fi
  local c
  for c in "$REPO/third_party/nimony/bin/nimony" \
           "/home/ubuntu/yantra/third_party/nimony/bin/nimony"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  echo ""
}

find_vocab() {
  if [ -n "${YANTRA_VOCAB:-}" ]; then echo "$YANTRA_VOCAB"; return; fi
  local c
  for c in "$REPO/sdk/sutra" "$OS/sdk/sutra"; do
    [ -f "$c/sutraui.nim" ] && { echo "$c"; return; }
  done
  echo ""
}

# ── what kind of source is this? ────────────────────────────────────────────
# A Sutra cell declares `view`/`record` at column 0 and never imports; a Nim
# module imports and does not. Both tests, so a stray `record` in a Nim
# comment cannot flip the answer.
kind_of() {
  local src="$1"
  if grep -qE '^(view|record) +[A-Za-z_]' "$src" && ! grep -qE '^import ' "$src"; then
    echo sutra
  else
    echo nim
  fi
}

# The root view: the LAST `view Name` at column 0. host/atlas/build.nim mounts
# `cells[^1]` — the last cell reached — and every cell in a single-file app is
# that file, so the last view in the file is what the Atlas mounts. apps/todo
# (`TaskRow` then `Todo`) and apps/gallery3d (`NightHall`, `Work`, `Spot`, then
# `Gallery3d`) both end with their root view, and the exported app.yantra.json
# of each shows the matching window title ("Todo", "Gallery3d").
root_view_of() {
  grep -oE '^view +[A-Za-z_][A-Za-z0-9_]*' "$1" | tail -1 | awk '{print $2}'
}

if [ "${1:-}" = "--kind" ]; then
  [ -n "${2:-}" ] || die "usage: build-app.sh --kind <app-id>"
  [ -f "$APPS/$2/app.nim" ] || die "no such app: apps/$2/app.nim"
  kind_of "$APPS/$2/app.nim"
  exit 0
fi

APP="${1:?usage: build-app.sh <app-id> <out.wasm>}"
OUT="${2:?usage: build-app.sh <app-id> <out.wasm>}"
SRC="$APPS/$APP/app.nim"
[ -f "$SRC" ] || die "no such app: $SRC (apps are directories under $APPS)"

# An output path the caller can find from anywhere; its directory is made if
# it is missing, so `build-app.sh arcade /tmp/out/arcade.wasm` just works.
mkdir -p "$(dirname "$OUT")"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$OUT_DIR/$(basename "$OUT")"

# Never leave a stale module looking fresh.
rm -f "$OUT" "$OUT.opt"

TMPBASE="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "$TMPBASE/yantra-build-$APP.XXXXXX")"
cleanup() {
  if [ "${YANTRA_KEEP:-0}" = "1" ]; then echo "build-app: kept $WORK" >&2
  else rm -rf "$WORK"; fi
}
trap cleanup EXIT

KIND="$(kind_of "$SRC")"
START=$(date +%s)

if [ "$KIND" = "nim" ]; then
  # ── Nim 2 app: yantra-os/tools/build-wasm.sh, unchanged ──────────────────
  # The script writes its nimcache, minilibc.o and panicoverride.nim next to
  # the source it is given. Give it a temp MIRROR of the tree so nothing is
  # written inside apps/: the app's own directory is copied (its siblings'
  # modules are imported, e.g. orrery's `import model`, and desktop/config.nim
  # for files), and every other app plus sdk/ is a symlink. Build outputs
  # therefore land in $WORK, never in the repo.
  MIRROR="$WORK/tree"
  mkdir -p "$MIRROR/apps"
  ln -s "$OS/sdk" "$MIRROR/sdk"
  for d in "$APPS"/*/; do
    id="$(basename "$d")"
    if [ "$id" = "$APP" ]; then
      mkdir -p "$MIRROR/apps/$id"
      tar -C "$d" --exclude='nimcache*' --exclude='*.wasm' --exclude='*.o' -cf - . \
        | tar -C "$MIRROR/apps/$id" -xf -
    else
      ln -s "$d" "$MIRROR/apps/$id"
    fi
  done
  # binaryen is installed on this box but build-wasm.sh only looks for a
  # Windows path and then `command -v`, so without this its --release size
  # squeeze is silently skipped and every module is 20-35% larger than it
  # should be (measured elsewhere: 164,616 B unsqueezed -> 132,255 B squeezed).
  for b in "$REPO/third_party/binaryen/bin" "/home/ubuntu/yantra/third_party/binaryen/bin"; do
    [ -x "$b/wasm-opt" ] && export PATH="$b:$PATH"
  done
  echo "build-app: $APP is Nim 2 syntax — tools/build-wasm.sh --release"
  bash "$OS/tools/build-wasm.sh" "$MIRROR/apps/$APP/app.nim" "$OUT" --release
else
  # ── Sutra cell: prelude + source + the engine's protocol ─────────────────
  NIMONY="$(find_nimony)"
  [ -n "$NIMONY" ] || die "no nimony found; set YANTRA_NIMONY (looked in \$REPO/third_party/nimony/bin)"
  VOCAB="$(find_vocab)"
  [ -n "$VOCAB" ] || die "no Sutra vocabulary found; set YANTRA_VOCAB (looked in \$REPO/sdk/sutra)"
  # PER-APP cache by default. A shared cache made two concurrent builds write each
  # other's bytes: building calc and notes in parallel produced NOTES' module for BOTH,
  # with exit 0 and no warning (reproduced 2026-11-06 by the autoreload lane; the flock
  # around `nimony w` does not cover whatever clobbers the cache). A private cache per
  # app costs a cold compile the first time and is correct always.
  NIMCACHE="${YANTRA_NIMCACHE:-$TMPBASE/yantra-nimcache-sutra-$APP}"

  VIEW="${YANTRA_ROOT_VIEW:-$(root_view_of "$SRC")}"
  if [ -z "$VIEW" ] && ! grep -qE 'exportc: *"yantra_main"' "$SRC"; then
    die "apps/$APP/app.nim has no top-level \`view\` and no yantra_main; set YANTRA_ROOT_VIEW"
  fi

  # assemble.py is the Atlas's moduleText for one file: the prelude, a plain
  # Nim type for every `record` block, the cell, then the engine protocol.
  ASSEMBLED="$WORK/app.nim"
  if [ -n "$VIEW" ]; then
    python3 "$HERE/assemble.py" "$SRC" "$ASSEMBLED" --view "$VIEW" \
      || die "could not assemble apps/$APP/app.nim into a module"
  else
    python3 "$HERE/assemble.py" "$SRC" "$ASSEMBLED" \
      || die "could not assemble apps/$APP/app.nim into a module"
  fi

  echo "build-app: $APP is Sutra syntax — root view $VIEW, nimony w (no database)"
  # Exactly the Atlas command (host/atlas/build.nim:636-639): no -d:, no
  # --opt, nothing else. One shared cache across apps, as the Atlas does, so
  # the five plugins compile once rather than once per app.
  #
  # The shared cache is why the call is serialised with flock: two nimony runs
  # on one cache stage the plugin executables in the same directory and the
  # loser dies with `nifler2: cannot read the input file` (measured, two of my
  # own runs overlapping). The lock is per cache directory, so it costs
  # nothing when nothing else is building.
  nimony_build() {
    ( cd "$WORK" && "$NIMONY" w \
        --nimcache:"$NIMCACHE" \
        --path:"$VOCAB" \
        -o:"$OUT" app.nim )
  }
  mkdir -p "$NIMCACHE"
  if command -v flock > /dev/null 2>&1; then
    ( flock 9; nimony_build ) 9> "$NIMCACHE/.build.lock" \
      || die "nimony w failed for apps/$APP/app.nim (see the output above)"
  else
    nimony_build || die "nimony w failed for apps/$APP/app.nim (see the output above)"
  fi
fi

[ -s "$OUT" ] || die "build produced no module at $OUT"

# A module without yantra_main loads and draws almost nothing. Refuse it here,
# where the message names the real problem, rather than in the screenshot.
python3 "$HERE/wasm-exports.py" --check yantra_main --check yantra_dispatch "$OUT" > /dev/null \
  || { python3 "$HERE/wasm-exports.py" "$OUT"; die "$OUT does not export the engine protocol"; }

BYTES="$(stat -c%s "$OUT")"
HASH="$(sha256sum "$OUT" | cut -d' ' -f1)"
MS=$(( ( $(date +%s) - START ) * 1000 ))
echo "build-app: $APP ($KIND) -> $OUT $BYTES bytes sha256 $HASH (${MS} ms)"
