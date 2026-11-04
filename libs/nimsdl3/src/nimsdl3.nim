## nimsdl3 — the window, input and frame presentation for the Yantra native engine
## (architecture §5). SDL3 comes from MSYS2 (`mingw-w64-x86_64-sdl3`).

{.compile: "sdl_shim.c".}
{.passL: "-lSDL3 -lshell32".}
when defined(windows): {.passL: "-ldwmapi -lole32 -luuid -lgdi32".}

type
  EventKind* = enum
    evNone = 0, evQuit, evMove, evDown, evUp, evWheel, evKey, evText, evResize, evExpose,
    evEditing,               ## an input method's word in progress: text, cursor in `button`
    evDrop,                  ## dropped file on window (C4): path in text, pointer in x,y
    evMenu,                  ## a menubar command: its id in `button` (Q8)
    evTheme,                 ## the system's light/dark theme changed (Q8)
    evLink,                  ## a deep link arrived from a second launch: `linkTaken` (Q8)
    evKeyUp                  ## a key went up (games: held keys); `button` on evKey is 1 for a repeat

  InputEvent* {.bycopy.} = object
    kind*: cint
    x*, y*: cfloat      ## pointer position in window pixels
    button*: cint
    key*: cint          ## SDL keycode
    mods*: cint
    wheel*: cfloat
    w*, h*: cint
    text*: array[512, char]
    dx*, dy*: cfloat    ## raw pointer movement in pixels (also under pointer lock)
  Window* = distinct pointer

const
  KeyBackspace* = 8'i32
  KeyTab* = 9'i32
  KeyReturn* = 13'i32
  KeyEscape* = 27'i32
  KeyDelete* = 127'i32
  KeyRight* = 0x4000004f'i32
  KeyLeft* = 0x40000050'i32
  KeyHome* = 0x4000004a'i32
  KeyEnd* = 0x4000004d'i32
  KeyKpEnter* = 0x40000058'i32
  CursorDefault* = 0
  CursorPointer* = 1
  CursorText* = 2

proc ys_init(headless: cint): cint {.importc, cdecl.}
proc ys_quit() {.importc, cdecl.}
proc ys_error(): cstring {.importc, cdecl.}
proc ys_window(title: cstring; w, h: cint): pointer {.importc, cdecl.}
proc ys_destroy(y: pointer) {.importc, cdecl.}
proc ys_pixel_size(y: pointer; w, h: ptr cint) {.importc, cdecl.}
proc ys_density(y: pointer): cfloat {.importc, cdecl.}
proc ys_set_title(y: pointer; t: cstring) {.importc, cdecl.}
proc ys_present(y: pointer; pixels: pointer; w, h, pitch: cint): cint {.importc, cdecl.}
proc ys_cursor(kind: cint) {.importc, cdecl.}
proc ys_ticks_ms(): culonglong {.importc, cdecl.}
proc ys_wait(y: pointer; e: ptr InputEvent; timeoutMs: cint): cint {.importc, cdecl.}
proc ys_push_click(x, y: cfloat; down: cint) {.importc, cdecl.}
proc ys_push_text(s: cstring) {.importc, cdecl.}
proc ys_push_drop(s: cstring; x, y: cfloat) {.importc, cdecl.}

proc init*(headless = false): bool = ys_init(cint(headless)) == 1
proc shutdown*() = ys_quit()
proc lastError*(): string = $ys_error()
proc openWindow*(title: string; w, h: int): Window = Window(ys_window(title.cstring, cint(w), cint(h)))
proc isNil*(w: Window): bool = pointer(w) == nil
proc close*(w: Window) = ys_destroy(pointer(w))
proc pixelSize*(w: Window): (int, int) =
  var a, b: cint
  ys_pixel_size(pointer(w), addr a, addr b)
  (int(a), int(b))
proc density*(w: Window): float32 = float32(ys_density(pointer(w)))
proc setTitle*(w: Window; t: string) = ys_set_title(pointer(w), t.cstring)
proc present*(w: Window; pixels: pointer; width, height, pitch: int): bool =
  ys_present(pointer(w), pixels, cint(width), cint(height), cint(pitch)) == 1
proc setCursor*(kind: int) = ys_cursor(cint(kind))
proc ticksMs*(): uint64 = uint64(ys_ticks_ms())
proc wait*(w: Window; e: var InputEvent; timeoutMs: int): bool =
  ## Waits up to `timeoutMs` for one event (-1 = forever, 0 = just poll).
  ys_wait(pointer(w), addr e, cint(timeoutMs)) == 1
proc kindOf*(e: InputEvent): EventKind = EventKind(e.kind)
proc textOf*(e: InputEvent): string = $cast[cstring](unsafeAddr e.text[0])
proc pushClick*(x, y: float32; down: bool) = ys_push_click(x, y, cint(down))
proc pushText*(s: string) = ys_push_text(s.cstring)
proc pushDrop*(path: string; x = 0.0'f32; y = 0.0'f32) = ys_push_drop(path.cstring, x, y)

proc ys_clipboard_set(s: cstring): cint {.importc, cdecl.}
proc ys_clipboard_get(): cstring {.importc, cdecl.}
proc ys_free(p: pointer) {.importc, cdecl.}

proc setClipboard*(s: string): bool = ys_clipboard_set(s.cstring) == 1
proc clipboard*(): string =
  ## The system clipboard's text ("" when empty or not text).
  let p = ys_clipboard_get()
  if p != nil:
    result = $p
    ys_free(p)

proc ys_gl_window(title: cstring; w, h, hidden: cint): pointer {.importc, cdecl.}
proc ys_gl_swap(y: pointer) {.importc, cdecl.}

proc openGlWindow*(title: string; w, h: int; hidden = false): Window =
  ## A window with an OpenGL context current, for GPU drawing; nil if there is no usable
  ## OpenGL (then fall back to `openWindow` and CPU frames).
  Window(ys_gl_window(title.cstring, cint(w), cint(h), cint(hidden)))
proc swap*(w: Window) = ys_gl_swap(pointer(w))
  ## Shows the frame drawn into a GPU window.

proc ys_native_handle(y: pointer): pointer {.importc, cdecl.}
proc ys_wake() {.importc, cdecl.}

proc nativeHandle*(w: Window): pointer = ys_native_handle(pointer(w))
  ## The OS window handle (HWND on Windows), for accessibility adapters.
proc wake*() {.cdecl.} = ys_wake()
  ## Makes a waiting loop return (callable from any thread).

proc ys_show(y: pointer) {.importc, cdecl.}
proc show*(w: Window) = ys_show(pointer(w))
  ## Windows open hidden (so accessibility can attach first); this puts one on screen.

proc ys_set_text_area(y: pointer; x, yy, w, h, cursor: cint) {.importc, cdecl.}
proc ys_push_editing(s: cstring; start: cint) {.importc, cdecl.}

proc setTextArea*(w: Window; x, y, width, height, cursor: int) =
  ## Where the text cursor is, in window points: the input method shows its candidates there.
  ys_set_text_area(pointer(w), cint(x), cint(y), cint(width), cint(height), cint(cursor))
proc pushEditing*(s: string; start: int) = ys_push_editing(s.cstring, cint(start))
  ## Test support: an input method composing `s`.

# --- OS integration (Q8) ---------------------------------------------------------------------
proc ys_set_frameless(y: pointer; f: cint) {.importc, cdecl.}

proc ys_set_regions(drag: ptr cfloat; nDrag: cint; noDrag: ptr cfloat; nNoDrag: cint) {.importc, cdecl.}
proc ys_window_op(y: pointer; op: cint) {.importc, cdecl.}
proc ys_system_theme(): cint {.importc, cdecl.}
proc ys_open_url(url: cstring): cint {.importc, cdecl.}
proc ys_accent_color(): cuint {.importc, cdecl.}
proc ys_set_menu(y: pointer; spec: cstring) {.importc, cdecl.}
proc ys_set_badge(y: pointer; count: cint) {.importc, cdecl.}
proc ys_link_listen(app: cstring): cint {.importc, cdecl.}
proc ys_link_send(app, url: cstring): cint {.importc, cdecl.}
proc ys_link_take(): cstring {.importc, cdecl.}
proc ys_register_scheme(scheme, command: cstring): cint {.importc, cdecl.}

proc setFrameless*(w: Window; on: bool) = ys_set_frameless(pointer(w), cint(ord(on)))
  ## No system title bar or border: the app draws them; edges still resize.
proc setDragRegions*(drag, noDrag: seq[array[4, float32]]) =
  ## Rects (x, y, w, h in points) the window is dragged by; `noDrag` ones inside stay clickable.
  ys_set_regions(if drag.len > 0: unsafeAddr drag[0][0] else: nil, cint(drag.len),
                 if noDrag.len > 0: unsafeAddr noDrag[0][0] else: nil, cint(noDrag.len))
proc windowOp*(w: Window; op: int) = ys_window_op(pointer(w), cint(op))
  ## 1 minimise, 2 maximise/restore, 3 close, 4 fullscreen.
proc systemTheme*(): int = int(ys_system_theme())   ## 0 unknown, 1 light, 2 dark
proc accentColor*(): uint32 = uint32(ys_accent_color()) ## ARGB, 0 unknown
proc openUrl*(url: string): bool = ys_open_url(url.cstring) == 1
proc setMenu*(w: Window; spec: string) = ys_set_menu(pointer(w), spec.cstring)
  ## "File|New:1|Open:2|-|Quit:3;Edit|Copy:4": commands come back as evMenu (Windows).
proc setBadge*(w: Window; count: int) = ys_set_badge(pointer(w), cint(count))
proc linkListen*(app: string): bool = ys_link_listen(app.cstring) == 1
proc linkSend*(app, url: string): bool = ys_link_send(app.cstring, url.cstring) == 1
  ## Hands `url` to a running instance of `app`; false if none is running.
proc linkTaken*(): string = $ys_link_take()
proc registerScheme*(scheme, command: string): bool = ys_register_scheme(scheme.cstring, command.cstring) == 1

type FileDialogCb* = proc(ud: pointer; path: cstring) {.cdecl.}

proc ys_show_open_file(win: pointer; filters: cstring; cb: FileDialogCb; ud: pointer) {.importc, cdecl.}
proc ys_show_save_file(win: pointer; defaultName, filters: cstring; cb: FileDialogCb; ud: pointer) {.importc, cdecl.}
proc ys_set_mock_open_file(path: cstring) {.importc, cdecl.}
proc ys_set_mock_save_file(path: cstring) {.importc, cdecl.}

proc showOpenFileDialog*(w: Window; filters: string; cb: FileDialogCb; ud: pointer = nil) =
  ys_show_open_file(pointer(w), filters.cstring, cb, ud)

proc showSaveFileDialog*(w: Window; defaultName, filters: string; cb: FileDialogCb; ud: pointer = nil) =
  ys_show_save_file(pointer(w), defaultName.cstring, filters.cstring, cb, ud)

proc setMockOpenFile*(path: string) =
  ys_set_mock_open_file(path.cstring)

proc setMockSaveFile*(path: string) =
  ys_set_mock_save_file(path.cstring)

proc ys_show_notification(win: pointer; title, body: cstring) {.importc, cdecl.}
proc ys_last_notify_title(): cstring {.importc, cdecl.}
proc ys_last_notify_body(): cstring {.importc, cdecl.}
proc ys_notify_count(): cint {.importc, cdecl.}

proc showNotification*(title, body: string; w: Window = Window(nil)) =
  ys_show_notification(pointer(w), title.cstring, body.cstring)

proc lastNotification*(): (string, string) = ($ys_last_notify_title(), $ys_last_notify_body())
proc notifyCount*(): int = int(ys_notify_count())


# --- games (G-IN) ---------------------------------------------------------------------------
proc ys_pointer_lock(w: Window; on: cint) {.importc, cdecl.}
proc ys_gamepad(axes: ptr cfloat; buttons: ptr cint): cint {.importc, cdecl.}
proc pointerLock*(w: Window; on: bool) = ys_pointer_lock(w, cint(ord(on)))
  ## Hides and holds the pointer (relative mode); motion events still carry dx, dy.
proc gamepad*(axes: var array[6, float32]; buttons: var int32): bool =
  ## The first connected gamepad: axes (sticks -1..1, triggers 0..1) and a button bitmask.
  var b: cint
  result = ys_gamepad(addr axes[0], addr b) == 1
  buttons = int32(b)
