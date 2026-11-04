# translated-skills/

Anthropic's official Agent Skills, translated to Yantra.

## What "translated" means here

These are **not ports**. Anthropic's document skills drive `python-docx`, `openpyxl`,
`python-pptx`, `pypdf`, `pptxgenjs`, `docx` (npm) and LibreOffice as **agent-side tools**.
A Yantra app is a sandboxed WebAssembly module with no filesystem, no Python, no
subprocess — `sdk/core/runtime.nim` imports only node ops, storage, fetch, file-read and
file-pick.

So every skill here makes the same distinction, up front:

| Half | Where it runs |
|---|---|
| **Building / viewing** the artefact | inside the app — nodes, layout, the engine's draw calls |
| **Producing a binary file** (`.docx`, `.xlsx`, `.pptx`, arbitrary PDF bytes) | a normal tool on the agent's host, outside the sandbox |

The second half is completely legitimate and is how the file gets built. What these skills
refuse to do is pretend it can happen inside the sandbox.

**Rule followed throughout: never invent a Yantra API.** Every name quoted here was read
from the SDK or docs, and every code block marked as compiling was actually built with
`tools/build-wasm.sh`. Where a capability does not exist, the skill says
`NOT SUPPORTED YET` and gives the recommended path.

---

## The document skills

### [`yantra-pdf`](pdf/SKILL.md)
Split most sharply, because Yantra genuinely has document capability.

**Real:** `page` / `slide` nodes are the same kind (`nkPage` = 44,
`sdk/core/wire.nim:50`; wired at `sdk/ui/dsl.nim:411`). `Engine.exportPdf`
(`render/native/engine.nim:4261`) walks them in paint order and writes one PDF page each, at
that node's own size, using the *same* `paintTree` as the screen — so shapes stay vectors
and text stays selectable. `slide` is `page` with `width(1280)`/`height(720)` pre-set.

Measured from real exported output: a `page` at `794 × 1123` px → `/MediaBox [0 0 596 842]`
(A4, via `ptPerPx = 72/96`); a `slide` → `/MediaBox [0 0 960 540]` (13.33 × 7.5 in, 16:9).
`/FontFile` and `/ToUnicode` both present, so the text is real.

**Host-side:** merging, splitting, rotating, watermarking, encryption, OCR, form filling —
all unchanged from the original, because those tools never ran in the sandbox.

### [`yantra-pptx`](pptx/SKILL.md)
A deck is a program. `slide` nodes, live apps inside a slide (`appView`), and the same app
renders to video via `render/native/film.nim`. PPTX file *output* is host-side `pptxgenjs`,
with the original's gotcha list preserved verbatim.

### [`yantra-xlsx`](xlsx/SKILL.md)
`sdk/ui/sheet.nim` is a real spreadsheet-scale grid: virtualised to visible cells, frozen
rows/cols, headers, column resize, selection, hit-testing. A cell is a
`proc (r, c: int): string` — so the "formula" is just Nim. Writing a real `.xlsx` with
formulas is host-side `openpyxl` + `recalc.py`, unchanged.

### [`yantra-docx`](docx/SKILL.md)
Documents are `page` trees; `rich` gives inline markup (`**bold**`, `*italic*`,
`` `code` ``, `~~strike~~`, `[link](url)`); `sdk/ui/blocks.nim` gives a real block editor
with markdown shortcuts. Mail merge is a `for` loop. `.docx` file output is host-side
`docx` (npm), unchanged.

### [`yantra-doc-coauthoring`](doc-coauthoring/SKILL.md)
A *workflow*, not a tool — so it translates almost completely. Only the deliverable-handling
notes changed.

---

## Honesty notes worth knowing before you use these

- **`docs/office.md` is a proposal, not a spec.** Its `doc` / `sheet` / `deck` DSL keywords
  do **not** exist. `sdk/ui/dsl.nim:440` raises `unknown node kind sheet`. Use `page`,
  `newSheet`, `slide`.
- **`sdk/office/formula.nim` is an unmerged worktree** (`STATE.md`: "cherry-pick, not
  branch-merge"). There is no formula parser or recalculation engine in the SDK today.
- **No PDF viewing inside an app.** No PDFium binding in the SDK, so an app cannot
  rasterise or paginate an arbitrary PDF. Extract host-side and render *that*.
- **Compile errors quoted in these skills are real and reproduced on purpose** — colours
  are `int` not strings; `window` is a proc not a `Node`; multi-line string concatenation
  does not parse inside a UI block; one `app` block per module; `.component.` procs take no
  parent parameter.
- **Do not trust a stale `.wasm`** (`AGENTS.md` rule 2). Rebuild from source.

## Other translated skills

Folders in this directory not listed above were translated by other agents:
`skill-creator/`, `web-artifacts-builder/`, `webapp-testing/`.

## Originals

All five were fetched successfully from
`https://raw.githubusercontent.com/anthropics/skills/main/skills/<name>/SKILL.md` on
2026-10-03. None had to be reconstructed from memory.