# 24 — Alpha ramps, vignettes and the `dst-out` eraser

*Read this before porting any vignette, glow, light pool, fog or spotlight. It explains why
the two obvious implementations both silently destroy the frame, and gives the one that works.*

A radial gradient that is **transparent in the middle and opaque at the edge** — a
vignette, a light pool, a fog falloff — cannot be built from the `Draw` API's disc
primitive. Two distinct wrong approaches both "work" until they silently destroy the
frame behind them.

## Trap 1 — nested discs compound absolute alpha

The obvious helper is "draw the discs largest first, each at its stop's alpha,
so they accumulate toward the centre":

```nim
proc rampDisc(d: var Draw; cx, cy, r: float32; stops: openArray[Stop]; n = 24) =
  var i = n
  while i > 0:
    let f = float32(i) / float32(n)
    d = d.circle(cx, cy, r * f, sampleStops(stops, f))
    dec i
```

Every smaller disc **repaints the centre** at its own absolute alpha. N discs
composite to `1 - Π(1 - aᵢ)` at the centre. With 28 discs at up to 0.55 that is
effectively opaque, no matter what the stops say.

Incremental alpha does not rescue it. Drawing largest-first, the incremental for ring
*i* is `(A(fᵢ) - A(fᵢ₋₁)) / (1 - A(fᵢ₋₁))`. For a vignette `A` *decreases* from the
edge toward the centre, so **every increment after the outermost is negative.** A
transparent-centre ramp is simply not expressible this way.

`rampDisc` is only valid when the stop alpha is constant.

## Trap 2 — `dst-out` erases the whole canvas, not just the ring

The natural fix is to build each ring as "fill the outer ellipse, knock out the inner
one":

```nim
# NOTE: there is NO `ell` proc in the SDK. `circle(cx, cy, r, argb)` (paint.nim:59) is
# the only oval — it emits `E cx cy r r argb`, one radius twice. There is no polygon
# primitive either (a polygon is moveTo/lineTo/close/fill, paint.nim:28,29,45,53), and
# `svgPath` DOES exist (paint.nim:46, emits `V `, handled at skia_shim.cpp:1389-1407).
# So an axis-aligned ellipse is four `curveTo` calls (paint.nim:35) or one `svgPath`
# with elliptical arcs — see `08-images-icons-and-svg.md:19` and
# `09-canvas-and-draw.md` §8. Apps that need a true non-circular ellipse define their own
# helper, and that helper then reads like SDK API. It isn't.
d = d.blend(eraser).circle(cx, cy, maxr * f0, 0xFF000000'u32).blend(bSrcOver)
```

> **CORRECTED 2026-10-03 — the "no ellipse proc" note above used to say only "Apps that need
> a true non-circular ellipse define their own helper", with no workaround named.** That was
> incomplete, not false. `curveTo` (`sdk/ui/paint.nim:35`) and `svgPath` (`sdk/ui/paint.nim:46`)
> are both real SDK API and either one draws an ellipse. The correct rule: `circle` is the
> only *oval proc* and it forces `rx == ry`; the ellipse workarounds are four cubics or an SVG
> path.

`eraser` is `bDstOut` (`sdk/ui/paint.nim:21`), ordinal 8 — inside
`SkBlendMode::kLastMode`, and the shim *does* apply it: every command gets
`paint.setBlendMode(blend)` at `skia_shim.cpp:1326`, and the ordinal is range-guarded at
`:1366` (`if (m >= 0 && m <= (int)SkBlendMode::kLastMode)`). The blend is not
the problem.

**`dst-out` operates on the entire canvas, not on the shape.** Every ring's knock-out
therefore deletes the backdrop that was drawn before it — the room gradient, the
rendered layer, everything. The result is a canvas that is black where your scene
should be, with no error anywhere.

> ~~"This is why the typewriter is immune and the gallery was not. The typewriter's lamp
> (`apps/typewriter/app.nim:415`) uses the same eraser trick, but it runs **inside its own
> layer bitmap**. An eraser confined to an offscreen surface is safe."~~
>
> **CORRECTED 2026-10-03 — this example was false, and it was citing the file that
> disproves it.** `apps/typewriter/app.nim:412-416` reads, in its own doc comment:
>
> > "It is deliberately NOT built from disc-fill + `eraser` (bDstOut) as an earlier revision
> > was: bDstOut knocks the hole through everything already painted in the layer, so every
> > ring erased the walnut under it and the desk came out with a lamp-sized hole in it —
> > visible as flat window background across the whole scene. Stroking needs no hole."
>
> So the typewriter did **not** use the eraser trick, and its safety was **not** immunity by
> virtue of running in a layer — it was *removing the trick*. A `bDstOut` eraser confined to
> an offscreen layer is still a bad idea, because the layer usually already contains the
> backdrop you were going to knock out.
>
> The rule that survives the correction: **`blend(eraser)` is destructive to everything
> already drawn in the same surface, layer or not.** The safe shape is a dedicated
> transparent layer per ramp, drawn on an empty surface.

## Do's

- **Give `blend(eraser)` a dedicated, still-empty layer of its own.** A layer that already
  holds the backdrop you want to knock out is exactly the failure the typewriter hit. On the
  main canvas it is destructive; in a layer it is destructive *to that layer's contents*,
  which is only safe if you drew nothing else there yet.
- **Force the alpha byte on every ramp colour.** Ring helpers that build colours by
  arithmetic will happily produce a `0x00` alpha and render an invisible vignette —
  `sdk/ui/paint.nim:28-82` takes `argb: uint32` in `0xAARRGGBB`, and a `Draw` colour gets
  **no** missing-alpha promotion from the engine (`render/native/engine.nim:345-348` does
  that for node props only; the shim does a bare `paint.setColor` at
  `skia_shim.cpp:1327`). See `09-canvas-and-draw.md` §3.
- **Verify a radial helper by measuring, not by reading it.** Paint it, run
  `tools/census2.mjs`, and check the *centre* pixel and a corner — not just that it
  built.
- **Bisect by disabling, not by reasoning.** Turning the suspect passes off and
  re-measuring settled in one run what several rounds of reading had not.
- **Check the stop direction first.** Alpha increasing outward (vignette) is the hard
  case. Alpha decreasing outward (glow) nests more happily.

## Don'ts

- Don't assume `dst-out` is scoped to the shape that triggered it.
- Don't trust a doc comment on a helper you haven't run; `rampDisc`'s own comment
  claimed the accumulation "matches the continuous ramp", which is false.
- Don't read a byte-identical frame across two code paths as evidence that neither
  path matters. It usually means something upstream already destroyed the frame for
  both. See `21-visual-parity-verification.md` §on dead frames.
- Don't ship a nested-disc vignette as "close enough" — it is opaque, and the failure
  reads as an empty scene rather than as a gradient bug.

## Working alternatives

1. **Single-buffer blit.** Build the whole ramp as one RGBA buffer and emit it with
   the `X` command. Exact per-pixel alpha, no blending involved. Costs one buffer.
2. **Flat rings, no eraser — and this is the one that actually works.** Build each band
   **between two boundaries** as a path, and draw every band **exactly once** at the
   **cumulative** alpha `1 - p` for that band's position `p`, not the per-band increment.

   The reason nested fills cannot work is geometric, and the symptom is misleading:
   **a filled ellipse carrying alpha also covers its own centre.** Alpha cannot be
   subtracted once painted. Drawing outside-in puts the rim over the whole frame; drawing
   inside-out puts it on the centre. Neither is a ramp, and both read as "the gradient is
   too strong" rather than as "this shape cannot express this ramp".

   An **annulus** fixes it because a band drawn *between* two contours is always
   geometrically contained within its outer contour, so no band ever repaints another's
   interior. That is the same invariant as the winding fix in `09-canvas-and-draw.md`:
   a hole only knocks out if it is wound opposite **and** contained; an overhanging hole
   fills instead.

   Note `1 - p`, the **cumulative** alpha. Using the per-band increment here reproduces
   Trap 1 exactly: too faint at the rim, opaque at the core. Then **measure the centre
   and a corner** after building it — a ramp that is uniformly wrong reads as "close
   enough" from the mean alone.
3. **Push it into the renderer.** If a real gradient primitive is warranted often
   enough, that is a `DECISION_QUEUE.md` item, not something to fake per app. The wire
   format genuinely cannot express it today: `runCmds` has **no gradient-fill verb**, and
   `K` (`skia_shim.cpp:1408`) — the only clip — is `clipRect`, an axis-aligned rect. So
   `fill:url(#gradient)` on a `<path>` is not a workaround problem at all: shape and paint
   are separate verbs and neither composes.
