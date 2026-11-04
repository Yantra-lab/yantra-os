## Q3: examples/shell/richtext.wasm — a link click says which link; an inline image draws in the
## line; find-in-page counts matches and scrolls the current one into view.
import std/[os, strutils, tables]
import engine, nimskia
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
discard writePng(dir / "icon.png", 20, 20, 0xFF00FF00'u32)
let e = start(dir / "richtext.wasm", 480, 400)
var px = newSeq[uint32](480 * 400)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 480, 400))
proc find(pred: proc (n: Node): bool): int32 =
  for i, n in e.s.nodes:
    if n.alive and pred(n): return int32(i)
  -1
proc clickAt(x, y: float32) = (e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y); frame())
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
let para = find(proc (n: Node): bool = n.kind == K_TEXT and n.sProp(P_TEXT).startsWith("Read"))
let pb = e.boxes[para]
let t = e.node(para).sProp(P_TEXT)
let r = textRects(t, 20, 24, 16, 400, pb.w, TextStyle(inline: "20,20"))
check("the link has a place in the line", r.len > 0, $r.len)
clickAt(pb.x + r[0][0] + r[0][2] / 2, pb.y + r[0][1] + r[0][3] / 2 - e.scrollY)
let label = find(proc (n: Node): bool = n.kind == K_TEXT and n.sProp(P_TEXT).startsWith("clicked:"))
check("clicking the second link says 'home'", e.node(label).sProp(P_TEXT) == "clicked: home", e.node(label).sProp(P_TEXT))
let ir = inlineRects(t, 16, 400, pb.w, 0, TextStyle(inline: "20,20"))
check("the inline image has a 20x20 box", ir.len == 1 and ir[0][2] == 20 and ir[0][3] == 20, $ir)
if ir.len == 1:
  let p = px[int(pb.y + ir[0][1] + 10 - e.scrollY) * 480 + int(pb.x + ir[0][0] + 10)]
  check("and is drawn there", ((p shr 8) and 0xFF) > 0xC0, p.toHex)
let fb = e.boxes[find(proc (n: Node): bool = n.kind == K_BUTTON and n.sProp(P_TEXT) == "Find needle")]
clickAt(fb.x + 4, fb.y + 4 - e.scrollY)
check("30 matches", e.s.findCount == 30, $e.s.findCount)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
