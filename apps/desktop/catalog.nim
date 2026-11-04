## apps/desktop/catalog.nim
## Registry of the 10 working Yantra OS apps (7 real + editor + files + shell)
## with procedural Skia mini-illustrations and a new-SDK starter template.
##
## Reconciled 2026-11: the bundle's 20-app catalog listed phantom ids with no
## apps/<id>/app.nim (daw, drive, vj, ...). They are DROPPED here — spawning one
## would only ever show the engine's deadEngine placeholder. The type keeps a
## `comingSoon` flag so the store can re-list future apps without a rewrite.

import std/math
import config
import yantra

type
  AppCategory* = enum
    acAll       = "All"
    acSystem    = "System & IDE"
    acGames     = "Arcade & Chess"
    acCreative  = "Creative & Type"
    acScience   = "Sim & Science"
    acTools     = "Tools & Notes"

  CatalogEntry* = object
    id*: string
    title*: string
    subtitle*: string
    category*: AppCategory
    accent*: uint32
    badge*: string
    nimPath*: string
    featured*: bool
    comingSoon*: bool
    isShell*: bool

const
  CatalogApps*: array[10, CatalogEntry] = [
    CatalogEntry(
      id: "typewriter", title: "Marlowe 44 Typewriter",
      subtitle: "Precision mechanical typing sim with Foley audio",
      category: acCreative, accent: ColGold, badge: "TYPE",
      nimPath: "apps/typewriter/app.nim", featured: true
    ),
    CatalogEntry(
      id: "chess", title: "Grandmaster's Study",
      subtitle: "Full chess analysis board with history scrub",
      category: acGames, accent: ColCyan, badge: "CHESS",
      nimPath: "apps/chess/app.nim", featured: true
    ),
    CatalogEntry(
      id: "dna", title: "Helix DNA",
      subtitle: "Real-time animated double-helix visualization",
      category: acScience, accent: ColEmerald, badge: "HELIX",
      nimPath: "apps/dna/app.nim", featured: true
    ),
    CatalogEntry(
      id: "gallery", title: "Galerie Nocturne",
      subtitle: "Interactive 3D art exhibition environment",
      category: acCreative, accent: ColViolet, badge: "3D ART",
      nimPath: "apps/gallery/app.nim", featured: true
    ),
    CatalogEntry(
      id: "calc", title: "Calculator",
      subtitle: "Clean utility calculator, instant arithmetic",
      category: acTools, accent: ColCyan, badge: "CALC",
      nimPath: "apps/calc/app.nim", featured: false
    ),
    CatalogEntry(
      id: "notes", title: "Sticky Notes",
      subtitle: "Minimalist desktop notepad with persistence",
      category: acTools, accent: ColGold, badge: "NOTES",
      nimPath: "apps/notes/app.nim", featured: false
    ),
    CatalogEntry(
      id: "todo", title: "Reactive Todo",
      subtitle: "Task management with list diffing & filters",
      category: acTools, accent: ColEmerald, badge: "TODO",
      nimPath: "apps/todo/app.nim", featured: false
    ),
    CatalogEntry(
      id: "editor", title: "Yantra Studio IDE",
      subtitle: "Nim Code Editor + Hot Reload + Node Graph",
      category: acSystem, accent: ColGold, badge: "IDE",
      nimPath: "apps/editor/app.nim", featured: true
    ),
    CatalogEntry(
      id: "files", title: "Yantra File Manager",
      subtitle: "Workspace Explorer, Source Inspector & Quick-Launch",
      category: acSystem, accent: ColCyan, badge: "FILES",
      nimPath: "apps/files/app.nim", featured: true
    ),
    CatalogEntry(
      id: "desktop", title: "Celestia Desktop Shell",
      subtitle: "This shell — tiling WM, spotlight & dock",
      category: acSystem, accent: ColViolet, badge: "SHELL",
      nimPath: "apps/desktop/app.nim", featured: false,
      isShell: true
    )
  ]

proc appSource*(entry: CatalogEntry): string =
  ## AppView source for a tab. "y:<id>" resolves to apps/<id>/app.wasm next
  ## to the desktop's own folder; a missing wasm shows the engine's
  ## deadEngine placeholder — never a crash.
  "y:" & entry.id

proc findCatalogApp*(appId: string): CatalogEntry =
  for entry in CatalogApps:
    if entry.id == appId:
      return entry
  CatalogEntry(
    id: appId,
    title: appId,
    subtitle: "Not installed yet",
    category: acSystem,
    accent: ColTextDim,
    badge: "SOON",
    nimPath: "apps/" & appId & "/app.nim",
    featured: false,
    comingSoon: true
  )

proc canLaunch*(entry: CatalogEntry): bool =
  not entry.comingSoon and not entry.isShell

# --- Opus DESK registry (state.nim) -------------------------------------------
# The desktop shell reads this generated-style registry: id/name/icon/tint per
# app. Tints are the Caelestia accents (hand-set; do NOT run apps-index.sh).

type
  CatalogApp* = object
    id*, name*, icon*: string
    tint*: int

const catalog*: seq[CatalogApp] = @[
  CatalogApp(id: "typewriter", name: "Marlowe 44 Typewriter", icon: "command", tint: 0xF4D078),
  CatalogApp(id: "chess", name: "Grandmaster's Study", icon: "grid", tint: 0x6BE6E6),
  CatalogApp(id: "dna", name: "Helix DNA", icon: "activity", tint: 0x5CE0A8),
  CatalogApp(id: "gallery", name: "Galerie Nocturne", icon: "palette", tint: 0xA882FF),
  CatalogApp(id: "calc", name: "Calculator", icon: "calculator", tint: 0x6BE6E6),
  CatalogApp(id: "notes", name: "Notes", icon: "file", tint: 0xF4D078),
  CatalogApp(id: "todo", name: "Todos", icon: "checkSquare", tint: 0x5CE0A8),
  CatalogApp(id: "editor", name: "Yantra Studio IDE", icon: "terminal", tint: 0xF4D078),
  CatalogApp(id: "files", name: "Yantra File Manager", icon: "folder", tint: 0x6BE6E6),
  CatalogApp(id: "desktop", name: "Desktop", icon: "home", tint: 0xA882FF)
]

proc drawCardPreview*(d: var Draw; entry: CatalogEntry; x, y, w, h, phase: float32) =
  d = d.rect(x, y, w, h, 0xFF0A0D18'u32, 6.0'f32)
  let cx = x + w * 0.5'f32
  let cy = y + h * 0.5'f32

  case entry.id
  of "editor":
    for i in 0 .. 4:
      let ly = y + 10.0'f32 + float32(i) * 9.0'f32
      let lw = float32(28 + ((i * 19) mod 45))
      let col = if i mod 2 == 0: ColViolet else: ColCyan
      d = d.rect(x + 12.0'f32, ly, lw, 4.0'f32, col, 2.0'f32)
    d = d.rect(cx + 8.0'f32, y + 12.0'f32, 34.0'f32, 18.0'f32, 0xFF1F2947'u32, 4.0'f32)
    d = d.rect(cx + 52.0'f32, y + 28.0'f32, 34.0'f32, 18.0'f32, 0xFF1F2947'u32, 4.0'f32)
    d = d.line(cx + 42.0'f32, y + 21.0'f32, cx + 52.0'f32, y + 37.0'f32, ColGold, 2.0'f32)

  of "files":
    for i in 0 .. 2:
      let fx = x + 16.0'f32 + float32(i) * 44.0'f32
      d = d.rect(fx, y + 16.0'f32, 34.0'f32, 26.0'f32, 0xFF1E2942'u32, 4.0'f32)
      d = d.rect(fx, y + 13.0'f32, 16.0'f32, 6.0'f32, ColCyan, 2.0'f32)

  of "chess":
    let n = 4
    let cw = (w - 24.0'f32) / float32(n)
    let chh = (h - 16.0'f32) / float32(n)
    for r in 0 ..< n:
      for c in 0 ..< n:
        let col = if (r + c) mod 2 == 0: 0xFFE8DCC8'u32 else: 0xFF4A3B2A'u32
        d = d.rect(x + 12.0'f32 + float32(c) * cw, y + 8.0'f32 + float32(r) * chh,
                   cw, chh, col)

  of "dna":
    for i in 0 .. 11:
      let t = float32(i) / 11.0'f32
      let yy = y + 8.0'f32 + t * (h - 16.0'f32)
      let off = sin(phase * 2.0'f32 + t * 6.2831'f32) * (w * 0.28'f32)
      d = d.circle(cx - off, yy, 3.0'f32, ColCyan)
      d = d.circle(cx + off, yy, 3.0'f32, ColEmerald)
      if i mod 3 == 0:
        d = d.line(cx - off, yy, cx + off, yy, ColTextDim, 1.0'f32)

  of "gallery", "desktop":
    d = d.rect(x + 12.0'f32, y + 8.0'f32, w - 24.0'f32, h - 16.0'f32, 0xFF1F2947'u32, 4.0'f32)
    d = d.rect(x + 18.0'f32, y + 14.0'f32, (w - 36.0'f32) * 0.45'f32, h - 28.0'f32, entry.accent, 2.0'f32)
    d = d.circle(cx + (w - 36.0'f32) * 0.22'f32, cy, 10.0'f32, ColGold)

  of "typewriter":
    d = d.rect(x + 12.0'f32, y + 8.0'f32, w - 24.0'f32, 22.0'f32, 0xFFF5F0E1'u32, 2.0'f32)
    for r in 0 .. 1:
      for c in 0 .. 5:
        d = d.circle(x + 22.0'f32 + float32(c) * 12.0'f32,
                     y + 40.0'f32 + float32(r) * 11.0'f32, 4.0'f32, entry.accent)

  of "calc":
    for r in 0 .. 2:
      for c in 0 .. 3:
        d = d.rect(x + 12.0'f32 + float32(c) * 26.0'f32, y + 8.0'f32 + float32(r) * 14.0'f32,
                   22.0'f32, 11.0'f32, 0xFF1F2947'u32, 2.0'f32)

  of "todo", "notes":
    for i in 0 .. 3:
      let ly = y + 10.0'f32 + float32(i) * 11.0'f32
      if entry.id == "todo":
        d = d.rect(x + 14.0'f32, ly, 7.0'f32, 7.0'f32,
                   (if i < 2: ColEmerald else: 0xFF1F2947'u32), 2.0'f32)
      d = d.rect(x + 26.0'f32, ly + 1.0'f32, w - 44.0'f32 - float32(i * 9), 4.5'f32, ColTextMid, 2.0'f32)

  else:
    d = d.circle(cx, cy, h * 0.30'f32, 0x336BE6E6'u32)
    d = d.circle(cx - 18.0'f32, cy - 6.0'f32, 6.0'f32, entry.accent)
    d = d.circle(cx + 18.0'f32, cy + 8.0'f32, 5.0'f32, ColGold)
    d = d.line(cx - 18.0'f32, cy - 6.0'f32, cx + 18.0'f32, cy + 8.0'f32, ColTextMid, 1.5'f32)

proc defaultStarterAppTemplate*(appId: string): string =
  ## Minimal new-SDK app: compiles clean under tools/build-wasm.sh, opens a
  ## window, paints a canvas every frame, counts clicks and keystrokes.
  result = "import ../../sdk/yantra\n\n" &
    "var clicks: int = 0\n" &
    "var keys: int = 0\n" &
    "var scene: Node\n" &
    "var sceneReady = false\n\n" &
    "proc repaint() =\n" &
    "  if sceneReady:\n" &
    "    var d = Draw()\n" &
    "    d = d.rect(0.0'f32, 0.0'f32, 1280.0'f32, 800.0'f32, 0xFF0D101B'u32)\n" &
    "    d = d.circle(640.0'f32, 400.0'f32, 72.0'f32 + float32(clicks mod 40), 0xFFF4D078'u32)\n" &
    "    d = d.text(24.0'f32, 24.0'f32, 16.0'f32, 0xFFF5F7FF'u32, \"Live Hot-Reload! Clicks: \" & $clicks & \" Keys: \" & $keys, 700)\n" &
    "    scene.set(pDraw, d.cmds)\n\n" &
    "proc main() =\n" &
    "  let page = window(\"Yantra App - " & appId & "\", 1280, 800)\n" &
    "  let stage = stack(page)\n" &
    "  scene = canvas(stage, 1280, 800)\n" &
    "  sceneReady = true\n" &
    "  scene.addHandler(evPointerDown, proc() =\n" &
    "    inc clicks\n" &
    "    repaint()\n" &
    "    handled())\n" &
    "  page.addHandler(evKey, proc() =\n" &
    "    let k = lastKey()\n" &
    "    if k.ctrl or k.alt: return\n" &
    "    if k.code >= 32 and k.code < 127:\n" &
    "      inc keys\n" &
    "      repaint()\n" &
    "      handled())\n" &
    "  scene.addHandler(evFrame, proc() = repaint())\n" &
    "  repaint()\n\n" &
    "proc yantra_main*() {.exportc: \"yantra_main\".} =\n" &
    "  main()\n"
