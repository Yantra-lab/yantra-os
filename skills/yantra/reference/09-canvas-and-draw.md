# 09 — Canvas and Draw

The 2D drawing API: the command list, layers, raw pixels, blend modes, and an honest
list of what `Draw` cannot do.

---

## Ground truth for this chapter

Every claim below was checked against these files. Signatures are copied verbatim.

| Fact | Source |
|---|---|
| `Draw` is an immutable builder: every method is `proc x*(d: Draw; …): Draw` | `sdk/ui/paint.nim:28-82` |
| The 24 verbs and their exact command strings | `sdk/ui/paint.nim:28-82` |
| Colours are `uint32` `0xAARRGGBB`, printed as **decimal** into `.cmds` | verified by compiling and running `paint.nim`'s own builder |
| Command stream is `;`-terminated, parsed by `CmdReader` / `runCmds` | `libs/nimskia/src/skia_shim.cpp:1185`, `:1305` |
| An unrecognised verb is **silently skipped** | `libs/nimskia/src/skia_shim.cpp:1413` (`default: break;`) |
| `O` (alpha) is a **cumulative multiplier**, applied to every later verb, and pushed/popped by `P`/`p` | `skia_shim.cpp:1412`, `:1327`, `:1364`, `:1365` |
| Layer surfaces are **premultiplied** N32; `read`/`write` are **straight** RGBA | `skia_shim.cpp` (`SkSurfaces::Raster(MakeN32Premul)` vs `kRGBA_8888` + `kUnpremul`) |
| Layer ids are offset by the engine's `layerBase` so two apps never collide | `render/native/engine.nim:1730-1735` |
| Canvas painting: `paintSurface` first, then `drawCommands` if `P_DRAW` is set | `render/native/engine.nim:1974-1982` |
| `canvas` maps to `make(nkCanvas, parent)` | `sdk/ui/dsl.nim:350-354` |
| `draw` prop: `PropMeta(dslName: "draw", wireProp: "Draw", propType: "string", allowedNodes: "Canvas")` | `protocol/schema.nim:357` |
| `evCanvasDraw = 11` exists in the SDK | `sdk/core/wire.nim:334`; the handler wrapper is `sdk/yantra.nim:414` |
| …but the engine never dispatches event 11 | grep of `render/native/*.nim`, `host/*.nim`, `web/runner/runner.js` for `CANVASDRAW\|CanvasDraw\|canvasDraw` → **0 hits** |
| **No text-measurement proc exists** | grep of `sdk/` for `measureText\|textMeasure\|measure` → **0 procs**; `yk_text_measure2` is in the shim but not exported to apps |

> **CORRECTED 2026-10-03.** This table used to cite `sdk/yantra.nim:414` for
> `evCanvasDraw = 11`. Line 414 is `proc onCanvasDraw*(node: Node, handler: proc()) =
> node.on(evCanvasDraw, handler)`; the constant itself is `sdk/core/wire.nim:334`.
> The claim was true, the evidence was not.

**What was verified at runtime.** A flat `Draw` list (rect / circle / text) was
compiled to wasm and driven through the real engine with
`render/native/build/mpdrive.exe`, reading the framebuffer numerically: a green rect
came back `(0,255,0)`, a red circle `(255,0,0)`, a cyan circle `(0,255,255)` in the
right places. That is the flat path. See §9 for what was **not** verified and why.

---

## 1. Two ways to draw

### (a) `canvas(draw = …)` — a declarative command list

The `draw` prop of a `canvas` node is a **string**. Build it with `Draw` and hand it
over as `.cmds`:

```nim
canvas @art(width = 200.px, height = 150.px, draw = Draw().layer(paper, 0, 0).cmds)
```

Because the prop value is not a literal, the DSL wraps it in an effect
(`sdk/ui/dsl.nim:67-68`), so **the list is rebuilt whenever any state it reads
changes**. That is the whole mechanism for per-frame redraw:

```nim
proc scene(): Draw =
  var d: Draw
  d = d.circle(60, 60, 30, (if flag.get: 0xFFFF0000'u32 else: 0xFF00FF00'u32))
  d

canvas @view(width = 140.px, height = 140.px, draw = scene().cmds)
```

Clicking a button that calls `flag.set(...)` re-runs `scene()` and repaints. Verified
working: a draw list that read `flag.get` chose its colour and the engine repainted.

If the prop value **is** a literal string, it is set once and never recomputed
(`reactiveOrOnce` checks `isLiteral`). `draw = ""` never changes.

### (b) `onCanvasDraw` — **registered but never dispatched**

`onCanvasDraw` exists in the SDK:

```nim
sdk/core/wire.nim:334   evCanvasDraw = 11     ## E_CANVASDRAW = 11
sdk/yantra.nim:414      proc onCanvasDraw*(node: Node, handler: proc()) = node.on(evCanvasDraw, handler)
```

But grepping `render/native/*.nim`, `host/*.nim` and `web/runner/runner.js` for
`CANVASDRAW`, `CanvasDraw` or `canvasDraw` returns **zero hits**. The engine never
raises event 11, on native or web.

> **NOT SUPPORTED YET.** `onCanvasDraw` compiles and registers a handler that is
> never called. Do not build on it.

**What to use instead:** `canvas(draw = …)` for the declarative path, and
`onFrame:` for per-frame work. `wantFrames*` / `frameEvent` do fire, and `fire()` sets
`dirtyF` so layout runs after the handler. `onFrame` handlers live on any node
(`onframe` → `evFrame`, `sdk/ui/dsl.nim:74`).

### When to use which

| You want | Use |
|---|---|
| A picture that changes only when the app's state changes | `canvas(draw = …)` reading state |
| Something animated at 60 fps | `onFrame:` — but re-set the whole `draw` string each frame (see below) |
| Strokes that accumulate and must persist | a **layer**, drawn by `d.layer(...)` (§4) |
| A bitmap from memory | `pixels` + a buffer (§5) |

---

## 2. The `Draw` builder

```nim
type
  Draw* = object
    cmds*: string     ## the command list (format: libs/nimskia skia_shim.cpp runCmds)
```

**`Draw` is immutable.** Every method takes `d` **by value** and returns a modified
copy. Two consequences that bite:

* Chaining works from a fresh value: `Draw().moveTo(10,10).lineTo(200,80).stroke(c, 6)`.
* **An unassigned call is lost.** `d.rect(…)` on its own does not mutate `d`, because the
  returned `Draw` is discarded. In fact a bare statement does not even compile — Nim raises
  `expression 'rect(d, …)' is of type 'Draw' and has to be used (or discarded)` — and if you
  write `discard d.rect(…)` the command is silently gone. So for one command per statement you
  **must** write `d = d.rect(…)`; the same is true of every other verb, `close` included.

> **CORRECTED 2026-10-03.** This used to say `reference/16-engine-limits-and-workarounds.md` §2.1
> item F "says 'one command per statement: `d.rect(…)`' — that advice is wrong". It does not say
> that: `16-engine-limits-and-workarounds.md:164` reads "**assign every call**, one command per
> statement: `d = d.rect(…)`". Chapter 16 is right and this chapter was misquoting it. The rule
> itself is unchanged — assign every `Draw` call. Chapter 16's extra point (`:160-169`) is worth
> keeping: the **bare statement fails to compile**, it is only `discard` (or a helper proc that
> forgets `result = d`) that loses work *silently*.

Floats go through a local formatter (`paint.nim:28`) that prints **two decimals**,
because the sandbox's C library cannot `formatFloat`. So every number in `.cmds`
looks like `10.00`.

### The complete method list

All signatures copied from `sdk/ui/paint.nim:28-82`.

| Signature | Emits | Meaning |
|---|---|---|
| `proc moveTo*(d: Draw; x, y: float32): Draw` | `M x y` | start a path / move the pen |
| `proc lineTo*(d: Draw; x, y: float32): Draw` | `L x y` | straight segment to a point |
| `proc quadTo*(d: Draw; cx, cy, x, y: float32): Draw` | `Q cx cy x y` | quadratic Bézier to `(x,y)` via control `(cx,cy)` |
| `proc curveTo*(d: Draw; cx1, cy1, cx2, cy2, x, y: float32): Draw` | `C cx1 cy1 cx2 cy2 x y` | cubic Bézier with two controls — **this is how you draw an axis-aligned ellipse** (§8) |
| `proc arcTo*(d: Draw; cx, cy, radius, startDeg, sweepDeg: float32): Draw` | `A cx cy r startDeg sweepDeg` | circular arc — **read the two arc traps in §8** |
| `proc close*(d: Draw): Draw` | `Z` | close the current path |
| `proc svgPath*(d: Draw; path: string; x, y, scale: float32; argb: uint32; strokeWidth = 0'f32): Draw` | `V x y scale strokeWidth argb <path>` | replay an SVG `d` attribute; fills unless `strokeWidth > 0` |
| `proc fill*(d: Draw; argb: uint32): Draw` | `F argb` | fill the path built so far — **consumes it**, see §8 |
| `proc stroke*(d: Draw; argb: uint32; width: float32): Draw` | `S argb width` | stroke the path so far, round joins and caps — **consumes it** |
| `proc rect*(d: Draw; x, y, w, h: float32; argb: uint32; radius = 0'f32): Draw` | `R x y w h radius argb` | filled rounded rect |
| `proc circle*(d: Draw; cx, cy, r: float32; argb: uint32): Draw` | `E cx cy r r argb` | filled circle — `r` twice, because there is **no `ellipse` proc** (§8) |
| `proc line*(d: Draw; x1, y1, x2, y2: float32; argb: uint32; width = 1'f32): Draw` | `G x1 y1 x2 y2 argb width` | one straight line, round caps |
| `proc text*(d: Draw; x, y, size: float32; argb: uint32; s: string; weight = 400): Draw` | `T x y size argb weight <s>` | one line of text. **`(x, y)` is the top-left of the paragraph line box** — not the baseline — and there is **no `align` parameter**. See §3 and §8 |
| `proc image*(d: Draw; x, y, w, h: float32; file: string): Draw` | `I x y w h 0 <file>` | a file image — **the file path is the LAST argument**; fit is hardcoded `0` (contain) |
| `proc layer*(d: Draw; l: Layer; x, y: float32; w = 0'f32, h = 0'f32): Draw` | `Y id x y w h` | composite a `Layer` bitmap; `w`/`h` are the **size** in px, `0` = the layer's own size |
| `proc pixels*(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32, h = 0'f32): Draw` | `X id pw ph x y w h` | upload an RGBA buffer from memory, **nearest-neighbour** |
| `proc blend*(d: Draw; mode: Blend): Draw` | `b <ord>` | set the blend mode for later commands |
| `proc save*(d: Draw): Draw` | `P` | push the transform, clip, alpha and blend |
| `proc restore*(d: Draw): Draw` | `p` | pop them |
| `proc translate*(d: Draw; x, y: float32): Draw` | `t x y` | translate the origin |
| `proc scale*(d: Draw; sx: float32; sy = 0'f32): Draw` | `s sx sy` | scale; **`sy == 0` means "uniform"**, and that is deliberate, not a bug (§7) |
| `proc rotate*(d: Draw; degrees: float32): Draw` | `o degrees` | rotate (degrees) |
| `proc alpha*(d: Draw; a: float32): Draw` | `O a` | **multiply** the alpha — sticky, see §7 |
| `proc clip*(d: Draw; x, y, w, h: float32): Draw` | `K x y w h` | rectangular clip only |

### The `.cmds` string

Space-separated numbers, `;`-terminated, one verb per command. Compiled and run
output from `paint.nim`'s own builder, every verb once:

```
M 10.00 10.00;L 100.00 80.00;Q 120.00 90.00 140.00 100.00;C 150.00 110.00 160.00 120.00 170.00 130.00;A 200.00 200.00 40.00 0.00 180.00;Z;F 4279312947;S 4294967295 3.00;R 0.00 0.00 10.00 10.00 4.00 4278190080;E 50.00 50.00 20.00 20.00 4294901760;G 0.00 0.00 5.00 5.00 4278255360 2.00;T 10.00 20.00 14.00 4294967295 700 hello\; world;V 4.00 4.00 2.00 1.50 4278190080 M0 0 L10 10 Z;b 24;P;t 5.00 6.00;s 2.00 0.00;o 45.00;O 0.50;K 0.00 0.00 100.00 100.00;p;
X 1 4 4 0.00 0.00 80.00 80.00;
M 100.00 20.00;L 120.00 60.00;L 160.00 60.00;Z;F 4294956800;
```

Read three things off that line:

* `4279312947` is `0xFF0000FF` in **decimal**. Colours are `uint32` printed with
  `$argb`, and the reader (`strtoull(p, &q, 0)`) accepts decimal or `0x` hex — but
  what Yantra writes is always decimal.
* `hello\; world` — `text` and `svgPath` embed the raw string in the stream, so a
  **semicolon inside the text is escaped as `\;`**. This happens automatically; you
  never escape it yourself.
* `s 2.00 0.00` — `scale(2)` emits a zero `sy`, and `skia_shim.cpp:1410` reads
  `y == 0` as "same as x". **This is intended, not a bug** — there is no other way to
  spell a uniform scale with a two-argument signature.

`runCmds` (`skia_shim.cpp:1305`) **skips verbs it does not recognise** —
`skia_shim.cpp:1413` is literally `default: break;`. So a newer command stream still
renders on an older engine. The flip side is worse than the guarantee suggests: a newer
app on an older engine loses those commands with **no error, no warning, and a
plausible-looking but incomplete frame**. Do not read "it built" as "it drew".

---

## 3. Colours

Colours are `uint32` in **`0xAARRGGBB`** byte order — alpha first.

```nim
0xFF0000FF'u32     # opaque blue
0x80FF0000'u32     # half-transparent red
0x00000000'u32     # fully transparent (skips everything)
0xFFFFFFFF'u32     # opaque white
```

Write the alpha byte as the **first** byte: `0xAA` is the alpha, not the last.

### The silent trap: a CSS hex has **no** alpha byte

Every `Draw` primitive takes `argb: uint32`. A six-digit CSS colour pasted straight in
carries an alpha of `0x00`:

```nim
d.rect(0, 0, 100, 100, 0xF7F9FB)     ## A = 0x00  ->  draws NOTHING
```

This **compiles, runs, crashes nothing, and is invisible.** No warning is emitted at any
layer — not by Nim, not by `paint.nim`, not by the shim. Every colour you write into a
`Draw` list needs its alpha byte supplied:

```nim
proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)
d.rect(0, 0, 100, 100, hex(0xF7F9FB))  ## opaque
```

That helper is verbatim from `apps/chess/app.nim:100`. Force `0xFF` up front, inside the
helper, so no call site can forget it.

**The same hex behaves differently in a `Draw` list than on a node.** A node colour prop
is forgiving: `render/native/engine.nim:345-348` (`proc argb`) promotes a missing alpha
byte, `if (u and 0xFF000000) == 0: 0xFF000000 or u else: u`, so `fill = 0x101018` on a
node is opaque. A `Draw` colour gets **no such promotion** — `paint.nim` writes `$argb`
straight into the stream (`paint.nim:58`, `:64`) and the shim does a bare
`paint.setColor(SkColor(argb))` at `skia_shim.cpp:1327`. **Port a colour from a node into
a `Draw` list and it goes invisible.** That is why the example in §9 uses `hex()` for
every `Draw` colour and why the same example's `app(…, fill = 0x101018)` is fine.

**`rgba` has two different signatures — know which one you have.** `sdk/ui/style.nim:23`
defines `proc rgba*(rgb: int; alpha: float): int` — a **signed `int`** taking a packed
`0xRRGGBB` plus an alpha float, clamping alpha to `1..255` (`style.nim:26`, so `alpha = 0`
comes back as `1`, "almost clear", deliberately distinguishable from a plain opaque
`0xRRGGBB`). Several ports define their **own** `proc rgba(r, g, b: int32; a: float32): uint32`
— `apps/typewriter/app.nim:80`, `apps/dna/app.nim:88`, `apps/gallery/app.nim:91` — and
Nim resolves in favour of the one defined in the port. **Reuse the port's. Do not add a
third definition**; two identically-named procs with different arities in one module is a
silent overload surprise, and a third makes it worse.

### `Draw.text`: where `(x, y)` actually lands

> ~~"`(x, y)` is the baseline left, not the top-left."~~
> ~~"`Draw.text(x, y, size, argb, s, weight)` puts `(x, y)` at the **baseline left**, not
> the top-left."~~ — both lines appeared in earlier drafts of this chapter.
>
> **CORRECTED 2026-10-03.** Both are wrong. `y` is the **top of the paragraph's line box**:
> neither the baseline nor the ink top. The shim hands `(x, y)` straight to
> `SkParagraph::paint` — `libs/nimskia/src/skia_shim.cpp:291`, `p->paint(static_cast<SkCanvas*>(c), x, y)`
> inside `yk_text_draw` — and `SkParagraph::paint` places `(x, y)` at the paragraph box's
> top-left. The SDK's own doc comment says "Draws `s` with its top-left at (x, y)"
> (`libs/nimskia/src/nimskia.nim:76`); that comment is **correct about the box and is the
> source of the "top-left = ink top" misreading**, which is how CSS `textBaseline:'top'`
> got ported as if `y` were the cap-height line.

**The offsets are MEASURED, not documented.** From the requested `y`, in units of font size
`S`, measured at `S = 12`, `24` and `48`:

| Feature | Offset from `y` |
|---|---|
| cap / ascender ink top | `y + 0.375·S` |
| x-height top | `y + 0.583·S` |
| **baseline** | `y + 1.0833·S` |
| descender bottom | `y + 1.333·S` |

So the two conversions you actually need:

```nim
const BaselineK = 1.0833   ## yantra_y = wantedBaselineY - BaselineK * size
const CapTopK   = 0.375    ## CSS textBaseline:'top'  ->  yantra_y = Y - CapTopK * S
```

**Caveat, and it is not small: these ratios are EMPIRICAL — measured from rendered output
for the DEFAULT TYPEFACE AND WEIGHT ONLY.** They are ratios of whatever Segoe UI's metrics
resolve to through SkParagraph at that size. A different family, a different weight, a
`lineHeight` override (`skia_shim.cpp:145`) or a multi-line string will move them. Treat
them as good for default-weight Segoe UI at one size and **re-measure** before relying on
them elsewhere.

`Draw.text` also has **no `align` parameter** (`sdk/ui/paint.nim:63-64`) — see §8. The
native `drawText` *does* take one (`nimskia.nim:75`), which is exactly why `Draw.text`
cannot reuse it.

### Premultiplication

Layer surfaces are created as
`SkSurfaces::Raster(SkImageInfo::MakeN32Premul(w, h))` — **premultiplied** N32. But
`yk_layer_read` and `yk_layer_write` use `kRGBA_8888_SkColorType` with
`kUnpremul_SkAlphaType` — **straight** (non-premultiplied) RGBA, top row first. So
`read` gives you un-premultiplied bytes while the surface holds premultiplied ones.
The moments that hurts, all measured in `apps/minipaint/PORT-NOTES.md` §"the lossy
8-bit store":

* Storing a translucent colour round-trips **lossily**: `rgba(127,187,227,0.2)`
  comes back out of the surface as the premultiplied `(125,185,225,51)`. A `read`
  unpremultiplies on the way out, and 8 bits per channel cannot represent the result
  exactly. Do not expect `read` to equal `write`.
* Skia's **src-over unpremultiplies a translucent destination** before blending, so
  compositing over a semi-transparent layer does not simply add alphas.
* An `O` alpha command **multiplies**, so `0x80FF0000` at `O 0.5` is stored as roughly
  a quarter of red, not a half.
* Chained operations amplify input error by 2–3×, so any dither bound you derive has
  to be scaled by a **measured per-chain gain**, not a guessed one.

**Practical rule:** use layers as an opaque drawing surface. Do the alpha maths with
blend modes and explicit compositing, and treat `read`/`write` as approximate.

---

## 4. Layers — the bitmap you draw into over time

A `Layer` is a raster surface the app draws into with a `Draw` list, exactly like a
canvas, but **it is not a node**: nothing lays it out, nothing repaints it
automatically. It keeps whatever you drew until you change it. That is the whole
point.

### The API, verbatim (`sdk/ui/paint.nim:13`, `:102-124`)

```nim
type Layer* = distinct int32

proc newLayer*(w, h: int): Layer
proc draw*(l: Layer; d: Draw)
proc clear*(l: Layer)
proc filter*(l: Layer; kind: Filter; amount = 1'f32)
proc read*(l: Layer; x, y, w, h: int): seq[byte]
proc write*(l: Layer; x, y, w, h: int; rgba: openArray[byte])
proc free*(l: Layer)
```

| Proc | What it does |
|---|---|
| `newLayer(w, h)` | a **transparent** surface of `w × h`. Rejects `w <= 0`, `h <= 0`, or any side `> 16384`. |
| `draw(l, d)` | runs the command list **into** the layer, in place. Whatever was there stays; this adds. |
| `clear(l)` | `l.draw(Draw().blend(bClear).rect(0, 0, 1e6, 1e6, 0'u32))` — the whole surface to transparent in one command. |
| `filter(l, kind, amount)` | applies a whole-surface filter **destructively, in place** — the pre-filter content is gone. |
| `read(l, x, y, w, h)` | `w*h*4` **RGBA** bytes, top row first, straight (non-premultiplied) alpha. **Returns an empty seq on failure** — check `len`, do not check for nil. |
| `write(l, x, y, w, h, rgba)` | **replaces** the destination rectangle with straight RGBA. |
| `free(l)` | releases the surface. |

**`write` replaces; it does not blend.** A transparent pixel in your buffer erases
what was there. `apps/minipaint/app.nim:567-599` composites its document over white
**in place** in the buffer for exactly this reason — writing a flattened document
with transparent margins straight into the layer turns the canvas dark.

### `Filter`

```nim
type Filter* = enum
  blur, brightness, contrast, saturation, invert, greyscale, sepia, fade
```

| Ord | Filter | `amount` meaning |
|---:|---|---|
| 0 | `blur` | pixels of blur — **the shim uses `amount * 0.5` as the sigma**, so `filter(blur, 8)` ≈ 4px sigma |
| 1 | `brightness` | additive offset; negative darkens |
| 2 | `contrast` | contrast multiplier |
| 3 | `saturation` | `setSaturation(amount)`; `0` is grey, `1` unchanged |
| 4 | `invert` | inverts RGB, leaves alpha |
| 5 | `greyscale` | `setSaturation(0)` |
| 6 | `sepia` | fixed sepia matrix |
| 7 | `fade` | `setAlphaf(amount)` — overall opacity |

Every `filter` ends the same way: the surface is cleared to transparent and the
filtered image is drawn back over it. **There is no undo.** To keep the original,
keep a second layer, or re-run the `Draw` list that made it.

### Why layers are the answer for a paint app

A canvas's `draw` string is rebuilt and replayed whenever state changes. For a paint
app that is exactly wrong: every stroke would repaint every earlier stroke, so cost
grows with the square of the picture and the whole thing flickers.

Layers invert it. `layer.draw(...)` is **incremental and permanent** — `render/native/t_paint.nim`
asserts this directly: a stroke drawn into a layer **stays** across two further
frames ("drawn once, not per frame"). The canvas then just says "show this layer":

```nim
let paper = newLayer(800, 600)
paper.draw(Draw().moveTo(10, 10).lineTo(200, 80).stroke(0xFF000000'u32, 6))
canvas(draw = Draw().layer(paper, 0, 0).cmds, width = 800.px, height = 600.px)
```

An `onPointerDown` handler adds one dab and the engine marks the layer dirty
(`render/native/engine.nim:1752-1756` bumps `layerVer`, damages the 3D views, sets
`fullDamage`). No state churn, no rebuild of the command string.

**Layer ids are namespaced by the engine.** `wireLayers` sets
`e.layerBase = nextLayerBase; nextLayerBase += 1_000_000`
(`engine.nim:1730-1731`) and adds the base to every id, so two apps in one host can
both have a layer `0` without colliding.

### Layers for shadows and effects

Because `filter` is destructive and `layer` composites, **a blurred copy is a drop
shadow**:

```nim
let shadow = newLayer(w, h)
shadow.draw(Draw().rect(10, 10, 80, 40, 0xFF000000'u32))
shadow.filter(blur, 6)                      # sigma 3
var d: Draw
d = d.layer(shadow, 4, 6)                   # offset = the shadow's direction
d = d.rect(10, 10, 80, 40, 0xFF3366CC'u32)  # the shape on top
```

---

## 5. Raw pixels — `pixels` + a buffer

`pixels` uploads an RGBA buffer straight from app memory. It needs a `newBuffer()`
handle from the scene3d module (`sdk/ui/scene3d.nim`):

```nim
var px = newSeq[byte](4 * 4 * 4)
for i in 0 ..< 16:
  px[i * 4]     = (if i mod 2 == 0: 255'u8 else: 0'u8)   # R
  px[i * 4 + 2] = (if i mod 2 == 0: 0'u8 else: 255'u8)   # B
  px[i * 4 + 3] = 255                                     # A
let dots = newBuffer()
dots.setData(addr px[0], px.len)

canvas @dots(width = 80.px, height = 80.px,
             draw = Draw().pixels(int32(dots), 4, 4, 0, 0, 80, 80).cmds)
```

```nim
proc pixels*(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32, h = 0'f32): Draw
```

`pw × ph` is the **source** size in pixels — they are **`int`**, not `float32`.
`x, y, w, h` is the **destination** rect. `w`/`h` of `0` mean "natural size".

* Byte order is **RGBA**, straight alpha.
* **The upload is nearest-neighbour** — `SkSamplingOptions()` with no filter, versus
  the `SkSamplingOptions(SkFilterMode::kLinear)` that `layer` uses. That is why
  `layer` looks soft when scaled and `pixels` looks crisp. `render/native/t_paint.nim`
  asserts this directly: a 4×4 checker scaled to 80px comes back with **hard 20px
  red squares and hard blue squares**, not a blur.
* The buffer must stay alive and unchanged; the draw list holds only the handle, so
  `seq[byte]` locals are the right shape (they live in app memory for the app's life).

Use `pixels` for pixel art, sprite sheets and any data you computed yourself
(`apps/minipaint` draws its gradient picker icon this way —
`d.pixels(gradientIconBuf(), GRADIENT_ICON_W, GRADIENT_ICON_H, gdx, gdy)`).

---

## 6. Blend modes

```nim
type Blend* = enum
  bClear, bSrc, bDst, bSrcOver, bDstOver, bSrcIn, bDstIn, bSrcOut, bDstOut,
  bSrcATop, bDstATop, bXor, bPlus, bModulate, bScreen, bOverlay, bDarken, bLighten,
  bColorDodge, bColorBurn, bHardLight, bSoftLight, bDifference, bExclusion,
  bMultiply, bHue, bSaturation, bColor, bLuminosity

const eraser* = bDstOut   ## draw with this blend to erase what is under the stroke
```

`blend(m)` sets the mode for every command after it, until another `blend` or a
`save`/`restore` pair. The number is the enum's ordinal, which is what goes into
`.cmds` as `b <ord>` (`blend(bMultiply)` emits `b 24` — verified).

| Ord | Name | What it does |
|---:|---|---|
| 0 | `bClear` | destination is cleared to transparent |
| 1 | `bSrc` | source only |
| 2 | `bDst` | destination only, source ignored |
| 3 | `bSrcOver` | **the default.** Source over destination |
| 4 | `bDstOver` | destination over source |
| 5 | `bSrcIn` | source, where destination is opaque |
| 6 | `bDstIn` | destination, where source is opaque |
| 7 | `bSrcOut` | source, where destination is transparent |
| 8 | `bDstOut` | **destination, where source is opaque — this is the eraser** |
| 9 | `bSrcATop` | source over destination, keeping destination's alpha |
| 10 | `bDstATop` | destination over source, keeping source's alpha |
| 11 | `bXor` | source XOR destination |
| 12 | `bPlus` | additive (`bPlus` is the one the DSL also calls `plus`) |
| 13 | `bModulate` | source × destination |
| 14 | `bScreen` | 1 − (1−s)(1−d) — lightens |
| 15 | `bOverlay` | multiply or screen, per side |
| 16 | `bDarken` | the darker of the two |
| 17 | `bLighten` | the lighter of the two |
| 18 | `bColorDodge` | dodge |
| 19 | `bColorBurn` | burn |
| 20 | `bHardLight` | hard light |
| 21 | `bSoftLight` | soft light |
| 22 | `bDifference` | \|s − d\| |
| 23 | `bExclusion` | s + d − 2sd |
| 24 | `bMultiply` | s × d — the classic "darker" |
| 25 | `bHue` | hue of source, saturation+value of destination |
| 26 | `bSaturation` | saturation of source, hue+value of destination |
| 27 | `bColor` | hue+saturation of source, value of destination |
| 28 | `bLuminosity` | luminosity of source, hue+saturation of destination |

Modes 0–28 match Skia's `kLastMode = 28` exactly; the shim guards `m >= 0 && m <=
kLastMode`, so a bad ord is ignored rather than crashing.

### `eraser`

`eraser` is `const eraser* = bDstOut`, a convenience alias:

```nim
paper.draw(Draw().blend(eraser).rect(90, 0, 20, 150, 0xFF000000'u32))
```

The shape of the rect decides **what** is erased, not its colour — `bDstOut` keeps
the destination where the source is opaque. Painting a circle with `eraser` punches a
round hole in whatever is under the stroke.

The DSL also accepts blend **words** on ordinary nodes
(`sdk/ui/dsl.nim:158`: `normal=3`, `multiply=24`, `screen=14`, `luminosity=28`, …) —
that is for node compositing, not for a `Draw` list. Inside `Draw` you use the enum.

---

## 7. Transforms, clip and alpha

### `save` / `restore` discipline

`save` (`P`) pushes the transform, clip, **alpha and blend** onto a stack;
`restore` (`p`) pops them. Every `save` needs a matching `restore`.

`runCmds` opens with one `cv->save()`, clips to the node box, translates by the
node's origin, and at the end unwinds with
`while (depth-- > 0) cv->restore(); cv->restore();`. So an **unbalanced `save` at the
end of the list is cleaned up for you** — but a `save` whose `restore` is missing in
the *middle* leaks into every command after it. Match them in the same list.

### The transform order

`translate`, `scale` and `rotate` mutate the current matrix, so they **compose**:

```nim
var d: Draw
d = d.translate(100, 50).scale(2).rotate(45)
```

sketches a rotated, doubled shape centred on `(100, 50)`. Note `scale(x)` with the
default `y = 0` emits `s x 0.00`, and the shim reads `y == 0` as "the same as x" —
`scale(2)` is uniform.

### `clip` is a rectangle and nothing else

```nim
proc clip*(d: Draw; x, y, w, h: float32): Draw    # K x y w h -> cv->clipRect(...)
```

That is the entire clipping capability: **an axis-aligned rect**. There is no path
clip, no elliptical clip, no soft mask in the `Draw` verb set.

> **NOT SUPPORTED YET.** Clipping to a shape. Workaround: draw the shape into its own
> layer and blend it to knock out everything outside the shape, or approximate with a
> rect clip plus an alpha mask drawn afterwards.

`clip` is saved and restored by `P`/`p`, so it is safe to set once at the top of a
group.

### `alpha` multiplies and is sticky

```nim
proc alpha*(d: Draw; a: float32): Draw    # O a  ->  sdk/ui/paint.nim:80
```

> **CORRECTED 2026-10-03 — one thing this chapter used to get wrong by omission.** Earlier
> drafts of this material repeated the claim that `Draw.alpha` is **silently dropped** by
> the engine. That is **FALSE**, and writing it would send you hunting for a bug that does
> not exist. `sdk/ui/paint.nim:80` really does emit `O `, and the shim really does handle
> it: `skia_shim.cpp:1412` is
> `case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;`.
> The accumulated `alpha` is then applied to real drawing — the `colour` lambda at
> `skia_shim.cpp:1327` (`if (alpha < 1) paint.setAlphaf(...)`) runs for every shape verb,
> plus explicitly for text (`:1353`), image (`:1360`), layer (`:1370`), pixel buffer (`:1384`)
> and svg path (`:1394`).

The real semantics, all four of which matter:

1. **It is a CUMULATIVE MULTIPLIER**, not a setter: the shim runs `alpha *= clamp(a, 0, 1)`.
   `O 0.5` twice gives `0.25`, and `O 1.0` does **not** undo an `O 0.5` — it multiplies by
   1 and leaves it at `0.5`. There is no "set alpha" verb.
2. **It is sticky**: it affects every command drawn after it, in the same replay, including
   `layer`, `image` and `pixels`.
3. **`save`/`restore` save and restore it** — `skia_shim.cpp:1364` pushes `alpha` onto a
   stack, `:1365` pops it. That is the only way back to full alpha.
4. **It is real but coarse.** The alpha byte *in the colour* is the simpler and far more
   predictable route, and it composes per-shape instead of per-list. Reach for `O` only
   when you genuinely want to dim a whole run of commands.

```nim
var d: Draw
d = d.save().alpha(0.5)
d = d.circle(50, 50, 20, 0xFFFF0000'u32)    # half-strength red
d = d.restore()                            # alpha back to 1
d = d.circle(100, 50, 20, 0xFF00FF00'u32)   # full-strength green
```

`reference/16-engine-limits-and-workarounds.md:125` calls this "the worst trap in this
chapter". It is the one that bites hardest, because the command string still looks
correct — `O` appears exactly where you put it.

One detail worth knowing: for `T` (text) the shim scales the **top byte** of the colour
rather than the paint's alpha — `skia_shim.cpp:1353`,
`col = (col & 0x00FFFFFFu) | ((unsigned)((col >> 24) * alpha) << 24)`. Every other verb
goes through the `colour` lambda at `:1327` instead. Both routes are the same multiplier.

### Anti-aliasing

Every paint the shim creates gets `setAntiAlias(true)`, so lines, circles and rounded
rects are antialiased. `pixels` is the exception — its upload is nearest-neighbour,
so it is never antialiased (§5).

---

## 8. What `Draw` cannot do, and what to do instead

This is the honest list. Everything marked **NOT SUPPORTED YET** is absent from
`sdk/ui/paint.nim` — not merely undocumented.

### Variable-width stroke (a brush that tapers)

> **NOT SUPPORTED YET.** `stroke(argb, width)` takes one width for the whole path.
> There is no per-point width, no pressure, no taper.

**Workaround: emit overlapping dabs.** Walk the path and stamp a circle every few
pixels. `apps/minipaint/tools.nim:119-129` does exactly this:

```nim
proc strokeDabs(d: Draw; x0, y0, x1, y1, size: float32; argb: uint32): Draw =
  # NOT named `stroke` — that collides with Draw.stroke
  # `result = d` first, or the caller's commands vanish (see §2)
  result = d
  let dist = sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
  let step = max(1.0'f32, size * 0.4'f32)
  var t = 0.0'f32
  while t <= dist:
    let f = t / dist
    result = result.circle(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, size / 2, argb)
    t += step
```

To get real taper, vary `size` along `t`. Two notes from the port: `floorf`/`ceilf`
are missing from the sandbox's mini-libc, so bound the coordinates with integer
comparisons; and skip the dab when `(dx*dx + dy*dy) > r*r + 0.25` to avoid a ring of
stray pixels at the boundary.

For a genuinely smooth variable-width line, build a **filled polygon** from the two
offset edges and `fill` it once — better than hundreds of circles, at the cost of
computing the offsets yourself.

### Gradients inside a Draw list

> **NOT SUPPORTED YET.** `fill(argb)` and `rect(..., argb)` take one flat colour.
> There is no gradient verb.

Node-level gradients **do** exist — `fill = linear(a, b, angle)` on an ordinary node
(`sdk/ui/style.nim:29-47`, feeding `pGradFrom`/`pGradTo`/`pGradAngle`) — but those
paint the **node's own background** via `paintSurface` (`engine.nim:1974-1982`).
They cannot fill a shape inside a `Draw` list.

**Workaround A — a strip loop.** Draw one flat rect per row (or column) with a
`lerp` between the two end colours. The §9 example does exactly this for a sky:

```nim
for row in 0 ..< 150:
  d = d.rect(0, row.float32, 320, 1,
             mix(0x2B3A67'u32, 0xF2795B'u32, row.float32 / 150.0'f32))
```

**Workaround B — compute into a layer.** For a gradient you need to move, resize or
read back, fill a `newLayer` with the loop and `layer` it in. miniPaint does this for
the gradient tool (`apps/minipaint/tools.nim:1147-1200`).

**The alpha in a gradient is a RAMP, not a constant.**
`a(t) = 255 + (alpha - 255) * t` — stop 0 is fully opaque, stop 1 carries the alpha.
The tempting `255 - alpha*t` is **wrong**: at `alpha == 0` it makes the first stop
transparent, so the gradient hides itself exactly where the user expects solid
colour. At `alpha == 255` both forms agree, which is why a test that only checks the
opaque case cannot tell them apart. miniPaint's `apps/minipaint/ref/src/js/config.js:434`
ships `alpha: 0`, and the currently-red test `apps/minipaint/tests/t_tools.nim:279-286`
asserts the stale constant reading.

### Drop shadow

> **NOT SUPPORTED YET.** No shadow verb.

Node-level `shadow = shadow(x, y, blur, color)` exists for a node's own box. For a
shape inside a `Draw` list, use a layer:

```nim
let sh = newLayer(w, h)
sh.draw(Draw().rect(10, 10, 80, 40, 0xFF000000'u32))
sh.filter(blur, 6)                     # sigma 3 (the shim halves it)

var d: Draw
d = d.layer(sh, 3, 5)                  # offset the shadow
d = d.rect(10, 10, 80, 40, 0xFF3366CC'u32)
```

Remember `filter` is **destructive** — keep the shape's own layer separate if you
want to re-use the unblurred version. And one `newLayer` per shadow is real memory;
re-use a single layer when only one shadow is on screen.

### Text measurement

> **NOT SUPPORTED YET.** There is no measure proc in the SDK at all.

* `sdk/ui/paint.nim:63` — `proc text*(d: Draw; x, y, size: float32; argb: uint32;
  s: string; weight = 400): Draw`. It returns a `Draw` and nothing else, and it has
  **no `align` parameter**, no width, no measured extent. There is nothing to read back.
* Grep of `sdk/` for `measureText`, `textMeasure`, `measure` returns **zero procs**
  (the only hits are the words "measured" in `sdk/ui/vlist.nim`'s row-height
  bookkeeping and a warning comment in `sdk/ui/settings.nim:121`).
* `y_node_size`'s axes (`host/host.nim:589-623`) are width, height, scrollY,
  mediaTime, duration, waveform peaks, blockCaret, canvas pointer x/y, scrollX,
  linkHit, findCount, findAt, pointerPage, command, menuCmd, sysTheme, accent,
  spellRange, peaks — **no text metrics on any axis**.
* `yk_text_measure2` exists in `skia_shim.cpp` and is wrapped **only on the native
  side** — `libs/nimskia/src/nimskia.nim:122` (and a simpler `measureText` at `:68`).
  Neither is exported to apps; `yk_text_draw2` at `:114` is imported privately for
  `drawText`, which is how the *engine* gets its centring and wrapping but not how an
  app can.

So right-aligning text, centring it, or laying out a word-wrapped paragraph is all
on you, and any of it is an **estimate**. Two honest options:

**Option A — a hand-built advance table.** miniPaint ships one
(`config.arial12`), a per-character advance for 12px Arial, and scales it linearly:

```nim
proc textCharWidth(ch: char; size: float32): float32 =
  arial12(ch) * (size / 12.0'f32)
```

That is a *measurement*, so it is only as good as the table. **Kerning is not
optional**: the same table carries `V`+`i` = `-0.578` and `T`+`o` = `-3.547`, and
`len(s) * 7` over-estimated all eight of miniPaint's menu labels by **1.7 to 12.3px**.
If you skip kerning, text will visibly overflow its box.

**Option B — don't measure.** Lay out to fixed widths, or give the text a fixed box
and let it clip. The `text` node (not `Draw.text`) participates in Yoga layout, so
prefer it when the text does not need to sit inside a `Draw` list.

Ascent and descent constants are available from the same table, which is what
`apps/minipaint/tools.nim:755-761` uses (`TEXT_ASCENT_EM = 0.905273`, `TEXT_DESCENT_EM = 0.211914`
— Arial's hhea 1854/434 of 2048).

Also remember `Draw.text(x, y, size, argb, s, weight)` puts `y` at the **top of the
paragraph's line box** — not the baseline, not the ink top. Measured offsets from `y`
are in §3 (`Draw.text`: where `(x, y)` lands); the baseline lands at `y + 1.0833 * size`
for default-weight Segoe UI. Default font families are `Segoe UI`, `Nirmala UI`,
`Segoe UI Emoji` (`skia_shim.cpp:139-142`); `weight > 0 ? weight : 400`
(`skia_shim.cpp:1354`).

### Filled polygons and ellipses — both absent as primitives

> **NOT SUPPORTED YET (as primitives).** There is no `polygon` proc and no `ellipse` proc
> in `sdk/ui/paint.nim`.
>
> **But read the verbs before you build a workaround.** "No proc" is not "no
> capability": the shim's `E` verb (`E cx cy rx ry`) *is* a true axis-aligned ellipse
> with independent semi-axes (`skia_shim.cpp:1346`), and it needs only
> `d.add "E …"`. Only `polygon` genuinely has no verb — that one does need the
> `moveTo`/`lineTo`/`close`/`fill` path below.

This is real and it is often the thing you trip over, so say it plainly:

* **Polygon.** A polygon is not a verb; it is `moveTo` + `lineTo`* + `close` + `fill` —
  `sdk/ui/paint.nim:28`, `:29`, `:45`, `:53`. That *is* the workaround and it works; it
  is only missing as a one-liner. Remember `fill` consumes the path (§ below), so build
  it in a proc you can replay.
* **Ellipse.** `circle` (`sdk/ui/paint.nim:59-60`) is the only oval proc, and it emits
  `E cx cy r r argb` — **one radius, twice**. There is no way to get an axis-aligned
  ellipse from `circle`. Three workarounds, all real:
  1. **Four `curveTo` calls** (`sdk/ui/paint.nim:35`, emits `C …`), the standard
     four-cubic-circle approximation, `k = 0.5523 × radius`.
  2. **`svgPath`** with an SVG `d` that encodes the ellipse — `sdk/ui/paint.nim:46`,
     emits `V `, handled at `skia_shim.cpp:1389-1407`. This is the cleanest option and
     it takes real elliptical arcs, not just cubics.
  3. **`circle` scaled** by a `scale(sx, sy)` pair — exact only for an ellipse that needs
     no rotation, and it scales everything else in the `save`/`restore` group too.

```nim
proc ellipse(d: Draw; cx, cy, rx, ry: float32; argb: uint32): Draw =
  ## Four cubics, k = 0.5523. NOT named `ellipse` only because the SDK has no such proc;
  ## this is an app-local helper, not SDK API.
  let kx = rx * 0.5523'f32
  let ky = ry * 0.5523'f32
  result = d.moveTo(cx + rx, cy)
  result = result.curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
  result = result.curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
  result = result.curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
  result = result.curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
  result = result.fill(argb)
```

### SVG paths — works, with one hard rule

`svgPath` **WORKS**. It replays an SVG `d` attribute through `SkParsePath`:

```nim
Draw().svgPath("M0 0 L10 10 Z", 4, 4, 2.0, 0xFF000000'u32)          # filled
Draw().svgPath("M0 0 L10 10 Z", 4, 4, 2.0, 0xFF000000'u32, 1.5)     # stroked
```

Arguments are `(path, x, y, scale, argb, strokeWidth = 0)`. It **fills unless
`strokeWidth > 0`**.

> **Never chunk the `d` string.** `apps/minipaint/PORT-NOTES.md:224-233` records the `V` verb
> being added for a cog whose path is a `Path2D` with relative curves, `H`/`V`, smooth
> curves and **elliptical arcs**. The first attempt chunked the path at a fixed
> column width, cut a number (`a195.425`) across a boundary, and silently lost
> **1,299 characters**. The test now asserts `COG_PATH` is byte-identical.

Because `svgPath` embeds the string in the command stream, a `;` inside it is
escaped automatically, exactly as for `text`.

**Extracting `d` from an HTML `<svg>`:** grep the markup for `<path … d="…">` and
carry the attribute value across as a literal string. Do not reformat it, do not
re-indent it, do not split it.

### Arc traps you cannot see in the command string

Both caught by looking at pixels (`apps/minipaint/PORT-NOTES.md:235-244`, "Two Skia gotchas,
both caught by looking at pixels"). Neither is visible in `.cmds`:

1. **`arcTo` draws nothing at `sweepDeg >= 180`.** Skia's behaviour is undefined
   there. Split it into two 180° arcs, **each with its own `moveTo`**, the second
   starting at 180°.
2. **A lone `A` with no current point renders nothing.** An arc needs a current
   point; start the path with `moveTo` or `lineTo` first.

```nim
proc halfArc(d: Draw; cx, cy, r, a0, a1: float32): Draw =
  result = d.moveTo(cx + r * cos(degToRad(a0)), cy + r * sin(degToRad(a0)))
  result = result.arcTo(cx, cy, r, a0, a1 - a0)

proc drawArc(d: Draw; cx, cy, r, a0, a1: float32): Draw =
  # NOT named `arc` — that collides with std/math.arc at the call site
  # `result = d` (via halfArc) — a helper that drops `d` loses the caller's commands (§2)
  if a1 - a0 >= 180:
    result = halfArc(d, cx, cy, r, a0, a0 + 180)
    result = halfArc(result, cx, cy, r, a0 + 180, a1)   # own moveTo
  else:
    result = d.moveTo(cx + r * cos(degToRad(a0)), cy + r * sin(degToRad(a0)))
    result = result.arcTo(cx, cy, r, a0, a1 - a0)
```

Two naming traps that cost real compiles: **`from` is a Nim keyword** (a parameter
named `from` will not parse), and **`arc` collides with `std/math.arc`** — call it
`drawArc`.

### `fill` then `stroke` — the path is consumed

`case 'F'` runs `path.detach()`, which **consumes** the path. Filling and then
stroking the same commands fills and strokes nothing: the second call sees an empty
path.

**Workaround: replay the path.** Factor the path into a proc and call it twice:

```nim
proc hull(d: Draw): Draw =
  result = d.moveTo(70, 190).lineTo(250, 190).lineTo(225, 215).lineTo(95, 215).close()

d = hull(d).fill(hex(0x1A1A22))       # consumes
d = hull(d).stroke(hex(0xF4E3C1), 2)    # replay it
```

This is also the cleanest illustration of the builder rule: `hull(d)` **replays**;
`d.hull()` does not exist.

One caveat: replaying the path twice changes **translucent** compositing order —
the fill and the stroke composite against different backdrops than they would if they
shared one path — so it is a parity risk for anti-aliased translucent edges. It is
exact for opaque shapes.

### Stroked rounded rectangles

The shim implements a `B` verb (`x y w h radius argb strokeWidth`) — a **stroked**
rounded rectangle. **`paint.nim` exposes no proc for it**, so it is not part of the
API. Reach it only through `svgPath` (a rounded rect as a path) or by
`stroke`-ing a `moveTo`/`lineTo` path.

**`B` is the one verb where a trailing argument sits AFTER a colour. Omit the width
and nothing warns you.** The shim reads the 7th field with `CmdReader::num()`
(`skia_shim.cpp:1188`), which **returns 0 when `strtof` fails**, and `skipSep()`
stops at `end`. So a six-argument `B` yields `setStrokeWidth(0)` — a zero-width
stroke that draws **nothing**, silently, with a plausible-looking score. This cost
`apps/chess` an entire piece rim before it was found (defect E31). If a border is
simply absent, check the argument count before you check anything else.

Also note the border is **stroked on the path**, so a 1px stroke centred on a
fractional coordinate straddles two device pixels at half strength. Chrome *snaps* a
CSS `1px` border to one device pixel with no antialiasing — measured on #75, `x=31`
is at full strength while `x=30` is bare background. Draw the stroke at `.5`
offsets so it lands on a single pixel, and prefer drawing it in the parent's space
rather than inside a layer that is itself blitted at a fractional offset.

### Images are asset-directory-restricted

`image(path, x, y, w, h, fit)` rejects paths with a drive letter, a root path, a
backslash, or `..`. The file has to be inside the app's own directory.

### Summary table

| Want | Status | Do this |
|---|---|---|
| variable-width stroke | **NOT SUPPORTED YET** | overlapping `circle` dabs, or a filled polygon |
| gradient in a Draw list | **NOT SUPPORTED YET** | per-row `rect` + `mix`, or a layer; alpha as a **ramp** |
| drop shadow | **yes, via a layer** | rasterise the silhouette **opaque** into its own `Layer`, `filter(blur, r)`, `fade`, then blit. `Layer.filter` is a **real Gaussian** and is the only route to a CSS `drop-shadow`. Include strokes when you build the silhouette — they are omitted by `:1396-1400` if you forget. **`r` is twice the sigma**: `skia_shim.cpp:1264` is `SkImageFilters::Blur(amount * 0.5f, amount * 0.5f, …)`, so CSS `blur(6px)` is `filter(l, FBlur, 6)` → **sigma 3.0**. Passing the CSS number straight through gives you **half the blur radius you asked for**, which reads as "the blur is too weak" and sends you looking at the wrong thing. |
| text measurement | **NOT SUPPORTED YET** | a hand-built advance table + kerning, or don't measure. `Draw.text` has no `align` either |
| filled polygon | **not a primitive** | `moveTo` / `lineTo` / `close` / `fill` (`paint.nim:28,29,45,53`) |
| axis-aligned ellipse | **WORKS** | the `E` verb takes **two independent semi-axes**: `E cx cy rx ry` → `drawOval` (`skia_shim.cpp:1346`). There is no SDK proc for it, so emit it by hand (`d.add "E ..."`) or use an `svgPath` with elliptical arcs. `circle` (`paint.nim:59-60`) is just this with `r` passed twice. It is **not** special-cased — it goes through the same `colour()` lambda as `F`, `S`, `R`, `B` and `G`, so alpha behaves identically. |
| path clipping | **NOT SUPPORTED YET** | rect `clip` only |
| reset alpha to full | **NOT SUPPORTED YET** | `save` / `restore` only — `O` multiplies |
| per-point stroke width | **NOT SUPPORTED YET** | dabs |
| SVG path | **WORKS** | `svgPath`, never chunk the `d` — this is also the ellipse workaround |
| stroked rounded rect | **WORKS in the shim only** | `B` verb exists (`skia_shim.cpp:1343-1345`) but no `paint.nim` proc emits it; use `svgPath` |
| layers | **WORKS** | `newLayer` / `draw` / `clear` / `filter` / `read` / `write` / `free` |
| raw pixel upload | **WORKS** | `pixels` + `newBuffer`, nearest-neighbour (crisp when scaled) |
| all 28 blend modes | **WORKS** | `blend`, plus `const eraser* = bDstOut` |
| node gradient / shadow | **WORKS** | `fill = linear(...)`, `shadow = shadow(...)` on the node |
| `onCanvasDraw` | **NOT SUPPORTED YET** | `canvas(draw = …)` / `onFrame:` — event 11 is never dispatched |

---

## 9. A complete worked example

A sunset over water, built only from the APIs in this chapter. It uses, deliberately,
one of each idea: a **gradient strip loop** into a layer, a **layer for the static
backdrop**, a second blurred layer for the **reflection**, a **fill-then-stroke path
replay** for the boat, `circle` for the sun, and a **reactive draw list** for what
moves.

```nim
const
  W = 320
  H = 240
  SEA = 150          ## the horizon row
  SUN_X = 210.0'f32
  SUN_Y = 118.0'f32

proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)
  ## Every Draw colour needs its alpha byte — a bare 0xRRGGBB draws nothing (§3).

proc mix(a, b: uint32; t: float32): uint32 =
  ## Two 0xRRGGBB colours mixed by t in 0..1. Alpha is always opaque.
  var v = 0xFF000000'u32
  for sh in 0 .. 2:
    let ca = float32(int((a shr (sh * 8 + 16)) and 0xFF'u32))
    let cb = float32(int((b shr (sh * 8 + 16)) and 0xFF'u32))
    let m = int(ca + (cb - ca) * clamp(t, 0.0'f32, 1.0'f32))
    v = v or (uint32(m and 0xFF) shl (sh * 8 + 16))
  v

proc hullPath(d: Draw): Draw =
  ## The same closed path every time — because fill() consumes it.
  result = d.moveTo(70, 190)
  result = result.lineTo(250, 190)
  result = result.lineTo(225, 215)
  result = result.lineTo(95, 215)
  result = result.close()

proc backdrop(): Draw =
  ## The static half of the picture, drawn ONCE into a layer: a sky that is one
  ## flat rect per row (Draw.fill is flat), and a boat.
  var d: Draw
  for row in 0 ..< SEA:
    d = d.rect(0, row.float32, W.float32, 1,
               mix(0x2B3A67'u32, 0xF2795B'u32, row.float32 / SEA.float32))
  d = d.rect(0, SEA.float32, W.float32, (H - SEA).float32, hex(0x1B2A4A))
  hullPath(hullPath(d).fill(hex(0x1A1A22))).stroke(hex(0xF4E3C1), 2)

proc waterMarks(): Draw =
  ## The reflection on the water: a second layer, blurred once, shown every frame.
  var d: Draw
  d = d.rect((W.float32 - 34) / 2, 0, 34, (H - SEA).float32, 0x40FFD166'u32)
  for i in 1 ..< 12:
    let y = float32(i * (H - SEA) div 12)
    let w = 96.0'f32 - float32(i) * 6.0'f32
    d = d.line((W.float32 - w) / 2, y, (W.float32 + w) / 2, y, 0x70FFD166'u32, 2)
  d

let
  backdropL = newLayer(W, H)
  waterL = newLayer(W, H - SEA)
  lit = state false

backdropL.draw(backdrop())
waterL.draw(waterMarks())
waterL.filter(blur, 3)

proc sunLabel(): string =
  if lit.get: "sun up" else: "sun down"

proc scene(): Draw =
  ## What the canvas shows each time anything changes: layers for what persists,
  ## plain Draw commands for what moves.
  var d: Draw
  d = d.layer(backdropL, 0, 0)
  # the sun rises 40px when it is lit
  d = d.circle(SUN_X, (if lit.get: SUN_Y - 40 else: SUN_Y + 30), 26, 0xFFD166'u32)
  d = d.blend(bScreen).layer(waterL, 0, SEA.float32)
  d = d.text(10, 20, 14, 0xFFFFFFFF'u32, "yantra + skia", 600)

app("Sunset", width = W, height = H, fill = 0x101018):
  column(gap = 8.px, pad = 8.px):
    row(gap = 8.px):
      button @b "toggle sun":
        onClick: lit.set(not lit.get)
      text @s "{sunLabel()}", size = 12
    canvas @view(width = W.px, height = H.px, draw = scene().cmds):
      onPointerDown:
        let (_, my) = pointerPos()
        lit.set(my < 120)
```

### What each part is teaching

| Line | Lesson |
|---|---|
| `mix` | the gradient workaround; alpha stays `0xFF` |
| the `for row` loop | one flat `rect` per row — §8 gradients |
| `hullPath(hullPath(d).fill(…)).stroke(…)` | the replay needed because `fill` consumes the path — §8 |
| `backdropL.draw(backdrop())` once at start-up | layers accumulate and stay; no per-frame rebuild — §4 |
| `waterL.filter(blur, 3)` | a whole-surface **destructive** filter, and how to fake a reflection — §4, §8 |
| `d.blend(bScreen).layer(waterL, 0, SEA)` | the blend applies to the layer composite — §6 |
| `scene()` reads `lit.get` | the reactive draw list — §1 |
| `d.text(10, 20, …)` | `y = 20` is the **top of the line box**, so the ink starts at `20 + 0.375·14 ≈ 25` — §3 |
| `draw = scene().cmds` | hand `.cmds`, never a `Draw` — §1 |

Note that the sun is a `circle`, not an `arcTo` — a sun is a full disc, and a full
disc is exactly the case `arcTo` refuses to draw (§8).

### Verification status — read this

**Built and verified:** the app compiles to wasm with
`tools/build-wasm.sh` (251,696 bytes, no errors). The flat-`Draw` path — `rect`,
`circle`, `text`, state-reactive draw lists — was driven through the real engine via
`render/native/build/mpdrive.exe` and the framebuffer read numerically: a green rect
came back `(0,255,0)`, a red circle `(255,0,0)`, a cyan circle `(0,255,255)`.

**Not verified here, and you should verify before trusting the pixel output:** the
**layer** path in this particular scene. The prebuilt `mpdrive.exe` is dated
`2026-09-30` while `render/native/engine.nim` was last changed `2026-10-02`, and
under it **no layer rendered** — including for the repo's own
`examples/shell/paint.nim`, the fixture that `render/native/t_paint.nim` asserts
works. A stale driver failing a known-good fixture is a driver problem, not a code
problem, so I did not treat it as evidence either way. Rebuilding the engine test
needs the MinGW/Clang C++ toolchain, which is absent from this checkout
(`third_party/msys64/mingw64/include` does not exist).

So: **compile-verified, flat-path render-verified, layer path unverified in this
environment.** The layer claims in §4 rest on `render/native/t_paint.nim`'s own
assertions and `engine.nim:1728-1756`, not on my own measurement.