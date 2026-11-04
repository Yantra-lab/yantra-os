## Native-only AppView fixture. The shipped app is app.nim; this root merely gives
## the acceptance driver a smaller, transformed desktop box containing y:emberdeep.
proc main() =
  let win = window("EMBERDEEP acceptance host", 1000, 700)
  win.setFill(0x05060A)
  let av = make(nkAppView, win)
  av.set(pSource, "y:emberdeep")
  av.width(920)
  av.height(640)
  av.set(pAbsolute, 1'i32)
  av.set(pInsetLeft, 37.0'f32)
  av.set(pInsetTop, 29.0'f32)

proc yantra_main*() {.exportc: "yantra_main".} = main()
