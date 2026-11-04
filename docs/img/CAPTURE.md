# Screenshots — how they were taken

**These are not mockups.** Every file in this folder is a real screenshot of a
shipped app, taken by [`tools/capture-shots.mjs`](../../tools/capture-shots.mjs),
which loads the app's actual `apps/<name>/app.wasm` in the repo's own browser
runner and photographs what it painted.

**Bluntly: these captures are the shipped `.wasm` modules rendered by the repo's
JavaScript web runner (`web/runner/`), NOT the native engine's Skia renderer.**
They prove the apps build, load and lay out through `web/runner/runner.js` in a
browser. They do not prove anything about `render/native` (SDL3 + Skia + Yoga).

## Reproduce

One command, from a checkout (any working directory — the script resolves every
path from its own location):

```sh
node tools/capture-shots.mjs
```

That rewrites `calc.png`, `desktop.png`, `notes.png`, `todo.png`,
`typewriter.png` and `manifest.json` in this folder, and exits `0` only if every
one of them painted something.

Other forms:

```sh
node tools/capture-shots.mjs --only todo          # re-shoot a single app
node tools/capture-shots.mjs --apps todo,calc     # re-shoot a list
node tools/capture-shots.mjs --all                # all ten apps; the five canvas-only ones report blank and exit 1
node tools/capture-shots.mjs --all --allow-blank  # also write the blank canvas-only shots, exit 0
node tools/capture-shots.mjs --frames 60 --viewport 1440x900
```

Exit codes: `0` = every requested app painted and the screenshot passed the
checks; `1` = an app failed to load, or painted a blank window, or two apps
produced byte-identical files; `2` = bad arguments.

### What the script actually does

1. Starts a tiny Node `http` static server on `127.0.0.1:0` (ephemeral port,
   read back from `server.address().port`) rooted at the repo (`yantra-os/`).
   No `npx`, no install, no `file://`.
2. Launches headless Chromium through Playwright, viewport **1440×900**,
   `deviceScaleFactor: 1`.
3. For each app: opens
   `http://127.0.0.1:<port>/web/runner/app.html?app=<name>`, waits for the
   runner's `#status` to say the module **loaded** and for the app to mount its
   `.y-window`, then advances **60 `requestAnimationFrame` ticks** (so animated
   scenes are mid-motion, not frame 0) and waits 150 ms more, then screenshots
   the viewport to `docs/img/<name>.png`.
4. Measures every PNG before accepting it — decode it in the browser and count
   distinct colours, luminance spread and the share of app-window pixels that
   differ from the window's dominant colour ("ink"). A shot is rejected as blank
   if it is ≤ 3000 bytes or its window has < 8 colours, luminance σ < 2.5, or
   < 0.5 % ink. It also fails if `#status` contains an error, or if two
   different apps produce byte-identical PNGs (a flat-image smell).
5. Prints a table (`app | wasm bytes | path | png bytes | pixels | ink |
   colours | state`) and writes [`manifest.json`](manifest.json) with the exact
   bytes, dimensions, stats and sha256 of each file plus the toolchain used.

`manifest.json` is generated — it describes the run that produced the PNGs next
to it.

## The captures

| file | app | what it is (one line) | kind | pixels | PNG bytes | window ink |
|---|---|---|---|---|---|---|
| [calc.png](calc.png) | Calculator — `apps/calc` | a 20-key grid (4 columns × 5 rows) built from one Nim component, themed with the shared design tokens | DOM | 1440×900 | 28,233 | 21.9 % |
| [desktop.png](desktop.png) | Desktop Shell — `apps/desktop` | the shell: wallpaper, menu bar, dock and a live clock; each icon opens an app through `AppView` | DOM | 1440×900 | ~55 k | 5.6 % |
| [notes.png](notes.png) | Notes — `apps/notes` | a two-pane notebook: grouped note list plus a bound textarea | DOM | 1440×900 | 47,333 | 33.2 % |
| [todo.png](todo.png) | Todos — `apps/todo` | a task list with add / toggle / filter / clear, a bound input and keyed rows | DOM | 1440×900 | 33,439 | 29.5 % |
| [typewriter.png](typewriter.png) | Marlowe 44 Typewriter — `apps/typewriter` | a letter-writing scene: DOM chrome (sheet no., line/column, keystrokes) over a canvas | DOM | 1440×900 | 208,939 | 32.1 % |

All five: viewport 1440×900 at 1×, **60 animation frames** advanced before the
shot, full-viewport screenshot (the runner's `App:` selector at the top is part
of the picture — that is the runner page itself).

`typewriter.png` shows the app's DOM chrome (title plaque, ribbon/sound buttons,
sheet, line and column readouts) over the typewriter's background. The typed
letter itself is drawn by the app as a canvas `Draw` command list, which the
dependency-free DOM runner does not rasterise — see below.

## The other five apps

`chess`, `dna`, `editor`, `files` and `gallery` all **load** (`#status` reports
`<app>.wasm · N KB loaded`) but paint only their window background through
`web/runner/`: they draw a canvas `Draw` command list (`K.CANVAS` /
`P.DRAW`), and `web/runner/runner.js` creates the canvas node as a plain
`<div>` with no 2-D backend. Measured on 2026-11-05 with
`node tools/capture-shots.mjs --all`:

| app | window ink | window colours | result |
|---|---|---|---|
| chess | 0.27 % | 42 | blank |
| dna | 0.27 % | 43 | blank |
| editor | 0.13 % | 7 | blank |
| files | 0.00 % | 3 | blank |
| gallery | 0.13 % | 7 | blank |

They are deliberately **not** in this folder: a picture of an empty window would
be honest but misleading. `node tools/capture-shots.mjs --all --allow-blank`
writes them if you want to see for yourself. Capturing those scenes needs the
canvas path (or the native renderer), not a different image.

## Reproducibility, honestly

Re-running the command reproduces **byte-identical** PNGs for `calc`, `notes`,
`todo` and `typewriter` (verified across repeated runs; the runner feeds apps a
fixed frame delta, so the scenes are deterministic). `desktop.png` is not
byte-identical: the shell renders a **live clock**, so about 0.1 % of its pixels
(the dock clock / date area) change between runs. Its file size therefore
wanders by a few KB. That is the app being alive, not the capture being faked.

## Toolchain used

| what | path |
|---|---|
| Node | v22.23.4 (`node`) |
| Playwright | `/home/ubuntu/yantra/open/node_modules/playwright/index.mjs` (package 1.64.1) |
| Chromium | `/home/ubuntu/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome` (launched headless with `--headless=new --no-sandbox --disable-gpu`) |

Those two absolute paths are the only machine-specific defaults in the script.
If your Playwright or Chromium lives elsewhere, override them — no code change:

```sh
PLAYWRIGHT_PATH=/path/to/node_modules/playwright node tools/capture-shots.mjs
CHROME_PATH=/path/to/chrome node tools/capture-shots.mjs
```

If neither `CHROME_PATH` nor the default exists, the script falls back to
browsers it finds under `~/.cache/ms-playwright/` (including
`chromium_headless_shell-*`), then to Playwright's own bundled browser, and
prints every launch attempt it tried before giving up.

## Verifying the pictures without eyes

The PNGs are ordinary 8-bit RGB PNGs (colour type 2). Their IHDR header
(bytes 16–23) says width 1440, height 900 for every file; they are 28 KB–209 KB,
all different sizes, all different sha256. Nothing here is a resized or
recoloured copy of another file, and nothing was taken from any other
repository — in particular, not from a different implementation's screenshot
folder.

A last aside: [`web/runner/app.html`](../../web/runner/app.html) gained
`editor` and `files` options in its `App:` dropdown so all ten apps are
selectable there. The captures do not depend on that change (the page has always
accepted `?app=<name>`).
