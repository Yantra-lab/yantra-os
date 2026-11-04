## The Yantra desktop (DESK) through the real app — apps/desktop: Spotlight opens apps of the
## local Yantra web ("y:<id>") as sandboxed tabs, the shown tabs tile side by side with gaps,
## workspaces keep their own tabs, closing a tab re-tiles the rest, and the clock renders.
## `t_desktop <out.ppm>` also writes the last frame, to look at.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire
import ../../apps/desktop/tiling
import ../../sdk/ui/input as sdk_input

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 1280'f32
const keySpaceCode = 32'i32
const modKey = 0x0100'i32   ## Alt: the desktop's modifier on Windows (config.nim)
const H = 800'f32
let apps = currentSourcePath().parentDir / ".." / ".." / "apps"
let e = start(apps / "desktop" / "app.wasm", W, H)
proc named(name: string): seq[int32] =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: result.add int32(i)
proc box(id: int32): Box = e.boxes.getOrDefault(id, Box())
var px = newSeq[uint32](int(W * H))
var now = 0.0
proc frame() =
  for _ in 0 .. 1:                             # twice: the tiles' move animation ends
    now += 400; e.tick(now)
    e.ensureLayout()
    e.paintFrame(addr px[0], int(W), int(H))
proc tiles(): seq[Box] =
  for i, n in e.s.nodes:
    if not (n.alive and n.sProp(P_NAME).startsWith("tile")): continue
    let id = int32(i)
    let b = box(id)
    if b.w > 0: result.add b
proc search(q: string) =
  ## Mod+Space, type, Enter: Spotlight runs its best hit.
  e.key(keySpaceCode, modKey)
  frame()
  e.typeText(q)
  e.key(13, 0)
  frame()

frame()
check("the desktop starts", e.crashed.len == 0, e.crashed)
check("the tabs pane and the dock are there", named("tabsPane").len == 1 and named("dock").len == 1)
check("the clock shows the time", block:
  let ids = named("clock")
  ids.len == 1 and e.s.nodes[ids[0]].sProp(P_TEXT).len == 5 and ':' in e.s.nodes[ids[0]].sProp(P_TEXT))

search("calc")
check("Spotlight opens the calculator as a tab", tiles().len == 1, $tiles().len)
check("it runs in its own sandbox", e.children.len == 1 and e.crashed.len == 0, $e.children.len)

search("notes")
let two = tiles()
check("a second app tiles beside the first", two.len == 2 and two[0].y == two[1].y and
      abs(two[0].w - two[1].w) < 2, $two)
check("with the gap between them", two.len == 2 and
      abs(min(two[1].x, two[0].x) + min(two[0].w, two[1].w) + 5 - max(two[1].x, two[0].x)) < 1.5, $two)

e.key(int32('2'), modKey)
frame()
check("workspace 2 starts empty", tiles().len == 0, $tiles().len)
search("todo")
check("and keeps its own tabs", tiles().len == 1)
e.key(int32('1'), modKey)
frame()
check("workspace 1 still has both", tiles().len == 2, $tiles().len)

e.key(int32('w'), modKey)
frame()
check("closing a tab re-tiles the rest", tiles().len == 1 and tiles()[0].w > two[0].w * 1.8, $tiles())
check("nothing crashed", e.crashed.len == 0, e.crashed)

# Unit tests for newly exported routines
let drects = dwindle(Rect(x: 0, y: 0, w: 100, h: 100), 2, 6'f32)
check("dwindle splits rectangles", drects.len == 2 and drects[0].w == 47'f32)
check("fuzzyScore matches query", fuzzyScore("calc", "Calculator") > 0 and fuzzyScore("xyz", "Calculator") == -1)

sdk_input.fakeInput = proc(what, arg: int32): float32 =
  case what
  of 13: float32(14 * 3600 + 30 * 60 + 15)
  of 14: 0'f32
  of 15: 28'f32
  of 16: 9'f32
  of 17: 2026'f32
  else: 0'f32

let (ch, cm, cs) = clockNow()
check("clockNow returns time", ch == 14 and cm == 30 and cs == 15)
let (ty, tm, td, tw) = today()
check("today returns date", ty == 2026 and tm == 9 and td == 28 and tw == 0)

if paramCount() >= 1:
  var f = open(paramStr(1), fmWrite)
  f.write("P6\n" & $int(W) & " " & $int(H) & "\n255\n")
  for p in px:
    f.write(char((p shr 16) and 0xFF)); f.write(char((p shr 8) and 0xFF)); f.write(char(p and 0xFF))
  f.close()

echo "desktop: ", passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
