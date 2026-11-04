# The applications

16 applications. Each folder holds the same four things:

| File | What it is |
| :--- | :--- |
| `app.nim` | the source, written against the SDK |
| `app.wasm` | the compiled module that this repository ships and verifies |
| `app.json` | the launcher manifest: id, name, icon, tint, window, module hash |
| `app.yantra.json` | the same app as a document, exported from the running module |

Every number below is measured — `bash tools/os-measure.sh` regenerates this file and
`bash tools/os-measure.sh --check` fails when it has drifted from the tree.

| App | What it is | Module bytes | KiB | Source | Live nodes | Draw bytes | Verifier |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | :---: |
| [`calc`](calc/app.nim) | a calculator: chained arithmetic, percent, sign, clear, backspace | 207,944 | 203.1 | 208 lines | 40 | — | PASS |
| [`chess`](chess/app.nim) | a chess study: full move validation, castling, en passant, promotion, check and mate | 303,779 | 296.7 | 649 lines | — | — | FAIL |
| [`descent`](descent/app.nim) | gradient descent running: a loss landscape, steps, learning rate, momentum | 320,352 | 312.8 | 372 lines | — | — | FAIL |
| [`desktop`](desktop/app.nim) | the shell: an Arc sidebar, a Caelestia bar, a shader wallpaper, windows that float or tile | 1,258,642 | 1,229.1 | 2,366 lines | 242 | — | PASS |
| [`dna`](dna/app.nim) | a 3-D DNA helix: rotate, pick a base, unzip, replicate, rejoin | 247,202 | 241.4 | 291 lines | — | — | FAIL |
| [`editor`](editor/app.nim) | a code editor: open, edit, save, line and column status | 257,891 | 251.8 | 415 lines | 73 | — | PASS |
| [`files`](files/app.nim) | a file manager: browse, select, open | 302,539 | 295.4 | 215 lines | 3 | 20,715 | PASS |
| [`gallery`](gallery/app.nim) | a 3-D exhibition hall: rooms, spotlights, paintings, guided tour | 190,722 | 186.3 | 174 lines | — | — | FAIL |
| [`gallery3d`](gallery3d/app.nim) | a 3-D hall: a corridor of paintings walked with keys or on-screen pads | 182,808 | 178.5 | 128 lines | 88 | — | PASS |
| [`kart`](kart/app.nim) | a lap racer: a circuit as arithmetic, pseudo-3D road, throttle and brake, three laps | 130,505 | 127.4 | 609 lines | 10 | 94,153 | PASS |
| [`notes`](notes/app.nim) | notes: a text surface, line count, save | 211,378 | 206.4 | 155 lines | 39 | — | PASS |
| [`ocean`](ocean/app.nim) | the open sea: six cascades of swell, Jacobian whitecaps, a sunset sky, one shader | 162,604 | 158.8 | 325 lines | — | — | FAIL |
| [`orrery`](orrery/app.nim) | a brass orrery: Kepler-solved planets, real periods, a gear train, a live almanac | 194,908 | 190.3 | 302 lines | — | — | FAIL |
| [`poster`](poster/app.nim) |  | 291,952 | 285.1 | 426 lines | — | — | FAIL |
| [`todo`](todo/app.nim) | a reactive todo list: add, check, filter | 227,216 | 221.9 | 167 lines | 41 | — | PASS |
| [`typewriter`](typewriter/app.nim) | the Marlowe 44: a procedural desk, cotton-bond paper, ink strikes, type bars | 438,505 | 428.2 | 268 lines | — | — | FAIL |
| **total** | | **4,928,947** | **4,813.4** | **7,070 lines** | **536** | **114,868** | **8/16** |

Run one app on its own with `node tools/verify-wasm.mjs apps/<name>`, or all of them
with `bash verify_all.sh`. Behaviour suites live in `../web/runner/tests/`.
