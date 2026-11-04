# Canvas2D → Skia `Draw`, command by command

Porting a `<canvas>` means rewriting its drawing calls as `Draw` builder calls. This
chapter is the lookup table, and every code line is either quoted from the working
port `apps/typewriter/app.nim` or taken directly from `sdk/ui/paint.nim`.

**Sources for this chapter**

| Source | What it fixes |
|---|---|
| `sdk/ui/paint.nim` (124 lines, read in full) | every `Draw` proc, its exact arity, the `Blend` and `Filter` enums, `eraser`, and the `Layer` API |
| `apps/typewriter/app.nim` | the ported program itself — 1033 lines that build clean |
| `apps/typewriter/029-typewriter-letters.html` | the source page the port came from |
| `apps/minipaint/ENGINE-ISSUES.md:582-586`, `reference/16` §3.2-3.4 | the `math.round` trap and the `float64` trap |

## 0. The whole API, in the order you will need it

`Draw` is one object with a single exported field, `cmds: string` (`paint.nim:11-12`).
Every proc below returns a **new** `Draw`; nothing mutates in place. The command
letters are what ends up in `cmds` (the format the Skia shim parses, `paint.nim:12`).

| Draw proc | Command | Signature, verbatim from `paint.nim` |
|---|---|---|
| `moveTo` | `M` | `(d: Draw; x, y: float32): Draw` — `:28` |
| `lineTo` | `L` | `(d: Draw; x, y: float32): Draw` — `:29` |
| `quadTo` | `Q` | `(d: Draw; cx, cy, x, y: float32): Draw` — `:30` — "Corner arc, matching canvas `quadraticCurveTo`" |
| `curveTo` | `C` | `(d: Draw; cx1, cy1, cx2, cy2, x, y: float32): Draw` — `:35` — "matching canvas `bezierCurveTo`" |
| `arcTo` | `A` | `(d: Draw; cx, cy, radius, startDeg, sweepDeg: float32): Draw` — `:40` — "matching canvas `arc()`. Angles in degrees, clockwise" |
| `close` | `Z` | `(d: Draw): Draw` — `:45` |
| `svgPath` | `V` | `(d: Draw; path: string; x, y, scale: float32; argb: uint32; strokeWidth = 0'f32): Draw` — `:46` |
| `fill` | `F` | `(d: Draw; argb: uint32): Draw` — `:53` |
| `stroke` | `S` | `(d: Draw; argb: uint32; width: float32): Draw` — `:55` — "round joins and caps: a brush" |
| `rect` | `R` | `(d: Draw; x, y, w, h: float32; argb: uint32; radius = 0'f32): Draw` — `:57` |
| `circle` | `E` | `(d: Draw; cx, cy, r: float32; argb: uint32): Draw` — `:59` |
| `line` | `G` | `(d: Draw; x1, y1, x2, y2: float32; argb: uint32; width = 1'f32): Draw` — `:61` |
| `text` | `T` | `(d: Draw; x, y, size: float32; argb: uint32; s: string; weight = 400): Draw` — `:63` |
| `image` | `I` | `(d: Draw; x, y, w, h: float32; file: string): Draw` — `:65` |
| `layer` | `Y` | `(d: Draw; l: Layer; x, y: float32; w = 0'f32; h = 0'f32): Draw` — `:67` |
| `pixels` | `X` | `(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32; h = 0'f32): Draw` — `:70` |
| `blend` | `b` | `(d: Draw; mode: Blend): Draw` — `:73` |
| `save` / `restore` | `P` / `p` | `(d: Draw): Draw` — `:75-76` |
| `translate` / `scale` / `rotate` | `t` / `s` / `o` | `(d: Draw; …: float32): Draw` — `:77-79` |
| `alpha` | `O` | `(d: Draw; a: float32): Draw` — `:80` |
| `clip` | `K` | `(d: Draw; x, y, w, h: float32): Draw` — `:81` |

Floats are serialised to **two decimals by hand** (`paint.nim:23-26`) because the
sandbox C library cannot format them. So sub-0.01-pixel precision does not survive the
round trip — do not build anything that depends on it.

### Setting up a canvas and repainting it

```nim
var scene: Node                        # the canvas, so handlers can repaint    app.nim:691
var sceneReady = false                 #                                          app.nim:692

proc repaint() =
  if sceneReady:
    scene.set(pDraw, buildScene())     # app.nim:698-700

# in main(), after the canvas exists:
scene = canvas(page, int32(SW), int32(SH - HEAD))   # app.nim:1010
sceneReady = true                                    # app.nim:1011
scene.set(pDraw, buildScene())                       # app.nim:1012
```

Two things worth stealing:

- The `sceneReady` flag (`app.nim:692, 1011`). `repaint()` is called from key and click
  handlers; a handler registered before the canvas exists would otherwise write to a
  node id of `-1`.
- `pDraw` takes the string itself — there is no `d.cmds` accessor call to forget:
  `proc set*(node: Node; prop: Prop; value: string)` (`sdk/core/runtime.nim:138`).

## 1. Paths and shapes

```nim
# ctx.fillRect(x, y, w, h)
d = d.rect(0, 0, w, h, cBody)                                    # app.nim:127

# ctx.strokeRect(x, y, w, h) with a uniform radius
# -> two commands: fill, then stroke the same path
d = d.svgPath(P_SHELL, cx(0), by(0), U, cEnamel)
d = d.svgPath(P_SHELL, cx(0), by(0), U, cRed, 2.0'f32 * U)

# ctx.beginPath / moveTo / lineTo / stroke
d = d.save().moveTo(x, y)
     .quadTo(x + cos(a + 0.6'f32) * l * 0.5'f32, y + sin(a + 0.6'f32) * l * 0.5'f32,
             x + cos(a) * l, y + sin(a) * l)
     .stroke(c, lw).restore()                                    # app.nim:267-270

# ctx.arc(cx, cy, r, startRad, endRad)  -> degrees, clockwise
d = d.arcTo(cx, cy, r, startDeg, sweepDeg)                       # app.nim:222

# ctx.fillStyle = c; ctx.arc(cx, cy, r, 0, 2π)  -> the circle primitive
d = d.circle(bx, by, br * (1.0'f32 - f), rgba(255, 200, 130, 0.014))   # app.nim:219
```

**No ellipse primitive.** `circle` takes one radius. For `ctx.ellipse(x, y, rx, ry, …)`
the port builds SVG path data and lets Skia's path parser do the arc — this is the
single most reusable helper in the whole port (`app.nim:385-389`):

```nim
proc ellipsePath(x, y, rx, ry: float32): string =
  ## An <ellipse> as path data, so Draw.svgPath can fill it. Skia parses arcs.
  "M" & $(x - rx) & " " & $y &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(rx * 2.0'f32) & " 0" &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(-rx * 2.0'f32) & " 0Z"
```

It is then used exactly like any other path (`app.nim:474-476`):

```nim
d = d.svgPath(ellipsePath(cxp, 30, 78, 23), cx(0), by(0), U, 0xFFB3BABE'u32)
d = d.svgPath(ellipsePath(cxp, 29, 66, 17), cx(0), by(0), U, 0xFF231F1D'u32)
d = d.svgPath(ellipsePath(cxp, 29, 11,  4), cx(0), by(0), U, 0xFFC9CED1'u32)
```

That is how the 45 typewriter key caps get their chrome rim, cream cap and red shifted
legend from three concentric ellipses each (`app.nim:542-550`).

### Multiple sub-paths: `beginPath` → `moveTo`

Canvas starts a new sub-path on `beginPath()`. `Draw` has no such call — a `moveTo`
followed by a `lineTo` chain starts one, and a second `moveTo` starts another:

```nim
var wdeg = 0.0'f32
while wdeg < 360.0'f32:
  let px = cos(wdeg * 0.017453'f32) * 122.0'f32
  let py = sin(wdeg * 0.017453'f32) *  40.0'f32 - 8.0'f32
  if wdeg == 0: d = d.moveTo(px, py) else: d = d.lineTo(px, py)
  wdeg += 4.0'f32
d = d.close().stroke(rgba(122, 106, 74, 0.045), 1.0'f32).restore()   # app.nim:286-292
```

That `if wdeg == 0` guard is the idiom for "move on the first point, line after". Note
`0.017453` = degrees → radians, used inline because there is no constant worth
importing for a single multiply.

### One width per path

`stroke()` takes exactly one `width` (`paint.nim:55`) and applies it to the whole path
so far. A canvas path with two widths is two `Draw` values:

```nim
d = d.moveTo(px, cy(88.5)).lineTo(px, cy(101)).stroke(cRed, 1.6'f32 * U)   # app.nim:583
```

If the source drew sub-paths with different widths in one `beginPath()`, split them.

### Text

`d.text(x, y, size, argb, s, weight = 400)` (`paint.nim:63`). There is no font-family
parameter — `weight` is the only axis, and it is a raw number.

```nim
d = d.text(cx(486), by(111), 20.0'f32 * U, 0xFFE9EEF0'u32, "Marlowe", 400)   # app.nim:484
d = d.text(x, y + ty * U + dy + r * 0.35'f32 * U, fs * U, 0xFF2B2724'u32, label, 700)  # app.nim:561
```

The string is escaped internally for the command separator (`paint.nim:64`:
`s.replace(";", "\\;")`), so a label may contain `;` but not be relied on for it.

#### ⚠ Where `y` actually lands — measured, and it is not the baseline

Canvas puts `y` on the **baseline** (`ctx.textBaseline = 'alphabetic'` is the
default). Yantra does not. `Draw.text` ends up in `yk_text_draw`, which calls
`p->paint(canvas, x, y)` on an `SkParagraph`
(`libs/nimskia/src/skia_shim.cpp:291`) — so **`y` is the top of the paragraph
line box**. The doc comment on the native side says "Draws `s` with its top-left
at (x, y)" (`libs/nimskia/src/nimskia.nim:76`), and that comment is **wrong**; it
is the direct cause of mis-positioned text across the ports.

Offsets from the `y` you pass, in units of font size `S`:

| feature | lands at |
|---|---|
| cap / ascender ink top | `y + 0.375·S` |
| x-height top | `y + 0.583·S` |
| **baseline** | **`y + 1.0833·S`** |
| descender bottom | `y + 1.333·S` |

**MEASURED at S = 12, 24 and 48 with two independent strings — not documented.**
Empirical for the **default typeface and weight only**; a port that sets a
family or a non-default weight must re-probe before trusting these ratios.

The conversion every port needs:

```nim
proc yantraY(baselineY, size: float32): float32 = baselineY - 1.0833'f32 * size
```

and for `ctx.textBaseline = 'top'` (ink top at `Y`): `yantra_y = Y - 0.375 * size`.

That is exactly where the `r * 0.35'f32 * U` fudge on `app.nim:561` above comes
from — it compensates, by eye, for an origin the SDK never documented. Now that
the ratio is known, write `yantraY(...)` and drop the fudge.

**There is also no text measurement in the SDK.** `Draw.text` returns `Draw` and
nothing else (`paint.nim:63`) and has no `align` parameter; `measureText` exists
only on the native side (`libs/nimskia/src/nimskia.nim:68`, `:122`). Centring,
right-alignment and wrapping all have to be estimated.

## 2. Transforms

| Canvas | Yantra | Note |
|---|---|---|
| `ctx.translate(x, y)` | `d.translate(x, y)` | value-returning: `d = d.translate(...)` |
| `ctx.scale(x, y)` | `d.scale(sx, sy)` | `sy` defaults to `0'f32` (`paint.nim:78`), and the shim reads `y == 0` as "uniform" (`skia_shim.cpp:1410`: `cv->scale(x, y == 0 ? x : y)`) — so `d.scale(2)` *is* `d.scale(2, 2)`. Passing both is still clearer. |
| `ctx.rotate(rad)` | `d.rotate(degrees)` | **degrees**, and the arc angles are degrees too, so radians appear only in `sin`/`cos` |
| `ctx.save()` / `ctx.restore()` | `d.save()` / `d.restore()` | also value-returning |

```nim
dd = dd.scale(2.0'f32, 2.0'f32).translate(px, py).rotate(rot * 57.29578'f32)  # app.nim:334
```

`rot * 57.29578'f32` is radians → degrees, inlined. `app.nim:334` draws one glyph plate;
`app.nim:237` scales the whole paper layer 2× (`d = d.scale(2.0'f32, 2.0'f32)`), which
is how the port matches the source's `devicePixelRatio`-sized canvas without a
`devicePixelRatio` concept existing anywhere in Yantra.

## 3. Clipping

```nim
d = d.clip(x, y, w, h)     # paint.nim:81 — save()/restore() it like any transform
```

Used sparingly in the port. When a clipping region is static, the cleaner Yantra
answer is a `Layer` sized to the region and a `d.layer(l, x, y)` blit, because the
layer *is* already cropped.

## 4. Alpha: `globalAlpha` and `rgba(...)`

Three tools, all real:

```nim
d = d.alpha(0.45)                                   # scoped, paint.nim:80
d = d.rect(x, y, w, h, withA(cEnamel, 0.45))        # per-command, via the colour
d = d.circle(x, y, r, rgba(255, 200, 130, 0.014))   # a helper that builds ARGB
```

The port has one helper for the second, which is the cheapest way to keep alpha out of
the command string:

```nim
proc withA(c: uint32; a: float32): uint32 =                    # app.nim:381-383
  (c and 0x00FFFFFF'u32) or
    (uint32(clamp(int32(a * 255.0'f32 + 0.5'f32), 0'i32, 255'i32)) shl 24)
```

and one for the third, used for every `rgba(r, g, b, a)` in the source:

```nim
proc rgba(r, g, b: int32; a: float32): uint32 =                # app.nim:67-70
  proc q(v: int32): int32 = clamp(v, 0'i32, 255'i32)
  result = (uint32(q(int32(a * 255.0'f32 + 0.5'f32))) shl 24) or
           (uint32(q(r)) shl 16) or (uint32(q(g)) shl 8) or uint32(q(b))
```

Note the nested `proc q` inside `rgba`: Nim allows it, it is evaluated per call, and it
keeps the clamping in one place. `clamp` comes from `import std/math` (`app.nim:16`).

**Alpha 0 is a real 0 in `Draw`** (unlike node colours, where `style.nim:23-27` clamps
alpha to 1..255 so that a transparent colour stays distinguishable from an opaque
`0x000000`). `d.rect(0, 0, SW, SH, 0x00000000'u32)` at `app.nim:661` is a genuine no-op
fill, used to punch the page background through.

## 5. Composite operations

`d.blend(mode)` (`paint.nim:73`) takes any of the 29 Skia modes declared at
`paint.nim:14-17` — `bClear, bSrc, bDst, bSrcOver, bDstOver, bSrcIn, bDstIn, bSrcOut,
bDstOut, bSrcATop, bDstATop, bXor, bPlus, bModulate, bScreen, bOverlay, bDarken,
bLighten, bColorDodge, bColorBurn, bHardLight, bSoftLight, bDifference, bExclusion,
bMultiply, bHue, bSaturation, bColor, bLuminosity`.

| `ctx.globalCompositeOperation` | Yantra |
|---|---|
| `'multiply'` | `d.blend(bMultiply)` |
| `'screen'` | `d.blend(bScreen)` |
| `'overlay'` | `d.blend(bOverlay)` |
| `'difference'` | `d.blend(bDifference)` |
| `'destination-out'` | `d.blend(eraser)` — `const eraser* = bDstOut` (`paint.nim:21`) |
| `'source-over'` (the default) | nothing to write |
| `'lighter'` / `'plus-lighter'` | `d.blend(bPlus)` — see below for the premultiplied case |

`blend` is also how a `Layer` is cleared — see §9.

### The `bPlus` / `plus-lighter` case — CLOSED in source

**What the blend "lambda" actually is.** There is no lambda and no per-op colour maths.
`Draw.blend` (`sdk/ui/paint.nim:73`) appends the literal bytes `"b <ordinal>;"` to the command
string, and `runCmds` reads it in one line —
`libs/nimskia/src/skia_shim.cpp:1366`:

```cpp
case 'b': { int m = (int)r.num(); if (m >= 0 && m <= (int)SkBlendMode::kLastMode) blend = (SkBlendMode)m; break; }
```

It stores the value in a local `SkBlendMode blend` (`skia_shim.cpp:1309`) that is stamped onto
the paint of every **subsequent** op (`skia_shim.cpp:1326` `paint.setBlendMode(blend)`), and it is
saved/restored around `save`/`restore` (`skia_shim.cpp:1364-1365`). There is no lookup table:
the SDK enum's ordinal **is** cast straight to `SkBlendMode`, which is why `sdk/ui/paint.nim:14`
declares `Blend` as "Skia's blend modes, in its order". `bClear = 0` … `bLuminosity = 28`, and
the bounds check rejects anything outside that.

**The premultiplied case.** Yantra does **no** premultiplication and **no** clamping of its own.
Colours reach the paint as straight, non-premultiplied 8-bit ARGB —
`skia_shim.cpp:1327`: `auto colour = [&](unsigned argb) { paint.setColor(SkColor(argb)); if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha); };`
— and the blend arithmetic is entirely Skia's. So:

- **Fully opaque source and destination: `bPlus` is exactly what `plus-lighter` does.** The
  `alpha < 1` branch is not taken, and additive compositing of opaque colours is the same
  operation in both. Use it without hesitation.
- **Source colour with alpha < 255: not bit-identical to the canvas spec.** Canvas2D defines
  `plus-lighter` on non-premultiplied components with the result alpha forced to 1, whereas
  Skia's `kPlus` operates inside Skia's premultiplied pipeline. I did **not** read Skia's header
  to restate the difference component by component — `third_party/skia-src-m143` contains no
  headers in this checkout (7 files, all under `src/`), so I cannot quote it. If your port
  accumulates translucent glows with `plus-lighter`, render one and compare; do not assume the
  two are interchangeable.

**One more difference worth knowing.** `b` applies from the next op onward and is *not* scoped to
a single command, unlike canvas, where `globalCompositeOperation` is a canvas-wide state you
reset. A `blend` you forget to undo colours every later stroke on that `Draw`.

## 6. `ctx.filter` → layer filters

There is **no per-command filter**. `ctx.filter = 'blur(4px)'` becomes: draw into a
`newLayer`, then filter the layer in place.

```nim
type
  Layer* = distinct int32                     # paint.nim:13
  Filter* = enum
    blur, brightness, contrast, saturation, invert, greyscale, sepia, fade   # paint.nim:18-19

proc newLayer*(w, h: int): Layer                       # paint.nim:102
proc draw*(l: Layer; d: Draw)                          # paint.nim:107
proc clear*(l: Layer)                                  # paint.nim:110
proc filter*(l: Layer; kind: Filter; amount = 1'f32)   # paint.nim:111
proc read*(l: Layer; x, y, w, h: int): seq[byte]       # paint.nim:114
proc write*(l: Layer; x, y, w, h: int; rgba: openArray[byte])   # paint.nim:120
proc free*(l: Layer)                                   # paint.nim:124
```

`amount` units, per the `filter` doc comment (`paint.nim:112-113`): **blur in px**,
brightness −1..1, contrast / saturation 1 = unchanged, fade 0..1.

```nim
paperLayer = newLayer(int(PW * 2.0), int(PH * 2.0))   # app.nim:928
paperLayer.filter(blur, 3.0'f32)                       # e.g. a soft shadow layer
```

Two important properties:

- `Layer.draw` is **one-shot and cumulative** (`paint.nim:108`): "Draws into the layer
  once; it stays there (strokes accumulate)." This is what makes a `Layer` the right
  home for anything static *and* the right home for anything that accumulates (a
  paint program, a simulation).
- `filter` is **in place** and destructive. Filter a throwaway layer, never the one you
  still need sharp.

## 7. Gradients — the one thing `Draw` cannot do

**`Draw` has no gradient primitive.** There is no `createLinearGradient`, no
`createRadialGradient`, no shader, no gradient stop list in `paint.nim`. This is the
single biggest gap in the Canvas2D mapping, and it is a *different* situation from a
CSS gradient on a node (see `CSS-SHADOWS-AND-EFFECTS.md` §1 — a node **does** have a
2-stop linear gradient, `panel(fill = linear(a, b, 90))`).

Two substitutions, both used in `app.nim`.

### 7a. Linear → a stack of flat bands

The source's 2-stop vertical gradient over a plank becomes 12 bands, each a flat fill
whose colour is interpolated by hand (`app.nim:138-152`):

```nim
# plank body: the source's 2-stop vertical gradient, as 12 bands
var band = 0
while band < 12:
  let f = band.float32 / 11.0'f32
  let cA = t[0] + 6
  let cB = t[0] - 8
  let cC = t[1] + 4
  let cD = t[1] - 6
  let cE = t[2] + 2
  let cF = t[2] - 4
  d = d.rect(0, y + ph * f, w, ph / 12.0'f32 + 1.0'f32,
             rgba(cA + int32((cB - cA).float32 * f),
                  cC + int32((cD - cC).float32 * f),
                  cE + int32((cF - cE).float32 * f), 1.0))
  inc band
```

The `+ 1.0'f32` on the band height is deliberate and load-bearing: bands are placed at
`f * ph` and are `ph/12` tall, so a 1 px overlap hides the seam that two-decimal
float serialisation (`paint.nim:23-26`) would otherwise open between them. **Every
banded fill in a port needs this overlap.**

For a *small* shape — a few hundred pixels tall — 3 bands are enough, and the port has a
helper that reproduces a 3-stop gradient by dropping the end stops in from above and
below the mid stop (`app.nim:391-397`):

```nim
proc gradShape(d: var Draw; path: string; x, y, sc: float32; top, mid, bot: uint32) =
  ## The source fills these paths with a real vertical linear gradient. Draw has
  ## no gradient primitive, so: the mid stop flat, then the top stop dropped in
  ## from above and the bottom stop from below — the same stops, same direction.
  d = d.svgPath(path, x, y, sc, mid)
  d = d.svgPath(path, x, y - sc * 7.0'f32, sc, withA(top, 0.45))
  d = d.svgPath(path, x, y + sc * 5.0'f32, sc, withA(bot, 0.40))
```

Used for the platen, the side cheek, the shell and the deck (`app.nim:411, 458-461`).
It is cheap, it is directionally correct, and it is *not* a gradient — at close range it
shows three bands. For a large area, go back to 12+ bands.

### 7b. Radial → concentric rings

`ctx.createRadialGradient` becomes a stack of shrinking circles, alpha falling off with
radius (`app.nim:198-211`):

```nim
# lamplight from the upper left — 26 concentric rings, additive
let lx = w * 0.18
let ly = -h * 0.12
let lr = sqrt(w * w + h * h) * 0.95'f32
var s = 0
while s < 26:
  let f = s.float32 / 25.0'f32
  let a = (1.0'f32 - f) * (if f < 0.37'f32: 0.36'f32
                 elif f < 0.78'f32: 0.10'f32 else: 0.30'f32)
  let c = if f < 0.37: rgba(255, 214, 150, a)
          elif f < 0.78: rgba(255, 190, 120, a)
          else: rgba(12, 5, 1, a)
  d = d.circle(lx, ly, lr * (1.0'f32 - f), c)
  inc s
```

Read it as: the light's core is 26 translucent discs of decreasing radius, each so
faint they stack into a falloff. The three alpha regimes (0.36 core, 0.10 mid,
0.30 warm rim) are a transcription of the source's stop list, and they are **data** —
change the numbers to change the light.

The same trick, cheaper, for a soft shadow (`app.nim:663-668`):

```nim
var e = 0
while e < 14:
  let f = e.float32 / 13.0'f32
  d = d.circle(MX + MW / 2.0, MY + 300.0'f32 * U, MW * 0.56 * (1.0'f32 - f * 0.4),
           rgba(12, 6, 2, 0.05))
  inc e
```

**Cost:** these loops run once, into a `Layer`. They are the reason the desk is
`deskLayer.draw(d)` (`app.nim:228`) and never rebuilt per frame. Never emit 26 rings
inside `buildScene()`.

## 8. PRNG transcription — make the port deterministic

A page whose art uses `Math.random()` will not port reproducibly: every run differs,
every screenshot diff is noise, and re-opening a saved document re-randomises it.
The fix is to transcribe the page's own generator, seed it from something stable, and
store the seed with the data.

The page's was `mulberry32`. Here it is, line for line (`app.nim:49-61`):

```nim
type Rng = object
  a: uint32

proc rngInit(seed: int32): Rng = Rng(a: uint32(seed) and 0x7FFFFFFF'u32)

proc nextF(r: var Rng): float32 =
  r.a = r.a + 0x6D2B79F5'u32
  var t = r.a
  t = (t xor (t shr 15)) * (1'u32 or t)
  t = t + ((t xor (t shr 7)) * (61'u32 or t)) xor t
  result = (t xor (t shr 14)).float32 / 4294967296.0'f32

proc irnd(r: var Rng; n: int32): int32 = int32(r.nextF() * n.float32)
```

Notes that matter when transcribing any PRNG:

- `0xFFFFFFFF'u32` and `4294967296.0'f32` are literal because there is no `2^32` and no
  `float64`. Every constant is spelled in the target width.
- `1'u32 or t` and `61'u32 or t` are JS's `|1` and `|0` written as Nim `or` — JS coerces
  to a 32-bit **signed** int, Nim's `or` on `uint32` is unsigned. The results agree for
  the low bit pattern this generator depends on; a different generator may not.
- **One seed per visual element, not one seed for the scene.** `Stroke` carries its own
  `seed` (`app.nim:73-77`), assigned at keystroke time
  (`app.nim:734: seed: (int32(nowMs) + seedCounter * 7919) and 0x7FFFFFFF`) and used to
  rebuild that one stamp (`app.nim:317: var r = rngInit(s.seed)`).

That last point is the reason a restored letter looks *the same*: `redrawAll()`
(`app.nim:342-344`) repaints the paper from the sheet number and re-stamps every stroke
from its own seed. Re-running `nextF` in a different order — or from one shared
generator — would give every letter a different set of imperfections on reload.

> **Nim trap: `for x in seq` iterates copies.** `redrawAll` works because
> `for st in strokes: stampOne(st)` only *reads*. Anything that *writes* must index:
> `for i in 0 ..< motes.len: motes[i].y = motes[i].y - 0.00064'f32 * motes[i].s`
> (`app.nim:643`). Writing `for m in motes: m.y -= …` gives
> `Error: type mismatch … expression 'm.y' is immutable, not 'var'`.

If the source page used `Math.random()` directly rather than a named PRNG, seed a
single generator once per paint pass and **capture the outputs into your own data** at
port time, or accept that the art differs per run and say so.

## 9. Layers: paint once, blit per frame

The mental model that made the typewriter tractable:

| Page concept | Yantra |
|---|---|
| a static background that never changes | `newLayer` + `paintDesk()` once, then `d.layer(deskLayer, 0, 0)` every frame (`app.nim:660`) |
| a canvas you keep painting into (a document, a paint app) | a `Layer` you `draw` into repeatedly — strokes accumulate |
| a region that must be moved as a unit (the sheet in the platen) | a `Layer`, blitted with an offset and scale (`app.nim:617`) |
| `ctx.clearRect` on a layer | `layer.clear()` — implemented as `blend(bClear)` + a huge rect (`paint.nim:110`) |

```nim
var deskLayer: Layer            # app.nim:114
var paperLayer: Layer            # app.nim:115

deskLayer.clear()                # app.nim:227
deskLayer.draw(d)                # app.nim:228
```

`d.layer(l, x, y, w = 0, h = 0)` (`paint.nim:67`) draws the layer at its own size
unless `w`/`h` are given. The paper is blitted scaled down to fit the machine
(`app.nim:617`):

```nim
d = d.layer(paperLayer, x0, paperY, PW * S, PH * S)
```

**Per-frame cost budget.** `buildScene()` (`app.nim:658-688`) assembles the whole
scene as one string every frame. Its cost is proportional to the *command count*, not
to the pixels of anything cached in a layer. Moving expensive work into a
`Layer` — the desk (`app.nim:122-228`), the paper (`app.nim:231-306`) — is the
difference between a scene that runs and one that does not.

## 10. `drawImage` and raw pixels

| Canvas | Yantra |
|---|---|
| `ctx.drawImage(img, x, y, w, h)` | `d.image(x, y, w, h, "file.png")` (`paint.nim:65`) |
| `ctx.drawImage(offscreenCanvas, …)` | `d.layer(l, x, y, w, h)` (`paint.nim:67`) |
| `ctx.getImageData` | `layer.read(x, y, w, h): seq[byte]` RGBA (`paint.nim:114`) |
| `ctx.putImageData` | `layer.write(x, y, w, h, rgba)` (`paint.nim:120`), or `d.pixels(buf, pw, ph, x, y, w, h)` (`paint.nim:70`) |

There is no filesystem: the app never names a path it does not declare, and the host
resolves assets from the app's own folder (`reference/17-pitfalls.md`, the
`@pstd@ssyncio.nim.c` row). `layer.read` returning a short buffer sets `result.len` to
0 (`paint.nim:119`) — treat an empty seq as "nothing there", never index it.

## 11. The traps, collected

Everything here is in `SKILL.md` §"Nim traps" with the measured error text. The three
that specifically bite Canvas2D ports:

1. **`d = d.something(...)`, never `d.something(...)`.** The bare form is not a
   compile error — it compiles and draws nothing. This is the one that costs an hour.
2. **`round` from `std/math` builds fine and faults at run time.** mini-libc's `round`
   is recursive, so a per-pixel loop overflows the stack. Use the port's `rnd32`
   (`app.nim:64`): `int32(if x < 0: x - 0.5 else: x + 0.5)`.
3. **`float64` compiles and is silently wrong on wasm32.** `1.0` in a `float32`
   expression is fine; a stray `float64` in a pixel loop produces correct-looking
   output that is wrong on a large fraction of inputs
   (`reference/16` §3.3). Write `1.0'f32` in art maths, as `app.nim` does everywhere.