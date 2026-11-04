# FILE-MAP — yantra-os, the release tree

Snapshot **2026-11-05T05:21Z**, measured inside `/home/ubuntu/yantra/yantra-os` (bytes by `stat`,
lines by `wc -l`, "works/fails" by running it). Nothing was edited to write this. Other agents were
writing `apps/*/app.json`, `apps/*/app.yantra.json`, `tools/*` and `web/runner/app.html` during the
review; where a fact changed mid-review the current value is given and the earlier one named.

## 1. Read this first (5 stops)

1. `README.md` — the claim. Read the prose; its size tables are stale (§5.9).
2. `docs/FILE-MAP.md` — this file: what is source, artifact, or dead weight.
3. `web/runner/` — the folder that proves the claim with no toolchain: `runner.js` (627 lines) is a second implementation of the host contract that loads the *shipped* `apps/*/app.wasm`.
4. `node tools/verify-wasm.mjs apps/typewriter`, then `node web/runner/tests/calc.mjs` for interaction. The verifier prints size, sha256, instantiation ms and the live node tree, and states that it compares no pixels (§4).
5. `docs/shell/PARITY-AUDIT.md` — the only honest gap list in the tree (`file:line`, 2026-11-05); `RELEASE.md` is the bar this tree misses.

## 2. The tree in one screen

```
yantra-os/
├── README.md                                  pitch; stale numbers (§5.9)
├── RELEASE.md                                 20-line release bar + junk policy (currently broken)
├── YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md   121,294 B spec duplicating existing source (§5.5)
├── LICENSE                                    MIT, Sanskar Balpande
├── apps/          10 Nim→wasm apps, 5,986,039 B of app.wasm + manifests + port notes + source HTML
│   ├── desktop/   91-line entry that `include`s 6 modules: ui.nim 52,790 B, state 31,438 B, config, catalog, tiling, settings
│   └── typewriter/ also 6 .wav samples (294,852 B); .gitignore lists *.wav, they ship anyway
├── sdk/           what an app imports (`import yantra`): 51 files, ui/ core/ motion/ minilibc
├── host/          engine half #1: wasmtime host (host.nim 1,525 lines), tree, sandbox, 4 t_*.nim
├── render/        api.nim contract + native/ = engine half #2 (engine.nim 4,377 lines, 71 files)
├── protocol/      schema.nim = source of truth; wire.nim and props.md are GENERATED
├── libs/          16 Nim wrappers for C/C++ libraries; not one has a tests/ dir
├── web/
│   ├── runner/    JS host that runs the shipped wasm + 11 tests   ← the verifiable part
│   └── engine/    2-file stub; its build/ was never made (emscripten + Skia needed)
├── tools/         17 entries; verify-wasm.mjs + os-measure.sh work, the rest need nim / third_party
├── docs/          spec/ vajra-book/ shell/ assets/ img/ context/ + 7 loose .md
├── skills/        LLM-facing manual (yantra, web-to-yantra, translated-skills), 1.5 MB
├── assets/brand/  2 brand PNGs (2,646,937 B), the input of tools/make-icon.mjs
├── yoga/          4 files, 3 of them entirely NUL bytes — corrupt copy of libs/nimyoga (§5.1)
├── scratch/       6,676,555 B (du) of probe PNG/PPM captures + 2 probe sources; gitignored
├── third_party/   ABSENT (upstream toolchains) — nothing here can be rebuilt
└── 5 PNGs at top level (1,105,586 B) + run.sh, run_yantra.sh, run_yantra.bat, verify_all.bat
```

## 3. What each folder is

| Path | What it is | Source or artifact? | Read it if you care about |
|---|---|---|---|
| `apps/` | `app.nim` + prebuilt `app.wasm` + `app.json` + *(moving)* `app.yantra.json`; chess/dna/gallery/typewriter also keep the source HTML, `.txt` and `port-notes.md` | App source; `.wasm` is a **prebuilt artifact** | The product, and the porting method |
| `sdk/` | The whole guest surface: `yantra.nim`, `ui/*` nodes, `core/*` services, `minilibc/minilibc.c`. `props.nim` and `core/wire.nim` are GENERATED | **Source of the guest SDK** | How 77 lines become 341 KiB |
| `host/` | The contract: `host.nim` loads wasm via `libs/nimwasmtime`, supplies imports positionally, owns the tree, dispatches events; `netrules/vajranet` = sandbox policy; `sys_{linux,win}.c` | **Source of the engine** (host half) | The security boundary |
| `render/` | `api.nim` = backend-agnostic Renderer; `native/` = the real engine (`engine.nim` 4,377 lines, `yantra_run.nim` entry, `devwatch.nim`, `mcp_server.nim`, 50 `t_*.nim` tests) | **Source of the engine** (render half) | Skia/SDL3/Yoga integration, the host binary |
| `protocol/` | `schema.nim` (48 node kinds, 265 props, events), `easing.nim`, `gen.nim` generator, `t_characterization.nim`; `wire.nim` + `props.md` are generated into the same folder | Source + generated files mixed | The wire format every binding derives from |
| `libs/` | 16 wrappers: `nimwasmtime, nimskia, nimsdl3, nimyoga, nimqt, nimfilament, nimjolt, nimminiaudio, nimsqlite, nimpg, nimcurl, nimblake3, nimspell, nimaccesskit, nimav, nimrtc`, each `src/*.nim` + `*_shim.c/.cpp`. 14 have a README, 13 of those an INTERFACE; `nimsdl3`/`nimskia` have `src/` only; **0 have `tests/`** | **Wrappers** — the C/C++ itself is not in the tree | The "wrap the real library" rule |
| `web/runner/` | `runner.js` (627), generated `protocol.mjs` (358), `app.html` (77; its dropdown listed 8 apps at 04:55 and all ten at 05:18), `index.html` (45, counter demo), 11 tests | Source (independent implementation, not a wrapper of the native engine) | **How the shipped wasm really runs** |
| `web/engine/` | `index.html` + `yantra.js` (16 KiB) fetching `build/engine.js`, `build/apps/<n>.wasm` | Stub — neither `build/` nor its input `render/web/` exists | The abandoned browser-engine path |
| `tools/` | Scripts + `scopes.txt`; each listed in §3.1 | Source | How anything is built, exported, checked |
| `docs/spec/` | `core.md` (22,994 B, "normative" language spec v1) + `style.md` | **Specification** | What the DSL is *supposed* to accept |
| `docs/vajra-book/` | 27 files: the future Vajra/Atlas book, per-feature `built`/`planned` status | **Specification of unbuilt work** | Where the project says it is going |
| `docs/shell/` | `PLAN.md` (2026-09-28) + `PARITY-AUDIT.md` (2026-11-05) | Plan / audit | The most honest document here |
| `docs/context/` | 8 `gitingest_*.txt`, 6,329,872 B (~6.0 MiB): whole-repo slurps made for LLM agents ("YANTRA OS REPOSITORY INGEST … Purpose: 1:1 Porting") | **AI context dumps, not product** | Nothing about the engine |
| `docs/assets/` | 6 README banners/infographics, 15,005,983 B (~14.3 MiB) | Images used by `README.md` | The marketing renders |
| `docs/img/` | 4 app screenshots + `manifest.json` from `tools/capture-shots.mjs` (05:11); manifest says "Not the native Skia renderer" | Generated evidence (DOM runner pixels) | What the apps actually paint |
| `docs/*.md` | `ARCHITECTURE`, `PROVENANCE`, `THIRD-PARTY`, `SUBMISSION_ANSWERS`, `MUSE_AGENT_SYSTEM`, `apis`, `language` | Mixed: docs + hackathon Q&A | Licences and per-binary provenance: `THIRD-PARTY.md`, `PROVENANCE.md` |
| `skills/` | Manual to hand an LLM: `yantra/` (23 reference files, 2 examples), `web-to-yantra/` (port rules), `translated-skills/` (8 Anthropic skills) | Source documentation | Why the code looks like this |
| `assets/brand/` | `yantra-icon.png` (1,091,923 B) + `yantra-os-hero.png` (1,555,014 B) | Build input for `make-icon.mjs` | Icon/exe generation only |
| `yoga/` | `README.md` (real, 3,526 B) + `nimyoga.nim`, `INTERFACE.md`, `t_layout.nim` — the last three are **100% NUL bytes** | Corrupt duplicate, **dead** | §5.1 |
| `scratch/` | 8 PNG + 1 PPM (3,072,016 B), `twotabs_probe.nim`, `pxstats.py` | Scratch, in `.gitignore` yet shipping | Nothing in a release |
| `third_party/` (absent) | wasmtime / Skia / SDL3 / Yoga / Filament / Jolt / miniaudio / wasi-sdk | Missing build input | Why §6 exists |

### 3.1 `tools/` — every entry

- `verify-wasm.mjs` (88) — runs a wasm in `web/runner/runner.js` and prints measured size, sha256, instantiation ms, the live node kinds, and "no pixels were compared". **Works** (10/10, exit 0). Its earlier 48-line version printed two constants ("`<0.2ms flexbox pass`", "`155/155 rounds matched`"); that was fixed at 05:16.
- `export-json.mjs` (358, *moving*) — steps an app and writes `app.yantra.json` + rewrites `app.json` with sha256/bytes/lines. **Worked at 05:03** (outputs exist); not re-run here, it writes the tree.
- `os-measure.sh` (13) + `os-measure.mjs` (201, *moving*) — the measured app table, and `--check` to fail when `README.md` drifts from the tree. **Works**: ran `bash tools/os-measure.sh`; it reproduced the §4 sizes and totals exactly.
- `capture-shots.mjs` (701, *moving*) — serves the repo, opens `app.html?app=…`, writes `docs/img/*.png`. **Worked at 05:11**, but defaults to Playwright *outside* the tree (`/home/ubuntu/yantra/open/node_modules/playwright`): not portable as-is.
- `build-wasm.sh` (176) — Nim → freestanding wasm32 via `nim` + wasi-sdk clang + `wasm-opt`. **Cannot run here**: no `nim`, no `third_party/wasi-sdk-*` (measured: "`nim: command not found`").
- `build-wasm.bat` (35) — Windows mirror; same missing deps; not run.
- `build-all.sh` (61) — wasm + verify + native; needs nim/clang/`third_party`; cannot run.
- `build-web.sh` (55) — emscripten build of `render/web/` (absent) + Skia-for-wasm → `web/engine/build/`. **Cannot run even with emsdk**: nothing to build.
- `check.sh` (238) — the merge gate. Needs a git branch vs `main` (no `.git` here), `.board/reports/<task>.md` (no `.board/`), and the `tools/merge.sh` + `tools/hooks/` it protects (both absent). Cannot run.
- `setup.sh` (133) — downloads msys2, wasmtime C API v48+v19 (Windows DLLs), Yoga 3.1.0, `miniaudio.h`. No wasi-sdk, no Skia, no SDL3, no nim.
- `apps-index.sh` (20) — regenerates the `CatalogApp` block of `apps/desktop/catalog.nim`. Not run (writes a repo file); `catalog.nim:127` says "do NOT run apps-index.sh".
- `make-icon.mjs` (167) — PNG → `render/native/yantra.ico` (gitignored, absent). Not run.
- `make_gitingest.mjs` (253) — builds `docs/context/*`; **hardcodes** `C:\Users\Sanskar\DEV\yantra-os`, so it will not reproduce them here unedited.
- `yantra-mcp-stdio.mjs` (242) — MCP stdio bridge to an engine on `127.0.0.1:9229`; parses, but needs `bin/yantra` (absent).
- `wt.sh` (51) — git worktree helper (Windows junctions); needs a git repo and `third_party/`.
- `scopes.txt` (54) — path-scope table for `check.sh`; data, not a script.

Running any rebuild test (e.g. `web/runner/tests/desktop_editor_mcp.mjs`) leaves `apps/desktop/minilibc.o`
(19,214 B, in this tree since 05:10) behind; `.gitignore` lists `minilibc.o`.

## 4. The apps

Ten apps; total shipped module size **5,986,039 B = 5,845.7 KiB = 5.708 MiB**. Bytes are `stat`, lines
`wc -l`, live nodes what `node tools/verify-wasm.mjs apps/<name>` reports (cross-checked against
`bash tools/os-measure.sh`, which prints the same bytes and totals).

| App | `.wasm` bytes | KiB | `app.nim` lines | live nodes | what it is |
|---|---:|---:|---:|---:|---|
| `calc` | 404,142 | 394.7 | 90 | 61 | Four-function calculator; key grid from one component — the "short app" proof. |
| `chess` | 577,770 | 564.2 | 2,918 | 7 | 1:1 port of `070-chess-study.html`: FIDE rules, piece renderer, animation, editable score sheet. |
| `desktop` | 2,186,434 | 2,135.2 | 91 | 128 | The shell: tiling WM, bar, dock, embedded `AppView`s; 91 lines + 6 included modules (ui.nim alone 52,790 B). 4x the next module. |
| `dna` | 416,112 | 406.4 | 1,487 | 2 | `052-dna-helix.html` with a hand-written 3D projection, every primitive a `Draw` verb. |
| `editor` | 353,828 | 345.5 | 416 | 3 | Studio IDE: explorer, Nim-highlight canvas, minimap, Ctrl+S reload, live preview tab. |
| `files` | 302,539 | 295.4 | 215 | 3 | Dual-pane manager over the ten catalog apps; hands one to the desktop via `storeSet`. |
| `gallery` | 545,597 | 532.8 | 2,755 | 2 | Galerie Nocturne: walk-through museum room, 8 procedural works, all `Draw`. |
| `notes` | 350,099 | 341.9 | 84 | 26 | Two-pane notes + editor with `persistent()` state. |
| `todo` | 348,770 | 340.6 | 77 | 30 | Add / check / filter list, keyed rows, bound input — shortest app. |
| `typewriter` | 500,748 | 489.0 | 2,045 | 29 | Marlowe 44: procedural desk and paper layers, ink stamps, carriage physics, 6 `.wav` Foley samples. |

Manifests *(moving)*: every app has both. `app.json` was a **90–112 B launcher stub of five keys** at
04:52 — `{"id","name","icon","tint","grants":[]}` (`icon` one character, `tint` `#RRGGBB`); since 05:03
`tools/export-json.mjs` rewrote all ten (587–648 B), keeping those five and appending
`window{title,width,height,bg}`, `module{path,bytes,sha256}`, `source{path,lines,bytes,sha256}`, `nodes`,
`document`, `generated`. `app.yantra.json` did **not** exist at 04:58; ten appeared 05:04 (5,906–33,200
B) with keys `$yantra` ("2026.11"), `app` ("y:@yantra/calc"), `name`, `exported{…protocol:"v2"}`,
`window`, `stats`, `nodes`, `provenance`, `verify` — "L1 structured twin … Not executable on its own, and
not restorable to the Nim source". Node counts match the verifier for nine apps; `app.yantra.json` says 4
for `editor` where the verifier instantiates 3. Extra artifact: `apps/desktop/desktop.wasm` (753,756 B), a
second build nothing fetches (§5.7).

The verifier proves: the module compiles, instantiates against the JS host's imports and builds its node
tree, and reports how long that took on the JS runner (~12 ms for `todo`, ~12,000 ms for `typewriter`). It
does **not** compare pixels. Tests today: `calc`, `chess` (140
assertions), `dna` (43), `notes`, `todo` pass; `gallery` passed 34 assertions but had not finished after
400 s; `typewriter` and `typewriter-timing` exceed 60 s (`-timing` finishes, prints "HANDLER BUDGET
EXCEEDED", ~714 ms/key, yet exits 0); `tests/test.mjs` dies on missing `examples/counter.wasm`;
`tests/shell.mjs` on missing `examples/shell/shell.wasm`; `tests/desktop_editor_mcp.mjs` re-runs
`build-wasm.sh` and dies at "`nim: command not found`" — so `web/runner/run_tests.sh` reports **FAIL**.

## 5. Naming problems (PROPOSALS ONLY — nothing renamed, moved or deleted)

1. **`yoga/` vs `libs/nimyoga/` — duplicates, and `yoga/` is corrupt.** Same API, but files differ and `file` calls `yoga/nimyoga.nim` "data": it, `yoga/INTERFACE.md` and `yoga/t_layout.nim` hold **zero non-NUL bytes** (same byte sizes as the libs copies, so zeroed in place). `docs/ARCHITECTURE.md:40` still sends readers to `yoga/*`. **Proposal:** delete `yoga/`; keep its 3,526 B README as `libs/nimyoga/README-META.md`; repoint `ARCHITECTURE.md:40` at `libs/nimyoga/`.
2. **`protocol/` does not say which files are generated.** `schema.nim` is the source of truth; `protocol/wire.nim:1`, `protocol/props.md:3`, `sdk/core/wire.nim`, `sdk/props.nim` and `web/runner/protocol.mjs:1` all say "GENERATED FILE. DO NOT EDIT."; `gen.nim` writes them. **Proposal:** add a 5-line `protocol/README.md`; rename `web/runner/protocol.mjs` → `protocol.gen.mjs` (update `gen.nim:88`).
3. **Three image folders.** `assets/brand/` (2,646,937 B, build input only), `docs/assets/` (15,005,983 B, README images), `docs/img/` (4 fresh screenshots + manifest; did not exist when AGENTS.md was written). **Proposal:** keep all three; add one line to `assets/` saying it is build input, not screenshots.
4. **`scratch/` should not ship.** 6.4 MiB: 8 PNGs, a 3,072,016 B raw PPM framebuffer, `twotabs_probe.nim`, `pxstats.py`; it is in `.gitignore`, so untracked debris ships anyway. **Proposal:** delete from the release tree — `docs/img/` is the evidence now.
5. **`YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md`.** 121,294 B, 3,078 lines; its 16 `FILE` blocks are full sources of files already in the tree (`apps/desktop/{config,tiling,catalog,app}.nim`, `apps/{editor,files}`, `render/native/{devwatch,mcp_server,yantra_run}.nim`, `tools/*`, `Yantra.*`, one test). Markers are HTML-escaped (`&lt;!-- FILE: … --&gt;`), so `unpack-yantra-bundle.mjs` matches **0 blocks** — a silent no-op (regex simulated; nothing written). **Proposal:** move to `docs/spec/impl-bundle.md`; delete the unpacker, or unescape the markers and keep it as the app scaffolder.
6. **Four launchers, overlapping.** `run.sh` (335: 11-item menu, starts a Python/Node HTTP server, falls back to the web runner, preflight looks for `bin/yantra.exe` even on Linux); `run_yantra.sh` (40: build desktop wasm, `nim c` `render/native/yantra_run.nim` → `bin/yantra`, exec `--watch --mcp-port=9229`; needs nim + `third_party`); `run_yantra.bat` (82: same for Windows, assumes `bin\` with 135 DLLs); `verify_all.bat` (56: looks for `bin\yantra.exe`, curls a release zip, checks 8 app wasm, calls `run_yantra.bat`). **Proposal:** keep `run_yantra.sh`/`.bat` as *the* launchers; `git mv run.sh tools/run.sh`; `git mv verify_all.bat tools/`; add `editor` and `files` to its list.
7. **Stale duplicate binary** `apps/desktop/desktop.wasm` (753,756 B) beside `app.wasm` (2,186,434 B); `app.html:47-50` tries `app.wasm` first, so the second is never fetched, yet `apps/README.md` quotes 753 KB as the desktop's size. **Proposal:** delete it.
8. **Ten identical `panicoverride.nim`** (722 B, all md5 `52b31f13…`, same as `sdk/panicoverride.nim`); `tools/build-wasm.sh:107-108` copies the SDK's own copy and AGENTS.md calls it generated output. **Proposal:** delete the ten `apps/*/panicoverride.nim`.
9. **README numbers contradict the tree.** `README.md:25` lists 5 apps — "`typewriter`, `gallery3d`, `descent`, `desktop`, `chess`" — but there is no `apps/gallery3d` and no `apps/descent`; `:27` gives typewriter 356 KB (489.0 KiB) and `descent` 410 KB; `:136` gives the gallery as "214 lines" (2,755); `:139` gives DNA 224 KB (406.4 KiB). `apps/README.md` has 8 rows, sizes wrong or stale, and omits `editor`, `files`. **Proposal:** regenerate both tables — `bash tools/os-measure.sh --write` already does it for the app table — and replace the phantom ids with the real ten.

## 6. What is missing from the tree (verified, not assumed)

- **`examples/` — absent, five references need it.** `web/runner/index.html:34` fetches `../../examples/counter.wasm`; `web/runner/tests/test.mjs:10` `stat`s it; `tests/shell.mjs:9-16` needs `examples/shell/shell.wasm` plus child apps; `app.html:50` lists it as a third fallback; `protocol/gen.nim:87` writes `../examples/protocol.mjs`. Measured: `test.mjs` ENOENT, `shell.mjs` "shell.wasm missing", `run_tests.sh` FAIL. The only example Nim sources are `skills/yantra/examples/{hello_app,imperative_app}.nim`, and nothing builds them.
- **`third_party/` — absent by policy** (gitignored, "never commit"), so no wasmtime/Skia/SDL3/Yoga/Filament/Jolt/miniaudio code is here and no `libs/` wrapper can be compiled. `tools/setup.sh` restores only part (Windows wasmtime DLLs, Yoga, `miniaudio.h`, msys2) — no wasi-sdk, no Skia, no `nim`. `docs/THIRD-PARTY.md` (05:04) documents the licences and says the folder is not shipped.
- **No native host binary.** No `bin/`, no `*.exe/*.dll/*.so/*.a` anywhere in the tree; `run_yantra.sh` is meant to compile `render/native/yantra_run.nim` on first run, which cannot happen here — the native path is unproven from this tree alone.
- **No `nim`.** Not vendored, not installable from the tree, missing on this machine: `build-wasm.sh`, `build-all.sh`, `check.sh` and the desktop test all stop at "nim: command not found". Every working command here is Node.
- **`render/web/` and `web/engine/build/` absent.** `web/engine/index.html` wants `build/engine.js` + `build/apps/<n>.wasm`; `build-web.sh` wants `render/web/web_main.nim` and `render/web/engine.nim`; neither exists and `emcc` is not installed. The browser-native engine is a 2-file stub.
- **`sdk/vajra/` absent** though `protocol/gen.nim:119` writes `sdk/vajra/wire.nim` (it would `createDir`, so the generator is fine; the output is simply not in this snapshot).
- **No runnable engine gate.** `host/` has 4 `t_*.nim`, `render/native/` 50 more, all needing `nim`. `tools/check.sh` also needs `.git`, `.board/reports/<task>.md`, `tools/baseline.txt`, `tools/merge.sh`, `tools/hooks/` — none present.

Start at `README.md`; keep this map beside it, and re-measure before quoting any number.

## Status of the proposals (2026-11-05, after the release pass)

This document was written against the tree as submitted. Nine proposals were made; here
is what was done to them, so the proposals above can be read as history rather than as a
to-do list.

| # | Proposal | Status |
| ---: | :--- | :--- |
| 1 | Delete `yoga/`, keep its README | **Done.** Three of its four files were 100 % NUL bytes. `libs/nimyoga/src/nimyoga.nim` is the intact wrapper; the README survives as `libs/nimyoga/README-legacy-top-level-copy.md`. |
| 2 | Label `protocol/` source vs generated | **Open.** `protocol/schema.nim` is the source; `web/runner/protocol.mjs` says "GENERATED FILE" in its first line. |
| 3 | Distinguish the three image folders | **Partly done.** `docs/img/` now holds script-generated screenshots (`docs/img/CAPTURE.md`); `docs/img/legacy/` holds the earlier captures with no recorded origin. |
| 4 | Delete `scratch/` | **Done.** |
| 5 | Move the 121 KB bundle to `docs/`, drop the unpacker | **Half done.** Moved to `docs/context/IMPLEMENTATION-BUNDLE.md`; `unpack-yantra-bundle.mjs` is still in the root. |
| 6 | Keep one launcher family | **Open.** `run.sh`, `run_yantra.sh`, `run_yantra.bat` and `verify_all.bat` all still exist; `verify_all.sh` is new and is the gate for this tree. |
| 7 | Delete `apps/desktop/desktop.wasm` | **Done.** |
| 8 | Delete the ten `panicoverride.nim` copies | **Done.** |
| 9 | Regenerate both README tables | **Done.** `bash tools/os-measure.sh --write` writes `README.md`'s table and `apps/README.md`; `--check` fails on drift. |

Two more things changed that this map did not ask for, and a reader should know:

* **`apps/<name>/app.yantra.json` now exists for all ten apps** — generated by
  `tools/export-json.mjs` from the running module, not hand-written. `apps/<name>/app.json`
  is now a real launcher manifest carrying the module's sha256 and byte count.
* **`tools/verify-wasm.mjs` no longer prints constants.** It reports what it measured.
  `docs/VERIFICATION.md` is the resulting table, dated.
