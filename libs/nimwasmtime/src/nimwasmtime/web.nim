## nimwasmtime on the web (emscripten): the same API the host uses, backed by the browser's own
## WebAssembly instead of wasmtime. The engine is itself wasm there, so an app is a second wasm
## instance beside it: its imports are JS stubs that call back into the engine (`yw_invoke`), and
## its memory is reached by copying (`memRead` / `memWrite`), never by pointer.
##
## Browsers refuse to compile large modules synchronously on the main thread, so the page compiles
## and instantiates every app first (web/engine/yantra.js, `ywPreload`); `compileCached` then just
## picks up that instance by its path.

type
  WasmtimeError* = object of CatchableError
  WasmValkind* = uint8
  WasmValunion* {.union.} = object
    i32*: int32
    i64*: int64
    f32*: float32
    f64*: float64
  WasmVal* = object          ## 16 bytes: kind at 0, value at 8 (web/engine/yantra.js relies on it)
    kind*: WasmValkind
    `of`*: WasmValunion
  WasmCaller* = object
  WasmTrap* = object
  WasmFuncCallback* = proc (env: pointer; caller: ptr WasmCaller; args: ptr WasmVal; nargs: csize_t;
                            results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.}
  WasmFunc* = int32          ## a slot in the host-function table
  WasmExtern* = int32
  WasmMemory* = int32        ## the instance id whose memory it is
  Engine* = ref object
  Store* = ref object
  Module* = ref object
    id*: int32
  Instance* = ref object
    id*: int32

const
  WASM_I32* = 0'u8
  WASM_I64* = 1'u8
  WASM_F32* = 2'u8
  WASM_F64* = 3'u8

{.emit: """/*INCLUDESECTION*/
#include <emscripten.h>
EM_JS(int, yw_take, (const char* key), { return Module.ywTake(UTF8ToString(key)); });
EM_JS(int, yw_import_count, (int id), { return Module.ywApps[id].imports.length; });
EM_JS(int, yw_import_name, (int id, int i, char* buf, int cap), {
  return stringToUTF8(Module.ywApps[id].imports[i].name, buf, cap); });
EM_JS(void, yw_bind, (int id, int i, int slot, int nres, int fmask), {
  const imp = Module.ywApps[id].imports[i]; imp.slot = slot; imp.nres = nres; imp.fmask = fmask; });
EM_JS(int, yw_has_export, (int id, const char* name), {
  return typeof Module.ywApps[id].inst.exports[UTF8ToString(name)] === 'function' ? 1 : 0; });
EM_JS(int, yw_call, (int id, const char* name, int nargs, double a, int* result, char* err, int cap), {
  try {
    const f = Module.ywApps[id].inst.exports[UTF8ToString(name)];
    const r = nargs > 0 ? f(a) : f();
    if (result) HEAP32[result >> 2] = r | 0;
    return 1;
  } catch (e) { stringToUTF8(String(e && e.message || e), err, cap); return 0; }
});
EM_JS(int, yw_mem_size, (int id), { return Module.ywApps[id].inst.exports.memory.buffer.byteLength; });
EM_JS(void, yw_mem_read, (int id, int off, char* dst, int n), {
  HEAPU8.set(new Uint8Array(Module.ywApps[id].inst.exports.memory.buffer, off, n), dst); });
EM_JS(void, yw_mem_write, (int id, int off, const char* src, int n), {
  new Uint8Array(Module.ywApps[id].inst.exports.memory.buffer, off, n).set(HEAPU8.subarray(src, src + n)); });
""".}

proc yw_take(key: cstring): cint {.importc, nodecl.}
proc yw_import_count(id: cint): cint {.importc, nodecl.}
proc yw_import_name(id, i: cint; buf: cstring; cap: cint): cint {.importc, nodecl.}
proc yw_bind(id, i, slot, nres, fmask: cint) {.importc, nodecl.}
proc yw_has_export(id: cint; name: cstring): cint {.importc, nodecl.}
proc yw_call(id: cint; name: cstring; nargs: cint; a: cdouble; res: ptr cint; err: cstring; cap: cint): cint {.importc, nodecl.}
proc yw_mem_size(id: cint): cint {.importc, nodecl.}
proc yw_mem_read(id, off: cint; dst: pointer; n: cint) {.importc, nodecl.}
proc yw_mem_write(id, off: cint; src: pointer; n: cint) {.importc, nodecl.}

var hostFuncs: seq[tuple[cb: WasmFuncCallback; nres, fmask: int]]
  ## fmask: bit k = parameter k is f32

proc yw_invoke(slot: cint; args: ptr WasmVal; nargs: cint; results: ptr WasmVal; nres: cint) {.
    exportc, codegenDecl: "EMSCRIPTEN_KEEPALIVE $# $#$#".} =
  ## Called by an app's import stub (web/engine/yantra.js) with its arguments laid out as WasmVals.
  discard hostFuncs[slot].cb(nil, nil, args, csize_t(nargs), results, csize_t(nres))

proc newEngine*(): Engine = Engine()
proc newStore*(e: Engine): Store = Store()

proc compileCached*(st: Store; bytes: openArray[byte]; cacheDir: string; key = ""): Module =
  ## The instance the page prepared for `key` (the app's path).
  let id = yw_take(key.cstring)
  if id < 0: raise newException(WasmtimeError, "the page did not preload " & key)
  Module(id: id)

proc importNames*(m: Module): seq[string] =
  var buf = newString(256)
  for i in 0 ..< yw_import_count(m.id):
    let n = yw_import_name(m.id, cint(i), buf.cstring, 256)
    result.add buf[0 ..< n]

proc hostFunc*(st: Store; params, results: seq[WasmValkind]; cb: WasmFuncCallback): WasmFunc =
  var mask = 0
  for k, p in params:
    if p == WASM_F32: mask = mask or (1 shl k)
  hostFuncs.add (cb, results.len, mask)
  WasmFunc(hostFuncs.high)

proc externOf*(f: ptr WasmFunc): WasmExtern = f[]

proc instantiateNamed*(m: Module; funcs: seq[WasmFunc]): Instance =
  ## Binds import i to host function funcs[i]; the instance itself already exists.
  for i, f in funcs: yw_bind(m.id, cint(i), f, cint(hostFuncs[f].nres), cint(hostFuncs[f].fmask))
  Instance(id: m.id)

proc getFunc*(inst: Instance; name: string): tuple[f: WasmFunc; ok: bool] =
  (0'i32, yw_has_export(inst.id, name.cstring) == 1)

proc getMemoryExport*(inst: Instance; name: string): tuple[m: WasmMemory; ok: bool] =
  (inst.id, true)

proc call(inst: Instance; name: string; nargs: int; a: float): int32 =
  var err = newString(200)
  var r: cint
  if yw_call(inst.id, name.cstring, cint(nargs), a, addr r, err.cstring, 200) == 0:
    raise newException(WasmtimeError, "trap in " & name & ": " & $err.cstring)
  r

proc callVoid*(inst: Instance; name: string) = discard call(inst, name, 0, 0)
proc callVoidI32*(inst: Instance; name: string; a: int32) = discard call(inst, name, 1, float(a))
proc callVoidF32*(inst: Instance; name: string; a: float32) = discard call(inst, name, 1, float(a))
proc callI32Result*(inst: Instance; name: string): int32 = call(inst, name, 0, 0)

proc memSize*(m: WasmMemory): int = int(yw_mem_size(m))
proc memRead*(m: WasmMemory; off, n: int): string =
  result = newString(n)
  if n > 0: yw_mem_read(m, cint(off), addr result[0], cint(n))
proc memWrite*(m: WasmMemory; off: int; data: string; n: int) =
  if n > 0: yw_mem_write(m, cint(off), unsafeAddr data[0], cint(n))
