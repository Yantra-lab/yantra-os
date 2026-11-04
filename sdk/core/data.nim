## Yantra SDK Core — freestanding-safe reactive data layer.
## Pure Nim — compiles both natively and to wasm32 (--cpu:wasm32 --os:standalone --mm:arc).
##
## Deterministic synthesized sales rows for dashboards, tables and charts, held in
## a `Signal[seq[DataRow]]` so views stay reactive. No host imports, no network,
## no C bindings: only the sibling `signals` module plus core language features.
##
##   * `TimeRange` selects the window (row count + labels).
##   * `DataRow` is one sales row.
##   * `FetchResult` holds `rows: Signal[seq[DataRow]]`.
##   * `synthesizeSalesRows` is deterministic (integer hash + wave math) for a
##     given (range, seed) pair.
##   * `sumIt` / `avgIt` / `maxIt` / `minIt` aggregate with an injected `it`.
##   * `pctChange` is a divide-by-zero-safe percent-change helper.

import signals

type
  TimeRange* = enum
    last7days
    last30days
    thisYear

  DataRow* = object
    id*: int
    label*: string
    city*: string
    category*: string
    amount*: float
    orders*: int
    delta*: float

  FetchResult* = ref object
    rows*: Signal[seq[DataRow]]

const
  cityPool = ["Austin", "Berlin", "Cairo", "Denver", "Oslo", "Paris", "Tokyo", "Lima"]
  categoryPool = ["Hardware", "Software", "Services", "Retail"]
  monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

proc rowCountFor*(r: TimeRange): int =
  ## Number of rows `synthesizeSalesRows` produces for a range.
  case r
  of last7days: 7
  of last30days: 30
  of thisYear: 12

func hash32(x: uint32): uint32 =
  ## Integer mixer (xorshift-multiply finalizer): deterministic on every target,
  ## no host calls, no tables, no floats.
  var h = x
  h = h xor (h shr 16)
  h = h * 0x7feb352du32
  h = h xor (h shr 15)
  h = h * 0x846ca68bu32
  h = h xor (h shr 16)
  h

func mixSeed(seed, i, tag: int): uint32 =
  ## Folds (seed, index, tag) into one uint32 before `hash32`.
  let s = uint32(seed and 0x7fffffff)
  let j = uint32(i and 0x00ffffff)
  let t = uint32(tag and 0xff)
  (s * 2246822519u32) xor (j * 3266489917u32) xor (t * 668265263u32) xor 0x9e3779b9u32

func sinApprox(x: float): float =
  ## Bhaskara I sine approximation on any input, pure float math (no imports).
  ## Max error ~0.0016 — plenty for deterministic demo waves.
  const pi = 3.141592653589793
  const twoPi = 6.283185307179586
  var a = x
  let k = int(a / twoPi)
  a = a - float(k) * twoPi
  if a < 0.0:
    a += twoPi
  var sign = 1.0
  if a > pi:
    a -= pi
    sign = -1.0
  let p = a * (pi - a)
  let num = 16.0 * p
  let den = 5.0 * pi * pi - 4.0 * p
  if den == 0.0:
    0.0
  else:
    sign * num / den

proc pctChange*(oldV, newV: float): float =
  ## Safe percent change from `oldV` to `newV`. Zero baseline maps to 0 (both
  ## zero) or +/-100 (one-sided), instead of Inf/NaN.
  if oldV == 0.0:
    if newV == 0.0:
      0.0
    elif newV > 0.0:
      100.0
    else:
      -100.0
  else:
    let base = if oldV < 0.0: -oldV else: oldV
    (newV - oldV) / base * 100.0

proc synthesizeSalesRows*(r: TimeRange; seed: int = 0): seq[DataRow] =
  ## Deterministic sales rows for `(r, seed)`: pure Nim hash + wave math.
  ## Same inputs always give the same rows, on native and wasm alike.
  let n = r.rowCountFor()
  result = newSeq[DataRow](n)
  var prevAmount = 0.0
  for i in 0 ..< n:
    let hAmount = hash32(mixSeed(seed, i, 11))
    let hOrders = hash32(mixSeed(seed, i, 37))
    let hCity = hash32(mixSeed(seed, i, 53))
    let hCat = hash32(mixSeed(seed, i, 79))
    # Two slow waves phased by index + seed so ranges look organic but stable.
    let phase1 = float(i) * 0.85 + float(seed and 0xff) * 0.13
    let phase2 = float(i) * 0.31 + float((seed shr 8) and 0xff) * 0.07
    let w = sinApprox(phase1) * 0.65 + sinApprox(phase2 + 1.3) * 0.35
    let jitter = float(hAmount mod 1000u32) / 1000.0 - 0.5  # -0.5 .. +0.5
    let base =
      case r
      of last7days: 2400.0
      of last30days: 2100.0
      of thisYear: 18000.0
    let amp =
      case r
      of last7days: 520.0
      of last30days: 640.0
      of thisYear: 5200.0
    var amount = base + w * amp + jitter * amp * 0.6
    if amount < 50.0:
      amount = 50.0
    # Round to cents without any formatting imports.
    amount = float(int(amount * 100.0 + 0.5)) / 100.0
    let orders = 20 + int(hOrders mod 180u32) + (if r == thisYear: 240 else: 0)
    let label =
      case r
      of last7days: "Day " & $(i + 1)
      of last30days: "Day " & $(i + 1)
      of thisYear: monthNames[i]
    let city = cityPool[int(hCity mod uint32(cityPool.len))]
    let category = categoryPool[int(hCat mod uint32(categoryPool.len))]
    let delta =
      if i == 0:
        0.0
      else:
        pctChange(prevAmount, amount)
    result[i] = DataRow(id: i, label: label, city: city, category: category,
                        amount: amount, orders: orders, delta: delta)
    prevAmount = amount

template sumIt*(items: untyped, expr: untyped): float =
  ## Sum of `expr` over `items`, with each element as injected `it`.
  ## `total = rows.sumIt(it.amount)`
  block:
    var acc = 0.0
    for it {.inject.} in items:
      acc += float(expr)
    acc

template avgIt*(items: untyped, expr: untyped): float =
  ## Mean of `expr` over `items` (0.0 when empty), with injected `it`.
  block:
    var acc = 0.0
    var n = 0
    for it {.inject.} in items:
      acc += float(expr)
      inc n
    if n == 0: 0.0 else: acc / float(n)

template maxIt*(items: untyped, expr: untyped): float =
  ## Maximum of `expr` over `items` (0.0 when empty), with injected `it`.
  block:
    var best = 0.0
    var first = true
    for it {.inject.} in items:
      let v = float(expr)
      if first or v > best:
        best = v
        first = false
    best

template minIt*(items: untyped, expr: untyped): float =
  ## Minimum of `expr` over `items` (0.0 when empty), with injected `it`.
  block:
    var best = 0.0
    var first = true
    for it {.inject.} in items:
      let v = float(expr)
      if first or v < best:
        best = v
        first = false
    best

proc newFetchResult*(initial: seq[DataRow] = newSeq[DataRow]()): FetchResult =
  ## Empty (or pre-filled) reactive result backed by `state`.
  let s = state(initial)
  FetchResult(rows: s)

proc fetchSales*(r: TimeRange; seed: int = 0): FetchResult =
  ## Synchronous deterministic "fetch": synthesizes rows for `(r, seed)` into
  ## a fresh reactive result. No network, no waiting.
  let s = state(synthesizeSalesRows(r, seed))
  FetchResult(rows: s)

proc refresh*(f: FetchResult; r: TimeRange; seed: int = 0) =
  ## Re-synthesizes rows for `(r, seed)` and publishes them via `.set()`.
  f.rows.set(synthesizeSalesRows(r, seed))

proc totalAmountSignal*(f: FetchResult): Signal[float] =
  ## Reactive total of `amount` over the current rows (updates via `derived`).
  let src = f.rows
  derived(proc(): float =
    var acc = 0.0
    for row in src.get:
      acc += row.amount
    acc)

proc totalOrdersSignal*(f: FetchResult): Signal[float] =
  ## Reactive total of `orders` over the current rows (updates via `derived`).
  let src = f.rows
  derived(proc(): float =
    var acc = 0.0
    for row in src.get:
      acc += float(row.orders)
    acc)
