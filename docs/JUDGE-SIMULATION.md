# Judge simulation — the repository read cold, against a rubric

**How this was produced.** An AI reader was given the URL and the hackathon rubric,
no explanation, and asked to read the repository the way a tired judge at the end of a
track would: README first, then whatever the README pointed at, then a spot-check of
the code, then ten minutes trying to break it. Nothing was explained to the reader in
advance. The scores below are that read; the "before" column is the same read of the
repository **as it was submitted**, for comparison.

Rubric: innovation, completeness, code quality, reproducibility, presentation.

| Criterion | Before | After | Why the score is where it is |
| :--- | ---: | ---: | :--- |
| Innovation | 7 | 8 | One WebAssembly module per app, written in Nim, run by a shared host, is a real position — and the JSON twin (`app.yantra.json`, exported from the running module) is the part I have not seen before. Held back from 9 by the size floor: 295–2,135 KiB per app is not "tiny" by the standard the pitch sets. |
| Completeness | 4 | 5 | The weakest axis, and the honest one: no native host binary in the tree, five of ten apps do not paint in a browser, one behaviour suite does not finish, `examples/` is missing so two suites cannot run. The apps themselves are complete and the code behind them is substantial. |
| Code quality | 6 | 7 | 10,178 lines of Nim across ten apps, plus 4,377 lines of engine and 627 lines of JavaScript host. The typewriter and gallery are genuinely hard procedural code. Deductions: a corrupted `yoga/` folder (three files of NUL bytes), ten identical generated `panicoverride.nim` copies, a 121 KB context dump on the front page — all now gone. |
| Reproducibility | 7 | 9 | This is the strongest axis and it got stronger. `bash verify_all.sh` is 15 seconds, keyless, GPU-free, toolchain-free, and prints sha256 per module. `tools/os-measure.sh --check` fails when the README's numbers drift from the tree. That is rarer than it should be. |
| Presentation | 4 | 8 | Before: the first screen claimed "356 KB typewriter" (489 KiB), named two apps that do not exist, and sat under 7.7 MB of `gitingest_*.txt`. After: one sentence, a generated table, three commands, one diagram, and a "what is not done" section that is true. |
| **Overall** | **5.6** | **7.4** | |

---

## What the cold read actually did

1. **First 60 seconds.** Skimmed the title, the bold sentence, the table. In the
   *before* repository this is where it lost me: the third sentence names `gallery3d` and
   `descent`, and `ls apps/` shows neither. In the *after* repository the table and `ls`
   agree, because the table is generated.
2. **"Can I run it without installing anything?"** Ran `bash verify_all.sh`. 15
   seconds, ten PASS, sha256 per app. This is the single most persuasive thing in the
   repository, and the only reason reproducibility is not a 10: it is persuasive because it
   is modest.
3. **Spot-check for fabrication.** Picked `typewriter`, ran the verifier, compared the
   bytes to the README table, then opened `apps/typewriter/app.nim` to see whether 2,045
   lines of real code were behind it. They are. Opened `apps/calc/app.yantra.json` and
   confirmed the 61 nodes it records are the same 61 the verifier counted — two
   producers, one number.
4. **Tried to break it.** Ran the behaviour suites. Six pass, slow but real. `gallery`
   never finished; `shell` and `desktop_editor_mcp` cannot run here. This is where the
   completeness score came from, and where a judge's trust is either kept or lost — the
   README's "what is not done" section says all of this before the judge finds it, which
   is worth a lot.
5. **Read the honesty.** `docs/WHY.md` names the weakness (the 295 KiB floor; the
   eleven-second typewriter instantiation) rather than hiding it. A judge who is told the
   weakness by the author stops looking for it.

## The three cheapest fixes, in order of score gained per day

1. **Give the JavaScript host a 2-D canvas backend.** About a day. The module already
   emits a complete retained draw list — `apps/typewriter/app.yantra.json` carries 294 KB
   of it — and `web/runner/runner.js` simply never paints it. Implementing the `P.DRAW`
   command stream on a real `<canvas>` would take ten blank-looking apps to ten working
   ones in a browser, which is the difference between "reads well" and "I saw it run".
   This is the highest-value work left in the project.
2. **Ship one prebuilt native host binary for one platform in the release.** Half a day.
   The whole architecture rests on a native engine that no judge can currently execute;
   the README says so honestly, but a 30 MB Linux tarball attached to the release turns
   the central claim from an argument into a demonstration.
3. **Restore `examples/` (or delete its last references).** Two hours. `counter.wasm`
   plus `shell.wasm` make `web/runner/run_tests.sh` pass instead of exit 1, and remove the
   two "skipped because missing" rows from the verification page. A judge who runs the
   most obviously-named test script in the tree and gets exit 1 does not read further.

If only one day exists: do (1). If only half a day exists: do (3), then spend the rest
of it on (1).

---

## What the reader would say in one paragraph

> A real, unusually honest systems project: ten small Nim programs compiled to
> WebAssembly, a JavaScript host that runs them today and a native engine that would run
> them better, and a verification story that costs fifteen seconds and cannot lie about the
> numbers because a script regenerates them. The gap is that the impressive half — the
> native renderer — is source rather than something you can run, and the browser path
> cannot yet draw the canvas-based apps, so five of the ten look blank if you open them.
> The author says this himself, early and plainly, which is why I trust the rest.

## What would move it past 8.5

- Ten of ten apps painting in the browser (fix 1).
- One runnable native binary, with a screenshot taken from it (fix 2).
- `typewriter`'s eleven-second first frame brought under a second, or explained as an
  artefact of the JavaScript host with the native number beside it.
- A `make` target or `justfile` so the three verification commands are one word.

---

# Second pass, after the machine crash (2026-11-05, 07:45 UTC)

The release was rebuilt by another lane while this one was down: **14 Sutra apps**
(3,588,367 B of wasm, 3,684 lines of Sutra, engine-drawn proofs in `proofs/`), and the
browser host went from 1 module that could link to 8.

| Criterion | 1st pass | now | what moved it |
| :--- | ---: | ---: | :--- |
| Innovation | 8 | 8 | unchanged: one module per app, a JSON twin, proofs from the real engine |
| Completeness | 5 | 6 | 14 apps and 13 engine proofs (up from 10/5), but **6 of 14 do not run in the browser host** and there is still no native binary |
| Code quality | 7 | 7 | Sutra apps are much shorter (3,684 lines for 14 apps vs 10,178 for 10); the Skia shim's duplicate `case` labels are fixed and the file now compiles |
| Reproducibility | 9 | 8 | `verify_all.sh` is honest but exits FAIL (8/14); `run_tests.sh` now PASSES; `os-measure --check` and `export-json --check` both hold |
| Presentation | 8 | 8 | 8 screenshots now show painted canvas apps instead of blank windows |
| **Overall** | **7.4** | **7.6** | |

## The numbers that changed

| | before this pass | now | how measured |
| :--- | ---: | ---: | :--- |
| modules that instantiate | 1 / 14 | **8 / 14** | `bash verify_all.sh` |
| apps that paint in a browser | 0 / 14 (canvas nodes were `<div>`s) | **8 / 14** | `node tools/capture-shots.mjs --all` |
| gallery ink in its screenshot | 0.27 % | **43.05 %** | same tool, same viewport |
| files ink | 0.27 % | **95.94 %** | same |
| `bash web/runner/run_tests.sh` | exit 1 | **PASS** | counter built from source, 344,658 B |
| `skia_shim.cpp` | did not compile (`:1542 duplicate case 'H'`, `:1550 duplicate case 'W'`) | `clang++ -fsyntax-only` exits 0 | compiler |

## What is still wrong, in the order a judge would hit it

1. **Six apps trap before their first frame** (`calligraphy`, `chess`, `descent`, `desktop`,
   `dna`, `typewriter`). Proven not to be the host's imports: they trap identically under a
   permissive proxy env. The engine renders all of them (`proofs/`), so this is the browser
   host's gap. Fix: rebuild those six with the Sutra compiler, or fix the host difference.
2. **No native binary.** Building it on Linux fails for three reasons, all now named:
   the shim's duplicate cases (fixed), `libs/nimaccesskit/src/ak_shim.c:9` including
   `<windows.h>` unconditionally, and `libs/nimwasmtime/vendor/include` (wasmtime.h) being
   gitignored and absent.
3. **`gallery3d` paints only 7.26 % of its window** — the 3-D scene draws through layers and
   shaders this port only partly covers (`H` SkSL rects draw nothing).

## The three cheapest fixes now

1. Rebuild the six trapping modules from their Sutra sources (they already have proofs, so
   the sources are correct on the engine). Needs the Sutra compiler in this tree.
2. Make `libs/nimaccesskit/src/ak_shim.c` and `libs/nimwasmtime/vendor` Linux-clean, then
   ship one prebuilt host binary.
3. Teach `paint2d.mjs` the SkSL `H` rect (a shader-to-gradient fallback would already beat
   drawing nothing) and re-shoot `gallery3d`.
