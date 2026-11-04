import std/[os, strutils]

const currentDir = currentSourcePath().parentDir().replace('\\', '/')
when defined(emscripten):
  const yogaWebLib {.strdefine.} = ""                        # tools/build-web.sh passes it
  {.passL: "\"" & yogaWebLib & "\"".}
else:
  {.passL: currentDir & "/../build/libyoga.a -lstdc++".}

type
  YGNodeRef = pointer

  FlexDirection* = enum
    fdColumn = 0
    fdColumnReverse = 1
    fdRow = 2
    fdRowReverse = 3

  Edge* = enum
    edgeLeft = 0
    edgeTop = 1
    edgeRight = 2
    edgeBottom = 3
    edgeStart = 4
    edgeEnd = 5
    edgeHorizontal = 6
    edgeVertical = 7
    edgeAll = 8

  Gutter* = enum
    gutterColumn = 0
    gutterRow = 1
    gutterAll = 2

  Direction* = enum
    dirInherit = 0
    dirLTR = 1
    dirRTL = 2

  LayoutResult* = object
    left*, top*, width*, height*: float32

  YogaNodeObj = object
    raw: YGNodeRef
  YogaNode* = ref YogaNodeObj

proc c_YGNodeNew(): YGNodeRef {.importc: "YGNodeNew", cdecl.}
proc c_YGNodeFree(node: YGNodeRef) {.importc: "YGNodeFree", cdecl.}
proc c_YGNodeFreeRecursive(node: YGNodeRef) {.importc: "YGNodeFreeRecursive", cdecl.}
proc c_YGNodeInsertChild(node, child: YGNodeRef; index: csize_t) {.importc: "YGNodeInsertChild", cdecl.}
proc c_YGNodeRemoveChild(node, child: YGNodeRef) {.importc: "YGNodeRemoveChild", cdecl.}
proc c_YGNodeStyleSetFlexDirection(node: YGNodeRef; dir: cint) {.importc: "YGNodeStyleSetFlexDirection", cdecl.}
proc c_YGNodeStyleSetWidth(node: YGNodeRef; width: cfloat) {.importc: "YGNodeStyleSetWidth", cdecl.}
proc c_YGNodeStyleSetHeight(node: YGNodeRef; height: cfloat) {.importc: "YGNodeStyleSetHeight", cdecl.}
proc c_YGNodeStyleSetFlexGrow(node: YGNodeRef; flexGrow: cfloat) {.importc: "YGNodeStyleSetFlexGrow", cdecl.}
proc c_YGNodeStyleSetPadding(node: YGNodeRef; edge: cint; padding: cfloat) {.importc: "YGNodeStyleSetPadding", cdecl.}
proc c_YGNodeStyleSetGap(node: YGNodeRef; gutter: cint; gapLength: cfloat) {.importc: "YGNodeStyleSetGap", cdecl.}
proc c_YGNodeCalculateLayout(node: YGNodeRef; availableWidth, availableHeight: cfloat; ownerDirection: cint) {.importc: "YGNodeCalculateLayout", cdecl.}
proc c_YGNodeLayoutGetLeft(node: YGNodeRef): cfloat {.importc: "YGNodeLayoutGetLeft", cdecl.}
proc c_YGNodeLayoutGetTop(node: YGNodeRef): cfloat {.importc: "YGNodeLayoutGetTop", cdecl.}
proc c_YGNodeLayoutGetWidth(node: YGNodeRef): cfloat {.importc: "YGNodeLayoutGetWidth", cdecl.}
proc c_YGNodeLayoutGetHeight(node: YGNodeRef): cfloat {.importc: "YGNodeLayoutGetHeight", cdecl.}

proc newNode*(): YogaNode =
  YogaNode(raw: c_YGNodeNew())

proc free*(node: YogaNode; recursive = false) =
  if node != nil and node.raw != nil:
    if recursive:
      c_YGNodeFreeRecursive(node.raw)
    else:
      c_YGNodeFree(node.raw)
    node.raw = nil

proc insertChild*(node, child: YogaNode; index: int) =
  c_YGNodeInsertChild(node.raw, child.raw, csize_t(index))

proc removeChild*(node, child: YogaNode) =
  c_YGNodeRemoveChild(node.raw, child.raw)

proc setFlexDirection*(node: YogaNode; dir: FlexDirection) =
  c_YGNodeStyleSetFlexDirection(node.raw, cint(ord(dir)))

proc setWidth*(node: YogaNode; width: float32) =
  c_YGNodeStyleSetWidth(node.raw, cfloat(width))

proc setHeight*(node: YogaNode; height: float32) =
  c_YGNodeStyleSetHeight(node.raw, cfloat(height))

proc setFlexGrow*(node: YogaNode; grow: float32) =
  c_YGNodeStyleSetFlexGrow(node.raw, cfloat(grow))

proc setPadding*(node: YogaNode; edge: Edge; padding: float32) =
  c_YGNodeStyleSetPadding(node.raw, cint(ord(edge)), cfloat(padding))

proc setGap*(node: YogaNode; gutter: Gutter; gap: float32) =
  c_YGNodeStyleSetGap(node.raw, cint(ord(gutter)), cfloat(gap))

proc calculateLayout*(node: YogaNode; availableWidth = NaN; availableHeight = NaN; dir = dirLTR) =
  c_YGNodeCalculateLayout(node.raw, cfloat(availableWidth), cfloat(availableHeight), cint(ord(dir)))

proc layout*(node: YogaNode): LayoutResult =
  LayoutResult(
    left: float32(c_YGNodeLayoutGetLeft(node.raw)),
    top: float32(c_YGNodeLayoutGetTop(node.raw)),
    width: float32(c_YGNodeLayoutGetWidth(node.raw)),
    height: float32(c_YGNodeLayoutGetHeight(node.raw))
  )

# --- E4: what a UI engine needs beyond the basics --------------------------------
# Enum values mirror yoga-3.1.0/yoga/YGEnums.h exactly (checked by tests/t_layout.nim).

type
  YAlign* = enum
    yaAuto = 0, yaStart = 1, yaCenter = 2, yaEnd = 3, yaStretch = 4, yaBaseline = 5,
    yaSpaceBetween = 6, yaSpaceAround = 7, yaSpaceEvenly = 8
  YJustify* = enum
    yjStart = 0, yjCenter = 1, yjEnd = 2, yjSpaceBetween = 3, yjSpaceAround = 4, yjSpaceEvenly = 5
  YDisplay* = enum
    ydFlex = 0, ydNone = 1
  MeasureMode* = enum
    mmUndefined = 0, mmExactly = 1, mmAtMost = 2
  YGSize* {.bycopy.} = object
    width*, height*: cfloat
  MeasureFunc* = proc (node: pointer; width: cfloat; widthMode: cint; height: cfloat;
                       heightMode: cint): YGSize {.cdecl.}

proc c_YGNodeStyleSetAlignItems(n: YGNodeRef; a: cint) {.importc: "YGNodeStyleSetAlignItems", cdecl.}
proc c_YGNodeStyleSetAlignSelf(n: YGNodeRef; a: cint) {.importc: "YGNodeStyleSetAlignSelf", cdecl.}
proc c_YGNodeStyleSetJustifyContent(n: YGNodeRef; j: cint) {.importc: "YGNodeStyleSetJustifyContent", cdecl.}
proc c_YGNodeStyleSetDisplay(n: YGNodeRef; d: cint) {.importc: "YGNodeStyleSetDisplay", cdecl.}
proc c_YGNodeStyleSetMargin(n: YGNodeRef; e: cint; v: cfloat) {.importc: "YGNodeStyleSetMargin", cdecl.}
proc c_YGNodeStyleSetMinWidth(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetMinWidth", cdecl.}
proc c_YGNodeStyleSetMinHeight(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetMinHeight", cdecl.}
proc c_YGNodeStyleSetMaxWidth(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetMaxWidth", cdecl.}
proc c_YGNodeStyleSetFlexShrink(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetFlexShrink", cdecl.}
proc c_YGNodeSetMeasureFunc(n: YGNodeRef; f: MeasureFunc) {.importc: "YGNodeSetMeasureFunc", cdecl.}
proc c_YGNodeSetContext(n: YGNodeRef; ctx: pointer) {.importc: "YGNodeSetContext", cdecl.}
proc c_YGNodeGetContext(n: pointer): pointer {.importc: "YGNodeGetContext", cdecl.}
proc c_YGNodeMarkDirty(n: YGNodeRef) {.importc: "YGNodeMarkDirty", cdecl.}
proc c_YGNodeGetChildCount(n: YGNodeRef): csize_t {.importc: "YGNodeGetChildCount", cdecl.}

proc setAlignItems*(n: YogaNode; a: YAlign) = c_YGNodeStyleSetAlignItems(n.raw, cint(ord(a)))
proc setAlignSelf*(n: YogaNode; a: YAlign) = c_YGNodeStyleSetAlignSelf(n.raw, cint(ord(a)))
proc setJustifyContent*(n: YogaNode; j: YJustify) = c_YGNodeStyleSetJustifyContent(n.raw, cint(ord(j)))
proc setDisplay*(n: YogaNode; d: YDisplay) = c_YGNodeStyleSetDisplay(n.raw, cint(ord(d)))
proc setMargin*(n: YogaNode; e: Edge; v: float32) = c_YGNodeStyleSetMargin(n.raw, cint(ord(e)), v)
proc setMinWidth*(n: YogaNode; v: float32) = c_YGNodeStyleSetMinWidth(n.raw, v)
proc setMinHeight*(n: YogaNode; v: float32) = c_YGNodeStyleSetMinHeight(n.raw, v)
proc setMaxWidth*(n: YogaNode; v: float32) = c_YGNodeStyleSetMaxWidth(n.raw, v)
proc setFlexShrink*(n: YogaNode; v: float32) = c_YGNodeStyleSetFlexShrink(n.raw, v)
proc setMeasureFunc*(n: YogaNode; f: MeasureFunc) =
  ## Makes `n` a leaf whose size Yoga asks for (text). A measured node can't have children.
  c_YGNodeSetMeasureFunc(n.raw, f)
proc setContext*(n: YogaNode; ctx: pointer) = c_YGNodeSetContext(n.raw, ctx)
proc contextOf*(rawNode: pointer): pointer = c_YGNodeGetContext(rawNode)
  ## Inside a MeasureFunc: the context set on the node being measured.
proc markDirty*(n: YogaNode) = c_YGNodeMarkDirty(n.raw)
proc childCount*(n: YogaNode): int = int(c_YGNodeGetChildCount(n.raw))

# --- E5: positioning, wrapping, scrolling --------------------------------------------
type
  YPosition* = enum ypStatic = 0, ypRelative = 1, ypAbsolute = 2
  YWrap* = enum ywNoWrap = 0, ywWrap = 1, ywWrapReverse = 2
  YOverflow* = enum yoVisible = 0, yoHidden = 1, yoScroll = 2

proc c_YGNodeStyleSetPositionType(n: YGNodeRef; t: cint) {.importc: "YGNodeStyleSetPositionType", cdecl.}
proc c_YGNodeStyleSetPosition(n: YGNodeRef; e: cint; v: cfloat) {.importc: "YGNodeStyleSetPosition", cdecl.}
proc c_YGNodeStyleSetFlexWrap(n: YGNodeRef; w: cint) {.importc: "YGNodeStyleSetFlexWrap", cdecl.}
proc c_YGNodeStyleSetOverflow(n: YGNodeRef; o: cint) {.importc: "YGNodeStyleSetOverflow", cdecl.}
proc c_YGNodeStyleSetMaxHeight(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetMaxHeight", cdecl.}

proc setPositionType*(n: YogaNode; t: YPosition) = c_YGNodeStyleSetPositionType(n.raw, cint(ord(t)))
proc setPosition*(n: YogaNode; e: Edge; v: float32) =
  ## An inset (top/left/right/bottom) for absolute or relative positioning.
  c_YGNodeStyleSetPosition(n.raw, cint(ord(e)), v)
proc setFlexWrap*(n: YogaNode; w: YWrap) = c_YGNodeStyleSetFlexWrap(n.raw, cint(ord(w)))
proc c_YGNodeStyleSetFlexBasis(n: YGNodeRef; v: cfloat) {.importc: "YGNodeStyleSetFlexBasis", cdecl.}
proc setFlexBasis*(n: YogaNode; v: float32) = c_YGNodeStyleSetFlexBasis(n.raw, v)
  ## The size along the main axis before growing and shrinking (0: only what grow gives it).
proc setOverflow*(n: YogaNode; o: YOverflow) = c_YGNodeStyleSetOverflow(n.raw, cint(ord(o)))
proc setMaxHeight*(n: YogaNode; v: float32) = c_YGNodeStyleSetMaxHeight(n.raw, v)

# --- keeping a tree between layouts (P1): relink and restyle nodes in place -------------
proc c_YGNodeGetChild(n: YGNodeRef; i: csize_t): YGNodeRef {.importc: "YGNodeGetChild", cdecl.}
proc c_YGNodeGetOwner(n: YGNodeRef): YGNodeRef {.importc: "YGNodeGetOwner", cdecl.}
proc c_YGNodeCopyStyle(dst, src: YGNodeRef) {.importc: "YGNodeCopyStyle", cdecl.}
proc c_YGNodeIsDirty(n: YGNodeRef): bool {.importc: "YGNodeIsDirty", cdecl.}

proc rawOf*(n: YogaNode): pointer = n.raw
  ## The C node, only for identity checks against `childAt`.
proc childAt*(n: YogaNode; i: int): pointer = c_YGNodeGetChild(n.raw, csize_t(i))
  ## The i-th child's C node (compare with `rawOf`).
proc removeChildAt*(n: YogaNode; child: pointer) = c_YGNodeRemoveChild(n.raw, child)
  ## Removes a child named by its C node (Yoga forgets its cached layout).
proc detach*(n: YogaNode) =
  ## Takes the node out of whatever node holds it, so it can be inserted elsewhere.
  let o = c_YGNodeGetOwner(n.raw)
  if o != nil: c_YGNodeRemoveChild(o, n.raw)
proc hasOwner*(n: YogaNode): bool = c_YGNodeGetOwner(n.raw) != nil
proc copyStyle*(dst, src: YogaNode) = c_YGNodeCopyStyle(dst.raw, src.raw)
  ## Gives `dst` exactly `src`'s style (and marks it dirty only if that changed its style).
proc isDirty*(n: YogaNode): bool = c_YGNodeIsDirty(n.raw)
proc c_YGNodeStyleSetDirection(n: YGNodeRef; d: cint) {.importc: "YGNodeStyleSetDirection", cdecl.}
proc setDirection*(n: YogaNode; d: Direction) = c_YGNodeStyleSetDirection(n.raw, cint(ord(d)))
  ## Right-to-left mirrors rows, start/end and insets under this node (P9).
