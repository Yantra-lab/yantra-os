# Yantra style, themes and composition — spec v1 (normative)

Goal: any interface people build today — an OS shell, a browser, an IDE, a spreadsheet, a
dashboard, a game menu — can be written in Yantra **without changing the language again**. What
grows later is the prop vocabulary (appended to `protocol/schema.nim`) and the engines; the syntax
below stays.

## 1. Props are the whole styling model [S-STY-1]

Every visual choice is a prop on a node. There are no stylesheets, selectors or cascades: a value
comes from the call site, a style preset (`use =`, §3) or the engine's plain default. Any prop value
that reads a signal re-evaluates when it changes [S-PROP-3] — this is what makes theming free (§4).

| Group | Props |
|---|---|
| Surface | `fill` (colour or `linear(from, to, angle)`), `border`, `borderColor`, `radius`, `shadow = shadow(x, y, blur, color)`, `opacity`, `clip` |
| Box | `pad`, `padX`, `padY`, `padTop`/`Right`/`Bottom`/`Left`, `margin` (same forms), `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight` |
| Flex | `gap`, `grow`, `shrink`, `alignItems` (`start center end stretch`), `justify` (`start center end between around evenly`), `wrap` |
| Layers | `stack:` container (children overlap), `absolute = true` with `top`, `left`, `right`, `bottom`; `z` |
| Scrolling | `scroll = true` — the node's content scrolls inside it |
| Text | `size`, `weight`, `font`, `lineHeight`, `italic`, `maxLines` (ellipsis), `color`, `align` |
| Vector | `path(d = "<SVG path data>", size, color, stroke)`; `icon("name", …)` from the standard icon set |
| Input | `placeholder`, `cursor` |
| Transform | `x`, `y` (offset), `scale`, `rotate` (degrees) — drawn moved; layout and hit testing keep the box |
| Motion | `transition`, `ease`, `enter`, `exit`, `animate` (§7) |

Colours are `0xRRGGBB` ints; `rgba(0xRRGGBB, alpha)` adds transparency.

**Theme words [S-STY-5].** In a colour prop (`fill`, `color`, `textColor`, `borderColor`, `shadow`,
and in state blocks) a bare theme colour name means the current theme's value: `fill = surface`,
`color = (if on: accent else: muted)`, `fill = linear(accent, danger, 135)`,
`shadow = shadow(color = rgba(accent, 0.3))`. They re-style on a theme switch like `theme().surface`
does. The names are `bg sidebar surface surface2 surface3 line text muted faint accent accentText
accentSoft danger success`; in a colour prop they always mean the theme, so name local variables something else. `font = mono` / `font = font` read the theme's fonts.

**Units [S-STY-6].** A number alone means px (lengths), ms (`transition`) or degrees (`rotate`). A value
with a unit must be the right one: `width = 320.px`, `transition = 180.ms` or `0.2.s`, `rotate = 45.deg`;
`width = 200.ms` is a compile error (Y020–Y022). Units add and scale (`2.px + gap`, `1.5.secs`).

## 2. Interaction states [S-STY-2]

Inside a node's block, `hover:`, `pressed:` and `focused:` hold prop assignments that apply while
that state holds. The engine applies them; the app does no work and no re-render happens.

```nim
button "Open":
  hover:
    fill = theme().surface2
  pressed:
    fill = theme().surface3
  onClick: open()
```

Allowed in a state block: `fill`, `color`, `borderColor`, `opacity`, `scale`, `y`. With `transition`
set on the node they glide (§7).

## 3. Style presets [S-STY-3]

A style is a value: `style(fill = …, radius = …, pad = …)` builds one; `use = s` applies it; call-site
props win over the preset. Presets are ordinary procs, so they can read the theme and stay reactive.

```nim
proc card(): Style = style(fill = theme().surface, radius = theme().radius, pad = 16)
panel(use = card(), gap = 8):
  text "Hello"
```

## 4. Themes [S-STY-4]

A theme is a plain value (`Theme`: colours, radius, font, spacing). The standard library ships
several and keeps the current one in a signal: `theme()` reads it (tracked), `setTheme(t)` switches.
Because props that read `theme()` are effects, switching re-styles the whole app in one step — one
click, no reload, no engine involvement. Apps may define their own themes the same way.

## 5. Components with children [S-CMP-4]

A component places its caller's block with `slot()`:

```nim
proc Card(title: string) {.component.} =
  panel(use = card()):
    text title, weight = 600
    slot()

Card("Totals"):
  text "₹12,34,567"
```

## 6. Apps inside apps [S-APP-1]

`appView(source = "name")` runs the app `name` (from the same app folder) in its own sandbox inside
this node's box. Its memory, tree and handlers are separate; if it traps, only it stops and its box
says so. Hidden app views keep their app running with its state (tabs).

## 7. Motion [S-MOT-1]

Motion is props too. The engine plays it on its own clock; the app does no work per frame and
nothing re-renders. What CSS transitions, `@keyframes` and Svelte's `in:`/`out:`/`animate:flip`
do on the web is spelled like this:

```nim
panel(transition = 200, ease = outBack)          # any change glides: fill, colour, border,
                                                 # opacity, size, position, hover/press states
row(enter = fly(y = 12), exit = fade())          # when it appears / after the app removes it
icon "refresh", animate = spin()                 # loops: spin, pulse, breathe, bob, loop(...)
```

- **`transition = ms`** (+ `ease =` any name in `protocol/schema.nim` `Easings`, default
  `outCubic`). Every visual value of the node follows its target: colours, opacity, state
  `scale`/`y`, and its layout box relative to its parent — so a keyed list reorders by sliding
  (Svelte's `animate:flip`) and a panel resizes smoothly. A change mid-flight starts from where the
  value is now; nothing jumps. A node's first value is taken as is.
- **`enter = …`** plays when the node appears after the first frame (Svelte's default: the first
  screen does not animate in). **`exit = …`** plays after the app removed the node: the engine keeps
  drawing it where it was (not hit-testable) until done, while its neighbours slide into the gap.
  Values: `fade()`, `fly(x, y)`, `pop(scale)`, `turn(rotate, scale)`, each with `ms`, `delay`
  (stagger lists with `delay = i * 30`) and `ease`.
- **`animate = …`** loops one channel: `spin(ms)`, `pulse(low, ms)`, `breathe(scale, ms)`,
  `bob(y, ms)` or `loop("opacity" | "rotate" | "scale" | "x" | "y", from, to, ms, yoyo, ease,
  count)`; `count = 0` is forever.
- **Reduced motion.** `YANTRA_REDUCED_MOTION=1` (the OS setting, later) makes every duration 0 and
  stands loops still; apps need no code for it.
- **Frames.** An engine asks for frames only while something moves; an idle app draws nothing.

**Springs [S-MOT-2].** `ease = spring | springGentle | springBouncy | springStiff`: in a `transition`
the value moves by real physics and keeps its speed when the target changes mid-flight (the feel of
modern native UI); in `enter`/`exit`/`animate` (fixed durations) the spring's step response is used.

**Timelines [S-MOT-3].** Steps in time, on the engine's clock (exact frames in a film):

```nim
timeline:
  at 0.4.s: scene.set(1)        # at a time from now
  then 600.ms: scene.set(2)     # after the step before it
```

Not yet: scroll-linked and shared-element (FLIP across parents) motion, and
motion in the web runner (task W2). These extend the prop vocabulary; the syntax above stays.

### 7.y State machines [S-MOT-5]

```nim
machine light:
  start red
  after 4.s: red -> green          # happens by itself, on the engine's clock
  after 3.s: green -> amber
  after 1.s: amber -> red
  on cross: green -> amber         # an event: light.send(cross)

panel(fill = (if light == red: 0xE5484D else: 0x30A46C))
text "{light}"
button "Cross": onClick: light.send(cross)
```

- The state is a signal, so UI that reads it (`light == red`, `"{light}"`, `light.can(cross)`)
  follows it.
- An event that does not apply in the current state does nothing: `send` returns false.
  Another machine's event is a compile error.
- A timed step starts when its state is entered and is cancelled if the machine leaves it
  first. On a film's fake clock it lands on the exact frame.
- `light.onEnter(green, proc () = …)` runs code on every entry. Without `start`, the first
  state named is the start.
- Tests: `sdk/tests/t_machine.nim`, and `render/native/t_light.nim` for a real app on the
  engine's clock.

### 7.x Scroll-linked motion [S-MOT-4]

```nim
panel(parallax = 0.4)                 # drifts: 0.4 of its distance from the view's middle
Card("One", reveal = fly(y = 60))     # rises into place as it scrolls into view
```

- `reveal` takes the same poses as `enter` (fade, fly, pop, turn). The node sits at that pose
  below its view and becomes itself over the bottom quarter of the view. Scroll back and it
  goes back. Only `ease` matters: the scroll position drives it, not a clock.
- `parallax = f` shifts a node by f times its distance from the middle of what shows, so
  it moves slower than the page for f > 0 and faster for f < 0.
- "The view" is what shows of the node's scroll container: the window, or an inner
  `scroll = true` area. Nothing runs in the app per frame; the engine reads the scroll
  position when it paints.
- Reduced motion, PDF export and films show every node as it is.
- An overshooting ease (outBack) overshoots position and scale, never opacity. This also
  applies to `enter` and `exit`.
- Web runner: not yet; nodes show as they are. Test: `render/native/t_scroll.nim`.

## 8. Effects [S-FX-1]

Effects are props too; the engine draws the node (and everything in it) through one layer.

```nim
text "Glow", color = accent, blur = 22.px              # blur of the node itself
panel(backdropBlur = 26.px, fill = rgba(0xFFFFFF, 0.1)) # frosted glass: blurs what is behind it
panel(fill = 0xEB5757, blend = multiply)               # multiply screen overlay darken lighten colorDodge
                                                       # colorBurn hardLight softLight difference exclusion
                                                       # hue saturation color luminosity plus normal
panel(saturate = 0, brightness = 1.2, contrast = 1.1)  # colour filters, 1 = unchanged
panel(shader = sksl"""                                 # SkSL: runs per pixel; may declare
  uniform float2 size; uniform float time;             #   size (its box) and time (seconds)
  half4 main(float2 p) { return half4(half(p.x / size.x), 0.3, 0.8, 1); }
""")
```

A shader that reads `time` animates by itself. One that does not compile shows its error over the
app (in dev builds) instead of drawing. Next: compile-time shader checks, masks, clip paths.

## 9. Grid [S-LAY-1]

```nim
grid "160 1fr 2fr", gap = 12.px:
  sidebar()
  card("One share")
  card("Two shares")
  banner(span = 2)          # takes two columns and the gap between them
```

- Columns: a number is pixels (`200` or `200px`), `Nfr` is a share of what is left after
  pixels, `auto` columns and gaps, `auto` is as wide as its widest item, and
  `repeat(3, 1fr)` repeats. Shares never go below zero.
- Items fill columns in order, row after row. `span = n` takes n columns. An item that
  doesn't fit in what is left of a row starts the next one.
- Every item in a row is as tall as the row's tallest item. An item with its own `width`
  keeps that width and still holds its cell.
- Grids nest, and they follow the window when it resizes.
- Not yet: explicit rows, row spans, and placing an item at a given column.

### 9.2 Long lists [S-LAY-3]

```nim
lazy m in msgs.get.keyed(m.id), 44:     # rows 44 px tall
  Bubble(m)
```

- A scrolling column that builds only the rows that show, plus 4 above and 4 below, with
  spacers for the rest. 100 000 rows: first frame 3 ms, 50 wheel steps 37 ms
  (`render/native/t_longlist.nim`, this laptop). Rows have one fixed height for now.
- `scrolled y:` inside a container gives its scroll offset as a signal, the same way
  `sized` gives its size.
- Signals are read without copying (`get` and `peek` borrow), so reading a big list is free.
- App-style and page-style windows: if some scroll area grows into the space left
  (`grow = 1, scroll = true`), the window is exactly its size and that area scrolls.
  Otherwise the page grows and the window scrolls.

### 9.1 Container queries [S-LAY-2]

```nim
column(grow = 1):
  sized w, h:                    # this column's laid-out size, as signals (px)
    if w < 640:
      column: cards()
    else:
      row: cards()
```

- `sized w:` or `sized w, h:` inside any container gives its own laid-out size, not the
  window's. A sidebar, a tab or a card each answer for their own space.
- The engine sends a `Resize` event before it paints, so the first frame already fits.
  It is sent again only when the size changes by half a pixel or more. A layout that
  changes its own size settles within 4 rounds.
- The web runner uses a `ResizeObserver`. Test: `render/native/t_sized.nim`.
- Engine: a grid is a wrapping Yoga row whose items get their columns' widths in a second
  layout pass (`fitGrids`). The web runner uses CSS grid. Test: `render/native/t_grid.nim`.

## 10. Network [S-NET-1]

```nim
app("Weather", net = "api.open-meteo.com"):
  let now = fetch("https://api.open-meteo.com/v1/forecast?latitude=13&longitude=80&current=temperature_2m")
  text "{(if now.get.loading: \"…\" elif now.get.ok: now.get.body else: now.get.error)}"
```

- `fetch(url)` is a signal holding a `Fetched`: `loading`, then `status` and `body`, or
  `error`. `fetchThen(url, proc (f: Fetched) = …)` calls a proc with the answer instead.
- An app reaches only the hosts its window lists in `net`, comma-separated. `*.example.com`
  covers its subdomains. A bare `*` allows nothing.
- It must use https. Plain http is allowed only to `localhost` and `127.0.0.1`, when listed.
  Redirects are not followed; the app sees the 3xx. A refused request is an answer at once,
  with `error` set.
- `fetchWhen(proc (): string = "https://api.x.com/w?city=" & city.get)` fetches again whenever
  the signals in the URL change; an answer for an older URL is dropped.
- `let total = derive: price.get * qty.get` is a computed signal (`derived` without the proc).
- `f.json(Forecast)` reads the body into a typed object (std/json); a body that does not fit
  raises, and apps can catch it (the wasm build is `--os:any`, so exceptions work).
- `fetch(url, meth = "POST", body = "…", headers = ["Content-Type: application/json"])`: any of
  GET, POST, PUT, PATCH, DELETE and HEAD. Headers that only the host sets (Host,
  Content-Length, Transfer-Encoding, Connection, Upgrade) are refused, and so is a header
  containing a line break.
- `let chat = socket("wss://chat.x.com/ws", proc (m: string) = …)` opens a WebSocket (wss, or ws
  to this machine) under the same `net` list, at most 8 at once. `chat.state` is a signal:
  connecting, then open, then closed, with `chat.reason` saying why it closed.
  `chat.send(m)` before it opens is kept and sent in order once it does.
- Open requests and sockets inside `app(...)`, not at the top of the file: the window
  (and its `net` list) must exist first. Otherwise they are refused.
- Limits: 8 MB a body, 30 s a request, 16 waiting at once. `YANTRA_NET=off` turns the
  network off for every app.
- `image "https://…"`: if the URL passes the window's `net` list (`netAllowed`), the engine
  downloads it once into `dataDir()/<appName>/.cache/<sha1 of url>`, draws nothing while it is
  in flight, and relayouts and paints once it arrives.
- The native engine uses libcurl (`libs/nimcurl`); the web runner uses the browser's
  `fetch` under the same rule. Tests: `render/native/t_net.nim`, `render/native/t_net_image.nim`,
  `sdk/tests/t_fetch.nim`, `libs/nimcurl/tests/t_curl.nim`.
- Audio in apps (`C2`): `var s = sound("click.wav")` loads a sound from the app's own folder via
  `resolveAsset`; `play(s)`, `stop(s)`, `setVolume(s, 0.5)`, and `volume(s)` control playback and
  gain through `libs/nimminiaudio` (`pumpAudio`). Test: `render/native/t_sound.nim`.

- File dialogs (`C3`): `pickFile("*.txt", proc(r: PickResult))` and `saveFile(data, "note.txt", "*.txt", cb)` open native SDL3 dialogs. Bytes go to app (read-only, 16 MB cap); paths never cross sandbox boundary. Test: `render/native/t_dialog.nim`.
- Drag and drop (`C4`): `onDragStart`, `onDragOver`, `onDrop` handle intra-app drags and external OS file drops (`dropFile`). File bytes (up to 16 MB) and filename are passed safely; paths never cross sandbox boundary. Test: `render/native/t_dnd.nim`.
- Desktop notifications (`C6`): `notify(title, body)` delivers native Windows toasts/balloons via `Shell_NotifyIcon` in `libs/nimsdl3`, capability-gated by `needs notifications`. Test: `render/native/t_notify.nim`.




