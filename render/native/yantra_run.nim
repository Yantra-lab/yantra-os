## render/native/yantra_run.nim
## Default zero-CLI entrypoint for Yantra OS (`bin/yantra` & `bin/yantra.exe`):
## - Defaults to launching `apps/desktop/app.wasm` when invoked with no arguments (double-click!)
## - Starts `DevWatcher` (`--watch` on by default) for instant `<100ms` WASM hot-reload
## - Starts `McpServer` on `127.0.0.1:9229` for BrowserOS-parity AI agent control
## - Headless proof mode: `--screenshot=out.png --frames=N --script="..."` renders
##   through the REAL engine (Yoga + Skia) with scripted pointer/key input, no window.
##
## Script commands (semicolon-separated; drive.nim semantics, same probe family):
##   click:X,Y  down:X,Y  up:X,Y  move:X,Y  drag:X1,Y1,X2,Y2  wait:N
##   key:CODE            key press (SDL keycode: letters are lowercase ASCII)
##   keym:CODE,MODS      key press with mods (1 = shift for capitals, 0xC0 = ctrl)
##   text:"STRING"       type into focused text inputs (input-node apps)
##   boxes               stderr dump of laid-out boxes (find click coordinates)
##   handlers            stderr dump of registered event handlers
##   crash               stderr dump of crash state

import std/[os, strutils, tables]
import engine, nimskia, nimsdl3, devwatch, mcp_server
import ../../host/host, ../../host/tree
import ../../protocol/wire

const
  WinW = 1440
  WinH = 900

const embeddedDesktopWasm = staticRead("../../apps/desktop/app.wasm")
  ## Desktop bytes baked into the exe at compile time: double-clicking the exe
  ## (or Yantra.bat) always boots desktop — CLI arg > sidecar file > embedded.

proc nums(parts: openArray[string]): seq[int] =
  for part in parts:
    for tok in part.split(','):
      let t = tok.strip()
      if t.len == 0: continue
      try: result.add parseInt(t)
      except ValueError: discard

proc runScript(e: Engine; script: string; startClock: float64) =
  ## Applies scripted input, then settles. startClock continues the pre-roll:
  ## the engine pins e.now = max(e.now, ms), so a restarted clock would starve
  ## evFrame (needs now - lastFrameAt >= 12) and all repaints/syncs would stop.
  var clockMs = startClock
  proc frame() =
    for _ in 0 .. 4:
      clockMs += 16.0'f64
      e.tick(clockMs)
    e.ensureLayout()
  if script.len > 0:
    for cmd in script.split(';'):
      let c = cmd.strip()
      if c.len == 0: continue
      let p = c.split(':')
      let name = p[0]
      let v = nums(p[1 .. ^1])
      case name
      of "boxes":
        for id in e.boxes.keys:
          let b = e.boxes[id]
          let n = e.node(id)
          stderr.writeLine("box " & $id & " kind=" & $n.kind &
            " x=" & $b.x & " y=" & $b.y & " w=" & $b.w & " h=" & $b.h)
      of "handlers":
        for id in e.boxes.keys:
          for ev in [20'i32, 21'i32, 22'i32, 1'i32, 15'i32, 33'i32]:
            let hv = e.s.handlerFor(id.int32, ev)
            if hv >= 0:
              stderr.writeLine("handler node=" & $id & " event=" & $ev & " h=" & $hv)
      of "avstate":
        stderr.writeLine("nodes=" & $e.s.nodes.len &
          " children=" & $e.children.len)
        for id in e.children.keys:
          let b = e.boxes.getOrDefault(id)
          stderr.writeLine("child node=" & $id & " src=" & e.node(id).sProp(P_SOURCE) &
            " box=" & $b.x & "," & $b.y & "," & $b.w & "," & $b.h &
            " crashed=[" & e.children[id].crashed & "]")
        let hit = e.hitTest(900.0'f32, 450.0'f32)
        stderr.writeLine("hit(900,450)=" & $hit &
          (if e.s.valid(hit): " kind=" & $e.node(hit).kind else: "") &
          " activeChild=" & $e.activeChild & " pressed=" & $e.pressed)
      of "crash":
        stderr.writeLine("crashed=[" & e.crashed & "] dirty=" & $e.dirty)
        if e.crashed.len > 0:
          for ln in e.crashed.splitLines:
            if ln.len > 0: stderr.writeLine("CRASH| " & ln)
        else:
          stderr.writeLine("crash: NONE")
      of "click":
        if v.len >= 2:
          e.pointerDown(v[0].float32, v[1].float32)
          e.pointerUp(v[0].float32, v[1].float32)
      of "down":
        if v.len >= 2: e.pointerDown(v[0].float32, v[1].float32)
      of "up":
        if v.len >= 2: e.pointerUp(v[0].float32, v[1].float32)
      of "move":
        if v.len >= 2: e.pointerMove(v[0].float32, v[1].float32)
      of "drag":
        if v.len >= 4:
          e.pointerDown(v[0].float32, v[1].float32)
          for i in 1 .. 8:
            let t = i.float / 8.0'f32
            e.pointerMove(v[0].float32 + (v[2] - v[0]).float32 * t,
                          v[1].float32 + (v[3] - v[1]).float32 * t)
          e.pointerUp(v[2].float32, v[3].float32)
      of "key":
        if v.len >= 1: e.key(int32(v[0]))
      of "keym":
        if v.len >= 2: e.key(int32(v[0]), int32(v[1]))
      of "text":
        if p.len >= 2: e.typeText(p[1].strip(chars = {'"'}))
      of "wait":
        let n = if v.len >= 1: v[0] else: 1
        for _ in 0 ..< n: frame()
      else:
        discard
    frame()
  frame()

proc runHeadless(wasmPath, shotOut: string; frames: int; script: string): int =
  discard newDevWatcher(getCurrentDir())
  let e = start(wasmPath, WinW.float32, WinH.float32, 1)
  var clockMs = 0.0'f64
  for _ in 0 ..< max(frames, 1):
    clockMs += 16.0'f64
    e.tick(clockMs)
  if script.len > 0:
    runScript(e, script, clockMs)
  else:
    for _ in 0 .. 4:
      clockMs += 16.0'f64
      e.tick(clockMs)
  e.ensureLayout()
  var px = newSeq[uint32](WinW * WinH)
  e.paintFrame(addr px[0], WinW, WinH)
  if shotOut.len > 0:
    if not savePixels(shotOut, addr px[0], WinW, WinH):
      stderr.writeLine("could not write " & shotOut)
      return 1
    echo "frame " & $WinW & "x" & $WinH & " -> " & shotOut
  if e.crashed.len > 0:
    stderr.writeLine("crashed=[" & e.crashed & "]")
    return 2
  0

proc routeEvent(e: Engine; ev: InputEvent; scale: float32) =
  let k = kindOf(ev)
  case k
  of evDown:
    e.pointerDown(ev.x / scale, ev.y / scale)
  of evUp:
    e.pointerUp(ev.x / scale, ev.y / scale)
  of evMove:
    e.pointerMove(ev.x / scale, ev.y / scale)
  of evWheel:
    e.wheel(ev.wheel / scale, dx = ev.dx / scale)
  of evKey:
    e.key(ev.key, ev.mods)
  of evKeyUp:
    e.keyUp(ev.key)
  of evText:
    e.typeText(textOf(ev))
  of evResize:
    discard
  else:
    discard

proc runLoop(wasmPath: string; enableWatch: bool; mcpPort: int) =
  if not nimsdl3.init():
    quit "no window: " & lastError(), 1
  let e = start(wasmPath, WinW.float32, WinH.float32, 1)
  let win = openWindow("Yantra", WinW, WinH)
  if win.isNil:
    quit "could not open window: " & lastError(), 1
  let (pw, ph) = win.pixelSize()
  let density = win.density()
  let scale = if density > 0: density else: 1.0'f32
  var watcher: DevWatcher = nil
  if enableWatch:
    watcher = newDevWatcher(getCurrentDir())
  var mcpSrv = if mcpPort > 0: newMcpServer(mcpPort) else: nil
  var px = newSeq[uint32](pw * ph)
  e.resize(pw.float32 / scale, ph.float32 / scale)
  var ev: InputEvent
  var running = true
  while running:
    while win.wait(ev, 0):
      if kindOf(ev) == evQuit:
        running = false
        break
      elif kindOf(ev) == evResize:
        let (nw, nh) = win.pixelSize()
        if nw * nh != px.len:
          px.setLen(nw * nh)
        e.resize(nw.float32 / scale, nh.float32 / scale)
      else:
        routeEvent(e, ev, scale)
    if not running: break
    if not watcher.isNil: watcher.poll(e)
    if not mcpSrv.isNil: mcpSrv.pollMcp(e)
    e.tick(ticksMs().float64)
    let t = e.title()
    if t.len > 0: win.setTitle(t)
    setCursor(e.cursorKind())
    let (cw, ch) = win.pixelSize()
    if cw * ch == px.len:
      e.paintFrame(addr px[0], cw, ch)
      discard win.present(addr px[0], cw, ch, cw * 4)
  win.close()
  nimsdl3.shutdown()

proc main() =
  var wasmPath = "apps/desktop/app.wasm"
  var wasmArgGiven = false
  var enableWatch = true
  var mcpPort = 9229
  var screenshotOut = ""
  var screenshotFrames = 12
  var script = ""

  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a == "--no-watch":
      enableWatch = false
    elif a == "--watch":
      enableWatch = true
    elif a.startsWith("--mcp-port="):
      mcpPort = try: parseInt(a.split('=')[1]) except: 9229
    elif a.startsWith("--screenshot="):
      screenshotOut = a.split('=')[1]
    elif a.startsWith("--frames="):
      screenshotFrames = try: parseInt(a.split('=')[1]) except: 12
    elif a.startsWith("--script="):
      script = a[a.find('=') + 1 .. ^1]
    elif not a.startsWith("-"):
      wasmPath = a
      wasmArgGiven = true

  if not wasmArgGiven and not fileExists(wasmPath):
    try:
      createDir("apps" / "desktop")
      writeFile(wasmPath, embeddedDesktopWasm)
    except OSError, IOError:
      discard

  if screenshotOut.len > 0:
    quit runHeadless(wasmPath, screenshotOut, screenshotFrames, script)
  else:
    runLoop(wasmPath, enableWatch, mcpPort)

when isMainModule:
  main()
