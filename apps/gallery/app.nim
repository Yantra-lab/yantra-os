# Galerie Nocturne — eight works presented as a quiet museum catalogue.
# The main plate and the contact sheet share one index; every numbered control
# opens its work, while Previous and Next walk the collection and wrap at its ends.
type Work = object
  title, artist, year, medium, note, art, gen, credit: string

let works = [
  Work(title: "There Comes Papa", artist: "Raja Ravi Varma", year: "1893",
       medium: "Oil on canvas", art: "art/ravi-varma.jpg", gen: "",
       credit: "Public domain · source scan: Wikimedia Commons.",
       note: "A mother lifts her child toward the father coming home. Ravi Varma's oils were shown at the 1893 World's Columbian Exposition in Chicago, where they won awards and carried Indian subjects to an international public."),
  Work(title: "The Great Wave off Kanagawa", artist: "Katsushika Hokusai", year: "c. 1831",
       medium: "Woodblock print, colour on paper", art: "art/hokusai.jpg", gen: "",
       credit: "The Metropolitan Museum of Art, 29.100.468 · CC0 / public domain.",
       note: "The first sheet of Thirty-Six Views of Mount Fuji, made when Hokusai was in his seventies. The boats are oshiokuri-bune, fast craft carrying fish to market, and the deep blue is Prussian blue, a pigment newly imported from Europe."),
  Work(title: "The Milkmaid", artist: "Johannes Vermeer", year: "c. 1660",
       medium: "Oil on canvas", art: "art/vermeer.jpg", gen: "",
       credit: "Rijksmuseum, SK-A-2344 · Public domain.",
       note: "A maid pours milk in a plain room while light falls from a window at the left. The Rijksmuseum acquired the painting in 1908; its stillness, and the thin white stream, are what visitors come to stand in front of."),
  Work(title: "Wind over Water", artist: "Drawn by the app", year: "2026",
       medium: "Sutra, Canvas draw commands", art: "", gen: "flow",
       credit: "Original computational work · drawn live in Sutra.",
       note: "Thirty-six streams drift through a sine wind that turns them at every step. The app computes each point and writes the line into a Canvas, so the picture is the rule being run, not an image of it."),
  Work(title: "Three Girls", artist: "Amrita Sher-Gil", year: "1935",
       medium: "Oil on canvas", art: "art/sher-gil.jpg", gen: "",
       credit: "Wikimedia Commons · Public domain in India; US status not reviewed.",
       note: "Painted soon after Sher-Gil returned from Paris to India, the three women lean into one another with the melancholy she made her own. She was twenty-two, and already painting the unease of being watched."),
  Work(title: "Wheat Field with Cypresses", artist: "Vincent van Gogh", year: "1889",
       medium: "Oil on canvas", art: "art/van-gogh.jpg", gen: "",
       credit: "The Metropolitan Museum of Art, 39.73 · CC0 / public domain.",
       note: "Van Gogh painted the view from the asylum at Saint-Remy, where the cypresses stood in the wheat. He wrote to his brother Theo that a cypress is 'as beautiful in line and proportion as an Egyptian obelisk'."),
  Work(title: "Vibration", artist: "Drawn by the app", year: "2026",
       medium: "Sutra, Canvas draw commands", art: "", gen: "vib",
       credit: "Original computational work · drawn live in Sutra.",
       note: "Twenty-two ruled bands run straight until a sine wave bends them, each one a little further out of phase than the last. Drawn from the same arithmetic the rest of the room is laid out with."),
  Work(title: "Water Lilies", artist: "Claude Monet", year: "1906",
       medium: "Oil on canvas", art: "art/monet.jpg", gen: "",
       credit: "Art Institute of Chicago, 1933.1157 · CC0 / public domain.",
       note: "Monet painted the pond he had dug at Giverny, kneeling at the water's edge. By 1906 he had given the surface the whole canvas: no bank, no horizon, only sky, water and their reflection in one plane.")]

# The room is after hours: a warm charcoal wall, a lit mount, and gold for the
# only things that need pointing at. Measured contrast on the wall (#17130E):
# ink 15.6:1, body 9.4:1, muted 5.2:1, accent 7.4:1 — all past 4.5:1.
let paper = #17130E        # the wall
let matte = #F4EFE3        # the mount: a white plate in a dark room
let ink = #F7F2E6
let body = #C6BCA9
let muted = #9C9282
let rule = #3A3226
let accent = #D2A868
let poll = #241D15         # the plate's shadow card
let chip = #221C14         # an unselected thumbnail's backing
let ui = "Noto Sans"
let display = "Noto Serif Display"
let mono = "DejaVu Sans Mono"

proc iv(x: float): string = $(int(x))
proc two(i: int): string = (if i < 10: "0" & $i else: $i)
proc position(i: int): string = "WORK " & two(i + 1) & " / 08"
proc prevOf(i: int): int = (i + works.len - 1) mod works.len
proc nextOf(i: int): int = (i + 1) mod works.len

proc flowDraw(w: int; h: int): string =
  result = "R 0 0 " & $w & " " & $h & " 0 0xFF0B2740;"
  result.add "U 0 0 " & $w & " " & $h & " 0 0 0 0 " & $h & " 0xFF2A5C7A 0xFF0A1B28;"
  result.add "W 0 0 " & $w & " " & $h & " 0 " & iv(float(w) / 2.0) & " " & iv(float(h) / 3.0) &
             " " & iv(float(w) * 0.75) & " 0x557FC4D8 0x002A5C7A;"
  for i in 0 ..< 36:
    var x = float((i * 89) mod w)
    var y = float((i * 113 + 17) mod h)
    result.add "M " & iv(x) & " " & iv(y) & ";"
    for s in 0 ..< 24:
      let a = sin(x * 0.021 + float(i)) * 0.9 + cos(y * 0.017 - float(i) * 0.7) * 0.7
      x = x + cos(a) * 10.0
      y = y + sin(a) * 10.0 + 4.0
      if x < 0.0: x = 0.0
      if x > float(w): x = float(w)
      if y < 0.0: y = 0.0
      if y > float(h): y = float(h)
      result.add " L " & iv(x) & " " & iv(y) & ";"
    let ink = if i mod 4 == 0: "0xEEEAF6F2" elif i mod 4 == 1: "0xCCBFE3E8"
              elif i mod 4 == 2: "0xAAA8DADC" else: "0x887FD0D8"
    result.add " S " & ink & " " & (if i mod 4 == 0: "2.6" else: "1.7") & ";"
    if i mod 3 == 0:
      result.add "E " & iv(x) & " " & iv(y) & " 2 2 0x99F1FAEE;"

proc vibDraw(w: int; h: int): string =
  result = "R 0 0 " & $w & " " & $h & " 0 0xFFF3EDDE;"
  let step = float(h) / 22.0
  for b in 0 ..< 22:
    let y0 = float(b) * step + step / 2.0
    result.add "M 0 " & iv(y0) & ";"
    for s in 1 .. 18:
      let x = float(s) * float(w) / 18.0
      let y = y0 + step * 0.36 * sin(x * 0.05 + float(b) * 0.55)
      result.add " L " & iv(x) & " " & iv(y) & ";"
    result.add " S 0xFF24180F " & iv(step * 0.34) & ";"

proc artDraw(w: Work; cw: int; ch: int): string =
  if w.gen == "flow": flowDraw(cw, ch)
  elif w.gen == "vib": vibDraw(cw, ch)
  else: ""


proc roomDraw(w: int; h: int): string =
  ## The room the works hang in: a wall lit from above the plate, a floor line,
  ## and the corners falling away. Built from the Draw vocabulary the same way
  ## the typewriter's desk is, so every 100x100 cell of the wall carries a ramp
  ## instead of one colour (the flat-paper page this replaces measured 92.6% of
  ## one colour across the whole text column).
  var d = Draw()
  d = d.linearRect(0, 0, float(w), float(h), 0xFF241E16'u32, 0xFF0C0A07'u32,
                   float(w) * 0.5, 0, float(w) * 0.5, float(h), 0)
  # the lamp over the plate: the single source of light in the room
  d = d.radialRect(0, 0, float(w), float(h), 0x50FFD9A0'u32, 0x00FFD9A0'u32, 250, 120, 620, 0)
  d = d.radialRect(0, 0, float(w), float(h), 0x28FFE7BE'u32, 0x00FFE7BE'u32, 900, 300, 520, 0)
  # the floor, and the skirting where the wall meets it
  d = d.linearRect(0, float(h) - 118, float(w), 118, 0xFF120F0A'u32, 0xFF070605'u32,
                   float(w) * 0.5, float(h) - 118, float(w) * 0.5, float(h), 0)
  d = d.line(0, float(h) - 118, float(w), float(h) - 118, 0x59D2A868'u32, 1.2)
  # a hairline of gold across the wall, where the picture rail would be
  d = d.line(0, 104, float(w), 104, 0x33D2A868'u32, 1)
  # the corners of the room fall away
  d = d.radialRect(0, 0, float(w), float(h), 0x00000000'u32, 0x9A070503'u32, 640, 372, 820, 0)
  d.cmds

view Gallery
  state current = 0
  let w = works[current]
  Stack(fill = paper, width = 1280px, height = 816px):
    # ── the room ──
    Canvas draw = roomDraw(1280, 816), width = 1280px, height = 816px
    # ── the house, and the collection ──
    Row(left = 56px, top = 30px, gap = 10px, alignItems = 1):
      Panel(width = 7px, height = 7px, fill = accent)
      Text "GALERIE NOCTURNE", font = ui, size = 12px, weight = 700, color = ink
    Text "ART, AFTER HOURS", font = mono, size = 9px, color = muted, left = 56px, top = 52px
    Column(right = 56px, top = 31px, width = 420px, gap = 6px, alignItems = 2):
      Text "THE NIGHT COLLECTION", font = ui, size = 11px, weight = 600, color = body, align = 2
      Text "EIGHT WORKS · ROOM 01", font = mono, size = 9px, color = muted, align = 2
    Panel(left = 56px, right = 56px, top = 88px, height = 1px, fill = rule)

    # ── the plate: a white mount on the wall, lit from the lamp above it ──
    Panel(left = 60px, top = 112px, fill = poll, pad = 5px, radius = 2px):
      Panel(fill = matte, pad = 13px, radius = 1px):
        Panel(fill = #E3DCCB, pad = 2px):
          Stack(width = 352px, height = 440px):
            Canvas draw = artDraw(w, 352, 440), width = 352px, height = 440px
            Image source = w.art, width = 352px, height = 440px, fit = 0
    Panel(left = 60px, top = 112px, width = 400px, height = 3px, fill = accent, opacity = 0.75)

    # ── the wall label ──
    Column(left = 528px, top = 120px, width = 696px, gap = 12px):
      Row(gap = 12px, alignItems = 1):
        Text position(current), font = mono, size = 10px, weight = 700, color = accent
        Panel(width = 26px, height = 1px, fill = rule)
        Text "ON VIEW", font = mono, size = 9px, weight = 700, color = muted
      Text w.title, font = display, size = 42px, weight = 500, color = ink,
           lineHeight = 1.06, maxLines = 2
      Text "{w.artist} · {w.year}", font = ui, size = 17px, weight = 500, color = body
      Panel(width = 48px, height = 2px, fill = accent)
      Text "ABOUT THE WORK", font = mono, size = 9px, weight = 700, color = accent
      Text w.note, font = ui, size = 15px, color = body, lineHeight = 1.55, maxLines = 4
      Text w.medium, font = ui, size = 12px, color = muted
      Panel(width = 696px, height = 1px, fill = rule)
      Text w.credit, font = ui, size = 11px, color = muted, lineHeight = 1.45, maxLines = 2

    # ── walking the room ──
    Row(left = 528px, top = 566px, gap = 12px):
      Button "← Previous", width = 164px, height = 46px, font = "DejaVu Sans", size = 13px, weight = 600,
             fill = #221C14, color = body, radius = 2px, border = 1px, borderColor = rule:
        on tap: current = prevOf(current)
      Button "Next →", width = 164px, height = 46px, font = "DejaVu Sans", size = 13px, weight = 700,
             fill = accent, color = #17130E, radius = 2px, border = 1px, borderColor = accent:
        on tap: current = nextOf(current)
    Column(right = 60px, top = 570px, width = 300px, gap = 7px, alignItems = 2):
      Text "NEXT IN THE ROOM", font = mono, size = 9px, weight = 700, color = muted, align = 2
      Text works[nextOf(current)].title, font = ui, size = 12px, color = body, align = 2, maxLines = 2

    # ── the contact sheet, on its own dark shelf ──
    Panel(left = 0px, top = 632px, right = 0px, height = 184px, fill = #12100C):
      Panel(width = 1280px, height = 1px, fill = rule)
    Text "THE CONTACT SHEET", font = mono, size = 9px, weight = 700, color = body,
         left = 56px, top = 648px
    Text "SELECT A NUMBER TO OPEN A WORK", font = mono, size = 9px, color = muted,
         right = 56px, top = 648px
    Row(left = 56px, top = 672px, gap = 11px):
      for i in 0 ..< 8:
        Column(width = 136px, gap = 5px, alignItems = 1):
          let chosen = i
          if i == current:
            Panel(pad = 3px, radius = 1px, border = 1px, borderColor = accent, fill = matte):
              Stack(width = 64px, height = 80px):
                Canvas draw = artDraw(works[i], 64, 80), width = 64px, height = 80px
                Image source = works[i].art, width = 64px, height = 80px, fit = 0
          else:
            Panel(pad = 3px, radius = 1px, border = 1px, borderColor = #2C2620, fill = chip):
              Stack(width = 64px, height = 80px):
                Canvas draw = artDraw(works[i], 64, 80), width = 64px, height = 80px
                Image source = works[i].art, width = 64px, height = 80px, fit = 0
          if i == current:
            Button "0{i + 1}", width = 72px, height = 20px, font = mono, size = 9px, weight = 700,
                   fill = accent, color = #17130E, radius = 1px, border = 1px, borderColor = accent:
              on tap: current = chosen
            Text works[i].title, width = 136px, font = ui, size = 9px, weight = 600,
                 color = ink, align = 1, maxLines = 1
          else:
            Button "0{i + 1}", width = 72px, height = 20px, font = mono, size = 9px, weight = 700,
                   fill = #221C14, color = body, radius = 1px, border = 1px, borderColor = rule:
              on tap: current = chosen
            Text works[i].title, width = 136px, font = ui, size = 9px, weight = 400,
                 color = muted, align = 1, maxLines = 1
