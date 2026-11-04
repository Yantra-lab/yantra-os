# 25. Notebooks: every result kept

Everything done in Yantra keeps its result, the way a notebook keeps the output under each
cell. A cell's history is its code and every result it ever gave: builds, runs, tests,
renders, judgements, training steps, evaluations and model calls. Nothing is lost, and any
result can be traced to the exact version of the code that gave it.

## 25.1 Runs (built)

`atlas.run` (`host/atlas/runs.nim`) keeps one row per result:

| Field | Holds |
|---|---|
| `cell`, `version` | the cell, and the version of it that ran |
| `kind` | `build`, `run`, `test`, `render`, `parity`, `judge`, `train`, `eval`, `model` or `note` |
| `by`, `session` | the person who ran it, and the agent session it was for |
| `started`, `ms` | when, and how long |
| `ok` | passed or not |
| `output` | what it printed (up to 20,000 characters) |
| `metrics` | its numbers: tests passed and failed, bytes, exit code, scores, losses, tokens |
| `artifacts` | the files it made, by their SHA-256 in the chunk store: images, videos, checkpoints |

- The MCP tools `build`, `run` and `test` record every result (**built**, t_mcp).
- `render` records its PNG as the run's file, kept once by its SHA-256; a failed render is
  kept too. `parity` records how many pixels it compared and how many differed (**built**;
  render in t_mcp).
- `runs` shows a cell's results, newest first, with what they printed, their numbers and
  their files; with `space` it shows the whole space, runs that belong to no cell too; `kind`
  keeps one kind (**built**, t_mcp, atlas tests).
- `notebook` shows an app as a notebook: its cells in the order they were made, each with
  its code and its latest result under it, and how many older results it has; a cell the
  person may not open is not there (**built**, t_mcp).
- A training round is a run of kind `eval` with no cell: the sampler's `--record:@space
  --as:<person>` keeps its model, tasks, samples, passes, pass rate, tokens and the judge's
  verdicts counted by kind as numbers, and its traces and the judge's results as files by
  hash (**built**, t_sample).
- Members of the space read results, and the files of any result they can read; whoever may
  write in the space records them. Row security decides, as everywhere (**built**, atlas
  tests).

## 25.2 Planned

- **Every kind recorded:** the judge's verdicts, every training step's losses and every
  evaluation's scores, every call to an image, video or audio model with its asset (§12).
- **A notebook view on screen:** the same notebook as a Yantra view, opening any older
  result, like a notebook you can scroll back through time (the agents' text form is
  `notebook`, above).
- **Comparing runs:** the same cell's metrics across versions, as a chart; which change made
  a test pass, a score rise or a render change.
- **Training as a notebook:** a training run is cells (the data query, the settings, the
  stages) whose results are its losses, checkpoints and exam scores, so a run can be read,
  repeated and compared like any other.
- **Repeatable:** a result names the code version and its inputs' hashes, so the same inputs
  give a check that the same result comes back.

## 25.3 Cells for now, cells for good: the terminal, replaced

Every cell has a lifetime, written as its first line and kept in the Atlas, not in the
code. **built** (atlas tests): `temporary` (it goes when its session ends: `endSession`),
`expires after 7days` (s, min, h, days, weeks; it goes that long after its last change, swept
by `vajra tick`), and a `keep` line, which makes either a kept cell. A cell that goes takes
its versions and its runs, except runs marked kept.

**built** (runtime suite): `vajra scratch @space --user:N`, the scratch page as a terminal.
Each entry (a line, or a block ending in `:` until an empty line) runs as it is written, as
that person, in a temporary cell that reaches the space's records by name; a bare value is
shown (`Order.count`); declarations (`proc`, `func`, `template`, `iterator`, `type`,
`const`) stay for the entries after, statements never run twice; `keep app.name` keeps what
was written as a cell; an empty line or `quit` ends the page and its cell goes. **planned**:
the same page on screen, and `keep` on a run.

| Lifetime | Written | What happens |
|---|---|---|
| kept | (the default for code in apps and libraries) | every version kept, for good |
| for the session | `temporary` | the cell lives as long as the session that made it (a scratch page, a notebook, an agent's session) and goes with it |
| for a time | `expires after 7days` | the cell goes that long after its last change |

A temporary cell is the terminal: write a line, run it, its result appears under it, and
the next line can use it. It does anything a terminal does, through tools (§13) and the
person's grants (§0.4): queries, builds, tests, deploys, git, files it is handed, the
network, schedules, and asking people and agents for work (§16.12).

```text
Order.where(at > today - 7days).group(status).count
build y:@asha-store/shop; test y:@asha-store/shop
deploy y:@asha-store/shop, to = production
ask(@yantra/coder, FixTest, test = "checkout pays once", in = y:@asha-store/shop)
keep                                        # this scratch cell becomes a kept cell
```

- A scratch cell's effects are worked out and checked like any cell's (§1.5); what the
  grants do not allow does not run.
- `keep` makes it a kept cell, with its history from then on; `expires after` gives it a
  time.
- Its runs are in the notebook while it lives; a run marked `keep` stays after the cell is
  gone.
- Nothing is a command outside the language: what a terminal command or an API call does is
  a tool or a service, typed, granted and kept.

## 25.4 Tests

Built: atlas tests ("a result is kept against the cell's version; members read it, a
stranger does not"; "a run's files are kept by their hash; members read them, a stranger
does not"; "the space's notebook shows every result, a round that belongs to no cell too, by
kind"); t_mcp ("every result is kept: runs shows the last run and test, newest first, with
what they printed"; "a render is kept as a run, with its picture kept by its hash"; "the
space's notebook lists every result of one kind, with the cell it came from"; "notebook
shows the app's cells in order with the latest result under each; a secret one is not
there"); t_sample
("the round is kept as one eval run, by the person it ran as, with its numbers"; "the
judge's verdicts are counted by kind"; "its first file is the traces, kept by their hash;
the second is the judge's results").
- A `temporary` cell is gone when its session ends, and so are its runs, except one marked
  `keep`.
- A cell that `expires after 1day` is gone a day after its last change.
- `keep` on a scratch cell makes it a kept cell whose next change is a new version.
- A scratch line whose effects the person's grants do not cover does not run, and says which
  grant is missing.
