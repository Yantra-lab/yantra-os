## Standard Penner & CSS easing curves ([S-TIME-4]). Shared by the SDK and the engines:
## an easing id on the wire (protocol/schema.nim `Easings`) is an index into `EasingKind`.
import std/math

type
  EasingKind* = enum
    easeLinear, easeInQuad, easeOutQuad, easeInOutQuad, easeInCubic, easeOutCubic, easeInOutCubic,
    easeInQuart, easeOutQuart, easeInOutQuart, easeInQuint, easeOutQuint, easeInOutQuint,
    easeInSine, easeOutSine, easeInOutSine, easeInExpo, easeOutExpo, easeInOutExpo,
    easeInCirc, easeOutCirc, easeInOutCirc, easeInBack, easeOutBack, easeInOutBack,
    easeInElastic, easeOutElastic, easeInOutElastic, easeInBounce, easeOutBounce, easeInOutBounce,
    easeSpring, easeSpringGentle, easeSpringBouncy, easeSpringStiff

proc bounceOut(t: float32): float32 =
  const n1 = 7.5625'f32; const d1 = 2.75'f32
  if t < 1.0'f32 / d1: n1 * t * t
  elif t < 2.0'f32 / d1: (let p = t - 1.5'f32 / d1; n1 * p * p + 0.75'f32)
  elif t < 2.5'f32 / d1: (let p = t - 2.25'f32 / d1; n1 * p * p + 0.9375'f32)
  else: (let p = t - 2.625'f32 / d1; n1 * p * p + 0.984375'f32)

proc springParams*(kind: EasingKind): (float32, float32) =
  ## (stiffness, damping) per unit mass — the classic presets (react-spring's default,
  ## gentle, wobbly and stiff).
  case kind
  of easeSpringGentle: (120'f32, 14'f32)
  of easeSpringBouncy: (180'f32, 12'f32)
  of easeSpringStiff: (210'f32, 20'f32)
  else: (170'f32, 26'f32)

proc isSpring*(kind: EasingKind): bool = kind in {easeSpring, easeSpringGentle, easeSpringBouncy, easeSpringStiff}

proc springStep*(kind: EasingKind; seconds: float32): float32 =
  ## A spring released from 0 toward 1 with no initial speed: where it is after `seconds`.
  let (k, c) = springParams(kind)
  let w0 = sqrt(k)
  let z = c / (2 * w0)
  let t = seconds
  if z < 1:
    let wd = w0 * sqrt(1 - z * z)
    1 - exp(-z * w0 * t) * (cos(wd * t) + (z * w0 / wd) * sin(wd * t))
  else:
    1 - exp(-w0 * t) * (1 + w0 * t)

var settleCache: array[4, float32]      # per spring preset, found once

proc springSettle*(kind: EasingKind): float32 =
  ## Seconds after which the spring stays within 0.1% of its target: its natural length.
  ## Found by stepping its response (a closed form misjudges springs near critical damping).
  let i = ord(kind) - ord(easeSpring)
  if i < 0 or i > 3: return 1
  if settleCache[i] > 0: return settleCache[i]
  var last = 0'f32
  var t = 0'f32
  while t < 10:
    if abs(springStep(kind, t) - 1) >= 0.001: last = t
    t += 0.002
  settleCache[i] = last + 0.002
  settleCache[i]

proc sample*(kind: EasingKind, tRaw: float32): float32 =
  if tRaw <= 0.0'f32: return 0.0'f32
  if tRaw >= 1.0'f32: return 1.0'f32
  if kind.isSpring: return springStep(kind, tRaw * springSettle(kind))   # a spring over a fixed time
  let t = tRaw
  const c1 = 1.70158'f32; const c2 = c1 * 1.525'f32; const c3 = c1 + 1.0'f32
  const c5 = (2.0'f32 * PI) / 4.5'f32
  case kind
  of easeLinear: t
  of easeInQuad: t * t
  of easeOutQuad: t * (2.0'f32 - t)
  of easeInOutQuad: (if t < 0.5'f32: 2.0'f32 * t * t else: -1.0'f32 + (4.0'f32 - 2.0'f32 * t) * t)
  of easeInCubic: t * t * t
  of easeOutCubic: (let p = t - 1.0'f32; p * p * p + 1.0'f32)
  of easeInOutCubic: (if t < 0.5'f32: 4.0'f32 * t * t * t else: (let p = 2.0'f32 * t - 2.0'f32; 0.5'f32 * p * p * p + 1.0'f32))
  of easeInQuart: t * t * t * t
  of easeOutQuart: (let p = t - 1.0'f32; 1.0'f32 - p * p * p * p)
  of easeInOutQuart: (if t < 0.5'f32: 8.0'f32 * t * t * t * t else: (let p = t - 1.0'f32; 1.0'f32 - 8.0'f32 * p * p * p * p))
  of easeInQuint: t * t * t * t * t
  of easeOutQuint: (let p = t - 1.0'f32; p * p * p * p * p + 1.0'f32)
  of easeInOutQuint: (if t < 0.5'f32: 16.0'f32 * t * t * t * t * t else: (let p = 2.0'f32 * t - 2.0'f32; 0.5'f32 * p * p * p * p * p + 1.0'f32))
  of easeInSine: 1.0'f32 - cos(t * (PI / 2.0'f32))
  of easeOutSine: sin(t * (PI / 2.0'f32))
  of easeInOutSine: -0.5'f32 * (cos(PI * t) - 1.0'f32)
  of easeInExpo: pow(2.0'f32, 10.0'f32 * (t - 1.0'f32))
  of easeOutExpo: 1.0'f32 - pow(2.0'f32, -10.0'f32 * t)
  of easeInOutExpo: (if t < 0.5'f32: 0.5'f32 * pow(2.0'f32, 20.0'f32 * t - 10.0'f32) else: 1.0'f32 - 0.5'f32 * pow(2.0'f32, -20.0'f32 * t + 10.0'f32))
  of easeInCirc: 1.0'f32 - sqrt(max(0.0'f32, 1.0'f32 - t * t))
  of easeOutCirc: (let p = t - 1.0'f32; sqrt(max(0.0'f32, 1.0'f32 - p * p)))
  of easeInOutCirc: (if t < 0.5'f32: 0.5'f32 * (1.0'f32 - sqrt(max(0.0'f32, 1.0'f32 - 4.0'f32 * t * t))) else: (let p = -2.0'f32 * t + 2.0'f32; 0.5'f32 * (sqrt(max(0.0'f32, 1.0'f32 - p * p)) + 1.0'f32)))
  of easeInBack: c3 * t * t * t - c1 * t * t
  of easeOutBack: (let p = t - 1.0'f32; 1.0'f32 + c3 * p * p * p + c1 * p * p)
  of easeInOutBack: (if t < 0.5'f32: (pow(2.0'f32 * t, 2.0'f32) * ((c2 + 1.0'f32) * 2.0'f32 * t - c2)) / 2.0'f32 else: (let p = 2.0'f32 * t - 2.0'f32; (pow(p, 2.0'f32) * ((c2 + 1.0'f32) * p + c2) + 2.0'f32) / 2.0'f32))
  of easeInElastic: -pow(2.0'f32, 10.0'f32 * t - 10.0'f32) * sin((t * 10.0'f32 - 10.75'f32) * ((2.0'f32 * PI) / 3.0'f32))
  of easeOutElastic: pow(2.0'f32, -10.0'f32 * t) * sin((t * 10.0'f32 - 0.75'f32) * ((2.0'f32 * PI) / 3.0'f32)) + 1.0'f32
  of easeInOutElastic: (if t < 0.5'f32: -(pow(2.0'f32, 20.0'f32 * t - 10.0'f32) * sin((20.0'f32 * t - 11.125'f32) * c5)) / 2.0'f32 else: (pow(2.0'f32, -20.0'f32 * t + 10.0'f32) * sin((20.0'f32 * t - 11.125'f32) * c5)) / 2.0'f32 + 1.0'f32)
  of easeInBounce: 1.0'f32 - bounceOut(1.0'f32 - t)
  of easeOutBounce: bounceOut(t)
  of easeInOutBounce: (if t < 0.5'f32: (1.0'f32 - bounceOut(1.0'f32 - 2.0'f32 * t)) / 2.0'f32 else: (1.0'f32 + bounceOut(2.0'f32 * t - 1.0'f32)) / 2.0'f32)
  of easeSpring, easeSpringGentle, easeSpringBouncy, easeSpringStiff: t   # handled above
