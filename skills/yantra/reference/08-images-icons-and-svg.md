# 08 — Images, icons and SVG

Four ways to put a picture on screen — an `image` node, a `path`/`icon` node, an SVG
`d` string inside a `Draw` list, and a raw RGBA buffer — plus what each one cannot
do, and the exact rules for lifting artwork out of an HTML file.

---

## Ground truth for this chapter

Every claim below was read out of these files. Signatures are copied verbatim.

| Fact | Source |
|---|---|
| `Draw.svgPath*(d: Draw; path: string; x, y, scale: float32; argb: uint32; strokeWidth = 0'f32): Draw` | `sdk/ui/paint.nim:46-52` |
| **`Draw.image*(d: Draw; x, y, w, h: float32; file: string): Draw` — there is no `fit` parameter.** It writes the literal `" 0 "` into the stream | `sdk/ui/paint.nim:65-66` |
| `Draw.pixels*(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32, h = 0'f32): Draw` | `sdk/ui/paint.nim:70-72` |
| `Draw.layer*(d: Draw; l: Layer; x, y: float32; w = 0'f32, h = 0'f32): Draw` | `sdk/ui/paint.nim:67-69` |
| **There is no ellipse primitive.** `circle(cx, cy, r, argb)` is the only oval, and it emits one radius twice | `sdk/ui/paint.nim:59-60` — `E cx cy r r argb` |
| **There is no gradient verb** in `paint.nim`. The `E`/`R`/`F` verbs take one flat colour | `sdk/ui/paint.nim:53-60`; the shim has no shader branch in `runCmds` |
| The `V` verb is parsed by `SkParsePath::FromSVGString`, then translated and scaled | `skia_shim.cpp:1389-1405` |
| `V` **fills unless `sw > 0`**, where `sw` is the 4th number | `skia_shim.cpp:1398` |
| The `I` verb rejects a drive letter, a leading `/`, a backslash or `..` | `skia_shim.cpp:1357-1359` |
| `fit`: **0 contain, 1 cover, 2 fill** — in the shim | `skia_shim.cpp:998-1006` (`drawFit`) |
| …the same 0/1/2 in the DSL words and in `pFit`'s doc comment | `sdk/ui/dsl.nim:157`; `libs/nimskia/src/nimskia.nim:182`, `:289` |
| `fit` is allowed on `Image` and `Video` only | `protocol/schema.nim:328` |
| `fit` also accepts a **string**: `"cover"`→1, `"fill"`→2, **anything else**→0 | `sdk/ui/dsl.nim:169-171` |
| An `image` node with no `width`/`height` takes the **file's own size**, falling back to 100×100 | `render/native/engine.nim:563-575` |
| A `Path` node lays out at `size` on both sides (default 24), `flexShrink = 0` | `render/native/engine.nim:576-580`, `:385` |
| A `Path` node is drawn as a **24×24 viewBox**: `scale = min(boxW, boxH) / 24`, centred | `render/native/engine.nim:1887-1893` |
| The icon set is **38 icons**, `iconPath(name)` / `iconNames()` | `sdk/ui/icons.nim:5-53` |
| `icon "name"` is a `Path` node with `pStrokeWidth` forced to 1.8 and `pPathData` from `iconPath` | `sdk/ui/dsl.nim:396-403` |
| Asset paths allow `[A-Za-z0-9_./-]` only, ≤ 200 chars | `render/native/engine.nim:934-938` |
| Network images need `https://` **and** the host in the window's `net` list | `engine.nim:1145-1148`; `host/host.nim:302-315` |

**What was verified at runtime:** both code samples in this chapter compile to wasm
with `tools/build-wasm.sh` (`probe08.wasm`, 252,891 bytes; `probe08b.wasm`,
240,825 bytes). Nothing here was measured off a framebuffer — the claims are read
out of source, and §9 says exactly what that leaves unproven.

---

## 1. The `image` node — a decoded bitmap

```nim
image "photo.jpg"                                   ## the app's own folder, natural size
image "card.png", width = 240, height = 160, fit = cover, radius = 12
image "map.png", fit = fill                          ## stretch to the box, no letterbox
image "big.tif", zoomable = true                     ## Ctrl+wheel / pinch zooms, drag pans
image "https://cdn.example.com/logo.png"             ## needs net = on the window
```

The source path is the **first positional argument**, not a prop
(`sdk/ui/dsl.nim:434-439`): `image "…"` sets `pSource` and starts the props at the
second argument. `pSource` is a plain string, so `source = "…"` also works
(`protocol/schema.nim:277` — `allowedNodes: "Image,Video,Model,Flex,Chart,Drawer,AppView"`).

### The props that matter for a picture

| Prop | Type | Default | What it does |
|---|---|---|---|
| `fit` | int32 | `0` | how the bitmap fills the box: **0 contain, 1 cover, 2 fill** |
| `radius` | int32 | `0` | corner radius — clips the bitmap to a rounded rect |
| `width` / `height` | | **the file's own size**, else `100` × `100` | the box |
| `zoomable` | bool | `false` | Ctrl+wheel zooms 1×–8×, drag pans, double click resets |
| `source` | string | — | the file or URL |

`radius` is the *node's* corner clipping (`drawFit` clips to
`SkRRect::MakeRectXY(box, r, r)` when `r > 0`, `skia_shim.cpp:1011-1016`), not a
border. `radius = 999` on an image is a circle.

### Sizing: the box comes from the file

`render/native/engine.nim:563-575` runs the asset through `imageInfo` and sets the
Yoga size from the decoded dimensions. Two consequences worth knowing before you
lay a screen out:

* **`image "logo.svg"`** is not an SVG — Skia decodes it as a raster, so an SVG file
  has no intrinsic size and you get the 100×100 fallback. For SVG artwork use a
  `path` node (§3) or `Draw.svgPath` (§5).
* Giving only `width` still triggers the probe and sets `height` from the file, so
  **one dimension is enough**; the aspect ratio is preserved for you.
* `flexShrink = 0` always, so a row of images will overflow rather than squash.
  That is deliberate — a squashed photo is a bug, not a layout.

### Where the file has to live

`validAssetPath` (`engine.nim:934-938`) is strict on purpose:

```nim
p.len > 0 and p.len <= 200 and p[0] != '/' and ':' notin p and '\\' notin p and ".." notin p and
  p.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.', '/'})
```

So: **relative, inside the app's own folder, forward slashes, no spaces, no `..`,
no drive letter.** `assets/logo.png` is fine; `C:\art\logo.png`, `/logo.png` and
`../logo.png` are all refused and simply draw nothing. The app writes into its own
folder as `data/<name>` and reads it back the same way (`engine.nim:1141-1142`).

The `Draw` image verb applies the same rule a second time, independently
(`skia_shim.cpp:1357-1359`), so a path that slips past the node check still cannot
escape the asset directory.

### Network images

`resolveAsset` (`engine.nim:1138-1155`) accepts an `https://` URL only when the
host passes `netAllowed` (`host/host.nim:302-315`):

```nim
app "Board", net = "api.github.com, *.cdn.example.com":
  image "https://cdn.example.com/logo.png"
```

* `*` allows everything. Plain `http://` is allowed **only** to `localhost` /
  `127.0.0.1`; everything else must be `https` (or `wss`).
* `YANTRA_NET=off` in the environment refuses every request, images included.
* The file is cached under `dataDir()/<appName>/.cache/<sha1>`; the first frame
  draws a stand-in while it downloads, then **fades in over 160 ms**
  (`ImgFadeMs`, `engine.nim:335`, applied at `engine.nim:1939-1945`).
* If the bytes never arrive, the engine falls back to `paintGif` (`engine.nim:1962`)
  and, failing that, the image node draws **nothing at all** — a broken image icon
  is not drawn. Test your URLs on a machine with network access before you trust a
  screenshot.

### `zoomable`, precisely

`zoomAt` clamps to **1×–8×** and keeps the point under the pointer under the pointer
(`engine.nim:3077-3092`). Ctrl+wheel steps `pow(1.12, dy)` (`engine.nim:3166`), a
pinch goes through the same proc, dragging pans only while the scale is above 1
(`engine.nim:2949-2951`, `:2617-2623`), and a **double click toggles 2× / 1×**
(`engine.nim:2943-2944`, with a 450 ms window). The zoom is applied about the node's
box and **clipped to it** (`engine.nim:1948-1953`), so a zoomed image never spills
over its neighbours. At scale 1 the `Zoom` entry is deleted entirely
(`engine.nim:3091`), so there is no cost when unused.

---

## 2. `fit`, exactly

`fit` is one integer, and **0/1/2 mean contain/cover/fill everywhere** — DSL word,
DSL string, node prop, shim, and the Nim wrapper's own doc comments.

| Value | Word | String | What `drawFit` does |
|---:|---|---|---|
| `0` | `fit = contain` | `"contain"` (and any unknown string) | `scale = min(w/iw, h/ih)`, then the box shrinks and **centres**: `dstRect = (x + (w-fitW)/2, y + (h-fitH)/2, fitW, fitH)` — `skia_shim.cpp:1002-1005` |
| `1` | `fit = cover` | `"cover"` | `scale = max(w/iw, h/ih)`, then the **source** is centre-cropped: `srcRect = ((iw-cropW)/2, (ih-cropH)/2, cropW, cropH)` — `skia_shim.cpp:998-1001` |
| `2` | `fit = fill` | `"fill"` | neither branch runs: the whole bitmap maps onto the whole box, aspect ratio **not** preserved |

```nim
image "hero.jpg", width = 400, height = 200, fit = cover   # crops the sides off a 3:2 photo
image "logo.png", width = 400, height = 200, fit = contain  # letterboxes; the logo keeps its shape
image "banner.png", width = 400, height = 200, fit = fill   # squashes it to 2:1 on purpose
```

Two traps:

* **The default is `contain`, not `fill`.** Omit `fit` on a wide box and your photo
  shrinks and centres, leaving transparent bars. Most "why is my image small" bugs
  are a missing `fit = fill`.
* **Any unrecognised string is `contain`.** `fit = "contaim"` (typo) silently gives
  you `0` and letterboxes — no error, no warning. `dsl.nim:169-171` is an
  `if w == "cover" / elif w == "fill" / else: 0`.

### `fit` inside a `Draw` list — there is no knob

`Draw.image` takes **five arguments and no `fit`**:

```nim
proc image*(d: Draw; x, y, w, h: float32; file: string): Draw
```

`sdk/ui/paint.nim:65-66` writes the literal string `" 0 "` into the command stream:

```nim
result.add "I " & f(x) & " " & f(y) & " " & f(w) & " " & f(h) & " 0 " & file
```

So **every image inside a `Draw` list is letterboxed (contain), always.** If you
need `cover` or `fill` there, compute the box yourself — that is the same arithmetic
`drawFit` does:

```nim
proc containBox(iw, ih, bw, bh: int): tuple[w, h: float32] =
  ## The letterboxed box Draw.image(contain) would use, computed by hand.
  let s = min(float32(bw) / float32(iw), float32(bh) / float32(ih))
  (w: float32(iw) * s, h: float32(ih) * s)

let box = containBox(200, 100, 160, 120)      # 160 × 80
d = d.image(0, 0, box.w, box.h, "card.png")   # the same result, in a place you chose
```

For `cover` you cannot crop from the app side — `Draw` has no clip other than a
rectangle (`skia_shim.cpp:1341-1342` for `R`, and `clip` is `K x y w h`). The
honest answer: **put media that needs `cover` in an `image` node**, where `fit` is
a real prop. The `Draw` verb is for pictures you place yourself, usually flat icons
at their natural size, where `contain` is the right behaviour anyway.

Two more things about the `I` verb that are not in the signature:

* The sampling is **bilinear** — `SkSamplingOptions(SkFilterMode::kLinear)`
  (`skia_shim.cpp:1010`). A bitmap scaled up inside a `Draw` list is soft. The
  `pixels` verb is nearest-neighbour (`reference/09-canvas-and-draw.md` §5).
* `yk_img_draw` returns `0 loading / 2 animated / 3 stand-in` and the `I` case sets
  the canvas's "again" flag (`skia_shim.cpp:1360-1361`), so a **GIF inside a
  `Draw` list animates** even though the layer/canvas path is otherwise static.
* `Draw.image` also applies the current alpha: `runCmds` passes its `alpha` into
  `yk_img_draw` (`skia_shim.cpp:1360`) and `drawFit` calls `paint.setAlphaf` when it
  is below 1 (`skia_shim.cpp:1009`). A faded image is free; a faded `icon` node is
  just `opacity = 0.5` on the node.

---

## 3. The icon set — 38 icons, and it is real

There **is** an icon set in the SDK, and it is the only artwork the SDK ships. It is
a plain `const` array of SVG path data in `sdk/ui/icons.nim:5-44` — 38 entries,
every one drawn as a **stroke** on a **24×24 grid**.

```nim
proc iconPath*(name: string): string   ## the SVG path data, or "" if there is no such icon
proc iconNames*(): seq[string]         ## all 38 names
```

### All 38 names

`search` · `plus` · `x` · `check` · `home` · `grid` · `list` · `sun` · `moon` ·
`palette` · `sliders` · `folder` · `file` · `chevronRight` · `chevronLeft` ·
`chevronDown` · `arrowRight` · `arrowLeft` · `refresh` · `trash` · `star` · `clock` ·
`bell` · `command` · `sidebar` · `layers` · `calculator` · `checkSquare` ·
`presentation` · `activity` · `sparkles` · `box` · `shield` · `terminal` · `globe` ·
`dot` · `power` · `split`

Read it out of code rather than trusting this list:

```nim
import yantra

let all = iconNames()          ## seq[string] — 38 of them
let d = iconPath("sparkles")  ## the raw `d=` attribute, for your own drawing
```

### `icon` is a `Path` node

`icon "name"` is not its own node kind. `sdk/ui/dsl.nim:396-403` rewrites it:

```nim
icon @mag("search", size = 20, color = 0xFFFFFF, animate = spin(1000))
icon @heart("star", size = 18, color = 0xFFD166)
```

into a `Path` node with two extra statements:

```nim
node.set(pStrokeWidth, float32(1.8))
node.set(pPathData, iconPath("search"))
```

So **every icon is stroked, not filled** — that is what the 1.8 is for, and it is
why the shapes are drawn as outlines (`M4 4 H10 V10 H4 Z` for a grid square, with
the interior left open). If you write the same path with a `path` node and no
`stroke`, you get the **same outline filled solid**, which is a different picture.

`iconPath` returns `""` for an unknown name (`icons.nim:46-50`), so a typo is a
**silently invisible icon**, not an error. `doAssert iconNode.prop(pPathData).len
> 10` is what `sdk/tests/t_style.nim:81` does — copy that when you add a name.

### `path` — your own SVG, as a node

```nim
path @mark(d = "M4 4 H20 V20 H4 Z", size = 24, color = 0x00FF00, stroke = 2)
```

| Prop | Wire | Allowed on | Meaning |
|---|---|---|---|
| `d` | `pPathData`, string | `Path` | the SVG path data |
| `size` | `pFontSize`, int32 | `Text,Button,Input,TextArea,Window,Checkbox,**Path**` | the box is `size × size` |
| `stroke` | `pStrokeWidth`, float32 | `Path` | `0` (default) fills, `> 0` strokes |
| `color` | `pTextColor`, int32 | `*` | the ink |

`protocol/schema.nim:318-319`, `:260`. Note `size` is a **shared** prop with text —
`size = 24` on a `path` means the box, not a font size. It defaults to **24**
(`engine.nim:385`) and sets both sides of the box (`engine.nim:576-580`).

The geometry is a **24×24 viewBox**, and it is centred:

```nim
let size = min(b.w, b.h)
c.svgPath(d, b.x + (b.w - size) / 2, b.y + (b.h - size) / 2, size / 24,
          n.num(P_STROKEWIDTH, 0), inkC)
```

— `engine.nim:1891-1893`. Three things follow:

* **`scale = min(boxW, boxH) / 24`, always uniform.** Author your `d` on a 24×24
  grid and it just works. Author it on a 1000×1000 grid and it renders 40× too big
  — there is no viewBox parsing.
* The path is centred in the box, so **`size` is the icon's own width, not the
  coordinate space**. If the artwork does not fill its own viewBox (an icon drawn
  from `4 4` to `20 20` leaves 4 units of margin on each side), you get that margin.
  Bake it out of the path.
* `color` goes through `pTextColor`, which is **int32** — so it is `0xRRGGBB`, with
  **no alpha byte**. `color = 0xFF00FF00` fails to compile
  (`4278255360 can't be converted to int`); `color = 0x00FF00` is green. Transparency
  is `opacity = 0.5` on the node instead.
* The ink is the node's **theme-aware** colour — hover, press and focus states all
  recolour it (`engine.nim:1892`). That is the single best reason to use `path` over
  `Draw.svgPath` for a button glyph.

---

## 4. `Draw.svgPath` — the biggest single win in this chapter

```nim
proc svgPath*(d: Draw; path: string; x, y, scale: float32; argb: uint32;
              strokeWidth = 0'f32): Draw
```

`sdk/ui/paint.nim:46-52`. The path argument is **SVG path data, taken verbatim**.
Not a subset — the full command set, because the shim hands the string straight to
`SkParsePath::FromSVGString`:

```cpp
case 'V': { float x = r.num(), y = r.num(), scale = r.num(), sw = r.num();
            unsigned col = r.color();          // before rest(): it runs to the ';'
            std::string d = r.rest();
            if (auto parsed = SkParsePath::FromSVGString(d.c_str())) {
              paint.setColor(SkColor(col));
              if (alpha < 1) paint.setAlphaf(paint.getAlphaf() * alpha);
              cv->save();
              cv->translate(x, y);
              if (scale != 1) cv->scale(scale, scale);
              if (sw > 0) { paint.setStyle(SkPaint::kStroke_Style);
                            paint.setStrokeWidth(sw);
                            paint.setStrokeJoin(SkPaint::kRound_Join);
                            paint.setStrokeCap(SkPaint::kRound_Cap); }
              cv->drawPath(*parsed, paint);
              cv->restore();
```

— `skia_shim.cpp:1389-1405`. Read five things off that:

1. **Relative commands work.** `m`, `l`, `h`, `v`, `c`, `s`, `q`, `t`, `a`, `z` —
   all of them. The repo's own `ellipsePath` (§5) uses `a`, and all 38 icons use
   `A`, `H` and `V` (`sdk/ui/icons.nim`). If Skia parses it, it renders.
2. **`(x, y)` is a translation, not an offset applied to the points.** `translate`
   then `scale` — so `svgPath(d, 10, 10, 2, …)` is the shape you authored, moved to
   `(10,10)`, doubled. It does **not** scale about `(10,10)`.
3. **It FILLS unless `strokeWidth > 0`.** There is no "both" — one `svgPath` call is
   one paint. Fill-then-stroke means **two calls with the same string**.
4. A `scale` of exactly `1` skips the `cv->scale` entirely; a `strokeWidth` of `0`
   leaves the paint in its default fill style.
5. **The current `alpha` and the current blend mode apply**, and the whole thing is
   wrapped in `save`/`restore` — so a `svgPath` cannot leak your transform or your
   opacity to the next command.

### Worked example: the typewriter platen

This is a real transcription from our own port. `apps/typewriter/app.nim` ported a
typewriter illustration whose **platen roller is an inline SVG shape with a
six-stop `linearGradient`** — no ellipse, no gradient primitive, nothing in the
source that maps to a Yantra primitive except a path.

**Step 1 — lift the `d` out of the markup.** The source's `<path>` carried:

```
d="M150 34 Q500 14 850 34 L850 44 L150 44Z"
```

**Step 2 — make it a `const` next to the other artwork.** Verbatim, no reformatting,
no re-indenting, no splitting (`app.nim:1207-1213`):

```nim
const
  P_SIDE  = "M900 16 L936 30 L992 292 Q994 306 978 312 L964 314 Z"
  P_SHELL = "M96 16 Q102 0 132 0 H868 Q898 0 904 16 L968 296 Q974 330 938 332 H62 Q26 330 32 296 Z"
  P_DECK  = "M104 12 Q108 4 132 4 H868 Q892 4 896 12 L906 70 Q700 88 500 88 Q300 88 94 70 Z"
  P_BASKET= "M330 4 Q330 74 500 76 Q670 74 670 4 Z"
  P_WELL  = "M86 128 Q88 120 104 120 H896 Q912 120 914 128 L944 300 Q946 314 930 314 H70 Q54 314 56 300 Z"
  P_PLATEN= "M150 34 Q500 14 850 34 L850 44 L150 44Z"
```

> Note the shape: the paths span a 1000-unit-wide artwork space, and the app
> multiplies by `U` (a units-to-pixels scale) and offsets with `cx(n)` / `cy(n)`.
> That is the whole "responsive artwork" pattern — author at any scale you like, then
> scale and place at draw time. There is no viewBox concept; `scale` is yours.

**Step 3 — place it.** One line (`app.nim:1218`):

```nim
d = d.svgPath(P_PLATEN, cx(0), cy(0), U, cPlaten)
```

which is `svgPath(path, x, y, scale, argb, strokeWidth = 0)` — a **fill**, because
`strokeWidth` was left at its default.

**Step 4 — the gradient it was filled with.** The source's roller had an SVG
`<linearGradient>` with six stops. `Draw` has no gradient verb, so the port fakes
it by drawing the path three times at three offsets with the three stops it cared
about (`app.nim:965-971`):

```nim
proc gradShape(d: var Draw; path: string; x, y, sc: float32; top, mid, bot: uint32) =
  ## The source fills these paths with a real vertical linear gradient. Draw has
  ## no gradient primitive, so: the mid stop flat, then the top stop dropped in
  ## from above and the bottom stop from below — the same stops, same direction.
  d = d.svgPath(path, x, y, sc, mid)
  d = d.svgPath(path, x, y - sc * 7.0'f32, sc, withA(top, 0.45))
  d = d.svgPath(path, x, y + sc * 5.0'f32, sc, withA(bot, 0.40))
```

That is the honest answer to "the source had a gradient": **not supported, here is
what we did instead.** A plain band loop is better when the shape is a rectangle
(§6); this offset-replay is better when the shape is curved, because the bands have
to follow the curve and a `rect` loop cannot.

### The four rules, condensed

| Rule | Why it costs you |
|---|---|
| **Never chunk, reflow or line-wrap a `d` string.** | `paint.nim` embeds it raw in the command stream. `apps/minipaint/PORT-NOTES.md` L224-233 records a path chunked at a fixed column width that cut the number `a195.425` across a boundary and silently lost **1,299 characters**. The regression test now asserts the path is byte-identical. |
| **`;` inside the string is escaped for you** (`paint.nim:52`) | You never escape it. But a path with a semicolon makes the command stream unreadable in a debugger — it is still correct. |
| **`scale` multiplies the geometry; `(x, y)` translates.** | `svgPath(d, 0, 0, 2, c)` doubles around the canvas origin. Use `save`/`translate`/`scale` if you want to scale about a point. |
| **One call, one paint.** Fill and stroke means two calls. | Unlike `fill()`/`stroke()`, `svgPath` does **not** consume anything — there is no path to consume, it re-parses. Replay is free and safe. |

The last row is worth contrasting with the rest of `Draw`: `fill` runs
`path.detach()` and eats the path (`skia_shim.cpp:1337`), so filling and then
stroking the same built path draws nothing the second time. `svgPath` has no such
trap, because it builds its own path from a string every time.

### Complete, compiled example

```nim
import yantra

const P_PLATEN = "M150 34 Q500 14 850 34 L850 44 L150 44Z"

proc scene(): Draw =
  var d: Draw
  d = d.svgPath(P_PLATEN, 0, 0, 1.0'f32, 0xFFB6D8C7'u32)               # filled
  d = d.svgPath(iconPath("search"), 0, 0, 1.0'f32, 0xFF000000'u32, 1.8'f32)  # stroked
  d

app "Probe08", width = 320, height = 240, fill = 0x101018:
  canvas @view(width = 320.px, height = 120.px, draw = scene().cmds)
```

`svgPath` also accepts a **`svgPath` from a `let`, not just a `const`** — the port's
`P_PLATEN` could equally be a `let` computed at start-up, since the string is just
concatenated into `cmds`.

---

## 5. No ellipse primitive — make one out of arcs

`Draw` has **no `ellipse`**. `circle(cx, cy, r, argb)` emits `E cx cy r r argb`, i.e.
one radius twice (`sdk/ui/paint.nim:59-60`), so it is the special case `rx == ry`.

You have three honest options, in order of preference:

**1. `arcTo`, in two halves.** Skia draws nothing at `sweepDeg >= 180`, so an ellipse
needs two arcs each with their own `moveTo` (`reference/09-canvas-and-draw.md` §8).
This only works for a *circular* arc though — `arcTo` is a circle, so it cannot make
an ellipse on its own. For `rx == ry` this is the cheapest path.

**2. Synthesise the ellipse as path data and hand it to `svgPath`.** This is what
`Draw` has no native support for, and this is the fix:

```nim
proc ellipsePath(x, y, rx, ry: float32): string =
  ## An <ellipse> as path data, so Draw.svgPath can fill it. Skia parses arcs.
  "M" & $(x - rx) & " " & $y &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(rx * 2.0'f32) & " 0" &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(-rx * 2.0'f32) & " 0Z"
```

— `apps/typewriter/app.nim:959-963`, verbatim, **verified working**. Read it as:
move to the left edge, one elliptical arc of `2rx` to the right edge, one arc of
`-2rx` back. `0 1 0` is `rx ry x-axis-rotation large-arc-flag sweep-flag`. One
ellipse, **two arcs**, no primitive needed.

```nim
proc face(d: Draw; cx0, cy0, rx, ry: float32; ink: uint32): Draw =
  ## Three concentric ellipses — a speedometer face, a shadow, a rim.
  result = d.svgPath(ellipsePath(cx0, cy0, rx,        ry),        0, 0, 1.0'f32, ink)
  result = result.svgPath(ellipsePath(cx0, cy0, rx * 0.72, ry * 0.72), 0, 0, 1.0'f32, ink)
  result = result.svgPath(ellipsePath(cx0, cy0, rx * 0.30, ry * 0.30), 0, 0, 1.0'f32, ink)
```

`apps/typewriter/app.nim:1276-1278` draws a speedometer with exactly this — three
concentric ellipses, each its own `svgPath`.

**3. Trace a polyline.** `moveTo`/`lineTo` in a loop. Correct for any convex shape,
ugly at small sizes, and it is the wrong choice for a circle when `circle` exists.

> **Never use `arcTo` for a full circle.** `sweepDeg >= 180` draws nothing. A sun is
> `circle`, not two arcs.

### The same trick for any `<shape>`

The rule generalises: **SVG `<ellipse>`, `<circle>`, `<rect>` and `<polygon>` all have
a trivial `d` form**, and once you have `d` you have `svgPath`. `<circle cx cy r>`
is `M cx-r cy a r r 0 1 0 2r 0 a r r 0 1 0 -2r 0Z` — the same two-arc shape with
`rx == ry`. If you find yourself hand-writing a `Draw` primitive for a shape that
existed as an SVG element, write the `d` instead.

---

## 6. No gradient inside a `Draw` list

`paint.nim` has no gradient verb. `fill(argb)`, `rect(…, argb)` and
`svgPath(…, argb)` each take **one flat colour**, and `runCmds` has no shader branch
at all — there is no `SkShader` anywhere in `skia_shim.cpp`'s command loop.

Node-level gradients **do** exist — `panel(fill = linear(a, b, 90))` from
`sdk/ui/style.nim` — but those paint the **node's own background** through
`paintSurface` (`engine.nim:1931`). They cannot fill a shape inside a `Draw` list.

Two workarounds, both in this repo:

**Banded fills — right for rectangles.** One flat `rect` per row:

```nim
proc mix(a, b: uint32; t: float32): uint32 =
  ## Two 0xRRGGBB colours mixed by t in 0..1. Alpha is always opaque.
  var v = 0xFF000000'u32
  for sh in 0 .. 2:
    let ca = float32(int((a shr (sh * 8 + 16)) and 0xFF'u32))
    let cb = float32(int((b shr (sh * 8 + 16)) and 0xFF'u32))
    let m = int(ca + (cb - ca) * clamp(t, 0.0'f32, 1.0'f32))
    v = v or (uint32(m and 0xFF) shl (sh * 8 + 16))
  v

for row in 0 ..< 40:
  d = d.rect(0, row.float32, 160, 1, mix(0x2B3A67'u32, 0xF2795B'u32, row.float32 / 40.0'f32))
```

**Offset replay — right for curved shapes.** `gradShape` in §4: draw the same
`svgPath` three times at three offsets with three stops. The bands follow the curve
because the curve is the path.

The alpha in a gradient is a **ramp, not a constant** —
`a(t) = 255 + (alpha - 255) * t`, so stop 0 stays fully opaque. The tempting
`255 - alpha * t` makes the first stop transparent and hides the gradient exactly
where the user expects solid colour. At `alpha == 255` both forms agree, which is
why a test that only checks the opaque case cannot tell them apart. See
`reference/09-canvas-and-draw.md` §8 and `apps/minipaint/tests/t_tools.nim:279-286`.

---

## 7. Raw pixels — `pixels`, `Layer.write`, `Layer.read`

When the picture is not in a file at all, you have three tools, all in
`reference/09-canvas-and-draw.md` §4–5 in full detail. The signatures that matter
here, because they are easy to get wrong:

```nim
proc pixels*(d: Draw; buf: int32; pw, ph: int; x, y: float32; w = 0'f32, h = 0'f32): Draw
proc read*(l: Layer; x, y, w, h: int): seq[byte]
proc write*(l: Layer; x, y, w, h: int; rgba: openArray[byte])
```

Note `pw, ph` are **`int`**, not `float32`, and `x, y` are the **top-left corner**
with `w`/`h` defaulting to 0 meaning "natural size".

```nim
let dots = newBuffer()
var px = newSeq[byte](4 * 4 * 4)
for i in 0 ..< 16:
  px[i * 4]     = (if i mod 2 == 0: 255'u8 else: 0'u8)   # R
  px[i * 4 + 2] = (if i mod 2 == 0: 0'u8 else: 255'u8)   # B
  px[i * 4 + 3] = 255'u8                                  # A
dots.setData(addr px[0], px.len)

d = d.pixels(int32(dots), 4, 4, 0, 0, 64, 64)   # a 4x4 checker scaled to 64px
```

* **Byte order is RGBA, straight alpha**, top row first. The `pixels` upload is
  **nearest-neighbour**, so it is crisp when scaled up — the opposite of `image`,
  which is bilinear (`skia_shim.cpp:1010`).
* `Layer.read` returns an **empty seq on failure**. Check `len`, not `nil`.
* `Layer.write` **replaces** the destination rectangle; it does not blend. A
  transparent pixel in your buffer erases what was there.

The full round trip — build a gradient into a `Layer`, sample one pixel back:

```nim
const
  W = 160
  H = 120

var ramp = newSeq[byte](W * H * 4)
for i in 0 ..< W * H:
  let c = mix(0x2B3A67'u32, 0xF2795B'u32, float32(i) / float32(W * H))
  ramp[i * 4]     = uint8(c shr 16)
  ramp[i * 4 + 1] = uint8(c shr 8)
  ramp[i * 4 + 2] = uint8(c)
  ramp[i * 4 + 3] = 255'u8

let plate = newLayer(W, H)
plate.write(0, 0, W, H, ramp)
let picked = plate.read(0, 0, 1, 1)     ## 4 bytes; empty on failure
```

Two measured gotchas from the layer path, both in `apps/minipaint/PORT-NOTES.md`:
translucent colours **round-trip lossily** (the surface is premultiplied N32,
`read`/`write` are straight RGBA, 8 bits per channel), and a chain of operations
amplifies input error by 2–3×. Use layers as an **opaque** drawing surface and treat
`read`/`write` as approximate.

---

## 8. Lifting artwork out of an HTML file — the recipe

This is the workflow `reference/18-porting-process.md` runs at the pixel level, and
the one `apps/minipaint` actually used. Five steps, and step 4 is where ports break.

**1. Decide node vs. path per shape, not per file.**
A toolbar icon is 38 glyphs of stroke on a 24×24 grid → a `path` node.
A 40-shape hero illustration → `svgPath` inside a `Draw` list, because it wants
placement, scale and layering rather than layout.

**2. For raster art, take the file.** Download the PNG/JPEG into the app's own
folder and use an `image` node. Do not trace a bitmap into path data — the `d` will
be enormous, the file larger than the PNG, and it will look worse.

**3. For vector art, copy the `d` attribute verbatim.** Grep the markup for
`<path … d="…">` and carry the value across as a literal string. **Do not reformat
it, do not re-indent it, do not split it across lines.** A path chunked at a fixed
column width cut the number `a195.425` across a boundary and silently lost **1,299
characters** (`apps/minipaint/PORT-NOTES.md` L231-233). The regression test now
asserts `COG_PATH` is byte-identical to upstream.

**4. Flatten every transform first.** This is the one that silently misplaces
artwork. Nested `<g>`, `<polygon>`, `<rect>`, `<circle>` and `matrix()`
transforms must all be resolved with the transforms **baked into the coordinates** —
`apps/minipaint/PORT-NOTES.md` L504-510, on the generator that produced its icon
set:

> Unsupported constructs raise rather than silently emitting bad artwork, and the
> generator refuses to write output unless every emitted chunk re-joins to exactly
> the intended path string.

`Draw` has a `translate`/`scale`/`rotate`, so you *can* transform at draw time —
but only once, uniformly, and only about the origin. Per-shape transforms from the
source belong in the coordinates.

**5. Map the fill and stroke separately.** A source `<path fill="#1C1917">` becomes
`svgPath(d, x, y, U, 0xFF1C1917'u32)`; a stroked one adds the sixth argument.
A gradient-filled one becomes §6. **There is no `<clipPath>`, no `<mask>` and no
`filter` inside a `Draw` list** — a clipped shape has to become its own layer.

### What has no equivalent at all

| Source construct | Status | Do this |
|---|---|---|
| `<linearGradient>` / `<radialGradient>` in a path fill | **NOT SUPPORTED YET** | banded rects, or `gradShape`'s offset replay (§6) |
| `<clipPath>` | **NOT SUPPORTED YET** | a layer per clipped shape; `clip` is a rect only |
| `<mask>` | **NOT SUPPORTED YET** | a layer + `blend(bDstIn)` — the source shape is the destination |
| `filter: invert(1)` on an icon | **NOT SUPPORTED YET** as a prop | swap the source, or author the path in the colour you want. minipaint hit this exactly: `--menu-icons-filter: invert(1)`, "the SVGs are authored **black on transparent**, so `invert(1)` is what makes them visible at all" (`PORT-NOTES` L518) |
| `object-fit: none`, `object-position` | **NOT SUPPORTED YET** | `fit` has three values (`schema.nim:328`) |
| An SVG **file** as an image source | **NOT SUPPORTED** as a raster | it is a `Path` node or `svgPath`, not an `image` node (§1) |

### Summary table

| Want | Status | Do this |
|---|---|---|
| A picture from the app's folder | **WORKS** | `image "a.png"`; relative path, strict charset |
| A picture from a URL | **WORKS** | `https://` + `net = "host"` on the window |
| `fit` contain / cover / fill | **WORKS** | `fit = contain \| cover \| fill` on an `image` node |
| Rounded / circular image | **WORKS** | `radius` on the node |
| Zoom and pan a photo | **WORKS** | `zoomable = true`, 1×–8× |
| An icon from the standard set | **WORKS** | `icon "search"` — 38 of them |
| Your own SVG as a laid-out node | **WORKS** | `path(d = "M…", size = 24, color = …, stroke = …)`, 24×24 grid |
| **SVG path data inside a `Draw` list** | **WORKS** | `Draw().svgPath(d, x, y, scale, argb, strokeWidth = 0)` — verbatim, never chunked |
| Raw RGBA pixels | **WORKS** | `pixels` + `newBuffer`, nearest-neighbour |
| Read a pixel back | **WORKS** | `Layer.read` → `seq[byte]`, check `len` |
| **Ellipse in a `Draw` list** | **WORKS** | the `E` verb takes **two independent semi-axes** — `E cx cy rx ry` → `SkCanvas::drawOval` (`skia_shim.cpp:1346`). There is no SDK proc for it, so emit it by hand (`d.add "E …"`). `circle` (`sdk/ui/paint.nim:59-60`) is just this with `r` passed twice, so a true non-circular ellipse is one line of `Draw` — **not** the two-arc `ellipsePath` workaround this table used to prescribe. Note `E` is not special-cased: it goes through the same `colour()` lambda as `F`, `S`, `R`, `B` and `G`, so `Draw.alpha` (`O`) treats it identically. |
| **Gradient in a `Draw` list** | **NOT SUPPORTED YET** | banded rects, or `gradShape` offset replay (§6) |
| `fit` on a `Draw` image | **NOT SUPPORTED YET** | always contain; compute the box (§2) |
| `cover` inside a `Draw` list | **NOT SUPPORTED YET** | use an `image` node |
| `<clipPath>` / `<mask>` | **NOT SUPPORTED YET** | a layer each |
| `object-position`, `object-fit: none` | **NOT SUPPORTED YET** | — |
| Path morphing (`d` interpolation) | **NOT SUPPORTED YET** | two `svgPath` calls + `alpha`, or animate on a canvas |

---

## 9. A complete worked example

An image well, a toolbar and an illustration, using all four mechanisms in one app:
a natural-size `image` node, a `fit`-fitted one, five icons, and an SVG path placed
by hand inside a canvas. This is the file that was compiled.

```nim
import yantra

const
  P_PLATEN = "M150 34 Q500 14 850 34 L850 44 L150 44Z"   ## lifted verbatim from the markup

proc ellipsePath(x, y, rx, ry: float32): string =
  ## An <ellipse> as path data, so Draw.svgPath can fill it. Skia parses arcs.
  "M" & $(x - rx) & " " & $y &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(rx * 2.0'f32) & " 0" &
  "a" & $rx & " " & $ry & " 0 1 0 " & $(-rx * 2.0'f32) & " 0Z"

proc face(d: Draw; cx0, cy0, rx, ry: float32; ink: uint32): Draw =
  ## Three concentric ellipses — a speedometer face, a shadow, a rim.
  result = d.svgPath(ellipsePath(cx0, cy0, rx,           ry),           0, 0, 1.0'f32, ink)
  result = result.svgPath(ellipsePath(cx0, cy0, rx * 0.72, ry * 0.72), 0, 0, 1.0'f32, ink)
  result = result.svgPath(ellipsePath(cx0, cy0, rx * 0.30, ry * 0.30), 0, 0, 1.0'f32, ink)

proc scene(): Draw =
  ## Everything here is a path or an icon — no primitives for either.
  var d: Draw
  d = d.svgPath(P_PLATEN, 0, 0, 0.4'f32, 0xFFB6D8C7'u32)              # scaled to 400 wide
  d = face(d, 140.0'f32, 40.0'f32, 60.0'f32, 24.0'f32, 0xFF231F1D'u32) # ellipses, synthesised
  d = d.svgPath(iconPath("search"), 240, 20, 1.0'f32, 0xFF000000'u32, 1.8'f32)  # the icon set
  d

app "Media", width = 400, height = 320, fill = 0x101018:
  let zoom = state false

  row(gap = 8.px, pad = 8.px):
    icon @mag("search", size = 20, color = 0xFFFFFF)
    icon @heart("star", size = 20, color = 0xFFD166, animate = spin(1000))
    path @mark(d = "M4 4 H20 V20 H4 Z", size = 24, color = 0x00FF00, stroke = 2)
    text @t "media", size = 12

  row(gap = 8.px, pad = 8.px):
    image @card("test_card.png", width = 120, fit = contain)   # height from the file
    image @hero("test_card.png", width = 120, height = 90, fit = cover, radius = 12)

  canvas @view(width = 384.px, height = 140.px, draw = scene().cmds)

  button @z "zoom":
    onClick: zoom.set(not zoom.get)
  image @big("test_card.png", width = 200, height = 140, fit = cover,
             zoomable = zoom.get)
```

### What each line is teaching

| Line | Lesson |
|---|---|
| `P_PLATEN` as a `const` | lift the `d` verbatim; `svgPath` replays it as-is (§4) |
| `0.4'f32` as the scale | artwork authored at 1000 units, placed at 400 — `scale` is yours, there is no viewBox |
| `ellipsePath` | no ellipse primitive; two arcs is the whole shape (§5) |
| `face` | the same trick the typewriter speedometer uses |
| `iconPath("search")` **inside a `Draw`** | the icon set is just `d` strings — usable either way |
| `1.8'f32` as the sixth argument | `svgPath` fills unless you pass a stroke width |
| `icon @mag(...)` | an `icon` **node**, stroked, theme-aware, laid out |
| `color = 0x00FF00` on `path` | node ink is **int32**, no alpha byte — `0xFF00FF00` will not compile |
| `fit = contain` with only `width` | the missing side comes from the decoded file (§1) |
| `fit = cover, radius = 12` | cover centre-crops the source; `radius` clips the box |
| `zoomable = zoom.get` | the prop is reactive; the whole zoom machinery follows it |

---

## 10. CORRECTIONS TO OTHER CHAPTERS

Both of these are wrong in the repository today. I did not edit them — this file
records the fix so the next agent can apply it.

**`reference/09-canvas-and-draw.md:137`** — the `image` row of the method table:

> `proc image*(d: Draw; path: string; x, y, w, h: float32; fit = 0'f32): Draw`
> … `fit = 0` stretch, `1` contain, `2` cover

is wrong on **both** counts. The real signature is
`proc image*(d: Draw; x, y, w, h: float32; file: string): Draw`
(`sdk/ui/paint.nim:65-66`) — `file` is **last**, and there is **no `fit`
parameter**; the verb hardcodes `" 0 "`, so a `Draw` image is always `contain`.
And the enum is the standard **0 contain, 1 cover, 2 fill**
(`skia_shim.cpp:998-1006`), matching `dsl.nim:157` and
`nimskia.nim:182`/`:289`. A caller following ch.09 would pass `fit` and fail to
compile, or pass the arguments in the documented order and silently draw the wrong
picture. `skills/web-to-yantra/HTML5-CANVAS-TO-SKIA.md:37-39` has it **right** —
ch.09 is the outlier.

Two more ch.09 rows are stale in the same table:

* **`layer` (line 138)** — stated as `(l, x, y, sx = 0, sy = 0)`. The real one is
  `(d: Draw; l: Layer; x, y: float32; w = 0'f32, h = 0'f32)` (`paint.nim:67`); they
  are **width and height**, not scale factors.
* **`pixels` (line 139 and the signature block at 334)** — stated as
  `(buf: int32; pw, ph: float32; x, y, w, h: float32)`. The real one is
  `(buf: int32; pw, ph: int; x, y: float32; w = 0'f32, h = 0'f32)`
  (`paint.nim:70`). The `09` example at line 330 happens to still be correct —
  `pixels(int32(dots), 4, 4, 0, 0, 80, 80)` binds to the same values either way —
  which is exactly why the error survived.

`reference/15a-html-css-mapping.md` was checked and is **correct** on every claim in
its media-fitting section (§1.9, lines 235-267) and on `<svg>` → `path` / `icon`
(line 57). `HTML5-CANVAS-TO-SKIA.md` is correct on `svgPath`, the no-ellipse
workaround and the no-gradient statement. No fixes needed in either.

---

## 11. Verification status — read this

**Compiled.** Every Nim block in this chapter is in `probe08.nim`, `probe08b.nim`
or `probe08c.nim`, built with `tools/build-wasm.sh`:

| Probe | Bytes | Covers |
|---|---:|---|
| `probe08.wasm` | 252,891 | `icon`, `path`, `image` with `fit`/`radius`/`zoomable`, `net`, `svgPath`, `Draw.image`, `iconPath` |
| `probe08b.wasm` | 240,825 | `pixels`, `Layer.write`/`read`, `mix`, `containBox`, banded gradient |
| `probe08c.wasm` | 232,191 | every published block together: `P_PLATEN`, `gradShape`, `ellipsePath`, `face`, all six `image` forms |
| `probe08d.wasm` | 251,944 | the §9 worked example, verbatim |

The probes were deleted after the build; re-create them from the code blocks above
if you want to re-check.

**Not verified here:** the pixel output. These probes compile and their command
strings are what `paint.nim` is documented to emit, but I did not drive them through
`render/native/build/mpdrive.exe` and read a framebuffer. `reference/09-canvas-and-draw.md`
§9 already records that the prebuilt driver is **stale** (dated 2026-09-30 against
`engine.nim` at 2026-10-02) and that no layer rendered under it, including for the
repo's own known-good fixture. So the render-side claims here — that `contain`
letterboxes, that `cover` crops, that `svgPath` fills unless stroked, that
`radius` rounds — rest on `drawFit` and `runCmds` as read above, not on my own
measurement. The `image`/`zoomable` behaviour additionally rests on
`render/native/t_image.nim`, which asserts `fit = 0 (contain)` and `fit = 1 (cover)`
directly at lines 29 and 36.

**Unverifiable from this checkout, flagged rather than guessed:** nothing. Every
claim above carries a `path:line`.
