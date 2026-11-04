# 4. Graphs

Every link is an edge. A record that links to others is already a graph; Vajra adds the
words to walk it, match patterns in it, find paths, and run the graph algorithms a graph
database runs. The checklist is ISO GQL (the 2024 graph query standard) and Neo4j's
algorithm library. Walks, patterns and paths run inside Postgres, in the same transaction
as everything else (§2.7). Heavy algorithms over very large graphs (PageRank over billions
of links) may run as jobs on a consistent snapshot, in a native engine that uses every core
and the GPU (§6, §7), and write their results back as derived fields.

## 4.1 Built

- A field whose type is a record is a link; `seq[Person]` is many links; a record may link
  to itself. **built**
- `Person.where(name == "Cy").follow(friends, upto = 3)` walks one kind of link a number of
  steps, as a query that composes with `where`, `sort` and `count`. **built**
- Links read like fields, in code and in queries: `o.customer.name`,
  `where(customer.name == "Ada")`. **built**

## 4.2 Edges with fields

```text
record Follows
  follower: Person
  followed: Person
  since: Date
  strength: float = 1.0
  edge                             # a link that is a record of its own: its first two links are its ends
```

`edge` lets queries walk `Follows` as a link from its first link (`follower`) to its second
(`followed`), and read its fields on the way. **planned**. (An end cannot be named `from`: it
is a word of the language, and `from: Person` does not parse.)

## 4.3 Patterns

```text
Person.named("cy").via(follows, worksAt).where(company.name == "Acme")
Person.via(follows * 1..4).to(Person.named("ada"))         # one to four steps
Person.via(follows, optional livesIn)                      # a step that may be missing
Product.via(boughtWith).where(it != p).ranked              # bought together, most often first
```

| Feature | Status |
|---|---|
| several kinds of link in one pattern | **built**: `via(friends, firm)`, up to 4 steps (runtime suite) |
| paths of any length, with bounds | **built**: `via(friends * 1..3)`, also inside a pattern (runtime suite) |
| an optional step | **planned** |
| a path as a value: its nodes, its edges, its length | **planned** |
| create a pattern if it is not there | **planned** |

`via` is a query word: each step goes through one link (a link, a maybe-link or a list
of links) to the rows of the record it links to, so `Member.where(name == "Bo").via(friends,
firm)` is a query of `Firm`, checked when the program is built, and composes with `where`,
`sort` and `count`. `link * a..b` repeats one link, keeping the rows `a` to `b` steps away.
Only rows the person may read are walked.

## 4.4 Paths

```text
let p = shortest(ada, cy, via = follows)                    # fewest steps
let route = shortest(home, office, via = roads, cost = length)   # weighted
let routes = shortest(home, office, via = roads, cost = time, best = 3)
```

Fewest steps, weighted (Dijkstra), with a guide (A*), and the k best. Inside Postgres for
small graphs (recursive queries, pgRouting); in the native engine for large ones.
**built**: fewest steps, `shortest(ada, cy, via = friends)` (also `upto = 6`, the most
steps looked at): the rows on the way, both ends included, empty when none is found; links
are followed in their direction, no row twice, only rows the person may read (runtime
suite). Weighted, guided and the k best: **planned**.

## 4.5 Algorithms

| Family | Algorithms | Example |
|---|---|---|
| importance | PageRank, degree, betweenness, closeness | `Person.rank(follows, by = pagerank)` |
| communities | connected parts, strongly connected, label propagation, Louvain | `Person.communities(follows)` |
| similarity | Jaccard, cosine over neighbours | `Product.similar(p, via = boughtWith)` |
| embeddings | node vectors from the graph | `Person.embed(follows)` into a `Vector` field |
| links likely to form | from neighbours and embeddings | `Person.likelyLinks(follows)` |

Results are written back as fields the database keeps current (`derive`, §3), so a lens
can rank by them (§22). **planned**

**built** (runtime suite), inside Postgres over the rows the person may read:
`Person.all.rank(friends, by = pagerank)` (each row with its PageRank by that link, highest
first), `rank(friends, by = degree)` (how many links point to each row), `Person.all
.communities(friends)` (the groups links join, either way, as lists, the largest first) and
`Product.all.similar(p, via = tags)` (the rows sharing most of p's links: shared over all,
p itself left out). They run over a record's rows, optionally filtered without program
values; on billions of links they belong to the native engine (planned).

## 4.6 Rules over graphs

```text
derive Reachable(a, b: Person) =
  follows(a, b) or (follows(a, x) and Reachable(x, b))
```

A rule that refers to itself is kept current as its links change. **planned**

## 4.7 The graph as it was

Every link has its history (**built**: the change log), so `asOf(t)` works on a walk too:
the graph as it was on any day. **planned**

## 4.8 Each graph word, exactly

- **`edge`**: a record with exactly two links named `from` and `to` (of any records). It is
  walked from `from` to `to`; `via(follows.back)` walks it the other way, `via(follows.both)`
  either way. Its other fields are read on the way: `via(follows where since > 2025-01-01)`.
- **`via`** is the one word for walking. A step is a link field or an edge; steps in a list
  are taken in order; `l * a..b` repeats a step from `a` to `b` times (at most 32; more
  needs `* a..b, deep`); `optional l` is a step that may be missing (the row stays, the rest
  of its walk is `none`). The result is rows of the record the walk ends on, so it composes
  with `where`, `sort`, `take`, `count`. `follow(l, upto = n)` is the same as
  `via(l * 1..n)`.
- **No cycles by default.** A walk visits each row at most once; `via(…, cycles)` allows
  revisits for walks bounded by length.
- **`Path[T]`**: `.paths` on a walk, or `shortest`, gives values with `nodes: seq[T]`,
  `edges`, `length` and `cost`.
- **`shortest(a, b, via = l, cost = f, best = k)`** gives a `Path?` (`none` when `b` cannot be
  reached), or with `best` the `k` cheapest as a `seq[Path]`. `cost` must be a number field of
  the link or edge, never negative (a negative one fails to build or, read at run time,
  fails the call).
- **`ensure`** a pattern: creates what is missing of it, never a second copy:
  `ensure ada.via(follows).to(cy)` makes the `Follows` row only if there is none.
- **Algorithms** write their results as `derive`d fields (§3), recomputed when the links
  change, or on a schedule for the heavy ones: `derive rank = Person.rank(follows, by =
  pagerank), every 1h`.

## 4.9 Tests

Built: the runtime suite's `follow` checks.

Planned (each one is a task):
- `via(follows, worksAt)` returns exactly the people a hand-written two-step query finds.
- `shortest` agrees with Dijkstra written by hand on 10,000 random weighted graphs.
- PageRank on a known graph matches the published values within 1e-6.
- `communities` on two cliques joined by one edge gives two communities.
- `Reachable` stays correct after 1,000 random link changes.
- A walk `asOf` last week does not use a link made today.
- The native engine and Postgres give the same answers on graphs both can hold.
- `follow(l, upto = 3)` and `via(l * 1..3)` give the same rows.
- A walk on a graph with a cycle ends, and visits no row twice.
- `shortest` to a row that cannot be reached is `none`; a negative cost fails.
- `ensure` twice makes one `Follows` row.
