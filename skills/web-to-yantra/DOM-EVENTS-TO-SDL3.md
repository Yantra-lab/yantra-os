# DOM events → SDL3 events

`keydown`, `click`, `pointerdown`, `requestAnimationFrame`, `setTimeout`,
`localStorage`, `element.animate`, `visibilitychange`, pointer capture, and — the hard
one — **hit-testing a canvas you drew yourself**.

**Sources:** `sdk/ui/keys.nim` (48 lines, read in full), `sdk/ui/input.nim` (65 lines),
`sdk/core/runtime.nim:132-193` (`set`, `addHandler`, `onClick`), `sdk/core/wire.nim:322-356`
(the `Event` enum), `sdk/core/persist.nim:34` (`persistent`), `sdk/ui/motion.nim:74-99`
(`afterMs`, `after`, `timeline`), `sdk/yantra.nim:437-467` (`animate`, `transition`),
`host/host.nim:589-623` + `render/native/engine.nim:3016-3023` (`pointerPos`),
`sdk/ui/sheet.nim:140-175` (a real drag implementation), `apps/typewriter/app.nim`
(a working port of a keyboard-driven page).

## 0. The whole map

The wire has 34 events (`wire.nim:322-356`). The ones a port needs:

| DOM | Yantra | Event id | Read the event with |
|---|---|---|---|
| `keydown` | `evKey` | 15 | `lastKey()` → `KeyPress`, then `handled()` |
| `click` | `evClick` | 0 | `pointerPos()` (canvas-local px) |
| `pointerdown` / `mousemove` / `pointerup` | `evPointerDown` / `evPointerMove` / `evPointerUp` | 20 / 21 / 22 | `pointerPos()` |
| `requestAnimationFrame` | `evFrame` | 33 | `frameDt()` → **seconds** |
| `setTimeout` / `setInterval` | — | — | `afterMs(ms, body)` / a frame counter |
| `<input>` `input` / `change` | `evInput` / `evChange` | 3 / 1 | the bound `Signal` |
| `scroll` | `evScroll` | 6 | `yNodeSize(id, 2)` (y) and `, 9` (x) |
| `resize` (element) | `evResize` | 12 | `yNodeSize(id, 0/1)` |
| `dragstart` / `dragover` / `drop` | `evDragStart` / `evDragOver` / `evDrop` | 30 / 31 / 32 | `droppedFile()` |
| `focus` / `blur` | `evFocus` / `evBlur` | 4 / 5 | |
| `element.animate()` | — | — | `node.animate(…)` for nodes; a `var` + `evFrame` for canvas |
| `visibilitychange` | **none** | — | see §8 |
| `setPointerCapture` | **none** | — | see §9 |
| `window.resize` | **none** | — | see §10 |

Two structural differences to internalise before reading on:

- **A handler is a bare `proc()` with no arguments.** Everything the event carries is
  read from a *global-ish* getter: `lastKey()`, `pointerPos()`. There is no event
  object, no `event.target`, no `stopPropagation`.
- **Handlers are per (node, event) and run innermost-first**, and `handled()` stops the
  key going further — no outer handler and no built-in action
  (`keys.nim:1-4`). That is the whole propagation model.

```nim
proc addHandler*(node: Node; event: Event; handler: proc()) =     # runtime.nim:174-185
  ## Any number of handlers per node and event, run in the order they were added
  ## (an `input` bound to a signal can also have its own `onInput:`). The engine
  ## sees one handler per (node, event): a dispatcher over this list.
```

---

## 1. `keydown` → `evKey` + `lastKey()`

```nim
type KeyPress* = object
  code*: int32     ## SDL key code: a letter or digit is its lower-case ASCII code
  mods*: int32     ## modifier bits

proc lastKey*(): KeyPress = KeyPress(code: yKey(0), mods: yKey(1))   # keys.nim:41
proc handled*() = yKeyHandled()                                     # keys.nim:42
proc shift*(k: KeyPress): bool = (k.mods and 0x0003) != 0           # keys.nim:43
proc ctrl*(k: KeyPress): bool = (k.mods and 0x0CC0) != 0            # keys.nim:44 — Ctrl, or Cmd on a Mac
proc alt*(k: KeyPress): bool = (k.mods and 0x0300) != 0             # keys.nim:45
proc `==`*(k: KeyPress; code: int32): bool = k.code == code         # keys.nim:46
proc `==`*(k: KeyPress; c: char): bool =                           # keys.nim:47-48
  k.code == int32(ord(if c in {'A'..'Z'}: char(ord(c) + 32) else: c))
```

The named non-ASCII keys are consts (`keys.nim:18-39`): `keyBackspace = 8`,
`keyTab = 9`, `keyEnter = 13`, `keyEscape = 27`, `keySpace = 32`, `keyDelete = 127`,
`keyLeft/Right/Up/Down`, `keyHome`, `keyEnd`, `keyPageUp/Down`, `keyPeriod`,
`keyComma`, plus `keyShift`/`keyCtrl`/`keyAlt` in `input.nim:13-15` for `keyHeld`.

**`k == 'a'` folds case** (`keys.nim:47-48`), so one comparison covers `A` and `a` — but
only for letters. Digits and punctuation have no such fold: `k == 'A'` and `k == 'a'`
are the same test, `k == '1'` is only `'1'`.

The port's whole keyboard handler, which is also a good model for the shape of the
answer (`app.nim:1019-1028`):

```nim
page.addHandler(evKey, proc() =
  let k = lastKey()
  if k.ctrl or k.alt: return                     # leave shortcuts to the host
  if k == keyEnter: carriageReturn(); handled(); return
  if k == keyBackspace: backspace(); handled(); return
  if k == keyTab: doTab(); handled(); return
  if k == keySpace: doSpace(); handled(); return
  if k.code >= 32 and k.code < 127:
    typeChar(char(k.code))
    handled())
```

Four decisions in that snippet, all worth copying:

1. **Register on `page` (the window root), not on a control.** `keys.nim:1-3`: the root's
   handler runs for every key. Registering on a button means the key only arrives when
   that button has focus — the single most common port mistake.
2. **`if k.ctrl or k.alt: return` before anything else**, so Ctrl-C is never eaten.
   Without it, a text field's copy shortcut dies.
3. **The printable range is `32 ..< 127`.** Everything else is a named const. Note this
   delivers *unshifted* ASCII: `k.code` is the lower-case letter's code, so `A` arrives
   as 65 and shift state is only in `k.shift(k)`. The port derives the uppercase form
   itself (`app.nim:900: if ch in {'a'..'z'} and up: ch = char(ord(ch) - 32)`).
4. **`handled()` on every branch that consumed the key.** It is what stops the engine's
   own behaviour (a focused field's text entry, a button's Enter) from also firing.

`shift` on `KeyPress` is a proc, so it reads `k.shift` — and it is both shift keys
(`0x0003`). There is **no `keypress` vs `keydown` distinction**: a key press that
auto-repeats arrives repeatedly, so a handler that advances state must be idempotent or
rate-limited itself.

For a *game* loop you want the other input API entirely — polling, not events
(`input.nim:33-36`): `keyHeld('w')`, `keyHeld(keyLeft)`, `mouseHeld(1)`,
`mouseDelta()`, `frameDt()`.

---

## 2. `click` / `pointerdown` → `evClick` + `pointerPos()`

`pointerPos()` returns **the pointer in the canvas's own pixels**, not window
coordinates (`input.nim:54-56`; computed in the engine at `engine.nim:3016-3023` as
`(x - b.x, y + scrollY - b.y)`):

```nim
proc pointerPos*(): (float32, float32) = (yNodeSize(0, 7), yNodeSize(0, 8))
  ## In onPointerDown / onPointerMove / onPointerUp on a canvas: where the pointer is, in the
  ## canvas's own pixels (painting, dragging on a canvas).
```

`pointerPage()` (`input.nim:57-58`, axes 13/14) is the same point in window space, when
you need it.

The typewriter's handler is the whole pattern (`app.nim:1014-1017`):

```nim
scene.onClick(proc() =
  let (px, py) = pointerPos()
  let k = hitKey(px, py)
  if k.len > 0: onScreenKey(k))
```

Note: **no coordinates are passed to the handler**; you read them, and you read them
once, at the top.

---

## 3. Hit-testing your own drawn keys — the real problem

A `button` node hit-tests itself. A canvas does not, so *you* write the geometry test,
and you must write it with the **same numbers the drawing used**. The single most
important rule: **the hit-test and the draw must call the same layout function.**

The drawing used these (`app.nim:513-519`):

```nim
const ROWS = [
  (y: 150.0'f32, r: 16.5'f32, sp: 58.0'f32, dx: 10.0'f32, n: 12),
  (y: 190.0'f32, r: 17.5'f32, sp: 61.0'f32, dx:  6.0'f32, n: 11),
  (y: 230.0'f32, r: 18.5'f32, sp: 64.0'f32, dx:  3.0'f32, n: 11),
  (y: 270.0'f32, r: 19.5'f32, sp: 67.0'f32, dx:  0.0'f32, n: 12)
]
const ROWKEYS = ["1234567890-BS", "TABqwertyuiop", "LOCKasdfghjkl;", "SHIFTzxcvbnm,./SHIFT"]
```

`drawKeys()` computes each key's position from `ROWS`/`ROWKEYS` (`app.nim:524-537`):

```nim
for ri in 0 .. 3:
  let row = ROWS[ri]
  let keys = ROWKEYS[ri]
  let n = row.n
  let x0 = 500.0'f32 + row.dx - (n - 1).float32 * row.sp / 2.0'f32
  for i in 0 ..< n:
    let k = $keys[i]
    let x = cx(x0 + i.float32 * row.sp)
    let y = by(row.y)
```

and `hitKey()` recomputes **the identical expression**, then inflates the test box by a
few pixels so small targets stay tappable (`app.nim:857-880`):

```nim
proc hitKey(px, py: float32): string =
  ## Which illustrated key did the pointer land on? Canvas space: subtract HEAD.
  let cyv = py + HEAD
  if cyv < by(140.0): return ""
  # space bar
  if px > cx(292) and px < cx(708) and cyv > by(284) and cyv < by(310):
    return " "
  for ri in 0 .. 3:
    let row = ROWS[ri]
    let keys = ROWKEYS[ri]
    let n = row.n
    let x0 = 500.0'f32 + row.dx - (n - 1).float32 * row.sp / 2.0'f32
    for i in 0 ..< n:
      let kx = cx(x0 + i.float32 * row.sp)
      let ky = by(row.y)
      if px > kx - row.r * U - 4 and px < kx + row.r * U + 4 and
         cyv > ky - row.r * 0.8'f32 * U and cyv < ky + row.r * 0.8'f32 * U + 6:
        return $keys[i]
  # the carriage-return lever, which rides with the carriage
  let mid = SW / 2.0'f32 - (PW / 2.0'f32) * S
  let lx = cx(900.0) + (carX - mid)
  if px > lx and px < lx + 100.0'f32 * U and cyv > cy(-8.0) and cyv < cy(54.0):
    return "@RETURN"
  ""
```

Every line of that is a decision:

- **`let cyv = py + HEAD`** converts canvas-local back to the scene coordinates the art
  was authored in (`app.nim:858`). The canvas node sits below a 64 px header
  (`app.nim:952, 1010`), so window-space y = canvas y + header height. Get this wrong
  and every hit test is offset by exactly the header height — the classic symptom is
  "clicking the bottom row types into the top row".
- **The `cx()`/`by()` helpers, not raw numbers.** The drawing goes through
  `proc cx(x: float32): float32 = MX + x * U` and `proc by(y: float32): float32 = MY + 100.0'f32 * U + y * U`
  (`app.nim:377-379`), so the hit-test goes through the same two procs. If the window
  size or the scale ever changes, one edit fixes both.
- **The test box is inflated**: `-4 … +4` in x and `+6` at the bottom. The drawn cap is
  an ellipse (`ry = r * 0.8`), but a rectangular test box is right for a keyboard — and
  a few pixels of slack is the difference between a key you can hit and one you cannot.
- **Return a *label*, not an index**, and dispatch on it afterwards (`onScreenKey`,
  `app.nim:882-902`). Keys that are words (`"BS"`, `"TAB"`, `"SHIFT"`, `"LOCK"`) and
  keys that are characters then share one hit-test.
- **Moving targets are hit-tested at their current position.** The carriage-return lever
  rides the carriage: `lx = cx(900.0) + (carX - mid)` (`app.nim:877`) uses the live
  `carX`, not a stored rect. Same for the bell marker, which the port keeps behind a
  forward-declared helper for exactly this reason
  (`proc midBell(): float32` at `app.nim:572`, defined at `:591`, used by both the draw
  and the hit paths).

**Alternative worth knowing:** if the drawn thing is a grid of items, reuse the SDK's
own grid hit-test. `sdk/ui/sheet.nim:160` does `let (r, c) = s.hit(x, y)` after
`let x = yNodeSize(id, 7)` / `let y = yNodeSize(id, 8)` — the same read, the same
"return −1 / a sentinel when nothing was hit" contract.

**When to skip all of this:** if the widget is a discrete control, make it a **node**
laid over the canvas. The typewriter does exactly that for its header (`app.nim:951-987`)
and gets focus, hover, pressed states and hit-testing for free. Drawing a button *and*
hand-writing its hit-test is only worth it when the button is part of an illustration.

---

## 4. `requestAnimationFrame(loop)` → `evFrame` + `frameDt()`

```nim
proc frameDt*(): float32 = yInput(7, 0)
  ## Seconds since the previous frame: move things by speed * frameDt().    # input.nim:45-46
```

**`frameDt()` is in seconds.** The page's `t` in milliseconds becomes
`nowMs += frameDt() * 1000.0'f32` (`app.nim:906`). This is the single most common unit
bug in a port: a 60 ms spring multiplied straight by `frameDt()` moves 60× too little.

```nim
scene.addHandler(evFrame, proc() = tick())     # app.nim:1030
```

Register the frame handler on the canvas you are repainting — or on the window, if
several things animate. The port's whole animation loop (`app.nim:905-922`):

```nim
proc tick() =
  nowMs += frameDt() * 1000.0'f32
  # escapement snap on a keystroke, slower overshooting glide on return
  let k = min(1.0'f32, frameDt() * 9.0)
  carX = carX + (carTarget - carX) * k
  paperY = paperY + (paperTarget - paperY) * min(1.0'f32, frameDt() * 11.0)
  strikeFlash = max(0.0'f32, strikeFlash - frameDt() * 4.0)
  bellFlash = max(0.0'f32, bellFlash - frameDt() * 1.4)
  if dingT >= 0:
    dingT += frameDt() * 1000.0'f32
    if dingT > 1400.0: dingT = -1.0
  if toastMsg.len > 0:
    toastT += frameDt()
    if toastT > 2.6:
      toastMsg = ""
  if litKey.len > 0:
    litKeyTimer += frameDt()
    if litKeyTimer > 0.11: litKey = ""
```

What that shows:

- **Frame-rate-independent easing** is `v += (target - v) * min(1, dt * rate)`. The `k`
  factor is computed from `frameDt()` so the same animation runs at 30 fps and 144 fps.
  This is the `ease`-by-hand version of what `node.animate` does for nodes (§7).
- **Every transient is a countdown in seconds**: `strikeFlash - dt * 4.0` is a 250 ms
  flash; `toastT > 2.6` is a 2.6 s toast; `litKeyTimer > 0.11` is the source's 110 ms
  key flash. Negative sentinel = "hidden" (`dingT = -1.0`, `app.nim:106`).
- **The frame handler does not repaint for you.** `tick()` mutates state; the repaint
  happens in whatever triggered it, or you add `repaint()` at the end of `tick()` if the
  animation is the only thing moving.

A caveat, now resolved from source: **`frameDt()` does NOT return 0 on the first
frame.** `render/native/engine.nim:3241` computes it as

```nim
e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60
```

so the first frame is a synthetic **1/60 s**, and every later frame is the real
elapsed wall-clock delta. Dividing by `frameDt()` on frame one is therefore safe
by accident — but do not design around it; clamp instead (see §8).

> **CORRECTED 2026-10-03.** This section used to say *"a hidden or unfocused
> window stops producing frames, so `frameDt()` goes to 0 (or very large)"* and
> carried an unresolved verification marker because the two branches were never
> separated. They are now separated from source: `render/native/engine.nim:3241`
> shows the first frame is `1'f32/60` and every later frame is a **measured
> elapsed delta**, so a stall produces **one large value on return, not 0**. The
> marker is resolved and removed.

---

## 5. `setTimeout` / `setInterval`

**For a one-shot delay there is a real API** (`sdk/ui/motion.nim:74-81`):

```nim
proc afterMs*(ms: float32; body: proc()) =
  ## Runs `body` once, `ms` from now on the engine's clock (a real clock in a window,
  ## exact frame times when a film is rendered). Batched like an event handler.
  yAfter(int32(max(ms, 0) + 0.5), onHandler(proc() = batch(body)))

template after*(delay: untyped; body: untyped) =
  ## `after 1.2.s: step.set(2)` — a scene moves on by itself; a film is steps in time.
  afterMs(durationOf(delay), proc() = body)
```

and `timeline:` for a scripted sequence (`motion.nim:83-99`) using `at <time>:` /
`then <duration>:` steps.

**But inside a canvas, prefer a frame counter.** The port's toast and key flash are both
`setTimeout`s in the page and both are counters in `tick()` (§4). Why: `afterMs` runs on
the *engine's* clock and is batched like an event, while canvas animation is driven by
your `evFrame` handler; mixing the two gives you two clocks and a class of bugs where
something animates while everything else is paused. One counter, one clock.

The same reason applies to `setInterval`: it becomes "a countdown in the frame loop".

---

## 6. `localStorage` → `persistent[T]`

```nim
proc persistent*[T](initial: T; key: string): Signal[T] =      # persist.nim:34-49
  ## A signal holding `initial` the first time, and whatever it last held ever after.
  ## Every change is saved at once. A saved value that no longer fits the type (the app
  ## changed) is ignored.
```

It returns a `Signal[T]`, so it is a `state` that also persists: `.get()` to read,
`.set(v)` to write (saving on every change), `+=` / `-=` are overloaded for signals
(`sdk/core/signals.nim:239-243`). Storage lives in the host, in the app's own folder,
1 MB a value / 16 MB an app (`persist.nim:1-3`). **There is no filesystem access**, so
this is the only persistence there is.

Three typed keys in the port (`app.nim:693-694`):

```nim
var saved      = persistent("",  "marlowe44.letter.v1")
var savedMuted = persistent(0'i32, "marlowe44.muted")
```

- **Strings** for structured data, serialised by hand (`app.nim:709-714`):

```nim
proc persistNow() =
  var buf = ""
  for st in strokes:
    buf.add $st.ch & "," & $st.col & "," & $st.line & "," & $int(st.red) & ";"
  buf.add "|" & $sheetNo & "," & $col & "," & $line & "," & $int(red) & "," & $int(bellRung)
  saved.set(buf)
```

- **A plain `int32`** for a flag: `muted = savedMuted.get() == 1` (`app.nim:935`) and
  `savedMuted.set(if muted: 1'i32 else: 0'i32)` (`app.nim:982`). Use the *typed* API
  whenever the value is a scalar — the packing is free and the type check on restore is
  free too.
- **Restore is defensive parsing**, because a save file can be from an older build
  (`app.nim:833-854`): split on `|`, check `parts.len < 2`, skip short records with
  `if e.len < 3: continue`, and parse with `int32(parseInt(f[1]))` from
  `import std/strutils` (`app.nim:16`).

Note what is **not** saved: the per-stroke PRNG seeds are regenerated on restore
(`app.nim:846: seed: int32(strokes.len) * 7919 + 7919`). Because the seeds are a pure
function of the stroke index, a restored letter re-stamps identically — the same
argument as `HTML5-CANVAS-TO-SKIA.md` §8.

`localStorage` semantics you lose: there is no `localStorage.clear()` for one key, no
enumeration of keys, and no storage event across windows.

---

## 7. `element.animate()` and CSS `@keyframes`

### On a node — a real prop

```nim
proc animate*(node: Node; target: string; to: float32; duration: int32 = 300;
              easing: Easing = easeOutCubic; startVal: Option[float32] = none(float32);
              delay: int32 = 0; loop: int32 = 1; yoyo: bool = false;
              trigger: string = "mount")                             # yantra.nim:437-440
  ## target: property to animate ("opacity", "x", "y", "width", "height", "scale", "rotation")

proc transition*(node: Node; kind: string; duration: int32 = 300; easing: Easing = easeOutCubic) =
  ## kind: "enter" | "exit" | "move" | "resize" | "opacity"           # yantra.nim:462-464
```

plus the presets in `sdk/ui/motion.nim:29-48` — `fade()`, `fly()`, `pop()`, `turn()` for
enter/exit, and `spin()`, `pulse()`, `breathe()`, `bob()` for loops — usable directly as
props: `animate = spin()`, `enter = fly(y = 12)`.

The engine plays these on **its own clock**: "the app does no work per frame and nothing
re-renders" (`motion.nim:1-2`). That is the whole difference from `element.animate`:
there is no per-frame app code at all.

### In a canvas — a `var` and the frame loop

There is no `animate` for a `Draw`. Two mechanisms, and the port uses both:

1. **Hand-rolled exponential easing** in `tick()` (§4): `v = v + (target - v) * min(1, dt * rate)`.
   Right for anything that has a target value (carriage position, paper offset).
2. **A countdown with a normalised `f`** for anything time-bound — the port's `ding`
   flourish (`app.nim:679-683`):

```nim
if dingT >= 0:
  let f = dingT / 1.4'f32                       # 0 → 1 over 1.4 s
  let dx = cx((X0 - MX) / U) + 40.0'f32 * U
  d = d.text(dx, MY + 20.0'f32 * U - f * 34.0'f32,
         16.0'f32 * U, withA(cLamp, (1.0'f32 - f) * 0.9), "ding", 400)
```

`f` is then used for position, alpha, scale — one clock, any number of channels. The
toast does the same with a fade in *and* out from one counter
(`app.nim:685: let a = min(1.0'f32, min(toastT, 2.6'f32 - toastT) * 4.0'f32)`).

Keep a `Ease` function if the page used one: the page's easing curve becomes a small
`proc ease(t: float32): float32` called from `tick()` with `f`.

---

## 8. `visibilitychange`, `pagehide`, focus loss

**No event exists for this.** Grep the wire `Event` enum (`wire.nim:322-356`): there is
no visibility, no blur-window, no pagehide. What exists is `evFocus` / `evBlur`
(4 / 5) for *node* focus, and `evSystemTheme` (26).

The workable substitute is `frameDt()` itself: a hidden or un-focused window stops
producing frames, so on the first frame back your clock **jumps by the whole
stall**. Two consequences to design for:

- **Clamp the step**, or the first frame after a stall teleports everything:
  `let k = min(1.0'f32, frameDt() * 9.0)` (`app.nim:908`) bounds the easing factor at
  1 whatever `dt` was.
- **Do not run gameplay logic off wall-clock time** — use accumulated `dt`, as `tick()`
  does.

> **RESOLVED 2026-10-03 — this replaces an open verification marker.** The old text
> said it was unknown whether `frameDt()` goes to **0** or to **one large value**
> while a window is unfocused, and told you to go test it. That is settled from
> source: `render/native/engine.nim:3241` is
> `e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60`.
> A stall produces **one large value** on return; only the synthetic first frame is
> `1/60`. So **clamp** — and now you know why, and that "goes to 0" was never the
> failure mode to fear. Host side: `host/host.nim:926` (`of 7: host.frameDt`),
> reached from `y_input(7, 0)`.

**Audio is the other thing that should stop.** The port gates every sound on the user
toggle rather than on focus (`proc playS(s: Sound) = if not muted and s.id != 0: play(s)`,
`app.nim:706-707`).

---

## 9. Pointer capture and drag

`setPointerCapture` does not exist. The pattern that replaces it is **a capture id in a
`var`**: set it on `evPointerDown`, act on it in `evPointerMove`, clear it in
`evPointerUp`. The SDK's own table implementation is 20 lines and is the reference
(`sdk/ui/sheet.nim:148-175`):

```nim
s.node.addHandler(evPointerDown, proc() =
  let x = yNodeSize(id, 7)
  let y = yNodeSize(id, 8)
  …                                     # find what was grabbed
  if r < 0: return
  s.dragCol = c                          # THE CAPTURE: which thing owns the pointer
  s.dragFrom = x
  s.dragW = w
  return)
s.node.addHandler(evPointerMove, proc() =
  if s.dragCol < 0: return               # not dragging: ignore move entirely
  s.colW[s.dragCol] = max(24'f32, s.dragW + yNodeSize(id, 7) - s.dragFrom)
  s.layoutCols()
  s.redraw())
s.node.addHandler(evPointerUp, proc() = s.dragCol = -1)
```

The invariants:

- The sentinel is `-1`, never `0` — node id 0 is a real node.
- The `if s.dragCol < 0: return` guard goes **first** in the move handler.
- A `evPointerUp` that never sees a down must be harmless; make the up handler
  unconditionally release.
- Add `if r < 0: return` on down so a miss does not arm the capture.

For a canvas drag, use `pointerPos()` in each handler and keep the last position in a
`var`. There is no `pointerId` and no `buttons` bitmask in the event model — `mouseHeld(1)`
(`input.nim:39`) is a polled check if you need it.

---

## 10. `window.resize`, media queries, reflow

**There is no reflow.** A Yantra window is the size you declared and it does not change
under you. The port says so in its own constants (`app.nim:30-32`):

```nim
SW   = 1280.0'f32    # scene width  (window is fixed: Yantra has no reflow)
HEAD  = 64.0'f32     # header strip height
SH   = 816.0'f32     # scene height
```

and drops the page's mobile branch entirely (`app.nim:347-349`): "Yantra windows are
fixed, so SW/SH are constants and K (the mobile split-travel factor) is always 1."

`evResize` (12) exists and is real — it fires when a node's laid-out size changes, and
you read it with `yNodeSize(id, 0)` / `, 1` (`sdk/yantra.nim:401-406`, `trackSize`;
`sheet.nim:140-143`). That is enough for a scroll area or a split pane to learn its own
size. It is **not** a viewport media query.

The CSS media-query equivalent is a size-driven branch, which the SDK expresses with a
`sized w, h:` block (`reference/15a` §0). For a canvas whose art depends on size, the
port's answer is: pick one size, and compute layout from constants at startup
(`proc layout()` — `app.nim:347-357`), not on every frame.

---

## 11. The port checklist for events

1. **Keys on the window root**, `handled()` on every consumed branch, ctrl/alt let
   through first, printable range `32..<127` with shift applied by you.
2. **One frame loop**, `dt` in seconds, every transient a countdown, every easing factor
   clamped to 1.
3. **One clock.** Prefer frame counters to `afterMs` for canvas animation; use
   `afterMs` / `after` / `timeline` for scripted steps between user actions.
4. **Hit-test with the same functions the draw used.** Same `cx()`/`by()`, same consts,
   same current positions for anything that moves. Inflate the box. Convert coordinates
   back to the space the art was authored in.
5. **Prefer a node** for anything that must be clicked, focused or tabbed to. Only hand-
   write hit-tests for things that are genuinely part of the illustration.
6. **Persistence**: `persistent[T]` per key; typed for scalars, hand-serialised for
   structures; parse defensively on restore.
7. **Drag**: a capture `var` set on down, checked first in move, cleared on up, with a
   `-1` sentinel.
8. **Clamp `dt`** — the first frame after a stall is the one that breaks every port.
9. **Nothing in the `Event` enum covers the page lifecycle.** Visibility, unload and
   cross-window events do not exist; design so that losing all of them is survivable.