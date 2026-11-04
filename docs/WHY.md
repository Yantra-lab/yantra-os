# WHY — why each app is a WebAssembly module

One question: is it worth replacing "the browser" as the runtime for a desktop app
with a small sandboxed module plus one shared renderer? Everything numeric below was
measured on this tree, with the command named next to it. Nothing here is estimated.

## 1. The problem

Three things are wrong with shipping a desktop app as a browser, and they are not
equally proven.

**Industry facts, not measured here.** Every app that ships as a browser carries its
own copy of the browser. A UI update has to travel through the framework's component
diff, the DOM, style recalculation and layout, and that whole path runs on one
JavaScript thread. These are properties of the Electron/CEF/WebView model as published
by those projects; I did not measure a browser or an Electron app in this tree, so no
Chromium, Electron or V8 size appears in this file.

**What Yantra measured itself.** In this tree the module floor, not the app's logic,
dominates the bytes:

- `todo` is 77 lines of `app.nim` and ships 348,770 B.
- `chess` is 2,918 lines of `app.nim` and ships 577,770 B.
- That is 37.9x the source (`2918/77`) for 1.66x the bytes (`577770/348770`).
- The smallest module is `files` at 302,539 B, with 215 source lines.

So an app's own code is a minority of what it installs. The floor is the shared guest
runtime: the SDK, the Nim runtime, and the wire protocol compiled into every module.
Yantra's answer removes the DOM and the per-app engine but does not remove that floor.
Each of the ten modules still pays it. That is a real cost, and it is paid ten times.

## 2. The measured answer

Binary size by `stat -c%s apps/<name>/app.wasm`, KiB as that number divided by 1024,
source lines by `wc -l apps/<name>/app.nim`, live nodes from
`node tools/verify-wasm.mjs apps/<name>` (the node count the verifier prints).

| App | `.wasm` bytes | KiB | `app.nim` lines | live nodes |
|---|---:|---:|---:|---:|
| `calc` | 404,142 | 394.7 | 90 | 61 |
| `chess` | 577,770 | 564.2 | 2,918 | 7 |
| `desktop` | 2,186,434 | 2,135.2 | 91 | 128 |
| `dna` | 416,112 | 406.4 | 1,487 | 2 |
| `editor` | 353,828 | 345.5 | 416 | 3 |
| `files` | 302,539 | 295.4 | 215 | 3 |
| `gallery` | 545,597 | 532.8 | 2,755 | 2 |
| `notes` | 350,099 | 341.9 | 84 | 26 |
| `todo` | 348,770 | 340.6 | 77 | 30 |
| `typewriter` | 500,748 | 489.0 | 2,045 | 29 |
| **total** | **5,986,039** | **5,845.7** | **10,178** | **291** |

All ten apps together are 5,986,039 B of WebAssembly: 5.71 MiB. The largest single
module is 2,186,434 B (`desktop`, 2.13 MiB) and the next largest is 577,770 B, so the
total is not representative of a normal app. The median module is 410,127 B. Ten apps,
10,178 lines of Nim, 291 live UI nodes at boot.

### The verifier

```
node tools/verify-wasm.mjs apps/<name>
```

I ran it for all ten apps in this tree; every run printed `RESULT: PASS` and exited 0.
The node counts above are that command's own output.

**What a pass proves.** The shipped `.wasm` compiles and instantiates in a sandbox that
is given no keys, no network and no GPU, and its start-up code builds a live UI tree
with a root element. The verifier also lists the tree by node kind, so you can see
whether an app is DOM-shaped or canvas-shaped.

**What a pass does not prove.** The script does not render. As it stands in this tree it
prints the line "no pixels were compared — this script does not render", and that is
accurate: no frame is rasterised, so a verifier pass says nothing about layout
correctness, colour, or visual fidelity to any reference image. It also does not prove
the module does anything useful after start-up — that is what the interaction suites in
section 3 are for.

**Timing.** Two honest measurements, both on this machine (Intel Xeon Platinum 8559C,
Node v22.23.4), neither of which says anything about the native engine:

- `WebAssembly.compile` of each module, median of 5 runs after one warm-up, timed with
  `process.hrtime.bigint()`: 0.8 ms for `files` to 4.2 ms for `desktop`.
- Boot in the web runner (`createRunner` = compile + instantiate + the module's start
  hook building its tree), the figure the verifier itself prints: 15.4 ms for `calc`,
  32.3 ms for `desktop`, and 11,930.8 ms for `typewriter`.

The typewriter figure is a weakness, not a boast. Its start hook paints large retained
layers into a DOM-backed canvas, and the web runner pays for that in JavaScript. It is
the strongest argument in this tree for a native renderer, and the native renderer is
not runnable from this tree (section 4).

## 3. What is proven here

- **All ten shipped modules run.** `for a in calc chess desktop dna editor files gallery
  notes todo typewriter; do node tools/verify-wasm.mjs apps/$a; done` — ten passes,
  exit 0 each.
- **The capability surface is 32 functions.** Listing the imports of all ten modules
  with `WebAssembly.Module.imports` in Node shows 32 distinct imports, every one of them
  under the single `env` namespace and every one named `y_*` (`y_node_create`,
  `y_node_set_i32`, `y_fetch`, `y_store_get`, `y_layer_draw`, and 27 more). There is no
  WASI import and no filesystem import, so the module cannot reach a file, a socket or a
  clock except through those functions. Per app the count is 10 imports (`todo`) to 22
  (`desktop`).
- **Behaviour is tested, not just boot.** `node web/runner/tests/calc.mjs` (all
  assertions passed), `node web/runner/tests/notes.mjs`, `node web/runner/tests/todo.mjs`,
  `node web/runner/tests/chess.mjs` (prints "140 passed"),
  `node web/runner/tests/dna.mjs` (43 assertions), and
  `node web/runner/tests/typewriter.mjs` (47 assertions). These drive the real controls:
  `calc` types `7 x 6` through the emitted elements and asserts the display reads 42;
  `typewriter` asserts a saved PNG's signature and 1200x1552 dimensions. I ran all six
  and saw them pass.
- **The artifact under test is the shipped artifact.** The runner loads
  `apps/<name>/app.wasm` — the same bytes `run_yantra.sh` hands to the native host. Each
  module's sha256 is recorded in its `app.json`, so a reader can confirm the binary has
  not changed since export.
- **The modules are built with ARC.** `tools/build-wasm.sh:141` compiles with
  `--mm:arc`, so there is no tracing collector to pause. This is the build script's
  flag, not a measurement of pause times; nobody has profiled pauses here.
- **The JSON twin exists for all ten apps.** `ls apps/*/app.yantra.json` lists ten files,
  and each one parses (`node -e 'JSON.parse(require("fs").readFileSync(p,"utf8"))'`).
  Each records the module hash, the source hash, the window, the node census and the
  verifier command that backs it. `calc`'s export records 61 nodes, the same number the
  verifier counted by instantiating the module — two independent producers of one
  census.

## 4. What is not done

Each item below was checked in this tree today.

- **There is no native host binary.** No compiled object ships in the tree at all: no
  `bin/`, no `build/`, and no `.so`, `.a`, `.dll`, `.dylib` or `.exe`
  (`find . -name '*.so*' -o -name '*.dll' -o -name '*.exe'` returns nothing). The only
  executable files are scripts (`verify_all.sh`, `tools/os-measure.sh`, the `.mjs`
  tools). A judge cannot run the native engine from this repo. What runs is the web
  runner in `web/runner/`, which is a second implementation of the host contract in
  JavaScript, not the engine.
- **The native engine must be compiled, and this tree cannot compile it.**
  `run_yantra.sh` builds `bin/yantra` with `nim c -d:release --threads:on ... render/native/yantra_run.nim` when it is missing, then execs
  `./bin/yantra apps/desktop/app.wasm --watch --mcp-port=9229`. That needs a Nim
  compiler and `third_party/`, which is gitignored and absent here — there is no
  `third_party/` directory in the tree at all. `render/config.nims` points its toolchain
  at `third_party/msys64/mingw64`, so the documented native build is a Windows/MinGW one.
  On this machine `nim` is not installed, so I could not build it either.
- **The 3D path has no runnable artifact.** `libs/nimfilament` is a README, an
  INTERFACE and two sources (`nimfilament.nim`, `filament_shim.cpp`); `libs/nimjolt` is
  the same shape. Filament itself is the Windows release v1.77.1 under
  `third_party/filament`, and the README says the shim builds `build/yfilament.dll` —
  neither is in this tree. There are 0 `run_tests.sh` files under `libs/`, so even the
  README's own "Tests: `bash tests/run_tests.sh`" cannot be run here.
- **Test gaps are real.** `bash web/runner/run_tests.sh` exits 1, because it runs only
  `web/runner/test.mjs`, which stats `examples/counter.wasm` — there is no `examples/`
  directory in this tree. `node web/runner/tests/shell.mjs` prints
  "FAIL: shell.wasm missing" and exits 1 for the same reason.
  `node web/runner/tests/desktop_editor_mcp.mjs` exits 1 because it rebuilds
  `apps/{desktop,editor,files}/app.wasm` before testing anything and fails at
  `nim: command not found`. `node web/runner/tests/gallery.mjs` does not finish: given
  900 seconds it had printed 30 passing assertions and no failure when it was stopped, so
  it is slow rather than broken. `node web/runner/tests/typewriter-timing.mjs` exits 0
  while printing "HANDLER BUDGET EXCEEDED" (50 typing handlers, average 691.72 ms, worst
  1055.54 ms), so its exit code is not a pass/fail signal.
- **`web/runner/run_tests.sh` is still broken; the gate is now `verify_all.sh`.**
  `run_tests.sh` covers one file that stats a missing `examples/counter.wasm` and exits 1.
  `bash verify_all.sh` is the single command that fails honestly: it runs the ten module
  verifiers (about 15 seconds) and the JSON freshness check, and `--interactions` adds the
  behaviour suites. The gate exists as of this pass; before it, the suites had to be run
  one by one.
- **RAM and cold start are unmeasured for the engine.** The old README claims
  "15-25 MB RAM" and "<85 ms cold start". Neither can be checked from this tree, because
  there is no native host to run. The only cold-start numbers I have are for the
  JavaScript runner (section 2), and they do not transfer to Skia, SDL3 and wasmtime.
- **The numbers are generated now, and they were not before.** `README.md` and
  `apps/README.md` are written by `bash tools/os-measure.sh --write`, and
  `bash tools/os-measure.sh --check` fails when either drifts from the tree. Before this
  pass the README said 356 KB typewriter (the file is 500,748 B), quoted a "410 KB
  descent" and a `gallery3d` that do not exist in the tree, and gave DNA 224 KB
  (416,112 B); `docs/SUBMISSION_ANSWERS.md` carried the same figures and is corrected.
  Older prose elsewhere (`docs/ARCHITECTURE.md`, `skills/`) still quotes development-time
  sizes: trust `stat` over prose that this script does not generate.
- **The JSON export is new in this pass.** All ten `app.yantra.json` files were generated
  by `tools/export-json.mjs`, which instantiates each module and writes down the tree it
  built; `apps/*/app.json` were rewritten by the same tool and now carry byte counts, line
  counts and sha256 for both module and source. `node tools/export-json.mjs --check`
  proves each pair still matches. The documents are level L1 of a JSON parallel — nodes,
  parameters, draw commands — not a restorable source form.

## 5. Why the design is what it is

- **WebAssembly for safety.** The guest gets 32 host functions and nothing else (section
  3), so the security boundary is a list you can read in one screen. It is enforced in
  `host/host.nim`, which supplies the imports positionally and owns the tree.
- **Nim for a real compiled language with no tracing GC.** `sdk/yantra.nim` is what an
  app imports; `tools/build-wasm.sh:141` compiles it with `--mm:arc`. The app ships
  machine code, not source for a runtime to interpret.
- **One shared renderer instead of one runtime per app.** `render/native/engine.nim` is
  4,377 lines of the real drawing path for every app; `web/runner/runner.js` is 627 lines
  of a second implementation of the same contract. Two implementations of one protocol is
  how the protocol gets checked — `protocol/schema.nim` defines the 48 node kinds both
  must honour — and it is also why the web runner can stand in for the engine in a test.
  It is not evidence that the engine itself runs.

Read next: `README.md` for the claim, `docs/FILE-MAP.md` for what in this tree is source,
artifact, or dead weight.
