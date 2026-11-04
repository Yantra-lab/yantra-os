#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# Check requirements
if ! command -v curl >/dev/null; then echo "curl is required"; exit 1; fi
if ! command -v unzip >/dev/null; then echo "unzip is required"; exit 1; fi

download_and_verify() {
  local url="$1"
  local dest="$2"
  local want_sha="$3"
  
  if [ -f "$dest" ]; then
    local got_sha="$(sha256sum "$dest" | awk '{print $1}')"
    if [ "$got_sha" = "$want_sha" ]; then
      echo "  [OK] $dest already matches sha256"
      return 0
    fi
    echo "  [INFO] $dest hash mismatch, redownloading"
  fi
  
  echo "  [DL] Downloading $url to $dest"
  curl -L -s -o "$dest" "$url"
  local got_sha="$(sha256sum "$dest" | awk '{print $1}')"
  if [ "$got_sha" != "$want_sha" ]; then
    echo "  [FAIL] SHA256 mismatch for $dest: got $got_sha, want $want_sha"
    exit 1
  fi
  echo "  [OK] Verified $dest"
}

# 1. MSYS2 Qt 6 mingw64 bundle
echo "==> Setting up MSYS2 Qt 6 mingw64 bundle"
mkdir -p "$ROOT/third_party"
cd "$ROOT/third_party"
MSYS_URL="https://github.com/msys2/msys2-installer/releases/download/2024-07-27/msys2-base-x86_64-20240727.sfx.exe"
# Verified 2026-10-01 against the upstream-published digest file and against a
# fresh download of the asset (both agree):
#   https://github.com/msys2/msys2-installer/releases/download/2024-07-27/msys2-base-x86_64-20240727.sfx.exe.sha256
MSYS_SHA="587b86c7e2b7e77d133a4422d4c9b0ae68312442b905277ea3d4ccd0e75cbdea"
download_and_verify "$MSYS_URL" "msys2.sfx.exe" "$MSYS_SHA"

if [ ! -d "msys64" ]; then
  echo "  [INSTALL] Extracting MSYS2..."
  ./msys2.sfx.exe -y
  echo "  [INSTALL] Updating MSYS2 and installing Qt6..."
  msys64/usr/bin/bash.exe -lc "pacman -Syu --noconfirm"
  msys64/usr/bin/bash.exe -lc "pacman -S --noconfirm mingw-w64-x86_64-qt6-base mingw-w64-x86_64-qt6-declarative mingw-w64-x86_64-harfbuzz mingw-w64-x86_64-freetype mingw-w64-x86_64-sqlite3 mingw-w64-x86_64-ffmpeg mingw-w64-x86_64-jolt-physics mingw-w64-x86_64-libblake3 mingw-w64-x86_64-curl"
else
  echo "  [OK] msys64 already extracted"
fi

# 2. Wasmtime C API
echo "==> Setting up Wasmtime C API (v19 and v48)"
VENDOR="$ROOT/libs/nimwasmtime/vendor"
BUILD="$ROOT/libs/nimwasmtime/build"
mkdir -p "$VENDOR" "$BUILD"

WT48_URL="https://github.com/bytecodealliance/wasmtime/releases/download/v48.0.0/wasmtime-v48.0.0-x86_64-windows-c-api.zip"
WT48_SHA="7715de37377f6c2303af236dace91fae8c853e79306f9fc12b0ee2f827e65069"
download_and_verify "$WT48_URL" "$VENDOR/wt.zip" "$WT48_SHA"

if [ ! -d "$VENDOR/wasmtime-v48.0.0-x86_64-windows-c-api" ]; then
  echo "  [EXTRACT] wasmtime v48"
  unzip -q "$VENDOR/wt.zip" -d "$VENDOR/"
fi

WT19_URL="https://github.com/bytecodealliance/wasmtime/releases/download/v19.0.2/wasmtime-v19.0.2-x86_64-windows-c-api.zip"
WT19_SHA="9814038a400680a322f8c287ccba68fc0c5ffccede31f9ed444e945bdeec5c70"
download_and_verify "$WT19_URL" "$VENDOR/wt19.zip" "$WT19_SHA"

if [ ! -d "$VENDOR/wasmtime-v19.0.2-x86_64-windows-c-api" ]; then
  echo "  [EXTRACT] wasmtime v19"
  unzip -q "$VENDOR/wt19.zip" -d "$VENDOR/"
fi

# 3. Copy wasmtime.dll to build/
#
# ############################################################################
# TRAP — READ BEFORE "FIXING" A MISSING wasmtime.dll:
# The upstream wasmtime C API archives extract into VENDOR/ (lowercase:
# libs/nimwasmtime/vendor/wasmtime-v<VER>-x86_64-windows-c-api/lib/wasmtime.dll).
# It does NOT extract into build/. build/ is only ever a staging copy made by
# THIS step. On a fresh clone -- or in a new worktree -- build/ is empty and
# the dll genuinely is not there yet; run tools/setup.sh instead of hand-
# copying from build/. The canonical source of truth is the VENDOR/ tree.
# Both vendor/ and build/*.dll are .gitignored and are never committed.
# ############################################################################
echo "==> Staging wasmtime.dll (source: VENDOR/ .../lib/wasmtime.dll -> build/)"
WT48_DLL="$VENDOR/wasmtime-v48.0.0-x86_64-windows-c-api/lib/wasmtime.dll"
if [ ! -f "$WT48_DLL" ]; then
  echo "  [WARN] $WT48_DLL not found; searching VENDOR/ for wasmtime.dll"
  WT48_DLL="$(find "$VENDOR" -type f -name 'wasmtime.dll' -path '*v48*' | head -1)"
fi
if [ -z "$WT48_DLL" ] || [ ! -f "$WT48_DLL" ]; then
  echo "  [FAIL] No wasmtime v48 dll under $VENDOR/. Re-run this script to re-download." >&2
  exit 1
fi
cp -f "$WT48_DLL" "$BUILD/wasmtime.dll"
echo "  [OK] Copied $WT48_DLL -> $BUILD/wasmtime.dll"

# 4. Yoga layout engine
echo "==> Setting up Yoga layout engine (v3.1.0)"
YOGA_DIR="$ROOT/third_party/yoga"
mkdir -p "$YOGA_DIR"
YOGA_URL="https://github.com/facebook/yoga/archive/refs/tags/v3.1.0.tar.gz"
YOGA_SHA="06ff9e6df9b2388a0c6ef8db55ba9bc2ae75e716e967cd12cf18785f6379159e"
download_and_verify "$YOGA_URL" "$YOGA_DIR/yoga.tar.gz" "$YOGA_SHA"
if [ ! -d "$YOGA_DIR/yoga-3.1.0" ]; then
  echo "  [EXTRACT] yoga v3.1.0"
  tar -xzf "$YOGA_DIR/yoga.tar.gz" -C "$YOGA_DIR"
fi

# 5. miniaudio audio engine & decoder
echo "==> Setting up miniaudio (v0.11.21)"
MA_DIR="$ROOT/third_party/miniaudio"
mkdir -p "$MA_DIR"
MA_URL="https://raw.githubusercontent.com/mackron/miniaudio/0.11.21/miniaudio.h"
MA_SHA="6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9"
download_and_verify "$MA_URL" "$MA_DIR/miniaudio.h" "$MA_SHA"

# 6. Verify ffmpeg and ffprobe
echo "==> Verifying ffmpeg and ffprobe"
if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then
  echo "  [OK] ffmpeg and ffprobe available"
else
  echo "  [WARN] ffmpeg or ffprobe not found on PATH"
fi

echo "==> Setup complete!"
