---
name: webapp-testing
description: Toolkit for interacting with and testing local Yantra apps without a browser. Covers building an app to WebAssembly, running it under the native runner, driving synthetic pointer/keyboard input, and dumping the framebuffer to a PNG. Use when asked to verify that a Yantra app renders, to click/type/screenshot a Yantra app, to debug why a button "does nothing", to capture a frame for visual review, or to check a UI change without a human in the loop. Every command here was read from the repo, not remembered.
license: Translated from Anthropic's `webapp-testing` skill. Original: https://github.com/anthropics/skills/tree/main/skills/webapp-testing
---

# Yantra App Testing

**There is no browser.** Yantra apps are `.nim` files compiled to sandboxed WebAssembly and
drawn by a native SDL3 + Skia + Yoga host. So there is no DOM, no Playwright, no devtools
protocol, no `networkidle`, and no `page.locator(...)`.

The Yantra equivalent of "open a browser and click the button" is:

> **build the wasm → hand it to a scripted-input driver → dump the framebuffer → read the pixels.**

That loop is not a metaphor. `render/native/drive.nim` exists on disk precisely because unit
tests proved miniPaint's algorithms but not their wiring: a whole family of tools passed every
test while being unreachable in the real app. The driver's own header comment says a harness
that only calls procs **cannot catch that class of bug**. So drive the real pointer pipeline.

---

## Helper tooling available (treat as black boxes)

| Tool | What it is |
|---|---|
| `tools/build-wasm.sh` | `<src.nim> <out.wasm> [--release\|--opt\|--no-libc]` — Nim → wasm32 |
| `render/native/build/desktop/yantra_run.exe` | runs an app in a real window (`--watch` rebuilds on save) |
| `render/native/build/mpdrive.exe` | **the scripted-input driver**: runs an app, applies synthetic input, writes a raw frame dump |
| `render/native/shot.nim` | source of a "first frame" shooter: `shot <wasm> <out.raw> <w> <h> <scale> [demo]` → BGRA dump. A trailing `demo` word types into the first `input` and ticks the first `checkbox` — a realistic state for a gallery shot. **No `shot.exe` is checked in**; build it from this source. |
| `render/native/drive.nim` | source of `mpdrive.exe` — the authoritative verb grammar |
| `render/native/run_tests.sh` | the renderer test suite; builds and runs `t_*.nim` |
| `examples/verify_*.mjs` + `examples/protocol.mjs` | **mock-engine** verification: run a wasm against a fake host and assert the node tree |
| `scratch/mprun2.py`, `scratch/fbread.py`, `scratch/mppng.py` | Python harness: run the driver, read the framebuffer, save a PNG |

**Run the helper scripts as black boxes.** Read their `--help` / docstring first. They are large
and reading them into context pollutes it — `scratch/mprun2.py` and `scratch/fbread.py` exist so
you never have to re-derive the DLL `PATH`, the raw-format details, or the verb grammar.

---

## The verification loop (this is the whole method)

### 1. Build — the gate is exit 0, not "it looked fine before"

```bash
bash tools/build-wasm.sh path/to/app.nim path/to/app.wasm            # debug
bash tools/build-wasm.sh path/to/app.nim path/to/app.wasm --release  # -d:release + wasm-opt -Oz
```

Never trust a prebuilt `*.wasm` (`AGENTS.md` rule 2 — a stale `hello.wasm` once hid an SDK that
did not compile). Rebuild before you claim anything works.

### 2. Structural check — the node tree, without a renderer

This is the closest thing to "inspect the DOM", and it is fast and exact. `examples/verify_*.mjs`
instantiates the wasm with a **mock engine** that records every host call, then asserts on the
resulting tree.

```bash
node examples/verify_hello.mjs examples/hello.wasm
```

It prints every node it received, then checks structure and props:

```
  [0] kind=0 children=[1] props={"0":"Hello, Yantra","3":800,"4":600,"6":3088670}
OK   node count: got 7, want 7
OK   root is a window: got 0, want 0
...
=== 19/19 checks passed ===
```

It also fires an event **back into** the sandbox (`inst.exports.yantra_dispatch(handler)`) to
prove the callback path works in both directions, and it fails on any **unexpected import**
("no unexpected imports"), which catches an app that quietly started depending on something.

`examples/protocol.mjs` is the generated wire-protocol table: `K` (node kinds, 0..47),
`P` (props, 0..264), `E` (events, 0..33). Import `K` and `P` in your own verifier rather than
hardcoding numbers:

```js
import { K as KIND, P, E } from './protocol.mjs';
check('button kind', nodes[4].kind, KIND.BUTTON);
```

This is the right first check after every build: it proves the app compiled, ran, built the tree
you intended, and has no stray host dependency.

### 3. Visual + interactive check — drive the real app and read the pixels

```bash
render/native/build/mpdrive.exe <app.wasm> out.raw <W> <H> <SCALE> "<verb;verb;verb>"
```

The 5th argument is **scale**, not frames. For a 1280×800 app at native size pass `1`.

Output is a **headerless raw BGRA dump** of `W*SCALE × H*SCALE` pixels, 4 bytes per pixel.

#### THE SEPARATOR IS `;` — NOT `,`

This is the single fact that costs the most time. A verb's own arguments contain commas
(`click:400,400`), so splitting the verb string on commas tears a verb in half. `nums()` then
drops the unparsable tokens and **the verb silently does nothing** — no error, no stderr, no
trap. Arity is checked, not enforced; unknown verb names hit `else: discard`. Both failure modes
are silent.

```
WRONG:  mpdrive.exe app.wasm out.raw 1280 800 1 "wait:4,click:400,400"
RIGHT:  mpdrive.exe app.wasm out.raw 1280 800 1 "wait:4;click:400,400"
```

#### Verb list — complete, verbatim from the `case name` block in `render/native/drive.nim`

| Verb | Args | Effect |
|---|---|---|
| `boxes` | — | stderr: `box <id> kind=<k> x= y= w= h=` for every laid-out node — **ground truth, no input needed** |
| `crash` | — | stderr: `crashed=[..] dirty=..` + crash body, or `crash: NONE` |
| `handlers` | — | stderr: `handler node=<id> event=<ev> h=<h>` for events 20/21/22/1 |
| `probe` | — | hit-tests `pointerDown` at x=34, y ∈ {0,15,29,30,31,44}; prints `pressed` / `scrollY` |
| `click` | `X,Y` | `pointerDown` + `pointerUp`; logs `click X,Y hit=<node> kind=<k>` |
| `down` | `X,Y` | `pointerDown` only |
| `up` | `X,Y` | `pointerUp` only; logs `up X,Y hit=<node>` |
| `move` | `X,Y` | `pointerMove` only |
| `drag` | `X1,Y1,X2,Y2` | `down` at A, **8 interpolated moves**, `up` at B — what a real drag looks like |
| `key` | `N` | key **code** N as an int32, not a character (`g`=103, `u`=117, `R`=82, `ESC`=27) |
| `text` | `S` | types the literal string S — quote it: `text:"hello"` |
| `wait` | `N` | N settled frames (each = 5 ticks + `ensureLayout` + paint) |

Coordinates are in the frame's **own pixel space** (already scaled).

#### A real, verified sequence

```
wait:6;drag:400,400,700,400;wait:2;click:640,60;wait:2
```

A final `frame()` is always painted after the verb batch, so input effects show without a trailing
`wait` — **but** the wasm processes queued events only on `tick()`, so keep `wait:2..4` after any
input if anything is animated. Otherwise you screenshot the *previous* state and conclude the click
did nothing.

### 4. Turn the dump into a PNG and *look at it*

"It compiled is not it rendering" (`SKILL.md` rule 2). A prop can exist in the wire protocol and
be ignored by the renderer — only a screenshot catches that.

```python
import sys; sys.path.insert(0, r"C:/Users/Sanskar/DEV/yantra/scratch")
from mprun2 import run, hit, click, drag, wait, key
from mppng import to_png

f, log = run("wait:6;drag:400,400,700,400;wait:2",
             wasm=r"C:/Users/Sanskar/DEV/yantra/apps/minipaint/app.wasm", w=1280, h=800)
to_png(f, r"C:/Users/Sanskar/DEV/yantra/.board/frame.png")   # .board/ — scratch work goes here
```

`run(verbs, ...)` returns `(Frame, log_text)`. `verbs` may be a list; it joins with `;` for you.
`hit(verbs)` is the quick health probe: `{trapped, chrome, canvas, diff, bbox, frame, log}`.

`Frame` (`scratch/fbread.py`) has `.w .h .rgb(x,y) .argb(x,y) .px(x,y) .diff .bbox .data
.is_trapped()`. **There is no `.size` attribute**, and `load(path, w, h)` needs `w` and `h` because
the dump carries no header.

### 5. Or just open it in a window

```bash
render/native/build/desktop/yantra_run.exe app.wasm           # human-in-the-loop
render/native/build/desktop/yantra_run.exe app.wasm --watch   # rebuild+swap on save
```

### A note on stale harness binaries

A screenshot proves what the **harness** drew, not what your app can draw. `shot_excal.exe` on
disk is a prebuilt helper that predates the `V` (SVG path) verb in the Skia shim — it rendered an
SVG cog as empty with no error anywhere, and the wasm was correct. The lesson generalises: when a
shape goes missing, compare the **harness's build time** against the shim's before believing the
shape code (`apps/minipaint/ENGINE-ISSUES.md` §5).

---

## Decision tree: choosing your approach

```
Task → Is the question about the TREE (does it exist, right kinds/props/handlers)?
    ├─ Yes → node examples/verify_<name>.mjs <app.wasm>          (mock engine, exact)
    │
    └─ No (it is about pixels or behaviour) → Does it need input?
          ├─ No  → mpdrive.exe with "wait:N"   (first-frame dump)
          └─ Yes → mpdrive.exe with a `;`-separated verb string
```

Then, always: **read the frame back** (`Frame.rgb`, `.diff`, `.bbox`) and/or **convert to PNG and
look**. `boxes` is the single highest-value verb — it prints what the engine actually laid out, so
"my click did nothing" stops being a mystery and becomes a coordinate you can read off.

---

## Reconnaissance-then-action

Same idea as the original, in Yantra vocabulary. **Never guess a coordinate or a selector.**

1. `boxes` → every node's id, kind, and laid-out rect.
2. `handlers` → which nodes actually have handlers for pointer down/move/up (events 20/21/22).
   A hit test that reports `kind=34` (canvas) proves nothing about whether a handler exists —
   `handlers` prints the registration itself.
3. `click:X,Y` at the coordinate you read in step 1 → the stderr line gives you the **hit node id
   and kind** back.
4. `crash` → did the wasm trap.
5. Read the pixels: probe a point you know should have changed, and check `.diff` / `.bbox`.

## Common pitfalls

❌ **Don't** paint a frame immediately after firing input. The wasm only drains its event queue on
`tick()`, so you screenshot the previous state and every click looks dead. Put `wait:2` after input.
✅ **Do** keep `wait:2..4` after any input verb.

❌ **Don't** split verbs on commas. Use `;`. (See above — the failure is silent.)
✅ **Do** quote the whole verb string, and quote `text:"…"` inside it.

❌ **Don't** treat `rc=0` as proof of health. A trapped run still exits 0. Check
`Frame.is_trapped()` or the crash colour.
✅ **Do** run the `crash` verb.

❌ **Don't** probe for a layout fact with a colour scan. A white-pixel scan for a dropdown
silently measures the canvas instead; a probe at y 0–7 gets painted over by the menu bar.
✅ **Do** encode runtime values as **bar width**, never as colour — colour passes through alpha and
overdraw, geometry cannot be misread. And remember: ink is not the oracle for a layout question
(glyph side bearings end ink ~10px early) — the **hit box** is the oracle, and a click reveals it.

❌ **Don't** walk the repo with `rglob`/`os.walk`. `render/native/build/nimcache` holds thousands of
generated files and the walk times out.
✅ **Do** use a narrow glob, or name the file.

❌ **Don't** hand the driver a **directory** as the output path.
✅ **Do** give it a plain file path (`os.makedirs(outfile)` then reading it raises
`PermissionError`).

❌ **Don't** build the driver with `-d:release` — a release build of `mpdrive.exe` crashes.
✅ **Do** keep debug builds.

**When a measurement contradicts the source, the source wins and the measurement is suspect.**

## Best practices

- **Use the bundled harnesses as black boxes.** `scratch/mprun2.py` already encodes the DLL `PATH`,
  the outfile rules, the verb grammar and the trap heuristic. Import it; do not re-derive it.
- **`PATH` must be set in-process** and `subprocess.run` called **without `env=`** — passing `env=`
  is a known failure mode. `mprun2.setup_path()` does it correctly.
- DLL directories, in order: `render/native/build`; `third_party/skia-build/pkg/mingw-w64-x86_64-skia/mingw64/bin`;
  `third_party/msys64/mingw64/bin`; `libs/nimwasmtime/vendor/wasmtime-v19.0.2-x86_64-windows-c-api/lib`.
- **Encode assertions as bar width / node count / prop value**, not as pixels, wherever the
  question allows. The mock-engine verifier and `boxes` are both exact; pixels are a fallback.
- **Every claim needs a number you measured.** "0 of 1,024,000 pixels differed" is a report; "the
  button seems to work" is not.

## Reference files

- `render/native/drive.nim` — the driver source; its header comment is the verb grammar, read it
  first if this doc ever drifts.
- `scratch/MPRIVER.md` — the authoritative, measured verb grammar, a real verified sequence, the
  health-reference pixel table, and the harness API. **Read this before improvising.**
- `scratch/mprun2.py`, `scratch/fbread.py`, `scratch/mppng.py` — the harness, the framebuffer
  reader, the PNG writer.
- `render/native/run_tests.sh` — the renderer suite; `just test` is the repo gate.
- `skills/yantra/reference/16-engine-limits-and-workarounds.md` — **before you promise anything**:
  what the renderer does not draw, and the exact workaround for each.
- `skills/yantra/examples/` — every `.nim` there compiles; copy from them.
- `skills/yantra/reference/02-language-core.md` — the DSL and events, if you need to know what a
  handler *should* have registered.

### What does **not** apply here

| Playwright concept | Yantra reality |
|---|---|
| `page.goto(url)` / `wait_for_load_state('networkidle')` | There is no page. There is a wasm module the host loads synchronously. The equivalent settle is `wait:N`, where each frame is 5 ticks + layout + paint. |
| `page.locator('button')` / CSS selectors | **NOT SUPPORTED YET** — there is no DOM and no CSS selector engine. Use `boxes` (ids + rects) and `click:X,Y`. `reference/16` §2.7 D/E. |
| `page.content()` / `inspect the DOM` | Use the mock-engine verifier: it prints the exact node tree and props. |
| Console logs | `yantra_log(ptr, len)` is the app's log channel; the mock engine records it, and `handlers`/`crash` are the driver's stderr channel. |
| Multiple servers / ports | **Not applicable.** A Yantra app has no server. Networking is outbound only, through the host's `net` allow-list (`sdk/core/net.nim`). |
| Running in a real browser | **NOT SUPPORTED YET** — file pick is broken on the web target and there is no webview node (`reference/16` §2.11 B, §2.11 A note). The native host is the target. |
