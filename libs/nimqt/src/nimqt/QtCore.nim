## nimqt — Low-level Qt6 Core bindings ({.importcpp.}).
##
## Conventions (see INTERFACE.md):
## * Polymorphic C++ classes (QObject & friends) are handled exclusively via
##   `ptr` in Nim. Importcpp patterns dereference explicitly (`#->`, `(*#)`)
##   so nothing is ever sliced.
## * C++ value classes (QString, QVariant, QUrl ...) are `{.bycopy.}` and are
##   passed/returned by value, mirroring the C++ ABI exactly.
## * QString <-> string conversions go through shim.cpp so that no temporary
##   QByteArray can dangle between two FFI calls.
## * `const char*` results (metaobject names/signatures) point into Qt's own
##   static data and are converted immediately to Nim string.

when not defined(nimqtQtCore):
  {.push hint[XDeclaredButNotUsed]: off.}

const nimqtQtCore* = true

{.compile: "shim.cpp".}

type
  QObject* {.importcpp: "QObject", header: "<QObject>", inheritable,
             pure.} = object
  QCoreApplication* {.importcpp: "QCoreApplication",
                      header: "<QCoreApplication>", inheritable, pure.} = object
  QTimer* {.importcpp: "QTimer", header: "<QTimer>", pure.} = object
  QEventLoop* {.importcpp: "QEventLoop", header: "<QEventLoop>", pure.} = object

  QString* {.importcpp: "QString", header: "<QString>", bycopy, pure.} = object
  QByteArray* {.importcpp: "QByteArray", header: "<QByteArray>", bycopy,
                pure.} = object
  QVariant* {.importcpp: "QVariant", header: "<QVariant>", bycopy, pure.} = object
  QUrl* {.importcpp: "QUrl", header: "<QUrl>", bycopy, pure.} = object
  QStringList* {.importcpp: "QStringList", header: "<QStringList>", bycopy,
                 pure.} = object
  QVariantList* {.importcpp: "QVariantList", header: "<QVariant>", bycopy,
                  pure.} = object
  QVariantMap* {.importcpp: "QVariantMap", header: "<QVariant>", bycopy,
                 pure.} = object

  QMetaObject* {.importcpp: "QMetaObject", header: "<QMetaObject>", pure.} = object
  QMetaMethod* {.importcpp: "QMetaMethod", header: "<QMetaMethod>", bycopy,
                 pure.} = object
  QMetaProperty* {.importcpp: "QMetaProperty", header: "<QMetaProperty>",
                   bycopy, pure.} = object
  QMetaEnum* {.importcpp: "QMetaEnum", header: "<QMetaEnum>", bycopy, pure.} = object
  QMetaObjectConnection* {.importcpp: "QMetaObject::Connection",
                           header: "<QObject>", bycopy, pure.} = object

  QPointF* {.importcpp: "QPointF", header: "<QPointF>", bycopy, pure.} = object
  QSizeF* {.importcpp: "QSizeF", header: "<QSizeF>", bycopy, pure.} = object
  QRectF* {.importcpp: "QRectF", header: "<QRectF>", bycopy, pure.} = object

const
  QtHighEventPriority* = cint(1000)
  QtNormalEventPriority* = cint(0)
  QtLowEventPriority* = cint(-1000)

# ---------------------------------------------------------------------------
# shim.cpp bridge: UTF-safe QString conversions
# ---------------------------------------------------------------------------

proc shimQStrUtf8Size*(s: QString): cint {.importc: "nimqt_qstr_utf8_size".}
proc shimQStrUtf8Copy*(s: QString; buf: ptr char) {.importc: "nimqt_qstr_utf8_copy".}

proc toString*(s: QString): string =
  ## QString -> Nim string (UTF-8). Exception-safe copy through shim.
  let n = int(shimQStrUtf8Size(s))
  if n <= 0: return ""
  result = newString(n + 1)   # room for NUL guard
  shimQStrUtf8Copy(s, result[0].addr)
  result[n] = '\0'
  result.setLen(n)

proc toQString*(s: cstring): QString {.importcpp: "QString::fromUtf8(#)",
                                        header: "<QString>".}
proc toUtf8Raw*(s: QString): QByteArray {.importcpp: "#.toUtf8()",
                                          header: "<QString>".}
proc `$`*(s: QString): string {.inline.} = toString(s)

# ---------------------------------------------------------------------------
# QString extras
# ---------------------------------------------------------------------------

proc qsIsEmpty*(s: QString): bool {.importcpp: "#.isEmpty()", header: "<QString>".}
proc qsSize*(s: QString): cint {.importcpp: "#.size()", header: "<QString>".}
proc qsAt*(s: QString; i: cint): QString {.importcpp: "#.at(#)", header: "<QString>".}
proc qsArg*(s: QString; a: QString): QString {.importcpp: "#.arg(#)",
                                               header: "<QString>".}
proc qsEquals*(a: QString; b: QString): bool {.importcpp: "(# == #)",
                                               header: "<QString>".}
proc qsPlus*(a: QString; b: QString): QString {.importcpp: "(# + #)",
                                             header: "<QString>".}
proc qsCompare*(a: QString; b: QString): cint {.importcpp: "#.compare(#)",
                                                header: "<QString>".}

# Nim-side convenience operators (forward to C++ via importcpp above).
proc `==`*(a, b: QString): bool {.inline.} = qsEquals(a, b)

# ---------------------------------------------------------------------------
# QByteArray (internal)
# ---------------------------------------------------------------------------

proc qbaSize*(b: QByteArray): cint {.importcpp: "#.size()", header: "<QByteArray>".}

# ---- New high-level QObject helpers (constructor + name convenience) ----
type NewQObjectResult* = object
  h*: ptr QObject

proc newQObjectRaw*(): ptr QObject {.importcpp: "new QObject()",
    header: "<QObject>".}
proc newQObject*(): NewQObjectResult =
  ## Convenience constructor for a top-level QObject (Nim wrapper
  ## around `new QObject()`; replaces the missing nimqt helper).
  result = NewQObjectResult(h: newQObjectRaw())

# QObject::delete() — explicit ownership drop (paired with newQObject).
proc objDelete*(o: ptr QObject) {.importcpp: "delete #", header: "<QObject>".}

proc objDeleteLater*(o: ptr QObject) {.importcpp: "#->deleteLater()",
                                       header: "<QObject>".}
proc objParent*(o: ptr QObject): ptr QObject {.importcpp: "#->parent()",
                                               header: "<QObject>".}
proc objSetParent*(o: ptr QObject; p: ptr QObject) {.importcpp: "#->setParent(#)",
                                                     header: "<QObject>".}
proc objObjectName*(o: ptr QObject): QString {.importcpp: "#->objectName()",
                                               header: "<QObject>".}
proc objSetObjectName*(o: ptr QObject; name: QString) {.importcpp: "#->setObjectName(#)",
                                                        header: "<QObject>".}
proc objMetaObject*(o: ptr QObject): ptr QMetaObject {.importcpp: "#->metaObject()",
                                                       header: "<QObject>".}
proc objBlockSignals*(o: ptr QObject; blocked: bool): bool {.importcpp: "#->blockSignals(#)",
    header: "<QObject>".}
proc objSignalsBlocked*(o: ptr QObject): bool {.importcpp: "#->signalsBlocked()",
    header: "<QObject>".}
proc objProperty*(o: ptr QObject; name: cstring): QVariant {.importcpp: "#->property(#)",
    header: "<QObject>".}
proc objSetProperty*(o: ptr QObject; name: cstring; v: QVariant): bool {.importcpp:
    "#->setProperty(#, #)", header: "<QObject>".}
proc objChildrenCount*(o: ptr QObject): cint {.importcpp: "(int)#->children().size()",
    header: "<QObject>".}
proc objDispose*(o: ptr QObject) {.importcpp: "delete #", header: "<QObject>".}

proc connIsValid*(c: QMetaObjectConnection): bool
  {.importcpp: "#.isValid()", header: "<QObject>".}
proc connDispose*(c: QMetaObjectConnection)
  {.importcpp: "{ auto tmp_ = #; tmp_.~Connection(); }", header: "<QObject>".}

# ---------------------------------------------------------------------------
# QMetaObject / QMetaMethod / QMetaProperty
# ---------------------------------------------------------------------------

proc nimqtMoClassName(m: ptr QMetaObject): QString {.importc: "nimqt_mo_class_name".}
proc moClassName*(m: ptr QMetaObject): string {.inline.} =
  nimqtMoClassName(m).toString()

proc moSuperClass*(m: ptr QMetaObject): ptr QMetaObject {.importcpp: "#->superClass()",
    header: "<QMetaObject>".}
proc moMethodCount*(m: ptr QMetaObject): cint {.importcpp: "#->methodCount()",
    header: "<QMetaObject>".}
proc moMethodOffset*(m: ptr QMetaObject): cint {.importcpp: "#->methodOffset()",
    header: "<QMetaObject>".}
proc moIndexOfMethod*(m: ptr QMetaObject; sig: cstring): cint {.importcpp: "#->indexOfMethod(#)",
    header: "<QMetaObject>".}
proc moIndexOfSignal*(m: ptr QMetaObject; sig: cstring): cint {.importcpp: "#->indexOfSignal(#)",
    header: "<QMetaObject>".}
proc moIndexOfSlot*(m: ptr QMetaObject; sig: cstring): cint {.importcpp: "#->indexOfSlot(#)",
    header: "<QMetaObject>".}
proc moMethodAt*(m: ptr QMetaObject; i: cint): QMetaMethod {.importcpp: "#->method(#)",
    header: "<QMetaObject>".}
proc moPropertyCount*(m: ptr QMetaObject): cint {.importcpp: "#->propertyCount()",
    header: "<QMetaObject>".}
proc moPropertyOffset*(m: ptr QMetaObject): cint {.importcpp: "#->propertyOffset()",
    header: "<QMetaObject>".}
proc moIndexOfProperty*(m: ptr QMetaObject; name: cstring): cint {.importcpp: "#->indexOfProperty(#)",
    header: "<QMetaObject>".}
proc moPropertyAt*(m: ptr QMetaObject; i: cint): QMetaProperty {.importcpp: "#->property(#)",
    header: "<QMetaObject>".}
proc moUserProperty*(m: ptr QMetaObject): QMetaProperty {.importcpp: "#->userProperty()",
    header: "<QMetaObject>".}
proc moEnumeratorsOf*(m: ptr QMetaObject; name: cstring): QMetaEnum
  {.importcpp: "#->enumerator(#->indexOfEnumerator(#))", header: "<QMetaObject>".}

proc nimqtMmSignature(mm: QMetaMethod): QString {.importc: "nimqt_mm_signature".}
proc mmSignature*(mm: QMetaMethod): string {.inline.} =
  nimqtMmSignature(mm).toString()
proc nimqtMmName(mm: QMetaMethod): QString {.importc: "nimqt_mm_name".}
proc mmName*(mm: QMetaMethod): string {.inline.} =
  nimqtMmName(mm).toString()
proc mmParameterCount*(mm: QMetaMethod): cint {.importcpp: "#.parameterCount()",
    header: "<QMetaMethod>".}
proc mmIsValid*(mm: QMetaMethod): bool {.importcpp: "#.isValid()",
                                          header: "<QMetaMethod>".}
type MethodKind* = enum mkMethod = 0, mkSignal = 1, mkSlot = 2
proc mmMethodTypeRaw*(mm: QMetaMethod): cint
  {.importcpp: "(int)#.methodType()", header: "<QMetaMethod>".}
proc mmMethodType*(mm: QMetaMethod): MethodKind {.inline.} =
  MethodKind(mm.mmMethodTypeRaw())

proc nimqtMpName(mp: QMetaProperty): QString {.importc: "nimqt_mp_name".}
proc mpName*(mp: QMetaProperty): string {.inline.} =
  nimqtMpName(mp).toString()
proc nimqtMpTypeName(mp: QMetaProperty): QString {.importc: "nimqt_mp_type_name".}
proc mpTypeName*(mp: QMetaProperty): string {.inline.} =
  nimqtMpTypeName(mp).toString()
proc mpIsValid*(mp: QMetaProperty): bool {.importcpp: "#.isValid()",
    header: "<QMetaProperty>".}
proc mpIsWritable*(mp: QMetaProperty): bool {.importcpp: "#.isWritable()",
    header: "<QMetaProperty>".}
proc mpIsReadable*(mp: QMetaProperty): bool {.importcpp: "#.isReadable()",
    header: "<QMetaProperty>".}
proc mpHasNotifySignal*(mp: QMetaProperty): bool {.importcpp: "#.hasNotifySignal()",
    header: "<QMetaProperty>".}
proc mpNotifySignal*(mp: QMetaProperty): QMetaMethod {.importcpp: "#.notifySignal()",
    header: "<QMetaProperty>".}
proc mpReadOn*(mp: QMetaProperty; o: ptr QObject): QVariant {.importcpp: "#.read(#)",
    header: "<QMetaProperty>".}
proc mpWriteOn*(mp: QMetaProperty; o: ptr QObject; v: QVariant): bool {.importcpp: "#.write(#, #)",
    header: "<QMetaProperty>".}

proc nimqtMeName(me: QMetaEnum): QString {.importc: "nimqt_me_name".}
proc meName*(me: QMetaEnum): string {.inline.} = nimqtMeName(me).toString()
proc meKeyCount*(me: QMetaEnum): cint {.importcpp: "#.keyCount()", header: "<QMetaEnum>".}
proc meKeyToValue*(me: QMetaEnum; key: cstring): cint {.importcpp: "#.keyToValue(#)",
    header: "<QMetaEnum>".}

# ---------------------------------------------------------------------------
# QVariant
# ---------------------------------------------------------------------------

proc qvariantNewInvalid*(): ptr QVariant {.importcpp: "new QVariant()",
    header: "<QVariant>".}
proc qvariantCopyNew*(v: QVariant): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}

proc variantIsValid*(v: QVariant): bool {.importcpp: "#.isValid()",
    header: "<QVariant>".}
proc variantIsNull*(v: QVariant): bool {.importcpp: "#.isNull()", header: "<QVariant>".}
proc variantTypeName*(v: QVariant): string
proc variantToString*(v: QVariant): QString {.importcpp: "#.toString()",
    header: "<QVariant>".}
proc variantToInt*(v: QVariant): cint {.importcpp: "#.toInt()", header: "<QVariant>".}
proc variantToUInt*(v: QVariant): cuint {.importcpp: "#.toUInt()", header: "<QVariant>".}
proc variantToLongLong*(v: QVariant): clonglong {.importcpp: "#.toLongLong()",
    header: "<QVariant>".}
proc variantToDouble*(v: QVariant): cdouble {.importcpp: "#.toDouble()",
    header: "<QVariant>".}
proc variantToBool*(v: QVariant): bool {.importcpp: "#.toBool()", header: "<QVariant>".}
proc variantToByteArray*(v: QVariant): QByteArray {.importcpp: "#.toByteArray()",
    header: "<QVariant>".}
proc variantToStringList*(v: QVariant): QStringList {.importcpp: "#.toStringList()",
    header: "<QVariant>".}
proc variantEquals*(a: QVariant; b: QVariant): bool {.importcpp: "(# == #)",
    header: "<QVariant>".}

proc qvariantNewBool*(b: bool): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewInt*(i: cint): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewUInt*(i: cuint): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewLongLong*(i: clonglong): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewDouble*(d: cdouble): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewFloat*(f: cfloat): ptr QVariant {.importcpp: "new QVariant((float)#)",
    header: "<QVariant>".}
proc qvariantNewString*(s: QString): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariant>".}
proc qvariantNewStringList*(l: QStringList): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QStringList>".}
proc qvariantNewUrl*(u: QUrl): ptr QVariant {.importcpp: "new QVariant(#)",
                                              header: "<QUrl>".}
proc qvariantNewVariantMap*(m: QVariantMap): ptr QVariant {.importcpp: "new QVariant(#)",
    header: "<QVariantMap>".}

proc variantDispose*(p: ptr QVariant) {.importcpp: "delete #", header: "<QVariant>".}

proc nimqtVariantTypeName(v: QVariant): QString {.importc: "nimqt_variant_type_name".}
proc variantTypeName*(v: QVariant): string =
  ## typeName() as Nim string (empty when invalid).
  nimqtVariantTypeName(v).toString()

# ---------------------------------------------------------------------------
# shim: QGuiApplication bootstrap lives in shim.cpp, declared in QtGui.nim.

# ---------------------------------------------------------------------------
# QUrl
# ---------------------------------------------------------------------------

proc qurlNewEmpty*(): QUrl {.importcpp: "QUrl()", header: "<QUrl>".}
proc qurlFromString*(s: QString): QUrl {.importcpp: "QUrl(#)", header: "<QUrl>".}
proc qurlFromLocalFile*(path: cstring): QUrl
  {.importcpp: "QUrl::fromLocalFile(QString::fromUtf8(#))", header: "<QUrl>".}
proc urlToString*(u: QUrl): QString {.importcpp: "#.toString()",
                                      header: "<QUrl>".}
proc urlIsValid*(u: QUrl): bool {.importcpp: "#.isValid()", header: "<QUrl>".}
proc urlIsEmpty*(u: QUrl): bool {.importcpp: "#.isEmpty()", header: "<QUrl>".}
proc urlIsLocalFile*(u: QUrl): bool {.importcpp: "#.isLocalFile()",
                                      header: "<QUrl>".}
proc urlToLocalFile*(u: QUrl): QString {.importcpp: "#.toLocalFile()",
                                         header: "<QUrl>".}
proc urlScheme*(u: QUrl): QString {.importcpp: "#.scheme()", header: "<QUrl>".}
proc urlHost*(u: QUrl): QString {.importcpp: "#.host()", header: "<QUrl>".}
proc urlPath*(u: QUrl): QString {.importcpp: "#.path()", header: "<QUrl>".}
proc urlQuery*(u: QUrl): QString {.importcpp: "#.query()", header: "<QUrl>".}

# ---- String helpers (Nim-facing aliases) ----
proc schemeStr*(u: QUrl): string {.inline.} = urlScheme(u).toString()
proc hostStr*(u: QUrl): string {.inline.} = urlHost(u).toString()
proc pathStr*(u: QUrl): string {.inline.} = urlPath(u).toString()
proc queryStr*(u: QUrl): string {.inline.} = urlQuery(u).toString()

# ---------------------------------------------------------------------------
# QStringList
# ---------------------------------------------------------------------------

proc slSize*(l: QStringList): cint {.importcpp: "#.size()", header: "<QStringList>".}
proc slAt*(l: QStringList; i: cint): QString {.importcpp: "#.at(#)",
                                               header: "<QStringList>".}
proc slAppend*(l: QStringList; s: QString) {.importcpp: "#.append(#)",
                                                header: "<QStringList>".}
proc slJoin*(l: QStringList; sep: QString): QString {.importcpp: "#.join(#)",
                                                   header: "<QStringList>".}
proc slAtStr*(l: QStringList; i: cint): string {.inline.} = slAt(l, i).toString()
proc slJoinStr*(l: QStringList; sep: string): string {.inline.} =
  slJoin(l, toQString(sep)).toString()
proc slSizeStr*(l: QStringList): string {.inline.} = $slSize(l)

# Low-level QStringList construction (matches C++ QStringList ctor).
proc qstringlistNew*(): QStringList {.importcpp: "QStringList()",
                                     header: "<QStringList>".}

# ---------------------------------------------------------------------------
# QPointF / QSizeF / QRectF
# ---------------------------------------------------------------------------

proc qpointfNew*(x: cdouble; y: cdouble): QPointF {.importcpp: "QPointF(@)",
    header: "<QPointF>".}
proc pointfX*(p: QPointF): cdouble {.importcpp: "#.xp", header: "<QPointF>".}
proc pointfY*(p: QPointF): cdouble {.importcpp: "#.yp", header: "<QPointF>".}

proc qsizefNew*(w: cdouble; h: cdouble): QSizeF {.importcpp: "QSizeF(@)",
    header: "<QSizeF>".}
proc sizefW*(s: QSizeF): cdouble {.importcpp: "#.wd", header: "<QSizeF>".}
proc sizefH*(s: QSizeF): cdouble {.importcpp: "#.ht", header: "<QSizeF>".}

proc qrectfNew*(x: cdouble; y: cdouble; w: cdouble; h: cdouble): QRectF {.importcpp: "QRectF(@)",
    header: "<QRectF>".}
proc rectfX*(r: QRectF): cdouble {.importcpp: "#.xp", header: "<QRectF>".}
proc rectfY*(r: QRectF): cdouble {.importcpp: "#.yp", header: "<QRectF>".}
proc rectfW*(r: QRectF): cdouble {.importcpp: "#.w", header: "<QRectF>".}
proc rectfH*(r: QRectF): cdouble {.importcpp: "#.h", header: "<QRectF>".}

# ---------------------------------------------------------------------------
# QTimer
# ---------------------------------------------------------------------------

proc qtimerNew*(parent: ptr QObject = nil): ptr QTimer
  {.importcpp: "new QTimer(@)", header: "<QTimer>".}
proc timerStartMs*(t: ptr QTimer; ms: cint) {.importcpp: "#->start(#)",
    header: "<QTimer>".}
proc timerStop*(t: ptr QTimer) {.importcpp: "#->stop()", header: "<QTimer>".}
proc timerSetInterval*(t: ptr QTimer; ms: cint) {.importcpp: "#->setInterval(#)",
    header: "<QTimer>".}
proc timerSetSingleShot*(t: ptr QTimer; b: bool) {.importcpp: "#->setSingleShot(#)",
    header: "<QTimer>".}
proc timerIsActive*(t: ptr QTimer): bool {.importcpp: "#->isActive()",
    header: "<QTimer>".}

# ---------------------------------------------------------------------------
# QCoreApplication statics & QEventLoop
# ---------------------------------------------------------------------------

proc appExecStatic*(typ: typedesc[QCoreApplication]): cint
  {.importcpp: "QCoreApplication::exec()", header: "<QCoreApplication>".}
proc appQuitStatic*(typ: typedesc[QCoreApplication]) {.importcpp: "QCoreApplication::quit()",
    header: "<QCoreApplication>".}
proc appInstanceStatic*(typ: typedesc[QCoreApplication]): ptr QCoreApplication
  {.importcpp: "QCoreApplication::instance()", header: "<QCoreApplication>".}
proc appSetApplicationNameStatic*(name: QString)
  {.importcpp: "QCoreApplication::setApplicationName(#)", header: "<QCoreApplication>".}
proc appSetOrganizationNameStatic*(name: QString)
  {.importcpp: "QCoreApplication::setOrganizationName(#)", header: "<QCoreApplication>".}
proc processEventsFor*(ms: cint) {.importcpp: "QCoreApplication::processEvents(QEventLoop::AllEvents, #)",
    header: "<QCoreApplication>".}

proc processEventsAll*() {.importcpp: "QCoreApplication::processEvents(QEventLoop::AllEvents)",
                            header: "<QCoreApplication>".}
proc sendPostedEventsAll*() {.importcpp: "QCoreApplication::sendPostedEvents(nullptr, QEvent::None)",
                               header: "<QCoreApplication>".}

proc eventLoopNew*(): ptr QEventLoop {.importcpp: "new QEventLoop()",
                                        header: "<QEventLoop>".}
proc eventLoopExec*(el: ptr QEventLoop): cint {.importcpp: "#->exec()",
    header: "<QEventLoop>".}
proc eventLoopQuit*(el: ptr QEventLoop) {.importcpp: "#->quit()",
    header: "<QEventLoop>".}
proc eventLoopFree*(el: ptr QEventLoop) {.importcpp: "delete #",
    header: "<QEventLoop>".}

# ===========================================================================
# Member-style forwarders (must be defined AFTER the underlying procs)
# ===========================================================================

# ---- QString ----
proc size*(s: QString): cint {.inline.} = qsSize(s)
proc isEmpty*(s: QString): bool {.inline.} = qsIsEmpty(s)
proc at*(s: QString; i: cint): QString {.inline.} = qsAt(s, i)

# ---- QByteArray ----
proc size*(b: QByteArray): cint {.inline.} = qbaSize(b)

# ---- QStringList ----
proc size*(l: QStringList): int {.inline.} = int(slSize(l))
proc at*(l: QStringList; i: int): string {.inline.} = slAt(l, cint(i)).toString
proc append*(l: QStringList; s: QString) {.inline.} = slAppend(l, s)
proc join*(l: QStringList; sep: string): string {.inline.} =
  slJoin(l, toQString(sep)).toString

# ---- QObject ----
proc objectName*(o: ptr QObject): string {.inline.} = objObjectName(o).toString
proc setObjectName*(o: ptr QObject; n: string) {.inline.} =
  objSetObjectName(o, toQString(n))
proc property*(o: ptr QObject; name: string): QVariant {.inline.} =
  objProperty(o, cstring(name))
proc setPropertyValue*(o: ptr QObject; name: string; v: QVariant): bool
  {.inline.} = objSetProperty(o, cstring(name), v)

# ---- QUrl ----
proc isValid*(u: QUrl): bool {.inline.} = urlIsValid(u)

# ---- QVariant ----
template toString*(v: QVariant): string = v.variantToString.toString
template toBoolV*(v: QVariant): bool = variantToBool(v)
proc toInt32*(v: QVariant): int32 {.inline.} = int32(variantToInt(v))
proc toInt64*(v: QVariant): int64 {.inline.} = int64(variantToLongLong(v))
proc toFloat*(v: QVariant): float32 {.inline.} = float32(variantToDouble(v))
proc `==`*(a, b: QVariant): bool {.inline.} = variantEquals(a, b)
proc `!=`*(a, b: QVariant): bool {.inline.} = not variantEquals(a, b)
proc isValid*(v: QVariant): bool {.inline.} = variantIsValid(v)
proc isNull*(v: QVariant): bool {.inline.} = variantIsNull(v)
proc typeIdName*(v: QVariant): string {.inline.} = variantTypeName(v)

# ---- QMetaObject member-style ----
proc className*(m: ptr QMetaObject): string {.inline.} = moClassName(m)
proc methodCount*(m: ptr QMetaObject): int {.inline.} = int(moMethodCount(m))

# ---- QTimer member-style ----
proc newQTimer*(): ptr QTimer = qtimerNew(nil)
proc start*(t: ptr QTimer) {.inline.} = timerStartMs(t, 0)
proc start*(t: ptr QTimer; ms: cint) {.inline.} = timerStartMs(t, ms)
proc stop*(t: ptr QTimer) {.inline.} = timerStop(t)
proc setInterval*(t: ptr QTimer; ms: cint) {.inline.} = timerSetInterval(t, ms)
proc setSingleShot*(t: ptr QTimer; b: bool) {.inline.} = timerSetSingleShot(t, b)
proc isActive*(t: ptr QTimer): bool {.inline.} = timerIsActive(t)

{.pop.}
