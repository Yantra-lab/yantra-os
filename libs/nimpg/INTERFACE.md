# nimpg interface

```nim
import nimpg

pgModule()                                   # once per extension library

proc myImpl(fc: FunctionCallInfo): Datum = textDatum("hi " & fc.argText(0))
pgFunction(my_fn, myImpl)                    # SQL: create function my_fn(text) returns text
                                             #      as '<lib>.so', 'my_fn' language c strict

pgGuard:   <postgres calls>                  # Postgres ERROR -> raises PgError
pgSubxact: <postgres calls>                  # same, rolled back, safe to catch and continue

spiExec(sql): uint64                         # rows processed; errors propagate
spiExecSub(sql): uint64                      # in a subtransaction; errors are catchable

fc.argInt(i): int32    fc.argText(i): string
intDatum(x)  int64Datum(x)  textDatum(s)

PgError.sqlState                             # Postgres' packed SQLSTATE
```
