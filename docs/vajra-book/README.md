# The Vajra book

The whole of Vajra and the Atlas, as they will be. It is the design, the model's manual,
and the source of its tasks. Read `docs/foundations.md` first, then §0: everything else is built on it.

## How to read a chapter

Every feature has four parts:
1. **Code:** what a person or a model writes.
2. **Meaning:** what it does, in short exact sentences.
3. **How it is made:** a plugin, SQL in the Atlas, a NIF pass, or the GPU.
4. **Tests:** the checks that define it.

Every feature has a status:
- **built**: a test proves it; the test is named.
- **planned**: the word is part of Vajra now. Its types are checked, then the build stops
  with `<word> is part of Vajra but not built yet (book §N)`. Its tests are the task
  that builds it.

Code in this book is the language as it will be. Code a reader writes today stays right
when a planned feature is built: only the "not built yet" message goes away.

## The rules every chapter keeps

1. **One noun.** Data is a `record`. Lines inside it change how it behaves (`shared`,
   `keep history`, `expire after`, `queue`, `ledger`).
2. **The same words everywhere.** `where`, `sort`, `group`, `take`, `via` work on every
   kind of record.
3. **Types carry behaviour.** A field's type decides how it is stored, merged, sealed,
   measured and shown.
4. **The Atlas knows the whole program.** It works out indexes, permissions, what each
   device syncs, migrations and each node's interface. Nobody writes them by hand.
5. **New features are plugins.** The compiler stays small; the vocabulary grows.
6. **Prove what can be proved, test the rest.** Nimony's contracts engine proves ranges at
   compile time; budgets and rules follow it there.
7. **The database decides.** Permissions, invariants and refusals live in Postgres, so
   no app and no agent can forget them.
8. **The shape of the language** (§1.6): one shape for every declaration; `can`, `may` and
   `uses`; one address grammar; no async words; one way to fail; words over symbols; one
   naming style; all of Nimony; `open` documents; editions.

## Chapters

| § | Chapter | File |
|---|---|---|
| 0 | The core and extensions | [00-core-and-extensions.md](00-core-and-extensions.md) |
| 1 | Values and types | [01-values-and-types.md](01-values-and-types.md) |
| 2 | Records | [02-records.md](02-records.md) |
| 3 | Kinds of data | [03-kinds-of-data.md](03-kinds-of-data.md) |
| 4 | Graphs | [04-graphs.md](04-graphs.md) |
| 5 | Time and history | [05-time-and-history.md](05-time-and-history.md) |
| 6 | Concurrency | [06-concurrency.md](06-concurrency.md) |
| 7 | The GPU | [07-the-gpu.md](07-the-gpu.md) |
| 8 | Sync and multiplayer | [08-sync-and-multiplayer.md](08-sync-and-multiplayer.md) |
| 9 | Views, layout and devices | [09-views-layout-devices.md](09-views-layout-devices.md) |
| 10 | Motion, film and 3D | [10-motion-film-3d.md](10-motion-film-3d.md) |
| 11 | Sound | [11-sound.md](11-sound.md) |
| 12 | The studio: models as providers | [12-the-studio.md](12-the-studio.md) |
| 13 | Tools, jobs and the network | [13-tools-jobs-network.md](13-tools-jobs-network.md) |
| 14 | Tests and checks | [14-tests-and-checks.md](14-tests-and-checks.md) |
| 15 | Formatting and style | [15-formatting-and-style.md](15-formatting-and-style.md) |
| 16 | The Atlas and its agents | [16-atlas-and-agents.md](16-atlas-and-agents.md) |
| 17 | What to store | [17-what-to-store.md](17-what-to-store.md) |
| 18 | The OS vocabulary | [18-os-vocabulary.md](18-os-vocabulary.md) |
| 19 | Agents that serve people | [19-agents-that-serve-people.md](19-agents-that-serve-people.md) |
| 20 | Money | [20-money.md](20-money.md) |
| 21 | The superapp | [21-the-superapp.md](21-the-superapp.md) |
| 22 | The Yantra web | [22-the-yantra-web.md](22-the-yantra-web.md) |
| 23 | The graph view | [23-the-graph-view.md](23-the-graph-view.md) |
| 24 | Memory | [24-memory.md](24-memory.md) |
| 25 | Notebooks: every result kept | [25-notebooks.md](25-notebooks.md) |
