## Yantra Renderer Interface (R2)
##
## Defines the backend-agnostic Renderer contract (create/set/child/remove/frame/snapshot).
## `host/` imports only `render/api.nim`; concrete backends (`render/qt/`, `render/native/`)
## implement `Renderer`.

type
  Renderer* = ref object of RootObj

method createNode*(r: Renderer; kind: int32): int32 {.base.} =
  0'i32

method setPropInt*(r: Renderer; node, prop, val: int32) {.base.} =
  discard

method setPropFloat*(r: Renderer; node, prop: int32; val: float32) {.base.} =
  discard

method setPropStr*(r: Renderer; node, prop: int32; val: string) {.base.} =
  discard

method addChild*(r: Renderer; parent, child: int32) {.base.} =
  discard

method removeNode*(r: Renderer; node: int32) {.base.} =
  discard

method renderFrame*(r: Renderer; dt: float32) {.base.} =
  discard

method snapshot*(r: Renderer): string {.base.} =
  ""
