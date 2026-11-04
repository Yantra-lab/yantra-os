# Changelog — this skill is a living document

Every port, fix or new engine fact should land here **in the same change**.

## How to keep this folder current

The rule is simple: **you learn something on a real port, you write it down
before you finish.** A fact that only lives in your head is lost.

| What you learned | Where it goes |
|---|---|
| An API, prop or signature | `reference/03-node-and-prop-reference.md` (only if read from source) |
| A CSS/DOM/JS → Yantra mapping | `reference/15a-html-css-mapping.md` |
| A gap, a limitation, a workaround | `reference/16-engine-limits-and-workarounds.md` |
| A compiler error and its fix | `reference/17-pitfalls.md` — exact error text, never paraphrased |
| A reusable snippet | `examples/` — **and build it** before you commit |
| Anything user-visible | a line in this file |

Never document an API you did not see in the source. Never leave a
`VERIFY IN SOURCE` marker behind — resolve it or delete the claim. Never claim a
number you did not measure.

**When you correct something that was already wrong**, do not silently rewrite
it. Leave the old claim visible and add a `CORRECTED` note under it carrying the
`path:line` or the measurement that settles it — a reader who memorised the old
rule needs to see that it changed and why.

---

## 2026-10-03 — routing repaired, engine facts reconciled with measurement

Full changelog entry, with the evidence for each correction, is at the top of
[`../README.md`](../README.md). In short:

**Routing.** Chapters **21**, **22** and **23** linked from nothing — they are
now routed from `reference/00-INDEX.md` and `SKILL.md`. The whole
`../web-to-yantra/` skill was unrouted and is now linked from three places. Two
links in this folder pointed at a non-existent `reference/15a-html-css-js-mapping.md`;
the real file is `reference/15a-html-css-mapping.md` (this table and `SKILL.md`
were both wrong).

**Chapter count.** This folder's README claimed "20 routed chapters". The truth
is **22 chapters plus `00-INDEX.md` = 23 files in `reference/`**, with no `04`
and no `14`/`15` — the numbering skips them deliberately.

**Engine facts corrected across the chapters**, each with `path:line` evidence:

| fact | evidence |
|---|---|
| `Draw.text`'s `y` is the paragraph line-box top, not the baseline; `baseline = y + 1.0833·S` | `libs/nimskia/src/skia_shim.cpp:291`; the `nimskia.nim:76` doc comment is wrong |
| `Draw` colours are AARRGGBB — a bare CSS hex is fully transparent (and only `Draw` is affected: node props are rescued by `engine.nim:345-348`) | `sdk/ui/paint.nim:57` and every sibling primitive; `skia_shim.cpp:1327` |
| `rgba` exists twice, with different arity and return type | `sdk/ui/style.nim:23` vs. the app-local `rgba(r,g,b: int32; a: float32): uint32` |
| `Draw.alpha()` is **not** dropped — it is a cumulative multiplier | `sdk/ui/paint.nim:80` emits `"O "`; `skia_shim.cpp:1412` handles it; applied at `:1327` |
| an unrecognised Draw verb **is** skipped silently | `skia_shim.cpp:1413` `default: break;` |
| `frameDt()` is the live clock; `yantra_get_dt()` reads 0 on the native runner | `sdk/ui/input.nim:45` vs `sdk/core/runtime.nim:75`; `setFrameDt` only in `render/render_qml.nim:42` and a test |
| no filled-polygon and no `ellipse` primitive; `svgPath` does exist | `sdk/ui/paint.nim:28,29,45,53` / `:59,:35` / `:46` |
| no text measurement API in the SDK | `sdk/ui/paint.nim:63` returns `Draw`; `measureText` is native-side only (`nimskia.nim:68,:122`) |
| frame dumps are BGRA and must be swapped before diffing | `render/native/drive.nim:191-193`; 91.45% unswapped vs 72.83% swapped, same port and reference |
| `log()` is unobservable and costs ~7% of module size | measured +15,660 bytes on a ~215 KB module |

**Six fabricated citations removed.** `reference/16-engine-limits-and-workarounds.md`
cited `render/native/t_paint_arc.nim`, `t_paint_path.nim`, `t_paint_alpha.nim`,
`t_font.nim`, `t_assetready.nim` and `t_select.nim`. **None of them exists** in
the repo. Every surviving `path:line` in this folder was re-verified against the
real tree.

**`scripts/` and `assets/` are empty.** They were advertised in the README's
layout as "build + verify helpers". They contain nothing. The README now says so
and points at the real tools in `tools/`. The directories were left on disk —
deleting a folder is the Owner's call (`AGENTS.md` rule 9).

## 2026-10-04 — lessons from porting five real apps

Verified complete: **zero open `VERIFY IN SOURCE` markers remain** anywhere in
`skills/` (a search returns 4 hits, all of them the *rule text* describing the
convention — `yantra/SKILL.md:195`, `web-to-yantra/SKILL.md:226`, and two lines of
this changelog — not an unresolved claim), and 80/80 relative links resolve. Then
extended with three things this round proved the hard way, each traceable to a
measured failure rather than to a review pass.

| addition | chapter | why |
|---|---|---|
| diff at **two tolerances** to split grain from structure | `21-visual-parity-verification.md` | a headline "differing pixels" number cannot tell you how much of the error is worth attacking |
| the **annulus containment invariant** | `24-draw-alpha-ramps.md` | the chapter recommended "flat rings" without saying *why* they work where nested fills cannot |
| some original JS is **not reproducible** | `20-cloning-a-live-website.md` | a seeded PRNG is portable; a PRNG consumed by a sort comparator is not |

**The tolerance split refuted a live claim.** #52 was reported as "at its floor". On the
headline it is the best of five ports (10.06%); by structure it is the **worst** — only
22% grain against chess's 82%, carrying **82,316 structural pixels** versus chess's
39,605 and calligraphy a 56,565. Both statements were true of different quantities and
only one was actionable. The lesson is now a rule: **"at the floor" is a claim about
structure, so it owes a measurement.**

Corollary recorded with it: **score colour candidates at tol 8, never on mean offset.**
On #70 a dark-square blue −4 shift *gained* 80 px at tol 24 while *losing* 3,297 at
tol 8, because narrowing a grain window from one side pushes half the noise out the
other. A mean-|Δ| improvement is not evidence.

**The annulus invariant, stated because the symptom misleads.** A filled ellipse
carrying alpha also covers its own centre, and alpha cannot be subtracted once painted —
so drawing outside-in covers the whole frame and inside-out hits the centre. Neither is
a ramp, and both read as "the gradient is too strong". A band drawn *between* two
contours is always contained within its outer contour, so no band repaints another's
interior: the same invariant as the non-zero winding rule. Each band is drawn **once**
at the **cumulative** alpha `1 - p`; the per-band increment reproduces the old trap.

**A PRNG consumed by a comparison callback is not portable.** #75's `html:581` shuffles
with `[0,1,2,3,4].sort(function(){ return R() - 0.5; })`. The comparator draws from the
PRNG, so *how many times it runs* is implementation-defined — a property of V8's TimSort,
not of the source. The permutation cannot be derived from the source at all. The chapter
now says to name the line and report what *does* land (the 70 wear circles and 260
speckles after the shuffle stayed statistically identical) instead of quietly
substituting. With the inverse warning: **do not hope a region is grain so you can stop**
— #70's title block measured 6.5% grain, pure structure, and would have been a false
excuse to leave it.

**Recorded because three separate lanes re-learned it this round:** "the region is empty"
is nearly always a broken invocation, not a measurement. Observed causes were probe
coordinates off-surface, a PNG read as raw bytes, an argv-shape mismatch, and one lane's
own PRNG simulator disagreeing with the JS and manufacturing a convincing *analytic
prediction* of a port defect. The surviving rule: **an instrument that cannot fail will
fail confidently** — validate against `tools/pngdiff.mjs`, or make the tool refuse.

Engine facts newly established and filed with `path:line` in `.board/reports/ISSUES.md`
(E26–E29); all are queued for the Owner in `DECISION_QUEUE.md` as D10/D11, with E29
folded into D6 because a font API that cannot name a CJK face cannot fix it either.

---

## 2026-10-03 — initial build

Created the skill from the SDK source: `sdk/yantra.nim`, `sdk/core/wire.nim`,
`sdk/ui/dsl.nim`, `sdk/ui/paint.nim`, `sdk/core/signals.nim`, plus `AGENTS.md`
and `tools/build-wasm.sh`.

Measured facts established up front:

- `bash tools/build-wasm.sh <src.nim> <out.wasm>` builds in **~9 s**, exit 0.
- **48** node kinds and **265** props in the wire protocol.
- **35** easing curves, **34** events, **29** Skia blend modes.

Pitfalls captured by actually breaking things and reading the real errors:

| Error text (measured) | Cause | Fix |
|---|---|---|
| `invalid module name: '01-hello-app'; a module name must be a valid Nim identifier.` | Nim module names cannot start with a digit or contain `-` | Rename `01-hello-app.nim` → `hello_app.nim` |
| `type mismatch: got 'int' for 'count + 1' but expected 'Signal[system.int]'` | A `Signal` has a converter that unwraps it on read, but there is no `=` overload, so `count = count + 1` is a type error | Mutate with `count += 1`, `count.set(v)` or `count.update(proc(v: var int) = …)` |
| `expression 'createEffect(proc () = …)' is of type 'Effect' and has to be used (or discarded)` | `createEffect` returns an `Effect` handle | `discard createEffect(proc () = …)` |

Verified compiling examples: `examples/hello_app.nim` (215120 bytes),
`examples/imperative_app.nim` (214577 bytes).