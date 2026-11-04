## Pages and PDF (D1): a deck written in Yantra shows its slides stacked on screen and
## exports one real PDF page per slide — vector shapes, embedded fonts, 16:9 at 13.33 x 7.5 in.
import std/[os, strutils, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

proc pageCount(pdf: string): int =
  ## "/Type /Page" objects, not the "/Type /Pages" tree.
  var i = 0
  while true:
    i = pdf.find("/Type /Page", i)
    if i < 0: break
    if i + 11 >= pdf.len or pdf[i + 11] != 's': inc result
    i += 11

proc mediaBox(pdf: string): string =
  let i = pdf.find("/MediaBox")
  if i < 0: "" else: pdf[i ..< pdf.find(']', i) + 1].splitWhitespace.join(" ")

let wasm = currentSourcePath().parentDir / ".." / ".." / "examples" / "docs" / "pitch.wasm"
let e = start(wasm, 1400, 860)
let ps = e.pages
check("the deck has three slides", ps.len == 3, $ps.len)
let b0 = e.boxes[ps[0]]
let b1 = e.boxes[ps[1]]
check("each slide is 1280x720", b0.w == 1280 and b0.h == 720 and b1.w == 1280, $b0)
check("on screen they stack like pages, top to bottom", b1.y > b0.y + b0.h, $b0.y & " " & $b1.y)

let outp = getTempDir() / "yantra_pitch_test.pdf"
removeFile(outp)
let n = e.exportPdf(outp, "Yantra pitch")
let pdf = readFile(outp)
check("exportPdf writes a PDF", n == 3 and pdf.startsWith("%PDF-") and pdf.strip.endsWith("%%EOF"), $n)
check("with three pages", pdf.pageCount == 3, $pdf.pageCount)
check("each 960x540 points: a standard 16:9 slide (13.33 x 7.5 in)", pdf.mediaBox == "/MediaBox [0 0 960 540]", pdf.mediaBox)
check("with its fonts embedded (the text is text, not pictures)", "/FontFile" in pdf and "/ToUnicode" in pdf)
check("drawing for the file leaves the screen as it was", e.scrollY == 0 and e.pages.len == 3)

# an app without pages exports its window as one page
let one = getTempDir() / "yantra_counter_test.pdf"
let c = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "counter.wasm", 360, 300)
let onePages = c.exportPdf(one)
let oneBox = readFile(one).mediaBox
check("an app without pages is one page the size of its window", onePages == 1 and oneBox == "/MediaBox [0 0 270 225]", oneBox)

echo "pdf: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
