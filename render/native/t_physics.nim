## Physics (PH1) through a real app — examples/shell/drop.nim: Jolt in the engine steps on the
## engine's clock; a crate falls and rests on fixed ground, an impulse moves it, a ray finds it
## by name, a rope holds a ball, and what physics moves is drawn where it is.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 400
const H = 300
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "drop.wasm", W, H)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](W * H)
proc frame() = e.paintFrame(addr px[0], W, H)
proc num(name: string): int =
  try: parseInt(e.node(idOf(name)).sProp(P_TEXT).strip) except ValueError: -99999
proc redY(): float =
  var sy, n = 0
  for y in 0 ..< H:
    for x in 0 ..< W:
      let p = px[y * W + x]
      let (r, g, b) = (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
      if r > 90 and r > g + 60 and r > b + 60: (sy += y; inc n)
  if n == 0: -1.0 else: sy / n
proc run(ms: int) =
  for _ in 0 ..< ms div 16:
    e.tick(e.now + 16); e.ensureLayout()
  frame()

frame()
check("the app starts", e.crashed.len == 0, e.crashed)
run(32)
let y0 = redY()
let startY = num("cy")
check("the crate starts up high", startY > 350, $startY)
run(2500)
check("it falls and comes to rest on the ground (centre 1 m up)", abs(num("cy") - 100) <= 5, $num("cy"))
let y1 = redY()
check("and is drawn where physics put it (lower on screen)", y1 > y0 + 20, $(y0, y1))
let x0 = num("cx")
let b = e.boxes[idOf("kick")]
e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
run(1000)
check("an impulse pushes it along", num("cx") > x0 + 50, $(x0, num("cx")))
let lb = e.boxes[idOf("look")]
e.pointerDown(lb.x + 4, lb.y + 4); e.pointerUp(lb.x + 4, lb.y + 4)
e.ensureLayout()
let hit = e.node(idOf("hit")).sProp(P_TEXT)
check("a ray straight down from 10 m finds the ground (the crate moved off), by name",
      hit.startsWith("ground ") and abs(parseInt(hit.split(' ')[1]) - 1000) <= 10, hit)
check("the rope holds the ball: never further than 3 m from its anchor", num("bob") <= 930 and num("bob") > 400, $num("bob"))
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
