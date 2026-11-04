## Particles (PT1) through a real app — examples/shell/sparks.nim: an emitter sprays sprites at
## its rate, they rise and fall under gravity and fade; a burst emits many at once; all native.
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
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "sparks.wasm", W, H)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](W * H)
proc frame() = e.paintFrame(addr px[0], W, H)
proc step(n = 1) =
  for _ in 0 ..< n:
    e.tick(e.now + 16); e.ensureLayout(); frame()
proc orange(): (int, float) =
  var n, sy = 0
  for y in 0 ..< H:
    for x in 0 ..< W:
      let p = px[y * W + x]
      let (r, g, b) = (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
      if r > 150 and g > 50 and b < 90 and r > b + 80: (inc n; sy += y)
  (n, if n > 0: sy / n else: -1.0)
proc blue(): int =
  for y in 0 ..< H:
    for x in 0 ..< W:
      let p = px[y * W + x]
      let (r, g, b) = (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
      if b > 150 and b > r + 80: inc result

frame()
check("the app starts", e.crashed.len == 0, e.crashed)
check("nothing before any is emitted", orange()[0] == 0 and blue() == 0, $(orange(), blue()))
step(10)
let (n1, _) = orange()
check("the fountain sprays sparks", n1 > 100, $n1)
step(60)
let (n2, _) = orange()
check("it keeps spraying: a steady stream (born and dying)", n2 > 150, $n2)
check("no blue before the burst", blue() == 0, $blue())
let b = e.boxes[idOf("blast")]
e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
e.ensureLayout(); step(4)
let bl = blue()
if existsEnv("YANTRA_SHOTS"): (var raw = newString(px.len * 4); copyMem(addr raw[0], addr px[0], raw.len); writeFile(getEnv("YANTRA_SHOTS") / "sp.bgra", raw))
check("a burst emits many at once", bl > 200, $bl)
step(80)
check("and they die after their lifetime", blue() < bl div 10, $(bl, blue()))
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
