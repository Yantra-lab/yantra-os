---
name: yantra-docx
description: "Use this skill whenever the user wants to create, read, edit or manipulate Word documents (.docx) or templates (.dotx), or asks for a professional document with a table of contents, headings, page numbers or letterhead — or wants to extract or reorganise content from a .docx, insert images, or find-and-replace inside one. Also use for a 'report', 'memo', 'letter' or 'template' delivered as a document. In Yantra a document is an app: write `page` nodes, and `yantra-pdf` exports them as real vector PDF pages. Producing a real .docx is a host-side docx-js job, not a sandboxed one."
license: Proprietary. Translated from Anthropic's `docx` skill; see NOTICE.md.
---

# DOCX / documents in Yantra

**This is a translation, not a port.** Anthropic's `docx` skill drives the `docx` npm
package, `pandoc`, LibreOffice and `pdftoppm` as agent-side tools. Yantra's document story
splits in two.

## The rule

| Half | Where it runs | What |
|---|---|---|
| **Authoring / viewing a document** | inside the app | `page` nodes + `yantra-pdf` — real vector pages, embedded fonts |
| **Emitting a real `.docx`** | host-side tool | `docx` (npm), `pandoc`, LibreOffice — the agent's machine |

The app sandbox cannot `require('docx')`, cannot `unzip`, cannot `zip`. A translated skill
that says "call `new Document()` from inside your Yantra app" is fiction, and this file
exists partly to say so out loud.

---

## 1. A document in Yantra — verified

### The mechanism

`page` and `slide` are the same node kind (`nkPage` = 44, `sdk/core/wire.nim:50`), wired at
`sdk/ui/dsl.nim:411`. `slide` is `page` with `width(1280)` and `height(720)` applied for you.
A bare `page` has **no default size** — you must give it both.

`Engine.exportPdf` (`render/native/engine.nim:4261`) walks the `page` nodes in paint order
and writes one PDF page each at that node's own size, using the same `paintTree` as the
screen. Geometry: `ptPerPx = 72/96`, so a `page` at `794 × 1123` px comes out at
`/MediaBox [0 0 596 842]` — A4 exactly. I built and exported such an app and read those
bytes back; `/FontFile` and `/ToUnicode` are both present, so the text is real, selectable
text.

### A complete document — A4, with a letterhead rule

```nim
import yantra

proc Head(title: string) {.component.} =
  column(gap = 6, padBottom = 18):
    text "ACME LTD", size = 12, weight = 700, color = 0x70707A
    text title, size = 40, weight = 800, color = 0x101015
    panel(height = 2, fill = 0x101015, marginTop = 10)   # a rule, not a table

proc Para(markup: string) {.component.} =
  rich markup, size = 15, color = 0x202028, lineHeight = 1.5

app("Offer letter", width = 900, height = 900, fill = 0xE8E8EE):
  # A4 at 96 dpi: 210 x 297 mm
  page(width = 794, height = 1123, fill = 0xFFFFFF, pad = 64):

    Head("Offer of employment")

    Para("Dear **Ada Lovelace**,")
    Para("")
    # a multi-line string concatenation does NOT parse inside a UI block — bind it first
    let offer = "We are pleased to offer you the role of *Analytical Engine Programmer*" &
                " at a CTC of **INR 1,20,00,000**, commencing 1 March."
    Para(offer)
    Para("")
    Para("Full particulars are at [the policy document](https://example.com/policy).")

    Para("")
    Para("Yours sincerely,")

  page(width = 794, height = 1123, fill = 0xFFFFFF, pad = 64):
    Head("Schedule A — terms")
```

I compiled exactly this and exported it:

```
wrote out/vdoc.pdf (2 pages)
/MediaBox [0 0 596 842]
/MediaBox [0 0 596 842]
```

Two A4 pages, real vector output.

export:

```bash
bash tools/build-wasm.sh letter.nim out/letter.wasm
render/native/build/yantra-pdf.exe out/letter.wasm out/letter.pdf "Offer letter"
```

Note: use a **relative** output path. An absolute `C:/…` path gets mangled by the MSYS bash
layer in `tools/build-wasm.sh` and the file lands in a stray `C:` folder.

### Rich text, because a document needs it

`sdk/ui/rich.nim` — `rich "Some **bold**, *italic*, `code`, ~~gone~~ and [a link](https://x.com)"`
is **one** Text node whose runs the engine styles with SkParagraph. One paragraph, wrapped as
a whole, selectable like any text.

Supported markup, exactly as `parseRich` implements it:

| Markup | Effect |
|---|---|
| `**bold**` | bold |
| `*italic*` or `_italic_` | italic |
| `` `code` `` | monospace |
| `~~struck~~` | strikethrough |
| `[text](url)` | underlined link in `linkColor`, clickable |
| `\x` | a literal `x` — the backslash escape |

`parseRich` returns `(plainText, seq[RichRun])`; nested marks are split into non-overlapping
pieces carrying both flags, because "runs must not overlap for the engine". A `\` escapes the
next character, and an unclosed mark stays literal text.

**Limit worth knowing:** `rich` is a *single paragraph*. It is inline markup, not block
structure — no `#` headings, no `-` lists, no `|` tables. For block-structured documents use
`sdk/ui/blocks.nim` instead (see below).

### Blocks — the closest thing Yantra has to a document model

`sdk/ui/blocks.nim` is "Notion-style blocks (Q6)": a `BlockDoc` is a `seq[Block]` in a
signal, with `BlockKind* = bkText, bkH1, bkH2, bkH3, bkBullet, bkNumbered, bkTodo, bkQuote,
bkCode`.

```nim
import yantra

proc Spec() {.component.} =
  blockEditor(yParent, newDoc(@[
    Block(id: 1, kind: bkH1,    text: "Design note"),
    Block(id: 2, kind: bkText,  text: "The problem, stated first."),
    Block(id: 3, kind: bkBullet, text: "Every app ships a browser engine."),
    Block(id: 4, kind: bkTodo,  checked: false, text: "Cut the weight by half."),
  ]))

app("Spec", width = 800, height = 900):
  Spec()
```

`newDoc(initial: seq[Block] = @[]): BlockDoc` is the constructor; it seeds the model.

It gives you markdown shortcuts as you type (`# `, `- `, `1. `, `[] `, `> `, ` ``` `),
Enter to split, Backspace to merge, arrows to move between blocks, undo/redo across blocks,
and drag-by-handle to move one. That is a real editing surface.

**But it is an editor, not a paginated document.** It has no page size, no margins, no
pagination, no headers/footers, no TOC. Those are the "our own work, done test-first" items
in `docs/office.md` §2. Do not claim them.

### Mail merge is just a loop

`docs/office.md` §4 sketches this, and it is the honest Yantra shape — you build the pages
from data, in the app, and export. This compiles and produces one page per candidate:

```nim
type Candidate = object
  name, role, ctc: string

let candidates = @[
  Candidate(name: "Ada Lovelace", role: "Analytical Engine Programmer", ctc: "INR 1,20,00,000"),
  Candidate(name: "Grace Hopper", role: "Compiler Architect",           ctc: "INR 98,00,000"),
]

app("Offers", width = 900, height = 900, fill = 0xE8E8EE):
  column(gap = 40, padY = 40, alignItems = center):
    for c in candidates:                    # a plain loop, not a word processor's merge field
      page(width = 794, height = 1123, fill = 0xFFFFFF, pad = 64):
        Head("Offer — " & c.name)
        let line = "Dear **" & c.name & "**, we are pleased to offer you the role of *" &
                  c.role & "* at a CTC of **" & c.ctc & "**."
        Para(line)
```

```
wrote out/vmerge.pdf (2 pages)
```

The page count in the exported PDF equals the number of candidates. That is the mail-merge
feature, and it works because a document is code. Note the DSL `for` takes one loop variable
(`dsl.nim:466`); `xs.keyed(x.id)` is available if the list is reactive and needs stable keys.

---

## 2. Gotchas, learned by compiling

- **Colours are `int`, not strings.** `fill = "#FFFFFF"` fails to compile:
  `type mismatch … proc setFill(n: Node; c: int)`. Write `fill = 0xFFFFFF`. Theme words
  (`bg`, `surface`, `accent`, `text`, `muted`, `line`) work bare and re-style live.
- **A `page` with no `width`/`height` collapses.** Unlike `slide`, nothing defaults it.
- **`.component.` procs take no parent parameter.** `proc Head(p: Node) {.component.}` makes
  the call site demand an extra argument; use the implicit `yParent`.
- **`window` is a proc, not a node.** Passing it to `blockEditor(window, …)` or
  `newSheet(window, …)` is a `type mismatch` — the DSL `window` is
  `proc (title: string; w, h: int32): Node`. Inside a `{.component.}` proc, use `yParent`.
- **Multi-line string concatenation does not parse inside a UI block.** Writing
  `Para("a long string "\n & "continued")` gives `expected: ')', but got: '&'`. Bind it to a
  `let` inside the block first, then pass the name.
- **One `app` block per module.** Two `app` calls give
  `redefinition of 'yantra_main'`.
- **Text nodes take `size`, not `fontSize`** (both work — `dsl.nim:212` maps them), and
  `weight = 800` for a display weight.
- **Rebuild from source before trusting output.** `AGENTS.md` rule 2: a stale `.wasm` once
  hid an SDK that did not compile.

---

## 3. Emitting a real `.docx` — host-side, unchanged

If the deliverable must open in Word, use `docx` (npm) on the host. The original's gotcha
list is reproduced because it is the difference between a document that opens in Word and
one that Word offers to "repair".

```js
const { Document, Packer, Paragraph, TextRun, HeadingLevel, PageBreak } = require("docx");
const doc = new Document({
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 } } },  // DXA; 1440 = 1 inch
    children: [
      new Paragraph({ text: "Title", heading: HeadingLevel.HEADING_1 }),
      new Paragraph({ children: [new TextRun({ text: "Body" })] }),
      new Paragraph({ children: [new PageBreak()] }),   // a PageBreak lives INSIDE a Paragraph
    ],
  }],
});
Packer.toBuffer(doc).then(b => require("fs").writeFileSync("out.docx", b));
```

The footguns, kept:

- **Page size defaults to A4.** For US Letter: `page: { size: { width: 12240, height: 15840 } }`.
- **Landscape:** pass portrait dimensions and `orientation: PageOrientation.LANDSCAPE` — the
  library swaps them internally.
- **Tables need dual widths** — `columnWidths` on the table AND `width` on every cell, both
  `WidthType.DXA`. `PERCENTAGE` breaks in Google Docs. Column widths must sum to the table
  width.
- **Table shading:** `ShadingType.CLEAR`, never `SOLID` (renders black).
- **Lists:** never insert `•` literally; use a `numbering` config with `LevelFormat.BULLET`.
- **`ImageRun` requires `type:`** (`"png"`, `"jpg"`, …).
- **`PageBreak` must be inside a `Paragraph`.**
- **Never use `\n`** — use separate `Paragraph` elements.
- **TOC:** headings must use built-in `HeadingLevel.*`; custom heading styles need
  `outlineLevel` set or they won't appear.
- **Don't use a table as a horizontal rule** — use a paragraph bottom border.
- **Dot-leader / right-aligned-on-same-line:** use `PositionalTab`
  (`alignment: PositionalTabAlignment.RIGHT`, `leader: PositionalTabLeader.DOT`) inside a
  `TextRun`, not literal `.` or space padding.

### Editing an existing document

```
unzip -q doc.docx -d unpacked/
find unpacked -type l -delete        # strip symlinks — an external .docx is untrusted
python scripts/merge_runs.py unpacked/   # coalesce fragmented runs so text is findable
# edit unpacked/word/document.xml IN PLACE — do not reformat or pretty-print
(cd unpacked && rm -f ../out.docx && zip -Xr ../out.docx .)
python scripts/office/validate.py out.docx --original doc.docx
```

Word splits text across many `<w:r>` runs (revision ids, spell-check markers), so a phrase
you can see in the document often does not exist as a contiguous string in the XML.
`merge_runs.py` merges adjacent identically-formatted runs without changing content or
rendering. Legacy `.doc` must be converted first.

### Tracked changes

Wrap runs in `<w:ins>`/`<w:del>` with `w:id`, `w:author`, `w:date`. Inside `<w:del>` the text
element is `<w:delText>`, not `<w:t>`. A deleted paragraph mark
(`<w:pPr><w:rPr><w:del .../></w:rPr></w:pPr>`) means "merge this paragraph into the next" —
so deleting a paragraph outright is that *plus* a `<w:del>` around every run. The `<w:del/>`
must come before the rPr's other children; their order is schema-enforced.

Validate redlines with `--author "<the name you redlined under>" --original <src>`: it reports
any text you changed without a `<w:ins>`/`<w:del>` around it, which is easy to do by accident
and invisible in the accepted view. To produce a clean copy with all changes accepted:
`python scripts/accept_changes.py in.docx out.docx`.

**Caveat that survives the translation:** both `pandoc --track-changes=accept` and
`accept_changes.py` strip the deleted text but leave the emptied paragraph behind, which reads
as a stray empty bullet when it was auto-numbered. Word itself joins the paragraphs. An empty
bullet in either view is an artifact of that view, not a defect in the document — check the
XML.

### Comments

Six cross-linked files: `comments.xml`, `commentsExtended.xml`, `commentsIds.xml`,
`commentsExtensible.xml`, the relationships, and the content-type overrides. Use the helper:

```bash
python scripts/comment.py unpacked/ "Fees & expenses cap is too low"
python scripts/comment.py contract.docx "This cap is too low" -o annotated.docx
```

It then prints the `<w:commentRangeStart>`/`<w:commentRangeEnd>`/`<w:commentReference>`
snippet to add to `word/document.xml` — **until you place those markers the comment exists
but is not visible.**

### Verify the output

```bash
python scripts/office/soffice.py --headless --convert-to pdf output.docx
pdftoppm -jpeg -r 100 output.pdf page
ls page-*.jpg        # then READ the images
```

`pdftoppm` zero-pads page numbers to the width of the page count (`page-01.jpg`…`page-12.jpg`).

---

## 4. Document quality — the part that carries over intact

Tool-independent, and the reason this translation is worth doing at all.

- **Look at the rendered pages.** Not the source. The most common defect in a document is
  text that overflows or collides, and it is invisible in code.
- **A heading that is not visually a heading.** In Word that is a missing `HeadingLevel`. In
  Yantra it is a `size` and `weight` that do not contrast with the body.
- **Structure before prose.** Decide the outline first, then write. The original's advice —
  custom styles need `outlineLevel` or they vanish from the TOC — generalises: if a heading
  does not carry an explicit level, structure downstream silently drops it.
- **Never fake a table with whitespace or a rule.** Use a real table or a real border.
- **Margins and measure.** The original's layout advice transfers: one consistent margin, one
  consistent gap, and body text that is not centred.

---

## 5. What is NOT SUPPORTED YET

| Capability | Status | Recommended path |
|---|---|---|
| Write a `.docx` from inside the app | **NOT SUPPORTED YET** | host-side `docx` (npm); or export the Yantra document to PDF, which is a better document anyway |
| Read/parse a `.docx` inside the app | **NOT SUPPORTED YET** | host-side `pandoc -t markdown file.docx`, then feed the app markdown |
| Automatic pagination, widows/orphans, footnotes, TOC, cross-references | **NOT SUPPORTED YET** | compose `page` nodes yourself; listed as own work in `docs/office.md` §2 |
| A `doc` / `sheet` / `deck` DSL statement | **NOT SUPPORTED YET** | `docs/office.md` §4's syntax is a **proposal**. `sdk/ui/dsl.nim:440` raises `unknown node kind doc`. Use `page` |
| Block-structured **rich** markup (`#`, `-`, `\|`) | **NOT SUPPORTED YET** | `sdk/ui/blocks.nim` (`blockEditor`) for an editable doc; `rich` is inline-only |
| Track changes, comments inside the app | **NOT SUPPORTED YET** | host-side docx XML surgery (§3) |
| Round-trip fidelity with Word | **NOT SUPPORTED YET** | `docs/office.md` §7 lists native docx import/export as future work behind LibreOfficeKit |

---

## Dependencies

**Inside the app:** nothing extra — `page` and `rich` are in `import yantra`.
**Host-side:** `docx` (npm), `pandoc`, LibreOffice (`soffice`), `pdftoppm` (Poppler),
`defusedxml` / `lxml` for XML surgery.

## Provenance

Translated from Anthropic's `docx` skill (fetched from `anthropics/skills`, `skills/docx/SKILL.md`).
The `page` mechanism, the A4 geometry, the rich-text markup table and the compile errors
quoted were verified against the source and by building an app. Section 3 keeps the
original's content because the tool did not change — only where it runs.