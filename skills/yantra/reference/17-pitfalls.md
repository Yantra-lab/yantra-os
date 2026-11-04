# 17 — Pitfalls

The mistakes that actually cost time in Yantra. Sections 1 and 2 are transcribed from the repo's
own rules (`AGENTS.md`, `tools/build-wasm.sh`). Section 3 is **measured** — every error string in it
was produced by running `bash tools/build-wasm.sh` on a deliberately broken file. Nothing in
section 3 is invented.

---

## 1. The repo's hard rules (AGENTS.md)

These are not style preferences. Breaking one invalidates the work.

### The gate

`just test` must end with every suite at **0 failed**. Paste the tail of its output in your report.
No output = not done.

### Rules

1. **Never commit** `third_party/`, `vendor/`, `.exe`, `.dll`, `.wasm`, or anything with keys.
   Run `git status` before every commit and *read* it.
2. **Never trust a prebuilt artifact.** Rebuild from source before claiming something works.
   (A stale `hello.wasm` once hid an SDK that did not compile.)
3. **Never weaken, skip or delete a test to make it pass.** Fix the code or report "Stuck".
4. **Paths are derived from the script's own location.** No `C:/Users/...`, no cwd assumptions.
5. **Wrap, don't rewrite.** Use an existing C/C++ library behind a small Nim interface.
   New library = ask Owner first (add to `DECISION_QUEUE.md`).
6. **The SDK only promises what the renderer draws.** Adding a node kind requires the renderer
   mapping + a test in `render/t_qml.nim` in the same task.
7. One task = one `PLAN.md` item, ≤ ~300 changed lines, one commit.
8. Stuck on the same error 3 times → stop, write what you tried under "Stuck" in `STATE.md`,
   move to the next task.
9. Anything user-visible (names, words, look, defaults), new dependencies, deleting folders, or
   licence questions → `DECISION_QUEUE.md`, don't decide silently.
10. **Bank every lane, delete the junk.** Generated build output is never committed:
    `panicoverride.nim` (tools/build-wasm.sh), `host/nc_lb/` (nimcache), `*.bak`,
    `apps/mirror/pieces/_probe/`. When a lane dies, bank its source before anything else —
    unbanked work is lost work.
11. **Never claim a number you did not measure.** No invented diff percentages, no invented test
    passes. A reported failure is a fine outcome; a fabricated pass is not.
    `tools/mirror/count-pieces.sh` prints the real mirror census.

### Layout — do not invent new top-level folders

| Folder | What it is |
|---|---|
| `sdk/` | What app authors import (`import yantra`). Compiles to wasm. |
| `host/` | Native engine: loads the wasm (via `libs/nimwasmtime`), owns the UI tree, dispatches events. |
| `render/` | Turns the UI tree into pixels. Swappable. |
| `libs/<name>/` | One Nim wrapper per C/C++ library. Each has `src/`, `tests/run_tests.sh`, `README.md`, `INTERFACE.md`. |
| `examples/` | Example apps. Each must build with `tools/build-wasm.sh`. |
| `tools/` | Build/setup scripts. |
| `docs/` | Plain-language docs. `docs/img/` holds curated screenshots. |
| `third_party/` | Local toolchains. **Gitignored. Never commit it.** |

Never import across the arrows in `docs/architecture.md` §2.

### Commits

`area: imperative summary` then a body with `Verified:` and the pasted test tail.
Example: `render: honour app window size — Verified: render sweep 7 passed, 0 failed`.
**Do not push; Owner pushes.**

---

## 2. Build gotchas (from the "GOTCHAS BAKED IN" block in `tools/build-wasm.sh`)

Each of these is already handled inside the script. They are here because the moment you bypass
the script — hand-rolling a `nim c` line, writing a new build path — you reintroduce them.

1. **Native clang does NOT understand MSYS paths like `/c/Users/...`** — include and library paths
   MUST be native (`C:/Users/...`). `pwd -W` produces that.
   *Why it matters:* the script wraps path conversion in `pw() { pwd -W 2>/dev/null || pwd; }` and
   applies it to ROOT, SRC, MINILIBC and the compiler-rt archives. Copy that helper, don't
   re-derive paths yourself.
2. **`--os:any`, not `--os:standalone`** — standalone has no `except`, so `std/json` and any library
   that catches exceptions would not compile. `any` needs `signal.h` (a no-op stand-in in the
   mini-libc) and compiler-rt builtins (linked from wasi-sdk).
   *Cost:* +5.5 KB on the counter. `panicoverride.nim` is still copied for old callers.
3. **`fmod` must NOT be `__builtin_fmod`** — on wasm that lowers to a libcall to `fmod`, i.e. to
   itself. (Infinite recursion at instantiation.)
4. **Do not add `clang -O2` to the Nim-generated C** — it strength-reduces the formatter's 64-bit
   divide into a `__multi3` libcall, which becomes an unresolved import and breaks instantiation.
   This is also why the mini-libc is compiled to a **real object file** (`-c ... -o minilibc.o`),
   not llvm bitcode: `-emit-llvm` makes wasm-ld do codegen at link time, which re-creates the very
   same `__multi3` unresolved import.
5. **`--export-all` makes every symbol a GC root**, so `--gc-sections` cannot drop unused
   mini-libc code. A pure-arithmetic module would inherit an unused `yantra_log` import (~18 KB)
   just by linking the library. That is what `--no-libc` is for.

Two more baked in that bite silently:

- **The nimcache directory is hashed from the nim flags** (`md5sum | cut -c1-8`). Nim keys its
  object cache on the module graph and flags, but *not* on a flag arriving through a different
  route. Building `YANTRA_NIM_FLAGS=-d:minipaint_gallery` and then a plain build reused the
  flagged `@mapp.nim.c`, and the "plain" wasm still contained the gallery — a screenshot showed
  debug scaffolding in a build that was supposed to have it compiled out.
  **Never reuse a nimcache dir across flag changes.**
- **`panicoverride.nim` is copied next to your source** by the script. It is generated build
  output — hard rule 10: never commit it.

---

## 3. Measured compiler errors

Every string below is a recorded transcript of `bash tools/build-wasm.sh` on this
repo, with paths elided to `PROBE.nim` for readability; line numbers are exact.

> **How much weight to give the wording.** These were captured on **Nim 2.2.10
> windows-amd64 / clang 22.1.8**, and that version is a property of *that machine*,
> not of the repo — `tools/build-wasm.sh` pins no toolchain version, it uses
> whatever `nim` and `clang` are on `PATH`. **The file, line and column numbers are
> the durable part and are correct for this tree.** The prose of an error message
> can differ on a different Nim; treat a mismatch in wording as "same error,
> different compiler", not as a new bug. Nothing in this table was re-run during
> the 2026-10-03 audit, and per AGENTS.md rule 11 it is reported as a recorded
> transcript rather than as something re-measured here.

All builds pass `--import:yantra` (see the script's nim invocation), so **`import yantra` is not
needed in an app module** — the script supplies it.

| Symptom / error text | Cause | Exact fix |
|---|---|---|
| `Error: attempting to call undeclared routine: 'fontSizeKlass'` | Prop/proc name invented, or a typo. Nim does not suggest here — it just names the routine. | Check `protocol/props.md` (generated, complete) and grep the setter in `sdk/`. Rename to a real setter. |
| `Error: attempting to call undeclared routine: 'fnotSize'` | Same shape: typo'd setter (`fontSize` → `fnotSize`). Note there is **no** "did you mean" line for a bare call. | Fix the spelling: `t.fontSize(14)`. |
| `Error: type mismatch`<br>`Expression: padding(t, 1, 2, 3)`<br>`Expected one of (first mismatch at [position]):`<br>`[3] proc padding(node: Node; all: int32)` → `extra argument given`<br>`[5] proc padding(node: Node; top, right, bottom, left: int32)` → `missing parameter: left` | Wrong arity. Only 1-arg and 4-arg overloads exist; 3 args matches neither. | `padding(8)` for all sides, or `padding(t, r, b, r, l)` — all four. |
| `Error: type mismatch`<br>`Expression: width(t, "50%")`<br>`  [2] "50%": string`<br>`Expected one of:`<br>`[2] proc width(node: Node; value: int32)` | Unit/string given where an `int32` length is expected. There is no `"50%"` string form on the setter. | Use an int: `t.width(200)`. For CSS-like lengths in the DSL use the unit literals (`400.px`, `1.fr`) in the block form, not on the setter. |
| `Error: undeclared identifier: 'laterProc'`<br>`candidates (edit distance, scope distance); see '--spellSuggest':`<br>` (4, 6): 'iterToProc'`<br>` (4, 6): 'rawProc'` | Proc **used before it is defined** with no forward declaration. (Adding `proc laterProc(): string` above the use makes it compile — measured.) | Add the forward declaration above the use. Do not reorder files. |
| `expression 'fontSize(t, 14)' has no type (or is ambiguous)` | `discard` on a call that returns **void**. Setters return nothing. | Drop the `discard`. Just `t.fontSize(14)`. |
| `undeclared identifier: 'getCurrentDir'` (`import os`) | The OS surface is not there. Only a few `std/os` symbols are even declared; most are gone. | No OS access. The wasm sandbox has no filesystem, no process, no clock outside the SDK's own `frameDt()`/`ms`. |
| `@pstd@ssyncio.nim.c:10:10: fatal error: 'errno.h' file not found`<br>`  10 | #include <errno.h>`<br>`Error: execution of an external compiler program 'clang.exe -c ...' failed with exit code: 1` | `readFile("secret.txt")` pulled in `std/asyncio`/`os`, whose generated C `#include`s `<errno.h>` — the mini-libc freestanding target has no such header. This is the **sandbox** error, and it appears at C-compile time, not Nim time. | Do not read files. Assets are declared to the SDK (`image(col, "logo.png")`, `model`) and the host resolves them from the app's folder. |

### Two honest "no error" results

These are findings, not failures — the build did **not** produce an error, and that is the useful
part.

- **Missing `import yantra` produced NO error.** A module with no import at all built fine, because
  `tools/build-wasm.sh` passes `--import:yantra` on the nim command line. Do not expect a
  "missing import" diagnostic from this build path.
- **`import std/strutils` compiled clean.** `"abc".toUpperAscii()` is fine; strutils is pure
  computation. It is `std/os` and the filesystem path that breaks — and only at the C layer,
  as shown in the table.

---

## 4. The four Nim gotchas already paid for

From `AGENTS.md` (see `docs/renderer.md` §6 for more), expanded:

### a. `passC` flags that are substrings of each other get silently dropped

> Nim silently drops a `passC` flag that is a substring of one already added → order include paths
> short-to-long (`libs/nimqt/config.nims`).

**In practice:** you add `-IC:/long/path/to/lib` and then `-IC:/long` — or the flags differ only by
a suffix. Nim de-duplicates and one vanishes, so an `#include` resolves against the *wrong*
directory, or not at all, with no warning. The build looks configured and the C compiler disagrees.
**Fix:** order include paths shortest-to-longest, in every `config.nims` you write.

### b. Procs must be declared before use

**In practice:** Nim is single-pass. A proc defined at the bottom of the file is invisible to a call
above it. The error is `undeclared identifier` with **suggestions from unrelated stdlib names**
(`iterToProc`, `rawProc`) — which look like typos but are not; the real proc exists, just too late.
**Fix:** add a forward declaration (`proc laterProc(): string`) above the use. Do **not** reorder
files to fix this — the file order is the module's structure and reviewers diff against it.
(Also see the measured error in §3.)

### c. `nim.exe` needs native paths, not MSYS paths

**In practice:** on Windows, an MSYS-style path (`/c/Users/...`) passed to `nim.exe` does not
resolve — you get a confusing "cannot open file" or a silent empty build rather than a clear
"bad path". `pwd -W` converts; use it everywhere. Same root cause as build gotcha 1.
Related hard rule 4: derive paths from the script's own location, never from cwd.

### d. 3D renders only in a real window

**In practice:** an offscreen 3D render produces a **blank frame that still passes**. A green test
proves the pipeline ran, not that anything was drawn. Any 3D claim must be verified in a real
window before you report it. (This is the same shape of trap as §5 below, which is why both exist.)

### Bonus, from the build script itself

**Nim's own allocator corrupts data when a seq grows** under the default standalone allocator: the
first element's string came back empty (E4 bisect). Hence `-d:nimAllocPagesViaMalloc`. Do not
"optimize" that flag away — `-d:useMalloc` also works but leaks without bound, because the
mini-libc free is a no-op.

---

## 5. Engine-level traps: "it compiles" ≠ "it renders"

The Nim compiler checks the **vocabulary**, not the **renderer**.

### The dead-property trap: `pAlign`

`pAlign` existed in the prop vocabulary and **the renderer never emitted it**, so every value an app
set was silently discarded. No compile error, no warning — the app just did nothing. This is
recorded twice in the repo so it stays remembered:

- `sdk/yantra.nim`: `## Text alignment. This was a DEAD property for a while: 'pAlign' existed in
  ## the vocabulary and the renderer never emitted it, so every value an app set was silently
  ## discarded.`
- `render/qmlgen.nim`: `# Text alignment was a DEAD property: pAlign existed in the vocabulary and
  # the renderer never emitted it, so every value an app set was discarded.` — now guarded by
  `if n.hasProp(P_ALIGN)`.

**How to tell "compiles" from "renders":**

1. **Compile is necessary, not sufficient.** The setter resolves against `sdk/core/wire.nim`'s enum.
   The renderer must *emit* the prop. Those are two different files and they can disagree.
2. **Verify by screenshot, per element, not per app.** One screenshot that "looks right" can hide a
   silently-dropped prop. Check the specific thing you just set, in isolation.
3. **Grep the renderer for the prop when you use it for the first time.** `grep -rn "P_ALIGN"
   render/` — if the render side has no `hasProp` guard and no emit line, it is dead.
4. **Read `protocol/props.md`.** It is generated from `protocol/schema.nim` and is the complete,
   authoritative prop list. A prop not in it does not exist, whatever the SDK seems to accept.

### The rule: a new node kind is one task, not two

Hard rule 6, verbatim:

> **The SDK only promises what the renderer draws.** Adding a node kind requires the renderer
> mapping + a test in `render/t_qml.nim` in the same task.

Concretely, if you add `nkSparkline` to `core/wire.nim` and a `sparkline(parent)` constructor in
`sdk/`, then in the **same task** you must:

- add the mapping in `render/qmlgen.nim` that emits real pixels for it;
- add a test in `render/t_qml.nim` that fails without the mapping;
- update `protocol/schema.nim` and regenerate `protocol/props.md` / `sdk/props.nim`
  (`## GENERATED FILE. DO NOT EDIT. ## Edit protocol/schema.nim instead.`).

Ship the SDK half without the renderer half and you have manufactured a dead property — exactly the
`pAlign` bug, with the same silent failure mode. The test is what makes the promise true; without
it the prop compiles, type-checks, and does nothing.

### Other things that compile and do nothing

- **A `Draw` colour with no alpha byte.** `0xF7F9FB'u32` passed to a `Draw` primitive
  draws **nothing** — `libs/nimskia/src/skia_shim.cpp:1327` is a bare
  `paint.setColor(SkColor(argb))` with no promotion. Node colour props are *not* affected:
  `render/native/engine.nim:345-348` (`argb`) forces a zero top byte to `0xFF`. So the trap
  is specifically **moving a working colour from a node into a `Draw` list** — it compiles,
  runs, and silently stops drawing. Full write-up and the `hex()` helper:
  `07-color-gradients-and-effects.md` §1.
- A prop set on a node that the renderer's `common()` path never reaches (the prop is read on a
  different `K_*` branch than the one your node kind takes).
- `visible(false)` / `opacity(0)` — they type-check; whether the renderer honours them is a
  renderer question.
- **The stale-nimcache trap** (§2): a build that genuinely changed can reuse a cached `@m*.nim.c`
  and produce an artifact that does not match the source. Hard rule 2 applies with extra force:
  when a change appears to have no effect, rebuild before concluding anything.

---

## 7. Three silent no-ops that pass every test

> **On the numbering: there is no §6.** An earlier §6 was folded into §5 (engine
> traps). The gap is kept rather than renumbered, because five chapters outside
> this one cite §3, §5 and §9 by number and renumbering would silently break
> them. Jump from §5 to §7 without looking for §6 — nothing is missing.

All three build clean, produce a correct-looking node tree, and pass a headless harness. None is a
compile error or a trap. They are one failure class: **the module works, the host never hears about
it.** "It ran without trapping" proves nothing about whether anything started or was drawn —
assert on the import/export surface explicitly.

### 7a. `yantra_main` is not exported

`host/host.nim:1188` does `callVoid(inst, "yantra_main")` **unconditionally**, and `host.nim:7`
lists it as loading step 3. `yantraRun:` (`sdk/core/runtime.nim:232`) is only sugar for
`proc yantra_main*() {.exportc: "yantra_main".} = <body>`.

So this app **cannot be started by the engine at all**:

```nim
when isMainModule:      # WRONG — exports NimMainModule, not yantra_main
  main()
```

```nim
proc yantra_main*() {.exportc: "yantra_main".} =   # RIGHT
  main()
```

Every example under `examples/` uses `yantraRun:`; anything hand-rolled ending in
`when isMainModule` does not. Check with the harness, which prints
`entry : yantra_main present = true|false`. Do **not** detect this by grepping the `.wasm` for the
string — ASCII-grepping a wasm gives false negatives (it reported `y_store_get` absent for a module
that demonstrably imported and called it).

### 7b. `pointerPos()` is stale unless the node registers that event

`pointerPos()` (`sdk/ui/input.nim:54`) only reads `yNodeSize(0,7)`/`(0,8)`, which the **engine**
writes. `engine.nim:3018` (`canvasPointer`) opens with:

```nim
if id < 0 or not e.s.valid(id) or e.s.handlerFor(id, ev) < 0: return false
```

It sets `pointerAt` **only** when the node has a handler for the event being dispatched. The
`E_CLICK` path (`engine.nim:3066`) does `e.fire(p, E_CLICK)` and never touches `pointerAt` at all.

So a `canvas` registering only `onClick` gets a permanent stale `(0, 0)` and every hit test
collapses to the origin. The node tree is perfect and the feature is simply dead:

```nim
scene.onClick(proc() =                    # WRONG — pointerPos() is always (0,0) here
  let (x, y) = pointerPos(); ...)

scene.addHandler(evPointerDown, proc() =  # RIGHT
  let (x, y) = pointerPos(); ...)
```

Most HTML apps listen on `pointerdown` anyway, so this is usually the faithful port.

Also: `pointerPos()` is **canvas-local** px — the same space `Draw` commands are issued in, so do
NOT add a header or page offset. `pointerPage()` is window/page space. `frameDt()` is **seconds**
(`sdk/ui/input.nim:45-46`), first frame 1/60.

### 7c. `tick()` that advances time but never repaints

> **CORRECTED 2026-10-03.** This section used to say: *"A frame handler that updates
> state without `repaint()` makes **every animation invisible** — key flashes, sparks,
> glows, glides, feeds, particles"*, and then *"calling `frameDt()` from a
> scene-building path instead of a frame handler consumes an input slot and can
> silently break later pointer events."* **Both halves are wrong.**
>
> **1. There is no `repaint()` in the SDK.** The string `repaint` appears **nowhere**
> under `sdk/`. It is an **app-local helper** and every port writes its own —
> `apps/gallery/app.nim:2906` (`scene.set(pDraw, buildScene().cmds)`),
> `apps/chess/app.nim:949`, `apps/typewriter/app.nim:1857`, `apps/dna/app.nim:481`,
> `render/native/t_mpopen.nim:139`. Copying the *call* `repaint()` from a port
> without its definition gets you an `undeclared identifier`. **The SDK's actual
> redraw mechanism is a state write:** changing a `state` (or any node prop) from
> `onFrame:` marks the node dirty and the window repaints
> (`render/native/engine.nim:4077-4119`; `10-animation-and-motion.md` §6.3). The
> *real* freeze is the one this section should have named: a handler that computes
> and stores nothing at all. Then nothing is dirty, nothing repaints, the last
> committed frame is the last action's frame — and nothing warns you.
>
> **2. `frameDt()` does not consume an input slot.** `y_input` is a **pure read**:
> `host/host.nim:910-941` (`cbInput`) evaluates a `case` and calls `setResult`; for
> the frame delta that is `of 7: host.frameDt` (`host/host.nim:926`). It mutates no
> host state, consumes nothing, and cannot break later pointer events. Reading it
> outside a frame handler is not corruption — it returns whatever `host.frameDt`
> currently holds, i.e. the value left over from the **last** frame (`0.0` before
> the first). That is a stale-read problem, and the fix is the same either way:
> read it once per frame.

---

## 8. Open SDK finding — `persistent[T].set()` never persists on wasm

Measured, reproduced in isolation, **not yet fixed**. Recorded so no port is blamed for it.

A minimal two-node probe (`persistent("", "probe.key")` plus one `.set()` inside `yantra_main`,
nothing else) creates its window and panel, runs `main()` to completion without trapping, calls
`y_store_get` during the initial load — and **never calls `y_store_set`**. The real app is not
implicated: `apps/typewriter` calls `persistNow()` from all eight mutating actions and reaches
exactly the same non-result.

The chain that should carry it: `persist.nim:46` persists through `createEffect`; `signals.nim:228`
`set()` schedules `s.subscribers`; `signals.nim:142` `flush()` runs them; `createEffect`
(`signals.nim:245`) runs its body once immediately outside a flush so the effect subscribes to the
signal. Every link looks right, and none of them fires.

Until it is fixed, "did the app write anything?" is not verifiable headlessly. Test behaviour
through observable state — node tree, `pDraw` command length, layer bytes — and report the store as
a known gap instead of gating the suite on it. (Do **not** reach for `log()` to check: see §9a.)

---

## 9. Four dead instruments: they compile, they link, they do nothing

Every trap in this section shares one shape — **the app is fine, the host never hears
about it.** These four are the ones that cost the most, because each one looks like
a working debug or verification loop right up until you rely on it.

### 9a. `log()` — collected by the host, printed by nobody

> **CORRECTED 2026-10-03.** The claim that `log()` is a usable debugging channel —
> or even merely "visible in a terminal under `drive.exe`" — is **wrong, and
> nothing ever reads it.** `sdk/core/runtime.nim:129-130` wraps `yLog`
> (`runtime.nim:66`, `{.importc: "yantra_log"}`); the host registers the import at
> `host/host.nim:1029`; and `cbLog` at **`host/host.nim:628`** does exactly one
> thing — `host.logs.add readStr(...)`. That is the only writer in the repo, and a
> repo-wide grep for `host.logs` finds **no reader at all**: not `cli/`, not
> `render/native/`, not `host/`. (`render/native/t_mpopen.nim:173` prints
> `e.s.logs`, which is the *capability* log, a different field.) **The host
> collects every line your app writes and throws it away.**
>
> It costs you: **one `log()` call measured at +15,660 bytes on a ~215 KB module —
> about 7 % — because it drags the whole `yantra_log` import and its string
> machinery in.** You pay that for a channel nobody listens on.
>
> **Debug by drawing, or by reading the pixels.** Encode what you want to know in
> what you can see: a colour swatch, a text label, a node's position. For a real
> number, read the frame dump (§9b) or the node's props from a headless harness.

### 9b. Frame dumps are BGRA — swap before you diff, or the score is meaningless

> **CORRECTED 2026-10-03.** This chapter gave no guidance here and other chapters
> imply a raw dump is ready to diff. It is not. `render/native/drive.nim:191-193`
> `copyMem`s a `seq[uint32]` of Skia pixels straight to disk. Skia's `SkColor` is
> `0xAARRGGBB`, so **little-endian memory reverses it: the bytes on disk are
> B, G, R, A.** But `tools/pngdiff.mjs` and `tools/refdiff.mjs` read bytes 0, 1, 2
> as R, G, B with no swap — so an unswapped raw is scored with **R and B
> exchanged.**
>
> **Measured**, same port, same reference, the swap being the *only* difference:
> gallery scored **91.45 % unswapped vs 72.83 % swapped**. The unswapped number is
> not a worse score, it is a score of the wrong image.
>
> **Always swap first:** `node tools/rawswap.mjs <in_bgra.raw> <out_sw.raw>`.
> A **double-swap** is the matching trap: if a tool ever starts emitting RGBA, the
> swap becomes the bug. Sanity-check against a known CSS colour from the original
> page rather than trusting the convention.

### 9b-bis. Probe instruments that reported a confident false finding

**Measured 2026-10-04 (rounds 140-144).** Every one of these produced numbers, not errors, and
every finding was plausible enough that I acted on two of them before catching them. They
are listed here because the pattern — *an instrument that cannot fail will fail
CONFIDENTLY* — has now cost more rounds than any single port bug.

1. **Read the rawswapped frame as R,G,B,A.** `tools/pngdiff.mjs` compares `raw[i]` against
   `ref.rgba[i]` *position-for-position*, so `tools/rawswap.mjs`'s output is already in
   reference order. A probe that reads it as B,G,R double-corrects. I "measured" a
   warm-reference / cool-frame hue inversion across an entire image this way — **in two
   probes at once**, which is what made it convincing.
   **Rule: a corroborating probe must use the same byte order as the differ it supports.**

2. **A 128-luminance IoU threshold is vacuous in a dark scene.** In the night-lit gallery
   **98.8%** of reference pixels are below 128, so thresholding there compares two
   nearly-full masks: it read **IoU 0.9675** with the verdict "placement is the problem".
   Re-thresholded on the *lit* pixels (lum ≥ 90): **IoU 0.3709**, frame holding **1.61×** the
   reference's bright mass, and no shift in ±6 helped.
   **Rule: pick the threshold so both masks cover a comparable AREA (~10–20%), not so the
   answer looks stable.** A mask covering 99% of the frame discriminates nothing.

3. **Averaged boxes hide small bright elements.** A 160×800 mean reported a plausible tone
   while concealing ref `(156,141,100)` against frame `(33,31,30)` inside the same region.
   **Rule: profile the dimension; never average a small bright thing out of a large dark
   field.**

4. **Measure a CSS gradient; do not reason about it.** A purpose-built probe — flat 128-grey
   under `radial-gradient(120% 95% at 50% 50%, …)` — gave corner luma **109**, exactly what
   `rx = 1.2·W / ry = 0.95·H` predicts, and refuted my leading hypothesis in one capture
   after I had argued about it at length.
   **Rule: when a gradient/filter semantic is in doubt, render it over a known flat value
   and read the ramp.**

### 9b-ter. Three more, from isolating one layer inside a layered app

**Measured 2026-10-04 (rounds 141-144), same gallery.** These are the isolation-specific
siblings of the four above.

5. **A probe that produces a frame IDENTICAL to baseline has not run.** A patch intended
   to bypass one layer used `(?m)^  drawFogVig\(result\)$`. `$` in .NET multiline mode
   does **not** match before a CR, so on a CRLF file the pattern never matched — yet the
   build succeeded and its output *changed size*, because writing the file normalised
   line endings. The frames came out byte-identical and the tool confidently reported
   "this layer contributes 0.0%" — the app scored against itself.
   **Rule: diff the probe frame against the baseline before believing any statistic from
   it. Equal hashes mean the patch missed, not that the layer is inert.** Verify the patch
   landed (grep for your own marker and read the line number) *before* building, and make
   the regex `\r?`-tolerant.

6. **A layer probe's bounding box is a validity check — but only if the layer is the
   *only* producer.** Asking for "mirror sprites alone" left the whole real group drawn,
   and the sprites spanned `x 0..1279` in every row: obviously the wall paintings, not
   eight reflections. On the retry, twelve bypasses inside `renderCorridor` still left
   **99.7%** of the frame drawn — because the room gradient and the fog are painted in
   `repaint`, **outside the proc being probed**, and fill the canvas.
   **Rule: bypass every producer of the pixels you want gone, including ones outside the
   routine you are probing. Trace who writes the destination buffer, not just what you
   are editing.** A bbox covering the whole canvas is the signal, and no count of edits
   will reveal it if you only edit inside one proc.

7. **Prefer a differential probe (X on / X off, everything else shared) over a single
   probe.** Two builds differing *only* in the layer under test cancel every common
   confounder by construction — room gradient, fog, tone curve — instead of hoping they
   were small. It also makes the invalidity condition unambiguous: if the differential is
   empty, the layer genuinely does not reach that region. That is exactly how the mirror
   sprites were cleared of the near floor (13.46% of frame, bbox `y 229..664`, **zero
   pixels past y=664**) — and how the correct culprit was found in the layer everyone had
   assumed was decorative.
   **Rule: one probe tells you what a frame looks like. A differential tells you what a
   layer did.**

Two corollaries the same round produced, both from reading a number before checking it:

- **A colour that matches a source is not evidence that source drew it.** Bright pixels
  matching the artwork were attributed to painting reflections; the differential showed
  they were mirrored *walls*. Reading brightness → inferring layer is the same mistake as
  comparing a region's ratio to nothing — always name the layer that produced the pixel.
- **Re-derive a surprising statistic before writing it down.** A first pass reported a
  "+62.8 sprite contribution" in a band where the two builds are byte-identical (0 of
  51,200 pixels). It came from an unchecked script, and it would have been banked.

### 9b-quater. "I removed a layer" is not the same as "I am looking at a layer"

**Measured 2026-10-04 (round 145), and this one cost the most.** Two conclusions were
published from a probe named `mirroronly`, then withdrawn after a face map was added.

Bypassing **one** `blit` (the floor) does not isolate what is *under* it — it exposes
everything underneath, including an entire real group that the probe was never meant to
include. The numbers were real, the layer label was not: the frame reported the mirrored
walls at 76–83 luma and a 0.570 ref/frame ratio, when it was in fact reporting the real
group's walls. Two published findings were withdrawn.

**The failure was not exotic.** I had *already written up* pitfall 6 — "a probe that
does not isolate the layer you asked for" — and then applied an unisolated frame to a new
claim without re-checking it against the rule I had just banked.

**Three rules, in order of how much they would have saved:**

1. **A label in a variable name is not evidence.** `mirroronly`, `nofog`, `nobm` — the
   name records intent. Nothing more. Rename them to what they *omit* (`fullMinusFloor`)
   and the class of confusion largely disappears.
2. **Confirm the layer is present by making it identifiable, not by assuming it.**
   Painting each face or sub-layer a flat primary (`255'u32 shl 24` for R, `shl 8` G,
   `shl 16` B — note **alpha: a bare `255'u32` is RGBA(255,0,0,0), fully transparent**,
   which produces a confident all-black map that reads as "nothing is drawn here") turns
   an assumption into a measurement, and costs one build.
3. **Ask what the bypass actually leaves behind before drawing any conclusion from it.**
   Enumerate the remaining producers. If you cannot name them, you have not isolated
   anything — the differential form (rule 7) is the safe alternative, and it makes the
   question moot because only the layer under test differs.

**Corollary, from the alpha bug above:** when a layer's output is classified as "dark",
check whether it is *absent* before reasoning about its brightness. A genuinely absent
layer and a present-but-black layer need different next steps — a producer hunt versus
an alpha hunt — and conflating them sends the investigation to the wrong layer entirely.
Diff the layer's own output against its background (draw it over a known flat value and
subtract) to tell "absent" from "dark"; do not infer it from a low value alone.

The banked instruments live in `tools/probe/` and are verified running:
`brightiou.mjs` (lit-mask IoU sweep — use this in dark scenes, not a 128 threshold),
`brightmap.mjs`, `excessmap.mjs` (ref-only vs frame-only bright masks),
`deltahist.mjs` (one small bias, or many causes?), `gainfit.mjs` (tonal or structural?),
`hotmap.mjs` (which tiles, ranked), `scanline.mjs` / `colscan.mjs` / `tone.mjs` /
`pts.mjs` (pixel-level ref-vs-frame), `iou.mjs`, `gradscan.mjs` + `gradsem.html`.
All of them read a rawswapped frame as R,G,B,A.

### 9c. Reference PNGs are colourType 2 (RGB, 3 channels)
> **CORRECTED 2026-10-03.** `.board/frames/ref*.png` are colourType **2** — three
> channels, no alpha. The reflexive `stride = w * 4 + 1` therefore throws
> `Z_BUF_ERROR` (short IDAT) the moment you decode one; `w * 3 + 1` works.
> **Branch on `colorType`, never assume 4.** `tools/pngdiff.mjs:36` does
> (`ctype === 6 ? 4 : ctype === 2 ? 3 : 0`) and `tools/refdiff.mjs:40` does
> (`{0:1, 2:3, 4:2, 6:4}`) — copy one of those if you write your own decoder.

### 9d. A failed build leaves the OLD `.wasm` in place

> **CORRECTED 2026-10-03.** Nothing in `tools/build-wasm.sh` deletes the output
> before compiling, so a build that fails leaves the previous artifact sitting at
> the same path — and the driver loads and re-renders **that**, silently, giving a
> clean frame from stale code. `build-wasm: wrote $OUT` is the last thing the
> script prints on success (`tools/build-wasm.sh:176`). **Confirm you saw that
> line before you trust a single frame.** This is hard rule 2 with a sharper edge:
> "never trust a prebuilt artifact" also means "never trust a *stale* one you just
> rebuilt".

### 9e. `drive.exe` can spin forever instead of failing

**Measured 2026-10-04 (round 146).** A probe wasm that built cleanly produced no frame:
`drive.exe` reached **1,845 seconds of CPU** and was still running when it was killed. No
output file, no error, no exit — the harness simply never returns.

This is the failure mode that wastes the most, because it looks like slow progress. Two
compounding costs: the round's remaining budget is spent waiting, and if you have several
probes queued you do not find out which one hung until each is tried in turn.

**Rules:**

1. **Always run the driver as a background job, never inline.** A foreground
   `drive.exe` with no timeout can hold a turn open indefinitely — one did, for 20+
   minutes, before the harness moved it aside. `run_in_background` plus
   `job_output(wait:)` gives you a bounded wait and a killable handle.
2. **Check whether it is alive or looping before waiting on it.**
   `Get-Process drive | Select-Object Name,Id,CPU` — a large and climbing `CPU` value is
   a spin, not progress. A healthy render is seconds.
3. **A hung driver means no measurement, not a negative result.** Report it as
   *the probe produced no data*; never carry a hypothesis forward on the strength of a
   frame that was never written. The probe that hung was measuring the one candidate
   still open on that lane, so the lane parked with an untested suspect — which is the
   honest state, and is recorded as such.
4. **If a probe build compiles but the driver hangs, suspect the patch, not the app.**
   The probe had replaced a `blit` with a direct buffer `put` and wrote an opaque pixel
   over the floor; an app that renders fine for production renders is not the variable.

---

## 10. The one-paragraph version

Never commit junk or a prebuilt artifact; rebuild before you claim it works; never delete a test to
get green; wrap libraries, don't rewrite them; one task = one commit ≈300 lines; three strikes on
the same error means write it under "Stuck" and move on; anything user-visible goes to
`DECISION_QUEUE.md`; and never state a number you didn't measure. On the build path: native paths,
`--os:any`, real object files, no extra `-O2`, a flag-hashed nimcache — and confirm
`build-wasm: wrote …` actually printed, or you are looking at the last `.wasm`. In Nim:
declaration before use, and include paths shortest-to-longest. In the engine: a prop that
type-checks is not a prop that draws — screenshot the specific thing, and if you added a node
kind, the renderer mapping and `render/t_qml.nim` test ship in the same commit. And when the
pixels are the only truth: `log()` is never printed, frame dumps are BGRA until you swap them, and
`frameDt()` — not `yantra_get_dt()` — is the clock that actually ticks.