# Downloads — the latest binaries, one per platform

**Policy (owner, 2026-11-06): binaries only — no archives, no folders — and only the newest
of each.** A new release overwrites these files; the previous build is deleted from the tree,
not kept beside it.

Built from commit `0cd4368c` (Android) and the `main` engine build `b8c3cdb6`; see SHA256SUMS.

| file | platform | run it with |
|---|---|---|
| `yantra-linux-x64` | Linux x86-64 (ELF, self-contained shared libs via rpath) | `./yantra-linux-x64 apps/desktop/app.wasm --watch` |
| `yantra-windows-x64.exe` | Windows 10/11 x86-64 (GUI subsystem) | double-click, or `yantra-windows-x64.exe apps\desktop\app.wasm` |
| `yantra-android-arm64.apk` | Android 9+ arm64 (signed, minSdk 28) | `adb install -r yantra-android-arm64.apk` |

All three run **the same app modules**: `yantra-os/apps/<id>/app.wasm` is shipped inside the APK
and byte-identical to the desktop's (20/20, sha256-compared by `tools/build-android.sh`).

Windows note: the `.exe` needs its DLL set, which is large; it ships beside the release assets
(`yantra-windows-x64-bin.zip` on the v1.0.0 release) rather than in this tree, so that this folder stays binaries-only.
