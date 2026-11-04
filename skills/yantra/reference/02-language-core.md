# 02 — The core language

Every Yantra app is a Nim file. It has no `main` requirement of its own: the SDK
gives you one shape — build a UI tree and hand it to the host — and two ways to
write it.

Both styles compile to the *same* calls on the same SDK. The declarative style is
a **compile-time rewrite** into the imperative one; there is no virtual DOM, no
diffing runtime, no second implementation. From `sdk/ui/dsl.nim:1`:

> Everything here is a compile-time rewrite into plain calls on the SDK: node
> constructors, setters, `createEffect`, and the two control-flow procs in
> ui/control.nim.

---

## 1. The two authoring styles

### 1a. Imperative / procedural

You call node constructors and hold the handles yourself. Each constructor takes
the **parent node as its first argument** and returns the new `Node`
(`sdk/ui/widgets.nim`):

```nim
proc column*(parent: Node): Node = make(nkColumn, parent)
proc row*(parent: Node): Node = make(nkRow, parent)
proc text*(parent: Node, content: string): Node =
proc button*(parent: Node, label: string): Node =
proc input*(parent: Node, hintText: string = ""): Node =
```

The whole app body goes inside `yantraRun`, which turns it into the exported
entry point the host calls (`sdk/core/runtime.nim:232`):

```nim
macro yantraRun*(body: untyped): untyped =
  result = quote do:
    proc yantra_main*() {.exportc: "yantra_main".} = `body`
```

`examples/hello.nim` is a complete app in this style — 35 lines, copied verbatim:

```nim
yantraRun:
  let win = window("Hello, Yantra", 800, 600)
  win.color(0x1e, 0x1e, 0x2e)

  let col = column(win)

  let title = text(col, "Hello, Yantra")
  title.fontSize(32)
  title.color(0xff, 0xff, 0xff)

  let subtitle = text(col, "This UI was built inside a WebAssembly sandbox.")
  subtitle.fontSize(16)
  subtitle.color(0x9a, 0x9a, 0xb0)

  var clicks = 0
  let btn = button(col, "Click me")

  btn.onClick(proc() =
    clicks += 1
    title.setText("Clicked " & $clicks & " time(s)")
    log("button clicked: " & $clicks)
  )

  let img = image(col, "logo.png")
  img.width(64)
  img.height(64)

  let nameField = input(col, "Your name")
  nameField.fontSize(14)
```

### 1b. The declarative `app(...)` macro and `{...}` blocks

You write a *tree* with indentation and named props. `examples/counter.nim`,
copied verbatim, complete:

```nim
app "Counter":
  var clicks = state 0

  column(gap = 12, pad = 24):
    text "Clicked {clicks} times", size = 32
    button "Click me":
      onClick: clicks += 1
```

Note what vanished: no parent plumbing, no handles, no `let`. The macro reads the
indentation as nesting — `column` is the parent of `text` and `button` — and
rewrites each line into the imperative call above.

### Which to prefer, and when

| | Imperative | Declarative (`app` + blocks) |
|---|---|---|
| **Prefer it for** | Logic that is really code: procs with branches, loops, timers, workers, computed graphs | Anything that is really a *view*: a screen, a card, a row, a form |
| **Reactivity** | You write `createEffect` yourself | Automatic — see §4. Any non-literal prop/text becomes an effect |
| **Handles** | You have every `Node` handle | Hidden, unless you name one with `@name` |
| **Control flow** | Manual add/remove of children | `if` / `case` / keyed `for` rebuild and dispose for you |
| **Reading a node** | `node.getStr(pValue)`, `yNodeSize(...)` | Rarely needed — signals cover it |

**Rule of thumb:** default to the declarative style for the UI, and drop to
imperative *inside a `{.component.}` proc* when the layout needs to be computed
rather than described. The two styles mix freely — a component can call
`column(win)` directly.

---

## 2. The `app(...)` macro

### Exact signature (`sdk/ui/dsl.nim:673`)

```nim
macro app*(title: string; args: varargs[untyped]): untyped =
  ## `app "Title", width = 480, height = 720:` then the UI block.
  var props: seq[NimNode] = @[]
  var body: NimNode = newStmtList()
  for a in args:
    if a.kind == nnkExprEqExpr: props.add(a)
    elif a.kind == nnkStmtList: body = a
  result = expandAppAst(title, body, props)
```

So it takes:

1. **A title string** — mandatory, first positional.
2. **`name = value` props** — any number, applied to the *window node*.
3. **One block** — the trailing `:` body.

Both spellings work; the parser distinguishes `nnkExprEqExpr` from
`nnkStmtList` automatically:

```nim
app "Counter":
  ...                                     # form 1: bare title + block

app("Todos", width = 440, height = 620, fill = 0x0B0B10):
  ...                                     # form 2: parenthesised (examples/todo.nim)
```

### What it expands to (`expandAppAst`, `dsl.nim:653`)

```nim
inner.add(newLetStmt(winSym, newCall(ident"window", title)))
for p in winProps: inner.add(buildPropSetter(winSym, "Window", p))
inner.add(transformUiBlock(body, winSym))
result = newCall(ident"yantraRun", inner)
```

Read that as: create `window(title)` → apply each window prop → transform the
block with that window node as the parent → wrap the whole thing in
`yantraRun`. So `app` is `yantraRun` + `window` + a parent-aware block, and
nothing more.

### Capabilities: `needs = ...`

One prop is not a window prop. `needs` is hoisted out of the window props and
turned into a `needs(...)` call *before* the window is created (`dsl.nim:658`):

```nim
if p.kind == nnkExprEqExpr and ($p[0]).toLowerAscii() == "needs":
  ...
  if val.kind == nnkBracket:
    var call = newCall(ident"needs")
    for elem in val: call.add elem
    inner.add call
  else:
    inner.add newCall(ident"needs", val)
```

`sdk/core/runtime.nim:35` declares the four capabilities, and the engine refuses
any call the manifest did not grant:

```nim
const
  files* = "files"
  network* = "network"
  storage* = "storage"
  notifications* = "notifications"

proc needs*(caps: varargs[string]) =
```

Usage inside an app: `app("x", needs = ["files", "network"]):` or
`needs = "files"`. `yantra_manifest_needs` is what the host reads before it even
loads the app.

### Components: `{.component.}` and `slot()`

A UI block can be lifted into an ordinary proc (`dsl.nim:682`):

```nim
macro component*(p: untyped): untyped =
  ## `proc Card(title: string) {.component.} = <UI block>`: an ordinary proc whose
  ## body is a UI block. It gets a hidden first parameter, the parent node, which
  ## the caller's UI block supplies [S-CMP-1].
```

Two hidden parameters are injected: `yParent: Node` and
`yChildren: proc (p: Node) {.closure} = nil`. At the call site
(`transformUiStmt`, `dsl.nim:557`), a capitalised name inside a UI block is a
component call, the parent is prepended, and the caller's trailing block is
passed as `yChildren`:

```nim
if name[0].isUpperAscii():
  # A component: `Card("x", 3)` -> `Card(parent, "x", 3)` [S-CMP-1]
```

Inside the component, `slot` places the caller's block (`dsl.nim:628`):

```nim
if low == "slot" and stmt.len == 1:
  # the caller's block, placed here [S-CMP-4]
  return newIfStmt((infix(ident"yChildren", "!=", newNilLit()), newCall(ident"yChildren", parentSym)))
```

Real example, `examples/todo.nim:44`:

```nim
proc TodoRow(todo: Todo) {.component.} =
  row(gap = 10, pad = 10, fill = 0x17171D, radius = 10):
    checkbox(checked = todo.done, label = todo.title, grow = 1):
      onChange: toggle(todo.id)
    button "✕", fill = 0x17171D, textColor = 0x8C8C96:
      onClick: remove(todo.id)
```

used as `TodoRow(t)` inside the loop — note it takes **no** parent argument.

### Other block-level forms

Recognised inside a UI block, all rewritten by `transformUiStmt`:

| Form | Expands to | Source |
|---|---|---|
| `hover:` / `pressed:` / `focused:` | props applied while the state holds | `dsl.nim:223` |
| `sized w, h:` | `newState(0'f32)` ×2 + `trackSize(...)` — container queries | `dsl.nim:579` |
| `scrolled y:` | `newState(0'f32)` + `trackScroll(...)` | `dsl.nim:590` |
| `lazy m in xs, 44:` | a scrolling column that builds only the visible rows | `dsl.nim:598` |
| `empty:` (after a `for`) | the empty state, disposed when the list fills | `dsl.nim:643` |
| `style(...)` / `use = …` | reusable prop bundle | `dsl.nim:710` |

`style(...)` builds a `Style` object out of non-reactive prop setters
(`dsl.nim:717`); `use = …` applies it via `applyStyle` (`sdk/ui/style.nim:54`).
Call-site props written *after* `use` win.

---

## 3. Node constructors

Two tables: the **imperative** constructors you call directly, and the
**declarative** keywords the `app` macro rewrites into those constructors (and
into `make(nk…, parent)` for the ones with no imperative twin).

### 3a. Imperative — exact signatures from source

`sdk/ui/widgets.nim` in full:

```nim
proc setText*(node: Node, value: string) = node.set(pText, value)
proc width*(node: Node, value: int32) = node.set(pWidth, value)
proc height*(node: Node, value: int32) = node.set(pHeight, value)

proc window*(title: string, w: int32 = 800, h: int32 = 600): Node =
  result = make(nkWindow); result.setText(title); result.width(w); result.height(h)

proc column*(parent: Node): Node = make(nkColumn, parent)
proc row*(parent: Node): Node = make(nkRow, parent)
proc text*(parent: Node, content: string): Node =
  result = make(nkText, parent); result.setText(content)
proc button*(parent: Node, label: string): Node =
  result = make(nkButton, parent); result.setText(label)
proc image*(parent: Node, src: string): Node =
  result = make(nkImage, parent); result.setText(src); result.set(pSource, src)
proc input*(parent: Node, hintText: string = ""): Node =
  result = make(nkInput, parent); result.setText(hintText)
proc panel*(parent: Node, w: int32 = 0, h: int32 = 0): Node =
  result = make(nkPanel, parent)
  if w > 0: result.width(w)
  if h > 0: result.height(h)
proc divider*(parent: Node, w: int32 = 0): Node {.discardable.} = panel(parent, w, 1)
proc spacer*(parent: Node, h: int32 = 8): Node {.discardable.} =
  result = make(nkSpacer, parent)
  if h > 0: result.height(h)
```

`sdk/yantra.nim` — forms, layout, media, overlays, 3D:

```nim
proc textArea*(parent: Node, placeholder: string = ""): Node     # multi-line text input
proc checkbox*(parent: Node, label: string = ""): Node            # checkbox input
proc radio*(parent: Node, group: string, label: string = ""): Node
proc select*(parent: Node, options: string = "[]"): Node          # options = JSON array
proc slider*(parent: Node, minVal: float32 = 0, maxVal: float32 = 100): Node
proc progress*(parent: Node, value: float32 = 0, maxVal: float32 = 100): Node
proc switch*(parent: Node, label: string = ""): Node
proc datePicker*(parent: Node): Node
proc colorPicker*(parent: Node): Node

proc grid*(parent: Node, cols: string = "1fr 1fr"): Node         # grid-template-columns
proc flex*(parent: Node, direction: string = "row"): Node        # row|row-reverse|column|column-reverse
proc stack*(parent: Node): Node                                   # overlay children
proc scrollArea*(parent: Node): Node
proc tabs*(parent: Node): Node
proc tabPanel*(parent: Node, label: string): Node

proc table*(parent: Node): Node
proc listView*(parent: Node): Node
proc treeView*(parent: Node): Node
proc chart*(parent: Node, chartType: string = "line"): Node       # line|bar|pie|scatter

proc video*(parent: Node, src: string = ""): Node
proc audio*(parent: Node, src: string = ""): Node
proc canvas*(parent: Node, w: int32 = 300, h: int32 = 150): Node

proc modal*(parent: Node, title: string = ""): Node
proc drawer*(parent: Node, side: string = "right"): Node          # left|right|top|bottom
proc popover*(parent: Node): Node
proc tooltip*(parent: Node, content: string): Node
proc menu*(parent: Node): Node
proc contextMenu*(parent: Node): Node

proc scene3d*(parent: Node, w: int32 = 0, h: int32 = 0): Node
proc model*(parent: Node, meshy: string = "#Cube"): Node          # param is `meshy`, not `source`
proc camera*(parent: Node): Node
proc light*(parent: Node): Node
```

The universal fallback is `make` (`sdk/core/runtime.nim:132`):

```nim
proc make*(kind: NodeKind, parent: Node = Node(id: NodeId(-1))): Node =
```

`Node` is a one-field object (`runtime.nim:9`) — `Node(id*: NodeId)` — so a
handle is just a number.

### 3b. Declarative keywords — the DSL's full `nodeKinds` list

`dsl.nim:461`, verbatim:

```nim
const nodeKinds = ["column", "row", "panel", "group", "text", "button", "input", "textarea", "checkbox", "spacer", "appview",
                   "stack", "path", "icon", "video", "page", "slide", "image", "grid", "rich", "model",
                   "modal", "drawer", "popover", "menu", "contextmenu", "tooltip",
                   "scene3d", "camera", "light", "mesh", "box", "sphere", "plane", "cylinder", "synth", "canvas", "particles"]
```

What each takes, from `nodeStmt` (`dsl.nim:293`) and the source comments:

| Keyword | Node kind | Positional arg | Purpose |
|---|---|---|---|
| `column(p)` | Column | — | vertical stack of children |
| `row(p)` | Row | — | horizontal stack |
| `panel(p)` | Panel | — | a plain box |
| `group(p)` | Group | — | layout-transparent container (`control.nim:16`) |
| `text "…"` | Text | the text | one run of text; interpolated if it has `{…}` |
| `button "…"` | Button | the label | a button |
| `input(draft)` | Input | a `Signal[string]` → two-way bound | one-line text field |
| `textArea notes` | TextArea | a `Signal[string]` | many-line text field |
| `checkbox` | Checkbox | — | checkbox (`checked =`, `label =`) |
| `spacer` | Spacer | — | elastic gap; sets `pFlexGrow = 1` |
| `appview` | AppView | — | another app sandboxed in this box |
| `stack` | Stack | — | children overlap, each placed by its own top/left/… |
| `path` | Path | — | a raw path |
| `icon "search"` | Path | the icon name | an icon from the standard set; sets `pStrokeWidth = 1.8` |
| `video "clip.mp4"` | Video | the file name | video from the app's own folder |
| `page` | Page | — | one page of a PDF |
| `slide` | Page | — | a 1280×720 deck slide (width/height preset) |
| `image "logo.png"` | Image | the source path | a picture |
| `grid "1fr 2fr 200"` | Grid | the columns string | px / `fr` / `auto` columns; `span = 2` |
| `rich "…**bold**…"` | Text | the markup | inline styled text: `**bold**`, `[a link](url)` |
| `model "fox.glb"` | Model | the file name | a glTF 2.0 model, lit and framed |
| `modal` / `drawer` / `popover` / `menu` / `contextmenu` | Modal… | — | overlays above the window, not in layout |
| `tooltip "Copy link"` | Tooltip | the text | shown after the pointer rests on the node |
| `scene3d` / `camera` / `light` | Scene3D… | — | native 3D (Filament) |
| `box`/`sphere`/`plane`/`cylinder`/`mesh` | Mesh | — | 3D objects inside a `scene3d` |
| `synth` | Synth | — | a sound the engine makes; not laid out |
| `canvas` | Canvas | — | 2D drawing (paint.nim's `Draw`) |
| `particles` | Particles | — | sprites the engine emits and moves |

Notes straight from the source comments:

- Overlays: *"a modal is centred over a dimmed window, a drawer docks to an edge,
  a popover or menu opens by the node it is inside, a context menu at a right click
  on that node. `open = sig` shows it (absent: open while it exists); Escape or a
  click outside fires `onDismiss`"* (`dsl.nim:311`).
- 3D: *"`scene3d(sky = 0x87CEEB, fog = 0.02):` is a view into a 3D world; inside
  it `box`/`sphere`/`plane`/`cylinder`/`mesh(geometry = buf)` are objects
  (posX.., rotY.., sizeX.., fill, metal, rough, glow, instances = buf), `light`
  and `camera` light and see it, and `model "fox.glb"` is an object too. Filament
  draws it; the objects are not laid out."* (`dsl.nim:338`)
- Grid: *"`grid "1fr 2fr 200", spacing = 12:` — columns of fixed px, shares (`fr`)
  or `auto`; children fill them in order, row after row (`span = 2` takes two
  columns)"* (`dsl.nim:419`).

Two important DSL-only behaviours:

**Interpolation** (`dsl.nim:262`, `textLike`) — a literal text argument is set
once; a text with `{…}` in it becomes an effect that rewrites itself:

```nim
if mainArg.kind in {nnkStrLit, nnkTripleStrLit}:
  let (exprAst, isReactive) = parseInterpolatedExpr(mainArg.strVal, mainArg)
  if isReactive:
    result.add(newLetStmt(nodeSym, newCall(ident(ctor), parentSym, newLit(""))))
    result.add(effect(newCall(newDotExpr(nodeSym, ident"setText"), exprAst)))
```

A non-literal first argument (e.g. a signal) is `$`-wrapped inside an effect.

**Named handles** — `takeHandle` (`dsl.nim:276`) pulls `text @headline "Hi"` or
`panel(@card, …)` out of the statement and sets it as `pName`, *"a stable name
for code, tests, tools and AI edits"*.

Every node also gets `pSite` set to its source position in dev builds
(`dsl.nim:448`), so hot reload and inspectors can jump from a pixel to its line.

### 3c. Imperative-only constructors

Not in `nodeKinds` (so not available as DSL keywords, though `divider` is
reachable as `panel(parent, w, 1)`):

- `divider(parent, w = 0)`
- `table`, `listView`, `treeView`, `chart`, `tabs`, `tabPanel`, `flex`
- `scrollArea`, `audio`, `radio`, `slider`, `progress`, `switch`, `datePicker`,
  `colorPicker`

These are **not** usable as UI-block keywords. `transformUiStmt` checks
`low in nodeKinds` first, then falls through to
`else: error("unknown node kind " & name)` (`dsl.nim:440`). And a capitalised
name is treated as a *component* call, which prepends `yParent` — so writing
`Radio(p, "g")` in a block would expand to `Radio(yParent, p, "g")`, not what
you meant.

A `{.component.}` proc body is *also* a UI block, so the same rule applies
there. To reach these kinds from inside one, use the escape hatch the DSL itself
uses — `make` with the kind enum:

```nim
make(nkCheckbox, yParent)
```

> **RESOLVED 2026-10-03.** This used to carry an open verification marker asking
> you to confirm the spelling. Confirmed: the enum is
> `NodeKind* {.size: sizeof(int32).} = enum` at `sdk/core/wire.nim:5`, and every
> kind is `nk<Name>` — `nkWindow = 0` (`sdk/core/wire.nim:6`) through
> `nkParticles = 47` (`sdk/core/wire.nim:53`). That file is **generated**
> (`sdk/core/wire.nim:1-2`: "GENERATED FILE. DO NOT EDIT. Edit
> `protocol/schema.nim` instead"), so the spellings come from
> `protocol/schema.nim`. `03-node-and-prop-reference.md` is the table to read;
> the source of truth for the spelling is `sdk/core/wire.nim`.

---

## 4. State & reactivity

`sdk/core/signals.nim` header, verbatim:

> Three ideas, as in docs/spec/core.md §5:
> * a `Signal` holds a value and knows which effects read it;
> * an `Effect` re-runs when a signal it read in its latest run changes. Before
>   every run it forgets its old dependencies and disposes what it created, so it
>   only ever depends on what it actually read last time [S-RX-5];
> * an `Owner` is a scope. Effects, child scopes and clean-ups belong to the
>   scope that was current when they were created.

### The type

```nim
type
  Signal*[T] = ref object of SignalBase
    value: T
```

### Creating — `state`

The template you use in apps (`signals.nim:198`):

```nim
template state*(initial: untyped): untyped =
  ## A signal holding `initial`. It keeps its value when the app is hot-reloaded.
  let s = newState(initial)
  when not defined(release):
    keepAcrossReloads(s, instantiationInfo(-1).filename, instantiationInfo(-1).line)
  s
```

and the raw constructor behind it (`signals.nim:181`):

```nim
proc newState*[T](initial: T): Signal[T] =
  Signal[T](value: initial, subscribers: newSeqOfCap[Effect](4))
```

Real usage, `examples/counter.nim` and `examples/todo.nim`:

```nim
var clicks = state 0
var todos = state(@[Todo(id: 1, title: "Write the pitch"), Todo(id: 2, title: "Record the demo")])
var draft = state("")
var filter = state("All")
```

`state` is a `varargs`-free template, so it works with any expression.

### Reading and writing

```nim
proc get*[T](s: Signal[T]): lent T =
  ## Reads and subscribes. Borrowed, not copied: reading a list of 100 000 items costs
  ## nothing (copy it with `var x = s.get` to change it).
  track(s)
  s.value

proc peek*[T](s: Signal[T]): lent T = s.value        ## reads WITHOUT subscribing

proc set*[T](s: Signal[T]; v: T) =
  if s.value == v: return
  s.value = v
  schedule(s.subscribers)

proc update*[T](s: Signal[T]; fn: proc(v: var T)) =
  ## Mutates in place and always notifies [S-RX-3].
  fn(s.value)
  schedule(s.subscribers)

proc `+=`*[T](s: Signal[T]; delta: T) = s.set(s.value + delta)
proc `-=`*[T](s: Signal[T]; delta: T) = s.set(s.value - delta)
```

The full write vocabulary:

```nim
clicks += 1          # the += operator
todos.update(proc(xs: var seq[Todo]) = xs.add Todo(id: nextId, title: title))
draft.set("")
filter.set(name)
```

Note `set` short-circuits on an unchanged value; `update` **always** notifies,
which is what you want for in-place mutation of a collection.

### The implicit unwrap (converter)

```nim
converter val*[T](s: Signal[T]): T =
  ## Implicit unwrap of a Signal[T] to its inner value T while tracking subscriptions [S-RX-1].
  s.get()
```

This is why `text "Clicked {clicks} times"` works without `.get`. Also:

```nim
proc `$`*[T](s: Signal[T]): string = $(s.get())
```

### `createEffect`

```nim
proc createEffect*(fn: proc()): Effect =
  ## Runs `fn` now and again whenever a signal it read changes. Belongs to the
  ## current scope, so disposing that scope stops it.
```

It runs **immediately**, then again on any change. Imperative example, from
`skills/yantra/examples/imperative_app.nim`:

```nim
let label = text(page, "Clicks: 0")
label.fontSize(28)

createEffect:
  label.setText("Clicks: " & $(count.get))

let add = button(row, "Click me")
add.width(120)
add.onClick(proc() = batch(proc() = count.set(count.get + 1)))
```

**You never write `createEffect` in the declarative style.** The macro emits one
for every non-literal prop or text (`dsl.nim:64`):

```nim
proc effect(stmt: NimNode): NimNode =
  newTree(nnkDiscardStmt, newCall(ident"createEffect", lambda(newStmtList(stmt))))

proc reactiveOrOnce(stmt: NimNode; value: NimNode): NimNode =
  if isLiteral(value): stmt else: effect(stmt)
```

`isLiteral` (`dsl.nim:52`) is the whole heuristic — int, float, char, string,
triple-string literals, plus `true`/`false`/`nil`, plus any identifier that looks
like a constant (`al…` with an uppercase third char):

```nim
proc isLiteral(n: NimNode): bool =
  case n.kind
  of nnkCharLit .. nnkFloat128Lit, nnkStrLit .. nnkTripleStrLit: true
  of nnkIdent, nnkSym: ($n) in ["true", "false", "nil"] or ($n).startsWith("al") and ($n).len > 2 and ($n)[2].isUpperAscii
  of nnkPrefix: n.len == 2 and isLiteral(n[1])
  else: false
```

`examples/todo.nim:52` shows the derived case — a prop whose value is a whole
`if` expression becomes one effect that re-runs when `filter` changes:

```nim
proc FilterTab(name: string) {.component.} =
  button name, fill = (if filter.get() == name: 0xFFB23E else: 0x17171D),
         textColor = (if filter.get() == name: 0x1A1206 else: 0xC9C9D2):
    onClick: filter.set(name)
```

### `batch`

```nim
proc batch*(fn: proc()) =
  inc batchDepth
  try:
    fn()
  finally:
    dec batchDepth
  if batchDepth == 0 and not flushing:
    flush()
```

Writes inside one `batch` produce exactly **one** re-render, not one per write.
The DSL applies it for free — every event handler is wrapped (`dsl.nim:253`):

```nim
proc eventHandler(nodeSym: NimNode; ev: string; body: NimNode): NimNode =
  ## node.on(evX, proc() = batch(proc() = body))
  let batched = newCall(ident"batch", lambda(body))
  newCall(newDotExpr(nodeSym, ident"on"), ident(ev), lambda(newStmtList(batched)))
```

Imperatively you must remember it yourself (see the `onClick` above).

### Derived signals

```nim
proc derived*[T](fn: proc(): T): Signal[T] =
  ## A value computed from other signals and kept up to date [S-RX-5].
  let s = Signal[T](subscribers: newSeqOfCap[Effect](4))
  discard createEffect(proc() = s.set(fn()))
  s

template derive*(body: untyped): untyped =
  ## `let total = derive: items.get.len * price.get` — `derived` without the proc (S11).
  derived(proc (): auto = body)
```

### Scopes and cleanup

```nim
proc newOwner*(parent: Owner = currentOwner): Owner
proc getOwner*(): Owner = currentOwner
proc disposeOwner*(o: Owner): Owner          ## children, then effects, then clean-ups, each in reverse creation order. Idempotent.
proc runWithOwner*(o: Owner; fn: proc())     ## runs fn with o as the current scope, outside any effect and untracked
proc onCleanup*(fn: proc())                  ## inside an effect: runs before its next run; otherwise: when the current scope is disposed
proc untrack*[T](fn: proc(): T): T          ## reads inside subscribe nothing
```

### Interpolation — `"{n} times"`

`parseInterpolatedExpr` (`dsl.nim:12`), the doc comment is the spec:

```nim
proc parseInterpolatedExpr*(s: string; info: NimNode): (NimNode, bool) =
  ## "Clicked {n} times" -> `"Clicked " & $(n) & " times"`, and whether it had any `{…}`.
```

It splits on `{…}`, parses each inner expression with `parseExpr`, wraps it in
`$`, and joins with `&`. It only goes reactive if something was actually
interpolated (`hasInterp`). Real examples, from the examples folder:

```nim
text "Clicked {clicks} times", size = 32                              # counter.nim:5
text "{left()} left of {todos.get().len}", size = 14, color = 0x8C8C96 # todo.nim:59
```

Note the second: an arbitrary call is fine inside `{…}`, so computed values read
their own signals and stay current.

**Limits.** The interpolation parser is hand-rolled over the *string*, not the
AST, so anything that contains `}` inside the braces confuses it, and nested
braces are not supported. `interpolateStr` (`dsl.nim:44`) is the runtime twin,
replacing `{name}` from an `openArray[(string, string)]`.

### Reactive `if` / `case`

Both expand to `showWhen` (`dsl.nim:491`, `dsl.nim:511`):

```nim
proc showWhen*(parent: Node; branchOf: proc(): int; builds: seq[proc(parent: Node)]) =
  ## `if`/`elif`/`else`: `branchOf` returns the index of the branch to show
  ## (-1 = none). Only a change of branch rebuilds; the branch's own effects keep
  ## it up to date otherwise [S-CTL-1].
```

The branch selector is a real `if` expression whose result is the branch index,
so the conditions are ordinary Nim. `examples/todo.nim:74`:

```nim
if todos.get().len > left():
  button "Clear done", fill = 0x0B0B10, textColor = 0x8C8C96:
    onClick: clearDone()
```

**Every branch lives in its own `Owner` scope inside a `Group`** (`control.nim:21`):

```nim
proc buildScoped(outer: Owner; parent: Node; build: proc(parent: Node)): (Owner, Node) =
  ## Builds `build` into a fresh Group under `parent`, inside a fresh scope under
  ## `outer`. Disposing the scope removes the Group and everything in it.
```

So switching branches disposes the old scope: its effects stop and its nodes are
removed from the engine, *with everything below them*. That is the mechanism
behind "no leaks in a loop".

`case` works identically and gets its own transform (`dsl.nim:511`).

### Keyed `for`

```nim
proc keyedList*[T](parent: Node; source: proc(): seq[T]; keyOf: proc(x: T): string;
                   build: proc(parent: Node; item: T); empty: proc(parent: Node) = nil) =
  ## Keyed `for`: one scope per key [S-CTL-2, S-NODE-2].
  ##   * a key that stays with the same value keeps its nodes and state untouched;
  ##   * a key whose value changed is rebuilt in place (same position);
  ##   * a new key is built; a key that goes is disposed, removing its nodes;
  ##   * a move reorders the existing nodes instead of rebuilding them.
  ## Duplicate keys keep only the first occurrence [S-CTL-3]. `empty` is shown
  ## while the list is empty (the `empty:` block after the loop) [S-CTL-5].
```

**Syntax** (`forStmt`, `dsl.nim:466`): one loop variable, optional `.keyed(...)`:

```nim
for x in items:              # the item itself is the key
for x in items.keyed(x.id):  # key by an id
```

An `empty:` block immediately after the loop is consumed as the empty state
(`dsl.nim:643`). Real example, `examples/todo.nim:70`:

```nim
column(gap = 8):
  for t in shown().keyed(t.id):
    TodoRow(t)
  empty:
    text "Nothing here yet.", color = 0x55555E
```

`shown()` is an ordinary proc reading signals (`todo.nim:36`) — that is what
makes the loop source reactive: `keyedList` reads it inside `createEffect`.

What iterates (`control.nim:120`):

```nim
proc listValue*[T](s: Signal[seq[T]]): seq[T] = s.get()   ## a list signal is read (and so tracked)...
proc listValue*[T](s: seq[T]): seq[T] = s                  ## ...a plain list is used as it is.
proc listValue*[I, T](a: array[I, T]): seq[T] = @a        ## ...and a fixed array becomes a list.
```

### Bound inputs

`input draft` is a **two-way** binding to a `Signal[string]` (`dsl.nim:372`):

```nim
# `input draft`: two-way binding to a Signal[string] [S-CMP-3]
let sig = stmt[1]
result.add(effect(newCall(newDotExpr(nodeSym, ident"set"), ident"pValue",
                          newCall(ident"get", sig))))
result.add(newCall(newDotExpr(nodeSym, ident"on"), ident"evInput",
  lambda(newStmtList(newCall(ident"set", sig,
    newCall(newDotExpr(nodeSym, ident"getStr"), ident"pValue"))))))
```

Real usage, `examples/todo.nim:61`:

```nim
input(draft, placeholder = "What needs doing?", grow = 1, fill = 0x17171D, radius = 10):
  onSubmit: add()
```

Signal → widget in an effect; widget → signal on `evInput`. The `onSubmit:`
coexists — `addHandler` keeps a list per (node, event), so *"an `input` bound to
a signal can also have its own `onInput:`"* (`runtime.nim:176`).

`textArea notes` binds the same way. `checkbox` is **not** auto-bound — it takes
`checked =` as a prop and you wire `onChange:` yourself (`todo.nim:46`).

### Container queries — signals fed by the engine

Two more signal sources, both imperative (`sdk/yantra.nim`):

```nim
proc trackSize*(node: Node; w, h: Signal[float32])
  ## Keeps `w` and `h` at the node's laid-out size (px): the engine sends Resize when it
  ## changes, before painting. `sized w, h:` in the DSL uses it [S-LAY-2].
proc trackScroll*(node: Node; y: Signal[float32])
  ## Keeps `y` at the node's scroll offset (px): the engine sends Scroll when it changes.
proc trackMedia*(node: Node; time, duration: Signal[float32])
```

In the DSL these become `sized w, h:` and `scrolled y:` (`dsl.nim:579`, `590`),
which allocate the signals for you:

```nim
sized w, h:
  if w.get() < 640: ...
```

---

## 5. Events

### The declarative table — all 16, verbatim

`dsl.nim:70`:

```nim
const eventNames = [("onclick", "evClick"), ("onchange", "evChange"), ("oninput", "evInput"),
                    ("onsubmit", "evSubmit"), ("onfocus", "evFocus"), ("onblur", "evBlur"),
                    ("ondismiss", "evDismiss"), ("oncontextmenu", "evContextMenu"), ("onkey", "evKey"),
                    ("ondragstart", "evDragStart"), ("ondragover", "evDragOver"), ("ondrop", "evDrop"),
                    ("onframe", "evFrame"), ("onpointerdown", "evPointerDown"),
                    ("onpointermove", "evPointerMove"), ("onpointerup", "evPointerUp")]
```

| Block keyword | Event enum | Wire id (`wire.nim`) |
|---|---|---|
| `onClick:` | `evClick` | 0 |
| `onChange:` | `evChange` | 1 |
| `onInput:` | `evInput` | 3 |
| `onSubmit:` | `evSubmit` | 2 |
| `onFocus:` | `evFocus` | 4 |
| `onBlur:` | `evBlur` | 5 |
| `onDismiss:` | `evDismiss` | 14 |
| `onContextMenu:` | `evContextMenu` | 13 |
| `onKey:` | `evKey` | 15 |
| `onDragStart:` | `evDragStart` | 30 |
| `onDragOver:` | `evDragOver` | 31 |
| `onDrop:` | `evDrop` | 32 |
| `onFrame:` | `evFrame` | 33 |
| `onPointerDown:` | `evPointerDown` | 20 |
| `onPointerMove:` | `evPointerMove` | 21 |
| `onPointerUp:` | `evPointerUp` | 22 |

**Case is irrelevant.** Lookup lowercases the source name
(`dsl.nim:78`):

```nim
proc eventOf(name: string): string =
  for (k, v) in eventNames:
    if k == name.toLowerAscii(): return v
  ""
```

So `onClick:`, `onclick:` and `ONCLICK:` are the same block.

**Syntax.** It is a *block*, not a lambda — `onClick: clicks += 1`, with no
`proc()` and no `=`. The body becomes `node.on(evX, proc() = batch(proc() = body))`.

**An event attaches to the node it is written inside.** In
`examples/todo.nim:46-49`, the `onChange:` belongs to the `checkbox`, the
`onClick:` to the button — the child block, not the enclosing `row`.

### The full Event enum

`Event* {.size: sizeof(int32).} = enum` (`wire.nim:322`), all 34 values:

```nim
evClick = 0        evChange = 1       evSubmit = 2        evInput = 3
evFocus = 4        evBlur = 5         evScroll = 6        evTabChange = 7
evSelectionChange = 8                 evMediaEnd = 9      evMediaError = 10
evCanvasDraw = 11  evResize = 12      evContextMenu = 13  evDismiss = 14
evKey = 15         evTimeUpdate = 16  evMediaReady = 17   evBlockSplit = 18
evBlockMerge = 19  evPointerDown = 20 evPointerMove = 21  evPointerUp = 22
evLinkClick = 23   evCommand = 24     evMenuCommand = 25  evSystemTheme = 26
evDeepLink = 27    evSpellMenu = 28   evCallSignal = 29   evDragStart = 30
evDragOver = 31    evDrop = 32        evFrame = 33
```

The 18 without a block keyword are reachable imperatively via `on(node, ev, fn)`
or a named helper — see below.

### Imperative handlers — exact signatures

The generic form (`sdk/yantra.nim:384`):

```nim
proc on*(node: Node, event: Event, handler: proc()) =
  node.addHandler(event, handler)
```

`sdk/core/runtime.nim`, exact:

```nim
proc addHandler*(node: Node; event: Event; handler: proc())
proc clickable*(node: Node, handler: proc()) = node.addHandler(evClick, handler)
proc onClick*(node: Node, handler: proc()) = node.addHandler(evClick, handler)
proc onChange*(node: Node, handler: proc()) = node.addHandler(evChange, handler)
proc onDragStart*(node: Node, handler: proc()) = node.addHandler(evDragStart, handler)
proc onDragOver*(node: Node, handler: proc()) = node.addHandler(evDragOver, handler)
proc onDrop*(node: Node, handler: proc()) = node.addHandler(evDrop, handler)
```

`sdk/yantra.nim`, exact:

```nim
proc onInput*(node: Node, handler: proc()) = node.on(evInput, handler)
proc onFocus*(node: Node, handler: proc()) = node.on(evFocus, handler)
proc onBlur*(node: Node, handler: proc()) = node.on(evBlur, handler)
proc onScroll*(node: Node, handler: proc()) = node.on(evScroll, handler)
proc onTabChange*(node: Node, handler: proc()) = node.on(evTabChange, handler)
proc onSelectionChange*(node: Node, handler: proc()) = node.on(evSelectionChange, handler)
proc onMediaEnd*(node: Node, handler: proc()) = node.on(evMediaEnd, handler)
proc onMediaError*(node: Node, handler: proc()) = node.on(evMediaError, handler)
proc onCanvasDraw*(node: Node, handler: proc()) = node.on(evCanvasDraw, handler)
proc onMediaReady*(node: Node, handler: proc()) = node.on(evMediaReady, handler)
proc onTimeUpdate*(node: Node, handler: proc()) = node.on(evTimeUpdate, handler)
```

`onDrop` is **overloaded** — the `runtime.nim` one takes `proc()`, the
`runtime.nim:222` one takes the dropped file:

```nim
type DroppedFile* = object
  name*: string
  data*: string

proc droppedFile*(): DroppedFile = DroppedFile(name: droppedName(), data: droppedData())
proc onDrop*(node: Node, handler: proc(f: DroppedFile)) =
  node.addHandler(evDrop, proc() = handler(droppedFile()))
```

Plus the drag source and the editor/OS helpers:

```nim
proc setDragData*(data: string)                 # runtime.nim:201
proc spellMenu*(): (string, seq[string])       # runtime.nim:308 — misspelling + suggestions
proc spellRange*(node: Node): (int, int)       # runtime.nim:316
proc menuCommand*(): int32                     # runtime.nim:297 — which item, in a MenuCommand handler
proc systemDark*(): bool                       # runtime.nim:298
proc accentRgb*(): int32                       # runtime.nim:299 — 0xRRGGBB
proc deepLinkUrl*(): string                    # runtime.nim:300 — in a DeepLink handler
proc mediaTime*(node: Node): float32           # yantra.nim:418
proc mediaDuration*(node: Node): float32       # yantra.nim:420
proc waveform*(node: Node): seq[float32]       # yantra.nim:429
```

### Multiple handlers, and the input reading idiom

```nim
proc addHandler*(node: Node; event: Event; handler: proc()) =
  ## Any number of handlers per node and event, run in the order they were added
  ## (an `input` bound to a signal can also have its own `onInput:`). The engine
  ## sees one handler per (node, event): a dispatcher over this list.
```

To read what the user typed (`runtime.nim:72`):

```nim
proc yCapture*(kind, op, name, nameLen: int32): int32 {.importc: "y_capture", cdecl.}
  ## Copies up to `cap` bytes of a string property into the app's memory at `buf`;
  ## returns the full length. How an app reads what the user typed.
```

and the public wrappers:

```nim
proc getStr*(node: Node, prop: Prop): string
```

```nim
btn.onClick(proc() =
  let q = input.getStr(pValue)
  log("user typed: " & q))
```

The input can also be edited and replaced as an undoable change
(`runtime.nim:304`):

```nim
proc replaceText*(node: Node; a, z: int; text: string) =
  ## Replaces bytes a ..< z of an input's value as an edit (undoable; the field fires Input).
```

---

## 6. Imperative setters

Every setter takes the `Node` first. The universal one is `set`, with four
overloads by value type (`sdk/core/runtime.nim:138-170`):

```nim
proc set*(node: Node, prop: Prop, value: string)
proc set*(node: Node, prop: Prop, value: float32)
proc set*(node: Node, prop: Prop, value: int32)
proc set*(node: Node, prop: Prop, value: bool)
```

Everything else is a thin, named wrapper over it.

### Box model & geometry

`sdk/yantra.nim`, exact signatures with their real doc comments:

```nim
proc fontSize*(node: Node, value: int32) = node.set(pFontSize, value)

proc spacing*(node: Node, value: int32) =
  ## Gap between the children of a Column or Row. Previously this was hardcoded
  ## to 10 in the renderer, so every gap on a page was identical.
  node.set(pSpacing, value)

proc padding*(node: Node, all: int32)          ## Uniform inset, on any side. Sets all four.
proc padding*(node: Node, top, right, bottom, left: int32)

proc radius*(node: Node, value: int32)         ## Corner radius, in pixels.

proc border*(node: Node, width: int32, r, g, b: int32) =
  ## Border width plus its colour, in one call so a border is never half-set.
```

`padding` is genuinely overloaded — one arg for all four sides, four for
per-side.

### Appearance

```nim
proc color*(node: Node, r, g, b: int32) =
  ## 0xRRGGBB packed, so a colour is one integer across the boundary. For a
  ## Model this is the material's base colour.
  node.set(pColor, (r shl 16) or (g shl 8) or b)

proc x*(node: Node, value: float32) = node.set(pX, value)
proc y*(node: Node, value: float32) = node.set(pY, value)
proc visible*(node: Node, value: bool) = node.set(pVisible, value)
proc opacity*(node: Node, value: float32) = node.set(pOpacity, value)

type
  Align* {.size: sizeof(int32).} = enum
    alLeft   = 0
    alCenter = 1
    alRight  = 2

proc align*(node: Node, a: Align) =
  ## Text alignment. Was a dead property until the renderer started emitting it.
  node.set(pAlign, int32(a))
```

Size, from `sdk/ui/widgets.nim`:

```nim
proc width*(node: Node, value: int32) = node.set(pWidth, value)
proc height*(node: Node, value: int32) = node.set(pHeight, value)
proc setText*(node: Node, value: string) = node.set(pText, value)
```

Note `color` takes **three bytes**, while in the DSL you write one packed int
(`fill = 0x17171D`). `examples/hello.nim:15` uses `title.color(0xff, 0xff, 0xff)`;
`examples/todo.nim:45` uses `fill = 0x17171D`. Both spellings are correct for
their style.

### Style values — colours with alpha, gradients, shadows

`sdk/ui/style.nim`:

```nim
type
  Gradient* = object
    ## `fill = linear(0xFF7A2F, 0xFFD28A, 135)`: from, to, angle in degrees (90 = top to bottom).
    a*, b*: int
    angle*: float32
  Shadow* = object
    ## `shadow = shadow(y = 8, blur = 24, color = rgba(0x000000, 0.4))`
    x*, y*, blur*: float32
    color*: int
  Style* = object
    apply*: seq[proc (n: Node)]

proc rgba*(rgb: int; alpha: float): int
proc linear*(a, b: int; angle = 90.0): Gradient = Gradient(a: a, b: b, angle: float32(angle))
proc shadow*(x = 0.0; y = 6.0; blur = 18.0; color = rgba(0x000000, 0.35)): Shadow
proc setFill*(n: Node; c: int) = …          ## also switches any gradient off (pGradAngle = -1)
proc setFill*(n: Node; g: Gradient) = …
proc setShadow*(n: Node; s: Shadow) = …
proc applyStyle*(n: Node; s: Style) = for f in s.apply: f(n)
```

`rgba`'s alpha note is worth internalising: *"Alpha 0 is kept as 'almost clear'
so it stays distinguishable from a plain 0xRRGGBB (which means opaque)."*

### Forms & inputs

```nim
proc value*(node: Node, v: string)  = node.set(pValue, v)
proc value*(node: Node, v: float32) = node.set(pValue, v)
proc value*(node: Node, v: int32)   = node.set(pValue, v)
proc value*(node: Node, v: bool)    = node.set(pValue, v)

proc placeholder*(node: Node, v: string)
proc min*(node: Node, v: float32)   proc max*(node: Node, v: float32)
proc step*(node: Node, v: float32)
proc checked*(node: Node, v: bool)
proc options*(node: Node, v: string)
proc multiple*(node: Node, v: bool)  proc disabled*(node: Node, v: bool)
proc required*(node: Node, v: bool)  proc readOnly*(node: Node, v: bool)
proc maxLength*(node: Node, v: int32) proc pattern*(node: Node, v: string)
```

### Layout

```nim
proc flexGrow*(node: Node, v: float32)   proc flexShrink*(node: Node, v: float32)
proc flexBasis*(node: Node, v: float32)
proc gridCols*(node: Node, v: string)    proc gridRows*(node: Node, v: string)
proc gridGap*(node: Node, v: int32)      proc zIndex*(node: Node, v: int32)
proc overflow*(node: Node, v: string)    proc tabIndex*(node: Node, v: int32)
proc scrollX*(node: Node, v: int32)      proc scrollY*(node: Node, v: int32)
```

### Tabs, tables, media, canvas, overlays

```nim
proc columns*(node: Node, v: string)   proc rows*(node: Node, v: string)
proc selection*(node: Node, v: string) proc sortable*(node: Node, v: bool)
proc filterable*(node: Node, v: bool)

proc src*(node: Node, v: string)       proc poster*(node: Node, v: string)
proc autoplay*(node: Node, v: bool)    proc loop*(node: Node, v: bool)
proc muted*(node: Node, v: bool)       proc volume*(node: Node, v: float32)
proc playbackRate*(node: Node, v: float32)

proc canvasSize*(node: Node, w, h: int32)

proc open*(node: Node, v: bool)                    ## pModalOpen — shows/hides an overlay
proc title*(node: Node, v: string)                 ## pModalTitle
proc closeOnEsc*(node: Node, v: bool)
proc closeOnClickOutside*(node: Node, v: bool)
```

### 3D setters

```nim
proc source*(node: Node, value: string)   ## "#Cube" or an asset path, for a Model
proc scale*(node: Node, value: float32)   ## uniform — one number, not three
proc rotation*(node: Node, rx, ry, rz: float32)   ## Euler degrees
proc position*(node: Node, px, py, pz: float32)
proc metalness*(node: Node, value: float32)  ## 0 = dielectric, 1 = metal
proc roughness*(node: Node, value: float32)  ## 0 = mirror, 1 = fully diffuse
```

### Animations

```nim
proc animate*(node: Node; target: string; to: float32; duration: int32 = 300;
              easing: Easing = easeOutCubic; startVal: Option[float32] = none(float32);
              delay: int32 = 0; loop: int32 = 1; yoyo: bool = false;
              trigger: string = "mount") =
  ## Declarative animation. The engine translates this to a Qt Quick animation.
  ##
  ## target: property to animate ("opacity", "x", "y", "width", "height", "scale", "rotation")
  ## trigger: "mount" | "click" | "hover" | "focus" | "prop:<name>"

proc transition*(node: Node; kind: string; duration: int32 = 300; easing: Easing = easeOutCubic) =
  ## kind: "enter" | "exit" | "move" | "resize" | "opacity"
```

`loop: 0` means infinite.

### Tree surgery

```nim
proc insertBefore*(parent, child: Node; before: Node = Node(id: NodeId(-1)))
proc remove*(node: Node)   ## detaches from parent and destroys it and everything under it
proc make*(kind: NodeKind, parent: Node = Node(id: NodeId(-1))): Node
```

### How the DSL reaches the same setters

Named props are not a second system — `buildPropSetter` (`dsl.nim:142`) emits a
call to one of these, or to a raw `node.set(...)`. Six props are special-cased
to the named setter:

```nim
of "gap", "spacing":
  s = newCall(newDotExpr(nodeSym, ident"spacing"), newCall(ident"int32", propVal))
of "pad", "padding":
  s = newCall(newDotExpr(nodeSym, ident"padding"), newCall(ident"int32", propVal))
of "size", "fontsize":
  s = newCall(newDotExpr(nodeSym, ident"fontSize"), newCall(ident"int32", propVal))
of "width":
  s = newCall(newDotExpr(nodeSym, ident"width"), newCall(ident"int32", propVal))
of "height":
  s = newCall(newDotExpr(nodeSym, ident"height"), newCall(ident"int32", propVal))
```

and five to a dedicated helper: `fill` → `setFill`, `shadow` → `setShadow`,
`use` → `applyStyle`, `enter` → `setEnter`, `exit` → `setExit`, `reveal` →
`setReveal`, `animate` → `setLoop`.

### Enumerated prop words

Several props take bare English words; the macro compiles them to the wire
integer (`dsl.nim:152`):

```nim
let words = case norm
  of "alignitems": @[("first", 0), ("start", 0), ("center", 1), ("last", 2), ("stretch", 3)]
  of "justify": @[("first", 0), ("start", 0), ("center", 1), ("last", 2), ("between", 3), ("around", 4), ("evenly", 5)]
  of "cursor": @[("arrow", 0), ("hand", 1), ("ibeam", 2), ("text", 2)]
  of "align": @[("left", 0), ("center", 1), ("right", 2)]
  of "fit": @[("contain", 0), ("cover", 1), ("fill", 2)]
  of "blend": @[("normal", 3), ("plus", 12), ("screen", 14), ("overlay", 15), ("darken", 16), ("lighten", 17),
                ("colordodge", 18), ("colorburn", 19), ("hardlight", 20), ("softlight", 21), ("difference", 22),
                ("exclusion", 23), ("multiply", 24), ("hue", 25), ("saturation", 26), ("color", 27),
                ("luminosity", 28)]
  else: @[]
```

Plus `ease = outBack` and friends, resolved against the `Easings` enum in
`protocol/schema.nim` (`dsl.nim:165`), and `font = mono` → `theme().mono`.

### Theme colour words

Bare theme names in any colour prop are rewritten to live reads of the current
theme, so a theme switch restyles them (`dsl.nim:96`, `101`):

```nim
const themeColors = ["bg", "sidebar", "surface", "surface2", "surface3", "line", "text", "muted", "faint",
                     "accent", "accentText", "accentSoft", "danger", "success"]
const colorProps = ["fill", "color", "textcolor", "bordercolor", "shadow"]
```

The rewrite recurses through `if`, `rgba(…)`, `linear(…)` and
`shadow(color = …)`, but leaves **field names alone** — `x.accent` stays a field
access (`dsl.nim:103`): *"Callee names, field names (`x.accent`) and argument
names stay."*

---

## 7. Units

`sdk/ui/units.nim`, header verbatim:

> Units as types (roadmap S1): `320.px`, `180.ms`, `1.5.s`, `90.deg`. A plain
> number still means px, ms or degrees, but a value WITH a unit must be the right
> one: `width = 200.ms` is a compile error, not a silent bug.

### The three types and their constructors

```nim
type
  Px* = distinct float32     ## a length in logical pixels
  Ms* = distinct float32     ## a duration in milliseconds
  Deg* = distinct float32    ## an angle in degrees, clockwise

template px*(x: SomeNumber): Px = Px(float32(x))
template ms*(x: SomeNumber): Ms = Ms(float32(x))
template s*(x: SomeNumber): Ms = Ms(float32(x) * 1000)
template secs*(x: SomeNumber): Ms = Ms(float32(x) * 1000)
template deg*(x: SomeNumber): Deg = Deg(float32(x))
```

Because they are `distinct`, `px` and `ms` cannot be mixed without a compile
error — that is the entire mechanism.

### How a prop knows which one it wants

Three checking functions, and the rule is: *the prop decides, the value is
checked*.

```nim
proc lengthOf*(x: SomeNumber): float32 = float32(x)
proc lengthOf*(x: Px): float32 = float32(x)
proc lengthOf*(x: Ms): float32 {.error: "Y020 this prop is a length: use px (e.g. 16.px), not ms".}
proc lengthOf*(x: Deg): float32 {.error: "Y020 this prop is a length: use px (e.g. 16.px), not deg".}

proc durationOf*(x: SomeNumber): float32 = float32(x)
proc durationOf*(x: Ms): float32 = float32(x)
proc durationOf*(x: Px): float32 {.error: "Y021 this prop is a duration: use ms or s (e.g. 200.ms), not px".}
proc durationOf*(x: Deg): float32 {.error: "Y021 this prop is a duration: use ms or s (e.g. 200.ms), not deg".}

proc angleOf*(x: SomeNumber): float32 = float32(x)
proc angleOf*(x: Deg): float32 = float32(x)
proc angleOf*(x: Px): float32 {.error: "Y022 this prop is an angle: use deg (e.g. 45.deg), not px".}
proc angleOf*(x: Ms): float32 {.error: "Y022 this prop is an angle: use deg (e.g. 45.deg), not ms".}
```

So: `lengthOf` → `float32`, `durationOf` → `float32`, `angleOf` → `float32`.
Each returns *"the number the wire carries"*.

The DSL inserts the right call automatically, based on the prop's normalised
name (`dsl.nim:89`):

```nim
const lengthProps = ["width", "height", "minwidth", "maxwidth", "minheight", "maxheight", "pad", "padding",
                     "padx", "pady", "padtop", "padright", "padbottom", "padleft", "margin", "marginx",
                     "marginy", "margintop", "marginright", "marginbottom", "marginleft", "gap", "spacing",
                     "radius", "border", "top", "left", "right", "bottom", "x", "y", "size", "fontsize",
                     "blur", "backdropblur"]
const durationProps = ["transition"]
const angleProps = ["rotate"]
```

```nim
proc withUnits(norm: string; v: NimNode): NimNode =
  if norm in lengthProps: newCall(ident"lengthOf", v)
  elif norm in durationProps: newCall(ident"durationOf", v)
  elif norm in angleProps: newCall(ident"angleOf", v)
  else: v
```

So `width = 200.ms` becomes `lengthOf(200.ms)` and fails with **Y020** at compile
time. Note also:

```nim
if not isLiteral(propVal):                # a plain number needs no unit check
  propVal = withUnits(norm, propVal)
```

A bare literal never gets checked — `width = 200` is accepted, because a plain
number is assumed correct.

In imperative code the wrappers are already there, so you pass the plain number
(`width(64)`, not `width(64.px)`) — `padding`, `spacing`, `fontSize`, `width`
and `height` all take `int32`. `lengthOf` is only reachable via the DSL, or if
you call it yourself.

### Unit arithmetic

```nim
proc `$`*(x: Px): string = $float32(x) & "px"
proc `$`*(x: Ms): string = $float32(x) & "ms"
proc `$`*(x: Deg): string = $float32(x) & "deg"
proc `+`*(a, b: Px): Px = Px(float32(a) + float32(b))
proc `-`*(a, b: Px): Px = Px(float32(a) - float32(b))
proc `*`*(a: Px; k: SomeNumber): Px = Px(float32(a) * float32(k))
proc `+`*(a, b: Ms): Ms = Ms(float32(a) + float32(b))
proc `*`*(a: Ms; k: SomeNumber): Ms = Ms(float32(a) * float32(k))
proc `==`*(a, b: Px): bool {.borrow.}
proc `==`*(a, b: Ms): bool {.borrow.}
proc `==`*(a, b: Deg): bool {.borrow.}
```

So `24.px + 8.px`, `24.px * 2` and `200.ms * 0.5` all work, and comparing two
signals' `Px` values works too — e.g. `if w.get() < 640.px`.

### `fr` and `%` — neither exists as a value

**CLOSED 2026-10-03 — repo-wide grep, not a bounded one.** A `grep -E 'Fr\*|`%`|template %|proc fr|percent'`
over the whole `sdk/` tree returns **zero** type declarations and **zero** templates — every
hit is one of these four, all of them the literal string `fr` inside a grid column string:

- `sdk/yantra.nim:111` — `proc grid*(parent: Node, cols: string = "1fr 1fr"): Node =`
- `sdk/ui/dsl.nim:419` — the comment `# \`grid "1fr 2fr 200", spacing = 12:\` — columns of fixed px, shares (fr) or \`auto\``
- `sdk/tests/t_sdk.nim:38` — `verify("grid", w.grid("1fr 1fr").id == NodeId(1))`
- `sdk/tests/t_sdk.nim:61` — `n.flexBasis(100.0); n.gridCols("1fr"); n.gridRows("auto"); n.gridGap(4)`

(the `proc fr` and `percent` alternations matched only `proc frameDt` (`sdk/ui/input.nim:45`),
`proc free` (`sdk/ui/paint.nim:124`) and the word "percentage" in a test message
(`sdk/tests/t_settings.nim:84`) — none of them a unit.)

So there is **no `Fr` type and no `%` template**. Proportions are expressed
as **text inside grid column strings**, not as unit values:

- `grid "1fr 2fr 200"` — `fr` and `auto` are tokens in the CSS
  `grid-template-columns` string (`dsl.nim:419`, `yantra.nim:111`)
- `flexGrow = 1`, `flexShrink`, `flexBasis` — the floats that produce the same
  effect in a Row/Column
- `span = 2` — how many grid columns a child takes

If you want to build a grid string from a number, interpolate it
(`grid "1fr " & $n & "fr"`). Do not expect `1.fr` to compile.

---

## Quick reference

```nim
app "Title", width = 480, height = 720, fill = 0x0B0B10:
  column(gap = 12, pad = 24, grow = 1):
    text "Hello {name.get()}", size = 32, weight = 700, color = 0xF5F5F7
    button "Click me":
      onClick: count.set(count.get + 1)

    for t in items.get().keyed(t.id):
      Row(t)
    empty:
      text "Nothing here yet."

    if open.get():
      text "shown"
```

Signals: `state 0` · `.get` · `.set` · `.update` · `+=` · `.peek` · `derive:` ·
`createEffect` · `batch`.
Units: `16.px` · `200.ms` · `1.5.s` · `45.deg`; checked by `lengthOf` /
`durationOf` / `angleOf`.