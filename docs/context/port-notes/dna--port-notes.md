# 052 dna-helix — port notes

Owner of this lane: the #52 dna port. Reference `.board/frames/ref052b.png`,
1280x816, **clock `wait:8`** (`drive.exe` reports `now=800.0`, matching the
capture budget). Scratch instruments live in `.board/dna52/`.

---

## Result

| | baseline (before this lane) | after | delta |
|---|---|---|---|
| differing @ tol 8 | 105,066 (**10.06%**) | **104,436 (10.00%)** | **-630** |
| mean \|delta\| | 8.50 | **8.39** | **-0.11** |
| STRUCTURE @ tol 24 | 82,316 | **81,570** | **-746** |
| grain share | 22% | 22% | — |

Confirmed by `.board/scoreboard.ps1`: `dna 10.00% 8.39 81570 px 22%`.

Raw verified 4,177,920 bytes every time, always `rawswap`ped, always built with a
captured `build-wasm: wrote …` line. The render is **deterministic**: two
consecutive renders are byte-identical (SHA-256 `431AF7C4…`), so run-to-run noise
is zero and every delta above is real.

**The previous lane's "at its floor" is refuted.** Two changes landed, and the
largest single bucket (the helix, 42,707 structure px) is diagnosed below but was
*not* fixed. There is still a great deal here.

---

## 1. The `0.22 nm` mystery — SOLVED, and the port was the wrong one

The brief asked for this, and explicitly warned not to assume the port was right.
**The port was wrong.**

`app.nim` drew, in `.facts` row 1 col 2, `"0.22 nm"` / `"major groove width"`,
with a long comment arguing "the frame wins" over `html:196`'s `≈ 2.2 nm`.

Three checks, each independent:

1. **The run-structure argument was invalid.** The prior evidence was that the ink
   at rows 724–740 splits into two runs (x1088..1123, x1130..1156) with no leading
   gap, whereas a leading `"≈ "` would split it into three. That establishes only
   that there is **no leading `≈`**. It says nothing about the digits: `"0.22"` and
   `"0.34"` put the same four glyphs at the same places and therefore produce the
   *identical* run structure. The inference "the frame wins ⇒ 0.22" does not
   follow.

2. **The caption settles it outright.** Measured caption ink in `ref052b.png` at
   y=757 spans **x1088..1172 = 85 px**. Costed with this file's own `adv` table at
   11.5px:

   | string | width | vs 85 px measured |
   |---|---|---|
   | `rise per base pair` | 83.6 px | **match** |
   | `major groove width` | 94.1 px | no (port rendered 98 px on screen) |

3. **No JS rewrites `.facts`.** Every `textContent =` in the page targets the
   sequence message or the caption; the measurements block is static markup. So
   `html:194-197` is authoritative.

The real bug was bigger than one digit. `.facts` is a `1fr 1fr` grid filling
row-major, and **3 of the 4 boxes were wrong**:

| box | was (wrong) | now (html verbatim) |
|---|---|---|
| r1c1 | `10.5` / base pairs per turn | unchanged ✓ |
| r1c2 | `0.22 nm` / major groove width | `0.34 nm` / **rise per base pair** |
| r2c1 | `≈ 0.34 nm` / rise per base pair | `≈ 3.6 nm` / **length of one turn** |
| r2c2 | `≈ 1.2 nm` / minor groove width | `≈ 2 nm` / **helix diameter** |

`major/minor groove width` are not facts at all — they live in the `.ann`
annotation list (`html:187-188`), and a previous pass pulled them in and
duplicated `rise per base pair`.

**Measured: -549 px @ tol 8, -555 @ tol 24, mean 8.50 → 8.40.**

---

## 2. The one-turn bracket — drawn (at the measured position)

`html:459-469`. The port drew nothing; `overlay-notes.md` records that an earlier
pass deliberately declined to, because this port's projection disagreed with the
frame.

I measured the frame directly (`runsin.mjs`, x120..480 y615..725). The bracket is
a ~1px stroke crossing a near-horizontal line at 13.6°, so each scan row shows a
5px-wide run; fitting the run centres gives **dx/dy = -4.14 to better than 0.5px
over 65 rows**:

- main line **(140.4, 711.1) → (409.5, 646.0)** in page coords
- ticks ±5 along the normal (0.235, 0.972), independently confirmed by a run at
  **x=410..411, y=641..650** — exactly the 10px the normal predicts

Drawn in canvas-local coords (page y − 60). Verified co-located: at row 700 the ref
ink sits at x181–189 and the port at x181–186; at row 680, ref x266–272, port
x265–270. Within ~1px.

**Measured: -81 px @ tol 8, -191 px @ tol 24.** (tol 24 gains more than tol 8,
as expected: the line fills background *and* overlaps molecule.)

### ⚠️ This exposes a second source-vs-frame disagreement

This port's own `proj()` puts `html:461`'s `a0 … a0+10.5*RISE` at `vv=RAD+7` on
**(140.8, 632.7) → (425.4, 571.7)**. The frame has it at (140.4, 711.1) →
(409.5, 646.0): **~75px lower and 5.5% shorter in x**.

The x extent is **not** fixable by changing `vv` — `proj`'s x depends only on `u`,
`s` and `kk`, and `vv` touches none of them. So this is not a one-constant fudge.
Together with the kicker discrepancy already noted at `vizTitle`, the evidence is
accumulating that **`ref052b.png` was not captured from the revision of the page now
in this tree**. Parity is measured against the frame, so the bracket is drawn where
the frame has it and the disagreement is reported rather than hidden.

The bracket's **label** (`one turn · 10.5 bp · ≈ 3.6 nm`, 11px MONO, rotated
13.6°) is still not drawn — roughly 850 of the 1,113 originally-missing px in that
band. It needs rotated text plus a MONO advance table this file does not have
(`adv` is a proportional table). Not attempted rather than attempted blind.

---

## 3. What the remaining 81,570 structural px actually are

Exact partition of the canvas/panel/topbar split (these three rects are disjoint
and sum to the frame total exactly, which is how the instruments were validated):

| region | tol 24 | tol 8 | meanΔ |
|---|---|---|---|
| canvas (0,60–860,816) | 58,572 | 72,449 | 9.70 |
| panel (860,60–1280,816) | 21,921 | 30,692 | 7.45 |
| topbar (0,0–1280,60) | 1,268 | 1,376 | 1.40 |
| **total** | **81,570** | | |

Inside the canvas, `helix-core` (140,300–700,640) alone is **42,707** — 52% of
all remaining structure. That is the prize and **I did not crack it.** Everything
below is what I established about it.

### The port draws ~15% less ink than the reference

Two-sided decomposition (`missing.mjs`, bg=247,249,251, ink threshold 40):

| region | MISSING (ref ink, port blank) | EXTRA (port ink, ref blank) | both, differing |
|---|---|---|---|
| helix-core | **16,991** | 7,682 | 16,828 |
| canvas-all | 24,346 | 11,255 | 20,856 |

Missing is **2.2× extra**. A rotation or phase error would produce those roughly
symmetrically, so this is not phase alone.

At the missing pixels, the port's own deviation from background is:

| port dev | 0–4 | 4–8 | 8–16 | 16–24 | 24–40 | 40+ |
|---|---|---|---|---|---|---|
| share | **90.3%** | 1.5% | 4.0% | 1.4% | 2.7% | **0.0%** |

Nothing above dev 60. **The port does not draw there — it is not a tone or
antialias problem, it is absent geometry.** The deficit is also *uniform* along the
helix (port/ref ink ratio 0.80–0.86 in every 80px column strip, not alternating),
which is why it is not the growth animation.

### Everything in the pipeline was checked against source and MATCHES

| suspect | verdict |
|---|---|
| item-pool saturation (`MAXIT=6000`, `item()` returns −1) | **eliminated by counting**: ~295 items are generated. No build needed. |
| projection scale (`risePx`, `kk`, `cx0`, `cy0`) | matches `html:290-297` exactly |
| canvas width `W` | **measured at the panel edge**: ref and port are both `226,231,238` at x=860 then white — identical. `W=860` confirmed |
| replication strands (`html:414-432`) | correctly absent: `startReplication()` fires only on a **button click**, so the capture was never in `unzip` mode. `arrA/arrB` are right at 0. |
| round line caps (`html:470`) | already correct — `skia_shim.cpp:1339,1349,1402` all set `kRound_Cap` |
| `hover` highlight (`html:477`) | inactive; `hover = -1` in both |
| drop-shadow on the molecule | none in source; `--shadow` is only on `.ctrls`, `.ann`, `.tip`, `.btn` |
| t == 0..4 draw loop | matches the source item for item |

### What it most likely is: the refused spin calibration

Cross-correlating the reference against the port over ±20px (SAD on a mean-abs
channel basis) gives a clear *interior* minimum — but at **different offsets at
different points along the helix**:

| window | best offset | improvement |
|---|---|---|
| lower-left (200,470–360,590) | dx=−1 **dy=−5** | 9.4% |
| middle (380,400–540,520) | dx=+1 **dy=+8** | 15.7% |
| upper-right (560,300–720,420) | dx=−1 **dy=+4** | 13.8% |
| (480,350–640,470) | dx=0 **dy=+7** | 24.8% |

**A translation cannot remove this** — the offset varies from −5 to +8 along the
axis. That is a rotation-like displacement, which is exactly what E22's spin
disagreement (ref 0.65165 rad vs port 0.74140 rad, 5.1° over-rotation) predicts.

I did **not** calibrate the spin; the brief forbids it and I found no new evidence
that overturns that decision. But this is the first *independent* measurement
showing the helix residual has the signature of phase rather than of a missing
element, which is the experiment E22 says would settle it.

### New evidence relevant to the E22 refusal

The clock sweep (`wait:1…45`, same wasm, `wait:8` still the headline) is
**monotone increasing with no minimum anywhere in range**:

| clock | 1 | 4 | 6 | **8** | 10 | 12 | 16 | 20 | 30 | 45 |
|---|---|---|---|---|---|---|---|---|---|---|
| tol 8 | **9.19%** | 9.63% | 9.89% | **10.06%** | 10.57% | 10.93% | 11.72% | 12.48% | 13.31% | 13.56% |
| tol 24 | **72,821** | 74,953 | 77,847 | **82,316** | 86,802 | 91,596 | 101,321 | 110,864 | 122,581 | 126,550 |

This explains the prior lane's "inverted" observation without needing a refutation
of the pin probe: the score is **monotone in clock**, so the lowest clock always
wins regardless of whether it matches the reference's phase. Pin alignment (a
discrete `frontMost` argmax) and overall diff are simply not monotone in each
other. Note the extrapolated floor is only ~9.0%, so spin alone cannot account for
81,570 structure px even if it were applied perfectly.

---

## 4. The panel (21,921) is largely an engine antialias floor

The port's panel text has **10–16% less ink** than the reference. Splitting ink
into core / mid / fringe bands **refutes** the obvious "wrong font weight" theory:

| tile | Δcore | Δmid | Δfringe |
|---|---|---|---|
| p1_1 | −11 | **−350** | +24 |
| p1_2 | +63 | **−289** | +66 |
| p1_3 | −126 | **−182** | +64 |
| p1_4 | +171 | **−354** | +52 |
| p2_1 | +119 | **−386** | +47 |

Core (dev>150) glyph pixels **match or exceed** the reference. What is depleted is
the mid-tone AA ramp (dev 80–150). That is a rasterisation-ramp difference between
Chrome's text AA and Skia's, not a weight error, and it lives in `libs/nimskia` —
outside this port's write scope. Not chaseable from `app.nim`.

`--sans` is `"Inter","Segoe UI Variable Text","Segoe UI",…`; the port renders
Segoe UI (`skia_shim.cpp:142`), which is the correct fallback.

---

## 5. Things that did NOT work (recorded so they are not re-derived)

- **Spin calibration** — forbidden, and the sweep above shows no minimum to aim at.
- **"The port draws too little because MAXIT truncates the pool"** — wrong; ~295
  items, cap 6000.
- **"The replication strands (html:414-432) are missing"** — they are button-gated
  and correctly absent from both.
- **"Round caps are missing"** — the shim already sets them.
- **"Panel text is too light ⇒ bump the weight"** — refuted by the core/fringe split.
- **"The molecule is displaced by a constant offset"** — refuted; the best offset
  varies −5…+8 along the helix.
- **"The canvas width / scale is wrong"** — refuted at the panel edge, pixel-exact.
- **A score drop between two identical renders** — this was **my own instrument
  bug**, not the engine: `missmap.mjs` read its threshold from `argv[6]` instead of
  `argv[5]`, so a run intended with inkThr=40 actually used 10. The render is
  byte-identical across runs (SHA-256 verified). Fixed at `.board/dna52/missmap.mjs`.

---

## 6. Instruments (`.board/dna52/`)

Every one self-validates against `tools/pngdiff.mjs`; the region tool's disjoint
rects sum to **exactly** 82,316 / 81,570, which is how they were checked.

| file | purpose |
|---|---|
| `structmap.mjs` | coarse ASCII map of tol-N differing px (total must equal pngdiff) |
| `region.mjs` | differing-px counts in named rects; disjoint rects sum to the frame total |
| `missing.mjs` | two-sided split: MISSING / EXTRA / both-ink-differing |
| `misswhy.mjs` | histogram of the port's own deviation at MISSING px → "faint" vs "absent" |
| `missmap.mjs` | ASCII maps of MISSING and EXTRA separately |
| `runsin.mjs` | per-row runs of MISSING ink → isolates undrawn overlay elements |
| `inkbox.mjs` | ink extent + count, ref vs port, per rect |
| `ink3.mjs` | ink split into core / mid / fringe → refutes weight mismatches |
| `profile.mjs` | ref/port/diff bar profiles along a row or column, with run listing |
| `silhouette.mjs` | per-column ink top/bottom for ref vs port → smaller / shifted / thicker |
| `shift.mjs` | ±N cross-correlation → "is it displaced, and by how much?" |
| `colourcount.mjs` | per-colour ink census → "is one strand under-drawn?" |

Note for the next lane: `tools/refdiff.mjs` **silently ignores** its trailing rect
arguments (`.board/PORTING-FACTS.md` implies otherwise) — it always reports the
whole frame. That is the "region is empty because the invocation is broken" trap
in a new costume.

---

## 7. Where the remaining work is, ranked

1. **helix-core, 42,707 structure px** — a rotation-like displacement varying
   −5…+8 px along the axis. Blocked behind the refused spin calibration (E22).
   Everything else in the pipeline has been verified against source.
2. **panel, 21,921** — mostly AA-ramp difference in `libs/nimskia`, out of scope here.
3. **the bracket label, ~850 px** — needs rotated text + a MONO advance table.
4. **the dashed axis (`html:454-458`)** — not drawn; ~350–500 px. Needs a
   hand-emitted dash run (the engine has no `setLineDash`, E11). It is faint
   (alpha .16 → dev ≈37, just under the 40 threshold used in the ink analyses,
   so it does not appear in the missing/extra counts above).
5. **strand-end labels `5′`/`3′` (`html:498-509`) and the SVG leader lines
   (`html:570-584`)** — still not drawn.
---

## 8. Second pass — the three reachable overlay items

Baseline re-established from scratch before any edit, and it reproduced the
handed-down numbers **exactly**, which is the build-identity check:

```
bash tools/build-wasm.sh apps/dna/app.nim .board/frames/dna3/dna.wasm
  -> build-wasm: wrote .board/frames/dna3/dna.wasm (306096 bytes)
drive.exe ... dna.raw 1280 816 1 "wait:8"
  -> paramCount=6 script=[wait:8]   crashed=[]  now=800.0   pDraw[1] len=34643
tools/pngdiff.mjs ref052b.png dna_sw.raw 1280 816 8   -> 104,436 (10.00%) mean 8.39
tools/pngdiff.mjs ref052b.png dna_sw.raw 1280 816 24  -> 81,570 (7.81%)
```

`crashed=[]` was checked to be genuinely empty (R13): one earlier run in this
session failed at `unhandled exception: app requires unavailable import 'round'`
and **still left a full-size raw behind**, so `pngdiff` happily scored the
*previous* frame. That is R13 biting a second time and it is worth the paranoia.

### 8.1 The monospace advance table — MEASURED from the font

The brief asked for the label's MONO advance table to be built from the font
rather than guessed, and it is. `.board/dna3/monotable.mjs` parses the sfnt table
directory of `C:\Windows\Fonts\consola.ttf` directly:

```
unitsPerEm 2048   hhea ascender 1521  descender -527
char  cp   gid  adv(units)  adv/upem
"o"   111  145  1126        0.549805
"≈"   8776 690  1126        0.549805
"'"   8242 2517 1126        0.549805
      -> distinct advances among all 28 runes of the label: 1126
```

**Consolas is the face Chrome resolves here**: `--mono` (html:12) lists
`"JetBrains Mono","SF Mono",Menlo,Consolas,…` and the first three are not
installed on this machine, so the 4th entry wins. One number, 1126/2048 =
0.5498047 em, covers every rune including U+2032 PRIME, U+2248 and U+00B7 — which
is the whole point of a mono face. It is in `app.nim` as `MONO_ADV`, with
`MONO_MID_EM = (1521-527)/2/2048 = 0.2426758` for canvas `textBaseline:'middle'`.

Independent confirmation that the table is right: at 11 px the label is
28 × 6.048 = **169.3 px** wide, and the frame's label ink measures **172 px**
end to end (`.board/dna3/colmap.mjs`, x190..362, y672..718). Centred at
(276, 695) against the 278.7 / 694.1 the bracket geometry predicts.

### 8.2 The bracket label — implemented, MEASURED WORSE, not drawn

`monoRun` in `app.nim` does the rotation (`d.rotate`, which the shim honours at
`skia_shim.cpp:1411`) and the centring, and walks the string **by UTF-8 lead
byte** so U+2032 lands once instead of vanishing (E32). It is written to be right.

It still loses, because the one thing `Draw.text` cannot do is choose the face:
there is no family parameter (`sdk/ui/paint.nim:63`) and the shim's `T` verb
passes family 0, so `TextOpts.family` stays null and the fallback chain in
`skia_shim.cpp:142` resolves to **Segoe UI**. Measured, at both tolerances:

> **CORRECTED 2026-10-04 (round 156).** The statement above is true of `Draw.text`
> and misleading as written: `Draw.textFace(x, y, size, c, family, s)` **does** take a
> family (verb `'N'`, `sdk/ui/paint.nim:72`) and is how `apps/typewriter` names
> "Courier New" at 11 call sites. So this is **not** an engine gap — it is a choice
> this port has not yet made. Anything below that ranks "no typeface" as a *limitation*
> of Yantra should be re-read: it is a limitation of `Draw.text`, one of two verbs.
> The gap is real only where the drawing is a **node** rather than a canvas run.

| build | tol 8 | tol 24 | mean |
|---|---|---|---|
| baseline | **104,436** | **81,570** | 8.39 |
| + bracket label, weight 600 | 104,666 (+230) | 81,742 (+172) | 8.40 |
| + bracket label, weight 700 | 104,705 (+269) | 81,789 (+219) | 8.41 |
| + bracket label + strand labels | 104,757 (+321) | 82,827 (+257) | 8.42 |

600 is better than 700 (Consolas has no semibold; Chrome snaps 600 to Bold, while
Segoe UI 700 is genuinely heavier and overshoots) but both are net losses.
`pathtrace`/`px` sampling along the label's own baseline shows why: the frame's
stems sit at 123–165 grey, the port's at 188–247 — right place, wrong face, not
enough ink to cancel the offset. **The procs stay in the tree, not called**, with
the numbers above on them.

This is the same root cause as the 21,921 px panel bucket: not a drawing bug, a
typeface the SDK cannot reach.

### 8.3 The SVG leader lines — DRAWN, at the measured geometry

`html:570-584` emits one `<path d="M ax ay H ex L tx ty">` per annotation into a
`position:fixed; z-index:5` SVG that is only hidden under `max-width:900px`
(html:117-121) — at 1280 wide the leads cross over the molecule. They were worth
**~2,160 ink pixels** (`.board/dna3/leads.mjs`, the composite model
`ref ~= 0.75*--ink3 + 0.25*port`, which separates them cleanly from the axis'
much fainter ink) and the port drew **none** of it.

The leads in this frame **do not point at the pins**, which is worth recording:

* every horizontal ends at **x = 866**, but html's `a.x = pin.left - 4` and the
  pin discs measurably start at x = 881;
* `ex` follows html's `-3 per i` rule exactly for i = 0,1,2 (825, 822, 819), yet
  html puts `ex` at `panel.left - 18 - 3i` = 842, 839, 836;
* three diagonals are present and **none of them reaches any of the six pins the
  frame actually draws** at (643.4,507.0) (475.5,497.7) (364.6,515.9) (224.1,566.2)
  (220.3,528.4) (193.6,519.6) — `.board/dna3/discs.mjs`, pure --ink blobs;
* leads 0 and 1 have **no diagonal at all**.

Third instance of the "frame is a different page revision" pattern (after the
`vizTitle` kicker and the bracket). Same call `drawBracketOv` makes: parity is
measured against the frame, so they are drawn where the frame has them.

| lead | a.y | horizontal | diagonal |
|---|---|---|---|
| 0 `dir` | 133.0 | x 825..866 | none found |
| 1 `bb` | 238.5 | x 822..866 | none found |
| 2 `maj` | 344.0 | x 819..866 | (818, 343.8) -> (440.6, 438.3), len 389 |
| 3 `min` | 450.0 | x 816..866 | (816, 448.6) -> (352, 489), len 470 |
| 4 `hb` | 555.0 | x 813..866 | (815.9, 555.4) -> (184.4, 464.6), len 638 |

Both diagonals' far ends were confirmed by A/B, not assumed, because the two
cases come out opposite:

* truncating lead 4 at the last point `pathtrace` reports as unbroken ink —
  (338, 475), which also agrees with the local slope there — **costs 548 px at
  tol 8** (104,241 -> 104,789) and 594 at tol 24. The frame really does carry
  the run out to x = 184.
* carrying lead 3 on 200 px further along its own slope **costs 506 px at tol 8**
  (104,241 -> 104,747) and 457 at tol 24. There is nothing there.

Colour: `--ink3` #8793A4 at `stroke-opacity:.75` (html:118-119), which is what
`rgba(135,147,164,0.75)` composites to over the backdrop.

**Measured effect of the leads: -195 px @ tol 8, -705 px @ tol 24, mean
8.39 -> 8.34.** The residual leader mask fell 4,816 -> 4,283 px; the five
horizontals are gone from it entirely.

### 8.4 The dashed axis — searched, not located, not drawn

`html:454-458` draws `setLineDash([3,6])`, `lineWidth 1`,
`strokeStyle rgba(15,27,45,.16)` from `proj(u0,0,0)` to `proj(u1,0,0)` with
`u0 = (-(n-1)/2 - 1.5)*RISE` and `u1 = ((n-1)/2 + 1.5)*RISE`.

* Its full-alpha composite over `--bg` is (209.9, 213.5, 218.2), dev **37** — so
  it is invisible to every ink instrument in §6, which threshold at dev > 40.
  `.board/dna3/colmap.mjs` with `COV=1.0` and target 210,214,218 finds no clean
  diagonal band anywhere in the canvas.
* `.board/dna3/pathtrace.mjs` in `DARK` mode (a scalar-consistency test: ref must
  lie on the segment bg -> 0.16*ink in all three channels at once, with the port
  at background so the ink is genuinely missing) walks the line this port's
  `proj` predicts, page (44,571) -> (764,395), and gets **1 hit in 38 samples**,
  which is chance.
* The bracket is ~75 px below this port's prediction in the frame, so the axis was
  also tested on the bracket-parallel offset through (44,646) -> (764,470) — also
  nothing.

So: **not drawn, because it cannot be located.** The hand-emitted dash run is
ready to go the moment someone can point at the pixels. Upper bound on the prize
is ~350-500 px and most of that is below tol 24 once `[3,6]` duty and AA are
priced in, which is why it is last.

---

## 9. Ledger for this pass

| | before | after | delta |
|---|---|---|---|
| differing @ tol 8 | 104,436 (10.00%) | **104,241 (9.98%)** | **-195** |
| mean \|delta\| | 8.39 | **8.34** | **-0.05** |
| STRUCTURE @ tol 24 | 81,570 (7.81%) | **80,865 (7.74%)** | **-705** |

Region census, `region.mjs`, disjoint rects summing to exactly 80,865:

| region | tol 24 | before | delta |
|---|---|---|---|
| canvas 0,60,860,816 | 57,676 | 58,572 | -896 |
| panel 860,60,1280,816 | 21,921 | 21,921 | 0 |
| topbar 0,0,1280,60 | 1,268 | 1,268 | 0 |
| *of which* helix-core 140,300,700,640 | 42,492 | 42,707 | -215 |

### Blocked, quantified, not faked around

1. **helix-core — 42,492 structure px (52.5% of everything left at tol 24).**
   A rotation-like displacement varying −5…+8 px along the axis, not a constant
   offset and not a scale. Diagnosed, not guessed; the fix is the refused spin
   calibration (E22) and this lane does not touch it.
2. **panel — 21,921 px.** `libs/nimskia/src/skia_shim.cpp:225` `yk_canvas_new`
   calls `MakeRasterDirect` with three arguments, so the surface takes default
   `SkSurfaceProps` and text mask coverage is rasterised at contrast 0.5. The
   glyph pixels themselves match or exceed the reference; the **mid-tone AA ramp
   is depleted**. Needs a wire/shim change plus a `drive.exe` rebuild — engine
   territory, explicitly out of scope here.
3. **The typeface.** `Draw.text` has no family parameter and the shim's `T` verb
   hardcodes family 0, so every MONO run in the page — the bracket label and the
   four `5'`/`3'` strand-end labels — renders in Segoe UI. Measured above: drawing
   them correctly-positioned-but-wrong-faced is a net loss of 321 px at tol 8.
   This is a real SDK gap, not a port bug, and it is the same wall as (2).
4. **The dashed axis.** Searched at dev-25 and dev-37 sensitivity; not locatable
   in this frame (§8.4).

Nothing above was worked around by drawing something plausible instead. The two
things that moved the number are the two that were measured first.

### 17.26 REVERTED: the dna font switch is a measured regression, and the CSS stack was not the reason

Round 161's chess result suggested a free win — resolve the page's CSS font stack against the
fonts actually installed and pass the winner to `Draw.textFace`. On chess that was correct and
improved the score. On dna the same recipe makes it **worse**, and the reason is worth more
than the switch was.

**What was applied.** `052-dna-helix.html` declares two stacks:

    --sans: Inter, "Segoe UI Variable Text", "Segoe UI", Roboto, ...
    --mono: "JetBrains Mono", "SF Mono", Menlo, Consolas, "DejaVu Sans Mono", ...

Checked against `%WINDIR%\Fonts`: Inter, JetBrains Mono, SF Mono, Menlo and Nimbus are all
**absent**; `SegUIVar.ttf`, `segoeui.ttf` and `consola.ttf` are **present**. So the first
*present* match is **Segoe UI Variable Text** for `--sans` and **Consolas** for `--mono`, and
that is what the port was set to.

**(A false negative worth recording: a first pass filtered for `Consolas*.ttf` and reported
Consolas absent. The file is `consola.ttf`.** A font-resolution check that gets a filename
prefix wrong will confidently report a *present* font as missing and pick the wrong one
downstream. Verify the font inventory by eyeballing the actual filenames at least once.

**Measured against `ref052.png` at tol 8, all rendered at `wait:8`, baseline built from HEAD:**

| build | differing px | % | mean |
|---|---|---|---|
| baseline (no family -> Segoe UI) | 104 291 | **9.98 %** | 8.33 |
| sans only (`Segoe UI Variable Text`) | 104 830 | 10.04 % | **8.24** |
| mono only (`Consolas`) | 108 597 | 10.40 % | 9.17 |
| both | 109 136 | 10.45 % | 9.07 |

Both metrics got worse, so **this is reverted** — `apps/dna/app.nim` is back at HEAD. The
family field itself works: the two builds differ by 8 012 px, so `Draw.textFace` is not being
silently ignored. It is being applied, to the wrong font.

**Per-band attribution against the reference** (bands located by diffing the two builds, then
scored each against `ref052.png`), which is what actually localises the damage:

| band | Segoe UI | Consolas | verdict |
|---|---|---|---|
| y 87..95 | 263 | 365 | worse by 102 |
| y 107..118 | 1 164 | 1 583 | worse by 419 |
| y 136..176 | 4 530 | **8 122** | worse by **3 592** |
| y 683..691 | 690 | 883 | worse by 193 |

Consolas is worse in **every** band, so this is not one bad label. It is systematic.

**The part that makes this worth more than a revert: the ink extent is identical in all three
frames** (y 136..176 measures x 34..998 in the reference, x 33..998 in the baseline, x 34..998
with Consolas). **The glyphs sit in exactly the same places; only their shapes differ.** And
`app.nim:1119` already says

    MONO_ADV = 0.5498047'f32        ## Consolas hmtx advance / unitsPerEm

— the port is **already advancing by Consolas metrics**. So the positions were right before the
switch and are right after it; what the switch changed is which outlines fill those positions,
and Consolas outlines are further from the reference than Segoe UI outlines are.

**So the reference's canvas mono runs are laid out with Consolas advances but are not drawn in
Consolas.** That is a real and slightly surprising result: a browser is not obliged to honour
`--mono` for canvas text, because canvas `ctx.font` carries its own font string, and the CSS
variable says nothing about what the page's JavaScript asked for. **Resolving a CSS font stack
against the installed fonts is necessary and it is not sufficient** — it tells you what the
*stylesheet* would pick, not what the *canvas* actually drew. Chess was the case where they
agreed; dna is the case where they do not, and the scoreboard is what caught it.

**Kept from the attempt, because both are true and useful:** `Draw.textFace` works and is
reached; and the sans-only build is *better by 141 px inside these four bands* while being
*worse by 539 px across the whole frame* — a genuine mixed signal, so it is not shipped either.
Getting a per-region verdict and a whole-frame verdict that disagree is exactly why the whole
frame is the gate.

## Interaction pass (2026-11-04)

`apps/dna/play.nim` (new, ~700 lines, included by app.nim) wires the full
html:592-800 contract: viz drag-rotate with fling inertia, hover pick with
dim + tooltip + seq-strip highlight (both directions), zoom buttons and
`+`/`-`/Arrow/Space keys, auto-rotate toggle, reset, panel scroll (the DOM
scrolls, html:69, so the port scrolls too), the below-fold seq input with
validation messages + random + stats, the unzip/synth/done/rejoin state
machine with captions, ann hover (panel wash + focus pin + focus leader), and
the dark theme toggle (palette vars + BG + dot-field re-bake).

app.nim changes: palette consts became theme-swapped vars; build() fills
hit[] and emits the arrival nucleotides + daughter backbones when mode != 0;
repaint() runs tickPlay() and clips the panel to its scroll offset.

Proof: `web/runner/tests/dna.mjs` (43 asserts: rotate/inertia, pick/tooltip,
ann hover, keys, zoom/reset exact-settle, scroll offset, typing/invalid/
backspace/random, full unzip->synth->done->rejoin timeline) and
`node tools/verify-wasm.mjs apps/dna` ALL CHECKS PASSED. No wheel events exist
in the SDK, so scroll-to-zoom is buttons/keys only; the rest is 1:1.
