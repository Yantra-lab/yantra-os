## Yantra host — loads a WebAssembly app module and runs it.
##
## This is the engine side of the contract in sdk/yantra.nim. It:
##   1. loads an app .wasm produced by tools/build-wasm.sh
##   2. enumerates the module's imports and supplies them (positionally, which is
##      what wasmtime's C API requires)
##   3. calls the app's `yantra_main` export
##   4. collects the UI tree it builds, by CALLBACK
##   5. can dispatch events back into the sandbox
##
## Everything the sandbox can do is listed in the `imports` table below. That is
## the security boundary: an app that tries to call anything else fails to
## instantiate, because the host does not provide it.

import std/[os, strformat, strutils, tables, sequtils, sets, times, json, math]
when defined(emscripten):
  import nimwasmtime/web
else:
  import nimwasmtime
  import nimwasmtime/raw
import tree
import wasmmath
import netrules
export netrules
export tree
import ../render/api
from ../protocol/wire import P_NET
export api


# ===========================================================================
# Additional wasm-c-api bindings.
#
# nimwasmtime does not yet expose module-import enumeration, and the host needs
# it: wasmtime's C API matches imports POSITIONALLY, so the host must ask the
# module what its imports are, in order, rather than assuming. `wasm_name_t` is a
# typedef of `wasm_byte_vec_t` (wasm.h:104), which raw.nim already binds, so only
# the type and two accessors are new.
# ===========================================================================

when not defined(emscripten):
  type
    WasmImporttype* {.importc: "wasm_importtype_t", header: "<wasm.h>",
        incompleteStruct.} = object
    WasmImporttypeVec* {.importc: "wasm_importtype_vec_t", header: "<wasm.h>",
        bycopy.} = object
      size*: csize_t
      data*: ptr ptr WasmImporttype

  # NOTE on the `pointer` parameter below (this is subtle and cost a build):
  # `wasm_module_imports` is wasm-c-api and takes `const wasm_module_t*`, while the
  # module we hold is a `wasmtime_module_t*` — different C types, so strict GCC
  # rejects the call outright. It is still correct: in wasmtime's implementation
  # `wasm_module_t` is either a typedef of `wasmtime_module_t` (identical type) or a
  # wrapper whose module is the first field (offset 0, identical address). Taking
  # `pointer` lets the implicit void* conversion through, and the host PROVES the
  # assumption at runtime by checking the enumerated names against the import table
  # — a wrong pointer would yield garbage names, not a silent pass.
  proc wasmModuleImports*(m: pointer; outp: ptr WasmImporttypeVec) {.
      importc: "wasm_module_imports", header: "<wasm.h>".}
  proc wasmImporttypeName*(t: ptr WasmImporttype): ptr WasmByteVec {.
      importc: "wasm_importtype_name", header: "<wasm.h>".}
  proc wasmImporttypeModule*(t: ptr WasmImporttype): ptr WasmByteVec {.
      importc: "wasm_importtype_module", header: "<wasm.h>".}

# ===========================================================================
# The node tree type now lives in tree.nim — a dependency-free module so the
# translation logic can be tested with neither wasmtime nor Qt. Re-exported
# above, so `import host` still gives callers Node/HostState.
# ===========================================================================

# Globals: one instance at a time. The memory base is re-read per callback (see
# readStr) because the sandbox's bump allocator can grow linear memory, which
# may move it.
# Per OS thread (Q7): a worker instance runs on its own thread with its own store, so the
# "current app" these callbacks read is thread-local.
var
  store {.threadvar.}: Store
  memExport {.threadvar.}: WasmMemory
  memReady {.threadvar.}: bool
  host {.threadvar.}: HostState
  currentCaps {.threadvar.}: HashSet[string]

when defined(emscripten):
  proc memTotal(): int = memSize(memExport)
  proc memCopyOut(p, n: int): string = memRead(memExport, p, n)
  proc memCopyIn(p: int; data: string; n: int) = memWrite(memExport, p, data, n)
else:
  proc memTotal(): int = int(wasmtimeMemoryDataSize(store.ctx, addr memExport))
  proc memCopyOut(p, n: int): string =
    result = newString(n)
    let base = wasmtimeMemoryData(store.ctx, addr memExport)
    copyMem(addr result[0], cast[pointer](cast[uint](base) + uint(p)), n)
  proc memCopyIn(p: int; data: string; n: int) =
    let base = wasmtimeMemoryData(store.ctx, addr memExport)
    copyMem(cast[pointer](cast[uint](base) + uint(p)), unsafeAddr data[0], n)

proc readStr(p: int32; n: int32): string =
  ## Copy `n` bytes out of the sandbox at offset `p`. The bytes are copied
  ## immediately; nothing is retained on the wasm side, so there is no ownership
  ## puzzle. Bounds are checked against the CURRENT memory size.
  if not memReady or p <= 0 or n <= 0: return ""
  if p < 0 or int(p) + int(n) > memTotal(): return ""
  memCopyOut(int(p), int(n))

# ===========================================================================
# Host callbacks. Signature is wasmtime's wasm_func_callback_t.
# ===========================================================================

proc argAt(args: ptr WasmVal; i: int): WasmVal {.inline.} =
  cast[ptr UncheckedArray[WasmVal]](args)[i]

proc setResult(results: ptr WasmVal; i: int; v: WasmVal) {.inline.} =
  cast[ptr UncheckedArray[WasmVal]](results)[i] = v

proc i32Val(v: int32): WasmVal {.inline.} =
  WasmVal(kind: WASM_I32, `of`: WasmValunion(i32: v))

proc cbCreate(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_create(kind: i32) -> i32
  let kind = argAt(args, 0).`of`.i32
  setResult(results, 0, i32Val(host.createNode(kind)))
  nil

proc cbChild(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_child(parent: i32, child: i32)
  host.appendChild(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  nil

proc cbInsert(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_insert(parent: i32, child: i32, before: i32)
  host.insertBefore(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32)
  nil

proc cbRemove(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_remove(node: i32)
  host.removeNode(argAt(args, 0).`of`.i32)
  nil

proc writeStr(p: int32; data: string; cap: int32) =
  ## Copies up to `cap` bytes of `data` into the sandbox at offset `p`, bounds-checked.
  if not memReady or p <= 0 or cap <= 0 or data.len == 0: return
  let n = min(int(cap), data.len)
  if int(p) + n > memTotal(): return
  memCopyIn(int(p), data, n)

proc cbGetStr(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_get_str(node: i32, prop: i32, buf: i32, cap: i32) -> i32 (full length)
  let node = argAt(args, 0).`of`.i32
  let prop = argAt(args, 1).`of`.i32
  var v = ""
  if host.valid(node): v = host.nodes[int(node)].sProp(prop)
  writeStr(argAt(args, 2).`of`.i32, v, argAt(args, 3).`of`.i32)
  setResult(results, 0, i32Val(int32(v.len)))
  nil

proc cbSetI32(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_set_i32(node: i32, prop: i32, value: i32)
  let node = argAt(args, 0).`of`.i32
  let prop = argAt(args, 1).`of`.i32
  let value = argAt(args, 2).`of`.i32
  host.setProp(node, prop, Value(kind: vkInt, i: value))
  nil

proc cbSetF32(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_set_f32(node: i32, prop: i32, value: f32)
  let node = argAt(args, 0).`of`.i32
  let prop = argAt(args, 1).`of`.i32
  let value = argAt(args, 2).`of`.f32
  host.setProp(node, prop, Value(kind: vkFloat, f: value))
  nil

proc cbSetStr(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_set_str(node: i32, prop: i32, data: i32, len: i32)
  let node = argAt(args, 0).`of`.i32
  let prop = argAt(args, 1).`of`.i32
  let data = argAt(args, 2).`of`.i32
  let len = argAt(args, 3).`of`.i32
  when defined(yantraTraceStr):
    echo "set_str node=", node, " prop=", prop, " ptr=", data, " len=", len, " -> '", readStr(data, len), "'"
  host.setProp(node, prop, Value(kind: vkString, s: readStr(data, len)))
  nil

var g_frameDt {.threadvar.}: float32

proc cbGetDt(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## yantra_get_dt() -> f32
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: g_frameDt)))
  nil

proc cbOn(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_on(node: i32, event: i32, handler: i32)
  let node = argAt(args, 0).`of`.i32
  let event = argAt(args, 1).`of`.i32
  let handler = argAt(args, 2).`of`.i32
  if host.valid(node):
    host.handlers[node] = handler
    host.events[(node, event)] = handler
  nil

proc cbAfter(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_after(ms: i32, handler: i32) — run `handler` once, `ms` from now on the engine's clock.
  host.timers.add (max(argAt(args, 0).`of`.i32, 0'i32), argAt(args, 1).`of`.i32)
  nil

# --- storage: each app's own saved values (N1) -------------------------------------------

const
  storeMaxValue* = 1 shl 20            ## one value: 1 MB
  storeMaxTotal* = 16 shl 20           ## one app, all values: 16 MB

proc dataDir*(): string =
  ## Where apps keep what they save, one folder each. YANTRA_DATA moves it.
  if getEnv("YANTRA_DATA").len > 0: getEnv("YANTRA_DATA") else: getDataDir() / "yantra" / "data"

proc validStoreKey*(k: string): bool =
  k.len > 0 and k.len <= 128 and k.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}) and k[0] != '.'

proc storePath(app, key: string): string = dataDir() / app / key & ".bin"

proc storeGet*(app, key: string): (bool, string) =
  ## The value an app saved under `key`, if any.
  if not validStoreKey(key) or not validStoreKey(app): return (false, "")
  let p = storePath(app, key)
  if not fileExists(p): return (false, "")
  try: (true, readFile(p)) except IOError: (false, "")

proc storeSet*(app, key, value: string): bool =
  ## Saves a value for an app — only inside its own folder, within its quota, written whole
  ## or not at all.
  if not validStoreKey(key) or not validStoreKey(app) or value.len > storeMaxValue: return false
  let dir = dataDir() / app
  var total = value.len
  if dirExists(dir):
    for f in walkFiles(dir / "*.bin"):
      if f != storePath(app, key): total += int(getFileSize(f))
  if total > storeMaxTotal: return false
  try:
    createDir(dir)
    let p = storePath(app, key)
    writeFile(p & ".tmp", value)
    moveFile(p & ".tmp", p)
    true
  except CatchableError:
    false

proc cbStoreGet(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_store_get(key: i32, keyLen: i32, buf: i32, cap: i32) -> i32: the value's full length
  ## (-1 if none), copying up to `cap` bytes into the app's memory at `buf`.
  let key = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let (found, v) = storeGet(host.appName, key)
  if found and argAt(args, 3).`of`.i32 > 0: writeStr(argAt(args, 2).`of`.i32, v, argAt(args, 3).`of`.i32)
  setResult(results, 0, i32Val(if found: int32(v.len) else: -1'i32))
  nil

proc cbStoreSet(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_store_set(key: i32, keyLen: i32, val: i32, valLen: i32) -> i32: 1 saved, 0 refused.
  let key = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let n = argAt(args, 3).`of`.i32
  let v = if n > 0: readStr(argAt(args, 2).`of`.i32, n) else: ""
  setResult(results, 0, i32Val(if n >= 0 and v.len == n and storeSet(host.appName, key, v): 1'i32 else: 0'i32))
  nil

# --- network (F1): fetches only to the hosts the app's window lists ------------------------

const fetchMaxPending* = 16

proc windowNet(): string =
  if host.nodes.len > 0 and host.nodes[0].alive and P_NET in host.nodes[0].props:
    let v = host.nodes[0].props[P_NET]
    if v.kind == vkString: return v.s

proc cbFetch(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_fetch(url: i32, urlLen: i32, handler: i32) -> i32: the request's id, 0 if refused
  ## (host not in the window's `net` list, not https, or too many at once). `handler` runs
  ## once when the answer is in; y_fetch_status / y_fetch_body read it then.
  let url = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  var id = 0'i32
  if netAllowed(windowNet(), url) and host.fetchQueue.len < fetchMaxPending:
    inc host.nextFetch
    id = host.nextFetch
    host.fetchQueue.add FetchReq(id: id, meth: "GET", url: url, handler: argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(id))
  nil

const
  fetchMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]
  hostOnlyHeaders = ["host", "content-length", "transfer-encoding", "connection", "upgrade"]
  wsMaxOpen* = 8

proc parseRequest*(req: string): (bool, FetchReq) =
  ## "METHOD\nURL\nName: value\n…\n\nBODY" as the SDK writes it; false if malformed, a
  ## method we do not send, or a header only the host may set.
  let lines = req.split('\n')
  if lines.len < 2 or lines[0] notin fetchMethods: return
  var r = FetchReq(meth: lines[0], url: lines[1])
  var i = 2
  while i < lines.len and lines[i].len > 0:
    let k = lines[i].find(':')
    if k <= 0 or lines[i].contains('\r') or lines[i][0 ..< k].strip.toLowerAscii in hostOnlyHeaders: return
    r.headers.add lines[i]
    inc i
  if i < lines.len: r.body = lines[i + 1 .. ^1].join("\n")
  (true, r)

proc cbFetchEx(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_fetch_ex(req: i32, reqLen: i32, handler: i32) -> i32: like y_fetch, with a method,
  ## headers and a body (parseRequest). 0 if refused.
  let (ok, r) = parseRequest(readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32))
  var id = 0'i32
  if ok and netAllowed(windowNet(), r.url) and host.fetchQueue.len < fetchMaxPending:
    inc host.nextFetch
    id = host.nextFetch
    var q = r
    q.id = id
    q.handler = argAt(args, 2).`of`.i32
    host.fetchQueue.add q
  setResult(results, 0, i32Val(id))
  nil

# ---- the system (y_sys): for the desktop's control centre --------------------------------------
when defined(windows):
  {.compile: "sys_win.c".}
  {.passL: "-lole32 -liphlpapi -lwlanapi -ladvapi32".}
else:
  {.compile: "sys_linux.c".}
proc ysys_battery(): cint {.importc, cdecl.}
proc ysys_charging(): cint {.importc, cdecl.}
proc ysys_volume(): cint {.importc, cdecl.}
proc ysys_set_volume(pct: cint): cint {.importc, cdecl.}
proc ysys_muted(): cint {.importc, cdecl.}
proc ysys_set_muted(on: cint): cint {.importc, cdecl.}
proc ysys_network(): cint {.importc, cdecl.}
proc ysys_wifi_name(buf: cstring; cap: cint): cint {.importc, cdecl.}
proc ysys_uptime(): cint {.importc, cdecl.}
proc ysys_cpu(): cint {.importc, cdecl.}
proc ysys_memory(): cint {.importc, cdecl.}
proc ysys_disk(): cint {.importc, cdecl.}
proc ysys_user(buf: cstring; cap: cint): cint {.importc, cdecl.}
proc ysys_host(buf: cstring; cap: cint): cint {.importc, cdecl.}
proc ysys_os(buf: cstring; cap: cint): cint {.importc, cdecl.}

const sysTextMax* = 128
  ## How much of a text the C shim will ever write (battery/volume have no text; a name is
  ## shorter than this). One byte over: the shims NUL-terminate, so the buffer needs a spare.

proc cbSys(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_sys(op: i32, arg: i32) -> i32, for an app with the `system` grant (else -1): 1 battery
  ## percent, 2 on mains power (1/0), 3 volume 0-100, 4 set the volume to `arg`, 5 muted (1/0),
  ## 6 mute (`arg` 1) or unmute, 7 network: 0 offline, 1 wired, 2 Wi-Fi, 8 seconds since the
  ## machine started, 9 CPU use %, 10 memory in use %, 11 the system disk's use %. -1: not known.
  let arg = argAt(args, 1).`of`.i32
  let v = if "system" notin currentCaps: -1'i32
          else:
            case argAt(args, 0).`of`.i32
            of 1: int32(ysys_battery())
            of 2: int32(ysys_charging())
            of 3: int32(ysys_volume())
            of 4: int32(ysys_set_volume(cint(arg)))
            of 5: int32(ysys_muted())
            of 6: int32(ysys_set_muted(cint(arg)))
            of 7: int32(ysys_network())
            of 8: int32(ysys_uptime())
            of 9: int32(ysys_cpu())
            of 10: int32(ysys_memory())
            of 11: int32(ysys_disk())
            else: -1'i32
  setResult(results, 0, i32Val(v))
  nil

proc cbSysText(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_sys_text(op: i32, buf: i32, cap: i32) -> i32: a text about the system, its length (-1 if
  ## not known), copying up to `cap` bytes to `buf`. 1: the Wi-Fi network's name, 2: the user's
  ## name, 3: the computer's name, 4: the system's name.
  var n = -1'i32
  let op = argAt(args, 0).`of`.i32
  if "system" in currentCaps and op in 1'i32 .. 4'i32:
    # +1 so the shim's NUL terminator lands inside our own allocation, not past its end.
    var name = newString(sysTextMax + 1)
    let k = case op
            of 1: ysys_wifi_name(cstring(name), sysTextMax)
            of 2: ysys_user(cstring(name), sysTextMax)
            of 3: ysys_host(cstring(name), sysTextMax)
            else: ysys_os(cstring(name), sysTextMax)
    if k >= 0:
      name.setLen(k)
      n = int32(k)
      if argAt(args, 2).`of`.i32 > 0: writeStr(argAt(args, 1).`of`.i32, name, argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(n))
  nil

# ---- the model (y_ai): the host holds the key, the app never sees it ---------------------------

proc aiBackend*(): int32 =
  ## Which model answers `y_ai`: 2 a local OpenAI-compatible server (YANTRA_AI_URL), 1 Claude
  ## (ANTHROPIC_API_KEY, read from the environment and never stored), 0 none.
  if getEnv("YANTRA_AI_URL").len > 0: 2'i32
  elif getEnv("ANTHROPIC_API_KEY").len > 0: 1'i32
  else: 0'i32

proc cbAiReady(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ai_ready() -> i32: aiBackend() for an app with the `ai` grant, else 0. Honest: a machine
  ## with no model set up reads 0, so an app hides its agent rather than offering a dead button.
  setResult(results, 0, i32Val(if "ai" in currentCaps: aiBackend() else: 0'i32))
  nil

proc cbAi(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ai(req: i32, reqLen: i32, handler: i32) -> i32: asks the model. `req` is JSON
  ## {system, messages: [{role, content}], max_tokens}; the host adds the model and the key (the
  ## app never sees it) and queues it like a fetch: y_fetch_status / y_fetch_body read the
  ## answer in `handler`. 0 if refused: no `ai` grant, no model set up, or too many requests.
  var id = 0'i32
  let backend = aiBackend()
  if "ai" in currentCaps and backend > 0 and host.fetchQueue.len < fetchMaxPending:
    try:
      let j = parseJson(readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32))
      var q = FetchReq(meth: "POST", handler: argAt(args, 2).`of`.i32)
      if backend == 2:                       # a local server: the OpenAI chat shape
        var msgs = newJArray()
        if j{"system"}.getStr.len > 0: msgs.add %*{"role": "system", "content": j["system"].getStr}
        for m in j{"messages"}: msgs.add m
        q.url = getEnv("YANTRA_AI_URL")
        q.headers = @["content-type: application/json"]
        q.body = $(%*{"model": getEnv("YANTRA_MODEL", "local"), "messages": msgs,
                      "max_tokens": j{"max_tokens"}.getInt(1024)})
      else:
        var body = j
        body["model"] = %getEnv("YANTRA_MODEL", "claude-sonnet-5")
        q.url = "https://api.anthropic.com/v1/messages"
        q.headers = @["x-api-key: " & getEnv("ANTHROPIC_API_KEY"),
                      "anthropic-version: 2023-06-01",
                      "content-type: application/json"]
        q.body = $body
      inc host.nextFetch
      id = host.nextFetch
      q.id = id
      host.fetchQueue.add q
    except CatchableError:
      id = 0
  setResult(results, 0, i32Val(id))
  nil

proc cbWsOpen(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ws_open(url: i32, urlLen: i32, handler: i32) -> i32: a WebSocket's id, 0 if refused
  ## (host not in `net`, not wss — ws only to this machine —, or 8 already open). `handler`
  ## runs on every event: y_ws_event says which, y_ws_data gives the message.
  let url = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let scheme = urlHost(url)[0]
  var id = 0'i32
  if scheme in ["ws", "wss"] and netAllowed(windowNet(), url) and host.wsLive.len < wsMaxOpen:
    inc host.nextFetch
    id = host.nextFetch
    host.wsOpen.add (id, url, argAt(args, 2).`of`.i32)
    host.wsLive.incl id
  setResult(results, 0, i32Val(id))
  nil

proc cbWsSend(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ws_send(id: i32, data: i32, len: i32) -> i32: 1 queued (sent in order once open), 0 if
  ## the socket is unknown or closed.
  let id = argAt(args, 0).`of`.i32
  let n = argAt(args, 2).`of`.i32
  var ok = 0'i32
  if id in host.wsLive and n >= 0 and n <= 8 shl 20:
    host.wsSend.add (id, if n > 0: readStr(argAt(args, 1).`of`.i32, n) else: "")
    ok = 1
  setResult(results, 0, i32Val(ok))
  nil

proc cbWsClose(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ws_close(id: i32): closes it; its handler hears nothing more.
  let id = argAt(args, 0).`of`.i32
  if id in host.wsLive:
    host.wsLive.excl id
    host.wsClose.add id
  nil

proc cbWsEvent(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ws_event(id: i32) -> i32: inside its handler, 1 opened, 2 a message, 3 closed; else 0.
  let id = argAt(args, 0).`of`.i32
  setResult(results, 0, i32Val(if id in host.wsEvent: host.wsEvent[id][0] else: 0'i32))
  nil

proc cbWsData(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_ws_data(id: i32, buf: i32, cap: i32) -> i32: the message (or why it closed); its full
  ## length, -1 if none, copying up to `cap` bytes to `buf`.
  let id = argAt(args, 0).`of`.i32
  var n = -1'i32
  if id in host.wsEvent:
    let d = host.wsEvent[id][1]
    n = int32(d.len)
    if argAt(args, 2).`of`.i32 > 0: writeStr(argAt(args, 1).`of`.i32, d, argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(n))
  nil

proc cbFetchStatus(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_fetch_status(id: i32) -> i32: the HTTP status, 0 if it failed (the body is then the
  ## reason), -1 if there is no answer for `id` (only inside its handler).
  let id = argAt(args, 0).`of`.i32
  setResult(results, 0, i32Val(if id in host.fetchDone: host.fetchDone[id][0] else: -1'i32))
  nil

proc cbFetchBody(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_fetch_body(id: i32, buf: i32, cap: i32) -> i32: the body's full length (-1: none),
  ## copying up to `cap` bytes into the app's memory at `buf`.
  let id = argAt(args, 0).`of`.i32
  var n = -1'i32
  if id in host.fetchDone:
    let body = host.fetchDone[id][1]
    n = int32(body.len)
    if argAt(args, 2).`of`.i32 > 0: writeStr(argAt(args, 1).`of`.i32, body, argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(n))
  nil

proc cbKey(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_key(which: i32) -> i32: in a Key handler, the key's code (0) or modifier bits (1).
  setResult(results, 0, i32Val(if argAt(args, 0).`of`.i32 == 0: host.keyCode else: host.keyMods))
  nil

proc cbKeyHandled(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_key_handled(): the app took the key; it goes no further (no bubbling, no built-in action).
  host.keyHandled = true
  nil

proc cbNodeSize(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_node_size(node: i32, axis: i32) -> f32: the node's laid-out width (axis 0) or height
  ## (1), for nodes with a Resize handler; its scroll offset (2) for nodes with a Scroll
  ## handler. 0 before the first layout / scroll. Video/audio (P3): 3 position and 4 length
  ## in seconds, 5 how many waveform peaks there are, 1000 + i peak i (0..1). 6: the caret
  ## byte a BlockSplit happened at (P5). 7, 8: a canvas pointer event's x, y in the node (P7);
  ## 9: a canvas's horizontal scroll (P8).
  let id = argAt(args, 0).`of`.i32
  let (w, hh) = host.sizes.getOrDefault(id, (0'f32, 0'f32))
  let axis = argAt(args, 1).`of`.i32
  let v = if axis == 0: w elif axis == 1: hh
          elif axis == 3: host.mediaTime.getOrDefault(id, (0'f32, 0'f32))[0]
          elif axis == 4: host.mediaTime.getOrDefault(id, (0'f32, 0'f32))[1]
          elif axis == 5: float32(host.waveforms.getOrDefault(id, @[]).len)
          elif axis == 6: float32(host.blockCaret)
          elif axis == 7: host.pointerAt[0]
          elif axis == 8: host.pointerAt[1]
          elif axis == 9: host.scrollXOf.getOrDefault(id, 0'f32)
          elif axis == 10: float32(host.linkHit)
          elif axis == 11: float32(host.findCount)
          elif axis == 12: float32(host.findAt)
          elif axis == 13: host.pointerPage[0]
          elif axis == 14: host.pointerPage[1]
          elif axis == 15: float32(host.command)
          elif axis == 16: float32(host.menuCmd)
          elif axis == 17: float32(host.sysTheme)
          elif axis == 18: float32(host.accent)
          elif axis == 19: float32(host.spellRange[0])
          elif axis == 20: float32(host.spellRange[1])
          elif axis >= 1000:
            (let wf = host.waveforms.getOrDefault(id, @[]); if axis - 1000 < wf.len: wf[axis - 1000] else: 0'f32)
          else: host.scrollOf.getOrDefault(id, 0'f32)
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: v)))
  nil

proc cbLog(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## yantra_log(data: i32, len: i32) — the only output channel an app has.
  host.logs.add readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  nil

# --- workers (Q7) --------------------------------------------------------------------
# A worker is another instance (of the app's own module or another one from its folder) on
# its own OS thread, with its own wasmtime engine and store. Messages are strings, copied
# through two channels; the parent gets its worker's messages as events in `pumpWorkers`.
when not defined(emscripten):
  type WorkerBox = object
    path: string
    inbox, outbox: Channel[string]   ## to the worker / from it
    thread: Thread[ptr WorkerBox]

  proc callOptional(inst: Instance; name: string): bool =
    let (_, ok) = inst.getFunc(name)
    if ok: callVoid(inst, name)
    ok

  proc loadApp*(wasmPath: string): Instance

  proc workerMain(w: ptr WorkerBox) {.thread.} =
    {.cast(gcsafe).}:                              # only this thread's own (threadvar) app state
      try:
        let inst = loadApp(w.path)
        host.workerOut = addr w.outbox
        currentCaps = initHashSet[string]()         # a worker gets no capabilities
        discard callOptional(inst, "NimMain")        # top-level state; no UI is built
        discard callOptional(inst, "yantra_worker_main")
        while true:
          let m = w.inbox.recv()
          if m == "\0stop": break
          host.workerMsg = m
          discard callOptional(inst, "yantra_worker_message")
      except CatchableError as err:
        w.outbox.send("\0error " & err.msg)

proc cbWorkerStart(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_worker_start(name: i32, len: i32, handler: i32) -> i32: starts module `name` from the
  ## app's folder ("" = the app's own module) as a worker; its messages come to `handler`.
  ## -2 a bad name, -3 no such module, -1 inside a worker (workers don't nest).
  when defined(emscripten):
    setResult(results, 0, i32Val(-1))
  else:
    let name = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
    let h = argAt(args, 2).`of`.i32
    if host.workerOut != nil: (setResult(results, 0, i32Val(-1)); return nil)
    if name.len > 64 or not name.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}):
      setResult(results, 0, i32Val(-2))
      return nil
    let path = host.appDir / (if name.len > 0: name else: host.appName) & ".wasm"
    if not fileExists(path): (setResult(results, 0, i32Val(-3)); return nil)
    let w = cast[ptr WorkerBox](allocShared0(sizeof(WorkerBox)))
    w.path = path
    w.inbox.open()
    w.outbox.open()
    createThread(w.thread, workerMain, w)
    inc host.nextWorker
    host.workers[host.nextWorker] = (cast[pointer](w), h)
    setResult(results, 0, i32Val(host.nextWorker))
  nil

proc cbWorkerSend(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_worker_send(id: i32, data: i32, len: i32) -> i32: a message to worker `id` (0 ok, -1 none).
  when not defined(emscripten):
    let id = argAt(args, 0).`of`.i32
    if id notin host.workers: (setResult(results, 0, i32Val(-1)); return nil)
    let w = cast[ptr WorkerBox](host.workers[id][0])
    w.inbox.send(readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32))
  setResult(results, 0, i32Val(0))
  nil

proc cbWorkerPost(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_worker_post(data: i32, len: i32): inside a worker, a message to the app that started it.
  when not defined(emscripten):
    if host.workerOut != nil:
      cast[ptr Channel[string]](host.workerOut)[].send(readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32))
  nil

proc cbWorkerMsg(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_worker_msg(buf: i32, cap: i32) -> i32 (full length): the message being delivered.
  let m = host.workerMsg
  if argAt(args, 1).`of`.i32 > 0: writeStr(argAt(args, 0).`of`.i32, m, argAt(args, 1).`of`.i32)
  setResult(results, 0, i32Val(int32(m.len)))
  nil

proc cbWorkerStop(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_worker_stop(id: i32): the worker finishes what it is doing and ends.
  when not defined(emscripten):
    let id = argAt(args, 0).`of`.i32
    if id in host.workers:
      let w = cast[ptr WorkerBox](host.workers[id][0])
      w.inbox.send("\0stop")
      host.workers[id] = (host.workers[id][0], -1'i32)   # its thread ends; pumpWorkers frees it
  nil

proc cbCall(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_call(op: i32, text: i32, len: i32) -> i32 (Q11): a voice call; needs the `mic` and
  ## `calls` capabilities (-1 otherwise). ops: 1 call (text "1" to make the offer, "0" to
  ## answer one; then "\n"-separated ICE server URLs), 2 the other side's description
  ## ("type\nsdp"), 3 its candidate ("mid\ncandidate"), 4 hang up, 5 mute ("1") / unmute ("0").
  ## What to send the other side comes back as CallSignal events on the window.
  if "mic" notin currentCaps or "calls" notin currentCaps:
    setResult(results, 0, i32Val(-1))
    return nil
  let op = argAt(args, 0).`of`.i32
  if op < 1 or op > 5: (setResult(results, 0, i32Val(-2)); return nil)
  host.callReq.add (op, readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32))
  setResult(results, 0, i32Val(0))
  nil

proc cbOpenUrl(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_open_url(url: i32, len: i32) -> i32: opens an http(s) or mailto URL with the system
  ## (the browser: OAuth sign-in, links). -1 any other scheme. The engine does it.
  let u = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let l = u.toLowerAscii
  if u.len > 4096 or not (l.startsWith("https://") or l.startsWith("http://") or l.startsWith("mailto:")) or
     u.contains({'\0', '\n', '\r', '"'}):
    setResult(results, 0, i32Val(-1))
    return nil
  host.openReq.add u
  setResult(results, 0, i32Val(0))
  nil

proc cbCapture(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_capture(kind: i32, op: i32, name: i32, nameLen: i32) -> i32 (Q2). kind 1 the microphone
  ## (capability `mic`), 2 the camera (`camera`). ops: 1 record into `name` (a file in the
  ## app's data folder: .ogg/.opus/.m4a), 2 pause, 3 resume, 4 stop and keep, 5 cancel and
  ## delete, 6 photo from the camera preview into `name` (.png/.jpg); 7 the level now
  ## (0..1000), 8 the state (0 idle, 1 recording, 2 paused, -1 failed), 9 the length in ms.
  ## -1 refused (capability not declared), -2 a bad name; 0 queued for the engine.
  let kind = argAt(args, 0).`of`.i32
  let op = argAt(args, 1).`of`.i32
  if (kind == 1 and "mic" notin currentCaps) or (kind == 2 and "camera" notin currentCaps) or kind notin [1'i32, 2]:
    setResult(results, 0, i32Val(-1))
    return nil
  case op
  of 7: setResult(results, 0, i32Val(int32(host.captureLevel * 1000)))
  of 8: setResult(results, 0, i32Val(host.captureState))
  of 9: setResult(results, 0, i32Val(host.captureMs))
  of 1 .. 6:
    let name = readStr(argAt(args, 2).`of`.i32, argAt(args, 3).`of`.i32)
    if op in [1'i32, 6] and (name.len == 0 or name.len > 120 or ".." in name or '/' in name or '\\' in name or ':' in name):
      setResult(results, 0, i32Val(-2))
      return nil
    host.captureReq.add (kind, op, name)
    setResult(results, 0, i32Val(0))
  else: setResult(results, 0, i32Val(-2))
  nil

proc cbFileRead(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_file_read(pathPtr: i32, pathLen: i32, outBuf: i32, outCap: i32) -> i32
  if "files" notin currentCaps:
    setResult(results, 0, i32Val(-1))
    return nil
  let pathOffset = argAt(args, 0).`of`.i32
  let nPath = argAt(args, 1).`of`.i32
  let outBuf = argAt(args, 2).`of`.i32
  let outCap = argAt(args, 3).`of`.i32
  let rawPath = readStr(pathOffset, nPath)
  if rawPath.len == 0 or rawPath.contains("..") or rawPath.startsWith("/") or rawPath.startsWith("\\") or (rawPath.len > 1 and rawPath[1] == ':'):
    setResult(results, 0, i32Val(-2))
    return nil
  let fullPath = host.appDir / rawPath   # only inside the app's own folder, never the cwd
  if host.appDir.len == 0 or not fileExists(fullPath):
    setResult(results, 0, i32Val(-3))
    return nil
  let data = readFile(fullPath)
  if outCap == 0:
    setResult(results, 0, i32Val(int32(data.len)))
    return nil
  writeStr(outBuf, data, outCap)
  setResult(results, 0, i32Val(int32(min(data.len, int(outCap)))))
  nil

# ===========================================================================
# Import table. This IS the sandbox's entire capability surface.
# ===========================================================================

type
  ImportSpec = object
    params*: seq[WasmValkind]
    results*: seq[WasmValkind]
    cb: WasmFuncCallback

const i32k = WasmValkind(WASM_I32)
const f32k = WasmValkind(WASM_F32)

# --- Vajra apps (built by the Vajra compiler from Atlas cells) ---------------------
# Four more imports: print, stop, and the database through the person using the app.
# The host holds no database itself: the Vajra runtime sets `vajraQueryHook` to run SQL
# as that person (row-level security decides), returning rows joined by \x1f / \x1e, or
# \x15 and the error.
var vajraQueryHook*: proc (sql: string; args: seq[string]): string
# `fetch` the same way: the program that opens the app sets `vajraFetchHook` to the app's
# own rules (host/vajra/livenet.nim: its declared hosts, its secrets); without it the
# app has no network.
var vajraFetchHook*: proc (packed: string): string
var vajraPending {.threadvar.}: string
const vajraExitTrap = "vajra: exit"
proc wasmtimeTrapNew(msg: cstring; len: csize_t): ptr WasmTrap {.
  importc: "wasmtime_trap_new", header: "<wasmtime.h>".}

proc cbNimWrite(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## nim_write(fd, buf, len) -> len: what a Vajra app prints goes to the app's log.
  host.logs.add readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(argAt(args, 2).`of`.i32)); nil

proc cbNimExit(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## nim_exit(code): ends the current call (the app's top-level code ends this way).
  wasmtimeTrapNew(vajraExitTrap, csize_t(vajraExitTrap.len))

proc cbVajraQuery(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_query(sql, sqlLen, args, argsLen) -> result length (collect with vajra_take).
  let sql = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let packed = readStr(argAt(args, 2).`of`.i32, argAt(args, 3).`of`.i32)
  var params = packed.split('\x1f') # each argument ends with \x1f
  params.setLen max(params.len - 1, 0)
  vajraPending = if vajraQueryHook == nil: "\x15this host has no database"
                 else: vajraQueryHook(sql, params)
  setResult(results, 0, i32Val(int32(vajraPending.len))); nil

proc cbVajraFetch(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_fetch(req, reqLen) -> result length (collect with vajra_take): the app waits.
  let packed = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  vajraPending = if vajraFetchHook == nil: "\x15this app has no network here"
                 else: vajraFetchHook(packed)
  setResult(results, 0, i32Val(int32(vajraPending.len))); nil

const f64k = WasmValkind(WASM_F64)

proc cbVajraTake(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_take(dst, cap) -> bytes copied: the result of the last vajra_query.
  let n = min(int(argAt(args, 1).`of`.i32), vajraPending.len)
  writeStr(argAt(args, 0).`of`.i32, vajraPending, int32(n))
  vajraPending = ""
  setResult(results, 0, i32Val(int32(n))); nil

proc cbVajraNow(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_now() -> i64: microseconds since 1970-01-01 UTC (the device's clock).
  let t = getTime()
  setResult(results, 0, WasmVal(kind: WASM_I64, `of`: WasmValunion(i64: t.toUnix * 1_000_000 + t.nanosecond div 1000)))
  nil

proc cbVajraUtcOffset(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_utc_offset() -> i32: seconds the device's local time is ahead of UTC.
  setResult(results, 0, i32Val(int32(-now().utcOffset)))
  nil

proc cbVajraLocation(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_location(dst, cap) -> its length: the screen the app was opened on (`/room/…`).
  let cap = argAt(args, 1).`of`.i32
  if cap > 0: writeStr(argAt(args, 0).`of`.i32, host.location, min(cap, int32(host.location.len)))
  setResult(results, 0, i32Val(int32(host.location.len))); nil

proc cbVajraNavigated(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_navigated(path, len): the app went to another screen; its address now ends so.
  host.location = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  inc host.version; nil

proc cbVajraParam(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_param(packed, len): the app made a `param` (view, name, value, lo, hi, \x1f between).
  let f = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32).split('\x1f')
  if f.len == 5:
    host.params.add ParamInfo(view: f[0], name: f[1], value: f[2], lo: f[3], hi: f[4])
    inc host.version
  nil

proc cbVajraParamValue(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## vajra_param_value(i) -> its length (vajra_take reads it): param `i`'s value, as the host has it.
  let i = argAt(args, 0).`of`.i32
  vajraPending = if i >= 0 and int(i) < host.params.len: host.params[int(i)].value else: ""
  setResult(results, 0, i32Val(int32(vajraPending.len))); nil

proc cbSoundLoad(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  inc host.nextSound
  let id = host.nextSound
  host.soundQueue.add SoundCmd(id: id, op: 0, path: readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32), vol: 1.0'f32)
  setResult(results, 0, i32Val(id))
  nil

proc cbSoundPlay(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  host.soundQueue.add SoundCmd(id: argAt(args, 0).`of`.i32, op: 1)
  nil

proc cbSoundStop(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  host.soundQueue.add SoundCmd(id: argAt(args, 0).`of`.i32, op: 2)
  nil

proc cbSoundVol(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  host.soundQueue.add SoundCmd(id: argAt(args, 0).`of`.i32, op: 3, vol: argAt(args, 1).`of`.f32)
  nil

proc cbPickOpen(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  inc host.nextPick
  let filter = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  host.pickQueue.add PickReq(id: host.nextPick, save: false, handler: argAt(args, 2).`of`.i32, filter: filter)
  setResult(results, 0, i32Val(host.nextPick)); nil

proc cbPickSave(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  inc host.nextPick
  let data = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let name = readStr(argAt(args, 2).`of`.i32, argAt(args, 3).`of`.i32)
  let filter = readStr(argAt(args, 4).`of`.i32, argAt(args, 5).`of`.i32)
  host.pickQueue.add PickReq(id: host.nextPick, save: true, handler: argAt(args, 6).`of`.i32, name: name, filter: filter, saveData: data)
  setResult(results, 0, i32Val(host.nextPick)); nil

proc cbPickStatus(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  let id = argAt(args, 0).`of`.i32
  let s = if id in host.pickDone: host.pickDone[id][0] else: -1'i32
  setResult(results, 0, i32Val(s)); nil

proc cbPickBody(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  let id = argAt(args, 0).`of`.i32
  var n = -1'i32
  if id in host.pickDone:
    let data = host.pickDone[id][1]; n = int32(data.len)
    if argAt(args, 2).`of`.i32 > 0: writeStr(argAt(args, 1).`of`.i32, data, argAt(args, 2).`of`.i32)
  setResult(results, 0, i32Val(n)); nil

proc cbDropData(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  let n = int32(host.dropData.len)
  if argAt(args, 1).`of`.i32 > 0: writeStr(argAt(args, 0).`of`.i32, host.dropData, argAt(args, 1).`of`.i32)
  setResult(results, 0, i32Val(n)); nil

proc cbDropName(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  let n = int32(host.dropName.len)
  if argAt(args, 1).`of`.i32 > 0: writeStr(argAt(args, 0).`of`.i32, host.dropName, argAt(args, 1).`of`.i32)
  setResult(results, 0, i32Val(n)); nil

proc cbNotify(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  if "notifications" notin currentCaps:
    setResult(results, 0, i32Val(-1)); return nil
  let title = readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32)
  let body = readStr(argAt(args, 2).`of`.i32, argAt(args, 3).`of`.i32)
  host.notifyQueue.add NotifyReq(title: title, body: body)
  setResult(results, 0, i32Val(0)); nil

proc cbBuf(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_buf(id, ptr, len): bulk data (a mesh's vertices, thousands of matrices) in one copy,
  ## not one call per number; nodes name the buffer by id (Geometry, Instances).
  let n = argAt(args, 2).`of`.i32
  host.bufs[argAt(args, 0).`of`.i32] = if n > 0: readStr(argAt(args, 1).`of`.i32, n) else: ""
  host.bufVer.mgetOrPut(argAt(args, 0).`of`.i32, 0).inc
  host.bufsTouched = true
  inc host.version
  nil

proc cbInput(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_input(what, arg) -> f32 (G-IN): 0 key `arg` held, 1/2 mouse dx/dy since the last frame,
  ## 3 mouse buttons held (mask), 4 gamepad axis `arg`, 5 gamepad button `arg` held,
  ## 6 a gamepad is connected, 7 seconds since the last frame, 8 the pointer is locked,
  ## 9-11 where the last click hit a 3D object, 12 which instance it hit, 13 local seconds since
  ## midnight, 14 weekday (0 Monday), 15 day of the month, 16 month, 17 year.
  let arg = argAt(args, 1).`of`.i32
  let v = case argAt(args, 0).`of`.i32
    of 0: float32(ord(arg in host.keysHeld))
    of 1: host.mouseDX
    of 2: host.mouseDY
    of 3: float32(host.buttonsHeld)
    of 4: (if arg in 0 .. 5: host.padAxes[arg] else: 0'f32)
    of 5: float32(ord(arg in 0 .. 30 and (host.padButtons and (1'i32 shl arg)) != 0))
    of 6: float32(ord(host.padOn))
    of 7: host.frameDt
    of 8: float32(ord(host.pointerLocked))
    of 9, 10, 11: host.pickAt[argAt(args, 0).`of`.i32 - 9]
    of 12: float32(host.pickInstance)
    of 13, 14, 15, 16, 17, 18:                   # the local date and time (a desktop's clock)
      let t = times.now()
      float32(case argAt(args, 0).`of`.i32
               of 13: t.hour * 3600 + t.minute * 60 + t.second
               of 14: ord(t.weekday)
               of 15: t.monthday
               of 16: ord(t.month)
               of 17: t.year
               else: t.minute)
    else: 0'f32
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: v)))
  nil

proc layerCall(op: int32; args: ptr WasmVal; data = ""; f = 0'f32): string =
  if host.layerOp == nil: return ""
  host.layerOp(op, argAt(args, 0).`of`.i32, 0, 0, 0, 0, f, data)

proc cbLayerNew(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_layer_new(id, w, h) -> 1: a transparent bitmap the app draws into over time (CV2).
  let ok = if host.layerOp == nil: "" else:
    host.layerOp(0, argAt(args, 0).`of`.i32, 0, 0, argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32, 0, "")
  setResult(results, 0, i32Val(int32(ord(ok == "1")))); nil

var layerDrawTap*: proc (id: int32; cmds: string)
  ## Debugging: sees every layer draw (tools comparing a port with its original).

proc cbLayerDraw(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_layer_draw(id, ptr, len): canvas commands drawn into the layer once, where they stay.
  let cmds = readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32)
  if layerDrawTap != nil: layerDrawTap(argAt(args, 0).`of`.i32, cmds)
  discard layerCall(1, args, cmds); nil

proc cbLayerFilter(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_layer_filter(id, kind, amount): blur, brightness, contrast, saturation, invert, grey, sepia, opacity.
  if host.layerOp != nil:
    discard host.layerOp(2, argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32, 0, 0, 0, argAt(args, 2).`of`.f32, "")
  nil

proc cbLayerRead(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_layer_read(id, x, y, w, h, ptr) -> bytes: w x h RGBA into the app's memory at ptr.
  let (w, h) = (argAt(args, 3).`of`.i32, argAt(args, 4).`of`.i32)
  let px = if host.layerOp == nil: "" else:
    host.layerOp(3, argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32, w, h, 0, "")
  if px.len > 0: writeStr(argAt(args, 5).`of`.i32, px, int32(px.len))
  setResult(results, 0, i32Val(int32(px.len))); nil

proc cbLayerWrite(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_layer_write(id, x, y, w, h, ptr): w x h RGBA from the app's memory into the layer.
  let (w, h) = (argAt(args, 3).`of`.i32, argAt(args, 4).`of`.i32)
  if host.layerOp != nil and w > 0 and h > 0:
    discard host.layerOp(4, argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32, w, h, 0,
                         readStr(argAt(args, 5).`of`.i32, w * h * 4))
  nil

proc cbLayerFree(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  discard layerCall(5, args); nil

proc cbPhys(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_phys(op, namePtr, nameLen, a..f) -> f32 (PH1): push, set velocity, read pose, raycast,
  ## ropes… on the 3D object called `name` (sdk/ui/physics.nim has what each op is).
  var a: array[6, float32]
  for i in 0 .. 5: a[i] = argAt(args, 3 + i).`of`.f32
  let v = if host.physOp == nil: 0'f32 else:
    host.physOp(argAt(args, 0).`of`.i32, readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32), a)
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: v)))
  nil

proc cbBone(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_bone(op, modelPtr, modelLen, bonePtr, boneLen, a, b, c) -> f32 (CH1): 0 turn the bone by
  ## (a, b, c) degrees on top of its animation, 1 let it go, 2..4 where it is (x, y, z).
  let v = if host.boneOp == nil: 0'f32 else:
    host.boneOp(argAt(args, 0).`of`.i32, readStr(argAt(args, 1).`of`.i32, argAt(args, 2).`of`.i32),
                readStr(argAt(args, 3).`of`.i32, argAt(args, 4).`of`.i32),
                [argAt(args, 5).`of`.f32, argAt(args, 6).`of`.f32, argAt(args, 7).`of`.f32])
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: v)))
  nil

proc cbTextMeasure(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_text_measure(ptr, len, familyPtr, familyLen, size, weight) -> f32 (A1): the width of
  ## `s` drawn at `size` px and `weight` in `family`. This is the only way an app can learn a
  ## real advance: `Draw` is a command string and cannot return a value, so before this an app
  ## had to invent a per-character width, which is wrong for every font except a monospace one.
  ## Returns 0 when no renderer is attached, so a headless host degrades instead of trapping.
  let v = if host.measureTextOp == nil: 0'f32 else:
    host.measureTextOp(readStr(argAt(args, 0).`of`.i32, argAt(args, 1).`of`.i32),
                       readStr(argAt(args, 2).`of`.i32, argAt(args, 3).`of`.i32),
                       argAt(args, 4).`of`.f32, argAt(args, 5).`of`.i32)
  setResult(results, 0, WasmVal(kind: WASM_F32, `of`: WasmValunion(f32: v)))
  nil

proc cbPhysHit(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
    nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
  ## y_phys_hit(ptr, cap) -> len: the name of what the last raycast hit.
  if argAt(args, 1).`of`.i32 > 0 and host.physHit.len > 0:
    writeStr(argAt(args, 0).`of`.i32, host.physHit, min(argAt(args, 1).`of`.i32, int32(host.physHit.len)))
  setResult(results, 0, i32Val(int32(host.physHit.len))); nil

proc importTable*(): Table[string, ImportSpec] =
  result = initTable[string, ImportSpec]()
  result["y_node_create"]  = ImportSpec(params: @[i32k], results: @[i32k], cb: cbCreate)
  result["y_node_child"]   = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbChild)
  result["y_node_set_i32"] = ImportSpec(params: @[i32k, i32k, i32k], results: @[], cb: cbSetI32)
  result["y_node_set_f32"] = ImportSpec(params: @[i32k, i32k, f32k], results: @[], cb: cbSetF32)
  result["y_node_set_str"] = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[], cb: cbSetStr)
  result["yantra_get_dt"]  = ImportSpec(params: @[], results: @[f32k], cb: cbGetDt)
  result["y_node_on"]      = ImportSpec(params: @[i32k, i32k, i32k], results: @[], cb: cbOn)
  result["y_node_insert"]  = ImportSpec(params: @[i32k, i32k, i32k], results: @[], cb: cbInsert)
  result["y_node_remove"]  = ImportSpec(params: @[i32k], results: @[], cb: cbRemove)
  result["y_node_get_str"] = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbGetStr)
  result["yantra_log"]     = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbLog)
  result["nim_write"]      = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbNimWrite)
  result["nim_exit"]       = ImportSpec(params: @[i32k], results: @[], cb: cbNimExit)
  result["vajra_query"]    = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbVajraQuery)
  result["vajra_take"]     = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbVajraTake)
  result["vajra_fetch"]    = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbVajraFetch)
  result["vajra_now"]      = ImportSpec(params: @[], results: @[WasmValkind(WASM_I64)], cb: cbVajraNow)
  result["vajra_utc_offset"] = ImportSpec(params: @[], results: @[i32k], cb: cbVajraUtcOffset)
  result["vajra_location"] = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbVajraLocation)
  result["vajra_navigated"] = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbVajraNavigated)
  result["vajra_param"] = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbVajraParam)
  result["vajra_param_value"] = ImportSpec(params: @[i32k], results: @[i32k], cb: cbVajraParamValue)
  for m in mathImports():  # the C math library (wasmmath.nim)
    let k = if m.wide: f64k else: f32k
    result[m.name] = ImportSpec(params: (if m.arity == 1: @[k] else: @[k, k]), results: @[k], cb: m.cb)
  result["y_after"]        = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbAfter)
  result["y_store_get"]    = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbStoreGet)
  result["y_store_set"]    = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbStoreSet)
  result["y_node_size"]    = ImportSpec(params: @[i32k, i32k], results: @[f32k], cb: cbNodeSize)
  result["y_key"]          = ImportSpec(params: @[i32k], results: @[i32k], cb: cbKey)
  result["y_key_handled"]  = ImportSpec(params: @[], results: @[], cb: cbKeyHandled)
  result["y_fetch"]        = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbFetch)
  result["y_fetch_ex"]     = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbFetchEx)
  result["y_ws_open"]      = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbWsOpen)
  result["y_ws_send"]      = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbWsSend)
  result["y_ws_close"]     = ImportSpec(params: @[i32k], results: @[], cb: cbWsClose)
  result["y_ws_event"]     = ImportSpec(params: @[i32k], results: @[i32k], cb: cbWsEvent)
  result["y_ws_data"]      = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbWsData)
  result["y_fetch_status"] = ImportSpec(params: @[i32k], results: @[i32k], cb: cbFetchStatus)
  result["y_fetch_body"]   = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbFetchBody)
  result["y_file_read"]    = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbFileRead)
  result["y_capture"]      = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbCapture)
  result["y_worker_start"] = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbWorkerStart)
  result["y_worker_send"]  = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbWorkerSend)
  result["y_worker_post"]  = ImportSpec(params: @[i32k, i32k], results: @[], cb: cbWorkerPost)
  result["y_worker_msg"]   = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbWorkerMsg)
  result["y_worker_stop"]  = ImportSpec(params: @[i32k], results: @[], cb: cbWorkerStop)
  result["y_open_url"]     = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbOpenUrl)
  result["y_call"]         = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbCall)
  result["y_sound_load"]   = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbSoundLoad)
  result["y_sound_play"]   = ImportSpec(params: @[i32k], results: @[], cb: cbSoundPlay)
  result["y_sound_stop"]   = ImportSpec(params: @[i32k], results: @[], cb: cbSoundStop)
  result["y_sound_volume"] = ImportSpec(params: @[i32k, f32k], results: @[], cb: cbSoundVol)
  result["y_pick_open"]    = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbPickOpen)
  result["y_pick_save"]    = ImportSpec(params: @[i32k, i32k, i32k, i32k, i32k, i32k, i32k], results: @[i32k], cb: cbPickSave)
  result["y_pick_status"]  = ImportSpec(params: @[i32k], results: @[i32k], cb: cbPickStatus)
  result["y_pick_body"]    = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbPickBody)
  result["y_drop_data"]    = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbDropData)
  result["y_drop_name"]    = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbDropName)
  result["y_phys"]         = ImportSpec(params: @[i32k, i32k, i32k, f32k, f32k, f32k, f32k, f32k, f32k],
                                        results: @[f32k], cb: cbPhys)
  result["y_bone"]         = ImportSpec(params: @[i32k, i32k, i32k, i32k, i32k, f32k, f32k, f32k],
                                        results: @[f32k], cb: cbBone)
  result["y_phys_hit"]     = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbPhysHit)
  result["y_layer_new"]    = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbLayerNew)
  result["y_layer_draw"]   = ImportSpec(params: @[i32k, i32k, i32k], results: @[], cb: cbLayerDraw)
  result["y_layer_filter"] = ImportSpec(params: @[i32k, i32k, f32k], results: @[], cb: cbLayerFilter)
  result["y_layer_read"]   = ImportSpec(params: @[i32k, i32k, i32k, i32k, i32k, i32k], results: @[i32k], cb: cbLayerRead)
  result["y_layer_write"]  = ImportSpec(params: @[i32k, i32k, i32k, i32k, i32k, i32k], results: @[], cb: cbLayerWrite)
  result["y_layer_free"]   = ImportSpec(params: @[i32k], results: @[], cb: cbLayerFree)
  result["y_sys"]          = ImportSpec(params: @[i32k, i32k], results: @[i32k], cb: cbSys)
  result["y_sys_text"]     = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbSysText)
  result["y_ai"]           = ImportSpec(params: @[i32k, i32k, i32k], results: @[i32k], cb: cbAi)
  result["y_ai_ready"]     = ImportSpec(params: @[], results: @[i32k], cb: cbAiReady)
  result["y_input"]        = ImportSpec(params: @[i32k, i32k], results: @[f32k], cb: cbInput)
  result["y_text_measure"] = ImportSpec(params: @[i32k, i32k, i32k, i32k, f32k, i32k], results: @[f32k],
                                       cb: cbTextMeasure)
  result["y_buf"]          = ImportSpec(params: @[i32k, i32k, i32k], results: @[], cb: cbBuf)
  result["y_notify"]       = ImportSpec(params: @[i32k, i32k, i32k, i32k], results: @[i32k], cb: cbNotify)


proc makeHostFunc(st: Store; spec: ImportSpec): WasmFunc =
  when defined(emscripten):
    return hostFunc(st, spec.params, spec.results, spec.cb)
  else:
    ## Builds a host function with an explicit signature. varargs, so a 0- or
    ## n-result signature both work.
    var pv: WasmValtypeVec
    valtypeVecUninit(addr pv, csize_t(spec.params.len))
    for i, k in spec.params: setKind(addr pv, i, k)

    var rv: WasmValtypeVec
    valtypeVecUninit(addr rv, csize_t(spec.results.len))
    for i, k in spec.results: setKind(addr rv, i, k)

    result = registerHostFuncTyped(st, "", spec.cb, addr pv, addr rv)

# ===========================================================================
# Load and run.
# ===========================================================================

proc moduleImportNames(m: Module): seq[string] =
  ## The module's imports, IN ORDER — the order wasmtime requires when supplying
  ## them. Needed because the C API matches positionally, not by name.
  when defined(emscripten):
    return importNames(m)
  else:
    var vec: WasmImporttypeVec
    wasmModuleImports(cast[pointer](m.rawHandle), addr vec)
    for i in 0 ..< int(vec.size):
      let it = cast[ptr UncheckedArray[ptr WasmImporttype]](vec.data)[i]
      let nm = wasmImporttypeName(it)
      var s = newString(int(nm.size))
      if nm.size > 0: copyMem(addr s[0], nm.data, int(nm.size))
      result.add s

proc moduleCacheDir*(): string =
  ## Where compiled apps are kept between runs (each version compiled once). YANTRA_CACHE
  ## moves it; YANTRA_NO_CACHE=1 turns it off.
  if getEnv("YANTRA_NO_CACHE") == "1": ""
  elif getEnv("YANTRA_CACHE").len > 0: getEnv("YANTRA_CACHE")
  else: getCacheDir() / "yantra" / "modules"

proc loadAppBytes*(bytes, wasmPath: string): Instance

var appSourceHook*: proc (address: string): string
  ## Supplies the bytes of an app named by a `y:` address (`y:@space/cell.Name`),
  ## which lives in Postgres, not in a file. The Atlas sets it (host/vajra/apps.nim).
var assetSourceHook*: proc (app, name: string): string
  ## The bytes of asset `name` (a sound, an image) of the `y:` app `app`, from
  ## Postgres; "" when there is none.

proc splitScreen*(address: string): (string, string) =
  ## `y:@space/todo.Todo/room/0190…` is the app `y:@space/todo.Todo` opened on its
  ## screen `/room/0190…`; an address without a screen opens the app's first one.
  result = (address, "")
  if address.startsWith("y:"):
    let first = address.find('/')
    let second = if first >= 0: address.find('/', first + 1) else: -1
    if second > 0: result = (address[0 ..< second], address[second .. ^1])

proc loadApp*(wasmPath: string): Instance =
  ## Compiles an app module, supplies its imports, and instantiates it. The app is a
  ## file, or a `y:` address served from Postgres through `appSourceHook`.
  let (app, screen) = splitScreen(wasmPath)
  let bytes =
    when defined(emscripten): " "     # the page holds web modules
    else:
      if app.startsWith("y:"):
        if appSourceHook == nil: raise newException(IOError, "no app source for " & app)
        appSourceHook(app)
      else: readFile(app)
  result = loadAppBytes(bytes, app)
  host.location = screen

proc loadAppBytes*(bytes, wasmPath: string): Instance =
  ## As `loadApp`, from the module's bytes: a Vajra app comes straight out of
  ## Postgres and never touches a file. `wasmPath` only names the app (and its
  ## folder, for apps that still read assets from one).
  if bytes.len == 0:
    raise newException(IOError, "empty module: " & wasmPath)

  let engine = newEngine()
  store = newStore(engine)
  host = HostState(nodes: @[], handlers: initTable[int32, int32](), logs: @[],
                   events: initTable[(int32, int32), int32](), appName: wasmPath.splitFile.name,
                   appDir: wasmPath.absolutePath.parentDir)

  when defined(emscripten):
    let m = compileCached(store, bytes.toOpenArrayByte(0, bytes.len - 1), "", wasmPath)
  else:
    let m = compileCached(store, bytes.toOpenArrayByte(0, bytes.len - 1), moduleCacheDir())
  let names = moduleImportNames(m)
  
  when defined(yantraDebug):
    echo "DEBUG loadApp: module imports count: ", names.len
    for n in names: echo "  - ", n
    flushFile(stdout)
    stderr.writeLine("DEBUG loadApp: module imports count: ", names.len)

  let table = importTable()
  var externs = newSeq[WasmExtern](names.len)
  var keepAlive = newSeq[WasmFunc](names.len)
  for i, name in names:
    when defined(yantraDebug):
      echo "DEBUG loadApp: checking import '", name, "'"
      flushFile(stdout)
      stderr.writeLine("DEBUG loadApp: checking import '", name, "'")
    if name notin table:
      when defined(yantraDebug):
        echo "DEBUG loadApp: MISSING import '", name, "'"
        flushFile(stdout)
        stderr.writeLine("DEBUG loadApp: MISSING import '", name, "'")
      raise newException(WasmtimeError,
        "app requires unavailable import '" & name & "' — refusing to instantiate")
    keepAlive[i] = makeHostFunc(store, table[name])
    externs[i] = externOf(addr keepAlive[i])

  when defined(emscripten):
    result = instantiateNamed(m, keepAlive)
  else:
    if externs.len > 0:
      result = instantiateWithImports(m, addr externs[0], csize_t(externs.len))
    else:
      result = instantiateWithImports(m, nil, 0)

  let (me, ok) = getMemoryExport(result, "memory")
  if ok:
    memExport = me
    memReady = true

proc initVajra(inst: Instance) =
  ## A Vajra app initialises its globals in `_start` (which ends with nim_exit: that
  ## trap is expected). Every way of starting an app must run it before yantra_main.
  let (_, isVajra) = inst.getFunc("_start")
  if isVajra:
    try: callVoid(inst, "_start")
    except WasmtimeError as e:
      if vajraExitTrap notin e.msg: raise

proc callMain*(inst: Instance) =
  ## Runs the module's own initialisation (its top-level `var`s) and then the app.
  ## Without `NimMain` a top-level `var todos = state(...)` stays zeroed, and wasm
  ## reads of address 0 do not trap — the app silently sees empty data. The web
  ## runner does the same two calls.
  let (_, hasInit) = inst.getFunc("NimMain")
  if hasInit: callVoid(inst, "NimMain")
  initVajra(inst)
  callVoid(inst, "yantra_main")

proc setParam*(inst: Instance; name, value: string; view = "") =
  ## A GUI moved a Vajra view's `param` `name` (in `view`, or the first that has it) to
  ## `value` (text, as the app shows it: `180px`, `#FF0000`, `true`): the app takes it
  ## and draws the view again.
  for i, p in host.params:
    if p.name == name and (view == "" or p.view == view):
      host.params[i].value = value
      callVoidI32(inst, "vajra_param_changed", int32(i))
      return
  raise newException(KeyError, "this app has no param " & name)

proc dispatch*(inst: Instance; handler: int32) =
  inc host.dispatchCalls
  callVoidI32(inst, "yantra_dispatch", handler)

proc callFrame*(inst: Instance) =
  ## Calls the app's `yantra_frame()` export. The app may or may not
  ## define this; if absent the call is a clean no-op.
  let (f, ok) = inst.getFunc("yantra_frame")
  if not ok:
    return
  when defined(emscripten):
    callVoid(inst, "yantra_frame")
    return
  else:
    var trap: ptr WasmTrap = nil
    let err = funcCall(store.ctx, addr f, nil, 0, nil, 0, addr trap)
    if err != nil:
      raiseWtError("callFrame func_call failed", err)
    if trap != nil:
      raise newException(WasmtimeError, "trap in yantra_frame: " & trapMessage(trap))

proc setFrameDt*(dt: float32) =
  ## Sets the frame delta time for the next yantra_get_dt() call.
  g_frameDt = dt

proc state*(): HostState = host

# ===========================================================================
# Many apps at once (E5): the shell and every app inside it are separate
# instances, each with its own store, memory and node tree. The procs above
# work on "the current app"; `within` makes an app current for the length of a
# call and restores the previous one after, so an app's callbacks can only ever
# touch that app's own memory and tree. Single-threaded, so this is exact.
# ===========================================================================

type
  App* = ref object
    store: Store
    mem: WasmMemory
    memOk: bool
    state*: HostState
    inst*: Instance
    path*: string
    declaredCaps*: HashSet[string]
    grantedCaps*: HashSet[string]
    ranNimMain*: bool

proc capture(): App =
  App(store: store, mem: memExport, memOk: memReady, state: host, grantedCaps: currentCaps)

proc activate(a: App) =
  if a != nil:
    store = a.store
    memExport = a.mem
    memReady = a.memOk
    host = a.state
    currentCaps = a.grantedCaps

proc grantCapability*(a: App; cap: string) =
  a.grantedCaps.incl cap
  if a.store == store: currentCaps.incl cap

proc revokeCapability*(a: App; cap: string) =
  a.grantedCaps.excl cap
  if a.store == store: currentCaps.excl cap

proc hasCapability*(a: App; cap: string): bool =
  cap in a.grantedCaps

template within*(a: App; body: untyped) =
  ## Runs `body` with `a` as the current app, then restores whatever was current.
  let saved = capture()
  activate(a)
  try:
    body
  finally:
    activate(saved)

proc loadManifestCaps(a: App) =
  let (_, ok) = a.inst.getFunc("yantra_manifest_needs")
  if ok:
    let p = callI32Result(a.inst, "yantra_manifest_needs")
    if p > 0:
      var s = readStr(p, int32(min(4096, memTotal() - int(p))))
      let z = s.find(char(0))
      if z >= 0: s.setLen(z)
      for cap in s.split(','):
        let trimmed = cap.strip()
        if trimmed.len > 0:
          a.declaredCaps.incl trimmed
          a.grantedCaps.incl trimmed
          currentCaps.incl trimmed

proc openApp*(wasmPath: string): App =
  ## Loads and instantiates an app as its own sandbox, without disturbing the
  ## current one. Call `run` to start it.
  let saved = capture()
  try:
    let inst = loadApp(wasmPath)
    result = capture()
    result.inst = inst
    result.path = wasmPath
  finally:
    activate(saved)

proc run*(a: App; restore = "") =
  ## NimMain + yantra_main, inside the app's own sandbox. `restore` is a snapshot from
  ## `saveState` of an earlier build: it goes in between the two, so top-level state
  ## and state made while building the UI both come back (hot reload).
  within(a):
    let (_, hasInit) = a.inst.getFunc("NimMain")
    if not a.ranNimMain:
      if hasInit: callVoid(a.inst, "NimMain")
      initVajra(a.inst)
      a.ranNimMain = true
    let (_, canRestore) = a.inst.getFunc("yantra_state_restore")
    if restore.len > 0 and canRestore:
      callVoidI32(a.inst, "yantra_state_reserve", int32(restore.len))
      let p = callI32Result(a.inst, "yantra_state_buf")
      writeStr(p, restore, int32(restore.len))
      callVoid(a.inst, "yantra_state_restore")
    callVoid(a.inst, "yantra_main")
    loadManifestCaps(a)

proc saveState*(a: App): string =
  ## Every `state(...)` of the running app, packed (sdk/core/hotstate.nim); "" if it has none.
  let (_, ok) = a.inst.getFunc("yantra_state_save")
  if not ok: return ""
  within(a):
    let p = callI32Result(a.inst, "yantra_state_save")
    let n = callI32Result(a.inst, "yantra_state_len")
    if n > 0: result = readStr(p, n)

proc dispatchTo*(a: App; handler: int32) =
  within(a):
    dispatch(a.inst, handler)

proc frameTo*(a: App) =
  within(a):
    callFrame(a.inst)

proc sendTheme*(a: App; name: string): bool =
  ## Tells the app its host switched theme: writes `name` into the app's
  ## `yantra_theme_buf` and calls `yantra_theme(len)`. False if the app has no theme hook.
  let (_, okBuf) = a.inst.getFunc("yantra_theme_buf")
  let (_, okSet) = a.inst.getFunc("yantra_theme")
  if not okBuf or not okSet or name.len == 0: return false
  within(a):
    let p = callI32Result(a.inst, "yantra_theme_buf")
    writeStr(p, name, 64)
    callVoidI32(a.inst, "yantra_theme", int32(min(name.len, 64)))
  true

proc callExport*(a: App; name: string): bool =
  ## Calls an optional no-argument export of the app (e.g. `yantra_theme`); false
  ## if the app doesn't have it.
  let (_, ok) = a.inst.getFunc(name)
  if not ok: return false
  within(a):
    callVoid(a.inst, name)
  true

proc pumpWorkers*(a: App): bool =
  ## Hands each worker's messages to its handler in the app (Q7), and frees workers that
  ## stopped. True if a handler ran.
  when not defined(emscripten):
    var gone: seq[int32]
    for id, (p, h) in a.state.workers.pairs:
      let w = cast[ptr WorkerBox](p)
      while true:
        let (ok, m) = w.outbox.tryRecv()
        if not ok: break
        if h >= 0:
          a.state.workerMsg = m
          dispatchTo(a, h)
          result = true
      if h < 0 and not w.thread.running:
        gone.add id
    for id in gone:
      let w = cast[ptr WorkerBox](a.state.workers[id][0])
      joinThread(w.thread)
      w.inbox.close()
      w.outbox.close()
      `=destroy`(w.path)
      deallocShared(w)
      a.state.workers.del id
