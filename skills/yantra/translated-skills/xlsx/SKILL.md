---
name: yantra-xlsx
description: "Use this skill any time a spreadsheet is the primary input or output — opening, reading, editing or fixing an .xlsx/.xlsm/.xltx/.csv/.tsv, adding columns, computing formulas, formatting, charting, cleaning messy tabular data; or creating a spreadsheet from scratch or from another data source. Also trigger when cleaning messy tabular data into a proper table. The deliverable must be a spreadsheet. In Yantra a spreadsheet is an app: `newSheet` gives a virtualised million-row grid, and a cell holds either a formatted string or any Nim expression. Writing a real .xlsx is a host-side openpyxl job, not a sandboxed one."
license: Proprietary. Translated from Anthropic's `xlsx` skill; see NOTICE.md.
---

# XLSX / spreadsheets in Yantra

**This is a translation, not a port.** Anthropic's `xlsx` skill drives `openpyxl`, `pandas`
and LibreOffice recalculation as agent-side tools. Yantra's spreadsheet story splits in two.

## The rule

| Half | Where it runs | What |
|---|---|---|
| **Viewing / computing / exploring data** | inside the app | `newSheet` — a virtualised grid, cells are Nim expressions |
| **Writing a real `.xlsx` with formulas** | host-side tool | `openpyxl` + `scripts/recalc.py` — the agent's machine |

An app sandbox cannot `import openpyxl`, cannot read `/data/orders.csv` off an arbitrary
disk path, and cannot run LibreOffice. The spreadsheet *you ship* is a file the agent writes
on the host. The spreadsheet *you explore in* is an app.

---

## 1. What Yantra genuinely has: a real grid

### The mechanism, verified

`sdk/ui/sheet.nim` — "A spreadsheet-scale grid (P8) on one Canvas node: only the cells that
show are drawn, so a million cells cost what a screenful costs."

```nim
type Sheet* = ref object
  node*: Node                          ## the Canvas
  rows*, cols*: int
  colW*: seq[float32]                  ## width of each column
  rowH*: float32
  frozenRows*, frozenCols*: int
  headerH*, headerW*: float32          ## the A B C row and the 1 2 3 column (0: none)
  cell*: proc (r, c: int): string      ## what a cell shows
  onEdit*: proc (r, c: int; x, y, w, h: float32)
  onSelect*: proc (r, c: int)
  selR*, selC*: int
  ink*, grid*, head*, headInk*, sel*, bg*: uint32
```

What this gives you, all verified by reading the source:

- **Virtualised.** `redraw` rebuilds the draw list from what shows: `O(visible cells)`, not
  `O(rows × cols)`.
- **Frozen rows and columns.** `frozenRows` / `frozenCols`, with the corner redrawn last.
- **Row and column headers.** `colName(0)` → `A`, `colName(25)` → `Z`, `colName(26)` → `AA`.
- **Column resize** by dragging a header edge, with a 24 px floor.
- **Selection** (`selR`/`selC`, `onSelect`) and an **edit hook** (`onEdit` gives you the cell
  rect so you can place an editor there).
- **Hit testing** — `sheet.hit(x, y)` returns the cell under a node point, `(-1, -1)` in a
  header. This is what makes the grid interactive.

### A complete, verified program

I compiled this to confirm every name:

```nim
import yantra

proc Grid(parent: Node) =
  let sh = newSheet(parent, rows = 50_000, cols = 8,
    cell = proc (r, c: int): string =
      if r == 0: colName(c)
      elif c == 0: "row " & $r
      else: $((r * c) mod 997))
  sh.frozenRows = 1
  sh.frozenCols = 1
  sh.redraw()

app("Orders", width = 900, height = 600, fill = 0x101015):
  Grid()
```

`newSheet*(parent: Node; rows, cols: int; cell: proc (r, c: int): string): Sheet`

Notes from getting it to compile:

- **`newSheet` takes a real `Node`, not the DSL `window`.** Inside an `app` block, `window`
  is a *proc* — passing it gives `type mismatch: proc (title: string; …)` where a `Node` was
  expected. Inside a `{.component.}` proc the implicit `yParent` is the right value.
- **`.component.` procs take no parent parameter.** `proc Grid(parent: Node)` makes the call
  site demand an extra argument. Use the implicit `yParent`.
- **`cell` is a `proc (r, c: int): string`** — a callback, not data. A million cells cost one
  closure. This is the design: you compute cells, the grid virtualises them.
- **`redraw()` is manual.** The sheet redraws itself on resize, scroll, select and drag; call
  it after changing anything it cannot see (as above, after setting `frozenRows`).

### The thing the original skill never had

`docs/office.md` §3 — the ambition:

> A sheet cell can hold an Excel formula **or any Nim expression**; a whole sheet can import
> a Nim module. (Python-in-Excel, but compiled, sandboxed, and offline.)

So a "cell" is a Nim expression evaluated against live signals. That is genuinely better than
`=SUMIFS(...)` for anything that is not a spreadsheet-shaped question — and it is the reason
you would build the grid in Yantra rather than read a CSV.

**Be honest about the boundary:** that vision is a *proposal for Owner review*, not shipped.
What exists today is the grid, the callbacks, the virtualisation and the interaction. There
is no formula parser, no dependency graph and no recalculation engine in the SDK. `STATE.md`
lists `agent/O1-formula-engine` as an in-flight worktree ("cherry-pick, not branch-merge").
Check the source before you rely on it.

---

## 2. Producing a real `.xlsx` — host-side, unchanged

This is the bulk of the original skill, and it is still correct. Reproduced because a
spreadsheet that opens is a different skill from one that produces a corrupt file.

### Requirements for every output

- **A professional font throughout** unless the user says otherwise.
- **Zero formula errors.** Never ship while `recalc.py` reports `errors_found`.
- **Use formulas, never hardcoded results.** `sheet['B10'] = '=SUM(B2:B9)'`, not the
  Python-computed total. The sheet must recalculate when its inputs change.
- **Follow the user's spec literally.** Exact tab names, exact column headers, the exact
  formula they spelled out. A redesign that computes something else fails, however elegant.
- **Document every assumption and hardcoded number** where the reader will see it. Cite a
  real source when one exists; when the number came from the user, say so plainly.
- **A workbook you create for someone to fill in** needs a short legend naming which cells
  to edit, and one example row of realistic values. Never add such a row to a file you were
  asked to edit.
- **Editing an existing file: match its conventions exactly.** They override every guideline
  here. Find the designated input cells first, write only there, leave existing formulas
  untouched.

### Recalculate — mandatory whenever the file has formulas

openpyxl writes formulas as strings with **no cached values**. Until you recalculate, every
formula cell reads back as `None` to pandas, to `load_workbook(data_only=True)`, and to most
previewers.

```bash
python scripts/recalc.py output.xlsx [timeout_seconds]   # default 30
```

You get JSON: `status` (`success` | `errors_found`), `total_formulas`, `total_errors`, and an
`error_summary` naming up to 100 cells per error type. JSON with an `error` key means nothing
was recalculated — that is the only case that exits non-zero. `errors_found` exits 0, so
**never treat a clean exit as a clean workbook.**

**A green recalc proves your formulas evaluate, not that they are right.** An off-by-one range
yields a clean, error-free file with wrong numbers. Write 2-3 formulas first and check they
pull the values you expect, before building out a grid.

**A workbook that links to another file loses those links** if you re-save it with openpyxl
and then recalculate. `='[1]Returns Analysis'!$B$2` — the `[1]` names a separate file on disk.
openpyxl strips the cached value on save; LibreOffice then resolves for real, fails, writes
`#NAME?`, and deletes every link. Copy those cells' values out before you save over them.

### Choosing formulas that survive verification

- **Prefer Excel-2007-era functions** — `SUMIFS`, `INDEX`, `MATCH`, `IFERROR`, `SUMPRODUCT`.
- **Six post-2007 functions work only with an `_xlfn.` prefix**: `_xlfn.TEXTJOIN`,
  `_xlfn.CONCAT`, `_xlfn.IFS`, `_xlfn.SWITCH`, `_xlfn.MAXIFS`, `_xlfn.MINIFS`. Bare, each
  yields `#NAME?`.
- **Never use `XLOOKUP`, `XMATCH`, `SORT`, `FILTER`, `UNIQUE`, or `SEQUENCE`.** The runtime's
  LibreOffice cannot evaluate them under any prefix, and an openpyxl-written file has no spill
  metadata, so only the top-left cell gets a value — and `recalc.py` reports
  `total_errors: 0` on the truncated result. Use `INDEX`/`MATCH`; sort, filter and
  de-duplicate before writing the cells.
- A formula LibreOffice could not parse is written back **lowercased** — a quick tell beside
  a `#NAME?`.

### openpyxl gotchas

- **Reading a model takes two loads.** `data_only=True` gives cached values with formulas
  gone; the default gives formula strings with no values. One pass cannot give you both.
- **`data_only=True` is destructive if you save.**
- **`data_only=True` on a file openpyxl just wrote returns `None` everywhere** — recalc first.
- **Merged cells: write the top-left anchor only.**
- **`.xlsm` loses its macros unless you pass `keep_vba=True`.**
- **A sheet name containing a space must be quoted**: `='Assumptions Inputs'!$B$5`.

---

## 3. Financial models — the colour convention is genuinely portable

This part of the original is excellent and it maps cleanly onto a Yantra grid, because
`sheet.nim` exposes the colours as fields (`ink`, `grid`, `head`, `sel`, `bg`).

**Colour:**

| Meaning | Colour |
|---|---|
| hardcoded inputs and scenario levers | blue text `0,0,255` |
| formulas | black |
| links to another sheet | green `0,128,0` |
| links to another file | red `255,0,0` |
| key assumptions / cells the user fills in | yellow fill `255,255,0` |

**Numbers:**

- Currency `$#,##0`, with the unit named in the header (`Revenue ($mm)`).
- Zeros render as `-`, including in percentages: `$#,##0;($#,##0);-`.
- Negatives in parentheses.
- Percentages `0.0%`, **stored as fractions** — `0.15` renders `15.0%`; storing `15` renders
  `1500.0%`.
- Valuation multiples `0.0x`.
- Years as text (`"2024"`, never `2,024`).

**Structure:**

- Every assumption in its own labelled cell, referenced by the formulas that use it
  (`=B5*(1+$B$6)`, never `=B5*1.05`).
- Formulas consistent across every projection period — a lone edited cell mid-row is the
  commonest silent error.
- Guard denominators that can be zero.

In a Yantra sheet the assumption/formula split becomes an ordinary Nim closure — and the
`cell` callback is exactly the right place for it, because the "formula" is just Nim. This
one **compiles**:

```nim
import yantra
import std/strutils

proc money(v: float64): string =
  ## A currency cell: zeros as a dash, negatives in parentheses.
  if v == 0: "-"
  elif v < 0: "($" & $int(-v) & ")"
  else: "$" & $int(v)

proc Model() {.component.} =
  var growth = state(0.08)                 # the lever
  let revenue = 4000.0

  let sh = newSheet(yParent, rows = 40, cols = 5,
    cell = proc (r, c: int): string =
      if r == 0:
        return @["", "Base ($k)", "Growth", "Projected ($k)", "Multiple"][c]
      if c == 0: return "Q" & $r
      if c == 1: return money(revenue)                     # the assumption
      if c == 2: return money(growth.get * 100)
      if c == 3: return money(revenue * (1 + growth.get))  # the "formula" — just Nim
      # a ratio; `max(revenue, 1.0)` is the denominator guard
      return $int(revenue * (1 + growth.get) / max(revenue, 1.0) * 10) & ".0x")

  sh.ink = 0x0A84FF'u32                   # blue: this grid's numbers are computed
  sh.headInk = 0xFFB23E'u32               # amber headers
  sh.frozenRows = 1
  sh.frozenCols = 1
  sh.redraw()

  row(gap = 8, alignItems = center):
    text "growth", size = 14, color = 0xA0A0B0
    button "-":
      growth.set(growth.get - 0.01)
      sh.redraw()
    text @g "{int(growth.get * 100)}%", size = 14
    button "+":
      growth.set(growth.get + 0.01)
      sh.redraw()

app("Model", width = 760, height = 520, fill = 0x101015):
  column(gap = 12):
    Model()
```

Two honest limits of this sketch:

- **Per-cell colours are not available.** `ink`, `head`, `headInk`, `sel`, `bg` are
  grid-wide fields, not per-cell styles. So the original's blue-inputs / black-formulas
  convention needs one grid per role, or a custom grid drawn on a `canvas`.
- **`cell` is a plain proc, not an effect.** It does not subscribe to `growth`; the buttons
  call `sh.redraw()` themselves. If you want the grid to track a signal automatically, call
  `redraw` from a `createEffect` on that signal.

---

## 4. Getting data into the app

The app cannot open `/data/orders.csv`. Three honest paths:

**1. A file beside the app, read with the `files` capability.**

```nim
app("Orders", width = 900, height = 600, needs = files):
  column:
    let raw = readTextFile("orders.csv")
    case raw
    of FileResult(ok: true, data):
      text "{raw.data.splitLines().len} lines", size = 14
    else:
      text "could not read: {raw.error}", size = 14, color = 0xE5484D
```

`readTextFile` (`sdk/core/runtime.nim:78`) returns a `FileResult`; without the capability it
returns `CapabilityDenied("files", "permission denied")` rather than crashing. Capabilities
are declared with `needs files` — the set is `files`, `network`, `storage`, `notifications`
(`sdk/core/runtime.nim:27-31`).

**2. Fetch it.** `fetch("https://…/orders.csv")` — capability-gated, https only (plain http
only to localhost), and the host must be listed: `app("Orders", net = "api.example.com")`.
It returns a `Signal[Fetched]`; read `f.body`, check `f.ok`.

**3. The agent parses it host-side and writes a `.nim` data module next to the app.** For a
large or messy CSV this is the right answer: the messy cleanup happens in Python where
pandas is available, and the app ships a clean `seq[Row]`.

---

## 5. What is NOT SUPPORTED YET

| Capability | Status | Recommended path |
|---|---|---|
| Write an `.xlsx` from inside the app | **NOT SUPPORTED YET** | host-side `openpyxl`, then `recalc.py` |
| Read an `.xlsx` inside the app | **NOT SUPPORTED YET** | host-side `openpyxl`/`pandas` → write a `.nim` data module, or a CSV beside the app |
| Excel formula parsing and recalculation | **NOT SUPPORTED YET** | compute in the `cell` callback in Nim; `sdk/office/formula.nim` is an unmerged worktree |
| Cell-level formatting (bold, fills, number formats) per cell | **NOT SUPPORTED YET** | `sheet.nim` colours whole rows/headers as fields, not per-cell styles. Draw a custom grid on a `canvas` if you need it |
| Multiple named sheets / a workbook | **NOT SUPPORTED YET** | `newSheet` is one grid. Use a tab strip over separate grids, or a `canvas` |
| Column/row insertion and deletion | **NOT SUPPORTED YET** | set `rows`/`cols` and `redraw()`; no structural editing |
| CSV import with type inference | **NOT SUPPORTED YET** | parse in the `cell` callback, or host-side |

`docs/office.md` §3 sketches `sheet`, `table`, `col`, `cell`, `pivot`, `chart` and `query`
(DuckDB) as a proposal. **None of those keywords exist in the SDK today.** `sheet` as a DSL
statement does not parse — `sdk/ui/dsl.nim:440` raises `unknown node kind sheet`. Use
`newSheet`. Do not write code from the office doc.

---

## Dependencies

**Inside the app:** nothing extra — `newSheet` and `colName` are in `import yantra`.
**Host-side:** `openpyxl`, `pandas`, `markitdown` (pip), LibreOffice (`soffice`) for recalc.

## Provenance

Translated from Anthropic's `xlsx` skill (fetched from `anthropics/skills`, `skills/xlsx/SKILL.md`).
Section 1 was verified by reading `sdk/ui/sheet.nim` and compiling a program against it;
the compile errors quoted (the `window` proc vs `Node` mismatch, the `.component.` parent
parameter) are real and reproduced on purpose. Sections 2 and 3 are kept from the original
because the tool did not change — only where it runs.