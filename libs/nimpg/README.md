# nimpg

Postgres server extensions written in Nim. This is the foundation for keeping Yantra's code, wiki, users and agents in Postgres.

Postgres reports an ERROR by jumping up the C stack (`longjmp`). This library is the one place that makes that safe for Nim:

| Direction | Tool | What it guarantees |
|---|---|---|
| Nim calls Postgres | `pgGuard: ...` | A Postgres ERROR becomes a Nim `PgError`, with its message and SQLSTATE kept |
| Nim catches and continues | `pgSubxact: ...` | The work runs in a subtransaction that is rolled back on ERROR, so the backend stays usable |
| Postgres calls Nim | `pgFunction(name, impl)` | A Nim exception becomes a Postgres ERROR only after every Nim frame has returned, so nothing Nim owns is skipped |

## Rules for code inside a guard

Keep it to Postgres calls on plain values. Nim objects created inside a guarded block are skipped, not freed, if Postgres jumps out. Strings handed to Postgres are copied into Postgres memory (`pstrdup`) before the guard.

## Building and testing

Development Postgres 18 runs in the Arch WSL on port 5433. To build and test, from the repo root inside WSL:

```
PATH=/usr/bin:/usr/sbin:/bin nim r libs/nimpg/tests/run_tests.nim
```

The suite checks the following:
- arguments pass in and results come back out;
- SQL runs through SPI;
- a Postgres ERROR crosses into Nim with its SQLSTATE intact;
- a Nim exception becomes a Postgres ERROR;
- an error caught in Nim leaves the transaction usable;
- 5,000 caught errors and 2,000 rethrown errors in one statement are handled;
- resident memory stays flat across repeated rounds of errors.

The extension is built with Nim 2 and `--mm:arc`. Header paths come from `pg_config`.
