# What Yantra is for — the owner's brief

> Written from the owner's own words (Sanskar Balpande, SVAROG SYSTEMS), 2026-11-05.
> This is the *why*. `AGENTS.md` is the *how*.

---

## One sentence

**One language, one engine — replacing the web and every professional creative tool.**

Not a framework, not a faster JavaScript. **The whole stack**: the language, the renderer,
the database, the shell, the browser, the editor, the app store, and eventually the operating
system — **built once, in one thing, so nothing has to be stitched together again.**

---

## The four promises

### 1. Every capability of the web — "in a very, very beautiful way"

**"Our own browser alternative for a new world."** Not a browser that renders other people's
HTML badly — **a runtime where an app is a few hundred lines and everyone shares the platform.**

| The web has | Yantra's answer |
|---|---|
| HTML/CSS | the `view` dialect — `Column`, `Row`, `Text`, `Button`, props |
| Canvas | `Canvas` + `Draw` verbs |
| WebGL / Three.js | `Scene3D` on Filament |
| fetch | `Net` on libcurl |
| localStorage | **the Atlas** (PostgreSQL, with RLS) |
| Workers | `Runtime` (wasmtime) |
| npm | **the app store** |
| the DOM | 237 KB wasm modules that draw natively |

### 2. Photoshop, Premiere, Blender, Nuke, Houdini, SolidWorks, a DAW — class capabilities

**"If there is anything that might be very hard, implement it as well. Like videos."**

The apps in this repo are the proof, not the product: a 3-D gallery, a paint program, a chess
engine, a film. The product is a runtime where **an agent or a person writes such an app in a
few hundred lines**, because the hard parts (colour, 3-D, media, layout, text) belong to the
platform.

### 3. A full OS — "beauty matching the best Hyprland rices"

An Arch distro that boots into Yantra, **runs as an app on any platform**, and looks like the
best of Caelestia / Omarchy / Dusky. **Not a desktop environment bolted onto Linux — the same
engine that draws the apps, drawing the desktop.**

### 4. A downloadable app for any PC, with a store

One binary, one store, apps installed and launched inside the same engine. **"We just want one
Yantra engine running, and it should run other apps — they shouldn't be standalone."**

---

## The doctrine (this is the part engineers keep forgetting)

> **Many forms, one meaning.**

Every capability must exist **once** and appear in **whatever form is natural**: a word in the
language, a `view` component, an op an agent calls, a record in the database, a JSON twin. **One
implementation, many spellings** — never two implementations that must be kept in agreement.

> **The database is the source of truth, not the files.**

Code, vocabulary, assets, documents and proofs live in PostgreSQL (the Atlas). Files on disk are
an export mirror. **A build that reads loose files is a build that can drift from what runs.**

> **Users should never care about performance.**

Yantra pushes any code to its absolute limits **by default** — there is no "release mode" to
opt into.

> **An absence-proof needs a presence-proof beside it.**

The rule that has cost the most: *"no work happens"* is satisfied by **never doing the work at
all.** Every optimisation needs a second test that the work happens when it should.

> **Revert first, argue second.**

Four lanes confirmed one bug for four hours; one revert closed it.

---

## What "done" looks like, in order

1. **An app a stranger writes in an afternoon**, with the language telling them the fix when
   they are wrong. *(The author's loop: `tools/sutra-check`, 859 ms, and the fix is a sentence
   plus the book lines.)*
2. **The shell hosts every app** — one engine, many apps, state preserved across a redraw.
   *(Proved: `t_shellhost` 47/0.)*
3. **A browser that renders real pages** with our own renderer. *(Proved: `apps/browser`, 16/0.)*
4. **The OS boots and paints.** *(Proved: the ISO's own `desktop.wasm` draws 1280×800, 591
   colours, and a click changes it.)*
5. **A store that installs and launches.** *(Proved: `yantra-os/store/ystore chess`.)*
6. **A small model builds Photoshop from a 200 KB manual.** *(In progress: `docs/sutra-200k.md`.)*
7. **300 agents work on it at once** without stepping on each other. *(The reason for the
   database-first design and the per-lane worktrees.)*

---

## What the owner does NOT want

- **Dumb basic apps as examples.** Films, artwork, simulations, games — nothing a beginner would
  write as a tutorial.
- **A language that makes them fight the compiler.** *"I don't want it to worry about nonsense or
  tiny idiotic errors."*
- **Claims without a number.** Every screenshot in `proofs/` is a measured pixel count; every
  doc row names its test.
- **A beautiful frontend over a backend nobody proved.** The backend is a deliverable, not a
  detail.

---

## The one decision the owner made, and the reasoning

**The language is the bet. The engine is not.**

The engine is reversible by construction — nine seams, and `engine.nim` names no library types,
so any library can be swapped in days. **The language is the risk**: a young compiler, six bugs
in one night, every one fixed in under 70 lines. **That is shallow, not deep — and the bug rate
is now a number (`tools/compiler-regression.sh`) instead of a feeling.**

**A risk you can count is a risk you can act on.**
