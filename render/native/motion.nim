## Motion for the native engine (docs/spec/style.md §7): the clock, retargetable
## tweens, enter/exit specs and looping animations. Pure maths: no tree, no canvas,
## so every curve here is tested without a window.
##
## A tween follows a target. When the target changes mid-flight it starts again
## from where it is now, so a hover that ends halfway fades back from halfway, like
## a CSS transition, never jumping.

import std/[strutils, math]
import ../../protocol/easing

type
  Track* = object
    ## One animated number. `seen` is false until the first target arrives; the
    ## first target is taken as is (a node does not animate into existence unless
    ## it asks to, with `enter`).
    a, b: float32
    t0, dur: float64
    ease: int32
    seen: bool
    v: float32              ## springs: speed now (units per second), kept through a retarget
    lastT: float64          ## springs: when the physics last stepped

  ColorTrack* = object
    a, b: uint32
    t0, dur: float64
    ease: int32
    seen: bool

  Spec* = object
    ## How a node looks at the far end of an enter or exit: its opacity, offset,
    ## scale and rotation, and how long the trip takes.
    opacity*, x*, y*, scale*, rotate*: float32
    ms*, delay*: float64
    ease*: int32

  Loop* = object
    ## A looping animation (`animate = spin()`): one channel between two values.
    target*: string         ## opacity | rotate | scale | x | y
    frm*, to*: float32
    ms*, delay*: float64
    ease*: int32
    count*: int             ## 0 = forever
    yoyo*: bool

proc curve*(ease: int32; t: float32): float32 =
  ## Eased progress for an easing id from the wire; unknown ids ease out.
  let k = if ease >= 0 and ease <= int32(high(EasingKind)): EasingKind(ease) else: EasingKind.easeOutCubic
  sample(k, clamp(t, 0, 1))

proc progress(t0, dur, now: float64): float32 =
  if dur <= 0 or now >= t0 + dur: 1'f32
  elif now <= t0: 0'f32
  else: float32((now - t0) / dur)

# --- numbers and colours that follow a target ------------------------------------------

proc isSpringId*(ease: int32): bool =
  ## `ease` is an int32 WIRE id, and the wire `Easing` enum and `EasingKind`
  ## (protocol/easing.nim) declare the same members at the same values (31..34),
  ## so an unqualified ord() is ambiguous once both modules are in scope.
  ## Either qualification is equivalent; name EasingKind explicitly.
  ease >= int32(ord(EasingKind.easeSpring)) and ease <= int32(ord(EasingKind.easeSpringStiff))

proc value*(t: Track; now: float64): float32 =
  if isSpringId(t.ease): t.a                              # springs: where the physics left it
  else: t.a + (t.b - t.a) * curve(t.ease, progress(t.t0, t.dur, now))

proc seen*(t: Track): bool = t.seen
proc startFrom*(t: var Track; v: float32; now: float64) =
  ## Puts the track at `v` (at rest), so the next `follow` moves from there: a hero lands.
  t = Track(a: v, b: v, t0: now, seen: true, lastT: now)

proc running*(t: Track; now: float64): bool =
  if isSpringId(t.ease): t.seen and (t.a != t.b or t.v != 0)
  else: t.seen and t.dur > 0 and now < t.t0 + t.dur

proc stepSpring(t: var Track; now: float64) =
  ## Advances the spring to `now` in small fixed steps (so it lands the same on any frame
  ## rate) and settles it exactly once it is still.
  let (k, c) = springParams(EasingKind(t.ease))
  var left = min((now - t.lastT) / 1000, 10.0)
  const h = 1.0 / 480
  while left > 0:
    let dt = float32(min(h, left))
    let acc = -k * (t.a - t.b) - c * t.v
    t.v += acc * dt
    t.a += t.v * dt
    left -= h
  t.lastT = max(t.lastT, now)
  if abs(t.a - t.b) < 0.001 and abs(t.v) < 0.01:
    t.a = t.b
    t.v = 0

proc follow*(t: var Track; target: float32; now, dur: float64; ease: int32): float32 =
  ## Moves toward `target` from wherever it is now: over `dur` ms along a curve, or — for a
  ## spring — by physics, keeping its speed when the target changes mid-flight.
  if not t.seen:
    t = Track(a: target, b: target, t0: now, seen: true, lastT: now)
  elif isSpringId(ease) and dur > 0:
    if not isSpringId(t.ease):                    # switching to a spring: start from here, at rest
      t.a = t.value(now)
      t.v = 0
      t.lastT = now
    t.ease = ease
    t.dur = dur
    t.stepSpring(now)
    t.b = target
    return t.a
  elif target != t.b:
    let cur = t.value(now)
    t = Track(a: cur, b: target, t0: now, dur: dur, ease: ease, seen: true, lastT: now)
  t.value(now)

proc mix*(a, b: uint32; p: float32): uint32 =
  ## Blends two ARGB colours channel by channel.
  var r = 0'u32
  for sh in [24'u32, 16, 8, 0]:
    let x = float32((a shr sh) and 0xFF)
    let y = float32((b shr sh) and 0xFF)
    r = r or (uint32(clamp(x + (y - x) * p + 0.5, 0, 255)) shl sh)
  r

proc value*(t: ColorTrack; now: float64): uint32 =
  mix(t.a, t.b, curve(t.ease, progress(t.t0, t.dur, now)))

proc running*(t: ColorTrack; now: float64): bool = t.seen and t.dur > 0 and now < t.t0 + t.dur

proc follow*(t: var ColorTrack; target: uint32; now, dur: float64; ease: int32): uint32 =
  if not t.seen:
    t = ColorTrack(a: target, b: target, t0: now, seen: true)
  elif target != t.b:
    let cur = t.value(now)
    t = ColorTrack(a: cur, b: target, t0: now, dur: dur, ease: ease, seen: true)
  t.value(now)

# --- enter / exit ------------------------------------------------------------------------

proc parseSpec*(s: string): Spec =
  ## "opacity,x,y,scale,rotate,ms,delay,easing" as the SDK writes it (sdk/ui/motion.nim).
  result = Spec(opacity: 1, scale: 1, ms: 200, ease: int32(EasingKind.easeOutCubic))
  let f = s.split(',')
  proc num(i: int; d: float): float =
    if i < f.len:
      try: parseFloat(f[i].strip) except ValueError: d
    else: d
  result.opacity = float32(num(0, 1))
  result.x = float32(num(1, 0))
  result.y = float32(num(2, 0))
  result.scale = float32(num(3, 1))
  result.rotate = float32(num(4, 0))
  result.ms = max(0.0, num(5, 200))
  result.delay = max(0.0, num(6, 0))
  result.ease = int32(num(7, float(ord(EasingKind.easeOutCubic))))

type Pose* = object
  ## What motion adds to a node this frame: opacity multiplier, offset, scale, turn.
  opacity*, x*, y*, scale*, rotate*: float32

proc still*(): Pose = Pose(opacity: 1, scale: 1)

proc combine*(a, b: Pose): Pose =
  Pose(opacity: a.opacity * b.opacity, x: a.x + b.x, y: a.y + b.y, scale: a.scale * b.scale,
       rotate: a.rotate + b.rotate)

proc between*(s: Spec; p: float32): Pose =
  ## p = 0 is the spec's far end, p = 1 is the node as it is. Easings that overshoot (outBack)
  ## overshoot position and scale, never opacity.
  Pose(opacity: clamp(s.opacity + (1 - s.opacity) * p, 0, 1), x: s.x * (1 - p), y: s.y * (1 - p),
       scale: s.scale + (1 - s.scale) * p, rotate: s.rotate * (1 - p))

proc entering*(s: Spec; t0, now: float64): Pose =
  ## A node coming in: from the spec to itself. Before its delay it waits at the spec.
  s.between(curve(s.ease, progress(t0 + s.delay, s.ms, now)))

proc leaving*(s: Spec; t0, now: float64): Pose =
  ## A node going out: from itself to the spec (delay ignored: it is already gone).
  s.between(1 - curve(s.ease, progress(t0, s.ms, now)))

proc done*(s: Spec; t0, now: float64; withDelay = true): bool =
  now >= t0 + (if withDelay: s.delay else: 0) + s.ms

# --- loops ---------------------------------------------------------------------------------

proc loopValue*(l: Loop; t0, now: float64): (float32, bool) =
  ## The loop's value now, and whether it is still going.
  if l.ms <= 0: return (l.to, false)
  let el = now - t0 - l.delay
  if el <= 0: return (l.frm, true)
  let cycles = el / l.ms
  var k = floor(cycles)
  var frac = float32(cycles - k)
  var going = true
  if l.count > 0 and k >= float(l.count):
    k = float(l.count - 1)
    frac = 1
    going = false
  if l.yoyo and (int(k) mod 2) == 1: frac = 1 - frac
  (l.frm + (l.to - l.frm) * curve(l.ease, frac), going)

proc identity*(target: string): float32 =
  ## Where a loop starts when the app gave no `from`.
  case target
  of "opacity", "scale": 1
  else: 0

proc poseOf*(target: string; v: float32): Pose =
  result = still()
  case target
  of "opacity": result.opacity = v
  of "scale": result.scale = v
  of "rotate", "rotation": result.rotate = v
  of "x": result.x = v
  of "y": result.y = v
  else: discard
