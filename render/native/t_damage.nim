## P1: the kept Yoga tree and damage repaint, headless on the real todo.wasm. A partial
## frame must give exactly the pixels a full repaint gives.
import std/[os, tables]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 440
const H = 620
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "todo.wasm", W, H)
e.partialPaint = true
var px = newSeq[uint32](W * H)
var full = newSeq[uint32](W * H)
e.paintFrame(addr px[0], W, H)
let fulls = e.fullLayouts

proc findKind(kind: int32; label = ""): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and (label.len == 0 or n.sProp(P_TEXT) == label): return int32(i)
  -1

proc sameAsFull(what: string) =
  ## Repaint everything into a second buffer and compare with the partial frame.
  e.partialPaint = false
  e.dirty = true
  e.paintFrame(addr full[0], W, H)
  e.partialPaint = true
  var diff = 0
  for i in 0 ..< px.len:
    if px[i] != full[i]: inc diff
  check(what & ": the partial frame equals a full repaint", diff == 0, $diff & " pixels differ")

let add = findKind(K_BUTTON, "Add")
let ab = e.boxes[add]
e.pointerMove(ab.x + ab.w / 2, ab.y + ab.h / 2 - e.scrollY)
e.paintFrame(addr px[0], W, H)
check("hover repaints only a band", e.lastDamage.h > 0 and e.lastDamage.h < H / 3, $e.lastDamage)
sameAsFull("hover")

let input = findKind(K_INPUT)
e.focusOn(input)
e.paintFrame(addr px[0], W, H)
e.typeText("milk")
e.paintFrame(addr px[0], W, H)
check("typing lays out only what changed", e.fullLayouts == fulls and e.partialLayouts > 0 and e.restyled <= 6,
      "full " & $e.fullLayouts & " partial " & $e.partialLayouts & " restyled " & $e.restyled)
sameAsFull("typing")
e.blink()
e.paintFrame(addr px[0], W, H)
check("a caret blink repaints only the input", e.lastDamage.h <= e.boxes[input].h + 24, $e.lastDamage)
sameAsFull("caret blink")

echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
