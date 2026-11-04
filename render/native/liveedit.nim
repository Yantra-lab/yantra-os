## Live edits (roadmap §5): small typed changes — from a model, a tool or a person — applied
## to a running app at once, and written into its source so they last. The app's code
## stays the one source of truth: a live change is a preview of the source change, which
## the hot reloader (devwatch.nim) then builds and swaps in with the app's state kept.
##
## The edit language, one per line:
##   set @headline.size = 80                  a prop, by name (`text @headline "…"`)
##   set notes.nim:72:6.color = accent        …or by where the node's code is (its Site)
##   insert after @headline: text "Made in Yantra", size = 24
##   remove @subtitle
## Props are checked against protocol/schema.nim: an unknown or misplaced prop is refused
## with a suggestion, before anything changes.

import std/[strutils, os, tables]
import ../../protocol/[schema, wire]
import ../../host/[host, tree]
import engine

type
  EditKind* = enum ekSet, ekInsertAfter, ekRemove
  Edit* = object
    kind*: EditKind
    target*: string                ## "@name" or a Site "file.nim:line:col"
    prop*, value*: string          ## set: the prop and its new value, as Yantra code
    code*: string                  ## insert: the statement to add
  EditResult* = object
    ok*: bool
    error*: string
    files*: seq[string]            ## source files changed
    live*: int                     ## nodes changed on screen right away

# --- reading edits ----------------------------------------------------------------------

proc parseEdit*(line: string): (Edit, string) =
  ## One edit from its text; the string is an error ("" if fine).
  let l = line.strip
  if l.startsWith("set "):
    let rest = l[4 .. ^1]
    let eq = rest.find('=')
    if eq < 0: return (Edit(), "set needs `= value`: set @name.prop = value")
    let lhs = rest[0 ..< eq].strip
    let dot = lhs.rfind('.')
    if dot <= 0: return (Edit(), "set needs a target and a prop: set @name.prop = value")
    return (Edit(kind: ekSet, target: lhs[0 ..< dot], prop: lhs[dot + 1 .. ^1], value: rest[eq + 1 .. ^1].strip), "")
  if l.startsWith("insert after "):
    let rest = l[13 .. ^1]
    let colon = rest.find(':')
    if colon < 0: return (Edit(), "insert needs `: code`: insert after @name: text \"…\"")
    var target = rest[0 ..< colon].strip
    var code = rest[colon + 1 .. ^1].strip
    if not target.startsWith("@"):         # a Site has colons of its own: file.nim:line:col: code
      let parts = rest.split(':')
      if parts.len >= 4:
        target = parts[0 .. 2].join(":").strip
        code = parts[3 .. ^1].join(":").strip
    if code.len == 0: return (Edit(), "insert needs the code to add")
    return (Edit(kind: ekInsertAfter, target: target, code: code), "")
  if l.startsWith("remove "):
    return (Edit(kind: ekRemove, target: l[7 .. ^1].strip), "")
  (Edit(), "unknown edit: " & l & " (set, insert after, remove)")

# --- finding code in a source file (pure: tested on strings) ----------------------------

proc offsetOf(src: string; line, col: int): int =
  ## Byte offset of 1-based `line`, 0-based `col`; -1 if out of range.
  var l = 1
  var i = 0
  while l < line:
    let nl = src.find('\n', i)
    if nl < 0: return -1
    i = nl + 1
    inc l
  if i + col > src.len: -1 else: i + col

proc lineStart(src: string; at: int): int =
  var i = at
  while i > 0 and src[i - 1] != '\n': dec i
  i

proc indentOf(src: string; at: int): int =
  var i = lineStart(src, at)
  result = 0
  while i < src.len and src[i] == ' ':
    inc i; inc result

type Span = object
  a, b: int                        ## [a, b) in the source

proc skipString(src: string; i: int): int =
  ## Past a string literal starting at i (" or """); returns the index after it.
  if src.continuesWith("\"\"\"", i):
    let e = src.find("\"\"\"", i + 3)
    return (if e < 0: src.len else: e + 3)
  var j = i + 1
  while j < src.len and src[j] != '"' and src[j] != '\n':
    if src[j] == '\\': inc j
    inc j
  min(j + 1, src.len)

proc callArgs*(src: string; line, col: int): (seq[Span], int, bool) =
  ## The top-level arguments of the node call whose code is at (line, col): their spans,
  ## where a new argument would go, and whether the call is `f(…)` style.
  var i = offsetOf(src, line, col)
  if i < 0: return (@[], -1, false)
  var paren = false
  if src[i] == '(':
    paren = true
    inc i
  else:                                     # command style: skip the head word
    while i < src.len and (src[i].isAlphaNumeric or src[i] == '_'): inc i
  var args: seq[Span]
  var depth = 0
  var start = i
  var endAt = -1
  var lastNonSpace = i
  while i < src.len:
    let c = src[i]
    if c == '"':
      i = skipString(src, i)
      lastNonSpace = i - 1
      continue
    if c == '#':                            # a comment: to the end of the line
      while i < src.len and src[i] != '\n': inc i
      continue
    if c in {'(', '[', '{'}: inc depth
    elif c in {')', ']', '}'}:
      if depth == 0 and paren:
        endAt = i
        break
      dec depth
    elif c == ',' and depth == 0:
      args.add Span(a: start, b: i)
      start = i + 1
    elif c == ':' and depth == 0 and not paren:
      # a block starts here (`text "x", size = 3:`) unless it is part of a value
      var j = i + 1
      while j < src.len and src[j] == ' ': inc j
      if j >= src.len or src[j] in {'\n', '\r', '#'}:
        endAt = i
        break
    elif c == '\n' and depth == 0 and not paren:
      if src[lastNonSpace] != ',':          # the statement ends with its line
        endAt = i
        if i > 0 and src[i - 1] == '\r': endAt = i - 1
        break
    if c notin {' ', '\n', '\r'}: lastNonSpace = i
    inc i
  if endAt < 0: endAt = src.len
  if src[start ..< endAt].strip.len > 0: args.add Span(a: start, b: endAt)
  var trimmed: seq[Span]
  for s in args:
    var a = s.a
    var b = s.b
    while a < b and src[a] in {' ', '\n', '\r'}: inc a
    while b > a and src[b - 1] in {' ', '\n', '\r'}: dec b
    if b > a: trimmed.add Span(a: a, b: b)
  (trimmed, endAt, paren)

proc setArg*(src: string; line, col: int; prop, value: string): (string, string) =
  ## `prop = value` in the call at (line, col): replaced if it is there, else added.
  ## Returns the new source, or "" and an error.
  let (args, endAt, paren) = callArgs(src, line, col)
  if endAt < 0: return ("", "no code at line " & $line)
  for s in args:
    let text = src[s.a ..< s.b]
    let eq = text.find('=')
    if eq > 0 and cmpIgnoreStyle(text[0 ..< eq].strip, prop) == 0 and text[eq + 1] != '=':
      var v = s.a + eq + 1
      while v < s.b and src[v] == ' ': inc v
      return (src[0 ..< v] & value & src[s.b .. ^1], "")
  let piece = (if args.len > 0: ", " else: (if paren: "" else: " ")) & prop & " = " & value
  (src[0 ..< endAt] & piece & src[endAt .. ^1], "")

proc stmtEnd(src: string; line, col: int): int =
  ## Offset just past the statement at (line, col) and everything indented under it.
  let at = offsetOf(src, line, col)
  let ind = indentOf(src, at)
  var i = src.find('\n', at)
  if i < 0: return src.len
  inc i
  while i < src.len:
    var j = i
    var k = 0
    while j < src.len and src[j] == ' ':
      inc j; inc k
    let blank = j >= src.len or src[j] in {'\n', '\r'}
    if not blank and k <= ind: break
    let nl = src.find('\n', i)
    if nl < 0: return src.len
    i = nl + 1
  i

proc insertAfter*(src: string; line, col: int; code: string): string =
  ## `code` as the next statement after the one at (line, col), at its indentation.
  let at = offsetOf(src, line, col)
  let pad = spaces(indentOf(src, at))
  let e = stmtEnd(src, line, col)
  var lines: seq[string]
  for l in code.splitLines: lines.add pad & l
  let nl = if "\r\n" in src: "\r\n" else: "\n"
  let body = lines.join(nl) & nl
  if e >= src.len and not src.endsWith("\n"): src & nl & body
  else: src[0 ..< e] & body & src[e .. ^1]

proc removeStmt*(src: string; line, col: int): string =
  ## Deletes the statement at (line, col) and everything under it.
  let s = lineStart(src, offsetOf(src, line, col))
  src[0 ..< s] & src[stmtEnd(src, line, col) .. ^1]

# --- applying edits to a running app ------------------------------------------------------

proc siteOf(s: string): (string, int, int) =
  let p = s.split(':')
  if p.len < 3: return ("", 0, 0)
  try: (p[0], parseInt(p[1]), parseInt(p[2].split('#')[0]))
  except ValueError: ("", 0, 0)

proc targets(e: Engine; target: string): seq[int32] =
  ## Every live node the target names: by `@name`, or by the code that made it.
  for i, n in e.s.nodes:
    if not n.alive: continue
    if target.startsWith("@"):
      if n.sProp(P_NAME) == target[1 .. ^1]: result.add int32(i)
    elif n.sProp(P_SITE) == target.split('#')[0]: result.add int32(i)

proc liveValue(n: tree.Node; prop, value: string): (int32, Value, bool) =
  ## A plain literal the engine can show right away (the rebuild brings everything else).
  let v = value.strip
  let norm = prop.toLowerAscii
  let wireName = case norm
    of "fill": "Color"
    of "color", "textcolor": "TextColor"
    of "size", "fontsize": "FontSize"
    else:
      let i = findPropMeta(prop)
      if i < 0: return (0, Value(), false) else: PropTable[i].wireProp
  let pid = int32(Props.find(wireName))
  if pid < 0: return (0, Value(), false)
  let meta = findPropMeta(prop)
  let typ = if meta >= 0: PropTable[meta].propType elif norm in ["fill", "color"]: "int32" else: "int32"
  try:
    if v.len >= 2 and v[0] == '"' and v[^1] == '"' and typ == "string":
      return (pid, Value(kind: vkString, s: v[1 .. ^2]), true)
    if v.startsWith("0x"):
      return (pid, Value(kind: vkInt, i: cast[int32](uint32(fromHex[int64](v) or 0xFF000000'i64))), true)
    if typ == "float32": return (pid, Value(kind: vkFloat, f: float32(parseFloat(v))), true)
    if typ in ["int32", "bool"]:
      if v in ["true", "false"]: return (pid, Value(kind: vkInt, i: int32(v == "true")), true)
      return (pid, Value(kind: vkInt, i: int32(parseFloat(v))), true)
  except ValueError:
    return (0, Value(), false)             # not a plain literal: the rebuild will show it
  (0, Value(), false)

proc kindName(k: int32): string = (if k >= 0 and k < NodeKinds.len: NodeKinds[k] else: "?")

proc sourceFile(e: Engine; file: string): string =
  ## The app's source file `file` (a name from a Site), found next to its .wasm.
  if validAssetPath(file) and fileExists(e.appDir / file): e.appDir / file else: ""

proc applyEdit*(e: Engine; ed: Edit): EditResult =
  ## Checks the edit, shows it at once where it can, and writes it into the source.
  let nodes = e.targets(ed.target)
  if nodes.len == 0:
    return EditResult(error: "no node is " & ed.target & " (names come from `text @name …`)")
  let site = e.node(nodes[0]).sProp(P_SITE)
  if site.len == 0:
    return EditResult(error: ed.target & " has no source location — is this a release build?")
  let (file, line, col) = siteOf(site)
  let path = e.sourceFile(file)
  if path.len == 0: return EditResult(error: "cannot find " & file & " next to the app")
  var src = readFile(path)
  case ed.kind
  of ekSet:
    let kind = kindName(e.node(nodes[0]).kind)
    let special = ed.prop.toLowerAscii in ["fill", "shadow", "use", "enter", "exit", "animate", "padx", "pady",
                                            "margin", "marginx", "marginy"]
    if not special and not isPropAllowedOnNode(ed.prop, kind):
      let sug = suggestPropName(ed.prop, kind)
      return EditResult(error: "'" & ed.prop & "' is not a prop of " & kind.toLowerAscii &
                        (if sug.len > 0: " — did you mean '" & sug & "'?" else: ""))
    let (patched, err) = setArg(src, line, col, ed.prop, ed.value)
    if err.len > 0: return EditResult(error: err)
    src = patched
    result.ok = true
    let (pid, v, ok) = liveValue(e.node(nodes[0]), ed.prop, ed.value)
    if ok:
      for id in nodes:
        e.s.setProp(id, pid, v)
        inc result.live
      e.dirty = true
  of ekInsertAfter:
    src = insertAfter(src, line, col, ed.code)
    result.ok = true
  of ekRemove:
    src = removeStmt(src, line, col)
    result.ok = true
  writeFile(path, src)
  result.files.add path

proc applyEdits*(e: Engine; text: string): EditResult =
  ## Several edits, one per line. All are read first, then applied from the bottom of each
  ## file up (so an insert never moves the code a later edit points at); if any is refused,
  ## every file goes back to how it was and nothing on screen changes for the rest.
  var eds: seq[(Edit, int)]
  for l in text.splitLines:
    if l.strip.len == 0 or l.strip.startsWith("#"): continue
    let (ed, err) = parseEdit(l)
    if err.len > 0: return EditResult(error: err)
    let ns = e.targets(ed.target)
    let line = if ns.len > 0: siteOf(e.node(ns[0]).sProp(P_SITE))[1] else: 0
    eds.add (ed, line)
  var before: Table[string, string]
  for f in walkFiles(e.appDir / "*.nim"): before[f] = readFile(f)
  for i in 0 ..< eds.len:                       # bottom-up
    for j in i + 1 ..< eds.len:
      if eds[j][1] > eds[i][1]: swap(eds[i], eds[j])
  result.ok = true
  for (ed, _) in eds:
    let r = e.applyEdit(ed)
    if not r.ok:
      for f, src in before:
        if readFile(f) != src: writeFile(f, src)
      return EditResult(error: r.error)
    result.live += r.live
    for f in r.files:
      if f notin result.files: result.files.add f
