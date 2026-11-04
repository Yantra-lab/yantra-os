## Nocturne native-input acceptance driver. There is no SDL window and no browser:
## real native Engine parent key/pointer methods drive the real desktop child.
## Observation is read-only UI/draw state; no wasm linear memory is read or written.
import std/[algorithm, md5, os, strutils, tables]
import ../../../render/native/engine, nimskia
import ../../../host/host, ../../../host/tree
import ../../../host/sutra/[live, apps, livenet]
import ../../../host/atlas/atlas
import ../../../libs/nimpg/src/pgclient
import ../../../protocol/wire

const
  KeyUp = 0x40000052'i32
  KeyDown = 0x40000051'i32
  KeyLeft = 0x40000050'i32
  KeyRight = 0x4000004f'i32
  KeySpace = 32'i32

var a = atlas.open(getEnv("YANTRA_DB", "host=localhost port=5433 dbname=yantra user=postgres"))
serveFromAtlas(a)
let desktopPath = paramStr(1)
let outPrefix = paramStr(2)
let mode = paramStr(3)
let w = 1920.0
let h = 1080.0
var e = start(desktopPath, w, h, 1)
if e.crashed.len > 0: quit "desktop stopped: " & e.crashed, 1
var tickIndex = 0
var appId = -1'i32

proc advance(frames: int) =
  for _ in 1 .. frames:
    inc tickIndex
    e.tick(float64(tickIndex) * 16.0)

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
      e.pointerDown(b.x + b.w / 2, b.y + b.h / 2)
      e.pointerUp(b.x + b.w / 2, b.y + b.h / 2)
      echo "PARENT_TAP ", repr(label), " native_node=", target
      return true
  false

proc game(): Engine =
  e.ensureLayout()
  for id, child in e.children:
    if child.s.nodes.len > 0 and child.s.nodes[0].sProp(P_TEXT) == "Nocturne Rally":
      appId = id
      return child
  quit "Nocturne child missing", 1

proc childDraw(): string =
  let child = game()
  for id in 0 ..< child.s.nodes.len:
    if child.s.nodes[id].alive and child.s.nodes[id].kind == 34:
      return child.s.nodes[id].sProp(P_DRAW)
  ""

proc reading(d, marker: string): string =
  let p = d.find(marker)
  if p < 0: return "absent"
  let a = d.find("Arial;", p)
  if a < 0: return "absent"
  let z = d.find(';', a + 6)
  if z < 0: return "absent"
  d[a + 6 ..< z]

proc lean(d: string): string =
  let p = d.find("o ")
  if p < 0: return "absent"
  let z = d.find(';', p)
  if z < 0: return "absent"
  d[p + 2 ..< z]

proc speedValue(): int =
  parseInt(reading(childDraw(), "N 43.00 671.00"))

proc leanValue(): float =
  parseFloat(lean(childDraw()))

proc launcherCount(): int =
  for n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == "launcher": inc result

proc state(label: string) =
  let d = childDraw()
  echo "STATE ", label, " tick=", tickIndex,
       " speed_kmh=", reading(d, "N 43.00 671.00"),
       " speedbar_distance_m=", reading(d, "N 948.00 620.00"),
       " time=", reading(d, "N 1158.00 78.00"),
       " lap=", reading(d, "N 995.00 91.00"),
       " body_lean_deg=", lean(d),
       " turbo=", d.contains("MINI-TURBO  /"),
       " throttle_open=", d.contains("THROTTLE OPEN"),
       " live=", d.contains("STAGE LIVE"), " draw_md5=", getMD5(d)

proc shoot(label: string) =
  let child = game()
  doAssert e.crashed.len == 0, "desktop crashed: " & e.crashed
  doAssert child.crashed.len == 0, "Nocturne crashed: " & child.crashed
  echo "NATIVE_CRASH parent=", repr(e.crashed), " child=", repr(child.crashed)
  e.ensureLayout()
  var px = newSeq[uint32](int(w) * int(h))
  e.paintFrame(addr px[0], int(w), int(h))
  let path = outPrefix & "-" & label & ".png"
  doAssert savePixels(path, addr px[0], int(w), int(h)), "could not write " & path
  echo "NATIVE_FRAME ", path, " 1920x1080"
  state(label)

proc keyDownPhysical(code: int32; name: string; mods = 0'i32) =
  e.key(code, mods)
  let child = game()
  echo "NATIVE_KEY_DOWN ", name, " parent=e.key; mods=", mods, " active_child=e.activeChild; ",
       "child.keysHeld.contains=", child.s.keysHeld.contains(code), " active_child_ok=", e.activeChild == appId
  doAssert child.s.keysHeld.contains(code), name & " keyDown did not reach the native child"

proc keyUpPhysical(code: int32; name: string) =
  e.keyUp(code)
  let child = game()
  let propagated = not child.s.keysHeld.contains(code)
  echo "NATIVE_KEY_UP ", name, " parent=e.keyUp; recursive_child_release=true; ",
       "child_release_delivered=", propagated, " parent_release_delivered=", not e.s.keysHeld.contains(code),
       " active_child_ok=", e.activeChild == appId
  doAssert not e.s.keysHeld.contains(code), name & " remains held in parent after real parent keyUp"
  doAssert propagated, name & " remains held in child after real parent keyUp"

proc pointer(label: string) =
  let child = game()
  child.ensureLayout()
  for id in 0 ..< child.s.nodes.len:
    let n = child.s.nodes[id]
    if n.alive and n.kind == 4 and n.sProp(P_TEXT) == label:
      let lb = child.boxes[int32(id)]
      let av = e.boxes[appId]
      let x = av.x + lb.x + lb.w / 2
      let y = av.y + lb.y + lb.h / 2
      e.pointerMove(x, y)
      e.pointerDown(x, y)
      e.pointerUp(x, y)
      echo "NATIVE_POINTER ", label, " child_local=", int(lb.x + lb.w / 2), ",", int(lb.y + lb.h / 2),
           " desktop=", int(x), ",", int(y), " routed_app=", appId
      return
  quit "child pointer target missing: " & label, 1

# Real desktop -> Library -> Nocturne -> maximize. No direct AppView creation.
doAssert e.tapByLabel("Explore apps"), "Explore apps missing"
if not e.tapByLabel("Nocturne Rally"):
  doAssert e.tapByLabel("Kart"), "Nocturne/Kart library card missing"
discard game()
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
doAssert candidates.len >= 3, "native maximize controls missing"
let zb = e.boxes[candidates[^2][1]]
e.pointerDown(zb.x + zb.w / 2, zb.y + zb.h / 2)
e.pointerUp(zb.x + zb.w / 2, zb.y + zb.h / 2)
advance(30)
discard game()
echo "WINDOW before=", before.w, "x", before.h, " after=", e.boxes[appId].w, "x", e.boxes[appId].h

pointer("LAUNCH")
advance(1)
doAssert childDraw().contains("HOLD YOUR LINE"), "native LAUNCH did not enter countdown"

case mode
of "throttle":
  pointer("GAS") # cancel launch's default armed throttle: ArrowUp alone drives below
  advance(184)
  state("throttle-before")
  keyDownPhysical(KeyUp, "ArrowUp")
  advance(180)
  state("throttle-held")
  let heldSpeed = speedValue()
  keyUpPhysical(KeyUp, "ArrowUp")
  advance(45)
  shoot("throttle-after-parent-keyup")
  doAssert not childDraw().contains("THROTTLE OPEN"), "throttle remained open after ArrowUp release"
  doAssert speedValue() < heldSpeed, "kart accelerated after ArrowUp release"
of "brake":
  advance(359)
  state("brake-before")
  keyDownPhysical(KeyDown, "ArrowDown")
  advance(45)
  shoot("brake-held")
  let brakingSpeed = speedValue()
  keyUpPhysical(KeyDown, "ArrowDown")
  advance(30)
  shoot("brake-after-parent-keyup")
  doAssert speedValue() > brakingSpeed, "braking remained stuck after ArrowDown release"
of "left", "right":
  advance(359)
  state(mode & "-before")
  let code = if mode == "left": KeyLeft else: KeyRight
  let name = "Arrow" & mode.capitalizeAscii()
  keyDownPhysical(code, name)
  advance(22)
  shoot(mode & "-held")
  let heldLean = abs(leanValue())
  keyUpPhysical(code, name)
  advance(12)
  shoot(mode & "-after-parent-keyup")
  doAssert abs(leanValue()) < heldLean, name & " steering lean remained stuck after release"
of "space":
  advance(359)
  keyDownPhysical(KeyUp, "ArrowUp")
  keyDownPhysical(KeyLeft, "ArrowLeft")
  keyDownPhysical(KeySpace, "Space")
  advance(145)
  shoot("space-held")
  let heldLean = abs(leanValue())
  keyUpPhysical(KeySpace, "Space")
  keyUpPhysical(KeyLeft, "ArrowLeft")
  keyUpPhysical(KeyUp, "ArrowUp")
  advance(45)
  shoot("space-release-turbo")
  doAssert childDraw().contains("MINI-TURBO  /  3"), "Space release did not fire the charged level-3 turbo"
  advance(50)
  shoot("space-after-parent-keyup")
  doAssert not childDraw().contains("MINI-TURBO"), "level-3 turbo did not expire on the real game clock"
  doAssert not childDraw().contains("DRIFT CHARGING"), "drift charging remained stuck after Space release"
  doAssert abs(leanValue()) < heldLean, "steering lean remained stuck after drift release"
of "stop":
  advance(359)
  keyDownPhysical(KeyDown, "ArrowDown (full stop)")
  advance(120)
  shoot("stop-held")
  doAssert speedValue() == 0, "held brake did not bring the kart to a full stop"
  keyUpPhysical(KeyDown, "ArrowDown (full stop)")
  advance(30)
  shoot("stop-after-parent-keyup")
  doAssert speedValue() > 0, "kart remained braking after release from a full stop"
of "lifecycle":
  advance(359)
  keyDownPhysical(KeyLeft, "Shift+ArrowLeft", 0x0001)
  advance(22)
  keyUpPhysical(KeyLeft, "Shift+ArrowLeft")
  doAssert launcherCount() == 0, "desktop launcher was unexpectedly open"
  keyDownPhysical(KeySpace, "Super+Space (focused child)", 0x0400)
  advance(1)
  doAssert launcherCount() == 0, "focused child leaked Super+Space into the desktop"
  keyUpPhysical(KeySpace, "Super+Space (focused child)")
  keyDownPhysical(KeyUp, "ArrowUp before focus loss")
  e.pointerDown(0, 0)
  e.pointerUp(0, 0)
  doAssert e.activeChild != appId, "native desktop pointer did not take focus from the child"
  keyUpPhysical(KeyUp, "ArrowUp after focus loss")
  e.key(KeySpace, 0x0400)
  advance(1)
  doAssert launcherCount() == 1, "Super+Space did not open the desktop launcher"
  doAssert not game().s.keysHeld.contains(KeySpace), "desktop Super+Space leaked into the unfocused child"
  e.keyUp(KeySpace)
  e.key(27, 0)
  advance(1)
  doAssert launcherCount() == 0, "Escape did not close the desktop launcher"
  e.keyUp(27)
  shoot("lifecycle-desktop")
  e.key(int32('w'), 0x0400)
  advance(1)
  e.ensureLayout() # child disposal is part of layout sync after the native key event
  echo "NATIVE_DESKTOP_CLOSE app=", appId, " still_present=", appId in e.children, " parent_crashed=", repr(e.crashed)
  doAssert appId notin e.children, "Super+W did not close the focused desktop child"
  e.keyUp(int32('w'))
  doAssert e.crashed.len == 0, "desktop crashed after child close/release: " & e.crashed
  echo "NATIVE_DESKTOP_SHORTCUTS Super+Space=opened Escape=closed Super+W=child_closed release_after_close=safe"
of "pointers":
  advance(359)
  state("pointer-before")
  pointer("GAS")
  advance(30)
  state("pointer-gas-off")
  pointer("BRAKE")
  advance(12)
  state("pointer-brake-pulse")
  pointer("◀")
  advance(25)
  state("pointer-left-nudge")
  pointer("▶")
  advance(60)
  state("pointer-right-nudge")
  pointer("GAS")
  advance(120)
  keyDownPhysical(KeyLeft, "ArrowLeft (pointer-drift steering)")
  pointer("DRIFT")
  advance(150)
  pointer("DRIFT")
  advance(1)
  doAssert childDraw().contains("MINI-TURBO  /"), "pointer DRIFT release did not create turbo"
  shoot("pointer-turbo")
  advance(95)
  doAssert not childDraw().contains("MINI-TURBO  /"), "pointer mini-turbo did not expire"
  state("pointer-turbo-expired")
  pointer("LAUNCH")
  advance(1)
  doAssert childDraw().contains("HOLD YOUR LINE"), "pointer restart did not enter countdown"
  shoot("pointer-restart")
of "lap":
  pointer("GAS")
  advance(184)
  keyDownPhysical(KeyUp, "ArrowUp")
  advance(2100)
  shoot("lap-two")
else:
  quit "unknown mode " & mode & "; expected throttle/brake/left/right/space/stop/lifecycle/pointers/lap", 2
echo "NATIVE_INPUT_COMPLETE ", mode, " (all emitted native release and mode assertions passed)"
