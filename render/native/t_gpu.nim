## The GPU path (roadmap U5): the same engine paint, drawn by Skia on the GPU (OpenGL),
## gives the same picture as the CPU and is much faster on effects-heavy screens.
import std/[os, monotimes, times, strutils]
import engine, nimsdl3, nimskia

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const W = 1000
const H = 700
let fx = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "fx.wasm"

doAssert nimsdl3.init(), lastError()
let win = openGlWindow("gpu test", 64, 64, hidden = true)
check("an OpenGL window opens", not win.isNil, lastError())
let gpu = newGpu()
check("Skia gets a GPU context on it", not gpu.isNil)
let surf = gpu.offscreen(W, H)
check("and an off-screen GPU surface", not surf.isNil)

let eg = start(fx, W, H)
let ec = start(fx, W, H)
var gpuPx = newSeq[uint32](W * H)
var cpuPx = newSeq[uint32](W * H)
eg.tick(500); ec.tick(500)
eg.paint(surf.canvas)
gpu.flush(wait = true)
check("a GPU frame reads back", surf.readPixels(addr gpuPx[0], W, H))
ec.paintFrame(addr cpuPx[0], W, H)
var diff = 0.0
for i in 0 ..< gpuPx.len:
  for sh in [0'u32, 8, 16]:
    diff += abs(float((gpuPx[i] shr sh) and 0xFF) - float((cpuPx[i] shr sh) and 0xFF))
let meanDiff = diff / float(gpuPx.len * 3)
check("the GPU draws the same picture as the CPU (mean difference under 3 of 255)", meanDiff < 3, meanDiff.formatFloat(ffDecimal, 2))

proc timeIt(e: Engine; gpuPath: bool): float =
  let t0 = getMonoTime()
  for i in 1 .. 30:
    e.tick(500 + float64(i) * 16.67)
    if gpuPath:
      e.paint(surf.canvas)
      gpu.flush(wait = true)
    else:
      e.paintFrame(addr cpuPx[0], W, H)
  float((getMonoTime() - t0).inMicroseconds) / 1000 / 30
let tg = timeIt(eg, true)
let tc = timeIt(ec, false)
echo "  effects poster ", W, "x", H, ": GPU ", tg.formatFloat(ffDecimal, 1), " ms, CPU ", tc.formatFloat(ffDecimal, 1), " ms per frame"
check("the GPU is at least 4x faster on it", tg * 4 < tc, tg.formatFloat(ffDecimal, 1) & " vs " & tc.formatFloat(ffDecimal, 1))
check("and fast enough for 60 fps", tg < 16.7, tg.formatFloat(ffDecimal, 1) & " ms")

# the window path the runner uses: draw into the window's own framebuffer and show it
let ws = gpu.windowSurface(64, 64)
check("the window's framebuffer takes GPU frames", not ws.isNil)
eg.paint(ws.canvas)
gpu.flush()
win.swap()
ws.free()

surf.free()
gpu.free()
win.close()
shutdown()
echo "gpu: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
