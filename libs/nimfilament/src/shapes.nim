## The engine's built-in shapes as vertices (position, normal, uv: 8 floats each) and triangles,
## centred on the origin, 1 unit across: a scene scales them to size. Plus the matrix maths a
## scene needs to place things (column-major, like Filament).
import std/math

type Geometry* = object
  verts*: seq[float32]
  idx*: seq[uint32]

proc quad(g: var Geometry; o, u, v, n: array[3, float32]) =
  let base = uint32(g.verts.len div 8)
  for (a, b) in [(0'f32, 0'f32), (1'f32, 0'f32), (1'f32, 1'f32), (0'f32, 1'f32)]:
    for k in 0 .. 2: g.verts.add o[k] + u[k] * a + v[k] * b
    for k in 0 .. 2: g.verts.add n[k]
    g.verts.add [a, 1 - b]
  g.idx.add [base, base + 1, base + 2, base, base + 2, base + 3]

proc box*(): Geometry =
  ## A unit cube: six faces with their own normals (sharp edges).
  result.quad([-0.5'f32, -0.5, 0.5], [1'f32, 0, 0], [0'f32, 1, 0], [0'f32, 0, 1])     # front
  result.quad([0.5'f32, -0.5, -0.5], [-1'f32, 0, 0], [0'f32, 1, 0], [0'f32, 0, -1])   # back
  result.quad([0.5'f32, -0.5, 0.5], [0'f32, 0, -1], [0'f32, 1, 0], [1'f32, 0, 0])     # right
  result.quad([-0.5'f32, -0.5, -0.5], [0'f32, 0, 1], [0'f32, 1, 0], [-1'f32, 0, 0])   # left
  result.quad([-0.5'f32, 0.5, 0.5], [1'f32, 0, 0], [0'f32, 0, -1], [0'f32, 1, 0])     # top
  result.quad([-0.5'f32, -0.5, -0.5], [1'f32, 0, 0], [0'f32, 0, 1], [0'f32, -1, 0])   # bottom

proc plane*(): Geometry =
  ## A unit square lying flat (facing up): ground, water, walls once rotated.
  result.quad([-0.5'f32, 0, 0.5], [1'f32, 0, 0], [0'f32, 0, -1], [0'f32, 1, 0])

proc sphere*(rings = 24; segments = 32): Geometry =
  ## A unit-diameter sphere, smooth.
  for i in 0 .. rings:
    let phi = PI * float(i) / float(rings)
    for j in 0 .. segments:
      let th = 2 * PI * float(j) / float(segments)
      let n = [float32(sin(phi) * cos(th)), float32(cos(phi)), float32(sin(phi) * sin(th))]
      for k in 0 .. 2: result.verts.add n[k] * 0.5
      for k in 0 .. 2: result.verts.add n[k]
      result.verts.add [float32(j) / float32(segments), float32(i) / float32(rings)]
  for i in 0 ..< rings:
    for j in 0 ..< segments:
      let a = uint32(i * (segments + 1) + j)
      let b = a + uint32(segments + 1)
      result.idx.add [a, a + 1, b, a + 1, b + 1, b]

proc cylinder*(segments = 32): Geometry =
  ## A unit cylinder (diameter 1, height 1) along y, with caps.
  for j in 0 .. segments:
    let th = 2 * PI * float(j) / float(segments)
    let (c, s) = (float32(cos(th)), float32(sin(th)))
    let u = float32(j) / float32(segments)
    result.verts.add [c * 0.5'f32, -0.5, s * 0.5, c, 0, s, u, 1, c * 0.5'f32, 0.5, s * 0.5, c, 0, s, u, 0]
  for j in 0 ..< segments:
    let a = uint32(j * 2)
    result.idx.add [a, a + 1, a + 2, a + 1, a + 3, a + 2]
  for (y, ny) in [(0.5'f32, 1'f32), (-0.5'f32, -1'f32)]:
    let centre = uint32(result.verts.len div 8)
    result.verts.add [0'f32, y, 0, 0, ny, 0, 0.5, 0.5]
    for j in 0 .. segments:
      let th = 2 * PI * float(j) / float(segments)
      let (c, s) = (float32(cos(th)) * 0.5'f32, float32(sin(th)) * 0.5'f32)
      result.verts.add [c, y, s, 0, ny, 0, c + 0.5'f32, s + 0.5'f32]
    for j in 0 ..< segments:
      let a = centre + 1 + uint32(j)
      if ny > 0: result.idx.add [centre, a + 1, a] else: result.idx.add [centre, a, a + 1]

proc shape*(kind: int): Geometry =
  ## 0 box, 1 sphere, 2 plane, 3 cylinder.
  case kind
  of 1: sphere()
  of 2: plane()
  of 3: cylinder()
  else: box()

proc compose*(pos, rotDeg, size: array[3, float32]): array[16, float32] =
  ## Translation * rotation (y, then x, then z; degrees) * scale, column-major.
  let (x, y, z) = (float(rotDeg[0]).degToRad, float(rotDeg[1]).degToRad, float(rotDeg[2]).degToRad)
  let (cx, sx, cy, sy, cz, sz) = (cos(x), sin(x), cos(y), sin(y), cos(z), sin(z))
  let r = [                                                   # Ry * Rx * Rz, by column
    [cy * cz + sy * sx * sz, cx * sz, -sy * cz + cy * sx * sz],
    [-cy * sz + sy * sx * cz, cx * cz, sy * sz + cy * sx * cz],
    [sy * cx, -sx, cy * cx]]
  for c in 0 .. 2:
    for k in 0 .. 2: result[c * 4 + k] = float32(r[c][k]) * size[c]
  result[12] = pos[0]; result[13] = pos[1]; result[14] = pos[2]; result[15] = 1
