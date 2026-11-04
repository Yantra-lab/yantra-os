## Native 3D data (S3D): what a scene needs beyond props — bulk buffers (an app's own mesh
## vertices, thousands of placements) handed to the engine in one copy each, and the matrix
## maths to place things. The words (`scene3d`, `box`, `light`, …) are in the DSL.
##
##   let city = newBuffer()
##   var at: seq[Mat4]
##   for b in buildings: at.add place(b.x, b.h / 2, b.z, sx = b.w, sy = b.h, sz = b.d)
##   city.setInstances(at)
##   scene3d(sky = 0x87CEEB):
##     box(instances = city, fill = 0x808890)      # one mesh, every building
import std/math

type
  Buffer* = distinct int32
  Mat4* = array[16, float32]   ## column-major 4x4, like glTF

var bufSeq: int32

proc newBuffer*(): Buffer =
  ## A new buffer id; fill it with `setGeometry` / `setInstances` / `setData` (again any time).
  inc bufSeq
  Buffer(bufSeq)

converter toInt32*(b: Buffer): int32 = int32(b)   ## `geometry = buf`, `instances = buf`

proc c_memcpy(dest, src: pointer; n: csize_t): pointer {.importc: "memcpy", header: "<string.h>", discardable.}
template copyData(dest, src: pointer; n: int) =
  c_memcpy(dest, src, csize_t(n))

when sizeof(pointer) == 4:
  proc yBuf(id, p, n: int32) {.importc: "y_buf", cdecl.}
  proc setData*(b: Buffer; data: pointer; bytes: int) =
    ## Raw bytes: one copy into the engine.
    yBuf(int32(b), (if bytes > 0: cast[int32](data) else: 0'i32), int32(bytes))
else:
  var hostBufs*: seq[(int32, string)]            ## native test builds: what was handed over
  proc setData*(b: Buffer; data: pointer; bytes: int) =
    var s = newString(bytes)
    if bytes > 0: copyData(addr s[0], data, bytes)
    hostBufs.add (int32(b), s)

proc setInstances*(b: Buffer; placements: openArray[Mat4]) =
  ## One copy of a mesh per matrix (a mesh with `instances = b`).
  if placements.len == 0: b.setData(nil, 0)
  else: b.setData(unsafeAddr placements[0], placements.len * sizeof(Mat4))

proc setGeometry*(b: Buffer; verts: openArray[float32]; tris: openArray[uint32]) =
  ## An app's own mesh (a mesh with `geometry = b`): position, normal and uv per vertex (8
  ## floats), three vertex indices per triangle.
  let nv = uint32(verts.len div 8)
  let ni = uint32(tris.len)
  var data = newSeq[byte](8 + verts.len * 4 + tris.len * 4)
  copyData(addr data[0], unsafeAddr nv, 4)
  copyData(addr data[4], unsafeAddr ni, 4)
  if verts.len > 0: copyData(addr data[8], unsafeAddr verts[0], verts.len * 4)
  if tris.len > 0: copyData(addr data[8 + verts.len * 4], unsafeAddr tris[0], tris.len * 4)
  b.setData(addr data[0], data.len)

proc place*(x, y, z: float32; rotX = 0'f32; rotY = 0'f32; rotZ = 0'f32;
            sx = 1'f32; sy = 1'f32; sz = 1'f32): Mat4 =
  ## Where one copy sits: position, rotation in degrees (y, then x, then z), size.
  let (a, b, c) = (float(rotX).degToRad, float(rotY).degToRad, float(rotZ).degToRad)
  let (cx, sx0, cy, sy0, cz, sz0) = (cos(a), sin(a), cos(b), sin(b), cos(c), sin(c))
  let r = [
    [cy * cz + sy0 * sx0 * sz0, cx * sz0, -sy0 * cz + cy * sx0 * sz0],
    [-cy * sz0 + sy0 * sx0 * cz, cx * cz, sy0 * sz0 + cy * sx0 * cz],
    [sy0 * cx, -sx0, cy * cx]]
  let size = [sx, sy, sz]
  for col in 0 .. 2:
    for k in 0 .. 2: result[col * 4 + k] = float32(r[col][k]) * size[col]
  result[12] = x; result[13] = y; result[14] = z; result[15] = 1
