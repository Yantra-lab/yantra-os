# 1. Values and types

Vajra is Nimony (Nim 3) with plugins: Nim's types, with literals that look like the thing
they mean, and a few rules that make every program safer. Built unless marked.

## 1.1 Literals that look like the thing (built)

| Kind | Written | Kept as |
|---|---|---|
| colour | `#5B5BF6`, `#fff`, `#00000080` (alpha last) | `Color`; in records, its `#RRGGBB` text |
| date | `2026-10-15` | `Date` |
| time of day | `9:30` | `TimeOfDay`; `launch.at(standup)` is a `Time` |
| span of time | `500ms 45s 30min 2h 3days 2weeks`, `1.5h` | `Duration` |
| length on a screen | `12px` | `Px` |
| angle | `90deg`, `1.5rad`, `0.25turn` | degrees |
| share of the whole | `50%` | a fraction from 0 to 1 |
| money | `₹1_23_456`, `$9.99`, `€3`, `£0.99` | each currency its own type: `₹5 + $5` does not compile |
| distance | `850m`, `2.5km` | for places |
| text with values | `"{t.title} is due {t.due}"` | `string` |

A `#` that is not a colour starts a comment, and `2026 - 10` (with spaces) stays a
subtraction.

## 1.2 Types

- **Nim's types:** integers, floats, `bool`, `char`, `string`, enums, objects, tuples,
  arrays, `seq`, `Table`, `HashSet`, procs, generics, concepts.
- **Maybe-values:** `T?` is a value that may be missing (`NULL` in a record, never a
  sentinel); `x.get(0)`, `x.isSome`, `nothing`.
- **Regular expressions** (`std/rex`): a DFA, so matching is linear in the text and no
  pattern can make it hang; `re"…"` in code, `regex(pattern)` for a pattern a person typed.
- **Places, meanings, trees, ranges, money, time, zones:** §3.
- **Any type can be a field** of a record when it has three procs (`sqlType`, `toSql`,
  `fromSql`); the built-in types follow the same rule, so the core has no special cases.

**planned:** units of measure with their dimensions (`5kg + 3m` does not compile;
`60km / 1h` is a speed); `Tensor[T]` for numbers in n dimensions (§7); `Text`, `counter`
and `Position` for sync (§8); `Words` for text in many languages.

## 1.3 What every cell gets (built)

Cells never import. The prelude brings Vajra's vocabulary, the UI words, the engine, and
the everyday standard library: text (`split`, `strip`, `replace`, `parseInt` …), `tables`,
`sets`, `sequtils`, `algorithm`, `math`, regular expressions. It turns on:
- `assumeSync`: one app instance is one thread (its parallel work is §6);
- `lenientFloats`: a `float32` mixed with a float widens to `float64` inside an expression;
- `implicitResult`: `result` starts as `default(T)`;
- `autoclosures` and `canraise`.

## 1.4 Errors (built)

- Every routine may fail, as in Nim 2; nothing is marked. `fail "at most 8 seats"` stops what
  is happening, saying why; `try … except e` catches it.
- A `func` is pure and never fails, so it can run anywhere, in parallel too (§6).
- A failure nothing handles ends a program with its message; in a view, it undoes the
  event and shows the message beneath it.

## 1.5 What a routine may touch: effects and grants

Every routine has effects: what it touches outside itself. The compiler works them out from
the routine's body and everything it calls, as Nim works out its tags, and keeps them in
the routine's interface (§16.11). Nobody has to write them. **planned** (Nim's tags and
`func` are **built**)

| Effect | Meaning | Added by |
|---|---|---|
| `reads R`, `writes R` | reads or changes rows of record `R` (and which fields) | `@yantra/data` |
| `network "host"` | reaches one host | `@yantra/data` (`fetch`) |
| `secret "name"` | uses a secret, only in requests to its host | `@yantra/data` |
| `files` | reads or writes a file it was handed (`Path`) | `@yantra/tools` |
| `model k` | calls a model of kind `k`, one of §12's kinds (`language`, `image`, `video`, `mesh`, `speech`, `music`, …) | `@yantra/media` |
| `spends` | spends money or a budget | `@yantra/money` |
| `gpu` | runs work on the GPU | `@yantra/gpu` |
| `requests` | asks a person, organisation or agent for work (`ask`, §16.12) and pays its price | `@yantra/agents` |
| `clock`, `random` | reads the time, draws a random number | the core |
| `fails` | may stop with an error | the core |

Extensions add effect kinds through their hooks (§0.6), so a new provider brings its own.

```text
func discount(p: Money, rate: Percent): Money =      # no effects: pure, never fails
  p * (100% - rate)

proc share(p: Post) =                                 # effects worked out:
  p.summary = prose("One line about: {p.text}")      #   writes Post.summary, model language
  post("https://x.com/api/post", p)                   #   network "x.com"

proc share(p: Post) =
  uses Post, network "x.com", model language up to ₹2   # a ceiling, checked
  …
```

- A `uses` line inside a routine is a ceiling. If the routine's effects go beyond it, the
  build fails and names the call that goes beyond, through every routine on the way. A
  cell's `uses` lines (`uses network "host"`, **built** for apps) are the same rule.
- `func` means no effects at all: no `fails`, no `clock`, no `random`. So a `func` gives the
  same result for the same arguments, may run in parallel with anything (§6), and its result
  may be kept by the hash of its arguments. Hooks (§0.6) are `func`s.
- **Grants decide at run time** (§0.4). An effect happens only if the person, app or agent
  running it holds a grant for it; a `spends` beyond the grant's limit goes to the giver's
  inbox. An agent is offered only the tools whose effects its grants cover, so it cannot be
  talked into more than it was given.
- **Replay.** `clock`, `random`, `network` and `model` results are kept in the run that made
  them (§25). Replaying a run feeds them back instead of calling again, so a whole
  production, agents included, replays exactly, and any one step can be redone alone.
- **Parallel by effects.** Two calls whose effects touch nothing in common may run at the
  same time (§6): two reads, two fetches to different hosts, two model calls.

## 1.6 The shape of the language

Ten rules every chapter and every extension keeps (decided 2026-10-22). They are what makes
Vajra one language however many hands write it.

1. **One shape for every declaration.** Every top-level word (`record`, `view`, `flow`,
   `scene`, `film`, `service`, `charter`, `derive`, `extension`, `lens`, `test`, `tool`, and
   any an extension adds) is written the same way: the word, a name, its parameters, an
   optional address, then indented lines (fields, lines like `queue`, rules like `can`),
   then its body.

   ```text
   view RoomPage(r: Room) at "/room/{r.id}"
     state open = false
     Text "in {r.name}"
   ```

2. **Three permission words, never mixed.** `can` is who may touch rows (a record's rules);
   `may` is a power given to someone (a grant, a charter's lines); `uses` is what code needs
   (a ceiling on its effects, §1.5).

   ```text
   can read, write: owner              # in a record
   may refund, up to ₹2_000 each       # in a charter or a grant
   uses network "api.x.com"            # in a cell or a routine
   ```

3. **One way to write an address.** `@owner` is a person, an organisation or an agent;
   `@owner/name` a cell; `@owner/app.Root/path` a screen. `y:` comes before an address only
   in a link shared outside Yantra (`y:@asha-store/shop.Home/product/42`).

4. **No async words.** Waiting looks like a call. Waits that do not use each other's results
   overlap by themselves (§6); there is no `async`, `await`, callback or future to write.

5. **One way to fail.** `fail "why"` stops what is happening, saying why. A failure a caller
   is meant to handle has a kind: `fail notFound, "no order 42"`, caught by
   `except notFound`. There are no error codes, and no other kind of error.

6. **Words over symbols.** `not`, `and`, `or`, `in`, `total`, `average`, `upto`, `via`;
   symbols are for arithmetic, comparison and units.

7. **Names.** Types, records, views and other declarations are `PascalCase`; fields, values
   and routines `camelCase`; enum values lowercase; units are suffixes (`12px`, `3days`,
   `₹500`, `2.5km`).

8. **All of Nimony is there.** Any Nimony library compiles into an app; Nim's freedom of form
   stays (method or function call, command syntax, operators, templates, macros). What a
   program may touch is limited by effects and grants, not by the language.

9. **`open` makes a record a document**: any field it was not declared with, at any depth
   (§3.6).

10. **Editions.** A change that would break code waits for an edition (`use vajra 2027.04`),
    at most two a year; code on an older edition keeps building, and the move to a newer one
    is a generated change a person accepts.

## 1.7 Tests

Built: the runtime suite and t_views cover each literal and type above.

Planned (each one is a task):
- `5kg + 3m` fails to compile and names both units; `60km / 1h` prints as `60 km/h`; a
  `Tensor[float32]` of 1,000×1,000 adds on the GPU and the CPU to the same values.
- A routine whose effects go beyond its `uses` line fails to build, and the message names the
  call path to the effect.
- A `func` that reads the clock, draws a random number or calls a routine with any effect
  fails to build.
- An agent whose grants do not cover `network "x.com"` is not offered a tool that has it.
- A run with `clock`, `random`, `network` and `model` effects, replayed, gives the same
  result without calling any of them.
- A `spends` over a grant's limit waits in the giver's inbox and runs only once approved.
