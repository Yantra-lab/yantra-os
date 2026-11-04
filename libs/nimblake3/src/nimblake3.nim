## nimblake3 — official C BLAKE3 wrapper + content-addressed asset store (architecture §12).

import std/[os, times]
import ../../nimsqlite/src/nimsqlite

const
  shimDir = currentSourcePath().parentDir
  msysDir = shimDir / ".." / ".." / ".." / "third_party" / "msys64" / "mingw64"
  blake3Inc = msysDir / "include"
  blake3Lib = msysDir / "lib" / "libblake3.dll.a"

{.passC: "-I\"" & blake3Inc & "\"".}
{.passL: "\"" & blake3Lib & "\"".}

type
  blake3_chunk_state {.bycopy.} = object
    cv: array[8, uint32]
    chunk_counter: uint64
    buf: array[64, uint8]
    buf_len: uint8
    blocks_compressed: uint8
    flags: uint8

  blake3_hasher {.bycopy.} = object
    key: array[8, uint32]
    chunk: blake3_chunk_state
    cv_stack_len: uint8
    cv_stack: array[(54 + 1) * 32, uint8]

  Blake3Hasher* = object
    h: blake3_hasher

  AssetInfo* = object
    hash*: string
    size*: int
    mimeType*: string
    createdAt*: int64

  AssetStore* = ref object
    db: SqliteDb
    storeDir: string

proc c_blake3_version(): cstring {.importc: "blake3_version", cdecl.}
proc c_blake3_hasher_init(self: ptr blake3_hasher) {.importc: "blake3_hasher_init", cdecl.}
proc c_blake3_hasher_init_keyed(self: ptr blake3_hasher; key: ptr uint8) {.importc: "blake3_hasher_init_keyed", cdecl.}
proc c_blake3_hasher_update(self: ptr blake3_hasher; input: pointer; input_len: csize_t) {.importc: "blake3_hasher_update", cdecl.}
proc c_blake3_hasher_finalize(self: ptr blake3_hasher; `out`: ptr uint8; out_len: csize_t) {.importc: "blake3_hasher_finalize", cdecl.}

const HexChars = "0123456789abcdef"
proc bytesToHex(b: openArray[byte]): string =
  result = newString(b.len * 2)
  for i, val in b:
    result[i * 2] = HexChars[int(val shr 4)]
    result[i * 2 + 1] = HexChars[int(val and 0x0F)]

proc blake3Version*(): string = $c_blake3_version()

proc initHasher*(): Blake3Hasher =
  c_blake3_hasher_init(addr result.h)

proc update*(h: var Blake3Hasher; data: openArray[byte]) =
  if data.len > 0:
    c_blake3_hasher_update(addr h.h, unsafeAddr data[0], csize_t(data.len))

proc update*(h: var Blake3Hasher; text: string) =
  if text.len > 0:
    c_blake3_hasher_update(addr h.h, cast[pointer](text.cstring), csize_t(text.len))

proc finalizeHex*(h: Blake3Hasher): string =
  var copy = h.h
  var outBytes: array[32, byte]
  c_blake3_hasher_finalize(addr copy, cast[ptr uint8](addr outBytes[0]), 32)
  bytesToHex(outBytes)

proc blake3Hash*(data: openArray[byte]): string =
  var h = initHasher()
  h.update(data)
  h.finalizeHex()

proc blake3Hash*(text: string): string =
  var h = initHasher()
  h.update(text)
  h.finalizeHex()

proc blake3KeyedHash*(key: array[32, byte]; data: openArray[byte]): string =
  var h: Blake3Hasher
  c_blake3_hasher_init_keyed(addr h.h, cast[ptr uint8](unsafeAddr key[0]))
  if data.len > 0:
    c_blake3_hasher_update(addr h.h, unsafeAddr data[0], csize_t(data.len))
  h.finalizeHex()

proc openAssetStore*(dirPath: string): AssetStore =
  createDir(dirPath / "blobs")
  let dbPath = dirPath / "assets.db"
  let db = openDb(dbPath)
  db.exec("CREATE TABLE IF NOT EXISTS assets (hash TEXT PRIMARY KEY, size INTEGER NOT NULL, mime_type TEXT NOT NULL, created_at INTEGER NOT NULL);")
  AssetStore(db: db, storeDir: dirPath)

proc close*(store: AssetStore) =
  if store != nil and store.db != nil:
    store.db.close()
    store.db = nil

proc putBlob*(store: AssetStore; bytes: string; mimeType: string = "application/octet-stream"): string =
  let h = blake3Hash(bytes)
  let blobPath = store.storeDir / "blobs" / h
  if not fileExists(blobPath):
    writeFile(blobPath, bytes)
  let now = getTime().toUnix()
  let stmt = store.db.prepare("INSERT OR REPLACE INTO assets (hash, size, mime_type, created_at) VALUES (?, ?, ?, ?);")
  stmt.bindText(1, h)
  stmt.bindInt(2, int64(bytes.len))
  stmt.bindText(3, mimeType)
  stmt.bindInt(4, now)
  discard stmt.step()
  stmt.finalize()
  h

proc hasBlob*(store: AssetStore; hash: string): bool =
  let stmt = store.db.prepare("SELECT 1 FROM assets WHERE hash = ? LIMIT 1;")
  stmt.bindText(1, hash)
  result = stmt.step()
  stmt.finalize()

proc getBlob*(store: AssetStore; hash: string): string =
  let blobPath = store.storeDir / "blobs" / hash
  if fileExists(blobPath): readFile(blobPath) else: ""

proc blobSize*(store: AssetStore; hash: string): int =
  let stmt = store.db.prepare("SELECT size FROM assets WHERE hash = ? LIMIT 1;")
  stmt.bindText(1, hash)
  if stmt.step():
    result = int(stmt.columnInt(0))
  stmt.finalize()

proc blobInfo*(store: AssetStore; hash: string): AssetInfo =
  let stmt = store.db.prepare("SELECT hash, size, mime_type, created_at FROM assets WHERE hash = ? LIMIT 1;")
  stmt.bindText(1, hash)
  if stmt.step():
    result = AssetInfo(
      hash: stmt.columnText(0),
      size: int(stmt.columnInt(1)),
      mimeType: stmt.columnText(2),
      createdAt: stmt.columnInt(3)
    )
  stmt.finalize()
