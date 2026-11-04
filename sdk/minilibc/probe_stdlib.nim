## PROBE: does a hand-written mini-libc make Nim's *standard library* work on
## freestanding wasm32? This is the question that decides whether app modules can
## be small (minilibc, ~few KB) or need wasi-libc (much larger).
##
## Probe 1 established that pure int arithmetic compiles. The blocker was that the
## first Nim `string` pulls in <string.h>. If minilibc closes that, strings,
## seq, $int, formatting and tables are all back on the table.

import std/math

proc greet*(n: int32): int32 {.exportc: "greet".} =
  ## Build strings in the sandbox and report the length. Returns a length rather
  ## than a pointer because handing memory across the boundary needs a convention
  ## both sides agree on - design work, not compilation work.
  var s = "hello, sandbox #"
  s.add($n)
  s.add(" - built without a libc")
  result = int32(s.len)

proc formatNumber*(v: float64): int32 {.exportc: "formatNumber".} =
  ## Floats are the hard case: this exercises snprintf (via $float), the math
  ## header, and the mini formatter all at once.
  var s = "pi is about " & $v
  result = int32(s.len)

proc sumSquares*(n: int32): int32 {.exportc: "sumSquares".} =
  ## A seq - heap allocation, indexed writes, iteration - to prove the allocator
  ## and generics survive the target.
  var acc = newSeq[int32](0)
  for i in 1 .. n:
    acc.add(i * i)
  var total = 0'i32
  for v in acc:
    total = total + v
  result = total

proc useMath*(x: float64): float64 {.exportc: "useMath".} =
  ## Trig + sqrt + pow through the mini math layer.
  result = sqrt(x) + pow(2.0, 3.0) + sin(0.0) + cos(0.0)
