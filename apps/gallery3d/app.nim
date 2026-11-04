## Night Gallery — six public-domain paintings hung in a real Filament 3D hall,
## walked by two buttons: the camera moves with the plate.

let claret = #5E2A24          # the plaster, painted a museum claret
let gilt = #C9A24A            # a gilded frame
let ink = #F6EEDC             # the label's type
let mute = #B09B7C
let night = #0B0908
let art = "data/"              # the app's own folder: its paintings, by name

let titles = ["There Comes Papa", "The Great Wave", "The Milkmaid",
              "Three Girls", "Wheat Field with Cypresses", "Water Lilies"]
let artists = ["Raja Ravi Varma, 1893", "Katsushika Hokusai, c. 1832",
               "Johannes Vermeer, c. 1660", "Amrita Sher-Gil, 1935",
               "Vincent van Gogh, 1889", "Claude Monet, 1906"]
let files = ["ravi-varma.jpg", "hokusai.jpg", "vermeer.jpg",
             "sher-gil.jpg", "van-gogh.jpg", "monet.jpg"]

proc zOf(i: int): float =
  ## How far down the hall a work hangs: a room every three metres.
  case i
  of 0: -4.0
  of 1: -7.0
  of 2: -10.0
  of 3: -13.0
  of 4: -16.0
  else: -19.0

proc sideOf(i: int): float =
  ## -1.0: the left wall, 1.0: the right; the works alternate.
  if i mod 2 == 0: -1.0 else: 1.0

proc wallOf(i: int): string =
  ## Which wall the plate hangs on, for the label.
  if i mod 2 == 0: "LEFT WALL" else: "RIGHT WALL"

view NightHall
  ## The corridor itself: polished floor, claret walls, gilt skirting.
  Mesh(shape = 0, posX = 0, posY = -0.06, posZ = -10, sizeX = 5.2, sizeY = 0.12, sizeZ = 28,
       fill = #4A423B, rough = 0.22, metal = 0.08)
  Mesh(shape = 0, posX = 0, posY = 0.012, posZ = -10, sizeX = 1.5, sizeY = 0.012, sizeZ = 26,
       fill = #5A2114, rough = 0.9)
  Mesh(shape = 0, posX = -2.55, posY = 1.8, posZ = -10, sizeX = 0.12, sizeY = 3.6, sizeZ = 28,
       fill = claret, rough = 0.9)
  Mesh(shape = 0, posX = 2.55, posY = 1.8, posZ = -10, sizeX = 0.12, sizeY = 3.6, sizeZ = 28,
       fill = claret, rough = 0.9)
  Mesh(shape = 0, posY = 3.62, posZ = -10, sizeX = 5.2, sizeY = 0.12, sizeZ = 28,
       fill = #2A1F19, rough = 0.95)
  Mesh(shape = 0, posY = 1.8, posZ = -24, sizeX = 5.2, sizeY = 3.6, sizeZ = 0.12,
       fill = #4A211C, rough = 0.9)
  Mesh(shape = 0, posX = -2.47, posY = 0.1, posZ = -10, sizeX = 0.06, sizeY = 0.2, sizeZ = 28,
       fill = gilt, metal = 1, rough = 0.3)
  Mesh(shape = 0, posX = 2.47, posY = 0.1, posZ = -10, sizeX = 0.06, sizeY = 0.2, sizeZ = 28,
       fill = gilt, metal = 1, rough = 0.3)
  Mesh(shape = 0, posX = -2.47, posY = 3.44, posZ = -10, sizeX = 0.06, sizeY = 0.08, sizeZ = 28,
       fill = gilt, metal = 1, rough = 0.35)
  Mesh(shape = 0, posX = 2.47, posY = 3.44, posZ = -10, sizeX = 0.06, sizeY = 0.08, sizeZ = 28,
       fill = gilt, metal = 1, rough = 0.35)
  # The corridor's bones: pilasters between the bays, a runner on the floor, and
  # a beam every bay. Geometry, not a texture — it is what makes the hall read
  # as a room with a length to it instead of two flat walls.
  for bay in 0 .. 5:
    let bz = -2.5 - float(bay) * 3.0
    Mesh(shape = 0, posX = -2.42, posY = 1.85, posZ = bz, sizeX = 0.16, sizeY = 3.7, sizeZ = 0.26,
         fill = #4A211C, rough = 0.92)
    Mesh(shape = 0, posX = 2.42, posY = 1.85, posZ = bz, sizeX = 0.16, sizeY = 3.7, sizeZ = 0.26,
         fill = #4A211C, rough = 0.92)
    Mesh(shape = 0, posX = 0, posY = 3.56, posZ = bz, sizeX = 5.1, sizeY = 0.14, sizeZ = 0.2,
         fill = #231A15, rough = 0.95)
  Mesh(shape = 0, posX = 0, posY = 0.028, posZ = -10, sizeX = 1.16, sizeY = 0.02, sizeZ = 26,
       fill = #4A1618, rough = 0.96)
  Mesh(shape = 0, posX = -0.58, posY = 0.03, posZ = -10, sizeX = 0.03, sizeY = 0.024, sizeZ = 26,
       fill = gilt, metal = 1, rough = 0.4)
  Mesh(shape = 0, posX = 0.58, posY = 0.03, posZ = -10, sizeX = 0.03, sizeY = 0.024, sizeZ = 26,
       fill = gilt, metal = 1, rough = 0.4)
  Light(lightKind = 1, posY = 3.1, posZ = 1.5, intensity = 300000, color = #FFE0B8, shadows = false)
  Light(lightKind = 1, posY = 3.1, posZ = -22, intensity = 300000, color = #FFE0B8, shadows = false)
  Light(lightKind = 1, posY = 0.9, posZ = -1.0, intensity = 90000, color = #FFD2A0, shadows = false)

view Work(i: int)
  ## One painting: the gilt frame, the canvas, and its little plate.
  Mesh(shape = 0, posX = sideOf(i) * 2.44, posY = 1.62, posZ = zOf(i),
       sizeX = 0.05, sizeY = 1.36, sizeZ = 1.1, texture = art & files[i], tilingY = -1, fill = #FFFFFF, rough = 0.8)
  Mesh(shape = 0, posX = sideOf(i) * 2.46, posY = 1.62, posZ = zOf(i) - 0.6,
       sizeX = 0.08, sizeY = 1.56, sizeZ = 0.1, fill = gilt, metal = 1, rough = 0.28)
  Mesh(shape = 0, posX = sideOf(i) * 2.46, posY = 1.62, posZ = zOf(i) + 0.6,
       sizeX = 0.08, sizeY = 1.56, sizeZ = 0.1, fill = gilt, metal = 1, rough = 0.28)
  Mesh(shape = 0, posX = sideOf(i) * 2.46, posY = 2.4, posZ = zOf(i),
       sizeX = 0.08, sizeY = 0.1, sizeZ = 1.3, fill = gilt, metal = 1, rough = 0.28)
  Mesh(shape = 0, posX = sideOf(i) * 2.46, posY = 0.84, posZ = zOf(i),
       sizeX = 0.08, sizeY = 0.1, sizeZ = 1.3, fill = gilt, metal = 1, rough = 0.28)
  Mesh(shape = 0, posX = sideOf(i) * 2.47, posY = 1.02, posZ = zOf(i) + 0.78,
       sizeX = 0.03, sizeY = 0.17, sizeZ = 0.3, fill = #EADCC0, rough = 0.6)

view Spot(i: int)
  ## A museum spot in the ceiling, aimed at the middle of one painting.
  Light(lightKind = 2, posX = sideOf(i) * 0.85, posY = 3.4, posZ = zOf(i) + 1.0,
        targetX = sideOf(i) * 2.44, targetY = 1.6, targetZ = zOf(i),
        intensity = 500000, color = #FFE6C6, shadows = true)
  Mesh(shape = 1, posX = sideOf(i) * 0.85, posY = 3.52, posZ = zOf(i) + 1.0,
       sizeX = 0.16, sizeY = 0.08, sizeZ = 0.16, fill = #2A2A2A, glow = #FFE6C6)

view Exhibit(i: int)
  ## The real 3-D object: tencent/Hunyuan3D-2.1, image-to-3D, out of the GPU fleet.
  ## A `Model` inside a `Scene3D` is a world object and is NOT framed for you —
  ## `filament_shim.cpp:216-222` frames only a TOP-LEVEL `model` node — so the
  ## placement below is arithmetic, not taste. The hall's eye is at
  ## (-side, 1.52, z+2.4) and its target at (side*2.44, 1.45, z-0.2), so half way
  ## down that sight line (delta z = -1.3) the gaze is at (side*0.72, 1.485, z+1.1).
  ## The object's centre is put at that height, which is what the plinth is for: left
  ## on the floor, the GLB's base fell 34 deg below the 23 deg half-fov and the
  ## bottom of it was cut off by the viewport.
  ## Scale 0.4: the GLB measures 1.95 x 1.62 x 1.99 units, so it stands 0.65 m tall
  ## and 0.78 m wide — a 289-pixel-tall object on a 1280x816 surface.
  Mesh(shape = 0, posX = sideOf(i) * 0.72, posY = 0.56, posZ = zOf(i) + 1.1,
       sizeX = 0.78, sizeY = 1.12, sizeZ = 0.62, fill = #EADCC0, rough = 0.6)
  Model(source = "assets/mesh-mushroom-01.glb",
        posX = sideOf(i) * 0.72, posY = 1.44, posZ = zOf(i) + 1.1, scale = 0.4)

view Gallery3d
  state picked = 4
  Stack(width = 1280px, height = 816px, fill = night):
    # The hall is walked: ←/→ step one work, ↑/↓ jump a room. The on-screen pads
    # below do the same thing, so a person with no keyboard is never stuck.
    on key:
      let k = lastKey()
      if k.code == keyLeft:
        picked = max(0, picked - 1)
      elif k.code == keyRight:
        picked = min(5, picked + 1)
      elif k.code == keyUp:
        picked = max(0, picked - 3)
      elif k.code == keyDown:
        picked = min(5, picked + 3)
    Scene3D(width = 1280px, height = 816px, sky = #171210, shadows = true, bloom = 0.45,
            exposure = 2.25, fog = 0.032, fogColor = #0D0A08, ambient = 34000, ssao = true,
            vignette = 0.32):
      Camera(posX = -sideOf(picked) * 1.0, posY = 1.52, posZ = zOf(picked) + 2.4,
             targetX = sideOf(picked) * 2.44, targetY = 1.45, targetZ = zOf(picked) - 0.2, fov = 46)
      NightHall()
      Exhibit(picked)
      for i in 0 ..< 6:
        Spot(i)
        Work(i)
    Column(absolute = true, left = 40px, top = 32px, gap = 5px):
      Text "NIGHT GALLERY", size = 12px, weight = 700, color = gilt
      Text "The Hall of Six", size = 34px, weight = 700, color = ink
      Text "A walk-through corridor, rendered in Filament", size = 14px, color = mute
    Column(absolute = true, right = 40px, top = 132px, gap = 8px):
      Text "WALK THE HALL", size = 11px, weight = 700, color = mute
      Button "01", width = 44px, height = 34px, radius = 8px, fill = (if picked == 0: gilt else: #1C1512), color = (if picked == 0: #1A120C else: mute):
        on tap: picked = 0
      Button "02", width = 44px, height = 34px, radius = 8px, fill = (if picked == 1: gilt else: #1C1512), color = (if picked == 1: #1A120C else: mute):
        on tap: picked = 1
      Button "03", width = 44px, height = 34px, radius = 8px, fill = (if picked == 2: gilt else: #1C1512), color = (if picked == 2: #1A120C else: mute):
        on tap: picked = 2
      Button "04", width = 44px, height = 34px, radius = 8px, fill = (if picked == 3: gilt else: #1C1512), color = (if picked == 3: #1A120C else: mute):
        on tap: picked = 3
      Button "05", width = 44px, height = 34px, radius = 8px, fill = (if picked == 4: gilt else: #1C1512), color = (if picked == 4: #1A120C else: mute):
        on tap: picked = 4
      Button "06", width = 44px, height = 34px, radius = 8px, fill = (if picked == 5: gilt else: #1C1512), color = (if picked == 5: #1A120C else: mute):
        on tap: picked = 5
    Panel(absolute = true, left = 40px, bottom = 36px, width = 520px, fill = #1B1412,
          radius = 14px, pad = 22px, border = 1px, borderColor = #4A3527):
      Panel(absolute = true, left = 0px, top = 22px, width = 3px, height = 92px, fill = gilt, radius = 2px)
      Column(gap = 7px, padLeft = 12px):
        Row(gap = 9px):
          Text "No. {picked + 1} of 6", size = 11px, weight = 700, color = gilt
          Text wallOf(picked), size = 11px, color = mute
        Text titles[picked], size = 26px, weight = 700, color = ink
        Text artists[picked], size = 14px, color = #D9BC7E
        Row(gap = 6px):
          for i in 0 ..< 6:
            Panel(width = (if i == picked: 44px else: 16px), height = 3px,
                  fill = (if i == picked: gilt else: #3B2A22), radius = 2px)
        Text "Public domain · Galerie Nocturne", size = 11px, color = #9C8B73
    Row(absolute = true, right = 40px, bottom = 44px, gap = 10px):
      Button "Prev", width = 108px, radius = 10px, fill = #241A16, color = ink:
        on tap: picked = max(0, picked - 1)
      Button "Next", width = 108px, radius = 10px, fill = gilt, color = #1A120C, weight = 700:
        on tap: picked = min(5, picked + 1)
