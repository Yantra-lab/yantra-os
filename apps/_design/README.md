# `apps/_design` — the shared design system

One module, one set of numbers, and a checker that fails when an app drifts off them.
The rules it encodes are in [`skills/yantra/reference/25-frontend-craft-rules.md`](../../../skills/yantra/reference/25-frontend-craft-rules.md);
what Yantra still cannot express is in [`26-frontend-gaps.md`](../../../skills/yantra/reference/26-frontend-gaps.md).

| File | What it is |
| :--- | :--- |
| `design.nim` | the tokens, the `Style` presets, the WCAG contrast functions, the self-check |
| `demo.nim` | the proof: one screen, two builds (`-d:adhoc` = the old way, plain = the system) |
| `audit.py` | the mechanical checker — reads an app source, prints rule violations with line numbers |

## Use it

```nim
import "../_design/design"        # from apps/<id>/app.nim — QUOTED, see below

Column(gap = Sp4, pad = Sp6, fill = surface):
  Text "Stages", size = FsTitle, weight = W600, color = text
  Text "three laps", size = FsSmall, weight = W500, color = muted
  Button "Start", use = ctlPrimary():
```

**The path must be a quoted string.** A bare `import ../_design/design` fails with
`Error: invalid token: _ (\95)` because a Nim identifier cannot start with `_`. Proved both
ways on this box: quoted compiles, bare does not. From an app two levels down (e.g.
`apps/_assets/demo/`) use `import "../../_design/design"`.

An imperative app (`kart`, `emberdeep` drive `Node`s directly) uses the twins:

```nim
typeOn(b, FsSmall, W700)          # snaps an off-scale size to the nearest legal step
ctlOn(b, ctlFill(), ctlInk())     # radius + fill + ink in one call
spaceInto(row, Sp3)               # snaps a gap to the rhythm
focusRing(b)                      # the 2 px ring, from the theme's accent
```

## The tokens

| Family | Values | Rule |
| :--- | :--- | :--- |
| Type (px) | 11, 12, 14, 16, 20, 26, 34, 46 | T1 — nothing else |
| Weight | 400, 500, 600, 700, 800 | T5 |
| Space (px) | 4, 8, 12, 16, 24, 32, 48 | S1 — plus an optical 1–2 px between a label and its own value |
| Radius (px) | 0, 6, 10, 16 | R1 |
| Motion (ms) | 120, 180, 280, 360 | M1 |
| Contrast | 4.5:1 body · 3:1 large · 3:1 border/ring | C1, C2, C3 |

"Large" is taken from **WCAG 2.2 SC 1.4.3**, not from habit: 24 px, or 19 px and
bold (14 pt at 96 dpi). Material's 20 px / 16 px-bold is *looser*, and a looser
threshold lets a 20 px pair pass at 3:1 that WCAG wants at 4.5:1 — so this module
uses the strict one. `audit.py` is pinned to the same numbers.

## The measurements behind it

Every number below was produced by a command in this directory; re-run them to check.

**1. The house themes, measured** — `nim c -r --hints:off yantra-os/apps/_design/design.nim`
(the `when isMainModule` block runs `checkThemes()` over all eight themes):

```
C4 Midnight faint/surface 2.64 < 3.00
C1 Paper accentText/accent 4.30 < 4.50
C4 Paper faint/surface 2.54 < 3.00
C4 Fjord faint/surface 2.68 < 3.00
C1 Blossom accentText/accent 3.96 < 4.50
C4 Blossom faint/surface 2.37 < 3.00
6 contrast findings over 8 themes
```

Read that as two facts, not two bugs in the SDK:

- **`text`, `muted` and `textual` pairs pass 4.5:1 in all eight themes.** The house
  palette is sound where it matters.
- **`faint` does not reach 3:1 on `surface` in four of eight themes** (2.37–2.68), and
  **`accentText` on `accent` misses 4.5:1 in Paper (4.30) and Blossom (3.96)**. So
  `faint` is a hairline and a disabled glyph only — never a label — and an accent
  button in Paper or Blossom needs `theme().bg` as its ink, not `accentText`. Rule C4
  and C1 in the rules doc say exactly this.

**2. The system against the old way, on one screen** — `demo.nim`, two builds:

| | before (`-d:adhoc`) | after (tokens) |
| :--- | :--- | :--- |
| module | `/tmp/demo-before.wasm` 134,883 B<br>sha256 `092d91bd99a1003692ab538860fa5701fd65b172501b8b2bb777983198d0437e` | `/tmp/demo-after.wasm` 134,883 B<br>sha256 `bd2fb9ca54e1fdce11540705c5a27a6367b0d656c192087f4cd0fa4bc5176904` |
| frame | `/tmp/fs-demo-before.png` 43,902 B 1440×900 | `/tmp/fs-demo-after.png` 46,142 B 1440×900 |
| distinct colours (§7 metric) | 517 | 506 |
| ink fraction (§7 metric) | 1.000 | 1.000 |
| label contrast, computed | `0x66799C` on `0x0B1222` = **4.25:1** (fails 4.5) | `0x8C8C96` on `0x16161D` = **5.41:1** |
| smallest label | 9 px | 11 px |
| pixels changed between the two frames | — | **16.97 %** (3-px sample) |

The honest reading: the §7 metric **cannot see typography** — distinct colours moved
1.9 % and ink fraction did not move at all, while 16.97 % of the frame changed. For
layout-and-type work the numbers that track the work are the *computed* ones (size,
rhythm, radius, contrast ratio) and a change map. Use all three; never quote the
colour count alone as evidence that a screen got better.

**3. The census** — `python3 yantra-os/apps/_design/audit.py --json yantra-os/apps/*/app.nim`.
Two rows, both measured, both reproducible: the baseline is the branch tip this lane
started from, checked out with `git show 7b7ceec9:yantra-os/apps/<id>/app.nim` into a
temp directory; the working row is the same command over the live tree.

| rule | baseline `7b7ceec9` | working tree | what it counts |
| :--- | ---: | ---: | :--- |
| S1 | 403 | 270 | spacing off the 4-pt rhythm |
| T1 | 334 | 247 | text sizes off the 8-step scale |
| R1 | 241 | 241 | radii off the 3-radius set |
| X1 | 18 | 18 | apps with controls and no state block at all |
| T5 | 8 | 0 | font weights off the closed set |
| M1 | 4 | 0 | durations off the motion bands |
| C3 | 3 | 3 | a border under 3:1 against its fill |
| X2 | 1 | 1 | controls with no `focused:` block |
| **total** | **1012** | **780** | over 20 app sources |

Per app at the baseline: `desktop` 310 · `editor` 97 · `poster` 84 · `notes` 78 ·
`coast` 70 · `todo` 69 · `dna` 53 · `descent` 52 · `gallery` 35 · `ocean` 30 ·
`typewriter` 28 · `chess` 27 · `ink` 24 · `calc` 15 · `orrery` 14 · `gallery3d` 13 ·
`arcade` 9 · `emberdeep` 2 · `kart` 2 · `files` 0.
`desktop` alone went 310 → 78 across two craft commits (`b203b87c` type, `a250525f`
spacing); the rest of the drop is `emberdeep`'s type commit (`8e36a3f6`), which took T5
8 → 0 and T1 334 → 247.

## What this system cannot do yet

See `GAPS` in [`26-frontend-gaps.md`](../../../skills/yantra/reference/26-frontend-gaps.md).
The three that bite this system: **no letter-spacing** on `Text` (so micro-caps cannot
be tracked out), **no cubic-bezier easing** (the wire carries an `Easing` *index*, so a
designer's curve has to be snapped to one of 35 named curves), and **no OS
reduced-motion signal**, so the reduced-motion variant has to be an app-level switch.
