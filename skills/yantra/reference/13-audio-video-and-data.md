# 13 — Audio, video, storage and networking

Yantra apps are sandboxed wasm modules: no filesystem, no OS, no socket of their own. Audio
must be something the **host** owns, storage must go through a host call, and the network
must be opened by the host on the app's behalf. This chapter is the map of those four.

Everything below was read out of source. Line numbers are for orientation; the API text is
copied exactly. Nothing in this chapter is left unverified: each claim below carries the
`path:line` it was read from, and the one place where this is a *source* reading rather than an
executed test says so in place (§1b, formats).

---

## 1. Audio

There are exactly two routes to sound. Pick by "is it a tone" vs "is it a recording".

| Route | What it is | Node / API | Costs |
|---|---|---|---|
| **Synth** | a live voice the engine generates (miniaudio) | `synth(...)` node, `nkSynth` = 46 | no asset, no file |
| **Sound file** | a pre-rendered file the host decodes and mixes | `sound("x.wav")` + `play`/`stop`/`setVolume` | an asset next to the `.wasm` |

### 1a. The synth node — `synth(...)`

`synth` is a DSL keyword, not a `proc`. `sdk/ui/dsl.nim:360`:

```nim
of "synth":
  # `synth(freq = pitch, wave = 3, filter = 1, cutoff = 800, playing = held)`: a sound the
  # engine makes (AU1) — wave or noise, filtered, enveloped, echoed, panned; not laid out
  kindCap = "Synth"
  result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkSynth", parentSym)))
```

A synth node is **not laid out** — it takes no box and is invisible
(`render/native/t_synth.nim:38`: `idOf("tone") notin e.boxes`). It exists only to make sound.

**The full parameter set.** Every prop is read each frame in `render/native/engine.nim:4036-4050`;
the defaults in the right-hand column are the ones the engine supplies when the prop is absent.
The ranges are what the C voice actually clamps to (`libs/nimminiaudio/src/nimminiaudio.nim:97-136`).

| Prop | id | DSL name | Default | Meaning / range |
|---|---|---|---|---|
| `pWave` | 212 | `wave` | 0 | source: **0** sine, **1** square, **2** triangle, **3** sawtooth, **4** white noise, **5** pink noise, **6** brown noise |
| `pFreq` | 213 | `freq` | 440 | pitch in Hz (a signal → the pitch follows the app) |
| `pVolume` | 75 | `volume` | 0.5 | gain 0..1; changed values glide over ~10 ms so they don't click |
| `pFilterKind` | 214 | `filter` | 0 | **0** none, **1** low-pass, **2** high-pass, **3** band-pass (miniaudio `ma_lpf2` / `ma_hpf2` / `ma_bpf2`) |
| `pCutoff` | 215 | `cutoff` | 1000 | Hz, **clamped 10 … 20000** |
| `pResonance` | 216 | `resonance` | 0.707 | filter Q, **clamped to ≥ 0.1** |
| `pPan` | 217 | `pan` | 0 | −1 hard left … +1 hard right, **clamped** |
| `pAttack` | 218 | `attack` | 0.01 | seconds, **clamped to ≥ 0.001** |
| `pRelease` | 219 | `release` | 0.2 | seconds, **clamped to ≥ 0.001** |
| `pEcho` | 220 | `echo` | 0 | delay time in **seconds** (`delay = echo * 48000` frames); the delay buffer is 2 s, so > ~2 s is pointless |
| `pEchoMix` | 221 | `echoMix` | 0.4 | wet mix 0..1 |
| `pEchoFeedback` | 222 | `echoFeedback` | 0.3 | **clamped to ≤ 0.95** (self-oscillation guard) |
| `pLfo` | 223 | `lfo` | 0 | vibrato rate in Hz; 0 = off |
| `pLfoDepth` | 224 | `lfoDepth` | 0.01 | pitch swing as a **fraction** (0.01 = ±1 %) |
| `pPlaying` | 160 | `playing` | (absent ⇒ on) | the gate. `engine.nim:4050`: `if not n.has(P_PLAYING) or n.flag(P_PLAYING)`. Turning it off fades out over `release`, it does not cut. |

Note `volume` here is `pVolume` (75) — the same prop the `audio` node uses — but the synth
default is **0.5**, while a media node's default is **1**.

**The working example** — `examples/shell/band.nim`, the fixture `render/native/t_synth.nim`
drives and measures:

```nim
let pitch = state 440'f32
let on = state true

app("Band", width = 300, height = 200, fill = 0x101014):
  column(gap = 8.px, pad = 12.px):
    button @low "Low":
      onClick: pitch.set(220)
    button @mute "Mute":
      onClick: on.set(false)
    synth @tone(freq = pitch, volume = 0.5, playing = on, attack = 0.001, release = 0.01)
    synth @wind(wave = 5, filter = 1, cutoff = 300, volume = 0.5)   # pink noise, low-passed
    synth @bright(wave = 4, volume = 0.5)                            # raw white noise
```

What the test proves, so you know it is real and not declared (`t_synth.nim`):
* zero-crossing counting finds **440 Hz** before the click and **220 Hz** after — a signal
  really does drive the pitch;
* RMS > 0.15 (audible), and turning `playing` off fades to silence over the 10 ms release;
* `wave = 4` (white) is rough, `wave = 5` through `filter = 1` (low-pass) is smooth
  (roughness 0.2 vs > 1.0) — the filter really runs.

Copy `band.nim` and run `render/native/t_synth.nim` before you trust your own synth.

### 1b. Sound files — the pattern apps/typewriter actually uses

This is the proven route for a real sound effect, and the answer to "I have a Web Audio
sound effect, how do I get it into a Yantra app?"

**The API** (`sdk/core/runtime.nim:341-366`, exact):

```nim
type
  Sound* = object
    id*: int32
    vol*: float32

proc sound*(path: string): Sound =
  let p = if path.len > 0: cast[int32](path.cstring) else: 0'i32
  Sound(id: ySoundLoad(p, int32(path.len)), vol: 1.0'f32)
proc play*(s: Sound) = ySoundPlay(s.id)
proc stop*(s: Sound) = ySoundStop(s.id)
proc setVolume*(s: var Sound; v: float32) =
  s.vol = clamp(v, 0.0'f32, 1.0'f32)
  ySoundVol(s.id, s.vol)
proc volume*(s: Sound): float32 = s.vol
```

`setVolume` takes `var Sound`, so pass a `var` (a global or a local field), not a literal.
On a native test build (32-bit pointer absent) `play`/`stop` are no-ops and only `vol` moves.

**Where the file goes.** Right next to the `.wasm`. `sound("key.wav")` is a *relative name*
resolved by `Engine.resolveAsset` (`render/native/engine.nim:1138`):

```nim
proc resolveAsset*(e: Engine; p: string): string =
  if p.startsWith("data/") and ...: return dataDir() / e.s.appName / p[5 .. ^1]
  if validAssetPath(p) and e.appDir.len > 0:
    return e.appDir / p
  ...
```

and `validAssetPath` (`engine.nim:934`) is the sandbox rule:

```nim
p.len > 0 and p.len <= 200 and p[0] != '/' and ':' notin p and '\\' notin p and ".." notin p and
  p.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.', '/'})
```

So: sub-folders are allowed (`clips/intro.mp4` is valid), absolute paths, drive letters,
backslashes and `..` are all refused, and a refused path resolves to `""` — which means
**silence, not an error**. `sound("../secret.wav")` compiles, runs, and does nothing
(`render/native/t_sound.nim:68-70`).

**There is no manifest to declare assets.** `apps/typewriter/` has **no `app.json`** — I
checked. `app.json` is desktop-catalog metadata only (`id` / `name` / `icon` / `grants`),
read by `tools/apps-index.sh` to generate `apps/desktop/catalog.nim`. Assets are pure
filesystem convention: **the `.wav` sits in the same folder as `app.wasm`, and the app names
it with a relative path.**

**Exactly what apps/typewriter does** (`apps/typewriter/app.nim`):

```nim
var
  sndKey, sndSpace, sndSoft, sndBell, sndRet, sndPaper: Sound

proc initSounds() =
  ## Synthesized typewriter sounds (apps/typewriter/*.wav), baked to mirror the
  ## HTML's WebAudio recipes: key click, space thump, soft tick, margin bell,
  ## return ratchet + glide, paper feed rustle.
  sndKey = sound("key.wav")
  sndSpace = sound("space.wav")
  sndSoft = sound("soft.wav")
  sndBell = sound("bell.wav")
  sndRet = sound("return.wav")
  sndPaper = sound("paper.wav")

proc playSnd(s: Sound) =
  if not muted.get(): play(s)
```

and it is called **twice**, at line 1203 (top level) *and* line 1208 (inside the `app` block)
— once for a cold start, once per hot reload, because the engine re-runs the UI block but
not top-level statements.

Then every trigger goes through `playSnd`, never `play`: `playSnd(sndBell)` at the margin,
`playSnd(sndKey)` per keystroke, `playSnd(sndSpace)` for space, `playSnd(sndRet)` for the
carriage return, `playSnd(sndPaper)` for the sheet rustle. **Mute is an app-level gate, not
`setVolume(s, 0)`** — `muted = state false` plus `if not muted.get()`. That is deliberate:
it also stops a sound that has already started being debated.

The six files, in the folder, sizes as built: `key.wav` 7,982 B · `space.wav` 10,628 B ·
`soft.wav` 7,100 B · `bell.wav` 149,984 B · `return.wav` 52,964 B · `paper.wav` 66,194 B.
These are **baked .wav assets generated from the HTML's Web Audio recipes**, not live DSP —
see the comment above `initSounds`. That is the whole port in one sentence.

**What the host does with them** (`engine.nim:3602-3634`):

* load: `resolveAsset` → `ma.newDecoder(full)`; a file that will not resolve or will not
  decode leaves **no slot at all**, so `play` on it is a no-op;
* `play`: **seeks to PCM frame 0 first**, then starts mixing — so one `Sound` object replays
  from the top every time and cannot play two overlapping copies;
* `stop`: stops and rewinds;
* mixing stops itself when the decoder runs out (`if got < frames: slot.playing = false`).

`render/native/t_sound.nim` proves the whole chain: silence before `play()`, decoded
samples in the mix after (> 0.5 peak for a 0.8-amplitude WAV), `setVolume(s, 0.25)` scaling
the peak to exactly a quarter, `stop()` back to instant silence, and `../secret.wav` refused.

**Formats. CLOSED 2026-10-03 — MP3 and FLAC are compiled in; this was settled from the build
recipe, not by rendering.** The decoder is miniaudio's `ma_decoder_init_file`
(`libs/nimminiaudio/src/nimminiaudio.nim:33-36`), and miniaudio's built-in decoders are
**WAV, MP3, FLAC** (`third_party/miniaudio/miniaudio.h:2479-2485`) plus stb Vorbis
(`miniaudio.h:63021`, `#if !defined(MA_NO_VORBIS)`). Each is compiled unless explicitly disabled:
the MP3 decoder body is inside `#if !defined(MA_NO_MP3) && !defined(MA_NO_DECODING)`
(`miniaudio.h:60457`, and again `:89808`), FLAC behind `#if !defined(MA_NO_FLAC) && !defined(MA_NO_DECODING)`
(`miniaudio.h:60170`).

**Nothing in this repo disables any of them.** The library is compiled by the `static:` block at
`libs/nimminiaudio/src/nimminiaudio.nim:7`:

```
gcc -O2 -c -DMINIAUDIO_IMPLEMENTATION -x c ".../third_party/miniaudio/miniaudio.h" -o miniaudio.o
```

`MINIAUDIO_IMPLEMENTATION` is the **only** `-D` on that line. A sweep of every `.nim`, `.nims`,
`.sh`, `.ps1`, `.bat`, `.cmd`, `.json` and `.yml` file under `libs/`, `render/`, `host/`,
`tools/`, `sdk/`, `bridge/` and `cli/` for `MA_NO_` / `-DMA_` / `-D MA_` returns **zero**
miniaudio hits — the only `-D` flags anywhere in those trees are `-DUNICODE`, `-D_UNICODE`
(`libs/nimqt/config.nims:56-57`, `render/config.nims:141-142`) and `-DYANTRA_HAS_3D`
(`render/config.nims:216`). Excluded from that sweep: `third_party/` and `node_modules/`, which
are gitignored build inputs, not build flags. So `sound("track.mp3")` decodes.

Two honest caveats:

- **No MP3 is exercised anywhere in this repo.** Only WAV is (`t_sound.nim` generates WAVs; the
  typewriter ships WAVs), so the MP3 claim above is a statement about what the build compiles,
  not a measured playback.
- **The linked `.a` is a prebuilt artifact and was not rebuilt for this check.**
  `libs/nimminiaudio/build/libminiaudio.a` exists (828,138 B, dated 25-09-2026) and the `static:`
  block only builds it `if not fileExists(...)` (`nimminiaudio.nim:5`). Per AGENTS.md rule 2, to
  trust this end-to-end, delete that file and let it rebuild.

For an `audio` node the path is different and stronger: `openPlayer` is libav-backed
(`render/native/t_video.nim` says "FFmpeg's libraries"), and `examples/film` uses `.mp4` there.

### 1c. Synth or file? — the honest answer for a Web Audio port

An HTML file's Web Audio graph cannot run: there is no `AudioContext` inside the wasm. So
every Web Audio sound becomes one of two things.

**Prefer a generated `.wav` asset whenever the sound has a real timbre** — a key click, a
ratchet, a rustle, a bell. A `.wav` is one line of app code (`sound("key.wav")`), plays with
correct envelopes, filters and noise for free, and is what a working app in this repo does.
The cost is one asset in the app folder.

**Prefer `synth` only for a plain tone or gate** — a beep, a held drone, a pitch that must
follow a signal, a filtered-noise "wind". It costs no asset and reacts to state.

If the HTML sound is genuinely real-time DSP — an `AudioWorklet`, granular synthesis, a
convolution reverb whose impulse response is generated at runtime, anything that reacts to
a microphone — then see §5: it is not supported, and you pre-render it to a file instead.

### 1d. Microphone, speakers, notifications (adjacent, verified)

From `sdk/core/runtime.nim:236-252, 293-299, 319-337`:

```nim
proc recordStart*(file: string): int32 = captureCall(1, 1, file)   ## .ogg/.opus Opus, .m4a AAC
proc recordPause*(): int32 = captureCall(1, 2)
proc recordResume*(): int32 = captureCall(1, 3)
proc recordStop*(): int32 = captureCall(1, 4)     ## finish and keep the file
proc recordCancel*(): int32 = captureCall(1, 5)   ## stop and delete it
proc micLevel*(): float32 = float32(captureCall(1, 7)) / 1000   ## 0..1, poll it
proc takePhoto*(file: string): int32 = captureCall(2, 6, file)
proc openUrl*(url: string): bool
proc notify*(title, body: string): bool
```

Recording and camera need `needs("mic")` / `needs("camera")`, else every call returns −1.
Recordings land in the app's data folder and are played back with
`audio "data/<file>"` — that is the `data/` branch of `resolveAsset`.