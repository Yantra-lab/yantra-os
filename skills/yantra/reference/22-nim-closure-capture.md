---
name: nim-closure-capture
description: >
  A Nim closure cannot capture a `var` parameter or local — it will not compile.
  The error names the offending identifier and the declaration site, and the fix is
  usually `ref T`, or dropping the closure. Hit twice in one file while porting.
domainTags: [yantra, nim, ports, gotchas]
---

# Nim closures cannot capture `var` — and it keeps happening

**What this chapter is for.** It is one compiler error, its real cause, and the three fixes
in order of preference. **After this chapter you can** read `'x' is of type <T> which cannot
be captured` and know it is a memory-safety refusal rather than a type error, fix it at the
declaration *and* every call site, and recognise the moved-error pattern that follows a
half-fix.

**Read next:** `17-pitfalls.md` for the other build failures you will hit in the same session;
`01-build-run-and-verify.md` for the build command that surfaces this error; and
`18-porting-process.md` phase 5, which is where the drawing code that causes it gets written.

## The error

```
app.nim(1040, 5) Error: 'd' is of type <Draw> which cannot be captured as it would
violate memory safety, declared here: app.nim(996, 16); using '-d:nimNoLentIterators'
helps in some cases. Consider using a <ref T> which can be captured.
```

It reads like a type error but it is not. Nim refuses to copy a `var` binding into a
closure's environment, because that copy would be an alias the compiler cannot prove
safe. `-d:nimNoLentIterators` does **not** fix this — it only silences part of the
message.

This bit twice in `apps/gallery/app.nim`, in different procs, hours apart:

| | identifier | declared | still in the tree today at |
|---|---|---|---|
| first  | `r: var Rng`  | `genSunset` | `apps/gallery/app.nim:429` — now `proc genSunset(d: var Draw; W, H: float32; r: Rng; n: Noise)`, the fix landed |
| second | `d: var Draw` | `genMosaic`'s nested helper | `apps/gallery/app.nim:1011` — `proc tile(dr: var Draw; tx, ty, s, ang: float32; kind: int32)`, kept as a `proc`, not a closure |

> **CORRECTED 2026-10-03.** This chapter previously cited the sites as *"`r: var Rng`,
> `genSunset`, line 413"*, *"line 996, captured at 1040"* and quoted the error as
> `app.nim(1040, 5)` / `declared here: app.nim(996, 16)`. **None of those line numbers
> resolve.** `apps/gallery/app.nim:413` is `while k < 3:` inside a pixel loop; `:996` is a
> `##` comment about the tessera gradient; `:1040` is `let a = s * 0.5'f32` inside the mosaic
> tile body. The line numbers came from the state of the file at the time of the error and
> were never re-checked after the fix moved the code.
>
> The **fixes** are still in the tree and are the durable evidence:
> `apps/gallery/app.nim:154` declares `type Rng = ref object`, and its comment at
> `:151-152` says exactly why — *"A `ref`, not a plain object, only so the generators' nested
> helper procs can close over the stream: Nim will not lift a `var Rng` into a closure."*
> **The lesson the numbers were meant to carry is the same one; only the pointers were
> stale. Re-check a line number before you print it.**

Two occurrences in one file is the signature of an agent writing drawing code as a
nest of closures. It is the single most common Nim build error in these ports.

## Why the code reaches for a closure at all

The source artwork is naturally nested — "for each pixel, pick a colour" — and the
port keeps that shape:

```nim
proc genSunset(d: var Draw; W, H: float32; r: var Rng; n: Noise) =
  proc col(x, y: float32): (float32, float32, float32) =   # <-- closure
    ...
    return (275.0'f32 + r.nextF() * 30.0'f32, ...)          # <-- captures r
```

That inner `proc col` is real: `apps/gallery/app.nim:453`.

## The fixes, in order of preference

**1. `ref T` — when the closure genuinely needs to mutate shared state.**
Capturing a `ref` copies the *reference*, which is allowed, and it gives every call
site the same stream. This is the right answer for an RNG, a noise table, or a
builder:

```nim
proc genSunset(d: var Draw; W, H: float32; r: ref Rng; n: Noise) =
# caller: genSunset(d, pw, ph, addr rng, n)
```

`apps/gallery/app.nim:154` is this fix, in the tree: `type Rng = ref object`. A `ref` here is
not a workaround — it is a statement that the state is shared on purpose.

**2. Drop the closure.** If the inner function does not mutate anything, make it a
`proc` and pass what it needs. Nim will then capture by value, which is safe, and
the error never appears. This is often the smaller change.

> **CORRECTED 2026-10-03.** What this chapter used to say was just *"Drop the closure"*.
> That is right, and worth being precise about **why**, because the distinction decides the
> fix: **a nested `proc` that only reads its captures is lifted by value and compiles; the
> error is specifically a nested `proc` that *mutates* a `var` capture.**
> `apps/gallery/app.nim:1011` — `proc tile(dr: var Draw; tx, ty, s, ang: float32; kind: int32)`
> — carries a `var Draw` parameter and survives fine, because nothing reaches through the
> closure and mutates it. The rule is not "avoid `var` in nested procs"; it is **"do not
> mutate a `var` from inside a nested proc."**

**3. Return values instead of capturing.** A closure that only reads can return the
value it needs and let the caller apply it.

**Do not** silence it with `{.closure.}`-style pragmas or `--warning[Closure]:off`.
That warning is the only thing standing between a port and a memory-safety bug in
artwork code that will be re-run a thousand times per frame.

## A trap when fixing it

Changing `var Rng` to `ref Rng` at the declaration is **not enough on its own**. The
caller still holds a value and the error simply moves:

```
(447, 27) 'r' is of type <Rng> which cannot be captured ...
(450, 28) type mismatch                     <- after the ref fix
(166,  7) invalid type: 'var uint32' ... 'Rng' for var   <- now in an unrelated proc
```

> **CORRECTED 2026-10-03.** These three numbers are from the same unverified snapshot as the
> `413 / 996 / 1040` block above and are **not** resolvable against the current
> `apps/gallery/app.nim`. The *pattern* is the durable lesson and it is unchanged — three
> errors, three different procs, one half-finished fix. Read the shape, not the coordinates.

Fix the declaration **and** every call site (`addr rng`, or pass an existing `ref`)
before rebuilding. A moved error is not a new bug; it is the same unfixed one.