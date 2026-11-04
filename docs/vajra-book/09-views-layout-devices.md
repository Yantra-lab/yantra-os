# 9. Views, layout and devices

A `view` says what is on a screen, as a tree of components. The engine draws it with real
native libraries, the same on every device, and redraws only what changed. Most of this
is **built**; devices beyond the desktop are **planned**.

## 9.1 Views (built)

```text
view Counter(label: string, step = 1)
  state count = 0
  param size = 28px in 12px .. 64px
  Column(gap = 12px, pad = 24px):
    Text @title "{label}: {count}", size = size
    Button "Add":
      on tap: count += step
```

- Components, their properties and their events come from one place: the engine's
  protocol (`protocol/schema.nim`: 48 kinds of node, 207 properties). A view is checked
  against it at compile time; a misspelled property is an error with a suggestion
  (t_views).
- `state` is kept per instance, under the instance's place among the views; `key` keeps it
  with its row in a list (t_views).
- A view with an address is a screen; `go` and `back` move between screens (t_views).
- `param` values are settings a GUI can change, and `tuneParam` writes them into the code;
  `@name` gives a node a stable name (t_views, §23).
- A tap is one transaction: if it fails, its changes are undone and the message shows.
- Another person's change to a row redraws every screen that read it; a redraw sends only
  the properties that changed (t_views, t_live).

## 9.2 Layout and drawing

| Part | Library | Status |
|---|---|---|
| layout: rows, columns, flex, grid, gaps, padding | Yoga, wrapped (`libs/nimyoga`) | **built** |
| drawing: shapes, text, images | Skia, wrapped (`libs/nimskia`) | **built** |
| text shaping: every script, right to left | HarfBuzz, wrapped (`libs/nimharfbuzz`) | wrapped |
| 3D: scenes, models, cameras, lights | Filament, wrapped (`libs/nimfilament`) | wrapped |
| windows, input, the GPU | SDL3, wrapped (`libs/nimsdl3`) | **built** (desktop) |
| spelling | `libs/nimspell` | wrapped |
| accessibility (screen readers) | AccessKit, wrapped (`libs/nimaccesskit`) | wrapped, with an engine test (`render/native/t_a11y.nim`) not yet in the gate |

"Wrapped" means the library has a Nim interface in `libs/`; a view reaching it end to end
is shown by its test, or it is **planned**.

## 9.3 One view, every screen

**planned:**
- A view adapts to the size and shape of its screen with size classes:
  `when compact: … when regular: …`, chosen by the engine from the window's width.
- One input model for every kind of pointing: mouse, touch, pen, gamepad, hands and
  controllers all arrive as `tap`, `press`, `drag`, `scroll`, `pinch`, `focus`, with the
  device named when a view needs it. Keys and the pointer are **built**
  (`yantra/engine.nim`).
- Text input with the system's own keyboard and input methods, every language.

## 9.4 Devices

| Where | How | Status |
|---|---|---|
| Windows | the host, as an app | **built** |
| macOS, Linux | the host, as an app (SDL3, Skia and Filament run there) | **planned** |
| Android, iOS | the host, as an app; on iOS, wasm runs through wasmtime's interpreter or a module compiled before shipping, as Apple allows no compiler at run time | **planned** |
| headsets | OpenXR, wrapped; a view becomes a panel in space, a `Scene3D` the world | **planned** |
| Yantra OS | the device boots into the host; the shell is the first screen | **planned** |

## 9.5 The shell

The shell is the first app and the frame for every other: full screen, apps opened by
their `y:` addresses, tabs on one side and a dock on the other, layouts that can be saved,
the person's notifications and the permissions they gave (§18). It is a Vajra app like
any other, so it can be remixed.

## 9.6 Tests

Built: `host/vajra/tests/t_views.nim` (40 checks), `t_live` (7).

Planned (each one is a task):
- A view with `when compact` draws its compact layout in a 390-pixel-wide window and its
  regular layout at 1440.
- A tap from a touch screen and a click from a mouse run the same `on tap`.
- A screen reader reads the label of every `Button` in the tasks app.
- The tasks app draws the same pixels on Windows and on Linux.
- On a headset, the tasks app is a panel that can be pointed at and tapped.
