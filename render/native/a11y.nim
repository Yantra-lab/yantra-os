## Accessibility (roadmap U10): the engine's tree as screen readers see it — every app,
## including the ones running inside the shell's tabs. `snapshot` is pure (tested
## headless); `publishA11y` hands it to AccessKit (Windows UI Automation today) and
## `handleA11y` carries out the clicks and focus moves a screen reader asks for.

import std/tables
import engine, nimaccesskit
import ../../host/host, ../../host/tree
import ../../protocol/wire

type A11yNode* = object
  id*: uint64
  role*: AkRole
  label*, value*: string
  x0*, y0*, x1*, y1*: float
  kids*: seq[uint64]
  click*, focus*: bool
  toggled*: int                          ## -1 none, 0 off, 1 on

proc akId*(slot, id: int32): uint64 = (uint64(slot) shl 32) or uint64(id + 1)
  ## Slot 0 is the window's own app; an app inside an appView uses that node's id + 1.

proc textOf(e: Engine; id: int32): string =
  ## The words inside a clickable row: what it says, for its name.
  let n = e.node(id)
  if not n.alive or not n.visible: return
  if n.kind in [K_TEXT, K_BUTTON] and n.sProp(P_TEXT).len > 0: return n.sProp(P_TEXT)
  for c in n.children:
    let t = e.textOf(c)
    if t.len > 0:
      if result.len > 0: result.add " "
      result.add t

proc walk(e: Engine; slot: int32; id: int32; ox, oy, sc: float; outp: var seq[A11yNode]): seq[uint64] =
  let n = e.node(id)
  if not n.alive or not n.visible: return
  if n.kind == K_GROUP:                   # layout-only: its children stand in for it
    for c in n.children: result.add e.walk(slot, c, ox, oy, sc, outp)
    return
  if id notin e.boxes: return
  let clickable = e.s.handlerFor(id, E_CLICK) >= 0
  if n.kind == K_PATH and not clickable: return        # icons are decoration
  let b = e.boxes[id]
  var node = A11yNode(id: akId(slot, id), toggled: -1,
                      x0: ox + float(b.x) * sc, y0: oy + float(b.y - e.scrollY) * sc,
                      x1: ox + float(b.x + b.w) * sc, y1: oy + float(b.y - e.scrollY + b.h) * sc)
  let name = n.sProp(P_NAME)
  case n.kind
  of K_WINDOW: node.role = (if slot == 0: akWindow else: akPane); node.label = n.sProp(P_TEXT)
  of K_TEXT: node.role = akLabel; node.value = n.sProp(P_TEXT)   # AccessKit names static text by its value
  of K_BUTTON: node.role = akButton; node.label = n.sProp(P_TEXT)
  of K_INPUT, K_TEXTAREA:
    node.role = (if n.kind == K_INPUT: akTextInput else: akMultiline)
    node.label = (if n.sProp(P_PLACEHOLDER).len > 0: n.sProp(P_PLACEHOLDER) else: name)
    node.value = n.sProp(P_VALUE)
  of K_CHECKBOX:
    node.role = akCheckBox
    node.label = n.sProp(P_TEXT)
    node.toggled = (if n.iProp(P_CHECKED) != 0: 1 else: 0)
  of K_IMAGE: node.role = akImage; node.label = (if name.len > 0: name else: n.sProp(P_SOURCE))
  of K_VIDEO: node.role = akVideo; node.label = (if name.len > 0: name else: n.sProp(P_SOURCE))
  of K_PAGE: node.role = akDocument; node.label = name
  else:
    node.role = (if clickable: akButton else: akContainer)
    node.label = (if clickable: e.textOf(id) else: name)
  node.click = clickable or n.kind in [K_BUTTON, K_CHECKBOX]
  node.focus = node.click or n.kind in [K_INPUT, K_TEXTAREA]
  if n.kind == K_APPVIEW and id in e.children:           # an app inside: its whole tree, as a pane
    let c = e.children[id]
    if c.crashed.len == 0 and c.s != nil:
      c.ensureLayout()
      node.role = akPane
      node.kids.add c.walk(id + 1, 0, node.x0, node.y0, sc, outp)
  elif n.kind != K_BUTTON and n.kind != K_CHECKBOX:
    for c in n.children: node.kids.add e.walk(slot, c, ox, oy, sc, outp)
  outp.add node
  @[node.id]

proc snapshot*(e: Engine): seq[A11yNode] =
  ## Every node a screen reader should know about, with window-pixel bounds; the window is last.
  if e.crashed.len > 0 or e.s == nil: return
  e.ensureLayout()
  discard e.walk(0, 0, 0, 0, float(e.scale), result)

proc focusId*(e: Engine): uint64 =
  ## The node that has the keyboard, in snapshot ids (the window when none does).
  if e.activeChild in e.children:
    let c = e.children[e.activeChild]
    if c.focus >= 0: return akId(e.activeChild + 1, c.focus)
  if e.focus >= 0: akId(0, e.focus) else: akId(0, 0)

proc publishA11y*(e: Engine) =
  ## Hands the current tree to screen readers (cheap when none is listening).
  let nodes = e.snapshot
  if nodes.len == 0: return
  beginSnapshot()
  for n in nodes:
    addNode(n.id, n.role, n.label, n.value, n.x0, n.y0, n.x1, n.y1, n.kids, n.click, n.focus, n.toggled)
  publish(akId(0, 0), e.focusId)

proc handleA11y*(e: Engine): bool =
  ## Carries out what screen readers asked for since the last call; true if anything ran.
  while true:
    let (action, node) = takeAction()
    if action == akNone: break
    result = true
    let slot = int32(node shr 32)
    let id = int32(node and 0xFFFFFFFF'u64) - 1
    var target = e
    if slot > 0:
      if (slot - 1) notin e.children: continue
      target = e.children[slot - 1]
    if not target.s.valid(id): continue
    case action
    of akClick: target.activate(id)
    of akFocus:
      if slot > 0: e.activeChild = slot - 1
      target.focusOn(id)
      target.focusVisible = true
    of akNone: discard
    e.dirty = true

proc a11ySignature*(e: Engine): int =
  ## Changes when what a screen reader sees may have: the tree (here and in apps inside),
  ## focus, scrolling or size.
  if e.s == nil: return 0
  result = e.s.version * 31 + e.focus * 7 + int(e.scrollY) * 3 + int(e.width) + int(e.height) * 5
  for id, c in e.children:
    if c.s != nil: result = result * 17 + c.s.version + c.focus + id
