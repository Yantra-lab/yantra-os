## Native numerical checks for the orrery's astronomy and contact gear train.
import std/math
import ../model

var passed = 0
var failed = 0

proc check(name: string; condition: bool; detail = "") =
  if condition:
    inc passed
    echo "PASS ", name
  else:
    inc failed
    echo "FAIL ", name, (if detail.len > 0: " — " & detail else: "")

proc near(a, b, tolerance: float64): bool = abs(a - b) <= tolerance

block:
  check("J2000 starts at the preceding midnight", julianDay(2000, 1, 1) == J2000 - 0.5)
  check("1774 epoch Julian date is exact", julianDay(1774, 1, 1) == 2369000.5,
        $julianDay(1774, 1, 1))
  check("modern civil date is exact", julianDay(2026, 11, 5) == 2461349.5,
        $julianDay(2026, 11, 5))
  check("civilDate inverts J2000", civilDate(J2000) == (2000, 1, 1))
  check("civilDate inverts 1774", civilDate(2369000.5) == (1774, 1, 1))
  check("civilDate inverts 2026-11-05", civilDate(2461349.5) == (2026, 11, 5))
  check("Gregorian leap day exists in 1776", daysInMonth(1776, 2) == 29)
  check("1774 is not a leap year", daysInMonth(1774, 2) == 28)
  check("31 December is day 365", dayOfYear(1774, 12, 31) == 365)

block:
  var residual = 0.0
  for p in Planet:
    let e = Planets[p].e0
    for k in 0 .. 72:
      let m = float64(k) * 5.0 * Deg
      let wrapped = (m + PI) - floor((m + PI) / (2.0 * PI)) * (2.0 * PI) - PI
      let solved = solveKepler(m, e)
      residual = max(residual, abs(solved - e * sin(solved) - wrapped))
  check("Kepler residual below 1e-12 rad for every planet", residual < 1.0e-12, $residual)

block:
  var ordered = true
  var periodError = 0.0
  var previousA = 0.0
  for p in Planet:
    let data = Planets[p]
    if data.a0 <= previousA: ordered = false
    previousA = data.a0
    let daysFromElements = 36525.0 * 360.0 / data.lRate
    periodError = max(periodError, abs(daysFromElements - data.periodDays))
    let atPeri = placeAtE(p, J2000, 0.0)
    let atApo = placeAtE(p, J2000, PI)
    check($p & " perihelion distance", near(atPeri.distance, data.a0 * (1.0 - data.e0), 1.0e-10))
    check($p & " aphelion distance", near(atApo.distance, data.a0 * (1.0 + data.e0), 1.0e-10))
  check("planets are ordered by physical semi-major axis", ordered)
  check("quoted periods match secular motion within 0.12 day", periodError < 0.12, $periodError)

block:
  # Independently evaluated from the same published J2000 elements with Python,
  # not from Nim's display formatter. Earth is near 100.22 degrees at the epoch.
  let earth = helio(Earth, J2000)
  check("Earth J2000 heliocentric longitude", near(earth.longitude, 100.380180225, 0.00001), $earth.longitude)
  check("Earth J2000 distance is near one AU", near(earth.distance, 0.983307435, 0.00001), $earth.distance)
  let mercury = helio(Mercury, J2000)
  check("Mercury J2000 heliocentric longitude", near(mercury.longitude, 253.783678483, 0.00001), $mercury.longitude)
  let later = helio(Earth, J2000 + 365.256367131)
  check("Earth sidereal-year longitude includes secular element drift", near(later.longitude, 100.380072251767, 0.00000001),
        $later.longitude)
  check("zodiac degree derives from longitude", signText(43.84) == "TAURUS 13°", signText(43.84))

block:
  let (a, b, c, d) = annualTrain(0.0)
  check("annual driver has 48 teeth", a.teeth == 48)
  check("48 teeth at module 3.2 have 76.8 pitch radius", near(pitchRadius(a), 76.8, 1.0e-12))
  check("B meshes at 28.75 degrees", near(b.theta, 28.75, 1.0e-10), $b.theta)
  check("C meshes at 10 degrees", near(c.theta, 10.0, 1.0e-10), $c.theta)
  check("D meshes at 262.5 degrees", near(d.theta, 262.5, 1.0e-10), $d.theta)
  let (a2, b2, c2, d2) = annualTrain(90.0)
  check("quarter turn drives B backwards three turns", near(b2.theta, -241.25, 1.0e-10), $b2.theta)
  check("B-C tooth ratio is real", near(c2.theta, 145.0, 1.0e-10), $c2.theta)
  check("A-D tooth ratio is real", near(d2.theta, 82.5, 1.0e-10), $d2.theta)
  var meshes = true
  for k in 0 .. 36:
    let (aa, bb, cc, dd) = annualTrain(float64(k) * 10.0)
    if not near(meshPhase(aa, bb), bb.theta, 1.0e-9): meshes = false
    if not near(meshPhase(bb, cc), cc.theta, 1.0e-9): meshes = false
    if not near(meshPhase(aa, dd), dd.theta, 1.0e-9): meshes = false
  check("every driven tooth phase stays meshed", meshes)
  let (bx, by) = gearCentre(118.0, 150.0, a, -35.0, b)
  check("gear centres are one pitch-radius sum apart", near(hypot(bx - 118.0, by - 150.0),
        pitchRadius(a) + pitchRadius(b), 1.0e-10))

echo "t_model: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
