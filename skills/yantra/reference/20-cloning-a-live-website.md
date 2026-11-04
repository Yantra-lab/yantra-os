# 20 — Cloning a live website

*Everything marked **[measured]** in this chapter was run from
`C:\Users\Sanskar\DEV\yantra` while writing it. Where something this chapter asks for cannot
be produced in this environment, the chapter says so and gives you the thing that does work —
it never describes a command that was not run.*

Chapter 18 is the general porting process and you should have read it first. This chapter is
only about the case 18 assumes away: **the site is a live URL, not a local HTML file.** So the
capture step is real work, the cascade you capture is a computed cascade rather than a text
one, and — this is the part that matters — **the visual acceptance test that 18 phase 6 depends
on cannot be run in this checkout.** Section 3 tells you what you can actually prove instead.

**What this chapter is for.** It is 18 specialised for a live URL: capture and flatten the
computed cascade, classify it, and verify what is verifiable without a screenshot.
**After this chapter you can** build a value table from computed styles rather than guessing
from source CSS, substitute a headless host harness for pixels, and say precisely which
questions that substitution leaves unanswered.

**Read next:** `18-porting-process.md` for the phases this specialises;
`15a-html-css-mapping.md` §6 for the selector→construct table this chapter's §2.3 flattens
(remember: cite 15a by **section**, not by line — its rows move); `01-build-run-and-verify.md`
for the raw→PNG bridge; `21-visual-parity-verification.md` for the real diff;
`23-wasm-import-gate.md` if nothing renders; `19-done-checklist.md` before saying done.

---

## 0. The one thing to know before you start

Yantra app modules are headless WebAssembly. A pixel-diff harness needs a native host that
renders a frame to memory. In this checkout **the native host cannot be compiled**, so there is
no screenshot, and therefore no pixel diff. Everything in sections 4 and 5 — capture, flatten,
screenshot-diff — is procedure you can follow on a machine where the host builds, and it is
marked **[UNVERIFIED HERE]** because it was not executed here.

What you *can* do here, and what actually catches the class of bug that cost this project an
entire app, is in section 3. Read section 3 before you start a clone. It is shorter than the
thing it replaces.

| You want to prove | Run this | Proves |
|---|---|---|
| the module calls only host functions it was designed to | `node tools/verify-wasm.mjs <app.wasm>` | **structure** |
| the app built the tree it intended | same | **structure** |
| the procedural surfaces actually reached the host | same — the layer byte count | **behaviour** |
| a click/frame dispatch changed state | same | **behaviour** |
| the pixels are correct | a native screenshot tool | **appearance — BLOCKED HERE** |

---

## 1. What "cloning a live site" actually means here

You are not porting a file. You are reconstructing, from a rendered page, a source that does
not exist. The evidence is:

- the live URL, rendered in a browser, at a **chosen viewport size**;
- the CSS the browser computed, which you can read rather than guess;
- screenshots of every state you can reach.

The target is still chapter 18's target: `apps/<name>/app.nim` plus `apps/<name>/PORT-NOTES.md`,
with every value a literal you copied.

### Order of work

1. **Freeze the viewport first.** Every number below is viewport-relative. Pick the width, and
   write it into `PORT-NOTES.md` before you measure anything else. 18 phase 6 says "same window
   size, or the comparison is meaningless" — with a live site the trap is worse, because the
   live site reflows while you work.
2. **Capture** (section 2).
3. **Flatten the cascade** (section 2.3) — before writing a line of Nim, because the flattened
   table *is* the port's `const` blocks.
4. **Classify** with 18 phase 3 — node / Draw / gap.
5. **Build** with 18 phase 5, using section 3 as your verification.
6. **Diff** (section 5) — only on a machine where the host builds.

### What the browser gives you that a file does not

- **Computed styles.** `getComputedStyle(el)` returns the value after the cascade, after
  inheritance and after media queries. That is exactly the "flattened" table 18 phase 2 demands,
  already computed. You do not have to reason about specificity at all if you read computed
  values off each element.
- **The box model, measured.** `el.getBoundingClientRect()` gives you the *actual* laid-out
  position and size, including everything flexbox and grid did for you. These are the px values
  18 phase 2 insists you copy rather than estimate.
- **The list of resources**, from the network panel — the asset filenames you must reproduce in
  `apps/<name>/`.

Read these with the browser tooling, not by eyeballing a screenshot. `18-porting-process.md`
phase 2's done test is "every hex and every px is a literal you copied, not one you estimated" —
a colour you read out of a screenshot with a picker is a literal you copied, but a colour you
looked at and named is a guess.

---

## 2. Capture

### 2.1 What to take, and when

Take these three artifacts. All three are inputs to the port, so they live next to it.

| Artifact | How | Feeds |
|---|---|---|
| reference screenshots, one per screen/state | browser, at the frozen viewport | the diff in section 5 |
| the computed-style dump | a `getComputedStyle` walk over every element | the flattened table, §2.3 |
| the asset list | network panel / page source | `apps/<name>/` file names (18 phase 1) |

Screenshots: one per **state**, not one per page. A page with a menu open, a modal up, a hover
state and an empty state is four screenshots, because those are four things the port must
reproduce. 18 phase 1 makes the same demand in the abstract.

### 2.2 The computed-style walk

The whole cascade, in one pass, as data. This is the piece that makes cloning tractable — you
are not translating CSS, you are reading what the browser concluded.

```js
// paste into the page console, at the frozen viewport
const out = [];
const walk = (el, depth) => {
  const cs = getComputedStyle(el);
  const r  = el.getBoundingClientRect();
  out.push({
    depth,
    tag: el.tagName.toLowerCase(),
    id: el.id || null,
    cls: el.className?.toString?.() ?? null,
    text: el.children.length === 0 ? (el.textContent || '').slice(0, 120) : null,
    rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
    color: cs.color, background: cs.backgroundColor,
    font: `${cs.fontWeight} ${cs.fontSize}/${cs.lineHeight} ${cs.fontFamily}`,
    padding: cs.padding, margin: cs.margin, gap: cs.gap,
    border: cs.border, radius: cs.borderRadius,
    shadow: cs.boxShadow, opacity: cs.opacity, transform: cs.transform,
  });
  for (const c of el.children) walk(c, depth + 1);
};
walk(document.body, 0);
console.log(JSON.stringify(out, null, 1));
```

Three things to know about this walk, all of them real:

- **It does not see pseudo-elements or generated content.** `::before` / `::after` and
  `content:` are invisible to it. The `::before` / `::after` rows in
  `15a-html-css-mapping.md` **§6** are exactly the trap: a real glyph can arrive as a bare
  `<span>` whose artwork is a `background-image` on an `:after` pseudo-element. Find those in
  the Elements panel and write them into `PORT-NOTES.md` as real content.
- **`transform` is a matrix, not a layout.** `getComputedStyle` returns `matrix(1, 0, 0, 1, x, y)`
  for `translate`, and a rotation collapses layout. A rotated element's `getBoundingClientRect()`
  is its *bounding box*, not its box. Read the untransformed `offsetWidth` / `offsetHeight` too
  and record both.
- **`getBoundingClientRect()` includes scroll.** Subtract the scroll offset, or read
  `getBoundingClientRect()` relative to a positioned ancestor, or your absolute positions will
  be off by however far the page was scrolled when you ran the walk.

### 2.3 Flatten the cascade

Yantra has no cascade. From `docs/spec/style.md` §1, quoted at the head of
`15a-html-css-mapping.md` **§6** (and again in its §0 mental-model table):
*"There are no stylesheets, selectors or cascades: a value comes from the call site, a style
preset (`use = `) or the engine's plain default."*

> **CORRECTED 2026-10-03 — every `15a` citation in this chapter was a bare file line, and every
> one of them was stale.** They pointed into unrelated rows of a file that is actively being
> edited and has gained rows since. `15a` now carries a "How other chapters cite this one"
> table near its top that maps each inbound citation to the section it lands in, and it says
> outright: **cite sections, not file lines.** Every citation below is now a section.
>
> The old pins were `15a:589-590` (the cascade quote), `:596`, `:598`, `:602`, `457`, `:609-611`
> and `:634`. As of this pass they resolved to: unrelated `@keyframes` rows, an Svelte `out:`
> row, a stagger row, a `---` horizontal rule, three lines of prose after a table, and the
> `:target` / `:link` / `:visited` row. **Not one of them pointed at the thing it claimed.**
>
> **This is the second time in this chapter that a line-number citation has gone stale, and
> the same fix applies to `tools/verify-wasm.mjs`: check it against the file, or don't print
> it.**

So "flattening the cascade" is not a metaphor. It is a mechanical reduction. Each row names
the **section** of `15a` that settles it:

| CSS source | Yantra | where 15a settles it |
|---|---|---|
| `:root / :root { … }` | const block, or a proc over the theme | §0 mental-model table; §3 |
| a class used on N elements | one `proc name(): Style = style(…)` | **§6**, the `.card { … }` → `Style` preset row |
| that class + a one-off override | the call-site prop — call-site props WIN over the preset | **§6**, the `.card:hover`-style override row |
| a unique id `#hero { … }` | a `var` + expression props, or one proc used at one site | **§6**, the `#hero { … }` (an id) row |
| inherited `font-size` | does NOT cascade — set it on **every** text node | **§4.1**, the `font-size` on a container row |
| `.pseudo-class rule` | a `hover:` / `pressed:` / `focused:` block | **§6**, the `:hover` / `:active` / `:focus` rows |
| media query `@media (max-width: …)` | a `sized` block — the real container-query replacement | **§6**, the responsive-visibility row; also **§0** |

> **CORRECTED 2026-10-03 — a clone has to carry the alpha, the baseline and the estimate.**
> Two of the literal-value rules above cannot be followed literally, and getting either wrong
> produces a port that is *invisible* rather than *imperfect*.
>
> 1. **Write every colour as AARRGGBB, not as the CSS hex.** `argb` is `0xAARRGGBB`
>    (`sdk/ui/paint.nim:55`, `:57`, `:59`, `:61`, `:63`). `#F7F9FB` pasted straight in has
>    alpha `0x00` and draws **fully transparent** — it compiles, runs, crashes nothing, and
>    paints nothing. Measured on port #52: adding the alpha bytes moved it from **100%
>    differing to 23.7%** in one edit. Force it with `apps/chess/app.nim:100`:
>    `proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)`.
> 2. **Record the BASELINE of every text run, then convert.** Text `y` in a `Draw` is the
>    **top of the paragraph line box, not the baseline** —
>    `libs/nimskia/src/skia_shim.cpp:291` calls `p->paint(canvas, x, y)`.
>    `libs/nimskia/src/nimskia.nim:76` documents the opposite and is **wrong**. Measured from
>    `y`, in units of font size S (verified at S = 12, 24, 48): baseline sits at
>    `y + 1.0833·S`; ink top `y + 0.375·S`; x-height top `y + 0.583·S`; descender bottom
>    `y + 1.333·S`. So `yantra_y = wantedBaselineY - 1.0833 * size`. **Empirical — default
>    typeface and weight only; a live site with a custom `font-family` needs a re-probe.**
> 3. **Any centring is an estimate, and must be written as one.** There is **no text
>    measurement API in the SDK**: `sdk/ui/paint.nim:63` returns `Draw` and nothing else, and
>    `Draw.text` has no `align` parameter. `measureText` is native-only
>    (`libs/nimskia/src/nimskia.nim:68`, `:122`). A live site gives you
>    `getBoundingClientRect()` for free, so record the real box — but the port can only
>    *reproduce* it approximately, and PORT-NOTES must say so.

**The done test for flattening** is the one from `19-done-checklist.md` §4, applied to the
flattened table rather than to a `PORT-NOTES.md`: every colour, size, padding and timing in the
port is a literal that appears in the capture. If a value appears only in the original CSS text,
it is unflattened — either you never resolved it, or nothing in the port uses it. Both are bugs.

Write the result as `const` blocks before any proc. `skills/web-to-yantra/SKILL.md:206-210`
gives the working order on the one port in this repo that did it: *"Transcribe the constants
first — every `const` block from `:root`, the layout function, the palette… Then transcribe the
PRNG before anything that uses it."* The PRNG point matters for a clone specifically: if the live
site's visual uses `Math.random()`, your port will never reproduce the reference screenshot unless
you transcribe or replace the generator, and a clone that renders differently every run cannot
be pixel-diffed at all.

---

## 3. What you can actually verify here — the headless harness

**This section is the chapter.** It is the substitute for the screenshot diff, and on the one
failure mode below it is *better* than a screenshot.

### 3.1 Why the native host will not build here — measured

> **Added 2026-10-03 — read this as a statement about *this machine's current state*, not as a
> law.** This chapter says the native host cannot be compiled, and it was true of the checkout
> as it stood. It is **not** a permanent property, and `21-visual-parity-verification.md` §1
> documents how to change it: the bare `msys64` archive is a skeleton with empty package
> databases, and one `pacman` command installs the toolchain. Also note that
> **`render/native/build/drive.exe` and `render/native/build/mpdrive.exe` both exist** — but
> per AGENTS.md rule 2 they are prebuilt, dated before `render/native/engine.nim`, and a
> screenshot proves what the *harness* drew, not what your app does.
>
> So the honest reading of this section is: *on this machine, right now, rebuild the native
> target before you trust any pixel.* It is not: *pixels are impossible.* Follow §3 while the
> toolchain is absent, and switch to §5 the moment you install it.

Building any `render/native/*.nim` target fails in this checkout:

```
fatal error: SDL3/SDL.h: No such file or directory
```

`third_party/msys64/mingw64/include/SDL3/SDL.h` — **does not exist** **[measured]**.
`third_party/msys64/mingw64/bin` holds **0 files** **[measured]**. The same absence applies to
the curl, ffmpeg, Jolt and Skia headers.

The prebuilt `*.exe` files under `render/native/build/` — **55 of them** **[measured]** — do
exist, and you must not use them as evidence:

| File | Size | Last write | vs `render/native/engine.nim` (02-10-2026 14:29) |
|---|---|---|---|
| `build/mpdrive.exe` | 4 764 327 | 30-09-2026 00:50 | **2.5 days older** |
| `build/yantra.exe` | 4 066 167 | 02-10-2026 01:25 | ~13 h older |

**[measured]** by `Get-Item`. AGENTS.md rule 2 — *"Never trust a prebuilt artifact"* — exists
because a stale `hello.wasm` once hid an SDK that did not compile. A stale `.exe` is the same
trap with a longer fuse: it is dated *before* the engine it is supposed to contain, and one
agent measured that the stale `mpdrive.exe` fails even the repo's own known-good layer fixture
`examples/shell/paint.nim`. So it is not evidence in either direction — a failure from it is not
proof your port is broken, and a success is not proof it works.

**Therefore: no pixels in this checkout.** Do not write "verified visually" in a report from
this machine.

### 3.2 The substitute: `tools/verify-wasm.mjs`

A Yantra module has no window and no OS. Everything it does is a call out to a host function.
So Node **can** be the host: implement the imports, let the app build its tree, assert on the
tree that arrives. That is `tools/verify-wasm.mjs`, and it exists and works.

> **CORRECTED 2026-10-03 — the line citations in this subsection were all stale, and the
> description of the tool was wrong.** What this chapter used to say: *"That is
> `tools/verify-wasm.mjs` (**351 lines**)"*, and cited `:45-46`, `:74-171`, `:173-182`,
> `:265-266`, `:76-98` and `:23`.
>
> **The file is 676 lines** and has been substantially rewritten. Two changes matter to you:
>
> - **It now enforces the real host's import gate**, which this chapter said it did not.
>   `verify-wasm.mjs:146-161` parses `importTable()` out of `host/host.nim` at run time and
>   `:184-229` refuses before instantiating. So the "import census" in §4.4 is now partly
>   automated — but keep the check, because the host is still the authority.
> - **Its mock host is fed a clock.** `verify-wasm.mjs:255` sets `dt: 1 / 60` in the clock
>   record the app reads, and `:253-254` documents `// 7 = frameDt seconds`. So the harness
>   animates apps that read `frameDt()` — while `yantra_get_dt()` still reads nothing on the
>   real runner, because `setFrameDt` has **zero callers** under `render/native/`, `cli/`,
>   `apps/` or `web/`.
>
> Corrected anchors for the current file:

| what | was cited as | actually at |
|---|---|---|
| the tool's total length | "351 lines" | **676 lines** |
| reads the file and compiles it | `:45-46` | `:169-170` |
| the mock host object | `:74-171` | `:257` onward (`y_node_create` `:259`, `y_node_child` `:264`, `y_node_set_i32` `:269`, `y_node_set_str` `:282`, `y_node_on` `:286`) |
| the generated constants | `:23` | `:35` — `import { K as KIND, P, E as EVT } from '../examples/protocol.mjs'` |
| the host import gate | (not mentioned) | `:146-166` parse, `:172-229` refuse |
| "an unknown import shows up as a failure" | `:265-266` | the gate at `:184-229` now does this before anything runs |
| `pDraw` reported as a length | `:243` | `:441-443` (in the tree printer), and `:489` for the `canvas pDraw len` line |

#### The four assertion families

**(a) Load the module and mock the host imports.** `verify-wasm.mjs:169-170` reads the file
and compiles it; `:257` onward defines the mock host — every `y_*` function the app may call,
each one *recording* what it was asked to do.

That matters on a clone. A port of a live site will reach for an import the SDK does have and
the harness has not stubbed. The harness tells you so, by name, in its import census — and
the census is split three ways (`:633-640`): **HOST-MODELLED** (real host provides it *and* the
mock implements it), **HOST-ONLY** (real host provides it, this run cannot see it — a blind
spot, not a load failure), and anything else, which cannot occur because the gate exited
first.

**(b) Assert the node tree.** The mock records `y_node_create` / `y_node_child` /
`y_node_set_i32` / `y_node_set_str` / `y_node_on` (`verify-wasm.mjs:259-289`), so the whole UI
the app asked the host to build is in `nodes`. Assert structure against the *generated*
constants from `examples/protocol.mjs` (`KIND`, `P`, `EVT` — `:35`), never against hardcoded
integers.

This is your pixel-perfection substitute for **layout**: every node, every nesting, every
measured px width you put in `PORT-NOTES.md`, every literal colour. If your flattened cascade
says the header row is 64 px tall, assert `props[HEIGHT] == 64`. You cannot see that 64 px on a
screen here — but you can and must see it arrive.

**(c) Assert the `pDraw` command length.** The canvas node's `pDraw` prop is a multi-kilobyte
command string. `verify-wasm.mjs:441-443` deliberately reports its **length**, not its body,
because "pDraw is 37 KB of scene commands … Dumping it whole would bury the report." Length is
the assertion that matters: `drawLen > 0` proves the scene was built at all
(`verify-wasm.mjs:506`), and a **before/after length change** across an event proves the scene
*repainted in response to input*.

**(d) Dispatch a real event back into the module and assert state changed.** The callback
direction — `host → app` through `yantra_dispatch` — is the one that is easy to get wrong and
that a build never exercises at all. `verify-wasm.mjs:534-549` finds a button node with a
CLICK handler, records `pDraw`'s length and the button's colour, calls
`inst.exports.yantra_dispatch(h.handler)`, and asserts something actually changed.

> **Read this before you trust a green run.** `verify-wasm.mjs:604-614` prints
> `pDraw length before=… afterPress=… afterFrames=…`, and its own comment at `:550` is blunt:
> **`(unchanged is CORRECT)`** — because a click on a colour swatch is *expected* to leave
> `pDraw` byte-identical and change only `aria-pressed` on the node. Asserting on the value
> captured immediately after dispatch compares the pre-repaint output with itself, and that
> check fails at every coordinate, valid ones included, which reads exactly like "the pointer
> is dead". Assert on the **post-repaint** value — `afterFrames`.

#### Run it — measured

`tools/guard-29.ps1` is the one-shot gate: rebuild from source, then run the harness
(`guard-29.ps1:56-70` stage 1, `:72-84` stage 2). It rebuilds because rule 2 forbids trusting
the existing `.wasm`; `-SkipBuild` runs the harness alone.

```
pwsh -NoProfile -File tools/guard-29.ps1
```

**[measured]**, output on the 029 Carriage Return app, verbatim and abridged only where marked:

```
=== guard-29: 029 Carriage Return ===
[1/2] rebuild from source: tools/build-wasm.sh
    build-wasm: wrote apps/typewriter/app.wasm (407652 bytes)
[2/2] run the harness
    module : apps/typewriter/app.wasm
    size   : 407652 bytes
    imports (16): y_sound_load, y_node_create, y_node_child, y_node_set_str, y_node_set_i32,
                  y_node_on, y_sound_play, y_store_get, y_store_set, y_key, y_key_handled,
                  y_input, y_node_size, y_layer_new, y_layer_draw, yantra_log
    entry  : yantra_main present = false, NimMainModule present = true
    nodes: 26
      [0] WINDOW children=[1,11,25]  handlers=[KEY->#6]
           props={"TEXT":"Carriage Return","WIDTH":1280,"HEIGHT":816,...}
      [1] ROW children=[2,5,6,7,8,9,10] props={"HEIGHT":64,"SPACING":10,...}
      ...
      [25] CANVAS children=[]  handlers=[CLICK->#5,FRAME->#7]
           props={"WIDTH":1280,"HEIGHT":752,...,"DRAW length":37448}

    canvas pDraw len  : 37448
    pDraw first 220   : Y 1 0.00 0.00 0.00 0.00;R 0.00 0.00 1280.00 816.00 0.00 0;E 640.00 683.12 458.75 ...

    OK   module ran without trapping
    OK   node tree is not empty
    OK   every declared import is implemented by this harness
    OK   root is a window
    OK   window title: got "Carriage Return", want "Carriage Return"
    OK   window width: got 1280, want 1280
    OK   window height: got 816, want 816
    OK   exactly one canvas
    OK   canvas carries a non-empty pDraw

    layers created: 2, draws: 85, bytes: 1061939
    OK   app creates layers (newLayer reached the host)
    OK   procedural surfaces were actually submitted (NOT a no-op build)

    sounds loaded (6): bell.wav, key.wav, paper.wav, return.wav, soft.wav, space.wav
    store keys written (2): marlowe44.letter.v1, marlowe44.muted

    dispatched click on [6] BUTTON "Black"
      pDraw length 37448 -> 37446
    OK   dispatching a click did not trap
    OK   the canvas repainted after the click

    dispatched a click at (386.87, 590) on the canvas (canvas-local pixels)
      pDraw length 37446 -> 37487
      saved letter bytes 721 -> 730
    OK   the on-screen keyboard click did not trap
    OK   the clicked key produced a stroke (saved letter grew)

=== 16/16 checks passed ===
=== PASS ===
```

That last block is the whole chapter in miniature: a click was dispatched **into the sandbox**,
a key on a **drawn, not DOM'd** keyboard was hit-tested, the app's saved letter grew from 721
to 730 bytes, and the scene repainted. No pixels were involved anywhere.

#### One honesty note about reusing the harness

`tools/verify-wasm.mjs` is **currently hard-coded to the 029 app**: `verify-wasm.mjs:501-503`
asserts the title is `"Carriage Return"` at 1280×816, `:577` and `:598` read the store key
`marlowe44.letter.v1`, and `:534-539` hunts for a button with a CLICK handler — preferring one
labelled `"Red"`. The default click point is also 029-specific: `:56` sets `--ptr` to `640,762`,
derived from that app's own layout constants at `:49-55`. Those assertions will fail —
correctly — against a different app. When you clone a different site, copy the file
and retarget those expectations to *your* app's real values. Do not delete the assertions to get
a green run: AGENTS.md rule 3, and `19-done-checklist.md` §2. An assertion you removed is an
assertion you no longer have.

> **CORRECTED 2026-10-03.** The line numbers above were `verify-wasm.mjs:268-270`, `:319` and
> `:299-300`. None resolved against the current 676-line file. **This correction note was
> placed because the same class of error had already been corrected once in this chapter** —
> every `15a` line number in §2 — and it recurred. **Check a line number against the file
> before you print it, or cite the section name.**

> **And one more thing it still cannot see, which is the one that produces an invisible app.**
> The harness prints an `entry` line. **`yantra_main present = false` is a FAIL, not a
> detail.** `host/host.nim:1188` calls `callVoid(inst, "yantra_main")` unconditionally, so a
> module that exports only `NimMainModule` — which is what `when isMainModule: main()` produces
> — compiles clean and passes every other assertion in the file while **rendering nothing**.
> `verify-wasm.mjs:406-407` prints `entry  : yantra_main present = false, NimMainModule
> present = true`; `:408-409` then prints `host gate: PASSED — every declared import is in
> importTable(), so drive.exe will instantiate this module`. One port sat in exactly that
> state: a 2,005-byte stub. The required form is
> `proc yantra_main*() {.exportc: "yantra_main".} = main()`.

### 3.3 What this proves, and what it never proves

**It proves STRUCTURE and BEHAVIOUR.** The module imported only symbols the SDK binds, built the
tree and set the props you wrote, submitted its procedural surfaces as actual bytes, and
responded to a real dispatched event with a real state change.

**It never proves APPEARANCE.** Not one of those 16 checks reads a pixel. A Draw command string
that is 37 KB of well-formed commands can describe the wrong colour, the wrong font size, the
wrong z-order and the wrong geometry, and every one of the 16 checks still passes. Blending
modes, gradient banding and text shaping happen **inside Skia**, which is not linked here.

So the honest report sentence is: *"structure and behaviour verified headlessly, N/N; appearance
NOT verified — the native host cannot be compiled in this checkout (§3.1)."* Anything else
overstates what you ran.

---

## 4. The trap that cost this project an entire app

Read this section even if you skip everything else. It is the failure that produced a complete,
clean, passing, invisible application.

### 4.1 `tools/build-wasm.sh` MUST pass `-d:yantra_engine`

`sdk/ui/paint.nim:86` gates the layer bindings:

```nim
when defined(yantra_headless) or (defined(wasm) and not defined(yantra_engine)):
  # No rasteriser linked (unit tests, plain `nim c`): every layer op is a no-op.
  proc yLayerNew(id, w, h: int32): int32 = 1
  proc yLayerDraw(id, p, n: int32) = discard
  proc yLayerFilter(id, kind: int32; amount: float32) = discard
  proc yLayerRead(id, x, y, w, h, p: int32): int32 = 0
  proc yLayerWrite(id, x, y, w, h, p: int32) = discard
  proc yLayerFree(id: int32) = discard
else:
  proc yLayerNew(id, w, h: int32): int32 {.importc: "y_layer_new", cdecl.}
  ...
```

Without the flag, on wasm, **every** `Layer` op is `discard`. The `else` branch
(`paint.nim:94-100`) is what actually binds `y_layer_new` / `y_layer_draw` / `y_layer_filter`.

What that produces is the worst kind of failure: the app **builds clean**, still emits `Y n`
layer references in its `pDraw` (because `Draw.layer` at `paint.nim:67-69` allocates and formats
the id regardless of whether anything consumes the bytes), still passes a node-tree test — and
renders **no desk, no paper and no text**. Layer ids appear in the command string; the surfaces
behind them are empty.

This is fixed in the script now. `tools/build-wasm.sh:141-142` passes `-d:yantra_engine`, and
`:129-140` is the in-script comment explaining why it is mandatory rather than optional — the
script's only output is a module the engine loads, and `host/host.nim` (`cbLayerNew` /
`cbLayerDraw` / `cbLayerFilter`) always provides `y_layer_*`, so the real bindings are always
the correct ones for a build from this script. `yantra_headless` and a plain `nim c` remain the
deliberate no-op paths.

**The rule for a clone:** never invoke `nim c` by hand. Go through `tools/build-wasm.sh`. If you
must invoke `nim c` yourself for any reason, `-d:yantra_engine` is not optional.

### 4.2 The regression guard that catches it

Because no screenshot is available here (§3.1), the layer byte count is the **only** way to
observe whether procedural surfaces reached the host at all. `verify-wasm.mjs:317-326` stubs
`y_layer_new` / `y_layer_draw` and accumulates bytes; `:513-520` turns that into two assertions:

```
layers created: 2, draws: 85, bytes: 1061939
OK   app creates layers (newLayer reached the host)
OK   procedural surfaces were actually submitted (NOT a no-op build)
```

The threshold is `layers >= 2 && draws >= 2 && bytes > 100000`
(`verify-wasm.mjs:516-520`). **[measured]** on the 029 app: 2 layers, 85 draws, 1 061 939
bytes. A no-op build reports 2 layers, **0 draws, 0 bytes** — and would have passed every other
check in the harness. Keep both assertions in the copy you make for your own app.

> **CORRECTED 2026-10-03.** This subsection cited `verify-wasm.mjs:120-134`, `:280-287` and
> `:285-286`. The stubs are at `:317-326` and the assertions at `:513-520`; `:280` is
> `y_node_set_f32` and `:285` is a blank line. The threshold `draws >= 2 && bytes > 100000` was
> right and is unchanged.

### 4.3 "Compiles clean + passes the harness" is not "renders what you wrote"

Generalise §4.1. There are at least four independent gaps between "green" and "visible", and a
clone sits on all of them at once because it is large and drawing-heavy:

| Gap | Why green passes anyway | Where you catch it |
|---|---|---|
| `Layer` ops compiled to no-ops | ids still allocated, `Y n` still emitted | layer byte count (§4.2) |
| a prop exists in the protocol but no renderer reads it | it type-checks and is stored | `19` §7 — `grep -rn "P_<NAME>" render/` |
| a module imports a symbol the host does not implement | `verify-wasm.mjs` now refuses at `:184-229` — but only if you ran it | import census (§4.4) |
| the module exports `NimMainModule`, not `yantra_main` | every assertion passes; `host/host.nim:1188` finds nothing to call | `WebAssembly.Module.exports()` → `false` for `yantra_main` |
| the Draw commands are well-formed but describe the wrong thing | nothing parses them here | **a real screenshot — unavailable here** |

The first four are catchable headlessly. The fifth is not. That is the line.

> **Added 2026-10-03.** The `yantra_main` row is new. A module with only
> `when isMainModule: main()` compiles clean, passes every other check in the harness, and
> **renders nothing** — a 2,005-byte stub, measured. It is the single most expensive way for
> a clone to be "done".

### 4.4 The import-list diff — do this on every clone

The harness's import census tells you whether *the harness* anticipated your imports. It does
not tell you whether the **host** implements them. That check is separate and cheap, and it is
the one that catches a module importing something that binds fine but has no callback behind it.

Do it in two halves:

```bash
# 1. what the module actually imports
node -e "const m=new WebAssembly.Module(require('fs').readFileSync('apps/x/app.wasm'));
console.log(WebAssembly.Module.imports(m).map(i=>i.name).join('\n'))"

# 2. what the host actually implements
grep -n 'result\["y_' host/host.nim
```

`host/host.nim:1017` is `proc importTable(): Table[string, ImportSpec]` — the whole table. The
`y_layer_*` rows are at `:1069-1074`, which is the "~line 1069" this project keeps citing; the
layer block sits between `y_phys_hit` at `:1068` and `y_sys` at `:1075`. Every entry is
`ImportSpec(params: …, results: …, cb: cbName)` — note that a row with a `cb` is implemented and
a row without one is a hole.

**Done test:** every name in the module's import list appears as a `result["<name>"]` row in
`host/host.nim`. Any name that does not is either a symbol the host does not implement (the real
host will refuse to instantiate — `host/host.nim:1158` tests `name notin table`) or a name you
made up. Either way, fix it before you report anything.

---

## 5. Screenshot-diffing, on a machine where the host builds

> **[UNVERIFIED HERE]** Everything in this section is procedure taken from
> `render/native/drive.nim`'s own header and from
> `reference/01-build-run-and-verify.md` §4. None of it was executed in this checkout, because
> §3.1 says it cannot be. Treat it as a recipe to run elsewhere, not as a result.

### 5.1 Preconditions

- The native host **compiles from source** here. If any `render/native/*.nim` build dies on a
  missing header, stop — you have §3.1's environment, not this section's. (`21` §1 explains how
  to install the missing MSYS2 toolchain rather than concluding it cannot be built.)
- `bash tools/build-wasm.sh <app.nim> <app.wasm>` exits 0 (never a prebuilt artifact) — **and
  the output contains `build-wasm: wrote <app.wasm> (<n> bytes)`.** A failed build leaves the
  previous `.wasm` in place, and every tool below will cheerfully render the stale one: exit 0,
  a full-size raw, a confident number, for code that does not exist.
- `WebAssembly.Module.exports()` returns **true** for `yantra_main`.
  `host/host.nim:1188` calls it unconditionally; a module exporting only `NimMainModule`
  renders nothing.
- The harness in §3 passes **first**. Diffing pixels on top of a structurally wrong app wastes
  the whole cycle, and it is easy to mistake "the layout is off by 2 px" for "the tree is wrong".

### 5.2 Render the reference frame

`render/native/drive.nim` is the tool. Its own header (`drive.nim:1-25`) documents the calling
convention and the verb set:

```
drive app.wasm out.raw W H SCALE SCRIPT
```

- `SCALE` is scale, **not** frame count (`drive.nim:34`).
- `SCRIPT` verbs are separated by **`;`, never `,`** — a verb's own arguments contain commas
  (`click:400,400`), so a comma separator splits a verb in half and it silently does nothing.
  `drive.nim:12-14` records this having already cost a debugging round.
- Verbs: `click:X,Y`, `down:X,Y`, `up:X,Y`, `move:X,Y`, `drag:X1,Y1,X2,Y2` (8 interpolated
  moves), `key:N`, `text:S`, `wait:N`.
- Coordinates are in the frame's own pixel space, already scaled (`drive.nim:25`).
- The harness runs **five settle passes** before painting (`drive.nim:44-60` — the comment at
  `:49-55` explains why the clock must advance), because the app
  builds its tree on its first update — "without this the frame comes out uniform."

Use the `boxes` verb first (it prints the laid-out tree with no app instrumentation). It is the
cheapest way to find out whether a pixel offset is a *layout* bug or a *drawing* bug. `crash`
is the second: `drive.exe` writes `crashed=[…]` to **stderr** on every run
(`drive.nim:159-163`), so an app that exits 0, writes a full raw of the right size and painted
nothing of its own is visible immediately — **capture stderr, or you will not see it.**

### 5.3 Compare

1. **Same window size as the reference, exactly.** 18 phase 6. With a live site this means your
   browser viewport width/height must equal `W`/`H`.
2. **Same clock as the reference — and you must know what it was.** With a live site this is
   the trap, because the page keeps moving. Capture with `tools/capture-ref.ps1 <html> <out.png> <budgetMs>`
   so the budget is recorded and printed. **Two independent headless captures of the SAME
   animated page at the same nominal 800 ms budget differ from each other by 2.13%** —
   22,288 of 1,044,480 pixels. That is the noise floor. A comparison against a reference whose
   clock you did not record measures clock difference and reports it as port error.
3. **Swap the raw before any diff tool touches it.** The dump is headerless B,G,R,A
   (`render/native/drive.nim:191-193`) — Skia's `SkColor` is `0xAARRGGBB` and little-endian
   memory reverses it. **`tools/pngdiff.mjs:100-103` and `tools/refdiff.mjs:90-94` read bytes
   0,1,2 as R,G,B with NO swap.** Measured on one port, same reference, swap the only
   difference: **91.45% unswapped vs 72.83% swapped.** Run
   `node tools/rawswap.mjs <in_bgra.raw> <out_sw.raw>` first, always.
4. **Convert `.raw` → `.png`.** The bridge is in `01-build-run-and-verify.md` §4 step 3, and
   the two rules that make it work are: use `Format32bppRgb` on **both** the bitmap and the
   `LockBits` call, and assert the file length equals `w*h*4` before copying.
   **Reference PNGs, by contrast, are colourType 2 — RGB, 3 channels.** Every file under
   `.board/frames/ref*.png` was verified as colourType 2 / depth 8, so a decoder that assumes
   `stride = w*4 + 1` throws; **`w*3 + 1` works**, and `tools/refdiff.mjs:40` is the pattern to
   copy (`const ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]`).
5. **Count distinct pixels before you look.** A uniform frame passes every exit-code check while
   drawing nothing — `01` §4 calls this "the single most misleading failure in the renderer."
   **[measured]** on a real hello-world frame: 89 distinct colours. One or two means nothing was
   drawn. This is the cheap automated gate; make it the *first* diff check, not a later one.
6. **Trust `differing pixels` / `mean |delta|`; never a `pngdiff` band cell.** The band map is
   gated at `tools/pngdiff.mjs:133` on `if (rows[y] && cols[x] && …)`, so any row **or** column
   with zero differing pixels contributes nothing to its cell — bands read artificially low,
   and this produced three rounds of confidently wrong conclusions about one port. The headline
   numbers are computed before that gating and are authoritative. **Localise with
   `tools/refdiff.mjs`.**
7. **Then look, and diff the colours with a picker.** Colours by eye are exactly the "close
   enough" values `19` §4 rejects. Remember they are AARRGGBB (§2.3 above).
8. **Then diff the command stream.** For a drawing-heavy clone the `pDraw` string is the better
   artifact to diff than the image: it is deterministic, text, diffable line by line, and it
   localises a mismatch to a single command instead of a rectangle. The harness prints only
   its length (`verify-wasm.mjs:441-443`, `:489`) — raise the head to as much as you need, in
   your copy.

> **CORRECTED 2026-10-03.** Step 5 of the old list was *"Then diff the command stream … The
> harness already prints the length (`verify-wasm.mjs:255-259`)"*. That citation resolved to
> `y_node_set_str` and a blank line. The current locations are `:441-443` and `:489`. More
> importantly, **the old list had no step for the swap and none for the clock**, and both make
> the whole comparison meaningless rather than merely imprecise.

### 5.4 The stale-harness warning, restated for clones

`01` §4 records that `apps/minipaint/ENGINE-ISSUES.md` §5 was bitten by a `shot_excal.exe` older
than the shim it exercised: a shape rendered empty, with no error anywhere. A screenshot proves
what the **harness** drew, not what your app is.

Before you believe a diff:

- [ ] the harness binary's build time is **newer** than `render/native/engine.nim` and than your `app.nim`;
- [ ] the repo's own known-good fixture renders correctly through the **same** harness binary
      (e.g. `examples/shell/paint.nim`). If the fixture fails, the harness is stale and your diff
      is meaningless — go back to §3 and use the headless path until it is rebuilt.

### 5.5 Iterate

Work the difference list: fix, re-screenshot, re-diff, repeat until the diff is empty or every
remaining item is a written GAP in `PORT-NOTES.md` (18 phase 7). Then the interaction pass —
18 phase 7's second paragraph: click, type, scroll and hover the real thing; screenshots of the
idle screen are not interaction verification.

### 5.6 Some of the original is not reproducible, and you must say so rather than fake it

> **NEW 2026-10-04.** A clone often carries seeded randomness. A `mulberry32`/`xorshift`
> PRNG with a constant seed *is* reproducible — port it faithfully and the sequence matches.
>
> **But a PRNG consumed by a comparison callback is not.** On 075, `html:581` shuffles with
> `[0,1,2,3,4].sort(function(){ return R() - 0.5; })`. The comparator draws from the PRNG, so
> **how many times the comparator runs is implementation-defined** — that is a property of
> V8's TimSort, not of the source. The resulting permutation cannot be derived from the
> source at all. Using Fisher-Yates instead produces a *valid* shuffle with a *different*
> one, and the PRNG stream then diverges from that point onward.
>
> The honest report is: **this is not reproducible in principle**, name the line, and say
> what *does* land — in that case the 70 wear circles and 260 speckles after the shuffle
> stayed statistically identical, so the seal's weight and texture matched even though its
> glyph pattern never could.
>
> Do **not** spend rounds chasing it, and do **not** quietly substitute and let the diff
> absorb it. `19-done-checklist.md` treats an unexplained GAP as a failure; an *explained*
> GAP is the deliverable. Same rule for the reverse mistake: if you find yourself hoping a
> region is grain so you can stop, measure it first (see `21-visual-parity-verification.md`,
> "split grain from structure") — on 070 the title block turned out to be only **6.5% grain**,
> pure structure, and would have been a false excuse to leave it.

### 5.7 The other half: a seeded PRNG **is** reproducible, and porting it is worth thousands of pixels

> **NEW 2026-10-04.** §5.6 above is about the PRNG you *cannot* reproduce. This is about
> the one you absolutely can, and which is very easy to mistake for a decoy.
>
> On 070 the 64 board squares each carry their own gradient. The style rule reads
>
> ```
> background-image: linear-gradient(var(--ga, 90deg),
>                   rgba(255,248,230, var(--v1, .05)),
>                   rgba( 60, 30, 10, var(--v2, .06)))
> ```
>
> and the obvious reading is **one 90° wash at fixed alpha over the whole board** — which
> is exactly what the port did, for five rounds, while looking correct on the light squares.
>
> But `90deg` and `.05/.06` are only the **`var()` fallbacks**. A generator overwrites all
> three per square:
>
> ```
> let seed = 90210;
> const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
> btn.style.setProperty('--ga', (light ? 88 + rnd()*6 : -3 + rnd()*6) + 'deg');
> btn.style.setProperty('--v1', (0.02 + rnd()*0.07).toFixed(3));
> btn.style.setProperty('--v2', (0.02 + rnd()*0.08).toFixed(3));
> ```
>
> Replaying that gives light squares **88.2–93.9°** and dark squares **−2.8–+3.0°**. So a
> dark square gets a near-**vertical** wash and a light one a near-**horizontal** one — the
> port was ramping the wrong axis on half the board. Measured across one dark square:
> reference brightens left-to-right `(136,92,62) → (146,101,71)`, the port darkens
> `(130,86,59) → (118,73,46)`. **Opposite-signed ramps, not a small tone offset.**
>
> That signature matters: it survives every per-square *colour* sweep, because the colour
> at the centre of the square is nearly right while the gradient direction is not. Five
> rounds of tuning the wrong quantity is what it costs.

**Four things that have to be exactly right, and each is a separate way to be close-but-wrong:**

1. **The call order.** Three `rnd()` per square, in source order, `s = 0..63`. One extra
   or missing draw shifts every subsequent value in the stream.
2. **The integer width.** `seed * 16807` reaches ~3.6e13 — **int32 overflows**. Use int64.
   A 32-bit port produces a plausible, wrong sequence that never throws.
3. **The index mapping.** Squares are indexed `s = (7 - row) * 8 + col`, from the page's own
   `disp()` with `flipped=false`. Off-by-one-flip here mirrors the whole board.
4. **Gradient coordinates are element-local.** A CSS `background` gradient is sized to the
   element's **padding box**, not the viewport. Pass the square's own size and
   square-local coordinates, or every square ramps across the full board instead of itself.

**And the proof, which is worth more than the fix** — check a region that contains **none**
of the randomised element:

```
rank 5  y324-408:  314 ->    2 structural px   (no pieces in this rank at all)
rank 6  y240-324:   79 ->   30
rank 4  y408-492:  202 ->   26
```

A band with no piece geometry going to zero can only mean its error was the board's own
tone. **That is what distinguishes "I fixed the mechanism" from "I found a number that
went down."** Seek out such a control region before you believe any broad change.

Two general rules fall out:

- **`var(--x, fallback)` in a stylesheet means the fallback is a decoy**, not a default.
  Always grep for the setter before you trust the literal. (`grep` the whole file — see
  `02-reading-the-real-error.md`, "a bounded grep is not a grep".)
- **Grep the source before theorising.** This one cost five rounds of per-square colour
  tuning; the answer was in one `grep -- '--ga'`.

---

## 6. Clone-specific checklist

`19-done-checklist.md` is the gate; these are the boxes that a *clone* fails and a local-file
port does not. Answer every one, or write a GAP.

### Capture and cascade

- [ ] Viewport size frozen and written into `PORT-NOTES.md` **before** any measurement.
- [ ] A reference screenshot exists per **state**, not per page.
- [ ] The computed-style dump was taken at that viewport; pseudo-elements and `::before` /
      `::after` artwork were inspected separately in the Elements panel (§2.2).
- [ ] `getBoundingClientRect` values were corrected for scroll; transformed elements have
      **both** their untransformed and their bounding box recorded.
- [ ] Every value in the port appears in the capture. No value exists only in the original CSS.
- [ ] **Every colour is written AARRGGBB**, not as the bare CSS hex — a pasted `0xF7F9FB` has
      alpha `0x00` and draws fully transparent (§2.3).
- [ ] **`font-size` is set on every text node, not inherited** — `15a` §4.1.
- [ ] **Text is placed from a recorded baseline**, converted with `yantra_y = baseline - 1.0833 * size`
      (§2.3). Any custom `font-family` in the source means those constants must be re-probed.
- [ ] **Every centring or wrapping is recorded as an estimate**, because there is no text
      measurement API to make it exact (§2.3).
- [ ] Each media query became a `sized` block; each class became one `proc (): Style` (`15a` §6).
- [ ] The live site's PRNG was transcribed or replaced, so the port is deterministic and can be
      diffed at all.

### What the harness proves

- [ ] `pwsh -NoProfile -File tools/guard-29.ps1` (retargeted to this app — §3.2) exits 0.
- [ ] The wasm was **rebuilt from source** in that same run.
- [ ] The import census is empty of `UNSTUBBED` and `CALLED-BUT-NOT-DECLARED`.
- [ ] Every module import appears as a `result["<name>"]` row in `host/host.nim` (§4.4).
- [ ] Node-tree assertions cover every **measured px** from `PORT-NOTES.md` — width, height,
      spacing, padding — not just "the tree is not empty".
- [ ] The `pDraw` length assertion is present.
- [ ] A real click/frame dispatch happened and the **length or state changed** after it.
- [ ] The layer assertions are present and non-zero — `draws >= 2 && bytes > 100000`.

### What the harness does not prove — must be stated in the report

- [ ] The report says **"appearance NOT verified"** with §3.1 as the reason, if it was run in
      this environment. Do not write "verified visually", "looks right", or "renders correctly".
- [ ] No number in the report is one you did not measure (AGENTS.md rule 11). Not "diff < 1 %".
      Not "matches the original".

### Appearance, where it is possible

- [ ] The native host was rebuilt from source, not taken from `render/native/build/`.
- [ ] The known-good fixture renders correctly through the harness binary first (§5.4).
- [ ] Distinct-pixel count is not 1 or 2 before any diff is read.
- [ ] Colours compared with a picker, at the same window size.

---

## 7. The two sentences to keep in your report

**In this environment:**

> Rebuilt from source; headless harness N/N passed (node tree, `pDraw` length, layer bytes,
> dispatched-event state change); appearance NOT verified — the native host cannot be compiled
> here (`render/native` needs SDL3/curl/ffmpeg/Jolt/Skia headers absent from `third_party/`, and
> the prebuilt `*.exe` predate `engine.nim`).

**On a machine where the host builds:**

> Rebuilt from source; headless harness N/N passed; screenshot-diffed at <W>×<H> against the
> reference: <measured distinct-pixel count> colours, <measured list of remaining differences>,
> each remaining item written as a GAP in `PORT-NOTES.md` with its reason.

Neither sentence may contain a number you did not measure. A reported failure is a fine outcome;
a fabricated pass is not (AGENTS.md rule 11).