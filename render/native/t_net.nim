## Network (F1) in a real app — examples/shell/net.nim against a server on this machine:
## answers reach the app's text, a host the window does not list is refused, and the
## rules themselves (host/host.nim netAllowed).
import std/[os, times, tables]
import engine
import ../../host/host, ../../host/tree
import ../../protocol/wire
import ../../libs/nimcurl/tests/localserver

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

# the rules
check("a listed host over https is allowed", netAllowed("api.example.com", "https://api.example.com/v1?q=1"))
check("an unlisted host is refused", not netAllowed("api.example.com", "https://evil.com/"))
check("a lookalike host is refused", not netAllowed("example.com", "https://example.com.evil.com/"))
check("plain http to the internet is refused", not netAllowed("api.example.com", "http://api.example.com/"))
check("plain http to this machine is allowed when listed", netAllowed("127.0.0.1", "http://127.0.0.1:8080/x"))
check("*.host allows its subdomains, not itself", netAllowed("*.example.com", "https://a.b.example.com/") and
      not netAllowed("*.example.com", "https://example.com/") and not netAllowed("*.example.com", "https://badexample.com/"))
check("a bare * allows nothing", not netAllowed("*", "https://anything.com/"))
check("user@host tricks are refused", not netAllowed("good.com", "https://good.com@evil.com/"))
check("hosts compare without case", netAllowed("API.Example.com", "https://api.EXAMPLE.com/"))
check("not a URL: refused", not netAllowed("x.com", "x.com/path") and not netAllowed("x.com", "https://x.com:abc/"))
check("an app with no net list reaches nothing", not netAllowed("", "https://example.com/"))
check("urlHost reads scheme and host, lower case", urlHost("HTTPS://Api.X.com:443/p?q") == ("https", "api.x.com"))
check("urlHost turns down what it cannot trust", urlHost("https://[::1]/")[1] == "" and urlHost("nope")[1] == "")
check("only localhost and 127.0.0.1 are this machine", isLocalHost("localhost") and isLocalHost("127.0.0.1") and not isLocalHost("10.0.0.1"))
putEnv("YANTRA_NET", "off")
check("YANTRA_NET=off refuses everything", not netAllowed("api.example.com", "https://api.example.com/"))
delEnv("YANTRA_NET")

startServer(18432)
let e = start(currentSourcePath().parentDir / ".." / ".." / "examples" / "shell" / "net.wasm", 520, 320)
proc idOf(name: string): int32 =
  for i, n in e.s.nodes:
    if n.alive and n.sProp(P_NAME) == name: return int32(i)
  -1
proc textOf(name: string): string = e.node(idOf(name)).sProp(P_TEXT)

check("the app starts", e.crashed.len == 0, e.crashed)
check("while it waits, it says so", textOf("hello") == "loading…", textOf("hello"))
check("a host it does not list is refused at once", textOf("elsewhere") == "refused", textOf("elsewhere"))
check("its requests are on their way", e.netPending == 2, $e.netPending)

var clock = 0.0
proc settle() =
  let t0 = epochTime()
  while epochTime() - t0 < 10:
    clock += 16
    e.tick(clock)
    if e.netPending == 0: break
    sleep(10)
settle()
check("the answer reaches the text", textOf("hello") == "hi there", textOf("hello"))
check("a 404 is an answer with its status", textOf("missing") == "status 404", textOf("missing"))
check("nothing left pending", e.netPending == 0)

e.activate(idOf("ask"))
check("a click starts a request", e.netPending == 1, $e.netPending)
settle()
check("and its answer lands", textOf("echoed") == "press1", textOf("echoed"))
e.activate(idOf("ask"))
settle()
check("again", textOf("echoed") == "press2", textOf("echoed"))
check("JSON is read into a typed object inside the sandbox, and a bad body is caught", textOf("parsed") == "7C caught", textOf("parsed"))
check("still running", e.crashed.len == 0, e.crashed)

echo "net: ", passed, " passed, ", failed, " failed"
if failed > 0: quit 1
