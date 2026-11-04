# 18 — The porting process

Porting an HTML page (or any web app) to Yantra. Eight phases, each with a **done test**. Do not
skip ahead: each phase's done test is what makes the next one cheap.

Source of truth: `docs/agent-guide/process.md`, `quality.md`, `README.md`.

**What this chapter is for.** The general route from an HTML file to a Yantra app: eight phases,
each with a done test, plus the canvas-vs-node decision and the seven anti-patterns. **After
this chapter you can** decide what to port as a node and what to draw, sequence the work so
each phase is cheap, and write a GAP instead of faking a feature.

**Read next:** `01-build-run-and-verify.md` for the build and harness commands;
`20-cloning-a-live-website.md` when the source is a live URL rather than a local file;
`21-visual-parity-verification.md` for phase 6's instrument; `23-wasm-import-gate.md` when
nothing renders; `19-done-checklist.md` before you say done.

> **CORRECTED 2026-10-03 — engine corrections that were missing from these phases.** Each one
> compiles, runs, and silently does the wrong thing. See §5b of
> `01-build-run-and-verify.md` for the full evidence; the short form:
>
> | claim | where it bites | the rule |
> |---|---|---|
> | colours are AARRGGBB | phase 2 spec, phase 5 build | a pasted CSS hex (`0xF7F9FB`) has alpha `0x00` and draws **fully transparent**. Force `0xFF` — `apps/chess/app.nim:100` |
> | text `y` is the baseline | phase 5 text layout | it is the **top of the line box**. Baseline is `y + 1.0833·S`; use `yantra_y = wantedBaselineY - 1.0833 * size` (`skia_shim.cpp:291`) |
> | centring needs no measurement | phase 2 sizes, phase 5 | **there is no measurement API.** `Draw.text` returns `Draw` and has no `align` (`sdk/ui/paint.nim:63`). Estimate, and write the estimate into PORT-NOTES |
> | animation is driven by `yantra_get_dt()` | phase 5 behaviour | **it reads 0 on the real runner.** Use `frameDt()` (`sdk/ui/input.nim:45`; `setFrameDt` has zero callers under `render/native/`, `cli/`, `apps/`, `web/`) |
> | a clean build means a fresh module | phase 5, phase 7 | **a failed build leaves the old `.wasm` on disk** and the harness re-renders the stale artifact. Confirm `build-wasm: wrote …` |
> | `when isMainModule: main()` is the entry point | phase 5 | **`host/host.nim:1188` calls `yantra_main` unconditionally.** A `NimMainModule` export builds, passes every check, and renders nothing |

---

## Phase 1 — READ the source completely

Read the entire HTML/CSS/JS. Not a skim. Not the rendered result.

**Inventory, in writing:**

- every DOM node and its nesting
- every CSS rule: selectors, exact values, media queries, pseudo-classes, keyframes
- every canvas / SVG / WebGL block and what it draws
- every JS state machine: state variables, transitions, timers
- every animation: duration (ms), easing function, delay, iteration
- every web API: `fetch`, WebSocket, `localStorage`, IndexedDB, timers, clipboard, geolocation

> "Get the original running in a browser and take reference screenshots of each screen/state."
> — process.md §1. **Do this before writing any Nim.** The screenshots are the acceptance test
> for Phase 6; without them you have nothing to compare against.

**Done test:** you can list every screen/state the page has, and every element on each, without
re-opening the source. If you cannot, you have not finished reading.

---

## Phase 2 — WRITE the spec

Create `apps/<name>/PORT-NOTES.md`. Capture **exact** values, not approximations:

- **Palette:** every hex, spelled out. `README.md` rule 3: "Same colours (copy the hex values).
  "Close enough" is not the goal; side by side is." — **and written as AARRGGBB.** Yantra's
  `argb` is `0xAARRGGBB`; a CSS hex pasted straight in has alpha `0x00` and draws **fully
  transparent**. Measured on port #52: adding the alpha bytes moved it from 100% differing to
  23.7% in one edit. Record the hex **and** its alpha, e.g. `#F7F9FB -> 0xFFF7F9FB`.
- **Sizes:** every px. Same rule.
- **Fonts:** family, weight, size, line-height, letter-spacing — **and the baseline.** Text `y`
  in a Yantra `Draw` is the **top of the paragraph line box, not the baseline**
  (`libs/nimskia/src/skia_shim.cpp:291`); the baseline sits at `y + 1.0833·S`, so
  `yantra_y = wantedBaselineY - 1.0833 * size`. `libs/nimskia/src/nimskia.nim:76` documents
  the opposite and is **wrong**. Those constants are empirical, for the default typeface and
  weight only — a port that sets a family must re-probe them.
- **Text metrics:** record every centring or wrapping as an **estimate**. There is **no text
  measurement API in the SDK** — `sdk/ui/paint.nim:63` returns `Draw` and nothing else, and
  `Draw.text` has no `align` parameter; `measureText` exists only natively
  (`libs/nimskia/src/nimskia.nim:68`, `:122`). An estimate written down is honest; an exact
  centring claim you cannot measure is over-claiming.
- **Spacing:** paddings, margins, gaps.
- **Timings:** ms durations, easing curves, delays.
- **Layout tree:** the nesting, written as a tree.

Also record, per the process.md inventory: **assets** (images, fonts, sounds — copied into
`apps/<name>/` with the same names) and **numbers to keep** (colours, sizes, speeds, camera
positions, physics constants — "they are what makes it 'the same'").

**Done test:** every hex and every px in the spec is a literal you copied, not one you estimated.
Grep your spec for words like "about", "roughly", "similar" — every hit is a value you did not
measure.

---

## Phase 3 — CLASSIFY each element

For every element from Phase 1, assign exactly one class:

| Class | Means |
|---|---|
| **native node** | Yantra has a node for this (`text`, `button`, `input`, `image`, `column`, …). Use it. |
| **canvas drawing** | Procedural, repeated, or hundreds of similar things. Draw it. |
| **unsupported** | No Yantra equivalent today. This is a GAP. |

Classify by **behaviour**, not by appearance. A grid of 400 bars looks like 400 DOM nodes in the
source; it is one canvas draw list.

**Done test:** every element from Phase 1 appears in exactly one of the three classes. No element
is unclassified. An unclassified element is the one that will silently vanish later.

---

## Phase 4 — Check the engine-limits chapter

For **every** "unsupported" from Phase 3, check the engine-limits / gaps chapter *before*
improvising.

> "If Yantra lacks something, write it in `PORT-NOTES.md` next to the app (what is missing, where,
> what you did instead) and carry on with the rest."
> — `docs/agent-guide/README.md` rule 4

**Never fake a feature.** Do not draw a placeholder that pretends to be the thing. A reviewer
finding a picture of a feature instead of the feature is a rejection (quality.md review checklist).

**Done test:** each GAP has a written line in PORT-NOTES.md: what is missing, where it was in the
original, and what you did instead. Count of GAPS in Phase 3 == count of GAP lines in
PORT-NOTES.md.

---

## Phase 5 — BUILD the tree incrementally

Get **something on screen early**. Order, from `process.md` §2:

1. **Data and logic first**, as plain Nim, with the original's names. JS → Nim is mechanical:
   `const`/`let` → `let`, reassigned `let` → `var`, arrays → `seq`, objects → `object`,
   `Map` → `Table` (std/tables), classes → object + procs, `number` → `float32`/`int`.
2. **The static screen:** layout and look. Compare with the reference screenshot *before*
   adding behaviour.
3. **Behaviour:** events, signals, frame loop, animation, sound.
4. **Polish:** transitions, post-processing, particles, exact timings.

**Advance the clock with `frameDt()`, never with `yantra_get_dt()`.** `sdk/ui/input.nim:45` —
`proc frameDt*(): float32 = yInput(7, 0)` — is the live clock the engine feeds. `yantra_get_dt`
is declared as an `importc` (`sdk/core/runtime.nim:75`) whose only writer is `setFrameDt`
(`host/host.nim:1211-1213`, registered at `host/host.nim:1024`), and repo-wide `setFrameDt`
appears in exactly **two** files: `render/render_qml.nim:42` (legacy Qt) and
`host/t_run_hello.nim:107`, `:137`, `:140` (a test harness). **Zero occurrences under
`render/native/`, `cli/`, `apps/` or `web/`.** So on the real runner `yantra_get_dt()` reads
0 and an app animated off it **never moves** — it builds, it renders, it passes, frozen.

**What `frameDt()` actually returns** — `render/native/engine.nim:3241`:

```nim
e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60
```

Two consequences worth knowing before you animate anything:

- **The first frame is a synthetic `1/60` s, never 0.** Your first step is not lost.
- **It is a real elapsed delta afterwards, unclamped.** A window that was stalled, minimised
  or backgrounded produces **one large value on return**, and `speed * frameDt()` teleports
  whatever moves by that much. **Clamp it.**

```nim
let dt = min(frameDt(), 0.05'f32)   # never trust a raw frameDt on the frame after a stall
```

**Do not instrument with `log()`.** It compiles, it is callable, and **nothing in the repo
reads it**: `host/host.nim:628` (`cbLog`) is the only writer, `host/host.nim:1029` binds
`yantra_log` to it, and the only reader anywhere — `render/native/t_mpopen.nim:173` — reads a
different log, the engine's `e.s.logs`. One `log()` call measured **+15,660 bytes** on a
~215 KB module. Instrument by drawing, or by reading pixels with `drive.exe`'s `boxes` / `crash`
verbs.

Build after every few changes:

```
bash tools/build-wasm.sh apps/<name>/app.nim apps/<name>/app.wasm
```

> **Confirm the build printed `build-wasm: wrote apps/<name>/app.wasm (<n> bytes)`.** A failed
> build **leaves the previous `.wasm` in place**, and the next verification step will render
> the stale artifact: exit 0, a full-size raw, a plausible number, for code that does not
> exist. This is not hypothetical — a stale `hello.wasm` once hid an SDK that did not compile.

> **The app must export `yantra_main`.** `proc yantra_main*() {.exportc: "yantra_main".} = main()`.
> `host/host.nim:1188` calls it unconditionally; an app with only
> `when isMainModule: main()` exports `NimMainModule` instead, compiles clean, passes every
> headless check, and never renders a frame. One port sat in exactly that state — a 2,005-byte
> stub that built and passed while rendering nothing. Proof it is missing:
> `WebAssembly.Module.exports()` returns `false` for `yantra_main`.

> "Compare with the reference screenshots at the same window size. Check colours with a picker."
> — process.md §3. Same window size, or the comparison is meaningless. **And same clock:**
> `21-visual-parity-verification.md` §10 — two headless captures of the same page at the same
> nominal 800 ms budget already differ by 2.13%.

**Done test:** the app builds clean, and the static screen — layout and look, no behaviour yet —
visually matches its reference screenshot before you write a single event handler.

---

## Phase 6 — VERIFY with a screenshot

Compare against the original page, side by side, at the **same window size**.

- Check colours with a picker, not by eye.
- Check every hex from Phase 2 actually landed.
- Check spacing and px from the spec.

**This phase has a procedure and it is not optional.** `21-visual-parity-verification.md` is
the instrument: render with `render/native/build/drive.exe`, capture the reference with
`tools/capture-ref.ps1` at a **recorded** virtual-time budget, swap the raw, and diff. Three
things will otherwise make your number wrong rather than your port:

1. **Swap the raw first.** The frame dump is B,G,R,A (`render/native/drive.nim:191-193`) and no
   diff tool swaps for you (`tools/pngdiff.mjs:100-103`, `tools/refdiff.mjs:90-94`). Measured
   on one port: **91.45% unswapped vs 72.83% swapped.**
2. **Match the clock.** Two headless captures of the same page at the same nominal 800 ms
   budget differ from each other by **2.13%** — that is the instrument's noise floor.
3. **Trust `differing pixels` / `mean |delta|`**, not `pngdiff`'s band map, which is gated at
   `pngdiff.mjs:133` and reads artificially low. Localise with `tools/refdiff.mjs`.

> "I looked at it and it looks right" is not a done test.

---

## Phase 7 — ITERATE on the diff

Work the difference list. Fix, re-screenshot, re-compare. Repeat until the diff is either empty or
each remaining item is a written GAP.

Then the interaction pass — Phase 5 step 3 is not done until you have actually clicked, typed,
scrolled, and hovered the thing.

**Done test:** every remaining difference is either fixed or written down in PORT-NOTES.md with the
reason. PORT-NOTES.md ends with a short, honest **"matches / differs / why"** (process.md §5).

---

## Phase 8 — Clean up before committing

```bash
git status   # and READ it — hard rule 1
```

Remove: generated `.wasm`, `panicoverride.nim`, `nimcache*` directories, `minilibc.o`, `*.bak`.
Hard rule 1: never commit `.wasm`, `.exe`, `.dll`, `third_party/`, `vendor/`, or anything with keys.

**Done test:** `git status` shows only source, spec files and curated screenshots.

---

## The decision rule: canvas vs node tree

> **Prefer a canvas for anything procedural. Use a node tree for anything with text, focus,
> scrolling or events.**

**Reach for canvas when:**

- the element is **procedural** — drawn by code, not authored in HTML;
- there are **many similar things** — quality.md rule 13: "Many similar 2D/3D things: one canvas
  draw list, one layer, or one instanced mesh — **never a node each**";
- it is **geometry** — charts, grids, plots, particles, connectors, waveforms;
- it is an **accumulating drawing** — quality.md rule 14: "Accumulating drawings (strokes, trails):
  draw into a layer once, don't replay history every frame."

**Reach for a node tree when:**

- the element **contains text** that must be selectable, searchable or accessible;
- it needs **focus** or **keyboard** interaction (inputs, buttons, Tab order);
- it needs **scrolling** — a scroll container is a node, not a canvas;
- it needs **layout** — flexbox/grid positioning is free in a tree and hand-rolled in a canvas;
- there are only a **handful** of them (≲20). A node per element is fine at that scale;
- it must be **individually addressable** by an AI edit or an accessibility reader.

**The trap:** the source HTML is DOM, so a literal port produces a node per element — and a page
that is visually one canvas becomes 2000 nodes and a slideshow. That is anti-pattern #1 below.

---

## Anti-patterns

### 1. Porting the DOM literally when the page is mostly one canvas

The single most common mistake. If the original is "a `<canvas>` plus a thin DOM chrome", the
faithful port is "a canvas plus the same thin chrome". Translating the canvas's internal drawing
into 2000 nodes is not a port — it is a rewrite that also loses the animation.

**Tell:** you are writing a node inside a loop that draws something repeated.
**Fix:** one canvas draw list, one layer, one node (`quality.md` rule 13).

### 2. Ignoring z-order

Painter's order in a DOM is document order. In Yantra, later nodes draw over earlier ones — but
only if you do not reorder the tree for convenience. Sorting the tree to group "all the panels
together", or appending a node from a late event handler, silently moves it to the top and puts it
in front of things it should be behind.

**Tell:** a screenshot diff where an overlay is missing or an element is on top that should not be.
**Fix:** build in paint order, top-most last. Never reorder after the fact.

### 3. Forgetting the wasm sandbox has no filesystem, no DOM, no network

The app module is a sandboxed wasm blob with **no libc beyond `sdk/minilibc`**. There is:

- **no filesystem** — `readFile` fails at C-compile time with `fatal error: 'errno.h' file not
  found` (measured — see 17-pitfalls §3). Assets are declared to the SDK
  (`image(col, "logo.png")`, `model`) and the host resolves them from the app's folder;
- **no DOM** — there is nothing to query, append or style. The UI tree you build *is* the DOM;
- **no network** by default — a fetch must be declared on the app's window (`net = "api.x.com"`)
  and goes through the SDK (`fetch(url)`, `.json(T)`, `socket(url, onMessage)`), https only;
- **no OS** — `getCurrentDir` and friends are undeclared identifiers;
- **no JS runtime** — logic is Nim, compiled in.

Translating a `fetch` as "read a JSON file" is the usual way this bites.

### 4. Inventing an API instead of checking

> "Every prop and word you use must exist: props are listed in `protocol/props.md` (generated,
> complete), SDK procs in `sdk/` (grep them)."
> — `docs/agent-guide/README.md` rule 5

A made-up prop is usually a compile error (good), but a made-up **proc with a plausible name** that
happens to exist with different semantics is worse. Grep before you use.

### 5. Silently dropping what you could not build

The GAP that was never written down. It reads as "done" and it is a rejection.
(`README.md` rule 4: never fake a feature. quality.md rule 22: "No TODOs left behind: write gaps
in PORT-NOTES.md instead.")

### 6. Wrapping an engine bug instead of reporting it

> "If something in Yantra looks broken (not missing — broken), write a minimal repro in PORT-NOTES.md
> under 'Engine bugs' and work around it; don't bend the port to hide it."
> — process.md §3

Also quality.md rule 19: engine problems go in `ENGINE-ISSUES.md` in the app folder with what you
did, what you expected, what happened, and a 10-line repro.

### 7. Big apps in one file

> "Keep the original's module structure: one Nim file per JS module, `include`d or imported from
> `app.nim` (same folder), so reviewers can diff them side by side." — process.md §4

And quality.md rule 1: one file per area, no file over ~400 lines, no proc over ~40 lines.