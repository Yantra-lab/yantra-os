# nimblake3

Nim wrapper for the official upstream C BLAKE3 cryptographic hash function (v1.8.7, CC0-1.0 / Apache-2.0).
Provides high-speed tree hashing, keyed hashing, incremental hashing, and a SQLite-backed content-addressed asset store.

## Vendor Details
- Upstream: BLAKE3 (v1.8.7) via MSYS2 `mingw-w64-x86_64-libblake3`
- License: CC0-1.0 / Apache-2.0
- Build: Installed via `tools/setup.sh`; links against `libblake3.dll.a` and `libblake3-0.dll`

## Testing
Run tests via `bash libs/nimblake3/tests/run_tests.sh`.
