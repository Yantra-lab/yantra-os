# skills/

**This is the folder you hand to an LLM that is being asked to make something
Yantra can run.** Point an agent at this folder and nothing else, and it should be
able to build a Yantra app or clone a web page without looking anywhere else.

Everything below is either read out of the engine source with a `path:line`, or
measured against the real renderer. Where a chapter repeats something that later
turned out to be wrong, the old claim is still there with a `CORRECTED` note
underneath it — so you can see what changed and why, instead of silently
inheriting a rule that was already broken.

---

## Changelog — what was corrected in this pass, and why

**2026-10-03 — routing repaired, engine facts reconciled with measurement.**
Every claim below was re-checked against source, not against memory.

### Routing

- **Chapters 21, 22 and 23 were orphaned** — nothing linked to them. They are now
  in `yantra/reference/00-INDEX.md` and in `yantra/SKILL.md`.
- **`web-to-yantra/` was unrouted.** It is a second, complete skill (the
  command-by-command HTML/CSS/Canvas2D/SVG/Events port). It is now linked from
  this README, from `00-INDEX.md` and from `SKILL.md`.
- **Two links pointed at a file that does not exist**:
  `yantra/CHANGELOG.md` and `yantra/SKILL.md` both referenced
  `reference/15a-html-css-js-mapping.md`. The real file is
  `reference/15a-html-css-mapping.md`. Both fixed; the targets verified to exist
  before editing.
- **The chapter count was wrong.** It said "20 routed chapters". The true count
  is **22 chapters plus `00-INDEX.md` = 23 files in `reference/`**. There is no
  chapter `04` and no `14`/`15`; the numbering skips them and that is deliberate.

### Engine facts corrected in the chapters

- **`Draw.text(x, y, …)`'s `y` is the top of the paragraph line box, not the
  baseline.** `libs/nimskia/src/skia_shim.cpp:291` calls
  `SkParagraph::paint(canvas, x, y)`. The doc comment at
  `libs/nimskia/src/nimskia.nim:76` says "top-left at (x, y)" and is **wrong** —
  it is the direct cause of mis-positioned text. Measured offsets from `y`, in
  units of font size `S`, verified at S=12, 24 and 48: cap top `y + 0.375·S`,
  x-height top `y + 0.583·S`, **baseline `y + 1.0833·S`**, descender bottom
  `y + 1.333·S`. So `yantra_y = wantedBaselineY - 1.0833 * size`. This is
  **empirical, for the default typeface and weight only** — a port that sets a
  family or a non-default weight must re-probe. Carried into `06`, `09`, `15a`,
  `16` and the verification chapters.
- **Colour alpha — and the trap is `Draw`-specific.** Every `Draw` primitive takes
  `argb: uint32` in **AARRGGBB**. A CSS hex pasted straight in (`0xF7F9FB`) has
  alpha `0x00` and draws fully transparent — it compiles, it runs, nothing
  crashes, and it is invisible. **Node** colour props are *not* affected:
  `render/native/engine.nim:345-348` (`proc argb`) promotes a missing alpha byte
  to `0xFF`. **A `Draw` colour gets a bare `paint.setColor` at
  `libs/nimskia/src/skia_shim.cpp:1327` with no such rescue.** So the specific
  trap is *moving a colour that worked on a node into a `Draw` list* — it stops
  being drawn, silently. Force `0xFF` up front.
- **`fill = 0x000000` paints opaque black — it does not mean "paint nothing".**
  A consequence of the line above: `argb(0)` is `0xFF000000`. Combined with
  `style.nim:26` clamping `rgba`'s alpha to at least 1, **alpha 0 is unreachable
  on a node at all**. To not paint, omit `fill`.
- **`rgba` is defined twice with different signatures** — `sdk/ui/style.nim:23`
  (`proc rgba*(rgb: int; alpha: float): int`, a *signed* int taking a packed
  `0xRRGGBB`) versus the app-local `proc rgba(r, g, b: int32; a: float32): uint32`
  that ports define. Nim picks the local one, so it works, but you cannot tell
  from the call site which is in scope.
- **`Draw.alpha()` is NOT silently dropped.** The claim that it is, was checked
  and found to be **false against the current source**: `sdk/ui/paint.nim:80`
  emits `"O "`, and `libs/nimskia/src/skia_shim.cpp:1412` is
  `case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;`. The
  accumulator is applied by the `colour` lambda at `skia_shim.cpp:1327` to every
  drawing verb. It is a **cumulative multiplier, not a setter**. The related
  claim that survives: an *unrecognised* verb is skipped with no error
  (`skia_shim.cpp:1413` `default: break;`).
- **`frameDt()` is the live clock; `yantra_get_dt()` is dead on the native
  runner.** `sdk/ui/input.nim:45` is `frameDt`. `sdk/core/runtime.nim:75`
  declares `yantra_get_dt` as an `importc`, and its only writer is
  `setFrameDt` (`host/host.nim:1211`), which appears in exactly two files
  repo-wide: `render/render_qml.nim:42` (legacy Qt) and `host/t_run_hello.nim`
  (a test). **Zero** occurrences under `render/native/`, `cli/`, `apps/`, `web/`.
  An app animated off `yantra_get_dt()` reads 0 and never moves.
- **`log()` is a dead instrument** under `drive.exe`, and one call measured at
  **+15,660 bytes (~7% of a ~215 KB module)**. Debug by drawing or by reading
  pixels.
- **Six `render/native/` test files cited by `16-engine-limits-and-workarounds.md`
  do not exist** (`t_paint_arc.nim`, `t_paint_path.nim`, `t_paint_alpha.nim`,
  `t_font.nim`, `t_assetready.nim`, `t_select.nim`). They sit in that chapter's
  *"where the fix would live"* column, so they are **proposed** files, not
  fabricated citations — but nothing said so, and a reader could not tell. Every
  one is now marked `new test … (does not exist yet)`, and the chapter carries a
  banner listing all six. Every surviving `path:line` citation in the folder was
  re-verified against the real tree; **nine wrong line numbers in `16` were
  corrected**, including `engine.nim:4071` (which is `proc synthSamples`, not
  `tick`) and `host/host.nim:801`/`:932` (entirely the wrong functions).
- **Chapter 15a's internal links.** Five were genuinely broken and are fixed: a
  pointer to a `§3.4` that never existed, a pointer to cascade discussion in `§4`
  (it is `§6`), a `§5.2` that is `§5.3`, an ambiguous `§3` that meant
  `docs/spec/style.md §3`, and `protocol/gen.nim:518` (a blank line) pointing at a
  `docs/props.md` that does not exist. The inbound **section** citations from
  other chapters all turned out to resolve correctly — what was stale was
  *line-number pinning across files*, now replaced with section citations.
- **Real API gaps, re-stated from `sdk/ui/paint.nim`:** there is **no
  filled-polygon primitive** (a polygon is `moveTo:28` / `lineTo:29` /
  `close:45` / `fill:53`) and **no `ellipse` proc** (`circle:59` emits rx=ry=r; an
  ellipse needs four `curveTo:35` calls or an `svgPath`). **`svgPath` does exist**
  — `sdk/ui/paint.nim:46`. Any chapter claiming svgPath was missing is corrected.
- **Frame dumps are BGRA and must be swapped.** `render/native/drive.nim:191-193`
  `copyMem`s a `seq[uint32]` of Skia `0xAARRGGBB` pixels to disk, so the bytes are
  **B,G,R,A**; `tools/pngdiff.mjs:101-103` reads them as R,G,B with no swap.
  Measured on one port, same reference, swap being the only difference:
  **91.45% unswapped vs 72.83% swapped**.

### `scripts/` and `assets/` — honest status

**Neither directory exists.** Earlier drafts of this folder advertised both as if
they held helpers and assets. They held nothing — they were empty placeholders —
and they have since been removed from the tree, so nothing here points at them.

The real helpers live in the repo's `tools/` and every one of these was verified
to exist before being listed:

| tool | what it does |
|---|---|
| `tools/build-wasm.sh` | build a `.nim` into a `.wasm` |
| `tools/rawswap.mjs` | **required** — BGRA → RGB before any diff |
| `tools/pngdiff.mjs` | headline `%`, mean/max delta, band map |
| `tools/refdiff.mjs` | localise a diff (worst bands, per-column delta) |
| `tools/rowink.mjs` | ink runs per row — how you find exact text rows |
| `tools/capture-ref.ps1` | capture a reference PNG with a recorded clock |
| `tools/floor.mjs` | detect an already-swapped file, so you do not swap twice |

Binaries, for reference: `render/native/build/drive.exe` renders an app and dumps
a frame; `render/native/build/mpdrive.exe` drives a multi-port sequence;
`render/native/build/desktop/yantra_run.exe` is the full desktop runtime (the
`desktop/` subdirectory is the deployment layout — that is where the DLL set
lives). **`render/native/build/shot.exe` does not exist** — earlier drafts of
`yantra/SKILL.md` told you to run it.

---

## Layout — what is actually here

```
skills/
├── README.md                  <- you are here; the entry page
├── yantra/                    <- the skill (SKILL.md is its entry point)
│   ├── SKILL.md
│   ├── CHANGELOG.md           <- maintained; add a line for every port or fix
│   ├── reference/             <- 23 files: 00-INDEX.md + 22 chapters
│   ├── examples/              <- 2 apps, both compile
│   └── translated-skills/     <- Anthropic's Agent Skills, translated to Yantra
└── web-to-yantra/             <- the second skill: the port playbook
    ├── SKILL.md
    ├── HTML5-CANVAS-TO-SKIA.md
    ├── CSS-SHADOWS-AND-EFFECTS.md
    └── DOM-EVENTS-TO-SDL3.md
```

---

## How an LLM should use this folder

**Start at `yantra/SKILL.md`.** It is five lines of "what Yantra is", the exact
build command, and a complete compiling program. From there:

1. **Read `SKILL.md` in full.** It is short on purpose.
2. **Use `yantra/reference/00-INDEX.md` to pick chapters.** It carries one honest
   line per chapter: what it is for, and what you will be able to do afterwards.
   It also carries the conflict-resolution rules below.
3. **For a port, read `web-to-yantra/SKILL.md` early.** It is the command-by-command
   translation of HTML/CSS/Canvas2D/SVG/DOM-events into Yantra, worked end to end
   on a real page (`apps/typewriter`). It tells you which of Yantra's three layers
   each piece of a page belongs in — a decision you otherwise make by accident.
4. **Read only the chapters the task needs.** 03 is the lookup table; 16 is the
   honesty check; 19 is the gate. You do not need 12 for a form page.
5. **Never invent an API.** Every name in this folder was read out of the SDK
   source. If it is not in `03-node-and-prop-reference.md`, it does not exist —
   and check `16-engine-limits-and-workarounds.md` before assuming it is missing.
6. **Compiling is not rendering.** A prop can exist in the wire protocol and be
   ignored by the renderer. Always produce a frame and look at it.

Suggested prompts that work:

- *"Read `skills/yantra/SKILL.md` and `skills/web-to-yantra/SKILL.md`, then port
  `apps/foo/029-thing.html` to `apps/foo/app.nim`. Build it. Screenshot it.
  Iterate until it matches. Keep `skills/` updated with anything you learned —
  see the `CORRECTED` format in `yantra/reference/06-text-and-fonts.md`."*
- *"Read `skills/yantra/SKILL.md` and clone <URL> into
  `apps/clones/<name>/app.nim`, pixel-perfect at 1280×800. Use
  `skills/yantra/reference/21-visual-parity-verification.md` and report a
  measured number, not an impression."*

## When two chapters disagree

This is the rule that matters most, because the chapters are not a manual — they
are a record of what was true when each was written.

1. **The engine's source beats both chapters.** Open the file — `sdk/`,
   `host/`, `render/`, `libs/nimskia/` — and read it. That is the only authority.
2. **Otherwise: later and more specific wins.** A chapter scoped to one subsystem
   beats a general one.
3. **A `CORRECTED` note supersedes the text above it** in the same chapter.
4. **Measured beats documented.** Where a number was measured against the real
   renderer, the measurement wins even when a doc comment says otherwise. The
   text `y` origin is exactly this case: `nimskia.nim:76` documents one thing and
   the pixels say another.
5. **If you find a fourth kind of disagreement — one no rule here covers — fix the
   chapter in the same change as whatever you were doing**, with the `path:line`
   or the measurement that settles it.

## Why it is trustworthy

- Every API in it was read out of the SDK source, not from memory, and is cited by
  `path:line` so you can check it in one keystroke.
- Every code block was compiled with `tools/build-wasm.sh` before being written
  down.
- Compiler errors quoted in it are real, measured, and reproduced on purpose.
- Anything the renderer does not actually draw is marked `NOT SUPPORTED YET`
  with a workaround, rather than quietly implied to work.
- Where a doc comment and the measured behaviour disagree, **both** are printed,
  with the measurement winning. That is the failure mode this folder exists to
  prevent: a rule memorised by three ports before anyone measured it.

### The open-marker rule, and where it currently stands

This folder's own contract (`yantra/SKILL.md`) is: *never leave a verification
marker behind — resolve it or delete the claim.* That is the right rule, and it
is **not yet fully met**. Be clear-eyed about that rather than claiming a clean
sweep.

This pass **resolved ten** of them outright — the text frame clock, `flex()`'s
direction argument, the `nk…` spellings, `visibilitychange`, `lineHeight` (a
**multiplier, not px**: `skia_shim.cpp:96,359`), `sticky`, `smooth`, `direction`,
the font cascade, and whether any colour form besides `rgba` exists in `sdk/`.
Each was replaced with the settled fact and its `path:line`.

**About two dozen remain, and they are not padding.** Fifteen are in
`reference/15a-html-css-mapping.md`, listed in its own §10; the rest are one to
four each in `02`, `06`, `07`, `10`, `11`, `13` and
`web-to-yantra/HTML5-CANVAS-TO-SKIA.md`. They mark cases where reading the source
genuinely does not settle the question — does Skia resolve a generic family name
like `serif`? does Yoga honour a negative margin? what are `windowAction`'s exact
int values? Those are honest "nobody has checked this yet" flags, and they are
safer than a confident guess.

**How to treat one:** do not build on the claim until you have read the renderer
yourself. A marker is a debt someone still owes an answer, and it is better than
an unmarked claim that turns out to be wrong.

## Keeping it alive

This folder is expected to improve with every port. See
[`yantra/CHANGELOG.md`](yantra/CHANGELOG.md) for the table of where each kind of
learned fact belongs, and `yantra/SKILL.md` §"Keeping this skill current" for
the rule: you learn something on a real port, you write it down before you
finish.
