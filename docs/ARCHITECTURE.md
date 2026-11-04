# Yantra OS Deep Technical Architecture

This document provides a comprehensive technical breakdown of how the Yantra operating platform is structured, how applications compile, how the host engine executes them, and how Meta Yoga coordinates layout resolution.

---

## 1. Architectural Layers

Yantra is divided into four distinct execution boundaries:

```
[ Application Layer ]
      Nim Source Code (DSL, Signals, Reactive State)
             |
             v (wasi-sdk / clang / nim c --os:standalone)
[ Sandboxed WASI Layer ]
      Hermetic .wasm Binary (Linear Memory, Typed Imports/Exports)
             |
             v (Memory-mapped IPC / Binary Ring Buffers)
[ Native Wire Protocol ]
      Node Creation, Property Updates, Event Dispatch
             |
             v
[ Host Runtime Layer ]
      Wasmtime + Meta Yoga 3.1.0 + Google Skia / Filament + SDL3 + miniaudio
```

### 1.1 The Sandboxed Guest (`apps/*`)
Guest applications are written in Nim against the Yantra SDK (`sdk/yantra.nim`). 
- **Compilation target:** `wasm32-wasi-threads` / `wasm32-unknown-wasi`.
- **Runtime weight:** Minimalist libc stub (`minilibc.c` + `panicoverride.nim`), which avoids dragging in the standard POSIX C runtime. This keeps compiled `.wasm` binaries between **200 KB and 500 KB**.
- **Memory safety:** Applications execute inside Wasmtime instances with dedicated, bound-checked linear memory. Guest code cannot touch host memory or make unauthorized syscalls.

### 1.2 The Wire Protocol
Guest applications do not call host GUI APIs directly. Instead, they serialize state mutations into an ultra-fast binary wire protocol:
- **Node Mutation:** `createNode(kind)`, `appendChild(parent, child)`, `setProp(node, key, val)`.
- **Layout Instructions:** `setFlexDirection`, `setWidth`, `setHeight`, `setFlexGrow`, `setGap`, `setPadding`.
- **Event Streaming:** Keyboard, mouse, touch, and resize events are dispatched into the guest's `yantra_dispatch` or `yantra_frame` entry points.

### 1.3 Meta Yoga Layout Integration (`yoga/*`)
Once received by the native host:
- The host synchronizes the protocol tree with a retained tree of `YogaNode` structures.
- Unchanged subtrees are kept hot in Yoga's internal layout cache (`copyStyle`).
- When a layout calculation is triggered via `calculateLayout(viewportWidth, viewportHeight)`:
  1. Yoga computes recursive flexbox dimensions (margins, paddings, gutters, flex grow/shrink).
  2. Bounding boxes `(left, top, width, height)` are resolved for every active node in under 200 microseconds.
  3. The computed rectangles are passed directly to Google Skia 2D and Filament 3D drawing routines.

### 1.4 Native Rendering & Foley Audio
- **2D Graphics:** Google Skia (`libskia.dll`, `libskparagraph.dll`, `libharfbuzz-0.dll`, `libfreetype-6.dll`) handles vector paths, sub-pixel text rasterization, and GPU surface blitting.
- **3D Graphics:** Google Filament (`yfilament.dll`) renders materials, PBR lighting, and 3D scenes.
- **Audio:** `miniaudio` streams uncompressed low-latency `.wav` Foley audio (e.g. typewriter keystrokes, carriage returns, and bells) directly through system audio endpoints.

---

## 2. The 135-DLL Hermetic Closure

Running complex native graphics engines on Windows usually requires installing large distribution bundles (Visual C++ Redistributable, Vulkan SDK, MSYS2 MinGW-w64).

To ensure hackathon judges can run Yantra OS immediately with **zero configuration**:
- The exact PE import dependency graph was harvested across all runtime layers.
- **39 root build DLLs** (`SDL3.dll`, `wasmtime.dll`, `yfilament.dll`, `libstdc++-6.dll`, `swresample-7.dll`, `swscale-10.dll`, etc.) and **96 desktop subsystem DLLs** (`accesskit.dll`, `libskia.dll`, `libJolt.dll`, `avcodec-63.dll`, etc.) were consolidated into `bin/`.
- Total standalone closure: **135 DLLs (255.8 MB)**, completely self-contained.
