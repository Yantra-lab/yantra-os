# nimwasmtime INTERFACE

## High-level (import nimwasmtime)
- `newEngine*(): Engine` — wasmtime execution engine
- `newStore*(engine): Store` — isolated sandbox (objects live here)
- `store.compileWat*(wat: string): Module` — compile WAT text
- `module.instantiate*(): Instance` — zero-import instantiation
- `instance.callI32I32ToI32*(name: string; a, b: int32): int32`
  Calls an exported `(i32,i32)->i32`; raises `WasmtimeError` on missing
  export, call failure, or WASM trap.

## Errors
`WasmtimeError` — carries formatted wasmtime diagnostics.

## Raw layer (import nimwasmtime/raw)
Direct C99 surface: engine/store/context/module/instance/func handles,
`WasmVal`/`WasmValunion`, byte vectors, `wat2wasm`, trap pointers.
