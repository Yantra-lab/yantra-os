## Q1: examples/shell/vchat.wasm — variable heights, starts at the newest, prepend keeps the view.
import std/[os, strutils, tables]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "vchat.wasm", 420, 640)
var px = newSeq[uint32](420 * 640)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 420, 640))
proc topMsg(): (string, float32) =
  ## The first message on screen and its top.
  var best = 1e9'f32
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT).startsWith("#") and int32(i) in e.boxes:
      let b = e.boxes[int32(i)]
      if b.y + b.h > 60 and b.y < best: (best = b.y; result = (n.sProp(P_TEXT).split(' ')[0], b.y))
for _ in 0 ..< 6: frame()
check("the app starts", e.crashed.len == 0, e.crashed)
let (first, _) = topMsg()
check("it opens at the newest messages", first.len > 1 and parseInt(first[1 .. ^1]) > 9900, first)
var built = 0
for n in e.s.nodes:
  if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT).startsWith("#"): inc built
check("only a few screens of 10 000 are built", built > 3 and built < 120, $built)
e.pointerMove(210, 400)
e.wheel(10)                                           # up a little, off the end
for _ in 0 ..< 4: frame()
let before = topMsg()
var older = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == "Older": older = int32(i)
let ob = e.boxes[older]
e.pointerDown(ob.x + 4, ob.y + 4); e.pointerUp(ob.x + 4, ob.y + 4)
for _ in 0 ..< 6: frame()
let after = topMsg()
check("prepending 200 older messages doesn't move what shows", before[0] == after[0] and abs(before[1] - after[1]) < 2,
      $before & " -> " & $after)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
