## apps/files/app.nim
## Dedicated Celestia File Manager (`apps/files/app.wasm`) on the new SDK:
## browse the 10 catalog apps, inspect live `.nim` sources (devwatch mirror
## bridge) + manifests, and hand any app to the desktop via
## storeSet("desk", "active_app", id). Split mode embeds the selected app as a
## live AppView (`source = "y:<id>"`) beside the preview, so any app opens in
## Split without leaving the manager.

import std/strutils
import yantra
import ../desktop/[config, catalog]

proc storeSet(scope, key, value: string): bool =
  ## The two-argument store write, same shim as `storeGet` below: the desktop
  ## reads "active_app" back out of the shared store.
  result = saveStored(key, value)
  discard scope

proc storeGet(scope, key: string): string =
  ## The two-argument store read this app was written against: `render/native/
  ## devwatch.nim` publishes every app's source as `mirror.<id>` into the shared
  ## store folder, and every module is app.wasm, so the scope is already implied
  ## by the host - the key is the whole address. Kept as a shim so the call sites
  ## below stay readable.
  var v = ""
  if loadStored(key, v): result = v
  discard scope

const
  FW* = 1100.0'f32
  FH* = 720.0'f32

var
  selectedIdx: int = 0
  activeSubFile: int = 0
  splitMode: bool = false
  previewLines: seq[string] = @[]
  mouseFX: float32 = -1.0'f32
  mouseFY: float32 = -1.0'f32
  fpage, fstage, fchrome: Node
  fchromeReady: bool = false
  previewAv: Node
  previewHas: bool = false
  previewSrc: string = ""

proc refreshPreview() =
  if selectedIdx < 0 or selectedIdx >= CatalogApps.len:
    selectedIdx = 0
  let entry = CatalogApps[selectedIdx]
  if activeSubFile == 0:
    var txt = storeGet("desk", "mirror." & entry.id)
    if txt.len == 0:
      txt = storeGet("desk", "liveedit." & entry.id)
    if txt.len == 0:
      txt = defaultStarterAppTemplate(entry.id)
    previewLines = txt.splitLines()
  else:
    var txt = storeGet("desk", "mirrorjson." & entry.id)
    if txt.len == 0:
      txt = "{\n" &
        "  \"id\": \"" & entry.id & "\",\n" &
        "  \"title\": \"" & entry.title & "\",\n" &
        "  \"category\": \"" & $entry.category & "\",\n" &
        "  \"description\": \"" & entry.subtitle & "\",\n" &
        "  \"badge\": \"" & entry.badge & "\",\n" &
        "  \"source\": \"" & entry.appSource() & "\",\n" &
        "  \"nim\": \"" & entry.nimPath & "\"\n" &
        "}"
    previewLines = txt.splitLines()

proc syncSplitView() =
  let entry = CatalogApps[selectedIdx]
  let wantAv = splitMode and entry.canLaunch
  if not wantAv:
    if previewHas:
      previewAv.remove()
      previewHas = false
      previewSrc = ""
    return
  let leftW = 310.0'f32
  let topH = 42.0'f32
  let px = leftW + 12.0'f32 + (FW - leftW - 24.0'f32) * 0.5'f32 + 4.0'f32
  let pw = (FW - leftW - 24.0'f32) * 0.5'f32 - 4.0'f32
  let src = "y:" & entry.id
  if previewHas and previewSrc == src:
    previewAv.set(pInsetTop, topH + 10.0'f32)
    previewAv.set(pInsetLeft, px)
    previewAv.width(int32(pw))
    previewAv.height(int32(FH - topH - 20.0'f32 - 4.0'f32))
  else:
    if previewHas:
      previewAv.remove()
      previewHas = false
    previewAv = make(nkAppView, fstage)
    previewAv.set(pSource, src)
    previewAv.set(pInsetTop, topH + 10.0'f32)
    previewAv.set(pInsetLeft, px)
    previewAv.width(int32(pw))
    previewAv.height(int32(FH - topH - 20.0'f32 - 4.0'f32))
    previewHas = true
    previewSrc = src

proc buildFiles(): Draw =
  let leftW = 310.0'f32
  let topH = 42.0'f32
  var d = Draw()
  d = d.rect(0, 0, FW, FH, ColVoid)
  d = d.rect(0, 0, FW, topH, ColChrome)
  drawYantraEmblem(d, 22.0'f32, topH * 0.5'f32, 12.0'f32, compact = true)
  drawTextVCenter(d, 40.0'f32, 0, topH,
                  "यंत्र FILE MANAGER  ·  /apps/" & CatalogApps[selectedIdx].id,
                  14.0'f32, ColGold, true)
  let tab0hov = mouseFX >= FW - 428.0'f32 and mouseFX <= FW - 340.0'f32 and
    mouseFY >= 7.0'f32 and mouseFY <= 35.0'f32
  d = d.rect(FW - 428.0'f32, 7.0'f32, 88.0'f32, 28.0'f32,
             (if activeSubFile == 0: ColGold elif tab0hov: ColCardHover else: ColCard), 6.0'f32)
  drawTextHCenter(d, FW - 384.0'f32, 7.0'f32, 28.0'f32, "app.nim", 12.0'f32,
                  (if activeSubFile == 0: ColVoid else: ColTextHi), true)
  let tab1hov = mouseFX >= FW - 332.0'f32 and mouseFX <= FW - 244.0'f32 and
    mouseFY >= 7.0'f32 and mouseFY <= 35.0'f32
  d = d.rect(FW - 332.0'f32, 7.0'f32, 88.0'f32, 28.0'f32,
             (if activeSubFile == 1: ColGold elif tab1hov: ColCardHover else: ColCard), 6.0'f32)
  drawTextHCenter(d, FW - 288.0'f32, 7.0'f32, 28.0'f32, "app.json", 12.0'f32,
                  (if activeSubFile == 1: ColVoid else: ColTextHi), true)
  let splitHov = mouseFX >= FW - 236.0'f32 and mouseFX <= FW - 148.0'f32 and
    mouseFY >= 7.0'f32 and mouseFY <= 35.0'f32
  let splitBg =
    if splitMode: ColEmerald
    elif splitHov: ColCardHover
    else: ColCard
  d = d.rect(FW - 236.0'f32, 7.0'f32, 88.0'f32, 28.0'f32, splitBg, 6.0'f32)
  drawTextHCenter(d, FW - 192.0'f32, 7.0'f32, 28.0'f32, "◫ Split", 12.0'f32,
                  (if splitMode: ColVoid else: ColTextHi), true)
  d = d.rect(FW - 140.0'f32, 7.0'f32, 128.0'f32, 28.0'f32, ColCyan, 6.0'f32)
  drawTextHCenter(d, FW - 76.0'f32, 7.0'f32, 28.0'f32, "◫ Edit in Studio", 12.0'f32, ColVoid, true)
  d = d.rect(0, topH, leftW, FH - topH, ColPanel)
  for idx, entry in CatalogApps:
    let ry = topH + 10.0'f32 + float32(idx) * 32.0'f32
    if ry + 28.0'f32 > FH: break
    let sel = (idx == selectedIdx)
    let hov = mouseFX >= 8.0'f32 and mouseFX <= leftW - 8.0'f32 and
      mouseFY >= ry and mouseFY <= ry + 28.0'f32
    d = d.rect(8.0'f32, ry, leftW - 16.0'f32, 28.0'f32,
               (if sel: ColCardHover elif hov: ColCard else: ColCard), 6.0'f32)
    d = d.circle(20.0'f32, ry + 14.0'f32, 4.5'f32, entry.accent)
    drawTextVCenter(d, 32.0'f32, ry, 28.0'f32, "📁 apps/" & entry.id, 12.0'f32,
                    (if sel: ColGold else: ColTextHi), sel)
    drawTextVCenter(d, leftW - 68.0'f32, ry, 28.0'f32, entry.badge, 11.0'f32, entry.accent)
  let fullW = FW - leftW - 24.0'f32
  let (px, pw) =
    if splitMode and CatalogApps[selectedIdx].canLaunch: (leftW + 12.0'f32, fullW * 0.5'f32 - 4.0'f32)
    else: (leftW + 12.0'f32, fullW)
  let py = topH + 10.0'f32
  let ph = FH - topH - 20.0'f32
  d = d.rect(px, py, pw, ph, 0xFF0B0E1A'u32, 16.0'f32)
  let maxL = min(previewLines.len, int((ph - 16.0'f32) / 19.0'f32))
  for ln in 0 ..< maxL:
    let ly = py + 8.0'f32 + float32(ln) * 19.0'f32
    drawTextVCenter(d, px + 10.0'f32, ly, 19.0'f32, $(ln + 1), 11.0'f32, ColTextDim)
    var tx = px + 48.0'f32
    for tok in tokenizeNimLine(previewLines[ln]):
      if tx > px + pw - 60.0'f32: break
      drawTextVCenter(d, tx, ly, 19.0'f32, tok.text, 14.0'f32, tokenColor(tok.kind))
      tx += mTextW(tok.text, 14.0'f32, mono = true)
  if previewLines.len == 0:
    # X1: an app that can show nothing has to say why. `previewLines` is empty when
    # devwatch has not mirrored this app's source yet (or the store is cold), which is
    # the only state in which the panel would otherwise be a blank rectangle.
    drawTextVCenter(d, px + 16.0'f32, py + 16.0'f32, 20.0'f32,
                    "No source published for this app yet - devwatch mirrors apps/" &
                    CatalogApps[selectedIdx].id & "/app.nim on start.",
                    12.0'f32, ColTextDim)
  if splitMode and not CatalogApps[selectedIdx].canLaunch:
    drawTextVCenter(d, px + 10.0'f32, py + ph - 22.0'f32, 18.0'f32,
                    "shell: no live Split for this entry",
                    11.0'f32, ColTextDim)
  elif splitMode:
    drawTextVCenter(d, px + 10.0'f32, py + ph - 22.0'f32, 18.0'f32,
                    "◫ Split: live y:" & CatalogApps[selectedIdx].id & " on the right · click ◫ Edit in Studio to open on the desktop",
                    11.0'f32, ColTextDim)
  else:
    drawTextVCenter(d, px + 10.0'f32, py + ph - 22.0'f32, 18.0'f32,
                    "mirror bridge: live source via devwatch · ◫ Split runs any app here · ◫ Edit in Studio opens it on the desktop",
                    11.0'f32, ColTextDim)
  result = d

proc repaintFiles() =
  if fchromeReady:
    fchrome.set(pDraw, buildFiles().cmds)

proc onFilesDown(mx, my: float32) =
  let leftW = 310.0'f32
  let topH = 42.0'f32
  if my <= topH:
    if mx >= FW - 428.0'f32 and mx <= FW - 340.0'f32:
      activeSubFile = 0
      refreshPreview()
    elif mx >= FW - 332.0'f32 and mx <= FW - 244.0'f32:
      activeSubFile = 1
      refreshPreview()
    elif mx >= FW - 236.0'f32 and mx <= FW - 148.0'f32:
      splitMode = not splitMode
      refreshPreview()
      syncSplitView()
    elif mx >= FW - 140.0'f32:
      discard storeSet("desk", "active_app", CatalogApps[selectedIdx].id)
    return
  if mx < leftW:
    let idx = int((my - (topH + 10.0'f32)) / 32.0'f32)
    if idx >= 0 and idx < CatalogApps.len:
      selectedIdx = idx
      refreshPreview()
      syncSplitView()

proc main() =
  if previewLines.len == 0:
    refreshPreview()
  fpage = window("Yantra File Manager", int32(FW), int32(FH))
  fstage = stack(fpage)
  fstage.width(int32(FW))
  fstage.height(int32(FH))
  fchrome = canvas(fstage, int32(FW), int32(FH))
  fchromeReady = true
  fchrome.addHandler(evPointerDown, proc() =
    let (px, py) = pointerPage()
    onFilesDown(px, py)
    repaintFiles()
    handled())
  fchrome.addHandler(evPointerMove, proc() =
    let (px, py) = pointerPage()
    mouseFX = px
    mouseFY = py)
  fchrome.addHandler(evFrame, proc() =
    syncSplitView()
    repaintFiles())
  repaintFiles()

proc yantra_main*() {.exportc: "yantra_main".} =
  main()
