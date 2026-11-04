## Network (F1): `fetch(url)` is a signal that holds the answer when it comes. The host
## only lets an app reach the hosts its window lists — `app("Weather", net = "api.example.com")`
## — over https (plain http only to this machine), and never follows redirects
## (host/host.nim `netAllowed`; tested in render/native/t_net.nim).

import std/json
export JsonParsingError
import runtime, signals

type Fetched* = object
  loading*: bool              ## still on its way
  status*: int                ## the HTTP status (200, 404, …); 0 if it failed
  body*: string               ## the answer's bytes
  error*: string              ## why it failed or was refused ("" if it did not)

proc ok*(f: Fetched): bool = f.status >= 200 and f.status < 300
  ## A 2xx answer.

when sizeof(pointer) == 4:                # wasm: hand the host (pointer, length) pairs
  proc ptrOf(s: string): int32 = (if s.len == 0: 0'i32 else: cast[int32](cast[uint](unsafeAddr s[0])))

  proc startFetch(url: string; handler: int32): int32 = yFetch(ptrOf(url), int32(url.len), handler)

  proc startRequest(req: string; handler: int32): int32 = yFetchEx(ptrOf(req), int32(req.len), handler)
  proc wsOpen(url: string; handler: int32): int32 = yWsOpen(ptrOf(url), int32(url.len), handler)
  proc wsSend(id: int32; data: string): bool = yWsSend(id, ptrOf(data), int32(data.len)) == 1
  proc wsClose(id: int32) = yWsClose(id)
  proc wsEvent(id: int32): (int32, string) =
    let n = yWsData(id, 0, 0)
    var d = newString(max(n, 0))
    if n > 0: discard yWsData(id, ptrOf(d), n)
    (yWsEvent(id), d)

  proc fetchResult(id: int32): (int32, string) =
    let n = yFetchBody(id, 0, 0)
    var body = newString(max(n, 0))
    if n > 0: discard yFetchBody(id, ptrOf(body), n)
    (yFetchStatus(id), body)
else:                                     # native builds (tests) have no host: a test sets these
  var nativeFetchStart*: proc (url: string; handler: int32): int32
  var nativeFetchResult*: proc (id: int32): (int32, string)

  proc startFetch(url: string; handler: int32): int32 =
    if nativeFetchStart == nil: 0'i32 else: nativeFetchStart(url, handler)

  proc fetchResult(id: int32): (int32, string) =
    if nativeFetchResult == nil: (-1'i32, "") else: nativeFetchResult(id)

  var nativeRequest*: proc (req: string; handler: int32): int32
  var nativeWsOpen*: proc (url: string; handler: int32): int32
  var nativeWsSend*: proc (id: int32; data: string): bool
  var nativeWsClose*: proc (id: int32)
  var nativeWsEvent*: proc (id: int32): (int32, string)
  proc startRequest(req: string; handler: int32): int32 =
    if nativeRequest == nil: 0'i32 else: nativeRequest(req, handler)
  proc wsOpen(url: string; handler: int32): int32 = (if nativeWsOpen == nil: 0'i32 else: nativeWsOpen(url, handler))
  proc wsSend(id: int32; data: string): bool = nativeWsSend != nil and nativeWsSend(id, data)
  proc wsClose(id: int32) = (if nativeWsClose != nil: nativeWsClose(id))
  proc wsEvent(id: int32): (int32, string) = (if nativeWsEvent == nil: (0'i32, "") else: nativeWsEvent(id))

proc encodeRequest*(meth, url: string; headers: openArray[string]; body: string): string =
  ## The form the host reads (host.nim parseRequest): method, URL, header lines, a blank
  ## line, then the body, split by line feeds.
  let lf = $chr(10)
  result = meth & lf & url & lf
  for h in headers:
    if chr(10) notin h and chr(13) notin h: result.add h & lf
  result.add lf & body

proc fetchThen*(url: string; done: proc (f: Fetched); meth = "GET"; body = "";
                headers: openArray[string] = []): bool =
  ## Starts a request and calls `done` with the answer. False (and `done` is never called)
  ## if the host refused it: not in the `net` list, not https, or too many at once.
  ## `meth`: GET, POST, PUT, PATCH, DELETE or HEAD; `headers`: "Name: value".
  var id = new int32
  let h = onHandler(proc () =
    let (st, body) = fetchResult(id[])
    if st > 0: done(Fetched(status: int(st), body: body))
    else: done(Fetched(error: (if body.len > 0: body else: "no answer"))))
  id[] = if meth == "GET" and body.len == 0 and headers.len == 0: startFetch(url, h)
          else: startRequest(encodeRequest(meth, url, headers, body), h)
  id[] != 0

proc fetch*(url: string; meth = "GET"; body = ""; headers: openArray[string] = []): Signal[Fetched] =
  ## A signal: `loading` until the answer is in, then the answer.
  result = newState(Fetched(loading: true))
  let s = result
  if not fetchThen(url, proc (f: Fetched) = s.set(f), meth, body, headers):
    s.set(Fetched(error: "refused: " & url & " is not in this app's net list (or not https)"))

proc fetchWhen*(url: proc (): string): Signal[Fetched] =
  ## Like `fetch`, but the URL is computed from signals: when they change it fetches again,
  ## `loading` meanwhile, and an answer to an older URL is dropped (S11 `resource`).
  result = newState(Fetched(loading: true))
  let s = result
  var asked = new int                  # which request is the latest
  discard createEffect(proc () =
    let u = url()
    inc asked[]
    let mine = asked[]
    s.set(Fetched(loading: true))      # a write, not a read: the effect does not depend on s
    if not fetchThen(u, proc (f: Fetched) =
        if mine == asked[]: s.set(f)):
      s.set(Fetched(error: "refused: " & u & " is not in this app's net list (or not https)")))

proc json*[T](f: Fetched; t: typedesc[T]): T =
  ## The body read as JSON into a `T` (fields by name; extra fields are ignored). Raises
  ## `JsonParsingError` / `KeyError` if it does not fit: check `ok` first, or catch it.
  to(parseJson(f.body), T)

# --- WebSockets (W1) -------------------------------------------------------------------

type
  SocketState* = enum socketConnecting, socketOpen, socketClosed
  Socket* = ref object
    id: int32
    state*: Signal[SocketState]   ## connecting, then open, then closed
    reason*: string               ## why it closed ("" if it closed cleanly or has not)

proc socket*(url: string; onMessage: proc (m: string)): Socket =
  ## A WebSocket to a host the window lists in `net` (wss; ws only to this machine).
  ## `onMessage` gets each whole message; `send` before it is open is kept and sent, in
  ## order, once it opens. A refused socket is closed at once, with a reason.
  let s = Socket(state: newState(socketConnecting))
  let h = onHandler(proc () =
    let (kind, data) = wsEvent(s.id)
    case kind
    of 1: s.state.set(socketOpen)
    of 2: onMessage(data)
    of 3:
      s.reason = data
      s.state.set(socketClosed)
    else: discard)
  s.id = wsOpen(url, h)
  if s.id == 0:
    s.reason = "refused: " & url & " is not in this app's net list (or not wss)"
    s.state.set(socketClosed)
  s

proc send*(s: Socket; m: string): bool {.discardable.} =
  ## Sends one message (kept until it opens); false once it is closed.
  s.state.peek != socketClosed and wsSend(s.id, m)

proc close*(s: Socket) =
  ## Closes it; its `onMessage` hears nothing more.
  if s.state.peek != socketClosed:
    wsClose(s.id)
    s.state.set(socketClosed)
