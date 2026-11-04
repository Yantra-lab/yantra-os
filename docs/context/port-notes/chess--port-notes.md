# Port notes — `apps/chess` (#70 chess-study)

Pixel port of `apps/chess/070-chess-study.html` into `app.nim`.
Reference: `.board/frames/ref070.png`, 1280x816.

## How to reproduce a number

From the repo root, PowerShell:

```powershell
$env:PATH="$PWD\third_party\msys64\mingw64\bin;$env:PATH"
bash tools/build-wasm.sh apps/chess/app.nim .board/frames/chess.wasm   # MUST print "wrote"
& .\render\native\build\drive.exe .\.board\frames\chess.wasm .\.board\frames\chess_bgra.raw 1280 816 1 "wait:45"
node tools/rawswap.mjs .board/frames/chess_bgra.raw .board/frames/chess_sw.raw
node tools/pngdiff.mjs .board/frames/ref070.png .board/frames/chess_sw.raw 1280 816
```

`drive.exe` writes BGRA; `drive.nim:191-193` `copyMem`s the `seq[uint32]`
straight to disk, so the file on disk is B,G,R,A. **Always `rawswap` before
diffing.** `pngdiff` arity is `<ref> <frame> <W> <H> [tol]` with tol defaulting
to 8 — the headline metric here is always tol 8.

Scratch probes live in `.board/frames/chess/`: `box.mjs` (region count/mean),
`rows.mjs` (per-row-band profile), `inkrows.mjs` (bright-ink runs),
`darkrows.mjs` (dark-ink runs), plus assorted one-off column scans.

## Result

| | differing pixels | share | mean abs delta |
|---|---|---|---|
| as found | 258 195 | 24.72% | 9.47 |
| final | **240 588** | **23.03%** | **7.93** |

Net −17 607 differing pixels (−6.8% of the error) and −1.54 mean absolute
delta, with no tolerance loosened and nothing removed to flatter the number.

## The task premise was wrong, and it matters

The brief supplied 24.72% as the "before". Re-measuring through `rawswap`
reproduced exactly that — **but only because the number was already correct.**
Diffing the *un-swapped* raw against the reference gives **79.97%, mean 49.76**.
If anyone re-baselines this port by diffing `chess_bgra.raw` directly they will
report a 24.72% "improvement" out of a 79.97% that never existed.

## Classification: geometry/tone, not animation desync

The same frame rendered at three different times gives byte-identical diffs:

| wait | differing pixels | share | mean |
|---|---|---|---|
| 10 | 240 588 | 23.03% | 7.93 |
| 45 | 240 588 | 23.03% | 7.93 |
| 90 | 240 588 | 23.03% | 7.93 |

Perfectly flat, so this is static-geometry and colour error. The scene is
built once and holds no animated state at t=0.

## Iterations

Every row below is a build that printed `build-wasm: wrote …`, rendered,
swapped, and diffed.

| # | change | differing px | share | mean | delta |
|---|---|---|---|---|---|
| 0 | baseline as found | 258 195 | 24.72% | 9.47 | — |
| 1 | brass buttons baked at 2x with both inset shadows; separate disabled variant | 251 813 | 24.11% | 9.14 | −6 382 |
| 2 | `drawCorner` mirror fixed (per-axis flip) | 249 193 | 23.86% | 8.12 | −2 620 |
| 3 | h1 y 47.5 -> 43.04, the PORTING-FACTS scale-aware rule | 249 182 | 23.86% | 8.12 | **−11** |
| 4 | h1 y 43.04 -> 45.0, the measured ink alignment | 248 975 | 23.84% | 7.97 | −207 |
| 5 | tray inset shadow, naive `cGauss(sdRect(...))` | 278 480 | 26.66% | 8.77 | **+29 505 WORSE** |
| 6 | tray inset shadow, rescaled to a fitted 0.66 peak | 275 698 | 26.40% | 8.49 | **+26 723 WORSE** |
| 7 | tray inset shadow, distance-to-edge passed as positive | 246 104 | 23.56% | 8.04 | −2 871 |
| 8 | score-sheet text y corrections (4 lines) | 245 366 | 23.49% | 7.97 | −738 |
| 9 | title rule and status bar each down one row | 243 878 | 23.35% | 7.90 | −1 488 |
| 10 | title rule drawn as its real gradient ramp | 243 848 | 23.35% | 7.89 | −30 |
| 11 | `erfA` given oddness (see below) | 240 588 | 23.03% | 7.93 | −3 260 |

## Dead ends and things that got worse

**#3 — the scale-aware text-y rule from PORTING-FACTS does not work here.**
The rule says `capTop = y + 0.375*size`. Applying it to the 34.56px h1 gave
`y = 56 - 12.96 = 43.04`. That moved 11 pixels and bought −11 differing pixels:
nothing. The port's own measured ink offset for that string at that size is
**+11.0px, not +12.96px** — the constant was calibrated on a different
typeface. Direct ink measurement (#4) put the h1 ink on rows 56-89 against the
reference's 56-90, for −207. This is consistent with PORTING-FACTS recording
that a *constant* text-y offset previously moved this page the wrong way; the
truth is that the correction is size-dependent **and** font-dependent, so it
has to be measured per call site, not derived.

**#5 and #6 — the tray's inset shadow, two failures worth 26-29k pixels.**
`box-shadow: inset 0 2px 8px rgba(0,0,0,.5)` was simply missing, which is
visible in the reference: down the tray's middle column the port sat flat at
(38,60,49) while the reference ramped (27,43,35) -> (36,57,47). Adding it
naively made the whole frame **26% worse**. The cause is `cGauss`:

```nim
proc erfA(x: float32): float32 =
  if x <= 0.0'f32: return 0.0'f32    # WRONG: erf is odd
```

`cGauss` computes `0.5 * (1 - erfA(g/(sigma*sqrt2)))` and `sdRect` is
*negative* inside a rect — the whole interior, and the entire
distance-to-edge falloff, was being thrown away. That is a self-inflicted
wound, fixed in #11. It is documented here because the intermediate regressions
were real and would have looked like a catastrophic misport.

**#11 is the same bug in its other costume, and it was the single biggest win.**
`erfA` returning 0 below zero capped `cGauss` at **0.5 instead of 1.0**, so
every outer `box-shadow` on the page drew at half its CSS alpha —
`0.45 * cGauss` peaked at 0.225 not 0.45, `0.70 * cGauss` at 0.35 not 0.70.
Measured symptom: under the board frame the reference reads (5,8,6) where the
port read (8,12,10). Giving `erfA` its oddness fixed the frame's shadow band
under the board from 4 090 differing pixels to 831.

**Not attempted, and why:** the `<i>Study</i>` run is `#e8cf97`, not the
`#f6ecd6` the port paints the whole h1 in — but the SDK has no text
measurement, so the port cannot know where the italic run starts, and
guessing would move the glyphs rather than the colour. `.disc`'s
`radial-gradient` and `.sheet`'s 4px radius / outer drop shadow were left
alone once the row-level profiles showed the remaining sheet error is
dominated by glyph shape, not structure.

## Where the remaining 240 588 pixels are

| region | differing px | share of box | mean | delta |
|---|---|---|---|---|
| board interior `80,72 – 752,744` | 198 374 | 43.9% | 10.49 | **82.4%** |
| frame lacquer above board `36,28 – 796,68` | 5 425 | 17.8% | 8.43 | −16 214 |
| title block `834,16 – 1244,112` | 5 963 | 15.1% | 22.67 | −7 187 |
| score sheet `834,362 – 1244,780` | 7 079 | 4.1% | 4.46 | −6 524 |
| frame lacquer below board `36,748 – 796,788` | 4 557 | 15.0% | 10.20 | −6 514 |
| frame lacquer left `36,68 – 80,748` | 2 836 | 9.5% | 6.30 | −5 832 |
| buttons `834,193 – 1244,253` | 2 138 | 8.7% | 4.98 | −5 221 |
| frame lacquer right `752,68 – 796,748` | 2 399 | 8.0% | 5.07 | −5 600 |
| tray `834,264 – 1244,352` | 1 389 | 3.8% | 4.96 | −10 430 |

## The dominant term is noise, and it is irreducible

The board's `.wood::after` is a `feTurbulence` overlay. The port has no noise
generator, so the residual is structural-vs-texture, not positional:

| tolerance | differing px | share |
|---|---|---|
| 8 (headline) | 240 588 | 23.03% |
| 12 | 149 164 | 14.28% |
| 16 | 96 784 | 9.27% |
| 24 | 49 671 | 4.76% |
| 32 | 37 155 | 3.56% |
| 48 | 27 030 | 2.59% |

Inside the board interior specifically: **198 374 px differ at tol 8 but only
24 982 at tol 24.** That means **173 392 pixels — 72.1% of the entire
remaining error — are differences of 9..24, i.e. exactly the ±10/±15 grain.**
Empty board rows read 33-45% differing at tol 8 and **1.0% at tol 24**.

Of the 24 982 px that survive tol 24 inside the board, the white pieces hold
nearly all of it:

| board band | tol 24 px | share | mean |
|---|---|---|---|
| white pieces `y576-660` | 7 316 | 13.0% | 14.70 |
| white pieces `y660-744` | 9 033 | 16.0% | 16.40 |
| black pieces `y72-240` | 6 462 | 5.7% | 10.27 |
| empty `y480-576` | 980 | 1.5% | 7.90 |

So ~16 350 px is real piece-silhouette error, concentrated in the white
pieces. Ebony-on-dark falls under tolerance; ivory-on-light does not. Closing
this means reproducing the reference's exact chess-piece SVG outlines, which is
a separate piece of work from tone/geometry.

**A tolerance sweep is a diagnostic, never the headline.** The tol-24 figure of
4.76% is quoted here solely to separate grain from structure.

## Verified exact

Worth recording, because they confirm the geometry model rather than just the
error total:

- Button top row unfiltered is exactly `0.7*(255,250,230) + 0.3*(241,212,143)`
  = `(251,238,203)` — the `inset 0 1px 0 rgba(255,250,230,.7)` over the
  gradient's first stop.
- The disabled Undo plate is exactly `(195,191,179)` = the same value through
  `grayscale(.6) brightness(.8)`, confirming `.brass:disabled` and that Undo is
  indeed disabled at t=0 (`html:662`, `!game.hist.length`).
- The `#5b4320` underplate is `(91,67,32)` unfiltered, `(63,55,44)` filtered.
- Button bulk gradient matches within ±1/channel at x=1000, rows 200-248.
- Button horizontal extents (tol-20 row runs) REF
  `[834-930, 939-1034, 1043-1139, 1148-1243]` vs PORT
  `[834-930, 938-1034, 1043-1139, 1147-1243]` — within 1px, not chased.
- Empty board-square tone within ~1-3/channel: ref (198,167,129) vs port
  (197,164,126).
- Frame lacquer from row 29 down matches within 1-2 units at x=200/400/600,
  e.g. x=400 y34 `(122,81,68)` in both.
- Score-sheet rule row: ref `(112,99,60)`, port `(119,104,62)`; the three-stop
  gradient model predicts `(110,98,59)`.
- Status bar bottom hairline: ref `(53,53,33)`, port `(54,53,33)`.

## Text placement, measured

`Draw.text` paints at the paragraph box top, and this port's typeface puts cap
ink about **0.333 * size** below the `y` given. Per call site, ref vs port ink
rows before correction:

| line | size | ref ink | port ink (was) | shift |
|---|---|---|---|---|
| h1 | 34.56 | 56-90 | 59-92 | −3 (up) |
| eyebrow `A HOT-SEAT GAME FOR TWO` | 12 | 32-40 | 32-40 | already exact |
| `SCORE SHEET` / `Game 1` | 13 | 381-389 | 380-388 | +1 |
| `WHITE` / `BLACK` | 11 | 408-414 | 401-408 | +7 |
| placeholders | 16 | 408-422 | 410-425 | −2 |
| `The sheet is blank` | 15 | 442-454 | 433-446 | +9 |
| hint line | 12.5 | 759-771 | 756-768 | +3 |

The eyebrow was **already** on the reference's rows; an earlier reading that
suggested otherwise was contaminated by a phantom corner plate (fixed in #2).
The per-call corrections are genuinely different, which is the whole point —
there is no single constant that fixes this page.

## Engine / SDK defects (reported, not fixed)

1. `sdk/ui/paint.nim:63` — `Draw.text` returns `Draw` and offers no text
   measurement and no alignment. Every centring, wrap and letter-spacing in
   this page is therefore a hand-estimated constant, and no call site can
   discover where a styled run like `<i>Study</i>` begins. This is the single
   biggest structural obstacle to closing the remaining title error.
2. `libs/nimskia/src/nimskia.nim:76` documents `text` as placing at the
   "top-left at (x, y)", but `libs/nimskia/src/skia_shim.cpp:291` calls
   `SkParagraph::paint(canvas, x, y)`, which paints the **paragraph box** top,
   not the glyph ink top. The doc contradicts the behaviour, and the gap
   between the two is size-dependent (~0.333*size here, ~0.375*size for other
   typefaces) — which is exactly why a derived constant cannot be trusted.
3. The shim's `runCmds` switch has no `case 'O'`, so `Draw.alpha()` is
   **silently dropped** — emitted, never applied, no warning.
4. `.board/mean.mjs` (and `.board/frames/chess/box.mjs`, modelled on it) takes
   `<png> x0 y0 x1 y1` but `<raw> W H x0 y0 x1 y1`. PORTING-FACTS.md documents
   only the raw form, so the PNG form is easy to get wrong; feeding it the raw
   argument list silently reports `n=0 NaN`.
5. **Stale-`.wasm` trap, hit live twice.** A Nim compile error leaves the
   previous module in place, and `drive.exe` runs it happily, so `pngdiff`
   re-reports the *previous* numbers with no indication anything failed. Here
   it produced a wall of "identical" measurements for several steps. The build
   line `build-wasm: wrote … <n> bytes` must be checked every single time;
   it is the only signal that the change is live.

**Correction to item 3** (made later, by the next iteration of this port):
item 3 is **wrong** and is hereby retracted. `case 'O'` *does* exist —
`skia_shim.cpp:1412`, `alpha *= std::max(0.0f, std::min(1.0f, r.num()))` — so
`Draw.alpha()` works and is a cumulative multiplier. The earlier claim was a
false negative from grepping for the verb in the wrong place. PORTING-FACTS.md
already carries the same retraction. Do not re-raise it.

---

# Round 3 — the drop shadow, the light squares, the top bevel

**Starting point 240 588 px / 23.03% / mean 7.93 / tol-24 49 671 (4.76%).**
**Ending point 221 358 px / 21.19% / mean 7.41 / tol-24 39 605 (3.79%).**
Net −19 230 px at tol 8, −10 066 at tol 24. Every step below is a real build
checked for `build-wasm: wrote …`, rendered at `wait:8`, rawswapped and diffed.

The reference is `.board/frames/ref070.png` (1280×816 RGB8, confirmed from the
IHDR). The brief named `ref070b.png`; that file does not exist. The numbers are
flat across `wait`, so the scene is static and `wait:8` is safe — corroborated
independently by the largest `--d` stagger 0.175 s + 0.55 s duration = 0.725 s,
inside the 0.800 s capture.

## 12. Piece drop shadow — the first real win

`.pc svg{filter:drop-shadow(0 3px 2px rgba(0,0,0,.42))}` (html:101, and again
at :103 for the ebony pieces) had been listed as "not omitted" in the header but
was in fact never drawn. The giveaway was in the per-piece ink boxes: every piece
was 3–5 px short at the **bottom only**, and rows 149–155 under e8 carried a
soft dark tail the port did not have at all (ref row means 152,126,96 against a
board of 199,167,128).

`Draw` has no blur, but `Layer.filter(blur, r)` is a real Gaussian
(`skia_shim.cpp:1264`, `SkImageFilters::Blur(r*0.5, r*0.5, kDecal, nullptr)`),
so the shadow is baked once per piece type into an 88×92 layer and blitted.
**Paint the silhouette opaque and `fade` it, not fill at the shadow alpha** —
overlapping subpaths composite to 1−(1−a)² and the blur smears that lump in.

| # | change | tol 8 | mean | tol 24 |
|---|---|---|---|---|
| 12 | shadow layers, blur σ=1, offset +3 | 236 669 (22.66%) | 7.69 | 42 903 |

## 13. Light-square colour — measured, not assumed

An offline sweep over the 32 empty squares said lift `LT_BASE` by (+2,+4,+4)
and leave the dark squares alone: `0xD7B78D` → `0xD9BB91`.

| # | change | tol 8 | mean | tol 24 |
|---|---|---|---|---|
| 13 | `LT_BASE` +2,+4,+4 | **228 359 (21.86%)** | 7.53 | 41 225 |

−8 310 at tol 8, better than the −3 434 the 32 empty squares predicted, because
the same lift also moves the piece-bearing light squares.

**A trap worth recording.** The same sweep offered `DK_BASE` blue −4, which
*also* looked attractive: the 32 dark squares mean +4.3 in blue. Applying it
gains 80 px at tol 24 and **loses 3 297 at tol 8**. Narrowing a grain window
from one side only pushes half the noise population out the other side. Mean
offset is the wrong statistic here; the sweep must be scored at tol 8.

## 14–18. Tuning the shadow's sigma — with two regressions

The reference's tail decays more slowly than σ=1 implies, so σ was swept.
Sweeping `l.filter(blur, r)` (σ = r/2):

| # | change | tol 8 | mean | tol 24 |
|---|---|---|---|---|
| 14 | σ = 1.5 | 225 833 | 7.49 | 40 721 |
| 15 | σ = 2.5 | **223 201** | 7.45 | 40 370 |
| 16 | σ = 3.5 | 225 258 ✗ **regression** | 7.48 | 40 615 |
| 17 | σ = 3.0 | 224 354 ✗ **regression** | 7.47 | 40 466 |
| 18 | σ = 2.0 | 223 264 | 7.46 | 40 412 |
| 18b | offset +4 (σ=2.0) | 224 439 ✗ **regression** | 7.47 | 40 437 |

σ 2.0 and σ 2.5 are a plateau (63 px apart, i.e. noise). Note that CSS
`blur(2px)` nominally means **σ=1**, and the fitted optimum is ~2.5× that: the
reference's `drop-shadow` tail does not match the radius the CSS spells. The
offset stays at +3.

## 19. The shadow silhouette must include the stroke

The CSS filter applies to the element's **rendered** output, stroke included.
Adding the 1.5-wide stroke (1.26 px after the shim's `cv->scale`, confirmed at
`skia_shim.cpp:1396-1400`) to the silhouette is both more faithful and better:

| # | change | tol 8 | mean | tol 24 |
|---|---|---|---|---|
| 19 | σ = 2.5, fill + stroke silhouette | **221 973 (21.25%)** | 7.44 | 40 223 |

## 20. The frame's top bevel was never drawn

Row 28 was wrong by ~760 px — a full row, uniformly, the entire frame width.
The cause: `bakeFrame` tests `ly < 1.0` for `inset 0 1px 0 rgba(255,230,200,.22)`,
but the bake is half-size so `ly = (j+0.5)*2` is **exactly 1.0** on the top row
and the test never fired. (Lines 526-527, the ring test, are dead for the same
reason — the ring is drawn by the `B` verb instead.)

The paint order is the reverse of the CSS list. A literal reading puts the
`inset 0 0 0 1px rgba(0,0,0,.6)` ring on top and predicts `0.4*lit` =
(52,37,31); the reference reads (84,66,55), which is the ring applied **first**
and the highlight **second**: `0.78*(40,22,18) + 0.22*(255,230,200)` =
(88,68,58). Drawn after the `B` rim, not before it.

| # | change | tol 8 | mean | tol 24 |
|---|---|---|---|---|
| 20 | 1px `rgba(255,230,200,.22)` over the frame top | **221 358 (21.19%)** | 7.41 | 39 605 |

## The grain is a floor, and here is the number for it

Splitting every region into "differs at tol 8" and "still differs at tol 24":
the gap is grain, and what survives tol 24 is structure.

| region | tol 8 | tol 24 | grain % |
|---|---|---|---|
| board interior | 179 759 | 15 534 | **91.4** |
| rank 8 / rank 7 (black pieces) | 21 535 / 22 048 | 1 265 / 1 122 | 94.1 / 94.9 |
| ranks 6–3 (empty) | 17 433 / 25 315 / 23 864 / 18 779 | 79 / 314 / 202 / 174 | 99+ |
| rank 2 / rank 1 (white pieces) | 26 203 / 24 582 | 5 346 / 7 032 | 79.6 / 71.4 |
| frame lacquer (4 bands) | 14 602 | 9 231 | 30–45 |
| title block | 5 963 | 5 575 | **6.5** |
| score sheet / hint line | 5 402 / 1 221 | 4 310 / 1 073 | 20.2 / 12.1 |
| page ground | 8 063 | 98 | 96–99.7 |

The page ground is 18.41% of its area at tol 8 and **0.06%** at tol 24. That is
`feTurbulence` grain and it is not reachable: reproducing Chrome's
`fractalNoise` baseFrequency/numOctaves/seed and its conic quarter-tile mask
would mean reimplementing the filter, and a wrong generator makes the score
worse, not better. It is not chased here.

## Where the remaining non-grain error is, ranked

| region | tol 24 px | what it is |
|---|---|---|
| board ranks 1–2 | 12 378 | piece fills are flat where CSS uses a gradient |
| frame lacquer | 9 231 | lacquer gradient shape near the edges, 4 corner pieces |
| title block | 5 575 | typeface: the port's h1 ends at x1147, ref at x1158 |
| score sheet | 4 310 | typeface, same cause |
| buttons / status / tray | 3 833 | mixed |
| hint line | 1 073 | typeface |

## Piece census — no missing pieces

Per-square ink boxes (threshold 30) over all 64 squares: **all 32 pieces are
present, none extra, none the wrong shape.** x placement is exact to ±1 px and
the ink box top is now aligned to 0–1 px on every square. The three
"MISSING IN PORT" hits the tool reports (3d, 4e, 5h) are grain: they appeared
only after `LT_BASE` moved, they have no structural shape, and their counts
scale with the threshold. Not chased.

## The piece gradient — a real defect, and it is blocked

`.pc.w{fill:url(#gIv)}` and `.pc.b{fill:url(#gEb)}` (html:210-215) are 4-stop
linear gradients, ~66 units of range for ivory and ~82 for ebony. The port fills
pieces flat, so a white piece body reads ~24 off in R at its shadowed edge.
This is the largest single reachable block left (12 378 px at tol 24).

**It cannot be done with the current primitives, and the reason is specific.**
`runCmds` accepts exactly these verbs: `M L Q C A Z F S R B E G T I P p b Y X
V K O`. `K` (`skia_shim.cpp:1408`) is the only clip and it is
`clipRect` — an **axis-aligned rectangle**, not a path. So there is no way to
express *path ∩ gradient*, which is what a CSS `fill:url(#gradient)` on a
`<path>` means. `SkGradientShader` is used at `skia_shim.cpp:441`, but only by
`yk_rrect_gradient` (line 432), a standalone helper that draws a rounded **rect**
and is not exposed as a `Draw` verb.

Reported as defect 6 below. Not worked around, not approximated with a flat
mid-stop — the flat fill is already the honest approximation and a wrong ramp
would be a second guess on top of the first.

## Engine / SDK defects (round 3)

6. **No gradient fill and no path clip.** `runCmds` (`skia_shim.cpp:1330-1413`)
   has no gradient verb and its only clip, `case 'K'` at line 1408, is
   `clipRect`. Every CSS/SVG `fill:url(#gradient)` is therefore unreachable,
   which for this page means all 32 chess pieces. `yk_rrect_gradient` at line 432
   shows the shim already knows how to build a linear shader — it just is not
   reachable from `Draw`. Adding a `clipPath` verb plus a gradient-fill colour
   argument (or a `sk` verb taking two points and N stops) would unlock the
   pieces here and a lot of vector art elsewhere.
7. `Draw.text` cannot name a typeface (see defect 1). For this page that alone
    costs ~11 000 px at tol 24 across the title, score sheet and hint line: the
    page's serif renders the h1 **323 px** wide where the port's hardcoded face
    renders it **311 px**, so the accumulated tracking drifts ~12 px from start
    to end and almost no glyph overlaps. There is no measurement API to fit the
    advances against (defect 1), so this is not fixable from the app side.

    > **CORRECTED 2026-10-04 (round 156).** True of `Draw.text`, false of the engine.
    > `Draw.textFace(x, y, size, c, family, s)` takes a family (verb `'N'`,
    > `sdk/ui/paint.nim:72`) — `apps/typewriter` calls it 11 times. **The 11 000 px is
    > not a Yantra limitation; it is this port filing item 7 as "cannot" rather than
    > "not yet done here".** Item 7 belongs off the gap list and on the task list:
    > move these runs to `textFace`, re-measure, expect a large drop.

## Tools added this round (`.board/frames/ch2/`)

`regions.mjs` per-region diff at tol 8 **and** tol 24 plus the %grain gap ·
`scan.mjs` actual RGB along a row or column, ref vs port · `text.mjs` per-row
ink count and x-span for a text band · `blockmap.mjs` coarse tol-24 block count
for a rect · `dhist.mjs` signed-delta histogram and constant-shift payoff ·
`pieces.mjs` per-square ink bbox · `rowprof.mjs` · `pix.mjs` · `ascii.mjs` ·
`squares.mjs` per-empty-square colour plus shift sweep.

`pngdiff.mjs:133` gates its band map on `if (rows[y] && cols[x] && ...)`, so it
skips every zero-difference row and column and the band map is not to be
trusted. The headline `differing pixels` / `mean |delta|` are unaffected.

# Round 4 — the reachable error (this lane)

Baseline reproduced exactly: **221 358 / 21.19% / mean 7.41** at tol 8,
39 605 at tol 24. Every build checked for `build-wasm: wrote`, rendered at
`wait:8`, `rawswap`ped, then diffed — `regions.mjs` re-validated each round
(its regions sum to within 0.05% of the `pngdiff` headline).

**Result: 214 943 / 20.58% / mean 7.09**, tol 24 **34 621**. Net
**−6 415 @ tol 8, −4 984 @ tol 24, mean 7.41 → 7.09.**

| round | change | tol 8 | tol 24 |
|---|---|---|---|
| 0 | baseline | 221 358 | 39 605 |
| 1 | `.coords` line-box centring | 220 952 | 39 197 |
| 2 | brass corners baked | 215 775 | 35 014 |
| 3 | coord x nudge + status box | 215 141 | 34 808 |
| 4 | disabled-button underplate filter | **214 943** | **34 621** |

## 12. The `.coords` labels were 4px low — `place-items:center` centres the LINE box

`drawCoords` centred each glyph on a box of height `size` (the em box). CSS
`place-items:center` centres the **line box**, ascent + descent ≈ **1.435em**.
Solving `FY + (FR − H)/2 + inkOffset` against the measured ink top gives
H = 26.5px for size 18.48 — `LH = 0.7175`, half the line box.

The port's own two bands were self-consistent before this (ink top exactly 24px
from each 44px band's top) and so were the reference's (20px) — a pure
centring-constant error, not a per-row one. After: all eight top file labels
land on **exactly** the reference's ink rows (48-56, and 45-56 for ascenders).

## 13. The brass corners were a BAKE, not a gradient-fill blocker — biggest win of the round

The plate is `fill:url(#gBrass)` (html:226), a 5-stop linear gradient on a path,
which is defect 6 below and normally unreachable. But **defect 6 only blocks
path ∩ gradient; it does not block baking one.** `bakeFrame` already bakes a
*radial* gradient into a Layer pixel by pixel, so the same route opens here.

The old `drawCorner` drew the ornament with `rect`/`circle`/`line` at flat
`#d9b56a` (the 0.35 stop). Measured across the plate, the reference ramps
**235,207,142 → 207,171,96** while the flat fill was out by up to 36/channel
over the *whole* plate: **5 116 differing px at tol 24 across four corners,
58% of the frame lacquer's structural error.**

Rebuilt as four baked 168² Layers (one per orientation — the ornament is not
symmetric, three screws at 9.6,9.6 / 47,9.6 / 9.6,47, so the mirror is baked):

* the L-bracket as a real SDF — `sdRect` ×2 for the arms, `max(sdDisc, plane)`
  for the two r6.5 outer semicircles, and the **concave r9 fillet** at the
  inner corner: a quarter disc centred on (16,16) that adds a lobe *into* the
  notch. The old two-rect drawing left that notch open.
* `gBrass` at 135° over the path bbox [3,61.5]² via `linT`
* `gScrew` radials, the three slots, both hairline strokes, the `#4d3713` ring
* the previously-omitted `filter:drop-shadow(0 2px 2px rgba(0,0,0,.5))` —
  three separable box passes, r=8, giving σ = √(3·(2r+1)/12) = 2.06 bake px
  against the CSS σ = blur/2 = 1 device px = 2.0 bake px

The plate now matches within **0-2/channel**. Frame lacquer tol 24:
9 231 → **4 640**.

### TRAP: a mirrored corner must blit from the box's LEFT edge, not the anchor

`cx`/`cy` are the element box's anchor **edge** (`right`/`bottom` of −3px).
Blitting the layer from the anchor put the top-right plate at x 799..883 — on
top of the title block. One root cause, two misleading symptoms: the corners
looked worse *and* the title block appeared to regress 5 575 → 6 878 @ tol 24
when nothing had changed to it. **A region table is what caught it** — the
title "regressing" in the same build that touched only corners is the tell.
Fix is `x0 = anchor − CBOX` when flipped; the mirror is baked, the blit origin
still has to move.

## 14. Status bar: STY was underdetermined by the plate, fixed by the border

`STY`/`STH` were 130.5/48.5 → box [130.5, 179.0]. That is right at the
bottom (the edge line at 178.5 covers row 178 full, and it measured exact) but
puts the top edge line at y=131.0, where a 1px stroke spans rows 130 **and**
131 at half strength. Measured reference: one **full**-strength row at 130,
(52.6,53.3,33.3) mean, falling straight to (14.4,23.7,18.5) at 132.

The plate fill alone cannot tell 130.0 from 130.5 — it is uniform there, so any
measurement of the plate is equally happy with both. Only the 1px border
discriminates. **STY = 130.0, STH = 49.0**, both edge lines at a row centre.
−442 @ tol 8.

Only −24 @ tol 24, and that is not a disappointment: the error being fixed is
~18 units, which is *below* tol 24 by construction. **tol 24 is the wrong
instrument for a sub-24 error** — scoring the fix at tol 8 is what showed it
worked. Reach for tol 8 whenever the residual is a few units.

## 15. The disabled button's `box-shadow` IS filtered; its inner band is not

`#5b4320` underplate on the `:disabled` Undo button read (91,67,32) — the
*unfiltered* colour. `html:143` `filter:grayscale(.6) brightness(.8)` applies to
the element's own box-shadow too: luma = 0.299·91 + 0.587·67 + 0.114·32 = 69.6,
lerp 0.6 toward it, then ×0.8 → **(63,55,44)**, which is what the reference
reads at col 870 row 252. The `desaturate` proc already existed and already
documented this; it was applied to the icon ink but not to the underplate.
−198 @ tol 8, −187 @ tol 24.

The `rgba(0,0,0,.30)` inner band deliberately needs **no** change: black at
alpha `a` under `brightness(k)` is `plate·k·(1−a)` whichever order you apply
it. Worth stating so the next lane does not "fix" it.

## What is now known to be unreachable

* **board interior 15 534 @ tol 24** — 32 gradient-filled pieces (defect 6).
  Ranks 1-2 alone are 12 378. Rank 8's 1 265 is the top edge.
* **title 5 575, score sheet 4 310, hint 1 073, tray 1 202, buttons 1 215,
  status 1 205 @ tol 24** — every one of these is now *localised to glyphs*.
  This was verified, not assumed: `blockmap.mjs` shows the tray's entire
  1 202 confined to x 834..954 (everything right of 954 is **exactly 0**),
  which is the two `.who` labels, not the move list. All of it is defect 1.
* **The lacquer's own smooth gradient matches within 1-2 units almost
  everywhere.** Its tol-24 error is localised high-contrast spots (corners,
  the `.frame::before` hairline, the coord labels), *not* gradient shape. The
  earlier reading of that blockmap as "the lacquer gradient is wrong" was
  simply wrong, and acting on it would have cost the round.

## Still open, ranked

1. **Lacquer bottom inset** `inset 0 -2px 6px rgba(0,0,0,.5)` is modelled in
   `bakeFrame` as a **linear** ramp; Chrome renders a Gaussian (σ = 3).
   Measured at col x=400: port flat (43,19,14) across rows 749-785 while the
   reference ramps 35→43 (rows 749-765) and 43→33 (778-784) — port too bright
   by up to 7.9. Reachable via the same bake; gains are tol-8-scale.
2. **Coord x nudge is a fudge.** `CDX = 2.0` from a per-label spread of
   0..4 (mean 1.75). It is an advance-width correction and `centred`'s 0.667
   estimate is still wrong underneath. Under the typeface block this is risky
   — it was accepted because it improved **both** tolerances (−192/−182), never
   on mean offset alone.
3. **Button drop band** `0 8px 14px -4px rgba(0,0,0,.55)`: port reads
   (19,30,24) at rows 254-258 where the reference reads (13,21,17) — the port's
   shadow is too weak. Only 0 @ tol 24 now, 305 @ tol 8.
4. **Rank labels (left/right columns) were never cleanly measured** — the
   corner ornament overlaps x 38-47 and swamped the threshold. Now that the
   corners are a clean bake, re-measure with `runs.mjs` on the bands
   `36,72-744,80` and `800,72-744,844`.

## Reusable lesson

The brief's instinct to distrust a region table's *interpretation* was right
twice, in both directions. `.coords` and the brass corners were both reported
as "lacquer gradient error"; both were something else entirely — one a
centring constant, one a gradient that was simply unreachable *by the route
the notes had assumed*. And the title's phantom regression was a corner drawn
in the wrong place. **Blockmaps localise; they do not explain.**

---

# Round 5 — the piece gradient bake, and a confirmed defect that was not one

Baseline re-measured first and reproduced exactly: **214 943 @ tol 8 (20.58%),
mean |Δ| 7.09, 34 621 @ tol 24**, 1280x816, `wait:8`.

| # | change | tol 8 | tol 24 | mean |
|---|---|---|---|---|
| 0 | baseline (round 4 close) | 214 943 | 34 621 | 7.09 |
| 1 | `B` verb's missing 7th argument (`1.00`) | 214 943 | 34 621 | 7.09 |
| 2 | piece gIv/gEb gradient baked (6 types × 2 colours) | **200 664** | **30 812** | **6.77** |

Net for the round: **−14 279 @ tol 8, −3 809 @ tol 24, mean −0.32**.
The entire win is inside `board_interior 80,72-752,744`; all eleven regions
were re-measured and **every other one is byte-identical to its round-4 value**,
so nothing regressed.

## 1. The `B` verb — a real defect, and the stated consequence was false

`app.nim:710` emits six arguments; `skia_shim.cpp:1343-1344` reads seven
(`x y w h radius COLOR width`), so `CmdReader::num()` (`:1188-1195`) hit the
trailing `;`, `strtof` failed, and it returned 0. That much is real, and the
code comment claiming otherwise was wrong.

**But the brief's two claims about the consequence are both wrong**, and it
matters because they are the kind of claim that costs a round:

* It is **not** the piece rim. `app.nim:710` is inside `drawFrame` — it is the
  **frame's** border, `inset 0 0 0 1px rgba(0,0,0,.6)` from html:58. The piece
  rim is drawn through a different verb entirely: `d.svgPath(path, x0, y0, sc,
  strC, 1.5)` at `app.nim:1065`, which is the `S` verb, and `S` *does* pass its
  width.
* A zero stroke width does **not** draw nothing. Skia renders
  `kStroke_Style` at width 0 as a 1px **hairline**. Measured before the fix, at
  col x=36 the port read (25.9,9.3,5.7) against a lacquer of (65.7,24.0,14.8)
  — a ratio of 0.394, which is exactly `1 - 0.6`, the `rgba(0,0,0,.6)` inset.
  The rim was already there, at the right strength, in the right place.

The fix (append `1.00`, read from html:58's `1px` — not guessed) is correct
regardless and is banked, but it buys **exactly 0 pixels** at both
tolerances: the frame is byte-identical. On this geometry Skia's hairline and
a 1.0 stroke are the same pixels. See `apps/chess/.board/c2/`.

## 2. The piece gradient — the bake DOES reach what a Draw verb cannot

This was the one item on the list marked "blocked", with the hint to apply the
brass-corner trick. It works, and it is the largest single win available on
this page. The port now rasterises the pieces itself:

* a small SVG path parser (M/L/H/V/C/A/Z, abs + rel) with beziers flattened
  at 20 steps and arcs at 1 step per 2°, in `flattenPath`;
* antialiased **nonzero winding** — 4 scanlines per pixel row with exact
  horizontal span coverage, in `fillCov`;
* a stroke band from a distance-to-polyline that is only evaluated near the
  boundary (`markNear` marks candidates from the scanline crossings; a full
  w×h×|p| field would have been 64M ops across all 31 paths);
* the gradient sampled per pixel.

`path ∩ gradient` is still unreachable (defect 6 stands: `runCmds` has no
gradient verb and its only clip is `clipRect`), but **the engine never has to
do the intersection** — that is the whole trick, and it is why the corner bake
generalises.

### The gradient is PER-PATH, not per-piece

`gradientUnits` defaults to `objectBoundingBox`, which is the bbox of the
element that **references** the gradient — each `<path>`, not the enclosing
`<svg>`. This is worth stating because the union is the intuitive guess and it
is wrong by 22 units. Measured on the a1 rook at y=690, which crosses the
crenellation path (bbox x31–69, y23–40.5):

| model | predicted at x=134 | reference |
|---|---|---|
| per-path bbox | (190.8,164.4,124.8) | **(189,162,122)** |
| union of all five rook paths | (211.5,191.0,155.7) | (189,162,122) |

Result: the piece body now matches the reference to **d = 0–1 across the whole
body** (x=110→136 read 248,242,228 → 189,162,122 in both), and the black
pieces match to d ≤ 1. The silhouettes did not move.

### Paint order changed as a side effect

The old code replayed each path as *stroke then fill* because `F`+`S` on one
path is broken (reference/16 §1); that loses the stroke's inner half, so the
outline was 0.63px instead of 1.26px. The bake composites fill-then-stroke,
which is SVG's actual order and what Chrome rendered, so the full outline is
now visible. This is confounded with the gradient change in the same build —
the measured −3 809 is the net of both, not the gradient alone.

### Two bugs worth writing down

Both were found by a **native** harness, `.board/c2/raster_test.nim`, which
compiles the same procs with `nim js` and prints bboxes and per-row ink. The
wasm render hung for **5+ minutes** on the first attempt; the harness made it a
one-line read. Native `nim c` is not available here (msys gcc cannot execute
`cc1`) — `nim js -d:nodejs` is the workaround, and it is fast enough to
iterate in seconds.

1. **The M-pair re-read.** A command must consume numbers only when a number
   actually *follows* it. The obvious formulation — always run `case cmd` —
   re-reads `M24 91c…`'s `91` as an implicit lineto, because M leaves
   `cmd = 'L'` behind, silently corrupting `cx` on every path shaped
   `M<a> <b><letter>`.
2. **`xs` was never cleared between scanlines.** `crossings` appends to a
   `seq` that lived across the whole loop, so every scanline inherited the
   previous one's crossings. The symptom was deceptive: the top of a shape was
   correct and it then bled to the bottom of the tile — the rook base filled
   device rows 69–91 instead of 69–76. **A rasteriser that fills too much looks
   exactly like a rasteriser with a geometry bug.** The per-row ink table from
   the harness, not the overall image, is what caught it.

## What this re-ranks

With the board interior down to **11 725 @ tol 24**, the remaining structure
budget is:

| region | tol 24 | reachable? |
|---|---|---|
| board_interior | 11 725 | partly — see below |
| title | 5 575 | defect 1, glyphs |
| scoresheet | 5 383 | defect 1, glyphs |
| frame_above / below / left / right | 1 648 / 1 169 / 882 / 787 | mixed |
| buttons / status / tray / hint | 1 215 / 1 205 / 1 202 / 1 073 | glyphs + defect 5 |

The pieces are no longer "blocked": what is left inside the board is ~6 500 px
of silhouette-scale error (deltas 45–200, the dark ebony pieces against light
board) and ~4 400 px of tone (25–45). **The gradient axis is now nearly
exhausted; what remains on the pieces is geometry, not colour**, and that is a
much harder problem than a ramp.

## Engine defect confirmed (not new, but now precisely stated)

**Defect 6 is real and load-bearing.** There is no way to express
`path ∩ gradient` through `Draw`: `runCmds` verbs are M L H V C A Z F S R B E
G T I P p b Y X V K t s o O, plus `svgPath` via the SDK — no gradient, and the
only clip is `clipRect`. `Canvas.fillGradient` (`nimskia.nim:133`) exists but is
**rrect-only** and is not reachable from an app module. Only a bake gets there.

Also re-confirmed, cheaply: **a `.wasm` byte count is not a build fingerprint.**
Three builds of this app differed by 4 bytes (325 822 → 325 826 → 373 889) for
three genuinely different programs, and the render is what identified them.

## 3. `inset 0 -2px 6px` — worth zero pixels, and it took the page down

Two things happened here, and the second is worth more than the first.

### The latent `erfA` stack overflow (the real find)

Modelling the bottom inset properly means clamping distance-to-edge at 0. The
first build with that clamp **rendered nothing at all**:

```
crashed=[trap in yantra_main: error while executing at wasm backtrace:
    0:  0x348c0 - ch.wasm!erfA__app_u197
    1:  0x3497f - ch.wasm!erfA__app_u197
   ... 19 identical frames ...
Caused by: memory fault at wasm address 0x10000000c
           wasm trap: out of bounds memory access
] now=800.0
```

`erfA` exploited oddness with `if x <= 0.0: return -erfA(-x)`. IEEE says
`-0.0 <= 0.0` is **true**, so `erfA(0.0)` recurses on itself until the stack
dies. Rounds 1-4 never hit it because no caller ever passed exactly 0 — it is
a **latent trap that any caller passing 0 will find**, and it presents as an
unattributable whole-app memory fault, not as an error in the thing you
changed. Fixed with `if x < 0.0`: `x = 0` needs no special case at all, because
`ERF_TAB[0]` **is** `erf(0) = 0` and the table branch already answers it. The
comment now says so.

This is the third time on this page that a plausible one-token change has been
the whole difference, and it is the reason the crash was worth more than the
shadow: it was not reachable by reading, only by doing.

### The shadow itself: a measured zero

| | tol 8 | tol 24 | mean | band worst |
|---|---|---|---|---|
| linear 6px ramp, half-size bake | 200 664 | 30 812 | 6.77 | dR 7 |
| fitted Gaussian (σ 3.69, edge ly 757.33) | **200 659** | **30 812** | **6.76** | **dR 2** |

**−5 pixels at tol 8, zero at tol 24.** Predicted before the build, from the
histogram: the band's worst |Δ| was 7, under the tol-8 threshold, and the
1 648 px that `frame_below` still carries at tol 24 are coord-label glyph
edges, not this shadow. The fit is right (d≤2 across the whole band, from d≤7),
but a correct fix that cannot move a threshold is a correct fix and nothing
else.

Two things were wrong, not one. The old model was a *linear* ramp where Chrome
draws a Gaussian; and because the bake is half size (`ly` steps by `B/FRW =
2.0`), the guard `ly > B-2` fired on **one bake row out of 380** — so the
shadow was effectively *absent*, not merely misshapen. Measured alpha at the
bottom edge (col 400; col 120 agrees to 1, so it is uniform in x):

    row  778 780 781 782 783 784 785 786
    a     .024 .024 .048 .071 .119 .167 .214 .286

Fitting `0.5 * cGauss(g, sigma)` gives the shadow edge at ly = 757.33 with
**σ = 3.69** — about **1.23×** the CSS nominal 3. That is the same direction and
roughly the same magnitude as every other blur this port has needed, and it is
now the fourth independent measurement of the same effect. It is a property of
this port's baking, not of this page.

## Round 6

Baseline carried in: **200 659** @tol8 (19.21%), **30 812** @tol24 (2.95%), mean 6.76.
Chess reference noise floor, re-measured this round against
`.board/probe/refr2_chess.png`: **18 029 px (1.73%) @tol8**, **14 761 px (1.41%)
@tol24**. Quote every figure against that spread.

### 6.1 Board tone: the squares are individually randomised, not one fixed wash

`bakeBoard()` applied a single fixed 90° wash at fixed α 0.05/0.06 to all 64
squares. `070-chess-study.html:537-549` instead runs an LCG per square
(`seed = 90210`, Park–Miller `seed*16807 % 2147483647`) and derives **three** CSS
custom properties per square: `--ga` (gradient angle, light squares
`88 + rnd*6`, dark `-3 + rnd*6`), `--v1` (`0.02 + rnd*0.07`), `--v2`
(`0.02 + rnd*0.08`). The port now replays that LCG and stores angle + both alphas
per square. Note the ordering: `light` is decided from the **raw** index `s`
*before* the flip at html:557, so the light/dark test is
`((s shr 3) + (s and 7)) and 1 == 1` on the un-flipped index.

`int64` is mandatory here — `seed*16807` reaches 3.6e13 and silently overflows
int32.

Diagnostic proof the fix was correct, and the reason to trust it beyond the
score: the ranks with **no pieces on them** went to ~zero structural error
(rank5 314 → 2, rank6 79 → 30, rank4 202 → 26 @tol24). Error there could only
have been board tone, and only board tone changed.

    board interior @tol24   11 452   ->  11 035
    whole frame  @tol8    200 659   ->  179 631   (-21 028)
    whole frame  @tol24    30 812   ->   30 122   (   -690)
    mean                    6.76     ->    6.48

The tol-8 move is ~12× the 1.73% floor. **The tol-24 move of -690 is inside the
1.41% floor band** and must not be claimed as significant on its own; the
tol-8 figure is the honest headline for this change.

### 6.2 Item 3, piece geometry — `flattenPath`'s arc branch was wrong

This is the "drawn from the wrong source geometry" item. It was **not** the path
data: all six symbols in `app.nim:386-451` are verbatim against
`070-chess-study.html:235-299`, re-checked character by character. The defect is
in the rasteriser that consumes them.

`app.nim:1215-1226` computed the SVG arc's start and sweep angles with
`arccos` plus a cross-product sign, and derived the *endpoint* direction from
`(ox - rx*cs - cx, oy - rx*sn - cy)` — a vector that is not the endpoint at all.
For a semicircle both are wrong. Replaying both formulations
(`apps/chess/.board/ch6/arcdbg2.mjs`) on the five round shapes in the pieces:

| shape | old endpoint error | new |
|---|---|---|
| pawn head `M50 32.5a13.5…` | 24.9447 units | 0.0000 |
| bishop ball | 8.3149 | 0.0000 |
| queen ball (x30) | 5.3585 | 0.0000 |
| queen ball (x57) | 5.3585 | 0.0000 |
| queen finial | 8.4997 | 0.0000 |

24.94 units is nearly **twice the 13.5-unit pawn head radius**: the flattened arc
never reached its own endpoint, so the fill closed on a wedge and every round
shape in every piece had a bite taken out of it, with the blurred drop-shadow
layer showing through. The old code produced th0 = 90° where -90° was correct
and dth = 225° where 180° was correct.

Confirmed on the frame before the fix — e2, row 620, the port painted the pawn
head as a flat `121,104,81` where the reference carries a continuous bright
ivory fill ramping `232,219,193 → 193,168,129`: a ~105-level dark hole straight
through the middle of the piece.

The fix replaces the angle helper with `atan2` on the start and end radii in the
ellipse's own frame:

```nim
let u1x = (cx-ox)*cs + (cy-oy)*sn
let u1y = -(cx-ox)*sn + (cy-oy)*cs
let u2x = (x-ox)*cs  + (y-oy)*sn
let u2y = -(x-ox)*sn  + (y-oy)*cs
let th0 = arctan2(u1y, u1x)
var dth = arctan2(u2y, u2x) - th0
```

Nim spells it `arctan2`, not `atan2`.

    board interior @tol24   11 035   ->   9 130   (-1 905)
    whole frame  @tol8    179 631   ->  177 501   (-2 130)
    whole frame  @tol24    30 122   ->   28 217   (-1 905)
    mean                    6.48     ->    6.32

Ranks 1-2 (white) 6 687 → 5 497; rank 7 2 439 → 1 730; ranks 3-6 unchanged, as
expected for empty ranks.

### 6.3 Reported, not fixed: an unexplained dark lens on d3

The reference carries a dark lens of ~138 reference-only pixels at the top of
d3 (rect x332-416 y492-576, rows 497-507) that the port does not have at all.

* **It is real, not noise.** It reproduces independently in the second chess
  capture `.board/probe/refr2_chess.png` — 748 ink px in that rect there, 0 in
  the port (`apps/chess/.board/ch6/glyph.mjs`).
* **It is not `.sq.ring::after`.** Fitting a circle to the reference-only ink
  (`apps/chess/.board/ch6/ring.mjs`) gives radii spread over 13.2 .. 58.7 with
  median 47.7, whereas that gradient's band on an 84px square is
  r = 36.8 .. 44.0. No match.
* Only d3 is affected; the same rows on a-, b-, c-, e-, f- and g-file are clean.

At 199 px @tol24 it is small. Flagging rather than guessing: **I cannot attribute
it to a named CSS construct.**

### 6.4 Ruled lines in the score sheet — checked, no change needed

The 26px repeating rule (`rgba(70,110,150,.18)`, html:162) was suspected of a
2px phase error. Measured with `apps/chess/.board/ch6/lines.mjs`: reference dark
rows at 387, 413, 439; port at 387, 413, 439. **Pitch and phase agree exactly** —
no change made. The residual at that band is glyph error.

## Final state

| | tol 8 | % | tol 24 | % | mean |
|---|---|---|---|---|---|
| round 4 close | 214 943 | 20.58% | 34 621 | 3.31% | 7.09 |
| round 5 | 200 659 | 19.21% | 30 812 | 2.95% | 6.76 |
| round 6.1 board tone | 179 631 | 17.20% | 30 122 | 2.88% | 6.48 |
| **round 6 close** | **177 501** | **16.99%** | **28 217** | **2.70%** | **6.32** |

Cumulative this round: **-23 158 @tol8**, **-2 595 @tol24**, mean **-0.44**.
The reference noise floor is 1.73% / 1.41% @tol8 / @tol24, so the headline
tol-8 figure stands well clear of it; the tol-24 figure clears the floor by
about 1.4× and, more importantly, moved in a *concentrated* way (board interior
-1 905 out of a total -1 905) rather than spread evenly, which is what
distinguishes a real fix from noise.

### What is left, and what is reachable

| region | @tol24 | reachable? |
|---|---|---|
| title h1 | 4 208 | **no** — defect 1, no typeface on the wire |
| ranks 1-2 pieces | 5 497 | partly — see below |
| frame lacquer (4 bands) | ~4 458 | tone matches to d≤4; residual is fine structure |
| score sheet | 4 310 | **no** — glyphs (rule phase verified correct, §6.4) |
| ranks 8/7 pieces | ~3 376 | partly |
| d3 lens | 199 | **unattributed**, §6.3 |
| status bar / hint / tray | ~3 480 | **no** — glyphs |

Board interior 9 130 @tol24, spread ~250-510 across the 32 occupied squares with
no single square dominating. **The piece *silhouette* is now correct** — the arc
fix removed the systematic hole — and the per-square body tone agrees to d≤2.
What remains on the pieces is the gradient-fill mismatch inside the silhouettes,
which is defect 6 (`runCmds` has no gradient verb; its only clip, `case 'K'` at
`libs/nimskia/src/skia_shim.cpp:1408`, is `clipRect`, so path ∩ gradient cannot
be expressed).

### Still open, and worth more than pixels

The **intermittent `out of bounds memory access`** in #70. Not reproduced this
session: 3 renders, `crashed=[]` empty every time. Candidate class per the brief
is unguarded array indexing, `floor`/`sqrt`/`log` of zero or negative, or loop
bounds from division. Note that 6.2 *removed* an unbounded-arc code path (the
old one produced a 225° sweep where 180° was correct), which is adjacent to that
class — but that is not proof it was the same bug and it is not claimed as such.

**The single most valuable thing this lane produced is not a pixel count.** It is
`apps/chess/.board/c2/raster_test.nim`: a native `nim js` harness that runs a
bake in seconds instead of a 5-minute wasm render, prints exact bboxes and
per-row ink, and turned two bugs and a stack overflow into one-line reads.

---

# Round 7 — the reference, not the port

**Starting point**: the baselines quoted in the brief, re-measured here:
shipped ref070.png vs the unchanged port: **58.54% / 45.51% @tol24 / mean 52.68**.
Much worse than the round-6 close (17.20% / 3.70% @tol24 / mean 6.32),
but the port is unchanged — the reference moved, not the code.

## The reference is still a 1296-wide layout cropped to 1280×816

`capture-ref.ps1`'s R18 probe reports `clientWidth/clientHeight = 1280×816`,
but Chrome's `100vw`/`100vh` resolve to the **window size** (1296×911).
The script crops the 1296-wide screenshot to 1280×816, producing a PNG that
looks right (correct left-edge desk border) but whose layout is a 1296-wide
one shifted left and cut at the right.

Independent captures at each window size, decoded with two independent
PNG decoders (both agree; crop.mjs's re-encode was not the cause):

| window | board pitch | board x | panel x | port matches? |
|---|---|---|---|---|
| **1296×911** (shipped ref) | **88** | **74** | **863** | no — 58.54% |
| 1280×816 (true viewport) | **84** | **80** | **834** | **18.11%** |
| 1264×721 (old broken) | **~73.5** | ~114 | ~778 | — |

The port's constants (`FX=36, FY=28, B=760, FR≈44, PX=834.2`) are
**verified correct** against the 1280×816 layout: `--B = min(100vh-56,
100vw-500) = 760`, `--fr = B*.058 ≈ 44`, board 672, pitch 84, panel
x = 36+760+gap ≈ 834.

## Numbers for the report

| comparison | tol 8 | tol 24 | mean |
|---|---|---|---|
| port vs shipped ref070 | 58.54% | 45.51% | 52.68 |
| port vs true 1280×816 capture | **18.11%** | 3.86% | 7.43 |
| shipped ref070 vs true 1280×816 | 57.14% | 45.08% | 51.73 |
| ref070 vs a fresh script capture (noise floor) | 2.02% | 1.19% | 0.93 |
| round-6 floor | 1.73% | 1.41% | — |

## Attribution

- **No viewport compensation in app.nim.** `SW=1280`, `SH=816`, no
  `clientWidth/clientHeight` reads, no 1264/719 literals. The earlier
  typewriter bug (SW=1264/SH=719.5 back-solving a broken reference) is
  **not present here**.
- **Attributable to tooling**: R18a is not fixed — the probe verifies
  `innerWidth/clientWidth`, the page renders at the window width, and
  the crop preserves the wrong layout. The same defect that created
  the 1264×721 references (R18) recurs in a subtler form.

## RESOLVED at round 139 — this analysis was right, the fix was elsewhere

R7 diagnosed the *symptom* correctly (ref070 carried a 1296-wide layout) and
blamed "capture-ref.ps1's probe-to-window mapping". That is right about the
mechanism and wrong about the fix, in a way that cost two more rounds:

R18/R18b did not *fail* to compensate — it compensated unconditionally. The
right compensation depends on which CSS metric the page lays out against, and
`100vw` and `clientWidth` resolve to different numbers at the same window size
(innerWidth=1264 vs 100vw=1280 at `--window-size=1280,816`). Forcing a
scrollbar onto the probe made the overhead 16 px larger and therefore correct
only for `clientWidth` pages. Chess lays out off `100vw`, so for chess the
compensated capture was the *wrong* one — 18.42% at no-overhead vs 58.57% at
overhead, measured both ways.

So R7's item 1 ("orchestrator must fix the probe-to-window mapping") is
answered, but not by fixing the mapping. The fix is `capture-ref.ps1`'s new
6th argument `nooverhead`, and chess is a `nooverhead` page. Full entry in
`.board/reports/ISSUES.md` as R18c.

R7's item 2 is done. Re-measured against a correctly-captured 1280×816
reference: **18.42% @tol8, mean 8.02** (was reported 18.11% against a
hand-made capture — 0.31pp apart, which is the grain floor of the reference,
not a change in the port). The port's own layout constants
(`FX=36, FY=28, B=760, FR≈44, PX=834.2`) are confirmed correct against it.

R7's item 3 stands: typeface/glyph error and the intermittent crash are the
port's own remaining work, and they are now measured against a reference that
can actually refute them.

## Next item

1. 18.42% @tol8 / 3.86% @tol24 vs a correct reference is the honest baseline.
   The structural residual is ~44k px; the rest is feTurbulence grain.
2. Port's own reachable residual: typeface/glyph error (defect 1) and
   the intermittent crash (defect class noted R6).

### 17.24 Defect 7 done — and the 11 000 px prediction was wrong by an order of magnitude

Item 7 said `Draw.text` cannot name a typeface, cost this page ~11 000 px, and had been
corrected in round 156 from "cannot" to "not yet done here". So: done.

**All 9 `d.text` call sites moved to `Draw.textFace` with `"Palatino Linotype"`.**

Choosing the family was not a guess. The page's stack is `--serif: Baskerville, Baskerville
Old Face, Hoefler Text, Garamond, Palatino Linotype, Book Antiqua, P052, URW Palladio L,
Georgia, serif` (`070-chess-study.html:22`). Checked against `%WINDIR%\Fonts`: Baskerville,
Garamond and P052 are all **absent**; Palatino Linotype (`pala.ttf`), Georgia, Times,
Cambria and Constantia are present. So the capture browser resolved to **Palatino Linotype**
too, and the port now matches what the reference actually drew. `Draw.text` emits the `T`
verb, which the shim renders in the engine default — Segoe UI — so before this the entire
page was set in a sans face against a serif reference.

**Measured against `.board/frames/ref070.png` at tol 8, both frames rendered at `wait:8`:**

| | differing px | mean abs delta |
|---|---|---|
| baseline (`Draw.text`, Segoe UI) | 177 501 / 1 044 480 (**16.99 %**) | 6.32 |
| **`textFace`, Palatino Linotype** | 176 455 / 1 044 480 (**16.89 %**) | **6.09** |

Both metrics moved the right way, so the change is real. But it is **1 046 px, not the
11 000 the note predicted** — an order of magnitude short, and the prediction is the thing
that needs correcting. It was an estimate of tracking drift multiplied out by an area guess,
never measured, and it was wrong.

**The more informative number is that the change moved 12 376 pixels of the frame.** So the
old font was wrong over a large area and the new one is wrong over nearly as much of it;
only ~8 % of the churn was a net correction. Wrong pixels are not the same as pixels the
right font fixes, and I conflated the two when writing the estimate.

**Where the text still disagrees**, from differencing the two rendered frames rather than
against the reference (bands of rows that moved at all):

    y   32.. 90   (h1 "Grandmaster's Study")        y  408.. 423   1443 px
    y  107.. 120    153 px                            y  442.. 456   1253 px
    y  149.. 163    698 px                            y  527.. 540    123 px
    y  191.. 204     89 px                            y  611.. 624    129 px
    y  229.. 240    405 px                            y  695.. 708     97 px
    y  275.. 295                                      y  759.. 776   1469 px
    y  321.. 328    266 px
    y  380.. 389    464 px

**The next step is the `spaced` proc, and the change made it worse rather than better.**
`spaced` (`app.nim:276`) advances by `size * 0.667 + track` — a single constant chosen for
Segoe UI's metrics, applied per character. Palatino Linotype has different advances, so
every letter-spaced run (the `WHITE`/`BLACK` labels at y 107-120 and y 149-163, and the
piece captions) now drifts at a new rate. **That constant is per-family and was never
measured**; defect 1 (no text measure API) is what makes it a constant at all. Re-tuning it
against Palatino is the next measurable move, and it should be done by measuring rendered
run extents rather than by fitting a number to the reference.

### 17.25 Defect 1 finally has a number, and a control

17.24 left the `spaced` proc: it advances by `size * 0.667 + track`, one constant per
character, picked for Segoe. Changing the family does not change the advance, so the swap
fixed the glyph shapes and left the spacing exactly as wrong as before.

**Two tools were needed first, both in `tools/`:**

- `png2raw.mjs` — decode a PNG reference to raw RGBA. Every existing probe reads `.raw`,
  and the only way to compare against the reference was `pngdiff.mjs`, which reports a
  whole-frame score and cannot answer "which pixels hold this text". **Validated by
  decoding `ref070.png` and differencing it against itself: 0 / 1 044 480 at tol 0, mean
  0.00.** A measuring tool that has not been checked against its own input is not a tool.
- `textextent.mjs` — per-column ink profile of a band, reported as glyph clusters and
  inter-glyph advances. Takes an optional colour key (`minRB`, minimum red-minus-blue).

The colour key is what made this possible. The runs **overlap vertically** — the eyebrow is
drawn at y=28 size 12 and the h1 at y=45 size 34.56, so both put ink in rows 19-38 and no y
band separates them. By colour they separate cleanly: `C_BRASS 0xC9A45C` has R-B = **109**,
`C_IVORY 0xF7F0E1` has R-B = **22**. Keying at R-B >= 60 isolates the eyebrow in both frames.

**Measured — two independent runs, with the Segoe build as a control:**

| run | size | track | reference | port, Palatino | port, Segoe | excess/char |
|---|---|---|---|---|---|---|
| `A HOT-SEAT GAME FOR TWO` (23 ch) | 12 | 4.08 | **261 px** | 275 px | 275 px | **0.61** |
| `SCORE SHEET` (11 ch) | 13 | 3.9 | **127 px** | 134 px | 132 px | **0.64** |

**The control is the finding.** Palatino and Segoe produce the *same* 275 px eyebrow span,
because the advance is a constant that never sees the family. So none of the drift is
typographic — all of it is the `0.667`. That is the first statement about this defect that is
attributable, and it retires the plausible reading that the font swap should have improved
spacing.

Solving `size * (0.667 - k)` from the two runs independently gives **k = 0.616** and
**k = 0.618**. Consistent to 0.002 across different sizes, tracks and strings — so the drift
is systematic, not a per-string coincidence.

Glyph clusters tell the same story from the other side: the reference resolves **19** and
**10** separate glyphs, the port **17** and **9**. Characters are colliding into blobs.

**And I am still not changing the constant.** 0.617 is the mean advance of the *particular
strings on this page*, not a property of Palatino Linotype — a run of `I` would be far
narrower and a run of `W` far wider, and no single number can be right for both. Changing
0.667 to 0.617 would move the scoreboard without fixing the cause, which is the same trade
as fitting `rx ≈ 376` and is refused for the same reason. **The cause is defect 1: the app
cannot measure text.** The fix is a measure query in the SDK — the shim already has
`yk_text_draw2` and Skia has `measureText`; what is missing is a way for a `Draw` producer to
*ask* for advances before it commits to pen positions.

**What changed is that the gap is now quantified rather than gestural.** §17.24's standing
note said "the next measurable move". It was measurable, it took two tools and a control,
and the answer is **~0.6 px per character, entirely attributable to one constant, and not
fixable from app code.** That is the first time this defect has had a number attached to it.

### 17.27 Letter-spacing ELIMINATED as a cause, and the 0.667 "calibration" corrected

Round 163 showed dna's `MONO_ADV = 0.5498047 ## Consolas hmtx advance / unitsPerEm` — a
hand-built advance table that encodes one font's metrics. Chess's `spaced()` advances by a
single flat `size * 0.667 + track` for **every** glyph, which is the same kind of stand-in.
So the question this round settled is: does the flat constant explain the 16.89 %?

**Deriving per-glyph advances from the reference.** A font advance is a property of the
typeface, and the reference renders that typeface, so the reference's own glyph origins ARE
the advance values. For each glyph in "A HOT-SEAT GAME FOR TWO":

    advance(c) = (origin_to_origin_spacing − track) / size,  track = 12 × 0.34 = 4.080px

Advances that **skip a space** (A→H, T→G, E→F, R→T) also carry the space's width and are
discarded — reading one as a single glyph produced a *negative* advance for `A`, which is how
the bug was caught.

**The table (em), and the check that it is real:**

| ch | em | ch | em | ch | em |
|---|---|---|---|---|---|
| `-` | 0.3267 | `S` | 0.4933 | `O` | 0.7433 |
| `E`,`F` | 0.5767 | `T` | 0.6600 | `H` | 0.8267 |
| `G` | 0.7433 | `A` | 0.7850 | `M`,`W` | 0.9933 |

**`O` occurs twice and measures 0.743 both times; `T` occurs twice and measures 0.660 both
times.** That exact repeat agreement is the evidence this is measurement and not noise —
a fitted coefficient would not reproduce the same character to the same 1/1000 em twice.
`A` differs (0.743 / 0.827) by exactly the ±1 px quantisation, since cluster origins are
integer pixel columns. **Range 0.327 → 0.993 em, a 0.667 em spread.** The hyphen is 51 %
narrower than the flat constant gave it; `M` and `W` are 49 % wider.

**So the constant is wrong — and fixing it changes nothing.**

| build | differing px | % | mean |
|---|---|---|---|
| HEAD, flat 0.667 | 176 454 | 16.89 % | 6.09 |
| per-glyph table | 176 416 | 16.89 % | 6.08 |

Net **39 pixels out of 1 044 480**. Worse in 19 rows, better in 28, unchanged in 769. **That is
noise, so the table was reverted** and `0.667` stays — shipping 30 lines of "measured" values
for a 0.004 % move that is not even directionally uniform would make the code look more
precise than it is. Rule: *different is not better; prove it moves toward the reference.*

**The result worth keeping is the elimination.** A hypothesis is properly killed by a correct
implementation of it, not by an argument. The advance really does span 0.67 em, the constant
really was wrong, and implementing the right answer moved the scoreboard by 39 pixels.
**Letter-spacing is not what keeps this page at 16.89 %.** That is now settled and should not
be re-litigated.

**And the header's claim was simply false.** `app.nim` said 0.667 was "calibrated against the
reference eyebrow … measures 278px wide = 12.1px per character". Measured: the reference
eyebrow's ink spans **x 835..1094 = 260 px** across 19 glyphs; this port's own render spans
**273 px**. 278 is neither. **0.667 reproduces the PORT, not the reference** — and my
port-notes had recorded that I declined to fit this coefficient, while the code carried a
fitted one and described it as calibrated. The comment is corrected in place; the code is
unchanged, and the corrected build scores 176 454 — byte-identical to HEAD, which is what a
comment-only change must do.

Where the remaining error lives is therefore **not** spacing: defect 1 (+1.68/255 per
translucent fill, measured) and the 0.61 px/char text metric still stand, and nothing here
contradicts them.
