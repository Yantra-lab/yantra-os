## design.nim — the one design system every Yantra OS app shares.
##
## TOKENS, NOT TASTE. Every number an app needs to set a text size, a gap, a radius,
## a duration or a label/background colour pair comes from this file, and the file
## proves its own colour pairs with `selfCheck()`.
##
## WHY THIS EXISTS
##   An app that invents its own sizes drifts: one screen at 9px beside another at 20px,
##   gaps of 7 and 13, three different accent colours, a pressed state that never fires.
##   The rules here are the ones an outside reviewer can check mechanically, distilled
##   from Anthropic's frontend skills and the public design rule-sets — see
##   `skills/yantra/reference/25-frontend-craft-rules.md` for each rule's source.
##
## HOW TO USE IT
##   import ../../sdk/yantra          # or let config.nims do it
##   import ../_design/design         # relative to apps/<id>/app.nim
##
##   # declarative apps
##   Column(gap = Sp4, pad = Sp6, fill = surface):
##     Text "Stages", size = FsTitle, weight = W600, color = text
##     Text "three laps", size = FsSmall, weight = W500, color = muted
##     Button "Start", use = ctlPrimary()
##
##   # imperative apps
##   let b = button(row, "Start")
##   typeOn(b, FsSmall, W700)
##   ctlOn(b, ctlFill(), text)
##
##   # the states every control owes its user
##   b.onHover(proc() = b.setFill(ctlFillHover()))
##   b.onFocus(proc() = focusRing(b))
##
## THE RULES THIS FILE ENFORCES (ids match 25-frontend-craft-rules.md)
##   T1 no size outside the scale        S1 no gap/pad outside the 4-pt rhythm
##   R1 no radius outside {6, 10, 16}    C1 body text >= 4.5:1, large >= 3:1
##   C4 `faint` is not a label colour    M1 durations come from the motion bands
##   X2 every control has a visible focus ring
##
## NOT SUPPORTED YET: letter-spacing/tracking (Text has no such prop), per-node
## cubic-bezier easing (the wire carries an Easing index, not a control-point list),
## and a real reduced-motion signal from the OS. Workarounds are in
## `skills/yantra/reference/26-frontend-gaps.md`.

import std/[math, strutils]
import yantra

# ══════════════════════════════════════════════════════════════════════════════
# 1 · TYPE — T1: a closed scale. Eight steps, nothing else.
# ══════════════════════════════════════════════════════════════════════════════
#
# The scale is a hand-tuned 1.25-ish ladder rounded to whole pixels, because the
# engine takes integer px (`size` is a length prop, `sdk/ui/dsl.nim:92`). 11 px is
# the floor: below it a label stops being legible at 1440x900 on a 1x display, and
# the flagships were shipping 9 px HUD labels.

const
  FsMicro* = 11   ## T2 · the smallest legal label. Micro-caps, weight >= 600.
  FsSmall* = 12   ## helper text, table rows, HUD units
  FsBody*  = 14   ## running text
  FsBodyLg* = 16  ## emphasised body, list titles
  FsTitle* = 20   ## section titles
  FsTitleLg* = 26  ## screen titles, big HUD counters
  FsDisplay* = 34  ## the one number a screen is about
  FsHero*  = 46   ## a title screen; at most once per app

  W400* = 400
  W500* = 500
  W600* = 600
  W700* = 700
  W800* = 800

  # T4 · line height is a MULTIPLE, not px (`sdk/ui/...`: `lineHeight` is written raw,
  # not through lengthProps). 1.45 for running text, 1.15 for a display line.
  LhBody*    = 1.45
  LhTight*   = 1.15

  # T6 · the runner-up rule: no screen may use more than five distinct sizes.
  MaxSizesPerScreen* = 5

const
  typeScale*: array[8, int] = [FsMicro, FsSmall, FsBody, FsBodyLg, FsTitle, FsTitleLg, FsDisplay, FsHero]
    ## T1 in executable form: `isOnScale(n)` is the check.
  weightScale*: array[5, int] = [W400, W500, W600, W700, W800]

proc isOnScale*(px: int): bool =
  ## T1 — true when `px` is one of the eight legal sizes.
  for s in typeScale:
    if s == px: return true
  false

proc nearestStep*(px: int): int =
  ## T1's repair step: the legal size closest to a stray one (`nearestStep(9) == 11`).
  result = typeScale[0]
  for s in typeScale:
    if abs(s - px) < abs(result - px): result = s

proc isOnWeight*(w: int): bool =
  for s in weightScale:
    if s == w: return true
  false

# ══════════════════════════════════════════════════════════════════════════════
# 2 · SPACE — S1: one 4-pt rhythm.
# ══════════════════════════════════════════════════════════════════════════════
#
# Seven steps. Anything not on this list is a decision nobody made.

const
  Sp1*  = 4    ## inside a control: icon to label
  Sp2*  = 8    ## between a label and its value
  Sp3*  = 12   ## between sibling controls
  Sp4*  = 16   ## inside a card
  Sp6*  = 24   ## between cards
  Sp8*  = 32   ## between sections
  Sp12* = 48   ## screen margin on a 1280-wide window

  spaceScale*: array[7, int] = [Sp1, Sp2, Sp3, Sp4, Sp6, Sp8, Sp12]

proc isOnRhythm*(px: int): bool =
  ## S1 — true when `px` is a legal gap/pad/margin.
  for s in spaceScale:
    if s == px: return true
  false

proc nearestRhythm*(px: int): int =
  result = spaceScale[0]
  for s in spaceScale:
    if abs(s - px) < abs(result - px): result = s

# ══════════════════════════════════════════════════════════════════════════════
# 3 · RADIUS — R1: three radii, chosen by role, never by taste.
# ══════════════════════════════════════════════════════════════════════════════

const
  RsSm*   = 6    ## a tag, a chip, a hairline swatch
  RsCtl*  = 10   ## a button, an input, a menu row
  RsCard* = 16   ## a card, a panel, a window

proc isOnRadius*(px: int): bool =
  px == RsSm or px == RsCtl or px == RsCard

# ══════════════════════════════════════════════════════════════════════════════
# 4 · MOTION — M1: four bands. Same curve family as Material 3 / Apple HIG.
# ══════════════════════════════════════════════════════════════════════════════
#
# The wire carries an Easing INDEX (`protocol/easing.nim` `EasingKind`), so these
# are references to real curve names, not free-form beziers. Entering uses ease-out;
# a moving thing uses ease-in-out; nothing bounces except a deliberate pop.

const
  MsPress*  = 120   ## M2 · a pressed/hover response. Above ~150 ms a press feels late.
  MsBase*   = 180   ## a colour or opacity change
  MsEnter*  = 280   ## something appearing or leaving
  MsScreen* = 360   ## a whole-screen transition; M4 · never above 400 ms

proc isOnMotionBand*(ms: int): bool =
  ms == MsPress or ms == MsBase or ms == MsEnter or ms == MsScreen

proc nearestMotionBand*(ms: int): int =
  ## The repair step for a stray duration: `nearestMotionBand(250) == MsEnter`.
  const bands = [MsPress, MsBase, MsEnter, MsScreen]
  result = bands[0]
  for b in bands:
    if abs(b - ms) < abs(result - ms): result = b

# ── the presets, pinned to the bands ─────────────────────────────────────────
# The SDK's own presets carry their own numbers (`fade` 180, `fly` 260, `pop` 240,
# `turn` 320 — `sdk/ui/motion.nim`). These wrap them onto the bands so an app that
# writes `enter = dRise()` and the app beside it that writes `enter = fly()` do not
# disagree by 80 ms.

proc dFade*(delay = 0): Motion = fade(ms = MsEnter, delay = delay, ease = easeOutCubic)
proc dRise*(y = 12.0; delay = 0): Motion = fly(y = y, ms = MsEnter, delay = delay, ease = easeOutCubic)
proc dPop*(scale = 0.92; delay = 0): Motion = pop(scale = scale, ms = MsEnter, delay = delay, ease = easeOutBack)
proc dTurn*(rotate = -90.0; delay = 0): Motion = turn(rotate = rotate, ms = MsScreen, delay = delay, ease = easeOutBack)

# ══════════════════════════════════════════════════════════════════════════════
# 5 · CONTRAST — C1..C4, computed, not eyeballed.
# ══════════════════════════════════════════════════════════════════════════════
#
# WCAG 2.2 relative luminance, the same formula the audit used. Colours here are the
# engine's 0xAARRGGBB with the alpha byte optional — alpha is ignored for contrast,
# because the pair is judged on its opaque form.

proc srgbToLinear(c: int): float =
  let s = c.float / 255.0
  if s <= 0.04045: s / 12.92 else: pow((s + 0.055) / 1.055, 2.4)

proc luminance*(rgb: int): float =
  let r = (rgb shr 16) and 0xFF
  let g = (rgb shr 8) and 0xFF
  let b = rgb and 0xFF
  0.2126 * srgbToLinear(r) + 0.7152 * srgbToLinear(g) + 0.0722 * srgbToLinear(b)

proc contrastRatio*(fg, bg: int): float =
  ## C1 — the WCAG 2.2 contrast ratio between two opaque colours, 1.0 .. 21.0.
  let a = luminance(fg)
  let b = luminance(bg)
  let hi = max(a, b)
  let lo = min(a, b)
  (hi + 0.05) / (lo + 0.05)

const
  ContrastBody*  = 4.5   ## C1 · body text against its own background
  ContrastLarge* = 3.0   ## C2 · text >= 20 px, or >= 16 px at weight >= 700
  ContrastUi*    = 3.0   ## C3 · a border or focus ring that carries meaning

proc isLargeText*(px: int; weight: int): bool =
  ## C2's definition, taken from WCAG 2.2 SC 1.4.3 rather than from habit:
  ## large is **18 pt (24 px)**, or **14 pt bold (18.66 px, so 19 px here)**.
  ## Material and the Apple HIG are looser (20 px / 16 px bold) — this module
  ## follows WCAG, because a looser threshold would let a 20 px pair pass at
  ## 3:1 that WCAG requires at 4.5:1, i.e. it would ship a real failure.
  px >= 24 or (px >= 19 and weight >= 700)

proc passes*(fg, bg: int; px = FsBody; weight = W400): bool =
  ## C1/C2 — true when this text/background pair is legal at that size and weight.
  let need = if isLargeText(px, weight): ContrastLarge else: ContrastBody
  contrastRatio(fg, bg) >= need

proc passesUi*(fg, bg: int): bool =
  ## C3 — a border or ring: 3:1, no size excuse.
  contrastRatio(fg, bg) >= ContrastUi

# ══════════════════════════════════════════════════════════════════════════════
# 6 · STATE — X1..X3: every control owes hover, active, focus, disabled.
# ══════════════════════════════════════════════════════════════════════════════

const
  FocusRingWidth* = 2      ## X2 · px, drawn outside the fill
  FocusRingOffset* = 2     ## X2 · px of air between fill and ring
  DisabledOpacity* = 0.45  ## X3 · a disabled control is dimmed, never merely flat

proc focusRing*(n: Node) =
  ## X2 — the ring. It uses the theme's own `accent` at full strength, not
  ## `accentSoft`: a ring must clear 3:1 against the fill beside it, and a low-alpha
  ## accent composited over a surface does not. `border` (`sdk/yantra.nim:303`) takes
  ## RGB only, so the alpha-carrying colour goes through `pBorderColor` directly.
  n.set(pBorderWidth, FocusRingWidth.int32)
  n.set(pBorderColor, wireI32(theme().accent))

proc disabledOn*(n: Node) =
  ## G1's workaround, in one call. `pDisabled` crosses the wire and nothing in
  ## `render/` or `host/` reads it (see reference/26-frontend-gaps.md §G1), so
  ## `disabled = true` changes neither the pixels nor the input behaviour. Until the
  ## engine reads it, a disabled control is dimmed and recoloured by the app.
  n.opacity(DisabledOpacity.float32)
  n.setFill(theme().surface2)

proc disabledOff*(n: Node; fill: int) =
  n.opacity(1.0'f32)
  n.setFill(fill)

proc focusRingOff*(n: Node) =
  ## X2 — focus left: the ring goes, the fill stays.
  n.set(pBorderColor, wireI32(theme().line))

# ── the palettes every theme owes: a fill and a hover fill for a control ──────
# These are functions of the theme, so they re-style on `setTheme` like any other
# theme-word prop (`sdk/ui/dsl.nim:97`).

proc ctlFill*(): int = theme().surface2
proc ctlFillHover*(): int = theme().surface3
proc ctlFillPressed*(): int = theme().surface3
proc ctlInk*(): int = theme().text
proc ctlLine*(): int = theme().line
proc accentSoftFill*(): int = theme().accentSoft

# ══════════════════════════════════════════════════════════════════════════════
# 7 · THE PRESETS — one `Style` per role, so an app writes a role, not six props.
# ══════════════════════════════════════════════════════════════════════════════
#
# A `Style` is the SDK's own reusable prop bundle (`sdk/ui/dsl.nim:708`, applied with
# `use = …`). Call-site props written after `use` win, so a preset is a default, not a
# cage.

proc tMicro*(): Style = style(size = FsMicro, weight = W700)
proc tSmall*(): Style = style(size = FsSmall, weight = W500)
proc tBody*(): Style = style(size = FsBody, weight = W400, lineHeight = LhBody)
proc tBodyLg*(): Style = style(size = FsBodyLg, weight = W500, lineHeight = LhBody)
proc tTitle*(): Style = style(size = FsTitle, weight = W600, lineHeight = LhTight)
proc tTitleLg*(): Style = style(size = FsTitleLg, weight = W700, lineHeight = LhTight)
proc tDisplay*(): Style = style(size = FsDisplay, weight = W800, lineHeight = LhTight)
proc tHero*(): Style = style(size = FsHero, weight = W800, lineHeight = LhTight)

proc ctl*(): Style =
  ## A control's box, radius and inner spacing — the geometry half of a button.
  style(radius = RsCtl, pad = Sp3, weight = W600, size = FsBody)

proc card*(): Style =
  ## A card's box: the card radius and the card's own interior.
  style(radius = RsCard, pad = Sp4, gap = Sp3, fill = theme().surface)

proc screen*(): Style =
  ## The window's own padding, so every screen has the same margin.
  style(pad = Sp6, gap = Sp4, fill = theme().bg)

proc sectionGap*(): Style = style(gap = Sp8)
proc cardGap*(): Style = style(gap = Sp6)
proc controlGap*(): Style = style(gap = Sp3)

# ── imperative twins, for the apps that drive Nodes directly (kart, emberdeep) ──

proc typeOn*(n: Node; px: int; weight = W400; lineHeight = 0.0) =
  ## T1 — set type from the scale. `px` is snapped to the scale, so a stray 9
  ## becomes the legal 11 rather than a silent violation.
  n.fontSize(nearestStep(px).int32)
  n.set(pFontWeight, (if isOnWeight(weight): weight else: W400).int32)
  if lineHeight > 0.0: n.set(pLineHeight, lineHeight.float32)

proc ctlOn*(n: Node; fill: int; ink: int) =
  ## R1 + C1 — a control's fill, ink and radius in one call.
  n.radius(RsCtl)
  n.setFill(fill)
  n.set(pTextColor, wireI32(ink))

proc spaceInto*(n: Node; gapPx: int) =
  ## S1 — snap a gap to the rhythm. The wire's gap prop is `pSpacing`
  ## (`sdk/core/wire.nim:76`) — the DSL's `gap = …` rewrites onto it.
  n.set(pSpacing, nearestRhythm(gapPx).float32)

# ══════════════════════════════════════════════════════════════════════════════
# 8 · THE SELF-CHECK — C1..C4 over every house theme, measured.
# ══════════════════════════════════════════════════════════════════════════════
#
# Run it: `nim c -r yantra-os/apps/_design/design_check.nim`
# Every failure prints the pair, the ratio and the floor it missed.

type
  Finding* = object
    rule*: string    ## the rule id: C1, C3, C4 …
    theme*: string
    pair*: string
    ratio*: float
    floor*: float

proc checkThemes*(): seq[Finding] =
  ## Every theme's text/background pairs against the floors. `faint` is checked
  ## against ContrastUi, not ContrastBody: C4 says `faint` is a hairline and a
  ## disabled glyph, never a label — measured, four of eight house themes put
  ## `faint` on `surface` at 2.37–2.68:1, so it fails body text by construction.
  for t in themes:
    let textOnSurface = contrastRatio(t.text, t.surface)
    if textOnSurface < ContrastBody:
      result.add Finding(rule: "C1", theme: t.name, pair: "text/surface",
                         ratio: textOnSurface, floor: ContrastBody)
    let mutedOnSurface = contrastRatio(t.muted, t.surface)
    if mutedOnSurface < ContrastBody:
      result.add Finding(rule: "C1", theme: t.name, pair: "muted/surface",
                         ratio: mutedOnSurface, floor: ContrastBody)
    let mutedOnBg = contrastRatio(t.muted, t.bg)
    if mutedOnBg < ContrastBody:
      result.add Finding(rule: "C1", theme: t.name, pair: "muted/bg",
                         ratio: mutedOnBg, floor: ContrastBody)
    let accentTextOnAccent = contrastRatio(t.accentText, t.accent)
    if accentTextOnAccent < ContrastBody:
      result.add Finding(rule: "C1", theme: t.name, pair: "accentText/accent",
                         ratio: accentTextOnAccent, floor: ContrastBody)
    let faintOnSurface = contrastRatio(t.faint, t.surface)
    if faintOnSurface < ContrastUi:
      result.add Finding(rule: "C4", theme: t.name, pair: "faint/surface",
                         ratio: faintOnSurface, floor: ContrastUi)

proc checkScale*(sizes: openArray[int]; weights: openArray[int]): seq[string] =
  ## T1/T5/T6 over a screen's actual values — the repair list an audit prints.
  for s in sizes:
    if not isOnScale(s):
      result.add "T1 size " & $s & " is off the scale; use " & $nearestStep(s)
  for w in weights:
    if not isOnWeight(w):
      result.add "T1 weight " & $w & " is off the scale"
  var used = 0
  for s in typeScale:
    for q in sizes:
      if q == s: inc used
  if used > MaxSizesPerScreen:
    result.add "T6 " & $used & " distinct sizes on one screen (max " & $MaxSizesPerScreen & ")"

when isMainModule:
  let findings = checkThemes()
  if findings.len == 0:
    echo "design: all ", themes.len, " themes pass"
  else:
    for f in findings:
      echo f.rule, " ", f.theme, " ", f.pair, " ", f.ratio.formatFloat(ffDecimal, 2),
           " < ", f.floor.formatFloat(ffDecimal, 2)
    echo findings.len, " contrast findings over ", themes.len, " themes"
