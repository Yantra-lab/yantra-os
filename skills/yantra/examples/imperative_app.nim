## 02 — the imperative style, for when you need a handle on a node.
## Build: bash tools/build-wasm.sh skills/yantra/examples/imperative_app.nim out.wasm
##
## Same app as hello_app, written by calling the constructors directly. Use this when
## you must reach the node itself (measure it, animate it, attach a handler).
##
## GOTCHA (measured): `createEffect` RETURNS an Effect that must be discarded.

import yantra

proc main() =
  let page = window("Imperative", 420, 260)
  page.color(0x1a, 0x1f, 0x2e)
  page.padding(24)

  var count = newState(0)

  let label = text(page, "Clicks: 0")
  label.fontSize(28)

  discard createEffect(proc () =
    label.setText("Clicks: " & $(count.get)))

  let row = row(page)
  row.spacing(8)

  let add = button(row, "Click me")
  add.width(120)
  add.onClick(proc () = batch(proc () = count.set(count.get + 1)))

  let reset = button(row, "Reset")
  reset.width(120)
  reset.onClick(proc () = batch(proc () = count.set(0)))

when isMainModule:
  main()