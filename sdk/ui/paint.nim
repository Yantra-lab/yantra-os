## 2D drawing (P7, CV2): a `Draw` list for a canvas (`canvas(draw = d.cmds)`), and layers:
## bitmaps an app keeps and draws into over time — a painting's strokes, a simulation's frames.
##
##   let paper = newLayer(800, 600)
##   paper.draw(Draw().moveTo(10, 10).lineTo(200, 80).stroke(0xFF000000'u32, 6))   # once: it stays
##   paper.filter(blur, 4)
##   canvas(draw = Draw().layer(paper, 0, 0).cmds, width = 800.px, height = 600.px)
import std/strutils

type
  Draw* = object
    cmds*: string                ## the command list (format: libs/nimskia skia_shim.cpp runCmds)
  Layer* = distinct int32
  Blend* = enum                  ## Skia's blend modes, in its order
    bClear, bSrc, bDst, bSrcOver, bDstOver, bSrcIn, bDstIn, bSrcOut, bDstOut, bSrcATop, bDstATop,
    bXor, bPlus, bModulate, bScreen, bOverlay, bDarken, bLighten, bColorDodge, bColorBurn,
    bHardLight, bSoftLight, bDifference, bExclusion, bMultiply, bHue, bSaturation, bColor, bLuminosity
  Filter* = enum
    blur, brightness, contrast, saturation, invert, greyscale, sepia, fade
  FillRule* = enum             ## how `fill` resolves a self-crossing path
    winding, evenOdd

const eraser* = bDstOut           ## draw with this blend to erase what is under the stroke

proc f(x: float32): string =
  ## Two decimals, without formatFloat (the sandbox's C library does not format floats).
  let v = int(abs(x) * 100 + 0.5)
  (if x < 0 and v > 0: "-" else: "") & $(v div 100) & "." & align($(v mod 100), 2, '0')
proc add(d: var Draw; s: string) = d.cmds.add s & ";"
proc moveTo*(d: Draw; x, y: float32): Draw = (result = d; result.add "M " & f(x) & " " & f(y))
proc lineTo*(d: Draw; x, y: float32): Draw = (result = d; result.add "L " & f(x) & " " & f(y))
proc quadTo*(d: Draw; cx, cy, x, y: float32): Draw =
  ## Corner arc, matching canvas quadraticCurveTo.
  result = d
  result.add "Q " & f(cx) & " " & f(cy) & " " & f(x) & " " & f(y)

proc curveTo*(d: Draw; cx1, cy1, cx2, cy2, x, y: float32): Draw =
  ## Cubic Bézier, matching canvas bezierCurveTo. Used by the ellipse shape.
  result = d
  result.add "C " & f(cx1) & " " & f(cy1) & " " & f(cx2) & " " & f(cy2) &
             " " & f(x) & " " & f(y)
proc arcTo*(d: Draw; cx, cy, radius, startDeg, sweepDeg: float32): Draw =
  ## Circular arc, matching canvas arc(). Angles in degrees, clockwise.
  result = d
  result.add "A " & f(cx) & " " & f(cy) & " " & f(radius) & " " &
             f(startDeg) & " " & f(sweepDeg)
proc close*(d: Draw): Draw = (result = d; result.add "Z")

proc stopList(colors: openArray[uint32]; stops: openArray[float32]): string =
  let n = min(colors.len, 16)
  result = " " & $n
  for i in 0 ..< n:
    let p = if i < stops.len: stops[i] elif n > 1: float32(i) / float32(n - 1) else: 0'f32
    result.add " " & $colors[i] & " " & f(p)

proc linear*(d: Draw; x0, y0, x1, y1: float32; colors: openArray[uint32]; stops: openArray[float32] = []): Draw =
  ## The NEXT shape (fill, stroke, rect, circle, ellipse, line) is painted with a linear gradient from (x0, y0)
  ## to (x1, y1) instead of its colour; the colour's alpha still applies. Stops default to evenly spaced.
  result = d; result.add "H " & f(x0) & " " & f(y0) & " " & f(x1) & " " & f(y1) & stopList(colors, stops)
proc radial*(d: Draw; cx, cy, r: float32; colors: openArray[uint32]; stops: openArray[float32] = []): Draw =
  ## The NEXT shape is painted with a radial gradient around (cx, cy), radius r.
  result = d; result.add "J " & f(cx) & " " & f(cy) & " " & f(r) & stopList(colors, stops)
proc soft*(d: Draw; sigma: float32): Draw =
  ## The NEXT shape is drawn blurred by `sigma` px: soft shadows, glows, light pooling on a surface.
  result = d; result.add "W " & f(sigma)
proc clipPath*(d: Draw): Draw =
  ## Everything after (until `restore`) is clipped to the path built so far (moveTo/lineTo/curveTo/close).
  result = d; result.add "k"
proc svgPath*(d: Draw; path: string; x, y, scale: float32; argb: uint32;
              strokeWidth = 0'f32): Draw =
  ## SVG path data (any command set Skia parses: relative, H/V, smooth curves,
  ## arcs) at (x, y) scaled by `scale`. Filled unless strokeWidth > 0.
  result = d
  result.add "V " & f(x) & " " & f(y) & " " & f(scale) & " " & f(strokeWidth) &
             " " & $argb & " " & path
proc fill*(d: Draw; argb: uint32): Draw = (result = d; result.add "F " & $argb)
  ## Fills the path so far.
proc fillRule*(d: Draw; rule: FillRule): Draw = (result = d; result.add "f " & $ord(rule))
  ## The fill rule `fill` (and `svgPath`) use from here on. The default, `winding`, fills
  ## everything between a path's edges; `evenOdd` knocks out the region an even number of
  ## edges enclose — two circles drawn the same way around become a hollow ring (W1-2).
proc stroke*(d: Draw; argb: uint32; width: float32): Draw = (result = d; result.add "S " & $argb & " " & f(width))
  ## Strokes the path so far (round joins and caps: a brush).
proc rect*(d: Draw; x, y, w, h: float32; argb: uint32; radius = 0'f32): Draw =
  result = d; result.add "R " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " " & f(radius) & " " & $argb
proc circle*(d: Draw; cx, cy, r: float32; argb: uint32): Draw =
  result = d; result.add "E " & f(cx) & " " & f(cy) & " " & f(r) & " " & f(r) & " " & $argb
proc ellipse*(d: Draw; cx, cy, rx, ry: float32; argb: uint32): Draw =
  ## An axis-aligned ellipse. The shim's `E` verb has always taken SEPARATE rx and ry
  ## (`skia_shim.cpp` case 'E' -> `drawOval(LTRB(cx-rx, cy-ry, cx+rx, cy+ry))`); only
  ## `circle` collapsed them by passing `r` twice, which made ellipses look unreachable
  ## and pushed apps into tracing polylines instead. rx == ry is a circle, so this is a
  ## strict superset of `circle` — nothing that used `circle` needs to change.
  result = d; result.add "E " & f(cx) & " " & f(cy) & " " & f(rx) & " " & f(ry) & " " & $argb
proc line*(d: Draw; x1, y1, x2, y2: float32; argb: uint32; width = 1'f32): Draw =
  result = d; result.add "G " & f(x1) & " " & f(y1) & " " & f(x2) & " " & f(y2) & " " & $argb & " " & f(width)
proc linearRect*(d: Draw; x, y, w, h: float32; fromCol, toCol: uint32;
                 x1, y1, x2, y2: float32; radius = 0'f32): Draw =
  ## A rounded rect filled with a linear gradient: `fromCol` where the point (x1, y1)
  ## falls, leaning into `toCol` toward (x2, y2). Both clamp, so a rect wider than the
  ## segment ends in the pure colours. One verb for what used to cost a stack of
  ## clipped strips (DECISION_QUEUE D10; W1).
  result = d
  result.add "U " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " " & f(radius) &
             " " & f(x1) & " " & f(y1) & " " & f(x2) & " " & f(y2) & " " & $fromCol & " " & $toCol
proc linearDown*(d: Draw; x, y, w, h: float32; fromCol, toCol: uint32; radius = 0'f32): Draw =
  ## linear rect's common case: top-to-bottom, like CSS linear-gradient(180deg, …).
  d.linearRect(x, y, w, h, fromCol, toCol, x + w / 2, y, x + w / 2, y + h, radius)
proc radialRect*(d: Draw; x, y, w, h: float32; innerCol, outerCol: uint32;
                 cx, cy, rad: float32; radius = 0'f32): Draw =
  ## A rounded rect filled with a radial gradient: `innerCol` at (cx, cy), `outerCol`
  ## reached at radius `rad` (outside stays `outerCol`).
  result = d
  result.add "W " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " " & f(radius) &
             " " & f(cx) & " " & f(cy) & " " & f(rad) & " " & $innerCol & " " & $outerCol
proc noiseRect*(d: Draw; x, y, w, h: float32; fromCol, toCol: uint32;
                freq: float32 = 0.05'f32; freqY = 0'f32; octaves = 4; seed = 0'f32;
                radius = 0'f32): Draw =
  ## A procedural surface: fractal Perlin noise tinted fromCol→toCol, one verb for what
  ## used to be hundreds of hand-laid strips (W1-4). Pull `freqY` down for long streaks
  ## (wood grain: freqY = freq / 8), up for vertical ribs; `seed` picks the slab the
  ## texture is cut from.
  result = d
  result.add "z " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " " & f(radius) &
             " " & f(freq) & " " & f(freqY) & " " & $octaves & " " & f(seed) & " " & $fromCol & " " & $toCol
proc shaderRect*(d: Draw; x, y, w, h: float32; src: string; radius = 0'f32): Draw =
  ## An SkSL shader filling the rect (W1-4; same engine shader as a node's `shader` prop).
  ## It reads its coordinates in the rect's own px and may declare `uniform float2 size`
  ## and `uniform float time` (seconds — a shader reading time animates). A 'compile'-time
  ## error draws nothing, like a bad image path. ';' in the source escapes as '\;'.
  result = d
  result.add "H " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " " & f(radius) &
             " " & src.replace(";", "\\;")
proc text*(d: Draw; x, y, size: float32; argb: uint32; s: string; weight = 400): Draw =
  result = d; result.add "T " & f(x) & " " & f(y) & " " & f(size) & " " & $argb & " " & $weight & " " & s.replace(";", "\\;")
proc textFace*(d: Draw; x, y, size: float32; argb: uint32; family, s: string; weight = 400): Draw =
  ## Draws `s` in `family`, falling back to the engine default when it is "".
  ## DECISION_QUEUE D6. `text` above cannot name a typeface at all: it emits the `T`
  ## verb, the shim's `case 'T'` calls `yk_text_draw` which takes no family, and
  ## `yk_text_draw2` — which does — is reachable only from native nimskia, not from
  ## runCmds. So every direct-draw string was Segoe UI and an app could not change it.
  ##
  ## `family` and `s` are two separate `;`-terminated fields with **NO space between
  ## them**: `rest()` stops at the `;`, so a space here would become part of the name.
  ## An empty `family` takes the existing `!fam.empty()` fallback, so it renders
  ## identically to `text`.
  result = d; result.add "N " & f(x) & " " & f(y) & " " & f(size) & " " & $argb & " " & $weight & " " &
    family.replace(";", "\\;") & ";" & s.replace(";", "\\;")
proc image*(d: Draw; x, y, w, h: float32; file: string): Draw =
  result = d; result.add "I " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " 0 " & file
proc layer*(d: Draw; l: Layer; x, y: float32; w = 0'f32; h = 0'f32): Draw =
  ## Shows layer `l` at (x, y), at its own size unless w, h are given.
  result = d; result.add "Y " & $int32(l) & " " & f(x) & " " & f(y) & " " & f(w) & " " & f(h)
proc pixels*(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32; h = 0'f32): Draw =
  ## Raw RGBA pixels (pw x ph) from a buffer (newBuffer + setData), crisp when scaled up.
  result = d; result.add "X " & $buf & " " & $pw & " " & $ph & " " & f(x) & " " & f(y) & " " & f(w) & " " & f(h)
proc blend*(d: Draw; mode: Blend): Draw = (result = d; result.add "b " & $ord(mode))
  ## How what follows combines with what is under it (multiply, screen, eraser…).
proc save*(d: Draw): Draw = (result = d; result.add "P")
proc restore*(d: Draw): Draw = (result = d; result.add "p")
proc translate*(d: Draw; x, y: float32): Draw = (result = d; result.add "t " & f(x) & " " & f(y))
proc scale*(d: Draw; sx: float32; sy = 0'f32): Draw = (result = d; result.add "s " & f(sx) & " " & f(sy))
proc rotate*(d: Draw; degrees: float32): Draw = (result = d; result.add "o " & f(degrees))
proc alpha*(d: Draw; a: float32): Draw = (result = d; result.add "O " & f(a))
proc clip*(d: Draw; x, y, w, h: float32): Draw =
  result = d; result.add "K " & f(x) & " " & f(y) & " " & f(w) & " " & f(h)

var layerSeq: int32

when defined(yantra_headless) or (defined(wasm) and not defined(yantra_engine)):
  # No rasteriser linked (unit tests, plain `nim c`): every layer op is a no-op.
  proc yLayerNew(id, w, h: int32): int32 = 1
  proc yLayerDraw(id, p, n: int32) = discard
  proc yLayerFilter(id, kind: int32; amount: float32) = discard
  proc yLayerRead(id, x, y, w, h, p: int32): int32 = 0
  proc yLayerWrite(id, x, y, w, h, p: int32) = discard
  proc yLayerFree(id: int32) = discard
  proc yTextMeasure(sPtr, sLen, famPtr, famLen: int32; size: float32; weight: int32): float32 = 0
else:
  proc yLayerNew(id, w, h: int32): int32 {.importc: "y_layer_new", cdecl.}
  proc yLayerDraw(id, p, n: int32) {.importc: "y_layer_draw", cdecl.}
  proc yLayerFilter(id, kind: int32; amount: float32) {.importc: "y_layer_filter", cdecl.}
  proc yLayerRead(id, x, y, w, h, p: int32): int32 {.importc: "y_layer_read", cdecl.}
  proc yLayerWrite(id, x, y, w, h, p: int32) {.importc: "y_layer_write", cdecl.}
  proc yLayerFree(id: int32) {.importc: "y_layer_free", cdecl.}
  proc yTextMeasure(sPtr, sLen, famPtr, famLen: int32; size: float32; weight: int32): float32
      {.importc: "y_text_measure", cdecl.}

proc newLayer*(w, h: int): Layer =
  ## A transparent w x h bitmap.
  inc layerSeq
  discard yLayerNew(layerSeq, int32(w), int32(h))
  Layer(layerSeq)
proc draw*(l: Layer; d: Draw) =
  ## Draws into the layer once; it stays there (strokes accumulate).
  if d.cmds.len > 0: yLayerDraw(int32(l), cast[int32](d.cmds.cstring), int32(d.cmds.len))
proc clear*(l: Layer) = l.draw(Draw().blend(bClear).rect(0, 0, 1e6, 1e6, 0'u32))
proc filter*(l: Layer; kind: Filter; amount = 1'f32) = yLayerFilter(int32(l), int32(ord(kind)), amount)
  ## In place: blur (px), brightness (-1..1), contrast / saturation (1 same), invert, greyscale,
  ## sepia, fade (opacity 0..1).
proc read*(l: Layer; x, y, w, h: int): seq[byte] =
  ## w x h pixels as RGBA bytes (colour picker, saving, analysis).
  result = newSeq[byte](max(0, w * h * 4))
  if result.len > 0:
    let n = yLayerRead(int32(l), int32(x), int32(y), int32(w), int32(h), cast[int32](addr result[0]))
    if n != result.len: result.setLen(0)
proc write*(l: Layer; x, y, w, h: int; rgba: openArray[byte]) =
  ## w x h RGBA bytes into the layer at (x, y) (procedural images, simulations).
  if rgba.len >= w * h * 4 and w > 0 and h > 0:
    yLayerWrite(int32(l), int32(x), int32(y), int32(w), int32(h), cast[int32](unsafeAddr rgba[0]))
proc free*(l: Layer) = yLayerFree(int32(l))

proc textWidth*(s: string; size: float32; family = ""; weight = 400): float32 =
  ## How wide `s` is when drawn at `size` px in `family`, measured by the renderer with the
  ## real font. **Use this instead of guessing a per-character advance.** A flat
  ## `size * 0.6` is wrong for most fonts: Palatino's natural advance runs from 0.327em for
  ## '-' to 0.993em for 'W', a 0.667em spread, and dna's `MONO_ADV = 0.5498` was a hand-built
  ## table for one font that would be wrong for any other.
  ##
  ##   let w = textWidth("RESIGN", 13, "Palatino Linotype")   # right-align it exactly
  ##   for i, ch in "A HOT-SEAT GAME FOR TWO":                # letter-space it exactly
  ##     d.textFace(x + cx, y, size, col, "Palatino Linotype", ch)
  ##     cx += textWidth($ch, size, "Palatino Linotype") + track
  ##
  ## Pass the same `family` you draw with, or the measurement describes a different font.
  ## An empty `family` means the renderer's default, which is what `Draw.text` uses.
  ## Returns 0 for an empty string, or where no renderer is attached (headless tests).
  if s.len == 0: return 0
  yTextMeasure(cast[int32](s.cstring), int32(s.len), cast[int32](family.cstring),
               int32(family.len), size, int32(weight))
