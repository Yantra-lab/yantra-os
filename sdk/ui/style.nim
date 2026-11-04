## Style values: colours with alpha, gradients, shadows, alignment names, cursors and
## reusable style presets (docs/spec/style.md §1, §3).

import ../core/runtime

type
  Gradient* = object
    ## `fill = linear(0xFF7A2F, 0xFFD28A, 135)`: from, to, angle in degrees (90 = top to bottom).
    a*, b*: int
    angle*: float32
  Shadow* = object
    ## `shadow = shadow(y = 8, blur = 24, color = rgba(0x000000, 0.4))`
    x*, y*, blur*: float32
    color*: int
  Style* = object
    ## A reusable bundle of props: `style(fill = …, radius = …)`, applied with `use = …`.
    apply*: seq[proc (n: Node)]

proc wireI32*(x: int): int32 =
  ## Any int prop value as the wire's int32 — colours with alpha use the top byte.
  cast[int32](uint32(x and 0xFFFFFFFF))

proc rgba*(rgb: int; alpha: float): int =
  ## A colour with transparency. `alpha` 0..1. Alpha 0 is kept as "almost clear"
  ## so it stays distinguishable from a plain 0xRRGGBB (which means opaque).
  let a = clamp(int(alpha * 255 + 0.5), 1, 255)
  (a shl 24) or (rgb and 0xFFFFFF)

proc linear*(a, b: int; angle = 90.0): Gradient = Gradient(a: a, b: b, angle: float32(angle))

proc shadow*(x = 0.0; y = 6.0; blur = 18.0; color = rgba(0x000000, 0.35)): Shadow =
  Shadow(x: float32(x), y: float32(y), blur: float32(blur), color: color)

proc setFill*(n: Node; c: int) =
  n.set(pColor, wireI32(c))
  n.set(pGradAngle, -1'f32)           # a plain colour switches any gradient off

proc setFill*(n: Node; g: Gradient) =
  n.set(pGradFrom, wireI32(g.a))
  n.set(pGradTo, wireI32(g.b))
  n.set(pGradAngle, g.angle)

proc setShadow*(n: Node; s: Shadow) =
  n.set(pShadowX, s.x)
  n.set(pShadowY, s.y)
  n.set(pShadowBlur, s.blur)
  n.set(pShadowColor, wireI32(s.color))

template sksl*(src: static string): string =
  ## `shader = sksl"""…"""`: SkSL for the engine's GPU-class shaders (docs/spec/style.md §8).
  ## The shader may declare `uniform float2 size;` (its box) and `uniform float time;` (s).
  src

proc applyStyle*(n: Node; s: Style) =
  for f in s.apply: f(n)
