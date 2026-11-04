# nimjolt INTERFACE

## Types
- `Vec3*`: object with `x*, y*, z*: float32`
- `BodyId*`: distinct uint32 identifier for rigid bodies
- `PhysicsWorld*`: distinct pointer wrapping an initialized Jolt PhysicsSystem
- `MotionType*`: enum `mtStatic = 0`, `mtKinematic = 1`, `mtDynamic = 2`

## Procs
- `newPhysicsWorld*(gravityY: float32 = -9.81'f32): PhysicsWorld`
- `isValid*(w: PhysicsWorld): bool`
- `destroy*(w: PhysicsWorld)`
- `addStaticPlane*(w: PhysicsWorld; halfExtents: Vec3 = Vec3(x: 100.0, y: 1.0, z: 100.0); yOffset: float32 = -1.0): BodyId`
- `addBox*(w: PhysicsWorld; pos: Vec3; halfExtents: Vec3; motionType: MotionType = mtDynamic; restitution: float32 = 0.0'f32): BodyId`
- `step*(w: PhysicsWorld; dt: float32 = 1.0'f32 / 60.0'f32; collisionSteps: int = 1)`
- `bodyPosition*(w: PhysicsWorld; id: BodyId): Vec3`
- `bodyVelocity*(w: PhysicsWorld; id: BodyId): Vec3`
- `setLinearVelocity*(w: PhysicsWorld; id: BodyId; vel: Vec3)`
- `isResting*(w: PhysicsWorld; id: BodyId): bool`
