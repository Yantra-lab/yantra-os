import std/[os, tables, strutils], engine, ../../host/tree, ../../protocol/wire, ../../libs/nimsdl3/src/nimsdl3

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

proc clickButton(e: Engine; label: string) =
  for id, b in e.boxes:
    if e.node(id).alive and e.node(id).sProp(P_TEXT) == label:
      let cx = b.x + b.w / 2; let cy = b.y + b.h / 2
      e.pointerDown(cx, cy); e.pointerUp(cx, cy); return

proc findText(e: Engine; prefix: string): string =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT:
      let t = n.sProp(P_TEXT)
      if t.startsWith(prefix): return t

let here = currentSourcePath().parentDir
let buildDir = here / "build"
let wasmPath = buildDir / "dialog_app.wasm"
let eng = start(wasmPath, 400, 300)
check("engine starts dialog_app.wasm cleanly", eng.crashed.len == 0, eng.crashed)
eng.tick(16.0); eng.pumpPick()
check("initial status is ready", eng.findText("ready") == "ready")

# Test 1: Open file via mock
let sampleTxt = buildDir / "sample_open.txt"
writeFile(sampleTxt, "Hello from chosen file")
setMockOpenFile(sampleTxt)
eng.clickButton("Open"); eng.tick(32.0)
check("status updated after open", eng.findText("opened") == "opened 22")
check("file content loaded into app memory", eng.findText("Hello from chosen file") == "Hello from chosen file")

# Test 2: Save file via mock
let outTxt = buildDir / "sample_save.txt"
if fileExists(outTxt): removeFile(outTxt)
setMockSaveFile(outTxt)
eng.clickButton("Save"); eng.tick(48.0)
check("status updated after save", eng.findText("saved") == "saved successfully")
check("saved file written to disk", fileExists(outTxt) and readFile(outTxt) == "Hello from chosen file")

# Test 3: Cancelled dialog (empty mock)
setMockOpenFile("")
eng.clickButton("Open"); eng.tick(64.0)
check("cancelled dialog reports failure", eng.findText("open failed") == "open failed")

if fileExists(sampleTxt): removeFile(sampleTxt)
if fileExists(outTxt): removeFile(outTxt)
echo "dialog: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
