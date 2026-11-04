## Yantra SDK Core — fine-grained reactive signals, effects, owners and batched writes (L1, L7).
## Pure Nim — compiles both natively and to wasm32 (--cpu:wasm32 --os:standalone --mm:arc).
##
## Three ideas, as in docs/spec/core.md §5:
##   * a `Signal` holds a value and knows which effects read it;
##   * an `Effect` re-runs when a signal it read in its latest run changes. Before
##     every run it forgets its old dependencies and disposes what it created, so it
##     only ever depends on what it actually read last time [S-RX-5];
##   * an `Owner` is a scope. Effects, child scopes and clean-ups belong to the
##     scope that was current when they were created. Disposing a scope disposes all
##     of it, children first, in reverse creation order [S-RX-9]. A list item or an
##     `if` branch is one scope, which is how their nodes and effects go away.

import std/typetraits
import hotstate
export hotstate

type
  Owner* = ref object
    parent: Owner
    children: seq[Owner]
    effects: seq[Effect]
    cleanups: seq[proc()]
    disposed: bool

  SignalBase* = ref object of RootObj
    subscribers: seq[Effect]

  Effect* = ref object
    orderId: int
    fn: proc()
    cleanups: seq[proc()]
    deps: seq[SignalBase]
    scope: Owner          ## what the latest run created; disposed before the next run
    owner: Owner          ## the scope this effect belongs to
    disposed: bool
    queued: bool

  Signal*[T] = ref object of SignalBase
    value: T

var
  currentEffect: Effect = nil
  currentOwner: Owner = nil
  trackingEnabled: bool = true
  nextEffectOrderId: int = 0
  batchDepth: int = 0
  pendingEffects: seq[Effect] = @[]
  flushing: bool = false
  lastOverflowDetected: bool = false
  runsThisFlush: seq[(Effect, int)]

proc hasReactiveOverflow*(): bool =
  ## Returns true if the most recent effect flush hit the 100-run cycle guard.
  lastOverflowDetected

# --- owners ------------------------------------------------------------------

proc newOwner*(parent: Owner = currentOwner): Owner =
  ## A new scope under `parent` (by default, the current one).
  result = Owner(parent: parent)
  if parent != nil and not parent.disposed:
    parent.children.add(result)

proc getOwner*(): Owner = currentOwner

proc isDisposed*(o: Owner): bool = o == nil or o.disposed

proc dispose*(eff: Effect)

proc disposeOwner*(o: Owner) =
  ## Disposes a scope: child scopes, then effects, then clean-ups, each in reverse
  ## creation order. Idempotent.
  if o == nil or o.disposed: return
  o.disposed = true
  for i in countdown(o.children.high, 0): disposeOwner(o.children[i])
  o.children.setLen(0)
  for i in countdown(o.effects.high, 0): dispose(o.effects[i])
  o.effects.setLen(0)
  for i in countdown(o.cleanups.high, 0): o.cleanups[i]()
  o.cleanups.setLen(0)
  if o.parent != nil and not o.parent.disposed:
    let idx = o.parent.children.find(o)
    if idx >= 0: o.parent.children.delete(idx)

proc runWithOwner*(o: Owner; fn: proc()) =
  ## Runs `fn` with `o` as the current scope, outside any effect and untracked:
  ## what `fn` creates belongs to `o`, and what it reads subscribes nothing.
  let prevOwner = currentOwner
  let prevEff = currentEffect
  let prevTrack = trackingEnabled
  currentOwner = o
  currentEffect = nil
  trackingEnabled = false
  try:
    fn()
  finally:
    currentOwner = prevOwner
    currentEffect = prevEff
    trackingEnabled = prevTrack

# --- effects -----------------------------------------------------------------

proc unsubscribeAll(eff: Effect) =
  for dep in eff.deps:
    let i = dep.subscribers.find(eff)
    if i >= 0: dep.subscribers.delete(i)
  eff.deps.setLen(0)

proc runEffectInternal(eff: Effect) =
  if eff == nil or eff.disposed:
    return
  for i in countdown(eff.cleanups.high, 0):
    eff.cleanups[i]()
  eff.cleanups.setLen(0)
  disposeOwner(eff.scope)
  unsubscribeAll(eff)
  eff.scope = Owner(parent: nil)
  let prevEff = currentEffect
  let prevTrack = trackingEnabled
  let prevOwner = currentOwner
  currentEffect = eff
  trackingEnabled = true
  currentOwner = eff.scope
  try:
    eff.fn()
  finally:
    currentEffect = prevEff
    trackingEnabled = prevTrack
    currentOwner = prevOwner

proc noteRun(eff: Effect): bool =
  ## Counts a run of `eff` in this flush; false once it has run more than 100
  ## times — an effect that keeps re-triggering itself is a cycle [S-RX-7].
  for i in 0 ..< runsThisFlush.len:
    if runsThisFlush[i][0] == eff:
      inc runsThisFlush[i][1]
      return runsThisFlush[i][1] <= 100
  runsThisFlush.add((eff, 1))
  true

proc flush() =
  if flushing or batchDepth > 0:
    return
  flushing = true
  lastOverflowDetected = false
  runsThisFlush.setLen(0)
  while pendingEffects.len > 0:
    # Earliest-created first: parents before children, stable order [S-RX-4, S-RX-8].
    var best = 0
    for i in 1 ..< pendingEffects.len:
      if pendingEffects[i].orderId < pendingEffects[best].orderId: best = i
    let eff = pendingEffects[best]
    pendingEffects.delete(best)
    eff.queued = false
    if eff.disposed: continue
    if not noteRun(eff):
      for e in pendingEffects: e.queued = false
      pendingEffects.setLen(0)
      runsThisFlush.setLen(0)
      flushing = false
      lastOverflowDetected = true
      when not defined(standalone):
        raise newException(ValueError, "ReactiveOverflow: effect cycle exceeded 100 iterations")
      else:
        return
    runEffectInternal(eff)
  flushing = false
  runsThisFlush.setLen(0)

proc schedule(subs: seq[Effect]) =
  for eff in subs:
    if eff != nil and not eff.disposed and not eff.queued:
      eff.queued = true
      pendingEffects.add(eff)
  if batchDepth == 0 and not flushing:
    flush()

# --- signals -------------------------------------------------------------------

proc newState*[T](initial: T): Signal[T] =
  Signal[T](value: initial, subscribers: newSeqOfCap[Effect](4))

proc keepAcrossReloads*[T](s: Signal[T]; file: string; line: int) =
  ## Registers `s` with hot reload (sdk/core/hotstate.nim), if its type can be saved.
  ## Release builds leave hot reload out entirely: it costs them nothing.
  when not defined(release) and compiles((var b = ""; packInto(b, s.value))):
    hotRegister(file, line, name(T),
      proc (): string = packInto(result, s.value),
      proc (data: string): bool =
        var x: T
        var p = 0
        if unpackFrom(data, p, x) and p == data.len:
          s.value = x
          true
        else: false)

template state*(initial: untyped): untyped =
  ## A signal holding `initial`. It keeps its value when the app is hot-reloaded.
  let s = newState(initial)
  when not defined(release):
    keepAcrossReloads(s, instantiationInfo(-1).filename, instantiationInfo(-1).line)
  s

proc track(s: SignalBase) =
  if trackingEnabled and currentEffect != nil and not currentEffect.disposed:
    if s.subscribers.find(currentEffect) < 0:
      s.subscribers.add(currentEffect)
      currentEffect.deps.add(s)

proc get*[T](s: Signal[T]): lent T =
  ## Reads and subscribes. Borrowed, not copied: reading a list of 100 000 items costs
  ## nothing (copy it with `var x = s.get` to change it).
  track(s)
  s.value

proc peek*[T](s: Signal[T]): lent T =
  ## Reads without subscribing (borrowed, like `get`).
  s.value

proc `$`*[T](s: Signal[T]): string =
  $(s.get())

converter val*[T](s: Signal[T]): T =
  ## Implicit unwrap of a Signal[T] to its inner value T while tracking subscriptions [S-RX-1].
  s.get()

proc set*[T](s: Signal[T]; v: T) =
  if s.value == v:
    return
  s.value = v
  schedule(s.subscribers)

proc update*[T](s: Signal[T]; fn: proc(v: var T)) =
  ## Mutates in place and always notifies [S-RX-3].
  fn(s.value)
  schedule(s.subscribers)

proc `+=`*[T](s: Signal[T]; delta: T) =
  s.set(s.value + delta)

proc `-=`*[T](s: Signal[T]; delta: T) =
  s.set(s.value - delta)

proc createEffect*(fn: proc()): Effect =
  ## Runs `fn` now and again whenever a signal it read changes. Belongs to the
  ## current scope, so disposing that scope stops it.
  inc nextEffectOrderId
  result = Effect(orderId: nextEffectOrderId, fn: fn, owner: currentOwner)
  if currentOwner != nil and not currentOwner.disposed:
    currentOwner.effects.add(result)
  if flushing:
    runEffectInternal(result)
  else:
    inc batchDepth
    try:
      runEffectInternal(result)
    finally:
      dec batchDepth
    if batchDepth == 0: flush()

proc onCleanup*(fn: proc()) =
  ## Inside an effect: runs before its next run and when it is disposed.
  ## Otherwise: runs when the current scope is disposed.
  if currentEffect != nil and not currentEffect.disposed:
    currentEffect.cleanups.add(fn)
  elif currentOwner != nil and not currentOwner.disposed:
    currentOwner.cleanups.add(fn)

proc dispose*(eff: Effect) =
  if eff == nil or eff.disposed:
    return
  eff.disposed = true
  for i in countdown(eff.cleanups.high, 0):
    eff.cleanups[i]()
  eff.cleanups.setLen(0)
  disposeOwner(eff.scope)
  unsubscribeAll(eff)
  let o = eff.owner
  if o != nil and not o.disposed:
    let i = o.effects.find(eff)
    if i >= 0: o.effects.delete(i)

proc batch*(fn: proc()) =
  inc batchDepth
  try:
    fn()
  finally:
    dec batchDepth
  if batchDepth == 0 and not flushing:
    flush()

proc untrack*[T](fn: proc(): T): T =
  let prevTrack = trackingEnabled
  trackingEnabled = false
  try:
    result = fn()
  finally:
    trackingEnabled = prevTrack

proc derived*[T](fn: proc(): T): Signal[T] =
  ## A value computed from other signals and kept up to date [S-RX-5].
  let s = Signal[T](subscribers: newSeqOfCap[Effect](4))
  discard createEffect(proc() = s.set(fn()))
  s

template derive*(body: untyped): untyped =
  ## `let total = derive: items.get.len * price.get` — `derived` without the proc (S11).
  derived(proc (): auto = body)
