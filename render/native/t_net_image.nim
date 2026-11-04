## Network images (C1): `image "https://…"` (or `http://127.0.0.1…` when listed in `net`):
## checked against `netAllowed(windowNet, url)`, downloaded once by the engine's `Fetcher`
## (`pumpNet`) into `dataDir()/<appName>/.cache/<sha1 of url>`, draws nothing until it
## arrives, then relayouts to the decoded image's dimensions and paints.
import std/[os, net, times, tables, strutils, sha1, atomics]
import engine
import ../../host/host
import nimskia

var passed, failed = 0
proc check(name: string; ok: bool; detail = "") =
  if ok: inc passed; echo "  ok  ", name
  else: inc failed; echo "  FAIL ", name, "  ", detail

let here = currentSourcePath().parentDir
let buildDir = here / "build"
createDir(buildDir)

let srcPng = buildDir / "net_badge.png"
check("generate 48x24 green PNG for server", writePng(srcPng, 48, 24, 0xFF00FF00'u32))
let pngBytes = readFile(srcPng)

var servedCount: Atomic[int]
servedCount.store(0)

proc serveImages(port: int) {.thread.} =
  {.gcsafe.}:
    let pngData = readFile(currentSourcePath().parentDir / "build" / "net_badge.png")
    let s = newSocket()
    s.setSockOpt(OptReuseAddr, true)
    s.bindAddr(Port(port), "127.0.0.1")
    s.listen()
    while true:
      var c: Socket
      try:
        s.accept(c)
        var line = ""
        c.readLine(line, timeout = 2000)
        while true:
          var h = ""
          c.readLine(h, timeout = 2000)
          if h.len == 0 or h == "\r\n" or h == "\c": break
        if "/badge.png" in line:
          discard servedCount.fetchAdd(1)
          c.send("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: " &
                 $pngData.len & "\r\nConnection: close\r\n\r\n" & pngData)
        else:
          c.send("HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\nConnection: close\r\n\r\nnope")
        c.close()
      except CatchableError as e:
        if e.msg.len < 0: echo e.msg

var th: Thread[int]
createThread(th, serveImages, 18439)
sleep(150)

let url = "http://127.0.0.1:18439/badge.png"
let expectedSha = ($secureHash(url)).toLowerAscii
let expectedCache = dataDir() / "net_img_app" / ".cache" / expectedSha

check("netAssetCachePath resolves to dataDir()/<appName>/.cache/<sha1>", netAssetCachePath("net_img_app", url) == expectedCache, netAssetCachePath("net_img_app", url))
check("netAssetCachePath rejects path traversal appName", netAssetCachePath("../outside", url) == "" and netAssetCachePath("net_img_app", "") == "")

let wasmPath = buildDir / "net_img_app.wasm"
let eng = start(wasmPath, 120, 100)

check("unlisted network image host is refused by resolveAsset", eng.resolveAsset("https://unlisted.example.com/secret.png") == "")
check("before pumpNet, allowed network image is not on disk yet", not fileExists(expectedCache))

var px = newSeq[uint32](120 * 100)
eng.paintFrame(addr px[0], 120, 100)
check("before arrival, image node draws nothing (background pixel intact)", px[10 * 120 + 10] == 0xFF0B0B10'u32, $px[10 * 120 + 10].toHex)
check("before arrival, engine has 1 network image download pending", eng.netPending == 1, $eng.netPending)

var clock = 0.0
let t0 = epochTime()
while epochTime() - t0 < 10:
  clock += 16
  eng.tick(clock)
  if eng.netPending == 0: break
  sleep(10)

check("download finished and cached under dataDir()/<appName>/.cache/<sha1>", eng.netPending == 0 and fileExists(expectedCache))
check("resolveAsset now returns the cached file path", eng.resolveAsset(url) == expectedCache)

eng.paintFrame(addr px[0], 120, 100)

var laidOut48x24 = false
for id, b in eng.boxes:
  if id > 0 and b.w == 48 and b.h == 24:
    laidOut48x24 = true
    let cx = int(b.x + b.w / 2)
    let cy = int(b.y + b.h / 2)
    check("after arrival, image node paints decoded green pixels", px[cy * 120 + cx] == 0xFF00FF00'u32, $px[cy * 120 + cx].toHex)
check("after arrival, engine relayouts image node to decoded 48x24 size", laidOut48x24)

eng.tick(clock + 16)
eng.paintFrame(addr px[0], 120, 100)
check("network image is downloaded only once (cached on subsequent frames)", servedCount.load() == 1, "servedCount=" & $servedCount.load())

removeFile(srcPng)
echo "net_image: ", passed, " passed, ", failed, " failed"
if failed > 0: quit(1)
