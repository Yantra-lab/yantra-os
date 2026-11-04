## Scroll-linked motion (V1) in a real app — examples/shell/scroll.nim: `reveal` poses follow
## the scroll position both ways, `parallax` drifts by a fraction, reduced motion and
## exports show everything as it is.
import std/[os, tables]
import engine, ./motion
import ../../protocol/easing
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "scroll.wasm", 600, 400)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
e.ensureLayout()
check("the app starts", e.crashed.len == 0, e.crashed)
check("the page is taller than the window", e.contentH > 900, $e.contentH)

let last = idOf("last")
let p0 = e.motionPose(last)
check("below the fold, a reveal waits at its pose", p0.opacity < 0.01 and abs(p0.scale - 0.8) < 0.01, $p0)
let first = e.motionPose(idOf("first"))
check("a node already well in view is itself", first.opacity > 0.99, $first)

let bd = idOf("backdrop")
let b0 = e.motionPose(bd).y
let bb = e.boxes[bd]
check("parallax at the top: offset by 0.4 of its distance from the middle", abs(b0 - (bb.y + bb.h / 2 - 200) * 0.4) < 0.5, $b0)

e.wheel(-3)                            # 144 px down
e.ensureLayout()
let b1 = e.motionPose(bd).y
check("scrolling 144 px moves the backdrop 0.4 of that against it", abs((b1 - b0) + 144 * 0.4) < 0.5, $(b1 - b0))

for _ in 0 ..< 40: e.wheel(-3)         # to the bottom
e.ensureLayout()
check("scrolled to the end", e.scrollY >= e.contentH - 400 - 1, $e.scrollY)
let p1 = e.motionPose(last)
check("in view, the reveal has played to itself", p1.opacity > 0.99 and abs(p1.scale - 1) < 0.01, $p1)

for _ in 0 ..< 40: e.wheel(3)          # back to the top
e.ensureLayout()
let p2 = e.motionPose(last)
check("scrolled away again, it goes back", p2.opacity < 0.01, $p2)

# partway: a node entering the bottom edge is partly revealed
let lb = e.boxes[last]
e.scrollY = lb.y - 400 + 50            # its top 50 px above the bottom edge (a quarter of 400 is 100)
e.dirty = true
let p3 = e.motionPose(last)
let c = curve(int32(easeOutBack), 0.5)  # pop's ease, which overshoots
check("halfway through the bottom quarter: the eased halfway pose", abs(p3.scale - (0.8 + 0.2 * c)) < 0.01, $p3 & " " & $c)
check("an overshooting ease never pushes opacity past 1", p3.opacity <= 1, $p3)

e.reducedMotion = true
let p4 = e.motionPose(last)
check("reduced motion: shown as it is", p4.opacity > 0.99 and e.motionPose(bd).y == 0, $p4)
e.reducedMotion = false

check("between is the far end at 0 and the node at 1", parseSpec("0,0,40,1,0,0,0,0").between(0).y == 40 and parseSpec("0,0,40,1,0,0,0,0").between(1).y == 0)

echo "scroll: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
