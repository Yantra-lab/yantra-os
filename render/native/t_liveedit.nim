## Live edits (roadmap §5): typed changes a model (or a tool) sends to a running app,
## shown at once, written into the source, rebuilt and hot-reloaded with state kept.
import std/[os, strutils, tables]
import engine, devwatch, liveedit
import ../../host/host, ../../host/tree
import ../../protocol/wire

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

# --- the source editor, on text ------------------------------------------------------
const src = """app("X"):
  column(gap = 8):
    text "Hello, world: hi", size = 20, color = muted
    panel(width = 3,
          height = 4):
      text "inner"
    button "Go":
      onClick: discard
    text "tail"
"""
let a1 = setArg(src, 3, 4, "size", "80")[0]
check("set replaces a prop in a command-style call", "text \"Hello, world: hi\", size = 80, color = muted" in a1)
let a2 = setArg(src, 3, 4, "weight", "700")[0]
let added = "color = muted, weight = 700\n" in a2
check("set adds a prop that was not there (commas and colons in strings are not arguments)", added, a2.splitLines[2])
let a3 = setArg(src, 4, 9, "fill", "accent")[0]
check("set adds inside a multi-line call's parentheses", "height = 4, fill = accent):" in a3, a3.splitLines[4])
let a4 = setArg(src, 4, 9, "height", "9")[0]
check("set replaces on a continuation line", "          height = 9):" in a4)
let a5 = setArg(src, 7, 4, "fill", "surface")[0]
check("set before a block's colon", "button \"Go\", fill = surface:" in a5, a5.splitLines[6])
let ins = insertAfter(src, 4, 9, "text \"new\"")
let placed = ins.splitLines[5] == "      text \"inner\"" and ins.splitLines[6] == "    text \"new\""
check("insert goes after the node's whole block, at its indentation", placed, ins.splitLines[6])
let rem = removeStmt(src, 7, 4)
check("remove takes the node and its block", "button" notin rem and "onClick" notin rem and "text \"tail\"" in rem)
check("edits parse", parseEdit("set @headline.size = 80")[0].prop == "size" and
      parseEdit("insert after @a: text \"x: y\"")[0].code == "text \"x: y\"" and
      parseEdit("remove @b")[0].kind == ekRemove and parseEdit("paint it red")[1].len > 0)

# --- a running app -------------------------------------------------------------------
let dir = currentSourcePath().parentDir / "build" / "edit"
let appSrc = dir / "counter.nim"
let e = start(dir / "counter.wasm", 360, 300)
let w = newWatcher(dir)
var clock = 0.0
proc findText(t: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_TEXT and n.sProp(P_TEXT) == t: return int32(i)
  -1
proc clickButton(label: string) =
  clock += 1000; e.tick(clock); e.ensureLayout()
  for i, n in e.s.nodes:
    if n.alive and n.kind == K_BUTTON and n.sProp(P_TEXT) == label:
      let b = e.boxes[int32(i)]
      e.pointerMove(b.x + 4, b.y + 4); e.pointerDown(b.x + 4, b.y + 4); e.pointerUp(b.x + 4, b.y + 4)
proc waitReload(n: int): bool =
  for _ in 0 ..< 240:
    discard w.poll(e)
    if e.reloads >= n or w.failed > 0: break
    sleep(500)
  e.ensureLayout()
  e.reloads >= n
proc countNode(): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == "count": return int32(i)
  -1

clickButton("Click me"); clickButton("Click me")
check("the app runs, named nodes and all", findText("2") >= 0 and countNode() >= 0)

let r1 = e.applyEdits("set @count.size = 40")
check("an edit is accepted", r1.ok and r1.live == 1, r1.error)
check("and shows at once, before any rebuild", e.node(countNode()).iProp(P_FONTSIZE) == 40)
check("and is written into the source", "text @count \"{clicks}\", size = 40," in readFile(appSrc))
check("the rebuild swaps in with the count kept", waitReload(1) and findText("2") >= 0 and
      e.node(countNode()).iProp(P_FONTSIZE) == 40, e.devNote)

let before = readFile(appSrc)
let bad = e.applyEdits("set @count.sizee = 3")
check("a misspelt prop is refused with a suggestion", not bad.ok and "did you mean 'size'" in bad.error, bad.error)
let nobody = e.applyEdits("set @nobody.size = 3")
check("an unknown target is refused", not nobody.ok and "@nobody" in nobody.error)
let mixed = e.applyEdits("set @count.color = accent\nset @count.nonsense = 1")
check("a batch with one bad edit changes nothing", not mixed.ok and readFile(appSrc) == before)

let r2 = e.applyEdits("insert after @count: text @hello \"Hello from a model\", size = 18")
check("an insert is accepted", r2.ok, r2.error)
check("and after the rebuild the new node is there, count kept", waitReload(2) and findText("Hello from a model") >= 0 and
      findText("2") >= 0, e.devNote)
let r3 = e.applyEdits("remove @hello")
check("a remove is accepted", r3.ok, r3.error)
check("and after the rebuild it is gone", waitReload(3) and findText("Hello from a model") < 0)

# the inbox: how a model reaches a running app (`yantra edit`, or any tool that writes a file)
createDir(dir / ".yantra")
writeFile(editsInbox(dir), "set @count.size = 52\n")
let took = w.pollEdits(e)
check("edits dropped in the app's inbox are taken and shown at once", took and e.node(countNode()).iProp(P_FONTSIZE) == 52)
check("and answered", readFile(editsResult(dir)).startsWith("ok 1 shown at once"), readFile(editsResult(dir)))
writeFile(editsInbox(dir), "set @count.bogus = 1\n")
discard w.pollEdits(e)
let answered = readFile(editsResult(dir)).startsWith("error:") and "bogus" in e.devNote
check("a refused edit is answered with the reason, and shown over the app", answered, readFile(editsResult(dir)))
check("the inbox is emptied once read", readFile(editsInbox(dir)).len == 0)

# the pieces, used directly
let (args, argEnd, paren) = callArgs(src, 4, 9)
let foundArgs = args.len == 2 and paren and src[argEnd] == ')'
check("callArgs finds a multi-line call's two arguments and its closing parenthesis", foundArgs, $args.len)
let one = e.applyEdit(Edit(kind: ekSet, target: "@count", prop: "weight", value: "300"))
check("applyEdit makes one checked edit", one.ok and "weight = 300" in readFile(appSrc), one.error)

echo "live edits: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
