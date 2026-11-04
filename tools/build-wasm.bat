@echo off
setlocal enabledelayedexpansion

:: Yantra OS - Windows WASM App Module Compiler
:: Usage: tools\build-wasm.bat <src.nim> <out.wasm>

if "%~1"=="" (
    echo Usage: tools\build-wasm.bat ^<src.nim^> ^<out.wasm^>
    exit /b 1
)

set "SRC=%~1"
set "OUT=%~2"
set "ROOT=%~dp0.."
set "SDK=%ROOT%\sdk"
set "MINILIBC=%SDK%\minilibc"

if not exist "%SRC%" (
    echo Error: Source file not found: %SRC%
    exit /b 1
)

if "%OUT%"=="" (
    set "OUT=%~dpn1.wasm"
)

echo [Yantra Builder] Compiling %SRC% -^> %OUT%

nim c --cc:clang --cpu:wasm32 --os:any --noMain:on --mm:arc -d:nimAllocPagesViaMalloc -d:yantra_engine --hints:off --warnings:off --path:"%SDK%" --import:yantra --passC:"--target=wasm32-unknown-unknown -nostdlib -ffreestanding -ffunction-sections -fdata-sections -I%MINILIBC%\include" --passL:"--target=wasm32-unknown-unknown -nostdlib -Wl,--no-entry -Wl,--export-all -Wl,--allow-undefined" -o:"%OUT%" "%SRC%"

if %ERRORLEVEL% equ 0 (
    echo [Yantra Builder] Successfully built: %OUT%
) else (
    echo [Yantra Builder] Compilation failed with error code %ERRORLEVEL%
)
