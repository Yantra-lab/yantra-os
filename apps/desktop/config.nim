## apps/desktop/config.nim
## Celestia Shell + Hyprland configuration, bilingual यंत्र / YANTRA emblem renderer,
## freestanding UTF-8 text width estimator, and hand-rolled Nim syntax highlighter.

import std/[strutils, math]
import yantra

const
  # Celestia Shell Cosmic Palette (0xAARRGGBB for Draw canvas calls)
  ColVoid*        = 0xFF07080E'u32
  ColAbyss*       = 0xFF0B0D17'u32
  ColChrome*      = 0xF20D101B'u32
  ColPanel*       = 0xFF111524'u32
  ColCard*        = 0xFF151A2C'u32
  ColCardHover*   = 0xFF1C233B'u32
  ColElevated*    = 0xFF222A46'u32
  ColBorderDim*   = 0xFF252D4A'u32
  ColBorderSub*   = 0xFF333E64'u32
  ColGold*        = 0xFFF4D078'u32
  ColAmber*       = 0xFFD99B38'u32
  ColCyan*        = 0xFF6BE6E6'u32
  ColViolet*      = 0xFFA882FF'u32
  ColRose*        = 0xFFFF75A0'u32
  ColEmerald*     = 0xFF5CE0A8'u32
  ColRed*         = 0xFFFF6B7B'u32
  ColTextHi*      = 0xFFF5F7FF'u32
  ColTextMid*     = 0xFFB4BFE2'u32
  ColTextDim*     = 0xFF7E8BB4'u32  # 4.61:1 on ColCardHover (its lightest surface), 5.13 on
                                   # ColCard, 5.71 on the code panel, 5.39 on ColPanel - it was
                                   # 0xFF6C789E, which measured 3.96-4.41 on the same three (F1 fail)

  # Layout Metrics
  TopBarH*        = 40.0'f32
  StatusBarH*     = 24.0'f32
  LeftRailW*      = 248.0'f32
  RightDockW*     = 58.0'f32
  TileHeaderH*    = 32.0'f32
  BaselineK*      = 1.0833'f32

type
  ViewMode* = enum
    vmFullPreview = 0   ## 100% live running WASM app (StackEdit Preview mode)
    vmSplit       = 1   ## 50/50 live Nim Monaco Editor + running WASM app
    vmFullCode    = 2   ## 100% full-screen Nim Monaco IDE + n8n Node Graph

  LeftTabMode* = enum
    ltSpaces   = 0      ## Workspaces, Tab Groups & Open Windows
    ltFiles    = 1      ## Integrated File Manager (`apps/*`, `sdk/*`)
    ltApps     = 2      ## Categorized 20-App Store Catalog
    ltNodes    = 3      ## n8n-style Visual Node Pipeline Inspector

  TabGroupColor* = enum
    tgcGold   = 0
    tgcCyan   = 1
    tgcViolet = 2
    tgcRose   = 3
    tgcGreen  = 4
    tgcBlue   = 5
    tgcOrange = 6
    tgcGrey   = 7

  NimTokKind* = enum
    ntkPlain
    ntkKeyword
    ntkType
    ntkString
    ntkNumber
    ntkComment
    ntkPragma
    ntkProc
    ntkOperator

  NimToken* = object
    text*: string
    kind*: NimTokKind

  DesktopConfig* = object
    gapsIn*: float32
    gapsOut*: float32
    borderSize*: float32
    cornerRadius*: float32
    masterRatio*: float32
    showLeftRail*: bool
    showRightDock*: bool
    showMinimap*: bool
    defaultViewMode*: ViewMode

proc defaultDesktopConfig*(): DesktopConfig =
  DesktopConfig(
    gapsIn: 6.0'f32,
    gapsOut: 8.0'f32,
    borderSize: 1.5'f32,
    cornerRadius: 10.0'f32,
    masterRatio: 0.54'f32,
    showLeftRail: true,
    showRightDock: true,
    showMinimap: true,
    defaultViewMode: vmFullPreview
  )

proc rnd32*(x: float32): int32 {.inline.} =
  ## Freestanding-safe float32 rounding (avoids C `round` import in WASM).
  int32(if x < 0.0'f32: x - 0.5'f32 else: x + 0.5'f32)

proc clampf*(v, lo, hi: float32): float32 {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

proc utf8CodePoints*(s: string): int =
  ## Counts visible UTF-8 code points so Devanagari (`यंत्र`) and box glyphs measure accurately.
  var i = 0
  while i < s.len:
    let b = uint8(s[i])
    if (b and 0x80'u8) == 0'u8: inc i
    elif (b and 0xE0'u8) == 0xC0'u8: i += 2
    elif (b and 0xF0'u8) == 0xE0'u8: i += 3
    else: i += 4
    inc result

proc mTextW*(s: string; size: float32; mono = false): float32 {.inline.} =
  ## Freestanding-safe text width estimator (requires zero host imports).
  float32(utf8CodePoints(s)) * size * (if mono: 0.58'f32 else: 0.51'f32)

proc drawTextVCenter*(d: var Draw; x, boxY, boxH: float32; text: string;
                      size: float32; color: uint32; bold = false) {.inline.} =
  ## Centers single-line text vertically inside `[boxY, boxY + boxH]` accounting for SkParagraph top-box offset.
  let ty = boxY + (boxH - size * 1.18'f32) * 0.5'f32
  d = d.text(x, ty, size, color, text, if bold: 700 else: 400)

proc drawTextHCenter*(d: var Draw; cx, boxY, boxH: float32; text: string;
                      size: float32; color: uint32; bold = false; mono = false) {.inline.} =
  let tw = mTextW(text, size, mono)
  let ty = boxY + (boxH - size * 1.18'f32) * 0.5'f32
  d = d.text(cx - tw * 0.5'f32, ty, size, color, text, if bold: 700 else: 400)

proc groupColorArgb*(c: TabGroupColor): uint32 =
  case c
  of tgcGold:   ColGold
  of tgcCyan:   ColCyan
  of tgcViolet: ColViolet
  of tgcRose:   ColRose
  of tgcGreen:  ColEmerald
  of tgcBlue:   0xFF5CA8FF'u32
  of tgcOrange: ColAmber
  of tgcGrey:   ColTextDim

proc drawFourPointStar*(d: var Draw; cx, cy, r: float32; color: uint32) =
  ## Draws a crisp 4-point celestial star matching the Yantra logo sparkles.
  d = d.line(cx - r, cy, cx + r, cy, color, 1.6'f32)
  d = d.line(cx, cy - r, cx, cy + r, color, 1.6'f32)
  let d45 = r * 0.42'f32
  d = d.line(cx - d45, cy - d45, cx + d45, cy + d45, color, 1.1'f32)
  d = d.line(cx - d45, cy + d45, cx + d45, cy - d45, color, 1.1'f32)
  d = d.circle(cx, cy, r * 0.22'f32, 0xFFFFFFFF'u32)

proc drawYantraEmblem*(d: var Draw; cx, cy, radius: float32; compact = false) =
  ## Renders the bilingual `यंत्र / YANTRA` cosmic orbital emblem inspired by `image_e35c4b.jpg`.
  d = d.circle(cx, cy, radius * 1.12'f32, 0x14A882FF'u32)
  d = d.circle(cx, cy, radius * 1.02'f32, 0x1E6BE6E6'u32)
  d = d.circle(cx, cy, radius * 0.94'f32, 0xFF090B14'u32)

  let segs = if compact: 24 else: 48
  for ring in 0 .. 2:
    let r = radius * (0.94'f32 - float32(ring) * 0.055'f32)
    let tiltY = if ring == 0: 0.92'f32 elif ring == 1: 0.78'f32 else: 0.86'f32
    let phase = float32(ring) * 0.85'f32
    for i in 0 ..< segs:
      let a0 = (float32(i) / float32(segs)) * 6.2831853'f32 + phase
      let a1 = (float32(i + 1) / float32(segs)) * 6.2831853'f32 + phase
      let x0 = cx + cos(a0) * r
      let y0 = cy + sin(a0) * r * tiltY
      let x1 = cx + cos(a1) * r
      let y1 = cy + sin(a1) * r * tiltY
      let col =
        if (i + ring * 5) mod 3 == 0: ColGold
        elif (i + ring * 5) mod 3 == 1: ColCyan
        else: ColViolet
      let thick = if i mod 4 == 0: 2.2'f32 else: 1.2'f32
      d = d.line(x0, y0, x1, y1, col, thick)

  if compact:
    let fs = radius * 0.88'f32
    drawTextHCenter(d, cx, cy - radius * 0.55'f32, radius * 1.1'f32, "यंत्र", fs, ColGold, true)
    drawFourPointStar(d, cx + radius * 0.25'f32, cy - radius * 0.48'f32, 3.2'f32, ColGold)
  else:
    let hindiSize = radius * 0.56'f32
    let engSize   = radius * 0.145'f32
    drawTextHCenter(d, cx + 1.5'f32, cy - radius * 0.46'f32 + 1.5'f32, hindiSize * 1.2'f32,
                    "यंत्र", hindiSize, 0x885A3808'u32, true)
    drawTextHCenter(d, cx, cy - radius * 0.46'f32, hindiSize * 1.2'f32,
                    "यंत्र", hindiSize, ColGold, true)

    drawFourPointStar(d, cx - radius * 0.04'f32, cy - radius * 0.48'f32, radius * 0.09'f32, ColGold)
    drawFourPointStar(d, cx + radius * 0.14'f32, cy - radius * 0.56'f32, radius * 0.06'f32, ColCyan)

    let ruleY = cy + radius * 0.16'f32
    let ruleW = radius * 0.58'f32
    d = d.line(cx - ruleW, ruleY, cx - 6.0'f32, ruleY, ColAmber, 1.2'f32)
    d = d.line(cx + 6.0'f32, ruleY, cx + ruleW, ruleY, ColAmber, 1.2'f32)
    d = d.circle(cx, ruleY, 3.0'f32, ColGold)

    drawTextHCenter(d, cx, cy + radius * 0.24'f32, engSize * 1.5'f32,
                    "Y A N T R A", engSize, ColGold, true)

proc bakeCelestiaWallpaper*(w, h: int): Layer =
  ## Pre-renders the Celestia cosmic starfield + subtle watermark `यंत्र / YANTRA` emblem into a Layer once.
  result = newLayer(w, h)
  let fw = float32(w)
  let fh = float32(h)
  var d = Draw()
  d = d.rect(0, 0, fw, fh, ColVoid)

  let cx = fw * 0.54'f32
  let cy = fh * 0.48'f32
  d = d.circle(cx, cy, min(fw, fh) * 0.52'f32, 0x0A6BE6E6'u32)
  d = d.circle(cx, cy, min(fw, fh) * 0.38'f32, 0x0CA882FF'u32)
  d = d.circle(cx, cy, min(fw, fh) * 0.24'f32, 0x10F4D078'u32)

  var seed = 0x59414E54'u32
  for i in 0 ..< 110:
    seed = seed * 1664525'u32 + 1013904223'u32
    let sx = float32(seed mod uint32(max(1, w)))
    seed = seed * 1664525'u32 + 1013904223'u32
    let sy = float32(seed mod uint32(max(1, h)))
    let r = if i mod 11 == 0: 1.8'f32 elif i mod 3 == 0: 1.2'f32 else: 0.8'f32
    let col =
      if i mod 7 == 0: 0x88F4D078'u32
      elif i mod 5 == 0: 0x886BE6E6'u32
      elif i mod 9 == 0: 0x88A882FF'u32
      else: 0x55E2E8F0'u32
    d = d.circle(sx, sy, r, col)
    if i mod 19 == 0:
      drawFourPointStar(d, sx, sy, 4.5'f32, 0x66F4D078'u32)

  drawYantraEmblem(d, cx, cy, min(fw, fh) * 0.17'f32, compact = false)
  result.draw(d)

# ---------------------------------------------------------------------------
# Hand-Rolled Freestanding Nim Syntax Lexer (Zero Regex / Zero Host Imports)
# ---------------------------------------------------------------------------

const
  NimKeywords = [
    "proc", "func", "method", "iterator", "macro", "template", "converter",
    "type", "object", "ref", "ptr", "var", "let", "const", "enum", "tuple",
    "distinct", "if", "elif", "else", "case", "of", "when", "while", "for",
    "in", "notin", "break", "continue", "return", "yield", "try", "except",
    "finally", "raise", "defer", "block", "do", "import", "export", "from",
    "include", "mixin", "bind", "using", "and", "or", "not", "xor", "shl",
    "shr", "div", "mod", "is", "isnot", "as", "addr", "cast", "static",
    "nil", "true", "false", "discard"
  ]

  NimTypes = [
    "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
    "uint32", "uint64", "float", "float32", "float64", "bool", "char",
    "string", "cstring", "pointer", "seq", "array", "openArray", "set",
    "Node", "Draw", "Layer", "AppConfig", "InputState", "Event", "Key"
  ]

proc isIdentStart(c: char): bool {.inline.} =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

proc isIdentChar(c: char): bool {.inline.} =
  isIdentStart(c) or (c >= '0' and c <= '9')

proc inWordList(w: string; list: openArray[string]): bool {.inline.} =
  for item in list:
    if w == item: return true
  false

proc tokenizeNimLine*(line: string): seq[NimToken] =
  var i = 0
  let n = line.len
  var prevWasProc = false

  while i < n:
    let c = line[i]
    if c == ' ' or c == '\t':
      let start = i
      while i < n and (line[i] == ' ' or line[i] == '\t'): inc i
      result.add(NimToken(text: line[start ..< i], kind: ntkPlain))
      continue

    if c == '#':
      result.add(NimToken(text: line[i ..< n], kind: ntkComment))
      break

    if c == '{' and i + 1 < n and line[i + 1] == '.':
      let start = i
      i += 2
      while i < n and not (line[i] == '.' and i + 1 < n and line[i + 1] == '}'):
        inc i
      if i + 1 < n: i += 2 else: i = n
      result.add(NimToken(text: line[start ..< i], kind: ntkPragma))
      continue

    if c == '"':
      let start = i
      inc i
      while i < n:
        if line[i] == '\\' and i + 1 < n:
          i += 2
        elif line[i] == '"':
          inc i
          break
        else:
          inc i
      result.add(NimToken(text: line[start ..< i], kind: ntkString))
      continue

    if (c >= '0' and c <= '9'):
      let start = i
      while i < n and ((line[i] >= '0' and line[i] <= '9') or
                       (line[i] >= 'a' and line[i] <= 'f') or
                       (line[i] >= 'A' and line[i] <= 'F') or
                       line[i] == 'x' or line[i] == '_' or line[i] == '.' or
                       line[i] == '\'' or line[i] == 'u' or line[i] == 'i' or line[i] == 'f'):
        inc i
      result.add(NimToken(text: line[start ..< i], kind: ntkNumber))
      continue

    if isIdentStart(c):
      let start = i
      while i < n and isIdentChar(line[i]): inc i
      let word = line[start ..< i]
      let kind =
        if prevWasProc:
          prevWasProc = false
          ntkProc
        elif inWordList(word, NimKeywords):
          if word in ["proc", "func", "template", "macro", "iterator"]:
            prevWasProc = true
          ntkKeyword
        elif inWordList(word, NimTypes) or (word.len > 0 and word[0] >= 'A' and word[0] <= 'Z'):
          ntkType
        else:
          ntkPlain
      result.add(NimToken(text: word, kind: kind))
      continue

    let start = i
    inc i
    result.add(NimToken(text: line[start ..< i], kind: ntkOperator))

proc tokenColor*(k: NimTokKind): uint32 {.inline.} =
  case k
  of ntkKeyword:  ColViolet
  of ntkType:     ColCyan
  of ntkString:   ColEmerald
  of ntkNumber:   ColGold
  of ntkComment:  ColTextDim
  of ntkPragma:   ColRose
  of ntkProc:     ColGold
  of ntkOperator: ColTextMid
  of ntkPlain:    ColTextHi

# ---------------------------------------------------------------------------
# Opus Caelestia DESK compat: tokens, metrics, and helpers state.nim needs.
# Values follow the Caelestia dark look (deep indigo, lavender accents).
# ---------------------------------------------------------------------------

const
  m3surface*         = 0x131317
  container*         = 0x1E1E27
  containerLow*      = 0x17171F
  containerLowest*   = 0x0E0E12
  containerHigh*     = 0x262633
  containerHighest*  = 0x2F2F3D
  primary*           = 0xC2C1FF
  primaryContainer*  = 0x3F3F76
  onPrimary*         = 0x2A2A60
  onPrimaryContainer* = 0xE2DFFF
  secondaryContainer* = 0x45455C
  onSecondaryContainer* = 0xE3E0FA
  tertiary*          = 0xF5B2E0
  onSurface*         = 0xE8E8F0
  onSurfaceVariant*  = 0x9A9AA5
  outline*           = 0x3A3A46
  outlineVariant*    = 0x47464F
  errorContainer*    = 0x93000A
  errorRole*         = 0xFFB4AB
  clear*             = 0x00000000
  stateHover*        = 0x14E5E1E7
  glassAlpha*        = 0.85
  cardRadius*        = 16
  windowRadius*      = 15
  effectMs*          = 200
  moveMs*            = 350
  uiFont*            = "Segoe UI Variable Text"
  displayFont*       = "Segoe UI Variable Display"
  monoFont*          = "Cascadia Mono"

  frameWidth*        = 10
  screenRadius*      = 25
  barWidth*          = 56
  sidebarWidth*      = 272
  settingsWidth*     = 400
  titleHeight*       = 36
  gapsOut*           = 10.0'f32
  gapsIn*            = 8.0'f32
  workspaceCount*    = 9
  recentCount*       = 5

  registryHost*      = ""
  registryUrl*       = ""

  modMask*           = 0x0FC3

proc fuzzyScore*(q, name: string): int =
  ## Ordered-subsequence match, best first: prefix > word-start > anywhere.
  if q.len == 0: return 0
  let qq = q.toLowerAscii()
  let nn = name.toLowerAscii()
  if nn.startsWith(qq): return 1000 - qq.len
  for i in 1 ..< nn.len:
    if nn[i - 1] in {' ', '-', '_', '/', '.'} and nn[i .. ^1].startsWith(qq):
      return 500 - qq.len - i
  var qi = 0
  for i in 0 ..< nn.len:
    if nn[i] == qq[qi]:
      inc qi
      if qi == qq.len: return 100 - i
  -1
