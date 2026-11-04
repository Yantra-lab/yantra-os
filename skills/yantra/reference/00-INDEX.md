# Skills index — read this to find the right file fast

`SKILL.md` is the entry point. This file is the complete routed table.

## How many chapters there are, exactly

**23 files in `reference/`**: this index (`00`) plus **22 chapters**.
There is no chapter `04` and no chapter `14`/`15` — the numbering skips them
deliberately, and chapter `15a` is the CSS-mapping chapter. Do not go looking
for the gaps; they are not mistakes.

Every chapter below is reachable from `skills/README.md` and from `SKILL.md` by
exactly one path. If you are reading a chapter and it tells you to look at
something that is not on this list, that chapter is stale — read the engine
source instead.

---

## Stage 0 — orientation and process (read in this order)

| # | Chapter | What it is for | What you can do afterwards |
|---|---|---|---|
| 01 | [`01-build-run-and-verify.md`](01-build-run-and-verify.md) | The exact build / run / screenshot commands and how to prove a frame is real | Build a module and produce a frame dump you can trust, and know when the dump you are holding is stale |
| 18 | [`18-porting-process.md`](18-porting-process.md) | The step-by-step workflow for turning an HTML file into `app.nim` | Execute a port without inventing an API mid-flight |
| 19 | [`19-done-checklist.md`](19-done-checklist.md) | The gate you must pass before saying "done" | Decide, with boxes ticked, whether a port is finished or merely built |
| 17 | [`17-pitfalls.md`](17-pitfalls.md) | Measured compiler errors and engine traps, each with its exact fix | Recognise a failure you have seen before and fix it instead of re-diagnosing it |
| 16 | [`16-engine-limits-and-workarounds.md`](16-engine-limits-and-workarounds.md) | What the engine genuinely cannot do yet, and the workaround for each | Promise only what the renderer will actually draw |
| 20 | [`20-cloning-a-live-website.md`](20-cloning-a-live-website.md) | Capturing a live site, flattening the cascade, diffing to pixel parity | Clone a URL (not just a local file) and reach a measured parity number |
| 21 | [`21-visual-parity-verification.md`](21-visual-parity-verification.md) | Turning "it looks right" into a number: build the toolchain, render both sides, diff | Prove a port matches its source pixel-by-pixel, and classify a diff as geometry or clock |

## Stage 1 — the language

| # | Chapter | What it is for | What you can do afterwards |
|---|---|---|---|
| 02 | [`02-language-core.md`](02-language-core.md) | `app()`, the node tree, `state`/signals, events, `if`/`for`, components, styles | Write a whole app in the block DSL with reactive state and working handlers |
| 03 | [`03-node-and-prop-reference.md`](03-node-and-prop-reference.md) | The lookup table: every node kind and every prop, with types and defaults | Answer "does this prop exist, and what does it take?" without guessing |

## Stage 2 — the subsystems (read only what your page needs)

| # | Chapter | What it is for | What you can do afterwards |
|---|---|---|---|
| 05 | [`05-layout-and-containers.md`](05-layout-and-containers.md) | column/row/panel/grid/flex/stack, sizing, padding, gap, sticky, scroll, lazy lists | Reproduce a CSS flex/grid layout, including scrolling and long lists |
| 06 | [`06-text-and-fonts.md`](06-text-and-fonts.md) | Typography, families, weights, and **where the `y` you pass actually lands** | Place text where the source page puts it, using the measured offset rather than the documented one |
| 07 | [`07-color-gradients-and-effects.md`](07-color-gradients-and-effects.md) | The colour model, themes, gradients, shadows, blend modes, opacity | Set any colour and know its alpha will actually be visible |
| 08 | [`08-images-icons-and-svg.md`](08-images-icons-and-svg.md) | Images, `fit`, SVG path extraction, the icon set | Get an icon or an SVG illustration onto the screen at the right size |
| 09 | [`09-canvas-and-draw.md`](09-canvas-and-draw.md) | The 2D drawing API, layers, raw pixels — and what `Draw` genuinely cannot do | Draw anything procedural, and know which three primitives you have to compose by hand |
| 24 | [`24-draw-alpha-ramps.md`](24-draw-alpha-ramps.md) | Vignettes, glows and fog: why nested discs go opaque, and why `dst-out` erases the whole canvas | Build a soft alpha ramp that survives compositing — the `X` buffer blit, not stacked discs |
| 10 | [`10-animation-and-motion.md`](10-animation-and-motion.md) | `animate`, `transition`, easings, keyframes, and the frame loop | Animate off the one clock that actually advances (`frameDt()`) |
| 11 | [`11-input-pointer-and-keys.md`](11-input-pointer-and-keys.md) | Pointer coordinates, keyboard, focus, drag and drop | Handle a click, a drag, and a keypress, including hit-testing your own drawn art |
| 12 | [`12-3d-and-shaders.md`](12-3d-and-shaders.md) | `scene3d`, models, instancing, custom shaders, particles | Build a 3D scene that renders in a real window |
| 13 | [`13-audio-video-and-data.md`](13-audio-video-and-data.md) | Synth, WAV assets, video, storage, networking | Add sound, persistence or a network fetch — inside the capability sandbox |

## Stage 3 — porting (the whole job, end to end)

| # | Chapter | What it is for | What you can do afterwards |
|---|---|---|---|
| 15a | [`15a-html-css-mapping.md`](15a-html-css-mapping.md) | Every CSS property and every DOM/JS API → Yantra, or "not supported: do X" | Translate a stylesheet into Yantra props mechanically, and know which CSS you must rebuild by hand |
| 22 | [`22-nim-closure-capture.md`](22-nim-closure-capture.md) | The Nim closure-capture error that hits every port that writes drawing code as nested closures | Fix `'x' is of type <Draw> which cannot be captured` instead of rewriting your architecture around it |
| 23 | [`23-wasm-import-gate.md`](23-wasm-import-gate.md) | The host refuses a module declaring an import it does not provide — and this happens **before** `yantra_main` runs | Diagnose an app that loads as an empty tree, and keep it instantiable |

## Other material in this skill

| Path | What it is |
|---|---|
| `../SKILL.md` | The entry point: what Yantra is, the build command, the program shape, the top rules |
| `../examples/` | Two complete apps. Both compile. Copy from them. |
| `../translated-skills/` | Anthropic's official Agent Skills, translated to Yantra |
| `../../web-to-yantra/SKILL.md` | **A second skill**: the command-by-command port of HTML/CSS/Canvas2D/SVG/Events into Yantra, worked end-to-end on `apps/typewriter`. Start here for a port; come back here for the API detail. |
| `../CHANGELOG.md` | What changed and when — this folder is maintained |

---

## The rules that decide a disagreement

1. **The engine's source beats both chapters.** If `SKILL.md` and a chapter
   disagree, open the file (`sdk/`, `host/`, `render/`, `libs/nimskia/`) and read
   it. That is the only authority.
2. **Otherwise: later and more specific wins.** A chapter scoped to one
   subsystem beats a general one. `24-draw-alpha-ramps.md` beats `09-canvas-and-draw.md`
   on alpha compositing; `15a` beats `05`/`07` on what a CSS property maps to.
3. **A claim marked `CORRECTED` supersedes the text above it in the same chapter.**
   The old claim is kept visible on purpose — so you can see what changed and why,
   and so nobody re-learns the wrong rule from an earlier session.
4. **Measured beats documented.** Where a number was measured against the real
   renderer, the measurement wins even when a doc comment says otherwise. This is
   the single most important rule in this folder: see `06-text-and-fonts.md`.
5. **If it is not here, it does not exist.** Never invent an API. If you need
   something that is not in `03-node-and-prop-reference.md`, check
   `16-engine-limits-and-workarounds.md` before assuming it is missing.

Nothing in this folder is written from memory. Every API was read out of the SDK
source, and every code block was compiled. But where a fact was **measured**, the
chapter says so and gives the numbers it was measured from — and where a doc
comment in the engine contradicts the measurement, the measurement is what you
use and the contradiction is written down.
