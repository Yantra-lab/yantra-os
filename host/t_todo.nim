## The todo app, compiled to wasm, driven through the real host (wasmtime):
## typing, clicking, toggling, filtering and deleting, checked on the host's tree.
import std/[os, strutils, tables]
import host
import ../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  | OK   ", name
  else: inc failed; echo "  | FAIL ", name, "  ", detail

let wasm = currentSourcePath().parentDir / ".." / "examples" / "todo.wasm"
let inst = loadApp(wasm)
callMain(inst)
let s = state()

proc texts(n: int32 = 0): seq[string] =
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

proc findKind(kind: int32): int32 =
  for i, n in s.nodes:
    if n.alive and n.kind == kind: return int32(i)
  -1

proc fire(n: int32; ev: int32) =
  let h = s.handlerFor(n, ev)
  doAssert h >= 0, "no handler for event " & $ev & " on node " & $n
  dispatch(inst, h)

check("starts with two rows and a count", texts() == @["Todos", "2 left of 2", "Add", "All", "Active", "Done",
      "Write the pitch", "✕", "Record the demo", "✕"], $texts())

let inp = findKind(K_INPUT)
check("the input has its placeholder", s.nodes[int(inp)].sProp(P_PLACEHOLDER) == "What needs doing?")
s.nodes[int(inp)].props[P_VALUE] = Value(kind: vkString, s: "Apply to IITM IC")
fire(inp, E_INPUT)
fire(inp, E_SUBMIT)
check("typing then Enter adds a row and clears the input",
      "Apply to IITM IC" in texts() and s.nodes[int(inp)].sProp(P_VALUE) == "", $texts())
check("the count follows", "3 left of 3" in texts(), $texts())

let pitch = findNode(K_CHECKBOX, "Write the pitch")
let pitchRow = s.nodes[int(pitch)].parent
fire(pitch, E_CHANGE)
let pitch2 = findNode(K_CHECKBOX, "Write the pitch")
check("checking an item marks it", s.nodes[int(pitch2)].iProp(P_CHECKED) == 1)
check("its row was rebuilt in the same place", s.nodes[int(pitch2)].parent != pitchRow and
      texts().find("Write the pitch") == 6, $texts())
check("the count and the clear button follow", "2 left of 3" in texts() and "Clear done" in texts(), $texts())

fire(findNode(K_BUTTON, "Active"), E_CLICK)
check("the Active filter hides done items", "Write the pitch" notin texts() and "Record the demo" in texts(), $texts())
check("the active tab is highlighted", s.nodes[int(findNode(K_BUTTON, "Active"))].iProp(P_COLOR) == 0xFFB23E)
fire(findNode(K_BUTTON, "Done"), E_CLICK)
check("the Done filter shows only done items", texts()[6 .. ^1] == @["Write the pitch", "✕", "Clear done"], $texts())
fire(findNode(K_BUTTON, "Clear done"), E_CLICK)
check("clearing done leaves the empty state", "Nothing here yet." in texts() and "Clear done" notin texts(), $texts())
fire(findNode(K_BUTTON, "All"), E_CLICK)
let before = s.nodes.len
for i in 0 ..< 2:
  let x = findNode(K_BUTTON, "✕")
  fire(x, E_CLICK)
check("deleting every row shows the empty state again", texts()[^1] == "Nothing here yet.", $texts())
var dead = 0
for n in s.nodes:
  if not n.alive: inc dead
check("removed rows are gone from the tree, subtrees included", dead >= 8, $dead & " removed")
discard before

echo "=== ", passed, "/", passed + failed, " todo host checks passed ==="
if failed > 0: quit(1)
