## nimqt — high-level wrappers.
##
## ref-object API over the low-level bindings. Ownership follows Qt's parent
## rule: objects with a C++ parent are never freed from Nim; parentless
## wrapper-owned objects are released in their =destroy hook.

import QtCore, QtGui, QtQml, QtQuick, marshaling, signals

{.push hint[XDeclaredButNotUsed]: off.}

type
  Application* = ref object of RootObj
    h: ptr QGuiApplication
    ownsCpp: bool

  Engine* = ref object of RootObj
    h: ptr QQmlEngine
    ownsCpp: bool

  Component* = ref object of RootObj
    h: ptr QQmlComponent
    ownsCpp: bool

  Context* = ref object of RootObj
    h: ptr QQmlContext
    ownsCpp: bool

  View* = ref object of RootObj
    h: ptr QQuickView
    ownsCpp: bool

  Item* = ref object of RootObj
    h: ptr QQuickItem
    ownsCpp: bool

  Window* = ref object of RootObj
    h: ptr QQuickWindow
    ownsCpp: bool

  Status* = enum
    stNull, stReady, stLoading, stError

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

proc toStatus(c: cint): Status =
  case c
  of 0: stNull
  of 1: stReady
  of 2: stLoading
  of 3: stError
  else: stNull

proc errorsToNim(l: QStringList): seq[string] =
  result = @[]
  for i in 0 ..< slSize(l):
    result.add(slAt(l, i).toString())

proc assertNotNil(p: pointer; what: string) =
  if p.isNil:
    raise newException(ValueError, "nimqt: nil " & what)

# ---------------------------------------------------------------------------
# Url / Size / Color / Image — thin Nim-friendly value wrappers
# ---------------------------------------------------------------------------

type
  Url* = object
    h: QUrl
  Size* = object
    w, h: float64

proc newUrl*(s: string = ""): Url {.inline.} =
  if s.len == 0: Url(h: qurlNewEmpty())
  else: Url(h: qurlFromString(toQString(s)))

proc urlFromFile*(path: string): Url {.inline.} =
  Url(h: qurlFromLocalFile(path))

proc toString*(u: Url): string {.inline.} = urlToString(u.h).toString()
proc `$`*(u: Url): string {.inline.} = u.toString()
proc isValid*(u: Url): bool {.inline.} = urlIsValid(u.h)
proc isEmpty*(u: Url): bool {.inline.} = urlIsEmpty(u.h)
proc isLocalFile*(u: Url): bool {.inline.} = urlIsLocalFile(u.h)
proc toLocalFile*(u: Url): string {.inline.} = urlToLocalFile(u.h).toString()

proc raw*(u: Url): QUrl {.inline.} = u.h

proc newSize*(w, h: float64): Size {.inline.} = Size(w: w, h: h)
proc width*(s: Size): float64 {.inline.} = s.w
proc height*(s: Size): float64 {.inline.} = s.h

# ---------------------------------------------------------------------------
# Application (QGuiApplication)
# ---------------------------------------------------------------------------

proc newApplication*(): Application =
  ## Constructs the singleton QGuiApplication (idempotent via shim).
  result = Application()
  result.h = qguiappNewShim()
  result.ownsCpp = false   # shim owns it; deliberately leaked at exit

proc exec*(app: Application): int =
  int(appExecStatic(QCoreApplication))

proc quit*(app: Application) =
  appQuitStatic(QCoreApplication)

proc processEvents*() =
  processEventsAll()

{.pop.}
# ---------------------------------------------------------------------------
# Engine (QQmlEngine)
# ---------------------------------------------------------------------------

proc newEngine*(): Engine =
  result = Engine()
  result.h = qqmlengineNew(nil)
  result.ownsCpp = true

proc raw*(e: Engine): ptr QQmlEngine {.inline.} = e.h

proc rootContext*(e: Engine): Context =
  ## NOT owned by Nim (engine owns it).
  result = Context()
  result.h = engineRootContext(e.h)
  result.ownsCpp = false

proc addImportPath*(e: Engine; path: string) =
  engineAddImportPath(e.h, toQString(path))

proc trimComponentCache*(e: Engine) = engineTrimComponentCache(e.h)
proc clearComponentCache*(e: Engine) = engineClearComponentCache(e.h)
proc collectGarbage*(e: Engine) = engineCollectGarbage(e.h)

# ---------------------------------------------------------------------------
# Component (QQmlComponent)
# ---------------------------------------------------------------------------

proc newComponentFromString*(e: Engine; data: string;
                             baseUrl: Url = newUrl()): Component =
  ## Loads QML from string via QQmlComponent::setData — the documented API.
  ## Note: `data` must start cleanly (no leading newline before `import`).
  result = Component()
  result.h = componentNew(e.h)
  compSetData(result.h, toQString(data).toUtf8Raw(), baseUrl.raw)
  result.ownsCpp = true

proc newComponentFromUrl*(e: Engine; url: Url): Component =
  result = Component()
  result.h = componentNewUrl(e.h, url.raw)
  result.ownsCpp = true

proc raw*(c: Component): ptr QQmlComponent {.inline.} = c.h

proc status*(c: Component): Status = toStatus(compStatus(c.h))

proc errors*(c: Component): seq[string] = errorsToNim(compErrorsShim(c.h))

import strutils

proc errorsString*(c: Component): string =
  c.errors().join("\n")

proc createObject*(c: Component; parentCtx: Context = nil): Item =
  ## Synchronous creation. Returns nil on failure (check status/errors).
  let obj = compCreateSync(c.h, if parentCtx.isNil: nil else: parentCtx.h)
  if obj.isNil: return nil
  result = Item()
  # QQmlComponent::create gives JavaScriptOwnership-with-parent semantics:
  # the object is owned by QML once it has a context/parent. We treat it as
  # not-owned unless it has no QObject parent at all.
  result.h = cast[ptr QQuickItem](obj)
  result.ownsCpp = objParent(obj).isNil

proc createAsyncStart*(c: Component; ctx: Context = nil): pointer =
  compCreateAsyncStart(c.h, if ctx.isNil: nil else: ctx.h)

proc createAsyncResult*(handle: pointer): Item =
  let obj = compAsyncResult(handle)
  if obj.isNil: return nil
  result = Item()
  result.h = cast[ptr QQuickItem](obj)
  result.ownsCpp = objParent(obj).isNil

# ---------------------------------------------------------------------------
# Context (QQmlContext)
# ---------------------------------------------------------------------------

proc wrapContext(h: ptr QQmlContext; owns: bool): Context =
  result = Context()
  result.h = h
  result.ownsCpp = owns

proc raw*(ctx: Context): ptr QQmlContext {.inline.} = ctx.h

proc setContextProperty*(ctx: Context; name: string; v: Variant) =
  contextSetContextPropertyVariant(ctx.h, toQString(name), v.deref())

proc setContextPropertyObj*(ctx: Context; name: string; o: QObjectLike) =
  assertNotNil(o.cppHandle(), "exposed object handle")
  contextSetContextPropertyObj(ctx.h, toQString(name), o.cppHandle())

proc setContextPropertyObj*(ctx: Context; name: string; o: ptr QObject) =
  contextSetContextPropertyObj(ctx.h, toQString(name), o)

proc resolvedUrl*(ctx: Context; u: Url): Url =
  Url(h: contextResolvedUrl(ctx.h, u.raw))

# ---------------------------------------------------------------------------
# View (QQuickView)
# ---------------------------------------------------------------------------

proc newView*(): View =
  result = View()
  result.h = qquickviewNewDefault()
  result.ownsCpp = true

proc newViewWithEngine*(e: Engine): View =
  result = View()
  result.h = qquickviewNewEngine(e.h, nil)
  result.ownsCpp = true

proc raw*(v: View): ptr QQuickView {.inline.} = v.h

proc setSource*(v: View; url: Url) = viewSetSource(v.h, url.raw)
proc source*(v: View): Url = Url(h: viewSourceUrl(v.h))
proc status*(v: View): Status = toStatus(viewStatusRaw(v.h))
proc errors*(v: View): seq[string] = errorsToNim(viewErrorsShim(v.h))
proc errorsString*(v: View): string = v.errors().join("\n")

proc rootObject*(v: View): Item =
  let it = viewRootObjectRaw(v.h)
  if it.isNil: return nil
  result = Item()
  result.h = it
  result.ownsCpp = false     # view owns its root item

proc engine*(v: View): Engine =
  result = Engine()
  result.h = viewEngineRaw(v.h)
  result.ownsCpp = false     # view owns its engine

proc show*(v: View) = viewShowWin(v.h)
proc showFullScreen*(v: View) = winShowFullScreen(cast[ptr QWindow](v.h))
proc resize*(v: View; w: int; h: int) = viewResizeWin(v.h, cint(w), cint(h))
proc width*(v: View): int = int(viewW(v.h))
proc height*(v: View): int = int(viewH(v.h))
proc title*(v: View): string = winTitle(cast[ptr QWindow](v.h)).toString()
proc setTitle*(v: View; s: string) = viewSetTitleWin(v.h, toQString(s))
proc closeView*(v: View) = viewCloseWin(v.h)

# ---------------------------------------------------------------------------
# Item / Window — generic property bridge + typed accessors
# ---------------------------------------------------------------------------

proc raw*(i: Item): ptr QQuickItem {.inline.} = i.h

template cppQObject(o: Item): ptr QObject = cast[ptr QObject](o.h)
template cppQObject(o: Window): ptr QObject = cast[ptr QObject](o.h)

proc cppHandleRaw*(o: Item): ptr QObject {.inline.} = cast[ptr QObject](o.h)
proc cppHandleRaw*(o: Window): ptr QObject {.inline.} = cast[ptr QObject](o.h)

proc propertyValue*(o: Item; name: string): Variant =
  newVariantFromRaw(qmlpropRead(cppQObject(o), toQString(name)))

proc setPropertyValue*(o: Item; name: string; v: Variant) =
  discard qmlpropWrite(cppQObject(o), toQString(name), v.deref())

proc propertyValue*(o: Window; name: string): Variant =
  newVariantFromRaw(qmlpropRead(cppQObject(o), toQString(name)))

proc setPropertyValue*(o: Window; name: string; v: Variant) =
  discard qmlpropWrite(cppQObject(o), toQString(name), v.deref())

proc nimqtInvokeDbg*(o: ptr QObject; name: cstring; args: ptr QVariant;
                    argc: cint; retOut: ptr QVariant): cint
  {.importc: "nimqt_invoke_method_dbg".}

proc nimqtInvokeMethodRaw(o: ptr QObject; name: cstring; args: ptr QVariant;
                          argc: cint; retOut: ptr QVariant): bool
  {.importc: "nimqt_invoke_method_c".}
proc nimqtInvokeMethodP(o: ptr QObject; name: cstring; args: ptr ptr QVariant;
                          argc: cint; retOut: ptr QVariant): bool
  {.importc: "nimqt_invoke_method_p".}

proc invokeMethodV*(o: Item; name: string; args: varargs[Variant]): Variant =
  var argv: array[10, QVariant]
  let n = min(args.len, argv.len)
  for i in 0 ..< n: argv[i] = args[i].deref()
  var retOut = qvariantNewInvalid()[]
  let ok = nimqtInvokeMethodRaw(cppQObject(o), name.cstring, addr argv[0],
                                cint(n), addr retOut)
  result = if ok: newVariantFromRaw(retOut) else: newVariant()

proc invokeMethodV*(o: Window; name: string; args: varargs[Variant]): Variant =
  var ptrs: array[10, ptr QVariant]
  let n = min(args.len, ptrs.len)
  for i in 0 ..< n: ptrs[i] = args[i].rawPtr
  var retOut = qvariantNewInvalid()[]
  let ok = nimqtInvokeMethodP(cppQObject(o), name.cstring,
                              cast[ptr ptr QVariant](addr ptrs[0]), cint(n),
                              addr retOut)
  # Keep varargs temps alive across the FFI call: copying the refs into a
  # seq retains them even if the caller's temporaries are destroyed.
  let keptAlive: seq[Variant] = @args
  result = if ok: newVariantFromRaw(retOut) else: newVariant()

proc invokeMethodV*(o: ptr QObject; name: string; args: varargs[Variant]): Variant =
  ## Invokes methods on any QObject (e.g. an exposed object's cppHandle()).
  var ptrs: array[10, ptr QVariant]
  let n = min(args.len, ptrs.len)
  for i in 0 ..< n: ptrs[i] = args[i].rawPtr
  var retOut = qvariantNewInvalid()[]
  let ok = nimqtInvokeMethodP(o, name.cstring,
                              cast[ptr ptr QVariant](addr ptrs[0]), cint(n),
                              addr retOut)
  result = if ok: newVariantFromRaw(retOut) else: newVariant()

proc connectSignal*(o: Item; signal: string; cb: SignalCb): ConnectionId =
  connectSignalImpl(cppQObject(o), signal, cb)

proc connectSignal*(o: Window; signal: string; cb: SignalCb): ConnectionId =
  connectSignalImpl(cppQObject(o), signal, cb)

proc connectSignal*(o: ptr QObject; signal: string; cb: SignalCb): ConnectionId =
  ## Bind a signal from any QObject pointer (e.g. QTimer::timeout,
  ## QCoreApplication::aboutToQuit, custom QObject::destroyed).
  connectSignalImpl(o, signal, cb)

proc childItems*(o: Item): seq[Item] =
  result = @[]
  let l = itemChildItems(o.h)
  for idx in 0 ..< listqitemSize(l):
    let ch = listqitemAt(l, idx)
    var w = Item(); w.h = ch; w.ownsCpp = false
    result.add(w)

proc findChildByName*(o: Item; name: string): Item =
  ## Recursive objectName search among child items.
  proc rec(it: ptr QQuickItem): ptr QQuickItem =
    let l = itemChildItems(it)
    for idx in 0 ..< listqitemSize(l):
      let ch = listqitemAt(l, idx)
      if objObjectName(cast[ptr QObject](ch)).toString() == name:
        return ch
      let deep = rec(ch)
      if not deep.isNil: return deep
    return nil
  let found = rec(o.h)
  if found.isNil: return nil
  result = Item(); result.h = found; result.ownsCpp = false

proc grabToImage*(o: Item; targetSize: Size = newSize(0, 0)): bool =
  ## Requests a grab; returns whether the request was accepted.
  let sz = qsizeNew(cint(targetSize.w), cint(targetSize.h))
  let res = itemGrabToImage(o.h, sz)
  result = not res.isNil

# ---- typed accessors ---------------------------------------------------------

proc x*(o: Item): float64 = itemX(o.h)
proc `x=`*(o: Item; v: float64) = itemSetX(o.h, v)
proc y*(o: Item): float64 = itemY(o.h)
proc `y=`*(o: Item; v: float64) = itemSetY(o.h, v)
proc z*(o: Item): float64 = itemZ(o.h)
proc `z=`*(o: Item; v: float64) = itemSetZ(o.h, v)
proc widthF*(o: Item): float64 = itemWidth(o.h)
proc `widthF=`*(o: Item; v: float64) = itemSetWidth(o.h, v)
proc heightF*(o: Item): float64 = itemHeight(o.h)
proc `heightF=`*(o: Item; v: float64) = itemSetHeight(o.h, v)
proc visible*(o: Item): bool = isVisibleItem(o.h)
proc `visible=`*(o: Item; b: bool) = itemSetVisible(o.h, b)
proc rotation*(o: Item): float64 = itemRotation(o.h)
proc `rotation=`*(o: Item; v: float64) = itemSetRotation(o.h, v)
proc opacity*(o: Item): float64 = itemOpacity(o.h)
proc `opacity=`*(o: Item; v: float64) = itemSetOpacity(o.h, v)
proc scaleF*(o: Item): float64 = itemScale(o.h)
proc `scaleF=`*(o: Item; v: float64) = itemSetScale(o.h, v)

proc rawHandle*(v: View): ptr QQuickView {.inline.} =
  ## Raw QQuickView. Needed for a synchronous framebuffer grab
  ## (QQuickWindow::grabWindow), which the bool-returning grabToImage wrapper
  ## cannot express.
  v.h

proc rawHandle*(o: Item): ptr QQuickItem {.inline.} =
  ## Raw QQuickItem.
  o.h

proc parentItem*(o: Item): Item =
  let p = itemParentItem(o.h)
  if p.isNil: return nil
  result = Item(); result.h = p; result.ownsCpp = false

# ---------------------------------------------------------------------------
# JsValue (high-level ref over QJSValue)
# ---------------------------------------------------------------------------

type
  JsValueObj = object
    h: QJSValue
    valid: bool
  JsValue* = ref JsValueObj

proc disposeQt*(x: var JsValueObj) =
  ## Explicit Qt-side release; not wired as =destroy until dtor binding
  ## ABI is validated (see t_ecmascript investigation).
  if x.valid:
    jsvalueDestroy(x.h)
    x.valid = false
proc jsUndefined*(): JsValue =
  new(result); result.h = jsvalueNewUndefined(); result.valid = true

proc jsFromInt*(i: int): JsValue =
  new(result); result.h = jsvalueFromIntV(cint(i)); result.valid = true

proc jsFromFloat*(f: float): JsValue =
  new(result); result.h = jsvalueFromDoubleV(cdouble(f)); result.valid = true

proc jsFromString*(s: string): JsValue =
  new(result); result.h = jsvalueFromStringV(toQString(s)); result.valid = true

proc jsFromBool*(b: bool): JsValue =
  new(result); result.h = jsvalueFromBoolV(b); result.valid = true

proc rawJsv*(j: JsValue): QJSValue {.inline.} = j[].h

proc isUndefined*(j: JsValue): bool = jsIsUndefined(j.h)
proc isNullJ*(j: JsValue): bool = jsIsNull(j.h)
proc isError*(j: JsValue): bool = jsIsError(j.h)
proc isArray*(j: JsValue): bool = jsIsArray(j.h)
proc isObject*(j: JsValue): bool = jsIsObject(j.h)
proc isCallable*(j: JsValue): bool = jsIsCallable(j.h)
proc isNumberJ*(j: JsValue): bool = jsIsNumber(j.h)
proc isStringJ*(j: JsValue): bool = jsIsStringV(j.h)

proc toString*(j: JsValue): string = jsToString(j.h).toString()
proc toNumber*(j: JsValue): float = float(jsToNumber(j.h))
proc toBoolJ*(j: JsValue): bool = jsToBool(j.h)
proc toInt32J*(j: JsValue): int32 = int32(jsToInt(j.h))

proc `$`*(j: JsValue): string = j.toString()

proc call*(j: JsValue; args: varargs[JsValue]): JsValue =
  ## Args live in fixed stack storage for the duration of the call; the
  ## C++ shim copy-constructs each into the QJSValueList (no Nim-side
  ## bycopy Qt values in seqs — that ABI mix corrupts heaps).
  var store {.noinit.}: array[10, QJSValue]
  var ptrs {.noinit.}: array[10, ptr QJSValue]
  var n = 0
  for a in args:
    if n < 10 and not a.isNil:
      store[n] = a.h
      ptrs[n] = addr store[n]
      inc n
  new(result)
  if n == 0:
    result.h = jsCallShimP(addr j.h, nil, 0)
  else:
    result.h = jsCallShimP(addr j.h, cast[ptr ptr QJSValue](addr ptrs[0]), cint(n))
  result.valid = true

proc property*(j: JsValue; name: string): JsValue =
  new(result)
  result.h = jsPropertyGet(j.h, toQString(name))
  result.valid = true

# ---------------------------------------------------------------------------
# Engine JS helpers
# ---------------------------------------------------------------------------

proc evaluateJs*(e: Engine; program: string; fileName: string = ""): JsValue =
  new(result)
  result.h = jsEngineEvaluate(e.h, toQString(program), toQString(fileName))
  result.valid = true

proc globalObject*(e: Engine): JsValue =
  new(result)
  result.h = jsEngineGlobalObject(e.h)
  result.valid = true

proc newArray*(e: Engine; len: int = 0): JsValue =
  new(result)
  result.h = jsEngineNewArrayShim(e.h, cuint(len))
  result.valid = true

proc newJsObject*(e: Engine): JsValue =
  new(result)
  result.h = jsEngineNewObject(e.h)
  result.valid = true

# ---------------------------------------------------------------------------
# Lifecycle hooks
# ---------------------------------------------------------------------------
# Nim does not allow `=destroy` on ref object types directly; we instead
# register per-type cleanup through the GC by attaching destructor procs to
# the underlying record types via `{.final.}`-style hooks is unavailable —
# so we expose explicit free() procedures plus finalizer registration.

proc engineFreeRaw(e: ptr QQmlEngine) {.importc: "nimqt_engine_free".}
proc nimqtComponentDispose(c: ptr QQmlComponent) {.importc: "nimqt_component_dispose".}
proc nimqtViewCloseAndFree(v: ptr QQuickView) {.importc: "nimqt_view_close_and_free".}

proc free*(e: Engine) =
  if e.ownsCpp and e.h != nil:
    engineFreeRaw(e.h)
    e.h = nil

proc free*(c: Component) =
  if c.ownsCpp and c.h != nil:
    nimqtComponentDispose(c.h)
    c.h = nil

proc free*(ctx: Context) =
  if ctx.ownsCpp and ctx.h != nil:
    contextDispose(ctx.h)
    ctx.h = nil

proc free*(v: View) =
  if v.ownsCpp and v.h != nil:
    nimqtViewCloseAndFree(v.h)
    v.h = nil

