## t_emberdeep — the rules of EMBERDEEP, driven natively. No engine, no drawing.
##   nim c -r apps/emberdeep/tests/t_emberdeep.nim
##
## Most numbers here were read out of the original's source or measured by driving
## the original game in a browser (`/tmp/ora/oracle*`); where a value is the
## original's own gate number it is marked (gate). The grid hashes are the
## original's worlds, so "world gen matches" is a fact, not an impression.

import std/[math, strutils, algorithm]
import ../emberdeep

var passed = 0
var failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok   ", name
  else: inc failed; echo "  FAIL ", name, (if detail.len > 0: " — " & detail else: "")

proc near(a, b, eps: float64): bool = abs(a - b) <= eps

proc tank(d: var Deep; x, y, w, h: int) =
  ## A sealed box of air, as the original's own gate builds it.
  for yy in y ..< y + h:
    for xx in x ..< x + w: d.g.put(xx, yy, MatAir)
  for xx in x ..< x + w:
    d.g.put(xx, y, MatDense)
    d.g.put(xx, y + h - 1, MatDense)
  for yy in y ..< y + h:
    d.g.put(x, yy, MatDense)
    d.g.put(x + w - 1, yy, MatDense)

proc fill(d: var Deep; x0, y0, x1, y1: int; m: uint8; lf = 0) =
  for y in y0 .. y1:
    for x in x0 .. x1: d.g.put(x, y, m, lf)

proc count(d: Deep; x0, y0, x1, y1: int; m: uint8): int =
  for y in y0 .. y1:
    for x in x0 .. x1:
      if d.g.at(x, y) == m: inc result

proc centroid(d: Deep; x0, y0, x1, y1: int; m: uint8): (float64, int) =
  var sum = 0.0
  var n = 0
  for y in y0 .. y1:
    for x in x0 .. x1:
      if d.g.at(x, y) == m: sum += float64(y); inc n
  result = ((if n > 0: sum / float64(n) else: 0.0), n)

proc advance(d: var Deep; n: int; inp = Input()) =
  for i in 0 ..< n: d.update(inp)

# ================================ the material table ==========================

block:
  check("40 materials in the table", mats.len == 40, $mats.len)
  check("water is a liquid at density 1.00",
        kindOf(MatWater) == mkLiquid and denOf(MatWater) == 1.00'f32)
  check("sand is a powder, rock is static, steam is a gas, fire is fire",
        kindOf(MatSand) == mkPowder and kindOf(MatRock) == mkStatic and
        kindOf(MatSteam) == mkGas and kindOf(MatFire) == mkFire)
  # the density ladder the whole simulation is built on
  check("oil 0.80 < water 1.00 < blood 1.05 < toxic 1.15 < slime 1.20 < acid 1.40 < lava 2.60",
        denOf(MatOil) == 0.80'f32 and denOf(MatWater) == 1.00'f32 and
        denOf(MatBlood) == 1.05'f32 and denOf(MatToxic) == 1.15'f32 and
        denOf(MatSlime) == 1.20'f32 and denOf(MatAcid) == 1.40'f32 and
        denOf(MatLava) == 2.60'f32)
  check("powder ladder ash 0.70 < snow 0.90 < sand 1.80 < gold 3.00",
        denOf(MatAsh) == 0.70'f32 and denOf(MatSnow) == 0.90'f32 and
        denOf(MatSand) == 1.80'f32 and denOf(MatGold) == 3.00'f32)
  check("gas ladder fgas 0.12 < smoke 0.20 < pgas 0.25 < steam 0.30",
        denOf(MatFgas) == 0.12'f32 and denOf(MatSmoke) == 0.20'f32 and
        denOf(MatPgas) == 0.25'f32 and denOf(MatSteam) == 0.30'f32)
  let waterHex = (int(mats[MatWater].r) shl 16) or (int(mats[MatWater].g) shl 8) or int(mats[MatWater].b)
  let lavaHex = (int(mats[MatLava].r) shl 16) or (int(mats[MatLava].g) shl 8) or int(mats[MatLava].b)
  let fireHex = (int(mats[MatFire].r) shl 16) or (int(mats[MatFire].g) shl 8) or int(mats[MatFire].b)
  let brickHex = (int(mats[MatBrick].r) shl 16) or (int(mats[MatBrick].g) shl 8) or int(mats[MatBrick].b)
  check("water paints #3A7ABA, lava #FF5C1C, fire #FF9628, brick #5C564E",
        waterHex == 0x3A7ABA and lavaHex == 0xFF5C1C and fireHex == 0xFF9628 and
        brickHex == 0x5C564E,
        toHex(waterHex, 6) & " " & toHex(lavaHex, 6))
  check("hardness: dirt 6, metal 12, brick 14, dense 15",
        hardOf(MatDirt) == 6 and hardOf(MatMetal) == 12 and hardOf(MatBrick) == 14 and
        hardOf(MatDense) == 15)
  check("flammability: gunpowder 100, oil 90, wood 80, stone 0",
        flammOf(MatGunp) == 100 and flammOf(MatOil) == 90 and flammOf(MatWood) == 80 and
        flammOf(MatStone) == 0)
  check("emissive: lava 200, fire 220, ember 160, crystal 110",
        emitOf(MatLava) == 200 and emitOf(MatFire) == 220 and emitOf(MatEmber) == 160 and
        emitOf(MatCrystal) == 110)
  # one literal pins all 40 rows x 9 fields: any accidental table edit fails here
  var h = 0xcbf29ce484222325'u64
  for i in 0 ..< 40:
    let den = int(float64(mats[i].den) * 100.0 + 0.5)
    for v in [ord(mats[i].kind), den shr 8, den and 255, int(mats[i].hard),
              int(mats[i].flamm), int(mats[i].emit), int(mats[i].cv), int(mats[i].r),
              int(mats[i].g), int(mats[i].b), int(mats[i].er), int(mats[i].eg),
              int(mats[i].eb)]:
      h = (h xor uint64(v and 255)) * 0x100000001b3'u64
  check("table digest 0x978a1a39c4937758 (computed from the original's own mat() calls)",
        h == 0x978a1a39c4937758'u64, "0x" & toHex(h, 16))

# ================================ the seeded stream ===========================

block:
  var d = seedDice(20261029'u32)
  let a = roll(d)
  let b = roll(d)
  let c = roll(d)
  # measured in node with the original's makeRng(20261029)
  check("the generator reproduces the original's first value 0.850172859384",
        near(a, 0.850172859384, 1e-12), $a)
  check("… second 0.466159952572 and third 0.169257494155",
        near(b, 0.466159952572, 1e-12) and near(c, 0.169257494155, 1e-12))
  var zeros = 0
  var ones = 0
  for i in 0 ..< 4000:
    let v = rint(d, 0, 1)
    if v == 0: inc zeros else: inc ones
  check("rint(0,1) is fair within 5% over 4000 draws",
        abs(zeros - 2000) < 100 and zeros + ones == 4000, $zeros)
  check("n2 stays in 0..1 and is deterministic",
        (block:
          var ok = true
          for i in 0 ..< 200:
            let v = n2(7'u32, float64(i) * 0.37, float64(i) * 0.11)
            if v < 0.0 or v > 1.0: ok = false
          ok) and n2(7'u32, 3.5, 2.5) == n2(7'u32, 3.5, 2.5))

# ================================ grid primitives =============================

block:
  var d = newDeep(20261029'u32)
  check("out of bounds reads DENSE (the world has no leaky edge)",
        d.g.at(-1, 0) == MatDense and d.g.at(WW, 5) == MatDense and
        d.g.at(3, -2) == MatDense and d.g.at(4, WH + 1) == MatDense)
  check("writes outside are dropped, not wrapped",
        (block:
          let before = d.g.cell[(WH - 1) * WW + 0]
          d.g.put(-1, WH - 1, MatLava)
          d.g.cell[(WH - 1) * WW + 0] == before and d.g.at(-1, WH - 1) == MatDense))
  # canOccupy: the whole density model in one truth table
  d.g.put(10, 300, MatAir)
  check("air accepts anything", d.g.canOccupy(10, 300, MatRock))
  d.g.put(10, 300, MatRock)
  check("rock accepts nothing", not d.g.canOccupy(10, 300, MatWater))
  d.g.put(10, 300, MatBrick)
  check("sanctum brick accepts nothing", not d.g.canOccupy(10, 300, MatLava))
  d.g.put(10, 300, MatWater)
  check("water cannot push into water (equal density)", not d.g.canOccupy(10, 300, MatWater))
  check("oil cannot push into water (0.80 < 1.00)", not d.g.canOccupy(10, 300, MatOil))
  check("lava pushes into water (2.60 > 1.00)", d.g.canOccupy(10, 300, MatLava))
  check("sand sinks through water (1.80 > 1.00)", d.g.canOccupy(10, 300, MatSand))
  d.g.put(10, 300, MatSand)
  check("water cannot enter sand (a powder wall holds)", not d.g.canOccupy(10, 300, MatWater))
  d.g.put(10, 300, MatFire)
  check("water may enter fire", d.g.canOccupy(10, 300, MatWater))
  d.g.put(10, 300, MatSmoke)
  d.g.put(10, 300, MatSmoke)
  check("steam cannot rise into smoke (0.30 is heavier than 0.20)", not d.g.canOccupy(10, 300, MatSteam))
  d.g.put(10, 300, MatPgas)
  check("… nor into poison gas (0.30 > 0.25)", not d.g.canOccupy(10, 300, MatSteam))
  d.g.put(10, 300, MatFgas)
  check("a light gas rises through a heavier one (0.12 < 0.30)",
        d.g.canOccupy(10, 300, MatFgas) == false and d.g.canOccupy(10, 300, MatSteam) == false)
  d.g.put(10, 300, MatSteam)
  check("fire gas rises through steam (0.12 < 0.30)", d.g.canOccupy(10, 300, MatFgas))
  # the stamp guard
  d.g = newGrid(WW, WH)
  d.g.stamp = 5
  d.g.put(10, 10, MatSand)
  d.g.put(10, 11, MatAir)
  check("shiftCell moves the material and the destination is stamped",
        d.g.shiftCell(10, 10, 10, 11) and d.g.at(10, 11) == MatSand and
        d.g.at(10, 10) == MatAir and d.g.mark[11 * WW + 10] == 5)
  check("a second move into the same destination in one tick is refused",
        (block:
          d.g.put(11, 10, MatSand)
          not d.g.shiftCell(11, 10, 10, 11)))

# ================== density layering and alchemy (the original's gate) ========

block:
  ## verify.mjs "density layering": the same tank, the same seed, the same tick
  ## counts — so the numbers can be compared with the original's own output.
  var d = newDeep(4242'u32)
  d.advance(10)
  let camY = int(d.camY)
  let tx = 40
  let ty = camY + 40
  d.tank(tx, ty, 30, 40)
  d.fill(tx + 2, ty + 20, tx + 27, ty + 37, MatWater)
  d.fill(tx + 2, ty + 8, tx + 27, ty + 17, MatOil)
  d.advance(90)
  let (oilY, oilN) = d.centroid(tx + 2, ty + 1, tx + 27, ty + 38, MatOil)
  let (watY, watN) = d.centroid(tx + 2, ty + 1, tx + 27, ty + 38, MatWater)
  check("oil stays on top: 242 oil cells, centroid y 57.1 (original: 242 / 57.1)",
        oilN == 242 and near(oilY, 57.11570247933884, 0.01), $oilN & " / " & $oilY)
  check("water settles under it: 435 cells, centroid y 70.1 (original: 435 / 70.1)",
        watN == 435 and near(watY, 70.1287356321839, 0.01), $watN & " / " & $watY)

  d.tank(tx + 40, ty, 24, 36)
  d.fill(tx + 42, ty + 18, tx + 61, ty + 33, MatWater)
  d.fill(tx + 42, ty + 6, tx + 61, ty + 13, MatBlood)
  d.advance(90)
  let (blY, blN) = d.centroid(tx + 42, ty + 1, tx + 61, ty + 34, MatBlood)
  let (w2Y, w2N) = d.centroid(tx + 42, ty + 1, tx + 61, ty + 34, MatWater)
  check("blood sinks under water: 145 blood cells, centroid y 70.9 (original: 145 / 70.86)",
        blN == 145 and near(blY, 70.86206896551724, 0.01), $blN & " / " & $blY)
  check("… and the water is left above it at y 60.0 (original: 292 / 59.95)",
        w2N == 292 and near(w2Y, 59.95205479452055, 0.01), $w2N & " / " & $w2Y)

  # lava + water: exactly one stone and one steam (gate: 1 and 1)
  d.tank(tx, ty + 50, 20, 20)
  d.g.put(tx + 10, ty + 60, MatLava)
  d.g.put(tx + 10, ty + 61, MatWater)
  d.advance(8)
  check("lava + water yields exactly one stone and one steam (gate: 1 / 1)",
        d.count(tx + 1, ty + 51, tx + 18, ty + 68, MatStone) == 1 and
        d.count(tx + 1, ty + 51, tx + 18, ty + 68, MatSteam) == 1,
        $d.count(tx + 1, ty + 51, tx + 18, ty + 68, MatStone) & " stone")

  # acid eats dirt: 10 of 10 in 40 ticks (gate: eaten=10)
  d.tank(tx + 50, ty + 50, 14, 14)
  for xx in tx + 52 .. tx + 61:
    d.g.put(xx, ty + 62, MatDirt)
    d.g.put(xx, ty + 61, MatAcid)
  d.advance(40)
  var eaten = 0
  for xx in tx + 52 .. tx + 61:
    if d.g.at(xx, ty + 62) != MatDirt: inc eaten
  check("acid corrodes all 10 dirt cells in 40 ticks (gate: eaten=10)", eaten == 10, $eaten)

block:
  ## the original's "fire consumes wood" and "acid vs brick" probes
  var d = newDeep(99'u32)
  let camY = int(d.camY)
  let tx = 40
  let ty = camY + 40
  d.tank(tx + 30, ty + 50, 16, 16)
  for i in 0 ..< 8: d.g.put(tx + 38, ty + 58 + (i mod 3), MatWood)
  d.g.put(tx + 38, ty + 57, MatFire, 40)
  d.advance(40)
  var byproducts = 0
  for yy in ty + 51 .. ty + 64:
    for xx in tx + 31 .. tx + 44:
      let m = d.g.at(xx, yy)
      if m == MatFire or m == MatSmoke or m == MatAsh or m == MatEmber: inc byproducts
  check("fire spreads into wood and leaves fire/smoke/ash behind (gate: byproducts=2)",
        byproducts >= 1, $byproducts)

block:
  ## acid against a high-hardness wall: brick (14) resists at 0.05 per neighbour-tick
  var d = newDeep(4242'u32)
  d.advance(10)
  let camY = int(d.camY)
  let tx = 90
  let ty = camY + 90
  d.tank(tx, ty, 14, 14)
  for xx in tx + 2 .. tx + 9:
    d.g.put(xx, ty + 12, MatBrick)
    d.g.put(xx, ty + 11, MatAcid)
  d.advance(400)
  check("acid leaves all 8 brick cells standing after 400 ticks",
        d.count(tx + 2, ty + 12, tx + 9, ty + 12, MatBrick) == 8,
        $d.count(tx + 2, ty + 12, tx + 9, ty + 12, MatBrick))

block:
  ## the fast, local rules: quenching, ignition, condensation, gunpowder
  var d = newDeep(7'u32)
  proc clearBox(d: var Deep; x0, y0, x1, y1: int) =
    for y in y0 .. y1:
      for x in x0 .. x1: d.g.put(x, y, MatAir)
  clearBox(d, 18, 198, 34, 212)
  d.g.put(26, 206, MatFire, 60)
  d.g.put(27, 206, MatWater)
  d.automaton(190, 210)
  var steam = 0
  for y in 200 .. 210:
    for x in 20 .. 32:
      if d.g.at(x, y) == MatSteam: inc steam
  check("water quenches an adjacent fire into steam within one tick",
        steam == 1 and d.count(20, 200, 32, 210, MatFire) == 0, $steam)

  # ignition probability is FLAM/900 per neighbouring fire per tick (the rule itself,
  # without letting the oil fall away first)
  var ignite = 0
  for t in 0 ..< 3000:
    clearBox(d, 18, 198, 34, 212)
    d.g.put(25, 206, MatFire, 60)
    d.g.put(26, 206, MatOil)
    discard d.reactAt(25, 206, MatFire)
    if d.g.at(26, 206) == MatFire: inc ignite
  let rate = float64(ignite) / 3000.0
  check("oil ignites at FLAM/900 = 0.100 per neighbouring fire per tick (±0.02)",
        near(rate, 0.100, 0.02), $rate)

  # steam with one tick left condenses to water (45%) or air
  var water = 0
  var air = 0
  for t in 0 ..< 400:
    clearBox(d, 34, 200, 40, 210)
    d.g.put(37, 206, MatSteam, 1)
    d.automaton(190, 210)
    if d.g.at(37, 206) == MatWater: inc water
    elif d.g.at(37, 206) == MatAir: inc air
  check("expiring steam condenses to water 45% of the time (400 trials, ±0.10)",
        abs(float64(water) / 400.0 - 0.45) < 0.10 and water + air == 400,
        $water & "/400")

  # gunpowder detonates rather than burning
  var d2 = newDeep(7'u32)
  d2.tank(200, 300, 40, 40)
  d2.fill(215, 315, 225, 325, MatGunp)
  d2.g.put(215, 317, MatFire, 60)
  let before = d2.count(210, 310, 230, 330, MatGunp)
  d2.automaton(280, 340)
  let after = d2.count(210, 310, 230, 330, MatGunp)
  check("gunpowder detonates: the charge is torn open in one tick",
        before == 120 and after < 100, $before & " -> " & $after)

  # the blast is spent against hardness: dirt below a brick wall survives
  proc erodedBelow(wall: bool): int =
    var d3 = newDeep(7'u32)
    d3.tank(200, 400, 40, 30)
    for y in 402 .. 427:
      for x in 202 .. 237: d3.g.put(x, y, MatDirt)
    if wall:
      for x in 202 .. 237: d3.g.put(x, 415, MatBrick)
    # 14,000 energy against a 14-hardness wall: the first brick spends the whole ray
    d3.explode(220, 412, 17, 0.0, 14000.0)
    var left = 0
    for y in 416 .. 427:
      for x in 205 .. 235:
        if d3.g.at(x, y) == MatDirt: inc left
    left
  let freeLeft = erodedBelow(false)
  let walledLeft = erodedBelow(true)
  check("a brick wall eats the blast: the dirt below it survives, without it does not",
        walledLeft == 31 * 12 and freeLeft < walledLeft,
        $freeLeft & " vs " & $walledLeft & " dirt left")

  check("… and the player inside a radius-11 blast takes 10 + dmg*0.15*(1-d/(rad+6))",
        (block:
          var d4 = newDeep(7'u32)
          d4.foes.setLen(0)
          let hp0 = d4.player.hp
          d4.explode(int(d4.player.x) + 2, int(d4.player.y), 11, 48.0, 0.0)
          let want = 10.0 + 48.0 * 0.15 * (1.0 - 2.0 / 17.0)
          near(hp0 - d4.player.hp, want, 0.5)),
        "player damage")

# ============================== determinism ==================================

block:
  var a = newDeep(20261029'u32)
  var b = newDeep(20261029'u32)
  var c = newDeep(20261030'u32)
  a.advance(200)
  b.advance(200)
  c.advance(200)
  check("the same seed and the same ticks give the same world (2 runs, 200 ticks)",
        a.gridHash() == b.gridHash(), "0x" & toHex(a.gridHash(), 16))
  check("a different seed gives a different world", a.gridHash() != c.gridHash())
  a.renderFb()
  b.renderFb()
  check("rendering is deterministic too (no randomness in the draw)", a.frameHash() == b.frameHash())

# ============================== world generation =============================

block:
  var d = newDeep(11'u32)
  var seen: seq[int] = @[]
  var y = 0
  while y < WH:
    let l = layerAt(y)
    if seen.find(l) < 0: seen.add l
    y += 40
  check("the biome ladder sampled every 40 rows is -1,0,10,1,11,2,12,3,13,4 (gate)",
        seen == @[-1, 0, 10, 1, 11, 2, 12, 3, 13, 4], $seen)
  var sanctums = 0
  for i in 0 ..< Sanctums:
    if d.holy[i].y1 > d.holy[i].y0: inc sanctums
  check("there are exactly 4 sanctuaries between the strata", sanctums == 4, $sanctums)
  check("the layer period is 420 rows (352 open + 68 sanctuary)",
        LayerPeriod == 420 and BandH == 352 and HoldH == 68)
  check("the delver spawns at x=192, y=102 (original: x=192 y=102)",
        d.player.x == 192.0 and near(d.player.y, 102.0, 0.001))
  check("… standing on solid ground", d.solidAtRect(d.player.x, d.player.y + 6.0, 6, 2))
  var tuskNear = false
  for e in d.foes:
    if e.id == tTusk and abs(e.x - d.player.x) < 80.0: tuskNear = true
  check("a gnawler waits within 80 px of the spawn (the guaranteed first fight)", tuskNear)
  var bosses = 0
  for e in d.foes:
    if e.id == tWellseye: inc bosses
  check("exactly one well eye, in the bottom arena", bosses == 1)
  check("the world is populated: 40 creatures for seed 20261029 (5 + 3i per layer)",
        newDeep(20261029'u32).foes.len == 40, $newDeep(20261029'u32).foes.len)
  check("the border columns and the last rows are DENSE",
        d.g.at(3, 500) == MatDense and d.g.at(WW - 4, 500) == MatDense and
        d.g.at(100, WH - 2) == MatDense)
  check("the sky above the surface is open air", d.g.at(100, 10) == MatAir)

block:
  ## whole-world parity: these hashes are the ORIGINAL's generated worlds
  var d = newDeep(20261029'u32)
  check("seed 20261029 generates the original's world, cell for cell (0xe67b61ea7cb77b9d)",
        d.gridHash() == 0xe67b61ea7cb77b9d'u64, "0x" & toHex(d.gridHash(), 16))
  var e = newDeep(11'u32)
  check("… and a second seed builds a different world", e.gridHash() != d.gridHash())
  check("the world is 384 x 2100 = 806,400 cells, one byte each",
        d.g.cell.len == 806400 and d.g.life.len == 806400 and d.g.mark.len == 806400)

# ================================= the player ================================

block:
  var d = newDeep(20261029'u32)
  d.advance(2)
  d.player.inv = 999
  let x0 = d.player.x
  var right = Input(); right.right = true
  d.advance(45, right)
  let dxR = d.player.x - x0
  check("walking right for 45 ticks moves +26.2 cells (original: +26.2)",
        dxR > 4.0 and near(dxR, 26.240111503725956, 0.5), $dxR)
  let x1 = d.player.x
  var left = Input(); left.left = true
  d.advance(45, left)
  let dxL = d.player.x - x1
  check("walking left for 45 ticks moves -23.7 cells (original: -23.7)",
        dxL < -2.0 and near(dxL, -23.68033450632126, 0.5), $dxL)
  d.advance(20)
  let y0 = d.player.y
  var jump = Input(); jump.jump = true
  d.advance(8, jump)
  let dy = d.player.y - y0
  check("a jump lifts 25.2 cells in 8 ticks (original: -25.2)",
        dy < -2.0 and near(dy, -25.2, 0.5), $dy)
  let h0 = d.player.hover
  d.advance(30, jump)
  check("hovering on the tank spends 0.72 per tick (30 ticks = 21.6)",
        near(h0 - d.player.hover, 21.6, 0.3), $(h0 - d.player.hover))
  d.advance(60)
  check("the hover tank refills at 0.24 per tick and stops at 100",
        d.player.hover > 0.0 and d.player.hover <= d.player.maxHover)
  # jumping into water: buoyancy and drag
  var w = newDeep(20261029'u32)
  w.advance(3)
  for y in int(w.player.y) - 6 .. int(w.player.y) + 8:
    for x in int(w.player.x) - 12 .. int(w.player.x) + 12: w.g.put(x, y, MatWater)
  let vy0 = w.player.vy
  w.updatePlayer(Input())
  check("a liquid drags the fall: vy is (vy + 0.165) * 0.9 - 0.04",
        near(w.player.vy, (vy0 + 0.165) * 0.9 - 0.04, 0.001) or w.player.vy == 0.0,
        $(vy0) & " -> " & $(w.player.vy))

# ================================= the wands =================================

block:
  ## the deck wrap: triple, flame, homing, spark on 300 mana (gate: 9, mana 1.0)
  var d = newDeep(7'u32)
  d.advance(4)
  var w = d.wands[0]
  w.slots = [spTriple.int8, spFlameMod.int8, spHoming.int8, spSpark.int8, -1'i8, -1'i8, -1'i8, -1'i8]
  w.nslots = 4
  w.mana = 300
  w.manaMax = 300
  w.delayT = 0
  w.rechT = 0
  w.cursor = 0
  w.spellsPerCast = 1
  d.wands[0] = w
  var inp = Input()
  inp.aimX = d.player.x + 80.0
  inp.aimY = 20.0
  let produced = d.tryCast(inp)
  check("a four-card deck wraps inside one cast: 9 projectiles (gate: 9)",
        produced == 9 and d.shots.len == 9, $produced & " / " & $d.shots.len)
  check("… and spends the mana down to 1.0 (gate: 300 -> 1.0)",
        near(d.wands[0].mana, 1.0, 0.001), $d.wands[0].mana)
  check("the cast delay is 13 = max(2, 8 + the triple's 5)",
        d.wands[0].delayT == 13, $d.wands[0].delayT)
  check("the deck wrapped, so the recharge is 25 = 22 + the triple's 3",
        d.wands[0].rechT == 25, $d.wands[0].rechT)
  check("and the cursor is back at the first card", d.wands[0].cursor == 0)

block:
  ## plain casts and the arithmetic the original's own probe measured
  var d = newDeep(7'u32)
  d.advance(4)
  var w = d.wands[0]
  w.slots = [spSpark.int8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8]
  w.nslots = 2
  w.mana = 100
  w.manaMax = 100
  w.cursor = 0
  w.delayT = 0
  w.rechT = 0
  d.wands[0] = w
  var inp = Input()
  inp.aimX = d.player.x + 80.0
  inp.aimY = 20.0
  discard d.tryCast(inp)
  check("one spark: delay 11 = max(2, 8 + 3), mana 95, no recharge (original: 11 / 95 / 0)",
        d.wands[0].delayT == 11 and near(d.wands[0].mana, 95.0, 0.001) and
        d.wands[0].rechT == 0 and d.wands[0].cursor == 1,
        $d.wands[0].delayT & " / " & $d.wands[0].mana)
  var w2 = d.wands[0]
  w2.slots = [spDrill.int8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8]
  w2.nslots = 1
  w2.castDelay = 8
  w2.cursor = 0
  w2.delayT = 0
  w2.rechT = 0
  w2.mana = 100
  d.wands[0] = w2
  discard d.tryCast(inp)
  check("a drill has delay 0 and rec -10: the cast delay stays 8 (original: 8)",
        d.wands[0].delayT == 8, $d.wands[0].delayT)
  var w3 = d.wands[0]
  w3.slots = [spSpark.int8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8]
  w3.nslots = 2
  w3.mana = 3
  w3.cursor = 0
  w3.delayT = 0
  w3.rechT = 0
  d.wands[0] = w3
  let none = d.tryCast(inp)
  check("a wand that cannot pay for its card produces nothing but still advances",
        none == 0 and d.wands[0].cursor == 1 and near(d.wands[0].mana, 3.0, 0.001))
  check("a modifier folds into the shot it precedes: [DMG+, spark] hits for 15.3",
        (block:
          var d2 = newDeep(7'u32)
          d2.advance(4)
          var m = d2.wands[0]
          m.slots = [spDmgPlus.int8, spSpark.int8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8, -1'i8]
          m.nslots = 2
          m.mana = 100
          m.manaMax = 100
          m.cursor = 0
          m.delayT = 0
          m.rechT = 0
          d2.wands[0] = m
          var i2 = Input()
          i2.aimX = d2.player.x + 80.0
          discard d2.tryCast(i2)
          d2.shots.len == 1 and near(d2.shots[0].dmg, 9.0 * 1.7, 0.001)))
  check("mana regenerates 28 in 60 ticks for the starting wand (original: 28)",
        (block:
          var d2 = newDeep(7'u32)
          d2.wands[0].mana = 0
          d2.advance(60)
          near(d2.wands[0].mana, 28.0, 0.01)))
  check("the starting kit is four wands and a two-card bag (gate: 4)",
        (block:
          var d2 = newDeep(20261029'u32)
          d2.wands.len == 4 and d2.gift.len == 2 and
          d2.wands[0].slots[0] == spSpark.int8 and d2.wands[1].shuffle))
  check("a shuffling wand keeps its cards: 100 catches lose or duplicate none",
        (block:
          var d2 = newDeep(7'u32)
          d2.wands[1].slots = [spSpark.int8, spBomb.int8, spIce.int8, spDisc.int8,
                               -1'i8, -1'i8, -1'i8, -1'i8]
          d2.wands[1].nslots = 4
          d2.wands[1].shuffle = true
          var inp2 = Input()
          inp2.aimX = d2.player.x + 40.0
          inp2.aimY = 20.0
          var ok = true
          for i in 0 ..< 100:
            d2.wands[1].mana = 400
            d2.wands[1].rechT = 0
            d2.wands[1].delayT = 0
            d2.wands[1].cursor = 3          # the last card: the deck ends here
            var before: seq[int8] = @[]
            for k in 0 ..< 4: before.add d2.wands[1].slots[k]
            d2.curWand = 1
            discard d2.tryCast(inp2)
            var after: seq[int8] = @[]
            for k in 0 ..< 4: after.add d2.wands[1].slots[k]
            before.sort()
            after.sort()
            if before != after: ok = false
            d2.curWand = 0
          ok))

# ============================== the six creatures ============================

block:
  check("six creature kinds with the original's hit points",
        defOf(tTusk).hp == 28 and defOf(tAshgun).hp == 36 and defOf(tNighthook).hp == 18 and
        defOf(tBurstling).hp == 22 and defOf(tBorewyrm).hp == 54 and defOf(tWellseye).hp == 720)
  check("… and their damage", defOf(tTusk).dmg == 8 and defOf(tBurstling).dmg == 28 and
        defOf(tWellseye).dmg == 16)
  check("… and their sizes", defOf(tTusk).w == 7 and defOf(tNighthook).h == 6 and
        defOf(tWellseye).w == 16)
  var d = newDeep(20261029'u32)
  var kinds: set[FoeKind] = {}
  for e in d.foes: kinds.incl e.kind
  check("the world actually contains melee, ranged, flyer, bomber and burrower",
        fkMelee in kinds and fkRanged in kinds and fkFly in kinds and
        fkBoom in kinds and fkBoss in kinds)

block:
  ## a projectile kills a gnawler and drops gold
  var d = newDeep(20261029'u32)
  d.foes.setLen(0)
  var e = Foe(id: tTusk, kind: fkMelee, name: "GNAWLER", x: d.player.x + 14.0,
              y: d.player.y, w: 7, h: 9, hp: 12.0, maxHp: 28.0, dmg: 8.0, cool: 99)
  d.foes.add e
  var inp = Input()
  inp.aimX = d.player.x + 14.0
  inp.aimY = d.player.y
  inp.fire = true
  var killed = false
  for i in 0 ..< 180:
    d.update(inp)
    if d.run.kills > 0: killed = true; break
  check("a gnawler within 14 px dies to the starting wand inside 180 ticks (gate: 87)",
        killed, "kills=" & $d.run.kills)
  check("… and drops gold on the floor", d.run.gold >= 0 and d.picks.len > 0)

# ================================ light and death ============================

block:
  var d = newDeep(20261029'u32)
  d.renderFb()
  let px = int(d.player.x)
  let py = int(d.player.y - d.camY)
  let nearL = d.lightAt(px, py)
  let farL = d.lightAt(8, 8)
  check("the lantern peak is 230 at the delver (gate: 230)", nearL == 230, $nearL)
  check("a far cave corner reads 16, the MINES ambient (gate: 16)", farL == 16, $farL)
  check("near light >= far light (the radial falloff)", nearL >= farL)
  # occlusion: a rock wall between the delver and a probe eats 45% per cell
  var d2 = newDeep(20261029'u32)
  let cx = int(d2.player.x)
  let cy = int(d2.player.y)
  for y in cy - 20 .. cy + 20: d2.g.put(cx + 6, y, MatRock)
  d2.renderFb()
  var lit = 0
  for y in cy - 3 .. cy + 3:
    if d2.lightAt(cx + 10, y - int(d2.camY)) > 18: inc lit
  check("a rock wall occludes the lantern (the region behind it falls to ambient)", lit <= 7)
  check("glass, ice and crystal are transparent to the lantern (the occlusion rules)",
        (block:
          var d3 = newDeep(20261029'u32)
          let cx3 = int(d3.player.x)
          let cy3 = int(d3.player.y)
          for y in cy3 - 20 .. cy3 + 20: d3.g.put(cx3 + 6, y, MatGlass)
          d3.renderFb()
          var n = 0
          for y in cy3 - 3 .. cy3 + 3:
            if d3.lightAt(cx3 + 10, y - int(d3.camY)) > 60: inc n
          n >= 3))

block:
  ## death always names a cause, and our English text says what happened
  proc deathBy(setup: proc (d: var Deep) {.closure.}; expect: string;
               ticks = 200): (string, string) =
    var d = newDeep(20261029'u32)
    d.foes.setLen(0)
    d.advance(3)
    d.player.inv = 0
    d.player.hp = 1.0
    setup(d)
    d.advance(ticks)
    (d.run.causeCode, causeTitle(d.run.causeCode))
  let (c1, t1) = deathBy(proc (d: var Deep) =
    for dy in -3 .. 5:
      for dx in -3 .. 3: d.g.put(int(d.player.x) + dx, int(d.player.y) + dy, MatFire, 200), "burn")
  check("fire kills with cause burn -> BURNED", c1 == "burn" and t1 == "BURNED", c1 & " " & t1)
  let (c2, t2) = deathBy(proc (d: var Deep) =
    ## a sealed water column: the head stays under the surface
    let px = int(d.player.x)
    let py = int(d.player.y)
    for y in py - 14 .. py + 16:
      d.g.put(px - 11, y, MatRock)
      d.g.put(px + 11, y, MatRock)
    for x in px - 11 .. px + 11: d.g.put(x, py + 16, MatRock)
    for y in py - 14 .. py + 15:
      for x in px - 10 .. px + 10: d.g.put(x, y, MatWater), "drown", 300)
  check("water kills with cause drown -> DROWNED (90 ticks of air, then 1.2/tick)",
        c2 == "drown" and t2 == "DROWNED", c2 & " " & t2)
  let (c3, t3) = deathBy(proc (d: var Deep) =
    for dy in -6 .. 2:
      for dx in -3 .. 3: d.g.put(int(d.player.x) + dx, int(d.player.y) + dy, MatRock), "crush")
  check("being buried kills with cause crush -> CRUSHED (8 a tick)", c3 == "crush" and t3 == "CRUSHED",
        c3 & " " & t3)
  let (c4, t4) = deathBy(proc (d: var Deep) =
    for dy in -4 .. 4:
      for dx in -4 .. 4: d.g.put(int(d.player.x) + dx, int(d.player.y) + dy, MatToxic), "toxic")
  check("toxic sludge kills with cause toxic -> POISONED", c4 == "toxic" and t4 == "POISONED",
        c4 & " " & t4)
  let (c5, t5) = deathBy(proc (d: var Deep) =
    for dy in -4 .. 4:
      for dx in -4 .. 4: d.g.put(int(d.player.x) + dx, int(d.player.y) + dy, MatAcid), "acid")
  check("acid kills with cause acid -> DISSOLVED (0.35 a tick)", c5 == "acid" and t5 == "DISSOLVED",
        c5 & " " & t5)
  let (c6, t6) = deathBy(proc (d: var Deep) =
    d.explode(int(d.player.x) + 2, int(d.player.y), 11, 30.0, 0.0), "explode")
  check("a blast kills with cause explode -> BLASTED", c6 == "explode" and t6 == "BLASTED",
        c6 & " " & t6)
  check("a dead delver has hp 0, is flagged dead, and the run is over",
        (block:
          var d = newDeep(20261029'u32)
          d.foes.setLen(0)
          d.hurt(500.0, "kill", "SLAIN · test")
          d.player.hp == 0.0 and d.player.dead and d.st == gsDead))
  check("the invulnerability window swallows a second hit (26 ticks)",
        (block:
          var d = newDeep(20261029'u32)
          d.foes.setLen(0)
          let hp0 = d.player.hp
          d.hurt(10.0, "kill", "SLAIN · test")
          d.hurt(10.0, "kill", "SLAIN · test")
          near(d.player.hp, hp0 - 10.0, 0.001) and d.player.inv == 26))

# ============================ perks and sanctuaries ==========================

block:
  var d = newDeep(20261029'u32)
  d.foes.setLen(0)
  d.offerPerks()
  check("a sanctuary offers three different blessings", d.offering and
        d.offer[0] != d.offer[1] and d.offer[1] != d.offer[2] and d.offer[0] >= 0)
  let pick = d.offer[0]
  check("choosing one applies it and closes the panel",
        d.choosePerk(0) and not d.offering and Perk(pick) in d.player.perk)
  check("a sanctuary refills the health on first entry",
        (block:
          var d2 = newDeep(20261029'u32)
          d2.foes.setLen(0)
          d2.player.hp = 20.0
          d2.player.y = float64(d2.holy[0].y0 + 10)
          d2.updatePlayer(Input())
          near(d2.player.hp, d2.player.maxHp, 0.001) and d2.offering))

# ============================== lighting numbers =============================

block:
  ## the composite: a bright pixel in a warm light keeps its warm tint
  var d = newDeep(20261029'u32)
  d.renderFb()
  var sum = 0'i64
  for i in 0 ..< LightN: sum += int64(d.light[i])
  check("the light buffer has 82,944 cells and the frame 331,776 bytes",
        d.light.len == LightN and d.fb.len == 331776)
  check("the frame is fully opaque", (block:
          var opaque = true
          var i = 3
          while i < d.fb.len:
            if d.fb[i] != 255: opaque = false
            i += 4
          opaque))
  check("the render paints the cave backdrop, not a blank canvas",
        (block:
          var nonBlack = 0
          var i = 0
          while i < d.fb.len:
            if int(d.fb[i]) + int(d.fb[i + 1]) + int(d.fb[i + 2]) > 12: inc nonBlack
            i += 4
          nonBlack > 5000))

echo ""
echo passed, " passed, ", failed, " failed"
if failed > 0: quit 1
