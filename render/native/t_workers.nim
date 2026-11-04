## Q7: examples/shell/workers.wasm — a worker computes on its own thread; the answer comes back
## as a message while the UI keeps ticking.
import std/[os, strutils, tables, times]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "workers.wasm", 360, 240)
var px = newSeq[uint32](360 * 240)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 360, 240))
proc label(): string =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT: return n.sProp(P_TEXT)
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
for i, n in e.s.nodes:
  if n.alive and n.kind == K_BUTTON:
    let b = e.boxes[int32(i)]
    e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
let t0 = epochTime()
var frames = 0
while not label().startsWith("sum") and epochTime() - t0 < 10:
  frame()
  inc frames
  sleep(2)
check("the worker's answer arrives", label() == "sum " & $((2000000 div 1000) * 499500), label())
check("the UI kept running meanwhile", frames > 0 and e.crashed.len == 0, $frames & " " & e.crashed)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
