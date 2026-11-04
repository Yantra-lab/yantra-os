# `apps/poster` — the real poster image, staged but not yet wired

**Status: the asset is committed here; `app.nim` is untouched.** Adding one line to a
shared `app.nim` was the lead's call, so the diff below is proposed, not applied.

## What is here

| file | bytes | sha256 |
|---|---|---|
| `assets/yantra-poster.png` | 578,954 | `40e08bbeaee872ef61ad4e8588071a0ae1644ce6a4cf21516e8d28a0ad2d1f14` |

A real `black-forest-labs/FLUX.2-klein-4B` render, 1024×1024 RGB, seed 7, 4 steps,
revision `e7b7dc27f91deacad38e78976d1f2b499d76a294`, pulled out of
`/tmp/gpu-fleet/out/` by `apps/_assets/fetch.sh` and hash-verified. Full row in
[`../_assets/PROVENANCE.tsv`](../_assets/PROVENANCE.tsv). The prompt is the fleet's
own, recorded in `/tmp/gpu-fleet/logs/gen1.json` — it was written for a poster of this
project, so it belongs to this app rather than to a demo.

It is byte-identical to `../_assets/demo/assets/poster.png`; the duplicate is deliberate,
because `resolveAsset` is `appDir / path` (`render/native/engine.nim:1193-1201`) and an
app cannot read a sibling app's folder. 579 KB twice is the price of the sandbox.

## Proposed diff (one line, not applied)

`app.nim:328` already holds the sheet:

```nim
    Canvas(draw = posterCommands(seed, motif, palette, layout, density, gridOn), width = 640px, height = 824px, absolute = true, left = 40px, top = 80px):
```

The image goes in the same `Stack`, after the `Canvas`, so a real poster covers the drawn
sheet while the controls keep working:

```nim
    Image("assets/yantra-poster.png", width = 640px, height = 824px, fit = cover,
          absolute = true, left = 40px, top = 80px)
```

`fit = 2` is `fill` and `1` is `cover` (`08-images-icons-and-svg.md` §2); `cover` keeps the
1024² square's centre without letterboxing. No new import is needed — `Image` is a node
kind, not a host call.

## The blocker is the engine binary, not this app

The prebuilt `/tmp/stage1/yantra` **refuses to instantiate `poster` at all**:

```
$ /tmp/stage1/yantra --screenshot=/tmp/p.png --frames=8 "$PWD/apps/poster/app.wasm"
host.nim(1325)           loadAppBytes
Error: unhandled exception: app requires unavailable import 'y_layer_save_png'
       — refusing to instantiate [WasmtimeError]
[exit 1]
```

Measured 2026-11-06, the same failure `docs/DEMO-READY.md` §5 records. But:

* `strings /tmp/stage1/yantra | grep -c y_layer_save_png` → **0**;
* the binary exposes only `y_layer_color_to_paint, draw, filter, free, new, read, write`;
* **this worktree's `host/host.nim:1222` does export it** —
  `result["y_layer_save_png"] = ImportSpec(...)`;
* the shared repo's `host/host.nim` (and `yantra-os/host/host.nim`) do not.

So the source is already fixed on this branch and the binary is stale. **Rebuilding the
engine from a tree that includes `host/host.nim:1222` is the whole fix** — no code change
to this app, and the artwork above is waiting for it. Until that rebuild exists, the
asset→engine→pixel path is proven in [`../_assets/`](../_assets/) instead, which needs no
such import.
