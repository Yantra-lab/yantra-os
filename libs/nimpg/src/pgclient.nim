## A small Postgres client over libpq, for tools that talk to the Yantra
## database from outside it (the Atlas worker, tests).

when defined(windows):
  const libpq = "libpq.dll"
else:
  const libpq = "libpq.so(|.5)"

type
  PGconn = pointer
  PGresult = pointer
  ExecStatus = cint

const
  CONNECTION_OK = 0
  PGRES_COMMAND_OK = 1
  PGRES_TUPLES_OK = 2

proc PQconnectdb(info: cstring): PGconn {.importc, dynlib: libpq.}
proc PQstatus(c: PGconn): cint {.importc, dynlib: libpq.}
proc PQerrorMessage(c: PGconn): cstring {.importc, dynlib: libpq.}
proc PQfinish(c: PGconn) {.importc, dynlib: libpq.}
proc PQexecParams(c: PGconn, command: cstring, nParams: cint, paramTypes: pointer,
                  paramValues: ptr UncheckedArray[cstring], paramLengths: pointer,
                  paramFormats: pointer, resultFormat: cint): PGresult {.importc, dynlib: libpq.}
proc PQresultStatus(r: PGresult): ExecStatus {.importc, dynlib: libpq.}
proc PQresultErrorMessage(r: PGresult): cstring {.importc, dynlib: libpq.}
proc PQntuples(r: PGresult): cint {.importc, dynlib: libpq.}
proc PQnfields(r: PGresult): cint {.importc, dynlib: libpq.}
proc PQgetvalue(r: PGresult, row, col: cint): cstring {.importc, dynlib: libpq.}
proc PQgetisnull(r: PGresult, row, col: cint): cint {.importc, dynlib: libpq.}
proc PQclear(r: PGresult) {.importc, dynlib: libpq.}

type PGnotify {.bycopy.} = object
  relname: cstring
  bePid: cint
  extra: cstring
  next: pointer
proc PQconsumeInput(c: PGconn): cint {.importc, dynlib: libpq.}
proc PQnotifies(c: PGconn): ptr PGnotify {.importc, dynlib: libpq.}
proc PQfreemem(p: pointer) {.importc, dynlib: libpq.}

type
  Db* = object
    conn: PGconn
  DbError* = object of CatchableError
  Row* = seq[string] ## NULL comes back as ""; use `query` when that matters

proc `=destroy`(d: Db) =
  if d.conn != nil: PQfinish(d.conn)
proc `=copy`(a: var Db, b: Db) {.error.}

proc connect*(info: string): Db =
  ## `info` is a libpq connection string, e.g. "host=localhost port=5433 dbname=yantra".
  result = Db(conn: PQconnectdb(info.cstring))
  if PQstatus(result.conn) != CONNECTION_OK:
    raise newException(DbError, $PQerrorMessage(result.conn))

const SqlNull* = "\0"
  ## SQL NULL, as a parameter and in `rowsWithNull`: no Postgres text value
  ## can be it (text cannot hold a NUL byte).

proc run(d: Db, sql: string, args: openArray[string]): PGresult =
  var vals = newSeq[cstring](args.len)
  for i, a in args: vals[i] = (if a == SqlNull: nil else: a.cstring)
  let p = if vals.len > 0: cast[ptr UncheckedArray[cstring]](addr vals[0]) else: nil
  result = PQexecParams(d.conn, sql.cstring, cint(args.len), nil, p, nil, nil, 0)
  let st = PQresultStatus(result)
  if st != PGRES_COMMAND_OK and st != PGRES_TUPLES_OK:
    let msg = $PQresultErrorMessage(result)
    PQclear(result)
    raise newException(DbError, msg)

proc exec*(d: Db, sql: string, args: varargs[string]) =
  ## Runs a statement; `$1`, `$2` ... are bound to `args` (never spliced).
  PQclear(d.run(sql, args))

proc rows*(d: Db, sql: string, args: varargs[string]): seq[Row] =
  let r = d.run(sql, args)
  for i in 0 ..< PQntuples(r):
    var row: Row
    for j in 0 ..< PQnfields(r): row.add $PQgetvalue(r, i, j)
    result.add row
  PQclear(r)

proc rowsWithNull*(d: Db, sql: string, args: openArray[string]): seq[Row] =
  ## As `rows`, but a NULL field is `SqlNull`, never "".
  let r = d.run(sql, args)
  for i in 0 ..< PQntuples(r):
    var row: Row
    for j in 0 ..< PQnfields(r):
      row.add(if PQgetisnull(r, i, j) != 0: SqlNull else: $PQgetvalue(r, i, j))
    result.add row
  PQclear(r)

proc listen*(d: Db, channel: string) =
  ## Subscribes this connection to `channel` (Postgres LISTEN).
  d.exec("listen " & channel)

proc notifications*(d: Db): seq[(string, string, int)] =
  ## (channel, payload, sender's backend pid) for every notification that has
  ## arrived. Never waits.
  if PQconsumeInput(d.conn) == 0:
    raise newException(DbError, $PQerrorMessage(d.conn))
  while true:
    let n = PQnotifies(d.conn)
    if n == nil: break
    result.add ($n.relname, $n.extra, int(n.bePid))
    PQfreemem(n)

proc value*(d: Db, sql: string, args: varargs[string]): string =
  ## First column of the first row, or "" when there is no row.
  let rs = d.rows(sql, args)
  if rs.len > 0 and rs[0].len > 0: rs[0][0] else: ""
