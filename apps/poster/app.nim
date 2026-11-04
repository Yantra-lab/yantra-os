## Raster / Form — a deterministic Swiss editorial poster press.
## Seven drawn motifs, four paper-and-ink recipes and four compositional stances.
## Every control changes the retained Canvas programme; there is no embedded web code.

const
  SheetW = 640
  SheetH = 824
  PressFrames = 22            # frames one edition takes to print
  Mono = "DejaVu Sans Mono"
  Sans = "DejaVu Sans"

let
  studio = #10130F
  panel = #1A1E19
  raised = #272C25
  lineCol = #363D33
  uiInk = #F1EEE4
  uiMuted = #9AA393
  uiFaint = #697363
  hot = #F06442

# ── chance: all editions are pure functions of their printed number ───────────────
type Chance = object
  n: uint32

proc chance(seed, motif, layout: int): Chance =
  Chance(n: uint32(seed) * 747796405'u32 + uint32(motif * 977 + layout * 131) + 2891336453'u32)

proc next(c: var Chance): uint32 =
  c.n = c.n * 1664525'u32 + 1013904223'u32
  result = c.n

proc pick(c: var Chance; n: int): int =
  if n <= 1: 0 else: int(c.next() mod uint32(n))

proc padded(n, width: int): string =
  result = $n
  while result.len < width: result = "0" & result

proc editionLine(seed: int): string = padded(seed, 4)

proc fit(s: string; width, cap: float): float =
  min(cap, width / max(1.0, float(s.len) * 0.64))

proc argb(c: Color): uint32 = uint32(c)
proc inkAlpha(c: uint32; a: int): uint32 = (c and 0x00FFFFFF'u32) or (uint32(a) shl 24)

proc paperOf(p: int): uint32 =
  [0xFFF2EFE8'u32, 0xFFEDF2F4'u32, 0xFFF4E6CF'u32, 0xFF171816'u32][p]
proc inkOf(p: int): uint32 =
  [0xFF171714'u32, 0xFF112C3B'u32, 0xFF26312A'u32, 0xFFF0EBDD'u32][p]
proc accentOf(p: int): uint32 =
  [0xFFE30613'u32, 0xFF005FCC'u32, 0xFFE3462F'u32, 0xFFFF6038'u32][p]
proc paletteName(p: int): string = ["Signal", "Cobalt", "Risograph", "Nocturne"][p]
proc motifName(m: int): string =
  ["Zahl / numeral", "Drei Sprachen", "Bogen / arcs", "Kreis / eclipse",
   "Takt / rhythm", "Senkrecht / field", "Diagonale"][m]
proc layoutName(l: int): string = ["Axis left", "Counter axis", "Low horizon", "Off centre"][l]

proc words(seed: int): array[3, string] =
  let bank = [["KLANG", "SON", "SUONO"], ["RAUM", "ESPACE", "SPAZIO"],
              ["ZEIT", "TEMPS", "TEMPO"], ["LICHT", "LUMIÈRE", "LUCE"],
              ["FORM", "FORME", "FORMA"], ["LINIE", "LIGNE", "LINEA"],
              ["RASTER", "GRILLE", "GRIGLIA"], ["FARBE", "COULEUR", "COLORE"],
              ["ORDNUNG", "ORDRE", "ORDINE"], ["RHYTHMUS", "RYTHME", "RITMO"]]
  bank[seed mod bank.len]

proc gx(c: int): float = 36.0 + float(c) * 48.0
proc gy(r: int): float = 36.0 + float(r) * 48.0
proc mirrorX(x, w: float; flip: bool): float = (if flip: SheetW.float - x - w else: x)

proc txt(d: Draw; x, y, size: float; col: uint32; s: string; weight = 700): Draw =
  d.textFace(x, y, size, col, Sans, s, weight)

proc micro(d: Draw; x, y: float; col: uint32; s: string): Draw =
  d.textFace(x, y, 9, col, Mono, s, 500)

proc bigWord(d: Draw; s: string; x, y, width, cap: float; col: uint32; right = false): Draw =
  let size = fit(s, width, cap)
  let tx = if right: x + width - size * float(s.len) * 0.64 else: x
  txt(d, tx, y, size, col, s, 800)

proc quarter(d: Draw; cx, cy, r, startDeg: float; col: uint32): Draw =
  let a = startDeg * PI / 180.0
  d.moveTo(cx, cy).lineTo(cx + cos(a) * r, cy + sin(a) * r)
    .arcTo(cx, cy, r, startDeg, 90).close().fill(col)

proc editionFurniture(d0: Draw; seed, palette, layout: int): Draw =
  ## Small type is deliberately subordinate to one loud typographic gesture.
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let paper = paperOf(palette)
  let faint = inkAlpha(ink, (if paper == 0xFF171816'u32: 150 else: 120))
  result = txt(result, 36, 35, 12, ink, "HAUS RASTER", 800)
  result = micro(result, 36, 54, faint, "INTERNATIONALE TYPOGRAPHIE / 1957—2027")
  result = micro(result, (if layout mod 2 == 0: 416.0 else: 424.0), 37, ink,
                "ED. " & editionLine(seed) & "  /  CH—ZÜRICH")
  result = result.line(36, 81, 604, 81, ink, 2)
  result = result.rect(36, 75, 20, 6, red)
  # The lower information block realigns with each composition, never habitually centred.
  result = result.line(36, 653, 604, 653, ink, 2)
  let flip = layout mod 2 == 1
  let hx = if flip: 356.0 else: 36.0
  let dx = if flip: 36.0 else: 356.0
  result = txt(result, hx, 674, 13, ink, "KONZERTREIHE FÜR NEUE MUSIK", 800)
  result = txt(result, hx, 699, 12, red, "CONCERT SERIES FOR NEW MUSIC", 600)
  result = micro(result, hx, 727, faint, "GROSSER SAAL · HAUS RASTER · EINTRITT FREI")
  result = txt(result, dx, 675, 26, ink, $(8 + seed mod 23) & ". NOV 2027", 700)
  result = micro(result, dx, 713, faint, (if flip: "20.00 UHR / TÜR 19.30" else: "MONTAG / 20.00 UHR"))
  result = micro(result, dx, 729, faint, "ZWÖLF REIHEN / SIEBEN KLÄNGE")
  result = result.line(36, 758, 604, 758, faint, 1)
  result = micro(result, 36, 776, ink, "WELTFORMAT F4 · OFFSET IN " & paletteName(palette).toUpperAscii)
  result = txt(result, 36, 789, 15, red, "No. " & editionLine(seed), 800)
  result = micro(result, (if flip: 433.0 else: 385.0), 796, ink,
                (if layout == 2: "FORM FOLLOWS THE GRID" else: "GRID IS A QUIET AGREEMENT"))

# ── seven motifs, each with real geometry and seed-dependent composition ─────────
proc motifZahl(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  let number = $(10 + seed mod 89)
  let cx = if flip: 205.0 else: 442.0
  let cy = if layout == 2: 382.0 else: 313.0
  let radius = 132.0 + float(density) * 14.0
  result = result.circle(cx, cy, radius, red)
  let right = not flip
  let nx = if flip: 42.0 else: 244.0
  result = txt(result, nx, 151 + float(layout == 2) * 52.0, fit(number, 355, 262), ink, number, 800)
  var ring = Draw()
  ring = ring.arcTo(cx, cy, radius * 0.63, 0, 360).stroke(red, 3)
  result.cmds.add ring.cmds
  result = bigWord(result, words(seed)[0], 36, 481 - float(layout == 2) * 35.0, 568, 106, ink, right)
  result = quarter(result, mirrorX(36, 92, flip), 576, 92, (if flip: 270.0 else: 180.0), ink)
  for i in 0 ..< 3 + density:
    let x = if flip: 506.0 else: 36.0 + float(i) * 27.0
    result = result.rect(x, 118, 14, 4 + float(i mod 2) * 5, red)

proc motifLanguages(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  let ws = words(seed)
  let hotAt = c.pick(3)
  let startY = if layout >= 2: 139.0 else: 113.0
  for i in 0 .. 2:
    let col = if i == hotAt: red else: ink
    result = bigWord(result, ws[i], 36, startY + float(i) * 139.0, 568, 126, col, flip)
    result = micro(result, (if flip: 36.0 else: 574.0), startY + 7 + float(i) * 139.0, col,
                  ["DE", "FR", "IT"][i])
  let baseline = 583.0
  for i in 0 ..< 12:
    let t = float((if flip: 11 - i else: i)) / 11.0
    let r = 3.0 + t * (9.0 + density.float * 2.0)
    result = result.circle(gx(i) + 20, baseline, r, (if i == hotAt * 4: red else: ink))
  result = result.line(36, 615, 604, 615, red, 5)

proc motifArcs(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  let cx = if flip: 604.0 else: 36.0
  let cy = if layout >= 2: 594.0 else: 627.0
  let start = if flip: 180.0 else: 270.0
  result = bigWord(result, words(seed)[0], 36, 113, 568, 110, ink, flip)
  result = micro(result, (if flip: 412.0 else: 36.0), 218, red, "(" & words(seed)[1] & " / " & words(seed)[2] & ")")
  let rings = 6 + density
  let selected = 1 + c.pick(rings - 1)
  for i in 1 .. rings:
    let r = 33.0 + float(i) * 43.0
    var arc = Draw()
    arc = arc.arcTo(cx, cy, r, start, 90).stroke((if i == selected: red else: ink),
                                                (if i mod 3 == 0: 13.0 else: 3.0 + density.float))
    result.cmds.add arc.cmds
  result = quarter(result, cx, cy, 69, start, red)
  let bx = if flip: 36.0 else: 565.0
  result = result.rect(bx, 299, 39, 189, red)
  result = result.circle((if flip: 110.0 else: 530.0), 552, 15, ink)

proc motifCircle(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let paper = paperOf(palette)
  let flip = layout mod 2 == 1
  let cx = if flip: 240.0 else: 393.0
  let cy = if layout >= 2: 365.0 else: 335.0
  let r = 165.0 + float(density) * 17.0
  result = result.circle(cx, cy, r, red)
  result = result.circle(cx + (if flip: 102.0 else: -102.0), cy - 94, r * 0.39, ink)
  var ring = Draw()
  ring = ring.arcTo(cx, cy, r * 0.72, 0, 360).stroke(inkAlpha(paper, 235), 3)
  result.cmds.add ring.cmds
  result = bigWord(result, words(seed)[0], 36, 482, 568, 118, ink, flip)
  result = result.rect(mirrorX(37, 12, flip), 126, 12, 280, red)
  for i in 0 ..< 5 + density:
    result = result.circle(48 + float(i) * 14, 573, (if i == 0: 5.0 else: 2.5), ink)
  result = micro(result, (if flip: 466.0 else: 36.0), 126, ink, "SCHEIBE / 01—" & padded(density + 5, 2))

proc motifBars(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  let signature = ["2/4", "3/4", "4/4", "5/4", "6/8", "7/8"][seed mod 6]
  result = txt(result, (if flip: 351.0 else: 36.0), 105, 150, ink, signature, 800)
  result = micro(result, (if flip: 36.0 else: 473.0), 129, red, "TAKT / MASS / BEAT")
  let n = 12
  var heights: array[12, int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  for i in 0 ..< n:
    heights[i] = 2 + c.pick(5 + density * 2)
  for i in 0 ..< n:
    let j = if flip: n - 1 - i else: i
    let h = float(heights[j]) * 31.0
    let w = [9.0, 15.0, 25.0, 34.0][c.pick(4)]
    let x = gx(i) + (if flip: 40.0 - w else: 0.0)
    let selected = (i + seed) mod 5 != 0
    result = result.rect(x, 613 - h, w, h, (if selected: red else: ink))
  result = result.rect(36, 616, 568, 3, ink)
  result = bigWord(result, words(seed)[0], 36, 526 - float(layout >= 2) * 35.0, 350, 63, ink, flip)
  result = micro(result, 36, 633, ink, "12 MODULE · " & $(6 + density * 2) & " DYNAMIC LEVELS")

proc motifField(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  let rows = 9 + density * 2
  let cols = 8 + density * 2
  let focalX = float(1 + c.pick(cols - 2))
  let focalY = float(1 + c.pick(rows - 2))
  for j in 0 ..< rows:
    for i in 0 ..< cols:
      let ii = if flip: cols - 1 - i else: i
      let dx = (float(ii) - focalX) / float(cols)
      let dy = (float(j) - focalY) / float(rows)
      let distance = sqrt(dx * dx + dy * dy) * 1.5
      let r = max(1.2, (1.0 - min(1.0, distance)) * (13.0 + density.float * 2.0))
      let x = 224.0 + float(i) * (360.0 / float(cols - 1))
      let y = 126.0 + float(j) * (474.0 / float(rows - 1))
      result = result.circle(x, y, r, (if abs(dx) + abs(dy) < 0.06: red else: ink))
  let tx = if flip: 118.0 else: 58.0
  result = result.save().translate(tx, 605)
  result = result.rotate(-90)
  result = bigWord(result, words(seed)[0], 0, 0, 470, 95, (if seed mod 2 == 0: red else: ink))
  result = result.restore()
  result = result.rect((if flip: 42.0 else: 181.0), 122, 5, 484, red)

proc motifDiagonal(d0: Draw; seed, palette, layout, density: int; c: var Chance): Draw =
  result = d0
  let ink = inkOf(palette)
  let red = accentOf(palette)
  let flip = layout mod 2 == 1
  result = bigWord(result, words(seed)[0], 36, 109, 568, 116, ink, flip)
  result = result.save().clip(36, 244, 568, 371).translate(320, 425)
  result = result.rotate((if flip: -34.0 else: 32.0) + float(layout - 1) * 4.0)
  let count = 5 + density
  for i in 0 ..< count:
    let h = if i mod 2 == 0: 44.0 else: 10.0
    let y = float(i - count div 2) * 63.0
    let w = 520.0 - float(c.pick(4)) * 54.0
    result = result.rect(-w / 2, y, w, h, (if i mod 3 == 0: ink else: red))
  result = result.restore()
  result = result.circle(mirrorX(85, 85, flip), 578, 42, ink)
  result = quarter(result, mirrorX(519, 85, flip), 536, 85, (if flip: 90.0 else: 0.0), red)
  result = micro(result, (if flip: 36.0 else: 487.0), 230, red, "ACHSENBRUCH / 32°")

proc paperTooth(d0: Draw; palette, seed: int): Draw =
  ## A printed sheet is never one tone. Three passes, all deterministic:
  ## the fractal tooth of the stock (`z`, four octaves of Perlin),
  ## the impression — the roller presses harder in the sheet's centre and
  ## lifts at the deckle edge — and a faint vertical roller streak.
  ## Before this, 79.4 % of the 640 × 824 sheet was ONE flat colour
  ## (measured on the frame at 1280 × 960, tag poster_base960).
  let paper = paperOf(palette)
  let ink = inkOf(palette)
  result = d0
  result = result.noiseRect(0, 0, float(SheetW), float(SheetH),
                            inkAlpha(paper, 0), inkAlpha(ink, 12),
                            freq = 0.42'f32, freqY = 0.42'f32, octaves = 4,
                            seed = float(seed mod 977))
  result = result.radialRect(0, 0, float(SheetW), float(SheetH),
                             inkAlpha(ink, 0), inkAlpha(ink, 16),
                             float(SheetW) * 0.5, float(SheetH) * 0.46, 560)
  var streak = Draw()
  for i in 0 ..< 26:
    let x = 6.0 + float(i) * 24.0 + float(i * 7 mod 9)
    streak = streak.line(x, 2, x, float(SheetH) - 2, inkAlpha(ink, 3 + (i * 5) mod 7), 1.6)
  result.cmds.add streak.cmds
  result = result.noiseRect(0, 0, float(SheetW), float(SheetH),
                            inkAlpha(paper, 0), inkAlpha(ink, 9),
                            freq = 2.6'f32, freqY = 0.08'f32, octaves = 2,
                            seed = float((seed + 31) mod 613))

proc gridRules(d0: Draw; palette: int): Draw =
  ## The twelve columns are DRAWN, not implied by the rectangles: column rules
  ## printed under the art (so a shape covers them, the margins keep them), the
  ## fifteen module ticks captured in the side margins, and four registration
  ## crosses. This is the poster's own claim — "the grid is a quiet agreement".
  ## Before this the sheet had no column structure at all outside the optional
  ## blue guides, and its first grid cell was 98.2 % one flat colour.
  let ink = inkOf(palette)
  let rule = inkAlpha(ink, 22)
  let tick = inkAlpha(ink, 46)
  result = d0
  var g = Draw()
  for i in 0 ..< 12:
    g = g.line(gx(i), 92, gx(i), 748, rule, 0.8)
  g = g.line(604, 92, 604, 748, rule, 0.8)
  for j in 0 ..< 15:
    let y = gy(j + 2)
    g = g.line(30, y, 35, y, tick, 1.0).line(605, y, 610, y, tick, 1.0)
    g = g.line(30, y + 40, 35, y + 40, tick, 1.0).line(605, y + 40, 610, y + 40, tick, 1.0)
  let marks = [(20.0, 20.0), (620.0, 20.0), (20.0, 804.0), (620.0, 804.0)]
  for k in 0 ..< marks.len:
    let cx = marks[k][0]
    let cy = marks[k][1]
    g = g.line(cx - 7, cy, cx + 7, cy, tick, 0.9).line(cx, cy - 7, cx, cy + 7, tick, 0.9)
    g = g.circle(cx, cy, 4.6, paperOf(palette))   # the cross opens at its centre
  result.cmds.add g.cmds

proc pressMask(d0: Draw; palette, reveal: int): Draw =
  ## THE PRESS. While `reveal` runs 0 -> PressFrames the ink arrives from the top
  ## of the sheet downward behind one red impression bar; at PressFrames the mask
  ## has zero height and the frame is exactly the poster it always was, so the
  ## result is still a pure function of the edition (no clock, no randomness).
  result = d0
  if reveal >= PressFrames: return
  let t = float(reveal) / float(PressFrames)
  let p = 1.0 - (1.0 - t) * (1.0 - t)          # the bar decelerates as it lands
  let y = float(SheetH) * p
  result = result.rect(0, y, float(SheetW), float(SheetH) - y, paperOf(palette))
  result = result.rect(0, max(0.0, y - 2.0), float(SheetW), 3.0, accentOf(palette))

proc posterDraw(seed, motif, palette, layout, density: int; showGrid: bool; reveal = PressFrames): Draw =
  var c = chance(seed, motif, layout)
  result = Draw().rect(0, 0, float(SheetW), float(SheetH), paperOf(palette))
  result = paperTooth(result, palette, seed)
  result = gridRules(result, palette)
  case motif
  of 0: result = motifZahl(result, seed, palette, layout, density, c)
  of 1: result = motifLanguages(result, seed, palette, layout, density, c)
  of 2: result = motifArcs(result, seed, palette, layout, density, c)
  of 3: result = motifCircle(result, seed, palette, layout, density, c)
  of 4: result = motifBars(result, seed, palette, layout, density, c)
  of 5: result = motifField(result, seed, palette, layout, density, c)
  else: result = motifDiagonal(result, seed, palette, layout, density, c)
  result = editionFurniture(result, seed, palette, layout)
  if showGrid:
    let guide = if palette == 3: 0x9959D9FF'u32 else: 0x9900A0DC'u32
    for i in 0 ..< 12:
      result = result.rect(gx(i), gy(2), 40, 696, inkAlpha(guide, 20))
      result = result.line(gx(i), gy(2), gx(i), 748, guide, 0.7)
      result = result.line(gx(i) + 40, gy(2), gx(i) + 40, 748, guide, 0.7)
      result = micro(result, gx(i) + 3, 92, guide, padded(i + 1, 2))
    for j in 0 ..< 15:
      result = result.line(36, gy(j + 2), 604, gy(j + 2), guide, 0.7)
      result = result.line(36, gy(j + 2) + 40, 604, gy(j + 2) + 40, guide, 0.7)
      result = micro(result, 14, gy(j + 2) + 3, guide, $(j + 1))
    result = result.rect(592, 790, 12, 12, guide)
  result = pressMask(result, palette, reveal)

proc posterCommands(seed, motif, palette, layout, density: int; showGrid: bool;
                    reveal = PressFrames): string =
  posterDraw(seed, motif, palette, layout, density, showGrid, reveal).cmds

# ── state and the studio ───────────────────────────────────────────────────────
proc selected(on: bool): Color = (if on: uiInk else: raised)
proc selectedInk(on: bool): Color = (if on: studio else: uiMuted)
proc motifFor(seed: int): int = (seed + 3) mod 7
proc applyEdition(seed: int): int = seed mod 4

proc tableArt(): string =
  ## The table the sheet lies on. The window behind the sheet used to be ONE flat
  ## #10130F rectangle — 24 % of the frame at its top colour and 57 % of the frame
  ## darker than luma 120 — a dead background, which is the signature of a cheap
  ## frame. Now it is a lit surface: a falling light from the top, the tooth of
  ## the table, a warm lamp pool under the sheet, and a vignette at the corners.
  Draw()
    .linearDown(0, 0, 1280, 960, 0xFF262C24'u32, 0xFF0A0C09'u32)
    .noiseRect(0, 0, 1280, 960, 0x00262C24'u32, 0x2A1B211C'u32,
               freq = 0.55'f32, freqY = 0.55'f32, octaves = 4, seed = 417.0'f32)
    .radialRect(0, 0, 1280, 960, 0x3AF2EFE8'u32, 0x00F2EFE8'u32, 470, 500, 700)
    .radialRect(0, 0, 1280, 960, 0x00000000'u32, 0x66000000'u32, 640, 480, 900).cmds

view Poster
  state seed = 417
  state motif = 0
  state palette = 0
  state layout = 1
  state density = 1
  state gridOn = false
  state exportStatus = "Ready · export uses this sheet’s exact RGBA pixels"
  state press = 0
  on frame:
    if press < PressFrames: press += 1

  Stack(fill = studio, width = 1280px, height = 960px):
    Canvas(draw = tableArt(), width = 1280px, height = 960px, absolute = true, left = 0px, top = 0px)
    # Masthead
    Text "RASTER / FORM", size = 25px, weight = 800, color = uiInk, font = Sans, absolute = true, left = 40px, top = 22px
    Text "DETERMINISTIC SWISS POSTER PRESS", size = 9px, weight = 600, color = uiMuted, font = Mono, absolute = true, left = 300px, top = 32px
    Text "640 × 824  /  LIVE CANVAS  /  EDITION " & editionLine(seed), size = 9px, weight = 600, color = uiMuted, font = Mono, absolute = true, left = 930px, top = 32px
    Panel(fill = lineCol, absolute = true, left = 40px, top = 64px, width = 1200px, height = 1px)
    # The sheet and a physical, offset shadow.
    Panel(fill = #060806, absolute = true, left = 50px, top = 91px, width = 640px, height = 824px)
    Canvas(draw = posterCommands(seed, motif, palette, layout, density, gridOn, press), width = 640px, height = 824px, absolute = true, left = 40px, top = 80px):
      on tap: seed = (seed mod 9999) + 1; motif = motifFor(seed); layout = applyEdition(seed); press = 0
    Text "TAP THE SHEET FOR THE NEXT EDITION", size = 8px, weight = 600, color = uiFaint, font = Mono, absolute = true, left = 40px, top = 925px
    Text "SAME INPUT / SAME PIXELS", size = 8px, weight = 600, color = uiFaint, font = Mono, absolute = true, left = 499px, top = 925px

    Panel(fill = panel, radius = 12px, border = 1px, borderColor = lineCol, pad = 22px, absolute = true, left = 728px, top = 80px, width = 512px, height = 824px):
      Column(gap = 10px):
        Row(gap = 12px, alignItems = 1):
          Column(gap = 3px, grow = 1):
            Text "COMPOSITION DESK", size = 10px, weight = 700, color = uiMuted, font = Mono
            Text motifName(motif), size = 20px, weight = 700, color = uiInk, font = Sans
          Panel(fill = hot, width = 8px, height = 36px)
        Row(gap = 10px, height = 72px, alignItems = 1):
          Button "←", width = 42px, height = 46px, fill = raised, color = uiInk, radius = 5px, font = Sans, size = 17px:
            on tap: seed = (if seed <= 1: 9999 else: seed - 1); motif = motifFor(seed); layout = applyEdition(seed); press = 0
          Column(grow = 1, gap = 0):
            Text "EDITION / SEED", size = 8px, weight = 700, color = uiFaint, font = Mono
            Text editionLine(seed), size = 37px, weight = 800, color = uiInk, font = Mono
          Button "→", width = 42px, height = 46px, fill = raised, color = uiInk, radius = 5px, font = Sans, size = 17px:
            on tap: seed = (seed mod 9999) + 1; motif = motifFor(seed); layout = applyEdition(seed); press = 0
        Row(gap = 8px):
          Button "New edition", grow = 1, height = 41px, fill = hot, color = #171714, radius = 5px, font = Sans, size = 12px, weight = 800:
            on tap: seed = (seed mod 9999) + 1; motif = motifFor(seed); layout = applyEdition(seed); press = 0
          Button "Recompose", grow = 1, height = 41px, fill = raised, color = uiInk, radius = 5px, font = Sans, size = 12px, weight = 700:
            on tap: layout = (layout + 1) mod 4; press = 0
        Panel(fill = lineCol, height = 1px)

        Text "01 / MOTIF", size = 9px, weight = 700, color = uiMuted, font = Mono
        Row(gap = 6px):
          Button "01 ZAHL", width = 109px, height = 35px, fill = selected(motif == 0), color = selectedInk(motif == 0), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 0; press = 0
          Button "02 SPRACHE", width = 109px, height = 35px, fill = selected(motif == 1), color = selectedInk(motif == 1), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 1; press = 0
          Button "03 BOGEN", width = 109px, height = 35px, fill = selected(motif == 2), color = selectedInk(motif == 2), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 2; press = 0
          Button "04 KREIS", width = 109px, height = 35px, fill = selected(motif == 3), color = selectedInk(motif == 3), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 3; press = 0
        Row(gap = 6px):
          Button "05 TAKT", width = 109px, height = 35px, fill = selected(motif == 4), color = selectedInk(motif == 4), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 4; press = 0
          Button "06 FELD", width = 109px, height = 35px, fill = selected(motif == 5), color = selectedInk(motif == 5), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 5; press = 0
          Button "07 DIAGONAL", width = 109px, height = 35px, fill = selected(motif == 6), color = selectedInk(motif == 6), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: motif = 6; press = 0
          Panel(grow = 1)
        Text "02 / COMPOSITION", size = 9px, weight = 700, color = uiMuted, font = Mono
        Row(gap = 6px):
          Button "LEFT", width = 109px, height = 32px, fill = selected(layout == 0), color = selectedInk(layout == 0), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: layout = 0; press = 0
          Button "COUNTER", width = 109px, height = 32px, fill = selected(layout == 1), color = selectedInk(layout == 1), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: layout = 1; press = 0
          Button "LOW", width = 109px, height = 32px, fill = selected(layout == 2), color = selectedInk(layout == 2), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: layout = 2; press = 0
          Button "OFFSET", width = 109px, height = 32px, fill = selected(layout == 3), color = selectedInk(layout == 3), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: layout = 3; press = 0
        Row(height = 18px):
          Text layoutName(layout), size = 9px, weight = 600, color = uiFaint, font = Mono
          Text "12 × 15 MODULES", size = 8px, weight = 600, color = uiFaint, font = Mono, grow = 1, align = 2

        Text "03 / PAPER + INK", size = 9px, weight = 700, color = uiMuted, font = Mono
        Row(gap = 6px):
          Button "SIGNAL", width = 109px, height = 35px, fill = selected(palette == 0), color = selectedInk(palette == 0), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: palette = 0; press = 0
          Button "COBALT", width = 109px, height = 35px, fill = selected(palette == 1), color = selectedInk(palette == 1), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: palette = 1; press = 0
          Button "RISO", width = 109px, height = 35px, fill = selected(palette == 2), color = selectedInk(palette == 2), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: palette = 2; press = 0
          Button "NIGHT", width = 109px, height = 35px, fill = selected(palette == 3), color = selectedInk(palette == 3), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: palette = 3; press = 0
        Text "04 / OPTICAL DENSITY", size = 9px, weight = 700, color = uiMuted, font = Mono
        Row(gap = 6px, alignItems = 1):
          Button "SPARSE", width = 109px, height = 32px, fill = selected(density == 0), color = selectedInk(density == 0), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: density = 0; press = 0
          Button "BALANCED", width = 109px, height = 32px, fill = selected(density == 1), color = selectedInk(density == 1), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: density = 1; press = 0
          Button "DENSE", width = 109px, height = 32px, fill = selected(density == 2), color = selectedInk(density == 2), radius = 4px, font = Sans, size = 9px, weight = 700:
            on tap: density = 2; press = 0
          Text "0" & $(density + 1), size = 18px, weight = 700, color = uiMuted, font = Mono, grow = 1, align = 2
        Panel(fill = lineCol, height = 1px)

        Row(gap = 8px):
          Button (if gridOn: "Grid  /  on" else: "Grid  /  off"), grow = 1, height = 38px,
                 fill = selected(gridOn), color = selectedInk(gridOn), radius = 4px, font = Sans, size = 11px, weight = 700:
            on tap: gridOn = not gridOn; press = 0
          Button "Surprise seed", grow = 1, height = 38px, fill = raised, color = uiInk, radius = 4px, font = Sans, size = 11px, weight = 800:
            on tap: seed = ((seed * 73 + 90) mod 9999) + 1; motif = motifFor(seed); layout = applyEdition(seed); press = 0
        Button "Export PNG", height = 38px, fill = uiInk, color = studio, radius = 4px, font = Sans, size = 11px, weight = 800:
          on tap:
            exportStatus = "Encoding 640 × 824 RGBA pixels…"
            let pngName = "poster-" & editionLine(seed) & ".png"
            let sheet = newLayer(SheetW, SheetH)
            sheet.draw(posterDraw(seed, motif, palette, layout, density, gridOn))
            let queued = sheet.savePng(pngName, proc (ok: bool) {.closure.} =
              exportStatus = (if ok: "PNG saved · " & pngName else: "PNG save cancelled or failed"))
            sheet.free()
            if queued:
              exportStatus = "Choose destination · " & pngName & (if gridOn: " · guides included" else: "")
            else:
              exportStatus = "PNG could not be encoded · no dialog queued"
        Text exportStatus, size = 8px, color = uiFaint, font = Mono
        Row(gap = 8px):
          Text "SEED LOCK", size = 8px, weight = 700, color = hot, font = Mono
          Text "Pure geometry · fixed copy · no clock", size = 8px, color = uiFaint, font = Mono, grow = 1
        Button "Reset to edition 0417", height = 28px, fill = panel, color = uiFaint, radius = 3px, size = 8px, font = Mono:
          on tap:
            seed = 417; motif = 0; palette = 0; layout = 1; density = 1; gridOn = false
            press = 0
            exportStatus = "Ready · export uses this sheet’s exact RGBA pixels"
        Panel(fill = studio, radius = 4px, pad = 12px):
          Column(gap = 5px):
            Text "PRINT REGISTER / LIVE", size = 8px, weight = 700, color = uiFaint, font = Mono
            Text paletteName(palette) & " paper + ink  /  density 0" & $(density + 1), size = 10px, color = uiMuted, font = Mono
            Text "Motif 0" & $(motif + 1) & "  /  " & layoutName(layout), size = 10px, color = uiMuted, font = Mono
            Panel(fill = lineCol, height = 1px)
            Text "NO CLOCK · NO NETWORK · NO AMBIENT RANDOMNESS", size = 7px, color = uiFaint, font = Mono
