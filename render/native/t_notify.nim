import std/[os, tables, strutils], engine, ../../host/tree, ../../host/host, ../../protocol/wire, ../../libs/nimsdl3/src/nimsdl3

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
let wasmPath = buildDir / "notify_app.wasm"
let eng = start(wasmPath, 400, 300)
check("engine starts notify_app.wasm cleanly", eng.crashed.len == 0, eng.crashed)
eng.tick(16.0)
check("initial status is idle", eng.findText("idle") == "idle")

let btnId = eng.findNodeByText("Send Notify")
check("send button found", btnId >= 0)
let btnBox = eng.boxes[btnId]

# 1. Click button to send notification with capability granted
let prevCount = notifyCount()
eng.pointerDown(btnBox.x + 5, btnBox.y + 5)
eng.pointerUp(btnBox.x + 5, btnBox.y + 5)
eng.tick(32.0)

check("status is sent ok", eng.findText("sent ok") == "sent ok")
let (t, b) = lastNotification()
check("notification title received", t == "Build Complete", t)
check("notification body received", b == "App compiled successfully", b)
check("notifyCount incremented", notifyCount() > prevCount)

# 2. Revoke capability and verify refusal
revokeCapability(eng.app, "notifications")
eng.pointerDown(btnBox.x + 5, btnBox.y + 5)
eng.pointerUp(btnBox.x + 5, btnBox.y + 5)
eng.tick(48.0)
check("status is sent failed after capability revoked", eng.findText("sent failed") == "sent failed")

echo "notify: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
