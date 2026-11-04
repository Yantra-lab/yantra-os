# CSS shadows and effects → Yantra

Gradients, `box-shadow`, `border-radius`, `opacity`, blend modes and filters. For each:
**what Yantra can do, what it cannot, and the workaround that was actually used.**

**The thing to understand first.** A CSS property does not have *one* Yantra answer.
It has two, and they have almost nothing in common:

| | **Layer 1 — a node** | **Layer 2 — a `Draw` command** |
|---|---|---|
| What paints it | the native engine, into a rounded rectangle | Skia, through your command string |
| Who owns the props | the wire protocol (`sdk/core/wire.nim`) | `sdk/ui/paint.nim` |
| Gradients | **yes** — 2 stops, linear | **no primitive at all** |
| Drop shadow | **yes** — offset + blur + colour | **no primitive** |
| Blur / saturate / brightness | **yes** — node props | **yes**, but only on a whole `Layer` |
| Blend modes | **yes** — all 29 Skia modes | **yes** — all 29 |
| Anything is a gradient | no: it is a rect with a radius | yes: any path |

So the first question for every effect is **which layer is the thing on**. A shadow on
a `panel` is one function call; the same shadow drawn inside a canvas is a loop.

**Sources:** `sdk/ui/style.nim` (55 lines, read in full), `sdk/core/wire.nim` (prop and
event enums), `sdk/ui/paint.nim` (read in full), `examples/shell/fx.nim` (53 lines —
a compiling poster of gradients, glass, glow, blends and colour filters),
`apps/typewriter/app.nim` (the ported page), `reference/15a-html-css-mapping.md` §2.4,
§2.5, §3 and `reference/16` §3.

---

## 1. Gradients

### 1a. On a node — two stops, linear, one angle

The entire gradient model is this (`sdk/ui/style.nim:6-10, 29, 38-41`):

```nim
type
  Gradient* = object
    ## `fill = linear(0xFF7A2F, 0xFFD28A, 135)`: from, to, angle in degrees (90 = top to bottom).
    a*, b*: int
    angle*: float32

proc linear*(a, b: int; angle = 90.0): Gradient = Gradient(a: a, b: b, angle: float32(angle))

proc setFill*(n: Node; g: Gradient) =
  n.set(pGradFrom, wireI32(g.a))
  n.set(pGradTo, wireI32(g.b))
  n.set(pGradAngle, g.angle)
```

Three wire props: `pGradFrom = 108`, `pGradTo`, `pGradAngle = 110`
(`wire.nim:164-166`). Real usage, from a file that compiles:

```nim
panel(width = 150.px, height = 100.px, radius = 14, fill = linear(0xFF006E, 0x3A86FF, 45))  # fx.nim:42
panel(width = 120.px, height =  84.px, radius = 12, fill = linear(0x2F80ED, 0xF2C94C, 0))   # fx.nim:19
slide(fill = linear(bg, surface2, 135), pad = 90.px, justify = center, gap = 22.px, radius = 6,
      shadow = shadow(y = 10, blur = 30, color = rgba(0x000000, 0.35)))                     # pitch.nim:20-21
```

**What you get:** two colours, one linear angle, clipped to the node's rounded rect
(the radius is passed into the gradient, so `radius = 14` + `linear(…)` is the rounded
gradient card).

**What you do not get, and the workaround for each:**

| CSS | Status | Workaround |
|---|---|---|
| `linear-gradient(to bottom, A, B)` | supported | `linear(A, B)` — the angle defaults to 90 = top→bottom (`style.nim:29`), which is what `to bottom` means |
| 3+ stops (`A 0%, B 50%, C 100%`) | **not supported** | an **SkSL shader** (§1c), or stack 2-stop nodes on top of each other in a `stack` |
| explicit stop positions (`B 20%`) | **not supported** | same — the two stops are implicitly 0 % and 100 % |
| `transparent` stop | supported | `linear(rgba(A, 0), A)` — and note `style.nim:23-27` clamps alpha to **1..255**, so a fully transparent stop is really 1/255, "almost clear", never exactly 0 |
| `radial-gradient(…)` | **not supported** | SkSL shader, or (in a canvas) concentric rings — `HTML5-CANVAS-TO-SKIA.md` §7b |
| `conic-gradient(…)` | **not supported** | SkSL shader |
| `repeating-*` | **not supported** | SkSL shader |
| a gradient as a **hover** fill | **a compile error — you cannot write it** | a state block types `fill` as **int32** (`sdk/ui/dsl.nim:234`, `of "fill": ("Fill", "int32")`), so `hover: fill = linear(A, B)` fails with `type mismatch: got 'Gradient' ... but expected 'int'`. You never reach a runtime "skipped" branch. Use a solid in the state block (`reference/15a` §3) |
| switching a gradient off | supported | set a plain colour — `setFill(n, c)` writes `pGradAngle = -1` (`style.nim:34-36`) |
| `deg`/`rad`/`turn` units | degrees only | write the number; `units.nim` has no `turn` |

> **The angle: `Yantra angle = CSS angle − 90`**, so **Yantra 0 = left→right**.
> Settled in source, not a guess: `libs/nimskia/src/skia_shim.cpp:431-437` draws the
> gradient from `centre − (cos a·w/2, sin a·h/2)` to `centre + (…)`, so `a = 0` runs
> left→right and `a = 90` runs top→bottom; CSS `0deg` is *to top*, which is `a = 270`.
> Confirmed by the passing assertion in `libs/nimskia/tests/t_skia.nim:54-56` (angle 0,
> red at x=1 and blue at x=62). So CSS `45deg` (`to top right`) is Yantra **315**,
> not 45. `examples/shell/fx.nim`'s `0`, `45` and `135` are Yantra angles, not CSS
> angles — convert with −90 before copying them into CSS.

### 1b. In a canvas — no gradient primitive, ever

There is no gradient in `sdk/ui/paint.nim`. There is no `shader` on a `Draw` command
either. If the effect lives inside a canvas it becomes arithmetic:

- **Linear over a big area** → a stack of bands with 1 px overlap
  (`HTML5-CANVAS-TO-SKIA.md` §7a; the desk planks, `app.nim:138-152`).
- **Linear over a small shape** → three fills of the same path, from `gradShape()`
  (`app.nim:391-397`) — the platen, the shell, the deck (`app.nim:411, 458-461`).
- **Radial** → concentric translucent rings (`app.nim:198-211`).
- **Edge darkening / vignette** → a few nested rectangles with falling alpha
  (`app.nim:294-303`, and the toast's fade-in-out at `app.nim:685`).

**These loops are a frame-budget cost.** Everything above moved into a `Layer` painted
once (`app.nim:227-228, 305-306`) rather than into `buildScene()`. Keep it that way.

### 1c. The honest answer for anything complicated: SkSL

There is a real escape hatch on **nodes**: a SkSL shader prop (`sdk/ui/style.nim:49-52`):

```nim
template sksl*(src: static string): string =
  ## `shader = sksl"""…"""`: SkSL for the engine's GPU-class shaders (docs/spec/style.md §8).
  ## The shader may declare `uniform float2 size;` (its box) and `uniform float time;` (s).
  src
```

used as a normal prop (`examples/shell/fx.nim:4-15, 25`):

```nim
const aurora = sksl"""
uniform float2 size;
uniform float time;
half4 main(float2 p) {
  float2 uv = p / size;
  float a = 0.5 + 0.5 * sin(uv.x * 6.0 + time * 0.8);
  float b = 0.5 + 0.5 * sin(uv.y * 5.0 - time * 0.6 + uv.x * 3.0);
  half3 c = mix(half3(0.04, 0.04, 0.10), half3(0.22, 0.10, 0.52), half(a));
  c = mix(c, half3(0.95, 0.45, 0.12), half(b * uv.y * 0.55));
  return half4(c, 1);
}
"""
# ...
panel @aurora(width = 1000.px, height = 700.px, shader = aurora)
```

If a gradient you must reproduce has more than two stops, is radial, or is conic —
**and the element is a node** — this is the right answer, not a stack of panels.
Inside a `canvas` there is no shader prop, so banding is the only option.

---

## 2. `box-shadow`

### 2a. On a node — supported

```nim
type
  Shadow* = object
    ## `shadow = shadow(y = 8, blur = 24, color = rgba(0x000000, 0.4))`
    x*, y*, blur*: float32
    color*: int

proc shadow*(x = 0.0; y = 6.0; blur = 18.0; color = rgba(0x000000, 0.35)): Shadow =   # style.nim:31
  Shadow(x: float32(x), y: float32(y), blur: float32(blur), color: color)
```

Four wire props: `pShadowX = 111`, `pShadowY = 112`, `pShadowBlur = 113`,
`pShadowColor = 114` (`wire.nim:167-170`), written by `setShadow` (`style.nim:43-47`).

```nim
panel(fill = theme().bg, shadow = shadow(y = 8, blur = 24))                 # t_style.nim:44
panel(width = 552.px, height = 260.px, radius = 18, fill = linear(...),
      shadow = shadow(y = 12, blur = 32, color = rgba(0x000000, 0.35)))      # deck.nim:29-30
```

The default is `y = 6, blur = 18, rgba(0x000000, 0.35)` — so `shadow()` with no
arguments is a card that floats.

### 2b. In a canvas — no shadow primitive

`Draw` can neither drop a shadow nor blur a shape. Three workarounds, in order of
fidelity:

**1. Draw it again, offset, as a translucent copy.** Good for a hard-edged shadow.

```nim
d = d.rect(x + 4, y + 6, w, h, withA(0xFF140E08'u32, 0.18), r)   # offset copy
d = d.rect(x,     y,     w, h, cPanel,                r)        # the real thing
```

**2. Stack shrinking copies for a soft edge.** What the typewriter does for the
machine's shadow on the desk (`app.nim:662-668`):

```nim
# the machine's own soft shadow
var e = 0
while e < 14:
  let f = e.float32 / 13.0'f32
  d = d.circle(MX + MW / 2.0, MY + 300.0'f32 * U, MW * 0.56 * (1.0'f32 - f * 0.4),
           rgba(12, 6, 2, 0.05))
  inc e
```

**3. Draw the shadow into a `Layer` and blur the layer.** The only real Gaussian blur,
and it blurs the *whole layer*, so the layer must contain nothing but the shadow:

```nim
var shadowLayer = newLayer(1280, 816)
shadowLayer.draw(Draw().rect(x + 6, y + 10, w, h, 0x99000000'u32, 8))
shadowLayer.filter(blur, 12.0'f32)          # in place and destructive: paint.nim:111
d = d.layer(shadowLayer, 0, 0)
```

`examples/shell/paint.nim:28` does the same for a paper texture: `paper.filter(blur, 8)`.

| CSS shadow feature | Status in a canvas | Note |
|---|---|---|
| `box-shadow: A B C colour` | workaround 1 | |
| `… , inset` (inner shadow) | **not supported** | draw a lighter copy clipped to the shape's inner edge; a real inset shadow is an inner stroke, and `Draw` strokes centre on the path |
| multiple shadows | one per copy | each is another pass over the same path |
| spread (`0 4px 8px rgba(…)`) | not a parameter | fake it by drawing the shadow shape larger by the spread amount |
| `text-shadow` | not supported | draw the text twice, offset, in a translucent colour |
| `filter: drop-shadow(…)` | **not supported** | a soft-edged version of the same problem; use the layer blur (3) |

---

## 3. `border-radius`

**On a node:** `radius` is a single `int32` in pixels — `proc radius*(node: Node; value: int32)`
(`sdk/yantra.nim:299`), wire prop `pRadius = 25` (`wire.nim:81`). In the DSL it takes a
length, because `radius` is in `lengthProps` (`dsl.nim:92`):

```nim
panel(width = 150.px, height = 100.px, radius = 14, fill = linear(0xFF006E, 0x3A86FF, 45))  # fx.nim:42
```

**In `Draw`:** `d.rect(x, y, w, h, argb, radius = 0'f32)` (`paint.nim:57`) — the sixth
argument, a `float32`, so it can be fractional where the node's cannot.

```nim
d = d.rect(cx(116), cy(61.6), 768.0'f32 * U, 3.2'f32 * U, cChrome, 1.6'f32 * U)   # app.nim:426
d = d.rect(cx(414), by(90), 172.0'f32 * U, 30.0'f32 * U, 0xFFB3BABE'u32, 15.0'f32 * U)  # app.nim:482
```

Three things that will bite:

1. **`svgPath` has no radius parameter.** `d.svgPath(path, x, y, scale, argb, strokeWidth)`
  — the rounded corners must already be in the path data, as `Q`/`C`/`a` commands. When
  transcribing an SVG that uses `rx`/`ry` on a `<rect>`, convert it to a rounded path
  first. The port's `ellipsePath()` (`app.nim:385`) is the shape of that conversion.
2. **Per-corner radii (`border-radius: 4px 4px 0 0`)** do not exist on either layer.
   Bake it into path data (`Q` commands at the corners you want rounded).
3. **`border` is a stroke prop, and a node only has one.** `result.border(1, 0x9F, 0xC9, 0xB6)`
   (`app.nim:973`) is width + RGB. Per-side borders and per-side colours
   (`border-left: 2px solid red`) are `reference/15a` territory, not this chapter.

---

## 4. `opacity`

| | Node | `Draw` |
|---|---|---|
| API | `node.opacity(0.6)` → `pOpacity = 9` (`wire.nim:65`), `float32` | `d.alpha(0.6)` (`paint.nim:80`), or the colour's alpha byte |
| Scope | the node and its subtree | everything after the command until the matching `save`/`restore` |
| Multiply with an existing translucent fill | yes | yes — the byte and `alpha()` combine |
| Effect on hit-testing | the node still receives events at `opacity = 0` | irrelevant — a canvas never hit-tests itself |

```nim
d = d.save(); d = d.alpha(0.45)
# ...everything here is 45 % …
d = d.restore()
```

In practice the port **bakes** alpha into the colour instead of calling `alpha()`,
because the colour is already the unit of composition:

```nim
proc withA(c: uint32; a: float32): uint32 = (app.nim:381-383)   # replace the alpha byte
d = d.circle(cx(midBell()), cy(72), 14.0'f32 * U, withA(cLamp, bellFlash * 0.35))  # app.nim:589
```

Use `alpha()` when a whole group should fade together; use `withA`/`rgba` when each
command fades by a different amount.

**One asymmetry to remember:** node colours clamp alpha to 1..255
(`style.nim:23-27`) so that a transparent colour stays distinguishable from an opaque
`0x000000`. In `Draw`, `0x00000000'u32` is a genuinely invisible fill — `app.nim:661`
uses it to let the window background show through.

---

## 5. Blend modes

**Both layers have all 29.** On a node, `pBlend = 148` (`wire.nim:204`) takes the
ordinal; the DSL maps bare words to it (`dsl.nim:158-161`: `normal` 3, `plus` 12,
`screen` 14, `overlay` 15, `darken` 16, `lighten` 17, `colordodge` 18, `colorburn` 19,
`hardlight` 20, `softlight` 21, `difference` 22, `exclusion` 23, `multiply` 24, `hue` 25,
`saturation` 26, `color` 27, `luminosity` 28 — which are exactly the `Blend` enum's
ordinals, `paint.nim:14-17`).

```nim
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = mode)   # fx.nim:20
Swatch("multiply", 24)   # fx.nim:50 — the mode as an int is also fine
```

In `Draw`, use the enum:

```nim
d = d.blend(bMultiply)
```

**The gap is isolation, not the modes.** CSS `isolation: isolate` (and the implicit
isolation of a stacking context) is what stops a `mix-blend-mode` element from
blending with the whole page behind it. Yantra's blend composes against whatever is
already in the target — the canvas bitmap, or the window. The workaround is to make
the isolated group be a `Layer`:

```nim
var group = newLayer(w, h)
group.draw(backing)                    # what the blend should see
group.draw(Draw().blend(bMultiply).rect(0, 0, w, h, colour))
d = d.layer(group, x, y, w, h)          # the group is now self-contained
```

That is the same reason `layer.clear()` is `blend(bClear)` + a giant rect
(`paint.nim:110`): it reaches for the blend enum precisely because it owns the target.

---

## 6. Filters

### 6a. On a node — props, all of them real

| CSS | Yantra prop | Wire | Meaning |
|---|---|---|---|
| `filter: blur(4px)` | `blur = 4.px` | `pBlur = 146` | Gaussian blur of the node itself |
| `backdrop-filter: blur(16px)` | `backdropBlur = 26.px` | `pBackdropBlur = 147` | blur of what is *behind* — frosted glass |
| `filter: saturate(0)` | `saturate = 0` | `pSaturate = 149` | 1 as given, 0 greyscale |
| `filter: brightness(1.4)` | `brightness = 1.4` | — | 1 as given |
| `filter: contrast(1.2)` | `contrast = 1.2` | — | 1 as given |
| `mix-blend-mode` | `blend = multiply` | `pBlend = 148` | §5 |
| an arbitrary shader | `shader = sksl"""…"""` | — | §1c |

`blur` and `backdropBlur` are length props and take `.px` in the DSL (`dsl.nim:92-93`);
`saturate`, `brightness`, `contrast` are plain floats. All four filters in one poster,
from a file that compiles:

```nim
text @glow "Every pixel is code.", size = 64, weight = 800, color = accent,
     blur = 22.px, opacity = 0.9                              # fx.nim:28
text "Every pixel is code.", size = 64, weight = 800, color = 0xFFFFFF   # the sharp copy over it

panel @glass(width = 300.px, height = 150.px, left = 60.px, top = 45.px, radius = 20,
             backdropBlur = 26.px, fill = rgba(0xFFFFFF, 0.10),
             border = 1, borderColor = rgba(0xFFFFFF, 0.35))   # fx.nim:36-37

panel(width = 150.px, height = 100.px, radius = 14, fill = linear(0xFF006E, 0x3A86FF, 45),
      saturate = 0, contrast = 1.2)                           # fx.nim:43-44
panel(width = 150.px, height = 100.px, radius = 14, fill = linear(0xFF006E, 0x3A86FF, 45),
      brightness = 1.4, saturate = 1.6)                        # fx.nim:45-46
```

The `@glow` / `@glass` / `@mono` handles are just labels for the nodes — a debugging
affordance, not a feature.

### 6b. In a canvas — `Layer.filter`, on the whole layer

```nim
type
  Filter* = enum
    blur, brightness, contrast, saturation, invert, greyscale, sepia, fade   # paint.nim:18-19

proc filter*(l: Layer; kind: Filter; amount = 1'f32) = yLayerFilter(int32(l), int32(ord(kind)), amount)
  ## In place: blur (px), brightness (-1..1), contrast / saturation (1 same), invert, greyscale,
  ## sepia, fade (opacity 0..1).                                          # paint.nim:111-113
```

Rules that matter:

- **In place and destructive.** It rewrites the layer's pixels. Apply it once, after the
  layer is finished, and never to a layer you also blit unfiltered.
- **Whole-layer only.** You cannot filter one command. To blur one shape, put it in its
  own layer, filter that, and `d.layer(...)` it in.
- **Two passes of `blur` do not compose** the way two CSS filters would. Filter once,
  harder.

```nim
paper.filter(blur, 8)     # examples/shell/paint.nim:28
```

### 6c. Not supported anywhere

| CSS filter | Status | Workaround |
|---|---|---|
| `hue-rotate()` | **no node prop, not in the `Filter` enum** | approximate with `saturate` + a different base colour |
| `invert()`, `grayscale()`, `sepia()` | **layer only** | as a `Layer.filter(invert)`; on a node, pre-invert the colours |
| `opacity()` as a *filter* | the node prop `opacity` does the job | — |
| `drop-shadow()` | **not supported** | §2b workaround 3 |
| `url(#svgFilter)` / SVG filters | **not supported** | the effects above; SVG filter primitives are not transcribed |
| `backdrop-filter` on a **canvas** | **not supported** | the canvas is one bitmap — put the frosted panel in the node tree *over* the canvas |

---

## 7. The port checklist for effects

Walk the page's stylesheet for these properties and answer, per occurrence:

1. **Is it on an element or inside a canvas?** Element → this chapter's node columns.
   Canvas → the `Draw` column, and expect arithmetic.
2. **Gradient with more than 2 stops?** → SkSL shader (`shader = sksl"""…"""`) on the
   node, or bands in the canvas.
3. **Gradient angle?** → **Yantra = CSS − 90** (0 = left→right), settled in source:
   `skia_shim.cpp:431-437` + the passing `t_skia.nim:54-56` assertion. Convert first,
   then check the first rendered frame against the screenshot.
4. **Shadow?** → `shadow = shadow(y, blur, color)` on a node; offset copy, stacked
   copies, or layer blur in a canvas. `inset` is the one to expect to give up on.
5. **Radius?** → one value, all four corners, node or `rect`. If the path came from an
   SVG, the corners are already in the data.
6. **Anything translucent?** → decide `alpha()` (group) or the colour byte (single
   command), and remember `withA`/`rgba` are your two helpers.
7. **Blend mode?** → `blend = word` or `d.blend(bMultiply)`. If it must not blend with
   the page, put it in a `Layer`.
8. **Filter?** → node prop; in a canvas, `Layer.filter` on a dedicated layer.
9. **Rebuild and look at the frame.** Half of every effect bug in this chapter is a
   prop that exists in the wire protocol and is not painted. Compiling is not rendering
   — `reference/17-pitfalls.md` §5 is the chapter on that.