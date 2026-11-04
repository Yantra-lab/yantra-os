## Motion values (docs/spec/style.md §7). The engine plays them on its own clock;
## the app does no work per frame and nothing re-renders.
##
##   panel(transition = 180, ease = outCubic)       # any change glides: fill, colour, box, hover
##   row(enter = fly(y = 12), exit = fade())        # appears / leaves (Svelte in:/out:)
##   icon "loader", animate = spin()                # loops (CSS @keyframes)

import std/macros
import ../core/[runtime, signals]
import units
from ../core/wire import Easing
export Easing

type
  Motion* = object
    ## The far end of an enter or exit: the node fades from `opacity`, moves from
    ## (`x`, `y`), grows from `scale` and turns from `rotate` to itself.
    opacity*, x*, y*, scale*, rotate*: float
    ms*, delay*: int
    ease*: Easing
  Loop* = object
    ## One channel (opacity, rotate, scale, x or y) moving between two values.
    target*: string
    frm*, to*: float
    ms*, delay*, count*: int         ## count 0 = forever
    ease*: Easing
    yoyo*: bool

proc fade*(ms = 180; delay = 0; ease = easeOutCubic): Motion =
  Motion(opacity: 0, scale: 1, ms: ms, delay: delay, ease: ease)

proc fly*(x = 0.0; y = 12.0; opacity = 0.0; ms = 260; delay = 0; ease = easeOutCubic): Motion =
  Motion(opacity: opacity, x: x, y: y, scale: 1, ms: ms, delay: delay, ease: ease)

proc pop*(scale = 0.9; opacity = 0.0; ms = 240; delay = 0; ease = easeOutBack): Motion =
  Motion(opacity: opacity, scale: scale, ms: ms, delay: delay, ease: ease)

proc turn*(rotate = -90.0; scale = 0.6; opacity = 0.0; ms = 320; delay = 0; ease = easeOutBack): Motion =
  Motion(opacity: opacity, scale: scale, rotate: rotate, ms: ms, delay: delay, ease: ease)

proc loop*(target: string; frm, to: float; ms = 1000; yoyo = true; ease = easeInOutSine; count = 0;
           delay = 0): Loop =
  Loop(target: target, frm: frm, to: to, ms: ms, delay: delay, count: count, ease: ease, yoyo: yoyo)

proc spin*(ms = 1000): Loop = loop("rotate", 0, 360, ms, yoyo = false, ease = easeLinear)
proc pulse*(low = 0.4; ms = 1200): Loop = loop("opacity", 1, low, ms)
proc breathe*(scale = 1.04; ms = 1600): Loop = loop("scale", 1, scale, ms)
proc bob*(y = -4.0; ms = 1400): Loop = loop("y", 0, y, ms)

proc encode*(m: Motion): string =
  ## The wire form the engine parses (render/native/motion.nim `parseSpec`).
  $m.opacity & "," & $m.x & "," & $m.y & "," & $m.scale & "," & $m.rotate & "," & $m.ms & "," &
    $m.delay & "," & $ord(m.ease)

proc setEnter*(n: Node; m: Motion) = n.set(pEnter, encode(m))
proc setExit*(n: Node; m: Motion) = n.set(pExit, encode(m))
proc setReveal*(n: Node; m: Motion) = n.set(pReveal, encode(m))
  ## `reveal = fly(y = 40)`: the node sits at that pose below the fold and becomes itself as
  ## it scrolls into view (over the bottom quarter of the view; back again if scrolled away).
  ## Tied to scrolling, not time: `ms` and `delay` are unused, `ease` shapes it.

proc setLoop*(n: Node; l: Loop) =
  n.set(pAnimFrom, float32(l.frm))
  n.set(pAnimTo, float32(l.to))
  n.set(pAnimDuration, int32(l.ms))
  n.set(pAnimDelay, int32(l.delay))
  n.set(pAnimEasing, int32(ord(l.ease)))
  n.set(pAnimLoop, int32(l.count))
  n.set(pAnimYoyo, l.yoyo)
  n.set(pAnimTarget, l.target)          # last: the engine starts the loop when it sees this

# --- steps in time -----------------------------------------------------------------

proc afterMs*(ms: float32; body: proc()) =
  ## Runs `body` once, `ms` from now on the engine's clock (a real clock in a window,
  ## exact frame times when a film is rendered). Batched like an event handler.
  yAfter(int32(max(ms, 0) + 0.5), onHandler(proc() = batch(body)))

template after*(delay: untyped; body: untyped) =
  ## `after 1.2.s: step.set(2)` — a scene moves on by itself; a film is steps in time.
  afterMs(durationOf(delay), proc() = body)

macro timeline*(body: untyped): untyped =
  ## A scene's steps in time, for films and intros:
  ##   timeline:
  ##     at 0.4.s: scene.set(1)          # at a time from now
  ##     then 600.ms: scene.set(2)       # after the step before it
  ## Each step runs once on the engine's clock (`after`), exactly on its frame in a film.
  result = newStmtList()
  let t = genSym(nskVar, "t")
  result.add newVarStmt(t, newLit(0'f32))
  for st in body:
    if st.kind notin {nnkCommand, nnkCall} or st.len != 3 or st[2].kind != nnkStmtList or
       not (eqIdent(st[0], "at") or eqIdent(st[0], "then")):
      error("a timeline step is `at <time>: …` or `then <duration>: …`", st)
    let d = newCall(ident"durationOf", st[1])
    if eqIdent(st[0], "at"): result.add newAssignment(t, d)
    else: result.add infix(t, "+=", d)
    result.add newCall(ident"afterMs", t, newProc(procType = nnkLambda, body = st[2]))
