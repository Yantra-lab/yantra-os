## Asset Lab — the two asset paths into the engine, in one frame.
##
##   left  : `image "assets/poster.png"`           bytes -> Skia decode -> pixels
##   right : `model "assets/mesh.glb"`             bytes -> glTF 2.0 -> Filament -> pixels
##
## Both nodes read their file from THIS app's own folder, by a relative path
## (`resolveAsset`, render/native/engine.nim:1193-1201 — `appDir / p`), which is the
## whole point of `apps/_assets`: one contract, demonstrated rather than described.
## The sizes and gaps are the shared design system's, not this app's own
## (`../../_design/design`) — `python3 apps/_design/audit.py apps/_assets/demo/app.nim`
## is clean at 0 findings.
##
## Run:
##   /tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 <abs>/apps/_assets/demo/app.wasm
## Measure with apps/_assets/measure.py, then crop the node boxes the engine reports:
##   /tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 --script="boxes" <abs>/app.wasm

import "../../_design/design"

const
  bg = 0x0B0D12                 ## C1: ink/bg 16.39, dim/bg 6.83 — both clear 4.5
  ink = 0xE8ECF2
  dim = 0x8E9AAE

app("Asset Lab", width = 1012, height = 596, fill = bg):
  column(pad = Sp4, gap = Sp3):
    row(gap = Sp2):
      text "ASSET LAB", size = FsSmall, weight = W700, color = ink
      text "apps/_assets — the asset contract, running", size = FsSmall, weight = W500, color = dim
    row(gap = Sp3):
      column(width = 480, gap = Sp2):
        text "2D image node · assets/poster.png", size = FsMicro, weight = W600, color = dim
        image "assets/poster.png", width = 480, height = 500, fit = cover, radius = 10
      column(width = 480, gap = Sp2):
        text "3D glTF 2.0 · assets/mesh.glb", size = FsMicro, weight = W600, color = dim
        model "assets/mesh.glb", width = 480, height = 500
