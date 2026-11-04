## Test the three new shell apps (music, kanban, settings) driven through the shell.
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
var clock = 0.0

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
  clock += 1000
  e.tick(clock)
  e.pointerMove(x, y); e.pointerDown(x, y); e.pointerUp(x, y)

proc clickShell(kind: int32; label: string) =
  let id = e.clickableAncestor(e.findIn(kind, label))
  if id < 0: return
  let (x, y) = e.centreOf(id)
  click(x, y)

proc activeApp(): Engine =
  for id, c in e.children:
    if e.node(id).visible and e.boxes[id].w > 0: return c
  nil

proc clickInApp(kind: int32; label: string) =
  let app = activeApp()
  if app == nil: return
  let target = app.clickableAncestor(app.findIn(kind, label))
  if target < 0: return
  let (lx, ly) = app.centreOf(target)
  var box: Box
  for id, c in e.children:
    if c == app: box = e.boxes[id]
  click(box.x + lx, box.y + ly - e.scrollY)

# 1. Music player
clickShell(K_TEXT, "Music")
e.ensureLayout()
let music = activeApp()
check("music app opens through the shell", music != nil)
if music != nil:
  check("shows now playing track", music.findIn(K_TEXT, "Now playing: Solar Echoes") >= 0)
  clickInApp(K_BUTTON, "Play")
  music.ensureLayout()
  check("clicking play switches to Pause", music.findIn(K_BUTTON, "Pause") >= 0)
  clickInApp(K_TEXT, "Subterranean")
  music.ensureLayout()
  check("clicking playlist changes now playing", music.findIn(K_TEXT, "Now playing: Subterranean") >= 0)

# 2. Kanban board
clickShell(K_TEXT, "Home")
e.ensureLayout()
clickShell(K_TEXT, "Kanban")
e.ensureLayout()
let kanban = activeApp()
check("kanban app opens through the shell", kanban != nil)
if kanban != nil:
  check("shows initial Todo count", kanban.findIn(K_TEXT, "Todo (1)") >= 0)
  clickInApp(K_BUTTON, "Advance")
  kanban.ensureLayout()
  check("advancing card updates column counts", kanban.findIn(K_TEXT, "In Progress (2)") >= 0)

# 3. Settings page
clickShell(K_TEXT, "Home")
e.ensureLayout()
clickShell(K_TEXT, "Settings")
e.ensureLayout()
let settings = activeApp()
check("settings app opens through the shell", settings != nil)
if settings != nil:
  check("shows initial sound switch state", settings.findIn(K_TEXT, "Sound: OFF") >= 0)
  clickInApp(K_TEXT, "Sound: OFF")
  settings.ensureLayout()
  check("toggling switch updates sound state", settings.findIn(K_TEXT, "Sound: ON") >= 0)
  check("shows initial volume", settings.findIn(K_TEXT, "Volume: 60%") >= 0)
  clickInApp(K_BUTTON, "+20%")
  settings.ensureLayout()
  check("stepping volume updates slider text", settings.findIn(K_TEXT, "Volume: 80%") >= 0)

echo "shell apps: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
