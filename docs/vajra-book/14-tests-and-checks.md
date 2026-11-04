# 14. Tests and checks

A check is how a program, a person or the model knows a thing is right. In Yantra every
check is code that runs and says pass or fail, with the evidence. The same checks guard
the Atlas, judge the model's work, and reward it in training: what is not checked is not
learned.

## 14.1 Tests beside the code (built)

```text
test "an empty title is refused":
  expect "a task needs a title":         # must fail, saying this; its changes are undone
    Task.create(title = "")
  Task.create(title = "plan")
  check Task.count == 1
```

- A test is a cell beside the app. `vajra test` (or the `test` tool) runs them all, each in
  a transaction that is always undone (runtime suite, t_mcp).
- The output is one `ok` or `FAIL` line per test and `N passed, M failed`; a failure exits
  with 1.

## 14.2 The checks Yantra has

| Check | What it proves | Status |
|---|---|---|
| `test` cells | an app's behaviour | **built** |
| the gate (`tools/vajra-gate.sh`) | every suite at 0 failed, and pixel parity | **built** |
| `parity` | an app draws exactly the pixels of the original | **built** (t_mcp, the gate) |
| `render` | an app, drawn by the real engine after taps, as a PNG | **built** (t_mcp) |
| the judge (`tools/judge`) | a Nimony program gives the right output on every test, in time | **built** (selftest 7/0) |
| replay (`tools/train/replay.nim`) | a compiler change makes its failing tests pass | **built**: on Nimony's two newest candidate commits it kept `70e931a` (its new test failed before, passed after) and turned down `7c607a5` (its tests passed both before and after); 737 s per commit |
| `hastur test` | the compiler's own tests | **built** (Nimony) |
| property tests | a rule holds for many generated inputs | **planned** |
| recorded replays | a game or an app given the same inputs ends in the same state | **planned** |
| budgets | a node stays within its time and memory (§16.4) | **planned** |
| the style check | kept text follows §17.3 | **planned** |
| a person's pick | which of two results is better (taste) | **planned** |

## 14.3 Property tests

```text
test "a transfer keeps the total" for a, b: Account, amount: INR in ₹1 .. ₹10_000:
  let before = Account.total(balance)
  transfer(a, b, amount)
  check Account.total(balance) == before
```

The test runs for many generated values; a failure prints the smallest values that fail.
**planned**

## 14.4 Checks as rewards

The model is trained on tasks whose checks are hidden from it (the model plan):
- **The exam is never trained on.** LiveCodeBench, and about 5% of every other source by a
  hash of each task's id, are marked `exam` (helper order 0009).
- **Visible and hidden tests.** In a task, the model sees some tests; it is judged on all.
  The sampler shows the first failing visible test in full, and names a hidden one without
  showing it.
- **A check must fail without the work.** A task counts only if its check fails before the
  change and passes after it: replay keeps only the commits whose new tests fail on the
  commit before.
- **A check must not be weakened to pass.** A change that edits a test, a checker or a task
  is judged by the unchanged one.

## 14.5 Tests

Built: the runtime suite, the atlas suite, t_views, t_mcp, t_live, the judge's selftest,
t_sample, t_agent.

Planned (each one is a task):
- A property test of `transfer` finds a seeded bug that loses a rupee, and prints the
  smallest amounts that show it.
- A recorded replay of the tasks app, run twice, ends with the same rows and the same
  pixels.
- A node over its time budget fails its check with the time it took.
- A model's change that edits a hidden test still fails the original hidden test.
