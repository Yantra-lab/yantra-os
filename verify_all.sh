#!/usr/bin/env bash
# verify_all.sh — the one command to check this repository.
#
# WHAT IT DOES
#   Runs every app's module verifier, in order, and prints one table. No API
#   keys, no GPU, no network, no toolchain: the apps ship as prebuilt `.wasm`
#   and the verifier is plain Node. It then proves the JSON documents next to
#   each app still match the modules they were exported from.
#
# WHAT A PASS MEANS
#   The module instantiates in a sandbox and builds a live UI tree. It does not
#   mean anything about pixels — see the note printed at the end.
#
# USAGE
#   bash verify_all.sh                  # module verifiers + JSON freshness (~20 s)
#   bash verify_all.sh --interactions   # also the behaviour suites (minutes)
#   bash verify_all.sh --help
#
# EXIT
#   0 every check passed; 1 something failed; 2 this machine cannot run it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
MODE=modules
for arg in "$@"; do
  case "$arg" in
    --interactions) MODE=all ;;
    --help|-h) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "verify_all: unknown flag $arg (try --help)" >&2; exit 2 ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "verify_all: node is required (>=18) and was not found" >&2; exit 2; }
NODE_V="$(node --version)"

if git rev-parse --git-dir >/dev/null 2>&1; then
  HEAD_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  DIRTY="$(git status --porcelain 2>/dev/null | head -n 1)"
  [ -n "$DIRTY" ] && HEAD_SHA="$HEAD_SHA (working tree has uncommitted changes)"
else
  HEAD_SHA="not a git checkout"
fi

echo "Yantra OS — verification"
echo "  repo    $ROOT"
echo "  commit  $HEAD_SHA"
echo "  node    $NODE_V"
echo "  mode    $MODE  (no keys, no GPU, no network, no toolchain)"
echo

# Group digits without depending on the machine's locale.
commas() {
  local n="$1" out=""
  while [ "${#n}" -gt 3 ]; do out=",${n: -3}${out}"; n="${n:0:${#n}-3}"; done
  printf '%s%s' "$n" "$out"
}

HDR="$(printf '%-11s %12s %14s %9s  %s' 'app' 'bytes' 'sha256(12)' 'verifier' 'measured at instantiation')"
SEP="$(printf '%.0s-' {1..96})"
echo "$HDR"
echo "$SEP"

PASS_N=0
FAIL_N=0
TOTAL=0
FAILED_APPS=""

for wasm in apps/*/app.wasm; do
  app="$(basename "$(dirname "$wasm")")"
  bytes="$(wc -c < "$wasm" | tr -d ' ')"
  total_fmt="$(commas "$bytes")"
  sha="$(sha256sum "$wasm" | cut -c1-12)"
  TOTAL=$((TOTAL + bytes))

  out="$(node tools/verify-wasm.mjs "apps/$app" 2>&1)"
  rc=$?
  detail="$(printf '%s\n' "$out" | sed -n 's/^  ui tree     \(.*\)$/\1/p' | cut -c1-40)"
  ms="$(printf '%s\n' "$out" | sed -n 's/^  instantiate \([0-9.]*\) ms$/\1/p')"
  if [ $rc -eq 0 ]; then
    PASS_N=$((PASS_N + 1))
    verdict="PASS"
  else
    FAIL_N=$((FAIL_N + 1))
    FAILED_APPS="$FAILED_APPS $app"
    verdict="FAIL"
  fi
  printf '%-11s %12s %14s %9s  %s\n' "$app" "$total_fmt" "$sha" "$verdict" "${ms} ms, ${detail}"
done

echo "$SEP"
printf '%-11s %12s %14s %9s\n' "total" "$(commas "$TOTAL")" "bytes" "$PASS_N/$((PASS_N + FAIL_N)) PASS"

echo
echo "JSON freshness (apps/<app>/app.yantra.json must match its module and source):"
if node tools/export-json.mjs --check; then
  JSON_OK=1
else
  JSON_OK=0
  FAIL_N=$((FAIL_N + 1))
fi

if [ "$MODE" = all ]; then
  echo
  echo "Behaviour suites (web/runner/tests):"
  SUITE_PASS=0
  SUITE_FAIL=0
  SUITE_SKIP=0
  for t in calc chess dna gallery notes todo typewriter; do
    if [ ! -f "web/runner/tests/$t.mjs" ]; then
      SUITE_SKIP=$((SUITE_SKIP + 1)); printf '  %-10s SKIP  no suite in this tree\n' "$t"; continue
    fi
    out="$(timeout 600 node "web/runner/tests/$t.mjs" 2>&1)"
    rc=$?
    count="$(printf '%s\n' "$out" | grep -oE '[0-9]+ (assertions passed|passed)' | tail -n 1)"
    if [ $rc -eq 0 ]; then
      SUITE_PASS=$((SUITE_PASS + 1)); printf '  %-10s PASS  %s\n' "$t" "${count:-ok}"
    elif [ $rc -eq 124 ]; then
      SUITE_FAIL=$((SUITE_FAIL + 1)); printf '  %-10s FAIL  timed out after 600 s\n' "$t"
    else
      SUITE_FAIL=$((SUITE_FAIL + 1)); printf '  %-10s FAIL  %s\n' "$t" "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-70)"
    fi
  done
  # These two suites need things this release tree does not contain; say so
  # rather than hiding them.
  printf '  %-10s SKIP  needs examples/shell/shell.wasm, not in this tree\n' shell
  printf '  %-10s SKIP  rebuilds apps (needs third_party/wasi-sdk), not in this tree\n' desktop_editor_mcp
  SUITE_SKIP=$((SUITE_SKIP + 2))
  echo "  suites: $SUITE_PASS passed, $SUITE_FAIL failed, $SUITE_SKIP skipped"
  if [ $SUITE_FAIL -gt 0 ]; then FAIL_N=$((FAIL_N + SUITE_FAIL)); fi
fi

echo
echo "NOTE  a module verifier instantiates the module and reads the UI tree it built."
echo "      It renders nothing, so it proves the module runs, not that it looks right."
echo

if [ $FAIL_N -eq 0 ] && [ $JSON_OK -eq 1 ]; then
  echo "RESULT: PASS — $PASS_N/${PASS_N} modules verified, JSON documents fresh"
  exit 0
fi
echo "RESULT: FAIL — $FAIL_N problem(s):$FAILED_APPS"
exit 1
