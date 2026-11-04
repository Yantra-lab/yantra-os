---
name: wasm-import-gate
description: >
  Yantra's host refuses to instantiate a wasm module that declares an import the
  host does not provide. std/math's float32 `round` is one of them. The failure
  happens at instantiate time, before yantra_main runs, so the app looks like an
  empty tree. tools/verify-wasm.mjs now enforces this gate itself — read §2 before
  assuming it does not.
domainTags: [yantra, wasm, host, gotchas, verification]
---

# The host import gate will make a working-looking app unloadable

**What this chapter is for.** It explains why an app that builds clean, passes every
headless check and renders an empty tree has failed *before any of its code ran*, and it
gives you the two commands that find the offending import. **After this chapter you can**
read an import census, recognise a name the host will never supply, and tell "the host
refused my module" apart from "my module ran and drew nothing".

**Read next:** `21-visual-parity-verification.md` for what to do once the module does load;
`01-build-run-and-verify.md` for the build that produced it; `19-done-checklist.md` for the
`yantra_main` box; `18-porting-process.md` for the phase this belongs to.

## What happens

`host/host.nim:1158-1164` walks every declared wasm import and refuses the module if the
name is absent from `importTable()` (`host/host.nim:1017`):

```nim
if name notin table:
  raise newException(WasmtimeError,
    "app requires unavailable import '" & name & "' — refusing to instantiate")
```

This raises inside `loadApp` **before `yantra_main` is ever called**. So there is no tree,
no nodes, no output — it presents exactly like "the app created nothing", which is a
diagnosis that will send you looking in entirely the wrong place.

## The trap that does it

`round` has no wasm instruction, so Nim lowers it to a C call and it becomes an
`env.round` import. The host provides no `round`. One call is enough to make the whole
module unloadable:

```nim
$((int(round(pz / 100.0'f32)) * 10 div 10) * 3)   # <-- becomes import "round"
```

Use the app's own half-away-from-zero helper instead. `int(round(x))` and `rnd32(x)`
agree on this, so semantics are unchanged:

```nim
$rnd32(pz / 100.0'f32)
```

`apps/chess/app.nim:92-94` is the helper to copy, and its own comment says why it exists:
*"round(), by hand. See the header: `round` is a wasm import the host lacks."*

**General rule: check the import table before blaming your own code.** After a build,
confirm what the module actually asks for:

```
node tools/verify-wasm.mjs app.wasm    # prints "imports (N): ..."
```

## `verify-wasm.mjs` used not to be a gate — that has changed

> **CORRECTED 2026-10-03. This reverses the chapter's previous headline claim.** What this
> chapter used to assert, in its own words: *"`tools/verify-wasm.mjs` does NOT enforce this
> gate and will report such a module as healthy"* and *"`OK module ran without trapping`
> does not mean the app runs."*
>
> **The first sentence is now false.** `tools/verify-wasm.mjs` **parses the real
> `importTable()` out of `host/host.nim` at run time** and refuses before instantiating:
>
> - `tools/verify-wasm.mjs:146-161` — `readRealImportTable()` scans from
>   `proc importTable*` and collects every `result["name"]` row, recording each one's line
>   number. It reads the source, not a hand-typed snapshot.
> - `tools/verify-wasm.mjs:163-166` — builds `HOST_IMPORTS` from that parse.
> - `tools/verify-wasm.mjs:172-179` — the gate: `WebAssembly.Module.imports(mod)`, matched on
>   the **bare import name**, "exactly like `host/host.nim:1153-1158`, which matches
>   `wasmImporttypeName` and ignores the module string".
> - `tools/verify-wasm.mjs:184-229` — on any name the host does not provide it prints
>   `*** FAIL: the REAL host would REFUSE to instantiate this module ***`, names the first
>   refused import, cites `host/host.nim:1158` / `:1163` / `:1164`, and **exits 1 without
>   running the module at all.** Its own comment says why: "a harness can only 'pass' a
>   module by running it, and the real host never runs this one."
>
> The old FAIL block this chapter quotes is still accurate *as the shape of the failure* —
> `unrecognised: …, round` — but it now appears **before** any "module ran without
> trapping" line, because the gate runs before instantiation. **If you see
> `OK module ran without trapping` in this tool's output, the gate already passed**, which
> is a genuinely different statement from the one this chapter used to make.
>
> The second sentence stays true in spirit and gains a specific: the mock host still runs
> no Yoga and no Skia, so a green `verify-wasm.mjs` says nothing about layout or pixels.

Still confirm with the real engine, and read the error channel:

```powershell
$env:PATH="$PWD\third_party\msys64\mingw64\bin;$env:PATH"
& render\native\build\drive.exe app.wasm out.raw 1280 800 1 ""
```

Success is **exit 0 and a raw of exactly `W*H*4` bytes**. Anything else is a failure,
whatever the node dump suggests.

> **CORRECTED 2026-10-03 — one thing the harness still cannot see.** `verify-wasm.mjs`
> prints an `entry` line. It reports `yantra_main present = false` for a module that exports
> only `NimMainModule` — which happens when an app is written `when isMainModule: main()`
> instead of `proc yantra_main*() {.exportc: "yantra_main".} = main()`. `host/host.nim:1188`
> calls `callVoid(inst, "yantra_main")` unconditionally, so such a module **compiles clean,
> passes every other check in the file, and never renders a frame.** The line is
> `tools/verify-wasm.mjs:406-407`:
>
> ```
> entry  : yantra_main present = false, NimMainModule present = true
> ```
>
> **`yantra_main present = false` is a FAIL.** One port sat in exactly that state — a
> 2,005-byte stub that built and passed while rendering nothing.

> **CORRECTED 2026-10-03 — the render may be stale.** Even a clean `verify-wasm.mjs` run
> proves nothing about the `.wasm` on disk if the build failed. **A failed wasm build leaves
> the OLD `.wasm` in place and `drive.exe` silently re-renders the stale artifact** — exit 0,
> a full-size raw, a confident number, for code that does not exist. The real occurrence: a
> stale `hello.wasm` once hid an SDK that did not compile. **Confirm the build printed
> `build-wasm: wrote …`** before trusting anything downstream. `tools/guard-29.ps1:65-69`
> checks exactly this — the module exists *and* was freshly written.

> **CORRECTED 2026-10-03 — `log()` will not help you debug any of this.** `log()` compiles,
> is callable, and **nothing in the repo reads it.** `host/host.nim:628` is the only writer
> (`cbLog` appends to `host.logs`); `host/host.nim:1029` binds `yantra_log` to it; the only
> reader anywhere is `render/native/t_mpopen.nim:173`, which reads a *different* log — the
> engine's capability log `e.s.logs`. No runner prints the collected lines. It is also
> expensive: one `log()` call measured **+15,660 bytes**, about **7% of a ~215 KB module**.
> Debug with `drive.exe`'s `crash` verb and stderr, not with `log()`.

## "Renders nothing" almost always means one of three things

In order of how often it has actually been the cause:

1. **An unsatisfied import** (this one) — fails before `yantra_main`; the tree is empty
   because no code ever ran.
2. **The module traps** — a Nim exception inside `main()`. The mock host reports this
   as a trapped frame; the native host dies the same silent way.
3. **The tree really is empty** — a `yantra_main` that is `discard`, or returns early.
   This is the *least* common cause and the one everyone assumes first.

`DUMP_GEOM=1` prints the layout tree to **stderr**, so a host-side rejection reads as
silence if you only capture stdout. Capture both, and always report `exit` plus the raw
byte count alongside any geometry dump.

> **Added 2026-10-03 — a fourth cause, and it is not rare.** **The module does not export
> `yantra_main` at all.** See the correction above. Add it to the list you actually check:
> `yantra_main present = true` in the harness's `entry` line, or the app renders nothing
> forever while every other signal stays green.