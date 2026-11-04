## yantra_android — the Android entry point of the Yantra native host.
##
## WHAT THIS IS
##   The SAME host engine as the desktop (`yantra-os/render/native/engine.nim`,
##   `yantra-os/host/host.nim`), the SAME sandboxed WebAssembly apps, the SAME
##   `env.y_*` import table. Nothing is re-implemented here: this file is the
##   platform glue that a desktop runner gets for free from its window system —
##   find where the app modules live, open a window, pump whatever input SDL
##   reports, tick the engine, paint a frame with Skia and hand it to SDL.
##
##   On desktop that glue is `yantra-os/render/native/yantra_run.nim` (252 lines,
##   a `main()`). On Android the process is a shared library loaded by SDL's own
##   Java glue (`org.libsdl.app.SDLActivity`), which dlsym's `SDL_main`; so the
##   same sequence lives behind that symbol here.
##
## PACKAGING FACTS THIS FILE DEPENDS ON (see docs/ANDROID.md)
##   * libSDL3.so, libmain.so (= this file, Nim -> aarch64-linux-android) and
##     libyantrahost glue are the app's APK `lib/arm64-v8a/*.so`.
##   * The app modules are APK `assets/apps/<id>/app.wasm`, byte-identical to the
##     desktop's `yantra-os/apps/<id>/app.wasm`. MainActivity.java copies them to
##     the app's private storage on first launch so the engine can open them by
##     path; the copy is a byte copy (`FileChannel.transferTo`), never a rebuild.

import std/[os, strutils]
import "../../yantra-os/render/native/engine"
import "../../yantra-os/host/host"
import "../../yantra-os/host/tree"
import nimsdl3, nimskia

const
  Tag = "YantraHost"
  ## The default app is the same one a desktop double-click starts.
  DefaultApp = "desktop"

# --- logging ------------------------------------------------------------------
# Android has no terminal: stderr from a lib goes nowhere. logcat is the proof
# surface, so every milestone the acceptance needs a line there.

when defined(android):
  proc alog(prio: cint; tag, fmt: cstring) {.importc: "__android_log_print", varargs,
      cdecl, header: "<android/log.h>".}
  proc logi(msg: string) = alog(4'i32, Tag.cstring, "%s", msg.cstring)      # ANDROID_LOG_INFO
  proc logw(msg: string) = alog(5'i32, Tag.cstring, "%s", msg.cstring)      # WARN
  proc loge(msg: string) = alog(6'i32, Tag.cstring, "%s", msg.cstring)      # ERROR
else:
  proc logi(msg: string) = stderr.writeLine("[yantra " & Tag & "] " & msg)
  proc logw(msg: string) = logi(msg)
  proc loge(msg: string) = logi(msg)

# --- SDL's Android storage path (the app's writable private dir) ---------------
# SDL's Java glue reports getFilesDir() into SDL on startup; using its own API
# keeps this file free of JNI.

proc SDL_GetAndroidInternalStoragePath(): cstring {.importc, cdecl, header: "<SDL3/SDL_system.h>".}

# --- input routing: identical to the desktop runner's ------------------------

proc routeEvent(e: Engine; ev: InputEvent; scale: float32) =
  case kindOf(ev)
  of evDown:   e.pointerDown(ev.x / scale, ev.y / scale)
  of evUp:     e.pointerUp(ev.x / scale, ev.y / scale)
  of evMove:   e.pointerMove(ev.x / scale, ev.y / scale)
  of evWheel:  e.wheel(ev.wheel / scale, dx = ev.dx / scale)
  of evKey:    e.key(ev.key, ev.mods)
  of evKeyUp:  e.keyUp(ev.key)
  of evText:   e.typeText(textOf(ev))
  else:        discard

# --- where the apps live ------------------------------------------------------

proc dataDir(): string =
  ## The app's private storage: SDL's internal path, overridable by the env var
  ## MainActivity sets (handy from `adb shell`, and for the qemu proof run).
  result = getEnv("YANTRA_DATA_DIR")
  if result.len > 0: return
  when defined(android):
    let p = SDL_GetAndroidInternalStoragePath()
    if p != nil: result = $p
  if result.len == 0: result = getCurrentDir()

proc findApp(a: string): string =
  ## `apps/<id>/app.wasm` under the data dir. `a` may be an id, a path, or "".
  let root = dataDir() / "apps"
  if a.len > 0:
    if a.endsWith(".wasm") and fileExists(a): return a
    if dirExists(a / "") or fileExists(root / a / "app.wasm"): return root / a / "app.wasm"
    if fileExists(a): return a
  if fileExists(root / DefaultApp / "app.wasm"): return root / DefaultApp / "app.wasm"
  # last resort: the first app in the folder, so a missing default still boots
  for kind, path in walkDir(root):
    if kind == pcDir and fileExists(path / "app.wasm"): return path / "app.wasm"
  ""

proc appIdOf(wasmPath: string): string =
  ## "…/apps/<id>/app.wasm" -> "<id>"; used for the log line only.
  let p = wasmPath.replace('\\', '/')
  let marker = "/apps/"
  let i = p.rfind(marker)
  if i < 0: return "?"
  p[i + marker.len .. ^1].split('/')[0]

# --- the run loop -------------------------------------------------------------

proc runApp(appArg: string; frames: int; shotOut: string): int =
  ## The desktop runner's `runLoop`, with Android's numbers: the window is the
  ## screen, the pointer is a finger (SDL turns touches into mouse events), and
  ## the frame is painted into a CPU buffer and uploaded — the same call
  ## (`e.paintFrame`) the desktop uses.
  # The headless screenshot path (used by the qemu proof and by `--screenshot`)
  # needs no window at all, so it does not touch SDL.
  if shotOut.len == 0 and not nimsdl3.init():
    loge("no video: " & lastError())
    return 1
  let wasmPath = findApp(appArg)
  if wasmPath.len == 0:
    loge("no app.wasm found under " & dataDir() / "apps")
    return 1
  logi("engine boot: app=" & appIdOf(wasmPath) & " module=" & wasmPath &
       " bytes=" & $getFileSize(wasmPath))
  let e = try: start(wasmPath, 1440'f32, 900'f32, 1'f32)
          except CatchableError as err:
            loge("start failed: " & err.msg); return 1
  if e.crashed.len > 0:
    logw("app trapped at start: " & e.crashed)

  if shotOut.len > 0:
    # headless proof path (the desktop's --screenshot): no window needed
    var clock = 0.0'f64
    for _ in 0 ..< max(frames, 1):
      clock += 16.0
      e.tick(clock)
    e.ensureLayout()
    var px = newSeq[uint32](1440 * 900)
    e.paintFrame(addr px[0], 1440, 900)
    var nonzero = 0
    for v in px:
      if v != px[0]: inc nonzero
    if savePixels(shotOut, addr px[0], 1440, 900):
      logi("frame 1440x900 -> " & shotOut & " changes=" & $nonzero)
    else:
      loge("could not write " & shotOut)
      return 1
    logi("crashed=[" & e.crashed & "]")
    return 0

  let win = openWindow("Yantra", 1440, 900)
  if win.isNil:
    loge("could not open window: " & lastError())
    return 1
  win.show()
  var (pw, ph) = win.pixelSize()
  let density = win.density()
  let scale = if density > 0: density else: 1.0'f32
  logi("window " & $pw & "x" & $ph & " density=" & $scale)
  var px = newSeq[uint32](pw * ph)
  e.resize(pw.float32 / scale, ph.float32 / scale)
  var ev: InputEvent
  var running = true
  var painted = 0
  var lastPaintLog = 0
  while running:
    while win.wait(ev, 0):
      if kindOf(ev) == evQuit:
        running = false
        break
      elif kindOf(ev) == evResize:
        let (nw, nh) = win.pixelSize()
        if nw * nh != px.len: px.setLen(nw * nh)
        e.resize(nw.float32 / scale, nh.float32 / scale)
      else:
        routeEvent(e, ev, scale)
    if not running: break
    e.tick(ticksMs().float64)
    let (cw, ch) = win.pixelSize()
    if cw * ch == px.len and cw > 0:
      e.paintFrame(addr px[0], cw, ch)
      if win.present(addr px[0], cw, ch, cw * 4):
        inc painted
        if painted == 1 or painted - lastPaintLog >= 300:
          lastPaintLog = painted
          logi("frame #" & $painted & " " & $cw & "x" & $ch & " (t=" & $ticksMs() & "ms)")
  win.close()
  nimsdl3.shutdown()
  logi("loop ended after " & $painted & " painted frames")
  0

# --- entry points -------------------------------------------------------------

proc main(argc: cint; argv: ptr cstring): int =
  var appArg = getEnv("YANTRA_APP")
  if argc > 1 and argv != nil:
    let a = $argv[1]
    if a.len > 0 and not a.startsWith("-"): appArg = a
  var frames = 8
  var shot = ""
  if argc > 1 and argv != nil:
    for i in 1 ..< int(argc):
      let a = $argv[i]
      if a.startsWith("--screenshot="): shot = a.split('=')[1]
      elif a.startsWith("--frames="): frames = try: parseInt(a.split('=')[1]) except: 8
  result = runApp(appArg, frames, shot)

proc NimMain() {.importc, cdecl.}
  ## Nim's runtime bootstrap, generated by `--app:lib`; a library build has no
  ## C `main`, so nothing else would call it.

proc SDL_main(argc: cint; argv: ptr cstring): cint {.exportc: "SDL_main", cdecl, dynlib.} =
  ## SDL's Java glue (SDLActivity -> nativeRunMain -> dlsym("SDL_main")) calls this
  ## on SDL's own thread.
  NimMain()
  result = cint(main(argc, argv))

when isMainModule and not defined(androidLib):
  quit(SDL_main(cint(paramCount()), nil))
