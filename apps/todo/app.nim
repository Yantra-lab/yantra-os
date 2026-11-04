## Todos — one list, four readings of it: what is open, what is done, what is next
## and how much of it is finished. Tasks are records the person owns, so every
## count on screen is a reading of the same rows; a host with no database shows a
## preview list instead of an empty page, and says so.

const proof = 0   # the doc line heads this cell, so the palette stays `const`
let bg = #0B0B10
let surface = #101017
let rowTint = #1C1C26
let line = #32323E
let ink = #F4F3F8
let muted = #8E8C9A
let faint = #8E8C9A
let accent = #5B5BF6
let amber = #FFB23E

record Task
  title: string
  done: bool = false
  due: Date?
  priority: int = 2
  owner: User = me
  can read, write: owner
  check title != "", "a task needs a title"
  search title

## One line of the list: what the row draws. `key` is the record's id; a row of
## the preview list has none.
type TaskRow = object
  key: string
  title: string
  done: bool
  whenLabel: string
  rank: string
  priority: int

var dbReady = false      ## the last read reached a database

if Task.count == 0:
  Task.create(title = "Draft the Meta submission", due = today + 1days, priority = 1)
  Task.create(title = "Record the 90-second demo", due = today + 2days, priority = 1)
  Task.create(title = "Send the press kit to three editors", due = today + 3days, priority = 2)
  Task.create(title = "Pick the desk lamp for the studio", due = today - 1days, priority = 3, done = true)

func stripe(p: int): Color =
  result = line
  if p == 1: result = amber
  elif p == 2: result = accent

func rank(p: int): string =
  result = "Later"
  if p == 1: result = "High priority"
  elif p == 2: result = "Normal"

func whenLabel(d: Date?, on: Date): string =
  result = "Anytime"
  if d.isSome:
    let gap = int((d.get(on) - on).days)
    if gap < 0: result = "Overdue"
    elif gap == 0: result = "Today"
    elif gap == 1: result = "Tomorrow"
    elif gap < 7: result = $gap & " days"
    else: result = $d.get(on)

func whenInk(label: string, finished: bool): Color =
  result = muted
  if not finished and (label == "Overdue" or label == "Today"): result = amber

proc readRows(): seq[TaskRow] =
  ## The list as the database holds it. A host with no database raises on the
  ## first query: that is a preview host, and `dbReady` records which it is.
  result = @[]
  dbReady = false
  try:
    for t in Task.sort(done, due):
      result.add TaskRow(key: t.id, title: t.title, done: t.done,
                         whenLabel: whenLabel(t.due, today), rank: rank(t.priority),
                         priority: t.priority)
    dbReady = true
  except:
    dbReady = false

proc previewRows(): seq[TaskRow] =
  ## Enough rows to see the list work: 22 of them, two long enough to truncate.
  result = @[]
  result.add TaskRow(title: "Draft the Meta submission", whenLabel: "Today", rank: "High priority", priority: 1)
  result.add TaskRow(title: "Record the 90-second demo", whenLabel: "Tomorrow", rank: "High priority", priority: 1)
  result.add TaskRow(title: "Send the press kit to three editors", whenLabel: "3 days", rank: "Normal", priority: 2)
  result.add TaskRow(title: "Grandmaster: rehearse the walkthrough on the projector until the words come out in the same order twice",
                     whenLabel: "4 days", rank: "Normal", priority: 2)
  result.add TaskRow(title: "Pick the desk lamp for the studio", whenLabel: "Overdue", rank: "Later", priority: 3)
  result.add TaskRow(title: "Rebuild the engine from this tree and quote its sha256", whenLabel: "Today", rank: "High priority", priority: 1)
  result.add TaskRow(title: "Answer the judges' three questions in one page", whenLabel: "Tomorrow", rank: "Normal", priority: 2)
  result.add TaskRow(title: "Print the label for the demo machine", whenLabel: "Overdue", rank: "Later", priority: 3)
  result.add TaskRow(title: "Take the six paintings out of the gallery", whenLabel: "5 days", rank: "Later", priority: 3)
  result.add TaskRow(title: "Delete the placeholder apps", whenLabel: "Anytime", rank: "Normal", priority: 2)
  result.add TaskRow(title: "Bring the typewriter's Foley into the mix", whenLabel: "6 days", rank: "Later", priority: 3)
  result.add TaskRow(title: "Write the empty state for every list", whenLabel: "Today", rank: "High priority", priority: 1)
  result.add TaskRow(title: "Book the room for the run-through", whenLabel: "Anytime", rank: "Later", priority: 3, done: true)
  result.add TaskRow(title: "Rod the microphone stand", whenLabel: "Anytime", rank: "Later", priority: 3, done: true)
  result.add TaskRow(title: "Read the release notes out loud once", whenLabel: "Anytime", rank: "Normal", priority: 2, done: true)
  for i in 1 .. 7:
    result.add TaskRow(title: "Field task " & $i, whenLabel: "Anytime", rank: "Later", priority: 3, done: (i mod 2 == 0))

proc loadList(): seq[TaskRow] =
  result = readRows()
  if not dbReady: result = previewRows()

proc indexAt(rows: seq[TaskRow]; at: int): TaskRow =
  ## One row, read by a proc: `rows[i].field` written inline traps the module.
  result = TaskRow(key: "", title: "", done: false, whenLabel: "", rank: "", priority: 2)
  if at >= 0 and at < rows.len: result = rows[at]

proc withRow(rows: seq[TaskRow]; at: int; r: TaskRow): seq[TaskRow] =
  ## The list with one row replaced, as a whole-list assignment.
  result = @[]
  for j in 0 ..< rows.len:
    if j == at: result.add r else: result.add indexAt(rows, j)

proc withoutRow(rows: seq[TaskRow]; at: int): seq[TaskRow] =
  result = @[]
  for j in 0 ..< rows.len:
    if j != at: result.add indexAt(rows, j)

proc openCount(rows: seq[TaskRow]): int =
  result = 0
  for j in 0 ..< rows.len:
    if not indexAt(rows, j).done: inc result

proc doneCount(rows: seq[TaskRow]): int =
  result = rows.len - openCount(rows)

proc doneShare(rows: seq[TaskRow]): int =
  result = 0
  if rows.len > 0: result = 100 * doneCount(rows) div rows.len

proc priorityCount(rows: seq[TaskRow]; p: int): int =
  result = 0
  for j in 0 ..< rows.len:
    if indexAt(rows, j).priority == p: inc result

proc matching(rows: seq[TaskRow]; tab: string): seq[int] =
  ## The rows a filter keeps, as indices into `rows`.
  result = @[]
  for i in 0 ..< rows.len:
    let r = indexAt(rows, i)
    if tab == "All" or (tab == "Done") == r.done: result.add i

proc keepRow(r: TaskRow) =
  ## Writes one row back through the record; a preview row is already where it lives.
  if r.key.len == 0: return
  try:
    discard Task.find(r.key).update(title = r.title, done = r.done)
  except:
    discard

proc newRow(title: string): TaskRow =
  result = TaskRow(key: "", title: title, done: false, whenLabel: "Today", rank: "Normal", priority: 2)
  try:
    let fresh = Task.create(title = title, due = today)
    result.key = fresh.id
    dbReady = true
  except:
    dbReady = false

proc dropRow(r: TaskRow) =
  try:
    if r.key.len > 0: Task.find(r.key).delete()
  except:
    discard

view Todo
  state rows: seq[TaskRow] = loadList()
  state db: bool = dbReady
  state tab = "All"
  state draft = ""
  state listY = 0.0
  state problem = ""
  state lastDone = ""
  # the draw works from a copy: a borrow of the state seq here would stop the
  # handlers below from writing it ("borrowed and cannot be mutated", measured)
  var all: seq[TaskRow] = @[]
  for j in 0 ..< rows.len: all.add indexAt(rows, j)
  let shown = matching(all, tab)
  let openN = openCount(all)
  let doneN = doneCount(all)
  let share = doneShare(all)
  Row(fill = bg, height = 900px, grow = 1, alignItems = 3):
    on key:
      let k = lastKey()
      if k.code == keyEscape and tab != "All":
        tab = "All"
        handled()
    Column(grow = 1, padTop = 24px, padBottom = 20px, padLeft = 28px, padRight = 24px, gap = 16px):
      Row(gap = 14px, alignItems = 1):
        Panel(fill = accent, radius = 13px, width = 46px, height = 46px, justify = 1, alignItems = 1):
          Path d = "M20 6L9 17L4 12", size = 22px, stroke = 2.6px, color = #FFFFFF
        Column(gap = 3px, grow = 1):
          Text "Todos", size = 28px, weight = 700, color = ink
          Text "{openN} open · {doneN} done · {all.len} in all", size = 13px, color = muted
        Text "{today}", size = 12px, color = muted
      Row(gap = 10px):
        Input draft, placeholder = "What needs doing?", size = 15px, color = ink,
              fill = rowTint, border = 1px, borderColor = line, radius = 12px,
              padTop = 13px, padBottom = 13px, padLeft = 14px, padRight = 14px, grow = 1
        Button "Add task", size = 14px, weight = 600, fill = accent, color = #FFFFFF,
               radius = 12px, padTop = 13px, padBottom = 13px, padLeft = 20px, padRight = 20px:
          on tap:
            if draft.strip().len == 0:
              problem = "A task needs a title — type one first."
            else:
              rows.add newRow(draft.strip())
              draft = ""
              problem = ""
              tab = "All"
      Row(gap = 8px, alignItems = 1):
        Button "All · {all.len}", size = 13px, fill = (if tab == "All": accent else: rowTint),
               color = (if tab == "All": #FFFFFF else: muted), radius = 9px,
               padTop = 8px, padBottom = 8px, padLeft = 14px, padRight = 14px:
          on tap: tab = "All"
        Button "Open · {openN}", size = 13px, fill = (if tab == "Open": accent else: rowTint),
               color = (if tab == "Open": #FFFFFF else: muted), radius = 9px,
               padTop = 8px, padBottom = 8px, padLeft = 14px, padRight = 14px:
          on tap: tab = "Open"
        Button "Done · {doneN}", size = 13px, fill = (if tab == "Done": accent else: rowTint),
               color = (if tab == "Done": #FFFFFF else: muted), radius = 9px,
               padTop = 8px, padBottom = 8px, padLeft = 14px, padRight = 14px:
          on tap: tab = "Done"
        Text "{shown.len} shown", size = 12px, color = muted, grow = 1
        if shown.len > 8:
          Button "▲", size = 11px, weight = 600, fill = surface, color = muted, radius = 7px,
                 border = 1px, borderColor = line, padTop = 5px, padBottom = 5px, padLeft = 9px, padRight = 9px:
            on tap: listY = max(0.0, listY - 336.0)
          Button "▼", size = 11px, weight = 600, fill = surface, color = muted, radius = 7px,
                 border = 1px, borderColor = line, padTop = 5px, padBottom = 5px, padLeft = 9px, padRight = 9px:
            on tap: listY = listY + 336.0
      if problem.len > 0:
        Row(gap = 7px, alignItems = 1):
          Panel(width = 6px, height = 6px, radius = 3px, fill = amber)
          Text problem, size = 12px, weight = 600, color = amber, grow = 1
      Column(gap = 8px, grow = 1, scroll = true, scrollTo = listY):
        if shown.len == 0:
          Column(gap = 8px, padTop = 26px, padBottom = 20px, alignItems = 1):
            Panel(width = 44px, height = 44px, radius = 22px, fill = rowTint, justify = 1, alignItems = 1):
              Path d = "M20 6L9 17L4 12", size = 18px, stroke = 2.4px, color = accent
            Text (if all.len == 0: "A list with nothing on it yet" else: "Nothing under this filter"), size = 20px, weight = 700, color = ink, align = 1
            Text (if all.len == 0: "Type the first task in the field above and press Add task — it becomes a row you own, not a line in a file."
                  else: "Every task here is either open or done. This filter has none of them right now."),
                 size = 13px, color = muted, lineHeight = 1.5, align = 1, maxLines = 2
            if all.len > 0:
              Button "Show every task", size = 13px, weight = 600, fill = accent, color = #FFFFFF,
                     radius = 10px, padTop = 10px, padBottom = 10px, padLeft = 16px, padRight = 16px:
                on tap: tab = "All"
            Text "Tab moves · Enter ticks a task · Ctrl+N is the field above", size = 11px, color = muted
        else:
          for i in shown:
            let r = indexAt(all, i)
            Row(gap = 13px, fill = rowTint, radius = 12px, padTop = 13px, padBottom = 13px,
                padLeft = 14px, padRight = 10px):
              Panel(width = 3px, height = 34px, radius = 2px, fill = stripe(r.priority))
              Panel(width = 22px, height = 22px, radius = 6px, border = 2px,
                    borderColor = (if r.done: accent else: line),
                    fill = (if r.done: accent else: rowTint), justify = 1, alignItems = 1):
                on tap:
                  var next = indexAt(rows, i)
                  next.done = not next.done
                  keepRow(next)
                  rows = withRow(rows, i, next)
                  lastDone = (if next.done: "Ticked: " else: "Reopened: ") & next.title
                if r.done:
                  Path d = "M20 6L9 17L4 12", size = 13px, stroke = 2.4px, color = #FFFFFF
              Column(gap = 4px, grow = 1):
                Text r.title, size = 15px, color = (if r.done: muted else: ink), maxLines = 1
                Row(gap = 6px):
                  Text r.whenLabel, size = 11px, color = whenInk(r.whenLabel, r.done)
                  Text "·", size = 11px, color = muted
                  Text r.rank, size = 11px, color = muted
              Button "×", size = 13px, fill = surface, color = muted, radius = 8px,
                     padTop = 7px, padBottom = 7px, padLeft = 9px, padRight = 9px:
                on tap:
                  dropRow(indexAt(rows, i))
                  rows = withoutRow(rows, i)
                  lastDone = "Removed"
      Row(gap = 7px, alignItems = 1):
        Panel(width = 6px, height = 6px, radius = 3px, fill = (if lastDone.len > 0: accent else: line))
        Text (if lastDone.len > 0: lastDone else: "Every count on this page is a reading of the same rows."),
             size = 11px, color = muted, grow = 1
        Text (if db: "record Task  /  owner only" else: "preview list  /  no database here"),
             size = 10px, color = muted
    Panel(width = 1px, fill = line)
    Column(gap = 14px, width = 300px, padTop = 24px, padBottom = 20px, padRight = 24px):
      Column(gap = 10px, fill = surface, border = 1px, borderColor = line, radius = 16px, pad = 18px):
        Text "YOUR LIST", size = 10px, weight = 700, color = muted
        Row(gap = 30px):
          Column(gap = 2px):
            Text "{openN}", size = 32px, weight = 700, color = ink
            Text "open", size = 12px, color = muted
          Column(gap = 2px):
            Text "{doneN}", size = 32px, weight = 700, color = muted
            Text "done", size = 12px, color = muted
        Panel(fill = rowTint, radius = 3px, height = 6px):
          Panel(fill = accent, radius = 3px, height = 6px, width = (240 * doneN div max(1, all.len)))
        Text "{share}% of the list is done", size = 11px, color = muted
      Column(gap = 8px, fill = surface, border = 1px, borderColor = line, radius = 16px, pad = 18px):
        Text "UP NEXT", size = 10px, weight = 700, color = muted
        if openN > 0:
          for i in matching(all, "Open"):
            if indexAt(rows, i).priority == 1:
              Text indexAt(all, i).title, size = 15px, weight = 600, color = ink, maxLines = 2, lineHeight = 1.3
              Row(gap = 6px):
                Text indexAt(all, i).whenLabel, size = 12px, color = whenInk(indexAt(rows, i).whenLabel, false)
                Text "·", size = 12px, color = muted
                Text indexAt(all, i).rank, size = 12px, color = muted
          Button "Complete it", size = 13px, weight = 600, fill = accent, color = #FFFFFF,
                 radius = 10px, padTop = 10px, padBottom = 10px:
            on tap:
              var done = 0
              for i in matching(all, "Open"):
                if done == 0 and indexAt(rows, i).priority == 1:
                  done = 1
                  var next = indexAt(rows, i)
                  next.done = true
                  rows = withRow(rows, i, next)
                  keepRow(next)
                  lastDone = "Ticked: " & next.title
        else:
          Text "All clear — nothing open.", size = 13px, color = muted
      Column(gap = 8px, fill = surface, border = 1px, borderColor = line, radius = 16px, pad = 18px):
        Text "BY PRIORITY", size = 10px, weight = 700, color = muted
        Row(gap = 9px):
          Panel(width = 8px, height = 8px, radius = 4px, fill = amber)
          Text "High priority", size = 13px, color = ink, grow = 1
          Text "{priorityCount(all, 1)}", size = 13px, color = muted
        Row(gap = 9px):
          Panel(width = 8px, height = 8px, radius = 4px, fill = accent)
          Text "Normal", size = 13px, color = ink, grow = 1
          Text "{priorityCount(all, 2)}", size = 13px, color = muted
        Row(gap = 9px):
          Panel(width = 8px, height = 8px, radius = 4px, fill = line)
          Text "Later", size = 13px, color = ink, grow = 1
          Text "{priorityCount(all, 3)}", size = 13px, color = muted
      Text "Todos · written in Sutra, running on Yantra OS", size = 10px, color = muted, maxLines = 2, lineHeight = 1.6
