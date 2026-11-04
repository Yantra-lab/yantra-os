## qg: build one Sutra app out of the Atlas and write its wasm.
##
##   YANTRA_DB="host=/var/run/postgresql port=5432 dbname=yantra user=ubuntu" \
##   nim r --hints:off yantra-os/apps/arcade/qg_build.nim arcade.Arcade ink.Ink ...
##
## Each argument is `<app>.<RootCell>`; the source is read from
## `yantra-os/apps/<app>/app.nim`, split into cells, put in its own space
## `@qg-<app>` (so a rebuild never collides with another lane), built, and
## written to `yantra-os/apps/<app>/app.wasm`. Prints bytes, sha256 and time.
import std/[os, osproc, strutils, sha1]
import ../../../host/atlas/[atlas, build, importer]

proc sh(cmd: string): string =
  let (o, c) = execCmdEx(cmd)
  if c != 0: raise newException(IOError, "failed: " & cmd & "\n" & o)
  o.strip

let repo = currentSourcePath().parentDir.parentDir.parentDir.parentDir
if paramCount() == 0: quit "usage: qg_build <app>.<Root> [...]", 2

var a = atlas.open(getEnv("YANTRA_DB"))
a.install()

for i in 1 .. paramCount():
  let target = paramStr(i)
  let app = target.split('.')[0]
  let src = repo / "yantra-os" / "apps" / app / "app.nim"
  let dst = repo / "yantra-os" / "apps" / app / "app.wasm"
  let space = a.space("@qg-" & app)
  discard a.clearSpace("@qg-" & app)
  var n = 0
  for (name, source) in splitCells(readFile(src)):
    discard a.put(space, app & "." & name, source, author = "qg")
    inc n
  let built = a.build(space, target, "wasm")
  if not built.ok:
    echo "BUILD FAILED ", target, "\n", built.log
    quit 1
  writeFile(dst, built.wasm)
  let sha = sh("sha256sum " & quoteShell(dst) & " | cut -c1-64")
  echo target, " cells=", n, " bytes=", getFileSize(dst),
       " sha256=", sha, " cached=", built.cached, " ms=", built.ms
