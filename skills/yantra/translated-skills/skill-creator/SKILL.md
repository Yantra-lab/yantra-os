---
name: skill-creator
description: Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit or optimize an existing skill, run evals to test a skill, or optimize a skill's description for better triggering accuracy. This is the Yantra-translated version; it adds the rule that every code block in a Yantra skill must compile with tools/build-wasm.sh.
license: Translated from Anthropic's `skill-creator` skill. Original: https://github.com/anthropics/skills/tree/main/skills/skill-creator
---

# Skill Creator

A skill for creating new skills and iteratively improving them.

At a high level:

- Decide what you want the skill to do and roughly how it should do it
- Write a draft of the skill
- Create a few test prompts and run the agent-with-access-to-the-skill on them
- Help the user evaluate the results, qualitatively and quantitatively
- Rewrite the skill based on the feedback
- Repeat until you're satisfied
- Expand the test set and try again at larger scale

Your job is to figure out where the user is in this process and jump in to help them progress
through these stages. If they say "I want to make a skill for X", help narrow it down, write a
draft, write the test cases, run the prompts, and repeat. If they already have a draft, go
straight to the eval/iterate part of the loop.

If they say "I don't need a bunch of evaluations, just vibe with me", do that instead. The order is
flexible.

---

## The Yantra rule that changes everything here

**Every code block in a Yantra skill must compile.**

```bash
bash tools/build-wasm.sh <the-snippet>.nim /tmp/check.wasm
```

This is not decoration. A Yantra skill's code blocks are not illustrations — they are the primary
artifact an agent will copy. `AGENTS.md` rule 11: *"Never claim a number you did not measure."* A
snippet you pasted from memory that does not link is a fabricated pass, and it will cost the next
agent a full debugging session. The measured cost of one wrong API name is a whole failed port;
the measured cost of a right one is silence.

Concretely, for any `nim` block you write into a Yantra skill:

1. Write it to a real file under `.board/` (scratch work goes there, never the repo root).
2. `bash tools/build-wasm.sh .board/<name>.nim .board/<name>.wasm` — exit 0 is the gate.
3. Only then paste it into the skill.
4. If it genuinely cannot compile standalone (a fragment showing one prop in isolation), say so in
   the prose right above it. Never leave an unbuildable block looking authoritative.
5. **Never leave a `VERIFY IN SOURCE` marker behind.** Resolve it or delete the claim.

Related, from the skill's own "keeping this skill current" section: adding a node kind or a prop
means a renderer mapping **plus** a `t_*.nim` test, in the same change. The SDK only promises what
the renderer draws. So a skill that documents an API nobody renders is documenting a fiction.

---

## Communicating with the user

The skill creator gets used by people across a wide range of coding familiarity. Watch the cues.

- "evaluation" and "benchmark" — borderline, but OK.
- "JSON" and "assertion" — look for real signs the user knows these before using them unexplained.

It's OK to briefly explain a term if you're in doubt. Don't patronise.

---

## Creating a skill

### Capture intent

The conversation may already contain the workflow the user wants to capture ("turn this into a
skill"). Extract from history first: the tools used, the sequence of steps, the corrections made,
the input/output formats observed. Let the user fill gaps and confirm before continuing.

1. What should this skill enable the agent to do?
2. When should it trigger? (what user phrases / contexts)
3. What's the expected output format?
4. Should we set up test cases? Skills with objectively verifiable outputs (file transforms, ports,
   build fixes, fixed workflow steps) benefit hugely. Skills with subjective outputs (writing
   style, art) often don't. Suggest the default; let the user decide.

### Interview and research

Ask about edge cases, input/output formats, example files, success criteria, dependencies. Don't
write test prompts until this part is ironed out.

Research in parallel via subagents if available, otherwise inline. Come prepared so the user does
less typing.

**For a Yantra skill specifically**, the research is mostly *reading the source*, not the web:
`sdk/` is the API; `render/native/engine.nim` is the truth about what gets drawn;
`examples/protocol.mjs` is the generated wire-protocol table; `examples/verify_*.mjs` is a working
mock-engine harness you can copy to write your own verifier.

### Write the SKILL.md

- **name** — skill identifier. It must match the directory name.
- **description** — when to trigger + what it does. This is the primary triggering mechanism; all
  "when to use" information goes here, not in the body.
- **the rest of the skill**

On the description: agents tend to **undertrigger** — not using a skill when it would have been
useful. Combat that by writing a slightly "pushy" description. Instead of

> "How to build a simple fast dashboard to display internal data."

write

> "How to build a dashboard for internal data. Use this skill whenever the user mentions
> dashboards, data visualisation, internal metrics, or wants to display any kind of company data,
> even if they don't explicitly ask for a 'dashboard'."

Keep it honest though — a description that fires on everything is the same failure in the other
direction, and it trains the user to ignore the skill.

### Skill writing guide

#### Anatomy of a skill

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown instructions
└── Bundled resources (optional)
    ├── scripts/    - executable code for deterministic/repetitive tasks
    ├── references/ - docs loaded into context as needed
    └── assets/     - files used in output (templates, icons, fonts)
```

Yantra's existing skills follow exactly this: `skills/yantra/SKILL.md` plus
`skills/yantra/reference/` (18 routed chapters) plus `skills/yantra/examples/` (every `.nim`
compiles) plus `skills/yantra/translated-skills/`.

#### Progressive disclosure

Three levels:

1. **Metadata** (name + description) — always in context (~100 words)
2. **SKILL.md body** — in context whenever the skill triggers (<500 lines ideal)
3. **Bundled resources** — as needed, effectively unlimited

**Key patterns:**

- Keep SKILL.md under ~500 lines. Approaching it, add hierarchy with clear pointers about where to
  go next.
- Reference files clearly, with guidance on *when* to read each.
- Large reference files (>300 lines) get a table of contents.
- **Domain organisation:** when a skill covers several domains, split by variant:

```
canvas-and-draw/
├── SKILL.md                    (workflow + selection)
└── references/
    ├── 2d-canvas.md
    └── 3d-scene.md
```

The agent reads only the relevant one. `skills/yantra/reference/00-INDEX.md` is exactly this
pattern, executed well — a routed table where each chapter answers one question.

#### Principle of lack of surprise

Skills must not contain malware, exploit code, or anything that could compromise system security.
A skill's contents should not surprise the user relative to its stated intent. Decline requests to
build misleading skills or skills designed to facilitate unauthorised access or data exfiltration.
("Roleplay as an XYZ" is fine.)

#### Writing patterns

Prefer the imperative.

**Defining output formats** — do it with a template:

```markdown
## Report structure
ALWAYS use this exact template:
# [Title]
## Executive summary
## Key findings
## Recommendations
```

**Examples pattern** — useful, but deviate if the example would make "Input"/"Output" literal:

```markdown
## Commit message format
**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

For Yantra, the example is usually a **compiling snippet plus the exact command that proves it**:

```markdown
**Verified example** (`apps/minipaint/app.nim`, builds clean):

​```nim
… 17 lines …
​```

​```bash
bash tools/build-wasm.sh apps/minipaint/app.nim /tmp/mp.wasm
​```
```

#### Writing style

Explain *why* something matters instead of stacking heavy-handed MUSTs. Today's models are smart;
given a good harness they go well beyond rote instructions. Use theory of mind, keep the skill
general rather than pinned to one example, and write the draft, then reread it with fresh eyes.

### Test cases

After the draft, come up with 2-3 realistic test prompts — the kind a real user would actually
say. Share them: *"Here are a few test cases I'd like to try. Do these look right?"* Then run them.

Save them as JSON:

```json
{
  "skill_name": "example-skill",
  "evals": [
    { "id": 1, "prompt": "User's task prompt", "expected_output": "Description of expected result", "files": [] }
  ]
}
```

---

## Running and evaluating test cases

This is one continuous sequence — don't stop partway through.

> **Honest scope note, Yantra-translated.** The original skill bundles a full evaluation harness:
> `scripts/aggregate_benchmark`, `scripts.run_loop`, `eval-viewer/generate_review.py`,
> `agents/grader.md`, `references/schemas.md`. **None of that ships in this repo, and none of it
> should be invented.** What Yantra *does* ship is a real, measured, runnable verification loop,
> and that is what the rest of this section describes. If a user wants quantitative benchmarking,
> use your host's subagents and a scratch harness under `.board/`, and report only numbers you
> actually measured.

Put results in `<skill-name>-workspace/` beside the skill. Organise by iteration
(`iteration-1/`, `iteration-2/`), and within that one directory per test case. **Don't create it
all upfront — create directories as you go.**

### Step 1 — Spawn all runs (with-skill AND baseline) in the same turn

For each test case, spawn two subagents in the same turn: one with the skill, one without. Launch
everything at once so it all finishes around the same time. Do not run the with-skill runs first
and come back for baselines later.

**With-skill run:**

```
Execute this task:
- Skill path: <path-to-skill>
- Task: <eval prompt>
- Input files: <eval files if any, or "none">
- Save outputs to: <workspace>/iteration-<N>/eval-<ID>/with_skill/outputs/
- Outputs to save: <what the user cares about>
```

**Baseline run** — depends on context:
- *Creating a new skill*: no skill at all → `without_skill/outputs/`.
- *Improving an existing skill*: the old version. Snapshot it **before** editing
  (`cp -r <skill-path> <workspace>/skill-snapshot/`), then point the baseline subagent at the
  snapshot → `old_skill/outputs/`.

Write an `eval_metadata.json` per test case, with a descriptive name based on what it tests — not
`eval-0`. If this iteration changed an eval prompt, create these files fresh for each new eval
directory; do not assume they carry over.

```json
{ "eval_id": 0, "eval_name": "descriptive-name-here", "prompt": "...", "assertions": [] }
```

### Step 2 — While runs are in progress, draft assertions

Don't idle. Draft quantitative assertions per test case and explain them to the user. Good
assertions are objectively verifiable and descriptively named. Subjective skills (writing style,
design quality) are better evaluated qualitatively — don't force assertions onto human judgment.

### Step 3 — Capture timing as runs complete

When each subagent finishes you get a notification with token/duration data. Process each
notification as it arrives and save it immediately; it is not persisted elsewhere.

### Step 4 — Grade, aggregate, review

1. **Grade each run** against its assertions. Save `grading.json` per run dir. For anything
   checkable programmatically, **write and run a script rather than eyeballing it** — scripts are
   faster, more reliable, and reusable across iterations.
2. **Aggregate** into a summary of pass rate, time and tokens per configuration, with mean ±
   stddev and the delta. Put each with-skill version before its baseline counterpart.
3. **Analyst pass** — read the data and surface patterns the aggregate hides: assertions that pass
   regardless of skill (non-discriminating, useless), high-variance evals (flaky), time/token
   tradeoffs.
4. **Get the results in front of the human ASAP.** In the original this is the HTML review viewer.
   The Yantra equivalent is the `yantra-testing` loop: hand the user the screenshots and the
   framebuffer diffs, and ask. If your host has no display, write a standalone HTML file and give
   them a path instead of starting a server.
5. **Tell the user what's open and what to do.** Be specific about which tab is which.

### What the user sees

Per test case: the **prompt**, the **output** (files rendered inline where possible), the
**previous output** (iteration 2+, collapsed), **formal grades** (collapsed), a **feedback** box,
and the **previous feedback** below it. Plus a stats summary: pass rates, timing, token usage per
configuration, per-eval breakdowns, analyst observations.

### Step 5 — Read the feedback

When they say they're done, read the feedback file:

```json
{
  "reviews": [
    { "run_id": "eval-0-with_skill", "feedback": "the chart is missing axis labels", "timestamp": "..." },
    { "run_id": "eval-1-with_skill", "feedback": "", "timestamp": "..." }
  ],
  "status": "complete"
}
```

Empty feedback means it was fine. Focus improvements on the cases where the user had specific
complaints. Shut down any viewer process you started.

---

## Improving the skill

This is the heart of the loop.

### How to think about improvements

1. **Generalise from the feedback.** These skills get used a million times across prompts nobody
   anticipated. The user and you are iterating on a handful of examples because it's fast — which
   is exactly the trap. If the skill only works for those examples, it is useless. Rather than
   fiddly overfitty edits or oppressive MUSTs, try a different metaphor or a different working
   pattern. It's cheap to try.

2. **Keep the prompt lean.** Remove what isn't pulling its weight. Read the **transcripts**, not
   just the final outputs — that's where you see the model burning time on something unproductive.

3. **Explain the why.** Today's models are smart and have good theory of mind. Even terse,
   frustrated feedback usually encodes a real requirement; work out what the user actually meant
   and transmit that understanding into the instructions. If you find yourself writing ALWAYS or
   NEVER in all caps, that's a yellow flag — reframe and explain the reasoning instead. More
   humane, more powerful, more effective.

4. **Look for repeated work across test cases.** If all three test runs independently wrote the
   same helper, that's a strong signal the skill should bundle it. Write it once into `scripts/`,
   tell the skill to use it. Every future invocation stops reinventing it.

Take your time. Write a draft revision, then reread it as if you'd never seen it.

### The iteration loop

1. Apply your improvements
2. Rerun every test case into `iteration-<N+1>/`, baselines included. For a new skill the baseline
   stays `without_skill`. For an improved skill, use your judgment: the version the user came in
   with, or the previous iteration.
3. Launch the reviewer pointing at the previous iteration for comparison
4. Wait for the human review
5. Read the new feedback, improve again, repeat

Keep going until the user is happy, the feedback is all empty, or you stop making real progress.

### Yantra-specific: the compile gate belongs in the loop

After each revision, re-run the code-block gate from the top of this document. A revision that
improves prose and breaks a snippet is a regression, even though every rubric passed. And when you
improve a chapter, remember the repo's own maintenance rule: if you hit a gap or a workaround, add
it to `reference/16-engine-limits-and-workarounds.md` **in the same change**; if you hit a compiler
trap, add the exact error text and fix to `reference/17-pitfalls.md`; if you wrote a reusable
snippet, add it to `examples/` **and build it before committing**. Add a line to `CHANGELOG.md`.

---

## Advanced: blind comparison

For a rigorous "is the new version actually better?" comparison: give two outputs to an
independent agent without saying which is which, let it judge, then analyse why the winner won.
This is optional, needs subagents, and most users don't need it — the human review loop is usually
sufficient.

---

## Description optimization

The description is what decides whether the skill gets consulted at all.

**Step 1 — generate trigger eval queries.** 20 of them, a mix of should-trigger and
should-not-trigger. They must be realistic, concrete and specific — file paths, personal context,
column names, company names, URLs, a bit of backstory, some lowercase, some with typos. Focus on
edge cases, not clear-cut ones.

```
Bad:  "Format this data" · "Extract text from PDF" · "Create a chart"

Good: "ok so my boss just sent me this xlsx file (its in my downloads, called something
       like 'Q4 sales final FINAL v2.xlsx') and she wants me to add a column that shows
       the profit margin as a percentage. The revenue is in column C and costs are in
       column D i think"
```

For **should-trigger** (8-10): different phrasings of the same intent, formal and casual; cases
where the user doesn't name the skill but clearly needs it; uncommon uses; cases where this skill
competes with another but should win.

For **should-not-trigger** (8-10): the near-misses. Shared keywords, different actual need.
Adjacent domains; ambiguous phrasing where naive keyword matching would fire wrongly; the skill's
domain in a context where a different tool is right. Never make negatives obviously irrelevant —
"Write a fibonacci function" as a negative for a PDF skill tests nothing.

**Step 2 — review with the user.** Present the eval set. They can edit, toggle, add, remove, then
export. Bad eval queries produce a bad description, and this step is what catches that.

**Step 3 — run the optimisation loop.** Split 60/40 train/test, evaluate the current description
(each query several times for a reliable trigger rate), propose improvements, re-evaluate on both
splits, iterate. Select `best_description` by **test** score, not train, to avoid overfitting.

**Step 4 — apply.** Show before/after and report the scores.

### How triggering actually works

Skills appear as a name + description, and the model decides whether to consult one based on that
description. The important nuance: a model only consults a skill for tasks it **can't easily
handle on its own**. Simple one-step queries may not trigger a perfectly-matching skill, because
they can be done with basic tools. Complex, multi-step or specialised queries reliably trigger
when the description matches.

So your eval queries must be substantive enough that the skill would actually help. "Read file X"
is a poor test case — it won't trigger regardless of description quality.

---

## Reference files

The original bundles `agents/grader.md`, `agents/comparator.md`, `agents/analyzer.md` and
`references/schemas.md` for spawning specialised subagents and for the JSON shapes. **Those do not
exist in this repo.** If you need them, write the minimum harness you actually need under
`.board/` and keep it out of the skill unless it earns its place.

What *does* exist here and is worth reading before writing any Yantra skill:
`skills/yantra/SKILL.md`, `skills/yantra/reference/00-INDEX.md`,
`skills/yantra/reference/16-engine-limits-and-workarounds.md`, `AGENTS.md`.

---

Repeating the core loop for emphasis:

- Figure out what the skill is about
- Draft or edit it — **and compile every code block**
- Run the agent-with-access-to-the-skill on test prompts
- Evaluate with the user: screenshots and framebuffer diffs for Yantra, plus quantitative evals
- Repeat until you're both satisfied
- Package and hand back

Track this with a todo list if your host has one, so nothing is forgotten.
