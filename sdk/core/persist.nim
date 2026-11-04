## Saved state (N1): `persistent(initial, "key")` is a `state(...)` that the app finds again
## the next time it runs. Values are packed like hot-reload snapshots (hotstate.nim) and kept
## by the host in the app's own folder (host.nim `storeSet`: 1 MB a value, 16 MB an app).

import runtime, signals, hotstate

when sizeof(pointer) == 4:                # wasm: hand the host (pointer, length) pairs
  proc ptrOf(s: string): int32 = (if s.len == 0: 0'i32 else: cast[int32](cast[uint](unsafeAddr s[0])))

  proc loadStored*(key: string; into: var string): bool =
    ## The bytes saved under `key`, if any.
    let n = yStoreGet(ptrOf(key), int32(key.len), 0, 0)
    if n < 0: return false
    into = newString(int(n))
    if n > 0: discard yStoreGet(ptrOf(key), int32(key.len), ptrOf(into), n)
    true

  proc saveStored*(key, bytes: string): bool =
    ## Saves bytes under `key`; false if the host refused (bad key, too big, over quota).
    yStoreSet(ptrOf(key), int32(key.len), ptrOf(bytes), int32(bytes.len)) == 1
else:                                     # native builds (tests) have no host: a test sets these
  var nativeStoreGet*: proc (key: string): (bool, string)
  var nativeStoreSet*: proc (key, bytes: string): bool

  proc loadStored*(key: string; into: var string): bool =
    if nativeStoreGet == nil: return false
    let (found, v) = nativeStoreGet(key)
    if found: into = v
    found

  proc saveStored*(key, bytes: string): bool =
    nativeStoreSet != nil and nativeStoreSet(key, bytes)

proc persistent*[T](initial: T; key: string): Signal[T] =
  ## A signal holding `initial` the first time, and whatever it last held ever after.
  ## Every change is saved at once. A saved value that no longer fits the type (the app
  ## changed) is ignored.
  var start = initial
  var saved: string
  if loadStored(key, saved):
    var v: T
    var p = 0
    if unpackFrom(saved, p, v) and p == saved.len: start = v
  result = newState(start)
  let s = result
  discard createEffect(proc () =
    var b = ""
    packInto(b, s.get())
    discard saveStored(key, b))
