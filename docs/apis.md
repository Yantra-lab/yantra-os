# Platform APIs — fetch, storage, files and friends

Status: **proposal for Owner review.** How an app talks to the outside world.

## 1. How every API works (one pattern)

An app is a sandboxed wasm module: it cannot open a socket or a file. Every API is:

```
app (Nim, wasm)          protocol message            host service (native)
fetch(url)        ──►   {op: net.request, id: 7}  ──►  capability check ──► libcurl
reactive value    ◄──   {op: net.done, id: 7, …}  ◄──  worker thread finishes
```

- **Declared, deny-by-default.** The app's manifest lists what it needs; the user approves.
  An undeclared call is a typed error, never a silent success.
- **Asynchronous, never blocking.** Results arrive as **reactive values** (they plug straight
  into the UI and re-render only what uses them) or via `await` for step-by-step code.
- **Typed.** JSON is decoded into your Nim types by code generated at compile time (macros),
  so a missing field is a clear error, not `undefined`.
- **Same API everywhere.** Native host uses libcurl/SQLite; the web target (architecture §9)
  uses the browser's fetch/IndexedDB. App code does not change.
- Each service is a host plugin (architecture §7.3). Adding an API = one service + generated
  bindings; the SDK side never special-cases it.

## 2. Fetch

```nim
type Weather = object
  temp: float
  summary: string

app "Weather":
  needs network("api.example.com")                 # manifest; user approves once

  var city = state "Chennai"
  let w = fetch("https://api.example.com/v1/{city}").json(Weather)   # reactive resource

  column(gap = 2, pad = 4):
    input city
    if w.loading: spinner()
    elif w.failed: text "Couldn't load: {w.error.message}", color = danger
    else: text "{w.value.temp}° — {w.value.summary}", size = xl
```

- Changing `city` re-fetches automatically (like SWR / Solid resources); stale requests are
  cancelled.
- Options: `method`, `headers`, `body = json(obj)`, `timeout`, `retry`, `cache = 5.min`,
  `offline = true` (serve from store when offline).
- Step-by-step form when order matters:

```nim
proc checkout() {.async.} =
  let order = await post("https://api.shop.in/orders", json(cart)).json(Order)
  await payments.checkout(order.id, amount = order.total)   # platform capability
```

## 3. The standard services (all follow §1)

| API | Needs | Backed by |
|---|---|---|
| `fetch`, `post`, `websocket` | `network(domains)` | libcurl, libdatachannel |
| `store` (typed tables, key-value, sync) | `storage` (private per app, on by default) | SQLite |
| `files.open()` / `files.save()` | none — the user picks in a system dialog | host portal |
| `clipboard`, `notify`, `share` | `clipboard`, `notifications` | SDL3 / OS |
| `camera`, `mic`, `screen` | `camera`, `mic`, `screen` | SDL3, FFmpeg |
| `payments.checkout` | `payments` | trusted adapter (UPI/Razorpay) — app never sees credentials |
| `ai.chat`, `ai.image`, `ai.voice` | `ai` | llama.cpp / providers (`docs/ai.md`) |
| `auth.signIn` | `identity` | platform account; app gets a scoped token |
| `realtime.join(room)` | `network` | Yrs CRDT sync (architecture §10) |

`store` example:

```nim
type Note = object
  id: Id
  title, body: string

let notes = store.table(Note)                    # created on first use, schema from the type
notes.add Note(title: "Idea", body: "…")
for n in notes.where(title.contains "Idea"): …   # reactive query: UI updates on change
```

## 4. Tests

Every service ships a **fake** used in tests (`fetch` answers from recorded fixtures,
`payments` in sandbox mode), so apps are testable offline and deterministic.
