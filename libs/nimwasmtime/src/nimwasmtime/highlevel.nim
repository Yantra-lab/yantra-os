## nimwasmtime — high-level WASM runtime: Engine, Store, Module, Instance.
import std/[os, strutils]
import nimwasmtime/raw
export raw

type
  WasmtimeError* = object of CatchableError

  Engine* = ref object
    h: ptr WasmEngine
  Store* = ref object
    h: ptr WasmStore
    ctx*: ptr WasmContext
    engine: Engine
    lastHostFunc*: WasmFunc
  Module* = ref object
    h: ptr WasmModule
    store: Store
  Instance* = ref object
    h*: WasmInstance
    store: Store
    lastHostFunc: WasmFunc

proc rawHandle*(m: Module): ptr WasmModule {.inline.} =
  ## Raw wasmtime module handle (import enumeration etc.).
  m.h

proc rawHandle*(i: Instance): ptr WasmInstance {.inline.} =
  ## Raw wasmtime instance handle.
  addr i.h

proc rawStore*(i: Instance): Store {.inline.} =
  ## The store this instance belongs to.
  i.store

proc rawHandle*(s: Store): ptr WasmContext {.inline.} =
  ## Raw wasmtime store context pointer (needed for funcCall).
  s.ctx

proc rawHandle*(e: Engine): ptr WasmEngine {.inline.} =
  ## Raw wasmtime engine handle. Needed to compile a module from bytes
  ## (wasmtime_module_new takes the engine, not the store, in v48).
  e.h

proc newEngine*(): Engine =
  new(result)
  result.h = engineNew()

# --- trap plumbing: extract the message, ALWAYS free the trap -----------
proc trapMessage*(t: ptr WasmTrap): string =
  ## Copies the human-readable trap text out of wasmtime and frees the
  ## trap object. The pre-verification wrappers raised without deleting
  ## the trap, leaking it on every trapped call.
  if t == nil: return ""
  var msg: WasmByteVec
  wasmTrapMessage(t, addr msg)
  if msg.size > 0:
    result = newString(int(msg.size))
    copyMem(addr result[0], msg.data, int(msg.size))
    wasmByteVecDelete(addr msg)
  wasmTrapDelete(t)

proc close*(e: Engine) =
  ## engineNew() returns memory OWNED BY WASMTIME's allocator; only
  ## wasm_engine_delete may free it. (The old code also called Nim's
  ## dealloc here - a cross-allocator double-free that crashed the
  ## first stress run and is now fixed at the source.)
  if e.h != nil:
    engineDelete(e.h)
    e.h = nil

proc newStore*(engine: Engine): Store =
  new(result)
  result.engine = engine
  result.h = storeNew(engine.h)
  if result.h == nil:
    raise newException(WasmtimeError, "wasmtime_store_new failed")
  result.ctx = storeContext(result.h)

proc compileWat*(st: Store; wat: string): Module =
  ## Compiles WebAssembly Text format directly (wasmtime_wat2wasm + module_new)
  new(result)
  result.store = st
  var wasm: WasmByteVec
  let err = wat2wasm(wat.cstring, csize_t(wat.len), addr wasm)
  if err != nil:
    var msg: WasmByteVec
    errorFormat(err, addr msg)
    var text = newString(msg.size)
    if msg.size > 0: copyMem(addr text[0], msg.data, msg.size)
    wasmByteVecDelete(addr msg)
    errorDelete(err)
    raise newException(WasmtimeError, "wat2wasm: " & text)
  defer: wasmByteVecDelete(addr wasm)
  var modPtr: ptr WasmModule
  let err2 = moduleNew(st.engine.h, wasm.data, wasm.size, addr modPtr)
  if err2 != nil:
    var msg: WasmByteVec
    errorFormat(err2, addr msg)
    var text = newString(msg.size)
    if msg.size > 0: copyMem(addr text[0], msg.data, msg.size)
    wasmByteVecDelete(addr msg)
    errorDelete(err2)
    raise newException(WasmtimeError, "module_new: " & text)
  result.h = modPtr

proc compileBytes*(st: Store; bytes: openArray[byte]): Module =
  ## Compiles a BINARY WebAssembly module (a .wasm file). compileWat() goes via
  ## the text format; shipping apps are binaries, so this is the path the host
  ## uses. Kept separate because wat2wasm would reject binary input.
  if bytes.len == 0:
    raise newException(WasmtimeError, "compileBytes: empty module")
  new(result)
  result.store = st
  var modPtr: ptr WasmModule = nil
  let err = moduleNew(st.engine.h, cast[ptr byte](unsafeAddr bytes[0]),
                      csize_t(bytes.len), addr modPtr)
  if err != nil:
    var msg: WasmByteVec
    errorFormat(err, addr msg)
    var text = newString(int(msg.size))
    if msg.size > 0: copyMem(addr text[0], msg.data, msg.size)
    wasmByteVecDelete(addr msg)
    errorDelete(err)
    raise newException(WasmtimeError, "module_new: " & text)
  result.h = modPtr

proc moduleSerialize(m: ptr WasmModule; ret: ptr WasmByteVec): ptr WasmError {.
    importc: "wasmtime_module_serialize", header: "<wasmtime.h>".}
proc moduleDeserialize(engine: ptr WasmEngine; bytes: ptr byte; len: csize_t;
                       ret: ptr ptr WasmModule): ptr WasmError {.
    importc: "wasmtime_module_deserialize", header: "<wasmtime.h>".}

proc errorText(err: ptr WasmError): string =
  var msg: WasmByteVec
  errorFormat(err, addr msg)
  result = newString(int(msg.size))
  if msg.size > 0: copyMem(addr result[0], msg.data, msg.size)
  wasmByteVecDelete(addr msg)
  errorDelete(err)

proc serialize*(m: Module): string =
  ## The module compiled to machine code, as bytes `loadCompiled` takes back (same
  ## wasmtime version and settings only).
  var v: WasmByteVec
  let err = moduleSerialize(m.h, addr v)
  if err != nil: raise newException(WasmtimeError, "module_serialize: " & errorText(err))
  result = newString(int(v.size))
  if v.size > 0: copyMem(addr result[0], v.data, v.size)
  wasmByteVecDelete(addr v)

proc loadCompiled*(st: Store; bytes: string): Module =
  ## A module from `serialize`d bytes: no compiling. Only for bytes this program wrote
  ## itself — wasmtime trusts them as machine code.
  if bytes.len == 0: raise newException(WasmtimeError, "loadCompiled: empty")
  new(result)
  result.store = st
  var modPtr: ptr WasmModule = nil
  let err = moduleDeserialize(st.engine.h, cast[ptr byte](unsafeAddr bytes[0]), csize_t(bytes.len), addr modPtr)
  if err != nil: raise newException(WasmtimeError, "module_deserialize: " & errorText(err))
  result.h = modPtr

proc cacheKey*(bytes: openArray[byte]): string =
  ## A file name for a module's compiled form: FNV-1a over its bytes, its length and the
  ## wasmtime release, so a changed app or a new wasmtime never reuses old machine code.
  var h = 0xcbf29ce484222325'u64
  for b in bytes:
    h = (h xor uint64(b)) * 0x100000001b3'u64
  "wt48-" & $bytes.len & "-" & h.toHex.toLowerAscii

proc compileCached*(st: Store; bytes: openArray[byte]; cacheDir: string): Module =
  ## `compileBytes`, but each distinct module is compiled once: later loads take its
  ## machine code from `cacheDir` (milliseconds instead of hundreds). A missing, stale or
  ## damaged cache entry just means compiling again. "" = no cache.
  if cacheDir.len == 0: return st.compileBytes(bytes)
  let path = cacheDir / cacheKey(bytes) & ".cwasm"
  if fileExists(path):
    try:
      return st.loadCompiled(readFile(path))
    except CatchableError:
      discard tryRemoveFile(path)             # damaged or from an incompatible build: recompile
  result = st.compileBytes(bytes)
  try:
    createDir(cacheDir)
    writeFile(path & ".tmp", result.serialize)
    moveFile(path & ".tmp", path)             # never leave a half-written entry
  except CatchableError:
    discard tryRemoveFile(path & ".tmp")     # a read-only cache is fine: it just stays cold

proc instantiate*(m: Module): Instance =
  ## Instantiates with zero imports.
  new(result)
  result.store = m.store
  var trap: ptr WasmTrap = nil
  let err = instanceNew(m.store.ctx, m.h, nil, 0, addr result.h, addr trap)
  if err != nil:
    var msg: WasmByteVec
    errorFormat(err, addr msg)
    var text = newString(msg.size)
    if msg.size > 0: copyMem(addr text[0], msg.data, msg.size)
    wasmByteVecDelete(addr msg)
    errorDelete(err)
    raise newException(WasmtimeError, "instance_new: " & text)

proc getFunc*(inst: Instance; name: string): tuple[f: WasmFunc; ok: bool] =
  var ext: WasmExtern
  let found = instanceExportGet(inst.store.ctx, addr inst.h,
                                name.cstring, csize_t(name.len), addr ext)
  return (ext.`of`.`func`, found)

proc getMemoryExport*(inst: Instance; name: string): tuple[m: WasmMemory; ok: bool] =
  var ext: WasmExtern
  let found = instanceExportGet(inst.store.ctx, addr inst.h,
                                name.cstring, csize_t(name.len), addr ext)
  return (ext.`of`.memory, found and ext.kind == WASM_EXTERN_MEMORY)

proc getFuncPtr*(inst: Instance; name: string): ptr WasmFunc =
  ## Returns a pointer to the exported function's WasmFunc struct.
  ## Uses a temporary lastHostFunc field on the instance.
  var ext: WasmExtern
  let found = instanceExportGet(inst.store.ctx, addr inst.h,
                                name.cstring, csize_t(name.len), addr ext)
  if not found:
    return nil
  inst.lastHostFunc = ext.of.func
  result = addr inst.lastHostFunc

proc readMemBytes*(inst: Instance; name: string; offset, n: int): seq[uint8] =
  ## Reads `n` raw bytes from the named exported memory starting at `offset`.
  ## Returns a seq[uint8] of length `n`. Used by t_memory_bridge to
  ## verify WASM can write a string into linear memory that Nim then
  ## reads back out.
  let (mem, ok) = inst.getMemoryExport(name)
  if not ok:
    raise newException(WasmtimeError, "memory not exported: " & name)
  let dataPtr = wasmtimeMemoryData(inst.store.ctx, addr mem)
  if dataPtr == nil:
    raise newException(WasmtimeError, "memory data null")
  let totalSize = wasmtimeMemoryDataSize(inst.store.ctx, addr mem)
  if csize_t(offset + n) > totalSize:
    raise newException(WasmtimeError, "memory read OOB")
  result = newSeq[uint8](n)
  copyMem(addr result[0], cast[pointer](cast[int](dataPtr) + offset), n)

proc readMemString*(inst: Instance; name: string; offset, n: int): string =
  ## Reads `n` bytes as a UTF-8 string from the named exported memory.
  let raw = inst.readMemBytes(name, offset, n)
  result = newString(n)
  copyMem(addr result[0], addr raw[0], n)

proc callI32I32ToI32*(inst: Instance; name: string; a, b: int32): int32 =
  ## Calls an exported (i32, i32) -> i32 function. Raises on trap/missing.
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var args: array[2, WasmVal]
  args[0] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: a))
  args[1] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: b))
  var res: WasmVal
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, addr args[0], 2, addr res, 1,
                     addr trap)
  if err != nil:
    errorDelete(err)
    raise newException(WasmtimeError, "func_call failed")
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))
  doAssert res.kind == WASM_I32
  result = res.`of`.i32

proc raiseWtError*(prefix: string; e: ptr WasmError) {.noinline.} =
  ## Formats a wasmtime_error_t into the exception message and deletes it.
  if e == nil:
    raise newException(WasmtimeError, prefix)
  var msg: WasmByteVec
  errorFormat(e, addr msg)
  var text = ""
  if msg.size > 0:
    text = newString(int(msg.size))
    copyMem(addr text[0], msg.data, int(msg.size))
    wasmByteVecDelete(addr msg)
  errorDelete(e)
  raise newException(WasmtimeError, prefix & ": " & text)

proc callI32Result*(inst: Instance; name: string): int32 =
  ## Calls an exported () -> i32 function (trap-propagation probes).
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var res: WasmVal
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, nil, 0, addr res, 1, addr trap)
  if err != nil:
    raiseWtError("func_call failed", err)
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))
  doAssert res.kind == WASM_I32
  result = res.`of`.i32

proc callI64I64ToI64*(inst: Instance; name: string; a, b: int64): int64 =
  ## Calls an exported (i64, i64) -> i64 function (official gcd.c port).
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var args: array[2, WasmVal]
  args[0] = WasmVal(kind: WASM_I64, `of`: WasmValunion(i64: a))
  args[1] = WasmVal(kind: WASM_I64, `of`: WasmValunion(i64: b))
  var res: WasmVal
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, addr args[0], 2, addr res, 1,
                     addr trap)
  if err != nil:
    errorDelete(err)
    raise newException(WasmtimeError, "func_call failed")
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))
  doAssert res.kind == WASM_I64
  result = res.`of`.i64

proc setVecKind*(v: ptr WasmValtypeVec; i: int; kind: WasmValkind) =
  cast[ptr UncheckedArray[ptr WasmValtype]](v.data)[i] = valtypeNew(kind)

proc setI32*(v: ptr WasmValtypeVec; i: int) = setVecKind(v, i, WASM_I32)

proc setKind*(v: ptr WasmValtypeVec; i: int; kind: WasmValkind) =
  setVecKind(v, i, kind)

proc registerHostFuncTyped*(st: Store; name: string;
    cb: raw.WasmFuncCallback; params, results: ptr WasmValtypeVec): WasmFunc =
  ## Registers a host function with an explicit signature; returns the func
  ## (wrap with externOf to get an import extern).
  let ftype = functypeNew(params, results)
  wasmtimeFuncNew(st.ctx, ftype, cb, nil, nil, addr st.lastHostFunc)
  st.lastHostFunc

proc registerHostFunc*(st: Store; name: string;
                       cb: raw.WasmFuncCallback): WasmFunc =
  ## Creates a host function (i32,i32,i32)->() in this store and returns it.
  ## The returned func can be turned into an extern and passed as an import.
  var params: WasmValtypeVec
  valtypeVecUninit(addr params, 3)
  cast[ptr UncheckedArray[ptr WasmValtype]](params.data)[0] = valtypeNew(WASM_I32)
  cast[ptr UncheckedArray[ptr WasmValtype]](params.data)[1] = valtypeNew(WASM_I32)
  cast[ptr UncheckedArray[ptr WasmValtype]](params.data)[2] = valtypeNew(WASM_I32)
  var resultsV: WasmValtypeVec
  valtypeVecNewEmpty(addr resultsV)
  let ftype = functypeNew(addr params, addr resultsV)
  wasmtimeFuncNew(st.ctx, ftype, cb, nil, nil, addr result)
  st.lastHostFunc = result

proc externOf*(f: ptr WasmFunc): WasmExtern =
  ## v19 has no extern_from_func; build the tagged union by hand
  ## (WASMTIME_EXTERN_FUNC == 0, func is the first union member).
  result.kind = 0
  result.`of`.`func` = f[]

proc instantiateWithImports*(m: Module; imports: ptr WasmExtern;
                             n: csize_t): Instance =
  new(result)
  result.store = m.store
  var trap: ptr WasmTrap = nil
  let err = instanceNew(m.store.ctx, m.h, imports, n,
                        addr result.h, addr trap)
  if err != nil:
    var msg: WasmByteVec
    errorFormat(err, addr msg)
    var text = newString(int(msg.size))
    if msg.size > 0: copyMem(addr text[0], msg.data, msg.size)
    wasmByteVecDelete(addr msg)
    errorDelete(err)
    raise newException(WasmtimeError, "instance_new: " & text)

proc callVoid*(inst: Instance; name: string) =
  ## Calls an exported () -> () function.
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, nil, 0, nil, 0, addr trap)
  if err != nil: errorDelete(err)
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))

proc attachStore*(m: Module; st: Store) =
  ## Rebinds a compiled module to a fresh store. v19 modules are
  ## engine-owned, so they survive store recycling; instantiation
  ## always runs against the bound store's context.
  m.store = st

proc externOfMemory*(m: WasmMemory): WasmExtern =
  ## Builds the tagged extern union for a memory (kind=2, memory is the
  ## second union member in v19's layout).
  result.kind = WASMTIME_EXTERN_MEMORY
  result.`of`.memory = m

proc getMemory*(inst: Instance; name = "memory"): tuple[m: WasmMemory;
    ok: bool] =
  var ext: WasmExtern
  let found = instanceExportGet(inst.store.ctx, addr inst.h,
                                name.cstring, csize_t(name.len),
                                addr ext)
  if found and ext.kind == WASMTIME_EXTERN_MEMORY:
    return (ext.`of`.memory, true)
  return (default(WasmMemory), false)

proc memoryBase*(inst: Instance; m: WasmMemory): ptr byte {.inline.} =
  wasmtimeMemoryData(inst.store.ctx, addr m)

proc memoryBytes*(inst: Instance; m: WasmMemory): int {.inline.} =
  ## Byte length of linear memory (NOT pages - wasmtime_memory_size
  ## returns page units; data_size is the byte-accurate accessor).
  int(wasmtimeMemoryDataSize(inst.store.ctx, addr m))

proc callVoidI32*(inst: Instance; name: string; a: int32) =
  ## Calls an exported (i32) -> () function.
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var args: array[1, WasmVal]
  args[0] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: a))
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, addr args[0], 1, nil, 0,
                     addr trap)
  if err != nil:
    raiseWtError("func_call failed", err)
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))

proc callVoidF32*(inst: Instance; name: string; a: float32) =
  ## Calls an exported (f32) -> () function. Added for shadow_studio's
  ## on_tick(dt) contract (same shape as callVoidI32).
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var args: array[1, WasmVal]
  args[0] = WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: a))
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, addr args[0], 1, nil, 0,
                     addr trap)
  if err != nil:
    raiseWtError("func_call failed", err)
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))

proc callVoidI32x4*(inst: Instance; name: string; a, b, c, d: int32) =
  ## Calls an exported (i32,i32,i32,i32) -> () function.
  let (f, ok) = inst.getFunc(name)
  if not ok:
    raise newException(WasmtimeError, "export not found: " & name)
  var args: array[4, WasmVal]
  args[0] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: a))
  args[1] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: b))
  args[2] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: c))
  args[3] = WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: d))
  var trap: ptr WasmTrap = nil
  let err = funcCall(inst.store.ctx, addr f, addr args[0], 4, nil, 0,
                     addr trap)
  if err != nil:
    raiseWtError("func_call failed", err)
  if trap != nil:
    raise newException(WasmtimeError,
        "trap in " & name & ": " & trapMessage(trap))

proc deleteInstance*(inst: Instance) =
  ## v19 owns instances inside their store: there is no
  ## wasmtime_instance_delete. To bound memory in long loops, recycle
  ## the whole store (Store.close + newStore) instead.
  discard

proc close*(st: Store) =
  ## Deletes the store (also invalidates its instances/functions).
  if st.h != nil:
    storeDelete(st.h)
    st.h = nil

proc close*(m: Module) =
  ## Deletes the compiled module.
  if m.h != nil:
    moduleDelete(m.h)
    m.h = nil
