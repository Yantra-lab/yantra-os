## Hot reload, the app's half (roadmap U4): every `state(...)` remembers where in the
## source it was made, so the engine can save all of them from the running build and
## hand them to the next build, which picks its values back up. Pure Nim; the host
## drives it through four exports (host/host.nim `saveState`, `run(app, restore)`).
##
## A value is matched to its old self by file, line, the n-th call at that line, and
## type; if lines moved, by file, type and order in the file. A type that changed, or
## data that no longer fits, is skipped: that state starts fresh. Nothing crashes.

import std/tables

# --- packing any plain value -----------------------------------------------------

proc packInto*[T](b: var string; x: T) =
  when T is string:
    packInto(b, int32(x.len))
    b.add x
  elif T is bool or T is char or T is enum or T is SomeNumber:
    let raw = cast[array[sizeof(T), char]](x)
    for c in raw: b.add c
  elif T is seq:
    packInto(b, int32(x.len))
    for it in x: packInto(b, it)
  elif T is array:
    for it in x: packInto(b, it)
  elif T is ref:
    packInto(b, x != nil)
    if x != nil: packInto(b, x[])
  elif T is tuple or T is object:
    for f in fields(x): packInto(b, f)
  else:
    {.error: "hot reload cannot keep a value of type " & $T.}

proc unpackFrom*[T](b: string; p: var int; x: var T): bool =
  ## Reads a value written by `packInto`; false if the bytes run out or don't fit.
  when T is string:
    var n: int32
    if not unpackFrom(b, p, n) or n < 0 or p + int(n) > b.len: return false
    x = b[p ..< p + int(n)]
    p += int(n)
    true
  elif T is bool or T is char or T is enum or T is SomeNumber:
    if p + sizeof(T) > b.len: return false
    var raw: array[sizeof(T), char]
    for i in 0 ..< sizeof(T): raw[i] = b[p + i]
    x = cast[T](raw)
    p += sizeof(T)
    true
  elif T is seq:
    var n: int32
    if not unpackFrom(b, p, n) or n < 0 or int(n) > b.len - p: return false
    x.setLen(int(n))
    for i in 0 ..< int(n):
      if not unpackFrom(b, p, x[i]): return false
    true
  elif T is array:
    for i in low(x) .. high(x):
      if not unpackFrom(b, p, x[i]): return false
    true
  elif T is ref:
    var has: bool
    if not unpackFrom(b, p, has): return false
    if has:
      new(x)
      unpackFrom(b, p, x[])
    else:
      x = nil
      true
  elif T is tuple or T is object:
    for f in fields(x):
      if not unpackFrom(b, p, f): return false
    true
  else:
    false

# --- the registry ----------------------------------------------------------------

when not defined(release):             # the registry exists in dev builds only
  type
    HotEntry = object
      file, typ: string
      line, site, order: int
      save: proc (): string {.closure.}
      load: proc (data: string): bool {.closure.}
    Pending = object
      file, typ, data: string
      line, site, order: int
      used: bool

  var entries: seq[HotEntry]
  var siteCount: Table[string, int]        # "file:line" -> calls so far
  var orderCount: Table[string, int]       # "file|type" -> states so far
  var pending: seq[Pending]

  proc findPending(e: HotEntry): int =
    for i, p in pending:
      if not p.used and p.file == e.file and p.typ == e.typ and p.line == e.line and p.site == e.site: return i
    for i, p in pending:                   # the lines moved: same file, type and order
      if not p.used and p.file == e.file and p.typ == e.typ and p.order == e.order: return i
    -1

  proc tryRestore(e: HotEntry) =
    let i = e.findPending
    if i >= 0:
      pending[i].used = true
      discard e.load(pending[i].data)

  proc hotRegister*(file: string; line: int; typ: string; save: proc (): string {.closure.};
                    load: proc (data: string): bool {.closure.}) =
    ## Called by every `state(...)`: remember it, and take its old value if a reload brought one.
    let sk = file & ":" & $line
    let ok = file & "|" & typ
    let site = siteCount.getOrDefault(sk, 0)
    let order = orderCount.getOrDefault(ok, 0)
    siteCount[sk] = site + 1
    orderCount[ok] = order + 1
    let e = HotEntry(file: file, typ: typ, line: line, site: site, order: order, save: save, load: load)
    entries.add e
    e.tryRestore()

  proc hotSnapshot*(): string =
    ## Every registered state, packed.
    packInto(result, int32(entries.len))
    for e in entries:
      packInto(result, e.file)
      packInto(result, e.typ)
      packInto(result, int32(e.line))
      packInto(result, int32(e.site))
      packInto(result, int32(e.order))
      packInto(result, e.save())

  proc hotRestore*(blob: string) =
    ## Takes a snapshot from the previous build: states made from now on (and any made
    ## already) pick up their old values.
    var p = 0
    var n: int32
    if not unpackFrom(blob, p, n): return
    pending.setLen(0)
    for _ in 0 ..< int(n):
      var q: Pending
      var line, site, order: int32
      if not (unpackFrom(blob, p, q.file) and unpackFrom(blob, p, q.typ) and unpackFrom(blob, p, line) and
              unpackFrom(blob, p, site) and unpackFrom(blob, p, order) and unpackFrom(blob, p, q.data)): return
      q.line = int(line); q.site = int(site); q.order = int(order)
      pending.add q
    for e in entries: e.tryRestore()

  proc hotReset*() =
    ## Forgets every registered state, as a fresh instance of the app starts out.
    ## (A real reload loads a new module; tests use this to act out one in-process.)
    entries.setLen(0)
    siteCount.clear()
    orderCount.clear()
    pending.setLen(0)

# --- the host's side: four exports ------------------------------------------------

when not defined(release):             # dev builds only: release apps carry none of this
  var outBuf, inBuf: string

  proc yantraStateSave(): int32 {.exportc: "yantra_state_save".} =
    outBuf = hotSnapshot()
    if outBuf.len == 0: 0'i32 else: cast[int32](cast[uint](addr outBuf[0]))
  proc yantraStateLen(): int32 {.exportc: "yantra_state_len".} = int32(outBuf.len)
  proc yantraStateReserve(n: int32) {.exportc: "yantra_state_reserve".} = inBuf = newString(max(int(n), 1))
  proc yantraStateBuf(): int32 {.exportc: "yantra_state_buf".} = cast[int32](cast[uint](addr inBuf[0]))
  proc yantraStateRestore() {.exportc: "yantra_state_restore".} = hotRestore(inBuf)
