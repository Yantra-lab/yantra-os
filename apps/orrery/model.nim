## Astronomy and clockwork for the orrery. No screen-space shortcuts live here:
## dates are Julian days, positions come from secular J2000 orbital elements and
## Newton's solution of Kepler's equation, and every driven gear inherits its
## driver's tooth ratio and meshing phase.

import std/math

const
  J2000* = 2451545.0
  YearDays* = 365.2425
  Deg* = PI / 180.0
  GearModule* = 3.2

type
  Planet* = enum
    Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune

  Elements* = object
    name*, epithet*: string
    a0*, aRate*, e0*, eRate*, i0*, iRate*: float64
    l0*, lRate*, peri0*, periRate*, node0*, nodeRate*: float64
    periodDays*: float64
    radiusKm*: int

  Place* = object
    longitude*, distance*, x*, y*, z*: float64

  Gear* = object
    teeth*: int
    theta*, phi*: float64

# NASA/JPL approximate Keplerian elements and their rates per Julian century.
# Orbital-period quotations are sidereal days, independently listed for display
# and checked against the mean-longitude rates in tests/t_model.nim.
const Planets*: array[Planet, Elements] = [
  Elements(name: "MERCURY", epithet: "THE SWIFT", a0: 0.38709927, aRate: 0.00000037,
    e0: 0.20563593, eRate: 0.00001906, i0: 7.00497902, iRate: -0.00594749,
    l0: 252.25032350, lRate: 149472.67411175, peri0: 77.45779628, periRate: 0.16047689,
    node0: 48.33076593, nodeRate: -0.12534081, periodDays: 87.969, radiusKm: 2439),
  Elements(name: "VENUS", epithet: "THE VEILED", a0: 0.72333566, aRate: 0.00000390,
    e0: 0.00677672, eRate: -0.00004107, i0: 3.39467605, iRate: -0.00078890,
    l0: 181.97909950, lRate: 58517.81538729, peri0: 131.60246718, periRate: 0.00268329,
    node0: 76.67984255, nodeRate: -0.27769418, periodDays: 224.701, radiusKm: 6051),
  Elements(name: "EARTH", epithet: "THE HEARTH", a0: 1.00000261, aRate: 0.00000562,
    e0: 0.01671123, eRate: -0.00004392, i0: -0.00001531, iRate: -0.01294668,
    l0: 100.46457166, lRate: 35999.37244981, peri0: 102.93768193, periRate: 0.32327364,
    node0: 0.0, nodeRate: 0.0, periodDays: 365.256, radiusKm: 6371),
  Elements(name: "MARS", epithet: "THE RUDDY", a0: 1.52371034, aRate: 0.00001847,
    e0: 0.09339410, eRate: 0.00007882, i0: 1.84969142, iRate: -0.00813131,
    l0: -4.55343205, lRate: 19140.30268499, peri0: -23.94362959, periRate: 0.44441088,
    node0: 49.55953891, nodeRate: -0.29257343, periodDays: 686.980, radiusKm: 3389),
  Elements(name: "JUPITER", epithet: "THE GIANT", a0: 5.20288700, aRate: -0.00011607,
    e0: 0.04838624, eRate: -0.00013253, i0: 1.30439695, iRate: -0.00183714,
    l0: 34.39644051, lRate: 3034.74612775, peri0: 14.72847983, periRate: 0.21252668,
    node0: 100.47390909, nodeRate: 0.20469106, periodDays: 4332.817, radiusKm: 69911),
  Elements(name: "SATURN", epithet: "THE RINGED", a0: 9.53667594, aRate: -0.00125060,
    e0: 0.05386179, eRate: -0.00050991, i0: 2.48599187, iRate: 0.00193609,
    l0: 49.95424423, lRate: 1222.49362201, peri0: 92.59887831, periRate: -0.41897216,
    node0: 113.66242448, nodeRate: -0.28867794, periodDays: 10755.884, radiusKm: 58232),
  Elements(name: "URANUS", epithet: "THE DISTANT", a0: 19.18916464, aRate: -0.00196176,
    e0: 0.04725744, eRate: -0.00004397, i0: 0.77263783, iRate: -0.00242939,
    l0: 313.23810451, lRate: 428.48202785, peri0: 170.95427630, periRate: 0.40805281,
    node0: 74.01692503, nodeRate: 0.04240589, periodDays: 30687.401, radiusKm: 25362),
  Elements(name: "NEPTUNE", epithet: "THE HIDDEN", a0: 30.06992276, aRate: 0.00026291,
    e0: 0.00859048, eRate: 0.00005105, i0: 1.77004347, iRate: 0.00035372,
    l0: -55.12002969, lRate: 218.45945325, peri0: 44.96476227, periRate: -0.32241464,
    node0: 131.78422574, nodeRate: -0.00508664, periodDays: 60189.659, radiusKm: 24622)
]

const
  Signs* = ["ARIES", "TAURUS", "GEMINI", "CANCER", "LEO", "VIRGO",
            "LIBRA", "SCORPIO", "SAGITTARIUS", "CAPRICORN", "AQUARIUS", "PISCES"]
  SignGlyphs* = ["ARI", "TAU", "GEM", "CAN", "LEO", "VIR", "LIB", "SCO", "SAG", "CAP", "AQR", "PSC"]
  Months* = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
  MonthDays* = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

proc norm360*(x: float64): float64 =
  result = x - floor(x / 360.0) * 360.0
  if result < 0.0: result += 360.0

proc julianDay*(year, month, day: int): float64 =
  ## Proleptic Gregorian calendar at 00:00; valid on both sides of 1582.
  var y = year
  var m = month
  if m <= 2:
    dec y
    m += 12
  let a = floor(float64(y) / 100.0)
  let b = 2.0 - a + floor(a / 4.0)
  floor(365.25 * float64(y + 4716)) + floor(30.6001 * float64(m + 1)) +
    float64(day) + b - 1524.5

proc civilDate*(jd: float64): (int, int, int) =
  ## Inverse of julianDay for integral/noon Julian dates and fractions thereof.
  let z = int(floor(jd + 0.5))
  var a = z
  if z >= 2299161:
    let alpha = int(floor((float64(z) - 1867216.25) / 36524.25))
    a = z + 1 + alpha - alpha div 4
  let b = a + 1524
  let c = int(floor((float64(b) - 122.1) / 365.25))
  let d = int(floor(365.25 * float64(c)))
  let e = int(floor(float64(b - d) / 30.6001))
  let day = b - d - int(floor(30.6001 * float64(e)))
  let month = if e < 14: e - 1 else: e - 13
  let year = if month > 2: c - 4716 else: c - 4715
  (year, month, day)

proc leapYear*(year: int): bool =
  year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0)

proc daysInMonth*(year, month: int): int =
  if month == 2 and leapYear(year): 29 else: MonthDays[month - 1]

proc dayOfYear*(year, month, day: int): int =
  result = day
  for m in 1 ..< month: result += daysInMonth(year, m)

proc solveKepler*(meanRad, eccentricity: float64): float64 =
  ## Newton iteration on E - e sin E = M. M is wrapped to [-pi, pi], which also
  ## prevents precision loss after long runs on the year-per-second setting.
  let m = (meanRad + PI) - floor((meanRad + PI) / (2.0 * PI)) * (2.0 * PI) - PI
  result = m + eccentricity * sin(m)
  for _ in 0 ..< 12:
    let step = (result - eccentricity * sin(result) - m) / (1.0 - eccentricity * cos(result))
    result -= step
    if abs(step) < 1.0e-13: break

proc placeAtE*(planet: Planet; jd, eccentricAnomaly: float64): Place =
  ## Ecliptic XYZ and heliocentric longitude/distance for one eccentric anomaly.
  ## a, e, i, longitude of perihelion and node all use their secular values.
  let t = (jd - J2000) / 36525.0
  let p = Planets[planet]
  let a = p.a0 + p.aRate * t
  let e = p.e0 + p.eRate * t
  let inc = (p.i0 + p.iRate * t) * Deg
  let peri = (p.peri0 + p.periRate * t) * Deg
  let node = (p.node0 + p.nodeRate * t) * Deg
  let xOrb = a * (cos(eccentricAnomaly) - e)
  let yOrb = a * sqrt(1.0 - e * e) * sin(eccentricAnomaly)
  let r = hypot(xOrb, yOrb)
  let u = peri - node + arctan2(yOrb, xOrb)
  let x = r * (cos(node) * cos(u) - sin(node) * sin(u) * cos(inc))
  let y = r * (sin(node) * cos(u) + cos(node) * sin(u) * cos(inc))
  let z = r * sin(u) * sin(inc)
  Place(longitude: norm360(arctan2(y, x) / Deg), distance: r, x: x, y: y, z: z)

proc helio*(planet: Planet; jd: float64): Place =
  let t = (jd - J2000) / 36525.0
  let p = Planets[planet]
  let meanLongitude = p.l0 + p.lRate * t
  let peri = p.peri0 + p.periRate * t
  let meanAnomaly = (meanLongitude - peri) * Deg
  let e = p.e0 + p.eRate * t
  placeAtE(planet, jd, solveKepler(meanAnomaly, e))

proc semiMajor*(planet: Planet; jd: float64): float64 =
  Planets[planet].a0 + Planets[planet].aRate * (jd - J2000) / 36525.0

proc eccentricity*(planet: Planet; jd: float64): float64 =
  Planets[planet].e0 + Planets[planet].eRate * (jd - J2000) / 36525.0

proc signText*(longitude: float64): string =
  let lon = norm360(longitude)
  let index = min(11, int(lon / 30.0))
  let degree = int(lon - float64(index) * 30.0)
  Signs[index] & " " & $degree & "°"

# -------------------------------------------------------------------- gears ---

proc gear*(teeth: int; theta, phi: float64): Gear =
  Gear(teeth: teeth, theta: theta, phi: phi)

proc pitchRadius*(g: Gear): float64 =
  float64(g.teeth) * GearModule / 2.0

proc toothPitch*(g: Gear): float64 =
  360.0 / float64(g.teeth)

proc meshPhase*(driver, driven: Gear): float64 =
  ## Tooth-for-tooth contact at the line of centres. Adjacent gears reverse;
  ## theta_B = -(N_A/N_B)(theta_A-phi_B)+phi_B+180-halfPitch_B.
  -(float64(driver.teeth) / float64(driven.teeth)) * (driver.theta - driven.phi) +
    driven.phi + 180.0 - toothPitch(driven) / 2.0

proc annualTrain*(annualAngle: float64): (Gear, Gear, Gear, Gear) =
  ## 48 drives 16 and 24; 16 drives 32. The displayed centres are placed one
  ## pitch-radius sum apart, so these are contacting wheels, not decorative icons.
  let a = gear(48, annualAngle, 0.0)
  var b = gear(16, 0.0, -35.0)
  var c = gear(32, 0.0, -100.0)
  var d = gear(24, 0.0, 30.0)
  b.theta = meshPhase(a, b)
  c.theta = meshPhase(b, c)
  d.theta = meshPhase(a, d)
  (a, b, c, d)

proc gearCentre*(x, y: float64; driver: Gear; angle: float64; driven: Gear): (float64, float64) =
  let distance = pitchRadius(driver) + pitchRadius(driven)
  (x + cos(angle * Deg) * distance, y - sin(angle * Deg) * distance)
