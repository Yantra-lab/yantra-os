## nimqt — Low-level Qt6 Quick bindings ({.importcpp.}).
## QQuickView, QQuickItem, QQuickWindow, QQuickItemGrabResult.
## Same conventions as QtCore.nim / QtQml.nim.

import QtCore, QtGui, QtQml

{.push hint[XDeclaredButNotUsed]: off.}

type
  QQuickItem* {.importcpp: "QQuickItem", header: "<QQuickItem>",
                inheritable.} = object of QObject
  QQuickWindow* {.importcpp: "QQuickWindow", header: "<QQuickWindow>",
                  inheritable.} = object of QWindow
  QQuickView* {.importcpp: "QQuickView", header: "<QQuickView>",
                inheritable.} = object of QQuickWindow
  QQuickItemGrabResult* {.importcpp: "QQuickItemGrabResult",
                          header: "<QQuickItemGrabResult>",
                          inheritable.} = object of QObject

type
  QListQQuickItem* {.importcpp: "QList<QQuickItem*>", header: "<QList>", bycopy,
                     pure.} = object

# QQuickView::Status values
const
  ViewNull*    = cint(0)
  ViewReady*   = cint(1)
  ViewLoading* = cint(2)
  ViewError*   = cint(3)

proc listqitemSize*(l: QListQQuickItem): cint {.importcpp: "#.size()",
    header: "<QList>".}
proc listqitemAt*(l: QListQQuickItem; i: cint): ptr QQuickItem
  {.importcpp: "#.at(#)", header: "<QList>".}

# ---------------------------------------------------------------------------
# QQuickItem
# ---------------------------------------------------------------------------

proc qquickitemNew*(parent: ptr QQuickItem = nil): ptr QQuickItem
  {.importcpp: "new QQuickItem(@)", header: "<QQuickItem>", constructor.}

proc itemX*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->x()", header: "<QQuickItem>".}
proc itemSetX*(i: ptr QQuickItem; v: cdouble) {.importcpp: "#->setX(#)", header: "<QQuickItem>".}
proc itemY*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->y()", header: "<QQuickItem>".}
proc itemSetY*(i: ptr QQuickItem; v: cdouble) {.importcpp: "#->setY(#)", header: "<QQuickItem>".}
proc itemZ*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->z()", header: "<QQuickItem>".}
proc itemSetZ*(i: ptr QQuickItem; v: cdouble) {.importcpp: "#->setZ(#)", header: "<QQuickItem>".}
proc itemWidth*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->width()", header: "<QQuickItem>".}
proc itemSetWidth*(i: ptr QQuickItem; v: cdouble) {.importcpp: "#->setWidth(#)", header: "<QQuickItem>".}
proc itemHeight*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->height()", header: "<QQuickItem>".}
proc itemSetHeight*(i: ptr QQuickItem; v: cdouble) {.importcpp: "#->setHeight(#)", header: "<QQuickItem>".}
proc itemOpacity*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->opacity()", header: "<QQuickItem>".}
proc itemSetOpacity*(i: ptr QQuickItem; v: cdouble)
  {.importcpp: "#->setOpacity(#)", header: "<QQuickItem>".}
proc itemRotation*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->rotation()", header: "<QQuickItem>".}
proc itemSetRotation*(i: ptr QQuickItem; v: cdouble)
  {.importcpp: "#->setRotation(#)", header: "<QQuickItem>".}
proc itemScale*(i: ptr QQuickItem): cdouble {.importcpp: "(double)#->scale()", header: "<QQuickItem>".}
proc itemSetScale*(i: ptr QQuickItem; v: cdouble)
  {.importcpp: "#->setScale(#)", header: "<QQuickItem>".}
proc isVisibleItem*(i: ptr QQuickItem): bool {.importcpp: "#->isVisible()",
    header: "<QQuickItem>".}
proc itemSetVisible*(i: ptr QQuickItem; b: bool) {.importcpp: "#->setVisible(#)",
    header: "<QQuickItem>".}
proc isEnabledItem*(i: ptr QQuickItem): bool {.importcpp: "#->isEnabled()",
    header: "<QQuickItem>".}
proc itemSetEnabled*(i: ptr QQuickItem; b: bool) {.importcpp: "#->setEnabled(#)",
    header: "<QQuickItem>".}
proc itemClip*(i: ptr QQuickItem): bool {.importcpp: "#->clip()", header: "<QQuickItem>".}
proc itemSetClip*(i: ptr QQuickItem; b: bool) {.importcpp: "#->setClip(#)",
    header: "<QQuickItem>".}

proc itemParentItem*(i: ptr QQuickItem): ptr QQuickItem
  {.importcpp: "#->parentItem()", header: "<QQuickItem>".}
proc itemSetParentItem*(i: ptr QQuickItem; p: ptr QQuickItem)
  {.importcpp: "#->setParentItem(#)", header: "<QQuickItem>".}
proc itemChildItems*(i: ptr QQuickItem): QListQQuickItem
  {.importcpp: "#->childItems()", header: "<QQuickItem>".}
proc itemIsAncestorOf*(i: ptr QQuickItem; child: ptr QQuickItem): bool
  {.importcpp: "#->isAncestorOf(#)", header: "<QQuickItem>".}

proc itemMapToScene*(i: ptr QQuickItem; p: QPointF): QPointF
  {.importcpp: "#->mapToScene(#)", header: "<QQuickItem>".}
proc itemMapFromScene*(i: ptr QQuickItem; p: QPointF): QPointF
  {.importcpp: "#->mapFromScene(#)", header: "<QQuickItem>".}
proc itemMapToItem*(i: ptr QQuickItem; p: QPointF; other: ptr QQuickItem): QPointF
  {.importcpp: "#->mapToItem(#, #)", header: "<QQuickItem>".}
proc itemContains*(i: ptr QQuickItem; p: QPointF): bool
  {.importcpp: "#->contains(#)", header: "<QQuickItem>".}
proc itemBoundingRect*(i: ptr QQuickItem): QRectF
  {.importcpp: "#->boundingRect()", header: "<QQuickItem>".}

proc itemUpdate*(i: ptr QQuickItem) {.importcpp: "#->update()", header: "<QQuickItem>".}
proc itemPolishItemsStatic*(w: ptr QQuickWindow)
  {.importcpp: "QQuickItem::polishItems(#)", header: "<QQuickItem>".}
proc itemReleaseResources*(i: ptr QQuickItem)
  {.importcpp: "#->releaseResources()", header: "<QQuickItem>".}
proc itemCursorStr*(i: ptr QQuickItem): QString
  {.importc: "nimqt_item_cursor_name".}
proc itemSetAcceptedMouseButtonsAll*(i: ptr QQuickItem)
  {.importcpp: "#->setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton | Qt::MiddleButton)",
   header: "<QQuickItem>".}
proc itemSetFlagAcceptDrops*(i: ptr QQuickItem; on: bool)
  {.importcpp: "#->setFlag(QQuickItem::ItemClipsChildrenToShape, #)",
   header: "<QQuickItem>".}

proc itemGrabToImage*(i: ptr QQuickItem; targetSize: QSize): ptr QQuickItemGrabResult
  {.importcpp: "#->grabToImage(#)", header: "<QQuickItem>".}
proc grabResultImageShim*(r: ptr QQuickItemGrabResult): QImage
  {.importc: "nimqt_grabresult_image".}
proc grabResultDisposeKeepAlive*(r: ptr QQuickItemGrabResult)
  {.importcpp: "{ QObject o_ = *#; }".} ## unused; ownership stays with item

# ---------------------------------------------------------------------------
# QQuickWindow
# ---------------------------------------------------------------------------

proc qquickwindowNew*(parent: ptr QWindow = nil): ptr QQuickWindow
  {.importcpp: "new QQuickWindow(@)", header: "<QQuickWindow>", constructor.}
proc winContentItem*(w: ptr QQuickWindow): ptr QQuickItem
  {.importcpp: "#->contentItem()", header: "<QQuickWindow>".}
proc winGrabWindowShim*(w: ptr QQuickWindow): QImage
  {.importc: "nimqt_quickwindow_grab".}
proc winColorSet*(w: ptr QQuickWindow; c: QColor)
  {.importcpp: "#->setColor(#)", header: "<QQuickWindow>".}
proc winColorGet*(w: ptr QQuickWindow): QColor
  {.importcpp: "#->color()", header: "<QQuickWindow>".}

# ---------------------------------------------------------------------------
# QQuickView
# ---------------------------------------------------------------------------

proc qquickviewNewDefault*(): ptr QQuickView
  {.importcpp: "new QQuickView()", header: "<QQuickView>", constructor.}
proc qquickviewNewEngine*(e: ptr QQmlEngine; parent: ptr QWindow = nil): ptr QQuickView
  {.importcpp: "new QQuickView(#, @)", header: "<QQuickView>", constructor.}

proc viewSourceUrl*(v: ptr QQuickView): QUrl {.importcpp: "#->source()",
    header: "<QQuickView>".}
proc viewSetSource*(v: ptr QQuickView; u: QUrl) {.importcpp: "#->setSource(#)",
    header: "<QQuickView>".}
proc viewStatusRaw*(v: ptr QQuickView): cint {.importcpp: "(int)#->status()",
    header: "<QQuickView>".}
proc viewErrorsShim*(v: ptr QQuickView): QStringList
  {.importc: "nimqt_view_errors".}
proc viewRootObjectRaw*(v: ptr QQuickView): ptr QQuickItem
  {.importcpp: "#->rootObject()", header: "<QQuickView>".}
proc viewEngineRaw*(v: ptr QQuickView): ptr QQmlEngine
  {.importcpp: "#->engine()", header: "<QQuickView>".}
proc viewInitialSize*(v: ptr QQuickView): QSize
  {.importcpp: "#->initialSize()", header: "<QQuickView>".}
proc viewCreateSync*(v: ptr QQuickView) {.importcpp: "#->create()",
    header: "<QQuickView>".}
proc viewResizeWin*(v: ptr QQuickView; w: cint; h: cint)
  {.importcpp: "#->resize(QSize(#, #))", header: "<QQuickView>".}
proc viewShowWin*(v: ptr QQuickView) {.importcpp: "#->show()", header: "<QQuickView>".}
proc viewSetTitleWin*(v: ptr QQuickView; t: QString)
  {.importcpp: "#->setTitle(#)", header: "<QQuickView>".}
proc viewCloseWin*(v: ptr QQuickView) {.importcpp: "#->close()", header: "<QQuickView>".}
proc viewW*(v: ptr QQuickView): cint {.importcpp: "#->width()", header: "<QQuickView>".}
proc viewH*(v: ptr QQuickView): cint {.importcpp: "#->height()", header: "<QQuickView>".}

{.pop.}
