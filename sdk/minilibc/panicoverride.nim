## Required by Nim's --os:standalone: the freestanding target has no libc, so the
## compiler demands you supply these two hooks yourself. This is the empirical
## answer to "is Nim->wasm a supported first-class target?" - it compiles, but YOU
## are the runtime. That is precisely the shape an embedded app sandbox needs, and
## precisely why it is not a "free" target.

proc panic(msg: string) {.nimcall.} =
  ## Host-side trap. In a real Yantra app module this would call the host's
  ## `yantra_panic` import so the engine can attribute the fault to this module.
  discard msg

proc rawoutput(msg: string) {.nimcall.} =
  ## stderr equivalent. No filesystem, no console: drop it, or forward to the host.
  discard msg
