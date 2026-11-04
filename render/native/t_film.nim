## Films from code (roadmap U8) and steps in time (`after`): the pitch intro
## (examples/film/intro.nim) rendered on an exact clock and encoded to a real video.
import std/[os, tables, hashes]
import engine, film, nimav
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let wasm = currentSourcePath().parentDir / ".." / ".." / "examples" / "film" / "intro.wasm"
const W = 640
const H = 360
proc hasText(e: Engine; s: string): bool =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == s: return true

# steps in time: the scene moves on by itself at 3.6 s, exactly
let e = start(wasm, W, H, 1, intro = true)
var px = newSeq[uint32](W * H)
e.tick(0)
check("the first scene starts", e.hasText("Yantra") and not e.hasText("Every app in its own sandbox."))
var titleId = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == "Yantra": titleId = int32(i)
let titleOpacity = e.motionPose(titleId).opacity
check("its title starts from nothing (intro mode plays enter on the first screen)", titleOpacity < 0.05, $titleOpacity)
check("an `after` step is waiting", e.pendingTimers == 1)
e.tick(3599)
e.ensureLayout()
check("just before 3.6 s nothing has changed", e.hasText("Yantra"))
e.tick(3600)
e.ensureLayout()
check("at 3.6 s the next scene is up", e.hasText("Every app in its own sandbox.") and e.pendingTimers == 0)
e.paintFrame(addr px[0], W, H)
check("and the old scene is leaving, not gone (its pills fade out)", e.ghostCount > 0, $e.ghostCount)

# every frame is the same on every run
let a = frameAt(wasm, W, H, 1200, fps = 30)
let b = frameAt(wasm, W, H, 1200, fps = 30)
let c = frameAt(wasm, W, H, 2400, fps = 30)
check("a frame is identical on every render", hash(a) == hash(b))
check("and frames differ over time (it moves)", hash(a) != hash(c))
var lit = 0
for p in c:
  if (p and 0xFF) > 0xC0 and ((p shr 8) and 0xFF) > 0xC0: inc lit
check("the title is really drawn (bright pixels)", lit > 500, $lit)
var cx, n = 0
for i, p in c:
  if (p and 0xFF) > 0xC0 and ((p shr 8) and 0xFF) > 0xC0:
    cx += i mod W
    inc n
check("and centred: a film designed at 1280x720 scales to fill any output size", n > 0 and abs(cx div n - W div 2) < W div 8,
      $(cx div max(n, 1)))

# a real video file
let outp = getTempDir() / "yantra_intro_test.mp4"
removeFile(outp)
let r = renderFilm(wasm, outp, W, H, 5.0, fps = 30)
let info = probe(outp)
check("renderFilm writes a video", fileExists(outp) and r.frames == 150, $r.frames)
let fileOk = info.frames == 150 and info.width == W and info.height == H and info.codec == "h264" and
             abs(info.seconds - 5.0) < 0.1
check("FFmpeg reads back 150 frames of 640x360 H.264 lasting 5 s", fileOk, $info)
let big = openFilm(wasm, 1920, 1080)
check("a film opened at 1080p lays out at its design size, scaled 1.5x", big.width == 1280 and big.scale == 1.5,
      $big.width & " " & $big.scale)

# the GPU path: same film, drawn on the GPU (fast for shaders and blurs), still a valid video
let gp = getTempDir() / "yantra_intro_gpu.mp4"
removeFile(gp)
let rg = renderFilm(wasm, gp, W, H, 2.0, fps = 30, gpu = true)
let gi = probe(gp)
let gpuOk = rg.frames == 60 and gi.frames == 60 and gi.width == W and gi.codec == "h264"
check("a film renders on the GPU too (60 frames of H.264)", gpuOk, $gi)
let cpuFrame = openDecoder(outp)
let gpuFrame = openDecoder(gp)
var fc = newSeq[uint32](W * H)
var fg = newSeq[uint32](W * H)
discard cpuFrame.frameAt(1.5, addr fc[0], W, H)
discard gpuFrame.frameAt(1.5, addr fg[0], W, H)
var d = 0.0
for i in 0 ..< fc.len:
  for sh in [0'u32, 8, 16]: d += abs(float((fc[i] shr sh) and 0xFF) - float((fg[i] shr sh) and 0xFF))
let meanDiff = d / float(fc.len * 3)
check("and looks the same as the CPU film (mean difference under 4 of 255)", meanDiff < 4, $meanDiff)
cpuFrame.close()
gpuFrame.close()

echo "film: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
