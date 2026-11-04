## Tests for sdk/motion/timeline.nim and sdk/motion/easing.nim (M1)
import std/tables
import easing, timeline

proc testTypedDurations() =
  let d1 = 600.ms; let d2 = 400.ms; let d3 = 1.s; let d4 = 2.5.s
  doAssert d1.toMillis == 600.0'f32 and d1.toSeconds == 0.6'f32 and d3.toMillis == 1000.0'f32
  doAssert d3.toSeconds == 1.0'f32 and d4.toSeconds == 2.5'f32 and d1 + d2 == d3 and d3 - d2 == d1
  doAssert d1 * 2 == 1200.ms and 2 * d1 == 1200.ms and d1 < d3 and d1 <= d3 and d3 > d1 and d3 >= d1 and d1 != d2
  doAssert $d1 == "600.0.ms" and $d3 == "1.s"

  var threw = false
  try: discard (-50).ms
  except TimelineError: threw = true
  doAssert threw
  var threwSub = false
  try: discard 100.ms - 500.ms
  except TimelineError: threwSub = true
  doAssert threwSub

proc testEasings() =
  let easings = [
    easeLinear, easeInQuad, easeOutQuad, easeInOutQuad, easeInCubic, easeOutCubic, easeInOutCubic,
    easeInQuart, easeOutQuart, easeInOutQuart, easeInQuint, easeOutQuint, easeInOutQuint,
    easeInSine, easeOutSine, easeInOutSine, easeInExpo, easeOutExpo, easeInOutExpo,
    easeInCirc, easeOutCirc, easeInOutCirc, easeInBack, easeOutBack, easeInOutBack,
    easeInElastic, easeOutElastic, easeInOutElastic, easeInBounce, easeOutBounce, easeInOutBounce
  ]
  for e in easings:
    doAssert abs(e.sample(0.0'f32)) < 1e-4 and abs(e.sample(1.0'f32) - 1.0'f32) < 1e-4

  doAssert easeLinear.sample(0.5'f32) == 0.5'f32
  doAssert easeInQuad.sample(0.5'f32) < 0.5'f32 and easeOutQuad.sample(0.5'f32) > 0.5'f32
  doAssert easeInCubic.sample(0.5'f32) == 0.125'f32 and easeOutCubic.sample(0.5'f32) == 0.875'f32

proc testSequentialTimeline() =
  let x = propTarget("x")
  var tl = newTimeline()
  tl.setInitial(x, 10.0'f32)
  tl.to(x, 100.0'f32, 1.s, easeLinear)
  tl.wait(500.ms)
  tl.to(x, 200.0'f32, 500.ms, easeLinear)

  doAssert tl.duration == 2.0'f32
  doAssert tl.sample(-0.5'f32, x) == 10.0'f32 and tl.sample(0.0'f32, x) == 10.0'f32
  doAssert tl.sample(0.5'f32, x) == 55.0'f32 and tl.sample(1.0'f32, x) == 100.0'f32
  doAssert tl.sample(1.25'f32, x) == 100.0'f32 and tl.sample(1.5'f32, x) == 100.0'f32
  doAssert tl.sample(1.75'f32, x) == 150.0'f32 and tl.sample(2.0'f32, x) == 200.0'f32 and tl.sample(3.0'f32, x) == 200.0'f32

proc testParallelAndLoop() =
  let a = propTarget("a"); let b = propTarget("b")
  var tl = newTimeline()
  tl.setInitial(a, 0.0'f32); tl.setInitial(b, 10.0'f32)
  tl.all(
    proc(sub: Timeline) = sub.to(a, 100.0'f32, 1.s, easeLinear),
    proc(sub: Timeline) = sub.to(b, 50.0'f32, 1.5'f32.s, easeLinear)
  )
  doAssert tl.duration == 1.5'f32 and tl.sample(1.0'f32, a) == 100.0'f32
  let expectedB = 10.0'f32 + (40.0'f32 * (1.0'f32 / 1.5'f32))
  doAssert abs(tl.sample(1.0'f32, b) - expectedB) < 1e-4 and tl.sample(1.5'f32, b) == 50.0'f32

  var tlLoop = newTimeline()
  tlLoop.setInitial(a, 0.0'f32)
  tlLoop.loop(3, proc(sub: Timeline) =
    sub.to(a, 10.0'f32, 100.ms, easeLinear)
    sub.to(a, 0.0'f32, 100.ms, easeLinear)
  )
  doAssert tlLoop.duration == 0.6'f32
  for step in 1 .. 3:
    doAssert tlLoop.sample(float32(step - 1) * 0.2'f32 + 0.1'f32, a) == 10.0'f32
    doAssert tlLoop.sample(float32(step) * 0.2'f32, a) == 0.0'f32

proc testZeroDurationAndBoundaries() =
  let p = propTarget("p")
  var tl = newTimeline()
  tl.setInitial(p, 5.0'f32)
  tl.to(p, 42.0'f32, 0.ms)
  doAssert tl.duration == 0.0'f32 and tl.sample(0.0'f32, p) == 42.0'f32 and tl.sample(1.0'f32, p) == 42.0'f32

  var tlBound = newTimeline()
  tlBound.setInitial(p, 0.0'f32)
  tlBound.to(p, 10.0'f32, 1.s, easeLinear)
  tlBound.to(p, 20.0'f32, 1.s, easeLinear)
  doAssert tlBound.sample(1.0'f32, p) == 10.0'f32

proc testTimelineMacroDsl() =
  let alpha = propTarget("alpha"); let rad = propTarget("radius")
  let tl = timeline:
    alpha.to(1.0, 600.ms, easeOutCubic)
    all:
      rad.to(320.0, 1.s, easeOutBack)
      alpha.to(0.5, 1.s)
    wait 300.ms
    loop 2:
      alpha.to(0.8, 100.ms)
      alpha.to(0.2, 100.ms)

  let expectedDuration = 0.6'f32 + 1.0'f32 + 0.3'f32 + 0.4'f32
  doAssert abs(tl.duration - expectedDuration) < 1e-4
  doAssert tl.sample(0.0'f32).hasKey(alpha)
  doAssert tl.sample(expectedDuration)[alpha] == 0.2'f32 and tl.sample(expectedDuration)[rad] == 320.0'f32

  let explicitTarget = propTarget(12'i32, "opacity")
  doAssert $explicitTarget == "#12.opacity" and $alpha == "alpha" and toPropTarget("x") == propTarget("x")
  var tlExplicit = newTimeline()
  tlExplicit.to("color", 10.0, 1.s)
  tlExplicit.to(explicitTarget, 5, 500.ms)
  doAssert tlExplicit.sample(1.5'f32.s, explicitTarget) == 5.0'f32
  doAssert tlExplicit.sample(1.s).hasKey(explicitTarget)
  doAssert tlExplicit.sample(500.ms, propTarget("color")) == 5.0'f32

proc runAll() =
  testTypedDurations(); testEasings(); testSequentialTimeline()
  testParallelAndLoop(); testZeroDurationAndBoundaries(); testTimelineMacroDsl()
  echo "PASS t_timeline"

runAll()
