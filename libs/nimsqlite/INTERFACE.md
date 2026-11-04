# nimsqlite INTERFACE

## Types
- `SqliteError`: exception type raised on database and statement errors
- `SqliteDb`: reference type wrapping an open SQLite database handle
- `SqliteStmt`: reference type wrapping a prepared statement handle

## Procs and Templates
- `openDb*(path: string): SqliteDb`
- `close*(db: SqliteDb)`
- `exec*(db: SqliteDb; sql: string)`
- `prepare*(db: SqliteDb; sql: string): SqliteStmt`
- `step*(stmt: SqliteStmt): bool`
- `reset*(stmt: SqliteStmt)`
- `finalize*(stmt: SqliteStmt)`
- `bindInt*(stmt: SqliteStmt; col: int; val: int64)`
- `bindFloat*(stmt: SqliteStmt; col: int; val: float64)`
- `bindText*(stmt: SqliteStmt; col: int; val: string)`
- `bindBlob*(stmt: SqliteStmt; col: int; val: string)`
- `columnInt*(stmt: SqliteStmt; col: int): int64`
- `columnFloat*(stmt: SqliteStmt; col: int): float64`
- `columnText*(stmt: SqliteStmt; col: int): string`
- `columnBlob*(stmt: SqliteStmt; col: int): string`
- `lastInsertRowId*(db: SqliteDb): int64`
- `changes*(db: SqliteDb): int`
- `beginTransaction*(db: SqliteDb)`
- `commit*(db: SqliteDb)`
- `rollback*(db: SqliteDb)`
- `withTransaction*(db: SqliteDb; body: untyped)`
