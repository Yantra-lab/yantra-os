# nimqt - Qt 6 QML/Quick bindings for Nim

**Full access to the Qt QML engine from Nim.** Load QML documents, instantiate
components, read/write properties, invoke QML functions, connect Nim closures
to any Qt signal, and expose Nim objects to QML as first-class QObjects -
with dynamic metaobjects built through `QMetaObjectBuilder`.

```nim
import nimqt

let app = newApplication()
let engine = newEngine()
let comp = engine.newComponentFromString(
  "import QtQuick\nRectangle { width: 100; height: 50 }")
doAssert comp.status() == stReady
let item = comp.createObject()
doAssert item.widthF == 100.0
```

## Status: verified green

| Suite | Result |
|---|---|
| tests/smoke (engine boot, file+string components, props, invoke, JS, errors) | PASS |
| tests/t_component (creation/error paths, async incubation) | PASS |
| tests/t_property (typed R/W, invalid props, binding re-eval) | PASS |
| tests/t_ecmascript (literals, closures, objects, error objects, VME fns) | PASS |
| tests/t_signals (Nim closures on Qt signals, QML->Nim calls) | PASS |
| examples/hello_qml, context_props, invoke_from_nim | PASS |

All verified headless (`QT_QPA_PLATFORM=offscreen`) against Qt 6.11.2.

## Installing

### Requirements
- **Nim >= 2.0**, built with **`nim cpp`** (importcpp packages must compile as C++)
- **Qt 6** dev libraries (Core, Gui, Qml, Quick); on Windows a matching
  MinGW-w64 GCC.

### Windows (bundled portable toolchain)
The repo ships a complete MSYS2 MinGW64 + Qt 6.11 toolchain under
`third_party/msys64/mingw64`. Nothing else needed:

```bash
cd nimqt
export PATH="$PWD/third_party/msys64/mingw64/bin:$PATH"
export TMP="$LOCALAPPDATA\\Temp" TEMP="$LOCALAPPDATA\\Temp"   # native Win path!
bash tests/run_tests.sh        # full suite + examples, offscreen
```

`config.nims` auto-detects the bundled toolchain; override with
`QT_TOOLCHAIN=/path/to/mingw64`. On Linux install `qt6-base qt6-declarative`
and set `QT_TOOLCHAIN=/usr`.

### Build rules that are NOT optional
1. Always `nim cpp`, never plain `nim c`.
2. `TMP`/`TEMP` must be Windows-native paths when driving MinGW from scripts,
   or the driver dies with "Cannot create temporary file" silently.
3. Keep `third_party/msys64/mingw64/bin` on PATH at RUNTIME too (Qt DLLs).

## API tour

| Type | Wraps | Notes |
|---|---|---|
| `Application` | `QGuiApplication` | singleton; `exec()`, `quit()`, `processEvents()` |
| `Engine` | `QQmlEngine` | `rootContext`, `evaluateJs`, global object |
| `Component` | `QQmlComponent` | string or URL load; `status()`, `errorsString()`, `createObject()`, async incubation (`createAsyncStart/Poll/Result`) |
| `Context` | `QQmlContext` | `setContextProperty(Obj)` |
| `View` | `QQuickView` | `setSource`, `show`, `resize`, `setTitle` |
| `Item` / `Window` | `QQuickItem` / `QQuickWindow` | typed accessors + generic property bridge |
| `Variant` | `QVariant` | exact Qt lifetime via `=destroy`; conversions |
| `JsValue` | `QJSValue` | call/construct, property access, conversions |

### Signals & exposed Nim objects
```nim
# Connect ANY Qt signal to a Nim closure:
let conn = item.connectSignal("widthChanged()") do(args: seq[Variant]):
  echo "width changed"

# Expose a Nim type to QML (dynamic metaobject under the hood):
type Counter = ref object of QObjectLike
method qmlClassSpec(c: Counter): tuple[name: string, props: seq[PropSpec],
    signals: seq[SignalSpec], slots: seq[SlotSpec]] =
  result.name = "Counter"
  result.slots = @[SlotSpec(name: "bump", params: @[], retVoid: true)]
method onInvoke(c: Counter; id: int; spec: SlotSpec; args: seq[Variant]): Variant =
  newVariant()
engine.rootContext().setContextPropertyObj("counter", exposeObject(counter))
```
Dynamic surfaces use the QVariant metatype uniformly; QML unwraps natively.
Non-void slots must declare `retVoid: false` and return `newVariant...()` from
`onInvoke`.

### Invoking QML functions from Nim
```nim
let r = item.invokeMethodV("doubleIt", newVariant(21.0))
doAssert r.toFloat() == 42.0
```
Dispatch uses Qt's string-based static `invokeMethod(Q_ARG...)` (the supported
path for dynamically-named members incl. QML script functions), converts args
to declared parameter metatypes, and falls back to `QQmlExpression` for engine-
context objects. For exposed objects whose Qt bool comes back `false` even on
success (builder-made metatypes), the bridge trusts metacall receipts instead.

## Tests
`tests/run_tests.sh` builds and runs everything headless. The ported subset
mirrors qtdeclarative `tests/auto/qml` cases (qqmlcomponent creation/error/
async, qqmlproperty typed semantics, qqmlecmascript evaluation) using the same
inputs and expectations as upstream.

## Ownership rules
1. Any QObject with a C++ parent is never freed by Nim.
2. Wrapper-owned handles are released explicitly; `createObject` results are
   owned by their context once parented.
3. `Application` intentionally leaks at exit (mirrors C++ practice).
4. `Variant` frees its heap QVariant via `=destroy`; JsValue exposes explicit
   `disposeQt` (automatic dtor wiring pending ABI validation).

## Known limitations
- No C++ templates or private APIs beyond `QMetaObjectBuilder`.
- Dynamic properties/signal params uniformly use QVariant metatype.
- Never store bycopy Qt values (`QJSValue`, `QString`, ...) in Nim
  `seq`s/fields that outlive an FFI call - pass pointers into shims that
  copy-construct on the C++ side (the bindings do this for you; keep it that
  way). Mixing the two heaps without copy ctors corrupts them (found via gdb:
  free() inside RtlFreeHeap from seq element teardown).
- Widgets out of scope by design; QtGui surface limited to what QML needs.

## Layout
```
src/nimqt/            low-level bindings + wrappers/marshaling/signals
src/nimqt/shim.cpp    C-linkage helpers: strings, bootstrap, dynamic invoke
src/nimqt/dynmeta.cpp QMetaObjectBuilder backend (DynTrap/DynExpose)
examples/             hello_qml, context_props, invoke_from_nim (+hello.qml)
tests/                smoke + ported Qt subset + run_tests.sh
third_party/          portable MSYS2 mingw64 + Qt 6.11 (Windows)
```
