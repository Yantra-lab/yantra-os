# Yantra language — core specification v1

Status: **normative.** Where this file and any other doc disagree, this file wins; where it is
silent, the behaviour is undefined and must be decided here (QUESTIONS.md) before anyone
implements it. Every rule has an id `[S-…]`; every id must be covered by at least one test in
`sdk/tests/spec/` whose name contains the id (enforced by `docs/spec/coverage` — PLAN L10).

Yantra is Nim plus a standard library of macros. Nothing here changes Nim's own semantics; it
defines what the Yantra macros accept and what they mean.

---

## 1. Syntax shapes

**[S-SYN-1] Two call shapes, one meaning.** Every Yantra construct can be written as a command
(statement position) or a call (any position). They are identical:

```nim
text "Hello", size = 32            # command — statement position only
let t = text("Hello", size = 32)   # call — required in expression position
```

**[S-SYN-2] Expression position needs parentheses.** `let x = text "a", size = 1` is a Nim
syntax error. Style rule (and `yantra fmt`): commands for statements, calls for expressions.

**[S-SYN-3] Argument order.** `kind(main, named…)` then an optional `:` block of children.
The *main* argument is positional and first (`text` → content, `image` → source, `button` →
label, `input` → bound value). All other props are named. A second positional argument is a
compile error `Y010 positional after main`.

**[S-SYN-4] Children.** A `:` block after a container holds its children, in order. Any Nim
statement may appear in a children block (`let`, `var`, `if`, `for`, `case`, proc calls);
only statements that *create nodes* add children.

**[S-SYN-5] Events are blocks.** `onClick: stmts` or `onClick(e): stmts` (with the event
value). An event block is a closure; it may read and write any visible variable.

**[S-SYN-6] Identifiers are Nim identifiers.** Nim ignores case and underscores after the first
letter: `fontSize`, `font_size` and `fontsize` are the same name, and **`eNum` is the keyword
`enum`**. Yantra style is camelCase; the formatter normalises. A prop or node name that
collides with a Nim keyword under this rule is forbidden in the library.

**[S-SYN-7] Reserved names.** Inside UI blocks the names of node kinds, props and events are
resolved by the Yantra macros first, then by normal Nim scoping. A local variable that shadows a
node kind inside a UI block is a compile error `Y011 shadows node kind 'text'` — rename it.

**[S-SYN-8] Naming a node (PROPOSED — decided by the Phase I A/B test).** A lowercase label
before a node statement names it, so timelines and handlers can refer to it without `let`:

```nim
film "Launch", format = vertical1080:
  shot "hook", 3.s:
    title: words "Apps without the bloat", size = 140
    hero: column(gap = 2):
      tag: text "60 KB apps", size = 48
    timeline:
      title.reveal(stagger = 60.ms)
      tag.opacity.to(1, 400.ms)
```

Why: it is a statement, so the command-in-expression trap ([S-SYN-2]) cannot happen; the name
comes first, which reads well and gives stable handles for targeted AI edits. A label is a
lowercase identifier not equal to any event name; PascalCase names are components. Candidates
being measured against it: `let x = text(...)` and `text "…", id = x`.

**[S-SYN-9] Nim keywords are never names in the library.** `out`, `export`, `from`, `type`,
`method`, `iterator`, `object`, `static`, `bind`, `mixin`, `using`, `when`, `of`, `in`, `is`, `as`,
`div`, `mod`, `shl`, `shr`, `and`, `or`, `not`, `xor`, `enum`, `tuple`, `concept`, `distinct`,
`block`, `defer`, `yield`, `addr`, `ptr`, `ref`, `var`, `let`, `const` (and every other Nim keyword,
compared style-insensitively per [S-SYN-6]) must not be node kinds, props, events, verbs or
recommended labels. The library uses `save` (not `export`), `final`/`result` (not `out`),
`source` (not `from`). A test in `sdk/tests/spec/` checks every generated name against the Nim
keyword list. Authors who use a keyword as a label get `Y012 'out' is a Nim keyword — try 'final'`.

**[S-SYN-10] No expressiveness ceiling.** Every construct in the standard library is written in
the same public language using lower levels (architecture §7.2): verbs → nodes → scene API → draw →
GPU shaders/compute → plain Nim → native plugins. Any computation a VFX tool, game engine or
browser can perform must be expressible in a Yantra program; the north stars (`docs/northstar.md`)
are the executable proof and may never be removed or simplified to make them pass.

**[S-SYN-11] The Yantra prelude is imported implicitly.** App modules do not require `import yantra`;
the full Yantra prelude (`sdk/yantra.nim`, including DSL verbs, signals, components, and node kinds)
is imported implicitly by the compiler, `config.nims`, and build tooling. Explicit `import yantra`
remains valid and produces no duplicate import warnings or errors.

## 2. Nodes

**[S-NODE-1]** A node is created by evaluating a node-kind call inside a UI block (`app`,
`component`, `scene`, `doc`, `site`, `deck`, `film`, `game`). Node-kind calls outside a UI block
are compile errors `Y020 node outside UI block`.

**[S-NODE-2] Identity.** A node's identity is its position in the *static* structure of the
source plus, inside `for`, its key (§4). Identity decides what survives a re-render: state,
focus, scroll position, running animations.

**[S-NODE-3]** A node has exactly one parent. Moving a node = remove + insert; its identity (and
therefore its state) is preserved only when moved by a keyed `for`.

**[S-NODE-4] Accessibility.** Every node kind declares a role (`protocol/schema.nim`); a node
kind without a role does not compile (Phase Y). Text content is the default accessible name;
`label = "…"` overrides it.

## 3. Props

**[S-PROP-1] Declared, typed, closed.** Each node kind has a declared prop set. Unknown prop →
compile error `Y001 unknown prop 'colour' on text — did you mean 'color'?` (edit distance ≤ 2).

**[S-PROP-2] Resolution order** (highest wins): explicit value at the call site → value passed
by the enclosing component → the node kind's theme style → the kind's built-in default.

**[S-PROP-3] Reactive or static is inferred.** If a prop's value expression reads a signal or
derived value, the prop re-evaluates when those change; otherwise it is evaluated once at
creation. The author never marks this.

**[S-PROP-4] Types and conversions.** `int` → `float` is implicit; `float` → `int` is a compile
error. Lengths accept a bare number (= logical px, [S-PLAT-1]) or a unit (`16.px`, `50.pct`, `1.fr`, `2.em`).
Colours accept a theme token (`accent`, `fg.muted`) or `rgb"#RRGGBB"` / `rgba"#RRGGBBAA"`. See [S-COL-1..4] for precision.
Durations must carry a unit (`300.ms`, `2.s`); a bare number is `Y002 duration needs a unit`.
Angles: `90.deg`, `1.5.rad`.

**[S-PROP-5] Spacing and size scales.** `pad`, `gap`, `margin` with a bare int `n` mean theme
step `n` (step 0 = 0, 1 = 4 px, 2 = 8, 3 = 12, 4 = 16, 5 = 24, 6 = 32, 7 = 48, 8 = 64);
an explicit unit (`pad = 10.px`) bypasses the scale. `size` on text accepts a scale name
(`xs sm md lg xl display`) or a number (px).

**[S-PROP-6] Out-of-range values** are clamped and reported once as a warning in debug builds:
`opacity` → [0, 1]; negative `width/height/pad/gap/radius` → 0; `fontSize` ≤ 0 → default.
NaN or ±Inf in any float prop → runtime error `PropValueError` (never silently drawn).

**[S-PROP-7] Setting the same prop twice** at one call site is `Y003 duplicate prop`.

## 4. Control flow in UI blocks

**[S-CTL-1] `if / elif / else` and `case`** are reactive when their conditions read signals.
Switching branches disposes the old branch's nodes, effects and resources (§5.6) and creates the
new branch's. Branches with no nodes are allowed.

**[S-CTL-2] `for x in xs`** is reactive when `xs` is a signal or derived value. Items are keyed:
- default key = the item itself when the item type is a value type with `==` and `hash`
  (ints, strings, value objects); otherwise the index;
- explicit key: `for t in todos, key = t.id:` (the expression is evaluated per item).
Keyed items keep their identity when reordered; unkeyed (index) items keep identity by position.

**[S-CTL-3] Duplicate keys** in one `for` → runtime error `DuplicateKey(key, positions)` in debug
builds; in release builds the later duplicate is keyed by `(key, occurrence)`.

**[S-CTL-4]** `while`, `break`, `continue`, `return` inside a UI block follow Nim rules but are not
reactive (evaluated once at creation). A `for` over a non-reactive collection is also evaluated
once.

**[S-CTL-5] Empty collections** render nothing; use `else` on `for` for an empty state:
`for t in todos: … else: text "Nothing yet"` (Yantra extension; compiles to an `if`).

## 5. Reactivity

Values: `state` (writable signal), `derived` (computed, read-only), `effect` (side effect).

```nim
var count = state 0                         # signal
let doubled = derived: count * 2            # lazy, memoised
effect: log "count is {count}"              # runs after the tree commits
```

**[S-RX-1] Reading** a signal inside a tracking scope (prop expression, `derived`, `effect`,
reactive `if/for` condition) subscribes that scope. Reading outside a tracking scope (e.g. in an
event handler) just returns the current value and subscribes nothing. `untrack: expr` reads
without subscribing inside a tracking scope.

**[S-RX-2] Writing** (`count += 1`, `count.set v`) is synchronous for reads: the next line sees
the new value. Propagation to the tree is **batched**: all writes in one event handler, one
frame callback, or one `batch:` block propagate once, at the end.

**[S-RX-3] Equality cut-off.** A write that is `==` to the current value does nothing. For
`seq`/`Table`/objects, mutate in place with `count.update(proc(v: var T) = …)`; `update` always
notifies. Direct mutation of a signal's inner value without `update` is a compile error for
container types (`Y030 mutate through update`).

**[S-RX-4] Glitch-free.** Within one propagation, every derived value and effect observes a
consistent snapshot; each runs at most once, in topological order. No derived value ever sees a
half-updated state.

**[S-RX-5] Derived values are lazy and memoised**: computed on first read, recomputed only when a
dependency changed and someone reads them again. Dependencies are dynamic (re-tracked each run),
so `derived: (if flag: a else: b)` depends only on the branch taken.

**[S-RX-6] Forbidden inside `derived`**: writing any signal (`Y031` at compile time when
visible; `WriteInDerived` at run time otherwise) and I/O. `derived` bodies are `func`-pure
where the compiler can prove it.

**[S-RX-7] Cycles.** A derived value that (transitively) reads itself → runtime error
`ReactiveCycle(path)` naming every node in the cycle. An effect that writes a signal it reads is
allowed but re-runs at most **100** times per propagation; beyond that → `ReactiveOverflow(path)`.

**[S-RX-8] Effects** run after the tree for the current propagation is committed, in creation
order. An effect may register cleanup with `onCleanup: …`, run before its next execution and on
disposal.

**[S-RX-9] Ownership and disposal.** Every signal, derived, effect, resource, timeline and event
subscription is owned by the node scope that created it. When that scope is disposed (branch
switch, keyed item removed, component unmounted, app closed), everything it owns is disposed in
reverse creation order, cleanups run, in-flight resources are cancelled. Nothing leaks by design.

**[S-RX-10] Signals in closures.** Event handlers and async procs capture signals by reference;
they always see the current value. Capturing a *plain* `var` in a handler captures the Nim
variable as usual (not reactive).

## 6. Components

```nim
proc Card(title: string, count: Val[int] = 0, onOpen: Handler = nil) {.component.} =
  box(pad = 4, radius = 12):
    text "{title} ({count})"
    button "Open":
      onClick:
        if onOpen != nil: onOpen()
    slot()
```

**[S-CMP-1]** A component is an ordinary Nim `proc` with the `{.component.}` pragma — the only
form (one way to say it, [S-TOK-1]). Parameters are ordinary typed parameters with defaults;
editors and nimsuggest understand it as a normal proc. Components are named in PascalCase. Recursion is allowed (tree views); runtime depth > 256 → `ComponentDepth` error.

**[S-CMP-2] `Val[T]`** accepts a plain `T`, a `state T` or a `derived T`. Inside the component,
reading a `Val[T]` is uniform and reactive when the caller passed a reactive value.

**[S-CMP-3] Two-way binding** only through an explicit `Bind[T]` parameter (the caller passes a
`state`): `input value` inside `component Field(value: Bind[string])`.

**[S-CMP-4] Slots.** `slot()` renders the caller's children block; named slots:
`slot(header)` with caller syntax `header: …`. Calling a component with children when it has no
`slot()` → `Y040 component has no slot`.

**[S-CMP-5]** Component-local `state` is created per instance and preserved as long as the
instance's identity (§2) survives.

## 7. Events

**[S-EVT-1]** Handlers run synchronously on the host's UI turn, inside a batch (§S-RX-2).
Default actions (focus, text insertion, scroll) happen after the handler unless it calls
`e.preventDefault()`.

**[S-EVT-2] Propagation.** Pointer and key events go target → ancestors (bubble); `e.stop()`
stops it. No capture phase in v1.

**[S-EVT-3] Exceptions in handlers** never crash the host: they propagate to the nearest
`errorBoundary(fallback):` ancestor; with none, the app shows the built-in error panel and the
exception is logged with the source location. The tree state before the handler is kept
(writes made before the raise are kept; propagation of them still happens).

**[S-EVT-4]** A handler that runs longer than 50 ms logs a slow-handler warning in debug builds
(apps are single-threaded; long work belongs in `spawn`/async).

## 8. Async and resources

**[S-ASY-1]** `fetch(...)`, `store` queries and other services return `Resource[T]` with
`loading`, `failed`, `error`, `value`, and `refresh()`. Reading `value` while `loading` or
`failed` raises `ResourceNotReady` — branch on the state first.

**[S-ASY-2] Latest wins.** When a reactive input of a resource changes, the in-flight request is
cancelled and a new one starts; a stale response is never delivered.

**[S-ASY-3]** `proc x() {.async.}` + `await` for sequential flows. Awaiting in a disposed scope
cancels the proc with `Cancelled` (no code after the `await` runs).

**[S-ASY-4]** Timeouts are explicit (`timeout = 10.s`, default 30 s for network); expiry sets
`failed` with `Timeout`.

## 9. Time and motion

**[S-TIME-1] Timeline composition.** Statements in `timeline:` run in sequence; duration of a
sequence = sum. `all:` runs children in parallel; duration = max. `wait d` adds `d`.
`loop n:` repeats its body `n` times (`n ≥ 1`); `loop:` (no count) is only allowed in apps, not
in `film`/`scene` (a video must have a finite length) → `Y050`.

**[S-TIME-2] `x.to(v, d, ease)`** tweens from the value `x` has *at the tween's start time* in
the timeline (resolved deterministically from earlier tracks, not from wall-clock state).

**[S-TIME-3] Sampling.** `sample(t)` for `t < 0` → start values; for `t ≥ duration` → end values;
at an exact boundary between two sequential tweens the later tween's start value is used.
Zero-duration tweens jump. Negative durations → `Y051` (literal) or `TimelineError` (computed).

**[S-TIME-4] Easing** functions are defined exactly (formulas in `sdk/motion/easing.nim`, matching
the standard Penner/CSS definitions) and must satisfy `e(0) == 0`, `e(1) == 1`.

**[S-TIME-5] Conflicts in apps.** A new `to` on a prop that is already animating cancels the
running tween and starts from the prop's current displayed value (“overwrite auto”).

**[S-TIME-6] Frames.** Films/scenes render at their declared fps; frame `n` is `t = n / fps`
exactly (rational time, no float drift). Apps animate on the display's refresh; `onFrame(dt)`
receives the real elapsed time clamped to ≤ 100 ms.

## 10. Text

**[S-TXT-1] Interpolation.** In string literals inside UI blocks, `{expr}` inserts any Nim
expression converted with `$`; `{expr:fmt}` uses strformat specs (`{price:.2f}`); `{{` and `}}`
are literal braces. The literal is reactive when any `expr` reads a signal.

**[S-TXT-2]** Strings from variables (not literals) are **not** interpolated — braces in user
data are shown as typed. (No template injection.)

**[S-TXT-3]** All text is UTF-8; lengths, cursor positions and selections count grapheme
clusters, never bytes (Indic conjuncts and emoji are single units to the user).

**[S-TXT-4]** Number/date formatting uses the app locale (`en-IN` → 12,34,567.00 lakh grouping);
`{n:raw}` opts out.

## 11. Errors

**[S-ERR-1] Compile-time errors** have stable codes `Yxxx`, point at the user's source line (not
generated code), and include a fix suggestion where one exists. The list lives in
`sdk/errors.nim`; every code has a test that triggers it.

**[S-ERR-2] Runtime errors** are typed exceptions (`PropValueError`, `DuplicateKey`,
`ReactiveCycle`, `ReactiveOverflow`, `ResourceNotReady`, `Cancelled`, `Timeout`,
`CapabilityDenied`, `TimelineError`, `ComponentDepth`) carrying structured fields.

**[S-ERR-3]** An app never crashes the host. A trap inside the wasm module (out-of-bounds, stack
overflow, unreachable) stops that app, shows the error panel, and keeps the host alive.

## 12. Determinism

**[S-DET-1]** Given the same source, inputs and timestamps, `film`/`scene` output is identical
frame for frame on every machine. `rand` is seeded (default seed = hash of the file name);
wall-clock, network and unseeded randomness are unavailable inside `film`/`scene` → `Y060`.

**[S-DET-2]** Iteration order of anything that affects output is defined (no hash-order
iteration); `Table` iteration in UI blocks uses insertion order (`OrderedTable` semantics).

## 14. Platforms (desktop, web, phone, tablet, VR)

**[S-PLAT-1] Logical pixels.** `px` and bare lengths are *logical* pixels (1 px = 1/96 inch at
100 % scale, like CSS px). The platform multiplies by the device scale; apps never see physical
pixels unless they ask (`screen.scale`). In VR, 2D panels map logical px to metres via the
panel's size; 3D lengths use metres (`1.2.m`, `30.cm`).

**[S-PLAT-2] One pointer model.** Mouse, touch, pen, controller ray and hand pinch all produce
the same events: `onPointerDown/Move/Up/Cancel`, `onClick` (= tap), `onHover` (never fires for
touch). `e.device` tells which (`mouse, touch, pen, ray, hand`); `e.pointerId` distinguishes
simultaneous touches. Gestures are recognisers on top: `onTap, onDoubleTap, onLongPress,
onPan, onPinch, onRotate, onSwipe`. An app written only against `onClick` works on every device.
Hover-only functionality is a lint warning (touch and VR users could not reach it).

**[S-PLAT-3] Environment is reactive.** Read-only signals: `screen.width/height` (logical px),
`screen.scale`, `screen.orientation`, `env.safeArea` (insets), `env.keyboardInset`,
`env.darkMode`, `env.reducedMotion`, `env.textScale`, `env.device` (`desktop, phone, tablet,
headset, web`). Layout that depends on them updates automatically.
`if screen.width < 600: …` is the responsive pattern; `site` breakpoints compile to this.

**[S-PLAT-4] Lifecycle.** `onSuspend:` (save work; ≤ 1 s budget), `onResume:`, `onLowMemory:`.
The platform snapshots `state` values before suspend and restores them after a cold restart,
so an app killed in the background comes back where it was.

**[S-PLAT-5] Respecting the user.** With `env.reducedMotion`, timelines in apps (not films) run
at duration 0 unless marked `essential = true`. Text honours `env.textScale` (layout must not
clip at 200 %). Touch targets are at least 44 × 44 logical px (lint warning below).

**[S-PLAT-6] Same source everywhere.** Platform-specific code is allowed only through
`when target == android:` (compile-time) or `if env.device == headset:` (run-time); a capability
missing on a platform raises `CapabilityDenied(reason = unsupported)`, never crashes.

## 15. Colour and pixel precision

**[S-COL-1] Colours are linear floating point internally.** A colour value is four `float32`
components (RGB + alpha) in **linear** light plus a **colour space** tag. `rgb"#RRGGBB"` and theme
tokens are convenience inputs in sRGB and are converted on entry. 8-bit integers never appear
inside the pipeline; they exist only at the final display or 8-bit export step.

**[S-COL-2] Colour spaces are explicit.** Supported tags start with `srgb`, `linearSrgb`,
`displayP3`, `rec2020`, `acesCg`; conversion is done by OpenColorIO. Mixing two colours in different
spaces converts to the working space first (default `linearSrgb` for apps, `acesCg` for films).

**[S-COL-3] HDR is allowed.** Components may exceed 1.0 (bright light, glows). Clamping or tone
mapping happens only at output, by an explicit `toneMap` setting on the film/app (default: none for
UI, ACES filmic for films). NaN/Inf follow [S-PROP-6] (error, never drawn).

**[S-COL-4] Frame precision.** Films render into 16-bit float frames by default (32-bit on request);
export chooses the file depth (8-bit MP4, 10-bit HEVC/ProRes, 16/32-bit EXR). The same film gives
identical pixels at the same depth ([S-DET-1]).

## 13. Token economy (rules for the library, not the author)

**[S-TOK-1]** One way to say each thing; no aliases in the library.
**[S-TOK-2]** Every prop has a good default; a construct's minimal form is one line.
**[S-TOK-3]** No imports for the standard library (prelude); no boilerplate entry points.
**[S-TOK-4]** Names are full words, ≤ 12 characters where possible, no abbreviations
(`padding` → `pad` is the only exception family: `pad`, `gap`, `min`, `max`).
**[S-TOK-5]** The one-page API (`docs/llm.md`, generated) stays under 2 000 words.
