# 3. Kinds of data

Every kind of data is a `record`. A line inside it changes how the record is kept and
behaves; the same query words work on all of them (§2). What a key-value store, a
document store, a queue, a ledger, a time-series store and a workflow engine each do
alone, Vajra does with one noun.

## 3.1 What is built

| Kind | Code | Kept as |
|---|---|---|
| documents | a field whose type is a plain object: `home: Address`; queries reach inside, `where(home.city == "Pune")` | `jsonb` |
| places | `at: Point`; `Shop.near(at, here, within = 2km)`, `distance(a, b)` | PostGIS |
| meanings | `meaning: Vector`; `Doc.nearest(meaning, asked)` | pgvector |
| ranges | `during: Slice[Time]`; `unique during per room` refuses overlaps | Postgres ranges |
| trees | `path: TreePath`; `where(path under "mha.police")`, `path.depth` | ltree |
| money | `cost: INR`; each currency its own type | `numeric` |
| time | `Time`, `Date`, `Duration`, `Zone`, `LocalTime` | `timestamptz`, `date`, … |
| enums | `status: Status = todo` | the value's word |
| maybe-values | `note: string?` | `NULL`, never a sentinel |
| sealed | `aadhaar: sealed string` | encrypted with a per-person key |
| shared | `shared` | one table, in the declaring space |
| history | `r.history`, `r.asOf(t)`, `keep history 7 years` | the change log |
| search | `search title` | full-text index |
| files | `Asset`, chunks under SHA-256, read by range | the chunk store |
| rows in and out | `importCsv`, `importJson`, `asCsv`, `asJson` | |

The tests: `host/vajra/tests/run_tests.nim` and `host/atlas/tests/run_tests.nim`.

## 3.2 The lines that change a record

```text
record Session
  user: User
  memory                          # kept in memory, never on disk
  expire after 30min              # gone 30 minutes after its last change

record Job
  queue                           # each row is held by one worker at a time
  tries 5, then failed            # retried, then kept as failed

record Reading
  at: Time
  pulse: int
  series by at                    # windows, gaps filled, old data kept coarser
  keep 1min detail for 30days, then 1h

record Payment
  ledger                          # append-only, each row chained to the one before by its hash

flow Delivery                     # steps that survive a crash and may wait for days
  order: Order
  step pack
  step ship: wait until order.paid
  step remind: after 3days unless order.delivered
```

| Line | What it does | Made from | Status |
|---|---|---|---|
| `memory`, `expire after` | fast, short-lived data: sessions, presence, rate limits | unlogged tables and a sweep in `vajra tick` | **built** (runtime suite) |
| `queue`, `tries` | work handed to one worker at a time, retried, failures kept | `select … for update skip locked` | **built** (runtime suite) |
| `series by`, `keep … detail` | time series: windows, gap filling, coarser old data | partitions and summaries kept current | `series` and gap filling **built** (runtime suite); `keep … detail` **planned** |
| `ledger` | append-only, tamper-evident | a hash chain and refused updates (§20) | **built** (runtime suite) |
| `flow`, `step`, `wait until`, `after` | long work that survives crashes | rows for each flow's state, run by `vajra tick` | **built** (runtime suite, §13.3) |
| `derive` | a record worked out by a rule, kept current, recursive if needed (§4) | views kept current by triggers | **built** for `where` and `group` rules (runtime suite); recursive **planned** |
| `partition by` | very large tables split by a key | Postgres partitions | **planned** |
| `from csv "…"`, `from postgres "…"` | outside data read as a record | foreign tables | **planned** |
| `counter`, `Text`, `Position` | merge rules for sync (§8) | | **planned** |
| `sensitive health` | stricter defaults (§17) | | **planned** |

### Each line, exactly

**`memory`.** The rows live in an unlogged table: fast, lost if the database crashes, never
in the change log, never in history, never synced to a device's disk. It may be combined
with `expire after`. With `ledger` or `keep history` the build fails: `memory rows are not
kept, so <line> cannot apply`.

**`expire after D`.** `D` is written `30s`, `30min`, `2h`, `7days` or `2weeks`. A row goes `D`
after its last change. A query never returns a row past its time, even before the sweep
removes it (a restrictive row policy); `vajra tick` removes it. **built**

**`queue`.** Adds hidden fields: who holds a row and until when, its tries, whether it
failed and why.

```text
let job = Job.take(5min)              # one row nobody holds (or whose hold ran out), or none
job.done()                            # removes it
job.release()                         # puts it back at once
job.fail("printer offline")           # gives it back, counting a try
job.reason; job.tries                 # why its last try failed; how many failed
```

Rows are taken oldest first; a held row is invisible to every other `take`
(`for update skip locked`), so many workers on many machines share one table. `done`,
`release` or `fail` by anyone but the holder fails: `Job 42 is not held by you`. A hold that
runs out counts as a try. **built**. `keep done` (keeping a done row, marked done) and the
holder's handle in the failure: **planned**.

**`tries N, then failed`.** `N` is from 1 to 100. Each `fail` counts one try; at `N`, the
row stops being taken and is kept as failed with its last reason (`Job.failed`, a query).
`job.retry()` by a supervisor puts it back with its tries at zero. Without the line, a row
is tried for ever. **built**

**`series by t`.** `t` is a `Time` field. Queries gain `.series(t, step)` (one row per
step, the record's numbers summarised: `average`, `lowest`, `highest`, `count`, `total`)
and `.fill(previous | zero | none)` for steps with no rows. Made with TimescaleDB on `t`.
**built** without TimescaleDB, on any `Time` field: `Reading.series(at, 1h).average(pulse)`
gives `(step, value)` from the first step with rows to the last, an empty step none
(`date_bin` and `generate_series`, one statement); `.fill(0.0)` puts a value in empty steps,
`.fillPrevious` carries the last value on. `count` per step and TimescaleDB's own storage:
**planned**.

**`keep A detail for P, then B`.** Rows newer than `P` are kept as written; older ones are
replaced by one summary row per `B` (each number's average, lowest, highest and count). A
query that spans both reads both, and the boundary does not show. `A < B`, else the build
fails.

**`ledger`.** Nobody may update or delete a row, owners and the system included: `Payment
is a ledger: its rows never change`. Each row keeps the hash of the row before it and its
own hash over both (SHA-256 over the row, times in UTC; one writer at a time, so the chain
never forks); `Payment.verify()` gives the first broken link, or `none`. The database checks
the whole chain, rows you cannot read included. A mistake is corrected by a new row that
reverses it. **built**

**`derive`.** A record worked out by a rule from others, read-only, current in the same
transaction that changes its sources; it may refer to itself (`repeat`, §2.7).

```text
derive Balance = Payment.group(account).total(amount)
derive Big = Payment.where(amount > 1000)
```

Writing to it fails: `Balance is derived from Payment; change Payment`. **built**: a rule is
`R.where(cond)` (the derived record has R's fields), optionally followed by `group(k)` and
one of `count`, `total(f)`, `average(f)`, `highest(f)`, `lowest(f)` (the derived record has
`k` and that word as fields). It is a view read with the person's own rights
(`security_invoker`), so each person's totals cover only the rows they may read; it is
current by construction, in the same transaction. **planned**: rules that join, recursive
rules (`repeat`), and kept (materialised) results for heavy rules.

**`partition by f`.** By a `Time` field: one partition a month (`monthly`, `daily`,
`yearly` to choose). By an enum or a key: one partition per value, or `into N` by its hash.
Queries do not change; an old partition can be moved to the object store and come back
when read.

**`from csv "p"`, `from postgres "url" table "t"`.** An outside table read as a record:
read-only, its declared fields checked against the outside columns when the app is built,
read again `every D` or when asked (`.refresh()`).

## 3.3 More words for queries

| Word | Example | Status |
|---|---|---|
| any, all or none of the linked rows | `Person.where(any friends(score > 40))` | **built** over a link to many; over the rows that link here, **planned** |
| the latest N per group | `Order.group(customer).latest(3)` | **built** (runtime suite) |
| previous and next, rank, moving average and totals | `Reading.sort(at).over(7days).average(pulse)` | **built** (runtime suite); percentiles **planned** |
| union, intersect, except | `admins.union(editors)` | **built** (runtime suite) |
| create or update by a unique key | `Contact.save(email = e, name = n)` | **built** (runtime suite) |
| pivot, subtotals | `Sale.pivot(region, month).total(amount)` | pivot **built** (runtime suite); subtotals **planned** |
| paging through millions, streaming | `for o in Order.stream: …` | **built** (runtime suite) |
| facets | `Product.facets(category)` | **built** (runtime suite) |
| typo-tolerant search | `search title fuzzy` | **built** (runtime suite) |
| the plan of a query | `Order.where(…).plan` | **built** (runtime suite) |
| only some fields | `for (item, total) in Order.where(paid).pick(item, total)` | **built** (runtime suite) |
| group, total, average, highest, lowest, ranked, running, follow | **built** | |

## 3.4 Rules a record can state

| Rule | Example | Status |
|---|---|---|
| a check, a unique key, no overlaps | `check qty > 0`, `unique title per owner` | **built** |
| allowed changes of a field | `moves todo -> doing -> done` | **built** (runtime suite) |
| what a deleted link does | `customer: Customer on delete remove` (or `keep`, `refuse`) | **built** (runtime suite) |
| a rule across rows | `check total(Allocation.amount) <= budget` | **built** (runtime suite) |
| a link to one of several records | `on: Post or Photo` | **built** (runtime suite) |
| a field fewer people may read | `salary: INR can read owners` (the space's owners; or `owner`, a field) | **built** (runtime suite) |
| a rule checked at the end of the transaction | `check later …` | **built** (runtime suite) |

### Each query word, exactly

- **`any`, `all`, `none`** over a link to many (`friends: seq[Person]`):
  `Person.where(any friends(score > 40))` keeps people with at least one such friend; `all`
  with every one (true for none at all); `none` with none. The condition is on the linked
  record's fields and checked when the program is built; only linked rows the person may
  read count. **built**. Over the rows that link here (`Customer.where(any Order.customer(…))`):
  **planned**.
- **`latest(n, by = t)`** after `group(k)`: the `n` newest rows of each group, by field `t`,
  else by when they were made (ids are in time order). The result is a query of the same
  record and composes with every word. **built**
- **`over`** (a row's window): `sort(…).over(7days)` (the rows up to 7 days before each row;
  the sort is by one time field) or `.over(rows = 5)` (the row and the 4 before), then `average`,
  `total`, `highest`, `lowest`, `rank`, `previous(f)`, `next(f)`: each row with its value,
  in the rows' order, as `(row, value)`; `previous` and `next` are none at the ends. Without a
  `sort` the build fails: `over needs an order: add .sort(…)`. **built**
  `percentile(p)` over a moving window: **planned** (Postgres has no windowed percentile; it
  needs its own plan).
- **`union`, `intersect`, `except`**: queries of the same record give a query of that
  record: its rows in either, in both, or in the first and not the second, each row once.
  Each side keeps its own `sort`, `take` and `skip` (`Person.sort(score).take(2).except(q)`);
  the result is unordered until sorted, and composes like any query. **built**. Over the
  same fields after `map`, and `unionAll` (keeping duplicates): **planned** with `map`.
- **`save(key = v, …)`**: creates the row, or changes the one with that key, in one
  statement (only the fields given change). The key is a `unique` line whose fields are all
  given, or have a default (`unique title per owner`, with `owner: User = me`, needs only
  `title`), else the build fails: `save needs a unique key: email is not unique on Contact`.
  It gives the row. **built**
- **`pivot(rows, columns).total(x)`**: each value of `columns` becomes a field. For an enum
  the fields are typed; for other values they are a `Doc` (§3.6). `.subtotals` adds a total
  row per group. **built**: `for (region, m) in Sale.pivot(region, month).total(amount)`
  gives each region with a `Doc` of the months' totals (`m.jan`; a month with no rows is
  none), also `average`, `highest`, `lowest`, in one statement. Typed fields for an enum and
  `.subtotals`: **planned**.
- **`stream`** (`size = 1000`): rows a page at a time, never all held at once; in id order
  unless sorted, each page found by the last id seen (as fast as the first), or the next
  rows in the query's order within its `take`. Inside an event every page comes from one
  consistent moment: `Order.stream`, `Order.where(…).stream(size = 100)`. **built**
- **`pick(a, b, c)`**: only the fields named (one to three), in the query's order: one field
  gives a list of its values, more give tuples, each typed as its field. **built**
- **`facets(f)`**: each value of `f` with how many rows have it, under the query's other
  filters, values in order: `for (category, n) in Product.where(price < ₹500).facets(category)`.
  **built**
- **`search … fuzzy`** (`search title, body fuzzy`): `where(search("lanch"))` also finds words
  within a typo or two ("launch"), by trigrams over the same text, best matches first;
  without `fuzzy` only the words match. **built**
- **`plan`**: how Postgres will run the query and the rows it expects, as JSON (Postgres's
  own plan). **built**. Where each part runs across backends and machines (§2.6, §2.7):
  **planned** with them.

### Each rule, exactly

- **`moves a -> b -> c`**: the only changes allowed for the enum field holding those words
  (one field may hold them; several `moves` lines add their steps). A new row starts at the
  first word of the first line. Any other change fails: `Task.status may not move from done
  to todo`. Kept by the database (a trigger), so no app and no agent can step around it.
  **built**. `starts at x`: **planned**.
- **`on delete keep | remove | refuse`**, written after the link's type
  (`customer: Customer on delete remove`): when the linked row is deleted, `keep` makes the
  link `none` (the field must be a maybe-link, `Customer? on delete keep`), `remove` deletes
  this row too, `refuse` (also when nothing is said) stops the delete with words that count
  the rows linking to it, naming the row by its first text field: `Client Bo has 2 Bills`.
  **built**
- **A rule across rows** (`check total(Allocation.amount) <= budget, "over the budget"`):
  `total`, `count`, `average`, `highest`, `lowest` over the rows of another record that link
  to this one (it must link once). Checked when every transaction ends that changes this
  row or a row it totals (a deferred trigger on both tables), on the rows as they are then;
  the failure is the line's message. **built**. Naming the values in the failure: **planned**.
- **`on: Post or Photo`**: a link to one of several records; `c.on.isA(Post)` asks which,
  `c.on.asA(Post)` reads it (a `Link[Post]`); a row or a link of either record fits where it
  is given. The database keeps the linked row's id (ids are unique across every record),
  checks that it is one of theirs, and refuses deleting a row this links to (`Post hi has 2
  Comments`). `where(on == p)` compares ids. **built**. `case` over the kinds: **planned**.
- **A field fewer may read** (`salary: INR can read owners`): to anyone else the field is
  `none` in every query and cannot be filtered on; writing it needs both the record's and the
  field's rule. **built**: the field is kept in a table of its own whose row rules are the
  record's and the field's, read through a join, so even a hand-written query cannot reach
  it; in the program it is a maybe-value (`INR?`).
- **`check later …`** (`check later qty > 0, "a job needs at least one"`): checked when the
  transaction ends, on the row as it is then, so a change may break it meanwhile; the
  message is the failure. **built**

## 3.5 Changing a record over time

A new field becomes a new column; nothing is dropped (**built**). `name: string renamed from
title` keeps the rows' data under the new name (**built**). A changed type converts each
row, or the change is refused, saying how many rows do not fit: `Gadget.price cannot become
boolean: 1 of its rows do not fit` (**built**). **planned:**
- splitting a record into two, or joining two, is a migration cell with its tests;
- every migration is a version of the record, so going back is going to the version before.

Indexes are worked out from the code: the Atlas sees every query at compile time and
makes the indexes they need. **built** for the fields a program's `where` and `sort` name
directly (a B-tree index each, made when the app is opened; not for lists, documents or
places, which have their own). **planned**: indexes over several fields, partial and
expression indexes, and dropping those no query uses any more.

## 3.6 Documents: anything a document store does

Some data has no fixed shape: an organisation's settings, a team's pages, a form's answers,
a bot's state, an import from somewhere else. A record with the line `open` keeps every
field it was not declared with, at any depth, in its document. The fields it declares stay
typed and checked; everything else is free.

```text
record Team
  name: string
  org: Org
  open                                    # any other field, any depth
  can read: org.members
  can write: org.admins

let t = Team.create(name = "Design", org = acme,
                    settings = {theme: "dark", tags: ["ui", "brand"]})
t.settings.tags.add "motion"              # changes that one path, nothing else
t.settings.theme = "light"

Team.where(settings.theme == "dark" and "ui" in settings.tags)
for team in Team.where(exists settings.billing):
  case team.settings.billing.plan
  of string as p: echo p
  of none: echo "no plan"
```

What it means:
- An undeclared field's value is a `Doc`: `none`, a boolean, a number, a string, a time, a
  list or an object of `Doc`s. Reading a path that is not there gives `none`, never an
  error. `as T` reads it as a type, `is T` asks, `case` matches its shape.
- A declared field never holds a value of another type.
- A write changes only the paths it names, so two writers on different paths of one
  document never undo each other; across devices, `Doc`s merge path by path (§8).
- `can` rules and every line of §3.2 apply to documents as to any record.

**built** (runtime suite): `open` keeps every undeclared field in the row's `_doc`
(`jsonb`, with a GIN index). In the program, `t.settings.theme` reads a path (a `Doc`:
`$d`, `d.str`, `d.num`, `d.len`, `d.isNone`, `"ui" in d`, `d == "dark"`; a missing path is
none); `t.settings.theme = "light"` and `t.settings = doc("{…}")` write that path and
nothing else, making the objects on the way; `t.settings.tags.add "motion"` adds to the
list there (`addOnce` unless it holds it, `remove` takes every equal item out), and
`t.settings.tags[0]` reads an item. Queries read paths: `Team.where(settings.theme == "light")`,
`where("ui" in settings.tags)`, `where(exists settings.billing)`. A name that is also a
routine taking the record (`t.about`) is that routine; any other undeclared name is the
document's. Values given when creating go in the document too:
`Team.create(name = "Design", settings = {theme: "dark", tags: ["ui", x]})` (literals become
JSON when the program is built, program values when it runs); a record that is not `open`
refuses a field it lacks when the program is built. `case` on a value's shape, and merging
two devices' writes path by path (§8): **planned**.

| What document stores do | In Vajra | Made from | Status |
|---|---|---|---|
| collections with no schema | a record with only `open` | a `jsonb` column beside the declared ones | **built** (runtime suite) |
| nested objects and lists, any depth | paths: `a.b.c`, `a.b[2]` | `jsonb` | **built**; writing an item by number **planned** |
| partial updates; list add, remove, add-once | `=`, `.add`, `.remove`, `.addOnce` on a path | one `jsonb_set` / `jsonb` operator statement | **built** (runtime suite) |
| upsert | `Team.save(name = n, …)` (§3.3) | `insert … on conflict` | **built** |
| queries on any path: exists, in, ranges, patterns | `where` on paths | `jsonb` operators, `jsonpath` | `==`, `in`, `exists` **built**; ranges and patterns **planned** |
| indexes on paths | worked out by the Atlas from the queries the program makes (book rule 4) | GIN and expression indexes | **planned** |
| aggregation | `group`, `total`, `over`, `each` (one row per list item) | SQL over `jsonb_array_elements` | **planned** |
| change streams | `watch Team.where(…)`: every change as it commits | logical replication, `NOTIFY` | **planned** |
| expiry, capped collections | `expire after 30days`, `keep last 1000` | the sweep of §3.2; a trigger after each insert | **built** |
| validation added later | declare the field: existing documents are checked, the field becomes a column | a generated migration (§0.8) | **planned** |
| sharding | `spread by org` (§2.6) | Citus | **planned** |
| key-value | a record with a key and `memory` | an unlogged table | **built** (§3.2) |
| wide columns, analytics | `columnar` | pg_duckdb, Citus columnar | **planned** |
| graphs | §4 | recursive SQL, Apache AGE | §4 |
| full text, vectors, time series | `search`, `Vector`, `series by` | pg_search, pgvectorscale, TimescaleDB | §3.1, §3.2 |

**Documents settle into records.** When a path holds the same type in every document and the
program queries it often, the Atlas proposes declaring it. Accepted, the path becomes a typed
column through a generated migration; code that used it does not change. Data can start free
and become exact without being rewritten.

## 3.7 Parity with SQL and NoSQL databases, and the limits

The Atlas is Postgres with its extensions, so what Postgres does, Vajra does, under one
transaction and one set of rules.

| What other databases do | In the Atlas | Status |
|---|---|---|
| transactions, serializable isolation, retries | every event; `atomic:` (§2.5) | **built** |
| constraints, unique keys, no overlaps, checks | `check`, `unique … per`, `unique during`, `check later`, rules across rows, `moves`, `on delete` | **built** |
| joins, groups, windows, recursion, set operations | links, `any`/`all`/`none`, `group`, `latest`, `over`, `follow`/`via`, `union`/`intersect`/`except` (§2.7, §3.3) | **built**, pivots and `via` included |
| views, materialised views, triggers | `derive` | views from `where` and `group` rules **built**; materialised and recursive **planned** |
| stored procedures | ordinary Vajra routines; `tool` and `service` cells | **built** (routines, tools) |
| row and column security, audit log, history and as-of | `can`, field `can read`, the change log, `asOf` | **built** |
| encryption: in transit, at rest, per field | TLS; the disk; `sealed` with per-person keys | `sealed` **built** |
| tamper-evident records | `ledger`: append-only, hash-chained, `verify()` | **built** |
| indexes: B-tree, hash, GIN, GiST, BRIN, partial, by expression | worked out by the Atlas from the queries (book rule 4) | lookup and search **built**; the rest **planned** |
| upserts, generated columns, sequences, collations | `save`, computed fields, UUIDv7 ids, text in every language | upserts, computed fields and ids **built** |
| partitioning, sharding, columnar analytics | `partition by`, `spread by`, `columnar` (§2.6) | **planned** |
| replication, backups, recovery to a moment | Postgres streaming replication and WAL archiving to the object store | **planned** (operations) |
| change data capture, pub/sub | `watch`, notifications | notifications **built**; `watch` **planned** |
| outside data | `from csv`, `from postgres` (foreign tables) | **planned** |
| documents (MongoDB) | `open` records (§3.6) | **built**: paths read, written, added to, removed from and queried; merging across devices **planned** |
| key-value, cache with expiry (Redis) | `memory`, `expire after` | **built** |
| queues and streams (SQS, Kafka) | `queue`, `tries`; append-only spread records with `watch` | queues **built**; streams with `watch` **planned** |
| graphs (Neo4j) | §4 | `follow`, `via` patterns, `shortest`, PageRank, degree, communities, similar **built**; edges with fields and the rest **planned** |
| search (Elasticsearch) | `search`, fuzzy, facets (pg_search) | full text, fuzzy and facets **built** (Postgres and pg_trgm); pg_search's ranking **planned** |
| vectors (Pinecone) | `Vector`, `nearest` (pgvector, pgvectorscale) | **built** (pgvector) |
| time series (InfluxDB) | `series by`, `keep … detail` (TimescaleDB) | `series` with gap filling **built**; `keep … detail` **planned** |
| places (PostGIS) | `Point`, `near`, `distance` | **built** |
| offline devices that merge (CouchDB, CRDT stores) | sync by type (§8) | in parts **built** |

**The limits, said once.** One system that does every kind of work is beaten, at the far end
of each kind, by a system built for that kind alone:

- **Writes in many regions at once.** Postgres takes writes in one place per row; a space
  lives in one region, read copies may be anywhere, and devices merge their offline work
  (§8). Many regions all writing the same rows at the same moment is not a goal.
- **The largest event streams.** Millions of events a second, kept for weeks, is a log
  engine's work. Spread, partitioned, append-only records go far; past that, a log engine
  would be added as a backend behind the same words.
- **The fastest cache.** An unlogged table answers in a fraction of a millisecond, not in
  microseconds. Where microseconds matter, the host keeps the hot values in its own memory,
  behind the same `memory` record.
- **Warehouse scale.** Petabytes of analytics run on columnar files in the object store
  through pg_duckdb, slower than a warehouse built only for that.
- **Graph algorithms over billions of links** run as jobs on a snapshot (§4), not inside a
  transaction.

## 3.8 Tests

Built: the runtime and atlas suites (§3.1).

Planned (each one is a task): one per row of §3.2 to §3.5, each checking what its
"What it does" says, for example:
- A `Session` with `expire after 30min` is gone after 31 minutes and `vajra tick`.
- Two workers take from a `queue`; each job runs once; a job that fails 5 times is kept as
  failed.
- A `ledger` row cannot be updated or deleted by anyone.
- A `flow` killed between `pack` and `ship` resumes at `ship`.
- `moves todo -> doing -> done` refuses `done -> todo`.
- `renamed from` keeps every row's value under the new name.
- `open`: a document keeps undeclared fields at any depth; a missing path reads as `none`;
  writes to two different paths of one document by two writers both stay.
- An index is made for a path the program queries, without anyone writing it.
- A path declared later becomes a column, every document's value moves into it, and code
  that used the path is unchanged.
- `watch` delivers every committed change matching its query, in order. (It is one word
  everywhere: `watch` on a query, a record, a cell or a work node (§16.7) gives that
  thing's committed changes.)
