## DNA — the double helix drawn from typed geometry: every bead, rung and ribbon
## is a point in ångström, tilted, perspective-divided and rolled by the procs
## below, then emitted as Canvas draw commands. The sequence is HBB, human beta-globin.

let bg = 0xFF070A12'u32
let panelBg = 0xFF0D1322'u32
let panel2 = 0xFF151C2E'u32
let dim = 0xFF66708A'u32
let muted = 0xFF98A2B8'u32
let ink = 0xFFF1F5FC'u32
let amber = 0xFFFFB347'u32
let amberLt = 0xFFFFD79B'u32
let cyan = 0xFF54E4D6'u32
let cyanLt = 0xFFB4F6EF'u32
let teal = 0xFF2EC4B6'u32
let rose = 0xFFE8719B'u32
let hbb = "ATGGTGCATCTGACTCCTGAGGAGAAGTCT"

type V3 = object
  ## After the tilt, perspective divide and roll: x, y in ångström; z the depth.
  x, y, z: float

type Item = object
  ## One drawable piece with its depth, so the painter's sort can order it.
  kind: int ## 2 backbone segment, 0 rung half, 1 nucleotide bead
  x1, y1, x2, y2, r, w, z: float
  c, c2: uint32
proc comp(c: char): char =
  if c == 'A': 'T'
  elif c == 'T': 'A'
  elif c == 'G': 'C'
  elif c == 'C': 'G'
  else: 'N'
proc beadInk(c: char): uint32 =
  if c == 'A': amber
  elif c == 'T': amberLt
  elif c == 'G': cyan
  elif c == 'C': cyanLt
  else: muted
proc rungInk(c: char): uint32 =
  ## A-T rungs are amber, G-C rungs cyan.
  if c == 'A' or c == 'T': amber else: cyan
proc clampf(x, lo, hi: float): float =
  if x < lo: lo elif x > hi: hi else: x
proc maxf(a, b: float): float =
  if a > b: a else: b
proc label(d: var Draw; x, y, size: float; c: uint32; s: string; weight = 400) =
  ## Text on the stage with a dark halo, so a label stays readable over a ribbon.
  let ox = [1.0, -1.0, 0.0, 0.0]
  let oy = [0.0, 0.0, 1.0, -1.0]
  for i in 0 .. 3:
    d = d.text(x + ox[i], y + oy[i], size, fade(bg, 0.82), s, weight)
  d = d.text(x, y, size, c, s, weight)
proc fade(c: uint32; a: float): uint32 =
  (c and 0x00FFFFFF'u32) or (uint32(int(clampf(a, 0.0, 1.0) * 255.0 + 0.5)) shl 24)
proc baseInk(c: char; hot: bool): uint32 =
  fade(beadInk(c), (if hot: 1.0 else: 0.55))
proc codonAt(k: int): string =
  let i = k * 3
  if i + 2 < hbb.len: hbb[i .. i + 2] else: ""
proc depthFade(z, tl: float): float =
  ## Far pieces dim: the depth cue that makes the back of the helix read behind.
  let zm = 50.0 * abs(sin(tl)) + 10.0
  0.40 + 0.60 * (0.5 - 0.5 * clampf(z / zm, -1.0, 1.0))
proc project(u, v, w, tl: float): V3 =
  ## (u, v, w) in ångström: across the helix, along it, across it again. Tilt about
  ## the screen x axis, divide by a 170 Å focal length, then roll -0.15 rad.
  let y2 = v * cos(tl) - w * sin(tl)
  let z2 = v * sin(tl) + w * cos(tl)
  let k = 170.0 / (170.0 + z2)
  let rl = -0.15
  V3(x: (u * cos(rl) - y2 * sin(rl)) * k, y: (u * sin(rl) + y2 * cos(rl)) * k, z: z2)
proc helix(spin, tilt, pick: int): string =
  ## The picture: 10.5 bp per turn, 3.4 Å rise, 10 Å radius, two antiparallel strands.
  let n = hbb.len
  let W = 816.0
  let H = 632.0
  let cx = 352.0
  let cy = 300.0
  let S = 5.1 # pixels per ångström
  let semi = float(n - 1) * 3.4 / 2.0
  let tl = float(tilt) * PI / 180.0
  let th0 = float(spin) * PI / 180.0
  let tw = 2.0 * PI / 10.5
  var d = Draw()
  d = d.radialRect(0.0, 0.0, W, H, 0xFF121C31'u32, bg, cx, cy, 640.0, 0.0)
  d = d.radialRect(0.0, 0.0, W, H, 0x00000000'u32, 0x5A04060C'u32, cx, cy, 470.0, 0.0)
  ## the rotation axis, and the two backbones sampled twice per base pair so the
  ## ribbons curve instead of faceting
  var pv = project(0.0, -semi, 0.0, tl)
  for k in 1 .. 12:
    let pw = project(0.0, -semi + float(k) * 2.0 * semi / 12.0, 0.0, tl)
    d = d.line(cx + pv.x * S, cy + pv.y * S, cx + pw.x * S, cy + pw.y * S, fade(ink, 0.06), 1.0)
    pv = pw
  var pa: seq[V3] = @[]
  var pb: seq[V3] = @[]
  for j in 0 .. 2 * (n - 1):
    let f = float(j) * 0.5
    let y = (f - float(n - 1) / 2.0) * 3.4
    let th = f * tw + th0
    pa.add project(10.0 * cos(th), y, 10.0 * sin(th), tl)
    pb.add project(10.0 * cos(th + 2.36), y, 10.0 * sin(th + 2.36), tl)
  ## the halo behind the base pair the app is reading
  let ga = pa[2 * pick]
  let gb = pb[2 * pick]
  let gx = cx + (ga.x + gb.x) / 2.0 * S
  let gy = cy + (ga.y + gb.y) / 2.0 * S
  d = d.circle(gx, gy, 32.0, fade(amber, 0.09))
  d = d.circle(gx, gy, 17.0, fade(amber, 0.14))
  var parts: seq[Item] = @[]
  for j in 0 ..< pa.len - 1:
    let za = (pa[j].z + pa[j + 1].z) / 2.0
    let zb = (pb[j].z + pb[j + 1].z) / 2.0
    parts.add Item(kind: 2, x1: cx + pa[j].x * S, y1: cy + pa[j].y * S,
                   x2: cx + pa[j + 1].x * S, y2: cy + pa[j + 1].y * S,
                   w: 6.2 * 170.0 / (170.0 + za), z: za,
                   c: fade(teal, 0.26 + 0.66 * depthFade(za, tl)))
    parts.add Item(kind: 2, x1: cx + pb[j].x * S, y1: cy + pb[j].y * S,
                   x2: cx + pb[j + 1].x * S, y2: cy + pb[j + 1].y * S,
                   w: 6.2 * 170.0 / (170.0 + zb), z: zb,
                   c: fade(rose, 0.26 + 0.66 * depthFade(zb, tl)))
  for i in 0 ..< n:
    let a = pa[2 * i]
    let b = pb[2 * i]
    let ax = cx + a.x * S
    let ay = cy + a.y * S
    let bx = cx + b.x * S
    let by = cy + b.y * S
    let zz = (a.z + b.z) / 2.0
    let hot = i == pick
    let rc = if hot: ink else: rungInk(hbb[i])
    let al = depthFade(zz, tl) * (if hot: 1.0 else: 0.9)
    let wd = 2.8 * 170.0 / (170.0 + zz) * (if hot: 1.9 else: 1.0)
    ## two halves with the hydrogen-bond gap between them
    parts.add Item(kind: 0, x1: ax, y1: ay, x2: ax + (bx - ax) * 0.46, y2: ay + (by - ay) * 0.46,
                   w: wd, z: zz, c: fade(rc, al))
    parts.add Item(kind: 0, x1: bx, y1: by, x2: bx + (ax - bx) * 0.46, y2: by + (ay - by) * 0.46,
                   w: wd, z: zz, c: fade(rc, al))
    parts.add Item(kind: 1, x1: ax, y1: ay, r: (if hot: 5.2 else: 3.9) * 170.0 / (170.0 + a.z),
                   z: a.z, c: fade(beadInk(hbb[i]), 0.45 + 0.55 * depthFade(a.z, tl)),
                   c2: fade(ink, 0.7))
    parts.add Item(kind: 1, x1: bx, y1: by, r: (if hot: 5.2 else: 3.9) * 170.0 / (170.0 + b.z),
                   z: b.z, c: fade(beadInk(comp(hbb[i])), 0.45 + 0.55 * depthFade(b.z, tl)),
                   c2: fade(ink, 0.7))
  ## painter's algorithm: the farthest piece first, so the near backbone crosses
  ## in front of the far one and the rungs pass behind it
  var k = 1
  while k < parts.len:
    var j = k
    while j > 0 and parts[j].z > parts[j - 1].z:
      swap(parts[j], parts[j - 1])
      dec j
    inc k
  for it in parts:
    if it.kind == 1:
      d = d.circle(it.x1, it.y1, it.r, it.c)
      d = d.circle(it.x1, it.y1, it.r * 0.4, it.c2)
    else:
      d = d.line(it.x1, it.y1, it.x2, it.y2, it.c, it.w)
  ## the hydrogen bonds of the highlighted pair: two for A-T, three for G-C
  let ax = cx + pa[2 * pick].x * S
  let ay = cy + pa[2 * pick].y * S
  let bx = cx + pb[2 * pick].x * S
  let by = cy + pb[2 * pick].y * S
  let e1x = ax + (bx - ax) * 0.46
  let e1y = ay + (by - ay) * 0.46
  let e2x = bx + (ax - bx) * 0.46
  let e2y = by + (ay - by) * 0.46
  let bonds = if hbb[pick] == 'A' or hbb[pick] == 'T': 2 else: 3
  for j in 0 ..< bonds:
    let f = if bonds == 2: 0.38 + 0.24 * float(j) else: 0.28 + 0.22 * float(j)
    let px = e1x + (e2x - e1x) * f
    let py = e1y + (e2y - e1y) * f
    let L = clampf(sqrt((e2x - e1x) * (e2x - e1x) + (e2y - e1y) * (e2y - e1y)), 0.001, 1e9)
    let nx = -(e2y - e1y) / L * 2.6
    let ny = (e2x - e1x) / L * 2.6
    d = d.line(px - nx, py - ny, px + nx, py + ny, fade(ink, 0.9), 1.5)
  ## the callout to the pair being read
  let mx = (ax + bx) / 2.0
  let my = (ay + by) / 2.0
  let ly = clampf(my - 8.0, 22.0, H - 46.0)
  d = d.line(mx - 18.0, my - 12.0, mx - 96.0, ly + 6.0, fade(amber, 0.45), 1.0)
  label(d, mx - 200.0, ly, 12.0, amber,
        "base " & $(pick + 1) & "   " & $hbb[pick] & " = " & $comp(hbb[pick]), 700)
  label(d, mx - 200.0, ly + 16.0, 11.0, muted,
        "codon " & $(pick div 3 + 1) & "   " & codonAt(pick div 3), 400)
  ## one turn, measured on the projected axis: 10.5 bp = 35.7 Å
  let q0 = project(0.0, (5.0 - float(n - 1) / 2.0) * 3.4, 0.0, tl)
  let q1 = project(0.0, (5.0 - float(n - 1) / 2.0) * 3.4 + 35.7, 0.0, tl)
  let y0 = cy + q0.y * S
  let y1 = cy + q1.y * S
  let bx0 = 648.0
  d = d.line(maxf(cx + pa[10].x * S, cx + pb[10].x * S) + 10.0, y0, bx0, y0, fade(muted, 0.4), 1.0)
  d = d.line(maxf(cx + pa[31].x * S, cx + pb[31].x * S) + 10.0, y1, bx0, y1, fade(muted, 0.4), 1.0)
  d = d.line(bx0, y0, bx0, y1, fade(muted, 0.6), 1.2)
  d = d.line(bx0 - 6.0, y0, bx0 + 6.0, y0, fade(muted, 0.6), 1.2)
  d = d.line(bx0 - 6.0, y1, bx0 + 6.0, y1, fade(muted, 0.6), 1.2)
  label(d, bx0 + 14.0, (y0 + y1) / 2.0 - 8.0, 12.0, muted, "one turn · 10.5 bp", 600)
  ## antiparallel: the teal strand is 5' at the top and 3' at the bottom, the rose
  ## strand the other way round, so the end labels state what the panel explains
  let topY = maxf(maxf(cy + pa[0].y * S, cy + pb[0].y * S) - 30.0, 4.0)
  let botY = maxf(cy + pa[^1].y * S, cy + pb[^1].y * S) + 8.0
  label(d, cx + pa[0].x * S + 10.0, topY, 12.0, teal, "5'", 700)
  label(d, cx + pb[0].x * S - 26.0, topY, 12.0, rose, "3'", 700)
  label(d, cx + pa[^1].x * S + 10.0, botY, 12.0, teal, "3'", 700)
  label(d, cx + pb[^1].x * S - 26.0, botY, 12.0, rose, "5'", 700)
  ## the width scale, at the same pixels per ångström as the model
  d = d.line(34.0, 30.0, 34.0 + 20.0 * S, 30.0, fade(muted, 0.55), 1.2)
  d = d.line(34.0, 25.0, 34.0, 35.0, fade(muted, 0.55), 1.2)
  d = d.line(34.0 + 20.0 * S, 25.0, 34.0 + 20.0 * S, 35.0, fade(muted, 0.55), 1.2)
  label(d, 34.0, 42.0, 11.0, muted, "2 nm across the helix", 400)
  d.cmds

view Dna
  state spin = 24
  state tilt = 16
  state pick = 19

  Column(fill = bg, grow = 1, pad = 22px, gap = 10px):
    Row(height = 54px, gap = 16px):
      Column(gap = 2px):
        Text "DNA", size = 32px, weight = 700, color = ink
        Text "the double helix · HBB, human beta-globin", size = 12px, color = muted
      Row(grow = 1)
      Text "spin {spin}° · tilt {tilt}° · base {pick + 1}", size = 12px, color = muted
      Button "Spin", fill = panel2, color = ink, radius = 9px, pad = 7px:
        on tap: spin += 30
      Button "-10°", fill = panel2, color = ink, radius = 9px, pad = 7px:
        on tap: spin -= 10
      Button "+10°", fill = panel2, color = ink, radius = 9px, pad = 7px:
        on tap: spin += 10
      Button "Tilt", fill = panel2, color = ink, radius = 9px, pad = 7px:
        on tap: tilt = (if tilt > 0: 0 else: 16)

    Row(grow = 1, gap = 20px):
      Canvas(width = 816, height = 632, draw = helix(spin, tilt, pick))
      Panel(width = 400px, height = 632px, fill = panelBg, radius = 18px, pad = 20px, gap = 12px):
        Text "ANATOMY", size = 10px, weight = 700, color = dim
        Row(gap = 8px):
          Panel(width = 6px, height = 6px, radius = 3px, fill = teal)
          Text "Antiparallel strands", size = 15px, weight = 600, color = ink
        Text "The two sugar-phosphate backbones run in opposite directions: the teal strand reads 5'→3' down the axis, the rose strand reads 5'→3' the other way.", size = 12px, color = muted, lineHeight = 1.5
        Row(gap = 8px):
          Panel(width = 6px, height = 6px, radius = 3px, fill = amber)
          Text "Base pairs", size = 15px, weight = 600, color = ink
        Text "A pairs with T through two hydrogen bonds, G with C through three. A purine always faces a pyrimidine, so every rung is the same width.", size = 12px, color = muted, lineHeight = 1.5
        Row(gap = 8px):
          Panel(width = 6px, height = 6px, radius = 3px, fill = cyan)
          Text "The turn", size = 15px, weight = 600, color = ink
        Text "10.5 base pairs complete one turn of the helix; each step along the axis is 3.4 Å, and the molecule is 2 nm across.", size = 12px, color = muted, lineHeight = 1.5
        Text "MEASUREMENTS", size = 10px, weight = 700, color = dim
        Row(gap = 8px):
          Panel(width = 112px, fill = panel2, radius = 11px, pad = 10px, gap = 2px):
            Text "10.5", size = 21px, weight = 700, color = amber
            Text "base pairs per turn", size = 10px, color = muted
          Panel(width = 112px, fill = panel2, radius = 11px, pad = 10px, gap = 2px):
            Text "3.4 Å", size = 21px, weight = 700, color = cyan
            Text "rise per base pair", size = 10px, color = muted
          Panel(width = 112px, fill = panel2, radius = 11px, pad = 10px, gap = 2px):
            Text "2 nm", size = 21px, weight = 700, color = ink
            Text "helix diameter", size = 10px, color = muted
        Panel(fill = panel2, radius = 12px, pad = 12px, gap = 6px):
          Row(gap = 8px):
            Text "HIGHLIGHTED BASE", size = 10px, weight = 700, color = dim
            Row(grow = 1)
            Button "Prev", fill = panelBg, color = ink, radius = 7px, pad = 5px:
              on tap: pick = (pick + hbb.len - 1) mod hbb.len
            Button "Next", fill = panelBg, color = ink, radius = 7px, pad = 5px:
              on tap: pick = (pick + 1) mod hbb.len
          Text "base {pick + 1} · {hbb[pick]} = {comp(hbb[pick])}", size = 13px, weight = 600, color = ink
          Text "codon {pick div 3 + 1} · {codonAt(pick div 3)} · in HBB", size = 11px, color = muted
        Row(grow = 1)
        Text "Sequence: Homo sapiens HBB, the beta-globin coding sequence, bases 1-30 of 444.", size = 10px, color = dim
        Text "The sickle-cell variant is one codon away: c.20A>T, codon 7 GAG→GTG.", size = 10px, color = dim

    Row(height = 64px, gap = 12px):
      Column(gap = 3px):
        Text "HBB · bases 1-30", size = 13px, weight = 600, color = ink
        Text "human beta-globin, coding sequence", size = 11px, color = muted
      for k in 0 .. 9:
        Column(gap = 3px):
          Text "{k + 1}", size = 9px, color = dim, align = 1, width = 55px
          Row(gap = 2px):
            for i in k * 3 .. k * 3 + 2:
              Text "{hbb[i]}", size = 17px, weight = 600, color = baseInk(hbb[i], i == pick), width = 17px, align = 1
      Row(grow = 1)
      Row(gap = 7px):
        Panel(width = 8px, height = 8px, radius = 4px, fill = amber)
        Text "A-T", size = 11px, color = muted
        Panel(width = 8px, height = 8px, radius = 4px, fill = cyan)
        Text "G-C", size = 11px, color = muted
