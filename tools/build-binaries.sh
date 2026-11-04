#!/usr/bin/env bash
# build-binaries.sh — build the Yantra desktop app for Linux x86_64 and Windows x86_64
# from ONE commit of this repo, and cut the two release bundles.
#
#   bash yantra-os/tools/build-binaries.sh                    # both targets into a temp dir
#   bash yantra-os/tools/build-binaries.sh --out /tmp/stage   # into a chosen dir
#   bash yantra-os/tools/build-binaries.sh --targets windows   # one target
#
# Produces, under --out:
#   linux-x64/                 yantra, lib/ (15 bundled .so), apps/ (12 modules), run-yantra.sh, BUILD-INFO.txt
#   yantra-linux-x64.tar.gz    the same directory, tarred with pinned flags (stable sha256)
#   windows-x64/               yantra.exe, the DLL set it needs, apps/, assets/, Yantra.bat, BUILD-INFO.txt
#   yantra-windows-x64.zip     the same directory, zipped under a top-level yantra/ (stable sha256)
#   SHA256SUMS                 sha256sum -c format for the two bundles
#   BUILD-INFO.txt             provenance for both
#
# WHY IT IS WRITTEN THIS WAY (measured on this box, 2026-11-06)
#   * The build tree is a `git archive HEAD` export, not a working copy: live lanes edit the
#     working trees, and an export of a commit is the only tree two people can agree on.
#   * There is no gcc on this box. Linux builds with clang (/usr/bin/clang) through Nim's
#     --cc:clang; the MinGW cross toolchain is the *-posix* variant because the win32-threads
#     libstdc++ of Debian's gcc 10 has no std::mutex / std::condition_variable at all
#     (libs/nimskia/src/skia_shim.cpp and Jolt need them). That is a real, silent-looking
#     failure: the error reads "'mutex' in namespace 'std' does not name a type".
#   * `third_party/` and `libs/*/{vendor,build}` are gitignored and hold the C/C++ toolchains
#     (Skia, FFmpeg, SDL3, Filament, wasmtime, Yoga source). They are linked into the build
#     tree from the repo root rather than rebuilt: rebuilding Skia/Filament from source is a
#     multi-hour job that is not what this script is about.
#   * Several libs in this tree compute their include/library paths with the *target* OS's
#     path separator, so a Windows cross-compile emits `-I\tmp\...`. That path does not exist
#     on Linux, so this script adds the same directories again as POSIX paths (--passC) and
#     creates the exact mangled names the linker is handed (see "mangled path shims" below).
#     Removing that hack means fixing the libs; this script redirects instead of editing them.
#   * Windows source code needs _WIN32_WINNT=0x0601: host/sys_win.c uses
#     IP_ADAPTER_ADDRESSES.FirstGatewayAddress, which mingw-w64 only declares for Vista+.
#   * nimav/nimcurl/nimsdl3/nimjolt expect an MSYS2 mingw64 prefix for Windows headers and
#     import libraries (that is how the product has always been built on Windows).
#     Pass one with --msys-prefix or set YANTRA_MSYS_PREFIX.
#
# WHAT IS BUILT HERE vs CARRIED (never claim more than this)
#   BUILT here, from source, by this script:
#     yantra (Linux ELF) · yantra.exe (Windows PE) · libyoga.a (Windows, mingw) ·
#     libminiaudio.a (Windows, mingw) · libwasmtime.a (Windows import lib, generated from the
#     DLL's export table with dlltool) · the bundles themselves.
#   CARRIED (third-party binaries that are not built from source here, provenance recorded
#   in BUILD-INFO.txt as carried=<file>=<sha256>@<where>): the Skia/FFmpeg/SDL3/ICU/HarfBuzz/
#   Jolt/curl DLLs from the MSYS2 prefix, wasmtime.dll, yfilament.dll (Filament ships MSVC
#   builds; rebuilding its Windows shim needs MSVC), and the 12 app .wasm modules committed in
#   the repo (built by yantra-os/tools/build-wasm.sh, not by this script).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YOS="$(cd "$HERE/.." && pwd)"          # .../yantra-os
REPO="$(cd "$YOS/.." && pwd)"          # repo root (has third_party/, libs/, host/, render/)

# ----------------------------------------------------------------------------- defaults
OUT="${YANTRA_BINARIES_OUT:-}"
TARGETS="linux,windows"
TREE=""
KEEP_TREE=0
MSYS="${YANTRA_MSYS_PREFIX:-}"
MAIN="${YANTRA_MAIN_TREE:-}"
WIN_DLL_DIR="${YANTRA_WIN_DLL_DIR:-/tmp/win-dist/yantra}"
WIN_SUBSYSTEM="gui"
MSVC_RT="${YANTRA_MSVC_RUNTIME:-}"
NIM_BIN="${YANTRA_NIM:-/home/ubuntu/tools/nim-2.2.4/bin/nim}"
CLANG_BIN="${YANTRA_CLANG:-/usr/bin/clang}"
CLANGXX_BIN="${YANTRA_CLANGXX:-/usr/bin/clang++}"
MGCC="${YANTRA_MINGW_GCC:-/usr/bin/x86_64-w64-mingw32-gcc-posix}"
MGXX="${YANTRA_MINGW_GXX:-/usr/bin/x86_64-w64-mingw32-g++-posix}"
MAR="${YANTRA_MINGW_AR:-/usr/bin/x86_64-w64-mingw32-ar}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    --out=*) OUT="${1#*=}"; shift ;;
    --targets) TARGETS="${2:?--targets needs linux,windows}"; shift 2 ;;
    --targets=*) TARGETS="${1#*=}"; shift ;;
    --tree) TREE="${2:?--tree needs a directory}"; shift 2 ;;
    --keep-tree) KEEP_TREE=1; shift ;;
    --main-tree) MAIN="${2:?--main-tree needs a directory}"; shift 2 ;;
    --main-tree=*) MAIN="${1#*=}"; shift ;;
    --msys-prefix) MSYS="${2:?--msys-prefix needs a directory}"; shift 2 ;;
    --msys-prefix=*) MSYS="${1#*=}"; shift ;;
    --win-dll-dir) WIN_DLL_DIR="${2:?--win-dll-dir needs a directory}"; shift 2 ;;
    --win-subsystem) WIN_SUBSYSTEM="${2:?gui|console}"; shift 2 ;;
    --msvc-runtime) MSVC_RT="${2:?--msvc-runtime needs a directory}"; shift 2 ;;
    --msvc-runtime=*) MSVC_RT="${1#*=}"; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
want_file() { [ -e "$1" ] || die "missing: $1${2:+ — $2}"; }

case ",$TARGETS," in *,linux,*|*,windows,*) ;; *) die "--targets must list linux and/or windows" ;; esac
[ -n "$OUT" ] || OUT="$(mktemp -d /tmp/yantra-binaries-XXXXXX)"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

cd "$REPO"
SRC_HEAD="$(git rev-parse HEAD)"
# The "source commit" is the newest commit that touched something the binaries are built from.
# This is what refresh-binaries.sh --check compares against, so committing the bundles
# themselves (yantra-os/downloads/) must not make them look stale.
SOURCE_PATHS=""
for p in render host libs sdk tools protocol yantra-os/apps yantra-os/render yantra-os/host \
         yantra-os/sdk yantra-os/assets yantra-os/store; do
  [ -e "$REPO/$p" ] && SOURCE_PATHS="$SOURCE_PATHS $p"
done
# shellcheck disable=SC2086
SRC_COMMIT="$(git rev-list -1 "$SRC_HEAD" -- $SOURCE_PATHS)"
SRC_DATE="$(git log -1 --format=%cI "$SRC_COMMIT")"
SRC_SUBJECT="$(git log -1 --format=%s "$SRC_COMMIT")"
DIRTY=0; git diff --quiet HEAD -- 2>/dev/null || DIRTY=1

# third_party/ and libs/*/{build,vendor} are gitignored: they live in whichever checkout has
# them built (this worktree may be a fresh `git worktree add` with none). Find that tree.
if [ -z "$MAIN" ]; then
  for cand in "$REPO" "$(git -C "$REPO" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')" \
              /home/ubuntu/yantra; do
    [ -n "$cand" ] && [ -d "$cand/third_party" ] && MAIN="$cand" && break
  done
fi
[ -n "$MAIN" ] && MAIN="$(cd "$MAIN" && pwd)"
say "build-binaries"
say "  repo          : $REPO"
say "  head          : $SRC_HEAD"
say "  source commit : $SRC_COMMIT ($SRC_DATE) — $(printf '%s' "$SRC_SUBJECT" | cut -c1-60)"
say "  out           : $OUT"
say "  toolchain tree: ${MAIN:-(none found — pass --main-tree)}"
say "  targets       : $TARGETS"

# --------------------------------------------------------------- 1. the clean build tree
# `git archive` writes exactly the tracked files of the commit: no lane's half-saved edit, no
# stale object. third_party/ and libs/*/{vendor,build} are then linked from the repo root.
make_tree() {
  local dest="$1"
  step "clean build tree from $SRC_COMMIT -> $dest"
  rm -rf "$dest"; mkdir -p "$dest"
  git archive "$SRC_COMMIT" | tar -x -C "$dest" || die "git archive failed"
  [ -d "$MAIN/third_party" ] || die "no $MAIN/third_party — the C/C++ toolchains (Skia, SDL3, FFmpeg, Filament, wasmtime) live there; set it up once with tools/setup.sh, then pass --main-tree DIR"
  ln -sfn "$MAIN/third_party" "$dest/third_party"
  local d b
  for d in "$MAIN"/libs/*/vendor; do
    [ -d "$d" ] || continue
    b="$(basename "$(dirname "$d")")"
    ln -sfn "$d" "$dest/libs/$b/vendor"
  done
  for d in "$MAIN"/libs/*/build; do
    [ -d "$d" ] || continue
    b="$(basename "$(dirname "$d")")"
    # nimyoga/nimminiaudio are rebuilt for the target by this script; nimfilament's shared
    # object is copied. A live lane rebuilding these in the main checkout is exactly the
    # hazard that broke one refresh (an aarch64 libyoga.a appeared mid-build), so nothing
    # under these three comes from a symlink into a working tree.
    case "$b" in nimyoga|nimminiaudio|nimfilament) continue ;; esac
    ln -sfn "$d" "$dest/libs/$b/build"
  done
  # The release tree carries its own render/native/{devwatch,mcp_server}.nim and its own
  # yantra_run.nim; the engine's entrypoint needs them beside engine.nim.
  cp -f "$dest/yantra-os/render/native/devwatch.nim"   "$dest/render/native/devwatch.nim"
  cp -f "$dest/yantra-os/render/native/mcp_server.nim" "$dest/render/native/mcp_server.nim"
  sed 's|staticRead("../../apps/desktop/app.wasm")|staticRead("../../yantra-os/apps/desktop/app.wasm")|' \
      "$dest/yantra-os/render/native/yantra_run.nim" > "$dest/render/native/yantra_stage1.nim"
  say "  tree files    : $(find "$dest" -type f | wc -l) (plus symlinked toolchains)"
}

NIM_PATHS=(-p:tools -p:libs/nimav/src -p:libs/nimcurl/src -p:libs/nimfilament/src -p:libs/nimjolt/src
           -p:libs/nimaccesskit/src -p:libs/nimwasmtime/src -p:libs/nimskia/src -p:libs/nimyoga/src
           -p:libs/nimminiaudio/src -p:libs/nimspell/src -p:libs/nimrtc/src -p:libs/nimsdl3/src -p:host)
COMMON_FLAGS=(--hints:off --warnings:off -d:release)

# ================================================================= 2. LINUX
build_linux_static_libs() {
  local tree="$1" ysrc="$MAIN/third_party/yoga/yoga-3.1.0"
  step "linux: static third-party libraries (clang, in-tree)"
  want_file "$ysrc" "Yoga source"
  want_file "$MAIN/third_party/miniaudio/miniaudio.h" "miniaudio source"
  rm -rf "$tree/libs/nimyoga/build"; mkdir -p "$tree/libs/nimyoga/build"
  ( cd "$tree/libs/nimyoga/build" \
    && "$CLANGXX_BIN" -std=c++20 -O2 -I"$ysrc" -c "$ysrc"/yoga/*.cpp "$ysrc"/yoga/*/*.cpp \
    && ar rcs libyoga.a ./*.o && rm -f ./*.o ) || die "yoga build (linux) failed"
  say "  libyoga.a      : $(stat -c%s "$tree/libs/nimyoga/build/libyoga.a") B"
  rm -rf "$tree/libs/nimminiaudio/build"; mkdir -p "$tree/libs/nimminiaudio/build"
  ( cd "$tree/libs/nimminiaudio/build" \
    && "$CLANG_BIN" -O2 -c -DMINIAUDIO_IMPLEMENTATION -x c "$MAIN/third_party/miniaudio/miniaudio.h" -o miniaudio.o \
    && ar rcs libminiaudio.a miniaudio.o && rm -f miniaudio.o ) || die "miniaudio build (linux) failed"
  say "  libminiaudio.a : $(stat -c%s "$tree/libs/nimminiaudio/build/libminiaudio.a") B"
  # Filament's shim is a real build of libs/nimfilament (hours); copy the .so so a lane
  # rebuilding it mid-run cannot change the bytes we link against.
  rm -rf "$tree/libs/nimfilament/build"; mkdir -p "$tree/libs/nimfilament/build"
  # Filament's shim is a real build (hours) that this script does not repeat, and live lanes
  # cross-built it for other arches in the main checkout twice today. Take it only if it is
  # an x86-64 ELF; otherwise fall back to the copy in the last released bundle.
  local shim_src="" cand
  for cand in "$MAIN/libs/nimfilament/build/libyfilament.so"; do
    [ -f "$cand" ] || continue
    file -b "$cand" | grep -q 'ELF 64-bit LSB.*x86-64' && shim_src="$cand"
  done
  if [ -z "$shim_src" ]; then
    cand="$YOS/downloads/yantra-linux-x64.tar.gz"
    if [ -f "$cand" ]; then
      # `tar -tzf | grep -q` trips pipefail (grep exits early, tar gets SIGPIPE), so list to a file
      tar -tzf "$cand" > "$OUT/.tar-listing.txt"
      grep -qx 'linux-x64/lib/libyfilament.so' "$OUT/.tar-listing.txt" || cand=""
    fi
    if [ -n "$cand" ]; then
      tar -xzf "$cand" -O linux-x64/lib/libyfilament.so > "$tree/libs/nimfilament/build/libyfilament.so"
      file -b "$tree/libs/nimfilament/build/libyfilament.so" | grep -q 'ELF 64-bit LSB.*x86-64' \
        || die "the carried libyfilament.so from $cand is not x86-64 either"
      shim_src="carried:$cand (the previous release bundle)"
      say "  NOTE: $MAIN/libs/nimfilament/build/libyfilament.so is not x86-64 (a lane rebuilt it for another arch) — carried the released copy instead"
    fi
  fi
  [ -n "$shim_src" ] || die "no x86-64 libyfilament.so in $MAIN/libs/nimfilament/build and no released bundle to carry one from"
  [ -f "$tree/libs/nimfilament/build/libyfilament.so" ] || cp -f "$MAIN/libs/nimfilament/build/libyfilament.so" "$tree/libs/nimfilament/build/"
  FILEL_SHIM_SRC="$shim_src"
  say "  libyfilament.so: $(stat -c%s "$tree/libs/nimfilament/build/libyfilament.so") B from $shim_src"
}

build_linux() {
  local tree="$1" dest="$OUT/linux-x64"
  build_linux_static_libs "$tree"
  step "linux: compile"
  want_file "$NIM_BIN" "Nim 2.2.4 (set YANTRA_NIM)"
  want_file "$CLANG_BIN" "clang (no gcc on this box)"
  local cmd=("$NIM_BIN" c "${COMMON_FLAGS[@]}" --cc:clang
             --clang.exe:"$CLANG_BIN" --clang.linkerexe:"$CLANG_BIN" --clang.cpp.exe:"$CLANGXX_BIN"
             --nimcache:"$tree/.nimcache-linux" "${NIM_PATHS[@]}" -o:"$OUT/yantra-linux-raw"
             render/native/yantra_stage1.nim)
  say "  cd $tree && ${cmd[*]}"
  ( cd "$tree" && "${cmd[@]}" ) || die "linux compile failed"
  local bin="$OUT/yantra-linux-raw"
  want_file "$bin"
  say "  binary        : $bin  $(stat -c%s "$bin") B  sha256 $(sha256sum "$bin" | cut -c1-16)"
  say "  defines       : -d:release --cc:clang (clang $(clang --version 2>/dev/null | head -1 | awk '{print $3}'))"

  step "linux: bundle shared libraries + \$ORIGIN rpath"
  local dest="$OUT/linux-x64" libdir="$dest/lib"
  rm -rf "$dest"; mkdir -p "$libdir" "$dest/apps"
  cp -f "$bin" "$dest/yantra"; chmod 0755 "$dest/yantra"

  local n_apps=0 w id
  shopt -s nullglob
  for w in "$tree"/yantra-os/apps/*/app.wasm; do
    id="$(basename "$(dirname "$w")")"
    mkdir -p "$dest/apps/$id"; cp -f "$w" "$dest/apps/$id/app.wasm"; n_apps=$((n_apps+1))
  done
  shopt -u nullglob
  [ "$n_apps" -gt 0 ] || die "no app modules under $tree/yantra-os/apps"
  say "  apps          : $n_apps modules"

  # Base-system directories are canonicalised once (/lib == /usr/lib on this box).
  local -a SYSTEM_DIRS=()
  local d
  while IFS= read -r d; do [ -n "$d" ] && SYSTEM_DIRS+=("$d"); done < <(
    for d in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64; do
      [ -d "$d" ] && realpath "$d"
    done | sort -u)
  is_system_path() { local p="$1" x; for x in "${SYSTEM_DIRS[@]}"; do case "$p" in "$x"/*) return 0;; esac; done; return 1; }
  is_glibc_name() {
    case "$1" in libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|ld-linux-x86-64.so.*|linux-vdso.so.*) return 0;; esac
    return 1; }

  # Recursive ldd closure. LD_LIBRARY_PATH points at lib/ so a bundled library's own deps are
  # resolved the way they will be at run time once bundled.
  declare -A BUNDLED_SRC=() SEEN=(); local -a QUEUE=("$dest/yantra")
  local target line name rest path rp out destlib
  local unresolved=0
  while [ "${#QUEUE[@]}" -gt 0 ]; do
    target="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}")
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      case "$line" in *" => "*) ;; *) continue ;; esac
      name="${line%% => *}"; rest="${line#* => }"; path="${rest%% (*}"
      [ -n "$name" ] || continue
      if [ "$path" = "not found" ]; then say "  NOT-FOUND: $name (needed by $(basename "$target"))"; unresolved=$((unresolved+1)); continue; fi
      [ -n "${SEEN[$name]:-}" ] && continue
      if is_glibc_name "$name"; then SEEN[$name]="glibc"; continue; fi
      rp="$(realpath "$path")"
      if is_system_path "$rp"; then SEEN[$name]="system"; continue; fi
      destlib="$libdir/$name"
      [ -e "$destlib" ] || { cp -Lf "$rp" "$destlib"; chmod 0755 "$destlib"; }
      SEEN[$name]="bundled"; BUNDLED_SRC[$name]="$rp"; QUEUE+=("$destlib")
    done < <(LD_LIBRARY_PATH="$libdir" ldd "$target" 2>&1 || true)
  done
  say "  closure       : ${#BUNDLED_SRC[@]} bundled, $unresolved unresolved"
  [ "$unresolved" -eq 0 ] || die "$unresolved shared libraries not found while bundling"

  patchelf --set-rpath '$ORIGIN/lib' "$dest/yantra" || die "patchelf on yantra failed"
  local lib
  for lib in "$libdir"/*; do [ -f "$lib" ] && patchelf --set-rpath '$ORIGIN' "$lib"; done
  printf '#!/usr/bin/env bash\ncd "$(dirname "$0")"\nexec ./yantra "$@"\n' > "$dest/run-yantra.sh"
  chmod 0755 "$dest/run-yantra.sh"

  # Self-check: empty environment, empty LD_LIBRARY_PATH, nothing may resolve outside lib/.
  local bad=0
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in *" => "*) ;; *) continue ;; esac
    name="${line%% => *}"; rest="${line#* => }"; path="${rest%% (*}"
    if [ "$path" = "not found" ]; then say "  SELFCHECK FAIL: $name not found"; bad=$((bad+1)); continue; fi
    rp="$(realpath "$path")"
    case "$rp" in "$libdir"/*) continue ;; esac
    is_system_path "$rp" && continue
    is_glibc_name "$name" && continue
    say "  SELFCHECK FAIL: $name -> $rp (outside the bundle)"; bad=$((bad+1))
  done < <(env -i PATH=/usr/bin:/bin LD_LIBRARY_PATH= ldd "$dest/yantra" 2>&1 || true)
  [ "$bad" -eq 0 ] || die "self-check found $bad dependencies outside the bundle"
  say "  selfcheck     : OK — every non-system dependency resolves inside lib/"

  local b s
  b="$(stat -c%s "$dest/yantra")"; s="$(sha256sum "$dest/yantra" | awk '{print $1}')"
  {
    echo "target=linux-x64"
    echo "artifact=yantra"
    echo "bytes=$b"
    echo "sha256=$s"
    echo "source_commit=$SRC_COMMIT"
    echo "source_commit_date=$SRC_DATE"
    echo "built_utc=$SRC_DATE"                 # pinned to the commit: keeps the bundles byte-stable
    echo "defines=-d:release --cc:clang (no gcc on this box); nim 2.2.4"
    echo "carried=libyfilament.so=$(sha256sum "$libdir/libyfilament.so" 2>/dev/null | awk '{print $1}')@Filament shim built outside this script (Filament ships no reusable Linux build here); source: ${FILEL_SHIM_SRC:-$MAIN}"
    echo "bundled_libs=${#BUNDLED_SRC[@]}"
    echo "apps=$n_apps"
    echo "rpath=yantra:\$ORIGIN/lib lib:\$ORIGIN"
    echo "toolchain=clang $(clang --version 2>/dev/null | head -1 | awk '{print $3}'), nim $("$NIM_BIN" --version 2>/dev/null | head -1 | cut -d' ' -f4)"
  } > "$dest/BUILD-INFO.txt"

  step "linux: pinned tarball"
  local tarball="$OUT/yantra-linux-x64.tar.gz"
  rm -f "$tarball"
  tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 --format=gnu \
      -czf "$tarball" -C "$OUT" linux-x64 || die "tar failed"
  say "  $tarball  $(stat -c%s "$tarball") B  sha256 $(sha256sum "$tarball" | awk '{print $1}')  entries $(tar -tzf "$tarball" | wc -l)"
  LINUX_BYTES="$(stat -c%s "$tarball")"; LINUX_SHA="$(sha256sum "$tarball" | awk '{print $1}')"
}

# ================================================================= 3. WINDOWS
# Two libs the link needs are static archives that must exist for the *target* arch; the
# prebuilt ones in libs/*/build are Linux ELF archives. Build them with MinGW.
build_win_static_libs() {
  local tree="$1" ysrc="$MAIN/third_party/yoga/yoga-3.1.0"
  step "windows: static third-party libraries (MinGW)"
  want_file "$MGXX"  "MinGW-w64 g++ (posix threads variant)"
  want_file "$ysrc"  "Yoga source"
  want_file "$MAIN/third_party/miniaudio/miniaudio.h" "miniaudio source"

  # Yoga 3.1.0 uses std::bit_cast, which libstdc++ 10 (this cross compiler) has no <bit>
  # entry for. One 25-line header supplies it; -I on the shim puts it before the system <bit>.
  local shim="$tree/.winbuild/shim"; mkdir -p "$shim"
  cat > "$shim/bit" <<'BITEOF'
#pragma once
#include_next <bit>
#ifndef __cpp_lib_bit_cast
#define __cpp_lib_bit_cast 201806L
#include <cstring>
#include <type_traits>
namespace std {
  template <class To, class From>
  constexpr typename enable_if<sizeof(To) == sizeof(From) &&
                                 is_trivially_copyable<From>::value &&
                                 is_trivially_copyable<To>::value, To>::type
  bit_cast(const From& src) noexcept { To d; __builtin_memcpy(&d, &src, sizeof(To)); return d; }
}
#endif
BITEOF
  rm -rf "$tree/libs/nimyoga/build"; mkdir -p "$tree/libs/nimyoga/build"
  ( cd "$tree/libs/nimyoga/build" \
    && "$MGXX" -std=c++20 -O2 -I"$shim" -I"$ysrc" -c "$ysrc"/yoga/*.cpp "$ysrc"/yoga/*/*.cpp \
    && "$MAR" rcs libyoga.a ./*.o && rm -f ./*.o ) || die "yoga cross-build failed"
  say "  libyoga.a      : $(stat -c%s "$tree/libs/nimyoga/build/libyoga.a") B"

  rm -rf "$tree/libs/nimminiaudio/build"; mkdir -p "$tree/libs/nimminiaudio/build"
  ( cd "$tree/libs/nimminiaudio/build" \
    && "$MGCC" -O2 -c -DMINIAUDIO_IMPLEMENTATION -x c "$MAIN/third_party/miniaudio/miniaudio.h" -o miniaudio.o \
    && "$MAR" rcs libminiaudio.a miniaudio.o && rm -f miniaudio.o ) || die "miniaudio cross-build failed"
  say "  libminiaudio.a : $(stat -c%s "$tree/libs/nimminiaudio/build/libminiaudio.a") B"
}

# The MSYS2 import libraries for the DLLs we bundle, plus a generated one for wasmtime, in one
# directory that -L points at. Only the ones the link asks for (a stray libmingwex.a from the
# MSYS2 prefix would shadow Debian's UCRT/mingw CRT and the link fails on crt2.o symbols).
make_winwinlib() {
  local tree="$1" wl="$tree/.winbuild/winlib" n
  mkdir -p "$wl"
  for n in skia skparagraph skshaper skunicode_core skunicode_icu icuuc icuin icudt harfbuzz \
           SDL3 curl avdevice avformat avcodec avutil swscale swresample Jolt; do
    if [ -f "$MSYS/lib/lib$n.dll.a" ]; then cp -f "$MSYS/lib/lib$n.dll.a" "$wl/"
    elif [ -f "$MSYS/lib/lib$n.a" ]; then cp -f "$MSYS/lib/lib$n.a" "$wl/"; fi
  done
  # nimav and nimsdl3 pass -lpthread themselves; Nim's mingw config appends `-Wl,-Bstatic
  # -lpthread` last. If the *static* libpthread.a is found after the import lib, every symbol
  # is defined twice. An import lib named libpthread.a (found first, via -L) keeps them equal.
  local mlib="${YANTRA_MINGW_LIB:-/usr/x86_64-w64-mingw32/lib}"
  [ -f "$mlib/libpthread.dll.a" ] && cp -f "$mlib/libpthread.dll.a" "$wl/libpthread.a"
  # wasmtime is not an MSYS2 package: generate its import library from the DLL we will bundle.
  local wt="$WIN_DLL_DIR/wasmtime.dll"
  if [ -f "$wt" ]; then
    python3 - "$wt" > "$tree/.winbuild/wasmtime.def" <<'PYDEF'
import subprocess, sys
dll = sys.argv[1]
out = subprocess.run(["x86_64-w64-mingw32-objdump","-p",dll],capture_output=True,text=True).stdout
names, on = [], False
for line in out.splitlines():
    if "[Ordinal/Name Pointer] Table" in line: on = True; continue
    if on:
        t = line.strip()
        if not t: break
        parts = t.split()
        if parts and parts[0].startswith("["): parts = parts[1:]
        if parts: names.append(parts[-1])
print("LIBRARY wasmtime.dll"); print("EXPORTS")
for n in names: print("    " + n)
PYDEF
    /usr/bin/x86_64-w64-mingw32-dlltool -d "$tree/.winbuild/wasmtime.def" -l "$wl/libwasmtime.a" -D wasmtime.dll \
      || die "dlltool could not build libwasmtime.a"
    say "  libwasmtime.a  : $(stat -c%s "$wl/libwasmtime.a") B (generated from $(basename "$wt")'s exports)"
  else
    die "no wasmtime.dll in $WIN_DLL_DIR (needed for its import library); pass --win-dll-dir"
  fi
  say "  import libs    : $(ls "$wl" | wc -l) in $wl"
}

build_windows() {
  local tree="$1" dest="$OUT/windows-x64"
  step "windows: compile (MinGW-w64 cross, $WIN_SUBSYSTEM subsystem)"
  want_file "$MGCC"; want_file "$MGXX"
  if [ -z "$MSYS" ]; then
    for cand in /tmp/wt-windows-current-scratch/msys-sdk/mingw64 \
                "$MAIN/third_party/msys64/mingw64" /opt/msys64/mingw64 /tmp/msys64/mingw64; do
      [ -d "$cand/include" ] && [ -d "$cand/lib" ] && MSYS="$cand" && break
    done
  fi
  [ -n "$MSYS" ] || die "no MSYS2 mingw64 prefix found: pass --msys-prefix DIR (or set YANTRA_MSYS_PREFIX).
  It must contain include/ (skia, SDL3, Jolt, ICU, ffmpeg headers) and lib/ (their import libraries);
  the Windows build cannot link without it."
  [ -d "$MSYS/include" ] || die "$MSYS does not look like an MSYS2 mingw64 prefix (no include/)"

  build_win_static_libs "$tree"
  make_winwinlib "$tree"

  # The libs compute paths with the TARGET's separator, so Nim hands the compiler and the
  # linker `\tmp\...` paths that do not exist on Linux. Shim them under exactly the names the
  # tools receive: an unquoted path loses its backslashes to the shell; a quoted one keeps them.
  step "windows: mangled path shims (target-OS separators in the libs' own paths)"
  local bs mang yf joltname
  bs="${tree//\//\\}"          # /a/b -> \a\b   (what the libs emit)
  mang="${bs//\\/}"            # a/b    (what the shell leaves of an unquoted \a\b)
  mkdir -p "$tree/${mang}libsnimwasmtimebuild"
  cp -f "$tree/.winbuild/winlib/libwasmtime.a" "$tree/${mang}libsnimwasmtimebuild/"
  yf="$WIN_DLL_DIR/yfilament.dll"
  [ -f "$yf" ] || die "no yfilament.dll in $WIN_DLL_DIR (Filament's Windows shim is carried, not built here)"
  ln -sfn "$yf" "$tree/${mang}libsnimfilamentbuildyfilament.dll"
  joltname="${bs}\\third_party\\msys64\\mingw64\\lib\\libJolt.dll.a"
  ln -sfn "$MSYS/lib/libJolt.dll.a" "$tree/${joltname}"
  say "  ${mang}libsnimwasmtimebuild/  ${mang}libsnimfilamentbuildyfilament.dll  ${joltname}"

  # mingw's libstdc++ 10 <thread> does not pull <mutex>/<condition_variable>; skia_shim.cpp and
  # Jolt's headers use them directly. Force-included for C++ translation units only.
  cat > "$tree/.winbuild/winprelude.h" <<'PREEOF'
#ifndef YANTRA_WIN_PRELUDE_H
#define YANTRA_WIN_PRELUDE_H
#ifdef __cplusplus
#include <mutex>
#include <condition_variable>
#include <thread>
#include <cstring>
#include <cstdint>
#endif
#endif
PREEOF

  # PE headers carry a link timestamp, so two identical links produce different bytes.
  # GNU ld honours SOURCE_DATE_EPOCH for it; pin it to the source commit's own time.
  export SOURCE_DATE_EPOCH="$(git -C "$REPO" log -1 --format=%ct "$SRC_COMMIT")"
  local subflag=(); [ "$WIN_SUBSYSTEM" = gui ] && subflag=(--app:gui)
  local cmd=("$NIM_BIN" c --os:windows --cpu:amd64 -d:mingw --cc:gcc "${COMMON_FLAGS[@]}"
    --gcc.exe:"$MGCC" --gcc.linkerexe:"$MGCC" --gcc.cpp.exe:"$MGXX" --gcc.cpp.linkerexe:"$MGXX"
    --passC:-D_WIN32_WINNT=0x0601 --passC:-DWINVER=0x0601
    --passC:-include --passC:"$tree/.winbuild/winprelude.h"
    --passC:-idirafter --passC:"$MSYS/include"
    --passC:-I"$tree/libs/nimwasmtime/vendor/include"
    --passC:-I"$tree/third_party/msys64/mingw64/include/skia"
    --passC:-I"$tree/third_party/skia-src-m143"
    --nimcache:"$tree/.nimcache-win" "${NIM_PATHS[@]}"
    --passL:-L"$tree/.winbuild/winlib" "${subflag[@]}"
    -o:"$OUT/yantra.exe" render/native/yantra_stage1.nim)
  say "  cd $tree && ${cmd[*]}"
  ( cd "$tree" && "${cmd[@]}" ) || die "windows compile failed"
  want_file "$OUT/yantra.exe"
  say "  exe           : $OUT/yantra.exe  $(stat -c%s "$OUT/yantra.exe") B  sha256 $(sha256sum "$OUT/yantra.exe" | cut -c1-16)"
  say "  defines       : -d:release -d:mingw --os:windows --cpu:amd64 _WIN32_WINNT=0x0601 + winprelude.h"
  say "  toolchain     : $("$MGCC" --version | head -1)"

  step "windows: assemble bundle (exe + DLL closure + apps + launcher)"
  rm -rf "$dest"; mkdir -p "$dest/apps"
  cp -f "$OUT/yantra.exe" "$dest/yantra.exe"
  local n_apps=0 w id
  shopt -s nullglob
  for w in "$tree"/yantra-os/apps/*/app.wasm; do
    id="$(basename "$(dirname "$w")")"
    mkdir -p "$dest/apps/$id"; cp -f "$w" "$dest/apps/$id/app.wasm"; n_apps=$((n_apps+1))
  done
  shopt -u nullglob
  [ -d "$tree/yantra-os/assets" ] && cp -a "$tree/yantra-os/assets" "$dest/" || true
  say "  apps          : $n_apps modules"
  printf '@echo off\r\nrem Yantra — double-click to start the desktop.\r\ncd /d "%%~dp0"\r\nstart "" yantra.exe %%*\r\n' > "$dest/Yantra.bat"

  # yfilament.dll (Filament's MSVC-built shim) imports the Microsoft VC++ 2015-2022 x64
  # runtime. It is not part of Windows, so a bare Windows box can refuse to start the exe.
  # Bundle it app-local (that is the deployment Microsoft documents for the VC++ runtime).
  local msvc_found=0 d
  for d in "$MSVC_RT" /tmp/wt-windows-current-scratch/wine11prefix/drive_c/windows/system32; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    if [ -f "$d/msvcp140.dll" ]; then
      cp -f "$d/msvcp140.dll" "$d/msvcp140_codecvt_ids.dll" "$d/vcruntime140.dll" "$d/vcruntime140_1.dll" "$dest/" 2>/dev/null || true
      msvc_found=1; MSVC_RT="$d"; break
    fi
  done
  say "  msvc runtime  : $( [ "$msvc_found" = 1 ] && echo "bundled from $MSVC_RT" || echo "not found — the exe needs the VC++ 2015-2022 x64 runtime installed" )"

  # PE import closure: every DLL the exe or a bundled DLL needs, except Windows' own.
  local llvm_bin
  llvm_bin="$(dirname "$(ls -d /tmp/wt-windows-current-scratch/llvm-toolchain/*/x86_64-w64-mingw32/bin 2>/dev/null | head -1)")"
  python3 - "$dest/yantra.exe" "$dest" "$MSYS/bin" "$llvm_bin" "$WIN_DLL_DIR" "$dest" <<'PYDEPS' || die "unresolved Windows DLL dependencies (see MISSING lines above)"
import os, shutil, subprocess, sys
exe, dest = sys.argv[1], sys.argv[2]
search = [d for d in sys.argv[3:] if d]
# Windows ships these; do NOT bundle them (a bundled system DLL is a support problem).
SYSTEM = set("""kernel32.dll user32.dll gdi32.dll advapi32.dll shell32.dll ole32.dll oleaut32.dll
msvcrt.dll ntdll.dll dwmapi.dll iphlpapi.dll wlanapi.dll ws2_32.dll ucrtbase.dll comdlg32.dll
comctl32.dll imm32.dll winmm.dll version.dll bcrypt.dll crypt32.dll setupapi.dll shlwapi.dll
dbghelp.dll psapi.dll powrprof.dll opengl32.dll glu32.dll rpcrt4.dll secur32.dll netapi32.dll
userenv.dll d3d11.dll d3d9.dll dxgi.dll gdiplus.dll dwrite.dll usp10.dll msimg32.dll wldap32.dll
wsock32.dll avicap32.dll avrt.dll bcryptprimitives.dll cfgmgr32.dll dnsapi.dll ncrypt.dll
wtsapi32.dll oleacc.dll msacm32.dll""".split())
APISET = ("api-ms-win-", "ext-ms-")
def imports(pe):
    out = subprocess.run(["x86_64-w64-mingw32-objdump","-p",pe],capture_output=True,text=True).stdout
    return [l.split()[-1] for l in out.splitlines() if "DLL Name:" in l]
srcmap, copied, missing, system = {os.path.basename(exe).lower(): exe}, [], [], []
for d in search:
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith(".dll") and f.lower() not in srcmap:
                srcmap[f.lower()] = os.path.join(root, f)
seen, queue = set(), [os.path.basename(exe).lower()]
while queue:
    n = queue.pop()
    if n in seen: continue
    seen.add(n)
    if n in SYSTEM or n.startswith(APISET): system.append(n); continue
    src = srcmap.get(n)
    if not src: missing.append(n); continue
    dst = os.path.join(dest, os.path.basename(src))
    if os.path.abspath(src) != os.path.abspath(dst): shutil.copy2(src, dst)
    copied.append((os.path.basename(dst), os.path.getsize(dst), src))
    queue += [d.lower() for d in imports(src) if d.lower() not in seen]
for name, size, src in sorted(copied): print(f"  DLL  {name:32s} {size:>10d}  {src}")
print(f"  closure: {len(copied)} DLLs bundled, {len(system)} Windows system DLLs, {len(missing)} missing")
for m in sorted(missing): print(f"  MISSING {m}")
sys.exit(1 if missing else 0)
PYDEPS

  local b s
  b="$(stat -c%s "$dest/yantra.exe")"; s="$(sha256sum "$dest/yantra.exe" | awk '{print $1}')"
  {
    echo "target=windows-x64"
    echo "artifact=yantra.exe"
    echo "bytes=$b"
    echo "sha256=$s"
    echo "source_commit=$SRC_COMMIT"
    echo "source_commit_date=$SRC_DATE"
    echo "built_utc=$SRC_DATE"
    echo "defines=-d:release -d:mingw --os:windows --cpu:amd64 -D_WIN32_WINNT=0x0601 (subsystem $WIN_SUBSYSTEM)"
    echo "toolchain=$("$MGCC" --version | head -1) cross-building from Linux, nim $("$NIM_BIN" --version | head -1 | cut -d' ' -f4)"
    echo "apps=$n_apps"
    # Keep three msvcp140-family DLLs? They are NOT here: yfilament.dll needs the Microsoft
    # VC++ 2015-2022 x64 runtime, which Windows apps normally install; Wine provides its own.
    if [ "$msvc_found" = 1 ]; then
      echo "carried=msvcp140.dll=$(sha256sum "$dest/msvcp140.dll" 2>/dev/null | awk '{print $1}')@MS VC++ 2015-2022 x64 runtime, app-local copy taken from $MSVC_RT (Wine's LGPL reimplementation on this box; needed by yfilament.dll)"
      echo "carried=vcruntime140.dll=$(sha256sum "$dest/vcruntime140.dll" 2>/dev/null | awk '{print $1}')@same"
    else
      echo "needs=msvcp140.dll msvcp140_codecvt_ids.dll vcruntime140.dll vcruntime140_1.dll (MS VC++ 2015-2022 x64 runtime, needed by yfilament.dll — NOT bundled)"
    fi
    echo "carried=yfilament.dll=$(sha256sum "$yf" | awk '{print $1}')@Filament Windows build (MSVC; its shim needs MSVC, so it is not cross-built here)"
    echo "carried=wasmtime.dll=$(sha256sum "$WIN_DLL_DIR/wasmtime.dll" | awk '{print $1}')@upstream wasmtime C API release (import lib generated here with dlltool)"
    echo "carried=DLL-set@$(basename "$MSYS") (Skia, FFmpeg, SDL3, ICU, HarfBuzz, Jolt, curl: packaged MSYS2 binaries, not built from source here)"
  } > "$dest/BUILD-INFO.txt"

  step "windows: deterministic zip"
  local zip="$OUT/yantra-windows-x64.zip"
  rm -f "$zip"
  python3 - "$dest" "$zip" <<'PYZIP' || die "zip failed"
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
FIXED = (1980, 1, 1, 0, 0, 0)          # fixed timestamp: the zip must not carry build time
entries = []
for root, dirs, files in os.walk(src):
    dirs.sort()
    for f in sorted(files):
        full = os.path.join(root, f)
        entries.append((os.path.relpath(full, src).replace(os.sep, "/"), full))
entries.sort()
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel, full in entries:
        zi = zipfile.ZipInfo("yantra/" + rel, date_time=FIXED)
        zi.external_attr = (0o755 if rel.lower().endswith((".exe", ".bat")) else 0o644) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(full, "rb") as fh: z.writestr(zi, fh.read())
print(f"  zip entries: {len(entries)}")
PYZIP
  say "  $zip  $(stat -c%s "$zip") B  sha256 $(sha256sum "$zip" | awk '{print $1}')"
  WIN_BYTES="$(stat -c%s "$zip")"; WIN_SHA="$(sha256sum "$zip" | awk '{print $1}')"
}

# ================================================================= 4. run
LINUX_BYTES=""; LINUX_SHA=""; WIN_BYTES=""; WIN_SHA=""
TREE_DIR="$TREE"
if [ -z "$TREE_DIR" ]; then
  # FIXED, not $OUT/build-tree: the tree path is baked into the binary (rpath + C string
  # constants), and measured on this box a rebuild at the same commit gives bit-identical
  # bytes only when the tree sits at the same path. A fixed path is what lets
  # refresh-binaries.sh report SAME instead of CHANGED for an unchanged commit.
  TREE_DIR="${YANTRA_BUILD_TREE:-${TMPDIR:-/tmp}/yantra-build-tree}"
  mkdir -p "$TREE_DIR"
  exec 9>"$TREE_DIR/.lock"
  flock -w 1800 9 || die "another build holds $TREE_DIR/.lock"
  make_tree "$TREE_DIR"
else
  say "using existing tree: $TREE_DIR (its contents are trusted as-is)"
fi

case ",$TARGETS," in *,linux,*)   build_linux   "$TREE_DIR" ;; esac
case ",$TARGETS," in *,windows,*) build_windows "$TREE_DIR" ;; esac

[ "$KEEP_TREE" -eq 1 ] || { [ -n "$TREE" ] || rm -rf "$TREE_DIR"; }

step "bundles + checksums"
cd "$OUT"
: > SHA256SUMS
[ -n "$LINUX_SHA" ] && printf '%s  %s\n' "$LINUX_SHA" yantra-linux-x64.tar.gz >> SHA256SUMS
[ -n "$WIN_SHA" ]   && printf '%s  %s\n' "$WIN_SHA"   yantra-windows-x64.zip  >> SHA256SUMS
{
  echo "# yantra desktop binaries — provenance"
  echo "source_commit=$SRC_COMMIT"
  echo "source_commit_date=$SRC_DATE"
  echo "head_commit=$SRC_HEAD"
  echo "dirty=$DIRTY"
  echo "build_command=bash yantra-os/tools/build-binaries.sh --out <dir>   (or: bash yantra-os/tools/refresh-binaries.sh)"
  echo "linux_bytes=$LINUX_BYTES"
  echo "linux_sha256=$LINUX_SHA"
  echo "windows_bytes=$WIN_BYTES"
  echo "windows_sha256=$WIN_SHA"
} > BUILD-INFO.txt
cat SHA256SUMS
say "BUILD-INFO.txt:"
sed 's/^/  /' BUILD-INFO.txt
step "done"
say "linux  : $OUT/yantra-linux-x64.tar.gz   ${LINUX_BYTES:-—} B  ${LINUX_SHA:-—}"
say "windows: $OUT/yantra-windows-x64.zip    ${WIN_BYTES:-—} B  ${WIN_SHA:-—}"
