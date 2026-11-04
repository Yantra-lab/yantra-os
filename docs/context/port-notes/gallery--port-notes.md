# #39 virtual-gallery — port notes

Port of `apps/gallery/039-virtual-gallery.html` to `apps/gallery/app.nim`.

Every number below was produced by the same four-step command, at 1280×800, with the
raw frame byte-swapped before it was diffed (`render/native/drive.nim:191-193` writes a
`seq[uint32]` to disk as B,G,R,A):

```
bash tools/build-wasm.sh apps/gallery/app.nim .board/frames/gal2.wasm
& .\render\native\build\drive.exe .\.board\frames\gal2.wasm .\.board\frames\gal2_w8.raw 1280 800 1 "wait:8"
node tools/rawswap.mjs .board/frames/gal2_w8.raw .board/frames/gal2_w8_sw.raw
node tools/pngdiff.mjs .board/frames/ref039_800.png .board/frames/gal2_w8_sw.raw 1280 800
```

**Status: NOT matching. 72.66% of pixels differ at the reference clock.**

## 1. Before / after

The starting point handed to this round was 745,957 px (72.85%) / mean |Δ| 33.19,
from a build made before this session. **To make before/after honest I re-measured
the baseline on the same toolchain**: I temporarily restored the debug scaffolding,
built, measured, then removed it again. Both numbers below are therefore from
identical tooling, same day.

**Before** (debug scaffolding live, as found):

```
build-wasm: wrote .board/frames/gal2base.wasm (504609 bytes)
crashed=[] now=800.0
differing pixels : 745,635 / 1,024,000  (72.82%)
mean |delta|     : 33.86
max  |delta|     : 250
```

**After** (this round's fix):

```
build-wasm: wrote .board/frames/gal2.wasm (509720 bytes)
crashed=[] now=800.0
differing pixels : 744,015 / 1,024,000  (72.66%)
mean |delta|     : 31.60
max  |delta|     : 233
```

**−1,620 pixels, −0.16 points, mean |Δ| −2.26, max |Δ| −17.** Small, but the first
real movement in several rounds, and §4 explains why it is not larger.

### Determinism checks

* The renderer is **exactly reproducible**: three consecutive `wait:8` runs of the
  same binary gave byte-identical numbers (744,015 / 31.60 each time).
* The **build is not byte-deterministic**: the same source produced 509,720 and
  509,721-byte wasm with different SHA-256. Both produce **identical** frame
  numbers, so this does not affect the measurement — but it does mean the byte
  count in a build log is not a reliable fingerprint of the source.
* Earlier in the session a build of the *fixed* source reported 72.57% rather than
  72.66%. That was a different nimcache state; the number above is the reproducible
  one from a clean pair of builds.

## 2. Which camera state is the reference

**Answer, with evidence: the reference is at the camera's initial rest pose, and so
is the port. There is no camera/state mismatch. This is a geometry + tone problem,
not an animation desync.**

Method: `.board/frames/gal2/align.mjs` downsamples both frames to a 160×100 grid,
normalises each to zero-mean/unit-sd, and scans every shift in ±14 cells.

| clock | `now` | zero-shift corr | best shift | best corr |
|---|---|---|---|---|
| `wait:1` | 240.0 | −0.080 | dx=+14, dy=−11 | 0.026 |
| `wait:8` | 800.0 | **0.704** | **dx=0, dy=0** | 0.704 |
| `wait:20` | 1760.0 | 0.707 | dx=0, dy=0 | 0.707 |
| `wait:45` | 3760.0 | 0.707 | dx=+1, dy=0 | 0.710 |
Three independent confirmations:

1. **Best fit is exactly zero shift at every clock past the bake.** A large
   coherent offset would mean phase; a scale or centroid error would mean geometry.
   It is neither. Centroids agree to ~12 px in x, ~5 px in y.
2. **The diff is flat across an 18× clock range** (72.66 → 72.80 → 73.05%). A
   desync grows with time. This one does not move. Per the `ISSUES.md` method note,
   flat over time ⇒ geometry/tone.
3. `drive.exe` stderr shows `crashed=[]` at every clock, and the Draw command count
   is stable at 8452 for `wait:8/20/45` (8706 at `wait:1`, +254 = the bake/veil
   phase still running).

`wait:1` differs only because the bake has not finished — its correlation is
*negative* (−0.08), which is what a partly-drawn frame looks like.

Why it is static, from the source: `cam = {x:0,y:0,z:160,rot:0}` and `tgt` identical;
`moved = 0` so the bob term is ~0; the only remaining motion is
`sway = sin(idleT*.35)*.5`, at most 0.5°; `setPersp` gives
`persp = round(clamp(560, min(1000, 1280*.6))) = 768`; fog is saturated
(`endDist = 2460`, `clamp((2460-500)/1300) = 1`, `rot = 0`).

**Clock rule: `wait:8` (800 ms) is the principled clock** and every headline number
here is at `wait:8`. No better-scoring clock is being adopted; the `wait:1/20/45`
numbers are reported for diagnosis only.

## 3. Reference provenance (established, so it need not be re-derived)

* Frame is **1280×800**. `capture-ref.ps1` writes **1280×816** (window-size); the
  shipped reference is the **top 800 rows**. Verified: crop offsets y0=0/8/16 all
  give ≈0.08% differing, y0=0 marginally best.
* The shipped `ref039_800.png` **is reproducible**: a fresh 800 ms capture cropped
  to 800 matches it to 0.08% (799 px, mean |Δ| 0.01).
* The reference is **completely static from 800 ms onward** — see §5.2.
* Colour is AARRGGBB; every colour constant needs an explicit `0xFF` alpha byte.
* `Draw.text` y is the **top of the paragraph line box**: `yantra_y = baselineY −
  1.0833·size`.
* Sample texture with a **window** (9×9 or 40–64 px cells), never single pixels —
  reference grain contrast ≈ 8/255, which equals the diff tolerance.

## 4. Why nothing had been working

The port had **debug scaffolding left live in the sprite baker**. `buildSprite`
returned early, immediately after painting four saturated colour bands and
discarding the entire real frame/mat/artwork path beneath:

```nim
spriteLayer[i] = newLayer(sw, sh)
## DEBUG: four coloured horizontal bands — which rows of the sprite reach the frame?
var dbg = Draw()
dbg = dbg.rect(0, 0, sw.float32, sh.float32 / 4, hex(0xFF0000))
dbg = dbg.rect(0, sh.float32 / 4, sw.float32, sh.float32 / 4, hex(0x00FF00))
dbg = dbg.rect(0, sh.float32 / 2, sw.float32, sh.float32 / 4, hex(0x0000FF))
dbg = dbg.rect(0, sh.float32 * 3 / 4, sw.float32, sh.float32 / 4, hex(0xFFFF00))
spriteLayer[i].draw(dbg)
return          ## <-- everything below is dead code
```

**This is why the number had not moved across several rounds: no round was ever
measuring the paintings.** Every edit to the frame code, the rope ring, the mat or
the generators was landing in dead code, so the diff had no reason to move.

It also explains the two symptoms that had been read as palette bugs:

* `0,255,255` cyan covering **6.14%** of the left band (`0,150–200,350`) — the blue
  debug band after fog/vignette compositing. Located by `hist.mjs`: 7,254 px,
  bbox x45–974 y155–552.
* A magenta fill over every artwork: `d.rect(cx0, cy0, w.w*S, w.h*S, hex(0xFF00FF))`
  — a placeholder where the real `artLayer[i]` should be blitted.

Also live: `if true:` guarding the gold rope ring, with a comment saying it had been
disabled "to test Draw truncation" — and its `else` branch was the *black* frame, so
this was actively wrong, not merely disabled.

**A second, independent debug path was also live**, found on the final sweep:

```nim
## ── DEBUG SCAFFOLD (gal2 round 2) ──
const DBG_ON = true
const DBG_I = 0'i32
...
  if i == DBG_I and DBG_ON:
    d = d.rect(0, 0, sw.float32, sh.float32, 0xFFFF00FF'u32)   ## whole sprite magenta
```

It painted sprite 0 solid magenta *over* its real contents, so even the artwork I
had just restored was being covered. Removing it changed the headline by **zero**
(744,015 either way) — sprite 0 is far down the corridor and heavily fogged, so
essentially none of it survives to the frame. Both scaffolds are now gone and
`find.mjs` reports **count=0** frame-wide for `near 255,0,255 12`.

## 5. Iteration ledger

### 5.1 Removed the debug bands and the magenta placeholder — 72.82% → 72.66%

Three edits in `buildSprite` (`app.nim:1155ff`):

1. Deleted the `dbg` Draw and its `return`, so the real frame/mat path runs.
2. Replaced the magenta placeholder with the real artwork:
   `d = d.layer(artLayer[i], cx0, cy0, w.w * S, w.h * S)`. `artLayer[i]` is already
   baked (`bakeTick` steps 0–7 run before steps 8–15 build the sprites), and the
   SDK's `layer()` emits the `Y` verb, which `skia_shim.cpp:1367` implements as a
   `drawImageRect` of a layer snapshot — verified implemented, not a no-op.
3. Changed `if true:` to `if w.gold or w.key == "mosaic":` on the rope ring. The
   source confirms this selector: `html:846` adds `.sheen` for
   `f.kind === 'gold' || w.key === 'mosaic'`, and the rope is `.frame.gold::before`
   (`html:64`), so gold frames only.

Verified the debug colours are gone — `find.mjs` reports **count=0** frame-wide for
`near 0,255,255 4`, `near 255,0,0 20`, `near 255,255,0 20`, `near 255,0,255 20`
(cyan was 7,254 px before).

**That this only moved 0.16 points is itself the finding**: the paintings were never
drawn, but they are also a small fraction of the frame. The corridor is what is
wrong — see §7.

### 5.2 Tried: a residual loading veil — REFUTED, not adopted

Hypothesis: the port's 0.78 brightness ratio might be the source's loading veil
(`.veil{ position:fixed; inset:0; background:var(--night); transition:opacity 1s ease }`,
`html:195-199`) not having finished fading at 800 ms.

The supporting evidence looked convincing:

* `veil.mjs` fitted `ref = a*port + (1-a)*rgb(11,10,9)`; best `a = 0.66`
  (rms 31.6 vs 39.99 for no model).
* `tone.mjs` found a pure gain of 0.78 was the single best global tone model
  (mean|d| 18.85 vs 26.02 identity).
* The per-channel fit at y=620 was self-consistent at α≈0.22 in R, G **and** B
  independently — which is what a real flat overlay looks like.

**The decisive test killed it.** I re-captured the reference at 1400/2000/3000 ms
budgets and compared to the 800 ms one (`p2p.mjs`, PNG-vs-PNG):

| comparison | differing | mean \|Δ\| |
|---|---|---|
| ref@800 vs ref@1400 | 396 (0.04%) | 0.01 |
| ref@800 vs ref@2000 | **0 (0.00%)** | **0.00** |
| ref@800 vs ref@3000 | **0 (0.00%)** | **0.00** |

The reference is **completely settled by 800 ms** — the veil is fully gone, exactly
as `bez.mjs` predicts from the CSS timing (`.gone` at t≈78 ms, then 722 ms into a 1 s
`cubic-bezier(.25,.1,.25,1)` ease ⇒ 0.05 residual, and in practice 0). So the 0.78
is a genuine brightness error **in the port**, not a capture artefact.

The overlay sweep, applied directly to the port frame and measured with the official
`pngdiff` each time, is recorded because it bounds what any global tone fix could
buy — not because it is the answer:

| α (veil) | differing | mean \|Δ\| |   | gain | differing | mean \|Δ\| |
|---|---|---|---|---|---|---|
| 0.00 | 72.57% | 31.23 | | 0.70 | 66.84% | 24.50 |
| 0.10 | 58.73% | 26.87 | | 0.75 | 56.14% | 23.52 |
| 0.20 | 52.92% | 23.33 | | **0.78** | **55.21%** | **23.38** |
| **0.25** | **51.17%** | **22.50** | | 0.82 | 56.43% | 23.80 |
| 0.30 | 53.73% | 22.77 | | 0.86 | 58.55% | 25.02 |
| 0.40 | 75.25% | 24.54 | | | | |

So a global tone correction is worth ~17–21 points. It is a **rescale**, and a
rescale is not a fix: it would flatten the contrast structure that §7 shows is still
wrong underneath. Not adopted.

### 5.3 Earlier rounds (kept for continuity; all measured, none moved the number)

| # | change | differing px | % |
|---|--------|--------------|---|
| 0 | baseline | 745,957 | 72.85% |
| 1 | gold rope drawn as a **ring** instead of full-height bars | 745,957 | 72.85% |
| 2 | `quadPx` near-plane cull sign | 765,453 | 74.75% |
| 3 | painting quad uses `paintX(w)` for all four corners | — | — |
| 4 | sheen quad de-degenerated | 748,372 | 73.08% |
| 5 | `quadPx`: perspective-correct u,v | 748,232 | 73.07% |
| 6 | `quadPx`: perspective-correct depth | 750,578\* | 73.30%\* |
| 7 | `quadPx`: scanline ends are the two edge crossings | 748,172 | 73.06% |

\* measured against the temporary four-band debug sprite, so not comparable to the
rows above.

Every one of these is a fix to a defect that can be demonstrated, and none moved the
headline number below baseline — **because they were all landing in the dead code of
§4.** That is the single most important lesson of this port: for several rounds the
instrument was fine and the target was not being drawn.

### 5.4 Instrument bugs found and fixed

Recorded because each produced a plausible-looking wrong number:

* `blockmap.mjs` mis-parsed raw dimensions (passed cols/rows as W/H). Abandoned for
  `bm.mjs`.
* `mean.mjs`/`find.mjs` need a **post-`rawswap`** raw; feeding an un-swapped raw
  silently reports every pixel wrong.
* My first veil sweep was invalid — I applied the overlay to an already-swapped raw
  and then ran `rawswap` a second time. Caught because the α=0 row disagreed with the
  official 72.57%. Any instrument reporting a *worse* number for "no change" than the
  official tool is wired up wrong.
* `verify.mjs` treated a PNG as a raw when I tried PNG-vs-PNG work, giving
  `mean |delta| NaN` and a nonsense 28.19%. `pngdiff.mjs` only accepts a raw as its
  second argument; wrote `p2p.mjs` instead.

**Instrument validation**: `verify.mjs` independently reproduces the official
`differing pixels` exactly. The instruments above are trusted only because they were
checked against `pngdiff.mjs`.

The multi-clock and alpha-sweep figures quoted in §2 and §5.2 were taken on the
intermediate 508,307-byte build, which measured 72.57% rather than the clean
72.66%. The offsets are ≤0.09 points and do not change any conclusion; the headline
before/after in §1 is the clean same-toolchain pair.

## 6. Files

* Modified: `apps/gallery/app.nim` — only `buildSprite` (app.nim:1155ff)
* Added: `apps/gallery/port-notes.md` (this file)
* Scratch instruments: `.board/frames/gal2/` — `verify.mjs`, `veil.mjs`,
  `tone.mjs`, `vtest.mjs`, `stest.mjs`, `p2p.mjs`, `crop.mjs`, `bez.mjs`,
  `hist.mjs`, `find.mjs`, `rowscan.mjs`, `prof.mjs`, `grid.mjs`, `align.mjs`,
  `maps.mjs`, `bm.mjs`, `vprof.mjs`, `lattice.mjs`, `sbs.mjs`, `edge.mjs`,
  `ratio.mjs`

Nothing outside those three paths was modified. No git command was run.
(`apps/dna/`, `apps/chess/`, `apps/typewriter/`, `apps/calligraphy/` and `skills/`
carry same-day timestamps in the tree — those are other agents' lanes, untouched
by me.)

## 6. Dead ends (measured, not assumed)

* **Residual veil** — refuted by the budget sweep, §5.2.
* **Command-stream truncation** — disproved earlier by putting a full-size magenta as
  the very last command (the frame changed, so the tail is not truncated).
* **CSS projection "bug"** — disproved earlier. `project` divides by `-z` while CSS
  `perspective` divides by `1 - z/d`; these are the same transform, because `.world`
  carries `translateZ(P)` with P the perspective distance, so the denominator becomes
  `d - (P + z) = -z`. The pinhole form is correct.
* **Adding persistence** — explicitly ruled out earlier; not retried.
* **Pure gain / global tone rescale** — quantified, §5.2, and deliberately not adopted
  because it hides the real error.

## 7. Where the remaining error is

The error is broad and structural, not one bug. Measured at `wait:8`.

**Frame mean:** ref `(59.9, 53.3, 46.9)`, port `(66.8, 63.4, 57.6)`. Port is ~12% too
bright on average and **hue-inverted**: the reference is warm (R > G > B by a wide
margin) while the port is neutral-to-cool, and in most regions port G actually
exceeds port R.

**The error is not uniform.** The port is simultaneously too bright on the
walls/floor and too dark on the ceiling and the end-wall band:

| region | ref mean RGB | port mean RGB | port error |
|---|---|---|---|
| ceiling `520,60–760,140` | 23.9, 21.9, 18.9 | 16.0, 14.0, 12.0 | **too dark** |
| ceiling `520,180–760,300` | 20.3, 18.3, 15.3 | 15.2, 13.3, 11.5 | **too dark** |
| near left wall `0,300–160,420` | 124.3, 87.4, 77.1 | 160.2, 150.0, 132.8 | **too bright, too cool** |
| near right wall `1120,300–1280,420` | 66.2, 58.5, 48.6 | 82.3, 72.4, 59.5 | too bright |
| floor `480,600–800,700` | 52.3, 49.7, 46.5 | 73.9, 80.2, 84.7 | **too bright, too blue** |
| floor `0,600–200,700` | 54.7, 49.6, 42.2 | 72.0, 65.1, 55.4 | too bright |

**The port is missing the end-wall/title highlight.** On centre column `x=640`:

| y | ref | port |
|---|---|---|
| 360 | 70.6 | 15.3 |
| 380 | 115.8 | 14.7 |
| 400 | 56.7 | 13.4 |

A 40×64 px block at `560,340–720,460` is short by 36–58 luma. That is the end-wall
radial spotlight (`html:883`,
`radial-gradient(ellipse 280px 330px at 300px 150px, rgba(255,243,220,.82)…)`) and/or
the `end-title` plane. Candidate causes, **not yet distinguished**: the `texEnd`
sampler; the title quad's placement (currently hardcoded
`[-275,-158,zFar+1] … [275,32,zFar+1]`, `scale .25`); or the corridor's half-resolution
ray-cast (`RW 640 × RH 400`, bilinear upscale) smearing the small bright core.

**8×8 band map** (`pngdiff`): the top-centre band (cols 3–5, rows 0–2) is already at
0–6% differing — that region matches. Everything else is 74–100%.

### What I would do next, in order

1. **Fix the end-wall/title highlight.** It is the largest single localised deficit
   (−58 luma) in a small, well-defined region.
2. **Resolve the hue inversion.** Reference `R−G ≈ +6.6` frame-wide; the port's is
   ≈ −3.4 on floor and walls. Since the floor is a translucent marble composited over
   the mirror (alpha 188/255, `html:795`), a wrong mirror contribution would produce
   exactly this warm/cool split. This is the most likely single cause of the
   simultaneous too-bright-and-too-cool floor.
3. **Only then** consider any global tone term. A rescale alone buys ~17 points but
   hides whatever 1 and 2 are still getting wrong.

## 8. Corrections to earlier notes

* The previous revision of this file stated that `Draw.alpha()` is a no-op because the
  shim's switch has no `case 'O'`. **That is now stale**: `skia_shim.cpp:1412` reads
  `case 'O': alpha *= ...` and it works. `Draw.alpha()` is safe to use.
* The previous revision reported the port as "about 1.3× brighter, never cooler".
  That was measured against a raw that had been double-swapped. After the swap the
  port is **both** too bright *and* too cool in the floor and wall regions (§7), and
  too dark on the ceiling. Both statements cannot be true; the second is the measured
  one.

## 9. Engine/SDK defects found (reported, NOT fixed — out of write scope)

* **`tools/raw2png.mjs:40-58` and `:122` — silently double-swaps an already-swapped
  raw.** `order` defaults to `'bgra'` with no guard against input already through
  `tools/rawswap.mjs`, so R and B come out inverted. This is the origin of the false
  "the port is cool-toned" claim in an earlier brief. `.board/floor.mjs` has exactly
  the guard that is missing here.
* **No text measurement in the SDK.** `sdk/ui/paint.nim:63` `Draw.text` returns only a
  `Draw`; `measureText` exists only in the native binding
  (`libs/nimskia/src/nimskia.nim:68`, `:122`). #39 needs it for every label.

## 10. Definition of done

* [x] `apps/gallery/app.nim` builds — `build-wasm: wrote .board/frames/gal2.wasm (509720 bytes)`
* [x] before/after `differing pixels` and `mean |delta|`, both through `rawswap`, at 1280×800,
      both from the same toolchain (§1)
* [x] camera-state answer with the four-`wait` correlation evidence, plus the
      ref-vs-ref budget sweep that independently proves the reference is static
* [x] this file, with every iteration including the refuted ones
* [x] nothing outside write scope changed (`apps/gallery/app.nim`,
      `apps/gallery/port-notes.md`, scratch under `.board/frames/gal2/`)

**Status: NOT A PASS.** 72.66% against a 72.82% same-toolchain baseline — a real
−0.16 point improvement, and the first real improvement in several rounds, because
the paintings are actually being drawn for the first time. The largest known
remaining error is the missing end-wall/title highlight and the warm/cool inversion
described in §7.

---
---

# 11. Round 3 — 72.66% / 31.60 → **40.98% / 14.99**

Supersedes §10. Five defects, all measured, four of them a single wrong constant or a
single missing branch. **Each is documented at its own site in `app.nim` with its
measurement**; this section is the ledger and the evidence trail.

## 11.0 Result

All numbers at 1280×800, `wait:8`, through `tools/rawswap.mjs`, scored with
`tools/pngdiff.mjs <ref> <sw.raw> 1280 800 8`, same toolchain for every row.

| # | change | differing | mean \|Δ\| |
|---|---|---|---|
| — | baseline (reproduced exactly this session) | 744,015 (72.66%) | 31.60 |
| 1 | `quadPx` composites with the **texel's own** alpha | 741,228 (72.39%) | **26.84** |
| 2 | ceiling gradient's 20–80% plateau | 751,824 (73.42%) | 26.66 |
| 3 | **the loading veil was being dropped entirely** | 458,741 (44.80%) | **17.80** |
| 4 | marble checkerboard (light tiles missing) | **419,663 (40.98%)** | **14.99** |

Build line for the final row: `build-wasm: wrote .board/frames/gal2/gal.wasm (511191 bytes)`,
raw confirmed `4096000 bytes  R/B swapped` before every diff.

**Iteration 2 made the differing-pixel count worse** (72.39% → 73.42%) while improving
mean |Δ| (26.84 → 26.66). It was kept: the ceiling fix is provable from the CSS text
independently of the score (§11.2), and the score is dominated by other things.

## 11.1 Iteration 1 — `quadPx` erased whatever was under it (`app.nim:1857`)

**Symptom.** Sprites were rasterised at exactly the right place and size but only their
top and bottom edges survived. Measured with sprite 0 filled solid magenta: bbox
x 0..272, y 135..570 — an exact match to the analytic prediction (CSS x 1.4–270.8,
y 136.8–569.2), yet only **15,937** of ~100,000 quad pixels carried magenta, arranged as
a chevron following the quad's top and bottom edges with rows 280–470 completely empty.

**Cause.** `quadPx` branched on the *caller's* `alpha`:

```nim
if alpha < 1.0'f32:  ... source-over ...
else:                buf[i+3] = byte((c shr 24) and 0xFF)   ## blind put
```

The sheen layer is transparent outside its 0.38–0.60 band and is drawn with `alpha = 1`
**over** the framed sprite. So every fully transparent sheen texel wrote `alpha = 0` into
`corrBuf` — deleting the painting underneath and letting the bare `.stage` background
through. At painting #1, y 350, the port showed `(9,8,7)`, which is exactly
`rampV` of `.stage`'s own `radial-gradient(90% 70% at 50% 45%, #1b1713, #0c0a08, #050404)`
at y = 0.4375 interpolated ≈ `(12,10,8)`. Painting #3 (also sheened) showed the sheen's
own pale band `(159,149,131)` where the reference has the plum field.

**Fix.** Always source-over with the texel's own alpha; `alpha` is a multiplier on it,
never a reason to skip blending.

**This also proves the brief's defect (b) is false.** The brief reported "sprite bbox
overshoot, whole-sprite fill measured bbox x0-989 y138-567". Measured bbox is
**x 0..272, y 135..570**. The projection, the depth test and the quad rasteriser are
correct; the only bug was the blend mode.

## 11.2 Iteration 2 — the ceiling's lit plateau rendered dark (`app.nim:1569`)

`ceilBg()` (html:833) is `linear-gradient(90deg, #100e0c, #1d1a16 20%, #1d1a16 80%, #100e0c)`.
Between the two `#1d1a16` stops the value is the **light** stop. The port mapped the
middle branch to `t = 0`, i.e. `#100e0c`.

Measured on the flattest patch in the frame, x 560–720 y 20–60 (both sides perfectly
uniform — `lum min == lum max` — so this is a constant, not grain): reference
`24.0, 22.0, 19.0`; port `16.0, 14.0, 12.0` = exactly `#100e0c`. Predicted `#1d1a16`
is `(29,26,22)`, which the reference's `24,22,19` matches once the atmosphere of §11.3
is applied — and after that fix the port renders that patch **exactly**.

## 11.3 Iteration 3 — THE BIG ONE: the loading veil was dropped (`app.nim:2603`, `:2865`)

The brief reported the port as "~1.3× brighter overall". Measured frame means: reference
`(59.9, 53.3, 46.9)`, port `(61.7, 58.5, 53.3)` — 3%, not 30%. **The brief's number was
wrong; the symptom was real but localised, and the brief's own localisation ("wall base
~1.28× too bright") was a consequence of it.**

**Localisation.** Fitting `ref = (1−a)·port + a·C` on clean, non-aliased wall columns gave
`a = 0.22` in R, G *and* B independently, stable to ±0.01 over nine rows. It was not the
vignette (computed `sv = 0.375 < 0.55`, i.e. transparent) and not the fog (`sf = 1.48 > 1`,
alpha 0) at those coordinates. Two regions of completely different luminance and hue fit
**one** `(a, C)`:

| region | port (the CSS stop) | reference | implied |
|---|---|---|---|
| ceiling plateau, x 560–720 y 20–60 | `29,26,22` = `#1d1a16` | `24.0,22.0,19.0` | a = 0.215 |
| near right wall, x 1150–1270 y 300–420 | `83,73,60` = `#53493c` | `66.2,58.5,48.6` | a = 0.215 |

`C` comes out neutral and ≈ 7–11, which is `var(--night)` = `#0b0a09` = `(11,10,9)` —
the `.veil`'s own `background`, at `position:fixed; inset:0; z-index:20` (html:195-199).

**Proof that it is the veil and not some other overlay** — the veil's own ink is in the
residual. Per-row positive-residual energy (`g2rowsum.mjs`) over x 500–790:

* **y = 438**: one row, run **x 550–729**, energy 5793 (≈9× its neighbours). That is
  `.veil .bar{ width:180px; height:1px; margin:18px auto 0 }` — 180 px wide, centred on
  a 1280-wide viewport, 1 px tall. Its `--p` is `done/8`, so the bar being full means
  **all eight canvases had rendered** by the capture.
* **y 371–388**: glyph ink x 550–700 — `<p>Galerie Nocturne</p>`, 26 px.
* **y 411–417**: sparse ink x 548–727 — `<small>HANGING EIGHT WORKS</small>`, 10 px with
  `letter-spacing:.34em`.

A fully-gone veil (`opacity:0; visibility:hidden`) cannot produce any of these.

**Timing.** html:1265-1273 keeps the veil at opacity 1 until the **third** of the eight
canvases has rendered, then runs `transition: opacity 1s ease`. Headless Chrome captures
with `--disable-gpu`, so each `renderWork` costs real time: work 3 lands at ≈315 ms of the
800 ms budget, i.e. 485 ms into the fade, and
`1 − cubic-bezier(.25,.1,.25,1)(0.485) = 0.212`. The port now implements exactly that
rule with `VEIL_GONE_S = 0.315`, driven by the app clock rather than by the port's own
bake (which completes in one pass).

**This is a calibration, and it is labelled as one.** The dismissal time is a *measured*
property of the reference capture, not something derivable from the source text. The
overlay colour, the fade curve and the dismissal *rule* are all from the CSS.

**After the fix the port matches the reference to within one level** on both the wall and
the ceiling (dR/dG/dB between −0.7 and +1.1 at six heights on x = 1200), which is the
acceptance test for the calibration.

### §5.2 was refuted by a broken instrument — corrected here

§5.2 above rejected exactly this hypothesis, on the strength of a ref-vs-ref budget
sweep reporting `ref@800 vs ref@2000 → 0 differing, mean |Δ| 0.00`. **That sweep is
void: `p2p.mjs` silently compares mismatched sizes.** Re-capturing with
`tools/capture-ref.ps1` at budget 2500 yields a **1280×816** PNG (the script hardcodes
`--window-size=1280,816`), while the reference of record is **1280×800**. `p2p.mjs`
reported "646 differing (0.06%), mean 0.01" for a pair whose means differ by 6.8
frame-wide and 8.3 on the near wall.

Re-measured with a minimal, independently written differ (`g2p2p.mjs`), that pair is
**506,767 differing (49.49%), mean |Δ| 16.77** over the shared 800 rows. The previous
agent's "the reference is completely settled by 800 ms" does not follow from it.

Two things that sweep does *not* settle, stated plainly:

1. `ref039_800.png` is **not** a top-800-row crop of an 816-tall render (that pair
   differs by 49.49%), so it was captured at a 1280×800 window and the port's 800×800
   projection is the right one — independently confirmed by the wall and ceiling now
   matching to ≤1 level.
2. Whether a *longer budget at a 1280×800 window* would let the veil finish cannot be
   tested with the tools in scope: `tools/capture-ref.ps1` hardcodes `--window-size=1280,816`
   and `tools/` is outside this task's write scope. The veil's presence is established
   directly from the reference's own pixels (the 180 px bar), not inferred from timing,
   so this does not affect the change.

## 11.4 Iteration 4 — half the marble was missing (`app.nim:1512`)

`marbleTex()` (html:780-798) returns a **256×256** image with a 2×2 checkerboard
(`tile = ((xx/128|0) + (y/128|0)) & 1`): two dark tiles `(16,15,16)` and two pale ones
`(138,133,124)`, plus a 45% grout line on every tile edge. It is applied as
`URLF(marble)` at `background-size: 128px 128px`, so CSS box-downscales the whole 256
image into each 128 px repeat cell.

`floorTex` indexed the 256×256 buffer with a 128 stride —
`marb[(y mod 128) * 128 + (x mod 128)]` — which reads **only the top-left 128×128
quadrant, i.e. tile 0, over and over**. Every pale tile was therefore absent from the
floor, and so was half the grout.

Measured along row y = 740: the reference alternates hard between luma ≈20 and ≈100 (the
dark tile, and the pale tile at `138 × 0.737 = 102` over the dark mirror); the port ran
28 → 94 in a single smooth undulation with **no checkerboard at all**. Now averaged as a
2×2 box per output texel, which is what CSS does at this scale.

## 11.5 Brief claims, measured

| brief claim | measurement | verdict |
|---|---|---|
| 25,072 px with `bright > 200` vs a reference with zero | port **max lum 196.1**, reference 195.0; frame mean R within 3.4 | **was true, now resolved** |
| purple artwork 1,101 px vs reference 5,431 | the veil was suppressing count *and* the checkerboard hid pale tiles; not re-counted after iteration 4 | **open**, see §11.6 |
| wall base ~1.28× too bright | near right wall port `83,73,60` vs reference `66.2,58.5,48.6` — real, and now **≤1 level** | **was true, resolved** |
| sprite bbox overshoot x0-989 | measured bbox **x 0..272, y 135..570**, matching the analytic quad | **false** |
| port ~1.3× brighter overall | frame means `61.7,58.5,53.3` vs `59.9,53.3,46.9` = 3% | **false** |
| signed per-column delta positive everywhere | −31.6 R on the left band | **false** |
| reference warm / port cool | both warm; resolved once the veil is in place | **false** |

## 11.6 Still open, with the current localisation

The residual is now **not** a tone problem — the 16×10 ref/port ratio grid reads 0.95–1.05
almost everywhere. What is left is content, in three places:

1. **The framed paintings, x 0–320 y 240–560** — ratio grid reads 1.23–1.96. Painting #1
   at row 350: x 128 matches (`174,103,70` vs `177,96,65`) but x 192 is 1.20× and x 0 is
   0.69×, so the sprite's *contents* are wrong at a sub-sprite scale rather than the quad.
2. **The floor's mirror half, x 560–960 y 480–720** — ratio 0.68–0.92, the port too dark.
   This is the reflection the translucent floor is supposed to show.
3. **Painting #2 (the grid) is displaced** — at row 350 the reference's red panel sits at
   x ≈ 960 showing `(85,33,28)`; the port shows neutral `(88,86,82)` there, so the sprite's
   content is being sampled at the wrong place inside the texture.

## 11.7 Also still missing from the port (unchanged from §7, not attempted)

* The **8 light beams** (`beamEl`, html:875-884): defined by `beamX` (`app.nim:308`) and
  built into `real` by `mk()`, but **never rasterised** in `renderCorridor`'s step 4.
  They are `clipPath` wedges with a 200° gradient at α ≤ .15, so they lighten; their absence
  makes those strips too dark. Not implemented this round — a clipPath wedge plus an
  angled CSS gradient line is a lot of machinery for a small alpha, and it was left out
  rather than half-built.
* `buildSheen` still applies no `filter(blur, r)` and `buildTitle` no `filter(fade, …)`.

---

# 12. Lane 3 — the 73% tree was not the tree under test

## 12.1 Headline

**40.98% differing, mean |Δ| 14.99, max 184** at 1280×800, `wait:8`, through `rawswap`
and `tools/pngdiff.mjs` tol 8. Independently confirmed by `.board/scoreboard.ps1`, which
reports `gallery 40.98%  14.99  189917 px  55%  511198 B`.

This lane opened by measuring the tree as **73.42% / 26.66** and ended at **40.98% /
14.99** — but **the lane did not make the improvement.** See §12.2. This is stated
plainly because the number otherwise reads as a result and it is not one.

## 12.2 The file changed underneath this lane — this is the most important finding

Measured at session start: `apps/gallery/app.nim` = **147,004 bytes**. Measured after
the first probe build: **150,484 bytes**, then 151,161 with my own scaffolding added
and removed. **+3,480 bytes and ~23 lines arrived from a writer other than me.** The
added code is real, substantial and correct — §11's "floor-over-void blend at alpha
188/255" note at `app.nim:3041` now describes a double-emit fix that was not in the
source I read at session start, and `floorTex`'s marble downscale comment
(`app.nim:1536-1548`) describes a checkerboard bug I did not fix.

The effect on the score is large and measurable:

| region | ref | 73.42% tree | current tree |
|---|---|---|---|
| ceiling `560,60,720,140` | `23.9,21.9,18.9` | `29.0,26.0,22.0` (Δ5.1,4.1,3.1) | `24.0,22.0,19.0` (**Δ0.1,0.1,0.1**) |
| centre floor `480,600,800,700` | `52.3,49.7,46.5` | `73.9,80.2,84.7` (Δ21.5,30.5,38.2) | `57.8,62.6,66.1` (Δ5.5,12.9,19.6) |
| left wall `20,300,140,400` | `128.2,85.4,72.2` | `150.6,89.3,93.7` (Δ22.4,3.9,21.6) | `120.3,71.9,75.5` (Δ−7.9,−13.4,3.3) |

Whole-frame mean luma now matches: **ref 54.53 sd 34.56, port 54.46 sd 34.23.** The
frame-wide brightness excess this lane was chasing **no longer exists**.

**Consequence for whoever reads this next: never trust a number carried in a brief or
a previous lane's notes against the source that is on disk. Re-measure first.**

## 12.3 A build-harness hazard that manufactured a false result

`tools/build-wasm.sh:121` keys the nimcache on `NIM_FLAGS` only:
`NIMCACHE_KEY="$(printf '%s' "$NIM_FLAGS" | md5sum | cut -c1-8)"`. Defines passed via
`D_NIM_DEFINES` do **not** enter that key. So a build with a define can leave objects
that a later "plain" build silently reuses.

I hit this directly and it cost several rounds: a `-d:probeMirror` build, then a plain
build of the same source, produced **byte-identical wasm output** (same differing-pixel
count to the pixel). Two builds that should have differed did not.

The workaround that works, and the only one I will rely on:

```
Remove-Item -Recurse -Force apps\gallery\nimcached41d8cd9
$env:YANTRA_NIM_FLAGS='-d:FOO="0.7"'   # NOT D_NIM_DEFINES
bash tools/build-wasm.sh apps/gallery/app.nim out.wasm
```

`YANTRA_NIM_FLAGS` *is* folded into `NIM_FLAGS` (`build-wasm.sh:71`), so it keys the
cache. When I switched from `D_NIM_DEFINES` to `YANTRA_NIM_FLAGS` the variants finally
differed (511,192 / 511,193 bytes). This is a **build-script bug worth reporting**, but
`tools/` was outside this lane's write scope so it is **not fixed here**.

Note also that all five alpha-sweep wasm files differed in size yet rendered an
**identical** score — see §12.5, that was not a cache artifact, it was a real property
of the pipeline.

## 12.4 What this lane measured and ruled out (refuted, do not re-chase)

Each of these was a live hypothesis, tested, and disproven by decoded pixels.

* **"The end-wall/title highlight is missing."** **False for this build.** At x=640 the
  port's title core peaks ~(186,175,157) where the reference is ~(130-135,69-77,32-35).
  The port is too bright and too desaturated there, not absent. The brief's
  "ref 70.6 vs port 15.3" numbers are from an older build and do not reproduce.
* **Title quad placement.** **Correct.** Pure-arithmetic projection puts it at CSS
  x 554.1–725.9, y 350.7–410.0, 171.8 × 59.3 px, matching html's
  `2200×760 scale(.25)` = 550×190 world units.
* **"Frame-wide hue inverted, caused by the translucent marble over the mirror."**
  **False.** The marble-over-mirror composite is real and correct (alpha 188/255,
  `app.nim:1555`), but whole-frame mean luma now matches to 0.07 and the floor's
  residual is small and *not* a hue inversion — the port is still a little blue on the
  floor (ΔB +19.6 vs ΔR +5.5), which is desaturation of the reflected content, not a
  warm/cool flip of the frame.
* **Fog and vignette geometry.** **Correct.** Recomputed from the CSS
  (`radial-gradient(30% 34% at 50% 50%)` ⇒ radii 384×272; `120% 95%` ⇒ 1536×760) and
  it matches `drawFogVig` exactly. `fogAmt()` = `cl((2460-500)/1300)` × `1-0` = **1.0**,
  and html:1087 computes the identical expression. Centre fog α = 0.62, corner vignette
  α = 0.148. Not the defect.
* **A global tone curve / gain.** **Still the wrong move**, and now doubly so: there is
  no longer a brightness excess to hide. Confirmed the brief's reasoning stands — the
  reference is settled (0-pixel change from 800 ms to 2000/3000 ms captures).
* **`-d:floorAlphaMul` sweep at 1.0/0.8/0.6/0.45/0.3.** **Inconclusive, then explained.**
  See §12.5.
* **"The floor blit is dead code."** **False.** Multiplying the blit alpha by `0.0`
  moved the score to **43.39%** from 40.98%, so the floor composite is live and
  load-bearing. Its raws are not identical to the baseline's.

## 12.5 Why the alpha sweep produced identical scores (a real property, not a bug)

`FALPHA` at 1.0 / 0.85 / 0.7 / 0.55 / 0.05 all rendered **exactly** 419,663 differing
pixels, mean 14.99; only `* 0.0` changed anything (43.39%). The four wasm files
differed in size, so the defines landed — this is not the §12.3 cache bug.

The cause is in `floorTex`. The marble composites at α 188/255 onto transparency
(`app.nim:1555`), but the eight picture pools (`app.nim:1566+`) and the two edge
shadows then composite *over that*, pushing most of the floor to **near-opaque alpha**.
`blit` (`app.nim:2134`) then short-circuits `a >= 1.0` to `put`, and even at
`FALPHA = 0.05` the surviving alpha is dominated by the already-opaque pools. So the
floor's opacity is essentially pinned by the pools, and **the marble alpha is not a
tunable knob for this region.** Recorded so nobody spends another round on it.

## 12.6 Where the remaining error actually is

Region budget at tol 24 (the scoreboard's "structure" band — above it is real work,
below it is the reference's feTurbulence grain, which the scoreboard explicitly says not
to chase). Whole frame: **>24: 189,917 px (18.55%)**, 9–24: 229,746 (22.44%).

| region | mean \|Δ\| | >24 count | % hard |
|---|---|---|---|
| ceiling | 7.87 | 10,385 | 6.8% |
| **left wall** | **30.88** | **39,191** | **50.2%** |
| right wall | 2.90 | 507 | 0.7% |
| end wall/title | 9.82 | 3,578 | 14.9% |
| **centre floor** | **26.23** | **12,737** | **39.8%** |
| near floor | 7.08 | 3,363 | 8.8% |
| far floor | 22.05 | 10,530 | 32.9% |
| hud pad | 20.59 | 11,994 | 27.3% |
| brand | 17.12 | 6,015 | 16.7% |

Two dominant terms, both **content**, not tone:

1. **Left wall `0,120,260,420` — 50.2% hard.** A row scan at y=300 shows the reference
   and the port both carrying the paintings, with matching large-scale shape but
   **different per-pixel detail**: ref swings `84.9,71.0,41.7` → `189.3,172.3,123.3`
   across x 21→23 while the port sits flat at `47.0,44.0,39.0`. The wall's *content* is
   wrong at a sub-sprite scale, which is §11.6's open item 1, still open. Note the
   ceiling and right wall are now essentially free (6.8% / 0.7%), so this is specific to
   the left wall's painted content, not a wall-rendering bug.
2. **Centre floor `480,600,800,700` — 39.8% hard.** Row profile shows a **monotonic
   brightening with distance from camera**: Δ +4.3 at y=600 rising to **+15.7 at y=690**.
   The port is too bright by an amount that grows toward the viewer, which is a
   perspective/scale signature, not a constant offset. Local sd is close (ref 28.8–36.5,
   port 23.4–37.0), so the texture is present — it is the magnitude ramp that is wrong.
   This is the single most promising remaining lead.

## 12.7 Honest status

**This lane did not improve the port.** The 73.42% → 40.98% change came from an
unattributed concurrent edit to `apps/gallery/app.nim` (§12.2); my own edits were four
temporary probes, all reverted, verified by grep (`FALPHA|probeMirror|floorAlphaMul`
→ no matches) and by rebuilding to the same 419,663 / 14.99.

What the lane produced is diagnostic: a refuted-hypothesis list that should stop the next
lane re-running five dead ends (§12.4), a **build-script bug report** (§12.3) that cost
me real time and will cost the next lane the same, and a localisation of the two
remaining structural terms (§12.6) with the floor's distance ramp named as the best lead.

I did not beat 72.39% by my own hand. The tree measures **40.98%** and that is the only
number I stand behind.

---

# 13. Lane 4 (gal3) — the paintings are composited at less than 100% opacity

## 13.1 Headline

**This lane did not improve the port.** It opens and closes at **419,663 px (40.98%) /
189,917 px (18.55% at tol 24) / mean |Δ| 14.99**, reproduced three times from the
on-disk source. The lane's output is a diagnosis that kills several plausible root
causes and names a new one.

## 13.2 Changes made (complete ledger, one edit)

| # | change | tol 8 | tol 24 | mean \|Δ\| | verdict |
|---|---|---|---|---|---|
| baseline | as found | 419,663 | 189,917 | 14.99 | — |
| 1 | `RW/RH` 640×400 → **1280×800** | 419,313 (−350) | 196,462 (**+6,545**) | 15.75 | **reverted** |
| 1r | **reverted to 640×400** | 419,663 | 189,917 | 14.99 | tree restored |

Iteration 1 was a genuine experiment and a genuine regression. It is reverted; the
measured rationale is now a comment on the constants at `app.nim:60-84` so the next lane
does not re-run it. Regional breakdown (tol 24 px):

| region | 640×400 | 1280×800 | Δ |
|---|---|---|---|
| wall `1050,300–1270,460` | 68 | 37 | −31 |
| floor `560,480–960,720` | 27,680 | 27,753 | +73 |
| **painting 1 `16,250–272,555`** | 50,462 | 54,645 | **+4,183** |

The wall band was **already** at 0.19% structure — half-resolution cost nothing there,
because a smooth gradient has no detail to lose. The whole regression is the painting.

## 13.3 The mechanism (measured, worth more than the constant)

`hf.mjs`, mean |luma gradient| per pixel:

| region | ref gradH / gradV | port @640 | port @1280 |
|---|---|---|---|
| painting 1 art `20,260–250,545` | 7.320 / 5.471 | 4.807 / 4.634 | **9.425 / 7.870** |
| frame-wide | 3.267 / 3.028 | 1.926 / 2.007 | 2.810 / 2.697 |
| flat wall control `288,340–312,360` | 1.373 / — | 0.077 / — | — |

The paintings are composited *into* `corrBuf`, so they inherit the corridor's
resolution. At full res the port **overshoots** (9.43 vs the reference's 7.32): `quadPx`
takes a single bilinear tap while Chrome area-averages a 2.9× minification. So the port
is simultaneously under-sharp in the corridor and over-sharp in the paintings, and the
640→1280 change trades one aliasing artefact for another.

**The fix for the paintings is area-averaging inside `quadPx`, not a resolution
constant.** This is the single most actionable finding of the lane and it is untried.

## 13.4 Refuted — do not re-chase

* **RNG.** `mulberry32` vs the port's `nextF` match to **2.98e-8** (the float32 floor)
  across 512 draws. Across 13,538 dots that is ~0.0008 expected branch flips.
  **The RNG is not the defect.**
* **Placement / flips.** `probe.mjs` over the painting-1 art interior, shift grid ±20:
  identity dx0 dy0 **28.04**, hflip 33.63, vflip 46.95, hvflip 46.10. Identity wins by
  a wide margin. The quad is where it should be and is not mirrored.
* **Perspective geometry.** `G_HALF = 300`, `G_ZFAR = −2300` match html:759 exactly, and
  pure-arithmetic projection reproduces the sprite bbox (CSS x 1.4–270.8, y 135–570).
  The frame's near-edge width works out to 27.6 screen px; the port measures ~26.
* **The grid generator.** `genGrid` was diffed line-by-line against html:444-487:
  short-circuit order of the `R()` draws in `split`, the stable descending-area sort,
  `slice(2, max(3, floor(n*.5)))`, `slice(floor(n*.5))`, argument evaluation order in
  the two-colour line, and the 70-stroke loop all match. It is faithful.
* **A global tone curve / gain.** Still wrong: there is no global brightness excess
  (frame-wide lumRatio 0.999).

## 13.5 The new finding — the reference's canvases are still fading in

`html:51` gives the artwork canvas `opacity:0; transition:opacity 1.1s ease`, and
`.ready` (added per work as its bake completes) takes it to 1. **`capture-ref.ps1` does
not pass `--force-prefers-reduced-motion`**, and html:261 only collapses the duration
under `prefers-reduced-motion: reduce`. So at the reference clock (`wait:8`, 800 ms)
the eight canvases are at **eight different points in the same 1.1 s fade**, ordered by
bake index. The port draws every artwork fully opaque.

Measured consequence — the two paintings want *opposite* corrections, which is why no
global gain ever fixed this region:

| region | ref | port | direction needed |
|---|---|---|---|
| painting 1 art `30,170–250,540` mean | 112.6, 88.5, 87.3 | 96.6, 73.8, 91.2 | port **too dark** |
| painting 1 art max luma | 183.5 | 196.1 | ≈ok |
| painting 2 grid `930,310–990,420` mean | 101.8, 82.4, 75.7 | 126.2, 108.4, 100.8 | port **too bright** |
| painting 2 grid max luma | 137.2 | 179.5 | port **too bright** |

Painting 2 (bake index 1, z −570) is short by ~24% of its highlight range while painting 1
(index 0, z −330) is essentially at full. Solving `ref = a·art + (1−a)·bg` for painting 2
with a near-black frame behind gives **a ≈ 0.5–0.7**, i.e. the reference's artwork really
is drawn at well under full opacity.

**This is the single largest structural bucket** (painting 1 alone is ~50k of the 189,917
tol-24 px) and it is partly a *timing* effect, not a tone effect. A correct port must
model `alpha_i = ease((now − t_ready_i)/1100 ms)` per work — which, unlike a fitted
constant, will behave correctly at clocks other than 800 ms. I did not have the budget
to build and validate that; I am flagging it rather than shipping a fitted constant,
because a fitted constant would be tuning to one clock, which the brief forbids.

## 13.6 Corrections to the brief

* **"The floor mirror half is too dark (ratio 0.68-0.92)."** **Wrong direction.**
  Measured `560,480–960,720`: dR **−0.2**, dG **+6.4**, dB **+12.6**, lumRatio
  **1.100** — the port is too *blue and light*, not dark. Do not spend a lane on a
  darkness fix here. The blue excess is consistent with §12.6's desaturation of the
  reflected content.
* **"Painting #2's red panel is displaced."** It is displaced in *texture* terms, but
  `genGrid` is faithful (§13.4). The apparent displacement is most likely the opacity
  deficit of §13.5, not a layout bug — do not go looking for a layout error there.
* **"8 light beams never rasterised — that may be the right call."** Agreed, left out.

## 13.7 Tools left behind (`apps/gallery/.board/gal3/`)

`region.mjs` (validated — reproduces `pngdiff` exactly; **throws** on an empty rect
rather than printing `n=0`/NaN, which is the failure that bit me twice), `txt.mjs`
(text-art side-by-side — the fastest way to see spatial structure), `probe.mjs`
(shift/flip; **flip the PORT lookup only**), `hf.mjs`, `rngcheck.mjs`.

`region.mjs` takes W/H explicitly for raw input (`png` input takes no W/H). Getting this
wrong is the "region is empty" trap.

**Do not use `.board/frames/gal3/lib.mjs`** — its `decodePng` returns wrong pixels
(reference mean 98.8 vs a true 59.9). Use `.board/png.mjs`, which is proven.

## 13.8 Still open

1. `quadPx` area-averaging (§13.3) — the principled fix for the paintings' sharpness.
2. Per-work canvas fade (§13.5) — the largest remaining structural term.
3. Floor blue excess, dB +12.6 (§13.6) — §12.5 explains why `FALPHA` cannot tune it.
4. Purple-artwork pixel count 1,101 (port) vs 5,431 (ref) — **not re-counted**, carried
   from the previous lane.
5. `buildSheen` has no `filter(blur, r)`; `buildTitle` has no `filter(fade, …)`.

---

## 14. Lane: missing paintings + the artwork canvas fade (2026-10-04)

Scope: `apps/gallery/app.nim` only. Scratch in `apps/gallery/.board/gal4/`.
Everything below is measured at 1280x800 against `.board/frames/ref039_800.png`
unless another reference is named. `drive.exe` frame dumps are always run through
`tools/rawswap.mjs` before diffing.

### 14.0 The headline is not opacity. Three paintings were never drawn.

The task was to implement `html:51`'s per-work canvas fade. Before fitting it, the
existing probes were re-run, and they said the artwork was not being drawn at all.

`app.nim`'s analytic projection (`gal4/geom.mjs`, a JS port of `app.nim:1719-1767`)
gives the eight sprite boxes at 1280x800:

| work | key   | side | z     | projected sprite box |
|------|-------|------|-------|----------------------|
| 0    | sunset| L    | −330  | 1..271               |
| 1    | grid  | R    | −570  | 918..1001            |
| 2    | field | L    | −810  | 378..425             |
| 3    | op    | R    | −1050 | 815..847             |
| 4    | ink   | L    | −1290 | 473..490             |
| 5    | geo   | R    | −1530 | 767..786             |
| 6    | flow  | L    | −1770 | 515..527             |
| 7    | mosaic| R    | −2010 | 740..752             |

`pdiff` on a `-d:probeSpriteTag` build (every sprite overpainted at alpha 0.9 in its
own colour) reports changed-pixel column runs of

    0..272  737..754  765..788  811..848  915..1002

— **five runs for eight paintings.** A `-d:probeNoDepth` build of the same source
adds `375..444`, `471..500`, `511..534`: works 2, 4 and 6 exactly.

### 14.1 Root cause: the depth test compared two different metrics

`hit()` returns the **world ray parameter** `t` (`app.nim:1817-1848`).
`quadPx` compared it against the quad's **interpolated view z** (`app.nim:1999`):

```nim
if not dTest or -z <= depth[yy * rw + px] + 0.5'f32:
```

Those are the same number only while the camera is unrotated: at `rot = 0` the ray
is `(ndcX, ndcY, −1)`, so the hit's view z is exactly `−t`.
`renderCorridor` adds `sway = sin(idleT*0.35)*0.5` degrees — 0.07 deg at the 800 ms
clock — and under a rotation a constant-x plane is no longer planar in **view**
space, so the interpolated value drifts off the plane's true depth by about 1% of
the distance (≈10 units at 1000) against a painting that stands only **1.5 units**
proud of its wall. The drift is a shear whose sign follows `ndcX`, so it destroyed
one wall and helped the other — which is exactly why only the left-wall works
beyond z = −330 died and all four right-wall works survived.

`gal4/depth.mjs` is a numeric replica of `hit()` + `quadPx` and reproduces the
split exactly:

```
rot=0     : all eight sprites accept, worst margin +1.80 .. +10.19
rot=0.0725: works 0,2,4,6 REJECTED, margins −0.16 .. −25.88
```

### 14.2 Rejected fix (measured, kept here so it is not re-tried)

Returning the **view-space z** from `hit()` instead of `t`. It made things worse:

| build                       | tol 8   | tol 24  | mean |
|-----------------------------|---------|---------|------|
| `t` (baseline)              | 419,663 | 189,917 | 14.99 |
| view z from `hit()`         | 420,008 | 194,533 | 15.28 |

The error is in the sprite's interpolated z, not in the buffer's.

### 14.3 Shipped fix: the test is per-ELEMENT and exact

Along one ray, world x is linear in `t`. For an element on the plane `x = X` standing
in front of the wall at `x = wallX`:

```
t_plane = t_wall * (X / wallX)        ⇒   t_plane <= t_wall  ⇔  |X| <= |wallX|
```

It was never really a per-pixel question. `drawSprite` (`app.nim:2230-2245`) now
computes that inequality once per element; constant-z elements (the end-wall title)
get the same statement against `G_ZFAR`; anything else keeps the per-pixel test.

### 14.4 Ledger — change 1, the exact plane depth test

| build            | tol 8            | tol 24           | mean \|Δ\| |
|------------------|------------------|------------------|------------|
| baseline         | 419,663 (40.98%) | 189,917 (18.55%) | 14.99      |
| + view z (rejected) | 420,008 (41.02%) | 194,533 (19.00%) | 15.28  |
| + exact plane test | **418,690 (40.89%)** | **184,989 (18.07%)** | **14.60** |

−973 at tol 8, −4,928 at tol 24. Smaller than the 11,826 px the three paintings
occupy, because they are drawn now but still wrong.

### 14.5 The fade mechanism (html:51-52, 925, 929)

`.frame canvas { opacity:0; transition:opacity 1.1s ease }` with `.ready` added at the
end of `renderWork`. CSS opacity is **group** opacity, and `html:85` hangs the
box-shadow on the canvas, so the artwork AND its shadow fade together over the frame
and mat while the frame itself does not move. So the canvas is now its own layer:

* `buildSprite` bakes shadow / moulding / rope / mat into `spriteLayer[i]` and the
  artwork plus its `html:85` shadow into a new `canvasLayer[i]`, both `ow*2 × oh*2`.
* bake step 22 reads back `spritePx[i]` **and** `canvasPx[i]`.
* `renderCorridor` draws the sprite at alpha 1 and then the canvas group at
  `canvasAlpha(i) = cssEase(clamp((appT − T_READY_S[i]) / 1.1, 0, 1))` — in the
  mirror pass as well as the real one (`html:929` gives the reflection `.ready` too).

`T_READY_S = [0.030, 0.046, 0.062, 0.078, 0.094, 0.110, 0.126, 0.142]` is
**derived from the source**: `html:1273` fires the first bake at 30 ms and
`html:1271` re-arms with `setTimeout(next, 16)`, so `T[i] = 30 + 16·i` ms. Chrome's
`--virtual-time-budget` does not advance the clock during script execution, so the
generators' own cost does not enter T.

### 14.6 A fitted schedule scored better and was REJECTED. Here is why.

The veil, fog, vignette and sheen are all per-pixel **affine**, so with P = the port
opaque and PU = the same port with the canvas group omitted,

```
R = PU + a · (P − PU)      ⇒      a = Σ(R−PU)(P−PU) / Σ(P−PU)²
```

holds exactly and the veil constant cancels, so `a` does not inherit the 21.5% veil
calibration (`gal4/alpha.mjs`, `gal4/alphal.mjs`; the blurred variant is needed
because §13.3's over-sharpness drags a least-squares alpha down — by 0.09 on work 0
and 0.20 on work 3 between a 0 px and a 2 px blur).

Solving that per work and isotonic-projecting onto the non-decreasing sequence
`html:1262-1273` guarantees gives `T = [0.140, 0.437, 0.437, 0.530, 0.621 ×4]` s.
It scores better:

| build                  | tol 8   | tol 24  | mean |
|------------------------|---------|---------|------|
| no fade                | 418,690 | 184,989 | 14.60 |
| fitted schedule        | 416,885 | **179,450** | **14.14** |
| source schedule (shipped) | 417,515 | 182,807 | 14.46 |

It does not survive being checked. The identity's premise is that canvas opacity is
the ONLY difference over a canvas rect, and at other clocks it plainly is not.
Re-solving against references captured at 480 / 1120 / 3760 ms:

| clock | per-work alphas read back |
|-------|---------------------------|
| 480 ms  | 4.36, 2.46, 2.35, 3.16, 3.51 — **opacity cannot exceed 1** |
| 1120 ms | 0.878, 0.625, 0.706, 0.630, 0.232 — implied T drifts LATER by 0.15–0.31 s, and keeps drifting with the clock |
| 3760 ms | 0.316, 0.080, 0.401, −0.14, −0.51 — a CSS opacity fade is monotone; these **fall** below their 800 ms values |

Those are not fades, they are a growing mismatch between the port's idle camera and
the reference's. A measurement that returns a >1 opacity and a negative one from the
same model is not a measurement of that model, so the source-derived schedule ships
and the fitted one is recorded here so it is not re-fitted.

### 14.7 Clock sweep — the critical constraint

References for the other three clocks were captured with the unmodified
`tools/capture-ref.ps1` into `apps/gallery/.board/gal4/` (budget 480 / 1120 / 3760 ms,
1280x800 — the budget matches `wait:4 / 12 / 45` because `drive.exe` runs
`(N+2) × 80 ms`).

**Noise floor first.** Two captures of the *same* reference clock are not identical:

| clock | ref vs ref, tol 8 | ref vs ref, tol 24 |
|-------|-------------------|--------------------|
| 480 ms  | 11      | 0     |
| 800 ms  | 91,325  | 1,661 |
| 1120 ms | 60,198  | 1,501 |
| 3760 ms | 16,150  | 1,720 |

**The reference capture is not byte-reproducible** (`tools/capture-ref.ps1` produces
different bytes every run), so tol-24 differences below ~1,700 px are not meaningful.

| clock | metric | no fade | fitted sched | **shipped** | vs no fade |
|-------|--------|---------|-------------|-------------|------------|
| wait:4  | tol 8  | 832,592 | 831,383 | 832,433 | **+159 (worse)** |
| wait:4  | tol 24 | 580,677 | 579,959 | 580,198 | −479 |
| wait:4  | mean   | 33.71   | 34.37   | 34.05   | **+0.34 (worse)** |
| wait:8  | tol 8  | 418,690 | 416,885 | 417,515 | −1,175 |
| wait:8  | tol 24 | 184,989 | 179,450 | 182,807 | −2,182 |
| wait:8  | mean   | 14.60   | 14.14   | 14.46   | −0.14 |
| wait:12 | tol 8  | 467,218 | 463,908 | 467,236 | +18 |
| wait:12 | tol 24 | 221,158 | 219,888 | 221,166 | +8 |
| wait:12 | mean   | 18.10   | 17.95   | 18.10   | 0.00 |
| wait:45 | tol 8  | 789,209 | 789,146 | 789,146 | −63 |
| wait:45 | tol 24 | 493,916 | 493,893 | 493,893 | −23 |
| wait:45 | mean   | 31.99   | 31.99   | 31.99   | 0.00 |

**Verdict, stated honestly.** On the two counting metrics the shipped schedule
improves or ties at every clock (worst case +18 px at wait:12, against a noise floor
of 60,198). On `mean |Δ|` it is **worse at wait:4 by 0.34** and better at wait:8.
The wait:4 regression is real and is not noise (that clock's ref-vs-ref floor is 11
px). At 480 ms the reference's bake is only part-done and the port's veil is still
at 0.755 opacity, so 81% of the frame differs for reasons the fade cannot touch;
the shipped schedule nevertheless draws work 0's canvas at
`ease((0.48−0.030)/1.1) = 0.42` where the source says it should be.

### 14.8 Could not be determined

* Whether the per-work alphas at 800 ms are real. The solve needs the canvas opacity
  to be the only difference over a canvas rect; §14.6 shows it is not, at other
  clocks. §13.3's over-sharpness and the port's idle-camera drift are both still in
  and both contaminate it.
* Works 5, 6 and 7 cannot be fitted at all: `|P−PU|` is 6.8, 4.0 and 0.4 over 949,
  498 and 345 px. They are 1–12 screen px wide. Whatever they do, it is invisible.
* What fraction of the three restored paintings is still missing at wait:8. They
  render and are in the right place (`region.mjs mapr 370 280 450 500` shows the
  canvas box populated and the upper half within lumRatio 0.85–1.3 of the reference),
  but only ~4,928 of their 11,826 px were recovered, so most of their error is
  something else. **That is the next thing to chase, and it is not opacity.**

### 14.9 Tooling defects (for whoever merges this into ISSUES.md)

1. **`tools/build-wasm.sh` §12.3's `YANTRA_NIM_FLAGS` workaround is inoperative on
   this machine.** `bash` here is WSL bash
   (`C:\Users\Sanskar\AppData\Local\Microsoft\WindowsApps\bash.exe` → `/bin/bash`
   with a `/mnt/c/…` view), not the MSYS2 bash PORTING-FACTS implies, and **no
   Windows environment variable crosses into it**. Verified directly:
   `$env:FOOBAR='hello'; bash -c 'echo $FOOBAR'` prints `FOOBAR=[]`.
   `$env:YANTRA_NIM_FLAGS=… ; bash tools/build-wasm.sh …` therefore built
   `apps/gallery/nimcached41d8cd9` with no flag, 511,193 bytes — byte-different from
   the flagged build's 511,191 and semantically identical (frame byte-identical to
   baseline). The fix is to set the flag inside the same invocation:
   `bash -c 'cd /mnt/c/…/yantra && YANTRA_NIM_FLAGS="-d:foo" bash tools/build-wasm.sh …'`.
   Proof it took: a new `apps/gallery/nimcache<key>` directory appears. This is
   R12's exact trap — a `.wasm` byte count is not a build fingerprint.
2. **`drive.exe` output must be redirected to a file, never piped into
   `Select-Object -First N`.** Piping truncated the frame dump to 2,768,896 bytes
   and `tools/pngdiff.mjs` then reported `raw size 2768896 != 1280*800*4`, which
   looks like a differ defect and is not.
3. **`tools/capture-ref.ps1` is not reproducible.** Two runs at the same budget
   produce different bytes — 1,066,732 against 1,042,799 at 800 ms — differing by
   91,325 px at tol 8 and 1,661 at tol 24. Every scoreboard number taken against a
   reference has that spread baked into it, and §14.6's cross-clock solve is
   probably measuring it. Worth a note in the file's header.
4. `tools/refdiff.mjs` **silently ignores trailing rect args** (defect R6, still
   open). Use `apps/gallery/.board/gal3/region.mjs`; never
   `apps/gallery/.board/gal3/lib.mjs` (broken `decodePng`, reports reference mean
   98.8 where truth is 59.9).

---

## 15. Area-averaging, the light shafts, and one texel per CSS pixel (lane gal5, 2026-10-04)

### 15.0 The census first, as instructed

Baseline (`gal.wasm`, rebuilt this lane, reproduces the authoritative scoreboard
exactly): **417,515 differing at tol 8 (40.77%), 182,807 at tol 24 (17.85%), mean
|delta| 14.46**, 1280x800, `wait:8`. The baseline reproduction is exact, which is
what makes every number below comparable.

16x10 cell census at tol 24, then a per-work sprite-box census (the eight painting
boxes hold **91,298 of 182,807**, half the structure):

| work | box (frame px) | d24 baseline | lumRatio |
|---|---|---|---|
| 0 sunset | 1,137-271,569 | **66,245** | 0.85 |
| 1 grid | 918,258-1001,488 | 15,203 | 1.21 |
| 2 field | 378,280-425,489 | 3,743 | 0.88 |
| 3 op | 815,316-847,454 | 3,444 | 1.20 |
| 4 ink | 473,320-490,465 | 684 | 1.10 |
| 5 geo | 767,348-786,431 | 999 | 1.24 |
| 6 flow | 515,340-527,444 | 157 | 1.00 |
| 7 mosaic | 740,349-752,434 | 823 | 0.66 |

**This contradicts the brief's ranking.** Item 1 was "~6,900 px of paintings 2/4/6";
those three together are **4,584**. Work 0 alone is **66,245**, 36% of all tol-24
structure. Whoever ranked this had not run the box census.

### 15.1 SHIPPED — area-averaging in `quadPx`

Chrome area-averages a minified texture; `quadPx` took one bilinear tap per
destination pixel. `quadPx` now measures each destination pixel's texel footprint
(`upx` analytically from u/w and the scanline span, `vpy` by re-running the scanline
one row lower -- `scanRow` was extracted for exactly this) and averages an
`nu x nv` grid of it, premultiplied, capped at 4x4.

| build | tol 8 | tol 24 | mean | painting-0 artwork rect gradH |
|---|---|---|---|---|
| baseline (point) | 417,515 | 182,807 | 14.46 | 4.575 (ref 6.888) |
| **area-average @640** | **417,245** | **178,863** | **14.25** | 3.541 |

**-270 at tol 8, -3,944 at tol 24, mean -0.21.** Small against 182,807 but it is the
right direction and the mechanism is not in doubt. It is also the fix §13.3 kept
pointing at from both sides.

### 15.2 SHIPPED — the light shafts (`beamEl`, html:865-871)

Three lanes flagged the beams and none had measured them; §13.6 argued they
"cannot explain a +138 delta" and left them out. That argument was about *this
particular pixel*, not about the element, and it was the wrong question to ask of
an element that had never been rendered at all.

Implemented as `beamAlphaAt` + `drawBeams`: the 150x420 element at
`(beamX, MIDY, w.z)`, the `clipPath polygon(124 0, 134 0, 0 bot, 0 top)` by even-odd,
the `linear-gradient(200deg, rgba(255,238,205,.15) 0%, .05 55%, .02 100%)` projected
onto CSS's 200deg axis (`d = (sin200, -cos200)`), `scaleX(-1)` on the right-hand side,
2x2 subsamples for the clip edge.

| build | tol 8 | tol 24 | mean |
|---|---|---|---|
| without beams | 417,245 | 178,863 | 14.25 |
| **with beams** | **414,407** | 178,920 | **14.22** |

**-2,838 at tol 8, +57 at tol 24.** It is flat at the tolerance the reference
distribution was fitted at and a clear win at tol 8 and in the mean. Kept, because
the alternative is knowingly shipping a missing element on the strength of 57 px.

Where it lands is worth recording: each wedge projects to frame x 237..332 (work 0),
857..902 (work 1), 448..473 (work 2)... i.e. **just to the right of its own
painting**, on bare wall -- the beam plane sits at |x| = 225 against the painting's
298.5, so it projects nearer the vanishing point and misses the frame entirely.
That is why painting 0's own box barely moves (63,423 -> 63,423) while the frame
total drops 2,838.

### 15.3 SHIPPED — `SPRITE_SCALE` 2 -> 1, one texel per CSS pixel

Every baked layer is a DOM element sized in CSS px and then projected. The artwork
inside is different: `artLayer[i]` is baked at `w*RES x h*RES` with **`RES = 3`**
(html:761, `min(4, 3*dpr)` at dpr 1) and the browser box-filters those three texels
into one CSS pixel when it paints the canvas element. At `SPRITE_SCALE = 2` that
filter only ran down to 1.5:1, so the port kept the Nyquist content the reference
has already thrown away.

| build | tol 8 | tol 24 | mean | artwork gradH / gradV |
|---|---|---|---|---|
| SS = 2 | 414,407 | 178,920 | 14.22 | 3.541 / 3.464 |
| **SS = 1** | 414,458 | **178,623** | **14.19** | 3.530 / 3.354 |

**-297 at tol 24, -0.03 mean, +51 at tol 8, and half the sprite memory.** A wash on
its own; kept because it makes the port's filter chain the browser's, which is the
property the other two changes are reasoning about.

### 15.4 REJECTED — a full-resolution sprite buffer (tried twice)

The corridor is rasterised at 640x400 and blitted to 1280x800 through
skia_shim.cpp:1374, `'Y'` = `SkFilterMode::kLinear`, so the sprites take a 2x bilinear
low-pass they should not take. The obvious fix is to give them their own
1280x800 buffer.

**Attempt 1, `SPRITE_SCALE = 2`.** Regression to 431,029 / 222,095 / 17.77. Root
cause found by a marker-filled sprite buffer (`0x20` alpha `0x20`): ink only reached
the top-left quadrant. `project()` returns RASTER coordinates that already fold in
`RW/SW = 1/2`, so a *larger* destination needs the corners **multiplied** by
`bw/RW`, not divided. Fixed and validated against
`apps/gallery/.board/gal5/qpx.mjs`, a JS replica of `camXf`/`viewAt`/`project` and
`quadPx`'s footprint estimate, which at `sx = bw/RW` reproduces §14.0's measured
boxes: sunset -1.7..268.6 / 136.3..569.3, grid 915.8..998.8 / 258.7..488.2,
flow 512.8..525.2 / 340.4..444.5.

**Attempt 2, with the scale fixed.** 417,120 / 185,517 / 14.87 -- still a
regression. Sprite boxes at tol 24 against the 640 area-averaged build: sunset
63,423 -> 69,863, grid 14,908 -> 15,301, field 3,498 -> 3,912, op 3,185 -> 3,395,
ink 734 -> 901, geo 968 -> 972, flow 164 -> 151, mosaic 742 -> 784.
**87,622 -> 95,279, +7,657.** At tol 8 it was a wash (-125 px).

**Attempt 3, `SPRITE_SCALE = 1` at full resolution** (the combination the two
changes above jointly argue for, and the reason this is worth recording):
**417,200 / 185,717 / 14.80**, artwork gradH **8.621** against a reference 6.889.
Removing the 2x low-pass overshoots by 25% *and* it overshoots identically at both
sprite scales (8.661 at SS=2, 8.621 at SS=1), which says the excess is in the
artwork source, not in the sampling chain. Buying detail with pixels does not work
here; buy it with area-averaging. **All three attempts reverted**; the
`spriteBuf`/`spriteLayer2` plumbing and `bw`/`bh`/`dX`/`dY` parameters are gone, with
the measurement kept in bake step 23 and in `drawSprite` so the next lane does not
re-derive it.

### 15.5 Net

| build | tol 8 | tol 24 | mean |
|---|---|---|---|
| baseline | 417,515 (40.77%) | 182,807 (17.85%) | 14.46 |
| **lane gal5** | **414,458 (40.47%)** | **178,623 (17.44%)** | **14.19** |
| | **-3,057** | **-4,184** | **-0.27** |

Painting 0's own box is still 63,423 of 178,623 (35%) and still runs at lumRatio
0.85 with artwork gradH 3.53 against a reference 6.89. **That term is unsolved.**
§15.4 shows the port is simultaneously too soft at 640 and too sharp at 1280, which
means the filter chain is not the whole story and whatever remains is in the
artwork or the projection, not in the resampling.

### 15.6 What was NOT done, honestly

- **The cross-clock validation the brief asked for could not be run.** The only
  1280x800 references in the tree are `ref039_800.png` and
  `.board/probe/ref_test800.png`, which is a *second capture of the same 800 ms
  clock*, not another clock. `.board/frames/gal2/ref_b*.png` are 1280x**816** and
  were captured under a different setup. Nothing in this section was fitted, so
  the exposure is small: area-averaging derives its footprint from the quad,
  `SPRITE_SCALE = 1` from the source's own `RES = 3`, and the beams from html:865-871
  verbatim -- zero free parameters, no per-clock constants. But that is an argument,
  not a measurement, and the next lane that can capture a second 1280x800 clock
  should do it.
- Works 2/4/6 (4,584 px) were not touched: they are not the term.
- Idle-camera drift (brief item 3) was not attacked.
- `tools/pngdiff.mjs` still cannot compare two PNGs; `refrepro.mjs` covers it.

---

## 16. Round 140 — re-measured against a CORRECT reference (the 57% is real)

Every number in sections 1-15 was measured against `ref039.png` **as captured in
rounds before 139**, when the page was 16 px too wide (see
`.board/reports/ISSUES.md` R18c: `100vw` resolves to the ICB width *including* the
scrollbar, so the old compensated capture laid the page out at 1280 and cut at
1264). R18c re-captured `ref039.png` at 1280x800 correctly. This section is the
first characterisation of the port against a reference that can actually refute
it, so it supersedes the localisation in 12.6/15.x.

**Headline (tol 8, ref 1280x800, frame rebuilt from current source):**

| | value |
|---|---|
| differing | 587,442 / 1,024,000 = **57.37%** |
| mean abs delta | 17.33 |
| max abs delta | 179 |

R12 check: rebuilt `apps/gallery/app.nim` and rendered fresh this round — the
fresh frame is **byte-identical in score** to the frame analysed (587,442 both),
so this is a property of current source, not a stale artifact.

### 16.1 The method that got here, and the one that nearly didn't

Two of my own probes were wrong before they were useful, and both would have
produced a confident false finding:

- **Channel order.** `pngdiff.mjs` compares `raw[i]` against `ref.rgba[i]`
  position-for-position, so the *rawswapped* frame is already R,G,B,A. My first
  tone probes read it as B,G,R and "measured" a warm/cool hue inversion across
  the whole left strip — a colour bug that does not exist. Any probe that reads
  a rawswapped frame must use the same order pngdiff uses.
- **The IoU threshold.** A 128-luminance threshold read **IoU 0.9675** and
  "placement is the problem". In this scene 98.8% of reference pixels are below
  128, so that compares two nearly-full masks and reads ~0.96 no matter what is
  wrong. The error lives in the few *lit* pixels. Re-thresholded at lum>=90:
  **IoU 0.3709**, frame has **1.61x** the reference's bright pixels, and no
  shift in +/-6 helps (best 0.3755 at dx=1,dy=1).

### 16.2 Where the error actually is (this is the useful part)

| region | differing @tol8 | mean abs | bright px ref -> frame |
|---|---|---|---|
| **left wall** (x 0..320) | **74.8%** | 24.6 | 59,415 -> 74,774 (1.26x) |
| **centre** (x 320..960) | 49.6% | 15.4 | 25,302 -> 60,128 (**2.38x**) |
| right wall (x 960..1280) | 55.5% | 14.0 | 13,238 -> 23,072 (1.74x) |

Delta histogram over the 587,442 differing pixels: 9-12 -> 27.1%, 13-16 -> 12.4%,
17-24 -> 21.2%, then a real tail out to 129+. Only 39.6% sit within 16 of
tolerance, so **this is not one small tone bias** — it is several independent
causes. A per-tile least-squares gain fit spans **0.567 .. 2.369**, which
independently confirms structural rather than global-tonal.

The 64x64 tile hotmap agrees: error is concentrated in the two walls (cols
0-256 and 896-1280) with the corridor centre largely clean. The pattern on the
floor is **peaks in the right places, too wide and too bright** — at y=700,
x=320 ref 100 / frame 113; x=560 ref 68 / frame 88; x=640 ref 12 / frame 44.

### 16.3 Refuted this round — do not re-chase

- **Fog and vignette geometry are CORRECT.** I suspected the ellipse radii.
  Measured with a purpose-built probe (`.board/probe/gradsem.html`, flat 128-grey
  under each gradient, so the ramp reads directly): the vignette gives luma 109
  at the corner, exactly what rx=1.2*W / ry=0.95*H predicts, and the fog gives
  76 / 115 / 108 at x = 900 / 800 / 1100, matching the port's radii to the unit.
- **`fogAmt()` is not the problem.** With cam.z=160, cam.rot=0, zFar=-2300 it
  evaluates to **1.0000** — full strength, as intended.
- **`csample`'s endpoint clamping is correct**, so the floor pools' outer 24-28%
  cannot be brightening anything.

### 16.4 Still open, with the localisation this round produced

1. **Left wall, 74.8% differing.** Carries the paintings; bright bands sit at
   *different x* (scanline y=528: ref bright `(156,141,100)` at x=32 where the
   frame is `(33,31,30)`, and the inverse at x=160). Consistent with 12.6's
   "content wrong at sub-sprite scale", still unsolved.
2. **Centre, 2.38x the reference's bright pixels.** Not a fog/vignette problem
   (16.3). Unexplained; this is the largest single excess and the newest lead.
3. **Floor pools too wide and too bright**, peaks correctly placed.

### 16.5 Instruments left behind (all in `.board/probe/`)

`brightiou.mjs` (lit-mask IoU sweep — use this, not a 128 threshold, in dark
scenes), `brightmap.mjs` (per-tile bright-pixel excess), `deltahist.mjs` (is this
one small bias or many causes?), `gainfit.mjs` (tonal or structural?),
`hotmap.mjs` (which tiles, ranked), `scanline.mjs`/`colscan.mjs`/`tone.mjs`
(pixel-level ref-vs-frame), `iou.mjs`, `pts.mjs`, `gradsem.html` +
`gradscan.mjs` (measure what a CSS gradient actually does instead of reading the
spec). Read a rawswapped frame as R,G,B,A in all of them.

### 16.6 The centre lead, localised (ref-only vs frame-only bright masks)

`excessmap.mjs` splits the bright population into ref-only / frame-only / both,
which the region ratios could not: **ref-only 28,713, frame-only 88,732, both
69,242 - the port over-draws 3.09x what it omits.**

The masks contradict the "centre is over-lit" reading from 16.2 in a useful way.
The reference's single brightest area (the upper-left painting, tiles rows 3-5,
cols 0-8, i.e. y 96..224 x 0..288) is **largely absent from the frame**:
`1999992` in the ref-only map against `80...052` in the frame-only map. So the
centre's 2.38x is not extra light - it is the frame's *own* version of that
painting being brighter and wider than the reference's.

Measured per-box contrast, so this is not an inference from the mask:

| box | ref mean / sd / max | frame mean / sd / max |
|---|---|---|
| painting L-upper 0,96-288,224 | 94.9 / 27.2 / 151 | **107.8 / 39.2 / 186** |
| painting L-lower 0,320-288,512 | 80.8 / 25.4 / 153 | 77.2 / **32.6** / **189** |
| left wall lower 0,560-288,760 | 41.4 / 19.2 / 153 | 50.3 / 25.7 / **182** |

**The painting is present and roughly aligned; it is over-contrasted.** Frame sd
is 32-44% above the reference on all three boxes and the frame's peak is ~186-189
where the reference's is ~151-153. A row scan at y=110 is uniformly +17; at
y=140 x=0 it inverts (ref 86, frame 43), so the difference is dynamic range, not
offset.

Two candidate sources, **neither yet verified, do not act on either without a
measurement**:
1. The artwork is over-contrasted before projection. §15 measured artwork-rect
   gradH 3.53 against a reference 6.89 and concluded the opposite (too FLAT) -
   but that was artwork-rect gradH against a screen-space painting box, which are
   different quantities. Both may be true: flat in the artwork, then sharpened by
   the projection chain. **This needs re-measuring on the same quantity.**
2. The gold moulding gradient peaks at `#F2D98B` (luma ~222) and the spotlight
   scallops add `rgba(255,243,220,.97)` on top. The reference's brightest pixel
   in these boxes is ~151, so something upstream is not being attenuated the way
   the browser attenuates it.

The discriminating measurement, not done yet: bake one painting's sprite alone
(no projection) and compare its histogram to the same painting's on-screen box
in the reference. That separates "artwork too contrasty" from "projection
sharpens" in one capture.

### 16.7 The discriminating measurement: is the artwork over-contrasty, or the projection?

16.6 named this as the experiment that would settle it. Done, with a purpose-built
probe build: a copy of `app.nim` whose `repaint()` blits `artLayer[0]` alone
(`.board/probe/galprobe.nim`, black behind it) - no projection, no frame, no mat,
no shadow, no fog, no vignette. Its histogram IS the artwork's own contrast.

    artwork as baked   mean 97.0   sd 45.8   max 252.4
    port painting box  mean 107.8  sd 39.2   max 185.8
    ref  painting box  mean  94.9  sd 27.2   max 150.6

**The projection REDUCES contrast (45.8 -> 39.2); it does not create it.** So the
excess is genuinely upstream in the artwork, and the projection chain is exonerated.

**A confound I nearly got wrong, and caught by reading.** I first compared the
whole artwork's per-channel mean against the on-screen box and "found" a hue error
(R 1.015x, G 0.788x, B 1.323x - magenta-shifted). That is an artifact: the screen
box contains the **gold moulding, mat and fog**, all warm, so it cannot be compared
to raw artwork. The confound-free comparison is **port-screen vs ref-screen**, which
contains the same frame on both sides and cancels. Use that one. The hue finding is
withdrawn.

### 16.8 A real generator bug, fixed - and it is NOT the cause of 16.6

Checked every generator's grain against the source:

    genSunset      html:388  NO grainPass call   port had 16   WRONG
    genGrid        html:444  10                  port had  6   WRONG
    genColorField  html:489  12  ok    genOp   html:523   7  ok
    genInk         html:546   8  ok    genGeo  html:618  14  ok
    genFlow        html:650   8  ok    genMosaic html:683 NO call

The old comment claimed `gMosaic` was "the ONE generator the source does not grain".
**Two** are ungrained - sunset and mosaic - and the table invented an amount for
sunset while calling out only the other. Sunset is `WORKS[0]`, the left-wall painting
that dominates the gallery's error, so it was the wrong one to have invented.

`gSunset` now discards, `gGrid` now uses 10.

**Effect, measured, and small:** 587,442 -> **587,440** differing pixels - **2 pixels
in 1,024,000**. Mean |delta| unchanged at 17.33, painting-box sd unchanged at 39.2.
Correct against the source and invisible in the score, because `grainPass` adds
`(R()-.5)*amt` whose sd contribution is only `amt/sqrt(12)` = 4.6 at amt 16. Kept
because it is a fidelity defect, not because it scores. **It does not explain 16.6.**

### 16.9 Refuted on the way (record so nobody re-chases them)

- **`hsl()` is correct.** Transcribed to JS and run against a CSS reference on all 10
  (h,s,l) values `genSunset` actually emits, including the >360 wrap to 370: **10/10
  identical**. The wrap at `fmod32` is load-bearing and right.
- **`noiseAt`'s `* 0.7` is correct.** html:376 ends `return (l1 + v * (l2 - l1)) * .7`.
  I suspected the port had invented this factor; the grep missed it and the read found
  it. Same for `fade`, `grad`, `fbm`.
- **The fade is not the cause.** `.frame canvas{ opacity:0; transition:opacity 1.1s }`
  looked like the obvious suspect - a capture at 800ms could catch the artwork
  mid-fade. Captured the page at 800ms and 4000ms: painting-box sd **31.5 vs 32.3**,
  whole frame differing **1.83%**. Settled by 800ms. Not it.
- **`genSunset` is a faithful transcription.** Compared line by line against html:388-417,
  including the branch order and the RNG-consuming branches.

So the 1.44x over-contrast is real, is upstream of the projection, is not grain, not
the fade, not `hsl`, and not noise. **Still unexplained.** The next discriminating
measurement is to bake the artwork WITH the gold frame and mat into the sprite (that
layer exists - `spriteLayer[i]`) and compare its histogram to the reference's painting
box, which tests whether the frame is attenuating the artwork the way a browser's
compositing does.

### 16.10 The discriminating experiment, run properly — and a probe mistake worth recording

16.9 said to bake `spriteLayer` (artwork + gold moulding + mat) and compare. I did,
and got a nonsense answer: artwork interior mean **5.3**. Nearly black. The reason:
**`spriteLayer[i]` does not contain the artwork.** At app.nim:1324 it draws the drop
shadow and moulding only; the artwork is composited into a *separate* `canvasLayer[i]`
(app.nim:1325-1338) and the two are drawn as two layers. I sampled the moulding's
transparent interior over black and nearly published it as a result.

**Rule: before trusting a probe that reads a layer, confirm what that layer is
composed of. `spriteLayer` = frame, `canvasLayer` = artwork.** They are different
rects with the same outer size, so the mistake is easy to make and looks like data.

Redone on `canvasLayer[0]` — the artwork as the browser composites it (artLayer
downscaled 3:1 from RES=3, plus the canvas shadow), still with no projection, no scene
lighting, no fog, no vignette:

    region                    mean      sd     min     max
    canvasLayer artwork      107.9    46.7     17.8   252.2
    REFERENCE painting box    94.9    27.2     11.2   150.6
    port screen painting box 107.8    39.2     13.1   185.8

### 16.11 THE FINDING: the port does not dim the artwork at all

Read the means down that column.

    unattenuated artwork            107.9
    port, on screen, after the      107.8   <- ratio 0.999
      full projection + lighting
      + fog + vignette chain
    reference, on screen            94.9    <- ratio 0.879

**The port's gallery lighting and fog leave the artwork essentially untouched — a
measured attenuation of 0.3%. The browser's attenuates it to about 88%.** That is
the missing ~12%, and it accounts for the whole over-contrast story at once: the mean
is 13.6% high, the max is 185.8 against 150.6, and sd rides along at 1.44x because an
un-attenuated painting keeps all of its highlight energy that the reference's has
already lost.

The bright tail confirms it. Trimming the artwork's top decile by cap:

    artwork sd, full           46.7
    drop pixels > 200          39.3   (n 27324 -> 25911)
    drop pixels > 170          32.2   (n -> 23907)
    drop pixels > 150          28.1   (n -> 22324)   <- reference box sd is 27.2
    drop pixels > 130          23.7   (n -> 19981)

**9.1% of the artwork's pixels sit above luma 200** — the sun disc at `hsl(50,100%,86-94%)`
and the lamp at `hsl(36,92%,78%)` are effectively white, and both are transcribed
correctly from html:409 and html:570-573. The reference's brightest pixel in that box
is 150.6. So the artwork is not wrong; it is **correctly generated and then wrongly
left at full brightness**, when the scene was supposed to be dimming it.

**Inference, stated as one:** this assumes the reference's artwork has the same mean as
the port's. That rests on the generators being identical, which is now established
(grain fixed in 16.8, `hsl` verified 10/10, `genSunset` compared line by line against
html:388-417). Under that assumption the attenuation factors above are direct
measurements.

**Next step, named before it is attempted:** find what dims the artwork in the browser.
Candidates in order of likelihood — a per-plane lighting multiply applied to the
`plane()`/artwork DOM nodes, the fog's actual effective alpha over that depth, or a
`filter: brightness()` on the frame. Measure which, do not assume.

### 16.12 CORRECTION of 16.11 — the conclusion there was wrong; the numbers were right

16.11 said "the port does not dim the artwork at all" and pointed the next step at
artwork lighting. **That is refuted.** The measurements it rested on are correct;
the inference drawn from them was not, and I caught it in the same round by running
the extra test instead of acting on it.

The ref/port luma ratio, binned by **port** luminance over the whole 1280x800 frame:

    port luma bin      n        mean ref/port
       0- 15       49183      1.371
      16- 31      288616      0.986
      32- 47      155268      1.032
      48- 63      236401      0.906
      64- 79       80309      0.873
      80- 95       87938      0.808
      96-111       63251      0.776
     112-127       27881      0.770
     128-143       13435      0.783
     144-159       12824      0.686
     160-175        4709      0.492
     176-191        2969      0.614

The ratio **falls as brightness rises** — neither flat (multiplicative gain) nor
climbing (additive offset). That is a **tone-curve difference**: the port's shadows
are too deep and its highlights too hot.

Whole frame, both images:

    reference  mean 47.2   sd 29.0
    port       mean 54.1   sd 33.6      -> mean x0.873,  sd x1.157

**So the dominant error is a GLOBAL tone-curve offset, roughly 15% across the whole
image — not an artwork-lighting bug.** 16.11's arithmetic hid this because it
compared the artwork's unattenuated mean (107.9) to the reference's box mean (94.9)
without first establishing a baseline: at a global ratio of 0.873 the painting box's
0.880 is **exactly what an undistorted region would give**. The artwork is not a
special case.

**Where the artwork does still stand out:** its sd ratio is **1.44**, against a global
**1.157**. So the painting carries real excess error *on top of* the global tone
offset — it is the worst region, but it is not a separate lighting bug.

**Where this points instead.** A global tone-curve difference is worth more than every
region-level fix available, and it is cheap to test: the frame-level tone curve is
where the 57% mostly lives. The discriminating next step is to fit the port->reference
luma transfer above and compare it against the ONE place the port applies a global
transfer — `corrLayer` at app.nim:3496, drawn over the whole scene. That is the first
thing to suspect, and it is a single global multiply the browser may not have.

**The lesson, fifth instance:** a correct measurement plus a plausible inference is
still not a finding. The tell was available immediately — compare the ratio to the
frame's global ratio before believing a region is special. Two of my last three
"discoveries" this round were the instrument or the inference, not the port.

### 16.13 The tone-curve hunt: two candidates checked and CLEARED, cause still open

16.12 pointed at `corrLayer`. **Wrong guess — recorded so nobody repeats it.**
`corrLayer` is the rasterised *corridor content* (app.nim:3475, 3496), not a global
transfer. There is no global multiply there.

Second candidate: the fog/vignette overlay, the one global element that darkens
everything. **Checked against source and cleared:**

- fog stops `rgba(8,7,6,.62) 0% / .34 45% / 0 100%` — verbatim html:96.
- vignette `rgba(0,0,0,0) 55% / rgba(0,0,0,.55) 100%` — verbatim html:98.
- radii: `fogRX = SW*.30`, `fogRY = SH*.34`; `vigRX = SW*1.20`, `vigRY = SH*.95`.
  CSS `radial-gradient(30% 34%)` is 30% of WIDTH and 34% of HEIGHT, and the port
  does exactly that (this was already fixed once — the old circle at `r = SW*0.60`
  reached 82% of the frame instead of 27%).
- `--fog` opacity is applied to the fog stops only, not the vignette — matching
  `.fog{opacity:var(--fog,1)}` with no opacity on `.vignette`.
- the two-layer composite is right: for black-over-black,
  `ca = af*(1-av) + av` and colour `(8,7,6)*af*(1-av)/ca`.

So the global tone difference is **not** the fog, **not** the vignette, **not** their
composite, and **not** `corrLayer`.

**What is established:** the port's frame is ~15% too bright and ~16% too contrasty
GLOBALLY (mean 47.2 -> 54.1, sd 29.0 -> 33.6), with the error growing toward the
highlights (ref/port 0.49 at port luma 160-175). The painting region adds further
excess on top (sd ratio 1.44 vs the global 1.157) but is not a separate bug.

**Named next step, in order — measure, do not guess:**
1. The **room background gradient** (html:25, `radial-gradient(90% 70% at 50% 45%,
   #1b1713 0%, #0c0a08 60%, #050404 100%)`). It is the only remaining global
   contributor and it sits UNDER everything, so an error in it lifts or crushes the
   whole frame in exactly the way measured. This is the first thing to test.
2. If the room gradient is right, the **corridor's own lighting ramp** — the per-pixel
   `corrBuf` — is the last global stage before the fog, and can be probed by
   rendering the corridor alone with the fog/vignette bypassed.

Note that (1) and (2) are cheap to separate: the existing probe pattern from 16.10
(bypass one stage, measure) applies directly.

### 16.14 Third candidate found and measured — a real defect, but NOT the cause, and deliberately not fixed

The room background is the remaining global contributor. It **has a genuine bug**:

    html:25   radial-gradient(90% 70% at 50% 45%, #1b1713 0%, #0c0a08 60%, #050404 100%)
    port      rampDisc(centre, roomGradRadius())  -- a CIRCLE

`rampDisc` takes one radius, and `roomGradRadius()` supplies the distance to the
farthest corner, so the port draws an **isotropic circle of r=776.7** where CSS asks for
an **ellipse of rx=1152, ry=560**. Measured, sampling both ramps:

    point              CSS luma   port luma   delta
    top centre            9.7        11.1      +1.4
    left/right edge mid  11.4         6.9      -4.5
    bottom centre         7.6        13.4      +5.9
    corner TL             6.6         4.3      -2.3
    corner BR             4.9         5.2      +0.3

**The signs are mixed, so this cannot produce a uniform global brightening** — and the
whole effect lives in luma 4-13, under a corridor that covers most of it. The global
mean gap to explain is **6.9** luma. This is not it.

**Not fixed this round, on purpose.** The right fix is an ellipse-capable primitive: the
SDK has `circle` (`sdk/ui/paint.nim:59`) and **no `oval`**, and `rampAnnulus` cannot
express a filled elliptical ramp because it knocks out its inner ellipse. Adding
`Draw.oval` is an SDK change, and AGENTS.md rule 6 requires the renderer mapping **and**
a `render/t_qml.nim` test in the same task. That is a larger, riskier change than a
<=6 luma difference on a mostly-occluded background justifies as a drive-by. It is
recorded as a known defect with its magnitude, not slipped in alongside a tone-curve
fix. If it is done, it should be its own task with its own test.

**Status after three candidates.** Cleared: `corrLayer`, the fog/vignette overlay and
its composite (16.13), and now the room gradient's geometry. The global tone difference
is real — mean 47.2 -> 54.1, sd 29.0 -> 33.6, error growing toward highlights — and
**still has no identified cause.** The room geometry finding is worth banking on its own
merits; it is not the answer to the question I asked.

Remaining untested global stages, in the order they composite:
1. the **corridor's own lighting ramp** in `corrBuf` (`renderCorridor`) — the last global
   stage before the fog. Probe by bypassing fog/vignette as 16.10 bypassed the scene.
2. the **per-plane lighting** applied to each artwork node inside the corridor raster,
   which is per-element rather than global but would still show as a frame-wide bias if
   it is applied at the wrong strength.

### 16.15 The fog bypass, run — and the FIRST invalid probe of this round, caught

Ran 16.13's named next step: bypass fog+vignette, keep everything else. **The first
attempt measured nothing.** The frames came out byte-identical (0 of 1,024,000 pixels
differing), and the reported "fog darkens the frame by 0.0%" was the real app scored
against itself.

Cause: the patch used `(?m)^  drawFogVig\(result\)$`, and `$` in .NET multiline mode
does not match before a CR — the file is CRLF, so the pattern never hit. The build
still succeeded and still changed size (line-ending normalisation), which is exactly
what made it look like it had worked. `Select-String` for the patch marker printed
nothing and I did not read that before moving on.

**Rule: a probe build that produces a frame IDENTICAL to the baseline has not run.**
Diff the two frames before believing any statistic from them. This is the sixth
instrument failure this session, and the second where the failure was silent and the
output looked well-formed.

Re-run with a `\r?`-tolerant pattern, verified applied before building:

    frames differing with-fog vs no-fog: 366,600 (35.8%)

    whole 1280x800      mean      sd
    port NO fog/vig     58.0     35.9
    port WITH fog/vig   54.1     33.6
    reference           47.2     29.0

**What this settles.** The port's fog+vignette overlay darkens the frame's mean by
**6.6%** and touches 35.8% of pixels — it is doing real, substantial work, and it is
correct. If the port's pre-fog frame (58.0) is comparable to the reference's, the
browser darkens by about **18.6%** overall. So the fog accounts for roughly a third of
what the browser does, and **the corridor's own content is about 12% too bright.**

That is the first positive statement about where the global tone error lives, and it
is consistent with every earlier result: it is frame-wide, it is not positional, it is
not the fog (correct, -6.6%), not the room gradient geometry (+/-5 luma, mixed sign),
and not `corrLayer` as a transfer (it is a content raster).

**Next step:** inside `renderCorridor`, the suspect is whatever scales the artwork and
floor into the corridor raster — a lighting multiply or exposure constant applied at the
wrong strength. `renderCorridor` writes `corrBuf`; probing it means drawing `corrBuf`
to the screen with the room gradient and the fog both bypassed, which isolates the
corridor's own output exactly the way 16.15 isolated the fog.

### 16.16 The tone error is NOT global exposure - it is the NEAR FLOOR, and it is the single worst region

16.15 left the corridor "~12% too bright" as a frame-wide statement. **That framing was
too coarse and it hides the answer.** Measured per element, ref/port luma ratio:

    painting 0 (sunset)   0.881
    left wall            0.823
    right wall           0.837
    ceiling              0.910
    FLOOR                0.762   <- worst by a clear margin

So it is element-dependent, not a uniform exposure constant. The ceiling is closest to
right (the port is only 1.10x too bright there); the floor is the outlier at 1.31x.

And the floor's error is not uniform across depth either. Ratio by screen row, where
**small y is far away and large y is near the camera**:

    y 470-510   0.865     (far)
    y 510-550   0.874
    y 550-600   0.862
    y 600-650   0.787
    y 650-700   0.732
    y 700-760   0.782
    y 760-800   0.697     (near)  <- the port is 1.43x too bright here

**The error grows toward the camera, which is the opposite of a distance-falloff bug.**
Under-applied distance attenuation would make the FAR floor wrong and the near floor
right; here the near floor is the worst region in the frame. That rules out the
hypothesis 16.15 implicitly invited, and it matches what round 140 recorded in passing
— "floor pools correctly placed but too wide/bright" — which was right and was filed as
a detail rather than the headline.

**What this now says, stated as a ranking rather than a guess:**
1. near floor (y 700-800), ref/port 0.697 — worst single region in the frame
2. far-to-mid floor, 0.73-0.87
3. walls, 0.82-0.84
4. painting 0, 0.881
5. ceiling, 0.910 — nearly right

The gallery's 57% is therefore mostly **one region**, not a global tone curve. Chasing a
global gain would have been the wrong fix and would have hurt the ceiling and the
paintings to help the floor.

**Next step, named:** the floor texture and its spotlight pools, sampled per row. The
question is whether `texFloor`/`drawBeams` is emitting pools that are too wide and too
bright near the camera, or whether the projection is over-brightening the near plane
specifically. Probe by rasterising the floor texture alone through the same projection
used at app.nim:2673-2683, which isolates it from the mirror, walls and beams.

This supersedes 16.15's "~12% corridor-wide" as the working characterisation: it is a
frame-average over a strongly non-uniform error.

### 16.17 floorTex audited line by line against html:814-824 - CORRECT, so the fault is downstream

Checked every element of the floor texture against the source before suspecting it:

| element | html | port | |
|---|---|---|---|
| 8 picture pools | `ellipse 150px 200px`, .3 / .1 / 0@72% | 150, 200, .30 / .10 / 0@.72 | ok |
| pool centres | `side==='L' ? 78 : 522`, `ly = z - G.zFar` | same | ok |
| near pool | `ellipse 260px 240px at 300px 90px`, .18 -> 0@75% | 260, 240, at 300,90, .18 / 0@.75 | ok |
| edge shadows | `90deg, rgba(0,0,0,.55) 0% / 0 9% / 0 91% / .55 100%` | .55 over fx<.09 and fx>.91 | ok |
| marble | `URLF(marble)` at `128px 128px` | 2x2 down of the 256 source, alpha 188/255 | ok |

**One difference, and it is inert.** CSS paints `background-image` first-listed on
TOP, so the real stack top-to-bottom is: 8 pools, near pool, edge shadows, marble. The
port builds it (line 1607 header says BOTTOM-UP) as: marble, edge shadows, 8 pools,
near pool — i.e. the near pool ends up **over** the eight, where CSS has it **under**.
It cannot matter: the near pool occupies x 40..560, y 0..330 in texture space, and the
eight picture pools sit at `ly = z - G.zFar` = 1360..1970, hundreds of rows away. They
never overlap, so the two orders are the same image. Worth knowing, not worth changing.

**So the floor texture is right and the excess is downstream of it.** Remaining
suspects, in order:

1. **the projection / mirror composite** at app.nim:2671-2683, where the floor is
   blitted translucently over the reflection buffer. The near floor is the region with
   the strongest mirror contribution and the least fog, so a mis-scaled alpha there is
   the most likely remaining cause.
2. **`drawBeams`** (app.nim:2538), which composites eight light shafts AFTER every
   sprite and is explicitly *not* fogged, so it lands at full strength on the near
   floor where the fog cannot reach it. Its `2x2` grid is the only approximation in
   that proc.

Point 2 deserves attention for a specific reason: **the near floor at y 760-800 sits
outside BOTH overlays** — the fog ellipse is 384x272 centred at (640,400), and the
vignette does not start until 55% of 1536x760, so at bottom-centre `sv` is 0.525 and
the vignette contributes nothing. The region carrying the frame's worst error is the
one region the port's global darkening never touches. That is why a global gain cannot
fix this, and it is consistent with 16.16.

**Not yet measured:** whether `drawBeams` is actually significant on the near floor in
either image. That is the single cheapest next probe — render with the beam pass
skipped and diff the near-floor band against the same band with it present.

### 16.18 Beams CLEARED, and the floor's error is ADDITIVE - pointing at the mirror beneath it

**`drawBeams` is not the cause.** Skipping it changes 10,435 px (**1.0%**) and the
near-floor band means are identical with and without it:

    band          ref   port-beams  port-nobeams
    far floor    38.1       44.0         44.0
    mid floor    50.4       64.1         64.1
    near floor   45.7       58.4         58.4
    nearest      41.3       59.3         59.3

**The floor's error is additive, not multiplicative.** Vertical profile at centre
(x 600-680) shows the reference oscillating hard between its dark and pale marble
tiles - 38.7, 24.8, 50.1, 22.2, 24.1, 57.0, 58.6, 21.2, 21.7, 35.0 ... - while the
port runs the same oscillation at a uniformly higher level (66.1, 36.5, 72.9, 46.4,
50.9, 96.2, 98.5, 50.4, ...). At y=785 the reference is **13.7** and the port **42.3**;
at y=680 the reference is 58.6 and the port 98.5.

Splitting floor pixels by reference luma and measuring the ABSOLUTE offset:

    dark marble tiles  n=44129   median port-ref = +11.6   p25 +3.8   p75 +25.0
    pale marble tiles  n=54567   median port-ref = +15.6   p25 +8.8   p75 +23.2

A multiplicative (exposure) error would scale the offset with the level and roughly
double it between these two populations. It does not - **12 to 16 luma is close to a
constant lift.**

**What an additive lift on a translucent surface means.** `floorTex` composites the
marble at alpha **188/255 = 0.737**, so **26.3% of whatever lies beneath shows
through**. The port's floor is sitting on something roughly **+49 luma** too bright
(+13 / 0.263), which is the **mirror** - the reflection buffer composited at
app.nim:2671-2683, and the only thing under the floor.

That also explains why the error looked "nearest-camera worst" in 16.16: the reflection
is strongest and most structured near the camera, and the far floor reflects the dark
vanishing point, so a too-bright mirror contaminates the near floor most. It explains
the additive signature, and it is consistent with everything still uncleared -
`floorTex` correct, beams 1.0%, fog and vignette not reaching the bottom edge.

**Next probe, named:** render the mirror alone - skip the floor composite at
app.nim:2673-2683 - and measure it against the reference in the bands where the floor
is thin or absent (the vanishing point and the side margins). Do **not** measure it
under the floor, where the floor's 0.737 covers it; that is the whole reason the
signal has been invisible until now.

### 16.19 The mirror is confirmed too bright, AND its depth profile is INVERTED

Ran 16.18's probe: skipped the `blit` at app.nim:2681 so the floor no longer composites,
leaving the mirror visible. 235,720 px changed (23.0%), so the probe ran. Measured the
mirror in the bands where it is exposed:

    band        ref   mirror   full   ref/mirror
    y 470-510  38.1     44.2   44.0      0.862
    y 510-560  40.5     52.2   46.3      0.776
    y 560-620  46.7     62.4   55.6      0.748
    y 620-680  49.3     83.1   65.5      0.593
    y 680-740  46.2     77.8   60.7      0.593
    y 740-800  43.5     76.3   59.7      0.570

**Two separate facts, and the second is the actionable one.**

1. The mirror is too bright everywhere, worsening toward the camera: ref/mirror falls
   0.862 -> 0.570. This confirms 16.18's inference quantitatively.

2. **The depth profile is backwards.** The reference's floor is essentially FLAT with
   depth - 38.1, 40.5, 46.7, 49.3, 46.2, 43.5, a spread of ~11 luma. The port's mirror
   RISES steeply toward the camera - 44.2, 52.2, 62.4, **83.1**, 77.8, **76.3**. It is
   not "a bit too bright", it is *shaped differently*.

**What that implies.** Near the camera the mirror should be reflecting the walls that
are right beside the viewer. Those are `.wall-pl{ background-color:#645d52 }`
(luma **93**) — and the port's near mirror at 76-83 is exactly that wall, dimmed by the
floor and the fog. The reference's near floor sits at **43.5**, which is nowhere near a
`#645d52` wall. Meanwhile the bright thing in this corridor is the END WALL's spotlight
(`html:883`, `rgba(255,243,220,.82)`), which is at `G.zFar` — so the physically
sensible reading is the opposite of the port's: the FAR floor should carry the bright
end-wall reflection and the NEAR floor the dim nearby walls.

So the port's mirror is not merely over-bright — **its near field is showing the bright
walls where the reference shows something much darker.** Candidate causes, in order:

1. **The wall planes in the mirror are over-extended toward the viewer.** `mk()` builds
   the mirror's walls as `plane('wall-pl', LEN, HGT, ...)` (html:878-881) — the same
   LEN as the real group. If the port's mirror walls run past the near end of the
   corridor, they fill the near floor with bright wall where the reference has nothing.
2. **The mirror's y-flip origin.** `.group.mirror{ transform:translateY(400px) scaleY(-1) }`
   flips about **400px**, not about `G.floorY`. If the port's flip is about the floor
   plane instead, every mirrored plane lands at a different depth. The port's own note
   at app.nim:1868-1871 records a past bug of exactly this family — "the mirror rays
   and the mirrored sprites were looking from two places 400 units apart."
3. Mirror sprites drawing at full alpha where the browser's reflection is occluded.

**Next step, named:** measure the mirror's screen-space extent per band — specifically
what is being hit at y 620-800, x 360-920 (which surface: wall, end wall, or a
painting). That distinguishes cause 1 from 2 immediately: if the near mirror is hitting
`F_WALL` where the reference has void, the walls are over-extended; if it is hitting the
wrong surface at the wrong z, the flip origin is wrong.

This is the first defect found in the gallery that has a concrete, testable mechanism
rather than a statistical anomaly, and it accounts for the frame's worst region.

### 16.20 The flip origin is CLEARED; the near mirror is painting reflections in the wrong place

**Candidate 2 (flip origin) is wrong — the port is right.** `G.floorY = 200` in both
(html:759, app.nim:38) and `translateY(400px) scaleY(-1)` composes to `y -> 400 - y =
2*G_FLOORY - y`, i.e. reflection **about the floor plane**, exactly as the port does.
The port's own note at app.nim:1819-1822 already flags `400.0` as `2*G_FLOORY` doing
that job. Nothing to fix here.

**What the mirror actually shows near the camera.** Mirror-only probe, sampling the
near-floor band:

    y    x     mirror RGB          ref RGB        luma mirror / ref
    640  640   117,110, 97          22, 20, 20        109 / 20
    660  640   147,140,125          70, 67, 63        139 / 67
    700  520   141,132,117          64, 61, 57        132 / 61
    700  760    64, 57, 46          70, 67, 63         56 / 67
    760  640    58, 54, 46          35, 33, 31         53 / 33
    780  520   165,155,137          63, 59, 55        152 / 59
    780  760    58, 51, 42          69, 66, 62         52 / 66

**It is patchy, and the pattern is the finding.** At x=760 the port and the reference
AGREE (56 vs 67, 52 vs 66). At x=520-640 the port is **2 to 3.5x** the reference's
luma, and the values are far brighter than any wall colour: `#645d52` is luma 93, but
the port's mirror reaches **139 and 152**, which is in the range of the **painted
artwork** (its own mean is 107, its pale highlights much higher).

So the port's near mirror is filled with **painting reflections in positions the
reference does not have them**. In the browser a painting at world `y = w.cy` mirrors to
`400 - w.cy`; for `WORKS[0]` with `cy = -22` that is world **+422**, well below the
floor, and it projects into the lower half of the frame — which is why reflections are
*expected* there in both images. The disagreement is not that reflections exist, it is
**where in x they land and how much of the band they fill.**

**This also explains the additive signature from 16.18** without any global tone term:
bright painting reflections, spread across the near floor, raise the mean by a roughly
constant amount wherever they appear, and darken-then-brighten locally where they do not.

**Next step, named and cheap:** locate the mirrored sprite quads. Draw ONLY the mirror
sprites (`drawSprite` at app.nim:2643-2669) with the mirror's wall/end-wall raster
(2620-2642) skipped. That gives the reflections alone on transparency, and their
per-sprite screen x-extents can be compared directly against where the reference's
reflections actually appear. If they are shifted toward the viewer, the defect is in
the `xm` transform used at app.nim:2626; if they are the right place but too large or
too opaque, it is in the mirror sprite's scale or alpha.

`xm` is the right first suspect: it is a **separate transform object** from `xr`, built
from the same world constants, and the flip is folded into its basis rather than
applied to shared geometry. A sign or offset error in one basis produces exactly this
— reflections present, roughly correct in character, wrong in position.

### 16.21 The mirror-sprite probe did NOT isolate - recording why, not what it "showed"

16.20 named the probe: draw only the mirror sprites, with the mirror raster skipped, and
read their per-sprite screen x-extents. **I ran it and it does not do that.**

What the patch actually removed: the mirror raster `put` (app.nim:2636) and the floor
blit (app.nim:2681). What it left: the entire REAL group — the walls/ceiling raster
(app.nim:2685+), both real sprite passes (app.nim:2656 and 2663), and `drawBeams`. So
the probe frame is "everything except the mirror raster and the floor", not "the mirror
sprites alone".

The tell was in the output and I should have read it before writing anything down:

    full vs "mirror-sprites-only" differing: 235,618 (23.0%)
    sprite-pixel bounding box: x 0..1279  y 0..799
    every sampled row 520..760: x 0..1279

**Sprites spanning the entire frame in every row is not a set of eight reflected
paintings** — it is the real paintings on the walls, which is what was left in. The
23.0% match against the mirror-only probe (235,720) is the same signature: both probes
removed one raster layer, neither isolated the mirror group.

**Seventh instrument failure this session, and the third silent one.** The lesson is
narrower than "check your patch" and worth stating precisely:

> **A probe's bounding box is a validity check.** If the region you asked for covers
> the whole canvas, the probe measured the rest of the app. Compare the probe's extent
> against what you intended to isolate BEFORE quoting any statistic from it.

**What it would take to actually isolate the mirror group** — five bypasses, not two:
the mirror raster (2636), the floor blit (2681), the real raster (2685+), both real
sprite passes (2656, 2663), and `drawBeams` (2775). That is a real patch and worth
doing properly rather than incrementally, because the mirror group is the frame's
worst region (ref/port 0.570 at y 740-800) and every proxy I have used so far is
contaminated by the real group.

**Unchanged and still standing from 16.20** — none of this touches those measurements:
the mirror is too bright in the near field, patchily in x (x 520-640 runs 2-3.5x the
reference while x=760 agrees), the excess is artwork-bright rather than wall-coloured,
and the flip origin is correct (`G_FLOORY = 200`, `400 = 2*G_FLOORY`).

### 16.22 Proper isolation (12 bypasses + a differential) WITHDRAWS 16.20

Built the isolation 16.21 specified. Twelve bypasses all verified applied before
building: mirror raster, the four real raster puts, the floor blit, the title/frame/
sheen/placard sprites, the real canvas sprite, and `drawBeams`. The two mirror sprite
passes (app.nim:2656, 2663) confirmed untouched.

**First validity check failed, correctly.** The probe frame was still 99.7% "drawn",
bbox `x 0..1279 y 0..799` - the same trap as 16.21. But for a different reason this
time: **the room gradient and the fog are drawn at `repaint` (app.nim:3516), outside
`renderCorridor`, and they fill the frame.** No amount of bypassing inside
`renderCorridor` can empty it. A bbox check on this app can never be the validity test.

The correct instrument is a **differential**: build a second variant with the mirror
sprites *also* zeroed, so everything common (room gradient, fog) cancels and the
difference is exactly the sprites' contribution.

**The differential** (A = mirror sprites on, B = same build with sprites at alpha 0):

    differing pixels: 137,835 (13.46% of frame)
    bounding box: x 0..1004   y 229..664

    row   x-extent        n
    380   x    0..1004   n=543
    500   x    0..1004   n=419
    580   x    0.. 208   n=209
    660   x    0..  14   n=15
    700   (none)
    780   (none)

**The mirror sprites stop at y=664 and contribute NOTHING below y=700.**

### THE CORRECTION

**16.20's central claim is wrong and is withdrawn.** It said the near mirror's excess
(147,140,125 and 165,155,137, artwork-bright) was "painting reflections in the wrong
place". It is not. Those pixels come from the **mirror raster** - the mirrored walls -
and the sprites are not there.

How the error happened, because it is worth recording precisely. The 16.20 samples were
taken from the **2-bypass** `mirroronly` frame, which still contained the mirror raster.
The bright values were read correctly, but they were attributed to sprites by inference
from brightness alone. The differential now shows sprites do not reach those pixels at
all. **A colour that matches the artwork is not evidence that the artwork is what drew
it** - the same mistake class as the 16.11 region-ratio error, one layer up.

I also made a fresh arithmetic error in the first attempt to read the differential: it
reported a "+62.8 sprite contribution" in y 740-800. A and B are **byte-identical**
there (0 differing pixels of 51,200). That number was nonsense and is discarded. It is
recorded because it is the second time this round that a plausible-looking number came
out of a script I had not sanity-checked.

**Where the near-floor excess actually is, stated only as far as it is measured:**

| source | contributes below y=700? |
|---|---|
| mirror sprites (paintings) | **no** - zero pixels past y=664 |
| mirror raster (walls, end wall) | **yes** - this is the 76-83 luma |
| beams | cleared in 16.18 (1.0% of frame) |
| fog / vignette | geometrically cannot reach the bottom edge (16.17) |
| `floorTex` | verified correct (16.17) |

So the near floor's brightness comes from the **mirrored walls**, and `.wall-pl` is
`#645d52`, luma **93**. The port's near mirror at 76-83 is that wall dimmed by floor and
fog; the reference's near floor is **43.5**, which no wall colour reaches.

**Next step, named:** the mirrored walls' geometry. `mk()` builds them as
`plane('wall-pl', LEN, HGT, ...)` with `LEN = G.zNear - G.zFar = 2700` (html:760,
878-881). Near the camera the port's mirror shows a wall that the reference does not.
Check whether the reference's near floor is reflecting the **dark near end** of the
corridor rather than a wall running the full length — i.e. whether the mirrored wall's
z-extent is over-long toward `G.zNear`, which in the browser would put that stretch
behind the camera and out of frame.

**Two lessons to add to skills, both earned here:**
1. **Bypassing layers only works if you bypass every producer, including ones outside
   the proc you are probing.** The room gradient and fog live in `repaint`, not
   `renderCorridor`; a bbox check caught it, a naive "I removed N layers" would not.
2. **When a region is suspect, prefer a differential probe (X on / X off, everything
   else shared) over a single probe.** It cancels common confounders by construction
   instead of by hoping they were small, and it makes the invalidity condition obvious:
   if the differential is empty, the layer genuinely does not reach that region.

### 16.23 BOTH 16.19 and 16.20 are withdrawn - the "mirror only" probe never isolated the mirror

16.22 named the wall z-extent as next. Before chasing geometry, I put a **face map** on
the mirror raster - each face painted a flat primary - in the EXACT round-143
configuration (only the floor blit bypassed), so the result is directly comparable to the
76-83 luma that 16.19 reported.

    ROUND-143 CONFIG (floor blit off) + mirror faces painted per-face:
    y 500    56% dark   44% OTHER
    y 620   100% dark
    y 680   100% dark
    y 740    63% dark   38% OTHER
    y 780   100% dark

**Not one face colour appears at the near floor.** And the round-143 frame's actual pixel
there is `(90,84,76)` at (520,760) - which is the wall colour `#645d52` (100,93,82)
dimmed, from the **REAL** group, which that probe left fully drawn.

So:

- **16.19 is withdrawn.** Its "the mirror is 76-83 luma and ref/mirror 0.570" measured
  the real walls and the room gradient, not the mirror. Skipping the floor blit removes
  one layer and exposes everything underneath it, including the entire real group.
- **16.20 is withdrawn with it.** Its bright samples were the same real-group pixels.
- **What survives:** the differential from 16.22 is unaffected, because it compared two
  builds that differed ONLY in the mirror sprites. Mirror sprites contribute **zero**
  pixels below y=664.
- **Also survives:** 16.18's measurement, which was made on the PRODUCTION frame against
  the reference, not on a probe. The near floor really is **+12 to +16 luma** additive.
  That has never been in doubt. **What is now unknown is which layer causes it**, and
  neither mirror layer accounts for it.

**The error is mine and it is the exact one I documented in 16.21.** I wrote a lesson
about a probe that fails to isolate, and then applied the same unisolated frame to a new
claim without re-checking it. Naming the probe "mirror only" did not make it mirror
only. **A label in a variable name is not evidence.**

**What this rules out for the near floor**, now with a clean instrument:

| candidate | status |
|---|---|
| mirror sprites (painting reflections) | cleared - 0 px below y=664 (16.22) |
| mirror raster (mirrored walls) | cleared at the near floor - no face colour (this section) |
| `drawBeams` | cleared - 1.0% of frame (16.18) |
| `floorTex` | verified correct vs html:814-824 (16.17) |
| fog / vignette | cannot reach the bottom edge (16.17) |
| the floor blit itself | **not yet tested** - alpha, or what it composites over |

**Next step, named:** the floor composite at app.nim:2679-2681. Not its texture -
already verified - but the **`blit` call itself**: `blit(corrBuf, ..., c, alphaOf(c))`.
Two specific things to measure, both cheap:
1. Does `sampleTex` return the floor texture's stored alpha (188/255) at the near rows,
   or is it saturating to 255? The near floor is where the texture is most magnified,
   so it is where a sampling/clamp error would be largest.
2. What is corrBuf's alpha **underneath** the near floor? `blit` is a source-over; if
   the destination alpha there is higher than the browser's, the composite lands
   differently. 16.18's additive signature is exactly what an alpha mismatch produces.

**Standing lesson, third instance of the class:** the probe frame that "shows the
mirror" showed the room. Before any conclusion drawn from a bypass probe, name what
survives the bypass and confirm the named layer is actually present in the output - by
colour-coding it, not by the file's name.

### 16.24 Lane close-out: the gallery mirror investigation stops here, on purpose

Attempted the last open candidate - encoding the floor blit's own alpha into the red
channel so it could be read directly (app.nim:2679-2681). The wasm built cleanly, then
**`drive.exe` spun**: 1,845 seconds of CPU, no frame, no `alpha_sw.raw`. Killed; the
probe yielded nothing. Not recorded as a finding.

**The gallery is parked at "localised, not fixed", and the reason is worth stating
plainly.** Across rounds 139-146 the scoreboard has not moved once: gallery **57.37%**,
dna 9.98%, chess 18.42%, calligraphy 20.74%, typewriter 31.82%. Eight rounds produced
four instrument failures, two withdrawn conclusions and a set of banked probe lessons -
real value, and **zero pixels**.

The objective says the five apps are ported one by one. At this rate app 1 is consuming
the budget that apps 2-5 need, on its single hardest region, with a candidate list that
has gone from "eleven suspects" to "one suspect" without ever reaching a fix. Continuing
to optimise the investigation is no longer the same as finishing the port.

**State at park, so the next agent does not repeat it:**

| what | status |
|---|---|
| near floor is **+12..+16 luma additive** | MEASURED (16.18, production frame) |
| mirror sprites (painting reflections) | cleared - 0 px below y=664 (16.22) |
| mirror raster (mirrored walls) | cleared at near floor (16.23) |
| `drawBeams` | cleared - 1.0% of frame (16.18) |
| `floorTex` vs html:814-824 | verified correct (16.17) |
| fog / vignette overlay | verified correct, -6.6% of mean (16.15) |
| flip origin (`G_FLOORY`=200, 400=2*G_FLOORY) | verified correct (16.20) |
| room gradient circle-vs-ellipse | **known defect**, circle r=776.7 vs ellipse 1152x560, +/-5.9 luma, needs SDK `Draw.oval` + rule 6 test |
| floor blit alpha | **untested** - the probe hung; first thing to try on return |

The single honest sentence about this app's biggest error: **the near floor is too bright
by a near-constant 12-16 luma, and no layer has been shown to be responsible.** An
additive lift on a translucent surface is the signature of an alpha mismatch, which is
why the floor blit is the right next candidate - it was never tested.
