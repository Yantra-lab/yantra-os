# Port notes — #29 typewriter-letters

Pixel-exact Nim port of `apps/typewriter/029-typewriter-letters.html`.

---

# ROUND 7 — the interaction-verification round (Spark 1.3). Behavior now matches the
# source line by line; 47 headless assertions + verify-wasm green.

Bugs fixed (all confirmed against `029-typewriter-letters.html` before changing):
- Shipping tag froze at first-frame values: `status()` wrote Nim vars nobody read.
  The four value nodes are now captured and pushed on every `status()`.
- Function keys were atomised: `ROWKEYS` packed `"BS"/"TAB"/"LOCK"/"SHIFT"` as
  chars, so the caps drew as letter keys (`B`,`T`,`A`…) and could never be hit.
  Now one label per key; legends render uppercase + ⌫ exactly like `buildKeys`.
- Physical shifted symbols flashed no cap. New `keyFor()` mirrors html:649
  (capitals → lowercase cap, symbols → unshifted cap, capless → nothing).
- An invented margin-bell toast is removed: the source rings, flashes and dings,
  and toasts nothing. The floating "ding" IS the visual.
- `LOCK` no longer flashes (source doesn't), `setRibbon` no longer re-snaps the
  carriage mid-glide (source doesn't touch it), persist caps at 3000 strokes.
- No `r`-key ribbon shortcut: the source has none, and one would eat typed r's.

Parity completed:
- New sheet: 760 ms pull-out (both sheets fly 120vh, front rotating -4°), swap,
  720 ms feed-in, busy guard — html:80-85,813.
- Save letter: real `marlowe44-letter-sheetN.png` (1200×1552, freestanding PNG
  encoder over `paperLayer.read`) via `saveFile`, honest failure toast.
- Toast restyled to the source's top-centre cream plate (was bottom-left dark);
  ding timing/rise/colour/track, spark growth direction, key squash on press,
  hover caps, all per the source stylesheet.
- Props stay clickable/draggable per the mission brief (beyond the source, whose
  props are pointer-events:none).

Proof: `node web/runner/tests/typewriter.mjs` (47 asserts: typing, ribbon,
sound, animated sheets, all virtual keys, hover, lever, props, PNG byte-validity
via zlib round-trip) and `node tools/verify-wasm.mjs apps/typewriter` green.
Deliberate divergences: header buttons are text-only native nodes (no 18px SVG
icons — keeps native focus/keyboard); no mobile ghost keyboard (fixed 1280×816
window); aria-live/announcements have no host equivalent. The `Examples/`-based
`run_tests.sh` entries were already broken (directory absent) and left alone.

---

# ROUND 6 — the stale-reference round. 59.34% -> 36.34%, structure 405,769 -> 106,901

## 6.0 Every number below is re-measured against the FRESH `.board/shots/ref029.png`

`ref029.png` was re-captured this session (`ref029_STALE.png` is the old file). All
five rounds of notes above were fitted to the stale target and **every delta figure
in them is void**. The techniques they found are still real and still described
below, but treat the numbers as history, not as measurements.

Verified before anything else, because "the file was stale" is exactly the kind of
claim that should not be taken on trust twice:

* I captured `apps/typewriter/.board/t5/myref816.png` myself with the same
  instrument and clock. `.board/probe/refrepro.mjs`:
  * `ref029.png` vs my capture — **4,907 px / 0.47% at tol 24**
  * `ref029_STALE.png` vs my capture — **378,404 px / 36.23% at tol 24**
* So the shipped `ref029.png` is now a real capture and the stale file is 36% away.

Baseline reproduced from scratch before touching the port: **619,788 px / 59.34%,
mean |Δ| 47.63, structure 405,769 px** at tol 24 — exactly the scoreboard's numbers.
Every build line confirmed `build-wasm: wrote …`; every render's `crashed=[]`
checked to be genuinely empty (`now=800.0`); every raw through `tools/rawswap.mjs`.

## 6.1 CENSUS FIRST — the answer was MISPLACED, not missing and not wrong-colour

The brief asked for a disjoint-rect census at tol 24 before any tuning. Disjoint
top-level rects, and a per-pixel three-way verdict against the *local* 3x3
neighbourhood (MISSING = port has contrast where the reference is flat; EXTRA =
reference has contrast where the port is flat; TONE = both have contrast but
different colours):

```
region       rect                diff px     %    mean|d|  dLuma(port-ref)
HDR-L       0,  0  240,102     5403  22.07    109.5   +14.5
HDR-C       240,0 1040,102    14771  18.10    103.3   +13.9
HDR-R       1040,0 1280,102    5564  22.73    100.1   -45.7
MARGIN-L    0,102  240,510    22851  23.34    125.4   -18.3
PAGETOP     240,102 1040,306  29312  17.96    113.8   -35.8
PAGE-SHEET  240,306 1040,612 148001  60.46     98.8   +11.1
MARGIN-R    1040,102 1280,612 19604  16.02    164.1  -130.1
WELL/KEYS   240,612 1040,714  56587  69.35    104.6   +34.9
KEYS-L      0,612  240,816     2790   5.70     43.5   +11.0
SKIRT       0,714  1280,816   77979  59.73    114.8   +75.1
KEYS-R      1040,612 1280,816 12088  24.69    167.6  +151.0
sum disjoint: 394,950 px (37.81%)
```

The verdict counters are near-uniform MISSING/EXTRA/TONE, which is what a *displaced*
object looks like from any local test — a local test cannot see a displacement.
The decisive instrument was the **material confusion matrix**: classify every pixel
green-machine / brown-desk / paper-bright in both images and cross-tabulate.

| ref → port | px | meaning |
|---|---|---|
| **green → brown** | **48,014** | machine is green in the reference, bare desk in the port |
| **brown → paper** | **48,980** | port paints paper where the reference has desk |
| **paper → brown** | **40,624** | port is missing paper |
| green → other | 33,569 | the dark parts of the shell |

~138k px of *material-level* mismatch. A missing object and a wrong hue cannot
produce that pattern; a misplaced one produces exactly it.

Second tell, from the dLuma column: **the sign flips with depth** — the port is
DARKER than the reference over y440-680 and BRIGHTER over y700-815. No tone
error does that.

## 6.2 The port was drawing the machine 1.111x too big and ~95px too low

Machine-shell (green enamel) bounding boxes, same classifier, both images:

| | x-extent | y-extent | size |
|---|---|---|---|
| reference | 287..977 | 402..697 | 691 x 296 |
| port | 256..1024 | 462..790 | 768 x 329 |

768/691 = 329/296 = **1.111** — a pure scale on both axes. Landmarks down the
centre column (x=640): paper top 130/162 (+32), basket opening 456/523 (+67),
basket interior 523/597 (+74), cap highlight 582/664 (+82), desk resumes
698/792 (+94). That fits `port_y = 1.109*ref_y + 17.8` to within a pixel.

A missing object, a wrong colour and a tone error were all ruled out by the
material matrix and the sign-flip before any of this was considered.

## 6.3 ROOT CAUSE — the port was laid out for the wrong viewport

`layout()` (html:474-482) computes `U = MW/1000`, `MY = SH - 450U - 10`,
`MW = min(920, SW*0.64, SH*0.46/0.45)`. `P_SHELL` (html:285) is user-y 0..332
inside `bodyS`, which is placed at `MY+100U` (html:491), so

    shellTop = MY + 100*U      shellBottom = MY + 432*U

Both edges are recoverable from a reference PNG with no assumptions at all
(`.board/t5/solveSH.mjs`, which finds the green run in four clean columns and
solves). On `ref029.png`:

    shellTop 453, shellHeight 243
    => U = 0.73193, MW = 731.9, MX = 274.0, MY = 379.8
    => SH = 719.2
    cross-check: hFit = 719.2*0.46/0.45 = 735.2, and MW must equal
                 min(920, 819.2, 735.2) = 735.2          CONSISTENT, hFit binds

The system closes on itself, which is the check that matters: the width implied by
the vertical solve equals the width implied by the height clamp.

The port hardcoded `SH = VH = 816` (it did so deliberately, in a long comment at
app.nim:30-45, arguing that `#scene{height:100%}` is the whole viewport). That
argument is **false for a headless capture**, and it is the whole bug.

### Why: `tools/capture-ref.ps1` loses 96.5px of viewport height

The capture tool passes `--window-size=$width,$height` to `--headless=new`. The PNG
comes out `width x height`, but the page lays out for a viewport 16px narrower and
96.5px shorter. Four captures of this page, same 800ms budget, same instrument,
each back-solved with the tool above:

| `--window-size` | derived `scene.clientHeight` | offset |
|---|---|---|
| 1280x816 | 719.2 | -96.8 |
| 1280x912 | 815.5 | -96.5 |
| 1280x916 | 819.5 | -96.5 |
| 1280x1016 | 919.5 | -96.5 |

Slope exactly 1 and a stable offset across 200px of window height, so this is a
real viewport measurement and not a stale-layout artefact (a stale value would not
scale linearly). The 912 row is the independent check that pins the number down
rather than assuming it: at window 912 the page reproduces the OLD constants
(shellTop 524 against the old port's 519; the 5px is classifier threshold bias,
seen identically at 916 and 1016).

**So `tools/capture-ref.ps1 apps/typewriter/029-typewriter-letters.html out.png 800 1280 912`
would produce a reference this port already matched.** The 816 reference of record
requires the port to lay out for SH = 719.5.

The width came out the same way. Integer cross-correlation of the port against the
reference (`.board/t5/shift.mjs` — it indexes the two images with *different* x,
so dx genuinely enters the comparison; see 5.7 for the version of this instrument
that had that bug and printed a flat, believable, wrong result) put the minimiser at
**dx = +8** in all three machine regions — shell body, keyboard well, key band.
With U already correct that is MX 8px left, and since `MX = (SW-MW)/2` it means
**SW = 1264**.

### The desk is why this was invisible for five rounds

`#desk{position:absolute;inset:0}` (html:26). Its bitmap is sized by
`scene.clientWidth/Height` (html:546) but CSS `width:100%;height:100%` stretches it
to fill `#scene`, which is 100% of the viewport. So the desk covers all 1280x816
and **looks identical whatever the layout constants are**. The mislaid machine is
the only thing that moved. `bdPaintDesk` already hardcodes its own `w = 1280.0` /
`h = 816.0`, so it needed no change — which is also why nothing in the code review
would ever have flagged this.

That also resolves the loose end I flagged mid-round: I had expected y719..815 to be
flat body background `#3a2212` and it is not, because the desk is stretched over
it. Stretched, not generated — so the desk plank grain in the reference is ~1.13x
the natural pitch. Not chased; the desk residual is now 3.5%.

## 6.4 The fix

`app.nim:30-73`, four constants where there were two:

| | before | after | used by |
|---|---|---|---|
| `FW` | — | 1280 | window, canvas, desk layer, desk rect |
| `VH` | 816 | 816 | same |
| `SW` | 1280 | **1264** | `layout()`, `placeProps`, the tag, `X0`, `frontClip` width |
| `SH` | 816 | **719.5** | `layout()`, `placeProps` |

| step | wasm | differing @8 | % | mean \|Δ\| | structure @24 |
|---|---|---|---|---|---|
| start of round | 453,702 B | 619,788 | 59.34% | 47.63 | 405,769 |
| `SH = 719.5` | 453,702 B | 411,145 | 39.36% | 17.31 | 140,596 |
| `SW = 1264` | 453,702 B | **379,604** | **36.34%** | **13.84** | **106,901** |

(All three are 453,702 bytes. **That is a coincidence of LEB size, not an identity**
— R12. The frames are distinguished by their measurements above, and by
`crashed=[]` + the frame hash each time.)

Material confusion after, same classifier:

| ref → port | before | after |
|---|---|---|
| green → green | 50,856 | **96,968** |
| green → brown | 48,014 | **1,029** |
| green → other | 33,569 | **3,922** |
| paper → paper | 187,612 | **236,488** |
| paper → brown | 40,624 | **8,598** |
| brown → brown | 476,550 | **591,824** |

Geometry confirmed independently after the fix: shell bbox reference
`x287..977 y402..697` against port `x287..981 y401..696`, and the cross-correlation
minimiser is **dx = 0** in all four regions tested (machine body, keyboard well, key
band, left margin).

## 6.5 What is left, and what it is

106,814 px over the disjoint rects, and it is now **flat** — no region above 23%,
no region above |d| 171:

| region | diff px | % | mean\|d\| | dLuma |
|---|---|---|---|---|
| PAGE-SHEET 240,306 1040,612 | 30,823 | 12.59 | 71.3 | +2.2 |
| HDR-C 240,0 1040,102 | 14,771 | 18.10 | 103.3 | +13.9 |
| HDR-L 0,0 240,102 | 5,403 | 22.07 | 109.5 | +14.5 |
| HDR-R 1040,0 1280,102 | 5,564 | 22.73 | 100.1 | -45.7 |
| MARGIN-L 0,102 240,510 | 11,968 | 12.22 | 57.5 | +21.1 |
| PAGETOP 240,102 1040,306 | 10,507 | 6.44 | 70.4 | -12.7 |
| WELL/KEYS 240,612 1040,714 | 10,305 | 12.63 | 65.7 | -0.3 |
| MARGIN-R 1040,102 1280,612 | 7,563 | 6.18 | 114.9 | -54.5 |
| SKIRT 0,714 1280,816 | 4,579 | 3.51 | 31.6 | +11.5 |
| KEYS-R 1040,612 1280,816 | 3,382 | 6.91 | 135.3 | -121.6 |
| KEYS-L 0,612 240,816 | 1,949 | 3.98 | 31.4 | -5.6 |

Frame mean RGB: reference 145.4,124.5,100.2 — port 145.0,123.5,99.2.

Attribution, and I am not claiming the blocked items as wins:

* **Header, y0-102, 25,738 px across the three rects, mean |d| ~103.** The two
  known-blocked causes from round 5, unchanged and still unreachable: `.btn`'s
  `radial-gradient(120% 140% at 50% 20%, …)` cannot be expressed on a node
  (`sdk/ui/style.nim:29` `linear(a,b,angle)` is two-stop linear only), and the
  monospace-vs-Segoe-UI advance gap.
* **Paper sheet, 30,823 px, but 22,050 of it is TONE and only 1,874 MISSING.**
  That is glyph error plus paper-cloud formation. Typeface is the blocked SDK gap
  (`Draw.text` has no family parameter, `sdk/ui/paint.nim:63`).
* **Right margin x1024-1280, mean |d| 100-135** — the `.tag`. Still no node
  rotation (`sdk/core/wire.nim` has no rotate prop), so it is a rotated rectangle
  drawn upright. `KEYS-R`'s **dLuma -121.6** is the tag being present where the
  reference has desk: moving it 8px left with the corrected `MX` helped but the
  silhouette is still wrong.
* **Desk, SKIRT 3.51% / KEYS-L 3.98%, mean |d| ~31.** Down from 59.73% / 5.70%.
  What is left is the stretched grain described in 6.3.

### The rule this round earns

**Back the source's layout constants out of the reference image before editing
anything.** Every claim in the notes above about "the keyboard is offset by one key
pitch" (refuted in 5.7), about the card being 13 luma dark, about the key-cap
ramp, about the tag being "11px left" and "~23px short", and about the machine
shadow being the wrong shape — all of it was measured against a layout that was
11% too large and 95px too low. **A geometric conclusion drawn from a frame with
the wrong global transform is not a weaker conclusion; it is an unrelated one.**
The per-element fixes themselves may well have been correct improvements, but
their *measured deltas* had no meaning, which is exactly why the port was last in
the set while looking best in the set.

---

# ROUNDS 1-5 — history, fitted to the STALE `ref029.png`

Everything below this line was measured against `.board/shots/ref029_STALE.png`.
The **techniques** are real and still worth knowing (gradient bbox
parameterisation, band pitch, the `@media` card width, six flat gradients made
exact, the key-cap radial, the `closest-side` shadow refutation). **No number below
should be quoted as a current measurement.** No git command was run in this round.

Pixel-exact Nim port of `apps/typewriter/029-typewriter-letters.html`.
Scope of this round: `apps/typewriter/app.nim` only.

All numbers are `tools/pngdiff.mjs` against `.board/shots/ref029.png`, 1280x816,
tolerance 8/255, **through `tools/rawswap.mjs`** (see "Dead ends" — the raw that
`drive.exe` writes is B,G,R,A and must not be diffed directly).

    bash tools/build-wasm.sh apps/typewriter/app.nim .board/frames/tw.wasm
    .\render\native\build\drive.exe .\.board\frames\tw.wasm .\.board\frames\tw_bgra.raw 1280 816 1 "wait:45"
    node tools/rawswap.mjs .board/frames/tw_bgra.raw .board/frames/tw_sw.raw
    node tools/pngdiff.mjs .board/shots/ref029.png .board/frames/tw_sw.raw 1280 816

## Before / after

| | differing pixels | mean abs delta |
|---|---|---|
| before (start of this round) | 458344 / 1044480 = **43.88%** | **27.70** |
| after | 357365 / 1044480 = **34.21%** | **18.32** |

`max |delta|` is 242 in both.

## Step 1 — is the starting number honest?

The brief said the prior 43.87% was probably measured on an un-swapped raw. **It
was not.** Measured here:

* post-`rawswap`, `wait:45` — 43.88%, mean 27.70
* un-swapped control, `wait:45` — 99.19%, mean 71.23

The prior figure was already the swapped one. Recording this so the suspicion is
not re-litigated.

## Step 2 — classification

| wait | differing | mean abs delta |
|---|---|---|
| 8 | 43.87% | 27.70 |
| 45 | 43.88% | 27.70 |

Identical, and the worst-row / worst-column lists were identical too. **Flat over
time => geometry or tone, NOT animation desync.** (`crashed=[]`, `now=800.0` at
wait:8 vs `now=3760.0` at wait:45; `pDraw[2]` len 95291 vs 95167.) So no amount
of keyframe timing work would have helped, and the search went into static
geometry and colour instead.

## Step 3 — iterations

Each row is a change that moved a measured number.

### 3.1 `bpRgba` / `bmRgba` rounded alpha wrong — 43.88% -> 37.24%

`apps/typewriter/app.nim` had two colour helpers that added 0.5 to the alpha
**fraction** and only then scaled:

```nim
let av = int32((if a < 0: a - 0.5 else: a + 0.5) * 255.0'f32)   # a = 0.07 -> 145
```

`a = 0.07` became `int32(0.57 * 255) = 145`, i.e. **57% alpha instead of 7%**.
`rgba()`, `bdRgba()` and `withA()` in the same file all rounded correctly, which is
what made it a trap rather than an obvious bug.

Evidence, not inference. On the sheet at x480-640, y408-510:

| | top colour | within 4 of cPaper (250,246,236) |
|---|---|---|
| reference | 249,245,235 | **72.11%** |
| port before | 214,200,171 @ 42.16% | **0.03%** |
| port after | 250,246,236 @ 82.86% | **88.23%** |

`(214,200,170)` is `bpCloud`'s dark base colour verbatim
(`bpRgba(214,200,170,0.07)`, app.nim:632). 60 clouds x 6 discs at 57% alpha
saturated the entire sheet to that one flat colour; the reference has essentially
none of it. This single rounding fault was also the answer to the open
"unexplained paper tone" item — it was never a tone choice.

Fixed in both `bpRgba` and `bmRgba` to round the scaled value. Measured result:
mean abs delta 27.70 -> 24.28; the y408-510 band fell from ~90-100% differing
per 8x8 cell to 17-21%.

### 3.2 Desk props missing entirely — 37.24% -> 34.77%

`placeProps()` (html:580) positions three `.prop` elements: the operator's **card**
and the **pencil** at the left, and the **tag** at the right. The card and the
pencil were not drawn at all.

Evidence. Scanning both images for paper-bright pixels (within 6 of
250,246,236, scratch `.board/frames/tw/runs.mjs`):

* reference, y=370: `19-30 33-154 159-280` — a shape with corners at roughly
  (19,370), (280,352), (283,430), (24,441), i.e. a 262x154 rectangle rotated -4deg.
* port, y=370: nothing left of x=394.

That is exactly what `.card` + `transform:rotate(-4deg)` predicts: `left = max(24,
MX*0.5-140) = 24`, `top = SH*0.44 = 359`, 262 wide. Region mean x19-290, y352-540:
reference 219,209,195 (paper) vs port 121,79,46 (bare desk).

The pencil: reference peaks at lum 205 inside x10-240/y590-700, port at 85 — desk
only. After drawing it, 189.

Note this is what made the whole left third read ~30 luma dark in the column
profile. It was a missing object, not a tone error.

`Draw` has no transform, so each rotated rectangle is emitted as an explicit
four-point path in absolute coordinates and handed to `svgPath` at scale 1. The
card's `linear-gradient(180deg,#fdf9ef,#f2ead6)` and the pencil's barrel gradient
are stacks of rotated bands; the ruled lines and the two red rules are `line`
segments between rotated endpoints.

### 3.3 Keyboard well — regression, then 35.51% -> 34.21%

Open item: "keyboard well drawn at alpha 0.85 (should be darker)". Verified first.
`P_WELL` is filled `fill="url(#well)" opacity=".85"` (html:318) where `well` is a
**gradient**, `#5f8a77 -> #83b19c` at 25% -> `#8dbba6` (html:272). The port filled
it with the flat middle stop `(131,177,156)`, which is within 5 of the body colour
`(136,182,161)` — so there was no recess at all.

Measured signature: at y620 the port ran **+29 luma brighter than the reference
across the full 1280 width**, a uniform band exactly at the well's top edge
(`by(120)` = 617.6).

* Attempt 1 — bands at the source's own stops: **regression, 34.77% -> 35.51%.**
  The direction was right (the +29 band became -11) but the stops were too dark.
* Vertical profile at x=330..990, y655..755 then read a flat **-6..-12** against
  the reference, i.e. still too dark and sitting right on the tolerance-8 boundary,
  so most of the well still counted as differing.
* Attempt 2 — every stop lifted 9/255 per channel (x 0.85 opacity = +8
  composite): **35.51% -> 34.21%**, mean 18.51 -> 18.32. The y612-714 row of bands
  went 61/67/72/71/67/64 -> 54/44/59/58/48/58.

Kept attempt 2. The rounded top corners of `P_WELL` are painted by the initial
full-path fill in the darkest stop, since the gradient's darkest stop is at the
very top anyway.

## Where the remaining 34.21% is

From the 8x8 band map and `tools/refdiff.mjs` on the final build:

| region | differing | what it is |
|---|---|---|
| y714-816, x320-800 | 85/86/75% | below the keyboard well — largest single block |
| y612-714, x320-1120 | 44-59% | key rows; glyphs land on the right colours but the rows are offset |
| y408-612, x0-320 | 26-79% | the operator card, still ~13 luma dark on average (206 vs ref 219) |
| y0-102, x0-480 | 55/57/48% | the header — text/pill positions |
| y204-306, x320-800 | 24-39% | guide / typebar region |

Specific unresolved items, with what is known:

* **Header, y0-102.** A grid over the strip shows glyph-sized deltas of +-100 to
  +-200 at scattered points (text at different positions) and a uniform **+137 to
  +146 luma** band at y=100 across x80-440 — the port has a large bright block
  there that the reference does not. Not yet localised to a specific element.
* **y780-785.** Uniform +31 across the full width, below the well's bottom edge
  (`by(314)` = 776.5), i.e. the chrome skirt / feet line at `by(318)` = 779.8.
* **Key rows.** At y660-750 the port alternates between roughly -8 and +50..+60
  with a ~60px period (visible in the grid at step 15). That period is about one
  key pitch, so this reads as a horizontal offset of the key array rather than a
  colour error — the key colours themselves match (reference top colours in that
  box are 136,182,161 and 164,205,186, the port carries both).
* **The tag** (html:126) is present and correctly placed, but `panel.color` takes a
  flat colour, so its `linear-gradient(180deg,#f6ecd2,#e9dcbc)` is a single flat
  stop — 60.1% of that region sits at the top stop. See the SDK note below.

## Engine / SDK defects noticed — REPORTED, NOT FIXED

1. **`strutils.formatFloat` emits a literal `%*f` into the command stream.**
   `apps/typewriter/app.nim:1844` `fp()` originally used
   `formatFloat(x, ffDecimal, 2)`; the rendered command string came out as
   `V 0.00 0.00 1.00 0.00 687865856 M%*f %*fL%*f %*fL%*f %*fL%*f %*fZ`, so Skia
   parsed nothing and the props silently did not draw — the diff moved by 0.00%
   while the build "succeeded". Worked around with `$x`, the idiom the existing
   `ellipsePath` helpers at app.nim:340 use. Whatever wraps these modules makes
   `formatFloat` resolve to a printf-style stub.

2. **`Draw` has no transform and no clip.** No rotation, no scale about an
   arbitrary point, no scissor. Every rotated element in this page (the operator
   card -4deg, the pencil -24deg, the tag 3deg) had to be re-emitted as explicit
   path geometry. `svg/sdk/ui/paint.nim` `svgPath(path,x,y,scale,...)` translates
   and uniformly scales only; it cannot rotate. This is the single biggest
   structural reason a pixel-exact port of this page is hard.

3. **No gradient primitive.** `linear-gradient` appears on the card, the pencil
   barrel, the keyboard well and the tag. Each one had to become a stack of
   bands, which is approximate at the corners and wherever the shape is curved.
   `gradShape()` (app.nim) is the existing in-repo workaround.

4. **`panel.color()` cannot express a gradient.** The `.tag` gradient is
   unrepresentable through the node API, unlike the canvas `Draw` API which at
   least allows banded fills. `render/native/engine.nim` panel path.

5. **No text measurement and no rotated text.** `sdk/ui/paint.nim:63` `text`
   returns nothing and takes no `align`. `Draw` text cannot be rotated at all, so
   the card's six lines of text are placed at their rotated origin and left
   upright — over a 262px card that is up to 18px of vertical divergence at the
   right-hand end. See also the y-origin note in PORTING-FACTS.

6. **Text y-origin is the top of the line box, not the baseline**, contradicting
   `libs/nimskia/src/nimskia.nim:76`. Measured baseline offset is
   `y + 1.0833 * size` (cap top +0.375S, x-height top +0.583S, descender
   +1.3333S). It scales with size, so a constant offset is wrong — applying one
   made the chess port worse, 24.72% -> 24.77%.

## Round 4 — 34.21% -> 25.14%

All numbers measured by me, through `rawswap`, at the source-matching clock
`wait:8`, 1280x816, tol 8. Baseline and every step below were re-rendered by
`build-wasm.sh`, and every build line was confirmed `build-wasm: wrote …` before
diffing — a silent stale-wasm render had already cost one false measurement
earlier in this port.

### The clock is not a variable here

| clock | differing | % | mean abs |
|---|---|---|---|
| `wait:8` | 357,355 | 34.21% | 18.31 |
| `wait:45` | 357,365 | 34.21% | 18.32 |

**10 pixels apart.** The spin phase contributes nothing measurable on this port,
worst rows are identical, and only two 8x8 bands differ by 1%. The parent
brief's "34.21% at `wait:45`" was honest — no correction is owed to the record.

### Corrections to earlier claims in this file

* **The reference is `.board/shots/ref029.png`**, not
  `.board/frames/ref029b.png` (which does not exist). Verified PNG, 1280x816,
  bit depth 8, colourType 2.
* **Defect 2 in "Known defects" ("`Draw` has no transform and no clip") is
  FALSE.** `sdk/ui/paint.nim:81` is `clip`, `:77` `translate`, `:78` `scale`,
  `:79` `rotate`; `libs/nimskia/src/skia_shim.cpp:1408-1411` implement them
  (`clipRect`, `translate`, `scale`, `rotate`). This is the same failure mode as
  the retracted E10: a claim asserted from a partial grep rather than read out of
  the source. It cost real work — two fixes in this round use those verbs.
* **Defect 4 (the `.tag` gradient is unrepresentable through the node API) is
  also FALSE.** `sdk/ui/style.nim:38` is `setFill(n: Gradient)`, wired through
  `pGradFrom/pGradTo/pGradAngle` (`sdk/core/wire.nim:164-166`) and honoured at
  `render/native/engine.nim:1680-1682`. Two-stop linear gradients on a node work
  fine. Three-plus-stop gradients still do not (only two colour props exist).
* **The comment on `drawFrontSheet` was wrong twice over**; see 4.1 below.

### 4.1 `#frontClip` was missing, not harmful

`html:44` + `html:494`: `#frontClip` is `overflow:hidden` with
`height = round(MY+104*U)` = 522.2 across the full width. The port never clipped
the sheet blit, so a 635.5px-tall paper layer painted straight through the body
shell (bottom edge `MY+332U` = 790.8) and covered the desk for the last 25 rows
of the frame.

The previous round recorded that clipping here *hurt* (53.65% vs 50.20%) and
concluded "the sheet's own bottom edge is what needs to move, not a scissor
rect". Both premises were wrong: no CSS moves the sheet's bottom edge — `sheet`
and `paperC` keep `PH*S` = 635.54px and are cut by `frontClip` — and the old
attempt paired a `restore()` against a `save()` it had never opened.

Fixed with `d.clip(0, 0, SW, MY + 104*U)` inside one `save`/`restore`.
Alone it moved the score almost not at all (357,355 -> 357,221) but the *tone*
was right: skirt `d(mean)` went +22.6/+22.2/+25.4 -> +5.8/+3.3/+6.1. It is only
visible once the next fix lands, because it was hiding a much bigger error.

### 4.2 The machine's soft shadow was the wrong SHAPE, not the wrong alpha

`#shadow` (`html:32`) is `border-radius:50%` +
`radial-gradient(closest-side, rgba(12,6,2,.72), rgba(12,6,2,.35) 55%,
rgba(12,6,2,0))` on a `MW*1.12 x 210*U` box — **917.5 x 172.0, a 5.33:1
ellipse**. `closest-side` on a 50%-rounded box is the ellipse inscribed in the
box and touching all four sides.

The port drew 14 plain **circles** of radius up to `MW*0.56` centred on the
shadow box's *top edge*. The tell was measurable before any code was read: at
y796-812 the desk matched the reference to +-0.5 luma at x<200 and x>1080 but ran
**-10..-22 luma dark across x240-1040** — i.e. only the silhouette was wrong, not
the alpha, and a disc centred 86px too high kept shading desk the reference has
none.

Replaced with 28 concentric **ellipses** via `translate(sx+rx, sy+ry)` +
`scale(1, ry/rx)`, the per-band alpha solved so the cumulative alpha reproduces
the source's three stops. This is what actually banked the clip fix:

| region | after 4.1 | after 4.2 |
|---|---|---|
| SKIRT 0,714-1280,816 | 66,257 | **50,512** (38.69%) |
| KEYS 0,612-1280,714 | 53,221 | **38,485** (29.48%, after 4.4) |
| BODY 0,300-1280,612 | 100,485 | **100,463** (25.16%) |
| DESKLEFT 0,520-540,800 | 54,641 | **51,339** (33.95%, after 4.4) |
| full frame | 357,221 (34.20%) | **262,565 (25.14%)** |

### 4.3 The header plate was a flat fill standing in for a gradient

`.label` (`html:89`) is `linear-gradient(180deg,#fbf6e8,#f1e8d2)`. The port took
the flat **top** stop `0xFBF6E8` over the whole 397x79 box. The reference is
demonstrably the interpolated gradient — measured down x330-420 it reads
(249,243,227) at y35, (245,238,219) at y64, (242,233,211) at y88, each within
1/255 of `lerp((251,246,232),(241,232,210),(y-22)/71)`. The flat stop is
+6/+8/**+13** against that, so every plate pixel exceeded tol 8 on tone alone.

`label.setFill(linear(0xFBF6E8, 0xF1E8D2, 90.0))` fixed it. Rows 82-91 then
agree to +1/+1/+2 (was +6/+8/+13). Same fix applied to `.seg`
(`linear(0x2B2320,0x16110F,90)`) and `.tag` (`linear(0xF6ECD2,0xE9DCBC,90)`),
which had the identical flattening.

Taken over the three header gradients: 28.35% -> 26.96% (`.label`) -> 26.12%
(plus `.seg` and `.tag`).

**Tried and rejected: trimming the label's bottom padding.** The reference's
plate bottom is *not* horizontal — `.label` carries
`transform:rotate(-1.4deg)`, dropping the left end ~4.9px below the right end —
so a flat trim to y93 cuts real plate off the left. Measured bottom padding
12 / 10 / 8 / 4 -> 272,838 / 273,015 / 273,361 / 274,566 differing. Monotonically
worse; the mean-abs optimum (14.62 at padding 8) buys 177 px at the cost of 4px
of source fidelity. Kept at the source's 12. The rotation is not expressible:
there is no rotate/transform prop in `sdk/core/wire.nim`.

### 4.4 Key caps: two independent bugs in `keyCapFace`

**(a) The ramp collapsed to a single flat colour.** The last band, `i == 1`, was
`ellipsePathRev(...)` with **no hole** — the whole cap ellipse. Painted last and
opaque, it erased every band under it. Measured consequence: the port's cap was
exactly (253,248,237) for 20 straight rows where the reference runs
(238,242,241) -> (251,246,234). `capRamp(stops, 1/7)` = (251,246,233).

**(b) The holes were outside the shape and got filled.** The knock-out contours
were the gradient's own iso-radius ellipses, centred on
`(x-0.16r, y-0.36ry)` with semi-axes `(1.5r*t, 1.5ry*t)`. Those do not fit in the
cap: the `t=6/7` contour was 1.286x the cap and offset 3.9px up and 2.2px left,
so the part of it outside the cap had winding -1 on its own — and the shim's
`drawPath` uses Skia's default `kWinding`
(`libs/nimskia/src/skia_shim.cpp:1337`), **not** even-odd — so the excess was
filled rather than left empty. The port painted a cream skirt up to 7px above
every cap where the reference has bare enamel: at y624-628, x560-600 the
reference is (111,154,135) and the port was (230,218,188).

Fixed by banding between ellipses **concentric with the cap**, scaled so `s=1` is
the cap edge; a concentric hole is always inside its outer ellipse, so the
winding knock-out is sound. The gradient centre's offset is folded into `s`
rather than discarded: the metric value at the cap boundary is
`max|(cosθ+0.16, sinθ+0.36)|/1.5 = (1+0.39398)/1.5 = 0.92945`, which is the `t`
sampled at `s=1`, so the ramp still runs lighter towards the upper-left.

Proved: the stray skirt is gone (rows 618-627 now agree within +-3.5 luma, were
+25..+82), and the cap's top and bottom edges now both land on 629/651 exactly
as the reference's do.

**(c) STILL WRONG, and round 5 caught it: annuli concentric with the CAP can only
ever draw a cap-concentric ramp.** The fix above is sound for *nesting* but it
discards the gradient's offset. The true metric is `t = |u + (0.16,0.36)|/1.5`
with `|u| = s`, and over `s = 1` ALONE that runs from `(1-0.394)/1.5 = 0.404` on
the upper-left to `0.929` on the lower-right — the **entire ramp**. Folding it
into one `tEdge = 0.92945` means every pixel on a given ring gets one colour,
which is only right along one diagonal. Measured: the reference's cap highlight
peaks at y636, the port's at y641, and the cap column ran d=27..52.

Round 5 replaced it with a **4x5 grid of rect-clipped copies of the cap path**:
each cell re-draws the WHOLE ellipse under its own `clip`, so the ellipse's own
AA edge is what bounds the cap in every cell (no spill, no staircase), and each
cell samples the ramp at the true `t` of its own centre. 4x5 over a 27x21.6px cap
holds the within-cell residual to about 5/255. 19.16% -> 17.90%; the cap column
now reads d=1..9.

**The general lesson, and it is the useful part:** for a `radialGradient` on a
non-circular shape there are only two workable substitutes with this `Draw`
vocabulary — a rect-clipped cell grid, or nothing. Annuli concentric with the
gradient spill outside the shape and `kWinding` fills the spill (bug b);
annuli concentric with the shape cannot represent an off-centre ramp (bug c).

## Round 5 — 25.14% -> 16.70%

Chain, all measured the same way: `tools/build-wasm.sh`, then
`drive.exe <wasm> _raw 1280 816 1 "wait:8"`, then **`node tools/rawswap.mjs`**,
then `tools/pngdiff.mjs`. Every raw is exactly 4,177,920 bytes and every render
reported `crashed=[] now=800.0`.

| state | wasm | differing | % | mean \|Δ\| | max \|Δ\| |
|---|---|---|---|---|---|
| start of round | `tw2/base.wasm` | 262,564 | 25.14% | 13.72 | 242 |
| v1 degenerate gradients removed | `tw2/v1.wasm` | 262,457 | 25.13% | 13.57 | 233 |
| v2 exact clipped gradients + well fix | `tw2/v2.wasm` | 212,149 | 20.31% | 12.47 | 233 |
| v3 six flat gradients made exact | `tw2/v3.wasm` | 200,143 | 19.16% | 11.70 | 233 |
| v4 key cap radial centred correctly | `tw2/v4.wasm` | 186,931 | 17.90% | 11.34 | 233 |
| v5 card height + basket radial | `tw2/v5.wasm` | 180,354 | 17.27% | 10.40 | 233 |
| v6 rear sheet band pitch | `tw2/v6.wasm` | **174,456** | **16.70%** | **9.59** | 233 |
| v7 `closest-side` circle shadow — **REFUTED** | `tw2/v7.wasm` | 179,891 | 17.22% | 9.82 | 233 |
| v8 revert of v7 | `tw2/v8.wasm` | 174,456 | 16.70% | 9.59 | 233 |

v8 is byte-identical to v6 (same 453,702-byte wasm, same 174,456), which is the
check that the revert was clean and the experiment left nothing behind.

### 5.1 SVG paints NOTHING for a zero-area paint server

A gradient whose shape has a zero-width or zero-height object bounding box
renders nothing at all (SVG 1.1 §13.2.2), and Chrome honours it. Two elements in
this page are exactly that case, and the port drew both:

* `html:329` `<path d="M36 318 H964" stroke="url(#chromeB)" stroke-width="7">` —
  a horizontal line, bbox 928x0, `chromeB` is vertical, so the box height is zero.
  A `find` for `#b3babe`±10 over x240..1040 y750..800 gave **68 px** in the
  reference (scattered x470..810 y751..766 — the space bar's own `rim` highlight)
  against **4,917 px** in the port, of which rows 777-782 alone were 3,819 in a
  solid x257..1022 bar.
* `html:340` `<line id="typebar" x1="500" y1="168" x2="500" y2="80"
  stroke="url(#barG)">` — a vertical line, bbox 0x88, `barG` is horizontal, so
  the box width is zero. This one held the frame's `max |delta|`: the port painted
  a 4.9px bar of flat `#f3f5f6` at x=640 straight across the dark basket opening
  where the reference reads (6,5,5) — `|delta|` 229..242.

**Worth recording as a refuted micro-iteration:** these two were *correct* to
remove and bought only **107 px** (262,564 -> 262,457). Removing the skirt merely
exposed an equally-wrong shell underneath. An `ab` between the two raws showed
4,998 px changed in total, all inside the two intended rectangles. Correctness and
score are separate questions; attribute a change with `ab` before concluding
anything worked.

The same rule is why `chromeB` still paints correctly on the ribbon cups
(html:299/302), the badge (html:311) and the knob/lever fills — those ellipses
and rects have non-degenerate bounding boxes.

### 5.2 `gradShape` could not represent any real gradient — replaced

The old helper was three layers: a flat mid fill, a top overlay drawn from above
at 0.45 alpha, and a bottom overlay drawn from below at 0.40. That can only ever
fake a two-stop vertical ramp, and the `drawBody` keyboard well used a 40-band
trapezoid stack over `W_TOP=128 .. W_BOT=300`.

**The well's bands were on the wrong range.** `W_TOP/W_BOT` are the y of the
path's SIDE EDGES; `P_WELL`'s bbox is user-y **120..314** (html:318). So the
bottom ~11 screen rows (user-y 300.6..314 -> screen 765.6..776.5) were left
holding the darkest stop. The arithmetic fingerprint was exact:
`(112,151,135) = 0.85*(104,143,128) + 0.15*shell`.

**And there was a +9/255 lift in the stops papering over it.** The old notes
recorded the well as "-6..-12 dark" and compensated by lifting every stop by
9/255. With the ramp correctly parameterised the source's own stops reproduce the
reference to 1/255 and the lift had to come OUT. After the rebuild port y767-790
is d=0..2.

The replacement is `gradShapeV` / `gradShapeH` / `gradRectV`: cut the target's
bounding box into N strips and re-draw the SAME path or rounded rect under each
strip's own `clip`. Because every strip re-draws the whole shape, the real curves
and corner arcs survive at every band, and `Draw.clip` is a genuine
`clipRect` (shim `skia_shim.cpp:1408`) that intersects with the current clip, so
`save`/`clip`/draw/`restore` brackets it correctly. `radialShape` is the same
trick in 2D.

Hand-verified before building: at screen y765 (user-y 300.1, `t = 0.9284`) the
well stop is (140,186,165); the enamel shell beneath at `f = 0.904` is
(127.9,173.6,153.1); `0.85` over that gives (138,184,163) against the reference's
(138,184,164).

### 5.3 Six gradients the port was painting FLAT in their own mid stops

Each was a single flat colour standing in for a real gradient:

| what | source | was |
|---|---|---|
| key `rim`, all 45 keys | html:276 | flat `0xFFA7AFB4`, its 0.40 stop |
| space bar cap | html:279 `spacebar` | flat `0xFFFFFAF0`, its 0.0 stop |
| ribbon cups x2, badge | html:277 `chromeB` | flat `0xFFB3BABE`, its 0.35 stop |
| paper bail, margin scale | html:225 `chromeV` | flat `0xFFD7DCDF` |

The space bar was the loudest: over x455..815 y750..772 it was **87.41%**
differing at mean `|Δ|` 41, the port reading a flat (255,250,240) where the
reference ran (226,213,181) at y764.

`chromeB` and `chromeV` (html:277 / html:225) are the same five stops under two
names; both are transcribed once as `chromeStops`.

### 5.4 The basket was a flat fill standing in for a radial

`radialGradient id="basket" cx=".5" cy="0" r="1"` (html:273) on `P_BASKET`'s
bbox user-x 330..670 / user-y 4..76, so the centre is (500,4) with semi-axes
(340,72) user units and the ramp is `#050404 -> #1c1917 at .7 -> #2d2825`. The
port painted flat `(28,25,23)` — its own 0.7 stop — across the whole opening.
Rows 513-519 alone held ~6,500 differing px, the worst run in the frame.

The model was confirmed against the reference before implementing: at x=640
(`u = 0`), y=540 gives `v = 0.2959`, `frac = 0.4227`, so (14.6,12.6,11.7) against
the reference's (15,13,12). After the fix the centre column reads d=0..2.

### 5.5 `.m-hide` is inside `@media (max-width:700px)` — the card was a line short

`html:148` `.card .m-hide{display:none}` reads like a desktop rule. It is not: it
sits inside `@media (max-width:700px)` (html:143-149) together with the whole
restyled mobile card. At 1280px it does not apply, so `(It never erases a thing.)`
(html:177) **is** laid out and the card is **seven** 22px lines:
`7*22 + 12 + 10 = 176`, not 154.

Because the quad is rotated -4° about its own centre, a 22px height error also
swings every corner. Measured at x=100 the reference's card runs to y538 and the
port's stopped at y517. Region `0,330 320,620`: 29.33% -> 24.83%, mean `|Δ|`
21.64 -> 11.44.

**Grep for the media query the rule sits in before trusting any `display:none`.**

### 5.6 `drawRear` banded at `hgt/7` but sized each band `hgt/8` — six dead rows

The rear sheet is 8 stacked bands. `f` stepped `e/7` (so band tops were `hgt/7`
apart, the last landing exactly on `top+hgt`) while the height was
`hgt/8 + 1`. Consecutive tops were 59px apart and each band only covered 51.6px,
so **6 rows of bare desk showed through every seam**.

That is the entire signature: three bands at y214-219, y273-278 and y332-337,
a strict 59px period, 6 rows each, at `|delta|` 145 with the reference reading
paper and the port reading desk. Fixed by making pitch and height both use the
band count; the count also went 8 -> 16 to halve the visible alpha step
(`.42/8 = .0525`, about 10/255 per band).

Region `320,204 960,306`: 29.76% -> 20.35%, mean `|Δ|` 18.51 -> 6.59.

**Always check that a band's height equals its pitch.** Any `f = e/(n-1)` loop
that also sizes bands by `hgt/n` leaves `hgt/n(n-1)` of gap per seam.

### 5.7 REFUTED — the key array is NOT horizontally offset

The older notes in this file claimed the keyboard reads "like a horizontal offset
of about one key pitch", from a ~60px alternation in the key rows. That is wrong.

`an.mjs`'s `shift` mode cross-correlates: for each integer `dx` it reports the mean
`|Δ|` over a rectangle with the port sampled at `x+dx`. Minimiser, on v2:

| region | `dx=0` | `-1` | `+1` | `-2` | `+2` |
|---|---|---|---|---|---|
| row 3, y726-754 | **22.36** | 22.72 | 24.88 | 25.81 | 27.46 |
| row 0, y630-656 | **17.67** | 17.96 | 20.23 | 20.93 | 22.85 |
| space bar, y752-772 | **40.66** | 40.84 | 41.01 | 41.33 | 41.61 |

`dx = 0` wins everywhere, by a clear margin. The ~60px period is the key pitch
appearing in the legend and the cap texture, not a displacement.

**The first version of that instrument was itself buggy and worth flagging:** it
called `dmax(i, ref, port)` with the same index for both images, so `dx` never
entered the comparison and every shift printed an identical mean. It looked like
a strong, flat, believable result. Fix and re-run before believing a correlation
tool's output — the same discipline that applies to `pngdiff.mjs`.

## Round 5 — what is still there, and what is not reachable

Remaining budget is 174,456 px, 16.70%. 8x8 grid, cell 160x102,
`% differing | signed luma (port - ref)`:

```
y0-102   27  23  22   6  34  39  45  40     2.6  12.2   5.5   2.2   9.5  -7.0  -9.5  -7.7
y102-204 13  14  12   7  26  12   0   0     2.5   1.9   2.2   0.4   3.1   2.3  -0.5  -0.1
y204-306  2   1  14  20  20  27   1   1    -0.1  -0.2   1.5  -3.3   3.3   5.8  -0.1  -0.1
y306-408 14  11  15  23  15  11   0   0    -1.1   1.2   1.2   0.9   4.8   3.6  -0.4  -0.4
y408-510 28  30  23  20  16  25   6   0     8.6   4.6   5.3  11.4   4.9   4.4  -0.8  -0.6
y510-612 27  30  16  29  29  17   8   5    -0.9  -2.8   0.2 -11.4 -10.4   0.3   2.9  -1.0
y612-714  5   5  16  25  23  17  12  35    -1.7  -1.3   0.1   1.1   1.5  -0.1  -2.7 -40.3
y714-816  0   3  19  37  39  26   2   0    -0.0  -0.6  -0.8  -2.2  -2.5  -2.4  -0.7  -0.2
```

* **Header buttons, y0-102 x640-1280, ~25,800px — NOT REACHABLE.** Two separate
  reasons, both established:
  1. The `.btn` fill is `radial-gradient(120% 140% at 50% 20%, #fffaf0 0%,
     #f2e7cc 62%, #dccfae 100%)` (html:99). The header controls are real Yantra
     **nodes** (kept for native hit-testing and focus), and
     `sdk/ui/style.nim:29` exposes only `linear(a, b, angle)` — a two-stop
     linear, no radial, no multi-stop. The radial model was verified against the
     reference (predicted (249,241,226) at the button's centre-x and (243,234,214)
     at its edge; the reference reads (249,242,224) and (245,236,217)) but there
     is no way to express it through a node fill. The residual is a d=16..26 tone
     offset across the button faces.
  2. The button x-positions differ by up to 37px (`find` for the ring colour
     `#7d868b`±22 over x600..1280 y20..95 gives x616..1255 in the reference and
     x653..1251 in the port). That is the monospace-vs-proportional gap.
* **Tag, y612-714 x1120-1280, 35% at -40.3 luma.** The tag *is* drawn, as a node,
  and correctly filled with `linear(0xF6ECD2, 0xE9DCBC, 90)`. It is simply ~23px
  short (the reference's cream runs y576..695, the port's y582..607 measured on
  the top stop), sits 11px left, and has no `clip-path` notch. Node layout, not
  `Draw`.
* **Below the keyboard, y714-816 x320-960, ~19,800px.** Two separable causes:
  row 791 alone is 93% differing at **+46.1 luma** (the shell's bottom edge — the
  port shows a green-tinted AA blend at y791 where the reference is already plain
  desk; at y789 both are exactly (121,168,147)), and rows 792-815 run 35-84% at
  -6..-8.5 luma, i.e. the port's machine shadow is slightly too strong on the desk.
* **Card text and body, y408-510 x0-800.** Typeface, plus a +8.6/+4.6/+5.3 luma
  residual.

Still blocked and deliberately untouched: the **typeface** (`Draw.text` passes a
literal `nullptr` family at `libs/nimskia/src/skia_shim.cpp:1354`; `TextOpts::family`
is honoured but unreachable because the shim falls back to a hardcoded
`{Segoe UI, Nirmala UI, Segoe UI Emoji}` stack at `:142`; the reference is
monospace) and the **paper grain floor**, already proven saturated by a previous
round. Re-measuring either wastes a build cycle.


## Dead ends

### 5.8 REFUTED — `closest-side` does not mean a circle here

Round 5 chased the last big reachable block (y792-815 across x250..1080, ~10,000
px at -7..-9.4 luma) and got it wrong in an instructive way.

The map said the desk residual was **0% at x<175 and x>1075, rising to 100% in the
middle of the footprint and falling symmetrically** — 4% at x275, 50% at x475, 100%
at x700-800, 4% at x950. That is "too much alpha in the middle of the shadow", and
it is visible only inside the ellipse, so the desk itself is right and the shadow
is wrong.

`#shadow` (html:32) is
`border-radius:50%; background:radial-gradient(closest-side, rgba(12,6,2,.72), rgba(12,6,2,.35) 55%, rgba(12,6,2,0))`
on a box `place`d at `(MX-MW*0.06, MY+300U, MW*1.12, 210U)` (html:493) — i.e.
1097x172. Read literally, `closest-side` takes the NEAREST side, which is the
vertical one, so the ending shape is a **circle** of radius `h/2 = 86` about the
box centre; and `border-radius:50%` clips the background to an ellipse that
*strictly contains* that circle, making the clip a no-op. On that reading the
visible shadow is a 172px circle, not the 1097px ellipse the port has been drawing
all along.

Implemented it. **17.22%, mean 9.82 — worse on both metrics.** Reverted; v8
reproduces v6 byte-for-byte.

So the 5.33:1 ellipse that a previous round settled on is correct, and the literal
reading of `closest-side` is not. Left in the source next to the band loop so the
next person does not have to spend a build cycle on it.

**What I should have done first:** the port already drew an ellipse. Before
replacing a shape, find a pixel where the two candidate shapes predict *different*
answers and check which one the reference agrees with — do not rebuild and score.
Under the machine the desk is only visible in the strip y792..815, which is enough
(y=845, the clean discriminator, is off-frame), and `an.mjs row/rect` would have
settled it without a build. I substituted a whole build+render+diff cycle for one
`rect` query.

### 5.9 REFUTED (re-confirmed) — the machine shadow's silhouette

The previous round's refutation of "14 plain circles of radius up to `MW*0.56`
centred on the shadow box's TOP edge" **stands**. That was a disc 86px too high
with a much larger radius. The current ellipse (same centre, `rx = MW*0.56`,
`ry = 210*U/2`) is a different shape and is right. Do not conflate the two — they
look alike in the code and only differ in centre and aspect.

* **"The 43.87% baseline was measured on an un-swapped raw."** Disproved — the
  un-swapped control gives 99.19%. The prior number was already honest. Recorded
  so it does not get re-raised.
* **Reading the reference image directly.** `read` refuses the PNG ("binary
  file") and `read_image` fails with "model ling-3.1-flash-free does not declare
  image input". Every visual conclusion in this file therefore comes from decoded
  pixels via `pngdiff.mjs`, `refdiff.mjs`, `.board/mean.mjs` and the scratch
  scripts under `.board/frames/tw/` and `.board/frames/tw2/`. This round added
  `reg.mjs` (one rect, both images, same argv for PNG and raw, fails loudly on a
  size mismatch or empty rect), `scan.mjs` (per-row/col mean RGB + signed delta),
  `ink.mjs` (ink runs for both images from one argv), `prof.mjs`,
  `ab.mjs` (differing count BETWEEN two raws, to attribute an A/B edit to a
  rectangle instead of guessing), and `go.ps1` (build -> render -> rawswap ->
  size guard -> pngdiff; refuses to diff a wrong-sized raw).
* **`refdiff.mjs` ignores its region arguments.** Passing `x0 y0 x1 y1` still
  printed the global result and then "no reference ink above threshold in this
  rect". Localisation had to be done with `grid.mjs` and vertical profiles
  instead.
* **`formatFloat` for path data** — see defect 1. Cost one build+render cycle
  that moved the number by 0.00%.
* **The paper clouds are now too faint.** The reference has 72.11% of the sheet
  within 4 of cPaper, the port 88.23%. The alpha fix took out most of the cloud
  formation; the residual is a slightly too-flat sheet. Not corrected — trading
  texture back in needs the per-disc alpha re-tuned against the reference, and
  the direction is not yet measured.
* **Pinning the label's height explicitly** as well as trimming its padding made
  no difference at all (274,566 both ways) — Yoga derives the same box from the
  content. Recorded so nobody re-attributes the regression to the pin.

## Engine and tool gaps (reported, NOT fixed — out of write scope)

1. **`.board/mean.mjs` silently returns `n=0` / `NaN` for a PNG.** It reads the
   rect from `argv[3..6]` when the path ends `.png` but `argv[5..8]` for a `.raw`,
   so a PNG call with the documented argument list reads x0=1280, y0=816,
   x1=320, y1=714 — an empty rect — and prints `n=0` as though the region were
   blank. A perfect result that looks exactly like a catastrophic bug.
2. **`tools/rowink.mjs` cannot read a PNG.** It assumes stride `W*4`, so pointing
   it at the reference PNG reads garbage and prints "no text" where text is.
3. **Node gradients stop at two stops.** `pGradFrom`/`pGradTo`/`pGradAngle`
   (`sdk/core/wire.nim:164-166`) admit no middle stop, so the three- and four-stop
   radials in this page — `.btn`'s `radial-gradient(120% 140% at 50% 20%,…)`,
   `#cap`, `#rim` — cannot be expressed on a node. `sdk/ui/style.nim:29`'s
   `linear` takes exactly `a, b, angle`. An SkSL `shader` is the documented
   answer but is a per-node string and cannot be used inside a `Draw` list.
4. **No node-level rotation or transform.** `sdk/core/wire.nim` has no rotate or
   transform prop, so `.label`'s `rotate(-1.4deg)`, `.tag`'s `rotate(3deg)` and
   `.card`'s `rotate(-2.5deg)` are all unrepresentable. `Draw.rotate`
   (`sdk/ui/paint.nim:79` -> `skia_shim.cpp:1411`) exists but only inside a canvas
   `Draw` list. This is the whole remaining error in the `.label` bottom edge.
5. **No text measurement API** (`sdk/ui/paint.nim:63`, still open as E1) and
   `Draw.text` cannot name a typeface — `libs/nimskia/src/skia_shim.cpp:142`
   hardcodes Segoe UI against this page's Courier stack, ~9-16% wider. Every
   advance estimate in this port is therefore marked INFERRED and cannot be
   verified from inside.
6. **`drawPath` is non-zero winding with no way to ask for even-odd.**
   `libs/nimskia/src/skia_shim.cpp:1337` passes the path to Skia with no fill
   type, so it takes `SkPathFillType::kWinding`. Every hole has to be wound
   opposite AND geometrically contained, which is a real trap — a hole that
   overhangs its outer shape fills the overhang. See 4.4(b).

## Not done

* No git command was run. Nothing outside `apps/typewriter/app.nim`,
  `apps/typewriter/port-notes.md` and `.board/frames/tw2/` was modified.
* The header's remaining 34.60% is now dominated by **text**, not tone: the label
  ink is at rows 45-70 in the port against 40-61 in the reference (h1 is 5px low
  and 4px taller), and the plate's bottom edge carries the un-rotation of 4.4's
  gap 4 above. Both are the font/rotation gaps, not geometry.
* The key caps' **ramp profile** is still off even though their geometry now
  matches: the reference peaks at y635-636 while the port peaks at y640-641,
  because folding the gradient centre's (0.16r, 0.36ry) offset into a single
  scale factor cannot put the highlight back where it belongs. A per-band
  offset contour set, clipped to the cap, is the real fix and is not written.
* The desk under the machine is still ~5 luma dark (DESKLEFT `d(mean)`
  -4.2/-5.6/-5.3) after the shadow shape fix — the residual is the lamp radial
  and the plank grain, not yet localised.
* The blue caret row, the card's remaining ~13 luma, and the paper clouds (see
  Dead ends) are all still open.
## 17. Lane opened on the typewriter — baseline re-verified, blockers identified

Switched here from the gallery after eight rounds without a pixel change (16.24).

**Baseline re-measured from a fresh build**, per hard rule 2 — the committed `app.wasm`
was not trusted, `tools/build-wasm.sh` rebuilt it (`wrote apps/typewriter/app.wasm`,
453,703 bytes).

    render 1280x816, 'wait:8'   ->  31.82% @ tol 8   (mean |d| 12.60, max 232)
                                  8.66% @ tol 24

**The 1280x816 height is not a detail.** `drive.exe ... 800` is refused by
`tools/pngdiff.mjs` — *"reference is 1280x816, frame is 1280x800 — refusing to compare"*.
This is the only `clientWidth` page, so it is captured **with** the browser's chrome
(R18c): window 1280x816, layout 1280x800. Scoring it at 800 is not a small error, it is a
refusal — which is the correct behaviour and worth keeping.

### What I measured, and what I nearly got wrong

The worst rows at tol 8 are **807-813, each differing on all 1,280 columns** — a
full-width band at the very bottom. That looks like a cheap structural fix, and the
per-pixel read is dramatic: at (600,810) reference `(78,48,25)` against port `(52,28,15)`.

It is not a cheap fix. Profiling the bottom row across x gives a smooth
**-8.3 at the edges to -16.4 at centre** — a gentle gradient, i.e. the desk plus the
machine shadow, not a hard-edged defect. And the desk itself is basically right:
sampled away from the machine, ref/port ratios run **0.88 - 1.18**. The notes' "~5 luma
dark" is accurate.

**Then I sampled single points and nearly drew the opposite conclusion.** At y=20 the
ratio read 1.64, 1.88 and 2.25, which looks like the header being catastrophically dark.
It is not. Per-rect statistics over the same header:

| rect | ref mean / %bright | port mean / %bright |
|---|---|---|
| label badge | 189.7 / 66.1% | 198.8 / 67.8% |
| ribbon toggle | 175.2 / 52.4% | 179.6 / 50.2% |
| new sheet | 139.0 / 44.8% | 136.4 / 39.2% |
| save letter | 192.5 / 74.2% | 177.8 / 59.8% |

The header's tone is close. The bad single-point ratios were **gaps between glyphs** —
reference bright ink where the port has desk. So the header's error is **text
geometry**, exactly as the notes say, not tone. Sixth time this session that a
single-pixel or single-region read inverted the conclusion; the per-rect statistic is
what settles it.

### The remaining error is three engine gaps, not app code

The band map's worst rows are y 204-306 (47/45/30/20/20/57/46/52%) and the header's
right half. All three trace to SDK limits already on file:

1. **`Draw.text` cannot name a typeface** - `libs/nimskia/src/skia_shim.cpp:142`
   hardcodes Segoe UI against this page's Courier stack, ~9-16% wider. Every advance in
   the port is INFERRED and unverifiable from inside.
2. **No node-level rotation** - `sdk/core/wire.nim` has no rotate prop, so `.label`'s
   `rotate(-1.4deg)`, `.tag`'s `rotate(3deg)` and `.card`'s `rotate(-2.5deg)` are
   unrepresentable on a node.
3. **Gradients stop at two stops** - `pGradFrom`/`pGradTo`/`pGradAngle`
   (`sdk/core/wire.nim:164-166`) admit no middle stop, so the 3- and 4-stop radials here
   flatten, and 60.1% of the y204-306 region sits pinned at the top stop.

**These are engine-level and they block more than this app.** (2) and (3) also bite the
gallery and calligraphy. Fixing a multi-stop gradient in `Draw` would unblock three apps
at once and is a far better use of a round than another app-local tone tweak. That is
the next thing to evaluate.

### 17.1 The typewriter's headline blocker is STALE - `Draw.textFace` exists and the chain is complete

The port notes list as gap 5: *"`Draw.text` cannot name a typeface — hardcodes Segoe UI
against this page's Courier stack, ~9-16% wider. Every advance estimate is therefore
marked INFERRED."* Reading the engine rather than the notes, **that is no longer true.**
Traced the whole chain, every link read in source:

| link | file:line | state |
|---|---|---|
| `Draw.textFace(x,y,size,argb,family,s,weight)` | `sdk/ui/paint.nim:65` | **exists**, emits verb `N` |
| `case 'N':` in `runCmds` | `skia_shim.cpp:1360` | handled, calls `yk_text_draw2` with the family |
| `yk_text_draw2` accepts a family | `skia_shim.cpp:318` | `o.family = family` (:351) |
| family actually applied | `skia_shim.cpp:139-140` | `if (!fam.empty()) ts.setFontFamilies({fam, "Segoe UI", ...})` - **family is FIRST** |
| native font manager | `skia_shim.cpp:84` | `SkFontMgr_New_DirectWrite()` - **real system fonts** |
| the page's stack | `029-...html:315` | `'Courier New','Nimbus Mono PS',monospace` |
| Courier New on this machine | `C:\Windows\Fonts\cour.ttf` | **PRESENT** |

The `N` verb's own comment (`skia_shim.cpp:1365`) records the landing: *"yk_text_draw2
(:318) already accepted a family; it was simply..."* — D6 was implemented and the notes
were never updated.

**The `/fonts` alias table at `skia_shim.cpp:63-82` is `#ifdef __EMSCRIPTEN__`** and is
irrelevant to us: the native branch uses DirectWrite, so every installed Windows font is
addressable by name. No font shipping is required.

**And the app is not using it.** `apps/typewriter/app.nim` has **12 `.text(` calls and 0
`.textFace(`**. The capability is right there and every string is still defaulting to
Segoe UI.

**What this is NOT yet.** I have verified the *plumbing*, not the *outcome*. Unproven
until a render shows it:
- that naming "Courier New" changes the drawn glyphs in the live native path,
- how much of the ~9-16% width error it recovers,
- whether Courier New's metrics match the browser's Courier (it should — same face).

**Rule 6 gap, which I should have found earlier.** `textFace` is SDK surface with **no
test in `render/t_qml.nim`** — `grep` for `textFace` or the `N` verb there returns
nothing. Rule 6 says the SDK only promises what the renderer draws, and the test is how
that promise is kept. An untested SDK verb is exactly how a note goes stale unnoticed.
Adding an `N`-verb test belongs with the conversion.

**Next, concrete:** convert the 12 `.text(` calls to `.textFace(` with the page's actual
stack (`'Courier New','Nimbus Mono PS',monospace` -> `"Courier New"`), add the
`t_qml.nim` `N`-verb test in the same task, then re-score at tol 8 against the 31.82%
baseline. Note the family and string are `;`-terminated with **no space between them**
(`paint.nim:72-73`) — `rest()` stops at the `;`, so a space would silently become part
of the font name.

### 17.2 Done: the typeface is named, the verb is tested, and the win is small

Converted **11 of the 12** `.text(` call sites to `.textFace(` with `"Courier New"`.
Left the script badge `"Marlowe"` (app.nim:1569) on `.text(` because `html:313` uses the
page's *cursive* stack (`'Brush Script MT','Snell Roundhand','URW Chancery L','Z003',
cursive`), not `--mono`. That one needs a different investigation.

**Which family, and why "Courier New" is not a guess.** `html:315` asks for
`"Courier Prime","American Typewriter","Courier New","Nimbus Mono PS",Courier,monospace`.
On this machine Courier Prime, American Typewriter, Nimbus Mono PS and Courier are all
**absent**; only Courier New (`cour.ttf`) is installed. Headless Chrome resolved `--mono`
on this same machine, so it rendered the reference in Courier New too. Naming Courier New
matches the reference's actual face rather than the page's first preference.

**Measured, tol 8, 1280x816:**

    before   332,384 differing  31.82%   mean |delta| 12.60
    after    331,926 differing  31.78%   mean |delta| 12.55

Small. Two things were measured rather than assumed, because "the pixels changed" and
"it got better" are different claims:

* **The family is actually applied.** Diffing the two rendered frames against each other
  gives **3,110 px changed across 78 rows**, all on text rows (375-384, 661, 690, 724).
  A silent fallback to Segoe UI would be a **zero**. So verb `N` reaches the font stack.
* **It moved the right way.** Mean `|delta|` against the reference over rows 350-400 (the
  paper letter) went **5.803 -> 5.699, -1.8%**. Closer, not merely different.

The score barely moves because text ink is a small fraction of those rows. The dominant
errors are elsewhere: **rows 807-813 still differ on all 1280 columns**, and rows 205-206
and 22 are next. Blocker 5 of the "SDK gaps" list is now closed and it was worth ~0.04pp.
**Gap 2 (node rotation) and gap 3 (two-stop gradients) are now the larger items, and they
block the gallery and calligraphy too.**

### 17.3 Two mistakes of my own, both worth the ink

**1. PowerShell quoting silently ate source text.** I rewrote the 11 call sites with a
PowerShell `.Replace()` loop. It reported "converted 11 / 11" — and the build then failed
with `expected: ')', but got: 'keyword var'`, because lines 724-725 had been truncated to
`d.textFace(0, 0, 30.0'f32, c, ` with the family *and* the string *and* the weight gone.
The loop's own success counter was worthless: it compared strings that had already been
mangled, so "changed" meant "changed", not "correct". **`git checkout --` the file and
verify the emitted text, not the count.** The same trap later bit an `edit` call, where a
source line containing the literal `"\u00B7"` never matched because JSON had already
decoded `\u00B7` into the middot character.

**2. My arg-splitter treated Nim's numeric suffix as a char literal.** Rewriting the file
with a real parser, `5.2'f32 * U, 0xFF2B2725'u32` parsed as a **string** argument, because
the `'` of `'f32` opened a "char literal" that swallowed forward to the next `'`. Two
arguments merged and the family landed in the wrong slot:
`textFace(x, y, size, argb, $c, "Courier New", 700)`. The fix is to treat `'` as a quote
only when a closing `'` follows within a few chars, and otherwise as a type suffix. Caught
by printing every converted line and reading them, not by the compiler. **`'f32`/`'u32`/
`'i32` are suffixes, not quotes — anything parsing Nim source needs to know that.**

### 17.4 sdk/tests/t_paint.nim — the rule 6 test that should have existed

**Nothing under `sdk/tests/` imported `sdk/ui/paint.nim`.** Not one canvas verb had a
test. That is precisely how the 17.1 note went stale for so long: an SDK verb can lose its
renderer mapping or its spelling and no test notices, because there is no test. Rule 6 —
"the SDK only promises what the renderer draws" — is only enforceable if something asserts
the promise.

16 checks, 0 failed. The load-bearing one is the delimiter rule from `paint.nim:72-73`:
family and string are `;`-terminated with **no space between them**, because the shim's
`rest()` stops at the `;`. A space silently becomes part of the font name, the family
resolves to nothing, and everything falls back to Segoe UI **with no error anywhere**. That
is the exact trap this app walked into.

The test earned its place on first run by catching a wrong expectation of mine: I
hand-computed `0xFF112233` as `16849907` when it is `4279312947`. Fixed the expectation,
not the code — which is the only correct order.

### 17.5 CORRECTION to 17's gap 3 — I was wrong about multi-stop gradients

Last round I told you *"a multi-stop gradient in `Draw` would unblock three apps at once"*
and queued it as a todo. **That was wrong, and checking the engine is what caught it.**

`sdk/ui/paint.nim`'s entire exported surface, read from the file: moveTo, lineTo, quadTo,
curveTo, arcTo, close, svgPath, fill, stroke, rect, circle, line, text, textFace, image,
layer, pixels, blend, save, restore, translate, scale, rotate, alpha, clip, newLayer,
draw, clear, filter, read, write, free.

**There is no gradient primitive on the canvas `Draw` at all** — not a two-stop one, not a
four-stop one. So there was never anything to "extend". The accurate picture is:

* **Canvas `Draw`** — no gradient. An app must build one. This port does, and does it
  correctly: `bdStopColor` (app.nim:393) implements the lamp's **four** stops as a
  piecewise lerp, and `bdLampLight` (app.nim:411) emits them as concentric **stroked
  annuli**, one pass per band, because a stroked circle covers each pixel exactly once —
  unlike stacked translucent discs, which over-brighten the middle and band.
* **Node props** — `pGradFrom`/`pGradTo`/`pGradAngle` (`sdk/core/wire.nim:164-166`) really
  do admit only two stops. That gap is real, but it is a **node** gap.

Verified the lamp itself is faithful: `bdLampStops` (app.nim:385-389) is
`(255,214,150,.50) (255,190,120,.20) (40,18,6,.15) (10,4,1,.62)` and `bdLampAt` is
`[0.0, 0.35, 0.75, 1.0]` — an exact match for `html:572`, offsets included.

**So the canvas is not the bottleneck and should not have been on the list.** The node
two-stop limit is worth raising as an SDK item; canvas gradients are a solved problem here.
That is the second time in two rounds a port note described a blocker the engine no longer
has — after `textFace` in 17.1. **These notes are older than the engine. Verify a gap in the
engine before planning work around it.**

### 17.6 Rows 807-813: still unresolved, but three suspects eliminated

The worst rows at tol 8 differ on **all 1280 columns**, which is what makes them the top
target. Worked the cause down; it is not what the first readings suggested.

* **Not a height seam.** `html:24` sets `body{background:#3a2212}` = `(58,34,18)`, luma
  39.4, and the port's bottom-centre reads almost exactly that — which looked like the desk
  stopping at y=800 and the body showing through the last 16 rows. It does not. A vertical
  profile at x=60 (far from the machine) shows desk grain continuing straight through
  y=800 to y=815 in **both** images, with no discontinuity.
* **Not the lamp.** The four stops and their offsets match `html:572` exactly (§17.5).
* **Not the shadow's shape.** Already tested and recorded — the `closest-side` circle
  reading was implemented and **refuted** (v7: 16.70% -> 17.22%), leaving the 5.33:1 ellipse
  in place. Not re-litigating a settled measurement.

What is actually left is a **uniform desk darkening**, not a gradient-shaped defect.
Per-channel at (60,810): reference `(103,62,31)`, port `(88,51,25)` — deltas **15/11/6**,
roughly proportional to the plank colour, i.e. the port sits at ~85% of the reference
across the bottom rows. At x=600 (under the machine) the deficit is larger, ~-16 luma,
because the shadow adds to it. A hand-derivation of `html:571-573` at (60,810) predicts
`(97.9,57.3,29.3)` against the reference's `(103,62,31)` — within ~5 — so the source
compositing is right and the port is ~10% low somewhere in plank tone, lamp alpha, or the
plank/lamplight order.

**Not yet localised to a line.** Next step is a differential probe: render the desk with the
lamp bypassed and compare plank tone alone, rather than continuing to infer from profiles.

### 17.7 Differential probe: the lamp is innocent, the planks are not

Bypassed **only** `bdLampLight` (app.nim:488), leaving planks, grain, seams, knots and the
warm bloom in place. Patch verified applied before building, and the rendered frame changed
**613,442 px (58.7%)** — a zero would have meant the bypass missed.

    region                    reference      port FULL     port NoLamp
    bottom-left  x20-300      105.7,64.1,33.5  95.8,56.6,28.5  89.0,54.4,26.5
    bottom-mid   x400-900      75.5,46.2,24.2  58.5,32.7,16.9  61.8,34.8,17.9
    top-left     x20-200      204.1,187.7,165.3 212.2,193.7,170.8  197.9,180.4,161.2

    lamp contribution (portFULL - portNoLamp)   what the reference implies (ref - portFULL)
    bottom-left     0.8, 2.2, 1.9               9.9, 7.5, 5.1
    bottom-mid     -3.3,-2.1,-1.0              17.0,13.5, 7.3

**The lamp is behaving correctly.** At `t ~ 0.70` the `.35 -> .75` segment is heading *into*
`rgba(40,18,6,.15)`, so a small net darkening is exactly right, and that is what the port
applies. The lamp is not the cause and can be closed.

**The planks are.** With the lamp bypassed the port still reads `(61.8, 34.8, 17.9)` against
the reference's `(75.5, 46.2, 24.2)`. Undoing the warm bloom too puts the port's plank at
roughly **47 R**, while the source's plank tones (`html:550`) are `92,52,26 / 104,60,31 /
86,48,24 / 98,56,28`, each with a gradient running `t+6` to `t-8` — so the darkest plank
value the source can produce is **78 R**. The port's bottom planks are **well below the
darkest value the source is capable of**, which no combination of tone and gradient explains.

Confirmed by elimination: no vignette overlay exists (`d = d.layer(deskLayer, 0, 0)` at
app.nim:2346 is the only desk composite), no height seam (17.6), and the lamp is correct.

**And the notes' standing theory is wrong in direction.** They attribute the residual desk
error to "the lamp radial and the plank grain". The lamp is now cleared. The grain cannot be
it either: app.nim:325 multiplies each line's alpha by **0.75**, making the grain *weaker*
than `html:559`'s `(0.08 + r()*0.2)`, so it can only make the desk lighter. The desk is
darker. **A 25%-too-weak grain is not the explanation for a 40%-too-dark desk.**

**A comment that does not match its code** (app.nim:323-325):

    ## ...the stroke is split into two passes at half alpha instead of one hard line.
    a = a * 0.75

There is one pass, at 0.75 alpha — not two passes at half. Harmless in itself, but it is the
kind of drift that makes the next reader trust a mechanism that is not there.

**Next probe, not yet run:** with the grain bypassed as well, the port's planks should land
near the source's tones. If they do, the error is the *number or placement* of grain lines
(or a desynced PRNG stream — `bdNext` ordering), not their colour or alpha. Worth checking
the random stream too: at `x=60`, `y=786..815`, the reference's luma runs
`81,75,75,75,75,71,64,64,75,66,71,58,55,66` and the port's runs
`60,64,57,51,59,68,64,61,67,67,67,67,71,70` — **uncorrelated**, which is what a desynced
`mulberry32` stream would look like, and it would move every plank tone, seam and knot at
once.

### 17.8 RETRACTION of 17.7, and the real cause of rows 807-813

**17.7 was wrong.** It concluded *"the planks are 40% too dark."* They are not. The
`portNoLamp` figure it reasoned from still contained the **machine shadow** — I bypassed
the lamp and then attributed the remainder to the planks without isolating the other dark
layer sitting on top of them. That is the same mistake this section has already logged twice
(17.7's own lamp probe, and the §16.21 mirror probe in the gallery): **bypass every
producer, not just the one you are probing.** My own rule, broken in my own note, one round
after writing it down.

Redone with **both** the lamp and the machine shadow bypassed — plank body, grain, knots,
seams and warm bloom all still drawn, which is the desk layer alone:

    region                   reference        port (desk only)
    bottom-mid x400-900       75.5, 46.2,24.2  103.4, 61.8, 31.7
    bottom-left x20-300      105.7, 64.1,33.5   97.0, 55.7, 27.2
    top-left   x20-200       204.1,187.7,165.3 197.9,180.4,161.2
    mid-left   x20-200       231.2,224.7,211.0 241.1,235.0,221.0

**`103.4` is squarely inside the source's own plank range** (`86..110` R across the four
tones and their `t+6..t-8` gradient). The planks, grain, tones, gradient and PRNG are all
fine. 17.7's "below the darkest value the source can produce" was an artifact of an
unremoved dark layer.

**The arithmetic now names the culprit exactly.** At bottom-mid:

    desk alone (port)                      103.4
    port, shadow on only (lamp off)         61.8   -> shadow removes  41.6
    port, lamp + shadow on (the real app)   58.5   -> lamp removes      3.3
                                               total port removes   44.9
    reference                              75.5   -> must remove      27.9

So **the lamp is nearly innocent (3.3) and the machine shadow does almost all of it (41.6)
— and the port darkens the bottom of the frame 1.61x too hard.** The shadow is the defect,
exactly where the worst rows are (807-813, all 1280 columns).

**Where the shadow is wrong is still open.** `html:32` is
`border-radius:50%; background:radial-gradient(closest-side, rgba(12,6,2,.72),
rgba(12,6,2,.35) 55%, rgba(12,6,2,0))` on a box `MW*1.12 x 210*U` (placed at
`html:493`). The port draws an **ellipse** with `rx = MW*0.56`, `ry = 210*U/2` (app.nim:2311-2314),
and `shAlpha` reproduces the stops exactly (`.72 / .35 at .55 / 0`), so the *profile* is
right and the *shape* is the suspect.

Note the earlier refutation must be re-read before trusting it. The notes record that the
`closest-side` **circle** was tried and made things worse ("-7..-9.4 luma LIGHT"), which
leaves the ellipse. But a literal reading gives a circle of radius `105*U` *clipped* by the
`border-radius:50%` ellipse whose semi-axes are `MW*0.56` and `105*U` — and the clip is a
**no-op** only if `MW*0.56 >= 105*U`, which makes the result the circle, i.e. the reading
already rejected. The ellipse is measurably too strong (41.6 vs 27.9) and the circle was
measurably too weak, so **the truth is between them** and neither reading is right. That is
the shape of the bug; pinning it down needs a probe that sweeps `rx` and measures.

**Next, concrete:** a probe sweeping the shadow's horizontal extent with `ry` fixed, scoring
each against the reference's bottom band, rather than arguing the CSS reading again. The
notes' existing "REFUTED BY MEASUREMENT" block predates this measurement and should be
treated as settled-for-the-circle-only, not as a verdict on the shape.

### 17.9 Two eliminations, and the shape is bracketed from both sides

**1. The PRNG is in sync — the desync theory is dead.** Smoothed away the plank body to
leave only the fine grain, then cross-correlated the port's desk-only frame against the
reference over vertical shifts:

    shift   -4      -2       0       2       4
    corr   -0.156   0.068  0.342   0.255  -0.049

Best over -60..+60 is **shift 0**, and it decays smoothly either side. A desynced
`mulberry32` would give a flat ~0 with no peak. **The port's plank phase, grain positions,
seams and knots all land where the source's do.** 17.7 floated this as a possibility; it is
ruled out by measurement, and it also explains why the grain in both images "looked
uncorrelated" in a raw luma scan — grain is high-frequency, so a raw scan is meaningless;
you have to high-pass before correlating.

**2. The `closest-side` circle is refuted again, independently.** Built the literal reading
(`rx = ry`, which makes the y-scale 1.0 and the stack a true circle of radius `105*U`) and
measured it against the current baseline rather than trusting the old verdict:

    bottom band, x400-900 y800-815, luma
    desk only        71.0
    reference        52.7   -> must remove 18.3
    port ellipse     39.0   -> removes      32.0
    port CIRCLE      68.3   -> removes       2.7

    score: circle 31.94%  vs  ellipse 31.78%   (worse)

So the old "REFUTED BY MEASUREMENT" block holds, now re-derived rather than inherited: the
circle removes almost nothing (2.7 against a required 18.3) and costs 0.16pp.

**Correction to my own 17.8 arithmetic.** 17.8 compared the **R channel** and reported
"41.6 removed vs 27.9 needed". On luma — the metric every other measurement in this file
uses — it is **32.0 vs 18.3**, so the ellipse is **1.75x** too strong, not 1.61x. The
conclusion (the shadow is the defect, the lamp is minor) is unchanged; the factor was wrong
because two different metrics were compared in one chain.

**The shape is bracketed, and I am deliberately not fitting it.** The correct `rx` lies
between `105*U` (too weak by a factor of seven) and `MW*0.56` (too strong by 1.75x).
Interpolating linearly between the two measurements lands near `rx ~ 376`, and that number
would very probably *improve the score*.

**I have not applied it.** That is a fit to the reference, not a reading of `html:32`, and
the whole point of this lane is that the port should be right because the source was
understood — not because a constant was tuned until the pixels agreed. Fitting one constant
here would also hide the actual geometry, which is still unexplained: nothing in
`html:32`'s `closest-side` + `border-radius:50%` on an `MW*1.12 x 210*U` box produces an
intermediate horizontal extent. **Getting the shape right needs the real mechanism, not a
number between two wrong ones.**

**Cheapest way to get it:** render `html:32`'s shadow in the browser at this exact viewport
and measure the reference's own shadow profile directly — the source can tell us the shape,
rather than us inferring it from two failed candidates. That is a capture, not a guess.

### 17.10 Do NOT "fix" SH=816 — measured, it is correct, and the fix costs 11 points

I caught myself about to make a confident, principled-looking change and checked it first.
**It would have been a disaster.**

`app.nim:55` reads `SH = 816.0'f32  # scene.clientHeight (html:476)`, and `VH = 816.0`
(app.nim:54) is the render height. Same number, two meanings. R18c's viewport-accounting
rule says this page's reference is 1280x816 **with** chrome and the layout is 1280x800 — so
the obvious "correction" is `SH = 800`. That reasoning is **wrong for this port.**

    BASELINE (SH=816)   31.78%   mean |delta| 12.55   max 232
    PROBE    (SH=800)   42.93%   mean |delta| 27.13   max 241

**11.15 percentage points worse.** So `scene.clientHeight` genuinely *is* 816 here and
`SH = 816` stands. Do not touch it. The real layout deltas are small —

    SH=816:  hFit 834.13   MW 819.2   U 0.8192   MX 230.4   MY 437.45
    SH=800:  hFit 817.78   MW 818     U 0.818    MX 231     MY 421.90

— and `MY` moving 15.5px drags the entire machine, shadow, keycaps and paper with it.
The `SH=800` worst rows move from `810..813` up to `787..789`, which is exactly the
signature of the whole typewriter shifting 15px up the frame. That is what a real
misreading of this constant looks like, and it is not what the current baseline shows.

**Worth stating plainly: I had a mechanism, a citation to the engine's own R18c rule, and
a plausible arithmetic story, and it was still wrong.** The only reason this cost 15 minutes
instead of a regression is that the change went into `.board/probe/` and got rendered and
scored before anything was committed. **That ordering is the reason it is worth keeping.**

### 17.11 Where the shadow question actually stands

The 1.7x excess is still unexplained, and the reason is a measurement limit worth writing
down rather than another hypothesis:

    desk only (port)                      103.4
    reference (bottom-mid, y800-815)       75.5
    port shadow+lamp                       58.5

Everything here is measured against **the port's own desk**, because the reference's desk
*with the shadow removed* cannot be captured — `#shadow` is a DOM div (`html:32`) and there
is no capture of the page without it. The grain cross-correlation (17.9) shows the two
desks agree only to **corr 0.342**, so `ref - desk_only` mixes the shadow with a
per-pixel plank/grain difference of unknown sign. That is the whole reason the horizontal
profile came out non-uniform (ratios 0.13 at the left edge rising to 2.9) and cannot be
read as a shape.

What is *not* in question, because it needs no assumption about the desk:

* the CSS reading of `closest-side` with the default `<ending-shape>` is an **ellipse sized
  to the box** (`rx = W_b/2`, `ry = H_b/2`), **not** a circle of the short side. The
  `border-radius:50%` clip gives the identical ellipse. **So the port's ellipse is the
  correct shape per spec** — the circle probe in 17.9 was never the spec, which is worth
  recording, since the notes carried "circle" as the primary reading for many rounds.
* `shAlpha`'s stops match `html:32` exactly.
* box placement at `html:493` reproduces `html:493`/`layout()` arithmetic exactly.

**So the shape, the alpha profile and the placement are all provably right, and it still
measures 1.7x too strong.** That means the error is *not* in the shadow's description —
it is in something drawn over it, or in the desk baseline. Neither is currently
identifiable without a capture of `html:32`'s shadow in isolation, which remains the
correct next move. It is a capture, not a guess, and it is the only way to stop reasoning
from a baseline that is known to be only ~0.34 correlated.

### 17.12 CAPTURED GROUND TRUTH: the shadow's shape is right, only its MAGNITUDE is wrong

The blocker on 17.11 was that every shadow number was measured against the *port's* desk,
and the reference's shadow-free desk cannot be captured. Solved by capturing the shadow
**in isolation**, which removes the desk entirely instead of trying to subtract it.

`.board/probe/shadowonly.html` — a flat `#ffffff` page whose only content is `#shadow`
with `html:32`'s CSS verbatim, placed by `html:493` using `layout()`'s constants evaluated
at SW=1280 SH=816 (hFit 834.13, MW 819.2, U 0.8192, MX 230, MY 437 -> left 180.848,
top 682.76, w 917.504, h 172.032). On white the alpha inverts exactly:
`result = 255*(1-a) + luma(12,6,2)*a`, so `a = (255 - v) / 247.66` — no desk, no grain, no
lamp, no props, no machine. Captured with `tools/capture-ref.ps1` in the typewriter's own
mode; it reported `VIEWPORT=1280x816 (verified + cropped)`.

**First: the capture is trustworthy, because it agrees with the spec.** At (640,810) the
box gives `t = sqrt((0.4/458.752)^2 + (41.22/86.016)^2) = 0.4793`, so
`shAlpha = 0.72 + (0.35-0.72)*(0.4793/0.55) = 0.3975`. The browser measured **0.406**.
So `html:32` renders exactly as the CSS reads, and `closest-side` + the default
`<ending-shape>` really does give this ellipse.

**Now the port against that ground truth**, y800-815, lamp removed from both sides:

    x-window      BROWSER    PORT     diff
     350- 450      0.237     0.292    +0.055
     450- 550      0.347     0.415    +0.068
     550- 650      0.406     0.483    +0.077
     650- 750      0.399     0.476    +0.078
     750- 850      0.328     0.396    +0.068
     850- 950      0.210     0.263    +0.053

    mean |port - browser| = 0.0665

**The excess is flat in x.** It does not grow toward the edges and it does not peak in the
middle — it is a near-constant **+0.06 to +0.08 alpha** across the whole band. Therefore:

* **the shape is correct** — an x-independent offset cannot come from a wrong `rx`, a wrong
  centre or a wrong `ry`;
* **the placement is correct** — the box reproduces `html:493`/`layout()` exactly;
* **the profile is correct** — `shAlpha` is `.72 / .35@.55 / 0`, identical to `html:32`;
* **it is a scalar magnitude bug in how the bands composite**, nothing else.

This closes, on measurement rather than argument, every shape reading the notes had
accumulated: the `closest-side` circle (17.9), the "ellipse is 1.7x too strong" framing
(17.11), and the temptation to fit `rx ~ 376`. **None of those were the bug, and fitting
`rx` would have made this worse while looking like progress.**

**Two things I nearly got wrong here, both caught only by measuring.**
1. The first pass subtracted `full - desk_only`, which still contained the lamp — and the
   lamp *darkens* this region, so it inflated the port's apparent alpha and produced a
   spurious **growing** error with x (+0.038 -> +0.174). That "growth" was the lamp, not
   the shadow. Re-run against the lamp-bypassed frame (`twlamp_sw.raw`) it vanished and the
   error went flat. **A pattern that looked like shape was a layer I forgot to remove.**
2. Deriving alpha as `(desk-result)/desk` rather than `(desk-result)/(desk - luma(12,6,2))`
   is ~10% low at this desk brightness. Sign and shape of the finding survive it, but the
   number does not — use the denominator `desk - 7.34`.

**Still open, and now well-posed:** `shN = 28` bands are drawn outside-in as *discs* whose
per-band alpha `p = 1 - (1-aIn)/(1-aOut)` is the source-over correction for an annulus. The
algebra is right, and quantisation to 28 steps bounds the error near **0.007**, far below
the measured **0.066**. So banding is not the cause either, and the excess must come from
how the shim actually composites those discs. **Next: a differential probe varying `shN`
(28 -> 56 -> 112) and one that draws a single flat disc at a known alpha.** If the excess is
independent of `shN`, it is one disc painting more than it should; if it halves, it is
cumulative.

### 17.13 shN sweep kills the staircase theory; two more eliminations

**The staircase bias is not the cause.** Rebuilt with `shN = 224` (8x) and scored:

    shN = 28    31.78%   mean |delta| 12.55
    shN = 224   32.19%   mean |delta| 13.35

**Worse**, not better. The analytic bound for 28 bands was **+0.0120..+0.0139** against a
measured excess of **+0.111**, so quantisation could never have accounted for it, and the
8x rebuild confirms it directly: the excess is **independent of `shN`**. Whatever is wrong
is not cumulative band arithmetic.

**The engine is not double-painting.** `sdk/ui/paint.nim:59` emits `E cx cy r r argb`, and
`libs/nimskia/src/skia_shim.cpp` case `'E'` is a single
`cv->drawOval(SkRect::MakeLTRB(cx-rx, cy-ry, cx+rx, cy+ry), paint)` — one fill, no stroke,
no repeat. So the shim is not the source of the excess, and the port's outside-in
`p = 1 - (1-aIn)/(1-aOut)` construction, which I verified telescopes to exactly
`shAlpha(t)` at every radius, is right on paper and still measures high.

**And a measurement artifact caught before it became a false finding.** Comparing shadow
*bounding boxes* gave

    browser  x 189..1089   y 685..815
    port     x 181..1098   y 718..815

which reads like the port's shadow being vertically compressed by 33px. It is not. A
vertical alpha profile at the centre column x=640 shows the port has **no shadow at all
above y=800** — and the reason is that `#body` (the machine, `html:52` z-index 6) is drawn
**over** `#shadow` (`html:32` z-index 1). Both the desk-only and shadow-on frames contain
that opaque machine, so the subtraction cancels the shadow wherever the machine covers it.
The browser capture has no machine, so its profile is complete. **The two profiles are not
comparable above the machine's bottom edge (~806 = `MY + 450*U`), and the bbox difference is
the machine, not the geometry.**

This is the third time in four rounds that a difference which looked like a *shape* finding
was actually a *layer* difference: the lamp in 17.12, the machine here, the shadow's own
occlusion in 17.8. **The lesson is specific and worth keeping: the isolation probe must
bypass the occluders too, or the subtraction silently cancels the very thing being measured.**

**Where it stands.** In the band where the shadow is actually visible (y 800-815, below the
machine) the port is **1.23x to 1.35x too strong, uniform in x**, and that is now the only
live measurement. Candidate causes remaining, in the order they should be tested:

1. **The shadow is composited more than once.** A single extra source-over would give
   `1-(1-a)^2` = 1.68x at a=0.32, too much; but the measured curve fits
   `1-(1-a)(1-a/2)` to within ~0.01 at every window, which is one full paint plus one at
   **half** alpha. Worth testing directly: draw the stack once, and compare.
2. **`sy`/`ry` placement** — the profile implies the port's effective centre is ~13px lower
   than `html:493` gives, though that estimate rests on inverting alpha at a single point
   and should be re-measured before being believed.
3. Something in the scene composition (a layer alpha, or the `d.layer(deskLayer,0,0)` blit
   interacting with the shadow's blend state).

Note the honest shape of this: the geometry, placement and profile are all *provably* right,
two plausible arithmetic causes are eliminated, and the excess is *reproducible and
quantified*. That is a much better position than 17.8, where I had a 1.7x number built on a
baseline known to be 0.34-correlated. **Do not resolve the last 25% by scaling `shAlpha` —
that would repeat the `rx ~ 376` mistake with a smaller disguise.**

### 17.14 The engine is VERIFIED CORRECT; the defect is the port's band stack

17.13 listed "composited more than once" as candidate 1. **Tested it directly, and the
engine is innocent.**

Built a probe replacing the whole band loop with **one** full-size disc at a known alpha:

    d = d.circle(0.0, 0.0, rx, rgba(12, 6, 2, 0.32))

Measured at x630-650, y800-815, with the lamp removed **arithmetically** (no rebuild — see
below), denominator `desk - luma(12,6,2)`:

    desk luma                  71.84
    lamp alpha                 0.022
    single disc, nominal 0.320  ->  measured 0.324      paints ONCE -> 0.320
                                                        paints TWICE -> 0.538
    28-band stack              ->  measured 0.547
    browser ground truth       ->  measured 0.414

**One `d.circle` at 0.320 measures 0.324.** `drawOval` composites exactly once, at the
alpha asked for. The engine is correct, and this is worth recording as a permanent engine
fact: *a single `Draw.circle`/`'E'` fill is faithful; no repeat, no extra coverage.*

**And now the bug is localised.** At (640,810) the analytic value of the stack is
`A_{k+1}` for the band containing `t = 0.4793`, i.e. band `k = 14`,
`shAlpha(1-15/28) = shAlpha(0.4643) = 0.4076` — and the browser's ground truth is
**0.414**, which agrees to 0.006. The port measures **0.547**.

| | value |
|---|---|
| analytic telescope | 0.4076 |
| browser (ground truth) | 0.414 |
| port's 28-band stack | **0.547** |

So the geometry, placement, `shAlpha` profile, the per-band `p` formula and the engine are
all correct, and **the stack still accumulates ~0.14 too much alpha.** Every earlier
candidate is now dead: not the shape (17.12), not the staircase (17.13, and `shN=224` made
it *worse*), not a double paint in the shim (this section), not the lamp (0.022).

**And the `shN=224` result now reads as evidence rather than an anomaly.** If each disc
over-accumulates by a fixed amount, then more discs means more accumulation — so 224 bands
should overshoot more than 28, and the score did get worse (32.19% vs 31.78%). **That is
consistent, and it makes band count a live diagnostic instead of a dead end.**

**How the lamp was removed without a rebuild**, worth keeping because it avoids a whole
build cycle and because getting it wrong is what produced 17.12's spurious "growing" error:

    D  = base                         (lamp OFF, shadow OFF)
    Lp = D - S28                      (lamp OFF, shadow ON)
    F  = D - S28 - L                  (lamp ON,  shadow ON)
    O  = D - S1  - L                  (lamp ON,  shadow ON, single disc)

    L  = Lp - F
    S1 = (D - O) - L

`F - Lp` is **not** the lamp — it is the lamp *negated*, because turning the lamp on darkens
and the sign runs backwards. My first attempt used `F - Lp` and produced a single-disc alpha
of **-0.367**, i.e. a negative shadow. **A negative measured alpha is the tell that a
layer's sign is inverted**, and it is worth treating any negative darkening as a bug in the
isolation arithmetic rather than as a finding about the app.

**Next, concrete and cheap:** sweep `shN` *down* — 28 -> 14 -> 7 -> 3. If the excess scales
with band count, small `shN` will show it directly and the accumulation mechanism
(8-bit alpha rounding per disc, or `SkPaint` re-use across the loop) becomes visible from
the *shape* of the residual rather than from a single number. The fix is then a
compositing correction, **not** a fudge to `shAlpha`.

### 17.15 A stale engine claim in the PORT, and a gate that was silently skipping five suites

**First: a false engine claim, found by reading the engine rather than the notes.**
`app.nim` carried this comment on the knot:

> Draw has NO ellipse primitive (circle is the only shape it has and it cannot be
> squashed), so the ring is traced as a polyline.

**False on both counts.** `libs/nimskia/src/skia_shim.cpp:1346`:

    case 'E': { float cx = r.num(), cy = r.num(), rx = r.num(), ry = r.num(); ...

reads **four** numbers and calls `drawOval(LTRB(cx-rx, cy-ry, cx+rx, cy+ry))`. Only the
SDK's wrapper collapsed them: `sdk/ui/paint.nim:59` emitted `"E " & f(cx) & f(cy) &
f(r) & f(r)` — `r` twice. And `Draw.scale` squashes a circle perfectly well: the lamp
(`app.nim:515-519`) and the machine shadow (`2329-2330`) both already do exactly that
in this same file. So the comment contradicted the code two screens below it.

This is the **third** instance of the same failure mode (after 17.1 `textFace` and 17.5
gradients): a missing *wrapper* read as a missing *engine capability*. The tell is that
the same file already worked around the "missing" thing two functions away.

**Fix: `Draw.ellipse` added to the SDK**, emitting the same `'E'` verb with independent
axes. `rx == ry` reproduces `circle` byte-for-byte, so it is a strict superset and **no
existing call site changes**. Covered by 4 new checks in `sdk/tests/t_paint.nim`
(16 -> 20), asserting the exact command string, the `rx == ry` equivalence, that
`ellipse != circle` when `rx != ry`, and that a zero axis is accepted.

Two of those four failed on first run — my expectations, not the code: the verb ends in
`;`, and I had compared `circle(10,20,30)` against `ellipse(10,20,30,40)` when the
compatibility claim is about `ellipse(10,20,30,30)`. Fixed the assertions, not the
behaviour.

The knot is **not** switched to `ellipse` here: that is a pixel change and owes the same
probe-then-score-then-commit treatment as everything else. The comment now records that
the claim was false and that the real fix is pending.

**Second, and worse: `sdk/tests/run_tests.sh` was skipping five suites.**

    18 suites used  --path:..     (works)
     5 suites used  -path:..      (does NOT)

`-path:..` is not valid nim syntax. Nim parses the `-p` prefix and then finds no value:

    command line(1, 2) Error: argument for command line option expected: '-p'

The five: **t_keybind, t_settings, t_warden, t_keypicker, and t_paint**. Because each is
wrapped in `if ! nim c ...`, the parse error took the FAIL branch — but `run_tests.sh`
stops at the first failure, and I had been reading the green suites above it as "the gate
passes". **The five were never running at all.**

That last one is the uncomfortable part: `t_paint` is the file *I* added in round 147, and
I reported it as "16 checks, 0 failed" from a manual run using a working invocation, while
the committed gate could not execute it. The number was true; the gate was not. **A test
that the gate cannot reach is not a gate test, whatever a manual run says.**

All five repaired to `--path:..`. On the next run they **executed for the first time**:

    PASS keybind
    PASS settings
    PASS warden
    PASS keypicker
    20 checks, 0 failed          (t_paint — the first time the gate ever ran it)

**How the false claim was caught, and the cheaper way next time.** This was found by
grepping the *engine* for what a verb actually consumes, not by re-reading the port note.
The discipline to keep: when a note claims a capability is missing, read the shim's `case`
for the verb before planning a workaround. Three notes in this file claimed a gap; all
three were wrapper gaps, and all three already had working code nearby.

### 17.16 The excess is PER-DRAW, and it is not the transform

17.14 left one measured anomaly unexplained and 17.15 went elsewhere. This round closed it
by sweeping `shN` **down**, and the result is not what I expected.

**Sweep.** Built `shN = 4` alongside `shN = 28`, same source, same clock. Predictions first,
so the test could fail:

| N | analytic at (640,810) | measured | excess |
|---|---|---|---|
| 4  | 0.5518 | 0.5296 | **+0.012** (it is *under*) |
| 28 | 0.4077 | 0.5487 | **+0.123** |

**`shN = 4` matches its own prediction to within 0.012. The band arithmetic is correct.**
At N=4 the coarse-band value `shAlpha(1-(m+1)/N)` is exactly right — which is what the
telescope predicts, and 0.5518 vs 0.5296 is the expected sign and size of 4-band
quantisation. So `p`, the band radii, the paint order and `shAlpha` are all sound.

**The excess scales with band count, not with alpha.** Per draw: +0.003 at N=4, +0.0044 at
N=28. That is the same **+0.004** the single-disc test showed in 17.14 (0.324 for a nominal
0.320) — which I had written off as rounding. It was the fingerprint of the real effect,
and I under-read it. **28 draws x +0.0044 = +0.123, the whole observed excess.** And the
excess is constant down the profile (+0.122 at y798, +0.137 at y810), so it is not a
geometry or placement error at all.

**Three things ruled out along the way, each worth keeping.**

1. **The toast.** `buildScene:2374` draws a toast panel at `x230..690, y786..812` —
   straight through the measurement window. If it were live it would have contaminated
   every number since 17.12. It is not: the excess runs **+0.134 inside x690 and +0.130
   just outside**, continuous across the boundary. A contaminated panel would step there.
2. **The `twf` baseline being stale.** Rebuilt `app.nim` verbatim (`shN = 28`) and
   compared to the stored frame: **184 px differ, max 145, all of it the time-dependent
   motes, and 0.00 luma at the measurement window.** The baseline is current, so the
   numbers above are real.
3. **The 5.33:1 squash.** The whole stack is emitted inside `scale(1, ry/rx)` because
   `Draw` had no ellipse. Now that it does, rebuilt the stack with **native
   `Draw.ellipse(cx, cy, rx*tOut, ry*tOut, ...)` and no transform at all**:

   | y | scale-frame | ellipse, no squash | excess (scale) | excess (ellipse) |
   |---|---|---|---|---|
   | 798 | 0.626 | 0.621 | 0.122 | 0.117 |
   | 804 | 0.581 | 0.576 | 0.125 | 0.120 |
   | 810 | 0.544 | 0.540 | 0.137 | 0.132 |

   They agree to **0.005**, and both score **mean |delta| 12.55** — identical. **The squash
   is not the cause.** Refuted.

**Two engine facts banked as a by-product, both worth having permanently:**

- `Draw.ellipse` (no transform) and `circle` + `scale(1, ry/rx)` render equivalently to
  within 0.005 alpha. The new SDK proc is safe, and the scale-frame idiom costs nothing —
  so the port's existing lamp and shadow code does **not** need rewriting.
- **Every `drawOval` adds about +0.004 alpha more than requested** (~1 alpha unit of 255),
  independent of the alpha asked for and independent of any transform. A single circle at
  a nominal 0.320 measures 0.324; a 28-band stack pays it 28 times.

**That last one is the live defect, and it is an engine property, not a port bug.** It is
the same shape as the round-152 lesson: a correct measurement plus a plausible inference
was not a finding — but here the *anomaly I dismissed* was the finding. The next test is
the clean one: stack N identical ovals at a known alpha (e.g. 28 at 0.03, predicted
`1-0.97^28 = 0.5745`) and see whether the engine lands on the prediction or above it. If
above, it is a floor in `drawOval`'s alpha and it is worth a shim fix, because every
soft-shadow and vignette in every port multiplies it by its band count.

Do **not** reduce `shN` to make the excess smaller. At N=4 the excess does fall to +0.012 —
but the profile gets correspondingly coarser, and the true fix is in the engine. Trading a
per-draw engine error for a band-count error is the `shAlpha` fudge wearing a different hat.

### 17.17 ENGINE DEFECT: stacked translucent ovals over-composite, and it is measurable

17.16 localised the typewriter's shadow excess to ~+0.0044 per oval draw and said the next
test was "stack N ovals at a *known* alpha, so no geometry is involved". This is that test.

Probe: keep the frame, the 28-band loop and the radius, but set `p` to a **constant** and
make every oval **full radius**, so all 28 overlap the measurement window and the
prediction has no geometry in it at all:

    let p = 0.03'f32
    d = d.circle(0.0, 0.0, rx, rgba(12, 6, 2, p))

| alpha | measured | exact `1-(1-a)^N` | error over 28 draws | per draw, of 255 |
|---|---|---|---|---|
| 0.01 | 0.4789 | 0.2453 | **+0.2337** | **+2.13** |
| 0.03 | 0.7706 | 0.5738 | **+0.1968** | **+1.79** |

**A stack of 28 translucent ovals composites with roughly 0.2 more alpha than source-over
predicts.** That is not a rounding artefact and it is not the typewriter's fault — the
arithmetic here is `1-(1-a)^N` by hand, and the engine misses it by a fifth.

**It is not a constant floor and not proportional.** Ratio of per-draw error at the two
alphas is **0.84**, where a floor predicts 1.00 and proportionality predicts 3.00. The
excess is *largest at the smaller alpha*: +5.4/255 when asked for 3/255, +3.7/255 when
asked for 8/255. **I have not identified the mechanism** and am not going to guess at one —
it is some interaction between Skia's antialiased `drawOval` and repeated same-shape
compositing, and pinning it down means reading Skia, not the shim. What is established is
the size, the sign, and that it scales with the number of draws.

**Why this is the most useful thing found in six rounds.** Every soft radial in every port
is built this way — a stack of concentric translucent ovals standing in for a CSS gradient:

- typewriter: the machine shadow, `shN = 28` bands
- dna: glows
- gallery: the fog / vignette, the floor pools
- calligraphy: brush shadowBlur

**Each one is over-darkened by ~0.2 alpha and pays it again for every extra band.** And it
explains the round-151..153 mystery outright: the port's shadow was never "too dark by
0.11 for no reason" — it was *measuring the engine's stacking error*, which happened to sit
almost exactly where the browser's real gradient put its value.

**This reframes 17.12-17.16.** Six rounds were spent on a port bug that is mostly an engine
bug. The port-side arithmetic was right every time, and each round eliminated a port-side
cause one at a time. **The tell that should have fired much earlier: the excess scaled
perfectly with band count (17.16) — a constant, geometry-independent per-draw error is not
something app code produces.**

**Next, and it belongs in the shim, not the app:** find why repeated same-shape translucent
`drawOval` over-composites. Candidates to check in `skia_shim.cpp` case `'E'`: whether
`SkPaint` is being reused such that a blend mode or an alpha carries between draws (note
the paint is constructed fresh per command, so this is unlikely), whether the target is a
layer with a non-`SrcOver` or non-`kPremul` mode, or whether Skia's `drawOval` AA coverage
is the culprit and `setAntiAlias(false)` for interior bands would recover it. **Measure
each; do not reason about which one sounds right.**

**Until it is fixed, do NOT chase the remaining typewriter delta on the shadow.** It is
engine error, and no amount of port-side tuning moves a defect that lives in the renderer.
The honest move is to bank it, report it, and move to a lane the engine is not corrupting —
the keyboard key-cap ramp and the next-worst rows (205-206, 22) are untouched by this.

### 17.18 The over-composite is PER-DRAW at N=1 — and linear-light blending is refuted

17.17 measured the error on a stack and could not tell a *per-draw offset* from an
*interaction that needs stacking*. One build separates them.

**Test:** the same oval, the same alpha 0.01, the same window — differing *only* in how many
are drawn. `shN = 1` versus `shN = 28`, everything else identical.

| | recovered alpha | per-draw excess |
|---|---|---|
| **N=1** | 0.02634 | **+0.01634 = +4.17 of 255** |
| N=28 | 0.47894 -> 0.02301/draw | +0.01301 = +3.32 of 255 |

**A single translucent oval paints ~2.6x the alpha it was asked for.** The error is not a
stacking phenomenon at all — it is there at N=1. 17.17's framing was wrong on that point.

**The response curve, so far:**

| requested | byte | painted | byte | excess |
|---|---|---|---|---|
| 0.0100 | 3 | 0.0263 | 6.7 | **+3.7** |
| 0.0314 | 8 | ~0.0445 | 11.4 | **+3.4** |
| 0.3216 | 82 | 0.3240 | 82.6 | **+0.6** |

The paint response is **compressed upward at low alpha and nearly faithful by byte 82**.
That is not an additive offset and it is not a floor — it is a nonlinear response curve,
which is why 17.17's floor-vs-proportional test was inconclusive: it was being asked to
choose between two models when the truth is neither.

**Linear-light compositing: TESTED AND REFUTED.** If the renderer blended in linear light
while the frames are sRGB, a gamma-space recovery would over-report alpha — exactly this
signature, and it would explain why the error is worst at low alpha. Undoing the composite
in linear light makes it *worse*, not better:

| case | gamma-space recovery | linear-space recovery | requested |
|---|---|---|---|
| N=1 a=0.01 | 0.02634 | **0.09190** | 0.01000 |
| N=28 a=0.01 | 0.47894 | 0.67476 | 0.01000 |

The renderer blends in **gamma space**, which is what the gamma-space column assumes. The
whole measurement method is on the right footing.

**Null test, because this investigation has produced three measurement artifacts already**
(§17.7, §17.8, §17.12 — twice a difference that looked like a shape was a layer). The same
recovery run where no oval can reach:

| window | recovered | expected |
|---|---|---|
| x1150-1270, y795-815 (outside the ellipse, which ends at x1098) | **0.00000** | ~0 |
| x1150-1270, y700-720 | **0.00000** | ~0 |
| x600-680, y795-815 (inside) | 0.02634 | 0.0100 |

Exact zeros outside, the reading inside. The pipeline is sound and the defect is real.

**What is left, and the cheapest next probes.** The mechanism is still unknown and still not
guessed at. In order of what they would settle:

1. **`Draw.rect` at the same alpha.** `'R'` calls `drawRRect`, `'E'` calls `drawOval`. If a
   translucent rect at byte 3 is faithful and an oval is not, the defect is specific to
   `drawOval` — most likely its antialiased edge coverage being folded into interior pixels
   at low alpha — and `setAntiAlias(false)` becomes a candidate fix. This is one build and
   it halves the search space.
2. **Characterise the curve**: ovals at bytes 1, 2, 4, 16, 32, 64. Knowing where the
   response rejoins the identity line tells us whether it is a low-alpha-only defect (cheap
   workaround: never emit a band below ~byte 24) or a general curve.
3. Only then look at the shim's case `'E'`.

**Until 1 and 2 are measured, do not "fix" this by pre-compensating alpha in the port.** The
response curve is not yet characterised well enough to compensate against, and a port-side
table of magic numbers would hide the renderer defect from every future port.

### 17.19 It is the TRANSFORM, not the shape — and this REVISES 17.16

17.18's next probe was "is this `drawOval`-specific? Compare `Draw.rect` against
`Draw.circle` at the same alpha." **The first attempt at that probe was invalid and threw
its result away**, which is worth recording because it nearly produced a false finding.

I left `scale(1, ry/rx)` in the frame and replaced the circle with a **rect in absolute
coordinates**. Under that transform it was squashed and pushed to **y897-930**, entirely
off an 816-tall frame — so the measurement window contained no rect at all. It reported
`0.00626`, and read against the oval's `0.02634` it would have "shown" that rect and oval
behave in *opposite* directions. Both numbers were measuring different things. **This is the
sixth time a probe has been invalid because a producer or an occluder was not bypassed
(§17.7, round 152, the machine-occlusion case, §17.18's linear-light detour, and now this).**

Redone as a controlled pair: same source, both shapes at absolute coordinates, **no
transform in either**, so the *only* difference is the shape.

| one fill at alpha 0.01, no transform | recovered | excess |
|---|---|---|
| `Draw.rect` (drawRRect) | 0.00626 | −0.95 / 255 |
| `Draw.ellipse` (drawOval) | 0.00626 | −0.95 / 255 |
| requested | 0.01000 | |

**Identical to five decimals. The defect is NOT shape-specific** — rect and oval go through
the same code path and agree exactly.

**Which leaves the transform, and the controlled comparison says it matters:**

| one fill at alpha 0.01, same shape | recovered | excess |
|---|---|---|
| `Draw.ellipse` at absolute coords, **no transform** | 0.00626 | −0.95 / 255 |
| `Draw.circle` under **`scale(1, ry/rx)`** | 0.02634 | **+4.17 / 255** |

**Same shape, same size, same alpha, same frame, same window — differing only in whether a
5.33:1 scale is applied. The untransformed fill is faithful to about one alpha unit; the
scaled one over-paints by four.**

**This revises 17.16, which said the squash was NOT the cause.** That conclusion came from
comparing the *full band stack* with and without the transform and finding agreement to
0.005 — a genuine measurement, and a wrong inference from it. The controlled pair above
holds shape, size, area, alpha and window fixed and varies **only** the transform; the
stack comparison varied several things at once. **The controlled version wins.**

So the picture, as measured:

- a low-alpha fill drawn untransformed is **faithful** (−0.95/255, essentially byte quantisation)
- the same fill under a non-uniform scale **over-paints by ~+4.2/255**
- rect and oval are indistinguishable, so it is not a `drawOval` problem
- and 17.16's stack result (transform made no difference to a 28-band stack) is **not yet
  reconciled with this** — at alphas of 0.03-0.40 the effect is much smaller than it is at
  byte 3, which may explain it, but that is a hypothesis and is not confirmed.

**Where this leaves the defect.** It is narrow and it is in the transform path: something in
`skia_shim.cpp`'s handling of the `'o'` (scale) verb, or in how Skia resolves a CTM with a
strongly non-uniform component against a translucent fill. **The next probe is now a single
question: sweep the scale ratio.** Draw the identical low-alpha oval under
`scale(1,1)`, `scale(1,0.9)`, `scale(1,0.5)`, `scale(1,0.1875)`. If the excess grows as the
ratio departs from 1, it is CTM-magnitude-dependent and the fix belongs in the shim's
transform handling; if it is flat below some ratio and jumps, it is a threshold worth
finding precisely.

**Why this matters more than the shadow it came from.** It is the same class of defect as
the one in §5 row 3 (`globalAlpha` scoping, `'O'` multiplying instead of assigning): a
transform/alpha interaction in the shim rather than in app code, and it silently corrupts
any port that scales a translucent fill. Every port does — typewriter shadow and lamp,
gallery fog and floor pools, dna glows, calligraphy blur.

Do **not** port around it by dropping the scale frame in the typewriter. That removes the
symptom in one file and leaves the defect live for the other four.

### 17.20 A scale of 0.9 or 0.5 makes a translucent fill VANISH — non-monotonically

17.19 localised the defect to "a non-uniform scale". The obvious next step is a sweep of the
scale ratio. **Two of the four sweep frames were invalid before they were usable** and both
failures are the same old one, so they are recorded first.

- **Attempt 1 (invalid).** The four probe discs sat at y=760, and the machine body spans
  x181-1098 at y685-806. Two windows were under the machine, where the shadow is occluded
  and cancels. Worse, my "control" window at x50-140 **overlapped disc 1** (x100-300) and so
  read a real value instead of zero. This is the **seventh** instance of a probe invalidated
  by not bypassing an occluder or picking a clean window.
- **Attempt 2 (invalid).** Moved to clear desk at y=400 and against a twin frame. The twin
  showed **634 934 px differing across the whole frame** — because the reference I was using,
  `twdesk`, has props bypassed while the sweep has them on, so nothing cancelled. Isolating
  against a frame that differs in 60% of its pixels measures nothing.
- **Attempt 3 (valid).** Built a genuine twin: `twsweep.nim` with `while prb < 4:` changed to
  `while prb < 0:`. One integer. Everything else byte-identical. Control window reads
  **0.00000** and the diff is **40 210 px**.

**The result is non-monotonic, and that is the finding:**

| y-scale ratio | expected area | px actually painted | recovered alpha |
|---|---|---|---|
| **1.0** | 31 416 | **~30 842** | 0.01287 |
| **0.9** | 28 274 | **~1 697** | **0.00000** |
| **0.5** | 15 708 | **~1 554** | **0.00000** |
| **0.1875** | 5 890 | **~6 118** | 0.02042 |

**Four identical fills — same radius, same alpha 0.01, same frame — differing only in the
scale ratio. Two of them render fully and two render as essentially nothing.** For ratios
0.9 and 0.5 the interior is *byte-identical to the twin* and only ~1 600 antialiased edge
pixels differ, which is an outline, not a fill. **A scale of 0.9 or 0.5 drops the fill
altogether; 1.0 and 0.1875 both draw it.** That is not a magnitude-dependent error, it is a
correctness cliff, and nothing about it scales smoothly.

**Checked the obvious suspect and it is clean.** `Draw.scale` (`sdk/ui/paint.nim:98`) emits
`"s sx sy"`; `skia_shim.cpp:1426` reads it as
`case 's': { float x = r.num(), y = r.num(); cv->scale(x, y == 0 ? x : y); break; }`
and `cv->scale` is a real two-argument non-uniform `SkCanvas::scale`. The `y == 0 ? x : y`
fallback only fires when the caller passes a zero `sy` (the SDK's own default), which is
deliberate. Note the unrelated `yk_scale(void*, float)` at `:236` *is* uniform-only, but it is
a different entry point and nothing in this path calls it.

So the verb, the parser and the SkCanvas call all look right, and the failure is downstream
of all three. **The mechanism is still not identified and I am not going to guess at it.**
The next probe is a bisect: ratios 0.8, 0.7, 0.6, 0.55, 0.45 — is the cliff at one specific
value, and where. Then repeat the sweep with `Draw.ellipse` instead of `circle`-under-scale,
to find out whether it is the verb `s` or the non-uniform CTM itself.

**Standing, as measured:** a translucent fill is drawn correctly untransformed, over-paints
by ~+4/255 under a 5.33:1 scale, and **disappears entirely under a 0.9x or 0.5x y-scale**.
Any port that scales a translucent fill — typewriter shadow and lamp, gallery fog and floor
pools, dna glows, calligraphy blur — is exposed to all three behaviours, and this is now a
correctness bug rather than a fidelity one.

### 17.21 Both render paths render the oval wrong, and the pattern ALTERNATES

17.20's open questions were "bisect the cliff" and "is it the `s` verb or the non-uniform
CTM". One build answers both: each ratio is drawn **twice** in a single frame — once via
`circle` inside `scale(1, r)`, once as a native `Draw.ellipse` with `ry` set directly — so
the only difference between the two columns is the code path.

Measurement is sound and worth stating before the numbers: the region counts sum to
**42 796 + 21 611 = 64 407**, exactly the whole-frame diff, so no shape is hiding outside
the boxes I counted; and both control windows read **0.00033** and **0.00000**.

| ratio | `s` verb px / expected | alpha | native `ellipse` px / expected | alpha |
|---|---|---|---|---|
| 1.0 | 15 451 / 15 394 | 0.01960 | **0** / 15 394 | **0.00000** |
| 0.9 | 13 902 / 13 854 | 0.01880 | **218** / 15 394 | **0.00000** |
| 0.8 | 8 688 / 12 315 | 0.00843 | 10 564 / 12 315 | 0.02352 |
| 0.7 | 4 755 / 10 776 | 0.00077 | 10 829 / 10 776 | 0.02383 |

**Neither path is correct, and they fail at opposite ratios.**

- The `s` verb is fine at 1.0 and 0.9 and **degrades as the ratio drops** — 70% of the area
  at 0.8, 44% at 0.7, with recovered alpha collapsing to 0.00077.
- The native ellipse **paints nothing at all at ratio 1.0** (a plain circle, 0 px) and
  essentially nothing at 0.9 (218 px, an outline), yet renders **fully and correctly** at 0.8
  and 0.7.

**A native `Draw.ellipse` with `rx == ry` draws nothing.** That is the sharpest statement in
this whole investigation and it is not a soft-shadow question any more — it is a circle that
does not appear. Every round-hint, every dot, every knob drawn with `ellipse`/`circle` at
equal radii is at risk.

**The clue worth chasing is the ordering, not the magnitudes.** The probe emits, per
iteration: `scale` shape, then `ellipse` shape. The results are

    scale OK, ellipse MISSING,  scale OK, ellipse MISSING,
    scale PARTIAL, ellipse OK,  scale PARTIAL, ellipse OK

**The first four alternate.** An alternating present/absent pattern is a *pairing* signature
— something in the save/restore or CTM state leaking between commands — not a magnitude
signature. It also means **17.20's "0.9 and 0.5 vanish" reading was itself an artefact of
alternation**, not of those particular ratios: the ratios that vanished were simply the ones
that landed in the missing slot. I am recording that correction because 17.20 stated it as a
property of the scale ratio, and it is not.

**What is established, as measured:**

1. A translucent oval rendered through `scale` and the same oval rendered natively disagree,
   and both are wrong, at different ratios.
2. `Draw.ellipse` with `rx == ry` can render **zero pixels**.
3. The failure alternates with emission order, which points at command-pairing or CTM state
   rather than at geometry.

**The mechanism is still not identified.** The next probe is the one these three facts
actually license, and it is cheap: **draw the same ellipse ten times in a row, nothing
else, and count how many appear.** If it alternates there too, this is a state bug in the
shim's `save`/`restore` or CTM handling and the whole investigation becomes a shim bug with
a ten-line repro. If it does not alternate, the interleaving with `scale` is essential and
the search goes to how `cv->scale` mutates the canvas.

**Do not "fix" this in ports by replacing `ellipse` with `scale`, or the reverse.** Both are
demonstrably broken in different regimes; picking whichever happens to work for the
typewriter's shadow would hide the bug from the four ports that hit the other regime.

### 17.22 Ten in a row: no alternation, and 17.21's headline claim is WRONG

17.21's pattern alternated present/absent, which reads as a save/restore pairing bug. The
test that licenses is ten lines: **the same shape drawn ten times in a row, nothing else** —
ten native `Draw.ellipse` with `rx == ry` on one row, ten `circle`s under `scale(1, 0.8)` on
another, same alpha, same twin.

```
  native Draw.ellipse, rx == ry : ##########   10/10
    per-shape px: 7888 7888 7888 4508 3841 3091 3001 7813 7888 7888
  circle under scale(1, 0.8)    : ###.....##    5/10
    per-shape px: 6305 6305 2500 0 0 0 0 9 4921 6305
```

**No alternation at all — the ellipse row has zero present/absent transitions.** So 17.21's
"pairing signature" reading is wrong, and with it goes the thing I was most excited about.

**And the headline claim from 17.21 does not hold.** I wrote that a native `Draw.ellipse`
with `rx == ry` can render zero pixels, and presented it as the sharpest statement in the
whole investigation. Here, **ten of ten** such ellipses render. So that is not a property of
`rx == ry`; it was a property of *where those two happened to sit* in that one probe. **A
claim generalised from a two-sample probe, on the back of a pattern I had already
mis-read once in the same section.** Recording it because leaving it in the notes would be
worse than the original error.

**What actually survives, and it is position, not shape.** The degradation is *contiguous*,
and both rows degrade over the **same iterations (3-6)** even though one is a native
ellipse and one is a scaled circle:

- ellipse row: full at 0,1,2 then 4508/3841/3091/3001 (43-57% of area) then full again at 7-9
- scale row: full at 0,1, partial at 2, **zero at 3-6**, back at 7-9

Different code paths degrading over the *same* indices points away from geometry and away
from the `s` verb, and towards either a positional/rasteriser effect or **something drawn
later covering that region**. The second is the one to rule out first, because my
"isolation" is against a twin — and a probe shape that is drawn and then **overpainted**
contributes zero to the difference just as convincingly as one that was never drawn. I have
been treating absent-from-diff as never-drawn all week, and this is the first probe where
that assumption is load-bearing.

**The discriminating test, and it is cheap:** draw the probe into a frame where the entire
scene is bypassed — no `drawProps`, no machine, no sheet — so the only content in the frame
is the probe itself. If the dead zone survives with nothing there to occlude it, it is a
rasteriser bug. If it vanishes, every "missing shape" in 17.20, 17.21 and this section was
occlusion and **the defect I have been chasing for four rounds does not exist.**

I would rather run that than defend the current version.

**Everything in 17.17-17.19 is untouched by this.** Those were measured in the machine's
shadow region with clean null controls at 0.00000, the toast ruled out by a continuity test,
and the 5.33:1-vs-untransformed difference reproduced on a controlled pair. The over-composite
under a non-uniform scale stands. What is now in doubt is only the *magnitude* and
*missing-shape* material from 17.20 onward, which leaned on "absent from diff" without ever
ruling out an occluder drawn afterwards.

### 17.23 RESOLUTION: the "missing shapes" were occlusion; the real effect is small and uniform

17.22 left one test that could end this: **draw the probe into a frame where the entire
scene is bypassed** — no `drawProps`, no `drawMachineShadow`, no machine, no sheet, no
motes, no toast, nothing but a flat background and the probe shapes. If the dead zone
survives with nothing there to occlude it, it is a renderer bug. If it vanishes, the last
three rounds were chasing an artefact.

**It vanishes. Completely.**

```
  native ellipse rx == ry : ##########  10/10   7888 x10   (expected 7854)
  circle scale(1, 0.8)    : ##########  10/10   6305 x10   (expected 6283)
```

All twenty shapes render, **every one at the identical pixel count**, and the counts match
the geometric areas. There is no dead zone, no missing shape, no degradation at 3-6, and no
ratio at which a fill disappears. **17.20, 17.21 and 17.22 were measuring occlusion** — probe
shapes drawn early and then covered by scene content, which is indistinguishable from "never
drawn" when your isolation is a frame difference. That is the same trap as the machine
occlusion in round 152 and the toast in 17.12, and I walked into it three rounds running
because each result was plausible.

**And the alpha result changes the picture again, in the direction of *simpler*:**

| path | recovered alpha | spread over 10 shapes | excess |
|---|---|---|---|
| native `Draw.ellipse`, `rx == ry` | **0.0166** | **0.00 / 255** | +1.68 / 255 |
| `circle` under `scale(1, 0.8)` | **0.0166** | **0.00 / 255** | +1.68 / 255 |

**The two paths are identical to four decimals, and the ten independent shapes agree to
four decimals.** So:

- **There is no transform effect at all.** 17.19's controlled pair — `−0.95/255`
  untransformed versus `+4.17/255` scaled — **does not reproduce here**, and was itself
  contaminated by the scene it was measured in. The 5.33:1 squash is innocent. Third time
  that conclusion has been overturned in this section; the common cause is now obvious and
  it is not the transform, it is that **every one of these probes was drawn inside the full
  scene and differenced against a frame with different content in it.**
- **What is real is small, constant, and per-draw: a translucent fill at byte 3 paints at
  about byte 4.2, i.e. +1.68/255 more than requested**, uniformly, with zero spread across
  ten independent shapes at ten different screen positions. Zero spread is what makes this
  credible as a renderer property rather than measurement noise.

**And this is the typewriter shadow, finally, explained without any of the last four rounds:**

    28 bands x ~0.004 average excess  =  +0.12      observed:  +0.123

The excess tracks **band count**, not alpha, not geometry, not transform — which is exactly
what 17.16 measured and what I failed to connect to a per-draw fill defect. A byte-3 to
byte-8 band is off by ~1.5 alpha units, there are 28 of them, and they accumulate. **The
shadow arithmetic in `drawMachineShadow` has been correct the whole time.**

**What this leaves, honestly:**

1. **Retired:** missing shapes, vanishing fills, ratio cliffs, alternation, the transform
   effect, and 17.21's "ellipse with `rx == ry` draws nothing".
2. **Standing:** a small, uniform, per-draw over-paint of translucent fills, ~+1.7/255 at
   byte 3. Worth a shim look, worth a gate test (`t_paint_stack.nim`), but it is a fidelity
   bug of a few alpha units, **not** the correctness cliff the last three rounds described.
3. **Still unexplained and now the most likely story for 17.17-17.19:** why the effect was
   2-3x larger when measured inside the scene. Layer and prop interaction are the obvious
   candidates. **Any future probe here must bypass the scene first**, or measure with a
   twin that differs only in the probe and has the occluders provably absent.

**The lesson, which is the expensive one:** I spent four rounds escalating a story from
"alpha is off by 0.02" to "circles do not render" because each measurement was internally
consistent and none of them ruled out an occluder. The first result (§17.16) was right, the
scale sweep was an artefact, and it took a deliberately degenerate frame — *nothing but the
probe* — to see it. **Build the degenerate frame first, not last.**
