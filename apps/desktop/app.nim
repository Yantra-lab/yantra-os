## The Yantra desktop (DESK). Yantra takes the whole screen: an Arc-style sidebar of tabs, pins
## and folders on the left, a Caelestia-style bar on the right, and between them a rounded screen
## inside a frame where windows float or tile. Every window runs one app of the Yantra web
## ("y:<id>") in its own sandbox. Every m3surface is a setting.
## Sections, in include order: config (the look), tiling (the maths), catalog (the apps),
## state (the behaviour), ui (the pieces), settings (the panel). In the release the six are
## folded into this one file, in that order, so an app stays one file.
## Plan: docs/shell/PLAN.md; design: docs/shell/DESIGN.md.
import std/[strutils, json, math, sequtils]
# [config.nim] ---------------------------------------------------------------------------
## Aura — Yantra's shell design system. Material 3 gives us the semantic colour roles and
## interaction states; Caelestia/Hyprland give us the rounded, translucent surfaces. The
## composition is our own: a browser's tabs on the left, OS spaces on the right, and a useful
## home between them. This is the only place the desktop's visual constants are chosen.

const
  # the modifier every shortcut uses: Super (the Windows key). The fullscreen desktop grabs the
  # keyboard, so Super+1 etc. reach it instead of the operating system.
  modMask* = 0x0C00'i32
  modName* = "Super"

  # Type: real sans-serif UI fonts on the release host, with a dedicated mono face.
  # Noto also gives the shell its Devanagari and international-language coverage.
  uiFont* = "Noto Sans"
  displayFont* = "Noto Sans"
  monoFont* = "DejaVu Sans Mono"

  # Aura: blue hour with a warm champagne counterpoint. Low-chroma surfaces preserve
  # hierarchy; the periwinkle accent is reserved for focus, selection and action.
  primary* = 0xAFBBFF
  onPrimary* = 0x141A33
  primaryContainer* = 0x343D68
  onPrimaryContainer* = 0xE6EAFF
  secondaryContainer* = 0x293149
  onSecondaryContainer* = 0xE5E9FB
  tertiary* = 0xE7BD91
  errorRole* = 0xFF9D96
  errorContainer* = 0x702B32
  m3surface* = 0x0C0E14              ## the frame, the sidebar and the bar
  containerLowest* = 0x080A10
  containerLow* = 0x11141D
  container* = 0x171B25
  containerHigh* = 0x202634
  containerHighest* = 0x2C3446
  onSurface* = 0xF1F3F8
  onSurfaceVariant* = 0xACB3C3       ## readable secondary text, not decorative grey
  outline* = 0x828B9E
  outlineVariant* = 0x333B4C
  stateHover* = rgba(0xE7EBFA, 0.07)  ## M3 state layers
  statePress* = rgba(0xE7EBFA, 0.12)
  clear* = rgba(0x000000, 0.0)
  glassAlpha* = 0.82                  ## surfaces when the glass setting is on
  blurPx* = 32

  # Shape: the design system's radii — 6 (small), 10 (control), 16 (card) and a pill,
  # which is always half the control's height. The one shape with no token is a
  # drawer's corner: a drawer is joined to the screen edge by a concave fillet whose
  # radius is the fillet panel's own side, so the corner and the panel are one
  # geometry and both use drawerRadius (app.nim:filletSksl).
  RsSm* = 6
  RsCtl* = 10
  RsCard* = 16
  drawerRadius* = 28
  frameWidth* = 12                 ## the frame around the rounded screen: a margin, so 4-pt
  screenRadius* = RsCard           ## the screen's inner corners
  windowRadius* = RsCard
  cardRadius* = RsCard
  pillHeight* = 36
  sidebarWidth* = 248
  barWidth* = 56                   ## the right bar: 40 px pills + padding
  gapsIn* = 8
  gapsOut* = 12                    ## the gap between the screen and its overlays
  titleHeight* = 36
  workspaceCount* = 9

  # the Yantra web: the public registry the Library's Discover reads (github.com/Yantra-lab/yantra-web)
  registryHost* = "yantra-lab.github.io"
  registryUrl* = "https://yantra-lab.github.io/yantra-web/index.json"

  # overlays
  spotlightWidth* = 640
  settingsWidth* = 400
  recentCount* = 12

  # motion (Caelestia: expressive spatial ~500 ms, effects ~200 ms)
  moveMs* = 350
  effectMs* = 200
# [tiling.nim] ---------------------------------------------------------------------------
## Tiling (Hyprland's "dwindle"): the first window takes the whole area; each new one splits the
## last window's rectangle in two along its longer side. Pure maths: no UI here.

import std/strutils

type Rect* = object
  x*, y*, w*, h*: float32

proc dwindle*(area: Rect; count: int; gap: float32): seq[Rect] =
  ## `count` rectangles filling `area`, `gap` px apart.
  if count <= 0: return
  result.add area
  for _ in 1 ..< count:
    let last = result.pop()
    if last.w >= last.h:                       # split side by side
      let half = (last.w - gap) / 2
      result.add Rect(x: last.x, y: last.y, w: half, h: last.h)
      result.add Rect(x: last.x + half + gap, y: last.y, w: last.w - half - gap, h: last.h)
    else:                                      # split top and bottom
      let half = (last.h - gap) / 2
      result.add Rect(x: last.x, y: last.y, w: last.w, h: half)
      result.add Rect(x: last.x, y: last.y + half + gap, w: last.w, h: last.h - half - gap)

proc fuzzyScore*(query, text: string): int =
  ## How well `query` matches `text` as a subsequence (case-insensitive): -1 if it does not;
  ## higher when the letters run together or start the text.
  if query.len == 0: return 1
  var qi = 0
  var run = 0
  for i, c in text:
    if qi < query.len and c.toLowerAscii == query[qi].toLowerAscii:
      inc run
      result += run * 2 + (if i == qi: 3 else: 0)
      inc qi
    else:
      run = 0
  if qi < query.len: result = -1
# [catalog.nim] ---------------------------------------------------------------------------
## Generated by tools/apps-index.sh from yantra-os/apps/*/app.json — do not edit.
type CatalogApp* = object
  id*, name*, icon*: string
  tint*: int                 ## the icon tile's colour
const catalog*: seq[CatalogApp] = @[
  CatalogApp(id: "calc", name: "Calculator", icon: "calculator", tint: 0xFF9F0A),
  CatalogApp(id: "chess", name: "Grandmaster's Study", icon: "grid", tint: 0x6BE6E6),
  CatalogApp(id: "coast", name: "Infinite Coastline", icon: "globe", tint: 0xD8B76E),
  CatalogApp(id: "descent", name: "Descent", icon: "activity", tint: 0xFF5A3C),
  CatalogApp(id: "dna", name: "Helix DNA", icon: "activity", tint: 0x10B981),
  CatalogApp(id: "editor", name: "Yantra Studio IDE", icon: "terminal", tint: 0xFF9F0A),
  CatalogApp(id: "files", name: "Yantra File Manager", icon: "folder", tint: 0x8E8E93),
  CatalogApp(id: "gallery", name: "Galerie Nocturne", icon: "presentation", tint: 0x9A6840),
  CatalogApp(id: "gallery3d", name: "Night Gallery", icon: "globe", tint: 0xC9A24A),
  CatalogApp(id: "ink", name: "Sumi", icon: "palette", tint: 0xF4EFE6),
  CatalogApp(id: "kart", name: "Nocturne Rally", icon: "activity", tint: 0xE8C27A),
  CatalogApp(id: "notes", name: "Notes", icon: "file", tint: 0xFFD60A),
  CatalogApp(id: "ocean", name: "Ocean", icon: "activity", tint: 0xE9C887),
  CatalogApp(id: "orrery", name: "Orrery", icon: "globe", tint: 0xC9A24A),
  CatalogApp(id: "poster", name: "Raster / Form", icon: "palette", tint: 0xF06442),
  CatalogApp(id: "todo", name: "Todos", icon: "checkSquare", tint: 0x0A84FF),
  CatalogApp(id: "typewriter", name: "Marlowe 44 Typewriter", icon: "file", tint: 0xF4D078),
]
# [state.nim] ---------------------------------------------------------------------------
## The desktop's state and behaviour: windows (tabs, in Arc's words), spaces, folders, pins,
## the settings every m3surface obeys, Spotlight and the keys. No drawing here (ui.nim, app.nim).

type
  Win = object
    id: int
    address: string              ## "y:<id>", a web address, or "" for a start page
    title, icon: string
    tint: int                    ## its app's icon colour
    folder: string               ## its sidebar folder ("" for none)
    ws: int                      ## the space it is on (1-based)
    shown: bool                  ## false while minimised to the dock
    maxed: bool                  ## zoomed to fill the space
    fx, fy, fw, fh: float32      ## where it floats; fw 0 = not placed yet
    history: seq[string]         ## the addresses it showed, for back and forward
    hpos: int                    ## where in `history` it is
  RegApp = object                ## one app the registry lists
    address, name, icon, category, description: string
    tint: int
  Group = object                 ## the sidebar's windows of one app, taskbar-style
    address: string
    ids: seq[int]
  Hit = object                   ## one Spotlight result
    label, kind, icon: string
    tint: int
    score: int
    run: proc ()

let wins = persistent(newSeq[Win](), "desk.windows")      ## the session: back after a restart
let focused = persistent(0, "desk.focused")                ## the focused window's id (0: none)
let workspace = persistent(1, "desk.workspace")
let tiledSpaces = persistent(newSeq[int](), "desk.tiled")  ## spaces that tile instead of float
let folders = persistent(newSeq[string](), "desk.folders")
let closedFolders = persistent(newSeq[string](), "desk.closedFolders")
let openGroups = persistent(newSeq[string](), "desk.openGroups")  ## groups shown expanded
let pins = persistent(newSeq[string](), "desk.pins")       ## pinned addresses: the sidebar's tiles
let recent = persistent(newSeq[string](), "desk.recent")   ## opened addresses, newest first
let addressDraft = state ""
let tabMenu = state false
let registry = state newSeq[RegApp]()   ## the Yantra web's public apps (Discover)
let registryState = state 0      ## 0 not asked, 1 on its way, 2 here, 3 could not be reached        ## the address bar's tab options menu     ## the sidebar's address bar while it is being edited
let spotlight = state false
let spotOpens = state 0          ## counts openings: each one focuses the search field again
let query = state ""
let sel = state 0                ## the highlighted Spotlight result
let sessionMenu = state false
let chat = persistent(newSeq[AiTurn](), "desk.agent")       ## the agent conversation
let agentDraft = state ""
let thinking = state false
let controlOpen = state false
let dashOpen = state false
let seconds = state ""
let sysCpu = state -1
let sysMem = state -1
let sysDisk = state -1
let sysUptime = state -1
let whoUser = state ""
let whoHost = state ""
let whoOs = state ""
var calYear, calMonth, calDay, calWeekday: int      # today, for the calendar
# the system, read every few seconds (sdk/core/sysinfo.nim); -1 / netUnknown: not known, not shown
let sysBattery = state -1
let sysCharging = state -1
let sysVolume = state -1
let sysMuted = state -1
let sysNet = state netUnknown
let sysWifi = state ""
let locked = persistent(false, "desk.locked")              ## the lock screen is up (stays up across a restart)
let settingsOpen = state false
let passportOpen = state false
let reloadId = state 0           ## a window whose app is being started afresh
let agentOpen = state false
let clock = state ""
let date = state ""
let revealed = state 0          ## the window whose caption is showing (title bars on hover)
var revealToken = 0
let dragId = state 0             ## the window being moved or resized (0: none)
let dragRect = state Rect()      ## its rectangle while the pointer is down
var dragFrom: (float32, float32)
var dragStart: Rect
var dragResize = false
# settings: one switch per m3surface, so any desktop can be made (settings.nim draws them)
const
  titleOnHover* = 0              ## window title bars appear when the pointer reaches the top edge
  titleAlways* = 1
  titleNever* = 2
let showSidebar = persistent(true, "desk.set.sidebar")
let showBar = persistent(true, "desk.set.bar")            ## the right bar
let screenFrame = persistent(true, "desk.set.frame")      ## the frame around a rounded screen
let titleMode = persistent(titleOnHover, "desk.set.titles")
let glass = persistent(false, "desk.set.glass")           ## translucent surfaces over the wallpaper
let compact = persistent(false, "desk.set.compact")       ## denser rows
let showPins = persistent(true, "desk.set.pins")
let barClock = persistent(true, "desk.set.clock")
let deskClock = persistent(true, "desk.set.deskClock")    ## the big clock on the wallpaper
let longDate = state ""
var nextWin = 1
for w in wins.get: nextWin = max(nextWin, w.id + 1)

# ---- addresses --------------------------------------------------------------------------------

proc isWeb(address: string): bool = address.startsWith("http://") or address.startsWith("https://")

const libraryAddress* = "y:library"  ## the Library: every app, one click to run (built into the desktop)

proc isWebApp(address: string): bool =
  ## An app of the Yantra web on some host ("y:draw.example.com"), not one on this machine.
  address.startsWith("y:") and ('.' in address or address.startsWith("y:localhost"))

proc catalogApp(address: string): (bool, CatalogApp) =
  if address.startsWith("y:"):
    for a in catalog:
      if "y:" & a.id == address: return (true, a)

proc appOf(address: string): CatalogApp =
  ## The app behind an address, or a stand-in for a web page or a start page.
  let (ok, a) = catalogApp(address)
  if ok: a
  elif address.len == 0: CatalogApp(name: "New Window", icon: "search", tint: 0x636366)
  elif address == libraryAddress: CatalogApp(id: "library", name: "Library", icon: "grid", tint: 0xC2C1FF)
  elif address.startsWith("y:"): CatalogApp(name: address[2 .. ^1], icon: "globe", tint: 0x8CD2D9)
  else: CatalogApp(name: address.replace("https://", "").replace("http://", ""), icon: "globe",
                   tint: 0x30B0C7)

proc remember(address: string) =
  recent.update(proc (xs: var seq[string]) =
    let i = xs.find(address)
    if i >= 0: xs.delete(i)
    xs.insert(address, 0)
    if xs.len > recentCount: xs.setLen(recentCount))

# ---- windows ----------------------------------------------------------------------------------

proc onSpace(ws: int): seq[Win] =
  for w in wins.get:
    if w.ws == ws: result.add w

proc shownOn(ws: int): seq[Win] =
  for w in wins.get:
    if w.ws == ws and w.shown: result.add w

proc minimised(): seq[Win] =
  for w in wins.get:
    if w.ws == workspace.get and not w.shown: result.add w

proc winById(id: int): (bool, Win) =
  for w in wins.get:
    if w.id == id: return (true, w)

proc editWin(id: int; f: proc (w: var Win)) =
  wins.update(proc (xs: var seq[Win]) =
    for x in xs.mitems:
      if x.id == id: f(x))

proc focusLast() =
  let here = shownOn(workspace.get)
  focused.set(if here.len > 0: here[^1].id else: 0)

proc closeOverlays() =
  spotlight.set(false)
  query.set("")

proc newWindow(address = "") =
  let a = appOf(address)
  let w = Win(id: nextWin, address: address, title: a.name, icon: a.icon, tint: a.tint,
              ws: workspace.get, shown: true)
  inc nextWin
  wins.update(proc (xs: var seq[Win]) = xs.add w)
  focused.set(w.id)
  if address.len > 0: remember(address)

proc navigate(id: int; address: string) =
  ## Window `id` goes to `address`, like a browser tab: what it showed stays in its history.
  let a = appOf(address)
  editWin(id, proc (x: var Win) =
    if x.hpos < x.history.len - 1: x.history.setLen(x.hpos + 1)   # a new branch drops what was ahead
    if x.address.len > 0 and (x.history.len == 0 or x.history[^1] != x.address): x.history.add x.address
    x.history.add address
    x.hpos = x.history.high
    x.address = address; x.title = a.name; x.icon = a.icon; x.tint = a.tint)
  if address.len > 0: remember(address)

proc step(id: int; d: int) =
  ## Back (-1) or forward (+1) in window `id`'s history.
  let (ok, w) = winById(id)
  if not ok: return
  let to = w.hpos + d
  if to < 0 or to > w.history.high: return
  let address = w.history[to]
  let a = appOf(address)
  editWin(id, proc (x: var Win) =
    x.hpos = to; x.address = address; x.title = a.name; x.icon = a.icon; x.tint = a.tint)

proc canStep(d: int): bool =
  let (ok, w) = winById(focused.get)
  ok and w.hpos + d >= 0 and w.hpos + d <= w.history.high and w.history.len > 1

proc runSelected()
proc moveFocused(ws: int)
proc toggleDash()

proc goAddress() =
  ## The address bar's Enter: an address goes to the focused window (or a new one); anything
  ## else is a search.
  let q = addressDraft.get.strip
  if q.len == 0: return
  let (ok, w) = winById(focused.get)
  if q.startsWith("y:") or q.isWeb:
    if ok and w.ws == workspace.get: navigate(w.id, q) else: newWindow(q)
  else:
    query.set(q)
    runSelected()
  addressDraft.set("")

proc reloadWin(id: int) =
  ## Starts window `id`'s app afresh: its view goes for a moment and comes back.
  if id == 0: return
  reloadId.set(id)
  afterMs(60, proc () = reloadId.set(0))

proc clearTabs() =
  ## Zen's "Clear": closes this space's tabs that are in no folder and not pinned.
  let ws = workspace.get
  wins.update(proc (xs: var seq[Win]) =
    for i in countdown(xs.high, 0):
      if xs[i].ws == ws and xs[i].folder.len == 0 and xs[i].address notin pins.get: xs.delete(i))
  focusLast()

proc loadRegistry() =
  ## Reads the registry's index.json once (again after a failure) for the Library's Discover.
  if registryState.get in [1, 2]: return
  registryState.set(1)
  let asked = fetchThen(registryUrl, proc (f: Fetched) =
    if not f.ok:
      registryState.set(3)
      return
    try:
      var apps: seq[RegApp]
      for a in parseJson(f.body){"apps"}:
        let t = a{"tint"}.getStr("#8E8E93").strip(chars = {'#'})
        var tint = 0x8E8E93
        try: tint = parseHexInt(t) except ValueError: discard
        let address = a{"address"}.getStr
        if address.startsWith("y:"):
          apps.add RegApp(address: address, name: a{"name"}.getStr(address), icon: a{"icon"}.getStr("globe"),
                          category: a{"category"}.getStr, description: a{"description"}.getStr, tint: tint)
      registry.set(apps)
      registryState.set(2)
    except CatchableError:
      registryState.set(3))
  if not asked: registryState.set(3)

proc openAddress(address: string) =
  ## Opens `address` in the focused window when that is a start page, else in a new window.
  let (ok, w) = winById(focused.get)
  if ok and w.address.len == 0 and w.ws == workspace.get:
    navigate(w.id, address)
  else:
    newWindow(address)
  closeOverlays()

proc closeWin(id: int) =
  wins.update(proc (xs: var seq[Win]) =
    for i in countdown(xs.high, 0):
      if xs[i].id == id: xs.delete(i))
  if focused.get == id: focusLast()

proc focusWin(id: int) =
  let (ok, w) = winById(id)
  if not ok: return
  if not w.shown: editWin(id, proc (x: var Win) = x.shown = true)
  workspace.set(w.ws)
  focused.set(id)

proc minimise(id: int) =
  editWin(id, proc (x: var Win) = x.shown = false)
  if focused.get == id: focusLast()

proc zoom(id: int) =
  editWin(id, proc (x: var Win) = x.maxed = not x.maxed)
  focused.set(id)

proc launch(a: CatalogApp) =
  ## The dock's click: bring the app's newest window here forward, or open it.
  let address = "y:" & a.id
  var found = 0
  for w in wins.get:
    if w.address == address and w.ws == workspace.get: found = w.id
  if found > 0: focusWin(found) else: newWindow(address)
  closeOverlays()

proc running(a: CatalogApp): bool =
  for w in wins.get:
    if w.address == "y:" & a.id: return true

proc workspaceIds(): seq[int] =
  for n in 1 .. workspaceCount: result.add n

proc usedSpaces(): seq[int] =
  ## The spaces worth showing: those with windows, and the current one.
  for n in 1 .. workspaceCount:
    if n == workspace.get or onSpace(n).len > 0: result.add n

proc showSpace(ws: int) =
  workspace.set(ws)
  focusLast()

proc moveFocused(ws: int) =
  editWin(focused.get, proc (x: var Win) = x.ws = ws)
  focusLast()

proc focusStep(d: int) =
  let here = shownOn(workspace.get)
  if here.len == 0: return
  var i = 0
  for k, w in here:
    if w.id == focused.get: i = k
  focused.set(here[(i + d + here.len) mod here.len].id)

proc tiled(): bool = workspace.get in tiledSpaces.get

proc toggleTiling() =
  let ws = workspace.get
  tiledSpaces.update(proc (xs: var seq[int]) =
    let i = xs.find(ws)
    if i >= 0: xs.delete(i) else: xs.add ws)

proc groupsOn(ws: int): seq[Group] =
  ## The space's windows outside folders, one group per app, in the order they first opened.
  for w in wins.get:
    if w.ws != ws or w.folder.len > 0: continue
    var found = false
    for g in result.mitems:
      if g.address == w.address and w.address.len > 0:
        g.ids.add w.id; found = true
    if not found: result.add Group(address: w.address, ids: @[w.id])

proc toggleGroup(address: string) =
  openGroups.update(proc (xs: var seq[string]) =
    let i = xs.find(address)
    if i >= 0: xs.delete(i) else: xs.add address)

proc focusGroup(address: string) =
  ## A group's row, like a taskbar button: the app's most recent window comes forward.
  var last = 0
  for w in wins.get:
    if w.address == address and w.ws == workspace.get: last = w.id
  if last > 0: focusWin(last)

proc togglePin(address: string) =
  pins.update(proc (xs: var seq[string]) =
    let i = xs.find(address)
    if i >= 0: xs.delete(i) else: xs.add address)

proc toggleFolder(name: string) =
  closedFolders.update(proc (xs: var seq[string]) =
    let i = xs.find(name)
    if i >= 0: xs.delete(i) else: xs.add name)

proc fileIn(id: int; folder: string) =
  editWin(id, proc (x: var Win) = x.folder = folder)

proc newFolder() =
  var n = 1
  while ("Folder " & $n) in folders.get: inc n
  let name = "Folder " & $n
  folders.update(proc (xs: var seq[string]) = xs.add name)

# ---- where windows are ------------------------------------------------------------------------

proc winRect(id: int; w, h: float32): Rect =
  ## Window `id`'s rectangle in the window area: dragged, zoomed, tiled (dwindle) or floating
  ## (new windows cascade from the top left).
  if dragId.get == id: return dragRect.get
  let here = shownOn(workspace.get)
  for i, x in here:
    if x.id == id and x.maxed: return Rect(x: 0, y: 0, w: w, h: h)
  if tiled():
    let rects = dwindle(Rect(x: 0, y: 0, w: w, h: h), here.len, float32(gapsIn))
    for i, x in here:
      if x.id == id: return rects[i]
  for i, x in here:
    if x.id == id:
      if x.fw > 0: return Rect(x: x.fx, y: x.fy, w: x.fw, h: x.fh)
      let cw = min(w * 0.64, 980)
      let ch = min(h * 0.74, 700)
      return Rect(x: (w - cw) / 2 - 90 + float32(34 * (i mod 6)), y: 24 + float32(30 * (i mod 6)),
                  w: cw, h: ch)

proc reveal(id: int) =
  ## Shows window `id`'s caption and hides it 1.2 s after the pointer last moved over it.
  inc revealToken
  let mine = revealToken
  if revealed.get != id: revealed.set(id)
  afterMs(1200, proc () =
    if revealToken == mine and dragId.get == 0: revealed.set(0))

proc dragBegin(id: int; resize: bool; w, h: float32) =
  ## The pointer went down on a floating window's title bar (move) or corner (resize).
  focused.set(id)
  let (ok, x) = winById(id)
  if tiled() or not ok or x.maxed: return
  dragFrom = pointerPage()
  dragStart = winRect(id, w, h)
  dragResize = resize
  dragRect.set(dragStart)
  dragId.set(id)

proc dragMove() =
  if dragId.get == 0: return
  let (px, py) = pointerPage()
  let (dx, dy) = (px - dragFrom[0], py - dragFrom[1])
  dragRect.set(if dragResize: Rect(x: dragStart.x, y: dragStart.y, w: max(dragStart.w + dx, 320),
                                   h: max(dragStart.h + dy, 200))
               else: Rect(x: dragStart.x + dx, y: max(dragStart.y + dy, 0), w: dragStart.w,
                          h: dragStart.h))

proc dragEnd() =
  ## Keeps where the window ended up (saved once, not on every move).
  let id = dragId.get
  if id == 0: return
  let r = dragRect.get
  editWin(id, proc (x: var Win) = (x.fx = r.x; x.fy = r.y; x.fw = r.w; x.fh = r.h))
  dragId.set(0)

# ---- the launcher's calculator (Caelestia's CalcItem) ------------------------------------------

const maxDepth = 1024
  ## How far the calculator's recursion may go, counted in PARSER FRAMES. The parser is a mutual
  ## recursion (sum -> product -> power -> atom -> sum) entered afresh for every parenthesis, so
  ## one level of nesting costs 4 frames and the number is a stack-depth question, not a taste one.
  ## Measured on this parser compiled -d:release, feeding it `(((...1+1...)))`: the 1 MiB
  ## main-thread stack takes nesting 4810 and overflows at 4811 with STATUS_STACK_OVERFLOW
  ## (0xC00000FD), which is ~19244 frames. This budget sits ~19x under that measured cliff, so it
  ## holds where the stack is smaller than the main thread's and where release frames vary.
  ## In input terms: `maxDepth div 4` = 255 levels of parentheses, far deeper than anyone types
  ## (real money and geometry arithmetic is single-digit). Same shape of rule as the repo's 2% and
  ## 24-level thresholds (porting-kit.md): a bound measured off a real failure, set well clear of
  ## both the cliff and real use.

type MathParser = object
  src: string
  i: int
  ok: bool
  depth: int                        ## how deep the recursion is now, in frames: the cap's job

template guarded(m: var MathParser; body: untyped) =
  ## Runs `body` only while the parser is shallow enough, and puts the depth back either way.
  ## Past maxDepth it refuses the way it refuses 1/0 and 5%0 -- `ok` false, so the launcher shows
  ## no answer -- instead of running the stack out.
  inc m.depth
  if m.depth > maxDepth:
    dec m.depth
    m.ok = false
    result = 0
  else:
    try:
      body
    finally:
      dec m.depth

proc skip(m: var MathParser) =
  while m.i < m.src.len and m.src[m.i] == ' ': inc m.i

proc peek(m: var MathParser): char =
  m.skip()
  if m.i < m.src.len: m.src[m.i] else: '\0'

proc sum(m: var MathParser): float

proc atom(m: var MathParser): float =
  m.guarded:
    let c = m.peek()
    if c == '(':
      inc m.i
      result = m.sum()
      if m.peek() == ')': inc m.i else: m.ok = false
    elif c == '-':
      inc m.i
      result = -m.atom()
    else:
      let start = m.i
      while m.i < m.src.len and m.src[m.i] in {'0'..'9', '.'}: inc m.i
      if m.i == start:
        m.ok = false
        return 0
      try: result = parseFloat(m.src[start ..< m.i]) except ValueError: m.ok = false

proc power(m: var MathParser): float =
  m.guarded:
    result = m.atom()
    if m.peek() == '^':                     # whole powers only: the sandbox has no C pow
      inc m.i
      let e = m.power()
      let n = int(e)
      if float(n) != e or n < 0 or n > 64:
        m.ok = false
        return
      var r = 1.0
      for _ in 1 .. n: r *= result
      result = r

proc product(m: var MathParser): float =
  m.guarded:
    result = m.power()
    while m.peek() in {'*', '/', '%'}:
      let op = m.src[m.i]
      inc m.i
      let r = m.power()
      if op == '*': result *= r
      elif r == 0: m.ok = false
      elif op == '/': result /= r
      else: result = result mod r

proc sum(m: var MathParser): float =
  m.guarded:
    result = m.product()
    while m.peek() in {'+', '-'}:
      let op = m.src[m.i]
      inc m.i
      let r = m.product()
      if op == '+': result += r else: result -= r

proc evalMath(src: string; ok: var bool): float =
  ## The value of an arithmetic expression: + - * / ^ %, parentheses, decimals. `ok` false when
  ## `src` is not one (then the launcher shows no answer).
  var m = MathParser(src: src, ok: true)
  result = m.sum()
  m.skip()
  ok = m.ok and m.i == src.len

proc formatValue(v: float): string

proc mathAnswer(q: string): string =
  ## The launcher's answer for `q` when it is a sum (it holds an operator and a digit), or "".
  if q.len < 3 or not q.anyIt(it in {'+', '-', '*', '/', '^', '%'}) or not q.anyIt(it in {'0'..'9'}): return ""
  if not q.allCharsInSet({'0'..'9', '.', ' ', '+', '-', '*', '/', '^', '%', '(', ')'}): return ""
  var ok = false
  let v = evalMath(q, ok)
  if not ok or v != v: return ""
  if abs(v) < 1e15 and abs(v - float(int64(v))) < 1e-9: $int64(v)
  else: formatValue(v)

proc formatValue(v: float): string =
  ## A decimal without the C formatter (the sandbox has none): up to 6 places, trailing zeros cut.
  let neg = v < 0
  var x = abs(v)
  let whole = int64(x)
  var frac = int64((x - float(whole)) * 1_000_000 + 0.5)
  var w = whole
  if frac >= 1_000_000: (inc w; frac -= 1_000_000)
  var f = align($frac, 6, '0')
  while f.len > 0 and f[^1] == '0': f.setLen(f.len - 1)
  (if neg: "-" else: "") & $w & (if f.len > 0: "." & f else: "")

# ---- Spotlight --------------------------------------------------------------------------------

proc hits(q: string): seq[Hit] =
  ## Everything the search field can do for `q`, best first. ">" asks for commands only
  ## (Caelestia's action prefix). Empty: what you open most, then every app.
  var q = q.strip
  if q.len == 0:
    for r in recent.get:
      let a = appOf(r)
      let address = r
      result.add Hit(label: a.name, kind: "Recent", icon: a.icon, tint: a.tint, score: 0,
                     run: proc () = openAddress(address))
      if result.len >= 3: break
    for a in catalog:
      let address = "y:" & a.id
      if address in recent.get[0 ..< min(3, recent.get.len)]: continue
      let app = a
      result.add Hit(label: a.name, kind: "Application", icon: a.icon, tint: a.tint, score: 0,
                     run: proc () = launch(app))
    result.add Hit(label: "Library", kind: "Every app, one click", icon: "grid", tint: primary, score: 0,
                   run: proc () = openAddress(libraryAddress))
    if result.len > 7: result.setLen(7)
    return
  let onlyCommands = q.startsWith(">")
  if onlyCommands: q = q[1 .. ^1].strip
  let answer = mathAnswer(q)
  if answer.len > 0 and not onlyCommands:
    result.add Hit(label: answer, kind: q & " =", icon: "calculator", tint: tertiary, score: 2000,
                   run: proc () = discard)
  if not onlyCommands and (q.startsWith("y:") or q.isWeb):
    result.add Hit(label: q, kind: "Address", icon: "globe", tint: 0x30B0C7, score: 1000,
                   run: proc () = openAddress(q))
  for a in catalog:
    let s = max(fuzzyScore(q, a.name), fuzzyScore(q, a.id))
    if s >= 0 and not onlyCommands:
      let app = a
      result.add Hit(label: a.name, kind: "Application", icon: a.icon, tint: a.tint, score: s + 20,
                     run: proc () =                  # from a new window's page: open it there
                       let (ok, w) = winById(focused.get)
                       if ok and w.address.len == 0: openAddress("y:" & app.id) else: launch(app))
  for w in wins.get:
    let s = fuzzyScore(q, w.title)
    if s >= 0 and w.address.len > 0 and not onlyCommands:
      let id = w.id
      result.add Hit(label: w.title, kind: "Window · Space " & $w.ws, icon: w.icon, tint: w.tint,
                     score: s + 10, run: proc () = (focusWin(id); closeOverlays()))
  let commands = [
    ("New Window", "plus", proc () = (newWindow(); closeOverlays())),
    ("Tile Windows", "split", proc () = (toggleTiling(); closeOverlays())),
    ("Toggle Sidebar", "sidebar", proc () = (showSidebar.set(not showSidebar.get); closeOverlays())),
    ("Toggle Bar", "sidebar", proc () = (showBar.set(not showBar.get); closeOverlays())),
    ("Settings", "sliders", proc () = (settingsOpen.set(true); closeOverlays())),
    ("Dashboard", "grid", proc () = (closeOverlays(); toggleDash())),
    ("Library", "grid", proc () = openAddress(libraryAddress)),
    ("Ask the Agent", "sparkles", proc () = (agentOpen.set(true); closeOverlays())),
    ("New Folder", "folder", proc () = (newFolder(); closeOverlays()))]
  for (name, ic, act) in commands:
    let s = fuzzyScore(q, name)
    if s >= 0: result.add Hit(label: name, kind: "Command", icon: ic, tint: 0x636366, score: s, run: act)
  if not onlyCommands: result.add Hit(label: "Search the web for “" & q & "”", kind: "Web", icon: "search", tint: 0x636366,
                 score: -1, run: proc () =
                   discard openUrl("https://duckduckgo.com/?q=" & q.replace(" ", "+"))
                   closeOverlays())
  for i in 1 ..< result.len:                   # insertion sort: the lists are short
    var j = i
    while j > 0 and result[j].score > result[j - 1].score:
      swap(result[j], result[j - 1]); dec j
  if result.len > 8: result.setLen(8)

proc toggleSpotlight() =
  if not spotlight.get:
    spotOpens.set(spotOpens.get + 1)
    sel.set(0)
  spotlight.set(not spotlight.get)

proc runSelected() =
  let h = hits(query.get)
  if h.len > 0: h[clamp(sel.get, 0, h.high)].run()

# ---- the agent ---------------------------------------------------------------------------------

proc agentSystem(): string =
  ## What the agent knows and may do: the desktop's state now, and the actions it can take.
  const lf = "\n"
  var open = ""
  for w in wins.get:
    open.add "- " & w.title & " (" & (if w.address.len > 0: w.address else: "a new window") &
             ", space " & $w.ws & (if w.shown: "" else: ", minimised") & ")" & lf
  var apps = ""
  for a in catalog: apps.add "- " & a.name & ": y:" & a.id & lf
  "You are the Yantra agent, built into the Yantra desktop. Answer briefly and plainly." & lf &
  "You can act on the desktop: put each action alone on its own line, exactly as written:" & lf &
  "ACTION open y:<id>" & lf & "ACTION space <1-9>" & lf & "ACTION tile" & lf & "ACTION close" & lf &
  "ACTION lock" & lf & "Only act when asked. Current space: " & $workspace.get & "." & lf &
  "Open windows:" & lf & (if open.len > 0: open else: "(none)" & lf) & "Apps on this machine:" & lf & apps

proc runActions(text: string): string =
  ## Carries out the ACTION lines in the agent's answer; returns the rest, to show.
  for line in text.splitLines:
    let l = line.strip
    if l.startsWith("ACTION "):
      let parts = l[7 .. ^1].splitWhitespace
      if parts.len == 0: continue
      case parts[0]
      of "open":
        if parts.len > 1 and (parts[1].startsWith("y:") or parts[1].isWeb): newWindow(parts[1])
      of "space":
        if parts.len > 1:
          try: showSpace(clamp(parseInt(parts[1]), 1, workspaceCount)) except ValueError: discard
      of "tile":
        if not tiled(): toggleTiling()
      of "close": closeWin(focused.get)
      of "lock": locked.set(true)
      else: discard
    elif l.len > 0 or result.len > 0:
      if result.len > 0: result.add "\n"
      result.add line
  result = result.strip

proc sendToAgent() =
  let q = agentDraft.get.strip
  if q.len == 0 or thinking.get: return
  chat.update(proc (xs: var seq[AiTurn]) = xs.add AiTurn(role: "user", text: q))
  agentDraft.set("")
  thinking.set(true)
  let started = aiAsk(chat.get, agentSystem(), proc (ok: bool; text: string) =
    thinking.set(false)
    let shown = if ok: runActions(text) else: "I could not answer: " & text
    chat.update(proc (xs: var seq[AiTurn]) =
      xs.add AiTurn(role: "assistant", text: (if shown.len > 0: shown else: "Done."))))
  if not started:
    thinking.set(false)
    chat.update(proc (xs: var seq[AiTurn]) =
      xs.add AiTurn(role: "assistant", text: "No model is set up. Set ANTHROPIC_API_KEY, or YANTRA_AI_URL " &
                    "for a local model server, and start Yantra again."))

# ---- keys and time ----------------------------------------------------------------------------

const
  weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                "October", "November", "December"]

proc lock() =
  closeOverlays()
  sessionMenu.set(false)
  locked.set(true)

proc handleKey(k: KeyPress) =
  let c = k.code
  if locked.get:                                  # any key unlocks (a password comes with Passport)
    locked.set(false)
    handled()
    return
  if spotlight.get and (c == keyDown or c == keyUp) and (k.mods and modMask) == 0:
    let n = hits(query.get).len
    if n > 0: sel.set((sel.get + (if c == keyDown: 1 else: -1) + n) mod n)
    handled()
    return
  if spotlight.get and c == keyEscape and (k.mods and modMask) == 0:
    closeOverlays()
    handled()
    return
  if (k.mods and modMask) == 0: return
  if c == keySpace: toggleSpotlight()
  elif c == int32('n'): newWindow()
  elif c == int32('w') or c == int32('q'): closeWin(focused.get)
  elif c == int32('m'): minimise(focused.get)
  elif c == int32('f'): toggleTiling()
  elif c == int32('b'): showSidebar.set(not showSidebar.get)
  elif c == int32('d'): toggleSpotlight()
  elif c == int32('l'): lock()
  elif c == int32('a'): agentOpen.set(not agentOpen.get)
  elif c == int32('c'): controlOpen.set(not controlOpen.get)
  elif c == int32('s'): settingsOpen.set(not settingsOpen.get)
  elif c == keyLeft: focusStep(-1)
  elif c == keyRight: focusStep(1)
  elif c >= int32('1') and c <= int32('9'):
    if k.shift: moveFocused(int(c - int32('0'))) else: showSpace(int(c - int32('0')))
  else: return
  handled()

proc readSystem() =
  sysBattery.set(battery())
  sysCharging.set(charging())
  sysVolume.set(volume())
  sysMuted.set(muted())
  sysNet.set(netKind())
  sysWifi.set(if sysNet.get == netWifi: wifiName() else: "")

proc readResources() =
  sysCpu.set(cpuUse())
  sysMem.set(memoryUse())
  sysDisk.set(diskUse())
  sysUptime.set(uptime())
  if whoUser.get.len == 0:
    whoUser.set(userName()); whoHost.set(hostName()); whoOs.set(osName())

proc tickSystem() =
  readSystem()
  if dashOpen.get: readResources()
  afterMs((if controlOpen.get or dashOpen.get: 1500 else: 6000), tickSystem)

proc toggleDash() =
  if not dashOpen.get: readResources()
  dashOpen.set(not dashOpen.get)

proc uptimeText(): string =
  let s = sysUptime.get
  if s < 0: return ""
  let d = s div 86400
  let h = (s mod 86400) div 3600
  let m = (s mod 3600) div 60
  "up " & (if d > 0: $d & "d " else: "") & (if h > 0 or d > 0: $h & "h " else: "") & $m & "m"

proc daysIn(y, m: int): int =
  case m
  of 2: (if (y mod 4 == 0 and y mod 100 != 0) or y mod 400 == 0: 29 else: 28)
  of 4, 6, 9, 11: 30
  else: 31

proc calendarCells(): seq[int] =
  ## This month as a grid starting on Monday: 0 for the blanks before the 1st, then the days.
  if calDay == 0: return
  let firstWd = ((calWeekday - (calDay - 1) mod 7) + 7 * 6) mod 7      # 0 Sunday
  let lead = (firstWd + 6) mod 7                                       # blanks before a Monday start
  for _ in 0 ..< lead: result.add 0
  for d in 1 .. daysIn(calYear, calMonth): result.add d

proc changeVolume(pct: int) =
  if setVolume(pct): sysVolume.set(clamp(pct, 0, 100))

proc toggleMute() =
  if sysMuted.get >= 0 and setMuted(sysMuted.get == 0): sysMuted.set(1 - sysMuted.get)

proc netIcon(): string =
  case sysNet.get
  of netWifi: "wifi"
  of netWired: "ethernet"
  of netOffline: "wifiOff"
  else: ""

proc netTitle(): string =
  case sysNet.get
  of netWifi: "Wi-Fi"
  of netWired: "Ethernet"
  else: "Offline"

proc netNote(): string =
  if sysWifi.get.len > 0: sysWifi.get
  elif sysNet.get == netOffline: "Not connected"
  else: "Connected"

proc tickClock() =
  let (h, m, _) = clockNow()
  let (yy, mo, d, wd) = today()
  (calYear, calMonth, calDay, calWeekday) = (yy, mo, d, wd)
  let (_, _, sec) = clockNow()
  seconds.set(align($sec, 2, '0'))
  clock.set(align($h, 2, '0') & ":" & align($m, 2, '0'))
  date.set(weekdays[clamp(wd, 0, 6)] & " " & $d & " " & months[clamp(mo - 1, 0, 11)])
  longDate.set(weekdayNames[clamp(wd, 0, 6)] & ", " & $d & " " & monthNames[clamp(mo - 1, 0, 11)])
  afterMs(1000, tickClock)


const wallpaper = sksl"""
uniform float2 size;
uniform float time;
float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }
half4 main(float2 fragCoord) {
  float2 uv = fragCoord / size;
  float t = time * 0.012;
  // Aura: two distant pools of light, restrained enough for interface text to stay crisp.
  float2 pa = uv - float2(0.13 + 0.025 * sin(t), 0.92);
  float2 pb = uv - float2(0.90, 0.02 + 0.035 * cos(t));
  pa.x *= size.x / size.y;
  pb.x *= size.x / size.y;
  float a = exp(-4.6 * dot(pa, pa));
  float b = exp(-5.8 * dot(pb, pb));
  float3 col = mix(float3(0.048, 0.054, 0.077), float3(0.029, 0.035, 0.052), uv.y);
  col += float3(0.27, 0.30, 0.58) * a * 0.34;
  col += float3(0.38, 0.20, 0.12) * b * 0.24;
  float vignette = smoothstep(0.24, 0.78, length((uv - 0.5) * float2(1.05, 0.92)));
  col *= 1.0 - 0.34 * vignette;
  // The Yantra horizon: a thin planetary arc, cyan at the left into champagne
  // at the right. It lives below the tools instead of adding another panel.
  float hx = (uv.x - 0.5) * 2.0;
  float horizonY = 0.99 - 0.14 * (1.0 - hx * hx);
  float hd = uv.y - horizonY;
  float core = exp(-hd * hd * 9000.0);
  float halo = exp(-hd * hd * 380.0);
  float3 light = mix(float3(0.24, 0.64, 0.98), float3(1.0, 0.61, 0.25),
                      smoothstep(0.10, 0.90, uv.x));
  col += light * (core * 0.42 + halo * 0.034);
  col += (hash(fragCoord) - 0.5) * 0.006;
  return half4(half3(col), 1);
}
"""

# [ui.nim] ---------------------------------------------------------------------------
## The desktop's pieces: tonal icons, Material switches and buttons, the sidebar (Arc), the bar
## (Caelestia), windows with title bars that appear at the top edge, Spotlight, Launchpad and the
## start page. app.nim puts them on the screen; settings.nim holds the settings panel.

proc filletSksl(cx, cy: int): string =
  ## A drawer's concave corner: `m3surface` everywhere in the square except inside the quarter circle
  ## centred at (cx, cy) (0 or 1, in units of the square's side), which stays see-through.
  "uniform float2 size;\nhalf4 main(float2 p) {\n" &
  "  float d = distance(p, float2(" & $cx & ".0 * size.x, " & $cy & ".0 * size.y));\n" &
  "  float a = clamp(d - size.x + 0.5, 0.0, 1.0);\n" &
  "  return half4(0.0471, 0.0549, 0.0784, 1.0) * half(a);\n}\n"

let filletBottomLeft = filletSksl(0, 0)     # left of a drawer that rises from the bottom edge
let filletBottomRight = filletSksl(1, 0)
let filletTopLeft = filletSksl(0, 1)        # left of a drawer that drops from the top edge
let filletTopRight = filletSksl(1, 1)

proc pill*(h: int): int = h div 2
  ## The pill radius: a control's corner is always half its own height.

proc surf(c: int): int =
  ## A m3surface colour, translucent when the glass setting is on.
  if glass.get: rgba(c, glassAlpha) else: c

proc never(): bool = false

proc Tonal(glyph: string; tint, size: int) {.component.} =
  ## An app's icon, Material style: its glyph in its colour on a soft tonal tile.
  panel(width = size.px, height = size.px, radius = size * 3 div 10, alignItems = center,
        justify = center, fill = rgba(tint, 0.18)):
    icon glyph, size = size * 11 div 20, color = tint

proc IconBtn(name: string; active: proc (): bool; act: proc ()) {.component.} =
  ## A round icon button; filled with the secondary container while what it controls is on.
  row(width = 36.px, height = 36.px, radius = pill(36), alignItems = center, justify = center,
      transition = effectMs.ms, fill = (if active(): secondaryContainer else: clear)):
    icon name, size = 20, color = (if active(): onSecondaryContainer else: onSurfaceVariant)
    hover:
      fill = (if active(): secondaryContainer else: stateHover)
    onClick: act()

proc Switch(isOn: proc (): bool; flip: proc ()) {.component.} =
  ## A Material 3 switch.
  stack @switch(width = 52.px, height = 32.px):
    panel(absolute = true, left = 0, top = 0, width = 52.px, height = 32.px, radius = 16,
          transition = effectMs.ms, fill = (if isOn(): primary else: containerHighest),
          border = (if isOn(): 0 else: 2), borderColor = outline)
    panel(absolute = true, top = (if isOn(): 4 else: 8), left = (if isOn(): 24 else: 8),
          width = (if isOn(): 24 else: 16).px, height = (if isOn(): 24 else: 16).px,
          radius = pill(24), transition = effectMs.ms, fill = (if isOn(): onPrimary else: outline))
    onClick: flip()

proc indexedHits(): seq[(int, Hit)] =
  for i, h in hits(query.get): result.add (i, h)

proc Results() {.component.} =
  column(gap = 4.px, pad = 8.px):
    for p in indexedHits():
      let k = p[0]
      let h = p[1]
      row(height = 48.px, radius = cardRadius, padX = 12.px, gap = 12.px, alignItems = center,
          transition = effectMs.ms, fill = (if sel.get == k: secondaryContainer else: clear)):
        Tonal(h.icon, h.tint, 30)
        text h.label, size = 14, weight = 500, font = uiFont, grow = 1, maxLines = 1,
             color = (if sel.get == k: onSecondaryContainer else: onSurface)
        text h.kind, size = 12, font = uiFont, color = onSurfaceVariant
        hover:
          fill = (if sel.get == k: secondaryContainer else: stateHover)
        onClick: h.run()

proc SearchPill(name, hint: string; big = false) {.component.} =
  row(height = (if big: 56 else: 40).px, radius = (if big: pill(56) else: pill(40)), padLeft = (if big: 20 else: 16).px,
      padRight = 8.px, gap = 12.px, alignItems = center, fill = containerHigh):
    icon "search", size = (if big: 20 else: 16), color = onSurfaceVariant
    input(query, placeholder = hint, grow = 1, size = (if big: 16 else: 14), font = uiFont,
          color = onSurface, fill = clear, border = 0,
          focusAt = (if name == "spot": "spot#" & $spotOpens.get else: name)):
      onInput: sel.set(0)
      onSubmit: runSelected()
      focused:
        borderColor = primary
    if big:
      row(width = 44.px, height = 44.px, radius = pill(44), alignItems = center, justify = center, fill = primary):
        icon "arrowRight", size = 20, color = onPrimary
        onClick: runSelected()

# ---- the sidebar (Arc) ------------------------------------------------------------------------

proc TabRow(w: Win) {.component.} =
  let id = w.id
  row(height = (if compact.get: 32 else: 38).px, radius = 10, padLeft = 8.px, padRight = 4.px, gap = 12.px,
      alignItems = center, transition = effectMs.ms, enter = fly(x = -10, y = 0, ms = 240),
      fill = (if focused.get == id: containerHigh else: clear)):
    Tonal(w.icon, w.tint, 24)
    text w.title, size = 14, font = uiFont, grow = 1, maxLines = 1,
         weight = (if focused.get == id: 600 else: 400),
         color = (if focused.get == id: onSecondaryContainer elif w.shown: onSurface else: onSurfaceVariant)
    row(width = 24.px, height = 24.px, radius = pill(24), alignItems = center, justify = center):
      icon "x", size = 14, color = onSurfaceVariant
      hover:
        fill = stateHover
      onClick: closeWin(id)
    hover:
      fill = (if focused.get == id: secondaryContainer else: stateHover)
    onClick: focusWin(id)

proc inGroup(address: string; id: int): bool =
  let (ok, w) = winById(id)
  ok and w.address == address

proc GroupRows(g: Group) {.component.} =
  ## Several windows of one app: one row with a count, expanded on request (like a taskbar).
  let address = g.address
  let a = appOf(address)
  row @group(height = (if compact.get: 30 else: 36).px, radius = pill(36), padLeft = 8.px, padRight = 4.px, gap = 12.px,
      alignItems = center, transition = effectMs.ms, enter = fly(x = -10, y = 0, ms = 240),
      fill = (if inGroup(address, focused.get): secondaryContainer else: clear)):
    Tonal(a.icon, a.tint, 24)
    text a.name, size = 14, font = uiFont, grow = 1, maxLines = 1,
         weight = (if inGroup(address, focused.get): 600 else: 400),
         color = (if inGroup(address, focused.get): onSecondaryContainer else: onSurface)
    row(height = 20.px, padX = 8.px, radius = 10, alignItems = center, fill = containerHighest):
      text $g.ids.len, size = 11, weight = 600, font = uiFont, color = onSurfaceVariant
    row(width = 24.px, height = 24.px, radius = pill(24), alignItems = center, justify = center):
      icon (if address in openGroups.get: "chevronDown" else: "chevronRight"), size = 14,
           color = onSurfaceVariant
      hover:
        fill = stateHover
      onClick: toggleGroup(address)
    hover:
      fill = (if inGroup(address, focused.get): secondaryContainer else: stateHover)
    onClick: focusGroup(address)
  if address in openGroups.get:
    column(gap = 4.px, padLeft = 16.px):
      for w in onSpace(workspace.get).keyed(w.id):
        if w.address == address and w.folder.len == 0: TabRow(w)

proc showing(address: string): bool =
  let (ok, w) = winById(focused.get)
  ok and w.address == address

proc PinTile(address: string) {.component.} =
  let a = appOf(address)
  row(width = 122.px, height = 52.px, radius = cardRadius, alignItems = center, justify = center,
      transition = effectMs.ms, fill = (if showing(address): secondaryContainer else: containerLow)):
    Tonal(a.icon, a.tint, 28)
    tooltip a.name
    hover:
      fill = containerHigh
    onClick: openAddress(address)

proc FolderRows(name: string) {.component.} =
  row(height = 32.px, radius = 16, padX = 8.px, gap = 12.px, alignItems = center):
    icon (if name in closedFolders.get: "chevronRight" else: "chevronDown"), size = 14, color = onSurfaceVariant
    icon "folder", size = 16, color = primary
    text name, size = 14, weight = 600, font = uiFont, color = onSurface, grow = 1
    hover:
      fill = stateHover
    onClick: toggleFolder(name)
  if name notin closedFolders.get:
    column(gap = 4.px, padLeft = 16.px):
      for w in onSpace(workspace.get).keyed(w.id):
        if w.folder == name: TabRow(w)

proc barSpaces(): seq[int] =
  ## Caelestia shows five spaces; more appear while they hold windows.
  for n in 1 .. workspaceCount:
    if n <= 5 or onSpace(n).len > 0 or n == workspace.get: result.add n

proc focusedAddress(): string =
  let (ok, w) = winById(focused.get)
  if ok and w.ws == workspace.get: w.address else: ""

proc NavBtn(glyph: string; enabled: proc (): bool; act: proc ()) {.component.} =
  row(width = 32.px, height = 32.px, radius = 16, alignItems = center, justify = center):
    icon glyph, size = 16, color = (if enabled(): onSurface else: outlineVariant)
    hover:
      fill = (if enabled(): stateHover else: clear)
    onClick: (if enabled(): act())

proc AddressBar() {.component.} =
  ## Zen's address bar: the focused tab's address (type to go, or to search) and its controls.
  row(height = 40.px, radius = 10, padLeft = 12.px, padRight = 4.px, gap = 8.px, alignItems = center,
      fill = containerHigh):
    input @address(addressDraft, placeholder = (if focusedAddress().len > 0: focusedAddress()
                                                else: "Search or enter address"),
                   grow = 1, size = 14, font = uiFont, color = onSurface, fill = clear, border = 0):
      onSubmit: goAddress()
      focused:
        borderColor = primary
    if focusedAddress().len > 0:
      NavBtn("star", proc (): bool = true, proc () = togglePin(focusedAddress()))
      row @tabMenuBtn(width = 32.px, height = 32.px, radius = 16, alignItems = center, justify = center):
        icon "sliders", size = 16, color = onSurfaceVariant
        hover:
          fill = stateHover
        onClick: tabMenu.set(not tabMenu.get)
        menu @tabMenu(open = tabMenu):
          onDismiss: tabMenu.set(false)
          button "Pin to essentials":
            onClick: (tabMenu.set(false); togglePin(focusedAddress()))
          button "Duplicate tab":
            onClick: (tabMenu.set(false); newWindow(focusedAddress()))
          button "Move to next space":
            onClick: (tabMenu.set(false); moveFocused(min(workspace.get + 1, workspaceCount)))
          button "Close tab":
            onClick: (tabMenu.set(false); closeWin(focused.get))

proc Essential(address: string) {.component.} =
  ## One of the essentials: a pinned app as a square tile, three to a row (Zen).
  let a = appOf(address)
  column(width = 78.px, height = 52.px, radius = 16, alignItems = center, justify = center, transition = effectMs.ms,
         fill = (if showing(address): secondaryContainer else: containerLow)):
    icon a.icon, size = 20, color = a.tint
    tooltip a.name
    hover:
      fill = (if showing(address): secondaryContainer else: containerHigh)
    onClick: openAddress(address)

proc SpaceDots() {.component.} =
  row(gap = 4.px, alignItems = center):
    for n in barSpaces():
      let ws = n
      row(width = (if workspace.get == ws: 18 else: 8).px, height = 8.px, radius = pill(8), transition = moveMs.ms,
          fill = (if workspace.get == ws: primary elif onSpace(ws).len > 0: outline else: outlineVariant)):
        onClick: showSpace(ws)

proc Jewel(glyph: string; lit: proc (): bool; act: proc (); dia = 40) {.component.} =
  ## A bar button, Caelestia-style: round, tonal when on, it squashes a little when pressed.
  row(width = dia.px, height = dia.px, radius = dia div 2, alignItems = center, justify = center,
      transition = effectMs.ms, fill = (if lit(): secondaryContainer else: clear)):
    icon glyph, size = dia * 9 div 20, color = (if lit(): onSecondaryContainer else: onSurfaceVariant)
    hover:
      fill = (if lit(): secondaryContainer else: stateHover)
    pressed:
      scale = 0.9
    onClick: act()

proc TabDot(w: Win) {.component.} =
  ## A tab in the slim sidebar: its icon; the focused one sits on a glowing primary pill.
  let id = w.id
  row(width = 40.px, height = 40.px, radius = pill(40), alignItems = center, justify = center, transition = moveMs.ms,
      enter = pop(scale = 0.6, ms = moveMs),
      fill = (if focused.get == id: primary else: clear),
      shadow = (if focused.get == id: shadow(y = 2, blur = 14, color = rgba(primary, 0.45))
                else: shadow(y = 0, blur = 0, color = clear))):
    icon w.icon, size = 20, color = (if focused.get == id: onPrimary else: w.tint)
    tooltip w.title
    hover:
      fill = (if focused.get == id: primary else: stateHover)
    pressed:
      scale = 0.9
    onClick: focusWin(id)

proc reloading(id: int): bool = reloadId.get == id

proc Logo() {.component.} =
  ## Yantra's mark: opens and folds the sidebar.
  stack @logo(width = 42.px, height = 42.px, radius = 16, clip = true,
              shadow = shadow(y = 2, blur = 16, color = rgba(primary, 0.22))):
    image "brand/yantra-mark.png", width = 42.px, height = 42.px, fit = cover
    tooltip "Yantra  ·  Super+B"
    hover:
      scale = 1.05
    pressed:
      scale = 0.9
    onClick: showSidebar.set(not showSidebar.get)

proc SlimSidebar() {.component.} =
  ## The sidebar folded into a Caelestia bar: the logo, back/forward/reload, this space's tabs, new tab.
  column @sidebar(width = barWidth.px, padY = 16.px, gap = 12.px, alignItems = center, fill = surf(m3surface),
                  enter = fade(ms = effectMs)):
    Logo()
    column(width = 40.px, padY = 4.px, gap = 4.px, radius = pill(40), alignItems = center, fill = container):
      Jewel("arrowLeft", proc (): bool = false, proc () = step(focused.get, -1), 32)
      Jewel("arrowRight", proc (): bool = false, proc () = step(focused.get, 1), 32)
      Jewel("refresh", proc (): bool = false, proc () = reloadWin(focused.get), 32)
    column(width = 40.px, gap = 8.px, alignItems = center, grow = 1, shrink = 1, minHeight = 0, clip = true):
      for w in onSpace(workspace.get).keyed(w.id):
        TabDot(w)
      Jewel("plus", proc (): bool = false, proc () = newWindow())
    Jewel("grid", proc (): bool = showing(libraryAddress), proc () = openAddress(libraryAddress))
    Jewel("sliders", proc (): bool = settingsOpen.get, proc () = settingsOpen.set(not settingsOpen.get))

proc SideToolRow(a: CatalogApp) {.component.} =
  let address = "y:" & a.id
  row(height = 38.px, radius = 10, padX = 8.px, gap = 12.px, alignItems = center):
    Tonal(a.icon, a.tint, 26)
    text a.name, size = 12, weight = 500, font = uiFont, color = onSurfaceVariant, grow = 1
    icon "arrowUpRight", size = 14, color = outline
    hover:
      fill = stateHover
    onClick: openAddress(address)

proc featuredTools(): seq[CatalogApp]

proc WideSidebar() {.component.} =
  ## The sidebar open: back, forward, reload and the address of the focused tab, pins, folders, and
  ## this space's tabs and apps by name.
  column @sidebar(width = sidebarWidth.px, padLeft = 12.px, padRight = 12.px, padY = 12.px, gap = 12.px,
                  fill = surf(m3surface), enter = fly(x = -24, y = 0, ms = moveMs)):
    row(height = 42.px, gap = 8.px, alignItems = center):
      Logo()
      column(grow = 1):
        text "Yantra", size = 16, weight = 600, font = displayFont, color = onSurface
        text "Workspace", size = 11, font = uiFont, color = onSurfaceVariant
      row(height = 34.px, padX = 4.px, radius = pill(34), alignItems = center, fill = containerLow):
        NavBtn("arrowLeft", proc (): bool = canStep(-1), proc () = step(focused.get, -1))
        NavBtn("arrowRight", proc (): bool = canStep(1), proc () = step(focused.get, 1))
        NavBtn("refresh", proc (): bool = focusedAddress().len > 0, proc () = reloadWin(focused.get))
    row(height = 20.px, padX = 8.px, gap = 8.px, alignItems = center):
      text "SPACE 0{workspace}", size = 11, weight = 700, font = monoFont, color = primary, grow = 1
      text "{shownOn(workspace.get).len} OPEN", size = 11, weight = 600, font = monoFont,
           color = onSurfaceVariant
    AddressBar()
    if not spotlight.get and query.get.strip.len > 0:
      column(radius = cardRadius, fill = containerLow):
        Results()
    if showPins.get and pins.get.len > 0:
      row(wrap = true, gap = 8.px):
        for p in pins.get:
          Essential(p)
    column(gap = 4.px, grow = 1, scroll = true):
      for f in folders.get:
        FolderRows(f)
      row(height = 22.px, padX = 8.px, gap = 8.px, alignItems = center):
        panel(grow = 1, height = 1.px, fill = outlineVariant)
        text "Clear", size = 11, weight = 500, font = uiFont, color = onSurfaceVariant
        onClick: clearTabs()
      row(height = 40.px, radius = 10, padX = 12.px, gap = 12.px, alignItems = center,
          fill = rgba(primary, 0.07)):
        icon "plus", size = 16, color = primary
        text "New Tab", size = 14, weight = 600, font = uiFont, color = onSurface
        hover:
          fill = rgba(primary, 0.13)
        onClick: newWindow()
      if groupsOn(workspace.get).len == 0:
        column(padTop = 16.px, gap = 4.px):
          text "YOUR WORKSPACE", size = 11, weight = 700, font = uiFont, color = outline,
               padLeft = 12.px, padBottom = 4.px
          for a in featuredTools(): SideToolRow(a)
          row(height = 38.px, radius = 10, padX = 8.px, gap = 12.px, alignItems = center):
            row(width = 26.px, height = 26.px, radius = 10, alignItems = center, justify = center,
                fill = rgba(primary, 0.12)):
              icon "grid", size = 14, color = primary
            text "All applications", size = 12, weight = 600, font = uiFont, color = onSurfaceVariant, grow = 1
            text "{catalog.len}", size = 11, font = monoFont, color = outline
            hover:
              fill = stateHover
            onClick: openAddress(libraryAddress)
      for g in groupsOn(workspace.get).keyed($g.ids[0] & "#" & $g.ids.len):
        if g.ids.len == 1:
          let (ok, w) = winById(g.ids[0])
          if ok: TabRow(w)
        else:
          GroupRows(g)
    row(height = 40.px, gap = 4.px, alignItems = center):
      Jewel("folder", proc (): bool = false, newFolder)
      Jewel("grid", proc (): bool = showing(libraryAddress), proc () = openAddress(libraryAddress))
      Jewel("sliders", proc (): bool = settingsOpen.get, proc () = settingsOpen.set(not settingsOpen.get))
      spacer(grow = 1)
      Jewel("plus", proc (): bool = false, proc () = newWindow())

proc activeIcon(): string =
  let (ok, w) = winById(focused.get)
  if ok: w.icon else: "grid"

proc activeTint(): int =
  let (ok, w) = winById(focused.get)
  if ok: w.tint else: primary

proc activeTitle(): string =
  ## The focused window's title, when it is on this space.
  let (ok, w) = winById(focused.get)
  if ok and w.ws == workspace.get and w.shown: w.title else: ""

proc SpaceDot(ws: int) {.component.} =
  row(width = 32.px, height = (if workspace.get == ws: 52 else: 32).px, radius = 16, alignItems = center,
      justify = center, transition = moveMs.ms,
      fill = (if workspace.get == ws: primary else: clear)):
    text $ws, size = 12, weight = 600, font = uiFont,
         color = (if workspace.get == ws: onPrimary elif onSpace(ws).len > 0: onSurface else: outline)
    hover:
      fill = (if workspace.get == ws: primary else: stateHover)
    onClick: showSpace(ws)

proc spaceApps(ws: int): seq[Win] =
  ## A space's windows, one per app, for the little icons under its number (Caelestia showWindows).
  var seen: seq[string]
  for w in wins.get:
    if w.ws == ws and w.address notin seen and result.len < 2:   # two at most: the bar stays short
      seen.add w.address
      result.add w

proc spaceHeight(ws: int): int

proc Workspace(ws: int) {.component.} =
  ## One space in the bar: its number, and its apps' icons beneath; over the primary indicator the
  ## number turns onPrimary.
  column(width = 32.px, height = spaceHeight(ws).px, padTop = 8.px, gap = 4.px, radius = 16, alignItems = center,
         transition = moveMs.ms):
    text $ws, size = 14, weight = 600, font = displayFont, lineHeight = 1.0,
         color = (if workspace.get == ws: onPrimary elif onSpace(ws).len > 0: onSurface else: outline)
    for w in spaceApps(ws):
      icon w.icon, size = 14, color = (if workspace.get == ws: onPrimary else: onSurfaceVariant)
    onClick: showSpace(ws)

proc spaceTop(ws: int): int =
  ## Where space `ws` starts in the workspaces pill (its items stack; each is 32 + 16 per app icon).
  result = 4
  for n in 1 ..< ws:
    result += 32 + 16 * spaceApps(n).len + 4

proc spaceHeight(ws: int): int = 32 + 16 * spaceApps(ws).len

proc spacesHeight(): int =
  ## The workspaces pill: every shown space, with 4 px around and between (a stack does not size
  ## itself to its children).
  result = 4
  for n in barSpaces(): result += spaceHeight(n) + 4

proc Workspaces() {.component.} =
  ## Caelestia's workspaces: a pill; occupied spaces lit on a tonal band; a primary indicator that
  ## slides to the current one.
  stack @workspaces(width = 40.px, height = spacesHeight().px, radius = pill(40), fill = container, transition = moveMs.ms):
    for n in barSpaces():
      let ws = n
      if onSpace(ws).len > 0:
        panel(absolute = true, left = 4, top = spaceTop(ws), width = 32.px, height = spaceHeight(ws).px, radius = 16,
              fill = containerHighest, transition = moveMs.ms)
    panel @spaceIndicator(absolute = true, left = 4, top = spaceTop(workspace.get), width = 32.px,
                          height = spaceHeight(workspace.get).px, radius = 16, fill = primary, transition = moveMs.ms)
    column(pad = 4.px, gap = 4.px):
      for n in barSpaces():
        Workspace(n)

proc BarClock() {.component.} =
  ## Caelestia's bar clock: a calendar glyph, the weekday and date, a hairline, the hour, the minute.
  column @barClock(width = 40.px, padY = 8.px, gap = 4.px, radius = pill(40), alignItems = center, transition = effectMs.ms,
                   fill = (if dashOpen.get: secondaryContainer else: clear)):
    icon "clock", size = 16, color = tertiary
    text (if date.get.len > 3: date.get[0 .. 2] else: ""), size = 11, weight = 500, font = uiFont, color = tertiary
    text (if date.get.len > 4: date.get[4 .. ^1].split(' ')[0] else: ""), size = 16, weight = 600,
         font = displayFont, color = tertiary
    panel(width = 22.px, height = 1.px, fill = outlineVariant, marginY = 2.px)
    text @clockH (clock.get.split(":")[0]), size = 16, weight = 600, font = displayFont, color = onSurface
    text (if clock.get.len == 5: clock.get[3 .. 4] else: ""), size = 16, weight = 600, font = displayFont,
         color = onSurface
    hover:
      fill = (if dashOpen.get: secondaryContainer else: stateHover)
    onClick: toggleDash()

proc AgentJewel() {.component.} =
  ## The agent: a gradient jewel, the brightest thing on the screen.
  row @agentBtn(width = 44.px, height = 44.px, radius = pill(44), alignItems = center, justify = center,
                fill = linear(primary, tertiary, 135), transition = effectMs.ms,
                shadow = shadow(y = 3, blur = (if agentOpen.get: 22 else: 14), color = rgba(primary, 0.55))):
    icon "sparkles", size = 20, color = onPrimary
    tooltip "Agent  ·  Super+A"
    hover:
      scale = 1.06
    pressed:
      scale = 0.92
    onClick: agentOpen.set(not agentOpen.get)

proc PassportBtn() {.component.} =
  ## The focused app's passport: its icon wearing a shield; opens what it is and where it came from.
  stack @passportBtn(width = 40.px, height = 40.px):
    row(width = 40.px, height = 40.px, radius = 16, alignItems = center, justify = center, transition = effectMs.ms,
        fill = (if passportOpen.get: secondaryContainer else: rgba(activeTint(), 0.18))):
      icon activeIcon(), size = 20, color = activeTint()
    row(absolute = true, right = -3, bottom = -3, width = 18.px, height = 18.px, radius = pill(18), alignItems = center,
        justify = center, fill = primary, border = 2, borderColor = m3surface):
      icon "shield", size = 11, color = onPrimary
    tooltip "Passport: " & activeTitle()
    pressed:
      scale = 0.92
    onClick: passportOpen.set(not passportOpen.get)

proc Dock() {.component.} =
  ## The dock, down the right edge: the agent, the spaces and their windows, the focused app's
  ## passport, the time, the controls, power.
  column @dock(width = barWidth.px, padY = 16.px, gap = 12.px, alignItems = center, fill = surf(m3surface)):
    AgentJewel()
    Workspaces()
    spacer(grow = 1)
    if activeTitle().len > 0:
      PassportBtn()
    if barClock.get: BarClock()
    column @status(width = 40.px, padY = 12.px, gap = 12.px, radius = pill(40), alignItems = center, transition = effectMs.ms,
                   fill = (if controlOpen.get: secondaryContainer else: container)):
      if netIcon().len > 0:
        icon netIcon(), size = 16, color = onSurface
      if sysVolume.get >= 0:
        icon (if sysMuted.get == 1: "volumeX" else: "volume"), size = 16, color = onSurface
      if sysBattery.get >= 0:
        icon (if sysCharging.get == 1: "batteryCharging" else: "battery"), size = 16, color = onSurface
      icon "sliders", size = 16, color = onSurface
      hover:
        fill = (if controlOpen.get: secondaryContainer else: containerHigh)
      pressed:
        scale = 0.95
      onClick: controlOpen.set(not controlOpen.get)
    row @session(width = 40.px, height = 40.px, radius = pill(40), alignItems = center, justify = center,
                 fill = (if sessionMenu.get: errorContainer else: clear)):
      icon "power", size = 20, color = errorRole
      hover:
        fill = stateHover
      pressed:
        scale = 0.9
      onClick: sessionMenu.set(not sessionMenu.get)

proc QuickTile(glyph, title, note: string; isOn: proc (): bool; act: proc ()) {.component.} =
  ## A control centre tile (Caelestia/Material): tonal when on, quiet when off.
  row(grow = 1, height = 64.px, radius = 16, padX = 16.px, gap = 12.px, alignItems = center, transition = effectMs.ms,
      fill = (if isOn(): primaryContainer else: container)):
    row(width = 36.px, height = 36.px, radius = pill(36), alignItems = center, justify = center,
        fill = (if isOn(): primary else: containerHighest)):
      icon glyph, size = 16, color = (if isOn(): onPrimary else: onSurfaceVariant)
    column(grow = 1, gap = 4.px):
      text title, size = 14, weight = 600, font = uiFont, maxLines = 1,
           color = (if isOn(): onPrimaryContainer else: onSurface)
      text note, size = 11, font = uiFont, maxLines = 1,
           color = (if isOn(): onPrimaryContainer else: onSurfaceVariant)
    hover:
      fill = (if isOn(): primaryContainer else: containerHigh)
    onClick: act()

proc NetTile() {.component.} =
  ## The network, live: the tile's words and icon follow the readings.
  row(grow = 1, height = 64.px, radius = 16, padX = 16.px, gap = 12.px, alignItems = center, transition = effectMs.ms,
      fill = (if sysNet.get != netOffline: primaryContainer else: container)):
    row(width = 36.px, height = 36.px, radius = pill(36), alignItems = center, justify = center,
        fill = (if sysNet.get != netOffline: primary else: containerHighest)):
      icon netIcon(), size = 16, color = (if sysNet.get != netOffline: onPrimary else: onSurfaceVariant)
    column(grow = 1, gap = 4.px):
      text netTitle(), size = 14, weight = 600, font = uiFont, maxLines = 1,
           color = (if sysNet.get != netOffline: onPrimaryContainer else: onSurface)
      text netNote(), size = 11, font = uiFont, maxLines = 1,
           color = (if sysNet.get != netOffline: onPrimaryContainer else: onSurfaceVariant)

proc VolumeSlider() {.component.} =
  ## The output volume: click along the track (0-100 over 200 px). Material 3 slider.
  row(height = 56.px, radius = 16, padX = 16.px, gap = 12.px, alignItems = center, fill = container):
    row(width = 36.px, height = 36.px, radius = pill(36), alignItems = center, justify = center, fill = containerHighest):
      icon (if sysMuted.get == 1: "volumeX" else: "volume"), size = 16, color = onSurfaceVariant
      onClick: toggleMute()
    stack @volumeTrack(width = 200.px, height = 28.px):
      panel(absolute = true, left = 0, right = 0, top = 11, height = 6.px, radius = pill(6), fill = containerHighest)
      panel(absolute = true, left = 0, top = 11, height = 6.px, radius = pill(6), transition = 120.ms,
            width = (max(sysVolume.get, 0) * 2).px, fill = (if sysMuted.get == 1: outline else: primary))
      panel(absolute = true, top = 4, left = max(sysVolume.get, 0) * 2 - 10, width = 20.px, height = 20.px,
            radius = 10, transition = 120.ms, fill = (if sysMuted.get == 1: outline else: primary))
      onPointerDown: (let (x, _) = pointerPos(); changeVolume(int(x / 2)))
    spacer(grow = 1)
    text (if sysVolume.get >= 0: $sysVolume.get else: ""), size = 12, weight = 600, font = uiFont,
         color = onSurfaceVariant

proc ControlCenter() {.component.} =
  column @control(absolute = true, left = gapsOut, bottom = gapsOut, width = settingsWidth.px, z = 16,
                  pad = 16.px, gap = 12.px, radius = 16, fill = surf(containerLow),
                  shadow = shadow(y = 12, blur = 36, color = rgba(0x000000, 0.45)),
                  enter = fly(x = 24, y = 0, ms = moveMs), exit = fade(ms = 140)):
    row(alignItems = center, gap = 12.px, padBottom = 4.px):
      column(grow = 1):
        text "{clock}", size = 26, weight = 500, font = displayFont, color = onSurface
        text "{longDate}", size = 12, font = uiFont, color = onSurfaceVariant
      if sysBattery.get >= 0:
        row(height = 30.px, padX = 12.px, gap = 8.px, radius = pill(30), alignItems = center, fill = container):
          icon (if sysCharging.get == 1: "batteryCharging" else: "battery"), size = 16, color = primary
          text $sysBattery.get & "%", size = 12, weight = 600, font = uiFont, color = onSurface
      IconBtn("sliders", proc (): bool = settingsOpen.get,
              proc () = (controlOpen.set(false); settingsOpen.set(true)))
    if sysNet.get != netUnknown:
      row(gap = 12.px):
        NetTile()
    if sysVolume.get >= 0:
      VolumeSlider()
    row(gap = 12.px):
      QuickTile("split", "Tiling", "This space", tiled, toggleTiling)
      QuickTile("sidebar", "Sidebar", "Tabs and pins", proc (): bool = showSidebar.get,
                proc () = showSidebar.set(not showSidebar.get))
    row(gap = 12.px):
      QuickTile("layers", "Glass", "See-through", proc (): bool = glass.get, proc () = glass.set(not glass.get))
      QuickTile("lock", "Lock", "Super+L", never, lock)

let filletRightTop = filletSksl(0, 0)      # above a drawer that comes out of the right edge
let filletRightBottom = filletSksl(0, 1)   # below it

proc SessionButton(glyph, label: string; hot: bool; action: int; act: proc ()) {.component.} =
  ## One of the session's 80 px buttons (Caelestia): the container colour, the secondary one for the
  ## first; squashes when pressed.
  row(width = 80.px, height = 80.px, radius = 16, alignItems = center, justify = center, windowAction = action,
      transition = effectMs.ms, fill = (if hot: secondaryContainer else: container)):
    icon glyph, size = 26, color = (if hot: onSecondaryContainer else: onSurface)
    tooltip label
    hover:
      fill = (if hot: secondaryContainer else: containerHigh)
    pressed:
      scale = 0.9
    onClick: act()

proc SessionPanel() {.component.} =
  ## Caelestia's session: a drawer out of the right edge, joined by concave corners — lock, the
  ## mark, leave Yantra (sleep, restart and shut down come with the system's power actions).
  column @sessionPanel(absolute = true, top = 0, bottom = 0, right = 0, z = 16, justify = 1, alignItems = 2,
                       enter = fly(x = 60, y = 0, ms = moveMs), exit = fly(x = 40, y = 0, ms = effectMs)):
    panel(width = 28.px, height = 28.px, shader = filletRightTop)
    column(padLeft = 16.px, padY = 16.px, padRight = 48.px, marginRight = -28.px, gap = 16.px, radius = drawerRadius,
           alignItems = center, fill = surf(m3surface)):
      SessionButton("lock", "Lock  ·  Super+L", true, 0, lock)
      stack(width = 80.px, height = 80.px, radius = 16, clip = true):
        image "brand/yantra-mark.png", width = 80.px, height = 80.px, fit = cover
      SessionButton("power", "Leave Yantra", false, 3, proc () = sessionMenu.set(false))
    panel(width = 28.px, height = 28.px, shader = filletRightBottom)

proc LockScreen() {.component.} =
  ## Caelestia's lock: the wallpaper, blurred, and the time on a card. Any key or a click unlocks.
  column @lock(absolute = true, top = 0, left = 0, right = 0, bottom = 0, z = 40, alignItems = center,
               justify = center, gap = 16.px, fill = m3surface,
               enter = fade(ms = moveMs), exit = fade(ms = effectMs)):
    panel(absolute = true, top = 0, left = 0, right = 0, bottom = 0, shader = wallpaper)   # no windows show
    column(pad = 48.px, gap = 8.px, radius = 16, alignItems = center, fill = rgba(containerLow, 0.42),
           backdropBlur = 36.px, border = 1, borderColor = rgba(onSurface, 0.08),
           enter = pop(scale = 0.92, ms = moveMs)):
      stack(width = 88.px, height = 88.px, radius = 16, clip = true, marginBottom = 12.px,
            shadow = shadow(y = 8, blur = 30, color = rgba(primary, 0.20))):
        image "brand/yantra-mark.png", width = 88.px, height = 88.px, fit = cover
      text "YANTRA OS", size = 12, weight = 600, font = uiFont, color = primary, marginBottom = 12.px
      text "{clock}", size = 46, weight = 400, font = displayFont, color = onSurface, lineHeight = 1.0
      text "{longDate}", size = 20, weight = 500, font = displayFont, color = onSurfaceVariant
      row(height = 40.px, padX = 16.px, marginTop = 24.px, gap = 12.px, radius = pill(40), alignItems = center,
          fill = containerHigh):
        icon "lock", size = 16, color = primary
        text "Click or press any key to unlock", size = 14, font = uiFont, color = onSurfaceVariant
    onClick: locked.set(false)

# ---- windows ----------------------------------------------------------------------------------

proc WinButton(glyph: string; isClose: bool; act: proc ()) {.component.} =
  ## A Windows-style caption button: minimise, maximise, close.
  row(width = 44.px, height = titleHeight.px, alignItems = center, justify = center, fill = clear):
    icon glyph, size = 14, color = onSurface
    hover:
      fill = (if isClose: 0xC42B1C else: stateHover)
    onClick: act()

proc Caption(w: Win; aw, ah: Signal[float32]) {.component.} =
  ## A window's caption: its icon and title, and Windows-style minimise, maximise and close.
  let id = w.id
  row @titlebar(height = titleHeight.px, padLeft = 12.px, gap = 8.px, alignItems = center,
                fill = surf(containerLow)):
    Tonal(w.icon, w.tint, 20)
    text w.title, size = 14, weight = 600, font = uiFont, grow = 1, maxLines = 1,
         color = (if focused.get == id: onSurface else: onSurfaceVariant)
    WinButton("minus", false, proc () = minimise(id))
    WinButton("square", false, proc () = zoom(id))
    WinButton("x", true, proc () = closeWin(id))
    onPointerDown: dragBegin(id, false, aw.get, ah.get)
    onPointerMove: (reveal(id); dragMove())
    onPointerUp: dragEnd()

proc EdgeCaption(w: Win; aw, ah: Signal[float32]) {.component.} =
  ## Title bars on hover: a thin strip at the window's top edge; reaching it slides the caption
  ## down over the app, and it goes again soon after the pointer leaves.
  let id = w.id
  panel @edge(absolute = true, top = 0, left = 0, right = 0, height = 8.px, z = 10, fill = clear):
    onPointerMove: reveal(id)
    onClick: (focused.set(id); reveal(id))
  if revealed.get == id:
    column(absolute = true, top = 0, left = 0, right = 0, z = 11,
           shadow = shadow(y = 4, blur = 14, color = rgba(0x000000, 0.35)),
           enter = fly(x = 0, y = -titleHeight, ms = effectMs), exit = fade(ms = 160)):
      Caption(w, aw, ah)

proc greeting(): string =
  let (h, _, _) = clockNow()
  if h < 5: "A little late-night clarity"
  elif h < 12: "Good morning"
  elif h < 17: "Good afternoon"
  elif h < 22: "Good evening"
  else: "Make room for one more idea"

proc toolNote(id: string): string =
  case id
  of "calc": "Numbers, without the noise"
  of "notes": "Thoughts that stay with you"
  of "todo": "A clear path through the day"
  of "kart": "Three laps. One perfect line."
  of "gallery": "Great art, given room to breathe"
  of "poster": "Editorial design, composed by you"
  of "ink": "Ink, water, and beautiful unpredictability"
  of "coast": "Follow the infinite edge"
  of "orrery": "The heavens, driven by clockwork"
  of "editor": "A thought away from running code"
  else: "Open in your workspace"

proc featuredTools(): seq[CatalogApp] =
  ## Three front-door experiences, not every installed app shouting at once. When
  ## the poster bench is installed it leads; the complete catalog lives in Library.
  for id in ["poster", "kart", "gallery", "calc", "notes", "todo"]:
    for a in catalog:
      if a.id == id: result.add a
    if result.len >= 3: return

proc HomeToolCard(a: CatalogApp) {.component.} =
  let address = "y:" & a.id
  column(width = 176.px, height = 134.px, radius = 16, pad = 16.px, gap = 8.px,
         fill = rgba(containerLow, 0.72), border = 1, borderColor = rgba(onSurfaceVariant, 0.08)):
    row(alignItems = center):
      Tonal(a.icon, a.tint, 36)
      spacer(grow = 1)
      icon "arrowUpRight", size = 16, color = outline
    text a.name, size = 16, weight = 600, font = displayFont, color = onSurface
    text toolNote(a.id), size = 11, font = uiFont, color = onSurfaceVariant, maxLines = 2,
         lineHeight = 1.25
    hover:
      fill = rgba(containerHigh, 0.90)
      borderColor = rgba(primary, 0.28)
      y = -2.0
    onClick: openAddress(address)

proc QuickAction(glyph, label: string; act: proc ()) {.component.} =
  row(height = 38.px, padX = 12.px, gap = 8.px, radius = 10, alignItems = center,
      fill = rgba(containerLow, 0.58), border = 1, borderColor = rgba(onSurfaceVariant, 0.07)):
    icon glyph, size = 16, color = primary
    text label, size = 12, weight = 600, font = uiFont, color = onSurface
    hover:
      fill = rgba(primary, 0.10)
      borderColor = rgba(primary, 0.24)
    onClick: act()

proc recentTop(): seq[string] =
  for i, address in recent.get:
    if i >= 3: break
    result.add address

proc RecentRow(address: string) {.component.} =
  let a = appOf(address)
  row(height = 46.px, radius = 10, padX = 12.px, gap = 12.px, alignItems = center,
      fill = rgba(containerLow, 0.48)):
    Tonal(a.icon, a.tint, 28)
    text a.name, size = 14, weight = 600, font = uiFont, color = onSurface, grow = 1, maxLines = 1
    text "OPEN", size = 11, weight = 700, font = monoFont, color = outline
    hover:
      fill = rgba(primary, 0.09)
    onClick: openAddress(address)

proc ShortcutRow(label, keys: string) {.component.} =
  row(height = 30.px, alignItems = center, gap = 12.px):
    text label, size = 11, font = uiFont, color = onSurfaceVariant, grow = 1
    text keys, size = 11, weight = 600, font = monoFont, color = primary

proc HomePage() {.component.} =
  ## The desktop when no window is open. A useful home, not an empty wallpaper:
  ## launch, continue, search, and see the real state of this space.
  column @home(absolute = true, top = 0, left = 0, right = 0, bottom = 0,
               pad = 32.px, gap = 16.px, scroll = true, enter = fade(ms = 260)):
    row(grow = 1, gap = 24.px, alignItems = start):
      column(grow = 1, gap = 24.px, padTop = 16.px):
        column(gap = 12.px):
          row(gap = 8.px, alignItems = center):
            panel(width = 6.px, height = 6.px, radius = pill(6), fill = primary)
            text "{greeting().toUpperAscii()}  /  SPACE 0{workspace}", size = 11, weight = 700,
                 font = uiFont, color = primary
          text "A quieter way\nto make things.", size = 46, weight = 500, font = displayFont,
               color = onSurface, lineHeight = 1.08, maxLines = 2
          text "Your tools, your tabs, and whatever comes next — in one place.", size = 14,
               font = uiFont, color = onSurfaceVariant, maxLines = 2
        column(gap = 12.px):
          SearchPill("home", "Search apps, commands, or open a y: address", true)
          if not spotlight.get and query.get.strip.len > 0:
            column(radius = cardRadius, fill = containerLow):
              Results()
          row(wrap = true, gap = 8.px):
            QuickAction("grid", "Explore apps", proc () = openAddress(libraryAddress))
            QuickAction("plus", "New tab", proc () = newWindow())
            QuickAction("sparkles", "Ask Yantra", proc () = agentOpen.set(true))
        column(gap = 12.px, padTop = 4.px):
          row(alignItems = center):
            text "YOUR TOOLS", size = 11, weight = 700, font = uiFont, color = onSurfaceVariant, grow = 1
            text "{catalog.len} INSTALLED", size = 11, weight = 600, font = monoFont, color = outline
          row(wrap = true, gap = 12.px):
            for a in featuredTools(): HomeToolCard(a)
        if recent.get.len > 0:
          column(gap = 8.px):
            text "PICK UP WHERE YOU LEFT OFF", size = 11, weight = 700, font = uiFont,
                 color = onSurfaceVariant
            for address in recentTop(): RecentRow(address)
        else:
          row(height = 1.px, fill = rgba(onSurfaceVariant, 0.10), marginY = 2.px)
          text "Nothing open in this space. Start with a tool, or search for anything.", size = 11,
               font = uiFont, color = onSurfaceVariant
      column(width = 228.px, gap = 16.px, padTop = 16.px):
        column(width = 228.px, radius = 16, pad = 24.px, gap = 16.px,
               fill = rgba(containerLow, 0.42), border = 1, borderColor = rgba(onSurfaceVariant, 0.065)):
          column(gap = 4.px):
            text "LOCAL TIME", size = 11, weight = 700, font = uiFont, color = primary
            text "{clock}", size = 46, weight = 400, font = displayFont, color = onSurface, lineHeight = 1.1
            text "{longDate}", size = 12, font = uiFont, color = onSurfaceVariant, maxLines = 2
          panel(height = 1.px, fill = rgba(onSurfaceVariant, 0.12))
          column(gap = 8.px):
            text "SPACE 0{workspace}", size = 11, weight = 700, font = monoFont, color = tertiary
            text "{shownOn(workspace.get).len} active windows", size = 14, weight = 600,
                 font = uiFont, color = onSurface
            text "{wins.get.len} windows across your desktop", size = 11, font = uiFont,
                 color = onSurfaceVariant, maxLines = 2
          row(height = 34.px, padX = 12.px, radius = 10, gap = 8.px, alignItems = center,
              fill = rgba(primary, 0.10)):
            icon "grid", size = 14, color = primary
            text "Manage this space", size = 11, weight = 600, font = uiFont, color = onSurface
            onClick: toggleDash()
        column(width = 228.px, radius = 16, pad = 16.px, gap = 4.px,
               fill = rgba(containerLowest, 0.20)):
          text "AT YOUR FINGERTIPS", size = 11, weight = 700, font = uiFont,
               color = onSurfaceVariant, padBottom = 8.px
          ShortcutRow("Search everything", "SUPER D")
          ShortcutRow("Open a new tab", "SUPER N")
          ShortcutRow("Switch spaces", "SUPER 1–9")
          ShortcutRow("Fold the sidebar", "SUPER B")

proc StartPage(id: int) {.component.} =
  ## The same language at window scale: one clear action, real apps and recent work.
  column(grow = 1, padTop = 32.px, padX = 32.px, gap = 24.px, scroll = true, fill = surf(containerLow)):
    column(gap = 8.px):
      text "NEW TAB  /  SPACE 0{workspace}", size = 11, weight = 700, font = uiFont, color = primary
      text "Where to next?", size = 34, weight = 500, font = displayFont, color = onSurface
      text "Open an app, continue your work, or type an address.", size = 14, font = uiFont,
           color = onSurfaceVariant
    column(gap = 12.px):
      SearchPill("start" & $id, "Search apps, commands, or a y: address", true)
      if not spotlight.get and query.get.strip.len > 0:
        column(radius = cardRadius, fill = containerLow):
          Results()
    column(gap = 12.px):
      text "YOUR TOOLS", size = 11, weight = 700, font = uiFont, color = onSurfaceVariant
      row(wrap = true, gap = 12.px):
        for a in featuredTools(): HomeToolCard(a)
    if recent.get.len > 0:
      column(gap = 8.px):
        text "RECENT", size = 11, weight = 700, font = uiFont, color = onSurfaceVariant
        for address in recentTop(): RecentRow(address)

proc LibraryCard(address: string) {.component.} =
  ## One app in the Library: its icon, name and where it comes from; a click runs it.
  let a = appOf(address)
  row(width = 240.px, height = 72.px, radius = cardRadius, padX = 16.px, gap = 16.px, alignItems = center,
      fill = containerLow):
    Tonal(a.icon, a.tint, 44)
    column(grow = 1, gap = 4.px):
      text a.name, size = 14, weight = 600, font = uiFont, color = onSurface, maxLines = 1
      text (if address.isWebApp: "Yantra web · " & address[2 .. ^1] else: "On this computer"), size = 11,
           font = uiFont, color = onSurfaceVariant, maxLines = 1
    row(height = 30.px, padX = 16.px, radius = pill(30), alignItems = center, fill = primary):
      text "Open", size = 12, weight = 600, font = uiFont, color = onPrimary
    hover:
      fill = containerHigh
    onClick: openAddress(address)

proc DiscoverCard(r: RegApp) {.component.} =
  ## A public app of the Yantra web: what it is, and one click to run it (it downloads on the way).
  let address = r.address
  column(width = 240.px, pad = 16.px, gap = 12.px, radius = cardRadius, fill = containerLow):
    row(gap = 12.px, alignItems = center):
      Tonal(r.icon, r.tint, 44)
      column(grow = 1, gap = 4.px):
        text r.name, size = 14, weight = 600, font = uiFont, color = onSurface, maxLines = 1
        text r.category, size = 11, font = uiFont, color = onSurfaceVariant, maxLines = 1
    text r.description, size = 12, font = uiFont, color = onSurfaceVariant, maxLines = 2
    row(height = 32.px, radius = 16, alignItems = center, justify = center, fill = primary):
      text "Get and open", size = 12, weight = 600, font = uiFont, color = onPrimary
      onClick: openAddress(address)
    hover:
      fill = containerHigh

proc webAppsSeen(): seq[string] =
  for r in recent.get:
    if r.isWebApp: result.add r

proc LibraryPage(id: int) {.component.} =
  ## The Library: every app — on this computer and from the Yantra web — one click to run; and any
  ## address can be opened. Discover (a public registry) comes when the registry is published.
  loadRegistry()
  column @library(grow = 1, padTop = 48.px, padX = 32.px, gap = 24.px, scroll = true, fill = surf(container)):
    row(alignItems = center, gap = 16.px):
      Tonal("grid", primary, 48)
      column(grow = 1):
        text "Library", size = 26, weight = 600, font = displayFont, color = onSurface
        text "Every app here runs in its own sandbox. One click opens it.", size = 14, font = uiFont,
             color = onSurfaceVariant
    column(gap = 12.px):
      text "Open any app by its address", size = 14, weight = 600, font = uiFont, color = onSurfaceVariant
      SearchPill("lib" & $id, "y:app.example.com, or an app's name", true)
      if not spotlight.get and query.get.strip.len > 0:
        column(radius = cardRadius, fill = containerLow):
          Results()
    column(gap = 12.px):
      text "On this computer", size = 14, weight = 600, font = uiFont, color = onSurfaceVariant
      row(wrap = true, gap = 12.px):
        for a in catalog:
          LibraryCard("y:" & a.id)
    if webAppsSeen().len > 0:
      column(gap = 12.px):
        text "From the Yantra web", size = 14, weight = 600, font = uiFont, color = onSurfaceVariant
        row(wrap = true, gap = 12.px):
          for r in webAppsSeen():
            LibraryCard(r)
    column(gap = 12.px):
      row(gap = 12.px, alignItems = center):
        text "Discover", size = 14, weight = 600, font = uiFont, color = onSurfaceVariant, grow = 1
        text (case registryState.get
              of 1: "Loading…"
              of 3: "The Yantra web could not be reached"
              else: ""), size = 12, font = uiFont, color = onSurfaceVariant
      row(wrap = true, gap = 12.px):
        for r in registry.get:
          DiscoverCard(r)

proc WindowBody(w: Win) {.component.} =
  if w.address.len == 0:
    StartPage(w.id)
  elif w.address == libraryAddress:
    LibraryPage(w.id)
  elif w.address.isWeb:
    let address = w.address
    column(grow = 1, alignItems = center, justify = center, gap = 16.px, fill = surf(container)):
      text "Web pages open here once the native web view lands.", size = 14, font = uiFont,
           color = onSurfaceVariant
      row(height = 40.px, padX = 16.px, radius = pill(40), alignItems = center, fill = primary):
        text "Open in Browser", size = 14, weight = 600, font = uiFont, color = onPrimary
        onClick: discard openUrl(address)
  elif reloadId.get != w.id:
    appview(source = w.address, grow = 1)

# ---- overlays ---------------------------------------------------------------------------------

proc arcPath(frac: float): string =
  ## A ring's progress as SVG path data on a 24-unit square: from the top, clockwise.
  let f = clamp(frac, 0.0, 0.999)
  if f <= 0.0: return ""
  let a = f * 2 * PI
  let x = 12 + 9 * sin(a)
  let y = 12 - 9 * cos(a)
  "M 12 3 A 9 9 0 " & (if f > 0.5: "1" else: "0") & " 1 " & $x & " " & $y

proc Ring(glyph: string; value: proc (): int) {.component.} =
  ## Caelestia's resource meter: a track, the use as a primary arc, the icon inside.
  stack(width = 64.px, height = 64.px):
    path(d = "M 12 3 A 9 9 0 1 1 11.99 3", stroke = 2.4, color = containerHighest, width = 64.px, height = 64.px,
         absolute = true, left = 0, top = 0)
    path(d = arcPath(max(value(), 0) / 100), stroke = 2.4, color = primary, width = 64.px, height = 64.px,
         absolute = true, left = 0, top = 0)
    row(absolute = true, left = 0, top = 0, width = 64.px, height = 64.px, alignItems = center, justify = center):
      icon glyph, size = 20, color = onSurfaceVariant

proc Dashboard() {.component.} =
  ## Caelestia's dashboard: a drawer that drops from the top edge of the frame — who and where,
  ## the time, this month, and the machine's load. Click the bar's clock.
  row @dashboard(absolute = true, left = 0, right = 0, top = 0, z = 30, justify = 1, alignItems = 0,
                 enter = fly(x = 0, y = -60, ms = moveMs), exit = fly(x = 0, y = -40, ms = effectMs)):
    panel(width = 28.px, height = 28.px, shader = filletTopLeft)
    column(padX = 16.px, padBottom = 16.px, padTop = 48.px, marginTop = -28.px, gap = 12.px, radius = drawerRadius,
           fill = surf(m3surface)):
      row(gap = 12.px, padX = 16.px, padY = 16.px, radius = 16, alignItems = center, fill = container):
        row(width = 64.px, height = 64.px, radius = pill(64), alignItems = center, justify = center, fill = primaryContainer):
          text (if whoUser.get.len > 0: $whoUser.get[0].toUpperAscii else: "?"), size = 26, weight = 600,
               font = displayFont, color = onPrimaryContainer
        column(grow = 1, gap = 4.px):
          text (if whoUser.get.len > 0: whoUser.get else: "You"), size = 20, weight = 600, font = displayFont,
               color = onSurface
          text (if whoHost.get.len > 0: "@" & whoHost.get else: ""), size = 12, font = uiFont, color = onSurfaceVariant
        column(gap = 4.px, alignItems = 2):
          text whoOs.get, size = 12, weight = 500, font = uiFont, color = primary
          text uptimeText(), size = 12, font = uiFont, color = onSurfaceVariant
      row(gap = 12.px, alignItems = 4):
        column(width = 110.px, padY = 16.px, radius = 16, alignItems = center, justify = center,
               fill = container):
          text (clock.get.split(":")[0]), size = 34, weight = 600, font = displayFont, color = tertiary, lineHeight = 1.0
          text "•••", size = 20, font = displayFont, color = primary, lineHeight = 1.0
          text (if clock.get.len == 5: clock.get[3 .. 4] else: ""), size = 34, weight = 600, font = displayFont,
               color = tertiary, lineHeight = 1.0
          text "•••", size = 20, font = displayFont, color = primary, lineHeight = 1.0
          text "{seconds}", size = 34, weight = 600, font = displayFont, color = tertiary, lineHeight = 1.0
        column(width = 7 * 36 + 32, pad = 16.px, gap = 8.px, radius = 16, fill = container):
          text (if calMonth > 0: monthNames[calMonth - 1] & " " & $calYear else: ""), size = 16, weight = 600,
               font = displayFont, color = primary, padLeft = 4.px
          row(width = (7 * 36).px):
            for wd in ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]:
              text wd, size = 11, weight = 600, font = uiFont, color = onSurfaceVariant, width = 36.px, align = center
          row(width = (7 * 36).px, wrap = true):
            for day in calendarCells():
              let dd = day
              row(width = 36.px, height = 32.px, alignItems = center, justify = center):
                row(width = 30.px, height = 30.px, radius = pill(30), alignItems = center, justify = center,
                    fill = (if dd == calDay: primary else: clear)):
                  text (if dd > 0: $dd else: ""), size = 12, weight = (if dd == calDay: 700 else: 400), font = uiFont,
                       color = (if dd == calDay: onPrimary else: onSurface)
        column(pad = 16.px, gap = 12.px, radius = 16, alignItems = center, justify = center, fill = container):
          Ring("cpu", proc (): int = sysCpu.get)
          Ring("layers", proc (): int = sysMem.get)
          Ring("hardDrive", proc (): int = sysDisk.get)
    panel(width = 28.px, height = 28.px, shader = filletTopRight)

proc LauncherItem(k: int; h: Hit) {.component.} =
  ## One result (Caelestia AppItem): the icon at 80% of the row, the name, a line under it.
  row(height = 57.px, radius = 16, padX = 12.px, gap = 12.px, alignItems = center, transition = effectMs.ms,
      fill = (if sel.get == k: rgba(onSurface, 0.08) else: clear)):
    Tonal(h.icon, h.tint, 42)
    column(grow = 1, gap = 4.px):
      text h.label, size = 14, font = uiFont, color = onSurface, maxLines = 1
      text h.kind, size = 12, font = uiFont, color = outline, maxLines = 1
    hover:
      fill = (if sel.get == k: rgba(onSurface, 0.08) else: rgba(onSurface, 0.05))
    onClick: h.run()

proc Launcher() {.component.} =
  ## Caelestia's launcher: a drawer that rises from the bottom edge of the frame, the search field
  ## at its foot, up to seven results above it. Super+Space or Super+D.
  row @launcher(absolute = true, left = 0, right = 0, bottom = 0, z = 30, justify = 1, alignItems = 2,
                enter = fly(x = 0, y = 60, ms = moveMs), exit = fly(x = 0, y = 40, ms = effectMs)):
    panel(width = 28.px, height = 28.px, shader = filletBottomLeft)
    column(width = 632.px, padX = 16.px, padTop = 16.px, padBottom = 48.px, marginBottom = -28.px, gap = 12.px,
           radius = drawerRadius, fill = surf(m3surface)):
      column(gap = 4.px):
        for p in indexedHits():
          LauncherItem(p[0], p[1])
      row(height = 52.px, radius = pill(52), padLeft = 16.px, padRight = 16.px, gap = 12.px, alignItems = center,
          fill = container):
        icon "search", size = 20, color = onSurfaceVariant
        input(query, placeholder = "Type \">\" for commands", grow = 1, size = 14, font = uiFont,
              color = onSurface, fill = clear, border = 0,
              focusAt = "spot#" & $spotOpens.get):
          onInput: sel.set(0)
          onSubmit: runSelected()
          focused:
            borderColor = primary
    panel(width = 28.px, height = 28.px, shader = filletBottomRight)

proc Bubble(t: AiTurn) {.component.} =
  let mine = t.role == "user"
  row(justify = (if mine: 2 else: 0)):             # 2 last, 0 start
    column(maxWidth = 300.px, padX = 16.px, padY = 12.px, radius = 16, enter = fly(y = 8, ms = effectMs),
           fill = (if mine: primaryContainer else: containerHigh)):
      text t.text, size = 14, font = uiFont, lineHeight = 1.4,
           color = (if mine: onPrimaryContainer else: onSurface)

proc Suggestion(label: string) {.component.} =
  row(height = 34.px, padX = 16.px, radius = pill(34), alignItems = center, fill = clear, border = 1,
      borderColor = outlineVariant):
    text label, size = 12, weight = 500, font = uiFont, color = onSurfaceVariant
    hover:
      fill = stateHover
    onClick: (agentDraft.set(label); sendToAgent())

proc PassportPanel() {.component.} =
  ## The focused app's passport: its address, where it came from, how it runs; its controls.
  column @passport(absolute = true, right = gapsOut, top = gapsOut, width = settingsWidth.px, z = 16, pad = 16.px,
                   gap = 16.px, radius = 16, fill = surf(containerLow),
                   shadow = shadow(y = 12, blur = 36, color = rgba(0x000000, 0.45)),
                   enter = fly(x = 24, y = 0, ms = moveMs), exit = fade(ms = 140)):
    row(alignItems = center, gap = 16.px):
      Tonal(activeIcon(), activeTint(), 48)
      column(grow = 1, gap = 4.px):
        text activeTitle(), size = 20, weight = 600, font = displayFont, color = onSurface
        text focusedAddress(), size = 12, font = monoFont, color = onSurfaceVariant
      IconBtn("x", never, proc () = passportOpen.set(false))
    column(gap = 8.px, pad = 16.px, radius = 16, fill = container):
      row(gap = 12.px, alignItems = center):
        icon "shield", size = 16, color = primary
        text "Runs in its own sandbox", size = 14, weight = 500, font = uiFont, color = onSurface
      text (if focusedAddress().isWebApp: "From the Yantra web: " & focusedAddress()[2 .. ^1]
            elif focusedAddress().len > 0: "Installed on this computer" else: ""), size = 12, font = uiFont,
           color = onSurfaceVariant
      text "It reaches only what it asks for and you allow. Per-app permissions and sign-ins arrive " &
           "with Passport.", size = 12, font = uiFont, color = onSurfaceVariant
    row(gap = 8.px):
      QuickTile("refresh", "Reload", "Start it afresh", proc (): bool = false, proc () = reloadWin(focused.get))
      QuickTile("star", "Pin", "To essentials", proc (): bool = focusedAddress() in pins.get,
                proc () = togglePin(focusedAddress()))

proc AgentPanel() {.component.} =
  column @agent(absolute = true, top = gapsOut, right = gapsOut, bottom = gapsOut, width = settingsWidth.px,
                z = 15, pad = 16.px, gap = 12.px, radius = 16, fill = surf(containerLow),
                shadow = shadow(y = 12, blur = 36, color = rgba(0x000000, 0.45)),
                enter = fly(x = 24, y = 0, ms = moveMs), exit = fade(ms = 140)):
    row(alignItems = center, gap = 12.px):
      Tonal("sparkles", primary, 36)
      column(grow = 1):
        text "Agent", size = 20, weight = 600, font = displayFont, color = onSurface
        text (case aiReady()
              of 1: "Claude"
              of 2: "Local model"
              else: "No model set up"), size = 12, font = uiFont, color = onSurfaceVariant
      IconBtn("refresh", never, proc () = chat.set(@[]))
      IconBtn("x", never, proc () = agentOpen.set(false))
    column(grow = 1, gap = 12.px, scroll = true):
      if chat.get.len == 0:
        column(gap = 12.px, padTop = 8.px):
          text "Ask anything, or tell it what to do on the desktop.", size = 14, font = uiFont,
               color = onSurfaceVariant
          row(wrap = true, gap = 8.px):
            Suggestion("Open Notes")
            Suggestion("Tile my windows")
            Suggestion("What is open?")
      for t in chat.get:
        Bubble(t)
      if thinking.get:
        row(gap = 8.px, alignItems = center, padLeft = 4.px, enter = fade(ms = effectMs)):
          Tonal("sparkles", primary, 22)
          text "Thinking…", size = 12, font = uiFont, color = onSurfaceVariant
    row(height = 48.px, radius = pill(48), padLeft = 16.px, padRight = 8.px, gap = 8.px, alignItems = center,
        fill = containerHigh):
      input @agentInput(agentDraft, placeholder = "Message the agent", grow = 1, size = 14, font = uiFont,
                        color = onSurface, fill = clear, border = 0,
                        focusAt = "agent#" & $agentOpen.get):
        onSubmit: sendToAgent()
        focused:
          borderColor = primary
      row(width = 36.px, height = 36.px, radius = pill(36), alignItems = center, justify = center,
          fill = (if thinking.get: containerHighest else: primary)):
        icon "arrowRight", size = 16, color = (if thinking.get: outline else: onPrimary)
        onClick: sendToAgent()

# [settings.nim] ---------------------------------------------------------------------------
## Settings, after Caelestia's Nexus: a window with a navigation pane (search, then the pages) and
## the page beside it. Every switch is saved (state.nim) and takes effect at once; every reading
## is the machine's own.

type NexusPage = object
  id, label, icon: string

const nexusPages = [
  NexusPage(id: "style", label: "Style", icon: "palette"),
  NexusPage(id: "panels", label: "Panels", icon: "sidebar"),
  NexusPage(id: "network", label: "Network", icon: "wifi"),
  NexusPage(id: "audio", label: "Audio", icon: "volume"),
  NexusPage(id: "apps", label: "Apps", icon: "grid"),
  NexusPage(id: "agent", label: "Agent", icon: "sparkles"),
  NexusPage(id: "about", label: "About", icon: "yantra")]

let nexusPage = state "style"
let nexusSearch = state ""

proc shownPages(): seq[NexusPage] =
  let q = nexusSearch.get.strip
  for p in nexusPages:
    if q.len == 0 or fuzzyScore(q, p.label) >= 0: result.add p

proc SettingRow(title, note: string; isOn: proc (): bool; flip: proc ()) {.component.} =
  row(height = 64.px, padX = 16.px, gap = 16.px, radius = 16, alignItems = center, fill = container):
    column(grow = 1, gap = 4.px):
      text title, size = 14, weight = 500, font = uiFont, color = onSurface
      text note, size = 12, font = uiFont, color = onSurfaceVariant, maxLines = 1
    Switch(isOn, flip)

proc InfoRow(title: string; value: proc (): string) {.component.} =
  row(height = 52.px, padX = 16.px, gap = 16.px, radius = 16, alignItems = center, fill = container):
    text title, size = 14, weight = 500, font = uiFont, color = onSurface, grow = 1
    text value(), size = 14, font = uiFont, color = onSurfaceVariant, maxLines = 1

proc Segment(label: string; value: int) {.component.} =
  row(grow = 1, height = 36.px, radius = pill(36), alignItems = center, justify = center, transition = effectMs.ms,
      fill = (if titleMode.get == value: secondaryContainer else: clear)):
    text label, size = 14, weight = 500, font = uiFont,
         color = (if titleMode.get == value: onSecondaryContainer else: onSurfaceVariant)
    hover:
      fill = (if titleMode.get == value: secondaryContainer else: stateHover)
    onClick: titleMode.set(value)

proc Section(title: string) {.component.} =
  text title, size = 14, weight = 600, font = uiFont, color = primary, padLeft = 8.px, padTop = 12.px

proc flipper(s: Signal[bool]): proc () = (proc () = s.set(not s.get))
proc reader(s: Signal[bool]): proc (): bool = (proc (): bool = s.get)

proc NavItem(p: NexusPage) {.component.} =
  ## A page in the navigation pane: a pill, filled while it is the page shown.
  let id = p.id
  row(height = 48.px, radius = pill(48), padX = 16.px, gap = 16.px, alignItems = center, transition = effectMs.ms,
      fill = (if nexusPage.get == id: secondaryContainer else: clear)):
    icon p.icon, size = 20, color = (if nexusPage.get == id: onSecondaryContainer else: onSurfaceVariant)
    text p.label, size = 14, weight = (if nexusPage.get == id: 600 else: 500), font = uiFont,
         color = (if nexusPage.get == id: onSecondaryContainer else: onSurface)
    hover:
      fill = (if nexusPage.get == id: secondaryContainer else: stateHover)
    pressed:
      scale = 0.97
    onClick: nexusPage.set(id)

proc PageTitle(title, note: string) {.component.} =
  column(gap = 4.px, padBottom = 8.px):
    text title, size = 26, weight = 600, font = displayFont, color = onSurface
    text note, size = 14, font = uiFont, color = onSurfaceVariant

proc StylePage() {.component.} =
  column(gap = 12.px):
    PageTitle("Style", "How the desktop looks.")
    SettingRow("Screen frame", "The screen sits rounded inside a frame", reader(screenFrame), flipper(screenFrame))
    SettingRow("Glass", "See the wallpaper through surfaces", reader(glass), flipper(glass))
    SettingRow("Compact", "Denser rows in the sidebar", reader(compact), flipper(compact))
    SettingRow("Desktop clock", "The time and date on the wallpaper", reader(deskClock), flipper(deskClock))
    SettingRow("Clock in the dock", "Hours over minutes", reader(barClock), flipper(barClock))

proc PanelsPage() {.component.} =
  column(gap = 12.px):
    PageTitle("Panels", "What sits around your windows.")
    SettingRow("Sidebar open", "Tabs, pins and folders; folded, a slim bar", reader(showSidebar), flipper(showSidebar))
    SettingRow("Dock", "Spaces, the agent, the time and the controls", reader(showBar), flipper(showBar))
    SettingRow("Pinned tiles", "Your essentials at the top of the sidebar", reader(showPins), flipper(showPins))
    Section("Windows")
    column(gap = 8.px, pad = 16.px, radius = 16, fill = container):
      text "Title bars", size = 14, weight = 500, font = uiFont, color = onSurface, padLeft = 4.px
      row(gap = 4.px, pad = 4.px, radius = 16, fill = containerHigh):
        Segment("On hover", titleOnHover)
        Segment("Always", titleAlways)
        Segment("Never", titleNever)
    SettingRow("Tile this space", "Windows share the space instead of floating", tiled, toggleTiling)

proc NetworkPage() {.component.} =
  column(gap = 12.px):
    PageTitle("Network", "What this computer is connected to.")
    if sysNet.get != netUnknown:
      row(gap = 12.px):
        NetTile()
    else:
      text "This computer does not say how it is connected.", size = 14, font = uiFont, color = onSurfaceVariant
    row(height = 44.px, padX = 16.px, radius = pill(44), alignItems = center, gap = 12.px, fill = secondaryContainer):
      icon "sliders", size = 16, color = onSecondaryContainer
      text "Open the system's network settings", size = 14, weight = 600, font = uiFont, color = onSecondaryContainer
      onClick: discard openUrl(when defined(linux): "settings://network" else: "ms-settings:network")

proc AudioPage() {.component.} =
  column(gap = 12.px):
    PageTitle("Audio", "The sound coming out of this computer.")
    if sysVolume.get >= 0:
      VolumeSlider()
    else:
      text "This computer does not share its volume yet.", size = 14, font = uiFont, color = onSurfaceVariant

proc AppsPage() {.component.} =
  column(gap = 12.px):
    PageTitle("Apps", "Everything here runs in its own sandbox.")
    for a in catalog:
      let address = "y:" & a.id
      row(height = 64.px, padX = 16.px, gap = 16.px, radius = 16, alignItems = center, fill = container):
        Tonal(a.icon, a.tint, 40)
        column(grow = 1, gap = 4.px):
          text a.name, size = 14, weight = 600, font = uiFont, color = onSurface
          text address, size = 12, font = monoFont, color = onSurfaceVariant
        row(height = 32.px, padX = 16.px, radius = 16, alignItems = center, fill = primary):
          text "Open", size = 12, weight = 600, font = uiFont, color = onPrimary
          onClick: (settingsOpen.set(false); openAddress(address))
    row(height = 44.px, padX = 16.px, radius = pill(44), alignItems = center, gap = 12.px, fill = secondaryContainer):
      icon "grid", size = 16, color = onSecondaryContainer
      text "Open the Library", size = 14, weight = 600, font = uiFont, color = onSecondaryContainer
      onClick: (settingsOpen.set(false); openAddress(libraryAddress))

proc AgentPage() {.component.} =
  column(gap = 12.px):
    PageTitle("Agent", "The assistant built into the desktop.")
    InfoRow("Model", proc (): string = (case aiReady()
                                        of 1: "Claude"
                                        of 2: "A local model server"
                                        else: "None set up"))
    text "Set ANTHROPIC_API_KEY for Claude, or YANTRA_AI_URL for a local OpenAI-compatible server " &
         "(llama.cpp, Ollama), then start Yantra again. The key is read by Yantra, never by an app.",
         size = 14, font = uiFont, color = onSurfaceVariant, padX = 8.px

proc AboutPage() {.component.} =
  column(gap = 12.px):
    row(gap = 16.px, alignItems = center, padBottom = 8.px):
      row(width = 72.px, height = 72.px, radius = 16, alignItems = center, justify = center,
          fill = linear(primaryContainer, 0x2A2A60, 135), shadow = shadow(y = 4, blur = 18, color = rgba(primary, 0.35))):
        icon "yantra", size = 46, color = primary
      column(gap = 4.px):
        text "Yantra", size = 26, weight = 600, font = displayFont, color = onSurface
        text "Apps are addresses. Everything runs sandboxed.", size = 14, font = uiFont, color = onSurfaceVariant
    InfoRow("User", proc (): string = whoUser.get)
    InfoRow("Computer", proc (): string = whoHost.get)
    InfoRow("System", proc (): string = whoOs.get)
    InfoRow("Running for", proc (): string = uptimeText())

proc SettingsPanel() {.component.} =
  ## Caelestia's Nexus, as a window over the desktop: the navigation pane and the page.
  readResources()
  row @settings(absolute = true, top = 0, left = 0, right = 0, bottom = 0, z = 15, justify = 1, alignItems = 1,
                fill = rgba(0x000000, 0.25), enter = fade(ms = effectMs), exit = fade(ms = 140)):
    row(grow = 1, maxWidth = 880.px, maxHeight = 600.px, marginX = 24.px, marginY = 24.px, radius = 16,
        alignItems = stretch,
        fill = surf(m3surface), border = 1,
        borderColor = rgba(outlineVariant, 0.6), shadow = shadow(y = 16, blur = 48, color = rgba(0x000000, 0.5)),
        enter = pop(scale = 0.96, ms = moveMs)):
      column(width = 240.px, pad = 16.px, gap = 16.px):
        row(height = 52.px, radius = pill(52), padLeft = 16.px, padRight = 16.px, gap = 12.px, alignItems = center,
            fill = containerLowest, border = 1, borderColor = outlineVariant):
          icon "search", size = 20, color = onSurfaceVariant
          input(nexusSearch, placeholder = "Search settings", grow = 1, size = 14, font = uiFont, color = onSurface,
                fill = clear, border = 0):
            focused:
              borderColor = primary
        column(gap = 4.px, grow = 1, scroll = true):
          for p in shownPages():
            NavItem(p)
      column(grow = 1, marginY = 12.px, marginRight = 12.px, pad = 24.px, radius = 16, fill = containerLow,
             scroll = true):
        row(alignItems = start):
          column(grow = 1):
            case nexusPage.get
            of "panels": PanelsPage()
            of "network": NetworkPage()
            of "audio": AudioPage()
            of "apps": AppsPage()
            of "agent": AgentPage()
            of "about": AboutPage()
            else: StylePage()
          IconBtn("x", never, proc () = settingsOpen.set(false))

setTheme(Theme(name: "Aura", dark: true, bg: m3surface, sidebar: m3surface, surface: container,
               surface2: containerHigh, surface3: containerHighest, line: outlineVariant, text: onSurface,
               muted: onSurfaceVariant, faint: outline, accent: primary, accentText: onPrimary,
               accentSoft: rgba(primary, 0.25), danger: errorRole, success: 0xB5CCBA, radius: 12,
               font: uiFont, mono: monoFont))

needs("ai", "system")                            # the agent; the control centre (sdk/core)

proc framePad(): int = (if screenFrame.get: frameWidth else: 0)

app("Yantra", width = 1280, height = 800, fill = m3surface, frameless = true, fullscreen = true,
    net = registryHost):
  onKey: handleKey(lastKey())
  tickClock()
  tickSystem()
  row(grow = 1, alignItems = stretch, fill = surf(m3surface)):
    if showSidebar.get: WideSidebar() else: SlimSidebar()
    stack @screen(grow = 1, marginY = framePad().px,
                  marginRight = (if showBar.get: 0 else: framePad()).px,
                  radius = (if screenFrame.get: screenRadius else: 0), clip = true):
      panel @wallpaper(absolute = true, top = 0, left = 0, right = 0, bottom = 0, shader = wallpaper)
      if shownOn(workspace.get).len == 0 and not dashOpen.get: HomePage()
      if deskClock.get and shownOn(workspace.get).len > 0: # the clock sits behind open windows
        column @deskClock(absolute = true, left = 44, bottom = 36, gap = 4.px, enter = fade(ms = moveMs)):
          text "{clock}", size = 46, weight = 400, font = displayFont, color = rgba(onSurface, 0.92),
               lineHeight = 1.0
          text "{longDate}", size = 20, weight = 500, font = displayFont, color = rgba(onSurfaceVariant, 0.85),
               padLeft = 8.px
      column(absolute = true, top = 0, left = 0, right = 0, bottom = 0, pad = gapsOut.px):
        stack @area(grow = 1):
          sized aw, ah:
            for w in shownOn(workspace.get).keyed(w.id):
              let id = w.id
              column @tile(absolute = true, left = winRect(id, aw.get, ah.get).x,
                           top = winRect(id, aw.get, ah.get).y, width = winRect(id, aw.get, ah.get).w,
                           height = winRect(id, aw.get, ah.get).h, radius = windowRadius, clip = true,
                           fill = surf(container), border = 1,
                           borderColor = (if focused.get == id: rgba(primary, 0.9) else: rgba(onSurfaceVariant, 0.07)),
                           transition = (if dragId.get == id: 0 else: moveMs).ms,
                           z = (if focused.get == id: 2 else: 1),
                           shadow = (if focused.get == id: shadow(y = 8, blur = 28, color = rgba(0x000000, 0.40))
                                     else: shadow(y = 4, blur = 15, color = rgba(0x000000, 0.25))),
                           enter = pop(scale = 0.92, ms = moveMs),
                           exit = pop(scale = 0.95, ms = effectMs, ease = easeInCubic)):
                if titleMode.get == titleAlways: Caption(w, aw, ah)
                WindowBody(w)
                if titleMode.get == titleOnHover: EdgeCaption(w, aw, ah)
                if focused.get != id:            # an unfocused window takes the first click itself
                  panel(absolute = true, top = 8, left = 0, right = 0, bottom = 0, z = 5, fill = clear):
                    onClick: focused.set(id)
                if not tiled():                  # the resize corner
                  panel @resize(absolute = true, right = 0, bottom = 0, width = 16.px, height = 16.px, z = 6):
                    onPointerDown: dragBegin(id, true, aw.get, ah.get)
                    onPointerMove: dragMove()
                    onPointerUp: dragEnd()
      if agentOpen.get: AgentPanel()
      if settingsOpen.get: SettingsPanel()
      if spotlight.get: Launcher()
      if dashOpen.get: Dashboard()
      if passportOpen.get: PassportPanel()
      if sessionMenu.get: SessionPanel()
      if controlOpen.get: ControlCenter()
    if showBar.get: Dock()
  if locked.get: LockScreen()
