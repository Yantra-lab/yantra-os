#!/usr/bin/env bash
# Rebuild every shipped app from its own source and prove the pixels match.
#
#   bash yantra-os/apps/_build/parity.sh            # every app in apps/*/
#   bash yantra-os/apps/_build/parity.sh arcade ink # just these
#
# For each app it screenshots the SHIPPED module, rebuilds the module from its
# source into /tmp, screenshots the REBUILT module, and prints one row:
#
#   app | shipped sha256 | rebuilt sha256 | shipped colours | rebuilt colours | MATCH/DIFFER
#
# `colours` is the distinct-colour count of a 1440x900 frame sampled on a 3-px
# grid — docs/DEMO-READY.md §7, measured by metrics.py. It is the project's
# official metric and the acceptance test here: the shipped module is the
# reference, and a rebuild whose frame has a different number of colours has
# lost (or gained) something real — a shader, a texture, a font rasteriser, a
# whole view. MATCH means the two counts are equal.
#
# Both frames are drawn from a directory holding that app's WHOLE folder —
# the shipped one from apps/<id>/ itself, the rebuilt one from a copy of it in
# $YANTRA_PARITY_DIR — because the engine resolves an asset as appDir/path. A
# module measured from a bare directory loses its art and reports fewer
# colours: apps/gallery read 1,120 there against its real 12,971.
#
# It also compares the two PNGs. `identical` in the summary counts rebuilds
# whose frame is not merely the same colour count but the same file byte for
# byte, which is the strongest statement available and the one most rebuilds
# here actually reach — two different modules, one frame.
#
# stdout is the table only; progress and every command's own output go to
# stderr. Exit status is 0 when every app built and matched, 1 otherwise, so
# the script can be a gate.
#
# Environment:
#   YANTRA_PARITY_DIR  where rebuilds and frames go (default /tmp/yantra-parity)
#   YANTRA_FRAMES      frames before the screenshot (default 8, as shot.sh)
#   YANTRA_ENGINE      the engine (default /tmp/stage1/yantra)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$(cd "$HERE/.." && pwd)"
OS="$(cd "$APPS/.." && pwd)"
REPO="$(cd "$OS/.." && pwd)"
OUTDIR="${YANTRA_PARITY_DIR:-/tmp/yantra-parity}"
FRAMES="${YANTRA_FRAMES:-8}"
export YANTRA_FRAMES="$FRAMES"

# --pinned compares the TRACKED source at HEAD against the TRACKED module at
# HEAD, extracted with `git archive`. Without it the table compares the working
# tree, which is a moving target: other lanes edit app sources and modules while
# a sweep runs, and a row that says DIFFER then means "two different sources",
# not "the rebuild is wrong". Measured: kart read 3209|3209 in one sweep and
# 3209|3163 in the next, hours apart, because its source had changed under it.
PINNED=0
if [ "${1:-}" = "--pinned" ]; then PINNED=1; shift; fi

mkdir -p "$OUTDIR"
SRCDIR="$APPS"
if [ "$PINNED" = "1" ]; then
  command -v git > /dev/null 2>&1 || { echo "parity: --pinned needs git" >&2; exit 1; }
  SRCDIR="$OUTDIR/head"
  rm -rf "$SRCDIR"
  mkdir -p "$SRCDIR"
  git -C "$REPO" archive HEAD yantra-os/apps \
    | tar -x -C "$SRCDIR" --strip-components=2 \
    || { echo "parity: git archive HEAD yantra-os/apps failed" >&2; exit 1; }
  [ -f "$SRCDIR/arcade/app.nim" ] || { echo "parity: the pinned tree has no apps/arcade/app.nim" >&2; exit 1; }
fi
export YANTRA_APPS_DIR="$SRCDIR"
TSV="$OUTDIR/parity.tsv"
: > "$TSV"

# Which apps to do: the arguments, else every directory under apps/ with a
# source file. app.nim is the contract — a directory without one is not an app
# this script can rebuild, and it says so rather than skipping silently.
if [ "$#" -gt 0 ]; then
  SELECTED=("$@")
else
  SELECTED=()
  for d in "$SRCDIR"/*/; do
    id="$(basename "$d")"
    [ "$id" = "_build" ] && continue
    [ -f "$d/app.nim" ] && SELECTED+=("$id")
  done
fi
[ "${#SELECTED[@]}" -gt 0 ] || { echo "parity: no apps found under $APPS" >&2; exit 1; }

esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }

printf 'app | shipped sha256 | rebuilt sha256 | shipped colours | rebuilt colours | verdict\n'
printf -- '--- | --- | --- | ---: | ---: | ---\n'

fails=0
built=0
matched=0
identical=0

for app in "${SELECTED[@]}"; do
  src="$SRCDIR/$app/app.nim"
  shipped="$SRCDIR/$app/app.wasm"
  d="$OUTDIR/$app"
  mkdir -p "$d"

  s_sha="-"; r_sha="-"; s_col="-"; r_col="-"; verdict="DIFFER"; note=""
  reason=""

  if [ ! -f "$src" ]; then
    verdict="NO SOURCE"; reason="apps/$app/app.nim is missing"
  elif [ ! -f "$shipped" ]; then
    verdict="NO SHIPPED"; reason="apps/$app/app.wasm is missing — nothing to compare against"
  else
    s_sha="$(sha256sum "$shipped" | cut -d' ' -f1)"
    if ! s_line="$(bash "$HERE/shot.sh" "$shipped" "$d/shipped.png" "$FRAMES" 2> "$d/shipped.log")"; then
      verdict="SHIPPED FAILED"; reason="the shipped module did not render: $(tail -2 "$d/shipped.log" | tr '\n' ' ')"
    else
      s_col="$(echo "$s_line" | awk '{print $4}')"
      s_ink="$(echo "$s_line" | awk '{print $5}')"
      echo "parity: $app shipped  $s_col colours ink $s_ink" >&2
      # STAGE THE WHOLE APP FOLDER, not the module alone: the engine resolves
      # an app's assets as appDir/path (render/native/engine.nim:1193-1201), so
      # a module measured from a bare /tmp directory measures a missing-asset
      # state — apps/gallery read 1,120 colours there against its real 12,971.
      # Copying apps/<id>/ puts art/, assets/ and brand/ beside the rebuilt
      # module, and the frame is drawn with the same assets as the shipped one.
      cp -a "$SRCDIR/$app/." "$d/" 2>/dev/null || true
      rm -f "$d/app.wasm"
      if [ -d "$SRCDIR/$app/art" ] || [ -d "$SRCDIR/$app/assets" ] || [ -d "$SRCDIR/$app/brand" ]; then
        echo "parity: $app staged with its asset folders ($(cd "$d" && ls -d art assets brand 2>/dev/null | tr '\n' ' '))" >&2
      fi
      if ! bash "$HERE/build-app.sh" "$app" "$d/app.wasm" > "$d/build.log" 2>&1; then
        verdict="BUILD FAILED"; reason="$(tail -3 "$d/build.log" | tr '\n' ' ')"
      else
        built=$((built + 1))
        r_sha="$(sha256sum "$d/app.wasm" | cut -d' ' -f1)"
        if ! r_line="$(bash "$HERE/shot.sh" "$d/app.wasm" "$d/rebuilt.png" "$FRAMES" 2> "$d/rebuilt.log")"; then
          verdict="RENDER FAILED"; reason="the rebuilt module did not render: $(tail -2 "$d/rebuilt.log" | tr '\n' ' ')"
        else
          r_col="$(echo "$r_line" | awk '{print $4}')"
          r_ink="$(echo "$r_line" | awk '{print $5}')"
          echo "parity: $app rebuilt $r_col colours ink $r_ink" >&2
          if [ "$s_col" = "$r_col" ]; then
            verdict="MATCH"
            matched=$((matched + 1))
            if cmp -s "$d/shipped.png" "$d/rebuilt.png"; then
              identical=$((identical + 1))
              note="frame identical byte for byte"
            else
              note="same colour count, frames differ"
            fi
          else
            note="colours ${s_col} -> ${r_col}"
          fi
        fi
      fi
    fi
  fi

  [ "$verdict" = "MATCH" ] || fails=$((fails + 1))
  row="$(esc "$app") | $(esc "$s_sha") | $(esc "$r_sha") | $s_col | $r_col | $verdict"
  printf '%s\n' "$row"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "$s_sha" "$r_sha" "$s_col" "$r_col" "$verdict" "$note" >> "$TSV"
  # The reason for a non-MATCH row, and what was actually built, on stderr so
  # the table on stdout stays a table.
  [ "$verdict" = "MATCH" ] && echo "parity: $app MATCH ($note)" >&2 || echo "parity: $app $verdict — $reason" >&2
done

echo
echo "parity: ${matched}/${#SELECTED[@]} apps match the shipped frame ($identical of them byte-identical PNGs); ${built} rebuilt from source"
echo "parity: table saved as TSV (full hashes, notes) in $TSV"
echo "parity: frames and rebuilds in $OUTDIR/<app>/{shipped.png,rebuilt.png,app.wasm}"
[ "$fails" -eq 0 ] || echo "parity: ${fails} app(s) differ — see the rows above"
[ "$fails" -eq 0 ]
