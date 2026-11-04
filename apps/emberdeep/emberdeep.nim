## emberdeep.nim — the rules of EMBERDEEP, a Yantra port of the falling-sand
## roguelike whose whole world is a 384x216 grid of material ids.
##
## Everything observable lives here and nothing else does: the 40-material table
## with the original's densities and colours, the bottom-up cellular automaton and
## its alchemy (oil on water, blood under it, lava + water -> stone + steam, acid
## eating hardness), the seeded cave generator, the player's physics and statuses,
## the deck-evaluated wand, six creatures, the lantern/radial light model and the
## software renderer that turns all of it into 331,776 RGBA bytes.
##
## No engine imports. `tests/t_emberdeep.nim` drives every rule natively; `app.nim`
## only samples the keyboard, calls `update`, and shows the framebuffer + HUD.
##
## Faithfulness note: the ORDER of operations is part of the behaviour (which cell
## reacts first, which seeded roll is spent where). The loops below therefore follow
## the original's order even where another order would look tidier.

import std/math

# --------------------------------------------------------------- dimensions ---

const
  VW* = 384                    ## screen cells across
  VH* = 216                    ## screen cells down
  WW* = 384                    ## world cells across
  WH* = 2100                   ## world cells down
  SurfY* = 72                  ## sky/ground line
  BandH* = 352                 ## playable rows in a layer
  HoldH* = 68                  ## sanctuary rows between layers
  LayerPeriod* = BandH + HoldH ## 420
  MatCount* = 40
  Sanctums* = 4                ## safe rooms between the strata
  LightN* = VW * VH

# --------------------------------------------------------------- materials ---

const
  MatAir* = 0'u8
  MatRock* = 1'u8
  MatDirt* = 2'u8
  MatSand* = 3'u8
  MatWater* = 4'u8
  MatOil* = 5'u8
  MatLava* = 6'u8
  MatWood* = 7'u8
  MatIce* = 8'u8
  MatMoss* = 9'u8
  MatBlood* = 10'u8
  MatSteam* = 11'u8
  MatFire* = 12'u8
  MatSmoke* = 13'u8
  MatGold* = 14'u8
  MatSnow* = 15'u8
  MatToxic* = 16'u8
  MatStone* = 17'u8
  MatMetal* = 18'u8
  MatBrick* = 19'u8
  MatAcid* = 20'u8
  MatCoal* = 21'u8
  MatFungus* = 22'u8
  MatGunp* = 23'u8
  MatPgas* = 24'u8
  MatSlime* = 25'u8
  MatAsh* = 26'u8
  MatEmber* = 27'u8
  MatSandst* = 28'u8
  MatSnowrock* = 29'u8
  MatVine* = 30'u8
  MatGlass* = 31'u8
  MatFgas* = 32'u8
  MatRust* = 33'u8
  MatCrystal* = 34'u8
  MatMud* = 35'u8
  MatWoodp* = 36'u8
  MatDense* = 37'u8
  MatGrass* = 38'u8
  MatBone* = 39'u8

type
  MatKind* = enum
    mkAir, mkStatic, mkPowder, mkLiquid, mkGas, mkFire

  MatDef* = object
    name*: string
    kind*: MatKind
    den*: float32
    hard*, flamm*, emit*, cv*: uint8
    r*, g*, b*, er*, eg*, eb*: uint8

## The 40 materials in the original's own order and numbers: density, hardness,
## flammability, emitted light, colour-variance and the hex colour each one paints.
const mats*: array[MatCount, MatDef] = [
  MatDef(name: "air", kind: mkAir, den: 0.00, hard: 0, flamm: 0, emit: 0, cv: 0, r: 8, g: 9, b: 14, er: 255, eg: 180, eb: 80),
  MatDef(name: "rock", kind: mkStatic, den: 5.00, hard: 10, flamm: 0, emit: 0, cv: 10, r: 78, g: 74, b: 70, er: 255, eg: 180, eb: 80),
  MatDef(name: "dirt", kind: mkStatic, den: 4.00, hard: 6, flamm: 0, emit: 0, cv: 12, r: 98, g: 72, b: 52, er: 255, eg: 180, eb: 80),
  MatDef(name: "sand", kind: mkPowder, den: 1.80, hard: 4, flamm: 0, emit: 0, cv: 14, r: 196, g: 162, b: 92, er: 255, eg: 180, eb: 80),
  MatDef(name: "water", kind: mkLiquid, den: 1.00, hard: 0, flamm: 0, emit: 0, cv: 10, r: 58, g: 122, b: 186, er: 255, eg: 180, eb: 80),
  MatDef(name: "oil", kind: mkLiquid, den: 0.80, hard: 0, flamm: 90, emit: 0, cv: 8, r: 92, g: 64, b: 28, er: 255, eg: 180, eb: 80),
  MatDef(name: "lava", kind: mkLiquid, den: 2.60, hard: 0, flamm: 0, emit: 200, cv: 18, r: 255, g: 92, b: 28, er: 255, eg: 120, eb: 20),
  MatDef(name: "wood", kind: mkStatic, den: 3.00, hard: 6, flamm: 80, emit: 0, cv: 10, r: 118, g: 78, b: 46, er: 255, eg: 180, eb: 80),
  MatDef(name: "ice", kind: mkStatic, den: 3.00, hard: 8, flamm: 0, emit: 0, cv: 10, r: 170, g: 210, b: 230, er: 255, eg: 180, eb: 80),
  MatDef(name: "moss", kind: mkStatic, den: 2.00, hard: 4, flamm: 50, emit: 0, cv: 10, r: 62, g: 108, b: 52, er: 255, eg: 180, eb: 80),
  MatDef(name: "blood", kind: mkLiquid, den: 1.05, hard: 0, flamm: 0, emit: 0, cv: 10, r: 168, g: 36, b: 48, er: 255, eg: 180, eb: 80),
  MatDef(name: "steam", kind: mkGas, den: 0.30, hard: 0, flamm: 0, emit: 12, cv: 8, r: 198, g: 214, b: 222, er: 255, eg: 180, eb: 80),
  MatDef(name: "fire", kind: mkFire, den: 0.15, hard: 0, flamm: 0, emit: 220, cv: 24, r: 255, g: 150, b: 40, er: 255, eg: 160, eb: 40),
  MatDef(name: "smoke", kind: mkGas, den: 0.20, hard: 0, flamm: 0, emit: 0, cv: 10, r: 86, g: 86, b: 96, er: 255, eg: 180, eb: 80),
  MatDef(name: "gold", kind: mkPowder, den: 3.00, hard: 4, flamm: 0, emit: 40, cv: 12, r: 232, g: 188, b: 64, er: 255, eg: 210, eb: 80),
  MatDef(name: "snow", kind: mkPowder, den: 0.90, hard: 3, flamm: 0, emit: 0, cv: 8, r: 226, g: 236, b: 244, er: 255, eg: 180, eb: 80),
  MatDef(name: "toxic", kind: mkLiquid, den: 1.15, hard: 0, flamm: 0, emit: 0, cv: 10, r: 132, g: 186, b: 42, er: 255, eg: 180, eb: 80),
  MatDef(name: "stone", kind: mkStatic, den: 5.00, hard: 10, flamm: 0, emit: 0, cv: 8, r: 96, g: 96, b: 100, er: 255, eg: 180, eb: 80),
  MatDef(name: "metal", kind: mkStatic, den: 7.00, hard: 12, flamm: 0, emit: 0, cv: 8, r: 118, g: 124, b: 132, er: 255, eg: 180, eb: 80),
  MatDef(name: "brick", kind: mkStatic, den: 8.00, hard: 14, flamm: 0, emit: 0, cv: 8, r: 92, g: 86, b: 78, er: 255, eg: 180, eb: 80),
  MatDef(name: "acid", kind: mkLiquid, den: 1.40, hard: 0, flamm: 0, emit: 30, cv: 12, r: 150, g: 230, b: 60, er: 160, eg: 255, eb: 80),
  MatDef(name: "coal", kind: mkStatic, den: 4.00, hard: 8, flamm: 70, emit: 0, cv: 8, r: 32, g: 30, b: 34, er: 255, eg: 180, eb: 80),
  MatDef(name: "fungus", kind: mkStatic, den: 2.00, hard: 5, flamm: 55, emit: 90, cv: 14, r: 186, g: 72, b: 168, er: 220, eg: 80, eb: 210),
  MatDef(name: "gunp", kind: mkPowder, den: 1.30, hard: 3, flamm: 100, emit: 0, cv: 8, r: 58, g: 52, b: 46, er: 255, eg: 180, eb: 80),
  MatDef(name: "pgas", kind: mkGas, den: 0.25, hard: 0, flamm: 0, emit: 0, cv: 10, r: 96, g: 160, b: 48, er: 255, eg: 180, eb: 80),
  MatDef(name: "slime", kind: mkLiquid, den: 1.20, hard: 0, flamm: 0, emit: 0, cv: 10, r: 72, g: 168, b: 96, er: 255, eg: 180, eb: 80),
  MatDef(name: "ash", kind: mkPowder, den: 0.70, hard: 2, flamm: 0, emit: 0, cv: 8, r: 120, g: 118, b: 116, er: 255, eg: 180, eb: 80),
  MatDef(name: "ember", kind: mkPowder, den: 0.50, hard: 1, flamm: 20, emit: 160, cv: 16, r: 255, g: 110, b: 30, er: 255, eg: 140, eb: 30),
  MatDef(name: "sandst", kind: mkStatic, den: 5.00, hard: 9, flamm: 0, emit: 0, cv: 10, r: 164, g: 132, b: 84, er: 255, eg: 180, eb: 80),
  MatDef(name: "snowrock", kind: mkStatic, den: 5.00, hard: 10, flamm: 0, emit: 0, cv: 8, r: 132, g: 154, b: 168, er: 255, eg: 180, eb: 80),
  MatDef(name: "vine", kind: mkStatic, den: 2.00, hard: 3, flamm: 75, emit: 0, cv: 8, r: 48, g: 96, b: 44, er: 255, eg: 180, eb: 80),
  MatDef(name: "glass", kind: mkStatic, den: 3.00, hard: 5, flamm: 0, emit: 20, cv: 6, r: 168, g: 196, b: 204, er: 255, eg: 180, eb: 80),
  MatDef(name: "fgas", kind: mkGas, den: 0.12, hard: 0, flamm: 100, emit: 40, cv: 10, r: 180, g: 90, b: 40, er: 255, eg: 140, eb: 40),
  MatDef(name: "rust", kind: mkStatic, den: 6.00, hard: 11, flamm: 0, emit: 0, cv: 8, r: 140, g: 78, b: 48, er: 255, eg: 180, eb: 80),
  MatDef(name: "crystal", kind: mkStatic, den: 5.00, hard: 11, flamm: 0, emit: 110, cv: 10, r: 90, g: 210, b: 230, er: 80, eg: 230, eb: 255),
  MatDef(name: "mud", kind: mkPowder, den: 1.60, hard: 4, flamm: 0, emit: 0, cv: 10, r: 86, g: 64, b: 42, er: 255, eg: 180, eb: 80),
  MatDef(name: "woodp", kind: mkPowder, den: 1.10, hard: 3, flamm: 85, emit: 0, cv: 8, r: 130, g: 88, b: 52, er: 255, eg: 180, eb: 80),
  MatDef(name: "dense", kind: mkStatic, den: 9.00, hard: 15, flamm: 0, emit: 0, cv: 4, r: 36, g: 38, b: 44, er: 255, eg: 180, eb: 80),
  MatDef(name: "grass", kind: mkStatic, den: 2.00, hard: 2, flamm: 70, emit: 0, cv: 10, r: 72, g: 128, b: 48, er: 255, eg: 180, eb: 80),
  MatDef(name: "bone", kind: mkPowder, den: 1.50, hard: 4, flamm: 0, emit: 0, cv: 8, r: 214, g: 206, b: 180, er: 255, eg: 180, eb: 80),
]

proc kindOf*(m: uint8): MatKind {.inline.} = mats[m].kind
proc denOf*(m: uint8): float32 {.inline.} = mats[m].den
proc hardOf*(m: uint8): uint8 {.inline.} = mats[m].hard
proc flammOf*(m: uint8): uint8 {.inline.} = mats[m].flamm
proc emitOf*(m: uint8): uint8 {.inline.} = mats[m].emit
proc nameOf*(m: uint8): string {.inline.} = mats[m].name

proc isSolid*(m: uint8): bool {.inline.} =
  ## Powders count as solid for collision (you stand on sand), liquids do not.
  let k = mats[m].kind
  k == mkStatic or k == mkPowder

# ------------------------------------------------------------------ random ---

type
  Dice* = object
    s*: uint32

proc seedDice*(sd: uint32): Dice = Dice(s: sd)

proc roll*(d: var Dice): float64 =
  ## The original's own generator, reproduced exactly: mulberry32 with the
  ## `61 | x` multiplier (not `61 * x`), one value in [0, 1).
  d.s = d.s +  0x6D2B79F5'u32
  var x = d.s
  x = (x xor (x shr 15)) * (x or 1'u32)
  x = x xor (x + ((x xor (x shr 7)) * (x or 61'u32)))
  result = float64(x xor (x shr 14)) / 4294967296.0

proc rint*(d: var Dice; lo, hi: int): int =
  ## Uniform integer in lo..hi (both ends included).
  lo + int(roll(d) * float64(hi - lo + 1))

proc chance*(d: var Dice; p: float64): bool {.inline.} = roll(d) < p

# ------------------------------------------------------- value noise, seeded ---

proc phash*(sd: uint32; x, y: int32): uint32 =
  ## An integer hash salted with the world seed: the shape of every cave.
  var n = (cast[uint32](x) * 374761393'u32) + (cast[uint32](y) * 668265263'u32) + sd
  n = (n xor (n shr 13)) * 1274126177'u32
  result = n xor (n shr 16)

proc h2*(sd: uint32; x, y: float64): float64 {.inline.} =
  phash(sd, int32(floor(x)), int32(floor(y))).float64 / 4294967296.0

proc n2*(sd: uint32; x, y: float64): float64 =
  ## Bilinear value noise with a smoothstep fade.
  let xi = floor(x)
  let yi = floor(y)
  let fx = x - xi
  let fy = y - yi
  let ix = int32(xi)
  let iy = int32(yi)
  let a = phash(sd, ix, iy).float64 / 4294967296.0
  let b = phash(sd, ix + 1, iy).float64 / 4294967296.0
  let c = phash(sd, ix, iy + 1).float64 / 4294967296.0
  let e = phash(sd, ix + 1, iy + 1).float64 / 4294967296.0
  let ux = fx * fx * (3.0 - 2.0 * fx)
  let uy = fy * fy * (3.0 - 2.0 * fy)
  a + (b - a) * ux + (c - a) * uy + (a - b - c + e) * ux * uy

proc fbm*(sd: uint32; x, y: float64): float64 =
  n2(sd, x, y) * 0.55 + n2(sd, x * 2.1, y * 2.1) * 0.30 + n2(sd, x * 4.3, y * 4.3) * 0.15

# -------------------------------------------------------------------- grid ---

type
  Grid* = object
    cell*: seq[uint8]        ## one byte per cell: the material id
    life*: seq[uint8]        ## countdown for fire, smoke and steam
    mark*: seq[uint8]        ## "already moved this tick" stamp
    stamp*: uint8
    dice*: Dice              ## the one seeded stream every physics roll spends

proc newGrid*(w, h: int): Grid =
  result.cell = newSeq[uint8](w * h)
  result.life = newSeq[uint8](w * h)
  result.mark = newSeq[uint8](w * h)

proc at*(g: Grid; x, y: int): uint8 {.inline.} =
  ## Reads; out of bounds is DENSE, so the world has no leaky edge.
  if x < 0 or y < 0 or x >= WW or y >= WH: return MatDense
  g.cell[y * WW + x]

proc put*(g: var Grid; x, y: int; m: uint8; lf = 0) {.inline.} =
  ## Writes; out of bounds is dropped. `lf` is the new lifetime.
  if x < 0 or y < 0 or x >= WW or y >= WH: return
  let i = y * WW + x
  g.cell[i] = m
  g.life[i] = uint8(lf)

proc canOccupy*(g: Grid; x, y: int; m: uint8): bool =
  ## The whole density model. Air takes anything; dense rock and sanctum brick take
  ## nothing; liquids and powders displace gas and fire; a liquid takes a lighter
  ## liquid (the 0.04 epsilon stops equal weights swapping forever); a gas takes
  ## fire or a heavier gas (0.02). A liquid can never push into a powder, which is
  ## what keeps a sand pile standing.
  if x < 0 or y < 0 or x >= WW or y >= WH: return false
  let n = g.cell[y * WW + x]
  if n == MatAir: return true
  if n == MatDense or n == MatBrick: return false
  let tm = mats[m].kind
  let tn = mats[n].kind
  if tm == mkLiquid or tm == mkPowder:
    if tn == mkGas or tn == mkFire: return true
    if tn == mkLiquid and mats[m].den > mats[n].den + 0.04'f32: return true
  if tm == mkGas and (tn == mkFire or (tn == mkGas and mats[m].den < mats[n].den - 0.02'f32)):
    return true
  false

proc shiftCell*(g: var Grid; x, y, nx, ny: int): bool =
  ## Swap two cells, stamping only the destination, so the cell that arrived is not
  ## moved again this tick and the one that left is not re-simulated.
  if not g.canOccupy(nx, ny, g.at(x, y)): return false
  let i = y * WW + x
  let j = ny * WW + nx
  if g.mark[j] == g.stamp: return false
  let m = g.cell[i]
  let lf = g.life[i]
  g.cell[i] = g.cell[j]
  g.life[i] = g.life[j]
  g.cell[j] = m
  g.life[j] = lf
  g.mark[j] = g.stamp
  true

# ------------------------------------------------------------------- biomes ---

type
  Biome* = object
    name*: string
    bg*: array[3, int]
    amb*: int
    tint*: array[3, float64]

const
  Strata* = [
    Biome(name: "MINES", bg: [11, 13, 20], amb: 16, tint: [1.00, 0.95, 0.85]),
    Biome(name: "COAL PITS", bg: [9, 9, 14], amb: 11, tint: [0.75, 0.72, 0.78]),
    Biome(name: "FUNGAL", bg: [16, 8, 18], amb: 13, tint: [1.05, 0.80, 1.15]),
    Biome(name: "FROST", bg: [10, 16, 28], amb: 18, tint: [0.85, 1.05, 1.20]),
    Biome(name: "EMBERLAKE", bg: [18, 8, 8], amb: 9, tint: [1.15, 0.80, 0.70]),
  ]

const
  MouthBiome* = Biome(name: "MOUTH", bg: [8, 10, 22], amb: 48, tint: [1.0, 1.0, 1.0])
  SanctumBiome* = Biome(name: "SANCTUM", bg: [16, 16, 22], amb: 52, tint: [1.0, 1.0, 1.0])

proc layerAt*(y: int): int =
  ## -1 mouth, 0..4 a stratum, 10..13 the sanctuary under stratum i.
  if y < SurfY: return -1
  let t = y - SurfY
  let i = min(4, t div LayerPeriod)
  let o = t mod LayerPeriod
  if i < 4 and o >= BandH: return 10 + i
  min(4, i)

proc inSanctum*(y: int): bool = layerAt(y) >= 10

proc biomeOf*(y: int): Biome =
  let b = layerAt(y)
  if b < 0: return MouthBiome
  if b >= 10: return SanctumBiome
  Strata[b]

proc biomeName*(y: int): string = biomeOf(y).name

# ------------------------------------------------------------------- spells ---

type
  SpellKind* = enum skProj, skMod, skMulti
  SpellId* = enum
    spSpark, spBolt, spFireball, spDisc, spDrill, spBubble, spIce, spAcidBolt, spBomb,
    spSparkTrig, spBoltTimer, spTriple, spDual,
    spHoming, spFlameMod, spBounceMod, spDmgPlus, spLightMod, spSpeedMod, spExplMod

  Spell* = object
    tag*: string             ## our own short English tag for the HUD
    kind*: SpellKind
    mana*, delay*, rec*: float64
    dmg*, spd*: float64
    spr*, pierce*, bounce*, drill*, expl*, count*, sprAdd*: int
    timer*, draws*: int
    light*: float64
    lightAdd*, dmgMul*, spdMul*, homing*: float64
    fire*, freeze*, acid*: int
    trigger*: int            ## 0 none, 1 on hit, 2 on timer
    col*: array[3, uint8]

const SpellN* = 20

## Sixteen spells in four kinds — projectiles, modifiers, triggers, multipliers.
const spells*: array[SpellN, Spell] = [
  # 9 projectiles
  Spell(tag: "SPARK", kind: skProj, mana: 5, delay: 3, dmg: 9, spd: 4.4, spr: 3,
        col: [255'u8, 230, 110], light: 1.0),
  Spell(tag: "BOLT", kind: skProj, mana: 12, delay: 9, dmg: 20, spd: 5.2, spr: 1,
        col: [120'u8, 210, 255], light: 0.8),
  Spell(tag: "FIREBALL", kind: skProj, mana: 22, delay: 16, rec: 6, dmg: 26, spd: 2.7, spr: 5,
        col: [255'u8, 130, 40], light: 1.4, expl: 11, fire: 1),
  Spell(tag: "DISC", kind: skProj, mana: 16, delay: 11, dmg: 18, spd: 3.6, spr: 6,
        col: [210'u8, 220, 230], bounce: 1, pierce: 3),
  Spell(tag: "DRILL", kind: skProj, mana: 8, rec: -10, dmg: 7, spd: 6.2, spr: 0,
        col: [230'u8, 245, 255], light: 1.1, drill: 7),
  Spell(tag: "BUBBLE", kind: skProj, mana: 6, delay: 5, dmg: 8, spd: 2.3, spr: 10,
        col: [170'u8, 230, 255], bounce: 1),
  Spell(tag: "ICE", kind: skProj, mana: 14, delay: 10, dmg: 15, spd: 4.1, spr: 2,
        col: [180'u8, 230, 255], freeze: 1),
  Spell(tag: "ACID", kind: skProj, mana: 12, delay: 9, dmg: 11, spd: 3.1, spr: 4,
        col: [160'u8, 255, 70], acid: 1),
  Spell(tag: "BOMB", kind: skProj, mana: 35, delay: 18, rec: 36, dmg: 48, spd: 1.9, spr: 2,
        col: [255'u8, 214, 70], expl: 17),
  # 2 triggers
  Spell(tag: "SPARK>", kind: skProj, mana: 10, delay: 5, dmg: 6, spd: 4.0, spr: 2,
        col: [255'u8, 200, 80], light: 1.0, trigger: 1, draws: 1),
  Spell(tag: "BOLT>", kind: skProj, mana: 16, delay: 9, dmg: 10, spd: 3.5, spr: 1,
        col: [190'u8, 150, 255], light: 0.9, trigger: 2, timer: 26, draws: 1),
  # 2 multipliers
  Spell(tag: "x3", kind: skMulti, mana: 9, delay: 5, rec: 3, count: 3, sprAdd: 14),
  Spell(tag: "x2", kind: skMulti, mana: 4, delay: 2, rec: 1, count: 2, sprAdd: 8),
  # 7 modifiers
  Spell(tag: "HOME", kind: skMod, mana: 16, homing: 0.14),
  Spell(tag: "FLAME", kind: skMod, mana: 5, fire: 1),
  Spell(tag: "BOUNCE", kind: skMod, mana: 3, bounce: 1),
  Spell(tag: "DMG+", kind: skMod, mana: 12, delay: 4, dmgMul: 1.7),
  Spell(tag: "LIGHT", kind: skMod, mana: 3, lightAdd: 1.6),
  Spell(tag: "SPEED", kind: skMod, mana: 3, delay: -3, spdMul: 1.55),
  Spell(tag: "BLAST", kind: skMod, mana: 10, delay: 5, rec: 3, expl: 8),
]

const
  ProjIds* = [spSpark, spBolt, spFireball, spDisc, spDrill, spBubble, spIce, spAcidBolt, spBomb]
  ModIds* = [spHoming, spFlameMod, spBounceMod, spDmgPlus, spLightMod, spSpeedMod, spExplMod]
  TrigIds* = [spSparkTrig, spBoltTimer]
  MultiIds* = [spTriple, spDual]

proc spellAt*(id: int): Spell {.inline.} = spells[id]

# ----------------------------------------------------------------- entities ---

type
  EntityId* = enum
    tTusk, tAshgun, tNighthook, tBurstling, tBorewyrm, tWellseye

  FoeKind* = enum
    fkMelee, fkRanged, fkFly, fkBoom, fkBurrow, fkBoss

  Foe* = object
    id*: EntityId
    kind*: FoeKind
    name*: string
    x*, y*, vx*, vy*: float64
    w*, h*: int
    hp*, maxHp*, dmg*: float64
    cool*, dir*, flash*, fuse*: int
    phase*: float64          ## a per-creature random phase, in radians
    segs*: seq[array[2, float64]]
    dead*: bool

  PickupKind* = enum
    puGold, puHeart, puSpell, puFlask, puChest, puWand

  Pickup* = object
    kind*: PickupKind
    x*, y*, vx*, vy*: float64
    val*: int
    spell*: int
    flask*: int
    wand*: Wand

  Part* = object
    x*, y*, vx*, vy*: float64
    life*, maxLife*: int
    kind*: int               ## 0 dot, 1 boom ring, 2 spark, 3 blood
    rad*: float64
    r*, g*, b*: int

  WorldLight* = object
    x*, y*: float64
    r*: int
    i*: int
    cr*, cg*, cb*: int

  Wand* = object
    name*: string
    slots*: array[8, int8]   ## -1 empty, else a SpellId
    nslots*: int
    castDelay*, recharge*, mana*, manaMax*, regen*: float64
    spread*, speed*: float64
    shuffle*: bool
    spellsPerCast*: int
    delayT*, rechT*, cursor*: int
    wrapped*: bool

  Perk* = enum
    pkSteel, pkGlass, pkCrit, pkBreath, pkTinker, pkGold, pkFireImm, pkToxImm, pkVamp, pkLamp

  PerkSet* = set[Perk]

  Body* = object
    x*, y*, vx*, vy*: float64
    w*, h*: int
    hp*, maxHp*, hover*, maxHover*: float64
    inv*, dir*, wet*, burning*, poison*, toxic*, oiled*, air*, flash*: int
    dead*, onGround*: bool
    perk*: PerkSet
    kills*: int

  GameState* = enum gsPlay, gsDead, gsWin

  SfxKind* = enum
    sfxCast, sfxHit, sfxHurt, sfxGold, sfxPerk, sfxJump, sfxKick, sfxDead, sfxWin, sfxKill, sfxBoom

  ShotParams* = object
    dmgMul*, spdMul*, spread*, homing*, light*: float64
    bounce*, fire*, pierce*, drill*, freeze*, acid*: int
    expl*: float64
    delay*, rech*: float64

  Tpl* = object
    sp*: int
    shot*: ShotParams
    payload*: seq[Tpl]       ## a trigger's nested payload (cards drawn behind it)

  Shot* = object
    x*, y*, vx*, vy*: float64
    life*: int
    dmg*: float64
    col*: array[3, uint8]
    enemy*: bool
    homing*, light*: float64
    bounce*, fire*, expl*, pierce*, drill*, freeze*, acid*: int
    trigger*, timer*: int
    payload*: seq[Tpl]
    flask*: int
    hit*: int

  Holy* = object
    y0*, y1*: int
    seen*: bool

  Run* = object
    gold*, depth*, kills*, frames*, casts*: int
    seed*: uint32
    causeCode*: string
    causeMsg*: string

  Input* = object
    left*, right*, jump*, fire*: bool
    aimX*, aimY*: float64

  Deep* = object
    g*: Grid
    sd*: uint32
    tick*: int
    camY*: float64
    shakeMag*: float64
    flash*: int
    aimX*, aimY*: float64      ## where the delver aims, in screen cells
    player*: Body
    wands*: array[4, Wand]
    curWand*: int
    gift*: seq[int]          ## the spell bag
    foes*: seq[Foe]
    shots*: seq[Shot]
    parts*: seq[Part]
    picks*: seq[Pickup]
    flasks*: seq[int]
    lamps*: seq[WorldLight]
    holy*: array[Sanctums, Holy]
    offer*: array[3, int]    ## perk ids on offer, -1 none
    offering*: bool
    st*: GameState
    kickCD*: int
    run*: Run
    toast*: string
    toastT*: int
    events*: seq[SfxKind]
    light*: seq[uint8]
    lightR*, lightG*, lightB*: seq[uint8]
    fb*: seq[byte]           ## RGBA framebuffer, VW*VH*4

# ----------------------------------------------------------- wand machinery ---

proc makeWand*(name: string; slots: openArray[int8]; nslots: int;
               castDelay = 10.0; recharge = 28.0; manaMax = 120.0; regen = 22.0;
               shuffle = false; spellsPerCast = 1; spread = 0.0; speed = 1.0): Wand =
  result.name = name
  for i in 0 ..< min(nslots, 8): result.slots[i] = slots[i]
  result.nslots = nslots
  result.castDelay = castDelay
  result.recharge = recharge
  result.manaMax = manaMax
  result.mana = manaMax
  result.regen = regen
  result.shuffle = shuffle
  result.spellsPerCast = spellsPerCast
  result.spread = spread
  result.speed = speed

proc spellName*(id: int): string {.inline.} =
  if id < 0 or id >= SpellN: "-" else: spells[id].tag

proc setupWands*(d: var Deep) =
  d.wands = [
    makeWand("MORNINGSTAR", [spSpark.int8, spSpark.int8, spFlameMod.int8, -1'i8], 4,
             castDelay = 8, recharge = 22, manaMax = 130, regen = 28),
    makeWand("PICKAXE", [spBomb.int8, -1'i8], 2,
             castDelay = 6, recharge = 8, manaMax = 90, regen = 12, shuffle = true),
    makeWand("HOLLOW", [-1'i8, -1'i8, -1'i8], 3, castDelay = 12, recharge = 30,
             manaMax = 110, regen = 20),
    makeWand("HOLLOW", [-1'i8, -1'i8, -1'i8, -1'i8], 4, castDelay = 14, recharge = 36,
             manaMax = 150, regen = 24),
  ]
  d.gift = @[spHoming.int, spTriple.int]
  d.curWand = 0

proc randomSpell*(d: var Deep; tier: int): int =
  var pool: seq[int] = @[]
  for s in ProjIds: pool.add ord(s)
  for s in ModIds: pool.add ord(s)
  if tier > 0:
    for s in TrigIds: pool.add ord(s)
    for s in MultiIds: pool.add ord(s)
  pool[rint(d.g.dice, 0, pool.high)]

proc randomWand*(d: var Deep; tier: int): Wand =
  let cap = 3 + min(4, tier)
  let n = rint(d.g.dice, 1, cap)
  var slots: array[8, int8]
  for i in 0 ..< 8: slots[i] = -1
  for i in 0 ..< n: slots[i] = int8(randomSpell(d, tier))
  const wandNames = ["BRIARWAND", "EMBERSWITCH", "FROSTBONE", "WELLLAMP", "RIFT", "NIGHTSONG"]
  let nm = wandNames[rint(d.g.dice, 0, 5)]
  let cd = 8.0 + float64(rint(d.g.dice, 0, 10))
  let rc = 18.0 + float64(rint(d.g.dice, 0, 24))
  let mm = 90.0 + float64(tier * 30) + float64(rint(d.g.dice, 0, 40))
  let rg = 18.0 + float64(tier * 6)
  let sh = chance(d.g.dice, 0.3)
  let spc = (if chance(d.g.dice, 0.15): 2 else: 1)
  let spr = float64(rint(d.g.dice, 0, 8))
  result = makeWand(nm, slots, cap, castDelay = cd, recharge = rc, manaMax = mm,
                    regen = rg, shuffle = sh, spellsPerCast = spc, spread = spr)

# ---------------------------------------------------------------- the world ---

proc solidMatFor(sd: uint32; b, x, y: int): uint8 =
  ## One recipe per stratum; the thresholds are the original's exactly.
  let n = n2(sd, float64(x) * 0.11, float64(y) * 0.09)
  if b == 0:
    if n > 0.72: return MatCoal
    if n2(sd, float64(x) * 0.2, float64(y) * 0.2) > 0.84: return MatGold
    if n < 0.38: return MatDirt
    if n2(sd, float64(x) * 0.07, float64(y) * 0.13) > 0.78: return MatMoss
    return MatRock
  if b == 1:
    if n > 0.55: return MatCoal
    if n2(sd, float64(x) * 0.16, float64(y) * 0.16) > 0.80: return MatOil
    if n < 0.28: return MatDirt
    return MatRock
  if b == 2:
    if n > 0.7: return MatFungus
    if n2(sd, float64(x) * 0.18, float64(y) * 0.1) > 0.82: return MatCrystal
    if n < 0.35: return MatDirt
    if n2(sd, float64(x) * 0.09, float64(y) * 0.2) > 0.76: return MatSlime
    return MatRock
  if b == 3:
    if n > 0.6: return MatSnowrock
    if n < 0.32: return MatIce
    if n2(sd, float64(x) * 0.14, float64(y) * 0.14) > 0.7: return MatSnow
    return MatRock
  if n > 0.7: return MatLava
  if n < 0.3: return MatStone
  if n2(sd, float64(x) * 0.1, float64(y) * 0.1) > 0.8: return MatMetal
  MatRock

proc fillDisk(d: var Deep; cx, cy, r: float64; m: uint8; lf = 0) =
  let r2 = r * r
  var yy = -r
  while yy <= r:
    var xx = -r
    while xx <= r:
      if xx * xx + yy * yy <= r2: d.g.put(int(cx + xx), int(cy + yy), m, lf)
      xx += 1.0
    yy += 1.0

proc fillRect(d: var Deep; x0, y0, x1, y1: int; m: uint8) =
  for y in y0 .. y1:
    for x in x0 .. x1: d.g.put(x, y, m)

proc carve(d: var Deep; x0, y0, x1, y1: int) =
  for y in y0 .. y1:
    for x in x0 .. x1:
      let m = d.g.at(x, y)
      if m != MatDense and m != MatBrick: d.g.put(x, y, MatAir)

proc spawnFoe*(d: var Deep; id: EntityId; x, y: float64)

proc generateWorld*(d: var Deep; sd: uint32) =
  ## Caves from a thresholded fBm field plus three analytic cuts (a winding shaft,
  ## galleries every 47 rows, closed edges) — no worms, no walkers. Then the seven
  ## fluid disks per stratum, the pit props and mushrooms, the torches, four
  ## sanctuaries, the boss arena, the creature and pickup placements.
  d.sd = sd
  d.g = newGrid(WW, WH)
  d.g.dice = seedDice(sd)
  d.lamps = @[]
  d.foes = @[]
  d.shots = @[]
  d.parts = @[]
  d.picks = @[]
  d.flasks = @[]
  for i in 0 ..< Sanctums: d.holy[i] = Holy()

  for y in 0 ..< WH:
    let b = layerAt(y)
    for x in 0 ..< WW:
      if x < 4 or x > WW - 5 or y > WH - 6:
        d.g.put(x, y, MatDense)
        continue
      if y < 18: continue
      if b >= 10:
        d.g.put(x, y, MatBrick)
        continue
      if b < 0:
        let ground = float64(SurfY - 8) + sin(float64(x) * 0.04) * 4.0 +
                     n2(sd, float64(x) * 0.08, 2.0) * 6.0
        if float64(y) > ground:
          d.g.put(x, y, if float64(y) > ground + 5.0: MatRock
                         elif chance(d.g.dice, 0.3): MatGrass else: MatDirt)
        continue
      let nx = float64(x) * 0.028
      let ny = float64(y) * 0.02
      let cave = fbm(sd, nx, ny) + sin(float64(x) * 0.09 + float64(y) * 0.017) * 0.12 +
                 sin(float64(x + y) * 0.011) * 0.08
      let edge = (if x < 14: float64(14 - x) / 14.0
                  elif x > WW - 15: float64(x - (WW - 15)) / 14.0 else: 0.0)
      var solid = cave < 0.46 + edge * 0.35
      let shaftX = float64(WW) * 0.5 + sin(float64(y) * 0.03) * 28.0
      let shaftW = 10.0 + n2(sd, float64(y) * 0.02, 4.0) * 8.0
      if abs(float64(x) - shaftX) < shaftW and y mod LayerPeriod < BandH - 8: solid = false
      if y mod 47 < 3 and abs(x - WW div 2) < 40: solid = false
      if solid:
        d.g.put(x, y, solidMatFor(sd, b, x, y))
      elif chance(d.g.dice, 0.012):
        case b
        of 0: d.g.put(x, y, if chance(d.g.dice, 0.5): MatWater else: MatSand)
        of 1: d.g.put(x, y, if chance(d.g.dice, 0.55): MatOil else: MatGunp)
        of 2: d.g.put(x, y, if chance(d.g.dice, 0.5): MatToxic else: MatSlime)
        of 3: d.g.put(x, y, if chance(d.g.dice, 0.6): MatWater else: MatSnow)
        else: d.g.put(x, y, if chance(d.g.dice, 0.7): MatLava else: MatAsh)

  for i in 0 ..< 5:
    let y0 = SurfY + i * LayerPeriod
    let y1 = y0 + BandH
    for k in 0 ..< 7:
      let cx = rint(d.g.dice, 30, WW - 30)
      let cy = rint(d.g.dice, y0 + 20, y1 - 20)
      let r = rint(d.g.dice, 8, 18)
      d.carve(cx - r, cy - r, cx + r, cy + r)
      if i == 0 and chance(d.g.dice, 0.5): d.fillDisk(float64(cx), float64(cy + r - 2), float64(r) * 0.6, MatWater)
      if i == 1 and chance(d.g.dice, 0.5): d.fillDisk(float64(cx), float64(cy + r - 2), float64(r) * 0.5, MatOil)
      if i == 2 and chance(d.g.dice, 0.45): d.fillDisk(float64(cx), float64(cy + r - 2), float64(r) * 0.5, MatToxic)
      if i == 3 and chance(d.g.dice, 0.5): d.fillDisk(float64(cx), float64(cy + r - 2), float64(r) * 0.55, MatWater)
      if i == 4 and chance(d.g.dice, 0.6): d.fillDisk(float64(cx), float64(cy + r - 2), float64(r) * 0.7, MatLava)
    if i == 0:
      var bx = 40
      while bx < WW - 40:
        let by = y0 + rint(d.g.dice, 30, BandH - 40)
        for yy in 0 ..< 22: d.g.put(bx, by + yy, MatWood)
        for xx in -6 .. 6: d.g.put(bx + xx, by, MatWood)
        bx += 28
    if i == 2:
      for k in 0 ..< 18:
        let mx = rint(d.g.dice, 20, WW - 20)
        let my = rint(d.g.dice, y0 + 10, y1 - 10)
        if d.g.at(mx, my + 1) != MatAir and d.g.at(mx, my) == MatAir:
          d.g.put(mx, my, MatFungus)
          d.g.put(mx, my - 1, MatFungus)
          if chance(d.g.dice, 0.5): d.g.put(mx, my - 2, MatCrystal)
          d.lamps.add WorldLight(x: float64(mx), y: float64(my - 1), r: 28, i: 140,
                                 cr: 200, cg: 70, cb: 210)
    for t in 0 ..< 10:
      let tx = rint(d.g.dice, 16, WW - 16)
      let ty = rint(d.g.dice, y0 + 12, y1 - 12)
      if d.g.at(tx, ty) == MatAir and isSolid(d.g.at(tx, ty + 1)):
        d.g.put(tx, ty, MatWood)
        d.g.put(tx, ty - 1, MatFire, 80)
        d.lamps.add WorldLight(x: float64(tx), y: float64(ty - 1), r: 42, i: 190,
                               cr: 255, cg: 160, cb: 50)

  for i in 0 ..< Sanctums:
    let y0 = SurfY + (i + 1) * BandH + i * HoldH
    let y1 = y0 + HoldH
    d.holy[i] = Holy(y0: y0, y1: y1, seen: false)
    d.fillRect(0, y0, WW - 1, y1, MatBrick)
    d.carve(28, y0 + 6, WW - 29, y1 - 3)
    for x in 28 ..< WW - 28:
      d.g.put(x, y0 + 5, MatBrick)
      d.g.put(x, y1 - 2, MatBrick)
      if (x + i * 3) mod 7 == 0: d.g.put(x, y0 + 4, MatGold)
    d.fillRect(36, y1 - 10, 70, y1 - 3, MatWater)
    d.fillRect(WW - 71, y1 - 10, WW - 37, y1 - 3, MatWater)
    d.fillRect(WW div 2 - 16, y1 - 8, WW div 2 + 16, y1 - 4, MatBrick)
    d.lamps.add WorldLight(x: 50.0, y: float64(y0 + 14), r: 50, i: 160, cr: 140, cg: 200, cb: 255)
    d.lamps.add WorldLight(x: float64(WW - 50), y: float64(y0 + 14), r: 50, i: 160,
                           cr: 140, cg: 200, cb: 255)
    d.lamps.add WorldLight(x: float64(WW div 2), y: float64(y0 + 16), r: 46, i: 180,
                           cr: 255, cg: 210, cb: 120)
    d.picks.add Pickup(kind: puHeart, x: float64(WW div 2 - 22), y: float64(y0 + 20), val: 0)

  d.carve(WW div 2 - 28, 16, WW div 2 + 28, SurfY + 36)
  for x in WW div 2 - 30 ..< WW div 2 + 30: d.g.put(x, SurfY + 36, MatDirt)
  for y in 20 ..< SurfY: d.g.put(WW div 2, y, MatAir)

  d.carve(40, WH - 90, WW - 40, WH - 12)
  d.fillRect(50, WH - 18, WW - 50, WH - 8, MatLava)
  d.spawnFoe(tWellseye, float64(WW div 2), float64(WH - 70))

  for i in 0 ..< 5:
    let y0 = SurfY + i * LayerPeriod + 40
    let y1 = y0 + BandH - 50
    let n = 5 + i * 3
    for k in 0 ..< n:
      let x = rint(d.g.dice, 24, WW - 24)
      let y = rint(d.g.dice, y0, y1)
      if d.g.at(x, y) != MatAir: continue
      let r = roll(d.g.dice)
      var t = tTusk
      if r < 0.18: t = tBurstling
      elif r < 0.4: t = tNighthook
      elif r < 0.62: t = tAshgun
      elif r < 0.74 and i >= 1: t = tBorewyrm
      d.spawnFoe(t, float64(x), float64(y))
    for k in 0 ..< 5:
      let x = rint(d.g.dice, 24, WW - 24)
      let y = rint(d.g.dice, y0, y1)
      if d.g.at(x, y) != MatAir: continue
      let t = roll(d.g.dice)
      if t < 0.45:
        d.picks.add Pickup(kind: puGold, x: float64(x), y: float64(y),
                           val: rint(d.g.dice, 4, 16))
      elif t < 0.65:
        d.picks.add Pickup(kind: puHeart, x: float64(x), y: float64(y), val: 25)
      elif t < 0.82:
        d.picks.add Pickup(kind: puSpell, x: float64(x), y: float64(y),
                           spell: randomSpell(d, i))
      elif t < 0.93:
        const flaskMats = [MatWater, MatOil, MatAcid, MatBlood, MatToxic]
        d.picks.add Pickup(kind: puFlask, x: float64(x), y: float64(y),
                           flask: int(flaskMats[rint(d.g.dice, 0, 4)]))
      else:
        d.picks.add Pickup(kind: puChest, x: float64(x), y: float64(y),
                           val: rint(d.g.dice, 12, 40))
    if chance(d.g.dice, 0.85):
      let x = rint(d.g.dice, 40, WW - 40)
      let y = rint(d.g.dice, y0 + 20, y1 - 20)
      if d.g.at(x, y) == MatAir:
        d.picks.add Pickup(kind: puWand, x: float64(x), y: float64(y),
                           wand: randomWand(d, i + 1))

  d.spawnFoe(tTusk, float64(WW div 2 + 18), float64(SurfY + 28))

  d.player = Body(x: float64(WW div 2), y: float64(SurfY + 30), vx: 0, vy: 0, w: 6, h: 10,
                  hp: 100, maxHp: 100, hover: 100, maxHover: 100, inv: 0, dir: 1,
                  wet: 0, burning: 0, poison: 0, toxic: 0, oiled: 0, air: 90,
                  dead: false, perk: {}, kills: 0, onGround: false, flash: 0)
  d.run = Run(gold: 0, depth: 0, kills: 0, frames: 0, casts: 0, seed: sd,
              causeCode: "", causeMsg: "")
  d.st = gsPlay
  d.camY = 0
  d.tick = 0
  d.shakeMag = 0.0
  d.aimX = float64(VW) * 0.7
  d.aimY = float64(VH) * 0.45
  d.offering = false
  d.offer = [-1, -1, -1]
  for i in 0 ..< Sanctums: d.holy[i].seen = false

# ------------------------------------------------------- collision & bodies ---

proc solidAtRect*(d: Deep; x, y: float64; w, h: int): bool =
  let l = int(floor(x - float64(w) / 2.0))
  let r = int(floor(x + float64(w) / 2.0))
  let t = int(floor(y - float64(h) / 2.0))
  let b = int(floor(y + float64(h) / 2.0))
  for yy in t .. b:
    for xx in l .. r:
      if isSolid(d.g.at(xx, yy)): return true
  false

proc moveBody*(d: var Deep; o: var Body; dx, dy: float64) =
  ## Axis-separated AABB against the cells: a wall stops you and kills the speed.
  if dx != 0:
    let nx = o.x + dx
    if not d.solidAtRect(nx, o.y, o.w, o.h): o.x = nx
    else: o.vx *= -0.1
  if dy != 0:
    let ny = o.y + dy
    if not d.solidAtRect(o.x, ny, o.w, o.h): o.y = ny
    else:
      if dy > 0: o.onGround = true
      o.vy = 0
  o.x = max(6.0, min(float64(WW - 6), o.x))
  o.y = max(8.0, min(float64(WH - 8), o.y))

# ------------------------------------------------------------- the automaton ---

proc explode*(d: var Deep; x, y: int; rad: int; dmg, energyIn: float64)

proc reactAt*(d: var Deep; x, y: int; m: uint8): bool =
  ## The alchemy: four neighbours, right/left/down/up, with the original's
  ## probabilities — and, crucially, its control flow: some reactions `return false`,
  ## which ABANDONS the rest of the neighbour scan (so the cell keeps its own turn),
  ## while others barely touch it and the scan continues.
  const nx = [1, -1, 0, 0]
  const ny = [0, 0, 1, -1]
  for k in 0 ..< 4:
    let ax = x + nx[k]
    let ay = y + ny[k]
    let n = d.g.at(ax, ay)
    if m == MatLava:
      if n == MatWater or n == MatToxic:
        d.g.put(x, y, MatStone); d.g.put(ax, ay, MatSteam, 50); return true
      if n == MatBlood:
        d.g.put(x, y, MatStone); d.g.put(ax, ay, MatSteam, 40); return true
      if n == MatOil or n == MatSlime:
        d.g.put(ax, ay, MatFire, 40); return false
      if int(mats[n].flamm) > 40 and chance(d.g.dice, 0.08):
        d.g.put(ax, ay, MatFire, 30); return false
      if n == MatIce or n == MatSnow:
        d.g.put(ax, ay, MatSteam, 40); return false
    if m == MatFire:
      if n == MatWater or n == MatBlood:
        d.g.put(x, y, MatSteam, 40); return true
      if n == MatIce:
        d.g.put(ax, ay, MatWater); return false
      if n == MatSnow:
        d.g.put(ax, ay, MatSteam, 30); return false
      if n == MatGunp:
        d.explode(ax, ay, 12, 28.0, 14000.0); return true
      if int(mats[n].flamm) > 0 and chance(d.g.dice, float64(mats[n].flamm) / 900.0):
        d.g.put(ax, ay, MatFire, 20 + (int(mats[n].flamm) shr 2))
        if n == MatOil:
          d.g.put(x, y + (if chance(d.g.dice, 0.5): 0 else: -1), MatFgas, 30)
      if n == MatWood or n == MatWoodp or n == MatCoal or n == MatMoss or
         n == MatVine or n == MatGrass or n == MatFungus:
        if chance(d.g.dice, 0.06): d.g.put(ax, ay, MatFire, 28)
    if m == MatAcid:
      if n != MatDense and n != MatBrick and n != MatAir and n != MatAcid and n != MatPgas:
        let rate = (if mats[n].kind == mkStatic: (if mats[n].hard >= 12: 0.05 else: 0.55)
                    elif mats[n].kind == mkPowder: 0.45 else: 0.12)
        if chance(d.g.dice, rate):
          d.g.put(ax, ay, (if chance(d.g.dice, 0.35): MatPgas else: MatAir), 18)
      if n == MatMetal and chance(d.g.dice, 0.08): d.g.put(ax, ay, MatRust)
    if m == MatWater:
      if n == MatToxic and chance(d.g.dice, 0.08): d.g.put(ax, ay, MatWater)
      if n == MatFire: d.g.put(ax, ay, MatSteam, 35)
      if n == MatLava:
        d.g.put(ax, ay, MatStone); d.g.put(x, y, MatSteam, 50); return true
    if m == MatBlood and n == MatPgas and chance(d.g.dice, 0.1):
      d.g.put(ax, ay, MatSlime)
  false

proc automaton*(d: var Deep; y0In, y1In: int) =
  ## One tick of the falling-sand world. Rows bottom-up so a falling cell is not
  ## re-simulated by the row above; direction alternates per row so nothing drifts;
  ## a stamp says "this cell already moved"; gases get a second, top-down pass.
  if d.g.cell.len == 0: return
  d.g.stamp = (if d.g.stamp == 255'u8: 1'u8 else: d.g.stamp + 1'u8)
  let y0 = max(1, min(WH - 2, y0In))
  let y1 = max(2, min(WH - 2, y1In))

  var y = y1
  while y >= y0:
    let ltr = ((y + d.tick) and 1) == 0
    for k in 0 ..< WW:
      let x = (if ltr: k else: WW - 1 - k)
      let i = y * WW + x
      if d.g.mark[i] == d.g.stamp: continue
      let m = d.g.cell[i]
      if m == MatAir or m == MatDense or m == MatBrick: continue
      let t = mats[m].kind
      if t == mkGas: continue
      if d.reactAt(x, y, m): continue
      if t == mkFire:
        var lf = (if d.g.life[i] > 0: int(d.g.life[i]) else: 18) - 1
        if d.g.at(x, y + 1) == MatWater or d.g.at(x, y - 1) == MatWater or
           d.g.at(x + 1, y) == MatWater or d.g.at(x - 1, y) == MatWater:
          d.g.put(x, y, MatSteam, 40); continue
        if lf <= 0:
          d.g.put(x, y, (if chance(d.g.dice, 0.65): MatSmoke else: MatAsh), 40); continue
        d.g.life[i] = uint8(lf)
        if chance(d.g.dice, 0.12) and d.g.at(x, y - 1) == MatAir:
          d.g.put(x, y - 1, MatSmoke, 24)
        if chance(d.g.dice, 0.04) and d.g.at(x, y + 1) == MatAir:
          d.g.put(x, y + 1, MatEmber, 12)
        if chance(d.g.dice, 0.3):
          let sgn = (if chance(d.g.dice, 0.5): -1 else: 1)
          discard d.g.shiftCell(x, y, x + sgn, y - 1)
        continue
      if t == mkPowder:
        if d.g.shiftCell(x, y, x, y + 1): continue
        let s = (if chance(d.g.dice, 0.5): -1 else: 1)
        if d.g.shiftCell(x, y, x + s, y + 1): continue
        if d.g.shiftCell(x, y, x - s, y + 1): continue
        continue
      if t == mkLiquid:
        if d.g.shiftCell(x, y, x, y + 1): continue
        let s = (if chance(d.g.dice, 0.5): -1 else: 1)
        if d.g.shiftCell(x, y, x + s, y + 1): continue
        if d.g.shiftCell(x, y, x - s, y + 1): continue
        if d.g.shiftCell(x, y, x + s, y): continue
        if d.g.shiftCell(x, y, x - s, y): continue
        continue
      if m == MatIce and chance(d.g.dice, 0.002):
        if d.g.at(x, y + 1) == MatLava or d.g.at(x, y - 1) == MatFire:
          d.g.put(x, y, MatWater)
    y -= 1

  var yy = y0
  while yy <= y1:
    let ltr = ((yy + d.tick) and 1) == 0
    for k in 0 ..< WW:
      let x = (if ltr: k else: WW - 1 - k)
      let i = yy * WW + x
      if d.g.mark[i] == d.g.stamp: continue
      let m = d.g.cell[i]
      if mats[m].kind != mkGas: continue
      var lf = int(d.g.life[i])
      if lf > 0:
        lf -= 1
        d.g.life[i] = uint8(lf)
        if lf == 0:
          if m == MatSteam and chance(d.g.dice, 0.45): d.g.put(x, yy, MatWater)
          else: d.g.put(x, yy, MatAir)
          continue
      elif chance(d.g.dice, 0.01):
        d.g.put(x, yy, (if m == MatSteam: MatWater else: MatAir))
        continue
      if m == MatFgas and (d.g.at(x, yy + 1) == MatFire or d.g.at(x, yy - 1) == MatFire) and
         chance(d.g.dice, 0.2):
        d.g.put(x, yy, MatFire, 16); continue
      if d.g.shiftCell(x, yy, x, yy - 1): continue
      let s = (if chance(d.g.dice, 0.5): -1 else: 1)
      if d.g.shiftCell(x, yy, x + s, yy - 1): continue
      if d.g.shiftCell(x, yy, x - s, yy - 1): continue
      if d.g.shiftCell(x, yy, x + s, yy): continue
      if d.g.shiftCell(x, yy, x - s, yy): continue
    yy += 1

proc bandLo*(d: Deep): int = max(1, min(WH - 2, int(d.camY) - 24))
proc bandHi*(d: Deep): int = max(2, min(WH - 2, int(d.camY) + VH + 28))

proc automaton*(d: var Deep) =
  ## The visible band only, like the original: off-screen chemistry sleeps.
  d.automaton(d.bandLo, d.bandHi)

# ---------------------------------------------------------------- creatures ---

type FoeDef* = object
  id*: EntityId
  name*: string
  kind*: FoeKind
  hp*: int
  w*, h*: int
  dmg*: int

## Six creatures. Our own English names; the hit points, sizes, damage and
## behaviour thresholds are the original's numbers.
const foeDefs: array[6, FoeDef] = [
  FoeDef(id: tTusk, name: "GNAWLER", kind: fkMelee, hp: 28, w: 7, h: 9, dmg: 8),
  FoeDef(id: tAshgun, name: "CINDER GUN", kind: fkRanged, hp: 36, w: 7, h: 9, dmg: 10),
  FoeDef(id: tNighthook, name: "NIGHTCLAW", kind: fkFly, hp: 18, w: 8, h: 6, dmg: 6),
  FoeDef(id: tBurstling, name: "BLASTCAP", kind: fkBoom, hp: 22, w: 6, h: 6, dmg: 28),
  FoeDef(id: tBorewyrm, name: "BURROWER", kind: fkBurrow, hp: 54, w: 9, h: 7, dmg: 12),
  FoeDef(id: tWellseye, name: "WELL EYE", kind: fkBoss, hp: 720, w: 16, h: 16, dmg: 16),
]

proc defOf*(id: EntityId): FoeDef = foeDefs[ord(id)]

proc spawnFoe*(d: var Deep; id: EntityId; x, y: float64) =
  let df = foeDefs[ord(id)]
  var e = Foe(
    id: id, kind: df.kind, name: df.name, x: x, y: y, vx: 0, vy: 0, w: df.w, h: df.h,
    hp: float64(df.hp), maxHp: float64(df.hp), dmg: float64(df.dmg),
    cool: rint(d.g.dice, 20, 80), dir: (if chance(d.g.dice, 0.5): -1 else: 1),
    phase: roll(d.g.dice) * 12.0, dead: false, flash: 0, fuse: 0)
  if id == tBorewyrm:
    for i in 0 ..< 6:
      e.segs.add [x - float64(i * 4), y]
  var yy = y
  if d.g.at(int(x), int(y)) != MatAir:
    var k = 0
    while k < 40 and d.g.at(int(x), int(yy)) != MatAir:
      yy -= 1.0
      inc k
    e.y = yy
  d.foes.add e

# -------------------------------------------------------------------- damage ---

proc die*(d: var Deep; code, msg: string)

proc hurt*(d: var Deep; dmgIn: float64; code, msg: string) =
  ## One damage event. Damage-over-time ignores the invulnerability window; a hit
  ## spends it and shakes the screen.
  if d.player.dead: return
  if pkFireImm in d.player.perk and (code == "burn" or code == "lava"): return
  if pkToxImm in d.player.perk and (code == "poison" or code == "toxic" or code == "acid"): return
  var dd = dmgIn
  if pkSteel in d.player.perk: dd *= 0.5
  let dot = code == "burn" or code == "poison" or code == "toxic" or code == "drown" or code == "acid"
  if not dot and d.player.inv > 0: return
  d.player.hp -= dd
  d.run.causeCode = code
  d.run.causeMsg = msg
  if not dot:
    d.player.inv = 26
    d.player.flash = 6
    d.flash = 5
    d.shakeMag = max(d.shakeMag, 3.5)
    d.events.add sfxHurt
    for i in 0 ..< 5:
      d.parts.add Part(x: d.player.x, y: d.player.y,
                       vx: (roll(d.g.dice) - 0.5) * 2.0, vy: -roll(d.g.dice) * 2.0,
                       life: 12, maxLife: 12, kind: 3, r: 200, g: 40, b: 50)
  if d.player.hp < 0.05: d.die(code, msg)

proc die*(d: var Deep; code, msg: string) =
  if d.player.dead: return
  d.player.dead = true
  d.player.hp = 0
  d.st = gsDead
  d.run.causeCode = code
  d.run.causeMsg = msg
  d.events.add sfxDead

proc causeTitle*(code: string): string =
  ## Our own English epitaphs; the codes are the original's.
  case code
  of "burn", "lava": "BURNED"
  of "drown": "DROWNED"
  of "crush": "CRUSHED"
  of "poison", "toxic": "POISONED"
  of "acid": "DISSOLVED"
  of "explode": "BLASTED"
  of "kill": "SLAIN"
  else: "DEAD"

# ------------------------------------------------------------------- blasts ---

proc hurtFoe*(d: var Deep; e: var Foe; dmg: float64)

proc killFoe*(d: var Deep; e: var Foe) =
  if e.dead: return
  e.dead = true
  inc d.player.kills
  inc d.run.kills
  d.events.add sfxKill
  var n = (if e.id == tWellseye: 180.0
           else: float64(rint(d.g.dice, 3, 14)) * (if pkGold in d.player.perk: 1.5 else: 1.0))
  d.picks.add Pickup(kind: puGold, x: e.x, y: e.y, vx: roll(d.g.dice) - 0.5, vy: -1.4,
                     val: int(n))
  for i in 0 ..< 8:
    let bx = int(e.x) + rint(d.g.dice, -3, 3)
    let by = int(e.y) + rint(d.g.dice, -2, 4)
    if d.g.at(bx, by) == MatAir: d.g.put(bx, by, MatBlood)
    d.parts.add Part(x: float64(bx), y: float64(by),
                     vx: (roll(d.g.dice) - 0.5) * 2.0, vy: -roll(d.g.dice) * 2.0,
                     life: 16, maxLife: 16, kind: 3, r: 170, g: 28, b: 40)
  if pkVamp in d.player.perk: d.player.hp = min(d.player.maxHp, d.player.hp + 8)
  if e.id == tBurstling: d.explode(int(e.x), int(e.y), 14, 22.0, 12000.0)
  if e.id == tWellseye:
    d.st = gsWin
    d.events.add sfxWin

proc hurtFoe*(d: var Deep; e: var Foe; dmg: float64) =
  if e.dead: return
  e.hp -= dmg
  e.flash = 4
  if e.hp <= 0: d.killFoe(e)

proc explode*(d: var Deep; x, y: int; rad: int; dmg, energyIn: float64) =
  ## Twenty rays against a hardness budget: a blast is eaten by the rock it meets,
  ## not a clean disc.
  d.shakeMag = max(d.shakeMag, min(12.0, float64(rad) * 0.45))
  d.events.add sfxBoom
  let energy = (if energyIn > 0: energyIn else: float64(rad * 9000))
  for a in 0 ..< 20:
    var e = energy
    let ang = float64(a) * PI * 2.0 / 20.0 + roll(d.g.dice) * 0.1
    let dx = cos(ang)
    let dy = sin(ang)
    for t in 0 .. rad:
      let gx = int(float64(x) + dx * float64(t))
      let gy = int(float64(y) + dy * float64(t))
      let m = d.g.at(gx, gy)
      if m == MatDense: break
      e -= float64(int(mats[m].hard) * 700 + 180)
      if m == MatBrick: e -= 8000.0
      if e <= 0: break
      if m != MatAir and m != MatBrick and m != MatDense:
        if int(mats[m].flamm) > 40 and chance(d.g.dice, 0.35): d.g.put(gx, gy, MatFire, 18)
        elif m == MatWater: d.g.put(gx, gy, MatSteam, 30)
        else:
          let hot = float64(t) < float64(rad) * 0.35 and chance(d.g.dice, 0.2)
          d.g.put(gx, gy, (if hot: MatFire else: MatAir), 12)
      elif m == MatAir and t < 3 and chance(d.g.dice, 0.3):
        d.g.put(gx, gy, MatFire, 10)
  d.parts.add Part(x: float64(x), y: float64(y), life: 14, maxLife: 14, kind: 1,
                   rad: float64(rad), r: 255, g: 180, b: 60)
  for i in 0 ..< 10:
    d.parts.add Part(x: float64(x), y: float64(y),
                     vx: (roll(d.g.dice) - 0.5) * 4.0, vy: (roll(d.g.dice) - 0.5) * 4.0 - 1.0,
                     life: 12 + rint(d.g.dice, 0, 10), maxLife: 22, kind: 2,
                     r: 255, g: 160 + rint(d.g.dice, 0, 60), b: 40)
  for i in 0 ..< d.foes.len:
    if d.foes[i].dead: continue
    let dd = sqrt((d.foes[i].x - float64(x)) * (d.foes[i].x - float64(x)) +
                  (d.foes[i].y - float64(y)) * (d.foes[i].y - float64(y)))
    if dd < float64(rad + 8):
      d.hurtFoe(d.foes[i], dmg * (1.0 - dd / float64(rad + 8)))
  if not d.player.dead:
    let dd = sqrt((d.player.x - float64(x)) * (d.player.x - float64(x)) +
                  (d.player.y - float64(y)) * (d.player.y - float64(y)))
    if dd < float64(rad + 6):
      d.hurt(10.0 + dmg * 0.15 * (1.0 - dd / float64(rad + 6)), "explode",
             "BLASTED · the shockwave tore you apart")

# -------------------------------------------------------------------- wands ---

proc baseShot*(w: Wand): ShotParams =
  ShotParams(dmgMul: 1.0, spdMul: (if w.speed > 0: w.speed else: 1.0), spread: w.spread,
             homing: 0, bounce: 0, fire: 0, expl: 0, light: 1.0, pierce: 0, drill: 0,
             freeze: 0, acid: 0, delay: 0, rech: 0)

proc drawOne*(w: var Wand): int =
  ## Takes the next non-empty card, wrapping at the end and remembering it wrapped.
  var guard = 0
  let n = w.nslots
  if n == 0: return -1
  while guard < n + 2:
    inc guard
    if w.cursor >= n:
      w.wrapped = true
      w.cursor = 0
    let id = w.slots[w.cursor]
    inc w.cursor
    if id >= 0: return int(id)
  -1

proc applyMod(shot: var ShotParams; sp: Spell) =
  if sp.homing > 0: shot.homing += sp.homing
  if sp.fire > 0: shot.fire = 1
  if sp.bounce > 0: shot.bounce = 1
  if sp.dmgMul > 0: shot.dmgMul *= sp.dmgMul
  if sp.spdMul > 0: shot.spdMul *= sp.spdMul
  if sp.lightAdd > 0: shot.light += sp.lightAdd
  if sp.expl > 0: shot.expl += float64(sp.expl)
  if sp.spr > 0: shot.spread += float64(sp.spr)

proc spawnFromTemplate(d: var Deep; tpl: Tpl; x, y, dirX, dirY: float64; extraSpr: float64) =
  let sp = spells[tpl.sp]
  let shot = tpl.shot
  let spr = (shot.spread + float64(sp.spr) + extraSpr) * PI / 180.0
  let a = (roll(d.g.dice) - 0.5) * 2.0 * spr
  let c = cos(a)
  let q = sin(a)
  let dx = dirX * c - dirY * q
  let dy = dirX * q + dirY * c
  let spd = (if sp.spd > 0: sp.spd else: 3.0) * (if shot.spdMul > 0: shot.spdMul else: 1.0)
  var p = Shot(x: x, y: y, vx: dx * spd, vy: dy * spd,
               life: (if sp.drill > 0: 18 else: 90 + (if sp.expl > 0: 20 else: 0)),
               dmg: (if sp.dmg > 0: sp.dmg else: 8.0) * (if shot.dmgMul > 0: shot.dmgMul else: 1.0),
               col: sp.col, enemy: false,
               homing: shot.homing,
               bounce: max(shot.bounce, sp.bounce),
               fire: max(shot.fire, sp.fire),
               expl: int(shot.expl) + sp.expl,
               light: shot.light + sp.light,
               pierce: sp.pierce,
               drill: max(sp.drill, shot.drill),
               freeze: sp.freeze, acid: sp.acid,
               trigger: sp.trigger, timer: sp.timer,
               payload: tpl.payload, hit: 0, flask: -1)
  if pkCrit in d.player.perk and chance(d.g.dice, 0.25): p.dmg *= 2.0
  d.shots.add p

proc collectTemplates(d: var Deep; w: var Wand; shot: var ShotParams; outp: var seq[Tpl];
                      budget: var int) =
  dec budget
  if budget < 0: return
  let id = drawOne(w)
  if id < 0: return
  let sp = spells[id]
  if w.mana < sp.mana: return
  w.mana -= sp.mana
  shot.delay += sp.delay
  shot.rech += sp.rec
  if sp.kind == skMod:
    applyMod(shot, sp)
    d.collectTemplates(w, shot, outp, budget)
    return
  if sp.kind == skMulti:
    for i in 0 ..< sp.count:
      var cp = shot
      d.collectTemplates(w, cp, outp, budget)
    return
  if sp.kind == skProj:
    outp.add Tpl(sp: id, shot: shot)

proc evalDraw(d: var Deep; w: var Wand; shot: var ShotParams; dirX, dirY, ox, oy: float64): int =
  ## One draw left to right from the cursor. A modifier folds in and continues; a
  ## multiplier recurses once per branch with the aim rotated; a projectile spawns.
  let id = drawOne(w)
  if id < 0: return 0
  let sp = spells[id]
  if w.mana < sp.mana: return 0
  w.mana -= sp.mana
  shot.delay += sp.delay
  shot.rech += sp.rec
  if sp.kind == skMod:
    applyMod(shot, sp)
    return d.evalDraw(w, shot, dirX, dirY, ox, oy)
  if sp.kind == skMulti:
    var n = 0
    for i in 0 ..< sp.count:
      let ang = (float64(i) - float64(sp.count - 1) / 2.0) * float64(sp.sprAdd) * PI / 180.0
      let c = cos(ang)
      let q = sin(ang)
      let ndx = dirX * c - dirY * q
      let ndy = dirX * q + dirY * c
      var cp = shot
      n += d.evalDraw(w, cp, ndx, ndy, ox, oy)
    return n
  if sp.kind == skProj:
    var payload: seq[Tpl] = @[]
    if sp.trigger != 0:
      var budget = 12
      for i in 0 ..< max(1, sp.draws):
        var cp = shot
        d.collectTemplates(w, cp, payload, budget)
    d.spawnFromTemplate(Tpl(sp: id, shot: shot, payload: payload), ox, oy, dirX, dirY, 0.0)
    return 1
  0

proc aimVec*(d: Deep; inp: Input): array[2, float64] =
  var ax = inp.aimX - d.player.x
  var ay = inp.aimY + d.camY - d.player.y
  let l = sqrt(ax * ax + ay * ay)
  if l <= 0.0: return [float64(d.player.dir), 0.0]
  ax /= l
  ay /= l
  [ax, ay]

proc tryCast*(d: var Deep; inp: Input): int =
  ## The cast gate: not dead, not paused, no recharge or delay pending. Then the
  ## deck is evaluated; if the deck wrapped or ran to its end the wand recharges and
  ## a shuffling wand re-shuffles its non-empty cards.
  if d.st != gsPlay or d.offering or d.player.dead: return 0
  if d.curWand < 0 or d.curWand > 3: return 0
  if d.wands[d.curWand].delayT > 0 or d.wands[d.curWand].rechT > 0: return 0
  let av = d.aimVec(inp)
  var shot = baseShot(d.wands[d.curWand])
  d.wands[d.curWand].wrapped = false
  var produced = 0
  for n in 0 ..< max(1, d.wands[d.curWand].spellsPerCast):
    produced += d.evalDraw(d.wands[d.curWand], shot, av[0], av[1],
                           d.player.x + av[0] * 8.0, d.player.y + av[1] * 6.0)
  if produced == 0 and d.wands[d.curWand].mana < 3.0:
    d.toast = "not enough mana"
    d.toastT = 90
    return 0
  inc d.run.casts
  d.wands[d.curWand].delayT = max(2, int(d.wands[d.curWand].castDelay + shot.delay))
  if d.wands[d.curWand].wrapped or d.wands[d.curWand].cursor >= d.wands[d.curWand].nslots:
    d.wands[d.curWand].rechT = max(0, int(d.wands[d.curWand].recharge + shot.rech))
    d.wands[d.curWand].cursor = 0
    d.wands[d.curWand].wrapped = false
    if d.wands[d.curWand].shuffle:
      # shuffle the non-empty cards in place, leaving the empty slots where they are
      var filled: seq[int8] = @[]
      for i in 0 ..< d.wands[d.curWand].nslots:
        if d.wands[d.curWand].slots[i] >= 0: filled.add d.wands[d.curWand].slots[i]
      var i = filled.len - 1
      while i > 0:
        let j = rint(d.g.dice, 0, i)
        let t = filled[i]
        filled[i] = filled[j]
        filled[j] = t
        i -= 1
      var fi = 0
      for k in 0 ..< d.wands[d.curWand].nslots:
        if d.wands[d.curWand].slots[k] >= 0:
          d.wands[d.curWand].slots[k] = filled[fi]
          inc fi
  d.events.add sfxCast
  produced

# -------------------------------------------------------------- projectiles ---

proc impactProj(d: var Deep; p: var Shot; x, y: float64)

proc updateProjectiles*(d: var Deep) =
  var i = d.shots.len - 1
  while i >= 0:
    var p = d.shots[i]
    if p.homing > 0:
      var best = -1
      var bd = 90.0
      if p.enemy:
        let dd = sqrt((d.player.x - p.x) * (d.player.x - p.x) +
                      (d.player.y - p.y) * (d.player.y - p.y))
        if not d.player.dead and dd < bd: bd = dd; best = -1
      else:
        for k in 0 ..< d.foes.len:
          if d.foes[k].dead: continue
          let dd = sqrt((d.foes[k].x - p.x) * (d.foes[k].x - p.x) +
                        (d.foes[k].y - p.y) * (d.foes[k].y - p.y))
          if dd < bd: bd = dd; best = k
      if p.enemy and best == -1 and bd < 90.0:
        let dd = max(bd, 1e-9)
        p.vx += (d.player.x - p.x) / dd * p.homing * 4.0
        p.vy += (d.player.y - p.y) / dd * p.homing * 4.0
        let n = sqrt(p.vx * p.vx + p.vy * p.vy)
        if n > 0:
          let spd = min(6.5, n)
          p.vx = p.vx / n * spd
          p.vy = p.vy / n * spd
      elif best >= 0:
        let dd = max(bd, 1e-9)
        p.vx += (d.foes[best].x - p.x) / dd * p.homing * 4.0
        p.vy += (d.foes[best].y - p.y) / dd * p.homing * 4.0
        let n = sqrt(p.vx * p.vx + p.vy * p.vy)
        if n > 0:
          let spd = min(6.5, n)
          p.vx = p.vx / n * spd
          p.vy = p.vy / n * spd
    p.x += p.vx
    p.y += p.vy
    if p.drill == 0: p.vy += 0.018
    dec p.life
    if p.fire > 0 and (d.tick and 1) == 0:
      let fx = int(p.x)
      let fy = int(p.y)
      if d.g.at(fx, fy) == MatAir: d.g.put(fx, fy, MatFire, 8)
    if p.trigger == 2:
      dec p.timer
      if p.timer <= 0:
        d.impactProj(p, p.x, p.y)
        d.shots.delete(i)
        dec i
        continue
    let hitMat = isSolid(d.g.at(int(p.x), int(p.y)))
    if hitMat:
      if p.bounce > 0 and p.life > 8:
        p.vx *= -0.75
        p.vy *= -0.75
        p.x += p.vx
        p.y += p.vy
        dec p.bounce
      elif p.drill > 0:
        d.impactProj(p, p.x, p.y)
        if p.life <= 0:
          d.shots.delete(i)
          dec i
          continue
      else:
        d.impactProj(p, p.x, p.y)
        d.shots.delete(i)
        dec i
        continue
    if p.enemy and not d.player.dead:
      if sqrt((d.player.x - p.x) * (d.player.x - p.x) +
              (d.player.y - p.y) * (d.player.y - p.y)) < 6.0:
        d.hurt(p.dmg, "kill", "SLAIN · an enemy bolt found your heart")
        d.impactProj(p, p.x, p.y)
        d.shots.delete(i)
        dec i
        continue
    if not p.enemy:
      var killed = false
      for k in 0 ..< d.foes.len:
        if d.foes[k].dead: continue
        let rad = (if d.foes[k].id == tWellseye: 12.0 else: 6.0)
        if sqrt((d.foes[k].x - p.x) * (d.foes[k].x - p.x) +
                (d.foes[k].y - p.y) * (d.foes[k].y - p.y)) < rad:
          d.hurtFoe(d.foes[k], p.dmg)
          d.foes[k].flash = 5
          if p.payload.len > 0 or p.expl > 0:
            d.impactProj(p, d.foes[k].x, d.foes[k].y)
          else:
            d.parts.add Part(x: d.foes[k].x, y: d.foes[k].y,
                             vx: (roll(d.g.dice) - 0.5) * 2.0, vy: -1.0,
                             life: 10, maxLife: 10, kind: 3, r: 180, g: 30, b: 40)
            d.events.add sfxHit
          if p.pierce > 0:
            dec p.pierce
            p.dmg *= 0.85
          else:
            d.shots.delete(i)
            killed = true
          break
      if killed:
        dec i
        continue
    if p.life <= 0 or p.x < 1.0 or p.x > float64(WW - 2) or p.y < 1.0 or p.y > float64(WH - 2):
      if p.payload.len > 0: d.impactProj(p, p.x, p.y)
      d.shots.delete(i)
    else:
      d.shots[i] = p
    dec i

proc impactProj(d: var Deep; p: var Shot; x, y: float64) =
  let xi = int(x)
  let yi = int(y)
  if p.flask >= 0:
    for i in 0 ..< 22:
      let ax = int(x) + rint(d.g.dice, -4, 4)
      let ay = int(y) + rint(d.g.dice, -3, 4)
      let n = d.g.at(ax, ay)
      if n == MatAir or mats[n].kind == mkGas or mats[n].kind == mkFire:
        d.g.put(ax, ay, uint8(p.flask))
    d.events.add sfxKick
    return
  if p.payload.len > 0:
    var dx = p.vx
    var dy = p.vy
    let l = sqrt(dx * dx + dy * dy)
    if l > 0:
      dx /= l
      dy /= l
    else:
      dx = 0.0
      dy = 0.0
    for tpl in p.payload:
      d.spawnFromTemplate(tpl, x, y, dx, dy, 6.0)
  if p.expl > 0:
    d.explode(xi, yi, p.expl, p.dmg, float64(p.expl * 9000))
  elif p.drill > 0:
    for yy in -3 .. 3:
      for xx in -3 .. 3:
        if xx * xx + yy * yy > 9: continue
        let m = d.g.at(xi + xx, yi + yy)
        if m != MatBrick and m != MatDense and int(mats[m].hard) <= 10:
          d.g.put(xi + xx, yi + yy, MatAir)
  elif p.fire > 0:
    d.g.put(xi, yi, MatFire, 24)
    for i in 0 ..< 4:
      let ax = xi + rint(d.g.dice, -2, 2)
      let ay = yi + rint(d.g.dice, -2, 2)
      if d.g.at(ax, ay) == MatAir or int(mats[d.g.at(ax, ay)].flamm) > 0:
        d.g.put(ax, ay, MatFire, 16)
  elif p.acid > 0:
    for i in 0 ..< 5:
      let ax = xi + rint(d.g.dice, -2, 2)
      let ay = yi + rint(d.g.dice, -2, 2)
      if d.g.at(ax, ay) != MatDense and d.g.at(ax, ay) != MatBrick:
        d.g.put(ax, ay, MatAcid)
  elif p.freeze > 0:
    let m = d.g.at(xi, yi)
    if m == MatWater: d.g.put(xi, yi, MatIce)
    elif m == MatAir: d.g.put(xi, yi, MatIce)
  else:
    let m = d.g.at(xi, yi)
    if m != MatBrick and m != MatDense and int(mats[m].hard) <= 8:
      d.g.put(xi, yi, MatAir)
  d.parts.add Part(x: x, y: y, life: 6, maxLife: 6, kind: 0,
                   r: int(p.col[0]), g: int(p.col[1]), b: int(p.col[2]))

# -------------------------------------------------------------------- player ---

proc isLiq*(m: uint8): bool {.inline.} = mats[m].kind == mkLiquid

proc offerPerks*(d: var Deep)

proc updatePlayer*(d: var Deep; inp: Input) =
  ## Walk, jump, hover on a fuel tank, liquid drag and buoyancy, the five statuses,
  ## drowning, gold pickup by touch, mana regen and the sanctuary heal.
  if d.player.dead: return
  let left = inp.left
  let right = inp.right
  let jump = inp.jump
  let accel = (if right: 1 else: 0) - (if left: 1 else: 0)
  if d.player.oiled > 0: d.player.vx += float64(accel) * 0.08
  else: d.player.vx += float64(accel) * 0.16
  if accel != 0: d.player.dir = accel
  d.player.vx *= (if d.player.oiled > 0: 0.92 else: 0.8)
  d.player.vx = max(-1.55, min(1.55, d.player.vx))
  d.player.onGround = d.solidAtRect(d.player.x, d.player.y + float64(d.player.h) / 2.0 + 1.0,
                                    d.player.w, 2)
  if jump and d.player.onGround:
    d.player.vy = -3.15
    d.player.onGround = false
    d.events.add sfxJump
  let hovering = jump and not d.player.onGround and d.player.hover > 0
  if hovering:
    d.player.vy = min(d.player.vy, 0.18)
    d.player.hover -= 0.72
  else:
    d.player.vy += 0.165
    let regen = (if pkBreath in d.player.perk: 0.5 else: 0.24)
    d.player.hover = min(d.player.maxHover, d.player.hover + regen)
  d.player.vy = max(-4.2, min(3.4, d.player.vy))
  let inLiq = isLiq(d.g.at(int(d.player.x), int(d.player.y))) or
              isLiq(d.g.at(int(d.player.x), int(d.player.y + 3.0)))
  if inLiq:
    d.player.vx *= 0.92
    d.player.vy *= 0.9
    d.player.vy -= 0.04
  d.moveBody(d.player, d.player.vx, 0.0)
  d.moveBody(d.player, 0.0, d.player.vy)

  if d.player.inv > 0: dec d.player.inv
  if d.player.flash > 0: dec d.player.flash
  if d.kickCD > 0: dec d.kickCD

  let head = d.g.at(int(d.player.x), int(d.player.y - 5.0))
  let body = d.g.at(int(d.player.x), int(d.player.y))
  let feet = d.g.at(int(d.player.x), int(d.player.y + 4.0))
  var around = [head, body, feet, d.g.at(int(d.player.x - 2.0), int(d.player.y)),
                d.g.at(int(d.player.x + 2.0), int(d.player.y))]
  var wet, oil, onFire, tox, ac, lav, cr = false
  for m in around:
    if m == MatWater or m == MatBlood or m == MatSlime: wet = true
    if m == MatOil: oil = true
    if m == MatFire or m == MatEmber: onFire = true
    if m == MatToxic or m == MatPgas: tox = true
    if m == MatAcid: ac = true
    if m == MatLava: lav = true
    if mats[m].kind == mkStatic and mats[m].hard >= 10: cr = true
  if wet:
    d.player.wet = 50
    d.player.burning = 0
    d.player.oiled = max(0, d.player.oiled - 3)
  elif d.player.wet > 0: dec d.player.wet
  if oil: d.player.oiled = 90
  elif d.player.oiled > 0: dec d.player.oiled
  if onFire or lav:
    if d.player.wet <= 0:
      d.player.burning = max(d.player.burning, (if lav: 90 else: 50))
  if d.player.burning > 0:
    dec d.player.burning
    d.hurt(d.player.maxHp * 0.02 / 60.0, (if lav: "lava" else: "burn"),
           (if lav: "BURNED · the lava turned you to ash"
            else: "BURNED · the fire ate your flesh"))
  if tox:
    d.player.toxic = 80
    d.hurt(d.player.maxHp * 0.015 / 60.0, "toxic", "POISONED · the sludge rotted your organs")
  elif d.player.toxic > 0: dec d.player.toxic
  if ac: d.hurt(0.35, "acid", "DISSOLVED · the acid ate through you")
  if mats[head].kind == mkStatic and mats[head].hard >= 8:
    d.hurt(8.0, "crush", "CRUSHED · the weight of the world pressed you flat")

  if mats[head].kind == mkLiquid or mats[head].kind == mkStatic:
    dec d.player.air
    if d.player.air <= 0:
      d.hurt(1.2, "drown", "DROWNED · the well filled your lungs")
  else:
    d.player.air = min(90, d.player.air + 3)

  if d.g.at(int(d.player.x), int(d.player.y)) == MatGold or
     d.g.at(int(d.player.x), int(d.player.y + 3.0)) == MatGold:
    for dy in -4 .. 5:
      for dx in -3 .. 3:
        if d.g.at(int(d.player.x) + dx, int(d.player.y) + dy) == MatGold:
          d.g.put(int(d.player.x) + dx, int(d.player.y) + dy, MatAir)
          d.run.gold += (if pkGold in d.player.perk: 2 else: 1)

  for i in 0 ..< 4:
    d.wands[i].mana = min(d.wands[i].manaMax, d.wands[i].mana + d.wands[i].regen / 60.0)
    if d.wands[i].delayT > 0: dec d.wands[i].delayT
    if d.wands[i].rechT > 0: dec d.wands[i].rechT
  if inp.fire: discard d.tryCast(inp)

  for i in 0 ..< Sanctums:
    if d.player.y >= float64(d.holy[i].y0) and d.player.y < float64(d.holy[i].y1) and
       not d.holy[i].seen:
      d.holy[i].seen = true
      d.player.hp = d.player.maxHp
      d.offerPerks()

# --------------------------------------------------------------------- perks ---

const perkNames* = ["STEEL BONES", "GLASS CANNON", "CRIT EYE", "LONG BREATH", "TINKER",
                    "GILDED", "EMBER SKIN", "CLEAN BLOOD", "BLOOD PRICE", "WELL LAMP"]

const perkDesc* = ["damage taken -50%", "spells x2, max HP halved", "25% chance of double damage",
                   "hover recovers twice as fast", "edit wands anywhere", "gold +50%",
                   "fire and lava cannot ignite you", "immune to poison, gas and acid",
                   "a kill heals 8", "a much wider lantern"]

proc offerPerks*(d: var Deep) =
  var pool: seq[int] = @[]
  for i in 0 ..< 10: pool.add i
  d.offer = [-1, -1, -1]
  for i in 0 ..< 3:
    let j = rint(d.g.dice, 0, pool.high)
    d.offer[i] = pool[j]
    pool.delete(j)
  d.offering = true

proc choosePerk*(d: var Deep; i: int): bool =
  if i < 0 or i > 2 or d.offer[i] < 0: return false
  let p = Perk(d.offer[i])
  d.player.perk.incl p
  if p == pkGlass:
    d.player.maxHp = float64(int(d.player.maxHp * 0.5))
    d.player.hp = min(d.player.hp, d.player.maxHp)
  d.offer = [-1, -1, -1]
  d.offering = false
  d.toast = "blessing: " & perkNames[ord(p)]
  d.toastT = 90
  d.events.add sfxPerk
  true

# ---------------------------------------------------------------- creature AI ---

proc updateFoes*(d: var Deep) =
  ## Six behaviours. Off-screen creatures freeze (|dy| > screen + 80), exactly as
  ## the original culls them.
  var i = d.foes.len - 1
  while i >= 0:
    if d.foes[i].dead:
      d.foes.delete(i)
      dec i
      continue
    if d.foes[i].flash > 0: dec d.foes[i].flash
    if abs(d.foes[i].y - d.player.y) > float64(VH + 80):
      dec i
      continue
    dec d.foes[i].cool
    let dx = d.player.x - d.foes[i].x
    let dy = d.player.y - d.foes[i].y
    let dist = max(sqrt(dx * dx + dy * dy), 1e-9)
    let sgnx = (if dx > 0.0: 1.0 elif dx < 0.0: -1.0 else: 0.0)
    let sgny = (if dy > 0.0: 1.0 elif dy < 0.0: -1.0 else: 0.0)
    case d.foes[i].kind
    of fkMelee:
      d.foes[i].vx += sgnx * 0.05
      d.foes[i].vx *= 0.86
      d.foes[i].vx = max(-0.85, min(0.85, d.foes[i].vx))
      d.foes[i].vy += 0.16
      let grounded = d.solidAtRect(d.foes[i].x, d.foes[i].y + float64(d.foes[i].h) / 2.0 + 1.0,
                                   d.foes[i].w, 2)
      if grounded and abs(dx) < 70.0 and d.foes[i].cool <= 0 and abs(dy) < 24.0:
        d.foes[i].vy = -2.2
        d.foes[i].cool = 70
      var b = Body(x: d.foes[i].x, y: d.foes[i].y, vx: d.foes[i].vx, vy: d.foes[i].vy,
                   w: d.foes[i].w, h: d.foes[i].h)
      d.moveBody(b, b.vx, b.vy)
      d.foes[i].x = b.x
      d.foes[i].y = b.y
      d.foes[i].vx = b.vx
      d.foes[i].vy = b.vy
      if dist < 9.0: d.hurt(d.foes[i].dmg, "kill", "SLAIN · " & d.foes[i].name & " bit you")
    of fkRanged:
      d.foes[i].vx += sin(float64(d.tick) * 0.03 + d.foes[i].phase) * 0.02 + sgnx * 0.01
      d.foes[i].vy += 0.12
      d.foes[i].vx *= 0.9
      var b = Body(x: d.foes[i].x, y: d.foes[i].y, vx: d.foes[i].vx, vy: d.foes[i].vy,
                   w: d.foes[i].w, h: d.foes[i].h)
      d.moveBody(b, b.vx, b.vy)
      d.foes[i].x = b.x
      d.foes[i].y = b.y
      d.foes[i].vx = b.vx
      d.foes[i].vy = b.vy
      if d.foes[i].cool <= 0 and dist < 160.0 and dist > 20.0:
        let a = arctan2(dy, dx)
        d.shots.add Shot(x: d.foes[i].x, y: d.foes[i].y, vx: cos(a) * 2.1, vy: sin(a) * 2.1,
                         life: 110, dmg: d.foes[i].dmg, col: [238'u8, 90, 110], enemy: true,
                         light: 0.6, flask: -1)
        d.foes[i].cool = 55 + rint(d.g.dice, 0, 30)
      if dist < 8.0:
        d.hurt(d.foes[i].dmg * 0.6, "kill", "SLAIN · " & d.foes[i].name & " struck you")
    of fkFly:
      d.foes[i].x += sin(float64(d.tick) * 0.07 + d.foes[i].phase) * 0.55 + sgnx * 0.12
      d.foes[i].y += cos(float64(d.tick) * 0.06 + d.foes[i].phase) * 0.4 + sgny * 0.08
      d.foes[i].x = max(8.0, min(float64(WW - 8), d.foes[i].x))
      if dist < 8.0: d.hurt(d.foes[i].dmg, "kill", "SLAIN · " & d.foes[i].name & " dived at you")
    of fkBoom:
      d.foes[i].vx += sgnx * 0.07
      d.foes[i].vx *= 0.88
      d.foes[i].vy += 0.14
      var b = Body(x: d.foes[i].x, y: d.foes[i].y, vx: d.foes[i].vx, vy: d.foes[i].vy,
                   w: d.foes[i].w, h: d.foes[i].h)
      d.moveBody(b, b.vx, b.vy)
      d.foes[i].x = b.x
      d.foes[i].y = b.y
      d.foes[i].vx = b.vx
      d.foes[i].vy = b.vy
      if dist < 28.0: inc d.foes[i].fuse
      else: d.foes[i].fuse = max(0, d.foes[i].fuse - 1)
      if d.foes[i].fuse > 40 or dist < 10.0:
        d.explode(int(d.foes[i].x), int(d.foes[i].y), 16, d.foes[i].dmg, 15000.0)
        d.foes[i].dead = true
    of fkBurrow:
      let ang = arctan2(dy, dx)
      d.foes[i].vx = cos(ang) * 0.55
      d.foes[i].vy = sin(ang) * 0.55
      d.foes[i].x += d.foes[i].vx
      d.foes[i].y += d.foes[i].vy
      for q in -2 .. 2:
        for k in -2 .. 2:
          let m = d.g.at(int(d.foes[i].x) + q, int(d.foes[i].y) + k)
          if m != MatDense and m != MatBrick and int(mats[m].hard) <= 10:
            d.g.put(int(d.foes[i].x) + q, int(d.foes[i].y) + k, MatAir)
      var px = d.foes[i].x
      var py = d.foes[i].y
      for s in 0 ..< d.foes[i].segs.len:
        let ndx = px - d.foes[i].segs[s][0]
        let ndy = py - d.foes[i].segs[s][1]
        let nd = max(sqrt(ndx * ndx + ndy * ndy), 1e-9)
        if nd > 5.0:
          d.foes[i].segs[s][0] += ndx / nd * (nd - 5.0)
          d.foes[i].segs[s][1] += ndy / nd * (nd - 5.0)
        px = d.foes[i].segs[s][0]
        py = d.foes[i].segs[s][1]
      if dist < 10.0:
        d.hurt(d.foes[i].dmg, "kill", "SLAIN · " & d.foes[i].name & " bored through you")
    of fkBoss:
      d.foes[i].vx += sin(float64(d.tick) * 0.02) * 0.02 + sgnx * 0.012
      d.foes[i].vy += cos(float64(d.tick) * 0.018) * 0.015 + sgny * 0.01
      d.foes[i].vx = max(-0.7, min(0.7, d.foes[i].vx))
      d.foes[i].vy = max(-0.5, min(0.5, d.foes[i].vy))
      d.foes[i].x = max(24.0, min(float64(WW - 24), d.foes[i].x + d.foes[i].vx))
      d.foes[i].y = max(float64(WH - 120), min(float64(WH - 24), d.foes[i].y + d.foes[i].vy))
      if d.foes[i].cool <= 0 and dist < 260.0:
        let a = arctan2(dy, dx)
        let n = (if d.foes[i].hp < d.foes[i].maxHp * 0.4: 5 else: 3)
        for q in -(n - 1) div 2 .. (n - 1) div 2:
          let aa = a + float64(q) * 0.18
          d.shots.add Shot(x: d.foes[i].x, y: d.foes[i].y, vx: cos(aa) * 1.9, vy: sin(aa) * 1.9,
                           life: 160, dmg: d.foes[i].dmg, col: [210'u8, 80, 230], enemy: true,
                           homing: (if d.foes[i].hp < d.foes[i].maxHp * 0.5: 0.04 else: 0.0),
                           light: 1.1, flask: -1)
        if d.foes[i].hp < d.foes[i].maxHp * 0.35 and chance(d.g.dice, 0.3):
          for k in 0 ..< 6:
            d.g.put(int(d.foes[i].x) + rint(d.g.dice, -20, 20), int(d.foes[i].y) + 8, MatLava)
        d.foes[i].cool = 40
      if dist < 16.0:
        d.hurt(d.foes[i].dmg, "kill", "SLAIN · " & d.foes[i].name & " burned you with its gaze")
    dec i

# ------------------------------------------------------------------- pickups ---

proc updatePickups*(d: var Deep) =
  var i = d.picks.len - 1
  while i >= 0:
    d.picks[i].vy += 0.07
    d.picks[i].x += d.picks[i].vx
    d.picks[i].y += d.picks[i].vy
    if isSolid(d.g.at(int(d.picks[i].x), int(d.picks[i].y + 3.0))):
      d.picks[i].vy = 0
      d.picks[i].vx *= 0.6
      d.picks[i].y -= 0.4
    if sqrt((d.picks[i].x - d.player.x) * (d.picks[i].x - d.player.x) +
            (d.picks[i].y - d.player.y) * (d.picks[i].y - d.player.y)) < 11.0:
      case d.picks[i].kind
      of puGold:
        let v = int(float64(d.picks[i].val) * (if pkGold in d.player.perk: 1.5 else: 1.0))
        d.run.gold += v
        d.toast = "+" & $v & " gold"
        d.toastT = 90
        d.events.add sfxGold
      of puHeart:
        if d.picks[i].val > 0:
          d.player.maxHp += 25
          d.player.hp = min(d.player.maxHp, d.player.hp + 25)
          d.toast = "max HP +25"
        else:
          d.player.hp = d.player.maxHp
          d.toast = "healed"
        d.toastT = 90
        d.events.add sfxPerk
      of puSpell:
        if d.gift.len < 16:
          d.gift.add d.picks[i].spell
        else:
          var emp = -1
          for k in 0 ..< d.wands[d.curWand].nslots:
            if d.wands[d.curWand].slots[k] < 0: emp = k; break
          if emp >= 0: d.wands[d.curWand].slots[emp] = int8(d.picks[i].spell)
          else: d.gift.add d.picks[i].spell
        d.toast = "spell: " & spellName(d.picks[i].spell)
        d.toastT = 90
        d.events.add sfxPerk
      of puFlask:
        d.flasks.add d.picks[i].flask
        d.toast = "flask: " & nameOf(uint8(d.picks[i].flask))
        d.toastT = 90
      of puChest:
        d.run.gold += d.picks[i].val
        if chance(d.g.dice, 0.7):
          d.picks.add Pickup(kind: puSpell, x: d.picks[i].x, y: d.picks[i].y - 6.0,
                             vx: roll(d.g.dice) - 0.5, vy: -1.5, spell: randomSpell(d, 2))
        d.toast = "chest opened"
        d.toastT = 90
        d.events.add sfxGold
      of puWand:
        var slot = -1
        for w in 0 ..< 4:
          var empty = true
          for k in 0 ..< d.wands[w].nslots:
            if d.wands[w].slots[k] >= 0: empty = false
          if empty: slot = w; break
        if slot < 0: slot = 3
        d.wands[slot] = d.picks[i].wand
        d.toast = "wand: " & d.picks[i].wand.name
        d.toastT = 90
        d.events.add sfxPerk
      d.picks.delete(i)
    dec i

proc updateParts*(d: var Deep) =
  var i = d.parts.len - 1
  while i >= 0:
    dec d.parts[i].life
    d.parts[i].x += d.parts[i].vx
    d.parts[i].y += d.parts[i].vy
    if d.parts[i].kind != 1 and d.parts[i].kind != 0: d.parts[i].vy += 0.08
    if d.parts[i].life <= 0: d.parts.delete(i)
    dec i

# ------------------------------------------------------------------- actions ---

proc kick*(d: var Deep; inp: Input) =
  if d.kickCD > 0 or d.player.dead: return
  d.kickCD = 18
  let a = d.aimVec(inp)
  let kx = d.player.x + a[0] * 10.0
  let ky = d.player.y + a[1] * 7.0
  d.events.add sfxKick
  d.shakeMag = max(d.shakeMag, 2.0)
  for i in 0 ..< d.foes.len:
    if d.foes[i].dead: continue
    if sqrt((d.foes[i].x - kx) * (d.foes[i].x - kx) +
            (d.foes[i].y - ky) * (d.foes[i].y - ky)) < 13.0:
      d.foes[i].vx += a[0] * 2.6
      d.foes[i].vy += a[1] * 1.8 - 1.2
      d.hurtFoe(d.foes[i], 5.0)
  let sgn = (if a[0] > 0.0: 1 else: -1)
  for dy in -5 .. 5:
    for dx in -5 .. 5:
      let m = d.g.at(int(kx) + dx, int(ky) + dy)
      if mats[m].kind == mkPowder or mats[m].kind == mkLiquid:
        let tx = int(kx) + dx + sgn * 2
        let ty = int(ky) + dy - 1
        if d.g.at(tx, ty) == MatAir:
          d.g.put(tx, ty, m)
          d.g.put(int(kx) + dx, int(ky) + dy, MatAir)
  d.parts.add Part(x: kx, y: ky, life: 6, maxLife: 6, kind: 0, r: 255, g: 255, b: 220)

proc throwFlask*(d: var Deep; inp: Input) =
  if d.flasks.len == 0: return
  let f = d.flasks.pop()
  let a = d.aimVec(inp)
  d.shots.add Shot(x: d.player.x + a[0] * 8.0, y: d.player.y + a[1] * 6.0,
                   vx: a[0] * 3.2, vy: a[1] * 3.2 - 0.4, life: 80, dmg: 4.0,
                   col: [mats[uint8(f)].r, mats[uint8(f)].g, mats[uint8(f)].b],
                   enemy: false, bounce: 1, light: 0.3, flask: f)

# ------------------------------------------------------------------ one tick ---

proc update*(d: var Deep; inp: Input) =
  ## One 1/60 s tick, in the original's order.
  if d.st != gsPlay: return
  if d.offering: return
  inc d.tick
  inc d.run.frames
  d.aimX = inp.aimX
  d.aimY = inp.aimY
  d.updatePlayer(inp)
  d.automaton()
  d.updateProjectiles()
  d.updateFoes()
  d.updatePickups()
  d.updateParts()
  d.camY += (d.player.y - float64(VH) * 0.55 - d.camY) * 0.14
  d.camY = max(0.0, min(float64(WH - VH), d.camY))
  d.run.depth = max(d.run.depth, int(d.player.y))
  d.shakeMag *= 0.84
  if d.flash > 0: dec d.flash
  if d.toastT > 0:
    dec d.toastT

proc renderFb*(d: var Deep)

proc newDeep*(sd: uint32): Deep =
  ## A whole run: the world, four wands, the delver at the well mouth.
  var d = Deep()
  d.light = newSeq[uint8](LightN)
  d.lightR = newSeq[uint8](LightN)
  d.lightG = newSeq[uint8](LightN)
  d.lightB = newSeq[uint8](LightN)
  d.fb = newSeq[byte](LightN * 4)
  d.setupWands()
  d.generateWorld(sd)
  d

# --------------------------------------------------------------------- light ---
# Light is a screen-space buffer rebuilt each frame; nothing is baked into the grid.
# The lantern is 28 rays that spend 45% of their brightness on every solid cell they
# enter, so rock really does hide what is behind it.

proc stampLight*(d: var Deep; sx, sy: float64; rad: int; intens: float64;
                 cr, cg, cb: int) =
  let r = rad
  let x0 = max(0, min(VW - 1, int(sx - float64(r))))
  let x1 = max(0, min(VW - 1, int(sx + float64(r))))
  let y0 = max(0, min(VH - 1, int(sy - float64(r))))
  let y1 = max(0, min(VH - 1, int(sy + float64(r))))
  let r2 = float64(r * r)
  if r2 <= 0.0: return
  for y in y0 .. y1:
    let dy = float64(y) - sy
    let dy2 = dy * dy
    for x in x0 .. x1:
      let dx = float64(x) - sx
      let d2 = dx * dx + dy2
      if d2 > r2: continue
      let fall = 1.0 - d2 / r2
      let v = intens * fall * fall
      let i = y * VW + x
      if v > float64(d.light[i]):
        d.light[i] = uint8(min(255.0, v))
        d.lightR[i] = uint8(cr)
        d.lightG[i] = uint8(cg)
        d.lightB[i] = uint8(cb)

proc stampLantern*(d: var Deep) =
  let px = d.player.x
  let R = (if pkLamp in d.player.perk: 96.0 else: 72.0)
  for a in 0 ..< 28:
    let ang = float64(a) * PI * 2.0 / 28.0
    let dx = cos(ang)
    let dy = sin(ang)
    var atten = 1.0
    var t = 0.0
    while t < R:
      let x = px + dx * t
      let y = d.player.y + dy * t
      let sx = x
      let sy = y - d.camY
      if sx < -2.0 or sy < -2.0 or sx >= float64(VW + 2) or sy >= float64(VH + 2): break
      let fall = 1.0 - t / R
      let v = 230.0 * fall * fall * atten
      let ix0 = int(sx)
      let iy0 = int(sy)
      for oy in 0 .. 1:
        for ox in 0 .. 1:
          let xx = ix0 + ox
          let yy = iy0 + oy
          if xx < 0 or yy < 0 or xx >= VW or yy >= VH: continue
          let i = yy * VW + xx
          if v > float64(d.light[i]):
            d.light[i] = uint8(min(255.0, v))
            d.lightR[i] = 255
            d.lightG[i] = 214
            d.lightB[i] = 150
      let m = d.g.at(int(x), int(y))
      if mats[m].kind == mkStatic and m != MatGlass and m != MatIce and m != MatCrystal:
        atten *= 0.55
        if atten < 0.05: break
      t += 2.0

proc lightAt*(d: Deep; x, y: int): int =
  if x < 0 or y < 0 or x >= VW or y >= VH: return 0
  int(d.light[y * VW + x])

# ------------------------------------------------------------------ renderer ---
# Every pixel is computed here: material colour with its texture hash, the biome sky
# and cave backdrop, the light composite with its warm tint and vignette, then the
# sprites, the flash and the aim line. The result is one RGBA framebuffer.

const
  # our own pixel art — the delver is a lamplit diver, the creatures silhouettes
  SprPlayer* = ["..111..", ".11111.", ".11311.", "..111..", ".23332.", "2333332",
                ".33333.", ".3...3.", ".3...3.", ".4...4."]
  SprTusk* = ["..11..", ".1111.", "211112", ".1111.", ".2..2."]
  SprGun* = ["..11..", ".1111.", "111113", ".1111.", ".2..2."]
  SprFly* = [".1...1.", "11.1.11", ".11111.", "..111.."]
  SprBoom* = [".111.", "12221", "12221", ".111."]
  SprBoss* = ["...111...", ".1133311.", "133141331", ".1133311.", "...111..."]

const
  PalPlayer* = [0x000000'u32, 0xE8BAA8'u32, 0x5A468C'u32, 0x7860B0'u32, 0x282434'u32]
  PalPlayerHit* = [0x000000'u32, 0xFFFFFF'u32, 0xFFFFFF'u32, 0xFFFFFF'u32, 0xFFFFFF'u32]
  PalTusk* = [0x000000'u32, 0xBAC4B0'u32, 0x282A30'u32, 0x000000'u32, 0x000000'u32]
  PalGun* = [0x000000'u32, 0xC4484E'u32, 0x281E20'u32, 0xF0C85A'u32, 0x000000'u32]
  PalFly* = [0x000000'u32, 0xC8608C'u32, 0x000000'u32, 0x000000'u32, 0x000000'u32]
  PalBoom* = [0x000000'u32, 0x50A046'u32, 0xDC503C'u32, 0x000000'u32, 0x000000'u32]
  PalBoss* = [0x000000'u32, 0xA030AA'u32, 0x281030'u32, 0xDC5AE6'u32, 0xFFF08C'u32]

proc u8c*(v: float64): byte {.inline.} =
  ## Uint8ClampedArray semantics exactly: clamp, then round to nearest with ties to
  ## even. (Half-up would drift a whole RGB unit on every exact .5 the flash
  ## overlay produces, and would show up as a 30% pixel difference on a white frame.)
  if v <= 0.0: return 0'u8
  if v >= 255.0: return 255'u8
  let f = floor(v)
  let rest = v - f
  var i = int(f)
  if rest > 0.5: inc i
  elif rest == 0.5 and (i and 1) == 1: inc i
  byte(i)

proc shoulder(v: float64): float64 {.inline.} =
  ## Display-only film curve: linear through the shadows, then a soft knee that
  ## approaches 255 instead of hitting a wall. A flame keeps a hot gradient instead
  ## of becoming a clipped white rectangle, and a bright rock face keeps its texture.
  ## Untouched below 176, so the whole material ramp keeps its contrast.
  if v <= 176.0: return v
  let t = v - 176.0
  176.0 + t * 90.0 / (t + 90.0)

proc pset*(d: var Deep; x, y: float64; r, g, b: float64; a = 1.0) =
  let xi = int(x)
  let yi = int(y)
  if xi < 0 or yi < 0 or xi >= VW or yi >= VH: return
  let i = (yi * VW + xi) * 4
  d.fb[i] = u8c(float64(d.fb[i]) * (1.0 - a) + r * a)
  d.fb[i + 1] = u8c(float64(d.fb[i + 1]) * (1.0 - a) + g * a)
  d.fb[i + 2] = u8c(float64(d.fb[i + 2]) * (1.0 - a) + b * a)

proc addGlow*(d: var Deep; cx, cy, r: float64; gr, gg, gb, gain: float64) =
  ## Additive light on the finished framebuffer: a bright core with a smooth
  ## quadratic falloff. This is how the frame gets a real light SOURCE in it — the
  ## delver's carried lamp and the drifting embers — instead of only lit surfaces.
  let x0 = max(0, int(cx - r))
  let x1 = min(VW - 1, int(cx + r))
  let y0 = max(0, int(cy - r))
  let y1 = min(VH - 1, int(cy + r))
  if x0 > x1 or y0 > y1 or r <= 0.0: return
  let inv2 = 1.0 / (r * r)
  for y in y0 .. y1:
    let dy = float64(y) - cy
    let dy2 = dy * dy
    for x in x0 .. x1:
      let dx = float64(x) - cx
      let q = 1.0 - (dx * dx + dy2) * inv2
      if q <= 0.0: continue
      let a = q * q * gain
      let i = (y * VW + x) * 4
      d.fb[i] = u8c(shoulder(float64(d.fb[i]) + gr * a))
      d.fb[i + 1] = u8c(shoulder(float64(d.fb[i + 1]) + gg * a))
      d.fb[i + 2] = u8c(shoulder(float64(d.fb[i + 2]) + gb * a))

proc drawSprite*(d: var Deep; px, py: float64; rows: openArray[string];
                 pal: array[5, uint32]; flip: bool) =
  let ox = int(px)
  let oy = int(py)
  for y in 0 ..< rows.len:
    let row = rows[y]
    let n = row.len
    for x in 0 ..< n:
      let ch = row[(if flip: n - 1 - x else: x)]
      if ch == '.': continue
      let ci = ord(ch) - ord('0')
      if ci < 0 or ci > 4: continue
      let c = pal[ci]
      if c == 0: continue
      let sx = ox + x - (n shr 1)
      let sy = oy + y - (rows.len shr 1)
      if sx < 0 or sy < 0 or sx >= VW or sy >= VH: continue
      let i = (sy * VW + sx) * 4
      d.fb[i] = byte((c shr 16) and 0xFF)
      d.fb[i + 1] = byte((c shr 8) and 0xFF)
      d.fb[i + 2] = byte(c and 0xFF)
      d.fb[i + 3] = 255

proc renderFb*(d: var Deep) =
  ## One frame into `d.fb` (RGBA, VW*VH*4 bytes).
  if d.g.cell.len == 0: return
  let cam = d.camY + (roll(d.g.dice) - 0.5) * d.shakeMag
  let y0 = int(cam)
  let bmid = biomeOf(y0 + int(float64(VH) * 0.5))
  let amb = bmid.amb
  for i in 0 ..< LightN:
    d.light[i] = uint8(amb)
    d.lightR[i] = 40
    d.lightG[i] = 50
    d.lightB[i] = 70

  if not d.player.dead: d.stampLantern()
  for L in d.lamps:
    let sy = L.y - cam
    if sy < -float64(L.r) or sy > float64(VH + L.r): continue
    d.stampLight(L.x, sy, L.r, float64(L.i), L.cr, L.cg, L.cb)
  # emissive materials: sampled every 3rd cell so the pool costs a ninth of the work
  var sy = 0
  while sy < VH:
    let wy = y0 + sy
    if wy >= 0 and wy < WH:
      let row = wy * WW
      var sx = 0
      while sx < VW:
        let m = d.g.cell[row + sx]
        if mats[m].emit != 0:
          let r = (if m == MatLava: 22 elif m == MatFire: 16
                   elif m == MatFungus or m == MatCrystal: 14 else: 10)
          d.stampLight(float64(sx), float64(sy), r, float64(mats[m].emit),
                       int(mats[m].er), int(mats[m].eg), int(mats[m].eb))
        sx += 3
    sy += 3
  for p in d.shots:
    if p.light > 0.0:
      d.stampLight(p.x, p.y - cam, 12 + int(p.light * 8.0), 160.0 * p.light,
                   int(p.col[0]), int(p.col[1]), int(p.col[2]))

  let bg = bmid.bg
  # --- the display lighting model ---------------------------------------------
  # The light buffer is exact and the tests gate it (230 at the lantern, 16 for the
  # MINES ambient), so nothing below changes it. What changed is how that buffer
  # becomes RGB. It used to be one scalar — `warm = 0.04 + L/255` — multiplied into
  # every material, so unlit rock was struck by ~0.10 of its own colour and 76 % of
  # the viewport came out below luma 8: a black hole with one small disc of lantern.
  #
  # Now a light *colour* is built per pixel from three named terms and multiplied
  # into the material, so a warm ambient really renders warm rock and a cold shaft
  # really reads cold:
  #   ambient  the stratum's own bounce light — cool near the mouth, ember-warm at
  #            depth, dimming down the screen as if the light falls from above;
  #   halo     a wide, soft glow around the delver: the cave is not one small disc;
  #   key      the existing lantern / lava / projectile buffer, keeping its tint.
  #
  # Air is a medium, not a surface. It scatters the same light additively, so an
  # empty tunnel reads as a dark blue volume against a warm rock face instead of as
  # dead black against dead black.
  var ambR, ambG, ambB, ambK: float64
  case layerAt(y0 + (VH shr 1))
  of -1: ambR = 0.55; ambG = 0.66; ambB = 1.00; ambK = 0.60   # the mouth: sky bounce
  of 0:  ambR = 0.55; ambG = 0.62; ambB = 0.98; ambK = 0.60   # MINES: cold slate
  of 1:  ambR = 0.40; ambG = 0.46; ambB = 0.90; ambK = 0.48   # COAL PITS: darker
  of 2:  ambR = 1.00; ambG = 0.40; ambB = 1.00; ambK = 0.54   # FUNGAL: violet
  of 3:  ambR = 0.45; ambG = 0.80; ambB = 1.00; ambK = 0.60   # FROST: cyan
  of 4:  ambR = 1.00; ambG = 0.52; ambB = 0.26; ambK = 0.52   # EMBERLAKE: ember
  else:  ambR = 1.00; ambG = 0.80; ambB = 0.55; ambK = 0.66   # sanctum lamps
  # Two lamplight radii around the delver: a tight warm core (a lamp you carry) and
  # a very wide, very faint wash. Outside both, the stratum's cool ambient survives —
  # so the screen has a warm near-field and a cold far-field instead of one flat wash.
  const invHalo2 = 1.0 / (208.0 * 208.0)
  const invCore2 = 1.0 / (58.0 * 58.0)
  let plx = d.player.x
  let ply = d.player.y - cam
  # Motion, all deterministic from d.tick so the frame hash still pins exactly:
  # a lantern that breathes, and a 64-entry sine table standing in for the heat
  # shimmer in air that is close to a flame.
  let tickF = float64(d.tick)
  let flick = 0.93 + 0.07 * sin(tickF * 0.29) + 0.03 * sin(tickF * 1.13)
  let haloAmt = (if d.player.dead: 0.45 else: 1.0) * flick
  var shim: array[64, float64]
  for k in 0 ..< 64:
    shim[k] = sin(float64(k) * 0.0982 + tickF * 0.11)
  for syi in 0 ..< VH:
    let wy = y0 + syi
    let row = wy * WW
    let sky = wy < SurfY - 4
    let dyh = float64(syi) - ply
    let dyh2 = dyh * dyh
    let ambRow = ambK * (1.0 - 0.30 * float64(syi) / float64(VH))
    for sxi in 0 ..< VW:
      var r, gch, b: float64
      var m = MatAir
      var medium = false
      var selfLit = 0.0
      if wy < 0 or wy >= WH:
        r = 4.0; gch = 5.0; b = 8.0
      else:
        m = d.g.cell[row + sxi]
        if m == MatAir:
          medium = not sky
          if sky:
            let k = max(0.0, min(1.0, 1.0 - float64(wy) / float64(SurfY)))
            r = 12.0 + k * 40.0
            gch = 10.0 + k * 18.0
            b = 28.0 + k * 50.0
            if (phash(d.sd, int32(sxi), int32(wy)) and 255) > 252:
              r = 220.0; gch = 220.0; b = 200.0
          else:
            r = float64(bg[0]) * 0.42
            gch = float64(bg[1]) * 0.42
            b = float64(bg[2]) * 0.42
        else:
          let flow = (if mats[m].kind == mkLiquid or m == MatFire: d.tick shr 2 else: 0)
          let h = int(phash(d.sd, int32(sxi), int32(wy + flow)) and 7) - 3
          r = float64(mats[m].r) + float64(h * int(mats[m].cv shr 1))
          gch = float64(mats[m].g) + float64(h * int(mats[m].cv shr 1))
          b = float64(mats[m].b) + float64((h * int(mats[m].cv)) shr 2)
          if m == MatRock or m == MatDirt:
            r *= bmid.tint[0]; gch *= bmid.tint[1]; b *= bmid.tint[2]
          if m == MatLava:
            # Molten, not orange paint: a white-hot skin where the lava meets air and
            # a deeper body underneath, so a pool reads as a volume with a crust.
            let hot = (if wy > 0 and d.g.cell[(wy - 1) * WW + sxi] == MatAir: 1.0 else: 0.0)
            r = 255.0
            gch = 84.0 + float64(h * 6) + hot * 130.0
            b = 18.0 + hot * 60.0
          elif m == MatFire:
            r = 255.0; gch = 132.0 + float64((h + 3) * 10); b = 34.0
          elif mats[m].emit != 0:
            # every other emitter glows in its own colour — ember, crystal, fungus,
            # gold, acid — instead of sitting there as an ordinary rock
            let heat = float64(mats[m].emit) / 255.0
            r += heat * 78.0; gch += heat * 62.0; b += heat * 26.0
          if m == MatBrick and ((sxi + wy) and 7) == 0:
            r += 18.0; gch += 12.0
          if mats[m].emit != 0:
            selfLit = 0.42 + float64(mats[m].emit) / 255.0 * 0.85
      let li = syi * VW + sxi
      let di = li * 4
      let vx = float64(sxi) / float64(VW) - 0.5
      let vy = float64(syi) / float64(VH) - 0.5
      let vig = 1.0 - (vx * vx + vy * vy) * 0.55
      if sky:
        d.fb[di] = u8c(shoulder(r * vig * 1.85 + 1.5))
        d.fb[di + 1] = u8c(shoulder(gch * vig * 1.85 + 1.5))
        d.fb[di + 2] = u8c(shoulder(b * vig * 1.85 + 2.5))
      else:
        let f = float64(d.light[li]) / 255.0
        let lr = float64(d.lightR[li]) / 255.0
        let lg = float64(d.lightG[li]) / 255.0
        let lb = float64(d.lightB[li]) / 255.0
        let dxh = float64(sxi) - plx
        let d2 = dxh * dxh + dyh2
        var halo = 0.0
        var q = 1.0 - d2 * invHalo2
        if q > 0.0: halo = q * q * q * 0.30
        q = 1.0 - d2 * invCore2
        if q > 0.0: halo = (halo + q * q * 0.85) * haloAmt
        elif halo > 0.0: halo *= haloAmt
        let key = 1.10 * f
        var totR = ambR * ambRow + halo + lr * key
        var totG = ambG * ambRow + 0.68 * halo + lg * key
        var totB = ambB * ambRow + 0.34 * halo + lb * key
        if selfLit > 0.0:
          # an emitter lights itself: it is never multiplied down into the dark
          if totR < selfLit: totR = selfLit
          if totG < selfLit * 0.94: totG = selfLit * 0.94
          if totB < selfLit * 0.86: totB = selfLit * 0.86
        if medium:
          # volumetric: the medium scatters the same light, additively; the squared
          # key term is the bloom veil that hangs in the air around a fire
          let veil = 56.0 * f * f
          # heat shimmer: air near a flame wavers instead of standing still
          let waver = shim[(syi * 11 + sxi * 7 + (d.tick shr 1)) and 63] * veil * 0.22
          d.fb[di] = u8c(shoulder((r * (0.68 + 1.25 * totR) + 21.0 * totR + veil + waver) * vig))
          d.fb[di + 1] = u8c(shoulder((gch * (0.68 + 1.25 * totG) + 21.0 * totG +
                                       veil * 0.62 + waver * 0.55) * vig))
          d.fb[di + 2] = u8c(shoulder((b * (0.68 + 1.25 * totB) + 21.0 * totB +
                                       veil * 0.24) * vig + 2.0))
        else:
          # surface: the light multiplies the material, so the material survives
          d.fb[di] = u8c(shoulder(r * totR * 1.30 * vig + 1.0))
          d.fb[di + 1] = u8c(shoulder(gch * totG * 1.30 * vig + 1.0))
          d.fb[di + 2] = u8c(shoulder(b * totB * 1.30 * vig + 1.5))
      d.fb[di + 3] = 255

  # --- the light sources you can actually see ---------------------------------
  # The light buffer was already exact, but nothing in the frame *was* a light: every
  # bright pixel came from the HUD. The delver carries a lamp, so the lamp is drawn —
  # a hot core with a warm bloom — and embers drift through the lit air.
  if not d.player.dead:
    let lx = d.player.x + float64(d.player.dir) * 6.0
    let ly = d.player.y - cam - 3.0
    d.addGlow(lx, ly, 24.0, 255.0, 190.0, 112.0, 0.52 * flick)
    d.addGlow(lx, ly, 4.6, 255.0, 244.0, 208.0, 0.90 * flick)
  for lamp in d.lamps:
    let sy = lamp.y - cam
    if sy < -20.0 or sy > float64(VH + 20): continue
    d.addGlow(lamp.x, sy, float64(lamp.r) * 0.20, 255.0, 196.0, 120.0, 0.30)
  # Embers: deterministic motes that rise through the lamp pool. They are anchored on
  # the light, not sprinkled over the whole viewport — the light buffer modulates each
  # one, so an ember over unlit rock is faint and an ember in the lamp pool is hot.
  # (A first pass scattered them across the whole screen, and every one of 46 landed
  # on ambient air: the frame did not change by a single pixel.)
  block embers:
    let ax = (if d.player.dead: float64(VW) * 0.5 else: d.player.x)
    let ay = (if d.player.dead: float64(VH) * 0.5 else: d.player.y - cam)
    for k in 0 ..< 40:
      let h1 = phash(d.sd, int32(k * 37 + 5), 11)
      let h2 = phash(d.sd, int32(k * 53 + 7), 23)
      let ang = float64(h1 mod 628) * 0.01
      let rad = 8.0 + float64(h2 mod 100) * 0.30
      let life = 52.0
      let rise = (tickF * (0.22 + float64(h1 mod 60) * 0.007) +
                  float64(h2 mod 100)) mod life
      let px = ax + cos(ang) * rad + sin(tickF * 0.05 + float64(k)) * 1.6
      let py = ay + sin(ang) * rad * 0.8 - rise
      let fade = 1.0 - rise / life
      if px < 0.0 or py < 0.0 or px >= float64(VW) or py >= float64(VH): continue
      let f = float64(d.light[int(py) * VW + int(px)]) / 255.0
      let twinkle = 0.5 + 0.5 * sin(tickF * 0.23 + float64(h1 mod 360) * 0.0174)
      let a = (0.18 + 0.82 * min(1.0, f)) * fade * (0.35 + 0.65 * twinkle)
      if a <= 0.02: continue
      d.addGlow(px, py, 1.7, 255.0, 152.0, 58.0, a * 0.95)

  # --- things that sit on the world -------------------------------------------
  for p in d.picks:
    let sy2 = p.y - cam
    let col = (case p.kind
               of puGold: [244.0, 202.0, 83.0]
               of puHeart: [255.0, 90.0, 110.0]
               of puWand: [180.0, 220.0, 255.0]
               of puFlask: [140.0, 200.0, 255.0]
               of puChest: [196.0, 140.0, 60.0]
               of puSpell: [180.0, 140.0, 255.0])
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if abs(dx) + abs(dy) < 4:
          d.pset(p.x + float64(dx), sy2 + float64(dy), col[0], col[1], col[2], 0.9)
  for p in d.shots:
    let sy2 = p.y - cam
    d.pset(p.x, sy2, float64(p.col[0]), float64(p.col[1]), float64(p.col[2]), 1.0)
    d.pset(p.x + 1.0, sy2, float64(p.col[0]), float64(p.col[1]), float64(p.col[2]), 0.8)
    d.pset(p.x, sy2 + 1.0, float64(p.col[0]), float64(p.col[1]), float64(p.col[2]), 0.7)
    d.pset(p.x - 1.0, sy2, float64(p.col[0]), float64(p.col[1]), float64(p.col[2]), 0.5)
  for p in d.parts:
    let sy2 = p.y - cam
    let a = float64(p.life) / float64(if p.maxLife > 0: p.maxLife else: 10)
    if p.kind == 1:
      let rad = p.rad * (1.0 - a)
      for t in 0 ..< 12:
        let ang = float64(t) * PI / 6.0
        d.pset(p.x + cos(ang) * rad, sy2 + sin(ang) * rad,
               float64(p.r), float64(p.g), float64(p.b), a)
    else:
      d.pset(p.x, sy2, float64(p.r), float64(p.g), float64(p.b), a)
  for e in d.foes:
    let sy2 = e.y - cam
    if sy2 < -16.0 or sy2 > float64(VH + 16): continue
    let white = [0x000000'u32, 0xFFFFFF'u32, 0xFFFFFF'u32, 0xFFFFFF'u32, 0xFFFFFF'u32]
    case e.kind
    of fkBoss: d.drawSprite(e.x, sy2, SprBoss, (if e.flash > 0: white else: PalBoss), false)
    of fkRanged:
      let wp = [0x000000'u32, 0xFFFFFF'u32, 0xC03030'u32, 0xFFFFC8'u32, 0x000000'u32]
      d.drawSprite(e.x, sy2, SprGun, (if e.flash > 0: wp else: PalGun), e.x < d.player.x)
    of fkFly:
      let wp = [0x000000'u32, 0xFFFFFF'u32, 0x000000'u32, 0x000000'u32, 0x000000'u32]
      d.drawSprite(e.x, sy2, SprFly, (if e.flash > 0: wp else: PalFly), false)
    of fkBoom:
      let armed = [0x000000'u32, 0xFF5028'u32, 0xFFDC50'u32, 0x000000'u32, 0x000000'u32]
      d.drawSprite(e.x, sy2, SprBoom, (if e.fuse > 20: armed else: PalBoom), false)
    of fkBurrow:
      d.pset(e.x, sy2, 160, 120, 80, 1.0)
      for s in 0 ..< e.segs.len:
        d.pset(e.segs[s][0], e.segs[s][1] - cam, 130, 100, 70, 1.0)
    of fkMelee:
      let wp = [0x000000'u32, 0xFFFFFF'u32, 0x000000'u32, 0x000000'u32, 0x000000'u32]
      d.drawSprite(e.x, sy2, SprTusk, (if e.flash > 0: wp else: PalTusk), e.vx > 0.0)
    if e.hp < e.maxHp:
      let bw = (if e.kind == fkBoss: 20 else: 10)
      for k in 0 ..< bw:
        d.pset(e.x - float64(bw) / 2.0 + float64(k), sy2 - float64(e.h) / 2.0 - 4.0,
               20, 20, 24, 1.0)
      let hw = float64(bw) * max(0.0, min(1.0, e.hp / e.maxHp))
      var k = 0
      while float64(k) < hw:
        d.pset(e.x - float64(bw) / 2.0 + float64(k), sy2 - float64(e.h) / 2.0 - 4.0,
               220, 70, 80, 1.0)
        inc k
  if not d.player.dead:
    let sy2 = d.player.y - cam
    let inv = d.player.inv
    # the delver blinks while invulnerable, and flashes white on the frame of a hit
    let white = d.player.flash > 0 or ((inv mod 4) < 2 and inv > 0)
    let pal = (if white: PalPlayerHit else: PalPlayer)
    if not (inv > 0 and (d.tick mod 4) < 2):
      d.drawSprite(d.player.x, sy2, SprPlayer, pal, d.player.dir < 0)
    var ax = d.aimX - d.player.x
    var ay = d.aimY + d.camY - d.player.y
    let l = sqrt(ax * ax + ay * ay)
    if l > 0.0:
      ax /= l
      ay /= l
    for t in 3 ..< 9:
      d.pset(d.player.x + ax * float64(t) + float64(d.player.dir * 2), sy2 + ay * float64(t),
             200, 180, 90, 0.7)
    if d.player.burning > 0:
      d.pset(d.player.x, sy2 - 6.0, 255, 160, 40, 0.8)
      d.pset(d.player.x + 1.0, sy2 - 7.0, 255, 200, 60, 0.6)
  if d.flash > 0:
    let a = float64(d.flash) / 8.0
    var i = 0
    while i < d.fb.len:
      d.fb[i] = u8c(float64(d.fb[i]) + (255.0 - float64(d.fb[i])) * a)
      d.fb[i + 1] = u8c(float64(d.fb[i + 1]) + (255.0 - float64(d.fb[i + 1])) * a * 0.8)
      d.fb[i + 2] = u8c(float64(d.fb[i + 2]) + (220.0 - float64(d.fb[i + 2])) * a * 0.5)
      i += 4

# -------------------------------------------------------------------- hashes ---

proc gridHash*(d: Deep): uint64 =
  ## FNV-1a 64 over every material id, in y*WW+x order: the world's fingerprint.
  var h = 0xcbf29ce484222325'u64
  for i in 0 ..< d.g.cell.len:
    h = (h xor uint64(d.g.cell[i])) * 0x100000001b3'u64
  h

proc frameHash*(d: Deep): uint64 =
  var h = 0xcbf29ce484222325'u64
  for i in 0 ..< d.fb.len:
    h = (h xor uint64(d.fb[i])) * 0x100000001b3'u64
  h
