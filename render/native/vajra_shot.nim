## A Vajra app, straight out of Postgres, drawn by the real engine (Yoga
## layout, Skia paint) as one person after tapping buttons by label, to a raw
## BGRA frame, or a PNG when `out` ends in .png:
##   vajra_shot y:@space/cell.Name out.raw|out.png width height scale user ["Label" ...]
## Taps are real pointer input through the engine's layout.
import std/[os, strutils, tables]
import engine, nimskia
import ../../host/host, ../../host/tree
import ../../host/vajra/[live, apps, livenet]
import ../../host/atlas/atlas
import ../../libs/nimpg/src/pgclient

let info = getEnv("YANTRA_DB", "host=localhost port=5433 dbname=yantra user=postgres")
var a = atlas.open(info)
serveFromAtlas(a)                                # y: addresses come from Postgres
if paramStr(1).startsWith("y:"):
  discard openLive(a, paramStr(1), paramStr(6))  # queries run as this person
  serveNet(a, paramStr(1))                       # `fetch` by the app's own `uses`
elif getEnv("VAJRA_APP").len > 0:              # a Vajra build run from a file, with that app's data
  discard openLive(a, getEnv("VAJRA_APP"), paramStr(6))
# (otherwise a plain .wasm path runs as before: the original, for comparisons)
let w = parseFloat(paramStr(3))
let h = parseFloat(paramStr(4))
let sc = parseFloat(paramStr(5))
var tap = ""
if getEnv("VAJRA_SHOT_LAYERS").len > 0:
  layerDrawTap = proc (id: int32; cmds: string) =
    tap.add "## layer " & $id & "\n" & cmds.replace(";", ";\n") & "\n"
let e = start(paramStr(1), w, h, sc)
if tap.len > 0: writeFile(getEnv("VAJRA_SHOT_LAYERS"), tap)
if e.crashed.len > 0: quit "the app stopped: " & e.crashed, 1
for i in 7 .. paramCount():
  let label = paramStr(i)
  e.ensureLayout()
  for id in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[id]
    if n.alive and n.kind == 4 and 0'i32 in n.props and n.props[0'i32].s == label:
      let b = e.boxes[int32(id)]
      e.pointerDown(b.x + b.w / 2, b.y + b.h / 2)
      e.pointerUp(b.x + b.w / 2, b.y + b.h / 2)
      break
sleep(parseInt(getEnv("VAJRA_SHOT_WAIT_MS", "0")))   # wall-clock time before the frame
for _ in 1 .. max(1, parseInt(getEnv("VAJRA_SHOT_TICKS", "1"))): e.tick(16)
e.ensureLayout()
let pw = int(w * sc)
let ph = int(h * sc)
var px = newSeq[uint32](pw * ph)
e.paintFrame(addr px[0], pw, ph)
if paramStr(2).endsWith(".png"):
  if not savePixels(paramStr(2), addr px[0], pw, ph): quit "could not write " & paramStr(2), 1
else:
  var bytes = newString(px.len * 4)
  copyMem(addr bytes[0], addr px[0], bytes.len)
  writeFile(paramStr(2), bytes)
echo "frame ", pw, "x", ph
