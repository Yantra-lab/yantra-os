## Q10: libav plays an HLS playlist through the P3 player (hardware decode when the machine
## has it, software otherwise), and the engine only streams from hosts the window allows.
import std/[os, times]
import nimav

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / "build" / "hls"
createDir(dir)
var enc = openEncoder(dir / "clip.m3u8", 64, 36, 25)     # the hls muxer: a playlist and .ts segments
var px = newSeq[uint32](64 * 36)
for f in 0 ..< 100:
  for i in 0 ..< px.len: px[i] = if f < 50: 0xFFFF0000'u32 else: 0xFF0000FF'u32
  enc.addFrame(addr px[0], 64 * 4)
enc.close()
check("an HLS playlist was written", fileExists(dir / "clip.m3u8") and fileExists(dir / "clip0.ts"))
let p = openPlayer(dir / "clip.m3u8", 32, 18, false)
check("it opens as a stream", p != nil and p.hasVideo)
if p != nil:
  p.setPaused(false)
  var buf = newSeq[uint32](32 * 18)
  var frames = 0
  let t0 = epochTime()
  while epochTime() - t0 < 2.5:
    var w, h: int
    if p.nextFrame(addr buf[0], buf.len * 4, w, h): inc frames
    sleep(15)
  check("frames keep coming across segments", frames > 30, $frames)
  check("and it reaches the blue half", (buf[9 * 32 + 16] and 0xFF) > 0xC0, $buf[9 * 32 + 16])
  p.close()
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
