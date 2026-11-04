# 19. Agents that serve people

An agent works for someone. A person, a shop, a school or a ministry deploys it with a
charter: whom it serves, whom it talks to, what it may do, and what needs approval. It
works through grants (§0.4), so it can never do more than its charter gives it. Built
under it: agent persons, the MCP door, sessions, supervisors, acting for someone
(§16, **built**). The rest is **planned**.

## 19.1 A charter

```text
charter Shopkeeper in y:@asha-store
  serves @asha                                  # the principal
  talks to anyone who messages y:@asha-store    # the audience
  may read Product, Stock
  may create Order, up to ₹50_000 each
  may take payment through y:@asha-store's payments
  may refund, up to ₹2_000 each; above that, ask @asha
  may call model image, video, copy; up to ₹500 a day
  never promises a delivery date that Stock does not support
```

- `serves`: the principals. Their inbox gets approvals, questions and a daily summary.
- `talks to`: the audience. Each person in it gets their own thread (§19.2).
- `may`: grants, each with its limit. Above a limit, the action waits for a principal.
- `never`: a rule the agent's actions are checked against before they happen.
- A charter is a record. Changing it is a change in the log, made by a principal.

## 19.2 Threads: one conversation, one small space

Every conversation between the agent and one person of its audience is a thread: a small
space whose members are that person, the principal's space, and the agent.

- In a thread the agent acts **for both sides at once**, and sees only what both allow:
  the shop's catalog and stock, and what this customer shared in this thread. The Atlas
  already gives an agent acting for someone only what both of them may (`acting_for`,
  **built**); a thread extends this to the shop and the customer together.
- It never sees another customer's thread. Postgres refuses it, whatever a customer types.
- The customer sees the thread and every promise made in it. The principal sees the
  thread unless the customer's data in it is sealed.

## 19.3 Words become records

Whatever the agent agrees to becomes a record: an `Order`, a `Payment`, a `Refund`, a
`Booking`, a `Promise` with a date. So:
- what was agreed is never only in a chat log;
- the money side is in the ledger (§20);
- a dispute starts from records both sides can read.

## 19.4 Approvals

An action above a grant's limit, or one that cannot be undone, becomes an `Approval` in
the principal's inbox, with what the agent wants to do and why. The agent tells the
customer it is waiting, and goes on with other work. When the principal answers, the
action runs, or the agent tells the customer no.

## 19.5 One agent, many specialists

An agent is a team:
- **the lead** plans, talks to people, and decides;
- **specialists** take parts of the work: a designer, a programmer, a 3D artist, a video
  editor, a copywriter, an accountant, a translator. Each one is a session (§16.10), and
  may use a different model (§12).
- They share one beginning of context (§16.9), so their working memory on the GPU is
  shared too. The work tree and drafts (§16.3, §16.6) keep them from colliding.
- A specialist has only the grants the lead passed to it, for that piece of work.

## 19.6 Memory, by thread and by principal

- **Per thread:** that person's history with the agent: what they asked, bought and
  prefer, kept with their consent and readable by them.
- **Per principal:** what the agent learned for the shop: what sells, the policies, the
  answers to common questions.
- Both are summary trees (§16.8), and follow §17's rules on what to keep.

## 19.7 The same pattern everywhere

| Principal | Agent | Audience |
|---|---|---|
| a shop | shopkeeper | buyers |
| a clinic | front desk | patients (health data `sensitive`, §17) |
| a school | tutor | students and their parents |
| a ministry | helpline | citizens |
| a family | assistant | the family |
| a game | characters | players |
| a creator | studio crew | their audience and their collaborators |

## 19.8 Tests

Planned (each one is a task):
- In thread A, the agent cannot read anything a customer wrote in thread B, by any tool.
- A refund of ₹1,500 runs at once; a refund of ₹2,500 becomes an `Approval` for @asha, and
  runs only after she approves.
- A charter's `never` rule blocks an action that breaks it, and the agent says why.
- A specialist cannot use a grant that the lead did not pass to it.
- Everything the agent agreed to in a thread is a record the customer can read.
- A change to a charter is in the change log, made by a principal; an agent cannot change
  its own charter.
