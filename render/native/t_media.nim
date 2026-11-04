## P2: images decode off the UI thread at the size they are drawn, into a capped cache.
import std/os
import nimskia

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / "build" / "media"
createDir(dir)
let big = dir / "big.png"
check("a 2000x1000 test image", writePng(big, 2000, 1000, 0xFFFF0000'u32))
var px = newSeq[uint32](100 * 50)
let c = newCanvas(addr px[0], 100, 50, 100 * 4)
c.clear(0xFF000000'u32)
let first = c.drawImageAsync(big, 0, 0, 100, 50, 0, 2)
check("not cached: the first draw is a placeholder", first == imgLoading and px[25 * 100 + 50] == 0xFF000000'u32, $first)
check("the decode finishes on a worker", waitImages(5000))
let second = c.drawImageAsync(big, 0, 0, 100, 50, 0, 2)
proc reddish(v: uint32): bool = (v shr 16 and 0xFF) > 0xF0 and (v shr 8 and 0xFF) < 0x10
check("then it draws", second == imgDrawn and reddish(px[25 * 100 + 50]), $second)
let st = imageCacheStats()
check("decoded at 1/16 (125x63), not at 2000x1000", st.bytes <= 125 * 63 * 4 and st.count == 1, $st)
setImageCacheLimit(1 shl 20)                        # 1 MB: about four 256x256 images
for i in 0 ..< 12:
  let p = dir / ("tile" & $i & ".png")
  discard writePng(p, 256, 256, 0xFF00FF00'u32)
  discard c.drawImageAsync(p, 0, 0, 50, 50, 0, 2, sync = true, level = 0)
let st2 = imageCacheStats()
check("the cache stays under its cap", st2.bytes <= 1 shl 20 and st2.count <= 5, $st2)
c.free()
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
