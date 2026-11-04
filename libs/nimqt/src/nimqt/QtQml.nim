## nimqt — Low-level Qt6 QML bindings ({.importcpp.}).
## QQmlEngine, QQmlComponent, QQmlContext, QQmlProperty, QJSValue,
## QQmlApplicationEngine. Same conventions as QtCore.nim.
## Error lists, async incubation, JS calls and root-object lists go through
## shim helpers (see shim.cpp).

import QtCore, QtGui

{.push hint[XDeclaredButNotUsed]: off.}

type
  QQmlEngine* {.importcpp: "QQmlEngine", header: "<QQmlEngine>",
                inheritable.} = object of QObject
  QQmlComponent* {.importcpp: "QQmlComponent", header: "<QQmlComponent>",
                   inheritable.} = object of QObject
  QQmlContext* {.importcpp: "QQmlContext", header: "<QQmlContext>".} = object
  QQmlProperty* {.importcpp: "QQmlProperty", header: "<QQmlProperty>", bycopy.} = object
  QJSValue* {.importcpp: "QJSValue", header: "<QJSValue>", bycopy.} = object
  QQmlApplicationEngine* {.importcpp: "QQmlApplicationEngine",
                           header: "<QQmlApplicationEngine>",
                           inheritable.} = object of QQmlEngine

type QListQObject* {.importcpp: "QList<QObject*>", header: "<QObject>", bycopy,
                     pure.} = object

# Component status values (QQmlComponent::Status)
const
  ComponentNull*    = cint(0)
  ComponentReady*   = cint(1)
  ComponentLoading* = cint(2)
  ComponentError*   = cint(3)

# ---------------------------------------------------------------------------
# QList<QObject*>
# ---------------------------------------------------------------------------

proc listqobjSize*(l: QListQObject): cint {.importcpp: "#.size()", header: "<QList>".}
proc listqobjAt*(l: QListQObject; i: cint): ptr QObject {.importcpp: "#.at(#)",
    header: "<QList>".}

# ---------------------------------------------------------------------------
# QQmlEngine
# ---------------------------------------------------------------------------

proc qqmlengineNew*(parent: ptr QObject = nil): ptr QQmlEngine
  {.importcpp: "new QQmlEngine(@)", header: "<QQmlEngine>", constructor.}
proc engineRootContext*(e: ptr QQmlEngine): ptr QQmlContext
  {.importcpp: "#->rootContext()", header: "<QQmlEngine>".}
proc engineAddImportPath*(e: ptr QQmlEngine; path: QString)
  {.importcpp: "#->addImportPath(#)", header: "<QQmlEngine>".}
proc engineAddPluginPath*(e: ptr QQmlEngine; path: QString)
  {.importcpp: "#->addPluginPath(#)", header: "<QQmlEngine>".}
proc engineImportPathList*(e: ptr QQmlEngine): QStringList
  {.importcpp: "#->importPathList()", header: "<QQmlEngine>".}
proc engineTrimComponentCache*(e: ptr QQmlEngine)
  {.importcpp: "#->trimComponentCache()", header: "<QQmlEngine>".}
proc engineClearComponentCache*(e: ptr QQmlEngine)
  {.importcpp: "#->clearComponentCache()", header: "<QQmlEngine>".}
proc engineCollectGarbage*(e: ptr QQmlEngine)
  {.importcpp: "#->collectGarbage()", header: "<QQmlEngine>".}

proc engineContextForObjectStatic*(o: ptr QObject): ptr QQmlContext
  {.importcpp: "QQmlEngine::contextForObject(#)", header: "<QQmlEngine>".}
proc engineSetContextForObjectStatic*(o: ptr QObject; ctx: ptr QQmlContext)
  {.importcpp: "QQmlEngine::setContextForObject(#, #)", header: "<QQmlEngine>".}

proc engineOutputWarningsToStdErr*(e: ptr QQmlEngine): bool
  {.importcpp: "#->outputWarningsToStandardError()", header: "<QQmlEngine>".}
proc engineSetOutputWarningsToStdErr*(e: ptr QQmlEngine; b: bool)
  {.importcpp: "#->setOutputWarningsToStandardError(#)", header: "<QQmlEngine>".}

# QJSEngine API surface reachable through QQmlEngine (it derives from it).
proc jsEngineGlobalObject*(e: ptr QQmlEngine): QJSValue
  {.importcpp: "static_cast<QJSEngine*>(#)->globalObject()", header: "<QQmlEngine>".}
proc jsEngineNewObject*(e: ptr QQmlEngine): QJSValue
  {.importcpp: "static_cast<QJSEngine*>(#)->newObject()", header: "<QQmlEngine>".}
proc jsEngineNewArrayShim*(e: ptr QQmlEngine; len: cuint): QJSValue
  {.importc: "nimqt_jsengine_new_array".}
proc jsEngineEvaluate*(e: ptr QQmlEngine; program: QString; fileName: QString = toQString("")): QJSValue
  {.importcpp: "static_cast<QJSEngine*>(#)->evaluate(#, #)", header: "<QJSEngine>".}
proc jsEngineFromVariant*(e: ptr QQmlEngine; v: QVariant): QJSValue
  {.importcpp: "static_cast<QJSEngine*>(#)->fromVariant(#)", header: "<QJSEngine>".}
proc jsEngineToVariant*(e: ptr QQmlEngine; j: QJSValue): QVariant
  {.importcpp: "static_cast<QJSEngine*>(#)->toVariant(#, QMetaType::UnknownType)",
   header: "<QJSEngine>".}

# ---------------------------------------------------------------------------
# QQmlContext
# ---------------------------------------------------------------------------

proc contextParentRaw*(ctx: ptr QQmlContext): ptr QQmlContext
  {.importcpp: "#->parentContext()", header: "<QQmlContext>".}
proc contextSetContextPropertyVariant*(ctx: ptr QQmlContext; name: QString;
                                       v: QVariant)
  {.importcpp: "#->setContextProperty(#, #)", header: "<QQmlContext>".}
proc contextSetContextPropertyObj*(ctx: ptr QQmlContext; name: QString;
                                   o: ptr QObject)
  {.importcpp: "#->setContextProperty(#, #)", header: "<QQmlContext>".}
proc contextBaseUrl*(ctx: ptr QQmlContext): QUrl
  {.importcpp: "#->baseUrl()", header: "<QQmlContext>".}
proc contextSetBaseUrl*(ctx: ptr QQmlContext; u: QUrl)
  {.importcpp: "#->setBaseUrl(#)", header: "<QQmlContext>".}
proc contextResolvedUrl*(ctx: ptr QQmlContext; u: QUrl): QUrl
  {.importcpp: "#->resolvedUrl(#)", header: "<QQmlContext>".}
proc contextEngineRaw*(ctx: ptr QQmlContext): ptr QQmlEngine
  {.importcpp: "#->engine()", header: "<QQmlContext>".}
proc contextIsValid*(ctx: ptr QQmlContext): bool
  {.importcpp: "#->isValid()", header: "<QQmlContext>".}
proc contextNameForObjectStatic*(o: ptr QObject): QString
  {.importcpp: "QQmlContext::nameForObject(#)", header: "<QQmlContext>".}
proc contextDispose*(ctx: ptr QQmlContext) {.importcpp: "delete #",
    header: "<QQmlContext>".}

# ---------------------------------------------------------------------------
# QQmlComponent
# ---------------------------------------------------------------------------

proc componentNew*(e: ptr QQmlEngine): ptr QQmlComponent
  {.importcpp: "new QQmlComponent(#)", header: "<QQmlComponent>", constructor.}
proc componentNewUrl*(e: ptr QQmlEngine; url: QUrl): ptr QQmlComponent
  {.importcpp: "new QQmlComponent(#, #)", header: "<QQmlComponent>", constructor.}
proc componentNewData*(e: ptr QQmlEngine; data: QByteArray; basePath: QString): ptr QQmlComponent
  {.importcpp: "new QQmlComponent(#, #, #)", header: "<QQmlComponent>", constructor.}

proc compLoadUrl*(c: ptr QQmlComponent; url: QUrl)
  {.importcpp: "#->loadUrl(#)", header: "<QQmlComponent>".}
proc compSetData*(c: ptr QQmlComponent; data: QByteArray; baseUrl: QUrl)
  {.importcpp: "#->setData(#, #)", header: "<QQmlComponent>".}
proc compStatus*(c: ptr QQmlComponent): cint
  {.importcpp: "(int)#->status()", header: "<QQmlComponent>".}
proc compIsLoading*(c: ptr QQmlComponent): bool
  {.importcpp: "#->isLoading()", header: "<QQmlComponent>".}
proc compIsError*(c: ptr QQmlComponent): bool
  {.importcpp: "#->isError()", header: "<QQmlComponent>".}
proc compIsNullState*(c: ptr QQmlComponent): bool
  {.importcpp: "#->isNull()", header: "<QQmlComponent>".}
proc compIsReady*(c: ptr QQmlComponent): bool
  {.importcpp: "#->isReady()", header: "<QQmlComponent>".}

## Errors as QStringList of QQmlError::toString() (shim).
proc compErrorsShim*(c: ptr QQmlComponent): QStringList
  {.importc: "nimqt_component_errors".}

proc compCreateSync*(c: ptr QQmlComponent; ctx: ptr QQmlContext = nil): ptr QObject
  {.importcpp: "#->create(#)", header: "<QQmlComponent>".}

## Async creation through QQmlIncubator, driven by an opaque handle owned by
## the shim. Poll returns 0=still loading, 1=ready, 2=error.
proc compCreateAsyncStart*(c: ptr QQmlComponent; ctx: ptr QQmlContext): pointer
  {.importc: "nimqt_incubator_start".}
proc compAsyncPoll*(handle: pointer): cint {.importc: "nimqt_incubator_poll".}
proc compAsyncResult*(handle: pointer): ptr QObject {.importc: "nimqt_incubator_result".}
proc compAsyncErrorsShim*(handle: pointer): QStringList {.importc: "nimqt_incubator_errors".}
proc compAsyncFree*(handle: pointer) {.importc: "nimqt_incubator_free".}

proc compCreationContext*(c: ptr QQmlComponent): ptr QQmlContext
  {.importcpp: "#->creationContext()", header: "<QQmlComponent>".}
proc compDispose*(c: ptr QQmlComponent) {.importcpp: "delete #",
    header: "<QQmlComponent>".}

# ---------------------------------------------------------------------------
# QQmlProperty (generic property read/write bridge)
# ---------------------------------------------------------------------------

proc qmlpropertyNewDefault*(): QQmlProperty
  {.importcpp: "QQmlProperty()", header: "<QQmlProperty>", constructor.}
proc qmlpropertyNewOn*(o: ptr QObject): QQmlProperty
  {.importcpp: "QQmlProperty(#)", header: "<QQmlProperty>", constructor.}
proc qmlpropertyReadVariant*(p: QQmlProperty): QVariant
  {.importcpp: "#.read()", header: "<QQmlProperty>".}
proc qmlpropertyWriteVariant*(p: var QQmlProperty; v: QVariant): bool
  {.importcpp: "#.write(#)", header: "<QQmlProperty>".}
proc qmlpropertyIsValidP*(p: QQmlProperty): bool
  {.importcpp: "#.isValid()", header: "<QQmlProperty>".}
proc qmlpropertyTypeNameStr*(p: QQmlProperty): QString
  {.importcpp: "#.propertyTypeName()", header: "<QQmlProperty>".}
proc qmlpropertyHasNotifySignalP*(p: QQmlProperty): bool
  {.importcpp: "#.hasNotifySignal()", header: "<QQmlProperty>".}

proc qmlpropRead*(o: ptr QObject; name: QString): QVariant
  {.importcpp: "QQmlProperty::read(#, #)", header: "<QQmlProperty>".}
proc qmlpropWrite*(o: ptr QObject; name: QString; v: QVariant): bool
  {.importcpp: "QQmlProperty::write(#, #, #)", header: "<QQmlProperty>".}
proc qmlpropReset*(o: ptr QObject; name: QString): bool
  {.importcpp: "QQmlProperty::reset(#, #)", header: "<QQmlProperty>".}

# ---------------------------------------------------------------------------
# QJSValue
# ---------------------------------------------------------------------------

proc jsvalueNewUndefined*(): QJSValue
  {.importcpp: "QJSValue()", header: "<QJSValue>", constructor.}
proc jsvalueFromBoolV*(b: bool): QJSValue
  {.importcpp: "QJSValue(#)", header: "<QJSValue>", constructor.}
proc jsvalueFromIntV*(i: cint): QJSValue
  {.importcpp: "QJSValue(#)", header: "<QJSValue>", constructor.}
proc jsvalueFromUIntV*(u: cuint): QJSValue
  {.importcpp: "QJSValue(#)", header: "<QJSValue>", constructor.}
proc jsvalueFromDoubleV*(d: cdouble): QJSValue
  {.importcpp: "QJSValue(#)", header: "<QJSValue>", constructor.}
proc jsvalueFromStringV*(s: QString): QJSValue
  {.importcpp: "QJSValue(#)", header: "<QJSValue>", constructor.}

proc jsIsUndefined*(j: QJSValue): bool {.importcpp: "#.isUndefined()", header: "<QJSValue>".}
proc jsIsNull*(j: QJSValue): bool {.importcpp: "#.isNull()", header: "<QJSValue>".}
proc jsIsBool*(j: QJSValue): bool {.importcpp: "#.isBool()", header: "<QJSValue>".}
proc jsIsNumber*(j: QJSValue): bool {.importcpp: "#.isNumber()", header: "<QJSValue>".}
proc jsIsStringV*(j: QJSValue): bool {.importcpp: "#.isString()", header: "<QJSValue>".}
proc jsIsArray*(j: QJSValue): bool {.importcpp: "#.isArray()", header: "<QJSValue>".}
proc jsIsObject*(j: QJSValue): bool {.importcpp: "#.isObject()", header: "<QJSValue>".}
proc jsIsError*(j: QJSValue): bool {.importcpp: "#.isError()", header: "<QJSValue>".}
proc jsIsCallable*(j: QJSValue): bool {.importcpp: "#.isCallable()", header: "<QJSValue>".}

proc jsToBool*(j: QJSValue): bool {.importcpp: "#.toBool()", header: "<QJSValue>".}
proc jsToInt*(j: QJSValue): cint {.importcpp: "#.toInt()", header: "<QJSValue>".}
proc jsToUInt*(j: QJSValue): cuint {.importcpp: "#.toUInt()", header: "<QJSValue>".}
proc jsToNumber*(j: QJSValue): cdouble {.importcpp: "#.toNumber()", header: "<QJSValue>".}
proc jsToString*(j: QJSValue): QString {.importcpp: "#.toString()", header: "<QJSValue>".}

proc jsvalueDestroy*(v: QJSValue) {.importcpp: "#.~QJSValue()", header: "<QJSValue>".}

proc jsCallShimP*(j: ptr QJSValue; args: ptr ptr QJSValue; n: cint): QJSValue
  {.importc: "nimqt_qjsvalue_call_ptrs".}
proc jsConstructShimP*(j: ptr QJSValue; args: ptr ptr QJSValue; n: cint): QJSValue
  {.importc: "nimqt_qjsvalue_construct_ptrs".}

proc jsCallShim*(j: QJSValue; args: ptr UncheckedArray[QJSValue]; n: cint): QJSValue
  {.importc: "nimqt_qjsvalue_call".}
proc jsConstructShim*(j: QJSValue; args: ptr UncheckedArray[QJSValue]; n: cint): QJSValue
  {.importc: "nimqt_qjsvalue_construct".}
proc jsPropertyGet*(j: QJSValue; name: QString): QJSValue
  {.importcpp: "#.property(#)", header: "<QJSValue>".}
proc jsPropertyGetIdx*(j: QJSValue; i: cint): QJSValue
  {.importcpp: "#.property(static_cast<quint32>(#))", header: "<QJSValue>".}
proc jsPropertySet*(j: QJSValue; name: QString; v: QJSValue)
  {.importcpp: "#.setProperty(#, #)", header: "<QJSValue>".}
proc jsArrayLen*(j: QJSValue): cint
  {.importcpp: "(int)(#).property(QString::fromUtf8(\"length\")).toInt()",
   header: "<QJSValue>".}

# ---------------------------------------------------------------------------
# QQmlApplicationEngine
# ---------------------------------------------------------------------------

proc qqmlappengineNew*(parent: ptr QObject = nil): ptr QQmlApplicationEngine
  {.importcpp: "new QQmlApplicationEngine(@)", header: "<QQmlApplicationEngine>",
   constructor.}
proc appengLoadUrl*(e: ptr QQmlApplicationEngine; url: QUrl)
  {.importcpp: "#->load(#)", header: "<QQmlApplicationEngine>".}
proc appengLoadData*(e: ptr QQmlApplicationEngine; data: QByteArray; url: QUrl)
  {.importcpp: "#->loadData(#, #)", header: "<QQmlApplicationEngine>".}
proc appengRootObjectsShim*(e: ptr QQmlApplicationEngine): QListQObject
  {.importc: "nimqt_appeng_root_objects".}

{.pop.}
