## Proves a port: an app's original build and its Vajra port, each drawn by the
## real engine from a fresh start, compared pixel by pixel.
##   vajra_parity original.wasm y:@space/cell.Name width height [user]
## Exit 0 when every pixel is equal. Each run starts clean: the original gets an
## empty data folder, the port's person an empty `vajra_store`.
import std/[os, strutils]
import engine
import ../../host/host
import ../../host/vajra/[live, apps]
import ../../host/atlas/[atlas, records]
import ../../libs/nimpg/src/pgclient

if paramCount() < 4: quit "usage: vajra_parity original.wasm y:@space/cell.Name width height [user]", 2
let info = getEnv("YANTRA_DB", "host=localhost port=5433 dbname=yantra user=postgres")
let w = parseFloat(paramStr(3))
let h = parseFloat(paramStr(4))
let user = if paramCount() >= 5: paramStr(5) else: "7"
var a = atlas.open(info)
serveFromAtlas(a)

proc frame(app: string): seq[uint32] =
  let e = start(app, w, h, 1)
  if e.crashed.len > 0: quit app & " stopped: " & e.crashed, 1
  e.tick(16)
  e.ensureLayout()
  result = newSeq[uint32](int(w) * int(h))
  e.paintFrame(addr result[0], int(w), int(h))

# the original, with an empty data folder
let fresh = getTempDir() / "vajra-parity-data"
removeDir(fresh)
createDir(fresh)
putEnv("YANTRA_DATA", fresh)
let original = frame(paramStr(1))

# the port, as `user`, with nothing saved
let ad = parseAddress(paramStr(2))
let space = a.db.value("select id from atlas.space where handle = $1", ad.handle)
if space == "": quit "no space " & ad.handle, 1
a.db.exec("delete from " & a.applyRecords(space, ad.root) & ".vajra_store where owner = $1", user)
discard openLive(a, paramStr(2), user)
let port = frame(paramStr(2))

var differ = 0
var worst = 0
for i in 0 ..< original.len:
  if original[i] != port[i]:
    inc differ
    for shift in [0, 8, 16, 24]:
      worst = max(worst, abs(int((original[i] shr shift) and 0xFF) - int((port[i] shr shift) and 0xFF)))
echo "pixels: ", original.len, "  differing: ", differ, "  largest channel difference: ", worst
quit(if differ == 0: 0 else: 1)
