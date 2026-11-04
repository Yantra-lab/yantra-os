## `yantra-pdf app.wasm out.pdf` — any Yantra app to PDF: one page per `page`/`slide`,
## or the whole window as one page. The engine draws it (engine.nim `exportPdf`), so the
## PDF matches the screen, with vector shapes and real text.

import std/os
import engine

when isMainModule:
  if paramCount() < 2:
    echo "usage: yantra-pdf <app.wasm> <out.pdf> [title]"
    quit(2)
  let e = start(paramStr(1), 1400, 900)
  if e.crashed.len > 0:
    echo "the app stopped while starting: ", e.crashed
    quit(1)
  let (w, h) = e.windowSizeHint
  e.resize(float32(w), float32(h))
  let n = e.exportPdf(paramStr(2), (if paramCount() >= 3: paramStr(3) else: ""))
  echo "wrote ", paramStr(2), " (", n, " page", (if n == 1: "" else: "s"), ")"
