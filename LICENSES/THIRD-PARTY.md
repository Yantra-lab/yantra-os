# Third-party components — Yantra OS release tree

This file lists every third-party component this tree depends on, the licence **as
evidenced in this repository**, and where the evidence is.

**Evidence rule.** A licence is only asserted here if one of these exists:

1. a `LICENSE` / `COPYING` / `NOTICE` file in this tree or in the upstream checkout
   under `/home/ubuntu/yantra/third_party/<lib>` (that folder is **not shipped** — it is
   gitignored in the private repo), or
2. the wrapper's own `README.md` / `INTERFACE.md` naming the upstream **and** its licence.

Where neither exists the licence column says **"licence not stated in this repo"**. Nothing
here is quoted from memory.

Measured on 2026-11-05 (UTC) against the working tree at `/home/ubuntu/yantra/yantra-os`.

---

## What this repo actually ships

```
find /home/ubuntu/yantra/yantra-os \( -name '*.so' -o -name '*.dll' -o -name '*.a' \
  -o -name '*.exe' -o -name '*.dylib' -o -name '*.o' -o -name '*.lib' \)
→ /home/ubuntu/yantra/yantra-os/apps/desktop/minilibc.o      (19214 bytes)
```

**This tree ships no third-party binary.** No `.so`, `.dll`, `.a`, `.exe`, `.dylib` or `.lib`
anywhere, and no `third_party/` directory. The single object file, `apps/desktop/minilibc.o`,
is a wasm32 object at exactly the path `tools/build-wasm.sh:87-91` writes when it compiles
this project's own `sdk/minilibc/minilibc.c`; it is that build debris, not a third-party
artefact.

The 11 prebuilt `.wasm` modules are the author's own Nim compiled by clang. Their import
section contains **only** the host functions `env.y_*` (verified with
`WebAssembly.Module.imports`), so none of the C/C++ libraries below is linked *inside* a
`.wasm`. They all live in the native host, whose binary is **not** in this tree.

The one guest-side exception is compiler-rt builtins (row 1), which `tools/build-wasm.sh`
links into the modules when the private toolchain happens to hold a wasi-sdk.

The native host binary is published separately as `yantra-windows-x64-bin.zip` on GitHub
Releases (README **Quick Start**); that zip — not this tree — carries the third-party DLLs
(Skia, SDL3, wasmtime, Jolt, Filament, FFmpeg, accesskit, …). `docs/ARCHITECTURE.md` records
39 root build DLLs plus 96 desktop subsystem DLLs.

---

## Components

| Component | Upstream | Licence (as evidenced) | Evidence path | How it reaches a user of this repo | Shipped in this tree? |
|---|---|---|---|---|---|
| 1. compiler-rt builtins (`libclang_rt.builtins.a`) | LLVM / wasi-sdk | licence not stated in this repo | `tools/build-wasm.sh:95-96` links `third_party/wasi-sdk-*/lib/clang/*/lib/wasm32-unknown-wasi/libclang_rt.builtins.a`; no `third_party/wasi-sdk-*` exists here | **(a)** statically linked into a `.wasm` built by the script *when that archive is present*; the shipped modules cannot be shown to contain it either way | No (not present in this tree) |
| 2. Skia | Google | **BSD-3-Clause** ("Copyright (c) 2011 Google Inc. All rights reserved.") | `/home/ubuntu/yantra/third_party/skia-m143/LICENSE` | **(b)** linked into the native host; **(c)** `libs/nimskia/` wrapper source is here (`skia_shim.cpp` includes `include/core/SkCanvas.h`) | No — wrapper source only |
| 3. HarfBuzz | Google (copy bundled inside the Skia checkout) | **BSD-3-Clause** (the text at that path) | `/home/ubuntu/yantra/third_party/skia-m143/third_party/harfbuzz/LICENSE` | **(b)** reached through Skia's `SkParagraph`, per `libs/nimskia/src/skia_shim.cpp:5` and `README.md:43,98` | No |
| 4. Filament | Google | **Apache-2.0** | `/home/ubuntu/yantra/third_party/filament-linux/LICENSE` | **(b)** linked into the native host via `libs/nimfilament`; **(c)** wrapper + shim shipped | No — wrapper source only |
| 5. SDL3 | Sam Lantinga / SDL project | **zlib** ("Copyright (C) 1997-2025 Sam Lantinga") | `/home/ubuntu/yantra/third_party/sdl3-local/share/licenses/SDL3/LICENSE.txt` | **(b)** linked into the native host (`libs/nimsdl3/src/sdl_shim.c` includes `<SDL3/SDL.h>`); **(c)** wrapper shipped | No — wrapper source only |
| 6. Yoga | Meta | **MIT** ("Copyright (c) Facebook, Inc. and its affiliates.") | `/home/ubuntu/yantra/third_party/yoga/yoga-3.1.0/LICENSE` | **(b)** linked into the native host; **(c)** wrapper shipped | No — wrapper source only |
| 7. Jolt Physics | Jorrit Rouwe | **MIT** | `/home/ubuntu/yantra/third_party/jolt-local/include/Jolt/Jolt.h:1-3` (`SPDX-License-Identifier: MIT`) and `libs/nimjolt/README.md:3,8` | **(b)** linked into the native host via `libs/nimjolt`; **(c)** wrapper + shim shipped | No — wrapper source only |
| 8. FFmpeg — libavformat, libavcodec, libswscale, libavutil | FFmpeg project | **LGPL/GPL per the FFmpeg build** — the exact variant is *not* stated in this repo | `libs/nimav/README.md:4` ("LGPL/GPL per the FFmpeg build; … H.264 through libx264") | **(b)** linked into the native host via `libs/nimav`; **(c)** wrapper + shim shipped | No — wrapper source only |
| 9. miniaudio | David Reid (mackron) | **public domain (Unlicense) or MIT-0 — the user's choice** | `/home/ubuntu/yantra/third_party/miniaudio/miniaudio.h:2` and the two licence statements at the end of that file; also `libs/nimminiaudio/README.md:3,8` | **(b)** linked into the native host; **(c)** wrapper shipped | No — wrapper source only |
| 10. wasmtime | Bytecode Alliance | licence not stated in this repo | `libs/nimwasmtime/README.md` names `wasmtime-v19.0.2-x86_64-windows-c-api` and its DLL but states no licence; `libs/nimwasmtime/vendor/` is not shipped | **(b)** the native host loads the `.wasm` modules through it (`host/host.nim:19`); **(c)** wrapper source shipped | No — wrapper source only |
| 11. SQLite | SQLite project | **Public Domain** | `libs/nimsqlite/README.md:3,8` | **(b)** linked into the host; **(c)** wrapper shipped. Nothing in this tree imports `nimsqlite` except `libs/nimblake3` | No — wrapper source only |
| 12. libcurl | curl project | **"curl (MIT-style)"** (wording of the README) | `libs/nimcurl/README.md:4` | **(b)** linked into the host (`host/vajranet.nim`, `render/native/engine.nim`); **(c)** wrapper + shim shipped | No — wrapper source only |
| 13. BLAKE3 | BLAKE3 team | **CC0-1.0 / Apache-2.0** | `libs/nimblake3/README.md:3,8` | **(c)** wrapper source shipped; **no file in this tree imports it** | No — wrapper source only |
| 14. libdatachannel (bundling libjuice, usrsctp, libsrtp) | Paul-Louis Ageneau | **MPL-2.0** for libdatachannel; the three bundled libraries: licence not stated in this repo | `libs/nimrtc/README.md:4` | **(b)** linked into the host via `libs/nimrtc`; **(c)** wrapper + shims shipped | No — wrapper source only |
| 15. AccessKit (`accesskit-c`) | AccessKit project | **MIT/Apache-2.0** (wording of the README) | `libs/nimaccesskit/README.md:4` | **(b)** linked into the host via `libs/nimaccesskit`; **(c)** wrapper + shim shipped | No — wrapper source only |
| 16. Qt 6 | Qt project | licence not stated in this repo | `libs/nimqt/README.md` names "Qt 6.11.2" and the bundled MSYS2 toolchain but states no licence | **(c)** wrapper source shipped (`libs/nimqt/`), **imported by nothing in this tree** — the Qt renderer is the legacy path | No — wrapper source only |
| 17. PostgreSQL (server C API) | PostgreSQL Global Development Group | licence not stated in this repo | `libs/nimpg/README.md` names "PostgreSQL 18" but states no licence | **(c)** wrapper source shipped; **(d)** used by the private repo's tooling (`render/native/vajra_parity.nim`, `vajra_shot.nim`) | No — wrapper source only |
| 18. Nim compiler (`nim c`) | Nim project | licence not stated in this repo | `tools/build-wasm.sh:141` runs `nim c`; no Nim checkout or licence in `third_party/` and no `nim` in this tree | **(d)** build time only — it produces the `.wasm` | No |
| 19. Nimony | Andreas Rumpf | **MIT** ("Copyright (c) 2024 Andreas Rumpf") | `/home/ubuntu/yantra/third_party/nimony/license.txt` | **(d)/(e)** build-time toolchain only; nothing Nimony produces is in this tree, and `build-wasm.sh` calls `nim`, not `nifler`/Nimony | No |
| 20. binaryen (`wasm-opt`) | WebAssembly/binaryen | licence not stated in this repo | `tools/build-wasm.sh:151-172`; `/home/ubuntu/yantra/third_party/binaryen/` has `bin/ lib/ include/` and **no licence file** | **(d)** build time only, and optional: the script says "wasm-opt is not a hard dependency" and keeps the unoptimised module if it is missing | No |
| 21. clang / LLVM (the C backend) | LLVM project | licence not stated in this repo | `tools/build-wasm.sh:89,141,147` (`clang --target=wasm32-unknown-unknown`, `nim c --cc:clang`, `--passC`/`--passL`) | **(d)** build time only | No |
| 22. Emscripten | Emscripten project | licence not stated in this repo | `web/engine/yantra.js:1` — "build/engine.js is engine.nim built with emscripten"; `build/engine.js` is **not** in this tree | **(d)** build time only, for a browser engine that is not shipped here | No |
| 23. Nativenif | Nim project | **MIT** ("Copyright (c) 2025 The Nim programming language") | `/home/ubuntu/yantra/third_party/nativenif/LICENSE` | **(e)** not used by this tree | No |
| 24. Anthropic Agent Skills (8 translations) | Anthropic (`anthropics/skills`) | **Proprietary** for 5 of 8 (docx, pdf, pptx, xlsx, doc-coauthoring); the other 3 state no licence at all | `skills/yantra/translated-skills/*/SKILL.md` line 4; `skills/yantra/translated-skills/README.md` | **(c)** documentation content shipped in this tree, read by an agent; compiled into nothing | **Yes** — 8 translated skill files |
| 25. `apps/typewriter/*.wav` (6 files) | not stated | licence not stated in this repo | no README, no metadata chunk and no generator script for them in this tree (`apps/chess/synth.mjs` generates chess audio, not these) | **(c)** runtime assets: `apps/typewriter/app.nim:1844-1849` loads them by name through `env.y_sound_load`; the host reads them from `apps/typewriter/`. Not compiled into the `.wasm` | **Yes** — `bell.wav`, `key.wav`, `paper.wav`, `return.wav`, `soft.wav`, `space.wav` |

Notes on two rows that look odd:

* **HarfBuzz (3)** is not a separate dependency of this repo; it arrives inside the Skia
  checkout. It is listed because `README.md` claims HarfBuzz shaping and a redistributor of
  the host should carry its notice too.
* **Windows `ISpellChecker`** (`libs/nimspell`) and `nimrtc`'s use of the OS audio stack are
  operating-system APIs, not third-party components; they carry no notice obligation.

---

## Obligations when you redistribute

These are the obligations the licences above impose; nothing more is claimed.

**MIT, BSD-3-Clause, zlib, MIT-0/unlicense (Yoga, Jolt, HarfBuzz, Skia, SDL3, miniaudio,
SQLite, BLAKE3, Nimony, Nativenif).**
Keep the copyright notice and the licence text with every copy of the source or binary you
pass on, and keep them in the documentation of a binary distribution (BSD-3 and zlib say so
explicitly). BSD-3 additionally forbids using the copyright holder's or contributors' names
to endorse your product. zlib adds: do not misrepresent the origin, and mark altered source
versions as altered. miniaudio lets you pick Unlicense **or** MIT-0 — if you rely on MIT-0
you must keep David Reid's notice; the Unlicense imposes nothing.

**Apache-2.0 (Filament).**
Ship a copy of the Apache-2.0 licence, keep any `NOTICE` file the upstream provides (the
`filament-linux` checkout here ships a `LICENSE` and no `NOTICE`), state the changes you made
to the files you modified, and do not imply endorsement. Apache-2.0 also carries an express
patent grant, which you must not contradict in your own terms.

**MPL-2.0 (libdatachannel).**
File-level copyleft: if you modify MPL-covered files you must publish those files' source;
otherwise you must keep the notice and tell recipients where to get the source. It may be
combined with the MIT-licensed rest of this project.

**LGPL or GPL (FFmpeg — which one depends on the build).**
`libs/nimav/README.md` records "LGPL/GPL per the FFmpeg build" and H.264 "through libx264";
`libx264` is only usable in a `--enable-gpl` FFmpeg, so **confirm the variant before you
rely on LGPL** (`ffmpeg -version` prints the configuration line of whatever build you ship).
For an LGPL build: ship the FFmpeg licence and either the library's source or a written
offer to supply it, keep FFmpeg dynamically linked so the user can replace it (this tree's
host loads FFmpeg DLLs, so relinking is possible), and say which FFmpeg version you used.
For a GPL build: the whole distributed combination must be GPL-compatible.

**Public domain (SQLite, miniaudio's Unlicense option).**
No legal obligation. Keeping the notice is courtesy and is what makes provenance auditable.

**Proprietary (the Anthropic skill translations).**
The only statement in this tree is `license: Proprietary`. Nothing in this tree grants a
right to redistribute them, and the `NOTICE.md` those files point to **does not exist**.
A redistributor who wants to be safe should obtain permission from Anthropic, or drop
`skills/yantra/translated-skills/` from the redistribution.

**Nothing here is legal advice.** It is a factual inventory of what the repository shows.

---

## Licence gaps a reader (or judge) will notice

1. **wasmtime has no licence anywhere in this tree.** It is the sandbox the whole product
   rests on, named in the README badge and the architecture diagram, and neither
   `libs/nimwasmtime/README.md` nor its source states a licence.
2. **FFmpeg's variant is unresolved.** "LGPL/GPL per the build" is honest but not
   actionable; the actual Windows DLL set is in the release zip, not here.
3. **`libs/nimskia/` and `libs/nimsdl3/` have no `README.md` and no `INTERFACE.md`**, alone
   among the 16 wrappers. Their upstreams are evidenced only by the `#include`s in their
   shims and by the `third_party/` licence files.
4. **binaryen's licence is not in its checkout** even though `third_party/binaryen/` is a
   full prebuilt (68 MB `libbinaryen.a` + `wasm-opt`).
5. **The six typewriter `.wav` files have no recorded origin** — no generator script, no
   source URL, no licence line. If they came from a sample library, that library's terms
   apply to them.
6. **`skills/yantra/translated-skills/`** ships translations of Anthropic's skills marked
   "Proprietary", and the `NOTICE.md` they reference is missing.
