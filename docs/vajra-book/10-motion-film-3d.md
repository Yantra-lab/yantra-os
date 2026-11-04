# 10. Motion, film and 3D

One clock, one kind of value that moves, and one engine for screens, films and 3D
scenes. A film is an app rendered on an exact clock; a scene is views and 3D nodes.

## 10.1 Motion (built)

```text
let slide = keys(0s: 0px, 1.5s: 200px, 3s: 80px, ease = smooth)
slide.at(1s)                        # the value one second in
let fade = keys(0s: #000000, 1s: #FFFFFF)    # colours mix in linear light
```

- Numbers, lengths, angles, durations and colours move, and so does anything with a
  `mix(a, b, f)` (`vajra/motion.nim`, t_views).
- Eases: `linear`, `smooth`, `easeIn`, `easeOut`, `snap`.
- The engine's own animation properties (`AnimFrom`, `AnimTo`, `AnimDuration`,
  `AnimEasing`, transitions) are in its protocol (`protocol/schema.nim`).

**planned:** springs (`spring(stiffness, damping)`), motion tied to scrolling, and a
`timeline` that holds many keyed values and nested timelines.

## 10.2 Films from code (built)

`yantra-film intro.wasm intro.mp4 --seconds 6 --fps 60 --size 1920x1080` renders an app
frame by frame on an exact clock and encodes the video directly: no screen capture. Every
frame is the same on every run, at 720p, 1080p or 4K (`render/native/film.nim`; its test
`render/native/t_film.nim` is not yet in the gate).

**planned:**
- `film` as a Vajra word: scenes, cuts, cameras, titles and sound on one timeline, each
  part a view or a scene.
- Generated assets placed in a film by their address (§12).
- The photoreal pass: for every frame the engine gives the exact depth, surface normals,
  edges and object masks; a video model that takes these as guides turns the render into
  photoreal footage that keeps the motion exactly (§12).

## 10.3 3D

- The protocol has `Scene3D`, `Model`, `Mesh`, `Camera`, `Light` and `Particles` nodes,
  with position, rotation, scale, metalness and roughness (`protocol/schema.nim`).
- Filament draws them; Jolt is the physics. Both are wrapped and imported by the native
  engine (`render/native/engine.nim`).

**planned:** materials and lights as records, scenes as files the studio can make (§12),
3D models from models (`mesh(…)`), physics bodies and joints as words, and the same scene
in a window, a film and a headset (§9.4).

## 10.4 Games

**planned:** a game's world is a fast, in-memory state with a fixed step, separate from
the database: entities and their parts in arrays, stepped deterministically, saved to the
Atlas only as it needs. The same inputs give the same world, which makes replays (§14) and
rollback multiplayer (§8) possible.

## 10.5 Scenes: a graph of typed media nodes

Anything visual or audible, from a poster to a feature film, is a graph of typed nodes.
Each node is a cell: it has versions, facets (§16.11) and its own history, and it can be
made or changed by its own stream (§16.7) without touching the rest. **planned**

```text
scene Launch
  let city = mesh("a coastal city at dusk, low poly", detail = high)
    .material(glass = 30%, rain = live(Weather.now(here).rain))   # bound to live data
  let sky = image("monsoon clouds over the sea, 35mm", size = 4096x2048)
  let waves = video(from = sky, prompt = "slow swell", length = 10s)
  let shore = mask(waves, keep = "the shoreline", feather = 24px)

  layer sky                                     # bottom to top
  layer waves, masked = shore, blend = screen
  place city, at = (0, -2, -30), camera = dolly(from = 40m, to = 12m, over = 10s)
  title "Monsoon", at = 3s, font = Satoshi, size = 120px
  sound music("tense strings, rising, 10s"), level = -12dB
```

| Node | Typed by | Made by |
|---|---|---|
| `Image`, `Clip` (video), `Sound`, `Mesh`, `Material`, `Environment` | size, length, frame rate, format; for meshes, level of detail | a provider call (§12), the engine, or a file |
| `mask`, `layer`, `blend`, `grade` | the nodes they apply to | the engine (Skia, Filament) |
| `camera`, `light`, `place`, `dolly`, `orbit`, `path` | positions, times, lenses | code, or the camera planner |
| `blockout` | a scene description | a provider, then refined |
| `shot`, `cut`, `timeline`, `title` | times on one clock | `film` (§10.2) |
| `live(query)` | the type of its value | the Atlas: the node changes when the rows do |

What it means:
- A node is data. It may be made by a provider call (§12), by asking a person or an
  agent (§16.12), by hand in the studio, or from a file; how it was made is its history,
  never its type.
- A node's inputs and outputs are typed, so a wrong join (a 4-second clip on a 10-second
  layer, a mask of another size) fails to build, not to render.
- **Variants** are derived nodes: sizes, crops, levels of detail, languages, the same
  shot at 9:16. Each is made once and kept by the hash of what it came from.
- **Live data.** A node bound to a query (`live(…)`) is redrawn when its rows change: a
  dashboard in 3D, a poster with today's prices, a scene lit by the weather.
- **One stream per node.** The graph is the plan for forking: each node's inputs and
  outputs are its contract, so whoever makes the scene (a person, or an agent asked for it)
  can give each shot, mesh or sound its own stream, and each stream works on its node alone.
- **Memory of everything.** Every node version, every provider call with its prompt, seed
  and cost, every review is kept (§25). A scene can be replayed, compared with an earlier
  one, or redone one node at a time.

**The bar it must clear.** Everything the Scenario add-on for Blender offers, done as code,
with many agents at once and the whole history kept: images (from text and from
references), video (from text, images or a playblast), 3D meshes and mesh edits,
PBR materials, speech, music and sound on the timeline, still and video renders with a
camera path planner and style references, greybox blockouts from a description,
panoramas and HDRI environments, and film recipes turned into shots, a timeline, a review
and an exported film (§16.12, `film Monsoon`).

## 10.6 Every operation on images, sound, video, 3D and pages

Everything design tools, video tools, deck tools and 3D tools do is done here as code.
**planned** (what it stands on is noted where it is **built**)

**How it is made.** Every operation is a `func` on a typed value (`Image`, `Clip`, `Sound`,
`Mesh`, `Shape`, `Page`): pure, so its result is kept by the hash of its inputs and asked
for again costs nothing (a variant, §10.5). The operations are cells of extensions in the
Atlas (`@yantra/image`, `@yantra/video`, `@yantra/sound`, `@yantra/mesh`, `@yantra/pages`):
anyone adds one by writing a cell. The heavy work runs in the host's wrapped libraries, on
the GPU when there is one (§7): Skia (2D, SVG, PDF, text through HarfBuzz; **built**), FFmpeg
(video and sound; **built**), Filament (3D; **built**), Jolt (physics; **built**), and
libvips, Assimp, OpenUSD and Rubber Band as they are wrapped. What only a model can do
(cut out, segment, fill in, enlarge, relight, restyle, speak, compose, separate, sync lips)
is a provider call (§12), typed the same way.

```text
let hero = Image.read("hero.jpg")
  .crop(1920x1080, focus = faces)                     # keeps the faces in the frame
  .mask(path = svg("M0 0 C 420 140, 900 0, 1920 180 V 1080 H 0 Z"), feather = 12px)
  .mask(gradient = linear(top = 100%, bottom = 0%))   # fades out to the bottom
  .grade(lut = "teal-orange", strength = 60%)

let poster = canvas(1080x1350, fill = radial(#1E1B4B, #000000))
  .place(removeBackground(product), at = center, shadow = soft(24px))
  .text("Monsoon sale", font = Satoshi, size = 96px, fill = linear(#5B5BF6, #F59E0B))

let reel = Clip.read("talk.mp4")
  .trim(3s .. 48s)
  .reframe(9:16, follow = speaker)                    # tracks the speaker
  .captions(style = karaoke)                          # word by word, from the speech
  .withMusic(music("lo-fi, calm", length = 45s), duckUnder = speech, by = -12dB)

deck Pitch(brand = @svarog/brand)
  slide "Apps are graphs of nodes", layout = hero
  slide each Outline.lines, layout = auto             # one slide per line, laid out
```

| Medium | Operations |
|---|---|
| **Image** | crop (size, aspect, focus on faces, a subject or what draws the eye), fit, fill, rotate, flip, perspective, warp; masks from a shape, an SVG path, a gradient, another image's alpha or brightness, or text; every blend mode; layers and groups; blur, sharpen, grain, vignette, glow, shadow, stroke; curves, levels, hue, saturation, white balance, LUTs; gradients linear, radial, conic and mesh; by models: cut out, segment, fill in, extend, enlarge, relight, restyle, make |
| **Shapes and text** | SVG in and out; paths and their union, difference and intersection; any font with its OpenType features and variable axes; text on a path; every script shaped correctly; text filled with gradients or images, outlined, or extruded in 3D |
| **Video** | trim, cut, split, join, speed, reverse, freeze; crop and reframe with tracking; chroma and luma keys; masks moved by keyframes or by tracking; layers composited; transitions; motion graphics (keyframes, §10.1); camera moves (dolly, crash zoom, orbit, whip pan): exact on 3D scenes, and on footage by a video model; stabilise; grade per shot; captions timed to the word; by models: generate, extend, restyle, sync lips |
| **Sound** | cut, fade, crossfade, mix, duck; loudness to a standard (EBU R128); EQ, compression, reverb; pitch and time-stretch; beats and tempo; by models: clean up, separate into stems, speech, voices, music, effects |
| **3D** | primitives, booleans, extrude, bevel, subdivide, and a stack of modifiers as typed nodes; geometry from code; PBR materials and textures; lights, cameras, camera paths; skeletons and their animation; physics; particles; by models: meshes and textures from text or pictures; renders and films (§10.2) |
| **Pages** | slides (themes, layouts, layout worked out from the content, notes, transitions); documents (styles, tables, footnotes, contents); designs with brand kits (a brand's colours, fonts and logos as records) and templates as cells; one design in every size at once (variants); charts from queries |
| **Files** | A design, a film, a deck or a model is code; a file is only what that code compiles to. Exporting to the common formats (PNG, MP4, PDF, PPTX, glTF …) and reading them back as code comes later; until then the engine draws, plays and renders the code itself |

What each operation keeps: its inputs, its settings, its result's hash, and for a model call
the provider, prompt, seed and cost (§12). So any image, film or deck can be made again,
changed one step back, or traced to where each part came from.

## 10.7 Tests

Built: `render/native/t_film.nim`, t_views (keyframes).

Planned (each one is a task):
- A spring settles at its target, and its value at each frame is the same on every run.
- A `film` with two scenes and a cut renders the cut at exactly the frame of its time.
- The photoreal pass gets depth, normals, edges and masks that line up, pixel for pixel,
  with the rendered frame.
- A game stepped 10,000 times from the same inputs ends in the same state on two machines.
- A layer whose clip is shorter than its place on the timeline fails to build, naming both
  lengths.
- A node bound to `live(…)` is redrawn within one frame of its rows changing.
- A variant asked for twice is made once.
- A scene replayed from its runs, with no provider called, gives the same frames.
- `crop(…, focus = faces)` keeps every face of a test photo inside the frame.
- A mask from an SVG path and a gradient gives, pixel for pixel, what Skia gives for the
  same path and gradient drawn by hand.
- The same `crop` asked for twice with the same inputs is computed once.
- `reframe(9:16, follow = speaker)` keeps the speaker's face inside the frame in every frame.
- Loudness brought to EBU R128 measures -23 LUFS within 0.5.
- An operation written as a new cell of an extension is used by an app without any change to
  the core.
