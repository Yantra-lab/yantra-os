## Descent — gradient descent, taught: a real loss, a ball that reads the slope, and every step it took.

const
  chartW = 760.0                 # the chart canvas, in its own pixels
  chartH = 560.0
  xLo = -0.9                     # the guesses the chart shows
  xHi = 4.5
  vLo = 2.2                      # the losses the chart shows
  vHi = 16.0
  px0 = 70.0                     # the plot box inside that canvas
  px1 = 728.0
  py0 = 96.0
  py1 = 470.0
  startX = -0.6                  # where every lesson starts the ball

# ── the palette, chosen once ────────────────────────────────────────────────────────────────
let night = #080D17
let card = #111A2B
let edge = #24314A
let ink = #EAF0FA
let dim = #93A1BC
let faint = #5A6A88
let ballRed = #FF5A3C
let trailAmber = #FFB547
let slopeCool = #58C7F3
let goodGreen = #7BE495

# ── the loss the ball descends ──────────────────────────────────────────────────────────────
proc lossAt(x: float): float =
  ## f(x) = (x-2)^4/8 + (x-2)^2 + 0.6 sin(3x) + 3 — one valley, with bumps on its floor.
  let u = x - 2.0
  result = u*u*u*u/8.0 + u*u + 0.6*sin(3.0*x) + 3.0

proc gradAt(x: float): float =
  ## The only thing the ball may know: f at x ± 0.001, as a difference quotient.
  result = (lossAt(x + 0.001) - lossAt(x - 0.001)) / 0.002

proc curvatureAt(x: float): float =
  ## The second difference: how sharply the curve bends there.
  result = (lossAt(x + 0.001) - 2.0*lossAt(x) + lossAt(x - 0.001)) / 0.000001

proc findBottom(): float =
  ## The lowest point, found by walking the curve: the app measures it instead of claiming it.
  result = xLo
  var best = lossAt(xLo)
  var x = xLo
  while x <= xHi:
    let v = lossAt(x)
    if v < best:
      best = v
      result = x
    x += 0.0005

let valley = findBottom()
let edgeRate = 2.0 / curvatureAt(valley)   # past this, the linear model stops converging

# ── numbers, colours, chart coordinates ────────────────────────────────────────────────────
proc fixed(v: float; digits: int): string =
  ## A number with exactly `digits` places (this build has no formatFloat).
  var p = 1
  for i in 0 ..< digits:
    p = p * 10
  let a = abs(v)
  var n = 100000 * p
  if a < 100000.0:
    n = int(a * float(p) + 0.5)
  result = (if v < 0.0 and n > 0: "-" else: "") & $(n div p)
  if digits > 0:
    var f = $(n mod p)
    while f.len < digits:
      f = "0" & f
    result = result & "." & f

proc shade(c: Color; alpha: int): uint32 =
  ## That colour at that opacity, as the engine's 0xAARRGGBB.
  (uint32(alpha and 0xFF) shl 24) or (uint32(c) and 0x00FFFFFF'u32)

proc toX(x: float): float =
  px0 + (clamp(x, xLo, xHi) - xLo) / (xHi - xLo) * (px1 - px0)

proc toY(v: float): float =
  py1 - (clamp(v, vLo, vHi) - vLo) / (vHi - vLo) * (py1 - py0)

proc note(x: float; lr: float; momentum: bool; steps: int): string =
  ## One true sentence about what is happening under the ball right now.
  let g = gradAt(x)
  if steps == 0:
    result = "ready: x = " & fixed(x, 3) & ". one tap is one step, and the ball only ever reads the slope."
  elif x <= xLo + 0.0001 or x >= xHi - 0.0001:
    result = "pinned to the edge: the step is wider than the whole valley. lower the rate, then Reset."
  elif abs(g) < 0.02:
    result = "at the bottom: the slope is " & fixed(g, 4) & " and the step is " & fixed(abs(lr*g), 5) & ", so it stops."
  elif momentum:
    result = "momentum: the step keeps 85% of the last one, so the ball overshoots the bottom and swings back."
  else:
    result = "slope " & fixed(g, 2) & ": this step moves x by " & fixed(abs(lr*g), 3) & " downhill at rate " & fixed(lr, 3) & "."
  result

# ── the chart: the curve, the trail, the ball, the words ───────────────────────────────────
proc plot(x: float; trail: seq[float]; lr: float; momentum: bool; steps: int): string =
  var d = Draw()
  d = d.rect(1, 1, chartW - 2, chartH - 2, shade(edge, 0xFF), 20)
  d = d.rect(2, 2, chartW - 4, chartH - 4, shade(night, 0xFF), 19)
  d = d.text(30, 18, 11, shade(dim, 0xFF), "LOSS SURFACE", 700)
  d = d.text(30, 38, 12, shade(faint, 0xFF), "f(x) = (x-2)^4/8 + (x-2)^2 + 0.6 sin(3x) + 3", 400)
  d = d.text(30, 74, 10, shade(faint, 0xFF), "LOSS", 700)
  var v = 4.0
  while v <= 14.0:
    d = d.line(px0, toY(v), px1, toY(v), shade(edge, 0x88), 1)
    d = d.text(px0 - 30, toY(v) - 7, 10, shade(faint, 0xFF), $(int(v)), 500)
    v += 2.0
  var gx = 0.0
  while gx <= 4.0:
    d = d.line(toX(gx), py0, toX(gx), py1, shade(edge, 0x66), 1)
    d = d.text(toX(gx) - 3, py1 + 9, 10, shade(faint, 0xFF), $(int(gx)), 500)
    gx += 1.0
  d = d.line(px0, py1, px1, py1, shade(edge, 0xFF), 1)
  # the curve: the area under it first, then the line itself, with a glow
  var band = Draw()
  var curve = Draw()
  var pen = false
  var s = xLo
  while s <= xHi + 0.00001:
    let lv = lossAt(s)
    if lv <= vHi:
      if not pen:
        band = band.moveTo(toX(s), py1).lineTo(toX(s), toY(lv))
        curve = curve.moveTo(toX(s), toY(lv))
        pen = true
      else:
        band = band.lineTo(toX(s), toY(lv))
        curve = curve.lineTo(toX(s), toY(lv))
    elif pen:
      band = band.lineTo(toX(s), py1).close()
      pen = false
    s += 0.01
  if pen:
    band = band.lineTo(toX(xHi), py1).close()
  d.cmds.add band.fill(shade(slopeCool, 0x22)).cmds
  d.cmds.add curve.stroke(shade(slopeCool, 0x2E), 9).cmds
  d.cmds.add curve.stroke(shade(slopeCool, 0xFF), 2.5).cmds
  # the bottom the app found: a line up from the axis and a mark on the curve
  let bxp = toX(valley)
  let byp = toY(lossAt(valley))
  d = d.line(bxp, byp, bxp, py1, shade(goodGreen, 0x44), 1)
  d = d.circle(bxp, byp, 3.5, shade(goodGreen, 0xFF))
  d = d.text(bxp - 36, py1 + 26, 10, shade(goodGreen, 0xFF), "bottom " & fixed(valley, 3), 600)
  # every step it took, the oldest faint, the newest bright
  var i = 0
  while i < trail.len:
    let tx = toX(trail[i])
    let ty = toY(lossAt(trail[i]))
    let alpha = 0x70 + min(i * 5, 0x8F)
    d = d.circle(tx, ty, (if i == trail.len - 1: 4.5 else: 3.0), shade(trailAmber, alpha))
    if i + 1 < trail.len:
      let nx = toX(trail[i + 1])
      let ny = toY(lossAt(trail[i + 1]))
      d = d.line(tx, ty, nx, ny, shade(trailAmber, 0x4C), 1.5)
    i += 1
  if trail.len > 0:
    let fx = toX(trail[0])
    let fy = toY(lossAt(trail[0]))
    d = d.rect(fx - 24, fy - 25, 48, 14, shade(night, 0xE6), 7)
    d = d.text(fx - 19, fy - 23, 9, shade(dim, 0xFF), "START", 700)
  # the slope it feels, drawn along the ball
  let g = gradAt(x)
  let bx = toX(x)
  let by = toY(lossAt(x))
  if abs(g) > 0.02:
    let dir = (if g > 0.0: -1.0 else: 1.0)
    let size = clamp(10.0 + abs(g) * 3.5, 10.0, 52.0)
    let tip = bx + dir * (12.0 + size)
    d = d.line(bx + dir * 10.0, by, tip, by, shade(slopeCool, 0xD0), 2.5)
    d = d.moveTo(tip, by).lineTo(tip - dir * 8, by - 4.5).lineTo(tip - dir * 8, by + 4.5).close().fill(shade(slopeCool, 0xD0))
  # the ball
  d = d.circle(bx, by, 19, shade(ballRed, 0x1C))
  d = d.circle(bx, by, 12, shade(ballRed, 0x33))
  d = d.circle(bx, by, 7.5, shade(ballRed, 0xFF))
  d = d.circle(bx - 2.5, by - 2.5, 2.2, 0xFFFFE6DA'u32)
  # the axis caption, the legend, the sentence about now
  d = d.text(30, 496, 10, shade(faint, 0xFF), "x: the one number the machine may change", 500)
  d = d.circle(500, 521, 4, shade(ballRed, 0xFF))
  d = d.text(510, 514, 10, shade(dim, 0xFF), "THE BALL", 700)
  d = d.circle(580, 521, 3, shade(trailAmber, 0xFF))
  d = d.text(590, 514, 10, shade(dim, 0xFF), "EVERY STEP", 700)
  d = d.line(664, 521, 678, 521, shade(slopeCool, 0xFF), 2)
  d = d.text(684, 514, 10, shade(dim, 0xFF), "LOSS", 700)
  let gnow = gradAt(x)
  let say = shade((if steps > 0 and (x <= xLo + 0.0001 or x >= xHi - 0.0001): ballRed
                   elif steps > 0 and abs(gnow) < 0.02: goodGreen
                   else: slopeCool), 0xFF)
  d = d.text(30, 534, 12, say, note(x, lr, momentum, steps), 500)
  d.cmds

# ── the two controls the engine paints no chrome for, drawn by the app ─────────────────────
proc rateArt(lr: float): string =
  ## The learning-rate track and its knob (a Slider node sits on top and takes the drag).
  var d = Draw()
  let t = clamp((lr - 0.01) / 0.79, 0.0, 1.0)
  let kx = 14.0 + t * 348.0
  let ex = 14.0 + (edgeRate - 0.01) / 0.79 * 348.0
  d = d.rect(14, 8, 348, 6, shade(edge, 0xFF), 3)
  d = d.rect(14, 8, max(kx - 14.0, 1.0), 6, shade(ballRed, 0xE0), 3)
  d = d.line(ex, 2, ex, 20, shade(trailAmber, 0xCC), 1)
  d = d.circle(kx, 11, 13, shade(ballRed, 0x22))
  d = d.circle(kx, 11, 7, shade(ballRed, 0xFF))
  d = d.circle(kx, 11, 2.5, 0xFFFFFFFF'u32)
  d = d.text(14, 24, 9, shade(faint, 0xFF), "0.01", 500)
  d = d.text(344, 24, 9, shade(faint, 0xFF), "0.80", 500)
  d = d.text(ex - 12, 24, 9, shade(trailAmber, 0xFF), fixed(edgeRate, 3), 700)
  d.cmds

proc switchArt(on: bool): string =
  ## The momentum switch, drawn (the Switch node on top takes the tap).
  var d = Draw()
  d = d.rect(0, 3, 64, 26, (if on: shade(goodGreen, 0xFF) else: shade(edge, 0xFF)), 13)
  d = d.circle((if on: 51.0 else: 13.0), 16, 9, shade(ink, 0xFF))
  d.cmds

# ── the three chapters, and the true sentence each one changes ─────────────────────────────
proc chapTitle(c: int): string =
  if c == 0: "A ball on a hill" elif c == 1: "Learning rate" else: "Momentum"

proc chapBody(c: int): string =
  if c == 0:
    "The curve is the loss: for every guess x, its height is how wrong that guess is. The machine " &
      "never sees the curve. It samples the slope at x±0.001 and steps against it, again and again, " &
      "until the ground is flat. That works because the slope points uphill: step the other way and " &
      "the loss goes down."
  elif c == 1:
    "The rate is the length of every step: x = x - rate * slope. Too small and learning crawls, " &
      "because every step is a fraction of what the slope asks for. Too large and each step crosses " &
      "the valley and climbs the far wall, so the loss stops falling and the ball bounces instead. " &
      "The right rate belongs to the curve, not to the algorithm."
  else:
    "Momentum keeps 85% of the last step and adds the new slope to it, so the ball remembers where it " &
      "was going instead of forgetting at every step. On a long slope that is speed. Near the bottom " &
      "it is an overshoot: the ball carries past the valley, climbs the other side, and settles only " &
      "when its memory runs out."

proc chapFact(c: int): string =
  ## Measured on this very curve by this very code — the numbers on the screen are the proof.
  if c == 0:
    "One step from the start moves x by 0.288: 0.02 x the slope there (14.4). The steps shrink as the slope does."
  elif c == 1:
    "2 / f''(bottom) = " & fixed(edgeRate, 3) & " is where the linear model stops converging. At 0.32 the ball still jumps between x = 1.45 and 2.04."
  else:
    "At the same 0.02 with momentum on, the ball rolls past the bottom to x = 3.16 before it turns back. Without it, x never passes 1.691."

proc chipFill(c: int; i: int): Color = (if c == i: ballRed else: edge)

proc chipInk(c: int; i: int): Color = (if c == i: night else: dim)

# ── the app ───────────────────────────────────────────────────────────────────────────────
view Descent
  state x = -0.6
  state vel = 0.0
  state steps = 0
  state lr = 0.02
  state momentum = false
  state chap = 0
  state trail = @[-0.6]
  Stack(fill = night, width = 1280px, height = 816px):
    Text "Descent", size = 38px, weight = 700, color = ink, absolute = true, left = 40px, top = 24px
    Text "HOW A MACHINE LEARNS, ONE STEP AT A TIME", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono", absolute = true, left = 42px, top = 78px
    Text "THE LOSS IT DESCENDS", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono", absolute = true, left = 820px, top = 30px, width = 420px, align = 2
    Text "f(x) = (x-2)^4/8 + (x-2)^2 + 0.6 sin(3x) + 3", size = 11px, color = faint, font = "DejaVu Sans Mono", absolute = true, left = 820px, top = 50px, width = 420px, align = 2

    Canvas(draw = plot(x, trail, lr, momentum, steps), width = 760px, height = 560px, absolute = true, left = 40px, top = 124px)

    Panel(fill = card, radius = 16px, border = 1px, borderColor = edge, pad = 16px, absolute = true, left = 40px, top = 700px, width = 1200px, height = 86px):
      Row(gap = 20px):
        Column(gap = 3px, grow = 1):
          Text "X: THE GUESS", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono"
          Text fixed(x, 3), size = 24px, weight = 700, color = ink, font = "DejaVu Sans Mono"
        Column(gap = 3px, grow = 1):
          Text "LOSS: HOW WRONG", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono"
          Text fixed(lossAt(x), 3), size = 24px, weight = 700, color = ink, font = "DejaVu Sans Mono"
        Column(gap = 3px, grow = 1):
          Text "STEPS TAKEN", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono"
          Text "{steps}", size = 24px, weight = 700, color = trailAmber, font = "DejaVu Sans Mono"
        Column(gap = 3px, grow = 1):
          Text "SLOPE: DLOSS/DX", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono"
          Text fixed(gradAt(x), 3), size = 24px, weight = 700, color = slopeCool, font = "DejaVu Sans Mono"

    Panel(fill = card, radius = 18px, border = 1px, borderColor = edge, pad = 20px, absolute = true, left = 820px, top = 124px, width = 420px, height = 340px):
      Column(gap = 10px):
        Text "CHAPTER {chap + 1} / 3", size = 10px, weight = 700, color = ballRed, font = "DejaVu Sans Mono"
        Text chapTitle(chap), size = 24px, weight = 700, color = ink
        Text chapBody(chap), size = 14px, color = dim, lineHeight = 1.45
        Text chapFact(chap), size = 12px, color = goodGreen, lineHeight = 1.45
        Row(gap = 6px):
          Button "A ball on a hill", size = 10px, pad = 8px, radius = 9px, grow = 1, fill = chipFill(chap, 0), color = chipInk(chap, 0):
            on tap:
              chap = 0
              lr = 0.02
              momentum = false
              x = startX
              vel = 0.0
              steps = 0
              trail = @[startX]
          Button "Learning rate", size = 10px, pad = 8px, radius = 9px, grow = 1, fill = chipFill(chap, 1), color = chipInk(chap, 1):
            on tap:
              chap = 1
              lr = 0.32
              momentum = false
              x = startX
              vel = 0.0
              steps = 0
              trail = @[startX]
          Button "Momentum", size = 10px, pad = 8px, radius = 9px, grow = 1, fill = chipFill(chap, 2), color = chipInk(chap, 2):
            on tap:
              chap = 2
              lr = 0.02
              momentum = true
              x = startX
              vel = 0.0
              steps = 0
              trail = @[startX]

    Panel(fill = card, radius = 18px, border = 1px, borderColor = edge, pad = 20px, absolute = true, left = 820px, top = 480px, width = 420px, height = 306px):
      Column(gap = 10px):
        Row(gap = 8px):
          Text "LEARNING RATE", size = 10px, weight = 700, color = dim, font = "DejaVu Sans Mono"
          Text fixed(lr, 3), size = 22px, weight = 700, color = ballRed, font = "DejaVu Sans Mono", grow = 1, align = 2
        Stack(width = 380px, height = 36px):
          Canvas(draw = rateArt(lr), width = 380px, height = 36px)
          Slider value = lr, min = 0.01, max = 0.8, width = 380px, height = 36px, left = 0px, top = 0px:
            on pointerDown:
              let (px, py) = pointerPos()
              lr = 0.01 + 0.79 * clamp((float(px) - 14.0) / 348.0, 0.0, 1.0)
            on pointerMove:
              let (px, py) = pointerPos()
              lr = 0.01 + 0.79 * clamp((float(px) - 14.0) / 348.0, 0.0, 1.0)
        Row(gap = 6px):
          Button "slower", size = 10px, pad = 6px, radius = 8px, fill = edge, color = dim:
            on tap: lr = max(0.01, lr * 0.7)
          Button "faster", size = 10px, pad = 6px, radius = 8px, fill = edge, color = dim:
            on tap: lr = min(0.8, lr * 1.4)
          Text "past {fixed(edgeRate, 3)} the ball stops settling", size = 9px, color = faint, font = "DejaVu Sans Mono", grow = 1, align = 2
        Row(gap = 10px):
          Stack(width = 64px, height = 32px):
            Canvas(draw = switchArt(momentum), width = 64px, height = 32px)
            Switch checked = momentum, width = 64px, height = 32px, left = 0px, top = 0px:
              on tap: momentum = not momentum
          if momentum:
            Text "momentum on: every step keeps 85% of the last one", size = 10px, color = dim, grow = 1
          else:
            Text "momentum off: every step starts from zero", size = 10px, color = dim, grow = 1
        Row(gap = 8px):
          Button "Step", size = 14px, weight = 700, pad = 15px, radius = 11px, grow = 1, fill = ballRed, color = night:
            on tap:
              let g = gradAt(x)
              vel = (if momentum: 0.85*vel else: 0.0) - lr*g
              x = clamp(x + vel, xLo, xHi)
              steps += 1
              trail.add x
          Button "Run 10", size = 14px, weight = 700, pad = 15px, radius = 11px, grow = 1, fill = edge, color = ink:
            on tap:
              for i in 0 ..< 10:
                let g = gradAt(x)
                vel = (if momentum: 0.85*vel else: 0.0) - lr*g
                x = clamp(x + vel, xLo, xHi)
                steps += 1
                trail.add x
          Button "Reset", size = 14px, weight = 700, pad = 15px, radius = 11px, grow = 1, fill = card, color = dim:
            on tap:
              x = startX
              vel = 0.0
              steps = 0
              trail = @[startX]
        Text "every number here is computed in the app, from f and its sampled slope", size = 9px, color = faint, font = "DejaVu Sans Mono"
