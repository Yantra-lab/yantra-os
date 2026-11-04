# 03 · Node & Prop Reference

**The lookup chapter.** Every node kind and every property Yantra's wire protocol
defines, in one place. Nothing here is invented: the tables come from
`sdk/core/wire.nim` (the generated enum), `protocol/schema.nim` (the single source
of truth, with each prop's type), `sdk/yantra.nim` + `sdk/ui/widgets.nim` (the
Nim setters) and `sdk/ui/dsl.nim` (what the `app` DSL accepts).

- **Node kinds: 48** — every `nk*` value in `NodeKind`.
- **Props: 265** — every `p*` value in `Prop`, ids 0–264, existing ids never move.

## How to read the tables

**wire id** — the number on the boundary. `nkButton = 4`, `pWidth = 3`. These are
stable and permanent: a new prop is always appended, never renumbered.

**type** — how the value crosses the wasm boundary. Only four shapes exist:
`int32`, `float32`, `bool`, `string`. Bools are sent as `int32` (0/1). Colours are
`int32` packed `0xAARRGGBB` (see `rgba()` in `sdk/ui/style.nim`). Numbers with
units (`16.px`, `200.ms`, `45.deg`) are stripped to their float before the call
(`sdk/ui/units.nim`).

A prop marked **wire-level only** has no Nim setter in the SDK and no name in the
DSL — the engine reads it, but an app author sets it through the engine or
through a higher-level helper, not by hand.

**DSL name** — where it differs from the prop name, the DSL spelling is given in
the "controls" column (`pColor` → `fill`, `pTextColor` → `color`, `pFlexGrow` →
`grow`, `pBorderWidth` → `border`, `pSpacing` → `gap`, and so on). The full
DSL↔wire mapping with allowed nodes is generated into
`docs/HOW_IT_WORKS/props.md`.

---

# Node kinds (48)

## Containers & structure

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 0 | `nkWindow` | The whole app: one top-level window with a title and a size | `app "Title":` — the root every other node lives in |
| 1 | `nkColumn` | A vertical stack; children top to bottom | the main content area of a screen |
| 2 | `nkRow` | A horizontal stack; children left to right | a toolbar, a button + label pair |
| 12 | `nkPanel` | A plain rectangular box with a fill, radius, border and padding | a card, a surface, a divider |
| 41 | `nkGroup` | A layout-transparent group — it lays out nothing, just holds children | the items of a `for` loop or the branch of an `if` |
| 23 | `nkFlex` | A CSS-Flexbox container | when you need `row-reverse` or per-child grow/shrink |
| 24 | `nkStack` | Children overlap in the same box; each places itself | a media frame with a caption and a badge on top |
| 25 | `nkScrollArea` | A clipping, scrolling viewport | long content in a fixed box |
| 26 | `nkTabs` | A tab strip; `nkTabPanel` children become its pages | settings / profile / docs |
| 27 | `nkTabPanel` | One page of a `nkTabs`; its text is the tab label | one section per tab |

## Text

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 3 | `nkText` | A run of text | headings, body copy, a value read-out |
| 7 | `nkSpacer` | Empty space that pushes siblings apart | a gap before a footer (`grow = 1` is set for you) |

## Inputs & controls

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 4 | `nkButton` | A clickable button | submit, confirm, "Add" |
| 6 | `nkInput` | A single-line text field | a search box, a name field |
| 13 | `nkTextArea` | A multi-line text field | notes, a comment body |
| 14 | `nkCheckbox` | A tick box | "remember me" |
| 15 | `nkRadio` | One option of a mutually exclusive group (the group name reuses `pSource`) | shipping method |
| 16 | `nkSelect` | A dropdown; options are a JSON array | pick a country |
| 17 | `nkSlider` | A draggable value between a min and a max | a volume or brightness knob |
| 18 | `nkProgress` | A read-only filled bar | upload progress |
| 19 | `nkSwitch` | An iOS-style on/off toggle | notifications on/off |
| 20 | `nkDatePicker` | A calendar input | a booking date |
| 21 | `nkColorPicker` | A colour well | a theme's brand colour |

## Layout

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 22 | `nkGrid` | A CSS Grid; `pGridCols` is a grid-template-columns string | a gallery, a dashboard of cards |

## Data display

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 28 | `nkTable` | Rows and columns with optional sorting and filtering | an invoice, a log |
| 29 | `nkListView` | A virtualized list — only visible rows are built | 100 000 messages |
| 30 | `nkTreeView` | An expandable tree | a file browser, a settings tree |
| 31 | `nkChart` | line / bar / pie / scatter (the type reuses `pSource`; data goes in `pRows`) | a trend |

## Media

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 5 | `nkImage` | A bitmap from a file path | a photo, a logo |
| 32 | `nkVideo` | A video player with a poster frame | a clip |
| 33 | `nkAudio` | An audio player | a voice note |
| 44 | `nkPage` | One page of a document or a 1280×720 deck slide (a PDF page each) | a report viewer, a slide deck |

## 3D

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 8 | `nkScene3D` | A 3D viewport: sky, fog, post-processing. Camera and light are optional | `scene3d(sky = 0x87CEEB):` |
| 9 | `nkModel` | A glTF 2.0 model inside a scene | `model "fox.glb"` |
| 10 | `nkCamera` | An explicit eye + target + field of view; without one the renderer supplies it | a scripted camera move |
| 11 | `nkLight` | A directional/point/spot light; without one the renderer supplies it | key light, or a glowing lamp |
| 45 | `nkMesh` | A primitive or custom geometry object inside a scene | `box`, `sphere`, `plane`, `cylinder`, `mesh` |
| 47 | `nkParticles` | Many small sprites the engine emits and moves | sparks, smoke, rain |
| 46 | `nkSynth` | A sound the engine generates: wave/noise → filter → envelope → echo | a UI tone, a hover blip |

## Overlays

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 35 | `nkModal` | A centred dialog over a dimmed window | a confirm, a form |
| 36 | `nkDrawer` | A panel docked to one edge (the side reuses `pSource`) | a settings drawer |
| 37 | `nkPopover` | A small panel anchored to the node it sits inside | a date picker anchor |
| 38 | `nkTooltip` | A hint shown after the pointer rests on its node | "this is a millisecond" |
| 39 | `nkMenu` | A menubar or a dropdown menu | a top menubar |
| 40 | `nkContextMenu` | A menu at a right click (or long press) on its node | cell actions in a list |

## Graphics, embedding, composition

| wire id | Nim name | plain-English meaning | typical use |
|---:|---|---|---|
| 34 | `nkCanvas` | An immediate-mode drawing surface fed by `pDraw` | a chart drawn by hand, a game field |
| 43 | `nkPath` | A vector shape from SVG path data | icons (`icon "search"`) and drawings |
| 42 | `nkAppView` | Another Yantra app, sandboxed, drawn in this box (`pSource` names it) | a plugin inside a shell |

---

# Props (265)

## The ~30 props an app author actually needs

If you read nothing else in this chapter, learn these. They cover layout, colour,
type, state and the common interactions.

| DSL name | prop | one-line meaning |
|---|---|---|
| `width` / `height` | `pWidth` / `pHeight` | the node's box size in px |
| `minWidth` `minHeight` `maxWidth` `maxHeight` | `pMin*`/`pMax*` | size clamps |
| `padding` / `padTop`… `padLeft` | `pPadTop`… | inset inside the node |
| `marginTop`… `marginLeft` | `pMargin*` | space outside the node |
| `gap` | `pSpacing` | space between a column's/row's children |
| `grow` | `pFlexGrow` | share of leftover space (the workhorse) |
| `shrink` | `pFlexShrink` | how readily a node gives space back |
| `fill` | `pColor` | background colour |
| `color` | `pTextColor` | text/ink colour |
| `radius` | `pRadius` | corner rounding in px |
| `border` / `borderColor` | `pBorderWidth` / `pBorderColor` | the outline |
| `shadow` | `pShadow*` | drop shadow (a `shadow(...)` value) |
| `opacity` | `pOpacity` | 1 = opaque, 0 = invisible |
| `visible` | `pVisible` | draw it or skip it |
| `fontSize` / `size` | `pFontSize` | text size in px |
| `weight` | `pFontWeight` | 400 body, 700 heading |
| `font` | `pFontFamily` | family name, or `mono` |
| `align` | `pAlign` | left / center / right text |
| `lineHeight` | `pLineHeight` | leading |
| `text` | `pText` | the node's string |
| `value` | `pValue` | a field's current value |
| `placeholder` | `pPlaceholder` | an empty field's hint |
| `checked` | `pChecked` | box / radio / switch state |
| `disabled` | `pDisabled` | grey it out and ignore input |
| `onclick` / `oninput` | `evClick` / `evInput` | the events that drive the app |
| `scroll` | `pScroll` | make this box scrollable |
| `z` | `pZIndex` | stacking order |
| `animate` / `transition` | `pAnim*` / `pTrans*` | motion |

Everything below is here when you need it.

## 1 · Text, geometry and visibility (0–11)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 0 | `pText` | string | The node's string. The window title, a label, a button's caption, an input's hint | `text "Total: {n}"`; `button "Save"` |
| 1 | `pX` | float32 | Horizontal offset in px (relative unless `absolute`) | `x = 12` — nudge a card right |
| 2 | `pY` | float32 | Vertical offset in px | `y = -2` — a pressed-state nudge |
| 3 | `pWidth` | int32 | Width in px. Layout reads this as a hard width | `width = 400` |
| 4 | `pHeight` | int32 | Height in px | `height = 220` |
| 5 | `pVisible` | bool | Whether the node is drawn and takes part in layout | `visible = ready` |
| 6 | `pColor` | int32 | DSL `fill`. The node's background colour, packed `0xAARRGGBB`; for a Mesh the material base colour | `fill = surface` or `fill = linear(0xFF7A2F, 0xFFD28A, 135)` |
| 7 | `pFontSize` | int32 | DSL `fontSize` / `size`. Text size in px | `fontSize = 18` |
| 8 | `pAlign` | int32 | Text alignment: `0` left, `1` center, `2` right (`Align` enum) | `align = center` |
| 9 | `pOpacity` | float32 | 1 = fully drawn, 0 = invisible; a fade animates it | `opacity = 0.6` |
| 10 | `pSource` | string | Overloaded by node kind: a model's mesh/asset, an image's path, a Flex's direction, a Chart's type, a Drawer's side, a Radio's group, an AppView's app name | `model(parent, "#Sphere")`; `flex(parent, "column")` |
| 11 | `pScale` | float32 | Uniform scale factor, 1 = as made. Not three axes — non-uniform scaling has no wire id | `scale = 1.08` (hover lift) |

## 2 · 3D transform & material (12–19)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 12 | `pRotX` | float32 | Pitch, degrees | `rotX = 15.deg` |
| 13 | `pRotY` | float32 | Yaw, degrees — the spin you see on a cube | `rotY = 45.deg` |
| 14 | `pRotZ` | float32 | Roll, degrees. DSL `rotate` | `rotate = 90` (2D UI rotation uses this) |
| 15 | `pPosX` | float32 | Position along X, scene units (a Model's offset; a Camera's eye) | `posX = -2` |
| 16 | `pPosY` | float32 | Position along Y (up) | `posY = 1.5` |
| 17 | `pPosZ` | float32 | Position along Z | `posZ = 4` |
| 18 | `pMetalness` | float32 | 0 = dielectric (plastic), 1 = metal. DSL `metal` | `metal = 0.9` |
| 19 | `pRoughness` | float32 | 0 = mirror, 1 = fully diffuse. DSL `rough` | `rough = 0.35` |

## 3 · Box model: spacing, padding, radius, border (20–27)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 20 | `pSpacing` | int32 | DSL `gap` / `spacing`. The gap between a Column's or Row's children. Was hardcoded to 10 in the renderer once — now yours | `gap = 12` |
| 21 | `pPadTop` | int32 | Inset from the top edge, px. Also the anchor DSL `pad` / `padding` writes to | `pad = 16` |
| 22 | `pPadRight` | int32 | Inset from the right edge, px | `padRight = 8` |
| 23 | `pPadBottom` | int32 | Inset from the bottom edge, px | `padBottom = 16` |
| 24 | `pPadLeft` | int32 | Inset from the left edge, px | `padLeft = 8` |
| 25 | `pRadius` | int32 | Corner rounding in px | `radius = 12` |
| 26 | `pBorderColor` | int32 | The outline's colour, `0xAARRGGBB` | `borderColor = line` |
| 27 | `pBorderWidth` | int32 | The outline's thickness in px. DSL `border` | `border = 1` |

## 4 · Animation & transition (28–39)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 28 | `pAnimTarget` | string | **Which property** the animation moves: `"opacity"`, `"x"`, `"y"`, `"width"`, `"height"`, `"scale"`, `"rotation"`. Set last — the engine starts the animation when it sees it | `animate = "opacity"` |
| 29 | `pAnimFrom` | float32 | The start value. Unset: whatever the node's value is now | `animate(target = "scale", from = 0.9, to = 1.0)` |
| 30 | `pAnimTo` | float32 | The end value | `animate(target = "opacity", to = 1.0, duration = 250)` |
| 31 | `pAnimDuration` | int32 | Milliseconds | `duration = 300` |
| 32 | `pAnimEasing` | int32 | The curve, from the `Easing` enum (0 linear … 34 springStiff) | `easing = easeOutCubic` |
| 33 | `pAnimDelay` | int32 | Milliseconds to wait before starting | `delay = 120` |
| 34 | `pAnimLoop` | int32 | How many times to run. **0 = forever** | `loop = 0` |
| 35 | `pAnimYoyo` | bool | Reverse direction on each repeat | `yoyo = true` |
| 36 | `pAnimTrigger` | string | When it starts: `"mount"`, `"click"`, `"hover"`, `"focus"`, `"prop:<name>"` | `trigger = "hover"` |
| 37 | `pTransition` | string | Which layout change to animate: `"enter"`, `"exit"`, `"move"`, `"resize"`, `"opacity"` | `transition = "move"` |
| 38 | `pTransDuration` | int32 | Transition length in ms. DSL `transition` | `transition = 180.ms` |
| 39 | `pTransEasing` | int32 | Transition curve (`Easing`). DSL `ease` | `ease = outBack` |

## 5 · Form & input state (40–55)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 40 | `pValue` | string / float32 / int32 / bool | A field's current value. All four setter overloads exist, so write whichever fits | `value = 42`; `input draft` binds it two ways |
| 41 | `pPlaceholder` | string | The hint shown while an empty Input/TextArea has focus | `placeholder = "Search…"` |
| 42 | `pMin` | float32 | Lowest accepted value — a Slider's floor, a Progress bar's zero | `slider(parent, minVal = 0, maxVal = 100)` |
| 43 | `pMax` | float32 | Highest accepted value; a Progress bar's full mark | `max = 100` |
| 44 | `pStep` | float32 | Granularity for a Slider or a numeric field | `step = 5` |
| 45 | `pChecked` | bool | Tick state of a Checkbox, Radio or Switch | `checked = subscribed` |
| 46 | `pOptions` | string | A Select's choices as JSON: `[{"label": "One", "value": "1"}, …]` | `options = """[{"label":"A","value":"1"}]"""` |
| 47 | `pMultiple` | bool | A Select accepts more than one value | `multiple = true` |
| 48 | `pDisabled` | bool | Grey it out; clicks and typing are ignored | `disabled = saving` |
| 49 | `pRequired` | bool | Validation: the field must be filled | `required = true` |
| 50 | `pReadOnly` | bool | Shown and selectable, not editable | `readOnly = true` |
| 51 | `pMaxLength` | int32 | Characters the field accepts | `maxLength = 140` |
| 52 | `pPattern` | string | A validation pattern for the field's text | `pattern = "^[a-z]+$"` |
| 53 | `pFlexGrow` | float32 | DSL `grow`. Share of the leftover space this node takes | `grow = 1` |
| 54 | `pFlexShrink` | float32 | DSL `shrink`. How readily it gives space back when space runs out (1 = default) | `shrink = 0` |
| 55 | `pFlexBasis` | float32 | The size this node starts from before grow/shrink are applied | `flexBasis = 120` |

## 6 · Grid, stacking and scrolling (56–62)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 56 | `pGridCols` | string | DSL `columns` / `source`. The grid-template-columns string: `1fr 2fr 200` | `grid "1fr 1fr", spacing = 12` |
| 57 | `pGridRows` | string | The grid-template-rows string | `gridRows = "auto 1fr auto"` |
| 58 | `pGridGap` | int32 | Space between grid tracks, px | `gridGap = 12` |
| 59 | `pZIndex` | int32 | DSL `z`. Stacking order among siblings | `z = 10` — a menu above the page |
| 60 | `pOverflow` | string | What happens to content past the box: `"visible"`, `"hidden"`, `"scroll"`, `"auto"` | `overflow = "hidden"` |
| 61 | `pScrollX` | int32 | Current horizontal scroll offset, px; each new value scrolls there | `scrollX = 0` |
| 62 | `pScrollY` | int32 | DSL `scrollTo`. Current vertical offset in px; each new value scrolls there | `scrollTo = 800` |

## 7 · Tabs, tables and lists (63–69)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 63 | `pTabIndex` | int32 | Which tab of a Tabs container is showing | `tabIndex = 1` |
| 64 | `pTabCount` | wire-level only | How many pages the Tabs container holds. The engine maintains it; there is no SDK setter | (engine-maintained) |
| 65 | `pColumns` | string | A Table's header definitions, JSON-ish: `["Name","Age"]` | `columns = """["Name","Age"]"""` |
| 66 | `pRows` | string / int32 | A Table's or Chart's data rows (string), **or** a TextArea's visible line count (int32) — the two uses share one id | `rows = """[["Ada",36]]"""`; `rows = 8` |
| 67 | `pSelection` | string | Which row/cell is selected; the id of the selected row | `selection = "3"` |
| 68 | `pSortable` | bool | A Table's column headers become clickable sorters | `sortable = true` |
| 69 | `pFilterable` | bool | A Table gets a filter box | `filterable = true` |

## 8 · Media playback (70–78)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 70 | `pSrc` | string | The media file to load | `video "clip.mp4"` |
| 71 | `pPoster` | string | The still shown before playback starts | `poster = "thumb.png"` |
| 72 | `pAutoplay` | bool | Start playing once ready | `autoplay = true` |
| 73 | `pLoop` | bool | Restart at the end, forever | `loop = true` |
| 74 | `pMuted` | bool | Silence the output (still shows a picture) | `muted = true` |
| 75 | `pVolume` | float32 | Output level, 0–1 | `volume = 0.6` |
| 76 | `pPlaybackRate` | float32 | Speed multiplier: 1 normal, 2 double | `playbackRate = 1.5` |
| 77 | `pCanvasWidth` | int32 | The drawing surface's pixel width, set alongside `pWidth` | `canvas(parent, w = 400, h = 300)` |
| 78 | `pCanvasHeight` | int32 | The drawing surface's pixel height, set alongside `pHeight` | same |

## 9 · Overlays (79–82)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 79 | `pModalOpen` | bool | DSL `open`. Whether the overlay is showing. **Not set means it stays open while it exists** | `open = showDialog` |
| 80 | `pModalTitle` | string | A Modal's title bar text | `modal(parent, "Delete file?")` |
| 81 | `pCloseOnEsc` | bool | Escape dismisses it (and fires `onDismiss`) | `closeOnEsc = true` |
| 82 | `pCloseOnClickOutside` | bool | A click on the dimmed backdrop dismisses it | `closeOnClickOutside = true` |

## 10 · Event-handler slots (83–87)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 83 | `pOnChange` | wire-level only | Handler id for `evChange`, "the value settled" (blur or Enter, not every keystroke). No SDK setter — attach with `node.on(evChange, …)` | `node.on(evChange, proc() = …)` |
| 84 | `pOnInput` | wire-level only | Handler id for `evInput`, every keystroke. `onInput(node, handler)` wraps it | `input draft` binds this automatically |
| 85 | `pOnFocus` | wire-level only | Handler id for `evFocus`. `onFocus(node, handler)` wraps it | `node.onFocus(proc() = …)` |
| 86 | `pOnBlur` | wire-level only | Handler id for `evBlur`. `onBlur(node, handler)` wraps it | `node.onBlur(proc() = …)` |
| 87 | `pOnSubmit` | wire-level only | Handler id for `evSubmit`, Enter in a single-line input. Nothing in the SDK sets it — the DSL's `onsubmit:` attaches it | `onsubmit: save()` |

## 11 · Typography (88–89, 115–118)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 88 | `pFontWeight` | int32 | DSL `weight`. 400 body, 600 subhead, 700 heading | `weight = 700` |
| 89 | `pTextColor` | int32 | DSL `color` / `textColor`. The ink: text, icon and label colour | `color = muted` |
| 115 | `pFontFamily` | string | DSL `font`. A family name, or the word `mono` (which reads the theme's monospace) | `font = mono` |
| 116 | `pLineHeight` | float32 | Leading — extra space between lines, px | `lineHeight = 24` |
| 117 | `pItalic` | bool | Italic text | `italic = true` |
| 118 | `pMaxLines` | int32 | Truncate after this many lines with an ellipsis | `maxLines = 2` |

## 12 · Margin, size clamps, flex alignment (90–101)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 90 | `pMarginTop` | float32 | Space above the node, outside its box | `marginTop = 8` |
| 91 | `pMarginRight` | float32 | Space to the right, outside its box | `marginRight = 8` |
| 92 | `pMarginBottom` | float32 | Space below the node | `marginBottom = 24` |
| 93 | `pMarginLeft` | float32 | Space to the left | `marginLeft = 8` |
| 94 | `pMinWidth` | float32 | Width floor. `0` means "may collapse" — what a virtual list sets so a spacer can be thin | `minWidth = 0` |
| 95 | `pMinHeight` | float32 | Height floor | `minHeight = 44` (a tappable target) |
| 96 | `pMaxWidth` | float32 | Width ceiling | `maxWidth = 720` (a readable measure) |
| 97 | `pMaxHeight` | float32 | Height ceiling | `maxHeight = 400` |
| 98 | `pAlignItems` | int32 | Cross-axis alignment of children: `0` start, `1` center, `2` last, `3` stretch | `alignItems = center` |
| 99 | `pJustify` | int32 | Main-axis distribution: `0` start, `1` center, `2` last, `3` between, `4` around, `5` evenly | `justify = between` |
| 100 | `pWrap` | bool | Let a row's children wrap onto more lines | `wrap = true` |
| 101 | `pAbsolute` | bool | Take the node out of flow; `x`/`y`/insets place it | `absolute = true` |

## 13 · Absolute insets, scrolling and clipping (102–107)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 102 | `pInsetTop` | float32 | DSL `top`. Offset from the parent's top edge | `top = 0` |
| 103 | `pInsetRight` | float32 | DSL `right` | `right = 12` |
| 104 | `pInsetBottom` | float32 | DSL `bottom` | `bottom = 0` |
| 105 | `pInsetLeft` | float32 | DSL `left` | `left = 12` |
| 106 | `pScroll` | bool | Make this box scrollable on both axes as needed | `column(scroll = true)` |
| 107 | `pClip` | bool | Cut children off at the box's edge instead of letting them show | `clip = true` |

## 14 · Gradients and shadows (108–114)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 108 | `pGradFrom` | int32 | A gradient's start colour | `fill = linear(0xFF7A2F, 0xFFD28A, 135)` |
| 109 | `pGradTo` | int32 | The gradient's end colour | same |
| 110 | `pGradAngle` | float32 | Gradient direction in degrees, 90 = top to bottom. **A plain colour sets this to `-1`, which switches any gradient off** | `linear(a, b, 45)` |
| 111 | `pShadowX` | float32 | Shadow offset on X, px | `shadow = shadow(y = 8, blur = 24)` |
| 112 | `pShadowY` | float32 | Shadow offset on Y — the one you actually change | `shadow(y = 6)` |
| 113 | `pShadowBlur` | float32 | Shadow softness in px | `blur = 18` |
| 114 | `pShadowColor` | int32 | Shadow colour, normally `rgba(0x000000, 0.35)` | `rgba(0x000000, 0.25)` |

## 15 · Vector paths (119–120)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 119 | `pPathData` | string | DSL `d`. SVG path data for a Path node. `icon "search"` fills it from the built-in icon set | `d = "M4 4 L20 20"` |
| 120 | `pStrokeWidth` | float32 | DSL `stroke`. The path's line thickness | `stroke = 1.8` |

## 16 · Cursor and interaction states (121–133)

These twelve are what the DSL's `hover:` / `pressed:` / `focused:` blocks write.
You can also set them directly with `node.set(pHoverFill, …)`. Inside a state
block, the short names are `fill`, `color`, `borderColor`, `opacity`, `scale`,
`y`; anything else is a compile error (Y013).

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 121 | `pCursor` | int32 | The mouse pointer over this node: `0` arrow, `1` hand, `2` I-beam/text | `cursor = hand` |
| 122 | `pHoverFill` | int32 | Background while the pointer is on the node | `hover: fill = surface2` |
| 123 | `pHoverColor` | int32 | Text colour on hover | `hover: color = text` |
| 124 | `pHoverBorder` | int32 | Border colour on hover | `hover: borderColor = accent` |
| 125 | `pHoverOpacity` | float32 | Opacity on hover | `hover: opacity = 0.9` |
| 126 | `pPressFill` | int32 | Background while the pointer is held down | `pressed: fill = accentSoft` |
| 127 | `pPressColor` | int32 | Text colour while pressed | `pressed: color = text` |
| 128 | `pPressBorder` | int32 | Border colour while pressed | `pressed: borderColor = accent` |
| 129 | `pPressOpacity` | float32 | Opacity while pressed | `pressed: opacity = 1.0` |
| 130 | `pFocusFill` | int32 | Background while the node has keyboard focus | `focused: fill = accentSoft` |
| 131 | `pFocusColor` | int32 | Text colour while focused | `focused: color = text` |
| 132 | `pFocusBorder` | int32 | Border colour while focused — the standard focus ring | `focused: borderColor = accent` |
| 133 | `pFocusOpacity` | float32 | Opacity while focused | `focused: opacity = 1.0` |

## 17 · Theme, motion presets and scroll-linked motion (134–136, 155–156)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 134 | `pTheme` | string | The theme name on a window: how a shell's theme reaches the apps inside it. Set by `theme()`, not by hand | `setTheme("dark")` |
| 135 | `pEnter` | string | The pose played when the node appears, encoded `"opacity,x,y,scale,rotate,ms,delay,easing"`. `enter = …` builds it from a `Motion` | `enter = rise(16)` |
| 136 | `pExit` | string | The pose played after the app removes the node, same encoding | `exit = fade(200)` |
| 155 | `pReveal` | string | The pose held while out of view; eased into itself as it scrolls in (enter's format) | `reveal = rise(24)` |
| 156 | `pParallax` | float32 | This fraction of its distance from the view's middle (0.3 = moves slower than the page) | `parallax = 0.3` |

## 18 · Motion scale/offset states (137–142)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 137 | `pHoverScale` | float32 | Scale while hovered — the classic button lift | `hover: scale = 1.02` |
| 138 | `pPressScale` | float32 | Scale while pressed (goes *down*: 0.97) | `pressed: scale = 0.97` |
| 139 | `pFocusScale` | float32 | Scale while keyboard-focused | `focused: scale = 1.01` |
| 140 | `pHoverY` | float32 | Vertical offset while hovered, px (a tooltip rising) | `hover: y = -2` |
| 141 | `pPressY` | float32 | Vertical offset while pressed, px | `pressed: y = 1` |
| 142 | `pFocusY` | float32 | Vertical offset while focused, px | `focused: y = -1` |

## 19 · Identity, media fit and effects (143–152)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 143 | `pSite` | string | Dev builds only: `"file.nim:line:col"` of the code that made the node. Hot reload and inspectors use it; you never write it | set for you by the DSL |
| 144 | `pFit` | int32 | DSL `fit`. How media fills its box: `0` contain, `1` cover, `2` fill. The DSL also accepts the words | `fit = cover` |
| 145 | `pName` | string | The `@handle` you gave a node — a stable name for code, tests, tools and AI edits | `text @headline "Hi"` |
| 146 | `pBlur` | float32 | Gaussian blur of the node itself, px | `blur = 12` |
| 147 | `pBackdropBlur` | float32 | Blur of what is *behind* the node — frosted glass | `backdropBlur = 16` |
| 148 | `pBlend` | int32 | Blend mode: `3` normal, `12` plus, `14` screen, `15` overlay, … `28` luminosity. DSL also takes the words | `blend = screen` |
| 149 | `pSaturate` | float32 | Saturation: 1 as given, 0 greyscale | `saturate = 0` |
| 150 | `pBrightness` | float32 | Brightness: 1 as given | `brightness = 1.1` |
| 151 | `pContrast` | float32 | Contrast: 1 as given | `contrast = 0.9` |
| 152 | `pShader` | string | DSL `shader`. SkSL for the GPU-class effects; it may declare `uniform float2 size;` and `uniform float time;` | `shader = sksl"…"` |

## 20 · Rich text, network and anchored overlays (153–158)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 153 | `pSpan` | int32 | DSL `span`. How many grid columns a grid item takes | `span = 2` |
| 154 | `pNet` | string | DSL `net`. On the window: the hosts this app may fetch from, `"api.example.com, *.example.org"` | `app "X", net = "api.example.com"` |
| 157 | `pSpans` | string | Styled runs over a Text's bytes: `"start,end,flags,argb,size;…"`. `rich "**bold** [link](url)"` builds it | written by `sdk/ui/rich.nim` |
| 158 | `pPlacement` | int32 | Where a popover/menu/tooltip sits by its anchor: `0` below, `1` above, `2` right, `3` left. It flips to fit | `placement = 1` |

## 21 · Media state and scroll helpers (159–162)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 159 | `pStickToEnd` | bool | A scroll area that was at its end stays there as content grows | `stickToEnd = true` (a log) |
| 160 | `pPlaying` | bool | Video/Audio/Synth: 1 plays, 0 pauses. **Not set means a video plays**, as before | `playing = held` |
| 161 | `pSeekTo` | float32 | Video/Audio: seconds; each new value seeks there | `seek = 12.5` |
| 162 | `pWaveform` | int32 | Audio: how many peaks to measure, read back with `node.waveform()` once MediaReady arrives | `waveform = 64` |

## 22 · Block editing, sticky headers, canvas and RTL (163–167)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 163 | `pBlock` | bool | The Input/TextArea is one block of a document: arrows cross blocks, Enter splits, Backspace at 0 merges | `block = true` |
| 164 | `pSticky` | float32 | Px from the top of the scrolling view this node sticks at, inside its own container | `sticky = 0` (a header) |
| 165 | `pStickyLeft` | float32 | Px from the left of the view it sticks at — a frozen column | `stickyLeft = 120` |
| 166 | `pDraw` | string | DSL `draw`. The Canvas's draw-command list (paths, shapes, text, images, layers, raw pixels, blend modes) | `canvas(draw = d.cmds)` |
| 167 | `pDirection` | int32 | Right-to-left: `0` inherit, `1` left-to-right, `2` right-to-left. Layout mirrors and text lays out RTL | `direction = 2` |

## 23 · Virtual lists (168–171)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 168 | `pAnchor` | bool | A scroll area keeps its first visible ItemKey row still when things above it change size — no jumping on insert | set by the virtual-list helper |
| 169 | `pStickBottom` | bool | A scroll area at its end stays there as content grows (a chat); it *starts* at the end | `stickBottom = true` |
| 170 | `pItemKey` | string | A row's stable key, for `pAnchor` and `pScrollToKey` | `itemKey = $item.id` |
| 171 | `pScrollToKey` | string | Bring the row with this ItemKey to the top. Append `"#n"` to jump again to the same key | `scrollToKey = key & "#1"` |

## 24 · Links, inline images and find-in-page (172–175)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 172 | `pLinks` | string | Text: clickable byte ranges `"start,end;…"`. `evLinkClick` says which (axis 10) | written by `rich` / link runs |
| 173 | `pInline` | string | Text: `"w,h,path;…"` one per U+FFFC in its text — images or emoji inside the line | `inline = "16,16,star.png"` |
| 174 | `pFind` | string | Window: the find-in-page query (case-insensitive) over Text nodes; the count reads back on axis 11 | `find = query` |
| 175 | `pFindIndex` | int32 | Window: which match is current — highlighted strongly and scrolled into view (axis 12 reads it back) | `findIndex = 2` |

## 25 · Smooth input, OS integration, spelling (176–186)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 176 | `pSmooth` | bool | A scroll area glides to `scrollTo`/`scrollToKey` targets instead of jumping | `smooth = true` |
| 177 | `pZoomable` | bool | Image: pinch or Ctrl+wheel zooms (1×–8×), drag pans, double click resets | `zoomable = true` |
| 178 | `pFocusAt` | string | Input/TextArea: `"caret#n"` — each new value focuses it with the caret at that byte. The `#n` makes a repeat jump work | `focusAt = "12#1"` |
| 179 | `pFrameless` | bool | Window: no system title bar; the app draws its own | `app "X", frameless = true` |
| 180 | `pDragRegion` | bool | This node drags the frameless window; its clickable children stay clickable | `dragRegion = true` |
| 181 | `pWindowAction` | int32 | Clicking a window-control node: `1` minimise, `2` maximise/restore, `3` close, `4` fullscreen | `windowAction = 3` |
| 182 | `pMenu` | string | Window: the native menubar, `"File|New:1|Open:2|-|Quit:3;Edit|Copy:4"`. `evMenuCommand` reports the id | `menu = "File|Open:1|-|Quit:3"` |
| 183 | `pBadge` | int32 | Window: the count on the taskbar button (0 = none) | `badge = unread` |
| 184 | `pScheme` | string | Window: `"myapp"` registers `myapp://` for this app; links arrive as `evDeepLink` | `scheme = "notes"` |
| 185 | `pSpellcheck` | bool | Input/TextArea: misspelled words get a red underline; right-click fires `evSpellMenu` | `spellcheck = true` |
| 186 | `pReplace` | string | Input/TextArea: `"start,end,text#n"` — each new value replaces those bytes as an undoable edit that fires `evInput` | `replace = "0,4,\"Yantra\"#1"` |

## 26 · 3D: mesh size, camera & light targeting (187–194)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 187 | `pSizeX` | float32 | Mesh: size across X, metres (a built-in shape is 1 across) | `sizeX = 2` |
| 188 | `pSizeY` | float32 | Mesh: size across Y, metres | `sizeY = 2` |
| 189 | `pSizeZ` | float32 | Mesh: size across Z, metres | `sizeZ = 2` |
| 190 | `pTargetX` | float32 | Where a Camera or Light points, X | `targetY = 0, targetZ = 0` |
| 191 | `pTargetY` | float32 | Where it points, Y | same |
| 192 | `pTargetZ` | float32 | Where it points, Z | same |
| 193 | `pFov` | float32 | Camera: vertical field of view in degrees (narrower = longer lens) | `fov = 45` |
| 194 | `pIntensity` | float32 | Light: lux (sun) or lumens (point, spot) | `intensity = 8000` |

## 27 · 3D: shape, emission, scene atmosphere (195–207)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 195 | `pShape` | int32 | Mesh: `0` box, `1` sphere, `2` plane, `3` cylinder. The DSL's `box`/`sphere`/`plane`/`cylinder` set it for you | `box(sizeX = 1, fill = 0xFFCC4444)` |
| 196 | `pGlow` | int32 | Mesh/Particles: the emissive colour `0xRRGGBB` — bloom picks it up | `glow = 0xFF66CCFF` |
| 197 | `pFog` | float32 | Scene3D: fog density, 0 = none | `fog = 0.02` |
| 198 | `pFogColor` | int32 | Scene3D: the fog's colour | `fogColor = 0xFF8899AA` |
| 199 | `pSky` | int32 | Scene3D: the sky colour. Not set means a transparent background | `sky = 0x87CEEB` |
| 200 | `pShadows` | bool | Scene3D: shadow maps on (the default) / off. On a Light: does it cast shadows | `shadows = true` |
| 201 | `pBloom` | float32 | Scene3D: bloom strength, 0 = off | `bloom = 0.4` |
| 202 | `pSsao` | bool | Scene3D: ambient occlusion — contact darkening in the corners | `ssao = true` |
| 203 | `pGeometry` | int32 | Mesh: a buffer (`y_buf`) holding its own vertices and triangles | `mesh(geometry = buf)` |
| 204 | `pInstances` | int32 | Mesh/Model: a buffer of 4×4 matrices — one copy of the mesh per matrix | `instances = mats` |
| 205 | `pLightKind` | int32 | Light: `0` sun, `1` point, `2` spot | `lightKind = 1` |
| 206 | `pAnimation` | int32 | Model: which of its animations plays, `-1` for none | `animation = 0` |
| 207 | `pAmbient` | float32 | Scene3D: the sky's soft light, lux | `ambient = 0.2` |

## 28 · 3D: input, shaders (208–211)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 208 | `pPointerLock` | bool | Window: the pointer is hidden and held; `mouseDelta()` gives raw movement. Escape releases it | `app "Game", pointerLock = true` |
| 209 | `pVertexShader` | string | Mesh: the body of `materialVertex()` — move `material.worldPosition` for waves, wind. DSL `vertex` | `vertex = "…"` |
| 210 | `pUniforms` | string | Mesh: up to 16 numbers `"a,b,c,…"` the shader reads as `materialParams.u[0..3]` | `uniforms = "2.0,0.5,0,0"` |
| 211 | `pUnlit` | bool | Mesh: no lighting — the shader's (or `fill`'s) colour is the colour as drawn | `unlit = true` |

## 29 · Synth: the 13 props that make a sound (212–224)

A Synth is a whole voice: wave → filter → envelope → echo. It is not laid out,
so it can be a child of anything.

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 212 | `pWave` | int32 | Oscillator: `0` sine, `1` square, `2` triangle, `3` saw, `4` white, `5` pink, `6` brown noise | `wave = 3` (saw) |
| 213 | `pFreq` | float32 | Pitch in Hz | `freq = 440` |
| 214 | `pFilterKind` | int32 | DSL `filter`: `0` none, `1` low-pass, `2` high-pass, `3` band-pass | `filter = 1` |
| 215 | `pCutoff` | float32 | The filter's frequency in Hz | `cutoff = 800` |
| 216 | `pResonance` | float32 | The filter's Q; `0.707` is flat | `resonance = 6` |
| 217 | `pPan` | float32 | −1 hard left … 1 hard right | `pan = -0.4` |
| 218 | `pAttack` | float32 | Seconds to full volume when `playing` turns on | `attack = 0.005` |
| 219 | `pRelease` | float32 | Seconds to silence when `playing` turns off | `release = 0.2` |
| 220 | `pEcho` | float32 | Echo delay in seconds, 0 = none | `echo = 0.25` |
| 221 | `pEchoMix` | float32 | How loud the echo is, 0–1 | `echoMix = 0.3` |
| 222 | `pEchoFeedback` | float32 | How much each echo repeats, 0–0.95 | `echoFeedback = 0.4` |
| 223 | `pLfo` | float32 | Vibrato rate in Hz | `lfo = 5` |
| 224 | `pLfoDepth` | float32 | Vibrato depth as a fraction of the pitch | `lfoDepth = 0.01` |

## 30 · 3D textures & picking (225–227)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 225 | `pTexture` | string | Mesh/Particles: an image file (png/jpeg) over its surface, multiplied by its fill colour | `texture = "wood.png"` |
| 226 | `pTiling` | float32 | Mesh: how many times the image repeats across (and down, unless `pTilingY`) | `tiling = 4` |
| 227 | `pTilingY` | float32 | How many times it repeats down, when it differs from `pTiling` | `tilingY = 8` |

## 31 · Physics (228–233)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 228 | `pBody` | int32 | Mesh: `1` fixed, `2` dynamic (falls, collides), `3` kinematic (the app moves it, it still pushes) | `body = 2` |
| 229 | `pMass` | float32 | Mesh: kilograms. Not set means it comes from the mesh's size | `mass = 5` |
| 230 | `pFriction` | float32 | Mesh: `0` ice … `1` rubber | `friction = 0.6` |
| 231 | `pBounce` | float32 | Mesh: `0` dead … `1` bouncy | `bounce = 0.4` |
| 232 | `pDamping` | float32 | Mesh: how fast it slows down in the air | `damping = 0.1` |
| 233 | `pGravity` | float32 | Scene3D/Particles: m/s² downwards (`9.81` is Earth) | `gravity = 9.81` |

## 32 · 3D: the finish — post-processing (234–242)

All on Scene3D. Contrast and saturate here are the FX1 2D props above; these
nine are camera-and-screen only.

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 234 | `pTaa` | bool | Temporal anti-aliasing — smooth edges, stable detail | `taa = true` |
| 235 | `pFocus` | float32 | Depth of field: the distance in focus, metres (0 = off) | `focus = 5` |
| 236 | `pDofBlur` | float32 | How strong the out-of-focus blur is | `dofBlur = 3` |
| 237 | `pReflections` | bool | Screen-space reflections (wet streets, glass) | `reflections = true` |
| 238 | `pVignette` | float32 | Darkened corners, 0–1 | `vignette = 0.25` |
| 239 | `pExposure` | float32 | EV stops; +1 is twice as bright | `exposure = 0.3` |
| 240 | `pToneMap` | int32 | `0` ACES, `1` filmic, `2` AgX, `3` neutral, `4` linear | `toneMap = 1` |
| 241 | `pFogHeight` | float32 | Height fog: where it starts, metres | `fogHeight = 2` |
| 242 | `pFogFalloff` | float32 | Height fog: how fast it thins going up | `fogFalloff = 0.2` |

## 33 · 3D materials (243–249)

All on Mesh. A map is a file name, `"layer:N"`, or `"pixels:BUF:W:H"`.

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 243 | `pNormalMap` | string | Bumps and grooves without adding geometry | `normalMap = "brick_n.png"` |
| 244 | `pNormalScale` | float32 | How strong the normal map is (1 = as drawn) | `normalScale = 1.5` |
| 245 | `pOrmMap` | string | Occlusion (r), roughness (g), metal (b) packed, like glTF | `ormMap = "brick_orm.png"` |
| 246 | `pEmissiveMap` | string | Where it glows, multiplied by `glow` | `emissiveMap = "grid.png"` |
| 247 | `pAlphaMode` | int32 | `0` opaque, `1` blended (glass, water), `2` cut out (leaves, fences) | `alphaMode = 1` |
| 248 | `pAlphaCutoff` | float32 | Cut out below this alpha | `alphaCutoff = 0.5` |
| 249 | `pColors` | int32 | A buffer of RGBA bytes — one colour per instance | `colors = buf` |

## 34 · Character animation (250–253)

All on a Model inside a Scene3D.

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 250 | `pAnimClip` | string | DSL `play`. The animation playing, by name; changing it crossfades | `play = "Run"` |
| 251 | `pBlendTime` | float32 | Seconds a clip change crossfades over (default 0.25) | `blendTime = 0.2` |
| 252 | `pAnimSpeed` | float32 | `1` as made, `2` twice as fast, `0` paused | `animSpeed = 0` |
| 253 | `pAnimTime` | float32 | Seconds into the clip, set by the app. Not set means the engine's own clock runs | `animTime = 1.2` |

## 35 · Particles (254–262)

All on Particles. Position/rotation place the *emitter*; the sprites spray along
its up.

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 254 | `pRate` | float32 | New particles per second | `rate = 200` |
| 255 | `pBurst` | string | Each new value emits that many at once (an explosion) | `burst = "40#1"` |
| 256 | `pLifetime` | float32 | Seconds each particle lives | `lifetime = 1.5` |
| 257 | `pSpeed` | float32 | m/s they leave at | `speed = 4` |
| 258 | `pSpread` | float32 | Degrees around the emitter's up they scatter; 180 = every way | `spread = 30` |
| 259 | `pPartSize` | float32 | Metres across when born | `partSize = 0.1` |
| 260 | `pPartSizeEnd` | float32 | Metres across when they die | `partSizeEnd = 0.02` |
| 261 | `pColorEnd` | int32 | The colour they fade to as they age (`fill` is the colour they're born) | `colorEnd = 0x00FF2000` |
| 262 | `pMaxCount` | int32 | How many at once at most (default 1000) | `maxCount = 500` |

## 36 · Render-to-texture & fullscreen (263–264)

| wire id | Prop | type | what it controls | example |
|---:|---|---|---|---|
| 263 | `pTarget` | string | Camera: draw into the texture of this name (a map can be `"view:NAME"`); `width`/`height` are its size | `target = "view:mirror"` |
| 264 | `pFullscreen` | bool | Window: take over the whole screen (the Yantra desktop) | `app "Deck", fullscreen = true` |

---

# How the DSL names props

The DSL is case-insensitive and matches a prop name against three lists before it
touches the wire.

## Length props — the unit check

```nim
const lengthProps = ["width", "height", "minwidth", "maxwidth", "minheight", "maxheight",
  "pad", "padding", "padx", "pady", "padtop", "padright", "padbottom", "padleft",
  "margin", "marginx", "marginy", "margintop", "marginright", "marginbottom", "marginleft",
  "gap", "spacing", "radius", "border", "top", "left", "right", "bottom", "x", "y",
  "size", "fontsize", "blur", "backdropblur"]
```

For each of these a value is wrapped in `lengthOf()`, so a *plain number* means px
and a **unit-carrying value must be the right one**: `width = 200.ms` is a
compile error (Y020), not a silent bug. Write `320.px`, or nothing at all.

```nim
column(width = 400):          # 400 px
text("Hi", fontSize = 18):    # 18 px
panel(padX = 12):             # left and right inset, 12 px
row(spacing = 8, marginTop = 8):
```

Two more lists exist for the same reason:

- `durationProps = ["transition"]` → `durationOf()`: use `200.ms` or `1.5.s`,
  never `200.px` (Y021).
- `angleProps = ["rotate"]` → `angleOf()`: use `45.deg`, never `45.px` (Y022).

## Shorthand rewrites

`dsl.nim` rewrites a handful of names before they reach `set()`:

| you write | becomes |
|---|---|
| `padx = v` | `pPadLeft = v` **and** `pPadRight = v` |
| `pady = v` | `pPadTop = v` **and** `pPadBottom = v` |
| `margin = v` | all four `pMargin*` |
| `marginx = v` / `marginy = v` | left+right / top+bottom |
| `gap = v` / `spacing = v` | `node.spacing(v)` |
| `pad = v` / `padding = v` | `node.padding(v)` — all four sides |
| `size = v` / `fontSize = v` | `node.fontSize(v)` |
| `width = v` / `height = v` | `node.width(v)` / `node.height(v)` |
| `fill = c` | `setFill(n, c)` — a colour **or** a gradient |
| `shadow = s` | `setShadow(n, s)` |
| `use = s` | `applyStyle(n, s)` — a reusable `style(...)` bundle |
| `enter`/`exit`/`reveal`/`animate` | `setEnter`/`setExit`/`setReveal`/`setLoop` |

Bare words are also accepted in place of numbers:

- `alignItems = center` → 1 (`start`/`first` 0, `last` 2, `stretch` 3)
- `justify = between` → 3 (also `around`, `evenly`, `center`, `start`, `last`)
- `cursor = hand` → 1 (also `arrow`, `ibeam`/`text`)
- `align = center` → 1 (also `left`, `right`)
- `fit = cover` → 1 (also `contain`, `fill`)
- `blend = screen` → 14 (a long list of named modes)
- `ease = outBack` → the `Easing` index; `easeOutBack` works too
- `font = mono` → the theme's monospace

And in any **colour** prop (`fill`, `color`, `textColor`, `borderColor`, `shadow`)
a bare theme word becomes a live read of the current theme, so it re-styles on a
theme switch: `bg`, `sidebar`, `surface`, `surface2`, `surface3`, `line`, `text`,
`muted`, `faint`, `accent`, `accentText`, `accentSoft`, `danger`, `success`.

---

# Where to go next

This chapter is the lookup table, not the tutorial. For the behaviour behind these
props, read the chapter that owns it:

- **Layout & sizing** — the flex/grid algorithm, `grow`/`shrink`, absolute
  positioning, container queries (`sized`, `scrolled`, `lazy`) and the overflow
  rules.
- **Text & typography** — fonts, weights, line height, rich text (`rich`,
  `spans`, `links`, `inline`) and find-in-page.
- **Canvas & painting** — `draw`, the command list, blend modes, layers, raw
  pixels and pointer events on a canvas.
- **Animation & motion** — `animate`, `transition`, `enter`/`exit`/`reveal`,
  the `Motion` presets, easing and spring curves, and scroll-linked motion.
- **3D scenes** — `scene3d`, meshes, materials, lights, cameras, physics,
  particles and post-processing.
- **Events & reactivity** — the 34 `ev*` events, Signals, effects and batched
  handlers.

Style values (`linear`, `rgba`, `shadow`, `style`/`use`) live in
`sdk/ui/style.nim`; the typed units (`px`, `ms`, `s`, `deg`) in
`sdk/ui/units.nim`; the generated DSL↔wire mapping with allowed nodes per prop in
`docs/HOW_IT_WORKS/props.md`.