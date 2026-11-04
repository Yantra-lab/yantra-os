## Keys (KEY1) through a real app — examples/shell/keys.nim: Key handlers run from the focused
## node outwards, the window's root sees every key, and handled() stops the built-in action.
import std/[os, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "keys.wasm", 600, 400)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc txt(name: string): string = e.node(idOf(name)).sProp(P_TEXT)
e.ensureLayout()
check("the app starts", e.crashed.len == 0, e.crashed)
const ctrl = 0x0040'i32
const shift = 0x0001'i32
e.key(int32(ord('k')), ctrl)
e.ensureLayout()
check("Ctrl+K with nothing focused reaches the root's handler", txt("search") == "true", txt("search"))
e.focusOn(idOf("item"))
e.key(0x40000051'i32)
e.key(0x40000051'i32)
e.ensureLayout()
check("arrows with the focus in the list reach the list's handler", txt("item") == "Row 2", txt("item"))
e.key(int32(ord('k')), ctrl)
check("keys the list does not take go on out to the root", txt("search") == "true")
e.focusOn(idOf("box"))
e.typeText("hello")
e.key(13, shift)
e.typeText("there")
e.ensureLayout()
check("Shift+Enter in the chat box is a new line (not taken)", e.node(idOf("box")).sProp(P_VALUE) == "hello\nthere",
      e.node(idOf("box")).sProp(P_VALUE))
e.key(13)
e.ensureLayout()
check("Enter is taken: it sends and the box is empty, with no new line added",
      txt("sent") == "hello\nthere" and e.node(idOf("box")).sProp(P_VALUE) == "", txt("sent") & "|" & e.node(idOf("box")).sProp(P_VALUE))

# scroll control (SCR1): the log sticks to its end while it was there; scrollTo jumps
let log = idOf("log")
check("a stickToEnd area starts at its end", e.scrolls.getOrDefault(log, 0) > 0 and
      abs(e.scrolls[log] - e.scrollMax[log]) < 0.5, $e.scrolls.getOrDefault(log, 0))
proc press(name: string) =
  let b = e.boxes[idOf(name)]
  e.pointerMove(b.x + 3, b.y + 3); e.pointerDown(b.x + 3, b.y + 3); e.pointerUp(b.x + 3, b.y + 3); e.ensureLayout()
let before = e.scrollMax[log]
press("more")
check("a new line arrives: still at the (new) end", e.scrollMax[log] > before and abs(e.scrolls[log] - e.scrollMax[log]) < 0.5)
let lb = e.boxes[log]
e.pointerMove(lb.x + 5, lb.y + 5)
e.wheel(1)
e.ensureLayout()
let away = e.scrolls[log]
press("more")
check("scrolled up by hand: a new line does not pull it back down", abs(e.scrolls[log] - away) < 0.5 and away < e.scrollMax[log],
      $away & " " & $e.scrolls[log])
press("top")
check("scrollTo = 0 from the app: at the top", e.scrolls[log] == 0, $e.scrolls[log])
press("more")
check("and off the end, a new line leaves it there", e.scrolls[log] == 0, $e.scrolls[log])
check("still running", e.crashed.len == 0, e.crashed)
echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
