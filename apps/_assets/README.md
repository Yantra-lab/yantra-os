# `apps/_assets` — the asset contract

One page that says where an image or a 3-D model has to live, what bytes the engine
will actually accept, how many of them are reasonable, and how a real asset got from
the GPU fleet into a running frame. Every number here was measured on this box; the
command or the `path:line` that produced it is beside it.

The proof is [`demo/`](demo/) plus [`proofs/`](proofs/): one window, left half an
`image` node, right half a `model` node, both reading their file out of the app's own
folder. It renders on the prebuilt engine:

```bash
/tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 "$PWD/apps/_assets/demo/app.wasm"
```

---

## 1 · Where an asset lives

**Next to the app module, inside the app's own folder.** An app cannot reach anything
outside that folder — that is the sandbox, not a style rule.

```
apps/<app-id>/
  app.nim
  app.wasm
  assets/            <- put files here
    poster.png
    mesh.glb
```

## 2 · How an app addresses it

```nim
image "assets/poster.png", width = 480, height = 500, fit = cover
model "assets/mesh.glb",   width = 480, height = 500
```

The path is the **first positional argument** and it is resolved as `appDir / path`
(`render/native/engine.nim:1193-1201`), where `appDir` is the directory the `.wasm`
was loaded from (`engine.nim:4409` — `appDir: wasmPath.parentDir`). So `assets/poster.png`
in a module at `apps/demo/app.wasm` means `apps/demo/assets/poster.png`. Nothing else.

`validAssetPath` (`engine.nim:934-938`) is strict, and a path that fails it draws
**nothing at all** — no error on screen, no console line:

| Rule | Refused |
|---|---|
| relative, no leading `/` | `/logo.png` |
| no `:` (so no drive letter) | `C:/art/logo.png` |
| no `\` | `assets\logo.png` |
| no `..` | `../shared/logo.png` |
| only `[A-Za-z0-9_./-]` | `assets/my logo.png` |
| length ≤ 200 | — |

Two special cases:

* `data/<name>` does **not** mean the app folder. It resolves to the app's *write*
  directory, `dataDir()/<appName>/<name>` (`engine.nim:1195-1197`) — what the app saved
  with a host call, not what you committed. `gallery3d` uses `data/` for its paintings
  (`apps/gallery3d/app.nim:16`), so those six files are expected in the runtime data
  directory, not in the repo. Worth knowing before you go looking for them.
* `https://…` works only if the window declares the host in `net = "…"`
  (`engine.nim:1203-1211`); cached under `dataDir()/<app>/` and faded in over 160 ms.

## 3 · What the engine actually accepts

### Rasters — decoded at runtime, no build step

`image` is a decoded bitmap, and **Skia decodes it when the frame is drawn**. There is
no build-time conversion, no texture atlas, no pre-multiplying to do yourself.

| Question | Answer | Source |
|---|---|---|
| Which formats? | **PNG and JPEG measured**. WebP and GIF are linked into the build (`libpng`, `libjpeg`, `libwebp`, `libwuffs` on the link line) but were not measured here | `libs/nimskia/src/nimskia.nim:19-31` |
| Is it decoded by extension or by content? | **By content.** JPEG bytes inside a file named `.png` rendered correctly (2,342 distinct colours in the node box) | measured, below |
| Colour space | sRGB, 8 bits per channel. Skia's decode target for drawing is `N32Premul` | `skia_shim.cpp` (`makeCodec` → `SkImageInfo::MakeN32Premul`) |
| Pre-multiplied alpha? | **No — give straight alpha and do nothing.** The file's alpha is unpremultiplied; Skia premultiplies internally on decode. Premultiplying a PNG yourself makes the edges too dark | same |
| Intrinsic size | the node takes the file's own width/height when the app gives neither, else falls back to 100×100 (`engine.nim:563-575`); giving one dimension is enough, the aspect ratio follows | `engine.nim:563-575` |
| Cost of a decode | **at the drawn size, not the file size** — the P2 pipeline decodes to the box it will be painted at, LRU-capped | `nimskia.nim:315-320`, `skia_shim.cpp:1123` |
| Does an SVG work in `image`? | No. Skia decodes it as a raster, so it has no intrinsic size. Use a `path` node or `Draw.svgPath` instead | `08-images-icons-and-svg.md` §3, §4 |

### Models — glTF 2.0, decoded by Filament

`model "file.glb"` is a real node (`nkModel` = 9, `sdk/ui/dsl.nim:330-336`,
`sdk/yantra.nim:217`). The chain:

```
model "x.glb"        sdk/ui/dsl.nim:330-336   sets pSource
  -> engine.nim:2089-2108                     newScene3D(pw,ph), scene.load(path), drawPixels
    -> nimfilament.yf_load                    filament_shim.cpp:189-225
      -> gltfio AssetLoader + ResourceLoader  filament_shim.cpp:16-21
```

* **`.glb` works today.** Textures packed *inside* the GLB are decoded (the loader
  registers `image/png` and `image/jpeg` providers, `filament_shim.cpp:210-211`).
* A `.gltf` with its own files beside it also works, but the sidecar paths resolve
  through the same `appDir` rule, so keep them next to the `.gltf`.
* A top-level `model` node **frames the camera on the model's bounding box**
  (`filament_shim.cpp:216-222`). A `model` **inside** a `scene3d` does not — it is
  placed as a world object and the camera is whatever the scene has. If a GLB renders
  as an empty dark panel, check which of the two you wrote.

## 4 · The proven loader path

The demo app renders both paths in one frame. Node boxes come from the engine itself,
never by eye:

```bash
/tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 --script="boxes" "$PWD/apps/_assets/demo/app.wasm"
# box 8  kind=5 x=16  y=63 w=480 h=500    <- Image
# box 11 kind=9 x=508 y=63 w=480 h=500    <- Model
```

Measured with [`measure.py`](measure.py) (the §7 metric of `docs/DEMO-READY.md`, plus a
region fingerprint and a pixel-diff):

| | before | after |
|---|---|---|
| `assets/poster.png` | placeholder, 18,985 B `52fbf11c…` | **FLUX.2-klein-4B**, 578,954 B `40e08bbe…` |
| image node box, distinct colours | **903** | **2,735** |
| image node box, sha256 of the region | `02459ca7…` | `4473148e…` |
| model node box, distinct colours (control) | 2,899 | **2,899 — unchanged** |
| model node box, sha256 of the region (control) | `ceecb338…` | `ceecb338… — identical` |
| whole frame, §7 distinct colours | 3,827 | 5,802 |
| pixels that changed, whole frame | — | **239,934 / 1,296,000 = 18.5134 %** |

Frames: [`proofs/before-placeholder.png`](proofs/before-placeholder.png) (152,539 B) and
[`proofs/after-flux-poster.png`](proofs/after-flux-poster.png) (252,117 B), both 1440×900.
**The two frames differ in exactly one file — `assets/poster.png`.** The 3-D half's
region hash is byte-identical across the pair, which is what makes the delta attributable
to the poster and not to the layout or the engine's mood.

Why the colour count alone would not be enough: it is nearly blind. The lead measured a
controlled case where 16.97 % of the frame changed while the colour count moved 517 → 506.
So this table quotes the changed-pixel fraction and a region hash next to the colour
count. The colour count moved here too (903 → 2,735) — it is reported because it is true,
not because it is sufficient.

A second, airtight control was run and then reverted: a 64×64 **solid red** PNG saved as
`assets/poster.png` produced exactly `(255, 0, 0)` on all 3,364 sampled pixels of the
node's central region — **one distinct colour**. That is the asset's bytes arriving on
screen, with nothing to interpret.

## 5 · Models that were rendered

Colours in the model node box (480×500, engine `--frames=8`), same app, same box:

| `assets/mesh.glb` | materials / images / textures | colours | note |
|---|---|---|---|
| missing | — | 7 | `ink = 0.0000` — nothing drawn |
| `mesh-test.glb`, 9,553,652 B | **0 / 0 / 0** | 530 | shape stage only: geometry with no material, so neutral grey |
| `mesh-textured.glb`, 2,367,248 B | **1 / 1 / 1** | 3,037 | `Hunyuan3D_baked_baseColor` |
| `mesh-mushroom-01.glb`, 2,319,188 B | **1 / 1 / 1** | 2,899 | shipped — smallest of the painted three |

`mesh-test.glb` is `NOT` broken: it is a real glTF 2.0 shape-stage artefact, and 530
colours is Filament's default material on a lit mesh, not an error. The painted models
prove the embedded `baseColorTexture` is decoded and applied.

## 6 · Size budget

The decoded cost is set by the box you draw into, not by the file, so the file size is a
clone and network concern rather than a frame-time one:

* decoded bytes = `drawn_w × drawn_h × 4` — a 1024² asset drawn at 480×500 is **0.96 MB**
  in the frame, not 4 MB (`nimskia.nim:315-320`, decode at the drawn size);
* the whole image cache is LRU-capped at **128 MiB** (`skia_shim.cpp:1056`), and one
  image's frames may not exceed a quarter of that — **32 MiB** (`skia_shim.cpp:1123`).

Budget this repo follows, so an app stays a small diff:

| kind | per file | per app | why |
|---|---|---|---|
| poster / texture | ≤ 1024×1024, ≤ 1 MB | ≤ 2 MB | a 1024² PNG of photographic content lands at 0.25–1.5 MB; `image-texture-titanium.png` is 1,531,455 B because it is a **1024×1024, 36,504-colour** photographic PBR map — that is what 1 MB of JPEG-artefact-free texture looks like, and it is not committed here |
| glb | ≤ 4 MiB | ≤ 6 MiB | `mesh-mushroom-01.glb` is 2,319,188 B: 60,000 faces + a 2048² baked baseColorTexture inside one file |

The poster in this repo is **578,954 B for 1024×1024** — FLUX's own PNG, committed at the
size the model wrote. It was not downscaled: 0.58 MB is inside budget and re-encoding it
would break the hash chain to the fleet's `gen1.json`.

## 7 · Provenance — a row or it does not exist

[`PROVENANCE.tsv`](PROVENANCE.tsv) has one tab-separated row per asset: file, bytes,
sha256, kind, model id, model revision, prompt, seed/steps, generated at, generator.
**No row, no asset.** Every hash was recomputed here with `sha256sum` and matches the
value the fleet's own log printed.

[`fetch.sh`](fetch.sh) is how an artefact becomes an asset:

```bash
./fetch.sh                                    # every *.png/*.glb in /tmp/gpu-fleet/out
./fetch.sh --list                             # hash and print, copy nothing
./fetch.sh --as poster.png:/tmp/gpu-fleet/out/image-yantra-poster.png
./fetch.sh --dest apps/poster/assets --as yantra-poster.png:/tmp/gpu-fleet/out/image-yantra-poster.png
```

It hashes the source, copies, hashes the copy, and deletes the copy if the two differ.
A file it cannot hash is refused, not copied — an empty hash comparing equal to another
empty hash is exactly how a bad copy passes. On an empty fleet it prints
`no artefacts yet` and exits 0: nothing there is a fact, not a failure.

## 8 · NOT SUPPORTED YET

**Nothing on this path is unsupported.** GLB loading was expected to be a gap and is not:
the `model` node, gltfio and the engine's paint path all exist and were measured rendering
the fleet's own artefacts (§5). The only honest gaps are narrower:

| gap | what it is | where it would be fixed |
|---|---|---|
| **`poster` still refuses to run** | `app requires unavailable import 'y_layer_save_png' — refusing to instantiate [WasmtimeError]`, exit 1, on the prebuilt `/tmp/stage1/yantra` | **not a source gap.** The worktree provides it at `host/host.nim:1222`; the shared repo's `host/host.nim` does not, and the binary predates it. A rebuild of the engine from a tree that includes that line fixes it. The artwork is staged at `apps/poster/assets/yantra-poster.png` waiting for that |
| WebP / GIF raster decode | linked but unmeasured here | `libs/nimskia/src/nimskia.nim:19-31` |
| animated GLB | the loader registers an `Animator` and `engine.nim:2106` reports `animations > 0`, but no app in this tree plays one | `libs/nimfilament/src/filament_shim.cpp:20` |

## 9 · What is *not* proven here

* The **poster app shows the poster** — not yet. The app cannot instantiate on the
  prebuilt engine (§8). What is proven is the asset→engine→pixel path, in `demo/`.
* Nothing about Windows, or about the Qt path.
* The fleet's own serving was not exercised for the mesh: `mesh-mushroom-01.glb` came
  from the lane's bake script (`logs/bake_mesh.log`), while `http://127.0.0.1:8301` was
  up with `requests_served: 0` at the time of writing. The image came through the live
  server (`http://127.0.0.1:8101`, `/health` reported revision `e7b7dc27…`).

## 10 · Quick reference

```bash
# build the demo module (83,131 B)
export PATH=/home/ubuntu/tools/nim-2.2.4/bin:$PATH
cd yantra-os && bash tools/build-wasm.sh apps/_assets/demo/app.nim apps/_assets/demo/app.wasm --release

# design-system check on the demo — 0 findings
python3 apps/_design/audit.py apps/_assets/demo/app.nim

# frame, node boxes, and the numbers
/tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 --script="boxes" "$PWD/apps/_assets/demo/app.wasm"
python3 apps/_assets/measure.py /tmp/x.png --box 16,63,480,500
python3 apps/_assets/measure.py proofs/before-placeholder.png proofs/after-flux-poster.png
```
