## Native desktop integration proof for the 1774 Orrery.
## Uses the actual desktop module and its y:orrery AppView. Every interaction is
## sent to the parent Engine at real viewport coordinates; no child event is
## invoked directly. Drawing text is read from the child's retained Canvas state.
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

proc orrery(): (int32, Engine) =
  result = (-1'i32, nil)
  e.ensureLayout()
  for id, child in e.children:
    if child.s.nodes.len > 0 and child.s.nodes[0].sProp(P_TEXT) == "THE CLOCKMAKER'S ORRERY":
      result = (id, child)
      return

proc childDraw(child: Engine): string =
  for id in 0 ..< child.s.nodes.len:
    if child.s.nodes[id].alive and child.s.nodes[id].kind == 34:
      return child.s.nodes[id].sProp(P_DRAW)

proc clockDays(child: Engine): float64 =
  child.ensureLayout()
  let d = child.childDraw()
  let marker = "CLOCK +"
  let start = d.find(marker)
  doAssert start >= 0, "child clock readout absent from real Canvas"
  let tail = start + marker.len
  let finish = d.find(" DAYS", tail)
  doAssert finish > tail, "child clock value is incomplete"
  parseFloat(d[tail ..< finish])

var tickIndex = 0
proc advance(frames: int) =
  for _ in 1 .. frames:
    inc tickIndex
    e.tick(float64(tickIndex) * 16.0)

proc state(label: string) =
  let (appId, child) = orrery()
  doAssert child != nil, "Orrery child missing"
  child.ensureLayout()
  let box = e.boxes[appId]
  let day = clockDays(child)
  let d = child.childDraw()
  echo "STATE ", label, " tick=", tickIndex, " clock_days=", day,
       " appview=(x=", box.x, ",y=", box.y, ",w=", box.w, ",h=", box.h, ")",
       " earth=", d.contains("365.256 d"), " saturn=", d.contains("10755.884 d"),
       " draw_bytes=", d.len, " draw_md5=", getMD5(d), " child_crash=", repr(child.crashed)

proc shoot(label: string) =
  let (_, child) = orrery()
  doAssert child != nil, "Orrery child missing before capture"
  doAssert child.crashed.len == 0, "Orrery child crashed: " & child.crashed
  e.ensureLayout()
  let pw = int(w * sc)
  let ph = int(h * sc)
  var px = newSeq[uint32](pw * ph)
  e.paintFrame(addr px[0], pw, ph)
  let path = outPrefix & "-" & label & ".png"
  doAssert savePixels(path, addr px[0], pw, ph), "could not write " & path
  echo "NATIVE_FRAME ", path, " ", pw, "x", ph
  state(label)

proc childTap(label: string) =
  ## Convert the child's real button centre through the current AppView rectangle,
  ## then route a complete pointer sequence through the desktop parent.
  let (appId, child) = orrery()
  doAssert child != nil, "Orrery child missing before " & label
  child.ensureLayout()
  let av = e.boxes[appId]
  var found = false
  var gx = 0.0'f32
  var gy = 0.0'f32
  for id in 0 ..< child.s.nodes.len:
    let n = child.s.nodes[id]
    if n.alive and n.kind == 4 and n.sProp(P_TEXT) == label:
      let b = child.boxes[int32(id)]
      gx = av.x + b.x + b.w / 2
      gy = av.y + b.y + b.h / 2
      found = true
      echo "CHILD_TAP ", repr(label), " local=(", int(b.x + b.w / 2), ",", int(b.y + b.h / 2), ")",
           " desktop=(", int(gx), ",", int(gy), ") appview=", appId
      break
  doAssert found, "Child button absent: " & label
  doAssert gx >= av.x and gx <= av.x + av.w and gy >= av.y and gy <= av.y + av.h,
       "Child button centre is clipped by AppView: " & label
  e.pointerMove(gx, gy)
  e.pointerDown(gx, gy)
  e.pointerUp(gx, gy)
  advance(1)
  doAssert e.activeChild == appId, "Parent did not focus/rout input to Orrery for " & label

# Actual desktop navigation: Home -> Explore apps -> visible y:orrery LibraryCard.
doAssert e.tapByLabel("Explore apps"), "Explore apps missing"
doAssert e.tapByLabel("Orrery"), "Orrery library card missing"
var (appId, child) = orrery()
doAssert child != nil, "LibraryCard did not start THE CLOCKMAKER'S ORRERY"
doAssert child.crashed.len == 0, "Orrery child failed: " & child.crashed
doAssert child.childDraw().contains("01 JANUARY"), "Loaded Orrery has no initial civil date"
let before = e.boxes[appId]
echo "WINDOW before maximize child=", appId, " x=", before.x, " y=", before.y,
     " w=", before.w, " h=", before.h
advance(30) # finish the desktop's genuine opening transition before judging pixels
shoot("floating")

# Reveal the actual floating-window caption and use its square maximize control.
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
advance(30)
e.ensureLayout()
(appId, child) = orrery()
let after = e.boxes[appId]
echo "WINDOW after maximize child=", appId, " x=", after.x, " y=", after.y,
     " w=", after.w, " h=", after.h
doAssert after.w >= before.w, "maximize did not enlarge the AppView"
doAssert child.childDraw().contains("01 JANUARY"), "Maximize lost the Orrery's real draw state"
shoot("grid")

# Advancing the parent must also advance the real child canvas and planetary model.
let startDay = clockDays(child)
let startDraw = getMD5(child.childDraw())
advance(90)
doAssert clockDays(child) > startDay + 1.0, "Parent clock did not advance child time"
doAssert getMD5(child.childDraw()) != startDraw, "Child drawing did not change under time"
shoot("running")

# Selection is a real parent-routed tap at Saturn's button, which changes its
# computed cartouche. +7 DAYS then HALT must leave both clock and drawing frozen.
childTap("SATURN")
doAssert child.childDraw().contains("10755.884 d"), "Saturn cartouche did not update after parent tap"
let beforeStep = clockDays(child)
childTap("+ 7 DAYS")
doAssert abs(clockDays(child) - beforeStep - 7.0) < 0.001, "+7 DAYS did not step exactly seven through parent"
childTap("HALT")
let frozenDay = clockDays(child)
let frozenDraw = getMD5(child.childDraw())
advance(120)
doAssert abs(clockDays(child) - frozenDay) < 0.001, "HALT did not freeze the clock"
doAssert getMD5(child.childDraw()) == frozenDraw, "HALT did not freeze the entire child drawing"
shoot("saturn-halt")

# Epoch restores the initial calendar and Earth selection while remaining halted.
childTap("1774 EPOCH")
doAssert abs(clockDays(child)) < 0.001, "1774 EPOCH did not reset the child Julian day"
doAssert child.childDraw().contains("365.256 d"), "1774 EPOCH did not restore Earth"
doAssert child.childDraw().contains("01 JANUARY"), "1774 EPOCH did not restore the civil date"
shoot("epoch")

# Resume on the year detent, again through parent routing; both time and pixels move.
childTap("1 YEAR / S")
let resumeDay = clockDays(child)
advance(90)
doAssert clockDays(child) - resumeDay > 400.0, "YEAR/S did not resume multi-month motion"
doAssert child.childDraw().contains("ONE YEAR PER SECOND"), "Year detent absent after resume"
shoot("resume")
echo "NATIVE_PROOF PASS actual desktop y:orrery parent-pointer motion selection HALT epoch resume"
