# 5. Time and history

Time is a type, and every row remembers its past. Built unless marked.

## 5.1 Time (built)

```text
let due = today + 3days
if now - started > 90min: echo "running long"
let call = 2026-10-15.at(9:30, zone"Europe/London")
echo meeting.at(zone"Asia/Tokyo")       # 2026-10-16 01:00 Asia/Tokyo
```

- `Time` is an instant, `Date` a day, `Duration` a span, `TimeOfDay` a clock reading,
  `Zone` an IANA name with Postgres's rules (summer time and every past change).
- `here` is the person's zone, or the device's when they have none; `today`, `t.date`,
  `t.clock` and `$t` are in `here`.
- A time the clocks skip means the one an hour later; a time they show twice means the
  first.

## 5.2 On a schedule (built)

`every day at 9:00:` runs once for each person who uses the app, at 9:00 on their own
clock, as that person (§13.2).

## 5.3 History (built)

```text
let then = order.asOf(2026-10-01.at(9:00))   # none if it was not made yet
for c in order.history: echo "{c.version} {c.at} {c.by.handle}"
record Note
  text: string
  keep history 7 years
```

- Every change to every row is in `atlas.change`: who, when, for whom, from which app.
- `r.asOf(t)` and `r.history` cover only a row the person may see now.
- `keep history` sets how long; `vajra tick` removes older history, except for a row on
  legal hold. Sealed fields are never in the log.
- Every row says whether it may be training data (consent) and whether it is on legal hold.

## 5.4 Planned

- **Two clocks:** when a fact was true (valid time) and when the Atlas learned it
  (transaction time), so a correction to the past is itself a fact with its own time:
  `salary.asOf(valid = march, known = june)`.
- **The graph as it was** (§4.7) and **a lens as it was** (§22): `asOf` on a walk, a query
  or a feed.
- **Time series** with windows and coarser old data (§3.2).
- **Undo for a person:** the last change a person made in an app, undone as a new change.

## 5.5 Tests

Built: the runtime suite ("as it was at a moment", "history older …", zones, `every`).

Planned (each one is a task): a fact corrected in June for March shows the old value for
`known = may` and the new one for `known = july`; undo of the last change makes a new
version equal to the one before it.
