#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/ScaledShape.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Constraints/DistanceConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Body/BodyLockMulti.h>
#include <vector>

using namespace JPH;

namespace Layers {
  static constexpr ObjectLayer NON_MOVING = 0, MOVING = 1, NUM_LAYERS = 2;
};

class ObjectLayerPairFilterImpl : public ObjectLayerPairFilter {
public:
  virtual bool ShouldCollide(ObjectLayer a, ObjectLayer b) const override {
    return (a == Layers::NON_MOVING) ? (b == Layers::MOVING) : true;
  }
};

namespace BroadPhaseLayers {
  static constexpr BroadPhaseLayer NON_MOVING(0), MOVING(1);
  static constexpr uint NUM_LAYERS = 2;
};

class ObjectVsBroadPhaseLayerFilterImpl : public ObjectVsBroadPhaseLayerFilter {
public:
  virtual bool ShouldCollide(ObjectLayer a, BroadPhaseLayer b) const override {
    return (a == Layers::NON_MOVING) ? (b == BroadPhaseLayers::MOVING) : true;
  }
};

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
  BroadPhaseLayer mMap[Layers::NUM_LAYERS];
public:
  BPLayerInterfaceImpl() {
    mMap[Layers::NON_MOVING] = BroadPhaseLayers::NON_MOVING;
    mMap[Layers::MOVING] = BroadPhaseLayers::MOVING;
  }
  virtual uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::NUM_LAYERS; }
  virtual BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer in) const override { return mMap[in]; }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
  virtual const char *GetBroadPhaseLayerName(BroadPhaseLayer in) const override {
    return (in == BroadPhaseLayers::NON_MOVING) ? "NON_MOVING" : "MOVING";
  }
#endif
};

static void DummyTrace(const char *, ...) {}
static int sInitRefCount = 0;
static void EnsureJoltInit() {
  if (sInitRefCount++ == 0) {
    Trace = DummyTrace;
    Allocate = [](size_t s) { return malloc(s); };
    Reallocate = [](void *p, size_t, size_t s) { return realloc(p, s); };
    Free = [](void *p) { free(p); };
    AlignedAllocate = [](size_t s, size_t a) { return _aligned_malloc(s, a); };
    AlignedFree = [](void *p) { _aligned_free(p); };
    RegisterDefaultAllocator();
    Factory::sInstance = new Factory();
    RegisterTypes();
  }
}
static void ReleaseJoltInit() {
  if (--sInitRefCount == 0 && Factory::sInstance) {
    delete Factory::sInstance;
    Factory::sInstance = nullptr;
  }
}

class SimpleTempAllocator final : public TempAllocator {
  uint8_t *mBase; size_t mSize, mTop;
public:
  SimpleTempAllocator(size_t sz) : mSize(sz), mTop(0) { mBase = (uint8_t*)_aligned_malloc(sz, 64); }
  virtual ~SimpleTempAllocator() override { if (mBase) _aligned_free(mBase); }
  virtual void *Allocate(uint inSize) override {
    if (inSize == 0) return nullptr;
    size_t newTop = (mTop + 63) & ~63;
    if (newTop + inSize > mSize) return nullptr;
    void *ptr = mBase + newTop; mTop = newTop + inSize; return ptr;
  }
  virtual void Free(void *inAddress, uint inSize) override {
    if (!inAddress) return;
    size_t sz = (inSize + 63) & ~63;
    mTop = (mTop >= sz) ? mTop - sz : 0;
  }
};

struct YJWorld {
  BPLayerInterfaceImpl bpli;
  ObjectVsBroadPhaseLayerFilterImpl ovbplf;
  ObjectLayerPairFilterImpl olpf;
  SimpleTempAllocator tempAlloc;
  JobSystemThreadPool jobSys;
  PhysicsSystem physSys;
  bool broadPhaseOptimized;
  std::vector<Constraint*> constraints;       // ropes and hinges, by the id yj_rope/yj_hinge returned

  YJWorld(float gy) : tempAlloc(48 * 1024 * 1024), jobSys(cMaxPhysicsJobs, cMaxPhysicsBarriers, 1), broadPhaseOptimized(false) {
    physSys.Init(16384, 0, 16384, 8192, bpli, ovbplf, olpf);   // bodies, pairs, contacts: a city of props
    physSys.SetGravity(Vec3(0.0f, gy, 0.0f));
  }
  ~YJWorld() {
    for (Constraint* c : constraints) if (c) physSys.RemoveConstraint(c);
    constraints.clear();
    ReleaseJoltInit();
  }
};

extern "C" {
void *yj_world_new(float gravity_y) { EnsureJoltInit(); return new YJWorld(gravity_y); }
void yj_world_free(void *w) { if (w) delete static_cast<YJWorld*>(w); }

uint32_t yj_add_box(void *w, float px, float py, float pz, float hx, float hy, float hz, int motion_type, float restitution) {
  if (!w) return 0;
  auto *yw = static_cast<YJWorld*>(w); yw->broadPhaseOptimized = false;
  BoxShapeSettings shapeSettings(Vec3(hx, hy, hz)); shapeSettings.SetEmbedded();
  ShapeSettings::ShapeResult res = shapeSettings.Create();
  if (res.HasError()) return 0;
  EMotionType mt = (motion_type == 0) ? EMotionType::Static : (motion_type == 1) ? EMotionType::Kinematic : EMotionType::Dynamic;
  BodyCreationSettings settings(res.Get(), RVec3(px, py, pz), Quat::sIdentity(), mt, (mt == EMotionType::Static) ? Layers::NON_MOVING : Layers::MOVING);
  settings.mRestitution = restitution;
  return yw->physSys.GetBodyInterface().CreateAndAddBody(settings, (mt == EMotionType::Static) ? EActivation::DontActivate : EActivation::Activate).GetIndexAndSequenceNumber();
}

void yj_step(void *w, float dt, int collision_steps) {
  if (!w) return;
  auto *yw = static_cast<YJWorld*>(w);
  if (!yw->broadPhaseOptimized) { yw->physSys.OptimizeBroadPhase(); yw->broadPhaseOptimized = true; }
  yw->physSys.Update(dt, collision_steps, &yw->tempAlloc, &yw->jobSys);
}

void yj_get_position(void *w, uint32_t id, float *ox, float *oy, float *oz) {
  if (!w) return;
  RVec3 p = static_cast<YJWorld*>(w)->physSys.GetBodyInterface().GetPosition(BodyID(id));
  if (ox) *ox = (float)p.GetX(); if (oy) *oy = (float)p.GetY(); if (oz) *oz = (float)p.GetZ();
}

void yj_get_velocity(void *w, uint32_t id, float *ox, float *oy, float *oz) {
  if (!w) return;
  Vec3 v = static_cast<YJWorld*>(w)->physSys.GetBodyInterface().GetLinearVelocity(BodyID(id));
  if (ox) *ox = v.GetX(); if (oy) *oy = v.GetY(); if (oz) *oz = v.GetZ();
}

void yj_set_velocity(void *w, uint32_t id, float vx, float vy, float vz) {
  if (w) static_cast<YJWorld*>(w)->physSys.GetBodyInterface().SetLinearVelocity(BodyID(id), Vec3(vx, vy, vz));
}

int yj_is_active(void *w, uint32_t id) {
  return (w && static_cast<YJWorld*>(w)->physSys.GetBodyInterface().IsActive(BodyID(id))) ? 1 : 0;
}
}

// --- the engine's physics (PH1): every shape a scene has, poses, pushes, rays, ropes, hinges --
extern "C" {
// A body for a scene object. shape: 0 box, 1 sphere, 2 plane (thin box), 3 cylinder, 4 capsule,
// 5 the object's own triangles (fixed bodies: terrain, buildings), 6 their convex hull (moving
// ones). sx, sy, sz: its size (metres). motion: 1 fixed, 2 dynamic, 3 kinematic (moved by the
// app). 0 when the shape is not possible.
uint32_t yj_add_body(void* w, int shape, float sx, float sy, float sz, const float* verts, int nv, int stride,
                     const uint32_t* idx, int ni, float px, float py, float pz, float qx, float qy, float qz, float qw,
                     int motion, float mass, float friction, float restitution, float damping) {
  if (!w) return 0;
  auto* yw = static_cast<YJWorld*>(w); yw->broadPhaseOptimized = false;
  ShapeSettings::ShapeResult res;
  float hx = sx * 0.5f, hy = sy * 0.5f, hz = sz * 0.5f;
  if (shape == 1) res = SphereShapeSettings(std::max(0.01f, hx)).Create();
  else if (shape == 2) { BoxShapeSettings b(Vec3(std::max(0.01f, hx), 0.02f, std::max(0.01f, hz)), 0.0f); res = b.Create(); }
  else if (shape == 3) res = CylinderShapeSettings(std::max(0.02f, hy), std::max(0.01f, hx), 0.0f).Create();
  else if (shape == 4) res = CapsuleShapeSettings(std::max(0.01f, hy - hx), std::max(0.01f, hx)).Create();
  else if ((shape == 5 || shape == 6) && verts && nv >= 3) {
    if (shape == 5 && idx && ni >= 3) {
      VertexList vl; IndexedTriangleList tl;
      for (int i = 0; i < nv; i++) vl.push_back(Float3(verts[i * stride] * sx, verts[i * stride + 1] * sy, verts[i * stride + 2] * sz));
      for (int i = 0; i + 2 < ni; i += 3) tl.push_back(IndexedTriangle(idx[i], idx[i + 1], idx[i + 2], 0));
      res = MeshShapeSettings(vl, tl).Create();
    } else {
      Array<Vec3> pts;
      for (int i = 0; i < nv; i++) pts.push_back(Vec3(verts[i * stride] * sx, verts[i * stride + 1] * sy, verts[i * stride + 2] * sz));
      res = ConvexHullShapeSettings(pts).Create();
    }
  } else { BoxShapeSettings b(Vec3(std::max(0.01f, hx), std::max(0.01f, hy), std::max(0.01f, hz)), std::min(0.05f, std::min(hx, std::min(hy, hz)) * 0.5f)); res = b.Create(); }
  if (res.HasError()) return 0;
  EMotionType mt = motion == 1 ? EMotionType::Static : motion == 3 ? EMotionType::Kinematic : EMotionType::Dynamic;
  if (mt == EMotionType::Dynamic && shape == 5) mt = EMotionType::Static;     // a triangle mesh cannot move
  BodyCreationSettings s(res.Get(), RVec3(px, py, pz), Quat(qx, qy, qz, qw).Normalized(), mt,
                         mt == EMotionType::Static ? Layers::NON_MOVING : Layers::MOVING);
  s.mFriction = friction;
  s.mRestitution = restitution;
  s.mLinearDamping = damping;
  s.mAngularDamping = std::max(0.05f, damping);
  if (mt == EMotionType::Dynamic && mass > 0) {
    s.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
    s.mMassPropertiesOverride.mMass = mass;
  }
  return yw->physSys.GetBodyInterface().CreateAndAddBody(s, mt == EMotionType::Static ? EActivation::DontActivate
                                                                                   : EActivation::Activate).GetIndexAndSequenceNumber();
}

void yj_remove(void* w, uint32_t id) {
  if (!w) return;
  BodyInterface& bi = static_cast<YJWorld*>(w)->physSys.GetBodyInterface();
  bi.RemoveBody(BodyID(id)); bi.DestroyBody(BodyID(id));
}

// Position and rotation (quaternion x, y, z, w) now.
void yj_get_pose(void* w, uint32_t id, float* p, float* q) {
  if (!w) return;
  BodyInterface& bi = static_cast<YJWorld*>(w)->physSys.GetBodyInterface();
  RVec3 pp; Quat qq;
  bi.GetPositionAndRotation(BodyID(id), pp, qq);
  p[0] = (float)pp.GetX(); p[1] = (float)pp.GetY(); p[2] = (float)pp.GetZ();
  q[0] = qq.GetX(); q[1] = qq.GetY(); q[2] = qq.GetZ(); q[3] = qq.GetW();
}

// Puts it there (the app moved it); a kinematic body is moved there over `dt` instead, so it
// pushes what it meets.
void yj_set_pose(void* w, uint32_t id, float px, float py, float pz, float qx, float qy, float qz, float qw, float dt) {
  if (!w) return;
  BodyInterface& bi = static_cast<YJWorld*>(w)->physSys.GetBodyInterface();
  if (dt > 0 && bi.GetMotionType(BodyID(id)) == EMotionType::Kinematic)
    bi.MoveKinematic(BodyID(id), RVec3(px, py, pz), Quat(qx, qy, qz, qw).Normalized(), dt);
  else bi.SetPositionAndRotation(BodyID(id), RVec3(px, py, pz), Quat(qx, qy, qz, qw).Normalized(), EActivation::Activate);
}

void yj_impulse(void* w, uint32_t id, float x, float y, float z) {
  if (w) static_cast<YJWorld*>(w)->physSys.GetBodyInterface().AddImpulse(BodyID(id), Vec3(x, y, z));
}
void yj_force(void* w, uint32_t id, float x, float y, float z) {
  if (w) static_cast<YJWorld*>(w)->physSys.GetBodyInterface().AddForce(BodyID(id), Vec3(x, y, z));
}
void yj_set_angular(void* w, uint32_t id, float x, float y, float z) {
  if (w) static_cast<YJWorld*>(w)->physSys.GetBodyInterface().SetAngularVelocity(BodyID(id), Vec3(x, y, z));
}
void yj_set_gravity(void* w, float x, float y, float z) {
  if (w) static_cast<YJWorld*>(w)->physSys.SetGravity(Vec3(x, y, z));
}

// The first body a ray from o along d (its length is the reach) hits: 1 with the body, the
// fraction of d where, and the point; 0 if none.
int yj_raycast(void* w, float ox, float oy, float oz, float dx, float dy, float dz, uint32_t* body, float* frac) {
  if (!w) return 0;
  auto* yw = static_cast<YJWorld*>(w);
  RRayCast ray{RVec3(ox, oy, oz), Vec3(dx, dy, dz)};
  RayCastResult hit;
  if (!yw->physSys.GetNarrowPhaseQuery().CastRay(ray, hit)) return 0;
  *body = hit.mBodyID.GetIndexAndSequenceNumber();
  *frac = hit.mFraction;
  return 1;
}

static int keep(YJWorld* yw, Constraint* c) {
  yw->physSys.AddConstraint(c);
  for (size_t i = 0; i < yw->constraints.size(); i++) if (!yw->constraints[i]) { yw->constraints[i] = c; return (int)i; }
  yw->constraints.push_back(c);
  return (int)yw->constraints.size() - 1;
}

// A rope from body a (at its centre) to body b (at its centre), or to a fixed point in the world
// (b = 0): it never gets longer than `length` (0: as long as it is now) but can go slack.
int yj_rope(void* w, uint32_t a, uint32_t b, float wx, float wy, float wz, float length) {
  if (!w) return -1;
  auto* yw = static_cast<YJWorld*>(w);
  BodyLockInterface const& li = yw->physSys.GetBodyLockInterface();
  BodyID ids[2] = {BodyID(a), BodyID(b)};
  BodyLockMultiWrite lock(li, ids, b ? 2 : 1);
  Body* ba = lock.GetBody(0);
  if (!ba) return -1;
  Body* bb = b ? lock.GetBody(1) : &Body::sFixedToWorld;
  if (!bb) return -1;
  DistanceConstraintSettings s;
  s.mSpace = EConstraintSpace::WorldSpace;
  s.mPoint1 = ba->GetCenterOfMassPosition();
  s.mPoint2 = b ? bb->GetCenterOfMassPosition() : RVec3(wx, wy, wz);
  float now = (float)(s.mPoint2 - s.mPoint1).Length();
  s.mMinDistance = 0.0f;
  s.mMaxDistance = length > 0 ? length : now;
  ba->SetAllowSleeping(false);
  return keep(yw, s.Create(*ba, *bb));
}

// A hinge between body a and body b (or the world, b = 0) at world point p, turning about axis.
int yj_hinge(void* w, uint32_t a, uint32_t b, float px, float py, float pz, float ax, float ay, float az) {
  if (!w) return -1;
  auto* yw = static_cast<YJWorld*>(w);
  BodyLockInterface const& li = yw->physSys.GetBodyLockInterface();
  BodyID ids[2] = {BodyID(a), BodyID(b)};
  BodyLockMultiWrite lock(li, ids, b ? 2 : 1);
  Body* ba = lock.GetBody(0);
  if (!ba) return -1;
  Body* bb = b ? lock.GetBody(1) : &Body::sFixedToWorld;
  if (!bb) return -1;
  HingeConstraintSettings s;
  s.mSpace = EConstraintSpace::WorldSpace;
  s.mPoint1 = s.mPoint2 = RVec3(px, py, pz);
  Vec3 axis = Vec3(ax, ay, az).Normalized();
  s.mHingeAxis1 = s.mHingeAxis2 = axis;
  s.mNormalAxis1 = s.mNormalAxis2 = axis.GetNormalizedPerpendicular();
  return keep(yw, s.Create(*ba, *bb));
}

void yj_unconstrain(void* w, int cid) {
  if (!w) return;
  auto* yw = static_cast<YJWorld*>(w);
  if (cid < 0 || cid >= (int)yw->constraints.size() || !yw->constraints[cid]) return;
  yw->physSys.RemoveConstraint(yw->constraints[cid]);
  yw->constraints[cid] = nullptr;
}
}
