## t_mpopen - File > Open, end to end, through the REAL dialog path.
##
## WHY THIS EXISTS AND WHY IT IS NOT A UNIT TEST
## ----------------------------------------------
## `file/open.open_file` had no branch in app.nim's menu dispatcher, so the item
## closed the menu and did nothing - no dialog, no log, and a frame diff of
## about zero. Every unit test of the pieces (openfiles.nim in
## apps/minipaint/tests/t_openfile.nim, imagedec in t_imagedec.nim, the picker
## binding in THIS directory's t_dialog.nim) can be green while that stays
## true, because none of them touches the menu dispatcher. Only a real pointer
## going through the real host does.
##
## So this drives apps/minipaint/app.wasm in the native engine and:
##   1. clicks File, then the Open submenu row, by MEASURED coordinates;
##   2. has the SDL layer hand back a real PNG from disk (setMockOpenFile is the
##      same hook t_dialog.nim uses, and it goes through `pumpPick` ->
##      `showOpenFileDialog` -> `onDialogPicked` -> `y_pick_body`, i.e. the whole
##      plumbing except the OS window itself);
##   3. asserts the framebuffer now contains the FILE's pixels, not just that
##      nothing crashed.
##
## Step 3 is the one that matters. A wiring that opened a dialog and then threw
## the bytes away would pass a "did not trap" check and fail this.
##
## Run from render/native with the repo's own nimcache:
##   nim c -r --hints:off --nimcache:"$LOCALAPPDATA/Temp/nc_mpopen" \
##     -p:...libs... t_mpopen.nim

import std/[os, strutils, math]
import engine, ../../host/tree, ../../protocol/wire, ../../libs/nimsdl3/src/nimsdl3

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let repo = here / ".." / ".."
let wasmPath = repo / "apps/minipaint/app.wasm"
check("app.wasm is where this expects it", fileExists(wasmPath), wasmPath)

# The fixture: a real PNG, 24x16, opaque magenta. Written by hand (a valid zlib
# STREAM would need inflate, so this uses stored deflate blocks) so the test
# owns its bytes and knows the exact RGBA it expects on screen.
proc pngFixture(w, h: int): seq[uint8] =
  var raw = newSeq[uint8](h * (1 + w * 3))
  for y in 0 ..< h:
    raw[y * (1 + w * 3)] = 0'u8                       # filter: none
    for x in 0 ..< w:
      let o = y * (1 + w * 3) + 1 + x * 3
      raw[o] = 255'u8; raw[o + 1] = 0'u8; raw[o + 2] = 255'u8
  # zlib: CMF/FLG for stored-only, then N stored blocks of <=65535.
  var z = @[0x78'u8, 0x01'u8]
  var p = 0
  while p < raw.len:
    let n = min(65535, raw.len - p)
    let last = (if p + n >= raw.len: 1'u8 else: 0'u8)
    z.add last
    z.add uint8(n and 0xFF); z.add uint8((n shr 8) and 0xFF)
    z.add uint8((not n) and 0xFF); z.add uint8(((not n) shr 8) and 0xFF)
    for i in 0 ..< n: z.add raw[p + i]
    p += n
  var adc = 0'u32
  for b in z: adc = (adc + uint32(b)) mod 65521'u32
  z.add uint8((adc shr 8) and 0xFF); z.add uint8(adc and 0xFF)

  var png = @[0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  proc be32(v: int): seq[uint8] =
    @[uint8((v shr 24) and 0xFF), uint8((v shr 16) and 0xFF),
      uint8((v shr 8) and 0xFF), uint8(v and 0xFF)]
  proc chunk(kind: string; body: seq[uint8]): seq[uint8] =
    result = be32(body.len)
    for ch in kind: result.add uint8(ord(ch))
    result.add body
    # The 4-byte CRC-32 IS part of the format: the decoder skips exactly 4
    # bytes of it after every chunk (imagedec.nim:403), so a fixture that omits
    # it desynchronises the walk and is rejected with "png chunk runs past the
    # end of the file" - which is the decoder being right and the fixture being
    # a fake PNG. A REAL CRC is computed here so this file is decodable by
    # anything, not just by a decoder that happens not to verify it.
    # A REAL CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320) so this file is a
    # valid PNG for anything, not just for a decoder that skips the field
    # without verifying it. Ten lines beat a table generator here because the
    # fixture is 1.2 KB.
    var crc = 0xFFFF_FFFF'u32
    for b in result:
      crc = crc xor uint32(b)
      for _ in 0 .. 7:
        crc = (if (crc and 1) != 0: 0xEDB8_8320'u32 xor (crc shr 1) else: crc shr 1)
    crc = crc xor 0xFFFF_FFFF'u32
    result.add uint8((crc shr 24) and 0xFF); result.add uint8((crc shr 16) and 0xFF)
    result.add uint8((crc shr 8) and 0xFF); result.add uint8(crc and 0xFF)
  png.add chunk("IHDR", be32(w) & be32(h) & @[8'u8, 2'u8, 0'u8, 0'u8, 0'u8])
  png.add chunk("IDAT", z)
  png.add chunk("IEND", @[])
  # The accumulator is a local, so it has to be handed to `result` explicitly.
  # Left implicit, this returned an EMPTY seq, the fixture on disk was 0 bytes,
  # and the app faithfully reported `picked 0 bytes` - which is exactly the
  # silent-no-op shape this suite exists to catch, one layer further down.
  result = png

let fixtureW = 24
let fixtureH = 16
let fixture = here / "build/mpopen_fixture.png"
createDir(here / "build")
writeFile(fixture, cast[string](pngFixture(fixtureW, fixtureH)))
stderr.write "fixture=" & fixture & " exists=" & $fileExists(fixture) &
  " size=" & $getFileSize(fixture) & "\n"

let e = start(wasmPath, 1280, 800, 1)
check("engine starts app.wasm cleanly", e.crashed.len == 0, e.crashed)
e.tick(16.0)

const
  MENU_H = 30.0'f32
  ROW_H = 30.0'f32
  BAR_PAD_L = 10.0'f32
  ## Measured, not derived: these are the coordinates the driver harness
  ## (scratch/MPRIVER.md) records for THIS app at 1280x800. The bar centres are
  ## File 29, Edit 69.5, View 112.5; the File dropdown starts at BAR_PAD_L with
  ## width 150; a dropdown row k centres at MENU_H + (k + 0.5) * ROW_H = 45+30k;
  ## and a submenu sits one dropdown-width further right. Spelling the numbers
  ## out means a drift in menuBarWidths shows up here as a MISSED CLICK rather
  ## than as a coordinate silently re-derived from the code under test.
  FILE_X = 29.0'f32
  DROP_W = 150.0'f32
  ## x centre of the File dropdown (level 0) and of Open's submenu (level 1).
  DROP_X = BAR_PAD_L + DROP_W / 2.0'f32        # 85  (level 0: 10..160)
  SUB_X = BAR_PAD_L + DROP_W + DROP_W / 2.0'f32    # 235 (level 1: 160..310)

proc clickAt(x, y: float32) =
  e.pointerDown(x, y); e.pointerUp(x, y); e.tick(16.0)

## The framebuffer, sampled at (x, y).
var px = newSeq[uint32](1280 * 800)
proc rgbAt(x, y: int): tuple[r, g, b: int] =
  let v = px[y * 1280 + x]
  (int((v shr 16) and 0xFF), int((v shr 8) and 0xFF), int(v and 0xFF))
proc repaint() =
  for _ in 0 .. 4: e.tick(16.0)
  e.paintFrame(addr px[0], 1280, 800)

repaint()
# Health before anything: (34,34,34) chrome is a live frame, (16,11,11) is the
# wasm's TRAP colour. rc=0 proves nothing on its own.
check("app is healthy before the click", rgbAt(600, 5) == (34, 34, 34),
      $rgbAt(600, 5))
let blank = rgbAt(640, 400)
check("canvas starts blank white", blank == (255, 255, 255), $blank)

# --- 1. File > Open > Open File, by measured coordinates ---------------------
# File's dropdown rows, from menu.nim's File menu in order, dividers skipped:
#   0 New, 1 Open, 2 Search Images, 3 Export, 4 Save As, ...
# Row k's centre is MENU_H + (k + 0.5) * ROW_H, and the File dropdown starts at
# x = BAR_PAD_L with width 150 (menu.css `min-width: 150px`).
clickAt(FILE_X, MENU_H / 2.0'f32)                               # File
clickAt(DROP_X, MENU_H + 1.5'f32 * ROW_H)                     # row 1 = Open
repaint()
# Open's submenu sits one dropdown-width to the right and its rows start at the
# same y as their parent's. "Open File" is its first row, and the click that
# selects it is the one below - after the mock is armed.

# The dialog is host-side, so there is nothing to await: pumpPick runs inside
# tick, and with the mock armed the callback fires in the SAME tick. The mock
# is armed BEFORE the leaf is clicked - armed after, the first click would open
# a REAL modal SDL dialog and block the test.
setMockOpenFile(fixture)
clickAt(SUB_X, MENU_H + 0.5'f32 * ROW_H)
for _ in 0 .. 8: e.tick(16.0)
repaint()

check("the app did not trap while opening", e.crashed.len == 0, e.crashed)
stderr.write "LOGS: " & e.s.logs.join(" || ") & "\n"
check("chrome is still live after the open", rgbAt(600, 5) == (34, 34, 34),
      $rgbAt(600, 5))

# --- 2. The FILE's pixels are on the canvas ---------------------------------
# The fixture is opaque magenta, 24x16. The document origin is viewPosX/viewPosY
# = (LEFT_W + 8, SUBMENU_H + 8) = (218, 38) at 100% zoom, and the decoded image is
# drawn at (0,0) of the document at its NATURAL size - upstream's layer canvas is
# document-sized with `drawImage(img, 0, 0)` (base-layers.js create_layer).
#
# The check is a COUNT over the whole expected rectangle, not a single sampled
# point. A single point is what let this suite report a false negative for hours:
# the sample was at y=60, which is 22 rows BELOW the 16-row image at y=38, so it
# was reading white PAGE and calling it a failed open. Counting also proves the
# image was placed at its natural size and not stretched - a scaled blit changes
# the count, and so does a wrong origin.
proc magentaIn(x0, y0, w, h: int): int =
  for y in y0 ..< y0 + h:
    for x in x0 ..< x0 + w:
      let (r, g, b) = rgbAt(x, y)
      if abs(r - 255) <= 4 and g <= 4 and abs(b - 255) <= 4: inc result

const
  DOC_X = 218          ## viewPosX = LEFT_W + 8, LEFT_W = 210
  DOC_Y = 38           ## viewPosY = SUBMENU_H + 8
let magentaCount = magentaIn(DOC_X, DOC_Y, fixtureW, fixtureH)
# A wider net than the image, so a miss reports WHERE the magenta actually is
# rather than just that it is absent.
var foundAt = ""
for y in DOC_Y - 4 .. DOC_Y + fixtureH + 4:
  for x in DOC_X - 4 .. DOC_X + fixtureW + 4:
    let (r, g, b) = rgbAt(x, y)
    if abs(r - 255) <= 4 and g <= 4 and abs(b - 255) <= 4:
      foundAt = " first magenta at " & $x & "," & $y
      break
  if foundAt.len > 0: break
stderr.write "magenta=" & $magentaCount & $foundAt & "\n"

check("the opened file's pixels reached the canvas, at natural size",
      magentaCount == fixtureW * fixtureH,
      "got " & $magentaCount & " magenta of " & $(fixtureW * fixtureH) & " expected")

# Outside the image (past its 24x16 extent) the page is still white: the layer
# buffer is document-sized and transparent beyond the decoded area, which is
# what proves the image was placed at (0,0) rather than stretched. Sampled one
# row BELOW the image's bottom edge, where the image cannot reach.
let beyond = rgbAt(DOC_X + 10, DOC_Y + fixtureH + 6)
check("past the image the page is still white", beyond == (255, 255, 255), $beyond)

# The submenu band reports the outcome (this port's stand-in for alertify).

# The attributes band reports the outcome (this port's stand-in for alertify).
# The whole app is ONE canvas node with a draw callback, so there are no K_TEXT
# nodes to read - the check has to be the PIXELS, at ACCENT (0x49,0xA4,0x5B),
# which is the only thing in that band painted in that colour.
var sawAccent = false
for y in 31 .. 69:
  for x in 335 .. 700:
    let (r, g, b) = rgbAt(x, y)
    if abs(r - 0x49) <= 6 and abs(g - 0xA4) <= 6 and abs(b - 0x5B) <= 6:
      sawAccent = true
check("the open is reported in the attributes band", sawAccent)

# --- 3. A cancelled dialog changes nothing ----------------------------------
# This is the case that used to be indistinguishable from the item being dead:
# upstream's `change` event does not fire when the picker is dismissed, so the
# right answer is silence - the document must be untouched.
let before = magentaIn(DOC_X, DOC_Y, fixtureW, fixtureH)
setMockOpenFile("")
clickAt(FILE_X, MENU_H / 2.0'f32)
clickAt(DROP_X, MENU_H + 1.5'f32 * ROW_H)
clickAt(SUB_X, MENU_H + 0.5'f32 * ROW_H)
for _ in 0 .. 8: e.tick(16.0)
repaint()
check("a cancelled dialog leaves the document alone",
      magentaIn(DOC_X, DOC_Y, fixtureW, fixtureH) == before,
      $magentaIn(DOC_X, DOC_Y, fixtureW, fixtureH) & " vs " & $before)
check("the app did not trap on cancel", e.crashed.len == 0, e.crashed)

if fileExists(fixture): removeFile(fixture)
echo "mpopen: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)