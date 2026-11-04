## Notion-style blocks (Q6), on the engine's block fields (P5): headings, bullets, numbered
## items, to-dos, quotes and code; markdown shortcuts as you type ("# ", "- ", "1. ", "[] ",
## "> ", "```"); Enter splits, Backspace at the start merges, arrows move between blocks;
## undo/redo across blocks (Ctrl+Z / Ctrl+Y, the app's history, not one field's); drag a
## block by its handle to move it. The model is a seq of blocks in a signal.
import std/[tables, strutils]
import ../core/[wire, runtime, signals]
import widgets, control

type
  BlockKind* = enum bkText, bkH1, bkH2, bkH3, bkBullet, bkNumbered, bkTodo, bkQuote, bkCode
  Block* = object
    id*: int
    kind*: BlockKind
    text*: string
    checked*: bool
  Shape = tuple[id: int, kind: BlockKind, checked: bool]   ## what a row is built from (text lives in its field)
  Snapshot = object
    blocks: seq[Block]
    focus, caret: int
  BlockDoc* = ref object
    blocks*: Signal[seq[Block]]
    undo, redo: seq[Snapshot]
    typingIn: int                        ## the block the current run of typing is in (-1: none)
    nextId: int
    fields: Table[int, Node]             ## block id -> its text field
    rows: Table[int, Node]
    heights: Table[int, float32]
    dragId: int
    dragFrom: float32
    focusN: int
    pending: (int, int)                  ## (block, caret) to focus once its row exists

proc newDoc*(initial: seq[Block] = @[]): BlockDoc =
  var bs = initial
  if bs.len == 0: bs.add Block(id: 1, kind: bkText)
  var mx = 0
  for b in bs: mx = max(mx, b.id)
  BlockDoc(blocks: newState(bs), typingIn: -1, nextId: mx + 1, dragId: -1, pending: (-1, 0))

proc indexOf(d: BlockDoc; id: int): int =
  for i, b in d.blocks.peek:
    if b.id == id: return i
  -1

proc textOf(d: BlockDoc; id: int): string =
  ## A block's text now: its field's value (typing updates the model as it goes too).
  if id in d.fields: d.fields[id].getStr(pValue) else: d.blocks.peek[d.indexOf(id)].text

proc snapshot(d: BlockDoc; focus, caret: int): Snapshot =
  var bs = d.blocks.peek
  for b in bs.mitems:
    if b.id in d.fields: b.text = d.fields[b.id].getStr(pValue)
  Snapshot(blocks: bs, focus: focus, caret: caret)

proc remember(d: BlockDoc; focus, caret: int) =
  d.undo.add d.snapshot(focus, caret)
  if d.undo.len > 500: d.undo.delete(0)
  d.redo.setLen(0)

proc focusBlock(d: BlockDoc; id, caret: int) =
  ## Puts the caret in block `id` (now, and again if its row is being rebuilt).
  inc d.focusN
  d.pending = (id, caret)
  if id in d.fields: d.fields[id].set(pFocusAt, $caret & "#" & $d.focusN)

proc restore(d: BlockDoc; s: Snapshot) =
  d.blocks.set(s.blocks)
  for b in s.blocks:                     # fields that stay are not rebuilt: give them their text back
    if b.id in d.fields and d.fields[b.id].getStr(pValue) != b.text: d.fields[b.id].set(pValue, b.text)
  d.typingIn = -1
  d.focusBlock(s.focus, s.caret)

const shortcuts = [("### ", bkH3), ("## ", bkH2), ("# ", bkH1), ("- ", bkBullet), ("* ", bkBullet),
                   ("1. ", bkNumbered), ("[] ", bkTodo), ("[ ] ", bkTodo), ("> ", bkQuote), ("```", bkCode)]

proc setKind(d: BlockDoc; id: int; k: BlockKind; text: string) =
  d.blocks.update(proc (bs: var seq[Block]) =
    for b in bs.mitems:
      if b.id == id: (b.kind = k; b.text = text))

proc onInput(d: BlockDoc; id: int) =
  let v = d.fields[id].getStr(pValue)
  if d.typingIn != id:                   # a new run of typing: one undo step for all of it
    var s = d.snapshot(id, v.len)
    let i = d.indexOf(id)
    if i >= 0: s.blocks[i].text = d.blocks.peek[i].text
    d.undo.add s
    d.redo.setLen(0)
    d.typingIn = id
  let i = d.indexOf(id)
  if i < 0: return
  if d.blocks.peek[i].kind == bkText:
    for (pre, k) in shortcuts:
      if v.startsWith(pre):
        let rest = v[pre.len .. ^1]
        d.remember(id, v.len)
        d.setKind(id, k, rest)           # the row is rebuilt for its new kind: put the caret back
        d.focusBlock(id, 0)
        return
  d.blocks.update(proc (bs: var seq[Block]) = bs[i].text = v)

proc split(d: BlockDoc; id: int) =
  let v = d.textOf(id)
  let at = clamp(int(yNodeSize(int32(d.fields[id].id), 6)), 0, v.len)
  d.remember(id, at)
  d.typingIn = -1
  let i = d.indexOf(id)
  let k = d.blocks.peek[i].kind
  if v.len == 0 and k in {bkBullet, bkNumbered, bkTodo, bkQuote}:   # Enter on an empty item: back to text
    d.setKind(id, bkText, "")
    d.focusBlock(id, 0)
    return
  let nk = if k in {bkBullet, bkNumbered, bkTodo}: k else: bkText
  let nb = Block(id: d.nextId, kind: nk, text: v[at .. ^1])
  inc d.nextId
  d.fields[id].set(pValue, v[0 ..< at])
  d.blocks.update(proc (bs: var seq[Block]) =
    bs[i].text = v[0 ..< at]
    bs.insert(nb, i + 1))

proc merge(d: BlockDoc; id: int) =
  let i = d.indexOf(id)
  if i <= 0: return
  let prev = d.blocks.peek[i - 1]
  let v = d.textOf(id)
  let pv = d.textOf(prev.id)
  d.remember(id, 0)
  d.typingIn = -1
  d.fields[prev.id].set(pValue, pv & v)
  d.blocks.update(proc (bs: var seq[Block]) =
    bs[i - 1].text = pv & v
    bs.delete(i))

proc moveBlock(d: BlockDoc; id, to: int) =
  let i = d.indexOf(id)
  if i < 0 or to == i: return
  d.remember(id, 0)
  d.blocks.update(proc (bs: var seq[Block]) =
    let b = bs[i]
    bs.delete(i)
    bs.insert(b, clamp(to, 0, bs.len)))

proc number(d: BlockDoc; id: int): int =
  ## 1, 2, 3 … along a run of numbered blocks.
  let bs = d.blocks.get
  var n = 0
  for b in bs:
    if b.kind == bkNumbered: inc n else: n = 0
    if b.id == id: return n

proc blockEditor*(parent: Node; d: BlockDoc) =
  ## The document: one row per block (handle, marker, field), in a column.
  let col = make(nkColumn, parent)
  col.set(pSpacing, 2'f32)
  let shapes = proc (): seq[Shape] =
    for b in d.blocks.get: result.add (b.id, b.kind, b.checked)
  keyedList[Shape](col, shapes, proc (s: Shape): string = $s.id, proc (p: Node; s: Shape) =
    let id = s.id
    let row = make(nkRow, p)
    row.set(pSpacing, 6'f32)
    row.set(pAlignItems, 0'i32)
    row.set(pTransDuration, 180'i32)          # moved blocks glide
    d.rows[id] = row
    let rid = int32(row.id)
    row.addHandler(evResize, proc () = d.heights[id] = yNodeSize(rid, 1))
    let handle = make(nkText, row)             # drag it to move the block
    handle.set(pText, "⋮⋮")
    handle.set(pFontSize, 14'i32)
    handle.set(pTextColor, cast[int32](0xFF55555E'u32))
    handle.set(pCursor, 1'i32)
    handle.addHandler(evPointerDown, proc () =
      d.dragId = id
      d.dragFrom = yNodeSize(int32(handle.id), 14))
    handle.addHandler(evPointerMove, proc () =
      if d.dragId == id:
        row.set(pY, yNodeSize(int32(handle.id), 14) - d.dragFrom)
        row.set(pZIndex, 10'i32))
    handle.addHandler(evPointerUp, proc () =
      if d.dragId != id: return
      let dy = yNodeSize(int32(handle.id), 14) - d.dragFrom
      d.dragId = -1
      row.set(pY, 0'f32)
      row.set(pZIndex, 0'i32)
      # where it was dropped: walk the rows' heights from its own place
      let i = d.indexOf(id)
      var to = i
      var left = dy
      let bs = d.blocks.peek
      if left > 0:
        while to + 1 < bs.len and left > d.heights.getOrDefault(bs[to + 1].id, 28) / 2:
          left -= d.heights.getOrDefault(bs[to + 1].id, 28)
          inc to
      else:
        while to > 0 and -left > d.heights.getOrDefault(bs[to - 1].id, 28) / 2:
          left += d.heights.getOrDefault(bs[to - 1].id, 28)
          dec to
      d.moveBlock(id, to))
    case s.kind
    of bkBullet, bkNumbered, bkQuote:
      let mark = make(nkText, row)
      mark.set(pFontSize, 16'i32)
      mark.set(pTextColor, cast[int32](0xFFA0A0B0'u32))
      if s.kind == bkBullet: mark.set(pText, "•")
      elif s.kind == bkQuote: mark.set(pText, "▎")
      else: discard createEffect(proc () = mark.set(pText, $d.number(id) & "."))
    of bkTodo:
      let box = make(nkCheckbox, row)
      box.set(pChecked, s.checked)
      box.addHandler(evChange, proc () =
        d.remember(id, 0)
        d.blocks.update(proc (bs: var seq[Block]) =
          for b in bs.mitems:
            if b.id == id: b.checked = not b.checked))
    else: discard
    let f = make(nkTextArea, row)
    d.fields[id] = f
    f.set(pBlock, true)
    f.set(pFlexGrow, 1'f32)
    f.set(pRows, 1'i32)
    f.set(pPadTop, 4'f32); f.set(pPadBottom, 4'f32)
    f.set(pFontSize, (case s.kind
      of bkH1: 28'i32
      of bkH2: 22'i32
      of bkH3: 18'i32
      else: 15'i32))
    if s.kind in {bkH1, bkH2, bkH3}: f.set(pFontWeight, 700'i32)
    if s.kind == bkCode: (f.set(pFontFamily, "Cascadia Mono"); f.set(pColor, cast[int32](0xFF1B1B22'u32)))
    if s.kind == bkTodo and s.checked: f.set(pTextColor, cast[int32](0xFF8C8C96'u32))
    let i = d.indexOf(id)
    f.set(pValue, if i >= 0: d.blocks.peek[i].text else: "")
    f.set(pPlaceholder, if d.blocks.peek.len == 1: "Type '/' for commands, or '# ' for a heading" else: "")
    if d.pending[0] == id:
      inc d.focusN
      f.set(pFocusAt, $d.pending[1] & "#" & $d.focusN)
      d.pending = (-1, 0)
    f.addHandler(evInput, proc () = d.onInput(id))
    f.addHandler(evBlockSplit, proc () = d.split(id))
    f.addHandler(evBlockMerge, proc () = d.merge(id))
    f.addHandler(evCommand, proc () =
      let fid = int32(f.id)
      if yNodeSize(fid, 15) == 1 and d.undo.len > 0:
        d.redo.add d.snapshot(id, 0)
        d.restore(d.undo.pop())
      elif yNodeSize(fid, 15) == 2 and d.redo.len > 0:
        d.undo.add d.snapshot(id, 0)
        d.restore(d.redo.pop()))
    )
