# 3D and shaders

Ground truth for this chapter:

| File | What it decides |
|---|---|
| `render/native/scene3d.nim` | what the renderer reads off a node (694 lines — the truth) |
| `libs/nimfilament/src/nimfilament.nim` + `filament_shim.cpp` | what the GPU layer accepts; the exact shader language |
| `protocol/schema.nim` | which prop name is legal on which node kind |
| `protocol/wire.nim` | wire ids `P_*`, node ids `K_*` |
| `sdk/ui/scene3d.nim` | `Buffer`, `Mat4`, `place`, `setGeometry`, `setInstances` |
| `render/native/t_scene3d.nim` | what a 3D app is *proved* to do |
| `render/native/t_particles.nim` | what the particle emitter is proved to do |
| `examples/cube3d.nim`, `examples/shell/world.nim` | apps that compile and run |

**What the 3D actually is.** The host's 2D is SDL3 + Skia. 3D is **Filament**, compiled natively
per shader at run time (`libs/nimfilament`), reached through `render/native/scene3d.nim`. The
finished RGBA frame comes back as pixels and is composited by the 2D layer
(`c.drawPixels`, `scene3d.nim:426`). So a 3D view is a normal node in the layout, and 2D content
drawn above it really does sit on top.

---

## 1. The minimal working 3D app

Two lines. The renderer supplies a default camera **and** a default sun for any scene that has
neither (`scene3d.nim:409-412`; `nimfilament.nim:132` "the first light replaces the default sun").

The imperative form — `examples/cube3d.nim`, verbatim in shape:

```nim
let scene = scene3d(win, 480, 360)      # a 3D viewport node
let cube = model(scene, "#Cube")        # a built-in primitive or a glTF path
```

The DSL block form (what `examples/shell/world.nim` uses):

```nim
scene3d(grow = 1):
  model "#Cube"
```

`scene3d(parent, w = 0, h = 0)` (`sdk/yantra.nim:208`) takes optional explicit size; in the DSL
use `grow = 1` or `width`/`height` instead. Objects are **not laid out** — they are placed in
world space by `posX/posY/posZ`; `scene3d` itself fills its box like any node.

`#Cube` and friends are 100 units across, and `scale` is a **multiplier** of that. The default
camera sits at z = 6, so a large `scale` puts the camera *inside* the mesh, backface culling
shows nothing, and the frame is a bare clear colour that looks exactly like "3D is broken"
(`examples/cube3d.nim:22-26`). If a scene renders nothing, check the scale first.

---

## 2. Node kinds and constructor signatures

`K_*` ids are in `protocol/wire.nim:13-52`. The DSL constructor names and their mapping are in
`sdk/ui/dsl.nim:337-359`; the imperative procs are in `sdk/yantra.nim:206-229`.

| DSL word | Node kind | wire id | Imperative proc |
|---|---|---|---|
| `scene3d` | `Scene3D` | `K_SCENE3D = 8` | `scene3d*(parent: Node, w: int32 = 0, h: int32 = 0): Node` |
| `camera` | `Camera` | `K_CAMERA = 10` | `camera*(parent: Node): Node` |
| `light` | `Light` | `K_LIGHT = 11` | `light*(parent: Node): Node` |
| `box`, `sphere`, `plane`, `cylinder`, `mesh` | `Mesh` | `K_MESH = 45` | (no separate proc — build with `make(nkMesh, parent)`) |
| `model "fox.glb"` | `Model` | `K_MODEL = 9` | `model*(parent: Node, meshy: string = "#Cube"): Node` |
| `particles` | `Particles` | `K_PARTICLES = 47` | — |

`box`/`sphere`/`plane`/`cylinder` are all `Mesh`; the DSL only sets `shape`:
`box` leaves it 0 (the `find` index is 0 and `if shapeOf > 0` skips it), `sphere` 1, `plane` 2,
`cylinder` 3. `shape(kind)` (`libs/nimfilament/src/shapes.nim:68`) is **0 box, 1 sphere, 2 plane,
3 cylinder**. `mesh` takes no shape — it draws `geometry = buf`.

`model`'s parameter is `meshy`, not `source` (shadowing, like `image`), and it is either a Qt-era
built-in (`"#Cube"`, `"#Sphere"`, `"#Cylinder"`, `"#Cone"`, `"#Plane"`) or an asset path.

**The default camera/light rule.** `paintScene3D` walks the scene's children; the first `camera`
*without* `target` becomes the view's camera. If there is none:
`eye = (0, 2, 6)`, `target = (0, 0, 0)`, `fov = 45` (`scene3d.nim:409-412`), applied once
(guarded by `camKey = "default"`). For lights there is no code path at all — the sun is created
inside the Filament scene and **the first explicit `light` replaces it**. So adding no light is
valid, and adding one is how you take over.

Picking: `onClick` on a mesh with `pickPoint()` → `(x, y, z)` in world space, and `pickInstance()`
→ which copy of an instanced mesh was hit (`sdk/ui/input.nim:48-50`).

---

## 3. Every 3D prop: type, meaning, default, honoured?

Types are from `protocol/schema.nim`; the wire ids from `protocol/wire.nim`. "Honoured" means
`render/native/scene3d.nim` actually reads it.

### Scene (`scene3d`)

| DSL prop | wire | type | meaning | default | honoured |
|---|---|---|---|---|---|
| `sky` | `P_SKY = 199` | int32 (`0xRRGGBB`) | skybox colour; **presence** turns the sky on | absent → transparent | yes, `scene3d.nim:357` |
| `fog` | `P_FOG = 197` | float32 | distance fog density | 0 (off) | yes |
| `fogColor` | `P_FOGCOLOR = 198` | int32 | fog colour | `0xFFFFFFFF` | yes |
| `fogHeight` | `P_FOGHEIGHT = 241` | float32 | height fog | 0 (off) | yes (via `post`) |
| `fogFalloff` | `P_FOGFALLOFF = 242` | float32 | height fog falloff | 1 | yes |
| `ambient` | `P_AMBIENT = 207` | float32 | sky light in lux | absent → `-1` sentinel = engine default | yes |
| `shadows` | `P_SHADOWS = 200` | bool | cascaded shadow maps | **true** unless you set `shadows = false` | yes |
| `bloom` | `P_BLOOM = 201` | float32 | bloom strength | 0 | yes |
| `ssao` | `P_SSAO = 202` | bool | ambient occlusion | false | yes |
| `taa` | `P_TAA = 234` | bool | temporal AA (also keeps the view repainting) | false (FXAA always on) | yes |
| `focus` | `P_FOCUS = 235` | float32 | depth of field focus distance, m | 0 (off) | yes |
| `dofBlur` | `P_DOFBLUR = 236` | float32 | depth of field blur | 0 | yes |
| `reflections` | `P_REFLECTIONS = 237` | bool | SSR | false | yes |
| `vignette` | `P_VIGNETTE = 238` | float32 | vignette | 0 | yes |
| `exposure` | `P_EXPOSURE = 239` | float32 | exposure, EV | 0 | yes |
| `toneMap` | `P_TONEMAP = 240` | int32 | 0 ACES, 1 filmic, 2 AgX, 3 neutral, 4 linear | 0 | yes |
| `gravity` | `P_GRAVITY = 233` | float32 | physics gravity | 0 | yes (Jolt; see `docs/agent-guide/from-three.md`) |
| `width`/`height`/`grow`/`visible`/`fill` | — | — | layout / clear colour | — | yes |

`saturate` and `contrast` are **not** scene props: `scene3d.nim:366` passes literal `1, 1` with
the comment "FX1 over the view". Grading is a 2D effect applied over the view, not a scene prop.

### Objects (`box`/`sphere`/`plane`/`cylinder`/`mesh` = `Mesh`, and `model`)

| DSL prop | wire | type | meaning | default | honoured |
|---|---|---|---|---|---|
| `posX/Y/Z` | `P_POS_X/Y/Z = 15-17` | float32 | world position | 0 | yes |
| `rotX/Y/Z` | `P_ROT_X/Y/Z = 12-14` | float32 | Euler **degrees**, applied Y then X then Z | 0 | yes |
| `scale` | `P_SCALE = 11` | float32 | uniform multiplier on the shape **and** `sizeX..` | 1 | yes |
| `sizeX/sizeY/sizeZ` | `P_SIZEX/Y/Z = 187-189` | float32 | non-uniform size, **multiplied** by `scale` | 1 | yes (`Mesh` only) |
| `fill` | `P_COLOR = 6` | int32 | material base colour (linearised with gamma 2.2) | `0xFFC8C8C8` | yes |
| `metal` | `P_METALNESS = 18` | float32 | 0 dielectric, 1 metal | **0** | yes |
| `rough` | `P_ROUGHNESS = 19` | float32 | 0 mirror, 1 diffuse | **0.6** | yes |
| `glow` | `P_GLOW = 196` | int32 | emissive colour (bloom picks it up) | absent → black | yes |
| `opacity` | `P_OPACITY = 9` | float32 | < 1 switches to blended | 1 | yes |
| `shape` | `P_SHAPE = 195` | int32 | 0 box, 1 sphere, 2 plane, 3 cylinder | 0 | yes |
| `geometry` | `P_GEOMETRY = 203` | int32 (Buffer) | the app's own vertices | 0 → built-in shape | yes (`Mesh` only) |
| `instances` | `P_INSTANCES = 204` | int32 (Buffer) | placements, one copy per matrix | absent → 1 copy | yes (`Mesh`, `Model`) |
| `colors` | `P_COLORS = 249` | int32 (Buffer) | 4 bytes RGBA per instance | absent → white | yes |
| `texture` | `P_TEXTURE = 225` | string | file path, `"layer:<id>"`, `"pixels:<buf>:<w>:<h>"`, or `"view:<name>"` | "" | yes |
| `tiling`/`tilingY` | `P_TILING/Y = 226-227` | float32 | texture repeat | 1 | yes |
| `normalMap`/`normalScale` | 243/244 | string/float32 | normal map | — / 1 | yes |
| `ormMap` | `P_ORMMAP = 245` | string | glTF ORM (r occlusion, g roughness, b metal) | "" | yes |
| `emissiveMap` | `P_EMISSIVEMAP = 246` | string | emissive map, times `glow` | "" | yes |
| `alphaMode`/`alphaCutoff` | 247/248 | int32/float32 | 0 opaque, 1 blended, 2 cut out | cutout at 0.5 | passed to the shim, **ignored on textured meshes** — `apps/minipaint/ENGINE-ISSUES.md` E6 |
| `shader` | `P_SHADER = 152` | string | body of `material()` | "" | yes — see §4 |
| `vertex` | `P_VERTEXSHADER = 209` | string | body of `materialVertex()` | "" | yes |
| `uniforms` | `P_UNIFORMS = 210` | string | up to 16 floats | "" | yes |
| `unlit` | `P_UNLIT = 211` | bool | UNLIT shading instead of LIT | false | yes |
| `body`/`mass`/`friction`/`bounce`/`damping` | 228-232 | | Jolt rigid body | | yes (physics) |

Model-only: `animation` (`P_ANIM_ATION = 206`, clip **index**, 0 = first, -1 = none), `play`
(`P_ANIM_CLIP = 250`, clip **name**; changing it crossfades over `blendTime`, default 0.25 s),
`animSpeed`, `animTime` (drive the pose yourself). All honoured in `syncModel`
(`scene3d.nim:214-231`); each instanced copy gets a `k * 0.37` time offset so a crowd is not in
step.

### Camera

`posX/Y/Z` (default eye `(0, 2, 6)`), `targetX/Y/Z` (default `(0, 0, 0)`), `fov` (`P_FOV = 193`,
default 45), `target` (`P_TARGET = 263`, **string**, default "") and `width`/`height` (default
512×512). `target = "name"` turns the node into a **render-to-texture camera**: it renders the
scene into a texture named `"view:name"`, and a mesh shows it with `texture = "view:name"`. That
camera is left out of its own picture. A camera *with* `target` never becomes the view's camera.

### Light

`lightKind` (`P_LIGHTKIND = 205`): **0 sun, 1 point, 2 spot**. `intensity`
(`P_INTENSITY = 194`) in lux for the sun, lumens otherwise — default **100000** for kind 0,
**10000** for kinds 1/2. `posY` defaults to 10. `targetX/Y/Z` give the direction (sun) or the aim
(point/spot); for a sun the default target is the origin. `fill` is the light colour (default
white). `shadows` defaults to **true** per light.

### Dead or misleading, honestly

- **`target` on `particles`** — `schema.nim:463` allows `target` on `Camera` only, and
  `syncParticles` never reads `P_TARGET`. It does nothing there.
- **`pointerLock`** (`P_POINTERLOCK = 208`) — a `Window`-level prop read by the host
  (`render/native/engine.nim:3228`), not by the 3D renderer. It is real; it is not a scene
  property.
- **`saturate` / `contrast`** on a scene — not props; hardcoded `1, 1` at `scene3d.nim:366`.
- **`ssao`, `bloom`, `taa`, `focus`, `dofBlur`, `reflections`, `vignette`, `exposure`, `toneMap`,
  `fogHeight`, `fogFalloff`, `ambient`, `animation`/`play`/`animSpeed`** — wired all the way to
  the shim, but **not asserted by `t_scene3d.nim` or `t_particles.nim`**. Honest status: real,
  untested end-to-end. Do not claim a pixel-verified result for them.
- **No image-based lighting.** The skybox is a flat colour
  (`filament_shim.cpp:887`), so there is nothing directional for a metal to reflect and metal can
  render near-black (`ENGINE-ISSUES.md` E9 — mechanism confirmed by reading the shim, symptom not
  reproduced there).
- **No webp decode** in the Filament texture path, and **no asset-ready signal**
  (`ENGINE-ISSUES.md` E7, E8). A `.webp` texture has no pixels to sample.
- **Not available**: motion blur, SSGI, god rays, chromatic aberration, custom full-screen passes
  (`docs/agent-guide/from-three.md` §Post-processing).

---

## 4. Custom shaders — the exact language

Yantra meshes take **Filament material code**, compiled natively at run time by `filamat` and
cached per source string. This is not GLSL you paste whole; it is two *bodies*.

- **`shader = "..."` is the body of `void material(inout MaterialInputs material)`**
  (`filament_shim.cpp:448-462`). It is appended **after** the built-in look, so colour × map ×
  instance colour, normal map, ORM and emissive have already been applied. Change them from here.
- **`vertex = "..."` is the body of `void materialVertex(inout MaterialVertexInputs material)`**
  (`filament_shim.cpp:463-467`). Move `material.worldPosition` — waves, wind, bending.
- **`unlit = true`** switches the whole material to `Shading::UNLIT` and skips the ORM block.

Anything Filament accepts you may write: `vec3`/`vec4`/`float`, `sin`, `mix`, `texture(...)`,
`if`/`for`, user helpers must be inlined in the body (there is no place to declare a function).

Writables on `material` in `shader`: `baseColor` (vec4), `metallic`, `roughness`,
`ambientOcclusion`, `emissive` (vec4), `normal`. Writables on `material` in `vertex`:
`worldPosition`, `instColor`.

Inputs available to both:

| Name | Type | Meaning |
|---|---|---|
| `materialParams.baseColor` | float4 | the mesh's `fill`, linearised |
| `materialParams.metallic` / `.roughness` | float | `metal` / `rough` |
| `materialParams.emissive` | float3 | `glow` |
| `materialParams.time` | float | **seconds since the view was created** |
| `materialParams.u[0..3]` | float4 ×4 | your `uniforms` — 16 floats |
| `materialParams.tiling` | float2 | the mesh's texture tiling |
| `materialParams.normalScale` | float | |
| `materialParams_map`, `materialParams_normalMap`, `materialParams_ormMap`, `materialParams_emissiveMap`, `materialParams_instTex` | sampler2D | |
| `getUV0()` | vec2 | the vertex UV |
| `getWorldPosition()` | vec3 | |
| `variable_instColor` | vec4 | this instance's colour (set for you in `vertex`) |
| `getInstanceIndex()` | int | **vertex only** — which copy of an instanced mesh |

### How uniforms are passed

`uniforms = "a, b, c, d"` — **a string of up to 16 numbers separated by commas**, spaces allowed.
`scene3d.nim:149-156` splits on `,`, `strip`s each part, `parseFloat`s it, and fills
`u[0..15]`; **the first four numbers are `u[0]` (a vec4), the next four `u[1]`**, and so on. That
is why the working example writes `materialParams.u[0].xyz` for three numbers. Numbers beyond 16
are dropped; anything unparseable leaves that slot at 0.

`materialParams.time` is supplied by the engine. If your shader or vertex source contains the
**substring `time`**, the renderer marks the view as moving and keeps repainting it
(`scene3d.nim:157`) — that is the whole of the "animate it" mechanism.

A shader that fails to compile leaves the mesh with its previous material and puts
`"shader: the shader did not compile (the log has the line)"` in the dev log; `t_scene3d.nim:85`
asserts the log stays clean.

### Working examples (copied from the repo, not invented)

`examples/shell/world.nim:58-60` — a pool whose colour comes from `uniforms`, with a surface that
moves on `time`:

```nim
plane @pool(posX = -4, posY = 0.02, posZ = 5, sizeX = 4, sizeZ = 4, uniforms = "0, 1, 0.8, 0",
            shader = "material.baseColor = vec4(materialParams.u[0].xyz, 1.0);",
            vertex = "material.worldPosition.y += 0.3 * sin(materialParams.time * 3.0);")
```

`libs/nimfilament/tests/t_scene.nim:83-84` — the same, from the shim's own test:

```nim
"material.baseColor = vec4(0.0, materialParams.u[0].y, 1.0, 1.0);",
"material.worldPosition.y += 0.5 * sin(materialParams.time);"
```

`docs/agent-guide/from-three.md` §Custom shaders has the four-number water form
(`uniforms = "0.1, 0.4, 0.6, 1"`, `material.roughness = 0.05;`).

`unlit = true` alone (no `shader` body) is enough for a flat `MeshBasicMaterial`-look object: the
renderer compiles the default body in UNLIT mode.

### Porting a GLSL shader

Only the names change: `vUv` → `getUV0()`, `uTime` → `materialParams.time`,
`uniform float x` → one component of `materialParams.u[k]`. If the injected GLSL computed
something in the vertex stage, it goes in `vertex`; if it set a colour or a material term, it goes
in `shader`. `t_scene.nim:100` proves a bad shader is reported, not silently drawn wrong.

---

## 5. Instancing — the key to data-visualisation 3D

One mesh, N copies, one copy of the data across the boundary. This is the API that makes
thousands of base pairs, bars, buildings or helices affordable.

`Buffer` is a distinct int32 handle (`sdk/ui/scene3d.nim`); a `toInt32` converter lets you write
`geometry = buf` / `instances = buf` directly.

```nim
import yantra

let b = newBuffer()                  # a buffer id
var at: seq[Mat4]
for i in 0 ..< 1000:
  at.add place(x, y, z, rotY = deg, sx = w, sy = h, sz = d)
b.setInstances(at)                   # ONE copy into the engine

# 4 bytes RGBA per copy
let tints = newBuffer()
var bytes: seq[byte]
for i in 0 ..< 1000: bytes.add [r, g, b, 255'u8]
tints.setData(addr bytes[0], bytes.len)
```

- `Mat4 = array[16, float32]`, **column-major**, glTF order. 64 bytes per copy; the renderer
  derives the copy count as `bytes div 64` (`scene3d.nim:67`).
- `place*(x, y, z: float32; rotX = 0, rotY = 0, rotZ = 0; sx = 1, sy = 1, sz = 1): Mat4` —
  rotation in **degrees**, applied Y then X then Z, exactly like `rotX/Y/Z`.
- `setInstances*(b: Buffer; placements: openArray[Mat4])` — call it again to move everything; the
  renderer is version-tracked, so an unchanged buffer costs nothing (`scene3d.nim:105-110`).
  An empty seq uploads an empty buffer and the object is removed.
- `setGeometry*(b: Buffer; verts: openArray[float32]; tris: openArray[uint32])` — your own mesh:
  **8 floats per vertex** `x y z nx ny nz u v`, then three `uint32` indices per triangle. Used as
  `mesh @name(geometry = b)`.
- `setData*(b: Buffer; data: pointer; bytes: int)` — raw bytes, for a `DataTexture` or the RGBA
  colour table.
- Attach with `box(instances = b, colors = tints, fill = 0xFFFFFF)`. `fill = 0xFFFFFF` is
  deliberate: the instance colour multiplies it, so white leaves the tints intact.
- `onClick:` + `pickInstance()` returns which copy was hit.

`examples/shell/world.nim:11-20,54` is the canonical hundred-house version and
`t_scene3d.nim:58-59` asserts both the drawing and the per-instance colours, while
`t_scene3d.nim:132-139` asserts a click reports `house 0..99`. **Instancing works, and it is
proven.** `examples/shell/fox.nim:42` does the same for a glTF (`model @herd("Fox.glb", instances = herd)`),
where each copy animates out of step.

Performance rule (`docs/agent-guide/from-three.md`): thousands of similar objects → **one** mesh
with `instances = buf` (and `colors = buf`), never thousands of nodes. Per-frame movement →
rebuild the `seq[Mat4]` and call `setInstances` again.

---

## 6. Post-processing and scene settings

All of these live on `scene3d` and reach the engine through two calls: `scene.env(...)`
(`scene3d.nim:357`) and `scene.post(...)` (`scene3d.nim:365`). Both are keyed and only re-sent
when the values change.

| Effect | Prop | Type | Default | Real? |
|---|---|---|---|---|
| Bloom | `bloom` | float32 | 0 | wired; not asserted by `t_scene3d` |
| SSAO / GTAO | `ssao` | bool | false | wired; not asserted |
| TAA (FXAA otherwise) | `taa` | bool | false | wired; also forces continuous repaint |
| Depth of field | `focus` (m) + `dofBlur` | float32 ×2 | 0 | wired; not asserted |
| Screen-space reflections | `reflections` | bool | false | wired; not asserted |
| Vignette | `vignette` | float32 | 0 | wired; not asserted |
| Exposure (EV) | `exposure` | float32 | 0 | wired; not asserted |
| Tone mapping | `toneMap` | int32 0 ACES / 1 filmic / 2 AgX / 3 neutral / 4 linear | 0 | wired; not asserted |
| Fog | `fog`, `fogColor`, `fogHeight`, `fogFalloff` | float32 / int32 | 0 | wired |
| Shadows | `shadows` (scene and per light) | bool | **true** | asserted — `t_scene3d.nim:69` |
| Glow (emissive) | `glow` on a mesh | int32 | black | asserted indirectly (instanced tints, lit faces) |
| Ambient / sky light | `ambient` (lux) | float32 | engine default | wired; not asserted |

"Real?" means the value reaches `filament_shim.cpp`'s `yf_env` / `yf_post`. What `t_scene3d.nim`
**actually asserts in pixels** is narrower: the sky colour, a lit box whose faces differ, a hundred
instanced houses with per-instance colours, a 2D layer as a texture, an app-vertex triangle,
**shadows on the ground**, a prop change repainting the view, a custom shader's colour, a shader on
time moving the surface, a tiled texture, picking (box / instance / sky), and a second camera into
a texture. Everything else in this table is wired but **unproven end-to-end** — say so.

Also not available: motion blur, SSGI, god rays, chromatic aberration, custom full-screen passes.
Saturation/contrast/grading are 2D effects applied over the view, not scene props.

---

## 7. Particles

`particles` (`K_PARTICLES = 47`) is an emitter the engine simulates each frame and draws as **one
instanced camera-facing quad**, unlit and transparent, sized and coloured by age
(`scene3d.nim:239-337`).

| Prop | wire | Type | Meaning | Default |
|---|---|---|---|---|
| `posX/posY/posZ` | 15-17 | float32 | emitter position | 0 |
| `rotX`/`rotZ` | 12/14 | float32 | tilt the emit direction (`rotY` is **not** used) | 0 |
| `rate` | `P_RATE = 254` | float32 | particles per second, fractional, accumulated | 0 |
| `burst` | `P_BURST = 255` | **string** | `"<count>#<tag>"`; fires whenever the string *changes* | "" |
| `lifetime` | `P_LIFETIME = 256` | float32 | seconds, ±20 % jitter; floored at 0.05 | 1 |
| `speed` | `P_SPEED = 257` | float32 | initial speed within ±25 % | 2 |
| `spread` | `P_SPREAD = 258` | float32 | cone half-angle, **degrees**, about the emit direction | 20 |
| `gravity` | `P_GRAVITY = 233` | float32 | downward acceleration on Y | 0 |
| `partSize` | `P_PARTSIZE = 259` | float32 | size at birth | 0.1 |
| `partSizeEnd` | `P_PARTSIZEEND = 260` | float32 | size at death | = `partSize` |
| `fill` | `P_COLOR = 6` | int32 | colour at birth | white |
| `colorEnd` | `P_COLOREND = 261` | int32 | colour at death | `fill` with alpha cleared |
| `glow` | `P_GLOW = 196` | int32 | emissive | black |
| `texture` | `P_TEXTURE = 225` | string | sprite image | none |
| `maxCount` | `P_MAXCOUNT = 262` | int32 | pool size, clamped to 1..100000 | 1000 |

Alpha fades as `1 - a²` toward death automatically; colour lerps `fill → colorEnd`. `burst` is a
*signal*, not a counter: the number is the part before `#`, and only a **changed string** emits
(`scene3d.nim:272-275`).

The verified example — `examples/shell/sparks.nim`, the fixture for `t_particles.nim`:

```nim
let boom = state ""
var booms = 0

app("Sparks", width = 400, height = 300, fill = 0x000000):
  column(grow = 1):
    button @blast "Blast":
      onClick:
        inc booms
        boom.set("300#" & $booms)
    scene3d @view(grow = 1, sky = 0x101018):
      camera(posY = 1.5, posZ = 6, targetY = 1.5)
      particles @fountain(posX = -1.2, posY = 0.5, rate = 300, lifetime = 1.2, speed = 5, spread = 15,
                          gravity = 9.8, partSize = 0.12, partSizeEnd = 0.02, fill = 0xFFA020,
                          colorEnd = 0xFF3000)
      particles @blue(posX = 1.5, posY = 1.5, burst = boom, lifetime = 0.8, speed = 3, spread = 180,
                      partSize = 0.1, fill = 0x40A0FF)
```

`t_particles.nim` asserts: nothing before emission, a steady stream, **no blue before the burst**,
more than 200 blue on one click of `blast`, and that they die afterwards.

---

## 8. Critical honesty

### 8.1 "3D renders only in a real window; offscreen 3D gives a blank frame that 'passes'"

This is `AGENTS.md:60`, and it is the single most important operational fact in this chapter.

What it means mechanically: `paintScene3D` needs a real Filament scene with a GPU surface
(`v.scene.ok`) and a real frame. If you drive the engine offscreen, or headless, or without the
MSVC `yfilament.dll` and a GPU, `newScene3D` fails, `if not v.scene.ok: return` fires
(`scene3d.nim:351`), the node paints its 2D surface only, and the frame is a flat clear colour.
Any assertion of the shape "the app started, no crash, some pixels were produced" **still passes**.
The 3D simply was never drawn.

Consequences for verification:

1. A green `t_scene3d` / `t_particles` result is only meaningful if the run had the native set-up:
   Skia private headers, `libyoga.a`, `wasmtime.dll`, the MSVC `yfilament.dll`, accesskit built
   by cargo (`apps/minipaint/ENGINE-ISSUES.md:1389-1395`).
2. **"The app builds" and "the app starts" prove nothing about 3D.** A compile check, a headless
   smoke run, or a screenshot diff against a blank scene can all pass with zero geometry on screen.
3. The honest bar for "3D works" is a **pixel** assertion in a test that ran on a real GPU —
   counting lit faces, counting instanced copies, reading a shader's computed colour, measuring
   that a shadow darkens the ground. `t_scene3d.nim` does exactly that and nothing less.
4. When a 3D claim cannot be verified on this machine, report it as **unverified**, with the
   mechanism you read and the symptom you did not reproduce — the format
   `ENGINE-ISSUES.md` uses. Never upgrade "wired in the source" to "works".

### 8.2 When 3D is *not* the right tool

A 3D scene is the right answer for solids with real lighting, a walkable camera, imported models,
picking, shadows, a crowd of identical meshes. It is the **wrong** answer for the things agents
most often reach for 3D to draw — a DNA helix, a rotating molecule, a ribbon, a chart in space.

Decision rule: **if you need to control exactly which pixels each element covers, project it
yourself into a 2D `canvas`.** Yantra's 2D canvas is Skia — a real GPU 2D path that is always on,
always headless-testable, and where every line, gradient, label and hit test is yours. A custom
vertex shader gives you a *displacement*, not a draw order, not text, not crisp hairlines, not
deterministic hit testing.

| | Yantra 3D (Filament) | 2D canvas + your own projection |
|---|---|---|
| Cost of one helix of 400 rungs | one `mesh(geometry = buf)` or one instanced mesh; GPU-lit | one path draw per rung; trivial |
| Exact colour per element | only through `colors = buf` or a shader | exact, always |
| Text labels in the scene | not available (you'd draw them as 2D above) | first-class |
| Lines / strokes of 1 px | aliased, MSAA-dependent | crisp, path stroking |
| Camera, orbit, depth of field, shadows | free | you write the maths (it's ~30 lines) |
| Verification | needs a real GPU window; blank frames can "pass" | pixel-diffable headless |
| Animate on time | `materialParams.time` (needs `"time"` in the source) | your own `t` state |
| Per-element click | `pickInstance()` / `pickPoint()` | your own hit test — exact |

For a DNA helix the 2D route is usually **more faithful and more controllable**: you compute each
rung's two projected endpoints, draw the ladder yourself, colour by base pair, label it, hit-test
it, and the result is identical on every machine. Use 3D when the *solid, lit, spatial* quality is
the point; use 2D + projection when the *diagram* is the point. `docs/agent-guide/from-three.md`
even says so: games that do their own collision maths should port it as plain Nim.

---

## 9. A complete example: instanced + custom-shaded

Every line below is taken from an app that a native test actually runs
(`examples/shell/world.nim` — the fixture for `t_scene3d.nim`), so it compiles by construction.
I did not build or run it in this session; build it with `tools/build-wasm.sh` before you claim
anything about how it looks.

It draws 400 instanced boxes (a field), a shader-lit ground, and an app-vertex triangle.

```nim
import std/math
import yantra

# --- the data: 400 placements, one copy across the boundary --------------------
let bars = newBuffer()
var at: seq[Mat4]
for i in 0 ..< 400:
  let x = float32(i mod 20) * 2.0 - 19.0
  let z = float32(i div 20) * 2.0 - 19.0
  let h  = 0.4 + 2.4 * float32((i * 37) mod 100) / 100.0     # deterministic height
  at.add place(x, h / 2, z, rotY = float32(i * 17), sx = 1.2, sy = h, sz = 1.2)
bars.setInstances(at)

# a colour per copy: 4 bytes RGBA, so the field reads as a heat map
let tints = newBuffer()
var bytes: seq[byte]
for i in 0 ..< 400:
  let t = float32((i * 53) mod 100) / 100.0
  bytes.add [byte(40 + 215 * t), byte(90 + 120 * t), byte(255 - 180 * t), 255'u8]
tints.setData(addr bytes[0], bytes.len)

# the app's own mesh: 8 floats per vertex (x y z nx ny nz u v), 3 indices per triangle
let tri = newBuffer()
tri.setGeometry([-1'f32, 0, 0, 0, 0, 1, 0, 1,
                  1, 0, 0, 0, 0, 1, 1, 1,
                  0, 1.5, 0, 0, 1, 0, 0.5, 0], [0'u32, 1, 2])

let hit = state ""

app("Field", width = 900, height = 560, fill = 0x000000):
  column(grow = 1):
    text @readout "{hit}", color = 0xFFFFFF
    scene3d @view(grow = 1, sky = 0x0B1020, shadows = true, fog = 0.012, fogColor = 0x0B1020):
      camera(posX = 0, posY = 14, posZ = 26, targetY = 1, fov = 50)
      light(posY = 20, targetX = 4, targetZ = 6, intensity = 110000)

      # one instanced mesh: 400 bars, each its own colour
      box @field(instances = bars, colors = tints, fill = 0xFFFFFF, rough = 0.6):
        onClick: hit.set("bar " & $pickInstance())

      # a custom-shaded ground: colour from uniforms, breathing on materialParams.time
      plane @floor(sizeX = 80, sizeZ = 80, rough = 0.9, uniforms = "0.08, 0.13, 0.24, 0",
                  shader = "material.baseColor = vec4(materialParams.u[0].xyz, 1.0); material.roughness = 0.85;",
                  vertex = "material.worldPosition.y += 0.12 * sin(materialParams.time * 1.5 + material.worldPosition.x * 0.2);")

      # the app's own triangle
      mesh @spike(geometry = tri, posX = 0, posY = 4, posZ = 0, fill = 0xFFB020, glow = 0x201000)
```

Notes on the pieces that are easy to get wrong:

- `fill = 0xFFFFFF` on an instanced mesh is not a typo — `material.baseColor` is
  `baseColor × map × instColor`, so white leaves the per-instance tint intact.
- `materialParams.u[0]` is the **first vec4**, i.e. the first four numbers of the `uniforms`
  string. Three numbers + a 0 is a common shape.
- The word `time` in the `vertex` source is what makes the renderer keep repainting the view.
- `pickInstance()` only means anything on a mesh with `instances = buf`.
- Building thousands of nodes instead of one instanced mesh is the failure mode this API exists to
  prevent.

---

## 10. Recipe: porting a three.js scene

`docs/agent-guide/from-three.md` is the full table; this is the order to work in.

| Three.js | Yantra |
|---|---|
| `new Scene()` + `WebGLRenderer` + canvas | `scene3d(grow = 1)` — a node in the layout; the engine renders it |
| `scene.background = color` | `scene3d(sky = 0x87B5E8)` |
| `FogExp2(c, d)` | `scene3d(fog = d, fogColor = c)`; height fog: `fogHeight`, `fogFalloff` |
| `renderer.shadowMap.enabled` | `scene3d(shadows = true)` (default on; cascaded on the sun) |
| `toneMapping = ACESFilmic` | `scene3d(toneMap = 0, exposure = 0)` |
| ambient / hemisphere light | `scene3d(ambient = 20000)` (lux) |
| `PerspectiveCamera` + `lookAt` | `camera(posX…, targetX…, fov = 50)`; omit it and you get `(0,2,6) → origin, 45°` |
| `DirectionalLight` | `light(lightKind = 0, posX…, targetX…, intensity = 100000, fill = …)` (lux) |
| `PointLight` / `SpotLight` | `light(lightKind = 1 / 2, …, intensity = …)` (lumens) |
| `Group` / parenting | `group` for layout lists; 3D objects live in world space — compute child poses yourself |
| `BoxGeometry(w,h,d)` | `box(sizeX = w, sizeY = h, sizeZ = d, …)` |
| `Sphere/Cylinder/Plane` | `sphere(…)`, `cylinder(…)`, `plane(… , rotX = 90)` to stand it up |
| `BufferGeometry` | `newBuffer()` + `setGeometry(verts, tris)` + `mesh(geometry = b)` |
| `Extrude/Lathe/ShapeGeometry` | generate the triangles in Nim, then `setGeometry` |
| `position` / `rotation` (radians) / `scale` | `posX/Y/Z`, `rotX/Y/Z` in **degrees** (Y then X then Z), `sizeX..` or `scale` |
| `InstancedMesh` + `setMatrixAt` | `newBuffer()` + `setInstances(mats)` (`place(...)` builds the matrix) + `box(instances = b)` |
| `instanceColor` / `setColorAt` | `colors = buf` — 4 bytes RGBA per copy |
| `visible = false` | `visible = false` |
| `MeshStandardMaterial.color` | `fill = 0xRRGGBB` |
| `metalness` / `roughness` | `metal` / `rough` (0..1; defaults 0 and 0.6) |
| `emissive` (+ intensity) | `glow = 0xRRGGBB`, with `scene3d(bloom = 0.3)` to see it |
| `map` + `repeat` | `texture = "file.png"`, `tiling = 4` (`tilingY` for the other axis) |
| `normalMap` / `normalScale` | `normalMap`, `normalScale = 1` |
| `roughnessMap` / `metalnessMap` / `aoMap` | one `ormMap` (r occlusion, g roughness, b metal — glTF's layout; pack yours) |
| `emissiveMap` | `emissiveMap` (multiplies `glow`) |
| `transparent` + `opacity` / `alphaTest` | `opacity = 0.4`, or `alphaMode = 1` / `alphaMode = 2, alphaCutoff = 0.5` (cutout is **ignored on textured meshes** — E6) |
| `MeshBasicMaterial` | `unlit = true` (add `shader` for anything more) |
| `ShaderMaterial` / `onBeforeCompile` | `shader = "..."` and/or `vertex = "..."` + `uniforms = "…"` — §4 |
| `CanvasTexture(canvas)` | draw into a `newLayer`, then `texture = "layer:" & $int32(myLayer)`; it re-uploads when you draw |
| `DataTexture(rgba, w, h)` | `texture = "pixels:" & $int32(buf) & ":" & $w & ":" & $h` |
| `WebGLRenderTarget` + 2nd camera | `camera(target = "mirror", width = 512, height = 512)` + `texture = "view:mirror"` |
| `GLTFLoader` | `model "hero.glb"` inside `scene3d` |
| `mixer.clipAction(...).play()` | `play = "Run"` (a string signal; changing it crossfades over `blendTime`) |
| `timeScale` / `mixer.setTime` | `animSpeed = 1.5` / `animTime = t` |
| bone rotation | `turnBone("hero", "Head", x, y, z)` in `onFrame`; `bonePos("hero", "RightHand")` |
| `SkeletonUtils.clone` for a crowd | one `model` with `instances = buf` (copies animate out of step) |
| `OrbitControls` | **no built-in.** A `camera` node plus `onFrame:` and `mouseDelta()`, or `app(pointerLock = true)` + `mouseDelta()`; compute `posX…/targetX…` yourself |
| `EffectComposer` bloom / SSAO / TAA / DOF / SSR / vignette / grading | `bloom`, `ssao`, `taa`, `focus` + `dofBlur`, `reflections`, `vignette`, `toneMap`, `exposure` on `scene3d` (§6 — wired, only `shadows` is pixel-asserted) |
| motion blur, SSGI, god rays, custom passes | **not available** — do the look in a 2D canvas over the view, or in the scene's own shader |
| `Points` / sprite systems | `particles(rate, burst, lifetime, speed, spread, gravity, partSize, partSizeEnd, fill, colorEnd, maxCount)` — §7 |
| physics (Cannon / Rapier / Ammo) | `body = fixed / dynamic / kinematic` on the mesh, `push`, `pushForce`, `setVelocity`, `raycast`, `rope`, `scene3d(gravity = 9.81)` |
| `requestAnimationFrame`, `keyState`, pointer lock | `onFrame:` with `frameDt()`, `keyHeld('w')`, `mouseDelta()`, `app(pointerLock = true)` |
| raycast for picking | `onClick:` on the mesh with `pickPoint()` / `pickInstance()` |

**Port order that avoids rework:** scene settings → camera and lights → one object to confirm
lighting → materials → instancing for anything repeated → textures → shaders → post → picking →
physics. Verify the first object in a real window (§8.1) before porting the other forty.

**The judgement call.** A three.js scene that is really a *diagram* — a helix, a graph laid out in
space, a labelled scatter — should not be ported to 3D at all. Keep the maths, move the drawing to
a 2D `canvas` (§8.2). Port to 3D when the thing is genuinely a solid lit world.



