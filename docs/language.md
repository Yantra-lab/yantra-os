# The Yantra language — design spec v0

Status: **proposal for Owner review.** Examples are the contract: an implementation is done
when these exact snippets compile and behave as described. All syntax below is valid Nim —
Yantra is a set of Nim macros, not a new parser.

## 1. The one idea

> **What you see is a function of state and time.**

- An **app** changes *state* (a click, a keystroke, data arriving).
- A **video** changes *time* (a clock ticking frame by frame).

Same tree, same properties, same renderer, same animation system. An app can contain a
video (an animated onboarding). A video can contain app widgets (a UI demo). Exporting a
video = driving the clock at a fixed frame rate and saving each frame. Nothing else.

## 1b. A real programming language, not a template language

Every block (`app`, `component`, `film`, `site`, `deck`, `machine`, `game`) is a Nim macro,
and **everything inside it is ordinary Nim**: types, procs, generics, closures, recursion,
exceptions, iterators, async, macros of your own, and any pure-Nim library. The DSL only adds
*meaning* to a few names (`text`, `column`, `state`…); it never takes power away.

Example — the 7GUIs "Cells" spreadsheet: a real parser, a dependency graph, and a reactive UI
in one file.

```nim
type
  ExprKind = enum ekNum, ekRef, ekCall
  Expr = ref object
    case kind: ExprKind
    of ekNum: n: float
    of ekRef: cell: string
    of ekCall: fn: string; args: seq[Expr]

proc parse(src: string): Expr = ...             # ordinary recursive-descent parser

proc eval(e: Expr, vals: Table[string, float]): float =
  case e.kind
  of ekNum: e.n
  of ekRef: vals.getOrDefault(e.cell)
  of ekCall:
    let xs = e.args.mapIt(eval(it, vals))
    case e.fn
    of "sum": xs.sum
    of "avg": xs.sum / xs.len.float
    else: raise newException(ValueError, "unknown function " & e.fn)

app "Cells":
  var formulas = state initTable[string, string]()
  let values = derived:                          # recomputed only when `formulas` changes
    var vals = initTable[string, float]()
    for key in topoSort(formulas): vals[key] = eval(parse(formulas[key]), vals)
    vals

  grid(cols = 26, rows = 100):
    for r in 0 ..< 100:
      for c in 'A' .. 'Z':
        let key = $c & $r
        cell key, value = values.getOrDefault(key), formula = formulas.getOrDefault(key):
          onEdit(src): formulas[key] = src
```

And a custom widget drawn from scratch — plain data, plain loops, per-frame simulation:

```nim
type Particle = object
  pos, vel: Vec2

proc Fireworks(count = 2000) {.component.} =
  var ps = newSeq[Particle](count)
  canvas(fill = true):
    onFrame(dt):
      for p in ps.mitems:
        p.vel += vec2(0, 300) * dt
        p.pos += p.vel * dt
      for p in ps:
        draw.circle(p.pos, 2, color = heat(p.vel.len))
```

What this guarantees:
- **Full standard library in apps**: `tables`, `sets`, `json`, `strutils`, `strformat`,
  `sequtils`, `algorithm`, `options`, `math`, `random` (seeded), `unicode`, `times` (via host
  clock). Enforced by a test (PLAN L0).
- **Any pure-Nim package** (nimble) that does no direct OS I/O works inside an app; I/O goes
  through the platform APIs (`docs/apis.md`).
- **Every built-in widget and verb is written in this same public language** (architecture
  §7.2) — you can read it, copy it, or write a better one.
- **Speed**: app code compiles to optimised wasm (≈1.2–1.5× native); heavy engines (render,
  physics, audio, video) run natively in the host.
- Trusted, signed apps may later compile as **native modules** (no wasm cost) with the same
  source.

## 2. Apps

### 2.1 Hello

```nim
import yantra

app "Counter":
  var clicks = state 0

  column(gap = 12, pad = 24):
    text "Clicked {clicks} times", size = 32
    button "Click me":
      onClick: clicks += 1
```

Rules:
- `app "Title":` opens a window. Optional: `app "Title", size = (800, 600):`.
- `state x` makes a **signal**. Reading it inside the UI subscribes; writing it updates
  **only the properties that read it** (fine-grained, like SolidJS — no virtual DOM, no
  re-render of the whole tree).
- `"{clicks}"` in any string literal inside UI is reactive interpolation.
- Layout nodes take a block of children. Leaf nodes take their main value first
  (`text "…"`, `button "…"`, `image "path"`) then named props.
- Events are blocks: `onClick:`, `onInput:`, `onHover:`.

### 2.2 Props are named, short and typed

```nim
text "Title", size = 32, weight = bold, color = fg.muted
box(pad = 16, radius = 12, fill = surface, border = 1):
  ...
```

One table (`sdk/props.nim`) maps every named prop → wire property id + type. The macro,
the docs and the editor autocomplete are all generated from that table. An unknown prop is a
**compile error with a suggestion**: `unknown prop 'colour' on text — did you mean 'color'?`

### 2.3 Theme — beautiful by default

```nim
app "Notes", theme = dark:          # built-ins: light, dark; or your own
  ...
```

Colours are **tokens**, not hex: `bg`, `surface`, `fg`, `fg.muted`, `accent`, `danger`.
Sizes come from scales: `pad = 2` means spacing step 2 (8 px), `size = lg` a type step.
Hex (`color = rgb"#1e1e2e"`) is allowed but never needed. Defaults (font, spacing, radius,
easing on every state change) are chosen so an unstyled app already looks finished.

### 2.4 Components

```nim
proc Card(title: string, body: string) {.component.} =
  box(pad = 4, radius = 12, fill = surface):
    text title, size = lg, weight = bold
    text body, color = fg.muted
    slot()                            # children passed by the caller go here

app "Cards":
  row(gap = 3):
    Card("Fast", "60 KB apps"):
      button "Learn more"
    Card("Safe", "Sandboxed by default")
```

A component is a Nim proc generated by the macro. Props are ordinary typed parameters;
pass a `state` to make them reactive.

### 2.5 Lists and conditions

```nim
var todos = state seq[Todo](@[])
var showDone = state true

column:
  for t in todos:                     # keyed by index by default; `for t in todos, key = t.id`
    row:
      checkbox t.done
      text t.title
  if showDone:
    text "All done!"
  else:
    text "{todos.len} left"
```

`for`/`if` inside UI blocks are reactive: when `todos` changes, only added/removed/moved
rows change.

### 2.6 Transitions in apps

```nim
text "Saved", opacity = 0:
  on state saved: opacity.to(1, 200.ms)
```

Any prop can animate with the same `to(...)` used by videos (section 3).

## 3. Motion — videos from code

```nim
import yantra/motion

scene "Intro", size = (1920, 1080), fps = 60:
  let logo  = text("Yantra", size = 160, opacity = 0)
  let ring  = circle(r = 0, stroke = accent, width = 8)
  let tag   = text("apps without the bloat", size = 48, y = 140, opacity = 0)

  timeline:
    logo.opacity.to(1, 600.ms, easeOutCubic)
    all:                                   # in parallel
      ring.r.to(320, 1.s, easeOutBack)
      logo.scale.to(1.1, 1.s)
    wait 300.ms
    tag.opacity.to(1, 400.ms)
    tag.y.to(120, 400.ms)                  # sequential by default
    wait 1.s
    all:
      logo.opacity.to(0, 500.ms)
      tag.opacity.to(0, 500.ms)
      ring.r.to(2000, 800.ms, easeInCubic)
```

Rules:
- Statements in `timeline:` run **one after another**; `all:` runs its children in parallel;
  `wait d` pauses; `loop n:` repeats.
- `x.to(value, duration, easing)` tweens from the value at that moment.
- Durations are typed: `600.ms`, `1.s`, `2.5.s`.
- The timeline compiles to a **pure function `sample(t) -> all property values`**. No hidden
  clock, no randomness. So:
  - `yantra preview intro.nim` opens a window with play/pause and a **scrubber**.
  - `yantra render intro.nim -o intro.mp4` renders every frame deterministically and
    encodes it. Same input → byte-identical frames.
- Shapes for motion: `circle`, `rect`, `line`, `path`, `text`, `image`, `group`, plus every
  app widget (so product demos are real UI, not screenshots).
- Later (not v0): `code` block with typewriter/diff highlighting, `latex`, camera moves,
  audio track sync, 3D scenes.

## 4. What it compiles to

```
your .nim  --(Yantra macros)-->  plain Nim calls to sdk/yantra.nim  --(nim + clang)-->  app.wasm
                                 (window/column/text/set/on …)                            ~60 KB
app.wasm   --(host)-->  node tree  --(render/)-->  Qt Quick  -->  window | PNG frames -> mp4
```

The existing imperative SDK is the **assembly language**; the DSL generates it. Every macro
can be inspected with `yantra expand file.nim`, which prints the generated plain Nim — no
magic the Owner cannot read.

## 5. Tooling (one binary, `yantra`)

| Command | Does |
|---|---|
| `yantra new <name>` | New app folder with a working example |
| `yantra dev <file>` | Build + open + **hot reload on save** (state kept) |
| `yantra preview <scene>` | Scene window with scrubber |
| `yantra render <scene> -o out.mp4` | Deterministic video export |
| `yantra expand <file>` | Show the plain Nim a macro generated |
| `yantra check` | Compile errors + unknown props, with suggestions |

## 6. Non-goals for v0

CSS, HTML, a JS runtime, a virtual DOM, stringly-typed styles, a custom parser, 3D video
export (Qt renders 3D only in a real window — see docs/renderer.md), audio.

## 7. How the implementation is tested (so an agent cannot fake it)

- **Macro golden tests**: each snippet in this file lives in `sdk/tests/spec/*.nim`; its
  expanded plain Nim is compared to a checked-in golden file.
- **Signal tests** (pure Nim, no wasm): writing a state updates exactly the dependent props,
  in a defined order, and nothing else.
- **Timeline tests** (pure): `sample(t)` at fixed times equals hand-computed values
  (e.g. halfway through a linear 1 s tween from 0→100 is exactly 50).
- **Frame determinism**: rendering frame N twice gives identical PNG bytes.
