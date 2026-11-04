# EMBERDEEP — native proof record

All measurements below are from this source tree. No browser/JS runner, memory mutation, reference screenshot, scripted attract mode, or warm build is involved. This is not a claim that keyboard input exercised every material, creature, biome, or boss.

## Accepted cold artifact

Built with `YANTRA_NIM_FLAGS=""` and:

```sh
bash yantra-os/tools/build-wasm.sh \
  yantra-os/apps/emberdeep/app.nim yantra-os/apps/emberdeep/app.wasm --release
```

The build script reports:

```
--cpu:wasm32 --os:any -d:yantra_engine -d:nimAllocPagesViaMalloc --mm:arc
--path:$ROOT/sdk --path:$ROOT/src
--d:release --opt:speed (clang -O3) then wasm-opt -Oz
```

| Item | Bytes / count | SHA-256 |
|---|---:|---|
| `app.wasm` | 241,099 B | `ce62d9c9443bda928201cd90c71fd312f91877fee239ac21fc9a6e72d02d490e` |
| `app.nim` | 23,597 B / 557 lines | `1b61ea817007c85b264e73bdda5d9c8410f7146b2c23cfbaf42b2301253f505a` |
| `emberdeep.nim` | 2,294 lines | `9bb0712f201a42836688739fa0fae19b36c67885544d368c5c9267fbb119d54f` |

### `--release` is pixel-identical, and 4.29x smaller

The module used to be shipped from the unoptimised build. Both builds were made from
this same source in this tree and rendered through `/home/ubuntu/qg/bin/shot.sh` at
1280x816 (freshly built branch engine):

| build | `app.wasm` | 1440x900 frame | `wait:45` PNG sha256 (1280x816) | `wait:240` PNG sha256 (1280x816) |
|---|---:|---|---|---|
| unoptimised | 1,034,613 B | runs | `7293d6d8771eeb8fdf3e25a7c9ecc63eafe6eb9518008fefac899fccf4a50d22` | `6b09ed60786eed35fe925503acf59e5d2a55b442d9e7e926c147633875a934d6` |
| `--release` (-O3 + `wasm-opt -Oz`) | 241,099 B | runs | `7293d6d8771eeb8fdf3e25a7c9ecc63eafe6eb9518008fefac899fccf4a50d22` | `6b09ed60786eed35fe925503acf59e5d2a55b442d9e7e926c147633875a934d6` |

Both frames are byte-identical between the two builds, at both a live `wait:45` frame and
a `wait:240` end-of-run frame. The 4.29x saving is code size only; the simulation and the
framebuffer are unchanged. (The unoptimised size measured 1,034,613 B here against the
1,034,580 B of the previously committed artifact — a 33 B toolchain difference, not a
source difference.)

There is no `-d:emberdeep_warm`, `-d:emberdeep_autostart`, or screenshot-only application path. The accepted proof starts the cold artifact before its first host tick. The measured `epochTime()` interval around the **whole native AppView host+child `start()`** was **295.610189 ms** on this accepted run; it is not a child-only timing and no frame-rate inference is made from it.

## Native AppView acceptance — actual accepted run

`tests/proof_host.nim` makes a 1000×700 root with a 37,29-positioned 920×640 `AppView`. Its fixed 1280×816 child therefore uses the real contain/letterbox transform. `tests/native_driver.nim` drives `render/native/engine.start`, `key`, recursive `keyUp`, `pointerMove/Down/Up`, `tick` and `paintFrame` through that real root. It reads only public node/draw state; it never reads or writes wasm linear memory.

`NATIVE_FRAME` PNGs in `proof/` are the actual buffers painted by this run, never app assets.

```text
NATIVE_FRAME .../emberdeep-cold.png 1000x700
COLD_LOAD_MS 295.6101894378662 no warm define; fixture=ticks begin after first capture
ROOT_POINTER FOCUS LIVE WORLD child=480.0,330.0 transformed=382.0,292.9375
INPUT_RELEASE move+kick passed x0=192 held=206 released_position=206
NATIVE_FRAME .../emberdeep-played.png 1000x700
INPUT_RELEASE pointer cast/stop passed 00 KILLS  /  007 CASTS
ROOT_POINTER PAUSE child=1080.0,788.0 transformed=813.25,622.125
NATIVE_FRAME .../emberdeep-paused.png 1000x700
ROOT_POINTER RESUME child=1080.0,788.0 transformed=813.25,622.125
ROOT_POINTER WAND 02 child=334.0,652.0 transformed=277.0625,524.375
WAND_AFTER PICKAXE EQUIPPED
NATIVE_FRAME .../emberdeep-death.png 1000x700
NATURAL_DEATH host_frames=240
ROOT_POINTER DESCEND AGAIN child=472.0,426.0 transformed=376.25,361.9375
NATIVE_FRAME .../emberdeep-restart.png 1000x700
NATIVE_EMBERDEEP_PASS move/kick/release/LMB/pause/wand/natural-death/transformed-restart; ticks=493
NATIVE_FRAME .../interaction-direct-cold.png 1280x816
NATIVE_FRAME .../interaction-direct-played.png 1280x816
NATIVE_DIRECT_DISPLAY_PASS actual zero-offset 1280x816 cold and key/pointer play; host_frames=169
```

What the assertions actually prove:

1. A real root click focused the child. Holding **D+F** moved the delver **192→206** and emitted `KICK / IMPACT 01`; after root key-up the key was absent and position stayed **206** through another 30 frames.
2. Holding root LMB over the transformed canvas caused **7 casts**; a further 45 frames after real pointer-up did not change the cast counter. This found and fixed nested pointer-state handling in the app: canvas `evPointerDown`/`evPointerUp` latch fire; no engine edit was needed.
3. Native transformed Pause/Resume clicks stopped/resumed the material simulation; native wand 02 produced `PICKAXE EQUIPPED`. This caught a shared loop closure and now each button owns a closure factory value.
4. With no memory/hp edits, the actual combat/controller killed the idle delver. The death says **SLAIN · GNAWLER bit you**. The transformed native **DESCEND AGAIN** button reset to seed **20261030** and x **192**.
5. The child contains exactly five `nkSynth` nodes. This is not an audible-speaker claim: the proof ran native/headless without opening a speaker.

## Direct math and long simulation — separate from native UI

Unchanged original 105-check file:

```sh
nim c -r --nimCache:/tmp/ember-premiere-math-final yantra-os/apps/emberdeep/tests/t_emberdeep.nim
# 105 passed, 0 failed
```

That includes exact table digest `0x978a1a39c4937758`, world hash `0xe67b61ea7cb77b9d`, 40-creature census, density counts/centroids, movement numbers, spell arithmetic and 230/16 lighting. Presentation exposure changes only final RGB output; those light-buffer assertions and all simulation checks still pass.

`tests/t_deep_simulation.nim` is explicitly a **direct fixture**, not a native-control demonstration:

```sh
nim c -r --nimCache:/tmp/ember-premiere-deep-sim-final yantra-os/apps/emberdeep/tests/t_deep_simulation.nim
# 9 passed, 0 failed
```

It compares two runs of the same scripted controller and pins **actual measured** results: grid `0x6ed0eb17275bc2cc`, frame `0xb8a6067f6078c819`, 1,331 ticks, depth 417, 84 casts, `kill`. Position/HP setup in the fourth sanctuary and bottom boss fixture is labeled as such. It verifies a real choice/perk mutation, the actual 720 HP `ctWellseye` in the final arena and its victory transition. Unattended simulation reached `kill`, 0 HP, at exactly 438 ticks. No all-material or all-creature claim is attached to these tests.

## Full-size visual review

`proof/direct-cold.png` and `proof/direct-played.png` are zero-offset `start(app.wasm, 1280, 816, 1)` paint buffers, not resized 1000×700 images. The played frame follows 169 real host frames of explicit focus, D+F, key-up, pointer-down, pointer-up and two settling ticks; it is not an autonomous warmup or a cover image.

The visual pass raises functional labels from 8–10 px to 11–12 px and the active wand to 15 px; right-aligns meter text using its real **700** font weight; uses bounded shared-width spell cards; and strengthens help/survey/status contrast. Biome/depth spacing and viewport/toast hierarchy were reviewed in the actual full-size frame. Rail and text compounds are SDK `Draw` commands, not UI screenshots.

World display changes are only final RGB: a restrained non-emissive material lift and material-colour floor retain terrain silhouettes without lifting black air or changing the light buffer. This deliberately changes the framebuffer expectation to `0xb8a6067f6078c819`; **105 original assertions are byte-unchanged**, and the deep fixture keeps all 9 assertions while pinning the review-approved display hash. Grid hash, ticks, depth, casts and natural death tick remain exact.

Chooser coverage remains the explicitly separated direct sanctuary/perk fixture. A bounded simple-controller descent research attempt failed and is not included as a native chooser/end-to-end gameplay pass, nor were physics edited to manufacture one. Actual desktop catalog/maximize review remains with the root integration lane; these images prove the actual 1280 app and transformed native AppView, not a claimed root-shell maximize.

## Publication hygiene

Only Nim, JSON, Markdown, the cold `.wasm`, and native proof PNGs are here. Generated libc objects, Nim caches, native test executables, original JS/source dumps, Node/Python comparison tooling, and reference art are excluded. The parent owns desktop-catalog integration; this lane changes no shared renderer, keyboard, viewport, desktop catalog, or engine test files.
