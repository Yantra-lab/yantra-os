## Yantra SDK Core Runtime (R3)
import std/[macros, tables]
import wire except Align, Easing
export NodeKind, Prop, Event

type
  NodeId* = distinct int32
  PropId* = distinct int32
  Node* = object
    id*: NodeId
  CapabilityDenied* = object
    capability*: string
    reason*: string
    msg*: string
  FileResult* = object
    ok*: bool
    data*: string
    error*: CapabilityDenied

proc newCapabilityDenied*(cap: string; reason = "permission denied"): CapabilityDenied =
  result.capability = cap
  result.reason = reason
  result.msg = "CapabilityDenied: '" & cap & "' access not granted in manifest"

proc `$`*(e: CapabilityDenied): string = e.msg

const
  files* = "files"
  network* = "network"
  storage* = "storage"
  notifications* = "notifications"

var g_manifestNeeds* = ""

proc needs*(caps: varargs[string]) =
  var s = ""
  for i, c in caps:
    if i > 0: s.add ","
    s.add c
  g_manifestNeeds = s

proc yantra_manifest_needs(): cstring {.exportc: "yantra_manifest_needs".} =
  cstring(g_manifestNeeds)

proc yNodeCreate*(kind: int32): int32 {.importc: "y_node_create", cdecl.}
proc yNodeChild*(parent: int32, child: int32) {.importc: "y_node_child", cdecl.}
proc yNodeSetF32*(node: int32, prop: int32, value: float32) {.importc: "y_node_set_f32", cdecl.}
proc yNodeSetI32*(node: int32, prop: int32, value: int32) {.importc: "y_node_set_i32", cdecl.}
proc yNodeSetStr*(node: int32, prop: int32, data: int32, len: int32) {.importc: "y_node_set_str", cdecl.}
proc yNodeOn*(node: int32, event: int32, handler: int32) {.importc: "y_node_on", cdecl.}
proc yAfter*(ms: int32, handler: int32) {.importc: "y_after", cdecl.}
proc yStoreGet*(key, keyLen, buf, cap: int32): int32 {.importc: "y_store_get", cdecl.}
proc yStoreSet*(key, keyLen, val, valLen: int32): int32 {.importc: "y_store_set", cdecl.}
proc yFetch*(url, urlLen, handler: int32): int32 {.importc: "y_fetch", cdecl.}
proc yNodeSize*(node, axis: int32): float32 {.importc: "y_node_size", cdecl.}
proc yKey*(which: int32): int32 {.importc: "y_key", cdecl.}
proc yKeyHandled*() {.importc: "y_key_handled", cdecl.}
proc yFetchStatus*(id: int32): int32 {.importc: "y_fetch_status", cdecl.}
proc yFetchBody*(id, buf, cap: int32): int32 {.importc: "y_fetch_body", cdecl.}
proc yFetchEx*(req, reqLen, handler: int32): int32 {.importc: "y_fetch_ex", cdecl.}
proc yWsOpen*(url, urlLen, handler: int32): int32 {.importc: "y_ws_open", cdecl.}
proc yWsSend*(id, data, len: int32): int32 {.importc: "y_ws_send", cdecl.}
proc yWsClose*(id: int32) {.importc: "y_ws_close", cdecl.}
proc yWsEvent*(id: int32): int32 {.importc: "y_ws_event", cdecl.}
proc yWsData*(id, buf, cap: int32): int32 {.importc: "y_ws_data", cdecl.}
proc yLog*(data: int32, len: int32) {.importc: "yantra_log", cdecl.}
proc yNodeInsert*(parent: int32, child: int32, before: int32) {.importc: "y_node_insert", cdecl.}
  ## Moves or inserts `child` into `parent` just before `before` (-1 = at the end).
proc yNodeRemove*(node: int32) {.importc: "y_node_remove", cdecl.}
  ## Detaches `node` from its parent and destroys it and everything under it.
proc yNodeGetStr*(node: int32, prop: int32, buf: int32, cap: int32): int32 {.importc: "y_node_get_str", cdecl.}
proc yCapture*(kind, op, name, nameLen: int32): int32 {.importc: "y_capture", cdecl.}
  ## Copies up to `cap` bytes of a string property into the app's memory at `buf`;
  ## returns the full length. How an app reads what the user typed.
proc yantra_get_dt*(): float32 {.importc: "yantra_get_dt", cdecl.}
proc yFileRead(pathPtr, pathLen, outBuf, outCap: int32): int32 {.importc: "y_file_read", cdecl.}

proc readText*(path: string): FileResult =
  when sizeof(pointer) == 4:
    let pathOffset = if path.len > 0: cast[int32](path.cstring) else: 0'i32
    let needed = yFileRead(pathOffset, int32(path.len), 0'i32, 0'i32)
    if needed < 0:
      return FileResult(ok: false, error: newCapabilityDenied("files", "permission denied"))
    if needed == 0:
      return FileResult(ok: true, data: "")
    var buf = newString(int(needed))
    let n = yFileRead(pathOffset, int32(path.len), cast[int32](buf.cstring), int32(needed))
    if n < 0:
      return FileResult(ok: false, error: newCapabilityDenied("files", "permission denied"))
    buf.setLen(int(n))
    return FileResult(ok: true, data: buf)
  else:
    return FileResult(ok: false, error: newCapabilityDenied("files", "native unsupported"))

proc readTextFile*(path: string): FileResult = readText(path)

type PickResult* = object
  ok*: bool
  data*: string
  error*: string

proc yPickOpen(filterPtr, filterLen, handler: int32): int32 {.importc: "y_pick_open", cdecl.}
proc yPickSave(dataPtr, dataLen, namePtr, nameLen, filterPtr, filterLen, handler: int32): int32 {.importc: "y_pick_save", cdecl.}
proc yPickStatus(id: int32): int32 {.importc: "y_pick_status", cdecl.}
proc yPickBody(id, buf, cap: int32): int32 {.importc: "y_pick_body", cdecl.}

var handlers*: seq[proc()] = newSeqOfCap[proc()](64)
proc onHandler*(handler: proc()): int32 = handlers.add(handler); int32(handlers.len - 1)
template strPtr(s: string): int32 =
  when sizeof(pointer) == 4: (if s.len > 0: cast[int32](s.cstring) else: 0'i32) else: 0'i32

proc pickFile*(filters = ""; cb: proc(res: PickResult)) =
  var reqId: int32 = 0
  let h = onHandler(proc() =
    if yPickStatus(reqId) == 200:
      let cap = yPickBody(reqId, 0, 0)
      var body = newString(int(cap))
      if cap > 0 and sizeof(pointer) == 4: discard yPickBody(reqId, cast[int32](body.cstring), cap)
      cb(PickResult(ok: true, data: body))
    else: cb(PickResult(ok: false, error: "cancelled or failed")))
  reqId = yPickOpen(strPtr(filters), int32(filters.len), h)

proc saveFile*(data: string; defaultName = ""; filters = ""; cb: proc(ok: bool) = nil) =
  var reqId: int32 = 0
  let h = onHandler(proc() = (if cb != nil: cb(yPickStatus(reqId) == 200)))
  reqId = yPickSave(strPtr(data), int32(data.len), strPtr(defaultName), int32(defaultName.len), strPtr(filters), int32(filters.len), h)


proc log*(msg: string) =
  if msg.len > 0: yLog(cast[int32](msg.cstring), int32(msg.len))

proc make*(kind: NodeKind, parent: Node = Node(id: NodeId(-1))): Node =
  let raw = yNodeCreate(int32(kind))
  result = Node(id: NodeId(raw))
  if int32(parent.id) >= 0: yNodeChild(int32(parent.id), raw)

when sizeof(pointer) == 4:
  proc set*(node: Node, prop: Prop, value: string) =
    if value.len > 0: yNodeSetStr(int32(node.id), int32(prop), cast[int32](value.cstring), int32(value.len))
    else: yNodeSetStr(int32(node.id), int32(prop), 0, 0)
else:
  var nativeStrings: seq[string] = @[""]
  proc getNativeString*(handle: int32): string =
    if handle > 0 and handle < nativeStrings.len: nativeStrings[handle] else: ""
  proc set*(node: Node, prop: Prop, value: string) =
    nativeStrings.add(value)
    yNodeSetStr(int32(node.id), int32(prop), int32(nativeStrings.len - 1), int32(value.len))
proc insertBefore*(parent, child: Node; before: Node = Node(id: NodeId(-1))) =
  yNodeInsert(int32(parent.id), int32(child.id), int32(before.id))

proc remove*(node: Node) = yNodeRemove(int32(node.id))

when sizeof(pointer) == 4:
  proc getStr*(node: Node, prop: Prop): string =
    var buf = newString(256)
    let n = yNodeGetStr(int32(node.id), int32(prop), cast[int32](buf.cstring), 256)
    if n > 256:
      buf = newString(n)
      discard yNodeGetStr(int32(node.id), int32(prop), cast[int32](buf.cstring), n)
    buf.setLen(max(n, 0))
    buf
else:
  var nativeGetStrHook*: proc (node, prop: int32): string
    ## Native builds (tests) have no engine to read from; a test engine sets this.
  proc getStr*(node: Node, prop: Prop): string =
    if nativeGetStrHook != nil: nativeGetStrHook(int32(node.id), int32(prop)) else: ""

proc set*(node: Node, prop: Prop, value: float32) = yNodeSetF32(int32(node.id), int32(prop), value)
proc set*(node: Node, prop: Prop, value: int32) = yNodeSetI32(int32(node.id), int32(prop), value)
proc set*(node: Node, prop: Prop, value: bool) = yNodeSetI32(int32(node.id), int32(prop), int32(value))

var listeners: Table[(int32, int32), seq[proc()]]

proc addHandler*(node: Node; event: Event; handler: proc()) =
  ## Any number of handlers per node and event, run in the order they were added
  ## (an `input` bound to a signal can also have its own `onInput:`). The engine
  ## sees one handler per (node, event): a dispatcher over this list.
  let key = (int32(node.id), int32(event))
  if key in listeners:
    listeners[key].add handler
  else:
    listeners[key] = @[handler]
    yNodeOn(key[0], key[1], onHandler(proc() =
      let all = listeners.getOrDefault(key)
      for f in all: f()))

proc clickable*(node: Node, handler: proc()) = node.addHandler(evClick, handler)
proc onClick*(node: Node, handler: proc()) = node.addHandler(evClick, handler)
proc onChange*(node: Node, handler: proc()) = node.addHandler(evChange, handler)
proc onDragStart*(node: Node, handler: proc()) = node.addHandler(evDragStart, handler)
proc onDragOver*(node: Node, handler: proc()) = node.addHandler(evDragOver, handler)
proc onDrop*(node: Node, handler: proc()) = node.addHandler(evDrop, handler)

type DroppedFile* = object
  name*: string
  data*: string

proc yDropData(buf, cap: int32): int32 {.importc: "y_drop_data", cdecl.}
proc yDropName(buf, cap: int32): int32 {.importc: "y_drop_name", cdecl.}
var localDragData: string
proc setDragData*(data: string) = localDragData = data

proc droppedData*(): string =
  when sizeof(pointer) == 4:
    let cap = yDropData(0, 0)
    if cap > 0:
      result = newString(int(cap))
      discard yDropData(cast[int32](result.cstring), cap)
    else: result = localDragData
  else: result = localDragData

proc droppedName*(): string =
  when sizeof(pointer) == 4:
    let cap = yDropName(0, 0)
    if cap > 0:
      result = newString(int(cap))
      discard yDropName(cast[int32](result.cstring), cap)
    else: result = ""
  else: result = ""

proc droppedFile*(): DroppedFile = DroppedFile(name: droppedName(), data: droppedData())
proc onDrop*(node: Node, handler: proc(f: DroppedFile)) =
  node.addHandler(evDrop, proc() = handler(droppedFile()))

var gFrameDtCache* = -1.0'f32
  ## The frame clock, read at most once per handler (W1-5). < 0 = "not read this handler".

proc resetFrameDt*() =
  ## Starts a handler: the frame clock must be read fresh from the host — once, then
  ## every frameDt() call inside the handler returns that one value (pure-identical).
  gFrameDtCache = -1'f32

proc yantraDispatch*(handler: int32) {.exportc: "yantra_dispatch".} =
  resetFrameDt()
  if handler >= 0 and handler < int32(handlers.len): handlers[handler]()

macro yantraFrame*(body: untyped): untyped =
  result = quote do:
    proc yantra_frame*() {.exportc: "yantra_frame", cdecl.} =
      resetFrameDt()          # the legacy per-frame export: same once-read rule (W1-5)
      `body`

macro yantraRun*(body: untyped): untyped =
  result = quote do:
    proc yantra_main*() {.exportc: "yantra_main".} = `body`

# --- microphone and camera (Q2): `needs("mic")` / `needs("camera")`, else every call is refused (-1)
proc captureCall(kind, op: int32; name = ""): int32 =
  when sizeof(pointer) == 4:
    yCapture(kind, op, (if name.len > 0: cast[int32](name.cstring) else: 0'i32), int32(name.len))
  else: -1
proc recordStart*(file: string): int32 = captureCall(1, 1, file)
  ## Records the microphone into `file` in the app's data folder (.ogg / .opus Opus, .m4a AAC);
  ## play it back with `audio "data/<file>"`.
proc recordPause*(): int32 = captureCall(1, 2)
proc recordResume*(): int32 = captureCall(1, 3)
proc recordStop*(): int32 = captureCall(1, 4)     ## finish and keep the file
proc recordCancel*(): int32 = captureCall(1, 5)   ## stop and delete it
proc micLevel*(): float32 = float32(captureCall(1, 7)) / 1000   ## 0..1, for a level meter (poll it)
proc recordState*(): int32 = captureCall(1, 8)    ## 0 idle, 1 recording, 2 paused, -1 failed / refused
proc recordMs*(): int32 = captureCall(1, 9)
proc takePhoto*(file: string): int32 = captureCall(2, 6, file)
  ## Saves what the camera preview (`video "camera:0"`) shows into `file` (.png / .jpg) in the data folder.

# --- workers (Q7): heavy work on another thread, in another instance ----------------------
proc yWorkerStart(name, len, handler: int32): int32 {.importc: "y_worker_start", cdecl.}
proc yWorkerSend(id, data, len: int32): int32 {.importc: "y_worker_send", cdecl.}
proc yWorkerPost(data, len: int32) {.importc: "y_worker_post", cdecl.}
proc yWorkerMsg(buf, cap: int32): int32 {.importc: "y_worker_msg", cdecl.}
proc yWorkerStop(id: int32) {.importc: "y_worker_stop", cdecl.}

type Worker* = object
  id*: int32                              ## > 0 when it started

proc strArg(s: string): int32 =
  when sizeof(pointer) == 4: (if s.len > 0: cast[int32](s.cstring) else: 0'i32) else: 0'i32

proc workerMessage*(): string =
  ## The message being delivered (inside an onMessage / onWorkerMessage handler).
  when sizeof(pointer) == 4:
    let n = yWorkerMsg(0, 0)
    result = newString(int(n))
    if n > 0: discard yWorkerMsg(cast[int32](result.cstring), n)

proc startWorker*(module: string; onMessage: proc (msg: string)): Worker =
  ## Starts `module` (a .wasm in the app's folder; "" = this app's own module) on its own
  ## thread. It gets messages with `send`; what it `postMessage`s arrives in `onMessage`
  ## (a "\0error …" message if it trapped). Its top-level code runs, not its `app` block.
  Worker(id: yWorkerStart(strArg(module), int32(module.len), onHandler(proc () = onMessage(workerMessage()))))
proc send*(w: Worker; msg: string) = discard yWorkerSend(w.id, strArg(msg), int32(msg.len))
proc stop*(w: Worker) = yWorkerStop(w.id)

var gWorkerRunner: proc ()
proc onWorkerMessage*(handler: proc (msg: string)) =
  ## Inside a worker (at top level): what to do with each message from the app.
  gWorkerRunner = proc () =
    handler(workerMessage())
proc postMessage*(msg: string) = yWorkerPost(strArg(msg), int32(msg.len))
  ## Inside a worker: a message back to the app that started it.
proc yantra_worker_message() {.exportc: "yantra_worker_message".} =
  if gWorkerRunner != nil: gWorkerRunner()

# --- the OS (Q8) -------------------------------------------------------------------------------
proc yOpenUrl(url, len: int32): int32 {.importc: "y_open_url", cdecl.}
proc openUrl*(url: string): bool = yOpenUrl(strArg(url), int32(url.len)) == 0
  ## Opens an http(s) or mailto URL with the system browser / mail app. For OAuth, send the
  ## user to the provider with redirect_uri = "<scheme>://oauth" and read the code in DeepLink.
proc menuCommand*(): int32 = int32(yNodeSize(0, 16))    ## in a MenuCommand handler: which item
proc systemDark*(): bool = yNodeSize(0, 17) == 2        ## the system theme is dark
proc accentRgb*(): int32 = int32(yNodeSize(0, 18))      ## the system accent colour, 0xRRGGBB
proc deepLinkUrl*(): string = workerMessage()           ## in a DeepLink handler: the URL

# --- spelling (Q9) --------------------------------------------------------------------------
var replaceN: int
proc replaceText*(node: Node; a, z: int; text: string) =
  ## Replaces bytes a ..< z of an input's value as an edit (undoable; the field fires Input).
  inc replaceN
  node.set(pReplace, $a & "," & $z & "," & text & "#" & $replaceN)
proc spellMenu*(): (string, seq[string]) =
  ## In a SpellMenu handler: the misspelled word and its suggestions.
  var parts: seq[string]
  var cur = ""
  for c in workerMessage():
    if c == '\t': (parts.add cur; cur = "") else: cur.add c
  parts.add cur
  (parts[0], parts[1 .. ^1])
proc spellRange*(node: Node): (int, int) =
  (int(yNodeSize(int32(node.id), 19)), int(yNodeSize(int32(node.id), 20)))

# --- voice calls (Q11): `needs("mic", "calls")` ----------------------------------------------------
from std/strutils import split, join
proc yCall(op, text, len: int32): int32 {.importc: "y_call", cdecl.}
proc callStart*(offer: bool; iceServers = "stun:stun.l.google.com:19302"): int32 =
  ## Starts a call: `offer` makes the offer; the other side answers (`offer = false`, then
  ## `callRemote` with the offer). Send every CallSignal "sdp"/"cand" text to the other side.
  let t = (if offer: "1" else: "0") & "\n" & iceServers
  yCall(1, strArg(t), int32(t.len))
proc callRemote*(signal: string): int32 =
  ## Hands the call a signal from the other side: its "sdp\ttype\tsdp" or "cand\tmid\tcandidate".
  let f = signal.split('\t')
  if f.len < 3: return -2
  let (op, t) = if f[0] == "sdp": (2'i32, f[1] & "\n" & f[2 .. ^1].join("\t")) else: (3'i32, f[1] & "\n" & f[2 .. ^1].join("\t"))
  yCall(op, strArg(t), int32(t.len))
proc callHangUp*(): int32 = yCall(4, 0, 0)
proc callMute*(on: bool): int32 =
  let t = if on: "1" else: "0"
  yCall(5, strArg(t), 1)
proc callSignal*(): string = workerMessage()   ## in a CallSignal handler: "sdp…", "cand…" or "state\tn\t"

# --- audio and notifications (C2, C6) -----------------------------------------------------------
type
  Sound* = object
    id*: int32
    vol*: float32

when sizeof(pointer) == 4:
  proc ySoundLoad(path, len: int32): int32 {.importc: "y_sound_load", cdecl.}
  proc ySoundPlay(id: int32) {.importc: "y_sound_play", cdecl.}
  proc ySoundStop(id: int32) {.importc: "y_sound_stop", cdecl.}
  proc ySoundVol(id: int32, v: float32) {.importc: "y_sound_volume", cdecl.}
  proc sound*(path: string): Sound =
    let p = if path.len > 0: cast[int32](path.cstring) else: 0'i32
    Sound(id: ySoundLoad(p, int32(path.len)), vol: 1.0'f32)
  proc play*(s: Sound) = ySoundPlay(s.id)
  proc stop*(s: Sound) = ySoundStop(s.id)
  proc setVolume*(s: var Sound; v: float32) =
    s.vol = clamp(v, 0.0'f32, 1.0'f32)
    ySoundVol(s.id, s.vol)
else:
  var nativeSoundSeq: int32
  proc sound*(path: string): Sound =
    inc nativeSoundSeq
    Sound(id: nativeSoundSeq, vol: 1.0'f32)
  proc play*(s: Sound) = discard
  proc stop*(s: Sound) = discard
  proc setVolume*(s: var Sound; v: float32) = s.vol = clamp(v, 0.0'f32, 1.0'f32)
proc volume*(s: Sound): float32 = s.vol

when sizeof(pointer) == 4:
  proc yNotify(titlePtr, titleLen, bodyPtr, bodyLen: int32): int32 {.importc: "y_notify", cdecl.}
  proc notify*(title, body: string): bool =
    let tp = if title.len > 0: cast[int32](title.cstring) else: 0'i32
    let bp = if body.len > 0: cast[int32](body.cstring) else: 0'i32
    yNotify(tp, int32(title.len), bp, int32(body.len)) == 0
else:
  proc notify*(title, body: string): bool = true

