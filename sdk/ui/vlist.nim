## A virtual list with rows of any height (Q1): only the rows that show (and a few more)
## exist. Heights are measured as rows lay out; rows never seen use the running average.
## The engine keeps the first visible row still when anything above it changes size or is
## prepended (Anchor), keeps a chat at its newest message (StickBottom), and jumps to a row
## by key (ScrollToKey).
import std/tables
import ../core/[wire, runtime, signals]
import widgets, control

type VList*[T] = ref object
  node*: Node                            ## the scroll area
  heights: Table[string, float32]        ## measured row heights by key
  measured: float32                      ## sum of measured heights
  version: Signal[int]                   ## bumped when a height changes: the range is worked out again
  y, h: Signal[float32]                  ## scroll offset and viewport height
  keyOf: proc (x: T): string
  items: proc (): seq[T]
  jumps: int
  overscan*: float32                     ## px built above and below what shows (default 600)
  onTop*: proc ()                        ## scrolled near the top: load older rows (chat)

proc estimate(v: VList): float32 =
  if v.heights.len == 0: 60'f32 else: v.measured / float32(v.heights.len)

proc heightOf(v: VList; key: string): float32 = v.heights.getOrDefault(key, v.estimate)

proc offsetOf*[T](v: VList[T]; key: string): float32 =
  ## Where row `key` starts, by measured heights and estimates.
  for x in untrack(v.items):
    let k = v.keyOf(x)
    if k == key: return
    result += v.heightOf(k)

proc scrollToKey*[T](v: VList[T]; key: string) =
  ## Jumps to row `key`: to its estimated place first (so it gets built), then exactly.
  inc v.jumps
  v.node.set(pScrollY, v.offsetOf(key) + float32(v.jumps mod 2) * 0.001)
  v.node.set(pScrollToKey, key & "#" & $v.jumps)

proc vlist*[T](parent: Node; items: proc (): seq[T]; keyOf: proc (x: T): string;
               row: proc (parent: Node; x: T); chat = false): VList[T] =
  ## `items` in order (a chat: oldest first, `chat = true` starts at the newest and stays
  ## there as messages arrive). `row` builds one row. Size the list like a node (it grows).
  let v = VList[T](keyOf: keyOf, items: items, version: newState(0), y: newState(0'f32), h: newState(0'f32),
                   overscan: 600)
  v.node = make(nkColumn, parent)
  v.node.set(pScroll, true)
  v.node.set(pFlexGrow, 1'f32)
  v.node.set(pMinHeight, 0'f32)
  v.node.set(pAnchor, true)
  if chat: v.node.set(pStickBottom, true)
  let id = int32(v.node.id)
  v.node.addHandler(evScroll, proc () =
    let y = yNodeSize(id, 2)
    batch(proc () = v.y.set(y))
    if v.onTop != nil and y < 200: v.onTop())
  v.node.addHandler(evResize, proc () = batch(proc () = v.h.set(yNodeSize(id, 1))))
  let top = make(nkPanel, v.node)
  var bottom = Node(id: NodeId(-1))
  var first, last = 0
  # the rows that show: a prefix sum over heights (measured or estimated)
  let visible = proc (): seq[T] =
    discard v.version.get
    let y0 = v.y.get - v.overscan
    let y1 = v.y.get + max(v.h.get, 1) + v.overscan
    let xs = v.items()
    var at = 0'f32
    var i = 0
    while i < xs.len and at + v.heightOf(keyOf(xs[i])) < y0:
      at += v.heightOf(keyOf(xs[i]))
      inc i
    first = i
    let above = at
    while i < xs.len and at < y1:
      at += v.heightOf(keyOf(xs[i]))
      inc i
    last = i
    var below = 0'f32
    for j in last ..< xs.len: below += v.heightOf(keyOf(xs[j]))
    top.set(pHeight, above)
    bottom.set(pHeight, below)
    xs[first ..< last]
  keyedList[T](v.node, visible, keyOf, proc (p: Node; x: T) =
    let k = keyOf(x)
    let r = make(nkColumn, p)
    r.set(pItemKey, k)
    let rid = int32(r.id)
    r.addHandler(evResize, proc () =
      let hh = yNodeSize(rid, 1)
      let was = v.heights.getOrDefault(k, -1)
      if abs(hh - was) >= 0.5:
        if was >= 0: v.measured -= was
        v.heights[k] = hh
        v.measured += hh
        batch(proc () = v.version.set(v.version.peek + 1)))
    row(r, x))
  let b = make(nkPanel, v.node)
  bottom.id = b.id
  v
