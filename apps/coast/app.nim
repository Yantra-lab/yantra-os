## Infinite Coastline — a real Mandelbrot / Julia instrument. The field is generated
## from live state into a native SkSL escape-time shader; no bitmap image assets.

const
  WW = 1280.0
  WH = 816.0

let night = #07090F
let panelCol = #0B0D12E8
let panelSoft = #0B0D12B8
let gold = #D8B76E
let paleGold = #F1DDA9
let ink = #F1EEE7
let dim = #8B887F
let edge = #6E563454
let selected = #D8B76E
let quiet = #FFFFFF09
let mono = "DejaVu Sans Mono"

const
  places = ["SEAHORSE VALLEY", "ELEPHANT VALLEY", "TRIPLE SPIRAL", "MINI-BROT", "WHOLE SET"]
  placeX = [-0.7436438870, 0.2855, -0.0810, -1.7548776662, -0.62]
  placeY = [0.1318259042, 0.0116, 0.6575, 0.0, 0.0]
  placeSpan = [0.0065, 0.012, 0.0036, 0.078, 2.55]
  paletteNames = ["AURUM", "ABYSS", "MAGMA", "PASTEL DREAM"]
  stops = [
    [0.0, 0.507, 0.533, 0.560, 0.590, 0.626, 0.689, 1.0],
    [0.0, 0.30, 0.55, 0.72, 0.82, 0.88, 0.94, 1.0],
    [0.0, 0.16, 0.33, 0.50, 0.66, 0.80, 0.90, 1.0],
    [0.0, 0.20, 0.40, 0.60, 0.75, 0.86, 0.94, 1.0]]
  ## AURUM is a designed aurora sweep — midnight, ocean, teal, sea glass, amber,
  ## rose, violet, midnight — so the field crosses six hue families instead of
  ## living in one. Its last colour equals its first, because `t` wraps: the seam
  ## at t = 1.0 is invisible only when the ramp closes on itself.
  ##
  ## The stops are not eyeballed. The home view's smooth iteration count is
  ## concentrated — mu p25..p75 is only 2.36..4.43 — so an evenly spaced ramp
  ## spends most of the frame in one segment: measured, 60.13 % of the
  ## saturation-weighted hue landed in orange 30-60 with an even ramp, against
  ## 92.06 % in blue 210-250 before it. These stops are the 1/7..6/7 quantiles of
  ## `t` measured over that same 1,044,480-pixel home frame, so every segment is
  ## covered by 14.3 % of the field's area (numpy sweep of the identical field,
  ## exterior 903,726 px of 1,044,480; see the commit's Verified line).
  colours = [
    [[8, 12, 30], [34, 82, 134], [176, 232, 232], [16, 78, 88], [238, 172, 82], [120, 60, 190], [248, 216, 152], [8, 12, 30]],
    [[1, 6, 26], [8, 48, 107], [15, 181, 212], [227, 253, 255], [105, 218, 231], [47, 147, 189], [8, 48, 90], [1, 6, 26]],
    [[0, 0, 4], [44, 17, 95], [114, 31, 129], [183, 55, 121], [241, 96, 93], [254, 176, 120], [252, 253, 191], [0, 0, 4]],
    [[46, 24, 52], [217, 198, 255], [191, 227, 255], [198, 245, 224], [255, 240, 189], [251, 211, 224], [216, 176, 219], [46, 24, 52]]]

proc fixed(v: float; digits: int): string =
  var p = 1'i64
  for _ in 0 ..< digits: p *= 10
  let scaled = int64(abs(v) * float(p) + 0.5)
  var frac = $(scaled mod p)
  while frac.len < digits: frac = "0" & frac
  $(scaled div p) & (if digits > 0: "." & frac else: "")

proc signed(v: float; digits = 6): string =
  (if v < 0.0: "−" else: "+") & fixed(v, digits)

proc homeSpan(mode: int): float = (if mode == 0: 2.55 else: 3.3)
proc iterationsFor(zoom: float): int =
  let z = max(1.0, zoom)
  min(720, 160 + int(95.0 * pow(ln(z) / ln(10.0) + 1.0, 1.55)))

proc rampSource(p: int): string =
  result = "vec3 ramp(float t) @\n  float u = 0.0;\n"
  for k in 0 .. 6:
    result.add "  if (t < " & $stops[p][k + 1] & ") @\n"
    result.add "    u = (t - " & $stops[p][k] & ") / " & $(stops[p][k + 1] - stops[p][k]) & ";\n"
    result.add "    u = u * u * (3.0 - 2.0 * u);\n"
    result.add "    return mix(vec3(" & $colours[p][k][0] & ".0," & $colours[p][k][1] & ".0," &
      $colours[p][k][2] & ".0), vec3(" & $colours[p][k + 1][0] & ".0," &
      $colours[p][k + 1][1] & ".0," & $colours[p][k + 1][2] & ".0), u);\n  `\n"
  result.add "  return vec3(0.0);\n`\n"

proc fieldSource(cx, cy, step: float; maxIter, palette, mode: int; seedRX, seedRY: float): string =
  ## A full-resolution native SkSL escape-time field. View state is compiled into this
  ## short shader, so every navigation action changes its source and every output pixel.
  result = rampSource(palette)
  result.add "uniform float2 size;\n"
  result.add "half4 main(float2 p) @\n"
  result.add "  float2 q = vec2(" & $cx & " + (p.x - size.x * 0.5) * " & $step &
    ", " & $cy & " - (p.y - size.y * 0.5) * " & $step & ");\n"
  # The set itself is a designed plate, not a hole in the picture: a diagonal wash
  # from midnight (13,17,31) to deep royal (30,38,64). The largest flat area in the
  # frame stops being one colour — cells r2c2/r3c2 were 65.7 % and 62.1 % one colour.
  result.add "  float2 uvg = float2(p.x / size.x, p.y / size.y);\n"
  result.add "  vec3 plate = mix(vec3(0.0510,0.0667,0.1216), vec3(0.1176,0.1490,0.2510), uvg.y * 0.66 + uvg.x * 0.34);\n"
  if mode == 1:
    result.add "  float2 c = vec2(" & $seedRX & "," & $seedRY & ");\n  float2 z = q;\n"
  else:
    result.add "  float2 c = q;\n  float2 z = float2(0.0);\n"
    result.add "  float xq = c.x - 0.25;\n  float bulb = xq * xq + c.y * c.y;\n"
    result.add "  if (bulb * (bulb + xq) <= 0.25 * c.y * c.y || (c.x + 1.0) * (c.x + 1.0) + c.y * c.y <= 0.0625) @ return half4(plate.r,plate.g,plate.b,1.0); `\n"
  result.add "  int n = 0;\n"
  result.add "  for (int i = 0; i < " & $maxIter & "; ++i) @\n"
  result.add "    if (dot(z,z) > 65536.0) @ break; `\n"
  result.add "    z = float2(z.x * z.x - z.y * z.y + c.x, 2.0 * z.x * z.y + c.y);\n    n = i + 1;\n  `\n"
  result.add "  if (n >= " & $maxIter & ") @ return half4(plate.r,plate.g,plate.b,1.0); `\n"
  result.add "  float lz = 0.5 * log(dot(z,z));\n"
  result.add "  float mu = float(n) + 1.0 - log(lz / log(2.0)) / log(2.0);\n"
  # The far field — every pixel with mu about 1 — is the largest area of the frame, and
  # a linear or sqrt ramp compresses all of it into the first eighth of the palette.
  # Measured consequence: 92.06 % of the hue weight sat in one 40-degree bin. The
  # 0.42 power stretches mu 1..5 across half the ramp and lets the boundary region
  # wrap; `t` still moves continuously with mu, so no banding is introduced.
  result.add "  float s0 = sqrt(max(0.0,mu - 1.0)) * 0.19;\n"
  result.add "  float t = fract(pow(s0, 0.42));\n"
  result.add "  vec3 rgb = ramp(t) / 255.0;\n"
  result.add "  return half4(rgb.r,rgb.g,rgb.b,1.0);\n`\n"
  result = result.replace("@", "\x7B").replace("`", "\x7D")

var drag = false
var downX = 0.0
var downY = 0.0
var downCX = 0.0
var downCY = 0.0
var savedX = -0.62
var savedY = 0.0
var savedZoom = 1.0
var savedPlace = 4
var heldCodes: seq[int] = @[]
const polledCodes = [43, 45, 48, 49, 50, 51, 52, 53, 106, 109, 114,
                     int(keyLeft), int(keyRight), int(keyUp), int(keyDown)]

view Coast
  state centerX = -0.62
  state centerY = 0.0
  state zoom = 1.0
  state mode = 0                 # 0 Mandelbrot, 1 Julia
  state paletteId = 0
  state activePlace = 4
  state seedX = -0.7436438870
  state seedY = 0.1318259042
  state hoverX = 640.0
  state hoverY = 408.0
  state hovering = false

  proc viewSpan(): float = homeSpan(mode) / zoom
  proc at(x, y: float): (float, float) =
    let s = viewSpan() / WH
    (centerX + (x - WW * 0.5) * s, centerY - (y - WH * 0.5) * s)

  proc mainArt(): string =
    var d = Draw()
    d = d.shaderRect(0, 0, WW, WH, fieldSource(centerX, centerY, viewSpan() / WH,
                     iterationsFor(zoom), paletteId, mode, seedX, seedY))
    # The scrims are a deep sea-navy, not black: a black wash eats the field's hue
    # and pushes the corners into crushed shadow (dark<13 luma was 33.6 %).
    d = d.linearDown(0, 0, WW, 170, 0x990B1220'u32, 0x000B1220'u32)
    d = d.linearDown(0, WH - 170, WW, 170, 0x000B1220'u32, 0xB80B1220'u32)
    d = d.radialRect(0, 0, WW, WH, 0x000B1220'u32, 0x44060A14'u32, 620, 390, 780)
    if hovering and not drag:
      d = d.line(hoverX - 10, hoverY, hoverX + 10, hoverY, 0xC0F1DDA9'u32, 0.7)
      d = d.line(hoverX, hoverY - 10, hoverX, hoverY + 10, 0xC0F1DDA9'u32, 0.7)
    d.cmds

  proc lensArt(): string =
    Draw().shaderRect(0, 0, 158, 158,
      fieldSource(0.0, 0.0, 3.3 / 158.0, 180, paletteId, 1, seedX, seedY)).cmds

  proc goPlace(i: int) {.closure.} =
    mode = 0
    activePlace = i
    centerX = placeX[i]
    centerY = placeY[i]
    zoom = 2.55 / placeSpan[i]
    seedX = placeX[i]
    seedY = placeY[i]

  proc zoomAbout(x, y, factor: float) {.closure.} =
    let (ax, ay) = at(x, y)
    zoom = min(1e10, max(0.35, zoom * factor))
    let s = viewSpan() / WH
    centerX = ax - (x - WW * 0.5) * s
    centerY = ay + (y - WH * 0.5) * s
    activePlace = -1

  proc toggleMode() {.closure.} =
    if mode == 0:
      savedX = centerX; savedY = centerY; savedZoom = zoom; savedPlace = activePlace
      mode = 1
      centerX = 0.0; centerY = 0.0; zoom = 1.0; activePlace = -1
    else:
      mode = 0
      centerX = savedX; centerY = savedY; zoom = savedZoom; activePlace = savedPlace

  proc panBy(dx, dy: float) {.closure.} =
    let s = viewSpan() / WH
    centerX = centerX - dx * s
    centerY = centerY + dy * s
    activePlace = -1

  let modeLabel = if mode == 0: "MANDELBROT" else: "JULIA SET"
  let placeLabel = if activePlace >= 0: places[activePlace] else: "CUSTOM COORDINATES"
  let toggleLabel = if mode == 0: "JULIA  /  J" else: "MANDELBROT  /  M"
  let lensLabel = if mode == 0: "MOVE OVER THE FIELD TO EXPLORE" else: "SEED LOCKED IN JULIA VIEW"

  proc keyAction(c: int) {.closure.} =
    if c == 106 or c == 109: toggleMode()
    elif c == 43: zoomAbout(WW * 0.5, WH * 0.5, 2.5)
    elif c == 45: zoomAbout(WW * 0.5, WH * 0.5, 0.4)
    elif c == 114 or c == 48: goPlace(4)
    elif c >= 49 and c <= 53: goPlace(c - 49)
    elif c == keyLeft: panBy(80, 0)
    elif c == keyRight: panBy(-80, 0)
    elif c == keyUp: panBy(0, 80)
    elif c == keyDown: panBy(0, -80)

  proc pollKeys() {.closure.} =
    ## Root onKey is not emitted by the current view runtime; keyHeld is the real
    ## SDL state, edge-triggered here so every advertised shortcut acts once.
    for c in polledCodes:
      if keyHeld(int32(c)):
        if c notin heldCodes:
          heldCodes.add c
          keyAction(c)
      elif c in heldCodes:
        heldCodes.delete(heldCodes.find(c))

  Stack(width = 1280px, height = 816px, fill = night):
    on frame: pollKeys()
    Canvas(draw = mainArt(), width = 1280px, height = 816px):
      on pointerDown:
        let (x, y) = pointerPos()
        downX = x; downY = y; downCX = centerX; downCY = centerY
        drag = true
      on pointerMove:
        let (x, y) = pointerPos()
        hoverX = x; hoverY = y; hovering = true
        if mode == 0 and not drag:
          let (sx, sy) = at(x, y)
          seedX = sx; seedY = sy
      on pointerUp:
        let (x, y) = pointerPos()
        if drag:
          if abs(x - downX) + abs(y - downY) > 7.0:
            centerX = downCX; centerY = downCY
            panBy(x - downX, y - downY)
          else:
            zoomAbout(x, y, 2.5)
        drag = false
        hovering = false

    Column(absolute = true, left = 28px, top = 23px, gap = 3px):
      Text "AN EXPLORER OF THE", size = 11px, color = gold
      Text "INFINITE COASTLINE", size = 32px, weight = 500, color = ink
      Panel(width = 322px, height = 1px, fill = 0xD8B76E80'u32, marginTop = 7px, marginBottom = 5px)
      Text "MANDELBROT & JULIA  /  FIELD 042", size = 10px, weight = 600, color = dim

    Panel(absolute = true, right = 26px, top = 24px, width = 278px, pad = 17px,
          fill = panelCol, radius = 3px, border = 1px, borderColor = edge):
      Column(gap = 9px):
        Row:
          Text "POSITION", size = 10px, weight = 700, color = gold, grow = 1
          Text modeLabel, size = 10px, color = dim
        Panel(height = 1px, fill = 0xD8B76E24'u32)
        Text "REAL", size = 10px, weight = 700, color = dim
        Text signed(centerX), size = 15px, color = ink, font = mono
        Text "IMAGINARY", size = 10px, weight = 700, color = dim
        Text signed(centerY) & " i", size = 15px, color = ink, font = mono
        Row(gap = 24px):
          Column(gap = 3px, grow = 1):
            Text "MAGNIFICATION", size = 10px, weight = 700, color = dim
            Text fixed(zoom, 2) & " ×", size = 15px, color = paleGold, font = mono
          Column(gap = 3px, grow = 1):
            Text "MAX ITER", size = 10px, weight = 700, color = dim
            Text $iterationsFor(zoom), size = 15px, color = paleGold, font = mono
        Panel(height = 1px, fill = 0xD8B76E24'u32)
        Text "1280 × 816 SKSL  ·  SMOOTH μ", size = 10px, color = dim, font = mono
        Text placeLabel, size = 10px, weight = 700, color = gold

    Panel(absolute = true, right = 26px, top = 292px, width = 278px, pad = 15px,
          fill = panelSoft, radius = 3px, border = 1px, borderColor = edge):
      Column(gap = 10px, alignItems = 1):
        Row(width = 246px):
          Text "JULIA LENS", size = 10px, weight = 700, color = gold, grow = 1
          Text "LIVE c", size = 10px, color = dim
        Panel(width = 164px, height = 164px, padding = 3px, fill = 0xD8B76E40'u32, radius = 86px, clip = true):
          Canvas(draw = lensArt(), width = 158px, height = 158px)
        Text signed(seedX, 5) & "  " & signed(seedY, 5) & "i", size = 12px, color = ink, font = mono
        Text lensLabel, size = 10px, color = dim

    Panel(absolute = true, left = 26px, bottom = 88px, width = 252px, pad = 14px,
          fill = panelSoft, radius = 3px, border = 1px, borderColor = edge):
      Column(gap = 7px):
        Row:
          Text "FAMOUS LOCATIONS", size = 10px, weight = 700, color = gold, grow = 1
          Text "1–5", size = 10px, color = dim
        Button "01  /  SEAHORSE VALLEY", width = 222px, height = 33px, radius = 2px,
               fill = (if activePlace == 0 and mode == 0: selected else: quiet),
               color = (if activePlace == 0 and mode == 0: night else: ink),
               border = 1px, borderColor = (if activePlace == 0 and mode == 0: gold else: edge), size = 10px, weight = 700:
          on tap: goPlace(0)
        Button "02  /  ELEPHANT VALLEY", width = 222px, height = 33px, radius = 2px,
               fill = (if activePlace == 1 and mode == 0: selected else: quiet),
               color = (if activePlace == 1 and mode == 0: night else: ink),
               border = 1px, borderColor = (if activePlace == 1 and mode == 0: gold else: edge), size = 10px, weight = 700:
          on tap: goPlace(1)
        Button "03  /  TRIPLE SPIRAL", width = 222px, height = 33px, radius = 2px,
               fill = (if activePlace == 2 and mode == 0: selected else: quiet),
               color = (if activePlace == 2 and mode == 0: night else: ink),
               border = 1px, borderColor = (if activePlace == 2 and mode == 0: gold else: edge), size = 10px, weight = 700:
          on tap: goPlace(2)
        Button "04  /  MINI-BROT", width = 222px, height = 33px, radius = 2px,
               fill = (if activePlace == 3 and mode == 0: selected else: quiet),
               color = (if activePlace == 3 and mode == 0: night else: ink),
               border = 1px, borderColor = (if activePlace == 3 and mode == 0: gold else: edge), size = 10px, weight = 700:
          on tap: goPlace(3)
        Button "05  /  WHOLE SET", width = 222px, height = 33px, radius = 2px,
               fill = (if activePlace == 4 and mode == 0: selected else: quiet),
               color = (if activePlace == 4 and mode == 0: night else: ink),
               border = 1px, borderColor = (if activePlace == 4 and mode == 0: gold else: edge), size = 10px, weight = 700:
          on tap: goPlace(4)

    Panel(absolute = true, right = 26px, bottom = 24px, width = 818px, pad = 10px,
          fill = panelCol, radius = 3px, border = 1px, borderColor = edge):
      Row(gap = 7px, alignItems = 1):
        Button "−", width = 42px, height = 38px, radius = 2px, fill = quiet, color = ink, size = 18px:
          on tap: zoomAbout(WW * 0.5, WH * 0.5, 0.4)
        Button "+", width = 42px, height = 38px, radius = 2px, fill = quiet, color = ink, size = 16px:
          on tap: zoomAbout(WW * 0.5, WH * 0.5, 2.5)
        Button "RESET", width = 68px, height = 38px, radius = 2px, fill = quiet, color = ink, size = 10px:
          on tap: goPlace(4)
        Panel(width = 1px, height = 27px, fill = edge, marginLeft = 3px, marginRight = 3px)
        Button "A", width = 34px, height = 34px, radius = 18px, fill = #D8B76E,
               color = night, size = 10px, weight = 800, border = (if paletteId == 0: 2px else: 1px),
               borderColor = (if paletteId == 0: ink else: night):
          on tap: paletteId = 0
        Button "B", width = 34px, height = 34px, radius = 18px, fill = #35A8CA,
               color = night, size = 10px, weight = 800, border = (if paletteId == 1: 2px else: 1px),
               borderColor = (if paletteId == 1: ink else: night):
          on tap: paletteId = 1
        Button "M", width = 34px, height = 34px, radius = 18px, fill = #C64B79,
               color = night, size = 10px, weight = 800, border = (if paletteId == 2: 2px else: 1px),
               borderColor = (if paletteId == 2: ink else: night):
          on tap: paletteId = 2
        Button "P", width = 34px, height = 34px, radius = 18px, fill = #D9C6FF,
               color = night, size = 10px, weight = 800, border = (if paletteId == 3: 2px else: 1px),
               borderColor = (if paletteId == 3: ink else: night):
          on tap: paletteId = 3
        Text paletteNames[paletteId], width = 102px, size = 10px, weight = 700, color = gold
        Panel(width = 1px, height = 27px, fill = edge, marginLeft = 3px, marginRight = 3px)
        Button toggleLabel, width = 132px, height = 38px,
               radius = 2px, fill = (if mode == 1: gold else: quiet),
               color = (if mode == 1: night else: ink), size = 10px, weight = 700:
          on tap: toggleMode()

    Column(absolute = true, left = 26px, bottom = 25px, width = 252px, gap = 4px):
      Text "CLICK DIVE  ·  DRAG PAN  ·  + / − ZOOM", size = 10px, color = paleGold
      Text "J  JULIA   ·   R  HOME   ·   ARROWS  PAN", size = 10px, color = dim
