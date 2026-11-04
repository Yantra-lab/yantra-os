## Effects (FX1) in a real app — the Effects poster (examples/shell/fx.nim): an animated SkSL
## shader, a blurred glow, frosted glass over sharp stripes, and colour filters.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 1000
const H = 700
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "fx.wasm", W, H)
var px = newSeq[uint32](W * H)
proc frame(t: float64) =
  e.tick(t)
  e.paintFrame(addr px[0], W, H)
proc at(x, y: int): uint32 = px[y * W + x]
proc named(name: string): Box =
  e.ensureLayout()
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return e.boxes[int32(i)]
proc ch(p: uint32; s: int): int = int((p shr s) and 0xFF)

frame(0)
let shots = getEnv("YANTRA_SHOTS")
if shots.len > 0:
  var bytes = newString(px.len * 4)
  copyMem(addr bytes[0], addr px[0], bytes.len)
  writeFile(shots / "fx.raw", bytes)
check("the poster draws without a shader error", e.devNote == "", e.devNote)

# the aurora is a shader that reads time: it moves on its own
let a0 = at(900, 650)
frame(1500)
let a1 = at(900, 650)
check("the SkSL background animates", a0 != a1 and e.needsPaint, a0.toHex & " " & a1.toHex)

# the glow: a blurred copy of the title spreads accent light past the letters
let g = named("glow")
var warm = 0                               # amber light just left of the first letter vs the sky further out
for y in int(g.y) ..< int(g.y + g.h):
  if ch(at(int(g.x) - 3, y), 16) > ch(at(int(g.x) - 30, y), 16) + 12: inc warm
check("the glow spreads beyond its text", warm > 10, $warm & " rows warmer near the letters")

# frosted glass: the stripes' hard edges are soft behind it, sharp outside it
let gl = named("glass")
let insideY = int(gl.y + gl.h / 2)
let outsideY = int(gl.y + gl.h + 20)
var softInside = 0
var hardOutside = 0
for x in 0 ..< 60:                           # count in-between reds across a stripe edge
  let vi = ch(at(int(gl.x) + 60 + x, insideY), 16)
  let vo = ch(at(int(gl.x) + 60 + x, outsideY), 16)
  if vi > 60 and vi < 200: inc softInside
  if vo > 60 and vo < 200: inc hardOutside
check("frosted glass blurs what is behind it and nothing else", softInside > 8 and hardOutside < 4,
      $softInside & " soft inside, " & $hardOutside & " outside")

# colour filters: saturate = 0 turns a pink-to-blue gradient grey
let m = named("mono")
let mp = at(int(m.x + m.w / 2), int(m.y + m.h / 2))
check("saturate 0 makes the gradient grey", abs(ch(mp, 16) - ch(mp, 8)) < 6 and abs(ch(mp, 8) - ch(mp, 0)) < 6, mp.toHex)

echo "effects: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
