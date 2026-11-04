# protocol/schema.nim
# The SINGLE SOURCE OF TRUTH for node kinds, properties, and events.

import std/strutils

const NodeKinds* = [
  "Window", "Column", "Row", "Text", "Button", "Image", "Input", "Spacer",
  "Scene3D", "Model", "Camera", "Light",
  "Panel",
  "TextArea", "Checkbox", "Radio", "Select", "Slider", "Progress", "Switch", "DatePicker", "ColorPicker",
  "Grid", "Flex", "Stack", "ScrollArea", "Tabs", "TabPanel",
  "Table", "ListView", "TreeView", "Chart",
  "Video", "Audio", "Canvas",
  "Modal", "Drawer", "Popover", "Tooltip", "Menu", "ContextMenu",
  "Group",  # layout-transparent: holds the items of a `for` or the branch of an `if`
  "AppView", # another app, in its own sandbox, drawn inside this node's box (`source` names it)
  "Path",    # vector shape from SVG path data (icons, drawings)
  "Page",    # a page of a document or a slide of a deck: one PDF page each (D1)
  "Mesh",    # S3D: a 3D object in a Scene3D: a built-in shape or the app's own geometry
  "Synth",   # AU1: a sound voice the engine generates (wave or noise -> filter -> envelope -> echo)
  "Particles" # PT1: sparks, smoke, rain: many small sprites the engine emits and moves in a Scene3D
]

const Props* = [
  "Text", "X", "Y", "Width", "Height", "Visible", "Color", "FontSize", "Align", "Opacity",
  "Source", "Scale", "RotX", "RotY", "RotZ", "PosX", "PosY", "PosZ", "Metalness", "Roughness",
  "Spacing", "PadTop", "PadRight", "PadBottom", "PadLeft", "Radius", "BorderColor", "BorderWidth",
  "AnimTarget", "AnimFrom", "AnimTo", "AnimDuration", "AnimEasing", "AnimDelay", "AnimLoop", "AnimYoyo", "AnimTrigger",
  "Transition", "TransDuration", "TransEasing",
  "Value", "Placeholder", "Min", "Max", "Step", "Checked", "Options", "Multiple", "Disabled", "Required", "ReadOnly", "MaxLength", "Pattern",
  "FlexGrow", "FlexShrink", "FlexBasis", "GridCols", "GridRows", "GridGap", "ZIndex", "Overflow", "ScrollX", "ScrollY",
  "TabIndex", "TabCount",
  "Columns", "Rows", "Selection", "Sortable", "Filterable",
  "Src", "Poster", "Autoplay", "Loop", "Muted", "Volume", "PlaybackRate",
  "CanvasWidth", "CanvasHeight",
  "ModalOpen", "ModalTitle", "CloseOnEsc", "CloseOnClickOutside",
  "OnChange", "OnInput", "OnFocus", "OnBlur", "OnSubmit",
  "FontWeight", "TextColor",
  # E5 style system (docs/spec/style.md) — appended, existing ids never move
  "MarginTop", "MarginRight", "MarginBottom", "MarginLeft",
  "MinWidth", "MinHeight", "MaxWidth", "MaxHeight",
  "AlignItems", "Justify", "Wrap",
  "Absolute", "InsetTop", "InsetRight", "InsetBottom", "InsetLeft",
  "Scroll", "Clip",
  "GradFrom", "GradTo", "GradAngle",
  "ShadowX", "ShadowY", "ShadowBlur", "ShadowColor",
  "FontFamily", "LineHeight", "Italic", "MaxLines",
  "PathData", "StrokeWidth", "Cursor",
  "HoverFill", "HoverColor", "HoverBorder", "HoverOpacity",
  "PressFill", "PressColor", "PressBorder", "PressOpacity",
  "FocusFill", "FocusColor", "FocusBorder", "FocusOpacity",
  "Theme",  # the theme name on a window: how a shell's theme reaches the apps inside it
  # M1 motion (docs/spec/style.md §7) — appended
  "Enter", "Exit",          # "opacity,x,y,scale,rotate,ms,delay,easing" played when a node appears / leaves
  "HoverScale", "PressScale", "FocusScale", "HoverY", "PressY", "FocusY",
  # U3 identity — appended
  "Site",   # dev builds: "file.nim:line:col" of the code that made the node (hot reload, inspectors)
  # U8 media — appended
  "Fit",    # how media fills its box: 0 contain, 1 cover, 2 fill
  # A1 live edits — appended
  "Name",   # `text @headline "…"`: a stable handle for code, tests, tools and AI edits
  # FX1 effects — appended
  "Blur", "BackdropBlur", "Blend", "Saturate", "Brightness", "Contrast", "Shader",
  # L1 grid layout — appended
  "Span",   # a grid item: how many columns it takes
  # F1 network — appended
  "Net",    # on the window: the hosts the app may fetch from ("api.example.com, *.example.org")
  # V1 scroll-linked motion — appended
  "Reveal",   # the pose while out of view (enter's format); eased to itself as it scrolls in
  "Parallax", # moves this fraction of its distance from the view's middle (0.3: slower than the page)
  # R2 rich text — appended
  "Spans",    # styled runs over a Text's bytes: "start,end,flags,argb,size;…" (nimskia TextStyle.spans)
  # OV1 overlays — appended
  "Placement", # where a popover/menu/tooltip sits by its anchor: 0 below, 1 above, 2 right, 3 left (flips to fit)
  # SCR1 scroll control — appended
  "StickToEnd", # a scroll area that was at its end stays there as content grows (chats, logs)
  # P3 media playback — appended
  "Playing",  # Video/Audio: 1 plays, 0 pauses (not set: a video plays, as before)
  "SeekTo",   # Video/Audio: seconds; each new value seeks there
  "Waveform", # Audio: how many peaks to measure for a waveform (read with y_node_size axis 1000+i)
  # P5 block editing — appended
  "Block",    # Input/TextArea: one block of a document (arrows cross blocks, Enter splits, Backspace at 0 merges)
  # P6 sticky — appended
  "Sticky",     # px from the top of the scrolling view it sticks at, inside its own container (headers)
  "StickyLeft", # px from the left of the view it sticks at (frozen columns)
  # P7 canvas — appended
  "Draw",     # Canvas: the draw-command list (see libs/nimskia skia_shim.cpp yk_canvas_run)
  # P9 right-to-left — appended
  "Direction", # 0 as its parent, 1 left-to-right, 2 right-to-left (layout mirrors; text is laid out RTL)
  # Q1 virtual lists — appended (ScrollY, from the start, is "scroll to this y": each new value)
  "Anchor",      # a scroll area keeps its first visible ItemKey row still when things above it change size
  "StickBottom", # a scroll area at its end stays at its end as content grows (chat); starts at the end
  "ItemKey",     # a row's stable key, for Anchor and ScrollToKey
  "ScrollToKey", # a scroll area brings the row with this ItemKey to its top ("key#n" to jump again)
  # Q3 rich text — appended
  "Links",       # Text: clickable byte ranges "start,end;…" (LinkClick says which: y_node_size axis 10)
  "Inline",      # Text: "w,h,path;…" one per U+FFFC in its text: images or emoji inside the line
  "Find",        # Window: find-in-page query (case-insensitive) over Text nodes; count = y_node_size(0, 11)
  "FindIndex",   # Window: which match is current (highlighted strongly, scrolled into view); axis 12 reads it back
  # Q4 smooth input — appended
  "Smooth",      # a scroll area glides to scrollTo / scrollToKey targets instead of jumping
  "Zoomable",    # Image: pinch / Ctrl+wheel zooms (1x-8x), drag pans, double click resets
  # Q6 blocks — appended
  "FocusAt",     # Input/TextArea: "caret#n": each new value focuses it with the caret at that byte
  # Q8 OS integration — appended
  "Frameless",   # Window: no system title bar; the app draws its own (DragRegion, WindowAction)
  "DragRegion",  # a node the window is dragged by (its clickable children stay clickable)
  "WindowAction",# clicking it: 1 minimise, 2 maximise/restore, 3 close, 4 fullscreen
  "Menu",        # Window: the native menubar, "File|New:1|Open:2|-|Quit:3;Edit|Copy:4" (MenuCommand)
  "Badge",       # Window: the count on the taskbar button (0 none)
  "Scheme",      # Window: "myapp" registers myapp:// for this app; links arrive as DeepLink
  # Q9 spelling — appended
  "Spellcheck",  # Input/TextArea: misspelled words get a red underline; right click fires SpellMenu
  "Replace",     # Input/TextArea: "start,end,text#n" — each new value replaces those bytes as an edit (undoable, fires Input)
  # S3D native 3D scenes — appended (PosX..RotZ, Scale, Metalness, Roughness are older)
  "SizeX", "SizeY", "SizeZ",           # a mesh's size in metres (a shape is 1 across)
  "TargetX", "TargetY", "TargetZ",     # where a camera or light points
  "Fov",         # Camera: vertical field of view, degrees
  "Intensity",   # Light: lux (sun) or lumens (point, spot)
  "Shape",       # Mesh: 0 box, 1 sphere, 2 plane, 3 cylinder
  "Glow",        # Mesh: emissive colour 0xRRGGBB (bloom picks it up)
  "Fog",         # Scene3D: fog density (0 none)
  "FogColor",    # Scene3D: 0xRRGGBB
  "Sky",         # Scene3D: sky colour 0xRRGGBB (not set: transparent)
  "Shadows",     # Scene3D: shadow maps on (default) / off; Light: casts shadows
  "Bloom",       # Scene3D: bloom strength (0 off)
  "Ssao",        # Scene3D: ambient occlusion
  "Geometry",    # Mesh: a buffer (y_buf) holding its own vertices and triangles
  "Instances",   # Mesh: a buffer of 4x4 matrices: one copy of the mesh per matrix
  "LightKind",   # Light: 0 sun, 1 point, 2 spot
  "Animation",   # Model in a Scene3D: which of its animations plays (-1 none)
  "Ambient",     # Scene3D: the sky's soft light, lux
  # G-IN game input — appended
  "PointerLock", # Window: the pointer is hidden and held; mouseDelta() gives raw movement (Esc releases)
  # SH1 3D shaders — appended (a Mesh's `shader` is its fragment code: Filament's material language)
  "VertexShader", # Mesh: the body of materialVertex() (move material.worldPosition: waves, wind)
  "Uniforms",     # Mesh: up to 16 numbers "a,b,c,…" the shader reads as materialParams.u[0..3]
  "Unlit",        # Mesh: no lighting: the shader's (or fill's) colour is the colour
  # AU1 synthesis — appended (Volume and Playing are older: volume, and the gate)
  "Wave",         # Synth: 0 sine, 1 square, 2 triangle, 3 saw, 4 white, 5 pink, 6 brown noise
  "Freq",         # Synth: pitch, Hz
  "FilterKind",   # Synth: 0 none, 1 low-pass, 2 high-pass, 3 band-pass
  "Cutoff",       # Synth: the filter's frequency, Hz
  "Resonance",    # Synth: the filter's Q (0.707 flat)
  "Pan",          # Synth: -1 left .. 1 right
  "Attack",       # Synth: seconds to full volume when playing turns on
  "Release",      # Synth: seconds to silence when it turns off
  "Echo",         # Synth: echo delay, seconds (0 none)
  "EchoMix",      # Synth: how loud the echo is, 0..1
  "EchoFeedback", # Synth: how much each echo repeats, 0..0.95
  "Lfo",          # Synth: vibrato rate, Hz
  "LfoDepth",     # Synth: vibrato depth, a fraction of the pitch
  # T3D textures and picking — appended
  "Texture",      # Mesh: an image file (png/jpeg) over its surface, times its fill colour
  "Tiling",       # Mesh: how many times the image repeats across (and down, unless TilingY)
  "TilingY",      # Mesh: how many times it repeats down
  # PH1 physics — appended
  "Body",         # Mesh: 1 fixed, 2 dynamic (falls, collides), 3 kinematic (the app moves it, it pushes)
  "Mass",         # Mesh: kg (not set: from its size)
  "Friction",     # Mesh: 0 ice .. 1 rubber
  "Bounce",       # Mesh: 0 dead .. 1 bouncy
  "Damping",      # Mesh: how fast it slows down in the air
  "Gravity",      # Scene3D: m/s^2 downwards (9.81)
  # LK1 the finish — appended (all on Scene3D; contrast and saturate are FX1's)
  "Taa",          # temporal anti-aliasing (smooth edges, stable detail)
  "Focus",        # depth of field: the distance in focus, metres (0 off)
  "DofBlur",      # depth of field: how strong the blur is
  "Reflections",  # screen-space reflections (wet streets, glass)
  "Vignette",     # darkened corners, 0..1
  "Exposure",     # EV stops (+1 twice as bright)
  "ToneMap",      # 0 ACES, 1 filmic, 2 AgX, 3 neutral, 4 linear
  "FogHeight",    # height fog: where it starts, metres
  "FogFalloff",   # height fog: how fast it thins going up
  # M3D materials — appended (on Mesh; a map is a file, "layer:N" or "pixels:BUF:W:H")
  "NormalMap",    # bumps and grooves without geometry
  "NormalScale",  # how strong the normal map is (1 as drawn)
  "OrmMap",       # occlusion (r), roughness (g), metal (b), like glTF
  "EmissiveMap",  # where it glows, times glow
  "AlphaMode",    # 0 opaque, 1 blended (glass, water), 2 cut out (leaves, fences)
  "AlphaCutoff",  # cut out below this alpha (0.5)
  "Colors",       # a buffer of RGBA bytes: a colour per instance
  # CH1 characters — appended (on Model in a Scene3D)
  "AnimClip",     # Model: the animation playing, by name (play = "Run"); changing it crossfades
  "BlendTime",    # seconds a clip change crossfades over (0.25)
  "AnimSpeed",    # 1 as made, 2 twice as fast, 0 paused
  "AnimTime",     # seconds into the clip, set by the app (not set: the engine's clock)
  # PT1 particles — appended (on Particles; pos/rot place the emitter, it sprays along its up)
  "Rate",         # new particles per second
  "Burst",        # each new value: that many at once (an explosion)
  "Lifetime",     # seconds each lives
  "Speed",        # m/s they leave at
  "Spread",       # degrees around the emitter's up they scatter (180: every way)
  "PartSize",     # metres across when born
  "PartSizeEnd",  # metres across when they die
  "ColorEnd",     # the colour they turn to as they age (fill: when born); they always fade out
  "MaxCount",     # how many at most at once (1000)
  # RT1 cameras into textures — appended
  "Target",       # Camera: draw into the texture of this name (a map can be "view:NAME"); width/height its size
  # DESK the desktop — appended
  "Fullscreen"    # Window: take over the whole screen (the Yantra desktop)
]

const Events* = [
  "Click", "Change", "Submit", "Input", "Focus", "Blur", "Scroll", "TabChange", "SelectionChange", "MediaEnd", "MediaError", "CanvasDraw",
  "Resize",  # Q1: the node's laid-out size changed (read it with y_node_size)
  "ContextMenu", # OV1: right click (or long press) on the node
  "Dismiss", # OV1: an open overlay was dismissed (Escape, a click outside, a menu item chosen)
  "Key",      # KEY1: a key went down with the focus in (or under) the node; read it with y_key
  # P3 media playback — appended
  "TimeUpdate", # the playing position moved (4 a second) or jumped: y_node_size axis 3 = time, 4 = duration
  "MediaReady", # the file is open: its duration (and waveform, if asked) can be read
  # P5 block editing — appended
  "BlockSplit", # Enter in a block: split it at y_node_size axis 6 (the caret byte); the engine then focuses the next block
  "BlockMerge", # Backspace at a block's start: join it onto the one before; the engine then focuses that one
  # P7 canvas — appended: pointer in the node's own px, y_node_size axis 7 = x, 8 = y
  "PointerDown", "PointerMove", "PointerUp",
  # Q3 — appended
  "LinkClick",   # a link in a Text was clicked: y_node_size axis 10 = its index in Links
  # Q6 — appended
  "Command",     # a field with this handler owns undo/redo: y_node_size axis 15 = 1 undo, 2 redo
  # Q8 — appended, all on the window node
  "MenuCommand", # a menubar item: y_node_size(0, 16) = its id
  "SystemTheme", # light/dark or the accent changed: axis 17 (1 light, 2 dark), 18 accent RGB
  "DeepLink",    # myapp://… opened (also at launch): the URL via y_worker_msg (workerMessage())
  # Q9 — appended
  "SpellMenu",   # right click on a misspelled word: "word\tsuggestion\t…" via y_worker_msg; axes 19, 20 its bytes
  # Q11 — appended, on the window
  "CallSignal",  # a call's signaling to carry to the other side, or its state: text via y_worker_msg
  # C4 drag and drop — appended
  "DragStart", "DragOver", "Drop",
  # G-IN game input — appended, on the window
  "Frame"        # every display frame while it has a handler (games): frameDt(), keyHeld, mouseDelta, pad*
]


const Aligns* = [
  "Left", "Center", "Right"
]

const Easings* = [
  "Linear", "InQuad", "OutQuad", "InOutQuad", "InCubic", "OutCubic", "InOutCubic",
  "InQuart", "OutQuart", "InOutQuart", "InQuint", "OutQuint", "InOutQuint",
  "InSine", "OutSine", "InOutSine", "InExpo", "OutExpo", "InOutExpo",
  "InCirc", "OutCirc", "InOutCirc", "InBack", "OutBack", "InOutBack",
  "InElastic", "OutElastic", "InOutElastic", "InBounce", "OutBounce", "InOutBounce",
  # S7 springs — appended: real physics in transitions (velocity carries through a retarget),
  # the matching step response wherever a fixed duration is needed
  "Spring", "SpringGentle", "SpringBouncy", "SpringStiff"
]

type
  PropMeta* = object
    dslName*: string
    wireProp*: string
    propType*: string
    allowedNodes*: string

const PropTable* = [
  PropMeta(dslName: "text", wireProp: "Text", propType: "string", allowedNodes: "Window,Text,Button,Input,Checkbox,Radio,Switch,TabPanel,Tooltip"),
  PropMeta(dslName: "size", wireProp: "FontSize", propType: "int32", allowedNodes: "Text,Button,Input,TextArea,Window,Checkbox,Path"),
  PropMeta(dslName: "fontSize", wireProp: "FontSize", propType: "int32", allowedNodes: "Text,Button,Input,TextArea"),
  PropMeta(dslName: "gap", wireProp: "Spacing", propType: "int32", allowedNodes: "Window,Column,Row,Panel,Group,Stack,Grid,Flex,Page"),
  PropMeta(dslName: "spacing", wireProp: "Spacing", propType: "int32", allowedNodes: "Column,Row,Grid,Flex"),
  PropMeta(dslName: "pad", wireProp: "PadTop", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "padding", wireProp: "PadTop", propType: "int32", allowedNodes: "Window,Column,Row,Panel,Button,Input,Modal"),
  PropMeta(dslName: "width", wireProp: "Width", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "height", wireProp: "Height", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "x", wireProp: "X", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "y", wireProp: "Y", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "visible", wireProp: "Visible", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "opacity", wireProp: "Opacity", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "color", wireProp: "TextColor", propType: "int32", allowedNodes: "*"),   # ink: text, icons, labels
  PropMeta(dslName: "fill", wireProp: "Color", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "radius", wireProp: "Radius", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "border", wireProp: "BorderWidth", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "align", wireProp: "Align", propType: "int32", allowedNodes: "Text,Column,Row"),
  PropMeta(dslName: "source", wireProp: "Source", propType: "string", allowedNodes: "Image,Video,Model,Flex,Chart,Drawer,AppView"),
  PropMeta(dslName: "scale", wireProp: "Scale", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "value", wireProp: "Value", propType: "string", allowedNodes: "Input,TextArea,Slider,Progress,Select"),
  PropMeta(dslName: "checked", wireProp: "Checked", propType: "bool", allowedNodes: "Checkbox,Radio,Switch"),
  PropMeta(dslName: "disabled", wireProp: "Disabled", propType: "bool", allowedNodes: "Button,Input,Checkbox,Radio,Select,Slider,Switch"),
  PropMeta(dslName: "min", wireProp: "Min", propType: "float32", allowedNodes: "Slider,Progress"),
  PropMeta(dslName: "max", wireProp: "Max", propType: "float32", allowedNodes: "Slider,Progress"),
  PropMeta(dslName: "weight", wireProp: "FontWeight", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "textColor", wireProp: "TextColor", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "grow", wireProp: "FlexGrow", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "placeholder", wireProp: "Placeholder", propType: "string", allowedNodes: "Input,TextArea"),
  PropMeta(dslName: "label", wireProp: "Text", propType: "string", allowedNodes: "Checkbox,Switch,Radio"),
  PropMeta(dslName: "borderColor", wireProp: "BorderColor", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "marginTop", wireProp: "MarginTop", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "marginRight", wireProp: "MarginRight", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "marginBottom", wireProp: "MarginBottom", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "marginLeft", wireProp: "MarginLeft", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "padTop", wireProp: "PadTop", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "padRight", wireProp: "PadRight", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "padBottom", wireProp: "PadBottom", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "padLeft", wireProp: "PadLeft", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "minWidth", wireProp: "MinWidth", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "minHeight", wireProp: "MinHeight", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "maxWidth", wireProp: "MaxWidth", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "maxHeight", wireProp: "MaxHeight", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "shrink", wireProp: "FlexShrink", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "alignItems", wireProp: "AlignItems", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "justify", wireProp: "Justify", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "wrap", wireProp: "Wrap", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "absolute", wireProp: "Absolute", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "top", wireProp: "InsetTop", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "right", wireProp: "InsetRight", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "bottom", wireProp: "InsetBottom", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "left", wireProp: "InsetLeft", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "z", wireProp: "ZIndex", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "scroll", wireProp: "Scroll", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "clip", wireProp: "Clip", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "font", wireProp: "FontFamily", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "lineHeight", wireProp: "LineHeight", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "italic", wireProp: "Italic", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "maxLines", wireProp: "MaxLines", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "d", wireProp: "PathData", propType: "string", allowedNodes: "Path"),
  PropMeta(dslName: "stroke", wireProp: "StrokeWidth", propType: "float32", allowedNodes: "Path"),
  PropMeta(dslName: "cursor", wireProp: "Cursor", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "transition", wireProp: "TransDuration", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "ease", wireProp: "TransEasing", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "rotate", wireProp: "RotZ", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "enter", wireProp: "Enter", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "exit", wireProp: "Exit", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "animate", wireProp: "AnimTarget", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "rows", wireProp: "Rows", propType: "int32", allowedNodes: "TextArea"),
  PropMeta(dslName: "fit", wireProp: "Fit", propType: "int32", allowedNodes: "Image,Video"),
  PropMeta(dslName: "loop", wireProp: "Loop", propType: "bool", allowedNodes: "Video,Audio"),
  PropMeta(dslName: "blur", wireProp: "Blur", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "backdropBlur", wireProp: "BackdropBlur", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "blend", wireProp: "Blend", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "saturate", wireProp: "Saturate", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "brightness", wireProp: "Brightness", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "contrast", wireProp: "Contrast", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "shader", wireProp: "Shader", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "columns", wireProp: "GridCols", propType: "string", allowedNodes: "Grid"),
  PropMeta(dslName: "span", wireProp: "Span", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "net", wireProp: "Net", propType: "string", allowedNodes: "Window"),
  PropMeta(dslName: "reveal", wireProp: "Reveal", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "parallax", wireProp: "Parallax", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "spans", wireProp: "Spans", propType: "string", allowedNodes: "Text,TextArea,Input"),
  PropMeta(dslName: "open", wireProp: "ModalOpen", propType: "bool", allowedNodes: "Modal,Drawer,Popover,Menu,ContextMenu"),
  PropMeta(dslName: "closeOnEsc", wireProp: "CloseOnEsc", propType: "bool", allowedNodes: "Modal,Drawer,Popover,Menu,ContextMenu"),
  PropMeta(dslName: "closeOnClickOutside", wireProp: "CloseOnClickOutside", propType: "bool", allowedNodes: "Modal,Drawer,Popover,Menu,ContextMenu"),
  PropMeta(dslName: "placement", wireProp: "Placement", propType: "int32", allowedNodes: "Popover,Menu,Tooltip,Drawer"),
  PropMeta(dslName: "scrollTo", wireProp: "ScrollY", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "stickToEnd", wireProp: "StickToEnd", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "playing", wireProp: "Playing", propType: "bool", allowedNodes: "Video,Audio,Synth"),
  PropMeta(dslName: "seek", wireProp: "SeekTo", propType: "float32", allowedNodes: "Video,Audio"),
  PropMeta(dslName: "volume", wireProp: "Volume", propType: "float32", allowedNodes: "Video,Audio,Synth"),
  PropMeta(dslName: "muted", wireProp: "Muted", propType: "bool", allowedNodes: "Video,Audio"),
  PropMeta(dslName: "waveform", wireProp: "Waveform", propType: "int32", allowedNodes: "Audio"),
  PropMeta(dslName: "block", wireProp: "Block", propType: "bool", allowedNodes: "Input,TextArea"),
  PropMeta(dslName: "sticky", wireProp: "Sticky", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "stickyLeft", wireProp: "StickyLeft", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "draw", wireProp: "Draw", propType: "string", allowedNodes: "Canvas"),
  PropMeta(dslName: "direction", wireProp: "Direction", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "anchor", wireProp: "Anchor", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "stickBottom", wireProp: "StickBottom", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "itemKey", wireProp: "ItemKey", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "scrollTo", wireProp: "ScrollY", propType: "float32", allowedNodes: "*"),
  PropMeta(dslName: "scrollToKey", wireProp: "ScrollToKey", propType: "string", allowedNodes: "*"),
  PropMeta(dslName: "links", wireProp: "Links", propType: "string", allowedNodes: "Text"),
  PropMeta(dslName: "inline", wireProp: "Inline", propType: "string", allowedNodes: "Text"),
  PropMeta(dslName: "find", wireProp: "Find", propType: "string", allowedNodes: "Window"),
  PropMeta(dslName: "findIndex", wireProp: "FindIndex", propType: "int32", allowedNodes: "Window"),
  PropMeta(dslName: "smooth", wireProp: "Smooth", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "zoomable", wireProp: "Zoomable", propType: "bool", allowedNodes: "Image"),
  PropMeta(dslName: "focusAt", wireProp: "FocusAt", propType: "string", allowedNodes: "Input,TextArea"),
  PropMeta(dslName: "frameless", wireProp: "Frameless", propType: "bool", allowedNodes: "Window"),
  PropMeta(dslName: "dragRegion", wireProp: "DragRegion", propType: "bool", allowedNodes: "*"),
  PropMeta(dslName: "windowAction", wireProp: "WindowAction", propType: "int32", allowedNodes: "*"),
  PropMeta(dslName: "menu", wireProp: "Menu", propType: "string", allowedNodes: "Window"),
  PropMeta(dslName: "badge", wireProp: "Badge", propType: "int32", allowedNodes: "Window"),
  PropMeta(dslName: "scheme", wireProp: "Scheme", propType: "string", allowedNodes: "Window"),
  PropMeta(dslName: "spellcheck", wireProp: "Spellcheck", propType: "bool", allowedNodes: "Input,TextArea"),
  PropMeta(dslName: "replace", wireProp: "Replace", propType: "string", allowedNodes: "Input,TextArea"),
  PropMeta(dslName: "posX", wireProp: "PosX", propType: "float32", allowedNodes: "Mesh,Model,Camera,Light,Particles"),
  PropMeta(dslName: "posY", wireProp: "PosY", propType: "float32", allowedNodes: "Mesh,Model,Camera,Light,Particles"),
  PropMeta(dslName: "posZ", wireProp: "PosZ", propType: "float32", allowedNodes: "Mesh,Model,Camera,Light,Particles"),
  PropMeta(dslName: "rotX", wireProp: "RotX", propType: "float32", allowedNodes: "Mesh,Model,Particles"),
  PropMeta(dslName: "rotY", wireProp: "RotY", propType: "float32", allowedNodes: "Mesh,Model"),
  PropMeta(dslName: "rotZ", wireProp: "RotZ", propType: "float32", allowedNodes: "Mesh,Model,Particles"),
  PropMeta(dslName: "sizeX", wireProp: "SizeX", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "sizeY", wireProp: "SizeY", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "sizeZ", wireProp: "SizeZ", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "metal", wireProp: "Metalness", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "rough", wireProp: "Roughness", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "targetX", wireProp: "TargetX", propType: "float32", allowedNodes: "Camera,Light"),
  PropMeta(dslName: "targetY", wireProp: "TargetY", propType: "float32", allowedNodes: "Camera,Light"),
  PropMeta(dslName: "targetZ", wireProp: "TargetZ", propType: "float32", allowedNodes: "Camera,Light"),
  PropMeta(dslName: "fov", wireProp: "Fov", propType: "float32", allowedNodes: "Camera"),
  PropMeta(dslName: "intensity", wireProp: "Intensity", propType: "float32", allowedNodes: "Light"),
  PropMeta(dslName: "shape", wireProp: "Shape", propType: "int32", allowedNodes: "Mesh"),
  PropMeta(dslName: "glow", wireProp: "Glow", propType: "int32", allowedNodes: "Mesh,Particles"),
  PropMeta(dslName: "fog", wireProp: "Fog", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "fogColor", wireProp: "FogColor", propType: "int32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "sky", wireProp: "Sky", propType: "int32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "shadows", wireProp: "Shadows", propType: "bool", allowedNodes: "Scene3D,Light"),
  PropMeta(dslName: "bloom", wireProp: "Bloom", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "ssao", wireProp: "Ssao", propType: "bool", allowedNodes: "Scene3D"),
  PropMeta(dslName: "geometry", wireProp: "Geometry", propType: "int32", allowedNodes: "Mesh"),
  PropMeta(dslName: "instances", wireProp: "Instances", propType: "int32", allowedNodes: "Mesh,Model"),
  PropMeta(dslName: "lightKind", wireProp: "LightKind", propType: "int32", allowedNodes: "Light"),
  PropMeta(dslName: "animation", wireProp: "Animation", propType: "int32", allowedNodes: "Model"),
  PropMeta(dslName: "ambient", wireProp: "Ambient", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "pointerLock", wireProp: "PointerLock", propType: "bool", allowedNodes: "Window"),
  PropMeta(dslName: "vertex", wireProp: "VertexShader", propType: "string", allowedNodes: "Mesh"),
  PropMeta(dslName: "uniforms", wireProp: "Uniforms", propType: "string", allowedNodes: "Mesh"),
  PropMeta(dslName: "unlit", wireProp: "Unlit", propType: "bool", allowedNodes: "Mesh"),
  PropMeta(dslName: "wave", wireProp: "Wave", propType: "int32", allowedNodes: "Synth"),
  PropMeta(dslName: "freq", wireProp: "Freq", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "filter", wireProp: "FilterKind", propType: "int32", allowedNodes: "Synth"),
  PropMeta(dslName: "cutoff", wireProp: "Cutoff", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "resonance", wireProp: "Resonance", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "pan", wireProp: "Pan", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "attack", wireProp: "Attack", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "release", wireProp: "Release", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "echo", wireProp: "Echo", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "echoMix", wireProp: "EchoMix", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "echoFeedback", wireProp: "EchoFeedback", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "lfo", wireProp: "Lfo", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "lfoDepth", wireProp: "LfoDepth", propType: "float32", allowedNodes: "Synth"),
  PropMeta(dslName: "texture", wireProp: "Texture", propType: "string", allowedNodes: "Mesh,Particles"),
  PropMeta(dslName: "tiling", wireProp: "Tiling", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "tilingY", wireProp: "TilingY", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "body", wireProp: "Body", propType: "int32", allowedNodes: "Mesh"),
  PropMeta(dslName: "mass", wireProp: "Mass", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "friction", wireProp: "Friction", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "bounce", wireProp: "Bounce", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "damping", wireProp: "Damping", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "gravity", wireProp: "Gravity", propType: "float32", allowedNodes: "Scene3D,Particles"),
  PropMeta(dslName: "taa", wireProp: "Taa", propType: "bool", allowedNodes: "Scene3D"),
  PropMeta(dslName: "focus", wireProp: "Focus", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "dofBlur", wireProp: "DofBlur", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "reflections", wireProp: "Reflections", propType: "bool", allowedNodes: "Scene3D"),
  PropMeta(dslName: "vignette", wireProp: "Vignette", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "exposure", wireProp: "Exposure", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "toneMap", wireProp: "ToneMap", propType: "int32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "fogHeight", wireProp: "FogHeight", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "fogFalloff", wireProp: "FogFalloff", propType: "float32", allowedNodes: "Scene3D"),
  PropMeta(dslName: "normalMap", wireProp: "NormalMap", propType: "string", allowedNodes: "Mesh"),
  PropMeta(dslName: "normalScale", wireProp: "NormalScale", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "ormMap", wireProp: "OrmMap", propType: "string", allowedNodes: "Mesh"),
  PropMeta(dslName: "emissiveMap", wireProp: "EmissiveMap", propType: "string", allowedNodes: "Mesh"),
  PropMeta(dslName: "alphaMode", wireProp: "AlphaMode", propType: "int32", allowedNodes: "Mesh"),
  PropMeta(dslName: "alphaCutoff", wireProp: "AlphaCutoff", propType: "float32", allowedNodes: "Mesh"),
  PropMeta(dslName: "colors", wireProp: "Colors", propType: "int32", allowedNodes: "Mesh"),
  PropMeta(dslName: "play", wireProp: "AnimClip", propType: "string", allowedNodes: "Model"),
  PropMeta(dslName: "blendTime", wireProp: "BlendTime", propType: "float32", allowedNodes: "Model"),
  PropMeta(dslName: "animSpeed", wireProp: "AnimSpeed", propType: "float32", allowedNodes: "Model"),
  PropMeta(dslName: "animTime", wireProp: "AnimTime", propType: "float32", allowedNodes: "Model"),
  PropMeta(dslName: "rate", wireProp: "Rate", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "burst", wireProp: "Burst", propType: "string", allowedNodes: "Particles"),
  PropMeta(dslName: "lifetime", wireProp: "Lifetime", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "speed", wireProp: "Speed", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "spread", wireProp: "Spread", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "partSize", wireProp: "PartSize", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "partSizeEnd", wireProp: "PartSizeEnd", propType: "float32", allowedNodes: "Particles"),
  PropMeta(dslName: "colorEnd", wireProp: "ColorEnd", propType: "int32", allowedNodes: "Particles"),
  PropMeta(dslName: "maxCount", wireProp: "MaxCount", propType: "int32", allowedNodes: "Particles"),
  PropMeta(dslName: "target", wireProp: "Target", propType: "string", allowedNodes: "Camera"),
  PropMeta(dslName: "fullscreen", wireProp: "Fullscreen", propType: "bool", allowedNodes: "Window"),
  PropMeta(dslName: "focusBorder", wireProp: "FocusBorder", propType: "int32", allowedNodes: "Input,TextArea")
]

proc findPropMeta*(dslName: string): int =
  let norm = dslName.toLowerAscii().replace("_", "")
  for i, m in PropTable:
    if m.dslName.toLowerAscii().replace("_", "") == norm:
      return i
  return -1

proc isPropAllowedOnNode*(dslName: string; nodeKind: string): bool =
  let idx = findPropMeta(dslName)
  if idx < 0:
    return false
  let allowed = PropTable[idx].allowedNodes
  if allowed == "*":
    return true
  for item in allowed.split(','):
    if item.strip().toLowerAscii() == nodeKind.toLowerAscii():
      return true
  return false

proc editDistance(a, b: string): int =
  let m = a.len
  let n = b.len
  var dp = newSeq[int]((m + 1) * (n + 1))
  for i in 0 .. m: dp[i * (n + 1)] = i
  for j in 0 .. n: dp[j] = j
  for i in 1 .. m:
    for j in 1 .. n:
      let cost = if a[i - 1] == b[j - 1]: 0 else: 1
      let delCost = dp[(i - 1) * (n + 1) + j] + 1
      let insCost = dp[i * (n + 1) + (j - 1)] + 1
      let subCost = dp[(i - 1) * (n + 1) + (j - 1)] + cost
      dp[i * (n + 1) + j] = min(delCost, min(insCost, subCost))
  result = dp[m * (n + 1) + n]

proc suggestPropName*(unknownName: string; nodeKind: string = "*"): string =
  let target = unknownName.toLowerAscii()
  var bestName = ""
  var bestDist = 3
  for m in PropTable:
    if nodeKind == "*" or m.allowedNodes == "*" or isPropAllowedOnNode(m.dslName, nodeKind):
      let d = editDistance(target, m.dslName.toLowerAscii())
      if d < bestDist:
        bestDist = d
        bestName = m.dslName
  result = bestName

proc formatPropsMarkdown*(): string =
  result = "# Yantra DSL Property Reference\n\n"
  result.add "Generated automatically by `protocol/gen.nim` from `protocol/schema.nim` (`PropTable`). Do not edit by hand.\n\n"
  result.add "| DSL Prop | Wire Prop | Type | Allowed Nodes |\n"
  result.add "|---|---|---|---|\n"
  for m in PropTable:
    result.add "| `" & m.dslName & "` | `p" & m.wireProp & "` | `" & m.propType & "` | `" & m.allowedNodes & "` |\n"
