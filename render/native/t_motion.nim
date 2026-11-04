## Motion (docs/spec/style.md §7), driven headless on a fake clock: the Motion app
## (examples/shell/motion.wasm) is clicked and hovered like a person would, and the
## engine is asked where things are at chosen moments.
import std/[os, tables, math]
import engine, ./motion
import ../../protocol/easing
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

# curves first: pure maths
var tr: Track
discard tr.follow(10, 0, 100, 0)
check("a track takes its first value as is", tr.value(0) == 10)
discard tr.follow(20, 0, 100, 0)
check("a new target is reached over the duration", abs(tr.value(50) - 15) < 0.01 and tr.value(100) == 20,
      $tr.value(50))
discard tr.follow(10, 50, 100, 0)
check("retargeting mid-flight starts from where it is", abs(tr.value(50) - 15) < 0.01 and abs(tr.value(100) - 12.5) < 0.01)
check("colours blend per channel", mix(0xFF000000'u32, 0xFFFFFFFF'u32, 0.5) == 0xFF808080'u32)
let l = Loop(target: "rotate", frm: 0, to: 360, ms: 1000, ease: 0, count: 0)
check("a loop repeats", abs(l.loopValue(0, 250)[0] - 90) < 0.01 and abs(l.loopValue(0, 1250)[0] - 90) < 0.01)
let y = Loop(target: "y", frm: 0, to: 10, ms: 100, ease: 0, count: 2, yoyo: true)
check("a yoyo loop comes back, and a counted one stops", abs(y.loopValue(0, 150)[0] - 5) < 0.01 and
      not y.loopValue(0, 250)[1] and y.loopValue(0, 250)[0] == 0)

# the Motion app
let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
let e = start(dir / "motion.wasm", 760, 1100)
var px = newSeq[uint32](760 * 1100)
let shots = getEnv("YANTRA_SHOTS")          # set it to a folder to also save these frames
proc frame(t: float64; shot = "") =
  e.tick(t)
  e.paintFrame(addr px[0], 760, 1100)
  if shots.len > 0 and shot.len > 0:
    var bytes = newString(px.len * 4)
    copyMem(addr bytes[0], addr px[0], bytes.len)
    writeFile(shots / shot & ".raw", bytes)

proc findIn(kind: int32; label: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1
proc centre(id: int32): (float32, float32) =
  e.ensureLayout()
  let b = e.boxes[id]
  (b.x + b.w / 2, b.y + b.h / 2)
proc click(id: int32) =
  var cur = id
  while cur >= 0 and e.s.handlerFor(cur, E_CLICK) < 0 and e.node(cur).kind != K_BUTTON: cur = e.node(cur).parent
  let (x, y) = centre(cur)
  e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y)
proc chipOf(label: string): int32 =
  ## The row that holds a chip's label.
  let t = findIn(K_TEXT, label)
  if t < 0: -1'i32 else: e.node(t).parent

frame(0)
check("the app starts with nothing moving but its loops", e.ghostCount == 0)

# transition: the bar grows and changes colour over time
var bar = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.kind == K_PANEL and n.iProp(P_WIDTH) == 96: bar = int32(i)
check("the bar is there", bar >= 0)
e.tick(1000)            # the window loop moves the clock before it hands over input
click(findIn(K_BUTTON, "Grow"))
frame(1000)
check("right after the click the bar has not jumped", e.boxes[bar].w == 96, $e.boxes[bar].w)
frame(1060, "1-growing")
let midW = e.boxes[bar].w
check("mid-way it is growing", midW > 96 and midW < 300, $midW)
frame(1500)
check("and it settles at its new width", abs(e.boxes[bar].w - 300) < 0.01, $e.boxes[bar].w)

# enter, and the others sliding over (a keyed list: the new chip goes first)
let layoutChip = chipOf("Layout")
let x0 = e.boxes[layoutChip].x
e.tick(2000)
click(findIn(K_BUTTON, "Add"))
frame(2000)
let newChip = chipOf("Exit")
check("Add made a new chip", newChip >= 0)
let p0 = e.motionPose(newChip)
check("a new chip starts at its enter pose (clear, 14px low)", p0.opacity < 0.01 and abs(p0.y - 14) < 0.01,
      $p0.opacity & " " & $p0.y)
check("the chip that was first has not jumped yet", abs(e.boxes[layoutChip].x - x0) < 0.01)
frame(2100, "2-entering")
let p1 = e.motionPose(newChip)
check("mid-way the new chip is fading and rising in", p1.opacity > 0.05 and p1.opacity < 1 and p1.y > 0 and p1.y < 14,
      $p1.opacity & " " & $p1.y)
let xMid = e.boxes[layoutChip].x
frame(2600)
let x1 = e.boxes[layoutChip].x
check("the others slide over to make room", xMid > x0 and xMid < x1, $x0 & " " & $xMid & " " & $x1)
check("the new chip is fully in", abs(e.motionPose(newChip).opacity - 1) < 0.01 and e.motionPose(newChip).y == 0)

# exit: the removed chip stays on screen as a ghost until its exit is done
let colour = chipOf("Colour")
var closeX = -1'i32
for k in e.node(colour).children:
  if e.node(k).kind == K_ROW: closeX = k
e.tick(3000)
click(closeX)
check("the app removed the chip", not e.node(colour).alive)
frame(3000)
frame(3100, "3-leaving")
check("but it is still drawn, leaving", e.ghostCount == 1 and e.boxes.hasKey(colour))
frame(3300)
frame(3310)
check("once its exit is done it is gone", e.ghostCount == 0 and not e.boxes.hasKey(colour))

# loops
var spinner = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.kind == K_PATH and n.sProp(P_ANIM_TARGET) == "rotate": spinner = int32(i)
frame(4000)
let r0 = e.motionPose(spinner).rotate
frame(4275)
let r1 = e.motionPose(spinner).rotate
check("the spinner turns on its own", abs(abs(r1 - r0) - 90) < 1, $r0 & " -> " & $r1)
check("a looping app keeps asking for frames", e.needsPaint)

# hover lifts a tile
let tile = e.node(findIn(K_TEXT, "Globe")).parent
let (tx, ty) = centre(tile)
e.tick(5000)
e.pointerMove(tx, ty)
frame(5000)
check("hover starts from rest", e.motionPose(tile).y == 0)
frame(5080)
let lift = e.motionPose(tile).y
check("the tile rises under the pointer", lift < 0 and lift > -4, $lift)
frame(5400, "4-hover")
check("and settles lifted and larger", abs(e.motionPose(tile).y + 4) < 0.01 and abs(e.motionPose(tile).scale - 1.04) < 0.01)
e.tick(5450)
e.pointerMove(5, 5)
frame(5450)
check("leaving starts from where it is (no jump)", abs(e.motionPose(tile).y + 4) < 0.01)
frame(5500)
let back = e.motionPose(tile).y
check("and eases back down", back < 0 and back > -4, $back)

# reduced motion: same app, everything instant, loops still
let r = start(dir / "motion.wasm", 760, 1100)
r.reducedMotion = true
r.tick(0)
r.paintFrame(addr px[0], 760, 1100)
var rb = -1'i32
for i, n in r.s.nodes:
  if n.alive and n.kind == K_PANEL and n.iProp(P_WIDTH) == 96: rb = int32(i)
var gb = -1'i32
for i, n in r.s.nodes:
  if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == "Grow": gb = int32(i)
r.ensureLayout()
let gbox = r.boxes[gb]
r.pointerMove(gbox.x + 5, gbox.y + 5); r.pointerDown(gbox.x + 5, gbox.y + 5); r.pointerUp(gbox.x + 5, gbox.y + 5)
r.tick(10)
r.paintFrame(addr px[0], 760, 1100)
check("with reduced motion a change is instant", abs(r.boxes[rb].w - 300) < 0.01, $r.boxes[rb].w)
check("and loops stand still, so an idle app stops painting", not r.needsPaint)

echo "motion: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)

# the spec parser and pose maths the engine uses
let sp = parseSpec("0,0,12,0.9,0,300,50,23")
check("an enter/exit spec parses", sp.opacity == 0 and sp.y == 12 and abs(sp.scale - 0.9) < 1e-6 and sp.ms == 300 and
      sp.delay == 50 and sp.ease == 23)
check("a short spec keeps the defaults", parseSpec("0.5").ms == 200 and parseSpec("0.5").scale == 1)
check("curves: linear is straight, out-cubic front-loads", curve(0, 0.5) == 0.5 and abs(curve(5, 0.5) - 0.875) < 1e-6)
let pz = combine(Pose(opacity: 0.5, x: 1, y: 2, scale: 2, rotate: 10), poseOf("rotate", 5))
check("poses combine: opacity and scale multiply, offsets add", pz.opacity == 0.5 and pz.scale == 2 and pz.rotate == 15)
check("while waiting for its delay an entering node sits at the spec", sp.entering(0, 40).y == 12)
echo "motion (maths): ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)

# springs (S7): physics in transitions, the step response where a duration is needed
let springId = int32(ord(easeSpring))
let bouncy = int32(ord(easeSpringBouncy))
var s1: Track
discard s1.follow(0, 0, 300, springId)
discard s1.follow(100, 0, 300, springId)
let early = s1.follow(100, 100, 300, springId)
check("a spring moves toward its target", early > 5 and early < 100, $early)
discard s1.follow(100, 3000, 300, springId)
check("and settles on it exactly", s1.value(3000) == 100 and not s1.running(3000))
var s2: Track
discard s2.follow(0, 0, 300, bouncy)
discard s2.follow(100, 0, 300, bouncy)
var peak = 0'f32
for ms in countup(10, 2000, 10): peak = max(peak, s2.follow(100, float64(ms), 300, bouncy))
check("a bouncy spring overshoots, then comes back", peak > 105 and s2.follow(100, 6000, 300, bouncy) == 100, $peak)
var s3: Track
discard s3.follow(0, 0, 300, springId)
discard s3.follow(100, 0, 300, springId)
let mid = s3.follow(100, 150, 300, springId)
let afterFlip = s3.follow(0, 170, 300, springId)                 # target flips back mid-flight
check("retargeting keeps the spring's speed (it carries on forward before turning)", afterFlip > mid, $mid & " -> " & $afterFlip)
let curveOk = curve(springId, 0) == 0 and abs(curve(springId, 1) - 1) < 0.002 and curve(bouncy, 0.35) > 1
check("as a curve, a spring still starts at 0 and ends at 1 (a bouncy one overshoots)", curveOk, $curve(bouncy, 0.35))
let presets = springParams(easeSpringBouncy) == (180'f32, 12'f32) and springParams(easeSpring) == (170'f32, 26'f32)
check("the spring presets are the classic ones (bouncy 180/12, default 170/26)", presets)
let settle = springSettle(easeSpring)
let stepOk = springStep(easeSpring, 0) == 0 and abs(springStep(easeSpring, settle) - 1) < 0.002 and settle > 0.2
check("a spring's step response runs from 0 to within 0.1% of 1 over its settle time", stepOk, $settle)
check("springs are known by kind and by wire id", isSpring(easeSpringGentle) and not isSpring(easeOutCubic) and
      isSpringId(springId) and not isSpringId(5))
echo "motion (springs): ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
