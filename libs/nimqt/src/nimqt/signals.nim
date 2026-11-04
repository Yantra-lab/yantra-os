## nimqt — Signals/slots bridge.
##
## Two capabilities, powered by dynamic meta objects (dynmeta.cpp):
##
## 1. connectSignal: attach a Nim closure to ANY Qt object's signal.
## 2. QObjectLike:   expose a Nim ref object to QML as a real QObject with
##                    dynamic properties/signals/invokables.
##
## Design note: Nim closures cannot be safely passed as C function pointers
## (the captured environment pointer is lost). Instead, we use ONE global
## cdecl dispatch procedure per callback kind, and pass a small integer
## registry index as the `env` parameter. The dispatcher looks up the actual
## Nim closure from a global table.

import QtCore, marshaling, strutils

# Private Qt include dirs (dynmeta.cpp needs QtCore/private/*) are added by
# config.nims, discovered from the toolchain — see the ORDER MATTERS note there.

{.compile: "dynmeta.cpp".}

{.push hint[XDeclaredButNotUsed]: off.}

# ---------------------------------------------------------------------------
# Low-level bridge declarations (implemented in dynmeta.cpp)
# ---------------------------------------------------------------------------

type
  TrapInvokeFn* = proc(env: pointer; argc: cint; args: ptr UncheckedArray[QVariant]) {.cdecl.}
  PropReadFn* = proc(env: pointer; propId: cint; outV: ptr QVariant) {.cdecl.}
  PropWriteFn* = proc(env: pointer; propId: cint; v: ptr QVariant): bool {.cdecl.}
  SlotInvokeFn* = proc(env: pointer; slotId: cint; args: ptr UncheckedArray[QVariant];
                       argc: cint; ret: ptr QVariant): bool {.cdecl.}

proc dynTrapCreate*(invoke: TrapInvokeFn; env: pointer): pointer
  {.importc: "nimqt_dyntrap_create".}
proc dynTrapBuildMatchingSlot*(trap: pointer; sender: ptr QObject;
                               signalIndex: cint): cint
  {.importc: "nimqt_dyntrap_build_matching_slot".}
proc dynTrapConnect*(sender: ptr QObject; signalIndex: cint; trap: pointer;
                     slotIndex: cint): pointer
  {.importc: "nimqt_dyntrap_connect".}
proc dynTrapDestroy*(trap: pointer) {.importc: "nimqt_dyntrap_destroy".}
proc dynTrapIsAlive*(trap: pointer): cint {.importc: "nimqt_dyntrap_is_alive".}
proc dynFindSignal*(o: ptr QObject; nameOrSig: cstring): cint
  {.importc: "nimqt_find_signal".}
proc dynConnectionDisconnect*(conn: pointer): bool
  {.importc: "nimqt_connection_disconnect".}
proc dynConnectionFree*(conn: pointer) {.importc: "nimqt_connection_free".}

proc dynExposeCreate*(className: cstring; propsJson: cstring;
                      signalsJson: cstring; slotsJson: cstring;
                      readFn: PropReadFn; writeFn: PropWriteFn;
                      invokeFn: SlotInvokeFn; env: pointer): pointer
  {.importc: "nimqt_dynexpose_create".}
proc dynExposeDestroy*(o: pointer) {.importc: "nimqt_dynexpose_destroy".}
proc dynExposeEmit*(o: pointer; nameOrSig: cstring; args: ptr QVariant;
                    argc: cint): bool
  {.importc: "nimqt_dynexpose_emit".}
proc dynExposeAsQObject*(o: pointer): ptr QObject {.importc: "nimqt_dynexpose_as_qobject".}

# ---------------------------------------------------------------------------
# Global signal-callback registry (index-keyed, avoids closure-pointer issues)
# ---------------------------------------------------------------------------

type
  SignalCb* = proc(args: seq[Variant]) {.gcsafe.}

  SigEntry = object
    fn: SignalCb
    used: bool

const MaxSignals* = 4096
var gSignalTable: array[MaxSignals, SigEntry]
var gNextSignalSlot = 0

proc nimqtDispatchSignal(env: pointer; argc: cint; args: ptr UncheckedArray[QVariant]) {.cdecl,
    exportc: "nimqt_dispatch_signal".} =
  ## Sole C-entry trampoline for ALL signal connections.
  let idx = cast[int](env)
  if idx < 0 or idx >= MaxSignals: return
  if not gSignalTable[idx].used: return
  var vs: seq[Variant] = @[]
  if argc > 0 and not args.isNil:
    vs = newSeq[Variant](int(argc))
    for i in 0 ..< int(argc):
      vs[i] = newVariantFromRaw(args[i])
  gSignalTable[idx].fn(vs)

proc allocSignalSlot(fn: SignalCb): int =
  ## Finds a free slot (round-robin), stores fn, returns index.
  for attempt in 0 ..< MaxSignals:
    let idx = (gNextSignalSlot + attempt) mod MaxSignals
    if not gSignalTable[idx].used:
      gSignalTable[idx] = SigEntry(fn: fn, used: true)
      gNextSignalSlot = (idx + 1) mod MaxSignals
      return idx
  raise newException(ResourceExhaustedError, "nimqt: signal table full")

proc freeSignalSlot(idx: int) =
  if idx >= 0 and idx < MaxSignals:
    gSignalTable[idx] = SigEntry(fn: nil, used: false)

# ---------------------------------------------------------------------------
# ConnectionId + records
# ---------------------------------------------------------------------------

type
  ConnectionId* = distinct uint64

  ConnRecord = object
    connPtr: pointer     # heap QMetaObject::Connection owned here
    trap: pointer        # receiver object (deleted on disconnect)
    sigIdx: int          # registry slot to release
    alive: bool

var gConnections: seq[ref ConnRecord] = @[]

proc rawConn(id: ConnectionId): ref ConnRecord =
  let idx = int(uint64(id) shr 8)
  if idx >= 0 and idx < gConnections.len:
    result = gConnections[idx]

proc isValidConn*(id: ConnectionId): bool {.inline.} =
  let rec = rawConn(id)
  result = rec != nil and rec.alive

# ---------------------------------------------------------------------------
# Public API: connect/disconnect
# ---------------------------------------------------------------------------

proc connectSignalImpl*(sender: ptr QObject; signal: string;
                        cb: SignalCb): ConnectionId =
  ## `signal`: normalized signature ("valueChanged(QString)") OR bare name
  ## ("valueChanged" → first overload found).
  assert not sender.isNil, "connectSignal: nil sender"

  let slotIdx = allocSignalSlot(cb)
  let trap = dynTrapCreate(nimqtDispatchSignal, cast[pointer](slotIdx))

  let sigIdx = dynFindSignal(sender, signal.cstring)
  if sigIdx < 0:
    dynTrapDestroy(trap); freeSignalSlot(slotIdx)
    raise newException(ValueError,
      "nimqt.connectSignal: signal not found: " &
      $objMetaObject(sender).moClassName() & "::" & signal)

  let dynSlotIdx = dynTrapBuildMatchingSlot(trap, sender, sigIdx)
  if dynSlotIdx < 0:
    dynTrapDestroy(trap); freeSignalSlot(slotIdx)
    raise newException(ValueError,
      "nimqt.connectSignal: cannot synthesize slot for " & signal)

  let conn = dynTrapConnect(sender, sigIdx, trap, dynSlotIdx)
  if conn.isNil:
    dynTrapDestroy(trap); freeSignalSlot(slotIdx)
    raise newException(ValueError, "nimqt.connectSignal: connect() failed")

  let rec = new(ConnRecord)
  rec.connPtr = conn; rec.trap = trap; rec.sigIdx = slotIdx; rec.alive = true
  gConnections.add(rec)
  result = ConnectionId(uint64(gConnections.len - 1) shl 8 or 1)

  # Sender-death safety: when the sender is destroyed Qt kills both the
  # connection and (the trap being parented to the sender) the trap.
  # Mark the record dead so a later disconnectSlot() cannot touch freed
  # C++ objects, and release the registry slot eagerly.
proc disconnectSlot*(id: ConnectionId): bool =
  let rec = rawConn(id)
  if rec.isNil or not rec.alive: return false
  if dynTrapIsAlive(rec.trap) != 0:
    # Trap still alive: we own the full teardown.
    discard dynConnectionDisconnect(rec.connPtr)
    dynConnectionFree(rec.connPtr)
    dynTrapDestroy(rec.trap)
  else:
    # Sender died earlier; Qt destroyed connection+trap. Nothing to free.
    discard
  freeSignalSlot(rec.sigIdx)
  rec.alive = false
  result = true

# ---------------------------------------------------------------------------
# QObjectLike — exposing Nim objects to QML
# ---------------------------------------------------------------------------

type
  PropKind* = enum pkBool, pkInt, pkDouble, pkString, pkVariant

  PropSpec* = object
    name*: string
    kind*: PropKind

  SlotSpec* = object
    name*: string
    params*: seq[PropKind]
    retVoid*: bool       ## true = void; false = returns QVariant

  SignalSpec* = object
    name*: string
    params*: seq[PropKind]

  ExposedState = object
    obj: RootRef                 # GC anchor for the user's object
    propKinds: seq[PropKind]
    slotSpecs: seq[SlotSpec]
    readHook: proc(o: RootRef; id: int; kind: PropKind): Variant {.gcsafe.}
    writeHook: proc(o: RootRef; id: int; kind: PropKind; v: Variant): bool {.gcsafe.}
    invokeHook: proc(o: RootRef; id: int; spec: SlotSpec; args: seq[Variant]): Variant {.gcsafe.}

  QObjectLike* = ref object of RootObj
    h: pointer               # nimqt_dynexpose handle
    cppObj: ptr QObject
    exposed: bool

proc kindToName(k: PropKind): string =
  case k
  of pkBool: "bool"
  of pkInt: "qlonglong"
  of pkDouble: "double"
  of pkString: "QString"
  of pkVariant: "QVariant"

proc toJsonKinds(kinds: seq[PropKind]): string =
  result = "["
  for i, k in kinds:
    if i > 0: result.add(",")
    result.add("\"" & kindToName(k) & "\"")
  result.add("]")

proc jsonStrArray(items: seq[string]): string =
  result = "["
  for i, n in items:
    if i > 0: result.add(",")
    result.add("\"" & n & "\"")
  result.add("]")

method qmlClassSpec*(o: QObjectLike):
    tuple[name: string, props: seq[PropSpec], signals: seq[SignalSpec],
          slots: seq[SlotSpec]] {.base, gcsafe.} =
  ## Subclasses override to declare their QML surface.
  result.name = "NimObject"

method onReadProperty*(o: QObjectLike; id: int; kind: PropKind): Variant {.
    base, gcsafe.} = newVariant()

method onWriteProperty*(o: QObjectLike; id: int; kind: PropKind; v: Variant): bool {.
    base, gcsafe.} = false

method onInvoke*(o: QObjectLike; id: int; spec: SlotSpec; args: seq[Variant]): Variant {.
    base, gcsafe.} = newVariant()

# ---- global dispatchers for exposed-object hooks -----------------------------

var gExposedStates: seq[ref ExposedState] = @[]

proc nimqtDispatchRead(env: pointer; propId: cint; outV: ptr QVariant) {.cdecl,
    exportc: "nimqt_dispatch_read".} =
  let idx = cast[int](env)
  if idx < 0 or idx >= gExposedStates.len: return
  let st = gExposedStates[idx]
  let obj = QObjectLike(st.obj)
  let v = st.readHook(obj, int(propId), st.propKinds[int(propId)])
  outV[] = v.deref()

proc nimqtDispatchWrite(env: pointer; propId: cint; v: ptr QVariant): bool {.cdecl,
    exportc: "nimqt_dispatch_write".} =
  let idx = cast[int](env)
  if idx < 0 or idx >= gExposedStates.len: return false
  let st = gExposedStates[idx]
  let obj = QObjectLike(st.obj)
  result = st.writeHook(obj, int(propId), st.propKinds[int(propId)],
                        newVariantFromRaw(v[]))

proc nimqtDispatchInvoke(env: pointer; slotId: cint; args: ptr UncheckedArray[QVariant];
                         argc: cint; ret: ptr QVariant): bool {.cdecl,
    exportc: "nimqt_dispatch_invoke".} =
  let idx = cast[int](env)
  if idx < 0 or idx >= gExposedStates.len: return false
  let st = gExposedStates[idx]
  let obj = QObjectLike(st.obj)
  var vs: seq[Variant] = @[]
  if argc > 0 and not args.isNil:
    vs = newSeq[Variant](int(argc))
    for i in 0 ..< int(argc):
      vs[i] = newVariantFromRaw(args[i])
  let spec = st.slotSpecs[int(slotId)]
  let r = st.invokeHook(obj, int(slotId), spec, vs)
  if not spec.retVoid and not ret.isNil:
    ret[] = r.deref()
  result = true

# ---- registration ------------------------------------------------------------

proc buildSignature(name: string; params: seq[PropKind]): string =
  result = name & "("
  for i, k in params:
    if i > 0: result.add(",")
    result.add(kindToName(k))
  result.add(")")

proc exposeObject*[T: QObjectLike](obj: T): T =
  ## Wraps `obj` in a dynamic meta object so QML sees it as a native type.
  ## All dynamic properties/params use the QVariant metatype (see dynmeta.cpp);
  ## Nim-side kinds are preserved in the specs for typed hook dispatch.
  let (clsName, props, signals, slots) = obj.qmlClassSpec()

  var propNames: seq[string] = @[]
  var propKinds: seq[PropKind] = @[]
  for p in props:
    propNames.add(p.name); propKinds.add(p.kind)
  var sigSigs: seq[string] = @[]
  for s in signals:
    sigSigs.add(buildSignature(s.name, s.params))
  var slotSigs: seq[string] = @[]
  for s in slots:
    var sig = buildSignature(s.name, s.params)
    if not s.retVoid:
      sig.add("!")
    slotSigs.add(sig)

  let propsPayload = propNames.join("\n")
  let sigsPayload = sigSigs.join("\n")
  let slotsPayload = slotSigs.join("\n")

  # Per-object hook state (kept alive forever — one per exposed object).
  var st = new(ExposedState)
  st.obj = obj
  st.propKinds = propKinds
  st.slotSpecs = slots
  st.readHook = proc(o: RootRef; id: int; kind: PropKind): Variant {.gcsafe.} =
    QObjectLike(o).onReadProperty(id, kind)
  st.writeHook = proc(o: RootRef; id: int; kind: PropKind; v: Variant): bool {.gcsafe.} =
    QObjectLike(o).onWriteProperty(id, kind, v)
  st.invokeHook = proc(o: RootRef; id: int; spec: SlotSpec; args: seq[Variant]): Variant {.gcsafe.} =
    QObjectLike(o).onInvoke(id, spec, args)
  let envIdx = gExposedStates.len
  gExposedStates.add(st)

  let handle = dynExposeCreate(clsName.cstring, propsPayload.cstring,
                               sigsPayload.cstring, slotsPayload.cstring,
                               nimqtDispatchRead, nimqtDispatchWrite,
                               nimqtDispatchInvoke, cast[pointer](envIdx))
  if handle.isNil:
    raise newException(ValueError, "nimqt.exposeObject: dynExposeCreate failed")

  result = obj
  result.h = handle
  result.cppObj = dynExposeAsQObject(handle)
  result.exposed = true

proc cppHandle*(o: QObjectLike): ptr QObject {.inline.} = o.cppObj

proc emitQmlSignal*(o: QObjectLike; name: string; args: openArray[Variant]): bool =
  ## Emits one of the declared signals by name.
  if o.h.isNil: return false
  var buf: array[16, QVariant]
  let n = min(args.len, buf.len)
  for i in 0 ..< n:
    buf[i] = args[i].deref()
  result = dynExposeEmit(o.h, name.cstring, addr buf[0], cint(n))

proc disposeExposed*(o: QObjectLike) =
  if not o.h.isNil:
    dynExposeDestroy(o.h)
    o.h = nil
    o.cppObj = nil
    o.exposed = false

{.pop.}
