#!/usr/bin/env bash
# ==============================================================================
# Yantra OS — Universal Multi-OS Runner
# Runs any application, film, or verification check across Windows, macOS, and Linux
# ==============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Detect Operating System & Subsystem
OS="$(uname -s 2>/dev/null || echo "Unknown")"
IS_WINDOWS=0
IS_WSL=0
IS_MAC=0
IS_LINUX=0

case "$OS" in
  CYGWIN*|MINGW*|MSYS*|Windows_NT)
    IS_WINDOWS=1
    ;;
  Darwin)
    IS_MAC=1
    ;;
  Linux)
    if [ -f /proc/version ] && grep -qiE "microsoft|wsl" /proc/version; then
      IS_WSL=1
    else
      IS_LINUX=1
    fi
    ;;
  *)
    IS_LINUX=1
    ;;
esac

# Convert POSIX path to Windows path when needed
to_win_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  elif command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$p"
  else
    # Fallback pwd -W for Git Bash / MSYS
    if [ -d "$p" ]; then
      (cd "$p" && pwd -W 2>/dev/null || pwd)
    else
      local d b
      d="$(cd "$(dirname "$p")" && pwd -W 2>/dev/null || pwd)"
      b="$(basename "$p")"
      echo "$d\\$b"
    fi
  fi
}

open_url_or_file() {
  local target="$1"
  if [ "$IS_MAC" -eq 1 ]; then
    open "$target"
  elif [ "$IS_WINDOWS" -eq 1 ]; then
    start "" "$target" 2>/dev/null || explorer "$target" 2>/dev/null || true
  elif [ "$IS_WSL" -eq 1 ]; then
    if command -v wslview >/dev/null 2>&1; then
      wslview "$target"
    else
      cmd.exe /c start "" "$target" 2>/dev/null || true
    fi
  else
    xdg-open "$target" 2>/dev/null || sensible-browser "$target" 2>/dev/null || true
  fi
}

start_web_server() {
  # Port probe: climb from 8080 until a free loopback port is found (max 8090),
  # so a second instance or another app never collides with a blind bind.
  local port=8080
  while [ "$port" -le 8090 ]; do
    if (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1; then
      port=$((port + 1))
    else
      break
    fi
  done
  if [ "$port" -gt 8090 ]; then
    echo "Notice: No free port in 8080-8090. Opening web files directly in browser..."
    return 1
  fi
  echo "==> Starting local HTTP server on http://localhost:$port..."

  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$port" &
  elif command -v python >/dev/null 2>&1; then
    # `python` may be py3 (http.server) or legacy py2 (SimpleHTTPServer) — probe it.
    if python -c "import http.server" >/dev/null 2>&1; then
      python -m http.server "$port" &
    else
      python -m SimpleHTTPServer "$port" &
    fi
  elif command -v npx >/dev/null 2>&1; then
    npx -y serve -p "$port" . &
  elif command -v php >/dev/null 2>&1; then
    php -S "localhost:$port" &
  else
    echo "Notice: No python/npx/php found. Opening web files directly in browser..."
    return 1
  fi
  SERVER_PID=$!
  SERVER_PORT=$port
  trap 'kill $SERVER_PID 2>/dev/null || true' EXIT INT TERM
  # Liveness: wait until the server actually answers (max ~10s), not a blind sleep.
  local waited=0
  while [ "$waited" -lt 10 ]; do
    if command -v curl >/dev/null 2>&1; then
      curl -sf -o /dev/null "http://127.0.0.1:$port/" && break
    else
      (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1 && break
    fi
    sleep 1; waited=$((waited + 1))
  done
  if ! (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1; then
    echo "Notice: Web server did not answer on port $port after ${waited}s; opening files directly..."
    kill $SERVER_PID 2>/dev/null || true
    return 1
  fi
  return 0
}

launch_web() {
  local app_name="${1:-todo}"
  if start_web_server; then
    local url="http://localhost:$SERVER_PORT/web/runner/app.html?app=$app_name"
    echo "==> Opening $url in browser..."
    open_url_or_file "$url"
    echo "Press [Ctrl+C] to stop web server."
    wait $SERVER_PID
  else
    open_url_or_file "$ROOT/web/runner/app.html?app=$app_name"
  fi
}

launch_film() {
  echo "==> Opening 'Dear Web' Release Film on YouTube..."
  open_url_or_file "https://youtu.be/4vPLnJ38SBM"
}

run_verification() {
  echo "=========================================================="
  echo " Yantra OS - Integrity & Standalone Verification Preflight"
  echo "=========================================================="
  local failures=0

  echo -n "Checking Native Host Runtime (bin/yantra.exe)... "
  if [ -f "$ROOT/bin/yantra.exe" ]; then
    echo "OK ($(stat -c%s "$ROOT/bin/yantra.exe" 2>/dev/null || stat -f%z "$ROOT/bin/yantra.exe") bytes)"
  else
    echo "MISSING (Download from GitHub Releases v1.0.0 or run via web runner)"
    failures=$((failures + 1))
  fi

  local apps=("typewriter" "desktop" "editor" "files" "gallery" "chess" "dna" "calc" "notes" "todo")
  for app in "${apps[@]}"; do
    echo -n "Checking App Module: $app... "
    if [ -f "$ROOT/apps/$app/app.wasm" ]; then
      echo "OK ($(stat -c%s "$ROOT/apps/$app/app.wasm" 2>/dev/null || stat -f%z "$ROOT/apps/$app/app.wasm") bytes)"
    else
      echo "MISSING"
      failures=$((failures + 1))
    fi
  done

  echo "=========================================================="
  local total=$(( ${#apps[@]} + 1 ))
  if [ "$failures" -eq 0 ]; then
    echo "ALL $total APP & RUNTIME CHECKS PASSED: Environment is 100% self-contained!"
  else
    echo "FAILED: $failures components were missing."
    exit 1
  fi
}

launch_app() {
  local target="$1"
  local wasm="$ROOT/apps/$target/app.wasm"

  if [ ! -f "$wasm" ]; then
    echo "Error: Application WASM module not found: $wasm"
    exit 1
  fi

  echo "==> Preparing to run: $target"

  # Case 1: Windows or MSYS / Git Bash
  if [ "$IS_WINDOWS" -eq 1 ]; then
    if [ ! -f "$ROOT/bin/yantra.exe" ]; then
      echo "==> Native Windows binary bundle not found in bin/."
      echo "==> Downloading standalone binary closure from GitHub Releases v1.0.0..."
      mkdir -p "$ROOT/bin"
      if curl -fL -o "$ROOT/yantra-windows-x64-bin.zip" "https://github.com/Yantra-lab/yantra-os/releases/download/v1.0.0/yantra-windows-x64-bin.zip"; then
        tar -xf "$ROOT/yantra-windows-x64-bin.zip" -C "$ROOT/bin" 2>/dev/null || unzip -q "$ROOT/yantra-windows-x64-bin.zip" -d "$ROOT/bin"
        rm -f "$ROOT/yantra-windows-x64-bin.zip"
      fi
    fi

    if [ ! -f "$ROOT/bin/yantra.exe" ]; then
      echo "==> Native binary not present. Falling back to universal web runner..."
      launch_web "$target"
      return 0
    fi

    local bin_win
    local wasm_win
    bin_win="$(to_win_path "$ROOT/bin")"
    wasm_win="$(to_win_path "$wasm")"
    
    echo "==> Launching native Windows host engine (bin/yantra.exe)..."
    export PATH="$ROOT/bin:$PATH"
    "$ROOT/bin/yantra.exe" "$wasm_win" &
    return 0
  fi

  # Case 2: Windows Subsystem for Linux (WSL)
  if [ "$IS_WSL" -eq 1 ]; then
    local win_root
    local wasm_win
    win_root="$(to_win_path "$ROOT")"
    wasm_win="$(to_win_path "$wasm")"
    
    echo "==> Launching native host engine via WSL Interop..."
    cmd.exe /c "set PATH=$win_root\\bin;%PATH% && start \"\" \"$win_root\\bin\\yantra.exe\" \"$wasm_win\"" 2>/dev/null || {
      echo "WSL direct exec failed; falling back to web runner..."
      launch_web "$target"
    }
    return 0
  fi

  # Case 3: Linux / macOS native binary check
  if [ -f "$ROOT/bin/yantra" ] && [ -x "$ROOT/bin/yantra" ]; then
    echo "==> Launching native Unix host (bin/yantra)..."
    "$ROOT/bin/yantra" "$wasm" &
    return 0
  fi

  # Case 4: Universal fallback for macOS / Linux without native compilation
  echo "==> Notice: Native GUI binary in bin/ is for Windows x86_64."
  echo "==> Launching WebAssembly module via universal web runner..."
  launch_web "$target"
}

# Interactive Menu if no arguments provided
interactive_menu() {
  echo ""
  echo "==========================================================="
  echo "      YANTRA OS — Universal Multi-OS Application Runner    "
  echo "==========================================================="
  echo " 1) Marlowe 44 Typewriter     (Vintage mechanical & Foley sound)"
  echo " 2) Desktop Window Shell      (Tiling window manager)"
  echo " 3) 3D Virtual Gallery        (3D Filament PBR exhibition)"
  echo " 4) Chess Study               (Interactive board evaluation)"
  echo " 5) 3D DNA Helix              (Real-time molecular visualizer)"
  echo " 6) Calculator                (Reactive state calculator)"
  echo " 7) Sticky Notes              (Minimal desktop text editor)"
  echo " 8) Todo App                  (Reactive list diffing task manager)"
  echo " 9) 'Dear Web' Film           (Opus 5.5 release film & screenplay)"
  echo "10) Run Browser Web Runner    (Serve any WASM app in browser)"
  echo "11) Integrity Preflight Check (Verify all binaries & assets)"
  echo " q) Quit"
  echo "==========================================================="
  read -r -p "Select an option [1-11, q]: " choice

  case "$choice" in
    1|typewriter) launch_app "typewriter" ;;
    2|desktop)    launch_app "desktop" ;;
    3|gallery)    launch_app "gallery" ;;
    4|chess)      launch_app "chess" ;;
    5|dna)        launch_app "dna" ;;
    6|calc)       launch_app "calc" ;;
    7|notes)      launch_app "notes" ;;
    8|todo)       launch_app "todo" ;;
    9|film)       launch_film ;;
    10|web)       launch_web "todo" ;;
    11|verify)    run_verification ;;
    q|Q)          echo "Exiting."; exit 0 ;;
    *)            echo "Invalid option: $choice"; exit 1 ;;
  esac
}

# Argument Router
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  interactive_menu
  exit 0
fi

case "$TARGET" in
  typewriter|1) launch_app "typewriter" ;;
  desktop|2)    launch_app "desktop" ;;
  editor)       launch_app "editor" ;;
  files)        launch_app "files" ;;
  gallery|3)    launch_app "gallery" ;;
  chess|4)      launch_app "chess" ;;
  dna|5)        launch_app "dna" ;;
  calc|6)       launch_app "calc" ;;
  notes|7)      launch_app "notes" ;;
  todo|8)       launch_app "todo" ;;
  film|dear-web|movie|9) launch_film ;;
  verify|check|test|11) run_verification ;;
  web|10)       launch_web "${2:-todo}" ;;
  help|--help|-h)
    echo "Usage: ./run.sh [app_name|target]"
    echo ""
    echo "Targets:"
    echo "  typewriter, desktop, editor, files, gallery, chess, dna, calc, notes, todo"
    echo "  film    - Watch the 'Dear Web' release film"
    echo "  web     - Launch browser-based WebAssembly runner"
    echo "  verify  - Run automated integrity preflight check"
    echo "  (no args) Launch interactive selection menu"
    exit 0
    ;;
  *)
    # Check if target is a custom app directory or wasm file
    if [ -f "$TARGET" ]; then
      if [ "$IS_WINDOWS" -eq 1 ]; then
        "$ROOT/bin/yantra.exe" "$(to_win_path "$TARGET")" &
      else
        launch_web "$TARGET"
      fi
    else
      echo "Unknown target '$TARGET'. Running interactive menu..."
      interactive_menu
    fi
    ;;
esac
