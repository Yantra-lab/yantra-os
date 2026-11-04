# 15. Formatting and style

Every cell has one look, whoever wrote it. One way to write each thing means fewer
mistakes, easier review, and code the model's drafter can predict (the model plan). Kept
text follows §17.3.

## 15.1 The typesetter (built)

The Atlas typesets every cell when it is saved (`host/atlas/typeset.nim`). Only whitespace
moves, never a value: no trailing spaces, at most one blank line in a row, and in a record
or an extension the names, types, defaults and comments line up in columns (atlas tests:
"cells are typeset when kept").

## 15.2 The formatter (planned)

The typesetter grows into a full formatter, still changing only layout:
- one line width (100), and one rule for where long lines break;
- inside a record, a fixed order: fields, then computed fields, then `can` lines, then
  checks and `unique`, then `search` and `index`, then the lines of §3.2;
- inside a view: `state`, then `param`, then the tree;
- the same spacing around every operator, the same indent everywhere.

## 15.3 Names

- A name says what a thing is, in plain words: `dueToday`, not `dt`; `Order`, not `OrderObj`.
- Records and views are nouns in `UpperCamel`; routines are verbs or nouns in
  `lowerCamel`; one word for one thing across the whole Atlas.
- No prefixes that repeat the type or the module: a cell already lives in its module.

## 15.4 Comments

- `##` on a cell is its card: what it does, at most three sentences (§16.4, §17.3). The
  Atlas reads it into the cell's card, so `find` finds a cell by what it does (**built**).
- `#~` is the model's thinking, in short lines, anywhere in the code (the model plan). The
  build ignores it; the Atlas keeps it with the cell's version.
- `#` is a note for the next reader: why, never what.

## 15.5 One way to write each thing

| Thing | The one way | Not |
|---|---|---|
| all the rows of a record | `Order.count`, `for o in Order` | `Order.all().len` |
| a missing value | `T?` and `nothing` | a sentinel (`-1`, `""`) |
| a call with no arguments that reads a value | `Order.count`, `t.history` | `Order.count()` |
| text with values | `"{x} of {n}"` | `$x & " of " & $n` |
| a span of time | `3days` | `3 * 24 * 3600` |
| a share | `50%` | `0.5` where a share is meant |

**planned:** the formatter rewrites the "Not" column into the "one way" column.

## 15.6 Tests

Built: the typesetter's atlas test.

Planned (each one is a task): the formatter, run twice, changes nothing the second time;
it never changes what a program does (the tests of every cell it formats still pass); a
record's lines come out in the order of §15.2.
