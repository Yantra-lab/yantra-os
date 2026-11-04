## nimpg: write Postgres server extensions in Nim.
##
## Postgres reports an ERROR by longjmp-ing up the C stack. Nim must never be
## jumped over while it owns memory, and a Nim exception must never escape into
## Postgres. This module is the one place both rules are enforced:
##
## * `pgGuard` runs Postgres calls that may ERROR, catches the jump and turns it
##   into a Nim `PgError` (message and SQLSTATE kept).
## * `pgFunction` exports a Nim proc as a Postgres V1 function. Any Nim
##   exception is converted to a Postgres ERROR only after every Nim frame has
##   returned, so nothing Nim owns is skipped.

{.passC: "-I" & staticExec("pg_config --includedir-server").}
{.passC: "-fPIC".}
const pgh = "\"postgres.h\"\n#include \"fmgr.h\"\n#include \"executor/spi.h\"\n" &
  "#include \"utils/builtins.h\"\n#include \"utils/memutils.h\"\n" &
  "#include \"access/xact.h\"\n#include <setjmp.h>"
  ## postgres.h must come first in every C file that touches Postgres, so all
  ## imports share this one header string.

type
  Datum* = uint
  NullableDatum* {.importc, header: pgh.} = object
    value*: Datum
    isnull*: bool
  FunctionCallInfoBaseData* {.importc, header: pgh.} = object
    nargs*: cshort
    isnull*: bool
    args*: UncheckedArray[NullableDatum]
  FunctionCallInfo* = ptr FunctionCallInfoBaseData
  PgFinfoRecord* {.importc: "Pg_finfo_record", header: pgh.} = object
    api_version*: cint
  SigJmpBuf {.importc: "sigjmp_buf", header: pgh, bycopy.} = object
  ErrorData {.importc, header: pgh.} = object
    message: cstring
    sqlerrcode: cint
  MemoryContext = pointer

  PgError* = object of CatchableError
    sqlState*: cint ## Postgres' packed SQLSTATE, preserved across the bridge

var
  PG_exception_stack {.importc, header: pgh.}: ptr SigJmpBuf
  error_context_stack {.importc, header: pgh.}: pointer
  CurrentMemoryContext {.importc, header: pgh.}: MemoryContext
  ERROR {.importc, header: pgh.}: cint
  ERRCODE_EXTERNAL_ROUTINE_EXCEPTION {.importc, header: pgh.}: cint

proc sigsetjmp(env: SigJmpBuf, savemask: cint): cint {.importc, header: pgh.}
proc CopyErrorData(): ptr ErrorData {.importc, header: pgh.}
proc FlushErrorState() {.importc, header: pgh.}
proc FreeErrorData(e: ptr ErrorData) {.importc, header: pgh.}
proc MemoryContextSwitchTo(c: MemoryContext): MemoryContext {.importc, header: pgh.}
proc errstart(elevel: cint, domain: cstring): bool {.importc, header: pgh.}
proc errcode(code: cint): cint {.importc, header: pgh.}
proc errmsg_internal(fmt: cstring): cint {.importc, header: pgh, varargs.}
proc errfinish(filename: cstring, lineno: cint, funcname: cstring) {.importc, header: pgh.}
proc pstrdup(s: cstring): cstring {.importc, header: pgh.}
proc cstring_to_text(s: cstring): pointer {.importc, header: pgh.}
proc text_to_cstring(t: pointer): cstring {.importc, header: pgh.}
proc pg_detoast_datum_packed(d: pointer): pointer {.importc, header: pgh.}
proc pfree(p: pointer) {.importc, header: pgh.}

proc SPI_connect*(): cint {.importc, header: pgh.}
proc SPI_finish*(): cint {.importc, header: pgh.}
proc SPI_execute(src: cstring, readOnly: bool, count: clong): cint {.importc, header: pgh.}
var SPI_processed {.importc, header: pgh.}: uint64

template pgGuard*(body: untyped) =
  ## Runs `body`, which calls Postgres; a Postgres ERROR inside it becomes a
  ## Nim `PgError`. Keep `body` to Postgres calls on plain values: Nim objects
  ## created inside it are skipped (not freed) if Postgres jumps out.
  let savedStack = PG_exception_stack
  let savedCtx = error_context_stack
  let savedMcxt = CurrentMemoryContext
  var jb: SigJmpBuf
  if sigsetjmp(jb, 0) == 0:
    PG_exception_stack = addr jb
    body
    PG_exception_stack = savedStack
    error_context_stack = savedCtx
  else:
    PG_exception_stack = savedStack
    error_context_stack = savedCtx
    discard MemoryContextSwitchTo(savedMcxt)
    let ed = CopyErrorData()
    FlushErrorState()
    let e = (ref PgError)(msg: $ed.message, sqlState: ed.sqlerrcode)
    FreeErrorData(ed)
    raise e

proc throwToPostgres(msg: cstring, code: cint) {.noreturn.} =
  ## Raises a Postgres ERROR. Only called from the exported shim, after every
  ## Nim frame below it has returned; `msg` already lives in Postgres memory.
  if errstart(ERROR, nil):
    discard errcode(code)
    discard errmsg_internal("%s", msg)
  errfinish("nimpg", 0, "nim")
  quit 1 # unreachable: errfinish jumps away for ERROR

proc runCaught*(impl: proc (fc: FunctionCallInfo): Datum {.nimcall.},
                fc: FunctionCallInfo, err: var cstring, code: var cint): Datum =
  ## Calls `impl`; any Nim exception is copied into Postgres memory as `err`.
  result = 0
  try:
    result = impl(fc)
  except PgError as e:
    err = pstrdup(e.msg.cstring)
    code = e.sqlState
  except CatchableError as e:
    err = pstrdup(cstring("nim: " & e.msg))
    code = ERRCODE_EXTERNAL_ROUTINE_EXCEPTION

var finfoV1* = PgFinfoRecord(api_version: 1)

template pgFunction*(name: untyped, impl: typed) =
  ## Exports `impl(fc: FunctionCallInfo): Datum` to Postgres as `name`.
  proc `name finfo`(): ptr PgFinfoRecord {.exportc: "pg_finfo_" & astToStr(name),
                                            dynlib, cdecl.} =
    addr finfoV1
  proc name(fc: FunctionCallInfo): Datum {.exportc: astToStr(name), dynlib, cdecl.} =
    var err: cstring = nil
    var code: cint = 0
    result = runCaught(impl, fc, err, code)
    if err != nil: throwToPostgres(err, code)

template pgModule*() =
  ## Declares the module magic Postgres checks when it loads the library.
  {.emit: "PG_MODULE_MAGIC;".}

# Argument and result helpers.

proc argInt*(fc: FunctionCallInfo, i: int): int32 = cast[int32](fc.args[i].value)
proc argText*(fc: FunctionCallInfo, i: int): string =
  let t = pg_detoast_datum_packed(cast[pointer](fc.args[i].value))
  let c = text_to_cstring(t)
  result = $c
  pfree(c)
proc intDatum*(x: int32): Datum = cast[Datum](int(x))
proc int64Datum*(x: int64): Datum = cast[Datum](x)
proc textDatum*(s: string): Datum = cast[Datum](cstring_to_text(s.cstring))

var CurrentResourceOwner {.importc, header: pgh.}: pointer
proc BeginInternalSubTransaction(name: cstring) {.importc, header: pgh.}
proc ReleaseCurrentSubTransaction() {.importc, header: pgh.}
proc RollbackAndReleaseCurrentSubTransaction() {.importc, header: pgh.}

template pgSubxact*(body: untyped) =
  ## Like `pgGuard`, but `body` runs in a subtransaction that is rolled back
  ## on ERROR, so Nim may catch the resulting `PgError` and carry on. Without
  ## this, catching a Postgres ERROR and continuing leaves the backend broken.
  let savedMcxt = CurrentMemoryContext
  let savedOwner = CurrentResourceOwner
  BeginInternalSubTransaction(nil)
  discard MemoryContextSwitchTo(savedMcxt)
  let savedStack = PG_exception_stack
  let savedCtx = error_context_stack
  var jb: SigJmpBuf
  if sigsetjmp(jb, 0) == 0:
    PG_exception_stack = addr jb
    body
    ReleaseCurrentSubTransaction()
    PG_exception_stack = savedStack
    error_context_stack = savedCtx
    discard MemoryContextSwitchTo(savedMcxt)
    CurrentResourceOwner = savedOwner
  else:
    PG_exception_stack = savedStack
    error_context_stack = savedCtx
    discard MemoryContextSwitchTo(savedMcxt)
    let ed = CopyErrorData()
    FlushErrorState()
    RollbackAndReleaseCurrentSubTransaction()
    discard MemoryContextSwitchTo(savedMcxt)
    CurrentResourceOwner = savedOwner
    let e = (ref PgError)(msg: $ed.message, sqlState: ed.sqlerrcode)
    FreeErrorData(ed)
    raise e

proc spiExecSub*(sql: string): uint64 =
  ## Runs `sql` in a subtransaction: a Postgres ERROR becomes a `PgError` the
  ## caller may catch and recover from.
  let q = pstrdup(sql.cstring)
  var rc: cint = 0
  pgSubxact:
    rc = SPI_connect()
    rc = SPI_execute(q, false, 0)
    result = SPI_processed
    rc = SPI_finish()

proc spiExec*(sql: string): uint64 =
  ## Runs `sql` through SPI; a Postgres ERROR becomes a `PgError`.
  let q = pstrdup(sql.cstring) # in Postgres memory: safe if Postgres jumps
  var rc: cint = 0
  pgGuard:
    rc = SPI_connect()
    rc = SPI_execute(q, false, 0)
    result = SPI_processed
    rc = SPI_finish()
