## nimcurl — HTTP for Yantra through libcurl (MSYS2 `mingw-w64-x86_64-curl`). Many
## requests at once on the caller's thread: start them, then `poll` each frame.

{.compile: "curl_shim.c".}
{.passL: "-lcurl".}

type
  Fetcher* = object
    h: pointer
  Fetched* = object
    id*: int
    status*: int               ## the HTTP status; 0 if there was no answer (see `error`)
    body*: string
    error*: string

proc yc_new(): pointer {.importc, cdecl.}
proc yc_start(h: pointer; url, protocols: cstring; timeoutMs, maxBytes: clong): cint {.importc, cdecl.}
proc yc_request(h: pointer; meth, url, protocols, headers, body: cstring; bodyLen, timeoutMs, maxBytes: clong): cint {.importc, cdecl.}
proc yc_pending(h: pointer): cint {.importc, cdecl.}
proc yc_poll(h: pointer; status: ptr cint; body: ptr cstring; len: ptr clong; err: cstring; errcap: cint): cint {.importc, cdecl.}
proc yc_free_body(b: cstring) {.importc, cdecl.}
proc yc_wait(h: pointer; ms: cint) {.importc, cdecl.}
proc yc_cancel(h: pointer; id: cint) {.importc, cdecl.}
proc yc_close(h: pointer) {.importc, cdecl.}

proc newFetcher*(): Fetcher = Fetcher(h: yc_new())

proc start*(f: Fetcher; url: string; allowHttp = false; timeoutMs = 30_000; maxBytes = 8 shl 20): int =
  ## Starts a GET; its id (> 0). Only https unless `allowHttp`; redirects are not followed.
  int(yc_start(f.h, url.cstring, (if allowHttp: "http,https" else: "https").cstring,
               clong(timeoutMs), clong(maxBytes)))

proc request*(f: Fetcher; meth, url: string; headers: openArray[string] = []; body = "";
              allowHttp = false; timeoutMs = 30_000; maxBytes = 8 shl 20): int =
  ## Any method with headers ("Name: value") and a body; its id (> 0). Same rules as `start`.
  var hs = ""
  for x in headers:
    if '\n' notin x and '\r' notin x: hs.add x & "\n"
  int(yc_request(f.h, meth.cstring, url.cstring, (if allowHttp: "http,https" else: "https").cstring,
                 hs.cstring, body.cstring, clong(body.len), clong(timeoutMs), clong(maxBytes)))

proc pending*(f: Fetcher): int = int(yc_pending(f.h))
  ## Requests still on their way.

proc poll*(f: Fetcher): seq[Fetched] =
  ## Moves every transfer along and returns the ones that finished.
  while true:
    var st: cint
    var b: cstring
    var n: clong
    var err = newString(256)
    let id = yc_poll(f.h, addr st, addr b, addr n, err.cstring, cint(err.len))
    if id == 0: break
    var body = newString(int(n))
    if n > 0: copyMem(addr body[0], b, int(n))
    yc_free_body(b)
    result.add Fetched(id: int(id), status: int(st), body: body, error: $err.cstring)

proc wait*(f: Fetcher; ms: int) = yc_wait(f.h, cint(ms))
  ## Sleeps until the network has something, or `ms` pass.
proc cancel*(f: Fetcher; id: int) = yc_cancel(f.h, cint(id))
proc close*(f: Fetcher) = yc_close(f.h)

# --- WebSockets ------------------------------------------------------------------------

type
  WebSocket* = object
    h: pointer
  WsEventKind* = enum wsNothing = 0, wsOpen = 1, wsMessage = 2, wsClosed = 3
  WsEvent* = object
    kind*: WsEventKind
    data*: string              ## the message (wsMessage)
    error*: string             ## why it closed ("" if it closed cleanly)

proc yc_ws_open(url, protocols: cstring; timeoutMs, maxBytes: clong): pointer {.importc, cdecl.}
proc yc_ws_poll(h: pointer; data: ptr cstring; len: ptr clong; err: cstring; errcap: cint): cint {.importc, cdecl.}
proc yc_ws_send(h: pointer; data: cstring; len: clong; binary: cint): cint {.importc, cdecl.}
proc yc_ws_state(h: pointer): cint {.importc, cdecl.}
proc yc_ws_close(h: pointer) {.importc, cdecl.}

proc openWebSocket*(url: string; allowPlain = false; timeoutMs = 10_000; maxBytes = 8 shl 20): WebSocket =
  ## Starts connecting (never blocks): wss only unless `allowPlain`; `poll` says when it is open.
  WebSocket(h: yc_ws_open(url.cstring, (if allowPlain: "ws,wss" else: "wss").cstring, clong(timeoutMs), clong(maxBytes)))

proc poll*(w: WebSocket): seq[WsEvent] =
  ## Everything that happened since the last call: opened, whole messages, closed.
  while true:
    var d: cstring
    var n: clong
    var err = newString(256)
    let k = yc_ws_poll(w.h, addr d, addr n, err.cstring, cint(err.len))
    if k == 0: break
    var ev = WsEvent(kind: WsEventKind(k), error: $err.cstring)
    if k == 2:
      ev.data = newString(int(n))
      if n > 0: copyMem(addr ev.data[0], d, int(n))
      yc_free_body(d)
    result.add ev
    if k == 3: break

proc send*(w: WebSocket; data: string; binary = false): bool =
  ## Sends one message; false if it is not open.
  yc_ws_send(w.h, data.cstring, clong(data.len), cint(ord(binary))) == 1

proc isOpen*(w: WebSocket): bool = yc_ws_state(w.h) == 1
proc close*(w: WebSocket) = yc_ws_close(w.h)
