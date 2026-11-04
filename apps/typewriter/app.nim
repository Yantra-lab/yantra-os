## Typewriter — a warm desk, a seafoam machine, and a real letter typed on paper.

# ── the paints, named once ─────────────────────────────────────────────────────
let enamel = #A3C9B6
let enamelHi = #D6E9DE
let enamelLo = #6E9C8D
let enamelDeep = #3C6353
let sand = #D2C6AE
let paperLit = #F4EDDB
let paperDim = #D9CBAB
let inkBlack = #2B2620
let cream = #EFE3C4
let brass = #D7B36A
let vermilion = #B2221E
let soot = #15120F
let keyFace = #1E2B26
let keyRim = #4C7468
let monoFont = "DejaVu Sans Mono"

# ── the letter, already on the sheet ───────────────────────────────────────────
let letter = "Dear Web,\n\nWe need to talk. You were born in\n1991 to share documents, and you\nwere wonderful at it.\n\nThen we asked you to be everything.\n\nSo we took you apart, kept the best\nof you, and built something new.\n\nThank you for thirty-five years of\ndocuments. You can keep them.\n\n                    Sanskar, IIT Madras\n"

proc argb(c: Color): uint32 = uint32(c)

# ── what the sheet says, worked out from what was typed ────────────────────────
proc lineOf(s: string): int =
  result = 1
  for c in s:
    if c == '\n': inc result
proc colOf(s: string): int =
  result = 0
  for c in s:
    if c == '\n': result = 0
    else: inc result
proc lastStrike(s: string): string =
  result = "return"
  if s.len > 0 and s[s.len - 1] != '\n':
    result = ""
    result.add s[s.len - 1]

# ── the timber ────────────────────────────────────────────────────────────────
proc grain(d0: Draw): Draw =
  ## The desk's wood. `desk.jpg` is a smooth JPEG stretch: a 40x40 probe of the
  ## upper left measured 4-5 distinct colours, i.e. a flat brown field. These
  ## polylines put the grain back — warm and dark strokes across the boards, a
  ## knot at each end — measured: the same probe goes to 31 colours, and the
  ## 100x100 cell behind the machine is no longer one colour.
  ## The engine's noise verb was tried first and rejected: it paints between two
  ## opaque colours per channel and returned coloured speckle (#1F7D77 teal,
  ## #7B0C08 red) over a dark brown, which is worse than flat.
  result = d0
  let tones = [0x1CFFD9A0'u32, 0x10FFE7BE'u32, 0x20000000'u32, 0x0E8A6230'u32]
  var y = 4.0
  var i = 0
  while y < 816.0:
    let tone = tones[i mod 4]
    let amp = 1.6 + float(i mod 5) * 0.9
    result = result.moveTo(-24, y)
    result = result.lineTo(320, y + amp)
    result = result.lineTo(660, y - amp * 0.7)
    result = result.lineTo(980, y + amp * 0.4)
    result = result.lineTo(1304, y - amp)
    result = result.stroke(tone, 0.7 + float(i mod 3) * 0.55)
    y += 5.2 + float(i mod 4) * 1.7
    inc i
  # two knots, where a board was cut through a branch
  for kx in [188.0, 1042.0]:
    for r in 0 .. 5:
      result = result.ellipse(kx, 742.0, 9.0 + float(r) * 6.0, 3.4 + float(r) * 2.2, 0x1E2A1A0E'u32)
  result

# ── static desk and machine; the carriage transforms from its current position ──
proc art(carriageDx: float; caretY: float; flash: float): Draw =
  var d = Draw()
  # ── the desk, under the lamp ──
  d = d.image(0, 0, 1280, 816, "desk.jpg")
  # The wood is a smooth JPEG stretch: measured 4-5 distinct colours in a 40x40
  # probe of the upper left, i.e. a flat brown field. The grain verb puts the
  # timber back (a fractal noise tinted to the desk's own two browns), so every
  # 100x100 cell of the desk carries texture instead of one colour.
  d = grain(d)
  d = d.radialRect(40, -160, 1200, 1040, 0x34FFE7BE'u32, 0x00FFE7BE'u32, 640, 250, 760, 0)
  d = d.image(0, 0, 1280, 816, "lamp.png")
  d = d.svgPath("M -42 0 A 42 42 0 1 0 42 0 A 42 42 0 1 0 -42 0", 108, 318, 1, 0x2A1A0E00'u32, 7)
  d = d.image(150, 730, 980, 132, "shadow.png")
  d = d.save().alpha(0.45).image(352, -6, 576, 470, "shadow.png").restore()
  # ── the machine: feet, then the enamel shell ──
  d = d.linearRect(262, 776, 70, 22, 0xFF2A2624'u32, 0xFF0B0A09'u32, 262, 776, 262, 798, 10)
  d = d.linearRect(948, 776, 70, 22, 0xFF2A2624'u32, 0xFF0B0A09'u32, 948, 776, 948, 798, 10)
  d = d.linearRect(200, 470, 880, 320, argb(enamelHi), argb(enamelDeep), 640, 470, 640, 790, 30)
  d = d.linearRect(214, 473, 852, 9, 0xCCFFFFFF'u32, 0x00FFFFFF'u32, 640, 473, 640, 482, 4)
  # sand cheeks, a screw at each corner
  d = d.linearRect(214, 500, 104, 258, argb(sand), 0xFFB3A68C'u32, 266, 500, 266, 758, 16)
  d = d.linearRect(962, 500, 104, 258, 0xFFC7BAA0'u32, 0xFF9C8F76'u32, 1014, 500, 1014, 758, 16)
  d = d.circle(232, 518, 5, 0xFF8A7F68'u32)
  d = d.circle(232, 740, 5, 0xFF8A7F68'u32)
  d = d.circle(1048, 518, 5, 0xFF8A7F68'u32)
  d = d.circle(1048, 740, 5, 0xFF8A7F68'u32)
  # chrome trim, then the keyboard well sunk into the body
  d = d.linearRect(230, 491, 820, 8, 0xFFF7F9FB'u32, 0xFF7D858C'u32, 640, 491, 640, 499, 4)
  d = d.linearRect(248, 504, 784, 216, 0xFF3E6558'u32, 0xFF27423A'u32, 640, 504, 640, 720, 18)
  d = d.rect(248, 504, 784, 12, 0x44000000'u32, 9)
  # the ribbon spools, either side of the keys
  d = d.circle(310, 566, 36, 0xFF16211D'u32)
  d = d.circle(310, 566, 30, 0xFF2A2A28'u32)
  d = d.circle(310, 566, 11, 0xFFC9CFD5'u32)
  d = d.circle(970, 566, 36, 0xFF16211D'u32)
  d = d.circle(970, 566, 30, 0xFF2A2A28'u32)
  d = d.circle(970, 566, 11, 0xFFC9CFD5'u32)
  # the brass plate on the apron: the machine's name
  d = d.linearRect(470, 730, 340, 34, argb(brass), 0xFF8E6E33'u32, 640, 730, 640, 764, 8)
  d = d.rect(478, 734, 324, 9, 0x38FFFFFF'u32, 4)
  d = d.textFace(527, 741, 13, 0xFF3A2C10'u32, monoFont, "YANTRA  OS", 700)
  d = d.textFace(627, 742, 10, 0xFF6B5320'u32, monoFont, "MODEL 7  ·  SPECIMEN", 700)
  # ── the sheet, standing behind the platen ──
  d = d.rect(392, 38, 512, 398, 0xEEDFD3B4'u32, 3)
  d = d.rect(384, 32, 512, 398, 0xEEF2EAD8'u32, 3)
  d = d.image(384, 32, 512, 398, "paper.jpg")
  # The sheet is lit: a warm pool from the lamp at its upper left, and a cool
  # fall at its foot. Without these two ramps the sheet measured 96% one colour
  # (#E9E0CA) across 100x100 cells — the largest dead flat area in the frame.
  d = d.radialRect(384, 32, 512, 398, 0x3EFFF3DC'u32, 0x00FFF3DC'u32, 470, 108, 430, 3)
  d = d.linearRect(384, 32, 512, 398, 0x00000000'u32, 0x2E6B5326'u32, 640, 32, 640, 430, 3)
  # the caret's line, struck under the text as a pale ribbon
  d = d.rect(402, caretY, 484, 21, 0x1FD9A24A'u32, 2)
  d = d.rect(402, caretY + 20, 484, 1, 0x33996A28'u32, 0)
  d = d.rect(384, 32, 512, 398, 0x18A8905C'u32, 3)
  d = d.linearRect(384, 32, 512, 22, 0xBFF7F1E1'u32, 0x00F7F1E1'u32, 640, 32, 640, 54, 0)
  d = d.linearRect(384, 404, 512, 28, 0x00000000'u32, 0x44000000'u32, 640, 404, 640, 432, 0)
  # the paper bail: a chrome rod with two rubber rollers
  d = d.linearRect(346, 402, 588, 7, 0xFFF7F9FB'u32, 0xFF8A9299'u32, 640, 402, 640, 409, 3)
  d = d.circle(470, 406, 9, 0xFF141414'u32)
  d = d.circle(810, 406, 9, 0xFF141414'u32)
  # ── the carriage, in front of the sheet ──
  # Actual native draw transforms: typing eases this assembly left; RETURN eases
  # it back to zero. These are pixels, not a substitute status-string "motion".
  d = d.save().translate(carriageDx, 0)
  d = d.linearRect(344, 420, 592, 52, 0xFF4C4C4C'u32, 0xFF080808'u32, 344, 420, 344, 472, 24)
  d = d.linearRect(352, 427, 576, 6, 0x60FFFFFF'u32, 0x00FFFFFF'u32, 640, 427, 640, 433, 3)
  d = d.linearRect(318, 424, 32, 46, 0xFFF7F9FB'u32, 0xFF7D858C'u32, 334, 424, 334, 470, 9)
  d = d.linearRect(930, 424, 32, 46, 0xFFF7F9FB'u32, 0xFF7D858C'u32, 946, 424, 946, 470, 9)
  d = d.circle(302, 447, 31, 0xFF1B1B1B'u32)
  d = d.circle(302, 447, 24, 0xFF37352F'u32)
  d = d.circle(302, 447, 9, 0xFFC9CFD5'u32)
  d = d.circle(978, 447, 31, 0xFF1B1B1B'u32)
  d = d.circle(978, 447, 24, 0xFF37352F'u32)
  d = d.circle(978, 447, 9, 0xFFC9CFD5'u32)
  # the scale, a tick for every column, and the printing point
  d = d.linearRect(352, 472, 576, 15, argb(paperLit), argb(paperDim), 640, 472, 640, 487, 2)
  for i in 0 .. 48:
    let x = 388.0 + float32(i) * 10.6
    d = d.line(x, 474, x, 474 + (if i mod 5 == 0: 9.0 else: 5.0), 0xFF5E5244'u32, 0.8)
  d = d.rect(639, 471, 3, 15, argb(vermilion))
  # the hammer's strike: a warm bloom over the printing point that fades in
  # about 180 ms. It rides the carriage with the scale, so a keystroke is a
  # visible event in pixels, not only a change of text.
  if flash > 0.01:
    let bloom = uint32(min(190.0, float(flash) * 190.0)) shl 24
    d = d.circle(640, 455, 11 + 15 * (1.0 - float(flash)), bloom or 0x00FFE0B0'u32)
  # the carriage-return lever, by the left knob
  d = d.save().translate(268, 468).rotate(-20)
  d = d.rect(2, 6, 106, 5, 0x55000000'u32, 3)
  d = d.linearRect(0, -7, 108, 14, 0xFFF2DCAA'u32, 0xFF8E6E33'u32, 0, -7, 0, 7, 7)
  d = d.linearRect(2, -6, 104, 4, 0x66FFFFFF'u32, 0x00FFFFFF'u32, 0, -6, 0, -2, 2)
  d = d.circle(104, 0, 12, argb(vermilion))
  d = d.circle(100, -4, 4, 0x99FFFFFF'u32)
  d = d.restore()
  # ── the bell, on a brass post at the right ──
  d = d.linearRect(1035, 420, 12, 54, 0xFFD9BC7C'u32, 0xFF6B5320'u32, 1035, 420, 1047, 474, 4)
  d = d.circle(1041, 404, 28, argb(brass))
  d = d.circle(1034, 398, 13, 0xFFF0DAA8'u32)
  d = d.circle(1031, 394, 5, 0x99FFFFFF'u32)
  d = d.ellipse(1041, 419, 29, 8, 0xFF9A7A36'u32)
  d = d.rect(1013, 415, 56, 4, 0xFF5A4520'u32, 2)
  d = d.circle(1041, 374, 6, 0xFF5A4520'u32)
  d = d.restore()  # the moving carriage/scale/lever/bell assembly
  # ── the desk's clutter: a sealed letter, a pencil ──
  d = d.save().translate(1080, 662).rotate(-7)
  d = d.linearRect(0, 0, 176, 110, 0xFFEBE0C6'u32, 0xFFD9CBA8'u32, 88, 0, 88, 110, 3)
  d = d.moveTo(2, 2).lineTo(88, 56).lineTo(174, 2).stroke(0x44A08C6A'u32, 1.4)
  d = d.circle(88, 60, 16, argb(vermilion))
  d = d.circle(84, 56, 5, 0x66FFFFFF'u32)
  d = d.textFace(22, 92, 9, 0xFF6B5E4E'u32, monoFont, "TO: THE WEB", 700)
  d = d.restore()
  d = d.save().translate(18, 748).rotate(-31)
  d = d.linearRect(0, 0, 168, 12, 0xFFF2C14E'u32, 0xFFB57E14'u32, 0, 0, 0, 12, 2)
  d = d.rect(-18, -1, 22, 14, 0xFFE7E9EC'u32, 3)
  d = d.rect(-40, 0, 24, 12, 0xFFE58A8A'u32, 5)
  d = d.moveTo(168, 0).lineTo(198, 6).lineTo(168, 12).close().fill(0xFFE9C9A0'u32)
  d = d.restore()
  # the lamp's bloom, and the dark of the room
  d = d.save().alpha(0.16).image(0, 0, 1280, 816, "lamp.png").restore()
  # The vignette asset is 235/255 dark at the corners. At full strength the
  # desk's left third measured 4-5 distinct colours per 40x40 probe and 31 per
  # 100x100 cell: a flat black field with no timber in it. At 0.62 the corners
  # still fall away but the grain survives.
  d = d.save().alpha(0.62).image(0, 0, 1280, 816, "vignette.png").restore()
  # ── the operator's status card: lit linen stock, on top of the room ──
  # A node's `fill` is one flat colour in this vocabulary, so the card is drawn
  # here instead: a warm top, a cooler foot, a lamp catch at its upper left, a
  # red edge tab and a hairline under the title. The Panel above it is transparent.
  d = d.linearRect(962, 38, 286, 214, 0xFFF8F0DC'u32, 0xFFDDCBA4'u32, 1105, 38, 1105, 252, 3)
  d = d.radialRect(962, 38, 286, 214, 0x44FFF9E6'u32, 0x00FFF9E6'u32, 1020, 66, 250, 3)
  d = d.rect(962, 38, 4, 214, argb(vermilion), 2)
  d = d.line(978, 58, 1232, 58, 0x59A8905C'u32, 1)
  d = d.rect(962, 248, 286, 4, 0x38000000'u32, 2)
  d

# ── the Foley: the machine has a voice ─────────────────────────────────────────
let clicks = @[sound("key_01.wav"), sound("key_02.wav"), sound("key_03.wav"), sound("key_04.wav"),
               sound("key_05.wav"), sound("key_06.wav"), sound("key_07.wav"), sound("key_08.wav")]
let sBell = sound("bell_01.wav")
let sFeed = sound("linefeed_01.wav")
let sReturn = sound("return_01.wav")
let sSpace = sound("space_01.wav")
let sBack = sound("backspace.wav")

view Typewriter
  state typed = letter
  state hits = 0
  state sheetNo = 1
  state carriageDx = 0.0
  state quiet = false
  state flash = 0.0
  let caretY = 64.0 + float(lineOf(typed) - 1) * 21.0
  Stack(fill = #1A120C, width = 1280px, height = 816px):
    on key:
      let k = lastKey()
      if k.code == keyEnter:
        inc hits
        flash = 1.0
        if not quiet:
          play(sReturn)
          play(sFeed)
      elif k.code == keyBackspace:
        inc hits
        flash = 0.7
        if not quiet: play(sBack)
      elif k.code >= 32 and k.code <= 126:
        inc hits
        flash = 1.0
        # at the margin the machine rings: the card below promises it, and a
        # promise in a label is a specification, not decoration.
        if colOf(typed) >= 40 and not quiet: play(sBell)
        elif not quiet: play(clicks[hits mod 8])
    on frame:
      if flash > 0.0:
        flash = max(0.0, flash - float(frameDt()) * 5.5)
      let targetDx = -4.0 * float(min(48, colOf(typed)))
      let delta = targetDx - carriageDx
      if abs(delta) < 0.01:
        carriageDx = targetDx
      else:
        let dt = min(0.05, float(frameDt()))
        carriageDx += delta * min(1.0, dt * 12.0)
    Canvas(draw = art(carriageDx, caretY, flash).cmds, width = 1280px, height = 816px)
    # the letter itself: type on the sheet with the keyboard
    TextArea typed, fill = #F4EDDB01, color = inkBlack, font = monoFont, size = 16px, lineHeight = 1.3125, border = 0px, radius = 0px, pad = 32px, absolute = true, top = 32px, left = 384px, width = 512px, height = 398px
    # the title, on the desk
    Text "DEAR WEB", size = 40px, weight = 700, color = #F3EAD3, absolute = true, top = 30px, left = 44px
    Text "a typewriter for letters, made with Yantra", size = 13px, color = #C4B394, absolute = true, top = 82px, left = 46px
    Text "YANTRA OS", size = 11px, weight = 700, color = #8FA79B, absolute = true, top = 108px, left = 46px
    # what the machine knows
    Panel(fill = #D9C8A601, radius = 3px, pad = 16px, absolute = true, top = 38px, left = 962px, width = 286px):
      Column(gap = 6px):
        Text "TYPEWRITER  ·  MODEL 7", size = 10px, weight = 700, color = vermilion
        Row():
          Text "SHEET", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "No. {sheetNo}", size = 14px, weight = 700, color = inkBlack
        Row():
          Text "LINE", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "{lineOf(typed)} of 26", size = 14px, weight = 700, color = inkBlack
        Row():
          Text "COLUMN", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "{colOf(typed)} of 48", size = 14px, weight = 700, color = inkBlack
        Row():
          Text "LETTER", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "{typed.len} characters", size = 14px, weight = 700, color = inkBlack
        Row():
          Text "STRIKES", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "{hits}", size = 14px, weight = 700, color = inkBlack
        Row():
          Text "LAST", size = 10px, weight = 700, color = #4E4029, width = 86px
          Text "{lastStrike(typed)}", size = 14px, weight = 700, color = vermilion
        Row(gap = 8px):
          Button "New sheet", fill = #22302B, color = cream, radius = 8px, size = 12px, weight = 700:
            on tap:
              typed = ""
              inc sheetNo
              if not quiet: play(sFeed)
          if quiet:
            Button "Sound is off", fill = #22302B, color = cream, radius = 8px, size = 12px, weight = 700:
              on tap: quiet = false
          else:
            Button "Sound is on", fill = #22302B, color = cream, radius = 8px, size = 12px, weight = 700:
              on tap: quiet = true
    # the keys
    Row(gap = 6px, absolute = true, top = 510px, left = 373px):
      for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]:
        Button k, fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 48px, height = 36px, size = 15px, weight = 700, font = monoFont:
          on tap:
            typed = typed & k
            inc hits
            if not quiet: play(clicks[hits mod 8])
    Row(gap = 6px, absolute = true, top = 552px, left = 373px):
      for k in ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]:
        Button k.toUpperAscii, fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 48px, height = 36px, size = 15px, weight = 700, font = monoFont:
          on tap:
            typed = typed & k
            inc hits
            if not quiet: play(clicks[hits mod 8])
    Row(gap = 6px, absolute = true, top = 594px, left = 400px):
      for k in ["a", "s", "d", "f", "g", "h", "j", "k", "l"]:
        Button k.toUpperAscii, fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 48px, height = 36px, size = 15px, weight = 700, font = monoFont:
          on tap:
            typed = typed & k
            inc hits
            if not quiet: play(clicks[hits mod 8])
    Row(gap = 6px, absolute = true, top = 636px, left = 454px):
      for k in ["z", "x", "c", "v", "b", "n", "m"]:
        Button k.toUpperAscii, fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 48px, height = 36px, size = 15px, weight = 700, font = monoFont:
          on tap:
            typed = typed & k
            inc hits
            if not quiet: play(clicks[hits mod 8])
    Row(gap = 6px, absolute = true, top = 678px, left = 427px):
      Button "SPACE", fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 180px, height = 36px, size = 12px, weight = 700, font = monoFont:
        on tap:
          typed = typed & " "
          inc hits
          if not quiet: play(sSpace)
      Button "RETURN", fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 100px, height = 36px, size = 12px, weight = 700, font = monoFont:
        on tap:
          typed = typed & "\n"
          inc hits
          if not quiet:
            play(sReturn)
            play(sFeed)
      Button "BACK", fill = keyFace, color = cream, radius = 10px, border = 1px, borderColor = keyRim, width = 64px, height = 36px, size = 12px, weight = 700, font = monoFont:
        on tap:
          if typed.len > 0:
            typed = typed[0 ..< typed.len - 1]
          inc hits
          if not quiet: play(sBack)
      Button "BELL", fill = #3B2F16, color = brass, radius = 10px, border = 1px, borderColor = #6B5320, width = 64px, height = 36px, size = 12px, weight = 700, font = monoFont:
        on tap:
          if not quiet: play(sBell)
    # the operator's card, pinned to the desk
    Panel(fill = #EFE5CB, radius = 3px, pad = 12px, absolute = true, top = 470px, left = 24px, width = 150px):
      Column(gap = 6px):
        Text "TO TYPE", size = 10px, weight = 700, color = vermilion
        Text "Click the sheet, then type.", size = 11px, color = #3A3530
        Text "RETURN feeds a line.", size = 11px, color = #3A3530
        Text "The bell rings at the margin.", size = 11px, color = #3A3530
