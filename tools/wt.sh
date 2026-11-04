#!/usr/bin/env bash
# tools/wt.sh <task-id-slug> — create an isolated worktree for a subagent.
#
#   bash tools/wt.sh E3-yoga   ->  ../yantra-wt/E3-yoga on branch agent/E3-yoga (from main)
#
# Toolchains are gitignored, so they are LINKED from the main folder into the
# worktree (Windows junctions); the full test suite then works there too.
# Remove when merged:  bash tools/wt.sh --remove <task>
#   NEVER use `git worktree remove --force` on these: it can follow the junctions
#   and delete the real toolchains. --remove unlinks the junctions first.
set -eu
if [ "${1:-}" = "--remove" ]; then
  t="${2:?usage: tools/wt.sh --remove <task-id-slug>}"
  HERE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  WT="$(cd "$HERE_ROOT/.." && pwd)/yantra-wt/$t"
  [ -d "$WT" ] || WT="$(cd "$(git -C "$HERE_ROOT" worktree list --porcelain | sed -n '1s/^worktree //p')/.." && pwd)/yantra-wt/$t"
  for j in third_party libs/nimwasmtime/vendor; do
    if [ -e "$WT/$j" ]; then
      w="$(cd "$(dirname "$WT/$j")" && pwd -W)/$(basename "$j")"
      powershell -NoProfile -Command "(Get-Item -LiteralPath '$w').Delete()"   # removes the link only
    fi
  done
  for j in third_party libs/nimwasmtime/vendor; do
    [ -e "$WT/$j" ] && { echo "wt.sh: junction $j still present — NOT deleting (would hit real toolchains)"; exit 1; }
  done
  git -C "$HERE_ROOT" worktree remove --force "$WT" 2>/dev/null || true
  git -C "$HERE_ROOT" worktree prune
  rm -rf "$WT" 2>/dev/null || true
  echo "removed worktree $WT (branch agent/$t kept)"
  exit 0
fi
t="${1:?usage: tools/wt.sh <task-id-slug>}"
HERE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Always the MAIN repo folder (first worktree), where the toolchains live.
ROOT="$(git -C "$HERE_ROOT" worktree list --porcelain | sed -n '1s/^worktree //p')"
ROOT="$(cd "$ROOT" && pwd)"
WT="$(cd "$ROOT/.." && pwd)/yantra-wt/$t"
mkdir -p "$(dirname "$WT")"
git -C "$ROOT" worktree add -q "$WT" -b "agent/$t" main
link() {  # link <path-relative-to-repo>  (Windows directory junction)
  [ -e "$ROOT/$1" ] || return 0
  mkdir -p "$(dirname "$WT/$1")"
  local dst src
  dst="$(cd "$(dirname "$WT/$1")" && pwd -W)/$(basename "$1")"
  src="$(cd "$ROOT/$1" && pwd -W)"
  powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$dst' -Target '$src' | Out-Null"
}
link third_party
link libs/nimwasmtime/vendor
[ -f "$ROOT/libs/nimwasmtime/build/wasmtime.dll" ] && cp "$ROOT/libs/nimwasmtime/build/wasmtime.dll" "$WT/libs/nimwasmtime/build/"
echo "worktree ready: $WT (branch agent/$t)"
