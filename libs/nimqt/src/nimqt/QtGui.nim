## nimqt — Low-level Qt6 Gui bindings ({.importcpp.}).
## QGuiApplication, QWindow, QColor, QFont, QImage (+ QIcon basics).
## Same conventions as QtCore.nim: polymorphic types via ptr, value classes
## bycopy. QGuiApplication construction goes through shim helpers because the
## C++ constructor mutates (int&, char**).

import QtCore

{.push hint[XDeclaredButNotUsed]: off.}

type
  QGuiApplication* {.importcpp: "QGuiApplication", header: "<QGuiApplication>",
                     inheritable.} = object of QCoreApplication
  QWindow* {.importcpp: "QWindow", header: "<QWindow>", inheritable.} = object of QObject
  QColor* {.importcpp: "QColor", header: "<QColor>", bycopy.} = object
  QFont* {.importcpp: "QFont", header: "<QFont>", bycopy.} = object
  QImage* {.importcpp: "QImage", header: "<QImage>", bycopy.} = object
  QSize* {.importcpp: "QSize", header: "<QSize>", bycopy.} = object

# ---------------------------------------------------------------------------
# QGuiApplication (ctor via shim: owns stable argv storage)
# ---------------------------------------------------------------------------

proc qguiappNewShim*(): ptr QGuiApplication {.importc: "nimqt_qguiapp_new".}
proc qguiappArgcShim*(): cint {.importc: "nimqt_qguiapp_argc".}
proc qguiappArgvShim*(): cstringArray {.importc: "nimqt_qguiapp_argv".}

proc guiappArguments*(typ: typedesc[QGuiApplication]): QStringList
  {.importcpp: "QGuiApplication::arguments()", header: "<QGuiApplication>".}
proc guiappPlatformName*(typ: typedesc[QGuiApplication]): QString
  {.importcpp: "QGuiApplication::platformName()", header: "<QGuiApplication>".}

# ---------------------------------------------------------------------------
# QWindow
# ---------------------------------------------------------------------------

proc qwindowNew*(parent: ptr QWindow = nil): ptr QWindow
  {.importcpp: "new QWindow(@)", header: "<QWindow>", constructor.}
proc winSetTitle*(w: ptr QWindow; t: QString) {.importcpp: "#->setTitle(#)",
    header: "<QWindow>".}
proc winTitle*(w: ptr QWindow): QString {.importcpp: "#->title()",
    header: "<QWindow>".}
proc winShow*(w: ptr QWindow) {.importcpp: "#->show()", header: "<QWindow>".}
proc winShowFullScreen*(w: ptr QWindow) {.importcpp: "#->showFullScreen()",
    header: "<QWindow>".}
proc winShowMaximized*(w: ptr QWindow) {.importcpp: "#->showMaximized()",
    header: "<QWindow>".}
proc winShowMinimized*(w: ptr QWindow) {.importcpp: "#->showMinimized()",
    header: "<QWindow>".}
proc winClose*(w: ptr QWindow) {.importcpp: "#->close()", header: "<QWindow>".}
proc winDestroy*(w: ptr QWindow) {.importcpp: "#->destroy()", header: "<QWindow>".}
proc winWidthRaw*(w: ptr QWindow): cint {.importcpp: "#->width()",
    header: "<QWindow>".}
proc winHeightRaw*(w: ptr QWindow): cint {.importcpp: "#->height()",
    header: "<QWindow>".}
proc winVisibility*(w: ptr QWindow): cint {.importcpp: "(int)#->visibility()",
    header: "<QWindow>".}

# ---------------------------------------------------------------------------
# QColor
# ---------------------------------------------------------------------------

proc colorNewDefault*(): QColor {.importcpp: "QColor()", header: "<QColor>",
                                  constructor.}
proc colorFromName*(name: QString): QColor {.importcpp: "QColor(#)",
    header: "<QColor>", constructor.}
proc colorFromRgb*(r: cint; g: cint; b: cint; a: cint = 255): QColor
  {.importcpp: "QColor(@)", header: "<QColor>", constructor.}
proc colorRed*(c: QColor): cint {.importcpp: "#.red()", header: "<QColor>".}
proc colorGreen*(c: QColor): cint {.importcpp: "#.green()", header: "<QColor>".}
proc colorBlue*(c: QColor): cint {.importcpp: "#.blue()", header: "<QColor>".}
proc colorAlpha*(c: QColor): cint {.importcpp: "#.alpha()", header: "<QColor>".}
proc colorIsValid*(c: QColor): bool {.importcpp: "#.isValid()", header: "<QColor>".}
proc colorNameStr*(c: QColor): QString {.importcpp: "#.name(QColor::HexRgb)",
    header: "<QColor>".}
proc colorSetNamed*(c: var QColor; name: QString)
  {.importcpp: "#.setNamedColor(#)", header: "<QColor>".}

# ---------------------------------------------------------------------------
# QFont
# ---------------------------------------------------------------------------

proc fontNewDefault*(): QFont {.importcpp: "QFont()", header: "<QFont>",
                                constructor.}
proc fontNewFamily*(family: QString; pointSize: cint = -1; weight: cint = -1;
                    italic: bool = false): QFont {.importcpp: "QFont(@)",
    header: "<QFont>", constructor.}
proc fontFamily*(f: QFont): QString {.importcpp: "#.family()", header: "<QFont>".}
proc fontSetFamily*(f: var QFont; fam: QString) {.importcpp: "#.setFamily(#)",
    header: "<QFont>".}
proc fontPointSize*(f: QFont): cdouble {.importcpp: "#.pointSizeF()",
    header: "<QFont>".}
proc fontSetPointSize*(f: var QFont; s: cdouble) {.importcpp: "#.setPointSizeF(#)",
    header: "<QFont>".}
proc fontPixelSize*(f: QFont): cint {.importcpp: "#.pixelSize()", header: "<QFont>".}
proc fontSetPixelSize*(f: var QFont; px: cint) {.importcpp: "#.setPixelSize(#)",
    header: "<QFont>".}
proc fontIsBold*(f: QFont): bool {.importcpp: "#.bold()", header: "<QFont>".}
proc fontSetBold*(f: var QFont; b: bool) {.importcpp: "#.setBold(#)",
    header: "<QFont>".}
proc fontIsItalic*(f: QFont): bool {.importcpp: "#.italic()", header: "<QFont>".}
proc fontSetItalic*(f: var QFont; b: bool) {.importcpp: "#.setItalic(#)",
    header: "<QFont>".}

# ---------------------------------------------------------------------------
# QImage
# ---------------------------------------------------------------------------

proc imageNewDefault*(): QImage {.importcpp: "QImage()", header: "<QImage>",
                                  constructor.}
proc imageNewSize*(w: cint; h: cint): QImage
  {.importcpp: "QImage(QSize(#, #), QImage::Format_ARGB32)", header: "<QImage>",
   constructor.}
proc imageNewFromData*(data: ptr byte; w: cint; h: cint; bytesPerLine: cint): QImage
  {.importcpp: "QImage(#, #, #, #, QImage::Format_RGBA8888)", header: "<QImage>",
   constructor.}
proc imageSavePng*(i: QImage; path: cstring): bool
  {.importcpp: "#.save(QString(#), \"PNG\")", header: "<QImage>", used.}

proc imageLoadFile*(i: var QImage; path: QString): bool
  {.importcpp: "#.load(#)", header: "<QImage>".}
proc imageSaveFile*(i: QImage; path: QString; fmt: QString = toQString("PNG")): bool
  {.importcpp: "#.save(#, #)", header: "<QImage>".}
proc imageWidthPx*(i: QImage): cint {.importcpp: "#.width()", header: "<QImage>".}
proc imageHeightPx*(i: QImage): cint {.importcpp: "#.height()", header: "<QImage>".}
proc imageIsNull*(i: QImage): bool {.importcpp: "#.isNull()", header: "<QImage>".}
proc imageSize*(i: QImage): QSize {.importcpp: "#.size()", header: "<QImage>".}
proc sizeW*(s: QSize): cint {.importcpp: "#.width()", header: "<QSize>".}
proc sizeH*(s: QSize): cint {.importcpp: "#.height()", header: "<QSize>".}
proc qsizeNew*(w: cint; h: cint): QSize {.importcpp: "QSize(@)", header: "<QSize>",
                                          constructor.}

# ---------------------------------------------------------------------------
# QStandardItemModel + QStandardItem (item-views framework)
# ---------------------------------------------------------------------------

type
  QStandardItem* {.importcpp: "QStandardItem", header: "<QStandardItem>",
                   inheritable, pure.} = object of QObject
  QStandardItemModel* {.importcpp: "QStandardItemModel",
                        header: "<QStandardItemModel>",
                        inheritable.} = object of QAbstractItemModel
  QModelIndex* {.importcpp: "QModelIndex", header: "<QAbstractItemModel>",
                pure, bycopy.} = object
  QAbstractItemModel* {.importcpp: "QAbstractItemModel",
                        header: "<QAbstractItemModel>",
                        inheritable, pure.} = object of QObject

proc qstandarditemNewText*(text: QString): ptr QStandardItem
  {.importcpp: "new QStandardItem(#)", header: "<QStandardItem>",
   constructor.}
proc qstandarditemmodelNew*(parent: ptr QObject = nil): ptr QStandardItemModel
  {.importcpp: "new QStandardItemModel(@)", header: "<QStandardItemModel>",
   constructor.}
proc qstandarditemmodelDispose*(m: ptr QStandardItemModel)
  {.importcpp: "delete #", header: "<QStandardItemModel>".}

proc siText*(it: ptr QStandardItem): QString {.importcpp: "#.text()",
    header: "<QStandardItem>".}
proc siSetText*(it: ptr QStandardItem; t: QString) {.importcpp: "#.setText(#)",
    header: "<QStandardItem>".}
proc siTextStr*(it: ptr QStandardItem): string {.inline.} = siText(it).toString()

proc simRowCount*(m: ptr QStandardItemModel): cint
  {.importcpp: "#.rowCount()", header: "<QStandardItemModel>".}
proc simColumnCount*(m: ptr QStandardItemModel): cint
  {.importcpp: "#.columnCount()", header: "<QStandardItemModel>".}
proc simSetRowCount*(m: ptr QStandardItemModel; n: cint): bool
  {.importcpp: "#.setRowCount(#)", header: "<QStandardItemModel>".}
proc simSetColumnCount*(m: ptr QStandardItemModel; n: cint): bool
  {.importcpp: "#.setColumnCount(#)", header: "<QStandardItemModel>".}
proc simIndex*(m: ptr QStandardItemModel; row: cint; col: cint;
              parent: QModelIndex = QModelIndex()): QModelIndex
  {.importcpp: "#->index(#, #, #)", header: "<QStandardItemModel>".}
proc simSetItem*(m: ptr QStandardItemModel; row: cint; col: cint;
                item: ptr QStandardItem): bool
  {.importcpp: "#->setItem(#, #, #)", header: "<QStandardItemModel>".}
proc simData*(m: ptr QStandardItemModel; idx: QModelIndex; role: cint): QVariant
  {.importcpp: "#->data(#, QModelIndex::DataRole(#))",
   header: "<QStandardItemModel>".}
proc simHeaderData*(m: ptr QStandardItemModel; section: cint;
                    orient: cint; role: cint): QVariant
  {.importcpp: "#->headerData(#, Qt::Orientation(#), QModelIndex::DataRole(#))",
   header: "<QStandardItemModel>".}
proc simDataStr*(m: ptr QStandardItemModel; row: cint; col: cint; role: cint): string =
  simData(m, simIndex(m, row, col), role).toString()
proc simHeaderDataStr*(m: ptr QStandardItemModel; section: cint;
                       orient: cint; role: cint): string =
  simHeaderData(m, section, orient, role).toString()
proc simRowCountStr*(m: ptr QStandardItemModel): string {.inline.} =
  $simRowCount(m)
proc simColumnCountStr*(m: ptr QStandardItemModel): string {.inline.} =
  $simColumnCount(m)

proc qmiIsValid*(idx: QModelIndex): bool {.importcpp: "#.isValid()",
    header: "<QModelIndex>".}
proc qmiRow*(idx: QModelIndex): cint {.importcpp: "#.row()",
    header: "<QModelIndex>".}
proc qmiColumn*(idx: QModelIndex): cint {.importcpp: "#.column()",
    header: "<QModelIndex>".}

# Member-style forwarders (so test can call `m.rowCount()`, `model.data(...)`).
proc rowCount*(m: ptr QStandardItemModel): int {.inline.} = int(simRowCount(m))
proc columnCount*(m: ptr QStandardItemModel): int {.inline.} = int(simColumnCount(m))
proc setRowCount*(m: ptr QStandardItemModel; n: int): bool
  {.inline.} = simSetRowCount(m, cint(n))
proc setColumnCount*(m: ptr QStandardItemModel; n: int): bool
  {.inline.} = simSetColumnCount(m, cint(n))
proc index*(m: ptr QStandardItemModel; row, col: int): QModelIndex
  {.inline.} = simIndex(m, cint(row), cint(col), QModelIndex())
proc setItem*(m: ptr QStandardItemModel; row, col: int; it: ptr QStandardItem): bool
  {.inline.} = simSetItem(m, cint(row), cint(col), it)
proc data*(m: ptr QStandardItemModel; row, col, role: int): QVariant
  {.inline.} = simData(m, simIndex(m, cint(row), cint(col)), cint(role))
proc headerData*(m: ptr QStandardItemModel; section, orient, role: int): QVariant
  {.inline.} = simHeaderData(m, cint(section), cint(orient), cint(role))
proc isValid*(idx: QModelIndex): bool {.inline.} = qmiIsValid(idx)
proc row*(idx: QModelIndex): int {.inline.} = int(qmiRow(idx))
proc column*(idx: QModelIndex): int {.inline.} = int(qmiColumn(idx))

const QtRole_DisplayRole* = 0
const QtRole_DecorationRole* = 1
const QtRole_EditRole* = 2
const QtRole_ToolTipRole* = 3
const QtRole_UserRole* = 256
const QtHorizontal* = 0
const QtVertical* = 1

{.pop.}
