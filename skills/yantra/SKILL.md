---
name: yantra
description: Build native desktop apps and clone web pages pixel-for-pixel in Yantra, a Nim→WebAssembly UI framework rendered by a native SDL3 + Skia host. Use when asked to write a Yantra app, port an HTML file to Yantra, clone/replicate a website or app in Yantra, draw with a 2D canvas, build a 3D scene, synthesise audio, or find out what the Yantra renderer can and cannot draw. Every API here is read from the SDK source; nothing is from memory.
---

# Yantra

## What Yantra is, in five lines

1. A Yantra **app is one `.nim` file** that does `import yantra` and compiles to a small sandboxed WebAssembly module.
2. A **native host** — SDL3 + Skia + Yoga + wasmtime — loads that module, owns the node tree, dispatches events, and draws real native pixels.
3. The app has **no DOM, no CSS engine, no filesystem and no network**. It describes a UI by calling the host across a scalar wire protocol; that is the whole security model.
4. You describe a **node tree** (window → column → row → panel → text/button/canvas/…) and set **props** on it; **Yoga** does flex/grid layout and **Skia** does the drawing.
5. Anything procedural — a brush stroke, a chart, a molecule, a painting — goes in a **canvas** and you draw it yourself; anything structural goes in the node tree.

## Build and run — the exact commands

```bash
# BUILD (measured: ~9 s, exit 0)
bash tools/build-wasm.sh <src.nim> <out.wasm>              # debug
bash tools/build-wasm.sh <src.nim> <out.wasm> --release    # optimised + wasm-opt -Oz
```

Flags: `--release`, `--opt`, `--no-libc` (pure-computation module, no mini-libc).

Run it natively, and screenshot the first frame to check it renders:

```powershell
# a real window, with pointer + keyboard input
render/native/build/desktop/yantra_run.exe <out.wasm>

# headless: render frames through the REAL pointer pipeline and dump pixels
#   drive app.wasm out.raw W H SCALE SCRIPT
#   SCRIPT is SEMICOLON-separated: click:X,Y  drag:X1,Y1,X2,Y2  move:X,Y  key:N  text:S  wait:N
& .\render\native\build\drive.exe .\app.wasm .\out.raw 1280 800 1 "wait:45"
```

**The dump is BGRA, and you must swap it before any diff.**
`render/native/drive.nim:191-193` `copyMem`s a `seq[uint32]` of Skia
`0xAARRGGBB` pixels to disk, so the bytes on disk are **B,G,R,A**, while
`tools/pngdiff.mjs` reads bytes 0,1,2 as R,G,B. Always:

```bash
node tools/rawswap.mjs out.raw out_sw.raw     # once, never twice
node tools/pngdiff.mjs ref.png out_sw.raw 1280 800
```

Measured on one port, same reference, the swap being the only difference:
**91.45% unswapped vs 72.83% swapped.** The unswapped number looks plausible
and is wrong.

Full verification recipes: **`reference/01-build-run-and-verify.md`**.
Pixel parity: **`reference/21-visual-parity-verification.md`**.

## The program shape — a complete, verified, compiling app

This is `examples/hello_app.nim`. It builds clean. It is the whole language: a window, a tree, state, an event, and text that recomputes itself.

```nim
import yantra

app "Hello", width = 420, height = 260, fill = surface, pad = 24:
  var count = state(0)                       # reactive state

  column(spacing = 12, grow = 1):
    text "Clicks: {count}", fontSize = 28, font = mono

    if count > 0:
      text "{count} is a lot", fontSize = 14, fill = muted

    row(spacing = 8):
      button "Click me":
        count += 1
      button "Reset":
        count.set(0)
```

**Read this before you write anything:**

| You want to… | Do this |
|---|---|
| Declare a UI tree, bind state, react to events | the block DSL above — `app "T", width = …:` then an indented block |
| Reach the node itself (measure, animate, imperative handler) | the imperative style — `examples/imperative_app.nim` |
| Draw shapes, paths, text, images into a bitmap | a **`canvas`** node + the `Draw` builder |
| Accumulate strokes / animate frames | **`newLayer`** + `layer.draw(...)`, or `onFrame` |
| Reuse a chunk of UI | a `proc` marked `{.component.}` + `slot()` |
| Style many nodes the same | `style(fill = …, radius = 12)` applied with `use = …` |
| Repeat over data | `for x in items.keyed(x.id):` (+ `lazy` for long lists) |
| Toggle UI on a condition | `if` / `case` directly in the block |

## Where everything is written down

Everything an agent needs is in this folder. Read the chapter, not the guess.
**`reference/00-INDEX.md` is the full routed table** — it has one honest line per
chapter: what it is for, and what you will be able to do afterwards.

| Chapter | Read it when |
|---|---|
| `reference/01-build-run-and-verify.md` | building, running, screenshotting, the test gate |
| `reference/02-language-core.md` | the DSL: `app()`, tree, state, events, control flow |
| `reference/03-node-and-prop-reference.md` | **the lookup table** — every node kind and every prop |
| `reference/05-layout-and-containers.md` | flex, grid, sizing, padding, gap, alignment, sticky, scroll |
| `reference/06-text-and-fonts.md` | type, weights, families, **and where the `y` you pass actually lands** |
| `reference/07-color-gradients-and-effects.md` | colour model, themes, gradients, shadows, blend, opacity |
| `reference/08-images-icons-and-svg.md` | images, `fit`, SVG paths, the icon set |
| `reference/09-canvas-and-draw.md` | the 2D drawing API, layers, and its real limits |
| `reference/10-animation-and-motion.md` | `animate`, `transition`, easings, the frame loop |
| `reference/11-input-pointer-and-keys.md` | pointer, keyboard, focus, drag & drop |
| `reference/12-3d-and-shaders.md` | scene3d, models, instancing, custom shaders, particles |
| `reference/13-audio-video-and-data.md` | synth, WAV assets, video, storage, networking |
| `reference/15a-html-css-mapping.md` | **porting** — every CSS property and DOM/JS API → Yantra |
| `reference/16-engine-limits-and-workarounds.md` | **before you promise anything** — what is NOT SUPPORTED YET |
| `reference/17-pitfalls.md` | measured compiler errors and the exact fix for each |
| `reference/18-porting-process.md` | the step-by-step porting workflow |
| `reference/19-done-checklist.md` | before you say "done" |
| `reference/20-cloning-a-live-website.md` | cloning a site that is not a local HTML file |
| `reference/21-visual-parity-verification.md` | proving a port matches its source, with a number |
| `reference/22-nim-closure-capture.md` | the closure-capture error that hits every drawing-heavy port |
| `reference/23-wasm-import-gate.md` | the app that loads as an empty tree because the host refused an import |
| `reference/24-draw-alpha-ramps.md` | vignettes, glows and fog — how to build a soft alpha ramp |
| `examples/` | two complete apps, both compile; copy from here |
| `translated-skills/` | the design/canvas/testing skills, translated to Yantra |
| `../web-to-yantra/SKILL.md` | **the second skill** — command-by-command HTML/CSS/Canvas2D/SVG/events → Yantra. Read this early for any port. |

There is **no chapter `04` and no `14`/`15`** — the numbering skips them. Do not
go looking; the gaps are not mistakes. There are 22 chapters plus this index.

## The four facts that will bite you if you do not know them

These are the ones that cost real rounds. Each is carried in full, with its
evidence, in the chapter named.

1. **`Draw.text(x, y, …)`'s `y` is the top of the paragraph line box, not the
   baseline.** `libs/nimskia/src/skia_shim.cpp:291` calls
   `p->paint(canvas, x, y)`. The doc comment at `libs/nimskia/src/nimskia.nim:76`
   says "top-left at (x, y)" and is **wrong**. Measured offsets from `y`, in
   units of font size `S` (verified at S=12, 24, 48): cap top `y + 0.375·S`,
   x-height top `y + 0.583·S`, **baseline `y + 1.0833·S`**, descender bottom
   `y + 1.333·S`. So `yantra_y = wantedBaselineY - 1.0833 * size`. This is
   **empirical — default typeface and weight only.** See `06-text-and-fonts.md`.
2. **A `Draw` colour must carry its alpha byte.** `Draw` primitives take
   `argb: uint32` in **AARRGGBB**. A CSS hex pasted straight in (`0xF7F9FB`) has
   alpha `0x00` and draws **fully transparent**. Node colour props are safe —
   `render/native/engine.nim:345-348` promotes a missing alpha byte to `0xFF` —
   but a `Draw` colour gets a bare `paint.setColor` (`skia_shim.cpp:1327`) with
   no rescue. So moving a colour that worked on a node into a `Draw` list makes it
   vanish. Force `0xFF` up front.
3. **`frameDt()` is the live clock; `yantra_get_dt()` is not.** `sdk/ui/input.nim:45`.
   `sdk/core/runtime.nim:75` declares `yantra_get_dt` as an importc whose only
   writer, `setFrameDt` (`host/host.nim:1211`), appears in exactly two files
   repo-wide — `render/render_qml.nim:42` (legacy Qt) and a test. An app animated
   off `yantra_get_dt()` reads 0 and never moves.
4. **`log()` is unobservable** under the headless driver, and one call measured at
   **+15,660 bytes (~7% of a ~215 KB module)**. Instrument by drawing, or by
   reading pixels.

## The three rules that save the most time

1. **Never invent an API.** Every name in this skill was read out of the SDK source. If you need something that is not in `03-node-and-prop-reference.md`, it does not exist — check `16-engine-limits-and-workarounds.md` before assuming it is missing.
2. **It compiling is not it rendering.** A prop can exist in the wire protocol and be ignored by the renderer. Always screenshot and look.
3. **Prefer a canvas for anything procedural.** An HTML page that is mostly one `<canvas>` becomes one Yantra `canvas` node and your own drawing code — not 300 nodes.

## When two chapters disagree

They will, eventually — they are a record of what was true when each was written,
not a manual. Resolve it in this order:

1. **The engine's source beats both.** Open the file (`sdk/`, `host/`, `render/`,
   `libs/nimskia/`) and read it. That is the only authority.
2. **Otherwise: later and more specific wins.**
3. **A `CORRECTED` note supersedes the text above it** in the same chapter.
4. **Measured beats documented.** The text `y` origin is exactly this case.
5. **If no rule covers it, fix the chapter** in the same change as whatever you
   were doing, with the `path:line` or the measurement that settles it.

## Repo rules that apply to you

From `AGENTS.md` — these are not suggestions:

- Never commit `third_party/`, `vendor/`, `*.exe`, `*.dll`, `*.wasm`, or anything with keys.
- Never trust a prebuilt artifact. Rebuild before claiming something works.
- Never weaken, skip or delete a test to make it pass.
- Adding a node kind or a prop = renderer mapping **plus** a `t_*.nim` test, in the same change. The SDK only promises what the renderer draws.
- Report what you measured. A reported failure is fine; a fabricated pass is not.
- Scratch work goes under `.board/`, never into the repo root.

## Keeping this skill current

This folder is a living document and **you are expected to improve it**. After you finish any port or build:

1. If you hit a gap, a workaround or a new engine fact, add it to `16-engine-limits-and-workarounds.md` (or the relevant chapter) **in the same change as the port**.
2. If you found a compiler error or a trap, add the exact error text and fix to `17-pitfalls.md`.
3. If you wrote a snippet worth reusing, add it to `examples/` **and build it** before you commit it.
4. Add a line to `CHANGELOG.md`.
5. Never document an API you did not see in the source, and never leave a `VERIFY IN SOURCE` marker behind — resolve it or delete the claim.