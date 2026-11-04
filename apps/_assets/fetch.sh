#!/usr/bin/env bash
# fetch.sh — pull the GPU fleet's artefacts into the repo, hash-verified.
#
# The fleet writes to /tmp/gpu-fleet/out/ (images from FLUX.2-klein-4B, meshes from
# Hunyuan3D-2.1). That directory is a scratch space: it can be empty, it can hold
# another lane's files, and its contents can be replaced under you. So nothing is
# copied on trust — a file is copied only if `sha256sum` reads it twice and agrees
# with itself, and the copy is verified AGAIN after it lands. A file that cannot be
# hashed is refused, not copied.
#
# Usage
#   ./fetch.sh                              # copy every *.png/*.glb into the demo's assets/
#   ./fetch.sh --dest apps/poster/assets    # somewhere else
#   ./fetch.sh --as poster.png:/tmp/gpu-fleet/out/flux-klein-123.png   # rename on the way in
#   ./fetch.sh --list                       # hash and print, copy nothing
#
# Exit 0 always when nothing is wrong — an empty fleet is a fact, not a failure.
#
# Prints, for every artefact, a line already shaped like PROVENANCE.tsv's first
# three columns (file, bytes, sha256) so a row is pasted from a measurement.
set -euo pipefail

SRC="${GPU_FLEET_OUT:-/tmp/gpu-fleet/out}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/demo/assets"
MODE="copy"
MAPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="${2:?--dest needs a directory}"; shift 2 ;;
    --dest=*) DEST="${1#--dest=}"; shift ;;
    --list) MODE="list"; shift ;;
    --as) MAPS+=("${2:?--as needs name:path}"); shift 2 ;;
    --as=*) MAPS+=("${1#--as=}"); shift ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "fetch: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

hash_of() {
  # One number, read once. Fails loudly rather than returning "" (an empty hash
  # that compares equal to another empty hash is how a bad copy passes).
  local h
  h="$(sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1)" || true
  [ "${#h}" -eq 64 ] || return 1
  printf '%s' "$h"
}

emit() {  # emit <source-path> <name-in-repo>
  local src="$1" name="$2" bytes h1 h2 dst
  bytes="$(stat -c%s -- "$src" 2>/dev/null || stat -f%z -- "$src")" || {
    echo "fetch: REFUSED (cannot stat) $src" >&2; return 1; }
  h1="$(hash_of "$src")" || { echo "fetch: REFUSED (cannot hash) $src" >&2; return 1; }

  if [ "$MODE" = "list" ]; then
    printf '%s\t%s\t%s\n' "$src" "$bytes" "$h1"
    return 0
  fi

  mkdir -p -- "$DEST"
  dst="$DEST/$name"
  if [ -f "$dst" ] && [ "$(hash_of "$dst" || true)" = "$h1" ]; then
    printf '%s\t%s\t%s\t(already current)\n' "$name" "$bytes" "$h1"
    return 0
  fi

  cp -- "$src" "$dst"
  h2="$(hash_of "$dst")" || { echo "fetch: REFUSED (copy unreadable) $dst" >&2; rm -f -- "$dst"; return 1; }
  if [ "$h1" != "$h2" ]; then
    echo "fetch: REFUSED (hash changed in flight) $dst" >&2
    echo "  source $h1" >&2
    echo "  copy   $h2" >&2
    rm -f -- "$dst"
    return 1
  fi
  printf '%s\t%s\t%s\n' "$name" "$bytes" "$h2"
}

if [ ! -d "$SRC" ]; then
  echo "no artefacts yet ($SRC does not exist)"
  exit 0
fi

# Explicit mappings win: they are how an artefact gets its canonical asset name.
if [ "${#MAPS[@]}" -gt 0 ]; then
  for m in "${MAPS[@]}"; do
    name="${m%%:*}"; path="${m#*:}"
    [ -f "$path" ] || { echo "fetch: no such artefact: $path" >&2; exit 1; }
    emit "$path" "$name"
  done
  exit 0
fi

shopt -s nullglob
found=("$SRC"/*.png "$SRC"/*.glb)
shopt -u nullglob

if [ "${#found[@]}" -eq 0 ]; then
  echo "no artefacts yet"
  exit 0
fi

for f in "${found[@]}"; do
  emit "$f" "$(basename -- "$f")"
done
