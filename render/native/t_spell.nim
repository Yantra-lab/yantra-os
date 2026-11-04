## Q9: examples/shell/spell.wasm — a misspelled word gets suggestions on right click and the
## app's choice replaces it (Windows' spell checker; elsewhere this SKIPs).
import std/[os, strutils, tables]
import engine, nimspell, nimskia
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "spell.wasm", 440, 240)
var px = newSeq[uint32](440 * 240)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 440, 240))
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
if misspelled("I like teh cat").len == 0:
  echo "  SKIP no system spell checker here"
else:
  check("'teh' is misspelled", misspelled("I like teh cat") == @[(7, 10)], $misspelled("I like teh cat"))
  var ta = -1'i32
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_TEXTAREA: ta = int32(i)
  let (ox, oy, maxW) = (e.boxes[ta].x + 12, e.boxes[ta].y + 11, e.boxes[ta].w - 24)
  let r = textRects("I like teh cat", 7, 10, 15, 400, maxW, TextStyle())
  e.contextClick(ox + r[0][0] + r[0][2] / 2, oy + r[0][1] + r[0][3] / 2)
  frame(); frame()
  check("the app got the word and a fix, and it replaced it", "teh" notin e.node(ta).sProp(P_VALUE),
        e.node(ta).sProp(P_VALUE))
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
