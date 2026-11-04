## Reactive control flow in UI blocks: `if` and keyed `for` [S-CTL-1..5].
##
## The `app` macro expands `if`/`for` inside a UI block into calls to these two
## procs. Each lives in its own `Group` node (layout-transparent), so it can add,
## remove and reorder its children without disturbing its siblings.
##
## Every branch and every list item is built inside its own scope (Owner). When
## the branch switches or the item disappears, that scope is disposed: its effects
## stop, and the clean-up registered at build time removes its node — with every
## node below it — from the engine.

import std/tables
import ../core/runtime, ../core/signals
import widgets

proc group*(parent: Node): Node =
  ## A layout-transparent container: its children lay out as if they were the
  ## parent's own children.
  make(nkGroup, parent)

proc buildScoped(outer: Owner; parent: Node; build: proc(parent: Node)): (Owner, Node) =
  ## Builds `build` into a fresh Group under `parent`, inside a fresh scope under
  ## `outer`. Disposing the scope removes the Group and everything in it.
  let scope = newOwner(outer)
  var g: Node
  runWithOwner(scope, proc() =
    g = group(parent)
    let gg = g
    onCleanup(proc() = gg.remove())
    build(g))
  (scope, g)

proc showWhen*(parent: Node; branchOf: proc(): int; builds: seq[proc(parent: Node)]) =
  ## `if`/`elif`/`else`: `branchOf` returns the index of the branch to show
  ## (-1 = none). Only a change of branch rebuilds; the branch's own effects keep
  ## it up to date otherwise [S-CTL-1].
  let outer = getOwner()
  let host = group(parent)
  var current = -2
  var scope: Owner = nil
  discard createEffect(proc() =
    let b = branchOf()
    if b == current: return
    current = b
    if scope != nil: disposeOwner(scope)
    scope = nil
    if b >= 0 and b < builds.len:
      scope = buildScoped(outer, host, builds[b])[0])

type
  Item[T] = object
    scope: Owner
    node: Node
    value: T

proc sameValue[T](a, b: T): bool =
  when compiles(a == b): a == b
  else: false

proc keyedList*[T](parent: Node; source: proc(): seq[T]; keyOf: proc(x: T): string;
                   build: proc(parent: Node; item: T); empty: proc(parent: Node) = nil) =
  ## Keyed `for`: one scope per key [S-CTL-2, S-NODE-2].
  ##   * a key that stays with the same value keeps its nodes and state untouched;
  ##   * a key whose value changed is rebuilt in place (same position);
  ##   * a new key is built; a key that goes is disposed, removing its nodes;
  ##   * a move reorders the existing nodes instead of rebuilding them.
  ## Duplicate keys keep only the first occurrence [S-CTL-3]. `empty` is shown
  ## while the list is empty (the `empty:` block after the loop) [S-CTL-5].
  let outer = getOwner()
  let host = group(parent)
  var live = initTable[string, Item[T]]()
  var order: seq[string] = @[]
  var emptyScope: Owner = nil
  discard createEffect(proc() =
    let xs = source()
    var next: seq[string] = @[]
    var fresh = initTable[string, T]()
    for x in xs:
      let k = keyOf(x)
      if k in fresh: continue            # duplicate key: first one wins
      fresh[k] = x
      next.add(k)
    # 1. keys that went away
    for k in order:
      if k notin fresh:
        disposeOwner(live[k].scope)
        live.del(k)
    # 2. changed values are rebuilt where they stand; new keys are built at the end
    for k in next:
      if k in live:
        if not sameValue(live[k].value, fresh[k]):
          let old = live[k]
          let v = fresh[k]
          let (scope, node) = buildScoped(outer, host, proc(p: Node) = build(p, v))
          host.insertBefore(node, old.node)
          disposeOwner(old.scope)
          live[k] = Item[T](scope: scope, node: node, value: v)
      else:
        let v = fresh[k]
        let (scope, node) = buildScoped(outer, host, proc(p: Node) = build(p, v))
        live[k] = Item[T](scope: scope, node: node, value: v)
    # 3. put nodes in order, back to front, only if the order changed
    var kept: seq[string] = @[]
    for k in order:
      if k in fresh: kept.add(k)
    for k in next:
      if k notin kept: kept.add(k)       # new nodes were appended in this order
    if kept != next:
      for i in countdown(next.high, 0):
        let before = if i == next.high: Node(id: NodeId(-1)) else: live[next[i + 1]].node
        host.insertBefore(live[next[i]].node, before)
    order = next
    # 4. the empty state
    if next.len == 0 and empty != nil:
      if emptyScope == nil: emptyScope = buildScoped(outer, host, empty)[0]
    elif emptyScope != nil:
      disposeOwner(emptyScope)
      emptyScope = nil)

proc listValue*[T](s: Signal[seq[T]]): seq[T] = s.get()
  ## What a `for` iterates: a list signal is read (and so tracked)...
proc listValue*[T](s: seq[T]): seq[T] = s
  ## ...a plain list is used as it is.
proc listValue*[I, T](a: array[I, T]): seq[T] = @a
  ## ...and a fixed array becomes a list.
