## Q2: examples/shell/recorder.wasm — the mic is allowed only when the app declares it.
import std/[os, strutils, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "recorder.wasm", 420, 560)
var px = newSeq[uint32](420 * 560)
e.paintFrame(addr px[0], 420, 560)
proc click(label: string) =
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == label:
      let b = e.boxes[int32(i)]
      e.pointerDown(b.x + 4, b.y + 4 - e.scrollY); e.pointerUp(b.x + 4, b.y + 4 - e.scrollY)
  e.tick(e.now + 16)
  e.paintFrame(addr px[0], 420, 560)
check("the app starts", e.crashed.len == 0, e.crashed)
check("it declared mic and camera", e.app.hasCapability("mic") and e.app.hasCapability("camera"))
click("Record")
check("a declared mic is not refused", "record 0" in e.s.logs, $e.s.logs)
check("recording, or no microphone on this machine", e.s.captureState in [1'i32, -1], $e.s.captureState)
click("Stop")
check("stopped", e.s.captureState == 0, $e.s.captureState)
e.app.revokeCapability("mic")
click("Record")
check("without the capability the host refuses", "record -1" in e.s.logs, $e.s.logs)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
