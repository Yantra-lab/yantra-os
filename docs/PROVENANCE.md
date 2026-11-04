# Provenance of the binaries in this tree

Every `.wasm` in `apps/` is **prebuilt** — shipped so verification runs with no toolchain and
no keys. Measured 2026-11-05 (UTC) in `/home/ubuntu/yantra/yantra-os`; re-run the commands
below rather than trusting this file.

## Re-measure

```bash
cd /home/ubuntu/yantra/yantra-os
sha256sum apps/*/*.wasm        # the provenance anchor
stat -c '%n %s' apps/*/*.wasm  # byte size
find . \( -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.exe' \
        -o -name '*.dylib' -o -name '*.o' -o -name '*.lib' \) -print
```

## The 11 app modules

Each is `apps/<name>/app.nim` compiled by `tools/build-wasm.sh`, using the command its own
usage line documents:

```bash
./tools/build-wasm.sh apps/<name>/app.nim apps/<name>/app.wasm --release
```

| Module | Built from | Bytes | sha256 |
|---|---|---|---|
| `apps/calc/app.wasm` | `apps/calc/app.nim` | 404142 | `54c7099be96111169106103bc6c63983aa490f974be23bf021c3810d8e46a9f6` |
| `apps/chess/app.wasm` | `apps/chess/app.nim` (+ `engine.nim`, `play.nim`, `perft.nim`) | 577770 | `42eb5aafbd2f13134f5c334bd90ae0ff04e03a2c465000ac9b70fc6a3fad58f2` |
| `apps/desktop/app.wasm` | `apps/desktop/app.nim` (+ `catalog.nim`, `config.nim`, `settings.nim`, `state.nim`, `tiling.nim`, `ui.nim`) | 2186434 | `1aa7f695f62d411cb9a44e5f9978e11c6681e658dadbb70124b1d1bb0e71d150` |
| `apps/dna/app.wasm` | `apps/dna/app.nim` | 416112 | `a9ccbdab927234485f945f1cfe5467ce6ebb8f8b7f96b58ae2b80f7f52fb1007` |
| `apps/editor/app.wasm` | `apps/editor/app.nim` | 353828 | `9938af9b67d2587432262bcf68d1c0888e93671c2eda3ea9fb34e1ac6bef0aca` |
| `apps/files/app.wasm` | `apps/files/app.nim` | 302539 | `4340f003ce21c07bb5a81ed97b031529fbbe2060239955b16871ace2aeb15b2d` |
| `apps/gallery/app.wasm` | `apps/gallery/app.nim` | 545597 | `aedd16818f6746d5dc84a366534bd85a52013f4b51d54053bed81550d83c6e16` |
| `apps/notes/app.wasm` | `apps/notes/app.nim` | 350099 | `0fb49f565fd4fa790b5f8aa022b55804aa72d9bb7d17fb30591c66296be4fac7` |
| `apps/todo/app.wasm` | `apps/todo/app.nim` | 348770 | `c952db27a3fe9841bcd7c530d45528a933105495162375c185dee5fb1628e59f` |
| `apps/typewriter/app.wasm` | `apps/typewriter/app.nim` | 500748 | `65cbb33c146f44d0a6a3b225f9da698344a073b711cb0d9729e980300bc0a413` |
| `apps/desktop/desktop.wasm` | see below — **not** produced by any command in this tree | 753756 | `65ece67db09719a5fb1cbcfbe90c6f406177567ee4fa5cab5491df67e274aaa0` |

**`apps/desktop/desktop.wasm` has unclear origin.** It is an earlier build of the same app
(18 imports / 1571 exports against `app.wasm`'s 22 / 3855); no command in this tree writes it
and nothing loads it (`run.sh`, `run_yantra.sh` and `tools/verify-wasm.mjs` use `app.wasm`) —
its only mention is `host/t_contract.nim:6,232-234`, which instantiates a path from
`$YANTRA_DESKTOP_WASM`. It is a contract fixture, not the desktop app: **keep it only as
that, otherwise propose deletion** (753,756 bytes of dead weight).

The modules are prebuilt, so the tree cannot prove the flags that built them (they carry a
`name` custom section, no `producers` section, and `wasm-opt` is optional — its absence is
explicitly not an error). Rebuilding also needs the private repo's toolchain: `third_party/`
is gitignored and absent, and there is no `wasi-sdk`, no `msys64` and no `nim` on `PATH` here.

## Every other binary-ish file

* `apps/desktop/minilibc.o` (19214 B) — **build debris**: a wasm32 object at exactly the path `tools/build-wasm.sh:87-91` writes when it compiles `sdk/minilibc/minilibc.c` (gitignored). **Propose deletion.**
* `apps/typewriter/{bell,key,paper,return,soft,space}.wav` (149984 / 7982 / 66194 / 52964 / 7100 / 10628 B) — **committed audio assets used by `apps/typewriter`**: `app.nim:1844-1849` loads all six by name through `env.y_sound_load` and the host reads them from this folder (RIFF/WAVE, 16-bit mono 44.1 kHz, no metadata chunk, no generator script in the tree). **Keep; the origin of the samples is not documented.**
* `proof_calc.png` and `proof_calc_keys.png` (19467 B each) — **byte-identical**, `sha256 9d1214151432130783085f826681fd20afee50a745e62b451312cb90e3952df5`: one 1440x900 calculator screenshot committed twice and referenced by nothing. **Keep one, delete the other.**
* `yantra-desktop.png` (930928), `yantra-files-nim.png` (93319), `yantra-files-json.png` (42405) — 1440x900 screenshots of the running desktop and file manager. **Unclear origin**: they were captured by the native host, whose binary is not in this tree, and no file references them.
* `assets/brand/yantra-icon.png` (1091923) — brand icon, read as an input by `tools/make-icon.mjs` and `tools/build-all.sh`. **Keep** (the author's own asset).
* `assets/brand/yantra-os-hero.png` (1555014) — unreferenced (the README uses `docs/assets/hero-banner.png`). **Keep or drop; not load-bearing.**
* `docs/assets/*.png` — `hero-banner.png` (3046969), `architecture-stack.png` (3085662), `comparison-infographic.png` (3198353), `event-loop-flowchart.png` (2755251), `pipeline-infographic.png` (2318286), `film-poster.png` (597366): all six are embedded by `README.md`. **Keep**; no generator in the tree, so they cannot be reproduced here.
* `scratch/` — `single_notes.png`, `twotabs.png`, `twotabs_ednotes.png`, `twotabs_notesfront.png`, `twotabs_notesfront2.png`, `twotabs_probe.png`, `twotabs_tiled.png` (1440x900 host captures), `twotabs_probe.ppm` (3072016 B, a raw 1280x800 framebuffer dump of the same probe), plus `twotabs_probe.nim` and `pxstats.py`: referenced by nothing, and `RELEASE.md` promises "no scratch debris". **Propose deleting the folder.**

## After the release pass (2026-11-05, later the same day)

The observations above were made against the tree as submitted. What changed since, and
what a reader should expect to find now:

* `README.md` and `apps/README.md` are **generated** by `bash tools/os-measure.sh --write`
  and checked by `--check`, so the "356 KB" and "desktop 753 KB" figures are gone. Every
  number in them is measured; the generator is in `tools/os-measure.mjs`.
* `tools/verify-wasm.mjs` no longer prints a constant "155/155 rounds matched": it prints
  the size, the sha256, the instantiation time and the node census it measured, and says
  in words that it does not render.
* `apps/desktop/desktop.wasm` (753,756 B) is **deleted**: nothing in this tree loads it.
* `apps/desktop/minilibc.o` is **deleted** (build debris).
* `scratch/` is **deleted** (7 PNG, one 3 MB PPM, two source files, referenced by nothing).
* `proof_calc.png` is **moved** to `docs/img/legacy/proof_calc.png`; its byte-identical
  twin `proof_calc_keys.png` is deleted. `yantra-desktop.png`, `yantra-files-nim.png` and
  `yantra-files-json.png` are **moved** to `docs/img/legacy/` (their origin is still the
  native host, which this tree does not contain). The five screenshots that a committed
  script can reproduce are in `docs/img/` and are described in `docs/img/CAPTURE.md`.
* `yoga/` is **deleted**: three of its four files were 100 % NUL bytes. The intact wrapper
  is `libs/nimyoga/src/nimyoga.nim`; `yoga/README.md` survives as
  `libs/nimyoga/README-legacy-top-level-copy.md`.
* `apps/*/panicoverride.nim` (ten identical 722 B copies, generated by
  `tools/build-wasm.sh`) are **deleted**.
* `YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md` is **moved** to
  `docs/context/IMPLEMENTATION-BUNDLE.md`.

## Tracking: fixed

The caveat above — that all eleven `.wasm` were gitignored by the parent repo and would
have been silently left out of a subtree publish — is **fixed in `yantra-os/.gitignore`**,
which now re-includes exactly the release artifacts:

```
!apps/*/app.wasm
!apps/*/desktop.wasm
!apps/*/*.wav
```

Verify with `git check-ignore -v yantra-os/apps/calc/app.wasm`, which now reports the
negation pattern rather than the parent's `*.wasm`.
