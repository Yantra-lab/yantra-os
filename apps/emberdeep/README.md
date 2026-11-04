# EMBERDEEP

A native falling-sand expedition: 40 materials, seeded caves, fluid/gas automata, alchemical reactions, deck-evaluated wands, lanterns, creatures, sanctuaries, and the Well Eye. The world is computed into RGBA at 384×216 and nearest-scaled into a 1280×816 native desktop frame; no screenshot, DOM, browser runner, or remote asset is used.

## Controls

- **A / D** or arrows: move; **W / Space / Up**: jump and hover
- **Mouse**: aim; **left button**: cast; **F**: kick; **G**: throw a flask
- **1–4** or the four native wand cards: equip a wand
- **Esc / P** or **Pause**: hold/resume the material clock
- A sanctuary pauses play for three blessings; choose by mouse or **1–3**
- Death and victory offer a real **Descend Again** button; **R** also restarts a completed run
- **Sound** toggles the five synthesized native voices (headless proof checks nodes, not speakers)

## Build and verification

Build only the cold module; there is deliberately no `emberdeep_warm` path.

```sh
export PATH="/home/ubuntu/tools/nim-2.2.4/bin:$PATH"
export YANTRA_NIM_FLAGS=""
bash yantra-os/tools/build-wasm.sh yantra-os/apps/emberdeep/app.nim yantra-os/apps/emberdeep/app.wasm --release
nim c -r --nimCache:/tmp/ember-premiere-math yantra-os/apps/emberdeep/tests/t_emberdeep.nim
```

`tests/proof_host.nim` and `tests/native_driver.nim` are native-only acceptance fixtures. The first puts `y:emberdeep` in a deliberately smaller transformed AppView; the second drives the real root Engine with keys, key-up, pointer down/up, native buttons and long-running natural death, then clicks restart at the transformed root position. They do not inspect or write wasm memory. Gameplay-depth/death fixtures are separate from these UI proofs; no claim is made that a keyboard script exercised all 40 materials or every creature.

## Provenance

Fresh Nim implementation and native presentation based on behavioral research into falling-sand roguelikes, including [JerryLiu369/noita-benchmark](https://github.com/JerryLiu369/noita-benchmark). The publication contains no JavaScript, original source dumps, reference screenshots, third-party art, or comparison runners. Typography uses the platform's existing DejaVu Sans and DejaVu Sans Mono installation; the geometric UI, presentation exposure, ornaments, and English writing are authored for this native edition.
