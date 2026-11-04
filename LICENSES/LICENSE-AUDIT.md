# Third-party licence audit — Yantra OS

Prepared 2026-11-06 (UTC) for the IITM Venture Studio evaluation, in answer to the written
request for *"software bill of materials (SBOM) and third-party license audit — specifically
outlining commercial compliance and linking/distribution terms for LGPL/GPL dependencies such
as FFmpeg"*.

Companion file: [`SBOM.cdx.json`](SBOM.cdx.json) — CycloneDX 1.6, 54 components, validated
against the official `bom-1.6.schema.json` (0 errors).

**Evidence rule.** A licence is asserted here only if (a) a `LICENSE` / `COPYING` / `NOTICE`
file exists in the repo, (b) a wrapper `README.md` names the upstream **and** its licence, or
(c) the shipped binary states it itself in its own strings — which for FFmpeg it does. Where
none of these hold, the row says **"licence not stated in this repo"**. Nothing here is quoted
from memory. Two roots are used, and they are not the same tree:

| Alias | Absolute path | Shipped? |
|---|---|---|
| `yantra-os/…` | `/home/ubuntu/yantra/yantra-os/…` | **yes** — the public release tree |
| `third_party/…`, `libs/…` | `/home/ubuntu/yantra/third_party/…`, `/home/ubuntu/yantra/libs/…` | no — gitignored build inputs |

One trap worth naming: `THIRD-PARTY.md`'s bare `libs/*/README.md` citations mean
**`yantra-os/libs/`**, not the root `libs/` — e.g. `libs/nimqt/README.md` exists only there.
Every citation below is written with its root spelled out for that reason.

---

## 1. The FFmpeg verdict, resolved by measurement

`yantra-os/libs/nimav/README.md:4` says only *"LGPL/GPL per the FFmpeg build … H.264 through libx264"*.
That is now resolved: **neither artifact is LGPL.** Both are GPL, and they are different GPLs.

| Artifact | Where it lives | Version | Size (bytes) | SHA-256 | Licence (measured) | What it forces on a redistributor |
|---|---|---|---|---|---|---|
| `libavutil.so.59.39.100` | `third_party/ffmpeg-local/lib/` | 59.39.100 | 1,022,248 | `d5f4d6290cb27040a9aef8f02317fbe889480e8c057997a70971b8d3ea49f6b5` | **GPL-2.0-or-later** | GPL terms on the combination |
| `libavcodec.so.61.19.101` | ″ | 61.19.101 | 17,432,512 | `6c250767c86d64818420e96a0e35a62a059805c349cde2deaa9d13e95335d62e` | **GPL-2.0-or-later** | ″ |
| `libavformat.so.61.7.100` | ″ | 61.7.100 | 2,725,136 | `fb7381e40fef8e5c8791b71f88d8f5e9caa8de06dd82d4c93521c288b545d7ed` | **GPL-2.0-or-later** | ″ |
| `libavdevice.so.61.3.100` | ″ | 61.3.100 | 82,128 | `b777e85cb80c2db808177910c06f2ac9d8b91558d6f2970bab8a3d09955017f4` | **GPL-2.0-or-later** | ″ |
| `libavfilter.so.10.4.100` | ″ | 10.4.100 | 4,543,664 | `55ea1e21fdc5e52de0aa595714d28842fd466705b58015758cb214ece0333944` | **GPL-2.0-or-later** | ″ |
| `libswscale.so.8.3.100` | ″ | 8.3.100 | 616,696 | `6b1e9af4e443e52dedbf0ee549247dc0397f49566c7de7ce7c2b17f7ce70ae6c` | **GPL-2.0-or-later** | ″ |
| `libswresample.so.5.3.100` | ″ | 5.3.100 | 125,008 | `e446f03ba9748a294a8a72e30ad771fa98ed98e508230f882224e78de874b957` | **GPL-2.0-or-later** | ″ |
| `libpostproc.so.58.3.100` | ″ | 58.3.100 | 75,704 | `743a33c6333a91ecb45af641e19ed4420260d8351e640dc5476264a44b336a92` | **GPL-2.0-or-later** | ″ |
| `avutil-61.dll` | `yantra-windows-x64-bin.zip` | unknown (major 61) | 1,304,143 | `d7aa04871268b32663372da2effbe9113aa259a8c312fec5335961d38f1f416e` | **GPL-3.0-or-later** | GPL-3 terms on the combination |
| `avcodec-63.dll` | ″ | unknown (major 63) | 20,633,533 | `5bb6988b6785ccc17d7f93a14ec950b08872623c9e7a74f00f1ceab4f4335877` | **GPL-3.0-or-later** | ″ |
| `avformat-63.dll` | ″ | unknown (major 63) | 2,994,130 | `e3984fe1adfdcb61633faabb689a272408de9d099e0e0cda4098ceffe6b32fb5` | **GPL-3.0-or-later** | ″ |
| `avdevice-63.dll` | ″ | unknown (major 63) | 175,052 | `0672c4d72d29bda3a89780dfacf01c735d66184e2259834ca57aef9ae7781a97` | **GPL-3.0-or-later** | ″ |
| `avfilter-12.dll` | ″ | unknown (major 12) | 6,817,538 | `9c12497075beaef2ccea82644a5bad427cb51614ebc63a6cfa61a629d2cc614d` | **GPL-3.0-or-later** | ″ |
| `swscale-10.dll` | ″ | unknown (major 10) | 2,215,415 | `307a2fea736687f393bcd547633cce668263b5fbccdde6827e542276a12ebcc2` | **GPL-3.0-or-later** | ″ |
| `swresample-7.dll` | ″ | unknown (major 7) | 186,336 | `7fce416f089f72d5b7637b9a53288d596bc066ef50b8ea5785644b08f8e755fa` | **GPL-3.0-or-later** | ″ |

### The evidence, in two forms

**(i) Each library says its own licence in its own strings.** Nothing was inferred:

```
$ cd /home/ubuntu/yantra/third_party/ffmpeg-local/lib
$ for f in libav*.so.* libsw*.so.* libpostproc.so.*; do
    printf '%-28s ' "$f"; strings -a "$f" | grep -m1 'license: '; done
libavutil.so.59.39.100       libavutil license: GPL version 2 or later
libavcodec.so.61.19.101      libavcodec license: GPL version 2 or later
libavformat.so.61.7.100      libavformat license: GPL version 2 or later
libavfilter.so.10.4.100      libavfilter license: GPL version 2 or later
libavdevice.so.61.3.100      libavdevice license: GPL version 2 or later
libswscale.so.8.3.100        libswscale license: GPL version 2 or later
libswresample.so.5.3.100     libswresample license: GPL version 2 or later
libpostproc.so.58.3.100      libpostproc license: GPL version 2 or later
```

```
$ cd /tmp/wt-windows-dist-scratch/extracted        # entries unzipped from the release zip
$ for f in avutil-61.dll avcodec-63.dll avformat-63.dll avfilter-12.dll avdevice-63.dll \
           swscale-10.dll swresample-7.dll; do
    printf '%-18s ' "$f"; strings -a "$f" | grep -m1 'license: '; done
avutil-61.dll      libavutil license: GPL version 3 or later
avcodec-63.dll     libavcodec license: GPL version 3 or later
avformat-63.dll    libavformat license: GPL version 3 or later
avfilter-12.dll    libavfilter license: GPL version 3 or later
avdevice-63.dll    libavdevice license: GPL version 3 or later
swscale-10.dll     libswscale license: GPL version 3 or later
swresample-7.dll   libswresample license: GPL version 3 or later
```

**(ii) The build configuration strings agree, and show why.**

The Linux build — `strings libavutil.so.59.39.100 | grep -E '^--(enable|prefix)'`, and the same
line in all 8 libraries:

```
--prefix=/tmp/vajra-wt/third_party/ffmpeg-local --libdir=/tmp/vajra-wt/third_party/ffmpeg-local/lib
--shlibdir=/tmp/vajra-wt/third_party/ffmpeg-local/lib --incdir=/tmp/vajra-wt/third_party/ffmpeg-local/include
--enable-shared --disable-static --enable-pic --disable-doc --disable-debug --enable-gpl
--enable-libx264 --enable-libopus
--extra-cflags='-I/tmp/engine-build/x264-local/include -I/tmp/engine-build/opus-local/include'
--extra-ldflags='-L/tmp/engine-build/x264-local/lib -L/tmp/engine-build/opus-local/lib'
--extra-libs='-lm -lpthread'
```

`third_party/ffmpeg-local/bin/ffmpeg -version` reports `ffmpeg version 7.1.1`, `gcc 11 (Ubuntu
11.4.0-1ubuntu1~22.04.3)`, and the identical configuration line.

The Windows build — `strings avutil-61.dll | grep -E '^--(enable|prefix)'`, the same line in all
7 DLLs, abbreviated to the flags that decide the licence:

```
--prefix=/mingw64 --target-os=mingw32 --arch=x86_64 --cc=gcc --cxx=g++
--enable-gpl  …  --enable-version3  …  --enable-libx264 --enable-libx265 --enable-libvpx
--enable-libsvtav1 --enable-libaom --enable-libdav1d --enable-libopus --enable-shared
```
(the full line carries 59 `--enable-*` flags and is reproduced verbatim in the `SBOM.cdx.json`
property `build.configuration` on the component *FFmpeg (Windows shared build …)*.)

### Reading it

* `--enable-gpl` is what makes an FFmpeg build GPL instead of LGPL. Both builds have it.
* `--enable-version3` upgrades GPL v2-or-later to GPL v3-or-later. **Only the Windows build has
  it**, which is exactly why one says "version 2 or later" and the other "version 3 or later".
* `--enable-libx264` requires `--enable-gpl` (that is an FFmpeg build-system rule, not a repo
  fact — but it is corroborated here: `libx264` is named in `yantra-os/libs/nimav/README.md:4`
  as the H.264 encoder, and both measured builds carry `--enable-gpl`).
* **Correction to the earlier note, confirmed:** a previous investigation recorded a Windows
  `avutil-61.dll` built with `--enable-gpl --enable-version3` against a Linux build with
  `--enable-gpl --enable-libx264`. That is exactly what the files show, and the two builds are
  also *different FFmpeg generations*: Linux is 7.1.1 (`lavu 59 / lavc 61 / lavf 61 /
  lavfi 10 / swscale 8 / swresample 5`), while the Windows DLLs are `avutil 61 / avcodec 63 /
  avformat 63 / avfilter 12 / swscale 10 / swresample 7` — newer majors on every axis.

### What this means commercially

* **Yantra can sell and ship the Windows host, but the distributed combination is a GPL-3.0
  work.** Every recipient gets the right to the corresponding source of the GPL-3.0 parts
  (GPL-3 §6), plus the GPL-3 anti-tivoisation and patent terms. There is no proprietary-licence
  escape through FFmpeg here, because the build is GPL.
* **You must actually ship the licences, and today you do not.** The release archive contains
  **136 entries — 135 DLLs and `yantra.exe` — and not one licence, notice, readme or text file**:

  ```
  $ python3 -c "import zipfile;z=zipfile.ZipFile('yantra-windows-x64-bin.zip');\
    print(len(z.infolist()),[i.filename for i in z.infolist() if any(k in i.filename.lower() \
    for k in ('licen','copying','notice','readme','.txt','.md'))])"
  136 []
  ```
  That is a same-day fixable defect and the single cheapest thing to fix before the meeting.
* **FFmpeg is a linked library, not static, in both cases** (`--enable-shared`), so a user can
  replace it — which matters for LGPL relinking but is simply good practice under GPL.
* **The `.wasm` app modules are not part of that linked work.** Measured: all 12 modules import
  only from the `env` namespace — 29 distinct function imports, no WASI and no third-party wasm
  module — so the apps are separate files loaded at runtime by the host, not copies of GPL code:

  ```
  $ node -e '…WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync("apps/<app>/app.wasm")))…'
  modules: 12 | distinct import names: 29 | namespaces: env | kinds: function
  non-env.y_* : env.cos, env.nim_exit, env.nim_write, env.pow, env.sin, env.sqrt,
                env.sutra_location, env.sutra_navigated, env.sutra_now, env.sutra_param_value,
                env.sutra_query, env.sutra_take, env.sutra_utc_offset, env.yantra_log
  ```
  (This also corrects `yantra-os/docs/THIRD-PARTY.md:34-37`, which says the tree ships "the
  **11** prebuilt `.wasm` modules" and that their import section contains "**only** the host
  functions `env.y_*`". Measured: **12** `apps/*/app.wasm` modules, and 15 of the 29 imported
  names are `env.y_*` while the other 14 are also `env` host functions — libm wrappers, the Nim
  runtime and Sutra primitives. The conclusion stands; the two absolute claims did not.)
* Whether that separation is enough to keep your own app/front-end code out of the GPL
  combination is a legal question, not a measurement. **Get a lawyer's sentence on it before a
  commercial contract.** Everything above is fact, not advice.
* **A naming trap.** The binaries say *"GPL version 2 or later"* and *"GPL version 3 or later"*,
  so the SPDX names are `GPL-2.0-or-later` and `GPL-3.0-or-later`. There is no "GPL-2.1" —
  2.1 is an **LGPL** version number, and neither artifact here is LGPL. If someone asks "so are
  you LGPL-2.1?", the measured answer is no.

---

## 2. The other 24 components

Row numbers match `yantra-os/docs/THIRD-PARTY.md`, which this audit re-verified path-by-path
(every cited file was confirmed to exist on 2026-11-06).

| # | Component | Licence (as evidenced) | Evidence path | Reaches a user how? |
|---|---|---|---|---|
| 1 | compiler-rt builtins | licence not stated in this repo | `yantra-os/tools/build-wasm.sh:95-96`; no `third_party/wasi-sdk-*` exists | statically into a `.wasm`, when that archive is present |
| 2 | Skia (m143) | **BSD-3-Clause** | `third_party/skia-m143/LICENSE:1`; version `third_party/skia-m143/include/core/SkMilestone.h:8` = 143 | linked into the native host |
| 3 | HarfBuzz (inside the Skia checkout) | **BSD-3-Clause** | `third_party/skia-m143/third_party/harfbuzz/LICENSE:1` | through Skia's SkParagraph (`yantra-os/libs/nimskia/src/skia_shim.cpp:5-6`) |
| 4 | Filament (1.77.1) | **Apache-2.0** | `third_party/filament-linux/LICENSE:2`; version `yantra-os/libs/nimfilament/README.md:6` | linked into the native host |
| 5 | SDL3 (3.2.16) | **Zlib** | `third_party/sdl3-local/share/licenses/SDL3/LICENSE.txt:1`; version `…/include/SDL3/SDL_version.h:47,56,65` | linked into the native host |
| 6 | Yoga (3.1.0) | **MIT** | `third_party/yoga/yoga-3.1.0/LICENSE:1`; `yantra-os/libs/nimyoga/README.md:8` | linked into the native host |
| 7 | Jolt Physics (5.3.0) | **MIT** | `yantra-os/libs/nimjolt/README.md:3`; `third_party/jolt-local/include/Jolt/Jolt.h:1-3` | linked into the native host |
| 8 | **FFmpeg** | **GPL-2.0-or-later** (Linux build) / **GPL-3.0-or-later** (Windows build) | §1 above | linked into the native host |
| 9 | miniaudio (0.11.21) | **Unlicense _or_ MIT-0** (user's choice) | `third_party/miniaudio/miniaudio.h:2` + the two statements at the end of the file; `yantra-os/libs/nimminiaudio/README.md:3` | linked into the native host |
| 10 | wasmtime (19.0.2) | **licence not stated in this repo** | `yantra-os/libs/nimwasmtime/README.md:12`; `vendor/` not shipped | the sandbox every app runs in |
| 11 | SQLite (3.53.4) | **Public Domain** | `yantra-os/libs/nimsqlite/README.md:3,8` | linked into the host |
| 12 | libcurl | **curl (MIT-style)** | `yantra-os/libs/nimcurl/README.md:4` | linked into the host |
| 13 | BLAKE3 (1.8.7) | **CC0-1.0 / Apache-2.0** | `yantra-os/libs/nimblake3/README.md:3,8` | wrapper only; nothing imports it |
| 14 | libdatachannel (+ libjuice, usrsctp, libsrtp) | **MPL-2.0**; the three bundled libs: licence not stated in this repo | `yantra-os/libs/nimrtc/README.md:4` | linked into the host |
| 15 | AccessKit (accesskit-c) | **MIT/Apache-2.0** | `yantra-os/libs/nimaccesskit/README.md:4` | linked into the host |
| 16 | Qt 6 (6.11.2) | **licence not stated in this repo** | `yantra-os/libs/nimqt/README.md:31`; no licence file | legacy renderer; imported by nothing |
| 17 | PostgreSQL (18) | **licence not stated in this repo** | `yantra-os/libs/nimpg/README.md:19` | private-repo tooling only |
| 18 | Nim compiler | **licence not stated in this repo** | `yantra-os/tools/build-wasm.sh:141` | build time only |
| 19 | Nimony | **MIT** | `third_party/nimony/license.txt:1` | build time only |
| 20 | binaryen (`wasm-opt`) | **licence not stated in this repo** | `yantra-os/tools/build-wasm.sh:151-172`; `third_party/binaryen/` has no licence file | build time, optional |
| 21 | clang / LLVM | **licence not stated in this repo** | `yantra-os/tools/build-wasm.sh:89,141,147` | build time only |
| 22 | Emscripten | **licence not stated in this repo** | `web/engine/yantra.js:1` | build time, browser engine not shipped |
| 23 | Nativenif | **MIT** | `third_party/nativenif/LICENSE:1` | not used by this tree |
| 24 | Anthropic Agent Skills (8 translations) | **Proprietary** for 5 of 8; the rest state none | `skills/yantra/translated-skills/*/SKILL.md:4`; the referenced `NOTICE.md` is **missing** | docs content, compiled into nothing |
| 25 | Typewriter sound assets — **20** `.wav` files, 367,666 B | **licence not stated in this repo** | `yantra-os/assets/typewriter/sfx/`; `yantra-os/apps/typewriter/app.nim:143-149` names 13 of them; no generator, no source URL | runtime audio assets |

Two things the table will not show:

* **The release tree ships no third-party binary at all.**
  ```
  $ cd /home/ubuntu/yantra/yantra-os && find . \( -name '*.so' -o -name '*.dll' -o -name '*.a' \
      -o -name '*.exe' -o -name '*.dylib' -o -name '*.o' -o -name '*.lib' \) -printf '%s\t%p\n'
  19438	./apps/notes/minilibc.o
  ```
  One line only — wasm32 build debris of `sdk/minilibc/minilibc.c` (the 12 `.wasm` files are the
  project's own Nim compile output). (`yantra-os/docs/THIRD-PARTY.md:25` still places
  `minilibc.o` in `apps/desktop/`; it has since moved to `apps/notes/`.)
* **The 135-DLL bundle is wider than this audit.** Beyond FFmpeg it carries `libx264-165.dll`
  (2,024,174 B, sha256 `0d814d13db7eeac0ff5264ed86d376f9260746323107cb07affb6c306b240329`),
  `libx265-217.dll`, `xvidcore.dll`, `libaom`, `libdav1d`, `libvpx`, `libsvtav1`, `librav1e`,
  `libass`, `libbluray`, `librsvg`, `libplacebo`, `libwhisper`, ICU, Cairo, Pango, GnuTLS and
  more. Only the components named by a repo wrapper or licence file are audited above; the rest
  are **not audited**, and several of them (`libx265`, `xvidcore`) have their own copyleft
  obligations that appear nowhere in this repo.

---

## 3. Obligations when you redistribute — the short form

* **GPL-2.0-or-later / GPL-3.0-or-later (FFmpeg as built).** Ship the licence text; ship or offer
  the complete corresponding source of the GPL parts, including the build configuration used to
  produce the binary (that configuration string is above, ready to paste into your offer); keep
  the whole distributed combination GPL-compatible; state any changes. Under GPL-3 additionally
  no "installation information" lock-out and an express patent grant.
* **MPL-2.0 (libdatachannel).** File-level copyleft: publish the source of MPL-covered files you
  modify, otherwise keep the notice and say where the source is.
* **Apache-2.0 (Filament).** Ship the licence, keep any upstream `NOTICE` (there is none here),
  state your modifications, do not imply endorsement.
* **MIT / BSD-3-Clause / Zlib / MIT-0 (Yoga, Jolt, Skia, HarfBuzz, SDL3, miniaudio, Nimony,
  Nativenif).** Keep the copyright notice and licence text with every copy, including in binary
  distribution documentation. BSD-3 adds a no-endorsement clause. Zlib adds: do not misrepresent
  the origin, mark altered versions as altered.
* **Public domain (SQLite; miniaudio's Unlicense option).** No obligation; keeping the notice is
  what makes provenance auditable.
* **Proprietary (the 8 Anthropic skill translations).** Nothing in this repo grants you the right
  to redistribute them; the `NOTICE.md` they point at does not exist. Either get Anthropic's
  permission or drop `skills/yantra/translated-skills/` from the release.

---

## 4. Gaps that survive this audit

1. **No licence file ships in the release archive** — 136 entries, zero licences. Highest
   priority, lowest cost.
2. **FFmpeg's own licence text is not in the repo.** `third_party/ffmpeg-local/` holds
   `bin/ include/ lib/ share/` and no `LICENSE`/`COPYING`. The variant is proven from the binary
   strings, but the text still has to be sourced and shipped.
3. **x264's licence is not stated anywhere in this repo**, although `--enable-libx264` is what
   forced `--enable-gpl` on the Linux build.
4. **Nine components state no licence at all** — compiler-rt, wasmtime, Qt 6, PostgreSQL, Nim,
   binaryen, clang/LLVM, Emscripten, and the 20 typewriter `.wav` files. wasmtime is the
   sandbox the whole product rests on and is the most conspicuous of these.
5. **Two rows of `THIRD-PARTY.md` are stale in this tree** (both corrected in §2 above): the
   typewriter assets are 20 files under `assets/typewriter/sfx/`, not 6 named ones under
   `apps/typewriter/`; and the tree has 12 app modules, not 11.
6. **The Windows FFmpeg version is unknown.** The zip has no `ffmpeg.exe` and no version string;
   only the library majors (61/63/63/12/10/7) are measurable.
7. **`yantra-os/libs/nimskia/` and `yantra-os/libs/nimsdl3/` have no README**, alone among the
   wrappers, so their upstreams rest only on `#include`s and the `third_party/` licence files.

## 5. Provenance of the artifacts measured here

The Windows DLLs were measured inside `/tmp/wt-windows-dist-scratch/yantra-windows-x64-bin.zip`
— 108,618,297 bytes, sha256
`e1dd23e7f2e21a14a4fa86c0690616d183edefbcfa3b22a5a59b58ddf7115d18`. That file was re-downloaded
during this audit from
`https://github.com/Yantra-lab/yantra-os/releases/download/v1.0.0/yantra-windows-x64-bin.zip`
(HTTP 200, `content-length: 108618297`) and hashed again: **identical sha256**. The hashes in
the table are therefore hashes of the published release artifact, not of a local rebuild.

The Linux libraries are the build input on this machine only (`third_party/` is gitignored and
not shipped). Their `--prefix=/tmp/vajra-wt/…` shows they were built in another directory and
copied here. If a Linux binary is ever published, it inherits the **GPL-2.0-or-later** finding
in §1.

**Nothing here is legal advice.**
