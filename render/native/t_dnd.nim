import std/[os, tables, strutils], engine, ../../host/tree, ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

proc findNodeByText(e: Engine; txt: string): int32 =
  for id, b in e.boxes:
    if e.node(id).alive and e.node(id).sProp(P_TEXT) == txt: return id
  -1'i32

proc findText(e: Engine; prefix: string): string =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT:
      let t = n.sProp(P_TEXT)
      if t.startsWith(prefix): return t

let here = currentSourcePath().parentDir
let buildDir = here / "build"
let wasmPath = buildDir / "dnd_app.wasm"
let eng = start(wasmPath, 400, 300)
check("engine starts dnd_app.wasm cleanly", eng.crashed.len == 0, eng.crashed)
eng.tick(16.0)
check("initial status is idle", eng.findText("idle") == "idle")

let srcId = eng.findNodeByText("Source")
check("source button found", srcId >= 0)
let targetTextId = eng.findNodeByText("Drop Target")
check("drop target found", targetTextId >= 0)

let srcBox = eng.boxes[srcId]
let tgtBox = eng.boxes[targetTextId]

# 1. Test in-app drag and drop
eng.pointerDown(srcBox.x + 5, srcBox.y + 5)
check("drag started", eng.draggingNode == srcId and eng.findText("dragging") == "dragging card-item")

eng.pointerMove(tgtBox.x + 5, tgtBox.y + 5)
check("dragged over target", eng.findText("over target") == "over target")

eng.pointerUp(tgtBox.x + 5, tgtBox.y + 5)
check("dropped in-app node", eng.findText("dropped node") == "dropped node card-item")
check("drop count is 1", eng.findText("count: 1") == "count: 1")

# 2. Test OS file drop
let sampleFile = buildDir / "dropped_sample.txt"
writeFile(sampleFile, "File drop payload 12345")
eng.dropFile(sampleFile, tgtBox.x + 5, tgtBox.y + 5)
eng.tick(32.0)
check("dropped OS file", eng.findText("dropped file dropped_sample.txt:File drop payload 12345") == "dropped file dropped_sample.txt:File drop payload 12345")
check("drop count is 2", eng.findText("count: 2") == "count: 2")

if fileExists(sampleFile): removeFile(sampleFile)
echo "dnd: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
