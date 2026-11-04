## render/native/devwatch.nim
## Watches BOTH `apps/*/*.nim` on disk AND liveedit store files saved by the
## in-WASM editors (`Ctrl+S` -> y_store_set -> dataDir()/app/desk.liveedit.<id>.bin,
## legacy: dataDir()/desk/liveedit.<id>.bin). Compiles to a staging `.tmp.wasm`,
## verifies via `tools/verify-wasm.mjs`, swaps atomically, and calls
## `engine.reloadEverywhere(wasmPath)` so both top-level and embedded `AppView`
## instances hot-reload in <100ms without restarting!
##
## Mirror bridge: the WASM sandbox can only read its own folder, so desktop /
## editor / files CANNOT read apps/<id>/app.nim directly. devwatch publishes
## every apps/<id>/app.nim + app.json into the store on startup and on change
## (dataDir()/app/desk.mirror.<id>.bin), and the apps read them back with
## storeGet("desk", "mirror." & id). All apps share the "app" store folder
## (every module is app.wasm), so one bridge serves desktop, editor and files.

import std/[os, osproc, times, tables, strutils, monotimes]
import engine
import ../../host/host

type
  DevWatcher* = ref object
    repoRoot*: string
    mtimes: Table[string, Time]
    liveEditMtimes: Table[string, Time]
    lastPollMs: int64

proc storeDirs(): seq[string] =
  ## New namespace dir first, legacy second. Writes go to both; reads prefer new.
  result = @[dataDir() / "app", dataDir() / "desk"]

proc storeFileName(key: string; legacyDir: bool): string =
  if legacyDir: key
  else: "desk." & key

proc readLiveEdit(appId: string): tuple[found: bool; content: string; path: string] =
  for i, dir in storeDirs():
    let p = dir / (storeFileName("liveedit." & appId, i == 1) & ".bin")
    if fileExists(p):
      try: return (true, readFile(p), p)
      except IOError: discard
  (false, "", "")

proc writeStoreFile(key, content: string) =
  for i, dir in storeDirs():
    let p = dir / (storeFileName(key, i == 1) & ".bin")
    try:
      createDir(dir)
      writeFile(p & ".tmp", content)
      moveFile(p & ".tmp", p)
    except OSError, IOError:
      discard

proc publishMirror*(w: DevWatcher; appId: string) =
  ## Publishes apps/<appId>/app.nim (+ app.json) into the store for WASM readers.
  let nimFile = w.repoRoot / "apps" / appId / "app.nim"
  if fileExists(nimFile):
    try: writeStoreFile("mirror." & appId, readFile(nimFile))
    except OSError, IOError: discard
  let jsonFile = w.repoRoot / "apps" / appId / "app.json"
  if fileExists(jsonFile):
    try: writeStoreFile("mirrorjson." & appId, readFile(jsonFile))
    except OSError, IOError: discard

proc publishAllMirrors*(w: DevWatcher) =
  for kind, appDir in walkDir(w.repoRoot / "apps"):
    if kind == pcDir:
      w.publishMirror(extractFilename(appDir))

proc newDevWatcher*(repoRoot = getCurrentDir()): DevWatcher =
  result = DevWatcher(
    repoRoot: repoRoot,
    mtimes: initTable[string, Time](),
    liveEditMtimes: initTable[string, Time](),
    lastPollMs: 0
  )
  for kind, appDir in walkDir(repoRoot / "apps"):
    if kind == pcDir:
      let nimFile = appDir / "app.nim"
      if fileExists(nimFile):
        try: result.mtimes[nimFile] = getLastModificationTime(nimFile)
        except OSError: discard
  result.publishAllMirrors()

proc writeBuildStatus(appId, status: string) =
  writeStoreFile("buildstatus." & appId, status)

proc toolchainPath*(repoRoot: string): string =
  ## wasi-sdk clang dir for build-wasm.sh: repo bundle first, sibling checkout
  ## fallback. A GUI-launched engine inherits a minimal PATH, so the build
  ## command must carry its toolchain explicitly (else: "clang not found").
  for base in [repoRoot / "third_party", repoRoot / ".." / "yantra" / "third_party"]:
    if dirExists(base):
      for kind, path in walkDir(base):
        if kind == pcDir and extractFilename(path).startsWith("wasi-sdk-"):
          let bin = path / "bin"
          if fileExists(bin / "clang.exe") or fileExists(bin / "clang"):
            return bin
  ""

proc rebuildAndHotReload*(w: DevWatcher; eng: Engine; appId, nimFile: string) =
  let t0 = getMonoTime().ticks
  let appDir = w.repoRoot / "apps" / appId
  let finalWasm = appDir / "app.wasm"
  let tmpWasm   = appDir / ".app.tmp.wasm"

  let tcp = toolchainPath(w.repoRoot)
  let pathPrefix =
    if tcp.len > 0: "export PATH=\"" & tcp & ":$PATH\"; "
    else: ""
  let cmd = pathPrefix & "bash " & quoteShell(w.repoRoot / "tools" / "build-wasm.sh") & " " &
            quoteShell(nimFile) & " " & quoteShell(tmpWasm)
  let (outp, code) = execCmdEx(cmd, workingDir = w.repoRoot)
  if code != 0:
    var errLine = "1"
    var errMsg = outp.strip()
    for ln in outp.splitLines():
      if "Error:" in ln:
        errMsg = ln.strip()
        let pOpen = ln.find('(')
        let pComma = ln.find(',', max(0, pOpen))
        if pOpen >= 0 and pComma > pOpen:
          errLine = ln[pOpen + 1 ..< pComma].strip()
        break
    writeBuildStatus(appId, "ERR|" & errLine & "|" & errMsg)
    stderr.writeLine("[devwatch] Build failed for " & appId & ": " & errMsg)
    return

  if fileExists(w.repoRoot / "tools" / "verify-wasm.mjs"):
    let (_, vCode) = execCmdEx(pathPrefix & "node " & quoteShell(w.repoRoot / "tools" / "verify-wasm.mjs") & " " & quoteShell(tmpWasm))
    if vCode != 0:
      writeBuildStatus(appId, "ERR|1|verify-wasm.mjs rejected imports/size")
      return

  try:
    moveFile(tmpWasm, finalWasm)
  except OSError:
    copyFile(tmpWasm, finalWasm)

  let elapsedMs = (getMonoTime().ticks - t0) div 1_000_000
  let kb = (try: int(getFileSize(finalWasm) div 1024) except OSError: 0)
  writeBuildStatus(appId, "OK|" & $kb & " KB|" & $elapsedMs & " ms")

  let relWasm = "apps/" & appId & "/app.wasm"
  discard eng.reloadEverywhere(relWasm)
  discard eng.reloadEverywhere(finalWasm)
  w.publishMirror(appId)
  echo "[devwatch] Hot-reloaded " & relWasm & " (" & $kb & " KB in " & $elapsedMs & " ms)"

proc poll*(w: DevWatcher; eng: Engine) =
  if w.isNil: return
  let nowMs = getMonoTime().ticks div 1_000_000
  if nowMs - w.lastPollMs < 120:
    return
  w.lastPollMs = nowMs

  for i, dir in storeDirs():
    if dirExists(dir):
      for kind, path in walkDir(dir):
        if kind == pcFile:
          let fname = extractFilename(path)
          let prefix = if i == 0: "desk.liveedit." else: "liveedit."
          if fname.startsWith(prefix) and fname.endsWith(".bin"):
            let appId = fname[prefix.len ..< fname.len - ".bin".len]
            try:
              let mt = getLastModificationTime(path)
              if not w.liveEditMtimes.hasKey(path) or mt > w.liveEditMtimes[path]:
                w.liveEditMtimes[path] = mt
                let newSource = readFile(path)
                if newSource.len > 0:
                  let appDir = w.repoRoot / "apps" / appId
                  createDir(appDir)
                  let nimFile = appDir / "app.nim"
                  writeFile(nimFile, newSource)
                  w.mtimes[nimFile] = getLastModificationTime(nimFile)
                  w.publishMirror(appId)
                  w.rebuildAndHotReload(eng, appId, nimFile)
            except OSError, IOError:
              discard

  for kind, appDir in walkDir(w.repoRoot / "apps"):
    if kind == pcDir:
      let appId = extractFilename(appDir)
      let nimFile = appDir / "app.nim"
      if fileExists(nimFile):
        try:
          let mt = getLastModificationTime(nimFile)
          if not w.mtimes.hasKey(nimFile):
            w.mtimes[nimFile] = mt
            w.publishMirror(appId)
          elif mt > w.mtimes[nimFile]:
            w.mtimes[nimFile] = mt
            w.rebuildAndHotReload(eng, appId, nimFile)
        except OSError:
          discard
