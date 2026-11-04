#!/usr/bin/env bash
# Yantra app-module build — Nim -> WebAssembly, tiny path.
#
# WHAT THIS DOES
#   Compiles a Nim app module to a freestanding wasm32 module that the Yantra
#   engine can load and run in a sandbox. No OS, and no libc beyond the mini-libc
#   in sdk/minilibc.
#
# WHY NOT WASI
#   Nim has no WASI target (see docs/EXECUTION-MODEL.md), and wasi-libc is large
#   anyway. An app module that needs memcpy, strlen and a number formatter should
#   not carry a full POSIX libc.
#
# USAGE
#   ./tools/build-wasm.sh <src.nim> <out.wasm> [flags]
#
#   flags:
#     --release   optimise harder (clang -O3, nim -d:release)
#     --no-libc   link NO mini-libc at all, for pure-computation modules
#
# GOTCHAS BAKED IN (each one cost real debugging time)
#   1. Native clang does NOT understand MSYS paths like /c/Users/... — include and
#      library paths MUST be native (C:/Users/...). `pwd -W` produces that.
#   2. --os:any (not standalone): standalone has no `except`, so std/json and any
#      library that catches exceptions would not compile. `any` needs signal.h (a
#      no-op stand-in in the mini-libc) and compiler-rt builtins (linked from wasi-sdk).
#      Cost: +5.5 KB on the counter. panicoverride.nim is still copied for old callers.
#   3. fmod must NOT be __builtin_fmod — on wasm that lowers to a libcall to fmod,
#      i.e. to itself.
#   4. Do not add clang -O2 to the Nim-generated C: it strength-reduces the
#      formatter's 64-bit divide into a __multi3 libcall, which becomes an
#      unresolved import and breaks instantiation.
#   5. `--export-all` makes every symbol a GC root, so --gc-sections cannot drop
#      unused mini-libc code. A pure-arithmetic module would therefore inherit an
#      unused `yantra_log` import (~18 KB) just by linking the library. That is
#      what --no-libc is for.

set -euo pipefail

SRC="${1:?usage: build-wasm.sh <src.nim> <out.wasm> [--release|--no-libc]}"
OUT="${2:?usage: build-wasm.sh <src.nim> <out.wasm> [--release|--no-libc]}"

RELEASE=0
NOLIBC=0
OPT=0
for _arg in "${@:3}"; do
  case "$_arg" in
    --release) RELEASE=1; OPT=1 ;;
    --opt) OPT=1 ;;
    --no-libc) NOLIBC=1 ;;
    *) echo "build-wasm: unknown flag '$_arg'" >&2; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MINILIBC="$ROOT/sdk/minilibc"

if [ "$NOLIBC" = "0" ] && [ ! -f "$MINILIBC/minilibc.c" ]; then
  echo "build-wasm: mini-libc not found at $MINILIBC" >&2
  exit 1
fi

# Native (Windows) paths — see gotcha 1.
pw() { pwd -W 2>/dev/null || pwd; }
ROOT_NATIVE="$(cd "$ROOT" && pw)"
SRC_NATIVE="$(cd "$(dirname "$SRC")" && pw)/$(basename "$SRC")"
WORK="$(dirname "$SRC_NATIVE")"

OPT_FLAGS="-O2"
NIM_FLAGS="${YANTRA_NIM_FLAGS:-}"   # extra nim flags from the environment (debugging)
if [ "$RELEASE" = "1" ]; then
  OPT_FLAGS="-O3"
  NIM_FLAGS="$NIM_FLAGS -d:release --opt:speed"
fi

INCLUDE_FLAGS=""
LINK_OBJ=""
if [ "$NOLIBC" = "0" ]; then
  MINILIBC_NATIVE="$(cd "$MINILIBC" && pw)"
  INCLUDE_FLAGS="-I$MINILIBC_NATIVE/include"

  # Compile the mini-libc to a real OBJECT file, not llvm bitcode.
  # WHY: linking -emit-llvm bitcode makes wasm-ld do codegen at link time, which
  # turns the formatter's 64-bit divide-by-constant into a `__multi3` (128-bit
  # multiply) libcall that shows up as an unresolved wasm import.
  OBJ="$WORK/minilibc.o"
  echo "build-wasm: compiling mini-libc (object file)"
  clang --target=wasm32-unknown-unknown $OPT_FLAGS -nostdlib -ffreestanding \
    -ffunction-sections -fdata-sections \
    -I "$MINILIBC_NATIVE/include" -c "$MINILIBC_NATIVE/minilibc.c" -o "$OBJ"
  LINK_OBJ="$OBJ"
  # compiler-rt builtins (128-bit multiply and friends) from the local wasi-sdk: Nim's
  # float parsing (std/json and others) reaches for them. Target-neutral; no WASI imports.
  for RT in "$ROOT"/third_party/wasi-sdk-*/lib/clang/*/lib/wasm32-unknown-wasi/libclang_rt.builtins.a; do
    [ -f "$RT" ] && LINK_OBJ="$LINK_OBJ $(cd "$(dirname "$RT")" && pw)/libclang_rt.builtins.a"
  done
else
  echo "build-wasm: --no-libc, skipping mini-libc (pure-computation module)"
fi

echo "build-wasm: compiling Nim -> wasm"
# The SDK lives in sdk/; app modules `import yantra`, so that path must be on
# the search path. panicoverride.nim is required by --os:standalone and is looked
# up next to the source file.
SDK_NATIVE="$ROOT_NATIVE/sdk"
if [ ! -f "$WORK/panicoverride.nim" ] && [ -f "$ROOT/sdk/panicoverride.nim" ]; then
  cp "$ROOT/sdk/panicoverride.nim" "$WORK/panicoverride.nim"
fi

# The nimcache MUST vary with the flags, or a -d: switch silently produces a
# stale wasm. Nim keys its object cache on the module graph and the flags, but
# NOT on a flag arriving through a different route: building
# YANTRA_NIM_FLAGS=-d:minipaint_gallery and then a plain build reused the
# flagged @mapp.nim.c, and the "plain" wasm still contained the gallery. That
# cost a confused debugging detour - a screenshot showed debug scaffolding in a
# build that was supposed to have it compiled out.
#
# Hash the flags into the cache directory name so a flag change is a different
# cache by construction, rather than something the caller has to remember.
NIMCACHE_KEY="$(printf '%s' "$NIM_FLAGS" | md5sum | cut -c1-8)"
NIMCACHE_DIR="$WORK/nimcache$NIMCACHE_KEY"

# -d:nimAllocPagesViaMalloc: Nim's own allocator (real free + reuse), taking its pages
# from the mini-libc. Without it the default standalone allocator corrupts data when
# a seq grows: the first element's string came back empty (E4 bisect). -d:useMalloc
# also works but leaks without bound, because the mini-libc free is a no-op.
#
# -d:yantra_engine: REQUIRED here, not optional. sdk/ui/paint.nim:86 gates its
# layer bindings on `defined(wasm) and not defined(yantra_engine)` and compiles
# them to NO-OPS otherwise. So without this flag a module built by THIS script
# silently discards every Layer.draw/filter/read/write: the desk texture, the
# paper texture and the stamped letter glyphs all build a large Draw string that
# is thrown away, the build stays clean, and the app looks correct in a harness
# because layer ids are still allocated and still emit `Y n`. It renders a
# correctly laid-out scene with none of its pixel-heavy surfaces.
# This script's only output is a module the engine loads, and host/host.nim
# (cbLayerNew/cbLayerDraw/cbLayerFilter, ~line 1069) always provides y_layer_*,
# so the real bindings are always the correct ones here. `yantra_headless` and a
# plain `nim c` remain the no-op paths.
nim c --cc:clang --cpu:wasm32 --os:any --noMain:on --mm:arc -d:nimAllocPagesViaMalloc \
  -d:yantra_engine \
  --hints:off --warnings:off $NIM_FLAGS \
  --path:"$SDK_NATIVE" \
  --import:yantra \
  --nimcache:"$NIMCACHE_DIR" \
  --passC:"--target=wasm32-unknown-unknown -nostdlib -ffreestanding -ffunction-sections -fdata-sections $INCLUDE_FLAGS" \
  --passL:"--target=wasm32-unknown-unknown -nostdlib $LINK_OBJ -Wl,--no-entry -Wl,--export-all -Wl,--allow-undefined" \
  -o:"$OUT" "$SRC_NATIVE"

# Optional size squeeze, for --release builds only. wasm-opt is not a hard dependency.
# The repo's own toolchain folder works even when it is not on PATH (the gate's shell).
[ -x "$ROOT/third_party/msys64/mingw64/bin/wasm-opt.exe" ] && ! command -v wasm-opt >/dev/null 2>&1 && \
  export PATH="$ROOT/third_party/msys64/mingw64/bin:$PATH"
if [ "$RELEASE" != "1" ]; then
  :
elif command -v wasm-opt >/dev/null 2>&1; then
  rm -f "$OUT.opt"
  BINARYEN_CORES=1 wasm-opt -Oz --strip-debug --strip-producers --enable-bulk-memory "$OUT" -o "$OUT.opt" >/dev/null 2>&1 &
  opt_pid=$!
  waited=0
  while kill -0 "$opt_pid" 2>/dev/null && [ "$waited" -lt "${YANTRA_WASM_OPT_TIMEOUT:-60}" ]; do
    sleep 1; waited=$((waited + 1))
  done
  if ! kill -0 "$opt_pid" 2>/dev/null && wait "$opt_pid" && [ -s "$OUT.opt" ]; then
    mv "$OUT.opt" "$OUT"
    echo "build-wasm: wasm-opt -Oz -> $(stat -c%s "$OUT") bytes"
  else
    echo "build-wasm: wasm-opt failed or did not finish in ${waited}s, keeping the unoptimised module (SZ1)"
  fi
else
  echo "build-wasm: wasm-opt not found, skipping size squeeze (optional)"
fi

SIZE=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")
echo "build-wasm: wrote $OUT ($SIZE bytes)"
