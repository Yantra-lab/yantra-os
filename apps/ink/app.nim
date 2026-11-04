## SUMI / a water study. A genuinely evolving, reduced Stam fluid: pointer
## forces enter a coarse velocity lattice, seven Gauss–Seidel pressure passes
## project it, and semi-Lagrangian advection carries three optical-density dye
## channels on a finer lattice. Drying transfers pigment to a permanent stain;
## concentration gradients make the tideline. Nothing is pre-painted.

const
  winW = 1280.0
  winH = 816.0
  NX = 84                    ## velocity cells, excluding the one-cell border
  NY = 54
  SX = NX + 2
  SY = NY + 2
  NS = SX * SY
  DW = NX * 2                ## dye cells: twice the velocity resolution
  DH = NY * 2
  ND = DW * DH
  projectPasses = 7

let washi = #F4EFE6
let inkDark = #1B1F2A
let quiet = #746F66
let faint = #AAA296
let vermilion = #B9352A

var
  u, v, u0, v0, pressure, divergence, curl, fu, fv: seq[float32]
  dyeR, dyeG, dyeB, oldR, oldG, oldB, nextR, nextG, nextB: seq[float32]
  stainR, stainG, stainB, age, sizing: seq[float32]
  rgba: seq[byte]
  water = Layer(0)
  pointerDownNow = false
  lastPX = 0.0
  lastPY = 0.0
  simTime = 0.0

proc yLayerWrite(id, x, y, w, h: int32; p: nil pointer) {.importc: "y_layer_write".}

proc clamp01(x: float32): float32 = max(0.0'f32, min(1.0'f32, x))

proc sample(a: seq[float32]; x, y: float32; w, h: int): float32 {.inline.} =
  if x != x or y != y: return 0.0'f32  # a confined NaN must never become an index
  let cx = max(0.0'f32, min(float32(w - 1) - 0.001'f32, x))
  let cy = max(0.0'f32, min(float32(h - 1) - 0.001'f32, y))
  let ix = int(cx)
  let iy = int(cy)
  let fx = cx - float32(ix)
  let fy = cy - float32(iy)
  let k = ix + iy * w
  result = a[k] * (1-fx) * (1-fy) + a[k+1] * fx * (1-fy) +
           a[k+w] * (1-fx) * fy + a[k+w+1] * fx * fy

proc velocityBounds() =
  for i in 1 .. NX:
    let un0 = u[i+SX]
    let vn0 = v[i+SX]
    let un1 = u[i+SX*NY]
    let vn1 = v[i+SX*NY]
    u[i] = un0
    v[i] = -vn0
    u[i+SX*(NY+1)] = un1
    v[i+SX*(NY+1)] = -vn1
  for j in 1 .. NY:
    let k = j*SX
    let un0 = u[k+1]
    let vn0 = v[k+1]
    let un1 = u[k+NX]
    let vn1 = v[k+NX]
    u[k] = -un0
    v[k] = vn0
    u[k+NX+1] = -un1
    v[k+NX+1] = vn1

proc scalarBounds(a: var seq[float32]) =
  for i in 1 .. NX:
    a[i] = a[i+SX]; a[i+SX*(NY+1)] = a[i+SX*NY]
  for j in 1 .. NY:
    a[j*SX] = a[j*SX+1]; a[j*SX+NX+1] = a[j*SX+NX]

proc addDrop(px, py: float; pigment: int; amount = 1.0) =
  ## Ink and an impact vortex enter state here; the frame alone never invents a bloom.
  let dx = clamp(float32(px / winW * float32(DW)), 2.0'f32, float32(DW-3))
  let dy = clamp(float32(py / winH * float32(DH)), 2.0'f32, float32(DH-3))
  let strengths = [1.50'f32, 1.22'f32, 1.18'f32, 1.35'f32]
  let absorb = [
    [2.12'f32, 2.17'f32, 2.12'f32],  # sumi
    [2.12'f32, 1.79'f32, 0.90'f32],  # indigo
    [0.62'f32, 1.81'f32, 2.18'f32],  # vermilion
    [0.73'f32, 0.88'f32, 1.34'f32]]  # pale gold
  let radius = 4.2'f32
  for y in max(1, int(dy-12)) .. min(DH-2, int(dy+12)):
    for x in max(1, int(dx-12)) .. min(DW-2, int(dx+12)):
      let ox = float32(x) - dx
      let oy = float32(y) - dy
      let r2 = ox*ox + oy*oy
      if r2 < 144:
        let q = exp(-r2 / (radius*radius)) * amount * strengths[pigment]
        let uneven = 0.86'f32 + 0.20'f32 * sin(float32(x)*1.71'f32 + float32(y)*0.83'f32)
        let k = x + y*DW
        dyeR[k] = min(5.5'f32, dyeR[k] + absorb[pigment][0]*q*uneven)
        dyeG[k] = min(5.5'f32, dyeG[k] + absorb[pigment][1]*q*uneven)
        dyeB[k] = min(5.5'f32, dyeB[k] + absorb[pigment][2]*q*uneven)
        age[k] = 0.0'f32
  let gx = clamp(float32(px / winW * float32(NX) + 1), 2.0'f32, float32(NX-1))
  let gy = clamp(float32(py / winH * float32(NY) + 1), 2.0'f32, float32(NY-1))
  for y in max(1, int(gy-6)) .. min(NY, int(gy+6)):
    for x in max(1, int(gx-6)) .. min(NX, int(gx+6)):
      let ox = float32(x)-gx
      let oy = float32(y)-gy
      let r2 = ox*ox + oy*oy
      if r2 < 36:
        let q = exp(-r2*0.32'f32) * amount
        let k = x+y*SX
        u[k] += (ox*0.36'f32 - oy*0.42'f32)*q
        v[k] += (oy*0.36'f32 + ox*0.42'f32)*q

proc beginPointer(px, py: float) =
  pointerDownNow = true
  lastPX = px; lastPY = py

proc stirPointer(px, py: float; pigment: int) =
  if not pointerDownNow: return
  let dx = px-lastPX
  let dy = py-lastPY
  if dx*dx + dy*dy < 1.0: return
  addDrop(px, py, pigment, 0.16)
  let gx = clamp(float32(px / winW * float32(NX) + 1), 2.0'f32, float32(NX-1))
  let gy = clamp(float32(py / winH * float32(NY) + 1), 2.0'f32, float32(NY-1))
  let fx = clamp(float32(dx / winW * float32(NX) * 0.95), -8.0'f32, 8.0'f32)
  let fy = clamp(float32(dy / winH * float32(NY) * 0.95), -8.0'f32, 8.0'f32)
  for y in max(1, int(gy-5)) .. min(NY, int(gy+5)):
    for x in max(1, int(gx-5)) .. min(NX, int(gx+5)):
      let ox = float32(x)-gx
      let oy = float32(y)-gy
      let q = exp(-(ox*ox+oy*oy)*0.32'f32)
      let k = x+y*SX
      u[k] += fx*q
      v[k] += fy*q
  lastPX = px; lastPY = py

proc clearWater() =
  for i in 0 ..< NS:
    u[i] = 0; v[i] = 0; u0[i] = 0; v0[i] = 0; pressure[i] = 0
    divergence[i] = 0; curl[i] = 0; fu[i] = 0; fv[i] = 0
  for i in 0 ..< ND:
    dyeR[i] = 0; dyeG[i] = 0; dyeB[i] = 0
    oldR[i] = 0; oldG[i] = 0; oldB[i] = 0
    nextR[i] = 0; nextG[i] = 0; nextB[i] = 0
    stainR[i] = 0; stainG[i] = 0; stainB[i] = 0; age[i] = 0
  pointerDownNow = false
  simTime = 0.0

proc simulate(dtArg: float; mode, frameNo: int) =
  var dt60 = float32(dtArg*60.0)
  if dt60 <= 0 or dt60 > 2.0: dt60 = 1.0
  simTime += float(dt60)/60.0
  let flow = float32(mode)
  # A controlled ambient current, not an autonomous ink animation.
  for j in 1 .. NY:
    for i in 1 .. NX:
      let k = i+j*SX
      u[k] += sin(simTime*0.37+float32(j)*0.19)*0.0030'f32*flow*dt60
      v[k] += cos(simTime*0.29+float32(i)*0.16)*0.0024'f32*flow*dt60
  # Vorticity confinement restores the small curls lost to a coarse lattice.
  for j in 2 .. NY-1:
    for i in 2 .. NX-1:
      let k = i+j*SX
      curl[k] = 0.5'f32*(v[k+1]-v[k-1]-u[k+SX]+u[k-SX])
  for j in 2 .. NY-1:
    for i in 2 .. NX-1:
      let k = i+j*SX
      var gx = 0.5'f32*(abs(curl[k+1])-abs(curl[k-1]))
      var gy = 0.5'f32*(abs(curl[k+SX])-abs(curl[k-SX]))
      let n = sqrt(gx*gx+gy*gy)+0.00001'f32
      gx = gx/n; gy = gy/n
      fu[k] = gy*curl[k]*0.17'f32*dt60
      fv[k] = -gx*curl[k]*0.17'f32*dt60
      u[k] += fu[k]; v[k] += fv[k]
  for j in 1 .. NY:
    for i in 1 .. NX:
      let k = i+j*SX
      if u[k] > 8.0'f32: u[k] = 8.0'f32
      elif u[k] < -8.0'f32: u[k] = -8.0'f32
      elif u[k] != u[k]: u[k] = 0.0'f32
      if v[k] > 8.0'f32: v[k] = 8.0'f32
      elif v[k] < -8.0'f32: v[k] = -8.0'f32
      elif v[k] != v[k]: v[k] = 0.0'f32
  # Two implicit viscosity passes.
  for i in 0 ..< NS:
    u0[i] = u[i]
    v0[i] = v[i]
  let visc = 0.035'f32*dt60
  for pass in 0 ..< 2:
    for j in 1 .. NY:
      for i in 1 .. NX:
        let k = i+j*SX
        u[k] = (u0[k]+visc*(u[k-1]+u[k+1]+u[k-SX]+u[k+SX]))/(1+4*visc)
        v[k] = (v0[k]+visc*(v[k-1]+v[k+1]+v[k-SX]+v[k+SX]))/(1+4*visc)
    velocityBounds()
  # Semi-Lagrangian transport of velocity.
  for i in 0 ..< NS:
    u0[i] = u[i]
    v0[i] = v[i]
  for j in 1 .. NY:
    for i in 1 .. NX:
      let k = i+j*SX
      let x = float32(i)-u0[k]*dt60
      let y = float32(j)-v0[k]*dt60
      fu[k] = sample(u0,x,y,SX,SY)
      fv[k] = sample(v0,x,y,SX,SY)
  for i in 0 ..< NS:
    u[i] = fu[i]
    v[i] = fv[i]
  velocityBounds()
  # Reduced incompressibility projection: SEVEN real Gauss–Seidel passes.
  for j in 1 .. NY:
    for i in 1 .. NX:
      let k = i+j*SX
      divergence[k] = -0.5'f32*(u[k+1]-u[k-1]+v[k+SX]-v[k-SX])
      pressure[k] *= 0.82'f32
  for pass in 0 ..< projectPasses:
    scalarBounds(pressure)
    for j in 1 .. NY:
      for i in 1 .. NX:
        let k = i+j*SX
        pressure[k] = 0.25'f32*(divergence[k]+pressure[k-1]+pressure[k+1]+pressure[k-SX]+pressure[k+SX])
  for j in 1 .. NY:
    for i in 1 .. NX:
      let k = i+j*SX
      u[k] -= 0.5'f32*(pressure[k+1]-pressure[k-1])
      v[k] -= 0.5'f32*(pressure[k+SX]-pressure[k-SX])
      let drag = if mode == 0: 0.977'f32 elif mode == 1: 0.994'f32 else: 0.998'f32
      u[k] *= drag; v[k] *= drag
      if u[k] > 8.0'f32: u[k] = 8.0'f32
      elif u[k] < -8.0'f32: u[k] = -8.0'f32
      elif u[k] != u[k]: u[k] = 0.0'f32
      if v[k] > 8.0'f32: v[k] = 8.0'f32
      elif v[k] < -8.0'f32: v[k] = -8.0'f32
      elif v[k] != v[k]: v[k] = 0.0'f32
  velocityBounds()
  # Fine dye advection through the newly projected velocity field.
  for i in 0 ..< ND:
    oldR[i] = dyeR[i]
    oldG[i] = dyeG[i]
    oldB[i] = dyeB[i]
  for y in 0 ..< DH:
    for x in 0 ..< DW:
      let k = x+y*DW
      let gx = (float32(x)+0.5'f32)*0.5'f32+0.5'f32
      let gy = (float32(y)+0.5'f32)*0.5'f32+0.5'f32
      let vx = sample(u,gx,gy,SX,SY)*dt60
      let vy = sample(v,gx,gy,SX,SY)*dt60
      let bx = (gx-vx-0.5'f32)*2.0'f32-0.5'f32
      let by = (gy-vy-0.5'f32)*2.0'f32-0.5'f32
      nextR[k] = sample(oldR,bx,by,DW,DH)
      nextG[k] = sample(oldG,bx,by,DW,DH)
      nextB[k] = sample(oldB,bx,by,DW,DH)
  for i in 0 ..< ND:
    oldR[i] = nextR[i]
    oldG[i] = nextG[i]
    oldB[i] = nextB[i]
  let diffusion = 0.021'f32*dt60
  for y in 0 ..< DH:
    for x in 0 ..< DW:
      let k = x+y*DW
      let l = max(0,x-1)+y*DW
      let r = min(DW-1,x+1)+y*DW
      let t = x+max(0,y-1)*DW
      let b = x+min(DH-1,y+1)*DW
      dyeR[k] = (oldR[k]+diffusion*(oldR[l]+oldR[r]+oldR[t]+oldR[b]))/(1+4*diffusion)
      dyeG[k] = (oldG[k]+diffusion*(oldG[l]+oldG[r]+oldG[t]+oldG[b]))/(1+4*diffusion)
      dyeB[k] = (oldB[k]+diffusion*(oldB[l]+oldB[r]+oldB[t]+oldB[b]))/(1+4*diffusion)
      let wet = dyeR[k]+dyeG[k]+dyeB[k]
      if wet > 0.003: age[k] += dt60/60.0
      # Evaporation fixes pigment rather than simply fading the picture away.
      let drying = (if age[k] > 1.2: 0.0035'f32*dt60 else: 0.0'f32)
      let keepR = dyeR[k]*drying
      let keepG = dyeG[k]*drying
      let keepB = dyeB[k]*drying
      dyeR[k] -= keepR; dyeG[k] -= keepG; dyeB[k] -= keepB
      stainR[k] += keepR*1.10'f32; stainG[k] += keepG*1.10'f32; stainB[k] += keepB*1.10'f32

proc present() =
  ## Absorbance, not RGB interpolation: mixed pigments darken by Beer–Lambert.
  for y in 0 ..< DH:
    for x in 0 ..< DW:
      let k = x+y*DW
      let wet = dyeR[k]+dyeG[k]+dyeB[k]
      let l = max(0,x-1)+y*DW
      let r = min(DW-1,x+1)+y*DW
      let t = x+max(0,y-1)*DW
      let b = x+min(DH-1,y+1)*DW
      let wl = dyeR[l]+dyeG[l]+dyeB[l]
      let wr = dyeR[r]+dyeG[r]+dyeB[r]
      let wt = dyeR[t]+dyeG[t]+dyeB[t]
      let wb = dyeR[b]+dyeG[b]+dyeB[b]
      let grad = abs(wr-wl)+abs(wb-wt)
      let band = (wet-0.30'f32)*6.0'f32
      let tide = clamp01(grad*1.8'f32)*exp(-band*band)
      let boost = sizing[k]*(1.0'f32+0.30'f32*tide)
      let inv = 1.0'f32/(wet+0.10'f32)
      let ar = dyeR[k]*boost + stainR[k] + dyeR[k]*tide*inv*0.55'f32
      let ag = dyeG[k]*boost + stainG[k] + dyeG[k]*tide*inv*0.55'f32
      let ab = dyeB[k]*boost + stainB[k] + dyeB[k]*tide*inv*0.55'f32
      let g = 2.1'f32*sin(float32(x)*0.21'f32+float32(y)*0.08'f32) +
              1.2'f32*sin(float32(y)*0.61'f32)
      rgba[k*4] = byte(clamp(int((244.0'f32+g)*exp(-ar)),0,255))
      rgba[k*4+1] = byte(clamp(int((239.0'f32+g)*exp(-ag)),0,255))
      rgba[k*4+2] = byte(clamp(int((230.0'f32+g)*exp(-ab)),0,255))
      rgba[k*4+3] = 255
  yLayerWrite(int32(water),0,0,int32(DW),int32(DH),addr rgba[0])

proc flowName(mode: int): string =
  if mode == 0: "STILL" elif mode == 1: "GENTLE" else: "CURRENT"

proc inkName(pigment: int): string =
  ["SUMI", "INDIGO", "VERMILION", "PALE GOLD"][pigment]

proc art(frameNo, drops, mode: int): string =
  present()
  var d = Draw()
  d = d.layer(water,0,0,winW,winH)
  # Kozo fibres and the deckle remain quiet and independent of the wet state.
  for i in 0 ..< 110:
    let x = float32((i*197+83) mod 1280)
    let y = float32((i*313+47) mod 816)
    let len = 12.0'f32+float32(i mod 9)*7.0'f32
    let slant = -3.0'f32+float32(i mod 7)
    d = d.line(x,y,x+len,y+slant,0x0C806F55'u32,0.55)
  # The artist's seal is the one deliberate mark on an empty sheet.
  d = d.rect(58,708,34,48,0xE6B9352A'u32,1)
  d = d.textFace(66,727,12,0xFFF4EFE6'u32,"serif","S",400)
  d = d.textFace(66,744,9,0xFFF4EFE6'u32,"serif","05",400)
  d = d.textFace(106,720,10,0xFF746F66'u32,"serif","suigetsu / moon in water",400)
  d = d.textFace(106,739,9,0xFF746F66'u32,"monospace",
                 $DW & " × " & $DH & " dye · " & $projectPasses & " pressure passes",400)
  if drops == 0:
    d = d.textFace(640,414,15,0xAA1B1F2A'u32,"serif","touch the water",400)
  d.cmds

proc initialise() =
  u = newSeq[float32](NS); v = newSeq[float32](NS)
  u0 = newSeq[float32](NS); v0 = newSeq[float32](NS)
  pressure = newSeq[float32](NS); divergence = newSeq[float32](NS)
  curl = newSeq[float32](NS); fu = newSeq[float32](NS); fv = newSeq[float32](NS)
  dyeR = newSeq[float32](ND); dyeG = newSeq[float32](ND); dyeB = newSeq[float32](ND)
  oldR = newSeq[float32](ND); oldG = newSeq[float32](ND); oldB = newSeq[float32](ND)
  nextR = newSeq[float32](ND); nextG = newSeq[float32](ND); nextB = newSeq[float32](ND)
  stainR = newSeq[float32](ND); stainG = newSeq[float32](ND); stainB = newSeq[float32](ND)
  age = newSeq[float32](ND); sizing = newSeq[float32](ND); rgba = newSeq[byte](ND*4)
  for y in 0 ..< DH:
    for x in 0 ..< DW:
      let n = sin(float32(x)*0.127'f32+sin(float32(y)*0.113'f32)) *
              sin(float32(y)*0.173'f32+1.4'f32)
      sizing[x+y*DW] = 0.94'f32+0.10'f32*n
  water = newLayer(DW,DH)

initialise()

view Ink
  state pigment = 0
  state mode = 1
  state drops = 0
  state stirs = 0
  state frameNo = 0
  Stack(width = 1280px, height = 816px, fill = washi):
    on frame:
      frameNo += 1
      simulate(float(frameDt()), mode, frameNo)
    Canvas(draw = art(frameNo,drops,mode), width = 1280px, height = 816px):
      on pointerDown:
        let (px,py) = pointerPos()
        beginPointer(px,py)
        addDrop(px,py,pigment,1.0)
        drops += 1
      on pointerMove:
        let (px,py) = pointerPos()
        if pointerDownNow:
          stirPointer(px,py,pigment)
          stirs += 1
      on pointerUp: pointerDownNow = false
    Column(absolute = true, left = 56px, top = 46px, gap = 4px):
      Text "S U M I", size = 38px, weight = 400, color = inkDark, font = "serif"
      Text "INK IN WATER / STUDY 05", size = 9px, weight = 600, color = quiet
      Text "one drop · a held breath · the slow unfurling", size = 11px, color = quiet, font = "serif"
    Column(absolute = true, right = 54px, top = 154px, width = 112px, gap = 6px):
      Text "P I G M E N T", size = 8px, weight = 600, color = quiet
      Button "SUMI", width = 112px, height = 31px, radius = 1px,
             fill = (if pigment == 0: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: pigment = 0
      Button "INDIGO", width = 112px, height = 31px, radius = 1px,
             fill = (if pigment == 1: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: pigment = 1
      Button "VERMILION", width = 112px, height = 31px, radius = 1px,
             fill = (if pigment == 2: #DCD4C6 else: washi), color = #A4382C, size = 9px, weight = 600:
        on tap: pigment = 2
      Button "PALE GOLD", width = 112px, height = 31px, radius = 1px,
             fill = (if pigment == 3: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: pigment = 3
      Text "W A T E R", size = 8px, weight = 600, color = quiet
      Button "STILL", width = 112px, height = 30px, radius = 1px,
             fill = (if mode == 0: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: mode = 0
      Button "GENTLE", width = 112px, height = 30px, radius = 1px,
             fill = (if mode == 1: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: mode = 1
      Button "CURRENT", width = 112px, height = 30px, radius = 1px,
             fill = (if mode == 2: #DCD4C6 else: washi), color = inkDark, size = 9px, weight = 600:
        on tap: mode = 2
      Button "NEW SHEET", width = 112px, height = 34px, radius = 1px,
             fill = washi, color = vermilion, size = 9px, weight = 600:
        on tap:
          clearWater()
          drops = 0; stirs = 0; frameNo = 0
    Text "tap to let a drop fall  ·  drag to stir", absolute = true, left = 470px,
         bottom = 38px, size = 12px, color = quiet, font = "serif"
    Text "{inkName(pigment)} · {flowName(mode)} · {drops} drops · {stirs} stirs · frame {frameNo}",
         absolute = true, right = 54px, bottom = 36px, size = 8px, color = faint
