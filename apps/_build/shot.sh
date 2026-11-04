#!/usr/bin/env bash
# Draw ONE frame from a Yantra module and measure it.
#
#   bash yantra-os/apps/_build/shot.sh <module.wasm> <out.png> [frames]
#
# Prints exactly one line — the whole, reproducible record of a frame:
#
#   /tmp/arcade.png 58154 1440x900 864 1.000
#   └ path          └ PNG bytes  └ WxH   └ distinct colours (3-px sample)  └ ink
#
# which is metrics.py's line (yantra-os/apps/_build/metrics.py, the metric in
# docs/DEMO-READY.md §7) and nothing else on stdout, so `shot.sh` output can be
# pasted into a table or `awk`ed without cleaning.
#
# WHAT RENDERS IT
#   /tmp/stage1/yantra --screenshot=<png> --frames=<n> <abs/path/app.wasm>
# The engine is a prebuilt stage-1 binary that takes a module path, steps it
# `frames` times and writes one PNG of its 1440x900 surface. It needs no X
# display on this box (measured: identical PNG with and without xvfb-run, e.g.
# apps/gallery3d bbfec72a… either way), no GPU and no database. Point
# YANTRA_ENGINE at a freshly built yantra-os/bin/yantra to use your own.
#
# `frames` defaults to 8. Frames matter for an app with an onTick or a clock:
# too few and you screenshot a blank first paint, so the number is part of the
# measurement and is printed on stderr with the engine's own line.
#
# Exits non-zero when the engine is missing, fails, or writes no PNG — never
# with a 0 that would let a blank frame pass as a result.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "shot: $*" >&2; exit 1; }

WASM="${1:?usage: shot.sh <module.wasm> <out.png> [frames]}"
PNG="${2:?usage: shot.sh <module.wasm> <out.png> [frames]}"
FRAMES="${3:-8}"

[ -f "$WASM" ] || die "no such module: $WASM"
case "$FRAMES" in ''|*[!0-9]*) die "frames must be a whole number, got '$FRAMES'" ;; esac
[ "$FRAMES" -gt 0 ] || die "frames must be at least 1"

ENGINE="${YANTRA_ENGINE:-/tmp/stage1/yantra}"
[ -x "$ENGINE" ] || die "no engine at $ENGINE — set YANTRA_ENGINE to a yantra binary
  (the lead's prebuilt one is /tmp/stage1/yantra; build one with
   bash yantra-os/tools/build-all.sh)"

# Absolute paths: the engine resolves the module from its own cwd.
WASM_ABS="$(cd "$(dirname "$WASM")" && pwd)/$(basename "$WASM")"
mkdir -p "$(dirname "$PNG")"
PNG_ABS="$(cd "$(dirname "$PNG")" && pwd)/$(basename "$PNG")"
rm -f "$PNG_ABS"

# The engine WRITES THE PNG and then does not always exit: apps/typewriter
# (audio, its own tick) wrote its frame and sat there for 11 minutes, measured.
# So the render is bounded, and a bounded render that produced a PNG is a
# measurement, not a failure — the frame is on disk and it is the one the app
# drew. YANTRA_SHOT_TIMEOUT seconds (default 30; 10 gave the same PNG
# sha256 as 120, so the frame is written long before the timeout).
TIMEOUT="${YANTRA_SHOT_TIMEOUT:-30}"
run() { timeout -s KILL "$TIMEOUT" "$ENGINE" --screenshot="$PNG_ABS" --frames="$FRAMES" "$WASM_ABS"; }

RC=0
OUT="$(run 2>&1)" || RC=$?
if [ "$RC" -ne 0 ]; then
  # A module that trapped wrote its frame and still failed the run; its own
  # words say so, and no retry will change the answer.
  case "$OUT" in
    *"export not found"*|*crashed=*)
      die "module trapped on $WASM_ABS:
$OUT" ;;
  esac
  case "$RC" in
    124|137)
      # The bounded exit. The frame is on disk; it is what the app drew.
      echo "shot: engine did not exit within ${TIMEOUT}s; measuring the frame it wrote" >&2 ;;
    *)
      # Some boxes only give the engine a GL context under a virtual X server,
      # so there is one retry rather than a hard dependency on one.
      command -v xvfb-run > /dev/null 2>&1 || die "engine failed on $WASM_ABS:
$OUT"
      echo "shot: direct render failed, retrying under xvfb-run" >&2
      RC2=0
      OUT="$(timeout -s KILL "$TIMEOUT" xvfb-run -a "$ENGINE" --screenshot="$PNG_ABS" \
        --frames="$FRAMES" "$WASM_ABS" 2>&1)" || RC2=$?
      case "$RC2" in
        0|124|137) : ;;
        *) die "engine failed on $WASM_ABS even under xvfb-run:
$OUT" ;;
      esac ;;
  esac
fi
[ -s "$PNG_ABS" ] || die "engine wrote no PNG to $PNG_ABS:
$OUT"

# The engine's own line ("frame 1440x900 -> /path") is evidence, not noise: it
# names the surface the frame came from. stderr, so stdout stays one clean row.
printf 'shot: %s frames -> %s\n' "$FRAMES" "$(printf '%s' "$OUT" | tr '\n' '|' | sed 's/|*$//')" >&2

python3 "$HERE/metrics.py" "$PNG_ABS"
