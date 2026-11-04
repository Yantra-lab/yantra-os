## Native engine tests for K_IMAGE: layout, Skia decode, fit/cover, corner clipping,
## and path sandboxing.
import std/[os, tables, strutils]
import engine
import nimskia

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let buildDir = here / "build"
createDir(buildDir)

# 1. Create a 20x10 pure red test image
let imgPath = buildDir / "test_card.png"
check("create test image", writePng(imgPath, 20, 10, 0xFFFF0000'u32))

let (iw, ih) = imageInfo(imgPath)
check("imageInfo returns correct dimensions", iw == 20 and ih == 10, $iw & "x" & $ih)

# 2. Direct Skia canvas tests: contain, cover, radius
var px = newSeq[uint32](40 * 40)
let cv = newCanvas(addr px[0], 40, 40, 40 * 4)

# (a) Contain: 20x10 image into 40x40 container letterboxes vertically (y: 10..29)
cv.clear(0xFF000000'u32)
cv.drawImage(imgPath, 0, 0, 40, 40, 0, 0) # fit = 0 (contain)
check("contain: middle is red", px[20 * 40 + 20] == 0xFFFF0000'u32, $px[20 * 40 + 20].toHex)
check("contain: top letterbox is black", px[2 * 40 + 20] == 0xFF000000'u32, $px[2 * 40 + 20].toHex)
check("contain: bottom letterbox is black", px[38 * 40 + 20] == 0xFF000000'u32, $px[38 * 40 + 20].toHex)

# (b) Cover: 20x10 image into 40x40 container scales to 80x40 and fills entire rect
cv.clear(0xFF000000'u32)
cv.drawImage(imgPath, 0, 0, 40, 40, 0, 1) # fit = 1 (cover)
check("cover: middle is red", px[20 * 40 + 20] == 0xFFFF0000'u32, $px[20 * 40 + 20].toHex)
check("cover: top edge is red", px[2 * 40 + 20] == 0xFFFF0000'u32, $px[2 * 40 + 20].toHex)
check("cover: bottom edge is red", px[38 * 40 + 20] == 0xFFFF0000'u32, $px[38 * 40 + 20].toHex)

# (c) Radius clipping: corner pixels clipped out
cv.clear(0xFF000000'u32)
cv.drawImage(imgPath, 0, 0, 40, 40, 12, 1) # radius = 12
check("radius: corner (0,0) is clipped to black", px[0] == 0xFF000000'u32, $px[0].toHex)
check("radius: interior (20,20) is red", px[20 * 40 + 20] == 0xFFFF0000'u32, $px[20 * 40 + 20].toHex)

# (d) Invalid path draws nothing
cv.clear(0xFF000000'u32)
cv.drawImage("../secret.png", 0, 0, 40, 40, 0, 0)
check("traversal path draws nothing", px[20 * 40 + 20] == 0xFF000000'u32)
cv.drawImage("C:/secret.png", 0, 0, 40, 40, 0, 0)
check("absolute path draws nothing", px[20 * 40 + 20] == 0xFF000000'u32)

# 3. Path sandboxing tests
check("sandbox: parent traversal rejected", not validAssetPath("../secret.png"))
check("sandbox: absolute drive path rejected", not validAssetPath("C:/secret.png"))
check("sandbox: absolute root path rejected", not validAssetPath("/secret.png"))
check("sandbox: backslash root rejected", not validAssetPath("\\secret.png"))
check("sandbox: plain filename allowed", validAssetPath("test_card.png"))
check("sandbox: subfolder relative path allowed", validAssetPath("assets/test_card.png"))

# 4. Engine integration through a real compiled app
let wasmPath = buildDir / "img_app.wasm"
let eng = start(wasmPath, 100, 100)
check("engine: sandbox resolves plain relative asset", sameFile(eng.resolveAsset("test_card.png"), imgPath))
check("engine: sandbox blocks path traversal", eng.resolveAsset("../secret.png") == "")
check("engine: sandbox blocks absolute path", eng.resolveAsset("C:/secret.png") == "")

var engPx = newSeq[uint32](100 * 100)
eng.paintFrame(addr engPx[0], 100, 100)

var foundNode = false
for id, b in eng.boxes:
  if id > 0 and b.w == 60 and b.h == 60:
    foundNode = true
    let cx = int(b.x + b.w / 2)
    let cy = int(b.y + b.h / 2)
    check("engine: painted image pixels are red", engPx[cy * 100 + cx] == 0xFFFF0000'u32, $engPx[cy * 100 + cx].toHex)
check("engine: image node is laid out by Yoga at 60x60", foundNode)

removeFile(imgPath)

echo "image: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
