# 6. Concurrency

Work that can run at the same time does, without locks, threads or callbacks in the
program. A pure routine is safe to run in parallel, because it changes nothing outside
itself. The compiler knows which routines are pure, so it splits their work across every
core. The result is always the same as running the work one step at a time.

## 6.1 What Nimony gives, today

These are part of Nimony and **built** there (tests in `third_party/nimony/tests/nimony/threads`):

| Piece | What it does |
|---|---|
| `for i in a \|\| b:` | a parallel `for`, rewritten by a plugin into chunks on a shared pool of workers, joined at the end of the loop. The body may write only `x[i]` at its own index and may not read those outputs back; the compiler checks this, so the loop has no data race (`tparfor`, `tparfor_race`). |
| fork and join by recursion | a `\|\|` inside a `\|\|`: each level runs its parts in parallel, and a waiting worker helps run queued work (`tparfib`; its run is skipped on Windows, so it is proved on Linux only) |
| `.passive` procs | coroutines the compiler makes from ordinary code: asynchronous input and output with no callbacks and no futures; a waiting worker parks instead of blocking |
| `delay(call)` | runs a call later, possibly on another thread; the compiler checks that what it captures may be sent |
| atomics, locks, `io_uring` | for the code underneath |

## 6.2 What Vajra adds

```text
func total(t: Tree): int =
  if t.isLeaf: t.value
  else: total(t.left) + total(t.right)      # both halves are pure: they run in parallel

parallel for i in 0 ..< pixels.len:          # each iteration writes only its own pixel
  lit[i] = pixels[i].lighten(20%)

let (left, right) = both(render(a), render(b))   # two calls at once, then joined

let w = fetch(weatherUrl)                    # neither wait uses the other: they overlap
let shops = Shop.near(at, here, within = 2km)
```

| Word | Meaning | Made from | Status |
|---|---|---|---|
| a pure `func` | may run in parallel with anything | `func` already promises no side effects (**built**) | the promise is **built**; running it in parallel is **planned** |
| automatic splitting | a call of a pure `func` on two independent parts runs both at once, when each part is big enough to pay for it | a plugin that rewrites to `\|\|`, with the size test done at run time (split only work that has already run long enough) | **planned** |
| `parallel for` | the parallel `for`, with Vajra's words | `\|\|` | **planned** |
| `both(a, b)`, `all(xs)` | run calls at once and join | `\|\|` over the calls, as `tparfib` does | **planned** |
| overlapping waits | waits that do not use each other's results run at the same time | `.passive` procs; the compiler sees which values each wait uses | **planned** |
| sending values between threads | a value moves to another thread whole, never shared | Nimony's sendability checks | **planned** |
| parallel by effects | two calls whose effects touch nothing in common run at once: two reads, two fetches to different hosts, two model calls (§1.5) | the effects in each routine's interface | **planned** |

**What stays one step at a time.** An event in a view is one serializable transaction
(**built**): its database statements run in order on one connection. Its waits for the
network, models and files overlap; its database work does not.

**Inside the sandbox.** An app is wasm. Its threads are wasm threads with shared memory
(wasmtime supports them); its GPU work goes through the engine (§7).

## 6.3 The guarantee, and how it is checked

- Pure code run in parallel gives the same result as the same code run one step at a
  time. This is a rule of the language, not of luck.
- A data race is a compile error, never a runtime surprise.
- The checks a task is judged by: the parallel and the sequential result are equal; the
  speed-up on N cores is measured; a race the rules forbid fails to compile.

## 6.4 Tests

Built (Nimony): `tparfor`, `tparfor_race`, `tparfib` (Linux).

Planned (each one is a task):
- `total` of a tree of a million leaves gives the same number with automatic splitting on
  and off; with it on, it runs at least 4 times faster on 8 cores.
- A tiny tree is not split: its run takes no longer than the sequential run.
- `parallel for` that reads `lit[i - 1]` fails to compile, with the race rule in the
  message.
- `both(fetch(a), fetch(b))` takes about as long as the slower fetch, not the sum of both.
- In an event, two queries run in order and two fetches overlap.
- `tparfib` runs, and passes, on Windows.
