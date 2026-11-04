## Drives an app's wasm through REAL pointer input and dumps the frame.
##
##   drive app.wasm out.raw W H SCALE SCRIPT
##
## This exists because unit tests proved the algorithms but not the wiring: a
## whole family of miniPaint tools passed every test while being unreachable in
## the app, because the app never allocated the struct the tests read. A test
## harness that only calls procs cannot catch that class of bug. This one goes
## through the host's pointer pipeline — pointerDown / pointerMove / pointerUp —
## so a tool that does not respond to a click stays unresponsive on screen.
##
## SCRIPT is a SEMICOLON-separated command list, applied in order. NOT commas:
## the arguments contain commas (click:21,57), so a comma separator splits one
## command in half. That bug cost a debugging round and is easy to re-introduce.
##
##   click:X,Y            pointerDown then pointerUp at (X, Y)
##   down:X,Y             pointerDown only
##   up:X,Y               pointerUp only
##   move:X,Y             pointerMove only
##   drag:X1,Y1,X2,Y2     down at A, move in 8 steps to B, up at B
##   wait:N               N frames with no input
##   key:N                 key code N
##   text:S                type S
##
## Coordinates are in the frame's own pixel space (already scaled).
import std/[os, strutils, tables]
import engine
import ../../host/host, ../../host/tree

let wasmPath = paramStr(1)
let outPath = paramStr(2)
let w = parseFloat(paramStr(3))
let h = parseFloat(paramStr(4))
let sc = parseFloat(paramStr(5))
let script = if paramCount() >= 6: paramStr(6) else: ""

let e = start(wasmPath, w, h, sc)
let pw = int(w * sc)
let ph = int(h * sc)
var px = newSeq[uint32](pw * ph)

var clockMs = 0.0'f64   ## monotonic virtual clock, ms. See frame() for why it must advance.

proc frame() =
  # A few settle passes: the app builds its node tree on its first update, so a
  # single paint right after start() can catch an empty tree. Five is what the
  # gallery screenshots settled on; without this the frame comes out uniform.
  #
  # The clock MUST advance. engine.nim:4077 does `e.now = max(e.now, ms)`, so
  # passing a constant 16 pins e.now at 16 forever; then engine.nim:4098
  # `e.now - e.lastFrameAt >= 12` is never true again and frameEvent() fires at
  # most once. Measured consequence: the gallery's 24-step bake advanced one step,
  # corrLayer was never allocated, buildScene emitted "Y 0" as its first Draw
  # command, and the frame came out 92% pure black. Same defect made every port's
  # animation timeline flat. Feed a real, monotonic clock in milliseconds.
  for _ in 0 .. 4:
    clockMs += 16.0'f64
    e.tick(clockMs)
  e.ensureLayout()
  e.paintFrame(addr px[0], pw, ph)

proc nums(parts: openArray[string]): seq[int] =
  ## split(':') leaves "21,57" as ONE element, so the comma has to be split here
  ## too. Doing it only in the command loop is the bug: parseInt("21,57")
  ## raises and the command silently does nothing.
  for part in parts:
    for tok in part.split(','):
      let t = tok.strip()
      if t.len == 0: continue
      try: result.add parseInt(t)
      except ValueError: discard

stderr.writeLine("paramCount=" & $paramCount() & " script=[" & script & "]")
if script.len > 0:
  for cmd in script.split(';'):
    let c = cmd.strip()
    if c.len == 0: continue
    let p = c.split(':')
    let name = p[0]
    let v = nums(p[1 .. ^1])
    case name
    of "boxes":
      # Ground truth about the laid-out tree, with no app instrumentation at
      # all. Every "my click did nothing" mystery in this project has come from
      # guessing what the engine laid out; this prints it instead.
      for id in e.boxes.keys:
        let b = e.boxes[id]
        let n = e.node(id)
        stderr.writeLine("box " & $id & " kind=" & $n.kind &
          " x=" & $b.x & " y=" & $b.y & " w=" & $b.w & " h=" & $b.h)
    of "crash":
      # Only print the body when there IS one. `"".splitLines` is `@[""]`, so the
      # naive loop printed a bare `CRASH| ` on every clean run - which read as a
      # fault and sent a whole session chasing a nonexistent wasm trap.
      stderr.writeLine("crashed=[" & e.crashed & "] dirty=" & $e.dirty)
      if e.crashed.len > 0:
        for ln in e.crashed.splitLines:
          if ln.len > 0: stderr.writeLine("CRASH| " & ln)
      else:
        stderr.writeLine("crash: NONE")
    of "handlers":
      # Which events each node actually has a handler for. `canvasPointer` bails
      # when handlerFor(id, E_POINTERDOWN) < 0, and a hit test that says "canvas"
      # proves nothing about the handler, so print the registration itself.
      for id in e.boxes.keys:
        for ev in [20'i32, 21'i32, 22'i32, 1'i32]:
          let hv = e.s.handlerFor(id.int32, ev)
          if hv >= 0:
            stderr.writeLine("handler node=" & $id & " event=" & $ev & " h=" & $hv)
    of "probe":
      for yy in [0, 15, 29, 30, 31, 44]:
        e.pointerDown(34.0'f32, yy.float32)
        stderr.writeLine("y=" & $yy & " pressed=" & $e.pressed &
          " scrollY=" & $e.scrollY)
        e.pointerUp(34.0'f32, yy.float32)
    of "click":
      if v.len >= 2:
        let hx = e.hitTest(v[0].float32, v[1].float32)
        let hn = (if e.s.valid(hx): e.node(hx).kind else: -99)
        stderr.writeLine("click " & $v[0] & "," & $v[1] & " hit=" & $hx & " kind=" & $hn)
        e.pointerDown(v[0].float32, v[1].float32); e.pointerUp(v[0].float32, v[1].float32)
    of "down":
      if v.len >= 2: e.pointerDown(v[0].float32, v[1].float32)
    of "up":
      if v.len >= 2:
        stderr.writeLine("up " & $v[0] & "," & $v[1] & " hit=" & $e.hitTest(v[0].float32, v[1].float32))
        e.pointerUp(v[0].float32, v[1].float32)
    of "move":
      if v.len >= 2: e.pointerMove(v[0].float32, v[1].float32)
    of "drag":
      # Eight intermediate moves so a painting tool lays down a stroke rather
      # than a single dab: the tools interpolate between the last and current
      # point, so a two-point drag is what a real user's drag looks like.
      if v.len >= 4:
        stderr.writeLine("drag down " & $v[0] & "," & $v[1] & " hit=" & $e.hitTest(v[0].float32, v[1].float32))
        e.pointerDown(v[0].float32, v[1].float32)
        for i in 1 .. 8:
          let t = i.float / 8.0'f32
          let mx = v[0] + int((v[2] - v[0]).float32 * t)
          let my = v[1] + int((v[3] - v[1]).float32 * t)
          e.pointerMove(mx.float32, my.float32)
        e.pointerUp(v[2].float32, v[3].float32)
    of "key":
      if v.len >= 1: e.key(int32(v[0]))
    of "text":
      if p.len >= 2: e.typeText(p[1].strip(chars = {'"'}))
    of "wait":
      let n = if v.len >= 1: v[0] else: 1
      for _ in 0 ..< n: frame()
    else:
      discard
  # Let the app process the batch before the final paint: the wasm's event
  # handler runs on its own update, so firing input and painting immediately
  # catches the PREVIOUS state and every click appears to do nothing.
  frame()

frame()

# Crash state. engine.nim:4098 suppresses frameEvent() when e.crashed is non-empty,
# and paint() diverts to paintCrashed at 2331 — so an app can exit 0, write a full
# raw of the right size and still have painted nothing of its own. drive.exe exited 0
# while the gallery rendered black, so the crash string has to be visible, not inferred.
stderr.writeLine("crashed=[" & e.crashed & "] now=" & $e.now)

# What the app actually handed the renderer. tools/verify-wasm.mjs prints this, but
# that mock never runs Yoga, never runs the app's frame handlers and therefore never
# completes a multi-frame bake — it reports `layers created: 0` for every app that
# builds state over time. Only this harness has the real clock and the real engine, so
# the app's final Draw has to be readable HERE or the black-frame hunt has no ground
# truth. `Y 0` specifically means an unallocated layer: sdk/ui/paint.nim:102-106
# increments layerSeq BEFORE first use, so id 0 is the uninitialised default and
# skia_shim.cpp:1369 silently skips it.
for id in 0'i32 ..< 512'i32:
  if int(id) >= e.s.nodes.len: break
  let v = e.s.nodes[id].sProp(166'i32)
  if v.len > 0:
    stderr.writeLine("pDraw[" & $id & "] len=" & $v.len & " first=" & v[0 ..< min(160, v.len)])

# Laid-out geometry dump. The mock host in tools/verify-wasm.mjs has no Yoga pass,
# so every y_node_size there returns 0 — structure alone cannot say WHERE a node
# landed. This runs against the REAL engine after ensureLayout, so it can.
# Opt-in via the DUMP_GEOM environment variable; stderr only, the raw is untouched.
if getEnv("DUMP_GEOM").len > 0:
  stderr.writeLine("--- laid-out geometry ---")
  for id in 0'i32 ..< 512'i32:
    let (lx, ty, w, h) = e.nodeRect(id)
    if w == 0'f32 and h == 0'f32: continue
    stderr.writeLine("  [" & $id & "] w=" & $w & " h=" & $h &
                     " x=" & $lx & " y=" & $ty)

var bytes = newString(px.len * 4)
copyMem(addr bytes[0], addr px[0], bytes.len)
writeFile(outPath, bytes)
