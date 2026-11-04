@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
echo ========================================================
echo  Yantra OS - Standalone Integrity and Runtime Preflight Check
echo ========================================================
echo.

set "FAIL_COUNT=0"
set "BIN_DIR=%~dp0bin"
set "YANTRA_EXE=%BIN_DIR%\yantra.exe"

if not exist "%YANTRA_EXE%" (
    echo [NOTICE] Binary not found at %YANTRA_EXE%
    echo [NOTICE] Downloading standalone Windows runtime closure from GitHub Releases v1.0.0...
    if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
    curl -fL -o "%~dp0yantra-windows-x64-bin.zip" "https://github.com/Yantra-lab/yantra-os/releases/download/v1.0.0/yantra-windows-x64-bin.zip"
    if exist "%~dp0yantra-windows-x64-bin.zip" (
        echo [NOTICE] Extracting runtime into bin\...
        tar -xf "%~dp0yantra-windows-x64-bin.zip" -C "%BIN_DIR%"
        del "%~dp0yantra-windows-x64-bin.zip"
    )
)

if not exist "%YANTRA_EXE%" (
    echo [FAIL] Binary not found: %YANTRA_EXE%
    echo Please download yantra-windows-x64-bin.zip from https://github.com/Yantra-lab/yantra-os/releases/tag/v1.0.0 and extract into bin\
    exit /b 1
)

echo [OK] Found Host Engine: %YANTRA_EXE%

set "APPS=typewriter desktop gallery chess dna calc notes todo"

for %%A in (%APPS%) do (
    set "WASM_PATH=%~dp0apps\%%A\app.wasm"
    if exist "!WASM_PATH!" (
        echo [OK] App found: %%A - !WASM_PATH!
    ) else (
        echo [FAIL] App WASM missing: %%A
        set /a FAIL_COUNT+=1
    )
)

echo.
if %FAIL_COUNT% equ 0 (
    echo ========================================================
    echo  ALL CHECKS PASSED: Environment is 100%% Standalone and Ready!
    echo ========================================================
    REM Single launcher model: run_yantra.* boots the desktop (run_typewriter.bat deleted).
    echo Launching desktop via run_yantra.bat...
    call "%~dp0run_yantra.bat"
) else (
    echo [ERROR] Verification failed with %FAIL_COUNT% missing components.
    pause
)
