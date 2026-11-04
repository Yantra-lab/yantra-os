## nimjolt — Jolt Physics wrapper for Yantra (architecture §5).
##
## Wraps the official Jolt Physics C++ engine via `jolt_shim.cpp`.
## Provides deterministic 3D rigid-body simulation.

import std/os

const
  shimDir = currentSourcePath().parentDir
  msysDir = shimDir / ".." / ".." / ".." / "third_party" / "msys64" / "mingw64"
  joltInc = msysDir / "include"
  joltLib = msysDir / "lib" / "libJolt.dll.a"

{.compile("jolt_shim.cpp", "-std=c++17 -DNDEBUG -DJPH_SHARED_LIBRARY -DJPH_CROSS_PLATFORM_DETERMINISTIC -DJPH_OBJECT_LAYER_BITS=16 -DJPH_DEBUG_RENDERER -DJPH_PROFILE_ENABLED -DJPH_OBJECT_STREAM -mavx2 -mfma -I\"" & joltInc & "\"").}
{.passL: "\"" & joltLib & "\" -lstdc++".}

type
  Vec3* = object
    x*, y*, z*: float32

  BodyId* = distinct uint32

  PhysicsWorld* = distinct pointer

  MotionType* = enum
    mtStatic = 0
    mtKinematic = 1
    mtDynamic = 2

proc yj_world_new(gy: cfloat): pointer {.importc, cdecl.}
proc yj_world_free(w: pointer) {.importc, cdecl.}
proc yj_add_box(w: pointer; px, py, pz, hx, hy, hz: cfloat; mt: cint; rest: cfloat): uint32 {.importc, cdecl.}
proc yj_step(w: pointer; dt: cfloat; steps: cint) {.importc, cdecl.}
proc yj_get_position(w: pointer; id: uint32; ox, oy, oz: ptr cfloat) {.importc, cdecl.}
proc yj_get_velocity(w: pointer; id: uint32; ox, oy, oz: ptr cfloat) {.importc, cdecl.}
proc yj_set_velocity(w: pointer; id: uint32; vx, vy, vz: cfloat) {.importc, cdecl.}
proc yj_is_active(w: pointer; id: uint32): cint {.importc, cdecl.}

proc newPhysicsWorld*(gravityY: float32 = -9.81'f32): PhysicsWorld =
  PhysicsWorld(yj_world_new(gravityY))

proc isValid*(w: PhysicsWorld): bool =
  pointer(w) != nil

proc destroy*(w: PhysicsWorld) =
  yj_world_free(pointer(w))

proc addStaticPlane*(w: PhysicsWorld; halfExtents: Vec3 = Vec3(x: 100.0, y: 1.0, z: 100.0); yOffset: float32 = -1.0): BodyId =
  BodyId(yj_add_box(pointer(w), 0.0, yOffset, 0.0, halfExtents.x, halfExtents.y, halfExtents.z, cint(mtStatic), 0.0))

proc addBox*(w: PhysicsWorld; pos: Vec3; halfExtents: Vec3; motionType: MotionType = mtDynamic; restitution: float32 = 0.0'f32): BodyId =
  BodyId(yj_add_box(pointer(w), pos.x, pos.y, pos.z, halfExtents.x, halfExtents.y, halfExtents.z, cint(motionType), restitution))

proc step*(w: PhysicsWorld; dt: float32 = 1.0'f32 / 60.0'f32; collisionSteps: int = 1) =
  yj_step(pointer(w), dt, cint(collisionSteps))

proc bodyPosition*(w: PhysicsWorld; id: BodyId): Vec3 =
  var x, y, z: cfloat
  yj_get_position(pointer(w), uint32(id), addr x, addr y, addr z)
  Vec3(x: x, y: y, z: z)

proc bodyVelocity*(w: PhysicsWorld; id: BodyId): Vec3 =
  var x, y, z: cfloat
  yj_get_velocity(pointer(w), uint32(id), addr x, addr y, addr z)
  Vec3(x: x, y: y, z: z)

proc setLinearVelocity*(w: PhysicsWorld; id: BodyId; vel: Vec3) =
  yj_set_velocity(pointer(w), uint32(id), vel.x, vel.y, vel.z)

proc isResting*(w: PhysicsWorld; id: BodyId): bool =
  yj_is_active(pointer(w), uint32(id)) == 0

# --- the engine's physics (PH1) -------------------------------------------------------------
proc yj_add_body(w: pointer; shape: cint; sx, sy, sz: cfloat; verts: ptr float32; nv, stride: cint;
                 idx: ptr uint32; ni: cint; px, py, pz, qx, qy, qz, qw: cfloat; motion: cint;
                 mass, friction, restitution, damping: cfloat): uint32 {.importc, cdecl.}
proc yj_remove(w: pointer; id: uint32) {.importc, cdecl.}
proc yj_get_pose(w: pointer; id: uint32; p, q: ptr cfloat) {.importc, cdecl.}
proc yj_set_pose(w: pointer; id: uint32; px, py, pz, qx, qy, qz, qw, dt: cfloat) {.importc, cdecl.}
proc yj_impulse(w: pointer; id: uint32; x, y, z: cfloat) {.importc, cdecl.}
proc yj_force(w: pointer; id: uint32; x, y, z: cfloat) {.importc, cdecl.}
proc yj_set_angular(w: pointer; id: uint32; x, y, z: cfloat) {.importc, cdecl.}
proc yj_set_gravity(w: pointer; x, y, z: cfloat) {.importc, cdecl.}
proc yj_raycast(w: pointer; ox, oy, oz, dx, dy, dz: cfloat; body: ptr uint32; frac: ptr cfloat): cint {.importc, cdecl.}
proc yj_rope(w: pointer; a, b: uint32; wx, wy, wz, length: cfloat): cint {.importc, cdecl.}
proc yj_hinge(w: pointer; a, b: uint32; px, py, pz, ax, ay, az: cfloat): cint {.importc, cdecl.}
proc yj_unconstrain(w: pointer; cid: cint) {.importc, cdecl.}

type
  Quat4* = array[4, float32]            ## x, y, z, w
  BodyPose* = object
    pos*: array[3, float32]
    rot*: Quat4

proc addBody*(w: PhysicsWorld; shape: int; size: array[3, float32]; pose: BodyPose; motion: int;
              mass = 0'f32; friction = 0.5'f32; bounce = 0'f32; damping = 0.05'f32;
              verts: openArray[float32] = []; stride = 8; idx: openArray[uint32] = []): BodyId =
  ## shape: 0 box, 1 sphere, 2 plane, 3 cylinder, 4 capsule, 5 own triangles, 6 their hull;
  ## motion 1 fixed, 2 dynamic, 3 kinematic. BodyId(0) when not possible.
  BodyId(yj_add_body(pointer(w), cint(shape), size[0], size[1], size[2],
    (if verts.len > 0: unsafeAddr verts[0] else: nil), cint(verts.len div max(1, stride)), cint(stride),
    (if idx.len > 0: unsafeAddr idx[0] else: nil), cint(idx.len),
    pose.pos[0], pose.pos[1], pose.pos[2], pose.rot[0], pose.rot[1], pose.rot[2], pose.rot[3],
    cint(motion), mass, friction, bounce, damping))
proc remove*(w: PhysicsWorld; id: BodyId) = yj_remove(pointer(w), uint32(id))
proc pose*(w: PhysicsWorld; id: BodyId): BodyPose = yj_get_pose(pointer(w), uint32(id), addr result.pos[0], addr result.rot[0])
proc setPose*(w: PhysicsWorld; id: BodyId; p: BodyPose; dt = 0'f32) =
  yj_set_pose(pointer(w), uint32(id), p.pos[0], p.pos[1], p.pos[2], p.rot[0], p.rot[1], p.rot[2], p.rot[3], dt)
proc impulse*(w: PhysicsWorld; id: BodyId; v: array[3, float32]) = yj_impulse(pointer(w), uint32(id), v[0], v[1], v[2])
proc force*(w: PhysicsWorld; id: BodyId; v: array[3, float32]) = yj_force(pointer(w), uint32(id), v[0], v[1], v[2])
proc setAngular*(w: PhysicsWorld; id: BodyId; v: array[3, float32]) = yj_set_angular(pointer(w), uint32(id), v[0], v[1], v[2])
proc setGravity*(w: PhysicsWorld; g: array[3, float32]) = yj_set_gravity(pointer(w), g[0], g[1], g[2])
proc raycast*(w: PhysicsWorld; origin, dir: array[3, float32]): (bool, BodyId, float32) =
  ## The first body along `dir` (its length is the reach): (hit, body, fraction of dir).
  var b: uint32
  var f: cfloat
  if yj_raycast(pointer(w), origin[0], origin[1], origin[2], dir[0], dir[1], dir[2], addr b, addr f) == 1:
    (true, BodyId(b), float32(f))
  else: (false, BodyId(0), 0'f32)
proc rope*(w: PhysicsWorld; a: BodyId; b = BodyId(0); worldPoint: array[3, float32] = [0'f32, 0, 0]; length = 0'f32): int =
  ## A rope from a to b (or to a point in the world): never longer than `length` (0: as now).
  int(yj_rope(pointer(w), uint32(a), uint32(b), worldPoint[0], worldPoint[1], worldPoint[2], length))
proc hinge*(w: PhysicsWorld; a: BodyId; b = BodyId(0); at, axis: array[3, float32]): int =
  int(yj_hinge(pointer(w), uint32(a), uint32(b), at[0], at[1], at[2], axis[0], axis[1], axis[2]))
proc unconstrain*(w: PhysicsWorld; c: int) = yj_unconstrain(pointer(w), cint(c))
