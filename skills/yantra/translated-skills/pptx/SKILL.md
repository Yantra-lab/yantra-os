---
name: yantra-pptx
description: "Use this skill any time a deck is involved — creating a slide deck or pitch deck, reading or extracting text from an existing .pptx/.potx, editing or updating a presentation, combining or splitting slides, or working with templates, layouts, speaker notes or comments. Trigger whenever the user mentions 'deck', 'slides', 'presentation', or a .pptx filename. In Yantra a deck is just an app: write `slide` nodes (1280x720), and `yantra-pdf` exports one real vector PDF page per slide. Producing a real .pptx file is a host-side pptxgenjs job, not a sandboxed one."
license: Proprietary. Translated from Anthropic's `pptx` skill; see NOTICE.md.
---

# PPTX / decks in Yantra

**This is a translation, not a port.** Anthropic's `pptx` skill drives `pptxgenjs` (npm) and
`python-pptx` as agent-side tools. Yantra's answer is different and, for decks, arguably
better: **a Yantra deck is a program.**

## The rule

| Half | Where it runs | What |
|---|---|---|
| **Authoring and viewing a deck** | inside the app | `slide` nodes, 1280×720, one PDF page each |
| **Emitting a real `.pptx`** | host-side tool | `pptxgenjs` / `python-pptx` — the agent's machine, not the sandbox |

The app sandbox cannot `require('pptxgenjs')`, cannot unzip, cannot zip, and has no
filesystem. Claiming otherwise is the failure mode this skill exists to prevent.

---

## 1. A deck in Yantra — verified, compiled, exported

### The mechanism

`sdk/ui/dsl.nim:411`:

```nim
of "page", "slide":
  # a page of a document, or a 1280x720 slide of a deck: one PDF page each (D1)
  kindCap = "Page"
  result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkPage", parentSym)))
  if name == "slide":
    result.add(newCall(newDotExpr(nodeSym, ident"width"), newLit(1280'i32)))
    result.add(newCall(newDotExpr(nodeSym, ident"height"), newLit(720'i32)))
```

A `slide` **is** a `page` with `width(1280)` and `height(720)` set for you. On screen the
slides stack top-to-bottom like a scroll of sheets. On export, `Engine.exportPdf`
(`render/native/engine.nim:4261`) writes one PDF page per slide node, at that node's size,
using the same `paintTree` as the screen — so shapes are vectors and text is selectable
text.

**Geometry, measured from real output:** `ptPerPx = 72/96`, so 1280×720 px →
`/MediaBox [0 0 960 540]` = 13.33 × 7.5 in. That is the standard 16:9 PowerPoint slide,
exactly. `t_pdf.nim` asserts this against `examples/docs/pitch.nim`.

### A complete deck

```nim
import yantra

proc Bullet(title, body: string) {.component.} =
  row(gap = 18, alignItems = start):
    panel(width = 10, height = 10, radius = 5, fill = 0xFFB23E, marginTop = 12)
    column(gap = 4, grow = 1):
      text title, size = 30, weight = 700, color = 0xF5F5F7
      text body, size = 22, color = 0xA0A0B0, lineHeight = 1.4

proc Tile(glyph, title, body: string) {.component.} =
  column(width = 340, gap = 12, pad = 28, radius = 20,
         fill = 0x15151B, border = 1, borderColor = 0x2A2A38):
    icon glyph, size = 34, color = 0xFFB23E
    text title, size = 28, weight = 700, color = 0xF5F5F7
    text body, size = 19, color = 0xA0A0B0, lineHeight = 1.4

app("Pitch", width = 1400, height = 860):
  column(gap = 40, padY = 40, alignItems = center):

    slide(fill = 0x101014, pad = 90, justify = center, gap = 22, radius = 6,
          shadow = shadow(y = 10, blur = 30, color = rgba(0x000000, 0.35))):
      panel(width = 90, height = 8, radius = 4, fill = 0xFFB23E)
      text "Yantra", size = 120, weight = 800, color = 0xF5F5F7
      text "One language for apps, documents and films.", size = 36, color = 0xA0A0B0

    slide(fill = 0x101014, pad = 90, gap = 34, radius = 6):
      text "The problem", size = 56, weight = 800, color = 0xF5F5F7
      Bullet("Every app carries a browser.", "A chat app ships its own engine.")
      Bullet("Five languages for one screen.", "HTML, CSS, JS, a framework, a build tool.")
      Bullet("Documents live elsewhere.", "The app cannot print or present what it shows.")

    slide(fill = 0x101014, pad = 90, gap = 40, radius = 6):
      text "What Yantra is", size = 56, weight = 800, color = 0xF5F5F7
      row(gap = 30, alignItems = stretch):
        Tile("shield", "Sandboxed", "Small wasm modules. One stops; others don't.")
        Tile("file", "Pages and slides", "The PDF is drawn by the screen's engine.")
        Tile("presentation", "Films", "Frame-exact render straight to video.")
```

This is `examples/docs/pitch.nim` in shape. I rebuilt it:
`build-wasm: wrote pitch_v.wasm (223907 bytes)`.

Export:

```bash
render/native/build/yantra-pdf.exe out/pitch.wasm out/pitch.pdf "Yantra — pitch"
# wrote out/pitch.pdf (3 pages)
```

### What Yantra gives you that pptxgenjs cannot

- **The deck is data.** `for s in slides:` builds slides. A pitch deck generated from live
  numbers is a loop, not a paste.
- **Live apps inside a slide.** `appView(source = "counter")` draws another sandboxed Yantra
  app inside a slide. No PowerPoint equivalent exists.
- **The deck is also a film.** `render/native/film.nim` renders any app frame-by-frame on an
  exact clock to H.264: `yantra-film intro.wasm intro.mp4 --seconds 6 --fps 60`. A deck that
  animates becomes a video of itself, with no screen capture and no PNG round-trip.
- **Reactive.** Slides recompute from signals. Change a number, every slide that used it
  updates.
- **Real PDF out.** Vector shapes, embedded fonts, `/ToUnicode` — selectable text.

### Gotchas, learned by compiling

- **Colours are `int`, not strings.** `fill = "#101014"` fails to compile:
  `type mismatch … proc setFill(n: Node; c: int)`. Use `fill = 0x101014`.
  Theme words (`bg`, `surface`, `accent`, `text`, `muted`, `line`) work bare.
- **A `.component.` proc takes no parent parameter.** Write `proc Tile(a, b: string) {.component.}`
  and use the implicit `yParent`. Declaring `proc Tile(p: Node)` makes the call site demand an
  extra argument.
- **Every slide needs both `size` and `weight` decided.** `text size = 56, weight = 800` is
  the difference between a title and body text. Default weights look like an accident.
- **Slides stack on screen with padding.** Wrap them in `column(gap = 40, padY = 40,
  alignItems = center)` or they touch. That padding is screen-only; it does not shrink the
  exported page.

---

## 2. Emitting a real `.pptx` — host-side, unchanged

If the deliverable must open in PowerPoint, use `pptxgenjs` on the host. The entire original
skill's gotcha list still applies verbatim; it is reproduced because it is correct and it is
the difference between a deck that opens and one that is silently corrupt.

```js
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";        // 13.3 x 7.5 in — SET BEFORE adding slides
const s = pres.addSlide();
s.addText("Title", { x: 0.5, y: 0.5, w: 12, h: 1, fontSize: 40, bold: true,
                     color: "F5F5F7" });        // no #, never 8 digits
s.addNotes("Speaker notes go here, not on the slide.");
pres.writeFile({ fileName: "out.pptx" });
```

The footguns from the original, kept because they are the ones that bite:

- **Set `pres.layout` before adding slides.** The default is `LAYOUT_16x9` = 10″×5.625″, not
  13.3″. Coordinates past the edge are written, not clamped — the shape just isn't there.
- **Hex colours: never `#`, never 8 digits.** `color: "FF0000"`. Both `"#FF0000"` and
  `"00000020"` corrupt the file. For translucency use `transparency: 0-100` on fills and
  images, `opacity: 0.0-1.0` on shadows.
- **pptxgenjs mutates option objects in place.** Never share one `shadow` object across two
  `add*` calls.
- **Shadow `offset` must be ≥ 0.** Negative corrupts the file. Cast upward with
  `angle: 270` and a positive offset.
- **`letterSpacing` is silently ignored.** The real option is `charSpacing`.
- **Lists:** `bullet: true` on each item, never a literal `•`. Set `breakLine: true` on
  every array item except the last. Space with `paraSpaceAfter`, not `lineSpacing`.
- **One `new pptxgen()` per output file.**
- **`rectRadius` only works on `ROUNDED_RECTANGLE`.**
- **Gradient fills aren't supported** — use a gradient image as the background.
- **Text boxes have built-in padding** — set `margin: 0` when text must align with a shape.
- **`PageBreak` / speaker notes** go in `addNotes`, never in a text box on the slide.
- **After `writeFile()`, validate.** `python-pptx` and LibreOffice will happily open a deck
  that PowerPoint calls corrupt. pptxgenjs emits bad chart XML specifically.

### Editing an existing deck

```
unzip → edit ppt/slides/slideN.xml → zip (from INSIDE the dir, rm the output first)
```

Do all structural work — add, delete, reorder — **before** editing any slide's content: a
duplicator copies a slide file verbatim, so duplicating after you edit clones your edits, and
the cleaner deletes any slide missing from `<p:sldIdLst>`, including one you just wrote.
Never copy a slide file by hand; `add_slide.py` does every registration a new slide needs.

If you script an XML transform, parse with `defusedxml.minidom` — round-tripping OOXML through
`xml.etree.ElementTree` rewrites namespace prefixes and corrupts the deck.

Legacy `.ppt` must be converted first with LibreOffice.

---

## 3. Design — the original's guidance carries over more or less intact

A Yantra deck is a native-rendered UI, so the *typographic* rules are the ones worth
keeping. The *font-availability* rules are not: Yantra draws with its own bundled fonts, not
whatever PowerPoint has, so "Arial renders true-to-width in LibreOffice but Georgia does not"
is a LibreOffice substitution problem that does not apply here.

**What still applies:**

- **Pick a bold, content-informed palette.** If swapping the colours into a completely
  different deck would still "work", you haven't made specific enough choices.
- **Dominance over equality.** One colour at 60-70% visual weight, 1-2 supporting tones, one
  sharp accent. Never give all colours equal weight.
- **Dark/light contrast.** Dark backgrounds for title and conclusion, light for content.
- **Commit to ONE visual motif** and repeat it — rounded image frames, icons in coloured
  circles. Carry it across every slide.
- **Every slide needs a visual element** — an icon, a chart, an image, a shape. Text-only
  slides are forgettable.
- **Don't repeat the same layout.** Vary columns, cards and callouts across slides.
- **Don't skimp on size contrast.** Yantra's equivalent of the original's 36-44pt title vs
  14-16pt body: `size = 56, weight = 800` for a title, `size = 22` for body. That is a 2.5×
  ratio, which reads instantly.
- **Don't centre body text.** Left-align paragraphs and lists; centre only titles.
- **Don't ship text that overflows its shape.** Reduce the size, split across slides, or
  enlarge the container.
- **Minimum margins.** The original says 0.5″; in a 1280×720 slide at 96 dpi that is ~48 px,
  and `pad = 90` (as `pitch.nim` does) is comfortably past it.
- **Choose one gap and use it.** `gap = 34` on one slide, `gap = 40` on another, reads as
  sloppiness.

**What does not apply:** the safe-font list, the Aptos warning, `letterSpacing`/`charSpacing`,
and every `addChart` option — none of them exist in the Yantra DSL.

### What does NOT apply, because Yantra draws it natively

- **NEVER use accent lines under titles.** This one *survives the translation* and gets
  stronger: the original calls it "a hallmark of AI-generated slides." In Yantra it is one
  line of `panel(width = 90, height = 8, radius = 4, fill = accent)` — cheap to add, cheap to
  overuse.
- **NEVER add decorative colour bars or accent stripes.** Header/footer bars spanning the
  slide width, vertical sidebar stripes, thin edges on cards. Same reasoning, same ban. If
  you want a card to read as a card, use `fill = surface, border = 1, radius = 20` — a tinted
  background and a soft corner, not a stripe.
- **Don't default to cream/beige.** Use white (`0xFFFFFF`) or a deliberate palette.

---

## 4. QA — required

Yantra's advantage: **the screen *is* the render.** There is no font substitution layer
between your code and the pixels. That makes QA cheap and exact.

```bash
bash tools/build-wasm.sh deck.nim out/deck.wasm
render/native/build/desktop/yantra_run.exe out/deck.wasm     # look at it
render/native/build/yantra-pdf.exe out/deck.wasm out/deck.pdf "Deck"
# wrote out/deck.pdf (7 pages)
```

Then inspect the PDF pages as images:

1. **Text overflow first.** Always. It is the most common defect and the most visible.
2. **Overlapping elements** — text through shapes, lines through words.
3. **Elements too close** (< ~30 px gaps) or uneven gaps.
4. **Insufficient margin** from slide edges.
5. **Low contrast** — dark text on a dark slide is invisible in a bright room.
6. **A slide that repeats the previous one's layout.**
7. **Leftover placeholder content** — "Lorem", "TODO", "xxx".

For a deck that came from a template, validate structurally too. If you built it in Yantra,
the equivalent check is simply the page count and a read of every page.

---

## 5. What is NOT SUPPORTED YET

| Capability | Status | Recommended path |
|---|---|---|
| Write a `.pptx` from inside the app | **NOT SUPPORTED YET** | host-side `pptxgenjs`; or export the Yantra deck to PDF, which is genuinely better as a document |
| Import a `.pptx` into a Yantra app | **NOT SUPPORTED YET** | host-side `soffice --convert-to pdf`, then read the text; or rebuild the slides as Yantra code |
| Speaker notes | **NOT SUPPORTED YET** | keep notes beside the deck; `addNotes` is pptxgenjs-only |
| Slide transitions / Magic Move | **NOT SUPPORTED YET** | `docs/studio.md` §4.3 lists `slide transition = magicMove` as roadmap (Phase S). Today: a separate app per slide, or `yantra-film` for a video |
| Presenter mode with timer | **NOT SUPPORTED YET** | roadmap, `docs/studio.md` |
| Native charts | **NOT SUPPORTED YET** | draw them in a `canvas` (`sdk/ui/paint.nim`) — this is real drawing, not an image |

`docs/office.md` §5 says PPTX import/export is planned "via LibreOfficeKit first, native
later". Neither has landed. Do not write code as if they have.

---

## Dependencies

**Inside the app:** nothing extra — `slide` and `icon` are in `import yantra`.
**Host-side:** `pptxgenjs` (npm), `markitdown[pptx]`, `python-pptx`, `defusedxml`, `lxml`,
LibreOffice (`soffice`), `pdftoppm` (Poppler).

## Provenance

Translated from Anthropic's `pptx` skill (fetched from `anthropics/skills`, `skills/pptx/SKILL.md`).
The `slide` mechanism, the geometry and the compiling example were verified against the
source and by building and exporting. The host-side `pptxgenjs` gotcha list and the design
rules are kept from the original, with an explicit note on which font rules no longer apply
and why.