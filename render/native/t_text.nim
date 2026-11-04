## Text editing (T1), driven like a person would in the Notes app
## (examples/shell/notes.wasm): click, drag, double-click, Shift+arrows, Ctrl+A/C/X/V/Z/Y,
## word jumps, a multi-line text area, Tab focus order, and Hindi.
import std/[os, tables, strutils, unicode]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

const
  Shift = 0x0001'i32
  Ctrl = 0x0040'i32
  Tab = 9'i32
  Enter = 13'i32
  Backspace = 8'i32
  Right = 0x4000004f'i32
  Left = 0x40000050'i32
  Down = 0x40000051'i32
  Up = 0x40000052'i32
  Home = 0x4000004a'i32
  End = 0x4000004d'i32

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
let e = start(dir / "notes.wasm", 900, 640)
var px = newSeq[uint32](900 * 640)
var clock = 0.0
let shots = getEnv("YANTRA_SHOTS")          # set it to a folder to also save frames
proc frame(shot = "") =
  clock += 1000
  e.tick(clock)
  e.paintFrame(addr px[0], 900, 640)
  if shots.len > 0 and shot.len > 0:
    var bytes = newString(px.len * 4)
    copyMem(addr bytes[0], addr px[0], bytes.len)
    writeFile(shots / shot & ".raw", bytes)

proc nodeWhere(kind: int32; pred: proc (n: tree.Node): bool): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and pred(n): return int32(i)
  -1
proc value(id: int32): string = e.node(id).sProp(P_VALUE)
proc at(id: int32; fx, fy: float32): (float32, float32) =
  e.ensureLayout()
  let b = e.boxes[id]
  (b.x + b.w * fx, b.y + b.h * fy - e.scrollY)
proc click(id: int32; fx = 0.5'f32; fy = 0.5'f32) =
  clock += 1000
  e.tick(clock)
  let (x, y) = at(id, fx, fy)
  e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y)
proc key(code: int32; mods = 0'i32) = e.key(code, mods)
proc hasText(label: string): bool =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == label: return true

frame()
let title = nodeWhere(K_INPUT, proc (n: tree.Node): bool = n.sProp(P_VALUE) == "Pitch outline")
let body = nodeWhere(K_TEXTAREA, proc (n: tree.Node): bool = true)
check("Notes shows the title input and a multi-line body", title >= 0 and body >= 0)

# select all, type over it, undo, redo
click(title)
check("clicking an input focuses it", e.focus == title)
key(int32(ord('a')), Ctrl)
check("Ctrl+A selects everything", e.selection == "Pitch outline", e.selection)
e.typeText("Deck")
e.ensureLayout()
check("typing replaces the selection", value(title) == "Deck", value(title))
check("and the app sees it (the list row renamed)", hasText("Deck"))
e.typeText(" plan")
key(int32(ord('z')), Ctrl)
check("Ctrl+Z undoes a run of typing in one step", value(title) == "Pitch outline", value(title))
key(int32(ord('y')), Ctrl)
check("Ctrl+Y redoes it", value(title) == "Deck plan", value(title))
key(int32(ord('z')), Ctrl or Shift)
check("Ctrl+Shift+Z is redo too (nothing left to redo)", value(title) == "Deck plan", value(title))
key(int32(ord('z')), Ctrl)
check("back to the start", value(title) == "Pitch outline", value(title))

# keyboard selection and the clipboard
key(End)
for _ in 0 ..< 3: key(Left, Shift)
check("Shift+Left extends the selection", e.selection == "ine", e.selection)
key(int32(ord('c')), Ctrl)
check("Ctrl+C copies it", clipboardGet() == "ine", clipboardGet())
key(Home)
check("an arrow without Shift drops the selection", e.selection == "" and e.caret == 0)
key(int32(ord('v')), Ctrl)
check("Ctrl+V pastes at the caret", value(title) == "inePitch outline", value(title))
key(int32(ord('z')), Ctrl)
key(Home)
key(Right, Ctrl)
check("Ctrl+Right jumps a word", e.caret == 5, $e.caret)
key(Right, Ctrl or Shift)
check("Ctrl+Shift+Right selects the next word", e.selection == " outline", e.selection)
key(int32(ord('x')), Ctrl)
check("Ctrl+X cuts it", value(title) == "Pitch" and clipboardGet() == " outline", value(title))
key(Backspace, Ctrl)
check("Ctrl+Backspace deletes a word", value(title) == "", value(title))
key(int32(ord('z')), Ctrl)
key(int32(ord('z')), Ctrl)
check("and undo brings it all back", value(title) == "Pitch outline", value(title))

# the mouse: drag and double-click
let (x0, y0) = at(title, 0.02, 0.5)
let (x1, y1) = at(title, 0.20, 0.5)
clock += 1000; e.tick(clock)
e.pointerMove(x0, y0); e.pointerDown(x0, y0); e.pointerMove(x1, y1); e.pointerUp(x1, y1)
check("dragging selects text", e.selection.len > 0 and "Pitch outline".startsWith(e.selection), e.selection)
clock += 1000; e.tick(clock)
let (wx, wy) = at(title, 0.03, 0.5)
e.pointerMove(wx, wy); e.pointerDown(wx, wy); e.pointerUp(wx, wy)
e.tick(clock + 150)
e.pointerDown(wx, wy); e.pointerUp(wx, wy)
check("double-click selects a word", e.selection == "Pitch", e.selection)

# Tab: title -> body, which selects the body's text
key(Tab)
check("Tab moves on to the body", e.focus == body)
check("and selects its text", e.selection == value(body), e.selection)

# the text area: new lines, growing, moving between lines
key(End, Ctrl)
e.ensureLayout()
let h0 = e.boxes[body].h
let lines0 = value(body)
key(Enter)
e.typeText("Second line")
key(Enter)
e.typeText("Third")
e.ensureLayout()
check("Enter makes new lines in a text area", value(body) == lines0 & "\nSecond line\nThird", value(body).escape)
check("the app keeps them", value(body).count('\n') == 2)
key(Up)
let lineStart = value(body).find("Second")
check("Up moves to the line above", e.caret >= lineStart and e.caret <= lineStart + 11, $e.caret)
key(Home)
check("Home goes to the start of that line", e.caret == lineStart, $e.caret & " vs " & $lineStart)
key(End, Shift)
check("Shift+End selects to its end", e.selection == "Second line", e.selection)
frame("text-selection")
key(Down)
check("Down drops the selection and goes to the next line", e.selection == "" and e.caret > lineStart + 11)
for _ in 0 ..< 30:
  key(Enter)
  e.typeText("more")
e.ensureLayout()
check("a text area grows with its text (or scrolls inside its box)", e.boxes[body].h > h0 or
      e.textScroll.getOrDefault(body, 0) > 0, $h0 & " -> " & $e.boxes[body].h)

# Hindi
key(End, Ctrl)
e.typeText(" नमस्ते")
key(Backspace)
let hindiOk = validateUtf8(value(body)) == -1 and value(body).endsWith("नमस्त")
check("Backspace removes a whole character in Hindi, never half of one", hindiOk, value(body)[^20 .. ^1])

# keyboard focus reaches buttons, and Enter presses them
var newBtn = nodeWhere(K_BUTTON, proc (n: tree.Node): bool = n.sProp(P_TEXT) == "New")
e.focusOn(-1)
var guard = 0
while e.focus != newBtn and guard < 40:
  key(Tab); inc guard
check("Tab reaches the New button", e.focus == newBtn and e.focusVisible)
frame()
key(Enter)
e.ensureLayout()
check("Enter presses it (a new note appears)", hasText("Untitled"))

# an input method's word in progress (IME): shown in place, not in the value until committed
click(title)
key(End)
let before = value(title)
proc titlePixels(): seq[uint32] =
  frame()
  let b = e.boxes[title]
  for y in int(b.y) ..< int(b.y + b.h):
    for x in int(b.x) ..< int(b.x + b.w): result.add px[y * 900 + x]
let plain = titlePixels()
e.preedit("नम", -1)
let composing = titlePixels()
check("a word being composed does not change the value yet", value(title) == before and e.preeditText == "नम")
check("but it is drawn at the caret", composing != plain)
let (cx, cy, cw, ch) = e.caretRect
let tb = e.boxes[title]
let inside = cx >= tb.x and cx <= tb.x + tb.w and cy >= tb.y - e.scrollY and cy + ch <= tb.y - e.scrollY + tb.h + 1 and ch > 5
check("the caret's place for the candidate window is inside the field", inside, $cx & "," & $cy & " in " & $tb)
e.typeText("नमस्ते")
check("committing puts the word in and ends the composition", value(title) == before & "नमस्ते" and e.preeditText == "")
e.preedit("x", -1)
e.preedit("", -1)
check("an input method that gives up leaves nothing behind", e.preeditText == "" and value(title) == before & "नमस्ते")

# --- y_text_measure wiring (SDK `textWidth`, A1) --------------------------------------------
# The app-facing half (the {.importc.} declaration, and cbTextMeasure in host/host.nim) is
# covered by the five ported apps compiling and by host's engine assertions. What is tested
# HERE is the half that could be silently wrong and would stay invisible until a port
# letter-spaced its text: that wireTextMetrics() runs at engine start, and that the op it
# installs measures with a real font rather than returning a constant.
block:
  let op = e.s.measureTextOp
  check("the engine wires text measurement at start", op != nil)
  if op != nil:
    let eyebrow = op("A HOT-SEAT GAME FOR TWO", "Palatino Linotype", 12, 400)
    check("an empty string measures 0", op("", "Palatino Linotype", 12, 400) == 0)
    check("a real string measures a real width", eyebrow > 0, $eyebrow)
    check("width grows with size",
          op("A HOT-SEAT GAME FOR TWO", "Palatino Linotype", 24, 400) > eyebrow)
    check("more characters measure wider",
          op("A HOT-SEAT GAME FOR TWO FOR TWO", "Palatino Linotype", 12, 400) > eyebrow)
    # The reason the SDK exposes this at all: five i's against five W's in Palatino. A flat
    # per-em advance would call those equal, so this fails if textWidth ever degrades to a
    # constant or to len * some fixed em - which is exactly what both ports had hand-rolled.
    check("width is not just a count times one em",
          op("iiiii", "Palatino Linotype", 12, 400) < op("WWWWW", "Palatino Linotype", 12, 400))
    let narrow = op("-", "Palatino Linotype", 12, 400)
    let wide = op("W", "Palatino Linotype", 12, 400)
    check("one glyph does not have one advance in a proportional font",
          narrow > 0 and wide > narrow * 1.5, $narrow & " vs " & $wide)

echo "text: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
