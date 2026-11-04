---
name: web-to-yantra
description: Port an existing web page to Yantra — the HTML/CSS/Canvas2D/SVG to Nim-to-Wasm mapping, command by command. Use when asked to port, clone, translate or rebuild an HTML file, a Canvas2D drawing app, an inline-SVG illustration or a DOM-driven page as a Yantra app, or to find out what happens to gradients, box-shadows, blend modes, filters, keydown handlers, requestAnimationFrame and localStorage in Yantra. Worked example: apps/typewriter/app.nim, a 1:1 port of a CSS/SVG/Canvas page rebuilt as one Skia Draw command list.
---

# Web → Yantra

You are holding an HTML file. It renders in a browser. Yantra has **no DOM, no CSS
engine, no SVG element and no Canvas2D context** — there is no `getContext('2d')`
anywhere in the SDK. So a port is never a transliteration; it is a decision about
*which of Yantra's three layers* each piece of the page belongs to.

Everything here was read out of the SDK source, or measured by compiling a probe
with `tools/build-wasm.sh`. The measured error texts are quoted verbatim.

## The worked example everything points at

**`apps/typewriter/app.nim`** (1033 lines) is a 1:1 port of
`apps/typewriter/029-typewriter-letters.html` — a page that is a stack of
absolutely-positioned DOM layers over **two procedural `<canvas>` elements**, an
**inline-SVG** Marlowe 44 typewriter in three-quarter view, and a **runtime-built
45-key keyboard** that is drawn, hit-tested and pressed.

The port's own header comment (`app.nim:1-14`) is the thesis of this skill:

> Yantra has no DOM and no SVG, so the whole scene is rebuilt as ONE `Draw` command
> list on a single canvas node, with real `button` nodes only for the header controls
> so they keep native hit-testing, focus and the keyboard.

The one-line summary of what the source became:

| In the HTML | In `app.nim` |
|---|---|
| `<div class="desk">` + a 1280×816 procedural canvas | `deskLayer = newLayer(...)`, painted once in `paintDesk()` (`app.nim:122`) |
| the second canvas (paper + fibres + watermark) | `paperLayer`, painted once per sheet in `paintPaper()` (`app.nim:231`) |
| the inline `<svg>` Marlowe | `const P_SIDE = "M900 16 L936 30 …"` + `d.svgPath(P_SIDE, …)` (`app.nim:401-406, 458`) |
| `<linearGradient>` on the chrome/enamel/platen | `gradShape()` — three flat fills of the same path (`app.nim:391`) |
| 45 absolutely-positioned `.key` divs with `onclick` | `ROWS` / `ROWKEYS` consts drawn by `drawKeys()` (`app.nim:513-519`) and hit-tested by `hitKey()` (`app.nim:857`) |
| `window.addEventListener('keydown', …)` | `page.addHandler(evKey, proc() = …)` (`app.nim:1019`) |
| `requestAnimationFrame(loop)` | `scene.addHandler(evFrame, proc() = tick())` (`app.nim:1030`) |
| `localStorage.setItem('letter', …)` | `persistent("", "marlowe44.letter.v1")` (`app.nim:693`) |
| the header `<button>`s | **real `button` nodes**, so focus, hover and hit-testing stay native (`app.nim:967-987`) |

That last row is the whole routing lesson: the page's *chrome* stayed a node tree;
the page's *illustration* became a Draw list.

## The three-layer mental model

Everything you port lands in exactly one of three layers. Getting this wrong is the
single biggest source of wasted ports, so decide per element, not per page.

| Layer | What it owns | Built with | Gets hit-testing / focus for free? |
|---|---|---|---|
| **1. Node tree** | Layout, controls, anything the page *arranges*: headers, buttons, panels, lists, scrolling columns, text | `window/row/column/panel/button/text/…` + props; Yoga lays it out (`sdk/yantra.nim:169`, `sdk/core/runtime.nim:132-170`) | **Yes.** The engine owns the tree, so `button` works, `onClick` fires, tab order exists, `hover:`/`pressed:`/`focused:` props light up |
| **2. `Draw`** | Pixels: illustrations, procedural texture, charts, plots, anything *procedural or infinite* | `Draw()` builder (`sdk/ui/paint.nim:10-82`) attached with `node.set(pDraw, cmds)` (`sdk/core/wire.nim:222`) | **No.** A canvas is a bitmap and nothing more. You must hit-test it yourself |
| **3. Native nodes inside a page** | The parts of a drawn scene that must still *be* controls | layer 1 nodes positioned over/around the canvas | **Yes**, and it is usually the cheapest answer |

Layer 3 is the one people forget. The typewriter header is not painted: it is five
real `button` nodes in a `row` (`app.nim:951-987`). If you can keep something a node,
you get focus, keyboard, hover and hit-testing for free instead of writing it.

### The routing decision, in one procedure

```
For each element / visual in the HTML page:

  Is it layout the page arranges (a bar, a form, a card, a list)?
    → LAYER 1. node tree. Node kind from the CSS (see 15a §0 "Node-kind ladder").

  Is it an <img>/<svg> illustration or a canvas painting?
    → LAYER 2. Draw.
        - inline <svg> path data?  → const string + d.svgPath(…)   (verbatim; see ch. 2)
        - a canvas already?       → Draw() builder, one proc per paint
        - repeated every frame?   → evFrame + repaint, or a Layer you keep drawing into

  Is it something the user must click, type into or tab to?
    → LAYER 3. Make it a real node, even if the pixels around it are Draw.
        - a whole drawn widget (a keyboard, a dial)?  draw it AND hit-test it by hand
          (ch. 4 §6), or overlay one transparent node per key.
```

**When in doubt, count.** An HTML page of 300 presentational `<div>`s over one
`<canvas>` becomes **one** `canvas` node, not 300 nodes. That is rule 3 in
`skills/yantra/SKILL.md`.

## Concept map — web → Yantra

Full detail lives in the three chapters at the bottom of this file. This is the
routing table.

| Web concept | Yantra equivalent | Where it is written |
|---|---|---|
| `<canvas>` + `getContext('2d')` | `canvas(page, w, h)` node + a `Draw` command string on `pDraw` | ch. 2 |
| `ctx.fillRect / strokeRect` | `d.rect(x, y, w, h, argb, radius)` | ch. 2 |
| `ctx.arc` / `ctx.ellipse` | `d.arcTo(cx, cy, r, startDeg, sweepDeg)` / `d.circle` / an `ellipsePath()` string fed to `svgPath` | ch. 2 |
| `ctx.moveTo/lineTo` + `stroke` | `d.moveTo/lineTo/…/stroke(argb, width)` — **one width per path** | ch. 2 |
| `ctx.quadraticCurveTo` | `d.quadTo(cx, cy, x, y)` | ch. 2 |
| `ctx.bezierCurveTo` | `d.curveTo(cx1, cy1, cx2, cy2, x, y)` | ch. 2 |
| `ctx.ellipse` (rx ≠ ry) | no primitive — build path data and use `d.svgPath` | ch. 2 |
| inline `<svg><path d="…">` | **the `d` string transcribes verbatim** into `d.svgPath(data, x, y, scale, argb, strokeWidth)` | ch. 2 |
| `<svg><circle>` / `<rect>` / `<polygon>` | convert to path data (`ellipsePath()` in `app.nim:385` is the worked helper) | ch. 2 |
| `new Path2D(p)` | a `const`/module-level `string` of path data | ch. 2 |
| `ctx.fillText(x, y, …)` | `d.text(x, y − 1.0833·size, size, argb, s, weight)` — **the `y` is the line-box top, not the baseline** | ch. 2 §1, see below |
| `ctx.measureText(s)` | **no equivalent in the SDK.** `Draw.text` returns `Draw` and nothing else (`paint.nim:63`) and has no `align`. Estimate | ch. 2 §1 |
| `ctx.globalAlpha = a` | `d.alpha(a)` (scoped) **or** bake it into the colour's alpha byte | ch. 2, ch. 3 |
| `rgba(…, 0.4)` | one `uint32` `0xAARRGGBB` — `0x66FF0000'u32` is 40 % red | ch. 3 |
| `ctx.globalCompositeOperation = 'multiply'` | `d.blend(bMultiply)` | ch. 2 |
| `… = 'destination-out'` | `d.blend(eraser)` — `eraser` is `const eraser* = bDstOut` (`paint.nim:21`) | ch. 2 |
| `ctx.filter = 'blur(4px)'` | no per-command filter: draw into a `newLayer`, then `layer.filter(blur, 4)` | ch. 2, ch. 3 |
| `ctx.createLinearGradient` / `createRadialGradient` | **NO EQUIVALENT IN `Draw`.** Banded fills / concentric rings | ch. 2 §7, ch. 3 §1 |
| `ctx.drawImage` | `d.image(x, y, w, h, "file.png")`, or `d.layer(l, x, y, w, h)` for a bitmap you drew | ch. 2 |
| `getImageData` / `putImageData` | `layer.read(x, y, w, h)` / `layer.write(x, y, w, h, rgba)`, or `d.pixels(buf, pw, ph, …)` | ch. 2 |
| `background: linear-gradient(a, b)` on an **element** | `panel(fill = linear(a, b, 90))` — two stops, linear only | ch. 3 §1 |
| `box-shadow` on an **element** | `shadow = shadow(x, y, blur, color)` | ch. 3 §2 |
| `box-shadow` inside a **`Draw`** | no primitive: draw the shape again, offset, blurred by re-drawing it as stacked translucent copies | ch. 3 §2 |
| `border-radius` | `node.radius(12)`; in Draw, `d.rect(…, radius)` | ch. 3 §3 |
| `opacity: .5` | `node.opacity(0.5)`; in Draw, `d.alpha(0.5)` or an alpha byte | ch. 3 §4 |
| `mix-blend-mode` | `d.blend(bMultiply)` etc. — all 29 Skia modes are in `Blend` (`paint.nim:14-17`) | ch. 3 §5 |
| `filter: blur() saturate()` on an element | `blur`, `saturate`, `brightness`, `contrast` props on the node; `layer.filter(kind, amount)` on a bitmap | ch. 3 §6 |
| `el.addEventListener('keydown', e)` | `node.addHandler(evKey, proc() = let k = lastKey() … handled())` | ch. 4 §1 |
| `'click'` / `'pointerdown'` | `addHandler(evClick, …)` + `pointerPos()` (canvas-local px) | ch. 4 §2 |
| `requestAnimationFrame(loop)` | `node.addHandler(evFrame, …)` + `frameDt()` **seconds** | ch. 4 §3 |
| `setTimeout(f, 250)` | `afterMs(250, proc() = …)` or `after 250.ms: …` (`sdk/ui/motion.nim:74-81`) | ch. 4 §4 |
| `localStorage` | `persistent[T](initial, "key")` → `.get()` / `.set(v)` (`sdk/core/persist.nim:34`) | ch. 4 §5 |
| `element.animate([...])` / CSS `@keyframes` | `node.animate(target, to, ms, …)` / `transition(kind, ms)` for nodes; **for Draw, a `var` + `evFrame`** | ch. 4 §6 |
| `document.visibilitychange` | no event. A hidden window stops producing frames, so the first frame back **jumps by the whole stall** — `render/native/engine.nim:3241`. **Clamp your step** | ch. 4 §8 |
| `setPointerCapture` | keep the pointer id in your own `var`, act in `evPointerMove`, release in `evPointerUp` | ch. 4 §8 |
| `window.innerWidth` / reflow | **no reflow.** Windows are fixed: pick a size and use it (`app.nim:30-32`) | ch. 4 §9 |
| `Math.random()` in the art | transcribe the page's PRNG so the port is deterministic (`app.nim:49-61`) | ch. 2 §8 |
| `<style>` / `.class {}` / cascade | there is no cascade: a `proc` returning a `Style`, applied with `use = …` | `reference/15a` §0 |

## The three rules that make the port compile

**1. Every `Draw` method returns a NEW `Draw`. You must assign.**

```nim
var d = Draw()
d = d.rect(0, 0, 100, 50, cBody)      # correct
d.rect(0, 0, 100, 50, cBody)          # wrong: the result is discarded, nothing is drawn
```

This includes the "modifier-looking" calls: `save`, `restore`, `translate`, `scale`,
`rotate`, `alpha`, `blend` are all value-returning (`sdk/ui/paint.nim:73-80`). The real
app chains them *within* an expression, which is the same rule:

```nim
d = d.save().arcTo(w * 0.9'f32, h * 0.3'f32, 44.0'f32, 17.2'f32, 321.0'f32)
     .stroke(rgba(60, 28, 8, 0.22), 3.0'f32).restore()          # app.nim:222-223
```

**2. The last `fill`/`stroke` applies to the whole path so far.**

`stroke()` takes exactly one width (`paint.nim:55`). A web path with two sub-paths of
different widths is two `Draw` values:

```nim
d = d.moveTo(x0, y0).lineTo(x1, y1).stroke(0xFF000000'u32, 1.0)   # thin
d = d.moveTo(x0, y0).lineTo(x1, y1).stroke(0xFF000000'u32, 6.0)   # thick
```

**3. Colours are ARGB `uint32` and there is no gradient primitive in `Draw`.**

```nim
const cEnamel = 0xFF9FC9B6'u32          # app.nim:35 — alpha first, always FF for opaque
d = d.rect(0, 0, 10, 10, 0x66FF0000'u32) # 0x66 = 102/255 ≈ 40 % alpha
```

## Nim traps, with the measured error text

Every row below was compiled against this repo with
`bash tools/build-wasm.sh` (Nim 2.2.10, wasm32). The fix column is what the working
port does.

| You wrote | Measured error | The trap | Do this |
|---|---|---|---|
| `for m in ms: m.y -= 1.0'f32` | `Error: type mismatch`<br>`expression 'm.y' is immutable, not 'var'` | `for x in seq` iterates **copies** (`app.nim:643` is the workaround in situ) | index it: `ms[i].y = ms[i].y - 1.0'f32` for `i in 0 ..< ms.len` |
| `for x in v: x = x + 1` | `Error: 'x' cannot be assigned to` | same trap, plain assign | same |
| `n.fontSize(10).weight(700)` | `Error: expression 'fontSize(n, 10)' has no type (or is ambiguous)` | node setters return **void** (`sdk/yantra.nim` — `proc fontSize*(node, v)`), so they cannot chain | one call per line |
| `if a.id == b.id:` | `Error: type mismatch`<br>`Expression: a.id == b.id`<br>`  [1] a.id: NodeId` … expected `proc ==(a, b: Deg/Ms/Px: bool)` etc. | `NodeId = distinct int32` (`sdk/core/runtime.nim:7`) and the SDK defines **no** `==` for it | `int32(a.id) == int32(b.id)`, or track the handle yourself |
| `const M = {'1': '!', '2': '"'}` then `M['1']` | `Error: type mismatch`<br>`Expression: M['1']`<br>`  [1] M: array[0..1, (char, char)]`<br>`  [2] '1': char` | a char-keyed const table becomes an **array of tuples**, not a map | a `case` statement — `shiftedOf()` in `app.nim:495-512` is the worked version |
| `round(2.5'f32)` | **no compile error.** It builds, then faults at runtime: mini-libc's `round` is implemented **recursively**, so a per-pixel loop overflows the stack (`wasm trap`, `apps/minipaint/ENGINE-ISSUES.md:582-586`; `reference/16` §3.4) | the trap is at *run* time, which is why it survives a clean build | `int32(if x < 0: x - 0.5 else: x + 0.5)` — `rnd32()` in `app.nim:64` |
| calling a proc defined further down the file | `Error: undeclared identifier: '…'` | procs must be declared before use | a forward declaration — `proc midBell(): float32` at `app.nim:572`, defined at `:591` |

**Measured and *not* a trap** (do not write this in a port note): `+=`, `-=`, `*=`,
`/=` on a `float32` variable or on a `float32` field of a `var` object compile and run
fine — probe `.board/probes/p8_allops.nim`. What does **not** work is compound
assignment through a `for`-loop copy (rows 1-2 above). Also note `-=` and `+=` *are*
overloaded for `Signal[T]` (`sdk/core/signals.nim:239-243`), so `count -= 1` works on
a signal but not on a `float32` seq element.

And one that is not an error at all, only a design trap: **`float64` compiles and is
silently wrong on wasm32** — there is no hardware `float64`. Use `float32` everywhere
(`reference/16` §3.3).

## The four chapters

| Chapter | Read it when |
|---|---|
| `HTML5-CANVAS-TO-SKIA.md` | the page has a `<canvas>`, an inline `<svg>`, or procedural art. Command-by-command, with the gradient workaround and the PRNG-transcription trick |
| `CSS-SHADOWS-AND-EFFECTS.md` | the page leans on gradients, `box-shadow`, `border-radius`, `opacity`, blend modes or filters — what Yantra can and cannot do, and the workaround for each |
| `DOM-EVENTS-TO-SDL3.md` | the page listens for keys, clicks, pointer, rAF, timeouts or storage — including **how to hit-test your own drawn keys**, which is the real problem |
| `../yantra/reference/15a-html-css-mapping.md` | you need the node-level CSS table (every property, all 48 node kinds, all 265 props) — do not rewrite it here |

## The port order that works

1. **Read the page and count the layers.** How many `<canvas>`, how many `<svg>`, how
   many controls? (See the routing decision above.)
2. **Transcribe the constants first** — every `const` block from `:root`, the layout
   function, the palette. `app.nim:19-44` is 26 lines and removes all later guesswork.
3. **Transcribe the PRNG before anything that uses it** (`app.nim:49-61`). If the page
   calls `Math.random()` for its art, replace it with a *deterministic* generator or
   the port will never be reproducible.
4. **Paint the static scene into a `Layer` once**, in a proc named after the source's
   `paintX()` (`paintDesk`, `paintPaper`). It is not redrawn per frame.
5. **Build the per-frame scene** as one `buildScene(): string` returning `d.cmds`
   (`app.nim:658-688`), with each drawing routine as `proc drawX(d: var Draw)` taking
   the Draw by reference — so they compose without returning values.
6. **Wire input last**, from `hitKey()` outward (`app.nim:857-902`).
7. **Build and screenshot.** `bash tools/build-wasm.sh apps/<x>/app.nim apps/<x>/app.wasm`,
   then `render/native/build/desktop/yantra_run.exe apps/<x>/app.wasm`. Compiling is not
   rendering — the first frame is where colour/gradient/rounding mistakes show up.

## Rules

- Never invent an API. Every name above was read out of `sdk/`. If something is not
  here, grep `sdk/` before using it, and write `VERIFY IN SOURCE` rather than guessing.
- Quote real lines from `apps/typewriter/app.nim` in preference to fresh examples.
- Three-layer routing is not a style preference: layer 1 gives you hit-testing, focus
  and keyboard for free, layer 2 gives you nothing but pixels. Choose deliberately.