---
name: yantra-pdf
description: "Use this skill whenever the user wants to do anything with PDF files — reading or extracting text and tables, merging, splitting, rotating, watermarking, creating new PDFs, filling forms, encrypting, extracting images, or OCR — or asks to produce a PDF at all. In Yantra it splits in two: producing a PDF (any .nim app writes `page`/`slide` nodes, and `yantra-pdf` exports them as real vector PDF pages with embedded fonts) and manipulating PDF bytes (pypdf/pdfplumber/qpdf, run host-side by the agent, never inside the sandbox). Use this skill for PDFs, not for Word documents, spreadsheets or slide decks."
license: Proprietary. Translated from Anthropic's `pdf` skill; see NOTICE.md.
---

# PDF in Yantra

**This is a translation, not a port.** Anthropic's `pdf` skill drives `pypdf`, `pdfplumber`,
`reportlab` and `qpdf` as agent-side tools. Yantra splits that world in two, and the split
matters more than anything else in this file:

| Half | Where it runs | What you use |
|---|---|---|
| **Creating** a PDF | inside the app | `page` / `slide` nodes + `yantra-pdf` — real, vector, text-selectable |
| **Manipulating** PDF bytes | host-side tool | `pypdf`, `pdfplumber`, `qpdf`, `pdftotext` — a normal script the agent runs |

## The rule that explains everything else

A Yantra app is a sandboxed WebAssembly module. It has **no filesystem, no Python, no
subprocess**. `sdk/core/runtime.nim` imports exactly these host calls: `yNodeCreate`,
`yNodeSet*`, `yStoreGet/Set`, `yFetch`, `yFileRead`, `yPickOpen/Save`. There is no `exec`,
no `popen`, no import of a Python library.

So: **the agent may absolutely run a Python script.** That runs on the agent's machine,
outside the app, exactly the way Anthropic's original skill intends. What it must not do is
pretend the sandboxed app can. A "Yantra docx skill" that says `import docx` inside an app
is fiction.

---

## 1. Creating a PDF — the part Yantra genuinely has

### The mechanism, verified

Two node kinds, both `nkPage` (kind 44, `sdk/core/wire.nim:50`), wired in `sdk/ui/dsl.nim:411`:

```nim
of "page", "slide":
  # a page of a document, or a 1280x720 slide of a deck: one PDF page each (D1)
  result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkPage", parentSym)))
  if name == "slide":
    result.add(newCall(newDotExpr(nodeSym, ident"width"), newLit(1280'i32)))
    result.add(newCall(newDotExpr(nodeSym, ident"height"), newLit(720'i32)))
```

`slide` is literally `page` with `width(1280)` and `height(720)` already set. A `page` has
**no default size — you must set both**, or it collapses.

On screen, `page`/`slide` nodes stack vertically like a scroll of sheets (`t_pdf.nim` asserts
`b1.y > b0.y + b0.h`). On export, the engine walks them in paint order and writes one PDF
page each at that node's own size — `Engine.pages` and `Engine.exportPdf`
(`render/native/engine.nim:4255-4291`).

### A complete, verified program

```nim
import yantra

app("Report", width = 900, height = 900, fill = 0xFFFFFF):
  page(width = 794, height = 1123, fill = 0xFFFFFF, pad = 60):   # A4 at 96 dpi
    column(gap = 18):
      text "Quarterly report", size = 40, weight = 800, color = 0x101015
      text "Prepared {today}", size = 16, color = 0x70707A

  page(width = 794, height = 1123, fill = 0xFFFFFF, pad = 60):
    text "Page two", size = 40, weight = 800, color = 0x101015
```

Export it:

```bash
bash tools/build-wasm.sh report.nim report.wasm
render/native/build/yantra-pdf.exe report.wasm report.pdf "Quarterly report"
```

### What the output is — measured, not assumed

I built and exported a two-page app and read the bytes back:

```
wrote verifydocsapi.pdf (2 pages)
/MediaBox [0 0 596 842]     <- the page(width=794, height=1123) -> A4
/MediaBox [0 0 960 540]     <- the slide -> 13.33 x 7.5 in, 16:9
FontFile: True              <- fonts embedded
ToUnicode: True             <- so selection and copy give back real characters
```

The scaling is `ptPerPx = 72/96` (`engine.nim:4253`), which is why 794×1123 px becomes
596×842 pt — A4 exactly. 1280×720 px becomes 960×540 pt — a standard 16:9 slide.

**The PDF matches the screen exactly**, because `exportPdf` calls the same `paintTree` the
screen does. Shapes stay vectors, text stays text. `t_pdf.nim` also asserts that drawing for
the file leaves the on-screen scroll position untouched.

### Gotchas, learned by compiling

- **A `page` with no `width`/`height` is a bug waiting to happen.** Unlike `slide`, nothing
  defaults it. Always write both.
- **A `page` at 96 dpi is a low-resolution page.** 794 px for A4 is correct *only* because
  `ptPerPx` scales it back up. Because the engine draws vectors, a `page` is resolution-
  independent anyway — what matters is that your px numbers are the *design* size.
- **Colours are `int`, not strings.** `fill = "#FFFFFF"` is a compile error:
  `type mismatch … proc setFill(n: Node; c: int)`. Write `fill = 0xFFFFFF`.
  Theme words (`bg`, `surface`, `accent`, `text`, `muted`) work bare and re-style live.
- **An app with no `page`/`slide` still exports** — the whole window becomes one page, sized
  to the window (`t_pdf.nim` checks a 360×300 counter app yields exactly 270×225 pt).
- **Export is host-side and deterministic.** `yantra-pdf` never captures the screen; it
  re-lays out and re-paints. Same `.wasm` in, same PDF out.

---

## 2. Manipulating PDFs — host-side, unchanged from the original

Everything in this section is a normal tool **you the agent run on the host**. It is
completely legitimate; it just is not inside the app.

### Reading text and metadata

```python
from pypdf import PdfReader
reader = PdfReader("document.pdf")
print(f"Pages: {len(reader.pages)}")
text = "".join(p.extract_text() for p in reader.pages)
meta = reader.metadata        # .title .author .subject .creator
```

For layout-preserving text, `pdftotext -layout in.pdf out.txt` is usually better than
`page.extract_text()`. For tables, pdfplumber:

```python
import pdfplumber
with pdfplumber.open("document.pdf") as pdf:
    for i, page in enumerate(pdf.pages):
        for j, table in enumerate(page.extract_tables()):
            print(f"page {i+1} table {j}:")
            for row in table: print(row)
```

### Merge, split, rotate

```python
from pypdf import PdfWriter, PdfReader

writer = PdfWriter()
for name in ["doc1.pdf", "doc2.pdf", "doc3.pdf"]:
    for page in PdfReader(name).pages:
        writer.add_page(page)
writer.write("merged.pdf")

reader = PdfReader("input.pdf")                      # split: one file per page
for i, page in enumerate(reader.pages):
    w = PdfWriter(); w.add_page(page); w.write(f"page_{i+1}.pdf")

writer = PdfWriter()                                 # rotate
page = PdfReader("input.pdf").pages[0]
page.rotate(90)
writer.add_page(page)
writer.write("rotated.pdf")
```

Same operations on the command line, when you would rather not write Python:

```bash
qpdf --empty --pages file1.pdf file2.pdf -- merged.pdf
qpdf input.pdf --pages . 1-5 -- pages1-5.pdf
qpdf input.pdf output.pdf --rotate=+90:1
qpdf --password=mypassword --decrypt encrypted.pdf decrypted.pdf
```

### Watermark, images, encryption

```python
watermark = PdfReader("watermark.pdf").pages[0]
writer = PdfWriter()
for page in PdfReader("document.pdf").pages:
    page.merge_page(watermark)
    writer.add_page(page)
writer.write("watermarked.pdf")
```

```bash
pdfimages -j input.pdf output_prefix     # → output_prefix-000.jpg, -001.jpg, …
```

```python
reader, writer = PdfReader("input.pdf"), PdfWriter()
for page in reader.pages: writer.add_page(page)
writer.encrypt("userpassword", "ownerpassword")
writer.write("encrypted.pdf")
```

### OCR

```python
import pytesseract
from pdf2image import convert_from_path
text = ""
for i, image in enumerate(convert_from_path("scanned.pdf")):
    text += f"Page {i+1}:\n" + pytesseract.image_to_string(image) + "\n\n"
```

### Two warnings from the original that still apply verbatim

- **Never use Unicode subscript/superscript characters** (₀₁₂₃, ⁰¹²³) in a generated PDF.
  Built-in fonts have no glyphs for them and they render as solid black boxes.
  In reportlab use the `<sub>` / `<super>` XML tags inside a `Paragraph`.
- **A PDF the runtime cannot evaluate is worse than a wrong number.** When you generate a
  PDF with a formula-driven chart, check the rendered page, not just the exit status.

---

## 3. Reading a PDF you did not create, into Yantra

An app cannot open a PDF and parse it — no `open()`, no `pypdf`. But it can hold data the
host prepared:

```nim
# Host-side, before running the app:
#   pdftotext -layout report.pdf report.txt
# The app then reads the text it was given.
let text = readTextFile("report.txt")     # needs the `files` capability
case text
of FileResult(ok: true, data): render text.data.splitLines()
else: text "could not read the file"
```

`readTextFile` returns a `FileResult` (`sdk/core/runtime.nim:78`) and returns
`CapabilityDenied("files", …)` if the app did not declare the capability. You declare it with
`needs files` inside the app body — `app(..., needs = files)` — see `sdk/core/runtime.nim:27-40`
(`files`, `network`, `storage`, `notifications`).

Or skip the file entirely and fetch it:

```nim
let doc = fetch("https://example.com/report.txt")   # app(..., net = "example.com")
text @body "{doc.get.body}"
```

`fetch` is capability-gated too, and only https (plain http only to localhost). See
`sdk/core/net.nim`.

**Recommended path for a PDF viewer inside Yantra: NOT SUPPORTED YET.** There is no PDFium
binding in the SDK, so an app cannot rasterise or paginate an arbitrary PDF. If you need
"open a PDF in my app", the honest options today are: (a) have the host extract text or
images and render *those*; (b) rebuild the document as a Yantra `page` tree from extracted
content — which also makes it editable and exportable, at the cost of layout fidelity.

---

## 4. Quality checks

This is the part of the original skill that carries over unchanged, and it carries over
*because* Yantra's PDF is drawn by the same engine as the screen — so what you see on
screen is what lands in the file.

1. **Render and look.** Do not declare a PDF done from the source code alone.
   `yantra-pdf` writes the file; open it and read every page.
2. **Text overflow is the first thing to check.** It is the most common defect and it is
   always user-visible. Reduce the size, split across pages, or enlarge the container.
3. **Check the page count.** `yantra-pdf` prints it: `wrote x.pdf (2 pages)`. A deck that
   should be 12 pages and is 3 means a `page` node is missing.
4. **Check the geometry.** A4 is `/MediaBox [0 0 596 842]`, a 16:9 slide is
   `/MediaBox [0 0 960 540]`. Anything else means the `page` size is wrong.
5. **Confirm the text is real.** `ToUnicode` present means selection works. If it is
   missing, the text was drawn as paths and the PDF is not searchable.
6. **Rebuild from source, never trust a stale `.wasm`.** Rule 2 of `AGENTS.md`. A stale
   artifact once hid an SDK that did not compile.

---

## 5. What is NOT SUPPORTED YET

Stated plainly, with the recommended path:

| Capability | Status | Recommended path |
|---|---|---|
| Render/parse an arbitrary PDF inside the app | **NOT SUPPORTED YET** | host-side `pdftotext`/`pdfplumber` → feed the app text or a Yantra `page` tree |
| Fill PDF forms (AcroForm) | **NOT SUPPORTED YET** | host-side `pypdf` (`PdfWriter.update_page_form_field_values`) |
| OCR inside the app | **NOT SUPPORTED YET** | host-side `pytesseract` |
| Merge/split/rotate inside the app | **NOT SUPPORTED YET** | host-side `pypdf` / `qpdf` — these are the normal tools anyway |
| Export a `.docx`/`.xlsx` from a `page` tree | **NOT SUPPORTED YET** | see the `yantra-docx` / `yantra-xlsx` skills |
| One PDF page per *screen*, A4 pagination with headers/footers | **NOT SUPPORTED YET** | `page` is an explicit, hand-sized box; it does not reflow. Compose the pages yourself, or use the Office roadmap (`docs/office.md` §4) |

`docs/office.md` is honest about this: page-layout features (automatic pagination,
widows/orphans, TOC, footnotes, cross-references) are listed under **"what no library gives
us (our own work, done test-first)"**. `page` today is a *box you author*, not a *flow that
paginates*.

---

## Dependencies

**Inside the app:** nothing extra — `page`/`slide` are in `import yantra`.
**Host-side:** `pypdf`, `pdfplumber`, `reportlab`, `qpdf`, `pdftotext` / `pdftoppm`
(Poppler), optionally `pytesseract` + `pdf2image`.

## Provenance

Translated from Anthropic's `pdf` skill (fetched from `anthropics/skills`, `skills/pdf/SKILL.md`).
Sections 1 and 3 are new, written from the Yantra source and verified by compiling and
exporting. Sections 2 and 4 keep the original's content because it is still correct — the
tool did not change, only where it runs.