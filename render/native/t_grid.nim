## Grid layout (L1) in a real app — examples/shell/grid.nim: fixed, `fr` and `auto`
## columns, spans, a fixed-width item, a nested grid, and a window resize.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

proc near(a, b: float32): bool = abs(a - b) < 1.0

# the pure track maths first
let t = parseTracks("160 1fr 2fr")
let tOk = t.len == 3 and t[0].kind == 'p' and t[0].v == 160 and t[2].kind == 'f' and t[2].v == 2
check("tracks parse: px, fr", tOk, $t)
let rep = parseTracks("repeat(3, 1fr) auto 40px")
let repOk = rep.len == 5 and rep[3].kind == 'a' and rep[4].v == 40
check("tracks parse: repeat(), auto, px suffix", repOk, $rep)
check("nonsense tracks fall back to one share", parseTracks("??").len == 1)
let w = trackWidths(t, @[0'f32, 0, 0], 852, 12)
check("fr shares what fixed columns and gaps leave", near(w[0], 160) and near(w[1], 222.67) and near(w[2], 445.33), $w)
let squeezed = trackWidths(t, @[0'f32, 0, 0], 100, 12)
check("fr never goes below zero", squeezed[1] == 0 and squeezed[2] == 0, $squeezed)
check("auto takes what it is given", trackWidths(parseTracks("auto 1fr"), @[70'f32, 0], 200, 10) == @[70'f32, 120])

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "grid.wasm", 900, 640)
proc named(name: string): Box =
  e.ensureLayout()
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return e.boxes[int32(i)]
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1

check("the app starts", e.crashed.len == 0, e.crashed)
let shots = getEnv("YANTRA_SHOTS")
if shots.len > 0:                     # a picture of it, for docs and for eyes
  var px = newSeq[uint32](900 * 640)
  e.paintFrame(addr px[0], 900, 640)
  var bytes = newString(px.len * 4)
  copyMem(addr bytes[0], addr px[0], bytes.len)
  writeFile(shots / "grid.raw", bytes)
let side = named("side")
check("the fixed column is 160 wide at the left", near(side.x, 24) and near(side.w, 160), $side)
let kids = e.node(idOf("main")).children
let one = e.boxes[kids[1]]
let two = e.boxes[kids[2]]
check("1fr takes a third of what is left", near(one.x, 196) and near(one.w, 222.67), $one)
check("2fr takes twice as much", near(two.x, 430.67) and near(two.w, 445.33), $two)
check("a row's items share its height", near(side.h, two.h) and near(one.h, two.h) and side.y == two.y, $side & " " & $two)
let wide = named("wide")
check("span = 2 covers two columns and the gap between", near(wide.x, 24) and near(wide.w, 394.67) and wide.y > side.y + side.h, $wide)
let fixed = named("fixed")
check("a fixed-width item keeps its width, in its own column", near(fixed.w, 120) and near(fixed.x, 430.67) and near(fixed.y, wide.y), $fixed)
let tall = named("tall")
check("span = 3 is a whole row of its own", near(tall.x, 24) and near(tall.w, 852) and tall.y > wide.y, $tall)

let ik = e.node(idOf("inner")).children
let lab1 = e.boxes[ik[0]]
let txt1 = e.boxes[ik[1]]
let lab2 = e.boxes[ik[2]]
let txt2 = e.boxes[ik[3]]
check("auto: every label cell is as wide as the widest label", near(lab1.w, lab2.w) and lab1.w > 60, $lab1 & " " & $lab2)
# (boxes are whole pixels: Yoga rounds each edge, so a gap can read 1 px off)
check("the 1fr cells line up after it", near(txt1.x, txt2.x) and abs(txt1.x - (lab1.x + lab1.w + 8)) <= 1.0, $lab1 & " " & $txt1 & " " & $txt2)
check("the nested grid fills its cell", near(txt1.x + txt1.w, tall.x + tall.w - 12), $txt1 & " " & $tall)

e.resize(600, 640)
let one2 = named("wide")
let side2 = named("side")
let kids2 = e.node(idOf("main")).children
let two2 = e.boxes[kids2[2]]
check("after a resize fr columns shrink and fixed ones stay", near(side2.w, 160) and near(two2.w, (552 - 160 - 24) * 2 / 3), $side2 & " " & $two2)
check("and spans follow", near(one2.w, 160 + 12 + (552 - 160 - 24) / 3), $one2)

echo "grid: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
