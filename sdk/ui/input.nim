## Game input (G-IN): what is held right now, polled once per frame. `onFrame:` on the app
## runs every display frame; inside it read the time step and the input:
##
##   app("Game", pointerLock = true):
##     onFrame:
##       let dt = frameDt()
##       if keyHeld('w'): speed += 5 * dt
##       let (dx, dy) = mouseDelta()        # raw movement, also while the pointer is locked
##       yaw += dx * 0.1
##       if padConnected(): steer = padAxis(padLeftX)

from ../core/runtime import yNodeSize, gFrameDtCache

const                          # letters: keyHeld('w'); arrows, space…: keys.nim (keyLeft, keySpace)
  keyShift* = 0x400000E1'i32   ## left shift
  keyCtrl* = 0x400000E0'i32    ## left ctrl
  keyAlt* = 0x400000E2'i32     ## left alt
  padLeftX* = 0'i32
  padLeftY* = 1'i32
  padRightX* = 2'i32
  padRightY* = 3'i32
  padLeftTrigger* = 4'i32
  padRightTrigger* = 5'i32
  padA* = 0'i32                ## south face button
  padB* = 1'i32
  padX* = 2'i32
  padY* = 3'i32

when sizeof(pointer) == 4:
  proc yInput(what, arg: int32): float32 {.importc: "y_input", cdecl.}
else:
  var fakeInput*: proc (what, arg: int32): float32   ## native test builds
  proc yInput(what, arg: int32): float32 = (if fakeInput != nil: fakeInput(what, arg) else: 0'f32)

proc keyHeld*(key: int32): bool = yInput(0, key) != 0
  ## Whether `key` (a keycode: keyLeft, keySpace, keyShift…) is down now.
proc keyHeld*(c: char): bool = yInput(0, int32(c)) != 0
  ## Whether letter or digit key `c` ('w', 'a', '1') is down now.
proc mouseDelta*(): (float32, float32) = (yInput(1, 0), yInput(2, 0))
  ## How far the mouse moved since the last frame (px), raw: also while the pointer is locked.
proc mouseHeld*(button = 1): bool = (int32(yInput(3, 0)) and (1'i32 shl (button - 1))) != 0
  ## Whether mouse button 1 (left), 2 (middle) or 3 (right) is down.
proc padConnected*(): bool = yInput(6, 0) != 0
proc padAxis*(axis: int32): float32 = yInput(4, axis)
  ## A gamepad stick (-1..1) or trigger (0..1): padLeftX, padRightY, padRightTrigger…
proc padHeld*(button: int32): bool = yInput(5, button) != 0
proc frameDt*(): float32 =
  ## Seconds since the previous frame: move things by speed * frameDt().
  ## The host input is read once per handler and cached for its whole run (W1-5),
  ## so frameDt() called twice in one frame is pure-identical — and no input query
  ## is consumed mid-frame.
  if gFrameDtCache < 0'f32:
    gFrameDtCache = yInput(7, 0)
  gFrameDtCache
proc pointerIsLocked*(): bool = yInput(8, 0) != 0
proc pickPoint*(): (float32, float32, float32) = (yInput(9, 0), yInput(10, 0), yInput(11, 0))
  ## In a 3D object's onClick: where the click hit it (world metres).
proc pickInstance*(): int = int(yInput(12, 0))
  ## In an instanced mesh's onClick: which copy was clicked (its index in the placements).

proc pointerPos*(): (float32, float32) = (yNodeSize(0, 7), yNodeSize(0, 8))
  ## In onPointerDown / onPointerMove / onPointerUp on a canvas: where the pointer is, in the
  ## canvas's own pixels (painting, dragging on a canvas).
proc pointerPage*(): (float32, float32) = (yNodeSize(0, 13), yNodeSize(0, 14))
  ## Where the pointer is in the window's page.
proc clockNow*(): (int, int, int) =
  ## The local time: (hour, minute, second).
  let t = int(yInput(13, 0))
  (t div 3600, (t div 60) mod 60, t mod 60)
proc today*(): (int, int, int, int) =
  ## The local date: (year, month 1-12, day 1-31, weekday 0 Monday .. 6 Sunday).
  (int(yInput(17, 0)), int(yInput(16, 0)), int(yInput(15, 0)), int(yInput(14, 0)))
