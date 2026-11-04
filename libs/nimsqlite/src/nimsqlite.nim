import std/[os, strutils]

const currentDir = currentSourcePath().parentDir().replace('\\', '/')
{.passC: "-I" & currentDir & "/../../../third_party/msys64/mingw64/include".}
{.passL: "-L" & currentDir & "/../../../third_party/msys64/mingw64/lib -lsqlite3".}

const
  SQLITE_ROW = 100
  SQLITE_DONE = 101
  SQLITE_TRANSIENT = cast[pointer](-1)

type
  SqliteError* = object of CatchableError

  SqliteDbObj = object
    raw: pointer
  SqliteDb* = ref SqliteDbObj

  SqliteStmtObj = object
    raw: pointer
    db: SqliteDb
  SqliteStmt* = ref SqliteStmtObj

proc sqlite3_open(filename: cstring, ppDb: ptr pointer): cint {.importc, cdecl.}
proc sqlite3_close(db: pointer): cint {.importc, cdecl.}
proc sqlite3_errmsg(db: pointer): cstring {.importc, cdecl.}
proc sqlite3_exec(db: pointer, sql: cstring, callback: pointer, arg: pointer, errmsg: ptr cstring): cint {.importc, cdecl.}
proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr pointer, pzTail: ptr cstring): cint {.importc, cdecl.}
proc sqlite3_step(stmt: pointer): cint {.importc, cdecl.}
proc sqlite3_reset(stmt: pointer): cint {.importc, cdecl.}
proc sqlite3_finalize(stmt: pointer): cint {.importc, cdecl.}
proc sqlite3_bind_int64(stmt: pointer, col: cint, val: int64): cint {.importc, cdecl.}
proc sqlite3_bind_double(stmt: pointer, col: cint, val: cdouble): cint {.importc, cdecl.}
proc sqlite3_bind_text(stmt: pointer, col: cint, val: cstring, n: cint, destructor: pointer): cint {.importc, cdecl.}
proc sqlite3_bind_blob(stmt: pointer, col: cint, val: pointer, n: cint, destructor: pointer): cint {.importc, cdecl.}
proc sqlite3_column_int64(stmt: pointer, iCol: cint): int64 {.importc, cdecl.}
proc sqlite3_column_double(stmt: pointer, iCol: cint): cdouble {.importc, cdecl.}
proc sqlite3_column_text(stmt: pointer, iCol: cint): cstring {.importc, cdecl.}
proc sqlite3_column_blob(stmt: pointer, iCol: cint): pointer {.importc, cdecl.}
proc sqlite3_column_bytes(stmt: pointer, iCol: cint): cint {.importc, cdecl.}
proc sqlite3_last_insert_rowid(db: pointer): int64 {.importc, cdecl.}
proc sqlite3_changes(db: pointer): cint {.importc, cdecl.}

proc openDb*(path: string): SqliteDb =
  new result
  let rc = sqlite3_open(path.cstring, addr result.raw)
  if rc != 0:
    let msg = if result.raw != nil: $sqlite3_errmsg(result.raw) else: "failed to open database"
    if result.raw != nil:
      discard sqlite3_close(result.raw)
      result.raw = nil
    raise newException(SqliteError, msg)

proc close*(db: SqliteDb) =
  if db != nil and db.raw != nil:
    discard sqlite3_close(db.raw)
    db.raw = nil

proc exec*(db: SqliteDb; sql: string) =
  var errmsg: cstring = nil
  let rc = sqlite3_exec(db.raw, sql.cstring, nil, nil, addr errmsg)
  if rc != 0:
    let msg = if errmsg != nil: $errmsg else: $sqlite3_errmsg(db.raw)
    raise newException(SqliteError, msg)

proc prepare*(db: SqliteDb; sql: string): SqliteStmt =
  var rawStmt: pointer = nil
  let rc = sqlite3_prepare_v2(db.raw, sql.cstring, sql.len.cint, addr rawStmt, nil)
  if rc != 0 or rawStmt == nil:
    let msg = if db.raw != nil: $sqlite3_errmsg(db.raw) else: "prepare failed: " & $rc
    raise newException(SqliteError, msg)
  new result
  result.raw = rawStmt
  result.db = db

proc step*(stmt: SqliteStmt): bool =
  let rc = sqlite3_step(stmt.raw)
  if rc == SQLITE_ROW: return true
  if rc == SQLITE_DONE: return false
  let msg = if stmt.db != nil and stmt.db.raw != nil: $sqlite3_errmsg(stmt.db.raw) else: "step failed: " & $rc
  raise newException(SqliteError, msg)

proc reset*(stmt: SqliteStmt) =
  if stmt != nil and stmt.raw != nil:
    discard sqlite3_reset(stmt.raw)

proc finalize*(stmt: SqliteStmt) =
  if stmt != nil and stmt.raw != nil:
    discard sqlite3_finalize(stmt.raw)
    stmt.raw = nil

proc bindInt*(stmt: SqliteStmt; col: int; val: int64) =
  let rc = sqlite3_bind_int64(stmt.raw, col.cint, val)
  if rc != 0: raise newException(SqliteError, "bindInt failed: " & $rc)

proc bindFloat*(stmt: SqliteStmt; col: int; val: float64) =
  let rc = sqlite3_bind_double(stmt.raw, col.cint, val.cdouble)
  if rc != 0: raise newException(SqliteError, "bindFloat failed: " & $rc)

proc bindText*(stmt: SqliteStmt; col: int; val: string) =
  let rc = sqlite3_bind_text(stmt.raw, col.cint, val.cstring, val.len.cint, SQLITE_TRANSIENT)
  if rc != 0: raise newException(SqliteError, "bindText failed: " & $rc)

proc bindBlob*(stmt: SqliteStmt; col: int; val: string) =
  let p = if val.len > 0: unsafeAddr val[0] else: nil
  let rc = sqlite3_bind_blob(stmt.raw, col.cint, p, val.len.cint, SQLITE_TRANSIENT)
  if rc != 0: raise newException(SqliteError, "bindBlob failed: " & $rc)

proc columnInt*(stmt: SqliteStmt; col: int): int64 =
  sqlite3_column_int64(stmt.raw, col.cint)

proc columnFloat*(stmt: SqliteStmt; col: int): float64 =
  sqlite3_column_double(stmt.raw, col.cint).float64

proc columnText*(stmt: SqliteStmt; col: int): string =
  let p = sqlite3_column_text(stmt.raw, col.cint)
  if p == nil: "" else: $p

proc columnBlob*(stmt: SqliteStmt; col: int): string =
  let p = sqlite3_column_blob(stmt.raw, col.cint)
  let n = sqlite3_column_bytes(stmt.raw, col.cint)
  if p == nil or n <= 0: return ""
  result = newString(n)
  copyMem(addr result[0], p, n)

proc lastInsertRowId*(db: SqliteDb): int64 =
  sqlite3_last_insert_rowid(db.raw)

proc changes*(db: SqliteDb): int =
  sqlite3_changes(db.raw).int

proc beginTransaction*(db: SqliteDb) = db.exec("BEGIN")
proc commit*(db: SqliteDb) = db.exec("COMMIT")
proc rollback*(db: SqliteDb) = db.exec("ROLLBACK")

template withTransaction*(db: SqliteDb; body: untyped) =
  db.beginTransaction()
  var committed = false
  try:
    body
    db.commit()
    committed = true
  finally:
    if not committed:
      db.rollback()
