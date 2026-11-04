# nimjolt

Nim wrapper for the official Jolt Physics C++ engine (v5.3.0, MIT).
Provides deterministic 3D rigid-body simulation for games, cinematics, and timelines.

## Vendor Details
- Upstream: Jolt Physics (v5.3.0) via MSYS2 `mingw-w64-x86_64-jolt-physics`
- License: MIT
- Bridge: `src/jolt_shim.cpp` linking with `libJolt.dll.a` and `libJolt.dll`

## Testing
Run tests via `bash libs/nimjolt/tests/run_tests.sh`.
