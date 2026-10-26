## Lightweight Polyworld rope geometry. Visuals never change the latch disk.
import std/math, chroma, vmath, polyworld/shapes

const
  LassoEye* = vec3(0,0,-0.95)
  RopeLight = rgbx(208,173,112,254)
  RopeBody = rgbx(147,108,62,254)
  RopeShade = rgbx(72,48,29,254)

proc ropeTube(renderer: var ShapeRenderer, points: openArray[Vec3], radius: float32,
    charged = false) =
  const Sides = 6
  for i in 0..<points.len-1:
    let delta = points[i+1]-points[i]
    if lengthSq(delta) < 0.000001'f32: continue
    let
      axis = normalize(delta)
      reference = if abs(axis.y)>0.95'f32: vec3(1,0,0) else: vec3(0,1,0)
      side = normalize(cross(axis,reference))
      up = normalize(cross(side,axis))
    for j in 0..<Sides:
      let
        a = TAU.float32*j.float32/Sides.float32
        b = TAU.float32*(j+1).float32/Sides.float32
        da = (side*cos(a)+up*sin(a))*radius
        db = (side*cos(b)+up*sin(b))*radius
        color = if charged: rgbx(250,210,104,254)
          elif sin((a+b)*0.5'f32)>0.35: RopeLight
          elif sin((a+b)*0.5'f32)< -0.35: RopeShade
          else: RopeBody
      renderer.addQuad(points[i]+da,points[i+1]+da,points[i+1]+db,points[i]+db,color)

proc addLassoRope*(renderer: var ShapeRenderer, points: openArray[Vec3], charged=false) =
  ## Continuous six-sided hemp rope, cheaper than the former iron-link chain.
  renderer.ropeTube(points,0.075'f32,charged)

proc collarWedge(renderer: var ShapeRenderer, transform: Mat4,
    a, b, tip: Vec3) =
  ## Faceted iron collar with a bright ridge and a dark underside.
  let
    up = vec3(0, 0.055'f32, 0)
    edge = rgbx(203,210,205,254)
    face = rgbx(83,96,100,254)
    back = rgbx(36,43,46,254)
    aa = transform * a
    bb = transform * b
    tt = transform * tip
    ridge = transform * ((a+b)*0.5'f32 + up)
  renderer.addTriangle(aa, ridge, tt, face)
  renderer.addTriangle(ridge, bb, tt, edge)
  renderer.addTriangle(bb, aa, tt, back)
  renderer.addTriangle(aa, bb, ridge, back)

proc addLassoLoop*(renderer: var ShapeRenderer, transform: Mat4, team: ColorRGBX) =
  # An open tapered noose with iron ferrules and a heavy honda collar.
  # Everything stays inside the original unit latch disk.
  proc rim(angle: float32): Vec3 =
    let taper = 0.82'f32 + 0.18'f32 * cos(angle)
    vec3(sin(angle)*0.80'f32*taper, 0, cos(angle)*0.90'f32)
  var points: array[33,Vec3]
  for i in 0..32:
    points[i] = transform * rim(TAU.float32*i.float32/32'f32)
  let gauge = length(transform*vec3(0.065,0,0)-transform*vec3(0,0,0))
  renderer.ropeTube(points,gauge)
  for i in 0..<6:
    let
      angle = -2.30'f32 + i.float32 * 0.92'f32
      center = rim(angle)
    # Rounded iron ferrules reinforce the rope without teeth inside the loop.
    renderer.addLine(transform*(center+vec3(0,-0.055,0)),
      transform*(center+vec3(0,0.055,0)),rgbx(54,63,66,254),gauge*1.45'f32)
  # Thick, angular honda jaw at the trailing end, wrapped in team leather.
  renderer.collarWedge(transform, vec3(-0.20,0,-0.77), vec3(0.20,0,-0.77),
    vec3(0,0,-0.98))
  renderer.addLine(transform*vec3(-0.16,0.06,-0.84),
    transform*vec3(0.16,0.06,-0.84),team,gauge*1.15'f32)
  renderer.addLine(transform*vec3(-0.08,0.09,-0.86),
    transform*vec3(0.08,0.09,-0.86),rgbx(210,162,79,254),gauge*0.5'f32)

proc addRopeCoil*(renderer: var ShapeRenderer, hand: Mat4, facing: float32) =
  let transform = translate(hand*vec3(0,0,0)) * rotateY(facing)
  for turn in 0..2:
    var points: array[21,Vec3]
    for i in 0..20:
      let a = TAU.float32*i.float32/20'f32
      points[i]=transform*vec3(cos(a)*0.48'f32,sin(a)*0.62'f32-0.38'f32,turn.float32*0.09'f32)
    renderer.ropeTube(points,0.055'f32)

proc addSwingingLasso*(renderer: var ShapeRenderer, hand: Vec3,
    facing, phase, radius, windup: float32, team: ColorRGBX) =
  ## A tilted overhead loop rolls around the wrist. Its honda follows the
  ## orbit, connected to the actual skinned hand by a short slack segment.
  let
    angle = facing + phase
    tilt = 0.10'f32 + windup * 0.35'f32
    orbit = rotateY(angle)
    center = hand + orbit * vec3(0, 0.85'f32, radius * 0.72'f32)
    transform = translate(center) * orbit * rotateX(tilt) * scale(vec3(radius))
    knot = transform * LassoEye
    mid = (hand + knot) * 0.5'f32 - vec3(0, 0.12'f32, 0)
  renderer.addLassoRope([hand, mid, knot])
  renderer.addLassoLoop(transform, team)
