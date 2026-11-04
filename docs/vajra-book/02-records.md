# 2. Records

A record is a type in the program, a table in Postgres, its permissions, its invariants and
its search index, from one declaration. There is no SQL, no ORM and no migration to write.
Built unless marked; the full reference is `sdk/vajra/README.md`, and the tests are the
runtime suite (`host/vajra/tests/run_tests.nim`).

## 2.1 One declaration

```text
record Order
  item: string
  qty: int
  price: float
  total: float = qty * price      # computed: the database keeps it current
  paid: bool = false              # a default: optional when creating
  tags: seq[string]
  customer: Customer              # a link to another record
  owner: User = me
  can read, write: owner          # row security, in Postgres
  check qty > 0                   # an invariant the database keeps
  search item                     # full-text search
  index item
```

- Every row has a global id, a UUIDv7 made by the database, unique everywhere and in time
  order.
- Every row has an envelope the database keeps (`t.about`): made and changed when, by
  whom, for whom, from which app, its version.
- Every change is in one log no app can read or forge; a row's history is `t.history`, and
  the row at a moment is `t.asOf(t)` (§5).

## 2.2 Using rows

```text
let ada = Customer.create(name = "Ada")
Order.create(item = "red pen", qty = 10, price = 0.5, customer = ada)
for o in Order.where(not paid and "ink" in tags).sort(total.desc).take(5):
  echo "{o.item} for {o.customer.name}"
Order.where(qty > 100).update(paid = false)
for (customer, spent) in Order.group(customer).total(total): echo "{customer.name} spent {spent}"
atomic:
  Order.create(item = "gift card", qty = 1, price = 10.0, customer = ada)
```

- A record's name stands for all its rows: `Order.count`, `Order.total(price)`; anything
  that changes every row says `all`.
- Queries are compiled to SQL and checked at compile time: a misspelled field or a value of
  the wrong type is a compile error; every program value is a bound parameter.
- The words: `where`, `sort`, `take`, `skip`, `group`, `update`, `delete`, `count`, `total`,
  `average`, `highest`, `lowest`, `ranked`, `running`, `follow`, `search`, `near`, `nearest`;
  more are planned (§3.3).

## 2.3 Who may see a row

`can` lines are the only permission system; Postgres enforces them on every query of
every app. A rule may name the row's owner, a list of people, a role in the space, or a
person reached through a link (`can read: note.owner`). Spaces form a tree, and a role holds
in every space below.

## 2.4 Records that reach across apps

- `shared`: one record's rows for every app, each app seeing a person's rows only as far as
  they allowed (§18).
- `extend Contact`: an app adds its own fields to another app's record.
- `sealed`: a field encrypted with a per-person key, never in history, never opened for an
  agent; no query may look at it.
- `importCsv`, `importJson`, `asCsv`, `asJson`: rows in and out, all or none.

## 2.5 Every event is all or nothing

A tap or keystroke is one transaction; `atomic:` is all or nothing (a savepoint inside
another). Every outermost one is serializable, and a conflict runs it again, up to 5 times,
so two transfers at the same moment never lose one.

## 2.6 Where rows live, at any scale

Today each app's records are tables in a schema of its own (`app_<space>_<name>`), and the
app connects as a login role of the same name (in role `yantra_app`), so Postgres keeps one
app out of another's tables. **built**. That does not scale: a schema and a role per app
make Postgres's catalogs grow with the number of apps, and every machine of a cluster must
know every role. The design at scale is below. **planned**

**Who is asking, and keeping apps apart.** One login role for every app (`yantra_app`). The
host binds a connection to an app and a person once, through a security-definer function
that checks the host's signed token; `atlas.app()` and `atlas.me()` read the binding, and
nothing changes it afterwards. Every app table has the row rule `atlas.app() = <its app>`
beside its `can` rules, and the app role may not create, alter or drop anything. An app that
names another app's table sees no rows and cannot write one. No role per app.

**Three placements.** A record says where its rows live with one line; most say nothing.

| Placement | For | How | Line |
|---|---|---|---|
| **its app's** | almost every app's records | the app's schema lives whole on one machine (Citus schema-based sharding), so its transactions stay on one machine | (none: the default) |
| **spread** | records that grow without end and many apps share: posts, follows, videos, comments, messages, events, views, classes, org members, a bot's conversations | rows spread over every machine by a key, so the record grows by adding machines; with `partition by time`, recent rows stay fast and old ones are kept compact (columnar) | `spread by author` |
| **everywhere** | small records every app reads: editions, currencies, people's public profiles | a copy on every machine | `everywhere` |

```text
record Post
  author: User
  at: Time = now
  text: string
  media: seq[Asset]
  spread by author                  # all of one author's posts on one machine
  partition by at                   # by month; old months compact
  can read: everyone
  can write: author
```

- A query that names the key (`Post.where(author == a)`) runs on one machine; one that does
  not runs on all of them in parallel, and the Atlas says so in the query's plan.
- `shared` records (§2.4) and the Atlas's own tables are spread by space.
- The platform's own large features are extensions built on spread records, each with its
  own records, views and agents: `@yantra/social` (posts, follows, feeds), `@yantra/video`,
  `@yantra/chat` (conversations, messages, bots), `@yantra/orgs` (organisations, teams,
  roles), `@yantra/classroom` (classes, work, grades), `@yantra/meet` (calls, rooms).
- A feed is written to each follower's timeline when a post is made, except for authors
  with very many followers, whose posts are read at the time the feed is shown.

**The long tail.** An app nobody has used for a set time is parked: its schema is written to
the object store and dropped. Its first request restores it, then it runs as before.

**Bytes.** Big files live in an object store addressed by SHA-256, served through a CDN;
Postgres keeps their names, sizes, owners and rules.

**The Atlas itself.** Every Atlas table except the kernel's seven (§0.7) is a record of an
extension, declared in Vajra, with the same rules, history and placement as any app's.

To measure before relying on it: how many app schemas a machine holds before catalog
lookups slow down (the aim: tens of thousands), how long a parked app takes to come back,
and how a spread record's queries scale as machines are added.

## 2.7 One algebra under every query

Every query word, on every kind of data (rows, documents, graphs, series, vectors, text),
lowers to one small relational algebra. Extensions add words and backends to it, never a
second query language. **planned** (queries compiled to SQL and checked at compile time:
**built**)

The algebra has ten operations: `scan`, `filter`, `map` (compute and keep fields), `join`
(links and `via` included), `group … total`, `window`, `order`, `take`, set operations
(`union`, `intersect`, `except`), and `repeat` (recursion: paths, `follow`, `derive`).
`each` makes one row per item of a list.

| Written | Its algebra | Runs on |
|---|---|---|
| `Order.where(total > ₹1000).sort(at).take(10)` | scan, filter, order, take | Postgres |
| `Shop.near(at, here, within = 2km)` | scan, filter on distance | PostGIS |
| `Doc.nearest(meaning, asked).take(20)` | scan, order by distance, take | pgvectorscale |
| `Person.follow(knows, upto = 3)` | repeat | recursive SQL, or Apache AGE for patterns (§4) |
| `Post.search("monsoon")` | scan, filter by match, order by score | pg_search |
| `Reading.series(at, 1h).average(pulse)` | group by time bucket, window | TimescaleDB |
| `Sale.pivot(region, month).total(amount)` over years of rows | group | pg_duckdb (columnar) |
| `Team.where(settings.theme == "dark")` | filter on a path | `jsonb` operators |

- A word is defined once, by its `queryWord` hook (§0.6): its type rule and its algebra.
  Where it runs is its `backend` hook's choice, which may change without the word, or any
  program, changing.
- Every query composes with every other: `Shop.near(at, here, within = 2km).where(open)
  .nearest(meaning, asked).take(5)` is one query, planned as a whole.
- Types flow through every step: a field that does not exist or a value of the wrong type
  fails to build.
- `.plan` shows the algebra and where each part runs: which backend, which machines (§2.6).
- The Atlas works out the indexes from the queries the program makes, on every backend
  (book rule 4).
- One transaction covers every backend, because every backend is inside Postgres.

## 2.8 What comes next

The lines that make a record a queue, a ledger, a time series, a flow or memory-only, and
the planned query words and rules: §3.

## 2.9 Tests

Built: the runtime suite (the `shop` app and every rule above).

Planned (each one is a task):
- An app that names another app's table sees no rows and cannot write one.
- A connection bound to an app and a person cannot change either.
- Building an app creates no role.
- A parked app, opened again, answers as before: its rows, its history, its rules.
- On two workers, one app's transaction touches one worker.
- A `spread by author` record's query that names an author runs on one machine; one that
  does not runs on every machine, and its plan says so.
- A feed shows a followed author's new post, whether written to timelines or read at show time.
- One query written with method calls, function calls or command syntax compiles to the
  same algebra.
- `near`, `where` and `nearest` in one query return the same rows as the same steps applied
  one after another.
- Moving a word to another backend (vectors from pgvector to pgvectorscale) changes no
  program, and no result beyond the backend's stated approximation.
- `.plan` names the backend and the machines of every part.
