## Q8: examples/shell/chrome.wasm — title-bar buttons, drag regions, menu commands, deep links,
## opening a URL (the OS parts are hooks here; the runner wires them to SDL / Win32).
import std/[os, strutils, tables]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

var ops: seq[int]
var opened: seq[string]
windowAction = proc (op: int) = ops.add op
openUrlHook = proc (u: string) = opened.add u
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "chrome.wasm", 480, 320)
var px = newSeq[uint32](480 * 320)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 480, 320))
proc find(kind: int32; label: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT).startsWith(label): return int32(i)
  -1
proc click(id: int32) =
  let b = e.boxes[id]
  e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
  frame()
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
check("it asks for no system frame, a menu, a badge and a scheme",
      e.node(0).iProp(P_FRAMELESS) == 1 and e.node(0).sProp(P_MENU).startsWith("File|") and
      e.node(0).iProp(P_BADGE) == 3 and e.node(0).sProp(P_SCHEME) == "yantrachrome")
let (drag, nodrag) = e.dragRegions
check("the title bar is a drag region, its 3 buttons are not", drag.len == 1 and nodrag.len >= 3, $drag.len & " " & $nodrag.len)
click(find(K_BUTTON, "×"))
check("the close button asks the window to close", ops == @[3], $ops)
e.menuCommand(2)
frame()
check("a menu command reaches the app", find(K_TEXT, "menu 2") >= 0)
e.deepLink("yantrachrome://oauth?code=abc")
frame()
check("a deep link reaches the app", find(K_TEXT, "link yantrachrome://oauth?code=abc") >= 0)
click(find(K_BUTTON, "Sign in"))
check("the app can open the browser for OAuth", opened.len == 1 and opened[0].startsWith("https://example.com/oauth"), $opened)
click(find(K_BUTTON, "Read all"))
check("the badge follows the app", e.node(0).iProp(P_BADGE) == 0)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
