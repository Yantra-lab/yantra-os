## Layers (CV2) through a real app — examples/shell/paint.nim: strokes drawn once into a layer
## stay, an eraser blend removes paint, a filter changes it in place, pixels read back into the
## app, and raw pixels from a buffer draw crisp.
import std/[os, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 400
const H = 300
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "paint.wasm", W, H)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](W * H)
proc frame() = e.paintFrame(addr px[0], W, H)
proc rgb(x, y: float32): (int, int, int) =
  let p = px[int(y) * W + int(x)]
  (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
proc click(name: string) =
  let b = e.boxes[idOf(name)]
  e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
  e.ensureLayout()
  frame()

frame()
check("the app starts", e.crashed.len == 0, e.crashed)
let art = e.boxes[idOf("art")]
check("an empty layer shows nothing", rgb(art.x + 50, art.y + 75) == (255, 255, 255), $rgb(art.x + 50, art.y + 75))
click("brush")
check("a stroke drawn into the layer shows", rgb(art.x + 50, art.y + 75)[0] < 30, $rgb(art.x + 50, art.y + 75))
frame(); frame()
check("and stays (drawn once, not per frame)", rgb(art.x + 50, art.y + 75)[0] < 30)
click("erase")
check("the eraser blend removes paint", rgb(art.x + 100, art.y + 75) == (255, 255, 255) and rgb(art.x + 50, art.y + 75)[0] < 30,
      $rgb(art.x + 100, art.y + 75))
click("pick")
check("pixels read back into the app (black, opaque)", e.node(idOf("picked")).sProp(P_TEXT) == "0,255",
      e.node(idOf("picked")).sProp(P_TEXT))
let edgeBefore = rgb(art.x + 50, art.y + 75 - 14)
click("soften")
let edgeAfter = rgb(art.x + 50, art.y + 75 - 14)
check("a blur filter changes the layer in place (the stroke's edge softens)", edgeAfter[0] < edgeBefore[0] - 20,
      $(edgeBefore, edgeAfter))
e.pointerDown(art.x + 150, art.y + 30); e.pointerUp(art.x + 150, art.y + 30)
e.ensureLayout(); frame()
let dot = rgb(art.x + 150, art.y + 30)
check("painting with the pointer: onPointerDown with pointerPos() draws where it was pressed",
      dot[2] > 200 and dot[0] < 60, $dot)
let dots = e.boxes[idOf("dots")]
let c0 = rgb(dots.x + 10, dots.y + 10)
let c1 = rgb(dots.x + 30, dots.y + 10)
check("raw pixels from a buffer draw, crisp (4x4 scaled to 80: red then blue squares)",
      c0[0] > 240 and c0[2] < 15 and c1[2] > 240 and c1[0] < 15, $(c0, c1))
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
