## Ocean native-desktop proof: a real SDL window presenting the actual desktop,
## with Ocean running as a nested AppView. No direct child button dispatch, no
## substitute scene, and no renderer changes. Build from the combined bootstrap
## described in the task; pass the lead desktop wasm and an output prefix.
import std/[algorithm, md5, os, osproc, strutils, tables, times]
import nimsdl3, nimskia
import ../../../render/native/engine
import ../../../host/host, ../../../host/tree
import ../../../host/sutra/[live, apps]
import ../../../host/atlas/atlas
import ../../../libs/nimpg/src/pgclient
import ../../../protocol/wire

let desktopPath = paramStr(1)
let outPrefix = paramStr(2)
let W = 1620  # Aura chrome leaves a 1280+ wide AppView; 1600 would clip four pixels.
let H = 1000
let atlasAddress = getEnv("OCEAN_CHILD_ADDRESS", "y:@tide-ocean/ocean.Ocean")
let info = getEnv("YANTRA_DB", "host=localhost port=5436 dbname=yantra user=postgres")
var db = atlas.open(info)
serveFromAtlas(db)
let registry = childApps(db, "1")
registry.registerChild("y:ocean", atlasAddress)
childAppHook = proc (parent: App; source, path: string; child: App) =
  registry.attachChild(parent, source, path, child)

doAssert nimsdl3.init(), "SDL init failed: " & lastError()
var e = start(desktopPath, float32(W), float32(H), 1)
if e.crashed.len > 0: quit "desktop stopped: " & e.crashed, 1
var win = openWindow("Ocean — native AppView proof", W, H)
if win.isNil: quit "native window failed: " & lastError(), 1
win.show()
var pixels = newSeq[uint32](W * H)
var tickIndex = 0
var tickMs = 0.0
var layoutMs = 0.0
var paintMs = 0.0
var presentMs = 0.0

proc pumpEvents() =
  ## Put real SDL events through the same parent event path as the desktop runner.
  var ev: InputEvent
  while win.wait(ev, 0):
    case ev.kindOf
    of evQuit: quit "native window was closed", 2
    of evExpose: e.dirty = true
    of evDown:
      if ev.button == 1: e.pointerDown(ev.x, ev.y)
    of evUp:
      if ev.button == 1: e.pointerUp(ev.x, ev.y)
    of evMove: e.pointerMove(ev.x, ev.y)
    of evResize: e.resize(float32(ev.w), float32(ev.h))
    else: discard

proc presentOne(measure = false) =
  let t0 = epochTime()
  inc tickIndex
  e.tick(float64(ticksMs()))
  let t1 = epochTime()
  e.ensureLayout()
  let t2 = epochTime()
  e.paintFrame(addr pixels[0], W, H)
  let t3 = epochTime()
  doAssert win.present(addr pixels[0], W, H, W * 4), "SDL present failed: " & lastError()
  let t4 = epochTime()
  if measure:
    tickMs += (t1 - t0) * 1000
    layoutMs += (t2 - t1) * 1000
    paintMs += (t3 - t2) * 1000
    presentMs += (t4 - t3) * 1000
  pumpEvents()

proc advance(frames: int) =
  for _ in 1 .. frames: presentOne()

proc shoot(label: string) =
  e.ensureLayout()
  e.paintFrame(addr pixels[0], W, H)
  doAssert win.present(addr pixels[0], W, H, W * 4), "SDL present failed: " & lastError()
  let path = outPrefix & "-" & label & ".png"
  doAssert savePixels(path, addr pixels[0], W, H), "could not save " & path
  echo "PRESENTED_NATIVE_WINDOW ", path, " ", W, "x", H
  pumpEvents()

proc clickTarget(root: Engine; at: int32): int32 =
  result = at
  var guard = 0
  while result >= 0 and guard < 16:
    if root.s.nodes[result].kind == 4 or root.s.handlerFor(result, E_CLICK) >= 0: return
    result = root.s.nodes[result].parent
    inc guard
  result = -1

proc rootPointer(x, y: float32) =
  e.pointerMove(x, y)
  e.pointerDown(x, y)
  e.pointerUp(x, y)
  pumpEvents()

proc rootTap(label: string) =
  e.ensureLayout()
  var found = false
  for id in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[id]
    if n.alive and 0'i32 in n.props and n.props[0'i32].s == label:
      let target = e.clickTarget(int32(id))
      if target < 0: continue
      let b = e.boxes.getOrDefault(target)
      if b.w <= 0 or b.h <= 0: continue
      echo "ROOT_TAP ", repr(label), " desktop=(", b.x + b.w / 2, ",", b.y + b.h / 2, ")"
      rootPointer(b.x + b.w / 2, b.y + b.h / 2)
      found = true
      break
  doAssert found, "desktop label missing: " & label

proc oceanChild(): (int32, Engine) =
  result = (-1'i32, nil)
  e.ensureLayout()
  for id, child in e.children:
    if child.s != nil and child.s.nodes.len > 0 and child.s.nodes[0].sProp(P_TEXT) == "Ocean":
      if child.crashed.len > 0: quit "Ocean child failed: " & child.crashed, 1
      return (id, child)

proc childTap(label: string) =
  ## Parent-root coordinates only: this is not a direct event call on the child.
  let (appId, child) = oceanChild()
  doAssert child != nil, "Ocean child missing before " & label
  child.ensureLayout()
  let av = e.boxes[appId]
  var found = false
  for id in 0 ..< child.s.nodes.len:
    let n = child.s.nodes[id]
    if n.alive and n.kind == 4 and n.sProp(P_TEXT) == label:
      let b = child.boxes[int32(id)]
      let x = av.x + b.x + b.w / 2
      let y = av.y + b.y + b.h / 2
      echo "PARENT_ROUTED_TAP ", repr(label), " child_local=(", b.x + b.w / 2, ",",
           b.y + b.h / 2, ") desktop=(", x, ",", y, ") appview=", appId
      doAssert x >= av.x and x <= av.x + av.w and y >= av.y and y <= av.y + av.h,
             label & " is clipped by the AppView"
      rootPointer(x, y)
      found = true
      break
  doAssert found, "Ocean button missing: " & label
  presentOne()
  doAssert e.activeChild == appId, "parent did not route focus to Ocean after " & label

proc texts(child: Engine; marker: string): bool =
  for n in child.s.nodes:
    if n.alive and n.kind in [K_TEXT, K_BUTTON] and n.sProp(P_TEXT) == marker: return true

proc meshState(child: Engine) =
  doAssert 1'i32 in child.s.bufs, "Ocean geometry buffer 1 disappeared"
  let data = child.s.bufs[1]
  var nv, ni: uint32
  copyMem(addr nv, unsafeAddr data[0], 4)
  copyMem(addr ni, unsafeAddr data[4], 4)
  echo "CHILD_MESH bytes=", data.len, " vertices=", nv, " indices=", ni, " triangles=", ni div 3
  doAssert nv == 21696 and ni == 129024, "Ocean is not the required rebuilt mesh"
  for n in child.s.nodes:
    if n.alive and n.kind == K_MESH and n.iProp(P_GEOMETRY) == 1:
      echo "SEA_UNIFORMS ", n.sProp(P_UNIFORMS)
      return
  quit "Ocean sea mesh is absent", 1

proc regionHash(): string =
  ## MD5 of the real child rectangle from the frame already presented by SDL.
  let (appId, _) = oceanChild()
  let b = e.boxes[appId]
  let x0 = max(0, int(b.x))
  let y0 = max(0, int(b.y))
  let x1 = min(W, int(b.x + b.w))
  let y1 = min(H, int(b.y + b.h))
  doAssert x1 > x0 and y1 > y0, "Ocean has no visible presented rectangle"
  let bytesPerRow = (x1 - x0) * 4
  var crop = newString(bytesPerRow * (y1 - y0))
  for y in y0 ..< y1:
    copyMem(addr crop[(y - y0) * bytesPerRow], addr pixels[y * W + x0], bytesPerRow)
  getMD5(crop)

# Navigate the actual desktop into its Library and open y:ocean. The integrated
# root catalogue still exposes its older label; the child itself is titled Ocean.
rootTap("Explore apps")
advance(2)
rootTap("The Sea at Dusk")
var (appId, child) = oceanChild()
doAssert child != nil, "desktop did not create the Ocean AppView"
let before = e.boxes[appId]
echo "APPVIEW_FLOATING x=", before.x, " y=", before.y, " w=", before.w, " h=", before.h

# Reveal the native floating caption and use its square control, as the other
# desktop proofs do; all coordinates go through the parent window.
e.pointerMove(before.x + before.w / 2, before.y + 2)
e.pointerDown(before.x + before.w / 2, before.y + 2)
e.pointerUp(before.x + before.w / 2, before.y + 2)
e.ensureLayout()
var candidates: seq[(float32, int32)] = @[]
for id in 0 ..< e.s.nodes.len:
  if e.s.handlerFor(int32(id), E_CLICK) < 0: continue
  let b = e.boxes.getOrDefault(int32(id))
  if b.x + b.w / 2 < before.x or b.x + b.w / 2 > before.x + before.w: continue
  if b.y < before.y - 50 or b.y > before.y + 40: continue
  if b.w < 43 or b.w > 45 or b.h < 20 or b.h > 48: continue
  candidates.add((b.x, int32(id)))
candidates.sort(proc (a, b: (float32, int32)): int = cmp(a[0], b[0]))
doAssert candidates.len >= 3, "native maximize control not found"
let square = candidates[^2][1]
let zb = e.boxes[square]
rootPointer(zb.x + zb.w / 2, zb.y + zb.h / 2)
advance(45)
(appId, child) = oceanChild()
let after = e.boxes[appId]
echo "APPVIEW_NATIVE x=", after.x, " y=", after.y, " w=", after.w, " h=", after.h,
     " child_engine=", int(child.width), "x", int(child.height)
doAssert after.w >= 1280 and after.h >= 816, "maximized child clips Ocean's native geometry"

# First native child paint: Filament/Vulkan creation and shader compilation are
# reported separately, never blended into the steady-state numbers below.
meshState(child)
let warm0 = epochTime()
e.ensureLayout()
let warmLayout = epochTime()
e.paintFrame(addr pixels[0], W, H)
let warmPaint = epochTime()
doAssert win.present(addr pixels[0], W, H, W * 4), "initial SDL present failed"
let warmPresent = epochTime()
echo "WARMUP layout_ms=", (warmLayout - warm0) * 1000,
     " paint_plus_3d_readback_ms=", (warmPaint - warmLayout) * 1000,
     " present_ms=", (warmPresent - warmPaint) * 1000,
     " total_ms=", (warmPresent - warm0) * 1000
doAssert savePixels(outPrefix & "-window.png", addr pixels[0], W, H)
echo "PRESENTED_NATIVE_WINDOW ", outPrefix & "-window.png ", W, "x", H

childTap("STORM")
doAssert texts(child, "50 kn"), "STORM did not update real child state"
childTap("BLUE")
advance(180)
meshState(child)
echo "TRANSITION_STATE wind50=", texts(child, "50 kn"),
     " blue=", child.texts("BLUE  /  SUN -2.4°")
doAssert texts(child, "BLUE  /  SUN -2.4°"), "BLUE transition did not settle to -2.4 degrees"
shoot("storm-blue")
let motionA = regionHash()

tickMs = 0
layoutMs = 0
paintMs = 0
presentMs = 0
let timedStart = epochTime()
for _ in 1 .. 16: presentOne(measure = true)
let timedTotal = epochTime() - timedStart
shoot("storm-blue-next")
let motionB = regionHash()
echo "ANIMATION child_region_md5_first=", motionA, " later=", motionB, " changed=", motionA != motionB
doAssert motionA != motionB, "nested ocean shader pixels did not animate"
echo "TIMED_NATIVE_FRAMES count=16 resolution=", W, "x", H,
     " tick_total_ms=", tickMs, " tick_mean_ms=", tickMs / 16,
     " layout_total_ms=", layoutMs, " layout_mean_ms=", layoutMs / 16,
     " paint_plus_3d_readback_total_ms=", paintMs, " paint_mean_ms=", paintMs / 16,
     " present_total_ms=", presentMs, " present_mean_ms=", presentMs / 16,
     " wall_total_ms=", timedTotal * 1000, " wall_mean_ms=", timedTotal * 1000 / 16,
     " fps=", 16 / timedTotal

# An optional independent X11 screenshot of the real SDL window, while it is
# still shown. The PNGs above are bytes already presented to that same window.
let ffmpeg = getEnv("OCEAN_X11_CAPTURE")
if ffmpeg.len > 0 and getEnv("DISPLAY").len > 0:
  var display = getEnv("DISPLAY")
  if not display.contains('.'): display.add ".0"
  let screenPath = outPrefix & "-x11.png"
  let cmd = quoteShell(ffmpeg) & " -loglevel error -y -f x11grab -video_size " & $W & "x" & $H &
            " -i " & quoteShell(display) & " -frames:v 1 " & quoteShell(screenPath)
  let (output, code) = execCmdEx(cmd)
  echo "X11_CAPTURE exit=", code, " path=", screenPath, " output=", output

win.close()
shutdown()
echo "NATIVE_OCEAN_PASS actual SDL desktop Window, nested AppView geometry, parent input, state, animation"
