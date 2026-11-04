## Container queries (Q1) in a real app — examples/shell/sized.nim: `sized w, h:` sees the
## container's laid-out size, the first painted frame already fits, and a resize switches
## the layout inside without looping.
import std/[os, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "sized.wasm", 900, 400)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](900 * 400)
e.paintFrame(addr px[0], 900, 400)
check("the app starts", e.crashed.len == 0, e.crashed)
check("the first painted frame already has the wide layout", idOf("wide") >= 0 and idOf("narrow") < 0)
check("the app sees its container's size", e.node(idOf("size")).sProp(P_TEXT) == "900.0 x 400.0",
      e.node(idOf("size")).sProp(P_TEXT))
let calls = e.s.dispatchCalls
e.paintFrame(addr px[0], 900, 400)
check("an unchanged size tells nobody again", e.s.dispatchCalls == calls, $(e.s.dispatchCalls - calls))

e.resize(500, 400)
e.ensureLayout()
check("narrower than 640: the stacked layout", idOf("narrow") >= 0 and idOf("wide") < 0)
check("and the size follows", e.node(idOf("size")).sProp(P_TEXT) == "500.0 x 400.0", e.node(idOf("size")).sProp(P_TEXT))
let n = e.boxes[idOf("narrow")]
check("its content is laid out in the new space", n.w > 0 and n.w <= 460, $n)
e.resize(700, 400)
e.ensureLayout()
check("wider again: side by side", idOf("wide") >= 0 and idOf("narrow") < 0)
check("settling took a bounded number of calls", e.s.dispatchCalls - calls <= 6, $(e.s.dispatchCalls - calls))
check("still running", e.crashed.len == 0, e.crashed)

echo "sized: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
