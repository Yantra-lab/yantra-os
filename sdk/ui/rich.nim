## Rich text (R2): `rich "Some **bold**, *italic*, `code`, ~~gone~~ and [a link](https://x.com)"`
## is one Text node whose runs are styled by the engine (SkParagraph): one paragraph, wrapped
## as a whole, selectable like any text. The markup is a small inline Markdown.

import std/[strutils, algorithm]
import ../core/runtime

const
  fBold* = 1
  fItalic* = 2
  fUnderline* = 4
  fStrike* = 8
  fMono* = 16
  linkColor* = 0xFF5B5BF6'u32

type RichRun* = object
  a*, b*: int          ## byte range in the plain text
  flags*: int
  color*: uint32       ## 0 = the text's own
  link*: string

# --- the delimiters, and the rules that decide when bytes are one --------------

const
  mBold = 0            ## `**`
  mStar = 1            ## `*`
  mStrike = 2          ## `~~`
  mUnder = 3           ## `_`   (a single `_`; `__` is not a delimiter here)
  nMarks = 4

const
  markers: array[nMarks, string] = ["**", "*", "~~", "_"]
  markFlags: array[nMarks, int] = [fBold, fItalic, fStrike, fItalic]

proc isSpaceByte(c: char): bool = c in {' ', '\t', '\n', '\r', '\f', '\v'}

proc isWordByte(c: char): bool =
  ## A byte that can be part of a word. Bytes >= 0x80 count, so a `_` inside a
  ## non-ASCII identifier is a word byte too.
  let u = ord(c)
  u >= 0x80 or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
    (c >= '0' and c <= '9') or c == '_'

proc isPunctByte(c: char): bool =
  ## Delimiter-adjacent punctuation (CommonMark's "punctuation", ASCII range):
  ## printable, and neither a space nor an alphanumeric. `_` counts as punctuation.
  let u = ord(c)
  u < 0x80 and u > 0x20 and not (c >= 'a' and c <= 'z') and
    not (c >= 'A' and c <= 'Z') and not (c >= '0' and c <= '9')

proc canOpen(s: string; i, k: int): bool =
  ## Whether the delimiter at `i` is allowed to OPEN a run of mark `k`.
  ##
  ## Two rules, both stated on the delimiter rather than on any particular word:
  ##
  ## 1. FLANKING (CommonMark). A delimiter may open only if what follows it is not
  ##    whitespace and is not itself punctuation: this keeps `src/*.nim`, `~/dev/*`
  ##    and `2 * 3` out of the markup, because in each of them the `*` sits between
  ##    punctuation or between two spaces, so there is nothing for it to open.
  ##
  ## 2. WORD BOUNDARY, for `_` only. `_` is the one delimiter that occurs INSIDE
  ##    ordinary identifiers — `snake_case_name`, `some_function_name`, `a_b_c` —
  ##    where it joins words and means nothing else. So a `_` may open only when the
  ##    byte before it is not a word byte. Nothing in this rule mentions any specific
  ##    identifier: every one of them is protected by the same boundary. A `_` next
  ##    to another `_` is not a delimiter either, which is why `__bold__` stays text —
  ##    this markup's bold is `**`, and `__…__` is left alone rather than reinterpreted.
  let m = markers[k]
  let after = if i + m.len < s.len: s[i + m.len] else: ' '
  let before = if i > 0: s[i - 1] else: ' '
  let leftFlanking =
    not isSpaceByte(after) and
    (not isPunctByte(after) or isSpaceByte(before) or isPunctByte(before))
  if not leftFlanking: return false
  if k == mUnder:
    if before == '_' or after == '_': return false
    if i > 0 and isWordByte(before): return false
  true

proc canClose(s: string; i, k: int): bool =
  ## Whether the delimiter at `i` is allowed to CLOSE a run of mark `k`: the same two
  ## rules, seen from the other side. A `_` closes only when no word byte follows it.
  let m = markers[k]
  let after = if i + m.len < s.len: s[i + m.len] else: ' '
  let before = if i > 0: s[i - 1] else: ' '
  let rightFlanking =
    not isSpaceByte(before) and
    (not isPunctByte(before) or isSpaceByte(after) or isPunctByte(after))
  if not rightFlanking: return false
  if k == mUnder:
    if before == '_' or after == '_': return false
    if i + m.len < s.len and isWordByte(after): return false
  true

proc hasPartner(s: string; i, k: int): bool =
  ## Whether anything after `i` closes this delimiter — searched for with the same
  ## `canClose` rule the scan itself uses, skipping escaped bytes. So an opener is
  ## only a marker when its closer really is there: in `snake_case_name` the second
  ## `_` cannot close (a word byte follows it), so the first `_` has no partner and
  ## stays text. In `snake_case` the second `_` CAN close, so that IS a real italic
  ## run — CommonMark agrees, and only the one *inside* a word is left alone.
  ##
  ## A wrong YES here cannot corrupt the text: the scan would then leave that opener
  ## unclosed, and the second pass puts it back as text.
  let m = markers[k]
  var j = i + m.len
  while j < s.len:
    if s[j] == '\\':
      j += 2
      continue
    if s.continuesWith(m, j) and canClose(s, j, k): return true
    inc j
  false

# --- pass 1: what is a marker, and what is text -------------------------------

type
  TokKind = enum
    rtText             ## literal bytes: kept exactly as the user typed them
    rtOpen             ## a delimiter that opens a run
    rtClose            ## a delimiter that closes a run

  Tok = object
    kind: TokKind
    a, b: int          ## byte range in the MARKUP (so an `rtText` token knows which
                       ## of the user's bytes to copy through)
    flags: int
    color: uint32
    link: string
    mark: int          ## which mark an open/close belongs to
    paired: int        ## a close: the token index of the open it closes

proc parseRich*(markup: string): (string, seq[RichRun]) =
  ## Plain text and its styled runs. `**b**`, `*i*` / `_i_`, `` `code` ``, `~~s~~`,
  ## `[text](url)`; a backslash keeps the next character as it is. Unclosed marks stay text.
  ##
  ## THE RULE: **the text returned is the markup minus exactly the delimiter bytes
  ## that were actually paired.** A byte sequence is a delimiter only if it is allowed
  ## to open or close there (the flanking and word-boundary rules above) and something
  ## really does close it. Anything else — an unpaired opener, a closer with no
  ## opener, a delimiter glued into a word — comes back as the characters the user
  ## typed, so `**b` reads back as `**b` (not `b`) and `snake_case_name` reads back as
  ## itself.
  ##
  ## The scan runs in two passes for that reason: pass 1 records every byte as either
  ## a marker or literal text, pass 2 builds the output from those records. An
  ## unmatched delimiter is text by construction, so it cannot be dropped by a later
  ## change to the scanning rules — there is no "remember to re-insert the character"
  ## step to forget.
  var toks: seq[Tok]
  var openAt: array[nMarks, int]
  for k in 0 ..< nMarks: openAt[k] = -1
  var i = 0
  while i < markup.len:
    let c = markup[i]
    if c == '\\' and i + 1 < markup.len:
      toks.add Tok(kind: rtText, a: i + 1, b: i + 2)
      i += 2
      continue
    if c == '`':
      let e = markup.find('`', i + 1)
      if e > i:
        toks.add Tok(kind: rtText, a: i + 1, b: e, flags: fMono)
        i = e + 1
        continue
    if c == '[':
      let close = markup.find("](", i + 1)
      let e = if close > i: markup.find(')', close + 2) else: -1
      if close > i and e > close:
        toks.add Tok(kind: rtText, a: i + 1, b: close, flags: fUnderline,
                     color: linkColor, link: markup[close + 2 ..< e])
        i = e + 1
        continue
    var matched = false
    for k in 0 ..< nMarks:
      let m = markers[k]
      if not markup.continuesWith(m, i): continue
      if openAt[k] >= 0 and canClose(markup, i, k):
        toks.add Tok(kind: rtClose, a: i, b: i + m.len, mark: k, paired: openAt[k])
        openAt[k] = -1
      elif canOpen(markup, i, k) and hasPartner(markup, i, k):
        openAt[k] = toks.len
        toks.add Tok(kind: rtOpen, a: i, b: i + m.len, mark: k)
      else:
        # Not a delimiter here, so these bytes are the user's text.
        toks.add Tok(kind: rtText, a: i, b: i + m.len)
      i += m.len
      matched = true
      break
    if matched: continue
    toks.add Tok(kind: rtText, a: i, b: i + 1)
    inc i

  # An opener the scan never closed (its closer was swallowed by a code span or a
  # link) goes back to being text, and so does the closer it had already claimed:
  # both byte sequences were the user's, so both come back.
  var asText = newSeq[bool](toks.len)
  for k in 0 ..< nMarks:
    if openAt[k] >= 0: asText[openAt[k]] = true
  for n, t in toks:
    if t.kind == rtClose and asText[t.paired]: asText[n] = true

  # --- pass 2: the text and its runs -----------------------------------------
  var text = ""
  var runs: seq[RichRun]
  var openText: array[nMarks, int]    # where each open mark's run starts, in the text
  var started: array[nMarks, bool]
  for n, t in toks:
    if asText[n] or t.kind == rtText:
      let a = text.len
      text.add markup[t.a ..< t.b]
      if t.flags != 0:
        runs.add RichRun(a: a, b: text.len, flags: t.flags, color: t.color, link: t.link)
    elif t.kind == rtOpen:
      openText[t.mark] = text.len
      started[t.mark] = true
    else:
      if started[t.mark] and text.len > openText[t.mark]:
        runs.add RichRun(a: openText[t.mark], b: text.len, flags: markFlags[t.mark])
      started[t.mark] = false

  # runs must not overlap for the engine: split nested ones into pieces with both flags
  var cuts: seq[int]
  for r in runs: cuts.add r.a; cuts.add r.b
  cuts.add 0; cuts.add text.len
  var pieces: seq[RichRun]
  var sorted = cuts
  sorted.sort()
  for j in 0 ..< sorted.high:
    let a = sorted[j]
    let b = sorted[j + 1]
    if b <= a: continue
    var p = RichRun(a: a, b: b)
    for r in runs:
      if r.a <= a and r.b >= b:
        p.flags = p.flags or r.flags
        if r.color != 0: p.color = r.color
        if r.link.len > 0: p.link = r.link
    if p.flags != 0 or p.color != 0: pieces.add p
  (text, pieces)

proc spansOf*(runs: seq[RichRun]): string =
  ## The engine's form: "start,end,flags,argb,size;…".
  for r in runs:
    result.add $r.a & "," & $r.b & "," & $r.flags & "," & $r.color & ",0;"

proc setRich*(n: Node; markup: string) =
  ## Sets a Text node's text and runs from markup (the DSL's `rich "…"`).
  let (text, runs) = parseRich(markup)
  n.set(pText, text)
  n.set(pSpans, spansOf(runs))
