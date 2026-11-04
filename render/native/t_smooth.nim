## Q4: examples/shell/viewer.wasm — notches and scrollTo glide over several frames, then land exactly.
import std/[os, tables]
import engine, nimskia
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
discard writePng(dir / "photo.png", 64, 40, 0xFF3366CC'u32)
let e = start(dir / "viewer.wasm", 420, 640)
e.smoothScroll = true
var px = newSeq[uint32](420 * 640)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 420, 640))
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
var list = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.hasProp(P_SMOOTH): list = int32(i)
let lb = e.boxes[list]
e.pointerMove(lb.x + 20, lb.y + 20 - e.scrollY)
e.wheel(-2)                                     # two notches down
frame()
let mid = e.scrolls.getOrDefault(list, 0)
for _ in 0 ..< 40: frame()
let landed = e.scrolls.getOrDefault(list, 0)
check("a notch glides: part way after one frame, all 96 px after a while", mid > 0 and mid < 96 and abs(landed - 96) < 0.6,
      $mid & " -> " & $landed)
for i, n in e.s.nodes:
  if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == "Bottom":
    let b = e.boxes[int32(i)]
    e.pointerDown(b.x + 4, b.y + 4 - e.scrollY); e.pointerUp(b.x + 4, b.y + 4 - e.scrollY)
frame()
let first = e.scrolls.getOrDefault(list, 0)
for _ in 0 ..< 60: frame()
let last = e.scrolls.getOrDefault(list, 0)
check("scrollTo glides to the end (Smooth)", first < last and last > 1000, $first & " -> " & $last)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
