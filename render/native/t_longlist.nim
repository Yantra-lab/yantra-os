## Lazy lists (L2) in a real app — examples/shell/longlist.nim: 100 000 rows, but only the
## ones that show exist as nodes; scrolling moves them; the scroll range is the whole list.
import std/[os, tables, times, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let t0 = epochTime()
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "longlist.wasm", 400, 600)
let startMs = (epochTime() - t0) * 1000   # includes compiling the module the first time
var px = newSeq[uint32](400 * 600)
let t2 = epochTime()
e.paintFrame(addr px[0], 400, 600)
let frameMs = (epochTime() - t2) * 1000
proc shownRows(): seq[string] =
  for n in e.s.nodes:
    if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT).startsWith("Row "): result.add n.sProp(P_TEXT)
proc alive(): int =
  for n in e.s.nodes:
    if n.alive: inc result

check("the app starts", e.crashed.len == 0, e.crashed)
let first = shownRows()
check("only about a screenful of 100 000 rows is built", first.len > 10 and first.len < 40, $first.len)
check("starting at the top", first.len > 0 and first[0] == "Row 0", $first)
check("the whole page has few nodes", alive() < 150, $alive())
check("the first frame (layout of what shows, and paint) in under 200 ms", frameMs < 200, $frameMs)

e.pointerMove(200, 300)
let t1 = epochTime()
for _ in 0 ..< 50: e.wheel(-3)          # 50 x 144 px = 7200 px = row 180
e.paintFrame(addr px[0], 400, 600)
let scrollMs = (epochTime() - t1) * 1000
let later = shownRows()
check("scrolling builds the rows that now show", "Row 180" in later and "Row 0" notin later, $later)
check("and still only about a screenful", later.len > 10 and later.len < 40, $later.len)
check("50 wheel steps and a frame in under a second", scrollMs < 1000, $scrollMs)
check("still few nodes (old rows are removed, not hidden)", alive() < 150, $alive())
check("still running", e.crashed.len == 0, e.crashed)
echo "  (start ", int(startMs), " ms, first frame ", int(frameMs), " ms, 50 scroll steps ", int(scrollMs), " ms)"

echo "longlist: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
