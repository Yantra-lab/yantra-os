---
name: yantra-doc-coauthoring
description: "Guide a user through a structured workflow for co-authoring documentation — writing docs, proposals, technical specs, decision docs, RFCs or similar structured content. Trigger when the user mentions writing docs, drafting a proposal or spec, or a similar documentation task. The workflow itself is tool-independent and carries over intact; what changes is that in Yantra the document is a program, so structure decisions become code structure decisions."
license: Proprietary. Translated from Anthropic's `doc-coauthoring` skill; see NOTICE.md.
---

# Doc co-authoring in Yantra

**This skill translates almost completely.** Anthropic's `doc-coauthoring` skill is a
*workflow*, not a tool: context gathering, refinement, reader testing. None of it depends on
python-docx or OOXML. What changes in Yantra is the last mile — where the document lives.

Keep that framing in mind: this is the one of the five translated skills where almost every
line of the original survives. The parts that change are marked.

---

## When to offer this workflow

**Trigger conditions:**
- "write a doc", "draft a proposal", "create a spec", "write up"
- "PRD", "design doc", "decision doc", "RFC"
- any substantial writing task

**The offer.** Explain the three stages:

1. **Context gathering** — the user provides everything relevant while you ask clarifying
   questions.
2. **Refinement & structure** — build each section by brainstorming and editing.
3. **Reader testing** — test the doc with a fresh agent that has no context, to catch blind
   spots before other humans read it.

Explain that this makes the doc work when others read it — including when they paste it into
an agent. Ask whether they want the workflow or would rather work freeform.

**In Yantra, add one question the original does not ask:** *is this a document to read, or a
document that is also a program?* A Yantra doc can be a `.nim` file whose pages export to
PDF, and that changes how you structure the source. It does not change the workflow.

If the user declines, work freeform. If they accept, go to Stage 1.

---

## Stage 1 · Context gathering

**Goal:** close the gap between what the user knows and what you know, so later guidance is
smart rather than generic.

### Initial questions

Ask for the meta-context first:

1. What type of document is this? (technical spec, decision doc, proposal)
2. Who is the primary audience?
3. What should happen when someone reads it?
4. Is there a template or format to follow?
5. Any other constraints or context?

Tell them they can answer in shorthand or dump information however works best.

**If they have a template or name a doc type:** ask to see it. If it is a shared document,
fetch it. If it is a file, read it. *(In Yantra: a Yantra-format document is a `.nim` file —
you can read it directly. A `.docx` or `.pdf` you would read with host-side tooling; see
the `yantra-docx` skill.)*

**If they mention editing an existing shared document:**
- Read the current state.
- **Check for images without alt-text.** If images exist without it, explain that an agent
  reading the doc will not see them. Offer to generate descriptive alt-text — ask them to
  paste each image in.

### Info dumping

Encourage them to dump everything, unorganised. Ask for: background on the project or
problem; related discussions; **why alternatives aren't being used**; organisational context;
timeline pressure; technical architecture or dependencies; stakeholder concerns.

Say explicitly: don't worry about organising it, just get it out.

**On integrations:** if Slack/Teams/Drive/SharePoint or MCP servers are available, mention
they can pull context in directly. If not, say so plainly and ask them to paste the content.
*(A Yantra app can `fetch` only the hosts its window lists, over https —
`app("Name", net = "example.com")`, `sdk/core/net.nim`. That is not a substitute for a Slack
connector, but it is enough to pull a document from an internal API.)*

**During gathering:**
- If they mention a channel or doc and integrations exist, tell them you will read it now,
  then read it.
- If they name an entity or project you don't know, **ask before searching.**
- Track what you're learning and what is still unclear.

### Clarifying questions

When they signal they've dumped enough, ask **5-10 numbered questions** aimed at the gaps.
Tell them they can answer in shorthand (`1: yes, 2: see #channel, 3: no because backwards
compat`), link to docs, point at channels, or keep dumping.

**Exit condition:** enough context gathered that your questions show understanding — you can
ask about edge cases and trade-offs without explaining the basics.

**Transition:** ask whether there is more context to add, or whether to start drafting.

---

## Stage 2 · Refinement & structure

**Goal:** build the document section by section.

Tell the user the process: for each section you will (1) ask clarifying questions about what
belongs in it, (2) brainstorm 5-20 options, (3) take their keep/remove/combine decisions,
(4) draft, (5) refine through surgical edits.

**Section ordering.** Start with whichever section has the most unknowns — usually the core
decision in a decision doc, the technical approach in a spec. Leave summaries for last. If
they do not know what sections they need, suggest 3-5 appropriate ones and ask if that
structure works.

**Create the scaffold** — every section header with a placeholder like `[To be written]`.
In a Yantra document this is literal: it is a `.nim` file, and a section can be a
`{.component.}` proc that renders a page or a slide. Building the scaffold first means the
structure is a thing you can both point at.

### For each section

**Step 1 — clarifying questions.** 5-10 specific questions about what this section should
include.

**Step 2 — brainstorming.** 5-20 numbered options, scaled to the section's complexity. Look
for forgotten context and angles not yet mentioned. Offer to brainstorm more.

**Step 3 — curation.** Ask what to keep, remove, or combine, with brief justifications —
those teach you their priorities for later sections. Give examples: *"Keep 1,4,7,9"*, *"Remove
3 (duplicates 1)"*, *"Combine 11 and 12"*. If they give freeform feedback ("looks good, but…"),
extract the preferences and apply them.

**Step 4 — gap check.** Ask if anything important is missing for this section.

**Step 5 — drafting.** Replace the placeholder with the drafted content, then ask them to
read it and say what to change.

> **Say this when drafting the first section:** instead of editing the doc directly, tell me
> what to change. "Remove the X bullet — covered by Y" or "make the third paragraph tighter."
> That teaches me your style for the remaining sections.

**Step 6 — iterative refinement.** Make surgical edits; never reprint the whole document.

*(This maps directly onto a Yantra source file: edit the one `{.component.}` proc, not the
whole app. And the same rule holds for the medium — a reader who asks for a change is
teaching you their preferences. Note those changes down and apply them to later sections.)*

### Quality checking

After **3 consecutive iterations with no substantial changes**, ask whether anything can be
removed without losing information. When a section is done, confirm it and ask about moving on.

### Near completion (80%+)

Re-read the whole document and check for: flow and consistency across sections; redundancy
or contradiction; anything that feels like generic filler; whether every sentence carries
weight. Give feedback.

Then review overall coherence, completeness, and ask whether to move to reader testing.

---

## Stage 3 · Reader testing

**Goal:** test the document with a fresh agent that has no context bleed.

### If sub-agents are available (Claude Code)

Do the testing directly, without involving the user.

1. **Predict reader questions.** Generate 5-10 questions a reader would realistically ask
   when discovering this document.
2. **Test with a fresh sub-agent.** For each question, invoke a sub-agent with only the
   document content and the question. Summarise what it got right and wrong.
3. **Additional checks.** A sub-agent looks for ambiguity, false assumptions and
   contradictions.
4. **Report and fix.** State the specific issues, fix the gaps, loop back to refinement.

### If sub-agents are not available

The user tests manually:

1. Generate the reader questions.
2. Have them open a fresh conversation and paste the document.
3. For each question, ask for the answer, plus: what was ambiguous, and what knowledge the
   doc assumes.
4. Ask additionally: *"What in this doc might be ambiguous?"*, *"What knowledge does it
   assume?"*, *"Are there internal contradictions?"*
5. Fix what came back weak.

### Exit condition

The document is ready when a fresh reader consistently answers correctly and surfaces no new
gaps or ambiguities.

---

## Final review

When reader testing passes:

1. Recommend the user do a final read themselves — they own the doc and its quality.
2. Suggest double-checking facts, links and technical details.
3. Ask them to confirm it achieves the impact they wanted.

Then, if done: consider linking the conversation in an appendix so readers can see how the
doc was developed; use appendices for depth without bloating the main doc; update the doc as
feedback arrives from real readers.

---

## Tips

- **Tone:** direct and procedural. Explain rationale briefly when it changes user behaviour.
  Don't sell the approach — execute it.
- **Deviations:** if they want to skip a stage, offer to write freeform. If they seem
  frustrated, acknowledge it and offer a faster route. Always give them agency.
- **Context management:** whenever something mentioned is unclear, ask. Don't let gaps
  accumulate.
- **Quality over speed.** Don't rush. Each iteration should make a meaningful improvement.
  The goal is a document that actually works for readers.

---

## What changes in Yantra

Carried over verbatim, because it does not depend on the tool:

- The entire three-stage workflow.
- The 5-10 clarifying questions, the 5-20 brainstorming options, the curation step.
- The "tell me what to change instead of editing it directly" instruction.
- The 3-iterations-with-no-change threshold for cutting.
- Reader testing with a fresh agent, and the exit condition.

Changed, and worth knowing:

| Original | Yantra |
|---|---|
| "Create the scaffold" in an artifact or a `.md` file | a `.nim` file: one `{.component.}` proc per section, rendered into `page`/`slide` nodes |
| "Follow the user's spec literally — exact section headers" | headers are `text` nodes with `size`/`weight`; "literal" now includes the visual hierarchy |
| The deliverable is a document others read | the deliverable can also be a **live app** — a document with interactive elements, or one that exports to a real vector PDF via `yantra-pdf` |
| A doc is a fixed artefact | a Yantra doc is source code — diffable, reviewable, version-controlled, and generated from data |

**One caution.** A Yantra document that *also* runs is a stronger deliverable, but it adds a
failure mode the original workflow does not have: it might not compile. Before declaring a
Yantra document done, `bash tools/build-wasm.sh doc.nim out/doc.wasm` must succeed, and if
it has pages, `yantra-pdf` must report the page count you expect.

---

## Dependencies

None. This is a process.

## Provenance

Translated from Anthropic's `doc-coauthoring` skill (fetched from
`anthropics/skills`, `skills/doc-coauthoring/SKILL.md`). Because the original is
tool-independent, almost all of it is preserved; only the deliverable-handling notes were
rewritten for Yantra.