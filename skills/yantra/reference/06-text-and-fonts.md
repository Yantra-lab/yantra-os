# Text and fonts

Ground truth for this chapter:

| File | What it decides |
|---|---|
| `protocol/props.md` (generated from `protocol/schema.nim`) | which text prop name is legal on which node kind |
| `protocol/wire.nim` + `sdk/core/wire.nim` | wire ids and types of every prop |
| `sdk/ui/dsl.nim` | what `size`/`weight`/`align`/`font` compile to; theme-word rewriting |
| `sdk/ui/rich.nim` | the `rich "…"` markup parser |
| `sdk/ui/theme.nim` | `Theme`, `theme()`, `setTheme`, `nextTheme`, `themeNames` |
| `sdk/ui/paint.nim` | `Draw.text()` and the canvas command list — **there is no `measureText` here (§5)** |
| `libs/nimskia/src/nimskia.nim` + `skia_shim.cpp` | what the renderer actually does with the text props — **including the `y` origin (§6); note the `drawText` doc comment at `nimskia.nim:76` is misleading** |
| `render/native/engine.nim` | defaults, the text→TextStyle mapping, layout, hit-testing |
| `docs/spec/style.md` §1, `docs/spec/core.md` §10 | the normative promise |

**Everything is one prop.** There is no stylesheet, no cascade, no `font-family` shorthand. A
value comes from the call site, a `style(...)` preset (`use = …`), or the engine's default.

---

## 1. Every text prop, exactly

Names, wire ids and node kinds come from `protocol/props.md`. Defaults come from
`render/native/engine.nim` (`fontSize`/`fontWeight`/`textStyle`, lines 385-398) — **an unset prop
has no default value in the SDK; the engine supplies it.**

| DSL prop | Wire id | Type | Allowed nodes | Default (engine) |
|---|---|---|---|---|
| `text` | `pText` | `string` | `Window,Text,Button,Input,Checkbox,Radio,Switch,TabPanel,Tooltip` | `""` |
| `label` | `pText` | `string` | `Checkbox,Switch,Radio` | — (alias of `text`) |
| `size` / `fontSize` | `pFontSize` | `int32` | `size`: `Text,Button,Input,TextArea,Window,Checkbox,Path`; `fontSize`: `Text,Button,Input,TextArea` | **15** px (`24` for `Path`) |
| `weight` | `pFontWeight` | `int32` | `*` | **400** (`600` for `Button`) |
| `font` | `pFontFamily` | `string` | `*` | engine stack (see §4) |
| `lineHeight` | `pLineHeight` | `float32` | `*` | `0` = the font's own; otherwise a **multiple** of the size |
| `italic` | `pItalic` | `bool` | `*` | `false` |
| `maxLines` | `pMaxLines` | `int32` | `*` | `0` = unlimited; `> 0` ellipsises with `…` |
| `color` / `textColor` | `pTextColor` | `int32` | `*` | ink `0xFFF5F5F7` |
| `align` | `pAlign` | `int32` | `Text,Column,Row` | `0` = left |
| `spans` | `pSpans` | `string` | `Text,TextArea,Input` | unset |
| `links` | `pLinks` | `string` | `Text` | unset |
| `inline` | `pInline` | `string` | `Text` | unset |

Notes that bite:

- **`size` is a length prop.** `sdk/ui/dsl.nim:92` lists `"size"` in `lengthProps`, so it goes
  through `lengthOf`. `size = 16.px` and `size = 16` both work; `size = 200.ms` is compile error
  **Y020**.
- **`lineHeight` is NOT in `lengthProps`, `durationProps` or `angleProps`.** It is written raw. It
  is a *multiple*, not px: `lineHeight = 1.45`, not `lineHeight = 24`. In the shim it becomes
  `TextStyle::setHeight` + `setHeightOverride(true)`.
- **`weight` is an integer CSS weight** handed straight to `SkFontStyle(weight, …)`. Any int is
  accepted; there is no enum and no "only 100..900" check.
- **`align` words** come from `sdk/ui/dsl.nim:156`: `left` 0, `center` 1, `right` 2. Also usable
  on `Column`/`Row` (where the engine aligns children, `pAlignItems` is the separate prop).
- **`color` vs `fill` on a Text.** `render/native/engine.nim:401-408`: for a `K_TEXT` node,
  `P_TEXTCOLOR` wins; a legacy `P_COLOR` on a Text is treated as its **ink**, not a background.
  `fillProp` returns false in that case, so `text "x", fill = 0x101010` does not paint a box —
  you want `panel` behind it.

Examples, all drawn from shipped apps:

```nim
text "Deck", size = 28, weight = 800, color = text, grow = 1          # examples/shell/todo.nim
text "{hint} ", size = 14, color = faint, font = theme().mono          # examples/shell/calc.nim
text "{display}", size = 44, weight = 300, color = text, maxLines = 1, font = theme().mono
text body, size = 17, color = muted, lineHeight = 1.45, maxWidth = 520 # examples/shell/deck.nim
text n.title, size = 14, weight = 600, color = text, maxLines = 1      # examples/shell/notes.nim
```

### Colour values are `0xAARRGGBB`, alpha first — and a CSS hex has no alpha byte

`color` / `textColor` / `fill` are `int32` wire values whose **top byte is alpha**
(`sdk/ui/style.nim:20`). A six-digit CSS hex pasted straight in therefore has alpha
`0x00`:

```nim
text "hello", color = 0xF7F9FB      # A = 0x00 ->  INVISIBLE, no warning anywhere
```

Unlike a `Draw` colour, a **node** colour is rescued by the engine:
`render/native/engine.nim:345-348` (`proc argb`) promotes a missing alpha byte,
`if (u and 0xFF000000) == 0: 0xFF000000 or u else: u`. So `fill = 0x101018` on a node is
opaque. The trap is still worth avoiding by hand — use `rgba`, or a `hex()` helper.

> **CORRECTED 2026-10-03.** This chapter previously showed raw hex colours with no mention
> of the alpha byte at all, and its `color` row (§1) listed a wire *id* and a *default* while
> implying the literal you paste in is the whole value. It is not: alpha is a **separate
> byte**, and everything that reads a colour (`ink` at `engine.nim:401-404`, `argb` at
> `engine.nim:345`, `paint.setColor` at `skia_shim.cpp:1327`) interprets the top byte as
> opacity.

**`rgba` has two signatures, and the SDK one is easy to misuse.**
`sdk/ui/style.nim:23` is `proc rgba*(rgb: int; alpha: float): int` — a **signed `int`**, a
packed `0xRRGGBB` **plus** an alpha float, with alpha clamped to `1..255`
(`style.nim:26`: `alpha = 0` comes back as `1`, "almost clear", deliberately distinct from
a plain opaque `0xRRGGBB`). Ports define their own
`proc rgba(r, g, b: int32; a: float32): uint32` (`apps/typewriter/app.nim:80`,
`apps/dna/app.nim:88`, `apps/gallery/app.nim:91`) and Nim resolves in favour of the port's.
**Reuse the port's; do not add a third definition.**

---

## 2. What `pSpans`, `pLinks`, `pInline` actually carry

All three are strings in a fixed mini-format. Exact formats, from `protocol/schema.nim:72,96,97`
and `libs/nimskia/src/nimskia.nim:101-103`:

| Prop | Format | Meaning |
|---|---|---|
| `spans` | `"start,end,flags,argb,size;…"` | byte ranges over the node's text. `flags`: `1` bold, `2` italic, `4` underline, `8` strike, `16` mono. `argb` 0 = inherit the text colour; `size` 0 = inherit. |
| `links` | `"start,end;…"` | byte ranges that are clickable. A `LinkClick` event says which index via `y_node_size(id, 10)`. |
| `inline` | `"w,h,path;…"` | one per `U+FFFC` in the text, **in order**. The paragraph gets a placeholder of that size; the engine draws the image into it. |

Worked example — `examples/shell/richtext.nim`, verbatim in shape:

```nim
n.set(pText, "Read the docs or go home \xEF\xBF\xBC now.")   # the U+FFFC is the inline slot
n.set(pLinks, "9,13;20,24")
n.set(pInline, "20,20,icon.png")
n.set(pSpans, "9,13,4,4284924159,0;20,24,4,4284924159,0")
n.on(evLinkClick, proc () = clicked.set(["docs", "home"][int(yNodeSize(int32(n.id), 10))]))
```

The link's colour/underline come from the span (flags `4`, argb). In the shim
(`skia_shim.cpp:186-201`) the span's `flags & 16` swaps the run to
`Cascadia Mono, Consolas, Segoe UI`; `flags & 1` sets weight 700; `size2 > 0` sets a run size.
**Nothing else in a span is honoured** — no per-run family, no letter-spacing, no baseline shift.

---

## 3. The DSL node kinds that carry text

From `sdk/ui/dsl.nim:305-311, 365-371, 372-385`:

- `text "…"` → `nkText`. `pText`.
- `button "…"` → `nkButton`. Default weight **600** (`engine.nim:386`).
- `input <signal>` / `textArea <signal>` → bound to a `Signal[string]` via `pValue`; the two-way
  binding is generated (`dsl.nim:377-385`). Placeholder is `placeholder`, prop `pPlaceholder`.
- `checkbox label` / `radio` / `switch` → the label is `pText`.
- `rich "…"` → an `nkText` whose text and spans come from `setRich` (`dsl.nim:365-371`).

`docs/spec/core.md` §10 **S-TXT-1/2**: inside a **string literal** in a UI block, `{expr}`
interpolates (`:fmt` supported, `{{`/`}}` literal). A string from a variable is **not**
interpolated — braces in user data show as typed. S-TXT-3: all text is UTF-8 and lengths,
caret positions and selections count **grapheme clusters**, never bytes.

---

## 4. Fonts: `font = …`, and what actually loads

`font` is `pFontFamily`, a plain string, the **name of a font family the OS already has**. There
is no font-file prop and no font-loading API anywhere in `sdk/` (see §5).

`sdk/ui/dsl.nim:168` adds two words, rewritten at compile time:

```nim
if norm == "font" and w in ["mono", "font"]: propVal = newDotExpr(newCall(ident"theme"), ident(w))
```

so `font = mono` becomes `theme().mono` and `font = font` becomes `theme().font` — the theme's
two family names, tracked, so they follow a theme switch. Both are `"Segoe UI"` / `"Consolas"` in
every built-in theme except **Terminal**, where `font` is also `"Consolas"`
(`sdk/ui/theme.nim:31-63`).

The family string reaches SkParagraph as the **first entry of a font stack**
(`skia_shim.cpp:139-142`):

```
named family  →  Segoe UI  →  Nirmala UI  →  Segoe UI Emoji
empty/unset   →             Segoe UI  →  Nirmala UI  →  Segoe UI Emoji
```

`g_fonts->collection->enableFontFallback()` is on — **`libs/nimskia/src/skia_shim.cpp:87`**,
inside the one-time font setup (`skia_shim.cpp:62-87`, where the collection is built and handed
the platform font manager at `:82`/`:85`). That is why an unknown family silently falls back
rather than failing. Weight and slant come from `pFontWeight` / `pItalic`:
`SkFontStyle(weight, kNormal_Width, italic ? kItalic_Slant : kUpright_Slant)`
(`skia_shim.cpp:143-144`).

Practical consequence: **an unknown `font = "Inter"` is not an error, it is Segoe UI.** This is
CLOSED in source, not eyeballed: `skia_shim.cpp:139-140` pushes the named family as the
*first* entry of the stack and `skia_shim.cpp:87` turns fallback on for that collection.

---

### 4a. ⚠️ `Draw.text` cannot name a typeface at all — only the node can

> **NEW 2026-10-04. Read this before §4, it is the same subject and the opposite answer.**

Everything in §4 above is about the **`text` node's `font` prop**. That path works: the
family string reaches SkParagraph as the first entry of a font stack.

**The `Draw.text` path has no such parameter, and this trips up almost everyone who
has just read §4.**

```
sdk/ui/paint.nim:63   proc text*(d: Draw; x, y, size; argb; s: string; weight = 400)
                                   ^^^ no family
skia_shim.cpp:1351   case 'T': ... yk_text_draw(..., col, 0);
skia_shim.cpp:141    if (!fam.empty()) ... else setFontFamilies({"Segoe UI", "Nirmala UI", ...})
```

`yk_text_draw2` at `skia_shim.cpp:318` **does** take a family — but only `T` calls
`yk_text_draw`, and `T` is the only text verb in `runCmds`. `host.nim`'s `importTable`
(`:1017-1066`) registers no `yk_*` symbol, so an app cannot reach it by import either.
**So a direct-draw string is always Segoe UI, and nothing in the app can change that.**

**This is not a cosmetic gap, and it is measurable.** On 070 the page asks for a serif
(`html:22` stacks Baskerville → Hoefler Text → Garamond → Palatino Linotype; the first
three are absent on a stock Windows box, so Chrome resolved Palatino) and the port
renders **Segoe UI, a sans**. Worth **~14,000 px** there and **~25,000 px** on 029.

**How to tell typeface error apart from everything else — do not assume it.** On 070
the error had been unattributed for three lanes, guessed at as antialiasing and as
position. The discriminator is an **IoU sweep**: binarise both images to ink masks,
shift the port over integer `(dx, dy)` in roughly ±4, and watch the best IoU.

* antialiasing / sub-pixel offset → **moves to IoU > 0.8** at some small shift
* wrong typeface → stays low (**0.29 measured**) **with the ink mass essentially equal**

Equal ink with disjoint shape is a different set of glyphs, not the same glyphs drawn
slightly differently. A second, cheaper check: the reference's inter-glyph run gaps have
a **non-zero standard deviation** (per-glyph advances); a uniform-advance model cannot
reproduce that, and its per-glyph start error will drift monotonically down the line.

**Open:** `DECISION_QUEUE.md` **D6** proposes `text(..., family = "")` plus a new verb
`N`, with a reviewed patch at `.board/aarate/proposed-d6-typeface.diff`. It is **not
landed** — it needs a `drive.exe` rebuild. Until it lands, treat per-square typeface
differences as a known, quantified, unreach-able gap and say so in your notes rather
than tuning positions to compensate.

---

## 5. What does NOT exist: no font files, and no measurement

This section is referenced from §4; it used to be missing from the chapter entirely.

**No font loading.** There is no `@font-face`, no `loadFont`, no font-file prop and no
font binary anywhere in `sdk/`. `font = …` is a family **name** that the OS must already
resolve. If the family is not installed, `enableFontFallback()` gives you Segoe UI and no
error — which means a port can look "almost right" with the wrong typeface and nothing
will tell you.

**No measurement, anywhere in the SDK.** There is no `measureText` proc to call, so:

* **Centring and right-alignment in a `Draw` list must be estimated.** `Draw.text`
  (`sdk/ui/paint.nim:63`) takes no `align` parameter and returns only a `Draw` — nothing
  about the width it needed. You cannot ask it how wide the string was.
* **Word wrapping must be estimated.** Same reason.
* A grep of `sdk/` for `measureText` / `textMeasure` / `measure` returns **zero procs**.

> **CORRECTED 2026-10-03.** Material that told you to "use the measurement API" or that a
> `measureText` was available to apps was wrong, and it sent people looking for a proc that
> has never existed. It exists **only on the native side**, wrapped for the engine:
> `libs/nimskia/src/nimskia.nim:68` (`measureText`, no `TextStyle`) and
> `libs/nimskia/src/nimskia.nim:122` (`measureText` taking a `TextStyle`); both call
> `yk_text_measure` / `yk_text_measure2` in `skia_shim.cpp`. Those wrappers live in the
> **native** module and are not part of the app-facing surface.

The correct rule: **if a text node does its own layout, let it.** The `text` node runs
through Yoga with real measured widths, so it centres and wraps correctly for free —
`reference/09-canvas-and-draw.md` §8 explains why. Estimate only when the string must sit
inside a `Draw` list, and then treat the estimate as an estimate.

## 6. Where text actually lands: the `y` origin

> ~~"`(x, y)` is the baseline left, not the top-left."~~
> ~~"`libs/nimskia/src/nimskia.nim:76`: Draws `s` with its top-left at `(x, y)`."~~
>
> **CORRECTED 2026-10-03.** The first line is wrong. The second is the SDK's own doc
> comment and is *half* right — which is exactly why it keeps being misread. `y` is the
> **top of the paragraph's line box**: not the baseline, and **not the ink top**. The shim
> passes `(x, y)` straight to `SkParagraph::paint` —
> `libs/nimskia/src/skia_shim.cpp:291`, `p->paint(static_cast<SkCanvas*>(c), x, y)` inside
> `yk_text_draw` — and `SkParagraph::paint` places `(x, y)` at the top-left of the
> paragraph **box**. "Top-left of the box" is not "top-left of the glyphs": the line box
> carries ascent above the cap height and descent below the baseline.

**The offsets are MEASURED, not documented.** From the requested `y`, in units of font
size `S`, measured at `S = 12`, `24` and `48`:

| Feature | Offset from `y` |
|---|---|
| cap / ascender ink top | `y + 0.375·S` |
| x-height top | `y + 0.583·S` |
| **baseline** | `y + 1.0833·S` |
| descender bottom | `y + 1.333·S` |

The two conversions worth memorising:

```nim
const BaselineK = 1.0833   ## yantra_y = wantedBaselineY - BaselineK * size
const CapTopK   = 0.375    ## CSS textBaseline:'top'  ->  yantra_y = Y - CapTopK * S
```

**Caveat, stated plainly: these ratios are EMPIRICAL — measured from rendered pixels for
the DEFAULT TYPEFACE AND DEFAULT WEIGHT ONLY.** They are whatever Segoe UI's metrics
resolve to through SkParagraph. Change the family, the weight, or `lineHeight`
(`skia_shim.cpp:145`) and they move. Do not treat them as an engine guarantee.

**This applies to node-level `text` too**, not just `Draw.text` — every one of
`render/native/engine.nim:1773`, `:1788`, `:1812`, `:1826`, `:1848`, `:1862`, `:1873`
calls `c.drawText(...)`, which lands in the same paragraph and the same `paint(x, y)`.
That is why a `Text` node's own layout already compensates, and why you must not
"correct" a node's `b.y` by hand.