## Yantra SDK Core — compile-time `fmt` macro (v2 port, L1).
##
## `fmt"..."` interpolates values into a string literal, parsed entirely at
## compile time. There is NO runtime format-string parsing and NO libc:
## only `std/macros` (compile-time parsing) plus integer math on the
## generated path. Safe under `--os:any` / wasm freestanding.
##
## Supported (spec S-TXT-1 subset, freestanding-safe):
##
##   fmt"hello {name}"          # `$`-style via fmtAtom (ints/strings/bools/chars)
##   fmt"price {p:.2f}"         # fixed-point, rounded half away from zero
##   fmt"n={n:d} h={n:x}/{n:X} o={n:o} b={n:b}"
##   fmt"{{literal}} + {v}"     # `{{` / `}}` are literal braces
##
## Floats NEVER go through `$`/formatFloat (the sandbox C library does not
## format floats — see sdk/ui/paint.nim `f`). `{x}` on a float uses
## `fmtFloatDefault` (up to 6 decimals, trailing zeros trimmed); `{x:.Nf}`
## uses `fmtFixed` with exactly N decimals. Ints use `$` (integer math only).
##
## The pattern MUST be a string literal — a variable is a compile error, so
## user data can never be misread as a format string (S-TXT-2).

import std/macros

# --- integer-math runtime helpers (no strformat, no formatFloat, no libc) ---

proc fmtDigits(v: uint64): string =
  ## Decimal digits of `v`, no grouping.
  if v == 0: return "0"
  var buf: array[20, char]
  var n = 0
  var x = v
  while x > 0:
    buf[n] = char(ord('0') + int(x mod 10))
    x = x div 10
    inc n
  result = newString(n)
  for i in 0 ..< n:
    result[i] = buf[n - 1 - i]

proc fmtUabs(n: int): uint64 {.inline.} =
  if n >= 0: uint64(n)
  else: uint64(-(n + 1)) + 1'u64

proc fmtFixed*(x: float64; decimals: int): string =
  ## Fixed-point, rounded half away from zero, exactly `decimals` digits.
  ## Integer math only: scale -> round -> split.
  let d = if decimals < 0: 0 elif decimals > 9: 9 else: decimals
  let neg = x < 0.0
  let ax = if neg: -x else: x
  var m: uint64 = 1
  for _ in 0 ..< d: m *= 10
  let scaled = uint64(ax * float64(m) + 0.5)
  let ip = scaled div m
  var fp = scaled mod m
  result = (if neg: "-" else: "") & fmtDigits(ip)
  if d > 0:
    result.add('.')
    var divi = m div 10
    while divi > 0:
      result.add(char(ord('0') + int(fp div divi)))
      fp = fp mod divi
      divi = divi div 10

proc fmtFixed*(x: float32; decimals: int): string {.inline.} =
  fmtFixed(float64(x), decimals)

proc fmtFixed*(n: int; decimals: int): string {.inline.} =
  ## Ints with `.Nf` render as `N.00` rather than failing.
  fmtFixed(float64(n), decimals)

proc fmtFloatDefault*(x: float64): string =
  ## Default float rendering for `{x}`: up to 6 decimals, trailing zeros
  ## trimmed (so `2.5` is `"2.5"`, not `"2.500000"`; `3.0` is `"3"`).
  let neg = x < 0.0
  let ax = if neg: -x else: x
  const m: uint64 = 1000000
  let scaled = uint64(ax * 1000000.0 + 0.5)
  let ip = scaled div m
  var fp = scaled mod m
  result = (if neg: "-" else: "") & fmtDigits(ip)
  if fp != 0:
    var digits: array[6, char]
    var divi = m div 10
    var i = 0
    while divi > 0:
      digits[i] = char(ord('0') + int(fp div divi))
      fp = fp mod divi
      divi = divi div 10
      inc i
    var last = 5
    while last > 0 and digits[last] == '0': dec last
    result.add('.')
    for k in 0 .. last: result.add(digits[k])

proc fmtFloatDefault*(x: float32): string {.inline.} =
  fmtFloatDefault(float64(x))

proc fmtHex*(n: int; upper: bool): string =
  ## Hex without `0x`, no sign handling beyond `-` prefix.
  let neg = n < 0
  var v = fmtUabs(n)
  if v == 0: return "0"
  var buf: array[16, char]
  var k = 0
  while v > 0:
    let d = int(v and 0xF'u64)
    let c = if d < 10: ord('0') + d
            elif upper: ord('A') + d - 10
            else: ord('a') + d - 10
    buf[k] = char(c)
    v = v shr 4
    inc k
  result = if neg: "-" else: ""
  for i in countdown(k - 1, 0): result.add(buf[i])

proc fmtOct*(n: int): string =
  let neg = n < 0
  var v = fmtUabs(n)
  if v == 0: return "0"
  var buf: array[22, char]
  var k = 0
  while v > 0:
    buf[k] = char(ord('0') + int(v and 7'u64))
    v = v shr 3
    inc k
  result = if neg: "-" else: ""
  for i in countdown(k - 1, 0): result.add(buf[i])

proc fmtBin*(n: int): string =
  let neg = n < 0
  var v = fmtUabs(n)
  if v == 0: return "0"
  var buf: array[64, char]
  var k = 0
  while v > 0:
    buf[k] = if (v and 1'u64) == 1'u64: '1' else: '0'
    v = v shr 1
    inc k
  result = if neg: "-" else: ""
  for i in countdown(k - 1, 0): result.add(buf[i])

# --- `fmtAtom`: default `{expr}` rendering ---

proc fmtAtom*(s: string): string {.inline.} = s
proc fmtAtom*(n: int): string {.inline.} = $n
proc fmtAtom*(n: int32): string {.inline.} = $n
proc fmtAtom*(n: int64): string {.inline.} = $n
proc fmtAtom*(n: uint32): string {.inline.} = $n
proc fmtAtom*(n: uint64): string {.inline.} = $n
proc fmtAtom*(b: bool): string {.inline.} = $b
proc fmtAtom*(c: char): string {.inline.} = $c
proc fmtAtom*(x: float32): string {.inline.} = fmtFloatDefault(x)
proc fmtAtom*(x: float64): string {.inline.} = fmtFloatDefault(x)
proc fmtAtom*[T](x: T): string {.inline.} = $x

# --- compile-time parser (runs inside the macro only) ---

proc fmtFindClose(pat: string; start: int): int =
  ## Index of the `}` closing the `{` at `start - 1`, or -1.
  var i = start
  while i < pat.len:
    if pat[i] == '}': return i
    inc i
  -1

proc fmtSplitSpec(inner: string; exprPart: var string; specPart: var string): bool =
  ## Splits `expr[:spec]` on the FIRST `:`. Returns true when a spec exists.
  var ci = -1
  for i in 0 ..< inner.len:
    if inner[i] == ':':
      ci = i
      break
  if ci < 0:
    exprPart = inner
    specPart = ""
    return false
  exprPart = ""
  for i in 0 ..< ci: exprPart.add(inner[i])
  specPart = ""
  for i in ci + 1 ..< inner.len: specPart.add(inner[i])
  true

macro fmt*(fmtStr: string{lit}): untyped =
  ## Compile-time string interpolation. Pattern must be a string literal.
  var patNode: NimNode = fmtStr
  if patNode.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
    # `fmt"..."` arrives as CallStrLit: unwrap to the literal.
    if patNode.kind == nnkCallStrLit and patNode.len == 2 and
       patNode[1].kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
      patNode = patNode[1]
    else:
      error("fmt: pattern must be a string literal, e.g. fmt\"{x:.2f}\"", fmtStr)
      return newLit("")
  let pat = patNode.strVal
  var parts: seq[NimNode] = @[]
  var cur = ""
  var i = 0
  var hasInterp = false
  while i < pat.len:
    let ch = pat[i]
    if ch == '{':
      if i + 1 < pat.len and pat[i + 1] == '{':
        cur.add('{')
        i += 2
        continue
      let closeIdx = fmtFindClose(pat, i + 1)
      if closeIdx < 0:
        error("fmt: unmatched '{' — use '{{' for a literal brace", patNode)
        return newLit("")
      if closeIdx == i + 1:
        error("fmt: empty '{}' — give an expression, e.g. {x}", patNode)
        return newLit("")
      var inner = ""
      for k in i + 1 ..< closeIdx: inner.add(pat[k])
      var exprPart = ""
      var specPart = ""
      let hasSpec = fmtSplitSpec(inner, exprPart, specPart)
      if exprPart.len == 0:
        error("fmt: empty expression before ':'", patNode)
        return newLit("")
      let exprNode =
        try: parseExpr(exprPart)
        except: nil
      if exprNode == nil:
        error("fmt: cannot parse expression '" & exprPart & "'", patNode)
        return newLit("")
      if cur.len > 0:
        parts.add(newLit(cur))
        cur = ""
      hasInterp = true
      if not hasSpec:
        parts.add(newCall(ident"fmtAtom", exprNode))
      else:
        if specPart.len >= 2 and specPart[0] == '.' and
           specPart[specPart.len - 1] == 'f':
          var decStr = ""
          for k in 1 ..< specPart.len - 1: decStr.add(specPart[k])
          if decStr.len == 0 or decStr.len > 1:
            error("fmt: bad fixed spec '{" & inner &
              "}' — use .Nf with N = 0..9, e.g. {x:.2f}", patNode)
            return newLit("")
          let dd = ord(decStr[0]) - ord('0')
          if dd < 0 or dd > 9:
            error("fmt: bad fixed spec '{" & inner &
              "}' — use .Nf with N = 0..9, e.g. {x:.2f}", patNode)
            return newLit("")
          parts.add(newCall(ident"fmtFixed", exprNode, newLit(dd)))
        elif specPart == "d" or specPart == "s":
          parts.add(newCall(ident"fmtAtom", exprNode))
        elif specPart == "x":
          parts.add(newCall(ident"fmtHex", exprNode, newLit(false)))
        elif specPart == "X":
          parts.add(newCall(ident"fmtHex", exprNode, newLit(true)))
        elif specPart == "o":
          parts.add(newCall(ident"fmtOct", exprNode))
        elif specPart == "b":
          parts.add(newCall(ident"fmtBin", exprNode))
        else:
          error("fmt: unknown spec '{" & inner &
            "}' — use .Nf, d, s, x, X, o or b", patNode)
          return newLit("")
      i = closeIdx + 1
      continue
    elif ch == '}':
      if i + 1 < pat.len and pat[i + 1] == '}':
        cur.add('}')
        i += 2
        continue
      error("fmt: unmatched '}' — use '}}' for a literal brace", patNode)
      return newLit("")
    else:
      cur.add(ch)
      inc i
  if cur.len > 0:
    parts.add(newLit(cur))
  if not hasInterp:
    return newLit(pat)
  if parts.len == 0:
    return newLit("")
  var combined = parts[0]
  for k in 1 ..< parts.len:
    combined = infix(combined, "&", parts[k])
  combined
