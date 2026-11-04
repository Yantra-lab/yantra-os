## Characters (CH1) through a real app — examples/shell/fox.nim: a skinned glTF model plays a
## clip by name; changing it crossfades (a snap jumps); the app turns a bone on top of the pose and
## reads bones back; one model with placements is a herd of copies.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 640
const H = 360
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "fox.wasm", W, H)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](W * H)
proc frame() = e.paintFrame(addr px[0], W, H)
proc num(name: string): int =
  try: parseInt(e.node(idOf(name)).sProp(P_TEXT).strip) except ValueError: -99999
proc step(n = 1) =
  for _ in 0 ..< n:
    e.tick(e.now + 16); e.ensureLayout(); frame()
proc click(name: string) =
  let b = e.boxes[idOf(name)]
  e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
  e.ensureLayout()
proc foxish(b: Box): int =
  for y in int(b.y) ..< int(b.y + b.h):
    for x in int(b.x) ..< int(b.x + b.w):
      let p = px[y * W + x]
      let (r, g, bl) = (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
      if r > 120 and r > g + 30 and r > bl + 60: inc result

frame(); step(3)
check("the app starts", e.crashed.len == 0, e.crashed)
let one = e.boxes[idOf("one")]
if existsEnv("YANTRA_SHOTS"): (var raw = newString(px.len * 4); copyMem(addr raw[0], addr px[0], raw.len); writeFile(getEnv("YANTRA_SHOTS") / "fox.bgra", raw))
check("a skinned model is drawn", foxish(one) > 800, $foxish(one) & " " & e.devNote)
let f0 = num("foot")
step(20)
check("its clip plays (a foot moves)", num("foot") != f0 and num("foot") != -99999, $(f0, num("foot")))
var biggest = 0
var last = num("foot")
for _ in 0 ..< 30:                              # how far a foot goes in one frame, walking
  step(); biggest = max(biggest, abs(num("foot") - last)); last = num("foot")
click("run"); step()
let smooth = abs(num("foot") - last)
check("a new clip crossfades: no jump at the switch", smooth <= biggest + 5, $(smooth, biggest))
step(40)
last = num("foot")
click("snap"); step()
let jump = abs(num("foot") - last)
check("with blendTime 0 it snaps to the new pose", jump > smooth, $(jump, smooth))
let h0 = num("head")
step(5)
check("a model without a clip holds still", num("head") == h0, $(h0, num("head")))
click("turn"); step(3)
check("turning a bone moves what hangs from it (the neck moves the head)", abs(num("head") - h0) > 20, $(h0, num("head")))
let many = e.boxes[idOf("many")]
check("one model with twelve placements is a herd", foxish(many) > foxish(one) * 3, $(foxish(many), foxish(one)))
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
