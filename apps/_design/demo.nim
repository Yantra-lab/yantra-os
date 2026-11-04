## demo.nim — the design system's own proof.
##
## One source, two builds. The whole point is a controlled experiment:
##
##   YANTRA_NIM_FLAGS=-d:adhoc → the "before": a screen built the way apps used to be
##                               built — a 9 px label, gaps of 7 and 22, four different
##                               radii, a full-saturation accent, a hairline that
##                               vanishes, no focus ring, no dimmed disabled state.
##   plain                     → the "after": the same screen, same words, same layout
##                               intent, every number taken from `design.nim`.
##
## Nothing but the design decisions changes between the two builds: same copy, same
## node kinds, same window. So a difference in the measured frame is a difference the
## design system made.
##
## Build and measure (the same commands are in `_design/README.md`):
##   cd yantra-os
##   bash tools/build-wasm.sh apps/_design/demo.nim /tmp/demo-after.wasm --release
##   YANTRA_NIM_FLAGS=-d:adhoc bash tools/build-wasm.sh apps/_design/demo.nim /tmp/demo-before.wasm --release
##   /tmp/stage1/yantra --screenshot=/tmp/demo-after.png --frames=8 /tmp/demo-after.wasm

import yantra
import design

const
  WinW = 1080
  WinH = 720

when defined(adhoc):
  # The ad-hoc values: what a screen looks like before it has a system. Not a straw
  # man — `9` is the size the flagship HUDs ship, `0x66799C` is their label colour,
  # `22`/`7` are real gaps from one of them.
  const
    cLabelSize = 9
    cSmallSize = 13
    cTitleSize = 24
    cBigSize = 27
    cPad       = 13
    cGap       = 7
    cGapWide   = 22
    cR1 = 5
    cR2 = 9
    cR3 = 11
    cR4 = 14
    cLabelCol  = 0x66799C
    cHairline  = 0x16203A
    cDimInk    = 0x5A6C8C
else:
  const
    cLabelSize = FsMicro
    cSmallSize = FsSmall
    cTitleSize = FsTitle
    cBigSize   = FsTitleLg
    cPad       = Sp4
    cGap       = Sp2
    cGapWide   = Sp6
    cR1 = RsSm
    cR2 = RsCtl
    cR3 = RsCtl
    cR4 = RsCard
    cLabelCol  = 0x8C8C96    # theme().muted for Midnight, stated so both builds differ only in choice
    cHairline  = 0x3A3A46
    cDimInk    = 0xA7A7B0

app("Design"):
  column(width = WinW, height = WinH, fill = theme().bg,
         gap = cGapWide, pad = cPad * 2, alignItems = 1):

    # ── the header: an eyebrow, a title, and the two primary actions ───────────
    row(width = WinW - cPad * 4, gap = cGapWide, alignItems = 1):
      column(gap = cGap, grow = 1):
        text "STAGE 03", size = cLabelSize, weight = 700, color = cLabelCol
        text "Harbour line", size = cTitleSize, weight = 700, color = theme().text
      button("Start run", radius = cR2, padX = cPad, padY = cGap,
             fill = theme().accent, color = theme().accentText,
             size = cSmallSize, weight = 700):
        hover:
          opacity = 0.92
        pressed:
          opacity = 0.84
        focused:
          borderColor = theme().accent
      button("Stop", radius = cR2, padX = cPad, padY = cGap,
             fill = theme().surface2, color = theme().text,
             size = cSmallSize, weight = 600):
        hover:
          fill = theme().surface3
        pressed:
          fill = theme().surface3
          opacity = 0.9
        focused:
          borderColor = theme().accent

    # ── the HUD: three counters, a micro label over a number ──────────────────
    panel(width = WinW - cPad * 4, radius = cR4, pad = cPad + cGap,
          gap = cGapWide, fill = theme().surface):
      row(gap = cGapWide, alignItems = 1):
        column(gap = cGap):
          text "ELAPSED", size = cLabelSize, weight = 700, color = cLabelCol
          text "02:14", size = cBigSize, weight = 800, color = theme().text, font = theme().mono
        column(gap = cGap):
          text "DISTANCE", size = cLabelSize, weight = 700, color = cLabelCol
          text "8.4 km", size = cBigSize, weight = 800, color = theme().accent, font = theme().mono
        column(gap = cGap):
          text "SPLIT", size = cLabelSize, weight = 700, color = cLabelCol
          text "+0.61", size = cBigSize, weight = 800, color = theme().danger, font = theme().mono

    # ── the list: three rows, each a real surface with a real hairline ────────
    panel(width = WinW - cPad * 4, radius = cR3, pad = cPad, gap = cGapWide,
          fill = theme().surface, border = 1, borderColor = cHairline, alignItems = 1):
      row(gap = cGapWide, alignItems = 1):
        column(gap = cGap, grow = 1):
          text "North quay", size = cSmallSize, weight = 600, color = theme().text
          text "3 checkpoints · last 14:20", size = cLabelSize, weight = 500, color = cLabelCol
        panel(radius = cR1, padX = cPad, padY = cGap, fill = theme().accentSoft):
          text "live", size = cLabelSize, weight = 700, color = theme().accent

    panel(width = WinW - cPad * 4, radius = cR3, pad = cPad, gap = cGapWide,
          fill = theme().surface, border = 1, borderColor = cHairline, alignItems = 1):
      row(gap = cGapWide, alignItems = 1):
        column(gap = cGap, grow = 1):
          text "Low tide shelf", size = cSmallSize, weight = 600, color = theme().text
          text "3 checkpoints · last 14:02", size = cLabelSize, weight = 500, color = cLabelCol
        panel(radius = cR1, padX = cPad, padY = cGap, fill = theme().success):
          text "done", size = cLabelSize, weight = 700, color = theme().bg

    panel(width = WinW - cPad * 4, radius = cR3, pad = cPad, gap = cGapWide,
          fill = theme().surface, border = 1, borderColor = cHairline, alignItems = 1):
      row(gap = cGapWide, alignItems = 1):
        column(gap = cGap, grow = 1):
          text "Bell buoy reach", size = cSmallSize, weight = 600, color = theme().text
          text "3 checkpoints · last 13:48", size = cLabelSize, weight = 500, color = cLabelCol
        panel(radius = cR1, padX = cPad, padY = cGap, fill = theme().surface3):
          text "queued", size = cLabelSize, weight = 700, color = cLabelCol

    # ── the footer: the muted line, and the one disabled control ──────────────
    row(width = WinW - cPad * 4, gap = cGapWide, alignItems = 1):
      text "3 stages · 2 completed", size = cSmallSize, weight = 500, color = cLabelCol, grow = 1
      panel(radius = cR2, padX = cPad, padY = cGap, fill = theme().surface2,
            border = 1, borderColor = cHairline):
        text "Next stage", size = cSmallSize, weight = 600, color = cDimInk
