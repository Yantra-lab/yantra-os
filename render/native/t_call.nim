## Q11: two copies of examples/shell/call.wasm in one process, their signaling relayed by the
## test: the WebRTC call connects (libdatachannel, host candidates on this machine).
import std/[os, strutils, tables, times]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let wasm = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "call.wasm"
let a = start(wasm, 360, 240)
let b = start(wasm, 360, 240)
var px = newSeq[uint32](360 * 240)
proc frame(e: Engine) = (e.tick(e.now + 16); e.paintFrame(addr px[0], 360, 240))
proc click(e: Engine; label: string) =
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == label:
      let bx = e.boxes[int32(i)]
      e.pointerDown(bx.x + 4, bx.y + 4); e.pointerUp(bx.x + 4, bx.y + 4)
proc status(e: Engine): string =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT: return n.sProp(P_TEXT)
var seenA, seenB = 0
proc relay(src, dst: Engine; seen: var int) =
  while seen < src.s.logs.len:
    let l = src.s.logs[seen]
    inc seen
    if l.startsWith("sig:"): dst.deepLink(l[4 .. ^1])
frame(a); frame(b)
check("both start", a.crashed.len == 0 and b.crashed.len == 0)
b.click("Answer")
a.click("Call")
check("the calls are allowed (mic + calls declared)", "start 0" in a.s.logs and "start 0" in b.s.logs, $a.s.logs)
let t0 = epochTime()
while epochTime() - t0 < 10 and not (a.status == "state 2" and b.status == "state 2"):
  frame(a); frame(b)
  relay(a, b, seenA); relay(b, a, seenB)
  sleep(10)
check("the call connects on both sides", a.status == "state 2" and b.status == "state 2", a.status & " / " & b.status)
a.click("Hang up")
frame(a)
check("hanging up", a.status == "ended")
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
