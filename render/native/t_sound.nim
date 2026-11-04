## Audio in apps (C2): `sound "click.wav"` / `play(s)`, `stop(s)`, `setVolume(s, v)`, `volume(s)`
## through `libs/nimminiaudio`; files only via `resolveAsset` (the app's own folder).
import std/[os, tables, math]
import engine
import ../../host/tree
import ../../protocol/wire
from ../../libs/nimminiaudio/src/nimminiaudio as ma import nil

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

proc writeTestWav(path: string; amp: float64) =
  let w = ma.newWaveform(ma.formatF32, channels = 1, sampleRate = 48000, ma.waveSine, amplitude = amp, frequency = 440.0)
  var buf = newSeq[float32](4800)
  discard ma.readPcmFrames(w, buf[0].addr, 4800)
  ma.free(w)
  let enc = ma.newEncoder(path, ma.encodingWav, ma.formatF32, channels = 1, sampleRate = 48000)
  discard ma.writePcmFrames(enc, buf[0].addr, 4800)
  ma.free(enc)

proc peakOf(samples: seq[float32]): float32 =
  for s in samples:
    if abs(s) > result: result = abs(s)

proc clickButton(e: Engine; label: string) =
  for id, b in e.boxes:
    if e.node(id).alive and e.node(id).sProp(P_TEXT) == label:
      let cx = b.x + b.w / 2
      let cy = b.y + b.h / 2
      e.pointerDown(cx, cy)
      e.pointerUp(cx, cy)
      return

let here = currentSourcePath().parentDir
let buildDir = here / "build"
let appFolder = buildDir / "sound_app_dir"
createDir(appFolder)

let clickWav = appFolder / "click.wav"
let secretWav = buildDir / "secret.wav"
writeTestWav(clickWav, 0.8)
writeTestWav(secretWav, 0.9)
copyFile(buildDir / "sound_app.wasm", appFolder / "sound_app.wasm")

let eng = start(appFolder / "sound_app.wasm", 400, 300)
check("engine starts sound_app.wasm cleanly", eng.crashed.len == 0, eng.crashed)

let idleSamples = eng.pumpAudio(512)
check("before play(), pumpAudio returns silence", peakOf(idleSamples) == 0.0'f32, $peakOf(idleSamples))

eng.clickButton("Play")
let fullSamples = eng.pumpAudio(512)
let fullPeak = peakOf(fullSamples)
check("after clicking Play, pumpAudio mixes decoded WAV samples (> 0.5 peak)", fullPeak > 0.5'f32, $fullPeak)

eng.clickButton("Half")
let qrtrSamples = eng.pumpAudio(512)
let qrtrPeak = peakOf(qrtrSamples)
check("after clicking Half (0.25 volume), pumpAudio scales amplitude to 1/4", qrtrPeak > 0.1'f32 and abs(qrtrPeak - fullPeak * 0.25'f32) < 0.05'f32, "qrtr=" & $qrtrPeak & " full=" & $fullPeak)
check("app volume(s) returns 0.25 after setVolume", eng.s.lastLog() == "0.25", eng.s.lastLog())

eng.clickButton("Stop")
let stoppedSamples = eng.pumpAudio(512)
check("after clicking Stop, pumpAudio immediately returns silence", peakOf(stoppedSamples) == 0.0'f32, $peakOf(stoppedSamples))

eng.clickButton("Bad")
let badSamples = eng.pumpAudio(512)
check("sound('../secret.wav') outside app folder is refused by resolveAsset", peakOf(badSamples) == 0.0'f32, $peakOf(badSamples))

eng.closeSounds()
removeFile(clickWav)
removeFile(secretWav)
removeFile(appFolder / "sound_app.wasm")
echo "sound: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
