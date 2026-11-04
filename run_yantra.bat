@echo off
REM DisableDelayedExpansion (B1): keeps `!` in %PATH% intact on Win11 dev boxes.
setlocal DisableDelayedExpansion
REM B7: never run from the wrong cwd — caller's drive may differ.
cd /d "%~dp0" || exit /b 1

REM Yantra OS double-click launcher (no CLI flags for users).
REM - PATH: bundled engine DLLs in bin\ (+ MinGW runtime if present)
REM - compile-if-missing: desktop wasm, then native GUI engine (no console window)
REM - boots the desktop wasm with --watch (devwatch hot reload) + MCP on 127.0.0.1:9229
REM - all output goes to yantra.log
set "PATH=%~dp0bin;%PATH%"

REM B6: always log to the absolute repo path, never the caller's cwd.
set "LOG=%~dp0yantra.log"

REM B4: evict zero-byte stale outputs so the exist-gates below rebuild them.
if exist "apps\desktop\app.wasm" for %%F in ("apps\desktop\app.wasm") do if %%~zF==0 del "apps\desktop\app.wasm"

if not exist "apps\desktop\app.wasm" (
  echo [Yantra OS] Building apps\desktop\app.wasm... ^(see yantra.log^)
  where bash >nul 2>nul
  if errorlevel 1 (
    echo [Yantra OS] FAIL: git-bash not found; install Git for Windows, then double-click again.
    pause
    exit /b 1
  )
  REM wasi-sdk clang for build-wasm.sh (repo junction first, sibling checkout fallback).
  where clang >nul 2>nul
  if errorlevel 1 (
    if exist "third_party\wasi-sdk-34.0-x86_64-windows\bin\clang.exe" set "PATH=%~dp0third_party\wasi-sdk-34.0-x86_64-windows\bin;%PATH%"
    if exist "..\yantra\third_party\wasi-sdk-34.0-x86_64-windows\bin\clang.exe" set "PATH=%~dp0..\yantra\third_party\wasi-sdk-34.0-x86_64-windows\bin;%PATH%"
  )
  bash tools/build-wasm.sh apps/desktop/app.nim apps/desktop/app.wasm >> "%LOG%" 2>&1
  if exist "apps\desktop\app.wasm" for %%F in ("apps\desktop\app.wasm") do if %%~zF==0 del "apps\desktop\app.wasm"
  if not exist "apps\desktop\app.wasm" (
    echo [Yantra OS] FAIL: desktop wasm build failed; see yantra.log
    pause
    exit /b 1
  )
)

REM B4: same zero-byte gate for the native engine.
if exist "bin\yantra.exe" for %%F in ("bin\yantra.exe") do if %%~zF==0 del "bin\yantra.exe"

if not exist "bin\yantra.exe" (
  echo [Yantra OS] Compiling native Windows engine bin\yantra.exe... ^(see yantra.log^)
  where nim >nul 2>nul
  if errorlevel 1 (
    echo [Yantra OS] FAIL: Nim not found. Unzip yantra-windows-x64-bin.zip into bin\ ^(see README^).
    pause
    exit /b 1
  )
  if not exist "third_party" (
    REM B2: quote both mklink operands (repo paths may contain spaces).
    if exist "..\yantra\third_party" (
      mklink /J "third_party" "..\yantra\third_party" >> "%LOG%" 2>&1
      REM B3: mklink needs admin/Developer Mode — warn loudly, keep PATH fallbacks.
      if errorlevel 1 echo [Yantra OS] WARN: mklink junction failed ^(needs admin or Developer Mode^); continuing with PATH fallbacks. & echo [Yantra OS] WARN: mklink junction failed ^(needs admin or Developer Mode^); continuing with PATH fallbacks. >> "%LOG%" 2>&1
    )
    if not exist "third_party" if exist "..\yantra\third_party\wasi-sdk-34.0-x86_64-windows\bin" set "PATH=%~dp0..\yantra\third_party\wasi-sdk-34.0-x86_64-windows\bin;%PATH%"
    if not exist "third_party" if exist "..\yantra\third_party\msys64\mingw64\bin" set "PATH=%~dp0..\yantra\third_party\msys64\mingw64\bin;%PATH%"
  )
  set "ICON_OBJ="
  if exist "render\native\yantra.rc" (
    where windres >nul 2>nul
    if not errorlevel 1 (
      windres render\native\yantra.rc -O coff -o render\native\yantra_res.o >> "%LOG%" 2>&1
      if exist "render\native\yantra_res.o" set "ICON_OBJ=--passL:"%~dp0render\native\yantra_res.o""
    )
  )
  nim c -d:release --threads:on --app:gui --hints:off %ICON_OBJ% --path:libs/nimaccesskit/src --path:libs/nimav/src --path:libs/nimblake3/src --path:libs/nimcurl/src --path:libs/nimfilament/src --path:libs/nimjolt/src --path:libs/nimminiaudio/src --path:libs/nimpg/src --path:libs/nimqt/src --path:libs/nimrtc/src --path:libs/nimsdl3/src --path:libs/nimskia/src --path:libs/nimspell/src --path:libs/nimsqlite/src --path:libs/nimwasmtime/src --path:libs/nimyoga/src --out:bin\yantra.exe render\native\yantra_run.nim >> "%LOG%" 2>&1
  if exist "bin\yantra.exe" for %%F in ("bin\yantra.exe") do if %%~zF==0 del "bin\yantra.exe"
  if not exist "bin\yantra.exe" (
    echo [Yantra OS] FAIL: engine build failed; download yantra-windows-x64-bin.zip ^(Releases v1.0.0^) into bin\ or see yantra.log
    pause
    exit /b 1
  )
)

REM GUI-subsystem exe: no console window. Detached start; engine logs to yantra.log.
start "" /B cmd /c ""%~dp0bin\yantra.exe" "%~dp0apps\desktop\app.wasm" --watch --mcp-port=9229 >> "%~dp0yantra.log" 2>&1"
