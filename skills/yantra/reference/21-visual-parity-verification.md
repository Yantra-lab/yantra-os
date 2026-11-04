---
name: visual-parity-verification
description: Proving a Yantra port matches its HTML source by real per-pixel comparison — build the native toolchain, render with drive.nim, screenshot the original with headless Chrome, and diff. Use when a port must be visually faithful, when "it looks right" needs to be a number, or when the native renderer appears to be unbuildable. Carries the byte-order rule, the reference-PNG colourType, the dead-frame check, and the text-metric limits that make a diff number meaningful.
---

# Visual parity verification

**What this chapter is for.** It turns "it looks right" into a number you can defend: build
the native harness, render a frame to a raw dump, screenshot the original at a known clock,
and diff them pixel by pixel. **After this chapter you can** name the true differing-pixel
percentage, say which number to trust when two disagree, and tell geometry error apart from
animation desync, colour error apart from channel-order error, and a dead frame apart from a
bad one.

The hardest thing about porting HTML to Yantra is that **nothing about a port looks wrong
until you look at it.** A wasm module compiles, the host loads it, the node tree has the
right shape, layers are submitted — and the picture can still be 64 pixels too low, a colour
channel reversed, or a whole viewport in the wrong place. Structural checks pass happily.

This skill is the instrument for turning "it looks right" into a number.

**Read next:** `01-build-run-and-verify.md` for the build and the headless harness itself;
`23-wasm-import-gate.md` when the module renders nothing at all; `24-draw-alpha-ramps.md` for
one specific rendering defect; `19-done-checklist.md` for the boxes this chapter feeds;
`18-porting-process.md` for the phase this sits inside.

**Read this first: there are two independent halves, and you need both.**

| half | tool | gives you |
|---|---|---|
| the port | `render/native/drive.nim` → `out.raw` | real pixels from the real Skia/SDL3 engine |
| the original | headless Chrome → `ref.png` | real pixels from the real browser |

Neither one alone proves anything. You need the same pixel dimensions on both sides, and you
need to know how the raw bytes are ordered.

---

## 1. The native toolchain looks broken when it is only uninstalled

This is the single biggest time sink, and the symptom is misleading. You will see:

```
fatal error: SDL3/SDL.h: No such file or directory
fatal error: libavcodec/avcodec.h: No such file or directory
fatal error: skia/SkCanvas.h: No such file or directory
```

and `third_party/msys64/mingw64/bin` will appear to exist while containing **zero files**.
Every prebuilt `.exe` in the tree will be older than the sources that supposedly produced it.

**Do not conclude the project cannot be built.** A bare `msys64` archive is the skeleton, not
an installation: it ships `usr/bin` with `pacman.exe` and empty package databases, and no
toolchain at all. If the network is reachable, the toolchain is one command away:

```powershell
cd third_party\msys64
.\usr\bin\pacman.exe -Sy --noconfirm
.\usr\bin\pacman.exe -S --noconfirm --needed `
  mingw-w64-x86_64-gcc mingw-w64-x86_64-skia mingw-w64-x86_64-sdl3 `
  mingw-w64-x86_64-icu mingw-w64-x86_64-harfbuzz mingw-w64-x86_64-freetype `
  mingw-w64-x86_64-ffmpeg mingw-w64-x86_64-jolt-physics mingw-w64-x86_64-curl `
  mingw-w64-x86_64-sqlite3 mingw-w64-x86_64-libblake3 mingw-w64-x86_64-pkgconf
```

That installs 146 packages (~2112 MiB). Some 404 on the first mirror; pacman retries others
and succeeds, so a 404 in the log is **not** a failure. Verify afterwards, don't assume:

```powershell
Test-Path third_party\msys64\mingw64\bin\g++.exe
Test-Path third_party\msys64\mingw64\include\SDL3\SDL.h
Test-Path third_party\msys64\mingw64\include\skia\SkCanvas.h
```

Check that the installed Skia matches the source tree the wrapper expects (e.g. skia
`143.r77119` against `third_party/skia-src-m143`) — a version mismatch produces link errors
that look nothing like a version mismatch.

**Do's**
- Derive every path from the script's own location (AGENTS.md rule 4), never `C:/Users/...`.
- Put `third_party\msys64\mingw64\bin` on `PATH` before running anything native.
- Build `drive.nim` with the same `--path` flags `tools/_probe-native.sh` uses.

**Don'ts**
- Don't trust any prebuilt `.exe` in the tree (AGENTS.md rule 2). Rebuild and check the
  timestamp; an "impossible" build failure is usually a stale artifact being run instead.
- Don't report "this environment cannot build the native renderer" until you have checked
  whether the toolchain is merely *absent* rather than *broken*.
- `mingw-w64-x86_64-libdatachannel` genuinely does not exist in MSYS2; `nimrtc` needs it. That
  one absence is not the same as "the build is impossible".

---

## 2. drive.nim gives you pixels, and the raw is BGRA

```powershell
render\native\build\drive.exe apps\<app>\app.wasm out.raw <W> <H> <scale> "<script>"
```

The script is **semicolon-separated**: `click:X,Y`, `down:X,Y`, `up:X,Y`, `move:X,Y`,
`drag:X1,Y1,X2,Y2`, `wait:N`, `key:N`, `text:S`. These go through the real pointer pipeline,
so a `down:` genuinely fires the app's handler.

A good `out.raw` is exactly `W * H * 4` bytes. **Check that first** — it is the cheapest proof
that you captured a whole frame and not a truncated buffer.

**The byte order is B, G, R, A.** The chain is worth spelling out, because one
tool in `tools/` concludes the opposite and a reader will hit both:

1. `drive.nim:191-193` copies a `seq[uint32]` straight out with `copyMem`, so the
   dump is whatever the uint32s look like in little-endian memory.
2. Those uint32s come from `libs/nimskia/src/skia_shim.cpp:707`:
   `readPixels(SkImageInfo::MakeN32Premul(w, h), pixels, w*4, 0, 0)`.
3. `MakeN32Premul` is Skia's **platform-native** 32-bit format. On win64 that is
   `kBGRA_8888` — the repo says so itself at `apps/minipaint/tests/t_pickergrad_probe.nim:24`
   ("kBGRA_8888: byte0=B, 1=G, 2=R, 3=A, PREMULTIPLIED").
4. Each element is therefore an `SkColor` of `0xAARRGGBB`, and little-endian memory
   reverses those bytes to **B, G, R, A**.

(`render/native/shot.nim:1` independently calls its own output a "raw BGRA dump".)

> **A live disagreement in `tools/`, unresolved by reading alone.** The header of
> `tools/refdiff.mjs:5-10` concludes *"despite the filename the frame is in straight
> RGBA byte order and no channel swap applies"*, argued from a round-82 measurement
> where swapping made the diff worse. **The code** at `refdiff.mjs:90-94` does no swap.
> That contradicts steps 1–4 above and the measured 91.45% unswapped vs 72.83%
> swapped.
>
> I am not resolving this by inspection, because the round-82 observation is real and
> something in it is unexplained — most likely that round's *reference* was the thing
> in the wrong order, which would make swapping look worse for a reason that does not
> generalise. Settling it needs one pixel measurement, which needs a render.
>
> **Until then: swap exactly once, before every diff, via `tools/rawswap.mjs`, and
> confirm the result on a frame containing a known colour before trusting a diff.**
> That check is cheap and it settles the question for your own run regardless of whose
> comment is right. `tools/` is outside this folder's scope, so this is reported, not
> fixed.

> **CORRECTED 2026-10-03.** This chapter previously cited the copy as `drive.nim:148-150`.
> Those lines are the `wait:` verb handler; the frame dump is written at
> **`render/native/drive.nim:191-193`** (`var bytes = newString(px.len*4)` /
> `copyMem(addr bytes[0], addr px[0], bytes.len)` / `writeFile(outPath, bytes)`).
> The wrong citation came from `tools/rawswap.mjs:5`, which repeats the same stale
> `drive.nim:148-150` in its header comment. The claim itself was always right; only the
> line numbers were not. **`tools/rawswap.mjs:5` still carries the old numbers and should be
> corrected by whoever owns `tools/`.**

### The swap is not optional — do it before every diff

> **CORRECTED 2026-10-03.** What this chapter used to say: *"The byte order is B, G, R, A …
> `tools/rawswap.mjs` does the swap; `tools/pngdiff.mjs` decodes a PNG and compares every
> pixel."* — i.e. the swap was presented as an option, and §12 presented the double-swap as
> the hazard. The stronger, measured rule is that **no diff tool in this repo swaps for you,
> so an unswapped raw is scored with R and B exchanged, and the headline number is wrong in
> a way that looks entirely plausible.**
>
> Evidence: `tools/pngdiff.mjs:100-103` compares `ref.rgba[i]` against `raw[i]`,
> `raw[i+1]`, `raw[i+2]` as R, G, B — **no swap**. `tools/refdiff.mjs:90-94` does the same.
> The bytes you hand them are B,G,R,A, so R is compared against B.
>
> Measured on one port, same reference, the swap the only difference:
> **91.45% unswapped vs 72.83% swapped.** The lower number is the true one.
>
> **The rule: `node tools/rawswap.mjs <in_bgra.raw> <out_sw.raw>` first, always, before any
> diff tool touches the frame.**

**And a double swap is just as bad.** `tools/floor.mjs:35` guards on the filename suffix —
`/_bgra\.raw$/i` means "already swapped, do not touch" — precisely because swapping twice
produced a garbage frame that reported 99.22% while `pngdiff` on the same file said 50.49%.
An instrument that contradicts the tool it calibrates against is worse than no instrument.

Do not take the order on trust — verify it against a known colour from the source. For
`029-typewriter-letters.html`, `body{background:#3a2212}` is RGB(58,34,18) (html:24), and the
dominant value in the raw dump was RGB(18,34,58). R and B exactly reversed. Swapping them
moved the port's reported difference from **99.98% to 92.72%** — the 99.98% was an artefact
of reading the channels backwards, not a real difference.

**Do** confirm the channel order against a hard-coded CSS colour in the source whenever you
start a new app. It costs one grep and it is the difference between a meaningful number and
a meaningless one.

### Reference PNGs are colourType 2 — branch on it before you decode one

> **CORRECTED 2026-10-03.** This chapter did not say, and a reader writing a decoder assumed
> four channels. **Every reference PNG under `.board/frames/ref*.png` is colourType 2 —
> RGB, 3 channels, depth 8.** Verified on all ten files in `.board/frames/` (`ref_00500.png`,
> `ref_01000.png`, `ref_02000.png`, `ref_04000.png`, `ref_039_800.png`, `ref052.png`,
> `ref052b.png`, `ref070.png`, `ref075.png`, `probe.png`).
>
> The consequence is a thrown exception, not a wrong number: a decoder that assumes
> `stride = w * 4 + 1` fails the length check and throws. `tools/refdiff.mjs:40` branches on
> it — `const ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]` — and derives `stride = W * ch`
> (`refdiff.mjs:43`). **`w * 3 + 1` is the working stride for these references.**

### The frame must come from the build you just made

> **CORRECTED 2026-10-03.** This chapter did not say, and it is the failure that makes every
> other number in the chapter meaningless. **A failed wasm build leaves the OLD `.wasm` in
> place, and `drive.exe` will happily re-render that stale artifact** — producing a full-size
> raw, exit 0, and a confident number for code that does not exist.
>
> The real occurrence: a stale `hello.wasm` once hid an SDK that did not compile (AGENTS.md
> rule 2). **Always confirm the build printed `build-wasm: wrote …` before you trust a
> frame.** `tools/guard-29.ps1:65-69` is the pattern — it checks the module exists *and*
> re-stamps the last-write time, because "a stale artifact the build failed to replace is
> exactly the failure mode rule 2 exists to catch."

### `log()` will not tell you anything, and it is not free

> **CORRECTED 2026-10-03.** Anything that tells a reader to instrument a port with `log()`
> is wrong. `log()` compiles, is callable, and **nothing in the repo ever reads it.**
>
> `host/host.nim:628` — `cbLog` does `host.logs.add readStr(...)`. That is the only writer.
> `host/host.nim:1029` binds `yantra_log` to it. The only reader anywhere is
> `render/native/t_mpopen.nim:173`, and that reads a *different* log — the engine's
> capability log `e.s.logs`, not `host.logs`. No runner prints the collected lines.
>
> It is also expensive: one `log()` call measured **+15,660 bytes** — about **7% of a
> ~215 KB module**.
>
> **Instrument by drawing something, or by reading pixels.** `drive.exe` does give you three
> real instruments: the `boxes` verb (`drive.nim:82-90`) prints the laid-out tree with no app
> instrumentation at all, `DUMP_GEOM=1` (`drive.nim:183-189`) prints laid-out rects, and
> `crash` (`drive.nim:91-99`) prints the crash string — which is how you discover that an
> app exited 0, wrote a full raw of the right size, and painted nothing of its own
> (`drive.nim:159-163`).

---

## 3. Screenshot the original with headless Chrome

> ⚠️ **Read the note immediately below before using this command line.** It is here so
> you can see the raw invocation, but **`tools/capture-ref.ps1` is the supported path**
> and it handles the viewport question correctly. The window size is **not** the page's
> layout width, and the size you pass is a page-specific choice, not a constant —
> see "The window size is NOT the page's layout width" further down. Passing
> `--window-size=1280,816` blindly is what produced three rounds of wrong scores here.

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless=new --disable-gpu `
   --no-sandbox --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,816 `
   --virtual-time-budget=4000 `
   --screenshot="C:\...\ref.png" "file:///C:/.../original.html"
```

`--force-device-scale-factor=1` matters: without it Chrome honours the host DPI and you
compare a 1280-wide image against a 1920-wide one. `--virtual-time-budget` lets the page's
own rAF/JS run before the capture — a page of generated art captured too early is blank, and
you will blame the port for it.

> **Note that `--hide-scrollbars` does NOT make the window size the layout width.** It hides
> the scrollbar but leaves `innerWidth` at 1264 when the window is 1280. Verified by
> measurement, 2026-10-04.

### Use `tools/capture-ref.ps1`, and never capture a reference whose clock you did not record

> **CORRECTED 2026-10-03.** This chapter taught the raw Chrome command line above and never
> mentioned that the reference files already sitting in `.board/frames/` were captured at an
> **unrecorded** virtual-time budget. `tools/capture-ref.ps1` now exists for exactly this
> reason — its own header says *"Never capture a ref without recording T"*, and it takes the
> budget as its third argument and prints it back.
>
> The cost of not knowing the clock is measurable, not theoretical. **Two independent
> headless captures of the SAME animated page at the same nominal 800 ms budget differ from
> each other by 2.13%** — 22,288 of 1,044,480 pixels. That is the noise floor of the
> instrument.
>
> **A comparison against a reference of unknown clock measures clock difference and reports
> it as port error.** Any `ref*.png` captured before `tools/capture-ref.ps1` existed must be
> re-captured, or the port's score is meaningless and will chase you for hours.

```powershell
pwsh -NoProfile -File tools/capture-ref.ps1 path\to\original.html .board\frames\ref.png 4000
```

> ### The window size is NOT the page's layout width — pick the mode per page, don't reason about it
>
> **Measured 2026-10-04 (round 139).** This is the third-largest source of a wrong score
> in this repo and it is invisible, because the capture succeeds and the PNG has the
> dimensions you asked for.
>
> At `--window-size=1280,816` headless Chrome reports **innerWidth=1264, innerHeight=721**
> — measured, and **even with `--hide-scrollbars`**, because that flag hides the scrollbar
> without shrinking the layout viewport. Then CSS splits the two metrics apart:
>
> | CSS metric | resolves to | at window 1280x816 |
> |---|---|---|
> | `100vw` | ICB width, scrollbar **included** | **1280** |
> | `innerWidth` / `clientWidth` / `100%` | scrollbar **excluded** | **1264** |
>
> So "capture at the target and add 16px" is correct **only for pages that lay out against
> `clientWidth`**, and 16px *wrong* for pages that lay out against `100vw`. **There is no
> single correct window size — there is one per page, and you cannot tell which from the
> HTML alone without measuring.**
>
> In this repo **four of five ports are `100vw` pages.** Chess is the proof this is a real
> split and not a nudge — measured at the same clock (`wait:8`, tol 8), capturing only the
> window size apart:
>
> | port | layout metric | no overhead | with overhead |
> |---|---|---|---|
> | chess | `100vw` | **18.42%** | 58.57% |
> | dna | `100vw` | **9.98%** | 16.26% |
> | calligraphy | `100vw` | **20.74%** | 38.37% |
> | gallery | `100vw` | **57.37%** | 62.66% |
> | typewriter | `clientWidth` | 60.51% | **31.82%** |
>
> **40 points on one port, from the window size alone, on code that round never touched.**
>
> **What to do:** pass the mode, don't derive it.
>
> ```powershell
> pwsh -NoProfile -File tools/capture-ref.ps1 page.html ref.png 800 1280 800 nooverhead
> #                                                        ^budget  ^W   ^H  ^mode
> ```
>
> `nooverhead` captures at exactly the target window and skips both the probe and the crop.
> It still runs the final output-dimension check — only the irrelevant verification is
> skipped. Measure both ways once per new page; that is cheaper than reasoning about it.
>
> **The trap that hid this for three rounds:** the script's verification probe asserts
> `clientWidth`. In the compensated mode that assertion is **correct by construction**, so it
> reports success while the page is being laid out 16px too wide. The round that "fixed" it
> forced a scrollbar onto the probe — making the four `100vw` ports wrong — and the
> verification passed. **A guard that can only fail on the probe, when the probe is fine, is
> decoration.** Check the OUTPUT (the PNG's dimensions), not a proxy for it.
>
> One more trap in the same command: the 3rd positional arg is `budgetMs`. Passing
> `nooverhead` in the `viewW` slot makes `[int]'nooverhead'` evaluate to **0** — a zero-width
> window that **hangs forever** rather than erroring. A hung Chrome is not a slow Chrome.

> ### The other way a reference goes stale, and the test that tells them apart
>
> The clock lesson above assumes the reference is *old*. There is a second failure
> mode that has nothing to do with clocks, and it is far more dangerous because every
> measurement made against it looks completely healthy.
>
> **Measured 2026-10-04.** A port scored **16.70%** and looked like the best of five.
> Scored against a fresh capture of *the same HTML at the same budget* it scored
> **59.34%** — the worst of the five. Its shipped reference differed from a real
> capture by **577,429 px (55.28%)**, while two fresh captures agreed with each other
> to **0.28%**.
>
> The page had been edited; the reference had not. The port had then been *optimised
> toward the stale file*, so every lane measurement was internally consistent,
> monotone and reproducible — **against the wrong target**. A lane improving toward a
> stale reference produces real, bankable, entirely misleading gains. Nothing in the
> normal chain catches it, because the scorer is told which file to trust and never
> asks whether that file still corresponds to the page.
>
> **The tell that separates this from clock noise** — capture the reference a *second*
> time and diff the two captures:
>
> | two fresh captures of the same clock agree | verdict |
> |---|---|
> | ~0% (the tool reproduces itself) | the shipped reference is **stale** — the page moved |
> | 1–10% | genuine capture noise (async canvas, animation mid-flight) — quote the spread |
>
> Run `tools/verify-refs.ps1`. It does this per port and exits non-zero on a stale or
> unverifiable reference.
>
> **And do not quote one noise figure.** 2.13% above is a single sample. Measured
> across ports the same way, the floor ranges **0.00%** (calligraphy, typewriter) to
> **8.92%** (gallery, whose canvases fade off an async bake), with chess at 1.73% and
> DNA at 0.10%. Quote the distribution for *your* page — measure it twice.
>
> One trap in the verifier itself, worth knowing because it is easy to repeat: **an
> ESM `import()` specifier of `C:/foo/bar` is invalid**, and if the surrounding script
> parses a thrown stack trace as `0%` it will report every reference as *current* while
> node has crashed. Make an unparseable result an explicit failure — never a pass.

Three details it gets right that the hand-rolled command does not: it derives paths from its
own location (AGENTS.md rule 4), it passes an absolute path to `--screenshot` (a relative one
silently produces no file), and it uses a throwaway `--user-data-dir` so a running Chrome
profile cannot hijack the capture.

---

## 4. Read the diff before you read the percentage

> **CORRECTED 2026-10-03.** What this chapter used to say, in its own words: *"`tools/pngdiff.mjs`
> prints a differing-pixel count, mean and max channel delta, the worst rows and columns, and
> an 8×8 band map. **The band map is the diagnostic, not the headline number.**"* — and it
> then used the band map to tell a global-transform failure from a localised one.
>
> **The band map reads artificially low, and it has produced three rounds of confidently
> wrong conclusions about one port.** Evidence: `tools/pngdiff.mjs:133` gates its band cell
> on `if (rows[y] && cols[x] && …)`, so **any row OR column with zero differing pixels
> contributes nothing** to its cell — the pixel is skipped, not counted as agreeing.
>
> **What is unaffected, and what you must trust:** the headline
> **`differing pixels`**, **`mean |delta|`** and **`max |delta|`** are computed in the main
> per-pixel loop (`pngdiff.mjs:95-108`) before any of the gating, and remain authoritative.
> The `worst rows` / `worst cols` lists (`pngdiff.mjs:113`, `:120-121`) are computed from the
> same ungated per-pixel counters and are also sound.
>
> **The rule: quote `differing pixels` / `mean |delta|`. Never quote a pngdiff band cell as
> evidence. Route all localisation to `tools/refdiff.mjs`**, whose bands are ranked from a
> real per-pixel mask (`refdiff.mjs:104-124`) and so do not have the flaw. `refdiff.mjs:12-18`
> documents this exact trap in its own header.

`tools/pngdiff.mjs` prints a differing-pixel count, mean and max channel delta, the worst
rows and columns, and an 8×8 band map.

Once the headline number is in hand, the two failure modes you must not confuse:

- **every band at 100%** → a global transform: wrong channel order, wrong colour space, or a
  gamma mismatch. Nothing about the layout is wrong; your instrument is.
- **a flat `differing pixels` across a re-render at a different `wait`** → geometry or tone.
  See §10 for the sweep that decides this.

A uniform 100% once sent me hunting for layout bugs that did not exist.

### Classify the diff before you theorise about it

> **CORRECTED 2026-10-03.** This chapter did not state the rule as a rule; it presented a
> timeline sweep at the end (§10) as one port's data. It is the single most reusable test in
> this chapter, so it is now stated up front:
>
> | what the diff does when you re-render at a different `wait` | what it is | what to do |
> |---|---|---|
> | **flat** | geometry or tone — time-invariant | stop looking at animation; fix composition |
> | **growing** with time | animation desync | fix the clock and the `frameDt()` integration |
>
> One test — re-render at a second `wait` and compare — has repeatedly been worth more than an
> hour of staring at a diff. Do it before you form a theory.

Sampling named regions is sharper still. For 029, sampling the same coordinates in both
images produced:

| region | original | port | reading |
|---|---|---|---|
| paper middle | (229,221,201) | (230,222,203) | matches within 2/255 |
| paper top | (239,232,218) | (65,40,21) | port's paper starts lower |
| bottom of frame | (138,184,163) | (134,180,159) | matches |

Two regions matching and the ones between them not is a **pure vertical offset** — and it
took one round of pixels to prove what seventeen passing structural tests had not.

### The second classifier: split grain from structure by diffing twice

> **NEW 2026-10-04.** The clock sweep above tells you *whether* the error is time-varying.
> It cannot tell you *how much of it is worth attacking*. For that, run `tools/pngdiff.mjs`
> on the same frame **twice — once at tol 8, once at tol 24**:
>
> ```powershell
> node tools/pngdiff.mjs $ref $sw 1280 816      # tol 8  (the default)
> node tools/pngdiff.mjs $ref $sw 1280 816 24   # tol 24
> ```
>
> | pixels | meaning |
> |---|---|
> | differ at **tol 8**, identical at **tol 24** | **GRAIN** — texture no generator will match exactly |
> | still differ at **tol 24** | **STRUCTURE** — wrong geometry or wrong tone, i.e. the real work |
>
> Measured across the five live ports:
>
> | port | tol 8 | tol 24 | grain | **structure** |
> |---|---|---|---|---|
> | 052 dna | 105,066 (10%) | 82,316 (8%) | **22%** | **82,316 px** |
> | 070 chess | 221,358 (21%) | 39,605 (4%) | 82% | 39,605 px |
> | 029 typewriter | 262,565 (25%) | 128,063 (12%) | 51% | 128,063 px |
> | 075 calligraphy | 225,662 (22%) | 56,565 (5%) | 75% | 56,565 px |
> | 039 gallery | 741,228 (72%) | 367,633 (36%) | 50% | 367,633 px |
>
> **This refuted a live claim.** A lane reported 052 as "at its floor". On the headline
> number it is the best port of the five; by *structure* it is the **worst** — the lowest
> grain fraction of all five, carrying more structural pixels than 070 and 075 combined.
> Both statements were true of different quantities, and only one of them was actionable.
>
> **So "at the floor" is a claim about structure, and you owe it a measurement.** The
> smallest tol-8/tol-24 gap is not proof of a floor — it is proof that the rest is grain.
> `.board/scoreboard.ps1` now prints a `structure` column for exactly this reason: a scorer
> that can only report one number cannot refute a claim made about the other one.
>
> **Corollary — score colour candidates at tol 8, never on mean offset.** Narrowing a grain
> window from one side only pushes half the noise out the other side. On 070 a dark-square
> blue −4 shift **gained 80 px at tol 24 and lost 3,297 at tol 8**: on the loose tolerance
> it is a win, on the real one it is a large loss. A mean-|Δ| improvement is not evidence.
>
> **When a region is pure grain, stop.** The residue on 070 and 075 is Chrome's
> `feTurbulence`. Reimplementing fractalNoise plus the conic quarter-tile mask is a real
> project, and a *wrong* generator scores worse than drawing nothing at all. Say so in the
> notes and spend the round on the regions that are still structure.

### A "the region is empty" reading is nearly always a broken invocation

> **NEW 2026-10-04.** This has now been re-learned by three separate lanes in one session,
> always in the same shape: a probe reported "the port draws nothing here", which reads as
> a clean finding, and turned out to be one of —
>
> - probe coordinates **outside the surface** (negative layer coordinates sample the desk)
> - a **PNG read as raw bytes**, so one half of a two-image comparison was meaningless
> - the tool's own **PRNG simulator** disagreeing with the JS, manufacturing a convincing
>   "analytic prediction" of a port defect
> - an `argv`-shape mismatch — PNG takes `<png> <x0> <y0> <x1> <y1>` with **no** W/H
>
> The rule that survives: **a measurement instrument that cannot fail will fail
> confidently.** `mean.mjs` and `bbox.mjs` print `n=0` rather than erroring; `pngdiff`
> scores a truncated raw as a perfect match; `raw2png.mjs` double-swaps an
> already-swapped raw; `drive.exe` re-renders a stale `.wasm` silently. Before trusting a
> scratch tool, **validate it against `tools/pngdiff.mjs`** — or make it refuse: the
> hardened region probe exits 3 with `FATAL` on an empty rect and rejects a raw that is
> not exactly `W*H*4` bytes. A tool that refuses is worth more than one that answers.

---

## 5. An app that creates no nodes crashes the host (engine defect)

```nim
# apps/probe/empty.nim — the whole file
import yantra
proc yantra_main*() {.exportc: "yantra_main".} = discard
```

Running that through `drive.exe` crashes with an unhandled exception:

```
engine.nim(4144) start
engine.nim(1517) layout
Error: unhandled exception: index out of bounds, the container is empty [IndexDefect]
```

`engine.nim:1517` is `let root = e.node(0)` — it indexes node 0 without checking that any
node exists. An app that builds no tree takes the host down instead of producing an empty
frame. (`proc start*` is at `render/native/engine.nim:4136`; the `4144` in the trace is a
frame line inside it from the run that produced it, not the proc header.)

Two lessons, and the second is the one that costs you:

- The fix belongs in `layout`: return early when `e.s.nodes.len == 0`.
- **When a port crashes the engine, reproduce it in six lines before you debug the port.**
  This exact trace meant "your app built nothing", but it looked exactly like a renderer fault.
  A minimal repro distinguishes the two in one build.

---

## 6. Structural checks cannot see layout

The checks in `tools/verify-wasm.mjs` — entry point present, layers submitted, node counts,
event handlers registered — passed 17/17 on a port whose entire scene was displaced 64px
downward and 64px too short. Every one of those assertions was true and none of them cared.

> **CORRECTED 2026-10-03 — a caveat on "entry point present".** `tools/verify-wasm.mjs` has
> since gained a real import gate: it parses `host/host.nim`'s `importTable()` out of the
> source at run time (`verify-wasm.mjs:140-166`) and refuses before instantiating if the host
> would refuse (`:172-229`). That gate is genuinely worth having. But its *entry point*
> line reports a fact about the module, not about the app — see §18: a module can report
> `yantra_main present = false` and still pass every other assertion in the file.

They are still worth having; they just answer "is this wired up", never "is this in the right
place". For that, see §8 — **ask the real engine for the rects.** Pixels are the ground truth
that proves the fix worked; the layout dump is the cheaper instrument that tells you *which*
node is wrong and where.

**Always render before you call a port done — and when it renders wrong, dump the rects
before you start theorising.**

---

## 7. Two ways to measure something other than the thing

Both of these cost me a round each. Neither was the code's fault.

### Piping a native command into `Select-Object -First N` truncates it

```powershell
# WRONG — kills drive.exe mid-write, leaving a SHORT frame file
& drive.exe app.wasm out.raw 1280 816 1 "" | Select-Object -First 1

# RIGHT — capture fully, then decide what to look at
$out = & drive.exe app.wasm out.raw 1280 816 1 ""
Write-Output "exit=$LASTEXITCODE"
```

The symptom is a raw dump whose byte count is not `W * H * 4`. I read that as "the canvas
changed size" and reported a regression that did not exist; the unfiltered re-run gave
exit 0 and exactly 4,177,920 bytes. **Always check `exit` and `bytes == W*H*4` together,
and never pipe a native process into a truncating cmdlet just to shorten its output.**

### Assert on the value captured AFTER the phase that renders

A handler that mutates state and lets the frame loop repaint has not changed the
*drawing* yet. Asserting on a value read immediately after dispatch compares the
pre-repaint output with itself:

```
pDraw length before=50039 afterPress=50039 afterFrames=50187
                                ^ unchanged        ^ this is the one that moves
```

That check failed at **every** click coordinate, valid ones included, which looks like
"the pointer is dead" and is not. The giveaway was dead code: `afterFrames` was computed
and never referenced anywhere in the file.

**Do** assert on the post-repaint value, and **prove the assertion still has teeth** by
showing the non-zero delta (50039 → 50187 above). A check that passes because it compares
nothing is worse than one that fails.

### Match the line you think you are reading

`Select-String 'pDraw length' | Select-Object -First 1` returned a *different* check's
line — one that legitimately prints "(unchanged is CORRECT)" — and I briefly reported that
someone had weakened the test. They had not. A `-match 'checks passed'` verdict is no
safer: that string appears in the **failure** summary too.

Print the exact line you mean, and never infer pass/fail from a substring that appears in
both outcomes.

---

## 8. A passing structural check cannot tell you where anything landed

`tools/verify-wasm.mjs` is a **mock host**. It records the node tree and the `Draw`
strings, but it never runs a Yoga layout pass, so **`y_node_size` returns 0 for every
node, always**. A node dump from it describes structure — kinds, children, parents —
and nothing about position.

That gap is not cosmetic. Measured on the 029 header:

```
[2] w=707  h=64  x=0   y=0      <- header row SHRINK-WRAPPED to its content
[11] x=583 w=104                <- last button ends at x=687; x=687..1280 is EMPTY
```

The tree was structurally perfect — right kinds, right children, right handlers, 17/17
checks green — while the entire control cluster sat ~590px left of where it belonged.
`justify-content:space-between` on a shrink-wrapped row does not spread anything.

**To measure layout, go through the real engine.** `Engine.nodeRect*(id)` (in
`render/native/engine.nim`) returns the laid-out `(left, top, width, height)`, zero for a
node with no Yoga node. `render/native/drive.nim` dumps it to stderr when `DUMP_GEOM` is
set, and it writes only to stderr, so the raw frame is untouched:

```powershell
$env:DUMP_GEOM="1"
& render\native\build\drive.exe app.wasm out.raw 1280 816 1 "" 2>&1 |
  Select-String '\[\d+\] w='
Remove-Item Env:\DUMP_GEOM
```

After the fix the same dump reads `x=653 w=599` — the cluster ends at 1252 = `1280 - 28px`,
matching the source's `padding:22px 28px 0`. Pixels moved 87.35% → 85.66% and
mean |delta| 63.47 → 54.14.

**Generalised: when a port looks structurally right and visually wrong, the discrepancy
is usually in a property the mock cannot observe.** Position, z-order, overflow clipping
and computed size all live there. Reach for the real engine before theorising.

---

## 9. Building `drive.exe` from PowerShell — the arg-array trap

`drive.exe` is native, not wasm, so it does **not** go through `tools/build-wasm.sh`.
It compiles against every library in `libs/`:

```powershell
# WRONG — one argument, Nim sees only the FIRST --path, then dies with
# "cannot open file: nimwasmtime" and almost no output:
& nim c --hints:off --warnings:off $paths -d:drive -o:... render/native/drive.nim

# RIGHT — an array, splatted, so each --path is its own argument:
$argsList = @('c','--hints:off','--warnings:off')
Get-ChildItem libs -Directory | ForEach-Object {
  $argsList += "--path:$($_.FullName -replace '\\','/')/src" }
$argsList += @('-d:drive','-o:render/native/build/drive.exe','render/native/drive.nim')
& nim @argsList
```

A space-joined string passed to a native command is **one** argument. When a native build
"produces no error but no binary either", check `$LASTEXITCODE` and the `.exe` timestamp
before assuming the source is at fault — a stale `drive.exe` that silently failed to
rebuild will happily keep answering with the old behaviour.

Also: `e.yoga` is a **private** field of `Engine`. Expose a `*` accessor rather than
reaching into the engine from `drive.nim`.

---

## 10. Both sides must be on the same clock — or the diff is meaningless

This is the rule that costs the most when it is broken, because the numbers look real.

Chrome freezes the page at a moment: `--virtual-time-budget=T`.
`drive.exe` advances the app with the script's `wait:N`.

```
Chrome  --virtual-time-budget=4000   -> a frame at t = 4000 ms
drive   ""            (empty script) -> a frame at t = ~0
pngdiff.mjs  ref4000.png  vs  t0.raw -> 85.66%   <- a number that means nothing
```

Measured on the 029 typewriter: the empty-script render scored **85.66%** against a
4000 ms reference, while the time-matched `wait:4000` render scored **91.04%** against
the same reference. Same app, same image, 5.4 points of pure clock error.

**Always pass a `wait:` that equals the Chrome budget.** A "static baseline" taken with an
empty script is not a baseline; it is a diff of two unrelated instants.

### A flat diff over time is a real finding — use it to classify the error

Once both sides share a clock, sweeping the timeline tells you *what kind* of wrong the
port is:

| t (ms) | 500 | 1000 | 2000 | 4000 |
|---|---|---|---|---|
| differing | 90.98% | 90.89% | 91.04% | 91.04% |

A 0.15-point spread across 3.5 seconds means the error is **time-invariant** — geometry
and tone, not animation timing. A port with desynced animation diverges harder the
further out you sample, because the carriage and the paper are in different places at
each instant. So a flat sweep means: *stop looking at the animations, go fix the
composition.* That one table redirected a round of work.

### Run the timeline with `tools/parity-timeline.ps1`

```powershell
pwsh -NoProfile -File tools/parity-timeline.ps1 -Times '500,1000,2000,4000'
```

Three traps in that tool, all measured, all now handled — read them before rewriting it:

- **`-Times` is a string, not an array.** `pwsh -File script.ps1 -Times 500,1200` binds
  the argument as the single value `5001200`. The param takes a string and splits it.
- **Never invoke Chrome with `&`.** It blocks on Chrome's entire process tree and the
  tool hangs forever. Chrome is fine — `Start-Process -PassThru` + `WaitForExit(ms)`,
  then `Kill()` on timeout.
- **Chrome needs an absolute Windows path** for `--screenshot`. A relative path
  produces no file, and the absence looks exactly like a timing failure.

It also covers **animation parity only** — headless Chrome cannot click. Interaction
parity needs a variant HTML that injects synthetic events on a timer, and that must not
be faked: a click fired at the wrong moment produces a diff that looks like an app bug
but is a harness bug.

---

## 11. The blank-frame floor — know when your percentage means nothing

A "differing pixels %" saturates. Once a frame is mostly empty, every possible frame
scores about the same, so the number stops discriminating and **starts lying**: it looks
like a near-miss when it is really a total failure.

Measure the floor explicitly. Replace the port frame with a flat fill at the reference's
mean luminance and diff that:

```
039, port frame          -> 98.70% differing
same size, flat grey 55  -> 98.07% differing      <- the blank-frame floor
                        => the port's rendering effort is worth 0.63 points
```

**98.70% and 98.07% are the same result.** All that effort is worth six tenths of one
percent. Tune against that number and you will chase geometry for hours while the app
paints nothing.

**The corollary is the census, and it is one command:**

```powershell
node tools/census2.mjs <ref.png> <frame.raw> <W> <H>
```

```
REFERENCE  distinct=72,533   mean=(59.9, 53.3, 46.9)
PORT       distinct=   672   mean=( 0.9,  1.1,  1.2)   91.13% pure #000000
luminance  ref : 28.0 22.6 26.7 12.5 6.3 2.9 0.7 0.3
           port: 99.6  0.2  0.1  0.0 0.0 0.0 0.0 0.0
```

672 distinct colours against 72,533, and 99.6% of pixels in the darkest bin, is not a
port that is *nearly* right. Check the census **before** reading any percentage, and if
the port is near-black, fix the backdrop first — until a full-frame fill lands, no
per-element pixel work can be measured at all.

### A pass signal is not a render

#39 exited 0, laid out a window at exactly `1280x800`, and wrote exactly `W*H*4` bytes —
every structural signal said healthy — while painting 91% pure black. `node -e` on the raw
would have said "works". Only the census caught it.

Corollary for triage order, cheapest and most decisive first:
**census → crash string → blank-frame floor → headline `differing pixels` → geometry →
per-region diff via `tools/refdiff.mjs`.** The full order is §19. The `pngdiff` band map is
not on it: when a frame is blank every band saturates uniformly and the map tells you
nothing (measured: all 56 cells 99–100%), and even on a good frame its cells are gated at
`pngdiff.mjs:133` and read artificially low (§4).

---

## 12. Do not double-swap: BGRA raw → RGB swapped → read as BGRA again

> **Superseded in emphasis, 2026-10-03.** §2 is now the stronger and more complete statement:
> **no diff tool swaps for you, so the swap is mandatory, not optional.** This section is
> kept because it documents the specific way that rule gets broken in the other direction.

This produced a *confidently wrong* conclusion twice, and it is easy to repeat because
the symptom looks like a real rendering bug.

`drive.exe` writes **BGRA**. `tools/rawswap.mjs` converts that to RGB. Any tool that then
reads the `*_bgra.raw` **as if it were still BGRA** swaps it back. A warm walnut-and-brass
room comes out reading as `(97, 115, 125)` — blue-dominant — which looks exactly like the
port has the wrong palette and is *not* a plausible tooling mistake.

**The guard is the filename.** `tools/floor.mjs:35` tests `/_bgra\.raw$/i` and skips the swap
for a file that already carries that suffix — because swapping a swapped frame produced
99.22% where `pngdiff` on the same file said 50.49%. Name your swapped output so the guard
knows what it is holding.

**Settle the order by proof, once, rather than by argument:**

```
walnut rgb(58,34,18)     as RGBA bytes -> 0       as BGRA bytes -> 127,820
mint   rgb(134,180,159)  as RGBA bytes -> 0       as BGRA bytes ->  96,652
```

Pick a colour the app *provably* draws, search the **unswapped** raw for both byte orders,
and the count that is non-zero settles it. Corrected, the same frame reads `(124.7, 115.5,
97.0)` — warm, matching the reference's `(145.0, 124.2, 100.1)`.

`tools/census2.mjs` therefore takes an explicit mode:

```powershell
node tools/census2.mjs ref.png frame.raw     1280 816       # raw is BGRA
node tools/census2.mjs ref.png frame_bgra.raw 1280 816 rgb   # already RGB
```

**The general lesson, which has now cost four rounds:** the recurring failure in this
project is not a wrong fix — it is a *right-looking number from an instrument that was
never validated*. Stale renders, a truncated native process, a mismatched clock, and now a
double swap. Before trusting a measurement, confirm two things: that it read the artifact
you think it did, and — via the blank-frame floor — that it still has dynamic range.

## 13. The blank-frame floor decides whether a percentage means anything

Run it on every port before quoting its score:

```powershell
node tools/floor.mjs <ref.png> <frame.raw> <W> <H> [tol] [refMeanLuma]
```

Measured, same session, same tool:

| port | score | blank floor | signal | meaning |
|---|---|---|---|---|
| 029 typewriter | 91.04% | 99.89% | **8.85 pts** | real signal — trust it |
| 039 gallery | 98.70% | 98.07% | **0.63 pts** | saturated — do not tune against it |

Two ports whose percentages look comparable are not comparable at all. The floor is what
tells them apart, and it costs one command.

---

## 14. Dead frames — a byte-identical diff proves nothing

> **Added 2026-10-03.** `24-draw-alpha-ramps.md:80-82` cites this chapter as
> "`21-visual-parity-verification.md` §on dead frames". This section is what makes that
> reference resolve. (24 was not edited to match.)

A **dead frame** is one where the port drew nothing, or where an upstream step destroyed the
frame before the code under test ran. It is the failure mode that produces the most
dangerous evidence in this project: **a number.**

The trap: if two code paths both read from a frame that was already dead, they return
**byte-identical output**. A diff of zero between them looks like a pass. It means the
comparison had nothing to compare.

Three dead-frame sources, all measured in this repo:

1. **The crash path.** `render/native/drive.nim:159-163` records it: the engine suppresses
   `frameEvent()` when `e.crashed` is non-empty and `paint()` diverts to `paintCrashed`
   (`engine.nim:2331-2333`). **An app can exit 0, write a full raw of exactly `W*H*4` bytes,
   and still have painted nothing of its own.** `drive.exe` exited 0 while the gallery
   rendered black. The `crash` verb (`drive.nim:91-99`) prints the string; `drive.exe` also
   writes `crashed=[…]` unconditionally (`drive.nim:163`), so **always capture stderr**.
2. **The empty-tree path.** An app that creates no nodes takes the engine down at
   `engine.nim:1517` (§5 above) rather than producing an empty frame.
3. **The unallocated-layer path.** `Y 0` in the Draw stream means an unallocated layer:
   `sdk/ui/paint.nim:102-106` increments `layerSeq` *before* first use, so id 0 is the
   uninitialised default and the shim silently skips it (`drive.nim:170-172`).

**The three checks, in order, before you believe any diff:**

| check | command | dead verdict |
|---|---|---|
| crash string | `drive.exe … "crash"`, or read stderr `crashed=[…]` | non-empty ⇒ dead |
| census | `node tools/census2.mjs <ref.png> <frame.raw> <W> <H>` | 1–2 distinct colours ⇒ dead |
| first Draw command | `drive.exe … "wait:4"` and read `pDraw[…]` on stderr (`drive.nim:173-177`) | `Y 0` first ⇒ dead |

Only after all three pass does a diff number mean anything. And if two paths that differ in
the source produce a **byte-identical frame**, suspect the frame, not the paths.

---

## 15. Colour alpha: `Draw` takes AARRGGBB, and a pasted CSS hex is invisible

> **CORRECTED 2026-10-03.** Chapters on porting and on colour have shown colours as bare
> hex literals — `0xF7F9FB` — as if a CSS hex were a Yantra colour. **It is not.** `Draw`
> and every node fill take `argb: uint32` in **AARRGGBB** (`sdk/ui/paint.nim:55`, `:57`,
> `:59`, `:61`, `:63` all take `argb: uint32` and interpolate it straight into the command
> string).
>
> A CSS hex pasted straight in — `0xF7F9FB` — has alpha bytes `0x00`. **It compiles, it
> runs, it crashes nothing, and it draws fully transparent.**
>
> Measured on port #52: adding the alpha bytes moved it from **100% differing to 23.7% in
> one edit.** The whole remaining error was one missing byte per colour.
>
> The safe pattern is a `hex()` helper that forces the alpha on. `apps/chess/app.nim:100`
> is the one to copy:
>
> ```nim
> proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)
> ```
>
> **Every chapter that shows a colour must say this.** Grep your app for bare hex literals
> before you read any percentage.

---

## 16. Text geometry: `y` is the TOP OF THE LINE BOX, and there is no measurement API

> **CORRECTED 2026-10-03.** `libs/nimskia/src/nimskia.nim:76` documents `drawText` as
> *"Draws `s` with its top-left at (x, y)"*, and any chapter repeating that sends readers to
> the wrong `y` by a predictable, measurable amount.
>
> Evidence that the doc comment is wrong: `libs/nimskia/src/skia_shim.cpp:291` calls
> `p->paint(static_cast<SkCanvas*>(c), x, y)` — Skia's `SkParagraph::paint` treats `y` as the
> **top of the paragraph line box**, not the baseline. `nimskia.nim:76` is not a simplification
> of the truth, it is the opposite of it.

**Measured offsets from `y`, in units of the font size S** (verified at S = 12, 24 and 48):

| landmark | offset from `y` |
|---|---|
| cap / ascender ink top | `y + 0.375·S` |
| x-height top | `y + 0.583·S` |
| **baseline** | `y + 1.0833·S` |
| descender bottom | `y + 1.333·S` |

So the conversion you actually need is:

```nim
let yantra_y = wantedBaselineY - 1.0833 * size
```

**These figures are EMPIRICAL and hold for the default typeface and weight only.** A port
that sets a `family` or a non-default weight **must re-probe** before trusting them.

### And there is no text measurement API in the SDK

> **CORRECTED 2026-10-03.** Any chapter promising exact centring, right-alignment or
> automatic wrapping in an app is over-claiming. `sdk/ui/paint.nim:63` —
> `proc text*(d: Draw; x, y, size: float32; argb: uint32; s: string; weight = 400): Draw` —
> **returns the new `Draw` and nothing else.** There is no width, no height, no measured
> advance. `Draw.text` has **no `align` parameter** at all.
>
> `measureText` exists only on the native side, in `libs/nimskia/src/nimskia.nim:68` and
> `:122`, and is not reachable from an app module.
>
> **Consequence: centring, right-alignment and wrapping must be ESTIMATED.** Estimate once,
> from the source's own px values, and write the estimate into `PORT-NOTES.md` as a known
> approximation. Do not describe an estimated centring as exact.

---

## 17. `frameDt()` is the clock — `yantra_get_dt()` reads 0 on the real runner

> **CORRECTED 2026-10-03.** Chapters that teach animation or say "advance the clock" pointed
> at `yantra_get_dt()`. **On the real runner it always returns 0, and an app animated off it
> never moves.**
>
> Evidence:
> - `sdk/ui/input.nim:45` — `proc frameDt*(): float32 = yInput(7, 0)`. This is the live
>   clock the engine actually feeds.
> - `sdk/core/runtime.nim:75` declares `yantra_get_dt` as an `importc`. Its only writer is
>   `setFrameDt` (`host/host.nim:1211-1213`), registered at `host/host.nim:1024`.
> - Repo-wide, `setFrameDt` appears in exactly **two** files: `render/render_qml.nim:42`
>   (the legacy Qt path) and `host/t_run_hello.nim:107`, `:137`, `:140` (a test harness).
>   **Zero occurrences under `render/native/`, `cli/`, `apps/` or `web/`.**
>
> **The rule: animate with `frameDt()`, never with `yantra_get_dt()`.** Anything else is a
> build that succeeds, a frame that renders, and an app that is frozen.
>
> **And it is unclamped.** `render/native/engine.nim:3241`:
> `e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60`.
> The first frame is a synthetic 1/60 s (never 0, so nothing is lost); every later frame is a
> real elapsed delta with **no upper bound**, so a stalled or backgrounded window hands you one
> large value on return and `speed * frameDt()` teleports whatever moves. When you diff a port
> at two different `wait` values, clamp it or the growth you are trying to measure is partly
> your own dt spike:
>
> ```nim
> let dt = min(frameDt(), 0.05'f32)
> ```

---

## 18. The app must export `yantra_main`

> **CORRECTED 2026-10-03.** This chapter verified apps with the headless harness without
> stating the one thing the harness was silently relying on. `host/host.nim:1188` calls
> `callVoid(inst, "yantra_main")` **unconditionally.**
>
> An app written as `when isMainModule: main()` exports **`NimMainModule`** instead. It
> compiles clean, passes every headless check, **and never renders a single frame.** One port
> sat in exactly that state: a **2,005-byte stub** that built and passed while rendering
> nothing.
>
> ```nim
> proc yantra_main*() {.exportc: "yantra_main".} = main()   # this, not `when isMainModule`
> ```
>
> **Proof, and the check to run on every app:** `WebAssembly.Module.exports()` returns
> **`false`** for `yantra_main`. `tools/verify-wasm.mjs:406-407` prints this verbatim as
> `entry  : yantra_main present = false, NimMainModule present = true` — a module showing
> `false` there is the 2,005-byte stub, not a pass.

---

## 19. Triage order, one table

Cheapest and most decisive first. Every row here has cost a round when skipped.

| # | check | tool | what a bad result means |
|---|---|---|---|
| 1 | did the build print `build-wasm: wrote …`? | build log | you are diffing a stale artifact |
| 2 | `exit` = 0 **and** `bytes == W*H*4`? | `drive.exe` | truncated native process — **never pipe it into `Select-Object -First N`** |
| 3 | stderr `crashed=[…]` empty? | `drive.exe` | dead frame via the crash path |
| 4 | distinct colours ≫ 2? | `tools/census2.mjs` | dead frame, nothing drawn |
| 5 | is the raw swapped exactly once? | `tools/rawswap.mjs` | channel error masquerading as layout error |
| 6 | do ref and frame share a known clock? | `tools/capture-ref.ps1` | clock difference reported as port error |
| 7 | **do two captures of that clock agree?** | `tools/verify-refs.ps1` | the reference is **stale** — the page moved since it was captured, and every score against it is measuring the wrong target |
| 8 | what is `differing pixels` / `mean \|delta\|`? | `tools/pngdiff.mjs` | **these two numbers are authoritative** |
| 9 | where is the error? | `tools/refdiff.mjs` | **not** `pngdiff`'s band map — it is gated at `pngdiff.mjs:133` |
| 10 | how much signal above the floor? | `tools/floor.mjs` | a saturated score that cannot be tuned against |
| 11 | flat or growing over time? | re-render at a second `wait` | geometry/tone vs animation desync |