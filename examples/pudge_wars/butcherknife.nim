## Socketed, bevelled butcher weapons. Shared by the game and char_viewer;
## purely cosmetic, with no changes to reach, hit timing, or damage.
import std/math, chroma, vmath, polyworld/shapes

type
  ButcherKnife* = enum
    SlaughterCleaver, HookedSkinner, BoneSplitter
  KnifeRow* = tuple[y,left,right: float32]

const
  KnifeNames* = ["Slaughter cleaver", "Hooked skinner", "Bone splitter"]
  DefaultButcherKnife* = SlaughterCleaver
  Steel = rgbx(109, 119, 117, 254)
  SteelDark = rgbx(48, 55, 56, 254)
  SteelLight = rgbx(137, 151, 147, 254)
  Edge = rgbx(221, 230, 213, 254)
  Leather = rgbx(62, 32, 25, 254)
  Brass = rgbx(164, 119, 62, 254)

proc knifeDescription*(knife: ButcherKnife): string =
  case knife
  of SlaughterCleaver: "Heavy slab / hanging hole / honed edge"
  of HookedSkinner: "Swept belly / hooked gutting point"
  of BoneSplitter: "Broad blade / jagged spine / iron collar"

proc butcherKnifeTransform*(hand: Mat4): Mat4 =
  ## The supplied L_Hand socket is at the wrist. Undo its bind rotation,
  ## Seat the handle in the fist with the blade projecting forward and
  ## the sharpened +X edge BELOW the spine, not the broad face below it.
  ## Keeping the full animated matrix makes the blade follow wrist roll.
  hand * rotateX(PI.float32) * rotateZ(23.617'f32*PI.float32/180) *
    rotateY(1.488'f32*PI.float32/180) * translate(vec3(0, -0.045, 0.025)) *
    rotateX(100'f32*PI.float32/180) * rotateZ(-15'f32*PI.float32/180) *
    rotateY(-PI.float32/2) *
    scale(vec3(0.145))

proc metal(normal: Vec3): ColorRGBX =
  let light = dot(normalize(normal), normalize(vec3(-0.4, 0.8, 0.6)))
  if light > 0.35: SteelLight
  elif light > -0.35: Steel
  else: rgbx(78,89,86,254)

proc plate(renderer: var ShapeRenderer, transform: Mat4,
           a,b,c,d: Vec3, paint: ColorRGBX) =
  renderer.addQuad(transform*a, transform*b, transform*c, transform*d, paint)

proc handleSection(renderer: var ShapeRenderer, transform: Mat4,
                   bottom, top, radius: float32, paint: ColorRGBX) =
  ## Octagonal leather handle, solid end caps and faceted steel furniture.
  const Sides = 8
  for i in 0..<Sides:
    let
      a = TAU.float32 * i.float32 / Sides.float32
      b = TAU.float32 * (i+1).float32 / Sides.float32
      p = vec3(cos(a)*radius, bottom, sin(a)*radius*0.72'f32)
      q = vec3(cos(b)*radius, bottom, sin(b)*radius*0.72'f32)
      r = vec3(q.x, top, q.z)
      s = vec3(p.x, top, p.z)
      shade = if i in [1,2,3]: paint else:
        rgbx(uint8(paint.r.int*3 div 4), uint8(paint.g.int*3 div 4),
          uint8(paint.b.int*3 div 4), 254)
    renderer.plate(transform,p,q,r,s,shade)
    renderer.addTriangle(transform*vec3(0,bottom,0),transform*q,transform*p,shade)
    renderer.addTriangle(transform*vec3(0,top,0),transform*s,transform*r,shade)

proc rivet(renderer: var ShapeRenderer, transform: Mat4, x,y,z,r: float32) =
  for i in 0..<8:
    let a = TAU.float32*i.float32/8
    let b = TAU.float32*(i+1).float32/8
    renderer.addTriangle(transform*vec3(x,y,z+(if z > 0: 0.018'f32 else: -0.018'f32)),
      transform*vec3(x+cos(a)*r,y+sin(a)*r,z),
      transform*vec3(x+cos(b)*r,y+sin(b)*r,z),Brass)

proc holePanel(renderer: var ShapeRenderer, transform: Mat4,
               left,right,bottom,top,z: float32, paint: ColorRGBX) =
  ## True through-hole, not a black decal: fan a rectangle to a circular
  ## opening and line its bore. Used on the cleaver's constant-width panel.
  let center = vec2(left+0.23'f32, (bottom+top)*0.5'f32)
  const Radius = 0.115'f32
  proc rim(angle: float32): tuple[outer,inner: Vec3] =
    let dir = vec2(cos(angle),sin(angle))
    let dx = if dir.x > 0: right-center.x else: left-center.x
    let dy = if dir.y > 0: top-center.y else: bottom-center.y
    let reach = min(abs(dx/max(abs(dir.x),1e-6'f32)),
      abs(dy/max(abs(dir.y),1e-6'f32)))
    (vec3(center+dir*reach,z),vec3(center+dir*Radius,z))
  # Include the four exact corner rays as well as the round bore samples;
  # otherwise a ray fan would cut tiny triangles off the panel corners.
  var angles: seq[float32]
  for i in 0..<24: angles.add TAU.float32*i.float32/24
  for p in [vec2(left,bottom),vec2(right,bottom),vec2(right,top),vec2(left,top)]:
    var a = arctan2(p.y-center.y,p.x-center.x)
    if a < 0: a += TAU.float32
    angles.add a
  # A tiny insertion sort keeps this geometry helper dependency-light.
  for i in 1..<angles.len:
    var j = i
    while j > 0 and angles[j] < angles[j-1]:
      swap(angles[j],angles[j-1])
      dec j
  for i in 0..<angles.len:
    let a = rim(angles[i])
    let b = rim(angles[(i+1) mod angles.len])
    renderer.plate(transform,a.outer,b.outer,b.inner,a.inner,paint)
    if z > 0:
      renderer.plate(transform,a.inner,b.inner,
        vec3(b.inner.x,b.inner.y,-z),vec3(a.inner.x,a.inner.y,-z),SteelDark)

proc knifeProfile*(knife: ButcherKnife): seq[KnifeRow] =
  ## Rows describe the silhouette (height, spine, cutting edge). Uneven
  ## spine rows give the splitter real notches, not painted-on serrations.
  case knife
  of SlaughterCleaver:
    result = @[(0.39'f32,-0.16'f32,0.17'f32), (0.70'f32,-0.34'f32,0.87'f32),
      (1.85'f32,-0.34'f32,0.91'f32), (2.45'f32,-0.34'f32,0.91'f32),
      (2.61'f32,-0.24'f32,0.76'f32)]
  of HookedSkinner:
    result = @[(0.39'f32,-0.12'f32,0.13'f32), (0.71'f32,-0.18'f32,0.42'f32),
      (1.40'f32,-0.17'f32,0.61'f32), (1.96'f32,-0.05'f32,0.68'f32),
      (2.30'f32,0.09'f32,0.68'f32), (2.63'f32,0.35'f32,0.59'f32),
      (2.86'f32,0.61'f32,0.63'f32)]
  of BoneSplitter:
    result = @[(0.39'f32,-0.18'f32,0.18'f32), (0.76'f32,-0.39'f32,0.75'f32),
      (1.12'f32,-0.40'f32,0.94'f32), (1.24'f32,-0.18'f32,0.98'f32),
      (1.37'f32,-0.41'f32,1.02'f32), (1.67'f32,-0.43'f32,1.10'f32),
      (1.79'f32,-0.20'f32,1.13'f32), (1.93'f32,-0.44'f32,1.16'f32),
      (2.48'f32,-0.46'f32,1.17'f32), (2.77'f32,-0.27'f32,0.89'f32),
      (2.89'f32,0.06'f32,0.48'f32)]

proc addButcherKnife*(renderer: var ShapeRenderer, transform: Mat4,
                      knife: ButcherKnife, team: ColorRGBX) =
  let rows = knifeProfile(knife)
  const Depth = 0.072'f32
  for side in [-1'f32,1'f32]:
    let
      z = Depth*side
      origin = transform*vec3(0,0,0)
      paint = metal(transform*vec3(0,0,side)-origin)
    for i in 0..<rows.high:
      let
        a = rows[i]
        b = rows[i+1]
        al = a.left+min(0.045'f32,(a.right-a.left)*0.15'f32)
        bl = b.left+min(0.045'f32,(b.right-b.left)*0.15'f32)
        ar = a.right-min(0.14'f32,(a.right-a.left)*0.3'f32)
        br = b.right-min(0.14'f32,(b.right-b.left)*0.3'f32)
      if knife == SlaughterCleaver and i == 2:
        renderer.holePanel(transform,al,ar,a.y,b.y,z,paint)
      else:
        # Broad, irregular forge facets contrast with the polished bevel.
        # Tessellate, rather than overlay: avoids depth fighting on the
        # workshop's 16-bit depth buffers, even with the camera zoomed out.
        let darker = rgbx(uint8(paint.r.int*4 div 5),uint8(paint.g.int*4 div 5),
          uint8(paint.b.int*4 div 5),254)
        let midA = al+(ar-al)*0.28'f32
        let midB = bl+(br-bl)*0.44'f32
        renderer.plate(transform,vec3(al,a.y,z),vec3(midA,a.y,z),
          vec3(midB,b.y,z),vec3(bl,b.y,z),darker)
        renderer.plate(transform,vec3(midA,a.y,z),vec3(ar,a.y,z),
          vec3(br,b.y,z),vec3(midB,b.y,z),paint)
      renderer.plate(transform,vec3(a.left,a.y,z*0.42'f32),vec3(al,a.y,z),
        vec3(bl,b.y,z),vec3(b.left,b.y,z*0.42'f32),SteelDark)
      renderer.plate(transform,vec3(ar,a.y,z),vec3(a.right,a.y,0),
        vec3(b.right,b.y,0),vec3(br,b.y,z),Edge)
      if side > 0:
        renderer.plate(transform,vec3(a.left,a.y,-z*0.42'f32),
          vec3(a.left,a.y,z*0.42'f32),vec3(b.left,b.y,z*0.42'f32),
          vec3(b.left,b.y,-z*0.42'f32),SteelDark)
    # Fine hammer scoring and dark oxidation near the spine. Both sides
    # are detailed so wrist turns do not reveal an unfinished back face.
    let detailZ = z+side*0.008'f32
    for i,y in [0.92'f32,1.23,1.29,1.57,1.76]:
      let x = if i mod 2 == 0: 0.08'f32 else: 0.22'f32
      let length = if i mod 2 == 0: 0.21'f32 else: -0.14'f32
      renderer.addTriangle(transform*vec3(x,y,detailZ),
        transform*vec3(x+length,y+0.07'f32,detailZ),
        transform*vec3(x+length*0.7'f32,y+0.083'f32,detailZ),SteelDark)
    # A few angular, reddish oxidation patches on the unfinished steel.
    for i,y in [0.84'f32,1.47,1.69]:
      let x = if i == 0: -0.10'f32 else: 0.015'f32
      renderer.addTriangle(transform*vec3(x,y,detailZ),
        transform*vec3(x+0.09'f32,y+0.15'f32,detailZ),
        transform*vec3(x-0.025'f32,y+0.19'f32,detailZ),rgbx(94,61,42,254))
    renderer.rivet(transform,0.015,0.67,detailZ,0.047)
  for row in [rows[0],rows[^1]]:
    let
      left = row.left+min(0.045'f32,(row.right-row.left)*0.15'f32)
      right = row.right-min(0.14'f32,(row.right-row.left)*0.3'f32)
      rim = [vec3(row.left,row.y,-Depth*0.42'f32),vec3(left,row.y,-Depth),
        vec3(right,row.y,-Depth),vec3(row.right,row.y,0),
        vec3(right,row.y,Depth),vec3(left,row.y,Depth),
        vec3(row.left,row.y,Depth*0.42'f32)]
      center = transform*vec3((row.left+row.right)*0.5'f32,row.y,0)
    for i in 0..<rim.len:
      renderer.addTriangle(center,transform*rim[i],transform*rim[(i+1) mod rim.len],SteelLight)
  renderer.handleSection(transform,-0.48,0.40,0.135,Leather)
  # Wrap seams and team-coloured binding at the pommel.
  for i in 0..<6:
    let y = -0.39'f32+i.float32*0.115'f32
    renderer.handleSection(transform,y,y+0.026'f32,0.142,rgbx(102,65,42,254))
  renderer.handleSection(transform,-0.48,-0.35,0.155,rgbx(team.r,team.g,team.b,254))
  renderer.handleSection(transform,-0.55,-0.48,0.17,Brass)
  renderer.handleSection(transform,0.34,0.48,0.22,
    if knife == BoneSplitter: SteelLight else: Brass)
