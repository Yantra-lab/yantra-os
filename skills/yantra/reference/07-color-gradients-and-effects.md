# Colour, gradients and effects

Ground truth for this chapter:

| File | What it decides |
|---|---|
| `sdk/ui/style.nim` (55 lines, read in full) | `Gradient`, `Shadow`, `Style`, `rgba`, `linear`, `shadow`, `setFill`, `setShadow`, `sksl` |
| `sdk/ui/theme.nim` (114 lines) | `Theme`, the eight built-ins, `theme()`, `setTheme`, `nextTheme`, `themeNames` |
| `sdk/core/wire.nim:62-208` | every colour/effect prop id |
| `protocol/props.md` | which DSL prop name is legal, and its wire type |
| `sdk/ui/dsl.nim:89-99, 152-172` | length props, theme words, colour props, the bare-word maps |
| `sdk/yantra.nim:236-306` | the imperative `opacity/color/radius/border` setters |
| `sdk/ui/paint.nim` (124 lines) | `Blend` (29 ords), `Filter`, `eraser`, `Layer.filter`, `Draw.alpha` |
| `render/native/engine.nim:1663-1692, 2195-2204` | the node paint order and the fx layer |
| `libs/nimskia/src/nimskia.nim:133-135, 187-200` | `fillGradient`, `shadow`, `saveFx` |
| `libs/nimskia/src/skia_shim.cpp:431-453` | what the gradient angle and the shadow actually do |
| `reference/15a-html-css-mapping.md` §2.1-§2.5 | the CSS→Yantra table (do not restate it here) |
| `skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md` | the **node layer vs `Draw` layer** split and the port workarounds |

**One chapter, one layer.** This is the **node-level** reference: colour, gradients,
shadows, opacity, blend and filters as *props on a node*. A `Draw` command has almost
none of these — **there is no gradient primitive in `Draw` at all**, no shadow, and
filters only as a whole-`Layer` operation. That split is the single most-confused fact
in the whole skills folder, so it gets its own short section (§10) and the rest of this
chapter is strictly about nodes. The `Draw` side is `reference/09-canvas-and-draw.md`;
the CSS-porting view of the same material is
`skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md`.

---

## 1. The colour model

**One integer.** A colour is a single `int` written across the boundary with
`wireI32` (`sdk/ui/style.nim:19-21`), and the top byte is alpha:

```
0xAARRGGBB          A = alpha in the top byte, then R, G, B
```

`rgba(rgb, alpha)` is the only colour constructor the SDK exports
(`style.nim:23-27`):

```nim
proc rgba*(rgb: int; alpha: float): int =
  let a = clamp(int(alpha * 255 + 0.5), 1, 255)
  (a shl 24) or (rgb and 0xFFFFFF)
```

Two consequences that bite:

- **Alpha clamps to 1..255 — so a node fill can never be *fully* clear.** `rgba(0xEB5757, 0)`
  is `0x01EB5757`, "almost clear", never exactly clear (`style.nim:26`:
  `clamp(int(alpha * 255 + 0.5), 1, 255)`). Combine that with the alpha promotion below
  and the answer is: **`alpha = 0` is unreachable at the node layer.** There is no
  "paint nothing" colour to write. To not paint, **omit `fill`** — then the node takes
  the engine's own default (`engine.nim:1684`).
- **There is no `rgb()`, `hsl()`, `oklch()` or named colour.** `style.nim` exports exactly
  these and nothing else — `wireI32` (`:19`), `rgba` (`:23`), `linear` (`:29`), `shadow` (`:31`),
  `setFill` ×2 (`:34`, `:38`), `setShadow` (`:43`), `sksl` (`:49`), `applyStyle` (`:54`).
  A repo-wide grep of the whole `sdk/` tree for `hsl|oklch|hsva|srgb|hsv|colorspace` returns
  **zero matches in any file** — there is no colour-space conversion anywhere in the SDK, in
  any module, not just `style.nim`. Precompute the hex.
  The one other colour entry point is **`node.color(r, g, b)`** (`sdk/yantra.nim:239-242`),
  which packs three channel ints into `pColor` — no alpha byte, so it produces an opaque colour
  or nothing useful for translucency. The engine reads `P_COLOR` as the node fill
  (`engine.nim:1684`).
  (For completeness on "colour manipulation": the engine does have a `shade` helper that
  lightens/darkens while keeping alpha — `engine.nim:350-353` — but that is a scalar multiply,
  **not** a colour-space conversion.)

### Alpha promotion — why a bare 6-digit hex is opaque on a node

`engine.nim:345-348` is the normaliser, and it is why this rule is safe to memorise
on the node side:

```nim
proc argb(v: int32): uint32 =
  ## Wire colour -> ARGB. 0xRRGGBB (no alpha byte) is opaque; rgba() sets the top byte.
  let u = cast[uint32](v)
  if (u and 0xFF000000'u32) == 0: 0xFF000000'u32 or u else: u
```

Every node colour read goes through it — `engine.nim:367-368`, `proc col(n, p, d)` is
`argb(n.iProp(p))` — and every fill, ink, border and gradient stop is read with `col`.
So **a bare `fill = 0xEB5757` renders opaque.** That is what the doc comment at
`sdk/ui/style.nim:25` means by "a plain `0xRRGGBB` (which means opaque)", and it is true.

> **CORRECTED 2026-10-03.** This chapter used to say: *"A node fill is skipped only when
> the alpha byte is literally 0 (`engine.nim:1686`: `if (f shr 24) != 0`) … use the bare
> integer `fill = 0x000000` for 'paint nothing'."* **Both halves are wrong.**
> - `fill = 0x000000` **paints an opaque black box**, not nothing: `argb(0)` is
>   `0xFF000000` (`engine.nim:348`), so `f shr 24` is `0xFF`, never 0.
> - The guard at `engine.nim:1686` is therefore **unreachable from any app-set colour** —
>   `argb()` guarantees a non-zero top byte, and `rgba` clamps it to ≥ 1 (`style.nim:26`).
>   It is a defensive default, not a feature.
>
> **The correct rule: the node layer cannot express a fully transparent fill.** Omit
> `fill` and let `engine.nim:1684` apply the kind's default fill. §10 already said this
> ("node colours cannot express it"), and §1 contradicted it.

### The alpha trap is `Draw`-specific — moving a colour between layers breaks it

> **CORRECTED 2026-10-03.** The widespread belief — and the shape most briefs repeat —
> is "a CSS hex pasted straight in is fully transparent, everywhere". **On the node
> layer it is not**: `argb()` rescues it, as above. **On the `Draw` layer there is no
> rescue at all.** `libs/nimskia/src/skia_shim.cpp:1327` is a bare
> `paint.setColor(SkColor(argb))` inside the `colour` lambda, and
> `CmdReader::color()` (`skia_shim.cpp:1196-1201`) returns the parsed value verbatim —
> its `0xFF000000u` is a *parse-failure* fallback (`if (q == p)`), not an alpha promotion.
>
> **So the trap is specific and worth stating precisely: a colour that works on a node
> and is then moved into a `Draw` command list stops being drawn.** `0xF7F9FB'u32` has
> top byte `0x00`, so it draws fully transparent — it compiles, runs, crashes nothing,
> and is invisible.
>
> **The correct rule:** on the node layer `0xRRGGBB` is fine; on the `Draw` layer
> **always** write the eight digits (`0xFFF7F9FBu32`). Two safe helpers, from a port:
> ```nim
> proc argb(r, g, b: int32; a: float32): uint32 =                        # apps/chess/app.nim:96
> proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)   # :100
> ```
>
> **This is measured, not theorised.** On port #52, adding the alpha bytes to the
> `Draw` colours moved that port from 100 % differing to 23.7 % in one edit.

### `rgba` is defined twice, with two different signatures

`sdk/ui/style.nim:23` is **signed `int`**, takes a packed `0xRRGGBB` **plus** an alpha
float, and clamps the alpha to 1..255 (`style.nim:26`):

```nim
proc rgba*(rgb: int; alpha: float): int          # sdk/ui/style.nim:23
```

Ports define their **own**, four-argument, `uint32` version — `rgba(r, g, b: int32;
a: float32): uint32` — at `apps/gallery/app.nim:91`, `apps/dna/app.nim:88` and
`apps/typewriter/app.nim:80`. Nim resolves in favour of the local one, so the call
compiles either way and **you cannot tell from the call site which is in scope**:
`rgba(0xEB5757, 0.5)` and `rgba(235, 87, 87, 0.5)` are different functions with
different arities, and only one of them clamps alpha to 1/255.

**Reuse the port's own `rgba` for per-channel work; do not add a third
definition.** If you only have `sdk/ui/style.nim` in scope, `rgba(rgb, alpha)` is the
only one and you must pre-pack the hex yourself.

### Which prop paints what

| Prop | Wire | Type | What it paints |
|---|---|---|---|
| `fill` | `pColor` | `int32` | the box behind the node — the `background` of CSS |
| `color` / `textColor` | `pTextColor` | `int32` | the ink: text, icons, labels |
| `borderColor` | `pBorderColor` | `int32` | the 1-value stroke colour |
| `fill` | `pGradFrom/To/Angle` | int32×2 + float32 | or a 2-stop linear gradient (§3) |
| `shadow` | `pShadowX/Y/Blur/Color` | float32×3 + int32 | the drop shadow (§4) |

(`protocol/props.md:19-23, 33, 37`; ids in `wire.nim:62, 81-83, 164-170`.)

`fill` is special-cased by the DSL into `setFill` (`dsl.nim:188-189`), which is why it
accepts **either** an `int` or a `Gradient`. `color` goes through the ordinary
int32 path.

**`fill` vs `color` on a Text.** `engine.nim:406` `fillProp` decides whether a
`pColor` on the node is a box or the ink: for a `K_TEXT` node a `pColor` is its **ink**,
not a background, and `fillProp` is false. So `text "x", fill = 0x101010` does not
paint a box — put a `panel` behind it.

### The imperative setters

`sdk/yantra.nim:236-306` has the OOP layer, for a `Node` you hold:

```nim
proc opacity*(node: Node; value: float32)          # yantra.nim:236
proc color*(node: Node; r, g, b: int32)            # yantra.nim:239  -> (r shl 16) or (g shl 8) or b
proc radius*(node: Node; value: int32)             # yantra.nim:299
proc border*(node: Node; width: int32; r, g, b)    # yantra.nim:303  width + RGB in one call
```

Note the trap: **`color(r, g, b)` takes three channels, not one packed int, and has
no alpha.** Inside the DSL you never call these — you write props. They compile:

```nim
proc setSwatch(n: Node) =
  n.color(235, 87, 87)
  n.radius(8)
  n.border(2, 51, 51, 68)
  n.opacity(0.9)
  setFill(n, 0xEB5757)                      # style.nim:34  — node layer: bare hex is fine (argb())
  setShadow(n, shadow(y = 6, blur = 14))    # style.nim:43
  setFill(n, linear(0xFF006E, 0x3A86FF, 45))
```

**Two ways to hold a node, and they are not the same.** `name = panel(…)` **binds a
Nim identifier** (`dsl.nim:545-549` → `dsl.nim:442-443`); the identifier must be
declared first (`var held: Node`). `panel @name(…)` only writes the node's *name prop*
for tools, tests and AI edits (`dsl.nim:444-445`) — `@name` binds nothing, and `name`
afterwards is an undeclared identifier. Both compile:

```nim
var held: Node

app "HoldProbe", width = 800, height = 400:
  column(gap = 12, pad = 20):
    held = panel(width = 200, height = 60, radius = 8, fill = 0xEB5757)
    held.opacity(0.85'f32)
    held.color(235, 87, 87)
    held.border(2, 51, 51, 68)
    held.radius(16)
    setFill(held, linear(0xFF006E, 0x3A86FF, 45))
    setShadow(held, shadow(y = 6, blur = 14, color = rgba(0x000000, 0.4)))
    held.set(pOpacity, 0.5'f32)
    panel @named(width = 100, height = 40, fill = accent)   # a label, not a variable
```

Every block in §2–§8 below was compiled with `tools/build-wasm.sh`; §1–§3 appear in
this one app. The first swatch is a bare 6-digit hex — legal on the **node** layer
because `argb()` promotes its alpha byte (§1). The last is `0x000000`, which is *not*
"paint nothing" — it is an opaque black box, also because of `argb()` (§1):

```nim
proc card(): Style = style(fill = theme().surface, radius = theme().radius, pad = 16)

app "ColorProbe", width = 900, height = 760, fill = bg:
  column(gap = 14, pad = 20):
    row(gap = 10):
      panel(width = 160.px, height = 56.px, radius = 12, fill = 0xEB5757)
      panel(width = 160.px, height = 56.px, radius = 12, fill = rgba(0xEB5757, 0.35))
      panel(width = 160.px, height = 56.px, radius = 12, fill = rgba(0xEB5757, 0))
      panel(width = 160.px, height = 56.px, radius = 12, fill = 0x000000)   # opaque black
    row(gap = 10):
      panel(width = 160.px, height = 56.px, radius = 12, fill = linear(0xFF006E, 0x3A86FF))
      panel(width = 160.px, height = 56.px, radius = 12, fill = linear(0xFF006E, 0x3A86FF, 0))
      panel(width = 160.px, height = 56.px, radius = 12, fill = linear(0xFF006E, 0x3A86FF, 180))
      panel(width = 160.px, height = 56.px, radius = 12, fill = linear(rgba(0x000000, 0), accent, 90))
      panel(width = 160.px, height = 56.px, radius = 12, fill = linear(accentSoft, surface, 45))
    row(gap = 10):
      panel(width = 160.px, height = 56.px, radius = 12, fill = surface, shadow = shadow(y = 10, blur = 24))
      panel(width = 160.px, height = 56.px, radius = 12, fill = surface,
            shadow = shadow(4, 6, 12, rgba(0x000000, 0.45)))
      panel(width = 160.px, height = 56.px, radius = 12, fill = rgba(0xFFFFFF, 0.06),
            border = 1, borderColor = line)
      panel(width = 160.px, height = 56.px, radius = 12, fill = accent, opacity = 0.6)
```

---

## 2. Themes

A `Theme` is a plain record of values (`sdk/ui/theme.nim:10-29`), not a stylesheet.
Eight are built in (`theme.nim:31-64`), in this order:

| # | Name | dark | accent | radius | mono |
|---|---|---|---|---|---|
| 0 | `Midnight` | yes | `0xFFB23E` | 10 | Consolas |
| 1 | `Paper` | no | `0xD9480F` | 8 | Consolas |
| 2 | `Fjord` | yes | `0x88C0D0` | 8 | Consolas |
| 3 | `Ember` | yes | `0xFF5A36` | 14 | Consolas |
| 4 | `Forest` | yes | `0x7BD88F` | 12 | Consolas |
| 5 | `Blossom` | no | `0xE0457B` | 16 | Consolas |
| 6 | `Terminal` | yes | `0x39FF14` | **0** | Consolas |
| 7 | `Contrast` | yes | `0xFFE600` | 4 | Consolas |

Fields: `bg sidebar surface surface2 surface3 line text muted faint accent accentText
accentSoft danger success radius font mono`. Note `radius` and the two font families
live on the theme too — `radius = theme().radius` is the usual way to stay consistent.

The API (`theme.nim:66-96`):

```nim
proc theme*(): Theme                                  # the current one; a tracked read
proc setTheme*(t: Theme)                              # by record
proc setTheme*(name: string)                          # by name, ignored if unknown
proc nextTheme*()                                     # cycles the eight
proc themeNames*(): seq[string]
```

`theme()` reads a signal, so **any prop written as `fill = theme().surface` re-runs
when the theme changes** — that is the whole theming mechanism, no engine work, no
reload. A custom theme is just a record:

```nim
row(gap = 10):
  row(width = 120, height = 40, radius = 8, fill = surface2, cursor = hand):
    onClick: nextTheme()
    text "next", size = 14, color = text
  row(width = 120, height = 40, radius = 8, fill = surface2, cursor = hand):
    onClick: setTheme("Paper")
    text "paper", size = 14, color = text

let cur = theme().name
let names = themeNames()
let rad = theme().radius
text "{cur} / {names.len} themes / radius {rad}", size = 14, color = muted

setTheme(Theme(name: "Mine", dark: true, bg: 0x101014, surface: 0x1A1A22,
                text: 0xFFFFFF, accent: 0xFFB23E, radius = 12))
```

(`examples/shell/shell.nim:164` does exactly the `onClick: nextTheme()` shape; a
custom theme needs only the fields it actually reads — unset fields are `0`, i.e.
black, so fill in the ones you use.)

### Bare theme words

Fourteen bare identifiers are rewritten at compile time to `theme().<name>`
(`dsl.nim:97-98, 101-115`):

```
bg sidebar surface surface2 surface3 line text muted faint
accent accentText accentSoft danger success
```

They are rewritten **anywhere in a value**, including inside `rgba(…)`,
`linear(…)` and `shadow(color = …)` — but only in the five colour props
(`dsl.nim:99`): `fill`, `color`, `textColor`, `borderColor`, `shadow`. So
`fill = linear(accentSoft, surface, 45)` follows a theme switch, and a bare `surface`
anywhere else in your code does **not**.

---

## 3. Gradients — two stops, linear, one angle

The entire model (`sdk/ui/style.nim:7-10, 29, 38-41`):

```nim
type
  Gradient* = object
    ## `fill = linear(0xFF7A2F, 0xFFD28A, 135)`: from, to, angle in degrees (90 = top to bottom).
    a*, b*: int
    angle*: float32

proc linear*(a, b: int; angle = 90.0): Gradient
proc setFill*(n: Node; g: Gradient) =
  n.set(pGradFrom, wireI32(g.a))
  n.set(pGradTo, wireI32(g.b))
  n.set(pGradAngle, g.angle)
```

Three wire props: `pGradFrom = 108`, `pGradTo = 109`, `pGradAngle = 110`
(`wire.nim:164-166`). **Two stops. Linear only. No radial, no third stop, no stop
positions, no hint.** The engine paints it with `fillGradient` (`engine.nim:1680-1682`)
→ `nimskia.nim:133-135` → `yk_rrect_gradient`.

### The angle, calibrated

The shim is the whole truth (`skia_shim.cpp:431-443`):

```cpp
float a = angleDeg * 3.14159265f / 180.f;
float cx = x + w / 2, cy = y + h / 2;
float dx = std::cos(a) * w / 2, dy = std::sin(a) * h / 2;
SkPoint pts[2] = {{cx - dx, cy - dy}, {cx + dx, cy + dy}};
```

The gradient runs from `centre − (cos·w/2, sin·h/2)` to `centre + (…)`, so:

| Yantra angle | direction of `a → b` |
|---|---|
| `0` | **left → right** |
| `90` | top → bottom (the default, and what the doc comment promises) |
| `180` | right → left |
| `270` / `-90` | bottom → top |
| `45` | top-left → bottom-right |

The zero point is therefore **not untested**: Yantra's angle is CSS's angle **minus
90** (CSS 0deg = to top, Yantra 0 = to right). `libs/nimskia/tests/t_skia.nim:54-56`
is the existing assertion for it — `fillGradient(…, red, blue, 0)` and the red must be
at `x = 1`, the blue at `x = 62`. Confirmed by rendering: render one
`linear(A, B, 0)` next to one `linear(A, B, 90)` and look. (Corrections: §12.)

The gradient spans the **box projection along that direction**, so on a non-square
node a diagonal gradient is stretched to the diagonal of the box, and the ends are
clamped (`SkTileMode::kClamp`), so there is no repeat.

### Limits, and the honest workaround for each

| You want | Status | Do this |
|---|---|---|
| `linear-gradient(to bottom, A, B)` | yes | `linear(A, B)` — 90 is the default |
| 3+ stops | **no** | an SkSL `shader` (§8), or stacked 2-stop nodes in a `stack` |
| stop positions (`B 20%`) | **no** | same — the stops are implicitly 0 % and 100 % |
| `radial-gradient` / `conic-gradient` | **no** | an SkSL `shader` |
| a transparent stop | yes | `linear(rgba(0x000000, 0), A)` — remember alpha clamps to 1/255 |
| gradient clipped to the radius | automatic | `engine.nim:1681` passes `radius` into `fillGradient` |
| switching a gradient off | yes | set a plain colour — `setFill(n, c)` writes `pGradAngle = -1` (`style.nim:36`) |
| a gradient as a **hover** fill | **no, and not silently** | you cannot put a `Gradient` in a state block at all — that is a compile error (§9). And once a state fill exists the node's *own* gradient is skipped (`engine.nim:1668-1680`), so it paints the solid. Use a solid |
| `turn` / `rad` / `grad` units | no | degrees only; multiply by hand |
| animating a gradient | no | the animatable channels are `opacity, rotate, scale, x, y` |

Real usage, from a file that compiles (`examples/shell/fx.nim:19, 42`):

```nim
panel(width = 120.px, height = 84.px, radius = 12, fill = linear(0x2F80ED, 0xF2C94C, 0))
panel(width = 150.px, height = 100.px, radius = 14, fill = linear(0xFF006E, 0x3A86FF, 45))
panel(width = 26, height = 26, radius = 8, fill = linear(accent, danger, 135))  # shell.nim:159
```

---

## 4. Shadows

```nim
type
  Shadow* = object
    ## `shadow = shadow(y = 8, blur = 24, color = rgba(0x000000, 0.4))`
    x*, y*, blur*: float32
    color*: int

proc shadow*(x = 0.0; y = 6.0; blur = 18.0; color = rgba(0x000000, 0.35)): Shadow   # style.nim:31
proc setShadow*(n: Node; s: Shadow) =                                              # style.nim:43-47
  n.set(pShadowX, s.x); n.set(pShadowY, s.y); n.set(pShadowBlur, s.blur)
  n.set(pShadowColor, wireI32(s.color))
```

Four wire props: `pShadowX = 111`, `pShadowY = 112`, `pShadowBlur = 113`,
`pShadowColor = 114` (`wire.nim:167-170`). What the engine does
(`engine.nim:1665-1667`):

- The shadow draws **only** if `pShadowColor` is present **and** at least one of
  `blur > 0`, `x != 0`, `y != 0`. `blur = 0` with no offset paints nothing.
- The node's `radius` is passed into the shadow call, so the shadow silhouette is the
  rounded rect, not a square.
- The shim blurs with `blur / 2` (`skia_shim.cpp:451`) — the parameter is a diameter,
  not a sigma.
- Default when the prop is missing: `0x59000000` (≈35 % black).

```nim
panel(width = 552.px, height = 300.px, radius = 18, fill = linear(surface2, bg, 135),
      border = 1, borderColor = line,
      shadow = shadow(y = 12, blur = 32, color = rgba(0x000000, 0.35)))          # deck.nim:29-30
panel(fill = bg, pad = 90.px, gap = 34.px, radius = 6,
      shadow = shadow(y = 10, blur = 30, color = rgba(0x000000, 0.35)))          # examples/docs/pitch.nim:25
panel(width = 200, height = 60, shadow = shadow(4, 6, 12, rgba(0x000000, 0.45)))
```

**One shadow per node.** No spread, no inset, no list, no `text-shadow`, no
`drop-shadow`. Two shadows = two nested panels; `inset` = a darker child panel inset
by the spread. All four are in `reference/15a` §2.5 with fix difficulty.

---

## 5. Radius, border, and the two things you cannot do to them

| Prop | Wire | Type | Note |
|---|---|---|---|
| `radius` | `pRadius = 25` | `int32` | pixels; in `lengthProps`, so `radius = 14.px` is legal too (`dsl.nim:92`) |
| `border` | `pBorderWidth = 27` | `int32` | one width for all four sides; a length prop |
| `borderColor` | `pBorderColor = 26` | `int32` | one colour for all four sides |

The imperative form sets both at once "so a border is never half-set"
(`yantra.nim:303-306`).

Three traps:

1. **Per-corner radii do not exist.** `engine.nim:1686` draws one `fillRRect` for the
   whole node. `border-radius: 8px 0 8px 0` needs a `canvas`, or an SkSL shader, or a
   baked SVG path.
2. **Per-side borders do not exist** — one width, one colour. `border-left: 2px solid
   red` is four nodes or nothing.
3. **A state border on a borderless node is drawn at 1.5 px.**
   `engine.nim:1691-1692`: if there is no `border` width but the state colour
   changed, the engine strokes at width 1.5 anyway.

Elliptical radii are impossible too: a node's corner is a circular arc of `radius`.

---

## 6. Opacity

| | |
|---|---|
| Prop | `opacity`, wire `pOpacity = 9`, `float32` (`props.md:19`) |
| Default | `1.0` (`engine.nim:1646`) |
| Scope | the node **and its whole subtree** |

How the engine applies it (`engine.nim:2185-2204`):

```nim
if op <= 0.001: return                       # a node at zero opacity is not painted at all
…
if hasFx: layers = c.saveFx(… Fx(… alpha: op))   # one fx layer for the subtree
elif op < 0.999: c.saveAlpha(op); layers = 1     # otherwise a plain group-alpha save
e.paintTree(c, id)
for _ in 0 ..< layers: c.restore()
```

So `opacity = 0` still lays out and still hit-tests — use `visible = false` to take a
node out of layout instead. Because it folds into the same fx layer as the filters
(§8), a node with both does not pay for two passes.

A translucent **fill** and a translucent **opacity** multiply; they are not
alternatives. `fill = rgba(0xFFFFFF, 0.06)` is one shape at 6 %,
`opacity = 0.5` is the shape and everything in it.

---

## 7. Blend modes

`pBlend = 148`, `int32` (`wire.nim:204`), default `-1` = no blend
(`engine.nim:2200`). The ords are Skia's own, and the node layer takes **the same 29**
(`sdk/ui/paint.nim:14-17`):

| ord | name | ord | name | ord | name |
|---|---|---|---|---|---|
| 0 | `bClear` | 10 | `bDstATop` | 20 | `bHardLight` |
| 1 | `bSrc` | 11 | `bXor` | 21 | `bSoftLight` |
| 2 | `bDst` | 12 | `bPlus` | 22 | `bDifference` |
| 3 | `bSrcOver` | 13 | `bModulate` | 23 | `bExclusion` |
| 4 | `bDstOver` | 14 | `bScreen` | 24 | `bMultiply` |
| 5 | `bSrcIn` | 15 | `bOverlay` | 25 | `bHue` |
| 6 | `bDstIn` | 16 | `bDarken` | 26 | `bSaturation` |
| 7 | `bSrcOut` | 17 | `bLighten` | 27 | `bColor` |
| 8 | `bDstOut` (= `eraser`) | 18 | `bColorDodge` | 28 | `bLuminosity` |
| 9 | `bSrcATop` | 19 | `bColorBurn` | | |

`const eraser* = bDstOut` (`paint.nim:21`) — an alias, so **`eraser` is ord 8**, and
on a node you write `blend = 8`, not `blend = eraser`: the DSL rewrites a bare
*identifier* word (`dsl.nim:150-164`), and `eraser` is not in its word table.

The seventeen DSL words (`dsl.nim:158-161`) are exactly the ords above:

```
normal 3  plus 12  screen 14  overlay 15  darken 16  lighten 17
colorDodge 18  colorBurn 19  hardLight 20  softLight 21  difference 22
exclusion 23  multiply 24  hue 25  saturation 26  color 27  luminosity 28
```

The comparison is done on the **lower-cased** spelling (`dsl.nim:151`), so
`blend = colorDodge`, `blend = colordodge` and `blend = ColorDodge` all work — but
`color-dodge` does not: it parses as `color - dodge`, an expression, not an identifier.
A bare integer is equally legal (`blend = 24`) — that is what the
`Swatch("multiply", 24)` helper at `examples/shell/fx.nim:50` passes to the
`blend = mode` at `examples/shell/fx.nim:17-20`.

```nim
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = multiply)
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = screen)
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = 24)
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = 8)   # eraser
panel(width = 120.px, height = 84.px, radius = 12, fill = 0xEB5757, blend = plus)
```

(Bare hexes are fine here — these are **node** fills, promoted by `engine.nim:345-348`.
The moment one of these colours becomes a `Draw` argument it needs its alpha byte: see
the CORRECTED note in §1. That is precisely the difference between
`examples/shell/fx.nim:20`, which draws a node fill and works, and a `Draw` list, which
would not.)

Two honest gaps:

- **`normal` is 3, not 0.** Ord 0 is `bClear`, which would erase the node.
- **There is no isolation.** A blend composes against whatever is already in the
  target — the window — so a CSS `isolation: isolate` group has no equivalent on a
  node; make the group an opaque `panel`, and verify on the real surface.

---

## 8. Filters, and the one escape hatch

Five node props, all folded into **one** fx layer (`engine.nim:2195-2202`):

| Prop | Wire | Type | Neutral value | CSS |
|---|---|---|---|---|
| `blur` | `pBlur = 146` | `float32` | 0 | `filter: blur(px)` |
| `backdropBlur` | `pBackdropBlur = 147` | `float32` | 0 | `backdrop-filter: blur(px)` |
| `saturate` | `pSaturate = 149` | `float32` | **1** | `filter: saturate()` |
| `brightness` | `pBrightness = 150` | `float32` | **1** | `filter: brightness()` |
| `contrast` | `pContrast = 151` | `float32` | **1** | `filter: contrast()` |

`blur` and `backdropBlur` are length props and take `.px` (`dsl.nim:93`); the other
three are plain floats and **1, not 0, means unchanged** — `saturate = 0` is greyscale.
`opacity` rides in the same record as `alpha`. One node, one layer, one pass: they
compose for free; there is no filter *list*, so you get one of each and no more.

```nim
text "Every pixel is code.", size = 64, weight = 800, color = accent,
     blur = 22.px, opacity = 0.9                                     # fx.nim:28
panel @glass(width = 300.px, height = 150.px, radius = 20,
             backdropBlur = 26.px, fill = rgba(0xFFFFFF, 0.10),
             border = 1, borderColor = rgba(0xFFFFFF, 0.35))          # fx.nim:36-37
panel(width = 150.px, height = 100.px, radius = 14,
      fill = linear(0xFF006E, 0x3A86FF, 45), saturate = 0, contrast = 1.2)
panel(width = 150.px, height = 100.px, radius = 14,
      fill = linear(0xFF006E, 0x3A86FF, 45), brightness = 1.4, saturate = 1.6)
```

There is **no** `hueRotate`, `sepia`, `greyscale` or `invert` prop. On a node those are
NOT SUPPORTED YET; the generic answer is a shader.

### The shader prop

```nim
template sksl*(src: static string): string   # style.nim:49-52
```

`shader` is a `string` prop (`pShader = 152`). `engine.nim:1670-1679`: it **replaces
the fill** (not layered on top), is clipped to the node's rounded rect, is **skipped
whenever a hover/press/focus fill applies** (same rule as the gradient), and if the
source contains `time` the engine keeps frames coming. A shader that fails to compile
shows its error over the app in dev builds.

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
panel @aurora(width = 1000.px, height = 700.px, shader = aurora)     # fx.nim:25
```

Only `uniform float2 size;` (the box) and `uniform float time;` (seconds) are provided.

---

## 9. Paint order, and what a state block may change

`engine.nim:1663-1692` paints a node's surface in exactly this order:

1. **shadow**, if `pShadowColor` is present and something is non-zero;
2. **shader** if present, else **gradient** if present and no state fill applies, else
   the **fill** colour — and the fill is skipped entirely when its alpha byte is 0;
3. **border** at `pBorderWidth`, in the state colour if one applies.

A `hover:` / `pressed:` / `focused:` block may change **only six** things
(`dsl.nim:233-242`): `fill`, `color`, `borderColor`, `opacity`, `scale`, `y`. Anything
else is compile error **Y013** — "`'radius'` can't change with state — use fill, color,
borderColor, opacity, scale or y".

```nim
panel(width = 160, height = 56, radius = 12, fill = surface, transition = 160):
  hover: fill = accentSoft
  pressed: fill = accent
  focused: borderColor = accent
text "State block", size = 16, color = muted
```

**A state block holds a colour, not a gradient or a shadow.** It writes
`pHoverFill`/`pHoverColor`/`pHoverBorder`/`pHoverOpacity`/`pHoverScale`/`pHoverY`
directly (`dsl.nim:246`), so:

```nim
panel(fill = 0x112233):
  hover: fill = linear(0xFF006E, 0x3A86FF, 90)
# Error: type mismatch: got 'Gradient' for 'linear(…)' but expected 'int'
```

And note the knock-on: as soon as a state fill exists, the node's **own** gradient is
skipped (`engine.nim:1668-1682`) and the node paints the solid state colour. So
`panel(fill = linear(A, B), hover: fill = solid)` renders a solid, not a gradient, until
the hover ends.

---

## 10. The one thing people get wrong: node ≠ `Draw`

This chapter is about nodes. `Draw` (`sdk/ui/paint.nim`) is a **separate command
list** with a *much* smaller vocabulary. Do not carry a node API into it, or a `Draw`
API into a node:

| | **node (this chapter)** | **`Draw` command** |
|---|---|---|
| gradient | **yes** — `linear(a, b, angle)`, 2 stops | **no primitive at all** — bands or a shader-free loop |
| drop shadow | **yes** — `shadow(x, y, blur, color)` | **no primitive** — an offset copy, stacked copies, or a layer blur |
| solid colour | `fill` / `color` props — `int`, `0xRRGGBB` is promoted to opaque (§1) | `uint32` **AARRGGBB** per command — `0xF7F9FB'u32` draws **nothing** (§1) |
| alpha | `opacity = 0.6` (the subtree) | `d.alpha(0.6)` (to the matching `save`/`restore`) **and** the colour's own alpha byte — the two compose |
| blend | `blend = multiply` / `blend = 24` | `d.blend(bMultiply)`, `d.blend(eraser)` |
| filter | five node props (§8) | `Layer.filter(kind, amount)` — **whole layer only**, in place, destructive |
| rounded rect | `radius = 12` (int, all four corners) | `d.rect(x, y, w, h, argb, radius = 8'f32)` — fractional, same four corners |

`alpha(0.0)` really is zero there: `0x00000000'u32` is a genuinely invisible fill,
which node colours cannot express — `rgba` clamps alpha to 1 and `argb()` promotes a
zero top byte to `0xFF` (§1), so `alpha = 0` is unreachable on a node.

> **`Draw.alpha()` is NOT silently dropped — do not write that it is.** This is
> stated here because the claim circulates and it is false. `sdk/ui/paint.nim:80`
> emits the verb `"O "`, and the shim handles it:
> `libs/nimskia/src/skia_shim.cpp:1412` —
> `case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;` — applied
> through the `colour` lambda at `skia_shim.cpp:1327`
> (`if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha)`).
> **It is a cumulative multiplier, not a setter**: `alpha(0.5).alpha(0.5)` is 0.25.
> What *is* silently skipped is an **unrecognised verb** —
> `skia_shim.cpp:1413` `default: break;` ("unknown: skipped, so newer apps still
> draw on older engines"). A verb your engine does not know is dropped without a
> word; `alpha` is known.

The `Draw` side is `reference/09-canvas-and-draw.md`; the CSS-porting view of both
layers, with the workarounds that were actually used, is
`skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md`. `Layer.filter` itself:

```nim
type
  Filter* = enum                                          # paint.nim:18-19
    blur, brightness, contrast, saturation, invert, greyscale, sepia, fade

proc filter*(l: Layer; kind: Filter; amount = 1'f32)       # paint.nim:111-113
  ## In place: blur (px), brightness (-1..1), contrast / saturation (1 same), invert,
  ## greyscale, sepia, fade (opacity 0..1).
```

```nim
canvas(draw = Draw().save().alpha(0.45).rect(0, 0, 120, 40, 0xFFEB5757'u32, 8)
                  .blend(bMultiply).circle(80, 60, 24, 0xFF3A86FF'u32)
                  .blend(eraser).circle(160, 30, 18, 0xFFFFFFFF'u32)
                  .restore().cmds, width = 260.px, height = 120.px)
```

---

## 11. NOT SUPPORTED YET, with the workaround

Node level. The CSS-side tables, with fix difficulty, are in
`reference/15a-html-css-mapping.md` §2.1-§2.5; `reference/16-engine-limits-and-workarounds.md`
§3 is the full list. The short version:

| You want | Node status | Workaround |
|---|---|---|
| `radial-gradient` / `conic-gradient` / `repeating-*` | no | `shader = sksl"""…"""`, or bands in a `canvas` |
| 3+ stops, stop positions, hints | no | a shader, or stacked 2-stop nodes |
| `background-image` as a fill | no | an `image` node inside a `stack` |
| per-corner / elliptical `border-radius` | no | `canvas`, a shader, or a baked SVG path |
| per-side / per-corner `border` | no | nested nodes |
| `box-shadow` spread, `inset`, a list | no | sibling panels, one per shadow |
| `text-shadow`, `filter: drop-shadow` | no | a second `text`/`path` node behind, offset with `x`/`y` |
| `hue-rotate`, `sepia`, `grayscale`, `invert` | no prop | a shader; or a `Layer.filter` if the effect lives in a canvas |
| `backdrop-filter` beyond blur | no | a translucent fill over the blurred panel |
| `hsl()`, `oklch()`, named colours, `color-mix()` | no | precompute the hex, or compute it in Nim |
| `outline`, `outline-offset` | no | a `border` on a `panel` placed around the node |
| `isolation: isolate` | no | an opaque `panel`, or a `Layer` in a canvas |
| animating a gradient / radius / colour keyframes | no | `transition` for one-off changes; the animatable channels are `opacity, rotate, scale, x, y` |

**The one mechanism that answers most of this is `shader = sksl"""…"""`.** It
replaces the fill, is clipped to the radius, and gets `size` and `time`. Prefer it to a
stack of panels whenever the element is a node.

---

## 12. CORRECTIONS TO OTHER CHAPTERS

Claims found in sibling chapters that this chapter's source reading contradicts:

1. **`reference/15a-html-css-mapping.md` §3 gradient table — the angle rule is wrong.**
   It says "**Yantra angle = CSS angle + 45**" and derives `to top right → 45` from it.
   Read out of `skia_shim.cpp:434-437` (`dx = cos(a)·w/2`, `dy = sin(a)·h/2`, from
   `centre−(dx,dy)` to `centre+(dx,dy)`), the rule is **Yantra = CSS − 90**, and `0` is
   **left → right**, not an unknown zero point:

   | CSS | Yantra |
   |---|---|
   | `0deg` (to top) | `270` / `-90` |
   | `90deg` / `to right` | `0` |
   | `180deg` / `to bottom` | `90` |
   | `270deg` / `to left` | `180` |
   | `45deg` / `to top right` | `315` / `-45`, **not 45** |

   The 15a rows for `to right → 0` and `to left → 180` were already right; only the
   "+45" rule, `to top right → 45` and `0deg → 0` are wrong (that row should read
   `270` / `-90`). Note the chapter also contradicted *itself* here: line 410 guessed
   "Yantra 0 = to right" while line 413 asserted "+45" — and it is line 410 that matches
   the source. The zero point is now **closed in source**, not left open: the gradient axis is
   a line through the **centre of the rect**, with the *first* colour at `centre − (dx, dy)`
   and the second at `centre + (dx, dy)` (`skia_shim.cpp:435-437`). It is corroborated by
   `libs/nimskia/tests/t_skia.nim:54-56`, which asserts that at angle `0` the *first* colour is
   at `x = 1` and the second at `x = 62`.

   > **CLOSED 2026-10-03 — 15a now carries this correction; no edit needed there.**
   > Re-read `reference/15a-html-css-mapping.md`: `:407` states "**The angle:
   > `Yantra angle = CSS angle − 90`**, so **Yantra 0 = left→right**", `:419` derives it
   > (`0deg = to top` → `a = 270`), `:429` maps `linear-gradient(0deg, A, B)` to
   > `linear(A, B, 270)`, `:434` maps `to top right` to `315`, and `:831-832` close both
   > VERIFY items ("**CLOSED in source**"). The "+45" claim this section warns about no
   > longer appears in 15a. This entry is kept as the record of how it was settled.

2. **`skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md` §1a, the row "a gradient as a
   hover fill → silently skipped".** It is not a silent skip: a `Gradient` in a state
   block is a **compile error**, because a state block writes `pHoverFill` as an
   `int32` (`dsl.nim:234, 246`). Compiling
   `panel(fill = 0x112233): hover: fill = linear(0xFF006E, 0x3A86FF, 90)` gives
   `Error: type mismatch: got 'Gradient' for 'linear(…)' but expected 'int'`. The
   *engine* skip is real, but it is about the node's own base gradient whenever a state
   fill exists (`engine.nim:1668-1682`). Both statements should say which is which.

3. **Minor, one chapter:** `t_style.nim:44` is `sdk/tests/t_style.nim:44`. The CSS
   chapter cites it without the folder; the line itself is correct:
   `panelNode = panel(fill = theme().bg, shadow = shadow(y = 8, blur = 24))`.

---

## 13. Before you trust any of this

- **The gradient angle — CLOSED in source, with one honest caveat.** The rule is
  **`Yantra angle = CSS angle − 90`**, measured **clockwise from left→right**, with the axis
  passing through the **centre of the rect** and the *first* colour at `centre − (dx, dy)`:
  `skia_shim.cpp:434-437` computes `dx = cos(a)·w/2`, `dy = sin(a)·h/2` from
  `centre = (x + w/2, y + h/2)` and makes `pts = {centre−(dx,dy), centre+(dx,dy)}` with
  `cols = {from, to}` — so at `a = 0` that is `(x, y+h/2) → (x+w, y+h/2)`, i.e. left→right with
  `from` on the left, and at `a = 90` it is `(x+w/2, y) → (x+w/2, y+h)`, top→bottom. The engine
  passes the prop straight through: `engine.nim:1680-1682` reads `P_GRADFROM` / `P_GRADTO` /
  `P_GRADANGLE` (defaulting to `90`) and calls `c.fillGradient(...)`, whose default matches
  (`sdk/ui/style.nim:29`, `angle = 90.0`). `t_skia.nim:54-56` asserts the `a = 0` case in pixels.
  **Caveat, stated rather than hidden:** this was read out of source, not rendered. The wasm
  path (`build-wasm.sh` → engine → Skia) was not rendered while closing this item, and
  `t_skia.nim` was not executed in this pass. If a gradient looks transposed on your build,
  check `skia_shim.cpp:434-437` first — it is the only place the angle is interpreted.
- **A prop can exist and still not paint.** Half the effect bugs are a wire id the
  renderer ignores. `reference/17-pitfalls.md` §5 is the chapter on that; compiling is
  not rendering.
- ~~**`hsl()` and friends.**~~ **CLOSED 2026-10-03 — they do not exist.** A whole-`sdk/`-tree
  grep for `hsl|oklch|hsva|srgb|hsv|colorspace` returns zero matches in any file, and
  `sdk/ui/style.nim` exports only `wireI32, rgba, linear, shadow, setFill, setShadow, sksl,
  applyStyle`. §1's claim now rests on a repo-wide grep, not on one file. The only other colour
  entry point is `node.color(r, g, b)` (`sdk/yantra.nim:239-242`, opaque, no alpha byte), and
  the only colour maths is `shade` (`engine.nim:350-353`), which is a scalar multiply and not a
  colour-space conversion.
- **Rendered confirmation of the layer split.** The §1 rule — *node colours are alpha-promoted,
  `Draw` colours are not* — is read out of `engine.nim:345-348` and `skia_shim.cpp:1327`,
  and it is measured. Do the once-only check anyway: draw one shape as a node `fill = 0xEB5757`
  and one as a `Draw` `.rect(…, 0xEB5757'u32)`, and confirm the second is missing. It is the
  cheapest check in this chapter and it catches the most common colour bug.
- **How to actually see what drew.** `log()` is a dead instrument — the host collects
  app log lines into `host.logs` (`host/host.nim:628`) and **no runner ever prints
  them**. Debug by drawing, or by reading the pixels out of a frame dump. The traps
  around that (the dump is **BGRA** and must be swapped before diffing; a failed build
  leaves the old `.wasm` in place) are in `reference/17-pitfalls.md` §9.
- If something here is not true of your engine build, the SDK source wins over this
  file. Chapter 00's rule applies: if it is not here, it does not exist; if it is
  marked NOT SUPPORTED YET, read `reference/16` before working around it yourself.