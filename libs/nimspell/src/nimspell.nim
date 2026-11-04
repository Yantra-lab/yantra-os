## nimspell — the system spell checker for text fields (Q9): Windows' ISpellChecker
## (Windows 8+). Elsewhere every word is right and there are no suggestions.
import std/strutils

{.compile: "spell_shim.c".}
when defined(windows): {.passL: "-lole32".}

proc ysp_open(lang: cstring): cint {.importc, cdecl.}
proc ysp_check(s: cstring; len: cint; outp: ptr cint; max: cint): cint {.importc, cdecl.}
proc ysp_suggest(word: cstring; outp: cstring; cap: cint): cint {.importc, cdecl.}
proc ysp_add(word: cstring) {.importc, cdecl.}

var opened = 0          ## 0 not tried, 1 ready, -1 none

proc ready(): bool =
  if opened == 0: opened = if ysp_open("en-US") == 1: 1 else: -1
  opened == 1

proc misspelled*(text: string): seq[(int, int)] =
  ## The misspelled words of `text` as (start, end) byte ranges.
  if text.len == 0 or not ready(): return
  var buf: array[512, cint]
  let n = ysp_check(text.cstring, cint(text.len), addr buf[0], 256)
  for i in 0 ..< int(n): result.add (int(buf[2 * i]), int(buf[2 * i + 1]))

proc suggestions*(word: string): seq[string] =
  ## Up to 8 corrections for `word`, best first.
  if word.len == 0 or not ready(): return
  var buf = newString(4096)
  let n = ysp_suggest(word.cstring, buf.cstring, 4096)
  if n > 0: result = buf[0 ..< int(n)].split('\n')

proc addWord*(word: string) =
  ## From now on `word` is spelled right (the user's dictionary).
  if ready(): ysp_add(word.cstring)
