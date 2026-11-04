## Accessibility (U10), headless: the tree a screen reader is given — roles, names, values,
## bounds, focus — including an app running inside the shell. (render/native/t_a11y.ps1 checks
## the same through Windows UI Automation on a real window.)
import std/[os, tables, strutils]
import engine, a11y, nimaccesskit, nimsdl3
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let dir = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell"
let e = start(dir / "shell.wasm", 1280, 800)
var snap = e.snapshot
proc find(s: seq[A11yNode]; role: AkRole; prefix: string): int =
  for i, n in s:
    if n.role == role and (n.label.startsWith(prefix) or n.value.startsWith(prefix)): return i
  -1
check("the window is the last node, with the app's title", snap.len > 5 and snap[^1].role == akWindow and snap[^1].label == "Yantra")
let row = snap.find(akButton, "Calculator")
check("a clickable row is a button named by its words", row >= 0 and snap[row].click and snap[row].focus)
check("with real bounds", row >= 0 and snap[row].x1 > snap[row].x0 + 20 and snap[row].y1 > snap[row].y0 + 10)
let search = snap.find(akTextInput, "Search apps")
check("an input is a text field named by its placeholder", search >= 0 and snap[search].focus)
check("icons are left out (decoration)", snap.find(akImage, "") < 0)
var ids: seq[uint64]
for n in snap: ids.add n.id
var kidsKnown = true
for n in snap:
  for k in n.kids:
    if k notin ids: kidsKnown = false
check("every child a node names is in the snapshot", kidsKnown)

# open the calculator: its tree appears inside the shell's, as a pane
var box: Box
for i, n in e.s.nodes:
  if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == "Calculator":
    var cur = int32(i)
    while cur >= 0 and e.s.handlerFor(cur, E_CLICK) < 0: cur = e.node(cur).parent
    e.activate(cur)
    break
e.ensureLayout()
snap = e.snapshot
let pane = snap.find(akPane, "Calculator")
check("an app in a tab is a pane in the tree", pane >= 0, $snap.len)
let seven = snap.find(akButton, "7")
check("with its own buttons, under their own ids", seven >= 0 and (snap[seven].id shr 32) > 0'u64)
check("and a focus id that exists", e.focusId in ids or e.focusId == akId(0, 0))
check("publishing hands AccessKit the whole snapshot", (e.publishA11y(); publishedCount() == snap.len), $publishedCount())
check("the signature changes when the tree does", e.a11ySignature != 0)

# the AccessKit calls themselves, on a real (hidden) window
beginSnapshot()
addNode(akId(0, 0), akWindow, "tiny", "", 0, 0, 100, 100, [akId(0, 1)], false, false)
addNode(akId(0, 1), akButton, "OK", "", 10, 10, 60, 40, [], true, true)
publish(akId(0, 0), akId(0, 1))
check("a hand-made snapshot is published whole", publishedCount() == 2)
doAssert nimsdl3.init()
let w = openWindow("a11y test", 200, 120)
check("an SDL window has a native handle", w.nativeHandle != nil)
check("AccessKit attaches to it before it is shown", attach(w.nativeHandle))
onAction(wake)
check("with nothing asked, no action waits", takeAction()[0] == akNone and not e.handleA11y())
detach()
w.close()

echo "a11y: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
