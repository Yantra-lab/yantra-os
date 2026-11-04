## A spreadsheet-scale grid (P8) on one Canvas node: only the cells that show are drawn,
## so a million cells cost what a screenful costs. Frozen rows and columns, row and column
## headers, column resize by dragging a header edge, a selected cell, and an edit hook that
## says where to put an editor. Scrolling is the engine's (wheel on a canvas with a Scroll
## handler, bounded by canvasWidth/canvasHeight).
import std/[strutils, algorithm]
import ../core/[wire, runtime]

type
  Sheet* = ref object
    node*: Node                          ## the Canvas
    rows*, cols*: int
    colW*: seq[float32]                  ## width of each column
    rowH*: float32
    frozenRows*, frozenCols*: int
    headerH*, headerW*: float32          ## the A B C row and the 1 2 3 column (0: none)
    cell*: proc (r, c: int): string      ## what a cell shows
    onEdit*: proc (r, c: int; x, y, w, h: float32)   ## a click on the selected cell: put an editor there (node px)
    onSelect*: proc (r, c: int)
    selR*, selC*: int
    ink*, grid*, head*, headInk*, sel*, bg*: uint32
    fontSize*: float32
    colX: seq[float32]                   ## colX[i]: left of column i in content px (headers excluded)
    sx, sy, vw, vh: float32
    dragCol: int
    dragFrom, dragW: float32

proc colName*(c: int): string =
  ## 0 -> A, 25 -> Z, 26 -> AA.
  var n = c + 1
  while n > 0:
    let m = (n - 1) mod 26
    result.insert($chr(ord('A') + m), 0)
    n = (n - 1) div 26

proc layoutCols(s: Sheet) =
  s.colX.setLen(s.cols + 1)
  var x = 0'f32
  for i in 0 ..< s.cols:
    s.colX[i] = x
    x += (if i < s.colW.len: s.colW[i] else: 100'f32)
  s.colX[s.cols] = x
  s.node.set(pCanvasWidth, s.headerW + x)
  s.node.set(pCanvasHeight, s.headerH + float32(s.rows) * s.rowH)

proc colAt(s: Sheet; x: float32): int =
  ## The column whose span holds content x.
  max(0, min(s.cols - 1, s.colX.upperBound(x) - 1))

proc esc(t: string): string = t.replace(";", "\\;")
proc f(v: float32): string = formatFloat(v, ffDecimal, 1)
proc col(v: uint32): string = $v

proc cellRect*(s: Sheet; r, c: int): (float32, float32, float32, float32) =
  ## Where cell (r, c) is on the canvas now (node px): frozen ones don't scroll.
  let x = s.headerW + s.colX[c] - (if c < s.frozenCols: 0'f32 else: s.sx)
  let y = s.headerH + float32(r) * s.rowH - (if r < s.frozenRows: 0'f32 else: s.sy)
  (x, y, s.colX[c + 1] - s.colX[c], s.rowH)

proc redraw*(s: Sheet) =
  ## Rebuilds the draw list from what shows: O(visible cells).
  var d = newStringOfCap(8192)
  d.add "R 0 0 " & f(s.vw) & " " & f(s.vh) & " 0 " & col(s.bg) & ";"
  let fx = s.colX[min(s.frozenCols, s.cols)]                 # frozen width / height, content px
  let fy = float32(s.frozenRows) * s.rowH
  proc span(lo, hi: float32; isCol: bool): (int, int) =
    if isCol: (s.colAt(lo), s.colAt(hi))
    else: (max(0, int(lo / s.rowH)), min(s.rows - 1, int(hi / s.rowH)))
  proc cells(d: var string; r0, r1, c0, c1: int) =
    for r in r0 .. r1:
      for c in c0 .. c1:
        let (x, y, w, h) = s.cellRect(r, c)
        let t = if s.cell != nil: s.cell(r, c) else: ""
        if r == s.selR and c == s.selC: d.add "R " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " 0 " & col(s.sel) & ";"
        d.add "B " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " 0 " & col(s.grid) & " 1;"
        if t.len > 0:
          d.add "P;K " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & ";T " & f(x + 6) & " " & f(y + (h - s.fontSize * 1.3) / 2) &
                " " & f(s.fontSize) & " " & col(s.ink) & " 400 " & esc(t) & ";p;"
  let bodyC = span(fx + s.sx, fx + s.sx + max(0, s.vw - s.headerW - fx), true)
  let bodyR = span(fy + s.sy, fy + s.sy + max(0, s.vh - s.headerH - fy), false)
  let bc0 = max(bodyC[0], s.frozenCols)
  let br0 = max(bodyR[0], s.frozenRows)
  # the scrolling body, then frozen columns, frozen rows, their corner, then headers: each over the last
  d.add "P;K " & f(s.headerW + fx) & " " & f(s.headerH + fy) & " " & f(s.vw) & " " & f(s.vh) & ";"
  cells(d, br0, bodyR[1], bc0, bodyC[1])
  d.add "p;"
  if s.frozenCols > 0:
    d.add "P;K " & f(s.headerW) & " " & f(s.headerH + fy) & " " & f(fx) & " " & f(s.vh) & ";"
    cells(d, br0, bodyR[1], 0, s.frozenCols - 1)
    d.add "p;"
  if s.frozenRows > 0:
    d.add "P;K " & f(s.headerW + fx) & " " & f(s.headerH) & " " & f(s.vw) & " " & f(fy) & ";"
    cells(d, 0, s.frozenRows - 1, bc0, bodyC[1])
    d.add "p;"
    if s.frozenCols > 0: cells(d, 0, s.frozenRows - 1, 0, s.frozenCols - 1)
  if s.headerH > 0:
    d.add "R 0 0 " & f(s.vw) & " " & f(s.headerH) & " 0 " & col(s.head) & ";"
    for c in 0 ..< s.frozenCols:
      let (x, _, w, _) = s.cellRect(0, c)
      d.add "T " & f(x + 6) & " 4 " & f(s.fontSize) & " " & col(s.headInk) & " 600 " & colName(c) & ";"
    d.add "P;K " & f(s.headerW + fx) & " 0 " & f(s.vw) & " " & f(s.headerH) & ";"
    for c in bc0 .. bodyC[1]:
      let (x, _, w, _) = s.cellRect(0, c)
      d.add "T " & f(x + 6) & " 4 " & f(s.fontSize) & " " & col(s.headInk) & " 600 " & colName(c) & ";"
      d.add "G " & f(x + w) & " 0 " & f(x + w) & " " & f(s.headerH) & " " & col(s.grid) & " 1;"
    d.add "p;"
  if s.headerW > 0:
    d.add "R 0 " & f(s.headerH) & " " & f(s.headerW) & " " & f(s.vh) & " 0 " & col(s.head) & ";"
    for r in 0 ..< s.frozenRows:
      let (_, y, _, _) = s.cellRect(r, 0)
      d.add "T 4 " & f(y + 4) & " " & f(s.fontSize) & " " & col(s.headInk) & " 400 " & $(r + 1) & ";"
    d.add "P;K 0 " & f(s.headerH + fy) & " " & f(s.headerW) & " " & f(s.vh) & ";"
    for r in br0 .. bodyR[1]:
      let (_, y, _, _) = s.cellRect(r, 0)
      d.add "T 4 " & f(y + 4) & " " & f(s.fontSize) & " " & col(s.headInk) & " 400 " & $(r + 1) & ";"
    d.add "p;"
  s.node.set(pDraw, d)

proc hit*(s: Sheet; x, y: float32): (int, int) =
  ## The cell under node point (x, y); -1 in a header.
  if x < s.headerW or y < s.headerH: return (-1, -1)
  let fx = s.colX[min(s.frozenCols, s.cols)]
  let fy = float32(s.frozenRows) * s.rowH
  let cx = x - s.headerW
  let cy = y - s.headerH
  let c = s.colAt(if cx < fx: cx else: cx + s.sx)
  let r = int((if cy < fy: cy else: cy + s.sy) / s.rowH)
  (min(r, s.rows - 1), c)

proc newSheet*(parent: Node; rows, cols: int; cell: proc (r, c: int): string): Sheet =
  ## A sheet in `parent`; size it like any node (`grow`, width/height).
  let s = Sheet(rows: rows, cols: cols, cell: cell, rowH: 24, headerH: 24, headerW: 48, fontSize: 13,
                ink: 0xFFE8E8EE'u32, grid: 0xFF2C2C35'u32, head: 0xFF1B1B22'u32, headInk: 0xFF8C8C96'u32,
                sel: 0x33FFB23E'u32, bg: 0xFF101015'u32, dragCol: -1, selR: -1, selC: -1)
  s.node = make(nkCanvas, parent)
  s.colW = newSeq[float32](cols)
  for i in 0 ..< cols: s.colW[i] = 100
  s.layoutCols()
  let id = int32(s.node.id)
  s.node.addHandler(evResize, proc () =
    s.vw = yNodeSize(id, 0)
    s.vh = yNodeSize(id, 1)
    s.redraw())
  s.node.addHandler(evScroll, proc () =
    s.sy = yNodeSize(id, 2)
    s.sx = yNodeSize(id, 9)
    s.redraw())
  s.node.addHandler(evPointerDown, proc () =
    let x = yNodeSize(id, 7)
    let y = yNodeSize(id, 8)
    if y < s.headerH and x >= s.headerW:          # a header edge: resize that column
      for c in 0 ..< s.cols:
        let (cx, _, w, _) = s.cellRect(0, c)
        if abs(x - (cx + w)) <= 4:
          s.dragCol = c
          s.dragFrom = x
          s.dragW = w
          return
      return
    let (r, c) = s.hit(x, y)
    if r < 0: return
    if r == s.selR and c == s.selC and s.onEdit != nil:
      let (cx, cy, w, h) = s.cellRect(r, c)
      s.onEdit(r, c, cx, cy, w, h)
      return
    s.selR = r
    s.selC = c
    if s.onSelect != nil: s.onSelect(r, c)
    s.redraw())
  s.node.addHandler(evPointerMove, proc () =
    if s.dragCol < 0: return
    s.colW[s.dragCol] = max(24'f32, s.dragW + yNodeSize(id, 7) - s.dragFrom)
    s.layoutCols()
    s.redraw())
  s.node.addHandler(evPointerUp, proc () = s.dragCol = -1)
  s
