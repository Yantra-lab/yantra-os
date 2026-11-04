# Licences that are not in this repository — named gaps, not guessed text

Provenance: `docs/iitm/LICENSE-AUDIT.md` §4, measured 2026-11-06 on this tree.

No licence text is invented here. Each row is a component that reaches a user but states no
licence anywhere in this repository; the last column is the path that should hold the text.

| Component | Why it matters | Where its licence text should come from |
| :--- | :--- | :--- |
| FFmpeg (`libav*`, `libsw*`) | the variant is proven from the binaries (GPL-3.0-or-later on Windows, GPL-2.0-or-later on Linux) but the text is absent | `third_party/ffmpeg-local/` holds no `LICENSE`/`COPYING` |
| x264 | `--enable-libx264` is what forces `--enable-gpl` on the Linux build | upstream `x264/COPYING` |
| libjuice / usrsctp / libsrtp | bundled inside libdatachannel (MPL-2.0 itself is stated) | each library's own `LICENSE` |
| compiler-rt builtins | linked into the `.wasm` when the wasi-sdk archive is present | `third_party/wasi-sdk-*/LICENSE.TXT` |
| wasmtime | the sandbox every app runs in | `vendor/` is not shipped; upstream `LICENSE` |
| Qt 6 | legacy renderer, imported by nothing | `libs/nimqt/README.md` names no licence file |
| PostgreSQL | private-repo tooling only | upstream `COPYRIGHT` |
| Nim compiler | build time only | upstream `copying.txt` |
| binaryen (`wasm-opt`) | build time, optional | `third_party/binaryen/` has no licence file |
| clang / LLVM | build time only | upstream `LICENSE.TXT` |
| Emscripten | build time; browser engine not shipped | upstream `LICENSE` |
| typewriter sound assets — 20 `.wav`, 367,666 B | runtime audio, no generator and no source URL | `assets/typewriter/sfx/` provenance note |
| Anthropic Agent Skills (8 translations) | 5 of 8 are proprietary; the `NOTICE.md` they point at does not exist | `skills/yantra/translated-skills/*/NOTICE.md` |

A missing licence text is a stated gap. A fabricated notice would be a defect.
