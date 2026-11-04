# 16 — What the engine cannot do yet, and the workaround for each

**Audience:** an agent about to port HTML/CSS, Canvas 2D, Web Audio or Three.js into Yantra.

**The one rule that decides every question in this chapter** (`AGENTS.md` rule 6):

> *The SDK only promises what the renderer draws.*

If a prop exists in the SDK and no mapping in `render/native/engine.nim` (~190 KB, the live
renderer) draws it, **it does not exist**. Before you use any prop below, check the renderer.

> **Reading a `t_*.nim` citation in this chapter.** Six of the test names that appear here are
> names of tests that **do not exist yet** — they are the *proposed* file to write alongside each
> fix, in a "Where it would live (renderer + test)" or "Fix" column, never a claim that a suite
> exists. They are: `render/native/t_paint_arc.nim`, `t_paint_path.nim`, `t_paint_alpha.nim`,
> `t_font.nim`, `t_assetready.nim`, `t_select.nim`. Every other `t_*.nim` named here was checked
> against the tree and exists. If a row cites a test with no "new" marker, that suite is real —
> and if it is not, that row is a bug worth reporting.

**Sources.** Every claim here is traceable to one of:

| Tag | File | What it is |
|---|---|---|
| `[EI]` | `apps/minipaint/ENGINE-ISSUES.md` | ~73 KB catalogue of engine limitations measured while porting miniPaint. Primary source. |
| `[PN]` | `apps/minipaint/PORT-NOTES.md` | ~133 KB of porting notes; limitations, workarounds and closed gaps. |
| `[GAPS]` | `docs/agent-guide/gaps.md` | The explicit known-gaps doc (26 lines, read it fully). |
| `[WEB]` | `docs/agent-guide/from-web.md` | HTML/CSS/JS → Yantra mapping. |
| `[CV]` | `docs/agent-guide/from-canvas-audio-input.md` | Canvas 2D / Web Audio / input mapping. |
| `[3D]` | `docs/agent-guide/from-three.md` | Three.js → Yantra 3D mapping. |
| `[CMP]` | `docs/compare-web.md` | Honest feature-by-feature comparison with the web (dated 2026-09-26). |

`[CMP]` is the **oldest** document here. Several things it lists as missing are built and tested
today — see §4. Never quote `[CMP]`'s §2 "where the web still wins" list as current truth without
checking §4 of this chapter and `docs/roadmap.md` §1 ("Built so far").

---

## 1. Master table — NOT SUPPORTED YET

Status values: **WORKS** (renderer draws it, test proves pixels) · **PARTIAL** (draws in some
cases) · **NOT SUPPORTED YET** (no renderer mapping) · **BROKEN** (exists but misbehaves; the
app must work around it).

| Feature | Status | Closest workaround | Difficulty to add | Where it would live (renderer + test) |
|---|---|---|---|---|
| `canvas` 2D draw list (`Draw` verbs) | **WORKS** | — | — | `render/native/engine.nim`; `t_paint.nim` `[CV]` |
| Canvas `arc()` at sweep ≥ 180° | **BROKEN** | Split into two 180° arcs, each with its own `moveTo`; second half starts at 180° | Low — split the sweep in the shim | `libs/nimskia/src/skia_shim.cpp` `arcTo`; new test `render/native/t_paint_arc.nim` (does not exist yet) `[EI §3]` |
| Fill-then-stroke on one path (`F` then `S`) | **BROKEN** | Replay the path for the stroke (changes translucency compositing order — a parity risk) | Low — a commit verb that keeps the path | `skia_shim.cpp` `case 'F'`; new test `render/native/t_paint_path.nim` (does not exist yet) `[EI §4]` |
| Canvas `arcTo` with no current point | **BROKEN** | Emit an explicit `moveTo` before every `A` | Low | `skia_shim.cpp`; new test `t_paint_arc.nim` (does not exist yet) `[PN "Two Skia gotchas"]` |
| `globalAlpha` scoped to one op | **BROKEN** | Alpha is **multiplicative and sticky**: `O 0.3` dims every later command. Reset with balanced `P`/`p` save/restore, never `O 1.0` | Low — make `O` assign, or push onto the state stack | `skia_shim.cpp` `case 'O'`; new test `t_paint_alpha.nim` (does not exist yet) `[EI/PN "Three engine-level drawing traps"]` |
| **A bare CSS hex passed to any `Draw` colour argument** | **BROKEN** — compiles, runs, invisible | Force the alpha byte: `proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)` | Low — normalise in `runCmds`, exactly as `engine.nim` does for node props | `sdk/ui/paint.nim:53,55,57,59,61,63,65,46`; `skia_shim.cpp:1327`; cf. `render/native/engine.nim:345-348` |
| **Measuring a string inside a `canvas`** | **NOT SUPPORTED YET** | Hand-build an advance table (miniPaint did: `config.arial12`), or estimate, or use a `text` node | Medium — expose the native `measureText` to the SDK | `sdk/ui/paint.nim:63` (no `align`, no measure); native side `libs/nimskia/src/nimskia.nim:68,:122` |
| **Axis-aligned ellipse in a `Draw` list** | **PARTIAL** | `circle` emits rx = ry = r; use four `curveTo` (`paint.nim:35`) or an `svgPath` | Low — an `ellipse` proc | `sdk/ui/paint.nim:59`; `skia_shim.cpp` `case 'E'` |
| **Filled polygon in a `Draw` list** | **WORKS** — it is the canvas idiom, not a gap | `moveTo`(`:28`) → `lineTo`(`:29`) → `close`(`:45`) → `fill`(`:53`) | — | `sdk/ui/paint.nim:28,29,45,53` |
| CSS `clip-path` / arbitrary clip shapes | **PARTIAL** | `.clip(x, y, w, h)` — rectangular only | Medium | `engine.nim`; `t_paint.nim` |
| Text selection, copy/paste, IME, multi-line edit | **WORKS** (per `roadmap.md` §1 "text editing (T1)") | — | — | `engine.nim`; `t_text.nim`, `t_richtext.nim`, `t_spell.nim` |
| Web font loading / `@font-face` | **NOT SUPPORTED YET** | Use a system-family name (`font = …`); a web page's `@font-face` cannot be honoured | High — font manager + SkTypeface per node | `engine.nim` text mapping; new test `render/native/t_font.nim` (does not exist yet) |
| Kerned advance measurement from the SDK | **PARTIAL** | Port an advance table yourself (miniPaint hand-built `config.arial12` hmtx sums) | Medium | `engine.nim` text measure; `t_character.nim` `[PN "menu bar is the kerned Arial advance"]` |
| Inline SVG path data from a command stream | **WORKS** — via the `V` verb | `Draw.svgPath` (added for the cog shape) | — | `skia_shim.cpp` `runCmds`; `t_paint.nim` `[PN "The V verb"]` |
| WEBP decode for 3D textures | **NOT SUPPORTED YET** | Export the texture as PNG | Low — link a decoder | `libs/nimfilament/src`; `t_scene3d.nim` `[EI E7]` |
| WEBP / JPG **export** (PNG/BMP/TIFF/GIF/JSON fine) | **NOT SUPPORTED YET** | Offer the row, refuse with upstream's reason string, write no bytes | Medium — bind `SkWebpEncoder`/`SkJpegEncoder` | app-side today; `t_saveenc.nim` `[EI M4]` |
| Non-PNG image **decode** on open | **NOT SUPPORTED YET** | PNG only; every other format is refused with a stated reason | Medium | app `imagedec.nim`; `t_imagedec.nim` `[PN "File > Open"]` |
| "Asset decoded and ready" signal | **NOT SUPPORTED YET** | Draw 3D assets only after a delay, or accept one black frame | Medium — a callback from the asset pipeline | `engine.nim` asset path; new `render/native/t_assetready.nim` `[EI E8]` |
| IBL / image-based lighting (metal looks near-black) | **NOT SUPPORTED YET** | Raise `ambient` (lux) so metal is lit at all | High — `.ibl` in `filament_shim.cpp` | `libs/nimfilament/src/filament_shim.cpp:887`; `t_light.nim` `[EI E9]` |
| `alphaMode` / `alphaCutoff` on a **textured** 3D mesh | **BROKEN** — passed to the surface, ignored | Use `opacity < 1` (blended), never `alphaMode = 2` | Medium | `render/native/scene3d.nim:119-120`; `t_scene3d.nim` `[EI E6]` |
| Motion blur, SSGI, god rays, chromatic aberration, custom full-screen passes | **NOT SUPPORTED YET** | Leave them out; keep TAA, AO, bloom, DoF, SSR, grading, vignette | High | `scene3d` post stack; `t_gpu.nim` `[GAPS]` |
| Per-mesh render order (`renderOrder`, `depthWrite: false`, `polygonOffset`) | **NOT SUPPORTED YET** | Blended meshes sort by distance; move decals a few mm off the surface | High | `scene3d.nim`; `t_scene3d.nim` `[GAPS]` |
| Parenting 3D objects (mesh inside a moving group) | **NOT SUPPORTED YET** | Compute children's world poses in `onFrame`, or use instance matrices | Medium | `scene3d.nim`; `t_physics.nim` `[GAPS]` |
| Morph targets (blend shapes) | **NOT SUPPORTED YET** | Only if the glTF clip animates them | High | `scene3d.nim`; `t_scene3d.nim` `[GAPS]` |
| Per-instance shader data beyond one colour | **NOT SUPPORTED YET** | Pack it into RGBA, or use `uniforms` | Medium | `scene3d.nim`; `t_particles.nim` `[GAPS]` |
| Compressed glTF (meshopt, Draco) | **PARTIAL** — decoders linked, untested | If a model fails to load, export it uncompressed | Low (test it) | `scene3d.nim` loader; `t_scene3d.nim` `[GAPS]` |
| Hinge joints from the SDK (engine has them) | **NOT SUPPORTED YET** | Ask for `hinge(...)` to be exposed | Low | `libs/nimfilament`; `t_physics.nim` `[GAPS]` |
| Filters / 3D positional audio on **file** sounds | **NOT SUPPORTED YET** | `synth` for generated sound; plain playback for files | Medium | `sound_app.nim`; `t_sound.nim` `[GAPS]` |
| `.ogg` sound files | **NOT SUPPORTED YET** | Convert to `.mp3` or `.flac`, keep the name | n/a | `sound_app.nim`; `t_sound.nim` `[GAPS]` |
| App-level clipboard read/write API | **NOT SUPPORTED YET** | Text fields copy/paste on their own (Ctrl+C/V) | Low | `engine.nim`; `t_keys.nim` `[GAPS]` |
| Raw mouse-wheel values in a game loop | **NOT SUPPORTED YET** | None. Scroll areas scroll themselves; read input in `onFrame` | Low | `engine.nim` input; `t_keys.nim` `[GAPS]` |
| `0x00RRGGBB` as a colour value on a **node prop** | **NOT SUPPORTED YET** — reads as **opaque** | Use `opacity = 0` on the node. `render/native/engine.nim:345-348` `proc argb(v: int32)` promotes a zero alpha byte to `0xFF` | Low — a way to spell "no fill" | `render/native/engine.nim:345-348`; `t_paint.nim` `[GAPS]` |
| `0x00RRGGBB` as a colour value on a **`Draw` verb** | **BROKEN** — fully transparent, i.e. invisible | Force the byte: `hex(0xF7F9FB)` | Low | `sdk/ui/paint.nim:53,55,57,59,61,63,65,46`; `skia_shim.cpp:1327`; §2.1 F |
| `formatFloat` inside apps (prints `%*f`) | **NOT SUPPORTED YET** | Format numbers yourself (`sdk/ui/paint.nim` `f()`) or use `$x` | Low | SDK string path; `t_engine.nim` `[GAPS]` |
| Websites / `<iframe>` of other sites inside an app | **NOT SUPPORTED YET** | None. `appview "other.wasm"` embeds a **Yantra** app only; a native WebView is planned | Very high | new renderer node; `t_apps.nim` `[GAPS]` `[WEB]` |
| Key handlers on a **child** node | **BROKEN** — dispatch is ancestor-only | Register `onKey` on the **app root**, as a sibling of `canvas` | Low — descend the focus tree | `render/native/engine.nim` `proc key*`; `t_keys.nim` `[EI "Key dispatch is ancestor-only"]` |
| `pointerIsLocked()` on the wasm host | **BROKEN** — permanently false | `app(…, pointerLock = true)` and assume lock from the app's own flag | Low | `host/tree.nim:73`, `host/host.nim:927`; `t_keys.nim` `[EI E4]` |
| A test that advances time with a constant `tick` | **BROKEN** — measures one frame | Use a `tickN(n, ms)` helper advancing by a delta (`e.tick(e.now + ms)`) | Low (harness, not the engine) | `engine.nim:4071`; `t_blocks.nim`/`t_call.nim`/`t_capture.nim`/`t_character.nim` do it right `[EI E1]` |
| Layer `read`/`write`/`filter` under the old pointer-width gate | **BROKEN (fixed in branch, needs `sdk/` review)** | Gate is now on whether a rasteriser is linked, not `sizeof(pointer)` | — | `sdk/ui/paint.nim`; `t_paint.nim` `[EI §2]` |
| File pick on the **web** target | **BROKEN** — every pick verb returns `-1` | Native host only (`host/host.nim:1058` registers `y_pick_open`) | Medium | `web/runner/runner.js:152-157`; `t_mpopen.nim` `[PN "File > Open"]` |
| Selection rectangle / constrained-op semantics (2D app feature) | **NOT SUPPORTED YET** | App-level: the click falls through to the brush path | High | app-side; a new test `t_select.nim` (does not exist yet) `[PN "Still open"]` |
| `wasm32` float predicates (`isnan`, `isinf`, `fpclassify`) and `math.round` | **NOT SUPPORTED YET** — link error | Integer arithmetic (`quant255`, `jsMathRound`, local `ffloor`); NaN via exponent bits | Low (header wrappers) | `sdk/minilibc/include/math.h`; `t_engine.nim` `[EI E2]` |
| `float64` arithmetic at wasm32 | **BROKEN** — silent wrong answers, not a link error | Stay in `float32`; `t_app_intact` is a source tripwire for the ban | Low | `sdk/minilibc`; app tests `[EI E2]` `[PN "wasm32 float64 is a trap"]` |

---

## 2. Subsystems

Each entry: **asked for → what happens → exact workaround → exact fix location.**

### 2.1 2D canvas & `Draw`

**A. `arc()` with a sweep of 180° or more — BROKEN**
- **Asked for:** canvas `ctx.arc(w/2, radius, radius, 0, 2*PI)` (miniPaint's `human` shape).
- **Happens:** `SkPathBuilder::arcTo(rect, start, sweep, forceMoveTo)` is **undefined** when
  `sweep >= 180`; the shim passed it straight through, so a full circle renders as *nothing*.
  Neither problem is visible in the command string — only in a screenshot. `[EI §3]`
- **Two** separate facts, both required:
  1. a sweep ≥ 180 must be split into halves;
  2. Skia does **not** carry a current point across an `arcTo`, so each half needs its own
     `moveTo`, and the second half must **start at 180°** or it retraces the first arc and
     leaves a semicircle. `[EI §3]` `[PN "Two Skia gotchas"]`
- **Workaround (verified, in production in miniPaint):**
  ```nim
  var d = Draw()
  d.moveTo(cx, cy - r)
  d.arc(cx, cy, r, 0.0, 180.0)          # half one
  d.moveTo(cx - r, cy)                   # its own moveTo — Skia has no current point
  d.arc(cx, cy, r, 180.0, 180.0)         # half two STARTS at 180
  ```
- **Fix:** the shim splits a `sweep >= 180` itself so callers get canvas semantics for free —
  `libs/nimskia/src/skia_shim.cpp` (`arcTo`/`runCmds`). Test: **a new**
  `render/native/t_paint_arc.nim` (the file does not exist today) drawing `A 0 360` and asserting
  a full-circle bounding box.

**B. A lone `A` verb renders nothing — BROKEN**
- **Asked for:** an arc without a preceding point (canvas `arc()` implies the move).
- **Happens:** nothing at all is drawn, silently. `[PN "Two Skia gotchas"]`
- **Workaround:** always emit `moveTo` to the arc's start before `arc`.
- **Fix:** same shim `arcTo` call site; same (not-yet-written) `t_paint_arc.nim`.

**C. Fill-then-stroke on the same path — BROKEN**
- **Asked for:** canvas semantics — build a path, `fill()`, then `stroke()` it.
- **Happens:** `case 'F'` calls `cv->drawPath(path.detach(), paint)`; `detach()` **consumes** the
  builder's path, so the stroke silently disappears. Every fill-then-stroke shape lost its
  border; miniPaint's `ellipse` lost its *fill* instead, because upstream strokes first. `[EI §4]`
- **Workaround:** replay the path for the stroke, with tests asserting the replay — **but this is
  not equivalent**: replaying changes the compositing order for translucent colours, so it is a
  real parity risk, not a free fix.
- **Fix:** a *commit verb* that draws the current path and leaves it intact, so `F` and `S` can be
  used the way canvas uses them — `libs/nimskia/src/skia_shim.cpp`; test
  `render/native/t_paint_path.nim` (a new file; fill+stroke on one `SkPathBuilder` yields both).

**D. `globalAlpha` is multiplicative and sticky — BROKEN (the worst trap in this chapter)**
- **Asked for:** `.alpha(0.3)` for one overlay.
- **Happens:** `sdk/ui/paint.nim:80` emits `"O " & f(a)`, and
  `libs/nimskia/src/skia_shim.cpp:1412` is
  `case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;` — `*=`, not `=`. It
  applies to **every later command in the same replay**, because the `colour` lambda at
  `skia_shim.cpp:1327` multiplies it into each paint (text `:1353`, image `:1360`, layer `:1370`,
  buffer `:1384`, svg `:1394`). A trailing `.alpha(0.3)` silently dims everything drawn after it —
  in miniPaint, the entire raster. **You cannot undo it with `O 1.0`** (you just get 0.3). The
  first attempt to reset the minimap overlay that way tinted every zoomed white raster
  `(154,156,159)`. `[PN "Three engine-level drawing traps"]` `[PN "Skia alpha is multiplicative and sticky"]`
- **Workaround:** a balanced `P`/`p` save/restore, which restores `alpha` from a stack —
  `skia_shim.cpp:1364` pushes `alpha` on `P`, `:1365` pops it on `p`:
  ```nim
  var d = Draw()
  d.save()
  d.alpha(0.3)
  d.rect(x, y, w, h, 0xFF00FF00'u32)
  d.restore()          # alpha is restored from the stack — NOT by another .alpha()
  ```
  The same trap applies to the canvas clip added for the zoomed raster.
- **Simpler alternative:** put the alpha in the **colour byte** instead of calling `.alpha()` at
  all. `0x4D00FF00` is a 30%-alpha green that affects only its own primitive, needs no bracket,
  and cannot leak into the next command. Prefer it; keep `.alpha()` for "dim everything I draw
  next as a group".
- **Fix:** make `O` assign rather than multiply, or push it onto the saved state —
  `libs/nimskia/src/skia_shim.cpp`; test `render/native/t_paint_alpha.nim` (a new file)
  asserting that a command after `restore` is unaffected.

> **CORRECTED 2026-10-03.** The widely-repeated claim that **`Draw.alpha()` is silently dropped**
> — the one this chapter used to carry by omission — is **wrong**, and so is its mirror image
> ("it is a setter, so it is scoped to the next call"). Evidence: `sdk/ui/paint.nim:80` emits
> `"O "`; `libs/nimskia/src/skia_shim.cpp:1412` multiplies a running accumulator; `:1327` applies
> it to every verb; `:1364`/`:1365` bracket it. **The correct rule:** it is honoured, it is
> **cumulative**, and `save`/`restore` is the only undo. **What *is* silently swallowed is an
> unrecognised verb** — `skia_shim.cpp:1413` is `default: break;`, so a verb a newer SDK emits
> renders as nothing on an older engine, with no error. That is the real silent-drop case.

**E. `Draw.scale(d, sx)` with no `sy` is NOT a bug — `sy = 0` means uniform**
- **Asked for:** "is the defaulted `sy` a bug? Does `.scale(2)` collapse the canvas to nothing?"
- **Happens:** nothing. `sdk/ui/paint.nim:78` is `proc scale*(d: Draw; sx: float32; sy = 0'f32): Draw`,
  and `libs/nimskia/src/skia_shim.cpp:1410` is `case 's': … cv->scale(x, y == 0 ? x : y); break;`.
  A `y` of zero is promoted to `x`.
- **Correct rule:** `d.scale(2)` is a uniform 2×. To scale non-uniformly you must pass both
  arguments — `d.scale(2, 0.5)`.

> **CORRECTED 2026-10-03.** What this chapter used to imply by omission — that the defaulted
> `sy` is a footgun, or that `Draw.scale` needs a second proc for uniform scaling. Evidence:
> `sdk/ui/paint.nim:78` (the `sy = 0'f32` default) and `libs/nimskia/src/skia_shim.cpp:1410`
> (`y == 0 ? x : y`). **The correct rule:** `sy = 0` is a documented "same as `sx`" sentinel, the
> same convention as `strokeWidth = 0` on `svgPath`. Nothing to fix.

**F. A bare CSS hex on any `Draw` colour argument draws nothing — BROKEN (invisible, not loud)**
- **Asked for:** `d.rect(x, y, w, h, 0xF7F9FB)` — a hex copied straight out of a stylesheet.
- **Happens:** **nothing at all is drawn.** Every `Draw` colour parameter is
  `argb: uint32` in **AARRGGBB**: `fill`(`sdk/ui/paint.nim:53`), `stroke`(`:55`), `rect`(`:57`),
  `circle`(`:59`), `line`(`:61`), `text`(`:63`), `image`(`:65`), `svgPath`(`:46`). `0xF7F9FB` has
  alpha `0x00`, and `libs/nimskia/src/skia_shim.cpp:1327` does
  `paint.setColor(SkColor(argb))` with no normalisation — so the shape is fully transparent. It
  **compiles, it runs, it crashes nothing, and it is invisible.** Measured on port #52: forcing
  the alpha bytes moved the frame from 100% differing to 23.7% in a single edit.
- **This is exactly the gap the node layer does *not* have.** `render/native/engine.nim:345-348`
  is `proc argb(v: int32): uint32` — *"0xRRGGBB (no alpha byte) is opaque; `rgba()` sets the top
  byte"* — and `engine.nim:367-368` runs every node colour through it. So `panel(fill = 0xFFFFFF)`
  is correct and `d.rect(…, 0xFFFFFF)` is not. Same literal, opposite meaning, two layers.
- **Workaround:** one helper, exactly as a real port wrote it (`apps/chess/app.nim:100`):
  ```nim
  proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)
  d = d.rect(x, y, w, h, hex(0xF7F9FB))
  ```
  or use `rgba(0xF7F9FB, 0.4)` for a real alpha — but read §2.1's note on the two `rgba`s first.
- **Fix:** normalise in `runCmds` the way `engine.nim` already does, so the two layers cannot
  disagree again.

**G. `rgba` has two definitions and a port can pick up the wrong one**
- **Asked for:** `rgba(0x000000, 0)` meaning "fully transparent".
- **Happens:** two procs with that name and **different signatures** exist.
  `sdk/ui/style.nim:23` is `proc rgba*(rgb: int; alpha: float): int` — signed `int`, packed
  `0xRRGGBB` plus a float alpha — and `:26` clamps with `clamp(int(alpha * 255 + 0.5), 1, 255)`,
  so **alpha 0 becomes 1/255 "almost clear" and never means fully transparent**. The app-local
  `proc rgba(r, g, b: int32; a: float32): uint32` a port defines (e.g.
  `apps/chess/app.nim:96-98`) packs **AARRGGBB** and does reach 0. Nim binds the local one inside
  the module that declares it, so the same call means two different things in two files of one app.
- **Workaround:** reuse the port's existing helper; **do not add a third**. If you need to tell
  them apart at a glance, name the new one `argb` the way chess does.
- **Fix:** one `rgba` in the SDK with an unambiguous signature and a documented alpha range.

**H. A draw-list proc that never does `result = d` silently discards the caller's commands**
- **Asked for:** `proc drawMinimap(d: Draw, …) = d.rect(...)` as the body of a builder.
- **Happens:** the proc starts from a fresh default `Draw`, so every command the caller passed in
  **vanishes**. It looked fine because it happened to be the last thing in the panel. `[PN
  "Three engine-level drawing traps" #3]`
- **Workaround:** always `result = d` at the top. Same trap as the early-return form: `discard`
  discards the *result value* and **falls through** into the body — the correct guard in a proc
  with a return value is `return d`. `bezierCurve` drew a curve it should have skipped and
  `polygonPath` then indexed `pts[0]` on an empty seq and crashed. `[PN "One real Nim trap"]`
- **Fix:** a doc comment on the `Draw` type in `sdk/ui/paint.nim` (this is a consistent trap, not
  a one-off — `[EI §6]`); app-level test.

**I. `Draw` builders return copies, so an unassigned call is discarded — BROKEN**
- **Asked for:** `d.rect(...)` as a statement, or `d.rect(...).text(...)` as a chain.
- **Happens:** every `Draw` proc takes `d: Draw` **by value** and returns a new `Draw`. A bare
  statement like `d.rect(...)` does not compile as a statement — you get
  `expression 'rect(d, …)' is of type 'Draw' and has to be used (or discarded)` — and if you
  `discard` it the drawing is silently lost. This bit miniPaint twice: a toolbar that rendered
  blank, and a menu bar at the wrong z-order. `[EI §6]`
- **Workaround:** **assign every call**, one command per statement: `d = d.rect(…)`;
  `d = d.text(…)`. `save`/`restore`/`translate`/`scale`/`rotate`/`alpha`/`blend`/`clip`/`close`
  are the same — they all return a new `Draw` and all need `d = `.
- **Verified:** `apps/typewriter/app.nim` had 73 unassigned `Draw` calls and every one is a hard
  compile error. The two mistakes are not equivalent — the chain *compiles* and loses work
  silently; the bare statement *fails to compile*. Only the second is loud.
- **Fix:** make the builder mutating (`var d` + `d.rect(...)` returning `void`, or a fluent type
  that shares the buffer) — `sdk/ui/paint.nim` `Draw`; test `render/native/t_paint.nim`
  asserting a two-command chain draws both.

**J. Full-layer pixel work costs a whole-surface round trip**
- **Asked for:** a per-pixel filter (sharpen, blur, desaturate, magic erase, gradient) on a layer.
- **Happens:** nothing is free — `Ctx.syncFromSurface` / `Ctx.syncToSurface` do **one whole-layer
  `read` and one whole-layer `write` around each filter**. On an 800×600 layer that is a
  full-canvas read/write *per click*. `[EI "The software mirror was never allocated"]`
- **Workaround:** none needed and none wanted — upstream does the same
  `getImageData(0,0,W,H)` / `putImageData` round trip, so this matches the cost profile rather
  than inventing a worse one.
- **Lesson (not a gap, a rule):** the software mirror `Ctx.buf` was **never allocated in the live
  app**, and `Ctx.live` (which gates every write to the real surface) was **never set** by any of
  the three `Ctx` constructions in `app.nim` — so whole-layer tools were silent no-ops in the real
  app while passing cleanly in tests. Two fixes in one session were the *same* bug: a struct field
  correct in the unit test and unset in the application. When a test fixture and the app construct
  the same struct, diff the **differing fields**, not the shared ones. `[EI]`

**K. No filled-polygon primitive and no `ellipse` proc — but both have a first-class workaround**
- **Asked for:** `ctx.polygon(points)` and `ctx.ellipse(cx, cy, rx, ry)`.
- **Happens:** `sdk/ui/paint.nim` has no `polygon` and no `ellipse`. `circle`(`:59`) emits
  `"E"` with `rx = ry = r`, so it cannot produce an axis-aligned ellipse. **A polygon is not a
  gap, though** — it is the canvas idiom: `moveTo`(`:28`) → `lineTo`(`:29`) → `close`(`:45`) →
  `fill`(`:53`).
- **Workaround, and the one to prefer:** `svgPath`. `sdk/ui/paint.nim:46` is
  `proc svgPath*(d: Draw; path: string; x, y, scale: float32; argb: uint32; strokeWidth = 0'f32):
  Draw` — "any command set Skia parses: relative, H/V, smooth curves, arcs" — and
  `libs/nimskia/src/skia_shim.cpp:1389-1407` handles the `V` verb through
  `SkParsePath::FromSVGString`. One call, and it takes arcs, so an ellipse is just four arcs.
  Failing that, an ellipse is four `curveTo`(`paint.nim:35`) calls (the doc comment on `curveTo`
  says as much: *"Used by the ellipse shape"*).
- **Fix:** an `ellipse` proc next to `circle` emitting `"E"` with distinct radii — one line in
  `paint.nim`, one branch in the shim.
- **Sibling:** §2.3 D records the `V` verb as **WORKS**. **CORRECTED 2026-10-03:** the claim that
  `svgPath` is missing, or that a polygon has no workaround, was wrong — evidence
  `sdk/ui/paint.nim:46` + `libs/nimskia/src/skia_shim.cpp:1389-1407`.

---

### 2.2 Text & fonts

**A0. `Draw.text`'s `y` is the top of the line box, not the baseline — MEASURED**
- **Asked for:** "place this label so its baseline sits at `y`, like SVG or the DOM."
- **Happens:** it does not. `libs/nimskia/src/skia_shim.cpp:291` is `p->paint(canvas, x, y)`, and
  `Paragraph::paint` takes that `y` as the top edge of the paragraph's line box. Everything you
  asked for lands about a line too low.
- **Measured** offsets from `y`, in units of font size `S`, verified at `S = 12, 24, 48`:

  | Feature | Offset from `y` |
  |---|---|
  | cap top | `y + 0.375·S` |
  | x-height top | `y + 0.583·S` |
  | **baseline** | **`y + 1.0833·S`** |
  | descender bottom | `y + 1.333·S` |

  **EMPIRICAL — default typeface and weight only.** A different family or weight moves these.
- **Workaround:** `yantra_y = wantedBaselineY - 1.0833 * size`.

> **CORRECTED 2026-10-03.** What the SDK has always documented — `libs/nimskia/src/nimskia.nim:76`
> says *"Draws `s` with its **top-left** at (x, y)"*, which reads like a glyph-box origin and is
> what a reader would take as the baseline. It is neither a glyph-box nor a baseline: it is the
> **top of the paragraph line box**, and the numbers above are the only way to place real
> features. Evidence: `libs/nimskia/src/skia_shim.cpp:291` (`p->paint(canvas, x, y)`) plus the
> measured offsets. **The correct rule:** `y` is the line-box top; the baseline sits at
> `y + 1.0833·size` for the default typeface and weight.

**How to actually run the full gate on this machine.** `just` is **not installed**; the suites
are `host/run_tests.sh`, `render/run_tests.sh`, `render/native/run_tests.sh`,
`sdk/tests/run_tests.sh` and one per `libs/*`. Two PATH traps, both of which cost real time
and both of which fail in ways that look like code breakage:

| what you do | what happens |
|---|---|
| `bash -lc "... run_tests.sh"` | a login shell **resets PATH**, so nim (a Windows scoop shim) vanishes: `nim: command not found` |
| prepend `msys64/mingw64/bin` inside the shell | the scoop shim then **shadows msys64's gcc**, and C compilation dies with `cannot execute 'cc1'` |

**What works:** append mingw64 to PATH *from PowerShell* and invoke the absolute bash
**without `-lc`**, so the child inherits a working PATH. `run_tests.sh` does
`cd "$(dirname "$0")"` itself, so cwd does not matter.

**Always take a control before believing a failure.** And know which failures are structural:

### The `render/native` gate is currently DEAD — it never runs its own tests

`render/native/run_tests.sh:23` does

```sh
bash "$WS/tools/build-wasm.sh" "$WS/examples/todo.nim" "$WS/examples/todo.wasm" \
  || { echo "FAIL todo.wasm build"; exit 1; }
```

`$WS` is a **Windows-style path** (`C:/Users/…`, from `pwd -W`). This MSYS bash cannot execute
a script given in that form:

```
/bin/bash: C:/Users/Sanskar/DEV/yantra/tools/build-wasm.sh: No such file or directory
```

So the line fails and the script `exit 1`s **before `t_engine`, `t_text`, `t_motion`, the shell
apps or any of the other ~50 `t_*.nim` files are built or run.** The reported failure is
`FAIL todo.wasm build`, which reads like a broken example app — it is not. The same build
succeeds when invoked with a relative path (`bash tools/build-wasm.sh examples/todo.nim …`,
307667 bytes) and from PowerShell.

**Consequence, stated plainly: `t_text`, `t_engine`, `t_motion`, `t_apps` and the rest of that
directory are not currently verified by anything.** Do not treat "render/native passed" as a
signal — check that a `PASS` line exists, not merely that no `FAIL` did.

**And `t_text` fails on its own even when run directly.** Built and executed past the harness
fault, it stops at its *first* check with `key not found: -1` (`raiseKeyError`), which is at
line ~50 of a 199-line file. A control run at HEAD is byte-identical, so this is pre-existing
too. Anything added to these suites must be verified by running the binary directly; do not
commit a test you have not seen execute.

**Root cause, and what it hides.** Both `host/run_tests.sh:15-16` and
`render/native/run_tests.sh:6-7` build their paths with

```sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # WRONG
```

GNU `pwd` defaults to `-P` (physical), and under MSYS that yields a **Windows-style path**
(`C:/Users/…`). Handing that to a script invocation fails, as above. The fix is `pwd -m`, which
forces the MSYS form; native tools keep the `C:/…` form via the existing `HERE_W`/`WS_W`.

Applying `pwd -m` is **verified to advance both suites past the misleading failures** — but it
then stops at `FAIL wasmtime.dll missing`. The guard is `[ ! -f "$HERE/build/wasmtime.dll" ]`,
which the old Windows-style path was **falsely reporting a file that is not there**. So the
harness fault was not only skipping the suite's tests; it was also **hiding a genuinely absent
dependency** (the vendored runtime from `libs/nimwasmtime`, built by that package's own test
script). Fixing the path does not fix the missing DLL.

**Do not commit that one-liner on its own** without carrying it to a green suite: a change whose
result you have not seen is not a fix. Correct order is `pwd -m` → build `wasmtime.dll` → then
judge the ~50 `t_*.nim` that have never run. That last step is a real unknown, not a
formality — `t_text` was already shown to fail on its own first check when run directly.

**The general lesson, which cost a round to learn.** A suite that has failed the same way for a
long time is usually failing in its **harness**, not its code, and that fault can silently
absorb both the suite's work *and* its dependency checks. Before believing a long-standing
FAIL, work out which of the two it is.

**RETRACTION (read this before acting on anything below).** The diagnosis given two rounds ago
— "bare `pwd` returns a Windows-style path under MSYS, so `bash "$WS/…"` fails; fix it with
`pwd -m`" — **is wrong, and the proposed fix breaks the suites.** Measured:

```
bare pwd : /c/Users/Sanskar/DEV/yantra/render/native     # already the MSYS form — correct
pwd -m   : (empty)  /usr/bin/bash: pwd: -m: invalid option
pwd -W   : C:/Users/Sanskar/DEV/yantra/render/native
test -f "$(pwd)/build/wasmtime.dll" : FOUND
```

**This shell's `pwd` accepts only `-L -P -W`; there is no `-m`.** Bare `pwd` already yields the
MSYS form, so `host/run_tests.sh:15-16` and `render/native/run_tests.sh:6-7` were correct as
written. Substituting `pwd -m` makes `HERE` **empty**, which is why both suites then failed with
`FAIL wasmtime.dll missing` — a file that is present, 22 MB, at
`render/native/build/wasmtime.dll`, and which `libs/nimwasmtime/tests/run_tests.sh` also builds
and passes on its own (t_wasm, t_official, t_stress, t_memory_bridge, t_char, t_cache all PASS).

So: the long-standing `FAIL todo.wasm build` / `FAIL sandbox.wasm failed to build` in
`host` and `render/native` is **still unexplained**. Do not treat the empty-`pwd` failure as
evidence of anything — it is an artefact of the bad fix, and it looks like a missing dependency
that does not exist.

**What survives from the earlier note:** the observation that these suites have failed the same
way for a long time, and that a long-standing FAIL deserves a harness-vs-code check before it
is believed. The conclusion drawn from it does not.

**SUPERSEDED — the real cause, and the fix that works.** `render/native/run_tests.sh` called
`bash "$WS/tools/build-wasm.sh" …` and that call always failed, so the suite exited before
building or running **any** of its ~50 `t_*.nim`. It printed `FAIL todo.wasm build`, which
reads like a broken example app.

**`bash` on this host cannot open a script given by an ABSOLUTE MSYS path.** It resolves
`/c/Users/…/build-wasm.sh` to `C:/Users/…/` and dies, exit 127. Three measurements, same script,
same arguments:

| variant | exit |
|---|---|
| `bash "$WS/tools/build-wasm.sh" …` (what the suite did) | **127** |
| `MSYS2_ARG_CONV_EXCL="*" bash "$WS/tools/build-wasm.sh" …` | **127** |
| `bash tools/build-wasm.sh examples/todo.nim …` (relative) | **0** |

The middle row matters: it **rules out argument path mangling**, which was the first guess and
would have sent a fix in the wrong direction. Only the **script** path must be relative —
absolute paths passed to nim are fine. Fixed by routing both call sites through

```sh
build_wasm() { (cd "$WS" && bash tools/build-wasm.sh "${1#$WS/}" "${2#$WS/}"); }
```

After which the suite runs for the first time: `PASS native engine`, `PASS yantra shell`,
`PASS motion`, `PASS text editing`, then stops at a *different*, still-unexamined
`FAIL reload variant v2/counter build`.

**And `t_text` PASSES.** This retracts the claim above that it fails on its first check with
`key not found: -1` — that was an artefact of running it against a stale or missing fixture
while the suite was bypassed.

**Two diagnoses in a row were wrong here** (`pwd -m`, then argument mangling). The reason both
looked convincing is worth keeping: each produced an *error message that was real* attached to a
*cause that was wrong*. Read the exit code and bisect the call before believing the story.

**A green baseline deserves the same suspicion as a red one.** `host/run_tests.sh` had been
quoted for three rounds as *"5 passed, 2 failed"*. Applying the same `build_wasm` fix there
**regressed it to 3/5** — the wasm build failures vanished (the fix works) but
*"todo app through the host"* started failing. Reverting the code did **not** restore 5/2:

```
baseline I had been quoting : 5 passed, 2 failed
host at HEAD, same code now : 3 passed, 4 failed
```

Same code, different result, because the experiment left a **freshly built** `examples/todo.wasm`
on disk, replacing a **stale** one. So the suite had been failing to build for long enough that
a fossil from an earlier run was carrying the app stage, and it was reporting green on the
strength of it — the same fault as `render/native` one level deeper: there the suite never ran,
here it ran on a fossil. **The unmasked defect is that a freshly built `todo.wasm` does not load
in the host**, though a stale one did. `host/run_tests.sh` is left at HEAD; re-applying the fix
needs that diagnosed first, and it is the second time the same change regressed it.

**THE WORKING RECIPE — host is green with no code change at all.** Three separate things were
being blamed on the repo, and all three were local. With this PATH and a cleared nimcache:

```powershell
$env:PATH="$PWD\third_party\msys64\mingw64\bin;$PWD\third_party\msys64\usr\bin;C:\Users\Sanskar\scoop\shims;$env:PATH"
& "$PWD\third_party\msys64\usr\bin\bash.exe" host/run_tests.sh
# host sweep: 5 passed, 0 failed
```

**All three directories are required, and dropping any one produces a misleading failure:**

| missing | symptom | looks like |
|---|---|---|
| `scoop/shims` | `nim: command not found` | code error |
| `usr/bin` | `sed: command not found` → *todo/sandbox app stages fail* | a broken freshly-built wasm |
| `mingw64/bin` | gcc missing / `cannot execute 'cc1'` | code error |

Verify the toolchain before believing a build failure:
`for t in nim gcc sed; do command -v $t; done` must print all three.

**And clear `host/nimcache` when the linker reports `undefined reference to
framePtr__system_u2760` (or any `__system_uNNNN` symbol).** Those are *object files compiled by
a different nim version*, mixed with fresh ones — not a source bug. Deleting the nimcache fixed
it immediately.

**Why this took three rounds:** each symptom was real, each cause was wrong, and each wrong
cause was plausible because the *next* failure sat right behind it. The `sed: command not found`
one is the nastiest, because it makes a perfectly good freshly-built wasm look broken — which is
exactly the "a fresh todo.wasm does not load" defect I recorded as real last round. **It was
never real.** Both the "stale fossil" theory and that conclusion are retracted.

**Re-derive a baseline from the current tree; never quote one you have not just watched happen.**
When a gate result changes, clear the caches and check the toolchain *before* theorising about
the code.

**Never hand-run a `t_*.nim` and believe it.** Running `t_text` directly fails its *first*
check (`Notes shows the title input and a multi-line body`) and then dies on `KeyError -1`,
while the same binary passes 44/44 through the suite. The suite sets up fixtures and
`YANTRA_DATA` that a bare invocation does not. **The suite is the authority**; a hand-run
failure is not evidence about the code. That is the same trap that produced the false
"a fresh `todo.wasm` does not load" defect recorded above — a plausible story built on a
harness artefact.

**Current gate state, all green:** `host/run_tests.sh` **5 passed, 0 failed**;
`render/native/run_tests.sh` **53 PASS, 0 FAIL** (native engine 29, shell 20, motion 29,
motion maths 34, motion springs 42, **text 44**, reload 31, net 27, desktop 16, sized 10,
scroll 13, light 9, chat 13, longlist 10, grid 19, effects 5, pdf 9, gpu 8, film 15, video 8,
live edits 26, store 10, a11y 15, a11y UI Automation 9, shell apps 12, image 23, net_image 12,
sound 7, dialog 7, dnd 10, notify 8); `sdk/tests/run_tests.sh` **20 checks, 0 failed**.

**To run one of them anyway**, bypass the harness — build the fixture, compile with the flags
on `run_tests.sh:29` (`--hints:off --warnings:off -d:release` plus `-p:<lib>/src` for each of
nimav, nimcurl, nimfilament, nimjolt, nimaccesskit, nimwasmtime, nimskia, nimyoga,
nimminiaudio, nimspell, nimrtc, nimsdl3, and `-p:<repo>/host`), then run the exe. Note the
script path must stay **relative**; the same script under `$WS` does not run.
`todo.wasm failed to build` and `sandbox.wasm failed to build`, and `render/native` reports
`FAIL todo.wasm build` — with or without any local change, verified by stashing and re-running.
Those three are **pre-existing**; they are not yours until a control says otherwise.

## TYPEWRITER (31.78%) — the bottom edge has a GRADIENT the port lost

Baseline, fresh and reproducible: **331,928 / 1,044,480 = 31.78%**, mean |delta| **12.55**, max
232, vs `.board/shots/ref029.png` at tol 8/255, SCALE 1.

```
worst rows : 810:1280  811:1280  808:1278  807:1275  809:1247  812:1203  813:1102
worst cols : 19:419  22:415  23:415  21:410  18:408  20:408  24:402  17:397
band row 7 (y 784-799): 65 40 31 37 39 32 43 48   <- highest band row overall
```

**1 — a full-width bottom strip, and it is a MISSING GRADIENT.** Six of the top seven worst rows
are `y=807..813` at ~1200–1280 differing px each — essentially **every column** of a 1280-wide
frame. Sampled full width:

| y | ref | frame | Δ |
|---|---|---|---|
| 800 | (80, 48, 24) | (70, 40, 20) | −10, −8, −4 |
| 806 | (86, 52, 26) | (70, 39, 19) | −16, −13, −7 |
| 810 | (88, 53, 27) | (69, 39, 19) | −19, −14, −8 |
| 814 | (0, 0, 0) | (0, 0, 0) | **0, 0, 0** |

Read the direction: the **reference brightens/warms downward** — 80 → 86 → 88 — while the **port
is flat and slightly decreasing** — 70 → 70 → 69. Both go black at `y=814`, so the bottom black
edge is present and correct in both; it is the strip immediately **above** it that is wrong. So
this is **a gradient present in the reference and missing or inverted in the port** — not a
missing element, not a geometry error. The scene is a warm brown, so what is lost is a warm
brightening at the foot of the paper. Chase this first: it is the most concentrated error in the
frame, ~9,000 px across 7 rows, all one cause.

**2 — a vertical band at `x 17..26`.** All ten worst columns, ~400 px each — a narrow full-height
band, the same *shape* as the gallery's left-margin band. Not yet sampled for colour.

**3 — structural errors exist.** `deltahist`: **55.6%** of differing pixels sit in 9–16, just above
tolerance — a small systematic error spread widely. But **23,207 px (7.0%) are at 129+**, which is
*not* systematic: wrong glyph, missing element, misplaced element. Chasing 55.6% first improves the
headline number; chasing 7.0% first is more honest about what is actually wrong.

**Still open:** rows 22, 205, 206 — the key-cap ramp lead; and the **"Marlowe" cursive badge**,
which needs 2D node rotation and is blocked without it (`wire.nim` has only `pRotX/Y/Z`).

#### ✅ Root cause of the bottom strip: the edge-darkening strips OVER-COMPOUND

`apps/typewriter/app.nim:744-769` — *"Edge darkening left, right, top and bottom."* Its own
comment states the source (`:746-751`):

> *"a horizontal gradient with 0.1 alpha of `rgba(150,125,85)` at each extreme, fully clear by 4%
> in from the edge… then the same vertically with **0.1 at top and 0.12 at bottom**, clear by 3%.
> Draw has no gradient, so the ramp is a run of thin vertical strips per edge… **A 1-unit overlap
> closes the seams** between strips."*

```nim
const STEPS = 10
let bandX = bpPW * 0.04'f32 / STEPS.float32
let bandY = bpPH * 0.03'f32 / STEPS.float32
let aX = 0.10'f32 * t
let aY = (0.10'f32 + 0.02'f32 * t) * t     # the bottom edge is slightly heavier
d = d.rect(0, oy,              bpPW, bandY + 0.5'f32, bpRgba(150, 125, 85, aY))  # top
d = d.rect(0, bpPH - oy - bandY, bpPW, bandY + 0.5'f32, bpRgba(150, 125, 85, aY))  # bottom
```

**Bug 1 — the strips over-compound, and the overlap makes it worse.** A CSS gradient is **one**
ramp composited once. This is **ten** separate semi-transparent rects stacked on each other, each
carrying the *full* CSS alpha for its band, deliberately overlapped by 0.5 units. Total alpha is
`1 − Π(1−aᵢ)`, which for a ramp whose alphas sum to ~0.55 reaches ≈0.42 — far more than the
integral of the CSS ramp over the same 3–4% band. **Every edge is drawn substantially darker than
the source**, which is exactly the measured direction: at `y=810` ref `(88,53,27)` vs port
`(69,39,19)`, ~22% too dark, at every column of `y=807..813`.

**Bug 2 — `aY` contradicts its own comment.** The comment says "0.1 at top and 0.12 at bottom", but
`aY = (0.10 + 0.02*t) * t` evaluates to **0.12 at `t=1` for both** — the same `aY` is passed to
the top rect at `:767` and the bottom rect at `:768`. The top edge is drawn at 0.12 where the
source says 0.10, and the trailing `* t` is a factor the comment never mentions.

**Fix direction:** stop stacking translucent rects to emulate one ramp — pre-interpolate the CSS
ramp per pixel into a single opaque strip, or draw non-overlapping bands whose alphas are *solved*
so their composition equals the CSS value. One composite, not ten.

**Same bug class as the gallery's dead nested-disc vignette**: a primitive `Draw` lacks, emulated
by stacking translucent pieces whose composition is not the source. **If fixed here, check
`gradRectV`/`gradShapeV` (`:1119`, `:1135`, `:1170`)** — they are the general form of this helper
and the same over-compounding applies.
#### 🔎 The strip is `drawMachineShadow` — and its own comment says it was solved once

`app.nim:2319`, the machine's contact shadow on the desk. Its comment is the most valuable part,
because it records this exact symptom being measured, fixed, then re-broken by a plausible
misreading:

> *"at y796-812 the desk matched the reference to ±0.5 luma at x<200 and x>1080 but ran −10..−22
> luma dark across x240-1040 — i.e. only the ellipse's own footprint was wrong, and a disc centred
> 86px too high kept shading the desk where the reference has none."*

> *"REFUTED BY MEASUREMENT (v7: 16.70% → 17.22%…). Reading `radial-gradient(closest-side,…)` (html:32)
> literally… **That reading is wrong.** Implemented it, and the desk under the machine went −7..−9.4
> luma **LIGHT** across x250..1080 at y792-815 and the whole frame got worse. The 5.33:1 ellipse is
> correct. **Recorded so nobody re-derives the same plausible reading.**"*

**But the current measurement does not match what that comment says was achieved** — `y=810`
averages **−19 red across the full 1280-wide row**. An ellipse with `rx = MW*0.56` (~459 px) cannot
account for a full-width average that dark. Either the shadow's alpha/extent has drifted since the
note was written, or something else now shades the desk across the whole width.

**❌ It is not the machine shadow — the three-box test says so.** `y=810`, 80×8 boxes:

| x | ref | frame | Δ |
|---|---|---|---|
| 100 | (108, 65, 34) | (94, 55, 27) | −14, −10, −7 |
| 400 | (86, 53, 28) | (68, 39, 20) | −18, −14, −8 |
| 640 | (72, 44, 23) | (52, 28, 14) | −20, −16, −9 |
| 900 | (87, 51, 26) | (67, 37, 17) | −20, −14, −9 |
| 1200 | (67, 37, 17) | (51, 27, 11) | −16, −10, −6 |

An ellipse (`rx ≈ 459 px`) would peak at centre and fall away at the edges. It does the
**opposite**: x=900 is exactly as dark as x=640, and x=100 only 4–6 luma lighter. The footprint is
**flat across the entire row**. This is the file's own warning repeating — the shadow has been the
plausible answer twice and been wrong twice.

**What it is instead:** a near-constant **absolute** darkening of ≈ −18 red. Note the ratio
`frame/ref` is 0.87 at x=100 but 0.72 at x=640 and 0.76 at x=1200 — no single gain explains it,
while the absolute delta stays nearly flat. **Additive, not multiplicative.**

Combined with the vertical profile (`y=800 −10, y=806 −16, y=810 −19, y=814 0`), and the reference
*brightening* downward (80→86→88) against the port's flat fall (70→70→69): the port is **missing
the reference's warm brightening at the foot of the desk** *and* carries an extra flat −18 on top.
The desk's lamp falloff is reproduced correctly in shape (ref 108/72/67 vs port 94/52/51), so the
lighting is fine and the fault is purely the bottom strip's final ramp.

#### ✅ It is a COVERAGE bug: the desk stops being painted and the WINDOW colour shows through

`app.nim:2717` supplies the number that identifies it:

```nim
page.color(0x3a, 0x22, 0x12)      ## = rgb(58, 34, 18)   <- the WINDOW background
```

against the port's measured rows:

| y | frame | |
|---|---|---|
| 800 | (70, 40, 20) | desk, plausible wood — ref (80,48,24), Δ −10,−8,−4 |
| 806 | (70, 39, 19) | still desk-ish |
| 810 | **(52, 28, 14)** | **essentially the window colour** |
| 814 | (0, 0, 0) | black, in **both** |

The port paints desk at y=800 and has fallen back to the page background by y=810. The reference
reads (88,53,27) there — real wood, lit — so **the source's desk reaches the bottom of the
viewport and the port's does not.**

**This also explains the confusing vertical profile.** `−10 → −16 → −19 → 0` was never a gradient;
it was a desk/background boundary averaged across the full width. And the uniform −18 with no
centre peak I read as "an additive term" is simply a **uniform exposure of the page background** —
exactly what a missing band looks like. No shadow, no vignette, no ramp.

**Where to look:** `deskLayer = newLayer(int(FW), int(VH))` (`:2699`, 1280×816),
`deskLayer.draw(bdPaintDesk())` (`:526`), `bdPaintDesk()` at `:473` with `let h = 816.0'f32` at
`:480`, drawn at `d = d.layer(deskLayer, 0, 0)` (`:2362`). The layer is the right size and drawn
in the right place — so does `bdPaintDesk`'s plank loop actually **reach h=816**, or does the last
partial plank get dropped? A shortfall of 6–10 px is exactly a dropped final plank.

#### ⚠ CORRECTION — it is the desk BASE colour, not the window colour. Coverage is fine.

`bdPaintDesk` (`:473-495`) fills the **entire** layer before any plank:

```nim
let w = 1280.0'f32 ; let h = 816.0'f32
# page background, then planks top to bottom
d = d.rect(0, 0, w, h, 0xFF2B170B'u32)      ## desk base = rgb(43, 23, 11)
var y = -20.0'f32
while y < h:
  let ph = 190.0'f32 + bdNext(r) * 80.0'f32  ## 190..270 tall
  bdPlankBody(d, r, w, h, y, ph, i)
  y = y + ph
```

So the bottom rows are guaranteed covered. The measured `y=810 = (52,28,14)` is that base **plus
lamp**, not `page.color` `(58,34,18)`. **The window-colour reading in `eaa8e68` is retracted.**

**The fault is that the port shows bare desk base where the reference shows lit plank:**

- port `y=810` **(52, 28, 14)** ≈ base (43,23,11) + lamp
- ref `y=810` **(88, 53, 27)** ≈ twice that, less saturated — real plank grain

The loop *does* cover y=810 on paper (planks are 190–270 tall from y=−20, so any plank starting
below 546 spans past 810). So the question moves into **`bdPlankBody`** — why doesn't the plank
covering y=810 paint there? Candidates, all local to that proc: it clamps its rect to the layer
height and the clamp is off by the plank's own offset; it skips a plank whose seed/index is out of
range near the end of the sequence; it draws grain and gaps but not the body fill for the final
plank; or it derives grain from `y` and produces nothing past some bound.

This file has a recorded instance of this same class — `:1897-1899`, *"a gap of `hgt/56` on every
seam, and the desk showed through it."*

**Next:** read `bdPlankBody` and find what its `y` parameter is compared against.

#### 🔎 …done — and coverage is fine. It is a plank TONE mismatch, and maybe PRNG drift.

`bdPlankBody` (`:304-359`) fills with **no clamp to the layer height**:

```nim
let t = bdTones[idx mod 4]
while band < 24:
  d = d.rect(0, y + ph * f0, w, ph * (f1 - f0) + 1.0'f32, bdPlankBase(t, fm))
```

Every plank paints `y → y+ph` regardless, so one starting below 546 *does* cover y=810 — the desk
base is not what's showing. "Why doesn't the plank paint there" was the wrong question.

**The fault is the plank's TONE.** `t = bdTones[idx mod 4]`, and the gap is exactly a tone
difference in size: port `(52,28,14)` vs ref `(88,53,27)`, ~1.7× brighter and less saturated.

**Why the bottom specifically — suspect PRNG drift, not an index bug.** The desk is seeded once,
`bdRngInit(21)` (`:481`), and consumed in one sequence. `bdPlankBody`'s consumption depends on its
arguments: the grain loop runs `n = bdRound(ph/2.4)` times (`:317`) at ~7 draws each (`:320-329`),
and the knot is a 55% coin flip (`:346`) — on the order of **a hundred draws per plank**. **One
extra or missing draw re-aligns every later plank**: different `ph`, different `n`, a knot where the
reference has none, a different `idx` sequence. ~4 planks span the 836 px, so the bottom is `idx 3`
— the last tone, and exactly what a small drift lands on.

That would make this look like "the bottom strip" when it is a **late-sequence divergence**, which
also explains why the frame is 31.51% different overall rather than only at the bottom.

**Not established — a lead, not a conclusion.** Confirm or kill it cheaply: the port already echoes
its desk command count, `echo "B-desk commands: ", d.cmds.len` (`:512`). **If the reference emits a
different number of desk draw calls, the sequences have diverged and the tone drift is confirmed.
If it matches exactly, PRNG drift is refuted** and the fault is local to `bdPlankBase`'s tone table.

**❌ Refuted by measurement — plank SEAMS line up, so there is no PRNG drift.** Plank seams are
high-contrast dark lines at `y + ph − 2` (`:357-358`), so drift would move the seam *rows*. A
column profile at `x=60..100` shows they do not move:

| y | ref | frame | |
|---|---|---|---|
| 203 | 102.6 | 80.4 | **seam — both, same row** |
| 276 | 102.6 | 92.7 | **seam — both, same row** |

Plank boundaries agree ⇒ the RNG sequence agrees through the first two planks ⇒ **drift is
refuted.** (The loud rows `y=375/382` at dip ~50 and `y=47..85` are the machine and keyboard —
`:2142-2145` records the machine region at ref lum 205 vs port 85 — **not** desks.)

So the tone difference at y=810 is **local to how a plank's colour is computed**: `bdTones`' four
values, `bdPlankBase`'s mapping of `t` and band-midpoint `fm`, or the 24-slice banding. Caveat:
the seam test only covers the first two planks, so a drift *beginning after y=276* is still
possible — these are the next read, not a conclusion.

**⚠ Tool note — `png.mjs` does NOT return an indexable RGB buffer.** The correct accessor is
`im.px(x, y)` (`tone.mjs:18`). A probe that indexes `load(...)` directly prints **`NaN` for every
row**. That is a **failed measurement**, not a black column — record it as one and conclude
nothing from it.

**✅ …and `bdTones`/`bdPlankBase` are CLEAN — so something AFTER the planks erases them.**

```nim
const bdTones: array[4, array[3, int32]] =
  [[92,52,26], [104,60,31], [86,48,24], [98,56,28]]         # :236
proc bdPlankBase(t: array[3, int32]; f: float32): uint32 =   # :240
  let hi = bdRgba(t[0] + 6, t[1] + 4, t[2] + 2, 1.0)
  let lo = bdRgba(t[0] - 8, t[1] - 6, t[2] - 4, 1.0)
```

No negative components (smallest `t[2]−4 = 20`), no out-of-range mixes. **Plank red therefore lives
in 78–110 at every tone, both stops, every `f`.**

**And that is the whole point:** the port's `y=810 = (52,28,14)` is *below the darkest plank in the
table*, so it **cannot be a plank** — it is the desk base `0x2B170B` (43,23,11) + lamp. The
reference reads `(88,53,27)`, squarely inside the plank range.

Since `bdPlankBody` has no clamp that could cause this (it paints `y → y+ph` unconditionally),
**something drawn after the planks removes them** — and the draw order in `bdPaintDesk` says what:

```nim
# planks first, then:                              # :494-500
d = bdLampLight(d, w * 0.18, -h * 0.12, sqrt(w * w + h * h) * 0.95'f32)
```

**The lamp is the prime suspect, and this file records the mechanism at `:435`** — *"painted in the
layer, so every ring **erased the walnut under it**"*. `bdLampLight` lightens by **erasing** what
the gradient removes, in a layer that already holds the planks. Lamp centre `(230, −98)`, radius
≈1660; the frame's bottom edge is ~1010 px away = **~61% of the radius**, deep in the falloff,
exactly where an over-erased annulus stack bites hardest.

It also predicts something earlier readings could not: the fault should grow with distance from
the lamp — worse at the bottom **and the right**. The uniform −18 across `x=100..1200` at `y=810`
is consistent with that.

**✅ CONFIRMED — and it turns out HORIZONTAL, which is what makes it the lamp.** `y=810`, 80×8
boxes; plank red range 78–110, desk base red 43:

| x | ref | frame | frame red | |
|---|---|---|---|---|
| 60 | (106, 64, 33) | (92, 54, 26) | **92** | **inside** the plank range, Δ only −14 |
| 640 | (72, 44, 23) | (52, 28, 14) | 52 | **below** the plank floor |
| 1200 | (67, 37, 17) | (51, 27, 11) | 51 | **below** the plank floor |

**The split is the proof.** At x=60 (170 px from the lamp centre) the frame's red is 92 — a real
plank tone. At x=640 (410 px) it is 52; at x=1200 (970 px) it is 51. Both below the darkest plank,
so the plank is **not merely dimmed — it is gone** and the base shows. Planks are present near the
lamp and progressively removed with horizontal distance from it: **the lamp's falloff, inverted.**
It should *add* light far from centre; here it erases the surface as you move away.

**⚠ WHY EVERY EARLIER READING MISSED IT — worth remembering.** The strip was always measured
**averaged across the full 1280-wide row**, and a horizontally-varying fault averages to a uniform
−16..−20 at every x. A uniform average is exactly what this looks like once you average it away —
which is why `8c2ed71` read it as "an additive term with no footprint". **Average across `x`
before probing a lamp bug and you will never see the lamp.** Probe several columns *separately*.

**The fix, not written:** the lamp must not erase the layer's contents — composite it as a light
pass over the *finished* desk (what a canvas radial gradient does), or knockout against a **copy**
of the walnut rather than the layer itself.

**This also explains why the frame is 31.51% different overall** rather than only at the bottom:
the lamp erases everywhere it has faded, so it is a whole-frame effect. `26034fe` flagged that and
nothing since has explained it.

**❌ …but the eraser theory is REFUTED by the code, and the plank is not missing either.**

`bdLampLight` (`:426-450`) already rejected the eraser version in its own comment:

> *"It is deliberately **NOT** built from disc-fill + `eraser` (bDstOut) as an earlier revision was:
> bDstOut knocks the hole through everything already painted in the layer, so every ring erased the
> walnut under it… **Stroking needs no hole.**"*

It is **stroked annuli under `bSrcOver`**, 96 rings, each compositing `bdStopColor(mid)`.

And the plank **exists** — the column profile found a seam dip at **`y=789` in both** (ref 75.7,
frame 51.5). A plank starts there and spans past y=810. **It is drawn; it is DARKENED.** "Below
the plank floor" meant *overlaid*, not *absent* — that inference in `6af7564` was wrong.

**So the fault narrows to `bdStopColor`.** For a plank of tone 86–104 to land at red 51–52, the
overlay there must be order 0.5 alpha of dark warm colour — **not the faint tail of a lamp**. The
stop table is almost certainly not falling to transparent at the outer end the way a canvas
radial gradient does, but carrying real colour to the rim. Measured shape fits and fits nothing
else tried: x=60 reads 92 (nearly its own tone), x=640 and x=1200 read 52 and 51 — overlay at full
strength.

**Same bug class as the sheet edge darkening (`67ebff6`) and the gallery's dead nested-disc
vignette:** `Draw` has no gradient primitive, so a gradient is stacked tinted passes, and the
question is always whether they **sum** to the source's value. Here they **saturate** instead of
fading. **Next:** `bdStopColor`'s stop table (source quoted at `:404-425`) — what alpha and colour
does the **outermost** stop carry?

**✅ …the lamp table is verbatim and CORRECT — and my refutation of the machine shadow was wrong.**

```nim
## The four CSS stops of the lamplight radial, verbatim.       # :390-398
bdLampStops: array[4, uint32] =
  [bdRgba(255, 214, 150, 0.50), bdRgba(255, 190, 120, 0.20),
   bdRgba( 40,  18,   6, 0.15), bdRgba( 10,   4,   1, 0.62)]  # near-black at 62%
bdLampAt: array[4, float32] = [0.0, 0.35, 0.75, 1.0]
```

The outer stop **is** a near-black at 62% — that is what darkens the far desk, and it is marked
verbatim, so **the table is correct**. `bdStopColor` (`:400-416`) lerps colour *and* alpha linearly
with no easing, exactly as `createRadialGradient` does. Nothing to fix.

Checked against the measurement (centre `(230.4, −97.9)`, radius ≈1444), the lamp's predicted
composite **matches near the lamp and falls far short away from it**:

| x, y | t | predicted over plank 86 | measured |
|---|---|---|---|
| 60, 810 | 0.640 | ~92 | **92 — matches** |
| 640, 810 | 0.690 | ~82 | **52 — far too dark** |

**So there is a second darkening beyond the lamp — and I over-refuted the machine shadow.**
`8c2ed71` ruled it out for having "no centre peak", but `−14, −18, −20, −20, −16` at
x=100/400/640/900/1200 **is** a peak: −14 at x=100 versus −20 at x=640/900. I was looking for a
dramatic peak and read a modest one as flat — **the same averaging trap I warned about one round
later, committed one round earlier.** `8c2ed71` *is* that trap; I fell into it while documenting it.

**So the strip has at least TWO contributors that were being confused for one another:** the
lamp's dark outer stop (correct, strengthens with distance from `(230,−98)`) *and*
`drawMachineShadow` (centre-weighted on x≈640–900, wrongly dismissed). A third remains unexplained:
the near-lamp column matching to 0 while everything right of it does not.

**❌ …but the machine shadow CANNOT reach y=810. Arithmetic settles it — and so do I.**

From `layout()` (`:962-966`) with `SW=1280, SH=816`:

```
hFit = (816 × 0.46) / 0.45 = 834.13
MW   = min(920, min(819.2, 834.13)) = 819.2
U    = 0.8192      MX = 230.4      MY = 437.36
```

`drawMachineShadow` (`:2326-2329`): `sx=181.25, sy=683.12, rx=458.75, ry=86.03`

> **ellipse spans y 597.1 → 769.2. y=810 is 41 px below it. It does not touch y=810 at any x**,
> and `shAlpha` falls to 0 at t=1 (`:2314-2317`), so there is no soft tail.

**The partial reinstatement in `75131e2` was wrong again.** The centre weighting is real but is not
this shadow — the shadow isn't there. (The app's note at `:2337-2339` about `y792-815` going
*LIGHT* was the **refuted circle** variant, centred at `(640, 769)` r=86, which spans y 683–855.
The 5.33:1 ellipse does not reach there — easy to confuse from the comments alone.)

**What is at (640, 810):** `MX=230.4`, `MW=819.2` ⇒ the machine occupies **x 230.4..1049.6** with
`MY=437.36` as its top. That pixel is inside the **machine body**, not the desk — which **invalidates
the lamp calculation in `75131e2` there**, since it assumed a plank underneath. A dark machine body
rather than a dimmed plank is what closes the 82-vs-52 gap.

**So the bottom strip is NOT one fault.** The "uniform −18 across the row" that drove six rounds was
**three different things averaged together**: correct desk tone near x=60 (lamp + plank verified to
land on 92), the lamp's verbatim dark outer stop, and the machine body filling the frame centre.

**❌ …and there is NO machine body at y=810. The edge test refutes it cleanly.**

`y=810`, 60×8 boxes; machine spans x 230.4..1049.6:

| x | | ref | frame | Δ |
|---|---|---|---|---|
| 200 | **outside** | (109, 67, 35) | (95, 57, 29) | −14, −10, −6 |
| 240 | inside | (106, 65, 34) | (91, 54, 27) | −15, −11, −7 |
| 1030 | inside | (89, 52, 25) | (72, 39, 18) | −17, −13, −7 |
| 1070 | **outside** | (85, 49, 24) | (67, 37, 16) | −18, −12, −8 |

Values **and** deltas move smoothly across *both* machine boundaries (109→106→89→85, −14→−15→
−17→−18) with **no discontinuity**. An opaque body of a different colour would step. So
`(640, 810)` **is desk**, and the round-215 claim is refuted. The smooth ramp is simply the **lamp**:
brightening toward x=230 (its centre), dimming away — the verbatim geometry working correctly.

**So the strip is desk across its full width, with a correct lamp on top and a residual ~−16 that
does not vary with x.** Since the lamp is correct, whatever draws that residual **draws after
`bdLampLight`**.

**Now firmly established:**

- `y=807..813` is desk, full width — not machine body, not paper, not window background
- a plank **is** present there (seam at `y=789` in both)
- the lamp is verbatim-correct and its falloff reproduces (smooth 109→85)
- the residual is a roughly x-independent **~−16 red**, growing downward: −10 @ y=800, −16 @ y=806,
  −19 @ y=810, 0 @ y=814 (shared black edge)

**Refuted, each by measurement:** missing bottom gradient / inverted ramp (`26034fe`) · sheet edge
darkening as the cause (`67ebff6` — real defect, fixed, but not this) · window colour through a
coverage gap (`eaa8e68`) · scallop pass (`77bd04f`, bright and spot-shaped) · anisotropic
minification (`fd9e9a4`, wrong sign *and* place) · machine shadow at y=810 (`4250b39`, ellipse
bottoms out at y=769.2) · machine body at y=810 (this test) · lamp eraser rings (`6af7564`, code
rejects erasers) · PRNG drift in the plank sequence (`5db42b2`, seams line up).

**Still open:** what draws the last ~15 rows given desk + planks + lamp + bloom are all correct
there · `x 17..26` band · the 129+ tail (23,207 px, 7.0%) · key-cap ramp rows 22/205/206 · the
Marlowe badge (blocked on 2D node rotation).

**The most valuable output of this lane is the discipline, not a fix:** averaging a
horizontally-varying fault across the row turned three or four distinct problems into one fake
"uniform −18" that I then spent six rounds explaining. **Probe columns separately.**

**Next: the one full-frame draw over the desk.** The tail of `buildScene` (`:2362-2385`) after
`d.layer(deskLayer, 0, 0)`:

```nim
d = d.rect(0, 0, FW, VH, 0x00000000'u32)      # <-- full frame, transparent black
drawProps(d)
```

It is the only draw covering **every** pixel, so it is the one candidate that could produce the
**x-independent** darkening — the single property of the residual nothing else explained. It is a
**raw literal, not `bdRgba`**, so it skips the colour packing every other colour in the file goes
through; under `bSrcOver` a genuinely alpha-0 rect is a no-op, and a misparse would be a uniform
veil.

**But the measurement argues against it being the whole residual,** and that is why it is recorded
rather than fixed: a full-frame veil is constant in `y`, and the residual is not
(`−10 @ 800, −16 @ 806, −19 @ 810`). `drawProps` and `drawMotes` are the two remaining full-width
possibilities never checked; the rest are localised shapes, and `a588479` already showed no step at
the machine's `x` boundaries.

### Honest state of the lane — start here, not at round one

**Fixed and kept:** the edge-darkening over-compound, 31.78% → **31.51%**. Real defect, but not
this strip.

**Established:** `y=807..813` is desk, full width, with a plank present (seam `y=789` in both); the
lamp is verbatim-correct and its falloff reproduces; the residual is **~−16 red, x-independent,
ramping in y**.

**The open question, stated tightly:** *what darkens the last ~15 rows of the desk by ~−16 red,
uniformly in x and ramping in y, given desk, planks, lamp and bloom are all correct there? It is
drawn after `bdLampLight`.*

**The method failure that cost the rounds:** **averaging across x.** Six rounds were spent
explaining a "uniform −18" that was three or four distinct faults averaged into one number — and
**each of those faults has a different fix.**

#### 🔎 Split the 8-row boxes into 1-row boxes and the fault changes character

```
y=808  ref (70,43,22)  frame (55,31,16)  Δ-15
y=809  ref (73,44,23)  frame (56,30,16)  Δ-17
y=810  ref (73,45,23)  frame (51,28,14)  Δ-22
y=811  ref (74,45,24)  frame (53,28,15)  Δ-21
y=812  ref (75,46,23)  frame (51,27,12)  Δ-24
y=813  ref (76,46,24)  frame (53,27,15)  Δ-23
```

**The reference runs 70, 73, 73, 74, 75, 76 — smooth and monotonic. The frame runs 55, 56, 51, 53,
51, 53 — a period-2 row pattern** on a slow downward drift. **A 1-pixel alternating pattern is a
coverage/offset signature, not a tone error** — the same class as the gallery's ceiling oscillation
("ref flat 21.7 across 19 consecutive buckets, the port oscillates 30 → 122").

Local suspect: **grain frequency.** `bdPlankBody` draws grain every `n = bdRound(ph / 2.4)` px
(`:317`) — ~one per 2.4 px, matching the observed period far better than the reference's smooth
ramp does. Either the reference's grain thins toward the bottom, or the port draws it at ~2× the
source's density down there.

**Every per-row delta is −15..−24**, so the "−16"/"−18" figures quoted for the previous several
rounds were **8-row averages understating the true per-row error by up to 8 luma.**

#### ⚠ TOOL TRAP (2nd occurrence in this lane): `tone.mjs` reads out-of-bounds as BLACK

| box | result |
|---|---|
| `y=810 h=1` | ref (73,45,23) frame (51,28,14) Δ −22 |
| `y=810 h=4` | ref (74,45,24) frame (52,28,14) Δ −22 |
| `y=810 h=8` | ref **(0,0,0)** frame **(0,0,0)** Δ **0** |

The frame is 816 tall; that box covers rows 810–817 and the two out-of-range rows contribute black,
dragging the average to exactly `(0,0,0)`. **Any box whose bottom edge exceeds `VH` reports black.**

This narrows one earlier claim rather than overturning it: "both black at y=814" was a `y=814 h=4`
box (rows 814–817, two out of bounds), but it returned *exactly* `(0,0,0)`, and a partial-black
average could not — so rows 814/815 are genuinely black in both. **Re-measure any other
"both black at the bottom edge" claim with an in-bounds box.** (First occurrence: the `ref NaN`
column in `5db42b2`.)

#### ✅ …and it is the GRAIN PASS, drawn too dark. Not the bottom strip at all.

Column profile on far-right desk, `x=1180..1220`, testing the grain-frequency hypothesis
(`n = bdRound(ph/2.4)`, ~2.4 px):

```
y= 38   ref 177.3  frame 166.2
y= 40   ref 163.0  frame 170.7
y= 43   ref 162.6  frame 187.9
y=203   ref  54.6  frame  31.5    (-23)
y=428   ref  60.2  frame  38.3    (-22)
y=461   ref  58.8  frame  42.8    (-16)
```

**1 — grain frequency is refuted.** No period-2 ripple at all here; dips are sparse (38, 40, 43,
then 203, 428, 461). Over-drawn grain would show at x=1180 as much as at x=640. It doesn't.

**2 — the grain geometry is CORRECT.** Ref and frame share features at the *same rows*, so the
sine-warped lines land in the right places with the right spacing. A genuinely correct part.

**3 — but the grain is much too dark**, by ~−16..−23 at every dip — the same deficit the bottom
strip has shown all along.

**So the bottom strip is not a separate fault.** It is *this* fault where the grain is dense enough
to be visible: the per-row oscillation at `(640, 808-813)` is over-dark grain lines landing on
consecutive scanlines, averaging out away from the bottom centre. It also explains the smooth
x-profile at `y=810` (`a588479`) — many grain lines at similar depth, made more visible by the
lamp lifting the surrounding wood. **No separate full-width overlay is needed**, which is what the
"x-independent residual" in `de0f50b` was still wrongly pointing at.

**The culprit is `bdPlankBody`'s grain pass (`:316-343`)** — a local question, finally:

```nim
let dark = bdNext(r) < 0.62'f32
var a = (if dark: 0.08'f32 + bdNext(r) * 0.2'f32 else: 0.05'f32 + bdNext(r) * 0.12'f32)
let base = (if dark: 38'i32 else: 176'i32)
...
a = a * 0.75'f32
```

A −16..−23 luma deficit on the dips is a large fraction of the wood's own contrast, so this is not
sub-perceptual rounding — either `dark`'s **0.62** probability, the **alpha ranges**, or the **0.75**
factor is materially off the source. The dips are ~−22 while the surrounding wood is correct to a few
luma, so the fault is specific to the stroke, not the plank body — consistent with plank tone, lamp
and falloff all being verified correct.

This supersedes three earlier readings of the same strip — "missing gradient" (`26034fe`),
"over-compounding edge darkening" (`67ebff6`, fixed and kept, but not this), and "machine shadow"
(`dc5e4df`). All three fit the symptom; this one is the only one that explains why the symptom
**changed character** between y=800 and y=810.
(`app.nim:2362`) with things drawn over it; and check the source's own treatment of the bottom of
the `height:100%` container (`app.nim:2722`, `html:25`), which *is* the whole 1280×816 window.
by measurement. Geometry for reference: `sx = MX - MW*0.06`, `sy = MY + 300*U`, `rx = MW*0.56`,
`ry = 210*U/2 = 105*U`; alpha from `shAlpha(t)` = .72 at 0, .35 at .55, 0 at 1 (`:2314-2317`),
emitted in a scaled frame because *"circles become ellipses under a y-scale"*.
**Order of work:** bottom gradient → sample `x 17..26` → the 129+ tail (where the real bugs are) →
key-cap ramp → Marlowe badge (blocked on 2D rotation).
## GALLERY (57.37%) — the difference is global, not localised

Fresh baseline: 587,440 / 1,024,000 = **57.37%**, mean |delta| **17.33**, max 179, vs
`.board/shots/ref039.png` at tol 8/255, SCALE 1.

```
worst rows : 772 682 528 438 544 529 536 493 545 522
worst cols : 37 4 0 1 7 58 3 57 5 21

band % differing (8x8)
 91  23  18   0   0   8  16  28
 99  74  21   0   0  21  45  37
 98  72  46  11   9  55  77  53
 98  92  67  33  51  71  89  74
 97  92  70  41  49  65  87  68
 99  76  56  78  81  45  67  70
 59  38  85  93  94  90  28  48
 22  67  91  81  74  86  72  29
```

**Do not treat this as one misplaced element.** Bands run 0–99% and a mean |delta| of 17.33 is a
whole-page systematic offset. Two leads, in order:

1. **The left strip.** All ten worst columns are in `x 0..58`, and band column 0 reads
   91/99/98/98/97/99/59/22 down the rows — wrong from top to bottom. A uniformly wrong full-height
   60px strip is a whole element with the wrong colour or geometry (wall, frame edge, shadow
   column, scrollbar), not a gradient that drifted — a drifted gradient would vary with distance.
2. **The top-middle exception.** Bands (rows 0–1, cols 3–4) are **exactly 0%** while their
   neighbours read 91–99%. That region is already pixel-perfect: a free control. Work out what
   occupies it and why it matches exactly — likely the fastest route into the rest.

### The parked §16.24 lead, read — supported but NOT sufficient

`apps/gallery/app.nim:2681`, inside the app's **own** software room compositor (a raycast mirror
buffer, not the engine):

```nim
## -- 2. the real floor, composited TRANSLUCENTLY over the mirror
if h[0] == F_FLOOR:
  let c = sampleTex(texFloor, TW_F, TH_F, h[1], h[2])
  blit(corrBuf, (py * RW + px) * 4, c, alphaOf(c))
```

The floor is blended with the mirror behind it at the texture's own alpha instead of replacing
it. The mechanism the parked note suspected is real, and **the single worst row in the entire
image is 772** — at 800 rows that is the bottom 3.5%, exactly where a floor plane lands.

**But it cannot be the whole story.** A floor is a minority of the frame, yet the difference is
global — every band 0–99%, mean |delta| 17.33. The worst bands include row 2
(`98 72 46 11 9 55 77 53`), near the **top** of the image, nowhere near a floor. So there are at
least **two** faults, probably unrelated:

1. ~~**something global** — a whole-page luma/alpha offset~~ — **RETRACTED, see below**
2. **something at the floor** — the worst row in the frame sits at the floor plane

#### Measured: MULTIPLE independent causes — there is no global tone constant

`deltahist` on the gallery frame:

```
 9-12  159433  27.1%  #########      39.6% of differing pixels lie in 9-16,
13-16   73109  12.4%  #######      i.e. only just above the tolerance of 8
17-24  124677  21.2%  #############
25-32   85836  14.6%  #########
33-48   71835  12.2%  #######
49-64   34468   5.9%  ####
65-96   25451   4.3%  ###
97-128   8383   1.4%  #
129+     4248   0.7%
```

`gainfit`, per-tile gain needed to reconcile frame → ref:

| tile | g | refLum | frameLum | |
|---|---|---|---|---|
| (0,0) | 0.828 | 79.7 | 97.6 | frame **+17.9** brighter |
| (128,0) | 0.819 | 49.8 | 57.5 | +7.7 |
| (128,128) | 0.713 | 103.5 | 114.6 | +11.1 |
| (896,128) | 0.852 | 62.1 | 74.1 | +12.0 |
| (1024,128) | 0.679 | 46.7 | 54.4 | +7.7 |
| (256,128) | 0.892 | 47.0 | 46.1 | −0.9 |
| (0,256) | 0.989 | 82.8 | 78.8 | −4.0 |

Gains span **0.68 → 2.37**. **No single global tone or alpha error exists** — no one gain and no
one additive offset reconciles the frame with the reference. (Ignore wild-gain tiles where
`refLum == frmLum`, e.g. x=1024 y=0 `g=2.369` at 26.0/26.0 — degenerate fit on a flat tile.)

So the earlier "whole-page ~17/255 luma offset" framing is **retracted**. What survives: the
frame runs **7–18 luma brighter** than the reference across most left/upper tiles, and **39.6% of
failures are only 9–16 out** — consistent with a real translucency/alpha difference over a large
area, but not the whole of it.

**Ruled out explicitly: "find one global tone constant and nudge it" is dead.** Anyone attempting
it would be fitting noise. The useful consequence is that 39.6% of failures sit just above
tolerance, so one correctly-found cause could move 57% substantially — but it has to be found by
reading what the app actually draws in the high-count region, not by fitting.
**But the floor theory cannot explain the LEFT STRIP.** Reading what the app actually composites
(`app.nim:2694-2708`) settles it — every surface except the floor is written with `put`, an
opaque replacement:

```nim
elif h[0] == F_WALLL: put(corrBuf, o, sampleTex(texWallL, TW_L, TH_L, h[1], h[2]))
elif h[0] == F_WALLR: put(corrBuf, o, sampleTex(texWallR, TW_L, TH_L, h[1], h[2]))
elif h[0] == F_END:   put(corrBuf, o, sampleTex(texEnd, TW_E, TH_E, h[1], h[2]))
elif h[0] == F_CEIL:  put(corrBuf, o, sampleTex(texCeil, TW_F, TH_F, h[1], h[2]))
elif h[0] == F_FLOOR: dbuf[py * RW + px] = h[3]   # depth only; colour came from section 2
```

So the alpha/translucency difference is **confined to the floor plane** — yet the left strip is
wrong top to bottom and 7–18 luma *brighter*. The left strip is its own cause, accounted for by
neither the floor nor the alpha handling.

#### ✅ Candidate (2) is the answer: **the vignette** — and it explains the global spread too

`app.nim:3399`/`:3414`, verbatim from the source CSS:

```css
/* html:95-98 — the fog and the vignette, as ONE straight-alpha buffer */
.vignette{ radial-gradient(120% 95% at 50% 50%, rgba(0,0,0,0) 55%, rgba(0,0,0,.55) 100%) }
/* html:95-96 — the fog, an ellipse 30% x 34% at the centre, at --fog */
```

It fits every observation, including the ones earlier rounds could not explain:

- A vignette **darkens edges**. Observed, the frame is **7–18 luma brighter** in exactly the wrong
  tiles — (0,0) ref 79.7 / frame 97.6; (0,256) ref 82.8 / frame 78.8. A weaker or mis-centred
  vignette gives precisely that sign: edges too light.
- The error runs the **full height** of the left strip. A radial field is full height by
  construction — no element needs to be invented to explain it.
- It is applied **after** the room compositor in one straight-alpha blit, so it darkens walls,
  sprites and floor alike — consistent with the difference being global.
- The app already measured its footprint: *"fog and vignette were switched off, and only 81,353
  with them on"* (`app.nim` ~3503) — same order as the left strip's contribution.

**It also resolves the paradox** that killed the global-tone theory: the difference is global
(bands 0–99%) *yet* `gainfit` gains span 0.68–2.37. A vignette is a **spatial ramp, not a
constant** — it makes every tile need a different correction, which is exactly that signature.

#### Read `drawFogVig` — geometry and composite maths are CORRECT, so the suspect moves

`app.nim:3399-3460` checked against `html:95-98`. **Two candidate bugs ruled out:**

**1) The CSS values are restored, not tampered with.** The comment at `:3421-3423` warns the
alphas were raised last round on a wrong reading; they are back to source:

```nim
fogStops (0.00, rgba(8,7,6,0.62*f)) (0.45, rgba(8,7,6,0.34*f)) (1.00, rgba(8,7,6,0))
vigStops (0.55, rgba(0,0,0,0.00))    (1.00, rgba(0,0,0,0.55))
fogRX = SW*0.30  fogRY = SH*0.34  vigRX = SW*1.20  vigRY = SH*0.95
```

Including the two independent ellipse radii the comment warns about at `:3417-3418`. CSS
radial-gradient size percentages **are** radii, so `rx = 1.20*SW` is right.

**2) The composite at `:3448` is algebraically correct** — it only *looks* like the bug:

```nim
let ca = af * (1.0'f32 - av) + av        # correct source-over
```

The vignette is black and contributes no colour, so `correct = af + av*(1-af) = af + av - af·av`
and `as written = af - af·av + av` — **identical**. The unpremultiply at `:3452-3454` correctly
keeps the numerator `8*af*(1-av)`, since the vignette's colour term is 0.

**Still open (short list), now in priority order:**

1. **The blend at the call site** `:3460` — `d.pixels(fogVigBuf, SW, SH, 0, 0, SW, SH)`. Per
   `:3408-3411`, the `X` command builds a **kUnpremul** pixmap and draws it with the **current
   blend mode**. If that is not source-over when this executes, the vignette composites with the
   wrong operator — and a wrong/too-weak composite is exactly a "frame too bright at the edges"
   signature. #### ❌ The vignette path is verified CORRECT end to end — this lead is dead

`libs/nimskia/src/skia_shim.cpp`:

```
:1393-1404  case 'X': ...
    SkPixmap pm(SkImageInfo::Make(pw, ph, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType), ...)
    SkPaint lp; lp.setBlendMode(blend); lp.setAlphaf(alpha);
    cv->drawImageRect(img, ..., &lp);
:1309  SkBlendMode blend = SkBlendMode::kSrcOver;    <- default
:1315  float alpha = 1;                               <- default
:1382  case 'b': ... blend = (SkBlendMode)m;           <- the ONLY way blend changes
```

So the blend **is** source-over unless the gallery issues a `b`. That candidate is **refuted**.

Also verified: the `kUnpremul` declaration at `:1398` **pairs correctly** with the app's
arithmetic. `apps/gallery` writes a *straight* colour — `buf[o+0] = 8.0*af*(1-av)/ca` (`:3452`)
with `buf[o+3] = ca*255` (`:3451`) — which premultiplies back to exactly `8*af*(1-av)`. Had it
written premultiplied bytes while declaring `kUnpremul`, Skia would double-apply the alpha and
the vignette would be far too weak — a perfect match for "edges too bright". **That is not what
the code does.**

**The full negative** — verified at every level: stop values ✓, ellipse geometry ✓, composite
algebra at `:3448` ✓, unpremultiply numerators ✓, alpha-type pairing ✓, blend mode ✓.

Yet it fits the left-strip symptom better than anything else found. **That is a warning, not a
confirmation.**

#### ⚠ The pattern, and it is the real finding here

Four hypotheses for this region — translucent floor (`7b197b3`), a foreground panel over
`x 0..58`, the vignette, and the vignette's blend mode — each fit the symptom and each died on
reading the code. **Symptoms that good usually mean the measurement is describing something
real.** The next step must be a *new kind of evidence*, not another code read: dump the actual
RGB of a handful of pixels at the left edge in **both** ref and frame and compare directly.
`sampleStops()` and draw order remain untested, but they should **not** be next.
**Measured — and this settles it from the other direction.** `tone.mjs` wants
`<ref.png> <frame_sw.raw> <W> <H> <x> <y> <w> <h>` (⚠ omit `W`/`H` and it indexes the raw at
width 0 and returns `rgb(0,0,0)` for every box, including the centre — a failed measurement that
must not be reported as a result). Called correctly:

| box | ref | frame | delta |
|---|---|---|---|
| (0, 0) 58×60 | (69, 65, 58) | (83, 78, 69) | **+14, +13, +11** |
| (0, 300) 58×60 | (109, 84, 59) | (93, 61, 54) | **−16, −23, −5** |
| (0, 700) 58×60 | (33, 29, 24) | (38, 34, 28) | +5, +5, +4 |
| (400, 380) 60×60 | (58, 45, 35) | (60, 44, 40) | +2, −1, +5 ← effectively correct |
| (900, 380) 60×60 | (71, 68, 63) | (105, 94, 85) | +34, +26, +22 |

**The deltas CHANGE SIGN.** Within the left strip alone: +14 at y=0, **−16/−23 at y=300**, +5 at
y=700. A vignette only ever darkens — it cannot be +14 at one height and −23 at another in the
same column. **The vignette is definitively not the left strip's cause**, confirmed from the
measurement side independently of the code reading.

**Strongest single clue — `box(0,300,58,60)`:** the reference is (109, 84, 59), a bright warm
orange-brown; the frame shows (93, 61, 54), darker *and* much less saturated. That is a
**content** difference, not a tone difference. At mid-height on the left wall that is almost
certainly one of the eight paintings, and each carries a light shaft
(`BEAM_W 150, BEAM_H 420, BEAM_A 0.15`, `app.nim:324-350`) drawn **over** the painting and
placard — a beam or frame-bead difference produces exactly this: local, one band, warmer in the
reference.

**Swept the band (y=300, 40px steps) — it is a BLUE EXCESS with green exact:**

| x | ref | frame | ΔR, ΔG, ΔB |
|---|---|---|---|
| 0 | (112, 94, 62) | (80, 57, 47) | **−32, −37, −15** (separate, opposite fault) |
| 40 | (109, 65, 58) | (129, 68, 75) | +20, **+3**, +17 |
| 80 | (122, 66, 64) | (151, 73, 87) | +29, **+7**, +23 |
| 120 | (127, 69, 77) | (148, 70, 99) | +21, **+1**, +22 |
| 160 | (116, 89, 100) | (117, 90, 123) | +1, **+1**, +23 |
| 200 | (105, 90, 103) | (112, 90, 132) | +7, **0**, +29 |
| 240 | (110, 73, 74) | (119, 87, 93) | +9, +14, +19 |
| 280 | (72, 66, 58) | (83, 76, 66) | +11, +10, +8 (mild, all-channel) |

From x=40–360, **green is essentially exact** while **blue runs +17…+29 high**. A tone, gamma,
fog or vignette error moves all three channels together; none produces "green exact, blue way
off". This is a **hue error — a blue excess** — pointing at a cooling term, a colour grade, or a
texture generator whose palette does not match the source. The eight generators build palettes
procedurally (`html:409-425`, `html:394`), and the app applies a per-room grade on top. The
x=0 column is a second, opposite-signed fault; x=280–360 is a mild all-channel excess.

**⚠ CORRECTION — the blue excess was an artefact of a partial sweep.** Widening to the full
width at y=300 (80px steps) shows the centre is **essentially exact**:

| x | ΔR | ΔG | ΔB | |
|---|---|---|---|---|
| 0 | −14 | −23 | −4 | |
| 80 | +27 | +6 | +23 | |
| 160 | −1 | 0 | +24 | blue-dominant |
| 240 | +12 | +14 | +17 | blue-dominant |
| 320 | +10 | +8 | +7 | |
| **400** | **+5** | **+3** | **+3** | |
| **480** | **+2** | **+2** | **+2** | |
| **560** | **+3** | **+3** | **+2** | |
| **640** | **+4** | **+4** | **+4** | |
| **720** | **0** | **0** | **−1** | |
| 800 | +15 | +14 | +14 | |
| 880 | +20 | +16 | +14 | |
| **960** | **+32** | **+38** | **+36** | largest excursion in frame |
| 1120 | +9 | +8 | +6 | |
| 1200 | +9 | +8 | +6 | |

1. **The centre is at or below tolerance across all three channels** over >25% of the frame's
   width. The corridor, walls and end wall render essentially correctly.
2. **The error is at the edges**, growing away from centre in *both* directions (+10…+27 left,
   +14…+38 right, tapering to +9).
3. **Where it is large it is a tone error** — channels move together. Only x=160 and x=240 are
   genuinely blue-dominant.

So "blue excess is the signature" is **retracted as a global claim**; it survives only at
x 160–240.

**What this now points at:** an error absent in the middle and growing toward both frustum edges
is a **sampling error at the view's edges**, not a palette or grade error. Untested candidates:
`xr.hit()` returning wrong/stale texture coords near the frustum boundary (html:200 `setPersp()`
→ `PERSP` is viewport-derived, so an FOV/x-mapping error grows with `|ndcX|` — the observed
shape); and wall-texture wrapping at `u` near 0 and 1.

#### ❌ The FOV test is unrunnable: `PERSP` is a compile-time constant

```
:54   ## Yantra windows are fixed, so innerWidth is SW. 1280*.6 = 768, in range.
:58   PERSP = max(560.0'f32, min(1000.0'f32, SW * 0.6'f32))   ## 768
:1848 proc cssX(px: int32): float32 = (float32(px) + 0.5'f32) * SCALE
:2625 let ndcX = (cssX(px) - SW * 0.5'f32) / PERSP
```

`PERSP` derives from `SW`, and `SW` is a fixed 1280 constant, so `PERSP = 768` at compile time
and **the app never reads the viewport** (`:54` says so). Rendering the same wasm into a
1600-wide surface draws the identical image; `PERSP` does not move. The FOV hypothesis is
therefore untestable by re-rendering **and implausible** — there is no viewport dependence for it
to act through.

**But the mapping narrows things.** `cssX` is strictly linear with a correct half-pixel offset and
no wrap or per-edge special case, and `ndcX = (cssX - SW/2)/PERSP` is **symmetric about the
centre by construction**. So a correct raycaster should give **symmetric edge error** — and the
observed error is emphatically not symmetric: x=0 is −14,−23,−4 while x=80 is +27,+6,+23; x=960 is
+32,+38,+36 while x=1200 is +9,+8,+6.

#### ✅ It works — and localises to a ~25px dark band at the left edge, `x 5..30`

```
x=0    d=(-14, -18, -26)   |  x=1279  d=(-9, -13, -23)   symmetric, both dark
x=1    d=(-15, -20, -26)   |  x=1278  d=(-4,  -9, -20)   symmetric, both dark
x=7    d=(-35, -30, -18)   |  x=1272  d=(-2,  -5,  -9)   LEFT far worse
x=21   d=(-51, -57, -19)   |  x=1258  d=(+9,  +8,  +7)   LEFT far worse, SIGN FLIP
x=37   d=(+17,  +4, +14)   |  x=1242  d=(+9,  +8,  +7)   symmetric again
x=58   d=( +6,   0, +12)   |  x=1221  d=(+9,  +8,  +7)   symmetric again
```

The fault is a **narrow, full-height band ~25px wide at the left edge only**, x≈5–30, far too
dark. The largest single per-channel error in the whole frame is **−57 (green) at x=21**.
Everything outside that band is close to symmetric.

This is **not** a tone error, grade, vignette, FOV effect, or palette bug — those all vary
smoothly and symmetrically. A 25px full-height strip on one side only is an **ELEMENT**: drawn
wrong, or drawn when it should not be. Candidates, in order:

1. a DOM/node element in the left margin — the gallery has placards, a title, a key map
   (`app.nim:3534`, `html:1104-1130`) and a detail overlay; anything positioned at a left offset
   lands exactly here
2. a container border / box-shadow / outline — but those are ~1–3px; a *padded panel edge* would
   fit a 25px width
3. a sprite drawn into `corrBuf` at a world x that projects into the left margin — works are
   placed by `paintX(w)` and projected through `xr`, so one placed too far left would do this

#### ✅ Not full height — it's the **LEFT WALL**, y 150…600, worst at y=500. The floor is exact.

```
y=20   x5-30: (+14,+13,+12)   x21: (+15,+14,+13)
y=150  x5-30: (-17,-15, -8)   x21: (-24,-20, -1)
y=300  x5-30: (-41,-39,-20)   x21: (-51,-58,-17)
y=500  x5-30: (-60,-53,-34)   x21: (-105,-93,-49)   <- worst in frame
y=700  x5-30: ( +7, +6, +4)   x21: ( +7, +6, +5)
y=780  x5-30: (  0,  0,  0)   x21: (  0,  0,  0)   <- EXACT
```

**Margin elements and panel edges are dead** — they would run full height and would not vanish.
A sprite is dead too: it would have a hard vertical extent. What is here is a **smooth gradient
that grows downward, peaks near y=500, and is gone by y=700.**

**The most important number in this investigation is `y=780: (0,0,0)` — EXACT.** That is the
floor, which the app composites by a *different* path (`:2681` translucent blit, not `:2694`
wall `put`). So:

- the floor pipeline is **pixel perfect** — the parked translucent-floor worry from `c499408` is
  now **closed as not-a-problem**, not merely unexamined
- the error is confined to the **wall** rasterisation above it

**The fault: the left wall, ~y=150…600, is too dark, worst at y=500 where x=21 is out by −105
red.** Asymmetric (mirrored right wall nearly correct) and smooth in both x and y — the shape of a
**texture mapping** error rather than a colour one. Check the left wall's own sample:

```nim
put(corrBuf, o, sampleTex(texWallL, TW_L, TH_L, h[1], h[2]))     ## app.nim:2694
```

i.e. whether `h[2]` — the v coordinate from `xr.hit()` — is scaled by `TH_L` correctly, and whether
`texWallL`'s v axis runs the way the code assumes. A v error is near zero at the top of the wall,
grows downward, and disappears where the floor takes over — **exactly the measured profile**.

#### ❌ CORRECTION — that theory predicts the wrong SIGN and the wrong place. It is retracted.

Check it against the measurement *before* writing any fix. It fails twice:

**1 — the sign is backwards.** At the worst point, `x=21 y=500` the delta is `(-105,-93,-49)`:
the frame is **darker** than the reference. Minification bias predicts the **opposite** — the
browser averages a minified layer, pulling it down and lowering bright spikes, while the port
keeps isolated spikes, so it should come out too *bright* (exactly the ceiling case at
`:1933-1935`). **Minification error cannot explain a frame that is too dark.**

**2 — the spatial profile is backwards.** Minification is worst *far* from the camera; near the
camera the wall is *magnified*. The worst error is at `x=5..30`, the nearest part of the left wall
— the least minified region — while the far corridor (`x=400..720`) measures `+2,+2,+2`, essentially
perfect, exactly where a minification bug would peak.

Retracted as the cause of the dominant error. It may still contribute something smaller: the
mildly-too-light bands at `x=280..360` (`+11,+10,+8`) and `x=1040..1200` (`+12,+10,+9`) are
consistent in *sign* with spikes being kept.

**What actually fits "too dark, worst on one wall, grows downward":** an **occlusion or shadow
term** — something multiplying the wall down as `v` decreases — or a beam/vignette-style
additive-negative term. **Not a filtering error: filtering errors go both ways.**

**❌ …and the scallop pass is bright, so it is refuted too.** `wallTex`'s second pass
(`:1582-1605`) is the *scallops* — decorative ellipse highlights, `html:805`, drawn last:

```nim
let t = sqrt(dx*dx + dy*dy)
if t <= 1.0'f32:
  var p = loadPx(result, (y2*TW_L + x2) * 4)
  ov(p, csample([ (0.00'f32, rgba(255, 243, 220, 0.97'f32)),
                  (0.30'f32, rgba(246, 232, 206, 0.72'f32)),
                  (0.58'f32, rgba(233, 226, 214, 0.28'f32)),
                  (0.76'f32, rgba(233, 226, 214, 0.00'f32)) ], t))
  storePx(result, TW_L, (y2*TW_L + x2) * 4, p)
```

They **add** light — they cannot produce a region that is too dark. And a wrong count or wrong
seeded positions would give bright/dark **spots**, whereas the measured profile has no spot
structure at all (`+14, −17, −41, −105, +7, 0` down the column).

#### 🚦 Gallery lane PARKED here, deliberately

Six rounds of localisation with no fix; reading a 3556-line file one proc at a time now has
negative expected value. The localisation is precise and banked:

- frame correct in the middle (`x=400..720`, deltas ≤ 4); **floor EXACT** at `y=780` `(0,0,0)` —
  which closes the parked translucent-floor worry outright
- fault is the **LEFT WALL, y 150…600**, peaking at `y=500` where `x=21` is **−105 red too dark**
- mirrored right wall nearly correct at the same heights
- it is a **darkening growing downward** — occlusion/shadow or a negative additive term, not a
  filtering error
- **refuted by evidence:** vignette, fog, blend mode, alpha-type pairing, composite algebra, stop
  values, ellipse geometry, FOV/`PERSP`, viewport, anisotropic minification (wrong sign *and*
  place), scallop pass (bright, spot-shaped)

**When this lane resumes:** read the **room grade and the beam pass** (`app.nim:324-350`, and
whatever grades `corrBuf` after section 4) — *not* the texture generators, which the evidence has
now cleared. Note `BEAM_H = 420` is within a few texels of the wall's own `TH_L = 420`, and a beam
of the wrong vertical extent would affect a band of very similar height to the one measured.
 Start with `wallTex`
(`:1542-1602`): it has a depth term at `:1569` (`depth = float32(TH_L - y)`) and a **shadow loop at
`:1586-1602`** doing `loadPx`/`storePx` into the texture. A shadow baked into the texture is
exactly a darkening that is stronger on one wall and varies with height. Then the room grade
applied after it.

*(The earlier bilinear/minification analysis below is kept for the record but does not hold.)*
 `sampleTex`
(`:1927`) is itself **correct** — bilinear with CSS-like wrapping on both axes (`u mod tw`,
`v mod th`, with negative fixup). The bug is what it is *asked* to do:

```
TW_L = 2700   ## wall element width (LEN = zNear - zFar)     app.nim:1532
TH_L =  420   ## HGT                                          app.nim:1533
put(corrBuf, o, sampleTex(texWallL, TW_L, TH_L, h[1], h[2]))  app.nim:2694
```

The corridor maps **2700 texels of width into the few hundred screen pixels** the wall occupies —
~7:1 minification or worse, and worse toward the far end where it is foreshortened. Vertically it
is near 1:1 (420 texels over ~450 rows). **The minification is strongly anisotropic.**

Bilinear is smooth only up to ~2:1. Beyond that it samples four isolated texels and never
averages the neighbourhood, keeping full-intensity texels the browser averages away when it
minifies a background layer.

**This exact bug is already documented in this very function** — found and fixed for the *ceiling*:

> *"This was nearest neighbour. The corridor maps 2700 px of texture into a few dozen screen
> pixels (the ceiling especially)… Measured on the ceiling band: the reference is a flat 21.7
> across 19 consecutive buckets, the port oscillated 30 → 122."* (`:1930-1935`)

So it is the **same bug one surface over**: nearest→bilinear fixed the ceiling, and bilinear is
now being asked to solve a ~7:1 anisotropic case it cannot. Matches the measured signature —
smooth asymmetric darkening growing along the wall, floor exact.

**Not yet explained:** why the *left* wall is badly wrong while the right is nearly correct, when
both are minified. Probably the right wall is more foreshortened so occupies few samples — not
established.

**Fix direction (not yet written):** box-filtered minification for the walls — accumulate the
texel footprint each output pixel covers and average it, as a browser does for a minified
background layer. Bilinear stays as the ~1:1 special case for surfaces that aren't minified.

**Test that separates (1)/(2) from (3):** sample columns x 5–30 at **y=20 and y=780** as well. A
DOM element in the margin appears at all heights; a raycast sprite only at the height it is drawn.

**Separate, much smaller fault:** the mild *symmetric* darkening at x=0/1 and x=1279/1278
(−14,−18,−26 vs −9,−13,−23) — a genuine both-sides edge effect, distinct from the band.
**Next (cheap and direct):** sample `x=0` and `x=1279` (plus 1/1278, 7/1272) in the same band and
compare. If the two edges differ, something treats them differently — and given the input
transform is symmetric, that **cannot be the raycast's transform**, so it points at
post-processing, the sprite pass, or how the room compositor's output is blitted.
**Fastest test:** re-render at a **different viewport width**. If the edge error stays at the same
*pixel columns* it is not FOV; if it stays at the same *relative* position it is.
**Next:** sample **each work's own screen area** — a single scanline crosses several works — and
compare per channel. **One** work blue-excess ⇒ palette bug in one generator; **all** of them ⇒ the
per-room grade or a shared post step. Same-looking symptom, completely different fixes.
**Next:** sample the eight paintings in turn and find *which* is short of saturation. All eight
equally short ⇒ the texture generator; only some ⇒ the beam or placard pass.


   rather than on values visible in the app.**
2. `sampleStops()` — whether it interpolates correctly over the vignette's `0.55..1.0` range.
3. Draw order — whether this is reached before/after the sprites, and whether anything is drawn
   over the left strip afterwards.

**Next step:** read `drawFogVig` (`app.nim` ~3399-3420, call site ~3497) and check three things
against the CSS: the radial geometry `120% 95% at 50% 50%`, the stop at `55%`, and the final
alpha `.55`. A vignette slightly off in stop or alpha darkens too little over most of the frame —
exactly what is measured.

This does **not** make the floor theory wrong; it makes it a second, smaller fault confined to
the floor plane (see above).
Check these in order — and **rule out (2) first**, because it can invalidate the rest:

1. `sampleTex(texWallL, …)` sampling the wrong region or wrapping.
2. **Something drawn AFTER the room compositor over x 0..58** — a CSS overlay, vignette, side
   panel or scrim. The `gainfit` tiles at (0,0) and (0,256) have ref lums of **79.7** and **82.8**,
   far brighter than the corridor walls around **20**, so the left strip is plausibly a
   *foreground panel*, not the wall. If so, the raycaster is not where the bug lives at all and
   time spent there is wasted. Grep the app for overlay/panel/scrim drawing after section 4.
3. `xr.hit()` returning wrong coordinates near the left frustum edge.
**Do not go straight to making `blit` opaque.** Changing it alone cannot move a 57.37% spread
across bands 0–99%, and measuring afterwards would produce a number that looks like progress
while revealing nothing about cause. Find the global cause first; the two top-middle bands that
read exactly 0% remain the best free control.
Localisation only. Nothing changed in `apps/gallery`; the parked §16.24 lead (near-floor additive
luma, suspected floor blit alpha near `app.nim:2681`) is still unexamined — check it against
finding 2 before editing.
**A1. Text measurement — `textWidth` exists, is gate-tested, but is LIVE-ONLY**

> ### 🛑 `drive` argument 4 is SCALE, not a frame count — the whole "frame 23" saga was a misread
>
> **Retracts 6712c56, c007b5b, c6c6ddf, 8f1a712.** `drive.nim`'s header reads
> `drive app.wasm out.raw W H SCALE SCRIPT`, and I had been passing a frame count in the SCALE
> slot while the script stayed at `wait:8` throughout. "Exactly frame 23" was exactly **scale
> 23**. Nothing varied frames in any of those experiments.
>
> The truth is an **unchecked out-of-memory surface allocation**:
>
> | W×H | scale | pixel bytes | result |
> |---|---|---|---|
> | 1280×816 | 22 | 1.88 GB | OK |
> | 1280×816 | 23 | 2.06 GB | **SIGSEGV** |
> | 640×408 | 23 | 0.51 GB | OK |
> | 640×408 | 46 | 2.06 GB | **SIGSEGV** |
>
> Two geometries, the same 2.06 GB budget, both crash; below ~2 GB both render. It is a **memory
> ceiling**, and it is size-independent — which is why the "size is not a factor" observation
> that looked like it ruled things out was actually **confirming** this from the start. I read a
> confirming signal as a refuting one.
>
> **The real defect worth fixing:** a failed allocation surfaces as SIGSEGV "Attempt to read from
> nil" deep inside `nimskia.save` instead of a clean error naming the size wanted. Anything
> allocating a `W*scale × H*scale` surface should check the result and report its budget.
>
> **Retracted explicitly:** "chess crashes after ~25 frames"; "engine-side, proven by a constant
> draw-list length" (len is constant because *scale* doesn't change the app's draw commands —
> never evidence); "`dropFinishedGhosts` is the leading suspect" (never tested, now unfalsified).
>
> **All five baselines re-verified from FRESH renders (SCALE 1, tol 8/255):**
>
> | app | differing | pct | reference |
> |---|---|---|---|
> | chess | 176,454 / 1,044,480 | **16.89%** | `.board/frames/ref070.png` |
> | dna | 104,291 / 1,044,480 | **9.98%** | `.board/frames/ref052.png` |
> | calligraphy | 216,607 / 1,044,480 | **20.74%** | `.board/shots/ref075.png` |
> | typewriter | 331,928 / 1,044,480 | **31.78%** | `.board/shots/ref029.png` |
> | gallery | 587,440 / 1,024,000 | **57.37%** | `.board/shots/ref039.png` |
>
> **The standard invocation** (getting it wrong cost four rounds):
>
> ```
> bash tools/build-wasm.sh apps/<name>/app.nim .board/probe/<name>.wasm
> render/native/build/drive.exe <name>.wasm <name>.raw <W> <H> 1 'wait:8'
> node tools/rawswap.mjs <name>.raw <name>_sw.raw
> node tools/pngdiff.mjs <ref>.png <name>_sw.raw <W> <H> 8
> ```
>
> Argument 4 of `drive` is **SCALE, not a frame count**; SCALE 1 is correct for all five. The
> script stays `'wait:8'` — that is the clock, not a frame budget.
>
> **Trap: calligraphy.** `apps/calligraphy/app.nim` declares `SW = 558`, `SH = 739`, but **both**
> its reference images are **1280×816** — the full page, not the app's box. `pngdiff` refuses the
> comparison rather than guessing. Render and compare at 1280×816. **Do not take the app's `SW`/`SH`
> as the render size without checking the reference's actual dimensions.** The other four do
> match theirs (typewriter 1280×816, gallery 1280×800, dna 1280×816, chess 1280×816).
>> **Method — the real lesson.** Three rounds on a hypothesis built on a misread argument, where
> every round's evidence (constant len, size-independence, determinism) was reinterpreted to fit
> the story I already held. **Re-read the tool's own signature, and vary one variable from a
> known baseline, before theorising.**
>
> **For scoring:** the correct invocation for a 1280×816 app is **SCALE 1**. Always state the
> scale next to any score. Chess re-rendered fresh that way reproduces the long-quoted figure
> exactly — `crashed=[]`, **176,454 / 1,044,480 differing = 16.89%**, mean |delta| 6.09, max 234,
> vs `.board/frames/ref070.png` at tol 8/255 — so that baseline is now a **fresh reproducible
> render**, not the stale re-score I had been quoting. Worst rows 803/27/25/26/23/24; worst cols
> 37/794/864/507/180. The other four apps are unaffected.
>> ### ⚠ It breaks the headless renderer — do not use it in a ported app yet

> ### ⚠ It breaks the headless renderer — do not use it in a ported app yet
>
> An app that calls `textWidth` compiles and links fine, and used to be refused at instantiate
> time:
>
> ```
> Error: app requires unavailable import 'y_text_measure' — refusing to instantiate [WasmtimeError]
> ```
>
> `sdk/ui/paint.nim` declares `y_text_measure` in **both** branches, and the **supply** side is
> registered unconditionally at `host/host.nim:1094`, with `cbTextMeasure` returning 0 when no
> renderer is attached. So the table was always correct — **`render/native/build/drive.exe` was
> built at 05:50 while `host.nim` was modified at 13:57**. The driver driving every measurement on
> this project simply predated the import. Rule 2 again. Rebuilding it from
> `render/native/drive.nim` does fix the instantiate error; the app then reaches `paintFrame`.
>
> **This is the part that matters:** every fidelity number in this project is produced by
> `drive.exe`, so an app using `textWidth` **cannot be scored at all**. The SDK promises
> something the measurement path cannot use, and a port that reaches for it silently loses its
> ability to be verified.
>
> Two ways out, neither taken unilaterally:
>
> 1. **Register `y_text_measure` in the headless host** (return 0, or a per-em estimate). This is
>    the right long-term fix — *an app that renders differently headless than live* is the deeper
>    problem, and it has already cost this project once. But it changes what a headless render
>    draws, so it needs a **measured before/after on all five apps**, not a quiet addition.
> 2. **Document `textWidth` as live-only** and keep it out of the ported apps for now.
>
> Chess `centred()` was wired to it as an experiment: verified it compiles (383792 bytes),
> verified it cannot render, and **reverted**. An unverifiable rendering change does not get
> committed. The gate tests for it (`dec83ca`) stand — they run inside the live engine and are
> unaffected.

> **This entry used to read "There is no text measurement API in the SDK — NOT SUPPORTED
> YET". That stopped being true: `textWidth` now exists.** Everything below about hand-rolled
> advances is kept as the *fallback* and as the record of what the gap cost, not as the
> current answer.
>
> ```nim
> textWidth*(s: string; size: float32; family = ""; weight = 400): float32
> ```
> The width of `s` drawn at `size` px in `family`, measured by the renderer against the real
> font. Use it to centre, right-align and letter-space. **Always pass the same `family` you
> draw with**, or the measurement describes a different font. Returns 0 for an empty string,
> and 0 where no renderer is attached (headless tests) rather than trapping.
>
> **Why it needed a new host import, not just a new SDK proc.** The measuring code already
> existed — `yk_text_measure2` (`skia_shim.cpp:307`, returning `getMaxIntrinsicWidth`) and
> `measureText` in `nimskia.nim:68`/`:122`, used internally by `engine.nim` for chrome,
> inputs and hit-testing. The blocker was that **`Draw` is a command string and cannot return
> a value**, so a wasm app had no way to ask. The fix follows the established shape:
> `measureTextOp` on the host object (`host/tree.nim`) → assigned in
> `render/native/engine.nim` `wireTextMetrics` → `cbTextMeasure` registered in
> `host/host.nim`'s `importTable` → declared `{.importc, cdecl.}` in `sdk/ui/paint.nim`,
> which is re-exported by `sdk/yantra.nim:40`. It returns 0 when no renderer is wired, so a
> headless host degrades instead of trapping.
>
> **Do not reintroduce a per-glyph advance table.** `MONO_ADV = 0.5498047` (dna) and
> `size * 0.667` (chess) were both stand-ins for exactly this call. A3 records that measuring
> the real advances and applying them correctly was worth **39 pixels of 1,044,480** for
> chess — so if a future port is off by a text metric, reach for `textWidth` first and only
> then suspect the renderer.
- **Asked for:** "centre this string" / "right-align it" / "where does it wrap?" inside a
  `canvas`, i.e. `text-align: center` / `right` / `text-wrap` in a draw list.
- **Happens:** you cannot. `sdk/ui/paint.nim:63` is `proc text*(d: Draw; x, y, size: float32;
  argb: uint32; s: string; weight = 400): Draw` — it returns a `Draw` and **nothing else**, it has
  **no `align` parameter**, and there is no `measureText` anywhere under `sdk/`. It is structural,
  not a missing default: `libs/nimskia/src/skia_shim.cpp:1354` calls
  `yk_text_draw(c, s, len, size, wt, 0, x, y, col, 0)` — the final `0` is the native `align`
  argument, hard-coded to left. `measureText` exists only on the native side,
  `libs/nimskia/src/nimskia.nim:68` and `:122`.
- **Workaround:** estimate. Build an advance table (A below shows what that costs), or split the
  string yourself and emit one `text` per line. **Or do not use a `canvas` for the text** — on a
  `text` node, `align = center` / `right` is real: `pAlign` (`sdk/core/wire.nim:64`) reaches
  `yk_text_draw2` with an `align` argument (`libs/nimskia/src/nimskia.nim:130`) and the engine
  measures natively there.
- **Fix:** expose the native measure to the SDK (a `textWidth(sig, font, size)` import) and add an
  `align` parameter to `Draw.text`; the shim already has the argument to pass.

  **Measured cost of the estimating workaround, and the trap that comes with it.** Letter-spaced
  runs have to be emitted one character at a time, so the port invents an advance. The chess port
  uses `adv = size * 0.667 + track`. Measured against its reference, on two independent runs:

  | run | size | track | reference span | port span | excess/char |
  |---|---|---|---|---|---|
  | `A HOT-SEAT GAME FOR TWO` (23 ch) | 12 | 4.08 | **261 px** | 275 px | **0.61** |
  | `SCORE SHEET` (11 ch) | 13 | 3.9 | **127 px** | 134 px | **0.64** |

  Solving `size * (0.667 - k)` from the two runs independently gives **k = 0.616** and **k = 0.618**
  — consistent to 0.002 across different sizes, tracks and strings, so the drift is systematic.

  **The trap: this error is invisible from the typeface, and looks exactly like a font problem.**
  The same 275 px span came out of both a Segoe UI build and a Palatino Linotype build, because
  the constant never sees the family. Anyone who fixes the family — which is the visible,
  satisfying thing to do — will find the spacing unchanged and may conclude the advance is fine.
  It is not. **Measure the span before blaming the font, and build the control that can tell
  them apart.**

  **And do not fix it by tuning the coefficient.** `k = 0.617` is the mean advance of the strings
  on that page, not a property of any typeface: a run of `I` is far narrower, a run of `W` far
  wider, and no single number is right for both. Setting it moves the scoreboard without fixing
  the cause. Per-glyph advances are the fix, and they need the measure API above.

  Measuring this needs `tools/png2raw.mjs` (decode a PNG reference to raw so the same probe tools
  accept it — validate it by differing its decode against its own source: must read 0 at tol 0)
  and `tools/textextent.mjs` (per-column ink profile → glyph clusters and advances). If two text
  runs overlap vertically, separate them by **colour**: on the chess page `0xC9A45C` has
  red-minus-blue 109 and `0xF7F0E1` has 22, which splits two runs no `y` band can.

**A2. Naming the right family with `Draw.textFace` — the CSS stack is not the answer**
- **The trap.** `Draw.textFace(x, y, size, c, family, s)` works and is reached, and the obvious
  move — read the page's `--serif` / `--sans` / `--mono` stack, keep the first family actually
  installed, pass that — is **right on chess and wrong on dna**. Measured on dna at tol 8:

  | build | differing px | % | mean |
  |---|---|---|---|
  | baseline, no family (Segoe UI) | 104 291 | **9.98 %** | 8.33 |
  | sans only, `Segoe UI Variable Text` | 104 830 | 10.04 % | 8.24 |
  | mono only, `Consolas` | 108 597 | 10.40 % | 9.17 |

  `--mono` is `JetBrains Mono, SF Mono, Menlo, Consolas, …`; the first three are absent and
  `consola.ttf` is present, so Consolas is what the *stylesheet* resolves to — and it is worse in
  **every** band measured, 4 530 → 8 122 px in the largest. **Reverted.**
- **Why.** A CSS custom property says what the *stylesheet* would pick. Canvas text is not
  styled by it — `ctx.font` carries its own font string set by the page's JavaScript. On dna the
  canvas runs are **laid out with Consolas advances** (`MONO_ADV = 0.5498047`, annotated
  "Consolas hmtx advance / unitsPerEm") yet are **not drawn in Consolas**. The ink extent is
  identical in reference, baseline and Consolas builds — the glyphs occupy the same positions and
  only the outlines differ.
- **Rule.** Resolving a font stack against installed fonts is **necessary and not sufficient**.
  Never adopt a family on the strength of the stack alone: build both, score both against the
  reference, and keep the one that moves toward it. A family that changes 0 px is being ignored
  (check the draw stream); a family that changes px but scores worse is the wrong family.
- **Two traps in the check itself.** A font-inventory probe with the wrong filename prefix will
  report a *present* font as absent — `Consolas*.ttf` matches nothing because the file is
  `consola.ttf`, and that misreport silently selects a different family downstream. Confirm the
  inventory against the real filenames once.
- And a per-region verdict can disagree with the whole-frame one: the sans-only dna build is
  **better by 141 px** inside the bands where text lives and **worse by 539 px** across the whole
  frame. **The whole frame is the gate**; a region is evidence about a region.

**A3. Measuring a font's real per-glyph advances (and killing a hypothesis with it)**
- **The problem this solves.** `letter-spacing` cannot be done through `Draw.text`, because
  there is no measure API (A1), so a port advances each glyph by hand. Chess used one flat
  `size * 0.667 + track` for every glyph. dna's `MONO_ADV = 0.5498047` carries the same shape
  of guess with a comment admitting it ("Consolas hmtx advance / unitsPerEm").
- **Do not try to measure the font with a probe frame.** It is the expensive path and it did
  not work: a standalone probe could not be made to render reliably, because the host paints
  its own background and HUD on top of the app's canvas regardless of what `buildScene`
  emits (see the degenerate-frame note above). Three attempts, then rule 8.
- **Measure it from the reference instead.** A font advance is a property of the typeface, and
  the reference renders that typeface, so **the reference's own glyph origins ARE the advance
  values**. For each glyph: `advance(c) = (origin_to_origin_spacing − track) / size`. This is
  measurement, not curve-fitting — what would be fitting is choosing a coefficient to
  minimise a diff score.
- **The self-check that separates the two.** A character that occurs twice in the string must
  measure the same twice. On the chess eyebrow, `O` read 0.743 em in both places and `T` read
  0.660 em in both. A fitted constant will not reproduce a character to 1/1000 em twice; a
  measurement will.
- **Traps, all hit.** (1) **An advance that skips a space also carries the space's width** —
  "A␣H" measures `adv(A) + adv(space) + track`, not `adv(A)`. Reading one as a single glyph
  produced a *negative* advance, which is how the bug announced itself. (2) **Cluster origins
  are integer pixel columns**, so every value carries ±1 px of quantisation — at 12 px that is
  ±0.083 em, which is 25 % of a hyphen's advance. State the precision or the table is a lie.
  (3) **The hyphen is a glyph**: 22 characters minus 3 spaces is 19 ink runs, not 18. Get this
  wrong and the cluster-count guard fires — good, that guard is why it fired.
- **And then check whether it matters.** Measured chess advances span **0.327 em (`-`) to
  0.993 em (`M`, `W`)** — a 0.667 em spread the flat constant could not express. Implementing
  the correct per-glyph table scored **176 416 vs 176 454** differing pixels: net **39 of
  1 044 480**, better in 28 rows and *worse* in 19. **Noise, so it was reverted.** A hypothesis
  is killed by implementing it correctly, not by arguing about it — and letter-spacing is now
  **eliminated** as a reason chess sits at 16.89 %. Do not re-litigate it.
- **Corollary for stale comments.** That constant was described in the code as "calibrated
  against the reference eyebrow … measures 278px wide". The reference eyebrow's ink actually
  spans **260 px** (x 835..1094, 19 glyphs); the port's own render spans **273 px**. 278 is
  neither, so the constant reproduced **the port, not the reference**. Whenever a comment
  claims a measurement, re-measure it before believing it — and check whether the port's
  notes contradict the code's account of itself.

**A. Kerned advance measurement is not available from the SDK — PARTIAL**
- **Asked for:** "how wide is this label?" — miniPaint's menu bar is
  `font-size: 12px` + `padding: 0 10px`, so an item's width is its label's **kerned Arial-12
  advance plus 20px**. There is no character-count formula anywhere upstream. `[PN "The menu bar
  is the kerned Arial advance"]`
- **Happens:** the port used `len(name) * 7 + 20`, which over-estimated all eight labels by
  **1.7 to 12.3px**, by a different amount each, because Arial is not monospaced. Kerning is not
  optional: `V+i = -0.578` and `T+o = -3.547` are the pairs that fire in this bar, so `Tools` is
  **24.47** kerned, not **28.02** — 4.125px of the bar, the largest single error in the feature.
- **Workaround:** build the advance table yourself. `config.arial12` sums real `hmtx` advances
  (recovered by positional decomposition of the eight labels — no glyph got two values from two
  labels). Pin **the raw advance sum and the kerned one as separate numbers** in `t_menu_width`,
  because conflating them is precisely the mistake that was made first.
- **Measured result:** the bar's clickable span is **x 10 .. 384**; the eight kerned advances + 20px
  predict **10 .. 384.40625**. Agreement to within half a pixel, left pad honoured.
- **Fix:** expose a kerned-advance query on the node — `render/native/engine.nim` text measure;
  test `render/native/t_character.nim` (which already does the delta-tick helper correctly).

**B. Ink is the wrong oracle for a layout question**
- **Asked for:** "where does the Help item end?"
- **Happens:** measuring the last non-background pixel read **374** against a predicted **384.4**,
  which looks like a 10px layout bug. It is glyph **ink**: `p` in "Help" has a right side bearing,
  so the ink ends ~10px early. There was **no residual**; the bar was always correct. `[PN]`
- **Workaround:** the **hit box** is the oracle, and a click reveals it. Probe by clicking at x and
  measuring which dropdown opens: `x=9 → 0 px`, `x=10 → 25500 px`, `x=384 → 3758 px`,
  `x=385 → 0 px`.

**C. Web fonts (`@font-face`) — NOT SUPPORTED YET**
- **Asked for:** a page's `@font-face` / Google Fonts stack.
- **Happens:** there is no font manager in the renderer; `font` takes a family name the system can
  resolve. Nothing in `render/native` loads a font file for an app node.
- **Workaround:** use a system family and accept the metric difference — or, for a pixel-faithful
  port, pre-measure every string against the real typeface offline (what `config.arial12` does).
- **Fix:** a font-manager path plus a per-node `SkTypeface` in `render/native/engine.nim`'s text
  mapping; test `render/native/t_font.nim` (a **new** file — it does not exist yet) loading a
  `.ttf` and asserting an advance change.

**D. Half-pixel offsets are not optional for 1px rules**
- **Asked for:** a 1px ruler tick.
- **Happens:** 1px lines land *between* pixel centres and get blended to 50% grey — 93 pure-`#111`
  pixels instead of 424. `[PN "The strip-local coordinate trap"]`
- **Workaround:** offset by half a pixel, exactly as upstream does (`i + 0.5`, `ruler.js:134` and
  `:175`). A comment in the port claimed the offset was handled "rather than by rounding a
  width"; the code did not carry it out.

**E. Text editing itself — WORKS (do not reimplement)**
`docs/roadmap.md` §1 lists **text editing (T1)** as built, and the renderer carries
`t_text.nim`, `t_richtext.nim`, `t_spell.nim`, `t_character.nim`. `[CMP]` §2 item 1 ("no selection,
copy/paste, IME, multi-line editing") is **stale**. Text *metrics* (§2.2 A) and *web fonts*
(§2.2 C) are the live text gaps.

---

### 2.3 Images & SVG

**A. WEBP decode in the Filament 3D texture path — NOT SUPPORTED YET**
- **Asked for:** `texture = "hero.webp"` on a mesh.
- **Happens:** `libs/nimfilament/src` has no webp decoder linked, so the texture has no pixels to
  sample and the surface renders black. Confirmed by `grep` over `render/native` for
  `webp|Webp|WEBP` → **0 hits**. `[EI E7]`
- **Status discipline:** the *absence of a decoder is confirmed*; the "hero renders black"
  causal link is **unproven** — the original witness app was dropped from scope, and no Filament
  scene was run. Do not quote a measured pixel value for it.
- **Workaround:** export the texture as PNG.
- **Fix:** link a decoder in `libs/nimfilament`; test `render/native/t_scene3d.nim` with a `.webp`
  texture asserting non-black pixels.

**B. WEBP / JPG export — NOT SUPPORTED YET (by design, correctly)**
- **Asked for:** "Save As → WEBP" / "→ JPG".
- **Happens:** no encoder is linked into the wasm build: no `SkWebpEncoder.h`, no
  `SkJpegEncoder.h`, no reachable libwebp/libjpeg, and the strings `SkWebpEncoder`, `WebPEncode`,
  `jpeg_encode` do not occur in the built `app.wasm` (verified by scanning the binary). The rows
  are still **offered**, refuse with upstream's honest reason string, and produce **no bytes**.
  `[EI E7/M4]` `[PN "Engine issues found"]`
- **This is correct behaviour, not a defect.** Do not "fix" it by emitting a wrong file.
- **Three distinct things are routinely conflated here** — keep them apart `[PN "CONTRADICTION 2"]`:
  1. **export** has no encoder (M4) — the wasm link;
  2. **3D texture decode** has no decoder (E7) — the Filament path, no bearing on the exporter;
  3. **app-side `imagedec.nim` decodes PNG only** and refuses JPG/TIFF/GIF/BMP/WEBP/JSON by design.
- **What *does* work, proven by byte-level round trip:** PNG, BMP, TIFF, single- and multi-frame
  GIF are pixel-exact, and JSON is byte-identical to node's `JSON.stringify(x, null, "\t")`.
- **Fix:** bind `SkWebpEncoder` / `SkJpegEncoder` into `libs/nimskia`; test
  `apps/minipaint/tests/t_saveenc.nim` + `t_export_bytes.nim` decoded by an independent decoder.

**C. Image decode on File > Open is PNG-only — PARTIAL**
- **Asked for:** open a JPG.
- **Happens:** `imagedec.nim` is a real PNG decoder (inflate + fixed/dynamic Huffman + every
  filter + palette and tRNS) and **refuses** JPG/TIFF/GIF/BMP/WEBP/JSON with a stated reason
  rather than mis-decoding them. `t_imagedec` passing 29 checks is a claim that those formats are
  **rejected honestly**, *not* that they open. `[PN "Still open"]`
- **The MIME type is SNIFFED, not reported.** `PickResult` carries `{ok, data, error}` only — no
  filename, no MIME — so `openMimeFor` infers `image/png` from the container magic and answers
  `""` for everything else. Upstream never sniffs; it reads `f.type` from the browser. Consequence:
  a non-PNG image is *rejected by the accept test* rather than mis-decoded. Recorded, not papered
  over.
- **`pickFile` returns ONE file; upstream's `<input multiple>` returns N**, so the multi-file
  ordering pass is unreachable from the picker. Dropped files *do* have a name (`y_drop_name`).
- **Fix:** add `filename` + `mime` to `PickResult` in `sdk/core/runtime.pickFile` /
  `host/host.nim`; extend `imagedec.nim`; tests `t_openfile.nim`, `t_imagedec.nim`.

**D. SVG path data inside a command stream — WORKS (was a gap)**
The shim already linked `SkParsePath.h` for `yk_svg_path`, but it was unreachable from the command
stream. A `V` verb in `runCmds` plus `Draw.svgPath` in `sdk/ui/paint.nim` closed it, because
miniPaint's `cog.js` is a `Path2D` with relative curves, H/V, smooth curves and **elliptical
arcs** — no polygon approximation of its vertices would be faithful. `[PN "The V verb, added for
cog"]`
- **Trap found by testing:** the first attempt chunked the path string at a fixed column width, cut
  `a195.425` across a line boundary, and **silently lost 1,299 characters**. A test now asserts
  `COG_PATH` is byte-identical to the upstream string.
- Elsewhere: inline SVG icons are `icon "name"` or `path(d = "M…", color = …, strokeWidth = …)`
  `[WEB]`. Toolbar icons in a rich port are `18 vector paths + 1 decoded raster` `[PN]`.

**E. Images as node props — WORKS**
`image "file.png", fit = 1` (0 contain, 1 cover, 2 fill) `[WEB]`; the renderer carries
`t_image.nim` and `t_net_image.nim`. `[CMP]` §2 item 2 ("no image node") is stale.

---

### 2.4 Gradients & shadows

**A. Node gradients — WORKS**
`fill = linear(0xFF7A2F, 0xFFD28A, 135)` is the CSS `linear-gradient` equivalent `[WEB]`;
`t_fx.nim` and `t_smooth.nim` cover the effects layer. The miniPaint gradient **tool** had to be
built from `createLinearGradient` semantics by hand — see §2.4 B.

**B. Gradient alpha is a RAMP, not a constant — a measured divergence risk**
- **Asked for:** "gradient stops at `alpha: 0`".
- **Happens:** upstream's `gradient.js:158-160` makes stop 0 the plain `color1` (alpha 255) and
  stop 1 `rgba(r, g, b, alpha/255)`, so it ramps from **255 at t=0** to `alpha` at t=1:
  `a(t) = 255 + (alpha - 255) * t`. With the shipped default `alpha: 0` (`config.js:434` →
  `config.nim` `GRADIENT_ALPHA = 0`) the layer is **opaque-to-transparent**, not uniformly
  transparent. `[PN "gradient"]`
- **Trap:** a port that writes `alpha/100*255` as a *constant* passes the obvious reading and
  disagrees with upstream. The old test asserted the constant form and was the thing that was
  wrong; at pixel (0,0) the ramp reading is correctly 255 whatever `alphaPct` is.
- **Fix:** transcribe `gradient.js` literally. Test `t_fx_cssfilter.nim` / `t_tools.nim`.

**C. Blur / backdrop blur / blend modes / masks / filters — WORKS as props**
`[CMP]` §2 item 5 ("no blur or backdrop blur, blend modes, masks, clip paths or filters… Skia has
all of these, they are just not wired up yet") is **stale**. `[WEB]` maps
`filter: blur()` → `blur`, `backdrop-filter: blur()` → `backdropBlur`, and `roadmap.md` §1 lists
"Effects (FX1): SkSL shaders, blur, frosted glass, blend modes, colour filters as props". Tests:
`t_fx.nim`, `t_smooth.nim`, and `apps/minipaint/tests/t_fx_cssfilter.nim` (600 train + 900
held-out Chrome probes per chain). Live gap: **clip paths** remain rectangular-only (`.clip`).

**D. Shadow — WORKS**
`shadow = shadow(x = 0, y = 6, blur = 18, color = rgba(0x000000, 0.35))` `[WEB]`.

**E. Skia alpha is multiplicative here too**
Any "overlay then un-dim" sequence hits §2.1 D. The active-zone overlay of the minimap is the
worked example: green at 0.3 alpha, and the reset is a balanced `P`/`p`. `[PN]`

---

### 2.5 Layout

**A. Yoga flexbox — WORKS**
`row`/`column`, `grid "1fr 2fr 200", spacing = 12:` with `span = 2`, `grow`/`shrink`,
`alignItems`, `justify`, `wrap`, `pad`/`padX`/`padTop…`, `margin`, `width`/`height`/`minWidth…`,
`absolute = true, top/left/right/bottom, z`, `sticky = 0`, `scroll = true`, `clip = true`,
`sized w:` blocks for container queries, `direction = 2` for RTL, `transitions`. `[WEB]`
Tests: `t_grid.nim`, `t_scroll.nim`, `t_sized.nim`, `t_blocks.nim`. `[CMP]` §2 item 4 ("no grid,
no breakpoints or container queries, no `position: sticky`") is **stale**.

**B. Percentages do not exist — compute them or use `grow`**
`width`/`height` are px. For a percentage, compute from `sized` or let `grow` do it. `[WEB]`

**C. Draw order is your responsibility — "drawn last" is the rule**
- **Asked for:** a ruler strip over the canvas area.
- **Happens:** the strips are `position: absolute` inside `.middle_area` and sit **on top of** the
  canvas wrapper, which `.middle_area.has-ruler` then shifts clear by 20px. Drawn first in
  `renderApp`, `drawCanvasArea` painted straight over them and **the ruler was invisible while the
  key handler reported success**. `[PN "Drawn last, not first"]`
- **Workaround:** issue the strip commands after the bitmap's, in the same draw list.

**D. Strip-local vs shared-canvas coordinates — a silent misplacement**
- **Asked for:** ruler ticks at absolute window coordinates.
- **Happens:** upstream draws into **two separate `<canvas>` elements**, so its tick coordinates are
  strip-local and it never adds an origin. A single shared draw list does. Leaving them local put
  the ticks at x 10-15, y 0-15 — **in the menu bar**. The framebuffer diff bbox was the whole
  window, which is what gave it away; confined correctly it is x 210-1070, y 40-799. `[PN "The
  strip-local coordinate trap"]`
- **Fix:** add the origin. Test: a framebuffer bbox assertion, not a colour scan.

**E. Clipping is manual, and forgetting it hides other panels**
- **Asked for:** a zoomed 800×600 raster inside a narrower column.
- **Happens:** CSS clips the canvas element to its own grid cell. Without an explicit `clip`, a
  zoomed raster paints over the right panel and **hides the minimap entirely** — which looks
  exactly like "the minimap stopped drawing". `[PN "Three engine-level drawing traps" #2]`
- **Workaround:** `.clip(x, y, w, h)` around the raster.

**F. Overlapping boxes: `handled()` is a flag, not a `return`**
- **Asked for:** "my `+` / `D` / `R` buttons do nothing".
- **Happens:** two causes, in order.
  1. **The model is a plain `var`.** Every other piece of app state is a `signals.nim` `state`,
     which subscribes the rendering effect to itself and notifies on write. `var LayerStore` does
     not, so writing to it invalidates nothing. The actions ran, mutated the model, and the frame
     was never recomputed — **0 of 1,024,000 pixels** differed from a run with no click at all.
  2. **A `state` only invalidates if the render READS it.** A `layerRev` counter that is written
     but never read does nothing, because `signals.nim`'s `get` is what creates the dependency:
     ```nim
     proc get*[T](s: Signal[T]): lent T =
       track(s)          # <- the READ creates the dependency
       s.value
     ```
     The fix is the **pair**: bump the counter after the action, and `discard layerRev.get()` at
     the top of the painter. `[PN "A button that does nothing because the model is a plain var"]`
  3. Separately, `handled()` marks the key/click consumed and **falls through** to the rest of the
     template. The minimap at y 237, 100px tall, overlaps the Layers block's toolbar at y 264-292,
     so it was tested first and swallowed every click on `+`, `D`, `R` and the arrows — the canvas
     appeared to jump and the drawing appeared to shrink. Reordering alone changed nothing; the
     panel needed both the order fix **and** an explicit `return`. `[PN "Two overlapping boxes"]`
- **Lesson to keep:** a mutation that invalidates nothing is **silent** — no error, no log, the
  action returns successfully, and the only symptom is a stale screen. A write-only signal is
  exactly as invisible as no code. Check that what you changed is something the renderer *reads*
  before checking anything else.
- **Fix:** app-side (model as `state` + read in the painter); renderer test `t_damage.nim`.

---

### 2.6 Animation & motion

**A. `transition` / `enter` / `exit` / `animate` / springs — WORKS, and better than CSS**
`[CMP]` §1: any node with `transition` slides to its new layout box, **not just items in a keyed
`each`**; exit works for any removed node; reduced motion needs no app code.
`transition = 200.ms`, `enter = …`, `exit = …`, `animate`, springs (`sdk/ui/motion.nim`).
29 checks in `t_motion.nim`. `[CMP]`
`[CMP]` §3 also records the first version of this being broken: *"The engine had no clock. The
`transition` prop was accepted but did nothing."* — **Fixed (M1)**. If a transition does nothing,
check the build, not the prop.

**B. The clock only moves forward — BROKEN for fake time (E1)**
- **Asked for:** `e.tick(1000.0)` five times in a test and assert on animation.
- **Happens:** `proc tick*(e: Engine; ms: float64)` (`render/native/engine.nim:4077-4082`) does
  `e.takeTimers()` then `e.now = max(e.now, ms)` (`:4082`). `ms` may only ever move `e.now`
  **forward**, so a constant tick advances the clock once and then no-ops. Measured against
  `examples/shell/light.wasm`:

  | drive | `e.now` after each of 10 ticks | state changes |
  |---|---|---|
  | `tick(1000.0)` ×10 | `1000.0` on every tick | **0** |
  | `tick(i * 1000.0)` ×10 | `1000, 2000, … 10000` | **3** |

  A backwards tick does not move it either. **The consequence is not "dt is wrong", it is that no
  further work happens at all**: frame events fire only if `e.now - e.lastFrameAt >= 12`
  (`engine.nim:4098`), and `e.takeTimers()` (called at `engine.nim:4081`, drain loop at
  `engine.nim:4085-4094`) only releases entries with `at <= e.now`. A constant-clock test looks
  green having measured **exactly one frame**, and any assertion about motion, easing or timing
  is **vacuous — not wrong, vacuous**. `[EI E1]`
- **Workaround:** advance by a delta — `e.tick(e.now + ms)`. `t_blocks.nim`, `t_call.nim`,
  `t_capture.nim` and `t_character.nim` already do this correctly; copy their helper.
  **Audit criterion: no test should call `tick` with a literal constant twice in a row and then
  assert on time.**
- **Do not "fix" `tick` itself** — the clamp is correct for a live clock.

**C. Timelines, springs with velocity, scroll-linked motion, gestures — NOT SUPPORTED YET**
`[CMP]` §2 item 6 and §4: `timeline`, `spring` (with velocity), `onScroll` progress, drag/pinch/
fling, shared-element transitions, GSAP-class sequencing. `roadmap.md` §1 lists "Springs and
timelines (S7)" as a **first step**. Until then: compose from `transition`/`animate` plus
`afterMs` / `after 1.2.s` / `onFrame` + `frameDt()`. `[WEB]` `[CV]`

---

### 2.7 Input & pointer

**A. Key handlers must live on the app root — BROKEN (silent)**
- **Asked for:** `canvas @c(...): onKey: …` in `app("miniPaint", …)`.
- **Happens:** `render/native/engine.nim`'s `proc key*` dispatches by walking `focus` and then its
  **ancestors** and nothing else:
  ```nim
  var at = if e.focus >= 0 and e.s.valid(e.focus): e.focus else: 0'i32
  while at >= 0:
    if e.s.handlerFor(at, E_KEY) >= 0: ... e.fire(at, E_KEY)
    at = if at == 0: -1'i32 else: e.node(at).parent
  ```
  A handler registered on a **child** is unreachable. **Clicking first does not help** — the walk
  never descends. Verified with `expandAppDsl`: root-level `onKey` expands to `winNode_….on(evKey, …)`;
  the canvas-level form expands to `canvasNode_….on(evKey, …)`, which the loop never visits.
  `[EI "Key dispatch is ancestor-only"]`
- **This is not an SDK defect** — `sdk/yantra.nim`'s `Node.on` is correct, and it matches upstream,
  which binds shortcuts on `document` rather than on the drawing surface.
- **Workaround — register on the app root, as a sibling of `canvas`:**
  ```nim
  app("miniPaint", ...):
    onKey:                     # attaches to the window node
      ...
    canvas @c(...):
      onPointerDown: ...
  ```
- **Fix:** descend the focus tree in `proc key*` — `render/native/engine.nim`; test
  `render/native/t_keys.nim` asserting a key handler on a **leaf** fires.

**B. `pointerIsLocked()` is permanently false on the wasm host — BROKEN**
`host/tree.nim:73` declares `pointerLocked*: bool`; `host/host.nim:927` reads it for the `of 8:`
host-call query (`of 7: host.frameDt` at `:926` is the working neighbour — proof the query path
works and this one field is simply never fed). **Nothing ever writes it.** The only assignment
anywhere in `host/` or `render/` is `render/native/engine.nim:3243`
`e.s.pointerLocked = e.pointerLocked` — the engine copying the value **out of** the window node's
flag into app-visible state, which can only propagate what the app already has and so cannot
bootstrap the field. `[EI E4]`
- **Workaround:** use `app(…, pointerLock = true)` and assume lock state from the app's own flag;
  Esc always releases.
- **Fix:** the native SDL host sets the flag on `SDL_EVENT_WINDOW_FOCUS` / the pointer-lock-granted
  event and clears it on loss; the wasm host needs a real async `requestPointerLock`.
  Test `render/native/t_keys.nim`.

**C. Raw wheel values in a game loop — NOT SUPPORTED YET**
Scroll areas scroll by themselves. For a game, read input through `onFrame`; there is no raw
`wheel` delta exposed. `[GAPS]` `[CV]`

**D. Pointer coordinates — use the canvas's own pixels**
`onPointerDown:` / `onPointerMove:` / `onPointerUp:` on the canvas, and `pointerPos()` = where, **in
the canvas's pixels** (not the window's). See `examples/shell/paint.nim`. `[CV]`

**E. Hit-test boxes, not ink — and never a colour probe**
Five wrong diagnoses preceded the fix for the overlapping-panel bug (zeroed geometry, an aliased
buffer, an inherited `is_vector`, a compositor resize, and a stale-frame theory that was implemented
and then measured to make no difference). `[PN]` Four probe bugs produced four confident wrong
conclusions `[PN "Reading values off the framebuffer"]`:
- a probe at y 0-7 is **painted over** by the menu bar and reads as absent;
- a probe at `WIN_H - 12` is **clipped** by the canvas edge (x bar read 299, y bar missing
  entirely); a value of 0 is indistinguishable from a 0-width bar unless you offset it;
- a white-pixel scan for a dropdown silently measures the canvas instead;
- **encode runtime values as BAR WIDTH, never as colour** — colour passes through alpha and
  overdraw; geometry cannot be misread. `[EI "Method note"]`
- when a measurement contradicts the source, **the source wins and the measurement is suspect**.

**F. Everything else in the input box — WORKS**
`keyHeld('w')`, `keyHeld(keySpace/keyShift)`, `onKey:` + `lastKey()`, `mouseDelta()`,
`app(…, pointerLock = true)`, `mouseHeld(1)`, `padConnected()` / `padAxis(padLeftX)` /
`padHeld(padA)`, `onClick:` on a 3D mesh with `pickPoint()` / `pickInstance()`. `[CV]` `[3D]`
**Always move things by `speed * frameDt()`** so the port runs the same at any frame rate. `[CV]`

### 2.7.1 `frameDt()` is the live clock — `yantra_get_dt()` is a dead field. Do not mix them up

This is the single most expensive mix-up available, because the two names look interchangeable
and only one of them is wired.

**`frameDt()` — WORKS, use this.** `sdk/ui/input.nim:45-46` is
`proc frameDt*(): float32 = yInput(7, 0)` — *"Seconds since the previous frame: move things by
`speed * frameDt()`"*. The host answers `of 7:` with `host.frameDt` (`host/host.nim:926`), and
the renderer writes that field **every single frame** at `render/native/engine.nim:3241-3242`:

```nim
e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60
e.lastFrameAt = e.now
```

So: **the first frame is a synthetic `1/60` s** — never 0, so a `speed * frameDt()` first step
cannot divide by zero or freeze — and every later frame is the **real elapsed wall-clock delta**.

**`yantra_get_dt()` — DEAD on the real runner, reads 0.** `sdk/core/runtime.nim:75` declares it
`proc yantra_get_dt*(): float32 {.importc: "yantra_get_dt", cdecl.}`. The host side is two
separate fields that never meet:

| Piece | Where | What it is |
|---|---|---|
| the threadvar | `host/host.nim:189` | `var g_frameDt {.threadvar.}: float32` |
| the callback | `host/host.nim:191-194` | `cbGetDt` returns `g_frameDt` to the guest |
| the **only** writer | `host/host.nim:1211-1213` | `proc setFrameDt*(dt: float32) = g_frameDt = dt` |
| every `setFrameDt` call site repo-wide | — | `render/render_qml.nim:42` (legacy Qt) and `host/t_run_hello.nim:107,137,140` (a test). **Zero** under `render/native/`, `cli/`, `apps/`, `web/` |

> **CORRECTED 2026-10-03.** What is widely written down — that "Yantra's `frameDt()` is a stub
> that reads 0 on the real runner" — **is wrong**, and the confusion costs real debugging time.
> Evidence: `sdk/ui/input.nim:45` is `yInput(7, 0)`; `host/host.nim:926` answers `of 7:` with
> `host.frameDt`; `render/native/engine.nim:3241-3242` sets that field every frame. **The dead
> one is `yantra_get_dt()`** (`sdk/core/runtime.nim:75`), which reads the threadvar
> `host/host.nim:189` that only `setFrameDt` (`host/host.nim:1211-1213`) ever writes, and which is
> called from exactly two places: the legacy Qt renderer and a test. **The correct rule:** animate
> off `frameDt()`. Never call `yantra_get_dt()` from an app — it returns 0 under the native
> runner, so anything driven by it simply never moves, with no error anywhere.

---

### 2.8 3D

**A. `alphaMode` / `alphaCutoff` are ignored on textured meshes — BROKEN**
- **Asked for:** `alphaMode = 2, alphaCutoff = 0.5` (Three's `alphaTest`).
- **Happens:** `render/native/scene3d.nim:119-120` does the right thing at the API edge —
  ```nim
  let alphaMode = if n.has(P_ALPHAMODE): int(n.num(P_ALPHAMODE, 0))
                  elif n.num(P_OPACITY, 1) < 1: 1 else: 0
  v.scene.surface(obj, n.num(P_NORMALSCALE, 1), alphaMode, n.num(P_ALPHACUTOFF, 0.5))
  ```
  — and hands it to the Filament shim, which has **no "texture loaded yet" state**: a texture is
  whatever `e.resolveAsset` produced, and a textured surface renders with its alpha ignored — the
  classic "3D models are opaque rectangles". `[EI E6]`
- **Workaround:** use `opacity = 0.4` (switches to blended) instead of `alphaMode = 2`.
- **Fix:** a texture-ready flag in the shim; test `render/native/t_scene3d.nim` with a cutout PNG.

**B. No asset-ready signal — NOT SUPPORTED YET**
`grep` for `assetReady|asset_ready|onAssetReady` across `render/`, `host/` and `libs/nimfilament`
returns **0 hits**. Nothing tells an app that a texture or mesh has finished decoding, so an app
that draws on the first frame draws against an empty texture — the **same** symptom as E7, and the
reason a fixed E7 would still not be sufficient alone. `[EI E8]`
- **Workaround:** defer the first draw (`afterMs` / `onFrame` counter).
- **Fix:** emit a callback from the asset pipeline; test `render/native/t_assetready.nim` — a
  **new** file that does not exist yet.

**C. No IBL, so metal renders near-black — NOT SUPPORTED YET**
`libs/nimfilament/src/filament_shim.cpp:887` builds the skybox from a **flat colour**:
`s->sky = Skybox::Builder().color({sr, sg, sb, 1.0f}).build(*s->engine);` A constant-colour skybox
gives a PBR metal nothing to reflect. `grep` for `\bibl\b|imageBased` in `libs/nimfilament/src`
finds only the `Skybox.h` include. `[EI E9]`
- **Status discipline:** the flat-colour skybox is **confirmed by reading the shim**; "near-black
  metal" was **not re-rendered** — no Filament scene was run. Mechanism established, symptom
  plausible. Do not quote a measured pixel value.
- **Workaround:** raise `scene3d(ambient = …)` (lux) and use `rough`/`glow` to fake reflections.
- **Fix:** an `.ibl` path in `filament_shim.cpp`; test `render/native/t_light.nim` asserting a
  metal's mean luminance rises above a floor.

**D. The gaps.md 3D list (authoritative)**
| Missing | Stand-in until it exists |
|---|---|
| Motion blur, SSGI, volumetric sun shafts, chromatic aberration, custom full-screen post passes | leave them out; keep the built-in finish (TAA, AO, bloom, DoF, SSR, grading, vignette) |
| Per-mesh render order / depth tricks (`renderOrder`, `depthWrite: false`, `polygonOffset`) | blended meshes sort by distance; move decals a few mm off the surface |
| Parenting 3D objects (a mesh inside a moving group) | compute children's world poses yourself in `onFrame` (or instance matrices) |
| Morph targets (blend shapes) | only if the glTF clip animates them; no direct control |
| Arbitrary per-instance shader data beyond one colour | pack it into the RGBA colour, or `uniforms` |
| Hinge joints from the SDK (the engine has them) | ask for `hinge(...)` to be exposed |
| Compressed glTF (meshopt, Draco): the loader has the decoders but it is not tested | if a model fails to load, export it uncompressed |

`[GAPS]`. Fix location for each: `render/native/scene3d.nim`, with a matching suite in
`render/native/t_scene3d.nim` / `t_physics.nim` / `t_gpu.nim`.

**E. Custom shaders — WORKS, including runtime compile failures**
Filament material code compiled natively at run time. `shader` is the body of `material()` (runs
after the built-in look); `vertex` is the body of `materialVertex()`. Inputs: `materialParams.time`,
`materialParams.u[0..3]`, `getUV0()`, `getWorldPosition()`, `getInstanceIndex()`. **A shader that
does not compile leaves the mesh as it was** — the reason is only in the log, so a "black mesh" may
be a compile failure rather than a lighting problem. `[3D]`

**F. Performance habit that is not optional**
Thousands of similar objects → ONE mesh with `instances = buf` (and `colors = buf`), **never
thousands of nodes**; per-frame movement rebuilds the placements and calls `setInstances` again
(one copy); static geometry merges into big `setGeometry` meshes by material. `[3D]`

---

### 2.9 Audio

**A. `.ogg` — NOT SUPPORTED YET**
`sound()` decodes **wav, mp3, flac**. Convert `.ogg` to `.mp3` or `.flac` and keep the name. `[GAPS]`

**B. Filters / 3D positional audio on *file* sounds — NOT SUPPORTED YET**
Use `synth` for generated sound; plain playback for files. `[GAPS]` `[CV]`

**C. Web Audio on oscillators/noise — WORKS**
`synth(freq = 440, wave = 0)` (0 sine, 1 square, 2 triangle, 3 saw); noise `wave = 4 / 5 / 6`
(white, pink, brown); `synth(filter = 1 / 2 / 3, cutoff = 800, resonance = 0.7)`;
`volume`, `attack`, `release`; `playing = sig` is the gate; `echo`/`echoMix`/`echoFeedback`;
`pan = -1..1`; `lfo = 5, lfoDepth = 0.02`. Sequencers: change `freq`/`playing` from `onFrame` or
`afterMs`. `[CV]` Tests: `t_sound.nim`, `t_synth.nim`.

**D. Fix locations:** `render/native/sound_app.nim`; each new capability lands with a case in
`render/native/t_sound.nim`.

---

### 2.10 Video

`video "file.mp4"` puts real footage in an app, with `playing`, `seek`, `volume`; audio files use
the same node. `[WEB]` `roadmap.md` §1: "`video "clip.mp4"` puts real footage in apps and films."
Tests exist: `render/native/t_video.nim`, `t_film.nim`, `t_media.nim`.
**Frames are exact** — `after` steps on the engine clock, `yantra-film` / `yantra render` renders
any app **frame-exact to H.264** through FFmpeg's libraries (`libs/nimav`), scaled from its design
size. `roadmap.md` §1. `[CMP]` §2 item 2's "no video or audio" is **stale**.
No video gap is recorded in `[GAPS]`, `[EI]` or `[PN]`.

---

### 2.11 Storage & net

**A. `[CMP]` §2 item 7 is stale for net and storage — the renderer has suites for both**
`render/native/t_net.nim`, `t_store.nim`, `t_workers.nim`, `t_net_image.nim` exist.
`[WEB]`: `fetchThen(url, proc (f: Fetched) = …, meth = "POST", body = …, headers = […])` — **the
window must list hosts** with `app(…, net = "api.example.com")`; `socket(url, proc (msg: string) = …)`
with `.send`, `.close`, `.state`; `persistent(initial, "key")` saves a signal on every change;
`newRouter("/")` with `r.push`, `r.current`; `notify(title, body)`; `startWorker` / `postMessage`.
`[GAPS]` confirms websockets and workers are among the things people assume are not there.

**B. File pick is native-host only — BROKEN on web**
`web/runner/runner.js:152-157` returns `-1` for `y_pick_open`, `y_pick_save`, `y_pick_status`,
`y_pick_body`, `y_drop_data` and `y_drop_name`, so the callback never fires and drag-and-drop has
**no data source**. Only the native host implements file pick (`host/host.nim:1058` registers
`y_pick_open`, behind `showOpenFileDialog`). **Anything you read about Open working is a
native-host claim and says nothing about the wasm/web build.** `[PN "File > Open"]`
Fix: implement the verbs in `web/runner/runner.js`; test `render/native/t_mpopen.nim`,
`t_dnd.nim`.

**C. `PickResult` has no filename and no MIME — PARTIAL**
`{ok, data, error}` only, so the app sniffs the container magic. See §2.3 C.

**D. App-level clipboard — NOT SUPPORTED YET**
Text fields copy/paste on their own (Ctrl+C/V). `[GAPS]` `[WEB]` Fix: `render/native/engine.nim`
input path; test `t_keys.nim`.

---

### 2.12 Accessibility

`render/native/a11y.nim` exists with `t_a11y.nim`; `roadmap.md` §1: "Accessibility (U10, first
step): AccessKit on Windows UI Automation." `[CMP]` §3 records that accessibility "is marked
'design now' but has no task" and that **Y1/Y2 were pulled forward**: roles are declared in the
schema next to each kind, and Tab order comes with T1.
**Status discipline:** `[CMP]` §2 item 3 ("no screen-reader support and no Tab focus order") is
dated 2026-09-26 and predates the U10 first step. It is the highest-risk claim in this chapter to
repeat unverified — check `render/native/a11y.nim` and run `t_a11y.nim` before telling anyone
accessibility is absent.

---

### 2.13 Performance

- **Never thousands of nodes.** One mesh + `instances` for thousands of objects; merge static
  geometry by material. `[3D]`
- **Filter cost is per whole-surface round trip** — see §2.1 G.
- **Per-frame pixel work in wasm is the slow path.** Two `round` calls per pixel over an 800×600
  document overflowed the wasm stack (§4/§3). Keep the per-pixel path integer; `t_no_round.nim`
  proves `quant255` bit-identical to `Math.round` over the entire 256³ blend domain *and asserts the
  ban mechanically*, so a reintroduction fails the suite instead of faulting a user. `[EI]`
- **Duplicated exported symbols are a latent perf/compile hazard.** Measured by intersecting export
  markers across `fx_canvas`, `fx_glfx`, `blendmode`, `compositor`, `tools` — 155 exported symbols,
  **four collisions**: `toByte` (identical), `composite` (differ **only in parameter names**),
  `put` (separates by first-param type), `blendOver` (identical). The build is clean because Nim
  prefers the current module's own symbol and `put`/`composite` separate by argument shape, but
  `composite` is one signature change away from a green build becoming an ambiguity error — the
  `Loop` (`render/native/motion.nim` vs `sdk/ui/motion.nim`) and `easeSpring` (`sdk/core/wire.nim`
  vs `protocol/easing.nim`) precedents were both one change away from harmless. Rename:
  `fx_canvas.toByte` → `cssToByte`, `fx_canvas.composite` → `cssComposite`, `compositor.blendOver`
  → `blendOverExact`. `[EI E3]` `[PN "Still open"]`
- **Bounds the undo/history in the currency you pay.** miniPaint pays 1.92 MB per undo entry (pixel
  copies), so its bound is `UNDO_MAX_BYTES` / `undoBudget()` (≈3 document buffers) rather than an
  entry count — upstream bounds by count because its entries hold image *references*. `[EI]`

---

### 2.14 Measuring a port: debug output, frame dumps and pixel diffs

Three traps that make a *measurement* wrong rather than a *port*. All three produce a confident
number; none of them errors.

**A. `log()` is dead under `drive.exe`, and it is not free.**
`sdk/core/runtime.nim:129-130` is the whole implementation:

```nim
proc log*(msg: string) =
  if msg.len > 0: yLog(cast[int32](msg.cstring), int32(msg.len))
```

`yLog` is `yantra_log`, and it is registered **only by the wasm host**
(`host/host.nim:1029`, handler at `host/host.nim:627` — *"the only output channel an app has"*).
`render/native/drive.nim` registers no such import, so under the native driver an app's `log()`
call goes nowhere. Worse, leaving it in costs size: one measured call added **+15,660 bytes** to
a ~215 KB module — about **7%** — because the string stays in the wasm.

> **CORRECTED 2026-10-03.** What a reader is told implicitly by the phrase "the only output
> channel an app has" — that `log()` is the way to see what the app is doing under any runner —
> is **wrong for the native runner**. Evidence: `sdk/core/runtime.nim:129-130` calls `yLog`;
> `host/host.nim:1029` is the registration and `render/native/drive.nim` has none. **The correct
> rule:** to debug an app under `drive.exe`, **draw** what you want to know, or **read pixels**.
> `log()` costs ~7% of module size to produce nothing. Remove it before you ship.

**B. Frame dumps are BGRA and must be swapped before any diff.**
`render/native/drive.nim:191-193` is the whole dump path:

```nim
var bytes = newString(px.len * 4)
copyMem(addr bytes[0], addr px[0], bytes.len)
writeFile(outPath, bytes)
```

`px` is a `seq[uint32]` of Skia `SkColor`, which is `0xAARRGGBB`. Written through on a
little-endian machine, the bytes on disk are **B, G, R, A** — the reverse of what the code reads.
`tools/pngdiff.mjs` and `tools/refdiff.mjs` read bytes 0,1,2 as R,G,B with **no swap**, so an
unswapped dump diffs against the wrong reference.

> **CORRECTED 2026-10-03.** What a first reading of "the raw dump is the framebuffer" implies —
> that the bytes are RGBA and can be fed straight to `pngdiff.mjs` — is **wrong**, and it is the
> difference between a real parity number and noise. Evidence: `render/native/drive.nim:191-193`
> (`copyMem` of a `seq[uint32]` of `SkColor`, no channel reordering anywhere in the path).
> Measured on one port against the same reference: **91.45% differing unswapped vs 72.83%
> swapped.** **The correct rule:** run
> `node tools/rawswap.mjs <in_bgra.raw> <out_sw.raw>` **first, always** — the tool's own header
> documents why, with a DOM-value proof rather than a convention. **A double swap is also a trap**:
> if a future build hands you RGBA, swapping makes it worse. Check the dominant colour against a
> known CSS value before trusting the convention in either direction.

**C. Reference PNGs are colourType 2 (RGB, 3 channels) — branch on colourType when decoding.**
A hand-rolled PNG decoder that assumes 4 bytes per pixel computes `stride = w * 4 + 1`, which
does not match the inflated IDAT and throws `Z_BUF_ERROR` on inflate. The reference PNGs in this
repo are 8-bit **colourType 2**, so `stride = w * 3 + 1`.

The shipped tools already get this right — `tools/pngdiff.mjs:36`
(`const channels = ctype === 6 ? 4 : ctype === 2 ? 3 : 0`), `tools/refdiff.mjs:40`
(`const ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]`) and `tools/census2.mjs:22` — so this bites only
when you write your own decoder in Nim or Python for a one-off comparison. Derive channels from
the IHDR `colourType` byte; never from the file's stated purpose.

---

## 3. Do NOT waste time on these

Attempts already known to fail, with the exact error text or symptom.

**3.1 `undefined symbol: floorf` / `call to undeclared function 'atan2f'`**
`sdk/minilibc/include/math.h` declares `fabsf` and `sqrtf` but not the other float variants. `floorf`
/ `ceilf` → `undefined symbol` at link time; `atan2f` → `call to undeclared function 'atan2f'`.
Same family: `cosf`, `sinf`, `tanf`, `asinf`, `acosf`, `atanf`, `expf`, `logf`, `powf` →
`call to undeclared function 'cosf'`. **Do not work around it in the app** — add the wrapper to the
header. `[EI §1]` `[EI "float trig wrappers"]`
**The ordering trap:** each wrapper must come **AFTER** the `double` prototype it calls. Placing
them with the other float helpers at the top produces a cascade of
`undeclared function 'exp'/'log'/'pow'` errors, because the `static inline` bodies are parsed
before those prototypes exist. `atan2f` **must** be defined after the `atan2` prototype.

**3.2 `call to undeclared function 'isnan'`**
`math.classify` lowers to `isNaN__pureZmath_u211`, whose C body calls `isnan(...)`.
`grep` over `sdk/minilibc` for `isnan|isinf|fpclassify` returns **0 hits**. `math.round` fails the
same way. `[EI E2]`
**Workarounds that are already in the tree:** test NaN as an explicit exponent-bit read —
`(bits shr 52) and 0x7FF == 0x7FF` (`jsonexport.nim:159`); define `jsMathRound` over integer
arithmetic (`effects_pixels.nim:61`); use a local `ffloor` and say why (`fxmenu.nim:239`); route the
NaN case to the engine's own `setInterval` (`tools.nim:1881`).

**3.3 `float64` at wasm32 — silently wrong, and it presents as a compositing bug**
`mosaicBlockPx` was spelled `int((float64(side) * float64(sizePct) / 100.0).round())` — the obvious
transcription of `Math.round`, arithmetically correct, and it **passed every host test**. On
wasm32 there is no hardware `float64`, and **Effects > Mosaic trapped the whole app on every
click**. The symptom was the whole window going uniform dark brown (app fill `(34,34,34)`, crash
overlay `(16,11,11)`) — the yantra crash dialog — which cost a long stretch of analysing it as a
layer/compositing bug, *including writing a fix for a defect that had nothing to do with it*. The
port also recorded `float64` code that produced **correct-looking output that was wrong on 83% of
random RGBA pairs**. `[EI E2]` `[PN "wasm32 float64 is a trap"]`
- Integer form of `Math.round`: `floor(x + 0.5) == (2*num + den) div (2*den)`, valid for
  non-negative inputs.
- The guard is a **source tripwire** in `t_app_intact` (comments stripped first — a doc comment
  explaining the ban contains the banned word), verified by reinstating the `float64` form.

**3.4 `memory fault at wasm address 0xffffffec` / `wasm trap: out of bounds memory access`**
Root cause found after five bisect rounds: `blendOver` and `applyOpacity` each called `round` —
**four times per pixel** — over the whole 800×600 document, and in this wasm target
`std/math.round` lowers to a mini-libc `round` that is implemented **RECURSIVELY**. It was a stack
overflow. `[EI "SOLVED (second time, verified)"]`
**Retracted conclusions — do not re-investigate these:** "the canvas is 100x400" (the digit-colour
probe was reading shim blends `0xFFFF8888` as palette entries; a bar-width probe reads 800×600);
"presentDocument never runs on a click" (probe flags overwritten); "the canvas hit box is small" (the
`boxes` verb shows 1280×800 at (0,0)); "there is a wasm trap" (first claim — `drive.nim`'s `crash`
verb printed a phantom `CRASH| ` line on clean runs because `"".splitLines` is `@[""]`, fixed in
`5e05a4b`); "`-Wl,--initial-memory=67108864` will fix it" (grew the heap from ~8.9 MB to 64 MB and
the fault was **byte-identical**, still `-20`); "it is memory exhaustion"; "it is a
`compositeOrder`/`src` index" (guards at both sites never fire); "the float maths is it" (a plain
byte copy, same loop shape and bounds, still traps); "it is size-dependent" (100×100 traps at the
same address); `flatten`'s body; `tools.nim`'s `dab`/`put`/`px`/`inBounds`/`idx`; `surface.write`'s
arguments; the `Ctx`/`Compositor` copies. `[EI]`
**A `by-value` struct parameter deep-copies.** `proc flatten*(c: var Compositor; …)` — was
`c: Compositor`. A `Compositor` holds one 1,920,000-byte `seq[uint8]` per layer, so passing it by
value deep-copied **every layer buffer on every present**. (This is a real cost and was worth
fixing — it was **not** the fault. `tests/t_flatten_borrow.nim` (3 tests) pins the signature text
out of `compositor.nim`, asserts flatten leaves the caller's compositor and buffers untouched, and
that 20 consecutive flattens composite real pixels.) `[EI]`

**3.5 A wasm out-of-bounds read kills the app silently, with no crash record**
`Engine.crashed` **stays empty**, `hitTest` keeps returning the right node, and the app simply
stops responding with the last frame frozen. The frame after the offending click can be
**byte-identical to the baseline**, which looks exactly like "the handler ran and changed nothing".
Two rules: a frame identical to the baseline is **ambiguous** — send a SECOND, known-good event; if
that also produces no change, the app died. And **`Engine.crashed` is not a reliable indicator**
for a trap inside the wasm guest. `[EI "A wasm out-of-bounds read…"]`
The reproduction was `drawMenuDropdown` indexing a filtered sequence by the unfiltered index
(`ys[i]` over non-divider rows).

**3.6 When bisecting a wasm fault: DELETE code, never gate it**
Three rounds of "disable this call" produced contradictory results because the compiler
**inlines**, so `if false:` or an early `return` around a call does not remove the code. The
techniques that work, in order: (a) **prefix-grow the handler body** one literal line at a time
(257 of 258 lines were clean; the fault was the last line, `saveCurrentLayerFrom(ctx); presentDocument()`);
(b) **rename the proc and leave a stub under the original name**, so the body is unreachable and
cannot be inlined. Gating works only for "disable the body", never for "disable one call inside a
body". `[EI "Why five bisect rounds all pointed the wrong way"]` `[EI "Fourth round"]`

**3.7 Probes inside a trapping code path cannot measure the trap**
Every bar-width probe placed inside the app read **nothing** (not zero — absent) on a post-click
frame, because the click handler traps and the frame is never completed. Probes must live in a frame
that **survives**, or the measurement must come from outside the wasm entirely (the driver's `crash`
verb, or a headless test). A probe placed at the end of `renderApp` produced **no bars even on a
clean startup frame** — do not trust an in-app framebuffer probe whose forced-on sanity run has not
first been shown to draw. `[EI "Fifth round"]` `[EI "Instrumentation note"]`

**3.8 The stale-build traps (three separate ones)**
- `render/native/build/shot_excal.exe` is a **prebuilt** screenshot helper that predates the `V`
  verb, so a new verb renders as empty with no error — the wasm was correct, the harness was not.
  Build it from `render/native/shot.nim` (adding every `libs/*` path). **A screenshot proves what
  the harness drew.** `[EI §5]`
- `tools/build-wasm.sh` **reuses one nimcache** (`apps/minipaint/nimcache`) across differently
  flagged builds. `YANTRA_NIM_FLAGS=-d:minipaint_gallery` then a plain build produced a wasm that
  **still contained the gallery**. Any `-d:` switch through this script needs
  `rm -rf apps/minipaint/nimcache` first. `[EI "build-wasm.sh reuses one nimcache…"]`
- A claim of "fixed" backed by one clean run that was a **stale-wasm read** — the build printed
  741,145 bytes but the wasm actually exercised was the previous one. Rebuilt and re-run three
  times from an identical tree, the fault was deterministic. `[EI "CORRECTION to 683cd8a"]`

**3.9 MSYS paths are not converted for native tools**
`nim.exe` needs native paths (`pwd -W`). An `/c/...` `-I` is passed through verbatim and the header
is "not found". For the vendored `drive.nim` build, `--path` must be repeated **per package *and*
for each `src/`** (`--path:libs/$n` alone is insufficient); C headers come from `third_party`. `[EI
"Recovering a vendored drive.nim build"]`

**3.10 `handled()` does not return, and the `of t` tool dispatch swallows unknown tools**
`handled()` is a flag setter, not a control-flow return — it marks the click consumed and falls
through to the rest of the template. `[PN "Two overlapping boxes"]` In miniPaint, `select`,
`selection` and `media` have no arm in the tool `case`, so a click with any of them selected falls
through to `painting.set(true)` — the **brush path**. `[PN "Still open"]`

**3.11 `discard` as an early return**
In a proc with a return value, `discard` discards the *result value* and execution **falls through**
into the body. The correct form is `return d`. `[PN "One real Nim trap"]`

**3.12 "The image is 100x400" / "the framebuffer is unchanged" / "the test proves it works"**
Three classes of false conclusion to check before filing:
- **A unit test on a struct the app never populates is testing a fiction.** `w`, `h`, `surface`,
  `color` matched between test fixture and app; `live` and `buf` did not. `[EI]`
- **Green tests over an unexercised path.** `fx_glfx` is pinned against a `Math.fround`
  transcription of the GLSL, **not a driver** — nothing in this repo has run it on a GPU, so a real
  driver may differ by ~1 LSB on `sin`/`pow`, on the bilinear unit's 8.8 fixed-point weighting, on
  unorm8 rounding, or on spec-undefined **reversed** `smoothstep` edges. `[EI M3]`
- **A decoder round trip cannot see a palette that was never upstream's.** GIF export is a valid
  GIF with exact geometry but a deterministic **first-appearance** quantiser, not NeuQuant
  (NeuQuant needs floating point the wasm target does not have cleanly), so a photograph's colours
  **will differ** from upstream — and `t_export_bytes.nim` is green and cannot detect it. `[EI M2]`

**3.13 Things that are red on purpose — do not "fix" them**
`apps/minipaint/tests/t_fx_cssfilter.nim` prints `1 CHAINS OUTSIDE TOLERANCE` and **exits 1 by
design**: ten of eleven CSS filter chains are held-out exact, and `pencil` is the single red at
83.11% held-out (worst error 1/255, `tol +0`). Widening `pencil`'s `tol` from `0`
(`t_fx_cssfilter.nim:40`) would be cheating. `[EI M1]` `[PN "Audit record"]`

---

## 4. Things that LOOK unsupported but actually work

Equally valuable. Reimplementing any of these is wasted effort. `[GAPS]` states most of them
explicitly as "people assume they are not" there.

| Thing | Status | Where |
|---|---|---|
| Instancing with per-instance colours | **WORKS** | `instances = buf`, `colors = buf` (4 bytes RGBA/instance); `place(x,y,z,rotY,sx)` makes a matrix `[3D]` |
| Custom shaders compiled at **run time** (Filament material + vertex bodies) | **WORKS** | `shader = …`, `vertex = …`, `uniforms = "16 numbers"` `[3D]` |
| Cameras rendered into textures | **WORKS** | `camera(target = "mirror", width = 512, height = 512, …)` + `texture = "view:mirror"` `[3D]` |
| Skinned characters with crossfades and bone control | **WORKS** | `play = "Run"` signal crossfades over `blendTime`; `turnBone("hero","Head",x,y,z)`, `resetBone`, `bonePos(...)`, `animSpeed`, `animTime` `[3D]` |
| Crowds | **WORKS** | one `model` with `instances = buf`; each copy animates out of step `[3D]` |
| Jolt physics with **ropes and raycasts** | **WORKS** | `rope("hero", (ax,ay,az), length)`, `cut(r)`; `raycast(origin, dir, reach = 100)` → `hit`, `name`, `distance`, `point` `[3D]` `[GAPS]` |
| Particles (camera-facing, blended, fading) | **WORKS** | `particles(posY = 1, rate = 200, burst = sig, lifetime = 1.2, …)`; `burst = "300#" & $n` `[3D]` |
| Synthesis (Web Audio `OscillatorNode`/`BiquadFilterNode`/`GainNode`/`DelayNode`/`StereoPanner`/LFO) | **WORKS** | `synth(...)` — full table in `[CV]` §Web Audio |
| 2D raster **layers** with blend modes, pixel read/write, filters | **WORKS** | `newLayer(w,h)`, `layer.read/write/filter`, `.layer(l,x,y)`, `.blend(bMultiply)` `[CV]` `[GAPS]` |
| Pointer lock | **WORKS** | `app(…, pointerLock = true)` (Esc always releases); `pointerIsLocked()` is the broken part (§2.7 B), not the lock `[CV]` |
| Gamepads | **WORKS** | `padConnected()`, `padAxis(padLeftX)` (sticks -1..1, triggers 0..1), `padHeld(padA)` `[CV]` |
| 3D picking | **WORKS** | `onClick:` on the mesh, `pickPoint()`, `pickInstance()` `[CV]` `[3D]` |
| Video and audio nodes | **WORKS** | `video "file.mp4"` with `playing`, `seek`, `volume` `[WEB]`; tests `t_video.nim`, `t_media.nim` |
| WebSockets and workers | **WORKS** | `socket(url, cb)` + `.send/.close/.state`; `startWorker` / `postMessage` `[WEB]` `[GAPS]` |
| Text editing (selection, copy/paste, IME, multi-line) | **WORKS** | `roadmap.md` §1 "text editing (T1)"; `t_text.nim`, `t_richtext.nim`, `t_spell.nim` |
| Image node, network images | **WORKS** | `image "file.png", fit = 1`; `t_image.nim`, `t_net_image.nim` |
| CSS **grid**, `position: sticky`, container queries | **WORKS** | `grid "1fr 2fr 200", spacing = 12:`; `sticky = 0`; `sized w:`; `t_grid.nim`, `t_sized.nim`, `t_scroll.nim` |
| Motion that outlives the app thread | **WORKS (and better than CSS)** | `transition`, `enter`, `exit`, `animate` are props the engine plays — including **layout-box** changes and exit on *any* removed node; reduced motion needs no app code. 29 checks in `t_motion.nim` `[CMP]` |
| Effects as props: SkSL shaders, blur, frosted glass, blend modes, colour filters | **WORKS** | `roadmap.md` §1 (FX1); `style.md §8`; `t_fx.nim`, `t_smooth.nim` |
| Accessibility (first step) | **WORKS (partial)** | `render/native/a11y.nim` + `t_a11y.nim`; AccessKit on Windows UI Automation `[roadmap §1]` |
| Virtualised lists, long lists | **WORKS** | `t_vlist.nim`, `t_longlist.nim` exist `[CMP]` §2 item 8 is stale |
| Frame-exact H.264 export of any app | **WORKS** | `after` steps on the engine clock; `yantra-film` / `yantra render` via FFmpeg (`libs/nimav`) `[roadmap §1]` |
| Vector PDF export | **WORKS (first step)** | `page`/`slide` nodes; `yantra-pdf` / `exportPdf` writes one vector PDF page each `[roadmap §1]` |
| SVG path data in a draw list | **WORKS** | `V` verb + `Draw.svgPath`; also `icon "name"` / `path(d=…)` `[PN]` `[WEB]` |
| Arbitrary geometry from a port | **WORKS** | `newBuffer()` + `setGeometry(verts, tris)`, verts are 8 floats `x y z nx ny nz u v`; generate Extrude/Lathe/Shape triangles in Nim `[3D]` |
| `DataTexture` / `CanvasTexture` | **WORKS** | `texture = "pixels:" & $int32(buf) & ":" & $w & ":" & $h`; `texture = "layer:" & $int32(myLayer)` (re-uploads on draw) `[3D]` `[CV]` |
| Hot reload with state, live source edits | **WORKS (first step)** | `@name` handles, typed `set / insert after / remove` written into source and hot-reloaded (`docs/ai.md §0`) `[roadmap §1]` |
| **Ellipses** / squashed circles in a `Draw` list | **WORKS** | `Draw.ellipse(cx, cy, rx, ry, c)` — `sdk/ui/paint.nim`. The shim's `'E'` verb has always read **four** numbers and called `drawOval(LTRB(cx-rx,cy-ry,cx+rx,cy+ry))`; only the `circle` wrapper collapsed them by passing `r` twice. `rx==ry` reproduces `circle` byte-for-byte, so it is a strict superset. `Draw.scale(sx,sy)` inside `save`/`restore` also squashes a circle. Tested in `t_paint.nim` |
| **Naming a typeface** in a `Draw` list | **WORKS** | `Draw.textFace(x, y, size, c, family, s)` — verb `'N'`, `sdk/ui/paint.nim`. family and string are two `;`-terminated fields with **no space between them**, because the shim's `rest()` stops at `;`; a space becomes part of the font name. Tested in `t_paint.nim` |

**The stale-claim pattern, stated once so it stops costing rounds.** Every
false "the engine cannot X" claim found in `apps/*/port-notes.md` so far has been a
**wrapper** gap, not an engine gap: the verb existed in the shim and only the SDK
proc was missing or wrong. Three examples, all now fixed:

| Port note said | Actually |
|---|---|
| "Draw has NO ellipse primitive (circle … cannot be squashed)" | `'E'` took `rx, ry` all along; `Draw.scale` squashes too |
| "Draw.text cannot name a typeface — hardcodes Segoe UI" | `Draw.textFace` exists (verb `'N'`) |
| "the CSS font stack says which font this text uses" | **It does not, for canvas text.** See the warning below — measured both ways |
| "multi-stop gradients are unavailable" (node) | nodes genuinely are 2-stop (`pGradFrom`/`pGradTo`/`pGradAngle`); the *canvas* has no gradient primitive at all — two different subsystems, two different answers |

**The check that catches all three in one grep:** when a note claims a capability is
missing, read the shim's `case` for the verb and see what it actually consumes, *and*
look for working code nearby in the same file. All three had working code within a few
dozen lines of the comment claiming the thing was impossible.

---

## 4b. Verified-absent — re-checked against the engine, so don't re-derive these

Checked 2026-10-04 against `libs/nimskia/src/skia_shim.cpp`, `sdk/ui/paint.nim` and
`sdk/core/wire.nim`. These are **real**. If you are about to plan a workaround for one
of them, that is time well spent — but do not re-open the question without new evidence.

| Capability | Verdict | Evidence |
|---|---|---|
| Clip to an arbitrary **path** | **ABSENT** | only `clipRect` and `clipRRect` exist (`skia_shim.cpp:239, 517, 573, 1013`, verb `'K'` at `:1424`); no `clipPath` anywhere. `Draw.clip` is axis-aligned only |
| `setLineDash` / dashed strokes | **ABSENT** | no occurrence of "dash" (case-insensitive) in the shim. A dashed run must be drawn as individual segments — which is what the dna port does |
| **Even-odd** path fill | **ABSENT** | no `FillType`, `EvenOdd` or `kWinding` in the shim; `'F'` calls `drawPath` with the default winding rule |
| Canvas gradient | **ABSENT** | no gradient verb in `paint.nim` at all. A node gradient is 2-stop only (`wire.nim` `pGradFrom`/`pGradTo`/`pGradAngle`) |
| 2D node **rotation** prop | **ABSENT** | `wire.nim` has `pRotX`/`pRotY`/`pRotZ` (3D) but no 2D rotate. Note `Draw.rotate` *does* exist (`paint.nim:99`, verb `'o'`) — so rotation is canvas-only |
| Multi-stop / radial / conic gradient | **ABSENT** | see above |

---

**Still stale in `[CMP]` (do not quote these):** §2 items 2 (images/media), 3 (accessibility),
4 (grid/sticky/container queries), 5 (blur/blend/masks/filters), 7 (net/storage/routing) — all have
renderer suites today; item 1's text-editing claim is superseded by T1.

---

## 5. Recommended engineering fixes — for the gaps that matter when porting a rich page

Each row: **the gap → the file in `render/native/` (or `libs/`) → the prop/verb → the `t_*.nim`
test to add in the same change.** This follows `AGENTS.md` rule 6: a new capability needs the
renderer mapping **and** a test in the same task — and rule 3: never weaken a test to make it pass.

| # | Gap (blocks what) | Renderer change | Prop / verb | Test to add (and extend) |
|---|---|---|---|---|
| 1 | `arc()` ≥ 180° (any chart, donut, clock face) | `libs/nimskia/src/skia_shim.cpp` `arcTo` — split the sweep, emit each half's `moveTo` | `A` verb | **new `render/native/t_paint_arc.nim`** |
| 2 | fill-then-stroke (any outlined shape) | `skia_shim.cpp` `case 'F'` — draw without `detach()`, or add a commit verb | `F` / `S` | **new `render/native/t_paint_path.nim`** |
| 3 | `globalAlpha` scoping (every overlay, tooltip, scrim) | `skia_shim.cpp` `O` — assign instead of multiply, or push onto the saved state | `O` with `P`/`p` | **new `render/native/t_paint_alpha.nim`** |
| 4 | key handlers on child nodes (every canvas app) | `render/native/engine.nim` `proc key*` — descend the focus tree | `Node.on(evKey, …)` | `render/native/t_keys.nim` |
| 5 | `pointerIsLocked()` always false | `host/tree.nim:73` + `host/host.nim:801` — assign on focus/pointer-lock-gained, clear on loss | `of 8:` host call | `render/native/t_keys.nim` |
| 6 | clock only moves forward (every timing test) | harness, **not** `tick`: a `tickN(n, ms)` delta helper | `Engine.tick` | extend `t_blocks.nim` / `t_call.nim` / `t_capture.nim` / `t_character.nim` with the audit criterion "no constant `tick` twice, then assert on time" |
| 7 | WEBP decode for 3D textures (any textured model) | `libs/nimfilament/src` — link a webp decoder | `texture` | `render/native/t_scene3d.nim` |
| 8 | no asset-ready signal (first-frame black textures) | `render/native/engine.nim` asset path — emit a callback | new `onAssetReady` on the scene node | **new `render/native/t_assetready.nim`** |
| 9 | metal renders near-black (any PBR product shot) | `libs/nimfilament/src/filament_shim.cpp:887` — an `.ibl` skybox instead of a flat colour | `scene3d(ibl = "x.ibl")` | `render/native/t_light.nim` (mean-luminance floor) |
| 10 | `alphaMode`/`alphaCutoff` ignored on textured meshes (foliage, cutouts) | `render/native/scene3d.nim:119-120` + a texture-ready flag in the shim | `alphaMode`, `alphaCutoff` | `render/native/t_scene3d.nim` |
| 11 | web fonts / `@font-face` (any branded page) | `render/native/engine.nim` text mapping — a font manager + per-node `SkTypeface` | `font`, new `fontFile` | **new `render/native/t_font.nim`** |
| 12 | kerned advance measurement (any measured layout) | `render/native/engine.nim` text measure — expose kerned advances | `textWidth(sig, font, size)` | `render/native/t_character.nim` (already has the delta helper) |
| 13 | clip paths (any non-rectangular mask) | `render/native/engine.nim` + `skia_shim.cpp` — a path clip verb, not just `clip(x,y,w,h)` | `clipPath(d)` | `render/native/t_paint.nim` |
| 14 | timelines / springs with velocity / gestures (GSAP-class motion) | `render/native/motion.nim` | `timeline`, `spring`, `onScroll` | `render/native/t_motion.nim` (extend the 29 checks) |
| 15 | raw wheel delta (games, custom scroll) | `render/native/engine.nim` input path | `wheelDelta()` | `render/native/t_keys.nim` |
| 16 | app-level clipboard (copy a row, paste into a field) | `render/native/engine.nim` | `clipboardRead` / `clipboardWrite` | `render/native/t_keys.nim` |
| **17** | **translucent fills paint ~1.7/255 stronger than requested — every soft radial in every port** (shadow, glow, vignette, fog, brush blur) | `libs/nimskia/src/skia_shim.cpp` — find why a byte-3 fill lands near byte 4.2 | `E` (also `R`, and `circle` under `s`) | **new `render/native/t_paint_stack.nim`** — a fill at a known alpha on a bare frame, assert the recovered alpha |

### Row 17 in detail — measured in a bare frame, and smaller than it first looked

Every CSS radial gradient has to be faked with a stack of concentric translucent ovals, so
this row is the one that decides whether soft shadows, glows and vignettes are faithful.

**The measurement that counts** was taken in a frame containing *nothing but the probe*: no
layer, no props, no machine, nothing drawn over it, differenced against a twin that differs
by one integer. Ten identical shapes, ten screen positions:

| path | recovered alpha | spread over 10 shapes | excess |
|---|---|---|---|
| `Draw.ellipse` with `rx == ry` | 0.0166 | **0.00 / 255** | **+1.68 / 255** |
| `Draw.circle` under `scale(1, 0.8)` | 0.0166 | **0.00 / 255** | **+1.68 / 255** |

Requested was 0.01 (byte 3); the renderer lands near byte 4.2. **Zero spread across ten
independent shapes is what makes this a renderer property and not measurement noise.**

Two things this rules out, both of which were believed for a while and are now retired:

- **It is not transform-dependent.** `scale` and no `scale` give identical alpha. A squash
  changes nothing.
- **Shapes do not vanish.** No ratio, size or draw count makes a fill disappear. Every one
  of twenty shapes rendered at exactly its geometric pixel count.

**What it costs.** A 28-band radial pays it 28 times, at roughly +0.12 alpha — which is
exactly the excess the typewriter machine shadow measures. Small, but it accumulates with
band count, so it is worth fixing in the renderer.

**The mechanism is still not identified.** Worth measuring in the shim: whether the paint
carries alpha between draws (note `SkPaint paint` is constructed fresh inside the command
loop, so this is unlikely); whether the target surface or layer is not
`SrcOver`/premultiplied; whether Skia's antialiased edge coverage bleeds inward at low alpha.

**Code sites, read and narrowed.** These are the places a fix would live — the *hypotheses*
are labelled unverified on purpose, because reading the code is not measuring it.

| site | what it does | bearing on the defect |
|---|---|---|
| `skia_shim.cpp:1196-1203` `color()` | `strtoull(p, &q, 0)`; returns **`0xFF000000`** when `q == p` | a colour that fails to parse becomes **opaque black**, not a no-op. Worth checking whether any draw passes a malformed colour, because that would show up as *too dark*, not too light |
| `skia_shim.cpp:1324` `SkPaint paint;` | constructed **fresh per command**, `setAntiAlias(true)` | rules out alpha leaking between draws — already suspected and now confirmed by reading, though still worth a test |
| `skia_shim.cpp:1327` the `colour` lambda | `paint.setColor(SkColor(argb)); if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha)` | the only place alpha is applied. **The premultiplication theory is eliminated — see below** |
| `skia_shim.cpp:1341-1347` `'R'`/`'B'`/`'E'` | `drawRRect` / `drawOval`, all via the same lambda | the defect was measured on `ellipse`, so `'E'` is the minimal reproducer |

**Two leads closed by arithmetic, without a probe.** Reading the sites is not measuring them,
but it can still *refute* a theory, and that is cheap:

- **Premultiplication is NOT the cause.** `SkColor` is premultiplied by Skia convention while
  the SDK hands over straight `0xAARRGGBB`, so passing one for the other is a real latent bug
  — but it cannot produce this symptom. At alpha 0.01 over black the correct result is ~2.55,
  and a straight-as-premultiplied read would give the *fill colour itself* (~60 for a mid
  grey, saturated for anything pale) — a wildly wrong number, not one that overshoots by
  1.68. The measurement sits next to the correct value, so the renderer is not misreading the
  colour. This holds for any fill colour that is not itself near-white; a white fill at this
  alpha would be degenerate, so re-check it if the probe's fill is ever changed.
- **A failed colour parse is not it either**, for a reason worth stating: `color()` returning
  `0xFF000000` would render **opaque black**, which is far darker than the reference, and the
  defect is an excess, not a deficit.

**Every surface is `SkImageInfo::MakeN32Premul(w, h)`** — `:224`, `:694`, `:851`, `:862`,
`:1240` (the drawing surface) — via the single-argument overload, which leaves the colour
space null. **No colour management is attached anywhere**, so the browser's sRGB blend and
Skia's blend are both happening in whatever that un-tagged space is. This is the one lead
still standing, and it fits the shape of the number: a **fixed** +1.68/255 excess that does
not shrink as alpha falls is a conversion or rounding applied **after** the blend, not a
compositing error, which would be proportional to alpha.

**The test that would settle it, in order of cost:** render one white fill at alpha 0.01 on
black through `'E'`; then the same with the surface built through the four-argument
`SkImageInfo::Make(w, h, kN32_SkColorType, kPremul_SkAlphaType, SkColorSpace::MakeSRGB())`;
then the same with the colour premultiplied before `setColor`. The first that moves byte 4.2
to 2.55 is the cause. Until one does, treat "+1.68/255" as a **symptom with a known magnitude
and no known mechanism** — not as a characterised defect.

**Do not tune around it in app code.** Lowering the band count shrinks the error and coarsens
the gradient in the same move — trading a renderer defect for a fidelity one and hiding both.

#### The methodology note, which cost four rounds to learn

An earlier version of this row claimed a 28-band stack over-composites by **+0.2 alpha** and
that fills **vanish at particular scale ratios**. Both were **artefacts of occluders**, and
the row is corrected because the errors are instructive:

- A probe shape drawn early and then covered by scene content is **indistinguishable from
  one that was never drawn** under a frame-difference isolation. That produced a
  "missing shapes" bug that survived three rounds of increasingly elaborate probing.
- The same contamination inflated a real +1.7/255 effect into an apparent +4 to +13/255,
  and invented a transform dependency that does not exist.

**Build the degenerate frame first.** A probe frame containing only the probe — nothing but the
probe, no layer, no occluders, plus a twin differing by one integer — costs one build and settles
what hours of scene-differencing cannot. Only after a clean baseline exists is it worth
re-introducing the scene.

**…but you do not get to choose the background, and this is measured, not assumed.** An earlier
version of this note said "flat background" as part of the recipe. **That was wrong.** A probe
whose first and only command is `d.rect(0, 0, FW, VH, 0xFF101010)` still renders with the
background **RGB(18, 34, 58)** at every sampled corner *and* at the centre — the app's full-canvas
rect does not become the background, the host supplies it. The same thing was seen earlier as a
"modal_bg ~45–54" puzzle; it was never a puzzle, it was this.

So: **measure the background, never assume it.** Take the modal luma of the rendered frame (as
`textextent.mjs` already does) and threshold against that. Assuming the value you drew is the
classic probe failure — it marks ~94 % of the frame as ink and every measurement returns
nonsense while looking like a rendering problem.

Three further geometry facts, all measured on the same probe, none of which are guessable:

- **Text ink does not start where you asked.** A `Draw.textFace` at `x = 4` put its first ink
  pixel at `x = 28`, and at `y = 6` the ink began at `y = 22` with a cap height of 8 px at size
  12 (so the baseline sat ~24 px down). **Derive the offset empirically from the frame; never
  compute band bounds from the coordinates you passed in.**
- **Band bounds clip.** Two repeat counts of one glyph at size 12 both ran to the edge of a
  213 px measurement window, giving an identical width for both and an advance of 0. A window
  narrower than the run silently truncates it. Check `bx` against the window edge before
  believing a span.
- **A large draw list appears to truncate.** 126 text calls in one frame produced ink for
  roughly the first 24 characters and nothing after; 42 calls rendered only the first handful.
  This is uncharacterised — **do not treat it as a fixed cap**, but do treat it as a reason to
  keep probes small and to verify *every* expected cell has ink before believing any of them.
| 17 | `0x00RRGGBB` reads as opaque (any fade-to-nothing) | `render/native/engine.nim` colour decode | colour semantics; keep `opacity = 0` as the answer today | `render/native/t_paint.nim` |
| 18 | file pick on web / no filename-MIME in `PickResult` | `web/runner/runner.js:152-157` + `host/host.nim:932`; add `filename`/`mime` to `PickResult` in `sdk/core/runtime.pickFile` | `y_pick_*`, `PickResult` | `render/native/t_mpopen.nim`, `t_dnd.nim` |
| 19 | raw wheel → also: `<input type="color">` gradient picker (a rich colour UI) | app-side today; needs a `color` control in `sdk/ui/widgets.nim` drawn by `engine.nim` | `color` control | `render/native/t_chrome.nim` |
| 20 | per-mesh render order / depth writes (decals, transparent overlays in 3D) | `render/native/scene3d.nim` | `renderOrder`, `depthWrite`, `polygonOffset` | `render/native/t_scene3d.nim` |
| 21 | 3D parenting (a mesh inside a moving group) | `render/native/scene3d.nim` | `parent = "groupName"` | `render/native/t_scene3d.nim` / `t_physics.nim` |
| 22 | filters / 3D panning on file sounds | `render/native/sound_app.nim` | `filter`, `positional` | `render/native/t_sound.nim` |
| 23 | minilibc float math (`floorf`, `isnan`, `round`, `cosf`, …) | `sdk/minilibc/include/math.h` — wrappers **after** each double prototype | n/a (build-time) | `render/native/t_engine.nim` |
| 24 | `float64` silently wrong at wasm32 | guard, not a fix: keep a mechanical ban | n/a | `apps/minipaint/tests/t_app_intact.nim` (source tripwire) |
| 25 | duplicate exported symbols (latent compile hazard) | rename `fx_canvas.toByte`→`cssToByte`, `fx_canvas.composite`→`cssComposite`, `compositor.blendOver`→`blendOverExact` | n/a | `render/native/t_fx.nim` (symbol-set intersection) |

### The workflow rule that makes the table above hold

1. **Do not fake a gap.** For each gap: do NOT fake it; note it in `PORT-NOTES.md`, use the listed
   stand-in if there is one, and move on. Engineers read those notes to decide what to build. `[GAPS]`
2. **A new capability = renderer mapping + a `t_*.nim` test in the same change.** One task = one
   `PLAN.md` item, ≤ ~300 changed lines, one commit. `[AGENTS.md]`
3. **Never trust a prebuilt artifact** — a stale `hello.wasm` once hid an SDK that did not compile,
   and a stale `shot_excal.exe` once hid a working `V` verb. Rebuild from source before claiming
   something works. `[AGENTS.md]` `[EI §5]`
4. **Never claim a number you did not measure**, and when something cannot be checked, say so
   instead of asserting it. `[AGENTS.md]` `[EI "What I could not verify"]`
5. **Wrap, don't rewrite** — use the real Skia / Filament / Yoga behind a small Nim interface. New
   library = ask the Owner first (`DECISION_QUEUE.md`). `[AGENTS.md]`

### Known-unverifiable areas (do not fill these in by guessing)

Per `ENGINE-ISSUES.md`'s closing section, none of these was reproduced from that machine, and no
one should assert a symptom for them: every engine test under `render/native` in full (needs skia
private headers, `libyoga.a`, `wasmtime.dll`, the MSVC `yfilament.dll`, accesskit via cargo); E7's
black hero and E9's near-black metal (mechanism confirmed by reading the shim, symptom not
reproduced); `fx_glfx` on hardware (no GPU path exercised at all); the GIF quantiser divergence
(structurally undetectable by a decoder round trip). `[EI]`
## ⚠ GATE NOT GREEN (2026-10-04) — `t_character.exe` segfaults under the suite

```
host/run_tests.sh
  PASS  sandbox capabilities through the host (14 checks)
  host sweep: 5 passed, 0 failed

render/native/run_tests.sh
  ok  the app starts
  ok  a skinned model is drawn
  ok  its clip plays (a foot moves)
  ok  a new clip crossfades: no jump at the switch
  FAIL characters
  line 97:   973 Segmentation fault   "$HERE/build/t_character.exe"
```

**Any earlier "53 PASS, 0 FAIL" in this lane is superseded — do not repeat it.** AGENTS.md requires
0 failed in every suite.

Run **directly** it initialises (Unreal/OpenGL, feature level 3) and **exits 0** — but segfaults
under the suite. So it is environment- or ordering-dependent, not a deterministic crash in the
test's own logic. **"It passes when I run it by hand" is not a pass** — rule 2 applies to that
convenience exactly as it applies to a stale `.wasm`.

Likely the surface-allocation nil-deref on the open list: an unchecked surface alloc failing as a
bare SIGSEGV with no diagnostic instead of a reported budget. Character atlases/render targets are
allocated at content-driven dimensions — the same shape as the ~2 GB threshold in `2721396`
(1280×816 SCALE 22 = 1.88 GB OK, SCALE 23 = 2.06 GB SIGSEGV, size-independent the way a null-deref
is).

**Next:** ① re-run the suite — one run cannot separate "always crashes" from "crashes under
load", and the fixes differ · ② if deterministic, get a backtrace instead of guessing · ③ make the
engine **check the allocation and report the wanted size**, so every future occurrence is a readable
error rather than a bare SIGSEGV.
#### ✅ Both questions answered: DETERMINISTIC access violation, empty stderr, inside the character check

I suspected last entry that it might *hang* rather than crash. **That was wrong.** Under a 60s cap
it exits on its own in seconds:

    exit code -1073741819  =  0xC0000005  =  ACCESS_VIOLATION (SIGSEGV)

The earlier "~60 min with no output" was **not a hang in the test** - it was the suite being slow,
because run_tests.sh:92-95 **recompiles every test with `nim c`** before running it. Do not read a
quiet suite as a stuck one.

**It crashes inside the character check, after the clip checks pass.** stdout ends:

    ok  the app starts
    ok  a skinned model is drawn
    ok  its clip plays (a foot moves)
    ok  a new clip crossfades: no jump at the switch
    <nothing further>

The character assertions never print, so the four preceding checks are sound and the fault is
confined to what t_character does next. **stderr is completely empty** - no assertion, no
diagnostic. (Partly the harness's doing: line 97 is a bare `2>/dev/null` run.) The process died
before it could report anything, with a plain access violation and no abort message.

**Why this is the surface-alloc defect:** a test allocating a glyph atlas or render target at
content-driven dimensions and dereferencing the result unchecked produces exactly this - the same
shape as the ~2 GB threshold in 2721396.

**The fix, right regardless of what t_character does - do BOTH halves:**
  - the allocator **refuses cleanly** with a diagnostic naming the wanted width/height
  - callers **treat a failed allocation as an error**, not as a valid pointer

**Next, concrete:** read t_character.nim and find the first thing it does after "a new clip
crossfades: no jump at the switch" - that is the call site dereferencing the failed allocation.
#### ✅ The crash is at `step(40)` — and the frame counts make it a PER-FRAME SURFACE LEAK

`t_character.nim:53-57`. Last check that prints is `:53`, so the crash is `:54` or `:56`:

```nim
53:  check("a new clip crossfades: no jump at the switch", smooth <= biggest + 5, ...)
54:  step(40)                       # <-- crash here; nothing prints after :53
55:  last = num("foot")
56:  click("snap"); step()
```

**Count the frames before the crash:**

| | frames |
|---|---|
| `:45` `step(20)` | 20 |
| `:49-50` loop `step()` ×30 | 30 |
| `:51` `click("run"); step()` | 1 |
| | **51 rendered successfully** |
| `:54` `step(40)` | **dies, ~frame 52..91** |

**Nothing about the scene changes between them** — same model, same size, no new content. So this
is **not** a content-driven allocation that is too big (that fails on frame 1) and **not** a
fixed-size surface. **What changes with frame count is cumulative memory.** A per-frame leak: each
rendered frame retains something it should release, and the process crosses the allocation ceiling
in the 52nd–91st frame, then dereferences the failed allocation → `0xC0000005`, empty stderr.

**Same ceiling as `2721396`** (SCALE 22 = 1.88 GB fine, SCALE 23 = 2.06 GB SIGSEGV, size-independent
= raw null-deref). Here it presents as *frame-count*-dependent instead — the same bug along a
different axis: **the request is never too big, the system runs out, and nothing checks.**

**Why nobody noticed:** the other render tests drive a handful of frames each and exit, staying far
below the ceiling. Only `t_character` crosses it.

**Fix — both halves:**
- **find the leak:** render one frame in a loop and watch resident memory; whatever grows per
  frame is the culprit. First suspects: any surface/texture created per frame and not freed, or a
  draw-list/command list retained rather than released.
- **make failure readable:** the allocator refuses cleanly reporting requested width/height, and
  callers treat a failed allocation as an error, not a valid pointer. Without this, the leak can
  regress and the next occurrence is a bare SIGSEGV again.

**Do not "fix" it by lowering the frame count or adding a retry.** The test is correct; the renderer
is leaking.
#### Leak hunt narrowed: the per-frame canvas ops, fillGradient / shadow

`paintSurface` (`engine.nim:1663-1692`) delegates - it reads tree properties and calls exactly
three primitives per node per frame: `c.shadow` (`:1666`, when `P_SHADOW*` is set),
`c.fillGradient` (`:1681`, when `P_GRADANGLE >= 0`), and `c.fillRRect`/`c.strokeRRect`
(`:1686/:1690/:1692`). If memory grows with frame count it grows in one of those, and the two that
plausibly **allocate** are the gradient and the shadow - both need an `SkShader`/`SkImageFilter`
per call.

**Hypothesis, not a conclusion:** if the Nim wrapper returns a raw C++ pointer nobody releases, or
caches shaders in a `Table` that is never pruned, each frame allocates N shader objects for N
gradient/shadow nodes and frees none. Over the ~91 frames `t_character` renders that crosses the
ceiling, while a 20-frame test never gets close - exactly the observed behaviour.

**Where to look, in order:**

1. `libs/nimskia/src/skia_shim.cpp` (NOT `render/native/skia_shim.cpp` - that path does not exist) -
   the `fillGradient` and `shadow` entry points, and what they do with the `SkShader`/
   `SkImageFilter` they create. A `sk_sp<>` releases on scope exit; a raw pointer with no matching
   release does not.
2. Any `Table`/`seq` on `Engine`/`Canvas` storing shaders or filters keyed by node id and never
   pruned. Per-frame growth keyed by id fits too.
3. Whether `c.shadow`/`c.fillGradient` allocate even for a no-op effect, since `paintSurface` calls
   them for every node merely *having* the property set.

**Confirm in one run rather than by reading:** render the same scene in a loop and sample resident
memory per frame; whatever grows is the allocation. If growth stops when gradient/shadow nodes are
absent from the scene, that names the primitive. Faster and more decisive than auditing the wrapper.

#### CORRECTION — t_character PASSES 9/9 standalone. Three rounds of my own conclusions were over-read.

```
t(s)   WS(MB)  PM(MB)
 0.0    24.6    52.8
 0.8   238.6   345.1
 1.5   355.3   550.8
 2.2   381.5   554.9
 -> exited, code 0

ok the app starts / a skinned model is drawn / its clip plays / crossfades /
   blendTime 0 snaps / holds still / turning a bone moves the head /
   twelve placements is a herd / still running
9 passed, 0 failed
```

**Retracted, three rounds of it:**

1. *"The failure is DETERMINISTIC"* (`77a21ee`) — **wrong.** It does not reproduce. One failing run
   is not evidence of determinism and I treated it as such.
2. *"It is a PER-FRAME SURFACE LEAK"* (`2e66211`) — **not supported.** Memory rises 24.6 → 381.5 MB
   in ~2.2 s and the process exits cleanly at 9/9. That is start-up/warm-up allocation, not
   unbounded growth. The frame arithmetic was correct arithmetic on correct line numbers, but it
   described **one run** and I promoted it to a mechanism.
3. *"The leak is `fillGradient`/`shadow`"* (`7b2c978`) — follows from (2), goes with it.
   `paintSurface` remains the right place to look *if* a leak is ever shown; none is.

**What the evidence supports:** the test is green alone and fails inside the suite, which recompiles
and runs many tests before it, so a lot is resident; `t_character` needs ~380 MB. The honest reading
is **resource pressure under the suite producing a failed allocation that is then dereferenced** —
the same empty-stderr nil-deref as `c5a8b44`, but **flaky and environment-dependent**, with no
leak established.

That makes the `c5a8b44` fix the right one and the only one warranted: **a failed allocation must
report the requested size and must not be dereferenced.** Not a bug fix — there is no demonstrated
bug — but **robustness**: a 380 MB test in a long suite will eventually fail to allocate on some
machine, and today that is an unreadable SIGSEGV instead of a message naming the size it wanted.

**METHOD — this is the second time in this lane one sample was over-read.** Round 219 I averaged
across `x` and fused several faults into one number; now I took **one failing run** and built three
rounds of mechanism on it. Same lesson both ways: **one sample is not a mechanism, and a failure
that does not reproduce is a flake until proven otherwise. Run the thing twice before theorising.**

#### ✅ ROOT CAUSE — the `t_character` "flake" was MY OWN leaked processes. `job_kill` does not stop the work.

The suite re-run froze at 31 lines for ~2 h, reaching `PASS native engine` and never reaching
`characters`. Not slow — **hung**. The process list showed why:

```
Id    ProcessName   CPUs     WS_MB  StartTime
14332 bash        7,579.30    7.40  04-10-2026 15:51:11
 9988 bash        7,538.60    7.40  04-10-2026 15:51:11
11416 bash        7,581.90    7.40  04-10-2026 15:51:11
26956 bash        7,545.10    7.40  04-10-2026 15:51:11
27988 bash        7,587.50    7.40  04-10-2026 15:51:11
25376 bash        7,544.00    7.40  04-10-2026 15:51:11
25564 bash        7,578.40    7.40  04-10-2026 15:51:11
17268 bash        7,547.50    7.40  04-10-2026 15:51:11
```

**Eight `bash` processes, all started 15:51:11, ~7,550 CPU-SECONDS each** — ~2.1 h of CPU apiece,
~60,000 CPU-seconds total, all spinning. They are from the suite started in one round and
"cancelled" with `job_kill` in the next. **`job_kill` killed the job record, not the work.**

This explains everything theorised since, far more simply:
- `c5a8b44` saw `t_character` fail under the suite with `0xC0000005` and empty stderr while it
  passed standalone in `92f691c` — under eight runaway processes, exactly the resource-pressure
  failure I guessed at, **with the cause sitting visible in the process list the whole time**.
- The suite being "slow and quiet" (rationalised in `77a21ee` as "it recompiles every test") — it
  also was competing with its own zombie siblings.
- The ~60 min "still running" in that round that made me suspect a hang in `t_character` itself —
  it was not `t_character` at all.

**The lesson — the most expensive in this lane: before blaming a test, a build, or the engine for a
resource failure, LOOK AT THE PROCESS TABLE.** Rounds of a deterministic-crash theory, a per-frame
surface leak, and a gradient/shadow leak were built and retracted while the answer was one
`Get-Process` call away.

**`job_kill` is a request to the supervisor, not a guarantee about descendants.** After cancelling,
**verify with `Get-Process`** that nothing it started is still running, and kill those PIDs
explicitly if it is.

Killed all 8 (`Stop-Process -Force`); remaining `bash` processes are the current run's, <0.2 s CPU.

**The in-flight suite result is untrustworthy** — it competed with the zombies. Re-run on the freed
machine; treat neither its result nor the earlier failure as evidence either way.
#### The suite hangs after `PASS native engine` on a CLEAN machine — zero CPU. One observation only.

Machine verified idle after the 8 zombies were killed (`none - machine is clean`), suite re-run from
scratch. It reached the same point and stopped:

```
lines: 31, unchanged for the whole round
last:  PASS native engine
total bash CPU: 0s
nim alive: 0
t_*.exe alive: (none)
```

**Zero CPU, no compiler, no test binary — that is not slowness, it is blocked.**

**Scope is narrower than the original failure.** In `c5a8b44` the suite got *past* here and reached
`characters`. So `:38` → `characters` is traversable; what follows is the yantra shell build
(`:41-48`), another `nim c`. A build that neither runs nor burns CPU is waiting on a lock, a pipe,
a network fetch, or stdin. Line 15 runs `bash "$WS/libs/nimskia/fetch_private_headers.sh"` — a
network fetch at script top. **A candidate, not a conclusion.**

**Stated as what it is: ONE observation, one clean machine, one run.** Per `92f691c` this is not
promoted to a mechanism and no build is "fixed". Cheap falsifier: run the suite again — a hang at
the *same line* reproduces, a hang that moves is something else.

**Solid from this round regardless:**
- the 8 zombies are gone and the machine is idle
- the suite does not pass 31 lines without work happening. **"Quiet" and "stuck" are distinguished
  by CPU, and I should have used that from the start** — one `Get-Process` away, and it would have
  saved the entire retracting detour of `92f691c`.
- `t_character`'s `c5a8b44` result stays unexplained — measured under the zombies, untrustworthy as
  evidence of an engine defect either way.

**Gate: NOT green and NOT claimable.** `host` 5 passed / 0 failed at `c5a8b44`; `render/native` has
produced no trustworthy result since.#### Next check on the `PASS native engine` hang: `fresh()` is `rm -rf`, and `rm -rf` blocks on a locked handle

**A candidate to verify, explicitly NOT a conclusion** (per `92f691c`, one observation is not a
mechanism). Reading `run_tests.sh:1-22` for what could block with zero CPU:

```bash
14: fresh() { rm -rf "$YANTRA_DATA"; mkdir -p "$YANTRA_DATA"; }
15: bash "$WS/libs/nimskia/fetch_private_headers.sh"
```

`fresh()` is called before **every** test program in the script (`fresh; if "$HERE/build/t_engine.exe"...`
at `:38`, and again at `:95` for `t_character`). It does `rm -rf` on `$YANTRA_DATA`. **On Windows a
`rm -rf` against a file whose handle is still open does not fail fast — it blocks.** That is exactly
the observed signature: no CPU, no child process, script parked.

Why this is worth checking first: in the clean run the eight zombies were killed **while they may
have held handles inside `render/native/build/data`**, and the suite then reached `PASS native
engine` — meaning several `fresh` calls had already succeeded — and hung on a later one. A stale
handle would explain "works at first, blocks later" better than a network fetch at `:15`, which is
only reached once and had already run.

**Cheap falsifier:** `rm -rf render/native/build/data` by hand. If it blocks, that is the bug and
it is reproducible without the suite at all. If it returns instantly, this candidate is dead and the
next place to look is whatever `:41-48` (the yantra shell build) waits on.

Also worth doing regardless of which it turns out to be: **`job_kill` did clean up this time**
(0 leftover `bash`/`nim` immediately after, verified clean) — the leak in `2c971e0` came from the
first multi-process suite run, not from every cancellation. Still verify every time; do not assume.#### The `PASS native engine` hang: what is RULED OUT, and the measurement that was missing

Three candidates eliminated this round, each by a cheap test rather than by argument.

**1. `fresh()` / `rm -rf` on a locked handle — REFUTED.** Predicted a block on
`render/native/build/data`:

```
Remove-Item -Recurse -Force  -> returned in 0.01s
msys rm -rf                 -> exited 0.04s, code 0
```

Both instant. No lock, no block. **Candidate dead.**

**2. The PowerShell pipeline (`Tee-Object`) blocking the writer — REFUTED.** Re-ran with no pipeline
whatsoever; bash redirected its own output to a file (`bash -c "... > suite3.log 2>&1"`), so there is
no pipe for a writer to block on. **It hung at the same place, same line count.** So the earlier
`Tee-Object` runs were never the problem. (Worth recording that the two symptoms being similar was
what made this a reasonable first guess.)

**3. A test binary left running after printing its summary — REFUTED.** The log ends at
`native engine: 29 passed, 0 failed` and never reaches the `PASS native engine` echo, which does
suggest `t_engine.exe` printed its summary and did not return control. But enumerating
`t_*`/`drive*` processes finds **none** — no test binary is alive. So it did exit.

**THE MEASUREMENT I HAD BEEN SKIPPING, which explains why three checks all came back negative:**
every check in this investigation filtered `Get-Process` for `bash` and `nim`. The processes that
actually matter — the test binaries, the runner, the app under test — were never in the filter. The
"nothing is running" conclusion was an artefact of what I chose to look for. **Enumerate every
process, or none of this is evidence.**

**REMAINING, STATED AS UNKNOWN.** bash is alive (~0.1 s CPU), no `nim`, no test binary, no output
progress, indefinitely. No candidate left that I can currently distinguish. Per `92f691c` I am not
inventing a fourth theory from the same single observation. The next useful step is a real
backtrace or a blocked-state dump of the parked bash — what it is waiting on — rather than another
guess about which line. On Windows/MSYS that means checking its wait state, not reading more
source.#### ✅ RESOLVED — `t_character` PASSES. The whole failure was my own leaked processes.

Clean-machine run (machine verified idle first, and enumerating **every** process rather than
filtering for `bash`/`nim`):

```
native engine: 29 passed, 0 failed
shell: 20 / motion: 29 / motion (maths): 34 / motion (springs): 42
text: 44 / reload: 31 / net: 27 / particles: 12
PASS characters          <-- 9 passed, 0 failed
...  PASS: 19   FAIL: 0    (still running at time of writing)
```

**Both "mysteries" had one cause: the eight runaway `bash` processes from `2c971e0`.**
`t_character` did not have a deterministic crash, a per-frame surface leak, or a gradient/shadow
leak. It was resource exhaustion from processes I leaked and killed the wrong way. The suite's
"hang after `PASS native engine`" was the same saturated machine, not a lock, a pipe, or a test
binary that would not exit.

**The fix that was needed was `Get-Process`, not allocator checks.** In `92f691c` I retracted the
leak theories *correctly* — but then reached for a robustness patch to the allocator when the
defect was in my own process hygiene. **A correct retraction still does not imply the next theory
is right.**

**What actually prevented this from costing days:** every theory was killed by a cheap falsifier
run before building on it. `rm -rf` timing (0.01 s), a pipeline-free re-run, and a full
unfiltered process enumeration each cost one command. That discipline — *falsify before
elaborating* — is the part worth keeping from this entire stretch.

**General point that survives, now marked as NOT the cause:** a failed allocation should report its
requested size and must not be dereferenced. That is still correct engineering and still worth
doing, but it did **not** explain `c5a8b44`, and any future reader must not take that entry as a
diagnosis of it.

**Two standing traps from this arc, both about what I looked at rather than what happened:**
1. **Filtering the process table for what you expect to find will confirm it.** Filter `bash`+`nim`
   when the test binary is what hung, and you get "nothing is running" — an artefact of the filter,
   not a fact about the machine. **Enumerate everything, or the negative result is worthless.**
2. **`job_kill` cancels the job record, not the descendants.** Verify with `Get-Process` after
   every cancellation, and kill leftover PIDs explicitly.#### ✅ GATE IS GREEN — measured, on a clean machine. Supersedes every earlier claim in this lane.

Both suites run after verifying the machine idle (the 8 zombies of `2c971e0` killed and re-checked),
output redirected by bash itself rather than through a PowerShell pipeline.

**Verified:**

```
render/native/run_tests.sh
  PASS native engine / characters / 3D scenes / overlays / state machines /
       chat over websockets / navigation / rich text / desktop notifications / ...
  52 summary lines, every one "N passed, 0 failed"
  53 ^PASS, 0 ^FAIL, no non-zero "failed" anywhere
  EXIT=True

host/run_tests.sh
  === 35/35 host checks passed ===
  PASS  engine assertions (35/35)
  PASS  sandbox capabilities through the host (14 checks)
  host sweep: 5 passed, 0 failed
```

**Supersedes every earlier gate claim here, in both directions:**
- `c5a8b44`'s "FAIL characters" was real but caused by my leaked processes — it says nothing about
  the engine.
- The "53 PASS, 0 FAIL" I asserted early in the lane, before any of this, **is now measured and
  holds**. It was unverified when I first said it and should not have been said; it is verified now.
- `f1c9d33`'s "hangs after `PASS native engine`" was a saturated machine. It does not hang.

**The engine was never defective in any way these rounds claimed. No engine code changed at any
point in this investigation — nothing needed to change.** The only thing ever wrong was my process
hygiene. The one real app fix from this lane is `bd3ae69` (edge-darkening over-compound; typewriter
31.78% -> 31.51%, verified by build -> render -> re-score).#### The grain pass: measured contrast says the frame draws grain the reference does not have AT ALL

The measurement `7b2c978` asked for. Ref vs frame at x=1180, 40px wide, near the y=203 dip:

```
BASELINE WOOD (correct)
  y=194  40x4   ref (82,45,21)  frame (83,46,22)   delta (+1,+1,+1)
  y=198  40x4   ref (83,46,22)  frame (81,44,22)   delta (-2,-2, 0)

THE "DIP"
  y=202  40x2   ref (83,46,22)  frame (58,31,14)   delta (-25,-15,-8)
  y=203  40x2   ref (82,46,22)  frame (65,36,17)   delta (-17,-10,-5)
  y=204  40x2   ref (81,45,21)  frame (89,50,25)   delta (+8,+5,+4)
```

**The reference has no dip there at all** — 83, 82, 81 across the three rows is smooth wood. The
frame puts a hard 2px dark band at 58/65 and then overshoots bright to 89 on the row after.

So the earlier framing in `f20d407` ("the grain is drawn too dark") is INCOMPLETE and was reading a
`colprof` local-luma figure rather than the box mean. The truth is sharper:

  - the surrounding wood is correct to within 1-2 luma, so `bdPlankBase`, the tone table and the
    lamp are all right - already established, now reconfirmed at 1px resolution
  - the grain STROKE ITSELF is the whole error, and it is not a subtle alpha difference. The
    reference's grain is essentially invisible in this region while the frame's is a hard 25-luma
    black band.

Arithmetic worth checking against the code. `bdPlankBody` draws grain at
`n = bdRound(ph / 2.4)` px intervals (`:317`) - about one every 2.4px. A 2px-tall box therefore
catches one or two strokes, and each dark stroke is `(38,18,6)` at
`a = (0.08 + rand*0.2) * 0.75` over wood near (83,46,22). One such stroke algebraically gives
roughly 83*(1-0.21) + 38*0.21 = 74, i.e. about **-9 luma, not -25**. **Two overlapping strokes get
there.** So the observed -25 implies the strokes are compounding - the same class of bug as
`bd3ae69` (bands overlapping so pixels get `1 - prod(1-a_i)` instead of the intended ramp).

THAT IS THE SHARPEST LEAD IN THE LANE and it is testable: **give each grain stroke its own row and
verify it does not overlap its neighbour.** If `ph / 2.4` rounds to an interval smaller than the
stroke's height, consecutive strokes stack. Note the reference shows the grain as nearly flat, so
either the density or the alpha must ALSO come down - fixing overlap alone should roughly halve the
error, from -25 to about -12, not close it.

No code changed. Tracked tree clean.#### Reading `bdPlankBody`'s grain loop (app.nim:316-343) - density is the dominant error, and the comment lies about the method

```nim
316  # grain lines: sine-warped, ~1 every 2.4px of plank height
317  let n = bdRound(ph / 2.4'f32)
319  while k < n:
320    let gy = y + bdNext(r) * ph          # RANDOM position, not evenly spaced
324    let dark = bdNext(r) < 0.62'f32
325    var a = (if dark: 0.08 + rand*0.2 else: 0.05 + rand*0.12)
329    let lw = 0.5'f32 + bdNext(r) * 1.7'f32
330    # A grain line fades out at the plank edges the way real grain does, so the
331    # stroke is split into two passes at half alpha instead of one hard line.
332    a = a * 0.75'f32
341    d = d.stroke(bdRgba(base, g, bch, a), lw)
```

FOUR THINGS, in descending confidence.

**1. THE COMMENT DESCRIBES A METHOD THE CODE DOES NOT USE.** `:330-331` says the stroke "is split
into two passes at half alpha instead of one hard line". There is no second pass - `:332` is a
single `a = a * 0.75` and `:341` draws exactly one `stroke()`. Same failure shape as `bd3ae69`,
where the comment and the code had already diverged. **When a comment describes a technique, verify
the technique is present before reasoning about output.**

**2. THE DENSITY IS THE DOMINANT ERROR, not the overlap.** `n = bdRound(ph / 2.4)` is ~80-110 strokes
per plank, each `lw` up to 2.2px, over a plank `ph` of 190-270px. Expected coverage is roughly
`90 * 1.35 / 230` = **~53% of the plank area carries grain**. The reference measured in the last
round is essentially FLAT wood there (83, 82, 81 across three consecutive rows). A reference with no
visible dip cannot be reproduced by halving alpha alone.

**3. THE LINES ARE RANDOMLY PLACED.** `gy = y + bdNext(r) * ph` is uniform-random per line, so
grain has no consistent direction or spacing down the plank - only the sine warp within one line
gives it shape. If the reference shows directional grain (parallel, following the plank), this
cannot match at any density. **Worth one measurement of the reference's actual grain structure
before tuning any number.**

**4. THE ALPHA ARITHMETIC ALONE DOES NOT REACH -25.** Dark stroke `(38,18,6)` at `a <= 0.21` over
wood `(83,46,22)`: one stroke -> `83*0.79 + 38*0.21` = 73.5, i.e. **-9.5**. Two strokes -> -17. Three
-> -23. So -25 needs ~3 concurrent strokes, which is consistent with the density in (2) rather than
with a single mis-set constant. **Fixing alpha alone caps out around -12; density is the lever.**

CONTRADICTION TO RESOLVE BEFORE FIXING ANYTHING. `colprof` reported "y=203 ref 54.6 frame 31.5",
but direct box measurement with `tone.mjs` gives ref 82-83 at those same rows. The two cannot both
be right about the reference. `tone.mjs` has been verified repeatedly and is the trustworthy one;
`colprof` already produced a `NaN` column on its first ever run (`5db42b2`). **Do not tune the grain
against `colprof` numbers.**

No code changed - the density, the placement model, and the reference's actual grain structure all
need measuring before any constant is touched, and one of my two measuring tools is now in doubt.
Tracked tree clean.#### RESOLVED - it is not grain. It is the PLANK SEAM at y=202-203, uniformly -14 red across the whole desk.

Row y=202, 1px tall, 20px wide, sampled across the desk (x=600 is the paper, off-desk):

```
y=202
  x=  60   ref (136, 93, 55)  frame (122, 84, 49)   delta (-14, -9, -6)
  x= 300   ref (144,101, 61)  frame (130, 93, 55)   delta (-14, -8, -6)
  x= 600   ref (235,227, 209)  frame (235,228, 209)  delta (  0,  1,  0)   <- paper
  x= 900   ref (108, 67, 36)  frame ( 94, 58, 31)   delta (-14, -9, -5)
  x=1180   ref ( 83, 46, 22)  frame ( 69, 38, 17)   delta (-14, -8, -5)

y=190 (plain wood, same xs)
  delta (+5,-4,+1,+1,+4)   -- essentially correct
```

**The delta is EXACTLY -14 red at every x across the desk, and 0 off-desk on the paper. The row
above it is correct.** That is not grain - grain is local, sparse and varies along its length. This
is a single **full-width horizontal dark line**, and it is the plank seam: y=203 was already
identified as a seam in `5db42b2` (and y=276 the next one).

SO THE GRAIN PASS IS EXONERATED. `f20d407` ("the grain is drawn too dark"), `d64e3ca` and the
density analysis in `2b31975` were all chasing this line by proximity - the seam sits among the grain
and any x-averaged probe near a plank boundary attributes the seam's darkness to whatever else is
nearby. **A 1px-tall probe taken across several x, at one row, separates a full-width defect from a
localised one; averaging over y is what hid this for ten rounds.**

Note also that the earlier 40x2 box at y=202 read -25 while this 20x1 box reads -14. The wider box
was averaging in y=203 (-17) and neighbouring rows. **The single-row number is the real one, and
every multi-row figure quoted for this strip -16, -18, -22 - has been inflated the same way.**

THE CULPRIT IS `bdPlankBase`'s seam, with the band overlap compounding it:

```nim
240  let hi = t + 6
241  let lo = t - 8
313  d.rect(0, y + ph * f0, w, ph * (f1 - f0) + 1.0'f32, bdPlankBase(t, fm))
```

The `+ 1.0'f32` on `:313` makes each of the 24 bands overlap its neighbour by a pixel, exactly as
`bd3ae69` found on the edge-darkening strips - pixels in an overlap receive
`1 - prod(1 - a_i)` instead of the intended ramp. At a seam two bands and the seam line itself
land on the same row, so the defect concentrates there instead of spreading.

WHAT TO DO NEXT, in order, none of it speculative:
  1. Confirm the seam rows: probe y=201..205 at 1px across two x values. If the darkness is
     confined to y=202-203 and identical at both x, it is the seam.
  2. Then look at how `bdPlankBase` renders the seam line and whether `:313`'s `+1.0` overlaps it.
  3. Only then consider the `+ 1.0` itself - which would ALSO be a candidate fix for the band
     gradient everywhere else, not just at seams.

No code changed. Tracked tree clean.#### BREAKTHROUGH - the plank SEAMS ARE MISPLACED. Reference and frame put the plank boundary at different y.

Reference vs frame, red channel, x=900, 1px rows, y=185..230:

```
y=185..193   ref 109 116 116 109 108 105 100 100 102   frame 101 105 106 106 106 106 106 106 106
y=194..201   ref ~107 (FLAT)                            frame 106..110
y=202   ref 108   frame  94   diff -14
y=203   ref 108   frame  80   diff -28     <-- frame's dark seam
y=204   ref 108   frame 105   diff  -3
y=205..225   ref ~107 (FLAT)                            frame 117..129   diff +7..+22
y=226   ref  91   frame 125   diff +34
y=227   ref  89   frame 125   diff +36     <-- REFERENCE's dark seam
y=228   ref 106   frame 125   diff +19
y=229   ref 127   frame 127   diff   0
y=230   ref 127   frame 128   diff  +1
```

THREE SEPARATE FACTS, and together they overturn a refutation I made earlier.

**1. THE REFERENCE'S PLANK IS FLAT.** From y=194 to y=225 the reference is a constant ~107 - **no
24-band gradient and no seams at all**. The port's plank oscillates 117-129. So the `bdPlankBase`
band gradient (`:240-245`, `:313`) is drawing structure the reference does not have, AND sitting
~15-20 luma too bright.

**2. THE PLANK BOUNDARY IS AT A DIFFERENT y IN EACH.** The reference's dark seam is **y=226-228**
(91, 89); the frame's dark seam is **y=202-204** (94, 80). They do not coincide. The reference is
uniform 108 at y=202-203 where the frame is 94/80, and the reference is 91/89 at y=226-227 where
the frame is 125/125. **The port's planks are laid out at the wrong vertical positions.**

**3. `5db42b2` IS WRONG AND MUST BE UNDONE.** That commit "refuted PRNG drift" on the grounds that
"plank seams at y=203 and y=276 land at the same rows in ref and frame". This measurement says the
reference has NO feature at y=203 at all (flat 108), and its seam is at y=226. **Whatever `5db42b2`
measured, it was not the reference's seam positions** - most likely it read the frame's own seam
rows and confirmed the frame against itself. That is the classic confirmation trap, and it is the
same shape as round 231's filtered process list: a method biased toward the answer cannot return a
disconfirming one.

I am NOT re-opening this as "PRNG drift" on this evidence. What is established is the observable:
the two images put the plank boundary at different y, ~24 rows apart. **The cause is not yet
established** - it could be plank heights, plank start offsets, or a differing `ph` distribution.
The next step is to locate EVERY boundary in both images and compare the whole sequence, not two
rows of one. If the whole sequence is offset consistently, it is an offset; if the spacings differ,
it is `bdNext` drift in `ph`.

Tracked tree clean. No code changed.#### ROOT CAUSE FOUND - `app.nim:313`'s `+ 1.0'f32` makes each of the 24 plank bands 1px too tall, so the band stack drifts down one pixel per band.

New probe `.board/probe/seams.mjs` finds every plank boundary in a column band separately for ref
and frame, then reports the offset from each ref boundary to the nearest frame boundary. Whole-
sequence comparison instead of two rows. At x=900 (desk above the machine, y<437), the offsets are:

```
y=199  ->   0
y=202  ->  -1
y=204  ->  +1
y=207  ->  +4
y=210  ->  +7
y=212  ->  +9
y=215  -> +12
y=219  -> +16
y=227  -> +24     <-- ref's strongest dip (-30); frame's strongest is at y=203 (-37)
y=276  ->  -1      <-- RESET
y=304  -> +27
y=309  -> +32
y=317  -> +40
```

**THE OFFSET GROWS STEADILY WITHIN A PLANK AND RESETS AT EACH PLANK BOUNDARY. A sawtooth.** The
growth is +4, +7, +9, +12, +16, +24 across bands - and `bdPlankBody` draws exactly **24 bands per
plank** (`:310-314`). One pixel of accumulated error per band, reaching ~24 px at band 24, then
reset when the plank loop restarts. **The prediction and the measurement agree numerically, not
just qualitatively.**

THE LINE THAT DOES IT:

```nim
313  d.rect(0, y + ph * f0, w, ph * (f1 - f0) + 1.0'f32, bdPlankBase(t, fm))
```

Each band is drawn `ph * (f1 - f0) + 1.0` tall while its slice of the plank is only
`ph * (f1 - f0)`. Band *k* therefore ends up **k pixels lower than it should**, and band 24 ends 24
px low. Two things follow, and both are observed:
  - **the geometry drifts**, which is why the reference's plank boundary at y=227 appears at y=203
    in the frame (the frame is ~24 px "ahead" in band terms);
  - **adjacent bands overlap by 1 px**, so those pixels receive `1 - prod(1 - a_i)` instead of the
    intended ramp - which is exactly the double-darkened seam measuring -28 red at y=203.

**THIS IS THE SAME CLASS AS `bd3ae69`** (the edge-darkening strips overlapping by 0.5 px), and the
same fix applies: give each band its own slice, with no overlap, and put any anti-aliasing need on
the colour rather than on geometry. Removing the `+ 1.0'f32` should move the boundary and halve the
seam darkness together - and, critically, it is a **one-token change with an exact predicted
magnitude**, which is the kind of fix that is worth applying and re-scoring immediately.

Also settled by this probe: **the reference's plank is NOT flat.** At x=900 it has boundaries at
191, 194, 199, 202, 204, 207, 210, 212, 215, 219, 227 - dense real structure. The "flat 107" reading
in the previous entry came from a 20px-wide box mean that averaged structure out; the dip detector
over the same 20px finds it. **A box mean can hide structure that a within-box scan reveals** - the
mirror image of the averaging error that hid this for ten rounds.

Matching overall: 30/54 ref boundaries matched within 2px at x=900, 31/42 at x=1180. So the PRNG is
broadly right and only the per-band drift is wrong - **this is NOT PRNG drift**, and `5db42b2`'s
refutation survives in substance even though its evidence was wrong.

NEXT, concrete: remove the `+ 1.0'f32` at `:313`, rebuild, re-render, re-score, and check whether
the boundary moves to y=227 and the y=203 seam lightens. No code changed yet.
#### REFUTED BY DIRECT TEST — the band-drift theory. Reverted. 31.51% -> 32.56%.

Removed `+ 1.0'f32` from `app.nim:313` (one token, clean build). Predicted: the plank boundary would
move y=203 -> y=227 and the seam would lighten.

**Measured:**

| | before | after |
|---|---|---|
| score | **31.51%** (329,113) | **32.56%** (340,087) |
| mean abs delta | 12.52 | 12.67 |
| frame seam | y=203 (**-34**) | y=203 (**-33**) — **did not move** |

**The prediction failed and the score got worse.** The overlap is not what displaces the boundary.
The apparent agreement between "24 bands" and the "+24" offset in the previous entry was
coincidence dressed up as corroboration — **I had two numbers that looked like they matched and
treated the match as confirmation, without ever testing whether removing the cause moved the
effect.** Reverted; tree clean.

**This is the correct way to lose an hour instead of a day:** a one-token fix, a specific numeric
prediction, one render. The previous entry's confidence was not warranted by its evidence and must
not be read as a root cause.

**Two process errors of my own, both nearly producing false conclusions:**

1. I reported *"98.30% — the fix is catastrophic"* for one tool call before checking whether the
   **render** was valid. It wasn't: red and blue came back swapped ((100,60): frame `165,179,185`
   vs baseline `185,179,165`). My retry had dropped `node tools/rawswap.mjs` from the pipeline the
   first attempt had. **A catastrophic score is exactly when to suspect the harness first** — a 98%
   regression from a one-token plank-band edit is not physically plausible, and an implausible
   result is itself strong evidence that the comparison is wrong.
2. Rendering took >135 s CPU and I polled `Get-Process` repeatedly instead of one long wait.
   Repeated polling mid-render yields nothing the previous poll didn't already say.

**Net: no change to the app, baseline still 31.51%.** The desk seam displacement (ref y=227, frame
y=203) is **real** — measured twice, at two column positions, and it survives this refutation.
**Only my explanation for it is dead.**
#### The seam displacement is a PLANK HEIGHT error — and `bdNext` diverges on the FIRST call

Band overlap is dead (`f36cb68`). The cause is in the plank loop (`app.nim:486-492`):

```nim
486  var y = -20.0'f32
488  while y < h:
489    let ph = 190.0'f32 + bdNext(r) * 80.0'f32
491    y = y + ph
```

Boundary at end of plank 0 is `y0 + ph0 = -20 + ph0`. Measured at x=900:

| | strongest desk dip | implied `ph0` | implied first `bdNext` |
|---|---|---|---|
| reference | **y=227** | 247 | **(247-190)/80 = 0.7125** |
| frame | **y=203** | 223 | **0.4125** |

**The very first `bdNext` call already differs.** Nothing accumulates — `ph0` comes from the first
value the generator ever emits and it is wrong immediately. Every later boundary inherits it, and
`seams.mjs` shows boundaries agreeing early then diverging, because `bdPlankBody` also consumes
many `bdNext` values for grain and that count differs too.

**This revives PRNG drift, which `5db42b2` refuted** on the grounds that "seams at y=203 and y=276
land at the same rows in ref and frame". That evidence cannot be right: the reference has **no**
boundary at y=203 (flat 108) and its first boundary is y=227. `5db42b2` almost certainly compared
the frame's own boundary list against itself. **A refutation that reads the suspect back out of the
thing being tested is not a refutation** — the same confirmation trap as the filtered process list
in `92f691c` and as reporting 98.30% before checking the render in `f36cb68`.

**Next, in order — do NOT start by tuning constants:**
1. Recover the reference's plank heights from the image: every strong boundary in a clear desk
   column, converted to `ph`. A target to fit, not a guess.
2. Read `bdNext`/`BdRng` and identify the algorithm. The reference is a browser page, so it is
   likely `Math.random()` — **which a port cannot reproduce**; the fixture must have used a
   seedable generator, and the seed + algorithm are the things to find.
3. If no seed reproduces 0.7125, the reference's plank layout is **not random** and
   `190 + rand*80` is simply the wrong model — then derive plank heights from the image instead.

Steps 1–3 decide *seeding problem vs modelling problem*, which need different fixes.

#### ROOT CAUSE — the plank height MODEL is wrong (190–270 vs ~161). Not the seed.

`bdNext` (`app.nim:194-199`) is a **correct mulberry32**, verified by hand. The precedence worry
does not bite:

```nim
t = t + ((t xor (t shr 7)) * (61'u32 or t)) xor t
```

In Nim `xor` binds looser than `+`, so this is `t xor (t + imul(...))` — matching JS `t ^=` — not
`+ ... xor t`. uint32 multiply wraps like `Math.imul`. Seed is `bdRngInit(21)` (`:481`).

**The deciding evidence is spacing, not the seed.** `seams.mjs` strong dips (drop > 20), ref only,
clear desk columns:

```
x=900 : y66 (-28),  y227 (-26)
x=1180: y67 (-15),  y227 (-31)
```

**Reference plank boundaries sit at y≈66 and y≈227 in BOTH columns — spacing 160–161.** The frame's
own strong boundaries are y=203 and y=428 — spacing **225**, inside the port's `190 + rand*80` band.

**No seed for mulberry32 can produce 161 where `190 + rand*80` cannot go below 190.** The interval
itself is wrong, so the whole `ph` distribution must be replaced. This is a **model** error, not a
seeding error — which also explains why the `+1.0'f32` band fix could not move the seam
(`f36cb68`): band height is a within-plank detail, boundaries are set entirely by `ph` at `:489`.
Two independent mistakes; I attacked the wrong one first.

The reference's first boundary at y≈66 with the port starting at y=−20 implies plank 0 is only ~86
tall — further evidence the model needs replacing, not rescaling.

**The seed question is open but demoted:** fitting plank 0 would need first-value 0.7125, but if the
model is wrong then 247 is the wrong target. `.board/probe/seed.mjs` is written and working but is
the **wrong question until the model is right**; its exhaustive hit at 326835 is a chance
coincidence of a 1e-7 tolerance over 5M candidates, not evidence.

**Next, in order:** ① establish the reference's true seam positions in a clear desk column, **and
require two independent columns to agree before believing any of it** — that agreement is exactly
what `5db42b2` assumed and never checked · ② fit the height distribution (expect nothing like
`190+rand*80`) · ③ only then revisit the generator.

#### CORRECTION to the plank-model conclusion: it IS a seed problem. The model range is fine.

Round 243 said "the model is wrong, reference planks are ~161px". **That was a grain line read as a
seam.** At thr=18 across five independent clear-desk columns:

```
x=  60  REF y48(-24) y61(-19) y102(-44) y109(-28) y227(-28)   FRAME y63(-31) y203(-36)
x= 150  REF y55(-26) y59(-54) y100(-53) y109(-29) y227(-33)   FRAME y203(-39)
x=1100  REF y165(-20) y192(-20) y227(-31)                     FRAME y148(-18) y203(-41)
x=1200  REF y67(-20) y192(-19) y227(-33) y303(-19)            FRAME y203(-41)
x=1250  REF y192(-19) y227(-35)                               FRAME y203(-40)
```

`y48/55/59/61/67/102/109/165/192` are grain — strong in one column, absent in the next.
**`y=227` is strong in all five** (-28,-33,-31,-33,-35); the frame's `y=203` likewise
(-36,-39,-41,-41,-40). **Offset +24 in every column, no exception.** The `y=66` feature behind
round 243 moves with x (y=59 at x=150, y=67 at x=1200) — a **diagonal grain stroke**, not a seam.

**Corrected arithmetic** (`y0 = -20`, seam at `y0 + ph0`):

| | seam | `ph0` | first `bdNext` |
|---|---|---|---|
| reference | y=227 | 247 | **0.7125** |
| frame | y=203 | 223 | **0.4125** |

**Both `ph0` lie inside the port's `190 + rand*80`.** The model range accommodates both images —
only the first emitted value differs. **Seed problem, not model problem.** This is the same shape as
the other three times this lane: a measurement error promoted straight to a root cause.

**Constraint on any finer analysis:** below y≈690 both images show a dense -20..-50 cluster
(ref 698-763, frame 675-810) that is props/shadow, not seams. Measured "spacings" of 18–52px there
are grain — **the frame cannot have 18px planks either, its model also says ≥190.** Only
five-column-unanimous features are seams.

**Next:** the target is solid (0.7125 / `ph0`=247, five columns), so `seed.mjs` is finally the right
tool — but a seed must match the **first value AND subsequent plank heights**, not a first value in
isolation. The previous exhaustive hit at 326835 was a 1e-7 coincidence over 5M candidates and
proves nothing.
#### A validated plank simulator narrows the seed to 3 candidates

`.board/probe/planksim.mjs` reproduces the plank loop (`app.nim:486-492`) exactly, **without
rendering**. `bdNext` consumption per iteration, now known exactly:

| part | calls | where |
|---|---|---|
| `ph` | 1 | `:489` |
| `grain` | `round(ph/2.4)` × 7 | `:316-343` |
| `knot` | 1, +2 if taken | `:346-348` |
| seam | **0** | `:357-358` |

**`bdKnotRing` consumes no `bdNext`** — it is fully determined by `q` (`:247-272`). That was the one
unknown, and reading it is what made the simulator possible.

**Validated against the port's own render:** seed 21 → boundaries `204.6, 429.5, 685.3`; frame's
measured seams at x=1200 are `203, 428` — same ~1.6px simulator bias. The simulation is faithful,
and the frame's other dips (480, 498, 528, 557) are now **confirmed grain/props, not seams**.

Also validated: `bdRngInit(21)` → first value 0.432291 → `ph0`=224.58 → boundary 204.6. **`mulberry32`
at `:194-199` is correct** and the loop reading is correct. The seed is the only free parameter.

**Search** on reference boundaries **227** (unanimous, 5 cols), **478** (2 cols), **699** (2 cols),
all within ±3px:

```
seeds 0..5000       ->  3 candidates
seeds 0..100,000    -> 40
seeds 0..1,000,000  -> 433
seed   897 -> 229.9  478.4  697.4  922.1
seed  2089 -> 228.5  480.8  700.7  897.4
seed  4012 -> 227.3  478.7  697.9  927.4
```

**Not yet decided.** 4012 is closest raw, but correcting the known 1.6px simulator bias puts 2089
closest — and *that correction is a hand-wave*. **Picking a winner on it would be the same
over-fitting this lane keeps falling into.** There is no fourth boundary inside `h=816` to break
the tie; the next lands near y=900.

**Next:** render all three (~135s each) and measure where the seam lands — the first test that can
*settle* this rather than narrow it. **Do not pick a seed on arithmetic alone**; the arithmetic
already produced one wrong root cause (`903a516`) and one wrong refutation (`5db42b2`). If none
lands at 227, the reference did not use a seeded mulberry32 in this range, and the move is to stop
fitting a generator and derive boundaries from the reference image as data.#### ✅ FIXED — seed 897, not 21. Desk seams land on the reference's. 31.51% → 29.23%.

`app.nim:481`. The plank loop (`:486-492`) makes `ph = 190 + bdNext*80` per plank, and grain
(`round(ph/2.4)`×7), knots (1 or 3) and plank tone all draw from the **same mulberry32 stream**, so
**the seed alone decides where every seam and grain stroke lands.** Seed 21 → first seam y=203;
reference has 227.

**How 897 was found — measured, not guessed:**

1. `seams.mjs` located reference seams: **y=227 unanimous across 5 desk columns**, then 478 and 699
   across 2 each. *Only multi-column agreement counts* — a single column's dips are mostly grain,
   which is exactly what made `903a516` wrong.
2. `.board/probe/planksim.mjs` replays the loop with **no rendering**, so seeds are testable in ms.
   Getting it right required reading `bdKnotRing` (`:247-272`) and finding it consumes **no** draws.
3. Seeds 0..5000 → **only 897, 2089, 4012** put seams near all three boundaries (0..100k → 40,
   0..1M → 433).
4. 897 predicted **229.9** and **rendered at 228** against the reference's 227. Since the simulator
   runs ~1.6px high, 2089 (~226.6) and 4012 (~225.4) would land *further* away — **the other two
   were dropped on prediction rather than wasting two more renders.**

```
ref seam  y=227 (-33)        frame seam y=228 (-43)   <- was y=203
differing pixels : 305345 / 1044480 (29.23%)   was 329113 (31.51%)
mean |delta|     : 12.21                      was 12.52
```

Verified: `host/run_tests.sh` — 35/35 engine, 14/14 sandbox, 13/13 todo, **sweep 5 passed 0 failed**,
exit 0.

**THE LESSON, which cost more than the fix:** the entire bug was a seed nobody had justified.
`5db42b2` "refuted" PRNG drift by comparing the frame's own seams against **itself**; `903a516`
declared the model wrong off **one column's grain line**. Two plausible-sounding conclusions,
both wrong, both overturned by requiring agreement across independent columns. **A single column's
dip is grain until several columns agree it is a seam.**#### Bottom strip y≥791: measured onset, and it is NOT the machine's cast shadow

With seed 897 the bottom rows y=802..813 are 7 of the top 10 worst rows, all near-full-width.
Measured at x=600, 1px, ref vs frame:

```
y=786..790   ref (120,167,146)   frame (120,167,146)   <- exact match, machine body
y=791        ref (58,35,17)      frame (82,94,79)       <- frame's body is 1 row lower
y=792        ref (55,34,16)      frame (48,25,13)
...
y=810        ref (74,46,24)      frame (58,32,17)   d=(-16,-14,-7)
y=815        ref (78,48,25)      frame (57,31,16)   d=(-21,-17,-9)
```

**THREE ESTABLISHED FACTS.**

1. **The onset is exactly y=791**, which is the machine's documented bottom edge
   `MY+332U = 790.8` (`:1928`). Above it the two images match to the byte.

2. **Below it the reference BRIGHTENS downward** (54 at y=793 → 78 at y=815) while **the port
   stays flat** (~50-58). The error is therefore not a constant offset; it *grows with distance
   below the machine*, reaching −21 by y=815.

3. **It is NOT the machine's cast shadow.** A cast shadow would peak under the machine (x≈640)
   and fall off at the edges. Measured at y=805:

   | x | 60 | 150 | 600 | 1200 | 1250 |
   |---|---|---|---|---|---|
   | ref | 104 | 108 | 70 | 71 | 75 |
   | frame | **102** | 96 | 55 | 56 | 64 |
   | error | **-2** | -12 | -15 | -15 | -11 |

   **At x=60 the port matches the reference almost exactly.** The error is near zero at the left
   edge and ~15 from x=150 rightward. That is a left-to-right transition, not a blob under the
   machine.

ALSO RULED OUT BY ARITHMETIC, not guesswork: the lamp vignette. `bdLampStops` (`app.nim:391-398`)
puts `rgb(10,4,1) α=0.62` at the outer stop. Evaluating `bdStopColor` at the bottom-centre gives a
composite of ≈(77,49,29) at y=810 — which matches the REFERENCE's (74,46,24) closely and is 20
luma above the port's (58,32,17). **So the port is darker than its own lamp model says it should
be, and the lamp stops themselves are roughly right.** Likewise `bpEdgeToning` (`:755-791`) only
*lightens* (tan rgba(150,125,85) at α≤0.12), so it cannot be the cause of darkening.

**OPEN LEAD, NOT A CONCLUSION:** the reference is brighter than the port at x≈100-200 at y=805
(ref 108 vs frame 96) and the port tracks the reference only at x<100. There is a real
left-edge bright region in the reference that the port does not reproduce. Whether that is a lamp
pool, a prop, or a CSS gradient still has to be established — and per this lane's own record, it
gets established by **cross-column agreement**, not from one column's dip.

NEXT: map the horizontal profile at y=805 across many columns in both images and find where they
diverge, the way the vertical profile was mapped above. The divergence point will name the element.
DO NOT tune a constant off the x=600 numbers alone — that is the exact move that produced
`903a516` and `5db42b2`.#### Bottom strip horizontal profile: clean at x<140, uniform −13..−17 everywhere else

`xprof.mjs` (new probe) walks one row in 20px boxes. At y=805, ref vs frame red channel:

```
   x      0   40   80  120  160  200  240  280 ...  640  ... 1040 1080 1160 1240
 delta   -5   +1   -2   -5  -12  -15  -16  -14     -14     -11  -12  -15  -14
```

**The profile has a sharp, clean structure:**

- **x = 0..140: the port MATCHES the reference** (delta −5, +1, −2, −5).
- **x = 160..1280: a flat, uniform −13..−17 deficit**, with no structure across the machine's
  span or past it.

A cast shadow, a missing prop, or a misplaced element would produce structure. **A flat offset
that switches on at one x and never varies again is a single pass with the wrong alpha over a
region** — not a displaced object.

AND THE PROFILE SHAPE DIFFERS. Reference peak is at **x≈200** (111), matching the lamp centre
`w*0.18 = 230`; the port's peak is at **x≈40-80** (102-103), which is not. So the port's lighting
in this strip is not merely darker, it peaks in the wrong place.

PRIME SUSPECT, stated as a hypothesis and NOT as a conclusion: **`bdLampLight` builds the radial
from RINGS=96 STROKED annuli** (`app.nim:426-450`). A stroked annulus composites its alpha along a
band, but where consecutive annuli' strokes meet the coverage **adds**. The CSS source is a single
`fillRect`-style gradient where each pixel is painted exactly once. If the annuli over-cover, the
dark outer stop (`rgb(10,4,1) α=0.62`) gets applied more times than the model intends and the
bottom of the frame goes too dark — while the top, where the stops are bright, stays close
enough to hide the error. **That asymmetry is what makes this bug easy to miss and has kept the
bottom strip blamed for a dozen rounds.**

The arithmetic from the previous entry already pointed here and was worth repeating: hand-evaluating
`bdStopColor` at bottom-centre predicts ≈(77,49,29), matching the REFERENCE's (74,46,24) and 20 luma
above the port's (58,32,17). **The port renders darker than its own stop table says it should.**
That gap is the defect, and over-covering annuli explain it in a way no stop colour can.

NEXT, concrete and in this order:
  1. Count how many times a single pixel at the bottom edge is painted by `bdLampLight`
     (instrument the annuli loop's radial step against the stroke width). If coverage > 1, that
     is the bug.
  2. Only then touch the stop colours. Adjusting stops to compensate for double-compositing is
     how a rendering bug gets frozen in as a "tuned" constant.#### Two corrections. (1) Lamp annulus over-coverage REFUTED by arithmetic. (2) My round-248 "not the machine shadow" was WRONG.

**(1) The annulus hypothesis is dead — I refuted my own guess.** `bdLampLight` (`:441-449`) strokes
ring *i* at radius `lr*mid` with pen width `lr*(t1-t0)`, where `mid=(t0+t1)/2` and
`t1-t0=1/RINGS`. So ring *i* covers exactly

```
[ lr*mid - lr*(t1-t0)/2 , lr*mid + lr*(t1-t0)/2 ] = [ lr*t0 , lr*t1 ]
```

which tiles `[0, lr]` **with no overlap**. Each pixel is painted once. Over-coverage is impossible
as written, so `bc140b7`'s prime suspect is withdrawn. (It was a reasonable guess and a cheap test,
but the test says no.)

**(2) The "NOT a cast shadow" claim in `d2bd1b7` was bad reasoning.** I argued that because the port
matches the reference at x=60, the shadow cannot be responsible. **That is exactly what a shadow
predicts** — x=60 is simply *outside* the footprint. I used agreement outside the suspect's
footprint as evidence of the suspect's absence. Same error class as `5db42b2`, in the opposite
direction: I let the hypothesis shape what the measurement was allowed to say.

THE SHADOW'S ACTUAL FOOTPRINT, computed from `:2338-2341` with MX=230.4 MW=819.2 MY=437.36
U=0.8192:

```
sx = MX - MW*0.06 = 181.25        centre = (sx+rx, sy+ry) = (640.0, 769.1)
sy = MY + 300*U   = 683.12        rx = MW*0.56 = 458.75
ry = 210*U/2      = 86.02         y  span = 683 .. 855   (clipped at 816)
                                  x  span = 181 .. 1099
```

**That matches the measurement.** The deficit switches on at x≈160-181 and is flat to x=1099 —
precisely the ellipse's horizontal extent. And the source is a light at upper-left, so a shadow
cast down-and-right is the right direction.

CONTROL (the run that should have been run last round) — red-channel delta at four columns:

```
y=150   x60 -2   x300 -1   x900  +3   x1250  -3
y=300   x60 -5   x300 +12   x900  -6   x1250  +2
y=420   x60 +14  x300  +9   x900  -5   x1250  -4
y=700   x60 +11  x300  -1   x900  -3   x1250  +7
y=780   x60  -8  x300   0   x900   0   x1250 -13
y=791   x60  -6  x300   0   x900 +18   x1250 -15
y=805   x60  -3  x300 -13   x900 -11   x1250 -13
```

**The deficit exists only at y≥791 and only for x≥160** — it is absent everywhere else, including
directly above. So it is a single element below the machine's bottom edge, which is what a cast
shadow is.

**WHAT IS STILL UNEXPLAINED, and must not be quietly absorbed:** the deficit continues past the
shadow's right edge. At y=805 the delta is −11 at x=1040, −12 at x=1080, −13 at x=1120, −15 at
x=1240 — but the ellipse ends at x=1099. **A flat deficit extending ~180px beyond the footprint is
a second contribution, not a rounded edge.** Either another element covers x>1099, or the ellipse's
falloff is wider than `drawMachineShadow` computes.

NEXT: ① map the deficit's vertical profile at x=1250 (outside the shadow) to find whether it is
the same element or a different one — the two must be separated before anything is tuned ·
② only then judge the shadow's own alpha. **Do not start by adjusting the shadow's opacity**: if
a second element is contributing, every opacity change will look like a partial fix that never
quite lands, which is the signature of the last dozen refuted bottom-strip theories.#### Two contributions separated. The x>1099 deficit is NOT the machine shadow and starts ABOVE the machine's bottom edge.

`yprof.mjs` (new probe) reads two x positions in one pass — x=600 inside the shadow footprint,
x=1250 outside it. Red channel, 1px rows:

```
   y    refA frA   dA      refB frB   dB        A = x=600 (inside)   B = x=1250 (outside)
 780   124  123   -1        71   58  -13 <<
 785   122  122    0        65   57   -8 <
 788   121  121   +1        71   59  -12 <<
 790   120  121   +1        72   58  -15 <<
 791    59   82  +24        71   56  -15 <<
 792    56   48   -8 <      65   56   -9 <
 795    62   50  -12 <<     57   56   -1
 796    66   50  -15 <<     47   56   +9
 799    63   44  -19 <<     62   55   -7 <
 805    71   56  -16 <<     66   53  -13 <<
 810    75   59  -16 <<     66   56  -10 <
 813    78   55  -23 <<     65   54  -11 <<
 815    79   58  -21 <<     68   50  -18 <<
```

**TWO DISTINCT SIGNATURES, and they are not the same element.**

1. **Inside the footprint (x=600): a clean monotonic deepening** from −8 at y=792 to **−23 at
   y=813**, starting exactly at the machine's bottom edge. That is the `drawMachineShadow` ellipse
   (centre 640,769; rx 458.75, ry 86.02; y span 683..855). It grows with distance below the ellipse's
   widest point, which is what an ellipse does.

2. **Outside the footprint (x=1250): a flat, noisy ≈−11** that is already present at
   **y=788–790 — ABOVE the machine's bottom edge of 790.8** — and does not deepen with distance
   (−15, −9, −1, +9, −7, −13, −11, −18 across y=788..815). **It does not grow, so it is not the
   shadow.** Its extent is x>1099, which is beyond the ellipse's 1099 edge.

**So the −14 across the bottom strip is two causes added together, and only one of them is the
machine shadow.** That is why every attempt to fix it by moving or dimming the shadow has read as
a partial fix that never quite lands — it can never fully land, because it is only part of the
cause. That is also the signature I flagged as a warning at the start of this line of work, and it
is now explained.

**THE SECOND ELEMENT IS NOT YET IDENTIFIED.** What is known: it covers x>1099, it is present from
at least y=788, it is ≈−11 flat, and it is absent at y=150/300/420/700 (control deltas −5..+14, no
consistent sign). Candidates worth separating before anything is tuned:
  - a right-side vignette or edge element that is wider than `bpEdgeToning`'s 4% band (which spans
    only x=1255.5..1280, so it cannot account for x=1099..1255)
  - a second bloom or lamp stop whose falloff reaches the bottom-right corner
  - a plank-tone or grain-amplitude difference that only shows where the desk is darkest

NEXT: map the deficit's **horizontal** profile at y=770 (above the machine, above the shadow's
visible band, where only this element exists). A single row read above the machine's bottom edge
isolates it completely — this is the cleanest available test and it has not been run.
**Do not tune either element's opacity until that row says which is which.**#### Isolated. The second element switches on at x≈1020-1040 — the machine's RIGHT edge (1049.6).

`xprof.mjs` at y=770 (above the machine body region, above the shadow's visible band, so only
the bottom-right element exists there):

```
   x     0   40   80  120  160  200  240 ... 1000  1040  1080  1120  1160  1200  1240
 delta  +4   +4   +4   +5   +4   -2   -4      0   -17   -15    -9   -11   -13   -10
```

**x = 0..1000: the port is within +0..+5 of the reference everywhere** — it is actually a shade
BRIGHTER. Above the machine's bottom edge the port is in good shape.

**The divergence is a single step between x=1000 (0) and x=1040 (−17), which is exactly the machine's
right edge at MX+MW = 1049.6.** After that it holds a steady −9..−17 out to x=1240. The reference
steps down at the same place (129 at x=1000 → 91 at x=1040) — **so the element is real and correctly
positioned in both; only its strength differs.**

**This unifies the two "causes" from the previous entry.** The flat −11 seen at x=1250 in the
y=780-815 range and this −17 at y=770 are very likely the same right-hand element, not two unrelated
things. The earlier "monotonic deepening inside the footprint vs flat outside" split was measuring
one shadow's elliptical falloff at two x positions, and reading the falloff as though it were a
second cause. **That was a mistake in the previous entry's framing and is corrected here.**

WHAT IS NOW WELL ESTABLISHED:
  - Above y=791 and left of x~1020, the port tracks the reference to within about 5 luma.
  - The defect is confined to the bottom-right region: right of the machine's right edge, below
    roughly y=770, and it is a single element, correctly placed, roughly 10-17 luma too strong.

THE OPEN QUESTION IS NARROW AND NOW NAMABLE: `drawMachineShadow` (`:2338-2341`) computes
`rx = MW*0.56 = 458.75`, giving a footprint of x=181..1099. But the deficit runs to x=1280. The
source's `#shadow` DIV is **1097 x 172** (per the docstring at `:2347`), and 1097/2 = **548.5**,
which does not equal `MW*0.56 = 458.75`. **If the shadow box's true half-width is 548.5 rather than
458.75, the ellipse is about 90px too narrow on each side** — which is consistent with the port
being too dark at x=1040-1280 and too dark in the middle-bottom, i.e. a shadow that is too strong
where it exists rather than one that is mispositioned.

NEXT, concrete and bounded:
  1. Re-derive the shadow's dimensions from html:32 in the source reference, and check whether the
     box is 1097 wide. If so, `rx` is 548.5, not 458.75.
  2. Change only `rx`, rebuild, re-render, re-score. One variable, from a known baseline of 29.23%.
  3. If the score moves and the bottom-right deficit shrinks proportionally, the box width was
     wrong. If it does not, the shadow is correctly sized and its ALPHA is the error — and those
     two must not be tried in the same edit.

**The alpha/width split matters.** `:2342` already records a previous shadow change that made
things worse (16.70% → 17.22%) and was reverted. Changing width and alpha together would produce a
third uninterpretable result.#### The shadow's WIDTH is right; its FALLOFF RADIUS is wrong by 5.3x. Confirmed from source html:493 and html:32.

`apps/typewriter/029-typewriter-letters.html:493`:

```js
place(shadow, MX-MW*0.06, MY+300*U, MW*1.12, 210*U);
```

`MW*1.12 = 917.5` and `210*U = 172.03`, so the box is **917.5 x 172** — **exactly** what
`drawMachineShadow` computes (`rx = MW*0.56 = 458.75`, `ry = 210*U/2 = 86.02`, centre
(640.0, 769.1)). **`db3622d`'s hypothesis that `rx` was ~90px too small is REFUTED by the source.**
Good: that one was checked against the source rather than inferred, and the source agreed with the
existing code.

**THE REAL DIFFERENCE IS THE FALLOFF, not the box.** Source `html:32`:

```css
#shadow{ ... background:radial-gradient(closest-side, rgba(12,6,2,.72), rgba(12,6,2,.35) 55%, rgba(12,6,2,0)); }
```

For a **917.5 x 172** box, `closest-side` means **the nearest side**, which is the *vertical* one:
the ending shape is a **circle of radius h/2 = 86**, centred at the box centre. The gradient's
stops are laid out over **86 pixels**, not over 458.75. `border-radius:50%` then clips that circle
to the full ellipse, so the visible shape is the ellipse but **the alpha reaches zero at 86px from
the centre and stays zero everywhere else inside the ellipse**.

The port instead spreads its ramp across the whole ellipse. `:2360-2368` walks `tOut` from 1 down to
0 with `tOut = 1 - k/shN` measured against `rx = 458.75`, so:

```
alpha_port(r) = ramp(r / 458.75)        alpha_source(r) = ramp(r / 86)
```

**The port's shadow is a 917px-wide soft blob where the source's is a 172px one** — 5.3x too wide.
At the machine's centre the two agree; everywhere else the port is darkening desk the source leaves
untouched. **This is the −10..−17 across x=1040..1280 and the whole bottom strip.**

NEGATIVE RESULT WORTH KEEPING, because it stops the next wrong turn: at (1240, 805) the distance from
the shadow centre (640, 769.1) is 601px. Both models give **alpha 0** there, yet the port still reads
−13. **So at that one point `drawMachineShadow` is not the whole story** — fixing the falloff radius
should clear most of x=1040..1280 and the bottom strip, but something else may still contribute out
at the far corner. Expect a partial improvement, and do not read a partial improvement as the fix
being wrong.

NEXT, one variable, from the 29.23% baseline:
  1. Change the ramp's argument from `t` (radius/rx) to `t` (radius/ry) in `shAlpha`/`tOut`, so the
     stops span 86px as the source does. **Do not touch `rx`, `ry`, the box, or the stop colours in
     the same edit** — `:2342` records a prior shadow change that regressed 16.70% -> 17.22%.
  2. Rebuild, re-render, re-score, and re-run the y=770 profile. Predicted: the −17 step at x=1040
     moves to roughly x=700..790 (the 86px band about x=640) and the far-corner −13 either clears or
     is isolated as a separate element.
  3. A score that does not move means `shAlpha` is not the function I think it is — read it before
     changing anything else.
#### VERIFIED: the machine shadow is a DISC of radius 86, not a wide ellipse. 29.23% -> 29.02%.

html:32 is `radial-gradient(closest-side, ...)`. For a 917.5 x 172 box the NEAREST side is the
vertical one, so the ending shape is a circle of radius h/2 = 86 and the stops span 86 pixels;
`border-radius:50%` clips that circle to the ellipse, which is a no-op. So the source's shadow is a
172px soft disc. The port stroked the ramp across the whole ellipse (`alpha = shAlpha(r/rx)`,
rx=458.75) - a 917px blob, 5.3x too wide.

Changed: dropped `d.scale(1.0, ry/rx)` and drew `d.circle(0, 0, ry*tOut, ...)`, so the stops span
86px as the source does. One variable; rx, ry, the box and the stop colours were left alone.

```
differing pixels : 303084 / 1044480 (29.02%)   was 305345 (29.23%)
mean |delta|     : 12.27                      was 12.21   (slightly worse)
```

MECHANISM CONFIRMED at the predicted place, and the prediction held at the far corner too:
y=770, x=1040: **-17 -> -6**. y=770, x=1080..1240: unchanged (-12,-9,-11,-13,-10). y=805,
x=1200..1240: unchanged (-15,-14).

**So the far-right deficit is a SECOND element, exactly as predicted before the render.** The disc
fix clears the shadow's over-reach; it does not clear x>1080. Note `:2342` records an earlier
"make it a closest-side CIRCLE" attempt that regressed 16.70% -> 17.22% and was reverted - that run
also changed other things, whereas this one changed only the radius basis.

Verified: host/run_tests.sh - 35/35 engine, 14/14 sandbox, 13/13 todo, sweep 5 passed 0 failed,
0 FAIL lines, exit 0.

STILL OPEN, measured and located: a flat -9..-15 for x>1080, below y~770, present with the
machine's shadow contributing nothing there. bpEdgeToning's band covers only x=1255.5..1280 and
cannot account for x=1080..1255. Next: find what darkens that region.#### The largest single defect in the frame is the cream CARD in the top-right (delta to -116). Located, not yet fixed.

Measured with `xprof.mjs`/`yprof.mjs` on the 29.02% frame, upper-middle region:

```
y=20   x840 120 | x920 185  x1000 185  x1080 186  x1160 185  x1240 180   (frame 92..119)
y=50   ref 246-255 across x=880..1240, frame 255 saturated
y=60   ref 209-215 at x=920..1240, frame 93..126        <-- delta -90 .. -116
y=100  ref 104..97, frame 104..96                       <-- matches
y=120  ref 74..94,  frame 79..92                        <-- matches
```

**At y=60 the port is up to 116 red below the reference** — the biggest single pixel error
anywhere in this app, and it was invisible until rows and columns were profiled SEPARATELY.
Averaging a region would have reported "the top strip is about 10% off" and hidden the 116.

**WHAT IT IS.** The bright band is a cream card, not lighting and not motes. Its brightness pins it
down: `#fbf6e8`/`#f1e8d2` (`.label`, html:89) has red 251/241 and `#f6ecd2`/`#e9dcbc` (`.tag`,
html:126) has red 246/233 — both match the saturated 247-255 band. The band peaks at y~50 and is
gone by y=100, spanning x~880..1250.

**THE PORT'S TEXT SITS LEFT OF THE REFERENCE'S.** Within the cream, the dips are the glyphs:

```
reference dips (dark text on cream) at x = 840, 960, 1100, 1260
frame dips                             at x =      940, 1080, 1240
```

So both draw the card and both draw its text, but the port's glyph columns are ~20-40px left and
its card's left edge starts too early (frame is bright at x=840 where the reference is 37). **This
is a position/rotation error, not a missing element** — a much cheaper class of bug than a missing
one, and it is why the delta is large but bounded.

**ALSO FOUND, which makes this actionable: `Draw.rotate` EXISTS.** `sdk/ui/paint.nim:99`:
```nim
proc rotate*(d: Draw; degrees: float32): Draw = (result = d; result.add "o " & f(degrees))
```
So the `-1.4deg` on `.label` (html:89) and the `3deg` on `.tag` (html:126) are reachable from app
code directly. **The comment at `app.nim:2159` — "Draw has no transform, so each rotated rectangle
is emitted as an explicit four-point path" — is now OUT OF DATE.** That workaround was written when
only `scale`/`translate` were exposed. Anything that hand-computes rotated corners to work around
a missing rotate should be revisited, and the corners computed by hand are exactly where a 20-40px
misplacement of glyphs comes from.

NOT YET DONE, and the order matters:
  1. Identify precisely WHICH card occupies x~880..1250 (`.label` and `.tag` are both cream and
     both candidates; `.tag` has `clip-path:polygon(22px 0,100% 0,100% 100%,22px 100%,0 50%)`, a
     pointed left edge, which would also explain the dark column at x=840).
  2. Then compare the port's hand-computed corner path against the card's true placement, and use
     `d.rotate` rather than a computed path.
  3. **Do not "fix" it by nudging the x offset.** The glyph columns and the card edge are off by
     DIFFERENT amounts, so a single translation cannot reconcile them — which is itself the
     evidence that this is rotation and not placement. Tuning an x to make the band score better
     would hide the real bug, exactly as the bottom strip's twelve refuted theories did.#### The -116 cream-card defect is in the HOST node tree, not in the app canvas. Boundary established.

Chased the top-right defect (see the previous entry) to its source. `drawProps` (`app.nim:2310`)
draws **only** `drawCard` and `drawPencil` — the left-hand `.card` and the pencil. It does not
draw the cream cards in the top-right at all.

Those are built as **host UI nodes**, not as canvas paint:

```
app.nim:2784   let label = panel(stage)      # .label  (html:89,  "Marlowe 44 · operator")
app.nim:2886   let tag   = panel(stage)      # .tag    (html:126, "Letter status")
```

`cTagHole` at `:2167` is a canvas constant for `.tag::before` and is **defined but never used** —
leftover from a canvas-drawn version that was replaced by the node version.

**THIS CHANGES THE OWNERSHIP OF THE BUG.** Everything wrong with that region — the card ~20-40px
left of the reference, the glyph columns offset by a different amount again — is produced by the
**host** (Yoga layout + Skia paint), because the app only supplies `panel(stage)` with CSS-derived
values. So this is:

- **NOT** fixable by editing `drawProps`, `drawCard`, `rotQuad` or any canvas code.
- **NOT** fixable by the hand-computed rotated-corner workaround at `:2176-2197`, which only
  affects the left-hand `.card` and the pencil.
- A candidate for a **host** defect — rotation, border-radius, clip-path, padding/border-box, or
  shadow geometry in the node pipeline.

**THE `Draw.rotate` FINDING FROM THE PREVIOUS ENTRY IS STILL TRUE BUT NOT THE FIX FOR THIS.**
`Draw.rotate` (`sdk/ui/paint.nim:99`) is a canvas op, and these cards are not on the canvas. It
remains useful for the `.card` and `.pencil`, and the stale comment at `:2159` should still be
corrected — but do **not** attribute the -116 to a missing canvas rotate.

**NEXT, and the owner changes:**
  1. Compare the node-built card's computed rect against the reference's measured edges. The
     reference's cream band spans x~880..1250 at y~50; get the node's actual x/y/w/h from the host.
  2. If the rect is off, suspect Yoga: `.label` uses `transform:rotate(-1.4deg)` plus
     `padding:14px 22px 12px` and `box-shadow`, and `.tag` uses `clip-path:polygon(22px 0,100% 0,
     100% 100%,22px 100%,0 50%)` with `padding:14px 16px 14px 36px`. **A `box-sizing` or
     padding-order mismatch between the CSS and the Yoga mapping shifts a card by tens of pixels
     while leaving its size nearly right — which is precisely the observed signature** (card and
     glyphs off by *different* amounts, neither off by the same amount as the other's size).
  3. This is engine work, so it needs a `render/` test in the same task (AGENTS.md rule 6) and a
     note in `DECISION_QUEUE.md` if a new node behaviour is required. **Do not fix it in app code
     by nudging coordinates** — the app does not own those coordinates.

STATUS AT HANDOFF: typewriter 29.02%, tree clean, live app running. This defect is understood and
bounded but NOT fixed; fixing it correctly is host-side and needs its own task.
#### VERIFIED FIX: the #tag prop was 24px too short. html:126 line-height:1.75 was never applied. 29.02% -> 28.67%, and the region is now BYTE-EXACT.

`.tag` (html:126) declares `line-height:1.75` with `font-size:12px`, so each of its 4 rows is
**21px** and the card is 14+14+4*21 = **112px** tall. The port's comment at `:2895` claimed
`tagCol.spacing(0)` would let line-height do the spacing — **but line-height does not reach the
host's row layout**, so all four rows collapsed to ~15px and the card came out 88px.

Measured before, at x=1120 y=680: ref rgb(233,221,189) vs frame rgb(65,36,16), delta
(-168,-185,-173) — the port had already turned to bare desk where the reference is still cream.
Measured after, same box: **ref rgb(233,221,189), frame rgb(233,221,189), delta (0,0,0),
max|d| = 0. BYTE EXACT.**

```
differing pixels : 299415 / 1044480 (28.67%)   was 303084 (29.02%)
mean |delta|     : 11.63                      was 12.27
```

THE LESSON, which is the transferable part: **a comment asserting that a CSS property is handled
elsewhere is not evidence that it is.** "line-height does the spacing" was a true statement about
CSS and a false statement about this host. When a region is short by a clean, round-box-sized
amount (24px here = 4 rows x 6px), suspect an omitted CSS property before suspecting a geometry
mistune — and fix it by applying the property's real value (21 = 1.75 * 12), not by nudging the
container until it looks right.

Verified: host/run_tests.sh - exit 0, 35/35 engine, 14/14 sandbox, 13/13 todo, sweep 5 passed
0 failed, 0 FAIL lines.
#### VERIFIED FIX: the operator card's box-shadow stacked. 28.67% -> 28.29%. Left flank now within 3 levels.

`html:120` is `box-shadow:0 18px 30px -12px rgba(0,0,0,.7)`. CSS insets the border box by
the -12 spread, offsets it down 18, and Gaussian-blurs with sigma = blur/2 = 15 — so the opaque
core sits 12px INSIDE the card and everything visible outside is only the tail
`coverage(d) = 0.7*Phi(-d/15)`.

The port instead drew six quads **OUTSET** from the border box with flat overlapping alpha, so
the five quads that reached left of the card stacked on each other. At 2px left of the card's
edge the old model predicted coverage 0.344 and MEASURED the port at red 81; the CSS curve gives
0.123 and the reference reads 112. **The old code was ~2.8x too opaque on the card's left flank,
which is exactly the x=13..28 band that made x=17..26 the worst columns in the frame.**

Replaced with 13 rings drawn largest-first from the Gaussian, whose alphas satisfy
`1 - prod(1-a) == 0.7*Phi(-g/15)` at every breakpoint.

```
  x     0   3   6   9  12  15  18  21  24(card interior)
  d    -1  -2  -2  -4  -2  -2  -3  +1  +1        was -15..-33 at x=13..21
differing pixels : 295436 / 1044480 (28.29%)   was 299415 (28.67%)
mean |delta|     : 11.51                      was 11.63
```

Both of the agent's pre-declared falsifiers were run before accepting: |d| <= 8 at x=13..21 (got
-2..-3) and the below-card strip at x=131 (now +0..+2 at y=538..546, was -21..-34). The strip at
y=548..554 still reads -12..-16, which is the grain floor rather than the shadow.

**THE TRANSFERABLE RULE — this is the second time today a "falling opacity" stand-in for a blur
was the bug, and both times the alphas STACKED rather than accumulating correctly.** When
approximating `box-shadow` with N concentric shapes, the per-shape alpha must be chosen so their
source-over ACCUMULATION equals the intended profile. Setting "each ring a bit fainter than the
last" and letting them overlap produces a far denser edge than intended, and the error is largest
exactly where the shapes overlap most — at the edge of the shape, which is the whole point of a
soft shadow. A stacked-alpha approximation must be checked against the intended value AT THE EDGE,
not in the middle where there is only one layer.