## Native desktop integration proof for Nocturne Rally.
## Derived from the corrected render/native/sutra_shot.nim harness. No engine
## changes: all desktop, caption and child input goes through real Engine events.
import std/[algorithm, md5, os, strutils, tables]
import ../../../render/native/engine, nimskia
import ../../../host/host, ../../../host/tree
import ../../../host/sutra/[live, apps, livenet]
import ../../../host/atlas/atlas
import ../../../libs/nimpg/src/pgclient
import ../../../protocol/wire

let info = getEnv("YANTRA_DB", "host=localhost port=5433 dbname=yantra user=postgres")
var a = atlas.open(info)
serveFromAtlas(a)
let desktopPath = paramStr(1)
let outPrefix = paramStr(2)
let w = parseFloat(paramStr(3))
let h = parseFloat(paramStr(4))
let sc = if paramCount() >= 5: parseFloat(paramStr(5)) else: 1.0
var e = start(desktopPath, w, h, sc)
if e.crashed.len > 0: quit "desktop stopped: " & e.crashed, 1

proc clickTarget(e: Engine; at: int32): int32 =
  result = at
  var guard = 0
  while result >= 0 and guard < 16:
    if e.s.nodes[result].kind == 4 or e.s.handlerFor(result, E_CLICK) >= 0: return
    result = e.s.nodes[result].parent
    inc guard
  result = -1

proc tapByLabel(e: Engine; label: string): bool =
  e.ensureLayout()
  for id in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[id]
    if n.alive and 0'i32 in n.props and n.props[0'i32].s == label:
      let target = e.clickTarget(int32(id))
      if target < 0: continue
      let b = e.boxes.getOrDefault(target)
      if b.w <= 0 or b.h <= 0: continue
      echo "TAP ", repr(label), " at ", int(b.x + b.w / 2), ",", int(b.y + b.h / 2),
           " (node ", target, ", kind ", e.s.nodes[target].kind, ")"
      e.pointerDown(b.x + b.w / 2, b.y + b.h / 2)
      e.pointerUp(b.x + b.w / 2, b.y + b.h / 2)
      return true
  echo "TAP ", repr(label), ": no node says that"
  false

proc game(): (int32, Engine) =
  result = (-1'i32, nil)
  e.ensureLayout()
  for id, child in e.children:
    if child.s.nodes.len > 0 and child.s.nodes[0].sProp(P_TEXT) == "Nocturne Rally":
      result = (id, child)
      return

proc childDraw(child: Engine): string =
  for id in 0 ..< child.s.nodes.len:
    if child.s.nodes[id].alive and child.s.nodes[id].kind == 34:
      return child.s.nodes[id].sProp(P_DRAW)

proc reading(d, marker: string): string =
  let p = d.find(marker)
  if p < 0: return "absent"
  let a = d.find("Arial;", p)
  if a < 0: return "absent"
  let z = d.find(';', a + 6)
  if z < 0: return "absent"
  d[a + 6 ..< z]

var tickIndex = 0
proc advance(frames: int) =
  for _ in 1 .. frames:
    inc tickIndex
    e.tick(float64(tickIndex) * 16.0)

proc state(label: string) =
  let (_, child) = game()
  doAssert child != nil, "Nocturne child missing"
  child.ensureLayout()
  let d = child.childDraw()
  echo "STATE ", label, " tick=", tickIndex, " speed_kmh=", reading(d, "N 43.00 671.00"),
       " distance_m=", reading(d, "N 948.00 620.00"),
       " time=", reading(d, "N 1158.00 78.00"),
       " live=", d.contains("STAGE LIVE"), " draw_bytes=", d.len,
       " draw_md5=", getMD5(d)

proc shoot(label: string) =
  let (_, child) = game()
  doAssert child != nil, "Nocturne child missing before capture"
  doAssert child.crashed.len == 0, "Nocturne child crashed: " & child.crashed
  e.ensureLayout()
  let pw = int(w * sc)
  let ph = int(h * sc)
  var px = newSeq[uint32](pw * ph)
  e.paintFrame(addr px[0], pw, ph)
  let path = outPrefix & "-" & label & ".png"
  doAssert savePixels(path, addr px[0], pw, ph), "could not write " & path
  echo "NATIVE_FRAME ", path, " ", pw, "x", ph
  state(label)

# Actual desktop navigation: Home -> Explore apps -> visible y:kart LibraryCard.
doAssert e.tapByLabel("Explore apps"), "Explore apps missing"
discard e.tapByLabel("Nocturne Rally") # record the integrated label honestly
doAssert e.tapByLabel("Kart"), "Kart library card missing"
var (appId, child) = game()
doAssert child != nil, "LibraryCard did not start Nocturne Rally"

# Reveal the real caption of the game's floating window, then click the middle
# of its right-hand three controls. Icons carry paths, not literal "square" text.
let before = e.boxes[appId]
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
doAssert candidates.len >= 3, "maximize control missing beside the close icon"
echo "CAPTION candidates=", candidates.len, " boxes=", candidates
let square = candidates[^2][1]
let zb = e.boxes[square]
echo "TAP native maximize at ", int(zb.x + zb.w / 2), ",", int(zb.y + zb.h / 2),
     " (node ", square, ")"
e.pointerDown(zb.x + zb.w / 2, zb.y + zb.h / 2)
e.pointerUp(zb.x + zb.w / 2, zb.y + zb.h / 2)
advance(30) # let the desktop's maximize/caption transitions finish before pixels
e.ensureLayout()
(appId, child) = game()
let after = e.boxes[appId]
echo "WINDOW child=", appId, " before=", before.w, "x", before.h,
     " after=", after.w, "x", after.h
doAssert after.w >= before.w, "maximize did not enlarge the AppView"
shoot("grid")

# Aim through the parent at the child's native LAUNCH button. The parent routes
# pointerDown/Up to its child exactly as desktop input does.
child.ensureLayout()
var launchFound = false
var launchX = 0.0
var launchY = 0.0
for id in 0 ..< child.s.nodes.len:
  let n = child.s.nodes[id]
  if n.alive and n.kind == 4 and n.sProp(P_TEXT) == "LAUNCH":
    let lb = child.boxes[int32(id)]
    let av = e.boxes[appId]
    launchX = av.x + lb.x + lb.w / 2
    launchY = av.y + lb.y + lb.h / 2
    launchFound = true
    echo "CHILD LAUNCH local=", int(lb.x + lb.w / 2), ",", int(lb.y + lb.h / 2),
         " desktop=", int(launchX), ",", int(launchY)
    break
doAssert launchFound, "LAUNCH button not found in child"
e.pointerMove(launchX, launchY)
e.pointerDown(launchX, launchY)
e.pointerUp(launchX, launchY)
advance(1)
doAssert child.childDraw().contains("HOLD YOUR LINE"), "LAUNCH did not begin the countdown"
advance(359)
shoot("race-a")
advance(240)
shoot("race-b")
