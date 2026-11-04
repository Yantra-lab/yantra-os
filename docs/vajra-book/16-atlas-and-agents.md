# 16. The Atlas and its agents

The Atlas is Postgres holding everything: code as versioned cells, the vocabulary,
people, their data, agents, secrets and big files. An agent works in the Atlas the way a
person does: as a member of spaces, through one door, under the same rules.

## 16.1 An agent is a person

- An agent is a person of kind `agent`. It is a member of spaces and holds roles in them,
  like any person. **built** (`host/vajra/tests/t_mcp.nim`)
- It acts only through MCP (`vajra mcp --as:<handle>`). It has no shell and no checkout.
- Postgres decides what it reads and writes, row by row, as for a person. It never reads a
  `secret` cell, a sealed field or a stored secret. **built**
- Every change it makes carries its name in the row's envelope and in the change log.
  **built**
- A person decides what an agent may do. Only a space's owners change who is a member and
  with which role, so an agent that is not an owner cannot raise its own role. **built**
  (row rules on `atlas.member`, `host/atlas/access.nim`; its test is planned, §16.10)

## 16.2 The one door: tools

Every action is a tool. A tool checks its arguments, acts as the agent, and returns text
the agent reads. Web pages, files and other people's fields come back marked as untrusted
data, never as instructions.

**built** (24 tools, `t_mcp`):

| Group | Tools |
|---|---|
| Cells | `find`, `list`, `open`, `write`, `delete`, `rename`, `usages` |
| History | `history`, `diff`, `revert` |
| Sharing and holding | `share`, `lease`, `release` |
| Making | `build`, `run`, `test`, `render`, `parity`, `import`, `asset` |
| Libraries and data | `publish`, `data`, `secret` |
| Self | `whoami` |

**planned** (each answers "not built yet (§16.2)" until built):

| Tool | What it does |
|---|---|
| `judge` | Builds a program and runs it on a task's tests; the verdict and what failed. |
| `draft`, `merge` | Opens a draft of a node; merges it when its checks pass (§16.6). |
| `fork`, `join` | Starts a substream from this point; takes its result back (§16.7). |
| `ask` | Sends a request to the stream on another node, or a proposal to the node above. |
| `inbox` | Asks a person: a taste call, or anything that cannot be undone. |
| `remember`, `recall`, `zoom` | The summary tree (§16.8). |
| `media` | Calls an image, video, 3D, speech or music model (§12). |
| `web` | Fetches a page or searches the web; the answer is untrusted data. |
| `study` | Reverse-engineers how an app or a site behaves (REA). |
| `job` | Starts long work (a render, a training run) and reports when it ends. |

## 16.3 The work tree

All work is a tree of nodes. A node is a product, a system, a module or a cell:

```text
product   y:editor                       the one idea, who it is for, budgets
 system   y:editor/render                a big part
  module  y:editor/render/text           one job, a folder of cells
   cell   y:editor/render/text/shape     one declaration
```

```text
type NodeKind* = enum product, system, module, cell
type Status* = enum planned, contracted, built, verified

record Node
  path: TreePath                 # y:editor/render/text, kept as ltree
  kind: NodeKind
  brief: string                  # what it is and why: at most three sentences (§17)
  mayUse: seq[Node]              # the only nodes it may depend on
  frameMs: Duration?             # budgets its checks measure
  memoryMb: int?
  status: Status = planned
  moves planned -> contracted -> built -> verified
  holder: User?                  # the stream that holds it now
  can read: members
  can write: holder or owners
```

- `TreePath`: **built**. `moves` (allowed changes of a field): **planned** (§2).
- A node is `verified` when its checks pass and every child is `verified`. The Atlas works
  this out; nobody sets it by hand. **planned**
- Ready work is a query, not a manager:
  `Node.where(status == planned and parent.status >= contracted and all mayUse(status == verified))`.
  **planned**

## 16.4 A contract is computed, not written

A node's contract is what it promises to the rest of the program. It has four parts, and
a machine checks each one:

1. **Its interface:** the types and routines it exports. The compiler works it out;
   Nimony already keeps an interface checksum for every module. When the checksum
   changes, the contract has changed.
2. **Its checks:** `test` cells beside it. **built** (`test`)
3. **Its budgets:** numbers the checks measure (`frameMs`, `memoryMb`).
4. **Its brief:** at most three sentences, checked by the style rules of §17.

Nothing else is in a contract. Prose that a machine cannot check has no place in it.

## 16.5 What the Atlas refuses

The database refuses these writes, whoever makes them:

| Refused | Message |
|---|---|
| A write to a cell held by another stream | `lease` answers `someone else holds it` **built**; naming the holder and the end time is **planned** |
| A use of a node outside `mayUse` | `render may not use app: it is not in render.mayUse` **planned** |
| A change to a node's interface by anyone but its parent's holder | `the interface of y:… is its parent's to change; ask` **planned** |
| Code without checks, in a node that is past `planned` | `y:… has no test` **planned** |
| A change that makes a dependent node's checks fail | `this breaks y:…: <the failing check>` **planned** |
| A node over its budget | `y:… took 21 ms of its 16 ms` **planned** |

## 16.6 Drafts

A stream writes into a draft: its own layer of the code and data, on top of the current
version. **planned**

- It reads its own changes, and the current version everywhere else.
- `merge` runs the checks of every node the draft touches, and the checks of every node
  that uses them. When they pass, the whole draft becomes current at once. When one fails,
  nothing changes and `merge` says which check failed.
- Two drafts that change the same cell do not both merge: the second one goes to the
  parent node's holder, who merges them.
- A draft costs nothing to open: it holds only what it changed.

## 16.7 Streams and their moves

Many streams work as one agent. They share one trunk: the text every stream reads first
(§16.9), so a GPU keeps the trunk's working memory once for all of them. **planned**

| Move | When | Tool |
|---|---|---|
| Do it | The change is small and close | (none: keep going) |
| Fork | A part can be done on its own | `fork`, `join` |
| Ask up | The interface or a decision must change | `ask` (to the parent) |
| Ask across | Another node must do something | `ask` (to that node) |
| Try several | A design choice, or a hard problem | `fork` two to four times; the checks and a critic choose |
| Review | Before every merge | `fork` as a critic, which reads the same trunk |
| Watch | A node it depends on may change | `watch` |
| Ask a person | Taste, or anything that cannot be undone | `inbox` |

Every move is a record in the Atlas, so a session can be replayed, and it can be used
for training.

`fork` with the session's own memory and `wait_clones` (join) are **built** (`tools/agent`,
`t_agent`); try several, review, watch and ask across are **planned**.

## 16.8 Memory: the summary tree

An agent's memory never ends and never loses anything. (The design follows UniiChat by
Victor Taelin.) **planned**. The whole memory system (kinds, scopes, helpers, blocks of
context, recall, live editing) is §24.

```text
record Memory
  owner: User                    # a person or an agent
  about: Node?                   # the node this memory belongs to, if any
  level: int                     # 0 is a message; 1 joins two messages; and so on
  first, last: Time              # the span it covers
  line: string                   # one line, written as §17 says
  parts: seq[Memory]             # the two lines it was made from (none at level 0)
  source: Link?                  # the original message or change, at level 0
  can read, write: owner
```

- Each message or event becomes one line (level 0).
- Two neighbouring lines are joined into one line a level up. The tree grows as a binary
  tree.
- The view is what a stream reads. Recent lines appear one by one; older parts appear as
  fewer, broader lines; everything fits a fixed size.
- `zoom` on a line returns the two lines it was made from, down to the original.
- The view changes only when a join is finished. Between joins it stays the same text, so
  its working memory on the GPU stays valid for every stream that reads it.
- There is one tree for each person, each agent, and each node of the work tree.
- The change log keeps every original version, so detail fades with age, and nothing is lost.

## 16.9 What a stream reads, in order

A stream's context is assembled by the Atlas, always in this order. The most stable parts
come first, so streams that share a beginning share its working memory on the GPU.
**planned**

1. This book, as of the edition the work uses.
2. The product's brief and budgets.
3. The brief and interface of each node above this one.
4. The memory view of this node.
5. The node itself: its code and its checks.
6. The interfaces (not the code) of every node it uses.
7. The task.

Siblings share parts 1 to 3. Streams on the same node share parts 1 to 6.

## 16.10 Sessions: agents are native to the Atlas

A session is one stream of work. It is rows in the Atlas, so the supervisors watch and
steer it with the Atlas's own tools, and Postgres decides who may. **built**
(`host/atlas/agents.nim`, atlas tests "an owner starts a session …" to "an agent forks …")

| Table | Holds |
|---|---|
| `atlas.agent_session` | the space, the agent, the goal, the state, the parent session, tokens used, the summary |
| `atlas.agent_step` | every model reply and tool result, numbered: the trace, and training data later |
| `atlas.agent_steer` | a supervisor's words to the session |
| `atlas.agent_ask` | the agent's questions, and the supervisors' answers |

- A session's agent, the agent of its parent session, and the human owners and editors of
  its space see it. Nobody else does.
- Only supervisors steer and answer. An agent cannot steer its own session; it can start a
  child session and steer that.
- A steer, an answer or a change of state wakes every listener on `atlas_agent` at once:
  the payload is the session's number.
- The states are `waiting`, `running`, `asking`, `stopping`, `stopped`, `done` and `failed`.
- The harness (`tools/agent/agent.nim`) runs one session. The supervisors' tools are
  `start`, `sessions`, `watch`, `steer`, `answer` and `stop`.
- The swarm (`docs/swarm.md`): models and settings are Atlas rows (`atlas.swarm_model`,
  `atlas.swarm_setting`); the supervisor (`tools/agent/swarm.nim`) keeps the GPUs full and
  merges only through the gate. **built** (`t_agent`, `t_swarm`)

## 16.11 Every version and its facets

A version is found by its hash: the hash of its canonical source together with the
versions of the edition and the extensions it was built against. (BLAKE3; today a
placeholder hash, `contentHash` in `host/atlas/atlas.nim`.) Beside each version the Atlas
keeps **facets**: things made from that version alone, each by a `facet` hook (§0.6). A
facet is computed once and stays valid as long as the hash is the same.

| Facet | Holds | Made by | Used by | Status |
|---|---|---|---|---|
| `source` | the canonical text | the typesetter, on save | people, review | **built** |
| `nif` | Nimony's typed intermediate form | the compiler | builds, the uses graph, structured edits | the column exists (`version.nif`); filling it **planned** |
| `interface` | the names, types and effects it exports, and their checksum | the compiler | contracts (§16.4), change notices, the contract a `fork` writes to | **planned** |
| `uses` | the versions it depends on | the compiler, from `nif` | `ref`, what a change affects, context assembly | `ref` from source **built**; from `nif` **planned** |
| `card` | one exact line of what it does (§17) | a model, checked by the style rules | search, context assembly | **built** (`card`) |
| `embedding` | its meaning as a vector, one per embedding model | a model | recall, similar code | **planned** |
| `kv` | a serving model's cached state for the card or the source, in a form that can be placed anywhere in a context | the serving engine | assembling a context at almost no input cost (§16.9) | **planned** |
| `artifact` | compiled output, renders, media | builds and renders | running, playback | builds **built**; per version **planned** |
| `checks` | the results of its tests, examples and budgets | the gate | contracts, the notebook (§25) | as runs **built** |

- A facet is never edited. A new version has new facets.
- A facet hook says when its facet is made: on save (`nif`, `interface`, `uses`, `card`),
  or the first time it is asked for (`embedding`, `kv`, `artifact`).
- Small facets are rows of `atlas.facet` (version, kind, model, hash, value). Big ones (`kv`,
  `artifact`) are blobs, kept by a cache policy on the fastest tier that has room: GPU
  memory, the host's memory, its disks, then the object store. The row says where.
- A `kv` facet belongs to one serving model and one form. When the model changes, its `kv`
  facets go; every other facet stays.

**Structured edits.** Besides writing text, a person or an agent may change code through
its `nif`: rename a name everywhere it is used, add a field, change a signature together
with every call. The result is new versions of every cell it touches, in one change, and
each goes through the typesetter like any other. A rename by structured edit cannot miss a
use, because the uses are known. **planned**

**Change notices.** When a version's `interface` checksum differs from the one before, the
Atlas notifies every stream holding or working on a cell that uses it, with one line: the
cell, what changed (a name, a type, an effect). The harness adds that line at the stream's
next step. A version that changes only the body sends nothing. **planned**

## 16.12 Agents are persons who offer services

An agent is a person (§16.1), like a human or an organisation. Nothing in the language,
the editor or the engine depends on one. Yantra's own agents (`@yantra/writer`,
`@yantra/director`, `@yantra/artist`, `@yantra/editor`, `@yantra/critic`, `@yantra/coder`,
…) are agents whose charter (§19) serves Yantra and talks to anyone; they are documented by
the services they offer, and used only as far as a grant allows, like any person's
services. Anyone may deploy their own agents the same way. **planned** (agent persons,
sessions, forks and the harness are **built**, §16.10)

**A service** is an offer, kept as a record in the offerer's space: what it takes, what it
gives, what it costs, how long it takes, and who may ask.

```text
service PlanShot by @yantra/director
  takes brief: string, line: ScriptLine, style: Style?
  gives Shot
  costs ₹4 typical, ₹20 at most
  answers in 10min typical
  may ask: anyone granted `ask @yantra/director`
```

**Asking** is the same for a human, an organisation or an agent: the request goes to them,
and the answer comes back typed. A human answers in their inbox, through a form made from
the types; an agent answers through its sessions (§16.10).

```text
let shot = ask(@yantra/director, PlanShot, brief = "A slow push in.", line = l)
let quote = ask(@asha-store, Quote, items = cart)       # a shop: a person or its agent answers
```

| Word | Meaning |
|---|---|
| `service S by @p` | an offer by person `@p`: its request and result types, price, time and who may ask (the `service` hook, §0.6) |
| `ask(@p, S, …)` | asks `@p` for service `S`; waits; returns the typed result, checked like any value of its type. Method and command forms mean the same (`@p.ask(S, …)`, `ask @p, S, …`) |
| `request(@p, S, …)` | the same without waiting: `r.wait`, `r.value`, `r.cancel` |
| `all(xs)`, `first(xs)` | many requests at once, joined; or the first to finish (§6) |
| `review x by @p until cond, at most n times` | `@p` reviews `x`; while `cond` is false, `x` goes back to whoever made it, with the reviewer's words |

- Code that asks is ordinary code, n8n-style: an app, a flow, a scratch cell (§25.3) or a
  film may ask, but none has to. Content made by asking is data like any other (§10.5).
- The asker's effect is `requests` (§1.5): it needs a grant to ask, and the price is spent
  from the asker's budget, beyond which the giver approves (§0.4).
- Which models an agent uses is its operator's business, kept as rows (for Yantra's own
  agents, `atlas.route`: the lead, worker, critic and image roles each map to a model), so
  an operator moves its agents to a new model in one change, and askers notice nothing.
- Every request and its answer is kept (§25), so work made by asking replays exactly
  (§1.5), and any one answer can be asked for again alone.

```text
film Monsoon
  let script = ask(@yantra/writer, WriteScript, brief = "Sixty seconds: a city waits for the monsoon.")
  var shots = all(script.lines.map(l => ask(@yantra/director, PlanShot, brief = "Plan it.", line = l)))
  for shot in shots.mitems:
    review shot by @yantra/critic until shot.score >= 8, at most 3 times
  render ask(@yantra/editor, CutFilm, shots = shots, music = "tense strings"), to = "monsoon.mp4"
```

## 16.13 Tests

Built:
- `t_mcp`: an agent speaks MCP and is offered every tool (32); write, then find a cell by
  what it does, then open it; every build, run, test and render is kept as a run;
  `notebook` shows an app's cells with the latest result under each.
- `t_agent`: a session forks a clone that starts from the session's own conversation
  (it sees the session's earlier work), writes its piece and reports back; `wait_clones`,
  `zoom`, `remember` and `recall`; past `compact_at`, older steps become one summary.
- `t_swarm`: the supervisor starts no agent while the model's server has a long queue,
  starts them when it is short, sends a red gate back to its agent, and merges each task
  into the base only through the gate.

Planned (each one is a task):
- A fresh agent sees no `secret` cell and nothing outside its spaces, through every tool.
- An agent with the `agent` role cannot change any member's role, its own included.
- A write to a node held by another stream is refused, with the holder's name.
- A use outside `mayUse` is refused at write time.
- A child's change to its own interface is refused; the same change by the parent's
  holder is accepted.
- A draft whose checks fail merges nothing; a draft whose checks pass merges all of its
  changes at once.
- Two drafts that change one cell: the first merges, the second goes to the parent's holder.
- `zoom` on a level-2 line returns its two level-1 lines; `zoom` on a level-0 line returns
  the original message.
- Two streams on sibling nodes get contexts whose first three parts are the same, byte for
  byte.
- `verified` is set on a node exactly when its checks pass and all its children are
  `verified`.
- Saving a cell makes its `nif`, `interface`, `uses` and `card` once; saving the same text
  again makes nothing.
- A change to a cell's body that keeps its interface sends no notice; a change to its
  interface reaches every stream on a cell that uses it, as one line at its next step.
- A rename by structured edit changes every use in one change, and the build passes.
- A context assembled from `kv` facets scores within a set margin of the same context read
  as text, on the exam.
- `ask(@p, S, …)` returns a value of `S`'s result type, or fails; never a value of another
  shape. A human asked answers through a form made from the types.
- Asking without a grant to ask `@p` is refused before `@p` hears of it.
- A change to an operator's `route` row moves its agents to the new model; askers' code and
  results' types do not change.
- `all` of three requests takes about as long as the slowest of them.
- `review … until … at most 3 times` sends the work back with the reviewer's words, and
  stops after the third time.
- Work made by asking replays from its runs without asking anyone again.
- A request over the asker's budget waits in the giver's inbox.
