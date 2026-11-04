## State machines (S7) in a real app — examples/shell/light.nim on the engine's clock: timed
## steps move it on exactly on time, a click sends an event, the UI follows the state.
import std/[os, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "light.wasm", 320, 360)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc shows(): string = e.node(idOf("state")).sProp(P_TEXT)
proc lamp(): int32 = e.node(idOf("lamp")).iProp(P_COLOR)

e.tick(0)
check("it starts red", shows() == "red" and lamp() == int32(0xE5484D), shows())
e.tick(3999)
check("still red just before 4 s", shows() == "red", shows())
e.tick(4000)
check("green at 4 s, on the dot", shows() == "green" and lamp() == int32(0x30A46C), shows())
e.tick(5000)
e.activate(idOf("cross"))
check("pressing Cross while green: amber", shows() == "amber", shows())
e.tick(6000)
check("amber lasts 1 s: red", shows() == "red", shows())
e.tick(7000)
check("green's own 3 s timer was cancelled by leaving it", shows() == "red", shows())
e.activate(idOf("cross"))
check("Cross does nothing while red", shows() == "red", shows())
e.tick(10000)
check("and red lasts 4 s again", shows() == "green", shows())
check("still running", e.crashed.len == 0, e.crashed)

echo "light: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
