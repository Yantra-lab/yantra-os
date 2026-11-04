## Yantra Motion Timeline & Deterministic Sampling ([S-TIME-1..4])
import std/[hashes, macros, math, strutils, tables]
import easing
export easing

type
  TimelineError* = object of ValueError
  Duration* = object
    millis*: float32
  PropTarget* = object
    targetId*: int32
    propName*: string
  Tween* = object
    target*: PropTarget
    startVal*, endVal*: float32
    startTime*, duration*: float32
    easing*: EasingKind
  Timeline* = ref object
    currentTime*, maxDuration*: float32
    tweens*: seq[Tween]
    initialValues*, lastTrackEnd*: Table[PropTarget, float32]

proc ms*(v: float32 | float64 | int): Duration = (let f = float32(v); if f < 0.0'f32: raise newException(TimelineError, "Y051 negative: " & $f); Duration(millis: f))
proc s*(v: float32 | float64 | int): Duration = (let f = float32(v); if f < 0.0'f32: raise newException(TimelineError, "Y051 negative: " & $f); Duration(millis: f * 1000.0'f32))
proc toMillis*(d: Duration): float32 = d.millis
proc toSeconds*(d: Duration): float32 = d.millis / 1000.0'f32
proc `+`*(a, b: Duration): Duration = Duration(millis: a.millis + b.millis)
proc `-`*(a, b: Duration): Duration = (if a.millis < b.millis: raise newException(TimelineError, "negative"); Duration(millis: a.millis - b.millis))
proc `*`*(d: Duration, n: int | float32): Duration = Duration(millis: d.millis * float32(n))
proc `*`*(n: int | float32, d: Duration): Duration = Duration(millis: float32(n) * d.millis)
proc `<`*(a, b: Duration): bool = a.millis < b.millis
proc `<=`*(a, b: Duration): bool = a.millis <= b.millis
proc `>`*(a, b: Duration): bool = a.millis > b.millis
proc `>=`*(a, b: Duration): bool = a.millis >= b.millis
proc `==`*(a, b: Duration): bool = a.millis == b.millis
proc `!=`*(a, b: Duration): bool = a.millis != b.millis
proc `$`*(d: Duration): string = (if d.millis >= 1000.0'f32 and (d.millis mod 1000.0'f32 == 0.0'f32): $(int(d.millis / 1000.0'f32)) & ".s" else: $(d.millis) & ".ms")

proc propTarget*(propName: string): PropTarget = PropTarget(targetId: 0'i32, propName: propName)
proc propTarget*(targetId: int32, propName: string): PropTarget = PropTarget(targetId: targetId, propName: propName)
converter toPropTarget*(name: string): PropTarget = propTarget(name)
proc hash*(p: PropTarget): Hash = !$(hash(p.targetId) !& hash(p.propName))
proc `==`*(a, b: PropTarget): bool = a.targetId == b.targetId and a.propName == b.propName
proc `$`*(p: PropTarget): string = (if p.targetId != 0'i32: "#" & $p.targetId & "." & p.propName else: p.propName)

proc newTimeline*(): Timeline =
  Timeline(currentTime: 0.0'f32, maxDuration: 0.0'f32, tweens: @[],
           initialValues: initTable[PropTarget, float32](), lastTrackEnd: initTable[PropTarget, float32]())

proc duration*(tl: Timeline): float32 = tl.maxDuration
proc setInitial*(tl: Timeline, target: PropTarget, val: float32) = tl.initialValues[target] = val

proc sample*(tl: Timeline, t: float32, target: PropTarget): float32

proc to*(tl: Timeline, target: PropTarget, endVal: float32, d: Duration, easing: EasingKind = easeLinear) =
  let durSec = d.toSeconds
  if durSec < 0.0'f32: raise newException(TimelineError, "Y051 negative duration in to: " & $durSec)
  var startVal = (if tl.lastTrackEnd.hasKey(target): tl.lastTrackEnd[target]
                  elif tl.initialValues.hasKey(target): tl.initialValues[target]
                  else: tl.sample(tl.currentTime, target))
  tl.tweens.add(Tween(target: target, startVal: startVal, endVal: endVal,
                      startTime: tl.currentTime, duration: durSec, easing: easing))
  tl.lastTrackEnd[target] = endVal
  tl.currentTime += durSec
  if tl.currentTime > tl.maxDuration: tl.maxDuration = tl.currentTime

proc to*(tl: Timeline, target: PropTarget, endVal: float64 | int, d: Duration, easing: EasingKind = easeLinear) = tl.to(target, float32(endVal), d, easing)
proc to*(tl: Timeline, target: string, endVal: float32 | float64 | int, d: Duration, easing: EasingKind = easeLinear) = tl.to(propTarget(target), float32(endVal), d, easing)

proc wait*(tl: Timeline, d: Duration) =
  let durSec = d.toSeconds
  if durSec < 0.0'f32: raise newException(TimelineError, "Y051 negative duration in wait: " & $durSec)
  tl.currentTime += durSec
  if tl.currentTime > tl.maxDuration: tl.maxDuration = tl.currentTime

proc all*(tl: Timeline, tracks: varargs[proc(sub: Timeline)]) =
  let branchStart = tl.currentTime
  var branchMax = 0.0'f32
  for track in tracks:
    let sub = newTimeline()
    sub.currentTime = branchStart; sub.maxDuration = branchStart
    sub.initialValues = tl.initialValues; sub.lastTrackEnd = tl.lastTrackEnd
    track(sub)
    for tw in sub.tweens: tl.tweens.add(tw); tl.lastTrackEnd[tw.target] = tw.endVal
    let trackDur = sub.maxDuration - branchStart
    if trackDur > branchMax: branchMax = trackDur
  tl.currentTime = branchStart + branchMax
  if tl.currentTime > tl.maxDuration: tl.maxDuration = tl.currentTime

proc loop*(tl: Timeline, count: int, body: proc(sub: Timeline)) =
  if count < 1: raise newException(TimelineError, "Loop count must be >= 1")
  for _ in 0 ..< count: body(tl)

proc sample*(tl: Timeline, t: float32, target: PropTarget): float32 =
  var val = tl.initialValues.getOrDefault(target, 0.0'f32)
  if t < 0.0'f32: return val
  for tw in tl.tweens:
    if tw.target == target:
      let tEnd = tw.startTime + tw.duration
      if t < tw.startTime: discard
      elif t == tw.startTime: val = (if tw.duration == 0.0'f32: tw.endVal else: tw.startVal)
      elif t >= tEnd: val = tw.endVal
      else:
        let progress = (t - tw.startTime) / tw.duration
        val = tw.startVal + (tw.endVal - tw.startVal) * tw.easing.sample(progress)
  result = val

proc sample*(tl: Timeline, t: float32): Table[PropTarget, float32] =
  result = initTable[PropTarget, float32]()
  for target in tl.initialValues.keys: result[target] = tl.sample(t, target)
  for tw in tl.tweens:
    if not result.hasKey(tw.target): result[tw.target] = tl.sample(t, tw.target)

proc sample*(tl: Timeline, d: Duration, target: PropTarget): float32 = tl.sample(d.toSeconds, target)
proc sample*(tl: Timeline, d: Duration): Table[PropTarget, float32] = tl.sample(d.toSeconds)

proc transformTimelineStmt(stmt: NimNode, tlSym: NimNode): NimNode =
  if stmt.kind in {nnkCall, nnkCommand}:
    let head = stmt[0]
    if head.kind in {nnkIdent, nnkSym}:
      let name = ($head).toLowerAscii()
      if name == "wait": return newCall(newDotExpr(tlSym, ident"wait"), stmt[1])
      elif name == "all":
        let inner = newStmtList(); let bStart = genSym(nskLet, "bStart"); let bMax = genSym(nskVar, "bMax")
        inner.add(newLetStmt(bStart, newDotExpr(tlSym, ident"currentTime")), newVarStmt(bMax, newLit(0.0'f32)))
        let allBody = stmt[^1]
        if allBody.kind == nnkStmtList:
          for child in allBody:
            let cb = newStmtList(newAssignment(newDotExpr(tlSym, ident"currentTime"), bStart),
                                transformTimelineStmt(child, tlSym),
                                newAssignment(bMax, newCall(ident"max", bMax, infix(newDotExpr(tlSym, ident"currentTime"), "-", bStart))))
            inner.add(cb)
        inner.add(newAssignment(newDotExpr(tlSym, ident"currentTime"), infix(bStart, "+", bMax)),
                  newAssignment(newDotExpr(tlSym, ident"maxDuration"), newCall(ident"max", newDotExpr(tlSym, ident"maxDuration"), newDotExpr(tlSym, ident"currentTime"))))
        return inner
      elif name == "loop":
        if stmt.len < 3: error("Y050 infinite loop not allowed in scene/film", stmt)
        let forVar = genSym(nskForVar, "i"); let forBody = newStmtList()
        if stmt[2].kind == nnkStmtList:
          for s in stmt[2]: forBody.add(transformTimelineStmt(s, tlSym))
        else: forBody.add(transformTimelineStmt(stmt[2], tlSym))
        return newTree(nnkForStmt, forVar, infix(newLit(0), "..<", stmt[1]), forBody)
    elif head.kind == nnkDotExpr and head[1].kind in {nnkIdent, nnkSym} and ($head[1]).toLowerAscii() == "to":
      var callTree = newCall(newDotExpr(tlSym, ident"to"), head[0])
      for i in 1 ..< stmt.len: callTree.add(stmt[i])
      return callTree
  result = stmt

macro timeline*(body: untyped): untyped =
  let tlSym = genSym(nskVar, "tl")
  result = newStmtList(newVarStmt(tlSym, newCall(ident"newTimeline")))
  if body.kind == nnkStmtList:
    for s in body: result.add(transformTimelineStmt(s, tlSym))
  else: result.add(transformTimelineStmt(body, tlSym))
  result.add(tlSym)
