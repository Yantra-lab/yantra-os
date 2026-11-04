# `apps/gallery3d` — a real fleet object standing in the hall

The Night Gallery now contains one real 3-D object: a **tencent/Hunyuan3D-2.1**
image-to-3D shape with its colour baked in, produced on the GPU fleet, on a plinth in
the corridor.

| | |
|---|---|
| asset | `assets/mesh-mushroom-01.glb` |
| bytes | **2,319,188** |
| sha256 | `9dc2648e9c4e60531082915e4295d2c3e22cd6e38a457d66b2da326bcf378a3c` |
| glTF | 1 material / 1 image / 1 texture — `Hunyuan3D_baked_baseColor`, roughness 0.72, metallic 0, doubleSided |
| bounds | 1.95 × 1.62 × 1.99 units, centred on the origin |
| provenance | POST `http://127.0.0.1:8301/mesh`, revision `0b94677654c57bb9a6b6845cd7b704ccf551d327`; row in [`../_assets/PROVENANCE.tsv`](../_assets/PROVENANCE.tsv) |

## The node

A new `view Exhibit(i: int)` sits beside `NightHall`, `Work` and `Spot`, and is added to
the scene after the hall:

```nim
view Exhibit(i: int)
  Mesh(shape = 0, posX = sideOf(i) * 0.72, posY = 0.56, posZ = zOf(i) + 1.1,
       sizeX = 0.78, sizeY = 1.12, sizeZ = 0.62, fill = #EADCC0, rough = 0.6)
  Model(source = "assets/mesh-mushroom-01.glb",
        posX = sideOf(i) * 0.72, posY = 1.44, posZ = zOf(i) + 1.1, scale = 0.4)
```

The path is relative and resolves through `appDir / path`
(`render/native/engine.nim:1193-1201`), so `assets/mesh-mushroom-01.glb` means
`apps/gallery3d/assets/mesh-mushroom-01.glb` — the sandbox rule, unchanged.

### The camera decision — a `Model` inside a `Scene3D` is NOT auto-framed

This is the trap this lane already paid for once. `filament_shim.cpp:216-222` computes a
bounding box and `lookAt`s it — but only on the `yf_load` path, i.e. a **top-level `model`
node**. A `Model` inside a `Scene3D` goes through `syncModel` (`render/native/scene3d.nim:184-210`)
instead: `resolveAsset`, `scene.model(path, copies)`, then
`scene.transform(obj, compose(pos, rot, scale))`. **It is a world object; the camera is
whatever the scene has.** The hall's camera is aimed at a painting
(`app.nim:103-104`), not at this object.

So the placement is arithmetic rather than taste:

* the eye is at `(-side, 1.52, z+2.4)`, the target at `(side*2.44, 1.45, z-0.2)`;
* half way down that sight line (`Δz = -1.3`) the gaze is at `(side*0.72, 1.485, z+1.1)`;
* the object's centre is put at that point — **hence the plinth**, not decoration:
  the camera's vertical half-fov is 23°, and standing on the floor 1.4 m away the
  object's base fell **34° below the gaze**, so its bottom was cut off by the viewport
  (measured: a 512×196 sliver at the bottom edge). Raised to the gaze height it is
  fully in frame.

Scale `0.4` turns the 1.95 × 1.62 × 1.99 unit GLB into a 0.78 × 0.65 × 0.80 m object,
289 px tall on the 1280×816 scene surface. The plinth is `#EADCC0`, the same museum
cream the hall already uses for its labels (`app.nim:75`).

## The measurement

Built and shot with this lane's harness, `wasm-opt` on PATH:

```bash
export PATH=/home/ubuntu/yantra/third_party/binaryen/bin:$PATH
bash yantra-os/apps/_build/build-app.sh gallery3d /tmp/g3.wasm
# stage the WHOLE app folder: assets resolve as appDir / path, and a bare /tmp module
# loses them — the way the harness once measured 1120 colours on gallery instead of 12,971
mkdir -p /tmp/g3app && cp -r yantra-os/apps/gallery3d/. /tmp/g3app/
cp /tmp/g3.wasm /tmp/g3app/app.wasm
bash yantra-os/apps/_build/shot.sh /tmp/g3app/app.wasm /tmp/after.png
```

The pair, both `1440×900`, both from the same harness:

| | before — the hall as shipped | after — the hall with the exhibit |
|---|---|---|
| frame colours (DEMO-READY §7) | **2,235** | **5,236** |
| frame bytes | 812,199 | 891,736 |
| ink | 0.947 | 0.963 |
| frame sha256 | `bbfec72a…` | `1bbe8e0b…` |

Frames: [`proofs/gallery3d-before-exhibit.png`](../proofs/gallery3d-before-exhibit.png) and
[`proofs/gallery3d-exhibit.png`](../proofs/gallery3d-exhibit.png). The before frame's hash
`bbfec72a…` is the same one `shot.sh` records for `apps/gallery3d` in its own header, so it
is the harness's reference frame, not a frame of my choosing.

Attribution, because the colour count alone is weak:

| | value |
|---|---|
| pixels changed, whole frame | **183,168 / 1,296,000 = 14.1333 %** |
| exhibit's screen region (plinth + object) | 580 × 574 at x[373,952] y[242,815] |
| colours in that region | 953 → **3,849** |
| sha256 of that region | `7116c0af…` → `022243da…` |
| **object alone**, measured against a plinth-only render | **479 × 393**, `y[242,634]` |
| colours in the object's box | 721 → **3,600** |
| sha256 of the object's box | `38adc7dc…` → `519d01f6…` |
| pixels the object alone changes | 94,859 / 1,296,000 = **7.3194 %** |

The object's box ends at `y = 634` inside an 816 px scene, so **the object is fully in
frame** — the plinth is what runs off the bottom edge, as a foreground pedestal does.

## Reproducing the shipped module

`apps/gallery3d/app.wasm` is **164,666 B**, sha256
`6144f9e670499cbfa1c04652dccced06483c5d90c5bd2fd1ac6ecf2aae89f29b`, and re-shooting it
from a staged app folder reproduces the after frame **byte for byte**
(`1bbe8e0b…` both). `app.json` and `app.yantra.json` were regenerated from the shipped
module with `node tools/export-json.mjs gallery3d` — never hand-edited — so
`module.bytes`/`module.sha256` (164,666 / `6144f9e6…`) and `source.bytes`/`source.sha256`
(8,602 / `5f565195…`) match the files on disk.

## Not done, deliberately

* the six paintings are still absent — the app reads them from `data/`, which is the app's
  **write** directory, `dataDir()/gallery3d/`, not `apps/gallery3d/` (`engine.nim:1195-1197`).
  Putting real FLUX art on the walls is a separate step with that path in mind.
* `rotY` is left at 0. The object reads correctly in colour and silhouette; whether its
  front faces the camera is a framing polish nobody can verify from a colour count.
