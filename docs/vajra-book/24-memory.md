# 24. Memory

What every agent knows, remembers and learns lives in the Atlas as records: typed, linked,
searched in every way Postgres can, guarded by row rules, and visible and editable live.
A model sees its memory as blocks of its context; a block that changes is recomputed, and
the blocks before it are not. This extends §16.8 (the summary tree) and §17 (what to
store). What is built is marked; the rest is **planned**.

## 24.1 Five kinds of memory

| Kind | What it holds | Kept as |
|---|---|---|
| **Working** | what a session is thinking about now | its context on the GPU; moved to RAM when it pauses (docs/conductor.md) |
| **Events** | everything that happened, in order | `atlas.agent_step` (**built**), and the summary tree over it (§16.8) |
| **Knowledge** | facts, rules, decisions, preferences, lessons | typed records (§24.2) |
| **Skills** | ways of doing things that worked: playbooks and example cells | `Skill` records and verified cells (§24.5) |
| **The map** | what exists and how it connects: nodes, people, records | the work tree (§16.3), links and graphs (§4) |

## 24.2 Knowledge is typed records

```text
type MemoryKind* = enum fact, rule, decision, preference, lesson, question

record Memory
  kind: MemoryKind
  line: string                     # one claim, written as §17.3 says
  scope: TreePath                  # where it holds: yantra / yantra.atlas / yantra.atlas.sessions.412
  about: seq[Link]                 # the nodes, records and people it is about
  because: seq[Link]               # the evidence: steps, tests, documents, people
  confidence: float = 1.0
  validFrom: Time = now            # when it became true
  validUntil: Time?                # when it stopped being true
  supersedes: Memory?              # the memory it corrects
  uses, wins: int = 0              # how often it was recalled, and how often that work passed
  meaning: Vector                  # its embedding, for search by meaning
  author: User = me
  can read: me in readersOf(scope)
  can write: author or holdsScope(scope)
  search line
```

- **Nothing is overwritten.** A correction is a new memory that `supersedes` the old one; the
  old one stays, with when it stopped being true. Every edit is in the change log (**built**).
- **Every memory says why** (`because`): the step, the test or the document it came from.
  `zoom` (§16.8) follows it back to the original.
- **Contradictions are kept side by side,** flagged, with their evidence, until someone in
  charge of the scope settles them.

## 24.3 Scopes: how the memory of agents and their helpers relates

Scopes nest like spaces (`TreePath`, **built**):

```text
yantra                          the laws: the book, the Owner's charter
 yantra.atlas                   one product or project
  yantra.atlas.team-sync        one team
   yantra.atlas.team-sync.s412  one session (an agent)
    ….s412.s418                 its helper
```

- **Reading flows down.** A helper reads its own scope and every scope above it: its lead's,
  its team's, the project's, the laws. It never reads a sibling's private scope.
- **Writing stays where you are.** An agent writes to its own scope. To write higher, it
  proposes: the holder of that scope (the team lead, Kimi, the Owner) accepts, edits or turns
  it down. So one helper's guess never becomes the whole team's truth.
- **A team blackboard.** Team scope also has notes every member appends to, each signed; the
  lead promotes the ones that hold.
- **When a helper finishes,** its summary goes up to its lead as the result, and its accepted
  lessons are promoted; its full event log stays in its own scope, and can be zoomed into.
- **A helper started by forking** (§16.7) begins with its parent's context and its parent's
  memory blocks, so it starts knowing everything its parent knew.
- **Permissions decide, as everywhere:** a helper never reads more than the agent that
  started it may read; sealed and secret things are never memory.

## 24.4 Memory as blocks of context

A session's context is built from memory blocks, always in the same order (§16.9), from
the most stable to the most changing:

1. the laws (the book, the charter);
2. the project's memory;
3. the team's memory;
4. the node's memory: its brief, contract, decisions, lessons and open questions;
5. what was recalled for this task (§24.6);
6. the session's own memory and its summary-tree view;
7. the live part: changes since the blocks were last built, and the task.

- **Each block is text made the same way every time:** same order, same layout. So two
  sessions with the same scopes get byte-for-byte the same beginning, and the GPU computes it
  once for all of them.
- **A block is named by the hash of its text.** When a memory changes, only its block and the
  blocks after it are recomputed.
- **Real time without waste.** A change made while sessions run is first added to block 7
  (the end of the context: nothing before it is recomputed), and every session that can see
  that scope gets it at its next step, through Postgres's notifications (**built**:
  `atlas_agent`). At the next quiet point, the change is folded into its own block.

## 24.5 Skills

```text
record Skill
  name: string                     # "port a Yoga layout rule"
  when: string                     # when it applies, in one sentence
  steps: seq[string]
  examples: seq[Cell]              # verified cells that show it
  scope: TreePath
  uses, wins: int = 0
```

A skill is written when the same kind of task has passed several times; it is recalled
when a similar task starts, and its `wins` say whether it still works.

## 24.6 Recall: what an agent sees without asking

When a task starts, the Atlas recalls memories and skills for it, from four directions at
once, in one query:
- by **meaning** (vectors, **built**: `nearest`),
- by **words** (full-text search, **built**),
- by **links**: memories about the nodes the task touches, and their neighbours (§4),
- by **scope** and **recency**,

ranked by how often each one helped work pass (`wins / uses`). The best fit block 5. The
agent can always ask for more (`recall`), or open anything by its link (`zoom`).

## 24.7 Seeing and editing memory, live

Tools, through the MCP door (each **planned** there). In the harness (`tools/agent`),
`remember`, `recall` and `zoom` over a session's steps are **built** (`t_agent`); the rest
are **planned**:

| Tool | What it does |
|---|---|
| `remember` | write a memory in your scope, with its evidence |
| `propose` | propose a memory for a scope above yours |
| `accept`, `refuse` | for the holder of a scope: settle a proposal |
| `revise` | correct a memory: a new one that supersedes it |
| `retire` | mark a memory no longer true, with why (it stays, with its end time) |
| `recall` | search memory every way at once |
| `zoom` | open a memory's evidence, or a summary line's parts |
| `blocks` | see exactly which memory blocks are in your context, and their hashes |

The Owner sees the same memory as a Yantra view: every scope, live, with who wrote what,
why, and how often it helped.

## 24.8 Memory that improves with use

- Every recalled memory counts a `use`; when the work it helped with passes its checks, a `win`.
  Recall ranks by that, so useful memories rise and useless ones sink, without retraining
  any model.
- A memory that keeps losing is shown to the scope's holder to revise or retire.
- Memories that hold across many tasks become training data for the swarm model, so what the
  agents learn moves into the weights over time.

## 24.9 Tests

Planned (each one is a task):
- A helper reads its team's memory and not its sibling's private scope.
- A helper's `propose` to team scope is invisible to the team until the lead accepts it.
- A `revise` keeps the old memory, with its end time, and recall returns the new one.
- Two sessions with the same scopes get the same first five blocks, byte for byte.
- A memory written while a session runs reaches that session at its next step, at the end of
  its context, and its earlier blocks are not recomputed.
- A memory that helped 10 passing tasks ranks above one that helped 10 failing tasks.
- A memory from a sealed field cannot be written.
