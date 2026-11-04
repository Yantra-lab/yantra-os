---
name: web-artifacts-builder
description: Suite of tools for building elaborate, multi-component Yantra apps as a self-contained deliverable — one .nim source plus its asset folder, built with tools/build-wasm.sh and bundled for handoff. Use for complex apps needing state management, routing, or a composed widget set — not for a quick single-file sketch. Every API and command here was read from the repo.
license: Translated from Anthropic's `web-artifacts-builder` skill. Original: https://github.com/anthropics/skills/tree/main/skills/web-artifacts-builder
---

# Yantra Artifact Builder

The original builds a React + TypeScript + Vite + Tailwind + shadcn/ui project and bundles it into
**one self-contained HTML file** the user can open.

Yantra's equivalent is closer to what Yantra already is: **one `.nim` file that does
`import yantra`, compiled to a sandboxed WebAssembly module, plus the asset folder it loads at
runtime.** The pipeline, the anti-slop design rules, the "test late, not upfront" advice and the
bundling discipline all carry over. The toolchain does not: there is no npm, no bundler, no
`.parcelrc`, and no inlining step.

## What Yantra's stack actually is

| Original | Yantra |
|---|---|
| React 18 + TypeScript | Nim (`import yantra`) |
| Vite / Parcel bundler | `tools/build-wasm.sh` (Nim → `wasm32-unknown-unknown`, clang, `-nostdlib`) |
| Tailwind CSS 3.4 + theming | props on nodes: `fill`, `radius`, `pad`, `fontSize`, `shadow`, `theme`, plus `style(...)` + `use = …` |
| shadcn/ui components | the node kinds in `reference/03-node-and-prop-reference.md` (48 kinds) + `{.component.}` procs for your own |
| path aliases `@/` | Nim modules; `import` what you wrote |
| `bundle.html` (everything inlined) | `app.wasm` + an assets folder next to it |

**Self-contained means:** the wasm module plus every file it references. Not a package manager,
not a CDN, not a font URL.

---

## The five steps

### Step 1 — Start from a compiling app, not an empty folder

The nearest thing to `init-artifact.sh` is an example that already builds. Copy one:

```bash
cp examples/hello.nim   apps/<your-app>/app.nim
bash tools/build-wasm.sh apps/<your-app>/app.nim apps/<your-app>/app.wasm
```

`examples/` is the contract: **every `.nim` in it compiles.** `skills/yantra/examples/hello_app.nim`
is the whole language in 17 lines — a window, a tree, state, an event, and text that recomputes
itself:

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

That gets you a green build in one command, which is what "fully configured project" means here.

### Step 2 — Develop the artifact

Edit the generated file. The routing table for *how* to write a piece of UI:

| You want to… | Do this |
|---|---|
| declare a UI tree, bind state, react to events | the block DSL above |
| reach the node itself (measure, animate, imperative handler) | the imperative style — `examples/imperative_app.nim` |
| draw shapes, paths, text, images into a bitmap | a **`canvas`** node + the `Draw` builder |
| accumulate strokes / animate frames | **`newLayer`** + `layer.draw(...)`, or `onFrame` |
| reuse a chunk of UI | `proc … {.component.}` + `slot()` |
| style many nodes the same | `style(fill = …, radius = 12)` applied with `use = …` |
| repeat over data | `for x in items.keyed(x.id):` (+ `lazy` for long lists) |
| toggle UI on a condition | `if` / `case` directly in the block |
| multi-view navigation | `newRouter("/")` with `r.push`, `r.current` |
| fetch data | `fetchThen` / `fetch` / `fetchWhen` + `app(…, net = "api.example.com")` |

**Never invent an API.** Every node kind and prop is in
`reference/03-node-and-prop-reference.md`. If it is not there, it does not exist — and before you
assume it is missing, read `reference/16-engine-limits-and-workarounds.md`, which lists what is
*not supported yet* **and the exact workaround for each**. That chapter is 74 KB of measured
limits; it will save you from re-deriving a trap that already cost someone a session.

### Step 3 — "Bundle": the build is the bundle

```bash
bash tools/build-wasm.sh apps/<your-app>/app.nim apps/<your-app>/app.wasm
bash tools/build-wasm.sh apps/<your-app>/app.nim apps/<your-app>/app.wasm --release
```

That is the whole bundling step. There is nothing to inline because there is nothing external:
the module is freestanding wasm32, linked against a small **mini-libc** in `sdk/minilibc`, and it
has no OS, no filesystem and no network of its own.

Flags:

- `--release` — `-d:release`, `--opt:speed`, `clang -O3`, then `wasm-opt -Oz --strip-debug` if
  `wasm-opt` is on `PATH`. The script prints the final size and, if `wasm-opt` fails or times out,
  says so explicitly and **keeps the unoptimised module** rather than pretending.
- `--opt` — optimise without `-d:release`.
- `--no-libc` — pure-computation modules; skips mini-libc entirely so you don't inherit an unused
  `yantra_log` import (~18 KB) just by linking the library.

**Requirements:** the file must do `import yantra`. The script puts `sdk/` on the search path and
copies `panicoverride.nim` next to your source if it is missing.

### Step 4 — Hand it over

The deliverable is:

```
apps/<your-app>/
├── app.nim          # the whole source
├── app.wasm         # the build product
└── assets/          # images, wav/mp3/flac, glb, pdf — whatever the app loads
```

Point the user at the folder. To look at it:

```bash
render/native/build/desktop/yantra_run.exe apps/<your-app>/app.wasm
```

**Assets are relative paths resolved by the host next to the wasm.** Keep them in the app folder.
An asset that is not there is the same class of bug as a missing import: it fails quietly at
runtime, not at build time.

### Step 5 — Testing / visualising (optional — and deliberately last)

Same advice as the original, and for the same reason: **testing up front adds latency between the
request and the moment the user can see the artifact.** Present it first; test afterwards if asked
or if something looks wrong.

When you do test, use the **`yantra-testing`** skill (`translated-skills/webapp-testing/SKILL.md`)
— it is the Yantra version of the Playwright loop:

```bash
bash tools/build-wasm.sh apps/<your-app>/app.nim apps/<your-app>/app.wasm
node examples/verify_hello.mjs apps/<your-app>/app.wasm      # structural: the node tree
render/native/build/mpdrive.exe apps/<your-app>/app.wasm out.raw 1280 800 1 "wait:6"   # pixels
```

---

## Design & style guidelines

VERY IMPORTANT: to avoid what is often called "AI slop", avoid excessive centred layouts, uniform
rounded corners, purple gradients, and defaulting to one sans-serif at one size.

Yantra-specific reads on that:

- **Varied geometry.** `radius` is a prop per node, so a card grid where every panel has the same
  radius is a choice, not a limitation. Mix `radius = 0`, small radii, and pills deliberately.
- **One accent colour, used sparingly.** `fill = 0xRRGGBB` with `opacity` for tints. The colour
  model, gradients and effects are in `reference/07-color-gradients-and-effects.md`.
- **Type hierarchy over decoration.** `fontSize`, `font` (families incl. `mono`), `fontWeight`,
  `italic`, `lineHeight`, `maxLines`. A page of equal-size text reads as generated; a page with a
  clear scale reads as designed.
- **Depth is real and cheap.** `shadow = shadow(x = 0, y = 6, blur = 18, color = …)`,
  `blur`, `backdropBlur` (frosted glass), `blend`. Do not fake depth with borders everywhere.
- **Fill the canvas with something procedural.** An HTML page that is mostly one `<canvas>` becomes
  one Yantra `canvas` node and your own drawing code — not 300 nodes. Charts, brush strokes,
  molecules, sparklines: `canvas` + `Draw`.

## What does **not** apply

| Original step/idea | Yantra reality |
|---|---|
| `npm run dev` dev server | None. The build is a compiler invocation; `yantra_run.exe --watch` rebuilds on save while the window stays open (state preserved). |
| Installing `parcel`, `html-inline`, etc. | Nothing to install. `tools/build-wasm.sh` uses the toolchain already under `third_party/`. |
| `@font-face` / Google Fonts | **NOT SUPPORTED YET** — there is no font manager in the renderer. `font` takes a family name the **system** can resolve. A web page's web fonts cannot be honoured. `reference/16` §2.2 C. |
| Tailwind class names / CSS specificity | No CSS engine. Props only. `style(...)` + `use = …` is the reuse mechanism; call-site props written after `use` win. |
| shadcn/ui component library | Not present. Build reusable pieces as `{.component.}` procs. |
| `index.html` requirement | None. The module entry points are `yantra_main` and `yantra_dispatch`. |
| Runtime `fetch` to a CDN | Outbound only, https only, and **only to hosts the window lists**: `app("Weather", net = "api.example.com")`. Plain http is allowed only to this machine. Redirects are never followed. See `sdk/core/net.nim`. |
| `<iframe>` of another site | **NOT SUPPORTED YET.** `appview "other.wasm"` embeds a **Yantra app**, not a website; a native WebView is planned but absent. `reference/16` §2.11 B. |
| 0x00RRGGBB meaning transparent | **NOT SUPPORTED YET** — it reads as **opaque**. Use `opacity = 0` on the node. `reference/16` §1. |
| Percentages for width/height | **Not supported.** `width`/`height` are px. Compute from `sized` or let `grow` do it. `reference/16` §2.5 B. |
| `float64` arithmetic | **BROKEN at wasm32 — silently wrong, not a link error.** Stay in `float32`. `reference/16` §3.3. |

## Reference

- Node kinds and props: `reference/03-node-and-prop-reference.md` (all 48 kinds, all 265 props).
- What the renderer cannot do yet: `reference/16-engine-limits-and-workarounds.md`.
- Porting HTML/CSS/JS: `reference/15a-html-css-mapping.md`.
- The compiler errors you are about to hit: `reference/17-pitfalls.md` *(routed from
  `reference/00-INDEX.md`; check the folder — not every routed chapter exists on disk yet)*.
- Examples that compile: `examples/`, `skills/yantra/examples/`.
