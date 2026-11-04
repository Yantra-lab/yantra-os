## Yantra SDK — the surface an app author writes.
##
## AN APP IS A WASM MODULE. It has no window, no filesystem and no network. It
## builds a description of a UI by calling the host, and the host decides what to
## do with it. That is the whole security model: the sandbox cannot reach the
## machine, it can only ask.
##
## HOW A CALL CROSSES THE BOUNDARY
##
##     your Nim code            wasm                  the engine (native)
##     -------------            ----                  -------------------
##     text(parent, "Hi")  ->   node_create(i32)   -> creates a node
##                              node_set_str(...)  -> reads your text out of
##                                                    wasm linear memory
##     onClick = proc()    ->   node_on(...)       -> engine remembers handler N
##
##     engine sees a click ->   yantra_dispatch(0) -> calls handler 0 in wasm
##
## STRINGS: a Nim string lives in wasm linear memory. We hand the engine a
## (pointer, length) pair and it copies the bytes out immediately. Nothing is
## retained on the wasm side, so there is no ownership puzzle.
##
## 3D: `scene3d` gives you a 3D viewport, and `model`/`camera`/`light` populate
## it. A scene with no camera or light gets sensible ones from the renderer, so
## the smallest working 3D app is two lines.

import std/options
import core/wire except Align, Easing; export NodeKind, Prop, Event

type
  Align* {.size: sizeof(int32).} = enum
    ## Text alignment. This was a DEAD property for a while: `pAlign` existed in
    ## the vocabulary and the renderer never emitted it, so every value an app
    ## set was silently discarded.
    alLeft   = 0
    alCenter = 1
    alRight  = 2

import core/runtime, core/signals, core/persist, core/net, core/ai, core/sysinfo, core/data, core/fmt, ui/widgets, ui/dsl, ui/control, ui/style, ui/theme, ui/icons, ui/motion, ui/units, ui/machine, ui/rich, ui/keys, ui/vlist, ui/sheet, ui/router, ui/blocks, ui/scene3d, ui/input, ui/paint, ui/physics, ui/character
export runtime, signals, persist, net, ai, sysinfo, data, fmt, widgets, dsl, control, style, theme, icons, motion, units, machine, rich, keys, vlist, sheet, router, blocks, scene3d, input, paint, physics, character
## NOTE (sdk-guardian 2026-11-05): core/tokens is INTENTIONALLY not imported/
## exported here. Tokens `px`/`ms`/`s` (plain int wire values) collide with
## ui/units `px`/`ms`/`s` templates (Px/Ms distinct types) and motion/timeline
## `ms`/`s` (Duration) — exporting both makes `16.px` / `200.ms` ambiguous and
## breaks every app. Use `import core/tokens` explicitly in the module that
## needs it. core/data (`fetchSales`, `TimeRange`, …) and core/fmt (`fmt`,
## `fmtFixed`, …) grep zero clashes in sdk/ + apps/, so they are prelude-safe.

proc fontSize*(node: Node, value: int32)
proc x*(node: Node, value: float32)
proc y*(node: Node, value: float32)
proc visible*(node: Node, value: bool)
proc opacity*(node: Node, value: float32)
proc color*(node: Node, r, g, b: int32)
proc source*(node: Node, value: string)
proc scale*(node: Node, value: float32)
proc rotation*(node: Node, rx, ry, rz: float32)
proc position*(node: Node, px, py, pz: float32)
proc metalness*(node: Node, value: float32)
proc roughness*(node: Node, value: float32)
proc spacing*(node: Node, value: int32)
proc padding*(node: Node, all: int32)
proc radius*(node: Node, value: int32)
proc border*(node: Node, width: int32, r, g, b: int32)
proc align*(node: Node, a: Align)

# --- forms & inputs --------------------------------------------------------


proc textArea*(parent: Node, placeholder: string = ""): Node =
  ## Multi-line text input.
  result = make(nkTextArea, parent)
  if placeholder.len > 0: result.set(pPlaceholder, placeholder)

proc checkbox*(parent: Node, label: string = ""): Node =
  ## Checkbox input.
  result = make(nkCheckbox, parent)
  if label.len > 0: result.setText(label)

proc radio*(parent: Node, group: string, label: string = ""): Node =
  ## Radio button. All radios with the same `group` are mutually exclusive.
  result = make(nkRadio, parent)
  result.set(pSource, group)  # reuse pSource for group name
  if label.len > 0: result.setText(label)

proc select*(parent: Node, options: string = "[]"): Node =
  ## Dropdown select. `options` is a JSON array: [{"label": "One", "value": "1"}, ...]
  result = make(nkSelect, parent)
  result.set(pOptions, options)

proc slider*(parent: Node, minVal: float32 = 0, maxVal: float32 = 100): Node =
  ## Range slider.
  result = make(nkSlider, parent)
  result.set(pMin, int32(minVal))
  result.set(pMax, int32(maxVal))

proc progress*(parent: Node, value: float32 = 0, maxVal: float32 = 100): Node =
  ## Progress bar.
  result = make(nkProgress, parent)
  result.set(pValue, value)
  result.set(pMax, int32(maxVal))

proc switch*(parent: Node, label: string = ""): Node =
  ## Toggle switch (iOS-style).
  result = make(nkSwitch, parent)
  if label.len > 0: result.setText(label)

proc datePicker*(parent: Node): Node =
  ## Date picker input.
  make(nkDatePicker, parent)

proc colorPicker*(parent: Node): Node =
  ## Color picker input.
  make(nkColorPicker, parent)

# --- layout ----------------------------------------------------------------

proc grid*(parent: Node, cols: string = "1fr 1fr"): Node =
  ## CSS Grid layout. `cols` is a grid-template-columns string.
  result = make(nkGrid, parent)
  result.set(pGridCols, cols)

proc flex*(parent: Node, direction: string = "row"): Node =
  ## Flexbox layout. `direction`: "row" | "row-reverse" | "column" | "column-reverse"
  result = make(nkFlex, parent)
  result.set(pSource, direction)  # reuse pSource for direction

proc stack*(parent: Node): Node =
  ## Stack layout (overlay children).
  make(nkStack, parent)

proc scrollArea*(parent: Node): Node =
  ## Scrollable container.
  make(nkScrollArea, parent)

proc tabs*(parent: Node): Node =
  ## Tab container. Add tabPanel children.
  make(nkTabs, parent)

proc tabPanel*(parent: Node, label: string): Node =
  ## A single tab panel. Must be child of tabs.
  result = make(nkTabPanel, parent)
  result.setText(label)

# --- data display ----------------------------------------------------------

proc table*(parent: Node): Node =
  ## Data table. Set columns/rows via properties.
  make(nkTable, parent)

proc listView*(parent: Node): Node =
  ## Virtualized list view.
  make(nkListView, parent)

proc treeView*(parent: Node): Node =
  ## Tree view with expandable nodes.
  make(nkTreeView, parent)

proc chart*(parent: Node, chartType: string = "line"): Node =
  ## Chart (line, bar, pie, scatter). Set data via pRows.
  result = make(nkChart, parent)
  result.set(pSource, chartType)

# --- media -----------------------------------------------------------------

proc video*(parent: Node, src: string = ""): Node =
  ## Video player.
  result = make(nkVideo, parent)
  if src.len > 0: result.set(pSrc, src)

proc audio*(parent: Node, src: string = ""): Node =
  ## Audio player.
  result = make(nkAudio, parent)
  if src.len > 0: result.set(pSrc, src)

proc canvas*(parent: Node, w: int32 = 300, h: int32 = 150): Node =
  ## Drawing canvas. Use evCanvasDraw to render.
  result = make(nkCanvas, parent)
  result.width(w)
  result.height(h)
  result.set(pCanvasWidth, w)
  result.set(pCanvasHeight, h)

# --- overlays --------------------------------------------------------------

proc modal*(parent: Node, title: string = ""): Node =
  ## Modal dialog. Use pModalOpen to show/hide.
  result = make(nkModal, parent)
  if title.len > 0: result.set(pModalTitle, title)

proc drawer*(parent: Node, side: string = "right"): Node =
  ## Side drawer. `side`: "left" | "right" | "top" | "bottom"
  result = make(nkDrawer, parent)
  result.set(pSource, side)

proc popover*(parent: Node): Node =
  ## Popover anchored to a trigger element.
  make(nkPopover, parent)

proc tooltip*(parent: Node, content: string): Node =
  ## Tooltip. Shows on hover.
  result = make(nkTooltip, parent)
  result.setText(content)

proc menu*(parent: Node): Node =
  ## Menu bar or dropdown menu.
  make(nkMenu, parent)

proc contextMenu*(parent: Node): Node =
  ## Right-click context menu.
  make(nkContextMenu, parent)

# --- 3D construction -------------------------------------------------------

proc scene3d*(parent: Node, w: int32 = 0, h: int32 = 0): Node =
  ## A 3D viewport. Add model/camera/light nodes to it.
  ## Camera and light are optional: the renderer supplies a sensible
  ## perspective camera and directional light when the scene has none.
  result = make(nkScene3D, parent)
  if w > 0: result.width(w)
  if h > 0: result.height(h)

proc model*(parent: Node, meshy: string = "#Cube"): Node =
  ## A mesh in a scene. `meshy` is either a Qt built-in primitive
  ## ("#Cube", "#Sphere", "#Cylinder", "#Cone", "#Plane") or an asset path.
  ## NOTE the parameter is `meshy`, not `source` — shadowing, as with `image`.
  result = make(nkModel, parent)
  if meshy.len > 0: result.source(meshy)

proc camera*(parent: Node): Node =
  ## An explicit point of view. Without one the renderer adds a default.
  make(nkCamera, parent)

proc light*(parent: Node): Node =
  ## An explicit directional light. Without one the renderer adds a default.
  make(nkLight, parent)

# --- setters ---------------------------------------------------------------

proc x*(node: Node, value: float32) = node.set(pX, value)
proc y*(node: Node, value: float32) = node.set(pY, value)
proc visible*(node: Node, value: bool) = node.set(pVisible, value)
proc opacity*(node: Node, value: float32) = node.set(pOpacity, value)
proc fontSize*(node: Node, value: int32) = node.set(pFontSize, value)

proc color*(node: Node, r, g, b: int32) =
  ## 0xRRGGBB packed, so a colour is one integer across the boundary. For a
  ## Model this is the material's base colour.
  node.set(pColor, (r shl 16) or (g shl 8) or b)

# --- 3D setters ------------------------------------------------------------

proc source*(node: Node, value: string) =
  ## The mesh asset for a Model: "#Cube" or a path.
  node.set(pSource, value)

proc scale*(node: Node, value: float32) =
  ## Uniform scale. One number, not three — non-uniform scaling is rare enough
  ## to not deserve wire ids until something needs it.
  node.set(pScale, value)

proc rotation*(node: Node, rx, ry, rz: float32) =
  ## Euler rotation in degrees. Three separate wire ids rather than a vector
  ## type, so the boundary stays int32/float32 scalars.
  node.set(pRotX, rx)
  node.set(pRotY, ry)
  node.set(pRotZ, rz)

proc position*(node: Node, px, py, pz: float32) =
  ## Position in scene units. A Model's offset in its scene; a Camera's
  ## eye position.
  node.set(pPosX, px)
  node.set(pPosY, py)
  node.set(pPosZ, pz)

proc metalness*(node: Node, value: float32) =
  ## 0 = dielectric, 1 = metal.
  node.set(pMetalness, value)

proc roughness*(node: Node, value: float32) =
  ## 0 = mirror, 1 = fully diffuse.
  node.set(pRoughness, value)

# --- box model setters -----------------------------------------------------

proc spacing*(node: Node, value: int32) =
  ## Gap between the children of a Column or Row. Previously this was hardcoded
  ## to 10 in the renderer, so every gap on a page was identical.
  node.set(pSpacing, value)

proc padding*(node: Node, all: int32) =
  ## Uniform inset, on any side. Sets all four.
  node.set(pPadTop, all)
  node.set(pPadRight, all)
  node.set(pPadBottom, all)
  node.set(pPadLeft, all)

proc padding*(node: Node, top, right, bottom, left: int32) =
  ## Per-side inset. A page needs a different gap on each side: a heading sits
  ## closer to its byline than to the section above it.
  node.set(pPadTop, top)
  node.set(pPadRight, right)
  node.set(pPadBottom, bottom)
  node.set(pPadLeft, left)

proc radius*(node: Node, value: int32) =
  ## Corner radius, in pixels.
  node.set(pRadius, value)

proc border*(node: Node, width: int32, r, g, b: int32) =
  ## Border width plus its colour, in one call so a border is never half-set.
  node.set(pBorderWidth, width)
  node.set(pBorderColor, (r shl 16) or (g shl 8) or b)

proc align*(node: Node, a: Align) =
  ## Text alignment. Was a dead property until the renderer started emitting it.
  node.set(pAlign, int32(a))

# --- forms & inputs setters ------------------------------------------------

proc value*(node: Node, v: string) = node.set(pValue, v)
proc value*(node: Node, v: float32) = node.set(pValue, v)
proc value*(node: Node, v: int32) = node.set(pValue, v)
proc value*(node: Node, v: bool) = node.set(pValue, v)

proc placeholder*(node: Node, v: string) = node.set(pPlaceholder, v)
proc min*(node: Node, v: float32) = node.set(pMin, v)
proc max*(node: Node, v: float32) = node.set(pMax, v)
proc step*(node: Node, v: float32) = node.set(pStep, v)
proc checked*(node: Node, v: bool) = node.set(pChecked, int32(if v: 1 else: 0))
proc options*(node: Node, v: string) = node.set(pOptions, v)
proc multiple*(node: Node, v: bool) = node.set(pMultiple, int32(if v: 1 else: 0))
proc disabled*(node: Node, v: bool) = node.set(pDisabled, int32(if v: 1 else: 0))
proc required*(node: Node, v: bool) = node.set(pRequired, int32(if v: 1 else: 0))
proc readOnly*(node: Node, v: bool) = node.set(pReadOnly, int32(if v: 1 else: 0))
proc maxLength*(node: Node, v: int32) = node.set(pMaxLength, v)
proc pattern*(node: Node, v: string) = node.set(pPattern, v)

# --- layout setters --------------------------------------------------------

proc flexGrow*(node: Node, v: float32) = node.set(pFlexGrow, v)
proc flexShrink*(node: Node, v: float32) = node.set(pFlexShrink, v)
proc flexBasis*(node: Node, v: float32) = node.set(pFlexBasis, v)
proc gridCols*(node: Node, v: string) = node.set(pGridCols, v)
proc gridRows*(node: Node, v: string) = node.set(pGridRows, v)
proc gridGap*(node: Node, v: int32) = node.set(pGridGap, v)
proc zIndex*(node: Node, v: int32) = node.set(pZIndex, v)
proc overflow*(node: Node, v: string) = node.set(pOverflow, v)
proc scrollX*(node: Node, v: int32) = node.set(pScrollX, v)
proc scrollY*(node: Node, v: int32) = node.set(pScrollY, v)

# --- tabs setters ----------------------------------------------------------

proc tabIndex*(node: Node, v: int32) = node.set(pTabIndex, v)

# --- table/list setters ----------------------------------------------------

proc columns*(node: Node, v: string) = node.set(pColumns, v)
proc rows*(node: Node, v: string) = node.set(pRows, v)
proc selection*(node: Node, v: string) = node.set(pSelection, v)
proc sortable*(node: Node, v: bool) = node.set(pSortable, int32(if v: 1 else: 0))
proc filterable*(node: Node, v: bool) = node.set(pFilterable, int32(if v: 1 else: 0))

# --- media setters ---------------------------------------------------------

proc src*(node: Node, v: string) = node.set(pSrc, v)
proc poster*(node: Node, v: string) = node.set(pPoster, v)
proc autoplay*(node: Node, v: bool) = node.set(pAutoplay, int32(if v: 1 else: 0))
proc loop*(node: Node, v: bool) = node.set(pLoop, int32(if v: 1 else: 0))
proc muted*(node: Node, v: bool) = node.set(pMuted, int32(if v: 1 else: 0))
proc volume*(node: Node, v: float32) = node.set(pVolume, v)
proc playbackRate*(node: Node, v: float32) = node.set(pPlaybackRate, v)

# --- canvas setters --------------------------------------------------------

proc canvasSize*(node: Node, w, h: int32) =
  node.width(w)
  node.height(h)
  node.set(pCanvasWidth, w)
  node.set(pCanvasHeight, h)

# --- overlay setters -------------------------------------------------------

proc open*(node: Node, v: bool) = node.set(pModalOpen, int32(if v: 1 else: 0))
proc title*(node: Node, v: string) = node.set(pModalTitle, v)
proc closeOnEsc*(node: Node, v: bool) = node.set(pCloseOnEsc, int32(if v: 1 else: 0))
proc closeOnClickOutside*(node: Node, v: bool) = node.set(pCloseOnClickOutside, int32(if v: 1 else: 0))

# --- event handlers --------------------------------------------------------

proc on*(node: Node, event: Event, handler: proc()) =
  node.addHandler(event, handler)

proc onInput*(node: Node, handler: proc()) = node.on(evInput, handler)

proc trackScroll*(node: Node; y: Signal[float32]) =
  ## Keeps `y` at the node's scroll offset (px): the engine sends Scroll when it changes.
  node.on(evScroll, proc () = batch(proc () = y.set(yNodeSize(int32(node.id), 2))))

proc lazyFirst*(y, rowH: float32; overscan = 4): int =
  ## The first row a lazy list builds when scrolled to `y` (a few above what shows).
  max(0, int(y / max(rowH, 1)) - overscan)

proc lazyLast*(y, h, rowH: float32; n: int; overscan = 4): int =
  ## One past the last row it builds: what shows in `h`, and a few below; never past `n`.
  min(n, int((y + h) / max(rowH, 1)) + 1 + overscan)

proc trackSize*(node: Node; w, h: Signal[float32]) =
  ## Keeps `w` and `h` at the node's laid-out size (px): the engine sends Resize when it
  ## changes, before painting. `sized w, h:` in the DSL uses it [S-LAY-2].
  node.on(evResize, proc () = batch(proc () =
    w.set(yNodeSize(int32(node.id), 0))
    h.set(yNodeSize(int32(node.id), 1))))
proc onFocus*(node: Node, handler: proc()) = node.on(evFocus, handler)
proc onBlur*(node: Node, handler: proc()) = node.on(evBlur, handler)
proc onScroll*(node: Node, handler: proc()) = node.on(evScroll, handler)
proc onTabChange*(node: Node, handler: proc()) = node.on(evTabChange, handler)
proc onSelectionChange*(node: Node, handler: proc()) = node.on(evSelectionChange, handler)
proc onMediaEnd*(node: Node, handler: proc()) = node.on(evMediaEnd, handler)
proc onMediaError*(node: Node, handler: proc()) = node.on(evMediaError, handler)
proc onCanvasDraw*(node: Node, handler: proc()) = node.on(evCanvasDraw, handler)
proc onMediaReady*(node: Node, handler: proc()) = node.on(evMediaReady, handler)
proc onTimeUpdate*(node: Node, handler: proc()) = node.on(evTimeUpdate, handler)

proc mediaTime*(node: Node): float32 = yNodeSize(int32(node.id), 3)
  ## A video's or audio's position in seconds (as of the last TimeUpdate).
proc mediaDuration*(node: Node): float32 = yNodeSize(int32(node.id), 4)
  ## Its length in seconds (0 until MediaReady; 0 if the file doesn't say).
proc trackMedia*(node: Node; time, duration: Signal[float32]) =
  ## Keeps `time` and `duration` at the node's playing position and length (P3).
  let update = proc () = batch(proc () =
    time.set(yNodeSize(int32(node.id), 3))
    duration.set(yNodeSize(int32(node.id), 4)))
  node.on(evTimeUpdate, update)
  node.on(evMediaReady, update)
proc waveform*(node: Node): seq[float32] =
  ## An audio node's peaks (0..1), as many as its `waveform` prop asked for, once MediaReady
  ## has come: a voice note's bars.
  let n = int(yNodeSize(int32(node.id), 5))
  for i in 0 ..< n: result.add yNodeSize(int32(node.id), int32(1000 + i))

# --- animations ------------------------------------------------------------

proc animate*(node: Node; target: string; to: float32; duration: int32 = 300;
              easing: Easing = easeOutCubic; startVal: Option[float32] = none(float32);
              delay: int32 = 0; loop: int32 = 1; yoyo: bool = false;
              trigger: string = "mount") =
  ## Declarative animation. The engine translates this to a Qt Quick animation.
  ##
  ## target: property to animate ("opacity", "x", "y", "width", "height", "scale", "rotation")
  ## to: end value
  ## duration: milliseconds
  ## easing: easing curve
  ## startVal: start value (optional, defaults to current)
  ## delay: delay before start (ms)
  ## loop: number of loops (0 = infinite)
  ## yoyo: reverse on each loop
  ## trigger: "mount" | "click" | "hover" | "focus" | "prop:<name>"
  node.set(pAnimTarget, target)
  node.set(pAnimTo, to)
  node.set(pAnimDuration, duration)
  node.set(pAnimEasing, int32(easing))
  node.set(pAnimDelay, delay)
  node.set(pAnimLoop, loop)
  node.set(pAnimYoyo, int32(if yoyo: 1 else: 0))
  node.set(pAnimTrigger, trigger)
  if startVal.isSome: node.set(pAnimFrom, startVal.get)

proc transition*(node: Node; kind: string; duration: int32 = 300; easing: Easing = easeOutCubic) =
  ## Transition animation for enter/exit/move/resize/opacity.
  ## kind: "enter" | "exit" | "move" | "resize" | "opacity"
  node.set(pTransition, kind)
  node.set(pTransDuration, duration)
  node.set(pTransEasing, int32(easing))

