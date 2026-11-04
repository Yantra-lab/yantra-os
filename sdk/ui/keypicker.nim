## The keybind picker (C122 P4) — the model a best-in-class picker needs, kept headless so
## the gate can test it. The desktop view draws exactly what these return.
##
## Accessibility here is not a "bare canvas": every control is a real widget that the engine
## already maps to an accessibility role (render/native/a11y.nim), so a screen reader gets a
## named button rather than a rectangle. `roleFor` is the single place that names a
## widget kind and the role it therefore becomes; `viewModel` builds a page out of nothing
## but those, and `t_keypicker` asserts every row has a non-blank accessible name.
##
## Keyboard-only operation: `moveFocus` wraps in both directions and `rowKey` says which
## key does what, so the page can be driven without a pointer — including to reset a
## single binding and to reset everything.

import std/strutils
import ./keybind

type
  PickerRow* = object
    ## One line of the picker: a binding, its chord, its scope, and anything wrong with it.
    b*: Binding
    index*: int                  ## index into the caller's `bindings`; NOT the row number,
                                 ## because hidden window-local rows make those differ
    chordText*: string           ## "Ctrl+Shift+K" — never a number
    scopeText*: string           ## "Global" / "This window (w1)"
    conflictWith*: seq[string]   ## ids already on this chord; empty when free
    focused*: bool               ## this row holds the keyboard
    capturing*: bool             ## this row is listening for the next chord

  Picker* = object
    rows*: seq[PickerRow]
    focus*: int                  ## index into `rows`, or -1 when the page has none
    capturing*: int              ## index being rebound, or -1
    showAllScopes*: bool         ## when false, only global rows are listed

proc roleFor*(b: Binding): string =
  ## The accessibility role this row exposes, and the widget the view must build to get it.
  ## The engine maps these in render/native/a11y.nim: a K_BUTTON becomes akButton with its
  ## label as the accessible name; a K_CHECKBOX becomes akCheckBox with a toggled state.
  ## Naming them here is what stops the view quietly falling back to drawing a bare rectangle.
  ##
  ## A window-local binding announces itself as a button inside a pane, because that is what
  ## it is: it only exists while that window has focus. A global one is a plain button.
  if b.scopeKind == skWindow: "akPane>akButton" else: "akButton"

proc enableRole*(): string =
  ## The role of the per-binding enable checkbox. A checkbox is right here (it really is
  ## on/off), unlike the chord itself, which is a button because a chord is not a boolean.
  "akCheckBox"

proc accessibleName*(r: PickerRow): string =
  ## What a screen reader announces for the row: the action, its chord, its scope, and a
  ## conflict if there is one. Never blank, and never a bare key code.
  result = r.b.id & ", " & r.chordText & ", " & r.scopeText
  if r.conflictWith.len > 0:
    result.add ", conflicts with " & r.conflictWith.join(", ")

proc rowName*(r: PickerRow): string =
  ## The visible line: the action's human label and its chord.
  r.b.id & "  " & r.chordText

proc describe*(r: PickerRow): string =
  ## The status line under a row: a conflict, or the reset hint. Empty when there is nothing
  ## to report, so the view can skip the element entirely.
  if r.conflictWith.len > 0:
    return "Already used by " & r.conflictWith.join(", ") & ". Choose another chord."
  ""

proc rebuild*(bs: seq[Binding]; focus, capturing: int; showAllScopes = true): Picker =
  ## The whole page from the bindings. Every row is built the same way, so a new binding
  ## needs no view code.
  result.focus = focus
  result.capturing = capturing
  result.showAllScopes = showAllScopes
  for i, b in bs:
    if not showAllScopes and b.scopeKind != skGlobal: continue
    result.rows.add PickerRow(b: b, index: i, chordText: formatChord(b.chord),
      scopeText: scopeLabel(b), conflictWith: conflictIds(bs, i),
      focused: (i == focus), capturing: (i == capturing))

proc visibleRows*(p: Picker): seq[int] =
  for i, r in p.rows:
    if r.focused: result.add i

proc rowAt*(p: Picker; i: int): (bool, PickerRow) =
  if i < 0 or i >= p.rows.len: return (false, PickerRow())
  (true, p.rows[i])

proc moveFocus*(p: var Picker; d: int): int =
  ## Moves the keyboard by `d` rows, wrapping at both ends, and never leaves the page. It
  ## updates the picker as well as returning the new index, so the `focused` flag on the rows
  ## always matches where the keyboard actually is. With no rows it stays at -1 rather than
  ## crashing, which is what makes "keyboard alone" safe on an empty page.
  if p.rows.len == 0: return -1
  let n = p.rows.len
  p.focus = ((p.focus + d) mod n + n) mod n
  for i in 0 ..< n: p.rows[i].focused = (i == p.focus)
  p.focus

proc focusFirst*(p: var Picker): int =
  if p.rows.len == 0: return -1
  p.moveFocus(-p.focus)

proc focusLast*(p: var Picker): int =
  if p.rows.len == 0: return -1
  p.moveFocus(p.rows.len - 1 - p.focus)

# ---- what a key press does in the picker ------------------------------------------------------------

type PickerKey* = enum
  pkDown, pkUp, pkHome, pkEnd, pkEnter, pkEscape, pkBackspace

proc rowKey*(k: PickerKey): string =
  ## The key a person presses, in words, for the hint line and the accessible description.
  case k
  of pkDown: "Down arrow"
  of pkUp: "Up arrow"
  of pkHome: "Home"
  of pkEnd: "End"
  of pkEnter: "Enter"
  of pkEscape: "Escape"
  of pkBackspace: "Backspace"

proc isRebindKey*(k: PickerKey): bool =
  k in [pkDown, pkUp, pkHome, pkEnd, pkEnter, pkEscape, pkBackspace]

proc helpLine*(): string =
  ## The picker's own keyboard help, one sentence, built from the key names themselves so the
  ## hint and the announcements can never drift apart.
  rowKey(pkUp) & " and " & rowKey(pkDown) & " move between bindings. " &
  rowKey(pkEnter) & " rebinds. " & rowKey(pkEscape) & " cancels. " &
  rowKey(pkBackspace) & " resets this binding."

# ---- capturing a chord -------------------------------------------------------------------------------

proc startCapture*(p: var Picker) =
  ## Begins listening for a chord on the focused row. `capturing` holds the ROW number, and
  ## the row carries the binding index, so hiding window-local rows cannot make the picker
  ## rebind the wrong action.
  if p.focus < 0 or p.focus >= p.rows.len: return
  p.capturing = p.focus
  for i in 0 ..< p.rows.len: p.rows[i].capturing = (i == p.focus)

proc cancelCapture*(p: var Picker) =
  ## Escape. The row keeps the chord it had; nothing is silently changed.
  p.capturing = -1
  for r in p.rows.mitems: r.capturing = false

proc finishCapture*(p: var Picker; bs: var seq[Binding]; c: Chord): (bool, seq[string]) =
  ## Applies the chord the user just pressed.
  ##
  ## On a clash it returns (false, the ids holding it) and changes nothing, so the picker can
  ## say so instead of stealing another action's key. Escape must not be storable: binding
  ## Escape would take away the key that cancels a rebind.
  if p.capturing < 0 or p.capturing >= p.rows.len: return (false, @[])
  let bi = p.rows[p.capturing].index
  if c.code == keyEscapeCode:
    p.cancelCapture()
    return (false, @[])
  let (ok, clashing) = tryBind(bs, bi, c)
  p.cancelCapture()
  (ok, clashing)

proc resetRow*(p: var Picker; bs: var seq[Binding]; i: int): bool =
  ## Resets the ROW numbered `i` to its default. Returns whether anything changed, so the view
  ## can announce "reset" only when it really was.
  if i < 0 or i >= p.rows.len: return false
  let bi = p.rows[i].index
  if bi < 0 or bi >= bs.len: return false
  let before = bs[bi].chord
  resetBinding(bs, bi)
  p.cancelCapture()
  not sameChord(before, bs[bi].chord)

proc resetEveryRow*(bs: var seq[Binding]): bool =
  ## Resets every binding in one step. Returns whether anything actually changed.
  var changed = false
  for i in 0 ..< bs.len:
    if not sameChord(bs[i].chord, bs[i].deflt): changed = true
  resetAll(bs)
  changed
