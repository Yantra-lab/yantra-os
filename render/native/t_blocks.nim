## Q6: examples/shell/blocks.wasm — "# " makes a heading, Enter splits, Ctrl+Z undoes across blocks.
import std/[os, tables]
import engine
import ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "blocks.wasm", 520, 640)
var px = newSeq[uint32](520 * 640)
proc frame() = (e.tick(e.now + 16); e.paintFrame(addr px[0], 520, 640))
proc fields(): seq[int32] =
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_TEXTAREA and n.hasProp(P_BLOCK): result.add int32(i)
frame()
check("the app starts", e.crashed.len == 0, e.crashed)
let n0 = fields().len
check("five blocks", n0 == 5, $n0)
e.focusOn(fields()[^1])
e.typeText("# Hi")
frame(); frame()
let last = fields()[^1]
check("'# ' turned the block into a heading", e.node(last).sProp(P_VALUE) == "Hi" and e.node(last).iProp(P_FONTSIZE) == 28,
      e.node(last).sProp(P_VALUE) & " " & $e.node(last).iProp(P_FONTSIZE))
check("and the caret is still in it", e.focus == last, $e.focus & " vs " & $last)
e.caret = 2; e.anchor = 2
e.key(13)                                               # Enter at the end: a new block after it
frame(); frame()
check("Enter split it into a new block", fields().len == n0 + 1, $fields().len)
check("the caret moved into the new block", e.focus == fields()[^1])
e.typeText("x")
frame()
e.key(int32(ord('z')), 0x0040)                          # Ctrl+Z: the typing goes
frame(); frame()
check("undo takes the typing back", e.node(fields()[^1]).sProp(P_VALUE) == "", e.node(fields()[^1]).sProp(P_VALUE))
e.key(int32(ord('z')), 0x0040)                          # and again: the split goes
frame(); frame()
check("undo again joins the blocks back", fields().len == n0, $fields().len)
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
