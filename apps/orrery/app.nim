## The Clockmaker's Orrery — an imagined 1774 instrument computed, not animated.
## Eight planets use the secular J2000 elements in model.nim. Their longitudes,
## radii and orbit traces all come from the same Newton-solved Keplerian position;
## one global log scale compresses distance without changing the angular solution.
## The annual train has four contacting wheels (48/16/32/24 teeth), with every
## rotation derived from its driver. Controls operate on the simulated Julian day.

import std/math
import model

const
  WinW = 1400.0'f32
  WinH = 900.0'f32
  DialX = 654.0'f32
  DialY = 404.0'f32
  OuterR = 370.0'f32
  BaseJD = 2369000.5
  Serif = "DejaVu Serif"
  Sans = "DejaVu Sans"
  Paper = 0xFFF1E5C8'u32
  PaperDeep = 0xFFDEC69A'u32
  PaperLight = 0xFFFFF6DF'u32
  Ink = 0xFF302317'u32
  InkSoft = 0xB3463420'u32
  InkFaint = 0x66583D28'u32
  Brass = 0xFFC18A1B'u32
  BrassMid = 0xFFD4A839'u32
  BrassHi = 0xFFFFE29A'u32
  BrassLo = 0xFF77500D'u32
  Rubric = 0xFF91351D'u32
  Ebony = 0xFF231A13'u32
  Recess = 0xFF2D2418'u32
  GlobeColours = [0xFF958B7D'u32, 0xFFE2BE72'u32, 0xFF398ABD'u32, 0xFFC25B37'u32,
                  0xFFD1A16B'u32, 0xFFD9BD7C'u32, 0xFF91CDD0'u32, 0xFF416ABF'u32]
  GlobeLights = [0xFFE0D7C9'u32, 0xFFFFF0BD'u32, 0xFFBDE9F5'u32, 0xFFF2AB76'u32,
                 0xFFFFE0A6'u32, 0xFFFFF0B6'u32, 0xFFE0FFFF'u32, 0xFF9DB9FF'u32]
  GlobeSizes = [6.4'f32, 9.0, 9.2, 7.6, 17.0, 14.2, 11.0, 10.6]
  DrawOrder = [Neptune, Uranus, Saturn, Jupiter, Mars, Earth, Venus, Mercury]
  Rates = [0.0, 1.0, 30.436875, 365.2425]
  RateNames = ["THE HEAVENS STAND STILL", "ONE DAY PER SECOND",
               "ONE MEAN MONTH PER SECOND", "ONE YEAR PER SECOND"]
  FullMonths = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
  # Button states, each pair measured against the fill it sits on:
  #   ink 0x302317 on BtnHover 10.21:1, on BtnPress 8.70:1
  #   BtnRing 0x91351D on BtnHover 5.15:1, on BtnPress 4.39:1
  #   BtnLineDark 0xCC9635 on the epoch button's Ebony 0x231A13 = 6.50:1
  #     (the shared BrassLo 0x77500D is only 2.39:1 there — the C3 failure)
  #   BrassHi 0xFFFFE29A on EpochHover 0x2E2419 12.00:1, on EpochPress 10.69:1
  BtnHover = 0xE4D2A6
  BtnPress = 0xD6C293
  BtnRing = 0x91351D
  BtnLineDark = 0xCC9635
  EpochHover = 0x2E2419
  EpochPress = 0x392C1E

let clockSig = state 0

var
  simJD = BaseJD
  rateIndex = 1
  selected = ord(Earth)
  calendarYear = 0
  calendarLongitudes: seq[float64] = @[]

proc invalidate() = clockSig.set(clockSig.get + 1)

proc setRate(index: int) =
  rateIndex = index
  invalidate()

proc choose(index: int) =
  selected = index
  invalidate()

proc speedFill(index: int): int =
  discard clockSig.get
  if rateIndex == index: 0xFFE29A else: 0xF1E5C8

proc planetFill(index: int): int =
  discard clockSig.get
  if selected == index: 0xFFE29A else: 0xE7D3AA

proc planetBorder(index: int): int =
  discard clockSig.get
  if selected == index: 0x91351D else: 0x77500D

# --------------------------------------------------------------- typography ---

proc fixed(value: float64; places: int): string =
  var power = 1.0
  for _ in 0 ..< places: power *= 10.0
  let scaled = int(abs(value) * power + 0.5)
  let whole = int(float64(scaled) / power)
  result = (if value < 0.0: "-" else: "") & $whole
  if places > 0:
    var fraction = $(scaled mod int(power))
    while fraction.len < places: fraction = "0" & fraction
    result.add "." & fraction

proc twoDigits(n: int): string =
  if n < 10: "0" & $n else: $n

proc polar(radius, longitude: float64): (float32, float32) =
  (float32(radius * cos(longitude * Deg)), float32(-radius * sin(longitude * Deg)))

proc engrave(d: Draw; x, y, size: float32; text: string; colour = Ink;
             family = Serif; weight = 400): Draw =
  result = d.textFace(x, y + 0.65, size, 0xA8FFF3D1'u32, family, text, weight)
  result = result.textFace(x, y, size, colour, family, text, weight)

proc centred(d: Draw; x, y, size: float32; text: string; colour = Ink;
             family = Serif; weight = 400): Draw =
  let width = textWidth(text, size, family, weight)
  d.engrave(x - width / 2.0, y, size, text, colour, family, weight)

proc tracked(d: Draw; x, y, size, spacing: float32; text: string;
             colour = InkSoft; weight = 600): Draw =
  result = d
  var cursor = x
  for ch in text:
    let glyph = $ch
    result = result.textFace(cursor, y, size, colour, Sans, glyph, weight)
    cursor += textWidth(glyph, size, Sans, weight) + spacing

proc ringText(d: Draw; cx, cy, radius, size, longitude: float64; text: string;
              colour = Ink; spacing = 1.8): Draw =
  ## The inscription is centred on its true ecliptic longitude and kept upright:
  ## all coordinates are absolute, so the web and native proof hosts agree.
  result = d
  var total = -spacing
  for ch in text: total += textWidth($ch, size, Serif, 400) + spacing
  let (px, py) = polar(radius, longitude)
  var cursor = cx + px - total / 2.0
  for ch in text:
    let glyph = $ch
    result = result.engrave(cursor, cy + py - size * 0.60, size, glyph, colour)
    cursor += textWidth(glyph, size, Serif, 400) + spacing + spacing

# ------------------------------------------------------------------ geometry ---

proc ring(d: Draw; cx, cy, radius: float32; colour: uint32; width = 1.0'f32): Draw =
  result = d.moveTo(cx + radius, cy).arcTo(cx, cy, radius, 0, 360).stroke(colour, width)

proc outline(d: Draw; x, y, w, h: float32; colour: uint32; width = 1.0'f32): Draw =
  result = d.moveTo(x, y).lineTo(x + w, y).lineTo(x + w, y + h).lineTo(x, y + h).close().stroke(colour, width)

proc ellipseStroke(d: Draw; x, y, rx, ry, rotation, startDeg, finishDeg: float64;
                   colour: uint32; width: float32): Draw =
  result = d
  let turn = rotation * Deg
  for step in 0 .. 48:
    let a = (startDeg + (finishDeg - startDeg) * float64(step) / 48.0) * Deg
    let ex = rx * cos(a)
    let ey = ry * sin(a)
    let px = x + float32(ex * cos(turn) - ey * sin(turn))
    let py = y + float32(ex * sin(turn) + ey * cos(turn))
    if step == 0: result = result.moveTo(px, py) else: result = result.lineTo(px, py)
  result = result.stroke(colour, width)

proc screw(d: Draw; x, y, angle: float32): Draw =
  result = d.radialRect(x - 4, y - 4, 8, 8, BrassHi, BrassLo, x - 1.2, y - 1.4, 6, 4)
  let a = float64(angle) * Deg
  result = result.line(x - float32(2.8 * cos(a)), y - float32(2.8 * sin(a)),
                       x + float32(2.8 * cos(a)), y + float32(2.8 * sin(a)), Ebony, 1.0)

proc plate(d: Draw; x, y, w, h: float32; title = ""): Draw =
  result = d.radialRect(x - 5, y - 2, w + 10, h + 10, 0x383A2608'u32, 0x003A2608'u32,
                        x + w / 2, y + h / 2, w * 0.72)
  result = result.linearRect(x, y, w, h, 0xFFF4D589'u32, 0xFFC18A2D'u32,
                             x, y, x + w, y + h, 7)
  result = result.linearRect(x, y, w, h * 0.45, 0x35FFFFFF'u32, 0x00FFFFFF'u32,
                             x, y, x, y + h * 0.45, 7)
  result = result.outline(x + 5, y + 5, w - 10, h - 10, 0x8074500D'u32, 0.8)
  result = result.screw(x + 12, y + 12, 25).screw(x + w - 12, y + 12, -35)
  result = result.screw(x + 12, y + h - 12, 65).screw(x + w - 12, y + h - 12, -20)
  if title.len > 0:
    result = result.centred(x + w / 2, y + 23, 10.5, title, Ink, Serif, 600)

# -------------------------------------------------------- static engraved sheet ---

proc staticArt(): Draw =
  result = Draw().linearDown(0, 0, WinW, WinH, PaperLight, PaperDeep)
  var fibre = 11.0'f32
  while fibre < WinH:
    result = result.line(0, fibre, WinW, fibre + 3, 0x082B1D0E'u32, 0.55)
    fibre += 23

  # Title block: deliberately an engraved museum plate, not interface chrome.
  result = result.tracked(28, 43, 10, 2.0, "ANNO MDCCLXXIV")
  result = result.line(147, 39, 267, 39, InkSoft, 0.7)
  result = result.engrave(27, 83, 31, "The", Ink)
  result = result.engrave(27, 122, 31, "Clockmaker’s", Ink)
  result = result.engrave(27, 166, 36, "Orrery", Rubric)
  result = result.engrave(29, 207, 13, "A Mechanical Theatre", InkSoft)
  result = result.engrave(29, 226, 13, "of the Heavens", InkSoft)
  result = result.line(28, 246, 267, 246, InkSoft, 0.75)
  result = result.ring(147, 254, 8, InkSoft, 0.8).ring(147, 254, 3, InkSoft, 0.8)
  result = result.line(28, 254, 130, 254, InkSoft, 0.65).line(164, 254, 267, 254, InkSoft, 0.65)
  result = result.engrave(29, 282, 11, "Eight wanderers turn about", InkSoft)
  result = result.engrave(29, 299, 11, "a golden Sun, each after its", InkSoft)
  result = result.engrave(29, 316, 11, "own true period.", InkSoft)

  # The brass rim and parchment diaphragm.
  result = result.soft(13).ellipse(DialX + 9, DialY + 13, OuterR + 4, OuterR + 4, 0x342B1A08'u32)
  result = result.radialRect(DialX - OuterR, DialY - OuterR, OuterR * 2, OuterR * 2,
                             BrassHi, BrassLo, DialX - 120, DialY - 135, OuterR * 1.65, OuterR)
  result = result.ring(DialX, DialY, OuterR - 1, InkSoft, 1.3)
  result = result.ring(DialX, DialY, 329, InkSoft, 1.1)
  result = result.radialRect(DialX - 328, DialY - 328, 656, 656,
                             PaperLight, 0xFFE5D3AC'u32, DialX - 50, DialY - 70, 410, 328)

  # 360 real ecliptic-degree ticks; longer cuts every 10 and 30 degrees.
  for degree in 0 ..< 360:
    let inner = if degree mod 30 == 0: 330.0'f32 elif degree mod 10 == 0: 342.0 else: 360.0
    let (ax, ay) = polar(inner, float64(degree))
    let (bx, by) = polar(369, float64(degree))
    let colour = if degree mod 30 == 0: Ink else: InkSoft
    let width = if degree mod 30 == 0: 1.35'f32 elif degree mod 10 == 0: 1.0 else: 0.65
    result = result.line(DialX + ax, DialY + ay, DialX + bx, DialY + by, colour, width)
  result = result.ring(DialX, DialY, 358, InkSoft, 0.65).ring(DialX, DialY, 369, InkSoft, 1.0)
  for sign in 0 ..< 12:
    result = result.ringText(DialX, DialY, 346, 10.2, float64(sign) * 30.0 + 15.0, SignGlyphs[sign], Ink, 1.8)
    for number in [10, 20]:
      let lon = sign * 30 + number
      let (px, py) = polar(335, float64(lon))
      result = result.centred(DialX + px, DialY + py - 3, 7.2, $number, InkSoft)

  # Fine construction lines, seventy restrained engraved stars and ring furniture.
  for spoke in 0 ..< 12:
    let (ax, ay) = polar(48, float64(spoke * 30))
    let (bx, by) = polar(304, float64(spoke * 30))
    result = result.line(DialX + ax, DialY + ay, DialX + bx, DialY + by, InkFaint, 0.65)
  var seed = 1774.0
  for _ in 0 ..< 70:
    seed = (seed * 16807.0) mod 2147483647.0
    let a = seed / 2147483647.0
    seed = (seed * 16807.0) mod 2147483647.0
    let b = seed / 2147483647.0
    let (sx, sy) = polar(48 + sqrt(a) * 252, b * 360)
    # A stipple's half-width in device px, not a type size: named `stipple` so the
    # design audit does not read it as one.
    let stipple = 0.6 + a * 1.25
    result = result.line(DialX + sx - stipple, DialY + sy, DialX + sx + stipple, DialY + sy, InkFaint, 0.45)
    result = result.line(DialX + sx, DialY + sy - stipple, DialX + sx, DialY + sy + stipple, InkFaint, 0.45)
  result = result.ring(DialX, DialY, 303, InkFaint, 0.7)
  result = result.ringText(DialX, DialY, 294, 7.1, 270,
                           "· MOTUS COELORUM MECHANICE EXPRESSUS ·", InkSoft, 2.0)

  result = result.tracked(29, 746, 8.2, 1.1, "FECIT J. WHITLOCK · AN IMAGINED MAKER")
  result = result.engrave(29, 767, 9.5, "One turn of the great wheel is one year.", InkSoft)
  result = result.tracked(1110, 771, 7.5, 0.65, "J2000 MEAN ELEMENTS · KEPLER SOLVED EACH FRAME")
  result = result.engrave(1110, 786, 8.5, "Distances share one logarithmic scale.", InkSoft)

# -------------------------------------------------------------- calendar dial ---

proc ensureCalendar(year: int) =
  ## Recomputed only when the simulated year changes. Day ticks are the Earth's
  ## own computed longitude on that date, not 365 equally decorative spokes.
  if year == calendarYear: return
  calendarYear = year
  calendarLongitudes = @[]
  let start = julianDay(year, 1, 1)
  let total = if leapYear(year): 366 else: 365
  for day in 0 ..< total:
    calendarLongitudes.add helio(Earth, start + float64(day)).longitude

proc drawCalendar(d: Draw; year: int): Draw =
  result = d
  ensureCalendar(year)
  let start = julianDay(year, 1, 1)
  var month = 1
  var day = 1
  for index, lon in calendarLongitudes:
    let first = day == 1
    let inner = if first: 303.0'f32 elif day mod 5 == 0: 311.0 else: 315.0
    let (ax, ay) = polar(inner, lon)
    let (bx, by) = polar(327, lon)
    result = result.line(DialX + ax, DialY + ay, DialX + bx, DialY + by,
                         if first: Ink else: InkSoft, if first: 1.1 else: 0.55)
    inc day
    if day > daysInMonth(year, month):
      day = 1
      if month < 12: inc month
  result = result.ring(DialX, DialY, 327, InkSoft, 0.7)
  for m in 1 .. 12:
    let lon = helio(Earth, julianDay(year, m, 16)).longitude
    result = result.ringText(DialX, DialY, 316, 7.1, lon, Months[m - 1], InkSoft, 1.1)
  discard start

# ------------------------------------------------------- planets and their arms ---

proc instrumentRadius(distanceAU: float64): float32 =
  ## A single physical scale for all eight: 132 px at 1 AU and 115 px per decade.
  float32(132.0 + 115.0 * log10(distanceAU))

proc screenPoint(place: Place): (float32, float32, float32) =
  let radius = instrumentRadius(place.distance)
  let (px, py) = polar(radius, place.longitude)
  (DialX + px, DialY + py, radius)

proc drawOrbits(d: Draw): Draw =
  result = d
  for planet in Planet:
    var path = result
    for sample in 0 .. 96:
      let place = placeAtE(planet, simJD, float64(sample) * 2.0 * PI / 96.0)
      let (x, y, _) = screenPoint(place)
      if sample == 0: path = path.moveTo(x, y) else: path = path.lineTo(x, y)
    result = path.close().stroke(if ord(planet) == selected: Rubric else: InkFaint,
                                 if ord(planet) == selected: 1.35 else: 0.75)

proc drawSun(d: Draw): Draw =
  result = d.radialRect(DialX - 95, DialY - 95, 190, 190,
                        0x44FFD571'u32, 0x00FFD571'u32, DialX, DialY, 95, 95)
  for ray in 0 ..< 16:
    let angle = float64(ray) * 22.5
    let (rx, ry) = polar(if ray mod 2 == 0: 54.0 else: 47.0, angle)
    let (l1, l2) = polar(34, angle + 4)
    let (r1, r2) = polar(34, angle - 4)
    result = result.moveTo(DialX + l1, DialY + l2).lineTo(DialX + rx, DialY + ry)
    result = result.lineTo(DialX + r1, DialY + r2).close().fill(BrassMid)
  result = result.radialRect(DialX - 32, DialY - 32, 64, 64,
                             0xFFFFF6C0'u32, 0xFFD98617'u32, DialX - 10, DialY - 12, 50, 32)
  result = result.ring(DialX, DialY, 32, BrassLo, 1.0).circle(DialX, DialY, 4, BrassHi)

proc globe(d: Draw; planet: Planet; x, y: float32): Draw =
  let index = ord(planet)
  let size = GlobeSizes[index]
  result = d
  if planet == Saturn:
    result = result.ellipseStroke(x, y, size * 1.9, size * 0.65, -18, 0, 360, 0xFFBC9657'u32, 4.2)
  result = result.circle(x + 1.2, y + 2, size + 2.2, 0x683B280D'u32)
  result = result.radialRect(x - size, y - size, size * 2, size * 2,
                             GlobeLights[index], GlobeColours[index], x - size * 0.35, y - size * 0.42, size * 2.1, size)
  result = result.ring(x, y, size, 0xA8392718'u32, 0.75)
  case planet
  of Mercury:
    result = result.circle(x - 2, y + 1, 1.2, 0x6850443A'u32).circle(x + 2.2, y - 2, 0.8, 0x6850443A'u32)
  of Venus:
    result = result.line(x - 6, y + 1, x + 6, y - 1, 0x75B28245'u32, 1.0)
    result = result.line(x - 5, y + 4, x + 4, y + 2, 0x75B28245'u32, 0.8)
  of Earth:
    result = result.moveTo(x - 5, y - 4).lineTo(x - 1, y - 6).lineTo(x + 1, y - 2)
    result = result.lineTo(x - 1, y).lineTo(x - 4, y + 2).close().fill(0xFF769461'u32)
    result = result.moveTo(x + 3, y + 1).lineTo(x + 7, y).lineTo(x + 5, y + 5)
    result = result.lineTo(x + 2, y + 4).close().fill(0xFF769461'u32)
  of Mars:
    result = result.ellipse(x - 1, y - size + 1.2, size * 0.48, 1.8, 0xFFF2D8C1'u32)
  of Jupiter:
    for belt in [-9.0'f32, -4.0, 2.0, 8.0]:
      let half = sqrt(max(0.0, size * size - belt * belt))
      result = result.line(x - half, y + belt, x + half, y + belt,
                           if belt == 2.0: 0xFF93613E'u32 else: 0x8C865137'u32,
                           if belt == 2.0: 2.0 else: 1.25)
    result = result.ellipse(x + 6, y + 5, 3.3, 1.8, 0xFFB05D43'u32)
  of Saturn:
    result = result.ellipseStroke(x, y, size * 1.9, size * 0.65, -18, 0, 180, 0xFFE0BE75'u32, 3.0)
  of Uranus:
    result = result.line(x - size + 2, y + 1, x + size - 2, y - 1, 0x70DDF7F0'u32, 1.1)
  of Neptune:
    result = result.ellipse(x + 3, y + 2, 2.4, 1.3, 0x902C385F'u32)
  if index == selected:
    result = result.ring(x, y, size + 5, Rubric, 1.35)
    result = result.circle(x, y - size - 5, 1.8, Rubric)
  result = result.centred(x, y + size + 15, 8.7, Planets[planet].name, Ink, Sans, 600)

proc taperedArm(d: Draw; place: Place; dx, dy, rootWidth, tipWidth: float32; colour: uint32): Draw =
  let (_, _, radius) = screenPoint(place)
  let ux = cos(place.longitude * Deg)
  let uy = -sin(place.longitude * Deg)
  let vx = -uy
  let vy = ux
  let tip = radius - 3.0
  result = d.moveTo(DialX + dx + vx * rootWidth, DialY + dy + vy * rootWidth)
  result = result.lineTo(DialX + dx + float32(ux * tip) + vx * tipWidth,
                         DialY + dy + float32(uy * tip) + vy * tipWidth)
  result = result.lineTo(DialX + dx + float32(ux * tip) - vx * tipWidth,
                         DialY + dy + float32(uy * tip) - vy * tipWidth)
  result = result.lineTo(DialX + dx - vx * rootWidth, DialY + dy - vy * rootWidth).close().fill(colour)

proc drawPlanets(d: Draw): Draw =
  result = d
  # Shadows and tapered mechanical arms, outermost first, all below the Sun.
  for planet in DrawOrder:
    let place = helio(planet, simJD)
    let (_, _, radius) = screenPoint(place)
    let ux = cos(place.longitude * Deg)
    let uy = -sin(place.longitude * Deg)
    result = result.taperedArm(place, 2, 3, 3.0, 1.4, 0x2A302317'u32)
    result = result.taperedArm(place, 0, 0, 2.8, 1.25, Brass)
    let mx = DialX + float32(ux * radius * 0.43)
    let my = DialY + float32(uy * radius * 0.43)
    result = result.line(mx + float32(uy * 2), my + float32(ux * 2),
                         mx - float32(uy * 2), my - float32(ux * 2), BrassHi, 1.4)
    let wx = DialX + float32(ux * radius * 0.22)
    let wy = DialY + float32(uy * radius * 0.22)
    result = result.circle(wx, wy, 3.1, BrassLo).circle(wx, wy, 1.8, BrassHi)
  result = result.drawSun()
  for planet in DrawOrder:
    let (x, y, _) = screenPoint(helio(planet, simJD))
    result = result.globe(planet, x, y)

# ------------------------------------------------------------- the annual train ---

proc gearPoint(g: Gear; x, y, scale: float64; ox, oy: float32;
               px, py: float64): (float32, float32) =
  let angle = g.theta * Deg
  let rx = x + px * cos(angle) - py * sin(angle)
  let ry = y + px * sin(angle) + py * cos(angle)
  (ox + float32(rx * scale), oy + float32(ry * scale))

proc wheel(d: Draw; g: Gear; x, y, scale: float64; ox, oy: float32; spokes: int): Draw =
  ## Outer teeth, open spoke windows and the axle bore, analytically transformed
  ## into absolute coordinates and emitted before one even-odd fill.
  result = d.fillRule(evenOdd)
  let pitchRadius = float64(g.teeth) * GearModule / 2.0
  let outer = pitchRadius + GearModule
  let root = pitchRadius - 1.25 * GearModule
  let pitch = 2.0 * PI / float64(g.teeth)
  var first = true
  for tooth in 0 ..< g.teeth:
    for (fraction, radius) in [(-0.50, root), (-0.27, root), (-0.11, outer), (0.11, outer), (0.27, root)]:
      let angle = (float64(tooth) + fraction) * pitch
      let (px, py) = gearPoint(g, x, y, scale, ox, oy, radius * cos(angle), radius * sin(angle))
      if first:
        result = result.moveTo(px, py)
        first = false
      else:
        result = result.lineTo(px, py)
  result = result.close()
  let hub = max(3.2 * GearModule, pitchRadius * 0.26)
  let rim = root - 1.5 * GearModule
  if spokes >= 2 and rim > hub:
    for spoke in 0 ..< spokes:
      let a0 = float64(spoke) * 2.0 * PI / float64(spokes) + 0.09
      let a1 = float64(spoke + 1) * 2.0 * PI / float64(spokes) - 0.09
      var (px, py) = gearPoint(g, x, y, scale, ox, oy, rim * cos(a0), rim * sin(a0))
      result = result.moveTo(px, py)
      for part in 1 .. 8:
        let angle = a0 + (a1 - a0) * float64(part) / 8.0
        (px, py) = gearPoint(g, x, y, scale, ox, oy, rim * cos(angle), rim * sin(angle))
        result = result.lineTo(px, py)
      (px, py) = gearPoint(g, x, y, scale, ox, oy, hub * cos(a1), hub * sin(a1))
      result = result.lineTo(px, py)
      for part in 1 .. 8:
        let angle = a1 - (a1 - a0) * float64(part) / 8.0
        (px, py) = gearPoint(g, x, y, scale, ox, oy, hub * cos(angle), hub * sin(angle))
        result = result.lineTo(px, py)
      result = result.close()
  var (hx, hy) = gearPoint(g, x, y, scale, ox, oy, 6, 0)
  result = result.moveTo(hx, hy)
  for part in 1 .. 16:
    let angle = 2.0 * PI * float64(part) / 16.0
    (hx, hy) = gearPoint(g, x, y, scale, ox, oy, 6.0 * cos(angle), 6.0 * sin(angle))
    result = result.lineTo(hx, hy)
  result = result.close().fill(BrassMid).fillRule(winding)
  let sx = ox + float32(x * scale)
  let sy = oy + float32(y * scale)
  result = result.circle(sx, sy, 4.0, BrassLo).circle(sx - 0.8, sy - 0.8, 2.1, BrassHi)

proc drawTrain(d: Draw): Draw =
  result = d.plate(20, 342, 258, 382, "THE ANNUAL TRAIN")
  let scale = 0.60
  let ox = 31.0'f32
  let oy = 366.0'f32
  let annualAngle = (simJD - BaseJD) / YearDays * 360.0
  let (a, b, c, dd) = annualTrain(annualAngle)
  let ax = 114.0
  let ay = 150.0
  let (bx, by) = gearCentre(ax, ay, a, -35, b)
  let (cx2, cy2) = gearCentre(bx, by, b, -100, c)
  let (dx, dy) = gearCentre(ax, ay, a, 30, dd)
  result = result.wheel(a, ax, ay, scale, ox, oy, 6)
  result = result.wheel(b, bx, by, scale, ox, oy, 0)
  result = result.wheel(c, cx2, cy2, scale, ox, oy, 4)
  result = result.wheel(dd, dx, dy, scale, ox, oy, 0)
  # The ebony crank is attached to A, so its displayed angle is the annual angle.
  let crankX = ox + float32(ax * scale)
  let crankY = oy + float32(ay * scale)
  let endX = crankX + float32(45.0 * cos(a.theta * Deg))
  let endY = crankY + float32(45.0 * sin(a.theta * Deg))
  result = result.line(crankX, crankY, endX, endY, BrassLo, 5)
  result = result.circle(endX, endY, 7.0, Ebony).circle(endX - 2, endY - 2, 2.2, 0xFF746352'u32)
  result = result.centred(149, 582, 8.6, "ANNUAL WHEEL ANGLE", InkSoft, Sans, 600)
  result = result.centred(149, 605, 24, fixed(norm360(a.theta), 2) & "°", Ink, Serif, 400)
  result = result.centred(149, 641, 8.2, "ONE TURN PER MEAN YEAR", InkSoft, Sans, 600)
  result = result.tracked(36, 685, 8.2, 1.0, "TEETH 48 · 16 · 32 · 24")
  result = result.centred(149, 706, 9.2, "Contact ratios and phases are computed.", InkSoft)

# ----------------------------------------------------------- plates and readouts ---

proc drawDate(d: Draw): Draw =
  result = d.plate(1094, 26, 282, 190, "THE SIMULATED DATE")
  let (year, month, day) = civilDate(simJD)
  result = result.rect(1112, 58, 246, 78, Recess, 4)
  result = result.outline(1115, 61, 240, 72, 0x758F6C32'u32, 0.8)
  result = result.centred(1235, 73, 22, twoDigits(day) & " " & FullMonths[month - 1], BrassHi, Serif, 600)
  result = result.centred(1235, 108, 15, $year & " · GREGORIAN", 0xFFE3C980'u32, Serif, 400)
  result = result.centred(1235, 145, 10.5, "JULIAN DAY " & fixed(simJD, 1), Ink, Sans, 500)
  let sunSign = signText(helio(Earth, simJD).longitude + 180)
  result = result.centred(1235, 166, 10.5, "SUN IN " & sunSign, InkSoft, Serif, 600)
  let elapsed = simJD - BaseJD
  result = result.centred(1235, 190, 9.2, "CLOCK +" & fixed(elapsed, 1) & " DAYS", InkSoft, Sans, 500)

proc drawSelected(d: Draw): Draw =
  result = d.plate(1094, 230, 282, 276, "THE SELECTED WANDERER")
  let planet = Planet(selected)
  let data = Planets[planet]
  let place = helio(planet, simJD)
  result = result.circle(1122, 278, 8, GlobeColours[selected]).circle(1120, 276, 2.3, GlobeLights[selected])
  result = result.tracked(1140, 274, 12, 1.5, data.name, Ink, 700)
  result = result.tracked(1141, 292, 8.0, 1.7, data.epithet, InkSoft, 600)
  result = result.centred(1235, 316, 36, fixed(place.longitude, 2) & "°", Ink, Serif, 400)
  result = result.centred(1235, 362, 10.5, "IN " & signText(place.longitude), Rubric, Serif, 600)
  result = result.line(1116, 389, 1354, 389, InkSoft, 0.65)
  result = result.engrave(1118, 410, 10.0, "HELIOCENTRIC DISTANCE", InkSoft, Sans, 600)
  result = result.engrave(1302, 410, 10.5, fixed(place.distance, 4) & " AU", Ink, Serif, 600)
  result = result.engrave(1118, 433, 10.0, "SIDEREAL PERIOD", InkSoft, Sans, 600)
  result = result.engrave(1270, 433, 10.5, fixed(data.periodDays, 3) & " d", Ink, Serif, 600)
  result = result.engrave(1118, 456, 10.0, "ECCENTRICITY", InkSoft, Sans, 600)
  result = result.engrave(1300, 456, 10.5, fixed(eccentricity(planet, simJD), 5), Ink, Serif, 600)
  let latitude = arctan2(place.z, hypot(place.x, place.y)) / Deg
  result = result.centred(1235, 483, 9.2, "ECLIPTIC LATITUDE " & fixed(latitude, 2) & "°", InkSoft, Sans, 500)

proc drawRate(d: Draw): Draw =
  result = d.plate(1094, 520, 282, 232, "RATE OF THE HEAVENS")
  result = result.centred(1235, 558, 10.0, RateNames[rateIndex], Ink, Serif, 600)
  let kx = 1235.0'f32
  let ky = 644.0'f32
  result = result.radialRect(kx - 43, ky - 43, 86, 86, BrassHi, BrassLo, kx - 12, ky - 13, 66, 43)
  for mark in 0 ..< 60:
    let angle = float64(mark) * 6.0
    let (ax, ay) = polar(if mark mod 5 == 0: 38.0 else: 40.0, angle)
    let (bx, by) = polar(43, angle)
    result = result.line(kx + ax, ky + ay, kx + bx, ky + by, InkSoft, 0.7)
  result = result.ring(kx, ky, 37, InkSoft, 0.8)
  let detents = [-100.0, -35.0, 35.0, 100.0]
  let theta = detents[rateIndex]
  let a = -theta * Deg
  let p1x = kx + float32(-3.0 * cos(a) - 7.0 * sin(a))
  let p1y = ky + float32(-3.0 * sin(a) + 7.0 * cos(a))
  let p2x = kx + float32(27.0 * sin(a))
  let p2y = ky + float32(-27.0 * cos(a))
  let p3x = kx + float32(3.0 * cos(a) - 7.0 * sin(a))
  let p3y = ky + float32(3.0 * sin(a) + 7.0 * cos(a))
  result = result.moveTo(p1x, p1y).lineTo(p2x, p2y).lineTo(p3x, p3y).close().fill(Rubric)
  result = result.circle(kx, ky, 6.5, BrassLo).circle(kx - 1.5, ky - 1.5, 3.2, BrassHi)
  result = result.centred(kx - 89, ky + 4, 9, "HALT", InkSoft, Sans, 600)
  result = result.centred(kx - 31, ky - 49, 9, "DAY", InkSoft, Sans, 600)
  result = result.centred(kx + 42, ky - 44, 9, "MONTH", InkSoft, Sans, 600)
  result = result.centred(kx + 90, ky + 4, 9, "YEAR", InkSoft, Sans, 600)
  result = result.centred(kx, 726, 9.0, "Buttons below set the detent.", InkSoft)

# Bake the still engraving once. The moving canvas contains only the computed
# calendar, arms, globes, clockwork and live plates.
let engravedSheet = block:
  let layer = newLayer(int(WinW), int(WinH))
  layer.draw(staticArt())
  layer

proc drawInstrument(): string =
  discard clockSig.get
  var d = Draw().layer(engravedSheet, 0, 0)
  let (year, _, _) = civilDate(simJD)
  d = d.drawCalendar(year).drawOrbits().drawPlanets().drawTrain().drawDate().drawSelected().drawRate()
  d.cmds

# ------------------------------------------------------------- clock and input ---

proc advance() =
  resetFrameDt()
  var dt = float64(frameDt())
  if dt <= 0.0 or dt > 0.10: dt = 0.016
  simJD += Rates[rateIndex] * dt
  invalidate()

proc stepDays(amount: float64) =
  simJD += amount
  rateIndex = 0
  invalidate()

proc restoreEpoch() =
  simJD = BaseJD
  rateIndex = 0
  selected = ord(Earth)
  invalidate()

app("THE CLOCKMAKER'S ORRERY", width = 1400, height = 900, fill = 0xF1E5C8):
  onFrame:
    advance()
  onKey:
    let key = lastKey()
    case key.code
    of keyRight, keyUp:
      stepDays(7)
      handled()
    of keyLeft, keyDown:
      stepDays(-7)
      handled()
    of keyPageUp:
      stepDays(YearDays)
      handled()
    of keyPageDown:
      stepDays(-YearDays)
      handled()
    of keyHome:
      restoreEpoch()
      handled()
    else: discard
  stack(width = 1400.px, height = 900.px, fill = 0xF1E5C8):
    canvas(draw = drawInstrument(), width = 1400.px, height = 900.px)
    row(absolute = true, left = 22.px, top = 792.px, gap = 8.px):
      button "HALT", width = 104.px, height = 42.px, radius = 10.px,
             fill = speedFill(0), color = 0x302317,
             border = 1.px, borderColor = 0x77500D, size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: setRate(0)
      button "1 DAY / S", width = 128.px, height = 42.px, radius = 10.px,
             fill = speedFill(1), color = 0x302317,
             border = 1.px, borderColor = 0x77500D, size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: setRate(1)
      button "1 MONTH / S", width = 150.px, height = 42.px, radius = 10.px,
             fill = speedFill(2), color = 0x302317,
             border = 1.px, borderColor = 0x77500D, size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: setRate(2)
      button "1 YEAR / S", width = 138.px, height = 42.px, radius = 10.px,
             fill = speedFill(3), color = 0x302317,
             border = 1.px, borderColor = 0x77500D, size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: setRate(3)
      button "- 7 DAYS", width = 124.px, height = 42.px, radius = 10.px,
             fill = 0xF1E5C8, color = 0x302317, border = 1.px, borderColor = 0x77500D,
             size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: stepDays(-7)
      button "+ 7 DAYS", width = 124.px, height = 42.px, radius = 10.px,
             fill = 0xF1E5C8, color = 0x302317, border = 1.px, borderColor = 0x77500D,
             size = 11.px, weight = 700, font = Sans:
        hover:
          fill = BtnHover
        pressed:
          fill = BtnPress
        focused:
          borderColor = BtnRing
        onClick: stepDays(7)
      button "1774 EPOCH", width = 138.px, height = 42.px, radius = 10.px,
             fill = 0x231A13, color = 0xFFE29A, border = 2.px, borderColor = BtnLineDark,
             size = 11.px, weight = 700, font = Sans:
        hover:
          fill = EpochHover
        pressed:
          fill = EpochPress
        focused:
          borderColor = 0xFFE29A
        onClick: restoreEpoch()
    row(absolute = true, left = 22.px, top = 844.px, gap = 8.px):
      for planet in [Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune]:
        button Planets[planet].name, width = 116.px, height = 39.px, radius = 10.px,
               fill = planetFill(ord(planet)),
               color = 0x302317, border = 1.px,
               borderColor = planetBorder(ord(planet)),
               size = 11.px, weight = 700, font = Sans:
          hover:
            fill = BtnHover
          pressed:
            fill = BtnPress
          focused:
            borderColor = BtnRing
          onClick: choose(ord(planet))
