## The Yantra shell (examples/shell/shell.wasm) driven like a person would: open apps,
## type and click inside them (each in its own sandbox), switch tabs, switch themes,
## close a tab, crash an app. Headless; set YANTRA_SHOTS=dir to also save frames.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
let e = start(dir / "shell.wasm", 1280, 800)
var px = newSeq[uint32](1280 * 800)
let shots = getEnv("YANTRA_SHOTS")
var clock = 0.0                      # the motion clock, ms
proc shot(name: string) =
  ## A settled frame: paint once (motion starts from what the last frame showed),
  ## let a second pass, paint again.
  for _ in 0 .. 1:
    clock += 1000
    e.tick(clock)
    e.paintFrame(addr px[0], 1280, 800)
  if shots.len > 0:
    var bytes = newString(px.len * 4)
    copyMem(addr bytes[0], addr px[0], bytes.len)
    writeFile(shots / name & ".raw", bytes)

proc findIn(en: Engine; kind: int32; label: string): int32 =
  for i, n in en.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1
proc clickableAncestor(en: Engine; id: int32): int32 =
  var cur = id
  while cur >= 0:
    if en.s.handlerFor(cur, E_CLICK) >= 0 or en.node(cur).kind in [K_BUTTON, K_CHECKBOX]: return cur
    cur = en.node(cur).parent
  id
proc centreOf(en: Engine; id: int32): (float32, float32) =
  en.ensureLayout()
  let b = en.boxes[id]
  (b.x + b.w / 2, b.y + b.h / 2 - en.scrollY)
proc click(x, y: float32) =
  ## Like the window loop: the clock moves on (a second, so any motion has finished
  ## by the next frame), then the input arrives.
  clock += 1000
  e.tick(clock)
  e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y)
proc reveal(id: int32) =
  ## Scrolls the way a person would (the wheel, over the page) until the node is on screen.
  for _ in 0 ..< 60:
    e.ensureLayout()
    let b = e.boxes[id]
    let top = b.y - e.scrollY
    if top >= 0 and top + b.h <= e.height: return
    e.pointerMove(700, 400)
    e.wheel(if top > 0: -1 else: 1)
proc clickShell(kind: int32; label: string) =
  let target = e.clickableAncestor(e.findIn(kind, label))
  reveal(target)
  let (x, y) = e.centreOf(target)
  click(x, y)
proc activeApp(): Engine =
  for id, c in e.children:
    if e.node(id).visible and e.boxes[id].w > 0: return c
  nil
proc clickInApp(kind: int32; label: string) =
  ## Click a node inside the visible app, through the shell (the real input path).
  let app = activeApp()
  let target = app.clickableAncestor(app.findIn(kind, label))
  let (lx, ly) = app.centreOf(target)
  var box: Box
  for id, c in e.children:
    if c == app: box = e.boxes[id]
  click(box.x + lx, box.y + ly - e.scrollY)
proc appTexts(app: Engine): seq[string] =
  for n in app.s.nodes:
    if n.alive and n.kind in [K_TEXT, K_BUTTON, K_CHECKBOX] and n.sProp(P_TEXT).len > 0: result.add n.sProp(P_TEXT)

shot("1-home")
check("the shell starts on Home", e.findIn(K_TEXT, "Good evening.") >= 0)
check("no apps are running yet", e.children.len == 0)

# open Notes from its card
clickShell(K_TEXT, "Notes")
e.ensureLayout()
check("clicking a card opens a tab running that app", e.children.len == 1 and activeApp() != nil)
let notes = activeApp()
check("the app inside is Notes, in its own sandbox", notes != nil and notes.findIn(K_TEXT, "Pitch outline") >= 0 and
      notes.s != e.s, $appTexts(notes))
check("the address bar shows it", e.findIn(K_TEXT, "yantra://notes") >= 0)
shot("2-notes")

# type into the app's search box through the shell
var searchId = -1'i32
for i, n in notes.s.nodes:
  if n.alive and n.kind == K_INPUT and n.sProp(P_PLACEHOLDER) == "Search notes": searchId = int32(i)
let (sx, sy) = notes.centreOf(searchId)
var nb: Box
for id, c in e.children: nb = e.boxes[id]
click(nb.x + sx, nb.y + sy)
e.typeText("flutter")
check("typing reaches the focused input inside the app", notes.s.nodes[int(searchId)].sProp(P_VALUE) == "flutter")
notes.ensureLayout()
check("and the app filters its list", notes.findIn(K_TEXT, "Questions to expect") >= 0 and notes.findIn(K_TEXT, "Pitch outline") < 0 and
      notes.findIn(K_TEXT, "Demo script") < 0,
      $appTexts(notes))

# open the calculator from the sidebar and use it
clickShell(K_TEXT, "Calculator")
e.ensureLayout()
check("a second app opens in a second tab", e.children.len == 2)
let calc = activeApp()
check("the calculator is the visible app", calc != nil and calc != notes and calc.findIn(K_BUTTON, "=") >= 0)
for k in ["7", "×", "6", "="]: clickInApp(K_BUTTON, k)
calc.ensureLayout()
check("clicks inside it work: 7 × 6 = 42", calc.findIn(K_TEXT, "42") >= 0, $appTexts(calc))
shot("3-calc")

# back to Notes: its state survived
clickShell(K_TEXT, "Notes")
e.ensureLayout()
check("switching back shows Notes again", activeApp() == notes)
check("with its state intact (the search is still 'flutter')", notes.s.nodes[int(searchId)].sProp(P_VALUE) == "flutter")

# one click re-themes the shell and every app inside it
clickShell(K_TEXT, "Home")
e.ensureLayout()
clickShell(K_TEXT, "Paper")
e.ensureLayout()
check("the shell switched theme", e.node(0).sProp(P_THEME) == "Paper")
check("the apps inside switched too", notes.node(0).sProp(P_THEME) == "Paper" and calc.node(0).sProp(P_THEME) == "Paper")
let calcBg = calc.node(0).iProp(P_COLOR)
check("and re-styled themselves (the calculator's window is Paper's background)", (calcBg and 0xFFFFFF) == 0xF6F4EF, calcBg.toHex)
shot("4-paper-home")
clickShell(K_TEXT, "Calculator")
e.ensureLayout()
shot("5-paper-calc")

# a crashing app stops alone
clickShell(K_TEXT, "Sandbox test")
e.ensureLayout()
let sb = activeApp()
check("the sandbox test app opens", sb != nil and sb.findIn(K_BUTTON, "Crash this app") >= 0)
clickInApp(K_BUTTON, "Crash this app")
check("pressing crash stops that app", sb.crashed.len > 0, sb.crashed)
check("the shell is still running", e.crashed.len == 0)
shot("6-crashed")
clickShell(K_TEXT, "Calculator")
e.ensureLayout()
clickInApp(K_BUTTON, "C")
clickInApp(K_BUTTON, "9")
calc.ensureLayout()
check("and the other apps still work", calc.findIn(K_TEXT, "9") >= 0, $appTexts(calc))

# closing a tab stops its app
let before = e.children.len
var closeX = -1'i32
for i, n in e.s.nodes:
  if n.alive and n.kind == K_PATH and n.sProp(P_PATHDATA) == "M6 6 L18 18 M18 6 L6 18" and e.boxes.hasKey(int32(i)):
    closeX = int32(i); break
let (cx, cy) = e.centreOf(e.clickableAncestor(closeX))
click(cx, cy)
e.ensureLayout()
check("closing a tab removes its app", e.children.len == before - 1, $e.children.len)

echo "shell: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
