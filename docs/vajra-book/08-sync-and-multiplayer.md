# 8. Sync and multiplayer

Every device works offline, and every change reaches everyone who may see it, in real
time. Many people can work on one thing at once, and their work merges. A program says
what its data is; the Atlas decides how it syncs and how it merges. **planned**, on the
foundations noted as **built**.

## 8.1 What a device holds

- A device holds a copy of the spaces its person uses, in its own Postgres: the full
  server on a computer, PGlite (Postgres compiled to wasm) where a full server cannot run.
- It holds only the rows its person may read. The rules that decide this are the same
  `can` lines as on the server (**built**), applied when the rows are sent.
- An app reads and writes the copy on the device. A read never waits for the network.

## 8.2 How changes travel

- Every change is already in one log (`atlas.change`, **built**): the row as it became,
  who made it, for whom, from which app.
- A device sends the changes it made since its last sync, and receives the changes made
  since it last received. With a network, this happens as they happen; without one, when
  it comes back.
- Ids are UUIDv7 (**built**): a device makes new rows offline, and their ids never collide.
- The server applies a device's change as that person, under the same rules (**built**:
  row security). A device cannot send what its person may not write.

## 8.3 How changes merge

A field's type says how two changes to it merge:

| Field | When two devices change it | Example |
|---|---|---|
| a plain value | the later change wins (by a hybrid clock, not the device's clock alone) | `title: string` |
| `counter` | the changes add up | `views: counter` |
| a list or a set | additions from both are kept; a removal removes | `tags: seq[string]` |
| `Text` | both people's typing is kept, in order (a CRDT: Automerge or Loro, wrapped) | `body: Text` |
| an ordered list | each item has a position between its neighbours, so two moves do not clash | `order: Position` |
| a link | the later change wins; a link to a row that was deleted becomes a conflict | `customer: Customer` |

```text
record Doc
  title: string
  body: Text                     # many people type at once, offline too
  views: counter
  editors: seq[User]
  can read, write: me in editors
```

- Rules are checked again when changes merge. A merge that breaks a `check` or a
  `unique` becomes a conflict: a record the person sees, with both versions, to choose
  from.
- A sealed field merges as a plain value, without being opened.

## 8.4 Presence

`presence` on a view shows who else is there: their cursor, their selection, what they are
typing. It travels live and is never stored (`memory`, §17).

```text
view DocPage(d: Doc)
  presence d                     # cursors and selections of everyone in this document
  TextEditor d.body
```

## 8.5 Games

A game's world is a fast, in-memory state on each device (§10). Multiplayer games use
**rollback**: each device runs the same deterministic step on the same inputs; when a late
input arrives, it steps back and replays. This needs the step to be deterministic, which
the game tests already check by replaying recorded inputs (§14).

## 8.6 Tests

Planned (each one is a task):
- Two devices, offline, each change a `Doc`'s title; after sync both show the later change.
- Two devices, offline, each type into the same `Text`; after sync both show both texts,
  in the same order on both.
- Two devices each add 1 to a `counter` offline; after sync it is 2 higher on both.
- A device cannot send a change its person may not write; the server refuses it, and the
  device shows the refusal.
- A merge that breaks a `unique` becomes a conflict record with both versions.
- A device receives no row its person may not read, in any sync.
- A rollback game replays a late input and ends in the same state on both devices.
