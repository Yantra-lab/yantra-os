# 11 — Input: pointer, keyboard, focus, drag and drop

Ground truth for this chapter (read, not guessed):

- `sdk/ui/input.nim` — `pointerPos`, `pointerPage`, `mouseDelta`, `keyHeld`, `frameDt`
- `sdk/ui/keys.nim` — `KeyPress`, `lastKey()`, `handled()`, key constants
- `sdk/ui/keybind.nim` — chords, conflicts, reset
- `sdk/core/runtime.nim:180-223` — `onClick`/`onChange`/`onDrag*`/`onDrop`, `DroppedFile`
- `sdk/yantra.nim:341-348, 384-416, 462-467` — `tabIndex`, `maxLength`, `pattern`, `Node.on`, the per-event helpers
- `sdk/ui/dsl.nim:70-75` — the **exact** `on…:` → `Event` table; `:223-246` — state blocks
- `host/host.nim:589-623` — `y_node_size` axis table; `render/native/engine.nim:3016-3023` — how `pointerPos` is computed
- `render/native/engine.nim:2597-2670` (pointer move), `2915-2955` (pointer down), `3025-3069` (pointer up / click), `2816-2848` (context menu), `3235-3284` (frame + key dispatch), `3207-3210, 3296-3310` (focus + tab), `2771-2781` (focus/blur events), `2797-2805` (dismiss), `3990-4013` (drop)
- `render/native/yantra_run.nim:158-203` — the SDL event loop
- `protocol/props.md` — the legal DSL props
- `apps/minipaint/ENGINE-ISSUES.md:208-241` — the key-dispatch ancestor-only lesson
- `apps/minipaint/PORT-NOTES.md:335-354, 1849-1859` — the drag-and-drop gaps

---

## 1. Pointer events

### 1.1 The complete table

`sdk/ui/dsl.nim:70-75` is the authoritative list — this table is the DSL's whole
vocabulary, matched case-insensitively:

| DSL handler | `Event` | Wire id | Imperative form |
|---|---|---|---|
| `onclick:` | `evClick` | 0 | `onClick(node, proc())` / `clickable(node, proc())` |
| `onpointerdown:` | `evPointerDown` | 20 | `node.on(evPointerDown, proc())` |
| `onpointermove:` | `evPointerMove` | 21 | `node.on(evPointerMove, proc())` |
| `onpointerup:` | `evPointerUp` | 22 | `node.on(evPointerUp, proc())` |
| `onkey:` | `evKey` | 15 | `node.on(evKey, proc())` |
| `onframe:` | `evFrame` | 33 | `node.on(evFrame, proc())` |
| `onchange:` | `evChange` | 1 | `onChange(node, proc())` |
| `onsubmit:` | `evSubmit` | 2 | `node.on(evSubmit, proc())` |
| `oninput:` | `evInput` | 3 | `onInput(node, proc())` |
| `onfocus:` | `evFocus` | 4 | `onFocus(node, proc())` |
| `onblur:` | `evBlur` | 5 | `onBlur(node, proc())` |
| `ondismiss:` | `evDismiss` | 14 | `node.on(evDismiss, proc())` |
| `oncontextmenu:` | `evContextMenu` | 13 | `node.on(evContextMenu, proc())` |
| `ondragstart:` | `evDragStart` | 30 | `onDragStart(node, proc())` |
| `ondragover:` | `evDragOver` | 31 | `onDragOver(node, proc())` |
| `ondrop:` | `evDrop` | 32 | `onDrop(node, proc())` **and** `onDrop(node, proc(f: DroppedFile))` |

Everything else (`onscroll:`, `onresize:`, `ontabchange:`, `oncanvasdraw:`,
`onmediaend:`, `ontimeupdate:`, `onselectionchange:`) has **no DSL word** — use
the imperative form: `onScroll`, `trackSize`, `onTabChange`, `onSelectionChange`,
`onCanvasDraw`, `onMediaEnd`, `onMediaError`, `onMediaReady`, `onTimeUpdate`
(all `sdk/yantra.nim:407-416`).

The generic imperative form is `proc on*(node: Node, event: Event, handler: proc())`
(`sdk/yantra.nim:384`) — that is the escape hatch for any event, including
`evLinkClick`, `evCommand`, `evSpellMenu`, `evSystemTheme`, `evDeepLink`.

### 1.2 How pointer dispatch actually works (`render/native/engine.nim`)

This is the part HTML habits get wrong. Read it before porting any mouse code.

```nim
proc canvasPointer(e: Engine; id: int32; ev: int32; x, y: float32): bool =
  if id < 0 or not e.s.valid(id) or e.s.handlerFor(id, ev) < 0: return false
  let b = e.boxes.getOrDefault(id)
  e.s.pointerAt = (x - b.x, y + e.scrollY - b.y)
  e.s.pointerPage = (x, y + e.scrollY)
  e.fire(id, ev)
  true
```

Rules, all verified:

- **The target is the single deepest node under the pointer that has that exact
  handler** (`hitTest` / `hitAll`). Pointer events **do not bubble**. A parent
  with `onPointerDown` does *not* receive a child's press — unlike `onKey`, which
  walks ancestors (§3).
- `canvasPointer` has **no canvas check in the source** — it reads
  `e.boxes[id]` and fires on any node that has the handler, so a `panel` or the
  app root can take pointer events the same way. Every shipped example happens
  to put them on a canvas (`examples/shell/paint.nim:36-38`,
  `apps/minipaint/app.nim:5590-5614`, `apps/typewriter/app.nim:1014`), and
  `render/native/t_paint.nim:54` is the regression test:
  *"painting with the pointer: onPointerDown with pointerPos() draws where it was
  pressed"*.
- **PointerDown**: `e.pressed = e.hitTest(x, y)` then
  `discard e.canvasPointer(n, E_POINTERDOWN, x, y)` (`engine.nim:2937-2940`).
- **PointerUp**: fires on **`e.pressed`** — the node the press landed on, not the
  node under the pointer at release (`engine.nim:3033`). A drag therefore
  down-here / up-there keeps delivering to the origin node.
- **PointerMove** fires on the **hover** node, or on the pressed node if that has
  a Move handler (`engine.nim:2625-2627`):
  ```nim
  if e.pressedChild < 0:
    let over = if e.pressed >= 0 and e.s.handlerFor(e.pressed, E_POINTERMOVE) >= 0: e.pressed else: e.hover
    discard e.canvasPointer(over, E_POINTERMOVE, x, y)
  ```
  So **once a node is pressed, its `onPointerMove` keeps getting every move** —
  that is the drag loop. You do not need pointer capture; just keep your own
  "is dragging" flag.
- **Click** is not a pointer event at all. It is synthesised on release:
  `pointerUp` re-hit-tests and only fires `E_CLICK` when
  `p >= 0 and p == target` (`engine.nim:3054-3066`) — press and release on the
  same node, or no click. A Checkbox fires `E_CHANGE` then `E_CLICK`.
- **Right click** → `contextClick` (`engine.nim:2816-2848`): walks the hit chain
  deepest-first, opens the **first** `contextmenu` node it finds (searching its
  children and `group`s), and fires `E_CONTEXTMENU` on the first node that has a
  ContextMenu handler. A right *release* also calls `contextClick` (spell menu).
  Note: only button 3 does this; there is no middle-button event at all.

---

## 2. Pointer coordinates — THE critical part for canvas ports

### 2.1 The API

```nim
# sdk/ui/input.nim:54-58
proc pointerPos*(): (float32, float32) = (yNodeSize(0, 7), yNodeSize(0, 8))
  ## In onPointerDown / onPointerMove / onPointerUp on a canvas: where the pointer is, in the
  ## canvas's own pixels (painting, dragging on a canvas).

proc pointerPage*(): (float32, float32) = (yNodeSize(0, 13), yNodeSize(0, 14))
  ## Where the pointer is in the window's page.
```

**There is no `event.x` / `event.y`. There is no event object at all.** Handlers
are `proc()` with no arguments (`sdk/core/runtime.nim:180-185`, `dsl.nim:253-256`).
The coordinates are read by calling a global.

### 2.2 The exact computation (`engine.nim:3020-3021`)

```nim
e.s.pointerAt  = (x - b.x, y + e.scrollY - b.y)     # in the target node's own pixels
e.s.pointerPage = (x, y + e.scrollY)                  # in page pixels (scroll added back)
```

where `b = e.boxes[id]` is the node's laid-out box and `e.scrollY` is the window
scroll offset. `x`/`y` arriving at `pointerDown/Move/Up` are **window logical
pixels** (`yantra_run.nim` divides the raw SDL values by `density`, so HiDPI is
already handled).

Read through `host.nim:600-621` — the whole `y_node_size` axis table:

```
axis 0  → laid-out width          axis 1  → laid-out height
axis 2  → vertical scroll         axis 9  → horizontal scroll
axis 7  → pointerAt[0]            axis 8  → pointerAt[1]
axis 13 → pointerPage[0]          axis 14 → pointerPage[1]
axis 3/4 → media time / duration  axis 5, 1000+i → waveform count / peak i
axis 6  → block caret             axis 10 → linkHit   axis 11/12 → findCount/findAt
axis 15/16 → command / menuCmd    axis 17/18 → systemDark / accentRgb
axis 19/20 → spell range          anything else → scrollOf (vertical)
```

Its doc comment (`host.nim:591-596`) is explicit about the two that matter for a
port: *"0 before the first layout / scroll"*, and the **size** axes are filled
only **for nodes with a Resize handler** while the **scroll** axes are filled
only **for nodes with a Scroll handler**.

### 2.3 Rules and traps

- **`pointerPos()` is only meaningful inside a pointer handler.** It is set as a
  side effect of `canvasPointer`, immediately before the handler is fired. Outside
  one it holds the last event's value. Verified empirically:
  `apps/minipaint/PORT-NOTES.md:1541` — *"`pointerPos()` returns exactly the
  injected click."*
- **It is relative to the node that received the event**, not the page. If a
  `panel` sits 40 px from the left, `pointerPos()[0]` at the page's left edge is
  `-40`. If the node has a `radius` or `border` this is still the **border box**,
  not the visual inner box.
- **Canvas content scroll is a separate offset.** A canvas whose content is larger
  than its box keeps its own `scrollOf` / `scrollXOf`
  (`engine.nim:3174-3185`), read back with `yNodeSize(id, 2)` for y and
  `yNodeSize(id, 9)` for x. If you scroll a canvas's content, **you must add that
  offset yourself** — `pointerPos()` does not.
  (The props are `pCanvasWidth` / `pCanvasHeight` — wire ids 77/78 — and they are
  **not** in `protocol/props.md`, so `canvasWidth = 900.px` in the DSL is a `Y001`
  error; set them imperatively with `node.set(pCanvasWidth, 900)`.)
  This is exactly the trap recorded in
  `apps/minipaint/PORT-NOTES.md:823-827`: *"All canvas pointer input routes
  through `screenToCanvas`; raw panel offsets are valid only at 100% with no
  pan."* That is, a port that also zooms and pans must map page → world itself.
- **`pointerPage()`** is what you want for overlay/hit-testing maths that spans
  several nodes, and it includes window scroll.
- **The node's own size**, for a 100 % / zoom mapping:
  ```nim
  let (w, h) = (yNodeSize(node.id, 0), yNodeSize(node.id, 1))
  ```
  Only refreshed when the node has a **Resize** handler, or once after layout
  (`sdk/yantra.nim:401-406`, `trackSize(node, w, h)`). `onFrame:` reading
  `yNodeSize` without a Resize handler gives `0` before the first layout.
- **Transforms are NOT applied.** `pointerPos` is layout-space; `scale`, `rotate`
  and `translate` are a *rendering* transform (`poseOf`). A canvas under
  `scale = 2` receives untransformed pointer coordinates. Do the inverse
  transform yourself.
- **High-DPI**: already divided by `density` (`yantra_run.nim:162-166`), so
  `pointerPos` is in **logical px**, matching `width = 200.px`.
- **Raw motion** for a locked pointer / first-person camera:
  `mouseDelta(): (float32, float32)` (`input.nim:37-38`) = movement since the
  last frame, also while locked, and it is **zeroed after each Frame event**
  (`engine.nim:3247-3248`), so read it inside `onFrame:`.
  `apps/minipaint/ENGINE-ISSUES.md:1193-1213` (**E4**): `pointerIsLocked()`
  is permanently `false` — `host.pointerLocked` is never assigned. Track your own.

---

## 3. Keyboard

### 3.1 `onKey:` — event-style keys

```nim
# sdk/ui/keys.nim
type KeyPress* = object
  code*: int32     ## SDL key code: a letter or digit is its lower-case ASCII code
  mods*: int32     ## modifier bits

proc lastKey*(): KeyPress = KeyPress(code: yKey(0), mods: yKey(1))
proc handled*() = yKeyHandled()

proc shift*(k: KeyPress): bool = (k.mods and 0x0003) != 0
proc ctrl*(k: KeyPress): bool  = (k.mods and 0x0CC0) != 0      ## Ctrl, or Cmd on a Mac
proc alt*(k: KeyPress): bool   = (k.mods and 0x0300) != 0
proc `==`*(k: KeyPress; code: int32): bool = k.code == code
proc `==`*(k: KeyPress; c: char): bool =
  k.code == int32(ord(if c in {'A'..'Z'}: char(ord(c) + 32) else: c))
```

```nim
app("Search"):
  onKey:                       # on the APP ROOT — see §3.4
    let k = lastKey()
    if k.ctrl and k == 'k': searching.set(true); handled()
    elif k == keyDown: selected.set(selected.get + 1); handled()
```

- `==` folds `'K'` to `'k'`, so `k == 'k'` matches both cases. **The key code is
  always the lower-case ASCII code**, regardless of Shift.
- `handled()` stops the key dead: no outer handler **and** no built-in action, so
  an app can take Enter, Escape or the arrows from a field.
  `render/native/engine.nim:3283`: `if e.s.keyHandled or e.crashed.len > 0: return`.
- There is **no `keyUp` event for apps.** Only `keyUp*` on the engine, feeding
  the polled `keyHeld`.

### 3.2 `keyHeld` — polled, game-style

```nim
# sdk/ui/input.nim
proc keyHeld*(key: int32): bool = yInput(0, key) != 0
proc keyHeld*(c: char): bool    = yInput(0, int32(c)) != 0
```

Polled state, valid anywhere, updated by the engine's `keyUp`
(`engine.nim:3214: e.s.keysHeld.excl code`) and key-down path. Read it in
`onFrame:`; the idiomatic form is `if keyHeld('d'): ballX.set(ballX.get + 10 * frameDt())`
(`examples/shell/world.nim:29`). `keyShift = 0x400000E1`, `keyCtrl = 0x400000E0`,
`keyAlt = 0x400000E2` (`input.nim:13-15`) are for `keyHeld`, **not** for `==`.

### 3.3 Key constants — exact names and values (`sdk/ui/keys.nim:19-40`)

| Constant | Value | | Constant | Value |
|---|---|---|---|---|
| `keyBackspace` | `8` | | `keyHome` | `0x4000004a` |
| `keyTab` | `9` | | `keyPageUp` | `0x4000004b` |
| `keyEnter` | `13` | | `keyEnd` | `0x4000004d` |
| `keyEscape` | `27` | | `keyPageDown` | `0x4000004e` |
| `keySpace` | `32` | | `keyPeriod` | `0x40000031` |
| `keyDelete` | `127` | | `keyComma` | `0x40000033` |
| `keyRight` | `0x4000004f` | | `keyLeft` | `0x40000050` |
| `keyDown` | `0x40000051` | | `keyUp` | `0x40000052` |

All `int32`. Letters and digits are **not** constants — compare with a char:
`k == 'q'`, `k == '7'`.

There is **no `keyPeriod` gap for the numeric keypad** and no F-key constants in
the SDK. `render/native/engine.nim` additionally knows
`KpEnter = 0x40000058` internally (Enter submits from the keypad) and
`render/native/engine.nim:3296-3298` swaps Left/Right under RTL — neither is
reachable by name from an app. `keybind.nim` adds `fKeyBase = 0x4000003a` (F1) …
`fKeyLast = 0x40000045` (F12) for *naming* chords only.

### 3.4 Key dispatch is ancestor-only — the single most important gotcha

`render/native/engine.nim:3276-3284`:

```nim
var at = if e.focus >= 0 and e.s.valid(e.focus): e.focus else: 0'i32   # the app first
while at >= 0:                                                         # Key handlers from the focus out
  if e.s.handlerFor(at, E_KEY) >= 0:
    e.s.keyCode = code; e.s.keyMods = mods; e.s.keyHandled = false
    e.fire(at, E_KEY)
    if e.s.keyHandled or e.crashed.len > 0: return
  at = if at == 0: -1'i32 else: e.node(at).parent
```

- Keys go to the focused node, then **its ancestors**, then node `0` (the window
  root) — and node 0 sees **every** key, even with nothing focused.
- **It never descends.** A handler on a `canvas` inside the app is **unreachable**,
  and clicking the canvas first does not help.
  `apps/minipaint/ENGINE-ISSUES.md:208-241` documents this as a real bug they
  hit and the fix they verified:
  ```nim
  app("miniPaint", …):
    onKey:                       # attaches to the WINDOW node
      …
    canvas @c(…):
      onPointerDown: …           # pointer events are fine on the canvas
  ```
- The same pattern in shipped code — `apps/typewriter/app.nim:1010-1021` puts
  `evKey` on **`page`**, the parent of the `canvas` it draws into, because the
  canvas is the focused-at-times child and `page` is on the ancestor path:
  ```nim
  scene = canvas(page, …)            # the drawing surface
  scene.onClick(proc() = let (px, py) = pointerPos(); …)
  page.addHandler(evKey, proc() = let k = lastKey(); …)
  ```
  Verified with `expandAppDsl`: root `onKey` expands to `winNode_….on(evKey, …)`;
  the canvas form expands to `canvasNode_….on(evKey, …)`, which the walk never
  visits.
- **Lesson: app-level shortcuts live on the app root. Mouse lives wherever.**

### 3.5 Key repeat

- SDL delivers a key-down event for each OS auto-repeat.
  `libs/nimsdl3/src/nimsdl3.nim:16`: *"`evKeyUp` … `button` on `evKey` is 1 for
  a repeat"*.
- `render/native/yantra_run.nim:175-181` forwards **every** `evKey` to
  `e.key(ev.key, ev.mods)` with no repeat flag, and `e.key` has no repeat
  parameter.
- **Consequence: `onKey:` fires again on each auto-repeat, and `lastKey()` cannot
  tell a repeat from a fresh press.** If you need "fire once", debounce yourself:
  keep `state` of the last handled key + the engine clock, or use `keyHeld`
  polling in `onFrame:` instead of `onKey:` for held keys.
- **Escape is special-cased before dispatch** (`yantra_run.nim:176-179`): if the
  pointer is locked, Escape releases it and never reaches the app; else if nothing
  is focused and the app has **no** `onFrame:` handler, Escape closes the window.

### 3.6 What a key does when no handler takes it

After the ancestor walk returns without `handled()`, `e.key` runs the built-in
actions (`engine.nim:3286-3390`): Escape closes the top overlay / clears focus;
Tab moves focus; Enter/Space on a focused Button/Checkbox fires Click; in a
focused text field arrows, Home/End/PageUp/PageDown, Backspace/Del, Ctrl+C/X/V/Z
and Enter all act; Ctrl+C on read-only `Text` copies the selection.

---

## 4. Focus, tab order, text inputs

### 4.1 Focus events

```nim
proc onFocus*(node: Node, handler: proc()) = node.on(evFocus, handler)
proc onBlur*(node: Node, handler: proc())  = node.on(evBlur, handler)
```
DSL: `onfocus:` / `onblur:`.

Fired by `Engine.focusOn` (`engine.nim:2771-2781`), which fires **Blur on the
old node before Focus on the new one**, only when the target actually changes.
There is **no `focus()` API for an app** — the SDK exposes no imperative "give
this node the keyboard". Focus is set by click, by Tab, or by an overlay opening
(`engine.nim:2801` focuses `-1` when an overlay containing the focus closes).

`focusVisible` is engine-internal (set on keyboard Tab, cleared on mouse press),
so a `focused:` style block fires on mouse focus too.

### 4.2 Tab order — `pTabIndex` is a no-op natively

- `sdk/yantra.nim:347`: `proc tabIndex*(node: Node, v: int32) = node.set(pTabIndex, v)`.
  `tabIndex` is **not** in `protocol/props.md`, so `tabIndex = 2` in the DSL is a
  compile error (`Y001 unknown prop`). It is imperative-only.
- **`P_TABINDEX` is read only by `render/qmlgen.nim:662`** — the legacy QML path.
  `render/native` never reads it.
- Native tab order is `e.paintOrder` filtered by `focusable`
  (`engine.nim:3296-3310`):
  ```nim
  proc focusable(e: Engine; id: int32): bool =
    n.alive and n.visible and (n.kind in [K_INPUT, K_TEXTAREA, K_BUTTON, K_CHECKBOX] or
                               e.s.handlerFor(id, E_CLICK) >= 0)
  ```
  So it is **document order**, Shift+Tab goes backwards and wraps, Tab into a
  field selects its whole text, and inside a Modal/Drawer focus is trapped to
  the overlay's subtree. Note `K_SWITCH` and `K_RADIO` are **not** in the
  focusable kind list — make them focusable with an `onClick:` handler.

### 4.3 Text inputs

DSL nodes: `input` and `textarea` (`sdk/ui/dsl.nim:372-375`). Legal props, from
`protocol/props.md`: `value` (27, Input/TextArea/Slider/Progress/Select),
`placeholder` (35, Input/TextArea), `rows` (75, TextArea), `block` (102),
`focusAt` (118), `spellcheck` (125), `replace` (126, Input/TextArea), plus
`text`, `size`/`fontSize`, `fill`, `radius`, `pad`, `width`. `disabled` (29) is
allowed on Input but **not** on TextArea.

**A bare `Signal[string]` as the first argument is a two-way binding**
(`sdk/ui/dsl.nim:377-385` — the DSL wires `evInput` for you):

```nim
input(draft, placeholder = "What needs doing?", grow = 1, fill = 0x17171D, radius = 10):
  onSubmit: add()
```

That expands to `set(pValue, draft.get())` in an effect, plus
`node.on(evInput, proc() = draft.set(node.getStr(pValue)))`. Read `draft.get()`
anywhere; it is always current. This is the form every built example uses
(`examples/todo.nim:61`, `examples/shell/chat.nim:46`, `notes.nim:69`).

The event-form alternative — for a field you want to *validate*, not store.
Note that `node = input(…)` (the `nameNode =` form) is what gives you a Nim
identifier; the `@name` form only sets a runtime label (§5):

```nim
var qNode: Node                       ## declared BEFORE the app block
app("…"):
  column:
    qNode = input(placeholder = "type a name"):
      onInput:
        let v = qNode.getStr(pValue)  # `node.value(v)` is the setter; `getStr` is the getter
        if v.len > 40: warnTooLong(v) # enforce maxLength yourself — the engine does not
      onSubmit:
        run(qNode.getStr(pValue))
```

`node.value(v)` (`sdk/yantra.nim:314-317`) is the **setter** only; the getter is
`node.getStr(prop)` (`sdk/core/runtime.nim:154/165`).

Events: `onInput` on every edit (`engine.nim:2726`), `onSubmit` on Enter or
keypad Enter in a focused field (`engine.nim:3387, 3422`), `onChange` on a
Checkbox toggle or a Radio/Select choice, `onFocus`/`onBlur`.

The engine writes the typed text into `pValue` on every edit (`e.edit` →
`setValue` → `E_INPUT`), so an `onInput` handler sees the new value already.

**Honest gaps (verified):**

| Prop | Status | Evidence |
|---|---|---|
| `maxLength(node, v)` | imperative only, **never read by the native engine** | `sdk/yantra.nim:329` sets `pMaxLength` (51); grepping `render/native` for `P_MAXLENGTH` gives **0 hits**. Not in `props.md`, so not a DSL prop. Enforce it yourself in `onInput`. |
| `pattern(node, v)` | same | `sdk/yantra.nim:330` sets `pPattern` (52); 0 hits in `render/native`. Validate in `onInput`/`onSubmit`. |
| `type = "number"` / `type = "email"` | no `type` prop at all | not in `props.md`. Filter in the handler. |

Built-in editing the engine gives you for free in a focused field: caret
placement, click-drag selection, double-click word / triple-click all,
arrow/Home/End/PageUp/PageDown with Shift-select, Ctrl+C/X/V/Z, Backspace/Del,
and clipboard. Blocking a key means `handled()` — but note the ancestor walk
means a `handled()` in the app root's `onKey:` **steals Enter from every field**.
Call `handled()` only when you actually mean it.

---

## 5. Naming a node: `nameNode = …` vs `@name`

These are two different things and ports get them wrong constantly.

| Form | What it does |
|---|---|
| `qNode = input(placeholder = "…")` | **binds a Nim identifier** `qNode` (`dsl.nim:442-443`, `assignTo`). The `Node` must be declared before the `app` block (`var qNode: Node`, `sdk/tests/t_style.nim:38`). Then `qNode.getStr(pValue)`, `qNode.set(...)`, `qNode.on(...)` all work. |
| `canvas @stage(width = 300.px, …)` | sets the wire prop **`pName = "stage"`** (`dsl.nim:444-445`). It is a **runtime label** for hot reload, inspectors and tests — **it does not create a Nim identifier**, and referring to `stage` in code is `Error: undeclared identifier`. Verified: `canvas @stage(...)` then `getStr(pName)` returns `"stage"`. |
| both | `qNode = canvas @stage(width = 300.px, …)` — Nim name **and** runtime label. |

Two accepted syntaxes (`takeHandle`, `dsl.nim:276-291`):
`panel @card(fill = …)` (nnkCall — the handle, then the arguments) and
`text @headline "Hi"` (nnkPrefix). The mixed form
`button @go "Hover me"(fill = …)` is **not** one of them — write
`button @go("Hover me", fill = …)`.

---

## 6. Hover / press / focus state props

There are **no DSL props** for these. They are set only through the
`hover:` / `pressed:` / `focused:` blocks, and exactly six prop names are legal
inside one (`sdk/ui/dsl.nim:233-242`; anything else is a compile-time `Y013`):

| In the block | Wire prop | `hover:` | `pressed:` | `focused:` |
|---|---|---|---|---|
| `fill` | `…Fill` | 122 | 126 | 130 |
| `color` | `…Color` | 123 | 127 | 131 |
| `borderColor` | `…Border` | 124 | 128 | 132 |
| `opacity` | `…Opacity` | 125 | 129 | 133 |
| `scale` | `…Scale` | 137 | 138 | 139 |
| `y` | `…Y` | 140 | 141 | 142 |

`border`, `radius`, `width`, `x`, `fontSize` etc. are **compile errors** in a
state block. The engine "switches them; the app does no work"
(`dsl.nim:226-227`).

**To react in code**, there is no `isHovered()` / `isPressed()` query — you build
it from `onPointerDown`/`onPointerMove`/`onPointerUp` on that node (or the root,
which sees the pointer move for everything) plus your own `state`. See §8.4.

Under a `transition = …`, the state colours are *eased* (`engine.nim:1685, 1787,
1810, 1892`), so a hover that ends halfway glides back from halfway.
---

## 7. Keybinds (`sdk/ui/keybind.nim`)

Pure logic, **no imports**, so it compiles and runs headless. It does **not**
register anything with the engine: it is the model behind a rebinding settings
page. You match a pressed key to a `Chord` yourself and then act.

### 7.1 The types

```nim
type
  Chord* = object
    code*: int32               ## SDL key code; a letter/digit is its lower-case ASCII
    ctrl*, shift*, alt*, super*: bool

  ScopeKind* = enum
    skGlobal,                 ## fires wherever Yantra has focus
    skWindow                  ## fires only in `owner`; the same chord may exist elsewhere

  Binding* = object
    id*: string               ## the action, e.g. "tiling.split"
    chord*: Chord             ## the live binding
    deflt*: Chord             ## what reset restores
    scopeKind*: ScopeKind
    owner*: string            ## "" when global; the window id when window-local

  Provenance* = enum
    pvInjected,               ## a value this page made up to fill the field in
    pvReported,               ## the shell told us; we did not read hardware ourselves
    pvDetected                ## read from the actual device

  NetworkReading* = object
    ssid*, security*: string
    rssi*: int                ## dBm; meaningless unless `source` is pvDetected
    source*: Provenance

  WifiProfile* = object
    ssid*, password*, security*: string
```

### 7.2 The API

```nim
proc keyName*(code: int32): string
proc formatChord*(c: Chord): string       ## "Ctrl+Shift+K" — fixed modifier order
proc sameChord*(a, b: Chord): bool
proc scopeLabel*(b: Binding): string      ## "Global" | "This window (w3)"
proc clash*(a, b: Binding): bool          ## same chord AND overlapping scopes
proc conflictIds*(bs: seq[Binding]; i: int): seq[string]
proc tryBind*(bs: var seq[Binding]; i: int; c: Chord): (bool, seq[string])
proc resetBinding*(bs: var seq[Binding]; i: int)
proc resetAll*(bs: var seq[Binding])
proc configuredReading*(ssid, security: string): NetworkReading
proc claimsHardware*(r: NetworkReading): bool
proc readingLabel*(r: NetworkReading): string
proc serializeWifi*(ps: seq[WifiProfile]): string
```

Key facts:

- **A chord is shown to a person, never as a number.** `formatChord` emits
  `Ctrl+Shift+Alt+Super` in that fixed order, then `keyName(code)`.
- **Conflicts are refused, not silently stolen.** `tryBind` probes with a copy and
  returns `(false, [clashing ids])` **changing nothing**, so the picker can show
  the conflict. `clash` is true only when the chords match *and* the scopes
  overlap (both global, or both window-scoped to the same `owner`).
- **Reset is per-binding (`deflt`) or global (`resetAll`).**
- `keyName` falls back to `"Key(<n>)"` for an unknown code rather than going
  blank, and understands F1–F12 via `fKeyBase = 0x4000003a` /
  `fKeyLast = 0x40000045`.
- The key-code constants are **repeated** here on purpose so the module stays
  dependency-free — the header warns that if a code in `keys.nim` moves, move it
  here too. They match exactly.

### 7.3 Persistence

There is **no keybind serialiser** in `keybind.nim`. `serializeWifi` is the only
serialiser and it exists to demonstrate one rule: a password is **never**
interpolated, it is replaced *structurally* by `redacted = "<redacted>"`, so no
code path can leak it.

For keybind persistence, use the SDK's own state persistence
(`sdk/core/hotstate.nim` / `state(...)`), which already serialises app state.
**CLOSED 2026-10-03 — `Chord` does round-trip, field by field, but only through hot-reload
state and only in a dev build.** The mechanism is generic, not chord-specific:

- `Chord` is a plain object of `int32` + four `bool` (`sdk/ui/keybind.nim:17-19`).
- `hotstate.nim` packs **any** object field by field: `hotstate.nim:29-30`
  `elif T is tuple or T is object: for f in fields(x): packInto(b, f)`, and unpacks it with the
  mirror `hotstate.nim:69-72`. A `seq[Binding]` nests through `hotstate.nim:21-23` / `:49-55`,
  and `ScopeKind`/`Provenance` go through the enum branch (`hotstate.nim:18` / `:42`). So
  `state[seq[Binding]](bindings)` is packed and restored whole.
- Every `state(...)` opts in — `sdk/core/signals.nim:198-203` calls `keepAcrossReloads` under
  `when not defined(release)`.

Three limits, so you do not read more into it than is there:

- **Dev builds only.** The registry and the four exports are both inside
  `when not defined(release)` (`hotstate.nim:78`, `:158`), so a release app carries no
  persistence at all.
- **It is hot reload, not disk.** The only consumer of `saveState` in the repo is the watcher
  (`render/native/engine.nim:4182`), and `host.nim:1295-1311` feeds the blob straight back into
  the next build's `run(app, restore)`. Nothing writes it to a file and reads it back on the
  next launch, so this does **not** give you "the user's keybinds survive a restart".
- **The node-prop wire is a different thing.** `Chord` has no wire ids and does not go over the
  `Node` prop protocol; `wire.nim` carries only `int32` / `float32` / `string` props.

The original claim — *nothing in the repo does that today* — still holds: a repo-wide grep for
`state[Chord]`, `state[Binding]` and `state[seq[Binding]]` returns **no matches**, and no file
under `apps/` mentions `Binding(` or imports `keypicker`. So this is a supported path, not an
exercised one.

### 7.4 Wiring a chord to a keypress

```nim
let bindings = @[Binding(id: "tiling.split", chord: Chord(code: int32(ord('b')), ctrl: true),
                         deflt: Chord(code: int32(ord('b')), ctrl: true), scopeKind: skGlobal,
                         owner: "")]

app("…"):
  onKey:
    let k = lastKey()
    let hit = Chord(code: k.code, ctrl: k.ctrl, shift: k.shift, alt: k.alt, super: false)
    for i, b in bindings:
      if sameChord(hit, b.chord) and b.scopeKind == skGlobal:
        split(); handled()
```

`super` (Cmd on macOS) is **not** exposed on `KeyPress` — `keys.nim` gives you
`shift`/`ctrl`/`alt` only, and `ctrl` is documented as "Ctrl, **or Cmd on a
Mac**". If you need a distinct Cmd chord, read `k.mods` directly against the SDL
bit (`KMOD_GUI = 0x0C00`; the engine's own masks are `0x0003` shift, `0x0CC0`
ctrl, `0x0300` alt — note these are *aggregated* masks, not single bits).

---

## 8. Drag and drop

### 8.1 What exists

```nim
proc onDragStart*(node: Node, handler: proc())
proc onDragOver*(node: Node, handler: proc())
proc onDrop*(node: Node, handler: proc())
proc onDrop*(node: Node, handler: proc(f: DroppedFile))   # a second overload

type DroppedFile* = object
  name*: string
  data*: string

proc droppedData*(): string
proc droppedName*(): string
proc droppedFile*(): DroppedFile
proc setDragData*(data: string)
```

DSL: `ondragstart:`, `ondragover:`, `ondrop:`.

### 8.2 The three event paths, verified

| Trigger | What happens |
|---|---|
| **In-app drag** | `pointerDown` on a node with a DragStart handler sets `e.draggingNode` and fires `E_DRAGSTART` (`engine.nim:2952-2955`). While dragging, every `pointerMove` fires `E_DRAGOVER` on the **first node in the hit chain** that has a DragOver handler (`engine.nim:2667-2670`, deepest-first, `break` after the first). `pointerUp` fires `E_DROP` on the first node in the chain with a Drop handler (`engine.nim:3045-3052`). |
| **OS file drop** | `Engine.dropFile(path, x, y)` (`engine.nim:3990-4013`) reads up to **16 MiB** of the file into `dropData`, sets `dropName = extractFilename(path)`, then fires Drop on the deepest node with a Drop handler (or the root). |
| **Right click** | `contextClick`, §1.2 — opens the nearest `contextmenu` node and fires `oncontextmenu:`. |

`render/native/t_dnd.nim` is the executable proof of all of this: it drives a
press on "Source", a move over "Drop Target" and a release, asserting
`dragging` → `over target` → `dropped node card-item`, then calls
`eng.dropFile(...)` and asserts `dropped file dropped_sample.txt:File drop payload 12345`.

### 8.3 The honest gap: what actually crosses

`Engine.dropFile` sets `e.s.dropData`, and the in-app path sets
`e.s.dropData = e.dragData` — where **`e.dragData` is set to `""` at drag start
and nothing in the repo ever sets it to anything else** (`engine.nim:2954`).
There is **no `y_drag_*` import** in `host.nim`.

- **OS file drops carry a real payload**: `droppedName()` and `droppedData()`.
- **In-app drops carry an empty string natively.** The tested working pattern
  (and the one `t_dnd.nim` exercises) is: **put the payload in your own `state`
  at DragStart and read it at Drop.** `setDragData(s)` only reaches
  `localDragData`, which `droppedData()` falls back to on **wasm32 builds**
  (`sdk/core/runtime.nim:203-210` — the `yDropData` call is inside
  `when sizeof(pointer) == 4`).

`apps/minipaint/PORT-NOTES.md:1849-1859` records the related web gap: on web
`y_drop_name` is stubbed and `y_drop_data`/`y_pick_*` are missing, so the
drag-and-drop *source* side is missing on the web target. `PORT-NOTES.md:335-350`
notes `y_drop_name` is stubbed on web while dropped files still have a name on
native. **Native is the only target where file drop is real.**

### 8.4 Drag recipes

```nim
## Click-drag (what you want for a canvas or a slider)
let dragging = state false
canvas @c(width = 400.px, height = 200.px, draw = Draw().cmds):
  onPointerDown: dragging.set(true); let (x, y) = pointerPos(); pos.set((x, y))
  onPointerMove:
    if dragging.get(): let (x, y) = pointerPos(); pos.set((x, y))
  onPointerUp:   dragging.set(false)
```
PointerMove keeps landing on the pressed node while it is pressed
(§1.2), so this needs no capture and no DragStart handler.

```nim
## Real drag & drop between two nodes
let payload = state ""                  # YOUR state is the payload — see §8.3
app("Dnd"):
  panel @card("Drag me"):
    onDragStart: payload.set("card-item")
  panel @zone("Drop here"):
    onDragOver: hoverZone.set(true)
    onDrop:
      if payload.get().len > 0: adopt(payload.get())
      payload.set("")

## File drop (native only)
input @f(placeholder = "or drop a file"):
  onDrop:
    let (n, d) = droppedName(), droppedData()
    if n.len > 0: readIt(n, d)
```
---

## 9. Recipe: porting an HTML page's keyboard + mouse

The two rules that make ports work:

1. **Keys go on the app root. Mouse goes where it happens.**
2. **Pointer state is your own `state`.** There are no event objects.

```nim
## Shortcuts on the root — the ancestor walk starts at the focus and climbs to 0,
## and it NEVER descends, so a canvas-level onKey is unreachable.
app("Port", width = 640, height = 480):
  onKey:
    let k = lastKey()
    if k.ctrl and k == 'z': undo(); handled()
    elif k == keyDelete: removeSelected(); handled()   # take Delete from a field
```

**Mapping table for a JS page:**

| In the page | In Yantra |
|---|---|
| `document.addEventListener('keydown')` | `onKey:` on the **app root** |
| `e.key === 'ArrowLeft'` | `lastKey() == keyLeft` (or `keyHeld(keyLeft)` in `onFrame:`) |
| `e.key === 'a'` / `e.code === 'KeyA'` | `k == 'a'` — case-folded, always lower-case ASCII |
| `e.ctrlKey \|\| e.metaKey` | `k.ctrl` |
| `e.shiftKey` / `e.altKey` | `k.shift` / `k.alt` |
| `e.preventDefault()` | `handled()` |
| `canvas.onmousedown` | `onPointerDown:` on the canvas; `pointerPos()` |
| `window.addEventListener('mousemove')` | `onPointerMove:` on the root (root sees everything) |
| `e.clientX / clientY` | `pointerPage()` (page px) |
| `canvas.getBoundingClientRect()` maths | `pointerPos()` (already node-local px) |
| `requestAnimationFrame(cb)` | `onFrame:` on the root, `frameDt()` |
| CSS `:hover { transform: scale(1.04) }` | `hover: scale = 1.04` + `transition = 200` |
| CSS `transition: all .2s` | `transition = 200` (colours, opacity, hover scale/lift only) |
| `setTimeout(fn, ms)` | `after 200.ms: …` / `afterMs(200'f32, …)` |
| `element.focus()` | no API — click it, or make it the first tab stop |
| `draggable="true"` / `ondrop` | `ondragstart:` + `ondrop:`, payload via your own `state` |
| `input.maxLength` / `pattern` | **not implemented** — enforce in `onInput` |
| `tabindex="3"` | **not implemented natively** — tab order is document order |

## 10. Recipe: a chess board (click-to-select + drag-to-move)

The shape every board / tool / puzzle port needs. Eight squares of `state`, a
selection, and a drag that moves the piece.

```nim
## 8 squares as 64 state cells; -1 empty, else the piece id.
var board = newSeq[int](64)
let sel = state -1                 # the selected square, or -1
let cursor = state -1              # what the keyboard cursor is on
let grabbed = state -1             # the square a drag took its piece from

const N = 8
proc sq(f, r: int): int = r * N + f

proc squareAt(x, y: float32): int =
  ## pointerPos() is already in this canvas's own pixels: subtract the origin and
  ## divide by the cell size. Add the canvas's own scroll offset if it scrolls.
  let f = int(x) div CELL
  let r = int(y) div CELL
  if f < 0 or f >= N or r < 0 or r >= N: -1 else: sq(f, r)

proc pieceAt(i: int): int =
  if i < 0 or i >= board.len: -1 else: board[i]

proc movePiece(from, to: int) =
  if from >= 0 and from < board.len and to >= 0 and to < board.len and board[from] != -1:
    board[to] = board[from]
    board[from] = -1
    version.set(version.get + 1)   # the bump that makes `draw` re-emit
```

**Click to select, click again to move** (the accessible baseline):

```nim
canvas @board(w = CELL * N, h = CELL * N,
              draw = drawBoard(board, sel.get, cursor.get)):
  onPointerDown:
    let i = squareAt(pointerPos())
    if i < 0: return
    if sel.get >= 0 and pieceAt(i) == -1: movePiece(sel.get, i)
    elif pieceAt(i) != -1: sel.set(i)
    else: sel.set(-1)
```

**Drag to move** — three lines more, and it needs no capture, because
`onPointerMove` keeps firing on the pressed node:

```nim
  onPointerDown:
    let i = squareAt(pointerPos())
    if i >= 0 and pieceAt(i) != -1:
      grabbed.set(i); sel.set(i)
    elif grabbed.get >= 0:
      movePiece(grabbed.get, i); grabbed.set(-1); sel.set(-1)
  onPointerMove:
    if grabbed.get >= 0:
      hoverSq.set(squareAt(pointerPos()))    # for the ghost/preview
  onPointerUp:
    grabbed.set(-1)
```

**Arrow keys** — on the **root**, with `handled()` so the app takes the arrows
rather than letting a focused field scroll:

```nim
app("Chess"):
  onKey:
    let k = lastKey()
    ## KeyPress is an object, so it cannot go in a `case` — use if/elif with the
    ## `==` overload (or switch on k.code, an int32).
    if grabbed.get >= 0: return              # a drag owns the board
    if k == keyLeft:  cursor.set(step(cursor.get, -1, 0)); handled()
    elif k == keyRight: cursor.set(step(cursor.get, +1, 0)); handled()
    elif k == keyUp:    cursor.set(step(cursor.get,  0, -1)); handled()
    elif k == keyDown:  cursor.set(step(cursor.get,  0, +1)); handled()
    elif k == keyEnter:
      if sel.get < 0 and pieceAt(cursor.get) != -1: sel.set(cursor.get)
      elif sel.get >= 0 and sel.get != cursor.get:
        movePiece(sel.get, cursor.get); sel.set(-1)
      handled()
    elif k == keyEscape: sel.set(-1); handled()
```

The four things that make this port correct, and each is a measured Yantra fact:

1. `pointerPos()` is **node-local px** — no `getBoundingClientRect()` maths.
2. The arrow/Enter handler is on the **root**, because the ancestor walk never
   descends to the canvas (`ENGINE-ISSUES.md:208-241`).
3. `handled()` stops the built-in action, so the arrows do not also scroll a
   field or the window.
4. Every state change bumps something the `draw` expression reads, which is what
   makes the canvas repaint. Chapter 10 §6 explains the loop.

---

## 11. A complete example

A canvas that responds to pointer drag and to the arrow keys. Compile-verified
with Nim 2.2.10 against `sdk/` using the headless harness from
`sdk/tests/t_style.nim` (all `y_node_*` / `y_input` / `y_node_size` /
`y_key` / `yantra_get_dt` imports stubbed): it builds 5 nodes and runs clean.

That check caught two real mistakes worth remembering:
`focused: border = …` is a `Y013` compile error, and **`KeyPress` cannot be used
in a `case`** (`selector must be of an ordinal type, float or string`) — write
`if k == keyLeft: … elif …`.

```nim
## Drag a dot around a canvas with the pointer; nudge it with the arrow keys.

const CW = 400
const CH = 200

let dotX = state 100'f32
let dotY = state 100'f32
let dragging = state false
let ticks = state 0

proc clampf(v, lo, hi: float32): float32 = (if v < lo: lo elif v > hi: hi else: v)

app("Drag + Keys", width = 460, height = 300, fill = 0x101725):
  ## Keys live on the APP ROOT: the key walk goes focus -> ancestors -> root and
  ## never descends, so a canvas-level onKey would never be reached.
  onKey:
    let k = lastKey()
    if k == keyLeft:  dotX.set(clampf(dotX.get - 12, 0, CW - 1)); handled()
    elif k == keyRight: dotX.set(clampf(dotX.get + 12, 0, CW - 1)); handled()
    elif k == keyUp:    dotY.set(clampf(dotY.get - 12, 0, CH - 1)); handled()
    elif k == keyDown:  dotY.set(clampf(dotY.get + 12, 0, CH - 1)); handled()
    elif k == keyEscape: dragging.set(false); handled()
    else: discard

  column(gap = 10.px, pad = 16.px):

    text @hud("{int(dotX.get)}, {int(dotY.get)} · moves {ticks.get}",
          size = 14, color = 0x8CA0C0)

    ## `draw` is re-read every paint. Because the expression reads state, the
    ## effect re-runs whenever that state changes and the canvas repaints.
    canvas @field(width = CW.px, height = CH.px,
                  draw = Draw()
                            .rect(0, 0, CW, CH, 0xFF162033'u32)
                            .line(0, dotY.get, CW, dotY.get, 0xFF24354Fu32, 1'f32)
                            .line(dotX.get, 0, dotX.get, CH, 0xFF24354Fu32, 1'f32)
                            .circle(dotX.get, dotY.get, 10, 0xFFFFB86B'u32)
                            .cmds):

      ## pointerPos() is in THIS canvas's own pixels — no rect maths needed.
      onPointerDown:
        let (x, y) = pointerPos()
        dragging.set(true)
        dotX.set(clampf(x, 0, CW - 1)); dotY.set(clampf(y, 0, CH - 1))
        ticks.set(ticks.get + 1)

      ## PointerMove keeps arriving here while the node is pressed, so this is
      ## the whole drag loop — no capture, no DragStart.
      onPointerMove:
        if dragging.get:
          let (x, y) = pointerPos()
          dotX.set(clampf(x, 0, CW - 1)); dotY.set(clampf(y, 0, CH - 1))
          ticks.set(ticks.get + 1)

      onPointerUp:
        dragging.set(false)

    button @reset("Reset", fill = 0x24354F, radius = 8.px):
      onClick:
        dotX.set(100); dotY.set(100); dragging.set(false)
```

### Verified limits checklist for a port

- `pointerPos()` is node-local px, `pointerPage()` is page px, and both are only
  fresh **inside** a pointer handler.
- Layout transforms (`scale`, `rotate`) are **not** applied to pointer
  coordinates; do the inverse transform yourself.
- A canvas that scrolls its own content (`pCanvasWidth` / `pCanvasHeight`, set
  imperatively) needs its scroll offset added by hand (`yNodeSize(id, 2)` for y,
  `yNodeSize(id, 9)` for x).
- Key handlers on a child node are unreachable — root only.
- No `keyUp` event: use `keyHeld` in `onFrame:`, or debounce `onKey:` yourself,
  because auto-repeat re-fires `onKey:` indistinguishably.
- No `tabIndex`, no `maxLength`, no `pattern`, no `element.focus()` natively.
- In-app drag payloads are empty natively: use your own `state`.
- `pointerIsLocked()` is always false — track your own lock state.
