## Editor — a code editor whose coloured pane is built by its own Sutra
## tokeniser: documents as records, a file list, a highlighted code view with a
## line gutter, a live buffer, and a status bar (Ln/Col, characters, lines,
## language, saved dot). Owner-scoped Doc search/open/edit/revert and private
## Atlas builds with native preview. The root fills its actual native window.

const editorPalette = 0 # keep the palette with the documentation cell in test builds
const studioBg = #0B1020
const chrome = #0E1526
const panel = #111A2C
const rule = #29354D
const raised = #182238
const ink = #E8EDF8
const dim = #A3AEC2
const faint = #7E8CA6
const accent = #929CF8
const accentSoft = #202A4B
const accentInk = #C7CDFF
const gold = #F2C57C
const good = #8FD3B6
const cKeyword = #C4B5FD
const cString = #9ED6B2
const cNumber = #F2C57C
const cColour = #F0A6C0
const cType = #89CFF0
const cComment = #7B8AA4
const ui = "Noto Sans"
const mono = "DejaVu Sans Mono"

const keywords = ["let", "proc", "func", "view", "record", "type", "state", "param", "for", "in",
                  "if", "elif", "else", "case", "of", "while", "return", "and", "or", "not",
                  "on", "tap", "discard", "import", "distinct", "object", "enum", "var", "const"]
const typeNames = ["string", "int", "float", "bool", "char", "seq", "Color", "User", "Doc", "Kind"]

let appText = @[
    "## app.nim — the note app this studio ships.",
    "let paper = #14131A",
    "let accent = #5B5BF6",
    "",
    "record Note",
    "  title: string",
    "  body: string",
    "  owner: User = me",
    "  can read, write: owner",
    "  check title != \"\", \"a note needs a title\"",
    "  search title",
    "",
    "proc words(note: Note): int =",
    "  ## the body, in words",
    "  for w in note.body.split(\" \"):",
    "    inc result",
    "",
    "view NoteRow(note: Note)",
    "  Row(gap = 10px, pad = 8px, fill = paper, radius = 8px):",
    "    Text note.title, size = 15px, weight = 600",
    "    Text note.body, size = 13px, color = #8A8698",
    "    Spacer(grow = 1)",
    "    Text $words(note), size = 12px",
    "",
    "view Notes",
    "  state draft = \"\"",
    "  Column(gap = 12px, pad = 24px, fill = paper):",
    "    Text \"Notes\", size = 28px, weight = 700",
    "    Input draft, placeholder = \"Search title\"",
    "    Button \"New note\", fill = accent, color = #FFFFFF:",
    "      on tap: discard Note.create(\"Untitled\")",
    "    for n in Note.sort(title).take(5):",
    "      NoteRow n, key = n.id",
  ].join("\n")

let highlightText = @[
    "## highlight.nim — the tokeniser behind this pane.",
    "type Kind = enum kComment, kString, kKeyword, kNumber",
    "",
    "type Tok = object",
    "  txt: string",
    "  kind: Kind",
    "",
    "proc tint(k: Kind): Color =",
    "  case k",
    "  of kComment: #5E5A6B",
    "  of kString: #A6E3A1",
    "  of kKeyword: #C792EA",
    "  of kNumber: #F2B65C",
    "",
    "proc toks(line: string): seq[Tok] =",
    "  ## cut the line at every kind of token",
    "  var i = 0",
    "  while i < line.len:",
    "    if line[i] == '#':",
    "      result.add Tok(txt: line[i .. ^1], kind: kComment)",
    "      break",
    "    inc i",
  ].join("\n")

let themeText = @[
    "## theme.nim — the seven inks of this editor.",
    "let bg = #0B0B10",
    "let ink = #E8E5F0",
    "let accent = #5B5BF6",
    "let keyword = #C792EA",
    "let text = #A6E3A1",
    "let number = #F2B65C",
    "let colour = #F07AA0",
    "let typename = #7FD7EC",
    "let comment = #5E5A6B",
  ].join("\n")

# The three sheets the studio opens with. They are also the fallback when the
# host has no database: `sutra_query` answers "\x15this host has no database",
# the prelude raises on that marker, and a raise inside a view truncates the
# tree — which is exactly how this app rendered ONE colour (a window and an
# empty Column, 512 nodes never built) when run as a plain module.
proc builtinNames(): seq[string] = @["app.nim", "highlight.nim", "theme.nim"]

record Doc
  name: string
  body: string
  owner: User = me
  can read, write: owner
  search name

record Workbench
  source: string
  space: string = ""
  root: string = ""
  status: string = "queued"
  diagnostics: string = ""
  preview: string = ""
  revision: int = 0
  owner: User = me
  can read, write: owner

# A queued Workbench row is the editor's only build request. The native Sutra
# host imports its source as private cells as this same owner, compiles it, and
# writes the real result back here before this event finishes.
type Kind = enum kComment, kString, kKeyword, kNumber, kColour, kType, kIdent, kSpace, kPunct

type Tok = object
  txt: string
  kind: Kind

type Line = object
  num: int
  txt: string

proc tint(k: Kind): Color =
  case k
  of kComment: cComment
  of kString: cString
  of kKeyword: cKeyword
  of kNumber: cNumber
  of kColour: cColour
  of kType: cType
  of kIdent: ink
  else: dim

proc isWord(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc colourAt(line: string; i: int): int =
  ## `#5B5BF6` is a colour; only a `#` that is not one opens a comment.
  let hex = {'0'..'9', 'a'..'f', 'A'..'F'}
  if i + 1 >= line.len or line[i + 1] notin hex: return 0
  var j = i + 1
  while j < line.len and line[j] in hex: inc j
  let n = j - i - 1
  if n == 3 or n == 6 or n == 8: n + 1 else: 0

proc toks(line: string): seq[Tok] =
  ## Cuts one line into typed tokens: comment, string, keyword, number, colour,
  ## type name, identifier, space, punctuation.
  var i = 0
  while i < line.len:
    let c = line[i]
    var j = i
    var k = kPunct
    if c == '#' and colourAt(line, i) > 0:
      j = i + colourAt(line, i)
      k = kColour
    elif c == '#':
      j = line.len
      k = kComment
    elif c == '"':
      j = i + 1
      while j < line.len and line[j] != '"':
        if line[j] == '\\': inc j
        inc j
      j = min(j + 1, line.len)
      k = kString
    elif c >= '0' and c <= '9':
      while j < line.len and (line[j] >= '0' and line[j] <= '9' or line[j] == '.'): inc j
      k = kNumber
    elif isWord(c):
      while j < line.len and isWord(line[j]): inc j
      let w = line[i ..< j]
      if w in keywords: k = kKeyword
      elif w in typeNames: k = kType
      else: k = kIdent
    elif c == ' ' or c == '\t':
      while j < line.len and (line[j] == ' ' or line[j] == '\t'): inc j
      k = kSpace
    else:
      while j < line.len and not isWord(line[j]) and line[j] notin {' ', '\t', '"', '#'}: inc j
      k = kPunct
    if j <= i: j = i + 1
    result.add Tok(txt: line[i ..< j], kind: k)
    i = j

proc linesOf(body: string): seq[Line] =
  var n = 0
  for ln in body.splitLines():
    inc n
    result.add Line(num: n, txt: ln)

proc gutter(n: int; hot: bool): string =
  ## A gutter four characters wide, so every line starts at the same column.
  result = if hot: "▸" else: " "
  if n < 10: result.add " "
  result.add $n
  result.add " "

proc changedAt(a, b: string): int =
  ## Where the buffer last changed: the caret a view can honestly know.
  result = 0
  while result < a.len and result < b.len and a[result] == b[result]: inc result

proc lineAt(t: string; at: int): int =
  result = 1
  var i = 0
  while i < at and i < t.len:
    if t[i] == '\n': inc result
    inc i

proc colAt(t: string; at: int): int =
  result = 1
  var i = 0
  while i < at and i < t.len:
    if t[i] == '\n': result = 1 else: inc result
    inc i

proc charCount(t: string): int =
  ## Characters, not bytes: a UTF-8 continuation byte is not one.
  for c in t:
    if (ord(c) and 0xC0) != 0x80: inc result

proc savedDot(dirty: bool): string =
  if dirty: "Unsaved" else: "Saved"

proc commentLine(ln: string): string =
  var i = 0
  while i < ln.len and ln[i] == ' ': inc i
  ln[0 ..< i] & "# " & ln[i .. ^1]

proc uncomment(ln: string): string =
  let i = ln.find('#')
  if i < 0: return ln
  var j = i + 1
  if j < ln.len and ln[j] == ' ': inc j
  ln[0 ..< i] & ln[j .. ^1]

proc toggleComment(body: string; line: int): string =
  ## The editor's Ctrl+/: comment the caret's line, or uncomment it again.
  var n = 0
  for ln in body.splitLines():
    inc n
    if result.len > 0: result.add "\n"
    var l = ln
    if n == line:
      if ln.strip.startsWith("#"): l = uncomment(ln) else: l = commentLine(ln)
    result.add l

test "editor comment and caret helpers":
  let changed = toggleComment("let a = 1\nlet b = 2", 1)
  check changed == "# let a = 1\nlet b = 2"
  check toggleComment(changed, 1) == "let a = 1\nlet b = 2"
  check lineAt("one\ntwo", 4) == 2
  check colAt("one\ntwo", 4) == 1
  check charCount("aé") == 2

test "document update commits and remains searchable":
  let d = Doc.create(name = "commitprobe", body = "let before = 1")
  discard d.update(body = "let after = 2")
  check Doc.find(d.id).body == "let after = 2"
  check Doc.where(search("commitprobe")).count == 1
  d.delete()
  check Doc.where(search("commitprobe")).count == 0

proc matchingCount(query: string): int =
  for nm in builtinNames():
    if query == "" or nm.contains(query): inc result

proc firstRecordName(): string =
  ## The Atlas's first sheet name, or "" when the host has no database.
  ## A query from inside a handler cell reached arkham's backend as "field
  ## `name` on a base of i32" (programs.nim:1688), so the query lives in a proc.
  try:
    for d in Doc.sort(name):
      return d.name
  except e:
    discard
  ""

proc firstRecordBody(): string =
  try:
    for d in Doc.sort(name):
      return d.body
  except e:
    discard
  ""

view Editor
  # The studio opens on its own source, always: the three sheets below are the
  # app's own copy, so a host with no database still gets a whole studio. The
  # first frame asks the Atlas afterwards and adopts the records if it answers.
  state body = appText
  state saved = appText
  state picked = "app.nim"
  state loaded = false
  state mark = ""
  state caretAt = 0
  state query = ""
  state commands = false
  state savedNote = ""
  state buildNote = ""
  if body != mark:
    caretAt = changedAt(mark, body)
    mark = body
  let ln = lineAt(body, caretAt)
  let col = colAt(body, caretAt)
  let dirty = body != saved
  let nlines = linesOf(body).len
  let nchars = charCount(body)
  let sheets = builtinNames()
  let bodies = @[appText, highlightText, themeText]
  let nshown = matchingCount(query)
  Column(fill = studioBg, width = 1280px, height = 816px):
    Row(fill = chrome, height = 58px, padLeft = 20px, padRight = 20px, gap = 12px, alignItems = 1):
      Panel(width = 34px, height = 34px, fill = accentSoft, radius = 9px, justify = 1, alignItems = 1):
        Text "Y", font = ui, size = 17px, weight = 700, color = accentInk
      Column(gap = 1px):
        Text "YANTRA", font = ui, size = 14px, weight = 700, color = ink
        Text "CODE STUDIO", font = ui, size = 10px, weight = 600, color = accentInk
      Panel(width = 1px, height = 28px, fill = rule)
      Column(gap = 2px, padLeft = 2px):
        Text "WORKSPACE", font = ui, size = 10px, weight = 600, color = faint
        Text "editor / documents", font = ui, size = 13px, weight = 600, color = dim
      Spacer(grow = 1)
      Button "Command", font = ui, fill = (if commands: accentSoft else: raised), color = (if commands: accentInk else: dim), radius = 8px, size = 12px, weight = 600, padTop = 9px, padBottom = 9px, padLeft = 13px, padRight = 13px:
        on tap: commands = not commands
      Button "Comment", font = ui, fill = raised, color = dim, radius = 8px, size = 12px, weight = 600, padTop = 9px, padBottom = 9px, padLeft = 13px, padRight = 13px:
        on tap: body = toggleComment(body, ln)
      Button "Revert", font = ui, fill = raised, color = dim, radius = 8px, size = 12px, weight = 600, padTop = 9px, padBottom = 9px, padLeft = 13px, padRight = 13px:
        on tap: body = saved
      Button "Build", font = ui, fill = raised, color = accentInk, radius = 8px, size = 12px, weight = 700, padTop = 9px, padBottom = 9px, padLeft = 15px, padRight = 15px:
        on tap:
          try:
            var queued = false
            for w in Workbench.all():
              if not queued:
                discard w.update(source = body, status = "queued", diagnostics = "", preview = "")
                queued = true
              else:
                w.delete()
            if not queued:
              discard Workbench.create(source = body, status = "queued")
            buildNote = "queued for the native host"
          except e:
            buildNote = "the host has no workbench here"
      Button "Save", font = ui, fill = accent, color = #101425, radius = 8px, size = 12px, weight = 700, padTop = 9px, padBottom = 9px, padLeft = 17px, padRight = 17px:
        on tap:
          saved = body
          savedNote = "saved"
          try:
            var found = false
            for d in Doc.sort(name):
              if d.name == picked:
                discard d.update(body = body)
                found = true
                savedNote = "saved to the Atlas"
            if not found:
              discard Doc.create(name = picked, body = body)
              savedNote = "saved to the Atlas"
          except e:
            savedNote = "kept in the buffer (no database here)"
    Panel(height = 1px, fill = rule)
    if commands:
      Row(fill = panel, height = 54px, padLeft = 22px, padRight = 20px, gap = 11px, alignItems = 1):
        Text "COMMAND ACTIONS", font = ui, size = 11px, weight = 700, color = accentInk
        Text "Act on the open buffer", font = ui, size = 12px, color = dim
        Spacer(grow = 1)
        Button "Comment line", font = ui, fill = raised, color = ink, radius = 7px, size = 12px, padTop = 8px, padBottom = 8px, padLeft = 12px, padRight = 12px:
          on tap:
            body = toggleComment(body, ln)
            commands = false
        Button "Revert buffer", font = ui, fill = raised, color = ink, radius = 7px, size = 12px, padTop = 8px, padBottom = 8px, padLeft = 12px, padRight = 12px:
          on tap:
            body = saved
            commands = false
        Button "Save document", font = ui, fill = accentSoft, color = accentInk, radius = 7px, size = 12px, weight = 600, padTop = 8px, padBottom = 8px, padLeft = 12px, padRight = 12px:
          on tap:
            for d in Doc.sort(name):
              if d.name == picked:
                discard d.update(body = body)
            saved = body
            commands = false
        Button "Done", font = ui, fill = panel, color = dim, radius = 7px, size = 12px, padTop = 8px, padBottom = 8px, padLeft = 12px, padRight = 12px:
          on tap: commands = false
      Panel(height = 1px, fill = rule)
    Row(grow = 1, alignItems = 3):
      Column(fill = chrome, width = 242px, padTop = 18px, padBottom = 16px, padLeft = 14px, padRight = 14px, gap = 12px):
        Row(height = 20px, alignItems = 1):
          Text "EXPLORER", font = ui, size = 12px, weight = 700, color = ink
          Spacer(grow = 1)
          Text "{nshown}", font = ui, size = 12px, weight = 600, color = dim
        Input query, placeholder = "Search files", font = ui, size = 13px, fill = raised, color = ink, radius = 8px, pad = 10px, border = 1px, borderColor = rule
        Row(height = 18px, padTop = 3px, alignItems = 1):
          Text "DOCUMENTS", font = ui, size = 11px, weight = 700, color = dim
          Spacer(grow = 1)
          Text "{sheets.len} sheets", font = ui, size = 11px, color = faint
        Column(gap = 4px, grow = 1, scroll = true):
          for i in 0 ..< sheets.len:
            if query == "" or sheets[i].contains(query):
              Panel(fill = (if sheets[i] == picked: accentSoft else: chrome), radius = 7px, padTop = 11px, padBottom = 11px, padLeft = 11px, padRight = 11px):
                on tap:
                  picked = sheets[i]
                Row(gap = 9px, alignItems = 1):
                  Panel(width = 2px, height = 16px, fill = (if sheets[i] == picked: accent else: chrome), radius = 1px)
                  Text sheets[i], grow = 1, font = ui, size = 13px, weight = (if sheets[i] == picked: 600 else: 400), color = (if sheets[i] == picked: accentInk else: dim), maxLines = 1
          if query != "" and nshown == 0:
            Text "No matching files", font = ui, size = 13px, weight = 600, color = dim, padTop = 8px
            Button "Clear search", font = ui, fill = raised, color = accentInk, radius = 7px, size = 12px, padTop = 9px, padBottom = 9px, padLeft = 12px, padRight = 12px:
              on tap: query = ""
          elif sheets.len == 0:
            Text "No sheets yet", font = ui, size = 13px, weight = 600, color = dim, padTop = 8px
            Text "The buffer remains editable.", font = ui, size = 12px, color = faint, lineHeight = 1.4
        Panel(height = 1px, fill = rule)
        Column(gap = 6px, padLeft = 2px, padRight = 2px):
          Text "DOCUMENT STORAGE", font = ui, size = 10px, weight = 700, color = faint
          Text "record Doc · search name", font = mono, size = 11px, color = dim
          Text "Owned by you · read / write", font = ui, size = 11px, color = faint
      Column(grow = 1, fill = studioBg):
        Row(fill = chrome, height = 48px, padLeft = 20px, padRight = 22px, gap = 11px, alignItems = 1):
          Panel(width = 3px, height = 22px, fill = accent, radius = 2px)
          Text picked, font = ui, size = 14px, weight = 600, color = ink, maxLines = 1
          Text savedDot(dirty), font = ui, size = 12px, weight = 600, color = (if dirty: gold else: good)
          Spacer(grow = 1)
          Text "Sutra", font = ui, size = 12px, weight = 600, color = accentInk
          Text "UTF-8", font = ui, size = 11px, color = faint
        Panel(height = 1px, fill = rule)
        Column(grow = 1, fill = studioBg, padTop = 14px, padBottom = 14px, padLeft = 18px, padRight = 18px, gap = 10px):
          Row(height = 20px, padLeft = 2px, padRight = 2px, gap = 8px, alignItems = 1):
            Text "SOURCE", font = ui, size = 11px, weight = 700, color = dim
            Text "· live syntax", font = ui, size = 11px, color = faint
            Spacer(grow = 1)
            Text "{nlines} lines · {nchars} characters", font = ui, size = 11px, color = dim
          Column(grow = 1, fill = studioBg, radius = 10px, border = 1px, borderColor = rule, padTop = 11px, padBottom = 11px, padLeft = 13px, padRight = 16px, gap = 0px, clip = true, scroll = true):
            for l in linesOf(body):
              let hot = l.num == ln
              Row(gap = 0px, pad = 0px, height = 24px):
                Text gutter(l.num, hot), font = mono, size = 14px, color = (if hot: accentInk else: faint), maxLines = 1
                Text "│", font = mono, size = 14px, color = rule, maxLines = 1
                for tk in toks(l.txt):
                  Text tk.txt, font = mono, size = 14px, color = tint(tk.kind), maxLines = 1
          Column(height = 184px, fill = chrome, radius = 10px, border = 1px, borderColor = rule, padTop = 11px, padBottom = 11px, padLeft = 12px, padRight = 12px, gap = 9px):
            Row(height = 18px, padLeft = 2px, padRight = 2px, gap = 12px, alignItems = 1):
              Text "EDIT BUFFER", font = ui, size = 11px, weight = 700, color = accentInk
              Text "Changes re-tokenise above", font = ui, size = 11px, color = dim
              Spacer(grow = 1)
              Text picked, font = ui, size = 11px, color = faint, maxLines = 1
            TextArea body, grow = 1, font = mono, size = 13px, lineHeight = 1.35, color = ink, fill = raised, radius = 8px, border = 1px, borderColor = rule, pad = 10px
    if buildNote != "":
      Column(height = 96px, fill = chrome, padTop = 10px, padBottom = 10px, padLeft = 16px, padRight = 16px, gap = 6px):
        Row(height = 20px, gap = 10px, alignItems = 1):
          Text "PRIVATE WORKBENCH", font = ui, size = 11px, weight = 700, color = accentInk
          Spacer(grow = 1)
          Text buildNote, font = ui, size = 11px, weight = 600, color = gold
        Text "Build sends this buffer to the native host, which compiles it into a private app and draws it back here.", font = ui, size = 11px, color = dim, maxLines = 2
    Row(fill = chrome, height = 34px, padLeft = 20px, padRight = 20px, gap = 18px, alignItems = 1):
      Text savedDot(dirty), font = ui, size = 11px, weight = 600, color = (if dirty: gold else: good)
      Text "Ln {ln}, Col {col}", font = ui, size = 11px, weight = 600, color = ink
      Text "{nlines} lines", font = ui, size = 11px, color = dim
      Text "{nchars} characters", font = ui, size = 11px, color = dim
      Spacer(grow = 1)
      Text "{sheets.len} sheets", font = ui, size = 11px, color = faint
      if savedNote != "":
        Text savedNote, font = ui, size = 11px, weight = 600, color = good
      Text "Sutra · UTF-8", font = ui, size = 11px, color = dim
