## EMBERDEEP — a native falling-sand expedition.
##
## The game and its exact, deterministic rules live in emberdeep.nim. This is only
## the imperative native shell: SDK nodes and handlers, one crisp RGBA upload per
## simulation frame, authored Draw UI, and five real synth voices. There is no DOM,
## browser scene, screenshot backdrop, scripted attract mode, or alternate game.

import std/[math, strutils]
import emberdeep
import "../_design/design"

const
  WinW = 1280
  WinH = 816
  WorldX = 24.0'f32
  WorldY = 104.0'f32
  WorldW = 896.0'f32
  WorldH = 504.0'f32
  Sans = "DejaVu Sans"
  Mono = "DejaVu Sans Mono"

  Night = 0xFF080A10'u32
  Panel = 0xF2141720'u32
  PanelHi = 0xFA1B1C25'u32
  Edge = 0xFF3A3435'u32
  EdgeSoft = 0xFF282831'u32
  Ink = 0xFFF0E5D2'u32
  Muted = 0xFF9C9AA3'u32
  Faint = 0xFF656674'u32
  Ember = 0xFFF3A45B'u32
  EmberHot = 0xFFFFD59A'u32
  Hp = 0xFFE97969'u32
  Mana = 0xFF78BDE0'u32
  Air = 0xFF9CCBD0'u32
  Lev = 0xFFE7C873'u32
  Gold = 0xFFF0C46C'u32
  Violet = 0xFFB9A0DA'u32

  # The controls' palette. Every pair below is a measured WCAG 2.2 ratio against
  # the fill it actually sits on (docs/DEMO-READY.md §7 engine frame, ratios from
  # `apps/_design/design.nim`'s contrastRatio):
  #   BtnLine/BtnFill    4.26:1   (was 0x45404A at 1.65:1 — the box was invisible)
  #   BtnLine/BtnHover   3.76:1   BtnLine/BtnPress 3.32:1
  #   BtnInk/BtnFill    11.63:1   BtnInkHot/BtnHover 12.30:1
  #   Ring/BtnFill      12.06:1   (the 2 px focus ring)
  #   AccentInk/AccentFill 8.55:1, on hover 9.92:1, on press 6.86:1
  BtnFill = 0x1B1E28
  BtnHover = 0x252833
  BtnPress = 0x2C3140
  BtnLine = 0x8A7E80
  BtnInk = 0xE3D6C5
  BtnInkHot = 0xF3EAD9
  Ring = 0xFFD59A
  AccentFill = 0xE6A15C
  AccentHover = 0xF0B070
  AccentPress = 0xD08F4C
  AccentInk = 0x151117
  WandFillOn = 0x684229     ## equipped wand: ink 6.98:1, border 6.35:1
  WandHoverOn = 0x7A5133    ## ink 5.49:1, border 4.99:1
  WandPressOn = 0x8A5C38    ## ink 4.57:1
  WandInkOn = 0xFFE2B0

var
  g: Deep
  paused = false
  muted = false
  acc = 0.0'f32
  clockMs = 0.0'f32
  actionHeld: seq[int32] = @[]
  previousActions: seq[int32] = @[]
  pointerSeen = false
  pointerInWorld = false
  pointerFire = false
  pointerX = 0.0'f32
  pointerY = 0.0'f32
  aimCellX = 0.0'f64
  aimCellY = 0.0'f64
  matTag = "air"
  kickCount = 0
  lastAction = "THE WELL IS LISTENING"
  worldPixels = newBuffer()
  scene: Node
  wandButtons: array[4, Node]
  choiceButtons: array[3, Node]
  pauseButton: Node
  soundButton: Node
  restartButton: Node
  voices: array[5, Node]
  voiceOffAt: array[5, float32]
  nextVoice = 0
  audioReady = false

proc mono(d: Draw; x, y, size: float32; colour: uint32; s: string; weight = 400): Draw =
  d.textFace(x, y, size, colour, Mono, s, weight)

proc sans(d: Draw; x, y, size: float32; colour: uint32; s: string; weight = 400): Draw =
  d.textFace(x, y, size, colour, Sans, s, weight)

proc textW(s: string; size: float32; family = Mono; weight = 400): float32 =
  result = textWidth(s, size, family, weight)
  if result <= 0.0: result = float32(s.len) * size * 0.58

proc centred(d: Draw; cx, y, size: float32; colour: uint32; s: string;
             family = Sans; weight = 400): Draw =
  d.textFace(cx - textW(s, size, family, weight) * 0.5, y, size, colour, family, s, weight)

proc number(v: int; width = 3): string =
  result = $max(0, v)
  while result.len < width: result = "0" & result

proc fixed(v: float64; digits = 1): string =
  var p = 1
  for _ in 0 ..< digits: p *= 10
  let whole = int(v)
  let frac = int((v - float64(whole)) * float64(p) + 0.5)
  result = $whole
  if digits > 0:
    var f = $frac
    while f.len < digits: f = "0" & f
    result.add "." & f

proc bar(d: Draw; x, y, w, h: float32; value: float64; colour: uint32): Draw =
  result = d
  result = result.rect(x, y, w, h, 0xFF252833'u32, min(4.0, h * 0.5))
  let f = max(0.0, min(1.0, value))
  if f > 0.001:
    result = result.rect(x, y, max(2.0, w * float32(f)), h, colour, min(4.0, h * 0.5))
    result = result.rect(x + 2, y + 1, max(0.0, w * float32(f) - 4), 1,
                         0x60FFFFFF'u32, 0.5)

proc blip(freq, ms: float32; wave = 1'i32) =
  if muted or not audioReady: return
  let i = nextVoice
  nextVoice = (nextVoice + 1) mod voices.len
  voices[i].set(pFreq, freq)
  voices[i].set(pWave, wave)
  voices[i].set(pPlaying, 1'i32)
  voiceOffAt[i] = clockMs + ms

proc voiceTick() =
  if not audioReady: return
  for i in 0 ..< voices.len:
    if voiceOffAt[i] > 0.0 and (clockMs > voiceOffAt[i] or muted):
      voices[i].set(pPlaying, 0'i32)
      voiceOffAt[i] = 0.0

proc drainSounds() =
  for e in g.events:
    case e
    of sfxCast: blip(620, 90, 1)
    of sfxHit: blip(180, 70, 1)
    of sfxHurt: blip(120, 120, 2)
    of sfxGold: blip(880, 90, 0)
    of sfxPerk: blip(520, 150, 0)
    of sfxJump: blip(300, 70, 1)
    of sfxKick: blip(90, 90, 1)
    of sfxDead: blip(70, 500, 3)
    of sfxWin: blip(660, 400, 0)
    of sfxKill: blip(240, 100, 1)
    of sfxBoom: blip(120, 260, 1)
  g.events.setLen(0)

proc makeInput(): Input =
  result.left = keyHeld('a') or keyHeld(keyLeft)
  result.right = keyHeld('d') or keyHeld(keyRight)
  result.jump = keyHeld('w') or keyHeld(keySpace) or keyHeld(keyUp)
  # A nested AppView receives canvas pointer events, while the root's independent
  # mouse-button bitmask is not guaranteed to reach it. The event latch is therefore
  # the authoritative held state; mouseHeld also supports a directly launched app.
  result.fire = (pointerFire or mouseHeld(1)) and pointerInWorld
  if pointerSeen:
    result.aimX = aimCellX
    result.aimY = aimCellY
  else:
    result.aimX = g.player.x + float64(g.player.dir) * 22.0
    result.aimY = g.player.y + 2.0
  g.aimX = result.aimX
  g.aimY = result.aimY - g.camY

proc statusLine(): string =
  if g.player.burning > 0: result.add "BURNING  "
  if g.player.wet > 0: result.add "WET  "
  if g.player.oiled > 0: result.add "OILED  "
  if g.player.toxic > 0: result.add "TOXIC  "
  if g.player.air < 40: result.add "LOW AIR  "
  if result.len == 0: result = "VITAL SIGNS NOMINAL"
  else: result = result.strip

proc refreshSurvey() =
  if pointerSeen and pointerInWorld:
    matTag = nameOf(g.g.at(int(aimCellX), int(aimCellY + g.camY)))
  else:
    matTag = "—"

proc newRun(sd: uint32) =
  g = newDeep(sd)
  paused = false
  acc = 0.0
  previousActions.setLen(0)
  pointerSeen = false
  pointerInWorld = false
  pointerFire = false
  aimCellX = g.player.x + 24.0
  aimCellY = g.player.y - 6.0
  g.aimX = aimCellX
  g.aimY = aimCellY - g.camY
  g.toast = "EXPEDITION " & $g.sd & "  /  ENTER THE MINES"
  g.toastT = 150
  lastAction = "A NEW DESCENT BEGINS"
  kickCount = 0
  g.renderFb()
  worldPixels.setData(addr g.fb[0], g.fb.len)
  refreshSurvey()

proc advance() =
  let dt = frameDt()
  acc += min(0.05'f32, max(0.0'f32, dt))
  var steps = 0
  while acc >= 1.0'f32 / 60.0'f32 and steps < 4:
    if not paused and not g.offering:
      g.update(makeInput())
    acc -= 1.0'f32 / 60.0'f32
    inc steps
  if steps > 0:
    g.renderFb()
    worldPixels.setData(addr g.fb[0], g.fb.len)
    refreshSurvey()
    drainSounds()

proc togglePause() =
  if g.st == gsPlay:
    paused = not paused
    previousActions.setLen(0)
    lastAction = if paused: "SIMULATION HELD" else: "EXPEDITION RESUMED"

proc action(code: int32) =
  if g.offering:
    if code >= int32(ord('1')) and code <= int32(ord('3')):
      discard g.choosePerk(int(code - int32(ord('1'))))
      lastAction = "BLESSING ACCEPTED"
    return
  if code >= int32(ord('1')) and code <= int32(ord('4')):
    g.curWand = int(code - int32(ord('1')))
    lastAction = g.wands[g.curWand].name & " EQUIPPED"
  elif code == int32(ord('f')) and not paused and g.st == gsPlay:
    g.kick(makeInput())
    inc kickCount
    lastAction = "KICK  /  IMPACT " & number(kickCount, 2)
  elif code == int32(ord('g')) and not paused and g.st == gsPlay:
    let before = g.flasks.len
    g.throwFlask(makeInput())
    if g.flasks.len < before: lastAction = "FLASK CAST INTO THE DARK"
    else: lastAction = "NO FLASK IN THE SATCHEL"
  elif code == keyEscape or code == int32(ord('p')):
    togglePause()
  elif code == int32(ord('r')) and g.st != gsPlay:
    newRun(g.sd + 1'u32)

proc pollActions() =
  const codes = [keyEscape, int32(ord('p')), int32(ord('r')), int32(ord('f')),
                 int32(ord('g')), int32(ord('1')), int32(ord('2')),
                 int32(ord('3')), int32(ord('4'))]
  previousActions.setLen(0)
  for code in codes:
    if keyHeld(code):
      previousActions.add code
      if code notin actionHeld: action(code)
  actionHeld = previousActions

proc aimAtPointer() =
  let (px, py) = pointerPos()
  pointerX = px
  pointerY = py
  pointerInWorld = px >= WorldX and px <= WorldX + WorldW and
                   py >= WorldY and py <= WorldY + WorldH
  if pointerInWorld:
    aimCellX = min(float64(VW - 1), max(0.0, float64((px - WorldX) / WorldW * float32(VW))))
    aimCellY = min(float64(VH - 1), max(0.0, float64((py - WorldY) / WorldH * float32(VH))))
    pointerSeen = true
  refreshSurvey()

proc portal(d: Draw; cx, cy, r: float32; colour: uint32): Draw =
  result = d.moveTo(cx, cy - r)
  for i in 1 .. 8:
    let a = -PI * 0.5 + float64(i) * PI * 0.25
    let rr = if i mod 2 == 0: r else: r * 0.46
    result = result.lineTo(cx + float32(cos(a)) * rr, cy + float32(sin(a)) * rr)
  result = result.close().fill(colour)

proc frameBackdrop(): Draw =
  result = Draw().linearDown(0, 0, float32(WinW), float32(WinH), Night, 0xFF111019'u32)
  result = result.noiseRect(0, 0, float32(WinW), float32(WinH),
                            0x060B1018'u32, 0x0917141B'u32,
                            freq = 0.009, freqY = 0.055, octaves = 3, seed = 37)
  # A restrained living frame. These are native ornaments, not cave imagery: every
  # cave pixel below is still produced by the simulation's own RGBA framebuffer.
  let pulse = 0.5 + 0.5 * sin(clockMs * 0.0017)
  result = result.soft(26).circle(1168, 48, 42, 0x16D88446'u32)
  for i in 0 ..< 18:
    let x = 22.0 + float32((i * 193) mod 1220)
    let y = 15.0 + float32((i * 47) mod 770)
    let a = 18 + int(16.0 * (0.5 + 0.5 * sin(clockMs * 0.001 + float32(i))))
    result = result.circle(x, y, if i mod 5 == 0: 1.1 else: 0.65,
                           (uint32(a) shl 24) or 0xD08A55'u32)
  result = result.line(24, 84, 1256, 84, EdgeSoft, 1)
  result = result.line(24, 84, 235, 84, Ember, 2)
  result = result.portal(1240, 49, 9 + float32(pulse), Ember)

proc worldFrame(d: Draw): Draw =
  result = d
  result = result.soft(16).rect(WorldX - 3, WorldY + 3, WorldW + 6, WorldH + 8,
                                0x70000000'u32, 5)
  result = result.rect(WorldX - 1, WorldY - 1, WorldW + 2, WorldH + 2, 0xFF533B30'u32, 3)
  result = result.pixels(worldPixels, VW, VH, WorldX, WorldY, WorldW, WorldH)
  # Precision corner brackets frame the viewport without hiding live terrain.
  for (x, y, sx, sy) in [(WorldX, WorldY, 1.0'f32, 1.0'f32),
                         (WorldX + WorldW, WorldY, -1.0'f32, 1.0'f32),
                         (WorldX, WorldY + WorldH, 1.0'f32, -1.0'f32),
                         (WorldX + WorldW, WorldY + WorldH, -1.0'f32, -1.0'f32)]:
    result = result.line(x, y, x + sx * 24, y, Ember, 2)
    result = result.line(x, y, x, y + sy * 24, Ember, 2)
  result = result.rect(WorldX + 14, WorldY + 12, 222, 27, 0xD6080B12'u32, 2)
  result = result.circle(WorldX + 26, WorldY + 25, 3.5,
                         if paused: Muted elif g.st == gsPlay: Ember else: Hp)
  result = result.mono(WorldX + 38, WorldY + 30, 11, EmberHot,
                       if paused: "SIMULATION HELD" elif g.st == gsPlay: "LIVE MATERIAL FIELD" else: "EXPEDITION ENDED", 700)
  if pointerSeen and pointerInWorld:
    let rx = WorldX + float32(aimCellX) / float32(VW) * WorldW
    let ry = WorldY + float32(aimCellY) / float32(VH) * WorldH
    result = result.circle(rx, ry, 6, 0x48FFD59A'u32)
    result = result.circle(rx, ry, 2, 0xD8FFD59A'u32)
    result = result.line(rx - 11, ry, rx - 6, ry, EmberHot, 1)
    result = result.line(rx + 6, ry, rx + 11, ry, EmberHot, 1)
    result = result.line(rx, ry - 11, rx, ry - 6, EmberHot, 1)
    result = result.line(rx, ry + 6, rx, ry + 11, EmberHot, 1)

proc expeditionRail(d: Draw): Draw =
  result = d
  result = result.linearDown(944, 104, 312, 504, 0xFA201C23'u32, 0xFF10141B'u32, 4)
  result = result.line(944, 104, 1256, 104, Ember, 2)
  result = result.mono(968, 131, 11, Ember, "EXPEDITION  /  CURRENT STRATUM", 700)
  result = result.sans(968, 159, 26, Ink, biomeName(int(g.player.y)), 700)
  result = result.mono(968, 198, 12, Muted,
                       "DEPTH  " & number(g.run.depth) & " m   /   Y " & $int(g.player.y), 700)
  result = result.mono(1180, 132, 11, Muted, number(max(0, layerAt(int(g.player.y))) + 1, 2) & " / 05", 700)
  result = result.line(968, 214, 1232, 214, EdgeSoft, 1)
  result = result.mono(968, 230, 11, Muted, "THE FIVE STRATA", 700)
  let current = layerAt(int(g.player.y))
  for i, b in Strata:
    let y = 250.0'f32 + float32(i) * 23.0
    let passed = current > i or g.st == gsWin
    let here = current == i
    result = result.line(977, y + 4, 977, y + 19,
                         if passed: Ember else: EdgeSoft, 1)
    result = result.circle(977, y, if here: 4.5 else: 3.0,
                           if here: EmberHot elif passed: Ember else: Muted)
    if here: result = result.circle(977, y, 8, 0x38F3A45B'u32)
    result = result.mono(993, y + 4, 11,
                         if here: Ink elif passed: Ink else: Muted,
                         number(i + 1, 2) & "  " & b.name, if here: 700 else: 500)
  result = result.line(968, 365, 1232, 365, EdgeSoft, 1)
  let hpText = $int(ceil(g.player.hp)) & " / " & $int(g.player.maxHp)
  result = result.mono(968, 390, 11, Ink, "VITAL", 700)
  result = result.mono(1232 - textW(hpText, 12, Mono, 700), 390, 12, Hp, hpText, 700)
  result = result.bar(968, 399, 264, 9, g.player.hp / max(1.0, g.player.maxHp), Hp)
  let w = g.wands[g.curWand]
  let manaText = $int(w.mana) & " / " & $int(w.manaMax)
  result = result.mono(968, 432, 11, Ink, "MANA", 700)
  result = result.mono(1232 - textW(manaText, 12, Mono, 700), 432, 12, Mana, manaText, 700)
  result = result.bar(968, 441, 264, 9, w.mana / max(1.0, w.manaMax), Mana)
  let airText = $g.player.air & " / 90"
  result = result.mono(968, 474, 11, Ink, "BREATH", 700)
  result = result.mono(1232 - textW(airText, 12, Mono, 700), 474, 12, Air, airText, 700)
  result = result.bar(968, 483, 264, 8, float64(g.player.air) / 90.0, Air)
  let levText = $int(g.player.hover) & "%"
  result = result.mono(968, 513, 11, Ink, "LEVITATION", 700)
  result = result.mono(1232 - textW(levText, 12, Mono, 700), 513, 12, Lev, levText, 700)
  result = result.bar(968, 522, 264, 8, g.player.hover / max(1.0, g.player.maxHover), Lev)
  result = result.mono(968, 558, 11,
                       if g.player.burning > 0 or g.player.toxic > 0 or g.player.air < 40: Hp else: Muted,
                       statusLine(), 700)
  result = result.mono(968, 585, 12, Ink,
                       "POSITION  X " & number(int(g.player.x)) & "  Y " & number(int(g.player.y)), 700)

proc lowerDeck(d: Draw): Draw =
  result = d
  let w = g.wands[g.curWand]
  result = result.mono(26, 710, 11, Ember, "ACTIVE DECK", 700)
  result = result.sans(119, 711, 16, Ink, w.name, 700)
  var recharge = "READY"
  if w.rechT > 0: recharge = "RECHARGING  " & $w.rechT
  elif w.delayT > 0: recharge = "CAST DELAY  " & $w.delayT
  result = result.mono(310, 710, 11, if recharge == "READY": Mana else: Gold, recharge, 700)
  result = result.mono(520, 710, 11, Muted,
                       "REGEN " & fixed(w.regen) & "/s   DELAY " & $int(w.castDelay) & "   FLASKS " & $g.flasks.len, 600)
  result = result.mono(968, 710, 12, Gold, number(g.run.gold, 4) & " GOLD", 700)
  result = result.mono(1110, 710, 11, Ink,
                       number(g.run.kills, 2) & " KILLS  /  " & number(g.run.casts, 3) & " CASTS", 700)
  var x = 26.0'f32
  let cardWidth = (918.0'f32 - float32(max(0, w.nslots - 1)) * 8.0) / float32(w.nslots)
  for i in 0 ..< w.nslots:
    let active = i == w.cursor
    let tag = if w.slots[i] >= 0: spellName(int(w.slots[i])) else: "EMPTY"
    # 11 px is the legible floor (design type scale). A wand has at most 8 slots, so
    # the label "NN  FIREBALL" is 12 glyphs: 12 x 6.63 = 79.6 px of a 223.5 px card
    # (4 slots) or of a 107.75 px card (8 slots). The old 9 px shrink never fired.
    result = result.rect(x, 724, cardWidth - 8, 28,
                         if active: 0xFF553823'u32 else: 0xFF1B1D26'u32, 3)
    if active:
      result = result.rect(x, 724, 3, 28, Ember, 1)
      result = result.line(x + 3, 724, x + cardWidth - 8, 724, 0xAAFFD59A'u32, 1)
    result = result.mono(x + 10, 743, 11,
                         if active: EmberHot elif w.slots[i] >= 0: Ink else: Muted,
                         number(i + 1, 2) & "  " & tag, if active: 700 else: 500)
    x += cardWidth
  result = result.mono(968, 743, 11, Ink, "SURVEY  /  " & matTag.toUpperAscii, 700)
  result = result.line(24, 760, 1256, 760, EdgeSoft, 1)
  result = result.mono(25, 785, 11, Ink,
                       "A D  MOVE    W / SPACE  JUMP + HOVER    LMB  CAST    F  KICK    G  FLASK    1–4  WANDS", 600)
  result = result.mono(25, 803, 11, Muted,
                       "40 MATERIALS  /  PROCEDURAL CAVES  /  FIXED 60 HZ SIMULATION  /  SEED " & $g.sd)
  result = result.mono(850, 803, 11, Ember, lastAction, 700)

proc stateOverlay(d: Draw): Draw =
  result = d
  if g.offering:
    result = result.rect(WorldX, WorldY, WorldW, WorldH, 0xE6090B12'u32, 2)
    result = result.centred(WorldX + WorldW * 0.5, 190, 11, Ember, "SANCTUM REACHED", Mono, 700)
    result = result.centred(WorldX + WorldW * 0.5, 238, 34, Ink, "THE WELL OFFERS A BOON", Sans, 700)
    result = result.centred(WorldX + WorldW * 0.5, 269, 12, Muted,
                            "THE CAVE IS HELD. CHOOSE ONE BLESSING.", Sans)
    for i in 0 .. 2:
      let x = 86.0'f32 + float32(i) * 280.0
      result = result.rect(x, 326, 256, 174, PanelHi, 4)
      result = result.line(x, 326, x + 256, 326, Ember, 2)
      if g.offer[i] >= 0:
        let p = Perk(g.offer[i])
        result = result.centred(x + 128, 356, 12, EmberHot, perkNames[ord(p)], Mono, 700)
        result = result.centred(x + 128, 486, 11, Muted, perkDesc[ord(p)], Sans)
    result = result.centred(WorldX + WorldW * 0.5, 544, 11, Muted,
                            "CHOOSE WITH THE MOUSE OR KEYS 1 / 2 / 3", Mono)
  elif paused:
    result = result.rect(WorldX, WorldY, WorldW, WorldH, 0xD9090B12'u32, 2)
    result = result.centred(WorldX + WorldW * 0.5, 270, 11, Ember, "THE MATERIAL CLOCK IS STOPPED", Mono, 700)
    result = result.centred(WorldX + WorldW * 0.5, 330, 34, Ink, "DESCENT PAUSED", Sans, 700)
    result = result.centred(WorldX + WorldW * 0.5, 371, 12, Muted,
                            "ESC OR PAUSE TO RETURN TO THE WELL", Sans)
  elif g.st != gsPlay:
    result = result.rect(WorldX, WorldY, WorldW, WorldH, 0xE4090B12'u32, 2)
    let won = g.st == gsWin
    result = result.centred(WorldX + WorldW * 0.5, 178, 11, if won: Gold else: Hp,
                            if won: "THE WELL EYE IS CLOSED" else: "EXPEDITION RECORD / FINAL", Mono, 700)
    result = result.centred(WorldX + WorldW * 0.5, 237, 34, Ink,
                            if won: "DAWN BELOW" else: causeTitle(g.run.causeCode), Sans, 700)
    result = result.centred(WorldX + WorldW * 0.5, 273, 12, Muted,
                            if won: "THE WELL IS NOT HEALED. ITS RULES ARE YOURS." else: g.run.causeMsg, Sans)
    result = result.line(324, 301, 620, 301, Edge, 1)
    result = result.centred(WorldX + WorldW * 0.5, 333, 12, EmberHot,
                            number(g.run.depth) & " m   /   " & $g.run.kills & " KILLS   /   " &
                            $g.run.gold & " GOLD   /   " & $g.run.frames & " TICKS", Mono, 700)
    result = result.centred(WorldX + WorldW * 0.5, 572, 11, Muted,
                            "A NEW SEED. THE SAME UNFORGIVING LAWS.", Mono)

proc frameArt(): string =
  var d = frameBackdrop()
  d = d.portal(31, 47, 13, Ember)
  d = sans(d, 54, 52, 26, Ink, "EMBERDEEP", 800)
  d = mono(d, 268, 49, 11, Ember, "A LIVING-CAVE ROGUELIKE", 700)
  d = mono(d, 268, 66, 11, Muted, "EVERY CELL IS REAL. EVERY DESCENT IS A DIFFERENT STORY.")
  d = mono(d, 1016, 37, 11, Muted, "NATIVE MATERIAL ENGINE", 700)
  d = mono(d, 1016, 61, 12, EmberHot, "40 MATERIALS  /  1 SEED")
  d = d.worldFrame()
  d = d.expeditionRail()
  d = d.lowerDeck()
  if g.toastT > 0 and g.toast.len > 0 and not g.offering and g.st == gsPlay:
    let tw = textW(g.toast, 12, Mono, 700)
    d = d.rect(WorldX + 18, WorldY + WorldH - 50, tw + 26, 31, 0xE20A0C12'u32, 3)
    d = mono(d, WorldX + 30, WorldY + WorldH - 29, 12, EmberHot, g.toast, 700)
  d = d.stateOverlay()
  d.cmds

proc controlStyle(n: Node; w, h, x, y: int32; accent = false) =
  ## One native control, on the design system: the `RsCtl` radius (`ctlOn`), type
  ## from the scale (`typeOn`), and the three states every control owes its user —
  ## hover, pressed and focus, painted by `render/native/engine.nim:1639 stateColor`.
  ##
  ## `border` is 2 px because the focus ring is 2 px and the wire carries one border
  ## width per node; `focusRing()` is not used here because it writes the ring into
  ## the node's *base* border, and this app's rest border has to keep its own 4.26:1.
  n.width(w)
  n.height(h)
  n.set(pAbsolute, 1'i32)
  n.set(pInsetLeft, float32(x))
  n.set(pInsetTop, float32(y))
  typeOn(n, if accent: FsBody else: FsSmall, W700)
  n.set(pFontFamily, Mono)
  ctlOn(n, if accent: AccentFill else: BtnFill, if accent: AccentInk else: BtnInk)
  n.set(pBorderWidth, 2'i32)
  n.set(pBorderColor, wireI32(if accent: Ring else: BtnLine))
  # hover
  n.set(pHoverFill, wireI32(if accent: AccentHover else: BtnHover))
  n.set(pHoverBorder, wireI32(if accent: Ring else: BtnLine))
  n.set(pHoverColor, wireI32(if accent: AccentInk else: BtnInkHot))
  # pressed
  n.set(pPressFill, wireI32(if accent: AccentPress else: BtnPress))
  n.set(pPressBorder, wireI32(if accent: Ring else: BtnLine))
  n.set(pPressColor, wireI32(if accent: AccentInk else: BtnInkHot))
  # focused: the 2 px ring, at 12.06:1 on the neutral fill and 9.06:1 on the accent
  n.set(pFocusBorder, wireI32(Ring))
  n.set(pFocusColor, wireI32(if accent: AccentInk else: BtnInkHot))

proc refreshControls() =
  for i in 0 .. 3:
    wandButtons[i].setText(number(i + 1, 2) & "  /  " & g.wands[i].name)
    let equipped = i == g.curWand
    wandButtons[i].setFill(if equipped: WandFillOn else: BtnFill)
    wandButtons[i].set(pHoverFill, wireI32(if equipped: WandHoverOn else: BtnHover))
    wandButtons[i].set(pPressFill, wireI32(if equipped: WandPressOn else: BtnPress))
    wandButtons[i].set(pTextColor, wireI32(if equipped: WandInkOn else: BtnInk))
    wandButtons[i].set(pHoverColor, wireI32(if equipped: WandInkOn else: BtnInkHot))
    wandButtons[i].set(pPressColor, wireI32(if equipped: WandInkOn else: BtnInkHot))
    wandButtons[i].set(pBorderColor, wireI32(if equipped: Ring else: BtnLine))
  pauseButton.setText(if paused: "RESUME" else: "PAUSE")
  pauseButton.visible(g.st == gsPlay and not g.offering)
  soundButton.setText(if muted: "SOUND OFF" else: "SOUND ON")
  soundButton.visible(not g.offering)
  restartButton.visible(g.st != gsPlay)
  for i in 0 .. 2:
    choiceButtons[i].visible(g.offering and g.offer[i] >= 0)
    if g.offer[i] >= 0:
      choiceButtons[i].setText($(i + 1) & "  /  " & perkNames[g.offer[i]])

proc refresh() =
  refreshControls()
  scene.set(pDraw, frameArt())

proc wandClick(index: int): proc() =
  ## A fresh closure cell per Native Button; one shared loop variable would leave
  ## every card selecting the final wand (proved through the real AppView click).
  result = proc() =
    g.curWand = index
    lastAction = g.wands[index].name & " EQUIPPED"
    refresh()

proc blessingClick(index: int): proc() =
  result = proc() =
    discard g.choosePerk(index)
    lastAction = "BLESSING ACCEPTED"
    refresh()

proc main() =
  let win = window("EMBERDEEP", WinW, WinH)
  win.setFill(0x080A10)
  let stage = stack(win)
  stage.width(WinW)
  stage.height(WinH)
  stage.setFill(0x080A10)
  scene = canvas(stage, WinW, WinH)
  scene.set(pDraw, frameArt())
  scene.addHandler(evFrame, proc() =
    clockMs += max(0.0'f32, frameDt()) * 1000.0'f32
    voiceTick()
    pollActions()
    advance()
    refresh())
  scene.addHandler(evPointerDown, proc() =
    aimAtPointer()
    pointerFire = pointerInWorld)
  scene.addHandler(evPointerMove, proc() = aimAtPointer())
  scene.addHandler(evPointerUp, proc() =
    aimAtPointer()
    pointerFire = false)
  for i in 0 .. 3:
    wandButtons[i] = button(stage, number(i + 1, 2) & " / WAND")
    controlStyle(wandButtons[i], 296, 52, 24 + i * 308, 626)
    wandButtons[i].addHandler(evClick, wandClick(i))
  pauseButton = button(stage, "PAUSE")
  controlStyle(pauseButton, 94, 34, 1034, 771)
  pauseButton.addHandler(evClick, proc() = togglePause(); refresh())
  soundButton = button(stage, "SOUND ON")
  controlStyle(soundButton, 112, 34, 1140, 771)
  soundButton.addHandler(evClick, proc() = muted = not muted; voiceTick(); refresh())
  restartButton = button(stage, "DESCEND AGAIN")
  controlStyle(restartButton, 240, 48, 352, 402, accent = true)
  restartButton.addHandler(evClick, proc() = newRun(g.sd + 1'u32); refresh())
  for i in 0 .. 2:
    choiceButtons[i] = button(stage, "BLESSING")
    controlStyle(choiceButtons[i], 232, 42, 98 + i * 280, 382, accent = true)
    choiceButtons[i].addHandler(evClick, blessingClick(i))
  for i in 0 .. 4:
    voices[i] = make(nkSynth, stage)
    voices[i].set(pPlaying, 0'i32)
    voices[i].set(pFreq, 440.0'f32)
    voices[i].set(pWave, 1'i32)
    voices[i].set(pVolume, if i == 4: 0.16'f32 else: 0.10'f32)
    voices[i].set(pAttack, 0.004'f32)
    voices[i].set(pRelease, if i == 4: 0.16'f32 else: 0.07'f32)
  audioReady = true
  refresh()

newRun(20261029'u32)

proc yantra_main*() {.exportc: "yantra_main".} =
  main()
