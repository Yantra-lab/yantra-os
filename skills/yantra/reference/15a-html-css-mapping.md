# 15a — HTML/CSS → Yantra mapping

The complete property-by-property translation table. Every row is written as
`CSS | Yantra equivalent | Exact syntax | Notes/limits`.

**Sources verified for this chapter** (all read directly, not inferred):

| Source | What it fixes |
|---|---|
| `protocol/schema.nim` `PropTable` (lines 254–464) | The authoritative list of every DSL prop name, its wire prop, its wire type and the node kinds it is allowed on. **This is ground truth — if a prop is not in this table, it does not exist.** |
| `sdk/ui/dsl.nim` lines 86–246 | The DSL rewrites: `padX`→two edges, `margin*`→four edges, `fill`/`shadow`/`use`/`enter`/`exit`/`animate` special cases, the bare-word → enum maps (`alignItems`, `justify`, `cursor`, `align`, `fit`, `blend`, `ease`), the unit-prop lists, theme words and colour props. |
| `sdk/ui/units.nim` | `Px`/`Ms`/`Deg`, the `.px/.ms/.s/.secs/.deg` templates and the Y020/Y021/Y022 unit-mismatch errors. |
| `sdk/ui/style.nim` | `Gradient`, `Shadow`, `Style`, `rgba`, `linear`, `shadow`, `setFill`, `setShadow`, `applyStyle`, `sksl`. |
| `docs/spec/style.md` §§1–9 | The normative behaviour: props-are-the-model, interaction states, presets, themes, motion, effects, grid, long lists, container queries. |
| `render/native/engine.nim` `styleContainer`/`styleCommon`/`paintSurface`/`styleYoga` (lines 464–611, 1663–1700, 2195–2211) | What the engine actually honours: which Yoga calls are made, with what defaults, and the real paint order. |
| `sdk/yantra.nim` lines 109–174 | The imperative constructors: `grid`, `flex`, `stack`, `scrollArea`, `tabs`, `table`, `listView`, `treeView`, `chart`, `canvas`. |
| `apps/minipaint/PORT-NOTES.md` | Real port findings, quoted throughout. miniPaint is a full HTML/CSS app ported to Yantra, so its notes are the closest thing to field evidence that exists. |

**Two rules that make this table mostly mechanical:**

1. Yantra layout is **Yoga** (flexbox + grid). Anything Yoga supports, Yantra can express;
   anything CSS supports that Yoga does not (`float`, `clear`, `display: block`, multi-column,
   `table-layout`, floats, `shape-outside`) is `NOT SUPPORTED YET`.
2. Yantra paint is **Skia**. Anything Skia can draw, Yantra can express; the paintable set is
   a rectangle with a uniform corner radius, a solid or 2-stop linear gradient, one stroke, one
   drop shadow, and an optional SkSL shader. Everything else is a shader.

### How other chapters cite this one

Sibling files point at this chapter **by section number**, not by file line — file lines move
every time this table gains a row. The inbound references in the repo today, and where each one
lands:

| Cited from | The citation | Lands here |
|---|---|---|
| `reference/07-color-gradients-and-effects.md:17,610` | `§2.1-§2.5` | §2.1 Background → §2.5 `box-shadow` (contiguous, no §2.6 in between) |
| `reference/07-color-gradients-and-effects.md:639` | `§3 gradient table` | §3 Gradients |
| `reference/20-cloning-a-live-website.md:131` | `§6` rows `::before` / `::after` | §6, the `::before`/`::after` rows near the end of the selector table |
| `skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md:25` | `§2.4`, `§2.5`, `§3` | §2.4 Effects, §2.5 `box-shadow`, §3 Gradients |
| `reference/20-cloning-a-live-website.md:146` | `15a-html-css-mapping.md:589-590`, quoted | §6's opening rule (the "no stylesheets, selectors or cascades" quote). **The quoted line numbers are stale** — the quote now sits at the top of §6. Cite §6, not a line. |

**A stale inbound pointer, now fixed.** `skills/yantra/CHANGELOG.md:13` and
`skills/yantra/SKILL.md:89` both used to link to `15a-html-css-js-mapping.md`,
which **does not exist**. The file is `15a-html-css-mapping.md` (no "js"). Both
were corrected on 2026-10-03 and now resolve here. If you have an older checkout,
that is the file you are looking for.

---

## 0. The mental model in one table

| HTML/CSS concept | Yantra equivalent |
|---|---|
| A stylesheet | **There is none.** "There are no stylesheets, selectors or cascades: a value comes from the call site, a style preset (`use =`, `docs/spec/style.md` §3) or the engine's plain default." — `docs/spec/style.md` §1. The full selector translation is **§6** below |
| `.class { … }` | a `proc` returning `Style` (`style(fill = …, radius = …)`), applied with `use = s` |
| `<div class="card">` | `panel(use = card(), gap = 8)` |
| `id="hero"` | a `var` signal + conditional props, or `@handle` + `node.set(...)` |
| `<style>` block | a `const`/module-level `Style` or a themed signal |
| Inheritance of `color`, `font-*` | **None — nothing cascades, not even `color`.** Every one of `font`/`size`/`weight`/`italic`/`lineHeight`/`color` is read off the node itself; the engine never walks to a parent. `engine.nim:395-398` builds `textStyle(n)` from `n.sProp(P_FONTFAMILY)` / `n.flag(P_ITALIC)` / `n.num(P_LINEHEIGHT, 0)` only; `engine.nim:385-386` are `n.num(P_FONTSIZE, …)` and `n.num(P_FONTWEIGHT, …)`; `engine.nim:401-404` `ink(n, d)` falls back to the engine default `d`, not to a parent's ink. Set them on every text node, or wrap in a `{.component.}` proc. See §4.1 |
| `:root { --x }` | a `Theme` value + `theme()` reads (`docs/spec/style.md` §4) |
| CSS variable `--brand: #f00` used as `var(--brand)` | a `Theme` field: `fill = theme().accent` |
| `box-sizing: border-box` | the default (Yoga is border-box) — nothing to write |
| `<template>` / repeated markup | a `{.component.}` proc that calls `slot()` |
| `@media (min-width: …)` | `sized w, h:` block + `if w >= 640` (`docs/spec/style.md` §9.1) |

**Node-kind ladder.** `window` → `column` / `panel` (column) / `row` / `group` / `stack` /
`grid` / `scrollArea` / `panel`. Children are the block inside the colon.

| CSS you were going to write | Yantra node | Verified in |
|---|---|---|
| `<div>` (block, vertical children) | `column:` or `panel:` | `dsl.nim:302` — `column/row/panel/group` |
| `<div style="display:flex;flex-direction:row">` | `row:` | `dsl.nim:302`; `engine.nim:466` maps `K_ROW`→`fdRow`, everything else container-ish→`fdColumn` |
| `<div style="display:contents">` | `group:` | `engine.nim:620-622` — "A Group adds its children directly: it is invisible to layout" |
| `<div style="position:relative">` with overlapping kids | `stack:` | `dsl.nim:389-392` — "children overlap; each is placed by its own top/left/right/bottom" |
| `<div style="overflow:auto">` | `column(scroll = true)` | `engine.nim:489-493` |
| `<canvas>` | `canvas(draw = d.cmds, width = 400, height = 300)` | `dsl.nim:350-354` |
| `<svg>` | `path(d = "M…", size, color, stroke)` or `icon "search"` | `dsl.nim:393-403` |
| `<p>`/`<span>`/`<h1>` | `text "…"` (+ `weight = 600`, `size = 24`) | `dsl.nim:305-308` |
| `<button>` | `button "…"` | `dsl.nim:305-308` |
| `<input type=text>` | `input draft` (two-way bound to a `Signal[string]`) | `dsl.nim:372-385` |
| `<input type=checkbox>` | `checkbox:` | `dsl.nim:386-388` |
| `<dialog>`/overlay | `modal:`, `drawer:`, `popover:`, `menu:`, `contextmenu:` | `dsl.nim:310-321` — "overlays (OV1): a layer above the window, not in the page's layout" |
| `<span title="…">` tooltip | `tooltip "Copy link"` inside the node | `dsl.nim:322-328` |
| `position: fixed` header pinned to the window | `modal`/`drawer`/`popover` overlay, or a `row` outside the scroll area | `dsl.nim:310-321`; PORT-NOTES line 558 records the upstream `.menu_bar { position: fixed }` |

---

## 1. Layout

### 1.1 `display` — the container type is the node kind

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `display: flex` | a container node | `row:` / `column:` / `panel:` | Yoga node, children laid out |
| `display: flex; flex-direction: row` | `row:` | `row(gap = 8):` | `engine.nim:466` — `fdRow` for `K_ROW` only |
| `display: flex; flex-direction: column` | `column:` | `column(gap = 8):` | default for `panel`/`group`/`column` |
| `display: grid` | `grid:` | `grid "160 1fr 2fr", gap = 12:` | `dsl.nim:418-425`; `docs/spec/style.md` §9 |
| `grid` via the imperative API | `grid(parent, cols)` | `grid(parent, "1fr 1fr")` | `sdk/yantra.nim:111-114` — "`cols` is a grid-template-columns string" |
| `display: flex` with a direction string | `flex(parent, direction)` | `flex(parent, "row-reverse")` | `sdk/yantra.nim:116-119` — "reuses pSource for direction". `direction` accepts `"row" | "row-reverse" | "column" | "column-reverse"`. **Note the DSL has no `flex:` statement** — use `row:`/`column:` there, or the proc. |
| overlapping children | `stack:` | `stack: panel(top = 0, left = 0): …` | `engine.nim:512-519` — a node in a Stack is `ypAbsolute`, and with no inset it defaults to `top = 0, left = 0` |
| `position: relative` (no overlap needed) | `panel:` — relative is the default | `panel:` | Yoga default position type is relative; there is no `relative` prop to set |
| `display: block` | **NOT SUPPORTED YET** | — | Yoga has no block layout. Workaround: `column:` is the nearest thing (every child on its own line, stretch to the container width). **Fix difficulty: high** — it would need a new layout mode in the engine, not a prop. |
| `display: inline` | **NOT SUPPORTED YET** | — | `PropTable` has `inline` (wire `Inline`) but `allowedNodes: "Text"` only, and it is a *string* (rich-text markup), not inline layout. Workaround for inline layout: `row(alignItems = center, gap = 4)` with `shrink` on the items. **Fix difficulty: high.** PORT-NOTES line 1418 is the concrete port note: upstream's layer buttons are "`display: inline-block` with no float, so they form a 28px line box in the …" — the port had to build that rhythm by hand. |
| `display: inline-block` | **NOT SUPPORTED YET** | — | PORT-NOTES line 1718: `.radios label { display:inline-block; margin-right: 10px }` — the port had to reproduce this with explicit row + gap. Same fix difficulty: high. |
| `display: contents` | `group:` | `group: …` | `engine.nim:620-622` — invisible to layout, children go straight to the parent |
| `display: none` | `visible = false` | `panel(visible = false)` | `PropTable` `visible → pVisible`; `engine.nim:520` — `y.setDisplay(ydNone)` |
| `display: none` on a subtree | `visible = false` on the parent | `panel(visible = false)` | the subtree is removed from layout with it |
| `display: table` / `table-layout` | **NOT SUPPORTED YET** | — | Yoga has no table layout. Workaround: a `grid "…"` with explicit columns. PORT-NOTES lines 1752-1753 needed "two columns" for the guides dialog and got them from a grid, not from a table. **Fix difficulty: high.** |
| `float: left` / `float: right` | **NOT SUPPORTED YET** | — | Workaround: `row:` ordering, or `absolute = true` with `left`/`right`. PORT-NOTES line 1418 explicitly records this: the upstream layer buttons use `inline-block` "with no float". **Fix difficulty: medium** — Yoga genuinely has no float; `absolute` inside a `stack:` is the idiom. |
| `clear: both` | **NOT SUPPORTED YET** | — | Workaround: `spacer:` (`dsl.nim:430-433` — a spacer with no size gets `flexGrow = 1`). **Fix difficulty: medium.** |

### 1.2 Flex container

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `flex-direction: row` | `row:` | `row:` | |
| `flex-direction: column` | `column:` / `panel:` | `column:` | |
| `flex-direction: row-reverse` | **NOT SUPPORTED YET** in the DSL | `flex(parent, "row-reverse")` | the DSL's `row:` is fixed to `fdRow` (`engine.nim:466`). Only the imperative `flex` proc carries a direction. Workaround: reverse the order in the `for` that builds the row. **Fix difficulty: easy** — one prop (`pSource` is already reused). |
| `flex-direction: column-reverse` | same as above | `flex(parent, "column-reverse")` | same |
| `flex-wrap: wrap` | `wrap = true` | `row(wrap = true):` | `PropTable` `wrap → pWrap` (bool); `engine.nim:482` — `y.setFlexWrap(ywWrap)` |
| `flex-wrap: nowrap` | the default | (omit) | |
| `flex-wrap: wrap-reverse` | **NOT SUPPORTED YET** | — | Workaround: reverse child order. **Fix difficulty: easy.** |
| `justify-content: flex-start` | `justify = start` (or `first`) | `row(justify = start)` | `dsl.nim:154` — `justify` words: `first`/`start`=0, `center`=1, `last`=2, `between`=3, `around`=4, `evenly`=5. `engine.nim:474-481` maps 0→`yjStart`. |
| `justify-content: center` | `justify = center` | `row(justify = center)` | |
| `justify-content: flex-end` | `justify = end` (or `last`) | `row(justify = end)` | `engine.nim:477` — 2→`yjEnd` |
| `justify-content: space-between` | `justify = between` | `row(justify = between)` | 3→`yjSpaceBetween` |
| `justify-content: space-around` | `justify = around` | `row(justify = around)` | 4→`yjSpaceAround` |
| `justify-content: space-evenly` | `justify = evenly` | `row(justify = evenly)` | 5→`yjSpaceEvenly` |
| `align-items: flex-start` | `alignItems = start` (or `first`) | `column(alignItems = start)` | `dsl.nim:153` — `alignItems` words: `first`/`start`=0, `center`=1, `last`=2, `stretch`=3 |
| `align-items: center` | `alignItems = center` | `row(alignItems = center)` | |
| `align-items: flex-end` | `alignItems = end` (or `last`) | `row(alignItems = end)` | `engine.nim:471` — 2→`yaEnd` |
| `align-items: stretch` | `alignItems = stretch` | `column(alignItems = stretch)` | 3→`yaStretch` |
| `align-items: baseline` | **NOT SUPPORTED YET** | — | Workaround: `alignItems = end` and set `lineHeight` uniformly. **Fix difficulty: easy** — Yoga has `YGBaseline`. |
| `align-items` default on a `row:` | **`center`** | — | `engine.nim:473` — `elif k == K_ROW: y.setAlignItems(yaCenter)`. This is a CSS divergence: `display:flex` defaults to `stretch`. **Set `alignItems = stretch` explicitly to get CSS behaviour.** |
| `align-items` default on a `column:` | `stretch` (Yoga default) | — | matches CSS |
| `align-self` | **NOT SUPPORTED YET** | — | Not in `PropTable`. The engine calls `setAlignSelf` only internally, for a growing `Scene3D` (`engine.nim:591`). Workaround: wrap the child in a `row(alignItems = …)` — a one-item row makes the item's alignment a container property. **Fix difficulty: trivial** — add `PropMeta(dslName: "alignSelf", …)`; the renderer call already exists in the codebase's vocabulary. |
| `align-content` | **NOT SUPPORTED YET** | — | Only matters with `wrap`. Workaround: `justify` + `alignItems` on the wrapping container. **Fix difficulty: easy.** |
| `gap: 8px` | `gap = 8` (or `spacing = 8`) | `row(gap = 8)` | `dsl.nim:208-209` — both spellings set `Spacing`. `PropTable` allows `gap` on `Window,Column,Row,Panel,Group,Stack,Grid,Flex,Page` and `spacing` on `Column,Row,Grid,Flex` |
| `gap: 8` (a length prop) | `gap = 8.px` also legal | `row(gap = 8.px)` | `gap` is in `lengthProps` (`dsl.nim:91`) so `lengthOf` is applied |
| `row-gap` | **NOT SUPPORTED YET** | — | `engine.nim:484` — `y.setGap(gutterAll, gap)` sets all gutters to one value. Workaround: one `gap`, or nest two rows. **Fix difficulty: trivial.** |
| `column-gap` | **NOT SUPPORTED YET** | — | same as `row-gap` |
| `flex: 1` (grow 1, shrink 1, basis 0) | `grow = 1` | `panel(grow = 1)` | `engine.nim:503-506` — `grow` sets `flexGrow`, forces `flexShrink = 1`, and sets `minWidth`. Close but not identical to `flex: 1`: `flex:1` also zeroes the basis; Yantra does not (only for a scrolling `grow` node, `engine.nim:493`). |
| `flex: 1 1 0` with an exact basis | `grow = 1` on a `column(scroll = true)` | `column(scroll = true, grow = 1)` | `engine.nim:491-493` — "a scroll area that grows takes the space left, not its content's size", via `setFlexBasis(0)`. `docs/spec/style.md` §9.2 documents the same. |
| `flex-grow: 0` | omit `grow` | — | |
| `flex-shrink: 0` | `shrink = 0` | `panel(shrink = 0)` | `engine.nim:507` — note the default read is `1` when the prop is present |
| `flex-basis` | **NOT SUPPORTED YET** as a prop | — | Only set internally (engine.nim:493, 580). Workaround: an explicit `width`/`height`, or `grow` + `scroll`. **Fix difficulty: trivial** (add the prop + one `setFlexBasis`). |
| `order: 2` | **NOT SUPPORTED YET** | — | Workaround: reorder in the `for` loop that builds the children, or use `z` (which is paint order, not flow order). **Fix difficulty: trivial** — Yoga has `setOrder`. |
| `aspect-ratio: 16/9` | **NOT SUPPORTED YET** as a general prop | — | Two node kinds get an implicit aspect: `video` derives the missing side from the other's (`engine.nim:592-599`), and `image`/`video` fit via `fit`. Workaround: nest in a `stack` and set the width, or compute the height in Nim (`let h = w * 9 / 16`). **Fix difficulty: medium** — needs a measure function hook, not just a prop. |
| `box-sizing` | nothing to write | — | Yoga is border-box; `width` includes padding + border. Matches `border-box`. `content-box` is `NOT SUPPORTED YET`. **Fix difficulty: easy** (Yoga exposes `setBoxSizing`). |

### 1.3 Grid

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `display: grid` | `grid:` | `grid "160 1fr 2fr", gap = 12:` | `dsl.nim:418-425` |
| `grid-template-columns: 200px` | a pixel number in the string | `grid "200"` | `docs/spec/style.md` §9 — "a number is pixels (`200` or `200px`)" |
| `grid-template-columns: 1fr` | `1fr` | `grid "1fr 1fr"` | "`Nfr` is a share of what is left after pixels" |
| `grid-template-columns: 2fr` | `2fr` | `grid "160 1fr 2fr"` | "Shares never go below zero" |
| `grid-template-columns: auto` | `auto` | `grid "auto 1fr auto"` | "as wide as its widest item". PORT-NOTES line 72 is the real port of this exact declaration: "the third `auto` column of `grid-template-columns: auto 1fr auto` pinned to `right: 0`" |
| `grid-template-columns: repeat(3, 1fr)` | `repeat(3, 1fr)` in the string | `grid "repeat(3, 1fr)"` | `docs/spec/style.md` §9 — "`repeat(3, 1fr)` repeats" |
| `grid-template-rows` | **NOT SUPPORTED YET** | — | `docs/spec/style.md` §9: "**Not yet: explicit rows, row spans, and placing an item at a given column.**" Rows are implicit — items fill "row after row". **Fix difficulty: easy** — `fitGrids` already runs a second layout pass. |
| `grid-column: span 2` | `span = 2` | `banner(span = 2)` | `PropTable` `span → pSpan`; `docs/spec/style.md` §9 — "takes n columns … An item that doesn't fit in what is left of a row starts the next one" |
| `grid-row: span 2` | **NOT SUPPORTED YET** | — | same spec line. **Fix difficulty: easy.** |
| `grid-column-start` / `grid-area` | **NOT SUPPORTED YET** | — | same spec line. Workaround: reorder children + `span`. **Fix difficulty: medium** (needs a real placement pass, not just a prop). |
| grid `gap` | `gap = n` | `grid "1fr 1fr", gap = 12` | `engine.nim:607-608` — a Grid reads `pGridGap` first, then `pSpacing` |
| grid row alignment | automatic | — | `engine.nim:606` — a Grid defaults to `alignItems = stretch`: "Every item in a row is as tall as the row's tallest item", matching CSS `align-items: stretch` in a grid |
| grid item with its own width | works | `item(width = 90)` | `docs/spec/style.md` §9 — "An item with its own `width` keeps that width and still holds its cell" |
| nested grids | work | `grid "1fr": grid "1fr 1fr": …` | "Grids nest, and they follow the window when it resizes" |
| `repeat(auto-fill, minmax(200px, 1fr))` | **NOT SUPPORTED YET** | — | Workaround: `grid "repeat(3, 1fr)"` at a fixed count, or swap between two grids on a `sized` breakpoint (`docs/spec/style.md` §9.1). **Fix difficulty: medium.** |

### 1.4 Box sizing

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `width: 400px` | `width = 400` | `panel(width = 400)` | `dsl.nim:214-215` → `node.width(int32(v))`; `PropTable` `width → Width` (int32), `allowedNodes: "*"` |
| `width: 400px` (explicit unit) | `width = 400.px` | `panel(width = 400.px)` | `width` is in `lengthProps` so `lengthOf` runs; `units.nim:30` accepts a bare number or a `Px` |
| `height: 100%` | **NOT SUPPORTED YET** — no `%` unit | `height = <computed>` | Yantra lengths are `float32` pixels. A bare number *is* px; there is no percent. Workaround: `grow = 1` on the child and `grow = 1, scroll = true` on the container (the documented idiom, `docs/spec/style.md` §9.2), or compute the value from `sized w, h:`. **Fix difficulty: medium** — a percent needs a parent size, which Yoga can supply, but the wire prop is `int32`, so it needs a type change too. |
| `height: 100vh` | **NOT SUPPORTED YET** — no `vh`/`vw` | — | `units.nim` defines exactly three unit types: `Px`, `Ms`, `Deg`. `lengthOf(Ms)` and `lengthOf(Deg)` are *compile errors* (Y020). Workaround: read the window size — `window(width = …, height = …)` or a `sized w, h:` block. PORT-NOTES line 791 records the bug this caused upstream's own code: "`vh = 1000.0`, which made every zoom jump to the wrong place and made Fit Window …" **Fix difficulty: medium** — add `Vv`/`Vh` types and resolve against the window. |
| `min-width: 2.88rem` | `minWidth = 28.8` | `panel(minWidth = 28.8)` | PORT-NOTES line 1098: `.label_width_character { max-width: 2.88rem }` at `html{font-size:10px}` → 28.8px. **This is the actual port** — the rem was multiplied out by hand. |
| `max-width: calc(4.25rem + 2rem)` | `maxWidth = 62.5` | `input(maxWidth = 62.5)` | PORT-NOTES line 1099: the upstream rule `.input_cw_3 { max-width: calc(4.25rem + 2rem) }` became "42.5 + 20" px — the calc was evaluated at port time. **Yantra has no `calc()`.** |
| `min-height: 2.4rem` | `minHeight = 24` | `row(minHeight = 24)` | PORT-NOTES line 1097 — `.ui_input_group { min-height: 2.4rem }` → 24px |
| `max-height` | `maxHeight = n` | `panel(maxHeight = 300)` | `engine.nim:502` — `setMaxHeight` |
| `min-width` / `max-width` as a pair | both props, any order | `panel(minWidth = 120, maxWidth = 320)` | |
| `width: fit-content` | **NOT SUPPORTED YET** | — | A `text`/leaf measures itself (`engine.nim:455-462` — `measureLeaf`), and a `stack`/`row` shrinks to content by default. Workaround: don't set `width` on a text node; set it on a wrapping `row`. **Fix difficulty: medium.** |
| `width: max-content` | leave `width` unset on a leaf | — | leaves are measured; containers take the available size |
| `width: auto` | omit `width` | — | Yoga default |
| intrinsic sizing | measured | — | `measureLeaf` is registered via `y.setMeasureFunc` for `K_TEXT, K_BUTTON, K_CHECKBOX, K_INPUT, K_TEXTAREA` (`engine.nim:524, 630-633`) |
| `aspect-ratio` on a `video` | implicit | `video "clip.mp4", width = 320` | `engine.nim:597` — height derives from the source aspect when only width is set |

### 1.5 Positioning

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `position: relative` | the default | (nothing) | Yoga default is relative |
| `position: absolute` | `absolute = true` | `panel(absolute = true, top = 0, left = 0)` | `PropTable` `absolute → pAbsolute` (bool, `"*"`); `engine.nim:512-517` — sets `ypAbsolute` and applies the insets |
| `position: fixed` | **NOT SUPPORTED YET** | — | Workaround A: an overlay node — `modal:`, `drawer:`, `popover:`, `menu:`, `contextmenu:` — which `dsl.nim:310-321` describes as "a layer above the window, not in the page's layout". Workaround B: keep the bar *outside* the scrolling container. PORT-NOTES line 558 records upstream's `.menu_bar { position: fixed }` needing "to sit above the canvas and both panels", and line 609 records `position: fixed` submenus being ported as "each open level is its own box one `MENU_DD_MINW` further right". **Fix difficulty: hard** — a fixed element must survive ancestor scroll and clip, which means a separate layout pass. |
| `position: sticky` | `sticky = n` / `stickyLeft = n` | `row(sticky = 8)` | `PropTable` `sticky → pSticky` (float32, `"*"`), `stickyLeft → pStickyLeft` (float32). **Settled — both are px offsets, not switches:** `engine.nim:1075` computes `let top = max(clip.y, e.scrollY) + cn.num(P_STICKY, 0)` and `:1078` `let left = clip.x + cn.num(P_STICKYLEFT, 0)`, so the prop is *where inside the clip* the node parks. `engine.nim:2003` gives a sticky node `zIndex + 0.5` so it sorts above its siblings |
| `top: 10px` | `top = 10` | `panel(absolute = true, top = 10)` | `PropTable` `top → pInsetTop` (float32); `top` is in `lengthProps` so `10.px` is legal |
| `right: 10px` | `right = 10` | `panel(absolute = true, right = 10)` | `pInsetRight` |
| `bottom: 10px` | `bottom = 10` | `panel(absolute = true, bottom = 10)` | `pInsetBottom` |
| `left: 10px` | `left = 10` | `panel(absolute = true, left = 10)` | `pInsetLeft` |
| `inset: 10px` | all four | `panel(absolute = true, top = 10, right = 10, bottom = 10, left = 10)` | no shorthand prop exists; `engine.nim:514-517` applies each side only if it is present |
| `inset: 0` in a `stack` | implicit | `stack: panel: text "…"` | `engine.nim:518-519` — inside a Stack, a node with no vertical inset is placed at `top = 0`, and with no horizontal inset at `left = 0` |
| `z-index: 10` | `z = 10` | `panel(z = 10)` | `PropTable` `z → pZIndex` (int32, `"*"`) |
| `position: absolute` without insets inside a flex parent | use `stack:` | `stack: …` | `engine.nim:512` — being in a Stack is itself enough to make a node absolute; `absolute = true` is then redundant |
| `translate` for positioning | `x` / `y` | `panel(x = 10, y = 20)` | `PropTable` `x → pX`, `y → pY` (float32). `docs/spec/style.md` §1 lists these under **Transform**: "drawn moved; layout and hit testing keep the box" — so `x`/`y` do **not** reflow siblings |

### 1.6 Overflow and scrolling

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `overflow: auto` | `scroll = true` | `column(scroll = true)` | `PropTable` `scroll → pScroll` (bool); `engine.nim:489-490` — `y.setOverflow(yoScroll)` |
| `overflow: hidden` | `clip = true` | `panel(clip = true)` | `PropTable` `clip → pClip` (bool); `engine.nim:494` — `y.setOverflow(yoHidden)` |
| `overflow: visible` | the default | (nothing) | |
| `overflow-x` / `overflow-y` separately | **NOT SUPPORTED YET** | — | Yoga's `setOverflow` is a single enum; the engine calls it once. Workaround: nest — `panel(clip = true)` outside, `column(scroll = true)` inside. **Fix difficulty: hard** (Yoga is single-axis). |
| `overflow: scroll` (always-visible bars) | **NOT SUPPORTED YET** | — | `scroll = true` is `overflow: auto`, **not** `scroll`: it scrolls on wheel/drag but draws no bar. No scrollbar is rendered anywhere in the product. Searched the whole tree for `[Ss]crollbar` across `*.nim`/`*.cpp`/`*.c`/`*.h`/`*.js`/`*.mjs`: zero hits in `sdk/`, `render/`, `host/` or `libs/` — the only hits are app comments, Chrome's `--hide-scrollbars` CLI flag in a test script, and a vendored minipaint bundle. `apps/minipaint/app.nim:4340` independently calls it "what a scrollbar-less clipped list does". **Fix difficulty: hard** (a new drawn primitive). |
| `overflow: overlay` | **NOT SUPPORTED YET** | — | no overlay scrollbars |
| scrolling a scrollable box that fills the window | `column(scroll = true, grow = 1)` | `column(scroll = true, grow = 1)` | `docs/spec/style.md` §9.2 — "if some scroll area grows into the space left (`grow = 1, scroll = true`), the window is exactly its size and that area scrolls. Otherwise the page grows and the window scrolls" |
| scroll offset as a signal | `scrolled y:` | `column(scroll = true):` …`scrolled y: …` | `dsl.nim:591` — "the container's scroll offset as a signal (px)" |
| `scroll-behavior: smooth` | `smooth = true` | `column(smooth = true)` | `PropTable` `smooth → pSmooth` (bool, `"*"`). **Settled — it animates a *programmatic* scroll, and only after the first placement:** `engine.nim:1103` and `:1112` gate the jump with `cn.flag(P_SMOOTH) and e.placedOnce`, and `engine.nim:1500` is the animated-scroll branch. It does **not** smooth a wheel or trackpad drag |
| programmatic scroll to a y | `scrollTo = n` | `column(scrollTo = 240)` | `PropTable` `scrollTo → pScrollY` (float32) |
| scroll a list to its end (chat) | `stickToEnd = true` | `column(stickToEnd = true)` | `PropTable` `stickToEnd → pStickToEnd` (bool) |
| scroll-linked animation | `parallax = n` / `reveal = "…"` | `panel(parallax = 0.4)` | `PropTable` `parallax → pParallax` (float32), `reveal → pReveal` (string; `dsl.nim:199` — "played when scrolling into view"). `docs/spec/style.md` §7.x covers scroll-linked motion. |
| scroll to a keyed item | `scrollToKey = "id"` | `lazy m in items, 44: …` + `scrollToKey` | `PropTable` `scrollToKey → pScrollToKey` (string); `docs/spec/style.md` §9.2 (`[S-LAY-3]`) for the long-list model |
| `overflow: hidden` on a leaf | `clip = true` | `image("x.png", clip = true)` | `engine.nim:2211` — `let clipped = n.flag(P_SCROLL) or n.flag(P_CLIP)` applies clipping to the whole fx layer |

### 1.7 Margin

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `margin: 8px` | `margin = 8` | `panel(margin = 8)` | `dsl.nim:183-187` — expands to all four sides as float32; `engine.nim:508-511` |
| `margin: 8px 5px` (two values) | `marginY = 8, marginX = 5` | `panel(marginY = 8, marginX = 5)` | `dsl.nim:185` — `marginX` → Left+Right, `marginY` → Top+Bottom |
| `margin: 8px 5px 2px 0` | four props | `panel(marginTop = 8, marginRight = 5, marginBottom = 2, marginLeft = 0)` | `PropTable` `marginTop/Right/Bottom/Left` (float32, `"*"`) |
| `margin-top: 7.5px` | `marginTop = 7.5` | `panel(marginTop = 7.5)` | PORT-NOTES line 1101 — `.ui_input_grid.stacked { margin: .75rem 0 }` → 7.5px vertical |
| `margin: 0 5px` | `marginX = 5` with `margin = 0` | `panel(margin = 0, marginX = 5)` | PORT-NOTES line 72: upstream `.sidebar_right { margin: 0 5px; width: 200px }` — the port's whole bug was here |
| `margin-left: auto` (push right) | **NOT SUPPORTED YET** | — | `margin` is `float32` on the wire (`PropTable`: `marginTop` is `float32`), and `units.nim:29` has no `auto`. `margin = auto` would reach `lengthOf(auto)` and fail to compile. Workaround: put the item second in a `row(justify = between)`, or give the preceding sibling `grow = 1`. **Fix difficulty: easy** — Yoga has `YGAuto`; needs a `float32`→`auto` sentinel or a `marginAuto = true` prop. |
| `margin: auto` (centre both ways) | **NOT SUPPORTED YET** | — | Workaround: `row(justify = center, alignItems = center)` on the parent and no margin. **Fix difficulty: easy.** |
| logical `margin-inline` / `margin-block` | **NOT SUPPORTED YET** | — | `direction` exists (`PropTable` `direction → pDirection`, int32; `engine.nim:521-522` — `dirRTL`/`dirLTR`), so the *effect* is available, but there is no logical-margin prop. Workaround: write the physical side. **Fix difficulty: easy.** |
| negative margin | works | `panel(marginTop = -8)` | **Settled — Yoga honours it; nothing clamps the value.** The chain is `engine.nim:508-511` → `libs/nimyoga/src/nimyoga.nim:147` (`proc setMargin*(n: YogaNode; e: Edge; v: float32) = c_YGNodeStyleSetMargin(n.raw, cint(ord(e)), v)`) → `third_party/yoga/yoga-3.1.0/yoga/style/Style.h:145-147` `void setMargin(Edge edge, Style::Length value) { pool_.store(margin_[yoga::to_underlying(edge)], value); }` — stored verbatim. Yoga then treats margin as a **signed** float everywhere: `Style.h:424-429` `computeMarginForAxis` is a plain sum of the two edges, and the layout algorithm adds it algebraically. Two decisive lines: `yoga/algorithm/CalculateLayout.cpp:1289` `availableWidth - marginAxisRow` — a negative row margin *widens* the box, exactly as CSS does — and `CalculateLayout.cpp:1625-1628` `setLayoutPosition(node->style().computeFlexStartBorder(…) + child->style().computeFlexStartMargin(…), flexStartEdge(crossAxis))` — a negative leading margin moves the child backwards past the border. (Honest limit: no Yoga regression test covers a negative margin. The entire vendored `third_party/yoga/yoga-3.1.0` tree — `tests/generated/`, `unit_tests/`, `gentest/` — was searched for one and contains none. The evidence above is the layout code itself, read at `path:line`.) |
| `margin: 0` shorthand reset | `margin = 0` | `panel(margin = 0)` | |

### 1.8 Padding

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `padding: 12px` | `pad = 12` (or `padding = 12`) | `panel(pad = 12)` | `dsl.nim:210-211` — both spellings call `node.padding(int32(v))`; `PropTable`: `pad → PadTop` on `"*"`, `padding → PadTop` on `Window,Column,Row,Panel,Button,Input,Modal` |
| `padding: 12px 8px` | `padY = 12, padX = 8` | `panel(padY = 12, padX = 8)` | `dsl.nim:177-182` — `padX` → `pPadLeft` + `pPadRight`; `padY` → `pPadTop` + `pPadBottom` |
| `padding: 8px 4px 2px 4px` | four props | `panel(padTop = 8, padRight = 4, padBottom = 2, padLeft = 4)` | `PropTable`: `padTop/padRight/padBottom/padLeft` (int32, `"*"`) |
| `padding: 0` | `pad = 0` | `panel(pad = 0)` | |
| `padding: 1rem` | `pad = 16` | `panel(pad = 16)` | PORT-NOTES line 621 — the dialog's "1rem content padding" at `html{font-size:16px}`. `rem` is **not** a Yantra unit; multiply by hand. |
| `padding: 0 calc(--range-handle-width / 2)` | `padX = 0.8` | `slider(padX = 0.8)` | PORT-NOTES line 1102 — "track inset 0.8 each end", from a CSS custom property used inside a `calc()`. Both the var and the calc had to be resolved at port time. |
| logical `padding-inline` / `padding-block` | **NOT SUPPORTED YET** | — | same as logical margin |
| percentage padding | **NOT SUPPORTED YET** | — | padding is `int32` px; see the `%` row in §1.4 |

### 1.9 Media object fitting

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `object-fit: contain` | `fit = contain` | `image("a.png", fit = contain)` | `dsl.nim:157` — `fit` words: `contain`=0, `cover`=1, `fill`=2; `dsl.nim:169-171` also accepts the **strings** `"cover"`/`"fill"`/`"contain"` |
| `object-fit: cover` | `fit = cover` | `image("a.png", fit = "cover")` | both the bare word and the string work |
| `object-fit: fill` | `fit = fill` | `image("a.png", fit = fill)` | |
| `object-fit: none` / `object-position` | **NOT SUPPORTED YET** | — | `PropTable` `fit → pFit` is allowed on `Image,Video` only and has three values. **Fix difficulty: medium** (needs per-axis origin). |

---

## 2. Box & paint

**Paint order is fixed by the engine, not by z-index.** `engine.nim:1663-1664`:
"Shadow, then gradient or fill (with state styles), then border." Anything you add
(an SkSL shader, a border) slots into that order, and nothing else is reorderable.

### The alpha byte — read this before you write a colour constant

Two layers take colours, and **they disagree about a bare CSS hex**.

**Node props (`fill`, `color`, `borderColor`, `shadow(color = …)`) are SAFE with `0xRRGGBB`.**
`render/native/engine.nim:345-348`:

```nim
proc argb(v: int32): uint32 =
  ## Wire colour -> ARGB. 0xRRGGBB (no alpha byte) is opaque; rgba() sets the top byte.
  let u = cast[uint32](v)
  if (u and 0xFF000000'u32) == 0: 0xFF000000'u32 or u else: u
```

and `engine.nim:367-368` runs every colour read through it (`proc col` → `argb(n.iProp(p))`).
So `panel(fill = 0xEB5757)` is opaque white-ish red, exactly as CSS `#eb5757` reads. That is why
every bare hex below is written the way it is.

**`Draw` primitives inside a `canvas` are NOT.** Every `Draw` colour parameter is
`argb: uint32` in **AARRGGBB** and goes into the command string verbatim:

| Verb | Where the parameter is declared |
|---|---|
| `fill(argb)` | `sdk/ui/paint.nim:53` |
| `stroke(argb, width)` | `sdk/ui/paint.nim:55` |
| `rect(…, argb, …)` | `sdk/ui/paint.nim:57` |
| `circle(cx, cy, r, argb)` | `sdk/ui/paint.nim:59` |
| `line(…, argb, …)` | `sdk/ui/paint.nim:61` |
| `text(…, argb, …)` | `sdk/ui/paint.nim:63` |
| `image` | `sdk/ui/paint.nim:65` |
| `svgPath(…, argb, …)` | `sdk/ui/paint.nim:46` |

The shim hands the number straight to Skia — `libs/nimskia/src/skia_shim.cpp:1327`
(`paint.setColor(SkColor(argb))`) — with no normalisation. **A CSS hex pasted straight in
(`0xF7F9FB`) has alpha `0x00` and draws fully transparent.** It compiles, it runs, it crashes
nothing, and it is invisible. Measured on port #52: forcing the alpha bytes moved the frame from
100% differing to 23.7% in a single edit.

> **CORRECTED 2026-10-03.** What this chapter used to do — show bare CSS hex constants with no
> statement that they mean different things on the two layers. **The trap is not "hex is
> dangerous"; it is moving a colour that worked on a node into a `Draw` command list.** Evidence:
> `sdk/ui/paint.nim:53,55,57,59,61,63,65,46` declare `argb: uint32` with no coercion;
> `libs/nimskia/src/skia_shim.cpp:1327` calls `paint.setColor(SkColor(argb))` directly; only
> `render/native/engine.nim:345-348` normalises. **The correct rule, stated as a decision test:**
> *a row that maps a CSS colour onto a **node** prop is fine with a bare `0xRRGGBB`; a row or
> snippet that maps one onto a **`Draw`** call needs the `0xFF` forced, or the shape stops being
> drawn — silently, while everything still compiles and runs.* A hex that rendered correctly in a
> `panel` and then vanishes in a `canvas` is this bug, every time.

The safe pattern is a one-line helper that forces `0xFF`, exactly as a real port wrote it
(`apps/chess/app.nim:100`):

```nim
proc hex(h: int32): uint32 = 0xFF000000'u32 or (uint32(h) and 0xFFFFFF'u32)

d = d.rect(x, y, w, h, hex(0xF7F9FB))     # opaque — alpha byte forced to 0xFF
d = d.rect(x, y, w, h, rgba(0xF7F9FB, 0.4))  # or go through rgba() for a real alpha
```

**Do not add a second `rgba` for `Draw`.** See §2.2.

### 2.1 Background

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `background: #fff` | `fill = 0xFFFFFF` | `panel(fill = 0xFFFFFF)` | `dsl.nim:188-189` — `fill` calls `setFill`. `style.nim:34-36`: a plain colour also sets `pGradAngle = -1`, "a plain colour switches any gradient off". **The bare hex is safe here only because `engine.nim:345-348` forces the alpha byte to `0xFF`; the same literal inside a `canvas` `Draw` list is transparent — see the alpha byte box above** |
| `background-color: #fff` | `fill = 0xFFFFFF` | | `fill` is *the* background colour. There is no separate `background-color` |
| `background-color: rgba(0,0,0,.4)` | `fill = rgba(0x000000, 0.4)` | `panel(fill = rgba(0x000000, 0.4))` | `style.nim:23-27` — alpha 0..1; alpha 0 is clamped to 1 ("almost clear") so it stays distinguishable from an opaque `0x000000` |
| `background: transparent` | `fill = rgba(0x000000, 0)` | `panel(fill = rgba(0x000000, 0))` | `engine.nim:1686` — the fill is drawn only `if (f shr 24) != 0`; `rgba(…, 0)` clamps to 1, so this draws as 1/255 — effectively nothing, and it still occupies the box. For a truly absent background, omit `fill` (or `visible = false`) |
| `background: var(--brand)` | `fill = theme().accent` | `panel(fill = accent)` | bare theme words work: `dsl.nim:97-98` lists `bg sidebar surface surface2 surface3 line text muted faint accent accentText accentSoft danger success` |
| `background-image: url(bg.png)` | **NOT SUPPORTED YET** as a *fill* | — | A `fill` is a colour or a 2-stop gradient (`style.nim:7-10`). Workaround: an `image` node as the first child inside a `stack`, absolutely placed. **Fix difficulty: medium** — Skia has `drawImageRect`; the prop would be a new string prop plus a paint branch. |
| `background-size: 18px 12px` | set the `image` node's `width`/`height` | `image("i.png", width = 18, height = 12, fit = fill)` | PORT-NOTES lines 496-497: `.text:after { background-size: 16px auto }` and `.gradient:after { background-size: 18px 12px; filter: none }` — the port set the image node's box, and note the two per-icon overrides meant "a uniform 20x20 for every icon would be wrong" |
| `background-size: 20px 20px` (square) | `width = 20, height = 20` | `image("i.png", width = 20, height = 20, fit = fill)` | PORT-NOTES line 495 |
| `background-size: cover` | `fit = cover` | `image("i.png", fit = cover)` | `object-fit`, but it is the same knob |
| `background-size: contain` | `fit = contain` | | |
| `background-size: auto` | leave the side unset | `image("i.png", width = 16)` | `engine.nim:597` — for `video`, the missing side follows the source aspect |
| `background-position: center center` | **NOT SUPPORTED YET** | — | PORT-NOTES line 494 — `.sidebar_left .item:after { background-position: center center }`. Workaround: `fit = contain` inside a box of exactly the right size, which centres by construction. **Fix difficulty: medium.** |
| `background-repeat: repeat` | **NOT SUPPORTED YET** | — | Skia has `kRepeat`; no prop. Workaround: a `canvas` node that draws the tile, or an SkSL `shader`. **Fix difficulty: easy** for `repeat`, hard for correct tiling. |
| `background-repeat: no-repeat` | the only behaviour | — | |
| `background-repeat-x/y` | **NOT SUPPORTED YET** | — | |
| `background-clip` | **NOT SUPPORTED YET** | — | Clip is implicit in the node's `radius`: `engine.nim:1686` uses `fillRRect` (or `shaderRRect`), so the fill is always clipped to the rounded rect. There is no separate clip box. **Fix difficulty: medium** (needs a clip-path renderer). |
| `background-clip: text` | **NOT SUPPORTED YET** | — | Workaround: draw the glyphs with `fill = accent` (`text`), or an SkSL shader with the glyph as a mask — Skia can do this but no prop exposes it. **Fix difficulty: hard.** |
| `background-origin` | **NOT SUPPORTED YET** | — | padding-box and border-box coincide in Yoga's border-box model, so this is usually a no-op; the real distinction (background-clip) is above. **Fix difficulty: medium.** |
| `background-attachment: fixed` | **NOT SUPPORTED YET** | — | Workaround: `parallax` / a `scroll`-driven signal, or `backdropBlur`-style content. **Fix difficulty: hard.** |
| multiple backgrounds | **NOT SUPPORTED YET** | — | one `fill` per node. Workaround: one `stack:` child per background layer, absolutely positioned. **Fix difficulty: medium.** |

### 2.2 Colour and opacity

> **`rgba` is defined twice, with two different signatures. Reuse the port's; do not add a third.**
>
> - `sdk/ui/style.nim:23-27` — `proc rgba*(rgb: int; alpha: float): int`. Signed `int`, a packed
>   `0xRRGGBB` plus a float alpha; line 26 does `clamp(int(alpha * 255 + 0.5), 1, 255)`, so
>   **alpha 0 can never mean fully clear** — it becomes 1/255 "almost clear".
> - the app-local `proc rgba(r, g, b: int32; a: float32): uint32` that ports define, e.g.
>   `apps/chess/app.nim:96-98`, which packs **AARRGGBB** and lets alpha reach 0.
>
> Nim picks the local one inside a module that declares it, so the same call can mean different
> things in two files of the same app. `rgba(0x000000, 0)` is "1/255 opaque" under the SDK's and
> "fully transparent" under a port's. **Name the port's helper something else** (`argb`, as chess
> does) so a reader can tell which one they are looking at, and keep exactly two.

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `color: #333` (text ink) | `color = 0x333333` | `text "Hi", color = 0x333333` | `PropTable` `color → pTextColor` (int32, `"*"`), commented in `schema.nim:272` — "ink: text, icons, labels". Distinct from `fill`, which is the box. Safe as a bare hex: `engine.nim:345-348` forces the alpha byte |
| `color: inherit` | pass the parent's colour down | — | there is no cascade at all — the rule and the preset mechanism are in **§6**, not §4 |
| `opacity: 0.5` | `opacity = 0.5` | `panel(opacity = 0.5)` | `PropTable` `opacity → pOpacity` (float32, `"*"`); `engine.nim:2202` folds it into the fx layer's `alpha` |
| `opacity` on a subtree | `opacity` on the parent | `panel(opacity = 0.5)` | the whole node plus its subtree goes through one layer (`docs/spec/style.md` §8: "the engine draws the node (and everything in it) through one layer") |
| `color: rgba(r,g,b,a)` | `rgba(0xRRGGBB, a)` | `fill = rgba(0x3B82F6, 0.25)` | there is no `rgb()`/`hsl()`/`color()` function — `style.nim` exports `rgba` only. **Settled:** `grep` for `proc rgb*` / `proc hsl*` / `proc oklch*` / `proc hex*` across `sdk/` returns **no other colour function at all**. Precompute the hex |
| `hsl()` / `oklch()` / named colours | **NOT SUPPORTED YET** | — | Workaround: precompute the hex. PORT-NOTES lines 1063-1076 show how much work a colour conversion is: hue rotation had to produce `#008000 → #800000 / #808000 / …` "reports lightness 25, and its hue gradient is …" — i.e. converted by hand, per value. **Fix difficulty: easy** (a `hsl(h,s,l)` proc, compile-time). |
| `#RRGGBB` / `#RGB` | `0xRRGGBB` only | `fill = 0xEB5757` | `style.nim:8` — colours are ints. Three-digit `#abc` must be expanded by hand. Safe bare, **on a node prop only** (`engine.nim:345-348` forces `0xFF`); in a `Draw` list the same literal is alpha 0 and invisible — see the alpha byte box at the top of §2 |
| currentColor | **NOT SUPPORTED YET** | — | use the same expression for `fill` and `color` |

### 2.3 Borders

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `border: 1px solid #ccc` | `border = 1, borderColor = 0xCCCCCC` | `panel(border = 1, borderColor = 0xCCCCCC)` | `PropTable`: `border → BorderWidth` (int32), `borderColor → BorderColor` (int32). `style.md` §1 groups them under **Surface**. |
| `border: 1px` | `border = 1` | `panel(border = 1)` | the colour defaults to the engine's `Line` (`engine.nim:1688`) |
| `border-width: 2px` | `border = 2` | `panel(border = 2)` | one width for all four sides |
| `border-top` / `-right` / `-bottom` / `-left` | **NOT SUPPORTED YET** | — | `engine.nim:1687-1690` — `let bw = n.num(P_BORDER_WIDTH, 0)` then one `strokeRRect(…, bw, colour)`. There is no per-side prop. Workaround: an inner `panel` with only the widths you need, or four nested boxes. **Fix difficulty: medium** — Skia's `strokeRect`/`drawLines` can do per-side strokes; it needs four int32 props and a paint branch. |
| `border-style: dashed` | **NOT SUPPORTED YET** | — | `strokeRRect` takes a single width. Workaround: a `canvas` node drawing dashes, or an SkSL `shader`. **Fix difficulty: easy.** |
| `border-style: dotted` | **NOT SUPPORTED YET** | — | same |
| `border-color` per side | **NOT SUPPORTED YET** | — | as per-side width |
| `border-color: transparent` | `borderColor = rgba(0x000000, 0)` | `panel(border = 1, borderColor = rgba(0x000000, 0))` | PORT-NOTES line 1105 — the real dark-theme values were `--input-border-color #0f0f0f`, `--border-color #727677`; a 1px `--input` border is part of the `.ui_range` track ("track 18 tall, 1px border", line 1100) |
| `border-radius: 8px` | `radius = 8` | `panel(radius = 8)` | `PropTable` `radius → Radius` (int32, `"*"`); `radius` is in `lengthProps`, so `8.px` is legal too |
| `border-radius: 50%` (circle) | `radius = <half the smaller side>` | `panel(width = 32, height = 32, radius = 16)` | radius is a plain int, so compute it |
| `border-radius` per corner (`8px 0 8px 0`) | **NOT SUPPORTED YET** | — | `engine.nim:1686` — one `radius` for the whole rect (`fillRRect`). Workaround: an SkSL shader, or a `canvas`. **Fix difficulty: medium** — Skia has `RRect` with per-corner radii. |
| elliptical radii (`50% / 20%`) | **NOT SUPPORTED YET** | — | needs `SkRRect` with (x,y) radii |
| `outline: 2px solid #f00` | **NOT SUPPORTED YET** | — | no outline paint path; `engine.nim:1670-1679` returns early after the shader, so an outline cannot be layered on top there. Workaround: an absolutely positioned sibling with a 2px larger box and the page colour behind it, or `hover: borderColor = …`. **Fix difficulty: easy** — one more stroke pass. |
| `outline-offset` | **NOT SUPPORTED YET** | — | same workaround (the padding-box trick) |
| `border-image` / `border-image-slice` | **NOT SUPPORTED YET** | — | PORT-NOTES lines 504-510 is the honest note on the same problem for icons: SVG `matrix()` transforms were resolved with "the transforms **baked into the coordinates** — dropping them would place every icon wrongly. Unsupported constructs raise rather than silently emitting bad artwork". For border images, the workaround is nine sliced `image`/`path` children. **Fix difficulty: hard.** |
| `box-shadow` | `shadow = shadow(...)` | see §2.5 | |
| border inside the box | always | — | Yoga is border-box; `width` includes padding and border |

### 2.4 Effects: filter, backdrop, blend

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `filter: blur(4px)` | `blur = 4` | `panel(blur = 4)` | `PropTable` `blur → pBlur` (float32, `"*"`); `engine.nim:2195-2202` — `saveFx(…, Fx(blur: …))`. `docs/spec/style.md` §8: `text "Glow", color = accent, blur = 22.px` — "blur of the node itself" |
| `filter: brightness(1.2)` | `brightness = 1.2` | `panel(brightness = 1.2)` | `pBrightness`; 1 = unchanged (`docs/spec/style.md` §8) |
| `filter: contrast(1.1)` | `contrast = 1.1` | `panel(contrast = 1.1)` | `pContrast`; 1 = unchanged |
| `filter: saturate(0)` | `saturate = 0` | `panel(saturate = 0)` | `pSaturate`; the spec's own example is `panel(saturate = 0, brightness = 1.2, contrast = 1.1)` |
| `filter: saturate(1.5)` | `saturate = 1.5` | `panel(saturate = 1.5)` | the value is a multiplier like CSS, not a percent |
| `filter: hue-rotate(90deg)` | **NOT SUPPORTED YET** as a prop | — | `PropTable` has `saturate`, `brightness`, `contrast`, `blur` — and nothing else in the `filter` family. Workaround: an SkSL `shader`. **Fix difficulty: easy** — Skia has `SkColorFilters::Matrix`, and `engine.nim` already builds fx layers. PORT-NOTES lines 638-640 show the arithmetic that a hue-rotate requires if done manually ("Grayscale (92, 92, 92) / 0.7152*128 = 91.52 → 92"), and lines 648-651 show the trap: "Channel aliasing in saturate. Assigning `r`, then `g`, then `b` in place makes each matrix row consume the already-rewritten channels of the rows before it." A matrix filter must read the originals through temporaries. |
| `filter: sepia(0.6)` | **NOT SUPPORTED YET** as a prop | — | PORT-NOTES line 639: "Sepia (60) → (59, 104, 41) — the sepia matrix at 60%", measured on a real framebuffer through the menu. The *app* implemented the matrix by hand; the engine has no `sepia` prop. **Fix difficulty: easy.** |
| `filter: grayscale(1)` | **NOT SUPPORTED YET** as a prop | — | PORT-NOTES line 637 — measured `(92, 92, 92)` from `0.7152*128 = 91.52`. **Fix difficulty: easy.** |
| `filter: invert(1)` | **NOT SUPPORTED YET** as a prop | — | PORT-NOTES line 518 is the real-world use: `--menu-icons-filter: invert(1)` — "The SVGs are authored **black on transparent**, so `invert(1)` is what makes them visible at all; drawing them unmodified renders black-on-dark." PORT-NOTES line 497 records the paired `filter: none` on `.gradient:after`. Workaround: swap the source icon, or an SkSL shader. **Fix difficulty: easy.** |
| `filter: opacity(0.5)` | `opacity = 0.5` | `panel(opacity = 0.5)` | identical effect, first-class prop |
| `filter: drop-shadow(2px 2px 4px #000)` | **NOT SUPPORTED YET** | — | no filter list at all — see `filter: url(#f)` below. Workaround: `shadow = shadow(2, 2, 4, 0x000000)`. **Fix difficulty: medium** — a true drop-shadow follows the alpha silhouette, which for a rounded rect means the rounded rect (so `shadow` is close), but for an `image` with transparent corners it does not. |
| `filter: url(#f)` (an SVG filter chain) | **NOT SUPPORTED YET** | — | see `mix-blend-mode` + `sksl` |
| chaining several filters | they compose | `panel(blur = 6, saturate = 1.4, brightness = 1.1)` | `engine.nim:2195-2202` puts them all in one `Fx` record — one layer, one pass |
| any other filter | an SkSL shader | `panel(shader = sksl"""…""")` | `docs/spec/style.md` §8: "SkSL: runs per pixel; may declare `uniform float2 size;` (its box) and `uniform float time;` (seconds)". `engine.nim:1670-1676` — the shader *replaces* the fill; a shader that fails to compile shows its error over the app in dev builds, and one that reads `time` keeps frames coming. **This is the universal escape hatch and should be the default answer for "NOT SUPPORTED YET" in this section.** |
| `backdrop-filter: blur(26px)` | `backdropBlur = 26` | `panel(backdropBlur = 26, fill = rgba(0xFFFFFF, 0.1))` | `docs/spec/style.md` §8 — "frosted glass: blurs what is behind it". `PropTable` `backdropBlur → pBackdropBlur`; `engine.nim:745` — the engine sets `e.hasBackdrop = true` |
| `backdrop-filter: saturate/brightness` | **NOT SUPPORTED YET** | — | only `blur` exists in the `Fx` record (`engine.nim:2200`). **Fix difficulty: easy.** |
| `backdrop-filter: brightness()` on a scrim | not needed | `panel(fill = rgba(0x000000, 0.5))` | plain translucent `fill` |
| `mix-blend-mode: multiply` | `blend = multiply` | `panel(fill = 0xEB5757, blend = multiply)` | `dsl.nim:158-161` — 17 words: `normal`=3, `plus`=12, `screen`=14, `overlay`=15, `darken`=16, `lighten`=17, `colorDodge`=18, `colorBurn`=19, `hardLight`=20, `softLight`=21, `difference`=22, `exclusion`=23, `multiply`=24, `hue`=25, `saturation`=26, `color`=27, `luminosity`=28 |
| `mix-blend-mode: screen` | `blend = screen` | `panel(blend = screen)` | |
| `mix-blend-mode: overlay` | `blend = overlay` | `panel(blend = overlay)` | |
| `mix-blend-mode: darken` | `blend = darken` | `panel(blend = darken)` | |
| `mix-blend-mode: lighten` | `blend = lighten` | `panel(blend = lighten)` | |
| `mix-blend-mode: color-dodge` | `blend = colorDodge` | `panel(blend = colorDodge)` | camelCase, not `color-dodge` |
| `mix-blend-mode: color-burn` | `blend = colorBurn` | `panel(blend = colorBurn)` | |
| `mix-blend-mode: hard-light` | `blend = hardLight` | `panel(blend = hardLight)` | |
| `mix-blend-mode: soft-light` | `blend = softLight` | `panel(blend = softLight)` | |
| `mix-blend-mode: difference` | `blend = difference` | `panel(blend = difference)` | |
| `mix-blend-mode: exclusion` | `blend = exclusion` | `panel(blend = exclusion)` | |
| `mix-blend-mode: hue/saturation/color/luminosity` | `blend = hue` / `saturation` / `color` / `luminosity` | `panel(blend = hue)` | the separable blend modes, all present |
| `mix-blend-mode: plus-lighter` | `blend = plus` | `panel(blend = plus)` | the non-separable additive mode; `plus` is not a CSS keyword |
| `mix-blend-mode: normal` | `blend = normal` | `panel(blend = normal)` | note `normal` = 3, not 0 — 0 is "unset" |
| `mix-blend-mode` with an `isolation: isolate` group | **NOT SUPPORTED YET** | — | no isolation group. Workaround: a `panel` that is itself opaque forces a new layer. **Fix difficulty: medium.** |
| `isolation: isolate` | **NOT SUPPORTED YET** | — | same |
| `mix-blend-mode` correctness caveat | — | — | PORT-NOTES lines 2070-2148 pin a separate, *app-level* blend implementation against a real canvas at **864/864 cases exact** — but PORT-NOTES lines 2312-2326 carry the standing warning for shader work: "**THE CAVEAT STANDDS AND MUST NOT BE LOST.** Nothing here has ever run on a real GPU … the oracle is a `Math.fround` transcription of the GLSL, not a driver." The same honesty applies to `blend`: verify on the real surface, not by inspection. |

**Sibling chapters.** `skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md` is the one that goes
deep on §2.4 and §2.5 — the node-layer-vs-`Draw`-layer split and the port workarounds.
`reference/07-color-gradients-and-effects.md` covers §3's engine behaviour; this section is the
CSS→Yantra translation only. **Do not double up:** read the sibling, do not restate it here.

### 2.5 `box-shadow`

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `box-shadow: 0 6px 18px rgba(0,0,0,.35)` | `shadow = shadow(0, 6, 18, rgba(0x000000, 0.35))` | `panel(shadow = shadow(y = 6, blur = 18, color = rgba(0x000000, 0.4)))` | `style.nim:31-32` — `shadow(x = 0, y = 6, blur = 18, color = rgba(0x000000, 0.35))`. Positional args are x, y, blur, colour |
| `box-shadow: 2px 0 0 #000` | `shadow = shadow(2, 0, 0, 0x000000)` | | `blur = 0` is a hard offset shadow |
| `box-shadow: inset …` | **NOT SUPPORTED YET** | — | `nimskia.nim:137` — `proc shadow*(c; x,y,w,h,r, dx, dy, blur: float32; argb: uint32)` — no inset flag. Workaround: a darker `panel` child inset by the spread, with `blend = multiply`. **Fix difficulty: easy** (Skia's `kInner` shadow mode). |
| `box-shadow: … 4px` (spread) | **NOT SUPPORTED YET** | — | no spread parameter anywhere. Workaround: an inner/outer sibling with a 4px-larger box behind. **Fix difficulty: easy.** |
| two shadows, `box-shadow: a, b` | **NOT SUPPORTED YET** | — | `PropTable` has `shadowX/shadowY/shadowBlur/shadowColor` — one shadow. Workaround: two stacked panels, the outer one carrying the outer shadow. **Fix difficulty: easy** — a `seq[Shadow]`. |
| `box-shadow: none` | omit `shadow` | | `engine.nim:1665` — the shadow only draws if `P_SHADOWCOLOR` is present **and** (`blur > 0` or `x != 0` or `y != 0`) |
| `box-shadow` following the border radius | automatic | `panel(radius = 12, shadow = shadow(...))` | `engine.nim:1666` passes `radius` into the shadow call, so the shadow silhouette matches the rounded rect |
| `box-shadow` theme colour | `shadow = shadow(color = rgba(accent, 0.3))` | | `style.md` §1 lists `shadow` among the colour props: `colorProps = ["fill", "color", "textcolor", "bordercolor", "shadow"]` (`dsl.nim:99`), so `themeWords` rewrites bare names inside `shadow(...)` too (`dsl.nim:101-104`) |
| `text-shadow` | **NOT SUPPORTED YET** | — | the shadow is drawn for the box, not the glyphs (`engine.nim:1663` — `paintSurface` on the node rect). Workaround: a `text` node behind, offset by `x`/`y`, in a darker colour. **Fix difficulty: easy** (Skia `drawTextPaint` with a shadow layer). |
| `drop-shadow` on an icon | a duplicated `path`/`icon` behind it | `icon "search", color = rgba(0,0,0,.4)` + `icon "search", x = 2, y = 2, color = accent` | `x`/`y` are drawn offsets that keep layout and hit-testing (`docs/spec/style.md` §1) — exactly what a text-shadow workaround needs |

### 2.6 Clipping, masks, visibility

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `overflow: hidden` | `clip = true` | `panel(clip = true)` | see §1.6 |
| `visibility: hidden` | **NOT SUPPORTED YET** | — | Not a distinct concept. Workaround A: `visible = false` (which also removes it from layout — `engine.nim:520`, `setDisplay(ydNone)`). Workaround B: `opacity = 0` (keeps layout). **Fix difficulty: easy** — a paint-skip flag. |
| `visibility: visible` on a child of a hidden parent | `opacity = 0` on the parent | `panel(opacity = 0, visible = true)` | Yantra has no per-child override; a `visible = true` child inside `visible = false` still disappears. **Fix difficulty: easy.** |
| `clip-path: circle(50%)` | **NOT SUPPORTED YET** | — | `docs/spec/style.md` §8 says it plainly: "Next: compile-time shader checks, masks, clip paths." Workaround: `radius = halfSize` on an `image`/`panel` (a circle via a rounded rect is not truly circular — Skia draws a rounded *rect* — so a true circle needs a `canvas` or a shader). **Fix difficulty: medium** — Skia has `IRect`/`RRect` clip ops; a generic path needs a new string prop. |
| `clip-path: polygon(...)` | **NOT SUPPORTED YET** | — | same |
| `mask` / `-webkit-mask` | **NOT SUPPORTED YET** | — | `docs/spec/style.md` §8: "Next: … masks, clip paths." Workaround: an SkSL `shader` that returns transparent outside the shape. **Fix difficulty: medium** (an Skia `MaskFilter`/`saveLayer` with a shader mask). |
| `mask-image: url(m.png)` | **NOT SUPPORTED YET** | — | same |
| `mask-repeat` / `mask-position` | **NOT SUPPORTED YET** | — | |
| `-webkit-backdrop-filter` | `backdropBlur = 26` | see §2.4 | |
| `filter: url(#clip)` | **NOT SUPPORTED YET** | — | |

---

## 3. Gradients

**The whole gradient model, in three props.** `style.nim:7-10`:

```nim
type
  Gradient* = object
    ## `fill = linear(0xFF7A2F, 0xFFD28A, 135)`: from, to, angle in degrees (90 = top to bottom).
    a*, b*: int
    angle*: float32
```

and `style.nim:38-41`:

```nim
proc setFill*(n: Node; g: Gradient) =
  n.set(pGradFrom, wireI32(g.a))
  n.set(pGradTo, wireI32(g.b))
  n.set(pGradAngle, g.angle)
```

**There are exactly two stops and one linear angle. That is the entire vocabulary.**
Anything else in CSS gradients is `NOT SUPPORTED YET`; the per-row "Workaround" column below is
where the answer is — there are no subsections of §3 to jump to.

**Sibling chapter:** `reference/07-color-gradients-and-effects.md` is the node-level gradient
reference and §11 there carries the `NOT SUPPORTED YET` table. This section is the CSS→Yantra
translation only; do not restate the engine behaviour.
`skills/web-to-yantra/CSS-SHADOWS-AND-EFFECTS.md` is the node-layer-vs-`Draw`-layer split.
**Yantra angle = CSS − 90** in both — see the derivation below.

**The angle: `Yantra angle = CSS angle − 90`**, so **Yantra 0 = left→right**.

Derivation from `libs/nimskia/src/skia_shim.cpp:431-437` (`yk_rrect_gradient`):

```cpp
float dx = std::cos(a) * w / 2, dy = std::sin(a) * h / 2;
SkPoint pts[2] = {{cx - dx, cy - dy}, {cx + dx, cy + dy}};
```

The gradient runs from `pts[0]` to `pts[1]`, i.e. along `(cos a, sin a)` in screen
coordinates (y pointing **down**). So Yantra `a = 0` gives direction `(1, 0)` —
**left to right** — and `a = 90` gives `(0, 1)` — top to bottom. CSS's zero is
`0deg = to top`, which in this parameterisation is `a = 270`. Hence `CSS − 90`.

This is corroborated by a passing assertion, not just by reading the C++:
`libs/nimskia/tests/t_skia.nim:54-56` fills a 64×32 rect with `from` red, `to`
blue at **angle 0**, and asserts red at x=1 and blue at x=62 — left to right.

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `linear-gradient(to bottom, A, B)` | `linear(A, B)` | `panel(fill = linear(0xFF7A2F, 0xFFD28A))` | the angle defaults to **90**, which is top→bottom (`style.nim:29`). CSS's `to bottom` is the default too, so the two agree |
| `linear-gradient(180deg, A, B)` | the default — omit the angle | `fill = linear(A, B)` | CSS `180deg` = to bottom = Yantra 90, which is the default, so the two agree |
| `linear-gradient(0deg, A, B)` (to top) | `linear(A, B, 270)` | `fill = linear(A, B, 270)` | **Yantra angle = CSS angle − 90**, and Yantra **0 = left→right**. See the derivation above |
| `linear-gradient(90deg, A, B)` (to right in CSS) | `linear(A, B, 0)` | `fill = linear(A, B, 0)` | 90 − 90 = 0; Yantra 0 is exactly this |
| `linear-gradient(45deg, A, B)` | `linear(A, B, 315)` | `fill = linear(A, B, 315)` | 45 − 90 = 315 (a negative 45, taken mod 360) |
| `linear-gradient(to right, A, B)` | `linear(A, B, 0)` | | = CSS 90deg |
| `linear-gradient(to left, A, B)` | `linear(A, B, 180)` | | = CSS 270deg |
| `linear-gradient(to top right, A, B)` | `linear(A, B, 315)` | | = CSS 45deg |
| `linear-gradient(1turn, …)` / `0.25turn` | **NOT SUPPORTED YET** — degrees only | `0.25 * 90` | `angleOf` (`units.nim:39`) takes a `Deg` or a bare number in degrees; there is no `turn`/`rad` template. Workaround: multiply by hand. **Fix difficulty: trivial** (add `turn*`/`rad*` templates to `units.nim`). |
| `linear-gradient(1rad, …)` | **NOT SUPPORTED YET** | | same; `rad * 57.2958` |
| `linear-gradient(90grad, …)` | **NOT SUPPORTED YET** | | same |
| 3+ colour stops (`A 0%, B 50%, C 100%`) | **NOT SUPPORTED YET** | — | Only `pGradFrom`/`pGradTo` exist. Workarounds, in order of preference: (a) two nodes — a `panel(fill = linear(A, B, 90))` with a second `panel(fill = linear(B, C, 90), top = 50%)`… except `%` is not supported either, so use an explicit `height` from a `sized` block; (b) an **SkSL `shader`**, which can express any number of stops precisely and is the honest answer. **Fix difficulty: medium** — Skia's `GradientShader::MakeLinear` takes a `std::vector`; the wire needs `pGradStops` as a string. |
| `linear-gradient(A 0%, B 20%)` (explicit stop positions) | **NOT SUPPORTED YET** | — | same as above; the two stops are implicitly 0% and 100% |
| `linear-gradient(transparent, A)` | `linear(rgba(A, 0), A)` | `fill = linear(rgba(0x000000, 0), 0x000000)` | the honest way to write a transparent stop, because `style.nim:23-27` clamps alpha to 1..255 — alpha 0 becomes "almost clear" (1/255), not exactly 0. PORT-NOTES line 2183-2188 is the measured reason this matters: "Skia's src-over unpremultiplies a translucent DESTINATION … No `1/outA` term. White at 50% over black is 128, not 255" |
| `linear-gradient(color-mix(...), B)` | **NOT SUPPORTED YET** | — | no colour functions at all; compute the mixed value yourself |
| `linear-gradient(A, B) ` with a **hint** (`A, B 30%`) | **NOT SUPPORTED YET** | — | same as explicit stop positions |
| `repeating-linear-gradient(...)` | **NOT SUPPORTED YET** | — | same as >2 stops. Workaround: an SkSL shader, or nested bands. **Fix difficulty: medium** |
| `radial-gradient(...)` | **NOT SUPPORTED YET** | — | there is no radial code path: `engine.nim:1680-1682` calls `c.fillGradient(...)`, and `nimskia.nim:133-135` maps that to `yk_rrect_gradient` — a *linear* gradient across the rect. Workaround: an SkSL `shader` (`half4 main(float2 p)` with `distance(p, size/2)`). **Fix difficulty: medium** — Skia has `GradientShader::MakeRadial`; it is a new prop plus a new binding, not a new idea. |
| `radial-gradient(circle at 30% 40%, A, B)` (shape/size/position) | **NOT SUPPORTED YET** | — | same |
| `conic-gradient(from 45deg, …)` | **NOT SUPPORTED YET** | — | SkSL only. **Fix difficulty: medium.** |
| `repeating-conic-gradient` | **NOT SUPPORTED YET** | — | SkSL only |
| `-webkit-linear-gradient` | same as `linear-gradient` | | |
| a gradient that must follow the border radius | automatic | `panel(radius = 12, fill = linear(A, B, 90))` | `engine.nim:1681` passes `radius` into `fillGradient` — the gradient is clipped to the rounded rect |
| a gradient on a node that also has a hover fill | hover wins, gradient is skipped | `panel(fill = linear(A, B), transition = 200):` …`hover: fill = 0xEEE` | `engine.nim:1668-1669, 1680` — `stateFill` is true when `pHoverFill`/`pPressFill`/`pFocusFill` applies, and then the gradient branch is skipped entirely. **A gradient cannot be a hover-state fill.** Workaround: use a solid in the state block. |
| theme colours in a gradient | yes | `fill = linear(accent, danger, 135)` | `docs/spec/style.md` §1 — theme words are rewritten "inside … `linear(…)`", so a theme switch re-styles the gradient |
| theme colours with alpha in a gradient | yes | `fill = linear(accentSoft, surface, 90)` | `accentSoft` exists (`dsl.nim:98`) and is exactly this use case |
| switching a gradient off | set a plain colour | `panel(fill = 0xFFFFFF)` | `style.nim:36` — "a plain colour switches any gradient off" (`pGradAngle = -1`) |
| `background: linear-gradient(...)` in a `Style` preset | yes | `style(fill = linear(A, B, 90), radius = 12)` | `use = cardGradient()` |
| **Degenerate gradient caveat** | — | — | PORT-NOTES line 2264-2269 is the one gradient warning in the whole repo, and it applies to any hand-rolled gradient work: "Chrome **dithers** a two-colour linear gradient whose two stops are identical … Reproducing a hardware dither mask is not a transcription problem." If you port a two-identical-stop gradient, expect a dithered result and do not chase it. |

---

## 4. Typography

### 4.1 Family and size

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `font-family: Inter` | `font = "Inter"` | `text "Hi", font = "Inter"` | `PropTable` `font → pFontFamily` (string, `"*"`); `nimskia.nim:128-131` passes `st.fam` to the text draw |
| `font-family: monospace` | `font = mono` | `text "Hi", font = mono` | `dsl.nim:168` — `font = mono` and `font = font` are rewritten to `theme().mono` / `theme().font` |
| `font-family: serif` / `sans-serif` | **NOT SUPPORTED YET** — CSS generics are not implemented at all | — | **Nothing in Yantra or in its Skia layer resolves a generic name.** The *only* special cases in the whole chain are `sdk/ui/dsl.nim:168` `if norm == "font" and w in ["mono", "font"]: propVal = newDotExpr(newCall(ident"theme"), ident(w))` — i.e. `mono` and `font` only, rewritten to `theme().mono` / `theme().font`. Anything else, `"serif"` included, is passed as a **literal family name** to `libs/nimskia/src/skia_shim.cpp:139-140` `ts.setFontFamilies({SkString(fam.c_str()), SkString("Segoe UI"), SkString("Nirmala UI"), SkString("Segoe UI Emoji")})`. There is no name table, no alias map and no generic case anywhere: an unmatched family simply falls through to `"Segoe UI"` on line 140, silently, with no error and no warning. Which names are matchable depends on the target — native resolves through `skia_shim.cpp:84` `SkFontMgr_New_DirectWrite()`, so only fonts installed on the machine match. Workaround: name a concrete family that exists. |
| `font-family: Inter, system-ui, sans-serif` (fallback list) | **NOT SUPPORTED YET** | — | one family string. Workaround: pick the one you can guarantee. **Fix difficulty: easy** — the text draw already takes a family string; a comma list plus `SkFontMgr::matchFamilyStyle` would do it. |
| a custom/embedded webfont (`@font-face` + woff2) | **NOT SUPPORTED YET** | — | **There is no font-loading API, confirmed by an exhaustive search.** Grepped the whole tree for `MakeFromData\|makeFromData\|loadFont\|fontFile\|fontPath\|registerFont\|addFont\|@font-face\|woff\|ttf\|otf` across `*.nim`/`*.cpp`/`*.c`/`*.h`/`*.js`/`*.mjs`: **zero** hits in `sdk/`, `render/`, `host/` or `libs/`. Every `ttf` hit in the tree is an app comment about Arial metrics (`apps/minipaint/config.nim:862`, `apps/minipaint/tests/t_menu_width.nim:77`). What *does* exist is a **hardcoded build-time download, wasm target only**: `tools/build-web.sh:34-37` `# fonts` / `F="$TP/fonts"` / `[ -f "$F/sans.ttf" ] || curl -sSLf -o "$F/sans.ttf" "…/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"` / `[ -f "$F/mono.ttf" ] || curl -sSLf -o "$F/mono.ttf" "…/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"` — Inter and JetBrains Mono, hardcoded, not selectable by an app. `libs/nimskia/src/skia_shim.cpp:63-82` then scans the page's `/fonts` directory with `makeFromFile` and registers each file under fixed aliases — `skia_shim.cpp:76-78` `for (const char* alias : mono ? std::initializer_list<const char*>{"Cascadia Mono", "Consolas"} : std::initializer_list<const char*>{"Segoe UI", "Nirmala UI"}) provider->registerTypeface(tf, SkString(alias));`, with `skia_shim.cpp:75` `bool mono = name.rfind("mono", 0) == 0;`. So a web build has exactly two real families and can name either by its own name or by one of those four aliases. Workaround: use a family name the machine already has, or draw text on a `canvas`. **Fix difficulty: medium** (a font-file loader + `SkTypeface::MakeFromData`; the wasm side needs the bytes in the module). |
| `font-size: 18px` | `size = 18` (or `fontSize = 18`) | `text "Hi", size = 18` | `dsl.nim:212-213` — both spellings call `node.fontSize(int32(v))`; `PropTable`: `size` on `Text,Button,Input,TextArea,Window,Checkbox,Path`, `fontSize` on `Text,Button,Input,TextArea` |
| `font-size: 1.125rem` | `size = 18` | | no `rem`; multiply by the root size (PORT-NOTES line 1093 — `html{font-size:10px}` meant `2.4rem` = 24px) |
| `font-size: 1.125em` | `size = <computed>` | | no `em`; resolve against the parent's `size` by hand |
| `font-size: 120%` | `size = <computed>` | | no `%` |
| `font-size: clamp(14px, 2vw, 20px)` | **NOT SUPPORTED YET** | — | no `clamp()`, no `vw`. Workaround: a `sized w, h:` block with `if w < 700: size = 14 else: size = 20` — `docs/spec/style.md` §9.1's own responsive idiom. **Fix difficulty: medium.** |
| `font-size` on a container | **NOT SUPPORTED YET** (no cascade) | — | `PropTable` allows `size` on `Window` (`protocol/schema.nim:260`) but the value never reaches children. `render/native/engine.nim:385` is the whole resolution: `proc fontSize(n: tree.Node; k: int32): float32 = n.num(P_FONTSIZE, if k == K_PATH: 24 else: 15)` — the node's own prop, a literal per-kind default, no parent lookup. Same shape for `font` (`engine.nim:396` `n.sProp(P_FONTFAMILY)`), `weight` (`:386`) and `color` (`:401-404`). Set `size` on every text node, or wrap in a component. |
| `font-weight: 600` | `weight = 600` | `text "Hi", weight = 600` | `PropTable` `weight → pFontWeight` (int32, `"*"`); `nimskia.nim:131` passes it as `int(weight)` to Skia |
| `font-weight: bold` / `normal` | `weight = 700` / `weight = 400` | `text "Hi", weight = 700` | the wire prop is a number; the words are not mapped (`dsl.nim:152-162` has no `weight` case) |
| `font-weight: 100..900` | the number | `weight = 300` | whether the installed family has a 300 is up to Skia's matcher. PORT-NOTES line 1664 is the place where text metrics bit the port: "The menu bar is the kerned Arial advance" |
| `font-style: italic` | `italic = true` | `text "Hi", italic = true` | `PropTable` `italic → pItalic` (bool, `"*"`); `nimskia.nim:131` passes `st.italic` |
| `font-stretch` / `font-width` | **NOT SUPPORTED YET** | — | no condensed/expanded axis. Workaround: pick a different family. **Fix difficulty: medium** (Skia has `SkFontStyle` width). |
| `font-variant-*` (`small-caps`, `oldstyle-nums`, `tabular-nums`) | **NOT SUPPORTED YET** | — | |
| `font-feature-settings` (OpenType features, `ss01`, `liga`) | **NOT SUPPORTED YET** | — | `nimskia.nim:131` passes only family, italic, lineHeight, maxLines. Workaround: `text-transform`-by-hand at the string level, or a family that has the feature on by default. **Fix difficulty: medium** — Skia exposes `SkFontMgr` features. |
| `font-kerning` | **NOT SUPPORTED YET** as a prop | — | PORT-NOTES line 1664: "The menu bar is the kerned Arial advance, and measuring the wrong thing first" — i.e. kerning **is** applied by the text draw, it just has no switch. Treat kerning as always-on. |

### 4.2 Line and block

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `line-height: 1.5` | `lineHeight = 1.5` | `text "Hi", lineHeight = 1.5` | `PropTable` `lineHeight → pLineHeight` (float32, `"*"`); `nimskia.nim:131` passes `st.lineHeight`. **Settled — it is a MULTIPLIER, not px:** `libs/nimskia/src/skia_shim.cpp:96` declares `float lineHeight = 0; // multiple of the font size; 0 = the font's own`, `:145` applies `ts.setHeight(o.lineHeight)`, and `:359` computes `float lh = size * (lineHeight > 0 ? lineHeight : 1.2f);`. **`lineHeight = 24` at `size = 16` means 24× the font size, not 24 px.** `0` leaves the engine's default of **1.2** |
| `line-height: 24px` | `lineHeight = 24` | `text "Hi", lineHeight = 24` | same caveat; note `lineHeight` is **not** in `lengthProps` (`dsl.nim:89-93`), so `24.px` is a compile error on it |
| `text-align: left` | `align = left` | `text "Hi", align = left` | `PropTable` `align → pAlign` (int32), allowed on `Text,Column,Row`; `dsl.nim:156` — `align` words: `left`=0, `center`=1, `right`=2`. `nimskia.nim:130` passes `align` to `yk_text_draw2`, and the engine centres natively via `yk_text_measure`. **`Draw.text` has no `align` parameter at all — see §12** |
| `text-align: center` | `align = center` | `text "Hi", align = center` | works on a `text` node: the engine measures the string and offsets it |
| `text-align: right` | `align = right` | `text "Hi", align = right` | same |
| `text-align: justify` | **NOT SUPPORTED YET** | — | no 4th align value. **Fix difficulty: easy.** |
| `text-align: start` / `end` | `align = left` / `right` (LTR) | | **Settled:** `direction` exists (`engine.nim:521-522`) and it *does* drive Yoga (`engine.nim:738`, `:1546`), but it is **not** consulted on `pAlign` — there is no `start`/`end` word in the `align` enum (`dsl.nim:156` maps left/center/right only). Under `direction = 2` you must pick the physical side yourself |
| `text-indent` | **NOT SUPPORTED YET** | — | Workaround: split into two `text` nodes in a `column(alignItems = start)`. **Fix difficulty: easy.** |
| `text-overflow: ellipsis` (with overflow hidden) | `maxLines = 2` | `text "…", maxLines = 2` | `PropTable` `maxLines → pMaxLines` (int32, `"*"`); `docs/spec/style.md` §1 — "`maxLines` (ellipsis)". `nimskia.nim:131` passes `st.maxLines`. PORT-NOTES line 1418 gives the line-box consequence: upstream's `inline-block` items "form a 28px line box" — in Yantra, `maxLines = 1` gives a one-line row rhythm |
| `text-overflow: clip` | omit `maxLines` | | |
| `white-space: nowrap` | **NOT SUPPORTED YET** | — | Text wraps by default. Workaround: a wide `row` with `shrink = 0` on the text, or `maxLines = 1`. **Fix difficulty: easy** — a wrap flag on the measure function. |
| `white-space: pre` / `pre-line` | **NOT SUPPORTED YET** | — | `textarea`/`textArea` is the multi-line control (`PropTable` `rows → pRows` on `TextArea`) |
| `word-break: break-all` | **NOT SUPPORTED YET** | — | PORT-NOTES line 293 records that the text tool's "text metrics + wrapping" is proven by `t_five_tools.nim`, so wrapping *is* real; only the CSS knobs are missing. **Fix difficulty: medium** |
| `word-break: break-word` / `overflow-wrap: anywhere` | **NOT SUPPORTED YET** | — | same |
| `hyphens: auto` | **NOT SUPPORTED YET** | — | no hyphenation dictionary. **Fix difficulty: hard** (needs a hyphenation table in the wasm module) |
| `overflow-wrap: break-word` | **NOT SUPPORTED YET** | — | |
| `vertical-align` | **NOT SUPPORTED YET** | — | No inline layout to align within (see `display: inline` in §1.1). Workaround: `row(alignItems = center)`. **Fix difficulty: trivial** once inline layout exists. |
| `direction: rtl` | `direction = <n>` | `column(direction = 2)` | `PropTable` `direction → pDirection` (int32). **Settled** — `render/native/engine.nim:521-522`: `if n.has(P_DIRECTION) and n.num(P_DIRECTION, 0) > 0: y.setDirection(if n.num(P_DIRECTION, 0) >= 2: dirRTL else: dirLTR)`. So the mapping is **`0` = unset (inherit), `1` = LTR, `2` = RTL**; `engine.nim:738` propagates it down and `engine.nim:756` applies it to the root |
| `unicode-bidi` | **NOT SUPPORTED YET** | — | Yoga has `setNodeDirection` but no bidi algorithm. **Fix difficulty: hard.** |
| `writing-mode: vertical-rl` | **NOT SUPPORTED YET** | — | no vertical text. **Fix difficulty: hard** (Skia can draw rotated glyphs; the *layout* would have to change) |
| `text-orientation` | **NOT SUPPORTED YET** | — | same |
| `writing-mode: horizontal-tb` | the default | | |
| `tab-size` | **NOT SUPPORTED YET** | — | |

### 4.3 Decoration and rich text

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `text-decoration: underline` | **NOT SUPPORTED YET** as a prop | — | `PropTable` has `links` (string, on `Text`) and `inline` (string, on `Text`) for the rich-text path. Workaround: `rich "Some **bold** and [a link](https://x.com)"` — `dsl.nim:365-371`; one `Text` node that "runs styled (R2)". **Fix difficulty: easy** — Skia's `drawTextBlob` takes a `TextBlobBuilder` with per-run decoration. |
| `text-decoration: line-through` | **NOT SUPPORTED YET** | — | same |
| `text-decoration: none` | the default | | |
| `text-transform: uppercase` | **NOT SUPPORTED YET** | — | Workaround A: `text $s.toUpperAscii`. Workaround B: a `proc label(s: string): string = s.toUpperAscii` used at the call site. **Fix difficulty: trivial** (a `case` in the text draw on the prop value). |
| `text-transform: lowercase` | `$s.toLowerAscii` | | same |
| `text-transform: capitalize` | not a `toUpperAscii` call | — | needs per-word capitalisation; do it in Nim |
| `text-transform: none` | the default | | |
| `letter-spacing` / `word-spacing` | **NOT SUPPORTED YET** | — | No prop, and `nimskia.nim:128-131` passes no tracking argument. PORT-NOTES line 1664 is the concrete cost: the menu bar is "the kerned Arial advance", and tracking would be a second measurement the port had to add by hand. **Fix difficulty: easy** — one float to the text draw, applied to `TextBlobBuilder`. |
| `::first-letter` / `::first-line` / `::selection` | **NOT SUPPORTED YET** | — | no pseudo-element paint at all. Workaround: split into separate `text` nodes. **Fix difficulty: easy** (for first-letter), harder for `::selection` (needs a selection rect). |
| `content: "…"` on a pseudo-element | **NOT SUPPORTED YET** | — | see §6, `::before`/`::after` |
| mixed formatting in one string | `rich "…**bold**…"` | `rich "Some **bold** and [a link](https://x.com)"` | `dsl.nim:365-371` |
| `white-space` handling of `&nbsp;` | not supported | — | use a real space, or `maxLines` |
| `color: transparent` text | `color = rgba(0x000000, 0)` | `text "Hi", color = rgba(0x000000, 0)` | |
| an ellipsis that is a character | `text "…"` | `text "…"` | |

---

## 5. Transforms & effects

### 5.1 Static transforms

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `transform: translateX(10px)` | `x = 10` | `panel(x = 10)` | `PropTable` `x → pX` (float32, `"*"`). `docs/spec/style.md` §1 — "drawn moved; **layout and hit testing keep the box**" |
| `transform: translateY(10px)` | `y = 10` | `panel(y = 10)` | `docs/spec/style.md` §1 lists `y` under **Transform** too, despite `y` also being an inset name — the DSL distinguishes them by context: `y = n` on a non-absolute node is `pY` (a draw offset); `top/left/right/bottom` are the insets (`dsl.nim:268-269, 307-310`) |
| `transform: translate(x, y)` | `x = …, y = …` | `panel(x = 10, y = 20)` | |
| `transform: scale(1.1)` | `scale = 1.1` | `panel(scale = 1.1)` | `PropTable` `scale → pScale` (float32); also animatable in a state block (`dsl.nim:238`) |
| `transform: rotate(45deg)` | `rotate = 45` | `panel(rotate = 45)` | `PropTable` `rotate → pRotZ` (float32); `rotate` is in `angleProps` (`dsl.nim:95`) so `45.deg` is legal |
| `transform: skewX(10deg)` | **NOT SUPPORTED YET** | — | no skew in `PropTable`. Workaround: an SkSL `shader`. **Fix difficulty: medium** (a Skia matrix prop would cover skew, and 3D rotation, at once). |
| `transform: skewY(10deg)` | **NOT SUPPORTED YET** | — | same |
| `transform: matrix(…)` | **NOT SUPPORTED YET** | — | no matrix prop |
| `transform: matrix3d(…)` | **NOT SUPPORTED YET** | — | no 3D transform prop |
| `transform: translate3d/rotate3d` | **NOT SUPPORTED YET** | — | no |
| `transform: perspective(...)` | **NOT SUPPORTED YET** | — | `scene3d:` / `camera(fov = …)` are the only 3D surface. **Fix difficulty: hard.** |
| `transform-origin` | **NOT SUPPORTED YET** | — | `x`/`y`/`scale`/`rotate` all act about the centre (Yoga/Skia default). `docs/spec/style.md` §1: "drawn moved; layout and hit testing keep the box" — no origin concept. **Fix difficulty: medium.** |
| `transform: rotate(…)` about a corner | **NOT SUPPORTED YET** | — | PORT-NOTES line 369 records how much a pivot costs when it is missing at the app layer: "`imagemenu.nim:424` `rotatePixelsInto` transcribes upstream's draw block; `imagemenu.nim:531` `rotateFit` supplies the pivot" — the pivot had to be supplied by hand in a separate proc |
| `transform-style: preserve-3d` | **NOT SUPPORTED YET** | — | |
| `backface-visibility` | **NOT SUPPORTED YET** | — | |
| `will-change: transform` | nothing to write | — | Not needed: the engine already routes `blur`/`backdropBlur`/`blend`/`saturate`/`brightness`/`contrast`/`opacity` through one fx layer (`engine.nim:2195-2202`), which is the entire set of things `will-change` would name |
| `will-change: contents` | nothing to write | | |

### 5.2 Transitions

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `transition: all 200ms ease` | `transition = 200` | `panel(transition = 200, ease = outCubic)` | `PropTable` `transition → pTransDuration` (int32); `transition` is in `durationProps` (`dsl.nim:94`) so `200.ms` / `0.2.s` are legal. `docs/spec/style.md` §7: "**any change glides**: fill, colour, border, opacity, size, position, hover/press states" |
| `transition-property: <list>` | **NOT SUPPORTED YET** | — | there is no property list. A `transition` covers *everything* the node can animate. Workaround: split into two nodes if only part should glide. **Fix difficulty: medium** (a bitmask prop). |
| `transition-duration: 200ms` | `transition = 200` | | |
| `transition-delay: 100ms` | **NOT SUPPORTED YET** on `transition` | — | `delay` exists only on `enter`/`exit`/`animate` (`motion.nim:29-48`). Workaround: `afterMs(100, …)` (`motion.nim:74-77`) or an `enter = fly(delay = 100)`. **Fix difficulty: trivial.** |
| `transition-timing-function: ease-out` | `ease = outCubic` | `panel(transition = 200, ease = outCubic)` | `dsl.nim:165-167` — `ease` accepts any name in `Easings` (`protocol/schema.nim:240-248`) case-insensitively, and also the prefixed form (`easeOutCubic` → `outcubic`). Default is `outCubic` (`docs/spec/style.md` §7) |
| `cubic-bezier(.4,0,.2,1)` (a custom curve) | **NOT SUPPORTED YET** | — | no arbitrary-bezier prop. Closest: the 36 named curves in `Easings` (`Linear, In/Out/InOutQuad/Cubic/Quart/Quint/Sine/Expo/Circ/Back/Elastic/Bounce` + `Spring, SpringGentle, SpringBouncy, SpringStiff`). **Fix difficulty: easy** — a 4-float prop. |
| `transition-timing-function: linear` | `ease = linear` | `panel(ease = linear)` | |
| `transition-timing-function: ease` | `ease = inOutCubic` | | the closest curve; there is no bare `ease` in `Easings` (`dsl.nim:166` also accepts `"ease" & name`, so `easeInOutCubic` works too) |
| `transition-timing-function: steps(n)` | **NOT SUPPORTED YET** | — | **Fix difficulty: medium.** |
| `transition-property: none` | omit `transition` | | "A node's first value is taken as is" (`docs/spec/style.md` §7) |
| A transition that retargets mid-flight | automatic | `panel(transition = 300)` then change `fill` again | "A change mid-flight starts from where the value is now; nothing jumps" |
| Springs | `ease = spring` / `springGentle` / `springBouncy` / `springStiff` | `panel(transition = 300, ease = springBouncy)` | `docs/spec/style.md` §7 (Springs `[S-MOT-2]`): "the value moves by real physics and keeps its speed when the target changes mid-flight" |
| A layout change gliding (FLIP) | automatic with `transition` | `column(transition = 250):` with keyed children | `docs/spec/style.md` §7 — "and its layout box relative to its parent — so a keyed list reorders by sliding (Svelte's `animate:flip`)" |
| Reduced motion | automatic | — | `docs/spec/style.md` §7 — `YANTRA_REDUCED_MOTION=1` "makes every duration 0 and stands loops still; apps need no code for it" |

### 5.3 Keyframes and enter/exit

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `@keyframes` on opacity | `animate = pulse(0.4, 1200)` | `icon "refresh", animate = pulse(0.4, 1200)` | `docs/spec/style.md` §7: "`animate = …` loops one channel: `spin(ms)`, `pulse(low, ms)`, `breathe(scale, ms)`, `bob(y, ms)` or `loop("opacity" \| "rotate" \| "scale" \| "x" \| "y", from, to, ms, yoyo, ease, count)`" |
| `@keyframes` on rotate | `animate = spin(1000)` | `icon "refresh", animate = spin()` | `motion.nim:45` — `spin(ms = 1000) = loop("rotate", 0, 360, ms, yoyo = false, ease = easeLinear)` |
| `@keyframes` on scale | `animate = breathe(1.04, 1600)` | `panel(animate = breathe())` | `motion.nim:47` |
| `@keyframes` on translateY | `animate = bob(-4, 1400)` | `panel(animate = bob())` | `motion.nim:48` |
| a hand-written keyframe track | `loop(target, frm, to, ms, yoyo, ease, count, delay)` | `animate = loop("opacity", 0, 1, 600, yoyo = true, ease = inOutSine, count = 3, delay = 100)` | `motion.nim:41-43` — exactly this signature. `count = 0` is forever (`docs/spec/style.md` §7) |
| `@keyframes` with more than one channel at once | **NOT SUPPORTED YET** | — | "loops **one** channel". Workaround: nest two nodes, each animating one channel. **Fix difficulty: medium** (a target list, like `loop`'s string but as a `seq`). |
| `@keyframes` with arbitrary keyframe percentages | **NOT SUPPORTED YET** | — | `loop` is a single from→to ramp with an optional yoyo. There is no keyframe list. **Fix difficulty: medium–hard.** |
| `@keyframes` on width/height/border-radius/colour | **NOT SUPPORTED YET** | — | the animatable channels are `opacity, rotate, scale, x, y`. Use `transition` for one-off changes, or a `machine:` (`docs/spec/style.md` §7.y). **Fix difficulty: medium.** |
| `@keyframes` on `offset-path` | **NOT SUPPORTED YET** | — | |
| `animation-play-state: paused` | **NOT SUPPORTED YET** | — | no prop. `PropTable` has `playing` but it is `allowedNodes: "Video,Audio,Synth"`. **Fix difficulty: trivial** (a bool the loop reads). |
| `animation-iteration-count` | `count = n` | `animate = loop("opacity", 0, 1, 600, count = 3)` | `motion.nim:42` |
| `animation-direction: alternate` | `yoyo = true` | `loop("scale", 1, 1.2, 600, yoyo = true)` | |
| `animation-timing-function` | `ease = …` on the loop | `loop("x", 0, 100, 800, ease = outBack)` | |
| `animation-delay` | `delay = n` | `loop("scale", 1, 1.1, 400, delay = 120)` | `motion.nim:42` |
| Svelte `in:` / Vue `<Transition>` | `enter = …` | `row(enter = fly(y = 12))` | `docs/spec/style.md` §7 — "played when the node appears after the first frame (Svelte's default: the first screen does not animate in)" |
| Svelte `out:` | `exit = …` | `row(exit = fade())` | "plays after the app removed the node: the engine keeps drawing it where it was (not hit-testable) until done, while its neighbours slide into the gap" |
| `@keyframes` on appear (CSS `animation` on mount) | `enter = fade()` | `panel(enter = fade(180))` | |
| stagger | `delay = i * 30` | `for i, m in msgs: row(enter = fly(y = 12, delay = i * 30)):` | `docs/spec/style.md` §7 — "each with `ms`, `delay` (stagger lists with `delay = i * 30`) and `ease`" |
| the four built-in motions | `fade()`, `fly(x, y)`, `pop(scale)`, `turn(rotate, scale)` | `fade(180)`, `fly(x = 0, y = 12, opacity = 0, ms = 260)`, `pop(0.9, ms = 240)`, `turn(-90, 0.6, ms = 320)` | exact signatures: `motion.nim:29, 32, 35, 38` |
| scroll-linked / shared-element motion | **NOT SUPPORTED YET** | — | `docs/spec/style.md` §7 says it outright: "**Not yet:** scroll-linked and shared-element (FLIP across parents) motion". The nearest available tools are `reveal = fly(y = 40)` (tied to scrolling into view, `motion.nim:57-60`) and `parallax`. **Fix difficulty: medium.** |
| `timeline:` (ordered steps) | `timeline:` / `at` / `then` | `timeline:` … `at 0.4.s: scene.set(1)` … `then 600.ms: scene.set(2)` | `docs/spec/style.md` §7 (Timelines `[S-MOT-3]`) — "Steps in time, on the engine's clock (exact frames in a film)". This is the closest thing to a keyframe timeline. |

---

## 6. Selectors → Yantra constructs

**The rule.** `docs/spec/style.md` §1: "There are no stylesheets, selectors or cascades: a value
comes from the call site, a style preset (`use =`, style.md §3) or the engine's plain default."
So *every* CSS selector is a translation of **a scoping mechanism** into **a code mechanism**.
Three of them exist: a proc, a variable, and the node tree.

**Cite this section by number, not by file line.** `reference/20-cloning-a-live-website.md:131`
and `:146` both point at `15a-html-css-mapping.md` by line; those line numbers are stale (the
quote above moved). `§6` is the stable reference. The `::before` / `::after` rows named there are
the three rows at the foot of the table below.
`reference/18-porting-process.md` is the chapter that sequences the walk that feeds this table.

| CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `.card { fill: …; radius: … }` | a `Style` preset proc | `proc card(): Style = style(fill = theme().surface, radius = 12, pad = 16)` | `docs/spec/style.md` §3 (`[S-STY-3]`) — the spec's own example. `style.nim:15-17` — a `Style` is `apply: seq[proc (n: Node)]` |
| `<div class="card">` | apply it | `panel(use = card(), gap = 8)` | `dsl.nim:192-193` — `use` → `applyStyle` (once, not wrapped in an effect) |
| `.card:hover`-style overrides | call-site props beat the preset | `panel(use = card(), radius = 20)` | `docs/spec/style.md` §3 — "**call-site props win over the preset**" |
| a preset that reads the theme | a plain proc | `proc card(): Style = style(fill = theme().surface, radius = theme().radius)` | "Presets are ordinary procs, so they can read the theme and stay reactive" |
| `.card { … }` with pseudo-classes inside | `proc card(hovered: bool): Style` | `panel(use = card(sel.get))` | a preset is a proc, so the state is a parameter |
| `#hero { … }` (an id) | a `var` + conditional props | `var isHero = false` … `panel(fill = (if isHero: accent else: surface))` | prop values are expressions; `docs/spec/style.md` §1 gives `color = (if on: accent else: muted)` as the canonical form |
| `#hero` with many rules | a `proc hero(): Style` used at the one site that owns it | `panel(use = hero())` | ids in CSS are unique; in Yantra uniqueness is by discipline |
| holding a node handle | `@name` | `panel @cardRow:` … `cardRow.set(pFill, 0xFF0000)` | `dsl.nim:276-291` (`takeHandle`) — "roadmap S3". Used as `panel(@card, …)` |
| reading a prop back off a node | `node.getStr` / `node.num` | `let w = heroRow.num(pWidth)` | |
| `.a .b` (descendant) | nesting in the node tree | `row: panel: text "…"` | Yantra has no matching; containment *is* the selector |
| `.a > .b` (child) | the same nesting, one level | | no way to express "only a direct child" |
| `.a + .b` (adjacent sibling) | the same nesting, order-dependent | `row: panel(a) panel(b)` | no sibling combinator; order in the tree is the only relationship |
| `.a ~ .b` (general sibling) | **NOT SUPPORTED YET** | — | Workaround: a `for` loop with an index and `if i > 0:`. **Fix difficulty: hard** — it is a cross-cutting query, and Yantra's model is a tree of owned nodes. |
| `:hover` | the `hover:` block | `button "Open":` … `hover:` … `fill = surface2` | `dsl.nim:223-246` (`stateBlock`). `docs/spec/style.md` §2 — "The engine applies them; the app does no work and no re-render happens" |
| `:active` / `:pressed` | the `pressed:` block | `pressed: fill = surface3` | same |
| `:focus` / `:focus-visible` | the `focused:` block | `focused: borderColor = accent` | same; `focus` is not focus-visible — it follows the engine's focus id (`engine.nim:1668`) |
| `:focus-within` | **NOT SUPPORTED YET** | — | no subtree-focus concept. Workaround: track it in a `var` and set `focused:` props manually via a handle. **Fix difficulty: medium.** |
| `:disabled` | `disabled = true` | `button("Save", disabled = busy.get)` | `PropTable` `disabled → pDisabled` (bool), allowed on `Button,Input,Checkbox,Radio,Select,Slider,Switch`. It is a *prop*, not a block — the disabled look is the engine's, not yours. **There is no `disabled:` state block.** |
| `:checked` | `checked = true` | `checkbox(checked = agree.get)` | `PropTable` `checked → pChecked` (bool) on `Checkbox,Radio,Switch` |
| `:enabled` | the inverse of `disabled` | `disabled = not ok` | |
| `:target` / `:link` / `:visited` | **NOT SUPPORTED YET** | — | no URL/visited state model in the window |
| `:nth-child(2n)` | an index in the `for` | `for i, item in items: panel(if i mod 2 == 0: fill = zebra else: surface2)` | the idiomatic translation |
| `:nth-child(odd)` | `(i+1) mod 2 == 1` | | |
| `:first-child` / `:last-child` | `i == 0` / `i == items.len - 1` | | |
| `:only-child` | `items.len == 1` | | |
| `:not(.x)` | an `if` | `if not sel.get:` | |
| `:root` | the theme | `theme()` | `docs/spec/style.md` §4 |
| `html` / `body` | the `window` | `app("Name"):` | |
| `[disabled]` (attribute selector) | the `disabled = true` prop | | |
| `[data-role="header"]` | a Nim enum/tagged value | `case role of hrHeader: …` | the enum replaces the attribute; there is no attribute bag |
| `[data-x="1"]` presence tests | `if flag.get:` | | |
| `::before` | an extra child node | `row:` … `panel(width = 6, fill = accent)` … `text "Label"` | There is no pseudo-element paint. The translation is literal: make the pseudo-element a real first child. **PORT-NOTES line 487-490 is the concrete case** — "The sidebar's glyphs are not `<img>` tags. `gui-tools.js:build_base()` emits a bare `<span class="item trn NAME"></span>` and the artwork comes from CSS `background-image` on an `:after` pseudo-element" — the port turned the pseudo-element into a drawn node. |
| `::after` | an extra child node | `row:` … `text "Label"` … `panel(width = 6, fill = accent)` | same |
| `::before { content: "…" }` | a literal `text` node | `text "•"` | |
| `::before` with a positioned absolute box | `panel(absolute = true, top = …, left = …)` inside a `stack:` | | combines two translations |
| `::first-letter` | a separate `text` node | `column: text "H"` `text "ello"` | |
| `:hover` on a pseudo-element | the pseudo-element node's own `hover:` block | | since it is a real node it can have its own state block |
| an HTML class used for **spacing utilities** (`.mt-2`) | a preset proc per utility | `proc mt2(): Style = style(marginTop = 8)` … `panel(use = mt2())` | feasible but verbose; a `for` over a table of presets is the pragmatic route |
| an HTML class used for **responsive visibility** (`.hidden-sm`) | a `sized` block | `sized w, h: if w < 640: column: cards() else: row: cards()` | `docs/spec/style.md` §9.1 — this is the real container-query replacement for every responsive utility class |
| `content-visibility` / lazy rendering | `lazy m in msgs, 44:` | `lazy m in msgs.get.keyed(m.id), 44:` | `docs/spec/style.md` §9.2 (`[S-LAY-3]`) — "builds only the rows that show, plus 4 above and 4 below, with spacers for the rest". PORT-NOTES line 891-893 records the measured result: "100 000 rows: first frame 3 ms, 50 wheel steps 37 ms" (`render/native/t_longlist.nim`) |
| a `<script>` that toggles a class | a signal | `var open = false` … `panel(use = (if open: panelOpen() else: panelClosed()))` | props are effects; changing the signal re-renders. `docs/spec/style.md` §4 — "one click, no reload, no engine involvement" |
| `!important` | **NOT SUPPORTED YET, and unnecessary** | — | there is no cascade to beat. If a call-site prop beats a preset, the ordering is already deterministic (`[S-STY-3]`) |

---

## 7. Units cheat-sheet

`units.nim` defines **three** unit types and nothing else: `Px`, `Ms`, `Deg`.
"A plain number still means px, ms or degrees, but a value WITH a unit must be the right one:
`width = 200.ms` is a compile error, not a silent bug."

| CSS unit | Accepted by Yantra? | Convert it to | Exact syntax | Notes/limits |
|---|---|---|---|---|
| unitless `0` | yes | `0` | `pad = 0` | always valid |
| `px` | **yes** | `Px` | `width = 400` or `width = 400.px` | `units.nim:10` — `template px*(x: SomeNumber): Px` |
| `rem` | no | a computed px number | `minHeight = 24` | PORT-NOTES line 1097 — `min-height: 2.4rem` at `html{font-size:10px}` → `minHeight = 24`. Do this conversion **once, at port time, and cite the CSS next to the constant** — that is exactly what the port did |
| `em` | no | a computed px number | `size = 18` | resolve against the *parent's* `size`, which Yantra does not cascade, so you must track it |
| `%` | no | a computed px number | `width = <n>` | the wire types are `int32` (width/pad) and `float32` (margin/inset); there is no percent anywhere in `PropTable` |
| `vh` | no | the window height | `sized w, h:` or an explicit `height` | PORT-NOTES line 620 — upstream's dialog is "centred, `top: 15vh`" and line 621 has "a 4rem header, 1rem content padding, a 5rem button bar" — **every one of these was resolved to a number at port time**. PORT-NOTES line 791 records what happens when a `vh` is wrong: "`vh = 1000.0`, which made every zoom jump to the wrong place and made Fit Window …" |
| `vw` | no | the window width | | same |
| `vmin` / `vmax` | no | | | |
| `dvh` / `svh` / `lvh` | no | | | no dynamic-viewport concept |
| `fr` | **yes — but only in a grid column string** | a grid track | `grid "160 1fr 2fr"` | `docs/spec/style.md` §9 — "`Nfr` is a share of what is left after pixels… Shares never go below zero" |
| `auto` (as a length) | no | | | see the `margin: auto` row in §1.7 |
| `deg` | **yes** | `Deg` | `rotate = 45` or `45.deg` | `units.nim:14` — degrees, **clockwise** |
| `turn` | no | `× 360` | `rotate = 0.25 * 360` | |
| `rad` | no | `× 57.2958` | `rotate = 1.57 * 57.2958` | |
| `grad` | no | `× 0.9` | | |
| `ms` | **yes** | `Ms` | `transition = 200` or `200.ms` | `durationProps = ["transition"]` (`dsl.nim:94`) — **only `transition`** takes a duration unit |
| `s` / `secs` | **yes** | `Ms` | `transition = 0.2.s` | `units.nim:12-13` — `s(x)` and `secs(x)` both multiply by 1000 |
| `calc(…)` | no | a computed number | `maxWidth = 62.5` | PORT-NOTES line 1099 — `calc(4.25rem + 2rem)` → "42.5 + 20" px |
| `min()` / `max()` / `clamp()` | no | a computed number or a `sized` block | `sized w: if w < 640: …` | `docs/spec/style.md` §9.1 is the intended replacement |
| CSS custom property `--x` | no | a `Theme` field or a Nim const | `fill = theme().accent` | `dsl.nim:97-98` — 14 theme words: `bg sidebar surface surface2 surface3 line text muted faint accent accentText accentSoft danger success` |
| `currentColor` | no | the same expression twice | | |
| `#hex` colour | **yes** | `0xRRGGBB` int | `fill = 0x2B3037` | PORT-NOTES line 64 — "both side panels `#2B3037`"; these are the literal ported values |
| `rgb()` / `rgba()` | `rgba()` only | `rgba(0xRRGGBB, 0..1)` | `fill = rgba(0x2B3037, 0.5)` | `style.nim:23-27` |
| `#rgb` (3-digit) | no | expand by hand | `0x2B3037` | |
| `hsl()` | no | compute it | | PORT-NOTES line 1063 — the colour work was done by hand and re-verified against an oracle |
| unit mismatch (`width = 200.ms`) | a **compile error** | — | — | `units.nim:31-32` — `Y020 this prop is a length: use px (e.g. 16.px), not ms` |
| duration prop given a px | a **compile error** | — | — | `Y021` (`units.nim:36`) |
| angle prop given a px or ms | a **compile error** | — | — | `Y022` (`units.nim:41`) |
| arithmetic on units | `2.px + gap`, `1.5.secs` | — | | `units.nim:19-23` — `+`, `-`, `*` are defined on `Px` and `Ms` |

**Which props are lengths** (`dsl.nim:89-93`, `lengthProps` — a bare number on one of these
goes through `lengthOf`, and a `Px` is required if you write a unit):

```
width height minWidth maxWidth minHeight maxHeight pad padding
padX padY padTop padRight padBottom padLeft margin marginX marginY
marginTop marginRight marginBottom marginLeft gap spacing
radius border top left right bottom x y size fontSize
blur backdropBlur
```

**Which props are durations:** `transition` only. **Which are angles:** `rotate` only.

> **The `%`/`vh`/`rem`/`calc` conversion rule, from the port that actually did it.**
> PORT-NOTES line 1093 gives the root size (`html{font-size:10px}`) and the table that
> follows converts every rule by hand, with the CSS quoted next to the number
> (`min-height: 2.4rem` → 24; `max-width: calc(4.25rem + 2rem)` → 42.5 + 20;
> `margin: .75rem 0` → 7.5). The same file records what you lose by guessing:
> the 50px sidebar bug (line 67-89, "RIGHT_W was 260 in `app.nim` with no citation")
> was a margin/padding reading error, found by scanning a live framebuffer for the
> panel's edge — not by reading the CSS again.

---

## 8. `NOT SUPPORTED YET` — the complete index, with fix difficulty

Every gap in one place, so a port can be triaged without re-reading the tables.
Difficulty is my estimate of the engine work, not the API work.

### 8.1 Trivial (add a prop, the renderer call already exists or is one line)

`align-self` · `order` · `flex-basis` · `row-gap` / `column-gap` · `border-style` (dashed/dotted) ·
`box-shadow` spread · `box-shadow` inset · multiple `box-shadow` · `margin: auto` ·
logical `margin-*` / `padding-*` · `outline` / `outline-offset` · `backdrop-filter` saturate/brightness ·
`filter: hue-rotate|sepia|grayscale|invert` · `animation-play-state` · `visibility: hidden` ·
`transition-delay` · `turn`/`rad` unit templates · `text-align: justify` · `text-indent` ·
`white-space: nowrap` · `flex-wrap: wrap-reverse` · `row-reverse` in the DSL ·
`transition-property` list · `cubic-bezier` curves · `steps()` easings.

### 8.2 Medium (a new prop plus a real paint or layout path)

`position: fixed` · `float` / `clear` · `clip-path` · `mask` / `mask-image` ·
`background-image` / `background-size` / `background-position` / `background-repeat` ·
`background-clip` (a shape other than the node radius) · `multiple backgrounds` ·
per-side `border-width` / `border-color` · per-corner and elliptical `border-radius` ·
`linear-gradient` with >2 stops · `repeating-linear-gradient` · `radial-gradient` ·
`conic-gradient` · `filter: drop-shadow` (alpha-following) · `text-decoration` ·
`letter-spacing` / `word-spacing` · `font-stretch` · `font-feature-settings` ·
`@keyframes` with multiple channels or arbitrary stops · `transform: skew` / `matrix` ·
`transform-origin` · `aspect-ratio` · `box-sizing: content-box` · `%` lengths ·
`clamp()` / `min()` / `max()` · `vh` / `vw` / `dvh` · `display: inline` / `inline-block` ·
`fit-content` · `repeat(auto-fill, minmax(…))` · grid explicit rows / row spans / `grid-area` ·
`backdrop-filter` beyond blur · `isolation: isolate` · `:focus-within` ·
scroll-linked and shared-element motion · `writing-mode` / vertical text ·
`font-family` fallback lists.

### 8.3 Hard (a new layout mode, a new text engine, or a new data source)

`display: block` · `display: table` / `table-layout` · floats with `shape-outside` ·
multi-column · `vh`-relative fixed positioning that survives ancestor scroll ·
`hyphens: auto` (needs a hyphenation table in the wasm module) ·
`unicode-bidi` (a real bidi algorithm) · embedded webfonts (a loader plus the bytes in the module) ·
`border-image` · `clip-path: polygon()` · `::first-line` / `::selection` paint ·
`:has()`, `~`, or any cross-cutting selector (`[data-*]` queries across siblings).

### 8.4 The universal escape hatch

**When a visual feature has no prop, it has a shader.** `docs/spec/style.md` §8:

```nim
panel(shader = sksl"""
  uniform float2 size;   // its box
  uniform float time;    // seconds
  half4 main(float2 p) { return half4(half(p.x / size.x), 0.3, 0.8, 1); }
""")
```

`engine.nim:1670-1679` shows the whole contract: the shader **is** the fill; the border is still
stroked on top; a shader that does not compile shows its error over the app in dev builds; and a
shader whose source mentions `time` sets `e.animating = true` so the frames keep coming.
This covers skews, clipping, multi-stop gradients, conic gradients, masks, `::selection` and
`text-shadow`-on-glyphs in one mechanism.

**And the honesty rule that goes with it.** PORT-NOTES lines 2312-2326, quoted in full because it
is the standing caveat for all shader work:

> **THE CAVEAT STANDDS AND MUST NOT BE LOST.** Nothing here has ever run on a real GPU. There is
> no WebGL context available in this repo … so the oracle is a `Math.fround` transcription of the
> GLSL, not a driver. That proves the Nim and the JS execute the same algorithm in the same
> precision. It does **not** pin: a driver's `sin` / `pow` / `exp` approximation, the hardware
> bilinear unit's **8.8 fixed-point** weighting, `float → unorm8` rounding on store, the
> spec-undefined **reversed `smoothstep`** case.

---

## 9. Porting checklist (the order that actually works)

Derived from how miniPaint's port went, not from a generic style guide.

1. **Pick the node kind before any value.** `row` vs `column` vs `panel` vs `stack` vs `grid` is
   the `display` decision, and it is the only structural decision CSS makes that Yantra does not
   make for you. PORT-NOTES line 58: "Grid | `submenu / sidebar_left, main, sidebar_right`" became
   `grid "auto 1fr auto"`.
2. **Convert every unit at port time and cite the CSS next to the constant.** The `rem`/`calc`/`vh`
   table (§7) is the method. PORT-NOTES line 1098: the value now "lives in `layerpanel.nim` beside
   the CSS it comes from".
3. **Set `alignItems = stretch` on any `row:`** unless you want centre. `engine.nim:473` defaults a
   row to `yaCenter`; CSS defaults to `stretch`. This is the single most common CSS→Yantra surprise.
4. **Box-sizing is already `border-box`.** Do not "fix" it.
5. **Relative positioning is the default.** `position: absolute` → `absolute = true` **plus** insets;
   inside a `stack:` it is automatic.
6. **`margin: auto` does not exist.** Centre with the parent (`justify`/`alignItems`), not with margins.
7. **One gradient, two stops, one angle.** For anything else: a shader, or a nested node.
8. **One shadow, no spread, no inset.** Two shadows → two nodes.
9. **One border width and colour for all four sides; one radius for all four corners.**
10. **Pseudo-elements become real child nodes.** PORT-NOTES line 487-490 is the worked example.
11. **`::after` on an icon is often a background image** — that becomes an `image`/`icon`/`path` node.
12. **Responsive rules become a `sized` block**, never a breakpoint prop.
13. **Verify against the real surface, not by reading the code.** PORT-NOTES lines 1788-1789 states
    the rule both of its own bugs point at: "**when a measurement contradicts the source, the source
    wins and the measurement is suspect.** Reading the code is cheaper than chasing a bad probe." —
    and then also records the opposite, where reading the code found the bug the probe had hidden
    (the 50px sidebar, the gradient stop order, `grep` returning 0 hits because the test file was
    named differently than the greppers guessed).

---

## 10. Source-verification log — every open question, resolved or deleted

**This section used to be a list of things this chapter could not settle. It no longer is.** Every
row below was reopened and settled by reading the source on 2026-10-04; the resolution and its
`path:line` are given. Where the original claim turned out to be **wrong**, that is stated — a
corrected claim is worth more than a deleted one, so rows were corrected rather than dropped, but
each correction names what it replaced.

| # | Question | Resolution |
|---|---|---|
| 1 | The gradient **zero point** | **CLOSED in source.** Yantra `0°` = **to right**, by `skia_shim.cpp:431-437` (`dx = cos(a)*w/2, dy = sin(a)*h/2`, drawn centre−d → centre+d) and confirmed by the passing assertion in `libs/nimskia/tests/t_skia.nim:54-56` (angle 0 → red at x=1, blue at x=62). **Yantra = CSS − 90.** |
| 2 | ~~Does `Yantra angle = CSS angle + 45°`?~~ | **CLOSED in source. The "+45" claim was wrong** — it is CSS − 90, from row 1. `to top right` (CSS 45deg) is Yantra **315**, not 45. |
| 3 | Is `lineHeight` a **multiplier** or a **px value**? | **RESOLVED — a multiplier.** `libs/nimskia/src/nimskia.nim:98` `lineHeight*: float32   ## multiple of the size`; `skia_shim.cpp:96` `float lineHeight = 0;           // multiple of the font size; 0 = the font's own`; `skia_shim.cpp:145` `if (o.lineHeight > 0) { ts.setHeight(o.lineHeight); ts.setHeightOverride(true); }`. Corollary the old row missed: the default lives in **`render/native/engine.nim:397`** `lineHeight: n.num(P_LINEHEIGHT, 0)` — neither `sdk/core/wire.nim` (a generated enum of wire ids only) nor `protocol/schema.nim` carries a default value. `0` = the font's own. Written up in §4.2. |
| 4 | The `direction` value→enum mapping | **RESOLVED: `0` = as its parent, `1` = LTR, `>= 2` = RTL.** `protocol/schema.nim:89` `# 0 as its parent, 1 left-to-right, 2 right-to-left (layout mirrors; text is laid out RTL)`; `engine.nim:521-522` `if n.has(P_DIRECTION) and n.num(P_DIRECTION, 0) > 0: y.setDirection(if n.num(P_DIRECTION, 0) >= 2: dirRTL else: dirLTR)`. Note the test is **`>= 2`, not `== 2`** — any int of 2 or more is RTL. There is **no** `direction = rtl` DSL mapping: `sdk/ui/dsl.nim` has no `direction`/`rtl` case, so the value must be a number. |
| 5 | Do `sticky` / `stickyLeft` take a px offset or act as a switch? | **RESOLVED, and the old premise was wrong** — the old row said "no renderer line for them was found in `engine.nim`". They *are* implemented, as a **px offset**, and behave like CSS `position: sticky; top: Npx`. `engine.nim:1071-1072` `if cn.has(P_STICKY) or cn.has(P_STICKYLEFT):` / `# sticky (P6): held at the view's edge while its container scrolls past, never out of that container`; `engine.nim:1075` `let top = max(clip.y, e.scrollY) + cn.num(P_STICKY, 0)`; `engine.nim:1076` `if b.y < top: b.y = max(b.y, min(top, pb.y + pb.h - b.h))` — the trailing `min(…, pb.y + pb.h - b.h)` is what stops it escaping its own container. `stickyLeft` is the same on x (`engine.nim:1077-1079`). |
| 6 | Does `smooth = true` affect programmatic scrolling? | **RESOLVED — yes, programmatic only, and only after the first placement.** Three gates: `engine.nim:1103` `if cn.has(P_SCROLLY) and not (cn.flag(P_SMOOTH) and e.placedOnce):`, `engine.nim:1112` `if not (cn.flag(P_SMOOTH) and e.placedOnce):`, and the animated branch `engine.nim:1500` `if abs(y - was) > 0.01 and n.flag(P_SMOOTH) and e.placedOnce and not e.reducedMotion and …`. Nothing in these three lines touches wheel or trackpad input. Written up in §1.6. |
| 7 | Does `fit` accept the *string* `"contain"`? | **RESOLVED — it follows from the code.** `sdk/ui/dsl.nim:169-171` `if norm == "fit" and propVal.kind in {nnkStrLit, nnkTripleStrLit}:` / `let w = propVal.strVal.toLowerAscii` / `propVal = newLit(if w == "cover": 1 elif w == "fill": 2 else: 0)`. Any unknown string, `"contain"` included, becomes `0`, and `protocol/schema.nim:59` `# how media fills its box: 0 contain, 1 cover, 2 fill`. |
| 8 | Is there a font registry in `sdk/ui/`? | **RESOLVED — there is none, and there is one specific mechanism instead.** Exhaustive search for `MakeFromData`/`loadFont`/`fontFile`/`fontPath`/`registerFont`/`addFont`/`@font-face`/`woff`/`ttf`/`otf` across `*.nim`/`*.cpp`/`*.c`/`*.h`/`*.js`/`*.mjs`: zero hits in `sdk/`, `render/`, `host/`, `libs/`. What exists is a hardcoded wasm build-time download of Inter + JetBrains Mono (`tools/build-web.sh:34-37`) plus the `/fonts` alias registration at `skia_shim.cpp:63-82`. Written up in §4.1. |
| 9 | Do `font`, `weight`, `size` cascade to descendant text nodes? | **RESOLVED — nothing cascades, and `color` does not either.** `engine.nim:385` `proc fontSize(n: tree.Node; k: int32): float32 = n.num(P_FONTSIZE, if k == K_PATH: 24 else: 15)` — the fallback is a **kind-based constant**, not a parent lookup; `engine.nim:395-398` builds `textStyle(n)` from the node's own props only; `engine.nim:401-404` `ink(n, d)` falls back to the engine default `d`. The tree walk that *does* carry style downward carries exactly one prop — RTL: `engine.nim:738` `cn.rtl = if cn.num(P_DIRECTION, 0) > 0: cn.num(P_DIRECTION, 0) >= 2 else: parentRtl`. Written up in §0 and §4.1. |
| 10 | Negative margins: does Yoga honour them through `setMargin`? | **RESOLVED — yes, nothing clamps and Yoga consumes margin as a signed float.** See §1.7 for the full chain `engine.nim:508-511` → `libs/nimyoga/src/nimyoga.nim:147` → `third_party/yoga/yoga-3.1.0/yoga/style/Style.h:145-147`, and the two decisive layout lines `yoga/algorithm/CalculateLayout.cpp:1289` (`availableWidth - marginAxisRow` — a negative margin widens the box) and `CalculateLayout.cpp:1625-1628` (a negative leading margin shifts the child backwards). Honest limit: **no Yoga regression test covers a negative margin**; the whole vendored `third_party/yoga/yoga-3.1.0` tree was searched for one. |
| 11 | Is there an `overflow-x`/`overflow-y` path in the **web** runner? | **RESOLVED — no, and the web target papers over nothing here.** `web/runner/runner.js:529` `case P.SCROLL: if (val) st.overflow = 'auto'; break;` and `:530` `case P.CLIP: if (val) st.overflow = 'hidden'; break;` — the identical single-axis mapping the native engine has (`engine.nim:489-490`, `:494`). A grep of all of `web/` for `overflow|viewport|sticky` returns only those two lines, `runner.js:62` (`.y-window{…overflow:auto…}`), and the two static viewport metas. So §1.6's "`overflow-x`/`overflow-y` is hard" applies to **both** targets. |
| 12 | `isPropAllowedOnNode` rejects a prop on the wrong node kind at compile time with `Y001`; check `allowedNodes` before writing. | **RESOLVED — the generated table is in the tree, at two paths.** `protocol/gen.nim:90-94` `proc writePropsRef() =` / `let md = formatPropsMarkdown()` / `writeFile("props.md", md)` / `createDir("../docs/HOW_IT_WORKS")` / `writeFile("../docs/HOW_IT_WORKS/props.md", md)`. Both outputs exist and are current, holding the same table: `protocol/props.md` and `docs/HOW_IT_WORKS/props.md` (line 118 of each is the `focusAt` row — `pFocusAt`, string, `Input,TextArea`). The old row's parenthetical was right that there is no `docs/props.md`. |
| 13 | *added* — `windowAction`'s int values | **RESOLVED: 1 minimise, 2 maximise/restore, 3 close, 4 fullscreen.** `libs/nimsdl3/src/sdl_shim.c:297-302`. 2 and 4 are **toggles**; 3 pushes an `SDL_EVENT_QUIT`. Written up in §11. |
| 14 | *added* — `seek`'s units | **RESOLVED: float32 seconds**, and only applied on a *changed* value. `engine.nim:3766`, `:3770`, `:3763`. Written up in §12. |
| 15 | *added* — `focusAt`'s accepted values | **RESOLVED, and the documented form was wrong.** It is a caret byte index, not a keyword — `engine.nim:1591`. `protocol/schema.nim:104`'s own comment `Input/TextArea: "caret#n"` describes a literal whose prefix does not parse (`parseInt("caret")` fails → caret 0); the working form is `"<index>#<counter>"`, as built by `sdk/ui/blocks.nim:65`. That schema comment is now wrong and is **left unmodified here** (out of scope for this chapter). Written up in §13. |
| 16 | *added* — `Chord` round-trip | **DELETED — there is no round-trip, and `Chord` is not an SDK prop, so the row never belonged in this chapter.** `sdk/ui/keybind.nim:17-19` defines `Chord`, and `keybind.nim:67-77` `formatChord` encodes it to `"Ctrl+Shift+K"`, but **there is no decoder anywhere in the tree** — no proc takes a string back to a `Chord`, so a binding cannot be reloaded from a stored chord. Separately, `keybind.nim`, `keypicker.nim` and `settings.nim` are not in `sdk/yantra.nim:39-40`'s import/export list, so `import yantra` does not give an app author a `Chord` at all. See `reference/11-input-pointer-and-keys.md`. |
| 17 | *added* — is `rgba` the only colour entry point? | **RESOLVED — yes; there is no colour-space conversion of any kind in the SDK.** Grepped `sdk/`, `render/` and `libs/` for `hsl|hsla|oklch|colorSpace|ColorSpace|linear_srgb|parseColor|fromHsl`: **zero hits in all three.** `sdk/ui/style.nim:23-27` `proc rgba*(rgb: int; alpha: float): int` is the only colour constructor in the SDK. The only `hsl` in the tree is app-level code that wrote its own — `apps/gallery/app.nim:126-127` `proc hsl(h, s, l: float32): uint32 =`, commented "CSS hsl(h, s%, l%)" — which is the recommended workaround. `sRGB` appears only on the 3D/Filament path (`render/native/scene3d.nim:7` "An sRGB 0xAARRGGBB colour as linear 0..1"), never as a 2D colour input. |

> **Note on the web target.** `docs/spec/style.md` §9.1 says "the web runner uses CSS grid"
> (and `ResizeObserver` for `sized`), so the open question was whether a CSS-backed runner papers
> over any of the `NOT SUPPORTED YET` rows above. **Checked in source on 2026-10-04: it does not.**
> The runner is a hand-written DOM mapper, and `overflow` is the clearest case — `web/runner/runner.js:529-530`
> maps the same single-axis `auto`/`hidden` the native engine has, so `overflow-x`/`overflow-y` is
> unsupported on **both**. `table(parent)` and `radio(parent, …)` have no web mapping either. Treat the
> `NOT SUPPORTED YET` rows as true for both targets unless a row names one explicitly.

---

## 11. The window itself — `<html>`/`<body>` props

These have **no CSS counterpart at all**, so they are listed as the inverse mapping: HTML →
Yantra. All from `PropTable` (`allowedNodes: Window` unless noted).

| HTML/CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `<title>My App</title>` | `app("My App")` | `app("Weather", net = "…")` | window title |
| `<body style="width:100vw;height:100vh">` | the window fills itself | `app("Name")` | no size props needed; `width`/`height` are optional |
| `<meta name="viewport">` | **NOT SUPPORTED YET** | — | no SDK prop for it, and the runner does not inject one. Grepped `sdk/`, `render/web/` (which contains only `standins.nim` and `web_main.nim`) and all of `web/` for `viewport`: the only occurrences are **hand-written static HTML** — `web/runner/app.html:5` and `web/engine/index.html:3`, both `<meta name="viewport" content="width=device-width, initial-scale=1">`. The runner appends exactly one node to the document at runtime, and it is a `<style>`, not a meta: `web/runner/runner.js:88-91` `const s = document.createElement('style'); … document.head.appendChild(s);`. `web/runner/index.html` has no viewport meta at all. |
| `window.resizeTo()` | `width`/`height` on the window | `app("Name", width = 800, height = 600)` | `width`/`height` are `int32` and allowed on `"*"` |
| a frameless window | `frameless = true` | `app("Name", frameless = true)` | `PropMeta(frameless, Frameless, bool, Window)` |
| a maximise/restore button | `windowAction = <n>` | `app("Name", windowAction = 1)` | int32 on `"*"` (`protocol/schema.nim:373`). **The values are 1 minimise, 2 maximise/restore, 3 close, 4 fullscreen** — proved by the shim itself, `libs/nimsdl3/src/sdl_shim.c:297` `/* 1 minimise, 2 maximise / restore, 3 close, 4 fullscreen on / off. */`, with `:299` `if (op == 1) SDL_MinimizeWindow(y->win);`. Three details that matter: **2 and 4 are toggles, not setters** (`:300` `if (SDL_GetWindowFlags(y->win) & SDL_WINDOW_MAXIMIZED) SDL_RestoreWindow(y->win); else SDL_MaximizeWindow(y->win);`; `:302` `SDL_SetWindowFullscreen(y->win, !(SDL_GetWindowFlags(y->win) & SDL_WINDOW_FULLSCREEN))`); **3 pushes an `SDL_EVENT_QUIT`** rather than closing directly (`:301`); and any other int falls through all four branches and does nothing. Chain: `engine.nim:3059-3060` → `yantra_run.nim:59` → `nimsdl3.nim:150`. |
| `<button id="fullscreen">` | `fullscreen = true` | `app("Name", fullscreen = true)` | bool, Window |
| a custom titlebar drag strip | `dragRegion = true` | `row(dragRegion = true)` | bool, `"*"` — the region the OS drags the window by |
| a native menu bar | `menu = "File Edit View"` | `app("Name", menu = "…")` | string, Window |
| `<body>` background | `fill` on the root node | `app("Name")` + root props | `PropTable` allows `fill` on `"*"` |
| `<html style="color-scheme: dark">` | `scheme = "dark"` | `app("Name", scheme = "dark")` | string, Window |
| a taskbar/dock badge | `badge = <n>` | `app("Name", badge = 3)` | int32, Window |
| CORS / `<meta http-equiv>` | `net = "api.open-meteo.com"` | `app("Weather", net = "api.open-meteo.com")` | `docs/spec/style.md` §10 — "An app reaches only the hosts its window lists in `net`… A bare `*` allows nothing" |
| browser find-in-page (Ctrl+F) | `find` / `findIndex` | `app("Name", find = "a", findIndex = 3)` | int32 + string, Window |
| pointer lock (FPS games) | `pointerLock = true` | `app("Name", pointerLock = true)` | bool, Window |
| `<meta name="theme-color">` | a `Theme` + `setTheme` | `setTheme(dark)` | `docs/spec/style.md` §4 — "one click, no reload, no engine involvement" |
| `window.onbeforeunload` | `ondismiss` → `evDismiss` | `onDismiss: …` | `dsl.nim:70-75` |
| routing (`history.pushState`) | `sdk/ui/router.nim` | `routes(parent, r, @[Route(pattern: "/chat/:id", build: …)])` + `r.push("/chat/1")` | **There is no `route("home")` proc** — I read `sdk/ui/router.nim` in full (105 lines) and its exported API is `newRouter` (`:21`), `current`/`canPop` (`:24-25`), `push`/`pop`/`replace`/`reset` (`:33`/`:37`/`:42`/`:46`), `deepLink`/`openLink` (`:52`/`:63`), `match` (`:65`), `routes` (`:84`), and the types `Router`/`Route`/`Params` (`:15`/`:12-14`/`:11`). Exported from `import yantra` (`sdk/yantra.nim:40`). Register patterns with the **plural** `routes(parent, r, table, notFound)`; navigate with `r.push(path)`. It is not a DSL construct — `sdk/ui/dsl.nim` has zero router references, which is why the working example `examples/shell/nav.nim:24-27` is a `proc Pages(parent: Node)` and not a `page:` block. |

## 12. Media, canvas and 3D — HTML elements, not CSS

| HTML/CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `<img src>` | `image "path"` | `image("a.png", fit = cover)` | `dsl.nim:434-439`; `PropTable` `source → pSource`, allowed on `Image,Video,Model,Flex,Chart,Drawer,AppView` |
| `background-image` (see §2.1) | `image` inside a `stack` | `stack: image("bg.png", absolute = true)` | the portable background-image idiom |
| `<img srcset>` | **NOT SUPPORTED YET** | — | one `source` per node; use a `sized` block to switch. **Fix difficulty: easy.** |
| `<img loading=lazy>` | **NOT SUPPORTED YET** | — | `lazy` exists for lists, not for single images |
| `<video>` | `video "clip.mp4"` | `video("clip.mp4", fit = cover, loop = true)` | `dsl.nim:404-410` |
| `autoplay` | `playing = true` | `video("c.mp4", playing = true)` | `PropMeta(playing, Playing, bool, Video,Audio,Synth)` |
| `loop` on media | `loop = true` | `video("c.mp4", loop = true)` | `PropMeta(loop, Loop, bool, Video,Audio)` |
| `<audio>` | `audio "track.mp3"` | `audio("t.mp3", volume = 0.5)` | `sdk/yantra.nim:165-167`; `playing`/`seek`/`volume`/`muted` are the audio props |
| a waveform display | `waveform = <n>` | `audio("t.mp3", waveform = 1)` | int32, Audio |
| native media controls | **NOT SUPPORTED YET** | — | build a `row` of `button`s over the media node using `playing`, `seek`, `volume`, `muted`. **`seek` is float32 SECONDS** (`protocol/schema.nim:350` `propType: "float32"`), clamped to the clip length and applied **only when the value changes**: `render/native/engine.nim:3766` `let t = if p.duration > 0: clamp(float64(v), 0, p.duration) else: max(0.0, float64(v))`, and the units are fixed by `engine.nim:3770` `if not p.paused: p.startAt = e.now - t * 1000` — `e.now` is milliseconds, so `t` is seconds. Re-issuing the same number does nothing (`engine.nim:3763` `if not p.seekKnown or v != p.seekSeen:`); nudge it or reset `p.ended`. |
| `<canvas>` | `canvas(draw = d.cmds, width = 400, height = 300)` | `canvas(draw = cmds, width = 400, height = 300)` | `dsl.nim:350-354` — "2D drawing (`paint.nim`'s `Draw`: paths, shapes, text, images, layers, raw pixels, blend modes); pointer events on it" |
| `ctx.globalAlpha` | `opacity` on the canvas node | `canvas(opacity = 0.5)` | |
| `ctx.filter` (a CSS filter chain on a canvas) | not a prop | — | PORT-NOTES §"The ten CSS canvas filters" measured ten Instagram filter chains ported into `fx_canvas.nim` at 101×67 against a real-Chrome oracle: `valencia` and `gingham` **byte-exact** (27 068/27 068 channels), worst error across all ten **6/255**, down from 227/255. That is *app-level* work; there is no `ctx.filter` prop |
| `<svg viewBox>` + `<path d>` | `path(d = "…", size, color, stroke)` | `path(d = "M10 10 H 90 V 90 H 10 Z", size = 24, color = accent, stroke = 2)` | `PropTable`: `d → PathData` (string, Path), `stroke → StrokeWidth` (float32, Path) |
| `<svg><g transform="matrix(…)">` | **NOT SUPPORTED YET** at runtime | — | PORT-NOTES line 504-509 is the honest port note: "Nested `<g>`, `<polygon>`, `<rect>`, `<circle>` and `matrix()` transforms are all resolved with the transforms **baked into the coordinates** — dropping them would place every icon wrongly. Unsupported constructs raise rather than silently emitting bad artwork." So an icon pipeline must flatten transforms *before* `d`. **Fix difficulty: easy** to bake, medium for runtime transforms |
| an icon font | `icon "search"` | `icon "search", size = 18, color = accent` | `dsl.nim:396-403` — from the standard icon set; `pStrokeWidth` defaults to 1.8 |
| a transparent PNG on a dark background | swap the source, or `blend = plus` | `image("i.png", blend = plus)` | PORT-NOTES line 518-522: `--menu-icons-filter: invert(1)` — "The SVGs are authored **black on transparent**, so `invert(1)` is what makes them visible at all; drawing them unmodified renders black-on-dark." With no `invert` prop, the port changed the *source*. See §2.4 |
| `<webgl>` / CSS 3D | `scene3d:` | `scene3d(sky = 0x87CEEB, fog = 0.02):` | `dsl.nim:337-349` — Filament. `box`/`sphere`/`plane`/`cylinder`/`mesh` are placed with `posX..posZ`, `rotX..rotZ`, `sizeX..sizeZ`; "Filament draws it; the objects are not laid out" |
| `transform: perspective()` on a page | `scene3d` / `camera(fov = …)` | `camera(fov = 60)` | `scene3d` is a separate surface, not a transform mode on `panel`s. **Fix difficulty: hard.** |
| a zoomable image viewer | `zoomable = true` | `image("map.png", zoomable = true)` | `PropMeta(zoomable, Zoomable, bool, Image)` |
| `<iframe>` | `appView "todo"` | `appView("todo", grow = 1)` | `dsl.nim:426-429`; `docs/spec/style.md` §6 — another app, sandboxed, drawn in this box; "If it traps, only it stops and its box says so" |
| an HTML `<table>` | `table(parent)` | `table(parent)` | **It honours no styling props at all, because the native engine has no code path for it.** `sdk/yantra.nim:140-142` is the whole constructor — `proc table*(parent: Node): Node =` / `## Data table. Set columns/rows via properties.` / `make(nkTable, parent)` — a bare node kind (`sdk/core/wire.nim:34` `nkTable = 28`) that sets no props. Three independent confirmations that nothing can be styled on it: (1) `PropTable` names `Table` as a node kind (`protocol/schema.nim:12`) but **no** `PropMeta` in `schema.nim:260-373` has `Table` in its `allowedNodes`; (2) grepping `render/native/engine.nim` for `K_TABLE`/`nkTable` returns **no matches** — every `Table` hit in that file is Nim's own `Table` type (`e.boxes`, `e.clips`, …), not the node kind; (3) the engine's draw switch (`engine.nim:1238-1983`) has no `K_TABLE` arm. It is not drawn at all. **Fix difficulty: hard** — a new node kind needs the renderer mapping + a test in the same task (AGENTS.md rule 6). |

### 12.1 Inside a `<canvas>`: the `Draw` layer is not the node layer

Everything in §2 that said "safe on a node prop" says the opposite here, and three more things
change. A `canvas` draw list is a string of verbs replayed by
`libs/nimskia/src/skia_shim.cpp`'s `runCmds`; there is no prop table, no `PropTable`, and no
`argb()` normalisation. The sibling chapter that goes deep on this is
`reference/09-canvas-and-draw.md`.

**1. Colour alpha — every `Draw` verb, with no exception.**
Each of `fill`(`paint.nim:53`), `stroke`(`:55`), `rect`(`:57`), `circle`(`:59`), `line`(`:61`),
`text`(`:63`), `image`(`:65`) and `svgPath`(`:46`) takes `argb: uint32` in **AARRGGBB**, and
`skia_shim.cpp:1327` does `paint.setColor(SkColor(argb))` with no fix-up. A CSS hex pasted in
(`0xF7F9FB`) has alpha `0x00` and is fully transparent. Use the `hex()` helper from the alpha
byte box at the top of §2 (`apps/chess/app.nim:100`).

**2. `Draw.text`'s `y` is the top of the paragraph line box — not the baseline.**
`libs/nimskia/src/skia_shim.cpp:291` is `p->paint(canvas, x, y)`, and `Paragraph::paint` treats
`y` as the line box's top edge.

> **CORRECTED 2026-10-03.** What this chapter used to leave implied — that a `Draw` text `y`
> behaves like a DOM/SVG baseline `y`, so the CSS rule "`dominant-baseline: text-before-edge` → the
> given `y`" transfers straight across. Evidence: `libs/nimskia/src/skia_shim.cpp:291`
> (`p->paint(canvas, x, y)`) puts `y` at the top of the paragraph, while
> `libs/nimskia/src/nimskia.nim:76` documents the opposite — *"Draws `s` with its top-left at
> (x, y)"* is what the wrapper says, and calling `y` a baseline is wrong in either reading. **The
> correct rule** is the measured offset, verified at `size = 12, 24, 48` (default typeface and
> weight only — a different family or weight moves these):

  | Feature | Distance from `y`, in units of font size `S` |
  |---|---|
  | cap top | `y + 0.375·S` |
  | x-height top | `y + 0.583·S` |
  | **baseline** | **`y + 1.0833·S`** |
  | descender bottom | `y + 1.333·S` |

  So a CSS `y` that names a baseline becomes `yantra_y = wantedBaselineY - 1.0833 * size`. A CSS
  `y` that names the top of the text (CSS `text-before-edge`, and the default `top` of a
  positioned box) maps across **unchanged**.

**3. There is no text measurement API, so centring, right-alignment and wrapping must be
ESTIMATED inside a `canvas`.** `sdk/ui/paint.nim:63` is `proc text*(d: Draw; x, y, size: float32;
argb: uint32; s: string; weight = 400): Draw` — it returns a `Draw` and nothing else, and it has
**no `align` parameter**. The shim makes that structural, not just a missing default:
`skia_shim.cpp:1354` calls `yk_text_draw(c, s, len, size, wt, 0, x, y, col, 0)` — the last `0` is
the native `align` argument, hard-coded to left. `measureText` exists only on the native side
(`libs/nimskia/src/nimskia.nim:68` and `:122`); there is no `measureText` anywhere under `sdk/`.
Consequences for CSS:

| CSS inside a `canvas` | Status in a `Draw` list | What to do |
|---|---|---|
| `text-align: center` / `right` on drawn text | **NOT SUPPORTED YET** | estimate the advance (a per-character table, or `len * 0.55 * size` as a first cut) and shift `x`. Or draw it as a `text` node instead, where `align = center` is real |
| `text-wrap` / wrapping at a width | **NOT SUPPORTED YET** — no measure, so no wrap point | break the string yourself and emit one `text` per line, or use a `text` node with `maxLines` |
| `ctx.measureText(s).width` | **NOT SUPPORTED YET** | see §2.2 A of `reference/16-engine-limits-and-workarounds.md` for the kerned-advance table a real port hand-built |

**4. Polygon and ellipse: two real gaps, and one thing that is NOT a gap.**
There is **no filled-polygon primitive**. A polygon is `moveTo`(`:28`) → `lineTo`(`:29`) →
`close`(`:45`) → `fill`(`:53`), which is a complete workaround — this is the canvas idiom, not a
missing feature. There is **no `ellipse` proc**: `circle`(`:59`) emits `"E"` with `rx = ry = r`,
so an axis-aligned ellipse needs either four `curveTo`(`:35`) calls or an `svgPath`.

> **CORRECTED 2026-10-03.** The widely-repeated claim that `svgPath` is missing is **wrong**.
> `sdk/ui/paint.nim:46` declares `proc svgPath*(d: Draw; path: string; x, y, scale: float32;
> argb: uint32; strokeWidth = 0'f32): Draw` — "SVG path data (any command set Skia parses:
> relative, H/V, smooth curves, arcs) at (x, y) scaled by `scale`. Filled unless `strokeWidth > 0`"
> — and `libs/nimskia/src/skia_shim.cpp:1389-1407` handles the `V` verb with
> `SkParsePath::FromSVGString`. Any polygon, ellipse, star or rounded shape can therefore be sent
> as path data in one call. `reference/16-engine-limits-and-workarounds.md` §2.3 D already records
> this as **WORKS**; do not tell a porter there is no workaround. **What `svgPath` genuinely lacks
> is narrower, and these are the real gaps:** it has **no corner-radius parameter** (round the
> corners in the path data itself) and **no gradient fill** (`argb` is a single flat colour —
> use `newLayer` + `layer.filter`, or an SkSL `shader`).

**5. `Draw.alpha()` is a cumulative multiplier — it is NOT silently dropped, and `scale`'s
defaulted `sy` is NOT a bug.** `sdk/ui/paint.nim:80` emits `"O "`; `skia_shim.cpp:1412` is
`case 'O': alpha *= std::max(0.0f, std::min(1.0f, r.num())); break;`, and the accumulator is
applied by the `colour` lambda at `skia_shim.cpp:1327` to **every** drawing verb — text `:1353`,
svg `:1394`, layer `:1370`, buffer `:1384`, image `:1360`. It is `*=`, not `=`, so it dims every
later command until you leave the `save`/`restore` bracket (`skia_shim.cpp:1364`, `:1365`) that
pushed it. **What *is* silently skipped is an unrecognised verb**: `skia_shim.cpp:1413` is
`default: break;`. And `Draw.scale*(d; sx, sy = 0'f32)` at `sdk/ui/paint.nim:78` is deliberate —
`skia_shim.cpp:1410` does `cv->scale(x, y == 0 ? x : y)`, so **`sy = 0` means "uniform"**, not
"scale to zero". See `reference/16-engine-limits-and-workarounds.md` §2.1 D for the `P`/`p`
workaround.

## 13. Form controls — `<input>`, `<select>`, `<progress>`

| HTML/CSS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `<input type=text value=…>` | `input <Signal[string]>` | `input draft` | `dsl.nim:372-385` — "two-way binding to a `Signal[string]` [S-CMP-3]". The node is the binding target, the signal is the model |
| `<input placeholder>` | `placeholder = "…"` | `input(draft, placeholder = "Search")` | `PropTable`: `placeholder → pPlaceholder`, allowed on `Input,TextArea` |
| `<textarea rows=4>` | `textArea` + `rows = 4` | `textArea notes` … `rows = 4` | `PropTable`: `rows → pRows` (int32, TextArea); `engine.nim:455-459` — the leaf is never shorter than `rows` lines |
| `<textarea resize:vertical>` | **NOT SUPPORTED YET** | — | there is no resize prop, and there does not need to be one for growth. Grepped `sdk/` and `render/` for `resize`, `resizable`, `autoResize` and `grows` as a textarea prop: **zero** hits — none of those names appears in `protocol/schema.nim:260-373`, `sdk/core/wire.nim`, `sdk/ui/input.nim` or `engine.nim`. A textarea already grows with its text and is floored at `rows`: `engine.nim:455` `# grows with its text; never shorter than `rows` lines`, `engine.nim:459` `YGSize(width: width, height: max(th - line, line * float32(max(leaf.rows, 1))))`, default 3 lines (`engine.nim:536` `rows: int(n.num(P_ROWS, 3))`). To pin the box instead, set `height` — a normal layout prop; the content then scrolls inside it. |
| `<input type=checkbox>` | `checkbox:` | `checkbox(checked = agree.get)` | `dsl.nim:386-388` |
| `<label>` for a checkbox | `label = "…"` | `checkbox(label = "Agree", checked = agree)` | `PropTable`: `label → pText`, allowed on `Checkbox,Switch,Radio` |
| `<input type=radio>` | `radio(parent, group, label)` | `radio(parent, "size", "Large")` | **Grouping exists in the SDK but is not rendered on the native target.** `sdk/yantra.nim:73-77` is the whole API: `proc radio*(parent: Node; group: string, label: string = ""): Node =` / `## Radio button. All radios with the same `group` are mutually exclusive.` / `result = make(nkRadio, parent)` / `result.set(pSource, group)  # reuse pSource for group name`. So the group name rides on the **reused `pSource` prop** (`sdk/core/wire.nim:66` `pSource = 10`) — there is no dedicated `group` prop and no Nim-side exclusivity helper; you still write the exclusivity yourself. Two gaps: grepping all of `render/native/` for `RADIO`/`Radio` returns **no matches**, so a `Radio` node is never measured, painted or clicked (`K_CHECKBOX` is handled at `engine.nim:448,524,551,1814,3209`; `K_RADIO` nowhere) — only the legacy Qt path honoured it, `render/qmlgen.nim:552` `exclusiveGroup: "…` + `esc(n.sProp(P_SOURCE))`; and `radio` is **not** a DSL node kind — `sdk/ui/dsl.nim:461-464` lists `checkbox` but not `radio`, so you must call the proc imperatively. |
| a toggle switch | `switch(parent, "Wi-Fi")` | `switch(parent, "Wi-Fi")` | `sdk/yantra.nim:96-99` |
| `<input type=range>` | `slider` | `slider(value = v, min = 0, max = 100)` | `PropTable`: `min`/`max` → float32, allowed on `Slider,Progress`; `value → pValue` |
| `<progress value max>` | `progress` | `progress(value = pct, max = 100)` | same props |
| `<select>` | `select` | `select(value = v)` | `PropTable`: `value`/`disabled` allowed on `Select` |
| `<input disabled>` | `disabled = true` | `input(draft, disabled = busy.get)` | **a prop, not a state block** — there is no `disabled:` block; see §6 |
| `<input autofocus>` | `focusAt = "<caret>#<n>"` | `input(draft, focusAt = "12#1")` | string, `Input,TextArea` (`protocol/schema.nim:370`). **The value is a caret BYTE INDEX, not a keyword.** `engine.nim:1589-1593` is the whole parse: `let hashAt = v.find('#')` / `discard parseInt(if hashAt >= 0: v[0 ..< hashAt] else: v, at)` / `e.focusOn(id)` / `e.caret = clamp(at, 0, e.node(id).sProp(P_VALUE).len)`. There is no string comparison against any word anywhere in the tree, so **`"end"`, `"start"` and `"select-all"` are not implemented** — `parseInt` fails, the result is discarded, and the caret silently lands at **0**. The `#n` suffix is a **change-counter, not an index**: the trigger is a value *change* (`engine.nim:747` `if cn.has(P_FOCUSAT) and cn.sProp(P_FOCUSAT) != e.focusSeen.getOrDefault(c): e.focusDue.add c`), so repeating the same caret position needs a fresh counter. See the real producers `sdk/ui/blocks.nim:65` `d.fields[id].set(pFocusAt, $caret & "#" & $d.focusN)` and `apps/desktop/app.nim:258`. |
| `spellcheck="false"` | `spellcheck = false` | `input(draft, spellcheck = false)` | bool, `Input,TextArea` |
| `inputmode` / `autocomplete` / `datalist` | **NOT SUPPORTED YET** | — | |
| find-and-replace in a field | `replace = "…"` | `input(draft, replace = "x")` | `PropMeta(replace, Replace, string, Input,TextArea)` |
| a field that grows with its content | (nothing to write — it is the default) | `textArea notes` | **A textarea already grows with its text**, so no prop is involved: `engine.nim:455` `# grows with its text; never shorter than `rows` lines` and `engine.nim:459` `height: max(th - line, line * float32(max(leaf.rows, 1)))`. What `block` (`protocol/schema.nim:354` — bool, `Input,TextArea`) actually does is make the field a **rich-text block field (P5)**, and nothing to do with size: `engine.nim:3441-3444` `proc blockKey(…) ## P5: Up/Down past a block's first/last line go to the block before/after (Shift: select across them); Enter splits (BlockSplit), Backspace at the start merges (BlockMerge)`; `engine.nim:2849-2851` `selectable` — a block field is part of the document one selection runs across; `engine.nim:2599-2605` drag-selects across block fields. So `<textarea>` ⇄ `textArea`, and `block = true` ⇄ "this field holds one block of a multi-field block document". |
| `::placeholder` styling | **NOT SUPPORTED YET** | — | the placeholder colour is the engine's. **Fix difficulty: easy.** |
| a custom-styled checkbox / radio / slider | **NOT SUPPORTED YET** | — | the widget is engine-drawn. Workaround: build it from `panel`s + a `checked` var. **Fix difficulty: hard** (a new node kind). PORT-NOTES lines 1107-1112 shows why this matters: the port had to prove "the hit test and the painted track are the same rectangle" by sampling the real framebuffer, not by reading the code |

## 14. Time-driven behaviour — the replacement for `animation` scripting

| CSS/JS | Yantra equivalent | Exact syntax | Notes/limits |
|---|---|---|---|
| `setTimeout` | `afterMs(500, …)` | `afterMs(500, proc () = batch(save()))` | `motion.nim:74-77` — routes through the engine clock, so a film gets an exact frame |
| `setInterval` / a polling loop | `machine:` | see below | no per-frame app work; `docs/spec/style.md` §7 — "the app does no work per frame and nothing re-renders" |
| a state-driven colour/visibility | `machine:` | `panel(fill = (if light == red: 0xE5484D else: 0x30A46C))` | `docs/spec/style.md` §7.y (`[S-MOT-5]`) |
| `requestAnimationFrame` | nothing to write | — | "**Frames.** An engine asks for frames only while something moves; an idle app draws nothing." |
| `@media (prefers-reduced-motion)` | nothing to write | — | `YANTRA_REDUCED_MOTION=1` — see §5.3 |
| a keyframed timeline | `timeline:` / `at` / `then` | `timeline:` … `at 0.4.s: scene.set(1)` … `then 600.ms: scene.set(2)` | `docs/spec/style.md` §7 (Timelines `[S-MOT-3]`) — "Steps in time, on the engine's clock (exact frames in a film)" |
| a finite state machine (traffic light) | `machine light:` | `machine light:` / `start red` / `after 4.s: red -> green` / `after 3.s: green -> amber` / `on cross: green -> amber` | `docs/spec/style.md` §7.y — "A timed step starts when its state is entered and is cancelled if the machine leaves it first. On a film's fake clock it lands on the exact frame." Read it with `light == red`, `light.can(cross)`; `light.onEnter(green, proc () = …)` runs code on entry |
| firing a state-machine event | `light.send(cross)` | `button "Cross": onClick: light.send(cross)` | "An event that does not apply in the current state does nothing: `send` returns false. Another machine's event is a compile error." |
| a delay before an animation | `delay = n` | `row(enter = fly(y = 12, delay = i * 30))` | `motion.nim:29-43` — `delay` is on every `Motion` and on `loop` |

### 14.1 The complete event map (DOM → Yantra)

`dsl.nim:70-75` — the complete list the DSL accepts.

| DOM | Yantra | Exact syntax |
|---|---|---|
| `onclick` | `evClick` | `button "X": onClick: save()` |
| `onchange` | `evChange` | `checkbox: onChange: …` |
| `oninput` | `evInput` | `input draft` (bound automatically) or `onInput: …` |
| `onsubmit` | `evSubmit` | `onSubmit: …` |
| `onfocus` / `onblur` | `evFocus` / `evBlur` | `onFocus: …` / `onBlur: …` |
| — (no DOM equivalent) | `evDismiss` | `ondismiss` — the overlay closed |
| `oncontextmenu` | `evContextMenu` | `onContextMenu: …` |
| `onkeydown` / `onkeyup` | `evKey` | `onKey: …` |
| `ondragstart` / `ondragover` / `ondrop` | `evDragStart` / `evDragOver` / `evDrop` | intra-app drags **and** OS file drops (`dropFile`, `docs/spec/style.md` §10, 16 MB cap) |
| `requestAnimationFrame` | `evFrame` | `onFrame: …` |
| `onpointerdown` / `move` / `up` | the same three | `onPointerDown: …` |
| `onmouseenter` / `onmouseleave` / `onmouseover` | **NOT SUPPORTED YET** | use the `hover:` block (§6). **Fix difficulty: easy.** |
| `addEventListener('scroll', …)` | `scrolled y:` | `scrolled y: text "{(y.get * 2)}"` |
| `ResizeObserver` | `sized w, h:` | `sized w, h: if w < 640: …` |
| `IntersectionObserver` | `reveal = fly(y = 60)` | `Card("One", reveal = fly(y = 60))` |

Handlers are auto-batched (`dsl.nim:253-256` — `node.on(evX, proc() = batch(...))`), so a
handler that mutates three signals re-renders once.

---

## 15. The 30-second version

If you remember nothing else:

```
display:flex;flex-direction:row     ->  row:
display:flex;flex-direction:column  ->  column:      (or panel:)
display:grid                        ->  grid "1fr 2fr 200", gap = 12:
position:relative                   ->  (nothing — it is the default)
position:absolute                   ->  absolute = true, top/left/right/bottom
overflow:auto                       ->  scroll = true
overflow:hidden                      ->  clip = true
display:none                         ->  visible = false
background                          ->  fill
color                               ->  color
border:1px solid #ccc               ->  border = 1, borderColor = 0xCCCCCC
border-radius:8px                   ->  radius = 8
box-shadow                          ->  shadow = shadow(x, y, blur, colour)
linear-gradient(180deg,A,B)         ->  linear(A, B)
width/height/gap/padding/margin     ->  width / height / gap / pad / margin  (px; no %, no calc)
font-size:18px;font-weight:600      ->  size = 18, weight = 600
text-align:center                   ->  align = center
text-overflow:ellipsis              ->  maxLines = 1
opacity:.5                          ->  opacity = 0.5
filter:blur(4px)                    ->  blur = 4
mix-blend-mode:multiply             ->  blend = multiply
backdrop-filter:blur(26px)          ->  backdropBlur = 26
transition:all 200ms ease-out       ->  transition = 200, ease = outCubic
@keyframes (one channel, looping)   ->  animate = spin() / pulse() / breathe() / bob() / loop(...)
transition in / out                  ->  enter = fly(y = 12) / exit = fade()
:hover / :active / :focus           ->  hover: / pressed: / focused:  blocks
.class                              ->  proc c(): Style = style(...) ; use = c()
#id                                 ->  var v = … ; fill = (if v: A else: B)
::before / ::after                  ->  another child node
:nth-child(2n)                      ->  for i, x in xs: … if i mod 2 == 0: …
@media (min-width:640px)            ->  sized w: if w >= 640: …
position:fixed                      ->  modal / drawer / popover / menu, or a node outside the scroller
no prop exists yet                  ->  panel(shader = sksl"""…""")
```

---

## 16. Prop index — the greppable list

Every DSL prop this chapter covers, with its wire prop, wire type and the node kinds it is
allowed on. Copied from `protocol/schema.nim` `PropTable` (lines 259–464) — this table is what
`dsl.nim:203-206` validates against, raising `Y001 unknown prop` with a
"did you mean …?" suggestion otherwise. `*` means every node kind.

### 16.1 Layout & box

| DSL prop | Wire prop | Type | Allowed on | CSS it replaces |
|---|---|---|---|---|
| `width` | `pWidth` | int32 | `*` | `width` |
| `height` | `pHeight` | int32 | `*` | `height` |
| `minWidth` | `pMinWidth` | float32 | `*` | `min-width` |
| `minHeight` | `pMinHeight` | float32 | `*` | `min-height` |
| `maxWidth` | `pMaxWidth` | float32 | `*` | `max-width` |
| `maxHeight` | `pMaxHeight` | float32 | `*` | `max-height` |
| `pad` / `padding` | `pPadTop` (all four) | int32 | `*` / `Window,Column,Row,Panel,Button,Input,Modal` | `padding` |
| `padX` | `pPadLeft` + `pPadRight` | int32 | `*` | `padding-left/right` |
| `padY` | `pPadTop` + `pPadBottom` | int32 | `*` | `padding-top/bottom` |
| `padTop` / `padRight` / `padBottom` / `padLeft` | same | int32 | `*` | the four `padding-*` |
| `margin` | `pMarginTop/Right/Bottom/Left` | float32 | `*` | `margin` |
| `marginX` / `marginY` | the pairs | float32 | `*` | `margin-left/right`, `margin-top/bottom` |
| `marginTop` / `marginRight` / `marginBottom` / `marginLeft` | same | float32 | `*` | the four `margin-*` |
| `grow` | `pFlexGrow` | float32 | `*` | `flex-grow` / `flex: 1` |
| `shrink` | `pFlexShrink` | float32 | `*` | `flex-shrink` |
| `alignItems` | `pAlignItems` | int32 | `*` | `align-items` |
| `justify` | `pJustify` | int32 | `*` | `justify-content` |
| `wrap` | `pWrap` | bool | `*` | `flex-wrap` |
| `gap` / `spacing` | `pSpacing` | int32 | `Window,Column,Row,Panel,Group,Stack,Grid,Flex,Page` / `Column,Row,Grid,Flex` | `gap` |
| `columns` | `pGridCols` | string | `Grid` | `grid-template-columns` |
| `span` | `pSpan` | int32 | `*` | `grid-column: span n` |
| `absolute` | `pAbsolute` | bool | `*` | `position: absolute` |
| `top` / `right` / `bottom` / `left` | `pInsetTop/…` | float32 | `*` | the four insets |
| `z` | `pZIndex` | int32 | `*` | `z-index` |
| `x` / `y` | `pX` / `pY` | float32 | `*` | `transform: translate` |
| `scale` | `pScale` | float32 | `*` | `transform: scale` |
| `rotate` | `pRotZ` | float32 | `*` | `transform: rotate` |
| `scroll` | `pScroll` | bool | `*` | `overflow: auto` |
| `clip` | `pClip` | bool | `*` | `overflow: hidden` |
| `scrollTo` | `pScrollY` | float32 | `*` | `scrollTop` |
| `stickToEnd` | `pStickToEnd` | bool | `*` | chat-style auto-scroll |
| `sticky` / `stickyLeft` | `pSticky` / `pStickyLeft` | float32 | `*` | `position: sticky` |
| `stickBottom` | `pStickBottom` | bool | `*` | pinned footer |
| `smooth` | `pSmooth` | bool | `*` | `scroll-behavior: smooth` |
| `direction` | `pDirection` | int32 | `*` | `direction: rtl` |
| `anchor` | `pAnchor` | bool | `*` | an anchored/floating node |
| `visible` | `pVisible` | bool | `*` | `display: none` |

### 16.2 Paint

| DSL prop | Wire prop | Type | Allowed on | CSS it replaces |
|---|---|---|---|---|
| `fill` | `pColor` (+ `pGradFrom/To/Angle`) | int32 | `*` | `background` / `background-color` |
| `color` / `textColor` | `pTextColor` | int32 | `*` | `color` |
| `opacity` | `pOpacity` | float32 | `*` | `opacity` |
| `radius` | `pRadius` | int32 | `*` | `border-radius` |
| `border` | `pBorderWidth` | int32 | `*` | `border-width` |
| `borderColor` | `pBorderColor` | int32 | `*` | `border-color` |
| `shadow` | `pShadowX/Y/Blur/Color` | float32/float32/float32/int32 | `*` | `box-shadow` |
| `blur` | `pBlur` | float32 | `*` | `filter: blur()` |
| `backdropBlur` | `pBackdropBlur` | float32 | `*` | `backdrop-filter: blur()` |
| `blend` | `pBlend` | int32 | `*` | `mix-blend-mode` |
| `saturate` | `pSaturate` | float32 | `*` | `filter: saturate()` |
| `brightness` | `pBrightness` | float32 | `*` | `filter: brightness()` |
| `contrast` | `pContrast` | float32 | `*` | `filter: contrast()` |
| `shader` | `pShader` | string | `*` | every other paint effect |
| `use` | (calls `applyStyle`) | Style | `*` | a CSS class |

### 16.3 Text

| DSL prop | Wire prop | Type | Allowed on | CSS it replaces |
|---|---|---|---|---|
| `text` | `pText` | string | `Window,Text,Button,Input,Checkbox,Radio,Switch,TabPanel,Tooltip` | the element's text content |
| `size` / `fontSize` | `pFontSize` | int32 | `Text,Button,Input,TextArea,Window,Checkbox,Path` / `Text,Button,Input,TextArea` | `font-size` |
| `weight` | `pFontWeight` | int32 | `*` | `font-weight` |
| `font` | `pFontFamily` | string | `*` | `font-family` |
| `italic` | `pItalic` | bool | `*` | `font-style: italic` |
| `lineHeight` | `pLineHeight` | float32 | `*` | `line-height` |
| `maxLines` | `pMaxLines` | int32 | `*` | `text-overflow: ellipsis` + a line clamp |
| `align` | `pAlign` | int32 | `Text,Column,Row` | `text-align` |
| `spans` | `pSpans` | string | `Text,TextArea,Input` | styled inline runs |
| `links` | `pLinks` | string | `Text` | clickable runs |
| `inline` | `pInline` | string | `Text` | inline markup (see the `rich` node) |
| `placeholder` | `pPlaceholder` | string | `Input,TextArea` | `placeholder` |
| `label` | `pText` | string | `Checkbox,Switch,Radio` | a `<label>` |
| `value` | `pValue` | string | `Input,TextArea,Slider,Progress,Select` | `value` |
| `rows` | `pRows` | int32 | `TextArea` | `<textarea rows>` |
| `block` | `pBlock` | bool | `Input,TextArea` | a block-level field |
| `focusAt` | `pFocusAt` | string | `Input,TextArea` | `autofocus` / caret placement |
| `spellcheck` | `pSpellcheck` | bool | `Input,TextArea` | `spellcheck` |
| `replace` | `pReplace` | string | `Input,TextArea` | find-and-replace |

### 16.4 Motion & interaction

| DSL prop | Wire prop | Type | Allowed on | CSS it replaces |
|---|---|---|---|---|
| `transition` | `pTransDuration` | int32 | `*` | `transition-duration` |
| `ease` | `pTransEasing` | int32 | `*` | `transition-timing-function` |
| `enter` | `pEnter` | string | `*` | an animation on appear |
| `exit` | `pExit` | string | `*` | an animation on removal |
| `animate` | `pAnimTarget` (+ `pAnimFrom/To/Duration`) | string | `*` | `@keyframes` |
| `reveal` | `pReveal` | string | `*` | `IntersectionObserver` |
| `parallax` | `pParallax` | float32 | `*` | a `background-attachment: fixed` effect |
| `cursor` | `pCursor` | int32 | `*` | `cursor` (`arrow`, `hand`, `ibeam`/`text`) |
| `disabled` | `pDisabled` | bool | `Button,Input,Checkbox,Radio,Select,Slider,Switch` | `:disabled` |
| `checked` | `pChecked` | bool | `Checkbox,Radio,Switch` | `:checked` |
| `hover:` | `pHoverFill/Color/Border/Opacity/Scale/Y` | mixed | `*` | `:hover` |
| `pressed:` | `pPress…` | mixed | `*` | `:active` |
| `focused:` | `pFocus…` | mixed | `*` | `:focus` |

**Only six things may change in a state block** (`dsl.nim:233-242`): `fill`, `color`,
`borderColor`, `opacity`, `scale`, `y`. Anything else is error `Y013`:
"`'radius'` can't change with state — use fill, color, borderColor, opacity, scale or y".

**The only props that are NOT styled through `p…` setters** (they get their own proc —
`dsl.nim:177-201`): `padX`, `padY`, `margin*`, `fill` (`setFill`), `shadow` (`setShadow`),
`use` (`applyStyle`), `enter` (`setEnter`), `exit` (`setExit`), `reveal` (`setReveal`),
`animate` (`setLoop`).

