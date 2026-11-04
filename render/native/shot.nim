## Renders an app's first frame (optionally after scripted input) to a raw BGRA dump
## for visual checks: `shot app.wasm out.raw width height scale`.
import std/[os, strutils, tables]
import engine
import ../../host/host, ../../host/tree
let e = start(paramStr(1), parseFloat(paramStr(3)), parseFloat(paramStr(4)), parseFloat(paramStr(5)))
let sc = parseFloat(paramStr(5))
let pw = int(parseFloat(paramStr(3)) * sc)
let ph = int(parseFloat(paramStr(4)) * sc)
var px = newSeq[uint32](pw * ph)
if paramCount() >= 6 and paramStr(6) == "demo":
  # a realistic state: one typed item, one checked, hover on Add

  for id in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[id]
    if n.alive and n.kind == 6:   # input
      let b = e.boxes[int32(id)]
      e.pointerDown(b.x + 20, b.y + 10); e.pointerUp(b.x + 20, b.y + 10)
      e.typeText("Apply to IITM IC"); e.key(13)
      e.typeText("Book the demo slot")
      break
  e.ensureLayout()
  for id in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[id]
    if n.alive and n.kind == 14 and n.props.len > 0:
      let b = e.boxes[int32(id)]
      e.pointerDown(b.x + 5, b.y + b.h / 2); e.pointerUp(b.x + 5, b.y + b.h / 2)
      break
e.paintFrame(addr px[0], pw, ph)
var bytes = newString(px.len * 4)
copyMem(addr bytes[0], addr px[0], bytes.len)
writeFile(paramStr(2), bytes)
