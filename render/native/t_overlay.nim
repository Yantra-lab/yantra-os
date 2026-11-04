## Overlays (OV1) through a real app — examples/shell/overlays.nim: modals, menus, popovers,
## context menus and tooltips are layers above the page, placed by their anchor, dismissed by
## Escape or a click outside, and a modal keeps the keyboard inside it.
import std/[os, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "overlays.wasm", 800, 600)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc box(name: string): Box = e.boxes.getOrDefault(idOf(name), Box())
proc shown(name: string): bool = idOf(name) in e.boxes and box(name).w > 0
proc click(name: string) =
  let b = box(name)
  e.pointerMove(b.x + b.w / 2, b.y + b.h / 2 - e.scrollY)
  e.pointerDown(b.x + b.w / 2, b.y + b.h / 2 - e.scrollY)
  e.pointerUp(b.x + b.w / 2, b.y + b.h / 2 - e.scrollY)
  e.ensureLayout()
var px = newSeq[uint32](800 * 600)
proc frame() = e.paintFrame(addr px[0], 800, 600)
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
check("closed overlays are not laid out", not shown("menu") and not shown("dialog") and not shown("pop"))
let pageH = e.contentH

# menu: opens under its button, above the page, and choosing an item closes it
click("openMenu")
frame()
check("the menu opens", shown("menu"))
let mb = box("menu")
let ob = box("openMenu")
check("under its button, left edges aligned", abs(mb.y - (ob.y + ob.h + 4)) < 0.5 and abs(mb.x - ob.x) < 0.5, $mb & " " & $ob)
check("the page's layout did not change", e.contentH == pageH)
check("a click on an item hits the item, not the page under it", e.hitTest(box("paste").x + 4, box("paste").y + 4) == idOf("paste"))
click("paste")
frame()
check("choosing an item runs it", e.node(idOf("picked")).sProp(P_TEXT) == "paste", e.node(idOf("picked")).sProp(P_TEXT))
check("and closes the menu (onDismiss)", not shown("menu"))

# click outside closes, and does not click what is under it
click("openMenu")
frame()
e.pointerDown(700, 300); e.pointerUp(700, 300); e.ensureLayout(); frame()
check("a click outside closes the menu", not shown("menu"))
click("openMenu")
frame()
e.key(27)
e.ensureLayout(); frame()
check("Escape closes the menu", not shown("menu"))

# popover near the bottom edge flips up
click("tips")
frame()
let pb = box("pop")
let tb = box("tips")
check("the popover near the bottom opens above its button", shown("pop") and pb.y + pb.h <= tb.y, $pb & " " & $tb)
check("and stays on the window", pb.y >= 8 and pb.x >= 8 and pb.x + pb.w <= 792, $pb)
e.key(27); e.ensureLayout(); frame()

# modal: centred, dims the page, takes every click, keeps Tab inside
click("openDialog")
frame()
let db = box("dialog")
check("the modal is centred", shown("dialog") and abs(db.x + db.w / 2 - 400) < 1 and abs(db.y + db.h / 2 - 300) < 1, $db)
check("its width is the app's", abs(db.w - 360) < 0.5, $db.w)
check("the page under it cannot be clicked", e.hitTest(box("openMenu").x + 4, box("openMenu").y + 4) != idOf("openMenu"))
var inside = true
for _ in 0 ..< 6:
  e.key(9)
  if e.focus < 0 or e.focus notin [idOf("reason"), idOf("cancel"), idOf("confirm")]: inside = false
check("Tab cycles inside the modal only", inside, $e.focus)
e.pointerDown(20, 580); e.pointerUp(20, 580); e.ensureLayout(); frame()
check("a click on the dimmed page dismisses the modal", not shown("dialog"))
check("and did not click anything under it", e.node(idOf("picked")).sProp(P_TEXT) == "paste")
click("openDialog"); frame()
click("confirm"); frame()
check("a button in the modal works and the app closes it", e.node(idOf("picked")).sProp(P_TEXT) == "deleted" and not shown("dialog"))

# context menu at the right click
let rb = box("row")
e.contextClick(rb.x + 30, rb.y + 10 - e.scrollY)
e.ensureLayout(); frame()
let cb = box("ctx")
check("a right click opens the row's context menu where it was", shown("ctx") and abs(cb.x - (rb.x + 30)) < 0.5 and abs(cb.y - (rb.y + 10)) < 0.5, $cb)
click("rename"); frame()
check("its item runs and it closes", e.node(idOf("picked")).sProp(P_TEXT) == "rename" and not shown("ctx"))

# tooltip after the pointer rests
let hb = box("hint")
e.pointerMove(hb.x + 4, hb.y + 4 - e.scrollY)
e.tick(e.now + 100); e.ensureLayout(); frame()
let tip = block:
  var t = -1'i32
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_TOOLTIP: t = int32(i)
  t
check("no tooltip at once", tip >= 0 and tip notin e.boxes)
e.tick(e.now + 600); e.ensureLayout(); frame()
check("the tooltip shows after a moment, beside its node (below: no room above at the top)",
      tip in e.boxes and hb.y < 34 and abs(e.boxes[tip].y - (hb.y + hb.h + 6)) < 0.5,
      (if tip in e.boxes: $e.boxes[tip] else: "not shown"))
e.pointerMove(700, 300)
e.ensureLayout(); frame()
check("and goes when the pointer leaves", tip notin e.boxes)

# a popover in a text field opens by the caret (mentions, slash menus)
e.focusOn(idOf("compose"))
e.typeText("hello @")
e.ensureLayout(); frame()
let mnb = box("mention")
let cmp = box("compose")
check("typing @ opens the mention popover under the caret, not at the field's left edge",
      shown("mention") and mnb.x > cmp.x + 40 and mnb.y >= cmp.y + 8 and mnb.y <= cmp.y + cmp.h + 4, $mnb & " " & $cmp)
check("still running", e.crashed.len == 0, e.crashed)

echo passed, " passed, ", failed, " failed"
quit(if failed == 0: 0 else: 1)
