## State machines (roadmap S7): a named set of states, the events that move between them, and
## steps that happen by themselves after a while. The state is a signal, so UI that reads it
## follows it.
##
##   machine player:
##     start idle
##     on play: idle -> playing
##     on pause: playing -> idle
##     after 30.s: playing -> idle
##
##   button "Play": onClick: player.send(play)
##   text "{player.state}"                         # idle / playing
##   if player == playing: …
##
## An event that does not apply in the current state does nothing (send returns false). A
## timed step is cancelled if the machine leaves that state first.

import std/[macros, tables, strutils]
import ../core/signals, motion, units

type Machine*[S: enum; E: enum] = ref object
  current*: Signal[S]
  moves: Table[(S, E), S]
  timed: seq[(S, float32, S)]
  hooks: seq[(S, proc ())]
  gen: int                    # bumped on every change: a timer from an older visit does nothing

proc newMachine*[S: enum; E: enum](initial: S; events: typedesc[E]): Machine[S, E] =
  Machine[S, E](current: newState(initial))

proc addMove*[S, E](m: Machine[S, E]; frm: S; ev: E; to: S) = m.moves[(frm, ev)] = to
proc addTimed*[S, E](m: Machine[S, E]; frm: S; ms: float32; to: S) = m.timed.add (frm, ms, to)
proc onEnter*[S, E](m: Machine[S, E]; s: S; body: proc ()) =
  ## Runs `body` every time the machine enters `s`.
  m.hooks.add (s, body)

proc state*[S, E](m: Machine[S, E]): S = m.current.get
  ## The current state (tracked: UI reading it follows it).
proc `==`*[S, E](m: Machine[S, E]; s: S): bool = m.current.get == s
proc `$`*[S, E](m: Machine[S, E]): string = $m.current.get

proc arrive[S, E](m: Machine[S, E]; s: S) =
  inc m.gen
  let g = m.gen
  m.current.set(s)
  for (st, h) in m.hooks:
    if st == s: h()
  for (st, ms, to) in m.timed:
    if st == s:
      let dest = to
      afterMs(ms, proc () =
        if m.gen == g: m.arrive(dest))

proc begin*[S, E](m: Machine[S, E]) =
  ## Starts the timed steps of the first state (the macro calls it).
  m.arrive(m.current.peek)

proc send*[S, E](m: Machine[S, E]; ev: E): bool {.discardable.} =
  ## Moves on if `ev` applies in the current state; false (and nothing changes) if not.
  let k = (m.current.peek, ev)
  if k notin m.moves: return false
  m.arrive(m.moves[k])
  true

proc can*[S, E](m: Machine[S, E]; ev: E): bool = (m.current.get, ev) in m.moves
  ## Whether `ev` would do something now (tracked: a button can grey out with it).

proc nameOf(n: NimNode): NimNode =
  if n.kind == nnkPrefix and $n[0] == "@": n[1] else: n

macro machine*(name: untyped; body: untyped): untyped =
  ## `machine player:` then `start s`, `on ev: a -> b` and `after 2.s: a -> b` lines.
  let m = nameOf(name)
  let base = ($m).capitalizeAscii
  let sType = ident(base & "State")
  let eType = ident(base & "Event")
  var states, events: seq[string]
  var initial = ""
  var steps = newStmtList()
  proc addState(s: string) =
    if s notin states: states.add s
  proc arrow(n: NimNode): (NimNode, NimNode) =
    var x = n
    if x.kind == nnkStmtList and x.len == 1: x = x[0]
    if x.kind != nnkInfix or $x[0] != "->": error("expected `from -> to`", n)
    (x[1], x[2])
  for st in body:
    if st.kind == nnkCommand and $st[0] == "start":
      initial = $st[1]
      addState(initial)
    elif st.kind == nnkCommand and $st[0] == "on" and st.len == 3:
      let (a, b) = arrow(st[2])
      addState($a); addState($b)
      if $st[1] notin events: events.add $st[1]
      steps.add newCall(ident"addMove", m, a, st[1], b)
    elif st.kind == nnkCommand and $st[0] == "after" and st.len == 3:
      let (a, b) = arrow(st[2])
      addState($a); addState($b)
      steps.add newCall(ident"addTimed", m, a, newCall(ident"durationOf", st[1]), b)
    else:
      error("a machine has `start state`, `on event: a -> b` and `after 1.s: a -> b` lines", st)
  if states.len == 0: error("a machine needs at least one state", body)
  if initial.len == 0: initial = states[0]
  if events.len == 0: events.add "noEvent"
  var sEnum = newTree(nnkEnumTy, newEmptyNode())
  for s in states: sEnum.add ident(s)
  var eEnum = newTree(nnkEnumTy, newEmptyNode())
  for ev in events: eEnum.add ident(ev)
  result = newStmtList(
    newTree(nnkTypeSection,
      newTree(nnkTypeDef, sType, newEmptyNode(), sEnum),
      newTree(nnkTypeDef, eType, newEmptyNode(), eEnum)),
    newLetStmt(m, newCall(newTree(nnkBracketExpr, ident"newMachine", sType, eType), ident(initial), eType)))
  result.add steps
  result.add newCall(ident"begin", m)
