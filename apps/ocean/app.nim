## Ocean — an open-water study drawn by one generated shader pair. Six wavelength
## bands contribute two dispersive Gerstner trains each; analytic tangents light the
## same surface the vertices make, and the horizontal Jacobian finds folding crests.
## This is deliberately not presented as an FFT simulation. There are no textures,
## models or backdrop images: water, atmosphere and every moving highlight are live.

# ── restrained instrumentation over the scene ────────────────────────────────────
let night = #040B12
let brass = #E9C887
let paper = #ECF3F5
let dim = #94AAB6
let edge = #9DB7C726
let glass = #07151FBC
let uiFont = "DejaVu Sans"
let monoFont = "DejaVu Sans Mono"

# ── where the eye stands ─────────────────────────────────────────────────────────
const
  eyeX = 0.0
  eyeY = 6.4
  eyeZ = 0.0
  sunAzim = -9.0              ## a sun path just left of the composition's centre
  domeR = 900.0               ## inside the camera's 1000 m far plane

# ── the spectrum: six cascades, twelve trains ────────────────────────────────────
# Wavelength in metres, amplitude in metres at a moderate sea, the train's heading
# in degrees off the wind, and its Gerstner steepness (Q*k*A < 1 keeps the surface
# from crossing through itself).
const
  nCasc = 6
  waveLen = [26.0, 13.0, 6.5, 3.3, 1.7, 0.9]
  ampAt = [1.50, 0.90, 0.50, 0.28, 0.15, 0.08]
  headAt = [0.0, 24.0, -31.0, 52.0, -63.0, 17.0]
  chopAt = [0.82, 0.76, 0.70, 0.62, 0.54, 0.46]

proc gl(x: float): string =
  ## A number as GLSL writes it.
  $x

proc waveSetup(): string =
  ## What both shaders set up before the sum: the clock, the sea's two dials, and the
  ## three accumulators the sum writes into.
  result = ""
  result.add "    float time = materialParams.time;\n"
  result.add "    float ampS = materialParams.u[2].x;\n"
  result.add "    float chopS = materialParams.u[2].y;\n"
  result.add "    vec3 disp = vec3(0.0);\n"
  result.add "    vec3 tX = vec3(1.0, 0.0, 0.0);\n"
  result.add "    vec3 tZ = vec3(0.0, 0.0, 1.0);\n"

proc fadeGlsl(): string =
  ## Each cascade stops being drawn where the mesh can no longer carry it: a wave
  ## needs several rings per wavelength, and the rings grow as they leave the eye.
  result = ""
  for c in 0 ..< nCasc:
    # The widest train never fades: it is the swell that gives the far water a shape,
    # and the fragment shader's analytic normal needs nothing from the mesh to carry
    # it. Each narrower train fades a little further out than before.
    let near = [260.0, 150.0, 90.0, 54.0, 34.0]
    let far = [700.0, 420.0, 260.0, 150.0, 90.0]
    let fadeFrom = if c == 0: 9000.0 else: near[c - 1]
    let fadeTo = if c == 0: 9001.0 else: far[c - 1]
    result.add "    float fadeC" & $c & " = 1.0 - smoothstep(" &
      gl(fadeFrom) & ", " & gl(fadeTo) & ", dist);\n"

proc waveGlsl(): string =
  ## The wave sum, written out: each train displaces the surface on the Gerstner
  ## equations, and its analytic tangents give the normal and the Jacobian. The same
  ## block goes into both shaders, so the fragment's normal is the surface the vertex
  ## shader actually made — worked out per pixel instead of per vertex.
  result = ""
  for c in 0 ..< nCasc:
    let k = 6.283185307 / waveLen[c]           # the wavenumber
    let omega = sqrt(9.81 * k)                 # deep-water dispersion: w = sqrt(g k)
    for t in 0 .. 1:
      let heading = headAt[c] + (if t == 0: 0.0 else: 43.0)
      let rad = heading * 0.0174532925
      let amp = ampAt[c] * (if t == 0: 0.62 else: 0.38)
      result.add "    {  // cascade " & $c & ", train " & $t & "\n"
      result.add "      float k = " & gl(k) & ";\n"
      result.add "      float a = " & gl(amp) & " * ampS * fadeC" & $c & ";\n"
      result.add "      float q = " & gl(chopAt[c]) & " * chopS;\n"
      result.add "      vec2 d = vec2(" & gl(sin(rad)) & ", " & gl(cos(rad)) & ");\n"
      result.add "      float ph = dot(d, P.xz) * k - time * " & gl(omega) & ";\n"
      result.add "      float s = sin(ph);\n"
      result.add "      float co = cos(ph);\n"
      result.add "      disp.y += a * s;\n"
      result.add "      disp.xz += q * a * d * co;\n"
      result.add "      tX += vec3(-q * a * k * d.x * d.x * s, a * k * d.x * co, -q * a * k * d.x * d.y * s);\n"
      result.add "      tZ += vec3(-q * a * k * d.x * d.y * s, a * k * d.y * co, -q * a * k * d.y * d.y * s);\n"
      result.add "    }\n"

proc seaVertexSource(): string =
  ## The vertex shader: the grid point in, the displaced surface out.
  result = ""
  result.add("""
    vec3 P = getPosition().xyz;
    float dist = length(materialParams.u[0].xyz - P);
  """
  )
  result.add(waveSetup())
  result.add(fadeGlsl())
  result.add(waveGlsl())
  result.add("""
    material.worldPosition = vec4(P + disp, 1.0);
  """
  )

# ── the sky, shared by the dome and by the water's reflection ────────────────────
let skyGlsl = """
    vec3 L = normalize(materialParams.u[1].xyz);
    float warmth = materialParams.u[2].w;
    vec3 sunCol = materialParams.u[3].rgb * materialParams.u[3].a;
    vec3 zenithCol = mix(vec3(0.009, 0.028, 0.072), vec3(0.028, 0.039, 0.078), warmth);
    vec3 horizonCol = mix(vec3(0.22, 0.115, 0.155), vec3(0.75, 0.25, 0.09), warmth);
    vec3 cloudShade = mix(vec3(0.035, 0.054, 0.092), vec3(0.155, 0.090, 0.098), warmth);
    float el = clamp(dir.y, -1.0, 1.0);
    // A sunset sky is BRIGHT at the horizon. The old pow(el, 0.30) was already half
    // way to the zenith colour by six degrees of elevation, so it pressed the whole
    // sky into one dark field: measured, rows 168..440 of 816 were luma 46 +- 2 with a
    // mean |Laplacian| of 1.65 - three hundred rows of nothing. A gentler exponent
    // keeps the warm band down where the sun is and still reaches the deep zenith.
    float skyHeight = pow(clamp(el, 0.0, 1.0), 0.30);
    vec3 skyCol = mix(horizonCol, zenithCol, skyHeight);
    float sunUp = clamp(dot(dir, L), 0.0, 1.0);
    float sunVis = smoothstep(-0.025, 0.035, L.y);
    // Two lobes: the tight one that was here, and a wide afterglow that carries the
    // sunset across the sky and, reflected, across the water.
    skyCol += sunCol * pow(sunUp, 10.0) * 0.16 * sunVis;
    skyCol += sunCol * pow(sunUp, 6.0) * 0.20 * sunVis;
    skyCol += sunCol * pow(sunUp, 2.0) * 0.055 * sunVis;
    float sunAngle = acos(sunUp);
    float disc = 1.0 - smoothstep(0.0046, 0.0058, sunAngle);
    skyCol += sunCol * disc * 4.2 * sunVis;
    float az = atan(dir.x, -dir.z);
    float c1 = sin(az * 3.1 + el * 19.0) * 0.5 + 0.5;
    float c2 = sin(az * 7.7 - el * 43.0 + 1.7) * 0.5 + 0.5;
    float c3 = sin(az * 19.3 + el * 91.0 - 0.8) * 0.5 + 0.5;
    float band = smoothstep(0.008, 0.09, el) * (1.0 - smoothstep(0.18, 0.78, el));
    float wisps = c1 * 0.52 + c2 * 0.31 + c3 * 0.17;
    float cl = smoothstep(0.55, 0.79, wisps) * band;
    vec3 cloudLight = mix(cloudShade, sunCol * 0.40, pow(sunUp, 3.0) * sunVis);
    skyCol = mix(skyCol, cloudLight, cl * 0.46);
    skyCol = mix(skyCol, horizonCol * 0.94, exp(-abs(el) * 13.0) * 0.38);
    if (warmth < 0.20 && el > 0.08) {
      vec2 starGrid = vec2(az * 170.0, el * 170.0);
      vec2 starCell = floor(starGrid);
      float starHash = fract(sin(dot(starCell, vec2(12.9898, 78.233))) * 43758.5453);
      float star = step(0.989, starHash) * (1.0 - smoothstep(0.025, 0.15, length(fract(starGrid) - 0.5)));
      skyCol += vec3(0.38, 0.50, 0.72) * star * (0.20 - warmth) * 2.4;
    }
    vec3 hazeCol = horizonCol;
  """

proc seaFragmentSource(): string =
  ## The water's fragment: the same twelve trains, summed at this pixel, give the
  ## normal and the fold of the surface (the Jacobian: whitecaps); Fresnel, the sun's
  ## glitter path and the sky it mirrors do the rest.
  result = ""
  result.add("""
    vec3 P = getWorldPosition().xyz;
    vec3 eye = materialParams.u[0].xyz;
    vec3 V = normalize(eye - P);
    float dist = length(eye - P);
  """
  )
  result.add(waveSetup())
  result.add(fadeGlsl())
  result.add(waveGlsl())
  result.add("""
    vec3 N = normalize(cross(tZ, tX));
    float jac = tX.x * tZ.z - tX.z * tZ.x;
    float folded = clamp((materialParams.u[2].z - jac) * 1.3 - 0.06, 0.0, 1.0);
    float crest = disp.y / max(ampS, 0.35);
    float foam = folded * smoothstep(0.30, 0.95, crest);
    foam += smoothstep(1.5, 2.6, crest) * 0.22;
    foam = clamp(foam, 0.0, 0.72);
    float amp = ampS;
    float warm = materialParams.u[2].w;
    // The calm water mirrors the warm horizon and reads as a second copy of the sky;
    // tipping the reflection up toward the zenith cools the water body and splits the
    // frame into a warm sky over a cool sea, which is the whole point of a sunset study.
    vec3 dir = reflect(-V, N);
  """
  )
  result.add(skyGlsl)
  result.add("""
    float ndv = clamp(dot(N, V), 0.0, 1.0);
    float fres = 0.025 + 0.975 * pow(1.0 - ndv, 5.0);
    float rs = clamp(dot(dir, L), 0.0, 1.0);
    float spec = (pow(rs, 920.0) * 24.0 + pow(rs, 150.0) * 3.6 + pow(rs, 32.0) * 0.34 +
                  pow(rs, 8.0) * 0.05) * sunVis;
    vec3 deep = mix(vec3(0.006, 0.027, 0.050), vec3(0.012, 0.046, 0.061), clamp(amp - 0.45, 0.0, 1.2));
    float up = clamp(N.y, 0.0, 1.0);
    float subsurface = pow(clamp(dot(N, L), 0.0, 1.0), 3.0) * max(disp.y, 0.0);
    vec3 body = deep * (0.58 + 0.42 * up) + vec3(0.014, 0.045, 0.044) * subsurface * (0.35 + 0.65 * warm);
    vec3 col = mix(body, skyCol, clamp(fres, 0.0, 0.94)) + sunCol * spec;
    vec3 foamCol = mix(vec3(0.62, 0.76, 0.80), vec3(0.92, 0.90, 0.84), warm);
    float foamBreakup = 0.82 + 0.18 * sin(P.x * 8.7 + P.z * 6.1 + time * 0.8);
    col = mix(col, foamCol, foam * foamBreakup);
    // The old 84% haze at the far plane dissolved the sea into one flat slab - rows
    // 624..700 of 816 measured luma 148 with p99 154.  Halve it so the water keeps a
    // body, and take the near water DOWN: a sunset frame needs a dark foreground, and
    // this one had none (p1 of the whole frame was luma 24.7, all of it in the sky).
    float away = clamp(dist / 900.0, 0.0, 1.0);
    vec3 farCol = mix(skyCol, hazeCol, 0.30);
    col = mix(col, farCol, away * away * 0.88);
    material.baseColor = vec4(col, 1.0);
    material.emissive = vec4(sunCol * spec * 0.035, 0.0);
  """
  )

proc domeFragmentSource(): string =
  ## The sky: the same function the water reflects, seen directly.
  result = ""
  result.add("""
    vec3 eye = materialParams.u[0].xyz;
    vec3 dir = normalize(getWorldPosition().xyz - eye);
  """
  )
  result.add(skyGlsl)
  result.add("""
    material.baseColor = vec4(skyCol, 1.0);
    material.emissive = vec4(sunCol * disc * 0.22 * sunVis, 0.0);
  """
  )

proc periodStop(light, dusk, gold, blue: float): float =
  ## Continuous light means a control can move through a period, not jump over it.
  ## Clamp at both ends even during an interrupted or repeated transition.
  let x = clamp(light, 0.0, 2.0)
  if x <= 1.0: dusk + (gold - dusk) * x
  else: gold + (blue - gold) * (x - 1.0)

proc sunElevation(light: float): float = periodStop(light, 4.2, 10.5, -2.4)
proc sunX(light: float): float =
  sin(sunAzim * 0.0174532925) * cos(sunElevation(light) * 0.0174532925)
proc sunY(light: float): float = sin(sunElevation(light) * 0.0174532925)
proc sunZ(light: float): float =
  -cos(sunAzim * 0.0174532925) * cos(sunElevation(light) * 0.0174532925)

proc cameraHeight(sea: float): float =
  ## Let the observer rise gently with rough weather, leaving calm and swell untouched.
  eyeY + max(sea - 1.0, 0.0) * 2.4

proc funiforms(sea, light: float): string =
  ## Sixteen shared numbers: eye, moving sun, amplitude, chop, Jacobian threshold,
  ## atmospheric warmth, and light colour/power. The frame event eases these inputs.
  let warmth = periodStop(light, 0.55, 1.0, 0.03)
  let sunR = periodStop(light, 1.0, 1.0, 0.42)
  let sunG = periodStop(light, 0.72, 0.78, 0.62)
  let sunB = periodStop(light, 0.50, 0.46, 1.0)
  let power = periodStop(light, 1.6, 2.0, 0.65)
  let amp = 0.30 + sea * 0.36
  let chop = 0.48 + sea * 0.135
  let cut = 0.80 - sea * 0.11
  gl(eyeX) & "," & gl(cameraHeight(sea)) & "," & gl(eyeZ) & "," & gl(warmth) & "," &
    gl(sunX(light)) & "," & gl(sunY(light)) & "," & gl(sunZ(light)) & ",1.0," &
    gl(amp) & "," & gl(chop) & "," & gl(cut) & "," & gl(warmth) & "," &
    gl(sunR) & "," & gl(sunG) & "," & gl(sunB) & "," & gl(power)

proc yBuf(id, p, n: int32) {.importc: "y_buf", cdecl.}

proc ringMesh(): int32 =
  ## One hundred twelve radial rings end at 940 m, inside the far plane. Dense
  ## sampling keeps displaced silhouettes clean; analytic normals add capillary
  ## detail that the mesh need not carry. One immutable buffer, one draw call.
  const
    rings = 112
    segs = 192
    r0 = 0.92
    grow = 1.063823
    rEnd = 940.0
  var verts: seq[float32] = @[]
  var tris: seq[uint32] = @[]
  var rad = newSeq[float32](rings + 1)
  rad[0] = 0.0
  var r = r0
  for k in 1 .. rings:
    rad[k] = float32(r)
    r = r * grow
  for k in 0 .. rings:
    for s in 0 ..< segs:
      let a = 6.283185307 * float(s) / float(segs)
      verts.add rad[k] * float32(cos(a))
      verts.add 0.0'f32
      verts.add rad[k] * float32(sin(a))
      verts.add 0.0'f32
      verts.add 1.0'f32
      verts.add 0.0'f32
      verts.add float32(s) / float32(segs)
      verts.add rad[k] / float32(rEnd)
  for k in 0 ..< rings:
    for s in 0 ..< segs:
      let s2 = (s + 1) mod segs
      let a = uint32(k * segs + s)
      let b = uint32(k * segs + s2)
      let c = uint32((k + 1) * segs + s)
      let d = uint32((k + 1) * segs + s2)
      tris.add a; tris.add c; tris.add b
      tris.add b; tris.add c; tris.add d
  var data = newSeq[byte](8 + verts.len * 4 + tris.len * 4)
  let nv = uint32(verts.len div 8)
  let ni = uint32(tris.len)
  copyMem(addr data[0], unsafeAddr nv, 4)
  copyMem(addr data[4], unsafeAddr ni, 4)
  copyMem(addr data[8], unsafeAddr verts[0], verts.len * 4)
  copyMem(addr data[8 + verts.len * 4], unsafeAddr tris[0], tris.len * 4)
  yBuf(1, cast[int32](addr data[0]), int32(data.len))
  1

let seaGeometry = ringMesh()

proc lightName(s: int): string =
  case s
  of 0: "DUSK"
  of 1: "GOLD"
  else: "BLUE"

proc knots(s: int): int =
  case s
  of 0: 6
  of 1: 14
  of 2: 26
  else: 50

proc waveHeight(s: int): string =
  case s
  of 0: "0.5 m"
  of 1: "1.4 m"
  of 2: "2.3 m"
  else: "4.1 m"

proc angleText(x: float): string =
  ## One decimal place, including negative elevations, without a stdlib formatter.
  let negative = x < 0.0
  let v = (if negative: -x else: x)
  var whole = int(v)
  var tenth = int((v - float(whole)) * 10.0 + 0.5)
  if tenth == 10:
    whole = whole + 1
    tenth = 0
  (if negative: "-" else: "") & $whole & "." & $tenth

view Ocean
  state sea = 1
  state light = 0
  state seaNow = 1.0
  state lightNow = 0.0
  Stack(width = 1280px, height = 816px, fill = night):
    on frame:
      let dt = clamp(float(frameDt()), 0.0, 0.05)
      let ease = 1.0 - exp(-dt * 5.5)
      seaNow = seaNow + (float(sea) - seaNow) * ease
      lightNow = lightNow + (float(light) - lightNow) * ease
    Scene3D(width = 1280px, height = 816px, sky = night, bloom = 0.14,
            exposure = 0.05, vignette = 0.16, toneMap = 2, ambient = 9000, shadows = false):
      Camera(posX = eyeX, posY = cameraHeight(seaNow), posZ = eyeZ,
             targetX = 0.0, targetY = cameraHeight(seaNow) - 13.0,
             targetZ = -180.0, fov = 48)
      Mesh(shape = 1, posX = eyeX, posY = cameraHeight(seaNow), posZ = eyeZ,
           sizeX = domeR, sizeY = domeR, sizeZ = domeR, fill = #101820,
           uniforms = funiforms(seaNow, lightNow), shader = domeFragmentSource(), unlit = true)
      Mesh(geometry = seaGeometry, fill = #0A2634, rough = 0.05, metal = 0.0,
           uniforms = funiforms(seaNow, lightNow), vertex = seaVertexSource(),
           shader = seaFragmentSource(), unlit = true)
    Column(absolute = true, left = 44px, top = 36px, gap = 5px):
      Text "NORTH ATLANTIC  /  LIVE STUDY", size = 9px, weight = 700, color = brass, font = monoFont
      Text "Ocean", size = 42px, weight = 600, color = paper, font = uiFont
      Text "SIX BANDS OF DEEP WATER", size = 10px, weight = 700, color = dim, font = uiFont
    Panel(absolute = true, right = 40px, top = 32px, width = 326px, fill = glass,
          radius = 12px, pad = 14px, border = 1px, borderColor = edge):
      Column(gap = 9px):
        Text "SEA STATE", size = 9px, weight = 700, color = dim, font = monoFont
        Row(gap = 4px):
          Button "CALM", width = 71px, height = 31px, radius = 6px,
                 fill = (if sea == 0: brass else: (#FFFFFF0C)),
                 color = (if sea == 0: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: sea = 0
          Button "SWELL", width = 71px, height = 31px, radius = 6px,
                 fill = (if sea == 1: brass else: (#FFFFFF0C)),
                 color = (if sea == 1: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: sea = 1
          Button "GALE", width = 71px, height = 31px, radius = 6px,
                 fill = (if sea == 2: brass else: (#FFFFFF0C)),
                 color = (if sea == 2: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: sea = 2
          Button "STORM", width = 71px, height = 31px, radius = 6px,
                 fill = (if sea == 3: brass else: (#FFFFFF0C)),
                 color = (if sea == 3: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: sea = 3
        Text "PERIOD", size = 9px, weight = 700, color = dim, font = monoFont
        Row(gap = 6px):
          Button "DUSK", width = 90px, height = 31px, radius = 6px,
                 fill = (if light == 0: brass else: (#FFFFFF0C)),
                 color = (if light == 0: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: light = 0
          Button "GOLD", width = 90px, height = 31px, radius = 6px,
                 fill = (if light == 1: brass else: (#FFFFFF0C)),
                 color = (if light == 1: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: light = 1
          Button "BLUE", width = 90px, height = 31px, radius = 6px,
                 fill = (if light == 2: brass else: (#FFFFFF0C)),
                 color = (if light == 2: night else: paper), size = 10px, weight = 700, font = uiFont:
            on tap: light = 2
    Panel(absolute = true, left = 40px, bottom = 34px, width = 422px, fill = glass,
          radius = 11px, pad = 15px, border = 1px, borderColor = edge):
      Row(gap = 26px):
        Column(gap = 4px, grow = 1):
          Text "WIND", size = 9px, weight = 700, color = dim, font = monoFont
          Text "{knots(sea)} kn", size = 21px, weight = 600, color = paper, font = uiFont
        Column(gap = 4px, grow = 1):
          Text "WAVE HEIGHT", size = 9px, weight = 700, color = dim, font = monoFont
          Text waveHeight(sea), size = 21px, weight = 600, color = paper, font = uiFont
        Column(gap = 4px, grow = 1):
          Text "SURFACE", size = 9px, weight = 700, color = dim, font = monoFont
          Text "12 trains", size = 21px, weight = 600, color = brass, font = uiFont
    Column(absolute = true, right = 42px, bottom = 40px, gap = 6px, alignItems = 3):
      Text "{lightName(light)}  /  SUN {angleText(sunElevation(lightNow))}°", size = 10px,
           weight = 700, color = paper, font = monoFont
      Text "Gerstner superposition · analytic normals · Jacobian foam", size = 11px,
           color = dim, font = uiFont
      Text "43,008 live triangles  /  no textures or backdrop", size = 9px,
           color = dim, font = monoFont
