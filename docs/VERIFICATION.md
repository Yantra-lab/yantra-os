# Verification — what runs, what paints, what fails, and how it was measured

Every number on this page was measured on this machine at the time printed below, by the
command named beside it. Timings move between runs; sizes and hashes do not.

| | |
| :--- | :--- |
| measured | 2026-11-05, from 07:30 UTC — the desktop's rows re-measured at 10:40 UTC |
| machine | Intel Xeon Platinum 8559C, Linux, Node v22.23.4 |
| tree | `yantra-os/`, 12 apps |

---

## 1. Does each module run? — `bash verify_all.sh`

The verifier loads the shipped module in `web/runner/runner.js`, instantiates it, and reads
the UI tree the module built. It renders nothing.

| App | Module bytes | Live nodes | Draw bytes | Result |
| :--- | ---: | ---: | ---: | :---: |
| `calc` | 207,944 | 40 | 0 | PASS |
| `desktop` | 3,330,533 | 118 | 0 | PASS |
| `editor` | 227,220 | 40 | 0 | PASS |
| `files` | 302,539 | 3 | 20,715 | PASS |
| `gallery` | 212,826 | 77 | 2,983 | PASS |
| `gallery3d` | 182,808 | 88 | 0 | PASS |
| `notes` | 212,039 | 22 | 0 | PASS |
| `todo` | 227,216 | 41 | 0 | PASS |
| `chess` | 303,779 | — | — | **FAIL** |
| `descent` | 320,352 | — | — | **FAIL** |
| `dna` | 247,202 | — | — | **FAIL** |
| `typewriter` | 438,505 | — | — | **FAIL** |
| **12 apps** | **6,212,963** | **429** | **23,698** | **8/12** |

### The four failures, exactly

`chess`, `descent`, `dna` and `typewriter` trap with
`RuntimeError: memory access out of bounds`. In every case the trap happens **after** the app
has built part of its tree (typewriter: 4 nodes; descent: 8; dna: 15; chess: 80), so these are
not link failures.

**It is not the JavaScript host's imports.** The same four trap identically when every host
import is replaced by a permissive fallback that answers `0` to anything unimplemented:

```
new WebAssembly.Instance(mod, { env: new Proxy(knownImports, { get: (t,k) => k in t ? t[k] : () => 0 }) })
dna         -> memory access out of bounds (15 nodes built)
chess       -> memory access out of bounds (80 nodes built)
typewriter  -> memory access out of bounds (4 nodes built)
descent     -> memory access out of bounds (8 nodes built)
```

The same modules *are* rendered by the engine: `proofs/` holds the engine's PNG for each of
them. So the engine runs them and this host does not — an open gap, not a closed claim.
Rebuilding those four from their Sutra sources is the fix; it needs the Sutra compiler, which
this tree does not contain.

`desktop` used to be the sixth: it trapped with `unreachable` after 2 nodes, because the
shipped module was built when the desk was a catalogue viewer. It is now the Caelestia shell
(`apps/desktop/app.nim`, rebuilt with `tools/build-wasm.sh`), and it instantiates here with
**118 live nodes**. It needed two fixes that are part of this tree: the module imports the
compiler-rt helper `__multi3` (present only when the wasm32 builtins are linked), and it asks
the host for `y_ai_ready`/`y_ai`/`y_sys`/`y_sys_text` — imports `web/runner/runner.js` now
serves, answering `0` and `-1` ("no model here", "the browser cannot reach the machine").

## 2. Does each app paint? — `node tools/capture-shots.mjs --all`

Served over HTTP, opened in headless Chromium at 1440×900, 60 animation frames advanced,
then measured: how much of the window is ink that is not the page background, and how many
distinct colours are present.

| App | PNG bytes | Ink | Colours | State |
| :--- | ---: | ---: | ---: | :--- |
| `files` | 128,811 | 95.94 % | 299 | renders |
| `calc` | 27,566 | 55.38 % | 50 | renders |
| `notes` | 36,939 | 48.92 % | 85 | renders |
| `gallery` | 18,656 | 43.05 % | 61 | renders |
| `editor` | 39,449 | 39.02 % | 91 | renders |
| `todo` | 51,098 | 22.58 % | 70 | renders |
| `gallery3d` | 36,722 | 7.26 % | 108 | renders |
| `desktop` | 52,058 | 3.82 % | 163 | renders |
| chess, descent, dna, typewriter | — | — | — | trap before paint |

`desktop`'s ink is low on purpose: the DOM runner paints no SkSL wallpaper (the shader is a
GPU-class surface), so most of the screen is one fill there. The engine's proof
(`proofs/desktop.png`) is the picture that carries the wallpaper.

### What the canvas backend changed

Before this pass the browser host made a plain `<div>` for every canvas node and never read
the retained draw list, so a canvas app painted only its window background. Measured then,
by the same tool: `gallery` **0.27 % ink**; `chess`, `dna`, `editor` and `files` between
0.00 % and 0.27 %. Measured now: `gallery` **43.05 %**, `files` **95.94 %**, `editor`
**39.02 %**, `gallery3d` **7.26 %**.

`web/runner/paint2d.mjs` is the second consumer of the command stream (a port of
`libs/nimskia/src/skia_shim.cpp`'s `runCmds` onto Canvas2D); `web/runner/hostimports.mjs`
serves the host import table (the C math library from `host/wasmmath.nim`, `nim_write`,
`nim_exit`, the Sutra runtime). Before those files existed, **13 of 14 modules could not even
link** in a browser: they imported `nim_write`, `sutra_query`, `sqrt`, `sin` and friends,
and the runner offered none of them.

## 3. The test script

```bash
bash web/runner/run_tests.sh   # -> PASS web_runner
```

It runs `web/runner/test.mjs` (the counter suite). `examples/counter.wasm` is now **built
from source** in this tree — `examples/counter.nim` → 344,658 bytes in 1.5 s with
`tools/build-wasm.sh` — rather than copied from an old build. The todo suite is no longer
imported there: it asserts the pre-Sutra todo app's seed list, and the release's todo is a
Sutra app on records. That suite is stale by fact, and it is named as stale rather than
deleted.

## 4. What a PASS does and does not mean

A module-verifier PASS means the shipped bytes instantiate and the module's own start-up
code builds a UI tree. It says nothing about pixels. The capture table in §2 is the pixel
evidence, and it covers 8 of 12 apps because the other four never reach a first frame.

## 5. Reproducing this page

```bash
bash verify_all.sh                    # §1, about 15 s
node tools/capture-shots.mjs --all    # §2, about 2 min (also writes the PNGs)
bash web/runner/run_tests.sh          # §3
bash tools/os-measure.sh --check      # the README and apps/README.md must match the tree
node tools/export-json.mjs --check    # every app.yantra.json must match its module
```
