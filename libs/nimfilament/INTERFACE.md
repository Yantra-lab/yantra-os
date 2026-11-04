# nimfilament — interface

```nim
let s = newScene3D(640, 480)          # offscreen; s.ok is false without a GPU context
if s.load("fox.glb"): ...             # glTF 2.0 (.glb / .gltf); the camera frames it
s.camera((0'f32, 1, 4), (0'f32, 0, 0), fov = 45)
var px: seq[uint8]
discard s.render(t = 1.5, px)         # BGRA, top row first; animation 0 loops
s.animations; s.lastError; s.close()
```
