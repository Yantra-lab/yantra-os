## Characters (CH1): a model's clip plays by name (`model @hero("hero.glb", play = "Run")`, changing
## it crossfades over blendTime); its bones can be turned on top of the animation, and read:
##
##   onFrame:
##     turnBone("hero", "Head", 0, lookYaw, 0)       # aim the head where the camera looks
##     let hand = bonePos("hero", "RightHand")        # shoot the web from the hand
##
## A crowd is one model with `instances = buf` (placements): each copy walks out of step.
import physics                       # Vec

when sizeof(pointer) == 4:
  proc yBone(op, mp, mn, bp, bn: int32; a, b, c: float32): float32 {.importc: "y_bone", cdecl.}
else:
  proc yBone(op, mp, mn, bp, bn: int32; a, b, c: float32): float32 = 0

proc call(op: int32; model, bone: string; a = 0'f32; b = 0'f32; c = 0'f32): float32 =
  yBone(op, (if model.len > 0: cast[int32](model.cstring) else: 0'i32), int32(model.len),
        (if bone.len > 0: cast[int32](bone.cstring) else: 0'i32), int32(bone.len), a, b, c)

proc turnBone*(model, bone: string; x, y, z: float32) = discard call(0, model, bone, x, y, z)
  ## Turns the bone by x, y, z degrees on top of what its animation does (every copy).
proc resetBone*(model, bone: string) = discard call(1, model, bone)
  ## The bone follows its animation alone again.
proc bonePos*(model, bone: string): Vec = (call(2, model, bone), call(3, model, bone), call(4, model, bone))
  ## Where the bone is in the world (metres), as last drawn.
