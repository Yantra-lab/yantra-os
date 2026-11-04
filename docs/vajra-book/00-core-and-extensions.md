# 0. The core and extensions

Yantra has a small core that changes rarely. Everything else is an extension, written
the same way by us and by anyone else. A new kind of thing never changes the core.

## 0.1 The core has three parts

| Part | What it is | Rule |
|---|---|---|
| **The language** | Nimony (Nim 3) with plugins | Every Vajra word is a plugin. The fork's own compiler changes shrink toward zero: each one is upstreamed or moved into a plugin. |
| **The Atlas** | Postgres holding all state | A fixed core: people, spaces, cells and their versions, grants, the change log, bytes. Everything else is an extension's schema. |
| **The host** | the engine, and the agents' door | It wraps real libraries (SDL3, Skia, Yoga, Filament, Jolt, FFmpeg, wasmtime), runs apps as sandboxed wasm, and gives them only what a grant allows. MCP is the only door for agents. |

## 0.2 Where Yantra runs

- **As an app** on Windows, macOS, Linux, Android and iOS: the host is a normal program.
  **built** (Windows; the others are **planned**, §9)
- **As the operating system** on devices we ship: the device boots into the host, and the
  shell is the first screen. **planned**
- One person's devices hold copies of the same Atlas spaces and sync in real time, offline
  first (§8). An app, a file or a half-written message is the same on every device.
  **planned**

The same apps run in both. An app never knows which one it is in.

## 0.3 Eight building blocks

Everything in Yantra is made of these, and nothing else:

| Block | What it is | Today |
|---|---|---|
| **Person** | anyone who acts: a human, an agent, an organisation, a device | humans and agents **built**; organisations and devices **planned** |
| **Space** | where things live, in a tree, with roles | **built** |
| **Cell** | code: kept for good with every version, or for a session, or for a time (§25.3) | kept **built**; lifetimes **planned** |
| **Record** | data, with its rules | **built** (`record`) |
| **Grant** | a permission to do one thing, given by someone who holds it | in parts (§0.4) |
| **Change** | the log: who did what, for whom, from which app | **built** (`atlas.change`) |
| **Blob** | bytes, found by their SHA-256 | **built** (the chunk store) |
| **Flow** | work that lasts: a session, an order, a render, a conversation | sessions and `every` **built**; `flow` **planned** (§13) |

## 0.4 Grants: every power has a holder, a limit and an end

A grant says: **who** may do **what**, **where**, **how much**, **until when**, given **by
whom**. Postgres checks it on every action. An app, an agent or a bot can do only what a
grant lets it do.

```text
grant @shopkeeper may refund in y:@asha-store, up to ₹2_000 each, until 2027-01-01
grant app y:@cy/editor may read File where folder under "home.drafts"
grant @tutor may call model image, up to ₹300 a day
```

- A holder may pass on a part of a grant: a smaller limit, a shorter time, a narrower
  place. Never more than it holds.
- Taking a grant back takes back everything passed on from it.
- Every use of a grant is in the change log, so "who did this, and by whose permission"
  always has an answer.
- Above a grant's limit, the action goes to the giver's inbox for approval (§19).

The grants that exist today are each one case of this:

| Today | As a grant | Status |
|---|---|---|
| a role in a space | a person may read or write in a space and the spaces under it | **built** |
| `shared` and `atlas.allow` | an app may use a person's rows of a shared record: all, or the chosen ones | **built** |
| `uses network "host"` | an app may reach one host | **built** |
| `uses secret "name"` | an app may use a secret, only in requests to its host | **built** |
| a tool's `Path` parameter | a tool may read and write only the file it was handed | **built** |
| a lease | one stream may write a cell, for a time | **built** |
| a session's supervisor | a person may steer and stop an agent's session | **built** |
| a budget, a model, the GPU, a payment, a message to a customer | — | **planned** (§12, §19, §20) |

**planned:** one table, `atlas.grant`, holds them all, and every one of the rows above
becomes a row in it.

## 0.5 Extensions

An extension is one package in the Atlas: a released library whose cells hold

1. **Hooks:** the words it adds to the language, each through one hook of §0.6.
2. **Schema:** its own records, which become tables, rules and indexes.
3. **Needs:** the extensions and hook versions it builds on, and the grants it asks for
   (the GPU, the network, a model, a payment provider).
4. **Flows and jobs:** its long work and its schedules.
5. **Tests:** its `test` cells. It installs only when they pass (§0.6, "Installing").
6. **A version.**

```text
extension @yantra/queues 1.0
  needs @yantra/data 1.x, hook recordLine 1, hook queryWord 1

hook recordLine "queue"           # `record Job` … `queue` now means something
hook recordLine "tries"           # `tries 5, then failed`
hook queryWord "take"             # `Job.take()`: one row, held by the caller
```

- An extension is installed in a space; every space under it can use it.
- A space stays on a version (`use @yantra/queues 1.0`) and moves when it chooses. A new
  version migrates its tables (§0.8); nothing is dropped.
- What is built today becomes the first extensions, so the core has no special cases:

| Extension | Holds | Today |
|---|---|---|
| `@yantra/data` | `record`, queries, `can`, `sealed`, `shared`, `extend`, history | **built**, inside the vocabulary |
| `@yantra/ui` | `view`, screens, `param`, `@name`, keyframes | **built**, inside the vocabulary |
| `@yantra/time` | `Time`, `Date`, `Duration`, zones, `every` | **built**, inside the vocabulary |
| `@yantra/tools` | `tool`, `Path`, `Folder` | **built**, inside the vocabulary |
| `@yantra/agents` | agent persons, charters, services and `ask`, sessions, forks, steering, questions, memory | sessions **built** (`host/atlas/agents.nim`, `tools/agent`); as a library **planned** |
| `@yantra/media` | image, video, mask, mesh, material, shot, timeline, audio nodes; providers | **planned** (§10, §12) |
| `@yantra/people`, `@yantra/files`, `@yantra/web` … | §18 | **planned** |

`@yantra/data`, `@yantra/agents` and their like are installed everywhere and maintained
with the core, but they hold no power the core does not give every extension.

## 0.6 Hooks: the contract every extension plugs into

A hook is a typed place where an extension adds meaning. The core defines the hooks and
runs them; extensions only implement them. There are eleven:

| Hook | An extension adds | It receives | It returns (a plan, as data) |
|---|---|---|---|
| `word` | a declaration word (`record`, `view`, `flow`, `film`) | the declaration's NIF and the interfaces it can see | NIF for the compiler, the declaration's interface, its facets |
| `recordLine` | a line inside `record` (`queue`, `ledger`, `series by`, `expire after`) | the record's shape (fields, types, rules) and the line | fields, indexes, rules, triggers, query words it enables, a migration |
| `type` | a value type (`Money`, `Point`, `Vector`, `Mesh`, `Video`) | its declaration | how it is stored, compared, merged when devices sync, sealed, shown, sent |
| `queryWord` | a query word (`near`, `nearest`, `follow`, `window`, `take`) | the input's record type and the arguments | the output's type, and the relational plan the core turns into SQL |
| `backend` | a Postgres extension a query word or type needs (PostGIS, pgvector, AGE, TimescaleDB, pg_search, pg_duckdb, Citus) | the plan pieces addressed to it | SQL for that backend, and its install steps |
| `viewNode` | a view node (`chart`, `map`, `timeline`) | its props | a composition of existing nodes; or, for a new primitive, the name of the host extension that draws it |
| `provider` | a model or service (`language`, `image`, `video`, `mesh`, `speech`, `music`, `payments`; §12's kinds) | a typed request | a typed result, its cost, its effect |
| `tool` | an action an agent or app may take | typed arguments, the caller's grants | a typed result |
| `service` | a service a person, organisation or agent offers (`@yantra/director` plans shots) | its request and result types, price, time, who may ask | a typed, documented offer anyone with a grant may `ask` for (§16.12) |
| `facet` | something kept beside every cell version (NIF, interface, card, embedding, KV chunk, artifact) | the version | the facet, kept by the version's hash |
| `check` | a check the gate runs (typesetting, coverage, the critic's rubric, an exam) | a change | pass, or the reasons it fails |

**Hooks are pure.** A hook's implementation is a proc with no effects: it reads its inputs
and returns a plan; it never touches the Atlas, the network or a file. The core applies the
plan. So builds are deterministic, every hook result is cached by the hash of its inputs,
hooks run in parallel, and a broken extension cannot damage a space: its plan is checked
before anything is applied.

**Plans are typed, never strings.** SQL, NIF and view trees inside a plan are typed values
built with the core's builders, so the core checks them (a column that does not exist, a
rule that names no person) before they reach Postgres or the compiler.

```text
hook recordLine "queue":
  proc plan(r: RecordShape, line: Line): RecordPlan =
    result.field "heldBy", User?, hidden
    result.field "heldUntil", Time?, hidden
    result.index "heldBy"
    result.queryWord "take", take        # enabled for records with this line

  test "two workers take different rows":
    record Job
      title: string
      queue
    Job.create(title = "a"); Job.create(title = "b")
    check as(@w1, Job.take()).title != as(@w2, Job.take()).title
```

**Names.** A word belongs to one extension in a space. Installing a second extension that
claims the same word is refused, unless it says it replaces it:

```text
extension @me/fastqueues 1.0
  replaces @yantra/queues.queue        # this space's `queue` now means mine
```

A replacement must pass the replaced word's tests as well as its own, so code that used the
word keeps working.

**Versions.** Every hook has a version (`recordLine 1`). An extension says which versions
it implements. The core keeps every hook version for at least one edition after a newer one
appears, and an edition (`use vajra 2027.04`) is where an old version stops.

**Installing.** An extension installs in three steps, and the space changes only at the
last: (1) its hooks and tests build in a scratch copy of the space's interfaces; (2) its
tests, and the tests of every word it replaces, pass there; (3) its plans are applied in one
transaction. Any failure leaves the space as it was.

**The same freedom of form as Nim.** A hook adds meaning, not a second way to say an
existing thing; that meaning still takes every elegant form Nimony allows: method or
function call, command syntax, operators, templates. What the gate refuses is a second
concept for a job that already has one (the critic's rubric, §14).

## 0.7 The kernel

A few things cannot be extensions, because extensions are made of them. They are written
by hand, kept small, and change only with an edition:

- **Nimony** and the plugin mechanism that runs hooks.
- **The hook dispatcher and the plan builders** (typed SQL, NIF, view trees).
- **Seven tables:** `person`, `space`, `member`, `cell`, `version`, `blob`, `change`, with
  their row rules. Every other Atlas table, the Atlas's own included (`agent_session`,
  `memory`, `run`, `swarm_model`, …), is declared in Vajra as a record of an extension and
  built like any app's.
- **The host's door:** wasm sandboxing, grants enforcement, MCP.

Test of the kernel's size: `@yantra/data`, installed as an extension in an Atlas that has
only the kernel, passes every records test that passes today.

## 0.8 Changing anything

Every part of Yantra is cells in the Atlas: the language's words, the Atlas's tables, model
routing, the agent library, the harness and its supervisor, rules and briefs. A person or an
agent changes any of it the same way, and only in these ways:

| Change | How | What stays safe |
|---|---|---|
| fix or improve a word | a new version of its extension, through the gate | spaces stay on their version until they move |
| give a word a different meaning in one space | an extension that `replaces` it | the old word's tests must still pass |
| change the language for everyone | an edition | code on the old edition builds as before |
| change a record's fields | the record's new version; the core generates the migration (add first, remove later; a renamed field keeps its data) | no data is lost, no reader breaks mid-change |
| change a setting, a model, a rule | a row in the Atlas, kept with its history | the change log says who, when and why |

Nothing is edited in place without a version, so every earlier state can be restored, and
every change has an author and a reason.

## 0.9 What never goes into the core

- A kind of content (videos, questions, orders): an extension.
- A domain (commerce, schools, government): an extension.
- A model, a provider, a payment company: a provider behind a grant.
- A ranking, a feed, a site: a lens, which is a cell (§22).
- A special case for one app: never.

## 0.10 Tests

Built:
- Libraries with releases and editions: atlas tests and `t_mcp` ("publish releases a
  library once; a release never changes").
- Sessions and their rules: atlas tests ("an owner starts a session …").

Planned (each one is a task):
- An extension whose tests fail does not install, and the space is unchanged.
- A second extension claiming an installed word is refused; with `replaces` it installs
  only when the replaced word's tests pass with it.
- A hook that tries an effect (a query, a file, the network) does not build: hooks are pure.
- A plan naming a column or a person that does not exist is refused before Postgres sees it.
- The same hook with the same inputs is computed once (its result is found by hash).
- An old hook version keeps working until the edition that ends it.
- A record's new version with a renamed field keeps every row's data under the new name.
- A grant passed on with a larger limit than its holder's is refused.
- Taking back a grant takes back every grant passed on from it, in one change.
- An action over a grant's limit goes to the giver's inbox, and runs only after approval.
- `@yantra/data`, installed as an extension in an Atlas that has only the kernel, passes
  every records test that passes today.
