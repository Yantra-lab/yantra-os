## A video node (U8): real footage decoded by FFmpeg's libraries and drawn by the
## engine — in an app, looping, and inside a rendered film — and only from the app's folder.
import std/[os, tables, strutils]
import engine, film, nimav

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "film"
# the clip: one second red, one second blue, 64x36 at 30 fps
block:
  var enc = openEncoder(dir / "test-clip.mp4", 64, 36, 30)
  var px = newSeq[uint32](64 * 36)
  for f in 0 ..< 60:
    let c = if f < 30: 0xFFFF0000'u32 else: 0xFF0000FF'u32
    for i in 0 ..< px.len: px[i] = c
    enc.addFrame(addr px[0], 64 * 4)
  enc.close()
writeFile(dir / ".." / "secret.mp4", readFile(dir / "test-clip.mp4"))   # a file the app must not reach

let e = start(dir / "clip.wasm", 320, 180)
var px = newSeq[uint32](320 * 180)
proc at(t: float64): uint32 =
  e.tick(t)
  e.paintFrame(addr px[0], 320, 180)
  px[90 * 320 + 160]
proc red(p: uint32): bool = ((p shr 16) and 0xFF) > 0xC0 and (p and 0xFF) < 0x40
proc blue(p: uint32): bool = (p and 0xFF) > 0xC0 and ((p shr 16) and 0xFF) < 0x40

check("the first second shows red", red(at(0)) and red(at(500)), at(500).toHex)
check("the second second shows blue", blue(at(1500)), at(1500).toHex)
check("it loops", red(at(2400)), at(2400).toHex)
check("the video keeps the engine painting while it plays", e.needsPaint)
check("a file outside the app's folder is never opened", e.videoCount == 1, $e.videoCount)
check("names that leave the folder are refused", not validAssetPath("../x.mp4") and not validAssetPath("C:/x.mp4") and
      not validAssetPath("/etc/x") and validAssetPath("clips/intro.mp4"))

# pixel content inside a rendered film
let outp = getTempDir() / "yantra_clip_film.mp4"
discard renderFilm(dir / "clip.wasm", outp, 320, 180, 2.0, fps = 30)
let d = openDecoder(outp)
var f = newSeq[uint32](320 * 180)
check("a rendered film carries the footage (red at 0.5 s)", d != nil and d.frameAt(0.5, addr f[0], 320, 180) and
      red(f[90 * 320 + 160]), if d != nil: f[90 * 320 + 160].toHex else: "no film")
check("and blue at 1.5 s", d.frameAt(1.5, addr f[0], 320, 180) and blue(f[90 * 320 + 160]), f[90 * 320 + 160].toHex)
d.close()
removeFile(dir / ".." / "secret.mp4")

echo "video: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
