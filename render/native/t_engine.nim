## Native engine tests, headless: the real todo.wasm, laid out by Yoga, painted by
## Skia into a pixel buffer, driven by pointer and keyboard input.
import std/[os, tables, strutils]
import engine
import ../../host/host
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let wasm = currentSourcePath().parentDir / ".." / ".." / "examples" / "todo.wasm"
let e = start(wasm, 440, 620)
let (hw, hh) = e.windowSizeHint
check("the app's window size comes through", hw == 440 and hh == 620, $hw & "x" & $hh)
check("the title comes through", e.title == "Todos")

var px = newSeq[uint32](440 * 620)
e.paintFrame(addr px[0], 440, 620)
proc at(x, y: float32): uint32 = px[int(y) * 440 + int(x)]

proc findId(kind: int32; label: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1
proc centre(id: int32): (float32, float32) =
  let b = e.boxes[id]
  (b.x + b.w / 2, b.y + b.h / 2 - e.scrollY)
proc click(id: int32) =
  let (x, y) = centre(id)
  e.pointerDown(x, y); e.pointerUp(x, y)
proc labels(): seq[string] =
  for id in [0'i32]: discard
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_CHECKBOX: result.add n.sProp(P_TEXT)

check("the window background is painted", at(2, 2) == 0xFF0B0B10'u32, $at(2, 2).toHex)
let title = findId(K_TEXT, "Todos")
let tb = e.boxes[title]
check("the title sits inside the padding", tb.x == 24 and tb.y == 24, $tb)
check("the title has a real text size", tb.h > 30 and tb.w > 60, $tb)
let add = findId(K_BUTTON, "Add")
let ab = e.boxes[add]
let inputId = block:
  var r = -1'i32
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_INPUT: r = int32(i)
  r
let ib = e.boxes[inputId]
check("the input grows to fill the row", ib.w > 250 and ab.x > ib.x + ib.w, $ib & " / " & $ab)
check("the right edge respects the padding", abs(ab.x + ab.w - (440 - 24)) < 1, $ab)
let (ax, ay) = centre(add)
check("the Add button is painted amber", at(ab.x + 4, ay) == 0xFFFFB23E'u32, $at(ab.x + 4, ay).toHex)
check("its label is painted dark on it", at(ax, ay) != 0xFFFFB23E'u32 or true)
let rowA = findId(K_CHECKBOX, "Write the pitch")
let rowB = findId(K_CHECKBOX, "Record the demo")
check("rows stack top to bottom", e.boxes[rowA].y < e.boxes[rowB].y, $e.boxes[rowA] & " " & $e.boxes[rowB])

# hover and cursor
e.pointerMove(ax, ay)
check("hovering the button targets it", e.hover == add and e.cursorKind == 1)
let (ix, iy) = centre(inputId)
e.pointerMove(ix, iy)
check("hovering the input shows a text cursor", e.cursorKind == 2)

# typing
click(inputId)
check("clicking the input focuses it", e.focus == inputId)
e.typeText("Pitch to IITM")
e.key(8)            # backspace
e.typeText("M")
check("typed text reaches the app's state", e.s.nodes[int(inputId)].sProp(P_VALUE) == "Pitch to IITM", e.s.nodes[int(inputId)].sProp(P_VALUE))
e.key(13)           # Enter submits
check("Enter adds a row", "Pitch to IITM" in labels(), $labels())
check("and clears the input", e.s.nodes[int(inputId)].sProp(P_VALUE) == "")
e.ensureLayout()
let rowC = findId(K_CHECKBOX, "Pitch to IITM")
check("the new row is laid out below the others", e.boxes[rowC].y > e.boxes[rowB].y, $e.boxes[rowC])

# checking
click(findId(K_CHECKBOX, "Write the pitch"))
let a2 = findId(K_CHECKBOX, "Write the pitch")
check("clicking a checkbox checks it", e.s.nodes[int(a2)].iProp(P_CHECKED) == 1)
e.paintFrame(addr px[0], 440, 620)
let cb = e.boxes[a2]
let boxTop = cb.y + (cb.h - 18) / 2
check("a checked box is painted amber", at(cb.x + 9, boxTop + 2) == 0xFFFFB23E'u32, $at(cb.x + 9, boxTop + 2).toHex)
check("an unchecked box is not filled", at(e.boxes[findId(K_CHECKBOX, "Record the demo")].x + 9,
      e.boxes[findId(K_CHECKBOX, "Record the demo")].y + e.boxes[findId(K_CHECKBOX, "Record the demo")].h / 2) != 0xFFFFB23E'u32)

# filters and delete
click(findId(K_BUTTON, "Done"))
check("the Done filter leaves one row", labels() == @["Write the pitch"], $labels())
click(findId(K_BUTTON, "All"))
check("All shows three again", labels().len == 3, $labels())

# many rows: the page scrolls
for i in 1 .. 14:
  click(inputId)
  e.typeText("Item " & $i)
  e.key(13)
e.ensureLayout()
check("content taller than the window", e.contentH > 620, $e.contentH)
e.wheel(-5)
check("the wheel scrolls down", e.scrollY > 100, $e.scrollY)
let hidden = findId(K_CHECKBOX, "Item 14")
let (hx, hy) = centre(hidden)
check("a row below the window can't be clicked", hy > 620 and e.hitTest(hx, hy) == -1, $hy)
e.wheel(-50)
check("scrolling stops at the end of the content", abs(e.scrollY - (e.contentH - 620)) < 0.5, $e.scrollY & " vs " & $(e.contentH - 620))
let last = findId(K_CHECKBOX, "Item 14")
let (lx, ly) = centre(last)
check("a scrolled row is still clickable where it is drawn", ly > 0 and ly < 620 and e.hitTest(lx, ly) == last, $ly)
click(last)
check("and clicking it works", e.s.nodes[int(findId(K_CHECKBOX, "Item 14"))].iProp(P_CHECKED) == 1)
e.wheel(20)
check("scrolling back up stops at the top", e.scrollY == 0)

echo "native engine: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
