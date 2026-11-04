# nimwasmtime

wasmtime WASM runtime bindings for Nim — the JavaScript replacement layer
for Yantra. Sandboxed, fast, industrial-grade WASM execution.

## Status
- `t_wasm` PASS — compiles WAT directly (`wat2wasm`), instantiates,
  calls `add(7,35)=42`, `add(-5,5)=0`, `mul(6,7)=42` through the real
  wasmtime runtime.

## Layout
- `vendor/wasmtime-v19.0.2-x86_64-windows-c-api/` — official C API release
- `build/libwasmtime.a` — MinGW import library generated from the DLL via
  objdump+dlltool (the shipped `.lib` is MSVC-format and incompatible)
- `build/wasmtime.dll` — runtime DLL (must sit next to every exe that uses it)

## High-level API
```nim
import nimwasmtime

let engine = newEngine()
let store = newStore(engine)
let module = store.compileWat("""
  (module (func (export "add") (param i32 i32) (result i32)
    local.get 0 local.get 1 i32.add))
""")
let instance = module.instantiate()
echo instance.callI32I32ToI32("add", 7, 35)   # 42
```

Raw C99 surface available via `import nimwasmtime/raw`.

## Windows/MinGW notes
- The official `wasmtime.lib` is MSVC COFF: MinGW ld fails on `__chkstk`
  etc. Generate a proper import lib instead:
  ```bash
  objdump -p wasmtime.dll | grep -E '^\s+\[\s*[0-9]+\]' | awk '{print $NF}' \
    | sort -u > exports.txt        # then wrap in LIBRARY/EXPORTS def file
  dlltool -d wasmtime.def -D wasmtime.dll -l libwasmtime.a -m i386:x86-64
  ```
- Copy `wasmtime.dll` next to every executable (app-dir beats System32).
