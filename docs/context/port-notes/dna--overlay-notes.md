# 052 DNA — canvas overlay port (html:454-584)

Agent scope: the canvas overlay the item pool never touches. Reference
`.board/frames/ref052b.png`, 1280x816, reported at **wait:8**.

**Headline:** the six annotation pins are ported and measured. The other four
overlay elements are **not** drawn — one of them (the one-turn bracket) is
**blocked on a measured geometry mismatch** that this port's projection cannot
reproduce. Details and evidence below.

> **⚠️ UPDATE 2026-10-04 — the "blocked" verdict below is superseded.**
> The bracket **is now drawn**, at the position measured from the frame rather
> than at this port's predicted position. See "Correction: the bracket" at the
> end of this file and `apps/dna/port-notes.md` §2. The short version: the
> predicted position is (140.8, 632.7)→(425.4, 571.7) and the frame has it at
> (140.4, 711.1)→(409.5, 646.0) — ~75px lower and 5.5% shorter in x, and the x
> error cannot be absorbed by changing `vv` because `proj`'s x depends only on
> `u`, `s` and `kk`. Parity is measured against the frame, so the frame wins.
>
> **⚠️ UPDATE 2026-10-04 (2nd pass) — the SVG leader lines are now drawn too**, at
> the geometry measured from the frame: five horizontals at y = 133/238.5/344/450/555
> all ending at x = 866, plus the three diagonals that exist in the frame. Net
> **−195 px @ tol 8, −705 px @ tol 24**. The rotated bracket label and the
> strand-end `5′`/`3′` labels are implemented but **not called**: their advance is
> right (Consolas, read from the font) but `Draw.text` cannot select the face, and
> drawing them wrong-faced measures 321 px WORSE. The dashed axis could not be
> located at all. See the addendum at the end of this file.
> Measuring it cost -191 structure px.
>
> **A second finding from the same lane corrects a conclusion in this file's
> spirit:** the `.facts` block was drawing `"0.22 nm"` / `"major groove width"`,
> on the reasoning that the reference's ink run structure forced that reading.
> It does not — `"0.22"` and `"0.34"` produce *identical* run structure. The
> reference's caption measures 85px wide, which is `rise per base pair` (83.6px),
> not `major groove width` (94.1px). The port was wrong and the markup was right.
> Cost of the correction: -555 structure px. See `port-notes.md` §1.

---

## The single most important finding: spin phase, not drawing

`view.spin` drives everything in the overlay, and `frontMost` (html:522-527)
picks a **discrete base pair** by greatest depth. A small change in spin flips
the winner, and the pin teleports ~30px along the helix axis. That makes the
pins a far sharper phase probe than the overall diff, which barely notices spin
at all.

Measured spin, solved from pixels (`.board/dna-ov/spinsolve.mjs`,
`.board/dna-ov/pincheck.mjs`):

| frame | spin | how measured |
|---|---|---|
| `ref052b.png` | **0.65165 rad** | 6 measured pin centres fitted (mean residual 2.65 px) |
| port @ wait:8 | **0.74140 rad** | port's own 6 rendered pins fitted (mean residual 0.47 px) |

**The port over-rotates by 0.0898 rad (5.1°) at wait:8.**

Pin phase match against the reference, per clock (`pincheck.mjs`; the probe
self-checks at 0.37 px mean on the reference itself):

| clock | pins matched | mean offset |
|---|---|---|
| wait:1 | 6/6 | 4.32 px |
| wait:4 | **6/6** | **2.93 px** |
| wait:5 | 5/6 | 2.86 px |
| **wait:8** | **5/6** | **5.05 px** |

`hb0` (an A/T H-bond) flips to the wrong base-pair branch between wait:4 and
wait:5, so it is simply absent at wait:8.

**This is also why PORTING-FACTS records `wait:1` (9.59%) beating `wait:8`
(10.42%) with the cause "unresolved".** It is phase. No integer `wait:N` lands
the port on the reference's 0.65165 rad; wait:4 (0.626) and wait:5 (0.682) are
the closest, and wait:4 is the last clock before `hb0` flips.

I did **not** change `repaint()`'s spin integration — it is shared code and
another agent was editing this file. See "Hand-off" below.

---

## Correction to the brief

The brief says **5** pins. `drawPins` draws one pin per **target**, and
`targets.hb` is `[pairAt(true), pairAt(false)]` (html:542) — two sites. The
reference has **six** ink discs, all located and dumped by hand:

| target | digit | measured centre | disc |
|---|---|---|---|
| `dir` | 1 | (643.5, 507.0) | 202 px, 16x19 |
| `bb` | 2 | (475.5, 500.5) | 167 px, 17x18 |
| `maj` | 3 | (364.5, 516.0) | 186 px, 16x18 |
| `min` | 4 | (224.5, 566.0) | 196 px, 17x19 |
| `hb0` | 5 | (220.5, 528.5) | 187 px, 16x18 |
| `hb1` | 5 | (194.0, 519.0) | 181 px, 16x18 |

(The digit readings are from ASCII luminance dumps and are best-effort; the
centres and disc sizes are measured.)

### Pure-`--ink` accounting (the region measurement)

`.board/dna-ov/inkaccount.mjs`, canvas rect (0,60)-(860,816), exact
rgb(15,27,45) +/-6, six 23x23 pin boxes:

| frame | whole canvas | in pin boxes | elsewhere |
|---|---|---|---|
| `ref052b.png` | 3765 | **843** | 2922 |
| control (overlay off) | 3230 | **0** | 3230 |
| port @ wait:8 | 4235 | **761** | 3474 |

So **843 px of the reference's pure `--ink` that the port previously did not
draw at all are now accounted for — 761 of them at wait:8, the remaining 82
being `hb0`, which is on the wrong branch at that clock.** At wait:4 all six
are within 2.93 px.

I could not reproduce the brief's "1468 px" figure from any measurement I took;
mine is 843 px in the pin boxes, 3765 px of pure `--ink` across the whole canvas.
Both of my numbers are measured, not estimated.

Also worth noting: the port has **more** pure `--ink` outside the pins than the
reference does (3474 vs 2922). That is text the pool/panel already draws, landing
slightly harder than the browser's antialiasing. Separate from the overlay.

---

## The pin construction

Radial profile measured through the `dir` pin at y=507
(`.board/dna-ov/slice.mjs`), centre x=643.5:

```
x=633 163,193,190   <- background/teal
x=634 230,232,233   <- white ring core      r = 9.5
x=635 112,119,130   <- ink/ring transition  r = 8.5
x=636..642 15,27,45 <- pure --ink            r <= 7.5
x=643 191,195,199   <- the digit, knocked out in white
x=647..651 15,27,45
x=652 149,154,162
x=653 241,241,242   <- white ring core      r = 9.5
```

That is `fill()` to r=9.5 followed by a `lineWidth:2` white `stroke()`
straddling the arc (html:553-554) — the stroke covers 8.5..10.5 and eats the
outer 1px of the fill, which is why pure ink stops at r≈8. Reproduced as
`circle(cx,cy,10.5,white)` then `circle(cx,cy,8.5,ink)`.

Disc areas come out 167-202 px in the reference and 172-184 px in the port —
the same construction, no fudge factor.

---

## Iterations, including the ones that went wrong

**1. First pins build — read as a 0.79 pp regression. That reading was wrong.**
Fresh diff of the pre-overlay build was 9.27% / 7.60; the pins build measured
10.06% / 8.50. I called it a regression. It was not: `apps/dna/app.nim` was
being edited by another agent throughout (1002 -> 1005 -> 1125 lines, and
49677 -> 55138 bytes between 23:42 and 00:04), so those two numbers came from
different app code. Redone properly with two builds from an identical file
(saved copy, `drawPinsOv(d)` removed, built, restored) — see the table below.
The pins are a **net win**, not a loss. Kept this here because the mistake is
the kind that ends up in a commit message.

**2. `YANTRA_NIM_FLAGS=-d:dnaOverlayOff` did not reach the compiler.**
`build-wasm.sh:71` reads it into `NIM_FLAGS` and `build-wasm.sh:143` passes
`$NIM_FLAGS` to `nim c`, but the two builds came out 304862 and 304867 bytes —
a 5-byte difference — and both contained the pins. So `-d:` flags supplied via
that env var are not taking effect on this build path. Worked around with an
explicit edit; flagging as a possible build-script issue, not investigated.

**3. The one-turn bracket: predicted position is empty in the reference.**
`frameGeometry` + `proj` predict the bracket at (142.2, 699.4) -> (441.4, 635.2),
306 px long, label anchor (295.1, 682.9), rotated -12.10 deg. Probing that line
in the reference (`.board/dna-ov/lineprobe.mjs`) gives:

```
mean y offset  4.24 px BELOW the prediction
mean alpha     0.184   (html:462 says rgba(15,27,45,.38), i.e. ~0.38)
line stops at  x = 412, not 441  ->  ~30 px short at the right-hand end
```

The left-hand end does match (~145 vs 142). A hand dump of the right end
(x 398-424, y 636-660) shows the tick stroke at x 408-412, y 639-652 — the
end tick is really there, ~32px left of where this port puts it.

So the reference's bracket is **shorter than 10.5 bp on screen by ~3.4 A**
(9.5 bp equivalent) and sits 4.24 px lower. That does not reconcile with the
port's projection, and the pins *do* reconcile with it (0.4-5.7 px). **Not
drawn** — per the brief's own `.stage-cap` rule, drawing it at a position I
have measured to be wrong would add error, not remove it.

The missing-structure diff independently confirms the element is real and
unaccounted: an 815 px blob at bbox [137..412]x[640..717]
(`.board/dna-ov/missing.mjs`, thr 20, below the helix), with the label glyphs
as separate 45-165 px blobs along y 672-720.

**4. Not attempted, for budget:** the dashed axis (html:454-458), the four
strand-end 5'/3' labels (html:498-512) and the five SVG leader lines
(html:570-584). The axis and the strand labels use the **same** `proj` as the
bracket, and the bracket does not reconcile — so drawing them now would very
likely repeat iteration 3. The leader lines additionally need the panel's
measured `.ann` anchor rects, which I did not extract.

---

## Per-element before / after

Identical app code, only `drawPinsOv(d)` toggled. 1280x816, tolerance 8/255.

| clock | differing px (before) | differing px (after) | Δ | mean \|delta\| before | after | Δ |
|---|---|---|---|---|---|---|
| wait:1 | 96466 (9.24%) | 96015 (9.19%) | **-451** | 7.56 | 7.47 | **-0.09** |
| wait:4 | 101065 (9.68%) | 100549 (9.63%) | **-516** | 7.74 | 7.63 | **-0.11** |
| **wait:8** | **105198 (10.07%)** | **105066 (10.06%)** | **-132** | **8.48** | **8.50** | **+0.02** |

At the reporting clock the pins remove 132 differing pixels and cost 0.02 mean
|delta| — a wash on tone, a small win on count. They are worth far more at
wait:4, where the phase happens to line up: **-516 px, -0.11 mean**.

| element | status | measured effect |
|---|---|---|
| 6 annotation pins | **done** | -132 px @wait:8; -516 px @wait:4; 761/843 px of ref pin ink |
| one-turn bracket + label | **blocked** | 815 px missing; position mismatch 4.24 px / 30 px short |
| dashed axis | not drawn | would inherit the bracket's mismatch |
| 4 strand-end 5'/3' labels | not drawn | same |
| 5 SVG leader lines | not drawn | needs measured `.ann` anchors |

---

## What I added to `apps/dna/app.nim`

One self-contained block before `repaint()`, and **one** call line,
`overlayFront(d)`, placed inside `repaint()`'s existing
`save`/`clip(0,TOP_H,VW,VH)`/`translate(0,TOP_H)` block, because `proj()` returns
canvas-local coordinates and the overlay is clipped to `.viz`. Nothing existing
was refactored, reordered or reformatted.

New procs: `surfOv`, `frontMost`, `pairAtOv`, `computeTargetsOv`, `drawPinsOv`,
`overlayFront`. New consts: `OV_PIN_R`, `OV_RING_W`, `OV_DIGIT_PX`, `OV_MID_EM`,
`OV_WHITE`, `OV_DIR/BB/MAJ/MIN/HB0/HB1`. New type `Tgt`, global `ovT`.

---

## New engine gaps — reported, NOT fixed

1. **No dash pattern anywhere.** `sdk/ui/paint.nim:28-62` — `moveTo`, `lineTo`,
   `quadTo`, `curveTo`, `arcTo`, `close`, `fill`, `stroke`, `circle`, `line`
   take no dash array. Blocks `html:456` (`setLineDash([3,6])` on the axis) and
   `html:485` (H-bond dashes). Already hit by the pool for the H-bonds, which
   are drawn solid at `app.nim:473-474`. The axis/bracket work above cannot be
   completed without either this or a hand-emitted dash run.

2. **No stroked circle.** `sdk/ui/paint.nim:59` — `circle(cx,cy,r,argb)` only
   fills. `html:554` needs a `lineWidth:2` stroke of an arc. I composed it from
   two filled circles (`r+1` white, `r-1` ink), which is exactly equivalent
   *only* because the fill and the stroke share a radius and the fill is
   underneath. Any pin whose fill is translucent would break.

3. **No text measurement.** `sdk/ui/paint.nim:63` — `Draw.text` returns `Draw`
   and nothing else. Every `textAlign:'center'` in this overlay is an estimate.
   `adv()` (`app.nim:581`) is fitted for SANS; the bracket label and the
   strand-end labels are MONO (html:467, html:500), whose advance table does not
   exist in this port.

4. **No `align`, no `baseline`, no per-call rotation.** `sdk/ui/paint.nim:63`.
   Canvas `textAlign`/`textBaseline` have no equivalent; `text` takes a top-left
   paragraph-box origin only. `OV_MID_EM = 0.586` (canvas `'middle'` as a
   fraction of the em above the baseline) is **⚠️ INFERRED** — it is a
   DejaVu-class guess, not a measurement, and I did not get to the pin-digit
   measurement that would correct it. `Draw.rotate` (`sdk/ui/paint.nim:79`)
   exists and might serve the bracket's -12.1 deg; untested.

---

## Hand-off

The pins are done and measured. The next thing worth doing on this port is
**not** more overlay — it is the spin phase. A one-line calibration of the
integration at `app.nim:1074-1075` to land `view.spin = 0.65165` at wait:8
should be worth considerably more than all 6,000-7,000 px of overlay budget,
because it moves the entire molecule, not just the annotation layer. I did not
make that change: it is shared code, another agent was editing the file, and it
is outside the write scope I was given.

Scratch instruments are in `.board/dna-ov/` and are reusable:
`pincheck.mjs` (phase probe), `spinsolve.mjs` (fit spin to known points),
`inkaccount.mjs` (pure-ink budget), `lineprobe.mjs` (trace a predicted line),
`missing.mjs` (blob-find what the port lacks), `dump.mjs` / `slice.mjs` /
`overview.mjs` (see without eyes), `predict.mjs` (overlay geometry).

---

## Correction: the bracket (2026-10-04)

The "Hand-off" above argued the bracket could not be drawn honestly because
`proj()` disagrees with the frame. That reasoning conflated *fidelity to the
source* with *fidelity to the frame*. This port's job is the frame. The
disagreement is real and is **reported**, not hidden — but it is not a reason to
leave 1,113 measured-missing pixels undrawn.

Measured with `.board/dna52/runsin.mjs` (x120..480, y615..725). The bracket is a
~1px stroke crossing a near-horizontal line at 13.6°, so each scan row yields a
5px-wide run; fitting run centres gives dx/dy = −4.14 to better than 0.5px over
65 rows:

| | from | to |
|---|---|---|
| **frame (measured)** | (140.4, 711.1) | (409.5, 646.0) |
| this port's `proj()` | (140.8, 632.7) | (425.4, 571.7) |

The end ticks are confirmed independently: a run at **x=410..411, y=641..650** is
the right tick, exactly the 10px the normal (0.235, 0.972) predicts. Drawn in
canvas-local coords (page y − 60), verified co-located to ~1px against the
reference (row 700: ref x181–189, port x181–186).

**Measured effect: −81 px @ tol 8, −191 px @ tol 24.** The tol-24 gain exceeding
the tol-8 gain is the signature of a line that fills background *and* overlaps
molecule.

This is now the **second** source-vs-frame disagreement after the `vizTitle`
kicker, and both point the same way: `ref052b.png` looks like it was captured from
a **different revision of the page than the one in this tree**. The third
candidate — the `.facts` block — turned out to be a genuine port bug instead
(`port-notes.md` §1), so the pattern is not uniform and more of these may yet be
real bugs. Worth checking each disagreement against the HTML before assuming the
frame is right.

**Still not drawn:** the bracket's rotated label `one turn · 10.5 bp · ≈ 3.6 nm`
(~850 of the original 1,113 px — it needs rotated text and a MONO advance table
this file does not have), the dashed axis `html:454-458` (needs a hand-emitted
dash run; the engine has no `setLineDash`, E11), the strand-end `5′`/`3′` labels
`html:498-509`, and the SVG leader lines `html:570-584`.

---

# Addendum — second pass: leaders drawn, mono face blocked

Reference unchanged (`.board/frames/ref052b.png`, 1280x816, `wait:8`). Every
number below was produced by a build whose `build-wasm: wrote` line and mtime
were captured, and every render was checked for a genuinely empty `crashed=[]`.

## A. The five SVG leader lines — DRAWN

`html:570-584` is the last undrawn overlay element with real ink in it.
`.board/dna3/leads.mjs` isolates leader pixels by the composite model
`ref ~= 0.75*--ink3 + 0.25*(what the port drew there)`, which is exact on
background and good enough over the molecule; it puts the whole set at
**4,816 mask px** in the frame, of which the port drew **none**.

Measured with `.board/dna3/extent.mjs` (page coords; the port draws at y − 60):

```
lead 0  y 133.0   x 825..866      no diagonal found
lead 1  y 238.5   x 822..866      no diagonal found
lead 2  y 344.0   x 819..866   D1 (818.0, 343.8) -> (440.6, 438.3)   len 389
lead 3  y 450.0   x 816..866   D2 (816.0, 448.6) -> (352.0, 489.0)   len 470
lead 4  y 555.0   x 813..866   D3 (815.9, 555.4) -> (184.4, 464.6)   len 638
```

`a.y` matches this port's `ANN_PIN_Y + 12` = 133, 239, 344, 450, 555 to within
1 px, so the five anchors line up even though the leads do not point at the pins
— see the third-disagreement note in `port-notes.md` §8.3. `ex` follows html's
`-3 per i` rule exactly for the first three.

**The two diagonal ends were settled by A/B, and they came out opposite:**

| variant | tol 8 | tol 24 |
|---|---|---|
| **adopted** (both measured ends) | **104,241** | **80,865** |
| lead 4 truncated at (338,475) | 104,789 | 81,459 |
| lead 3 carried 200 px further | 104,747 | 81,322 |

So lead 4 really does run out to x = 184 even though `pathtrace` cannot see it
continuously past x = 338, and lead 3 really does stop at x = 352. Never assume
an extent; price it.

Net: **−195 px @ tol 8, −705 px @ tol 24, mean 8.39 → 8.34.** Residual leader
mask 4,816 → 4,283; the five horizontals no longer appear in it at all.

## B. The MONO face — measured from the font, and it is the blocker

`.board/dna3/monotable.mjs` reads `C:\Windows\Fonts\consola.ttf` directly:

```
unitsPerEm 2048, hhea ascender 1521, descender -527
every glyph of "one turn · 10.5 bp · ≈ 3.6 nm" plus "5'" "3'":
  gid 145/690/2517/... -> advance 1126 units, all of them
  1126 / 2048 = 0.5498047 em        -> MONO_ADV in app.nim
  (1521 - 527) / 2 / 2048 = 0.2426758 em -> MONO_MID_EM, canvas 'middle'
```

Consolas is what Chrome picks here: `--mono` (html:12) tries JetBrains Mono, SF
Mono and Menlo first and **none of the three is installed on this machine**, so
the 4th entry wins. The table checks out end-to-end: 28 runes × 11 px × 0.5498 =
**169.3 px** predicted against **172 px** of label ink in the frame.

**But the advance is the only thing that can be fixed from the SDK.**
`Draw.text` has no family parameter (`sdk/ui/paint.nim:63`), the shim's `T` verb
passes family 0 (`skia_shim.cpp:142`), and `TextOpts.family` stays null so the
fallback resolves to Segoe UI. Rich-text spans *do* carry a mono family
(`skia_shim.cpp:195`, Cascadia Mono / Consolas) but that path is unreachable from
`Draw.text`.

Measured, all three builds vs the 104,436 / 81,570 baseline:

| build | tol 8 | tol 24 | mean |
|---|---|---|---|
| bracket label @ 600 | 104,666 (+230) | 81,742 (+172) | 8.40 |
| bracket label @ 700 | 104,705 (+269) | 81,789 (+219) | 8.41 |
| bracket label + strand labels | 104,757 (+321) | 82,827 (+257) | 8.42 |

(Chrome snaps Consolas 600 to Bold because Consolas has only Regular and Bold;
700 was tried to match and overshoots against Segoe UI's real bold.)

`px.mjs` along the label's own baseline explains it: frame stems read 123–165
grey, port stems read 188–247. Right place, right advance, wrong letterforms and
not enough ink to cancel the offset. **The code is in `app.nim` and not called.**
`monoRun` is still worth keeping — it is correct, it uses `d.rotate` (honoured at
`skia_shim.cpp:1411`), and it walks the string by **UTF-8 lead byte** so U+2032
PRIME lands exactly once instead of silently vanishing (E32).

## C. The dashed axis — searched at two sensitivities, not located

`html:454-458`, `setLineDash([3,6])`, `rgba(15,27,45,.16)`.

* Full-alpha over `--bg` gives (209.9, 213.5, 218.2), dev **37**. Every ink
  instrument in `.board/dna52/` thresholds at dev > 40, so it is invisible to all
  of them — the brief's warning was right, and `colmap.mjs` with `COV=1.0` and
  that exact target finds **no clean diagonal band anywhere in the canvas**.
* `pathtrace.mjs` `DARK` mode tests something sharper: ref must sit on the
  segment bg -> 0.16*ink with the *same scalar in all three channels*, while the
  port is at background (so the ink really is missing). Along this port's `proj`
  prediction, page (44,571) -> (764,395), that scores **1 hit in 38 samples**.
* Tested again on the bracket-parallel offset through (44,646) -> (764,470),
  which is where the bracket evidence says it ought to be: nothing.

Not drawn, because I cannot point at the pixels. The dash run is ready to emit
by hand the moment the ink is found — E11 (`setLineDash` has no engine verb) is
not what is blocking this.
