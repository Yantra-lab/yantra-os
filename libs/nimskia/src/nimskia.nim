## nimskia — Skia for the Yantra native engine (architecture §5).
##
## A thin Nim layer over `skia_shim.cpp`: a raster canvas over caller-owned
## pixels, rounded rects, clipping and paragraph text. Skia itself comes from
## MSYS2 (`mingw-w64-x86_64-skia`), installed into third_party/msys64.

import std/os

const shimDir = currentSourcePath().parentDir
when defined(emscripten):
  # the browser build: Skia from source, built for wasm; tools/build-web.sh passes where it is
  # (paths cannot be joined here: the target OS is not Windows, so `/` would mangle them)
  const skiaSrc {.strdefine.} = ""
  const skiaOut = skiaSrc & "/out/wasm"
  {.compile("skia_shim.cpp", "-std=c++20 -O2 -DNDEBUG -DSK_RELEASE -I\"" & skiaSrc & "\"").}
  {.passL: "\"" & skiaOut & "/libskparagraph.a\" \"" & skiaOut & "/libskshaper.a\" \"" & skiaOut &
    "/libskunicode_icu.a\" \"" & skiaOut & "/libskunicode_core.a\" \"" & skiaOut & "/libskia.a\" \"" & skiaOut &
    "/libicu.a\" \"" & skiaOut & "/libharfbuzz.a\" \"" & skiaOut & "/libfreetype2.a\" \"" & skiaOut &
    "/libpng.a\" \"" & skiaOut & "/libzlib.a\" \"" & skiaOut & "/libbrotli.a\" \"" & skiaOut & "/libjpeg.a\" \"" &
    skiaOut & "/libwuffs.a\"".}
else:
  const
    skiaInc = shimDir / ".." / ".." / ".." / "third_party" / "msys64" / "mingw64" / "include" / "skia"
    skiaPriv = shimDir / ".." / ".." / ".." / "third_party" / "skia-src-m143"   # see fetch_private_headers.sh
  {.compile("skia_shim.cpp", "-std=c++17 -O2 -DNDEBUG -DSK_RELEASE -I\"" & skiaInc & "\" -I\"" & skiaPriv & "\"").}
  {.passL: "-lskparagraph -lskshaper -lskunicode_icu -lskunicode_core -lskia -licuuc -licuin -lharfbuzz -lstdc++ -lgdi32 -lopengl32 -lole32 -loleaut32 -luuid -lusp10 -ldwrite -lpthread".}

type
  Canvas* = distinct pointer

proc yk_canvas_new(pixels: pointer; w, h, rowBytes: cint): pointer {.importc, cdecl.}
proc yk_canvas_free(c: pointer) {.importc, cdecl.}
proc yk_clear(c: pointer; argb: uint32) {.importc, cdecl.}
proc yk_save(c: pointer) {.importc, cdecl.}
proc yk_restore(c: pointer) {.importc, cdecl.}
proc yk_translate(c: pointer; x, y: cfloat) {.importc, cdecl.}
proc yk_scale(c: pointer; s: cfloat) {.importc, cdecl.}
proc yk_rotate(c: pointer; deg: cfloat) {.importc, cdecl.}
proc yk_clip_rect(c: pointer; x, y, w, h: cfloat) {.importc, cdecl.}
proc yk_rrect(c: pointer; x, y, w, h, r: cfloat; argb: uint32) {.importc, cdecl.}
proc yk_rrect_stroke(c: pointer; x, y, w, h, r, width: cfloat; argb: uint32) {.importc, cdecl.}
proc yk_polyline(c: pointer; xy: ptr cfloat; n: cint; width: cfloat; argb: uint32) {.importc, cdecl.}
proc yk_text_measure(s: cstring; len: cint; size: cfloat; weight: cint; maxW: cfloat;
                     outH: ptr cfloat): cfloat {.importc, cdecl.}
proc yk_text_draw(c: pointer; s: cstring; len: cint; size: cfloat; weight: cint; maxW: cfloat;
                  x, y: cfloat; argb: uint32; align: cint) {.importc, cdecl.}
proc yk_text_caret_x(s: cstring; len, bytes: cint; size: cfloat; weight: cint): cfloat {.importc, cdecl.}

proc newCanvas*(pixels: pointer; w, h, rowBytes: int): Canvas =
  ## A canvas that draws straight into `pixels` (32-bit premultiplied, native order).
  Canvas(yk_canvas_new(pixels, cint(w), cint(h), cint(rowBytes)))

proc free*(c: Canvas) = yk_canvas_free(pointer(c))
proc clear*(c: Canvas; argb: uint32) = yk_clear(pointer(c), argb)
proc save*(c: Canvas) = yk_save(pointer(c))
proc restore*(c: Canvas) = yk_restore(pointer(c))
proc translate*(c: Canvas; x, y: float32) = yk_translate(pointer(c), x, y)
proc scale*(c: Canvas; s: float32) = yk_scale(pointer(c), s)
proc rotate*(c: Canvas; degrees: float32) = yk_rotate(pointer(c), degrees)  ## clockwise, about the origin
proc clipRect*(c: Canvas; x, y, w, h: float32) = yk_clip_rect(pointer(c), x, y, w, h)

proc fillRRect*(c: Canvas; x, y, w, h, r: float32; argb: uint32) =
  yk_rrect(pointer(c), x, y, w, h, r, argb)

proc strokeRRect*(c: Canvas; x, y, w, h, r, width: float32; argb: uint32) =
  yk_rrect_stroke(pointer(c), x, y, w, h, r, width, argb)

proc measureText*(s: string; size: float32; weight = 400; maxW = 0'f32): (float32, float32) =
  ## (width, height) the text needs when wrapped at `maxW` (0 = one line).
  var h: cfloat
  let w = yk_text_measure(s.cstring, cint(s.len), size, cint(weight), maxW, addr h)
  (float32(w), float32(h))

proc drawText*(c: Canvas; s: string; x, y, size: float32; argb: uint32; weight = 400;
               maxW = 0'f32; align = 0) =
  ## Draws `s` with its top-left at (x, y). align: 0 left, 1 center, 2 right (within maxW).
  yk_text_draw(pointer(c), s.cstring, cint(s.len), size, cint(weight), maxW, x, y, argb, cint(align))

proc caretX*(s: string; bytes: int; size: float32; weight = 400): float32 =
  ## Horizontal position of a caret placed after `bytes` bytes of `s`.
  yk_text_caret_x(s.cstring, cint(s.len), cint(bytes), size, cint(weight))

proc strokePolyline*(c: Canvas; pts: openArray[(float32, float32)]; width: float32; argb: uint32) =
  ## An open line through `pts`, round caps and joins (ticks, chevrons, dividers).
  if pts.len < 2: return
  var xy = newSeq[cfloat](pts.len * 2)
  for i, (x, y) in pts:
    xy[2 * i] = x
    xy[2 * i + 1] = y
  yk_polyline(pointer(c), addr xy[0], cint(pts.len), width, argb)

# --- E5: the style system ------------------------------------------------------

type TextStyle* = object
  ## Text options beyond size and weight. Zero values mean "the default".
  family*: string
  italic*: bool
  lineHeight*: float32   ## multiple of the size
  maxLines*: int         ## 0 = unlimited; otherwise ends in an ellipsis
  rtl*: bool             ## right-to-left paragraph (P9): bidi base direction, start = right
  inline*: string        ## Q3: "w,h;w,h": the boxes each U+FFFC in the text becomes (inline images, emoji)
  spans*: string         ## styled runs: "start,end,flags,argb,size;…" (bytes; flags 1 bold,
                         ## 2 italic, 4 underline, 8 strike, 16 mono; argb/size 0 = inherit)

proc fam(st: TextStyle): string =
  ## The family string the shim reads; runs travel after a record separator (0x1E), and a
  ## leading group separator (0x1D) means right-to-left.
  result = if st.spans.len == 0: st.family else: st.family & $chr(0x1e) & st.spans
  if st.inline.len > 0: result.add $chr(0x1c) & st.inline
  if st.rtl: result = $chr(0x1d) & result

proc yk_text_measure2(s: cstring; len: cint; size: cfloat; weight: cint; maxW: cfloat; outH: ptr cfloat;
                      family: cstring; italic: cint; lineHeight: cfloat; maxLines: cint): cfloat {.importc, cdecl.}
proc yk_text_draw2(c: pointer; s: cstring; len: cint; size: cfloat; weight: cint; maxW: cfloat;
                   x, y: cfloat; argb: uint32; align: cint;
                   family: cstring; italic: cint; lineHeight: cfloat; maxLines: cint) {.importc, cdecl.}
proc yk_rrect_gradient(c: pointer; x, y, w, h, r: cfloat; a, b: uint32; angle: cfloat) {.importc, cdecl.}
proc yk_shadow(c: pointer; x, y, w, h, r, dx, dy, blur: cfloat; argb: uint32) {.importc, cdecl.}
proc yk_save_alpha(c: pointer; alpha: cfloat) {.importc, cdecl.}
proc yk_svg_path(c: pointer; d: cstring; x, y, scale, strokeWidth: cfloat; argb: uint32) {.importc, cdecl.}

proc measureText*(s: string; size: float32; weight: int; maxW: float32; st: TextStyle): (float32, float32) =
  var h: cfloat
  let w = yk_text_measure2(s.cstring, cint(s.len), size, cint(weight), maxW, addr h,
                           st.fam.cstring, cint(st.italic), st.lineHeight, cint(st.maxLines))
  (float32(w), float32(h))

proc drawText*(c: Canvas; s: string; x, y, size: float32; argb: uint32; weight: int; maxW: float32;
               align: int; st: TextStyle) =
  yk_text_draw2(pointer(c), s.cstring, cint(s.len), size, cint(weight), maxW, x, y, argb, cint(align),
                st.fam.cstring, cint(st.italic), st.lineHeight, cint(st.maxLines))

proc fillGradient*(c: Canvas; x, y, w, h, r: float32; a, b: uint32; angle: float32) =
  ## A linear gradient from `a` to `b`; angle in degrees, 90 = top to bottom.
  yk_rrect_gradient(pointer(c), x, y, w, h, r, a, b, angle)

proc shadow*(c: Canvas; x, y, w, h, r, dx, dy, blur: float32; argb: uint32) =
  ## A soft shadow for a rounded rect (drawn before the rect itself).
  yk_shadow(pointer(c), x, y, w, h, r, dx, dy, blur, argb)

proc saveAlpha*(c: Canvas; alpha: float32) =
  ## Fades everything until the matching `restore` as one layer.
  yk_save_alpha(pointer(c), alpha)

proc svgPath*(c: Canvas; d: string; x, y, scale, strokeWidth: float32; argb: uint32) =
  ## SVG path data at (x, y) scaled by `scale`; stroked when strokeWidth > 0.
  yk_svg_path(pointer(c), d.cstring, x, y, scale, strokeWidth, argb)

# --- T1: text editing geometry -------------------------------------------------

proc yk_text_caret(s: cstring; len, bytes: cint; size: cfloat; weight: cint; maxW: cfloat; family: cstring;
                   italic: cint; lineHeight: cfloat; x, y, h: ptr cfloat) {.importc, cdecl.}
proc yk_text_hit(s: cstring; len: cint; x, y, size: cfloat; weight: cint; maxW: cfloat; family: cstring;
                 italic: cint; lineHeight: cfloat): cint {.importc, cdecl.}
proc yk_text_rects(s: cstring; len, a, b: cint; size: cfloat; weight: cint; maxW: cfloat; family: cstring;
                   italic: cint; lineHeight: cfloat; outp: ptr cfloat; maxRects: cint): cint {.importc, cdecl.}

proc caretAt*(s: string; bytes: int; size: float32; weight: int; maxW: float32; st: TextStyle): (float32, float32, float32) =
  ## Where the caret goes after `bytes` bytes of `s` laid out at `maxW` (0 = one line): x, top, height.
  var x, y, h: cfloat
  yk_text_caret(s.cstring, cint(s.len), cint(bytes), size, cint(weight), maxW, st.fam.cstring, cint(st.italic),
                st.lineHeight, addr x, addr y, addr h)
  (float32(x), float32(y), float32(h))

proc textHit*(s: string; x, y, size: float32; weight: int; maxW: float32; st: TextStyle): int =
  ## The byte offset in `s` nearest to point (x, y) of the laid-out text.
  int(yk_text_hit(s.cstring, cint(s.len), x, y, size, cint(weight), maxW, st.fam.cstring, cint(st.italic),
                  st.lineHeight))

proc textRects*(s: string; a, b: int; size: float32; weight: int; maxW: float32; st: TextStyle): seq[(float32, float32, float32, float32)] =
  ## Rectangles covering bytes [a, b) of the laid-out text: a selection highlight.
  var buf: array[256, cfloat]
  let n = yk_text_rects(s.cstring, cint(s.len), cint(a), cint(b), size, cint(weight), maxW, st.fam.cstring,
                        cint(st.italic), st.lineHeight, addr buf[0], 64)
  for i in 0 ..< int(n): result.add (float32(buf[4*i]), float32(buf[4*i+1]), float32(buf[4*i+2]), float32(buf[4*i+3]))

# --- U8: pixels from elsewhere -------------------------------------------------

proc yk_draw_pixels(c: pointer; pixels: pointer; pw, ph: cint; x, y, w, h, r: cfloat; fit: cint) {.importc, cdecl.}

proc drawPixels*(c: Canvas; pixels: pointer; pw, ph: int; x, y, w, h, r: float32; fit = 0) =
  ## Draws a BGRA buffer (a decoded video frame) into a box: fit 0 contain, 1 cover, 2 fill.
  yk_draw_pixels(pointer(c), pixels, cint(pw), cint(ph), x, y, w, h, r, cint(fit))

# --- FX1: effects ------------------------------------------------------------------

proc yk_save_fx(c: pointer; x, y, w, h, r, blur, backdrop: cfloat; blend: cint; saturate, brightness, contrast,
                alpha: cfloat): cint {.importc, cdecl.}
proc yk_shader_rrect(c: pointer; src: cstring; x, y, w, h, r, time: cfloat; err: cstring; cap: cint): cint {.importc, cdecl.}
proc yk_shader_uses_time(src: cstring): cint {.importc, cdecl.}

type Fx* = object
  ## A node's effects. Zero values mean "none".
  blur*, backdrop*: float32       ## px: blur of the node itself; blur of what is behind it (glass)
  blend*: int                     ## an SkBlendMode; -1 = normal
  saturate*, brightness*, contrast*: float32   ## 1 = unchanged
  alpha*: float32

proc saveFx*(c: Canvas; x, y, w, h, r: float32; fx: Fx): int =
  ## Starts a layer with the effects; call `restore` the returned number of times.
  int(yk_save_fx(pointer(c), x, y, w, h, r, fx.blur, fx.backdrop, cint(fx.blend), fx.saturate, fx.brightness,
                 fx.contrast, fx.alpha))

proc shaderRRect*(c: Canvas; src: string; x, y, w, h, r, time: float32): string =
  ## Fills a rounded rect with an SkSL shader ("" on success, else the compile error).
  var err = newString(512)
  if yk_shader_rrect(pointer(c), src.cstring, x, y, w, h, r, time, err.cstring, cint(err.len)) == 1: ""
  else: $err.cstring

proc shaderUsesTime*(src: string): int = int(yk_shader_uses_time(src.cstring))
  ## 1 if the shader reads `time` (it animates), 0 if not, -1 if it does not compile.

# --- D1: PDF documents -------------------------------------------------------------

proc yk_pdf_open(path, title, author: cstring): pointer {.importc, cdecl.}
proc yk_pdf_page(h: pointer; w, hgt: cfloat): pointer {.importc, cdecl.}
proc yk_pdf_end_page(h: pointer) {.importc, cdecl.}
proc yk_pdf_close(h: pointer) {.importc, cdecl.}

type PdfDoc* = object
  h: pointer
  pages*: int

proc openPdf*(path: string; title = ""; author = ""): PdfDoc =
  ## A PDF to draw pages into (vector: shapes stay shapes, text stays text).
  let h = yk_pdf_open(path.cstring, title.cstring, author.cstring)
  if h == nil: raise newException(IOError, "cannot write " & path)
  PdfDoc(h: h)

proc beginPage*(d: var PdfDoc; w, h: float32): Canvas =
  ## A page of w x h points (1/72 inch); draw it with the canvas, then `endPage`.
  ## The canvas belongs to the document: do not `free` it.
  inc d.pages
  Canvas(yk_pdf_page(d.h, w, h))

proc endPage*(d: PdfDoc) = yk_pdf_end_page(d.h)

proc close*(d: var PdfDoc) =
  if d.h != nil:
    yk_pdf_close(d.h)
    d.h = nil

# --- U5: the GPU ---------------------------------------------------------------------

proc yk_gpu_new(): pointer {.importc, cdecl.}
proc yk_gpu_free(ctx: pointer) {.importc, cdecl.}
proc yk_gpu_window_surface(ctx: pointer; w, h: cint): pointer {.importc, cdecl.}
proc yk_gpu_offscreen(ctx: pointer; w, h: cint): pointer {.importc, cdecl.}
proc yk_surface_canvas(s: pointer): pointer {.importc, cdecl.}
proc yk_surface_free(s: pointer) {.importc, cdecl.}
proc yk_gpu_flush(ctx: pointer; sync: cint) {.importc, cdecl.}
proc yk_surface_read(s, pixels: pointer; w, h: cint): cint {.importc, cdecl.}

type
  Gpu* = distinct pointer        ## Skia's GPU context on the current OpenGL context
  Surface* = distinct pointer    ## something a GPU frame is drawn into

proc newGpu*(): Gpu = Gpu(yk_gpu_new())
  ## Needs an OpenGL context current on this thread (nimsdl3 `openGlWindow`).
proc isNil*(g: Gpu): bool = pointer(g) == nil
proc isNil*(s: Surface): bool = pointer(s) == nil
proc free*(g: Gpu) = yk_gpu_free(pointer(g))
proc windowSurface*(g: Gpu; w, h: int): Surface = Surface(yk_gpu_window_surface(pointer(g), cint(w), cint(h)))
proc offscreen*(g: Gpu; w, h: int): Surface = Surface(yk_gpu_offscreen(pointer(g), cint(w), cint(h)))
proc canvas*(s: Surface): Canvas = Canvas(yk_surface_canvas(pointer(s)))
  ## The surface's canvas (owned by the surface: do not `free` it).
proc free*(s: Surface) = yk_surface_free(pointer(s))
proc flush*(g: Gpu; wait = false) = yk_gpu_flush(pointer(g), cint(wait))
proc readPixels*(s: Surface; pixels: pointer; w, h: int): bool = yk_surface_read(pointer(s), pixels, cint(w), cint(h)) == 1
# --- Image support (N1) --------------------------------------------------------

proc yk_write_png(path: cstring; w, h: cint; argb: uint32): bool {.importc, cdecl.}
proc yk_image_info(path: cstring; outW, outH: ptr cint): bool {.importc, cdecl.}
proc yk_draw_image(c: pointer; path: cstring; x, y, w, h, r: cfloat; fit: cint) {.importc, cdecl.}

proc writePng*(path: string; w, h: int; argb: uint32): bool =
  ## Creates a solid PNG file with the given dimensions and argb colour.
  yk_write_png(path.cstring, cint(w), cint(h), argb)

proc imageInfo*(path: string): (int, int) =
  ## Queries image dimensions (width, height) without full draw.
  var w, h: cint
  if yk_image_info(path.cstring, addr w, addr h):
    (int(w), int(h))
  else:
    (0, 0)

proc drawImage*(c: Canvas; path: string; x, y, w, h, r: float32; fit: int = 0) =
  ## Draws an image with contain (fit=0), cover (fit=1), or fill (fit=2) and optional corner radius r.
  yk_draw_image(pointer(c), path.cstring, x, y, w, h, r, cint(fit))


# --- the image pipeline (P2): decode off the UI thread, at the drawn size, LRU-capped ------
proc yk_img_draw(c: pointer; path: cstring; x, y, w, h, r: cfloat; fit: cint; alpha: cfloat; tMs: cdouble;
                 level, sync: cint): cint {.importc, cdecl.}
proc yk_image_frames(path: cstring): cint {.importc, cdecl.}
proc yk_img_generation(): cint {.importc, cdecl.}
proc yk_img_cache_limit(bytes: clonglong) {.importc, cdecl.}
proc yk_img_stats(count: ptr cint; bytes: ptr clonglong; pending: ptr cint) {.importc, cdecl.}
proc yk_img_wait(timeoutMs: cint): bool {.importc, cdecl.}
proc yk_img_forget(path: cstring) {.importc, cdecl.}

const
  imgFailed* = -1     ## not an image Skia can decode (nothing drawn)
  imgLoading* = 0     ## queued or decoding: nothing drawn yet
  imgDrawn* = 1       ## drawn at the right size
  imgAnimated* = 2    ## drawn; animated, so draw again for the next frame
  imgStandIn* = 3     ## drawn from another size while the right one decodes

proc drawImageAsync*(c: Canvas; path: string; x, y, w, h, r: float32; fit = 0; alpha = 1'f32; tMs = 0.0;
                     sync = false; level = -1): int =
  ## Draws from the image cache. The decode size is the smallest power-of-two reduction
  ## covering the size the image lands on the device (`level` >= 0 forces one: 0 = full).
  ## Not cached yet: `sync` decodes now; otherwise a worker decodes it (see the constants).
  ## `tMs` picks an animated image's frame; `alpha` fades it.
  int(yk_img_draw(pointer(c), path.cstring, x, y, w, h, r, cint(fit), alpha, tMs, cint(level), cint(sync)))

proc imageFrames*(path: string): int = int(yk_image_frames(path.cstring))
  ## 1 for a still, more for an animation, 0 if Skia can't read it (header only).
proc imageGeneration*(): int = int(yk_img_generation())
  ## Bumps whenever a background decode finishes: images that were loading can draw now.
proc setImageCacheLimit*(bytes: int) = yk_img_cache_limit(clonglong(bytes))
  ## The decoded-pixel budget (default 128 MB); least recently drawn images go first.
proc imageCacheStats*(): tuple[count: int, bytes: int, pending: int] =
  var c, p: cint
  var b: clonglong
  yk_img_stats(addr c, addr b, addr p)
  (int(c), int(b), int(p))
proc waitImages*(timeoutMs = 5000): bool = yk_img_wait(cint(timeoutMs))
  ## Blocks until every queued decode is done (tests); false on timeout.
proc forgetImage*(path: string) = yk_img_forget(path.cstring)
  ## Drops what is cached for a file that changed.

# --- canvas node (P7) --------------------------------------------------------------------
proc yk_canvas_run(c: pointer; cmds: cstring; len: cint; ox, oy, w, h: cfloat; assetDir: cstring; tMs: cdouble): cint {.importc, cdecl.}
proc drawCommands*(c: Canvas; cmds: string; x, y, w, h: float32; assetDir: string; tMs = 0.0): bool =
  ## Replays a canvas node's command list (format: skia_shim.cpp, yk_canvas_run) at (x, y),
  ## clipped to w x h. True if an image in it is loading or animated (draw again later).
  yk_canvas_run(pointer(c), cmds.cstring, cint(cmds.len), x, y, w, h, assetDir.cstring, tMs) == 1

proc yk_save_pixels(path: cstring; bgra: pointer; w, h: cint): bool {.importc, cdecl.}
proc savePixels*(path: string; bgra: pointer; w, h: int): bool = yk_save_pixels(path.cstring, bgra, cint(w), cint(h))
  ## Writes BGRA pixels to a .png (or .jpg/.jpeg) file.

proc yk_text_placeholders(s: cstring; len: cint; size: cfloat; weight: cint; maxW: cfloat; align: cint; family: cstring;
                          italic: cint; lineHeight: cfloat; maxLines: cint; outp: ptr cfloat; max: cint): cint {.importc, cdecl.}
proc inlineRects*(s: string; size: float32; weight: int; maxW: float32; align: int; st: TextStyle): seq[(float32, float32, float32, float32)] =
  ## Where the text's inline objects (its U+FFFC characters, sized by `st.inline`) were laid out.
  var buf: array[256, cfloat]
  let n = yk_text_placeholders(s.cstring, cint(s.len), size, cint(weight), maxW, cint(align), st.fam.cstring,
                               cint(st.italic), st.lineHeight, cint(st.maxLines), addr buf[0], 64)
  for i in 0 ..< int(n): result.add (float32(buf[4*i]), float32(buf[4*i+1]), float32(buf[4*i+2]), float32(buf[4*i+3]))

# --- raster layers and bulk pixels (CV2) ----------------------------------------------------
proc yk_canvas_env(layerBase: cint; bufFn: pointer) {.importc, cdecl.}
proc yk_layer_new(id, w, h: cint): cint {.importc, cdecl.}
proc yk_layer_free(id: cint) {.importc, cdecl.}
proc yk_layer_draw(id: cint; cmds: cstring; len: cint; assetDir: cstring): cint {.importc, cdecl.}
proc yk_layer_filter(id, kind: cint; amount: cfloat): cint {.importc, cdecl.}
proc yk_layer_read(id, x, y, w, h: cint; o: pointer): cint {.importc, cdecl.}
proc yk_layer_write(id, x, y, w, h: cint; i: pointer): cint {.importc, cdecl.}
proc yk_layer_size(id: cint; w, h: ptr cint): cint {.importc, cdecl.}
proc canvasEnv*(layerBase: int; bufFn: pointer) = yk_canvas_env(cint(layerBase), bufFn)
  ## Before drawing an app's canvases: its layer ids' offset, and how 'X' finds a buffer's
  ## bytes (`proc (id: cint; len: ptr cint): pointer {.cdecl.}`).
proc newLayer*(id, w, h: int): bool = yk_layer_new(cint(id), cint(w), cint(h)) == 1
  ## A transparent w x h bitmap under global id `id` (replaces one with that id).
proc freeLayer*(id: int) = yk_layer_free(cint(id))
proc drawLayer*(id: int; cmds, assetDir: string): bool =
  ## Draws a canvas command list into layer `id`, where it stays.
  yk_layer_draw(cint(id), cmds.cstring, cint(cmds.len), assetDir.cstring) == 1
proc filterLayer*(id, kind: int; amount: float32): bool = yk_layer_filter(cint(id), cint(kind), amount) == 1
  ## In place: 0 blur px, 1 brightness, 2 contrast, 3 saturation, 4 invert, 5 grey, 6 sepia, 7 opacity.
proc readLayer*(id, x, y, w, h: int): string =
  ## w x h RGBA (not premultiplied) from (x, y); "" if there is no such layer.
  result = newString(max(0, w * h * 4))
  if result.len == 0 or yk_layer_read(cint(id), cint(x), cint(y), cint(w), cint(h), addr result[0]) != 1: result = ""
proc writeLayer*(id, x, y, w, h: int; rgba: string): bool =
  rgba.len >= w * h * 4 and w > 0 and h > 0 and
    yk_layer_write(cint(id), cint(x), cint(y), cint(w), cint(h), unsafeAddr rgba[0]) == 1
proc layerSize*(id: int): (int, int) =
  var w, h: cint
  if yk_layer_size(cint(id), addr w, addr h) == 1: (int(w), int(h)) else: (0, 0)
