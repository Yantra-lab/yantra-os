## Q5: examples/shell/nav.wasm — push slides a page in, the avatar flies between pages (hero),
## pop goes back, and reordered rows glide.
import std/[os, strutils, tables]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "nav.wasm", 420, 640)
var px = newSeq[uint32](420 * 640)
proc frame(ms = 16.0) = (e.tick(e.now + ms); e.paintFrame(addr px[0], 420, 640))
proc find(kind: int32; label: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1
proc named(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc click(id: int32) =
  let b = e.boxes[id]
  e.pointerDown(b.x + 4, b.y + 4 - e.scrollY); e.pointerUp(b.x + 4, b.y + 4 - e.scrollY)
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
click(find(K_BUTTON, "Contact 3"))
frame(); frame(100)
let title = find(K_TEXT, "Chat 3")
check("the chat page came", title >= 0)
check("the list page is still leaving (a ghost)", e.ghostCount > 0, $e.ghostCount)
let av = named("avatar")
check("the avatar is mid-flight between 40 and 96 px", av >= 0 and e.boxes[av].w > 41 and e.boxes[av].w < 95,
      if av >= 0: $e.boxes[av] else: "none")
for _ in 0 ..< 30: frame()
check("then it lands at 96", e.boxes[named("avatar")].w > 95.5, $e.boxes[named("avatar")])
click(find(K_BUTTON, "Back"))
for _ in 0 ..< 30: frame()
check("back pops to the list", find(K_TEXT, "Chat 3") < 0 and find(K_BUTTON, "Contact 1") >= 0)
let row1 = e.node(find(K_BUTTON, "Contact 1")).parent
let y0 = e.boxes[row1].y
click(find(K_BUTTON, "Shuffle"))
frame(); frame(80)
let yMid = e.boxes[row1].y
for _ in 0 ..< 30: frame()
let y1 = e.boxes[row1].y
check("a reordered row glides", y0 != y1 and yMid != y1 and min(y0, y1) < yMid and yMid < max(y0, y1),
      $y0 & " " & $yMid & " " & $y1)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
