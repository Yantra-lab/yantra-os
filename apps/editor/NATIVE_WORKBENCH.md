# Native Editor workbench

This package's proof is the **real native Desktop**, not a browser, DOM or
preview harness. `render/native/t_workbench_desktop.nim` starts
`apps/desktop/app.wasm`, opens **Explore apps → Yantra Studio IDE**, and drives
the checked-in `apps/editor/app.wasm` inside that window with wasmtime and Skia.
It never invokes `behavior.mjs`, `export-json.mjs` or a JavaScript runner.

## Actor and source binding

The harness uses a private Atlas space named `@workbench-desktop-native` and
creates the ordinary Atlas person `desktop-user`. Before starting the desktop,
it performs the production binding used by the native Sutra host:

```nim
serveFromAtlas(a)
let registry = childApps(a, person)
registry.registerChild("y:editor", "y:@workbench-desktop-native/editor.Editor")
childAppHook = proc (parent: App; source, path: string; child: App) =
  registry.attachChild(parent, source, path, child)
```

The local source id `y:editor` resolves to the checked-in module, while
`attachChild` opens an Atlas `openLive` principal for that Sutra interpreter.
An explicit address, not an app-name lookup, connects those two facts.
`Doc` and `Workbench` rows default to that person's owner. Generated cells stay
private and their versions' author is `desktop-user`; a second person cannot
resolve them. A failed build has no wasm or AppView.

Every source import uses exactly 49 cells. The module currently proven here is
300,045 bytes with SHA-256
`dffe0320f212d508d785f3f7c531c17e8be8414828ac23f34555613d2bbdcf04`.
The harness's first assertion compares it byte-for-byte with the
`Atlas.build(..., "wasm")` result.

## Build and run from the repository root

Use a **private** PostgreSQL database and compiler `TMPDIR`; this proof must not
run against the shared development database. Seed the Sutra vocabulary in that
database first (`nim r tools/atlas.nim seed`). Build `tools/osproof` and the
native harness with the wrapper `-p` paths documented by `tools/os.sh` and
`tools/gate-ritual.sh`, then:

```sh
export YANTRA_DB='<private libpq connection string>'
export TMPDIR='<private compiler scratch>'
export NIMONY_BIN='<absolute Nimony bin directory>'

# Import the responsive source into a fresh private application space.
tools/osproof import @workbench-desktop-native editor yantra-os/apps/editor/app.nim
tools/osproof build @workbench-desktop-native/editor.Editor \
  yantra-os/apps/editor/app.wasm

# The installed native, headless distribution proof.
render/native/build/t_workbench_desktop

# Additionally regenerate app.json, app.yantra.json and the three PNGs from
# live native UI state, then settle the desktop's actual transition frames.
render/native/build/t_workbench_desktop --export
```

The harness starts the desktop at 1920×1080. The measured floating Editor's
AppView is 980×700; the Editor root deliberately uses `grow = 1` rather than a input-only screenshot size. A normal run asserts 24 checks and returns 0 failed.
An export run adds the three actual `savePixels` assertions: 27 checks, 0 failed.
The independently run `host/sutra/tests/t_workbench.nim` remains 11 checks,
0 failed, and `render/native/t_sutra_children.nim` remains 15 checks, 0 failed.

## What the desktop run covers

- Three owner-scoped `Doc` records created by the actual module.
- Opening `highlight.nim` and receiving its source in the native edit buffer.
- Honest no-match search, exact `theme.nim` document search, and clearing it.
- Editing without an implicit database overwrite, then restoring via Revert.
- An intentionally misspelled `sise` property producing the real compiler's
  `did you mean \`size\`` diagnostic, without preview or fabricated wasm.
- Corrected source producing real wasm and a native child rendering V1.
- A second source edit producing a different module and replacing the child
  with V2 through `workbench3.Preview`.

## Evidence files

All three images are the whole native Desktop, not cropped child substitutes:

- `proofs/editor.png`: an opened owner-scoped document in the Editor window.
- `proofs/editor-error.png`: private root and genuine compiler diagnostics.
- `proofs/editor-preview.png`: successful second build and real rendered V2.

`app.json` preserves its authored design fields and gains measured native
source/module/node provenance. `app.yantra.json` is the 512-node native L1 twin
read from the running module's actual host tree; no DOM or JavaScript exporter
is involved. Both carry the `t_workbench_desktop.nim --export` provenance.
