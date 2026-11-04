## Capability sandbox test (B3)
## Tests that an app trying to read a file without "files" capability
## receives a typed CapabilityDenied and the UI reflects the refusal.
## When granted, the file content is read and reflected in the UI.
import std/[os, strutils, tables, sets]
import host
import ../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  | OK   ", name
  else: inc failed; echo "  | FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let wasm = here / ".." / "examples" / "sandbox.wasm"
let testFile = here / ".." / "examples" / "hello_sandbox.txt"
let testData = "Sandboxed file content: Yantra B3 verified!"
writeFile(testFile, testData)

let a = openApp(wasm)
run(a)
let s = a.state

proc texts(n: int32 = 0): seq[string] =
  if int(n) >= s.nodes.len: return
  let node = s.nodes[int(n)]
  if not node.alive: return
  if n != 0 and node.kind in [K_TEXT, K_BUTTON, K_CHECKBOX]:
    let t = node.sProp(P_TEXT)
    if t.len > 0: result.add t
  for c in node.children: result.add texts(c)

proc findNode(kind: int32; label: string): int32 =
  for i, n in s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1

# Branch 1: denied without capability
check("app starts and renders title", "Sandbox Capability Demo" in texts(), $texts())
var hasRefusal = false
for t in texts():
  if t.startsWith("Refused: CapabilityDenied"):
    hasRefusal = true
check("UI displays typed CapabilityDenied refusal", hasRefusal, $texts())
check("UI does not have file content when refused", testData notin texts(), $texts())

# Branch 2: granted capability
a.grantCapability("files")
check("hasCapability reports granted", a.hasCapability("files"))

let btn = findNode(K_BUTTON, "Read file")
check("found Read file button", btn >= 0)
let h = s.handlerFor(btn, E_CLICK)
check("found click handler", h >= 0)
dispatchTo(a, h)

var hasGranted = false
for t in texts():
  if t.startsWith("Granted: read"):
    hasGranted = true
check("UI displays granted status", hasGranted, $texts())
check("UI displays file content when granted", testData in texts(), $texts())

# Branch 3: revoked capability returns to refusal
a.revokeCapability("files")
check("hasCapability reports not granted", not a.hasCapability("files"))
dispatchTo(a, h)

var hasRefusalAfterRevoke = false
for t in texts():
  if t.startsWith("Refused: CapabilityDenied"):
    hasRefusalAfterRevoke = true
check("UI displays refusal after capability revoked", hasRefusalAfterRevoke, $texts())

# 4. Direct SDK runtime procs
import ../sdk/core/runtime
let err = newCapabilityDenied("network", "not permitted")
check("newCapabilityDenied structured fields", err.capability == "network" and err.reason == "not permitted")
needs("files", "storage")
check("needs sets manifest needs string", g_manifestNeeds == "files,storage")
check("readText is callable", not readText("nonexistent.txt").ok)
check("readTextFile is callable", not readTextFile("nonexistent.txt").ok)

removeFile(testFile)

echo "=== ", passed, "/", passed + failed, " sandbox host checks passed ==="
if failed > 0: quit(1)
