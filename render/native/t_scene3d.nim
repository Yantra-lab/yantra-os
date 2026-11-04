## Native 3D (S3D) through a real app — examples/shell/world.nim: a DSL-written world renders
## lit through Filament inside the page, objects follow their props, a hundred instances come
## from one buffer, the app's own vertices draw, and a change repaints the view.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 640
const H = 480
let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
if not fileExists(dir / "checker.png"):
  writeFile(dir / "checker.png", "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x40\x00\x00\x00\x40\x08\x02\x00\x00\x00\x25\x0b\xe6\x89\x00\x00\x00\x8a\x49\x44\x41\x54\x78\x9c\xed\xcf\xb1\x11\x00\x30\x0c\xc2\xc0\xec\xbf\xb4\x33\x81\x6b\x81\x4f\xd4\x14\xfa\x37\xcb\xde\xb2\xb4\x7f\x5c\x90\x00\x3a\x48\x00\x1d\x24\xa0\x0e\x70\x16\x96\x16\x24\x80\x0e\x12\x40\x07\x09\xa0\x83\xd6\x7f\x4d\x68\x4b\x90\x00\x3a\x48\x00\x1d\x24\xa0\x0e\x70\x16\x96\x16\x24\x80\x0e\x12\x40\x07\x09\xa0\x83\xd6\x7f\x4d\x68\x4b\x90\x00\x3a\x48\x00\x1d\x24\xa0\x0e\x70\x16\x96\x16\x24\x80\x0e\x12\x40\x07\x09\xa0\x83\xd6\x7f\x4d\x68\x4b\x90\x00\x3a\x48\x00\x1d\x24\xa0\x0e\x70\x16\x96\x16\x24\x80\x0e\x12\x40\x07\x09\x98\x50\xc0\x07\xfd\x42\xe9\x5a\x53\x4a\x78\x20\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82")
let e = start(dir / "world.wasm", W, H)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
var px = newSeq[uint32](W * H)
proc frame() = e.paintFrame(addr px[0], W, H)
proc rgb(x, y: int): (int, int, int) =
  let p = px[y * W + x]
  (int((p shr 16) and 0xFF), int((p shr 8) and 0xFF), int(p and 0xFF))
proc count(v: Box; pred: proc (c: (int, int, int)): bool): int =
  for y in int(v.y) ..< int(v.y + v.h):
    for x in int(v.x) ..< int(v.x + v.w):
      if pred(rgb(x, y)): inc result
proc isRed(c: (int, int, int)): bool = c[0] > 90 and c[0] > c[1] + 60 and c[0] > c[2] + 60
proc isGreen(c: (int, int, int)): bool = c[1] > 60 and c[1] > c[0] + 30 and c[1] > c[2] + 20
proc isBlueish(c: (int, int, int)): bool = c[2] > 110 and c[2] > c[0] + 50 and c[2] > c[1] + 50
proc isYellow(c: (int, int, int)): bool = c[0] > 150 and c[1] > 110 and c[2] < 80
proc isMagenta(c: (int, int, int)): bool = c[0] > 110 and c[2] > 110 and c[1] < c[0] - 50 and c[1] < c[2] - 50
proc isBlue(c: (int, int, int)): bool = c[2] > 90 and c[2] > c[0] + 60 and c[2] > c[1] + 30
proc redX(v: Box): float =
  var sx, n = 0
  for y in int(v.y) ..< int(v.y + v.h):
    for x in int(v.x) ..< int(v.x + v.w):
      if isRed(rgb(x, y)): (sx += x; inc n)
  if n == 0: -1.0 else: sx / n

frame()
check("the app starts", e.crashed.len == 0, e.crashed)
let view = idOf("view")
check("the 3D view is laid out, filling the space under the button", view in e.boxes and e.boxes[view].h > 300,
      (if view in e.boxes: $e.boxes[view] else: "no box"))
let v = e.boxes[view]
check("its objects are not laid out", idOf("crate") notin e.boxes and idOf("ground") notin e.boxes)
let sky = rgb(int(v.x) + 5, int(v.y) + 5)
check("the sky is its colour", abs(sky[2] - 0xE8) < 40 and sky[2] > sky[0], $sky)
let reds = count(v, isRed)
check("the red box is drawn, lit (its faces differ)", reds > 2000, $reds)
let tinted = count(v, isBlueish)
check("a hundred houses from one instanced mesh, each its own colour (magenta and blue)",
      tinted > 1000 and count(v, isMagenta) > 1000, $(tinted, count(v, isMagenta)))
check("a 2D layer drawn by the app is a texture in 3D (the yellow sign)", count(v, isYellow) > 300, $count(v, isYellow))
check("the app's own triangle (geometry buffer) is drawn", count(v, isBlue) > 300, $count(v, isBlue))
var shade = 999
var sunlit = 0
for y in int(v.y + v.h / 2) ..< int(v.y + v.h):     # grey ground: its darkest and brightest
  for x in int(v.x) ..< int(v.x + v.w):
    let c = rgb(x, y)
    if abs(c[0] - c[1]) < 20 and abs(c[1] - c[2]) < 25:
      shade = min(shade, c[0] + c[1] + c[2]); sunlit = max(sunlit, c[0] + c[1] + c[2])
check("things cast shadows on the ground", shade * 4 < sunlit * 3, $(shade, sunlit))
check("the view fills the window's width (grow)", abs(v.w - W) < 1, $v.w)
let x0 = redX(v)
if existsEnv("YANTRA_SHOTS"): (var raw = newString(px.len * 4); copyMem(addr raw[0], addr px[0], raw.len); writeFile(getEnv("YANTRA_SHOTS") / "world.bgra", raw))

let b = e.boxes[idOf("move")]
e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
e.ensureLayout()
frame()
let x1 = redX(v)
check("a prop change moves the box (and repaints the view)", x1 > x0 + 40, $(x0, x1))

# the app's own shader (SH1): colour from its uniforms, a surface that moves with time
proc isAqua(c: (int, int, int)): bool = c[1] > c[0] + 25 and c[2] > c[0] + 10 and c[2] > 150 and abs(c[1] - c[2]) < 40
let aqua = count(v, isAqua)
check("a mesh with the app's own shader draws in the colour the shader computes", aqua > 1000, $aqua)
check("its shader compiled (no complaint)", e.devNote.len == 0 or "shader" notin e.devNote, e.devNote)
var poolA: seq[int]
for y in int(v.y) ..< int(v.y + v.h):
  for x in int(v.x) ..< int(v.x + v.w):
    if isAqua(rgb(x, y)): poolA.add y * W + x
e.tick(e.now + 500); e.ensureLayout(); frame()
var moved = 0
for i in poolA:
  if not isAqua(rgb(i mod W, i div W)): inc moved
check("a shader on time keeps the view repainting and moves the surface", moved > 20, $moved)

# an image map (T3D): a black and white checker, tiled 4 x 4 on the sign: black squares
# (nothing else is black) with light between them along a row
var darkRows: seq[int]
var dark2 = 0
for y in int(v.y) ..< int(v.y + v.h):
  for x in int(v.x) ..< int(v.x + v.w):
    let c = rgb(x, y)
    if c[0] < 50 and c[1] < 50 and c[2] < 50:
      inc dark2
      if y notin darkRows: darkRows.add y
var flips = 0
if darkRows.len > 0:
  let row = darkRows[darkRows.len div 2]
  var was = false
  for x in int(v.x) ..< int(v.x + v.w):
    let c = rgb(x, row)
    let isDark = c[0] < 50 and c[1] < 50 and c[2] < 50
    if isDark != was: (inc flips; was = isDark)
check("a mesh shows its texture: black squares, tiled (4 across: 8 edges or more)", dark2 > 300 and flips >= 7,
      $(dark2, flips))

# picking (T3D): a click on the red box hits it (on its front, between 0 and 2 m up); a click on
# a house says which of the hundred copies it is; a click on the sky hits nothing
proc txt0(name: string): string = e.node(idOf(name)).sProp(P_TEXT)
proc clickAt(px, py: float32) =
  e.pointerDown(px, py); e.pointerUp(px, py); e.ensureLayout()
block:
  var sx, sy, n = 0
  for y in int(v.y) ..< int(v.y + v.h):
    for x in int(v.x) ..< int(v.x + v.w):
      if isRed(rgb(x, y)): (sx += x; sy += y; inc n)
  clickAt(float32(sx div max(n, 1)), float32(sy div max(n, 1)))
let hitBox = txt0("picked")
check("a click on the box fires its onClick, with where it hit", hitBox.startsWith("crate ") and
      (try: parseInt(hitBox[6 .. ^1]) in 0 .. 20 except ValueError: false), hitBox)
block:
  var hx, hy = -1
  for y in int(v.y) ..< int(v.y + v.h / 2):   # a far house: the upper half, left of the box
    for x in int(v.x) ..< int(v.x + v.w * 0.3):
      if hx < 0 and isBlueish(rgb(x, y)) and isBlueish(rgb(x + 2, y + 2)): (hx = x + 2; hy = y + 2)
  clickAt(float32(hx), float32(hy))
let hitHouse = txt0("picked")
check("a click on an instanced house says which copy", hitHouse.startsWith("house ") and
      (try: parseInt(hitHouse[6 .. ^1]) in 0 .. 99 except ValueError: false), hitHouse)
clickAt(v.x + 5, v.y + 5)
check("a click on the sky hits nothing", txt0("picked") == hitHouse, txt0("picked"))

# a camera into a texture (RT1): a screen shows the box from behind (it sees the red box and the
# sky the main view has); the screen is not in its own picture
let scr = block:
  var n = 0
  for y in int(v.y + v.h * 0.3) ..< int(v.y + v.h * 0.8):
    for x in int(v.x) ..< int(v.x + v.w * 0.3):
      if isRed(rgb(x, y)): inc n
  n
check("a second camera draws into a texture shown on a mesh (the box, seen on a screen)", scr > 150, $scr)

# game input (G-IN): a Frame event per display frame, held keys, raw mouse movement
proc txt(name: string): string = e.node(idOf(name)).sProp(P_TEXT)
check("the window asks for pointer lock", e.pointerLocked and e.wantsFrames)
let f0 = txt("frames")
for _ in 0 ..< 3:
  e.tick(e.now + 16); e.ensureLayout()
check("onFrame runs every frame", txt("frames") != f0 and e.crashed.len == 0, f0 & " -> " & txt("frames") & " " & e.crashed)
e.key(int32('d'))
for _ in 0 ..< 5:
  e.tick(e.now + 100); e.ensureLayout()
e.keyUp(int32('d'))
let rolled = txt("ballX")
check("a held key moves things by speed * frameDt (10/s for 0.5 s)", rolled == "50", rolled)
e.tick(e.now + 100); e.ensureLayout()
check("and stops when the key goes up", txt("ballX") == rolled, txt("ballX"))
e.rawMotion(30, 4)
e.tick(e.now + 16); e.ensureLayout()
check("raw mouse movement since the last frame", txt("dx") == "30", txt("dx"))
e.tick(e.now + 16); e.ensureLayout()
check("counted once", txt("dx") == "0", txt("dx"))
check("still running", e.crashed.len == 0, e.crashed)

echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
