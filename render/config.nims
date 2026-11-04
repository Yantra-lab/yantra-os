# Build config for the Qt render shell.
#
# WHY THIS IS CONDITIONAL: Nim loads config.nims for EVERY project file in a
# directory. Unconditionally forcing the g++ / Qt configuration would also apply
# it to the pure modules here (qmlgen, t_qml), which must build with the plain C
# backend — feeding the Nim runtime's C output to g++ fails with
# "redefinition of TNimTypeV2". So Qt configuration applies ONLY to the shell.
#
# Paths are DERIVED from nimqt's location. Nothing is machine-specific: the
# archived packages all shipped absolute dev-machine paths and broke the moment
# they moved.

import std/[os, strutils]

# ---------------------------------------------------------------------------
# PATH hygiene — runs for EVERY project in this directory, Qt-backed or not.
#
# A Qt RUNTIME bin directory (one holding Qt6Core.dll but no compiler) also
# contains libstdc++-6.dll and libgcc_s_seh-1.dll built for the GCC that Qt
# itself was compiled with (13.x). If such a directory precedes the compilers,
# a newer GCC (16.2.0 here) loads THAT runtime and dies with `exit code: 1` and
# NO diagnostics at all — gcc and g++ alike, on both backends. It looks exactly
# like a source error, and is not.
#
# Interactive shells accumulate precisely these entries: any
# `export PATH=.../Qt/6.8.3/mingw_64/bin:$PATH` done to run a Qt binary leaves
# it behind, after which a plain `nim c t_qml.nim` that worked a minute ago
# fails. Verified live — that is how this was found. Dropping them here means a
# build never depends on how the caller's shell happens to be configured.
#
# This also converts PATH to Windows form. MSYS bash exports it ':'-separated
# with /c/ prefixes, but Windows splits on ';', so every entry after the first
# would be unreadable to a spawned process.
proc yantraSanitizePath() =
  var keep: seq[string]
  for d in getEnv("PATH").split({':', ';'}):
    if d.len == 0: continue
    var x = d
    if x.len > 2 and x[0] == '/' and x[2] == '/':
      x = x[1].toUpperAscii & ':' & x[2 .. ^1]    # /c/Users -> C:/Users
    x = x.replace('\\', '/')
    let isQtRuntime = fileExists(x / "Qt6Core.dll") and not fileExists(x / "g++.exe")
    if not isQtRuntime:
      keep.add x
  if keep.len > 0:
    putEnv("PATH", keep.join(";"))

yantraSanitizePath()

# Binaries in this directory that need the Qt configuration. Everything else
# (qmlgen, t_qml) is a pure module and must build with the plain C backend —
# feeding the Nim runtime's C output to g++ fails with "redefinition of
# TNimTypeV2". An explicit list beats a single-name check: adding a Qt-backed
# binary is then a one-line, obvious change rather than a silent misbuild.
const qtBinaries = ["render_qml", "t3d_smoke", "spin3d", "test_load3"]

if projectName() notin qtBinaries:
  # Pure module or test: leave the default C backend alone.
  echo "config.nims: '", projectName(), "' is not Qt-backed - Qt config skipped"
else:
  let here = currentSourcePath().parentDir          # .../yantra/render
  let nimDir = here.parentDir                       # .../yantra (repo root)
  let nimqtDir = nimDir / "libs" / "nimqt"

  # --- Nim search paths ------------------------------------------------------
  switch("path", here)                              # qmlgen
  switch("path", nimDir / "host")                   # host, tree
  switch("path", nimqtDir / "src")
  switch("path", nimDir / "libs" / "nimwasmtime" / "src")

  # --- Qt toolchain: portable MSYS2 mingw64 bundled with nimqt ---------------
  # Override with QT_TOOLCHAIN=<root> (bin/g++.exe, include/qt6, lib).
  let tcEnv = getEnv("QT_TOOLCHAIN")
  let toolchain = if tcEnv.len > 0: tcEnv
                  else: nimDir / "third_party" / "msys64" / "mingw64"
  let toolchainBin = toolchain / "bin"

  if not dirExists(toolchain):
    echo "WARNING: Qt toolchain not found at ", toolchain
    echo "         set QT_TOOLCHAIN to a Qt6 root (bin/g++.exe, include/qt6, lib)"

  # The toolchain bin is needed on PATH so the compiler's driver subprocesses
  # (cc1plus, as, ld) can find their DLLs. PATH is already sanitised and in
  # Windows form by yantraSanitizePath() at the top of this file; a Qt-only bin
  # is deliberately never added — see the note there.
  #
  # A Windows-native temp dir is also required: an MSYS-style TMP makes the
  # compiler driver fail with "Cannot create temporary file in C:\WINDOWS\".
  proc toWinPath(p: string): string =
    ## MSYS bash exports PATH ':'-separated with /c/ drive prefixes. That string
    ## goes into the process environment verbatim, but Windows splits PATH on
    ## ';' — so every entry after the first is unreadable and spawned tools
    ## (cc1plus) fail to load their DLLs. Symptom: the compiler exits 1 having
    ## printed nothing, while the identical command works when run from bash
    ## (bash translates the PATH for its children; a process environment cannot).
    if ';' in p:
      return p                                   # already Windows form
    var parts: seq[string]
    for e in p.split(':'):
      if e.len == 0: continue
      var x = e
      if x.len > 2 and x[0] == '/' and x[2] == '/':
        x = x[1].toUpperAscii & ':' & x[2 .. ^1]  # /c/Users -> C:/Users
      parts.add x.replace('\\', '/')
    parts.join(";")

  # Only add a toolchain bin dir to PATH when it actually contains the compiler.
  #
  # Prepending a Qt-only bin is ACTIVELY HARMFUL: Qt ships its own
  # libstdc++-6.dll / libgcc_s_seh-1.dll (built for the GCC Qt was compiled
  # with — 13.x), and a g++ from a newer GCC (16.2.0 here) will load THAT
  # runtime instead of its own. The mismatch kills the driver with exit 1 and NO
  # diagnostics, while the byte-identical command succeeds when run from bash
  # (where Qt's bin is absent from PATH). Qt's bin is still needed at RUNTIME,
  # which is the harness's job, not the build's.
  if fileExists(toolchainBin / "g++.exe"):
    putEnv("PATH", (toolchainBin.replace('\\', '/')) & ";" & toWinPath(getEnv("PATH")))
  let localApp = getEnv("LOCALAPPDATA")
  if localApp.len > 0:
    let t = localApp & r"\Temp"
    putEnv("TMP", t)
    putEnv("TEMP", t)

  switch("cc", "gcc")                               # C++ backend
  # A toolchain root may or may not ship a compiler. The msys2 bundle includes
  # g++.exe; an online-installer Qt root does not. Only override the compiler
  # when one is actually present, otherwise keep whatever Nim would use.
  if fileExists(toolchainBin / "g++.exe"):
    # Forward slashes: see the qtInclude note below — backslash paths in a
    # spawned process's argv get mangled on this host.
    let gpp = (toolchainBin / "g++.exe").replace('\\', '/')
    switch("gcc.exe", gpp)
    switch("gcc.linkerexe", gpp)
  else:
    echo "config.nims: no g++ in ", toolchainBin, " - using the default compiler"

  # Qt 6 requires C++17. -fpermissive is required because Nim's winlean
  # GetProcAddress shim converts FARPROC to void*.
  switch("passc", "-std=c++17")
  switch("passc", "-fpermissive")
  switch("passc", "-DUNICODE")
  switch("passc", "-D_UNICODE")

  # Public Qt headers. Two layouts exist in the wild:
  #   online-installer : <root>/include/QtCore, <root>/include/QtQuick3D
  #   msys2/distro     : <root>/include/qt6/QtCore
  # Detect rather than assume.
  var qtInclude = toolchain / "include" / "qt6"
  if not dirExists(qtInclude): qtInclude = toolchain / "include"
  # FORWARD SLASHES ARE REQUIRED, not cosmetic. Nim spawns g++ as a native
  # process, and a backslash path in that argv arrives mangled: -IC:\Qt\6.8.3\
  # mingw_64\include\QtCore is seen by g++ as -IC:Qt6.8.3mingw_64includeQtCore,
  # so every Qt header reports "No such file or directory" even though it exists
  # (verified by compiling shim.cpp both ways). Forward slashes also keep the
  # config portable to Linux/macOS.
  qtInclude = qtInclude.replace('\\', '/')
  switch("passc", "-I" & qtInclude)

  # Qt's own version (e.g. "6.11.2"), read from the headers so nothing is
  # hardcoded. Private headers live at <qt6>/<Mod>/<ver>/<Mod>/private/, so both
  # <mod>/<ver> and <mod>/<ver>/<mod> must be on the include path.
  # NOTE: readFile, not lines(). A file iterator drags in syncio, which cannot
  # be importc'd during compile-time config evaluation.
  proc qtVersion(qtInc: string): string =
    let h = qtInc / "QtCore" / "qtcoreversion.h"
    if fileExists(h):
      let txt = readFile(h)
      let key = txt.find("QTCORE_VERSION_STR")
      if key >= 0:
        let a = txt.find('"', key)
        if a >= 0:
          let b = txt.find('"', a + 1)
          if b > a: return txt[a + 1 ..< b]
    ""

  let ver = qtVersion(qtInclude)

  # Modules to compile against. QtQuick3D is optional: it is not in every Qt
  # install (the msys2 bundle has only Core/Gui/Qml/Quick), so it is included
  # only when the headers are actually present. That keeps the 2D pipeline
  # working on a trimmed Qt while enabling 3D where the module exists.
  var mods = @["QtCore", "QtGui", "QtQml", "QtQuick"]
  let has3d = dirExists(qtInclude / "QtQuick3D")
  if has3d: mods.add "QtQuick3D"

  for mod_name in mods:
    switch("passc", "-I" & (qtInclude / mod_name).replace('\\', '/'))
    # Explicit, derived version roots. A walkDir loop also finds these, but Nim
    # merges switches from every config.nims on the search path and the
    # duplicate was observed to be dropped in favour of a RELATIVE path emitted
    # by nimqt's own config — which then resolves against the caller's cwd and
    # fails on QtCore/private/qglobal_p.h. Naming the version explicitly makes
    # the include path correct regardless of cwd or config ordering.
    if ver.len > 0:
      switch("passc", "-I" & (qtInclude / mod_name / ver).replace('\\', '/'))
      switch("passc", "-I" & (qtInclude / mod_name / ver / mod_name).replace('\\', '/'))
    # Fallback for an unusual layout with no version header.
    let base = qtInclude / mod_name
    if ver.len == 0 and dirExists(base):
      for kind in walkDir(base):
        if kind.kind == pcDir:
          let v = kind.path.lastPathPart
          switch("passc", "-I" & (base / v / mod_name).replace('\\', '/'))
          switch("passc", "-I" & (base / v).replace('\\', '/'))

  # Libraries.
  let qtLib = (toolchain / "lib").replace('\\', '/')
  switch("passl", "-L" & qtLib)
  for lib in ["Qt6Core", "Qt6Gui", "Qt6Qml", "Qt6Quick"]:
    switch("passl", "-l" & lib)
  if has3d:
    # QtQuick3D pulls in the 3D render/asset core. MinGW import libs do not
    # chase transitive deps, so the implementation libs are listed explicitly —
    # but only when they exist, since Qt installs differ in which ones ship and
    # -l for a missing library is a hard link error.
    switch("passc", "-DYANTRA_HAS_3D")
    for lib in ["Qt6Quick3D", "Qt63DRender", "Qt63DQuickRender",
                "Qt6Quick3DUtils", "Qt6Quick3DAssetUtils", "Qt6ShaderTools"]:
      if fileExists(qtLib / ("lib" & lib & ".a")) or
         fileExists(qtLib / ("lib" & lib & ".dll.a")):
        switch("passl", "-l" & lib)
