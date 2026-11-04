## nimwasmtime — raw C99 bindings for the wasmtime WASM runtime.

import std/[os, strutils]

# WASMTIME C API PATHS — derived, never hardcoded.
#
# These were originally absolute paths to the development machine
# (C:/Users/.../nimwasmtime/vendor/...), which broke the moment the package moved
# — first when it was archived, and again for anyone else cloning it. They are now
# computed from this file's own location at compile time, so the package works
# from any directory.
#
# Two API versions are vendored. The bindings below target the v48 C API (all
# handles opaque), so the newest is preferred; older distributions still work.
const pkgRoot = currentSourcePath().parentDir().parentDir().parentDir()

const osSuffix = when defined(windows): "-windows-c-api"
                 elif defined(macosx): "-macos-c-api"
                 else: "-linux-c-api"   # the GPU machines run Linux

proc pickVendor(): string =
  ## Newest vendored wasmtime C API distribution for this system, deterministically chosen.
  let vend = pkgRoot / "vendor"
  var best = ""
  if dirExists(vend):
    for kind, path in walkDir(vend):
      if kind == pcDir and "wasmtime-" in path.extractFilename and
         path.extractFilename.endsWith(osSuffix):
        if best == "" or path > best:
          best = path
  result = best

const wtVendor = static:
  pickVendor()

const wtInclude* = static:
  if wtVendor.len > 0: (wtVendor / "include")
  else: (pkgRoot / "vendor" / "include")     # fallback when vendored elsewhere

const wtLibDir* = static:
  when defined(windows): pkgRoot / "build"             # the import library made for MinGW
  else: wtVendor / "lib"                               # libwasmtime.so as released

{.passC: "-I" & wtInclude.}
{.passL: "-L" & wtLibDir.}
{.passL: "-lwasmtime".}
when not defined(windows):
  {.passL: "-Wl,-rpath," & wtLibDir.}                  # find libwasmtime.so where it was linked

# Runtime DLL: wasmtime.dll must sit next to the exe (loader app-dir rule).
{.emit: "/*WASMTIME RUNTIME: copy wasmtime.dll next to output*/".}

type
  # v48 API: all handles are OPAQUE and returned as pointers from _new fns.
  WasmEngine* {.importc: "wasm_engine_t", header: "<wasm.h>",
      incompleteStruct.} = object
  WasmStore* {.importc: "wasmtime_store_t", header: "<wasmtime.h>", incompleteStruct.} = object
  WasmModule* {.importc: "wasmtime_module_t", header: "<wasmtime.h>", incompleteStruct.} = object
  WasmInstance* {.importc: "wasmtime_instance_t", header: "<wasmtime.h>", bycopy, incompleteStruct.} = object
  WasmFunc* {.importc: "wasmtime_func_t", header: "<wasmtime.h>", bycopy.} = object
    storeId*: uint64
    index*: csize_t
  WasmTrap* {.importc: "wasm_trap_t", header: "<wasm.h>", incompleteStruct.} = object
  WasmError* {.importc: "wasmtime_error_t", header: "<wasmtime.h>", incompleteStruct.} = object

  WasmByteVec* {.importc: "wasm_byte_vec_t", header: "<wasm.h>", bycopy.} = object
    size*: csize_t
    data*: ptr byte

  WasmValkind* {.importc: "wasmtime_valkind_t", header: "<wasmtime.h>".} = uint8
  WasmValunion* {.importc: "wasmtime_valunion_t", header: "<wasmtime.h>", bycopy.} = object
    i32*: int32
    i64*: int64
    f32*: float32
    f64*: float64

  WasmVal* {.importc: "wasmtime_val_t", header: "<wasmtime.h>", bycopy.} = object
    kind*: WasmValkind
    `of`*: WasmValunion

const
  WASM_I32* = 0'u8
  WASM_I64* = 1'u8
  WASM_F32* = 2'u8
  WASM_F64* = 3'u8
  # wasm.h wasm_externkind_t enum (wabt order, not alphabetical):
  #   WASM_EXTERN_FUNC, WASM_EXTERN_GLOBAL, WASM_EXTERN_TABLE, WASM_EXTERN_MEMORY
  WASM_EXTERN_FUNC*   = 0'u8
  WASM_EXTERN_GLOBAL* = 1'u8
  WASM_EXTERN_TABLE*  = 2'u8
  WASM_EXTERN_MEMORY* = 3'u8

proc wasmByteVecNewEmpty*(v: ptr WasmByteVec) {.importc: "wasm_byte_vec_new_empty",
    header: "<wasm.h>".}
proc wasmByteVecUninit*(v: ptr WasmByteVec; n: csize_t) {.
    importc: "wasm_byte_vec_new_uninitialized", header: "<wasm.h>".}
proc wasmByteVecDelete*(v: ptr WasmByteVec) {.importc: "wasm_byte_vec_delete",
    header: "<wasm.h>".}

proc wat2wasm*(wat: cstring; watLen: csize_t; ret: ptr WasmByteVec): ptr WasmError {.
    importc: "wasmtime_wat2wasm", header: "<wasmtime.h>".}

proc engineNew*(): ptr WasmEngine {.importc: "wasm_engine_new",
    header: "<wasm.h>".}
proc engineDelete*(e: ptr WasmEngine) {.importc: "wasm_engine_delete",
    header: "<wasm.h>".}

proc storeNew*(engine: ptr WasmEngine; data: pointer = nil;
               finalizer: proc (p: pointer) {.cdecl.} = nil): ptr WasmStore {.
    importc: "wasmtime_store_new", header: "<wasmtime.h>".}
proc storeDelete*(st: ptr WasmStore) {.importc: "wasmtime_store_delete",
    header: "<wasmtime.h>".}
proc contextNew*(st: ptr WasmStore): ptr WasmStore {.
    importc: "wasmtime_context_new", header: "<wasmtime.h>".}

# In wasmtime v48, wasmtime_context_t is obtained from a store:
type WasmContext* {.importc: "wasmtime_context_t", header: "<wasmtime.h>",
    incompleteStruct.} = object
proc storeContext*(st: ptr WasmStore): ptr WasmContext {.
    importc: "wasmtime_store_context", header: "<wasmtime.h>".}

proc moduleNew*(engine: ptr WasmEngine; bytes: ptr byte; len: csize_t;
                ret: ptr ptr WasmModule): ptr WasmError {.
    importc: "wasmtime_module_new", header: "<wasmtime.h>".}
proc moduleDelete*(m: ptr WasmModule) {.importc: "wasmtime_module_delete",
    header: "<wasmtime.h>".}

type
  WasmMemory* {.importc: "wasmtime_memory_t", header: "<wasmtime.h>",
      bycopy.} = object
    storeId*: uint64
    index*: csize_t

  WasmExternUnion {.importc: "wasmtime_extern_union_t", header: "<wasmtime.h>",
      bycopy.} = object
    `func`*: WasmFunc
    memory*: WasmMemory

  WasmExtern* {.importc: "wasmtime_extern_t", header: "<wasmtime.h>",
      bycopy.} = object
    kind*: uint8                  # wasmtime_extern_kind_t
    `of`*: WasmExternUnion

proc instanceNew*(ctx: ptr WasmContext; m: ptr WasmModule;
                  imports: ptr WasmExtern; nimports: csize_t;
                  inst: ptr WasmInstance; trap: ptr ptr WasmTrap):
    ptr WasmError {.importc: "wasmtime_instance_new", header: "<wasmtime.h>".}

proc instanceExportGet*(ctx: ptr WasmContext; inst: ptr WasmInstance;
                        name: cstring; nameLen: csize_t;
                        item: ptr WasmExtern): bool {.
    importc: "wasmtime_instance_export_get", header: "<wasmtime.h>".}
proc instanceExportNth*(ctx: ptr WasmContext; inst: ptr WasmInstance;
                        idx: csize_t; name: ptr cstring; nameLen: ptr csize_t;
                        item: ptr WasmExtern): bool {.
    importc: "wasmtime_instance_export_nth", header: "<wasmtime/instance.h>".}

proc funcCall*(ctx: ptr WasmContext; f: ptr WasmFunc;
               args: ptr WasmVal; nargs: csize_t;
               results: ptr WasmVal; nresults: csize_t;
               trap: ptr ptr WasmTrap): ptr WasmError {.
    importc: "wasmtime_func_call", header: "<wasmtime.h>".}

proc errorFormat*(e: ptr WasmError; msg: ptr WasmByteVec) {.
    importc: "wasmtime_error_message", header: "<wasmtime.h>".}
proc errorDelete*(e: ptr WasmError) {.importc: "wasmtime_error_delete",
    header: "<wasmtime.h>".}

# --- host function support (wasm.h + func.h) ---
type
  WasmValtype* {.importc: "wasm_valtype_t", header: "<wasm.h>", incompleteStruct.} = object
  WasmFunctype* {.importc: "wasm_functype_t", header: "<wasm.h>", incompleteStruct.} = object
  WasmValtypeVec* {.importc: "wasm_valtype_vec_t", header: "<wasm.h>", bycopy.} = object
    size*: csize_t
    data*: ptr ptr WasmValtype
  WasmCaller* {.importc: "wasmtime_caller_t", header: "<wasmtime/func.h>", incompleteStruct.} = object

  WasmFuncCallback* = proc(env: pointer; caller: ptr WasmCaller;
      args: ptr WasmVal; nargs: csize_t; results: ptr WasmVal;
      nresults: csize_t): ptr WasmTrap {.cdecl.}  # const-cast in C is compatible

proc valtypeNew*(kind: WasmValkind): ptr WasmValtype {.
    importc: "wasm_valtype_new", header: "<wasm.h>".}
proc valtypeVecNewEmpty*(v: ptr WasmValtypeVec) {.
    importc: "wasm_valtype_vec_new_empty", header: "<wasm.h>".}
proc valtypeVecUninit*(v: ptr WasmValtypeVec; n: csize_t) {.
    importc: "wasm_valtype_vec_new_uninitialized", header: "<wasm.h>".}
proc functypeNew*(params: ptr WasmValtypeVec; results: ptr WasmValtypeVec):
    ptr WasmFunctype {.importc: "wasm_functype_new", header: "<wasm.h>".}

proc wasmtimeFuncNew*(ctx: ptr WasmContext; ftype: ptr WasmFunctype;
                      cb: pointer; env: pointer;
                      finalizer: pointer; ret: ptr WasmFunc) {.
    importc: "wasmtime_func_new", header: "<wasmtime/func.h>".}

# instance needs to ADD an export before instantiation — instead we create
# the host func in the store and pass it as an import at instance_new.
proc externFromFunc*(f: ptr WasmFunc; ext: ptr WasmExtern) {.
    importc: "wasmtime_extern_from_func", header: "<wasmtime/extern.h>".}

# --- trap introspection (verification-phase additions) ---
# NOTE: wasmtime v19 has NO wasmtime_instance_delete - instances live
# inside their store and are freed by wasmtime_store_delete. Recycle
# stores instead of deleting individual instances.
proc wasmTrapMessage*(t: ptr WasmTrap; msg: ptr WasmByteVec) {.
    importc: "wasm_trap_message", header: "<wasm.h>".}
proc wasmTrapDelete*(t: ptr WasmTrap) {.importc: "wasm_trap_delete",
    header: "<wasm.h>".}

# --- linear memory access (network SDK payload scratch) ----------------
const WASMTIME_EXTERN_MEMORY* = 3'u8   # per extern.h in v19

proc wasmtimeMemoryData*(ctx: ptr WasmContext; mem: ptr WasmMemory):
    ptr byte {.importc: "wasmtime_memory_data", header: "<wasmtime.h>".}
proc wasmtimeMemoryDataSize*(ctx: ptr WasmContext; mem: ptr WasmMemory):
    csize_t {.importc: "wasmtime_memory_data_size",
    header: "<wasmtime.h>".}
proc wasmtimeMemorySize*(ctx: ptr WasmContext; mem: ptr WasmMemory):
    uint64 {.importc: "wasmtime_memory_size", header: "<wasmtime.h>".}
proc externFromMemory*(m: WasmMemory; ext: ptr WasmExtern) {.
    importc: "wasmtime_extern_from_memory",
    header: "<wasmtime/extern.h>".}
