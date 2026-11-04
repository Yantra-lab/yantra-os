# nimqt — Shared Interface Contract (v1)

All subagents MUST code exactly against these signatures. File ownership is exclusive:
never edit a file you do not own. If something here is impossible, note it in your
report instead of deviating silently.

## Module layout (src/nimqt/)

    QtCore.nim      low-level {.importcpp.} bindings: QtCore
    QtGui.nim       low-level bindings: QtGui (QGuiApplication, QWindow, QColor, QFont, QImage)
    shim.nim        C++ helper declarations (QMetaObjectBuilder bridge, trampoline invoke)
    marshaling.nim  Variant <-> Nim conversion (toVariant/fromVariant)
    signals.nim     QMetaObject builder + connect/disconnect + Nim closure slots
    QtQml.nim       low-level bindings: QQmlEngine, QQmlComponent, QQmlContext,
                    QQmlProperty, QJSValue, QQmlApplicationEngine
    QtQuick.nim     low-level bindings: QQuickView, QQuickItem, QQuickWindow,
                    grabToImage etc.
    wrappers.nim    high-level ref object API (the names below)
    nimqt.nim       umbrella: exports QtCore, QtGui, QtQml, QtQuick, wrappers, marshaling

## Low-level conventions

- Every class is `{ .importcpp: "QObject", header: "<QObject>", inheritable. }`
  type QObject* {.importcpp, header, inheritable.} = distinct object — pointers only.
- Pointers are `ptr X`. No Nim finalizers on low-level types.
- QString/QByteArray appear ONLY inside QtCore.nim internals; the public wrapper
  layer uses Nim `string`.
- Method pattern:
  proc setParent*(self: ptr QObject; parent: ptr QObject)
    {.importcpp: "setParent", header: "<QObject>".}
- Static/ctor pattern uses `QtObject.newX(...)` style:
  proc newX*(typ: typedesc[QString]): ptr QString
    {.importcpp: "new QString", constructor: on.}
  Overloads: newXStr (const char*), newQUtf8String(QChar*, int)... keep one
  canonical name per signature, suffix by distinguishing type (e.g. newQVariantInt).
- Include path root is `<QTDIR>/include/qt6`; modules add their own subdir
  (`<QTDIR>/include/qt6/QtCore` etc.) — handled centrally in config/nimcfg.

## High-level wrapper API (wrappers.nim) — AUTHORITATIVE SIGNATURES

```nim
type
  Application* = ref object of RootObj   # wraps QGuiApplication*
    h: ptr QGuiApplication
    argvStore: seq[string]
    argvPtrs: array[16, cstring]         # stable storage for argv
    argcv: cint
  Engine* = ref object of RootObj        # wraps QQmlEngine*
    h: ptr QQmlEngine
  Component* = ref object of RootObj     # wraps QQmlComponent*
    h: ptr QQmlComponent
    ownsCpp: bool                        # false when wrapping createObject result owner
  Context* = ref object of RootObj       # wraps QQmlContext*
    h: ptr QQmlContext
    ownsCpp: bool
  View* = ref object of RootObj          # wraps QQuickView*
    h: ptr QQuickView
  Item* = ref object of RootObj          # wraps QQuickItem*
    h: ptr QQuickItem
  Window* = ref object of RootObj        # wraps QQuickWindow*
    h: ptr QQuickWindow

# Application
proc newApplication*(argv: seq[string] = @[]): Application
proc exec*(app: Application): int                  # runs event loop
proc quit*(app: Application)                       # QGuiApplication::quit
proc exit*(app: Application; code: int = 0)
proc processEvents*()                               # QCoreApplication::processEvents
proc aboutToQuitConnect*(app: Application; cb: proc())  # via signals layer

# Engine
proc newEngine*(): Engine                          # parent nil
proc rootContext*(e: Engine): Context              # NOT owned
proc loadUrl*(e: Engine; url: Url): void
proc trimComponentCache*(e: Engine): void
proc collectGarbage*(e: Engine): void

# Component
proc newComponentFromString*(e: Engine; data: string; baseUrl: Url = newUrl()): Component
proc newComponentFromUrl*(e: Engine; url: Url): Component
proc status*(c: Component): Status                 # Status = enum Null, Ready, Loading, Error
proc errorsString*(c: Component): string           # joined toString() lines
proc createObject*(c: Component; parentCtx: Context = nil): Item  # may return nil
proc objectCreatedConnect*(c: Component; cb: proc(obj: RootRef; url: Url)) # async create

# Context
proc setContextProperty*(ctx: Context; name: string; v: Variant): void
proc setContextPropertyObj*(ctx: Context; name: string; o: QObjectLike): void
proc contextObject*(ctx: Context): QObjectLike

# View
proc newView*(): View                              # QQuickView default ctor
proc setSource*(v: View; url: Url): void
proc status*(v: View): Status
proc errorsString*(v: View): string
proc rootObject*(v: View): Item                    # may be nil
proc show*(v: View): void
proc showFullScreen*(v: View): void
proc resize*(v: View; w: int; h: int): void
proc width*(v: View): int
proc height*(v: View): int
proc title*(v: View): string
proc setTitle*(v: View; s: string): void

# Item / Window property bridge (all go through QQmlProperty or metaobject)
proc propertyValue*(o: Item or Window; name: string): Variant
proc setPropertyValue*(o: Item or Window; name: string; v: Variant): void
proc invokeMethod*(o: Item or Window; name: string; args: varargs[Variant]): Variant
proc childItems*(o: Item): seq[Item]
proc findChildByName*(o: Item or Window; name: string): Item
proc grabToImage*(o: Item; targetSize: Size = newSize(0,0)): bool  # callback variant below
proc grabCallback*(o: Item; cb: proc(img: Image)): void
proc x*(o: Item): float32; proc `x=`*(o: Item; v: float32): void
proc y*(o: Item): float32; proc `y=`*(o: Item; v: float32): void
proc widthF*(o: Item): float32; proc `widthF=`*(o: Item; v: float32): void
proc heightF*(o: Item): float32; proc `heightF=`*(o: Item; v: float32): void
proc visible*(o: Item): bool; proc `visible=`*(o: Item; b: bool): void
proc rotation*(o: Item): float32; proc `rotation=`*(o: Item; v: float32): void
proc opacity*(o: Item): float32; proc `opacity=`*(o: Item; v: float32): void

# Variant
type Variant* = object                             # value type wrapping QVariant bytes
proc newVariantNil*(): Variant
proc newVariantBool*(b: bool): Variant
proc newVariantInt*(i: int32): Variant
proc newVariantFloat*(f: cdouble): Variant
proc newVariantString*(s: string): Variant
proc newVariantUrl*(u: Url): Variant
proc isValid*(v: Variant): bool
proc typeName*(v: Variant): string                 # "" if invalid
proc toString*(v: Variant): string
proc toInt*(v: Variant): int32
proc toFloat*(v: Variant): cdouble
proc toBool*(v: Variant): bool
proc toJsValue*(v: Variant; e: Engine): JsValue
proc `$`*(v: Variant): string                      # alias of toString

# JsValue
type JsValue* = ref object                         # heap QJSValue
proc newJsValue*(): JsValue                        # undefined
proc jsFromInt*(i: int): JsValue
proc jsFromFloat*(f: float): JsValue
proc jsFromString*(s: string): JsValue
proc jsFromBool*(b: bool): JsValue
proc isUndefined*(j: JsValue): bool
proc isNull*(j: JsValue): bool
proc isError*(j: JsValue): bool
proc isCallable*(j: JsValue): bool
proc toString*(j: JsValue): string
proc toNumber*(j: JsValue): float
proc toBool*(j: JsValue): bool
proc toInt32*(j: JsValue): int32
proc call*(j: JsValue; args: varargs[JsValue]): JsValue
proc property*(j: JsValue; name: string): JsValue
proc `$`*(j: JsValue): string

# Url / Size / Color / Font / Image thin wrappers (also in wrappers.nim)
type
  Url* = object            # value semantics over QUrl
  Size* = object           # QSizeF
  Color* = object          # QColor
  Image* = ref object      # QImage (ref, manual lifetime via GC hook)
proc newUrl*(s: string = ""): Url
proc toString*(u: Url): string
proc newSize*(w, h: float32): Size
proc newColor*(name: string): Color
proc newImage*(): Image
proc savePng*(img: Image; path: string): bool
```

## Signals/slots (signals.nim)

```nim
type QObjectLike* = ref object of RootObj  # Nim-side base for exposed objects
  cpp: pointer                             # ptr QObject created by metaobject builder
  mo: pointer                              # built QMetaObject

proc connectSignal*(sender: QObjectLike or Item or Window or Component;
                    signal: string; cb: proc(args: seq[Variant])): ConnectionId
proc disconnectSlot*(id: ConnectionId): bool
# Implementation: QMetaObjectBuilder defines a dynamic slot named "_nq_slotN"
# (signature "void _nq_slotN(QVariantList)" is FORBIDDEN — QVariantList is not
# a metatype on all builds; use single QVariant arg holding a QVariantMap with
# keys "a0".."aN") and routes into a Nim closure table.
```

## marshaling.nim

```nim
converter toVariant*(s: string): Variant
converter toVariant*(b: bool): Variant
converter toVariant*(i: int32): Variant
converter toVariant*(f: float64): Variant
proc fromVariant*[T](v: Variant; t: typedesc[T]): T
```

## Error handling rules

- `createObject`, `setSource`, `loadUrl` never raise; they mirror Qt: check
  `.status` / `.errorsString`. `assertReady(c)` helper raises `NimQtError` only
  in tests.
- `objectCreated(bool, QUrl)` maps to callback `(obj: RootRef-or-nil, url)`.

## Ownership rules (binding-wide)

1. QObject with parent: NEVER deleted from Nim.
2. Wrappers own their C++ object unless `ownsCpp == false`
   (rootContext(), rootObject(), createObject results owned by engine/context).
3. `=destroy` on high-level types deletes only if ownsCpp.
4. Application outlives everything; deleting it is a programming error → we leak
   it deliberately (documented).

## Testing hooks

- `proc qtVersionMajor*(): int` returns 6 (compile-time constant from headers).
- All tests set `QT_QPA_PLATFORM=offscreen` before `newApplication`.
