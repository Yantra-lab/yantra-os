## Synthesis (AU1) through a real app — examples/shell/band.nim: Synth nodes are voices the
## engine generates natively (miniaudio): pitch, gate, envelope and filter follow the props.
import std/[os, math, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "band.wasm", 300, 200)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc click(name: string) =
  let b = e.boxes[idOf(name)]
  e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
  e.ensureLayout()
proc left(s: seq[float32]): seq[float32] =
  for i in countup(0, s.len - 2, 2): result.add s[i]
proc crossings(s: seq[float32]): int =
  for i in 1 ..< s.len:
    if (s[i - 1] < 0) != (s[i] < 0): inc result
proc rms(s: seq[float32]): float =
  for x in s: result += float(x) * float(x)
  sqrt(result / float(max(1, s.len)))
proc roughness(s: seq[float32]): float =       # how much it changes sample to sample, vs its size
  var d = 0.0
  for i in 1 ..< s.len: d += float(s[i] - s[i - 1]) * float(s[i] - s[i - 1])
  sqrt(d / float(max(1, s.len - 1))) / max(1e-9, rms(s))

var px = newSeq[uint32](300 * 200)
e.paintFrame(addr px[0], 300, 200)
check("the app starts", e.crashed.len == 0, e.crashed)
check("sounds are not laid out", idOf("tone") notin e.boxes and idOf("wind") notin e.boxes)
let tone = idOf("tone")
discard e.synthSamples(tone, 4800)                # past the attack and the volume glide
let a = left(e.synthSamples(tone, 48000))
let c = crossings(a)
check("the tone is at its pitch: 440 Hz", abs(c - 880) <= 8, $c)
check("and loud enough to hear", rms(a) > 0.15, $rms(a))
click("low")
let b = left(e.synthSamples(tone, 48000))
check("a new pitch from the app's state: 220 Hz", abs(crossings(b) - 440) <= 8, $crossings(b))
click("mute")
discard e.synthSamples(tone, 2400)                # the 10 ms release, and then some
check("turning playing off fades it to silence", rms(left(e.synthSamples(tone, 4800))) < 0.001)
let wind = left(e.synthSamples(idOf("wind"), 48000))
let bright = left(e.synthSamples(idOf("bright"), 48000))
check("noise sounds", rms(wind) > 0.005 and rms(bright) > 0.05, $(rms(wind), rms(bright)))
check("a low-pass filter makes noise smooth (wind), unfiltered noise is rough",
      roughness(wind) < 0.2 and roughness(bright) > 1.0, $(roughness(wind), roughness(bright)))
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
