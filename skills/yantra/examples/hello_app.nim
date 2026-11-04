## 01 — the program shape, in 20 lines.
## Build: bash tools/build-wasm.sh skills/yantra/examples/hello_app.nim out.wasm
##
## The whole declarative language in one file: a window, a node tree, a piece of
## state, an event, and text that recomputes itself when that state changes.
##
## GOTCHA (measured): `count = count + 1` does NOT work. `count` is a Signal[int];
## the converter unwraps it to an int when read, but there is no `=` overload, so
## the assignment is a type error. Mutate with `+=`, `.set()` or `.update()`.

import yantra

app "Hello", width = 420, height = 260, fill = surface, pad = 24:
  var count = state(0)                       # reactive state

  column(spacing = 12, grow = 1):
    text "Clicks: {count}", fontSize = 28, font = mono

    if count > 0:
      text "{count} is a lot", fontSize = 14, fill = muted

    row(spacing = 8):
      button "Click me":
        count += 1
      button "Reset":
        count.set(0)