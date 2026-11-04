# 01 — Build, run and visually verify a Yantra app

*Every command on this page was run from `C:\Users\Sanskar\DEV\yantra` on branch
`agent/sanskar-100html-ports`. Output marked **[measured]** is real console output captured during
that run. Where a binary that folklore expects does not exist, this page says so instead of
inventing a command.*

---

## 1. The one build command

`tools/build-wasm.sh` is the only supported way to turn a `.nim` app into a `.wasm`.
Its usage line is `[flags]`-terminated and takes exactly two positional arguments:

```
./tools/build-wasm.sh <src.nim> <out.wasm> [--release|--no-libc|--opt]
```

### Which `bash` to use

The build needs a **POSIX shell**, MSVC paths converted, and `clang` + `nim` on `PATH`.
Two traps, both measured on this machine:

* The `bash` that is first on `PATH` here is **WSL** (`/bin/bash`, `/mnt/c/...`). It cannot
  see `C:/Users/...`, so `pwd -W` has nothing useful to emit and the build fails with
  `cd: /c/Users/Sanskar/DEV/yantra: No such file or directory`.
* The repo ships its own **MSYS2** at `third_party/msys64`. That is the shell the repo's own
  scripts assume (`render/native/run_tests.sh`, every `libs/*/tests/run_tests.sh`).

A **login** shell (`-l`) resets `PATH` and loses `clang`/`nim`. Use `-c` (inherited `PATH`).

### Windows (PowerShell) — verified working

```powershell
& "C:\Users\Sanskar\DEV\yantra\third_party\msys64\usr\bin\bash.exe" -c `
  'cd /c/Users/Sanskar/DEV/yantra && bash tools/build-wasm.sh examples/hello.nim scratch/_probe/hello.wasm'
```

### bash (MSYS, inside the repo)

```bash
cd /c/Users/Sanskar/DEV/yantra
bash tools/build-wasm.sh examples/hello.nim scratch/_probe/hello.wasm
```

### Flags

| Flag | Effect (from the script itself, not from docs) |
|---|---|
| `--release` | `-O3` for clang **and** Nim `-d:release --opt:speed`; then a `wasm-opt -Oz --strip-debug --strip-producers` pass if `wasm-opt` is on `PATH` |
| `--opt` | `-O2` clang only (no Nim `-d:release`) — the script's default is already `-O2`, so this is a no-op unless you want it explicit |
| `--no-libc` | link **no** mini-libc at all; for pure-computation modules. Saves an unused `yantra_log` import (~18 KB) |
| anything else | `build-wasm: unknown flag '<x>'` on stderr, exit 1 |

Two environment knobs exist: `YANTRA_NIM_FLAGS` injects extra Nim flags (the nimcache
directory name is a hash of them, so a flag change is a different cache by construction),
and `YANTRA_WASM_OPT_TIMEOUT` (default 60 s) bounds the `wasm-opt` pass.

### Measured output — debug build, ~7–10 s

```
build-wasm: compiling mini-libc (object file)
build-wasm: compiling Nim -> wasm
build-wasm: wrote scratch/_probe/hello.wasm (204306 bytes)

real	0m7.194s
```

A cold run (first invocation of the session, nimcache cold) measured **9.9 s**:

```
real	0m9.882s
```

**Treat ~10 s as the expected cost.** It is not hung.

### A failed build leaves the old `.wasm` in place

> **CORRECTED 2026-10-03.** This chapter quoted the `build-wasm: wrote …` line in three
> sample outputs but never made it a rule. **It is a rule, and it is the one that protects
> every other measurement in this skill.**
>
> **A failed wasm build does not remove or truncate the previous `.wasm`. The old file stays
> exactly where it is, and every downstream tool — `verify-wasm.mjs`, `drive.exe`, a pixel
> diff — renders the stale artifact happily.** It exits 0. It writes a full-size raw. It
> produces a node tree. Every signal looks healthy, and it is all describing code you no
> longer have.
>
> The real occurrence: **a stale `hello.wasm` once hid an SDK that did not compile** (AGENTS.md
> rule 2 exists because of it).
>
> **Before trusting any frame or any harness output: confirm the build printed
> `build-wasm: wrote <path> (<n> bytes)`.** `tools/guard-29.ps1:65-69` is the pattern to copy —
> it asserts the module exists *and* records its last-write time, because "a stale artifact
> the build failed to replace is exactly the failure mode rule 2 exists to catch."

### Measured output — `--release`, ~9 s

```
build-wasm: compiling mini-libc (object file)
build-wasm: compiling Nim -> wasm
build-wasm: wasm-opt not found, skipping size squeeze (optional)
build-wasm: wrote .../probe_hello_rel.wasm (79606 bytes)

real	0m9.280s
```

`wasm-opt not found` is **not** an error — the script calls it "optional" and keeps the
unoptimised module. Without `--release` the same warning does not appear because that
whole branch is skipped.

### `--no-libc`, measured

```
build-wasm: --no-libc, skipping mini-libc (pure-computation module)
build-wasm: compiling Nim -> wasm
build-wasm: wrote scratch/_probe/counter.wasm (213268 bytes)
```

### `/tmp` is a trap in the output argument

`build-wasm.sh` reports the output path through `pwd -W`. Asking for `/tmp/probe_hello.wasm`
printed `.../third_party/msys64/tmp/probe_hello.wasm` while the file actually landed at
`C:\Users\Sanskar\AppData\Local\Temp\probe_hello.wasm` (208223 bytes on disk vs 204312 in the
log). **Always give a path inside the repo**, and `cd` to the repo root first.

### Build side-effects you must clean up

Each build drops, next to the source or output:

* `minilibc.o` (next to the `.nim` source),
* `nimcache<8-hex-digest>/` (next to the `.nim` source),
* `panicoverride.nim` (copied next to the source if absent).

All three are gitignored (`minilibc.o`, `nimcache*/`, `panicoverride.nim`). The `just examples`
recipe deletes the first two explicitly after building.

---

## 2. Where the wasm goes, and how the host runs it

The `.wasm` is a **freestanding `wasm32-unknown-unknown` module** — no OS, no libc beyond the
mini-libc in `sdk/minilibc`. It cannot touch screen, disk or network. Everything it does is a
call out to host functions:

```
y_node_create(kind)      -> make a node, get a number back
y_node_child(parent, kid) -> attach it
y_node_set_str(node, prop, text, len)
y_node_set_i32(node, prop, value)
y_node_set_f32(node, prop, value)
y_node_on(node, event, handler)
yantra_log(msg, len)
```

**That import table is the security boundary.** A module that imports anything else is refused
at instantiation. Measured on a real build of `examples/hello.nim` (see §5):

```
imports : y_node_create, y_node_child, y_node_set_str, y_node_set_i32, y_node_on, yantra_log
```

Nothing else. The native host loads the module through wasmtime
(`libs/nimwasmtime`, vendored runtime), calls `yantra_main()` inside the sandbox, collects the
calls into a node tree (`host/tree.nim`), lays it out with Yoga, paints it with Skia
(`render/native/engine.nim`), and presents through SDL3. Callbacks run the other way through
`yantra_dispatch(handler)`.

Two paths exist for the output file:

* **next to the source** — `examples/hello.wasm`, which is what `just test` and
  `render/native/run_tests.sh` build and then run;
* **anywhere you like** — every native tool takes the path as `argv[1]`. This chapter builds
  into `scratch/_probe/` so probes never pollute `examples/`.

---

## 3. Running natively

### The real binary names

Source `render/native/yantra_run.nim` prints its own usage as `yantra <app.wasm> [--watch]`,
but `render/native/run_tests.sh` compiles it to `build/yantra.exe`, **not** `yantra_run.exe`:

```
if nim c $FLAGS --app:gui -o:"$HERE_W/build/yantra.exe" "$HERE_W/yantra_run.nim" ...
```

A second copy exists as `render/native/yantra_run.exe` (5.2 MB, 2026-10-01), outside `build/`.
Both are checked-out binaries; **neither is a git-tracked source of truth** and both are stale
by definition. Prefer `build/yantra.exe`.

> **CORRECTED 2026-10-03 — there is a third copy, and this chapter missed it.**
> `render/native/build/desktop/yantra_run.exe` exists (5 211 385 bytes) and is the path
> `skills/yantra/SKILL.md:29` prints. The `desktop/` directory also holds the runtime DLL
> set, so it is the self-contained deployment layout. `render/native/build/yantra_run.exe`
> does **not** exist — the binary is one directory deeper than this chapter implied.
> All three copies are prebuilt; per AGENTS.md rule 2 none is evidence.

### Required `PATH` (measured)

`yantra.exe` loads `wasmtime.dll` and the Skia DLLs at runtime, so it will not start without
this. Order matters — first four entries, then the existing `PATH`:

```powershell
$WS = 'C:\Users\Sanskar\DEV\yantra'
$env:PATH = "$WS\render\native\build;$WS\third_party\skia-build\pkg\mingw-w64-x86_64-skia\mingw64\bin;$WS\third_party\msys64\mingw64\bin;$WS\libs\nimwasmtime\vendor\wasmtime-v19.0.2-x86_64-windows-c-api\lib;" + $env:PATH
```

Run it from `render/native/build/` — the DLLs are copied there by the test script.

### Exact invocation

```powershell
& "$WS\render\native\build\yantra.exe" "$WS\scratch\_probe\hello.wasm"
& "$WS\render\native\build\yantra.exe" "$WS\scratch\_probe\hello.wasm" --watch   # rebuild + hot-swap on save
```

### What it shows — measured

* **Window**: a real native SDL3 window (Skia on OpenGL when a GPU is available, CPU frames
  otherwise or with `YANTRA_CPU=1`), sized from the app's window props, defaulting to 800x600.
* **stdout/stderr: completely silent.** A successful 6-second run produced empty stdout and
  empty stderr and was still running when killed. Silence *is* the healthy signal — the app
  says nothing; only `yantra_log()` output and crashes would appear.

> **CORRECTED 2026-10-03 — do not wait for `yantra_log()` output under a harness.** What
> this bullet says, in its own words: *"only `yantra_log()` output and crashes would appear."*
> That is true of nothing you can observe today. **`log()` compiles, is callable, and nothing
> in the repo ever reads it.**
>
> - `host/host.nim:628` — `cbLog` does `host.logs.add readStr(...)`. The only writer.
> - `host/host.nim:1029` — `result["yantra_log"] = ImportSpec(…, cb: cbLog)`.
> - The only reader anywhere is `render/native/t_mpopen.nim:173`, and it reads a *different*
>   log — the engine's capability log `e.s.logs`, not `host.logs`.
>
> No runner prints the collected lines. It is also expensive: one `log()` call measured
> **+15,660 bytes**, about **7% of a ~215 KB module**.
>
> **Instrument by drawing something or by reading pixels.** For a headless frame, `drive.exe`
> gives you three real instruments with no app code at all: the `boxes` verb, the `crash`
> verb, and `DUMP_GEOM=1`. Any procedure that says "add a `log()` to see what happened" is
> wrong.
* **Input**: real mouse, wheel, keyboard, IME, drag-and-drop, clipboard, gamepad, pointer lock,
  system theme, and the app's own window chrome (frameless / menu / badge / URL scheme).
* **Idle cost**: zero — the loop sleeps until input, a caret blink, or the next motion frame.

### Failure messages — measured

```
> yantra.exe
usage: yantra <app.wasm> [--watch]
exit=2

> yantra.exe <path that does not exist>
no such app: C:\...\nope.wasm
exit=2
```

Both come from `yantra_run.nim` itself and use exit code **2**. A missing file is reported
before SDL is even initialised, so this is safe to assert on in a script.

`--watch` echoes one line before the window appears:

```
watching <dir> — save a .nim file to reload it
```

---

## 4. Screenshot verification

### The tools that actually exist

`render/native/build/` was listed directly. **`shot.exe` is NOT there** — the source
`render/native/shot.nim` exists but no script in the repo builds it, and it cannot be rebuilt
in this checkout (see the caveat below). What *is* present and working:

| Binary | Source | Job |
|---|---|---|
| `build/mpdrive.exe` | `render/native/drive.nim` | **the working screenshot tool** — real pointer input + raw dump |
| `build/mpdrive_unwrap.exe` | same | variant |
| `build/shot_excal.exe` | an older `shot.nim` | prebuilt, **known stale** (see below) |
| `render/native/yantra_run.exe` | `yantra_run.nim` | live window runner (§3) |
| `build/yantra.exe` | `yantra_run.nim` | live window runner, current |

> **Caveat, measured.** Rebuilding any of these from source fails here with
> `fatal error: SDL3/SDL.h: No such file or directory` (also `curl/curl.h`, `Jolt/Jolt.h`) —
> those MSYS2 dev packages are not installed under `third_party/msys64/mingw64/include`, and
> no copy exists anywhere in the repo. Skia headers *do* resolve. So today these native
> binaries are the only screenshot path; do not promise a rebuild in a report.

### Step 1 — render a frame to a raw BGRA dump

> **CORRECTED 2026-10-03 — this dump MUST be swapped before any diff tool reads it.**
> What this chapter used to say was only that *"the raw dump is BGRA, not PNG"*, without
> saying that **no diff tool in the repo swaps for you**.
>
> `render/native/drive.nim:191-193` does
> `var bytes = newString(px.len * 4)` / `copyMem(addr bytes[0], addr px[0], bytes.len)` on a
> `seq[uint32]` of Skia pixels. Skia's `SkColor` is `0xAARRGGBB`, and little-endian memory
> reverses it, so **the bytes on disk are B, G, R, A**.
>
> `tools/pngdiff.mjs:100-103` and `tools/refdiff.mjs:90-94` both read bytes 0, 1, 2 as
> **R, G, B** — **no swap**. Feed them an unswapped raw and the headline number is computed
> with **R and B exchanged**, and it looks entirely plausible.
>
> Measured on one port, same reference, the swap the only difference:
> **91.45% unswapped vs 72.83% swapped.**
>
> ```
> node tools/rawswap.mjs <in_bgra.raw> <out_sw.raw>
> ```
>
> **Always, first, before any diff.** A double swap is also a trap: `tools/floor.mjs:35`
> guards on the `*_bgra.raw` filename suffix because swapping a swapped frame produced a
> 99.22% reading while `pngdiff` on the same file said 50.49%. Full treatment, including the
> headline-vs-band-map distinction, is `21-visual-parity-verification.md` §2 and §4.

```
mpdrive.exe <app.wasm> <out.raw> <width> <height> <scale> "<verb;verb;verb>"
```

The 5th argument is **scale**, not frames. Verbatim from `drive.nim`. The verb string
separator is **`;`, never `,`** — a verb's own arguments contain commas (`click:400,400`), so
splitting on commas tears a verb in half and the driver silently does nothing.

Measured, rendering `examples/hello.nim` freshly built to wasm:

```powershell
& .\render\native\build\mpdrive.exe scratch\_probe\hello.wasm scratch\_probe\hello.raw 800 600 1 "wait:4"
```

```
paramCount=6 script=[wait:4]

exit=0
```

Output file: **1 920 000 bytes** = 800 x 600 x 4, headerless, BGRA per pixel.

Verbs (complete, from `drive.nim`): `boxes`, `crash`, `handlers`, `probe`, `click:X,Y`,
`down:X,Y`, `up:X,Y`, `move:X,Y`, `drag:X1,Y1,X2,Y2` (8 interpolated moves), `key:N`,
`text:S`, `wait:N`. Diagnostics go to **stderr**; a final `frame()` is always painted after the
verb batch, so input effects show up without a trailing `wait` — but the wasm processes queued
events on its own update, so keep `wait:2..4` after animated input.

**Prove the frame is not blank.** A uniform frame "passes" every exit-code check while drawing
nothing — this is the single most misleading failure in the renderer (`docs/renderer.md` §5).
Count distinct pixels; measured on the frame above:

```
distinct colours: 89
```

A real hello-world frame has tens of distinct colours. One, or two, means nothing was drawn.

### Step 2 — the `demo` mode built into `shot.nim`

`shot.nim`'s signature is `shot app.wasm out.raw width height scale [demo]`. The 6th argument
`demo` fakes a realistic state before painting: it clicks the first input node (kind 6), types
`Apply to IITM IC`, presses Enter (key 13), types `Book the demo slot`, relayouts, then clicks
the first checkbox (kind 14). It paints **one** frame and exits.

> **`shot.exe` DOES NOT EXIST. Do not run this command.**
>
> | asked for | exists? |
> |---|---|
> | `render/native/shot.nim` (source) | **yes** |
> | `render/native/build/shot.exe` | **NO — absent from the tree** |
> | `render/native/build/desktop/yantra_run.exe` | **yes** (5 211 385 bytes) |
> | `render/native/build/yantra_run.exe` | no |
> | `render/native/build/mpdrive.exe` | **yes** |
> | `render/native/build/drive.exe` | **yes** |
> | `render/native/build/shot_excal.exe` | yes — **prebuilt and stale** |
>
> `skills/yantra/SKILL.md:30` still prints `render/native/build/shot.exe` as a runnable
> command. **It is not runnable.** Use `drive.exe` or `mpdrive.exe` instead — both take the
> same argument shape, `drive app.wasm out.raw W H SCALE SCRIPT`, documented in
> `render/native/drive.nim:1-25`.

`shot.nim`'s own header line 1 calls its output a *"raw BGRA dump"*, which is the same
B,G,R,A convention `drive.nim` produces and the reason for §3's swap rule.

This is the scripted-input path `shot.nim` documents — but see the caveat above: **`shot.exe` is
not built in this checkout**, so this exact command cannot be run today. `mpdrive.exe` is the
working equivalent and takes arbitrary verbs instead of one hardcoded `demo` sequence:

```powershell
& .\render\native\build\mpdrive.exe scratch\_probe\hello.wasm scratch\_probe\demo.raw 800 600 1 "wait:4;click:400,300;wait:3"
```

Use `boxes` first to learn where things actually landed — it prints ground truth about the
laid-out tree with no app instrumentation at all:

```powershell
& .\render\native\build\mpdrive.exe app.wasm out.raw 800 600 1 "boxes"
```

### Step 3 — turn the `.raw` into a `.png` you can actually look at

`shot.nim`/`drive.nim` write **raw BGRA**, not PNG. Nothing in the repo converts it (the only
reader is `scratch/decode_oracle.py`), so this PowerShell one-liner is the bridge. **Verified**
end to end: `hello.raw` (1 920 000 bytes) -> `hello.png` (7 888 bytes), same 800x600.

```powershell
Add-Type -AssemblyName System.Drawing
$raw = 'C:\...\hello.raw'; $w = 800; $h = 600
$bytes = [byte[]][System.IO.File]::ReadAllBytes($raw)
$bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
$rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$bmp.UnlockBits($data)
$bmp.Save('C:\...\hello.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
```

Rules that make it work:

* **The raw dump is headerless.** You must supply `w`/`h` yourself. They are
  `width * scale` and `height * scale` — for `800 600 1` that is 800x600.
* Use `Format32bppRgb` on **both** the bitmap and the `LockBits`, so the bytes land unchanged
  (B, G, R, A) with a stride of exactly `w * 4`. Mixing pixel formats is what produces the
  "colours are swapped" PNG.
* Sanity check: `(Get-Item $raw).Length` must equal `$w * $h * 4`. Measured: 1 920 000 = 800x600x4.
* Assert `$bytes.Length -le $data.Stride * $h` before copying, or a stale/larger dump writes
  past the locked buffer.

> **CORRECTED 2026-10-03 — reference PNGs are 3 channels, not 4.** Anything that *decodes* a
> reference PNG rather than dumping one needs this. **Every reference under
> `.board/frames/ref*.png` is colourType 2 — RGB, 3 channels, depth 8** (verified on all ten
> files in that directory).
>
> The usual assumption `stride = w * 4 + 1` therefore fails the length check and throws.
> **`w * 3 + 1` is the working stride.** `tools/refdiff.mjs:40` is the correct pattern —
> it branches on the header: `const ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]`, then
> `stride = W * ch` (`:43`).
>
> And record the clock the reference was captured at. **Two independent headless captures of
> the SAME animated page at the same nominal 800 ms budget differ from each other by 2.13%**
> — 22,288 of 1,044,480 pixels. That is the instrument's noise floor. Use
> `tools/capture-ref.ps1`, which takes the virtual-time budget as an argument and prints it,
> and never compare against a reference whose clock you did not record.

Then **look at the PNG** with the image viewer. A valid PNG on disk is not evidence that
anything was drawn (§5 of this chapter is about that trap; `docs/renderer.md` §5 has the
full offscreen-3D table).

### Stale-harness warning (already paid for once)

`apps/minipaint/ENGINE-ISSUES.md` §5: `build/shot_excal.exe` predated a verb added to the
shim, so a cog shape rendered empty **with no error anywhere** — the wasm was correct, the
harness was not. A screenshot proves what the *harness* drew. When a shape goes missing,
compare the harness binary's build time with the shim's before believing your shape code.

---

## 5. Node-based headless verification

### What is actually in `examples/`

```
protocol.mjs        GENERATED — kind/prop/event constant tables (DO NOT EDIT; edit protocol/schema.nim)
verify_hello.mjs    asserts the whole tree of examples/hello.nim, then clicks the button
verify_counter.mjs  6 checks on examples/counter.nim
verify_cube3d.mjs   3D scene tree
verify_animate.mjs  animation vocabulary
verify_noimport.mjs proves no unexpected import appears
```

### The technique

A Yantra module has no window and no OS, so **Node can be the host**. `verify_hello.mjs`:

1. `WebAssembly.compile(readFileSync(argv[2]))`, then `WebAssembly.instantiate(mod, { env })`
   with an `env` object of the seven host functions that *records* every call.
2. The `env` is wrapped in a `Proxy`. Any import it did not anticipate is pushed onto an
   `unknown` array and stubbed — so a new dependency shows up as a **failure**, not a mystery.
3. `inst.exports.yantra_main()` runs the app; the recorded calls are the tree.
4. Asserts are made against that tree using the numeric constants from `protocol.mjs`
   (`K.WINDOW`, `P.TEXT`, ...), never against hardcoded integers.
5. **The callback direction too**: `inst.exports.yantra_dispatch(h.handler)` fires a click back
   into the sandbox and asserts the tree changed. That direction is the easy one to get wrong.
6. `process.exit(1)` unless every check passed — so it drops straight into `just test`.

Two details worth copying: arrays are compared with `checkJson` (`JSON.stringify`), because
`===` on two distinct arrays is reference equality and the first version of this verifier
reported a failure on a correct tree for exactly that reason; and `check('no unexpected
imports', unknown.length, 0)` is asserted last.

### Exact command — measured

```powershell
cd C:\Users\Sanskar\DEV\yantra
node examples/verify_hello.mjs scratch/_probe/hello.wasm
```

```
size    : 204306 bytes
imports : y_node_create, y_node_child, y_node_set_str, y_node_set_i32, y_node_on, yantra_log

--- tree the engine received ---
nodes: 7
  [0] kind=0 children=[1] props={"0":"Hello, Yantra","3":800,"4":600,"6":1973806}
  [1] kind=1 children=[2,3,4,5,6] props={}
  [2] kind=3 children=[] props={"0":"Hello, Yantra","6":16777215,"7":32}
  [3] kind=3 children=[] props={"0":"This UI was built inside a WebAssembly sandbox.","6":10132144,"7":16}
  [4] kind=4 children=[] props={"0":"Click me"}
  [5] kind=5 children=[] props={"0":"logo.png","3":64,"4":64,"10":"logo.png"}
  [6] kind=6 children=[] props={"0":"Your name","7":14}

--- assertions ---
OK   node count: got 7, want 7
OK   root is a window: got 0, want 0
OK   window title: got "Hello, Yantra", want "Hello, Yantra"
...
OK   button registered a click handler: got 0, want 0
OK   title updated after click: got "Clicked 1 time(s)", want "Clicked 1 time(s)"
OK   engine received the log: got "button clicked: 1", want "button clicked: 1"
OK   second click increments: got "Clicked 2 time(s)", want "Clicked 2 time(s)"
OK   no unexpected imports: got 0, want 0

=== 24/24 checks passed ===
```

Second example, measured:

```
> node examples/verify_counter.mjs scratch/_probe/counter.wasm
=== 6/6 checks passed ===
```

And a **negative control**, because an assertion that cannot fail is not a test:

```
> node examples/verify_counter.mjs scratch/_probe/hello.wasm
FAIL: window title Counter
```

### What this catches that a build cannot

It proves the **module boundary contract**: the app called only host functions, built the tree
it intended, and its callbacks fire. It does **not** prove pixels. Only §4 proves pixels.
For "done", you want both.

### The one thing it cannot catch: a module with no `yantra_main`

> **CORRECTED 2026-10-03.** This chapter's step 3 says `inst.exports.yantra_main()` and its
> sample output shows a tree — but it never stated the requirement that makes that work, and
> a reader writing a minimal app from the prose can get it wrong and still pass everything.
>
> **`host/host.nim:1188` calls `callVoid(inst, "yantra_main")` unconditionally.** An app
> written as `when isMainModule: main()` exports **`NimMainModule`** instead. It **compiles
> clean, passes every headless check in this chapter, and never renders a single frame.**
> One port sat in exactly that state — a **2,005-byte stub** that built and passed while
> rendering nothing.
>
> ```nim
> proc yantra_main*() {.exportc: "yantra_main".} = main()   # this
> # not: when isMainModule: main()
> ```
>
> **The check:** `WebAssembly.Module.exports()` returns **`false`** for `yantra_main`.
> `tools/verify-wasm.mjs:406-407` prints this verbatim —
> `entry  : yantra_main present = false, NimMainModule present = true` — so
> `yantra_main present = false` is a **fail**, whatever else the harness says.

### `verify-wasm.mjs` does enforce the host's import gate

> **CORRECTED 2026-10-03.** `23-wasm-import-gate.md` used to state that this tool "does NOT
> enforce this gate and will report such a module as healthy." **It now does.**
> `tools/verify-wasm.mjs:146-161` parses the real `importTable()` out of `host/host.nim` at
> run time, and `:184-229` refuses with exit 1 **before instantiating** if the host would
> refuse. A green `verify-wasm.mjs` run therefore does mean "the real host would load this
> module" — which is a stronger statement than the one that chapter used to make. What it
> still never proves is layout or pixels: the mock runs no Yoga and no Skia.

---

## 5b. Five engine facts that will silently waste your day

Every one of these compiles. None of them errors. All five have cost real rounds.

### 1. `frameDt()` is the clock. `yantra_get_dt()` reads 0.

> **CORRECTED 2026-10-03.** Chapters teaching animation said "advance the clock" without
> naming the right one. `sdk/ui/input.nim:45` — `proc frameDt*(): float32 = yInput(7, 0)` —
> is the live clock. `sdk/core/runtime.nim:75` declares `yantra_get_dt` as an `importc`, whose
> only writer is `setFrameDt` (`host/host.nim:1211-1213`, registered at `host/host.nim:1024`).
> **Repo-wide `setFrameDt` appears in exactly two files:** `render/render_qml.nim:42` (the
> legacy Qt path) and `host/t_run_hello.nim:107`, `:137`, `:140` (a test harness).
> **Zero occurrences under `render/native/`, `cli/`, `apps/` or `web/`.**
>
> **An app animated off `yantra_get_dt()` never moves.** It renders, it builds, it passes —
> frozen at its initial state.

### 2. Colours are AARRGGBB. A pasted CSS hex is fully transparent.

`Draw` and every node fill take `argb: uint32` in AARRGGBB (`sdk/ui/paint.nim:55`, `:57`,
`:59`, `:61`, `:63`). `0xF7F9FB` pasted straight from CSS has alpha `0x00`: it compiles,
runs, crashes nothing, and draws **nothing**. Measured on port #52, adding the alpha bytes
moved it from **100% differing to 23.7%** in one edit. Copy the helper at
`apps/chess/app.nim:100`:

```nim
proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)
```

### 3. Text `y` is the top of the line box, not the baseline.

`libs/nimskia/src/nimskia.nim:76` says *"Draws `s` with its top-left at (x, y)"* — **that is
wrong.** `libs/nimskia/src/skia_shim.cpp:291` calls `p->paint(canvas, x, y)`, and Skia's
`SkParagraph::paint` treats `y` as the top of the paragraph line box. Measured from `y`, in
units of font size S (verified at S = 12, 24, 48): cap/ascender ink top `y + 0.375·S`,
x-height top `y + 0.583·S`, **baseline `y + 1.0833·S`**, descender bottom `y + 1.333·S`.
So `yantra_y = wantedBaselineY - 1.0833 * size`. **Empirical — default typeface and weight
only; a port that sets a family or a non-default weight must re-probe.**

### 4. There is no text measurement API.

`sdk/ui/paint.nim:63` — `proc text*(…): Draw` — returns the new `Draw` and nothing else: no
width, no height, no advance. `Draw.text` has **no `align` parameter**. `measureText` exists
only natively (`libs/nimskia/src/nimskia.nim:68`, `:122`) and is unreachable from an app
module. **Centring, right-alignment and wrapping must be estimated.** Never describe an
estimated centring as exact.

### 5. A failed build keeps the old `.wasm`.

Restated because it is the one that fakes everything else: the previous module stays on disk
and `drive.exe` renders it without complaint. See §1.

---

## 6. The test gate

```
just test
```

`just` lives in the repo's shell conventions (`justfile` sets `set shell := ["bash","-uc"]`,
so recipes run under MSYS bash). On this machine `just.exe` is at
`C:\Users\Sanskar\.cargo\bin\just.exe`.

### What it runs, in order

1. **`examples`** (a dependency of `test`) — builds `hello cube3d animate2d animate webpage`
   to `examples/*.wasm` with `tools/build-wasm.sh`, prints the last line of each, then removes
   `examples/nimcache` and `examples/minilibc.o`.
2. `bash libs/nimwasmtime/tests/run_tests.sh`
3. `bash libs/nimqt/tests/run_tests.sh`
4. `bash host/run_tests.sh`
5. `bash render/run_tests.sh`
6. `node examples/verify_hello.mjs examples/hello.wasm`

### What "done" means

> Every suite must end at **0 failed**. Paste the tail of `just test`'s output in your report.
> **No output = not done.** (AGENTS.md, "The gate")

Never weaken, skip or delete a test to make it pass (rule 3). Never claim a pass you did not
measure (rule 11). A reported failure is a fine outcome; a fabricated pass is not. Commits carry
the same evidence in the body: `Verified: render sweep 7 passed, 0 failed`.

### Measured on this checkout — the gate does NOT currently pass

```
build-wasm: wrote examples/hello.wasm (208120 bytes)
build-wasm: wrote examples/cube3d.wasm (185840 bytes)
build-wasm: wrote examples/animate2d.wasm (192498 bytes)
build-wasm: wrote examples/animate.wasm (186945 bytes)
build-wasm: wrote examples/webpage.wasm (214477 bytes)
bash libs/nimwasmtime/tests/run_tests.sh
PASS t_wasm (T_WASM_OK)
PASS t_official (T_WT_OFFICIAL_OK)
PASS t_stress (T_WT_STRESS_OK)
PASS t_memory_bridge (T_MEMORY_BRIDGE_OK double(21)=42 mem[1024..]='double=none!')
PASS t_char (T_CHAR_OK)
PASS t_cache (T_CACHE_OK)
bash libs/nimqt/tests/run_tests.sh
== tests ==
FAIL smoke (see /tmp/build_smoke.log)
FAIL t_component (see /tmp/build_t_component.log)
FAIL t_property (see /tmp/build_t_property.log)
FAIL t_ecmascript (see /tmp/build_ecmascript.log)
FAIL t_signals (see /tmp/build_signals.log)
...
fatal error: QString: No such file or directory
error: recipe `test` failed on line 15 with exit code 1
```

Suite 1 passed **6/6**. Suite 2 (`libs/nimqt`) fails on **5** tests, every one of them the same
environment problem: `QString: No such file or directory`. MSYS2's Qt is not installed in this
checkout — the same missing-dev-headers condition that blocks rebuilding `shot.exe` (§4), and
consistent with `docs/renderer.md` §6 on the two Qt directory layouts and `docs/architecture.md`
on Qt being **legacy** (the shipping renderer is SDL3 + Skia + Yoga).

**How to report it honestly:** paste the tail above, state that suites 3-6 never ran because
the recipe stopped at suite 2, and name Qt-headers-missing as the cause. Do not describe this
as "the gate passes", and do not quietly edit `justfile` to drop the Qt suite (rule 3).

---

## 7. Repo hygiene rules that bite agents

### Rule 1 — never commit build material

> **Never commit** `third_party/`, `vendor/`, `.exe`, `.dll`, `.wasm`, or anything with keys.
> Run `git status` before every commit and read it.

`third_party/` holds a full MSYS2 install **including GPG keyrings** — that is why it is
`/third_party/`-anchored in `.gitignore` with a comment saying so out loud.

### Rule 10 — bank every lane, delete the junk

> Generated build output is never committed: `panicoverride.nim` (tools/build-wasm.sh),
> `host/nc_lb/` (nimcache), `*.bak`, `apps/mirror/pieces/_probe/`. When a lane dies, bank its
> source before anything else — unbanked work is lost work.

The `.gitignore` patterns that cover this chapter's own by-products:

| Junk produced by this chapter | Ignored by |
|---|---|
| `third_party/` (toolchains, MSYS2 keyrings) | `/third_party/` |
| `*.wasm`, `*.wasm.opt` | always rebuilt from source |
| `*.exe`, `*.dll`, `*.o`, `*.pdb`, `*.log` | build outputs |
| `nimcache*/` | `host/nc_lb/`, `examples/nimcache/` |
| `minilibc.o` | next to the `.nim` source |
| `panicoverride.nim` | "generated by tools/build-wasm.sh" |
| `*.bak` | editor/lane backups |
| `apps/minipaint/shots/` | "local evidence … large, regenerable, and prove nothing that a test does not" |
| `/render/*.png`, `/host/*.png` | test renders; curated screenshots live in `docs/img/` |
| `.yantra/` | live-edit inbox of a running app |

**The one that will bite you:** `scratch/_probe/` — this chapter writes `.wasm`, `.raw` and
`.png` probe artifacts there. `scratch/` is *not* gitignored wholesale; `.wasm`/`.exe` are,
but a `.raw` or `.png` inside it is not. Delete your probe directory before committing.

### The behavioural rules that matter at this stage

* **Rule 2 — never trust a prebuilt artifact.** Rebuild from source before claiming something
  works. *A stale `hello.wasm` once hid an SDK that did not compile.* This is why §1 says
  "build, don't reuse", and why §4 warns that `shot_excal.exe` is stale.
* **Rule 4 — paths derive from the script's own location.** No `C:/Users/...`, no cwd
  assumptions, in anything you commit. `cd` to the repo root before building; the script does
  `HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
* **Rule 11 — never claim a number you did not measure.** No invented diff percentages, no
  invented test passes.
* One task = one `PLAN.md` item, ~300 changed lines, one commit (`area: imperative summary`,
  body with `Verified:` and the pasted test tail). **Do not push; Owner pushes.**

---

## 8. Copy-paste "verify my app" recipe

Save as `verify-app.ps1` at the repo root, then:

```powershell
pwsh -File .\verify-app.ps1 apps\myapp\app.nim
```

```powershell
# verify-app.ps1 — build, run, screenshot, inspect, clean up. One file, no network.
param(
  [Parameter(Mandatory)][string]$App,     # path to the app .nim, relative to the repo root
  [int]$W = 800, [int]$H = 600, [double]$Scale = 1,
  [string]$Verbs = "wait:4",              # ';' separated, mpdrive.exe verbs
  [switch]$Release,
  [switch]$KeepProbe                     # default: delete the probe folder at the end
)
$ErrorActionPreference = "Stop"
$WS   = Split-Path -Parent $MyInvocation.MyCommand.Path
$bash = "$WS\third_party\msys64\usr\bin\bash.exe"
if (-not (Test-Path $bash)) { throw "MSYS2 bash not found at $bash" }
$Probe = Join-Path $WS "scratch\_probe"
New-Item -ItemType Directory -Force -Path $Probe | Out-Null

# 1. BUILD -------------------------------------------------------------- ~10 s
$wasm = Join-Path $Probe ((Get-Item $App).BaseName) + ".wasm"
$flag = if ($Release) { " --release" } else { "" }
& $bash -c "cd /c/Users/Sanskar/DEV/yantra && bash tools/build-wasm.sh $App `"$wasm`"$flag"
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

# 2. HEADLESS ASSERTIONS (optional but cheap) ---------------------------
#    node examples/verify_hello.mjs <wasm>   # only if you wrote a verifier for this app

# 3. RENDER A FRAME ----------------------------------------------------- offscreen, no window
$env:PATH = "$WS\render\native\build;$WS\third_party\skia-build\pkg\mingw-w64-x86_64-skia\mingw64\bin;$WS\third_party\msys64\mingw64\bin;$WS\libs\nimwasmtime\vendor\wasmtime-v19.0.2-x86_64-windows-c-api\lib;" + $env:PATH
$raw = Join-Path $Probe "frame.raw"
& "$WS\render\native\build\mpdrive.exe" $wasm $raw $W $H $Scale $Verbs
if ($LASTEXITCODE -ne 0) { throw "mpdrive failed ($LASTEXITCODE)" }

# 4. RAW -> PNG (BGR in memory, BGRA on disk) --------------------------
Add-Type -AssemblyName System.Drawing
$pw = [int]($W * $Scale); $ph = [int]($H * $Scale)
$bytes = [byte[]][System.IO.File]::ReadAllBytes($raw)
if ($bytes.Length -ne $pw * $ph * 4) { throw "raw is $($bytes.Length) B, expected $($pw*$ph*4)" }
$png = Join-Path $Probe "frame.png"
$bmp = [System.Drawing.Bitmap]::new($pw, $ph, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
$d = $bmp.LockBits([System.Drawing.Rectangle]::new(0,0,$pw,$ph),
        [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $d.Scan0, $bytes.Length)
$bmp.UnlockBits($d); $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 5. INSPECT ------------------------------------------------------------ open it, and refuse to call a blank frame a pass
$set = [System.Collections.Generic.HashSet[uint32]]::new()
for ($i = 0; $i + 3 -lt $bytes.Length; $i += 4) {
  [void]$set.Add([uint32]$bytes[$i] -bor ([uint32]$bytes[$i+1] -shl 8) -bor ([uint32]$bytes[$i+2] -shl 16) -bor ([uint32]$bytes[$i+3] -shl 24))
}
"distinct colours: $($set.Count)"
if ($set.Count -lt 4) { Write-Warning "UNIFORM FRAME - nothing was drawn. Do not report this as a pass." }
Invoke-Item $png

# 6. RUN IT FOR REAL (optional) ---------------------------------------- opens a native window
# & "$WS\render\native\build\yantra.exe" $wasm --watch

# 7. CLEAN UP ------------------------------------------------------------ probes are never evidence
if (-not $KeepProbe) {
  Remove-Item -Recurse -Force $Probe -ErrorAction SilentlyContinue
  Get-ChildItem (Split-Path (Join-Path $WS $App)) -Filter 'minilibc.o'  -EA SilentlyContinue | Remove-Item -Force
  Get-ChildItem (Split-Path (Join-Path $WS $App)) -Filter 'nimcache*' -Directory -EA SilentlyContinue | Remove-Item -Recurse -Force
  Get-ChildItem (Split-Path (Join-Path $WS $App)) -Filter 'panicoverride.nim' -EA SilentlyContinue | Remove-Item -Force
}
Write-Host "OK - built, rendered, inspected. Paste this output in your report."
```

The sequence, stated plainly: **build → assert headlessly → render one frame offscreen →
convert to PNG → look at it and count colours → clean up**. Only after that does
`yantra.exe` matter, and only for interaction feel — never as your proof.

---

## 9. The five build failures already paid for

Transcribed from the `GOTCHAS BAKED IN` block in `tools/build-wasm.sh` — each one, in the
script author's words, cost real debugging time. They are already fixed in the script; the
point of recording them is so they are never re-derived.

**1. Native clang does NOT understand MSYS paths.** Include and library paths MUST be native
(`C:/Users/...`). `pwd -W` produces that. The whole script is built around it: `pw()`,
`ROOT_NATIVE`, `SRC_NATIVE`. (This is AGENTS.md's "nim.exe needs native paths" again, at the
clang layer.)

**2. `--os:any`, not `--os:standalone`.** Standalone has no `except`, so `std/json` and any
library that catches exceptions would not compile. `any` needs `signal.h` (a no-op stand-in in
the mini-libc) and compiler-rt builtins (linked from wasi-sdk). **Cost: +5.5 KB on the
counter.** `panicoverride.nim` is still copied for old callers — which is exactly why it shows
up as junk in your working tree.

**3. `fmod` must NOT be `__builtin_fmod`** — on wasm that lowers to a libcall to `fmod`,
i.e. to itself.

**4. Do not add clang `-O2` to the Nim-generated C.** It strength-reduces the formatter's
64-bit divide into a `__multi3` libcall, which becomes an unresolved import and breaks
instantiation. The same trap appears a second time in the mini-libc compile: the script
compiles mini-libc to a real **object** file, not llvm bitcode, precisely because linking
`-emit-llvm` bitcode makes wasm-ld do codegen at link time and reintroduce that `__multi3`.

**5. `--export-all` makes every symbol a GC root, so `--gc-sections` cannot drop unused
mini-libc code.** A pure-arithmetic module would therefore inherit an unused `yantra_log`
import (~18 KB) just by linking the library. **That is what `--no-libc` is for.**

### Bonus, from the nimcache comment (also real, also cost time)

The nimcache directory name is a hash of the Nim flags, because Nim keys its object cache on
the module graph and the flags but **not** on a flag arriving by a different route: building
with `YANTRA_NIM_FLAGS=-d:minipaint_gallery` and then a plain build reused the flagged
`@mapp.nim.c`, and the "plain" wasm still contained the gallery. A screenshot showed debug
scaffolding in a build that was supposed to have it compiled out.

---

## 10. Quick reference

```bash
# build (from the repo root; use third_party/msys64/usr/bin/bash.exe -c from PowerShell)
bash tools/build-wasm.sh <app.nim> <out.wasm> [--release|--no-libc]

# headless assertions
node examples/verify_hello.mjs <out.wasm>

# offscreen frame -> raw BGRA  (scale, then ';' separated verbs)
render/native/build/mpdrive.exe <out.wasm> frame.raw 800 600 1 "wait:4;click:400,300;wait:3"

# live window
render/native/build/yantra.exe <out.wasm> [--watch]

# the gate (expect 0 failed everywhere, paste the tail)
just test
```

Real tool binaries in `render/native/build/` at the time of writing (58 files): `yantra.exe`,
`mpdrive.exe`, `mpdrive_unwrap.exe`, `mpprobe.exe`, `shot_excal.exe`, `tsc3.exe`,
`yantra-film.exe`, `yantra-pdf.exe`, and the `t_*.exe` test binaries (`t_engine`, `t_shell`,
`t_text`, `t_motion`, `t_grid`, `t_scroll`, `t_light`, `t_play`, `t_pdf`, `t_sound`,
`t_video`, `t_probe`, `t_probe2`, `t_media`, `t_stream`, `t_mpopen`, `t_dialog`,
`t_dialog_open`, `t_a11y`, `t_call`, `t_chrome`, `t_capture`, `t_chat`, `t_damage`, `t_dnd`,
`t_film`, `t_fx`, `t_gpu`, `t_image`, `t_keys`, `t_liveedit`, `t_longlist`, `t_nav`,
`t_net`, `t_net_image`, `t_notify`, `t_overlay`, `t_richtext`, `t_reload`, `t_sized`,
`t_smooth`, `t_spell`, `t_store`, `t_vlist`, `t_workers`). **`shot.exe` and
`yantra_run.exe` are not in `build/`** — the latter exists one level up as
`render/native/yantra_run.exe`.

> **CORRECTED 2026-10-03 — the `yantra_run.exe` half of that sentence was wrong, in a way
> that mattered.** What it used to say: *"`shot.exe` and `yantra_run.exe` are not in `build/` —
> the latter exists one level up as `render/native/yantra_run.exe`."*
>
> Re-checked by path:
>
> | path | exists |
> |---|---|
> | `render/native/build/shot.exe` | **NO — does not exist anywhere in the tree** |
> | `render/native/build/yantra_run.exe` | **NO** |
> | `render/native/build/desktop/yantra_run.exe` | **YES — 5 211 385 bytes** |
> | `render/native/yantra_run.exe` | yes |
>
> So `yantra_run.exe` is **not** absent: it lives under `build/desktop/`, not one level up
> from `build/`, and `build/desktop/` also holds the runtime DLL set. That is the path
> `skills/yantra/SKILL.md:29` uses, and it is correct. **`skills/yantra/SKILL.md:30` is the
> broken one — it names `render/native/build/shot.exe`, which does not exist.** Use
> `render/native/build/drive.exe` or `render/native/build/mpdrive.exe`; both take
> `<wasm> <out.raw> <W> <H> <scale> "<verbs>"`, per `render/native/drive.nim:1-25`.
>
> The `shot.exe is NOT there` claim at the top of §4 was already right and is left alone.
