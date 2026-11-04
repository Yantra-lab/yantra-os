## nimfilament — 3D for Yantra through Google Filament (physically based rendering, glTF 2.0
## models, animation, shadows). Filament's Windows release is MSVC-built, so a small C shim
## (src/filament_shim.cpp, built by build.bat into build/yfilament.dll) is the boundary.
## Scenes render offscreen into RGBA pixels: the engine draws them like an image.

import std/os

const dll = currentSourcePath().parentDir / ".." / "build" / "yfilament.dll"
{.passL: dll.}

type Scene3D* = object
  h: pointer
  width*, height*: int

proc yf_create(w, h: cint): pointer {.importc, cdecl.}
proc yf_load(h: pointer; path: cstring): cint {.importc, cdecl.}
proc yf_camera(h: pointer; ex, ey, ez, tx, ty, tz, fov: cfloat) {.importc, cdecl.}
proc yf_animations(h: pointer): cint {.importc, cdecl.}
proc yf_render(h: pointer; t: cdouble; rgba: pointer): cint {.importc, cdecl.}
proc yf_error(h: pointer): cstring {.importc, cdecl.}
proc yf_destroy(h: pointer) {.importc, cdecl.}

proc newScene3D*(width, height: int): Scene3D =
  ## An offscreen 3D view: a sun, soft sky light, a camera; nil `h` if no GPU context.
  Scene3D(h: yf_create(cint(width), cint(height)), width: width, height: height)

proc ok*(s: Scene3D): bool = s.h != nil
proc load*(s: Scene3D; path: string): bool = yf_load(s.h, path.cstring) == 1
  ## A glTF 2.0 model (.glb or .gltf); the camera frames it.
proc lastError*(s: Scene3D): string = $yf_error(s.h)
proc camera*(s: Scene3D; eye, target: (float32, float32, float32); fov = 0'f32) =
  yf_camera(s.h, eye[0], eye[1], eye[2], target[0], target[1], target[2], fov)
proc animations*(s: Scene3D): int = int(yf_animations(s.h))
proc render*(s: Scene3D; t: float; rgba: var seq[uint8]): bool =
  ## Draws the scene at `t` seconds (animation 0 loops) into `rgba` (BGRA, top row first).
  rgba.setLen(s.width * s.height * 4)
  yf_render(s.h, t, addr rgba[0]) == 1
proc close*(s: Scene3D) = (if s.h != nil: yf_destroy(s.h))

# --- scene objects (S3D): an app's own meshes, lights and models, each an id ------------------
proc yf_obj_mesh(h: pointer; id: cint; v: ptr float32; nv: cint; idx: ptr uint32; ni, ninst: cint): cint {.importc, cdecl.}
proc yf_obj_instances(h: pointer; id: cint; m: ptr float32; n: cint) {.importc, cdecl.}
proc yf_obj_material(h: pointer; id: cint; r, g, b, a, metal, rough, er, eg, eb: cfloat) {.importc, cdecl.}
proc yf_obj_transform(h: pointer; id: cint; m: ptr float32) {.importc, cdecl.}
proc yf_obj_visible(h: pointer; id, on: cint) {.importc, cdecl.}
proc yf_obj_light(h: pointer; id, kind: cint; r, g, b, intensity, px, py, pz, dx, dy, dz, falloff: cfloat;
                  shadows: cint): cint {.importc, cdecl.}
proc yf_obj_model(h: pointer; path: cstring): cint {.importc, cdecl.}
proc yf_obj_animate(h: pointer; id, which: cint; t: cdouble) {.importc, cdecl.}
proc yf_obj_remove(h: pointer; id: cint) {.importc, cdecl.}
proc yf_obj_shader(h: pointer; id: cint; frag, vert: cstring; blend, unlit: cint): cint {.importc, cdecl.}
proc yf_obj_uniforms(h: pointer; id: cint; time: cfloat; u: ptr float32) {.importc, cdecl.}
proc yf_obj_texture(h: pointer; id: cint; path: cstring; tu, tv: cfloat): cint {.importc, cdecl.}
proc yf_post(h: pointer; taa: cint; dofFocus, dofBlur: cfloat; ssr: cint; vignette, exposure, contrast,
             saturation: cfloat; toneMap: cint; fogHeight, fogFalloff: cfloat) {.importc, cdecl.}
proc yf_obj_map(h: pointer; id, slot: cint; path: cstring; tu, tv: cfloat): cint {.importc, cdecl.}
proc yf_tex_pixels(h: pointer; key: cstring; rgba: pointer; w, ht, srgb: cint): cint {.importc, cdecl.}
proc yf_obj_surface(h: pointer; id: cint; normalScale: cfloat; alpha: cint; cutoff: cfloat) {.importc, cdecl.}
proc yf_obj_colors(h: pointer; id: cint; rgba: pointer; n: cint) {.importc, cdecl.}
proc yf_obj_model_n(h: pointer; path: cstring; count: cint): cint {.importc, cdecl.}
proc yf_obj_copies(h: pointer; id: cint): cint {.importc, cdecl.}
proc yf_obj_copy_transform(h: pointer; id, k: cint; m: ptr float32) {.importc, cdecl.}
proc yf_obj_clip(h: pointer; id: cint; name: cstring): cint {.importc, cdecl.}
proc yf_obj_pose(h: pointer; id, k, a: cint; ta: cdouble; b: cint; tb: cdouble; alpha: cfloat) {.importc, cdecl.}
proc yf_obj_bone(h: pointer; id, k: cint; bone: cstring; qx, qy, qz, qw, px, py, pz: cfloat): cint {.importc, cdecl.}
proc yf_obj_bone_world(h: pointer; id, k: cint; bone: cstring; o: ptr cfloat): cint {.importc, cdecl.}
proc yf_rt(h: pointer; key: cstring; w, ht: cint; ex, ey, ez, tx, ty, tz, fov: cfloat): cint {.importc, cdecl.}
proc yf_obj_shows(h: pointer; id: cint; key: cstring) {.importc, cdecl.}
proc yf_obj_has_animation(h: pointer; id, which: cint): cint {.importc, cdecl.}
proc yf_env(h: pointer; sr, sg, sb, sa, fog, fr, fg, fb, ambient: cfloat; shadows, ssao: cint; bloom: cfloat;
            msaa: cint) {.importc, cdecl.}
proc yf_camera_ex(h: pointer; ex, ey, ez, tx, ty, tz, fov, nearZ, farZ: cfloat) {.importc, cdecl.}

type
  Rgb* = tuple[r, g, b: float32]
  Mat4* = array[16, float32]           ## column-major, like Filament and glTF

proc mesh*(s: Scene3D; id: int; verts: openArray[float32]; idx: openArray[uint32]; instances = 1): int =
  ## Mesh `id` (a new one when `id` < 0): `verts` is position, normal and uv per vertex (8
  ## floats), `idx` its triangles. Returns its id (-1 if empty). Rebuilding keeps its transform.
  if verts.len < 8 or idx.len < 3: return -1
  int(yf_obj_mesh(s.h, cint(id), unsafeAddr verts[0], cint(verts.len div 8), unsafeAddr idx[0],
                  cint(idx.len), cint(instances)))
proc instances*(s: Scene3D; id: int; m: openArray[float32]) =
  ## Places an instanced mesh's copies: 16 floats (a Mat4) each.
  if m.len >= 16: yf_obj_instances(s.h, cint(id), unsafeAddr m[0], cint(m.len div 16))
proc material*(s: Scene3D; id: int; color: Rgb; alpha = 1'f32; metal = 0'f32; rough = 0.6'f32;
               glow: Rgb = (0'f32, 0'f32, 0'f32)) =
  yf_obj_material(s.h, cint(id), color.r, color.g, color.b, alpha, metal, rough, glow.r, glow.g, glow.b)
proc transform*(s: Scene3D; id: int; m: Mat4) = yf_obj_transform(s.h, cint(id), unsafeAddr m[0])
proc texture*(s: Scene3D; id: int; path: string; tiling = (1'f32, 1'f32)): bool =
  ## Mesh `id`'s image map (png/jpeg; "" none), repeated tiling.x by tiling.y times.
  yf_obj_texture(s.h, cint(id), path.cstring, tiling[0], tiling[1]) == 1
type MapSlot* = enum
  msColor, msNormal, msOrm, msEmissive   ## ORM: occlusion (r), roughness (g), metal (b), like glTF
proc map*(s: Scene3D; id: int; slot: MapSlot; path: string; tiling = (1'f32, 1'f32)): bool =
  ## Mesh `id`'s map in `slot`: an image file, or a key `pixels` made; "" none.
  yf_obj_map(s.h, cint(id), cint(ord(slot)), path.cstring, tiling[0], tiling[1]) == 1
proc pixels*(s: Scene3D; key: string; rgba: openArray[byte]; w, h: int; srgb = true): bool =
  ## A texture from RGBA bytes (not premultiplied) under `key`, for `map`; again to update it.
  rgba.len >= w * h * 4 and w > 0 and h > 0 and
    yf_tex_pixels(s.h, key.cstring, unsafeAddr rgba[0], cint(w), cint(h), cint(ord(srgb))) == 1
proc surface*(s: Scene3D; id: int; normalScale = 1'f32; alpha = 0; cutoff = 0.5'f32) =
  ## Normal map strength; alpha 0 opaque, 1 blended (glass, water), 2 cut out below `cutoff`.
  yf_obj_surface(s.h, cint(id), normalScale, cint(alpha), cutoff)
proc colors*(s: Scene3D; id: int; rgba: openArray[byte]) =
  ## A colour per instance (4 bytes each, placement order); empty: none.
  yf_obj_colors(s.h, cint(id), (if rgba.len >= 4: unsafeAddr rgba[0] else: nil), cint(rgba.len div 4))
proc model*(s: Scene3D; path: string; copies: int): int = int(yf_obj_model_n(s.h, path.cstring, cint(copies)))
  ## A glTF model with `copies` copies (a crowd); -1 (lastError says why).
proc copies*(s: Scene3D; id: int): int = int(yf_obj_copies(s.h, cint(id)))
proc placeCopy*(s: Scene3D; id, k: int; m: Mat4) = yf_obj_copy_transform(s.h, cint(id), cint(k), unsafeAddr m[0])
proc clip*(s: Scene3D; id: int; name: string): int = int(yf_obj_clip(s.h, cint(id), name.cstring))
  ## The index of the clip called `name`, -1 if none.
proc pose*(s: Scene3D; id, k, clip: int; t: float; fromClip = -1; fromT = 0.0; alpha = 1'f32) =
  ## Copy k at `t` s of `clip`, blended from `fromClip` at `fromT` by alpha (0 all from, 1 all clip).
  yf_obj_pose(s.h, cint(id), cint(k), cint(clip), t, cint(fromClip), fromT, alpha)
proc bone*(s: Scene3D; id, k: int; name: string; q: array[4, float32]; move = [0'f32, 0, 0]): bool =
  ## An offset for a bone (k < 0: every copy) on top of its animation; all zero: none.
  yf_obj_bone(s.h, cint(id), cint(k), name.cstring, q[0], q[1], q[2], q[3], move[0], move[1], move[2]) == 1
proc boneWorld*(s: Scene3D; id, k: int; name: string): (bool, array[3, float32]) =
  var o: array[3, float32]
  result = (yf_obj_bone_world(s.h, cint(id), cint(k), name.cstring, addr o[0]) == 1, o)
proc renderTarget*(s: Scene3D; key: string; w, h: int; eye, target: (float32, float32, float32); fov = 45'f32): bool =
  ## A camera drawing the scene into texture `key` (w x h) for maps; w = 0 removes it.
  yf_rt(s.h, key.cstring, cint(w), cint(h), eye[0], eye[1], eye[2], target[0], target[1], target[2], fov) == 1
proc shows*(s: Scene3D; id: int; key: string) = yf_obj_shows(s.h, cint(id), key.cstring)
  ## Mesh `id` shows camera texture `key` ("" none): that camera leaves it out.
proc visible*(s: Scene3D; id: int; on: bool) = yf_obj_visible(s.h, cint(id), cint(ord(on)))
proc light*(s: Scene3D; id, kind: int; color: Rgb; intensity: float32; pos, dir: (float32, float32, float32);
            falloff = 0'f32; shadows = true): int =
  ## Light `id` (new when < 0): kind 0 sun, 1 point, 2 spot. The first replaces the default sun.
  int(yf_obj_light(s.h, cint(id), cint(kind), color.r, color.g, color.b, intensity, pos[0], pos[1], pos[2],
                   dir[0], dir[1], dir[2], falloff, cint(ord(shadows))))
proc model*(s: Scene3D; path: string): int = int(yf_obj_model(s.h, path.cstring))
  ## A glTF model as an object with its own transform; -1 (lastError says why).
proc animate*(s: Scene3D; id, which: int; t: float) = yf_obj_animate(s.h, cint(id), cint(which), t)
proc remove*(s: Scene3D; id: int) = yf_obj_remove(s.h, cint(id))
proc shader*(s: Scene3D; id: int; frag: string; vert = ""; transparent = false; unlit = false): bool =
  ## Mesh `id` drawn by the app's own shader (compiled natively, cached): `frag` is the body of
  ## material() (set material.baseColor, emissive, roughness...), `vert` of materialVertex()
  ## (move material.worldPosition). They see materialParams.baseColor/metallic/roughness/
  ## emissive, .time and .u[0..3]. False (lastError) if it did not compile.
  yf_obj_shader(s.h, cint(id), frag.cstring, vert.cstring, cint(ord(transparent)), cint(ord(unlit))) == 1
proc uniforms*(s: Scene3D; id: int; time: float32; u: array[16, float32]) =
  ## A custom shader's inputs: time (s) and u[0..3].
  yf_obj_uniforms(s.h, cint(id), time, unsafeAddr u[0])
proc playing*(s: Scene3D; id, which: int): bool = yf_obj_has_animation(s.h, cint(id), cint(which)) == 1
  ## Whether model `id` has animation `which` to play.
proc env*(s: Scene3D; sky: Rgb; skyOn: bool; fog = 0'f32; fogColor: Rgb = (1'f32, 1'f32, 1'f32);
          ambient = -1'f32; shadows = true; ssao = false; bloom = 0'f32; msaa = 1) =
  ## The world: sky colour (or transparent), fog, sky light, shadows, ambient occlusion, bloom, MSAA.
  yf_env(s.h, sky.r, sky.g, sky.b, (if skyOn: 1'f32 else: 0'f32), fog, fogColor.r, fogColor.g, fogColor.b,
         ambient, cint(ord(shadows)), cint(ord(ssao)), bloom, cint(msaa))
proc post*(s: Scene3D; taa = false; dofFocus = 0'f32; dofBlur = 0'f32; ssr = false; vignette = 0'f32;
           exposure = 0'f32; contrast = 1'f32; saturation = 1'f32; toneMap = 0; fogHeight = 0'f32; fogFalloff = 1'f32) =
  ## The finish: TAA, depth of field, reflections, vignette, grading and tone mapping, height fog.
  yf_post(s.h, cint(ord(taa)), dofFocus, dofBlur, cint(ord(ssr)), vignette, exposure, contrast, saturation,
          cint(toneMap), fogHeight, fogFalloff)
proc look*(s: Scene3D; eye, target: (float32, float32, float32); fov = 0'f32; near = 0'f32; far = 0'f32) =
  ## The camera without re-framing (0 keeps fov; near/far 0: 0.1 and 1000).
  yf_camera_ex(s.h, eye[0], eye[1], eye[2], target[0], target[1], target[2], fov, near, far)
