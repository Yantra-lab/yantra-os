# 05 — Layout and containers

Ground truth: `sdk/ui/widgets.nim`, `sdk/yantra.nim`, `sdk/ui/control.nim`, `sdk/core/wire.nim`,
`protocol/schema.nim` (`PropTable`), `sdk/ui/dsl.nim`, `render/native/engine.nim`
(`styleContainer`, `styleCommon`, `fitGrids`, `parseTracks`, `trackWidths`),
`render/native/t_grid.nim`, `render/native/t_scroll.nim`, `render/native/t_longlist.nim`.

Two ways to build a UI:

* **Imperative** — `window`, `column`, `row`, `panel`, … return a `Node`; you call setters on it
  and add children with `parentSym`-first constructors. See `examples/webpage.nim`.
* **DSL** — the `app` macro, a `ui` block where `column(pad = 8.px):` is a statement
  (`sdk/ui/dsl.nim`). `dsl.nim`'s `nodeKinds` list (line 461) is the exact set of node names the
  DSL accepts. **`flex`, `scrollArea`, `tabs`, `tabPanel`, `divider` and `window` are NOT in it** —
  those are imperative-only.

---

## 1. Container nodes

Exact signatures. `parent` is the parent `Node`; a root container is `make(nkWindow)` with no parent.

### `window` — the root container

```nim
proc window*(title: string, w: int32 = 800, h: int32 = 600): Node
```

`sdk/ui/widgets.nim:9`. Creates `nkWindow`, sets `pText` to the title and `pWidth`/`pHeight`.
The only node made without a parent. In the DSL it is implicit: `app("Title", width = …, height = …)`.

```nim
let page = window("yantra webpage", 900, 720)
page.color(0x0f, 0x11, 0x17)
page.spacing(20)
page.padding(32)
```

### `column` — vertical flex

```nim
proc column*(parent: Node): Node     ## = make(nkColumn, parent)
```

`styleContainer` maps **every** non-row container to `fdColumn`
(`engine.nim:466`: `y.setFlexDirection(if k == K_ROW: fdRow else: fdColumn)`), so `panel`,
`group`, `grid`, `stack`, `scrollArea` and `tabs` all lay their children out vertically.

```nim
let body = column(page)
body.spacing(16)
let h = text(body, "Build webpages, apps and games in Nim")
h.fontSize(32)
```

### `row` — horizontal flex

```nim
proc row*(parent: Node): Node        ## = make(nkRow, parent)
```

**Default `alignItems` for a row is `yaCenter`** (`engine.nim:473`) when `pAlignItems` is not set;
a column's default is Yoga's (`stretch`).

```nim
let header = row(page)
header.spacing(16)
let brand = text(header, "yantra")
brand.fontSize(28)
```

### `panel` — a plain box (the workhorse)

```nim
proc panel*(parent: Node, w: int32 = 0, h: int32 = 0): Node
```

`widgets.nim:22`. A container with a background, radius, border, padding. `w`/`h` are only applied
when `> 0`; pass `0` (the default) and size it with props instead.

```nim
let card = panel(body, 300, 180)
card.padding(16)
card.color(0x1a, 0x1f, 0x2e)
card.radius(12)
card.border(1, 0x33, 0x33, 0x55)
```

### `stack` — overlapping children

```nim
proc stack*(parent: Node): Node      ## = make(nkStack, parent)
```

`yantra.nim:121`. Children of a stack are **all absolutely positioned** (`engine.nim:512`:
`if n.flag(P_ABSOLUTE) or inStack: y.setPositionType(ypAbsolute)`), so they take no space from each
other. Each places itself with `top`/`left`/`right`/`bottom`; a child with none of them defaults to
`top = 0, left = 0` (`engine.nim:518-519`). Stack children also do not count as grid items.

```nim
let over = stack(page)
let badge = text(over, "3")
badge.set(pInsetTop, 8'f32); badge.set(pInsetRight, 8'f32)   # no proc for these
```

### `flex` — a direction-parameterised container

```nim
proc flex*(parent: Node, direction: string = "row"): Node
```

`yantra.nim:116`. Creates `nkFlex` and stores the direction string in **`pSource`** (reused slot).
Documented directions: `"row" | "row-reverse" | "column" | "column-reverse"`.
> **RESOLVED 2026-10-03.** This used to carry an open verification marker. It is
> now settled from source and the advice is confirmed: `styleYoga`'s `case n.kind`
> (`render/native/engine.nim:550`) has **no `K_FLEX` branch at all** — a flex node
> falls through to `else: styleContainer(y, n)` (`render/native/engine.nim:609-610`),
> which gives a non-row container `fdColumn` regardless of the stored direction.
> Every `P_SOURCE` read in the engine is for a different kind: image/video
> (`:565`), model (`:973`, `:1909`), stack placement (`:1318`), appview (`:4230`).
> **So `flex(parent, direction)`'s direction argument is unimplemented on the
> native engine.** Use `row` / `column` (or `grid`) instead.

```nim
let f = flex(page, "row")
let grow = panel(f); grow.flexGrow(1)
```

### `grid` — CSS-Grid-style tracks

```nim
proc grid*(parent: Node, cols: string = "1fr 1fr"): Node
```

`yantra.nim:111`. Sets `pGridCols`. See §4 for the exact track-string grammar that actually parses.
There is a separate `direction` prop (`pDirection`, int32) for RTL, not a grid direction.

```nim
let main = grid(page, "160 1fr 2fr")
main.gridGap(12)          # or .spacing(12) — see §4
let side = panel(main); side.set(pName, "side")
```

### `scrollArea` — a scrollable container

```nim
proc scrollArea*(parent: Node): Node  ## = make(nkScrollArea, parent)
```

`yantra.nim:125`. Setting **`scroll = true`** is what makes any container scroll
(`engine.nim:489`: `y.setOverflow(yoScroll)`); that is the idiom actually used everywhere in the
examples (`column(grow = 1, scroll = true, minHeight = 0)`), not `scrollArea`.

```nim
let view = scrollArea(page)
view.scroll(true)
view.flexGrow(1)
view.minHeight(0)
```

### `tabs` / `tabPanel`

```nim
proc tabs*(parent: Node): Node                      ## = make(nkTabs, parent)
proc tabPanel*(parent: Node, label: string): Node   ## = make(nkTabPanel, parent); setText(label)
```

`yantra.nim:129,133`. `pText` on a tabPanel is its label (`PropTable` allows `text` on
`Window,Text,Button,Input,Checkbox,Radio,Switch,TabPanel,Tooltip`). `evTabChange` is delivered by
the engine. Neither has a DSL node name.

```nim
let t = tabs(page)
let p1 = tabPanel(t, "Files")
p1.scroll(true)
let p2 = tabPanel(t, "Settings")
```

### `sheet` — a spreadsheet-scale canvas grid

Not a node; a `Sheet` ref wrapping one `nkCanvas` (`sdk/ui/sheet.nim`):

```nim
proc newSheet*(parent: Node; rows, cols: int; cell: proc (r, c: int): string): Sheet
proc redraw*(s: Sheet)                                   ## O(visible cells)
proc cellRect*(s: Sheet; r, c: int): (float32, float32, float32, float32)
proc hit*(s: Sheet; x, y: float32): (int, int)          ## -1 in a header
proc colName*(c: int): string                           ## 0 -> A, 26 -> AA
```

Only the cells that show are drawn, so a million cells cost a screenful. Frozen rows/columns
(`frozenRows`, `frozenCols`), headers (`headerH`, `headerW`), column resize by dragging a header edge
(within 4 px), a selected cell, and `onEdit(r, c, x, y, w, h)` for placing an editor. Scrolling is
the engine's: a Scroll handler on the canvas, `yNodeSize(id, 2)` for `sy` and `(id, 9)` for `sx`.

```nim
var s = newSheet(page, 100_000, 26, proc (r, c: int): string = $r & "," & $c)
s.frozenRows = 1
s.frozenCols = 1
s.colW[0] = 160
s.node.flexGrow(1)
```

### `group` — layout-transparent

```nim
proc group*(parent: Node): Node   ## = make(nkGroup, parent), sdk/ui/control.nim:16
```

Children lay out as if they were the parent's own children. Every `if`/`for` branch inside a DSL
block gets one, so branches can add/remove/reorder without disturbing siblings. A group is skipped
by `yogaKids` reach and by grid-item collection (recursed into instead, `engine.nim:844`).

```nim
let g = group(parent)
let a = text(g, "one")
let b = text(g, "two")
```

### `spacer` — a gap

```nim
proc spacer*(parent: Node, h: int32 = 8): Node {.discardable.}
```

`widgets.nim:27`. `make(nkSpacer, parent)`; sets `pHeight` **only when `h > 0`**.
See §5 for exactly when a spacer is flexible — the default `8` is *not*.

```nim
discard spacer(page, 16)                 # a fixed 16 px gap
let s = spacer(bar, 0); s.flexGrow(1)    # a flexible gap
```

### `divider` — a 1 px rule

```nim
proc divider*(parent: Node, w: int32 = 0): Node {.discardable.} = panel(parent, w, 1)
```

`widgets.nim:26`. Literally a panel 1 px tall. Colour it like any node.

```nim
let rule = divider(page)
rule.color(0x22, 0x22, 0x3a)
```

---

## 2. Every layout prop

`PropTable` (`protocol/schema.nim:258`) maps the DSL name to the wire prop and its type; the wire
prop is set on `sdk/core/wire.nim`'s `Prop` enum. `pX` in the SDK is the lowerCamel alias the DSL
compiler emits (`dsl.nim:220`: `setCall(nodeSym, "p" & meta.wireProp, ...)`).

Types are the **wire** types. Most layout sizes are `int32` or `float32` pixels. `bool` props are set
with `1'i32` / `0'i32` from raw Nim, `true`/`false` from the DSL.

| wire prop | id | type | DSL name | what it does (verified in `engine.nim`) |
|---|---|---|---|---|
| `pSpacing` | 20 | `int32` | `gap` / `spacing` | gap between children, all sides: `y.setGap(gutterAll, gap)` — only when `> 0` (`:484`) |
| `pPadTop` | 21 | `int32` | `padTop` | padding, top edge (`:485`) |
| `pPadRight` | 22 | `int32` | `padRight` | padding, right edge (`:486`) |
| `pPadBottom` | 23 | `int32` | `padBottom` | padding, bottom edge (`:487`) |
| `pPadLeft` | 24 | `int32` | `padLeft` | padding, left edge (`:488`) |
| `pMarginTop` | 90 | `float32` | `marginTop` | margin, top edge (`:508`) |
| `pMarginRight` | 91 | `float32` | `marginRight` | margin, right edge (`:509`) |
| `pMarginBottom` | 92 | `float32` | `marginBottom` | margin, bottom edge (`:510`) |
| `pMarginLeft` | 93 | `float32` | `marginLeft` | margin, left edge (`:511`) |
| `pWidth` | 3 | `int32` | `width` | fixed width (`:497`) |
| `pHeight` | 4 | `int32` | `height` | fixed height (`:498`) |
| `pMinWidth` | 94 | `float32` | `minWidth` | `y.setMinWidth` (`:499`) |
| `pMinHeight` | 95 | `float32` | `minHeight` | `y.setMinHeight` (`:500`) |
| `pMaxWidth` | 96 | `float32` | `maxWidth` | `y.setMaxWidth` (`:501`) |
| `pMaxHeight` | 97 | `float32` | `maxHeight` | `y.setMaxHeight` (`:502`) |
| `pFlexGrow` | 53 | `float32` | `grow` | `y.setFlexGrow(v)` **and forces `setFlexShrink(1)`** (`:503-505`) |
| `pFlexShrink` | 54 | `float32` | `shrink` | `y.setFlexShrink(v)` — only read when the prop is present (`:507`) |
| `pFlexBasis` | 55 | `float32` | *(no DSL name)* | **not read by the native engine.** `y.setFlexBasis(0)` is only ever set implicitly, when a scroll container has `pFlexGrow` and no `pHeight` (`:493`) |
| `pGridCols` | 56 | `string` | `columns` | the track string; see §4 |
| `pGridRows` | 57 | `string` | *(no DSL name)* | **not read by the native engine** (only the legacy QML generator emits `rows:`, `render/qmlgen.nim:622`). Rows are implicit |
| `pGridGap` | 58 | `int32` | *(no DSL name; `node.gridGap(v)` proc)* | column gap; falls back to `pSpacing` when absent (`engine.nim:852`) |
| `pAlignItems` | 98 | `int32` | `alignItems` | cross-axis: `0 start, 1 center, 2 end, else stretch` (`:467-472`). A `row` with none set defaults to **center** (`:473`) |
| `pJustify` | 99 | `int32` | `justify` | main axis: `0 start, 1 center, 2 end, 3 spaceBetween, 4 spaceAround, 5 spaceEvenly` (`:474-481`) |
| `pWrap` | 100 | `bool` | `wrap` | `y.setFlexWrap(ywWrap)` (`:482`) |
| `pAbsolute` | 101 | `bool` | `absolute` | `y.setPositionType(ypAbsolute)` (`:512`) |
| `pInsetTop` | 102 | `float32` | `top` | absolute top offset (`:514`) |
| `pInsetRight` | 103 | `float32` | `right` | absolute right offset (`:515`) |
| `pInsetBottom` | 104 | `float32` | `bottom` | absolute bottom offset (`:516`) |
| `pInsetLeft` | 105 | `float32` | `left` | absolute left offset (`:517`) |
| `pZIndex` | 59 | `int32` | `z` | paint order; a sticky node gets `+ 0.5` (`:2003`) |
| `pOverflow` | 60 | `int32` | *(no DSL name; `node.overflow(v: string)` proc)* | **not read by the native engine.** Overflow comes from `pScroll` (`yoScroll`) and `pClip` (`yoHidden`) only |
| `pScrollX` | 61 | `int32` | *(no DSL name; `node.scrollX(v)` proc)* | **not read as a prop.** Horizontal scroll is *read out* with `yNodeSize(id, 9)` — `sheet.nim` does exactly that |
| `pScrollY` | 62 | `int32` | `scrollTo` | imperative jump: the engine pulls it and clamps it to the scroll range (`:1103-1113`) |
| `pScroll` | 106 | `bool` | `scroll` | `y.setOverflow(yoScroll)` + clip children to the box (`:489`, `:1085-1087`) |
| `pClip` | 107 | `bool` | `clip` | `y.setOverflow(yoHidden)` + clip children to the box (`:494`, `:1085`) |
| `pDirection` | 167 | `int32` | `direction` | `0` inherit, `1` LTR, `>= 2` RTL (`:521-522`, `:738`, `:1546`) |
| `pAnchor` | 168 | `bool` | `anchor` | keep the first visible child still when anything above it changes size or is prepended (`:749`, `:1457`) |
| `pSticky` | 164 | `float32` | `sticky` | hold a header at the view edge: `b.y = max(b.y, min(top, containerBottom - h))` (`:1074-1076`) |
| `pStickyLeft` | 165 | `float32` | `stickyLeft` | the same on the horizontal axis (`:1077-1079`) |
| `pStickToEnd` | 159 | `bool` | `stickToEnd` | stay at the bottom while the user is already there; release when they scroll up (`:1105-1114`) |
| `pStickBottom` | 169 | `bool` | `stickBottom` | anchor **and** stick to the newest message — the chat pairing (`:749`, `:1480`) |
| `pSpan` | 153 | `int32` | `span` | how many grid columns a grid item takes, clamped to the track count (`engine.nim:860`) |

Related props used constantly with the above: `pColor` (`fill`), `pTextColor` (`color`),
`pRadius` (`radius`), `pBorderWidth` (`border`), `pBorderColor` (`borderColor`), `pFill`.

```nim
import yantra

let col = column(win)
col.set(pSpacing, 12'i32)          # raw wire
col.flexGrow(1)                    # named proc
col.gridGap(12)                    # named proc
```

### Values that are words, not numbers

`dsl.nim:150-171` rewrites bare identifiers in these props (`dsl.nim` verbatim):

| prop | words → ints |
|---|---|
| `alignItems` | `first`/`start` 0, `center` 1, `last`/`end` 2, `stretch` 3 |
| `justify` | `first`/`start` 0, `center` 1, `last`/`end` 2, `between` 3, `around` 4, `evenly` 5 |
| `cursor` | `arrow` 0, `hand` 1, `ibeam` 2, `text` 2 |
| `align` | `left` 0, `center` 1, `right` 2 |
| `fit` | `contain` 0, `cover` 1, `fill` 2 |
| `blend` | `normal` 3, `plus` 12, `screen` 14, `overlay` 15, `darken` 16, `lighten` 17, `colordodge` 18, `colorburn` 19, `hardlight` 20, `softlight` 21, `difference` 22, `exclusion` 23, `multiply` 24, `hue` 25, `saturation` 26, `color` 27, `luminosity` 28 |
| `ease` | any name from `protocol/schema.nim`'s `Easings`, or `ease` + that name |

`fit` also accepts a **string** (`dsl.nim:169-171`): `"cover"` → 1, `"fill"` → 2, anything else → 0.

---

## 3. DSL shorthand props (`sdk/ui/dsl.nim:89-99`, `:177-199`)

### Units are checked

`lengthProps` (`:89`) — `width height minwidth maxwidth minheight maxheight pad padding padx pady
padtop padright padbottom padleft margin marginx marginy margintop marginright marginbottom
marginleft gap spacing radius border top left right bottom x y size fontsize blur backdropblur`.
A non-literal in one of these is wrapped in `lengthOf(...)`, so `16` and `16.px` are the same and a
unitless-vs-px mistake is a compile error. Literals skip the check (`:173`).

`durationProps = ["transition"]` → `durationOf`; `angleProps = ["rotate"]` → `angleOf`.

### Shorthands that collapse to several props

From `dsl.nim:176-199`, verbatim:

* **`padX`** → sets `pPadLeft` **and** `pPadRight` (`int32`).
* **`padY`** → sets `pPadTop` **and** `pPadBottom` (`int32`).
* **`margin`** → all four sides: `pMarginTop`, `pMarginRight`, `pMarginBottom`, `pMarginLeft` (`float32`).
* **`marginX`** → `pMarginLeft`, `pMarginRight`.
* **`marginY`** → `pMarginTop`, `pMarginBottom`.
* **`pad` / `padding`** → calls the `padding` setter: DSL rewrites it to `node.padding(int32(v))`,
  which sets all four sides. (The imperative API has both `padding(all)` and
  `padding(top, right, bottom, left)` — `yantra.nim:284,291`.)
* **`gap` / `spacing`** → `node.spacing(int32(v))`.
* **`width` / `height`** → `node.width(int32(v))` / `node.height(int32(v))`.
* **`size` / `fontSize`** → `node.fontSize(int32(v))` — `size` also means size on a `Window`.
* **`fill`** → `setFill(node, v)`: a colour **or** a `Gradient`. A plain colour also writes
  `pGradAngle = -1`, switching any gradient off (`sdk/ui/style.nim:34-41`).
* **`shadow`** → `setShadow(node, s)`: writes `pShadowX/Y/Blur/Color`.
* **`use`** → `applyStyle(node, s)`: a `Style` bundle.
* **`enter` / `exit` / `reveal` / `animate`** → `setEnter` / `setExit` / `setReveal` / `setLoop`.

### Bare theme colour words

`colorProps = ["fill", "color", "textcolor", "bordercolor", "shadow"]` (`:99`) are rewritten through
`themeWords`, so `bg sidebar surface surface2 surface3 line text muted faint accent accentText
accentSoft danger success` become reads of the current theme and re-style on a theme switch. It
rewrites inside `if`, `rgba(…)`, `linear(…)` and `shadow(color = …)`, but **not** callee names,
field names (`x.accent`) or argument names.

```nim
column(fill = surface, radius = 12.px, padX = 16.px, marginY = 8.px):
  row(alignItems = center, justify = between, gap = 12.px):
    text "Title", size = 20, weight = 700, color = text
    button @go "Go", fill = accent, color = accentText
```

