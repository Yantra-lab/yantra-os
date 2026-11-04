## nimaccesskit — screen readers for Yantra through AccessKit (accesskit-c, built from
## source into third_party/accesskit-c by `cargo build --release`). The engine publishes
## snapshots of its tree; actions a screen reader asks for wait in a queue (ak_shim.c).

import std/os

const akDir = currentSourcePath().parentDir / ".." / ".." / ".." / "third_party" / "accesskit-c"
{.passC: "-I" & (akDir / "include").}
{.compile: "ak_shim.c".}
{.passL: (akDir / "target" / "release" / "accesskit.dll").}

type
  AkRole* = enum
    akContainer = 0, akWindow, akLabel, akButton, akTextInput, akMultiline, akCheckBox, akImage, akVideo,
    akDocument, akPane
  AkAction* = enum akNone = 0, akClick = 1, akFocus = 2

proc ak_begin() {.importc, cdecl.}
proc ak_node(id: uint64; role: cint; label, value: cstring; x0, y0, x1, y1: cdouble; kids: ptr uint64; nkids: cint;
             actions, toggled: cint) {.importc, cdecl.}
proc ak_publish(root, focus: uint64) {.importc, cdecl.}
proc ak_attach(hwnd: pointer): cint {.importc, cdecl.}
proc ak_detach() {.importc, cdecl.}
proc ak_take_action(node: ptr uint64): cint {.importc, cdecl.}
proc ak_published_count(): cint {.importc, cdecl.}

proc beginSnapshot*() = ak_begin()
  ## Starts a new snapshot of the tree; add every node, then `publish`.

proc addNode*(id: uint64; role: AkRole; label, value: string; x0, y0, x1, y1: float; kids: openArray[uint64];
              click, focus: bool; toggled = -1) =
  ## One node: its role, name and value, its bounds in window pixels, its children, and
  ## what a screen reader can do with it. `toggled`: -1 none, 0 off, 1 on (checkboxes).
  let k = if kids.len > 0: unsafeAddr kids[0] else: nil
  ak_node(id, cint(ord(role)), label.cstring, value.cstring, x0, y0, x1, y1, k, cint(kids.len),
          cint((if click: 1 else: 0) or (if focus: 2 else: 0)), cint(toggled))

proc publish*(root, focus: uint64) = ak_publish(root, focus)
  ## Makes the snapshot the tree screen readers see, and tells them it changed.

proc attach*(hwnd: pointer): bool = ak_attach(hwnd) == 1
  ## Connects a window (its HWND) to UI Automation.

proc detach*() = ak_detach()

proc takeAction*(): (AkAction, uint64) =
  ## The next thing a screen reader asked for (akNone when nothing is waiting).
  var n: uint64
  let a = ak_take_action(addr n)
  (AkAction(a), n)

proc publishedCount*(): int = int(ak_published_count())
  ## How many nodes the published snapshot has.

proc ak_set_wake(fn: proc () {.cdecl.}) {.importc, cdecl.}
proc onAction*(wake: proc () {.cdecl.}) = ak_set_wake(wake)
  ## `wake` runs (on the screen reader's thread) whenever an action is queued.
