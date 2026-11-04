## EMBERDEEP native AppView acceptance: real root Engine input only. No browser,
## no wasm-memory access, no state injection and no one-frame-as-interaction claim.
import std/[os, strutils, tables, times]
import ../../../../render/native/engine, nimskia
import ../../../../host/host, ../../../../host/tree
import ../../../../protocol/wire

let hostPath = paramStr(1)
let outPrefix = paramStr(2)
let begin = epochTime()
var root = start(hostPath, 1000, 700, 1)
doAssert root.crashed.len == 0, root.crashed
let loaded = epochTime()

proc child(): (int32, Engine) =
  root.ensureLayout()
  for id, c in root.children:
    if c.s.nodes.len > 0 and c.s.nodes[0].sProp(P_TEXT) == "EMBERDEEP":
      if c.crashed.len > 0: quit "child crashed: " & c.crashed, 1
      return (id, c)
  quit "EMBERDEEP child missing", 1

var tickIndex = 0
proc advance(frames: int) =
  for _ in 1 .. frames:
    inc tickIndex
    root.tick(float64(tickIndex) * 16.0)

proc draw(): string =
  let (_, c) = child()
  for n in c.s.nodes:
    if n.alive and n.kind == K_CANVAS: return n.sProp(P_DRAW)
  ""

proc reading(marker: string): string =
  let d = draw()
  let p = d.find(marker)
  doAssert p >= 0, "draw marker missing: " & marker
  let family = d.find("DejaVu Sans Mono;", p)
  doAssert family >= 0, "font marker missing: " & marker
  let z = d.find(';', family + 17)
  doAssert z >= 0
  d[family + 17 ..< z]

proc rootPoint(x, y: float32): (float32, float32) =
  let (id, _) = child()
  root.appViewRootPoint(id, x, y)

proc tap(x, y: float32; label: string) =
  let p = rootPoint(x, y)
  root.pointerMove(p[0], p[1])
  root.pointerDown(p[0], p[1])
  root.pointerUp(p[0], p[1])
  echo "ROOT_POINTER ", label, " child=", x, ",", y, " transformed=", p[0], ",", p[1]

proc shoot(label: string) =
  root.ensureLayout()
  let pw = int(root.width)
  let ph = int(root.height)
  var px = newSeq[uint32](pw * ph)
  root.paintFrame(addr px[0], pw, ph)
  doAssert savePixels(outPrefix & "-" & label & ".png", addr px[0], pw, ph)
  echo "NATIVE_FRAME ", outPrefix & "-" & label & ".png ", pw, "x", ph

proc positionX(): int =
  let s = reading("N 968.00 585.00")
  let p = s.find("POSITION  X ")
  doAssert p == 0, s
  let z = s.find("  Y ")
  parseInt(s[12 ..< z])

var synthVoices = 0
let (_, initialChild) = child()
for n in initialChild.s.nodes:
  if n.alive and n.kind == K_SYNTH: inc synthVoices
doAssert synthVoices == 5, "expected five native synth nodes"
shoot("cold")
echo "COLD_LOAD_MS ", (loaded - begin) * 1000, " no warm define; fixture=ticks begin after first capture"

advance(5)
tap(480, 330, "FOCUS LIVE WORLD")
advance(2)
let (focusedId, _) = child()
doAssert root.activeChild == focusedId, "native root did not focus the AppView child"
let x0 = positionX()
# Real held movement and kick edge in the same physical frame.
root.key(int32('d'), 0)
root.key(int32('f'), 0)
advance(24)
doAssert positionX() > x0, "D did not move the delver"
doAssert draw().contains("KICK  /  IMPACT 01"), "F did not kick while D was held"
root.keyUp(int32('f'))
root.keyUp(int32('d'))
doAssert not initialChild.s.keysHeld.contains(int32('d')), "D remained held after root keyUp"
advance(36)
let settledX = positionX()
advance(30)
doAssert positionX() == settledX, "movement remained latched after key release"
echo "INPUT_RELEASE move+kick passed x0=", x0, " held=", settledX, " released_position=", positionX()

# LMB casts only in the live viewport and stops on actual pointer release.
let aim = rootPoint(560, 340)
root.pointerMove(aim[0], aim[1])
root.pointerDown(aim[0], aim[1])
advance(100)
root.pointerUp(aim[0], aim[1])
doAssert draw().contains("CASTS"), "cast telemetry missing"
doAssert not draw().contains("000 CASTS"), "LMB did not cast"
shoot("played")
let castsAfterRelease = reading("N 1110.00 710.00")
advance(45)
doAssert reading("N 1110.00 710.00") == castsAfterRelease, "casting continued after pointerUp"
echo "INPUT_RELEASE pointer cast/stop passed ", castsAfterRelease

# Native button through the same transformed AppView root.
tap(1080, 788, "PAUSE")
advance(2)
doAssert draw().contains("SIMULATION HELD"), "native pause did not hold the game"
shoot("paused")
tap(1080, 788, "RESUME")
advance(2)
tap(186 + 148, 652, "WAND 02")
advance(2)
let (_, wandChild) = child()
for id in 0 ..< wandChild.s.nodes.len:
  let n = wandChild.s.nodes[id]
  if n.alive and n.kind == K_BUTTON:
    echo "WAND_NATIVE_BUTTON ", n.sProp(P_TEXT), " box=", wandChild.boxes.getOrDefault(int32(id))
echo "WAND_AFTER ", reading("N 850.00 803.00")
doAssert draw().contains("PICKAXE EQUIPPED"), "native wand button did not switch deck"

# Let the real first creature/controller kill the idle delver: no hp/position writes.
var guard = 0
while not draw().contains("EXPEDITION RECORD / FINAL") and guard < 2400:
  advance(60)
  guard += 60
doAssert draw().contains("EXPEDITION RECORD / FINAL"), "natural run did not end within " & $guard & " host frames"
shoot("death")
echo "NATURAL_DEATH host_frames=", guard

# Restart is a real native button at transformed desktop coordinates.
tap(472, 426, "DESCEND AGAIN")
advance(5)
doAssert not draw().contains("EXPEDITION RECORD / FINAL"), "restart did not create a new run"
doAssert draw().contains("SEED 20261030"), "restart did not advance the seed"
doAssert positionX() == 192, "restart did not return to the original spawn"
shoot("restart")
echo "NATIVE_EMBERDEEP_PASS move/kick/release/LMB/pause/wand/natural-death/transformed-restart; ticks=", tickIndex

# The same plain artifact at its real 1280x816 size, with ZERO AppView offset.
# These are user-visible captures after explicit native input, never warm defines
# or an autonomous attract mode. The transformed proof above remains separate.
if paramCount() >= 3:
  root = start(paramStr(3), 1280, 816, 1)
  doAssert root.crashed.len == 0, root.crashed
  tickIndex = 0
  shoot("direct-cold")
  advance(5)
  root.pointerMove(480, 330)
  root.pointerDown(480, 330)
  root.pointerUp(480, 330)
  advance(2)
  root.key(int32('d'), 0)
  root.key(int32('f'), 0)
  advance(24)
  root.keyUp(int32('f'))
  root.keyUp(int32('d'))
  advance(36)
  root.pointerMove(560, 340)
  root.pointerDown(560, 340)
  advance(100)
  root.pointerUp(560, 340)
  advance(2)
  var directDraw = ""
  for n in root.s.nodes:
    if n.alive and n.kind == K_CANVAS: directDraw = n.sProp(P_DRAW)
  doAssert directDraw.contains("CASTS") and not directDraw.contains("000 CASTS"),
          "direct 1280 LMB did not cast"
  shoot("direct-played")
  echo "NATIVE_DIRECT_DISPLAY_PASS actual zero-offset 1280x816 cold and key/pointer play; host_frames=", tickIndex
