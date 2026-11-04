## Nocturne Rally — a midnight stage drawn entirely as projected geometry.
## Arrow up/down are the pedals, left/right steer; the buttons provide the same
## driving controls to a pointer. Three measured laps, a live stage clock and a
## real countdown/finish/restart state machine sit underneath the presentation.

import std/[colors, math]
import "../_design/design"

let night = 0x070A12
let ink = 0xF4F0E8
let muted = 0x969CAE
let champagne = 0xE8D3A2
let coral = 0xF27662
let coralDark = 0xA53F3C
let roadA = 0x282B34
let roadB = 0x2B2E37
let groundA = 0x101C23
let groundB = 0x132329
let kerbLight = 0xE9E2D3
let controlFill = rgba(0x111827, 0.80)
# The pedals' chrome and lit variants. Ratios on the composited fills are in
# `controlStyle` below; every one is measured, none is eyeballed.
let controlLine = 0x7C8798
let controlHover = rgba(0x1D2736, 0.90)
let controlPress = rgba(0x27313F, 0.94)
let ring = 0xFFD59A
let champagneHover = 0xF0E3BC
let champagnePress = 0xD6BF8B
let coralHover = 0xFF8D79
let coralPress = 0xD8624F

const
  winW = 1280.0
  winH = 816.0
  horizon = 300.0
  focal = 720.0
  camH = 2.45
  segLen = 3.0
  nSeg = 112
  roadHalf = 7.4
  lapLen = 1500.0
  lapsToWin = 3
  timeLimit = 96.0

var
  running = false
  gas = false
  dist = 0.0
  side = 0.0
  speed = 0.0
  drift = 0.0
  drifting = false
  driftToggle = false
  driftCharge = 0.0
  boostTime = 0.0
  boostLevel = 0
  nudge = 0.0
  nudgeDir = 0.0
  brakePulse = 0.0
  countdown = 0.0
  laps = 0
  clock = 0.0
  lapStart = 0.0
  lastLap = 0.0
  bestLap = 0.0
  offRoad = 0.0
  outcome = ""

proc shade(c: int; alpha: int): uint32 =
  (uint32(alpha and 0xFF) shl 24) or (uint32(c) and 0x00FFFFFF'u32)

proc fixed(v: float; digits: int): string =
  var p = 1
  for i in 0 ..< digits: p = p * 10
  let a = abs(v)
  let whole = int(a)
  let frac = int((a - float(whole)) * float(p) + 0.5)
  result = (if v < 0.0: "-" else: "") & $whole
  if digits > 0:
    var s = $frac
    while s.len < digits: s = "0" & s
    result &= "." & s

proc pad2(v: int): string =
  if v < 10: "0" & $v else: $v

proc stageTime(v: float): string =
  let mins = int(v) div 60
  pad2(mins) & ":" & pad2(int(v) mod 60) & "." & pad2(min(99, int((v - float(int(v))) * 100.0 + 0.5)))

proc txt(d: Draw; x, y, size: float; col: uint32; s: string; weight = 400): Draw =
  d.textFace(x, y, size, col, "Arial", s, weight)

proc poly(d: Draw; pts: seq[(float, float)]; col: uint32): Draw =
  result = d
  if pts.len < 3: return
  result = result.moveTo(float32(pts[0][0]), float32(pts[0][1]))
  for i in 1 ..< pts.len: result = result.lineTo(float32(pts[i][0]), float32(pts[i][1]))
  # The browser Canvas2D consumer keeps the current path after F (Skia rewinds it).
  # A zero-area transparent rect gives both consumers the same clean next path.
  result = result.close().fill(col).rect(-100, -100, 0, 0, 0x00000000'u32)

proc curveAt(d: float): float =
  13.0 * sin(d * 0.0035) + 6.5 * sin(d * 0.0083 + 1.1) + 2.4 * sin(d * 0.018 + 0.4)

proc hillAt(d: float): float =
  3.8 * sin(d * 0.0026 + 0.7) + 1.5 * sin(d * 0.0059 + 2.1)

proc project(z, x, y, camC, camY: float): (float, float) =
  let k = focal / max(0.5, z)
  (winW * 0.5 + k * (x - camC), horizon + k * (camH - y + camY))

proc restart() =
  running = false
  gas = true
  dist = 0.0
  side = 0.0
  speed = 0.0
  drift = 0.0
  drifting = false
  driftToggle = false
  driftCharge = 0.0
  boostTime = 0.0
  boostLevel = 0
  nudge = 0.0
  brakePulse = 0.0
  countdown = 3.0
  laps = 0
  clock = 0.0
  lapStart = 0.0
  lastLap = 0.0
  offRoad = 0.0
  outcome = ""

proc step() =
  resetFrameDt()
  var dt = float(frameDt())
  if dt <= 0.0 or dt > 0.2: dt = 0.016
  brakePulse = max(0.0, brakePulse - dt)
  if not running:
    if countdown > 0.0:
      countdown = max(0.0, countdown - dt)
      if countdown == 0.0:
        running = true
        speed = 4.0
    elif outcome.len == 0 and keyHeld(keyUp):
      restart()
    return
  clock += dt
  if nudge > 0.0:
    nudge = max(0.0, nudge - dt)
    drift += nudgeDir * dt * 3.2
  let left = keyHeld(keyLeft)
  let right = keyHeld(keyRight)
  let throttle = gas or keyHeld(keyUp)
  let braking = brakePulse > 0.0 or keyHeld(keyDown)
  boostTime = max(0.0, boostTime - dt)
  if boostTime == 0.0: boostLevel = 0
  let driftInput = driftToggle or keyHeld(keySpace)
  if driftInput and not drifting and speed > 14.0:
    drifting = true
    driftCharge = 0.0
  if drifting:
    if driftInput and speed > 7.0:
      # A drift charges through an actual steering input; Space alone is not a boost key.
      if left or right: driftCharge = min(2.4, driftCharge + dt)
    else:
      if driftCharge >= 0.35:
        boostLevel = if driftCharge >= 2.0: 3 elif driftCharge >= 1.1: 2 else: 1
        boostTime = if boostLevel == 3: 1.45 elif boostLevel == 2: 1.0 else: 0.60
      drifting = false
      driftCharge = 0.0
  var a = -1.6 - 0.34 * speed
  if throttle: a += 24.0
  if boostTime > 0.0: a += 18.0
  if braking: a -= 52.0
  speed = max(0.0, min(if boostTime > 0.0: 66.0 else: 58.0, speed + a * dt))
  let gripping = abs(side) < roadHalf - 1.0
  if left: drift = max(-1.0, drift - dt * 3.4)
  elif right: drift = min(1.0, drift + dt * 3.4)
  else: drift *= 1.0 - min(1.0, dt * 2.6)
  side += drift * speed * 0.30 * (if gripping: 1.0 else: 0.48) * dt
  side = max(-roadHalf - 5.0, min(roadHalf + 5.0, side))
  if gripping:
    offRoad = max(0.0, offRoad - dt * 2.0)
  else:
    offRoad = min(6.0, offRoad + dt)
    speed *= 1.0 - dt * 1.15
  dist += speed * dt
  let lapNow = int(dist / lapLen)
  if lapNow > laps:
    laps = lapNow
    lastLap = clock - lapStart
    lapStart = clock
    if bestLap == 0.0 or lastLap < bestLap: bestLap = lastLap
    if laps >= lapsToWin:
      outcome = "WIN"
      running = false
      gas = false
  if clock > timeLimit and outcome.len == 0:
    outcome = "LATE"
    running = false
    gas = false
  if offRoad > 4.5 and outcome.len == 0:
    outcome = "WRECK"
    running = false
    gas = false

proc ridge(d: Draw; base, amp, phase: float; col: uint32): Draw =
  var p = Draw()
  p = p.moveTo(-30, base + 24)
  var x = -30.0
  while x <= winW + 30:
    let y = base - amp * (0.58 + 0.24 * sin(x * 0.006 + phase) + 0.18 * sin(x * 0.014 + phase * 2.0))
    p = p.lineTo(float32(x), float32(y))
    x += 16.0
  p = p.lineTo(winW + 30, base + 24).close()
  result = d
  result.cmds.add p.fill(col).rect(-100, -100, 0, 0, 0x00000000'u32).cmds

proc backdrop(): Draw =
  var d = Draw()
  d = d.linearDown(0, 0, winW, horizon + 90, shade(0x070A16, 255), shade(0x493B50, 255))
  for k in 0 ..< 56:
    let x = 12.0 + float((k * 223) mod 1250)
    let y = 20.0 + float((k * 71) mod 220)
    let r = if k mod 7 == 0: 1.25 else: 0.62
    d = d.circle(x, y, r, shade(champagne, 70 + (k mod 4) * 30))
  d = d.soft(20).circle(1008, 152, 58, shade(champagne, 28))
  d = d.circle(1008, 152, 34, shade(champagne, 238))
  d = d.circle(996, 143, 7, shade(0xC7B68F, 36))
  d = d.circle(1018, 163, 5, shade(0xC7B68F, 34))
  d = ridge(d, horizon + 42, 112, 0.4, shade(0x1C2031, 255))
  d = ridge(d, horizon + 48, 66, 2.2, shade(0x101822, 255))
  d = d.linearDown(0, horizon - 10, winW, 44, shade(coral, 0), shade(coral, 14))
  d

proc camera(): (float, float) =
  let tremor = sin(clock * 31.0) * min(1.0, speed / 58.0) * 0.018
  (curveAt(dist) + side, hillAt(dist) + tremor)

proc road(): Draw =
  var d = backdrop()
  let (camC, camY) = camera()
  var i = nSeg
  while i >= 1:
    let zf = 1.8 + float(i) * segLen
    let zn = 1.8 + float(i - 1) * segLen
    let df = dist + zf
    let dn = dist + zn
    let cf = curveAt(df)
    let cn = curveAt(dn)
    let hf = hillAt(df)
    let hn = hillAt(dn)
    let (lf, yf) = project(zf, cf - roadHalf, hf, camC, camY)
    let (rf, _) = project(zf, cf + roadHalf, hf, camC, camY)
    let (ln, yn) = project(zn, cn - roadHalf, hn, camC, camY)
    let (rn, _) = project(zn, cn + roadHalf, hn, camC, camY)
    let stripe = (int(dn / 7.5) mod 2) == 0
    d = d.rect(0, yf, winW, max(1.0, yn - yf + 1.0), shade(if stripe: groundA else: groundB, 255))
    # A narrow, darker shoulder separates the luminous kerb from the terrain.
    let (sof, _) = project(zf, cf - roadHalf - 1.45, hf, camC, camY)
    let (son, _) = project(zn, cn - roadHalf - 1.45, hn, camC, camY)
    d = poly(d, @[(sof, yf), (lf, yf), (ln, yn), (son, yn)], shade(0x141923, 255))
    let (srf, _) = project(zf, cf + roadHalf + 1.45, hf, camC, camY)
    let (srn, _) = project(zn, cn + roadHalf + 1.45, hn, camC, camY)
    d = poly(d, @[(rf, yf), (srf, yf), (srn, yn), (rn, yn)], shade(0x141923, 255))
    d = poly(d, @[(lf, yf), (rf, yf), (rn, yn), (ln, yn)], shade(if stripe: roadA else: roadB, 255))
    if zn < 285.0:
      let (kif, _) = project(zf, cf - roadHalf + 0.95, hf, camC, camY)
      let (kin, _) = project(zn, cn - roadHalf + 0.95, hn, camC, camY)
      d = poly(d, @[(lf, yf), (kif, yf), (kin, yn), (ln, yn)], shade(if stripe: coralDark else: kerbLight, 255))
      let (krf, _) = project(zf, cf + roadHalf - 0.95, hf, camC, camY)
      let (krn, _) = project(zn, cn + roadHalf - 0.95, hn, camC, camY)
      d = poly(d, @[(krf, yf), (rf, yf), (rn, yn), (krn, yn)], shade(if stripe: coralDark else: kerbLight, 255))
    if not stripe and zn < 175.0:
      let (dlf, _) = project(zf, cf - 0.09, hf, camC, camY)
      let (drf, _) = project(zf, cf + 0.09, hf, camC, camY)
      let (dln, _) = project(zn, cn - 0.09, hn, camC, camY)
      let (drn, _) = project(zn, cn + 0.09, hn, camC, camY)
      d = poly(d, @[(dlf, yf), (drf, yf), (drn, yn), (dln, yn)], shade(champagne, 118))
    i -= 1
  d

proc pine(d: Draw; x, base, h, w: float; col: uint32): Draw =
  result = d.line(x, base, x, base - h * 0.72, shade(0x090D14, 220), max(1.0, w * 0.08))
  result = poly(result, @[(x, base - h), (x - w * 0.34, base - h * 0.56), (x + w * 0.34, base - h * 0.56)], col)
  result = poly(result, @[(x, base - h * 0.83), (x - w * 0.48, base - h * 0.30), (x + w * 0.48, base - h * 0.30)], col)
  result = poly(result, @[(x, base - h * 0.62), (x - w * 0.58, base), (x + w * 0.58, base)], col)

proc trackside(): Draw =
  var d = Draw()
  let (camC, camY) = camera()
  let first = int(dist / 24.0)
  var j = 13
  while j >= 1:
    let wd = float(first + j) * 24.0
    let z = wd - dist
    if z > 3.0 and z < 315.0:
      let c = curveAt(wd)
      let h = hillAt(wd)
      for sideSign in [-1.0, 1.0]:
        let x = c + sideSign * 11.4
        let (bx, by) = project(z, x, h, camC, camY)
        let (tx, ty) = project(z, x, h + 6.4, camC, camY)
        d = d.line(bx, by, tx, ty, shade(0x69717B, 210), max(0.65, 64.0 / z))
        let arm = -sideSign * focal / z * 1.25
        d = d.line(tx, ty, tx + arm, ty, shade(0x69717B, 220), max(0.65, 58.0 / z))
        d = d.soft(7).circle(tx + arm, ty + 1, max(3.0, 66.0 / z), shade(champagne, 120))
        d = d.circle(tx + arm, ty + 1, max(1.7, 27.0 / z), shade(champagne, 255))
        d = d.soft(10).ellipse(bx, by, focal / z * 2.2, focal / z * 0.52, shade(champagne, 16))
      # Uneven pines break up the regular rhythm of the lighting poles.
      let treeSide = if j mod 2 == 0: -1.0 else: 1.0
      let tx = c + treeSide * (18.0 + 3.0 * sin(wd * 0.17))
      let (bx, by) = project(z, tx, h, camC, camY)
      let th = focal / z * (8.0 + 2.0 * sin(wd * 0.11))
      d = pine(d, bx, by, th, th * 0.68, shade(0x0A151C, 245))
      if j mod 3 == 0 and z > 30.0:
        let signSide = -treeSide
        let sx = c + signSide * 12.8
        let (px, py) = project(z, sx, h + 1.45, camC, camY)
        let sc = focal / z
        let bw = 2.5 * sc
        let bh = 1.05 * sc
        d = d.line(px, py + bh * 0.5, px, by, shade(0x818794, 220), max(0.7, sc * 0.08))
        d = d.rect(px - bw / 2, py - bh / 2, bw, bh, shade(coralDark, 245), max(1.0, sc * 0.09))
        if bw > 15.0:
          d = txt(d, px - bw * 0.18, py + bh * 0.28, bh * 0.78, shade(ink, 255), ">", 700)
      if j mod 2 == 0:
        # Three tyre stacks sit outside the kerb, with alternating rally wraps.
        for stackIdx in 0 ..< 3:
          let tx = c - treeSide * (9.5 + float(stackIdx) * 0.78)
          let (sx, sy) = project(z, tx, h, camC, camY)
          let sc = focal / z
          for layer in 0 ..< 2:
            let yy = sy - float(layer) * sc * 0.43
            d = d.ellipse(sx, yy, sc * 0.43, sc * 0.22, shade(if layer == 0: coralDark else: kerbLight, 255))
            d = d.ellipse(sx, yy - sc * 0.05, sc * 0.23, sc * 0.10, shade(0x171C26, 255))
    j -= 1
  # A small occupied grandstand is world geometry and approaches with the stage.
  let standWorld = float(int((dist + 180.0) / 360.0)) * 360.0 + 180.0
  let standZ = standWorld - dist
  if standZ > 32.0 and standZ < 330.0:
    let sideSign = if int(standWorld / 360.0) mod 2 == 0: -1.0 else: 1.0
    let c = curveAt(standWorld) + sideSign * 25.0
    let h = hillAt(standWorld)
    let (lx, by) = project(standZ, c - 9.0, h, camC, camY)
    let (rx, _) = project(standZ, c + 9.0, h, camC, camY)
    let (_, ty) = project(standZ, c - 9.0, h + 5.8, camC, camY)
    d = poly(d, @[(lx, by), (rx, by), (rx, ty + 9), (lx, ty + 9)], shade(0x202735, 255))
    for rowIdx in 0 ..< 4:
      let yy = by - (by - ty) * (0.22 + float(rowIdx) * 0.18)
      d = d.line(lx + 3, yy, rx - 3, yy - 2, shade(0x596171, 180), 1)
      for seat in 0 ..< 9:
        let xx = lx + 6 + (rx - lx - 12) * float(seat) / 8.0
        d = d.circle(xx, yy - 3, max(0.7, (rx - lx) * 0.018), shade(if (seat + rowIdx) mod 3 == 0: coral else: champagne, 220))
    d = poly(d, @[(lx - 5, ty + 10), (rx + 5, ty + 8), (rx + 1, ty), (lx - 1, ty + 2)], shade(coralDark, 255))
    if rx - lx > 100.0:
      d = txt(d, lx + 12, ty + 8, float(FsMicro), shade(ink, 255), "N O C T U R N E   /   0 3", 700)
  # A suspended stage banner is a fixed world object, not a screen-space decal.
  let archWorld = float(int((dist + 120.0) / 300.0)) * 300.0 + 180.0
  let z = archWorld - dist
  if z > 18.0 and z < 335.0:
    let c = curveAt(archWorld)
    let h = hillAt(archWorld)
    let (lx, by) = project(z, c - 9.4, h, camC, camY)
    let (rx, _) = project(z, c + 9.4, h, camC, camY)
    let (_, ly) = project(z, c - 9.4, h + 7.4, camC, camY)
    let (_, ry) = project(z, c + 9.4, h + 7.4, camC, camY)
    let sw = max(1.0, 95.0 / z)
    d = d.line(lx, by, lx, ly, shade(0x353C49, 255), sw)
    d = d.line(rx, by, rx, ry, shade(0x353C49, 255), sw)
    let bh = focal / z * 1.45
    d = poly(d, @[(lx, ly), (rx, ry), (rx, ry + bh), (lx, ly + bh)], shade(0x0B101B, 248))
    d = d.line(lx, ly + bh, rx, ry + bh, shade(coral, 255), max(1.0, sw * 0.35))
    if rx - lx > 120.0:
      let size = min(24.0, bh * 0.53)
      d = txt(d, (lx + rx) * 0.5 - size * 3.15, (ly + ry) * 0.5 + bh * 0.72, size, shade(champagne, 255), "NOCTURNE", 700)
  d

proc speedMarks(): Draw =
  var d = Draw()
  if speed < 18.0: return d
  let energy = min(1.0, (speed - 18.0) / 38.0)
  for k in 0 ..< 30:
    let sideSign = if k mod 2 == 0: -1.0 else: 1.0
    let lane = float((k * 7) mod 15) / 15.0
    let travel = `mod`(dist * 0.013 + float(k) * 0.137, 1.0)
    let x = winW * 0.5 + sideSign * (270.0 + lane * 400.0)
    let y = horizon + 80.0 + travel * 430.0
    let len = (18.0 + 55.0 * energy) * (0.4 + travel)
    d = d.line(x, y, x + sideSign * len * 0.42, y + len, shade(ink, int(18.0 + energy * 58.0)), 0.8 + energy)
  d

proc kartBody(cx, cy, tilt: float): Draw =
  var d = Draw()
  d = d.ellipse(cx, cy + 66, 148, 24, 0x75000000'u32)
  d = d.save().translate(cx, cy).rotate(-tilt * 4.0).translate(-cx, -cy)
  # Rear tyres: dark sidewalls, visible contact patches and champagne hubs.
  for s in [-1.0, 1.0]:
    let x = cx + s * 108.0
    d = d.rect(x - 22, cy - 4, 44, 75, shade(0x070A10, 255), 10)
    d = d.rect(x - 15, cy + 9, 30, 49, shade(0x202632, 255), 8)
    d = d.line(x - 12, cy + 54, x + 12, cy + 54, shade(0x515663, 150), 2)
    d = d.circle(x, cy + 29, 8, shade(0x80889A, 255))
    d = d.circle(x, cy + 29, 3, shade(champagne, 255))
  # Carbon floor and coral bodywork, faceted rather than a single trapezoid.
  d = poly(d, @[(cx - 92, cy + 49), (cx - 65, cy - 13), (cx + 65, cy - 13), (cx + 92, cy + 49), (cx + 71, cy + 66), (cx - 71, cy + 66)], shade(0x0A0E16, 255))
  d = poly(d, @[(cx - 82, cy + 39), (cx - 58, cy - 18), (cx - 22, cy - 27), (cx - 30, cy + 51), (cx - 63, cy + 58)], shade(coralDark, 255))
  d = poly(d, @[(cx + 82, cy + 39), (cx + 58, cy - 18), (cx + 22, cy - 27), (cx + 30, cy + 51), (cx + 63, cy + 58)], shade(coral, 255))
  d = poly(d, @[(cx - 38, cy - 17), (cx + 38, cy - 17), (cx + 47, cy + 51), (cx - 47, cy + 51)], shade(0x171D28, 255))
  for k in 0 ..< 5:
    d = d.line(cx - 29, cy + float(k * 7), cx + 29, cy + float(k * 7), shade(0x56606E, 180), 2)
  # Rear wing, supports and end plates.
  d = d.rect(cx - 60, cy - 57, 9, 46, shade(0x303746, 255), 2)
  d = d.rect(cx + 51, cy - 57, 9, 46, shade(0x303746, 255), 2)
  d = d.rect(cx - 112, cy - 70, 224, 18, shade(0x111722, 255), 4)
  d = d.rect(cx - 105, cy - 67, 210, 4, shade(champagne, 220), 2)
  d = poly(d, @[(cx - 116, cy - 77), (cx - 103, cy - 70), (cx - 103, cy - 43), (cx - 116, cy - 48)], shade(coral, 255))
  d = poly(d, @[(cx + 116, cy - 77), (cx + 103, cy - 70), (cx + 103, cy - 43), (cx + 116, cy - 48)], shade(coral, 255))
  # Suit, helmet, visor and its cool reflected stripe.
  d = d.ellipse(cx, cy - 34, 39, 34, shade(0x202634, 255))
  d = poly(d, @[(cx - 32, cy - 39), (cx, cy - 58), (cx + 32, cy - 39), (cx + 24, cy - 11), (cx - 24, cy - 11)], shade(coralDark, 255))
  d = d.circle(cx, cy - 61, 31, shade(champagne, 255))
  d = d.ellipse(cx, cy - 61, 25, 13, shade(0x111B29, 255))
  d = d.line(cx - 18, cy - 66, cx + 14, cy - 69, shade(0x92B5C5, 190), 3)
  d = d.rect(cx - 4, cy - 91, 8, 15, shade(coral, 255), 2)
  # Number panel, tail lamps and a real exhaust silhouette.
  d = d.rect(cx - 25, cy + 24, 50, 29, shade(champagne, 255), 3)
  d = txt(d, cx - 16, cy + 47, float(FsTitleLg), shade(0x101522, 255), "03", 700)
  for s in [-1.0, 1.0]:
    d = d.soft(7).circle(cx + s * 62.0, cy + 34, 10, shade(coral, 92))
    d = d.circle(cx + s * 62.0, cy + 34, 5, shade(0xFF9A78, 255))
  d = d.rect(cx + 77, cy + 39, 30, 12, shade(0x7D8290, 255), 5)
  d = d.rect(cx + 94, cy + 41, 16, 8, shade(0x171B23, 255), 4)
  d.restore()

proc rallyFx(cx, cy: float): Draw =
  var d = Draw()
  if boostTime > 0.0:
    let pulse = 1.0 + 0.15 * sin(clock * 43.0)
    d = d.soft(8).poly(@[(cx + 91, cy + 38), (cx + 156 * pulse, cy + 52), (cx + 99, cy + 57)], shade(coral, 96))
    d = poly(d, @[(cx + 94, cy + 40), (cx + 150 * pulse, cy + 49), (cx + 98, cy + 49)], shade(coral, 235))
    d = poly(d, @[(cx + 96, cy + 42), (cx + 135 * pulse, cy + 46), (cx + 99, cy + 47)], shade(champagne, 255))
  if drifting and speed > 8.0:
    let phase = clock * 26.0
    for k in 0 ..< 9:
      let sideSign = if k mod 2 == 0: -1.0 else: 1.0
      let x = cx + sideSign * (95.0 + float(k mod 3) * 8.0) + sin(phase + float(k)) * 7.0
      let y = cy + 53.0 + float((k * 13) mod 31)
      d = d.line(x, y, x + sideSign * 15.0, y + 8.0, shade(if driftCharge > 1.1: coral else: champagne, 190), 2)
  d

proc lapFraction(): float =
  if outcome == "WIN": 1.0 else: `mod`(dist, lapLen) / lapLen

proc stateOverlay(): Draw =
  var d = Draw()
  if outcome.len > 0:
    let won = outcome == "WIN"
    let title = if won: "STAGE WON" elif outcome == "LATE": "TIME EXPIRED" else: "RUN ENDED"
    d = poly(d, @[(354.0, 344.0), (910.0, 344.0), (934.0, 368.0), (934.0, 526.0), (354.0, 526.0), (330.0, 502.0), (330.0, 368.0)], 0xF2070B15'u32)
    d = d.rect(354, 344, 5, 158, shade(if won: champagne else: coral, 255))
    d = txt(d, 382, 375, float(FsMicro), shade(coral, 255), "NOCTURNE RALLY  /  OFFICIAL RESULT", 700)
    d = txt(d, 378, 427, float(FsDisplay), shade(if won: champagne else: ink, 255), title, 700)
    d = txt(d, 382, 458, float(FsBodyLg), shade(muted, 255), stageTime(clock) & " TOTAL   ·   " & $laps & " / 3 LAPS", 500)
    d = txt(d, 382, 488, float(FsMicro), shade(champagne, 255), "BEST LAP  " & (if bestLap > 0.0: fixed(bestLap, 2) & " S" else: "—") & "    ·    LAUNCH TO RACE AGAIN", 700)
  elif countdown > 0.0:
    let n = max(1, int(countdown + 0.999))
    d = txt(d, 580, 390, float(FsMicro), shade(champagne, 255), "HOLD YOUR LINE", 700)
    d = txt(d, 598, 509, float(FsHero), shade(ink, 255), $n, 300)
    d = d.rect(586, 518, 108, 3, shade(coral, 255))
  elif not running:
    d = poly(d, @[(360.0, 360.0), (904.0, 360.0), (928.0, 384.0), (928.0, 526.0), (360.0, 526.0), (336.0, 502.0), (336.0, 384.0)], 0xED070B15'u32)
    d = d.rect(360, 360, 5, 142, shade(coral, 255))
    d = txt(d, 388, 390, float(FsMicro), shade(champagne, 255), "MIDNIGHT SERIES  /  ROUND 03", 700)
    d = txt(d, 384, 440, float(FsDisplay), shade(ink, 255), "THE NIGHT IS YOURS.", 700)
    d = txt(d, 388, 471, float(FsMicro), shade(muted, 255), "3 LAPS  ·  1.5 KM CIRCUIT  ·  THROTTLE ARMED", 500)
    d = txt(d, 388, 500, float(FsMicro), shade(coral, 255), "PRESS LAUNCH    /    ARROWS DRIVE", 700)
  d

proc hud(): Draw =
  var d = Draw()
  # Broadcast-style typography, with open space rather than large HUD boxes.
  d = d.rect(40, 35, 3, 43, shade(coral, 255))
  d = txt(d, 56, 59, float(FsTitleLg), shade(ink, 255), "NOCTURNE", 700)
  d = txt(d, 57, 79, float(FsMicro), shade(champagne, 255), "R A L L Y   /   M I D S U M M E R", 700)
  d = d.circle(586, 48, 3, shade(if running: coral else: champagne, 255))
  d = txt(d, 599, 52, float(FsMicro), shade(muted, 255), if running: "STAGE LIVE" elif countdown > 0.0: "START SEQUENCE" else: "N / R  03", 700)
  let shownLap = min(lapsToWin, laps + 1)
  d = txt(d, 1000, 49, float(FsMicro), shade(champagne, 255), "LAP", 700)
  d = txt(d, 995, 92, float(FsDisplay), shade(ink, 255), pad2(shownLap), 300)
  d = txt(d, 1062, 89, float(FsBodyLg), shade(muted, 255), "/ 03", 400)
  d = d.line(1140, 37, 1140, 95, shade(ink, 40), 1)
  d = txt(d, 1160, 49, float(FsMicro), shade(muted, 255), "TIME", 700)
  d = txt(d, 1158, 78, float(FsBodyLg), shade(ink, 255), stageTime(clock), 500)
  # Velocity is telemetry, not a detached card.
  d = txt(d, 48, 588, float(FsMicro), shade(champagne, 255), "VELOCITY", 700)
  d = txt(d, 43, 677, float(FsHero), shade(ink, 255), $int(speed * 3.6), 300)
  d = txt(d, 211, 665, float(FsMicro), shade(muted, 255), "KM/H", 700)
  for k in 0 ..< 16:
    let active = speed / 58.0 * 16.0 > float(k)
    d = d.rect(float(48 + k * 14), 696, 9, if k mod 4 == 3: 9.0 else: 5.0, shade(if active: (if k > 11: coral else: champagne) else: 0x55606D, if active: 230 else: 80))
  let throttle = gas or keyHeld(keyUp)
  d = txt(d, 49, 724, float(FsMicro), shade(if throttle: champagne else: muted, 220), if throttle: "THROTTLE OPEN" else: "THROTTLE CLOSED", 700)
  # Stage distance, grip and the next corner stay legible over a quiet scrim.
  let fraction = lapFraction()
  d = txt(d, 948, 592, float(FsMicro), shade(champagne, 255), "STAGE PROGRESS", 700)
  d = txt(d, 1118, 624, float(FsTitleLg), shade(ink, 255), $int(fraction * 100.0) & "%", 300)
  d = txt(d, 948, 620, float(FsMicro), shade(muted, 255), $int(`mod`(dist, lapLen)) & " / 1500 M", 500)
  d = d.rect(948, 641, 282, 3, shade(ink, 38), 1)
  d = d.rect(948, 641, 282 * fraction, 3, shade(champagne, 255), 1)
  for k in 0 ..< 3:
    let passed = k < laps or outcome == "WIN"
    d = d.circle(float(954 + k * 20), 664, 3, shade(if passed: champagne else: 0x67707E, if passed: 255 else: 100))
  let bend = curveAt(dist + 105.0) - curveAt(dist + 32.0)
  d = txt(d, 948, 699, float(FsMicro), shade(muted, 255), "NEXT  /  " & (if bend > 2.0: "RIGHT SWEEPER" elif bend < -2.0: "LEFT SWEEPER" else: "CREST"), 700)
  let off = abs(side) >= roadHalf - 1.0
  d = txt(d, 948, 721, float(FsMicro), shade(if off: coral else: champagne, 230), if off: "OFF ROAD  ·  RECOVER" else: "GRIP  ·  RACING LINE", 700)
  if boostTime > 0.0:
    d = txt(d, 530, 119, float(FsBodyLg), shade(coral, 255), "MINI-TURBO  /  " & $boostLevel, 700)
  elif drifting:
    d = txt(d, 530, 119, float(FsMicro), shade(champagne, 255), "DRIFT CHARGE  " & fixed(driftCharge, 1) & " S", 700)
  d = txt(d, 948, 753, float(FsMicro), shade(muted, 220), if drifting: "DRIFT CHARGING" else: "DRIFT  /  SPACE", 700)
  for k in 0 ..< 3:
    let threshold = if k == 0: 0.35 elif k == 1: 1.1 else: 2.0
    let active = (drifting and driftCharge >= threshold) or (boostTime > 0.0 and boostLevel > k)
    d = d.rect(float(948 + k * 96), 765, 88, 3, shade(if active: coral else: 0x67707E, if active: 255 else: 65))
  d.cmds.add stateOverlay().cmds
  d

proc frame(): string =
  var d = road()
  d.cmds.add trackside().cmds
  d.cmds.add speedMarks().cmds
  d = d.linearDown(0, 538, winW, 278, shade(night, 0), shade(night, 142))
  d.cmds.add rallyFx(winW * 0.5 + drift * 32.0, 688.0).cmds
  d.cmds.add kartBody(winW * 0.5 + drift * 32.0, 688.0, drift).cmds
  d.cmds.add hud().cmds
  d.cmds

proc nudgeBy(dir: float) =
  nudgeDir = dir
  nudge = 0.36

proc brakeNow() =
  brakePulse = 0.48

var
  scene: Node
  gasButton: Node
  brakeButton: Node
  driftButton: Node

proc controlStyle(n: Node; w: int32; col: int; textCol: int; size = FsMicro.int32) =
  ## A pedal, on the design system. The fill is glass (rgba 0x111827 at 80%), which
  ## composites to #0F1523 over the night stage — 1.2:1 against it, so the button
  ## had no visible edge at all and no border prop. `controlLine` #7C8798 measures
  ## 5.01:1 on that fill, 4.29:1 on the hover fill and 3.73:1 on the pressed fill
  ## (C3 needs 3:1). Ink #F4F0E8 is 16.04 / 13.74 / 11.92:1 on the three.
  n.width(w)
  n.height(42)
  n.radius(RsCtl)
  n.fontSize(size)
  n.set(pFontWeight, W700.int32)
  n.setFill(col)
  n.set(pTextColor, wireI32(textCol))
  n.set(pBorderWidth, 2'i32)                  # the wire carries one width; the ring is 2 px
  n.set(pBorderColor, wireI32(controlLine))
  # hover / pressed / focused — painted by render/native/engine.nim:1639 stateColor
  n.set(pHoverFill, wireI32(controlHover))
  n.set(pHoverBorder, wireI32(controlLine))
  n.set(pHoverColor, wireI32(ink))
  n.set(pPressFill, wireI32(controlPress))
  n.set(pPressBorder, wireI32(controlLine))
  n.set(pPressColor, wireI32(ink))
  n.set(pFocusBorder, wireI32(ring))          # 13.23:1 on the rest fill
  n.set(pFocusColor, wireI32(ink))

proc paintPedal(n: Node; on: bool; onFill, onHoverF, onPressF: int) =
  ## A pedal that is currently down keeps its own lit colour through every state,
  ## so hovering GAS while it is open does not flip it back to the neutral grey.
  n.setFill(if on: onFill else: controlFill)
  n.set(pTextColor, wireI32(if on: night else: ink))
  n.set(pHoverFill, wireI32(if on: onHoverF else: controlHover))
  n.set(pPressFill, wireI32(if on: onPressF else: controlPress))
  n.set(pHoverColor, wireI32(if on: night else: ink))
  n.set(pPressColor, wireI32(if on: night else: ink))

proc refreshControls() =
  paintPedal(gasButton, gas, champagne, champagneHover, champagnePress)
  paintPedal(brakeButton, brakePulse > 0.0, coral, coralHover, coralPress)
  paintPedal(driftButton, drifting or driftToggle, coral, coralHover, coralPress)

proc main() =
  let win = window("Nocturne Rally", 1280, 816)
  win.setFill(night)
  let stage = stack(win)
  stage.width(1280)
  stage.height(816)
  stage.setFill(night)
  scene = canvas(stage, 1280, 816)
  scene.set(pDraw, frame())
  scene.addHandler(evFrame, proc() =
    step()
    scene.set(pDraw, frame())
    refreshControls())
  let pedals = row(stage)
  pedals.set(pAbsolute, 1'i32)
  pedals.set(pInsetLeft, 40'f32)
  pedals.set(pInsetBottom, 22'f32)
  pedals.spacing(8)
  let leftButton = button(pedals, "◀")
  controlStyle(leftButton, 54, controlFill, ink, FsBodyLg.int32)
  leftButton.addHandler(evClick, proc() = nudgeBy(-1.0))
  let rightButton = button(pedals, "▶")
  controlStyle(rightButton, 54, controlFill, ink, FsBodyLg.int32)
  rightButton.addHandler(evClick, proc() = nudgeBy(1.0))
  gasButton = button(pedals, "GAS")
  controlStyle(gasButton, 92, controlFill, ink)
  gasButton.addHandler(evClick, proc() =
    gas = not gas
    refreshControls())
  brakeButton = button(pedals, "BRAKE")
  controlStyle(brakeButton, 92, controlFill, ink)
  brakeButton.addHandler(evClick, proc() =
    brakeNow()
    refreshControls())
  driftButton = button(pedals, "DRIFT")
  controlStyle(driftButton, 92, controlFill, ink)
  driftButton.addHandler(evClick, proc() =
    driftToggle = not driftToggle
    refreshControls())
  let launchButton = button(pedals, "LAUNCH")
  controlStyle(launchButton, 116, champagne, night)
  # It is champagne at rest, so its lit variants stay champagne in every state.
  launchButton.set(pHoverFill, wireI32(champagneHover))
  launchButton.set(pPressFill, wireI32(champagnePress))
  launchButton.set(pHoverColor, wireI32(night))
  launchButton.set(pPressColor, wireI32(night))
  launchButton.addHandler(evClick, proc() =
    restart()
    scene.set(pDraw, frame())
    refreshControls())
  refreshControls()

proc yantra_main*() {.exportc: "yantra_main".} =
  main()
