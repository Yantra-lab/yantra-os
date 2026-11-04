## Design tokens: colours, type scale, spacing and number formatting (L1).
##
## Ported from the v2 token spec, adapted to this repo's SDK:
##
## * v2's `Val[T]` (a plain value or a reactive one) is gone. Every reactive
##   slot is a `Signal[T]` from `sdk/core/signals.nim`: read it with `.get()`
##   inside an effect (tracked) or `.peek()` outside one. The `val` converter
##   in signals.nim also unwraps a `Signal[T]` to `T` automatically. The
##   `resolve` / `Signal` overloads below are that adaptation: same call shape
##   as v2, `Signal[T]` where v2 took `Val[T]`.
## * v2's `Fg` palette object is flattened to plain `fg*` consts. A converter
##   from an object type clashes with signals' generic `val` converter, so the
##   palette is `fg` / `fgMuted` / `fgFaint` — plain consts, no converters.
## * `px` / `ms` / `s` return plain `int` wire values (px, ms). The distinct
##   `Px` / `Ms` / `Deg` types live in `sdk/ui/units.nim`; this module stays in
##   `sdk/core` and does not depend on `sdk/ui`.
##
## Colours are `0xRRGGBB` ints (`0xAARRGGBB` where alpha matters), matching
## `docs/spec/style.md` and `sdk/ui/theme.nim`. Defaults follow the Midnight
## theme.
##
## Pure Nim: no `std/strformat`, no libc — safe under `--os:any`.

import signals

# --- semantic colours ---------------------------------------------------------

const
  bg* = 0x0B0B10          ## the window
  bgDeep* = 0x060609      ## behind the window: splash, overscroll
  surface* = 0x16161D     ## cards, rows, inputs
  surfaceHi* = 0x1E1E27   ## hover / raised surface
  surface2* = 0x1E1E27    ## ramp alias of surfaceHi
  surface3* = 0x282833    ## pressed / selected surface
  surfaces* = [surface, surfaceHi, surface2, surface3]  ## the surface ramp
  borderCol* = 0x26262F   ## hairlines and borders

  # v2 `Fg` object flattened: plain consts (see header).
  fg* = 0xF5F5F7          ## primary text
  fgMuted* = 0x8C8C96     ## secondary text
  fgFaint* = 0x5A5A64     ## disabled / placeholder text

  accent* = 0xFFB23E      ## brand / interactive
  accentHi* = 0xFFC966    ## accent hover / highlight
  accentSoft* = 0x2AFFB23E ## accent at low opacity: selection, focus rings

  good* = 0x44D07B        ## success
  goodSoft* = 0x2244D07B
  bad* = 0xFF6B5E         ## danger / error
  badSoft* = 0x22FF6B5E
  warn* = 0xF5A623        ## warning (defaults to amber)
  warnSoft* = 0x22F5A623

  gold* = 0xC9A45C
  cyan* = 0x4CC9E6
  violet* = 0x8B7CF6
  rose* = 0xF65D8B
  emerald* = 0x34D399
  amber* = 0xF5A623
  sky* = 0x5EBDF6
  white* = 0xFFFFFF
  black* = 0x000000
  clear* = 0x00000000     ## transparent

# --- type scale (px) ------------------------------------------------------------

const
  micro* = 10
  caption* = 12
  small* = 13
  body* = 15
  subhead* = 17
  title* = 20
  heading* = 24
  display* = 32
  hero* = 44

# --- reactive unwrap (v2 `Val[T]` -> `Signal[T]`) --------------------------------

proc resolve*[T](s: Signal[T]): T {.inline.} =
  ## Unwraps a token that may be reactive. Plain values pass through untouched
  ## (no call needed); a `Signal[T]` reads with `.get()`, subscribing the
  ## current effect so themed props re-evaluate on change.
  s.get()

proc resolvePeek*[T](s: Signal[T]): T {.inline.} =
  ## Like `resolve` but untracked: for event handlers and one-shot reads.
  s.peek()

# --- spacing --------------------------------------------------------------------

proc toSpacePx*(n: int): int {.inline.} =
  ## The 4px grid: steps 1..12 are `n * 4`, step 13 and up are exact px
  ## (an escape hatch for one-off measures). Zero and below clamp to 0.
  if n <= 0: 0
  elif n <= 12: n * 4
  else: n

proc toSpacePx*(s: Signal[int]): int {.inline.} =
  ## Reactive step: `toSpacePx(step.get)`.
  toSpacePx(s.get())

# --- units (plain wire values) -----------------------------------------------------

proc px*(n: int): int {.inline.} = n
  ## Length in logical pixels. A bare number already means px; this names it.
proc px*(x: float): float {.inline.} = x

proc ms*(n: int): int {.inline.} = n
  ## Duration in milliseconds.
proc ms*(x: float): int {.inline.} = int(x)

proc s*(n: int): int {.inline.} =
  ## Seconds to milliseconds: `1.s == 1000`.
  n * 1000
proc s*(x: float): int {.inline.} =
  int(x * 1000.0)

# --- number formatting (pure Nim: no strformat, no libc) ------------------------------
#
# Grouping only: western groups by 3 (`1,234,567`), Indian groups the last 3
# then by 2 (`12,34,567`). Sign handling: `-` prefixes the whole token
# (`-12,34,567`, `-Rs` style `-INR` below).

proc uabs(n: int): uint64 {.inline.} =
  ## Magnitude of `n`, exact even for `low(int)`.
  if n >= 0: uint64(n)
  else: uint64(-(n + 1)) + 1'u64

proc digitsOf(v: uint64): string =
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

proc groupWestern(digits: string): string =
  ## `digits` grouped by 3 from the right.
  let n = digits.len
  if n <= 3: return digits
  result = ""
  for i in 0 ..< n:
    if i > 0 and (n - i) mod 3 == 0:
      result.add(',')
    result.add(digits[i])

proc groupIndian(digits: string): string =
  ## `digits` grouped Indian-style: last 3, then groups of 2.
  let n = digits.len
  if n <= 3: return digits
  let head = digits[0 ..< n - 3]
  let tail = digits[n - 3 .. n - 1]
  var groupedHead = ""
  let m = head.len
  for i in 0 ..< m:
    if i > 0 and (m - i) mod 2 == 0:
      groupedHead.add(',')
    groupedHead.add(head[i])
  groupedHead & "," & tail

proc formatWesternInt*(n: int): string =
  ## `1234567` -> `"1,234,567"`.
  let neg = n < 0
  let g = groupWestern(digitsOf(uabs(n)))
  if neg: "-" & g else: g

proc formatWesternInt*(s: Signal[int]): string =
  formatWesternInt(s.get())

proc formatIndianInt*(n: int): string =
  ## `1234567` -> `"12,34,567"`.
  let neg = n < 0
  let g = groupIndian(digitsOf(uabs(n)))
  if neg: "-" & g else: g

proc formatIndianInt*(s: Signal[int]): string =
  formatIndianInt(s.get())

proc formatFixed(x: float; decimals: int): string =
  ## Fixed-point, rounded half away from zero. Internal helper for `inr`,
  ## `usd` and `pct` float overloads.
  let d = max(decimals, 0)
  let neg = x < 0.0
  let ax = if neg: -x else: x
  var m: uint64 = 1
  for i in 0 ..< d: m *= 10
  let scaled = uint64(ax * float(m) + 0.5)
  let ip = scaled div m
  var fp = scaled mod m
  result = (if neg: "-" else: "") & digitsOf(ip)
  if d > 0:
    result.add('.')
    var divi = m div 10
    while divi > 0:
      result.add(char(ord('0') + int(fp div divi)))
      fp = fp mod divi
      divi = divi div 10

proc twoDigits(c: int): string =
  result = newString(2)
  result[0] = char(ord('0') + c div 10)
  result[1] = char(ord('0') + c mod 10)

const rupee = "₹"

proc inr*(n: int): string =
  ## Whole rupees, Indian grouping: `1234567` -> `"₹12,34,567"`.
  let neg = n < 0
  let g = groupIndian(digitsOf(uabs(n)))
  (if neg: "-" & rupee else: rupee) & g

proc inr*(x: float): string =
  ## Rupees with paise: `1234.5` -> `"₹1,234.50"`.
  let neg = x < 0.0
  let ax = if neg: -x else: x
  let totalPaise = uint64(ax * 100.0 + 0.5)
  let g = groupIndian(digitsOf(totalPaise div 100))
  (if neg: "-" & rupee else: rupee) & g & "." & twoDigits(int(totalPaise mod 100))

proc inr*(s: Signal[int]): string =
  inr(s.get())

proc inr*(s: Signal[float]): string =
  inr(s.get())

proc usd*(n: int): string =
  ## Whole dollars, western grouping: `1234567` -> `"$1,234,567"`.
  let neg = n < 0
  let g = groupWestern(digitsOf(uabs(n)))
  (if neg: "-$" else: "$") & g

proc usd*(x: float): string =
  ## Dollars with cents: `1234.5` -> `"$1,234.50"`.
  let neg = x < 0.0
  let ax = if neg: -x else: x
  let totalCents = uint64(ax * 100.0 + 0.5)
  let g = groupWestern(digitsOf(totalCents div 100))
  (if neg: "-$" else: "$") & g & "." & twoDigits(int(totalCents mod 100))

proc usd*(s: Signal[int]): string =
  usd(s.get())

proc usd*(s: Signal[float]): string =
  usd(s.get())

proc pct*(x: float; decimals: int = 1): string =
  ## Percent with `decimals` digits: `12.34` -> `"12.3%"`.
  formatFixed(x, decimals) & "%"

proc pct*(n: int): string =
  ## Whole percent: `12` -> `"12%"`.
  formatWesternInt(n) & "%"

proc pct*(s: Signal[float]; decimals: int = 1): string =
  pct(s.get(), decimals)

proc pct*(s: Signal[int]): string =
  pct(s.get())
