## Saved state (N1): Notes keeps what you type across runs, in its own folder only, within
## its quota — `persistent(…)` in the app, the host's store underneath.
import std/[os, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let data = getTempDir() / "yantra_store_test"
removeDir(data)
putEnv("YANTRA_DATA", data)
check("apps save under YANTRA_DATA", dataDir() == data)
let notesWasm = currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "notes.wasm"

proc titleOf(e: Engine): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_INPUT and n.sProp(P_PLACEHOLDER) != "Search notes": return int32(i)
  -1

let first = start(notesWasm, 900, 640)
let t = first.titleOf
check("Notes starts with its first note", t >= 0 and first.node(t).sProp(P_VALUE) == "Pitch outline")
first.focusOn(t)
first.key(int32(ord('a')), 0x40)
first.typeText("Saved across runs")
check("what is typed is saved at once", fileExists(data / "notes" / "notes.bin"))

let second = start(notesWasm, 900, 640)
let t2 = second.titleOf
check("a new run of Notes finds it again", t2 >= 0 and second.node(t2).sProp(P_VALUE) == "Saved across runs",
      if t2 >= 0: second.node(t2).sProp(P_VALUE) else: "no title")
var listed = false
for n in second.s.nodes:
  if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == "Saved across runs": listed = true
check("in its list too", listed)

# the store's rules
check("an app reads only its own folder (the counter has no notes)", not storeGet("counter", "notes")[0])
check("keys cannot leave the folder", not storeSet("notes", "../escape", "x") and not storeSet("notes", "a/b", "x") and
      not validStoreKey(".hidden"))
check("a value over 1 MB is refused", not storeSet("notes", "big", newString(storeMaxValue + 1)))
var filled = 0
while storeSet("hog", "part" & $filled, newString(storeMaxValue)): inc filled
check("an app cannot fill the disk: 16 MB in all", filled >= 15 and filled <= 16, $filled)
check("values come back byte for byte", storeSet("notes", "raw", "a\x00b\xffc") and storeGet("notes", "raw") == (true, "a\x00b\xffc"))
removeDir(data)
delEnv("YANTRA_DATA")

echo "store: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
