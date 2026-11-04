## Films from code (roadmap U8): any Yantra app rendered frame by frame on an exact
## clock and encoded straight to video — no screen capture, no PNG round-trip. The
## same app runs live in a window; here time is simply stepped one frame at a time,
## so every frame is the same on every run.
##
##   yantra-film intro.wasm intro.mp4 --seconds 6 --fps 60 --size 1920x1080

import std/[os, strutils]
import engine, nimav, nimskia, nimsdl3

type FilmResult* = object
  frames*: int
  path*: string

proc openFilm*(wasm: string; width, height: int): Engine =
  ## The film's app, laid out at the size it was designed for (`app(..., width, height)`)
  ## and scaled to fill `width` x `height`: one film renders at 720p, 1080p or 4K alike.
  result = start(wasm, float32(width), float32(height), 1, intro = true)
  let (aw, ah) = result.windowSizeHint
  if aw > 0 and ah > 0:
    let sc = min(float32(width) / float32(aw), float32(height) / float32(ah))
    result.scale = sc
    result.resize(float32(width) / sc, float32(height) / sc)

proc frameAt*(wasm: string; width, height: int; t: float64; fps = 60): seq[uint32] =
  ## One frame of the film at time `t` (ms), rendered the way `renderFilm` does:
  ## every frame before it is stepped too, so motion and `after` steps are exact.
  let e = openFilm(wasm, width, height)
  result = newSeq[uint32](width * height)
  var i = 0
  while true:
    let now = float64(i) * 1000 / float64(fps)
    if now > t: break
    e.tick(now)
    e.paintFrame(addr result[0], width, height)
    inc i

type FrameSink = object
  ## Where frames are drawn: the CPU (the default: the same bytes on every machine) or the
  ## GPU (much faster for shaders and blurs; tiny differences between graphics cards).
  gpu: Gpu
  surf: Surface
  win: Window

proc openSink(width, height: int; useGpu: bool): FrameSink =
  if not useGpu: return
  if not nimsdl3.init(): raise newException(AvError, "no GPU: " & lastError())
  result.win = openGlWindow("yantra-film", 64, 64, hidden = true)
  if result.win.isNil: raise newException(AvError, "no GPU: OpenGL is not available")
  result.gpu = newGpu()
  if result.gpu.isNil: raise newException(AvError, "no GPU: Skia could not use OpenGL")
  result.surf = result.gpu.offscreen(width, height)

proc draw(s: FrameSink; e: Engine; px: var seq[uint32]; width, height: int) =
  if s.surf.isNil:
    e.paintFrame(addr px[0], width, height)
  else:
    e.paint(s.surf.canvas)
    s.gpu.flush(wait = true)
    if not s.surf.readPixels(addr px[0], width, height): raise newException(AvError, "reading a GPU frame failed")

proc close(s: FrameSink) =
  if not s.surf.isNil: s.surf.free()
  if not s.gpu.isNil: s.gpu.free()
  if not s.win.isNil: s.win.close()

proc renderFilm*(wasm, output: string; width, height: int; seconds: float; fps = 60; crf = 18;
                 progress: proc (frame, total: int) = nil; gpu = false): FilmResult =
  ## Renders `seconds` of the app at `fps` into `output` (.mp4, .mov, .mkv, .webm).
  ## `gpu`: draw each frame on the GPU (fast for shaders and blurs) instead of the CPU.
  let e = openFilm(wasm, width, height)
  if e.crashed.len > 0:
    raise newException(AvError, "the film's app stopped while starting: " & e.crashed)
  let sink = openSink(width, height, gpu)
  defer: sink.close()
  var px = newSeq[uint32](width * height)
  var enc = openEncoder(output, width, height, fps, crf)
  let total = int(seconds * float(fps) + 0.5)
  for i in 0 ..< total:
    e.tick(float64(i) * 1000 / float64(fps))
    sink.draw(e, px, width, height)
    enc.addFrame(addr px[0], width * 4)
    if progress != nil: progress(i + 1, total)
  enc.close()
  FilmResult(frames: total, path: output)

when isMainModule:
  proc usage() =
    echo "usage: yantra-film <app.wasm> <out.mp4> [--seconds 6] [--fps 60] [--size 1920x1080] [--crf 18] [--gpu]"
    quit(2)
  if paramCount() < 2: usage()
  var seconds = 6.0
  var fps = 60
  var w = 1920
  var h = 1080
  var crf = 18
  var gpu = false
  var i = 3
  while i <= paramCount():
    let a = paramStr(i)
    if a == "--gpu":
      gpu = true
      inc i
      continue
    if i == paramCount(): usage()
    let v = paramStr(i + 1)
    case a
    of "--seconds": seconds = parseFloat(v)
    of "--fps": fps = parseInt(v)
    of "--crf": crf = parseInt(v)
    of "--size":
      let p = v.toLowerAscii.split('x')
      if p.len != 2: usage()
      w = parseInt(p[0]); h = parseInt(p[1])
    else: usage()
    i += 2
  let r = renderFilm(paramStr(1), paramStr(2), w, h, seconds, fps, crf,
                     proc (f, t: int) =
                       if f mod fps == 0 or f == t: stdout.write "\r" & $f & "/" & $t & " frames"; stdout.flushFile,
                     gpu)
  echo "\nwrote ", r.path, " (", r.frames, " frames, ", w, "x", h, " at ", fps, " fps)"
