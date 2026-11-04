## Chat over a WebSocket (W1) in a real app — examples/shell/chat.nim against a server on this
## machine: it connects, a typed message goes out and its echo comes back as a bubble, a POST
## carries a body, and host rules for requests (methods, headers only the host may set).
import std/[os, times, tables, strutils]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire
import ../../libs/nimcurl/tests/localserver

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

# the request rules
let (okPost, post) = parseRequest("POST" & $chr(10) & "https://a.com/x" & $chr(10) & "X-A: 1" & $chr(10) & $chr(10) & "body")
check("a request reads as method, URL, headers and body", okPost and post.meth == "POST" and post.headers == @["X-A: 1"] and post.body == "body")
check("a method we do not send is refused", not parseRequest("CONNECT" & $chr(10) & "https://a.com/")[0])
check("headers only the host sets are refused", not parseRequest("GET" & $chr(10) & "https://a.com/" & $chr(10) & "Host: evil.com")[0])
check("wss and ws follow https and http", netAllowed("a.com", "wss://a.com/s") and not netAllowed("a.com", "ws://a.com/s") and
  netAllowed("127.0.0.1", "ws://127.0.0.1:1/s"))

startServer(18433)
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "chat.wasm", 420, 560)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc bubbles(): seq[string] =
  proc walk(id: int32; outp: var seq[string]) =
    let n = e.node(id)
    if not n.alive: return
    if n.kind == K_TEXT: outp.add n.sProp(P_TEXT)
    for c in n.children: walk(c, outp)
  walk(idOf("log"), result)
var clock = 0.0
proc settle(done: proc (): bool) =
  let t0 = epochTime()
  while epochTime() - t0 < 10 and not done():
    clock += 16
    e.tick(clock)
    sleep(5)

check("it starts connecting", e.crashed.len == 0 and e.node(idOf("status")).sProp(P_TEXT) == "connecting…", e.crashed)
settle(proc (): bool = e.node(idOf("status")).sProp(P_TEXT) == "online")
check("then it is online", e.node(idOf("status")).sProp(P_TEXT) == "online")
check("an open socket keeps the loop polling", e.netActive)
e.focusOn(idOf("box"))
e.typeText("hello")
e.activate(idOf("send"))
check("my message shows at once", bubbles() == @["hello"], $bubbles())
settle(proc (): bool = bubbles().len >= 2)
check("and the echo comes back as a bubble", bubbles() == @["hello", "hello"], $bubbles())
check("the box is empty again", e.node(idOf("box")).sProp(P_VALUE) == "")
for i in 1 .. 20:
  e.focusOn(idOf("box"))
  e.typeText("m" & $i)
  e.activate(idOf("send"))
settle(proc (): bool = bubbles().len >= 42)
var sent, echoed: seq[string]           # all 20 go out before any echo is read
for i in 1 .. 20: sent.add "m" & $i
let all = bubbles()
if all.len == 42: echoed = all[22 .. 41]
check("20 quick messages all come back, in order", all.len == 42 and all[2 .. 21] == sent and echoed == sent, $all)
e.activate(idOf("save"))
settle(proc (): bool = e.node(idOf("saved")).sProp(P_TEXT).len > 0)
check("a POST carries the body", e.node(idOf("saved")).sProp(P_TEXT).startsWith("POST hello;hello;m1;"), e.node(idOf("saved")).sProp(P_TEXT))
check("still running", e.crashed.len == 0, e.crashed)

echo "chat: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
