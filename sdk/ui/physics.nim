import std/math

## Physics (PH1): a mesh with `body = dynamic` falls, collides and bounces (Jolt, in the
## engine); `body = fixed` is ground and walls; `body = kinematic` is moved by the app and pushes.
## Objects are called by their @name:
##
##   box @crate(posY = 5, body = dynamic, mass = 20)
##   onClick: push("crate", 0, 200, 0)
##   let (x, y, z) = bodyPos("crate")
##   let hit = raycast((0'f32, 10'f32, 0'f32), (0'f32, -1'f32, 0'f32), reach = 50)
##   let web = rope("hero", (x, 30'f32, z))          # web-swinging
##   cut(web)

const
  fixed* = 1'i32        ## `body = fixed`: never moves (ground, walls, terrain from its own triangles)
  dynamic* = 2'i32      ## falls, collides, bounces
  kinematic* = 3'i32    ## the app moves it (posX…); it pushes what it meets

type
  Vec* = (float32, float32, float32)
  RayHit* = object
    hit*: bool
    name*: string       ## the @name of what it hit
    distance*: float32
    point*: Vec

when sizeof(pointer) == 4:
  proc yPhys(op, p, n: int32; a, b, c, d, e, f: float32): float32 {.importc: "y_phys", cdecl.}
  proc yPhysHit(p, cap: int32): int32 {.importc: "y_phys_hit", cdecl.}
else:
  proc yPhys(op, p, n: int32; a, b, c, d, e, f: float32): float32 = 0
  proc yPhysHit(p, cap: int32): int32 = 0

proc call(op: int32; name: string; a = 0'f32; b = 0'f32; c = 0'f32; d = 0'f32; e = 0'f32; f = 0'f32): float32 =
  yPhys(op, (if name.len > 0: cast[int32](name.cstring) else: 0'i32), int32(name.len), a, b, c, d, e, f)

proc push*(name: string; x, y, z: float32) = discard call(0, name, x, y, z)
  ## An impulse (N·s): a kick, a jump, a hit.
proc pushForce*(name: string; x, y, z: float32) = discard call(10, name, x, y, z)
  ## A force (N) for this step: thrust, wind, an engine.
proc setVelocity*(name: string; x, y, z: float32) = discard call(1, name, x, y, z)
proc spin*(name: string; x, y, z: float32) = discard call(9, name, x, y, z)
  ## Angular velocity, radians per second about each axis.
proc bodyPos*(name: string): Vec = (call(2, name, 0), call(2, name, 1), call(2, name, 2))
  ## Where physics has it now (metres).
proc bodyVel*(name: string): Vec = (call(3, name, 0), call(3, name, 1), call(3, name, 2))
proc bodyRot*(name: string): (float32, float32, float32, float32) =
  ## Its rotation as a quaternion (x, y, z, w).
  (call(8, name, 0), call(8, name, 1), call(8, name, 2), call(8, name, 3))
proc raycast*(origin, dir: Vec; reach = 100'f32): RayHit =
  ## The first body along `dir` from `origin`, within `reach` metres.
  let l = max(1e-6'f32, sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]))
  let (dx, dy, dz) = (dir[0] / l * reach, dir[1] / l * reach, dir[2] / l * reach)
  let d = call(4, "", origin[0], origin[1], origin[2], dx, dy, dz)
  if d < 0: return RayHit()
  var name = newString(64)
  let n = yPhysHit(cast[int32](addr name[0]), 64)
  name.setLen(clamp(n, 0, 64))
  RayHit(hit: true, name: name, distance: d,
         point: (origin[0] + dir[0] / l * d, origin[1] + dir[1] / l * d, origin[2] + dir[2] / l * d))
proc rope*(name: string; anchor: Vec; length = 0'f32): int =
  ## A rope from the object to a point in the world, never longer than `length` (0: as long as
  ## it is now); it goes slack when shorter. Returns the rope, for `cut` (-1: no such body yet).
  int(call(6, name, anchor[0], anchor[1], anchor[2], length))
proc cut*(rope: int) = discard call(7, "", float32(rope))
