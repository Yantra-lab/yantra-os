# Yantra OS frontend — Aura

The desktop is the product, not a catalogue for it. It is one native workspace for apps, games,
code, files, media and agents; on Yantra OS it becomes the session. **Aura** is its visual system:
blue-hour surfaces, cool periwinkle focus, champagne warmth, luminous glass, deliberate type.

## 1. Non-negotiable product rules

- **The first screen is useful.** Search, launch, recent work, actual workspace state and shortcuts.
  An empty wallpaper is not a home screen.
- **Beautiful means readable and responsive.** High contrast, clear focus, sensible targets, no
  microscopic labels, no path-glyph three-dot menus, no disabled-by-contrast buttons.
- **Every visible action works.** No decorative AI, fake search, dead export, invented system
  information, or a screenshot standing in for a simulation.
- **One engine, nested apps.** `appview(source = "y:<id>")` launches a real, sandboxed app. Do not
  spawn an OS browser, Electron wrapper, or second UI engine to make a screen easier to draw.
- **The app gets its own art direction.** Aura unifies the shell, typography, semantic states and
  interaction rules; a museum need not look like a kart racer or a code editor.
- **Performance is measured.** A port states its frame resolution, actual measured frame time,
  module size and input latency. Compile success is neither an appearance nor interaction proof.

## 2. Core tokens

Exact values live in `apps/desktop/config.nim`; the release carries them in
`apps/desktop/app.nim`. Change those, not forty independent colours.

| Role | Value | Use |
|---|---|---|
| `m3surface` | `#0C0E14` | chrome and outer frame |
| `containerLowest` | `#080A10` | recessed areas |
| `containerLow` | `#11141D` | quiet cards, inputs |
| `container` | `#171B25` | window surfaces |
| `containerHigh` | `#202634` | elevated/hover surfaces |
| `onSurface` | `#F1F3F8` | primary reading |
| `onSurfaceVariant` | `#ACB3C3` | secondary reading, never “disabled by default” |
| `outline` | `#828B9E` | tertiary labels, focus-adjacent marks |
| `outlineVariant` | `#333B4C` | hairlines and soft borders |
| `primary` | `#AFBBFF` | focus, selection and primary actions |
| `tertiary` | `#E7BD91` | warm brand counterpoint |

Measured WCAG relative-luminance ratios from these sRGB values: primary text/shell **17.38:1**,
secondary text/shell **9.18:1**, secondary text/card **8.75:1**, tertiary text/card **5.37:1**,
primary button text/primary **9.28:1**. These are contrast calculations, not a complete
accessibility audit; keyboard and screen-reader checks remain separate requirements.

Typography is **Noto Sans** for interface/display and **DejaVu Sans Mono** for numbers/code on the
release host. Code samples, clocks and race telemetry should not fall back into an incidental serif.
Serif can still be an intentional editorial choice, as in a museum exhibition.

Shape: 22 px screen radius, 14 px windows/cards, 248 px expanded sidebar, 56 px spaces rail. Use
pills for search and compact controls, not for every text container. Eight-pixel spacing is the
base rhythm; larger page composition uses 24–32 px breathing room.

## 3. Luminous identity

The owner-supplied artwork is in `assets/brand/`. The desktop loads its 256 px mark from
`apps/desktop/brand/yantra-mark.png`, inside its own sandbox. The wider key art remains in
`assets/brand/yantra-os.png` for release presentation. The logo is not an internet dependency and
no filename points at a temporary attachment store.

The wallpaper is one restrained SkSL field: two pools of light, a vignette and extremely subtle
grain. Blur belongs to a surface's material, not to unreadable text. The luminous logo supplies
the spectacle; the workspace stays calm.

## 4. Which source dialect is which

- **Desktop:** the platform's Nim SDK (`import yantra`, composable `panel`, `row`, `column`,
  `canvas`; built by `tools/build-wasm.sh`). The private workbench keeps `config`, `state`, `ui`,
  etc. modular; the release carries their folded `apps/desktop/app.nim`.
- **Showcase apps:** Sutra cells (`record`, `view`, `state`, `Canvas`, `on frame`, typed records).
  They compile through the release's Sutra/Atlas pipeline. Do not paste Nim SDK imports into them
  or assume that a file ending in `.nim` selects the other dialect.
- **Artifacts are part of this release.** `apps/<id>/app.wasm` is intentionally tracked alongside
  source and metadata so a judge can run it. That does not make unoptimised caches, `minilibc.o`,
  or `nimcache/` deliverable junk.

## 5. Flagship acceptance matrix

These ports are how the language earns its vocabulary. A beautiful export without the interaction
column passing is not finished.

| Experience | Must exercise | Acceptance beyond appearance |
|---|---|---|
| **Kart** | continuous time, keyboard/pointer input, projection, state transitions | throttle/brake/steer, lap change, loss/win, restart |
| **Poster** | records/data, deterministic PRNG, geometry, expressive layouts | same seed reproduces, controls regenerate, grid/export really works |
| **Sumi** | mutable numerical field, fixed-step simulation, pointer velocity | a stroke changes simulation state; later frames evolve honestly |
| **Coastline** | floating-point numerics, iteration bounds, palette mapping | zoom/navigation changes state and pixels; frame cost stated |
| **Orrery** | trigonometry, time, astronomical parameters, animation | two time states differ; pause, reset and step controls drive the same model |

(The last column describes required behavior, not the port's language.) The editor adds records,
permissions, parsing, persistence and the edit→build/reload loop. The desktop adds composition,
persistence, system capabilities and real nested apps. “Can do anything JS can” remains a
parity programme, not a sentence inferred from these five screens.

## 6. Current desktop verification

`render/native/t_desk_render` drives the real rebuilt desktop through the engine at 1100 × 768.
It returns **34 passed, 0 failed**, including real `Super+N`, an address field and window caption,
caption buttons, launcher and Escape, dashboard, screen frame, dock and non-zero window geometry.
At its initial state the new home has 242 live nodes and 240 measured boxes. Repaint examples are
1280 × 800 PNGs in `proofs/desktop.png` and `proofs/desktop-open.png`.

A screenshot driver that does not print a tap and yields a byte-identical before/after image is not
an interaction test. Use the keyboard/driver assertions, check input state, then inspect the frame.
