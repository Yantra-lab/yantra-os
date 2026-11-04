#!/usr/bin/env bash
# tools/check.sh — the mechanical gate. A branch may be merged ONLY if this prints
# "CHECK: PASS". It is deliberately dumb and strict so that no reviewer (human or
# AI) has to read the diff to know nothing was broken or faked.
#
#   bash tools/check.sh            # check the current branch against main
#
# Agents: you may NOT edit this file, tools/baseline.txt, tools/merge.sh,
# tools/hooks/, AGENTS.md or .gitignore. The check itself enforces that.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${YANTRA_ROOT:-$(cd "$HERE/.." && pwd)}"   # merge.sh runs main's copy of this file from a temp dir
cd "$ROOT"

fails=0
bad()  { echo "  FAIL  $*"; fails=$((fails + 1)); }
ok()   { echo "  ok    $*"; }

branch="$(git rev-parse --abbrev-ref HEAD)"
base="$(git merge-base main HEAD)"
echo "== check: branch '$branch' vs main"

# --- 1. never on main -------------------------------------------------------
[ "$branch" = "main" ] && bad "you are on main — work on a branch named agent/<task-id>-<slug>" \
                       || ok "on a branch"

# --- 2. clean tree (everything committed) -----------------------------------
clean_at_start=0
[ -z "$(git status --porcelain)" ] && { clean_at_start=1; ok "working tree clean"; } \
                                   || bad "uncommitted changes — commit or discard first"

# --- 3. protected files untouched ------------------------------------------
protected='^(tools/test-edits\.txt|tools/scopes\.txt|tools/check\.sh|tools/merge\.sh|tools/wt\.sh|tools/baseline\.txt|tools/hooks/|AGENTS\.md|\.gitignore|\.board/AGENT_PROMPT\.md)'
touched="$(git diff --name-only "$base"..HEAD | grep -E "$protected" || true)"
[ -z "$touched" ] && ok "protected files untouched" \
                  || bad "protected files changed: $(echo $touched)"

# --- 4. forbidden files never committed -------------------------------------
forbidden="$(git diff --name-only --diff-filter=AM "$base"..HEAD \
  | grep -Ei '(^third_party/|/vendor/|\.(exe|dll|wasm|opt|o|a|lib|pdb|zip|gz|7z)$|gnupg|\.env)' || true)"
[ -z "$forbidden" ] && ok "no binaries/toolchains/secrets" \
                    || bad "forbidden files: $(echo $forbidden)"

# --- 5. no test file deleted, no assertion removed --------------------------
testpat='(^|/)(t_[^/]*\.nim|test_[^/]*|[^/]*_test\.nim|run_tests\.sh|verify_[^/]*\.mjs)$|/tests/'
deleted="$(git diff --name-only --diff-filter=D "$base"..HEAD | grep -E "$testpat" || true)"
[ -z "$deleted" ] && ok "no test files deleted" || bad "test files deleted: $(echo $deleted)"
removed_asserts="$(git diff "$base"..HEAD -- $(git diff --name-only "$base"..HEAD | grep -E "$testpat") 2>/dev/null \
  | grep -E '^-[^-].*(doAssert|assert|check\(|expect|ok |bad )' | wc -l)"
[ "$removed_asserts" -eq 0 ] && ok "no assertions removed" \
                             || bad "$removed_asserts assertion line(s) removed from tests"

# --- 5b. anti-slop rules (added lines only) ---------------------------------
# Source = code that is not a test and not docs/board.
srcpat='\.(nim|nims|c|cc|cpp|h|hpp|mjs|js|py|sh)$'
testfiles="$(git diff --name-only --diff-filter=AM "$base"..HEAD | grep -E "$testpat" || true)"
srcfiles="$(git diff --name-only --diff-filter=AM "$base"..HEAD | grep -E "$srcpat" \
  | grep -vE "$testpat" | grep -vE '^(docs/|\.board/|parity/|third_party/)' || true)"
added_test="$( [ -n "$testfiles" ] && git diff "$base"..HEAD -- $testfiles | grep -E '^\+[^+]' || true)"
added_src="$( [ -n "$srcfiles" ] && git diff "$base"..HEAD -- $srcfiles | grep -E '^\+[^+]' || true)"

# (a) source changed => new assertions must be added in tests
new_asserts="$(printf '%s\n' "$added_test" | grep -cE '(check[ (]|doAssert|assert[ (]|expect[ (]|require[ (]|\bok |\bbad |PASS|FAIL)' || true)"
if [ -n "$srcfiles" ] && [ "${new_asserts:-0}" -eq 0 ]; then
  bad "source changed but no new test assertions were added (every change needs tests)"
else
  ok "tests added with source changes (${new_asserts:-0} new assertion lines)"
fi

# (b) tautological / disabled tests
taut="$( { printf '%s\n' "$added_test" | grep -nE \
  '(check|doAssert|assert|require)\s*\(?\s*(true|not false|1\s*==\s*1|0\s*==\s*0)\s*\)?\s*$|when false|\bskip\b|pending\(|disabled' ;
  printf '%s\n' "$added_test" | grep -nE '(check|doAssert|assert)\s*\(?\s*([A-Za-z_][A-Za-z0-9_.]*)\s*==\s*\2\s*\)?\s*$' ; } || true)"
# assertions whose arguments are only literals (e.g. check("A4", 1, 1)) test nothing
litonly="$(printf '%s\n' "$added_test" | grep -E '\b(check|doAssert|assert|require|expect)\b' \
  | sed -E 's/"([^"\]|\.)*"//g; s/^\+[[:space:]]*//; s/\b(check|doAssert|assert|require|expect)\b//' \
  | grep -vE '[A-Za-z_]' || true)"
[ -n "$litonly" ] && taut="$taut literal-only assertion: $(printf '%s' "$litonly" | head -2 | tr '\n' ' ')"
# test scripts must not be neutered
neuter="$(printf '%s\n' "$added_test" | grep -nE '^\+[^#]*[A-Za-z_]+=(""|'"''"')\s*$|set \+e|quit\(0\)' || true)"
[ -n "$neuter" ] && taut="$taut neutered check: $(printf '%s' "$neuter" | head -2 | tr '\n' ' ')"
[ -z "$taut" ] && ok "no tautological or disabled tests" \
               || bad "tautological/disabled test lines: $(printf '%s' "$taut" | head -3 | tr '\n' ' ')"

# (c) slop markers in new source lines
# Markers are case-sensitive (TODO, not "todo.nim"); phrases are case-insensitive.
slop="$( { printf '%s\n' "$added_src" | grep -nE '\b(TODO|FIXME|XXX|HACK)\b' ;
  printf '%s\n' "$added_src" | grep -niE \
  'not implemented|unimplemented|placeholder (implementation|code|logic|value|for now)|(#|//) *placeholder|\bstub(bed)?\b|\bdummy\b|lorem ipsum|except\s*:\s*discard|except [A-Za-z]+\s*:\s*discard|defined\((test|testing)\)|getEnv\("(CI|TEST|YANTRA_TEST)|isTestMode|--warnings:off|warning\[[A-Za-z]+\]:\s*off' ; } || true)"
[ -z "$slop" ] && ok "no slop markers in new source" \
               || bad "slop markers in new source: $(printf '%s' "$slop" | head -3 | tr '\n' ' ')"

# (d) task report present for agent branches
tid="$(printf '%s' "$branch" | sed -nE 's#^agent/([A-Za-z0-9]+)-.*#\1#p')"
if [ -n "$tid" ]; then
  git diff --name-only "$base"..HEAD | grep -qx ".board/reports/$tid.md" \
    && ok "report .board/reports/$tid.md present" \
    || bad "missing .board/reports/$tid.md for branch $branch"
  if git diff --name-only "$base"..HEAD | grep -qE '^\.board/STATUS[-A-Za-z0-9]*\.md$'; then
    ok ".board/STATUS file updated"
  else
    bad ".board/STATUS.md (or STATUS-<agent>.md) not updated on this branch"
  fi
  if git diff "$base"..HEAD -- '.board/MODELS*.md' | grep -E '^\+' | grep -qF "| $tid |"; then
    ok ".board/MODELS.md has a line for $tid"
  else
    bad ".board/MODELS.md: no line added for $tid"
  fi
fi

# (e) scope: the branch may only change paths allowed for its task (tools/scopes.txt)
if [ -n "$tid" ]; then
  best=""; bestre=""
  while read -r pfx re; do
    case "$pfx" in ''|\#*) continue;; esac
    case "$tid" in "$pfx"*) [ ${#pfx} -gt ${#best} ] && { best="$pfx"; bestre="$re"; };; esac
  done < "$ROOT/tools/scopes.txt"
  always="^(\.board/reports/$tid\.md|\.board/(STATUS|MODELS)[-A-Za-z0-9]*\.md|\.board/QUESTIONS\.md|docs/decisions/|docs/vendor/)"
  if [ -z "$best" ]; then
    bad "task $tid has no scope in tools/scopes.txt — ask in QUESTIONS.md"
  else
    outside="$(git diff --name-only "$base"..HEAD | grep -vE "$always" | grep -vE "$bestre" || true)"
    [ -z "$outside" ] && ok "all changes inside scope '$best'" \
                      || bad "changes outside scope '$best': $(echo $outside | cut -c1-200)"
  fi
fi

# (f) existing test files are append-only (no changed or deleted lines)
existing_tests="$(git diff --name-only --diff-filter=M "$base"..HEAD | grep -E "$testpat" || true)"
# Owner/Claude-authorised exceptions for this task (tools/test-edits.txt, protected)
if [ -n "$tid" ] && [ -f "$ROOT/tools/test-edits.txt" ]; then
  allowed="$(awk -v t="$tid" '$1 == t {print $2}' "$ROOT/tools/test-edits.txt")"
  for a in $allowed; do existing_tests="$(printf '%s
' "$existing_tests" | grep -vxF "$a" || true)"; done
  [ -n "$allowed" ] && ok "authorised test edits for $tid: $(echo $allowed)"
fi
changed_test_lines="$( [ -n "$existing_tests" ] && git diff "$base"..HEAD -- $existing_tests | grep -cE '^-[^-]' || true)"
[ "${changed_test_lines:-0}" -eq 0 ] && ok "existing tests untouched (append-only)" \
  || bad "$changed_test_lines line(s) changed/removed in existing test files: $(echo $existing_tests)"

# (g) every NEW exported routine is referenced by some test file
newsyms="$(printf '%s\n' "$added_src" | sed -nE 's/^\+\s*(proc|func|template|macro|method|iterator|converter)\s+`?([A-Za-z0-9_]+)`?\*.*/\2/p' | sort -u)"
untested=""
for sym in $newsyms; do
  git grep -qw "$sym" HEAD -- $(git ls-tree -r --name-only HEAD | grep -E "$testpat") 2>/dev/null || untested="$untested $sym"
done
[ -z "$untested" ] && ok "every new exported routine is used by a test" \
                   || bad "new exported routines with no test reference:$untested"

# --- 6. diff size -----------------------------------------------------------
changed="$(git diff --numstat "$base"..HEAD | awk '{s+=$1+$2} END {print s+0}')"
[ "$changed" -le 400 ] && ok "diff size $changed lines (<= 400)" \
                       || bad "diff is $changed lines — split the task (max 400)"

# --- 7. the suites, rebuilt from source -------------------------------------
echo "== running suites (this takes a few minutes)"
# Suites are DISCOVERED, so moving folders never requires editing this file:
#   - every example app: any .nim under examples/ that does `import yantra` or starts an
#     `app`/`yantraRun` block at top level (yantra is imported by default, INBOX 30)
#   - every suite: any run_tests.sh outside third_party/ and vendor/
#   - every verifier: examples/**/verify_*.mjs, run against its sibling .wasm
# The baseline (tools/baseline.txt) stops suites from silently disappearing.
run_all() {  # rebuild every example from source, run every suite and verifier
  find examples -name '*.wasm' -delete 2>/dev/null
  for src in $(grep -rlE '^(import yantra|app "|yantraRun)' examples --include='*.nim' | sort); do
    bash tools/build-wasm.sh "$src" "${src%.nim}.wasm" 2>&1 | tail -1
  done
  find examples -type d -name nimcache -prune -exec rm -rf {} + ; find examples -name minilibc.o -delete
  for suite in $(find . -name run_tests.sh -not -path './third_party/*' -not -path '*/vendor/*' -not -path './.git/*' | sort); do
    echo "## suite $suite"
    # a suite that crashes or exits non-zero without printing FAIL is still a failure
    bash "$suite" || echo "FAIL suite $suite exited with an error"
  done
  for v in $(find examples -name 'verify_*.mjs' | sort); do
    w="$(dirname "$v")/$(basename "$v" .mjs | sed 's/^verify_//').wasm"
    echo "## verifier $v"
    node "$v" "$w" || echo "FAIL verifier $v exited with an error"
  done
}
log="$(mktemp)"
run_all >"$log" 2>&1

wasm_ok="$(grep -c 'build-wasm: wrote' "$log")"
pass="$(grep -cE '^\s*PASS' "$log")"
failn="$(grep -cE '^\s*FAIL' "$log")"
# verify_*.mjs print "=== N/M checks passed ===" — sum N over all verifiers.
verify="$(grep -oE '^=== [0-9]+/[0-9]+ checks passed' "$log" | grep -oE '^=== [0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')"
. "$HERE/baseline.txt"

[ "$wasm_ok" -ge "$MIN_WASM" ]   && ok "examples built: $wasm_ok (>= $MIN_WASM)"   || bad "examples built: $wasm_ok (< $MIN_WASM)"
[ "$failn" -eq 0 ]               && ok "suite FAIL lines: 0"                        || bad "suite FAIL lines: $failn"
[ "$pass" -ge "$MIN_PASS" ]      && ok "suite PASS lines: $pass (>= $MIN_PASS)"     || bad "suite PASS lines: $pass (< $MIN_PASS)"
[ "${verify:-0}" -ge "$MIN_VERIFY" ] && ok "verify_hello: $verify (>= $MIN_VERIFY)" || bad "verify_hello: ${verify:-0} (< $MIN_VERIFY)"

echo "== suite summary"
grep -E '^\s*(PASS|FAIL)|sweep:|checks passed|^## ' "$log" | sed 's/^/  | /'
cp "$log" "$ROOT/.board/last-check.log" 2>/dev/null || true
printf "GOT_WASM=%s
GOT_PASS=%s
GOT_VERIFY=%s
" "$wasm_ok" "$pass" "${verify:-0}" > "$ROOT/.board/last-check.env"
rm -f "$log"

# --- 8. red check: new tests must FAIL when your source change is reverted ------
# Proves the tests actually test the change. A test that passes with and without
# the change (e.g. check("A4", 1, 1)) proves nothing.
if [ -n "$srcfiles" ]; then
  echo "== red check: re-running everything with your source changes reverted"
  addsrc="$(git diff --name-only --diff-filter=A "$base"..HEAD | grep -E "$srcpat" | grep -vE "$testpat" | grep -vE '^(docs/|\.board/|parity/|third_party/)' || true)"
  modsrc="$(git diff --name-only --diff-filter=M "$base"..HEAD | grep -E "$srcpat" | grep -vE "$testpat" | grep -vE '^(docs/|\.board/|parity/|third_party/)' || true)"
  # Suites regenerate tracked files (protocol/gen.nim writes props.md, wire.nim…) from the
  # reverted schema, so put back every tracked file — only when the tree was clean before,
  # so nobody's uncommitted work is ever touched.
  restore_src() {
    git checkout -q HEAD -- $srcfiles 2>/dev/null || true
    if [ "$clean_at_start" = 1 ]; then git checkout -q HEAD -- . 2>/dev/null || true; fi
    # objects built from the reverted source must not be linked into the next build
    find . \( -path ./third_party -o -path '*/vendor' -o -path ./.git \) -prune -o -type d -path '*/build/nimcache' -print 2>/dev/null \
      | while read -r d; do rm -rf "$d"; done
  }
  trap restore_src EXIT
  [ -n "$modsrc" ] && git checkout -q "$base" -- $modsrc
  for f in $addsrc; do rm -f "$f"; done
  redlog="$(mktemp)"
  run_all >"$redlog" 2>&1
  restore_src; trap - EXIT
  redfail="$(grep -cE '^\s*FAIL' "$redlog")"
  cp "$redlog" "$ROOT/.board/last-red-check.log" 2>/dev/null || true
  rm -f "$redlog"
  if [ -n "$(git status --porcelain)" ]; then bad "red check left the tree dirty (gate bug) — report to Claude"; fi
  [ "$redfail" -gt 0 ] && ok "red check: $redfail failure(s) without your change — the tests really test it" \
                       || bad "red check: everything PASSES with your source change reverted — your tests do not test your change"
fi

echo
if [ "$fails" -eq 0 ]; then echo "CHECK: PASS"; exit 0
else echo "CHECK: FAIL ($fails problem(s))"; exit 1; fi
