## Yantra Declarative UI DSL: the `app` macro, `{.component.}`, named props, events,
## reactive interpolation (L3/L4), reactive `if` and keyed `for` (L7), bound inputs.
##
## Everything here is a compile-time rewrite into plain calls on the SDK: node
## constructors, setters, `createEffect`, and the two control-flow procs in
## ui/control.nim. A prop, a text or a condition whose value is not a literal is
## wrapped in an effect, so it updates itself when the signals it reads change
## [S-PROP-3]. Event handlers run as one batch [S-RX-2].
import std/[macros, strutils]
import ../../protocol/schema

proc parseInterpolatedExpr*(s: string; info: NimNode): (NimNode, bool) =
  ## "Clicked {n} times" -> `"Clicked " & $(n) & " times"`, and whether it had any `{…}`.
  if not s.contains('{') or not s.contains('}'):
    return (newLit(s), false)
  var parts: seq[NimNode] = @[]
  var i = 0
  var cur = ""
  var hasInterp = false
  while i < s.len:
    if s[i] == '{':
      var closeIdx = s.find('}', i + 1)
      if closeIdx > i + 1:
        if cur.len > 0:
          parts.add(newLit(cur))
          cur = ""
        let exprStr = s[i + 1 .. closeIdx - 1].strip()
        let parsed = parseExpr(exprStr)
        parts.add(newCall(ident"$", parsed))
        hasInterp = true
        i = closeIdx + 1
        continue
    cur.add(s[i])
    inc i
  if cur.len > 0:
    parts.add(newLit(cur))
  if not hasInterp or parts.len == 0:
    return (newLit(s), false)
  var combined = parts[0]
  for idx in 1 ..< parts.len:
    combined = infix(combined, "&", parts[idx])
  result = (combined, true)

proc interpolateStr*(templateStr: string; vars: openArray[(string, string)]): string =
  ## Replaces all `{name}` occurrences in `templateStr` using `vars`.
  result = templateStr
  for (k, v) in vars:
    result = result.replace("{" & k & "}", v)

# --- helpers --------------------------------------------------------------------

proc isLiteral(n: NimNode): bool =
  case n.kind
  of nnkCharLit .. nnkFloat128Lit, nnkStrLit .. nnkTripleStrLit: true
  of nnkIdent, nnkSym: ($n) in ["true", "false", "nil"] or ($n).startsWith("al") and ($n).len > 2 and ($n)[2].isUpperAscii
  of nnkPrefix: n.len == 2 and isLiteral(n[1])
  else: false

proc lambda(body: NimNode; params: varargs[NimNode]): NimNode =
  var ps = @[newEmptyNode()]
  for p in params: ps.add(p)
  newProc(params = ps, body = body, procType = nnkLambda)

proc effect(stmt: NimNode): NimNode =
  newTree(nnkDiscardStmt, newCall(ident"createEffect", lambda(newStmtList(stmt))))

proc reactiveOrOnce(stmt: NimNode; value: NimNode): NimNode =
  if isLiteral(value): stmt else: effect(stmt)

const eventNames = [("onclick", "evClick"), ("onchange", "evChange"), ("oninput", "evInput"),
                    ("onsubmit", "evSubmit"), ("onfocus", "evFocus"), ("onblur", "evBlur"),
                    ("ondismiss", "evDismiss"), ("oncontextmenu", "evContextMenu"), ("onkey", "evKey"),
                    ("ondragstart", "evDragStart"), ("ondragover", "evDragOver"), ("ondrop", "evDrop"),
                    ("onframe", "evFrame"), ("onpointerdown", "evPointerDown"),
                    ("onpointermove", "evPointerMove"), ("onpointerup", "evPointerUp")]


proc eventOf(name: string): string =
  for (k, v) in eventNames:
    if k == name.toLowerAscii(): return v
  ""

proc headName(n: NimNode): string =
  if n.kind in {nnkCall, nnkCommand} and n.len > 0 and n[0].kind in {nnkIdent, nnkSym}: $n[0] else: ""

# --- props ------------------------------------------------------------------------

# Units (sdk/ui/units.nim): each of these props checks the unit a value carries.
const lengthProps = ["width", "height", "minwidth", "maxwidth", "minheight", "maxheight", "pad", "padding",
                     "padx", "pady", "padtop", "padright", "padbottom", "padleft", "margin", "marginx",
                     "marginy", "margintop", "marginright", "marginbottom", "marginleft", "gap", "spacing",
                     "radius", "border", "top", "left", "right", "bottom", "x", "y", "size", "fontsize",
                     "blur", "backdropblur"]
const durationProps = ["transition"]
const angleProps = ["rotate"]
# Theme words (docs/spec/style.md §4): in a colour prop, a bare `surface` means `theme().surface`.
const themeColors = ["bg", "sidebar", "surface", "surface2", "surface3", "line", "text", "muted", "faint",
                     "accent", "accentText", "accentSoft", "danger", "success"]
const colorProps = ["fill", "color", "textcolor", "bordercolor", "shadow"]

proc themeWords*(n: NimNode): NimNode =
  ## Rewrites bare theme colour names anywhere in a value — inside `if`, `rgba(…)`,
  ## `linear(…)`, `shadow(color = …)` — to reads of the current theme, so they re-style
  ## on a theme switch. Callee names, field names (`x.accent`) and argument names stay.
  case n.kind
  of nnkIdent:
    for w in themeColors:
      if eqIdent(n, w): return newDotExpr(newCall(ident"theme"), ident(w))
    n
  of nnkDotExpr:
    newTree(nnkDotExpr, themeWords(n[0]), n[1])
  of nnkCall, nnkCommand, nnkCallStrLit:
    var r = newTree(n.kind, n[0])
    for i in 1 ..< n.len: r.add themeWords(n[i])
    r
  of nnkExprEqExpr, nnkExprColonExpr:
    newTree(n.kind, n[0], themeWords(n[1]))
  of nnkLiterals, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice:
    n
  else:
    var r = copyNimNode(n)
    for c in n: r.add themeWords(c)
    r

proc withUnits(norm: string; v: NimNode): NimNode =
  if norm in lengthProps: newCall(ident"lengthOf", v)
  elif norm in durationProps: newCall(ident"durationOf", v)
  elif norm in angleProps: newCall(ident"angleOf", v)
  else: v

proc setCall(nodeSym: NimNode; prop: string; v: NimNode): NimNode =
  newCall(newDotExpr(nodeSym, ident"set"), ident(prop), v)

proc wireValue(propType: string; v: NimNode): NimNode =
  ## A prop value converted to its wire type.
  case propType
  of "int32": newCall(ident"wireI32", newCall(ident"int", v))
  of "float32": newCall(ident"float32", v)
  of "bool": newCall(ident"bool", v)
  else: newCall(ident"$", v)

proc buildPropSetter(nodeSym: NimNode; nodeKindName: string; arg: NimNode;
                     reactive = true; checkKind = true): NimNode =
  ## One `name = value` prop at a call site (or in a `style(...)` preset, where it
  ## is applied once, not wrapped in an effect, and is not tied to a node kind).
  let propName = $arg[0]
  var propVal = arg[1]
  let norm = propName.toLowerAscii()
  # words that only mean something in one prop: `justify = between`, `cursor = hand`
  if propVal.kind == nnkIdent:
    let w = ($propVal).toLowerAscii()
    let words = case norm
      of "alignitems": @[("first", 0), ("start", 0), ("center", 1), ("last", 2), ("stretch", 3)]
      of "justify": @[("first", 0), ("start", 0), ("center", 1), ("last", 2), ("between", 3), ("around", 4), ("evenly", 5)]
      of "cursor": @[("arrow", 0), ("hand", 1), ("ibeam", 2), ("text", 2)]
      of "align": @[("left", 0), ("center", 1), ("right", 2)]
      of "fit": @[("contain", 0), ("cover", 1), ("fill", 2)]
      of "blend": @[("normal", 3), ("plus", 12), ("screen", 14), ("overlay", 15), ("darken", 16), ("lighten", 17),
                    ("colordodge", 18), ("colorburn", 19), ("hardlight", 20), ("softlight", 21), ("difference", 22),
                    ("exclusion", 23), ("multiply", 24), ("hue", 25), ("saturation", 26), ("color", 27),
                    ("luminosity", 28)]
      else: @[]
    for (word, v) in words:
      if w == word: propVal = newLit(v)
    if norm == "ease":                   # `ease = outBack`: a curve from protocol/schema.nim `Easings`
      for i, e in Easings:
        if w == e.toLowerAscii or w == "ease" & e.toLowerAscii: propVal = newLit(i)
    if norm == "font" and w in ["mono", "font"]: propVal = newDotExpr(newCall(ident"theme"), ident(w))
  if norm == "fit" and propVal.kind in {nnkStrLit, nnkTripleStrLit}:
    let w = propVal.strVal.toLowerAscii
    propVal = newLit(if w == "cover": 1 elif w == "fill": 2 else: 0)
  if norm in colorProps: propVal = themeWords(propVal)
  if not isLiteral(propVal):                # a plain number needs no unit check
    propVal = withUnits(norm, propVal)
  var s: NimNode
  case norm
  of "padx":
    s = newStmtList(setCall(nodeSym, "pPadLeft", wireValue("int32", propVal)),
                    setCall(nodeSym, "pPadRight", wireValue("int32", propVal)))
  of "pady":
    s = newStmtList(setCall(nodeSym, "pPadTop", wireValue("int32", propVal)),
                    setCall(nodeSym, "pPadBottom", wireValue("int32", propVal)))
  of "margin", "marginx", "marginy":
    s = newStmtList()
    let sides = if norm == "marginx": @["Left", "Right"] elif norm == "marginy": @["Top", "Bottom"]
                else: @["Top", "Right", "Bottom", "Left"]
    for side in sides: s.add setCall(nodeSym, "pMargin" & side, wireValue("float32", propVal))
  of "fill":
    s = newCall(ident"setFill", nodeSym, propVal)            # a colour or a gradient
  of "shadow":
    s = newCall(ident"setShadow", nodeSym, propVal)
  of "use":
    s = newCall(ident"applyStyle", nodeSym, propVal)         # a style preset
  of "enter":
    s = newCall(ident"setEnter", nodeSym, propVal)           # played when the node appears
  of "exit":
    s = newCall(ident"setExit", nodeSym, propVal)            # played after the app removes it
  of "reveal":
    s = newCall(ident"setReveal", nodeSym, propVal)          # follows scrolling into view
  of "animate":
    s = newCall(ident"setLoop", nodeSym, propVal)            # a looping animation
  else:
    if findPropMeta(propName) < 0 or (checkKind and not isPropAllowedOnNode(propName, nodeKindName)):
      let sug = suggestPropName(propName, if checkKind: nodeKindName else: "*")
      let hint = if sug.len > 0: " — did you mean '" & sug & "'?" else: ""
      error("Y001 unknown prop '" & propName & "' on " & nodeKindName.toLowerAscii() & hint, arg)
    case norm
    of "gap", "spacing":
      s = newCall(newDotExpr(nodeSym, ident"spacing"), newCall(ident"int32", propVal))
    of "pad", "padding":
      s = newCall(newDotExpr(nodeSym, ident"padding"), newCall(ident"int32", propVal))
    of "size", "fontsize":
      s = newCall(newDotExpr(nodeSym, ident"fontSize"), newCall(ident"int32", propVal))
    of "width":
      s = newCall(newDotExpr(nodeSym, ident"width"), newCall(ident"int32", propVal))
    of "height":
      s = newCall(newDotExpr(nodeSym, ident"height"), newCall(ident"int32", propVal))
    else:
      let meta = PropTable[findPropMeta(propName)]
      s = setCall(nodeSym, "p" & meta.wireProp, wireValue(meta.propType, propVal))
  if reactive: reactiveOrOnce(s, propVal) else: s

const stateBlocks = [("hover", "Hover"), ("pressed", "Press"), ("focused", "Focus")]

proc stateBlock(nodeSym: NimNode; prefix: string; blk: NimNode): NimNode =
  ## `hover:` / `pressed:` / `focused:` — props that apply while the state holds
  ## [S-STY-2]. The engine switches them; the app does no work.
  result = newStmtList()
  for st in blk:
    if st.kind != nnkAsgn:
      error("a state block holds assignments like `fill = …`", st)
    let name = ($st[0]).toLowerAscii()
    let (suffix, typ) = case name
      of "fill": ("Fill", "int32")
      of "color": ("Color", "int32")
      of "bordercolor": ("Border", "int32")
      of "opacity": ("Opacity", "float32")
      of "scale": ("Scale", "float32")
      of "y": ("Y", "float32")
      else: ("", "")
    if suffix.len == 0:
      error("Y013 '" & name & "' can't change with state — use fill, color, borderColor, opacity, scale or y", st)
    var v = st[1]
    if name in ["fill", "color", "bordercolor"]: v = themeWords(v)
    elif name == "y": v = newCall(ident"lengthOf", v)
    result.add reactiveOrOnce(setCall(nodeSym, "p" & prefix & suffix, wireValue(typ, v)), v)

# --- statements ---------------------------------------------------------------------

proc transformUiStmt(stmt: NimNode; parentSym: NimNode; assignTo: NimNode = nil): NimNode
proc transformUiBlock*(blk: NimNode; parentSym: NimNode): NimNode

proc eventHandler(nodeSym: NimNode; ev: string; body: NimNode): NimNode =
  ## node.on(evX, proc() = batch(proc() = body))
  let batched = newCall(ident"batch", lambda(body))
  newCall(newDotExpr(nodeSym, ident"on"), ident(ev), lambda(newStmtList(batched)))

proc childBlock(nodeSym: NimNode; blk: NimNode): NimNode =
  ## Children of a node: events attach to the node itself, the rest are UI statements.
  transformUiBlock(blk, nodeSym)

proc textLike(ctor: string; nodeSym, parentSym, mainArg: NimNode): NimNode =
  ## A text/button: literal text is set once, interpolated or computed text updates itself.
  result = newStmtList()
  if mainArg.kind in {nnkStrLit, nnkTripleStrLit}:
    let (exprAst, isReactive) = parseInterpolatedExpr(mainArg.strVal, mainArg)
    if isReactive:
      result.add(newLetStmt(nodeSym, newCall(ident(ctor), parentSym, newLit(""))))
      result.add(effect(newCall(newDotExpr(nodeSym, ident"setText"), exprAst)))
    else:
      result.add(newLetStmt(nodeSym, newCall(ident(ctor), parentSym, mainArg)))
  else:
    result.add(newLetStmt(nodeSym, newCall(ident(ctor), parentSym, newLit(""))))
    result.add(effect(newCall(newDotExpr(nodeSym, ident"setText"), newCall(ident"$", mainArg))))

proc takeHandle(stmt: NimNode): string =
  ## `text @headline "Hi"` / `panel(@card, …)`: pulls out the `@name` handle (roadmap S3)
  ## and leaves the statement as it would be without it.
  if stmt.len < 2: return ""
  let a = stmt[1]
  if a.kind == nnkCall and a[0].kind == nnkPrefix and $a[0][0] == "@":
    # `panel @card(fill = …)` parses as a call of `@card`: the handle, then its arguments
    result = $a[0][1]
    stmt.del(1)
    for i in countdown(a.len - 1, 1): stmt.insert(1, a[i])
  elif a.kind == nnkPrefix and $a[0] == "@":
    result = $a[1]
    stmt.del(1)
  elif a.kind == nnkCommand and a.len == 2 and a[0].kind == nnkPrefix and $a[0][0] == "@":
    result = $a[0][1]
    stmt[1] = a[1]

proc nodeStmt(stmt: NimNode; parentSym: NimNode; assignTo: NimNode): NimNode =
  ## A node constructor: column/row/panel/group, text, button, input, checkbox, spacer.
  let handle = takeHandle(stmt)
  let name = ($stmt[0]).toLowerAscii()
  let nodeSym = genSym(nskLet, name & "Node")
  result = newStmtList()
  var firstArg = 1
  var kindCap = ""
  case name
  of "column", "row", "panel", "group":
    kindCap = if name == "column": "Column" elif name == "row": "Row" elif name == "panel": "Panel" else: "Group"
    result.add(newLetStmt(nodeSym, newCall(ident(name), parentSym)))
  of "text", "button":
    kindCap = if name == "text": "Text" else: "Button"
    if stmt.len < 2: error(name & " needs its text as the first argument", stmt)
    result.add(textLike(name, nodeSym, parentSym, stmt[1]))
    firstArg = 2
  of "modal", "drawer", "popover", "menu", "contextmenu":
    # overlays (OV1): a layer above the window, not in the page's layout. A modal is centred
    # over a dimmed window, a drawer docks to an edge, a popover or menu opens by the node it
    # is inside, a context menu at a right click on that node. `open = sig` shows it (absent:
    # open while it exists); Escape or a click outside fires `onDismiss` (or just closes it)
    kindCap = case name
              of "modal": "Modal"
              of "drawer": "Drawer"
              of "popover": "Popover"
              of "menu": "Menu"
              else: "ContextMenu"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident("nk" & kindCap), parentSym)))
  of "tooltip":
    # `tooltip "Copy link"` inside a node: shown after the pointer rests on that node
    kindCap = "Tooltip"
    if stmt.len < 2: error("tooltip needs its text as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkTooltip", parentSym)))
    result.add(reactiveOrOnce(setCall(nodeSym, "pText", newCall(ident"$", stmt[1])), stmt[1]))
    firstArg = 2
  of "model":
    # `model "fox.glb", width = 400.px, height = 300.px` — a glTF 2.0 model from the app's
    # folder, lit and framed, its first animation playing (Filament)
    kindCap = "Model"
    if stmt.len < 2: error("model needs its file name as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkModel", parentSym)))
    result.add(reactiveOrOnce(setCall(nodeSym, "pSource", newCall(ident"$", stmt[1])), stmt[1]))
    firstArg = 2
  of "scene3d", "camera", "light", "mesh", "box", "sphere", "plane", "cylinder":
    # native 3D (S3D): `scene3d(sky = 0x87CEEB, fog = 0.02):` is a view into a 3D world; inside
    # it `box`/`sphere`/`plane`/`cylinder`/`mesh(geometry = buf)` are objects (posX.., rotY..,
    # sizeX.., fill, metal, rough, glow, instances = buf), `light` and `camera` light and see
    # it, and `model "fox.glb"` is an object too. Filament draws it; the objects are not laid out.
    kindCap = case name
              of "scene3d": "Scene3D"
              of "camera": "Camera"
              of "light": "Light"
              else: "Mesh"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident("nk" & kindCap), parentSym)))
    let shapeOf = ["box", "sphere", "plane", "cylinder"].find(name)
    if shapeOf > 0: result.add(setCall(nodeSym, "pShape", wireValue("int32", newLit(shapeOf))))
  of "canvas":
    # `canvas(draw = d.cmds, width = 400.px, height = 300.px)`: 2D drawing (paint.nim's Draw:
    # paths, shapes, text, images, layers, raw pixels, blend modes); pointer events on it
    kindCap = "Canvas"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkCanvas", parentSym)))
  of "particles":
    # `particles(posY = 2, rate = 200, lifetime = 1.5, speed = 4, spread = 30, fill = 0xFFFFB000,
    # colorEnd = 0x00FF2000, gravity = 9.8)`: sprites the engine emits and moves (PT1)
    kindCap = "Particles"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkParticles", parentSym)))
  of "synth":
    # `synth(freq = pitch, wave = 3, filter = 1, cutoff = 800, playing = held)`: a sound the
    # engine makes (AU1) — wave or noise, filtered, enveloped, echoed, panned; not laid out
    kindCap = "Synth"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkSynth", parentSym)))
  of "rich":
    # `rich "Some **bold** and [a link](https://x.com)"`: one Text node, runs styled (R2)
    kindCap = "Text"
    if stmt.len < 2: error("rich needs its markup as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkText", parentSym)))
    result.add(reactiveOrOnce(newCall(ident"setRich", nodeSym, stmt[1]), stmt[1]))
    firstArg = 2
  of "input", "textarea":
    # `input draft` / `textArea notes`: one line or many, bound to a Signal[string]
    kindCap = if name == "input": "Input" else: "TextArea"
    result.add(newLetStmt(nodeSym, if name == "input": newCall(ident"input", parentSym)
                                   else: newCall(ident"make", ident"nkTextArea", parentSym)))
    if stmt.len >= 2 and stmt[1].kind notin {nnkExprEqExpr, nnkStmtList}:
      # `input draft`: two-way binding to a Signal[string] [S-CMP-3]
      let sig = stmt[1]
      result.add(effect(newCall(newDotExpr(nodeSym, ident"set"), ident"pValue",
                                newCall(ident"get", sig))))
      result.add(newCall(newDotExpr(nodeSym, ident"on"), ident"evInput",
        lambda(newStmtList(newCall(ident"set", sig,
          newCall(newDotExpr(nodeSym, ident"getStr"), ident"pValue"))))))
      firstArg = 2
  of "checkbox":
    kindCap = "Checkbox"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkCheckbox", parentSym)))
  of "stack":
    # children overlap; each is placed by its own top/left/right/bottom
    kindCap = "Stack"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkStack", parentSym)))
  of "path":
    kindCap = "Path"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkPath", parentSym)))
  of "icon":
    # `icon "search", size = 18, color = …` — a path from the standard icon set
    kindCap = "Path"
    if stmt.len < 2: error("icon needs its name as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkPath", parentSym)))
    result.add(setCall(nodeSym, "pStrokeWidth", newCall(ident"float32", newLit(1.8))))
    result.add(reactiveOrOnce(setCall(nodeSym, "pPathData", newCall(ident"iconPath", stmt[1])), stmt[1]))
    firstArg = 2
  of "video":
    # `video "clip.mp4", fit = cover, loop = true` — a file from the app's own folder
    kindCap = "Video"
    if stmt.len < 2: error("video needs its file name as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkVideo", parentSym)))
    result.add(reactiveOrOnce(setCall(nodeSym, "pSource", newCall(ident"$", stmt[1])), stmt[1]))
    firstArg = 2
  of "page", "slide":
    # a page of a document, or a 1280x720 slide of a deck: one PDF page each (D1)
    kindCap = "Page"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkPage", parentSym)))
    if name == "slide":
      result.add(newCall(newDotExpr(nodeSym, ident"width"), newLit(1280'i32)))
      result.add(newCall(newDotExpr(nodeSym, ident"height"), newLit(720'i32)))
  of "grid":
    # `grid "1fr 2fr 200", spacing = 12:` — columns of fixed px, shares (fr) or `auto`;
    # children fill them in order, row after row (`span = 2` takes two columns)
    kindCap = "Grid"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkGrid", parentSym)))
    if stmt.len >= 2 and stmt[1].kind notin {nnkExprEqExpr, nnkStmtList}:
      result.add(reactiveOrOnce(setCall(nodeSym, "pGridCols", newCall(ident"$", stmt[1])), stmt[1]))
      firstArg = 2
  of "appview":
    # another app, sandboxed, drawn in this box: `appView(source = "todo", grow = 1)`
    kindCap = "AppView"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkAppView", parentSym)))
  of "spacer":
    kindCap = "Spacer"
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkSpacer", parentSym)))
    result.add(newCall(newDotExpr(nodeSym, ident"set"), ident"pFlexGrow", newCall(ident"float32", newLit(1))))
  of "image":
    kindCap = "Image"
    if stmt.len < 2: error("image needs its source path as the first argument", stmt)
    result.add(newLetStmt(nodeSym, newCall(ident"make", ident"nkImage", parentSym)))
    result.add(reactiveOrOnce(setCall(nodeSym, "pSource", newCall(ident"$", stmt[1])), stmt[1]))
    firstArg = 2
  else:
    error("unknown node kind " & name, stmt)
  if assignTo != nil:
    result.add(newAssignment(assignTo, nodeSym))
  if handle.len > 0:                    # a stable name for code, tests, tools and AI edits
    result.add newCall(newDotExpr(nodeSym, ident"set"), ident"pName", newLit(handle))
  # where in the source this node comes from (dev builds only): hot reload keeps focus,
  # scroll and running child apps by it, and inspectors jump from a pixel to its code
  let li = stmt.lineInfoObj
  let site = li.filename.replace('\\', '/').rsplit('/', 1)[^1] & ":" & $li.line & ":" & $li.column
  result.add newTree(nnkWhenStmt, newTree(nnkElifBranch, prefix(newCall(ident"defined", ident"release"), "not"),
    newStmtList(newCall(newDotExpr(nodeSym, ident"set"), ident"pSite", newLit(site)))))
  for i in firstArg ..< stmt.len:
    let arg = stmt[i]
    if arg.kind == nnkExprEqExpr:
      result.add(buildPropSetter(nodeSym, kindCap, arg))
    elif arg.kind == nnkStmtList:
      result.add(childBlock(nodeSym, arg))
    else:
      error("unexpected positional argument to " & name & " (Y010 positional after main)", arg)

const nodeKinds = ["column", "row", "panel", "group", "text", "button", "input", "textarea", "checkbox", "spacer", "appview",
                   "stack", "path", "icon", "video", "page", "slide", "image", "grid", "rich", "model",
                   "modal", "drawer", "popover", "menu", "contextmenu", "tooltip",
                   "scene3d", "camera", "light", "mesh", "box", "sphere", "plane", "cylinder", "synth", "canvas", "particles"]

proc forStmt(stmt: NimNode; parentSym: NimNode; emptyBlk: NimNode): NimNode =
  ## `for x in xs.keyed(key): body` / `for x in xs: body` [S-CTL-2] -> keyedList(...)
  if stmt.len != 3 or stmt[0].kind != nnkIdent:
    error("for in a UI block takes one loop variable: `for x in items.keyed(x.id):`", stmt)
  let loopVar = stmt[0]
  var src = stmt[1]
  var keyExpr = newCall(ident"$", loopVar)          # default key: the item itself
  if src.kind == nnkCall and src[0].kind == nnkDotExpr and $src[0][1] == "keyed" and src.len == 2:
    keyExpr = newCall(ident"$", src[1])
    src = src[0][0]
  let listVal = newCall(ident"listValue", src)
  let itemT = newCall(ident"typeof", newTree(nnkBracketExpr, listVal, newLit(0)))
  let listT = newCall(ident"typeof", listVal)
  let parentParam = ident"yParent"
  let itemsProc = newProc(params = [listT], body = newStmtList(listVal), procType = nnkLambda)
  let keyProc = newProc(params = [ident"string", newIdentDefs(loopVar, itemT)],
                        body = newStmtList(keyExpr), procType = nnkLambda)
  let buildProc = newProc(params = [newEmptyNode(), newIdentDefs(parentParam, ident"Node"), newIdentDefs(loopVar, itemT)],
                          body = transformUiBlock(stmt[2], parentParam), procType = nnkLambda)
  var call = newCall(ident"keyedList", parentSym, itemsProc, keyProc, buildProc)
  if emptyBlk != nil:
    call.add(newProc(params = [newEmptyNode(), newIdentDefs(parentParam, ident"Node")],
                     body = transformUiBlock(emptyBlk, parentParam), procType = nnkLambda))
  newStmtList(call)

proc ifStmt(stmt: NimNode; parentSym: NimNode): NimNode =
  ## if/elif/else -> showWhen(parent, branchIndex, builds) [S-CTL-1]
  let parentParam = ident"yParent"
  var chooser = newTree(nnkIfExpr)
  var builds = newTree(nnkBracket)
  var hasElse = false
  for i, br in stmt:
    let buildProc = newProc(params = [newEmptyNode(), newIdentDefs(parentParam, ident"Node")],
                            body = transformUiBlock(br[^1], parentParam), procType = nnkLambda)
    buildProc.addPragma(ident"closure")   # one element type for the whole seq
    builds.add(buildProc)
    if br.kind == nnkElifBranch:
      chooser.add(newTree(nnkElifExpr, br[0], newLit(i)))
    else:
      chooser.add(newTree(nnkElseExpr, newLit(i)))
      hasElse = true
  if not hasElse: chooser.add(newTree(nnkElseExpr, newLit(-1)))
  let branchProc = newProc(params = [ident"int"], body = newStmtList(chooser), procType = nnkLambda)
  newStmtList(newCall(ident"showWhen", parentSym, branchProc, prefix(builds, "@")))

proc caseStmt(stmt: NimNode; parentSym: NimNode): NimNode =
  ## case -> showWhen(parent, branchIndex, builds) [S-CTL-1]
  let parentParam = ident"yParent"
  var chooser = newTree(nnkCaseStmt, stmt[0])
  var builds = newTree(nnkBracket)
  var hasElse = false
  var branchIdx = 0
  for i in 1 ..< stmt.len:
    let br = stmt[i]
    if br.kind == nnkOfBranch:
      let buildProc = newProc(params = [newEmptyNode(), newIdentDefs(parentParam, ident"Node")],
                              body = transformUiBlock(br[^1], parentParam), procType = nnkLambda)
      buildProc.addPragma(ident"closure")
      builds.add(buildProc)
      var ofBr = newTree(nnkOfBranch)
      for j in 0 ..< br.len - 1: ofBr.add(br[j])
      ofBr.add(newLit(branchIdx))
      chooser.add(ofBr)
      inc branchIdx
    elif br.kind == nnkElse:
      let buildProc = newProc(params = [newEmptyNode(), newIdentDefs(parentParam, ident"Node")],
                              body = transformUiBlock(br[0], parentParam), procType = nnkLambda)
      buildProc.addPragma(ident"closure")
      builds.add(buildProc)
      chooser.add(newTree(nnkElse, newLit(branchIdx)))
      hasElse = true
      inc branchIdx
  if not hasElse: chooser.add(newTree(nnkElse, newLit(-1)))
  let branchProc = newProc(params = [ident"int"], body = newStmtList(chooser), procType = nnkLambda)
  newStmtList(newCall(ident"showWhen", parentSym, branchProc, prefix(builds, "@")))

proc transformUiStmt(stmt: NimNode; parentSym: NimNode; assignTo: NimNode = nil): NimNode =
  if stmt.kind == nnkStmtList:           # a block inside a block (macros make these)
    return transformUiBlock(stmt, parentSym)
  if stmt.kind == nnkAsgn and stmt[1].kind in {nnkCall, nnkCommand}:
    # `x = column(...)` keeps the node in x; `x = anyOtherCall(...)` is plain Nim, kept as is
    let head = headName(stmt[1])
    if head.len > 0 and (head.toLowerAscii() in nodeKinds or head[0].isUpperAscii()):
      return transformUiStmt(stmt[1], parentSym, assignTo = stmt[0])
    return stmt
  if stmt.kind == nnkIfStmt:
    return ifStmt(stmt, parentSym)
  if stmt.kind == nnkCaseStmt:
    return caseStmt(stmt, parentSym)
  if stmt.kind in {nnkCall, nnkCommand} and stmt.len > 0 and stmt[0].kind in {nnkIdent, nnkSym}:
    let name = $stmt[0]
    if name[0].isUpperAscii():
      # A component: `Card("x", 3)` -> `Card(parent, "x", 3)` [S-CMP-1]
      var call = newCall(stmt[0], parentSym)
      for i in 1 ..< stmt.len:
        if i == stmt.len - 1 and stmt[i].kind == nnkStmtList:
          # the caller's block becomes the component's children (its `slot()`)
          let kids = newProc(params = [newEmptyNode(), newIdentDefs(ident"yParent", ident"Node")],
                             body = transformUiBlock(stmt[i], ident"yParent"), procType = nnkLambda)
          kids.addPragma(ident"closure")
          call.add(newTree(nnkExprEqExpr, ident"yChildren", kids))
        else:
          call.add(stmt[i])
      return call
    let low = name.toLowerAscii()
    if low in nodeKinds:
      return nodeStmt(stmt, parentSym, assignTo)
    let ev = eventOf(low)
    if ev.len > 0 and stmt.len >= 2 and stmt[^1].kind == nnkStmtList:
      return eventHandler(parentSym, ev, stmt[^1])
    for (st, prefix) in stateBlocks:
      if low == st and stmt.len == 2 and stmt[1].kind == nnkStmtList:
        return stateBlock(parentSym, prefix, stmt[1])
    if low == "sized" and stmt.len >= 3 and stmt[^1].kind == nnkStmtList:
      # `sized w:` / `sized w, h:` — the container's laid-out size as signals (px), so
      # an `if w < 640:` inside rebuilds when it crosses: container queries [S-LAY-2]
      result = newStmtList()
      let wSym = if stmt[1].kind in {nnkIdent, nnkSym}: stmt[1] else: genSym(nskLet, "w")
      let hSym = if stmt.len >= 4 and stmt[2].kind in {nnkIdent, nnkSym}: stmt[2] else: genSym(nskLet, "h")
      result.add newLetStmt(wSym, newCall(ident"newState", newLit(0'f32)))
      result.add newLetStmt(hSym, newCall(ident"newState", newLit(0'f32)))
      result.add newCall(ident"trackSize", parentSym, wSym, hSym)
      result.add transformUiBlock(stmt[^1], parentSym)
      return result
    if low == "scrolled" and stmt.len == 3 and stmt[^1].kind == nnkStmtList:
      # `scrolled y:` — the container's scroll offset as a signal (px)
      result = newStmtList()
      let ySym = if stmt[1].kind in {nnkIdent, nnkSym}: stmt[1] else: genSym(nskLet, "y")
      result.add newLetStmt(ySym, newCall(ident"newState", newLit(0'f32)))
      result.add newCall(ident"trackScroll", parentSym, ySym)
      result.add transformUiBlock(stmt[^1], parentSym)
      return result
    if low == "lazy" and stmt.len == 4 and stmt[1].kind == nnkInfix and $stmt[1][0] == "in" and
       stmt[^1].kind == nnkStmtList:
      # `lazy m in msgs.get, 44:` — a scrolling list that builds only the rows that show
      # (rows `44` px tall), with spacers for the rest: 100 000 items cost what 20 do
      let loopVar = stmt[1][1]
      var src = stmt[1][2]
      var keyCall: NimNode = nil
      if src.kind == nnkCall and src[0].kind == nnkDotExpr and $src[0][1] == "keyed" and src.len == 2:
        keyCall = src[1]
        src = src[0][0]
      let rh = newCall(ident"float32", stmt[2])
      let wS = genSym(nskLet, "lzW")
      let hS = genSym(nskLet, "lzH")
      let yS = genSym(nskLet, "lzY")
      let first = newCall(ident"lazyFirst", newCall(ident"get", yS), rh)
      let last = newCall(ident"lazyLast", newCall(ident"get", yS), newCall(ident"get", hS), rh,
                         newCall(ident"len", src))
      var slice = newTree(nnkBracketExpr, src, infix(first, "..<", last))
      if keyCall != nil: slice = newCall(newDotExpr(slice, ident"keyed"), keyCall)
      let rowBody = stmt[^1]              # quote takes plain names only
      let body = quote do:
        column(grow = 1, scroll = true, minHeight = 0):
          sized `wS`, `hS`:
            scrolled `yS`:
              panel(height = float32(`first`) * `rh`)
              column:
                for `loopVar` in `slice`:
                  `rowBody`
              panel(height = float32(len(`src`) - `last`) * `rh`)
      return transformUiBlock(body, parentSym)
    if low == "slot" and stmt.len == 1:
      # the caller's block, placed here [S-CMP-4]
      return newIfStmt((infix(ident"yChildren", "!=", newNilLit()), newCall(ident"yChildren", parentSym)))
  result = stmt

proc transformUiBlock*(blk: NimNode; parentSym: NimNode): NimNode =
  result = newStmtList()
  if blk.kind != nnkStmtList:
    result.add(transformUiStmt(blk, parentSym))
    return
  var i = 0
  while i < blk.len:
    let s = blk[i]
    if s.kind == nnkForStmt:
      var emptyBlk: NimNode = nil
      if i + 1 < blk.len and headName(blk[i + 1]).toLowerAscii() == "empty" and blk[i + 1][^1].kind == nnkStmtList:
        emptyBlk = blk[i + 1][^1]
        inc i
      result.add(forStmt(s, parentSym, emptyBlk))
    else:
      result.add(transformUiStmt(s, parentSym))
    inc i

# --- app and component ------------------------------------------------------------

proc expandAppAst(title: NimNode; body: NimNode; props: seq[NimNode] = @[]): NimNode =
  let winSym = genSym(nskLet, "winNode")
  let inner = newStmtList()
  var winProps: seq[NimNode] = @[]
  for p in props:
    if p.kind == nnkExprEqExpr and ($p[0]).toLowerAscii() == "needs":
      let val = p[1]
      if val.kind == nnkBracket:
        var call = newCall(ident"needs")
        for elem in val: call.add elem
        inner.add call
      else:
        inner.add newCall(ident"needs", val)
    else:
      winProps.add p
  inner.add(newLetStmt(winSym, newCall(ident"window", title)))
  for p in winProps: inner.add(buildPropSetter(winSym, "Window", p))
  inner.add(transformUiBlock(body, winSym))
  result = newCall(ident"yantraRun", inner)

macro app*(title: string; args: varargs[untyped]): untyped =
  ## `app "Title", width = 480, height = 720:` then the UI block.
  var props: seq[NimNode] = @[]
  var body: NimNode = newStmtList()
  for a in args:
    if a.kind == nnkExprEqExpr: props.add(a)
    elif a.kind == nnkStmtList: body = a
  result = expandAppAst(title, body, props)

macro component*(p: untyped): untyped =
  ## `proc Card(title: string) {.component.} = <UI block>`: an ordinary proc whose
  ## body is a UI block. It gets a hidden first parameter, the parent node, which
  ## the caller's UI block supplies [S-CMP-1].
  if p.kind != nnkProcDef: error("{.component.} goes on a proc", p)
  result = p.copyNimTree()
  let params = result.params
  var np = newTree(nnkFormalParams, params[0], newIdentDefs(ident"yParent", ident"Node"))
  for i in 1 ..< params.len: np.add(params[i])
  # the caller's block, if any, for `slot()` [S-CMP-4]
  np.add(newIdentDefs(ident"yChildren",
    newTree(nnkProcTy, newTree(nnkFormalParams, newEmptyNode(), newIdentDefs(ident"p", ident"Node")),
            newTree(nnkPragma, ident"closure")), newNilLit()))
  result.params = np
  result.body = transformUiBlock(p.body, ident"yParent")

macro expandAppDsl*(body: untyped): string =
  var target = body
  if target.kind == nnkStmtList and target.len == 1:
    target = target[0]
  if target.kind in {nnkCall, nnkCommand} and ($target[0]).toLowerAscii() == "app":
    let ast = expandAppAst(target[1], target[^1])
    result = newLit(ast.repr)
  else:
    let ast = expandAppAst(newLit("App"), target)
    result = newLit(ast.repr)


macro style*(args: varargs[untyped]): untyped =
  ## `style(fill = …, radius = 12, pad = 16)`: a reusable set of props, applied with
  ## `use = …` [S-STY-3]. Call-site props written after `use` win.
  let n = ident"yStyled"
  var procs = newTree(nnkBracket)
  for a in args:
    if a.kind != nnkExprEqExpr: error("style takes named props: style(fill = …, radius = …)", a)
    let lam = newProc(params = [newEmptyNode(), newIdentDefs(n, ident"Node")],
                      body = newStmtList(buildPropSetter(n, "*", a, reactive = false, checkKind = false)),
                      procType = nnkLambda)
    lam.addPragma(ident"closure")
    procs.add lam
  if procs.len == 0:
    result = newCall(ident"Style")
  else:
    result = newTree(nnkObjConstr, ident"Style", newColonExpr(ident"apply", prefix(procs, "@")))
