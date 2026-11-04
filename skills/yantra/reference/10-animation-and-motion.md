# 10 — Animation and motion

Ground truth for this chapter (read, not guessed):

- `sdk/ui/motion.nim` — `Motion`, `Loop`, `fade/fly/pop/turn`, `loop/spin/pulse/breathe/bob`, `setEnter/setExit/setReveal/setLoop`, `afterMs/after`, `timeline:` macro
- `sdk/motion/easing.nim`, `sdk/motion/timeline.nim` — re-export of `protocol/easing.nim`, and the deterministic sampler
- `sdk/yantra.nim:435-467` — the imperative `animate()` / `transition()`
- `sdk/core/wire.nim:84-95, 191-198, 211, 232, 363-398` — `pAnim*`, `pTrans*`, `pEnter/pExit/pReveal`, `pSmooth`, the `Easing` enum
- `sdk/ui/dsl.nim:70-75, 194-201` — the `on…:` event-name table and the `enter/exit/reveal/animate` prop rewrites
- `render/native/motion.nim` — the engine's motion maths: `curve`, `Track.follow`, `ColorTrack.follow`, `parseSpec`, `entering/leaving`, `loopValue`, `identity`, `poseOf`
- `render/native/engine.nim:894-930, 1500, 2006-2050, 3129-3153, 3230-3284, 4087-4088, 4134` — how motion is actually executed
- `sdk/ui/input.nim` — `frameDt()`, `keyHeld`, `mouseDelta`
- `protocol/props.md` — the generated table of legal DSL props
- `apps/minipaint/PORT-NOTES.md`, `apps/minipaint/ENGINE-ISSUES.md`

---

## 1. The headline: two different things are called "animation"

Yantra has **two** animation systems, and only one of them is the imperative
`animate()` people reach for first.

| | Declarative (`animate = spin()`, `enter = fly()`) | Imperative `node.animate("scale", 1.2, …)` |
|---|---|---|
| Defined in | `sdk/ui/motion.nim`, wired by `sdk/ui/dsl.nim:194-201` | `sdk/yantra.nim:437` |
| What it is | A **retargetable loop or a one-shot pose spec** on the engine's own clock | Writes the **same wire props** plus `pAnimTrigger` |
| Per-frame work | **None in the app.** The engine plays it off its own clock; the app sets no state and re-submits nothing. (The engine *does* keep repainting: `engine.nim:2044-2046` sets `e.animating = true` while the loop runs.) | Same |
| Native engine support | **Full** (`render/native/engine.nim:2013-2046`) | **Partial** — see §3 |

Both end up as the same `pAnim*` props. The declarative form is the one that
works; the imperative form adds a `trigger` string the native engine never reads.

---

## 2. `transition(node, kind, duration, easing)`

Exact signature (`sdk/yantra.nim:462`):

```nim
proc transition*(node: Node; kind: string; duration: int32 = 300;
                 easing: Easing = easeOutCubic)
```

It writes three props:

```nim
node.set(pTransition, kind)          # 37
node.set(pTransDuration, duration)   # 38
node.set(pTransEasing, int32(easing))# 39
```

**What the native engine actually does with it** (`render/native/engine.nim`):

- `P_TRANSITION` (the `kind` string) is **never read** by `render/native`. **CLOSED
  2026-10-03 — confirmed repo-wide, not per-file.** A grep for `P_TRANSITION` /
  `pTransition` over the whole repo returns exactly four code sites and no others:

  | site | role |
  |---|---|
  | `protocol/wire.nim:91` | the id itself — `P_TRANSITION* = 37'i32` |
  | `sdk/core/wire.nim:93` | the SDK's own copy of the table — `pTransition = 37` |
  | `sdk/yantra.nim:465` | the writer — `node.set(pTransition, kind)` |
  | `render/qmlgen.nim:253-254` | the **only** reader — `if n.has(P_TRANSITION): let kind = n.sProp(P_TRANSITION)` |

  `render/native/engine.nim` contains **zero** occurrences; so does the rest of `render/native/`.
  And `qmlgen` cannot be reached from the app path anyway: it is the legacy Qt generator
  (`render/qt/qmlgen.nim:2-3` re-exports it, `render/render_qml.nim:14` and
  `render/qt/backend.nim:6` import it), while `host/host.nim:23` imports **only**
  `../render/api` — an invariant the gate asserts by reading the host source:
  `render/t_api.nim:36-40` does `doAssert not hostSrc.contains("render/qt")` and
  `doAssert not hostSrc.contains("qmlgen")`. (`render/api.nim:4` states the same rule.)

  **So the gap is real and it is only a legacy-Qt gap**: under the native engine the `kind`
  argument is inert — `transition(kind, duration, easing)` behaves as a plain
  `duration + easing` tween and `kind` is written to the wire and never consumed.
- `P_TRANS_DURATION` + `P_TRANS_EASING` are the whole of the native behaviour, and
  they implement exactly one idea: *a CSS-style retargetable tween on the node's
  own look*. `transMs` returns 0 when motion is reduced or the prop is absent, and
  `eased(...)` then returns the target unchanged.

The channels that `transition` actually eases, from every `.eased(` call site in
`engine.nim`:

| Slot | What it eases | Line |
|---|---|---|
| `cFill` | the node's fill colour | 1685, 2391 (window background) |
| `cInk` | the node's ink / text colour | 1787, 1810, 1892 |
| `cBorder` | the node's border colour | 1689 |
| `nOpacity` | opacity | 2016 |
| `nScale` | the hover/press/focus scale multiplier | 2019 |
| `nLift` | the hover/press/focus Y lift | 2021 |

That is the **complete** list. Verified by grepping `\.eased\(` across
`render/native/engine.nim` — 9 call sites, all listed above.

The declared `kind` strings are `"enter" | "exit" | "move" | "resize" | "opacity"`
(`sdk/yantra.nim:463-464`), and the SDK's own DSL equivalent writes only the
duration and the easing — `protocol/props.md:69-70` maps the DSL props
`transition → pTransDuration` and `ease → pTransEasing`. There is **no DSL prop
for the kind**.

So the idiomatic form is:

```nim
panel(transition = 200, ease = outBack, fill = surface, borderColor = line):
```

which the engine reads as: "when this node's fill, ink, border, opacity,
hover-scale or hover-lift changes, glide to the new value over 200 ms along
`outBack`, starting from wherever it is now." That is the retargetable behaviour
`render/native/motion.nim` documents at the top of the file: *"a hover that ends
halfway fades back from halfway, like a CSS transition, never jumping."*

**Colour IS interpolated** — `motion.nim:115-135` has `mix(a, b: uint32, p)`,
an ARGB channel-by-channel blend, and `ColorTrack.follow`. So the "colour
interpolation cannot be animated" claim below is **wrong** for fill/ink/border
under `transition`. It is right for `animate()`.

---

## 3. `animate(node, target, to, duration, easing, startVal, delay, loop, yoyo, trigger)`

Exact signature (`sdk/yantra.nim:437-440`):

```nim
proc animate*(node: Node; target: string; to: float32; duration: int32 = 300;
              easing: Easing = easeOutCubic; startVal: Option[float32] = none(float32);
              delay: int32 = 0; loop: int32 = 1; yoyo: bool = false;
              trigger: string = "mount")
```

Parameter by parameter, with what the native engine does:

| Param | Type | Wire prop | Native behaviour |
|---|---|---|---|
| `target` | `string` | `pAnimTarget` (28) | **Only five values are recognised** — see below. Also the switch the engine needs to start a loop at all. |
| `to` | `float32` | `pAnimTo` (30) | the far value |
| `duration` | `int32` ms | `pAnimDuration` (31) | one full pass, `frm → to` |
| `easing` | `Easing` | `pAnimEasing` (32) | the curve; ids 31..34 are **springs**, not curves (§5) |
| `startVal` | `Option[float32]` | `pAnimFrom` (29), **only set when `isSome`** | when absent, the engine uses `identity(target)` |
| `delay` | `int32` ms | `pAnimDelay` (33) | the loop waits at `from` for `delay` ms |
| `loop` | `int32` | `pAnimLoop` (34) | repeat count; **`0` = forever** |
| `yoyo` | `bool` | `pAnimYoyo` (35) | reverse every other cycle |
| `trigger` | `string` | `pAnimTrigger` (36) | **NEVER READ by the native engine** |

### 3.1 The five legal `target` strings

The engine turns a loop value into a pose with `motion.poseOf`
(`render/native/motion.nim:207-215`), a `case` on the string. An unknown string
falls into `else: discard` and the animation silently does nothing visible.
**This case statement is the authoritative list:**

| `target` | Effect |
|---|---|
| `"opacity"` | the node's opacity pose |
| `"scale"` | the node's scale pose |
| `"rotate"` | the node's rotation pose |
| `"rotation"` | alias for `"rotate"` |
| `"x"` | the node's x offset |
| `"y"` | the node's y offset |

Nothing else. **`"width"` and `"height"` are accepted by the SDK doc comment
(`sdk/yantra.nim:443` lists them) but are NOT implemented** — `poseOf` has no
case for them, so they animate to nothing. This is a real doc/engine mismatch;
mark it and do not rely on it.

`identity(target)` (`motion.nim:201-205`) supplies the `from` when `startVal` is
`none`: `1` for `opacity` and `scale`, `0` for everything else.

### 3.2 `trigger` — declared vs. real

`sdk/yantra.nim:451` declares:

```nim
## trigger: "mount" | "click" | "hover" | "focus" | "prop:<name>"
```

**Verified: `pAnimTrigger` is read in exactly one place in the whole repo,
`render/qmlgen.nim:222` — the legacy QML generator.** Neither `render/native`
nor the host reads it. Consequences under the native engine:

- `trigger = "mount"` (the default) — the animation starts as soon as the engine
  sees `pAnimTarget` (`engine.nim:2041-2046`). Correct by accident.
- `trigger = "click"` / `"hover"` / `"focus"` / `"prop:<name>"` — **no effect at
  all.** The animation still starts on mount. There is no way to re-fire it
  declaratively.

**The working way to re-fire on interaction** is the declarative `hover:` /
`pressed:` / `focused:` blocks (§8) with `transition`, which the engine *does*
retarget on state change. `examples/animate2d.nim:54` uses
`animate("scale", 1.2, trigger = "click", …)` and comments "triggered on click
for demo" — that example does **not** do what its comment says. Do not copy it as
a pattern.

### 3.3 What the native engine runs (`engine.nim:2006-2011, 2041-2046`)

```nim
proc loopOf(n: tree.Node): motion.Loop =
  motion.Loop(target: n.sProp(P_ANIM_TARGET),
       frm: n.num(P_ANIM_FROM, identity(target)), to: n.num(P_ANIM_TO, identity(target)),
       ms: n.num(P_ANIM_DURATION, 300), delay: n.num(P_ANIM_DELAY, 0),
       ease: int32(n.num(P_ANIM_EASING, 5)), count: int(n.num(P_ANIM_LOOP, 1)),
       yoyo: n.flag(P_ANIM_YOYO))
```

and each frame:

```nim
if n.has(P_ANIM_TARGET) and not e.reducedMotion:
  let l = n.loopOf
  if id notin e.loopAt: e.loopAt[id] = e.now
  let (v, going) = l.loopValue(e.loopAt[id], e.now)
  result = combine(result, poseOf(l.target, v))
  if going: (e.animating = true; e.animFull = true)
```

Two consequences worth knowing when porting:

- **`loop` defaults to 1** in the imperative form, i.e. *one pass, then it stays
  at `to`*. The declarative `Loop` builders (`spin/pulse/breathe/bob`) default
  `count = 0` = forever. So `node.animate("opacity", 0.3)` runs once; the same
  thing as `animate = pulse(low = 0.3)` runs forever.
- The engine sets `e.animating = true` while the loop is running, which is what
  keeps the window repainting. With `count = 1` it stops, and an idle app stops
  painting entirely.
---

## 4. The declarative forms (the ones that actually work)

`sdk/ui/dsl.nim:194-201` rewrites four props into calls:

| DSL prop | expands to | meaning |
|---|---|---|
| `enter = …` | `node.setEnter(node, v)` | played when the node first appears |
| `exit = …` | `node.setExit(node, v)` | played after the app removes the node |
| `reveal = …` | `node.setReveal(node, v)` | tied to **scrolling into view**, not to time |
| `animate = …` | `node.setLoop(node, v)` | a looping animation |

### 4.1 `Motion` — the enter/exit/reveal builders (`sdk/ui/motion.nim:29-39`)

```nim
type Motion* = object
  opacity*, x*, y*, scale*, rotate*: float   # the FAR end: the node fades FROM these
  ms*, delay*: int
  ease*: Easing
```

```nim
proc fade*(ms = 180; delay = 0; ease = easeOutCubic): Motion
proc fly*(x = 0.0; y = 12.0; opacity = 0.0; ms = 260; delay = 0; ease = easeOutCubic): Motion
proc pop*(scale = 0.9; opacity = 0.0; ms = 240; delay = 0; ease = easeOutBack): Motion
proc turn*(rotate = -90.0; scale = 0.6; opacity = 0.0; ms = 320; delay = 0; ease = easeOutBack): Motion
```

The node animates **from** that pose **to itself**. So `fly(y = 40)` means
"start 40 px below where I belong and glide up into place".

### 4.2 `Loop` — the `animate = …` builders (`sdk/ui/motion.nim:21-27, 41-48`)

```nim
type Loop* = object
  target*: string          # opacity | rotate | scale | x | y
  frm*, to*: float
  ms*, delay*, count*: int  # count 0 = forever
  ease*: Easing
  yoyo*: bool

proc loop*(target: string; frm, to: float; ms = 1000; yoyo = true;
           ease = easeInOutSine; count = 0; delay = 0): Loop
proc spin*(ms = 1000): Loop    = loop("rotate", 0, 360, ms, yoyo = false, ease = easeLinear)
proc pulse*(low = 0.4; ms = 1200): Loop = loop("opacity", 1, low, ms)
proc breathe*(scale = 1.04; ms = 1600): Loop = loop("scale", 1, scale, ms)
proc bob*(y = -4.0; ms = 1400): Loop = loop("y", 0, y, ms)
```

### 4.3 `setLoop` ordering matters

```nim
proc setLoop*(n: Node; l: Loop) =
  n.set(pAnimFrom, …); n.set(pAnimTo, …); n.set(pAnimDuration, …)
  n.set(pAnimDelay, …); n.set(pAnimEasing, …); n.set(pAnimLoop, …); n.set(pAnimYoyo, …)
  n.set(pAnimTarget, l.target)   # last: the engine starts the loop when it sees this
```

The source says it: **`pAnimTarget` is written last**, because that is the prop
the engine's `n.has(P_ANIM_TARGET)` gate looks for. If you hand-roll a loop with
`node.set(...)`, set the target last.

### 4.4 The wire format, if you need it

`Motion` is encoded by `motion.nim:50-53` as
`opacity,x,y,scale,rotate,ms,delay,easingOrd` — eight comma-separated numbers —
and parsed by `render/native/motion.nim:139-154` (`parseSpec`). Defaults on a
short spec: `opacity 1, scale 1, ms 200, ease = easeOutCubic`.
Verified strings from `sdk/tests/t_style.nim`:

- `enter = fly(y = 10, delay = 40)` → `"0.0,0.0,10.0,1.0,0.0,260,40,5"`
- `exit = fade()` → `"0.0,0.0,0.0,1.0,0.0,180,0,5"`
- `pop()` → `"0.0,0.0,0.0,0.9,0.0,240,0,23"`

Poses compose multiplicatively for opacity/scale and additively for offsets:
`motion.combine` (`motion.nim:162-164`). An overshooting easing (`outBack`)
overshoots position and scale but **never opacity** (`between`, line 166-170).

---

## 5. The `Easing` enum — all 35 values

`sdk/core/wire.nim:363-398`. The DSL word form is the bare enum identifier:
`ease = outBack`, `ease = easeOutCubic`.

| id | DSL word | id | DSL word |
|---|---|---|---|
| 0 | `easeLinear` | 18 | `easeInOutExpo` |
| 1 | `easeInQuad` | 19 | `easeInCirc` |
| 2 | `easeOutQuad` | 20 | `easeOutCirc` |
| 3 | `easeInOutQuad` | 21 | `easeInOutCirc` |
| 4 | `easeInCubic` | 22 | `easeInBack` |
| 5 | `easeOutCubic` | 23 | `easeOutBack` |
| 6 | `easeInOutCubic` | 24 | `easeInOutBack` |
| 7 | `easeInQuart` | 25 | `easeInElastic` |
| 8 | `easeOutQuart` | 26 | `easeOutElastic` |
| 9 | `easeInOutQuart` | 27 | `easeInOutElastic` |
| 10 | `easeInQuint` | 28 | `easeInBounce` |
| 11 | `easeOutQuint` | 29 | `easeOutBounce` |
| 12 | `easeInOutQuint` | 30 | `easeInOutBounce` |
| 13 | `easeInSine` | 31 | `easeSpring` |
| 14 | `easeOutSine` | 32 | `easeSpringGentle` |
| 15 | `easeInOutSine` | 33 | `easeSpringBouncy` |
| 16 | `easeInExpo` | 34 | `easeSpringStiff` |
| 17 | `easeOutExpo` | | |

Defaults in the SDK: `easeOutCubic` (id 5) for `animate`/`transition`/`fade`/`fly`;
`easeOutBack` (23) for `pop`/`turn`; `easeInOutSine` (15) for a bare `loop`.

**Springs (31–34) are not curves.** `motion.nim:58-63`:

```nim
proc isSpringId*(ease: int32): bool =
  ease >= int32(ord(EasingKind.easeSpring)) and ease <= int32(ord(EasingKind.easeSpringStiff))
```

A spring easing makes `Track.follow` step a damped harmonic oscillator instead of
sampling a curve (`stepSpring`, `motion.nim:78-93`, fixed 1/480 s substeps so it
lands identically at any frame rate; settles exactly and stops). It keeps its
velocity when the target changes mid-flight. A spring ignores the tween's shape
but still uses the duration as its settling window. Springs only exist for the
`transition`/`eased` tween path — `loopValue` uses `curve()` on them like any
other id.

**Name-collision trap.** The wire `Easing` enum (`sdk/core/wire.nim`) and
`EasingKind` (`protocol/easing.nim`) declare the same members at the same values.
When both modules are in scope an unqualified `ord()` is ambiguous. `motion.nim:58-63`
documents this and qualifies as `EasingKind.easeSpring`. `apps/minipaint/PORT-NOTES.md:381-384`
records this as one of the repo's recurring symbol-collision bugs. `sdk/ui/motion.nim:12`
does `from ../core/wire import Easing; export Easing`, which is the SDK's answer.

---

## 6. The frame loop — THE critical part for porting canvas animations

### 6.1 `onFrame:` — the only per-frame hook

`sdk/ui/dsl.nim:74` maps `onframe` → `evFrame`. Put it on the **app root**:

```nim
app("World", width = 640, height = 480, fill = 0x000000, pointerLock = true):
  onFrame:
    …
```

**Why the root:** `render/native/engine.nim:3230-3233`

```nim
proc wantsFrames*(e: Engine): bool =
  for k in e.s.events.keys:
    if k[1] == E_FRAME and e.s.valid(k[0]): return true
```

The host asks this to decide whether to keep feeding display frames; *any* node
with a Frame handler answers yes, so a canvas-level `onFrame:` also works — but
the app root is the convention and the one the built examples use
(`examples/shell/world.nim:27`, `apps/spiderbench/app.nim:523`).

`frameEvent` (`engine.nim:3235-3248`) runs every handler **once** per frame:

```nim
e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60
e.lastFrameAt = e.now
for id in ids: e.fire(id, E_FRAME)
e.s.mouseDX = 0; e.s.mouseDY = 0      # raw movement is consumed per frame
```

and the gate in `tick` (`engine.nim:4098`) is
`e.lastFrameAt == 0 or e.now - e.lastFrameAt >= 12` — so **at most one Frame per
12 ms**, i.e. roughly the display rate, never faster. Handler order follows
`e.s.events.keys` and is not a documented order. If one traps, the rest are
skipped (`if e.crashed.len > 0: break`).

### 6.2 Getting delta time — three ways, ONE of them live

| Call | Where | Value |
|---|---|---|
| `frameDt()` | `sdk/ui/input.nim:45` → `yInput(7, 0)` | **seconds** since the previous frame — **use this one** |
| `yantra_get_dt()` | `sdk/core/runtime.nim:75` | **always `0` under the native runner** — do not use |
| your own accumulator | — | `t += frameDt()` |

**`frameDt()` is the live clock.** It reads `host.frameDt`, which
`Engine.frameEvent` writes from the real clock immediately before firing the
handlers. The first frame returns `1/60` (`engine.nim:3241`), so `dt` is never
zero and never absurd on startup. The host answers it with a pure field read —
`host/host.nim:926`, `of 7: host.frameDt`.

> **CORRECTED 2026-10-03.** This section used to present the three calls as
> "**three ways, one value**" — that framing is wrong and dangerous, because two of
> the three return **different values**, and one of them is always zero.
> `yantra_get_dt()` does not read the engine clock. It imports a **host symbol**
> (`sdk/core/runtime.nim:75`, `{.importc: "yantra_get_dt", cdecl.}`) that returns a
> host **threadvar** `g_frameDt` (`host/host.nim:189`, read at `:194`, registered at
> `:1024`). The **only** thing in the repo that ever writes it is
> `host.setFrameDt` (`host/host.nim:1211-1213`), and `setFrameDt` appears in exactly
> two places: `render/render_qml.nim:42` (the **legacy Qt/QML** path) and
> `host/t_run_hello.nim:107, 137, 140` (a test harness). It appears **zero** times
> under `render/native/`, `cli/`, `apps/` or `web/`.
> **Consequence: on the real native runner `dt` is `0` every frame and the animation
> never moves.** It compiles, it links, it traps nothing.
> **The correct rule: use `frameDt()`. Full stop.**
>
> **`yantraFrame:` / `frameTo` is the same dead road.**
> `host/host.nim:1326` defines `frameTo`, which calls the app's `yantra_frame`
> export — and **nothing in the repo calls `frameTo`**. The SDK's own
> `yantraFrame:` macro (`sdk/core/runtime.nim:228-230`) exports
> `yantra_frame`, which the native engine never invokes; the native path is
> `onFrame:` + `evFrame` (§6.1).
>
> **The two examples the skill points at teach this pattern. Do not copy it.**
> `examples/animate.nim:31-33`:
> ```nim
> yantraFrame:
>   let dt = yantra_get_dt()      # 0.0 on the native runner — Qt-era example
>   g_t += dt
> ```
> `examples/animate2d.nim:70-72` does the same. The replacement, which is what
> §6.3 and §11 use:
> ```nim
> app("Animate"):
>   onFrame:
>     let dt = frameDt()          # seconds, from the live engine clock
>     g_t += dt
>     g_animated.opacity(0.3 + 0.7 * easeOutCubic(...))
> ```
> (The `dt` value is the *only* thing wrong with those two examples — their
> `animate(...)` calls and their easing are fine.)

### 6.3 The recipe: a continuous simulation

```nim
var t = 0'f32
app("Sim"):
  onFrame:
    let dt = frameDt()            # seconds, already clamped by the engine
    t += dt
    simState.set(simState.get + 60 * dt)   # any state.set damages and repaints
```

Rules, all verified:

1. `dt` is **seconds**, not milliseconds. Multiply by your per-second rate.
2. `dt` is **not clamped** by the engine for your app's own maths. If you want a
   hard cap after a stall, do it yourself: `let dt = min(frameDt(), 0.05'f32)`.
   (The engine does clamp its own internal dt: `stepGlides` uses
   `clamp(e.now - e.lastTick, 0, 100)` ms, `engine.nim:3137`.)
3. Frame handlers run **before** `stepPhysics`, `syncMedia` and `stepGlides`, and
   before paint, inside `tick` (`engine.nim:4077-4119`; `e.frameEvent()` at `:4099`,
   `e.stepPhysics()` at `:4100`, `e.syncMedia()` at `:4105`, `e.stepGlides()` at
   `:4117`).
4. Changing a `state` (or any node prop) from `onFrame:` marks the node dirty and
   the window repaints. This is the whole redraw mechanism for canvas work.
5. **Testing trap (measured, `apps/minipaint/ENGINE-ISSUES.md:1049-1098`).**
   `Engine.tick` does `e.now = max(e.now, ms)` — the clock only moves **forward**.
   `tick(1000.0)` ten times advances time once, and then
   `e.now - e.lastFrameAt >= 12` can never become true again: **your app gets
   exactly one frame and every timing assertion becomes vacuous.** Drive a test
   with `tick(i * 16.0)` or a `tickN(n, ms)` helper.
6. `apps/minipaint/ENGINE-ISSUES.md:1193-1213` (**E4**): `pointerIsLocked()` is
   permanently false — `host.pointerLocked` is read by `cbNodeSize` but never
   assigned. Read `e.s.pointerLocked` if you need it in a test; in an app, track
   your own flag from Escape/click (as `apps/spiderbench/app.nim` does).

### 6.4 Reduced motion

`engine.nim:4145` sets it:
`reducedMotion: getEnv("YANTRA_REDUCED_MOTION") notin ["", "0"]`.
When true: `transMs` is 0 (every `transition` is instant), `enter`/`reveal`/
loops/parallax are skipped, scroll does not glide, and an idle app stops
painting (`render/native/t_motion.nim:148-165` asserts exactly this). **Write
apps that still work with motion off.**

---

## 7. Enter, exit, reveal, smooth

### 7.1 `enter` / `exit`

- `enterAt[id]` is stamped on first placement, but **only after the first layout
  and only if motion is not reduced** (`engine.nim:1045`:
  `if e.placedOnce and not e.reducedMotion: e.enterAt[c] = e.now`).
- `motion.entering(s, t0, now)` = `s.between(curve(ease, progress(t0+delay, ms, now)))`
  — during `delay` the node sits at the spec's far pose, verified by
  `t_motion.nim:178`.
- `exit` plays on a **Ghost**: the node is already removed from the tree but is
  still drawn while the exit runs (`engine.nim:1383-1385`,
  `ghostCount*(e)`, and `motion.done(s, t0, now, withDelay = false)` — the exit's
  `delay` is ignored, it is already gone).
- A node does **not** animate into existence unless it asks to, with `enter`:
  `Track.seen` is false until the first target arrives and the first target is
  taken as-is (`render/native/motion.nim:15-22, 98-99`).

### 7.2 `reveal` — scroll-linked, not timed

`engine.nim:2028-2040`:

```nim
if (n.has(P_REVEAL) or n.has(P_PARALLAX)) and not e.reducedMotion and not e.exporting and id in e.boxes:
  …
  if n.has(P_REVEAL):
    let spec = parseSpec(n.sProp(P_REVEAL))
    let p = clamp((bottom - b.y) / (viewH * 0.25), 0, 1)     # the bottom quarter of the view
    result = combine(result, spec.between(curve(spec.ease, p)))
  if n.has(P_PARALLAX):
    result.y += (b.y + b.h/2 - (top + bottom)/2) * n.num(P_PARALLAX, 0)
```

- Tied to **scrolling**, not time. `ms` and `delay` in the `Motion` are unused;
  only `ease` shapes it — exactly as `sdk/ui/motion.nim:58-60` says.
- A node **above** the bottom quarter of the visible area is at `p = 1`, i.e.
  fully itself. Scroll away and it goes back.
- Same block handles `parallax = <float32>`: a fractional vertical offset from
  the viewport centre.
- Needs `id in e.boxes`, so it only works on a laid-out node, and is skipped
  while `e.exporting` (film render).

### 7.3 `smooth`

`pSmooth` (176) is a **boolean on any node that opts into smooth scrolling** —
not a general motion setting. `engine.nim:1500-1502`:

```nim
if abs(y - was) > 0.01 and n.flag(P_SMOOTH) and e.placedOnce and not e.reducedMotion and asked:
  e.glides[c] = Glide(target: y, lastInput: e.now)
```

`asked` means the app asked for the scroll (`scrollTo = y`, `engine.nim:1493-1498`).
So: **`smooth = true` + `scrollTo = y` glides there; anchoring/keyboard scrolling
is never smoothed.** The glide is exponential decay `1 - exp(-dt/70)` per tick and
snaps when within 0.5 px (`stepGlides`, `engine.nim:3143-3145`). Touch coasting
(`e.smoothScroll`) is engine-wide and separate.

---

## 8. Interaction micro-animations

There is **no DSL prop** called `hoverScale` / `pressFill` / `hoverY`. They exist
as wire props (`pHoverFill 122`, `pHoverColor 123`, `pHoverBorder 124`,
`pHoverOpacity 125`, `pPressFill 126`, `pPressColor 127`, `pPressBorder 128`,
`pPressOpacity 129`, `pFocusFill 130`, `pFocusColor 131`, `pFocusBorder 132`,
`pFocusOpacity 133`, `pHoverScale 137`, `pPressScale 138`, `pFocusScale 139`,
`pHoverY 140`, `pPressY 141`, `pFocusY 142`) and **none of them appear in
`protocol/props.md`**, which is the generated table the DSL validates against
(`sdk/ui/dsl.nim:203` errors `Y001 unknown prop` otherwise).

They are set through the **`hover:` / `pressed:` / `focused:` state blocks**
(`sdk/ui/dsl.nim:578` → `stateBlock`), which is the form the SDK tests use
(`sdk/tests/t_style.nim:61-69`):

```nim
btnNode = button("Go", fill = theme().surface):
  hover:
    fill = theme().surface2
  pressed:
    fill = theme().surface3
    opacity = 0.9
  focused:
    borderColor = theme().accent

motionNode = panel(transition = 200, ease = outBack, …):
  hover:
    scale = 1.05
    y = -2
```

Verified wire results (`t_style.nim:78-79, 99, 147`):
`hover: fill` → `pHoverFill`; `pressed: opacity` → `pPressOpacity`; `hover: scale`
→ `pHoverScale = 1.05`; `hover: y = -2.px` → `pHoverY = -2.0`.

**Exactly six props are legal inside a state block** (`sdk/ui/dsl.nim:233-242`,
a `case` on the lower-cased name; anything else is a **compile error**):

```nim
# Y013 '<name>' can't change with state — use fill, color, borderColor, opacity, scale or y
```

| In a state block | Wire prop suffix | Wire type |
|---|---|---|
| `fill` | `Fill` | `int32` (a colour) |
| `color` | `Color` | `int32` |
| `borderColor` | `Border` | `int32` |
| `opacity` | `Opacity` | `float32` |
| `scale` | `Scale` | `float32` |
| `y` | `Y` | `float32` (wrapped in `lengthOf`, so `-3.px` works) |

combined with the three block names `hover` / `pressed` / `focused`
(`stateBlocks`, `dsl.nim:223`) — 18 wire props, which is exactly the 18 in
`wire.nim:178-198`. Anything else (`border`, `radius`, `width`, `x`, `fontSize`,
…) is a compile-time `Y013`.

**Which blocks the engine honours** (`engine.nim:2018-2021`):

- **scale**: only `pHoverScale` / `pPressScale` / `pFocusScale`, multiplied into
  the node's base scale. If the node has **none** of the three, the block is
  skipped entirely.
- **y**: only `pHoverY` / `pPressY` / `pFocusY`, **added** to the node's base y
  (a lift). Not a replacement.
- **fill / colour / border / opacity** go through `e.stateColor(id, n, base, P_HOVERFILL, P_PRESSFILL, P_FOCUSFILL)`
  and then `eased(…, cFill / cInk / cBorder)` — so they are **only eased, never
  moved or scaled**, and they only glide when the node also has a `transition`.

**To react in code** rather than by style, read the state through a handler:
`onPointerDown`/`onPointerMove`/`onPointerUp` plus your own `state`, or
`onFocus:`/`onBlur:`. There is no `isHovered()` query — hover is expressed as a
visual state only.

The precedence the engine uses is press → focus → hover → base
(`stateNum(id, n, default, P_HOVERSCALE, P_PRESSSCALE, P_FOCUSSCALE)`).
**The resolution order inside `stateNum` is closed in source** —
`render/native/engine.nim:1651-1655`, in full:

```nim
proc stateNum(e: Engine; id: int32; n: tree.Node; base: float32; hoverP, pressP, focusP: int32): float32 =
  if e.isPressed(id) and n.has(pressP): return n.num(pressP, base)
  if e.focus == id and n.has(focusP): return n.num(focusP, base)
  if e.hovered(id) and n.has(hoverP): return n.num(hoverP, base)
  base
```

Three things follow that matter for a three-way overlap:

1. **Strict first-match-wins, checked in the order press → focus → hover.** The `if`s have no
   `elif` but each `return`s, so an earlier match always wins.
2. **Each branch is guarded by `n.has(...)`.** If the node has *no* `P_PRESSSCALE` at all, the
   press branch is skipped and the next one is tried — it does **not** fall through to "base
   because a state is active". A node with only `focusScale` and `hoverScale` still resolves
   the focus value while focused.
3. **`base` is the fallback for every slot**, both when nothing matches and when the winning
   prop is read with `n.num(p, base)`.

`opacityOf` (`engine.nim:1645-1649`) is written the same way but with `elif`, and gives the same
press → focus → hover order.

---

## 9. Steps in time: `after`, `afterMs`, `timeline:`

Two different `timeline` symbols exist. **They collide if you import both
modules unqualified.**

### 9.1 `sdk/ui/motion.nim` — steps on the engine's clock

```nim
proc afterMs*(ms: float32; body: proc())
template after*(delay: untyped; body: untyped)      # `after 1.2.s: …`
macro timeline*(body: untyped): untyped              # `timeline:` block
```

```nim
timeline:
  at 0.4.s: scene.set(1)      # at a time from now
  then 600.ms: scene.set(2)   # after the step before it
```

The macro rewrites to a chain of `afterMs` calls on one accumulator `t`; each step
runs once, batched like an event handler, on the engine's clock. `durationOf` is
what parses `.s` / `.ms` literals (see `sdk/ui/units.nim`).

### 9.2 `sdk/motion/timeline.nim` — a deterministic sampler (no clock)

```nim
proc newTimeline*(): Timeline
proc duration*(tl: Timeline): float32        ## returns maxDuration, in SECONDS
proc setInitial*(tl: Timeline, target: PropTarget, val: float32)
proc to*(tl: Timeline, target: PropTarget, endVal: float32, d: Duration,
         easing: EasingKind = easeLinear)
proc to*(tl: Timeline, target: PropTarget, endVal: float64 | int, d: Duration, easing = easeLinear)
proc to*(tl: Timeline, target: string, endVal: float32 | float64 | int, d: Duration, easing = easeLinear)
proc wait*(tl: Timeline, d: Duration)
proc all*(tl: Timeline, tracks: varargs[proc(sub: Timeline)])
proc loop*(tl: Timeline, count: int, body: proc(sub: Timeline))
proc sample*(tl: Timeline, t: float32, target: PropTarget): float32
proc sample*(tl: Timeline, t: float32): Table[PropTarget, float32]
proc sample*(tl: Timeline, d: Duration, target: PropTarget): float32
proc sample*(tl: Timeline, d: Duration): Table[PropTarget, float32]

type Duration* = object
  millis*: float32
proc ms*(v: float32 | float64 | int): Duration   # raises TimelineError "Y051" on negative
proc s*(v: float32 | float64 | int): Duration
proc toMillis*(d: Duration): float32
proc toSeconds*(d: Duration): float32
```

Semantics (all from `timeline.nim:53-115`):

- `to` **chains**: it starts from `lastTrackEnd[target]` if the same `PropTarget`
  was tweened before, else from `initialValues`, else from sampling the timeline
  at the current time. It also advances `currentTime` by `d`.
- `wait(d)` just advances `currentTime`.
- `all(trackA, trackB, …)` runs branches **from the same branch start** and
  leaves `currentTime` at the longest one — true parallel composition.
- `loop(count, body)` repeats `count` times; `count < 1` raises
  `TimelineError("Loop count must be >= 1")`, and the `loop:` macro form errors
  with **`Y050 infinite loop not allowed in scene/film`** — an infinite timeline
  loop is refused at compile time.
- `sample(t, target)` walks **every** tween for that target in order and takes
  the last one that covers `t`; before the first it returns
  `initialValues[target]` (default `0.0`). `t` is in **seconds**.
- `PropTarget` is `(targetId: int32, propName: string)`; a bare `string`
  auto-converts via `converter toPropTarget` and gets `targetId = 0`.
  `$p` renders as `#<id>.<name>` when `targetId != 0`, else just the name.

**This module never talks to the engine.** It is pure maths over `EasingKind`
(`protocol/easing.nim`), which makes it ideal for a *film* (a fixed, reproducible
sequence that must land on exact frame times) and for tests. To play it back,
sample it in `onFrame:` and push the numbers into props or a canvas.

**Time is SECONDS everywhere except `Duration`.** `Duration` is in millis, but
`duration(tl)` returns `maxDuration`, which accumulates `toSeconds`
(`timeline.nim:50, 56-65`), and `sample(t, …)` takes seconds. This is measured,
not inferred — `tl.duration` after `300.ms + 200.ms` is `0.5'f32`, and
`tl.sample(250'f32, …)` (250 *seconds*) is past the end and returns the final
value, while `tl.sample(0.25'f32, …)` is mid-flight.

```nim
let tl = newTimeline()
tl.to("x", 400'f32, 300.ms, easeOutCubic)
tl.to("x", 0'f32, 200.ms, easeInBack)
# tl.duration == 0.5 (SECONDS); tl.sample(0.25'f32, propTarget("x")) is mid-flight
```

### 9.2.1 The `timeline:` macro — the form to actually use

```nim
let tl = timeline:
  x.to 400'f32, 300.ms, easeOutCubic
  x.to 0'f32, 200.ms, easeInBack
  wait 50.ms
# tl.duration == 0.55
```

`macro timeline*(body: untyped)` builds `newTimeline()`, rewrites each step and
returns the timeline (`timeline.nim:149-155`). Only three words are recognised:

| Written | Rewritten to |
|---|---|
| `wait 50.ms` | `tl.wait(50.ms)` |
| `loop 3: <body>` | `for i in 0 ..< 3: <body>` |
| `<target>.to v, d, easing` | `tl.to(<target>, v, d, easing)` |
| anything else | passed through unchanged |

Two traps that are compile errors, both verified by trying them:

- **`to` must be written as a dot-call on the target** (`x.to …`), because
  `transformTimelineStmt` only matches `nnkDotExpr` whose last name is `to`
  (`timeline.nim:143`). A bare `to x, 400, 300.ms` falls through unchanged and
  fails to resolve.
- **`all` with anonymous proc literals only type-checks inside a proc body.**
  `varargs[proc(sub: Timeline)]` is a closure type, and at module top level the
  lambda's inferred proc type does not unify with it — `Error: type mismatch`.
  Named top-level procs fail too (`'.closure' calling convention for top level
  routines is invalid`). Write it in a proc:

```nim
proc buildTracks() =
  let a = propTarget("a"); let b = propTarget("b")
  var tl = newTimeline()
  tl.setInitial(a, 0.0'f32); tl.setInitial(b, 10.0'f32)
  tl.all(
    proc(sub: Timeline) = sub.to(a, 100.0'f32, 1.s, easeLinear),
    proc(sub: Timeline) = sub.to(b, 50.0'f32, 1.5'f32.s, easeLinear)
  )
  doAssert tl.duration == 1.5'f32     # the LONGER branch wins
  doAssert tl.sample(1.0'f32, a) == 100.0'f32
```

  This is exactly how `sdk/motion/tests/t_timeline.nim:50-71` is written, and it
  **passes**. `loop(count, proc(…))` takes a single non-vararg closure and is
  fine anywhere.

Every claim in §9.2 above was checked by running it (Nim 2.2.10,
`--path:sdk/motion`, plus the repo's own `sdk/motion/tests/t_timeline.nim`:
`PASS t_timeline`).

---

## 10. Honest limits — what CANNOT be animated

Verified against `render/native/motion.nim` and `render/native/engine.nim`.
Everything below is a real, measured constraint, not a caution.

| Wanted | Status | Why (source) | Do this instead |
|---|---|---|---|
| `animate("width", …)`, `animate("height", …)` | **silently does nothing** | `poseOf` (`motion.nim:207-215`) has no case; `else: discard`. The SDK doc comment at `yantra.nim:443` wrongly lists them. | Animate `scale`, or drive `width`/`height` from `onFrame:`. |
| `animate("color"/"fill", …)` | not a legal target | `poseOf` has no colour case | `transition = 200` (§2) eases fill/ink/border by colour. |
| Path morphing / SVG `d` interpolation | not supported | `pPathData` (`d`) is a plain string prop; no morph in any engine file | Draw both paths with `Draw().svgPath(...)` and cross-fade with `alpha(...)` or `opacity`, or morph on a canvas in `onFrame:`. |
| Animating a non-scalar (a string, a list, a gradient's stops) | not supported | every motion track is `float32` or `uint32` (`Track`, `ColorTrack`) | Keep the *index* in a float and `state.set` the thing. |
| `animate("rotate", …)` vs `animate("rotation", …)` | both legal | `poseOf` matches `of "rotate", "rotation":` | `animate = spin()` uses `"rotate"`. |
| `animate("border", "radius", "fontSize", …)` | not legal | `poseOf` has no case; the pose channels are only opacity/x/y/scale/rotate | Change the prop from `onFrame:` with a `transition` if it is a colour, or a spring if it is a number. |
| Animating layout (`width` changing → siblings reflowing) | not tweened | `transition` only reaches the eight slots in §2; layout is Yoga's and snaps | `animated = false` scroll, or `onFrame:` + a `width` state. |
| `animate` on a node **inside** a scrolled area, coordinated with scroll | no | `reveal` is the scroll-linked one; `animate` is clock-only | Use `reveal` / `parallax`, or compute in `onFrame:`. |
| Re-firing a declarative animation on click/hover/focus | not available | `pAnimTrigger` is read only by `render/qmlgen.nim` | `hover:`/`pressed:`/`focused:` + `transition` (§8). |
| Frame-accurate "time" for a film | no `performance.now` | only `frameDt()` and `after`; the engine clock is monotonic and only the harness can force it | `sdk/motion/timeline.nim` + `onFrame:` sampling (§9.2). |

**The universal workaround**, and the one miniPaint-style ports use: put the
simulation in `onFrame:`, keep the numbers in `state`, and let a `canvas(draw = …)`
prop that reads that state re-emit its command list. See §11.

---

## 11. A complete example

Two things in one app: a button that animates on hover, and a canvas with a
continuous animation driven by the frame loop. Every API used here is one read in
the sources listed at the top of this chapter. (`cos`/`sin` come from
`import std/math` — the SDK does not re-export `system.math`.)

The `@go` / `@halo` / `@below` / `@stage` names are **runtime labels** (the wire
prop `pName`), useful for hot reload, inspectors and tests — they are *not* Nim
identifiers. To name a node in code, write `nameNode = node(…)` with
`var nameNode: Node` declared before the `app` block (see chapter 11 §5).

```nim
## Buttons that lift on hover, and a canvas with a continuous frame-loop animation.

let t = state 0'f32          # seconds since the app started
let mx = state 0'f32         # the pointer, in the canvas's own pixels
let my = state 0'f32
let dragging = state false
let dot = state 0'f32        # the dot's angle

app("Motion", width = 560, height = 360, fill = 0x141824):
  ## Per-frame callbacks live on the app root. dt is in SECONDS.
  onFrame:
    t.set(t.get + min(frameDt(), 0.05'f32))   # dt from the engine clock
    dot.set(dot.get + 90'f32 * frameDt())     # 90 deg/s

  column(gap = 12.px, pad = 16.px):

    ## 1. Hover lift. `transition` makes EVERY change on this node glide:
    ##    fill, ink, border, opacity, hover scale and hover lift.
    button @go("Hover me", fill = 0x2A3550, radius = 10.px,
               transition = 220, ease = outBack,      # ms + curve
               enter = fade(ms = 200),
               exit = fade(ms = 140),
               animate = spin(ms = 1400)):            # loops until removed
      hover:
        fill = 0x3D5A8C
        scale = 1.04
        y = -3
      pressed:
        fill = 0x1B2436
        scale = 0.97
      focused:
        borderColor = 0x7AA2F7
      onClick:
        mx.set(mx.get)

    ## 2. A looping "breathe" — the declarative loop form, forever.
    panel @halo(width = 200.px, height = 24.px, radius = 12.px,
                fill = 0x7AA2F7, animate = breathe(scale = 1.03, ms = 1600))

    ## 3. Scroll-linked reveal: tied to scrolling, not to time.
    panel @below(width = 400.px, height = 40.px, fill = 0x243046,
                 reveal = fly(y = 30))

    ## 4. The continuous canvas. `draw` is re-read every paint, and the
    ##    expression reads state, so the effect re-runs when the state changes.
    canvas @stage(width = 520.px, height = 200.px,
                  draw = Draw()
                            .rect(0, 0, 520, 200, 0xFF101725'u32)
                            .line(mx.get, my.get, mx.get + 24, my.get + 24,
                                  0xFF7AA2F7'u32, 2'f32)
                            .circle(260 + 200 * cos(dot.get * 0.0174533),
                                    100 + 200 * sin(dot.get * 0.0174533),
                                    12, 0xFFFFB86B'u32)
                            .cmds):
      onPointerDown:
        ## pointerPos() is in THIS node's own pixels.
        let (x, y) = pointerPos()
        mx.set(x); my.set(y); dragging.set(true)
      onPointerMove:
        let (x, y) = pointerPos()
        if dragging.get:
          mx.set(x); my.set(y)
      onPointerUp:
        dragging.set(false)
```

Checklist for a frame-loop app:

- `onFrame:` on the app root. `dt = frameDt()` in seconds — **not** `yantra_get_dt()`
  (§6.2; that one reads 0 under the native runner).
- `state.set(...)` is what marks the tree dirty and causes the repaint.
- `canvas(draw = <expression reading state>.cmds)` re-emits each time.
- Every colour literal in a `Draw` list needs its **`0xFF…` alpha byte**
  (`0xFF7AA2F7'u32`, not `0x7AA2F7'u32`) — `Draw` has no alpha promotion, so a bare
  6-digit hex draws nothing at all. Node `fill = 0x7AA2F7` is fine and is *not* the same
  trap; see `07-color-gradients-and-effects.md` §1.
- `pointerPos()` inside a pointer handler is in the **node's** pixels.
- Prefer `transition` + `hover:`/`pressed:`/`focused:` over `animate(trigger=…)`;
  the latter does not fire on interaction.
- Anything the five `animate` targets cannot express belongs in `onFrame:`.

**This example is compile-verified.** It was built with Nim 2.2.10 against
`sdk/` using the headless harness from `sdk/tests/t_style.nim`
(`nim c --path:<repo>/sdk`, all `y_node_*` / `y_input` / `y_node_size` /
`yantra_get_dt` imports stubbed) and ran clean: *6 nodes created, no errors*.
That check caught one real mistake worth remembering — `focused: border = 2.px`
is a compile error (`Y013`); `borderColor` is the only border prop a state
block accepts.

> **What that harness could not have caught.** `sdk/tests/t_style.nim:25` stubs
> `proc yantra_get_dt(): float32 {.exportc, cdecl.} = 0.016'f32` — the same
> hard-coded value appears in every `sdk/tests/` stub. A compile-only harness
> therefore makes the dead `yantra_get_dt()` path look *plausible* (0.016 is a
> believable frame time) when under the real native runner it is **0.0**
> (§6.2). **Compiling against the stubs does not validate the clock.** Only a
> real `drive.exe`/window render does, and the only instrument that shows it is
> the pixels — `log()` never prints (`17-pitfalls.md` §9a).
