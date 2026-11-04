# 19 — Done checklist

Run down this list before saying "done". Every box must be ticked or explicitly answered with
"N/A + why". A box you cannot tick is a **GAP**, and a GAP must be written down (section 9), not
skipped.

Derived from `AGENTS.md`, `docs/agent-guide/process.md`, `docs/agent-guide/quality.md`, and
`tools/build-wasm.sh`.

**Read next:** `21-visual-parity-verification.md` supplies most of section 5's evidence;
`23-wasm-import-gate.md` covers section 1's "it builds but nothing renders";
`22-nim-closure-capture.md` covers a build failure you will hit before section 1 is green;
`01-build-run-and-verify.md` has every command named below.

> **CORRECTED 2026-10-03.** This checklist ticked boxes that could all be green while the app
> was wrong, because each gap below compiles, runs, and passes every structural check it can
> reach. Section 0 is new; the boxes in 1, 5, 7 and 12 are extended to close them. Evidence
> is cited in each note; no number here is estimated.

---

## 0. The five checks that were missing

Each of these describes a port that **built, passed, and was wrong**. Do them first.

1. **Does the module export `yantra_main`?** `host/host.nim:1188` calls it unconditionally.
   `when isMainModule: main()` exports `NimMainModule` instead — it compiles clean, passes
   every headless check, and **renders nothing**. One port was a **2,005-byte stub** in exactly
   that state. Proof of absence: `WebAssembly.Module.exports()` returns `false` for
   `yantra_main`, and `tools/verify-wasm.mjs:406-407` prints
   `entry  : yantra_main present = false, NimMainModule present = true`.
   **That line is a FAIL.**
2. **Did the build print `build-wasm: wrote …`?** A failed build **leaves the old `.wasm` on
   disk** and `drive.exe` re-renders the stale artifact — exit 0, a full-size raw, a plausible
   number, for code that does not exist. The real occurrence: a stale `hello.wasm` once hid an
   SDK that did not compile.
3. **Is every colour AARRGGBB?** A CSS hex pasted straight in (`0xF7F9FB`) has alpha `0x00`
   and draws **fully transparent** — compiles, runs, crashes nothing, invisible. Measured on
   port #52: adding the alpha bytes moved it from **100% differing to 23.7%** in one edit.
   Use `apps/chess/app.nim:100`:
   `proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)`.
4. **Is the animation clock `frameDt()`, and is it clamped?** `yantra_get_dt()` **reads 0 on
   the real runner**. Its only writer is `setFrameDt` (`host/host.nim:1211-1213`, registered at
   `:1024`), and repo-wide `setFrameDt` appears in exactly two files — `render/render_qml.nim:42`
   (legacy Qt) and `host/t_run_hello.nim:107`, `:137`, `:140` (a test harness). **Zero
   occurrences under `render/native/`, `cli/`, `apps/`, `web/`.** An app animated off
   `yantra_get_dt()` never moves. The live clock is `frameDt()` (`sdk/ui/input.nim:45`,
   `yInput(7, 0)`), computed at `render/native/engine.nim:3241`: **the first frame is a
   synthetic 1/60 s, and every later frame is a real, unclamped elapsed delta** — so a stalled
   or backgrounded window hands you one large value on return. Clamp it.
5. **Is the raw swapped exactly once, against a reference of known clock?** The frame dump is
   B,G,R,A (`render/native/drive.nim:191-193`) and no diff tool swaps for you
   (`tools/pngdiff.mjs:100-103`, `tools/refdiff.mjs:90-94`). Measured on one port:
   **91.45% unswapped vs 72.83% swapped.** And two headless captures of the same page at the
   same nominal 800 ms budget differ from each other by **2.13%** (22,288 of 1,044,480
   pixels) — that is the instrument's noise floor, not your error. Capture references with
   `tools/capture-ref.ps1`, which records the budget.
6. **Was the reference captured in the mode that matches how the page lays out?** The window
   size is **not** the page's layout width. At window 1280x816 Chrome gives `innerWidth=1264`
   but `100vw` = **1280** — the flag `--hide-scrollbars` does not close this gap, it only
   hides the bar. So a `100vw` page and a `clientWidth` page need **different** capture
   windows, and you cannot tell them apart without measuring. Measured on chess: **18.42%
   captured with no overhead vs 58.57% with** — 40 points, on code that never changed.
   Pass `nooverhead` to `tools/capture-ref.ps1` for `100vw` pages. *(§21)*
7. **Does any probe you wrote read the swapped raw as R,G,B,A?** `tools/pngdiff.mjs` compares
   `raw[i]` against `ref.rgba[i]` position-for-position, so `rawswap.mjs` output is *already*
   in reference order. Reading it as B,G,R double-corrects and manufactures a hue inversion
   that does not exist — which is exactly what happened here, in two probes at once. *(§17 9b-bis)*
8. **If you binarised for an IoU, what fraction of the frame did the mask cover?** In a dark
   scene a threshold of 128 covered **98.8%** of reference pixels and read IoU 0.9675 for a
   frame that was badly wrong; the same comparison on lit pixels (lum ≥ 90) read **0.3709**.
   A mask covering nearly the whole frame discriminates nothing — check the coverage, not
   the IoU's stability. *(§17 9b-bis)*

---

## 1. It builds

- [ ] Rebuilt **from source** just now. Not a prebuilt artifact — a stale `hello.wasm` once hid an
      SDK that did not compile. *(AGENTS.md rule 2)*
- [ ] **The build printed `build-wasm: wrote <path> (<n> bytes)`.** Not "it exited 0" — a failed
      build leaves the previous `.wasm` in place and every later tool re-renders the stale
      artifact. Confirm the timestamp changed. *(§0 item 2)*
- [ ] **`yantra_main` is in the module's exports.** `proc yantra_main*() {.exportc: "yantra_main".} = main()`.
      `host/host.nim:1188` calls it unconditionally; `NimMainModule` is not it. *(§0 item 1)*
- [ ] `bash tools/build-wasm.sh <src.nim> <out.wasm>` exits 0.
- [ ] Zero errors.
- [ ] Every warning **read**, and each one dismissed for a stated reason. "Build with no errors and
      you read every warning." *(quality.md rule 16)*
- [ ] No warnings that matter are left unaddressed. If one cannot be fixed here, it is named in
      section 9.
- [ ] **No `log()` used as instrumentation.** It compiles, is callable, and **nothing in the repo
      reads it** — `host/host.nim:628` is the only writer, `host/host.nim:1029` binds it, and the
      only reader anywhere (`render/native/t_mpopen.nim:173`) reads a different log. One call
      measured **+15,660 bytes** on a ~215 KB module. *(§0, and `01` §3)*
- [ ] Every declared wasm import appears as a `result["<name>"]` row in `host/host.nim`'s
      `importTable()` (`:1017`). `tools/verify-wasm.mjs` now parses that table out of the source
      (`:146-161`) and refuses at `:184-229`, but the host is still the authority.

## 2. The gate passes

- [ ] `just test` ends with **every suite at 0 failed**.
- [ ] The tail of that output is **pasted in the report**. No output = not done. *(AGENTS.md)*
- [ ] No test was weakened, skipped or deleted to make it pass. *(AGENTS.md rule 3)*

## 3. Every source element is accounted for

- [ ] Every DOM node from the Phase 1 inventory exists in the port — native node, canvas drawing, or
      a written GAP.
- [ ] Every canvas/SVG/WebGL block was drawn.
- [ ] Every JS state machine is implemented (all states, all transitions).
- [ ] Every animation: duration, easing, delay, iteration count.
- [ ] Every web API used (`fetch`, storage, clipboard, timers…) is either ported via the SDK or is a
      written GAP.
- [ ] Every asset the source used is present in the app folder, with the original's filename.
- [ ] No element is **silently dropped**. Unclassified = not done.

## 4. Numbers are exact, not approximate

- [ ] Every hex value copied literally from the source — none eyeballed — **and written with its
      alpha.** `argb` is `0xAARRGGBB`; a CSS hex pasted straight in has alpha `0x00` and draws
      fully transparent. Measured on port #52: adding the alpha bytes moved it from 100%
      differing to 23.7% in one edit. *(§0 item 3)*
- [ ] Every px value copied literally.
- [ ] Fonts: family, weight, size, line-height — matched.
- [ ] Timings in ms — matched, not rounded.
- [ ] Spec file has no "about", "roughly", "similar", "close enough" in any value.

## 5. Verified by screenshot

- [ ] Reference screenshots of the original exist, per screen/state.
- [ ] Port screenshots taken **at the same window size**.
- [ ] **References were captured at a RECORDED virtual-time clock** — via `tools/capture-ref.ps1`,
      which takes the budget as an argument and prints it. A reference of unknown clock measures
      clock difference and reports it as port error: two captures of the same page at the same
      nominal 800 ms budget differ from each other by **2.13%**. *(§0 item 5)*
- [ ] The two were compared **side by side**, not from memory.
- [ ] **The frame dump was swapped before any diff.** It is B,G,R,A
      (`render/native/drive.nim:191-193`) and `tools/pngdiff.mjs:100-103` / `tools/refdiff.mjs:90-94`
      read bytes 0,1,2 as R,G,B with no swap: **91.45% unswapped vs 72.83% swapped** on one port.
      Exactly one swap — `tools/floor.mjs:35` guards on the `*_bgra.raw` suffix. *(§0 item 5)*
- [ ] **The number quoted is `differing pixels` / `mean |delta|`**, not a `pngdiff` band cell. The
      band map is gated at `pngdiff.mjs:133` on `if (rows[y] && cols[x] && …)`, so any row or
      column with zero differing pixels contributes nothing and bands read artificially low — this
      produced three rounds of confidently wrong conclusions about one port. Localise with
      `tools/refdiff.mjs`. *(§0)*
- [ ] **The frame is not dead.** `drive.exe` stderr `crashed=[…]` is empty, `tools/census2.mjs`
      shows far more than 2 distinct colours, and the Draw stream does not start `Y 0`. An app can
      exit 0, write a full `W*H*4` raw, and have painted nothing. Two code paths reading the same
      dead frame return byte-identical output, which reads as a pass and is not one.
      *(§0, and `21` §14)*
- [ ] Colours were checked with a picker, not by eye. *(process.md §3)*
- [ ] Each prop you set is confirmed **rendered**, not merely accepted — see §7 below.

## 6. Interaction verified

- [ ] Pointer: every clickable element actually clicked; every one responds.
- [ ] Keyboard: Tab order is sane; every focusable element is reachable; focus is visible.
- [ ] Typing: every text input accepts, edits and commits text.
- [ ] Scrolling: scroll containers scroll; nothing is unreachable.
- [ ] Hover/active states fire where the original has them.
- [ ] Hot reload still works, if that is part of the deliverable.

## 7. "Compiles" is not "renders"

- [ ] For **each** new prop used: `grep -rn "P_<NAME>" render/` shows the renderer **emits** it.
      A prop in `core/wire.nim` that no renderer branch reads is **dead** — it type-checks and does
      nothing. This is not hypothetical: `pAlign` was dead for a while.
- [ ] If a **new node kind** was added: the renderer mapping **and** a test in `render/t_qml.nim`
      shipped **in the same commit**. *(AGENTS.md rule 6)*
- [ ] `protocol/schema.nim` was edited and `protocol/props.md` / `sdk/props.nim` regenerated
      (both are generated — never hand-edited).
- [ ] Screenshots confirm each new node kind actually paints.
- [ ] **Text `y` was placed as a line-box top, not a baseline.** `libs/nimskia/src/skia_shim.cpp:291`
      calls `p->paint(canvas, x, y)`, so `y` is the top of the paragraph line box.
      `libs/nimskia/src/nimskia.nim:76` documents the opposite and is **wrong**. Measured from `y`
      in units of font size S (verified at S = 12, 24, 48): cap/ascender ink top `y + 0.375·S`,
      x-height top `y + 0.583·S`, **baseline `y + 1.0833·S`**, descender bottom `y + 1.333·S` —
      so `yantra_y = wantedBaselineY - 1.0833 * size`. **Empirical: default typeface and weight
      only. A port that sets a family or a non-default weight must re-probe.** *(§0, and `21` §16)*
- [ ] **Any centring, right-alignment or wrapping is written down as an ESTIMATE.** There is no
      text measurement API in the SDK: `sdk/ui/paint.nim:63` returns `Draw` and nothing else, and
      `Draw.text` has no `align` parameter. `measureText` is native-only
      (`libs/nimskia/src/nimskia.nim:68`, `:122`) and unreachable from an app module. *(§0)*

## 8. No invented APIs, no faked features

- [ ] Every prop used appears in `protocol/props.md` (generated, complete).
- [ ] Every proc used was **grepped** in `sdk/` — not assumed from a familiar name.
- [ ] No placeholder drawn to look like a missing feature. *(README.md rule 4)*
- [ ] No hand-rolled imitation of a library that should have been wrapped. *(AGENTS.md rule 5)*

## 9. The gap list is written down

Anything NOT SUPPORTED YET gets a line here. A GAP that is not written is a rejection.

- [ ] Each gap states: **what is missing**, **where it was in the original**, **what you did
      instead**.
- [ ] Count of gaps in the inventory == count of gap lines in PORT-NOTES.md.
- [ ] No `TODO`, `FIXME`, or commented-out block left in the source. *(quality.md rule 22)*
- [ ] PORT-NOTES.md ends with a short, honest **"matches / differs / why"**. *(process.md §5)*

## 10. Every claim is traceable

- [ ] **No number in the report was not measured.** No invented diff percentages, no invented test
      passes, no guessed file sizes. *(AGENTS.md rule 11)*
- [ ] Test output pasted verbatim, not summarised.
- [ ] File/line references point at real lines.
- [ ] Engine problems written up in `ENGINE-ISSUES.md` (app folder): what you did, what you
      expected, what happened, a 10-line repro. Not worked around silently. *(quality.md rule 19)*
- [ ] Anything user-visible — names, words, look, defaults — new dependencies, deleted folders, or
      licence questions went to `DECISION_QUEUE.md`. *(AGENTS.md rule 9)*

## 11. No generated artifacts committed

`git status` was run **and read** before every commit. *(AGENTS.md rule 1)*

- [ ] No `.wasm`, `.exe`, `.dll`.
- [ ] No `third_party/`, no `vendor/`.
- [ ] No `panicoverride.nim` (copied there by `build-wasm.sh`), no `nimcache*`, no `minilibc.o`.
- [ ] No `*.bak`, no `host/nc_lb/`, no `apps/mirror/pieces/_probe/`. *(AGENTS.md rule 10)*
- [ ] Nothing with keys.
- [ ] Scratch/probe files written under `.board/tmp/` are deleted or left untracked.

## 12. Code passes the quality bar

*(quality.md, rules 1–15)*

- [ ] One app = one folder: `app.nim` plus one file per area of the original. No file > ~400 lines.
- [ ] No proc > ~40 lines.
- [ ] Data first: plain `type` objects with the original's field names; logic in plain procs with no
      UI in them.
- [ ] One `state` per independent thing; derived values are `derive:` or procs, not hand-synced
      duplicates. No globals except signals and constants.
- [ ] Every magic number is a named constant (`const toolbarHeight = 44`).
- [ ] Names say what a thing is in the product's words (`selectedShapeIds`, not `arr2`).
- [ ] `##` doc comment on every non-obvious proc: what it does and why. No comments restating code.
- [ ] Empty, huge and wrong cases handled: empty lists, 10 000 items, missing files, network errors.
- [ ] Everything that moves uses `frameDt()` or ms timings, never per-frame constants.
      **Not `yantra_get_dt()`** — it is an `importc` (`sdk/core/runtime.nim:75`) whose only writer
      is `setFrameDt` (`host/host.nim:1211-1213`), and repo-wide `setFrameDt` has **zero callers**
      under `render/native/`, `cli/`, `apps/` or `web/`. The live clock is `frameDt()`
      (`sdk/ui/input.nim:45`, `yInput(7, 0)`). An app animated off `yantra_get_dt()` reads 0 and
      **never moves**. *(§0 item 4)*
- [ ] No copy-paste blocks — two near-identical blocks became one proc with a parameter.
- [ ] Every `@name` is unique inside its screen and matches the original's id or role.
- [ ] Long lists use keyed `for` (`.keyed(id)`) or `vlist`.
- [ ] Many similar things: one canvas draw list / layer / instanced mesh — not a node each.
- [ ] Accumulating drawings draw into a layer once.
- [ ] `onFrame` does not rebuild big strings or seqs unless they changed.
- [ ] Re-read the diff once as a reviewer: dead code, unused procs and debug output deleted.

## 13. Scope and commit hygiene

- [ ] One `PLAN.md` item. *(AGENTS.md rule 7)*
- [ ] ≤ ~300 changed lines. One commit.
- [ ] Commit message: `area: imperative summary`, with a body carrying `Verified:` and the pasted
      test tail.
- [ ] **Not pushed.** Owner pushes. *(AGENTS.md)*

---

## The three questions, if you only have time for three

1. **Would `git status` embarrass me?** (artifacts, secrets, scratch files)
2. **Did I measure, or did I assume?** (numbers, test results, sizes, "close enough" values)
3. **Is everything I could not build written down?** (gaps, engine bugs, deliberate differences)

If any answer is "no", you are not done — you are finished, which is different.