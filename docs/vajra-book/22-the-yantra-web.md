# 22. The Yantra web

One web of typed objects. What people publish (a post, a video, a question, an app) is
an object with an address. Every site is a lens: a way to choose, rank and lay out
objects. The social actions (react, comment, follow, share, remix) are the same for
every object, everywhere. All of it is **planned**; what it stands on is noted where it
is **built**.

## 22.1 Objects

An object is a record that carries the shared envelope:

```text
record Video
  object                         # the envelope (below)
  title: string
  stream: Blob                   # adaptive video, made by the Video extension
  length: Duration
  captions: seq[Caption]
  search title
```

The envelope, the same on every object:

| Field | Meaning |
|---|---|
| `author: User` | who published it |
| `home: Space` | where it lives and whose rules hold |
| `address` | `y:@space/…`, the one address it has everywhere (**built** for apps and screens) |
| `made`, `changed` | from the row's envelope (**built**) |
| `visible` | `everyone`, `followers`, `members` (of its space), or `me` |
| `language`, `tags` | for lenses and search |
| `replyTo: Object?` | what it answers |
| `remixOf: Object?` | what it was made from |

- Bytes are blobs found by their SHA-256 (**built**): the same bytes are kept once, and any
  machine can serve them.
- An object embeds another by its address: a post holds a live app, a document a running
  chart, an answer a video from 2:14.
- An app is an object too. Its code is cells; opening its address runs it, sandboxed, as
  the person who opened it (**built** for apps and screens).

## 22.2 Kinds of object

Each kind is an extension (§0.5) with five parts:

| Part | Video | Question | App | Image | Model3D |
|---|---|---|---|---|---|
| record | title, stream, length, captions | title, body, accepted answer | cells, version, grants it asks | picture, size | mesh, materials |
| editor | upload, trim, chapters | write, tag | the Vajra editor | edit, crop | the 3D editor |
| player | adaptive player | thread with answers | runs it | viewer | 3D viewer |
| signals | watch time, finishes | votes, accepted | people using it, keeping it | likes, saves | views, remixes |
| work | FFmpeg to adaptive streams, thumbnails, captions by a speech model | duplicates found by meaning | builds, its tests | sizes, descriptions | levels of detail |

A new kind of object is a new extension. Nothing else changes.

## 22.3 The social actions

One extension, `@yantra/social`, for every kind:

| Action | Record | Notes |
|---|---|---|
| react | `Reaction(on, kind)` | like, and the reactions a lens allows |
| comment | a `Post` with `replyTo` | a comment is an object, so threads nest and can be reacted to |
| follow | `Follow(target)` | a person, a space, a tag, a kind |
| share | a `Post` that embeds the object | |
| remix | an object with `remixOf` | remixing an app copies its cells into your space |
| save | `Saved(object, list)` | into named lists |
| report | `Report(object, reason)` | to the moderators of the object's home |

```text
v.react(like)
Post.create(text = "the drone shot at 2:14", replyTo = v)
me.follow(@asha)
let mine = app.remix(into = @me/sandbox)
```

## 22.4 Lenses: the sites

A lens is a cell: a choice of objects, a ranking, and a view.

```text
lens Watch at "/watch"
  shows Video
  where visible == everyone and not hidden
  rank by watchScore(it, me)           # a function in a cell: anyone can read it or change it
  view VideoPage

lens Ask at "/questions"
  shows Question
  rank by votes, then newest
  view QuestionList
```

- A lens is open: anyone can read its ranking, copy the lens, and change it.
- A person chooses the lenses they use. There is no single ranking for everyone.
- One object shows in every lens that chooses it: the same video in a feed, an answer, a
  course and a channel.
- Ranking runs where the data is: counts and recency in Postgres, closeness of meaning
  with vectors (**built**: `nearest`), signals from the change log.

## 22.5 Sites with communities

A site is a space, with its lenses and its rules:
- who may post, who moderates, what is allowed (`can` lines and grants, **built**);
- its moderators are roles in the space (**built**);
- its address is `y:@space`;
- agents help moderate, under the site's rules and grants (§19).

A Q&A site, a video channel, a game studio's community, a school and a ministry's portal
are each a space with lenses.

## 22.6 Organisations, government, projects, teams

The same objects, actions and lenses, kept private:
- An organisation is a tree of spaces (**built**); its intranet is lenses over its private
  objects: `Task`, `Project`, `Doc`, `Decision`, `Meeting`, `Approval`.
- A project is the work tree of §16.3 for any work: items move through allowed states, are
  held by people or agents, need approvals, and carry budgets.
- Government adds approval chains, audit views (§18.4), data kept in its own country, and
  the change log that nobody can forge (**built**).
- Public or private is only `visible`. A company's internal Q&A, a public Q&A site and a
  classroom's Q&A are one extension, seen through three lenses.

## 22.7 How it holds at the size of the world

One database cannot hold the whole web. So:
- **Every space has one home Atlas.** Its rules run there, and its data lives there. An
  organisation or a government runs its own, in its own country.
- **Public objects are copied, read-only, to other Atlases.** A copy says where its home
  is. A change happens only at home, and reaches the copies through the change log.
- **The change log is the feed of everything.** Search, rankings and timelines are records
  the database works out from it (`derive`, §3), never copies made by hand.
- **Bytes are served from anywhere,** because a blob's name is its SHA-256: a copy cannot
  be wrong.
- **A device holds the spaces its person uses** (§8), so most reads never leave it.

## 22.8 Tests

Planned (each one is a task):
- A `Video` posted once appears in two lenses that choose it; a reaction made in one lens
  is counted in both.
- A comment on an app and a comment on a video are the same kind of record.
- A lens's ranking is a cell another person can read, copy and change; the copy ranks the
  same objects its new way.
- An object with `visible == members` never appears in a lens viewed by a non-member.
- Remixing an app puts a copy of its cells in the remixer's space; changing the copy leaves
  the original unchanged; the copy's `remixOf` names the original.
- A public object copied to a second Atlas cannot be changed there; a change at its home
  reaches the copy.
- A blob served by a copy has the same SHA-256 as at its home.
