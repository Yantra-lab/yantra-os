## t_run_hello — does the REAL Yantra engine run a Nim-authored wasm app?
##
## This is the same contract that examples/verify_hello.mjs checks against a
## mock engine in JavaScript. Here the engine is the actual Yantra host, written
## in Nim, driving a real wasmtime instance. If both pass, the boundary is proven
## on both sides and the mock is no longer load-bearing.

import std/[os, strformat, strutils, tables, sequtils]
import host
import nimwasmtime
import nimwasmtime/raw

var checks = 0
var failed = 0

proc check(label: string; got, want: string) =
  inc checks
  if got == want:
    echo "OK   ", label, ": ", got
  else:
    inc failed
    echo "FAIL ", label, ": got ", got, ", want ", want

proc check(label: string; got, want: int) =
  check(label, $got, $want)

import ../protocol/wire

proc propStr(n: Node; p: int32): string =
  if p in n.props and n.props[p].kind == vkString: n.props[p].s else: "<none>"

proc propInt(n: Node; p: int32): int =
  if p in n.props and n.props[p].kind == vkInt: int(n.props[p].i) else: -1

proc joinInts(xs: seq[int32]): string =
  "[" & xs.mapIt($it).join(",") & "]"

proc nativePath(p: string): string =
  ## Accept MSYS-style paths from a bash caller. nim.exe/the exe are NATIVE
  ## programs, so /c/Users/... is meaningless to them — rewrite it to C:/Users/...
  if p.len >= 2 and p[0] == '/' and p[2] == '/':
    return p[1].toUpperAscii & ":" & p[2 .. ^1]
  p

proc main(): int =
  let wasm = if paramCount() >= 1: nativePath(paramStr(1))
             else: "../examples/hello.wasm"
  if not fileExists(wasm):
    echo "FAIL missing module: ", wasm
    return 1

  echo "--- loading ", wasm, " (", getFileSize(wasm), " bytes) into the Yantra host ---"
  let inst = loadApp(wasm)
  callMain(inst)

  let s = state()
  echo "\n--- tree the engine received ---"
  echo "nodes: ", s.nodes.len
  for i, n in s.nodes:
    var props = ""
    for k, v in n.props:
      props.add $k & "=" & (case v.kind
        of vkString: "\"" & v.s & "\""
        of vkInt: $v.i
        of vkFloat: $v.f) & " "
    echo fmt"  [{i}] kind={n.kind} children={joinInts(n.children)} props={{{props}}}"

  echo "\n--- assertions ---"
  check("node count", s.nodes.len, 7)
  check("root is a window", s.nodes[0].kind, K_WINDOW)
  check("window title", s.nodes[0].propStr(P_TEXT), "Hello, Yantra")
  check("window width", s.nodes[0].propInt(P_WIDTH), 800)
  check("window height", s.nodes[0].propInt(P_HEIGHT), 600)
  check("window colour 0x1E1E2E", s.nodes[0].propInt(P_COLOR), 0x1E1E2E)
  check("column is child of window", joinInts(s.nodes[0].children), "[1]")
  check("5 children under the column", s.nodes[1].children.len, 5)
  check("title text", s.nodes[2].propStr(P_TEXT), "Hello, Yantra")
  check("title font size", s.nodes[2].propInt(P_FONTSIZE), 32)
  check("title colour white", s.nodes[2].propInt(P_COLOR), 0xFFFFFF)
  check("subtitle is a text node", s.nodes[3].kind, K_TEXT)
  check("subtitle colour", s.nodes[3].propInt(P_COLOR), 0x9A9AB0)
  check("button kind", s.nodes[4].kind, K_BUTTON)
  check("button label", s.nodes[4].propStr(P_TEXT), "Click me")
  check("image source", s.nodes[5].propStr(P_TEXT), "logo.png")
  check("image width", s.nodes[5].propInt(P_WIDTH), 64)
  check("input placeholder", s.nodes[6].propStr(P_TEXT), "Your name")
  check("input font size", s.nodes[6].propInt(P_FONTSIZE), 14)

  echo "\n--- click the button (dispatch back into the sandbox) ---"
  let h = if 4'i32 in s.handlers: s.handlers[4'i32] else: -1'i32
  check("button registered a handler", if h >= 0: 1 else: 0, 1)
  dispatch(inst, h)
  check("title updated after click", s.nodes[2].propStr(P_TEXT), "Clicked 1 time(s)")
  check("engine received the log", s.lastLog(), "button clicked: 1")
  dispatch(inst, h)
  check("second click increments", s.nodes[2].propStr(P_TEXT), "Clicked 2 time(s)")

  # --- Z2 characterization tests for tree property accessors ---
  check("tree hasProp P_WIDTH", if s.nodes[0].hasProp(P_WIDTH): 1 else: 0, 1)
  check("tree hasProp missing", if s.nodes[0].hasProp(P_SCALE): 1 else: 0, 0)
  check("tree iProp P_WIDTH", int(s.nodes[0].iProp(P_WIDTH)), 800)
  check("tree sProp P_TEXT window", s.nodes[0].sProp(P_TEXT), "Hello, Yantra")
  check("tree sProp P_TEXT clicked", s.nodes[2].sProp(P_TEXT), "Clicked 2 time(s)")
  check("tree fProp default", int(s.nodes[0].fProp(P_SCALE)), 0)

  # --- Z2 characterization tests for frame and dt ---
  setFrameDt(0.016'f32)
  var caughtNoExport = false
  try:
    callVoid(inst, "yantra_absent")
  except WasmtimeError:
    caughtNoExport = true
  check("callFrame catches absent export", if caughtNoExport: 1 else: 0, 1)

  # --- Z2f tests for frame and dt ---
  let beforeNodeCount = s.nodes.len
  let beforeWinTitle = s.nodes[0].sProp(P_TEXT)
  var raisedOnHello = false
  try:
    callFrame(inst)
  except CatchableError:
    raisedOnHello = true
  check("callFrame is no-op when export absent", if not raisedOnHello and s.nodes.len == beforeNodeCount and s.nodes[0].sProp(P_TEXT) == beforeWinTitle: 1 else: 0, 1)

  # Verify animate.wasm frame loop changes opacity
  let animWasm = wasm.parentDir / "animate.wasm"
  if fileExists(animWasm):
    let animInst = loadApp(animWasm)
    callMain(animInst)
    let sAnim = state()
    var animNodeIdx = -1
    for i, n in sAnim.nodes:
      if n.kind == K_PANEL:
        animNodeIdx = i
        break
    if animNodeIdx >= 0:
      setFrameDt(0.05'f32)
      callFrame(animInst)
      let op1 = sAnim.nodes[animNodeIdx].fProp(P_OPACITY)
      setFrameDt(0.05'f32)
      callFrame(animInst)
      let op2 = sAnim.nodes[animNodeIdx].fProp(P_OPACITY)
      check("animate.wasm frame changes node opacity", if op1 > 0.0'f32 and op1 != op2: 1 else: 0, 1)

  # --- Z2 characterization tests for wasm module imports ---
  let eng = newEngine()
  let st = newStore(eng)
  let bytes = readFile(wasm)
  let m = compileBytes(st, bytes.toOpenArrayByte(0, bytes.len - 1))
  var importVec: WasmImporttypeVec
  wasmModuleImports(cast[pointer](m.rawHandle), addr importVec)
  check("wasmModuleImports count", int(importVec.size), 6)
  if importVec.size > 0:
    let firstImport = cast[ptr UncheckedArray[ptr WasmImporttype]](importVec.data)[0]
    let nmVec = wasmImporttypeName(firstImport)
    let nmLen = if nmVec != nil: int(nmVec.size) else: 0
    check("wasmImporttypeName non-empty", if nmLen > 0: 1 else: 0, 1)
    let modVec = wasmImporttypeModule(firstImport)
    var modStr = ""
    if modVec != nil and modVec.size > 0:
      modStr = newString(int(modVec.size))
      copyMem(addr modStr[0], modVec.data, int(modVec.size))
    check("wasmImporttypeModule env", modStr, "env")

  echo ""
  echo fmt"=== {checks - failed}/{checks} host checks passed ==="
  if failed > 0: 1 else: 0

when isMainModule:
  quit(main())
