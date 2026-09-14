## Forged meat hook and interlocking iron chain, shared by game and workshop.
## Geometry is cosmetic; the simulation still owns the hook's latch disk.

import std/math, chroma, vmath, polyworld/shapes

const
  HookEye* = vec3(-0.30, 0, -0.83)
  IronDark = rgbx(43, 45, 44, 254)
  IronBody = rgbx(75, 81, 79, 254)
  IronFace = rgbx(115, 123, 117, 254)
  IronEdge = rgbx(166, 177, 164, 254)
  HonedEdge = rgbx(205, 211, 194, 254)
  IronRust = rgbx(104, 64, 42, 254)

proc forgedFace(normal: Vec3, rust = false): ColorRGBX =
  let light = dot(normalize(normal), normalize(vec3(-0.35, 0.85, 0.4)))
  if rust: IronRust
  elif light > 0.62: IronEdge
  elif light > 0.12: IronFace
  elif light > -0.45: IronBody
  else: IronDark

proc tube(
    renderer: var ShapeRenderer, transform: Mat4,
    points: openArray[Vec3], widths: openArray[float32], depth: float32,
    closed = false, painted = rgbx(0,0,0,0), planeNormal = vec3(0,1,0),
    honed = false
) =
  ## An eight-sided forged cross section, tapered along the spine.
  const Sides = 8
  var rings = newSeq[array[Sides, Vec3]](points.len)
  for i, p in points:
    let
      prev = if i == 0: (if closed: points[^2] else: p) else: points[i-1]
      next = if i == points.high: (if closed: points[1] else: p) else: points[i+1]
      tangent = normalize(next-prev)
      across = normalize(cross(tangent, planeNormal))
    for side in 0..<Sides:
      let a = TAU.float32 * side.float32 / Sides.float32
      rings[i][side] = transform * (p + across * cos(a) * widths[i] +
        planeNormal * sin(a) * min(depth, widths[i]))
  for i in 0..<points.high:
    for side in 0..<Sides:
      let
        next = (side+1) mod Sides
        a = rings[i][side]
        b = rings[i+1][side]
        c = rings[i+1][next]
        d = rings[i][next]
        normal = cross(b-a, d-a)
      if lengthSq(normal) < 1e-10'f32: continue
      let color = if painted.a > 0: painted
        elif honed and side == 3 and i >= 3: HonedEdge
        else: forgedFace(normal, i mod 7 == 1 and side in [1,2])
      renderer.addQuad(a,b,c,d,color)
  if not closed:
    for side in 0..<Sides:
      let next = (side+1) mod Sides
      renderer.addTriangle(transform*points[0],rings[0][next],rings[0][side],IronDark)

proc addIronLink*(
    renderer: var ShapeRenderer, center, along: Vec3,
    stand: bool, size = 1'f32, paint = rgbx(0,0,0,0)
) =
  let
    axis = normalize(along)
    reference = if abs(axis.y) > 0.95'f32: vec3(1,0,0) else: vec3(0,1,0)
    side = normalize(cross(axis,reference))
    up = normalize(cross(side,axis))
    minor = if stand: up else: side
  const Sides = 8
  var
    points: array[Sides+1,Vec3]
    widths: array[Sides+1,float32]
  for i in 0..Sides:
    let a = TAU.float32*i.float32/Sides.float32
    points[i] = center + axis*cos(a)*0.46'f32*size + minor*sin(a)*0.24'f32*size
    widths[i] = 0.075'f32*size
  renderer.tube(mat4(),points,widths,0.075'f32*size,closed=true,painted=paint,
    planeNormal=normalize(cross(axis,minor)))

proc hookTransform*(center: Vec3, yaw, radius: float32, roll = 0'f32): Mat4 =
  translate(center) * rotateY(yaw) * rotateZ(roll) * scale(vec3(radius))

const
  HookTip* = vec3(0.20, 0, 0.025)
    ## Last spine point of the forged J; used to seat and test the grip.
  HeldHookVisualScale* = 0.55'f32
    ## Carried hook vs thrown latch-disk radius. Full size hid the butcher.

proc butcherHeldHookTransform*(
    hand: Mat4, facing: float32, radius: float32
): Mat4 =
  ## Horizontal C in the right fist, scaled down from the thrown head so
  ## the butcher stays readable.
  let eye = hand * vec3(0, 0.04, 0)
  translate(eye) * rotateY(facing) * scale(vec3(radius)) * translate(-HookEye)

proc butcherHeldHookEye*(hand: Mat4, facing: float32, radius: float32): Vec3 =
  butcherHeldHookTransform(hand, facing, radius) * HookEye

proc addButcherHook*(renderer: var ShapeRenderer, transform: Mat4, team: ColorRGBX) =
  ## A broad J-shaped crook with an open throat, sharpened inward tip,
  ## heavy shoulder and a welded rear eye. The team band is on the shank.
  const
    Spine = [
      vec3(-0.30,0,-0.65), vec3(-0.31,0,-0.43), vec3(-0.34,0,-0.12),
      vec3(-0.36,0,0.20), vec3(-0.32,0,0.48), vec3(-0.19,0,0.70),
      vec3(0.04,0,0.79), vec3(0.27,0,0.72), vec3(0.44,0,0.55),
      vec3(0.47,0,0.34), vec3(0.38,0,0.14), vec3(0.20,0,0.025)
    ]
    Widths = [0.105'f32,0.115,0.13,0.15,0.18,0.205,0.21,0.19,0.155,0.115,0.065,0.002]
  renderer.tube(transform,Spine,Widths,0.10,honed=true)
  const EyeSides = 16
  var
    eye: array[EyeSides+1,Vec3]
    gauge: array[EyeSides+1,float32]
  for i in 0..EyeSides:
    let angle = TAU.float32*i.float32/EyeSides.float32
    eye[i] = HookEye + vec3(cos(angle)*0.13'f32,0,sin(angle)*0.16'f32)
    gauge[i] = 0.043
  renderer.tube(transform,eye,gauge,0.043,closed=true)
  # A short wrap leaves most of the metal readable as weathered iron.
  let band = rgbx(team.r,team.g,team.b,254)
  const Band = [vec3(-0.313,0,-0.43),vec3(-0.32,0,-0.35),vec3(-0.327,0,-0.27)]
  renderer.tube(transform,Band,[0.129'f32,0.133,0.137],0.112,painted=band)

proc addHookChain*(
    renderer: var ShapeRenderer, points: openArray[Vec3],
    size = 1'f32, charged = false
) =
  ## Sample distance along the complete 3D path so links meet the eyelet
  ## and follow bends without stretching or turning into a solid rope.
  if points.len < 2 or size <= 0: return
  let spacing = 0.64'f32 * size
  var
    walked = 0'f32
    nextLink = 0'f32
    index = 0
  for segment in 0..<points.high:
    let delta = points[segment+1]-points[segment]
    let span = length(delta)
    if span < 1e-5'f32: continue
    let axis = delta/span
    while nextLink <= walked+span:
      let pos = points[segment] + axis*(nextLink-walked)
      let paint = if charged and index mod 4 == 0: rgbx(238,194,70,254)
        else: rgbx(0,0,0,0)
      renderer.addIronLink(pos,axis,(index and 1) != 0,size,paint)
      nextLink += spacing
      inc index
    walked += span
