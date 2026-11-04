## Arcade — NEON BREAKER: one paddle, one ball, a wall of bricks that gets faster
## every level. The whole game is this file — the same game as apps/arcade/app.nim,
## in Sutra's own form: a `view` the engine draws, cells whose props are checked
## against the engine's protocol when the app is built.
##
##   ← →  (or A / D)   steer the paddle — the pointer steers it too
##   SPACE             serve the ball now
##   P                 pause
##   R                 restart
##
## Lose three balls and the run ends; clear every brick and the next level is
## faster. Score = the row's value × the combo you have built.

## (Sutra cells never import: `sutra/prelude` brings math, strutils, sequtils…)

# ── the field, in canvas pixels ───────────────────────────────────────────────
const
  W = 1200.0
  H = 640.0
  RailL = 20.0
  RailR = W - 20.0
  CeilY = 12.0
  PaddleW = 150.0
  PaddleH = 14.0
  PaddleTop = 562.0
  PaddleSpeed = 1000.0
  BallR = 8.0
  Cols = 12
  Rows = 6
  BrickW = 86.0
  BrickH = 24.0
  BrickGX = 8.0
  BrickGY = 9.0
  BrickX0 = 53.0
  BrickY0 = 74.0
  StartLives = 3
  ServeWait = 1.1
  MaxSpeed = 780.0

# The palette, in one place, written as it looks: a Sutra colour is 0xAARRGGBB.
let cNight  = #05070E
let cDeep   = #0B1222
let cGrid   = #16203A
let cInk    = #F2F7FF
let cDim    = #8FA3C8
let cFaint  = #5A6C8C
let cNeon   = #35E7FF
let cPink   = #FF3D7F
let cAmber  = #FFC24B
let cLime   = #A6FF5E
let cViolet = #9B7BFF
let cOrange = #FF8A3D
let cRail   = #233A63

let rowInk = [cPink, cViolet, cNeon, cLime, cAmber, cOrange]

# ── small numbers, colours, words ─────────────────────────────────────────────
proc u32(c: Color): uint32 =
  ## A colour is 0xAARRGGBB already; a `Draw` verb wants those four bytes.
  uint32(c)

proc at(c: Color; a: float32): uint32 =
  ## The colour at opacity `a` (0 .. 1), as a `Draw` verb takes it.
  uint32(c.withAlpha(float(clamp(a, 0.0'f32, 1.0'f32))))

proc lit(c: Color; f: float32; a = 1.0'f32): uint32 =
  ## The colour scaled by `f` (its own hue, brighter or darker) at opacity `a`.
  let r = int(clamp(float32(c.red) * f, 0.0'f32, 255.0'f32))
  let g = int(clamp(float32(c.green) * f, 0.0'f32, 255.0'f32))
  let b = int(clamp(float32(c.blue) * f, 0.0'f32, 255.0'f32))
  uint32(rgba(r, g, b, int(clamp(a, 0.0'f32, 1.0'f32) * 255.0'f32)))

proc padded(v, digits: int): string =
  result = $v
  while result.len < digits: result = "0" & result

proc textW(s: string; size: float32): float32 =
  ## An advance estimate for centring a word. The engine's own `measure()` is exact,
  ## but it imports `y_text_measure`/`y_text_height`, which older hosts do not
  ## provide — and an app that fails to instantiate proves nothing.
  float32(s.len) * size * 0.56

proc heartRow(n: int): string =
  result = ""
  for i in 0 ..< StartLives:
    result.add(if i < n: "●" else: "○")

# ── the state: every number the game has ──────────────────────────────────────
type
  Spark = object
    x, y, vx, vy, life, total: float32
    col: Color
    size: float32
  Pop = object
    x, y, life, total: float32
    text: string
    col: Color

var
  gScore = 0
  gLives = StartLives
  gLevel = 1
  gPhase = 0                       # 0 ready, 1 live, 2 paused, 3 over, 4 level cleared
  gWait = ServeWait                # the countdown before the serve
  gPaddle = (W - PaddleW) * 0.5
  gBallX = W * 0.5
  gBallY = PaddleTop - BallR - 2.0
  gVX = 0.0
  gVY = 0.0
  gSpeed = 380.0
  gCombo = 0
  gBest = 0
  gShake = 0.0
  gTime = 0.0
  gBricks: seq[int] = @[]
  gFlash: seq[float32] = @[]
  trailX: seq[float32] = @[]
  trailY: seq[float32] = @[]
  sparks: seq[Spark] = @[]
  pops: seq[Pop] = @[]
  seed = 0x51ED270B'u32
  wasSpace = false
  wasPause = false
  wasRestart = false

# What the UI reads: the HUD words are the app's own numbers, formatted here.
proc scoreLine(): string = padded(gScore, 6)
proc levelLine(): string = padded(gLevel, 2)
proc ballsLine(): string = heartRow(gLives)
proc comboLine(): string = (if gCombo >= 2: "×" & $(1 + min(4, gCombo div 3)) else: "–")
proc stateLine(): string =
  if gPhase == 0: "READY"
  elif gPhase == 1: "LIVE"
  elif gPhase == 2: "PAUSED"
  elif gPhase == 3: "GAME OVER"
  else: "CLEARED"

# ── geometry and chance ───────────────────────────────────────────────────────
proc brickX(c: int): float32 = BrickX0 + float32(c) * (BrickW + BrickGX)
proc brickY(r: int): float32 = BrickY0 + float32(r) * (BrickH + BrickGY)
proc brickAt(r, c: int): int = r * Cols + c
proc levelRows(): int = min(Rows, 3 + gLevel)

proc dot(): float32 =
  ## A number in 0 .. 1. The sandbox has no `random`; the game owns its stream,
  ## so a run is reproducible from its seed.
  seed = seed * 1664525'u32 + 1013904223'u32
  float32(seed shr 8) / 16777216.0'f32

proc bricksLeft(): int =
  for i in 0 ..< gBricks.len:
    if gBricks[i] > 0: inc result

proc hudSync() =
  ## The HUD is read from the game's own numbers when the view is drawn, so there is
  ## nothing to push: kept as the one place a future HUD would publish to.
  discard

# ── starting, serving, losing, levelling ──────────────────────────────────────
proc resetBricks() =
  gBricks = newSeq[int](Rows * Cols)
  gFlash = newSeq[float32](Rows * Cols)
  for r in 0 ..< levelRows():
    for c in 0 ..< Cols:
      gBricks[brickAt(r, c)] = 1

proc parkBall() =
  gBallX = gPaddle + PaddleW * 0.5
  gBallY = PaddleTop - BallR - 2.0
  gSpeed = 380.0
  gVX = 0.0
  gVY = 0.0

proc ready() =
  gPhase = 0
  gWait = ServeWait
  parkBall()
  hudSync()

proc serve() =
  ## A serve, or a serve NOW if the ball is already waiting: one event, twice as useful.
  if gPhase == 0:
    let a = 0.24 + dot() * 0.40          # away from straight up, so it always plays
    let dir = (if dot() < 0.5: -1.0 else: 1.0)
    gVX = gSpeed * sin(a) * dir
    gVY = -gSpeed * cos(a)
    gPhase = 1
    hudSync()

proc newRun() =
  gScore = 0
  gLives = StartLives
  gLevel = 1
  gCombo = 0
  gShake = 0.0
  trailX = @[]
  trailY = @[]
  sparks = @[]
  pops = @[]
  resetBricks()
  ready()

proc burst(x, y: float32; col: Color; n: int; power: float32) =
  for i in 0 ..< n:
    let a = dot() * 6.2831853'f32
    let v = (0.25 + dot() * 0.75) * power
    sparks.add Spark(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v,
                     life: 0.28 + dot() * 0.42, total: 0.7,
                     col: col, size: 1.6 + dot() * 2.8)

proc popAt(x, y: float32; text: string; col: Color) =
  pops.add Pop(x: x, y: y, life: 0.8, total: 0.8, text: text, col: col)

proc dropBall() =
  dec gLives
  gCombo = 0
  gShake = 14.0
  burst(gBallX, H - 6.0, cNeon, 18, 260.0)
  if gLives <= 0:
    gPhase = 3
    gBest = max(gBest, gScore)
    hudSync()
  else:
    ready()

proc brickHit(r, c: int) =
  let i = brickAt(r, c)
  if gBricks[i] <= 0: return
  dec gBricks[i]
  gFlash[i] = 1.0
  let col = rowInk[min(r, rowInk.high)]
  let cx = brickX(c) + BrickW * 0.5
  let cy = brickY(r) + BrickH * 0.5
  if gBricks[i] == 0:
    inc gCombo
    let mult = 1 + min(4, gCombo div 3)
    let pts = (Rows - r) * 10 * mult
    gScore += pts
    burst(cx, cy, col, 9, 215.0)
    popAt(cx - 10.0, cy + 4.0, "+" & $pts, (if mult > 1: cAmber else: col))
    hudSync()
  else:
    burst(cx, cy, col, 3, 120.0)

# ── the ball, in substeps small enough that nothing is missed ─────────────────
proc collideBricks() =
  let r0 = max(0, int((gBallY - BallR - BrickY0) / (BrickH + BrickGY)) - 1)
  let r1 = min(levelRows() - 1, int((gBallY + BallR - BrickY0) / (BrickH + BrickGY)) + 1)
  if r1 < r0: return
  for r in r0 .. r1:
    for c in 0 ..< Cols:
      let i = brickAt(r, c)
      if gBricks[i] <= 0: continue
      let bx = brickX(c)
      let by = brickY(r)
      if gBallX + BallR < bx or gBallX - BallR > bx + BrickW: continue
      if gBallY + BallR < by or gBallY - BallR > by + BrickH: continue
      let nx = clamp(gBallX, bx, bx + BrickW)
      let ny = clamp(gBallY, by, by + BrickH)
      let dx = gBallX - nx
      let dy = gBallY - ny
      if dx * dx + dy * dy > BallR * BallR: continue
      # Bounce off the face the ball came in through: the shallower overlap wins.
      let ox = BallR - abs(dx)
      let oy = BallR - abs(dy)
      if ox < oy:
        gVX = -gVX
        gBallX += (if dx >= 0.0: ox + 0.02 else: -(ox + 0.02))
      else:
        gVY = -gVY
        gBallY += (if dy >= 0.0: oy + 0.02 else: -(oy + 0.02))
      brickHit(r, c)
      return

proc collideWalls() =
  if gBallX - BallR < RailL:
    gBallX = RailL + BallR
    gVX = abs(gVX)
    burst(RailL, gBallY, cRail, 2, 80.0)
  elif gBallX + BallR > RailR:
    gBallX = RailR - BallR
    gVX = -abs(gVX)
    burst(RailR, gBallY, cRail, 2, 80.0)
  if gBallY - BallR < CeilY:
    gBallY = CeilY + BallR
    gVY = abs(gVY)
    burst(gBallX, CeilY, cRail, 2, 80.0)

proc collidePaddle() =
  if gVY <= 0.0: return
  if gBallY + BallR < PaddleTop or gBallY - BallR > PaddleTop + PaddleH: return
  if gBallX < gPaddle - BallR or gBallX > gPaddle + PaddleW + BallR: return
  let rel = clamp((gBallX - (gPaddle + PaddleW * 0.5)) / (PaddleW * 0.5), -1.0'f32, 1.0'f32)
  let ang = rel * 1.02
  gSpeed = min(gSpeed * 1.03, MaxSpeed)
  gVX = gSpeed * sin(ang)
  gVY = -gSpeed * cos(ang)
  gBallY = PaddleTop - BallR - 0.5
  gCombo = 0
  burst(gBallX, PaddleTop, cNeon, 5, 150.0)
  hudSync()

proc stepBall(dt: float32) =
  let n = max(1, int(ceil(gSpeed * dt / 3.0)))
  let h = dt / float32(n)
  for _ in 0 ..< n:
    gBallX += gVX * h
    gBallY += gVY * h
    collideWalls()
    collideBricks()
    collidePaddle()
    if gPhase != 1: return
    if gBallY - BallR > H:
      dropBall()
      return
    if bricksLeft() == 0:
      gScore += 250 * gLevel
      gPhase = 4
      gWait = 1.9
      hudSync()
      return

proc ageEffects(dt: float32) =
  gShake = max(0.0'f32, gShake - dt * 42.0)
  var i = 0
  while i < sparks.len:
    sparks[i].life -= dt
    if sparks[i].life <= 0.0:
      sparks.delete(i)
    else:
      sparks[i].x += sparks[i].vx * dt
      sparks[i].y += sparks[i].vy * dt
      sparks[i].vy += 520.0 * dt
      inc i
  i = 0
  while i < pops.len:
    pops[i].life -= dt
    pops[i].y -= 46.0 * dt
    if pops[i].life <= 0.0: pops.delete(i) else: inc i
  for b in 0 ..< gFlash.len:
    if gFlash[b] > 0.0: gFlash[b] = max(0.0'f32, gFlash[b] - dt * 4.5)

# ── the picture: the table, the bricks, the ball, the words ───────────────────
proc drawBrick(d: var Draw; r, c: int) =
  let i = brickAt(r, c)
  if gBricks[i] <= 0: return
  let x = brickX(c)
  let y = brickY(r)
  let col = rowInk[min(r, rowInk.high)]
  let f = gFlash[i]
  d = d.rect(x - 3.0, y - 3.0, BrickW + 6.0, BrickH + 6.0, at(col, 0.10 + 0.40 * f), 9.0)
  d = d.rect(x, y, BrickW, BrickH, lit(col, 0.34 + 0.9 * f), 6.0)
  d = d.rect(x + 2.0, y + 2.0, BrickW - 4.0, BrickH * 0.42, lit(col, 1.35 + f, 0.85), 4.0)
  d = d.rect(x + 8.0, y + BrickH - 5.0, BrickW - 16.0, 2.0, at(col, 0.55), 1.0)
  if f > 0.02:
    d = d.rect(x, y, BrickW, BrickH, lit(col, 1.7, f * 0.75), 6.0)

proc drawPaddle(d: var Draw) =
  let x = gPaddle
  let y = PaddleTop
  d = d.rect(x - 7.0, y - 9.0, PaddleW + 14.0, PaddleH + 16.0, at(cNeon, 0.10), 13.0)
  d = d.rect(x - 2.0, y - 3.0, PaddleW + 4.0, PaddleH + 6.0, at(cNeon, 0.30), 9.0)
  d = d.linearDown(x, y, PaddleW, PaddleH, u32(cInk), u32(cNeon), 7.0)
  d = d.rect(x + PaddleW * 0.5 - 13.0, y + 3.0, 26.0, PaddleH - 6.0, at(cNight, 0.55), 3.0)
  if gPhase == 0:
    d = d.line(x + PaddleW * 0.5, y - 6.0,
               x + PaddleW * 0.5 + sin(0.24) * 58.0, y - 6.0 - cos(0.24) * 58.0,
               at(cNeon, 0.5), 2.0)

proc drawBall(d: var Draw) =
  var i = 0
  while i < trailX.len:
    let t = float32(i + 1) / float32(trailX.len + 1)
    d = d.circle(trailX[i], trailY[i], BallR * (0.22 + 0.68 * t), at(cNeon, 0.06 + 0.24 * t))
    inc i
  d = d.circle(gBallX, gBallY, BallR * 3.2, at(cNeon, 0.10))
  d = d.circle(gBallX, gBallY, BallR * 1.9, at(cNeon, 0.20))
  d = d.circle(gBallX, gBallY, BallR, u32(cInk))
  d = d.circle(gBallX - BallR * 0.28, gBallY - BallR * 0.28, BallR * 0.42, at(cNeon, 0.95))

proc drawOverlay(d: var Draw) =
  var title = ""
  var sub = ""
  var col = cInk
  if gPhase == 0:
    title = "NEXT BALL IN " & $int(ceil(max(0.0'f32, gWait)))
    sub = "SPACE serves now   ·   ← → moves the paddle"
    col = cNeon
  elif gPhase == 2:
    title = "PAUSED"
    sub = "P resumes   ·   R restarts"
    col = cAmber
  elif gPhase == 3:
    title = "GAME OVER"
    sub = "SCORE " & padded(gScore, 6) & "   ·   BEST " & padded(gBest, 6) & "   ·   R restarts"
    col = cPink
  elif gPhase == 4:
    title = "LEVEL " & $gLevel & " CLEARED"
    sub = "+" & $(250 * gLevel) & "   ·   the next wall is faster"
    col = cLime
  if title.len == 0: return
  let bw = 700.0
  let bh = (if gPhase == 3: 176.0 else: 140.0)
  let bx = (W - bw) * 0.5
  let by = (H - bh) * 0.5 - 22.0
  d = d.rect(bx, by, bw, bh, at(cNight, 0.88), 22.0)
  d = d.rect(bx, by, bw, bh, at(col, 0.16), 22.0)
  d = d.line(bx + 28.0, by + bh - 1.0, bx + bw - 28.0, by + bh - 1.0, at(col, 0.5), 2.0)
  let tw = textW(title, 40.0)
  d = d.text(bx + (bw - tw) * 0.5, by + 66.0, 40.0, u32(col), title, 800)
  let sw = textW(sub, 14.0)
  d = d.text(bx + (bw - sw) * 0.5, by + bh - 42.0, 14.0, u32(cDim), sub, 500)

proc fieldArt(): string =
  var d = Draw()

  # the shake: a few pixels, only while a ball is being lost
  var sx = 0.0'f32
  var sy = 0.0'f32
  if gShake > 0.5:
    sx = sin(gTime * 61.0) * gShake * 0.5
    sy = cos(gTime * 47.0) * gShake * 0.35
  d = d.save().translate(sx, sy)

  # the table: a deep wash, a grid, and the rails the ball bounces off
  d = d.linearDown(0.0, 0.0, W, H, u32(cDeep), u32(cNight))
  var gx = RailL
  while gx <= RailR:
    d = d.line(gx, CeilY, gx, H - 4.0, at(cGrid, 0.55), 1.0)
    gx += 48.0
  var gy = CeilY + 12.0
  while gy < H:
    d = d.line(RailL, gy, RailR, gy, at(cGrid, 0.35), 1.0)
    gy += 48.0
  d = d.rect(RailL - 6.0, CeilY - 6.0, RailR - RailL + 12.0, 6.0, at(cRail, 0.9), 3.0)
  d = d.rect(RailL - 6.0, CeilY, 6.0, H - CeilY, at(cRail, 0.55), 3.0)
  d = d.rect(RailR, CeilY, 6.0, H - CeilY, at(cRail, 0.55), 3.0)

  for r in 0 ..< levelRows():
    for c in 0 ..< Cols:
      drawBrick(d, r, c)

  for s in sparks:
    d = d.circle(s.x, s.y, s.size * (0.35 + 0.75 * s.life / s.total), at(s.col, s.life / s.total))
  for p in pops:
    d = d.text(p.x, p.y, 17.0, at(p.col, clamp(p.life / p.total, 0.0'f32, 1.0'f32)), p.text, 800)

  drawPaddle(d)
  if gPhase != 3: drawBall(d)

  d = d.text(RailL + 12.0, CeilY + 26.0, 11.0, at(cFaint, 1.0), "LEVEL " & padded(gLevel, 2), 700)
  if gCombo >= 2:
    let mult = 1 + min(4, gCombo div 3)
    let s = "COMBO ×" & $mult
    d = d.text(RailR - 12.0 - textW(s, 11.0), CeilY + 26.0, 11.0,
               at(cAmber, 0.95), s, 700)

  drawOverlay(d)
  d = d.restore()
  d.cmds

proc nextLevel() =
  inc gLevel
  gCombo = 0
  sparks = @[]
  trailX = @[]
  trailY = @[]
  resetBricks()
  ready()

# ── one frame ─────────────────────────────────────────────────────────────────
proc press(held: bool; was: var bool): bool =
  ## A key that went down this frame: once, however long it is held.
  result = held and not was
  was = held

proc tick(dt0: float32) =
  let dt = clamp(dt0, 0.0'f32, 0.05'f32)
  if dt <= 0.0: return
  gTime += dt
  ageEffects(dt)

  # Input first: a held key sends no event, so the game reads the engine's own
  # held-key state every frame (this is what makes it a game, not a slideshow).
  var steer = 0.0'f32
  if keyHeld(keyLeft) or keyHeld(int32(ord('a'))): steer -= 1.0
  if keyHeld(keyRight) or keyHeld(int32(ord('d'))): steer += 1.0
  if steer != 0.0 and gPhase in [0, 1]:
    gPaddle = clamp(gPaddle + steer * PaddleSpeed * dt, RailL, RailR - PaddleW)

  if press(keyHeld(keySpace), wasSpace): serve()
  if press(keyHeld(int32(ord('p'))), wasPause) and gPhase in [0, 1, 2]:
    gPhase = (if gPhase == 2: (if gVX == 0.0 and gVY == 0.0: 0 else: 1) else: 2)
    hudSync()
  if press(keyHeld(int32(ord('r'))), wasRestart): newRun()

  case gPhase
  of 0:
    parkBall()
    gPaddle = clamp(gPaddle, RailL, RailR - PaddleW)
    gWait -= dt
    if gWait <= 0.0: serve()
  of 1:
    stepBall(dt)
    if gPhase == 1:
      trailX.add gBallX
      trailY.add gBallY
      if trailX.len > 16:
        trailX.delete(0)
        trailY.delete(0)
  of 4:
    gWait -= dt
    if gWait <= 0.0: nextLevel()
  else:
    discard

  hudSync()

# A warm build plays two and a half seconds itself, with a paddle that follows the
# ball: the proof frame is real game state produced by this physics, not a drawing
# of one. The shipped module is built WITHOUT this define and starts on its countdown.
when defined(arcade_warm):
  proc warmStep() =
    # a paddle that chases the ball with a lag: the return comes off the paddle at
    # an angle, so the rally is varied and the wall really comes down
    let want = clamp(gBallX - PaddleW * 0.5, RailL, RailR - PaddleW)
    gPaddle = clamp(gPaddle + (want - gPaddle) * 0.16, RailL, RailR - PaddleW)
    tick(1.0 / 60.0)

  proc warmUp() =
    for _ in 0 ..< 1500: warmStep()
    # stop on a frame that is mid-rally: a brick just broke, so the sparks and the
    # score popup are on screen. Still the game's own physics, only the timing chosen.
    # stop two frames after a brick breaks: the flash, the sparks and the score
    # popup are all on screen. Still the game's own physics — only the frame is chosen.
    let before = gScore
    var guard = 0
    while gScore == before and guard < 2400:
      # a ball in a cleared column keeps going up and down that column forever:
      # nudge the paddle every 150 frames so the return finds new bricks
      if guard > 0 and guard mod 150 == 0:
        let jolt = (if (guard div 150) mod 2 == 0: 120.0 else: -120.0)
        gPaddle = clamp(gPaddle + jolt, RailL, RailR - PaddleW)
      warmStep()
      inc guard
    for _ in 0 ..< 3: warmStep()
  newRun()
  warmUp()
else:
  newRun()


# ── the view: one window, a HUD row, the field, and the controls ─────────────
view Arcade
  on frame: tick(frameDt())

  Column(width = 1280px, height = 816px, fill = cNight, justify = 1, alignItems = 1, gap = 12px):
    Row(width = 1200px, gap = 24px, alignItems = 1):
      Column(gap = 2px, grow = 1):
        Text "NEON BREAKER", size = 26px, weight = 800, color = cNeon
        Text "break every brick · keep the ball", size = 11px, weight = 500, color = cDim
      Column(gap = 1px, alignItems = 3):
        Text "SCORE", size = 11px, weight = 700, color = cDim
        Text scoreLine(), size = 26px, weight = 800, color = cInk, font = "DejaVu Sans Mono"
      Column(gap = 1px, alignItems = 3):
        Text "COMBO", size = 11px, weight = 700, color = cDim
        Text comboLine(), size = 26px, weight = 800, color = cAmber, font = "DejaVu Sans Mono"
      Column(gap = 1px, alignItems = 3):
        Text "LEVEL", size = 11px, weight = 700, color = cDim
        Text levelLine(), size = 26px, weight = 800, color = cViolet, font = "DejaVu Sans Mono"
      Column(gap = 1px, alignItems = 3):
        Text "BALLS", size = 11px, weight = 700, color = cDim
        Text ballsLine(), size = 20px, weight = 600, color = cPink, font = "DejaVu Sans Mono"

    Canvas(draw = fieldArt(), width = 1200px, height = 640px, fill = cNight):
      on pointerDown:
        let (px, py) = pointerPos()
        gPaddle = clamp(px - PaddleW * 0.5, RailL, RailR - PaddleW)
        if gPhase == 3: newRun()
        elif gPhase == 0: serve()
      on pointerMove:
        let (px, py) = pointerPos()
        if gPhase in [0, 1]:
          gPaddle = clamp(px - PaddleW * 0.5, RailL, RailR - PaddleW)

    Row(width = 1200px, gap = 16px, alignItems = 1):
      Text "← →  or  A / D  move      SPACE  serve      P  pause      R  restart",
           size = 12px, weight = 600, color = cDim, grow = 1
      Text stateLine(), size = 12px, weight = 700, color = cNeon, font = "DejaVu Sans Mono"
      Button "Restart", size = 12px, weight = 700, padTop = 8px, padBottom = 8px,
             padLeft = 16px, padRight = 16px, radius = 10px, fill = #14203A, color = cInk,
             border = 2px, borderColor = 0x5570A8:
        on tap: newRun()
