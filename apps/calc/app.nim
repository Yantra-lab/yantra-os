record Entry
  expression: string
  result: string
  made: Time = now
  owner: User = me
  can read, write: owner

let bg = #0B0A10
let panel = #15121C
let keyFace = #1D1A26
let actionFace = #2A2536
let ink = #F4EFE6
let muted = #9A93AB
let faint = #888199
let accent = #6C5CE7
let amber = #F0A868
let mono = "DejaVu Sans Mono"

# The type-and-spacing standard this app obeys. Every number is measured, not
# chosen: see .board/qs/type/AUDIT.md §6. The three contrast levels are checked
# against the panel (#15121C) — the darkest surface this app puts text on:
#   ink   16.15:1   muted 6.29:1   faint 4.97:1     (all >= the 4.5 body floor)
# `faint` used to be #4C4659, which measured 2.05:1 — the worst pair in the tree.
const
  tMicro = Px(11) ## the legibility floor: x-height 0.500*S >= 5.5 px at 1x
  tBody = Px(13)  ## body copy
  tHero = Px(48)  ## the single display number
  lhBody = 1.35     ## unset gives 1.154 for this app's mono face — under 1.2
  lhOne = 1.0       ## a single number in a fixed-height panel: the only use of 1.0


let keypad = [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"],
              ["1", "2", "3", "+"], ["0", ".", "⌫", "="]]

proc isOperator(k: string): bool = k in ["÷", "×", "−", "+"]

proc tone(k: string): Color =
  ## The face of a key: a digit is quiet, an operator speaks, `=` is the one warm note.
  if k == "=": amber
  elif isOperator(k): accent
  elif k in ["C", "±", "%", "⌫"]: actionFace
  else: keyFace

proc toFloat(s: string): float =
  ## A decimal read the way a person types it: no parseFloat in this vocabulary.
  var t = s
  var neg = false
  if t.len > 0 and t[0] == '-':
    neg = true
    t = t[1 .. ^1]
  let parts = t.split('.')
  var v = float(parseInt(parts[0]))
  if parts.len > 1 and parts[1].len > 0:
    v = v + float(parseInt(parts[1])) / pow(10.0, float(parts[1].len))
  if neg: -v else: v

proc fmt(x: float): string =
  ## A result as a calculator writes it: no trailing zeros, no exponent.
  var v = x
  var sign = ""
  if v < 0.0:
    sign = "-"
    v = -v
  if v != v: return "error"
  if v >= 1e9: return sign & $int64(v)
  let scaled = int64(v * 1_000_000.0 + 0.5)
  let whole = scaled div 1_000_000'i64
  var frac = scaled mod 1_000_000'i64
  result = sign & $whole
  if frac > 0:
    var f = $frac
    while f.len < 6: f = "0" & f
    while f.len > 0 and f[^1] == '0': f.setLen(f.len - 1)
    result = result & "." & f

proc evaluate(ts: seq[string]): float =
  ## A whole expression, precedence and all: `×` and `÷` bind before `+` and `−`,
  ## and each runs left to right among its own rank.
  var vals: seq[float] = @[]
  var plus: seq[string] = @[]
  var i = 0
  var sign = "+"
  while i < ts.len:
    var v = toFloat(ts[i])
    inc i
    while i < ts.len and (ts[i] == "×" or ts[i] == "÷"):
      let op = ts[i]
      inc i
      if i < ts.len:
        let b = toFloat(ts[i])
        inc i
        if op == "×": v = v * b
        elif b == 0.0: fail "cannot divide by zero"
        else: v = v / b
    vals.add v
    if vals.len > 1: plus.add sign
    if i < ts.len:
      sign = ts[i]
      inc i
  result = if vals.len > 0: vals[0] else: 0.0
  for j in 1 ..< vals.len:
    if plus[j - 1] == "+": result = result + vals[j]
    else: result = result - vals[j]

view Calc
  state entry = ""
  state tokens: seq[string] = @[]
  state shown = ""
  state note = ""
  state pending = false
  state done = false
  proc press(k: string) {.closure.} =
    ## Every tap and every keystroke lands here: one typed path, no second copy.
    note = ""
    if k == "C":
      entry = ""
      tokens.setLen(0)
      shown = ""
      pending = false
      done = false
    elif k == "⌫":
      if entry.len > 0: entry.setLen(entry.len - 1)
      done = false
    elif k == "±":
      if entry.len > 0:
        entry = if entry[0] == '-': entry[1 .. ^1] else: "-" & entry
      done = false
    elif k == "%":
      if entry.len > 0:
        entry = fmt(toFloat(entry) / 100.0)
        pending = false
        done = false
    elif k == "=":
      var work: seq[string] = @[]
      for t in tokens: work.add t
      if entry.len > 0 and not pending: work.add entry
      while work.len > 0 and isOperator(work[^1]): work.setLen(work.len - 1)
      if work.len > 0:
        let text = work.join(" ")
        var value = 0.0
        try:
          value = evaluate(work)
        except e:
          note = e.msg        # a division by zero: the tap is undone, the view says why
        if note.len > 0:
          entry = "0"
          shown = ""
        else:
          entry = fmt(value)
          shown = text
          # `result` is a field name the record plugin cannot create by (Nimony's implicit
          # `result` shadows it), so the row is made, then the answer written into it.
          let row = Entry.create(expression = text, result = "")
          row.update(result = entry)
        tokens.setLen(0)
        pending = false
        done = true
    elif isOperator(k):
      if done:
        done = false
        shown = ""
      if entry.len > 0 and not pending: tokens.add entry
      if tokens.len == 0: tokens.add "0"
      if isOperator(tokens[tokens.len - 1]): tokens[tokens.len - 1] = k
      else: tokens.add k
      pending = true
    else:
      if done or pending:
        entry = ""
        pending = false
        done = false
        shown = ""
      if k == ".":
        if '.' notin entry:
          entry = (if entry.len == 0 or entry == "-": "0." else: entry & ".")
      elif entry == "0": entry = k
      else: entry = entry & k
  on key:
    let c = lastKey().code
    var k = ""
    if c >= 48 and c <= 57: k = $char(c)
    elif c == 46: k = "."
    elif c == 43: k = "+"
    elif c == 45: k = "−"
    elif c == 42 or c == 120: k = "×"
    elif c == 47: k = "÷"
    elif c == 37: k = "%"
    elif c == 61 or c == keyEnter: k = "="
    elif c == keyBackspace: k = "⌫"
    elif c == keyEscape or c == 99: k = "C"
    if k.len > 0:
      press(k)
      handled()
  let small = if note.len > 0: note elif shown.len > 0: shown & " =" elif tokens.len > 0: tokens.join(" ") else: " "
  let big = if entry.len > 0: entry else: "0"
  Column(gap = 12px, pad = 20px, fill = bg, grow = 1, height = 640px):   # the 420x640 window
    Row(alignItems = 1):
      Text "Calculator", size = tBody, weight = 600, color = muted, lineHeight = lhBody
      Text "SUTRA", size = tMicro, weight = 700, color = faint, grow = 1, align = 2, lineHeight = lhBody
    Panel(gap = 4px, pad = 16px, fill = panel, radius = 20px, border = 1px, borderColor = #221E2C):
      Text small, size = tBody, weight = 500, color = (if note.len > 0: amber else: muted),
           font = mono, align = 2, maxLines = 1, lineHeight = lhBody
      Text big, size = (if big.len > 14: Px(32) elif big.len > 11: Px(40) else: tHero), weight = 600,
                color = ink, font = mono, align = 2, maxLines = 1, lineHeight = lhOne
    Panel(gap = 8px, pad = 16px, fill = panel, radius = 16px, border = 1px, borderColor = #221E2C, clip = true):
      Row:
        Text "TAPE", size = tMicro, weight = 700, color = muted, lineHeight = lhBody
        Text "last 3, kept as records", size = tMicro, color = faint, grow = 1, align = 2, lineHeight = lhBody
      for e in Entry.sort(made.desc).take(3):
        Row(gap = 8px, justify = 2):
          Text e.expression, size = tBody, color = muted, font = mono, maxLines = 1, lineHeight = lhBody
          Text "=", size = tBody, color = faint, font = mono, lineHeight = lhBody
          Text e.result, size = tBody, weight = 600, color = ink, font = mono, lineHeight = lhBody
      if Entry.count == 0:
        Text "nothing yet — press =", size = tBody, color = faint, font = mono, lineHeight = lhBody
    Column(grow = 1, gap = 12px):
      for row in keypad:
        Row(grow = 1, gap = 12px, alignItems = 3):
          for k in row:
            Button k, grow = 1, size = 22px, weight = 600, radius = 16px, padTop = 16px,
                   fill = tone(k), color = (if k == "=": #17110A else: ink):
              on tap: press(k)
