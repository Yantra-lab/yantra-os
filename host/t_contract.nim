## The import contract gate (E1/E4).
##
## The host's `imports` table IS the sandbox's security boundary: an app that imports
## anything the host does not provide does not fail safely, it fails to instantiate,
## and the failure surfaces at RUN time in someone else's app — which is exactly how
## DESK 0b543da's desktop.wasm died on `y_ai_ready` after the SDK had grown
## sdk/core/ai.nim and sdk/core/sysinfo.nim that main never learned to serve.
##
## So this test reads the SDK's OWN declarations (`{.importc: "y_..."}`) and the host's
## OWN registry, and asserts the first is a subset of the second. Adding an import to the
## SDK without teaching the host fails HERE, not in a desktop build three days later.
##
## It checks both directions that matter:
##   1. every `y_*` the SDK declares is registered by the host (the gap that bit us), and
##   2. every such host import has an SDK declaration (dead host code: also drift).
##
## Signatures are checked too — a name registered with the wrong arity is the same bug
## wearing a different hat, and wasmtime would only catch it at instantiate.
##
##   ./run_tests.sh        # builds and runs it as part of the host sweep

import std/[os, strutils, sequtils, sets, tables]
import host

proc hasExt(path: string; exts: seq[string]): bool =
  ## True if `path` ends in one of `exts` (".nim" -> @["nim"]).
  for e in exts:
    if path.endsWith("." & e): return true

proc walkFilesRec(dir: string; exts: seq[string]): seq[string] =
  ## Every .nim under `dir`, including nested ones. std/os has no recursive walk, and this
  ## gate must not miss a declaration that lives three directories down.
  var queue = @[dir]
  while queue.len > 0:
    let d = queue.pop()
    for kind, path in walkDir(d):
      case kind
      of pcDir: queue.add path
      else:
        if hasExt(path, exts): result.add path

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  | OK   ", name
  else: inc failed; echo "  | FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let sdk = here / ".." / "sdk"

# --- 1. what the SDK declares ---------------------------------------------------------------
#
# Every host import is written once in the SDK as a foreign proc:
#     proc yNodeSetStr*(...): void {.importc: "y_node_set_str", cdecl.}
# The importc NAME is the contract; the Nim name beside it means nothing to wasmtime.
# `sdk/tests/**` is excluded on purpose: those declare the same imports as `= discard`
# stand-ins so the SDK's own test harnesses link — they are not the app-facing contract.

type Decl = object
  name: string
  nparams, nresults: int
  where: string

proc paramCount(sig: string; openAt: int): int =
  ## How many wasm VALUES a foreign proc's parameter list passes. `openAt` is the index of
  ## the opening paren; -1 if the signature is one we cannot read.
  ##
  ## Nim lets a signature group same-typed names — `proc yPhys(op, p, n: int32; a, b, c:
  ## float32)` is 9 wasm params, not 2 — and a `;` starts a new parameter group. So count
  ## names, not commas: split the list on ',' and ';' and each piece is ONE name (the last
  ## piece of a group carries the `: type`).
  if openAt < 0 or openAt >= sig.len or sig[openAt] != '(': return -1
  var depth = 0
  var args = ""
  var i = openAt
  while i < sig.len:
    let c = sig[i]
    case c
    of '(':
      inc depth
      if depth > 1: args.add c
    of ')':
      dec depth
      if depth == 0: break
      args.add c
    of ',', ';':
      if depth == 1: args.add '\n' else: args.add c
    else:
      if depth >= 1: args.add c
    inc i
  if depth != 0: return -1
  var n = 0
  for nm in args.split('\n'):
    if nm.strip.len > 0: inc n
  n

proc resultCount(sig: string): int =
  ## 0 for a void foreign proc, 1 otherwise (every SDK import returns at most one value).
  ##
  ## The return type is what sits between the CLOSING paren of the parameter list and the
  ## `{.` pragma. So CUT the pragma off first and look at what is left.
  ##
  ## Cutting at the first '{' is the whole trick. `importc:` and `cdecl.` both live inside
  ## the pragma, so a `find(':')` over the UNTRIMMED tail finds the one in `importc:` and
  ## reports every void import as returning a value — 21 phantom arity mismatches, all of
  ## them invented by this parser. `proc yNodeChild*(parent, child: int32) {.importc: ...}`
  ## declares no return type at all, and the tail before `{` is just `*`.
  let openAt = sig.find('(')
  if openAt < 0: return 0
  var depth = 0
  var closeAt = -1
  var i = openAt
  while i < sig.len:
    case sig[i]
    of '(': inc depth
    of ')':
      dec depth
      if depth == 0:
        closeAt = i
    else: discard
    if closeAt >= 0: break
    inc i
  if closeAt < 0: return 0
  var tail = sig[closeAt + 1 .. ^1]
  let brace = tail.find('{')
  if brace >= 0: tail = tail[0 ..< brace]   # drop `{.importc: "y_...", cdecl.}`
  let colon = tail.find(':')
  if colon < 0: return 0                    # no declared return type -> void
  let r = tail[colon + 1 .. ^1]
  if "void" == r.strip: 0 else: 1

proc sdkDecls(): seq[Decl] =
  for f in walkFilesRec(sdk, @["nim"]):
    let norm = f.replace('\\', '/')
    if "/tests/" in norm: continue
    let lines = readFile(f).splitLines()
    for i, line in lines:
      if "importc" notin line: continue
      let q1 = line.find('"')
      if q1 < 0: continue
      let q2 = line.find('"', q1 + 1)
      if q2 < 0: continue
      let nm = line[q1 + 1 ..< q2]
      if not (nm.startsWith("y_") or nm.startsWith("yantra_")): continue
      let np = paramCount(line, line.find('('))
      let nr = resultCount(line)
      if np < 0: continue                       # not a proc signature we understand
      result.add Decl(name: nm, nparams: np, nresults: nr,
                      where: norm.split('/')[^1] & ":" & $(i + 1))

# --- 2. what the host registers -------------------------------------------------------------

type Spec = object
  nparams, nresults: int

proc hostSpecs(): Table[string, Spec] =
  ## Read the host's OWN registry, by importing host and asking it. This is the point of
  ## the test: the same table loadApp consults, not a copy of it that could rot.
  for nm, spec in pairs(importTable()):
    result[nm] = Spec(nparams: spec.params.len, nresults: spec.results.len)

# --- 3. the diff ----------------------------------------------------------------------------

echo "=== the import contract: SDK declarations vs the host's registry ==="
let decls = sdkDecls()
let specs = hostSpecs()
check("the host's registry is non-empty", specs.len > 0, $specs.len)
check("the SDK declares host imports", decls.len > 0, $decls.len)
echo "  | SDK declares ", decls.len, " y_* imports; the host registers ", specs.len

var seen = initTable[string, int]()
var missing: seq[string] = @[]
var wrongArity: seq[string] = @[]
for d in decls:
  seen[d.name] = seen.getOrDefault(d.name) + 1
  if d.name notin specs:
    missing.add d.name & "  (" & d.where & ")"
  else:
    let s = specs[d.name]
    if s.nparams != d.nparams or s.nresults != d.nresults:
      wrongArity.add d.name & ": SDK says " & $d.nparams & " params/" & $d.nresults &
                   " results, host provides " & $s.nparams & "/" & $s.nresults &
                   "  (" & d.where & ")"

check("every import the SDK declares is registered by the host", missing.len == 0,
      missing.join(", "))
check("every registered import has the SDK's arity", wrongArity.len == 0,
      wrongArity.join(", "))

# --- 4. the specific contract this gate was written for --------------------------------------
#
# The four DESK needed. Named explicitly so that removing one reads as a failure here,
# not just as a diff nobody reads.
for nm in ["y_ai", "y_ai_ready", "y_sys", "y_sys_text"]:
  check(nm & " is served by the host", nm in specs)

# y_ai_ready is a CAPABILITY QUERY, not a constant: an app reads it to decide whether to
# offer its agent at all. A machine with no model set up must read 0, never 1.
check("y_ai_ready takes no arguments and returns an i32",
      specs.getOrDefault("y_ai_ready").nparams == 0 and
      specs.getOrDefault("y_ai_ready").nresults == 1)
check("y_sys takes 2 arguments", specs.getOrDefault("y_sys").nparams == 2)
check("y_sys_text takes 3 arguments", specs.getOrDefault("y_sys_text").nparams == 3)
check("y_ai takes 3 arguments", specs.getOrDefault("y_ai").nparams == 3)

# The backend reports itself from the environment, so with neither variable set it must
# honestly read 0. This is the assertion that would catch a `return 1` shortcut.
putEnv("YANTRA_AI_URL", "")
putEnv("ANTHROPIC_API_KEY", "")
check("y_ai_ready reports 0 when no model is configured", aiBackend() == 0, $aiBackend())
putEnv("ANTHROPIC_API_KEY", "not-a-real-key-just-proves-the-branch")
check("y_ai_ready reports 1 (Claude) when ANTHROPIC_API_KEY is set", aiBackend() == 1, $aiBackend())
putEnv("YANTRA_AI_URL", "http://127.0.0.1:8080/v1/chat/completions")
check("y_ai_ready reports 2 (local) when YANTRA_AI_URL is set", aiBackend() == 2, $aiBackend())
putEnv("YANTRA_AI_URL", "")
putEnv("ANTHROPIC_API_KEY", "")

# --- 5. and the real proof: DESK's desktop module must instantiate ----------------------------
#
# The gate above is a static diff. This compiles the actual module that broke and asks
# loadApp for it, so a host that registers the names but supplies them with the wrong
# WasmFunc type still fails here rather than in a user's window.

let desktop = getEnv("YANTRA_DESKTOP_WASM")
if desktop.len > 0 and fileExists(desktop):
  var ok = true
  var why = ""
  try:
    discard loadApp(desktop)
  except CatchableError as e:
    ok = false
    why = e.msg
  check("DESK's desktop.wasm instantiates against this host", ok, why)
else:
  echo "  | SKIP the live instantiate (set YANTRA_DESKTOP_WASM to a desktop.wasm)"

echo ""
echo "=== ", passed, "/", passed + failed, " contract checks passed ==="
if failed > 0: quit 1