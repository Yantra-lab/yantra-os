## Native 3D scenes (S3D), included by engine.nim: a Scene3D node is a view into a Filament
## world; its Mesh, Light, Camera and Model children are that world's objects, kept in sync
## with their props (and the app's y_buf buffers) every time the view paints. Objects are not
## laid out; a change to any of them repaints the view's box.

proc linear(c: uint32): Rgb =
  ## An sRGB 0xAARRGGBB colour as linear 0..1 (Filament lights and shades in linear).
  proc ch(v: uint32): float32 = pow(float32(v and 0xFF) / 255, 2.2'f32)
  (ch(c shr 16), ch(c shr 8), ch(c))

proc composeQ(pos: array[3, float32]; q: Quat4; size: array[3, float32]): array[16, float32]
proc mul(a, b: array[16, float32]): array[16, float32]
proc quatOf(rotDeg: array[3, float32]): Quat4

proc bufVersion(e: Engine; b: int32): int

proc mapSource(e: Engine; v: View3D; spec: string; srgb: bool): string =
  ## A map prop as what the scene loads: a file's full path, or the key of pixels uploaded from
  ## one of the app's layers ("layer:N") or buffers ("pixels:BUF:W:H"), sent again when changed.
  if spec.startsWith("view:"): return spec     # a camera's texture (RT1), made by the camera node
  if spec.startsWith("layer:"):
    let id = int32(try: parseInt(spec[6 .. ^1]) except ValueError: -1)
    if id < 0: return ""
    let key = spec & "@" & $e.layerVer.getOrDefault(id, 0)
    if key notin v.uploaded:
      let (w, h) = layerSize(e.layerBase + int(id))
      if w <= 0: return ""
      let px = readLayer(e.layerBase + int(id), 0, 0, w, h)
      if px.len == 0: return ""
      discard v.scene.pixels(key, toOpenArrayByte(px, 0, px.high), w, h, srgb)
      v.uploaded.incl key
    return key
  if spec.startsWith("pixels:"):
    let p = spec.split(':')
    if p.len < 4: return ""
    let (b, w, h) = (try: (int32(parseInt(p[1])), parseInt(p[2]), parseInt(p[3])) except ValueError: (0'i32, 0, 0))
    let key = "pixels:" & $b & "@" & $e.bufVersion(b)
    if key notin v.uploaded:
      let d = e.s.bufs.getOrDefault(b)
      if w <= 0 or h <= 0 or d.len < w * h * 4: return ""
      discard v.scene.pixels(key, toOpenArrayByte(d, 0, w * h * 4 - 1), w, h, srgb)
      v.uploaded.incl key
    return key
  e.resolveAsset(spec)

proc sceneOf(e: Engine; id: int32): int32 =
  ## The Scene3D a 3D object is in (-1: none).
  var p = e.node(id).parent
  while p >= 0:
    if e.node(p).kind == K_SCENE3D: return p
    p = e.node(p).parent
  -1

proc objects3d(e: Engine; id: int32; outp: var seq[int32]) =
  ## A scene's objects, through the groups `for` and `if` make.
  for c in e.node(id).children:
    let n = e.node(c)
    if not n.alive: continue
    if n.kind == K_GROUP: e.objects3d(c, outp)
    elif n.kind in [K_MESH, K_LIGHT, K_CAMERA, K_MODEL, K_PARTICLES]: outp.add c

proc bufVersion(e: Engine; b: int32): int = e.s.bufVer.getOrDefault(b, 0)

proc syncMesh(e: Engine; v: View3D; id: int32; n: tree.Node) =
  let geo = n.iProp(P_GEOMETRY)
  let inst = if n.has(P_INSTANCES): n.iProp(P_INSTANCES) else: 0'i32
  let copies = if inst > 0: e.s.bufs.getOrDefault(inst).len div 64 else: 1
  let key = (if geo > 0: "b" & $geo & "@" & $e.bufVersion(geo) else: "s" & $n.num(P_SHAPE, 0)) & "x" & $copies
  var obj = v.objs.getOrDefault(id, -1)
  if v.keys.getOrDefault(id) != key:
    var g: Geometry
    if geo > 0:
      let d = e.s.bufs.getOrDefault(geo)
      if d.len >= 8:
        var nv, ni: uint32
        copyMem(addr nv, unsafeAddr d[0], 4)
        copyMem(addr ni, unsafeAddr d[4], 4)
        if d.len >= 8 + int(nv) * 32 + int(ni) * 4:
          g.verts.setLen(int(nv) * 8)
          g.idx.setLen(int(ni))
          if nv > 0: copyMem(addr g.verts[0], unsafeAddr d[8], int(nv) * 32)
          if ni > 0: copyMem(addr g.idx[0], unsafeAddr d[8 + int(nv) * 32], int(ni) * 4)
    else: g = shape(int(n.num(P_SHAPE, 0)))
    if copies == 0 or g.idx.len < 3:
      if obj >= 0: v.scene.remove(obj)
      v.objs.del id
      v.keys[id] = key
      return
    var lo = [1e30'f32, 1e30, 1e30]
    var hi = [-1e30'f32, -1e30, -1e30]
    for i in countup(0, g.verts.len - 8, 8):
      for k in 0 .. 2:
        lo[k] = min(lo[k], g.verts[i + k]); hi[k] = max(hi[k], g.verts[i + k])
    for k in 0 .. 2:                     # flat things (a plane) still get a little thickness to hit
      if hi[k] - lo[k] < 0.002: (lo[k] -= 0.001; hi[k] += 0.001)
    v.bounds[id] = (lo, hi)
    obj = v.scene.mesh(obj, g.verts, g.idx, copies)
    v.objs[id] = obj
    v.keys[id] = key
    v.placed.del id
    v.shaderKeys.del id                  # a new object: its shader and map go on again
    v.texKeys.del id
    v.colorsAt.del id
  if obj < 0: return
  if inst > 0 and v.placed.getOrDefault(id, -1) != e.bufVersion(inst):
    let d = e.s.bufs.getOrDefault(inst)
    var m = newSeq[float32](d.len div 4)
    if m.len > 0: copyMem(addr m[0], unsafeAddr d[0], m.len * 4)
    v.scene.instances(obj, m)
    v.placed[id] = e.bufVersion(inst)
  # its maps (T3D, M3D): files decoded once; layers and pixel buffers uploaded when they change
  let tiling = (n.num(P_TILING, 1), n.num(P_TILINGY, n.num(P_TILING, 1)))
  var keys: array[4, string]
  for slot, p in [P_TEXTURE, P_NORMALMAP, P_ORMMAP, P_EMISSIVEMAP]:
    keys[slot] = e.mapSource(v, n.sProp(p), srgb = slot in [0, 3])
  let texKey = keys[0] & "|" & keys[1] & "|" & keys[2] & "|" & keys[3] & "@" & $tiling &
               $n.num(P_NORMALSCALE, 1) & $n.num(P_ALPHAMODE, -1) & $n.num(P_ALPHACUTOFF, 0.5) & $(n.num(P_OPACITY, 1) < 1)
  if texKey != v.texKeys.getOrDefault(id, "|||@(1.0, 1.0)1.0-1.00.5false"):
    let alphaMode = if n.has(P_ALPHAMODE): int(n.num(P_ALPHAMODE, 0)) elif n.num(P_OPACITY, 1) < 1: 1 else: 0
    v.scene.surface(obj, n.num(P_NORMALSCALE, 1), alphaMode, n.num(P_ALPHACUTOFF, 0.5))
    for slot in 0 .. 3:
      if not v.scene.map(obj, MapSlot(slot), keys[slot], tiling):
        e.devNote = "map " & keys[slot] & ": " & v.scene.lastError
    v.texKeys[id] = texKey
  var shows = ""
  for k in keys:
    if k.startsWith("view:"): shows = k
  if v.showsKey.getOrDefault(id, "\x01") != shows:
    v.scene.shows(obj, shows)
    v.showsKey[id] = shows
  let colorsBuf = n.iProp(P_COLORS)
  if colorsBuf > 0 and v.colorsAt.getOrDefault(id, -1) != e.bufVersion(colorsBuf):
    v.colorsAt[id] = e.bufVersion(colorsBuf)
    let d = e.s.bufs.getOrDefault(colorsBuf)
    var bytes = newSeq[byte](d.len)
    if d.len > 0: copyMem(addr bytes[0], unsafeAddr d[0], d.len)
    v.scene.colors(obj, bytes)
  elif colorsBuf <= 0 and id in v.colorsAt:
    v.colorsAt.del id
    v.scene.colors(obj, [])
  # the app's own shader (SH1): compiled natively when its code (or blending) changes
  let alpha = n.num(P_OPACITY, 1)
  let shaderKey = n.sProp(P_SHADER) & "|none|" & n.sProp(P_VERTEXSHADER) & "|none|" & $(alpha < 1) & $n.flag(P_UNLIT)
  if shaderKey != v.shaderKeys.getOrDefault(id, "|none||none|falsefalse"):   # no shader: nothing to do
    v.shaderKeys[id] = shaderKey
    if not v.scene.shader(obj, n.sProp(P_SHADER), n.sProp(P_VERTEXSHADER), alpha < 1, n.flag(P_UNLIT)):
      e.devNote = "shader: " & v.scene.lastError
  if n.has(P_SHADER) or n.has(P_VERTEXSHADER):
    var u: array[16, float32]
    var k = 0
    for part in n.sProp(P_UNIFORMS).split(','):
      if k < 16:
        try: u[k] = float32(parseFloat(part.strip))
        except ValueError: discard
        inc k
    v.scene.uniforms(obj, float32((e.now - v.startAt) / 1000), u)
    if "time" in n.sProp(P_SHADER) or "time" in n.sProp(P_VERTEXSHADER): v.moving = true
  let s = n.num(P_SCALE, 1)
  if id in v.poses:                          # physics moves it (PH1)
    let p = v.poses[id]
    v.scene.transform(obj, composeQ(p.pos, p.rot, [n.num(P_SIZEX, 1) * s, n.num(P_SIZEY, 1) * s, n.num(P_SIZEZ, 1) * s]))
  else:
    v.scene.transform(obj, compose([n.num(P_POSX, 0), n.num(P_POSY, 0), n.num(P_POSZ, 0)],
                                   [n.num(P_ROTX, 0), n.num(P_ROTY, 0), n.num(P_ROTZ, 0)],
                                   [n.num(P_SIZEX, 1) * s, n.num(P_SIZEY, 1) * s, n.num(P_SIZEZ, 1) * s]))
  v.scene.material(obj, linear(n.col(P_COLOR, 0xFFC8C8C8'u32)), n.num(P_OPACITY, 1),
                   n.num(P_METALNESS, 0), n.num(P_ROUGHNESS, 0.6),
                   (if n.has(P_GLOW): linear(n.col(P_GLOW, 0)) else: (0'f32, 0'f32, 0'f32)))

proc syncLight(e: Engine; v: View3D; id: int32; n: tree.Node) =
  let kind = int(n.num(P_LIGHTKIND, 0))
  let pos = (n.num(P_POSX, 0), n.num(P_POSY, 10), n.num(P_POSZ, 0))
  let dir = (n.num(P_TARGETX, 0) - pos[0], n.num(P_TARGETY, 0) - pos[1], n.num(P_TARGETZ, 0) - pos[2])
  let c = n.col(P_COLOR, 0xFFFFFFFF'u32)
  let power = n.num(P_INTENSITY, if kind == 0: 100000'f32 else: 10000'f32)
  let shadows = not n.has(P_SHADOWS) or n.flag(P_SHADOWS)
  let key = $kind & $pos & $dir & $c & $power & $shadows
  if v.keys.getOrDefault(id) == key: return
  v.objs[id] = v.scene.light(v.objs.getOrDefault(id, -1), kind, linear(c), power, pos, dir, 0, shadows)
  v.keys[id] = key

proc syncModel(e: Engine; v: View3D; id: int32; n: tree.Node): bool =
  ## A glTF model in the scene (CH1): its copies (instances = placements), its clip by name or
  ## index, crossfaded when it changes, at its speed or at the time the app sets; bone offsets
  ## (turnBone) on top. True while it moves (it keeps repainting).
  let path = e.resolveAsset(n.sProp(P_SOURCE))
  let inst = if n.has(P_INSTANCES): n.iProp(P_INSTANCES) else: 0'i32
  let copies = if inst > 0: max(1, e.s.bufs.getOrDefault(inst).len div 64) else: 1
  let key = path & "#" & $copies
  if v.keys.getOrDefault(id) != key:
    if id in v.objs: v.scene.remove(v.objs[id])
    v.objs.del id
    v.keys[id] = key
    v.copiesAt.del id
    if path.len > 0:
      let obj = v.scene.model(path, copies)
      if obj >= 0: v.objs[id] = obj
      else: e.devNote = "model " & n.sProp(P_SOURCE) & ": " & v.scene.lastError
  let obj = v.objs.getOrDefault(id, -1)
  if obj < 0: return
  let s = n.num(P_SCALE, 1)
  let m = compose([n.num(P_POSX, 0), n.num(P_POSY, 0), n.num(P_POSZ, 0)],
                  [n.num(P_ROTX, 0), n.num(P_ROTY, 0), n.num(P_ROTZ, 0)], [s, s, s])
  if inst > 0:
    if v.copiesAt.getOrDefault(id, -1) != e.bufVersion(inst) or true:
      let d = e.s.bufs.getOrDefault(inst)
      for k in 0 ..< min(copies, d.len div 64):
        var im: array[16, float32]
        copyMem(addr im[0], unsafeAddr d[k * 64], 64)
        v.scene.placeCopy(obj, k, mul(m, im))
      v.copiesAt[id] = e.bufVersion(inst)
  else:
    v.scene.transform(obj, m)
  # which clip: by name, else by index (0 plays the first; -1 none)
  let want = if n.has(P_ANIMCLIP): v.scene.clip(obj, n.sProp(P_ANIMCLIP)) else: int(n.num(P_ANIMATION, 0))
  var (cur, since, prev, prevSince) = v.clips.getOrDefault(id, (-2, e.now, -1, e.now))
  if want != cur:
    if cur >= 0: (prev = cur; prevSince = since) else: prev = -1
    cur = want
    since = e.now
  v.clips[id] = (cur, since, prev, prevSince)
  let speed = n.num(P_ANIMSPEED, 1)
  let fixed = n.has(P_ANIMTIME)
  let t = if fixed: float(n.num(P_ANIMTIME, 0)) else: (e.now - since) / 1000 * speed
  let tPrev = (e.now - prevSince) / 1000 * speed
  let blend = n.num(P_BLENDTIME, 0.25)
  let alpha = if prev < 0 or blend <= 0: 1'f32 else: float32(clamp((e.now - since) / 1000 / blend, 0, 1))
  for k in 0 ..< copies:
    let off = float(k) * 0.37                  # a crowd does not walk in step
    v.scene.pose(obj, k, cur, t + off, (if alpha < 1: prev else: -1), tPrev + off, alpha)
  result = (cur >= 0 and not fixed and speed != 0) or alpha < 1

# --- particles (PT1): simulated here each frame, drawn as one instanced camera-facing quad ------

proc rnd(sp: Spray): float32 =
  sp.seed = sp.seed * 1664525'u32 + 1013904223'u32
  float32(sp.seed shr 8) / 16777216'f32

proc syncParticles(e: Engine; v: View3D; id: int32; n: tree.Node): bool =
  ## Emits (rate, bursts), moves (speed, spread, gravity) and ages this emitter's particles, then
  ## places them facing the camera, sized and coloured by age. True while any are alive.
  var sp = v.sprays.getOrDefault(id)
  if sp == nil:
    sp = Spray(lastT: e.now, seed: uint32(id) * 2654435761'u32 + 1, lastBurst: n.sProp(P_BURST))
    v.sprays[id] = sp
  let cap = clamp(int(n.num(P_MAXCOUNT, 1000)), 1, 100_000)
  let key = "particles#" & $cap & "@" & n.sProp(P_TEXTURE)
  var obj = v.objs.getOrDefault(id, -1)
  if v.keys.getOrDefault(id) != key:
    let q = plane()
    var g: Geometry                          # a quad standing up, facing +z (the camera, once turned)
    for i in countup(0, q.verts.len - 8, 8):
      g.verts.add [q.verts[i], -q.verts[i + 2], q.verts[i + 1], 0, 0, 1, q.verts[i + 6], q.verts[i + 7]]
    g.idx = q.idx
    if obj >= 0: v.scene.remove(obj)
    obj = v.scene.mesh(-1, g.verts, g.idx, cap)
    v.objs[id] = obj
    v.keys[id] = key
    discard v.scene.shader(obj, "", "", transparent = true, unlit = true)
    discard v.scene.map(obj, msColor, e.resolveAsset(n.sProp(P_TEXTURE)))
    v.colorsAt.del id
  let dt = float32(clamp((e.now - sp.lastT) / 1000, 0, 0.1))
  sp.lastT = e.now
  # emit
  let emitter = compose([n.num(P_POSX, 0), n.num(P_POSY, 0), n.num(P_POSZ, 0)],
                        [n.num(P_ROTX, 0), 0, n.num(P_ROTZ, 0)], [1'f32, 1, 1])
  let up = [emitter[4], emitter[5], emitter[6]]
  var newCount = 0
  sp.owed += n.num(P_RATE, 0) * dt
  newCount = int(sp.owed)
  sp.owed -= float32(newCount)
  if n.sProp(P_BURST) != sp.lastBurst:
    sp.lastBurst = n.sProp(P_BURST)
    let b = sp.lastBurst.split('#')[0]
    newCount += (try: parseInt(b) except ValueError: 0)
  let speed = n.num(P_SPEED, 2)
  let spread = n.num(P_SPREAD, 20).degToRad
  let life = max(0.05'f32, n.num(P_LIFETIME, 1))
  for _ in 0 ..< newCount:
    if sp.parts.len >= cap: break
    # a direction within `spread` of up: tilt by a random angle, turn by a random angle
    let tilt = sp.rnd * spread
    let turn = sp.rnd * 2 * PI.float32
    var side = [up[1] * 1 - up[2] * 0, up[2] * 0 - up[0] * 1, up[0] * 0 - up[1] * 0]   # up x (0,0,1)
    if abs(up[2]) > 0.9: side = [1'f32, 0, 0]
    let sl = max(1e-6'f32, sqrt(side[0] * side[0] + side[1] * side[1] + side[2] * side[2]))
    for k in 0 .. 2: side[k] /= sl
    let other = [up[1] * side[2] - up[2] * side[1], up[2] * side[0] - up[0] * side[2], up[0] * side[1] - up[1] * side[0]]
    var d: array[3, float32]
    for k in 0 .. 2:
      d[k] = up[k] * cos(tilt) + (side[k] * cos(turn) + other[k] * sin(turn)) * sin(tilt)
    let s = speed * (0.75'f32 + 0.5'f32 * sp.rnd)
    sp.parts.add Particle(pos: [emitter[12], emitter[13], emitter[14]], vel: [d[0] * s, d[1] * s, d[2] * s],
                          life: life * (0.8'f32 + 0.4'f32 * sp.rnd))
  # move and age
  let gy = n.num(P_GRAVITY, 0)
  var i = 0
  while i < sp.parts.len:
    sp.parts[i].age += dt
    if sp.parts[i].age >= sp.parts[i].life:
      sp.parts[i] = sp.parts[^1]
      sp.parts.setLen(sp.parts.len - 1)
      continue
    sp.parts[i].vel[1] -= gy * dt
    for k in 0 .. 2: sp.parts[i].pos[k] += sp.parts[i].vel[k] * dt
    inc i
  # place them: facing the camera, sized and coloured by age; the rest shrink to nothing
  var f = [v.eye[0] - v.target[0], v.eye[1] - v.target[1], v.eye[2] - v.target[2]]
  let fl = max(1e-6'f32, sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]))
  for k in 0 .. 2: f[k] /= fl
  var r = [f[2], 0'f32, -f[0]]                  # up(0,1,0) x f
  let rl = max(1e-6'f32, sqrt(r[0] * r[0] + r[2] * r[2]))
  for k in 0 .. 2: r[k] /= rl
  let u = [f[1] * r[2] - f[2] * r[1], f[2] * r[0] - f[0] * r[2], f[0] * r[1] - f[1] * r[0]]
  let c0 = n.col(P_COLOR, 0xFFFFFFFF'u32)
  let c1 = n.col(P_COLOREND, c0 and 0x00FFFFFF'u32)
  let (s0, s1) = (n.num(P_PARTSIZE, 0.1), n.num(P_PARTSIZEEND, n.num(P_PARTSIZE, 0.1)))
  var mats = newSeq[float32](cap * 16)
  var cols = newSeq[byte](cap * 4)
  for k, p in sp.parts:
    let a = p.age / p.life
    let sz = s0 + (s1 - s0) * a
    let o = k * 16
    for j in 0 .. 2:
      mats[o + j] = r[j] * sz; mats[o + 4 + j] = u[j] * sz; mats[o + 8 + j] = f[j] * sz
      mats[o + 12 + j] = p.pos[j]
    mats[o + 15] = 1
    proc mix(x, y: uint32; sh: int): byte = byte(float32((x shr sh) and 0xFF) * (1 - a) + float32((y shr sh) and 0xFF) * a)
    cols[k * 4] = mix(c0, c1, 16); cols[k * 4 + 1] = mix(c0, c1, 8)
    cols[k * 4 + 2] = mix(c0, c1, 0)
    cols[k * 4 + 3] = byte(float32(mix(c0, c1, 24)) * (1 - a * a))   # every particle fades out as it dies
  for k in sp.parts.len ..< cap: mats[k * 16 + 15] = 1   # the unused: zero size
  v.scene.instances(obj, mats)
  v.scene.colors(obj, cols)
  v.scene.material(obj, (1'f32, 1'f32, 1'f32), 1, 0, 1,
                   (if n.has(P_GLOW): linear(n.col(P_GLOW, 0)) else: (0'f32, 0'f32, 0'f32)))
  sp.parts.len > 0 or n.num(P_RATE, 0) > 0

proc paintScene3D(e: Engine; c: Canvas; id: int32; n: tree.Node; b: Box; r: float32) =
  e.paintSurface(c, id, n, b, 0, r)
  if b.w < 1 or b.h < 1: return               # an empty box: nothing to draw (and no zero-size GPU views)
  let pw = clamp(int(b.w * e.scale), 1, 4096)
  let ph = clamp(int(b.h * e.scale), 1, 4096)
  var v = e.views3d.getOrDefault(id)
  if v != nil and (v.scene.width != pw or v.scene.height != ph):
    v.scene.close()
    v = nil
  if v == nil:
    v = View3D(scene: newScene3D(pw, ph), startAt: e.now)
    e.views3d[id] = v
  if not v.scene.ok: return
  var playing = false
  let envKey = $n.num(P_SKY, -1) & $n.num(P_FOG, 0) & $n.num(P_FOGCOLOR, 0) & $n.num(P_AMBIENT, -1) &
               $n.num(P_SHADOWS, 1) & $n.num(P_SSAO, 0) & $n.num(P_BLOOM, 0)
  if envKey != v.envKey:
    v.envKey = envKey
    v.scene.env(linear(n.col(P_SKY, 0)), n.has(P_SKY), n.num(P_FOG, 0),
                linear(n.col(P_FOGCOLOR, 0xFFFFFFFF'u32)), n.num(P_AMBIENT, -1),
                not n.has(P_SHADOWS) or n.flag(P_SHADOWS), n.flag(P_SSAO), n.num(P_BLOOM, 0))
  let postKey = $n.flag(P_TAA) & $n.num(P_FOCUS, 0) & $n.num(P_DOFBLUR, 0) & $n.flag(P_REFLECTIONS) &
                $n.num(P_VIGNETTE, 0) & $n.num(P_EXPOSURE, 0) &
                $n.num(P_TONEMAP, 0) & $n.num(P_FOGHEIGHT, 0) & $n.num(P_FOGFALLOFF, 1)
  if postKey != v.postKey:                   # the finish (LK1)
    v.postKey = postKey
    v.scene.post(n.flag(P_TAA), n.num(P_FOCUS, 0), n.num(P_DOFBLUR, 0), n.flag(P_REFLECTIONS), n.num(P_VIGNETTE, 0),
                 n.num(P_EXPOSURE, 0), 1, 1, int(n.num(P_TONEMAP, 0)),   # saturate, contrast: FX1 over the view
                 n.num(P_FOGHEIGHT, 0), n.num(P_FOGFALLOFF, 1))
  if n.flag(P_TAA): playing = true            # TAA settles over a few frames
  var objs: seq[int32]
  e.objects3d(id, objs)
  var cam = false
  v.moving = false
  for o in objs:
    let on = e.node(o)
    case on.kind
    of K_MESH: e.syncMesh(v, o, on)
    of K_LIGHT: e.syncLight(v, o, on)
    of K_MODEL: playing = e.syncModel(v, o, on) or playing
    of K_PARTICLES: playing = e.syncParticles(v, o, on) or playing
    of K_CAMERA:
      if on.has(P_TARGET):                     # a camera into a texture (RT1), not the view's own
        let tw = int(on.num(P_WIDTH, 512))
        let th = int(on.num(P_HEIGHT, 512))
        let eye = (on.num(P_POSX, 0), on.num(P_POSY, 2), on.num(P_POSZ, 6))
        let tgt = (on.num(P_TARGETX, 0), on.num(P_TARGETY, 0), on.num(P_TARGETZ, 0))
        let key = "view:" & on.sProp(P_TARGET)
        let k2 = key & "|" & $tw & "x" & $th & $eye & $tgt & $on.num(P_FOV, 45)
        if v.rtKeys.getOrDefault(o) != k2:
          let was = v.rtKeys.getOrDefault(o).split('|')[0]
          if was.len > 0 and was != key: discard v.scene.renderTarget(was, 0, 0, eye, tgt)   # renamed
          if not v.scene.renderTarget(key, tw, th, eye, tgt, on.num(P_FOV, 45)): e.devNote = "camera: " & v.scene.lastError
          v.rtKeys[o] = k2
          v.showsKey.clear()                     # layer bits may have moved: meshes re-apply
        playing = true                           # what it films may move: keep it fresh
      elif not cam:
        cam = true
        let key = $(on.num(P_POSX, 0), on.num(P_POSY, 2), on.num(P_POSZ, 6), on.num(P_TARGETX, 0),
                    on.num(P_TARGETY, 0), on.num(P_TARGETZ, 0), on.num(P_FOV, 45), pw, ph)
        v.eye = [on.num(P_POSX, 0), on.num(P_POSY, 2), on.num(P_POSZ, 6)]
        v.target = [on.num(P_TARGETX, 0), on.num(P_TARGETY, 0), on.num(P_TARGETZ, 0)]
        v.fov = on.num(P_FOV, 45)
        if key != v.camKey:
          v.camKey = key
          v.scene.look((on.num(P_POSX, 0), on.num(P_POSY, 2), on.num(P_POSZ, 6)),
                       (on.num(P_TARGETX, 0), on.num(P_TARGETY, 0), on.num(P_TARGETZ, 0)), on.num(P_FOV, 45))
    else: discard
    if on.kind != K_CAMERA and o in v.objs: v.scene.visible(v.objs[o], on.visible)
  v.aspect = float32(pw) / float32(ph)
  if not cam: (v.eye = [0'f32, 2, 6]; v.target = [0'f32, 0, 0]; v.fov = 45)
  if not cam and v.camKey != "default":
    v.camKey = "default"
    v.scene.look((0'f32, 2'f32, 6'f32), (0'f32, 0'f32, 0'f32), 45)
  var gone: seq[int32]
  for o in v.objs.keys:
    if o notin objs: gone.add o
  for o in gone:
    v.scene.remove(v.objs[o])
    v.objs.del o
    v.keys.del o
    v.placed.del o
    v.sprays.del o
    v.showsKey.del o
    v.shaderKeys.del o
    v.texKeys.del o
  if v.scene.render((e.now - v.startAt) / 1000, v.px):
    c.drawPixels(addr v.px[0], pw, ph, b.x, b.y, b.w, b.h, r, 2)
  if playing or v.moving: (e.animating = true; e.animIds.add id)   # animations, shaders on time

# --- picking (T3D): which object a click hits, by a ray from the camera ----------------------

proc mul(a, b: array[16, float32]): array[16, float32] =
  for c in 0 .. 3:
    for r in 0 .. 3:
      var s = 0'f32
      for k in 0 .. 3: s += a[k * 4 + r] * b[c * 4 + k]
      result[c * 4 + r] = s

proc inverseAffine(m: array[16, float32]): array[16, float32] =
  ## The inverse of a column-major affine matrix (rotation, scale, translation).
  let (a, b, c) = (m[0], m[4], m[8])
  let (d, e, f) = (m[1], m[5], m[9])
  let (g, h, i) = (m[2], m[6], m[10])
  let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  if abs(det) < 1e-12: return
  let inv = 1 / det
  let r = [[(e * i - f * h) * inv, (c * h - b * i) * inv, (b * f - c * e) * inv],
           [(f * g - d * i) * inv, (a * i - c * g) * inv, (c * d - a * f) * inv],
           [(d * h - e * g) * inv, (b * g - a * h) * inv, (a * e - b * d) * inv]]
  for row in 0 .. 2:
    for col in 0 .. 2: result[col * 4 + row] = r[row][col]
  for row in 0 .. 2:
    result[12 + row] = -(r[row][0] * m[12] + r[row][1] * m[13] + r[row][2] * m[14])
  result[15] = 1

proc rayBox(inv: array[16, float32]; o, d: array[3, float32]; lo, hi: array[3, float32]): float32 =
  ## Where (in the ray's own t) a world ray first enters a local box; -1 if it misses.
  var lo2, d2: array[3, float32]
  for r in 0 .. 2:
    lo2[r] = inv[r] * o[0] + inv[4 + r] * o[1] + inv[8 + r] * o[2] + inv[12 + r]
    d2[r] = inv[r] * d[0] + inv[4 + r] * d[1] + inv[8 + r] * d[2]
  var tmin = -1e30'f32
  var tmax = 1e30'f32
  for k in 0 .. 2:
    if abs(d2[k]) < 1e-9:
      if lo2[k] < lo[k] or lo2[k] > hi[k]: return -1
    else:
      var t1 = (lo[k] - lo2[k]) / d2[k]
      var t2 = (hi[k] - lo2[k]) / d2[k]
      if t1 > t2: swap(t1, t2)
      tmin = max(tmin, t1); tmax = min(tmax, t2)
      if tmin > tmax: return -1
  if tmax < 0: -1'f32 elif tmin >= 0: tmin else: 0'f32

proc pick3d(e: Engine; x, y: float32): bool =
  ## A click (x, y: window px) inside a 3D view: the nearest mesh with an onClick under it gets
  ## Click, with the point it hit (and the copy, if instanced) readable during it. True if so.
  for sc, v in e.views3d:
    if sc notin e.boxes or not e.s.valid(sc): continue
    let b = e.boxes[sc]
    let py = y + e.scrollY
    if x < b.x or x >= b.x + b.w or py < b.y or py >= b.y + b.h: continue
    let nx = (x - b.x) / b.w * 2 - 1
    let ny = 1 - (py - b.y) / b.h * 2
    var f = [v.target[0] - v.eye[0], v.target[1] - v.eye[1], v.target[2] - v.eye[2]]
    let fl = sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2])
    if fl < 1e-6: return false
    for k in 0 .. 2: f[k] /= fl
    var r = [f[1] * 0 - f[2] * 1, f[2] * 0 - f[0] * 0, f[0] * 1 - f[1] * 0]   # f x up(0,1,0)
    let rl = max(1e-6'f32, sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]))
    for k in 0 .. 2: r[k] /= rl
    let u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
    let th = tan(float32(v.fov).degToRad / 2)
    var d: array[3, float32]
    for k in 0 .. 2: d[k] = f[k] + r[k] * nx * th * v.aspect + u[k] * ny * th
    var best = 1e30'f32
    var hitNode = -1'i32
    var hitCopy = -1'i32
    var objs: seq[int32]
    e.objects3d(sc, objs)
    for o in objs:
      let n = e.node(o)
      if n.kind != K_MESH or not n.visible or o notin v.bounds: continue
      if e.s.handlerFor(o, E_CLICK) < 0: continue
      let s = n.num(P_SCALE, 1)
      let m = compose([n.num(P_POSX, 0), n.num(P_POSY, 0), n.num(P_POSZ, 0)],
                      [n.num(P_ROTX, 0), n.num(P_ROTY, 0), n.num(P_ROTZ, 0)],
                      [n.num(P_SIZEX, 1) * s, n.num(P_SIZEY, 1) * s, n.num(P_SIZEZ, 1) * s])
      let (lo, hi) = v.bounds[o]
      let inst = if n.has(P_INSTANCES): n.iProp(P_INSTANCES) else: 0'i32
      if inst > 0:
        let data = e.s.bufs.getOrDefault(inst)
        for c in 0 ..< data.len div 64:
          var im: array[16, float32]
          copyMem(addr im[0], unsafeAddr data[c * 64], 64)
          let t = rayBox(inverseAffine(mul(m, im)), v.eye, d, lo, hi)
          if t >= 0 and t < best: (best = t; hitNode = o; hitCopy = int32(c))
      else:
        let t = rayBox(inverseAffine(m), v.eye, d, lo, hi)
        if t >= 0 and t < best: (best = t; hitNode = o; hitCopy = -1)
    if hitNode < 0: return false
    for k in 0 .. 2: e.s.pickAt[k] = v.eye[k] + d[k] * best
    e.s.pickInstance = hitCopy
    e.fire(hitNode, E_CLICK)
    return true
  false

# --- physics (PH1): Jolt bodies for meshes with a `body`, stepped on the engine's clock -------

proc quatOf(rotDeg: array[3, float32]): Quat4 =
  ## The rotation `compose` makes (y, then x, then z; degrees) as a quaternion.
  let (hx, hy, hz) = (float(rotDeg[0]).degToRad / 2, float(rotDeg[1]).degToRad / 2, float(rotDeg[2]).degToRad / 2)
  let (qy, qx, qz) = ([0.0, sin(hy), 0.0, cos(hy)], [sin(hx), 0.0, 0.0, cos(hx)], [0.0, 0.0, sin(hz), cos(hz)])
  proc qm(a, b: array[4, float]): array[4, float] =
    [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
     a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
     a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
     a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]
  let q = qm(qm(qy, qx), qz)
  [float32(q[0]), float32(q[1]), float32(q[2]), float32(q[3])]

proc composeQ(pos: array[3, float32]; q: Quat4; size: array[3, float32]): array[16, float32] =
  ## Translation * rotation (a quaternion) * scale, column-major.
  let (x, y, z, w) = (q[0], q[1], q[2], q[3])
  let r = [[1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)],
           [2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)],
           [2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]]
  for c in 0 .. 2:
    for k in 0 .. 2: result[c * 4 + k] = r[c][k] * size[c]
  result[12] = pos[0]; result[13] = pos[1]; result[14] = pos[2]; result[15] = 1

proc sizeOf3(n: tree.Node): array[3, float32] =
  let s = n.num(P_SCALE, 1)
  [n.num(P_SIZEX, 1) * s, n.num(P_SIZEY, 1) * s, n.num(P_SIZEZ, 1) * s]

proc propPoseOf(n: tree.Node): BodyPose =
  BodyPose(pos: [n.num(P_POSX, 0), n.num(P_POSY, 0), n.num(P_POSZ, 0)],
       rot: quatOf([n.num(P_ROTX, 0), n.num(P_ROTY, 0), n.num(P_ROTZ, 0)]))

proc syncBodies(e: Engine; sc: int32; v: View3D; dt: float32) =
  ## Bodies for the scene's meshes that have one (made again when what they are made of changes),
  ## moved when the app moves them, gone with them.
  var objs: seq[int32]
  e.objects3d(sc, objs)
  var seen: seq[int32]
  for o in objs:
    let n = e.node(o)
    if n.kind != K_MESH or not n.has(P_BODY) or n.num(P_BODY, 0) <= 0: continue
    seen.add o
    if pointer(v.phys) == nil:
      v.phys = newPhysicsWorld(-n.num(P_GRAVITY, 9.81))
      v.lastStep = e.now
    let motion = int(n.num(P_BODY, 0))
    let geo = n.iProp(P_GEOMETRY)
    let shape = if geo > 0: (if motion == 1: 5 else: 6) else: int(n.num(P_SHAPE, 0))
    let size = sizeOf3(n)
    let key = $shape & $size & $motion & $e.bufVersion(geo) & $n.num(P_MASS, 0) & $n.num(P_FRICTION, 0.5) &
              $n.num(P_BOUNCE, 0) & $n.num(P_DAMPING, 0.05)
    let pp = propPoseOf(n)
    let ppKey = $pp.pos & $pp.rot
    if v.bodies.getOrDefault(o, (BodyId(0), ""))[1] != key:
      if o in v.bodies: v.phys.remove(v.bodies[o][0])
      var verts: seq[float32]
      var idx: seq[uint32]
      if geo > 0:
        let d = e.s.bufs.getOrDefault(geo)
        if d.len >= 8:
          var nv, ni: uint32
          copyMem(addr nv, unsafeAddr d[0], 4)
          copyMem(addr ni, unsafeAddr d[4], 4)
          if d.len >= 8 + int(nv) * 32 + int(ni) * 4:
            verts.setLen(int(nv) * 8); idx.setLen(int(ni))
            if nv > 0: copyMem(addr verts[0], unsafeAddr d[8], int(nv) * 32)
            if ni > 0: copyMem(addr idx[0], unsafeAddr d[8 + int(nv) * 32], int(ni) * 4)
      let start = v.poses.getOrDefault(o, pp)
      let b = v.phys.addBody(shape, size, start, motion, n.num(P_MASS, 0), n.num(P_FRICTION, 0.5),
                             n.num(P_BOUNCE, 0), n.num(P_DAMPING, 0.05), verts, 8, idx)
      v.bodies[o] = (b, key)
      v.propPose[o] = ppKey
    elif v.propPose.getOrDefault(o) != ppKey:        # the app moved it: put it there
      v.propPose[o] = ppKey
      v.phys.setPose(v.bodies[o][0], pp, if motion == 3: dt else: 0'f32)
      v.poses.del o
  var gone: seq[int32]
  for o in v.bodies.keys:
    if o notin seen: gone.add o
  for o in gone:
    v.phys.remove(v.bodies[o][0])
    v.bodies.del o; v.poses.del o; v.propPose.del o

proc modelTarget(e: Engine; name: string): (View3D, int) =
  for sc, v in e.views3d:
    for o, obj in v.objs:
      if e.node(o).kind == K_MODEL and e.node(o).sProp(P_NAME) == name: return (v, obj)
  (nil, -1)

proc wireBones(e: Engine) =
  ## The app's y_bone calls: turn a named model's bone (every copy), let it go, say where it is.
  let ee = e
  e.s.boneOp = proc (op: int32; model, bone: string; a: array[3, float32]): float32 =
    let (v, obj) = ee.modelTarget(model)
    if v == nil: return 0
    case op
    of 0:
      discard v.scene.bone(obj, -1, bone, quatOf(a))
      for sc, vv in ee.views3d:
        if vv == v: ee.damageNode(sc)
      ee.dirty = true
    of 1: discard v.scene.bone(obj, -1, bone, [0'f32, 0, 0, 0])
    of 2, 3, 4:
      let (ok, p) = v.scene.boneWorld(obj, 0, bone)
      if ok: return p[op - 2]
    else: discard
    0'f32

proc stepPhysics(e: Engine) =
  ## Steps every 3D view's physics to the engine's clock; moving bodies repaint their view.
  for sc, v in e.views3d:
    if not e.s.valid(sc): continue
    let dt = if pointer(v.phys) == nil: 1'f32 / 60 else: float32(clamp((e.now - v.lastStep) / 1000, 0, 1 / 15))
    e.syncBodies(sc, v, dt)
    if pointer(v.phys) == nil or dt <= 0: continue
    v.lastStep = e.now
    v.phys.step(dt, max(1, int(dt * 60 + 0.5)))
    var moved = false
    for o, (b, _) in v.bodies:
      if e.node(o).num(P_BODY, 0) == 1: continue
      let p = v.phys.pose(b)
      let was = v.poses.getOrDefault(o, BodyPose(rot: [9'f32, 9, 9, 9]))
      if p != was: (v.poses[o] = p; moved = true)
    if moved:
      e.damageNode(sc)
      e.dirty = true

proc physicsTarget(e: Engine; name: string): (View3D, int32) =
  for sc, v in e.views3d:
    if pointer(v.phys) == nil: continue
    for o in v.bodies.keys:
      if e.node(o).sProp(P_NAME) == name: return (v, o)
  (nil, -1'i32)

proc wirePhysics(e: Engine) =
  ## The app's y_phys calls, answered from its scenes' physics.
  let ee = e
  e.s.physOp = proc (op: int32; name: string; a: array[6, float32]): float32 =
    if op == 4:                                        # raycast: from a[0..2] along a[3..5]
      for sc, v in ee.views3d:
        if pointer(v.phys) == nil: continue
        let (hit, b, frac) = v.phys.raycast([a[0], a[1], a[2]], [a[3], a[4], a[5]])
        ee.s.physHit = ""
        if not hit: return -1
        for o, (bb, _) in v.bodies:
          if uint32(bb) == uint32(b): ee.s.physHit = ee.node(o).sProp(P_NAME)
        return frac * sqrt(a[3] * a[3] + a[4] * a[4] + a[5] * a[5])
      return -1
    let (v, o) = ee.physicsTarget(name)
    if v == nil: return (if op == 6: -1'f32 else: 0'f32)   # not (yet) a body: no rope
    let b = v.bodies[o][0]
    case op
    of 0: v.phys.impulse(b, [a[0], a[1], a[2]])
    of 1: v.phys.setLinearVelocity(b, Vec3(x: a[0], y: a[1], z: a[2]))
    of 2: return v.phys.pose(b).pos[clamp(int(a[0]), 0, 2)]
    of 3:
      let vel = v.phys.bodyVelocity(b)
      return [vel.x, vel.y, vel.z][clamp(int(a[0]), 0, 2)]
    of 6:
      let r = v.phys.rope(b, BodyId(0), [a[0], a[1], a[2]], a[3])
      if r >= 0: v.ropes.add r
      return float32(r)
    of 7: v.phys.unconstrain(int(a[0]))
    of 8: return v.phys.pose(b).rot[clamp(int(a[0]), 0, 3)]
    of 9: v.phys.setAngular(b, [a[0], a[1], a[2]])
    of 10: v.phys.force(b, [a[0], a[1], a[2]])
    else: discard
    0'f32
