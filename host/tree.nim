## The node tree — the engine's data model, and the contract between the wasm
## app and whatever renders it.
##
## Deliberately dependency-free: no wasmtime, no Qt, no I/O. The host populates
## it from wasm imports; the renderer consumes it; tests construct it by hand.
## Keeping it free of both runtimes is what lets the translation logic be tested
## with no wasm module and no display.

import std/[tables, sets]
export sets

type
  ValueKind* = enum vkInt, vkFloat, vkString

  Value* = object
    ## A property value. The node tree is untyped at the wire level (an int32
    ## property id plus one of three payload kinds), because the SDK's prop ids
    ## are a versioned enum and the engine must not need to know their meaning.
    case kind*: ValueKind
    of vkInt: i*: int32
    of vkFloat: f*: float32
    of vkString: s*: string

  Node* = ref object
    ## One UI element. `children` holds indices into HostState.nodes, not
    ## pointers, so the tree serializes and copies trivially. Ids are never
    ## reused: a removed node stays in `nodes` with `alive = false`, so a stale id
    ## can never point at a different node.
    kind*: int32
    props*: Table[int32, Value]
    children*: seq[int32]
    parent*: int32 = -1
    alive*: bool = true
    rtl*: bool                       ## laid out right-to-left (its own or an ancestor's Direction; the engine sets it)

  FetchReq* = object
    ## One request an app made (F1/W1): checked against its `net` list before it is queued.
    id*: int32
    meth*, url*, body*: string
    headers*: seq[string]
    handler*: int32

  SoundCmd* = object
    id*, op*: int32
    path*: string
    vol*: float32

  PickReq* = object
    id*: int32
    save*: bool
    handler*: int32
    name*: string
    filter*: string
    saveData*: string

  ParamInfo* = object
    ## A Vajra view's `param` (`param size = 120px in 40px .. 400px`): what a GUI shows.
    view*, name*, value*, lo*, hi*: string

  NotifyReq* = object
    title*: string
    body*: string

  HostState* = ref object
    ## Everything one app instance has done so far.
    nodes*: seq[Node]
    bufs*: Table[int32, string]      ## S3D bulk data an app handed over with y_buf (vertices, matrices), by id
    bufVer*: Table[int32, int]       ## each buffer's version: bumped on every y_buf
    bufsTouched*: bool
    # game input (G-IN): what is held right now, read by the app with y_input
    keysHeld*: HashSet[int32]        ## keycodes down
    mouseDX*, mouseDY*: float32      ## raw movement since the last Frame event
    buttonsHeld*: int32              ## mouse buttons down (bit 0 left, 1 middle, 2 right)
    padAxes*: array[6, float32]      ## the first gamepad: sticks -1..1, triggers 0..1
    padButtons*: int32
    padOn*: bool
    pointerLocked*: bool
    pickAt*: array[3, float32]       ## where the last click hit a 3D object (world metres) (T3D)
    pickInstance*: int32             ## which copy of an instanced mesh it hit (-1 not instanced)
    physOp*: proc (op: int32; name: string; a: array[6, float32]): float32 {.closure.}
      ## physics (PH1): the engine answers the app's y_phys calls on its named objects
    physHit*: string                 ## the name of what the last raycast hit
    boneOp*: proc (op: int32; model, bone: string; a: array[3, float32]): float32 {.closure.}
      ## characters (CH1): the engine turns a named model's bones and says where they are
    layerOp*: proc (op, id, x, y, w, h: int32; f: float32; data: string): string {.closure.}
      ## raster layers (CV2): the engine does them (0 new, 1 draw, 2 filter, 3 read, 4 write, 5 free)               ## a buffer changed since the engine last looked
    measureTextOp*: proc (s, family: string; size: float32; weight: int32): float32 {.closure.}
      ## text metrics (A1): the engine measures a string in a named family and returns its
      ## width, so an app can centre, right-align and letter-space real text instead of
      ## inventing an advance. Nil until the renderer wires it.
    handlers*: Table[int32, int32]   ## node id -> most recent handler (kept for older callers)
    events*: Table[(int32, int32), int32]  ## (node id, event) -> handler index
    version*: int                    ## bumped on every change, so a renderer knows to redraw
    logs*: seq[string]
    dispatchCalls*: int
    propSets*: int                   ## property changes the app has sent (what a redraw costs)
    timers*: seq[(int32, int32)]     ## (delay ms, handler) the app asked for with y_after; the engine takes them
    appName*: string                 ## the app's file name: whose stored data this is
    appDir*: string                  ## the app's own folder: the only place it may read files from
    location*: string                ## the screen a Vajra app is on (`/room/0190…`): the end of its address
    params*: seq[ParamInfo]          ## a Vajra app's `param`s, in the order it made them: any GUI's controls
    fetchQueue*: seq[FetchReq]       ## requests the app asked for (checked); the engine starts them
    fetchDone*: Table[int32, (int32, string)] ## id -> (status, body or error): readable while its handler runs
    nextFetch*: int32
    wsOpen*: seq[(int32, string, int32)]      ## (id, url, handler): sockets to connect (checked)
    wsSend*: seq[(int32, string)]             ## messages the app sent, in order
    wsClose*: seq[int32]
    wsLive*: HashSet[int32]                   ## sockets not yet closed
    wsEvent*: Table[int32, (int32, string)]   ## id -> (1 open / 2 message / 3 closed, data or reason)
    scrollOf*: Table[int32, float32]  ## scroll offset of nodes with a Scroll handler (0 = the window)
    sizes*: Table[int32, (float32, float32)]  ## laid-out (width, height) of nodes that asked (Resize)
    frameDt*: float32                ## dt passed to yantra_frame()
    keyCode*, keyMods*: int32        ## the key a Key handler is running for (SDL key code, modifier bits)
    keyHandled*: bool                ## the handler took it: the engine does nothing more with it
    # what changed since the engine last laid out (P1): it restyles or re-links only these
    touched*: HashSet[int32]         ## nodes whose props were set
    reshaped*: HashSet[int32]        ## nodes whose children list changed (a child added, moved or removed)
    mediaTime*: Table[int32, (float32, float32)] ## video/audio node -> (position, duration) in s (P3)
    waveforms*: Table[int32, seq[float32]]      ## audio node -> peak loudness per slice, 0..1 (P3)
    blockCaret*: int32               ## where a block was split (BlockSplit), y_node_size axis 6 (P5)
    pointerAt*: (float32, float32)   ## a canvas pointer event's point, in the node's px (axes 7, 8; P7)
    scrollXOf*: Table[int32, float32] ## a canvas's horizontal scroll (axis 9; its vertical one is scrollOf, P8)
    # capture (Q2): what the app asked of the microphone and camera (checked); the engine does it
    captureReq*: seq[(int32, int32, string)]   ## (1 mic / 2 camera, op, file name in its data folder)
    captureState*: int32             ## 0 idle, 1 recording, 2 paused, -1 the last request failed
    captureLevel*: float32           ## the microphone's level now, 0..1
    captureMs*: int32                ## how long the recording is so far
    linkHit*: int32                  ## the link a LinkClick is about (axis 10, Q3)
    findCount*, findAt*: int32       ## find-in-page matches and the current one (axes 11, 12, Q3)
    pointerPage*: (float32, float32) ## a pointer event's point in page px (axes 13, 14, Q6)
    command*: int32                  ## a Command event's command: 1 undo, 2 redo (axis 15, Q6)
    # workers (Q7): background instances on their own threads (host.nim owns them)
    workers*: Table[int32, (pointer, int32)]  ## id -> (the worker's shared box, the handler for its messages)
    nextWorker*: int32
    workerMsg*: string               ## the message being delivered (y_worker_msg reads it)
    workerOut*: pointer              ## in a worker: where y_worker_post sends (its parent's inbox)
    # OS integration (Q8)
    menuCmd*: int32                  ## axis 16
    sysTheme*: int32                 ## axis 17: 0 unknown, 1 light, 2 dark
    accent*: int32                   ## axis 18: RGB
    openReq*: seq[string]            ## URLs the app asked the system to open (checked: http, https, mailto)
    spellRange*: (int32, int32)      ## the word a SpellMenu is about (axes 19, 20, Q9)
    callReq*: seq[(int32, string)]   ## calls (Q11): (op, text) the app asked for; the engine does them
    # sound, file dialogs, dnd, notifications (C2, C3, C4, C6)
    soundQueue*: seq[SoundCmd]
    nextSound*: int32
    pickQueue*: seq[PickReq]
    pickDone*: Table[int32, (int32, string)]
    nextPick*: int32
    dropData*: string
    dropName*: string
    notifyQueue*: seq[NotifyReq]


proc lastLog*(s: HostState): string =
  ## Most recent line the app asked the engine to log.
  if s.logs.len > 0: s.logs[s.logs.len - 1] else: ""

proc hasProp*(n: Node; p: int32): bool = p in n.props
proc iProp*(n: Node; p: int32): int32 =
  if p in n.props: n.props[p].i else: 0
proc fProp*(n: Node; p: int32): float32 =
  if p in n.props: n.props[p].f else: 0.0
proc sProp*(n: Node; p: int32): string =
  if p in n.props: n.props[p].s else: ""

# --- tree edits: the engine-side meaning of the wire ops -----------------------------

proc valid*(s: HostState; n: int32): bool = n >= 0 and int(n) < s.nodes.len and s.nodes[int(n)].alive

proc detach(s: HostState; c: int32) =
  let p = s.nodes[int(c)].parent
  if p >= 0:
    let i = s.nodes[int(p)].children.find(c)
    if i >= 0: s.nodes[int(p)].children.delete(i)
    s.reshaped.incl p
  s.nodes[int(c)].parent = -1

proc createNode*(s: HostState; kind: int32): int32 =
  s.nodes.add Node(kind: kind, props: initTable[int32, Value](), children: @[], parent: -1, alive: true)
  inc s.version
  int32(s.nodes.high)

proc appendChild*(s: HostState; parent, child: int32) =
  ## y_node_child: append (moving it if it already has a parent).
  if not s.valid(parent) or not s.valid(child) or parent == child: return
  s.detach(child)
  s.nodes[int(parent)].children.add child
  s.nodes[int(child)].parent = parent
  s.reshaped.incl parent
  inc s.version

proc insertBefore*(s: HostState; parent, child, before: int32) =
  ## y_node_insert: put `child` into `parent` just before `before` (-1 or not a
  ## child of `parent` = at the end).
  if not s.valid(parent) or not s.valid(child) or parent == child: return
  s.detach(child)
  let i = if before < 0: -1 else: s.nodes[int(parent)].children.find(before)
  if i < 0: s.nodes[int(parent)].children.add child
  else: s.nodes[int(parent)].children.insert(child, i)
  s.nodes[int(child)].parent = parent
  s.reshaped.incl parent
  inc s.version

proc kill(s: HostState; n: int32) =
  ## A dead node keeps its props and its children list, so an engine can still draw
  ## it on its way out (exit motion); `valid` is false for it and all below it.
  s.nodes[int(n)].alive = false
  for c in s.nodes[int(n)].children: s.kill(c)

proc removeNode*(s: HostState; n: int32) =
  ## y_node_remove: detach and destroy the node and its whole subtree.
  if not s.valid(n): return
  s.detach(n)
  s.kill(n)
  inc s.version

proc setProp*(s: HostState; n: int32; prop: int32; v: Value) =
  if not s.valid(n): return
  s.nodes[int(n)].props[prop] = v
  s.touched.incl n
  inc s.propSets
  inc s.version

proc handlerFor*(s: HostState; n: int32; event: int32): int32 =
  ## The handler registered for `event` on node `n`, or -1.
  s.events.getOrDefault((n, event), -1'i32)
