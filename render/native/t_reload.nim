## Hot reload (roadmap U3/U4): a new build is swapped into a running app and nothing the
## user was doing is lost. Variant builds come from run_tests.sh (build/reload/…): the
## same file with a small edit, like a developer saving it.
import std/[os, tables, strutils, times]
import engine, devwatch
from nimwasmtime import cacheKey
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let shellDir = here / ".." / ".." / "examples" / "shell"
let variants = here / "build" / "reload"
var px = newSeq[uint32](1280 * 800)
var clock = 0.0

proc findIn(e: Engine; kind: int32; label: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == kind and n.sProp(P_TEXT) == label: return int32(i)
  -1
proc clickNode(e: Engine; id: int32) =
  clock += 1000
  e.tick(clock)
  e.ensureLayout()
  var cur = id
  while cur >= 0 and e.s.handlerFor(cur, E_CLICK) < 0 and e.node(cur).kind notin [K_BUTTON, K_INPUT, K_TEXTAREA]:
    cur = e.node(cur).parent
  let b = e.boxes[cur]
  let (x, y) = (b.x + b.w / 2, b.y + b.h / 2 - e.scrollY)
  e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y)
proc paintOnce(e: Engine) =
  clock += 1000
  e.tick(clock)
  e.paintFrame(addr px[0], int(e.width), int(e.height))

# 1. the counter: state kept, new code running
let c = start(shellDir / "counter.wasm", 360, 300)
for _ in 0 ..< 3: c.clickNode(c.findIn(K_BUTTON, "Click me"))
c.ensureLayout()
check("the counter counts to 3", c.findIn(K_TEXT, "3") >= 0)
check("its first build says 'clicks'", c.findIn(K_TEXT, "clicks") >= 0)
check("a new build swaps in", c.reload(variants / "v2" / "counter.wasm") and c.reloads == 1, c.devNote)
c.ensureLayout()
check("the new code runs (it now says 'taps')", c.findIn(K_TEXT, "taps") >= 0 and c.findIn(K_TEXT, "clicks") < 0)
check("and the count is still 3", c.findIn(K_TEXT, "3") >= 0)
c.clickNode(c.findIn(K_BUTTON, "Click me"))
c.ensureLayout()
check("and it keeps counting from there", c.findIn(K_TEXT, "4") >= 0)
c.paintOnce()

# 2. a build that cannot start: the old one keeps running and says why
writeFile(variants / "broken.wasm", "this is not a wasm module")
check("a broken build is refused", not c.reload(variants / "broken.wasm"))
check("the app keeps running as it was", c.findIn(K_TEXT, "4") >= 0 and c.devNote.len > 0, c.devNote)
c.paintOnce()
check("and it can still be clicked", (c.clickNode(c.findIn(K_BUTTON, "Click me")); c.ensureLayout();
      c.findIn(K_TEXT, "5") >= 0))
check("the next good build clears the message", c.reload(variants / "v2" / "counter.wasm") and c.devNote == "" and
      (c.ensureLayout(); c.findIn(K_TEXT, "5") >= 0))

# 3. the shell: reload it while an app runs in a tab — the tab and its state survive
let s = start(shellDir / "shell.wasm", 1280, 800)
s.clickNode(s.findIn(K_TEXT, "Calculator"))
s.ensureLayout()
var calc: Engine
for _, ch in s.children: calc = ch
for k in ["7", "×", "6", "="]:
  let id = calc.findIn(K_BUTTON, k)
  var box: Box
  for aid, ch in s.children:
    if ch == calc: box = s.boxes[aid]
  calc.ensureLayout()
  let b = calc.boxes[id]
  let (x, y) = (box.x + b.x + b.w / 2, box.y + b.y + b.h / 2 - s.scrollY)
  s.pointerMove(x, y); s.pointerDown(x, y); s.pointerUp(x, y)
calc.ensureLayout()
check("the calculator in the shell shows 42", calc.findIn(K_TEXT, "42") >= 0)
check("the shell reloads with new code", s.reload(variants / "shell2" / "shell.wasm"), s.devNote)
var calcAfter: Engine
for _, ch in s.children: calcAfter = ch
check("the calculator tab is still open, the same running app", s.children.len == 1 and calcAfter == calc)
check("with its 42", calcAfter != nil and calcAfter.findIn(K_TEXT, "42") >= 0)
s.clickNode(s.findIn(K_TEXT, "Home"))
s.ensureLayout()
check("the shell shows its new text", s.findIn(K_TEXT, "Hello again.") >= 0)
check("a running app's state can be saved", calc.app.saveState().len > 0)
let swapped = s.reloadEverywhere(shellDir / "calc.wasm")
check("reloading the calculator's build swaps it inside the shell (and nothing else)", swapped == 1 and s.findIn(K_TEXT, "Hello again.") >= 0)
s.paintOnce()

# 4. an app reloaded mid-edit keeps focus, caret and the typed text
let nt = start(shellDir / "notes.wasm", 900, 640)
var title = -1'i32
for i, n in nt.s.nodes:
  if n.alive and n.kind == K_INPUT and n.sProp(P_VALUE) == "Pitch outline": title = int32(i)
nt.clickNode(title)
nt.key(int32(ord('a')), 0x40)
nt.typeText("Deck notes")
nt.key(0x40000050'i32)     # Left: caret one back
let caretBefore = nt.caret
check("a reload in the middle of typing", nt.reload(shellDir / "notes.wasm"), nt.devNote)
nt.ensureLayout()
check("keeps what was typed", nt.focus >= 0 and nt.node(nt.focus).sProp(P_VALUE) == "Deck notes",
      if nt.focus >= 0: nt.node(nt.focus).sProp(P_VALUE) else: "no focus")
check("keeps the focus on that field", nt.focus >= 0 and nt.node(nt.focus).kind == K_INPUT)
check("and the caret where it was", nt.caret == caretBefore, $nt.caret & " vs " & $caretBefore)
nt.typeText("!")
check("so typing carries on in place", nt.node(nt.focus).sProp(P_VALUE) == "Deck note!s")

# 5. the watcher: save a file, and the running app becomes the new build
let wdir = variants / "watch"
let wsrc = wdir / "counter.nim"
let w = newWatcher(wdir)
let we = start(wdir / "counter.wasm", 360, 300)
we.clickNode(we.findIn(K_BUTTON, "Click me"))
writeFile(wsrc, readFile(wsrc).replace("\"clicks\"", "\"presses\""))
setLastModificationTime(wsrc, getTime() + initDuration(seconds = 2))
var waited = 0
while waited < 240 and we.reloads == 0 and w.failed == 0:
  discard w.poll(we)
  sleep(500); inc waited
we.ensureLayout()
check("saving the file rebuilds and reloads the running app", we.reloads == 1 and w.built == 1,
      "built " & $w.built & " failed " & $w.failed & " " & we.devNote)
check("which now shows the edit, and kept its count", we.findIn(K_TEXT, "presses") >= 0 and
      we.findIn(K_TEXT, "1") >= 0)
writeFile(wsrc, readFile(wsrc).replace("text \"presses\"", "text presses oops"))
setLastModificationTime(wsrc, getTime() + initDuration(seconds = 4))
waited = 0
while waited < 240 and w.failed == 0:
  discard w.poll(we)
  sleep(500); inc waited
check("a save that does not compile shows the compiler error", w.failed == 1 and "Error" in we.devNote, we.devNote)
check("and the app keeps running its last good build", we.findIn(K_TEXT, "presses") >= 0)
check("the watcher is idle again", not w.busy)

# compiled apps are cached: each version is compiled once, then starts in milliseconds
let cacheDir = getTempDir() / "yantra_module_cache_test"
removeDir(cacheDir)
putEnv("YANTRA_CACHE", cacheDir)
check("the cache goes where YANTRA_CACHE says", moduleCacheDir() == cacheDir)
let counterWasm = shellDir / "counter.wasm"
discard start(counterWasm, 360, 300)
let key = cacheKey(readFile(counterWasm).toOpenArrayByte(0, readFile(counterWasm).len - 1))
check("starting an app stores its compiled form", fileExists(cacheDir / key & ".cwasm"))
let again = start(counterWasm, 360, 300)
again.ensureLayout()
check("and the next start runs from it", again.findIn(K_BUTTON, "Click me") >= 0)
putEnv("YANTRA_NO_CACHE", "1")
check("YANTRA_NO_CACHE turns it off", moduleCacheDir() == "")
delEnv("YANTRA_NO_CACHE")
delEnv("YANTRA_CACHE")
removeDir(cacheDir)

echo "reload: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
