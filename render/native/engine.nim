## The Yantra native engine: node tree -> layout (Yoga) -> pixels (Skia), and
## pointer/keyboard input -> app events. Architecture §5; tasks E4, E5.
##
## No window code lives here: the engine paints into any pixel buffer and takes
## input as plain calls, so it is tested headless and driven by SDL3 in
## yantra_run.nim. Everything is in logical pixels; `scale` maps to device pixels.
##
## Model: the app (wasm) owns the tree through the host; the engine only reads it,
## plus state of its own — hover, press, focus, caret, scroll offsets. Every visual
## decision comes from props (docs/spec/style.md); the engine's own defaults are a
## plain dark look used only where an app sets nothing.
##
## Painting and hit testing walk the tree, so clipping, scroll containers, z order,
## opacity layers and overlays all behave the same for pixels and for pointers.
##
## Motion (docs/spec/style.md §7) runs on the engine's own clock, `now`, set by
## `tick`: transitions follow prop and state changes, nodes play `enter` when they
## appear and `exit` after the app removed them (drawn as a ghost until done), and
## `animate` loops. The app does no work for any of it.
##
## Text editing (T1) is the engine's too: inputs and text areas keep a caret and a
## selection anchor, and handle selection by mouse and keyboard, word and line moves,
## copy/cut/paste, undo/redo and Tab focus order; the app only sees the new value.

import std/[tables, math, unicode, os, strutils, algorithm, sets, parseutils, sha1]
import ../../host/host, ../../host/tree
import ../../protocol/wire
import nimyoga, nimskia
when defined(emscripten):
  import nimwasmtime/web, ../web/standins   # the browser build (render/web)
else:
  import nimwasmtime, nimav, nimcurl, nimfilament, nimsdl3, nimjolt
  import nimspell, nimrtc
  from ../../libs/nimminiaudio/src/nimminiaudio as ma import nil
  from nimminiaudio import startAudioOut, addAudioSource, removeAudioSource, startCapture, readCapture,
    captureLevel, stopCapture, Synth, SynthParam, newSynth, set, render, play, free


# The engine's OWN motion (render/native/motion.nim), pinned with ./ on purpose:
# sdk/ui/motion.nim is a different module that also exports a `Loop`, so a bare
# `import motion` is a name that a search-path change elsewhere in the repo can
# silently redirect. `./` resolves relative to THIS file, so it cannot.
import ./motion

import shapes

type
  Particle = object
    pos, vel: array[3, float32]
    age, life: float32
  Spray = ref object               ## one emitter's live particles
    parts: seq[Particle]
    owed: float32                  ## fractional particles the rate has earned
    lastBurst: string
    lastT: float64
    seed: uint32

type View3D = ref object
  scene: Scene3D
  objs: Table[int32, int]          ## node id -> the scene's object id
  keys: Table[int32, string]       ## node id -> what its object was built from (rebuilt when it changes)
  placed: Table[int32, int]        ## instanced mesh node -> the version of the matrices it placed
  shaderKeys: Table[int32, string] ## mesh node -> the shader its object has (SH1)
  texKeys: Table[int32, string]    ## mesh node -> its maps, tiling and surface as last applied (T3D, M3D)
  uploaded: HashSet[string]        ## pixel textures (layers, buffers) already sent, by key with version
  colorsAt: Table[int32, int]      ## mesh node -> the version of the colours buffer it has
  bounds: Table[int32, (array[3, float32], array[3, float32])]  ## mesh node -> its local box (picking)
  phys: PhysicsWorld               ## its physics (PH1), made when an object first has a body
  bodies: Table[int32, (BodyId, string)]   ## mesh node -> its body and what it was made from
  poses: Table[int32, BodyPose]        ## moving bodies: where physics put them (drawn there)
  propPose: Table[int32, string]   ## the pose props last applied to a body (the app moving it)
  lastStep: float64
  ropes: seq[int]
  clips: Table[int32, (int, float64, int, float64)]   ## model node -> (clip, since, previous clip, its since)
  copiesAt: Table[int32, int]      ## model node -> the version of the placements it has (crowds)
  sprays: Table[int32, Spray]      ## particles node -> its particles (PT1)
  rtKeys: Table[int32, string]     ## camera node drawing into a texture -> its name and pose as applied (RT1)
  showsKey: Table[int32, string]   ## mesh node -> the camera texture it shows (so that camera skips it)
  eye, target: array[3, float32]   ## the camera it rendered with, for picking
  fov: float32
  aspect: float32
  moving: bool                     ## a shader reads the time: keep repainting
  envKey, camKey, postKey: string
  px: seq[uint8]
  startAt: float64

type Model3D = ref object
  scene: Scene3D
  path: string                      ## the model it has loaded ("" none yet)
  loaded: bool
  px: seq[uint8]
  startAt: float64

when not defined(emscripten):
  type SoundSlot = object
    dec: ma.Decoder
    playing: bool
    vol: float32

type
  Leaf = ref object
    ## What a measure callback needs to size a leaf (text, button, input, checkbox).
    text: string
    size: float32
    weight: int
    kind: int32
    st: TextStyle
    rows: int                       ## text areas: the smallest height, in lines

  Box* = object
    x*, y*, w*, h*: float32

  Engine* = ref object
    app*: App                       ## this engine's app, in its own sandbox
    s*: HostState
    width*, height*: float32        ## viewport, logical px
    scale*: float32                 ## device px per logical px
    boxes*: Table[int32, Box]       ## where each node is drawn, in page coordinates (root scroll not applied)
    clips: Table[int32, Box]        ## the visible part of each node's area (ancestor clips applied)
    paintOrder: seq[int32]          ## laid-out nodes in document order (focus order)
    yoga: Table[int32, YogaNode]
    leafOf: Table[int32, Leaf]      ## text-bearing leaves: what their measure callback reads (kept per node)
    yogaHost: Table[int32, int32]   ## node -> the node whose Yoga node holds its own (Groups are see-through)
    root: YogaNode
    yogaFor: HostState              ## the tree the kept Yoga tree mirrors (P1)
    yogaW, yogaH: float32
    yogaAppStyle: bool
    trash: seq[YogaNode]            ## Yoga nodes replaced during this layout, freed at its end
    fullLayouts*, partialLayouts*: int  ## how many layouts rebuilt everything / only what changed
    restyled*: int                  ## Yoga nodes made or restyled by the last layout
    # damage (P1): with `partialPaint` a frame repaints only the part of the window that changed
    partialPaint*: bool             ## the target keeps its pixels between frames (the SDL CPU buffer)
    damage: Box                     ## what to repaint, viewport px (logical)
    hasDamage: bool
    fullDamage: bool                ## repaint everything next frame
    lastDamage*: Box                ## what the last paint redrew, viewport px (the window after a full one)
    animIds: seq[int32]             ## nodes still tweening after the last paint: next frame repaints them
    animFull: bool                  ## something moving that has no one box (enter, loops, ghosts, slides)
    hasBackdrop: bool               ## a backdrop blur reads what is under it: damage can't stay local
    # images (P2): decoded by workers at the drawn size into Skia's side's LRU cache
    asyncImages*: bool              ## decode off this thread (the runner); else on first draw (tests, exports)
    imgWaiting: HashSet[int32]      ## image nodes drawn while their decode was not ready
    imgBlank: HashSet[int32]        ## ...of those, the ones that showed nothing yet: they fade in
    imgFadeAt: Table[int32, float64]
    imgGen: int                     ## `imageGeneration()` when the waiting ones were last looked at
    gifs: Table[int32, Player]      ## GIFs through libav where Skia has no GIF decoder (native)
    # playback (P3)
    liveMedia*: bool                ## decode threads + the audio device (the runner); else the engine clock
    maxDecoders*: int               ## live videos decoding at once (the visible ones first); 0 = 4
    mediaIds: seq[int32]            ## video and audio nodes in the tree, document order
    audioOut: int                   ## 0 not tried, 1 a device is playing, -1 there is none
    # read-only text selection across Text nodes (P4): (node, byte) ends, in document order
    selA*, selZ*: (int32, int)      ## anchor and moving end; node -1 = no selection
    selDragging: bool
    # scroll control (Q1): anchoring, stick-to-bottom, scroll to y / to a row
    scrollCtl: seq[int32]           ## scroll areas with Anchor, StickBottom, ScrollY or ScrollToKey
    scrollSeen: Table[int32, (float32, string)]  ## the ScrollY / ScrollToKey values already applied
    focusSeen: Table[int32, string] ## FocusAt values already applied (Q6)
    focusDue: seq[int32]
    spellCache: Table[int32, (string, seq[(int, int)])]   ## field -> (the text checked, its misspelled words) (Q9)
    replaceSeen: Table[int32, string]
    # a voice call (Q11)
    when not defined(emscripten):
      call: Call
      callEnc, callDec: OpusCodec
    callSlot: int
    callMuted: bool
    callMic: seq[float32]            ## captured samples waiting for a whole 20 ms frame
    # capture (Q2)
    when not defined(emscripten):
      recorder: Recorder
    recPath: string
    recBuf: seq[float32]
    recStart: float64
    recHeld: float64                ## ms recorded before the last pause
    # find in page (Q3)
    findKey: (string, int)          ## the query and tree version the matches are for
    findMatches: seq[(int32, int, int)]  ## (Text node, from byte, to byte), document order
    findShown: int32                ## the FindIndex last scrolled into view (-1)
    # smooth input (Q4)
    smoothScroll*: bool             ## wheel notches glide (the runner); off: they jump (tests)
    lastFrameAt: float64            ## when the last Frame event went out (G-IN)
    kinetic*: bool                  ## precise (touchpad) scrolling coasts on when the fingers lift, where the OS doesn't
    glides: Table[int32, Glide]     ## scroll areas (0 = the window) gliding to a target or coasting
    lastTick: float64
    zooms: Table[int32, Zoom]       ## zoomable images: scale and pan
    panning: int32                  ## the image being dragged (-1)
    panFrom: (float32, float32)
    # heroes (Q5): a named node that went, and one with the same @name that comes with a
    # transition, flies from the old box to the new one
    heroFrom: Table[string, (Box, float64)]
    net: Fetcher                    ## this app's requests in flight (F1); opened on its first fetch
    netOpen: bool
    netReqs: Table[int, (int32, int32)]
    imgRequested: HashSet[string]   ## network image URLs already queued once (C1)
    imgPending: seq[string]         ## network image URLs waiting to start in pumpNet
    imgReqs: Table[int, string]     ## curl id -> network image URL
    sockets: Table[int32, (WebSocket, int32)]  ## the app's open WebSockets and their handlers   ## curl's id -> (the app's id, its handler)
    grids: seq[int32]               ## grid containers, outer first: sized in a second layout pass
    gridAuto: Table[int32, seq[float32]]  ## a grid's `auto` columns: their widest item (first pass)
    laidOutVersion: int
    placeDirty: bool
    contentH*: float32
    scrollY*: float32               ## the window's own scroll
    scrolls*: Table[int32, float32] ## scroll offset of each `scroll = true` node
    scrollMax*: Table[int32, float32]
    scrollSet: Table[int32, float32]   ## the app's last `scrollTo` for each node, applied once when it changes
    atEnd: Table[int32, bool]          ## `stickToEnd` areas that were at their end
    scrollNotes: seq[(int32, float32)] ## offsets moved by placement, told to Scroll handlers after it
    hover*, pressed*, focus*: int32
    hoverChain: seq[int32]          ## every node under the pointer (for hover styles)
    caret*: int                     ## byte offset in the focused input
    anchor*: int                    ## the other end of the selection (== caret: none)
    textScroll*: Table[int32, float32] ## how far an input (x) or text area (y) is scrolled
    undoStack, redoStack: seq[TextEdit]
    typing: bool                    ## the last edit was typing: more typing joins it
    selecting: bool                 ## a mouse drag is extending the selection
    lastClickAt: float64
    lastClickNode: int32
    clicks: int                     ## 1 caret, 2 word, 3 everything
    focusVisible*: bool             ## focus came from the keyboard: draw a focus ring
    preeditText*: string            ## an input method's word in progress (not in the value yet)
    preeditCursor*: int             ## its cursor, in characters (-1: at its end)
    devNote*: string                ## a message over the app (a failed rebuild); "" = none
    reloads*: int                   ## how many times a new build was swapped in
    timers: seq[(float64, int32)]   ## (when, handler): `after` steps waiting on the clock
    players: Table[int32, Player]   ## video nodes: their decoder and when they started
    ovRoots: seq[(int32, YogaNode)] ## open overlays (OV1) in tree order = paint order, each its own Yoga root
    ovCurrent: int32                ## the overlay being painted or hit-tested (0: the window itself)
    ovYogaIds: HashSet[int32]       ## nodes whose Yoga node lives under an overlay root (rebuilt each layout)
    ovDirty: bool                   ## an overlay opened or closed: lay out again (the page's Yoga tree is kept)
    ovClosed: HashSet[int32]        ## dismissed with no onDismiss handler: closed until shown again
    ctxAt: Table[int32, (float32, float32)]  ## open context menus: where the right click was (page coords)
    tipOn, tipShown: bool           ## the pointer rests on a node with a tooltip; shown after a moment
    tipAnchor: int32
    tipSince: float64
    models: Table[int32, Model3D]   ## model nodes: their 3D view (Filament) and pixels
    layerBase: int                  ## this engine's apps' raster layer ids start here (CV2)
    layers: seq[int32]              ## the layers its app made (freed with it)
    layerVer: Table[int32, int]     ## each layer's version: bumped when it changes (3D maps follow)
    synths: Table[int32, (Synth, int)]   ## Synth nodes: their voice and its slot in the device's mix (AU1)
    synthsAt: int                   ## the tree version they were last matched to
    views3d: Table[int32, View3D]   ## Scene3D nodes: their world (Filament) and its objects (S3D)
    when not defined(emscripten):
      sounds: Table[int32, SoundSlot]
    shiftHeld: bool                 ## from the last key: a Shift+click extends the selection
    caretOn*: bool
    dirtyF: bool                    ## something new to show (see `dirty=`)
    appDir*: string                 ## where `appView(source = "name")` finds name.wasm
    children*: Table[int32, Engine] ## AppView node id -> the app running in it
    childSource: Table[int32, string]
    activeChild*: int32             ## the AppView whose app gets the keyboard, or -1
    hoverChild: int32
    pressedChild: int32
    px, py: float32                 ## last pointer position
    draggingNode*: int32
    dragData*: string
    crashed*: string                ## why this app stopped, if it did
    # motion
    now*: float64                   ## the engine clock in ms, set by `tick`
    reducedMotion*: bool            ## every duration is 0 and loops stand still
    motions: Table[int32, Motion]   ## the tweens of nodes that have `transition`
    entered: HashSet[int32]         ## nodes with `enter` already seen
    enterAt: Table[int32, float64]  ## nodes playing `enter`, from when
    loopAt: Table[int32, float64]   ## nodes playing `animate`, from when
    exitWatch: Table[int32, seq[int32]] ## nodes with `exit` -> the containers above them, nearest first
    ghosts: seq[Ghost]              ## removed nodes still playing `exit`
    ghostBoxes: Table[int32, Box]
    ghostClips: Table[int32, Box]
    placedOnce: bool
    moving: bool                    ## a box is still sliding: place again next frame
    animating*: bool                ## something moved in the last frame: paint again
    exporting: bool                 ## drawing for a file: nothing is off screen

  Glide = object
    target: float32                 ## where a notch or a scrollTo is going (NaN: coasting)
    vel: float32                    ## px per ms, for coasting
    lastInput: float64

  Zoom = object
    scale, x, y: float32            ## scale >= 1; the image's shift inside its box (px)

  Motion = ref object
    colors: array[3, ColorTrack]    ## cFill, cInk, cBorder
    nums: array[3, Track]           ## nOpacity, nScale, nLift
    bx, by, bw, bh: Track

  Player = ref object
    ## A video or audio node's playback. Two ways to play (P3): `dec`, frames by the engine
    ## clock on this thread (tests and films: exact and repeatable), or `live` (the runner),
    ## a decode thread whose clock the sound drives, frames pulled in `tick`.
    src: string
    path: string                    ## the file, resolved ("": missing, not allowed)
    dec: Decoder                    ## nil: the file is not there, not a video, or not allowed
    startAt: float64                ## engine ms at media time 0 (-1 until it starts)
    paused: bool
    heldPos: float64                ## media time while paused or closed (s)
    buf: seq[uint32]
    bw, bh: int                     ## decode size (dec) / the frame in `buf` (live)
    vw, vh: int                     ## the video's own size (0: not a video)
    when not defined(emscripten):
      live: MediaPlayer
    slot: int                       ## its source on the audio device (-1: none)
    hasFrame: bool
    duration: float64               ## s (0: unknown)
    pos: float64                    ## media time now (s), as `tick` last saw it
    seekSeen: float32
    seekKnown: bool
    lastFire: float64               ## media time of the last TimeUpdate
    ended, errored, ready: bool
    waveN: int

  TextEdit = object
    id: int32
    value: string
    spans: string                   ## its styled runs then (rich text)
    caret, anchor: int

  Ghost = object
    id, host: int32
    ids: seq[int32]                 ## the node and everything under it
    t0: float64
    spec: Spec

# --- defaults: used only where an app sets nothing ---------------------------------

proc dirty*(e: Engine): bool = e.dirtyF
proc `dirty=`*(e: Engine; v: bool) =
  ## Something changed that has no known place on screen: the next paint redraws everything.
  ## Changes with a known place call `damageBox`/`damageNode` instead.
  e.dirtyF = v
  if v: e.fullDamage = true

const
  ImgFadeMs = 160.0                 ## an image that was loading fades in over this long
  Ink = 0xFFF5F5F7'u32
  Muted = 0xFF8C8C96'u32
  Faint = 0xFF55555E'u32
  Amber = 0xFFFFB23E'u32
  WindowBg = 0xFF0B0B10'u32
  ButtonBg = 0xFF26262E'u32
  InputBg = 0xFF15151B'u32
  Line = 0xFF2C2C35'u32

proc argb(v: int32): uint32 =
  ## Wire colour -> ARGB. 0xRRGGBB (no alpha byte) is opaque; rgba() sets the top byte.
  let u = cast[uint32](v)
  if (u and 0xFF000000'u32) == 0: 0xFF000000'u32 or u else: u

proc shade(c: uint32; f: float32): uint32 =
  ## Lighten (f > 1) or darken (f < 1) a colour, keeping its alpha.
  proc ch(v: uint32): uint32 = uint32(clamp(float32(v) * f + (if f > 1: 10 else: 0), 0, 255))
  (c and 0xFF000000'u32) or (ch((c shr 16) and 0xFF) shl 16) or (ch((c shr 8) and 0xFF) shl 8) or ch(c and 0xFF)

proc withAlpha(c: uint32; a: float32): uint32 =
  (uint32(clamp(float32(c shr 24) * a, 0, 255)) shl 24) or (c and 0x00FFFFFF'u32)

proc node*(e: Engine; id: int32): tree.Node = e.s.nodes[int(id)]
proc has(n: tree.Node; p: int32): bool = n.hasProp(p)
proc num(n: tree.Node; p: int32; d: float32): float32 =
  if not n.hasProp(p): return d
  let v = n.props[p]
  case v.kind
  of vkInt: float32(v.i)
  of vkFloat: v.f
  of vkString: d
proc col(n: tree.Node; p: int32; d: uint32): uint32 =
  if n.hasProp(p) and n.props[p].kind == vkInt: argb(n.iProp(p)) else: d
proc flag(n: tree.Node; p: int32): bool = n.hasProp(p) and n.num(p, 0) != 0

proc visible*(n: tree.Node): bool = not n.hasProp(P_VISIBLE) or n.iProp(P_VISIBLE) != 0
proc isContainer(k: int32): bool = k in [K_WINDOW, K_COLUMN, K_ROW, K_PANEL, K_STACK, K_GROUP, K_SCROLLAREA, K_PAGE, K_GRID,
                                          K_MODAL, K_DRAWER, K_POPOVER, K_MENU, K_CONTEXTMENU]
proc isOverlay(k: int32): bool = k in [K_MODAL, K_DRAWER, K_POPOVER, K_TOOLTIP, K_MENU, K_CONTEXTMENU]
proc notLaid(k: int32): bool = isOverlay(k) or k == K_SYNTH
  ## Not in the page's layout: overlays (their own) and sounds (no box at all).

proc interactive(e: Engine; id: int32): bool =
  let n = e.node(id)
  n.kind in [K_BUTTON, K_CHECKBOX, K_INPUT, K_TEXTAREA] or e.s.handlerFor(id, E_CLICK) >= 0 or
    (n.kind == K_TEXT and e.s.handlerFor(id, E_LINKCLICK) >= 0) or
    (n.kind == K_IMAGE and n.flag(P_ZOOMABLE)) or n.has(P_WINDOWACTION) or
    e.s.handlerFor(id, E_POINTERDOWN) >= 0      # canvases, drag handles (Q6)

proc fontSize(n: tree.Node; k: int32): float32 = n.num(P_FONTSIZE, if k == K_PATH: 24 else: 15)
proc fontWeight(n: tree.Node; k: int32): int = int(n.num(P_FONTWEIGHT, if k == K_BUTTON: 600 else: 400))
proc inlineSizes(spec: string): string =
  ## "w,h,path;…" -> "w,h;…": what text layout needs of a Text's inline objects (Q3).
  for part in spec.split(';'):
    let f = part.split(',')
    if f.len >= 2:
      if result.len > 0: result.add ';'
      result.add f[0].strip & "," & f[1].strip

proc textStyle(n: tree.Node): TextStyle =
  TextStyle(family: n.sProp(P_FONTFAMILY), italic: n.flag(P_ITALIC),
            lineHeight: n.num(P_LINEHEIGHT, 0), maxLines: int(n.num(P_MAXLINES, 0)),
            spans: n.sProp(P_SPANS), rtl: n.rtl, inline: inlineSizes(n.sProp(P_INLINE)))

# the ink of text-bearing nodes: TextColor; a Text node's legacy Color also counts
proc ink(n: tree.Node; d: uint32): uint32 =
  if n.has(P_TEXTCOLOR): n.col(P_TEXTCOLOR, d)
  elif n.kind == K_TEXT and n.has(P_COLOR): n.col(P_COLOR, d)
  else: d

proc fillProp(n: tree.Node): bool =
  ## Whether the node paints a background. A Text node's Color is its ink (legacy), not a fill.
  n.has(P_COLOR) and not (n.kind == K_TEXT and not n.has(P_TEXTCOLOR))

var memClip: string
var clipboardGet*: proc (): string = proc (): string = memClip
  ## The clipboard. The window runner points these at the system one; tests keep this.
var clipboardSet*: proc (s: string) = proc (s: string) = memClip = s
var windowAction*: proc (op: int) = nil     ## the runner: minimise / maximise / close / fullscreen (Q8)
var openUrlHook*: proc (url: string) = nil  ## the runner: the system opens a URL (Q8)

proc isText(k: int32): bool = k in [K_INPUT, K_TEXTAREA]

proc start*(wasmPath: string; width, height: float32; scale = 1'f32; intro = false): Engine
proc paint*(e: Engine; c: Canvas)
proc textOrigin(e: Engine; id: int32): (float32, float32, float32)
proc playerFor(e: Engine; id: int32): Player
proc fire(e: Engine; id: int32; event: int32)
proc spellClick(e: Engine; x, y: float32): bool
proc caretRect*(e: Engine): (float32, float32, float32, float32)
proc resolveAsset*(e: Engine; p: string): string
proc damageMoved(e: Engine; before, beforeClips: Table[int32, Box]; changed: HashSet[int32])
proc needsPaint*(e: Engine): bool
proc damageNode*(e: Engine; id: int32)
proc selBytes(e: Engine; id: int32): (int, int)
proc textSelection*(e: Engine): string
proc textAtPoint(e: Engine; x, y: float32; nearest: bool): (int32, int)
proc blockKey(e: Engine; code: int32; shift: bool; v: string): bool
proc canvasPointer(e: Engine; id: int32; ev: int32; x, y: float32): bool
proc noteScroll(e: Engine; id: int32; y: float32)
proc linkAt(e: Engine; id: int32; x, y: float32): int
proc zoomAt*(e: Engine; id: int32; factor, x, y: float32)
proc focusOn*(e: Engine; id: int32)
proc replaceSelection(e: Engine; s: string; typing = false)
proc spellOf(e: Engine; id: int32; v: string): seq[(int, int)]

# --- layout -----------------------------------------------------------------------

proc measureLeaf(node: pointer; w: cfloat; wm: cint; h: cfloat; hm: cint): YGSize {.cdecl.} =
  let leaf = cast[Leaf](contextOf(node))
  let maxW = if MeasureMode(wm) == mmUndefined: 0'f32 else: max(float32(w), 1)
  case leaf.kind
  of K_CHECKBOX:
    let (tw, th) = measureText(leaf.text, leaf.size, leaf.weight, if maxW > 0: max(maxW - 28, 1) else: 0, leaf.st)
    YGSize(width: tw + 28, height: max(th, 20))
  of K_INPUT:
    let (_, th) = measureText("Hg", leaf.size, leaf.weight, 0, leaf.st)
    YGSize(width: if MeasureMode(wm) == mmExactly: w else: 160, height: th)
  of K_TEXTAREA:
    # grows with its text; never shorter than `rows` lines
    let width = if MeasureMode(wm) == mmExactly or MeasureMode(wm) == mmAtMost: float32(w) else: 280'f32
    let (_, line) = measureText("Hg", leaf.size, leaf.weight, 0, leaf.st)
    let (_, th) = measureText(leaf.text & "\n", leaf.size, leaf.weight, max(width, 1), leaf.st)
    YGSize(width: width, height: max(th - line, line * float32(max(leaf.rows, 1))))
  else:
    let (tw, th) = measureText(leaf.text, leaf.size, leaf.weight, maxW, leaf.st)
    YGSize(width: ceil(tw), height: ceil(th))

proc styleContainer(y: YogaNode; n: tree.Node) =
  let k = n.kind
  y.setFlexDirection(if k == K_ROW: fdRow else: fdColumn)
  if n.has(P_ALIGNITEMS):
    y.setAlignItems(case int(n.num(P_ALIGNITEMS, 0))
      of 0: yaStart
      of 1: yaCenter
      of 2: yaEnd
      else: yaStretch)
  elif k == K_ROW: y.setAlignItems(yaCenter)
  if n.has(P_JUSTIFY):
    y.setJustifyContent(case int(n.num(P_JUSTIFY, 0))
      of 1: yjCenter
      of 2: yjEnd
      of 3: yjSpaceBetween
      of 4: yjSpaceAround
      of 5: yjSpaceEvenly
      else: yjStart)
  if n.flag(P_WRAP): y.setFlexWrap(ywWrap)
  let gap = n.num(P_SPACING, 0)
  if gap > 0: y.setGap(gutterAll, gap)
  y.setPadding(edgeTop, n.num(P_PAD_TOP, 0))
  y.setPadding(edgeRight, n.num(P_PAD_RIGHT, 0))
  y.setPadding(edgeBottom, n.num(P_PAD_BOTTOM, 0))
  y.setPadding(edgeLeft, n.num(P_PAD_LEFT, 0))
  if n.flag(P_SCROLL):
    y.setOverflow(yoScroll)
    # a scroll area that grows takes the space left, not its content's size: its content
    # scrolls inside it (lazy lists need a real viewport to know what shows)
    if n.has(P_FLEXGROW) and not n.has(P_HEIGHT): y.setFlexBasis(0)
  elif n.flag(P_CLIP): y.setOverflow(yoHidden)

proc styleCommon(y: YogaNode; n: tree.Node; inStack: bool) =
  if n.has(P_WIDTH): y.setWidth(n.num(P_WIDTH, 0))
  if n.has(P_HEIGHT): y.setHeight(n.num(P_HEIGHT, 0))
  if n.has(P_MINWIDTH): y.setMinWidth(n.num(P_MINWIDTH, 0))
  if n.has(P_MINHEIGHT): y.setMinHeight(n.num(P_MINHEIGHT, 0))
  if n.has(P_MAXWIDTH): y.setMaxWidth(n.num(P_MAXWIDTH, 0))
  if n.has(P_MAXHEIGHT): y.setMaxHeight(n.num(P_MAXHEIGHT, 0))
  if n.has(P_FLEXGROW):
    y.setFlexGrow(n.num(P_FLEXGROW, 0))
    y.setFlexShrink(1)
    if n.kind != K_TEXT: y.setMinWidth(n.num(P_MINWIDTH, 0))
  if n.has(P_FLEXSHRINK): y.setFlexShrink(n.num(P_FLEXSHRINK, 1))
  y.setMargin(edgeTop, n.num(P_MARGINTOP, 0))
  y.setMargin(edgeRight, n.num(P_MARGINRIGHT, 0))
  y.setMargin(edgeBottom, n.num(P_MARGINBOTTOM, 0))
  y.setMargin(edgeLeft, n.num(P_MARGINLEFT, 0))
  if n.flag(P_ABSOLUTE) or inStack:
    y.setPositionType(ypAbsolute)
    if n.has(P_INSETTOP): y.setPosition(edgeTop, n.num(P_INSETTOP, 0))
    if n.has(P_INSETRIGHT): y.setPosition(edgeRight, n.num(P_INSETRIGHT, 0))
    if n.has(P_INSETBOTTOM): y.setPosition(edgeBottom, n.num(P_INSETBOTTOM, 0))
    if n.has(P_INSETLEFT): y.setPosition(edgeLeft, n.num(P_INSETLEFT, 0))
    if inStack and not (n.has(P_INSETTOP) or n.has(P_INSETBOTTOM)): y.setPosition(edgeTop, 0)
    if inStack and not (n.has(P_INSETLEFT) or n.has(P_INSETRIGHT)): y.setPosition(edgeLeft, 0)
  if not n.visible: y.setDisplay(ydNone)
  if n.has(P_DIRECTION) and n.num(P_DIRECTION, 0) > 0:
    y.setDirection(if n.num(P_DIRECTION, 0) >= 2: dirRTL else: dirLTR)

proc isLeafKind(k: int32): bool = k in [K_TEXT, K_BUTTON, K_CHECKBOX, K_INPUT, K_TEXTAREA]
proc yogaKids(k: int32): bool =
  ## Whether a node's children are laid out inside it (leaves and media ignore theirs).
  k notin [K_TEXT, K_BUTTON, K_CHECKBOX, K_INPUT, K_TEXTAREA, K_IMAGE, K_PATH, K_SPACER, K_APPVIEW, K_MODEL, K_VIDEO,
           K_SCENE3D]

proc leafFor(e: Engine; id: int32; n: tree.Node): bool =
  ## Brings node `id`'s measure data up to date (one Leaf per node, so its Yoga node keeps
  ## the same context). True if anything that changes its size changed.
  let shown = if n.kind != K_TEXTAREA: n.sProp(P_TEXT)
              elif n.sProp(P_VALUE).len > 0: n.sProp(P_VALUE) else: n.sProp(P_PLACEHOLDER)
  let nl = Leaf(text: shown, size: n.fontSize(n.kind), weight: n.fontWeight(n.kind),
                kind: n.kind, st: n.textStyle, rows: int(n.num(P_ROWS, 3)))
  var l = e.leafOf.getOrDefault(id)
  if l == nil:
    e.leafOf[id] = nl
    return true
  result = l.text != nl.text or l.size != nl.size or l.weight != nl.weight or l.rows != nl.rows or
           l.st.family != nl.st.family or l.st.italic != nl.st.italic or l.st.lineHeight != nl.st.lineHeight or
           l.st.maxLines != nl.st.maxLines or l.st.spans != nl.st.spans
  l.text = nl.text; l.size = nl.size; l.weight = nl.weight; l.st = nl.st; l.rows = nl.rows

proc styleYoga(e: Engine; y: YogaNode; id: int32; n: tree.Node; inStack: bool) =
  ## Every style Yoga needs for host node `id`, not its children. Called on a fresh node, so
  ## a prop that is gone leaves Yoga's default (restyling copies this whole style over).
  styleCommon(y, n, inStack)
  case n.kind
  of K_TEXT, K_BUTTON, K_CHECKBOX, K_INPUT, K_TEXTAREA:
    if n.kind == K_BUTTON:
      y.setPadding(edgeTop, n.num(P_PAD_TOP, 9)); y.setPadding(edgeBottom, n.num(P_PAD_BOTTOM, 9))
      y.setPadding(edgeLeft, n.num(P_PAD_LEFT, 14)); y.setPadding(edgeRight, n.num(P_PAD_RIGHT, 14))
    elif n.kind in [K_INPUT, K_TEXTAREA]:
      y.setPadding(edgeTop, n.num(P_PAD_TOP, 11)); y.setPadding(edgeBottom, n.num(P_PAD_BOTTOM, 11))
      y.setPadding(edgeLeft, n.num(P_PAD_LEFT, 12)); y.setPadding(edgeRight, n.num(P_PAD_RIGHT, 12))
      if not n.has(P_MINWIDTH): y.setMinWidth(80)
    if n.kind == K_TEXT and not n.has(P_FLEXSHRINK):     # text may shrink (and wrap) to fit its row,
      var p = n.parent                                    # but in a scroll area it keeps its height
      while p > 0 and e.node(p).kind == K_GROUP: p = e.node(p).parent
      if not e.node(max(p, 0)).flag(P_SCROLL): y.setFlexShrink(1)
  of K_IMAGE:
    if not n.has(P_WIDTH) or not n.has(P_HEIGHT):
      let rel = if n.has(P_SOURCE): n.sProp(P_SOURCE) elif n.has(P_TEXT): n.sProp(P_TEXT) else: ""
      let fullPath = e.resolveAsset(rel)
      var (iw, ih) = if fullPath.len > 0: imageInfo(fullPath) else: (0, 0)
      when not defined(emscripten):
        if iw == 0 and fullPath.len > 0 and fullPath.toLowerAscii.endsWith(".gif"):
          let info = probe(fullPath)     # libav reads GIFs (MSYS2's Skia has no GIF decoder)
          iw = info.width
          ih = info.height
      if not n.has(P_WIDTH): y.setWidth(if iw > 0: float32(iw) else: 100'f32)
      if not n.has(P_HEIGHT): y.setHeight(if ih > 0: float32(ih) else: 100'f32)
    y.setFlexShrink(0)
  of K_PATH:
    let s = n.fontSize(K_PATH)
    if not n.has(P_WIDTH): y.setWidth(s)
    if not n.has(P_HEIGHT): y.setHeight(s)
    y.setFlexShrink(0)
  of K_SPACER:
    if not n.has(P_HEIGHT) and not n.has(P_WIDTH): y.setFlexGrow(1)
  of K_APPVIEW:
    y.setMinHeight(0)
    y.setFlexShrink(1)
  of K_MODEL, K_SCENE3D:              # a 3D view: 320 x 240 unless the app sets a size or grow
    if not n.has(P_WIDTH) and not (n.kind == K_SCENE3D and n.has(P_FLEXGROW)): y.setWidth(320)
    if not n.has(P_HEIGHT) and not (n.kind == K_SCENE3D and n.has(P_FLEXGROW)): y.setHeight(240)
    y.setFlexShrink(0)
    if n.kind == K_SCENE3D and n.has(P_FLEXGROW) and not (n.has(P_WIDTH) and n.has(P_HEIGHT)):
      y.setAlignSelf(yaStretch)          # a growing view fills its row or column both ways
  of K_VIDEO:                         # its own size unless the app sets one
    let p = e.playerFor(id)
    let (vw, vh) = if p.vw > 0: (float32(p.vw), float32(p.vh)) else: (160'f32, 90'f32)
    if not n.has(P_WIDTH) and not n.has(P_HEIGHT):
      y.setWidth(vw); y.setHeight(vh)
    elif not n.has(P_HEIGHT): y.setHeight(n.num(P_WIDTH, vw) * vh / max(vw, 1))
    elif not n.has(P_WIDTH): y.setWidth(n.num(P_HEIGHT, vh) * vw / max(vh, 1))
    y.setFlexShrink(0)
  of K_GRID:
    # a grid is a wrapping row whose items get their columns' widths (fitGrids): first they
    # lay out at their own size, so `auto` columns can take their widest item
    styleContainer(y, n)
    y.setFlexDirection(fdRow)
    y.setFlexWrap(ywWrap)
    if not n.has(P_ALIGNITEMS): y.setAlignItems(yaStretch)
    let gap = if n.has(P_GRIDGAP): n.num(P_GRIDGAP, 0) else: n.num(P_SPACING, 0)
    y.setGap(gutterAll, gap)
  else:
    styleContainer(y, n)

proc inStackOf(e: Engine; host: int32): bool = host > 0 and e.node(host).kind == K_STACK

proc buildYoga(e: Engine; parentY: YogaNode; id: int32; host: int32) =
  ## Makes fresh Yoga node(s) for host node `id` and everything under it, appended to
  ## `parentY` (nil: left unattached). A Group adds its children directly: it is invisible
  ## to layout. A node that had a Yoga node gets a new one; the old one goes to the trash.
  let n = e.node(id)
  if not n.alive or notLaid(n.kind): return        # overlays are laid out on their own (OV1)
  if n.kind == K_GROUP:
    for c in n.children: e.buildYoga(parentY, c, host)
    return
  let y = newNode()
  let old = e.yoga.getOrDefault(id)
  if old != nil: e.trash.add old
  e.yoga[id] = y
  e.yogaHost[id] = host
  inc e.restyled
  e.styleYoga(y, id, n, e.inStackOf(host))
  if isLeafKind(n.kind):
    discard e.leafFor(id, n)
    y.setContext(cast[pointer](e.leafOf[id]))
    y.setMeasureFunc(measureLeaf)
  if n.kind == K_GRID: e.gridAuto.del id       # its items are new: measure `auto` columns again
  if parentY != nil: parentY.insertChild(y, parentY.childCount)
  if yogaKids(n.kind):
    for c in n.children: e.buildYoga(y, c, id)

proc restyleYoga(e: Engine; id: int32) =
  ## Node `id`'s props changed: give its Yoga node the new style in place, so its children
  ## and every cached measurement under it stay (text is measured again only if it changed).
  let n = e.node(id)
  let y = e.yoga[id]
  let tmp = newNode()
  e.styleYoga(tmp, id, n, e.inStackOf(e.yogaHost.getOrDefault(id, 0)))
  y.copyStyle(tmp)
  tmp.free()
  if isLeafKind(n.kind) and e.leafFor(id, n): y.markDirty()
  inc e.restyled

proc hostOf(e: Engine; id: int32): int32 =
  ## The nearest ancestor that has a Yoga node (-1: not in the tree).
  result = e.node(id).parent
  while result > 0 and e.node(result).kind == K_GROUP: result = e.node(result).parent

proc flatKids(e: Engine; id: int32; outp: var seq[int32]) =
  for c in e.node(id).children:
    let cn = e.node(c)
    if not cn.alive or notLaid(cn.kind): continue
    if cn.kind == K_GROUP: e.flatKids(c, outp) else: outp.add c

proc relink(e: Engine; h: int32) =
  ## Makes host `h`'s Yoga children match its tree children. Kept nodes keep their Yoga
  ## node (and layout cache); only the run between the unchanged start and end is re-linked.
  let hy = e.yoga[h]
  var kids: seq[int32]
  e.flatKids(h, kids)
  var want: seq[YogaNode]
  for c in kids:
    let y = e.yoga.getOrDefault(c)
    if y == nil:
      e.buildYoga(nil, c, h)            # new here: build it (and all under it) fresh
    elif e.yogaHost.getOrDefault(c, -2) != h:
      e.yogaHost[c] = h                 # moved here: its style may change (a Stack places it)
      e.restyleYoga(c)
    want.add e.yoga[c]
  var cur: seq[pointer]
  for i in 0 ..< hy.childCount: cur.add hy.childAt(i)
  var a = 0
  while a < cur.len and a < want.len and cur[a] == want[a].rawOf: inc a
  var z = 0
  while z < cur.len - a and z < want.len - a and cur[cur.len - 1 - z] == want[want.len - 1 - z].rawOf: inc z
  for i in a ..< cur.len - z: hy.removeChildAt(cur[i])
  for i in a ..< want.len - z:
    want[i].detach()
    hy.insertChild(want[i], i)

proc outerGrid(e: Engine; id: int32): int32 =
  ## The outermost grid at or above `id` (-1: none). Grid items carry widths fitGrids gave
  ## them, so a change inside a grid rebuilds that grid.
  result = -1
  var p = id
  while p > 0:
    if e.node(p).kind == K_GRID: result = p
    p = e.node(p).parent

proc updateYoga(e: Engine): bool =
  ## Brings the kept Yoga tree up to date with what the app changed since the last layout;
  ## false if it can't (the window's own style changed): then everything is rebuilt.
  if 0 in e.s.touched: return false
  for id in e.s.touched:                  # a direction change reaches every text below it: rebuild (rare)
    if e.s.valid(id) and e.node(id).has(P_DIRECTION): return false
  var grids, hosts: HashSet[int32]
  var restyle: seq[int32]
  for id in e.s.reshaped:
    if not e.s.valid(id) or id in e.ovYogaIds: continue   # gone (its parent is in here too), or an overlay's
    let g = e.outerGrid(id)
    if g >= 0: grids.incl g
    else:
      let h = if e.node(id).kind == K_GROUP: e.hostOf(id) else: id
      if h >= 0 and h in e.yoga and yogaKids(e.node(h).kind): hosts.incl h   # a leaf ignores children
  for id in e.s.touched:
    if not e.s.valid(id) or e.node(id).kind == K_GROUP or id notin e.yoga or id in e.ovYogaIds: continue
    let g = e.outerGrid(id)
    if g >= 0: grids.incl g else: restyle.add id
  for g in grids:
    let h = e.hostOf(g)
    if h < 0 or h notin e.yoga: continue
    e.buildYoga(nil, g, h)
    hosts.incl h
  for h in hosts: e.relink(h)
  for id in restyle:
    if e.s.valid(id) and id in e.yoga: e.restyleYoga(id)
  true

proc sweepYoga(e: Engine) =
  ## Lists laid-out nodes in document order (focus order; grids outer first) and frees the
  ## Yoga nodes of nodes no longer in the tree, and every node replaced this layout.
  e.paintOrder.setLen(0)
  e.grids.setLen(0)
  var seen = initHashSet[int32]()
  seen.incl 0
  proc walk(e: Engine; id: int32; seen: var HashSet[int32]) =
    let parentRtl = e.node(id).rtl
    for c in e.node(id).children:
      let cn = e.node(c)
      if not cn.alive or notLaid(cn.kind): continue        # overlays: buildOverlays
      cn.rtl = if cn.num(P_DIRECTION, 0) > 0: cn.num(P_DIRECTION, 0) >= 2 else: parentRtl
      if cn.kind == K_GROUP:
        e.walk(c, seen)
        continue
      if c notin e.yoga: continue
      seen.incl c
      e.paintOrder.add c
      if cn.has(P_BACKDROPBLUR): e.hasBackdrop = true
      if cn.kind in [K_VIDEO, K_AUDIO]: e.mediaIds.add c
      if cn.has(P_FOCUSAT) and cn.sProp(P_FOCUSAT) != e.focusSeen.getOrDefault(c): e.focusDue.add c
      if cn.has(P_REPLACE) and cn.sProp(P_REPLACE) != e.replaceSeen.getOrDefault(c): e.focusDue.add -c - 1
      if cn.flag(P_SCROLL) and (cn.has(P_ANCHOR) or cn.has(P_STICKBOTTOM) or cn.has(P_SCROLLY) or cn.has(P_SCROLLTOKEY)):
        e.scrollCtl.add c
      if cn.kind == K_GRID: e.grids.add c
      if yogaKids(cn.kind): e.walk(c, seen)
  e.hasBackdrop = false
  e.mediaIds.setLen(0)
  e.scrollCtl.setLen(0)
  e.node(0).rtl = e.node(0).num(P_DIRECTION, 0) >= 2
  e.walk(0, seen)
  var gone: seq[int32]
  for id in e.yoga.keys:
    if id notin seen and id notin e.ovYogaIds: gone.add id
  for id in gone:
    e.trash.add e.yoga[id]
    e.yoga.del id
    e.yogaHost.del id
    e.leafOf.del id
    e.gridAuto.del id
  for y in e.trash: y.free()              # one at a time: each leaves its owner, orphans its children
  e.trash.setLen(0)

proc freeYoga(e: Engine) =
  for y in e.trash: y.free()
  e.trash.setLen(0)
  if e.root != nil: e.root.free(recursive = true)
  e.root = nil
  for (_, y) in e.ovRoots: y.free(recursive = true)
  e.ovRoots.setLen(0)
  e.ovYogaIds.clear()
  e.yoga.clear()
  e.yogaHost.clear()
  e.leafOf.clear()
  e.paintOrder.setLen(0)
  e.grids.setLen(0)
  e.gridAuto.clear()

# --- grid layout (L1) ----------------------------------------------------------------

type GridTrack* = object
  kind*: char                         ## 'p' px, 'f' fr share, 'a' auto (its widest item)
  v*: float32

proc number(s: string; v: var float): bool =
  ## `s` is a whole number like "12" or "1.5" (nothing else in it).
  s.len > 0 and parseutils.parseFloat(s, v) == s.len

proc parseTracks*(spec: string): seq[GridTrack] =
  ## `"200 1fr 2fr auto"`, `"repeat(3, 1fr)"`; a bare number is px ("200px" too). Words
  ## that are none of these are left out.
  var words: seq[string]
  var s = spec.strip
  while s.len > 0:
    if s.startsWith("repeat("):
      let close = s.find(')')
      if close < 0: break
      let parts = s[7 ..< close].split(',', 1)
      var n = 0.0
      if parts.len == 2 and number(parts[0].strip, n):
        for _ in 1 .. clamp(int(n), 0, 64): words.add strutils.splitWhitespace(parts[1])
      s = s[close + 1 .. ^1].strip
    else:
      let sp = s.find(' ')
      words.add(if sp < 0: s else: s[0 ..< sp])
      s = if sp < 0: "" else: s[sp + 1 .. ^1].strip
  for w in words:
    let t = w.toLowerAscii
    var v = 0.0
    if t == "auto": result.add GridTrack(kind: 'a')
    elif t.endsWith("fr") and number(t[0 ..< ^2], v): result.add GridTrack(kind: 'f', v: max(0'f32, float32(v)))
    elif t.endsWith("px") and number(t[0 ..< ^2], v): result.add GridTrack(kind: 'p', v: max(0'f32, float32(v)))
    elif number(t, v): result.add GridTrack(kind: 'p', v: max(0'f32, float32(v)))
  if result.len == 0: result.add GridTrack(kind: 'f', v: 1)

proc trackWidths*(tracks: seq[GridTrack]; auto: seq[float32]; width, gap: float32): seq[float32] =
  ## Column widths for a grid `width` wide: px first, then `auto` columns, then what is
  ## left shared by `fr` (never below 0).
  var used = gap * float32(max(tracks.len - 1, 0))
  var fr = 0'f32
  for i, t in tracks:
    case t.kind
    of 'p': used += t.v
    of 'a': used += (if i < auto.len: auto[i] else: 0)
    else: fr += t.v
  let per = if fr > 0: max(0'f32, width - used) / fr else: 0
  for i, t in tracks:
    result.add(case t.kind
      of 'p': t.v
      of 'a': (if i < auto.len: auto[i] else: 0)
      else: t.v * per)

proc gridItems(e: Engine; id: int32; outp: var seq[int32]) =
  ## The grid's items in order (Groups are see-through; absolute children are not items).
  for c in e.node(id).children:
    let n = e.node(c)
    if not n.alive or not n.visible: continue
    if n.kind == K_GROUP: e.gridItems(c, outp)
    elif c in e.yoga and not n.flag(P_ABSOLUTE): outp.add c

proc fitGrids(e: Engine): bool =
  ## Gives every grid item its columns' width; true if any width changed (lay out again).
  for g in e.grids:
    let n = e.node(g)
    let tracks = parseTracks(n.sProp(P_GRIDCOLS))
    let gap = if n.has(P_GRIDGAP): n.num(P_GRIDGAP, 0) else: n.num(P_SPACING, 0)
    let inner = e.yoga[g].layout().width - n.num(P_PAD_LEFT, 0) - n.num(P_PAD_RIGHT, 0)
    var items: seq[int32]
    e.gridItems(g, items)
    # where each item goes: in order, row after row; one too wide for what is left of a row starts the next
    var at: seq[(int, int)]
    var col = 0
    for it in items:
      let span = clamp(int(e.node(it).num(P_SPAN, 1)), 1, tracks.len)
      if col + span > tracks.len: col = 0
      at.add (col, span)
      col = (col + span) mod tracks.len
    if g notin e.gridAuto:            # first pass: items are at their own size
      var auto = newSeq[float32](tracks.len)
      for i, it in items:
        let (c, span) = at[i]
        if span == 1 and tracks[c].kind == 'a':
          let cn = e.node(it)
          auto[c] = max(auto[c], e.yoga[it].layout().width + cn.num(P_MARGINLEFT, 0) + cn.num(P_MARGINRIGHT, 0) + 0.02)
      e.gridAuto[g] = auto
    let widths = trackWidths(tracks, e.gridAuto[g], inner, gap)
    for i, it in items:
      let (c, span) = at[i]
      var cell = gap * float32(span - 1)
      for k in c ..< c + span: cell += widths[k]
      let cn = e.node(it)
      let ml = cn.num(P_MARGINLEFT, 0)
      var mr = cn.num(P_MARGINRIGHT, 0)
      var w = max(0'f32, cell - ml - mr - 0.01)  # a hair under, so rounding never wraps a full row early
      if c + span < tracks.len and i + 1 < at.len and at[i + 1][0] == 0:
        for k in c + span ..< tracks.len: mr += gap + widths[k]   # the row ends early: fill the rest of it
      if cn.has(P_WIDTH):             # a fixed-width item keeps its width and still takes its cell
        mr += w - cn.num(P_WIDTH, 0)
        w = cn.num(P_WIDTH, 0)
      let y = e.yoga[it]
      if abs(y.layout().width - w) > 0.05: result = true
      y.setWidth(w)
      y.setFlexShrink(0)
      y.setMargin(edgeRight, mr)

# --- motion helpers ------------------------------------------------------------------

proc transMs(e: Engine; n: tree.Node): float64 =
  if e.reducedMotion or not n.has(P_TRANS_DURATION): 0.0 else: float64(max(0'f32, n.num(P_TRANS_DURATION, 0)))

proc transEase(n: tree.Node): int32 = int32(n.num(P_TRANS_EASING, 5))    # 5 = OutCubic

proc motionOf(e: Engine; id: int32): Motion =
  result = e.motions.getOrDefault(id)
  if result == nil:
    result = Motion()
    e.motions[id] = result

const
  cFill = 0
  cInk = 1
  cBorder = 2
  nOpacity = 0
  nScale = 1
  nLift = 2

proc eased(e: Engine; id: int32; n: tree.Node; slot: int; target: uint32): uint32 =
  ## `target` as this node shows it now: itself, or on its way there if the node has `transition`.
  let ms = e.transMs(n)
  if ms <= 0: return target
  let m = e.motionOf(id)
  result = m.colors[slot].follow(target, e.now, ms, n.transEase)
  if m.colors[slot].running(e.now):
    e.animating = true
    e.animIds.add id

proc eased(e: Engine; id: int32; n: tree.Node; slot: int; target: float32): float32 =
  let ms = e.transMs(n)
  if ms <= 0: return target
  let m = e.motionOf(id)
  result = m.nums[slot].follow(target, e.now, ms, n.transEase)
  if m.nums[slot].running(e.now):
    e.animating = true
    e.animIds.add id

# --- media (U8) ------------------------------------------------------------------------

proc validAssetPath*(p: string): bool =
  ## A file an app may name: inside its own folder, so no drive, no leading slash, no
  ## backslash and no `..` — the same rule as `appView` names, with sub-folders allowed.
  p.len > 0 and p.len <= 200 and p[0] != '/' and ':' notin p and '\\' notin p and ".." notin p and
    p.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.', '/'})

proc rawPos(e: Engine; p: Player): float64 =
  if p.startAt < 0 or p.paused or p.ended: p.heldPos else: (e.now - p.startAt) / 1000

proc isLive(p: Player): bool =
  when defined(emscripten): false
  else: p.live != nil

proc mediaPos(e: Engine; p: Player; n: tree.Node): float64 =
  ## Where a player on the engine clock is (s): looped, or held at the end.
  result = e.rawPos(p)
  if p.duration > 0:
    if n.flag(P_LOOP): result = result mod p.duration
    else: result = min(result, p.duration)

proc closeLive(e: Engine; p: Player) =
  ## Stops a live player's decode thread (off the audio device first), keeping its place.
  when not defined(emscripten):
    if p.live == nil: return
    if p.slot >= 0: removeAudioSource(p.slot)
    p.slot = -1
    p.live.close()
    p.live = nil
    p.hasFrame = false

proc closePlayer(e: Engine; p: Player) =
  e.closeLive(p)
  if p.dec != nil: p.dec.close()
  p.dec = nil

proc playerFor(e: Engine; id: int32): Player =
  ## The media node's player, made on first use (and again when `source` changes). Its
  ## path is "" for a file that is missing or not allowed; then it plays nothing.
  let n = e.node(id)
  let src = n.sProp(P_SOURCE)
  result = e.players.getOrDefault(id)
  if result != nil and result.src == src: return
  if result != nil: e.closePlayer(result)
  result = Player(src: src, startAt: -1, slot: -1, lastFire: -1)
  let streamed = src.startsWith("https://") or src.startsWith("http://")
  let path = if streamed: "" else: e.resolveAsset(src)
  if streamed and e.liveMedia and not e.exporting and netAllowed(e.node(0).sProp(P_NET), src):
    result.path = src                                # HLS / DASH / a file over http: libav streams it (Q10)
    when not defined(emscripten):
      if n.kind == K_VIDEO:
        result.vw = 1280                             # its real size comes with its first frame
        result.vh = 720
  elif path.len > 0 and fileExists(path): result.path = path
  elif src.startsWith("camera:") and n.kind == K_VIDEO and e.app != nil and e.app.hasCapability("camera") and
       e.liveMedia and not e.exporting:
    result.path = src                                # libav opens the device (Q2)
    result.vw = 640
    result.vh = 480
  if result.path.len > 0 and n.kind == K_VIDEO:
    if e.liveMedia and not e.exporting:
      when not defined(emscripten):
        let info = probe(result.path)       # its size only: the decoder opens when it shows
        result.vw = info.width
        result.vh = info.height
        result.duration = max(0.0, info.seconds)
    else:
      result.dec = openDecoder(result.path)
      if result.dec != nil:
        result.vw = result.dec.width
        result.vh = result.dec.height
        result.duration = result.dec.seconds
        let scale = min(1.0, 1920 / float(max(result.dec.width, 1)))   # decode no wider than 1080p
        result.bw = max(2, int(float(result.dec.width) * scale))
        result.bh = max(2, int(float(result.dec.height) * scale))
        result.buf = newSeq[uint32](result.bw * result.bh)
  elif result.path.len > 0:
    when not defined(emscripten):
      result.duration = max(0.0, mediaSeconds(result.path))
  e.players[id] = result

proc videoCount*(e: Engine): int =
  ## Video nodes with an open decoder (for tests: a refused file never opens one).
  for _, p in e.players:
    if p.dec != nil: inc result
    else:
      when not defined(emscripten):
        if p.live != nil: inc result

proc intersect(a, b: Box): Box =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  Box(x: x, y: y, w: max(0, min(a.x + a.w, b.x + b.w) - x), h: max(0, min(a.y + a.h, b.y + b.h) - y))

proc placeAll(e: Engine; parentId: int32; ox, oy: float32; clip: Box; host: int32) =
  ## Absolute boxes and visible areas. Yoga positions are relative to the Yoga parent,
  ## the nearest non-Group ancestor (`host`), so Groups pass their origin straight
  ## through; a scrolling parent shifts its children by its offset and clips them.
  ## A node with `transition` slides and resizes toward its new box, relative to
  ## its parent, and its children ride along.
  let n = e.node(parentId)
  for c in n.children:
    let cn = e.node(c)
    if not cn.alive: continue
    var chain: seq[int32]
    var p = cn.parent
    while p >= 0:
      if e.node(p).kind != K_GROUP: chain.add p
      p = e.node(p).parent
    e.exitWatch[c] = chain
    if cn.has(P_ENTER) and c notin e.entered:
      e.entered.incl c
      if e.placedOnce and not e.reducedMotion: e.enterAt[c] = e.now
    if cn.kind == K_GROUP:
      e.boxes[c] = Box(x: ox, y: oy, w: 0, h: 0)
      e.clips[c] = clip
      e.placeAll(c, ox, oy, clip, host)
      continue
    if c notin e.yoga: continue
    let l = e.yoga[c].layout()
    var b = Box(x: ox + l.left, y: oy + l.top, w: l.width, h: l.height)
    let ms = e.transMs(cn)
    if ms > 0:
      let m = e.motionOf(c)
      let ez = cn.transEase
      if not m.bx.seen and cn.has(P_NAME):          # a hero: starts where its namesake was
        let name = cn.sProp(P_NAME)
        let (hb, at) = e.heroFrom.getOrDefault(name, (Box(w: -1), 0.0))
        if hb.w >= 0 and e.now - at < 1000:
          m.bx.startFrom(hb.x - ox, e.now)
          m.by.startFrom(hb.y - oy, e.now)
          m.bw.startFrom(hb.w, e.now)
          m.bh.startFrom(hb.h, e.now)
          e.heroFrom.del name
      b = Box(x: ox + m.bx.follow(l.left, e.now, ms, ez), y: oy + m.by.follow(l.top, e.now, ms, ez),
              w: m.bw.follow(l.width, e.now, ms, ez), h: m.bh.follow(l.height, e.now, ms, ez))
      if m.bx.running(e.now) or m.by.running(e.now) or m.bw.running(e.now) or m.bh.running(e.now):
        e.moving = true
    if cn.has(P_STICKY) or cn.has(P_STICKYLEFT):
      # sticky (P6): held at the view's edge while its container scrolls past, never out of that container
      let pb = e.boxes.getOrDefault(host, b)
      if cn.has(P_STICKY):
        let top = max(clip.y, e.scrollY) + cn.num(P_STICKY, 0)
        if b.y < top: b.y = max(b.y, min(top, pb.y + pb.h - b.h))
      if cn.has(P_STICKYLEFT):
        let left = clip.x + cn.num(P_STICKYLEFT, 0)
        if b.x < left: b.x = max(b.x, min(left, pb.x + pb.w - b.w))
    e.boxes[c] = b
    e.clips[c] = clip
    if isContainer(cn.kind):
      var inner = clip
      var dy = 0'f32
      if cn.flag(P_SCROLL) or cn.flag(P_CLIP):
        inner = intersect(clip, b)
      if cn.flag(P_SCROLL):
        # how far the content reaches below the box
        var bottom = 0'f32
        proc reach(e: Engine; id: int32; bottom: var float32) =
          for k in e.node(id).children:
            let kn = e.node(k)
            if not kn.alive: continue
            if kn.kind == K_GROUP: e.reach(k, bottom)
            elif k in e.yoga:
              let kl = e.yoga[k].layout()
              bottom = max(bottom, kl.top + kl.height)
        e.reach(c, bottom)
        let mx = max(0'f32, bottom + cn.num(P_PAD_BOTTOM, 0) - b.h)
        e.scrollMax[c] = mx
        let was = e.scrolls.getOrDefault(c, 0)
        var cur = was
        if cn.has(P_SCROLLY) and not (cn.flag(P_SMOOTH) and e.placedOnce):                       # the app moved it (`scrollTo = y`; past the end: the end)
          let want = cn.num(P_SCROLLY, 0)
          if c notin e.scrollSet and cn.flag(P_STICKTOEND):
            e.scrollSet[c] = want                   # at first, sticking to the end wins
          elif c notin e.scrollSet or e.scrollSet[c] != want:
            e.scrollSet[c] = want
            cur = want
            e.atEnd[c] = want >= mx - 1
        if cn.flag(P_STICKTOEND) and e.atEnd.getOrDefault(c, true): cur = mx
        if not (cn.flag(P_SMOOTH) and e.placedOnce):
          e.scrolls[c] = clamp(cur, 0, mx)
          if cn.flag(P_STICKTOEND): e.atEnd[c] = e.scrolls[c] >= mx - 1
          if e.scrolls[c] != was: e.scrollNotes.add (c, e.scrolls[c])
        dy = e.scrolls.getOrDefault(c, 0)
      e.placeAll(c, b.x, b.y - dy, inner, c)

proc validAppName(n: string): bool =
  ## Only a plain name from the app folder: no paths, so an app can't reach files.
  n.len > 0 and n.len <= 64 and n.allCharsInSet({'a'..'z', '0'..'9', '_', '-'})

proc appSourcePath(e: Engine; src: string): string =
  ## Where an AppView's app is: a plain name beside this app, or "y:<id>" — an app of the
  ## Yantra web on this machine, apps/<id>/app.wasm next to this app's own folder (the desktop
  ## opens them). "" if neither is valid or there. (Later: "y:<id>.<domain>", fetched and cached.)
  if src.startsWith("y:"):
    let id = src[2 .. ^1]
    if validAppName(id) and fileExists(e.appDir / ".." / id / "app.wasm"): return e.appDir / ".." / id / "app.wasm"
  elif validAppName(src) and fileExists(e.appDir / src & ".wasm"): return e.appDir / src & ".wasm"
  ""

proc netAssetCachePath*(appName, url: string): string =
  ## Where a downloaded network image lives: `dataDir()/<appName>/.cache/<sha1 of url>`.
  if not validStoreKey(appName) or url.len == 0: return ""
  dataDir() / appName / ".cache" / ($secureHash(url)).toLowerAscii

proc resolveAsset*(e: Engine; p: string): string =
  ## The file an app names, inside its own folder, or a network URL allowed by the
  ## window's `net` list cached under `dataDir()/<appName>/.cache/<sha1>`; "" otherwise.
  if p.startsWith("data/") and validAssetPath(p[5 .. ^1]) and validStoreKey(e.s.appName):
    return dataDir() / e.s.appName / p[5 .. ^1]      # what the app saved: recordings, photos (Q2)
  if validAssetPath(p) and e.appDir.len > 0:
    return e.appDir / p
  if (p.startsWith("https://") or p.startsWith("http://")) and e.s != nil and e.s.nodes.len > 0:
    let winNet = e.s.nodes[0].sProp(P_NET)
    if netAllowed(winNet, p):
      let appName = if e.s.appName.len > 0: e.s.appName else: "app"
      let cachePath = netAssetCachePath(appName, p)
      if cachePath.len > 0:
        if fileExists(cachePath): return cachePath
        if p notin e.imgRequested:
          e.imgRequested.incl p
          e.imgPending.add p
  ""

proc deadEngine(msg: string; w, h: float32): Engine =
  Engine(crashed: msg, width: w, height: h, scale: 1, hover: -1, pressed: -1, focus: -1,
         activeChild: -1, hoverChild: -1, pressedChild: -1)

proc passTheme(e: Engine; child: Engine) =
  ## The host's theme (its window's Theme prop) goes to the app inside, which
  ## switches itself in `yantra_theme` — one click re-themes every sandbox.
  if child.crashed.len > 0 or child.app == nil: return
  let name = e.node(0).sProp(P_THEME)
  if name.len == 0 or child.node(0).sProp(P_THEME) == name: return
  child.s.setProp(0, P_THEME, Value(kind: vkString, s: name))
  try:
    discard child.app.sendTheme(name)
  except CatchableError as err:
    child.crashed = err.msg
  child.dirty = true

proc syncChildren(e: Engine) =
  ## Starts an app for every AppView that appeared or changed `source`, sizes each
  ## one to its box, and drops apps whose AppView is gone.
  var gone: seq[int32]
  for id, _ in e.children:
    if not e.s.valid(id) or e.node(id).kind != K_APPVIEW: gone.add id
  for id in gone:
    e.children.del(id)
    e.childSource.del(id)
    if e.activeChild == id: e.activeChild = -1
  for id, b in e.boxes:
    let n = e.node(id)
    if n.kind != K_APPVIEW or not n.alive: continue
    let src = n.sProp(P_SOURCE)
    if e.childSource.getOrDefault(id, "<none>") != src:
      e.childSource[id] = src
      let path = e.appSourcePath(src)
      if path.len > 0:
        try:
          e.children[id] = start(path, max(b.w, 1), max(b.h, 1), 1)
        except CatchableError as err:
          e.children[id] = deadEngine(err.msg, b.w, b.h)
      else:
        e.children[id] = deadEngine("No app called \"" & src & "\"", b.w, b.h)
      e.children[id].now = e.now
      e.children[id].reducedMotion = e.reducedMotion
      e.children[id].asyncImages = e.asyncImages
      e.children[id].liveMedia = e.liveMedia
    let c = e.children[id]
    e.passTheme(c)
    if c.width != b.w or c.height != b.h:
      c.width = b.w
      c.height = b.h
      c.laidOutVersion = -1
      c.dirty = true

# --- overlays (OV1): modals, drawers, popovers, menus, context menus, tooltips -------------
# Each open overlay is its own Yoga root, laid out after the page and placed on the window (not
# the page): a modal centred over a dimmed window, a drawer docked to an edge, a popover, menu or
# tooltip by its anchor (the node it is inside), flipped to the other side when it would not fit,
# a context menu where the right click was. They paint above everything in tree order, so a menu
# opened inside a modal is above the modal. Escape or a click outside dismisses the top one.

proc anchorOf(e: Engine; id: int32): int32 =
  ## The node an overlay opens by: its nearest ancestor that is not a Group.
  var p = e.node(id).parent
  while p > 0 and e.node(p).kind == K_GROUP: p = e.node(p).parent
  max(p, 0)

proc tooltipOf(e: Engine; id: int32): int32 =
  ## The tooltip a node holds (through Groups), or -1.
  for c in e.node(id).children:
    let cn = e.node(c)
    if not cn.alive: continue
    if cn.kind == K_TOOLTIP: return c
    if cn.kind == K_GROUP:
      let t = e.tooltipOf(c)
      if t >= 0: return t
  -1

proc isOpen(e: Engine; id: int32; n: tree.Node): bool =
  if id in e.ovClosed:
    if n.has(P_MODALOPEN) and not n.flag(P_MODALOPEN): e.ovClosed.excl id   # closed by the app too: may reopen
    return false
  case n.kind
  of K_TOOLTIP: e.tipOn and e.tipShown and e.anchorOf(id) == e.tipAnchor and n.sProp(P_TEXT).len > 0
  of K_CONTEXTMENU: id in e.ctxAt
  else: not n.has(P_MODALOPEN) or n.flag(P_MODALOPEN)

proc buildOverlays(e: Engine) =
  e.ovDirty = false
  if e.ovRoots.len > 0: e.fullDamage = true          # what was under a closing overlay shows again
  for id in e.ovYogaIds:                            # last layout's overlay Yoga trees: gone as a whole
    e.yoga.del id
    e.yogaHost.del id
  e.ovYogaIds.clear()
  for (_, y) in e.ovRoots: y.free(recursive = true)
  e.ovRoots.setLen(0)
  var gone: seq[int32]
  for id in e.ovClosed:
    if not e.s.valid(id) or not e.node(id).alive: gone.add id
  for id in gone: e.ovClosed.excl id
  proc walk(e: Engine; id: int32) =
    let n = e.node(id)
    if not n.alive or not n.visible: return
    if id != 0 and isOverlay(n.kind):
      if not e.isOpen(id, n): return
      let y = newNode()
      e.yoga[id] = y
      e.ovYogaIds.incl id
      styleCommon(y, n, false)
      let pad = case n.kind
                of K_MODAL: 24'f32
                of K_DRAWER: 20'f32
                of K_POPOVER: 12'f32
                of K_TOOLTIP: 6'f32
                else: 6'f32                                  # menus
      for (edge, p) in [(edgeTop, P_PAD_TOP), (edgeBottom, P_PAD_BOTTOM), (edgeLeft, P_PAD_LEFT), (edgeRight, P_PAD_RIGHT)]:
        if not n.has(p): y.setPadding(edge, if n.kind == K_TOOLTIP and edge in [edgeLeft, edgeRight]: 10'f32 else: pad)
      if n.kind == K_TOOLTIP:
        let leaf = Leaf(text: n.sProp(P_TEXT), size: n.num(P_FONTSIZE, 12), weight: 500, kind: K_TEXT, st: n.textStyle)
        e.leafOf[id] = leaf
        y.setContext(cast[pointer](leaf))
        y.setMeasureFunc(measureLeaf)
        if not n.has(P_MAXWIDTH): y.setMaxWidth(280)
      else:
        styleContainer(y, n)
        if n.kind in [K_MENU, K_CONTEXTMENU] and not n.has(P_MINWIDTH): y.setMinWidth(180)
        for c in n.children: e.buildYoga(y, c, id)
      if n.kind == K_DRAWER:
        if not n.has(P_WIDTH): y.setWidth(min(320'f32, e.width))
        y.setHeight(e.height)
      else:
        if not n.has(P_MAXWIDTH): y.setMaxWidth(max(e.width - 32, 1))
        if not n.has(P_MAXHEIGHT): y.setMaxHeight(max(e.height - 32, 1))
      y.calculateLayout(NaN, NaN)
      e.ovRoots.add (id, y)
      e.fullDamage = true
      proc mark(e: Engine; k: int32) =               # its nodes: focus order, and kept out of the page's upkeep
        for c in e.node(k).children:
          let cn = e.node(c)
          if not cn.alive or notLaid(cn.kind): continue
          if c in e.yoga and cn.kind != K_GROUP:
            e.ovYogaIds.incl c
            e.paintOrder.add c
          if cn.kind == K_GROUP or yogaKids(cn.kind): e.mark(c)
      e.paintOrder.add id
      e.mark(id)
    for c in n.children: e.walk(c)      # overlays inside overlays: a menu in a modal
  e.walk(0)

proc placeOverlays(e: Engine) =
  let top = e.scrollY                   # page coordinates of the window's top edge
  let win = Box(x: 0, y: top, w: e.width, h: e.height)
  for (id, y) in e.ovRoots:
    let n = e.node(id)
    let l = y.layout()
    let (w, h) = (l.width, l.height)
    var x, py: float32
    case n.kind
    of K_MODAL:
      x = (e.width - w) / 2
      py = top + max(16'f32, (e.height - h) / 2)
    of K_DRAWER:
      let left = int(n.num(P_PLACEMENT, 2)) == 3 or n.sProp(P_SOURCE) == "left"
      x = if left: 0'f32 else: e.width - w
      py = top
    of K_CONTEXTMENU:
      (x, py) = e.ctxAt.getOrDefault(id, (0'f32, top))
      if x + w > e.width - 8: x -= w                       # open leftwards / upwards near an edge
      if py + h > top + e.height - 8: py -= h
    else:                                                   # popover, menu, tooltip: by the anchor
      let an = e.anchorOf(id)
      var a = e.boxes.getOrDefault(an, win)
      if n.kind in [K_POPOVER, K_MENU] and an == e.focus and isText(e.node(an).kind):
        let (cx, cy, cw, ch) = e.caretRect()             # in a text field: by the caret (`/` and `@` menus)
        a = Box(x: cx, y: cy + e.scrollY, w: cw, h: ch)
      let gap = if n.kind == K_TOOLTIP: 6'f32 else: 4'f32
      var side = int(n.num(P_PLACEMENT, if n.kind == K_TOOLTIP: 1 else: 0))
      if side == 0 and a.y + a.h + gap + h > top + e.height and a.y - gap - h >= top: side = 1
      elif side == 1 and a.y - gap - h < top: side = 0
      elif side == 2 and a.x + a.w + gap + w > e.width: side = 3
      elif side == 3 and a.x - gap - w < 0: side = 2
      let alongX = if n.kind == K_TOOLTIP: a.x + (a.w - w) / 2 else: a.x
      case side
      of 1: (x, py) = (alongX, a.y - gap - h)
      of 2: (x, py) = (a.x + a.w + gap, a.y)
      of 3: (x, py) = (a.x - gap - w, a.y)
      else: (x, py) = (alongX, a.y + a.h + gap)
    if n.kind != K_DRAWER:                                  # always wholly on the window
      x = clamp(x, 8, max(8'f32, e.width - w - 8))
      py = clamp(py, top + 8, max(top + 8, top + e.height - h - 8))
    let b = Box(x: x, y: py, w: w, h: h)
    e.boxes[id] = b
    e.clips[id] = win
    e.placeAll(id, x, py, intersect(win, b), id)

proc place(e: Engine) =
  e.boxes.clear()
  e.clips.clear()
  e.moving = false
  let all = Box(x: -1e6, y: -1e6, w: 2e6, h: 2e6)
  e.boxes[0] = Box(x: 0, y: 0, w: e.width, h: max(e.contentH, e.height))
  e.clips[0] = all
  e.placeAll(0, 0, 0, all, 0)
  for id, b in e.ghostBoxes:          # nodes on their way out keep their last place
    e.boxes[id] = b
    e.clips[id] = e.ghostClips.getOrDefault(id, b)
  e.placeOverlays()
  e.placeDirty = false
  e.placedOnce = true

proc catchLeavers(e: Engine) =
  ## Nodes with `exit` that the app just removed become ghosts: drawn where they
  ## were, playing their exit, then dropped. Also forgets motion of dead nodes.
  var gone: seq[int32]
  var unwatch: seq[int32]
  for id, _ in e.exitWatch:
    if not e.node(id).alive:
      if e.node(id).has(P_EXIT): gone.add id
      else: unwatch.add id
  for id in unwatch: e.exitWatch.del id
  for id in gone:
    var host = -1'i32
    for h in e.exitWatch.getOrDefault(id):          # its container may have gone with it (a whole `if` branch)
      if e.s.valid(h):
        host = h
        break
    e.exitWatch.del id
    if e.reducedMotion or id notin e.boxes or host < 0: continue
    var g = Ghost(id: id, host: host, t0: e.now, spec: parseSpec(e.node(id).sProp(P_EXIT)))
    proc snap(e: Engine; k: int32; g: var Ghost) =
      if k in e.boxes:
        g.ids.add k
        e.ghostBoxes[k] = e.boxes[k]
        e.ghostClips[k] = e.clips.getOrDefault(k, e.boxes[k])
      for ch in e.node(k).children: e.snap(ch, g)
    e.snap(id, g)
    e.ghosts.add g
  var dead: seq[int32]
  for id in e.motions.keys:
    if not e.node(id).alive and id notin e.ghostBoxes: dead.add id
  for id in dead: e.motions.del id
  dead.setLen(0)
  for id in e.loopAt.keys:
    if not e.node(id).alive: dead.add id
  for id in dead: e.loopAt.del id
  dead.setLen(0)
  for id, p in e.players:
    if not e.node(id).alive: dead.add id
  for id in dead:
    e.closePlayer(e.players[id])
    e.players.del id
  dead.setLen(0)
  for id, m in e.models:
    if not e.node(id).alive: dead.add id
  for id in dead:
    e.models[id].scene.close()
    e.models.del id
  dead.setLen(0)
  for id, p in e.gifs:
    if not e.node(id).alive: dead.add id
  for id in dead:
    if e.gifs[id].dec != nil: e.gifs[id].dec.close()
    e.gifs.del id
  dead.setLen(0)
  for id in e.imgBlank:
    if not e.node(id).alive: dead.add id
  for id in e.imgFadeAt.keys:
    if not e.node(id).alive: dead.add id
  for id in dead:
    e.imgBlank.excl id
    e.imgWaiting.excl id
    e.imgFadeAt.del id

proc under(e: Engine; id, c: int32): bool =
  ## `id` is inside `c`.
  var p = e.node(id).parent
  while p >= 0:
    if p == c: return true
    p = e.node(p).parent

proc keyedRow(e: Engine; c: int32; key: string): int32 =
  ## The row with ItemKey `key` inside scroll area `c`, or -1.
  for k in e.paintOrder:
    if e.node(k).has(P_ITEMKEY) and e.node(k).sProp(P_ITEMKEY) == key and k in e.boxes and e.under(k, c): return k
  -1

type ScrollAnchor = object
  c: int32
  key: string                     ## the first row that showed ("" none)
  offset: float32                 ## its top below the area's top, before
  atEnd: bool

proc scrollAnchors(e: Engine): seq[ScrollAnchor] =
  ## Before a layout moves things: for each anchored area, which row is first on screen and
  ## where, and whether the area sits at its end.
  for c in e.scrollCtl:
    if c notin e.boxes: continue
    let n = e.node(c)
    let cb = e.boxes[c]
    var a = ScrollAnchor(c: c, offset: 0)
    a.atEnd = c notin e.scrollMax or e.scrolls.getOrDefault(c, 0) >= e.scrollMax[c] - 2
    if n.flag(P_ANCHOR):
      for k in e.paintOrder:
        let kn = e.node(k)
        if kn.has(P_ITEMKEY) and k in e.boxes and e.boxes[k].y + e.boxes[k].h > cb.y and e.under(k, c):
          a.key = kn.sProp(P_ITEMKEY)
          a.offset = e.boxes[k].y - cb.y
          break
    result.add a

proc applyScrollCtl(e: Engine; anchors: seq[ScrollAnchor]) =
  ## After placing: keeps anchored rows still, keeps stuck-to-the-end areas at the end, and
  ## applies new ScrollY / ScrollToKey values. Scrolls that moved are told (Scroll event).
  var moved: seq[int32]
  for c in e.scrollCtl:
    if c notin e.boxes: continue
    let n = e.node(c)
    let cb = e.boxes[c]
    let mx = e.scrollMax.getOrDefault(c, 0)
    let was = e.scrolls.getOrDefault(c, 0)
    var y = was
    var i = -1
    for j, a in anchors:
      if a.c == c: i = j
    if n.flag(P_STICKBOTTOM) and (i < 0 or anchors[i].atEnd):
      y = mx                                        # new, or already at its end: stay there
    elif i >= 0 and anchors[i].key.len > 0:
      let k = e.keyedRow(c, anchors[i].key)
      if k >= 0: y = was + (e.boxes[k].y - cb.y) - anchors[i].offset
    let seen = e.scrollSeen.getOrDefault(c, (NaN.float32, ""))
    var asked = false
    if n.has(P_SCROLLY) and n.num(P_SCROLLY, 0) != seen[0]:
      y = n.num(P_SCROLLY, 0)
      asked = true
      e.scrollSeen[c] = (n.num(P_SCROLLY, 0), seen[1])
    let want = n.sProp(P_SCROLLTOKEY)
    if want.len > 0 and want != e.scrollSeen.getOrDefault(c, seen)[1]:
      let hashAt = want.find('#')
      let k = e.keyedRow(c, if hashAt >= 0: want[0 ..< hashAt] else: want)
      if k >= 0:                                    # not built yet: tried again next layout
        y = was + (e.boxes[k].y - cb.y)
        asked = true
        e.scrollSeen[c] = (e.scrollSeen.getOrDefault(c, seen)[0], want)
    y = clamp(y, 0, mx)
    if abs(y - was) > 0.01 and n.flag(P_SMOOTH) and e.placedOnce and not e.reducedMotion and
       asked:                                       # an asked-for scroll glides there (Q4); anchoring never does
      e.glides[c] = Glide(target: y, lastInput: e.now)
    elif abs(y - was) > 0.01:
      e.scrolls[c] = y
      moved.add c
  if moved.len > 0:
    e.place()
    e.fullDamage = true
    for c in moved: e.noteScroll(c, e.scrolls[c])

proc layout*(e: Engine) =
  ## Brings the layout up to date with the tree. The Yoga tree is kept between layouts:
  ## only nodes the app changed are restyled or re-linked, so Yoga re-measures only them
  ## and lays out only the paths above them (P1). A resize, a reload or a change of the
  ## window's own style rebuilds it all.
  e.catchLeavers()
  let root = e.node(0)
  # app-style when some scroll area grows into the space left: the window is exactly its
  # size and that area scrolls; page-style otherwise: the page grows and the window scrolls
  var appStyle = false
  for n in e.s.nodes:
    if n.alive and n.flag(P_SCROLL) and n.has(P_FLEXGROW): (appStyle = true; break)
  e.restyled = 0
  let keep = e.root != nil and e.laidOutVersion >= 0 and e.yogaFor == e.s and e.yogaW == e.width and
             e.yogaH == e.height and e.yogaAppStyle == appStyle and e.updateYoga()
  if keep:
    inc e.partialLayouts
  else:
    inc e.fullLayouts
    e.fullDamage = true
    e.freeYoga()
    e.root = newNode()
    e.root.setWidth(e.width)
    if appStyle: e.root.setHeight(e.height) else: e.root.setMinHeight(e.height)
    styleContainer(e.root, root)
    e.yoga[0] = e.root
    for c in root.children: e.buildYoga(e.root, c, 0)
    e.yogaFor = e.s
    e.yogaW = e.width
    e.yogaH = e.height
    e.yogaAppStyle = appStyle
  let changed = if e.partialPaint and keep: e.s.touched else: initHashSet[int32]()
  e.s.touched.clear()
  e.s.reshaped.clear()
  e.sweepYoga()
  let dir = if root.num(P_DIRECTION, 0) >= 2: dirRTL else: dirLTR
  e.root.calculateLayout(e.width, NaN, dir)
  for _ in 0 ..< 4:                   # grids: size their items, again while nested ones change
    if e.grids.len == 0 or not e.fitGrids(): break
    e.root.calculateLayout(e.width, NaN, dir)
  e.contentH = e.root.layout().height
  let sy = clamp(e.scrollY, 0, max(0, e.contentH - e.height))
  if sy != e.scrollY: e.fullDamage = true
  e.scrollY = sy
  let before = if e.partialPaint and keep and not e.fullDamage: e.boxes else: initTable[int32, Box]()
  let beforeClips = if before.len > 0: e.clips else: initTable[int32, Box]()
  e.buildOverlays()
  let anchors = e.scrollAnchors()
  for id, b in e.boxes:                             # named nodes that just went: heroes to be (Q5)
    if id > 0 and not e.node(id).alive and e.node(id).has(P_NAME) and e.node(id).sProp(P_NAME) notin e.heroFrom:
      e.heroFrom[e.node(id).sProp(P_NAME)] = (b, e.now)
  e.place()
  e.applyScrollCtl(anchors)
  for due in e.focusDue:                            # FocusAt (Q6): the app puts the caret somewhere
    if due < 0:                                     # Replace (Q9): "start,end,text#n" as an edit of that field
      let id = -due - 1
      if not e.s.valid(id): continue
      let spec = e.node(id).sProp(P_REPLACE)
      e.replaceSeen[id] = spec
      let f = spec.split(',')
      if f.len < 3: continue
      var a, z: int
      if parseInt(f[0], a) == 0 or parseInt(f[1], z) == 0: continue
      var text = f[2 .. ^1].join(",")
      let hashAt = text.rfind('#')
      if hashAt >= 0: text.setLen(hashAt)
      let v = e.node(id).sProp(P_VALUE)
      a = clamp(a, 0, v.len)
      z = clamp(z, a, v.len)
      e.focusOn(id)
      e.anchor = a
      e.caret = z
      e.replaceSelection(text)
      continue
    let id = due
    if not e.s.valid(id): continue
    let v = e.node(id).sProp(P_FOCUSAT)
    e.focusSeen[id] = v
    let hashAt = v.find('#')
    var at = 0
    discard parseInt(if hashAt >= 0: v[0 ..< hashAt] else: v, at)
    e.focusOn(id)
    e.caret = clamp(at, 0, e.node(id).sProp(P_VALUE).len)
    e.anchor = e.caret
  e.focusDue.setLen(0)
  if before.len > 0: e.damageMoved(before, beforeClips, changed)
  e.laidOutVersion = e.s.version
  e.syncChildren()

proc fireResizes(e: Engine): bool =
  ## Tells nodes with a Resize handler their laid-out size when it changed (container
  ## queries: `sized w:` in the SDK). True if any handler ran (the tree may have changed).
  var due: seq[(int32, int32)]
  for (key, h) in e.s.events.pairs:
    if key[1] != E_RESIZE or key[0] notin e.yoga: continue
    let l = e.yoga[key[0]].layout()
    let was = e.s.sizes.getOrDefault(key[0], (-1'f32, -1'f32))
    if abs(was[0] - l.width) >= 0.5 or abs(was[1] - l.height) >= 0.5:
      e.s.sizes[key[0]] = (l.width, l.height)
      due.add (key[0], h)
  for (_, h) in due:
    try:
      dispatchTo(e.app, h)
    except CatchableError as err:
      e.crashed = err.msg
      return false
    result = true
  if result: e.dirtyF = true

proc ensureLayout*(e: Engine) =
  if e.crashed.len > 0: return
  for _ in 0 ..< 4:                   # a size can change what is shown, which can change sizes: settle
    if e.laidOutVersion != e.s.version or e.boxes.len == 0 or e.ovDirty: e.layout()
    elif e.placeDirty: e.place()
    var notes = false                  # offsets placement moved (scrollTo, stickToEnd) reach Scroll handlers
    for (id, y) in e.scrollNotes:
      if e.s.valid(id) and e.s.handlerFor(id, E_SCROLL) >= 0 and e.s.scrollOf.getOrDefault(id, -1) != y:
        e.s.scrollOf[id] = y
        e.fire(id, E_SCROLL)
        notes = true
    e.scrollNotes.setLen(0)
    if e.crashed.len > 0 or not (e.fireResizes() or notes): break

# --- state styles -----------------------------------------------------------------

proc hovered(e: Engine; id: int32): bool = id in e.hoverChain
proc isPressed(e: Engine; id: int32): bool = e.pressed == id and e.hovered(id)

proc stateColor(e: Engine; id: int32; n: tree.Node; base: uint32; hoverP, pressP, focusP: int32): uint32 =
  if e.isPressed(id) and n.has(pressP): return n.col(pressP, base)
  if e.focus == id and n.has(focusP): return n.col(focusP, base)
  if e.hovered(id) and n.has(hoverP): return n.col(hoverP, base)
  base

proc opacityOf(e: Engine; id: int32; n: tree.Node): float32 =
  result = n.num(P_OPACITY, 1)
  if e.isPressed(id) and n.has(P_PRESSOPACITY): result = n.num(P_PRESSOPACITY, 1)
  elif e.focus == id and n.has(P_FOCUSOPACITY): result = n.num(P_FOCUSOPACITY, 1)
  elif e.hovered(id) and n.has(P_HOVEROPACITY): result = n.num(P_HOVEROPACITY, 1)

proc stateNum(e: Engine; id: int32; n: tree.Node; base: float32; hoverP, pressP, focusP: int32): float32 =
  if e.isPressed(id) and n.has(pressP): return n.num(pressP, base)
  if e.focus == id and n.has(focusP): return n.num(focusP, base)
  if e.hovered(id) and n.has(hoverP): return n.num(hoverP, base)
  base

# --- paint -------------------------------------------------------------------------

proc drawCheck(c: Canvas; x, y, s: float32; col: uint32) =
  c.strokePolyline([(x + s * 0.26'f32, y + s * 0.52'f32), (x + s * 0.44'f32, y + s * 0.70'f32),
                    (x + s * 0.76'f32, y + s * 0.32'f32)], s * 0.13'f32, col)

proc paintSurface(e: Engine; c: Canvas; id: int32; n: tree.Node; b: Box; defaultFill: uint32; radius: float32) =
  ## Shadow, then gradient or fill (with state styles), then border.
  if n.has(P_SHADOWCOLOR) and (n.num(P_SHADOWBLUR, 0) > 0 or n.num(P_SHADOWY, 0) != 0 or n.num(P_SHADOWX, 0) != 0):
    c.shadow(b.x, b.y, b.w, b.h, radius, n.num(P_SHADOWX, 0), n.num(P_SHADOWY, 0), n.num(P_SHADOWBLUR, 0),
             n.col(P_SHADOWCOLOR, 0x59000000'u32))
  let stateFill = (e.isPressed(id) and n.has(P_PRESSFILL)) or (e.focus == id and n.has(P_FOCUSFILL)) or
                  (e.hovered(id) and n.has(P_HOVERFILL))
  if n.has(P_SHADER) and not stateFill:            # an SkSL shader is the fill (FX1)
    let src = n.sProp(P_SHADER)
    let err = c.shaderRRect(src, b.x, b.y, b.w, b.h, radius, float32(e.now / 1000))
    if err.len > 0:
      e.devNote = "A shader did not compile: " & err
    elif shaderUsesTime(src) == 1:
      e.animating = true                            # it reads `time`: keep the frames coming
    let bw = n.num(P_BORDER_WIDTH, 0)
    if bw > 0: c.strokeRRect(b.x, b.y, b.w, b.h, radius, bw, n.col(P_BORDER_COLOR, Line))
    return
  if not stateFill and n.has(P_GRADANGLE) and n.num(P_GRADANGLE, -1) >= 0:
    c.fillGradient(b.x, b.y, b.w, b.h, radius, n.col(P_GRADFROM, 0xFF000000'u32), n.col(P_GRADTO, 0xFF000000'u32),
                   n.num(P_GRADANGLE, 90))
  else:
    let base = if n.fillProp: n.col(P_COLOR, defaultFill) else: defaultFill
    let f = e.eased(id, n, cFill, e.stateColor(id, n, base, P_HOVERFILL, P_PRESSFILL, P_FOCUSFILL))
    if (f shr 24) != 0: c.fillRRect(b.x, b.y, b.w, b.h, radius, f)
  let bw = n.num(P_BORDER_WIDTH, 0)
  let bc = e.stateColor(id, n, n.col(P_BORDER_COLOR, Line), P_HOVERBORDER, P_PRESSBORDER, P_FOCUSBORDER)
  let shown = e.eased(id, n, cBorder, bc)
  if bw > 0: c.strokeRRect(b.x, b.y, b.w, b.h, radius, bw, shown)
  elif (bc != n.col(P_BORDER_COLOR, Line) and bc != Line) or shown != bc:
    c.strokeRRect(b.x, b.y, b.w, b.h, radius, 1.5, shown)    # a state border on a borderless node

when not defined(emscripten):
  proc paintGif(e: Engine; c: Canvas; id: int32; path: string; b: Box; r: float32; fit: int) =
    ## A GIF Skia can't decode, through libav like a looping video, decoded at the drawn size.
    if not path.toLowerAscii.endsWith(".gif"): return
    var p = e.gifs.getOrDefault(id)
    let bw = clamp(int(b.w * e.scale), 2, 2048)
    let bh = clamp(int(b.h * e.scale), 2, 2048)
    if p == nil or p.src != path or p.bw != bw or p.bh != bh:
      if p != nil and p.dec != nil: p.dec.close()
      p = Player(src: path, startAt: e.now, dec: openDecoder(path), bw: bw, bh: bh)
      p.buf = newSeq[uint32](bw * bh)
      e.gifs[id] = p
    if p.dec == nil: return
    let dur = p.dec.seconds
    var t = (e.now - p.startAt) / 1000
    if dur > 0: t = t mod dur
    if p.dec.frameAt(t, addr p.buf[0], p.bw, p.bh):
      c.drawPixels(addr p.buf[0], p.bw, p.bh, b.x, b.y, b.w, b.h, r, fit)
    if dur > 0:
      e.animating = true
      e.animIds.add id

include scene3d

# --- raster layers and bulk pixels (CV2): an app's bitmaps, drawn into over time ------------

var nextLayerBase = 1_000_000
var canvasBufs {.threadvar.}: HostState      ## whose buffers 'X' reads while canvases paint

proc bufBytes(id: cint; n: ptr cint): pointer {.cdecl.} =
  if canvasBufs == nil or int32(id) notin canvasBufs.bufs: return nil
  n[] = cint(canvasBufs.bufs[int32(id)].len)
  if n[] == 0: nil else: addr canvasBufs.bufs[int32(id)][0]

proc wireTextMetrics(e: Engine) =
  ## The app's y_text_measure calls. The measuring code already exists and is used
  ## internally (this file calls measureText for chrome, inputs and hit-testing) — what was
  ## missing was a way for a wasm app to reach it, because `Draw` is a plain command string
  ## and cannot return a value. This closes that: a synchronous host import.
  e.s.measureTextOp = proc (s, family: string; size: float32; weight: int32): float32 =
    if s.len == 0: return 0
    let (w, _) = measureText(s, size, int(weight), 0, TextStyle(family: family))
    w

proc wireLayers(e: Engine) =
  ## The app's y_layer_* calls, done here: new, draw into, filter, read, write, free.
  e.layerBase = nextLayerBase
  nextLayerBase += 1_000_000
  let ee = e
  e.s.layerOp = proc (op, id, x, y, w, h: int32; f: float32; data: string): string =
    if id < 0 or id >= 1_000_000: return ""
    let g = ee.layerBase + int(id)
    case op
    of 0:
      if not newLayer(g, int(w), int(h)): return ""
      if id notin ee.layers: ee.layers.add id
      result = "1"
    of 1:
      canvasBufs = ee.s
      canvasEnv(ee.layerBase, cast[pointer](bufBytes))
      discard drawLayer(g, data, ee.appDir)
    of 2: discard filterLayer(g, int(x), f)
    of 3: return readLayer(g, int(x), int(y), int(w), int(h))
    of 4: discard writeLayer(g, int(x), int(y), int(w), int(h), data)
    of 5:
      freeLayer(g)
      ee.layers.del(ee.layers.find(id))
    else: discard
    if op in [0'i32, 1, 2, 4, 5]:        # a layer changed: canvases showing it paint again
      ee.layerVer.mgetOrPut(id, 0).inc
      for sc in ee.views3d.keys: ee.damageNode(sc)
      ee.fullDamage = true
      ee.dirty = true

proc paintNode(e: Engine; c: Canvas; id: int32) =
  let n = e.node(id)
  let b = e.boxes[id]
  let k = n.kind
  let r = n.num(P_RADIUS, 0)
  case k
  of K_COLUMN, K_ROW, K_PANEL, K_STACK, K_SCROLLAREA, K_PAGE, K_GRID:
    e.paintSurface(c, id, n, b, 0, r)
  of K_MODAL, K_DRAWER, K_POPOVER, K_MENU, K_CONTEXTMENU:
    let rad = if n.has(P_RADIUS): r elif k == K_DRAWER: 0'f32 elif k == K_MODAL: 14'f32 else: 10'f32
    if not n.has(P_SHADOWCOLOR): c.shadow(b.x, b.y, b.w, b.h, rad, 0, 10, 30, 0x73000000'u32)
    e.paintSurface(c, id, n, b, 0xFF1C1C24'u32, rad)
    if not n.has(P_BORDER_WIDTH): c.strokeRRect(b.x, b.y, b.w, b.h, rad, 1, 0xFF34343E'u32)
  of K_TOOLTIP:
    c.fillRRect(b.x, b.y, b.w, b.h, 6, n.col(P_COLOR, 0xFF34343F'u32))
    c.drawText(n.sProp(P_TEXT), b.x + n.num(P_PAD_LEFT, 10), b.y + n.num(P_PAD_TOP, 6), n.num(P_FONTSIZE, 12),
               n.ink(Ink), 500, b.w - n.num(P_PAD_LEFT, 10) - n.num(P_PAD_RIGHT, 10), 0, n.textStyle)
  of K_TEXT:
    e.paintSurface(c, id, n, b, 0, r)
    if e.selA[0] >= 0:                            # read-only selection (P4)
      let (s0, s1) = e.selBytes(id)
      if s1 > s0:
        for (rx, ry, rw, rh) in textRects(n.sProp(P_TEXT), s0, s1, n.fontSize(k), n.fontWeight(k), b.w, n.textStyle):
          c.fillRRect(b.x + rx, b.y + ry, max(rw, 3), rh, 2, withAlpha(n.col(P_FOCUSBORDER, Amber), 0.32))
    for mi, (fid, fa, fz) in e.findMatches:       # find in page (Q3): every match, the current one stronger
      if fid == id:
        let cur = mi == int(e.node(0).num(P_FINDINDEX, 0))
        for (rx, ry, rw, rh) in textRects(n.sProp(P_TEXT), fa, fz, n.fontSize(k), n.fontWeight(k), b.w, n.textStyle):
          c.fillRRect(b.x + rx, b.y + ry, max(rw, 3), rh, 2, withAlpha(Amber, if cur: 0.75 else: 0.28))
    let inkC = e.eased(id, n, cInk, e.stateColor(id, n, n.ink(Ink), P_HOVERCOLOR, P_PRESSCOLOR, P_FOCUSCOLOR))
    c.drawText(n.sProp(P_TEXT), b.x, b.y, n.fontSize(k), inkC, n.fontWeight(k), b.w, int(n.num(P_ALIGN, 0)), n.textStyle)
    if n.has(P_INLINE):                            # inline images / emoji in their boxes in the line (Q3)
      let paths = n.sProp(P_INLINE).split(';')
      let rects = inlineRects(n.sProp(P_TEXT), n.fontSize(k), n.fontWeight(k), b.w, int(n.num(P_ALIGN, 0)), n.textStyle)
      for i, (rx, ry, rw, rh) in rects:
        if i >= paths.len: break
        let f = paths[i].split(',')
        if f.len < 3: continue
        let full = e.resolveAsset(f[2 .. ^1].join(",").strip)
        if full.len > 0 and rw > 0 and rh > 0:
          let st = c.drawImageAsync(full, b.x + rx, b.y + ry, rw, rh, 0, 0, 1, e.now, sync = e.exporting or not e.asyncImages)
          if st == imgLoading or st == imgStandIn: e.imgWaiting.incl id
          elif st == imgAnimated: (e.animating = true; e.animIds.add id)
  of K_BUTTON:
    let item = e.node(e.anchorOf(id)).kind in [K_MENU, K_CONTEXTMENU]   # a menu's item: flat, left-aligned
    var bg = if n.fillProp: n.col(P_COLOR, ButtonBg) elif item: 0x00000000'u32 else: ButtonBg
    if item and not n.fillProp and e.hovered(id): bg = 0xFF2C2C38'u32
    if not n.has(P_HOVERFILL) and e.hovered(id): bg = shade(bg, 1.12)
    if not n.has(P_PRESSFILL) and e.isPressed(id): bg = shade(bg, 0.85)
    let tmp = tree.Node(kind: n.kind, props: n.props, children: @[], parent: n.parent, alive: true)
    tmp.props[P_COLOR] = Value(kind: vkInt, i: cast[int32](bg))
    e.paintSurface(c, id, tmp, b, bg, n.num(P_RADIUS, 8))
    let fg = e.eased(id, n, cInk, e.stateColor(id, n, n.ink(Ink), P_HOVERCOLOR, P_PRESSCOLOR, P_FOCUSCOLOR))
    let pt = n.num(P_PAD_TOP, 9); let pl = n.num(P_PAD_LEFT, 14); let pr = n.num(P_PAD_RIGHT, 14)
    c.drawText(n.sProp(P_TEXT), b.x + pl, b.y + pt, n.fontSize(k), fg, n.fontWeight(k), b.w - pl - pr,
               int(n.num(P_ALIGN, if item: 0 else: 1)), n.textStyle)
  of K_CHECKBOX:
    let on = n.iProp(P_CHECKED) != 0
    let s = 18'f32
    let by = b.y + (b.h - s) / 2
    let accent = n.col(P_COLOR, Amber)
    if on:
      c.fillRRect(b.x, by, s, s, min(5, r + 5), accent)
      drawCheck(c, b.x, by, s, n.col(P_FOCUSCOLOR, 0xFF1A1206'u32))
    else:
      c.strokeRRect(b.x, by, s, s, 5, 1.5, if e.hovered(id): Muted else: n.col(P_BORDER_COLOR, Faint))
    let baseInk = n.ink(Ink)
    let inkC = if on: withAlpha(baseInk, 0.55) else: baseInk
    c.drawText(n.sProp(P_TEXT), b.x + 28, b.y, n.fontSize(k), inkC, n.fontWeight(k), max(b.w - 28, 1), 0, n.textStyle)
  of K_INPUT, K_TEXTAREA:
    let r2 = n.num(P_RADIUS, 8)
    let focused = e.focus == id
    let tmp = tree.Node(kind: n.kind, props: n.props, children: @[], parent: n.parent, alive: true)
    if not n.has(P_BORDER_WIDTH): tmp.props[P_BORDER_WIDTH] = Value(kind: vkFloat, f: if focused: 1.5 else: 1)
    if focused and not n.has(P_FOCUSBORDER): tmp.props[P_FOCUSBORDER] = Value(kind: vkInt, i: cast[int32](Amber))
    e.paintSurface(c, id, tmp, b, InputBg, r2)
    let v = n.sProp(P_VALUE)
    let size = n.fontSize(k)
    let wt = n.fontWeight(k)
    let st = n.textStyle
    let (ox, oy, maxW) = e.textOrigin(id)
    let accent = n.col(P_FOCUSBORDER, Amber)
    let inkC = n.ink(Ink)
    let pl = n.num(P_PAD_LEFT, 12); let pt = n.num(P_PAD_TOP, 11)
    c.save()
    c.clipRect(b.x + pl - 1, b.y + 1, max(b.w - pl - n.num(P_PAD_RIGHT, 12) + 2, 1), max(b.h - 2, 1))
    let composing = focused and e.preeditText.len > 0
    if composing:                     # an input method's word, shown in place and underlined
      let at = clamp(e.caret, 0, v.len)
      let shown = v[0 ..< at] & e.preeditText & v[at .. ^1]
      c.drawText(shown, ox, oy, size, inkC, wt, maxW, 0, st)
      for (rx, ry, rw, rh) in textRects(shown, at, at + e.preeditText.len, size, wt, maxW, st):
        c.fillRRect(ox + rx, oy + ry + rh - 2, max(rw, 2), 1.5, 0, inkC)
      var cur = e.preeditText.len
      if e.preeditCursor >= 0:
        cur = 0
        var k = 0
        while cur < e.preeditText.len and k < e.preeditCursor:
          cur += max(1, e.preeditText.runeLenAt(cur))
          inc k
      if e.caretOn:
        let (cx, cy, ch) = caretAt(shown, at + cur, size, wt, maxW, st)
        c.fillRRect(ox + cx, oy + cy, 1.5, ch, 0, accent)
    elif v.len == 0:
      c.drawText(n.sProp(P_PLACEHOLDER), ox, oy, size, withAlpha(inkC, 0.4), wt, maxW, 0, st)
    else:
      if e.selA[0] >= 0 and e.selA[0] != e.selZ[0]:          # a selection across blocks (P5)
        let (s0, s1) = e.selBytes(id)
        if s1 > s0:
          for (rx, ry, rw, rh) in textRects(v, s0, s1, size, wt, maxW, st):
            c.fillRRect(ox + rx, oy + ry, max(rw, 3), rh, 2, withAlpha(accent, 0.32))
      if focused and e.anchor != e.caret:
        let (a, z) = (min(e.anchor, e.caret), max(e.anchor, e.caret))
        for (rx, ry, rw, rh) in textRects(v, clamp(a, 0, v.len), clamp(z, 0, v.len), size, wt, maxW, st):
          c.fillRRect(ox + rx, oy + ry, max(rw, 3), rh, 2, withAlpha(accent, 0.32))
      c.drawText(v, ox, oy, size, inkC, wt, maxW, 0, st)
    if n.flag(P_SPELLCHECK) and not composing and v.len > 0:   # misspelled words: a dotted red line (Q9)
      for (a, z) in e.spellOf(id, v):
        if focused and e.caret >= a and e.caret <= z: continue       # the word being typed is left alone
        for (rx, ry, rw, rh) in textRects(v, a, z, size, wt, maxW, st):
          var x = ox + rx
          while x < ox + rx + rw:
            c.fillRRect(x, oy + ry + rh - 2, 2, 2, 1, 0xFFE53935'u32)
            x += 4
    if focused and e.caretOn and not composing:
      let (cx, cy, ch) = caretAt(v, clamp(e.caret, 0, v.len), size, wt, maxW, st)
      c.fillRRect(ox + cx, oy + cy, 1.5, ch, 0, accent)
    c.restore()
    discard pt
  of K_PATH:
    e.paintSurface(c, id, n, b, 0, r)
    let d = n.sProp(P_PATHDATA)
    if d.len > 0:
      let size = min(b.w, b.h)
      let inkC = e.eased(id, n, cInk, e.stateColor(id, n, n.ink(Ink), P_HOVERCOLOR, P_PRESSCOLOR, P_FOCUSCOLOR))
      c.svgPath(d, b.x + (b.w - size) / 2, b.y + (b.h - size) / 2, size / 24, n.num(P_STROKEWIDTH, 0), inkC)
  of K_SCENE3D:
    e.paintScene3D(c, id, n, b, r)
  of K_MODEL:
    # 3D (Filament): rendered offscreen at the box's pixel size on the engine's clock, so a
    # film gets the exact frame; drawn like a video frame
    e.paintSurface(c, id, n, b, 0, r)
    let pw = clamp(int(b.w * e.scale), 1, 4096)
    let ph = clamp(int(b.h * e.scale), 1, 4096)
    var m = e.models.getOrDefault(id)
    if m != nil and (m.scene.width != pw or m.scene.height != ph):
      m.scene.close()
      m = nil
    if m == nil:
      m = Model3D(scene: newScene3D(pw, ph), startAt: e.now)
      e.models[id] = m
    let path = e.resolveAsset(n.sProp(P_SOURCE))
    if m.scene.ok and path != m.path:
      m.path = path
      m.loaded = path.len > 0 and m.scene.load(path)
      if not m.loaded and path.len > 0: e.devNote = "model " & n.sProp(P_SOURCE) & ": " & m.scene.lastError
    if m.loaded and m.scene.render((e.now - m.startAt) / 1000, m.px):
      c.drawPixels(addr m.px[0], pw, ph, b.x, b.y, b.w, b.h, r, 2)
      if m.scene.animations > 0: (e.animating = true; e.animIds.add id)
  of K_VIDEO:
    e.paintSurface(c, id, n, b, 0, r)
    let p = e.playerFor(id)
    if p.dec != nil and b.w > 0 and b.h > 0:          # on the engine clock (tests, films)
      if p.startAt < 0: p.startAt = e.now - p.heldPos * 1000
      let t = e.mediaPos(p, n)
      if p.dec.frameAt(t, addr p.buf[0], p.bw, p.bh):
        c.drawPixels(addr p.buf[0], p.bw, p.bh, b.x, b.y, b.w, b.h, r, int(n.num(P_FIT, 0)))
      if not p.paused and not p.ended and (n.flag(P_LOOP) or t < p.duration):
        e.animating = true                            # playing: keep the frames coming
        e.animIds.add id
    elif p.hasFrame and b.w > 0 and b.h > 0:          # live: the last frame `tick` pulled
      c.drawPixels(addr p.buf[0], p.bw, p.bh, b.x, b.y, b.w, b.h, r, int(n.num(P_FIT, 0)))
  of K_IMAGE:
    e.paintSurface(c, id, n, b, 0, r)
    let rel = if n.has(P_SOURCE): n.sProp(P_SOURCE) elif n.has(P_TEXT): n.sProp(P_TEXT) else: ""
    let fullPath = e.resolveAsset(rel)
    if fullPath.len > 0 and b.w > 0 and b.h > 0:
      let fitMode = int(n.num(P_FIT, 0))
      var alpha = 1'f32
      let blank = id in e.imgBlank
      if blank: alpha = 0                     # the first frame it can draw starts its fade
      elif id in e.imgFadeAt:
        let t = (e.now - e.imgFadeAt[id]) / ImgFadeMs
        if t >= 1 or e.reducedMotion or e.exporting: e.imgFadeAt.del id
        else:
          alpha = float32(max(0.0, t))
          e.animating = true
          e.animIds.add id
      let sync = e.exporting or not e.asyncImages
      let z = e.zooms.getOrDefault(id, Zoom(scale: 1))
      if z.scale > 1:                               # zoomed (Q4): scaled about its box, clipped to it
        c.save()
        c.clipRect(b.x, b.y, b.w, b.h)
        c.translate(b.x + z.x, b.y + z.y)
        c.scale(z.scale)
        c.translate(-b.x, -b.y)
      let st = c.drawImageAsync(fullPath, b.x, b.y, b.w, b.h, r, fitMode, alpha, e.now,
                                sync = sync, level = if e.exporting: 0 else: -1)
      if z.scale > 1: c.restore()
      if st == imgLoading:
        e.imgWaiting.incl id
        e.imgBlank.incl id
      elif st == imgFailed:
        when not defined(emscripten):
          e.paintGif(c, id, fullPath, b, r, fitMode)
      else:
        if st == imgStandIn: e.imgWaiting.incl id    # the right size is on its way
        if st == imgAnimated:
          e.animating = true
          e.animIds.add id
        if blank:
          e.imgBlank.excl id
          if e.reducedMotion: e.damageNode(id)       # drawn at alpha 0 this frame: show it next
          else: e.imgFadeAt[id] = e.now
          e.animating = true
          e.animIds.add id
  of K_CANVAS:
    e.paintSurface(c, id, n, b, 0, r)
    if n.has(P_DRAW) and b.w > 0 and b.h > 0:
      canvasBufs = e.s
      canvasEnv(e.layerBase, cast[pointer](bufBytes))
      if c.drawCommands(n.sProp(P_DRAW), b.x, b.y, b.w, b.h, e.appDir, e.now):
        e.animating = true                         # an image in it is on its way or animated
        e.animIds.add id
        e.imgWaiting.incl id
  of K_APPVIEW:
    if id in e.children and b.w > 0 and b.h > 0:
      let child = e.children[id]
      c.save()
      c.translate(b.x, b.y)
      c.clipRect(0, 0, b.w, b.h)
      child.paint(c)
      c.restore()
  else: discard

proc zSorted(e: Engine; kids: seq[int32]): seq[int32] =
  ## Paint order: by zIndex; sticky nodes over their scrolling siblings (P6). Stable.
  result = kids
  var anyZ = false
  for k in kids:
    let n = e.node(k)
    if n.has(P_ZINDEX) or n.has(P_STICKY) or n.has(P_STICKYLEFT): anyZ = true
  if anyZ:
    proc z(e: Engine; k: int32): float32 =
      let n = e.node(k)
      n.num(P_ZINDEX, 0) + (if n.has(P_STICKY) or n.has(P_STICKYLEFT): 0.5 else: 0)
    result.sort(proc (a, b: int32): int = cmp(e.z(a), e.z(b)))

proc loopOf(n: tree.Node): motion.Loop =
  ## `animate = …` (sdk/ui/motion.nim) or the older `node.animate(...)`: same props.
  let target = n.sProp(P_ANIM_TARGET)
  motion.Loop(target: target, frm: n.num(P_ANIM_FROM, identity(target)), to: n.num(P_ANIM_TO, identity(target)),
       ms: float64(n.num(P_ANIM_DURATION, 300)), delay: float64(n.num(P_ANIM_DELAY, 0)),
       ease: int32(n.num(P_ANIM_EASING, 5)), count: int(n.num(P_ANIM_LOOP, 1)), yoyo: n.flag(P_ANIM_YOYO))

proc poseOf(e: Engine; id: int32; n: tree.Node): Pose =
  ## Everything that moves this node this frame, on top of its layout box: its own
  ## transform props, state scale/lift, `enter` and `animate`.
  result = Pose(opacity: e.eased(id, n, nOpacity, e.opacityOf(id, n)), x: n.num(P_X, 0), y: n.num(P_Y, 0),
                scale: n.num(P_SCALE, 1), rotate: n.num(P_ROT_Z, 0))
  if n.has(P_HOVERSCALE) or n.has(P_PRESSSCALE) or n.has(P_FOCUSSCALE):
    result.scale *= e.eased(id, n, nScale, e.stateNum(id, n, 1, P_HOVERSCALE, P_PRESSSCALE, P_FOCUSSCALE))
  if n.has(P_HOVERY) or n.has(P_PRESSY) or n.has(P_FOCUSY):
    result.y += e.eased(id, n, nLift, e.stateNum(id, n, 0, P_HOVERY, P_PRESSY, P_FOCUSY))
  if id in e.enterAt:
    let spec = parseSpec(n.sProp(P_ENTER))
    let t0 = e.enterAt[id]
    result = combine(result, spec.entering(t0, e.now))
    if spec.done(t0, e.now): e.enterAt.del id
    else: (e.animating = true; e.animFull = true)
  if (n.has(P_REVEAL) or n.has(P_PARALLAX)) and not e.reducedMotion and not e.exporting and id in e.boxes:
    # scroll-linked (V1): where the node is in the part of the page that shows
    let b = e.boxes[id]
    let cl = e.clips.getOrDefault(id, b)
    let top = max(cl.y, e.scrollY)
    let bottom = min(cl.y + cl.h, e.scrollY + e.height)
    let viewH = max(1'f32, bottom - top)
    if n.has(P_REVEAL):
      let spec = parseSpec(n.sProp(P_REVEAL))
      let p = clamp((bottom - b.y) / (viewH * 0.25), 0, 1)
      result = combine(result, spec.between(curve(spec.ease, p)))
    if n.has(P_PARALLAX):
      result.y += (b.y + b.h / 2 - (top + bottom) / 2) * n.num(P_PARALLAX, 0)
  if n.has(P_ANIM_TARGET) and not e.reducedMotion:
    let l = n.loopOf
    if id notin e.loopAt: e.loopAt[id] = e.now
    let (v, going) = l.loopValue(e.loopAt[id], e.now)
    result = combine(result, poseOf(l.target, v))
    if going: (e.animating = true; e.animFull = true)

proc motionPose*(e: Engine; id: int32): Pose =
  ## What motion adds to node `id` right now (for tests and inspectors).
  e.poseOf(id, e.node(id))

proc ghostCount*(e: Engine): int = e.ghosts.len    ## removed nodes still playing their exit

# --- damage (P1): what a frame repaints --------------------------------------------------
# With `partialPaint` (a target that keeps its pixels) a frame clears and repaints only the
# damaged part of the window. Changes with a known place damage it (hover, caret, the
# boxes and props layout saw change, nodes still tweening); anything else sets `dirty`,
# which repaints everything. Ink bounds are generous: a bigger repaint is only slower.

proc union(a, b: Box): Box =
  if a.w <= 0 or a.h <= 0: return b
  if b.w <= 0 or b.h <= 0: return a
  let x = min(a.x, b.x)
  let y = min(a.y, b.y)
  Box(x: x, y: y, w: max(a.x + a.w, b.x + b.w) - x, h: max(a.y + a.h, b.y + b.h) - y)

proc damageBox*(e: Engine; b: Box) =
  ## Repaint this part of the page (page coordinates, as in `boxes`) next frame.
  if b.w <= 0 or b.h <= 0: return
  let v = Box(x: b.x, y: b.y - e.scrollY, w: b.w, h: b.h)
  e.damage = if e.hasDamage: union(e.damage, v) else: v
  e.hasDamage = true
  e.dirtyF = true

proc moves(n: tree.Node): bool =
  ## The node can draw away from its box: transforms, state scale/lift, motion, blur.
  n.has(P_SCALE) or n.has(P_ROT_Z) or n.has(P_X) or n.has(P_Y) or n.has(P_HOVERSCALE) or
    n.has(P_PRESSSCALE) or n.has(P_FOCUSSCALE) or n.has(P_HOVERY) or n.has(P_PRESSY) or n.has(P_FOCUSY) or
    n.has(P_ENTER) or n.has(P_ANIM_TARGET) or n.has(P_REVEAL) or n.has(P_PARALLAX) or n.has(P_BLUR)

proc spread(n: tree.Node; r: Box; cx, cy, pad: float32): Box =
  ## `r` as node `n`'s own transform can carry it (about its centre cx, cy), grown by `pad`.
  let s = max(1'f32, max(max(n.num(P_SCALE, 1), n.num(P_HOVERSCALE, 1)), max(n.num(P_PRESSSCALE, 1), n.num(P_FOCUSSCALE, 1))))
  var x0 = cx + (r.x - cx) * s
  var y0 = cy + (r.y - cy) * s
  var x1 = cx + (r.x + r.w - cx) * s
  var y1 = cy + (r.y + r.h - cy) * s
  if n.num(P_ROT_Z, 0) != 0:                  # any angle: the circle through the farthest corner
    let rad = sqrt(max((x0 - cx) ^ 2, (x1 - cx) ^ 2) + max((y0 - cy) ^ 2, (y1 - cy) ^ 2))
    x0 = cx - rad; x1 = cx + rad; y0 = cy - rad; y1 = cy + rad
  let dx = abs(n.num(P_X, 0)) + pad
  let dy = abs(n.num(P_Y, 0)) + max(max(abs(n.num(P_HOVERY, 0)), abs(n.num(P_PRESSY, 0))), abs(n.num(P_FOCUSY, 0))) + pad
  Box(x: x0 - dx, y: y0 - dy, w: x1 - x0 + 2 * dx, h: y1 - y0 + 2 * dy)

proc inkOf(e: Engine; id: int32; b: Box): Box =
  ## Everywhere node `id` (itself, not its children) can draw when laid out at `b`.
  let n = e.node(id)
  var pad = 8'f32 + n.num(P_BORDER_WIDTH, 0) + n.num(P_STROKEWIDTH, 0) + n.num(P_BLUR, 0) * 3
  if n.has(P_SHADOWCOLOR):
    pad += n.num(P_SHADOWBLUR, 0) * 1.5 + max(abs(n.num(P_SHADOWX, 0)), abs(n.num(P_SHADOWY, 0)))
  var r = b
  let cl = e.clips.getOrDefault(id, Box(x: -1e6, y: -1e6, w: 2e6, h: 2e6))
  if n.kind in [K_TEXT, K_BUTTON, K_CHECKBOX]:   # text can run past its box, as far as its clip
    r.x = cl.x
    r.w = cl.w
    if n.has(P_HEIGHT) or n.has(P_MAXHEIGHT):
      r.y = cl.y
      r.h = cl.h
    else:
      r.y -= n.fontSize(n.kind)
      r.h += 2 * n.fontSize(n.kind)
  result = spread(n, r, b.x + b.w / 2, b.y + b.h / 2, pad)
  var carried = false
  var p = n.parent
  while p > 0:                                # an ancestor that moves carries this node with it
    let pn = e.node(p)
    if pn.moves and p in e.boxes:
      let pb = e.boxes[p]
      result = spread(pn, result, pb.x + pb.w / 2, pb.y + pb.h / 2, 8 + pn.num(P_BLUR, 0) * 3)
      carried = true
    p = pn.parent
  if not carried: result = intersect(result, Box(x: cl.x - pad, y: cl.y - pad, w: cl.w + 2 * pad, h: cl.h + 2 * pad))

proc damageNode*(e: Engine; id: int32) =
  ## Repaint node `id` and everything under it.
  if id == 0 or (not e.s.valid(id) and id notin e.ghostBoxes):
    e.fullDamage = true
    e.dirtyF = true
    return
  if id in e.boxes: e.damageBox(e.inkOf(id, e.boxes[id]))
  for c in e.node(id).children: e.damageNode(c)

proc same(a, b: Box): bool = a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h

proc damageMoved(e: Engine; before, beforeClips: Table[int32, Box]; changed: HashSet[int32]) =
  ## After an incremental layout: repaint every node whose box or clip changed, where it was
  ## and where it is, nodes that went or came, and nodes whose props changed.
  for id, b in e.boxes:
    let was = before.getOrDefault(id, Box(w: -1))
    if was.w < 0:
      e.damageBox(e.inkOf(id, b))
    elif not same(was, b) or not same(beforeClips.getOrDefault(id), e.clips.getOrDefault(id)):
      e.damageBox(e.inkOf(id, b))
      let now = e.clips.getOrDefault(id)
      e.clips[id] = beforeClips.getOrDefault(id, now)      # its old ink, under its old clip
      e.damageBox(e.inkOf(id, was))
      e.clips[id] = now
  for id, b in before:
    if id notin e.boxes:                      # gone: its ink where it was, under its old clip
      e.clips[id] = beforeClips.getOrDefault(id, b)
      e.damageBox(e.inkOf(id, b))
      e.clips.del id
  for id in changed:
    if e.s.valid(id):
      e.damageNode(id)
      let k = e.node(id).kind              # a 3D object has no box: its scene repaints (S3D)
      if k in [K_MESH, K_LIGHT, K_CAMERA, K_MODEL, K_GROUP]:
        let sc = e.sceneOf(id)
        if sc >= 0: e.damageNode(sc)
  if e.s.bufsTouched:                      # new bulk data: every 3D view repaints
    e.s.bufsTouched = false
    for sc in e.views3d.keys: e.damageNode(sc)
  if e.fullDamage: e.hasDamage = false

proc paintGhosts(e: Engine; c: Canvas; host: int32)

proc paintTree(e: Engine; c: Canvas; id: int32; extra = still()) =
  let n = e.node(id)
  if (not n.alive and id notin e.ghostBoxes) or not n.visible: return
  if isOverlay(n.kind) and id != e.ovCurrent: return      # painted in its own pass, above the page
  if n.kind == K_GROUP:
    for k in e.zSorted(n.children): e.paintTree(c, k)
    return
  if id notin e.boxes: return
  let b = e.boxes[id]
  let cl = e.clips.getOrDefault(id, b)
  if cl.w <= 0 or cl.h <= 0: return
  if not e.exporting and (b.y > e.scrollY + e.height or b.y + b.h < e.scrollY): return   # off screen
  if e.hasDamage and not isContainer(n.kind):       # a partial frame: leaves outside the damage wait
    let ink = e.inkOf(id, b)
    if ink.x > e.damage.x + e.damage.w or ink.x + ink.w < e.damage.x or
       ink.y - e.scrollY > e.damage.y + e.damage.h or ink.y + ink.h - e.scrollY < e.damage.y: return
  let pose = combine(e.poseOf(id, n), extra)
  let op = pose.opacity
  if op <= 0.001: return
  let moved = pose.x != 0 or pose.y != 0 or pose.scale != 1 or pose.rotate != 0
  if moved:
    c.save()
    let cx = b.x + b.w / 2
    let cy = b.y + b.h / 2
    c.translate(cx + pose.x, cy + pose.y)
    if pose.rotate != 0: c.rotate(pose.rotate)
    if pose.scale != 1: c.scale(max(pose.scale, 0.001))
    c.translate(-cx, -cy)
  let hasFx = n.has(P_BLUR) or n.has(P_BACKDROPBLUR) or n.has(P_BLEND) or n.has(P_SATURATE) or
              n.has(P_BRIGHTNESS) or n.has(P_CONTRAST)
  var layers = 0
  if hasFx:                                        # effects draw the node through one layer (FX1)
    layers = c.saveFx(b.x, b.y, b.w, b.h, n.num(P_RADIUS, 0),
                      Fx(blur: n.num(P_BLUR, 0), backdrop: n.num(P_BACKDROPBLUR, 0), blend: int(n.num(P_BLEND, -1)),
                         saturate: n.num(P_SATURATE, 1), brightness: n.num(P_BRIGHTNESS, 1),
                         contrast: n.num(P_CONTRAST, 1), alpha: op))
  elif op < 0.999:
    c.saveAlpha(op)
    layers = 1
  e.paintNode(c, id)
  if e.focus == id and e.focusVisible and not isText(n.kind):
    let r = n.num(P_RADIUS, if n.kind == K_BUTTON: 8 else: 0)
    c.strokeRRect(b.x - 3, b.y - 3, b.w + 6, b.h + 6, r + 3, 2, n.col(P_FOCUSBORDER, Amber))
  if isContainer(n.kind) and n.children.len > 0:
    let clipped = n.flag(P_SCROLL) or n.flag(P_CLIP)
    if clipped:
      c.save()
      c.clipRect(b.x, b.y, b.w, b.h)
    for k in e.zSorted(n.children): e.paintTree(c, k)
    if n.alive: e.paintGhosts(c, id)
    if clipped: c.restore()
    if n.flag(P_SCROLL) and e.scrollMax.getOrDefault(id, 0) > 0:
      let mx = e.scrollMax[id]
      let th = max(24'f32, b.h * b.h / (b.h + mx))
      let ty = b.y + (b.h - th) * e.scrolls.getOrDefault(id, 0) / mx
      c.fillRRect(b.x + b.w - 5, ty + 2, 3, th - 4, 1.5, 0x44FFFFFF'u32)
  for _ in 0 ..< layers: c.restore()
  if moved: c.restore()

proc paintGhosts(e: Engine; c: Canvas; host: int32) =
  ## Removed nodes drawn inside `host` while their `exit` plays.
  for g in e.ghosts:
    if g.host == host:
      e.paintTree(c, g.id, g.spec.leaving(g.t0, e.now))
      e.animating = true
      e.animFull = true

proc dropFinishedGhosts(e: Engine) =
  var keep: seq[Ghost]
  for g in e.ghosts:
    if g.spec.done(g.t0, e.now, withDelay = false) or not e.s.valid(g.host):
      for k in g.ids:
        e.ghostBoxes.del k
        e.ghostClips.del k
        e.boxes.del k
      e.placeDirty = true
    else: keep.add g
  e.ghosts = keep

proc crashReason(msg: string): string =
  ## One readable line out of a runtime's multi-line trap report.
  for line in msg.splitLines:
    let l = line.strip
    if l.startsWith("wasm trap:"): return l[10 .. ^1].strip
  for line in msg.splitLines:
    if line.strip.len > 0: return line.strip
  "unknown error"

proc paintCrashed(e: Engine; c: Canvas) =
  c.save()
  c.scale(e.scale)
  c.fillRRect(0, 0, e.width, e.height, 0, WindowBg)
  let w = min(e.width - 48, 420'f32)
  let x = (e.width - w) / 2
  let y = max(24'f32, e.height / 2 - 70)
  c.fillRRect(x, y, w, 128, 14, 0xFF15151B'u32)
  c.strokeRRect(x, y, w, 128, 14, 1, 0xFF2C2C35'u32)
  c.drawText("This app stopped.", x + 20, y + 20, 17, Ink, 600, w - 40)
  c.drawText("It ran in its own sandbox, so nothing else was affected.", x + 20, y + 48, 13, Muted, 400, w - 40)
  c.drawText("Reason: " & crashReason(e.crashed), x + 20, y + 90, 12, Faint, 400, w - 40)
  c.restore()
  e.dirty = false

proc spellOf(e: Engine; id: int32; v: string): seq[(int, int)] =
  ## The misspelled words of field `id`'s text (checked again only when it changed).
  when defined(emscripten): return
  else:
    let c = e.spellCache.getOrDefault(id, ("\0", @[]))
    if c[0] == v: return c[1]
    result = misspelled(v)
    e.spellCache[id] = (v, result)

proc revealBox(e: Engine; id: int32) =
  ## Scrolls the scroll areas around node `id`, and the window, so its box shows.
  if id notin e.boxes: return
  var p = e.node(id).parent
  while p > 0:
    if e.node(p).flag(P_SCROLL) and p in e.boxes and e.scrollMax.getOrDefault(p, 0) > 0:
      let b = e.boxes[id]
      let pb = e.boxes[p]
      let s0 = e.scrolls.getOrDefault(p, 0)
      var s1 = s0
      if b.y < pb.y: s1 = s0 - (pb.y - b.y) - 24
      elif b.y + b.h > pb.y + pb.h: s1 = s0 + (b.y + b.h - pb.y - pb.h) + 24
      s1 = clamp(s1, 0, e.scrollMax[p])
      if s1 != s0:
        e.scrolls[p] = s1
        e.place()
        e.noteScroll(p, s1)
    p = e.node(p).parent
  let b = e.boxes.getOrDefault(id)
  if b.y < e.scrollY or b.y + b.h > e.scrollY + e.height:
    e.scrollY = clamp(b.y - e.height / 3, 0, max(0, e.contentH - e.height))
    e.noteScroll(0, e.scrollY)
  e.fullDamage = true

proc updateFind(e: Engine) =
  ## Find in page (Q3): the window's Find query over every Text node (case-insensitive), and
  ## FindIndex brought into view when it changes.
  let q = e.node(0).sProp(P_FIND).toLowerAscii
  if (q, e.s.version) != e.findKey:
    e.findKey = (q, e.s.version)
    e.findMatches.setLen(0)
    if q.len > 0:
      for k in e.paintOrder:
        let n = e.node(k)
        if n.kind != K_TEXT or not n.visible: continue
        let t = n.sProp(P_TEXT).toLowerAscii
        var at = t.find(q)
        while at >= 0:
          e.findMatches.add (k, at, at + q.len)
          at = t.find(q, at + max(1, q.len))
    e.s.findCount = int32(e.findMatches.len)
    e.findShown = -1
    e.fullDamage = true
  let want = int32(e.node(0).num(P_FINDINDEX, 0))
  e.s.findAt = want
  if want != e.findShown and want >= 0 and want < e.findMatches.len:
    e.findShown = want
    e.revealBox(e.findMatches[want][0])

proc paint*(e: Engine; c: Canvas) =
  ## Paints the viewport (layout first if the tree changed). With `partialPaint` only the
  ## damaged part is cleared and repainted; `lastDamage` says which.
  if e.crashed.len > 0:
    e.paintCrashed(c)
    return
  e.animating = false
  if e.moving: e.placeDirty = true            # a box is sliding: place it again for this frame
  e.dropFinishedGhosts()
  # what the last frame left moving, and apps inside with something new, repaint here
  if e.animFull or e.ghosts.len > 0: e.fullDamage = true
  for id in e.animIds:
    if e.s.valid(id): e.damageNode(id)
  e.animIds.setLen(0)
  e.animFull = false
  for id, ch in e.children:
    if ch.needsPaint and id in e.boxes: e.damageBox(e.inkOf(id, e.boxes[id]))
  let gen = imageGeneration()
  if gen != e.imgGen:                         # decodes finished: images that were waiting draw again
    e.imgGen = gen
    for id in e.imgWaiting:
      if e.s.valid(id): e.damageNode(id)
    e.imgWaiting.clear()
  e.ensureLayout()
  if e.crashed.len > 0:
    e.paintCrashed(c)
    return
  e.updateFind()
  let partial = e.partialPaint and not e.fullDamage and not e.exporting and e.devNote.len == 0 and not e.hasBackdrop
  var d = Box(x: 0, y: 0, w: e.width, h: e.height)
  if partial:
    if not e.hasDamage:                      # nothing that shows changed
      e.lastDamage = Box()
      e.dirtyF = false
      return
    # whole shapes: a rounded box cut by the damage edge anti-aliases a little differently
    # there, so the band takes in (once, no cascade) the boxes of the leaves it touches
    var grown = e.damage
    for id in e.paintOrder:
      if id notin e.boxes or isContainer(e.node(id).kind): continue
      let b = e.boxes[id]
      let r = Box(x: b.x - 2, y: b.y - e.scrollY - 2, w: b.w + 4, h: b.h + 4)
      let d0 = e.damage
      if r.x < d0.x + d0.w and r.x + r.w > d0.x and r.y < d0.y + d0.h and r.y + r.h > d0.y:
        grown = union(grown, r)
    e.damage = grown
    # whole device pixels, inside the window
    let x0 = max(0'f32, floor(e.damage.x * e.scale) / e.scale)
    let y0 = max(0'f32, floor(e.damage.y * e.scale) / e.scale)
    let x1 = min(e.width, ceil((e.damage.x + e.damage.w) * e.scale) / e.scale)
    let y1 = min(e.height, ceil((e.damage.y + e.damage.h) * e.scale) / e.scale)
    if x1 <= x0 or y1 <= y0:
      e.lastDamage = Box()
      e.hasDamage = false
      e.dirtyF = false
      return
    d = Box(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    e.damage = d
  e.hasDamage = partial                       # paintTree culls leaves outside `damage` while set
  let root = e.node(0)
  c.save()
  c.scale(e.scale)
  c.clipRect(d.x, d.y, d.w, d.h)
  c.fillRRect(d.x, d.y, d.w, d.h, 0, e.eased(0, root, cFill, root.col(P_COLOR, WindowBg)))
  c.translate(0, -e.scrollY)
  for k in e.zSorted(root.children): e.paintTree(c, k)
  e.paintGhosts(c, 0)
  for (id, _) in e.ovRoots:             # overlays, above the page (OV1)
    if e.node(id).kind in [K_MODAL, K_DRAWER]:
      c.fillRRect(0, e.scrollY, e.width, e.height, 0, 0x8C000000'u32)    # the window behind, dimmed
    e.ovCurrent = id
    e.paintTree(c, id)
    e.ovCurrent = 0
  if e.tipOn and not e.tipShown: e.animating = true      # keep the clock going until it shows
  c.restore()
  e.animating = e.animating or e.moving
  if e.moving: e.animFull = true
  if e.devNote.len > 0:               # hot reload: why the new build is not running
    let lines = e.devNote.strip.splitLines
    let msg = lines[0 ..< min(lines.len, 6)].join("\n")
    let (_, th) = measureText(msg, 12, 400, e.width - 40, TextStyle(family: "Consolas"))
    let h = th + 34
    c.save()
    c.scale(e.scale)
    c.fillRRect(8, e.height - h - 8, e.width - 16, h, 10, 0xF02A1414'u32)
    c.strokeRRect(8, e.height - h - 8, e.width - 16, h, 10, 1, 0xFFFF6B5E'u32)
    c.drawText("The new build did not start, so the last one keeps running:", 20, e.height - h + 2, 12,
               0xFFFF9A90'u32, 600, e.width - 40)
    c.drawText(msg, 20, e.height - h + 20, 12, 0xFFF5F5F7'u32, 400, e.width - 40, 0, TextStyle(family: "Consolas"))
    c.restore()
  if e.contentH > e.height:    # a quiet scroll indicator for the window (translucent: only over what was cleared)
    let h = max(24'f32, e.height * e.height / e.contentH)
    let y = (e.height - h) * e.scrollY / max(1, e.contentH - e.height)
    c.save()
    c.clipRect(d.x * e.scale, d.y * e.scale, d.w * e.scale, d.h * e.scale)
    c.fillRRect((e.width - 5) * e.scale, (y + 2) * e.scale, 3 * e.scale, (h - 4) * e.scale, 1.5 * e.scale, 0x55FFFFFF'u32)
    c.restore()
  e.lastDamage = d
  e.hasDamage = false
  e.fullDamage = false
  e.dirtyF = false

proc paintFrame*(e: Engine; pixels: pointer; pw, ph: int) =
  e.ensureLayout()
  let c = newCanvas(pixels, pw, ph, pw * 4)
  e.paint(c)
  c.free()

# --- hit testing ----------------------------------------------------------------------

proc inside(b: Box; x, y: float32): bool = x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h

proc hitWalk(e: Engine; id: int32; x, y: float32; best: var int32; chain: var seq[int32]) =
  ## Later siblings and higher z are on top, so they overwrite `best`.
  let n = e.node(id)
  if not n.alive or not n.visible: return
  if isOverlay(n.kind) and id != e.ovCurrent: return
  if n.kind == K_GROUP:
    for k in e.zSorted(n.children): e.hitWalk(k, x, y, best, chain)
    return
  if id notin e.boxes: return
  let b = e.boxes[id]
  let cl = e.clips.getOrDefault(id, b)
  if e.opacityOf(id, n) <= 0.001: return
  if b.inside(x, y) and cl.inside(x, y):
    chain.add id
    if e.interactive(id): best = id
  if isContainer(n.kind):
    for k in e.zSorted(n.children): e.hitWalk(k, x, y, best, chain)

proc hitAll(e: Engine; x, y: float32): (int32, seq[int32]) =
  ## The topmost interactive node under viewport point (x, y), and every node under it.
  if e.crashed.len > 0: return (-1'i32, @[])
  e.ensureLayout()
  if x < 0 or y < 0 or x >= e.width or y >= e.height: return (-1'i32, @[])
  var best = -1'i32
  var chain: seq[int32]
  let py = y + e.scrollY
  for i in countdown(e.ovRoots.high, 0):          # overlays first, the top one first (OV1)
    let id = e.ovRoots[i][0]
    let k = e.node(id).kind
    if k == K_TOOLTIP: continue
    e.ovCurrent = id
    e.hitWalk(id, x, py, best, chain)
    e.ovCurrent = 0
    if chain.len > 0: return (best, chain)
    if k in [K_MODAL, K_DRAWER]: return (-1'i32, chain)   # the dimmed window takes the click
  for k in e.zSorted(e.node(0).children): e.hitWalk(k, x, py, best, chain)
  (best, chain)

proc hitTest*(e: Engine; x, y: float32): int32 = e.hitAll(x, y)[0]

# --- input --------------------------------------------------------------------------

# --- text editing (T1) --------------------------------------------------------------

proc textOrigin(e: Engine; id: int32): (float32, float32, float32) =
  ## Where the text of input/text area `id` starts on the page (its own scroll applied)
  ## and the width it wraps at (0 = one line).
  let n = e.node(id)
  let b = e.boxes.getOrDefault(id)
  let pl = n.num(P_PAD_LEFT, 12); let pt = n.num(P_PAD_TOP, 11)
  let sc = e.textScroll.getOrDefault(id, 0)
  if n.kind == K_TEXTAREA:
    (b.x + pl, b.y + pt - sc, max(b.w - pl - n.num(P_PAD_RIGHT, 12), 1))
  elif n.rtl:                                     # right-to-left: the line ends at the right padding (P9)
    let (tw, _) = measureText(n.sProp(P_VALUE), n.fontSize(n.kind), n.fontWeight(n.kind), 0, n.textStyle)
    (b.x + b.w - n.num(P_PAD_RIGHT, 12) - tw + sc, b.y + pt, 0'f32)
  else:
    (b.x + pl - sc, b.y + pt, 0'f32)

proc textPos(e: Engine; id: int32; x, y: float32): int =
  ## The byte offset under page point (x, y) in input/text area `id`.
  let n = e.node(id)
  let (ox, oy, maxW) = e.textOrigin(id)
  textHit(n.sProp(P_VALUE), x - ox, y - oy, n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)

proc keepCaretVisible(e: Engine; id: int32) =
  ## Scrolls an input sideways, or a text area up/down, so the caret shows.
  let n = e.node(id)
  if id notin e.boxes: return
  let b = e.boxes[id]
  let v = n.sProp(P_VALUE)
  let pl = n.num(P_PAD_LEFT, 12); let pt = n.num(P_PAD_TOP, 11)
  let (_, _, maxW) = e.textOrigin(id)
  let (cx, cy, ch) = caretAt(v, clamp(e.caret, 0, v.len), n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
  var sc = e.textScroll.getOrDefault(id, 0)
  if n.kind == K_TEXTAREA:
    let view = b.h - pt - n.num(P_PAD_BOTTOM, 11)
    if cy - sc < 0: sc = cy
    elif cy + ch - sc > view: sc = cy + ch - view
  else:
    let view = b.w - pl - n.num(P_PAD_RIGHT, 12)
    if cx - sc < 0: sc = cx
    elif cx - sc > view - 2: sc = cx - view + 2
  e.textScroll[id] = max(sc, 0)

proc isWordByte(c: char): bool = c.isAlphaNumeric or c == '_' or ord(c) >= 0x80

proc wordLeft(s: string; i: int): int =
  var j = min(i, s.len)
  while j > 0 and not isWordByte(s[j - 1]): dec j
  while j > 0 and isWordByte(s[j - 1]): dec j
  j

proc wordRight(s: string; i: int): int =
  var j = max(i, 0)
  while j < s.len and not isWordByte(s[j]): inc j
  while j < s.len and isWordByte(s[j]): inc j
  j

proc selection*(e: Engine): string =
  ## The selected text in the focused input or text area.
  if e.focus < 0 or not e.s.valid(e.focus) or not isText(e.node(e.focus).kind): return ""
  let v = e.node(e.focus).sProp(P_VALUE)
  v[clamp(min(e.anchor, e.caret), 0, v.len) ..< clamp(max(e.anchor, e.caret), 0, v.len)]

proc fire(e: Engine; id: int32; event: int32) =
  let h = e.s.handlerFor(id, event)
  if h >= 0:
    when defined(yantraUnwrapTrap):
      # The catch below is what makes every wasm fault look identical from the
      # outside: it converts the trap into a message string, and the driver then
      # prints only the entry frame, `yantra_dispatch`. Compiling with
      # -d:yantraUnwrapTrap lets the trap propagate into wasmtime, which reports
      # the frame that actually faulted. This is a DIAGNOSTIC build only.
      dispatchTo(e.app, h)
    else:
      try:
        dispatchTo(e.app, h)
      except CatchableError as err:
        e.crashed = err.msg      # a trap stops this app only; its host keeps running
  e.dirtyF = true              # what the handler changed, layout finds (a crash sets fullDamage in paint)
proc childAt(e: Engine; x, y: float32): (int32, float32, float32) =
  ## The visible AppView under viewport point (x, y), and that point in its app's coordinates.
  if e.crashed.len > 0: return (-1'i32, 0'f32, 0'f32)
  e.ensureLayout()
  let (_, chain) = e.hitAll(x, y)
  for i in countdown(chain.high, 0):
    let id = chain[i]
    if id in e.children and e.node(id).kind == K_APPVIEW:
      let b = e.boxes[id]
      return (id, x - b.x, y - (b.y - e.scrollY))
  (-1'i32, 0'f32, 0'f32)

proc needsPaint*(e: Engine): bool =
  ## True when this app or any app inside it has something new to show, or is
  ## in the middle of a motion.
  if e.dirty or e.animating: return true
  if e.imgWaiting.len > 0 and imageGeneration() != e.imgGen: return true
  if e.s != nil and (e.timers.len > 0 or e.s.timers.len > 0): return true
  for _, c in e.children:
    if c.needsPaint: return true

proc hasFocus*(e: Engine): bool =
  ## True when a text input somewhere in here (or in an app inside) has the keyboard.
  e.focus >= 0 or (e.activeChild in e.children and e.children[e.activeChild].hasFocus)

proc cursorKind*(e: Engine): int =
  ## 0 default, 1 pointer, 2 text — what the mouse cursor should look like.
  if e.hoverChild in e.children: return e.children[e.hoverChild].cursorKind
  for i in countdown(e.hoverChain.high, 0):
    let n = e.node(e.hoverChain[i])
    if n.has(P_CURSOR): return int(n.num(P_CURSOR, 0))
  if e.hover < 0: 0
  elif isText(e.node(e.hover).kind): 2
  elif e.node(e.hover).kind == K_TEXT: (if e.linkAt(e.hover, e.px, e.py + e.scrollY) >= 0: 1 else: 0)
  else: 1

proc pointerMove*(e: Engine; x, y: float32) =
  e.px = x; e.py = y
  if e.selecting and e.focus >= 0 and e.s.valid(e.focus) and e.pressedChild < 0 and e.node(e.focus).flag(P_BLOCK):
    let over = e.hitTest(x, y)                     # dragged into another block: select across them (P5)
    if over >= 0 and over != e.focus and e.node(over).kind in [K_INPUT, K_TEXTAREA] and e.node(over).flag(P_BLOCK):
      if e.selA[0] < 0: e.selA = (e.focus, e.anchor)
      let pos = e.textPos(over, x, y + e.scrollY)
      if (over, pos) != e.selZ:
        e.selZ = (over, pos)
        e.dirty = true
    elif e.selA[0] >= 0 and over == e.focus:
      e.selA = (-1'i32, 0)
      e.dirty = true
  if e.selecting and e.focus >= 0 and e.s.valid(e.focus) and e.pressedChild < 0 and e.selA[0] < 0:
    let before = e.caret
    e.caret = e.textPos(e.focus, x, y + e.scrollY)
    if e.caret != before:
      e.keepCaretVisible(e.focus)
      e.caretOn = true
      e.damageNode(e.focus)
  if e.panning >= 0 and e.panning in e.zooms and e.panning in e.boxes:   # dragging a zoomed image (Q4)
    var z = e.zooms[e.panning]
    let b = e.boxes[e.panning]
    z.x = clamp(z.x + x - e.panFrom[0], b.w - b.w * z.scale, 0)
    z.y = clamp(z.y + y - e.panFrom[1], b.h - b.h * z.scale, 0)
    e.zooms[e.panning] = z
    e.panFrom = (x, y)
    e.damageNode(e.panning)
  if e.pressedChild < 0:                         # a canvas follows the pointer: dragging it, or over it
    let over = if e.pressed >= 0 and e.s.handlerFor(e.pressed, E_POINTERMOVE) >= 0: e.pressed else: e.hover
    discard e.canvasPointer(over, E_POINTERMOVE, x, y)
  if e.selDragging:
    let (t, pos) = e.textAtPoint(x, y + e.scrollY, nearest = true)
    if t >= 0 and (t, pos) != e.selZ:
      e.selZ = (t, pos)
      e.dirty = true
  let (cid, lx, ly) = e.childAt(x, y)
  if e.hoverChild != cid and e.hoverChild in e.children:
    e.children[e.hoverChild].pointerMove(-1, -1)
  e.hoverChild = cid
  let (h, chain) = e.hitAll(x, y)
  if cid >= 0:
    e.children[cid].pointerMove(lx, ly)
  var tip = -1'i32                      # the deepest node under the pointer with a tooltip
  for i in countdown(chain.high, 0):
    if e.tooltipOf(chain[i]) >= 0: (tip = chain[i]; break)
  if tip != (if e.tipOn: e.tipAnchor else: -1'i32):
    if e.tipOn and e.tipShown: e.ovDirty = true
    e.tipOn = tip >= 0
    e.tipAnchor = tip
    e.tipSince = e.now
    e.tipShown = false
    e.dirty = true
  let newHover = if cid >= 0: -1'i32 else: h
  if newHover != e.hover or chain != e.hoverChain:
    # repaint only nodes whose look depends on being under the pointer and that came or went
    for (a, b) in [(e.hoverChain, chain), (chain, e.hoverChain)]:
      for id in a:
        if id in b or not e.s.valid(id): continue
        let n = e.node(id)
        if n.kind in [K_BUTTON, K_CHECKBOX] or n.has(P_HOVERFILL) or n.has(P_HOVERCOLOR) or
           n.has(P_HOVERBORDER) or n.has(P_HOVEROPACITY) or n.has(P_HOVERSCALE) or n.has(P_HOVERY) or
           (id == e.pressed and (n.has(P_PRESSFILL) or n.has(P_PRESSCOLOR) or n.has(P_PRESSBORDER) or
            n.has(P_PRESSOPACITY) or n.has(P_PRESSSCALE) or n.has(P_PRESSY))):
          e.damageNode(id)
    e.hover = newHover
    e.hoverChain = chain
    e.dirtyF = true


  if e.draggingNode >= 0:
    for i in countdown(chain.high, 0):
      if e.s.handlerFor(chain[i], E_DRAGOVER) >= 0:
        e.fire(chain[i], E_DRAGOVER); break


# --- rich text editing (R3): runs as per-byte styles, edited, merged back -------------------

type ByteStyle = tuple[flags: int, color: uint32, size: int]

proc expandSpans(spans: string; n: int): seq[ByteStyle] =
  result = newSeq[ByteStyle](n)
  for run in spans.split(';'):
    let f = run.split(',')
    if f.len < 3: continue
    try:
      let a = clamp(parseInt(f[0]), 0, n)
      let b = clamp(parseInt(f[1]), 0, n)
      let st: ByteStyle = (parseInt(f[2]), (if f.len > 3: uint32(parseBiggestUInt(f[3])) else: 0'u32),
                           (if f.len > 4: parseInt(f[4]) else: 0))
      for i in a ..< b: result[i] = st
    except ValueError: continue           # a malformed run is skipped, the rest still apply

proc mergeSpans(styles: seq[ByteStyle]): string =
  var i = 0
  while i < styles.len:
    let st = styles[i]
    var j = i + 1
    while j < styles.len and styles[j] == st: inc j
    if st.flags != 0 or st.color != 0 or st.size != 0:
      result.add $i & "," & $j & "," & $st.flags & "," & $st.color & "," & $st.size & ";"
    i = j

proc shiftSpans*(spans: string; textLen, a, z, inserted: int): string =
  ## The runs after bytes [a, z) of a `textLen`-byte text are replaced by `inserted` bytes;
  ## new text takes the style of the byte before it (as editors do).
  if spans.len == 0: return ""
  var st = expandSpans(spans, textLen)
  let a2 = clamp(a, 0, textLen)
  let z2 = clamp(z, a2, textLen)
  let inherit: ByteStyle = if a2 > 0: st[a2 - 1] else: (0, 0'u32, 0)
  var mid = newSeq[ByteStyle](inserted)
  for i in 0 ..< inserted: mid[i] = inherit
  mergeSpans(st[0 ..< a2] & mid & st[z2 .. ^1])

proc toggleSpans*(spans: string; textLen, a, z, flag: int): string =
  ## Bold/italic/underline… over [a, z): off if all of it has it, else on.
  var st = expandSpans(spans, textLen)
  let a2 = clamp(a, 0, textLen)
  let z2 = clamp(z, a2, textLen)
  var all = z2 > a2
  for i in a2 ..< z2:
    if (st[i].flags and flag) == 0: (all = false; break)
  for i in a2 ..< z2:
    st[i].flags = if all: st[i].flags and not flag else: st[i].flags or flag
  mergeSpans(st)

proc setValue(e: Engine; id: int32; v: string) =
  e.s.setProp(id, P_VALUE, Value(kind: vkString, s: v))
  e.fire(id, E_INPUT)

proc edit(e: Engine; newValue: string; caret: int; typing = false) =
  ## Replaces the focused text's value, remembering the old one for undo. Runs of
  ## typing in one field undo together.
  let id = e.focus
  let old = e.node(id).sProp(P_VALUE)
  if newValue == old and caret == e.caret: return
  if not (typing and e.typing and e.undoStack.len > 0 and e.undoStack[^1].id == id):
    e.undoStack.add TextEdit(id: id, value: old, caret: e.caret, anchor: e.anchor, spans: e.node(id).sProp(P_SPANS))
    if e.undoStack.len > 200: e.undoStack.delete(0)
  e.redoStack.setLen(0)
  e.typing = typing
  e.caret = caret
  e.anchor = caret
  e.caretOn = true
  e.setValue(id, newValue)
  if e.s.valid(id): e.keepCaretVisible(id)

proc replaceSelection(e: Engine; s: string; typing = false) =
  let id = e.focus
  let v = e.node(id).sProp(P_VALUE)
  let a = clamp(min(e.anchor, e.caret), 0, v.len)
  let z = clamp(max(e.anchor, e.caret), 0, v.len)
  let rich = e.node(id).has(P_SPANS)
  let newSpans = if rich: shiftSpans(e.node(id).sProp(P_SPANS), v.len, a, z, s.len) else: ""
  e.edit(v[0 ..< a] & s & v[z .. ^1], a + s.len, typing)
  if rich and e.s.valid(id): e.s.setProp(id, P_SPANS, Value(kind: vkString, s: newSpans))

proc restore(e: Engine; fromStack, toStack: var seq[TextEdit]) =
  ## Undo (or redo): put a field back as it was, and remember how it is now.
  if fromStack.len == 0: return
  let t = fromStack.pop()
  if not e.s.valid(t.id): return
  toStack.add TextEdit(id: t.id, value: e.node(t.id).sProp(P_VALUE), caret: e.caret, anchor: e.anchor,
                       spans: e.node(t.id).sProp(P_SPANS))
  if e.node(t.id).has(P_SPANS): e.s.setProp(t.id, P_SPANS, Value(kind: vkString, s: t.spans))
  if e.focus != t.id:
    e.focus = t.id
  e.caret = t.caret
  e.anchor = t.anchor
  e.typing = false
  e.setValue(t.id, t.value)
  if e.s.valid(t.id): e.keepCaretVisible(t.id)

proc focusOn*(e: Engine; id: int32) =
  if e.focus != id:
    if e.focus >= 0 and e.s.valid(e.focus): e.fire(e.focus, E_BLUR)
    e.focus = id
    if id >= 0:
      e.caret = e.node(id).sProp(P_VALUE).len
      e.anchor = e.caret
      e.typing = false
      e.fire(id, E_FOCUS)
    e.caretOn = true
    e.dirty = true

proc within(e: Engine; id, top: int32): bool =
  ## Is `id` the node `top` or inside it?
  var p = id
  while p >= 0:
    if p == top: return true
    p = if p == 0: -1'i32 else: e.node(p).parent
  false

proc topOverlay(e: Engine): int32 =
  ## The open overlay that Escape and outside clicks go to (tooltips never), or -1.
  for i in countdown(e.ovRoots.high, 0):
    if e.node(e.ovRoots[i][0]).kind != K_TOOLTIP: return e.ovRoots[i][0]
  -1

proc dismiss(e: Engine; id: int32) =
  ## Closes an overlay: its onDismiss runs (the app sets `open` false or removes it); without
  ## one, the engine closes it itself until the app shows it again.
  e.ctxAt.del id
  if e.focus >= 0 and e.within(e.focus, id): e.focusOn(-1)
  if e.s.handlerFor(id, E_DISMISS) >= 0: e.fire(id, E_DISMISS)
  elif e.node(id).kind != K_CONTEXTMENU: e.ovClosed.incl id
  e.ovDirty = true
  e.dirty = true

proc closeMenuOf(e: Engine; id: int32) =
  ## Choosing an item closes the menu it is in.
  var p = id
  while p > 0:
    if e.node(p).kind in [K_MENU, K_CONTEXTMENU] and e.s.valid(p):
      e.dismiss(p)
      return
    p = e.node(p).parent

proc contextClick*(e: Engine; x, y: float32) =
  ## A right click: opens the context menu of the deepest node under the pointer that holds one,
  ## and fires ContextMenu on the deepest node that handles it.
  let (cid, lx, ly) = e.childAt(x, y)
  if cid >= 0:
    e.children[cid].contextClick(lx, ly)
    e.dirty = true
    return
  if e.spellClick(x, y): return
  e.ctxAt.clear()
  e.tipOn = false
  let (_, chain) = e.hitAll(x, y)
  var opened, fired = false
  for i in countdown(chain.high, 0):
    let id = chain[i]
    if not opened:
      var menu = -1'i32
      proc find(e: Engine; id: int32; menu: var int32) =
        for c in e.node(id).children:
          let cn = e.node(c)
          if not cn.alive: continue
          if cn.kind == K_CONTEXTMENU: (menu = c; return)
          if cn.kind == K_GROUP: e.find(c, menu)
      e.find(id, menu)
      if menu >= 0:
        e.ovClosed.excl menu
        e.ctxAt[menu] = (x, y + e.scrollY)
        opened = true
    if not fired and e.s.handlerFor(id, E_CONTEXTMENU) >= 0:
      e.fire(id, E_CONTEXTMENU)
      fired = true
  e.ovDirty = true
  e.dirty = true
proc selectable(n: tree.Node): bool =
  ## Read-only Text, and block fields (P5): what one selection can run across.
  n.kind == K_TEXT or (n.kind in [K_INPUT, K_TEXTAREA] and n.flag(P_BLOCK))
proc selText(n: tree.Node): string = (if n.kind == K_TEXT: n.sProp(P_TEXT) else: n.sProp(P_VALUE))

proc textOrder(e: Engine; id: int32): int =
  ## Where Text node `id` comes in document order (-1: not laid out).
  var i = 0
  for k in e.paintOrder:
    if e.node(k).selectable:
      if k == id: return i
      inc i
  -1

proc textAtPoint(e: Engine; x, y: float32; nearest: bool): (int32, int) =
  ## The Text node and byte under page point (x, y). `nearest`: when over none, the end of
  ## the last Text above the point (a drag between lines), else (-1, 0).
  var best = -1'i32
  var above = -1'i32
  for k in e.paintOrder:
    let n = e.node(k)
    if n.kind != K_TEXT or not n.visible or k notin e.boxes: continue
    let b = e.boxes[k]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h: best = k
    elif b.y <= y: above = k
  if best < 0 and nearest and above >= 0:
    let b = e.boxes[above]
    let n = e.node(above)
    if y < b.y + b.h:                               # beside it on its own line
      let p = textHit(n.sProp(P_TEXT), x - b.x, y - b.y, n.fontSize(K_TEXT), n.fontWeight(K_TEXT), b.w, n.textStyle)
      return (above, p)
    return (above, n.sProp(P_TEXT).len)
  if best < 0: return (-1'i32, 0)
  let b = e.boxes[best]
  let n = e.node(best)
  (best, textHit(n.sProp(P_TEXT), x - b.x, y - b.y, n.fontSize(K_TEXT), n.fontWeight(K_TEXT), b.w, n.textStyle))

proc selRange(e: Engine): ((int, int32, int), (int, int32, int)) =
  ## The selection's two ends as (order, node, byte), first one first.
  let a = (e.textOrder(e.selA[0]), e.selA[0], e.selA[1])
  let z = (e.textOrder(e.selZ[0]), e.selZ[0], e.selZ[1])
  if a[0] < z[0] or (a[0] == z[0] and a[2] <= z[2]): (a, z) else: (z, a)

proc selBytes(e: Engine; id: int32): (int, int) =
  ## The selected bytes of Text node `id` ((0, 0): none).
  if e.selA[0] < 0 or not e.s.valid(e.selA[0]) or not e.s.valid(e.selZ[0]): return
  let (a, z) = e.selRange
  let o = e.textOrder(id)
  if o < a[0] or o > z[0] or a[0] < 0: return
  let len = e.node(id).selText.len
  let s0 = if o == a[0]: clamp(a[2], 0, len) else: 0
  let s1 = if o == z[0]: clamp(z[2], 0, len) else: len
  (s0, s1)

proc textSelection*(e: Engine): string =
  ## The selected read-only text, one line per Text node it spans.
  if e.selA[0] < 0: return
  var first = true
  for k in e.paintOrder:
    if not e.node(k).selectable: continue
    let (s0, s1) = e.selBytes(k)
    if s1 > s0:
      if not first: result.add "\n"
      result.add e.node(k).selText[s0 ..< s1]
      first = false

proc pointerDown*(e: Engine; x, y: float32) =
  e.tipOn = false
  let ov = e.topOverlay                  # a click outside the top overlay dismisses it (and stops there)
  if ov >= 0 and ov in e.boxes and not e.boxes[ov].inside(x, y + e.scrollY):
    let n = e.node(ov)
    if not n.has(P_CLOSEONCLICKOUTSIDE) or n.flag(P_CLOSEONCLICKOUTSIDE):
      e.dismiss(ov)
      e.pressed = -1
      return
    if n.kind in [K_MODAL, K_DRAWER]:
      e.pressed = -1
      return
  let (cid, lx, ly) = e.childAt(x, y)
  if e.activeChild != cid and e.activeChild in e.children:
    e.children[e.activeChild].focusOn(-1)     # the app that had the keyboard loses it
  e.activeChild = cid
  e.pressedChild = cid
  if cid >= 0:
    e.focusOn(-1)
    e.children[cid].pointerDown(lx, ly)
    e.dirty = true
    return
  e.pressed = e.hitTest(x, y)
  let n = e.pressed
  e.focusVisible = false
  discard e.canvasPointer(n, E_POINTERDOWN, x, y)
  e.panning = -1
  if n >= 0 and e.node(n).kind == K_IMAGE and e.node(n).flag(P_ZOOMABLE):
    if e.lastClickNode == n and e.now - e.lastClickAt < 450:   # double click: 2x there, or back to 1x
      if n in e.zooms: (e.zooms.del n; e.damageNode(n)) else: e.zoomAt(n, 2, x, y)
      e.lastClickNode = -1
    else:
      e.lastClickNode = n
      e.lastClickAt = e.now
    if n in e.zooms:
      e.panning = n
      e.panFrom = (x, y)
  if n >= 0 and e.s.handlerFor(n, E_DRAGSTART) >= 0:
    e.draggingNode = n
    e.dragData = ""
    e.fire(n, E_DRAGSTART)

  if n >= 0 and isText(e.node(n).kind):
    let extend = e.shiftHeld and e.focus == n
    e.focusOn(n)
    let v = e.node(n).sProp(P_VALUE)
    let pos = e.textPos(n, x, y + e.scrollY)
    if e.lastClickNode == n and e.now - e.lastClickAt < 450: inc e.clicks
    else: e.clicks = 1
    e.lastClickNode = n
    e.lastClickAt = e.now
    if e.clicks == 2:                    # a word
      e.anchor = wordLeft(v, min(pos + 1, v.len))
      e.caret = wordRight(v, e.anchor)
    elif e.clicks >= 3:                  # everything
      e.anchor = 0
      e.caret = v.len
    else:
      e.caret = pos
      if not extend: e.anchor = pos
    e.typing = false
    e.selecting = true
  elif n < 0 or not isText(e.node(n).kind):
    e.focusOn(-1)
  # read-only text: a press on a Text (not on something clickable) starts a selection
  e.selA = (-1'i32, 0)
  e.selZ = e.selA
  if n < 0 or not e.interactive(n):
    let (t, pos) = e.textAtPoint(x, y + e.scrollY, nearest = false)
    if t >= 0:
      let v = e.node(t).sProp(P_TEXT)
      if e.lastClickNode == t and e.now - e.lastClickAt < 450: inc e.clicks
      else: e.clicks = 1
      e.lastClickNode = t
      e.lastClickAt = e.now
      if e.clicks == 2: e.selA = (t, wordLeft(v, min(pos + 1, v.len))); e.selZ = (t, wordRight(v, e.selA[1]))
      elif e.clicks >= 3: e.selA = (t, 0); e.selZ = (t, v.len)
      else: e.selA = (t, pos); e.selZ = e.selA
      e.selDragging = true
  e.dirty = true

proc linkAt(e: Engine; id: int32; x, y: float32): int =
  ## The index of the link (Links "start,end;…") under page point (x, y) in Text `id`, or -1.
  if id < 0 or not e.s.valid(id) or e.node(id).kind != K_TEXT or not e.node(id).has(P_LINKS) or id notin e.boxes: return -1
  let n = e.node(id)
  let b = e.boxes[id]
  if x < b.x or y < b.y or x >= b.x + b.w or y >= b.y + b.h: return -1
  let t = n.sProp(P_TEXT)
  let at = textHit(t, x - b.x, y - b.y, n.fontSize(K_TEXT), n.fontWeight(K_TEXT), b.w, n.textStyle)
  # the hit is the nearest caret place: a link covers it if the byte after or before it is inside
  let parts = n.sProp(P_LINKS).split(';')
  for i in 0 ..< parts.len:
    let f = parts[i].split(',')
    if f.len < 2: continue
    var a, z: int
    if parseInt(f[0].strip, a) == 0 or parseInt(f[1].strip, z) == 0: continue
    if at >= a and at < z or (at == z and at > a and at > 0):
      for (rx, ry, rw, rh) in textRects(t, a, z, n.fontSize(K_TEXT), n.fontWeight(K_TEXT), b.w, n.textStyle):
        if x >= b.x + rx and x < b.x + rx + rw and y >= b.y + ry and y < b.y + ry + rh: return i
  -1

proc canvasPointer(e: Engine; id: int32; ev: int32; x, y: float32): bool =
  ## A pointer event for a canvas node, at its own px (P7). True if it had a handler.
  if id < 0 or not e.s.valid(id) or e.s.handlerFor(id, ev) < 0: return false
  let b = e.boxes.getOrDefault(id)
  e.s.pointerAt = (x - b.x, y + e.scrollY - b.y)
  e.s.pointerPage = (x, y + e.scrollY)
  e.fire(id, ev)
  true

proc pointerUp*(e: Engine; x, y: float32) =
  e.selDragging = false
  e.panning = -1
  if e.pressedChild < 0 and e.pressed >= 0 and e.s.handlerFor(e.pressed, E_LINKCLICK) >= 0:
    let li = e.linkAt(e.pressed, x, y + e.scrollY)
    if li >= 0 and li == e.linkAt(e.pressed, e.px, e.py + e.scrollY):
      e.s.linkHit = int32(li)
      e.fire(e.pressed, E_LINKCLICK)
  if e.pressedChild < 0: discard e.canvasPointer(e.pressed, E_POINTERUP, x, y)
  if e.pressedChild >= 0:
    let pc = e.pressedChild
    e.pressedChild = -1
    if pc in e.children and pc in e.boxes:
      let b = e.boxes[pc]
      e.children[pc].pointerUp(x - b.x, y - (b.y - e.scrollY))
    e.dirty = true
    return
  e.selecting = false
  if e.draggingNode >= 0:
    e.draggingNode = -1
    let (_, chain) = e.hitAll(x, y)
    for i in countdown(chain.high, 0):
      if e.s.handlerFor(chain[i], E_DROP) >= 0:
        e.s.dropData = e.dragData
        e.s.dropName = ""
        e.fire(chain[i], E_DROP)
        e.s.dropData = ""
        break
  if e.pick3d(x, y): (e.pressed = -1; e.dirty = true; return)   # a click on a 3D object (T3D)
  let target = e.hitTest(x, y)
  let p = e.pressed
  e.pressed = -1
  e.dirty = true
  if p < 0 or p != target: return
  if e.node(p).has(P_WINDOWACTION) and windowAction != nil:   # a title-bar button (Q8)
    windowAction(int(e.node(p).num(P_WINDOWACTION, 0)))
  let k = e.node(p).kind
  if k == K_CHECKBOX:
    e.fire(p, E_CHANGE)
    e.fire(p, E_CLICK)
  elif not isText(k):
    e.fire(p, E_CLICK)
    if e.s.valid(p): e.closeMenuOf(p)
  if e.focus >= 0 and not e.s.valid(e.focus): e.focus = -1   # the app removed it
  e.pointerMove(x, y)

proc noteScroll(e: Engine; id: int32; y: float32) =
  ## Tells a node with a Scroll handler its new offset (lazy lists build what shows).
  if e.s.handlerFor(id, E_SCROLL) >= 0 and e.s.scrollOf.getOrDefault(id, -1) != y:
    e.s.scrollOf[id] = y
    e.fire(id, E_SCROLL)

proc zoomAt*(e: Engine; id: int32; factor, x, y: float32) =
  ## Zooms image `id` by `factor` about window point (x, y), 1x to 8x (pinch or Ctrl+wheel).
  if id notin e.boxes: return
  let b = e.boxes[id]
  var z = e.zooms.getOrDefault(id, Zoom(scale: 1))
  let ns = clamp(z.scale * factor, 1, 8)
  let px = x - b.x
  let py = y + e.scrollY - b.y
  # the point under the pointer stays under it: (p - shift) / scale is the same image point
  z.x = px - (px - z.x) * ns / z.scale
  z.y = py - (py - z.y) * ns / z.scale
  z.scale = ns
  z.x = clamp(z.x, b.w - b.w * ns, 0)
  z.y = clamp(z.y, b.h - b.h * ns, 0)
  if ns <= 1.001: e.zooms.del id else: e.zooms[id] = z
  e.damageNode(id)

proc scrollOfId(e: Engine; id: int32): float32 = (if id == 0: e.scrollY else: e.scrolls.getOrDefault(id, 0))
proc scrollMaxOf(e: Engine; id: int32): float32 =
  if id == 0: max(0'f32, e.contentH - e.height) else: e.scrollMax.getOrDefault(id, 0)

proc setScroll*(e: Engine; id: int32; y: float32) =
  ## Moves a scroll area (0 = the window) to `y` now: places, repaints, tells the app.
  let y = clamp(y, 0, e.scrollMaxOf(id))
  if y == e.scrollOfId(id): return
  if id == 0:
    e.scrollY = y
    e.dirty = true
  else:
    e.scrolls[id] = y
    e.placeDirty = true
    if id in e.boxes: e.damageBox(e.inkOf(id, e.boxes[id])) else: e.dirty = true
  e.noteScroll(id, y)

proc scrollBy(e: Engine; id: int32; dy: float32; precise: bool) =
  let d = -dy * 48
  if precise:
    e.setScroll(id, e.scrollOfId(id) + d)
    if e.kinetic:                                   # remember how fast the fingers went
      var g = e.glides.getOrDefault(id, Glide(target: NaN, lastInput: e.now))
      let dt = max(8'f32, float32(e.now - g.lastInput))
      g.vel = if g.target == g.target: d / dt else: g.vel * 0.5 + (d / dt) * 0.5
      g.target = NaN
      g.lastInput = e.now
      e.glides[id] = g
  elif e.smoothScroll and not e.reducedMotion:
    let g = e.glides.getOrDefault(id, Glide(target: NaN))
    let base = if g.target == g.target: g.target else: e.scrollOfId(id)
    e.glides[id] = Glide(target: clamp(base + d, 0, e.scrollMaxOf(id)), lastInput: e.now)
  else:
    e.setScroll(id, e.scrollOfId(id) + d)

proc scrollTo*(e: Engine; id: int32; y: float32; animated = true) =
  ## Scrolls area `id` (0 = the window) to `y`, gliding there unless `animated` is false
  ## or motion is reduced (Q4).
  if not animated or e.reducedMotion: (e.glides.del id; e.setScroll(id, y); return)
  e.glides[id] = Glide(target: clamp(y, 0, e.scrollMaxOf(id)), lastInput: e.now)

proc stepGlides(e: Engine) =
  ## Each tick: gliding areas close in on their target (ease-out), coasting ones slow down.
  let dt = float32(clamp(e.now - e.lastTick, 0, 100))
  e.lastTick = e.now
  if e.glides.len == 0 or dt <= 0: return
  var done: seq[int32]
  for id, g in e.glides.mpairs:
    let cur = e.scrollOfId(id)
    if g.target == g.target:                       # a target: 1 - e^(-dt/70) of the way each tick
      let nxt = cur + (g.target - cur) * (1 - exp(-dt / 70))
      if abs(g.target - nxt) < 0.5: (e.setScroll(id, g.target); done.add id)
      else: e.setScroll(id, nxt)
    elif e.now - g.lastInput > 40:                 # fingers lifted: coast, friction ~325 ms
      g.vel *= exp(-dt / 325)
      let nxt = cur + g.vel * dt
      e.setScroll(id, nxt)
      if abs(g.vel) < 0.02 or e.scrollOfId(id) != clamp(nxt, 0, e.scrollMaxOf(id)): done.add id
  for id in done: e.glides.del id
  if e.glides.len > 0: e.dirtyF = true             # keep frames coming

proc wheel*(e: Engine; dy: float32; dx = 0'f32; precise = false; ctrl = false) =
  ## A wheel or touchpad scroll, in lines (48 px). `precise`: a touchpad's small deltas,
  ## applied at once (and coasting on with `kinetic`); notches glide with `smoothScroll`.
  ## Ctrl+wheel over a zoomable image zooms it (Q4).
  let (cid, _, _) = e.childAt(e.px, e.py)
  if cid >= 0:
    e.children[cid].wheel(dy, dx, precise, ctrl)
    return
  if ctrl:
    let h = e.hitTest(e.px, e.py)
    if h >= 0 and e.node(h).kind == K_IMAGE and e.node(h).flag(P_ZOOMABLE):
      e.zoomAt(h, pow(1.12'f32, dy), e.px, e.py)
      return
  e.ensureLayout()
  # the innermost scroll container under the pointer that can still move, else the window
  let (_, chain) = e.hitAll(e.px, e.py)
  for i in countdown(chain.high, 0):
    let id = chain[i]
    let cn = e.node(id)
    if cn.kind == K_CANVAS and e.s.handlerFor(id, E_SCROLL) >= 0 and id in e.boxes:
      # a canvas scrolls its own content (P8: a sheet draws only what shows): canvasWidth/Height say how far
      let b = e.boxes[id]
      let y0 = e.s.scrollOf.getOrDefault(id, 0)
      let x0 = e.s.scrollXOf.getOrDefault(id, 0)
      let y1 = clamp(y0 - dy * 48, 0, max(0'f32, cn.num(P_CANVASHEIGHT, b.h) - b.h))
      let x1 = clamp(x0 - dx * 48, 0, max(0'f32, cn.num(P_CANVASWIDTH, b.w) - b.w))
      if y1 != y0 or x1 != x0:
        e.s.scrollOf[id] = y1
        e.s.scrollXOf[id] = x1
        e.fire(id, E_SCROLL)
        return
    if cn.flag(P_SCROLL) and e.scrollMax.getOrDefault(id, 0) > 0:
      let base = if id in e.glides and e.glides[id].target == e.glides[id].target: e.glides[id].target else: e.scrolls.getOrDefault(id, 0)
      if clamp(base - dy * 48, 0, e.scrollMax[id]) != e.scrolls.getOrDefault(id, 0):
        e.scrollBy(id, dy, precise)
        e.atEnd[id] = clamp(base - dy * 48, 0, e.scrollMax[id]) >= e.scrollMax[id] - 1   # away from the end: stop sticking
        return
  e.scrollBy(0, dy, precise)

proc typeText*(e: Engine; s: string) =
  if e.activeChild in e.children:
    e.children[e.activeChild].typeText(s)
    return
  e.preeditText = ""                   # the input method committed its word
  if e.focus < 0 or not e.s.valid(e.focus) or not isText(e.node(e.focus).kind): return
  e.replaceSelection(s, typing = true)

proc prevRune(s: string; i: int): int =
  var j = i - 1
  while j > 0 and (ord(s[j]) and 0xC0) == 0x80: dec j
  max(j, 0)

proc focusable(e: Engine; id: int32): bool =
  let n = e.node(id)
  n.alive and n.visible and (n.kind in [K_INPUT, K_TEXTAREA, K_BUTTON, K_CHECKBOX] or
                             e.s.handlerFor(id, E_CLICK) >= 0)

# --- game input (G-IN): what is held, raw movement, gamepads, and a Frame event per frame ---

proc keyUp*(e: Engine; code: int32) = e.s.keysHeld.excl code
proc rawMotion*(e: Engine; dx, dy: float32) =
  ## Raw pointer movement (logical px), summed until the next Frame event reads it.
  e.s.mouseDX += dx
  e.s.mouseDY += dy
proc mouseButton*(e: Engine; button: int; down: bool) =
  ## Which mouse buttons are held (1 left, 2 middle, 3 right), for games.
  let bit = 1'i32 shl (button - 1)
  e.s.buttonsHeld = if down: e.s.buttonsHeld or bit else: e.s.buttonsHeld and not bit
proc setGamepad*(e: Engine; on: bool; axes: array[6, float32]; buttons: int32) =
  e.s.padOn = on
  e.s.padAxes = axes
  e.s.padButtons = if on: buttons else: 0
proc gamepadOn*(e: Engine): bool = e.s.padOn
proc pointerLocked*(e: Engine): bool = e.s.nodes.len > 0 and e.node(0).flag(P_POINTERLOCK)
  ## The window asks for pointer lock (the runner holds the pointer while it does).
proc wantsFrames*(e: Engine): bool =
  ## An app with an onFrame handler wants every display frame (games, simulations).
  for k in e.s.events.keys:
    if k[1] == E_FRAME and e.s.valid(k[0]): return true

proc frameEvent(e: Engine) =
  ## Every Frame handler runs once, with the time since the last frame and the input since.
  var ids: seq[int32]
  for k in e.s.events.keys:
    if k[1] == E_FRAME and e.s.valid(k[0]): ids.add k[0]
  if ids.len == 0: return
  e.s.frameDt = if e.lastFrameAt > 0: float32((e.now - e.lastFrameAt) / 1000) else: 1'f32 / 60
  e.lastFrameAt = e.now
  e.s.pointerLocked = e.pointerLocked
  for id in ids:
    if e.crashed.len > 0: break
    e.fire(id, E_FRAME)
  e.s.mouseDX = 0
  e.s.mouseDY = 0

proc key*(e: Engine; code: int32; mods = 0'i32) =
  ## Keys: Tab / Shift+Tab move focus; Enter or Space press the focused button; in a
  ## text field, editing, caret and selection moves (Shift extends, Ctrl goes by word),
  ## Ctrl+A/C/X/V/Z/Y, and Enter (a new line in a text area, submit in an input).
  e.s.keysHeld.incl code
  const
    Backspace = 8'i32
    Tab = 9'i32
    Enter = 13'i32
    Escape = 27'i32
    Space = 32'i32
    Del = 127'i32
    Right = 0x4000004f'i32
    Left = 0x40000050'i32
    Down = 0x40000051'i32
    Up = 0x40000052'i32
    Home = 0x4000004a'i32
    End = 0x4000004d'i32
    KpEnter = 0x40000058'i32
  if e.activeChild in e.children:
    e.children[e.activeChild].key(code, mods)
    return
  let shift = (mods and 0x0003) != 0
  let ctrl = (mods and 0x0CC0) != 0             # Ctrl, or Cmd on a Mac
  e.shiftHeld = shift
  e.dirty = true
  var at = if e.focus >= 0 and e.s.valid(e.focus): e.focus else: 0'i32   # the app first (KEY1):
  while at >= 0:                                                         # Key handlers from the focus out
    if e.s.handlerFor(at, E_KEY) >= 0:
      e.s.keyCode = code
      e.s.keyMods = mods
      e.s.keyHandled = false
      e.fire(at, E_KEY)
      if e.s.keyHandled or e.crashed.len > 0: return
    at = if at == 0: -1'i32 else: e.node(at).parent
  let ov = e.topOverlay
  if code == Escape and ov >= 0:
    if not e.node(ov).has(P_CLOSEONESC) or e.node(ov).flag(P_CLOSEONESC): e.dismiss(ov)
    return
  if ctrl and code == int32(ord('c')) and e.selA[0] >= 0 and (e.focus < 0 or e.selA[0] != e.selZ[0]):
    clipboardSet(e.textSelection)                # read-only text (P4)
    return
  var code = code
  if e.focus >= 0 and e.s.valid(e.focus) and e.node(e.focus).rtl:   # right-to-left: arrows move the way they point (P9)
    if code == Left: code = Right
    elif code == Right: code = Left
  if code == Tab and not ctrl:
    var order: seq[int32]
    let trap = if ov >= 0 and e.node(ov).kind in [K_MODAL, K_DRAWER]: ov else: -1'i32   # focus stays inside
    for id in e.paintOrder:
      if e.focusable(id) and (trap < 0 or e.within(id, trap)): order.add id
    if order.len > 0:
      let i = order.find(e.focus)
      let next = if i < 0: (if shift: order.high else: 0)
                 else: (i + (if shift: -1 else: 1) + order.len) mod order.len
      e.focusOn(order[next])
      e.focusVisible = true
      if isText(e.node(order[next]).kind):
        e.anchor = 0                        # Tab into a field selects its text
        e.caret = e.node(order[next]).sProp(P_VALUE).len
    return
  if e.focus < 0 or not e.s.valid(e.focus): return
  let n = e.node(e.focus)
  if code == Escape:
    e.focusOn(-1)
    return
  if not isText(n.kind):                    # a focused button, checkbox or clickable row
    if code in [Enter, KpEnter, Space]:
      let f = e.focus
      if n.kind == K_CHECKBOX: e.fire(f, E_CHANGE)
      e.fire(f, E_CLICK)
      if e.s.valid(f): e.closeMenuOf(f)
    return
  let v = n.sProp(P_VALUE)
  e.caret = clamp(e.caret, 0, v.len)
  e.anchor = clamp(e.anchor, 0, v.len)
  let hasSel = e.anchor != e.caret
  e.caretOn = true
  proc moveTo(e: Engine; pos: int) =
    e.caret = clamp(pos, 0, v.len)
    if not shift: e.anchor = e.caret
    e.typing = false
    e.keepCaretVisible(e.focus)
  proc lineMove(e: Engine; dy: float32): int =
    ## The position one line up (-1) or down (+1) in a text area, keeping the column.
    let (_, _, maxW) = e.textOrigin(e.focus)
    let (cx, cy, ch) = caretAt(v, e.caret, n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
    textHit(v, cx, cy + ch / 2 + dy * ch, n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
  proc lineEdge(e: Engine; right: bool): int =
    let (_, _, maxW) = e.textOrigin(e.focus)
    let (_, cy, ch) = caretAt(v, e.caret, n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
    textHit(v, if right: 1e6 else: -1e6, cy + ch / 2, n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
  if ctrl:
    case code
    of int32(ord('a')):
      e.anchor = 0
      e.caret = v.len
    of int32(ord('b')), int32(ord('i')), int32(ord('u')):
      if n.has(P_SPANS) and hasSel:          # rich text: style the selection (undoable)
        let flag = if code == int32(ord('b')): 1 elif code == int32(ord('i')): 2 else: 4
        let a = min(e.anchor, e.caret)
        let z = max(e.anchor, e.caret)
        let before = n.sProp(P_SPANS)
        e.undoStack.add TextEdit(id: e.focus, value: v, caret: e.caret, anchor: e.anchor, spans: before)
        e.redoStack.setLen(0)
        e.typing = false
        e.s.setProp(e.focus, P_SPANS, Value(kind: vkString, s: toggleSpans(before, v.len, a, z, flag)))
        e.fire(e.focus, E_INPUT)
        e.dirty = true
    of int32(ord('c')):
      if hasSel: clipboardSet(e.selection)
    of int32(ord('x')):
      if hasSel:
        clipboardSet(e.selection)
        e.replaceSelection("")
    of int32(ord('v')):
      var t = clipboardGet()
      if n.kind == K_INPUT: t = t.replace("\r", "").replace("\n", " ")
      else: t = t.replace("\r\n", "\n")
      if t.len > 0: e.replaceSelection(t)
    of int32(ord('z')), int32(ord('y')):
      let redo = code == int32(ord('y')) or shift
      if e.s.handlerFor(e.focus, E_COMMAND) >= 0:   # the app keeps the history (blocks, Q6)
        e.s.command = if redo: 2 else: 1
        e.fire(e.focus, E_COMMAND)
      elif redo: e.restore(e.redoStack, e.undoStack)
      else: e.restore(e.undoStack, e.redoStack)
    of Left: e.moveTo(wordLeft(v, e.caret))
    of Right: e.moveTo(wordRight(v, e.caret))
    of Home: e.moveTo(0)
    of End: e.moveTo(v.len)
    of Backspace:
      if hasSel: e.replaceSelection("")
      else: e.edit(v[0 ..< wordLeft(v, e.caret)] & v[e.caret .. ^1], wordLeft(v, e.caret))
    of Del:
      if hasSel: e.replaceSelection("")
      else: e.edit(v[0 ..< e.caret] & v[wordRight(v, e.caret) .. ^1], e.caret)
    of Enter, KpEnter: e.fire(e.focus, E_SUBMIT)
    else: e.dirty = false
    return
  if n.flag(P_BLOCK) and e.blockKey(code, shift, v): return
  if not shift: e.selA = (-1'i32, 0)             # a key in one block ends a selection across blocks
  case code
  of Backspace:
    if hasSel: e.replaceSelection("")
    elif e.caret > 0:
      let p = prevRune(v, e.caret)
      e.edit(v[0 ..< p] & v[e.caret .. ^1], p)
  of Del:
    if hasSel: e.replaceSelection("")
    elif e.caret < v.len:
      let q = e.caret + max(1, v.runeLenAt(e.caret))
      e.edit(v[0 ..< e.caret] & v[q .. ^1], e.caret)
  of Left:
    if hasSel and not shift: e.moveTo(min(e.anchor, e.caret))
    else: e.moveTo(prevRune(v, e.caret))
  of Right:
    if hasSel and not shift: e.moveTo(max(e.anchor, e.caret))
    elif e.caret < v.len: e.moveTo(e.caret + max(1, v.runeLenAt(e.caret)))
    else: e.moveTo(e.caret)
  of Up:
    if n.kind == K_TEXTAREA: e.moveTo(e.lineMove(-1)) else: e.moveTo(0)
  of Down:
    if n.kind == K_TEXTAREA: e.moveTo(e.lineMove(1)) else: e.moveTo(v.len)
  of Home:
    if n.kind == K_TEXTAREA: e.moveTo(e.lineEdge(false)) else: e.moveTo(0)
  of End:
    if n.kind == K_TEXTAREA: e.moveTo(e.lineEdge(true)) else: e.moveTo(v.len)
  of Enter, KpEnter:
    if n.kind == K_TEXTAREA:
      e.replaceSelection("\n")
    else:
      e.fire(e.focus, E_SUBMIT)
      if e.focus >= 0 and e.s.valid(e.focus):
        e.caret = min(e.caret, e.node(e.focus).sProp(P_VALUE).len)
        e.anchor = e.caret
      else: e.focus = -1
  else: e.dirty = false

proc blockNeighbour(e: Engine; id: int32; dir: int): int32 =
  ## The block field before (dir -1) or after (1) `id` in document order, or -1.
  let i = e.paintOrder.find(id)
  if i < 0: return -1
  var k = i + dir
  while k >= 0 and k < e.paintOrder.len:
    let c = e.paintOrder[k]
    let cn = e.node(c)
    if cn.alive and cn.kind in [K_INPUT, K_TEXTAREA] and cn.flag(P_BLOCK): return c
    k += dir
  -1

proc blockKey(e: Engine; code: int32; shift: bool; v: string): bool =
  ## P5: Up/Down past a block's first/last line go to the block before/after (Shift: select
  ## across them); Enter splits (BlockSplit), Backspace at the start merges (BlockMerge) —
  ## the app edits its seq of blocks; the engine then puts the caret where it belongs.
  ## True if the key was used.
  const
    Backspace = 8'i32
    Enter = 13'i32
    KpEnter = 0x40000058'i32
    Down = 0x40000051'i32
    Up = 0x40000052'i32
  let id = e.focus
  let n = e.node(id)
  let size = n.fontSize(n.kind)
  let wt = n.fontWeight(n.kind)
  let (ox, oy, maxW) = e.textOrigin(id)
  let (cx, cy, ch) = caretAt(v, clamp(e.caret, 0, v.len), size, wt, maxW, n.textStyle)
  case code
  of Up, Down:
    let (_, ly, _) = caretAt(v, v.len, size, wt, maxW, n.textStyle)
    let up = code == Up
    if not ((up and cy < ch * 0.5) or (not up and cy >= ly - ch * 0.5)): return false
    let nb = e.blockNeighbour(id, if up: -1 else: 1)
    if nb < 0: return false
    if shift and e.selA[0] < 0: e.selA = (id, e.anchor)
    elif not shift: e.selA = (-1'i32, 0)
    let nn = e.node(nb)
    let (nox, noy, nmaxW) = e.textOrigin(nb)
    let nv = nn.sProp(P_VALUE)
    let (_, nly, nlh) = caretAt(nv, nv.len, nn.fontSize(nn.kind), nn.fontWeight(nn.kind), nmaxW, nn.textStyle)
    let targetY = if up: nly + nlh / 2 else: nlh / 2      # its last line going up, its first going down
    let pos = textHit(nv, ox + cx - nox, targetY, nn.fontSize(nn.kind), nn.fontWeight(nn.kind), nmaxW, nn.textStyle)
    e.focusOn(nb)
    e.caret = pos
    e.anchor = pos
    if shift: e.selZ = (nb, pos)
    e.keepCaretVisible(nb)
    true
  of Enter, KpEnter:
    if shift or e.s.handlerFor(id, E_BLOCKSPLIT) < 0: return false   # Shift+Enter: a line break in a text area
    e.s.blockCaret = int32(clamp(e.caret, 0, v.len))
    e.selA = (-1'i32, 0)
    e.fire(id, E_BLOCKSPLIT)
    e.ensureLayout()
    let nb = e.blockNeighbour(id, 1)
    if nb >= 0:
      e.focusOn(nb)
      e.caret = 0
      e.anchor = 0
    true
  of Backspace:
    if e.caret != 0 or e.anchor != 0 or e.s.handlerFor(id, E_BLOCKMERGE) < 0: return false
    let prev = e.blockNeighbour(id, -1)
    if prev < 0: return false
    let joinAt = e.node(prev).sProp(P_VALUE).len          # the caret goes where the two meet
    e.s.blockCaret = 0
    e.selA = (-1'i32, 0)
    e.fire(id, E_BLOCKMERGE)
    e.ensureLayout()
    if e.s.valid(prev):
      e.focusOn(prev)
      e.caret = min(joinAt, e.node(prev).sProp(P_VALUE).len)
      e.anchor = e.caret
    true
  else: false

proc preedit*(e: Engine; text: string; cursor = -1) =
  ## An input method's word in progress (IME): shown at the caret, underlined, until the
  ## input method commits it (it then arrives through `typeText`) or clears it ("").
  if e.activeChild in e.children:
    e.children[e.activeChild].preedit(text, cursor)
    return
  if e.focus < 0 or not e.s.valid(e.focus) or not isText(e.node(e.focus).kind):
    e.preeditText = ""
    return
  e.preeditText = text
  e.preeditCursor = cursor
  e.caretOn = true
  e.dirty = true

proc nodeRect*(e: Engine; id: int32): (float32, float32, float32, float32) =
  ## The laid-out (left, top, width, height) of a node, or all zeroes when it has
  ## no Yoga node (a leaf that was never styled, or an id that is not in the tree).
  ## Exposed because layout is the one thing a structural check cannot see: the
  ## mock host in tools/verify-wasm.mjs has no Yoga pass at all, so y_node_size
  ## returns 0 for every node and "did this land where it was supposed to?" is
  ## unanswerable from the node tree alone.
  if id notin e.yoga: return (0'f32, 0'f32, 0'f32, 0'f32)
  let l = e.yoga[id].layout()
  (l.left, l.top, l.width, l.height)

proc caretRect*(e: Engine): (float32, float32, float32, float32) =
  ## The text cursor's place in the window (logical px, the window's own scroll applied):
  ## where an input method puts its candidate list. (0, 0, 0, 0) with no text focus.
  if e.activeChild in e.children:
    let c = e.children[e.activeChild]
    let (x, y, w, h) = c.caretRect
    if w == 0 and h == 0: return (0'f32, 0'f32, 0'f32, 0'f32)
    let b = e.boxes.getOrDefault(e.activeChild)
    return (b.x + x, b.y - e.scrollY + y, w, h)
  if e.focus < 0 or not e.s.valid(e.focus) or not isText(e.node(e.focus).kind): return
  let n = e.node(e.focus)
  let v = n.sProp(P_VALUE)
  let (ox, oy, maxW) = e.textOrigin(e.focus)
  let (cx, cy, ch) = caretAt(v, clamp(e.caret, 0, v.len), n.fontSize(n.kind), n.fontWeight(n.kind), maxW, n.textStyle)
  (ox + cx, oy + cy - e.scrollY, 2'f32, ch)

proc activate*(e: Engine; id: int32) =
  ## What pressing a node does, without a pointer or keyboard: a screen reader's
  ## "click". Text fields take the focus; checkboxes toggle; the rest are clicked.
  if not e.s.valid(id): return
  let n = e.node(id)
  if isText(n.kind):
    e.focusOn(id)
    return
  if n.kind == K_CHECKBOX: e.fire(id, E_CHANGE)
  e.fire(id, E_CLICK)
  e.dirty = true

proc blink*(e: Engine) =
  if e.activeChild in e.children:
    e.children[e.activeChild].blink()
  if e.focus >= 0:
    e.caretOn = not e.caretOn
    e.damageNode(e.focus)

proc takeTimers(e: Engine) =
  ## Timers the app asked for since the last look start counting from now.
  if e.s == nil or e.s.timers.len == 0: return
  for (delay, h) in e.s.timers: e.timers.add (e.now + float64(delay), h)
  e.s.timers.setLen(0)

proc pumpSockets(e: Engine) =
  ## WebSockets (W1): connects what the app opened, sends what it sent (in order, once
  ## open), and gives each event to the socket's handler.
  for (id, url, h) in e.s.wsOpen:
    e.sockets[id] = (openWebSocket(url, allowPlain = isLocalHost(urlHost(url)[1])), h)
  e.s.wsOpen.setLen(0)
  for id in e.s.wsClose:
    if id in e.sockets:
      e.sockets[id][0].close()
      e.sockets.del id
  e.s.wsClose.setLen(0)
  var ids: seq[int32]
  for id in e.sockets.keys: ids.add id
  for id in ids:
    let (w, h) = e.sockets[id]
    for ev in w.poll():
      if ev.kind == wsOpen:            # what was sent before it opened goes now, in order
        var keep: seq[(int32, string)]
        for (sid, data) in e.s.wsSend:
          if sid == id: discard w.send(data) else: keep.add (sid, data)
        e.s.wsSend = keep
      e.s.wsEvent[id] = (int32(ord(ev.kind)), if ev.kind == wsClosed: ev.error else: ev.data)
      try:
        dispatchTo(e.app, h)
      except CatchableError as err:
        e.crashed = err.msg
      e.s.wsEvent.del id
      e.dirtyF = true
      if ev.kind == wsClosed:
        w.close()
        e.sockets.del id
        e.s.wsLive.excl id
        break
  var keep: seq[(int32, string)]
  for (sid, data) in e.s.wsSend:
    if sid in e.sockets and e.sockets[sid][0].isOpen: discard e.sockets[sid][0].send(data)
    elif sid in e.s.wsLive: keep.add (sid, data)
  e.s.wsSend = keep

when not defined(emscripten):
  proc pumpSounds(e: Engine) =
    if e.s == nil or e.s.soundQueue.len == 0: return
    for sc in e.s.soundQueue:
      case sc.op
      of 0:
        if e.app != nil and e.app.path.startsWith("y:") and assetSourceHook != nil:
          # an app from Postgres: its sounds are assets there, decoded from memory
          let d = ma.newDecoderFromMemory(assetSourceHook(e.app.path, sc.path))
          if d != nil: e.sounds[sc.id] = SoundSlot(dec: d, playing: false, vol: 1.0'f32)
        else:
          let full = e.resolveAsset(sc.path)
          if full.len > 0:
            let d = ma.newDecoder(full)
            if d != nil: e.sounds[sc.id] = SoundSlot(dec: d, playing: false, vol: 1.0'f32)
      of 1:
        if sc.id in e.sounds:
          ma.seekToPcmFrame(e.sounds[sc.id].dec, 0)
          e.sounds[sc.id].playing = true
      of 2:
        if sc.id in e.sounds:
          e.sounds[sc.id].playing = false
          ma.seekToPcmFrame(e.sounds[sc.id].dec, 0)
      of 3:
        if sc.id in e.sounds:
          e.sounds[sc.id].vol = clamp(sc.vol, 0.0'f32, 1.0'f32)
      else: discard
    e.s.soundQueue.setLen(0)

  proc pumpAudio*(e: Engine; frames: int): seq[float32] =
    e.pumpSounds()
    result = newSeq[float32](max(frames, 0))
    if frames <= 0: return
    var tmp = newSeq[float32](frames)
    for _, slot in e.sounds.mpairs:
      if slot.playing and slot.dec != nil:
        let got = ma.readPcmFrames(slot.dec, tmp[0].addr, frames)
        if got > 0: ma.mixPcmFrames(result, tmp, got, channels = 1, volume = slot.vol)
        if got < frames: slot.playing = false

  proc closeSounds*(e: Engine) =
    for _, slot in e.sounds.mpairs:
      ma.free(slot.dec)
    e.sounds.clear()

proc pumpNet(e: Engine) =
  ## Starts the requests the app queued (the host already checked them against its
  ## `net` list) and hands finished ones to their handlers.
  when not defined(emscripten): e.pumpSounds()
  if e.s == nil: return
  if e.s.fetchQueue.len == 0 and e.imgPending.len == 0 and e.s.wsOpen.len == 0 and e.sockets.len == 0 and not e.netOpen: return
  if e.s.fetchQueue.len > 0 or e.imgPending.len > 0:
    if not e.netOpen:
      e.net = newFetcher()
      e.netOpen = true
    for q in e.s.fetchQueue:
      let local = isLocalHost(urlHost(q.url)[1])
      e.netReqs[e.net.request(q.meth, q.url, q.headers, q.body, allowHttp = local)] = (q.id, q.handler)
    e.s.fetchQueue.setLen(0)
    for url in e.imgPending:
      let local = isLocalHost(urlHost(url)[1])
      e.imgReqs[e.net.request("GET", url, @[], "", allowHttp = local)] = url
    e.imgPending.setLen(0)
  e.pumpSockets()
  if not e.netOpen or (e.netReqs.len == 0 and e.imgReqs.len == 0): return
  for r in e.net.poll():
    if r.id in e.imgReqs:
      let url = e.imgReqs[r.id]
      e.imgReqs.del r.id
      if r.status >= 200 and r.status < 300 and r.body.len > 0:
        let appName = if e.s.appName.len > 0: e.s.appName else: "app"
        let cachePath = netAssetCachePath(appName, url)
        if cachePath.len > 0:
          try:
            createDir(cachePath.parentDir)
            writeFile(cachePath & ".tmp", r.body)
            moveFile(cachePath & ".tmp", cachePath)
            e.laidOutVersion = -1
            e.dirty = true
          except CatchableError as err:
            e.devNote = err.msg
      continue
    if r.id notin e.netReqs: continue
    let (id, h) = e.netReqs[r.id]
    e.netReqs.del r.id
    e.s.fetchDone[id] = (int32(r.status), if r.status == 0: r.error else: r.body)
    try:
      dispatchTo(e.app, h)
    except CatchableError as err:
      e.crashed = err.msg
    e.s.fetchDone.del id
    e.dirtyF = true

proc mediaPending*(e: Engine): bool =
  ## Images here or in apps inside wait on a background decode (a loop looks for them often).
  if e.imgWaiting.len > 0: return true
  for _, c in e.children:
    if c.mediaPending: return true

proc netPending*(e: Engine): int =
  ## Requests on their way, here and in apps inside (a loop keeps polling while any are).
  if e.s != nil: result = e.netReqs.len + e.s.fetchQueue.len + e.imgReqs.len + e.imgPending.len
  for _, c in e.children: result += c.netPending

proc netActive*(e: Engine): bool =
  ## Anything on the network to look after: requests, or open sockets (the loop polls often).
  if e.netPending > 0 or e.sockets.len > 0: return true
  for _, c in e.children:
    if c.netActive: return true

proc onScreen(e: Engine; id: int32): bool =

  ## Some of the node's box shows in the window (inside its clip).
  if id notin e.boxes: return false
  let b = e.boxes[id]
  let cl = intersect(b, e.clips.getOrDefault(id, b))
  cl.w > 0 and cl.h > 0 and cl.y < e.scrollY + e.height and cl.y + cl.h > e.scrollY

proc syncMedia(e: Engine) =
  ## Video and audio nodes (P3): applies play/pause/seek/loop/volume, decodes live only the
  ## videos that show (at most `maxDecoders`, in document order) and playing audio, pulls
  ## due frames, and sends TimeUpdate, MediaReady, MediaEnd and MediaError.
  if e.crashed.len > 0 or (e.mediaIds.len == 0 and e.players.len == 0): return
  var due: seq[(int32, int32)]
  let budget = if e.maxDecoders > 0: e.maxDecoders else: 4
  var decoding = 0
  let liveMode = e.liveMedia and not e.exporting and not defined(emscripten)
  for id in e.mediaIds:
    if not e.s.valid(id): continue
    let n = e.node(id)
    let p = e.playerFor(id)
    if p.path.len == 0:
      if p.src.len > 0 and not p.errored:
        p.errored = true
        due.add (id, E_MEDIAERROR)
      continue
    if n.kind == K_AUDIO and p.startAt < 0: p.startAt = e.now      # nothing draws it: it starts now
    let loop = n.flag(P_LOOP)
    # play / pause (not set: it plays, as videos always did); play after the end starts over
    let playing = not n.has(P_PLAYING) or n.flag(P_PLAYING)
    if playing == p.paused:
      let wasEnded = p.ended
      if playing:
        if wasEnded: (p.heldPos = 0; p.ended = false; p.lastFire = -1)
        if p.startAt >= 0: p.startAt = e.now - p.heldPos * 1000
        p.paused = false
      else:
        if not p.ended: p.heldPos = e.mediaPos(p, n)
        p.paused = true
      when not defined(emscripten):
        if p.live != nil:
          if playing and wasEnded: p.live.seek(0)
          p.live.setPaused(not playing)
    # seek: each new SeekTo value
    if n.has(P_SEEKTO):
      let v = n.num(P_SEEKTO, 0)
      if not p.seekKnown or v != p.seekSeen:
        p.seekKnown = true
        p.seekSeen = v
        let t = if p.duration > 0: clamp(float64(v), 0, p.duration) else: max(0.0, float64(v))
        p.heldPos = t
        p.ended = false
        p.lastFire = -1
        if not p.paused: p.startAt = e.now - t * 1000
        when not defined(emscripten):
          if p.live != nil: p.live.seek(t)
    # live decoding: the videos that show, within budget, and audio that plays
    when not defined(emscripten):
      let wantLive = liveMode and (if n.kind == K_VIDEO: e.onScreen(id) and decoding < budget
                                   else: not p.paused or p.live != nil)
      if n.kind == K_VIDEO and wantLive: inc decoding
      var ww, wh = 2
      if n.kind == K_VIDEO and id in e.boxes:
        let b = e.boxes[id]
        ww = clamp(int(b.w * e.scale), 2, max(2, p.vw))
        wh = clamp(int(b.h * e.scale), 2, max(2, p.vh))
      let vol = if n.flag(P_MUTED): 0'f32 else: clamp(n.num(P_VOLUME, 1), 0, 1)
      if wantLive and p.live == nil:
        if e.audioOut == 0: e.audioOut = if startAudioOut(): 1 else: -1
        p.live = openPlayer(p.path, ww, wh, audio = e.audioOut == 1)
        if p.live == nil:
          p.path = ""                                  # not playable: say so once
          continue
        let at = e.mediaPos(p, n)
        if at > 0: p.live.seek(at)
        p.live.configure(loop, vol, ww, wh)
        p.live.setPaused(p.paused or p.ended)
        if p.live.hasAudio and e.audioOut == 1: p.slot = addAudioSource(audioPull(), p.live.handle)
      elif not wantLive and p.live != nil:
        p.heldPos = p.pos                              # its clock goes on without it
        if not p.paused: p.startAt = e.now - p.pos * 1000
        e.closeLive(p)
      if p.live != nil:
        p.live.configure(loop, vol, ww, wh)
        let st = p.live.status
        p.pos = st.time
        if st.duration > 0: p.duration = st.duration
        if st.ended and not p.ended and not loop:
          p.ended = true                               # it stays at the end until a seek or a new play
          p.heldPos = p.pos
          due.add (id, E_MEDIAEND)
        if n.kind == K_VIDEO:
          let need = max(ww * wh, p.bw * p.bh)
          if p.buf.len < need: p.buf.setLen(need)
          var fw, fh: int
          if p.live.nextFrame(addr p.buf[0], p.buf.len * 4, fw, fh):
            p.bw = fw
            p.bh = fh
            p.hasFrame = true
            e.damageNode(id)
    if not p.isLive:
      if not p.paused and not p.ended and not loop and p.duration > 0 and p.startAt >= 0 and
         e.rawPos(p) >= p.duration:
        p.ended = true
        p.heldPos = p.duration
        due.add (id, E_MEDIAEND)
      p.pos = e.mediaPos(p, n)
    # the file is open: its length, and its waveform if asked
    let waveN = int(n.num(P_WAVEFORM, 0))
    if not p.ready or waveN != p.waveN:
      p.ready = true
      p.waveN = waveN
      when not defined(emscripten):
        if waveN > 0: e.s.waveforms[id] = waveform(p.path, min(waveN, 4096)).peaks
        else: e.s.waveforms.del id
      due.add (id, E_MEDIAREADY)
    e.s.mediaTime[id] = (float32(p.pos), float32(p.duration))
    if not p.paused and (p.lastFire < 0 or abs(p.pos - p.lastFire) >= 0.25):
      p.lastFire = p.pos
      due.add (id, E_TIMEUPDATE)
    elif p.lastFire < 0:                               # a seek while paused still tells the app
      p.lastFire = p.pos
      due.add (id, E_TIMEUPDATE)
  for (id, ev) in due:
    if e.crashed.len > 0: break
    if e.s.valid(id) and e.s.handlerFor(id, ev) >= 0: e.fire(id, ev)

proc pumpCapture(e: Engine) =
  ## Q2: carries out what the app asked of the microphone and camera (the host checked the
  ## capabilities), and feeds the recording from the microphone's ring.
  when not defined(emscripten):
    for (kind, op, name) in e.s.captureReq:
      let file = if name.len > 0 and validStoreKey(e.s.appName): dataDir() / e.s.appName / name else: ""
      case op
      of 1:
        if e.recorder != nil: (discard e.recorder.finish(); e.recorder = nil)
        var err = ""
        if file.len > 0 and startCapture():
          createDir(file.parentDir)
          e.recorder = openRecorder(file, 48000, 1, err)
        if e.recorder == nil:
          e.s.captureState = -1
          if err.len > 0: e.s.logs.add "recording: " & err
        else:
          e.recPath = file
          e.recStart = e.now
          e.recHeld = 0
          e.s.captureState = 1
      of 2:
        if e.s.captureState == 1: (e.recHeld += e.now - e.recStart; e.s.captureState = 2)
      of 3:
        if e.s.captureState == 2: (e.recStart = e.now; e.s.captureState = 1)
      of 4, 5:
        if e.recorder != nil:
          discard e.recorder.finish()
          e.recorder = nil
          stopCapture()
          if op == 5: (try: removeFile(e.recPath) except CatchableError: discard)
        e.s.captureState = 0
      of 6:
        var shot = false
        for id, p in e.players:                     # the camera preview's last frame
          if p.src.startsWith("camera:") and p.hasFrame and file.len > 0:
            createDir(file.parentDir)
            shot = savePixels(file, addr p.buf[0], p.bw, p.bh)
            break
        if not shot: e.s.captureState = -1
      else: discard
    e.s.captureReq.setLen(0)
    if e.recorder != nil:
      if e.recBuf.len == 0: e.recBuf = newSeq[float32](48000)
      while true:                                   # drain the ring (paused: dropped)
        let n = readCapture(e.recBuf)
        if n <= 0: break
        if e.s.captureState == 1: discard e.recorder.write(e.recBuf, n)
      e.s.captureLevel = if e.s.captureState == 1: captureLevel() else: 0
      e.s.captureMs = int32(e.recHeld + (if e.s.captureState == 1: e.now - e.recStart else: 0))

proc pumpCall(e: Engine) =
  ## Q11: carries out the app's call requests, sends the microphone as Opus, plays what
  ## arrives, and hands signaling / state to the app as CallSignal events.
  when not defined(emscripten):
    for (op, text) in e.s.callReq:
      case op
      of 1:
        if e.call != nil: continue
        let lines = text.split('\n')
        e.call = newCall(lines[0] == "1", lines[1 .. ^1].join("\n"))
        if e.call == nil: continue
        e.callEnc = opusEncoder()
        e.callDec = opusDecoder()
        discard startCapture()
        if e.audioOut == 0: e.audioOut = if startAudioOut(): 1 else: -1
        e.callSlot = if e.audioOut == 1: addAudioSource(playPull(), e.call.handle) else: -1
      of 2, 3:
        if e.call == nil: continue
        let nl = text.find('\n')
        if nl < 0: continue
        if op == 2: discard e.call.setRemote(text[0 ..< nl], text[nl + 1 .. ^1])
        else: discard e.call.addCandidate(text[nl + 1 .. ^1], text[0 ..< nl])
      of 4:
        if e.call != nil:
          if e.callSlot >= 0: removeAudioSource(e.callSlot)
          e.callSlot = -1
          e.call.close()
          e.call = nil
          e.callEnc.close()
          e.callDec.close()
          if e.recorder == nil: stopCapture()
      of 5: e.callMuted = text == "1"
      else: discard
    e.s.callReq.setLen(0)
    if e.call == nil: return
    while true:                                        # signaling and state out
      let ev = e.call.nextEvent
      if ev.len == 0: break
      e.s.workerMsg = ev
      if e.s.handlerFor(0, E_CALLSIGNAL) >= 0: e.fire(0, E_CALLSIGNAL)
      if e.call == nil: return                         # hung up in the handler
    if e.recorder == nil:                              # the microphone, 20 ms at a time (a recording has it otherwise)
      if e.recBuf.len == 0: e.recBuf = newSeq[float32](48000)
      let n = readCapture(e.recBuf)
      if n > 0: e.callMic.add e.recBuf[0 ..< n]
      var pk: array[1500, uint8]
      while e.callMic.len >= 960:
        if e.callMuted: (for i in 0 ..< 960: e.callMic[i] = 0)
        if e.callEnc != nil:
          let bytes = e.callEnc.encode(e.callMic.toOpenArray(0, 959), pk)
          if bytes > 0: discard e.call.sendOpus(pk, bytes, 960)
        e.callMic = e.callMic[960 .. ^1]
      if e.callMic.len > 48000: e.callMic.setLen(0)    # not connected yet: don't pile up
    var inp: array[1500, uint8]
    var pcm: seq[float32]
    while true:                                        # what the other side said
      let n = e.call.nextPacket(inp)
      if n <= 0: break
      if e.callDec != nil:
        let f = e.callDec.decode(inp, n, pcm)
        e.call.playPush(pcm, f)

type DialogCtx = ref object

  e: Engine
  req: PickReq

proc onDialogPicked(ud: pointer; p: cstring) {.cdecl.} =
  if ud == nil: return
  let ctx = cast[DialogCtx](ud); GC_unref(ctx)
  let (e, req) = (ctx.e, ctx.req)
  let path = if p != nil: $p else: ""
  var st = -1'i32; var body = ""
  if not req.save:
    if path.len > 0 and fileExists(path):
      try:
        let f = open(path, fmRead)
        let sz = min(f.getFileSize(), 16 * 1024 * 1024)
        body = newString(sz)
        if sz > 0: discard f.readBuffer(addr body[0], sz)
        f.close(); st = 200'i32
      except CatchableError: st = -1'i32
  elif path.len > 0:
    try: writeFile(path, req.saveData); st = 200'i32
    except CatchableError: st = -1'i32
  e.s.pickDone[req.id] = (st, body)
  try: dispatchTo(e.app, req.handler)
  except CatchableError as err: e.crashed = err.msg
  e.s.pickDone.del req.id; e.dirty = true

proc pumpPick*(e: Engine) =
  if e.s == nil or e.s.pickQueue.len == 0: return
  let q = e.s.pickQueue; e.s.pickQueue.setLen(0)
  for req in q:
    let ctx = DialogCtx(e: e, req: req); GC_ref(ctx)
    if not req.save: showOpenFileDialog(Window(nil), req.filter, onDialogPicked, cast[pointer](ctx))
    else: showSaveFileDialog(Window(nil), req.name, req.filter, onDialogPicked, cast[pointer](ctx))

proc pumpNotify(e: Engine) =
  if e.s == nil or e.s.notifyQueue.len == 0: return
  let q = e.s.notifyQueue; e.s.notifyQueue.setLen(0)
  for req in q:
    showNotification(req.title, req.body)

proc dropFile*(e: Engine; path: string; x, y: float32) =
  if path.len == 0 or not fileExists(path): return
  var body = ""
  try:
    let f = open(path, fmRead)
    let sz = min(f.getFileSize(), 16 * 1024 * 1024)
    body = newString(sz)
    if sz > 0: discard f.readBuffer(addr body[0], sz)
    f.close()
  except CatchableError: return
  e.s.dropData = body
  e.s.dropName = extractFilename(path)
  let (cid, lx, ly) = e.childAt(x, y)
  if cid >= 0 and cid in e.children:
    e.children[cid].dropFile(path, lx, ly)
  else:
    let (_, chain) = e.hitAll(x, y)
    var target = -1'i32
    for i in countdown(chain.high, 0):
      if e.s.handlerFor(chain[i], E_DROP) >= 0:
        target = chain[i]; break
    if target < 0 and e.s.valid(0) and e.s.handlerFor(0, E_DROP) >= 0:
      target = 0
    if target >= 0: e.fire(target, E_DROP)
  e.s.dropData = ""
  e.s.dropName = ""


# --- synthesis (AU1): Synth nodes are voices in the audio device's mix ----------------------

proc syncSynths(e: Engine) =
  ## Voices for the app's Synth nodes, their parameters from the props, gone with the node.
  if e.s == nil or e.synthsAt == e.s.version: return
  e.synthsAt = e.s.version
  var seen: seq[int32]
  for i in 0 ..< e.s.nodes.len:
    let n = e.s.nodes[i]
    if not n.alive or n.kind != K_SYNTH: continue
    let id = int32(i)
    seen.add id
    if id notin e.synths:
      var slot = -1
      let v = newSynth()
      if e.liveMedia:
        if e.audioOut == 0: e.audioOut = if startAudioOut(): 1 else: -1
        if e.audioOut == 1: slot = v.play
      e.synths[id] = (v, slot)
    let v = e.synths[id][0]
    v.set(spWave, n.num(P_WAVE, 0))
    v.set(spFreq, n.num(P_FREQ, 440))
    v.set(spVolume, n.num(P_VOLUME, 0.5))
    v.set(spFilter, n.num(P_FILTERKIND, 0))
    v.set(spCutoff, n.num(P_CUTOFF, 1000))
    v.set(spResonance, n.num(P_RESONANCE, 0.707))
    v.set(spPan, n.num(P_PAN, 0))
    v.set(spAttack, n.num(P_ATTACK, 0.01))
    v.set(spRelease, n.num(P_RELEASE, 0.2))
    v.set(spEcho, n.num(P_ECHO, 0))
    v.set(spEchoMix, n.num(P_ECHOMIX, 0.4))
    v.set(spEchoFeedback, n.num(P_ECHOFEEDBACK, 0.3))
    v.set(spLfo, n.num(P_LFO, 0))
    v.set(spLfoDepth, n.num(P_LFODEPTH, 0.01))
    v.set(spGate, (if not n.has(P_PLAYING) or n.flag(P_PLAYING): 1'f32 else: 0'f32))
  var gone: seq[int32]
  for id in e.synths.keys:
    if id notin seen: gone.add id
  for id in gone:
    let (v, slot) = e.synths[id]
    if slot >= 0: removeAudioSource(slot)   # the device never calls it again: safe to free
    v.free
    e.synths.del id

proc synthSamples*(e: Engine; id: int32; frames: int): seq[float32] =
  ## Synth node `id`'s next `frames` stereo frames (48 kHz), rendered here instead of by the
  ## device — for tests and film export (not while it plays on the device).
  e.syncSynths()
  if id in e.synths: e.synths[id][0].render(result, frames)

proc tick*(e: Engine; ms: float64) =
  ## Sets the clock (ms, any origin, only ever forward) here and in every app inside,
  ## and runs the app's `after` steps that are due, in time order. On a fake clock
  ## (tests, video export) they land on exactly the frame they are due.
  e.takeTimers()
  e.now = max(e.now, ms)
  while e.crashed.len == 0:
    e.takeTimers()
    var best = -1
    for i, (at, _) in e.timers:
      if at <= e.now and (best < 0 or at < e.timers[best][0]): best = i
    if best < 0: break
    let h = e.timers[best][1]
    e.timers.delete(best)
    try:
      dispatchTo(e.app, h)
    except CatchableError as err:
      e.crashed = err.msg
    e.dirtyF = true
  if e.crashed.len == 0: e.pumpNet()
  e.syncSynths()
  if e.crashed.len == 0 and (e.lastFrameAt == 0 or e.now - e.lastFrameAt >= 12):   # ~one per display frame
    e.frameEvent()
  if e.crashed.len == 0: e.stepPhysics()
  if e.tipOn and not e.tipShown and e.now - e.tipSince >= 500:   # rested long enough: show it
    e.tipShown = true
    e.ovDirty = true
    e.dirty = true
  e.syncMedia()
  e.pumpCapture()
  e.pumpCall()
  if e.s != nil and e.s.openReq.len > 0:          # URLs for the system to open (Q8; the host checked them)
    for u in e.s.openReq:
      if openUrlHook != nil: openUrlHook(u)
    e.s.openReq.setLen(0)
  if e.crashed.len == 0 and e.app != nil and e.s.workers.len > 0:   # messages from background workers (Q7)
    try:
      if e.app.pumpWorkers(): e.dirtyF = true
    except CatchableError as err:
      e.crashed = err.msg
  e.stepGlides()
  if e.crashed.len == 0: e.pumpPick()
  if e.crashed.len == 0: e.pumpNotify()

  for _, c in e.children: c.tick(ms)

proc pendingTimers*(e: Engine): int =
  ## `after` steps still waiting (so a loop knows to keep ticking).
  e.takeTimers()
  e.timers.len

proc resize*(e: Engine; w, h: float32) =
  e.width = w
  e.height = h
  e.laidOutVersion = -1
  e.dirty = true

# --- start ---------------------------------------------------------------------------

proc start*(wasmPath: string; width, height: float32; scale = 1'f32; intro = false): Engine =
  ## Loads and runs the app module in its own sandbox; the engine is ready to paint.
  ## If the app traps while starting, the engine shows why instead of failing.
  ## `intro`: nodes on the first screen play their `enter` too (films start from nothing).
  let app = openApp(wasmPath)
  result = Engine(app: app, s: app.state, width: width, height: height, scale: scale,
                  hover: -1, pressed: -1, focus: -1, laidOutVersion: -1, dirtyF: true, fullDamage: true, selA: (-1'i32, 0), selZ: (-1'i32, 0), caretOn: true,
                  appDir: wasmPath.parentDir, activeChild: -1, hoverChild: -1, pressedChild: -1, draggingNode: -1,

                  reducedMotion: getEnv("YANTRA_REDUCED_MOTION") notin ["", "0"])
  result.placedOnce = intro
  result.wireLayers()
  result.wirePhysics()
  result.wireBones()
  result.wireTextMetrics()
  try:
    run(app)
  except CatchableError as err:
    result.crashed = err.msg
    return
  result.layout()

# --- hot reload (roadmap U3/U4) --------------------------------------------------------

proc siteKeys(e: Engine): Table[string, int32] =
  ## Every node made by the DSL in a dev build, by where in the source it came from
  ## plus its turn among nodes from the same place ("notes.nim:72:6#0"). Stable across
  ## builds as long as that code is still there.
  var seen: Table[string, int]
  proc walk(e: Engine; id: int32; seen: var Table[string, int]; keys: var Table[string, int32]) =
    let n = e.node(id)
    if not n.alive: return
    let site = n.sProp(P_SITE)
    if site.len > 0:
      let k = seen.getOrDefault(site, 0)
      seen[site] = k + 1
      keys[site & "#" & $k] = id
    for c in n.children: e.walk(c, seen, keys)
  e.walk(0, seen, result)

proc reload*(e: Engine; wasmPath: string): bool =
  ## Swaps in a new build of this app without losing what the user was doing: its
  ## `state(...)` values, focus, caret and selection, scroll positions, and the apps
  ## running inside its `appView`s all carry over. If the new build fails to start,
  ## the old one keeps running and `devNote` says why.
  var snapshot = ""
  if e.crashed.len == 0 and e.app != nil:
    try: snapshot = e.app.saveState()
    except CatchableError: snapshot = ""
  var byId: Table[int32, string]
  if e.crashed.len == 0 and e.s != nil:
    for k, id in e.siteKeys(): byId[id] = k
  let focusKey = byId.getOrDefault(e.focus, "")
  var scrollsBy, textScrollBy: Table[string, float32]
  for id, v in e.scrolls:
    if id in byId: scrollsBy[byId[id]] = v
  for id, v in e.textScroll:
    if id in byId: textScrollBy[byId[id]] = v
  var childrenBy: Table[string, (Engine, string)]
  for id, c in e.children:
    if id in byId: childrenBy[byId[id]] = (c, e.childSource.getOrDefault(id, ""))
  let app = try: openApp(wasmPath)
            except CatchableError as err:
              e.devNote = err.msg
              e.dirty = true
              return false
  try:
    run(app, snapshot)
  except CatchableError as err:
    e.devNote = "it stopped while starting: " & err.msg
    e.dirty = true
    return false
  # the new build is up: take it
  e.app = app
  e.s = app.state
  e.crashed = ""
  e.devNote = ""
  inc e.reloads
  e.freeYoga()
  e.boxes.clear(); e.clips.clear()
  e.motions.clear(); e.entered.clear(); e.enterAt.clear(); e.loopAt.clear()
  e.exitWatch.clear(); e.ghosts.setLen(0); e.ghostBoxes.clear(); e.ghostClips.clear()
  e.placedOnce = false                 # nothing plays `enter` just because it was rebuilt
  e.hover = -1; e.pressed = -1; e.hoverChain.setLen(0)
  e.undoStack.setLen(0); e.redoStack.setLen(0)
  e.children.clear(); e.childSource.clear()
  if e.netOpen:                        # answers for the old build have nobody to go to
    for cid in e.netReqs.keys: e.net.cancel(cid)
    e.netReqs.clear()
  for _, (w, _) in e.sockets: w.close()
  e.sockets.clear()
  e.scrolls.clear(); e.textScroll.clear()
  let keys = e.siteKeys()
  for k, (child, src) in childrenBy:     # apps in tabs keep running, with their own state
    let id = keys.getOrDefault(k, -1)
    if id >= 0 and e.node(id).kind == K_APPVIEW and e.node(id).sProp(P_SOURCE) == src:
      e.children[id] = child
      e.childSource[id] = src
  for k, v in scrollsBy:
    if k in keys: e.scrolls[keys[k]] = v
  for k, v in textScrollBy:
    if k in keys: e.textScroll[keys[k]] = v
  let hadFocus = e.focus
  e.focus = keys.getOrDefault(focusKey, -1)
  if e.focus >= 0:
    let n = e.node(e.focus).sProp(P_VALUE).len
    e.caret = clamp(e.caret, 0, n)
    e.anchor = clamp(e.anchor, 0, n)
  elif hadFocus >= 0:
    e.activeChild = -1
  if e.activeChild notin e.children: e.activeChild = -1
  if e.hoverChild notin e.children: e.hoverChild = -1
  if e.pressedChild notin e.children: e.pressedChild = -1
  e.laidOutVersion = -1
  e.layout()
  e.dirty = true
  true

proc reloadEverywhere*(e: Engine; wasmPath: string): int =
  ## Reloads every app built from `wasmPath`: this one and any running inside it.
  ## Returns how many were swapped.
  let target = wasmPath.replace('\\', '/').toLowerAscii
  if e.app != nil and e.app.path.replace('\\', '/').toLowerAscii == target:
    if e.reload(wasmPath): inc result
  for _, c in e.children: result += c.reloadEverywhere(wasmPath)
  if result > 0: e.dirty = true

# --- documents (D1) --------------------------------------------------------------------

const ptPerPx* = 72'f32 / 96'f32     ## PDF points per logical pixel: 1280x720 px is a 13.33x7.5 in slide

proc pages*(e: Engine): seq[int32] =
  ## The app's `page` / `slide` nodes, in reading order.
  e.ensureLayout()
  for id in e.paintOrder:
    if e.node(id).alive and e.node(id).kind == K_PAGE: result.add id

proc exportPdf*(e: Engine; path: string; title = ""; author = ""): int =
  ## Writes the app to a PDF: one page per `page`/`slide` node (at its own size), or the
  ## whole window as one page if it has none. The same drawing code as the screen, so
  ## shapes stay vectors and text stays selectable text. Returns the number of pages.
  e.ensureLayout()
  var doc = openPdf(path, (if title.len > 0: title else: e.node(0).sProp(P_TEXT)), author)
  let ps = e.pages
  let savedScroll = e.scrollY
  e.scrollY = 0
  e.exporting = true
  try:
    if ps.len == 0:
      let h = max(e.contentH, e.height)
      let c = doc.beginPage(e.width * ptPerPx, h * ptPerPx)
      c.scale(ptPerPx)
      c.clear(e.node(0).col(P_COLOR, WindowBg))
      for k in e.zSorted(e.node(0).children): e.paintTree(c, k)
      doc.endPage()
    else:
      for id in ps:
        let b = e.boxes[id]
        let c = doc.beginPage(b.w * ptPerPx, b.h * ptPerPx)
        c.scale(ptPerPx)
        c.translate(-b.x, -b.y)
        e.paintTree(c, id)
        doc.endPage()
  finally:
    e.exporting = false
    e.scrollY = savedScroll
    result = doc.pages
    doc.close()

proc windowSizeHint*(e: Engine): (int, int) =
  ## The size the app asked for with `app(..., width = , height = )`.
  let root = e.node(0)
  (int(root.num(P_WIDTH, 800)), int(root.num(P_HEIGHT, 600)))

proc title*(e: Engine): string = e.node(0).sProp(P_TEXT)

# --- OS integration (Q8) -----------------------------------------------------------------------

proc dragRegions*(e: Engine): (seq[array[4, float32]], seq[array[4, float32]]) =
  ## The window's drag regions (nodes with DragRegion) and, inside them, what stays
  ## clickable (interactive nodes), in window points.
  for id in e.paintOrder:
    if id notin e.boxes or not e.node(id).visible: continue
    let b = e.boxes[id]
    let r = [b.x, b.y - e.scrollY, b.w, b.h]
    if e.node(id).flag(P_DRAGREGION): result[0].add r
    elif e.interactive(id): result[1].add r

proc toWindow(e: Engine; ev: int32) =
  if e.crashed.len == 0 and e.s.handlerFor(0, ev) >= 0: e.fire(0, ev)

proc menuCommand*(e: Engine; id: int) =
  ## A menubar item was chosen: MenuCommand on the window.
  e.s.menuCmd = int32(id)
  e.toWindow(E_MENUCOMMAND)

proc systemTheme*(e: Engine; theme: int; accentArgb: uint32) =
  ## The system's light/dark theme and accent (at start and when they change).
  e.s.sysTheme = int32(theme)
  e.s.accent = int32(accentArgb and 0xFFFFFF'u32)
  e.toWindow(E_SYSTEMTHEME)

proc deepLink*(e: Engine; url: string) =
  ## scheme://… was opened (a link, an OAuth redirect): DeepLink on the window.
  e.s.workerMsg = url
  e.toWindow(E_DEEPLINK)

proc spellClick(e: Engine; x, y: float32): bool =
  ## A right click (Q9): on a misspelled word in a field with Spellcheck, the word is
  ## selected and SpellMenu tells the app the word and its suggestions (for its context menu).
  ## True if it was on one (then contextClick does nothing more).
  when not defined(emscripten):
    let id = e.hitTest(x, y)
    if id < 0 or not isText(e.node(id).kind) or not e.node(id).flag(P_SPELLCHECK): return
    let v = e.node(id).sProp(P_VALUE)
    let at = e.textPos(id, x, y + e.scrollY)
    for (a, z) in e.spellOf(id, v):
      if at >= a and at <= z:
        e.focusOn(id)
        e.anchor = a
        e.caret = z
        e.s.spellRange = (int32(a), int32(z))
        e.s.workerMsg = v[a ..< z] & "\t" & suggestions(v[a ..< z]).join("\t")
        if e.s.handlerFor(id, E_SPELLMENU) >= 0: e.fire(id, E_SPELLMENU)
        e.dirty = true
        return true

