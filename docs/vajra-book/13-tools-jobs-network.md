# 13. Tools, jobs and the network

How a program reaches beyond its screen: programs a person runs from the command line,
work on a schedule, long work that survives crashes, and the network. Each reach is a
grant (§0.4), so a program gets only what it was given.

## 13.1 Tools (built)

```text
tool subst(file: Path, pattern: string, by: string)
  file.write(file.read.replace(regex(pattern), by))
```

- A `tool` cell is a program a person runs: `vajra tool y:@me/kit.subst notes.txt "\d" "#"`.
- A `Path` or `Folder` parameter is the file or folder the person names, and it is all the
  tool may read or write; a path it makes up, or `..` out of a folder, is refused.
- It reads what is piped in, prints, and ends with `quit n`; it runs as the person, so it
  may use the app's records too. (runtime suite)
- Files: `read`, `write`, `append`, `exists`, `lines`, `remove`, `moveTo`, `copyTo`, `name`;
  folders: `files`, `folders`, `dir / "name"`, `dir.folder("name")` (made if missing),
  `remove`. Moving or copying needs both paths to be the tool's; a folder the person handed
  over cannot be removed. (runtime suite)
- Names: `dir.files("*.csv")` and `name.matches("a?c*")` (`*` any run, `?` one character);
  `for f in dir.walk` gives every file in every folder below. (runtime suite)

## 13.2 Schedules (built)

`every day at 9:00:` runs once for each person who uses the app, at 9:00 on their own
clock, as that person. Schedules from every 15 minutes to monthly; `vajra tick` runs what is
due; each run's result is kept in `atlas.job_run`. (runtime suite)

## 13.3 Flows: long work

```text
flow Delivery
  order: Order
  step pack
  step ship: wait until order.paid
  step remind: after 3days unless order.delivered
  step close
```

- A flow's state is rows: which step it is on, and what it waits for. A crash, a restart or
  a new machine resumes it at its step.
- `wait until` waits for a condition on records; `after` waits for a time; both wake
  through the change log and `vajra tick`.
- An agent's session (§16.10) is a flow; so is a render, an order, a training run.

**built** (runtime suite): a `flow` cell's fields and steps; its state is a record of the
same name (the step it is on, since when, done), kept by the database, so a crash or a new
machine resumes it at its step. A step's first lines may wait: `wait until parcel.paid`
(until the condition holds), `after 3days` (that long after the step began), `after 3days
unless parcel.paid` (skipped at once when the condition holds, else waits, then runs the
rest). `Delivery.start(parcel = p)` makes one and runs it as far as it can go; `vajra tick`
advances every unfinished one as the person who started it. Waking through the change log
the moment a condition can change, rather than at the next tick: **planned**.

## 13.4 Queues (planned)

`queue` on a record (§3.2): each row is held by one worker at a time, retried, and kept as
failed after its tries. Many workers on many machines take from one queue.

## 13.5 The network (built, and planned)

```text
uses network "api.openweathermap.org"
uses secret "weather" -> "api.openweathermap.org"

let w = fetch("https://api.openweathermap.org/data/2.5/weather?q=Pune&appid=" &
              secret("weather")).json(Weather)
```

**built:** `fetch` only to declared hosts, over https, never following a redirect; a
secret goes only into requests to the host it is declared for, so the app never sees it.

**planned:**
- `serve`: an app answers requests at its address, for webhooks and its own API:
  `serve post "/hooks/payment": …`, each request a transaction, as the caller's person.
- Mail and messages out (mail, SMS, chat services) as providers behind grants (§12), metered
  (§20).
- Live connections to other Yantra spaces through sync (§8), never by hand.

## 13.6 Tests

Built: the runtime suite (tools, `every`, `fetch`, secrets).

Planned (each one is a task):
- A `flow` killed between two steps resumes at the second one after `vajra tick`.
- `wait until order.paid` wakes within one tick of the order being paid.
- A `serve` handler that fails undoes its changes and answers with an error.
- A request to a host the app did not declare is refused, and names the host.
