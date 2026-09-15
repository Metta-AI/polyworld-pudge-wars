## Window, terrain, butchers, hook ribbons, and HUD for Pudge Wars.

import
  std/[math, os, strutils, tables, times],
  chroma, opengl, pixie, silky, vmath, windy,
  audio, butcherhook, butcherknife, content, director, fog, maps, sim, game, human, keybinds, netclient, netsim,
  netpredict, replays, ui,
  polyworld/[
    actioncam, characters, chrome, common, gameuis, particles, particleshaders,
    pathing, player, profiles, quadterrain, rtscameras, shadows, shapes,
    tapes, terrainsurfaces, viewers, worldbars
  , visions]

when not defined(emscripten):
  # The embedded lobby server cannot run in a browser build; a wasm
  # client is always a follower.
  import hosting

const
  AtlasPath = DataRoot & "/themes/pw.atlas.png"
  AppIconPath = "examples/pudge_wars/macos/AppIcon.png"
  WestHook = rgbx(220, 72, 64, 230)
  EastHook = rgbx(72, 148, 230, 230)
  GrabGlow = rgbx(168, 72, 230, 90)
  SpawnShieldDisk = rgbx(90, 210, 255, 95)
    ## Ice disk under a spawn-protected butcher. Saturated so it still
    ## reads at the far RTS zoom.
  SpawnShieldCore = rgbx(230, 250, 255, 165)
  SpawnShieldRim = rgbx(170, 236, 255, 220)
  SpawnShieldCap = rgbx(210, 246, 255, 130)
  SpawnShieldMote = rgbx(255, 255, 255, 200)
  SpawnShieldName = rgbx(170, 236, 255, 240)
  BlinkPuff = rgbx(72, 210, 255, 110)
    ## Cyan leave-behind disk; MagicBurst's opening color, oversized so
    ## it still reads at the baked 155 play-camera zoom.
  BlinkPuffCore = rgbx(200, 96, 255, 150)
    ## Magenta core matching the MagicBurst fade.
  BlinkResidueSeconds = 0.55
    ## Ground glow + silhouette linger after the hashed vanish tick.
  RotFill = rgbx(16, 38, 18, 90)
    ## Dark swamp stain inside the blight.
  RotSick = rgbx(28, 62, 26, 90)
    ## Foot glow on anyone standing in Rot.
  RotCore = rgbx(22, 48, 20, 125)
    ## Tight blight pooled under the caster.
  RotSpore = rgbx(34, 64, 28, 110)
    ## Drifting motes along the blight rim.
  LightningFlash = rgbx(255, 236, 80, 200)
  LightningRing = rgbx(255, 214, 90, 140)
  FireTrailFill = rgbx(255, 86, 18, 120)
  FireTrailCore = rgbx(255, 196, 48, 165)
  FireTrailEmber = rgbx(255, 140, 32, 130)
  DefaultCameraDistance = 75.0'f32
    ## Starts at the closest shipped zoom (75–155). Clamped live by
    ## zoomMinDistance / zoomMaxDistance.
  DebugFillAlpha = 88'u8
  DebugLineHalf = 0.16'f32
  DebugTileLabelStep = 16
  CollisionColor = rgbx(240, 218, 128, 150)
  HookDiskColor = rgbx(236, 92, 70, 140)
  SpawnPadColor = rgbx(96, 220, 110, 160)
  PlayBoundsColor = rgbx(255, 214, 120, 230)
  MidlineColor = rgbx(255, 140, 48, 230)
  BankEdgeColor = rgbx(236, 236, 232, 210)
  BroilerBar = rgbx(42, 32, 28, 230)
  BroilerGlow = rgbx(255, 110, 36, 70)
    ## Iron slats over the fire pit; a broiler, not a river.
  ButcherBarLift = 6.8'f32
  ButcherBarWidth = 3.0'f32
  NamePlateLift = 7.55'f32
    ## Just over the HP bar. No backing plate — small type only.
  NamePlateW = 280.0'f32
  NamePlateH = 16.0'f32
  NamePlateShadow = rgbx(8, 10, 14, 180)
  NamePlateText = rgbx(236, 228, 204, 210)
  NamePlateEyes = rgbx(255, 214, 120, 230)
  GrabGlowRadius = 1.4'f32
  PalisadeWood = rgbx(138, 94, 54, 255)
  PalisadeBand = rgbx(78, 68, 58, 255)
  PalisadeTop = rgbx(162, 116, 70, 255)
  PalisadeBarLift = 2.15'f32
  PalisadeBarWidth = 1.15'f32
  MeatHookRadius = BaseHookRadius.float32 / WorldScale.float32
    ## Visual head matches the sim latch disk (2.75 tiles at rank 0).
    ## Big Hook and radius upgrades scale this 1:1.
  RuneCoreRadius = RuneRadius.float32 / WorldScale.float32
    ## Same 1-tile body the sim grabs with; the tablet sits on this.
  RuneBobRate = 1.15'f32
    ## Slow hover, WC3 river-rune cadence — not a bouncing gem.
  RuneSpinRate = 0.42'f32
    ## Slow yaw so the carved glyph stays readable at RTS distance.
  RuneHover = 0.82'f32
  RuneBobAmp = 0.22'f32
  RuneTabletSides = 8
  RuneTabletThick = 0.34'f32
  RuneStone = rgbx(78, 72, 64, 255)
  RuneStoneDark = rgbx(42, 38, 34, 255)
  RuneStoneRim = rgbx(112, 104, 92, 255)

type
  GraphicsError = object of CatchableError
  SeekCheckpoint = object
    tick: int
    world: World
    replayActionIndex: int
    hashCheck: ReplayHashCheck
  FloatingText = object
    ## One rising world-anchored combat number.
    text: string
    color: ColorRGBX
    world: Vec3
    born: float64
  BlinkResidue = object
    ## Client-only leave-behind: glow + fading butcher at blink origin.
    origin: Vec3
    worldOrigin: WorldPoint
    facing: float32
    team: Team
    slot: int
    born: float64

proc renderPoint(position: WorldPoint): Vec3 =
  vec3(
    position.x.float32 / WorldScale.float32,
    position.y.float32 / WorldScale.float32,
    position.z.float32 / WorldScale.float32
  )

proc worldFromRender(point: Vec3): WorldPoint =
  WorldPoint(
    x: int32(point.x * WorldScale.float32),
    z: int32(point.z * WorldScale.float32)
  )

proc renderFacing(value: Heading): float32 =
  arctan2(value.x.float32, value.z.float32)

proc liftPoint(position: Vec3, extra = 0.7'f32): Vec3 =
  result = position
  result.y = surfaceHeightNear(position.x, position.z, position.y) + extra

proc tileOrigin(x, z: int): Vec3 =
  vec3(float32(x) - HalfGrid, 0, float32(z) - HalfGrid)

proc tileCenterRender(x, z: int): Vec3 =
  tileOrigin(x, z) + vec3(0.5'f32, 0, 0.5'f32)

proc addAxisBox(
    renderer: var ShapeRenderer,
    center: Vec3,
    hx, hy, hz: float32,
    color: ColorRGBX
) =
  ## Axis-aligned box. `hy` is half-height; the box is centered.
  let
    x0 = center.x - hx
    x1 = center.x + hx
    y0 = center.y - hy
    y1 = center.y + hy
    z0 = center.z - hz
    z1 = center.z + hz
  renderer.addQuad(
    vec3(x0, y1, z0), vec3(x1, y1, z0), vec3(x1, y1, z1), vec3(x0, y1, z1), color
  )
  renderer.addQuad(
    vec3(x0, y0, z1), vec3(x1, y0, z1), vec3(x1, y0, z0), vec3(x0, y0, z0), color
  )
  renderer.addQuad(
    vec3(x1, y0, z0), vec3(x1, y0, z1), vec3(x1, y1, z1), vec3(x1, y1, z0), color
  )
  renderer.addQuad(
    vec3(x0, y0, z1), vec3(x0, y0, z0), vec3(x0, y1, z0), vec3(x0, y1, z1), color
  )
  renderer.addQuad(
    vec3(x0, y0, z1), vec3(x1, y0, z1), vec3(x1, y1, z1), vec3(x0, y1, z1), color
  )
  renderer.addQuad(
    vec3(x1, y0, z0), vec3(x0, y0, z0), vec3(x0, y1, z0), vec3(x1, y1, z0), color
  )

proc debugTint(color: ColorRGBX, alpha = DebugFillAlpha): ColorRGBX =
  rgbx(color.r, color.g, color.b, alpha)

proc addDebugFill(
    renderer: var ShapeRenderer,
    x0, z0, x1, z1: float32,
    color: ColorRGBX,
    extra = 0.10'f32
) =
  let
    a = liftPoint(vec3(x0, 0, z0), extra)
    b = liftPoint(vec3(x1, 0, z0), extra)
    c = liftPoint(vec3(x1, 0, z1), extra)
    d = liftPoint(vec3(x0, 0, z1), extra)
  renderer.addQuad(a, b, c, d, color)

proc addDebugTile(
    renderer: var ShapeRenderer,
    x, z: int,
    color: ColorRGBX,
    inset = 0.06'f32,
    extra = 0.10'f32
) =
  let o = tileOrigin(x, z)
  renderer.addDebugFill(
    o.x + inset, o.z + inset, o.x + 1 - inset, o.z + 1 - inset, color, extra
  )

proc addDebugRect(
    renderer: var ShapeRenderer,
    x0, z0, x1, z1: float32,
    color: ColorRGBX,
    halfWidth = DebugLineHalf
) =
  let
    a = liftPoint(vec3(x0, 0, z0), 0.28'f32)
    b = liftPoint(vec3(x1, 0, z0), 0.28'f32)
    c = liftPoint(vec3(x1, 0, z1), 0.28'f32)
    d = liftPoint(vec3(x0, 0, z1), 0.28'f32)
  renderer.addLine(a, b, color, halfWidth)
  renderer.addLine(b, c, color, halfWidth)
  renderer.addLine(c, d, color, halfWidth)
  renderer.addLine(d, a, color, halfWidth)

proc addDebugRing(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    color: ColorRGBX,
    halfWidth = 0.08'f32
) =
  var points: seq[Vec3]
  const Sides = 28
  for i in 0 .. Sides:
    let a = float32(i) / float32(Sides) * TAU.float32
    points.add liftPoint(
      center + vec3(cos(a) * radius, 0, sin(a) * radius), 0.22'f32
    )
  renderer.addPolyline(points, color, halfWidth)

proc fadeRgbx(color: ColorRGBX, alpha: float32): ColorRGBX =
  rgbx(
    color.r, color.g, color.b,
    uint8(clamp(alpha, 0.0'f32, 255.0'f32))
  )

proc addHeightRing(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    color: ColorRGBX,
    halfWidth = 0.11'f32
) =
  ## Closed XZ ring at `center.y`. Unlike `addDebugRing` this does not
  ## snap to terrain, so stacked rims stay a dome.
  var points: seq[Vec3]
  const Sides = 22
  for i in 0 .. Sides:
    let a = float32(i) / float32(Sides) * TAU.float32
    points.add center + vec3(cos(a) * radius, 0, sin(a) * radius)
  renderer.addPolyline(points, color, halfWidth)

proc addSpawnShield(
    renderer: var ShapeRenderer,
    feet: Vec3,
    remain: float32,
    seconds: float32
) =
  ## WC3-style invuln bubble: ground disk, stacked rims, orbiting motes.
  ## `remain` is 1 at spawn and 0 as the window expires.
  let
    flashHz = 2.2'f32 + (1.0'f32 - remain) * 5.5'f32
    beat = 0.5'f32 + 0.5'f32 * sin(seconds * TAU.float32 * flashHz)
    pulse = 0.92'f32 + beat * 0.10'f32
    fade = 0.72'f32 + remain * 0.28'f32
    outer = 3.35'f32 * pulse
  renderer.addCircle(
    feet,
    outer,
    fadeRgbx(SpawnShieldDisk, 88.0'f32 * fade + beat * 36.0'f32),
    28
  )
  renderer.addCircle(
    feet,
    1.15'f32 + beat * 0.18'f32,
    fadeRgbx(SpawnShieldCore, 140.0'f32 * fade + beat * 40.0'f32),
    16
  )
  renderer.addHeightRing(
    feet,
    outer * 0.98'f32,
    fadeRgbx(SpawnShieldRim, 200.0'f32 * fade),
    0.14'f32
  )
  var waist = feet
  waist.y += 1.15'f32
  renderer.addCircle(
    waist,
    2.55'f32 * pulse,
    fadeRgbx(SpawnShieldCap, 70.0'f32 * fade + beat * 28.0'f32),
    22
  )
  renderer.addHeightRing(
    waist,
    2.62'f32 * pulse,
    fadeRgbx(SpawnShieldRim, 210.0'f32 * fade),
    0.12'f32
  )
  var chest = feet
  chest.y += 2.25'f32
  renderer.addCircle(
    chest,
    1.85'f32 * pulse,
    fadeRgbx(SpawnShieldCap, 85.0'f32 * fade + beat * 30.0'f32),
    18
  )
  renderer.addHeightRing(
    chest,
    1.92'f32 * pulse,
    fadeRgbx(SpawnShieldRim, 190.0'f32 * fade),
    0.11'f32
  )
  var cap = feet
  cap.y += 3.15'f32
  renderer.addCircle(
    cap,
    0.95'f32 + beat * 0.12'f32,
    fadeRgbx(SpawnShieldCore, 120.0'f32 * fade + beat * 50.0'f32),
    14
  )
  const MoteCount = 8
  for i in 0 ..< MoteCount:
    let
      a = seconds * 2.4'f32 + float32(i) * (TAU.float32 / float32(MoteCount))
      bob = 0.22'f32 * sin(seconds * 3.6'f32 + float32(i) * 0.9'f32)
    var mote = feet
    mote.x += cos(a) * outer * 0.82'f32
    mote.z += sin(a) * outer * 0.82'f32
    mote.y += 1.35'f32 + bob
    renderer.addCircle(
      mote,
      0.38'f32 + beat * 0.14'f32,
      fadeRgbx(SpawnShieldMote, 150.0'f32 * fade + beat * 50.0'f32),
      8
    )

proc addRotCloud(
    renderer: var ShapeRenderer,
    feet: Vec3,
    radius: float32,
    pulse: float32,
    seconds: float32
) =
  ## Breathing blight stain and drifting spores. `pulse` is 0 just after
  ## a rot tick and 1 just before the next.
  let
    flash = max(0.0'f32, 1.0'f32 - pulse * 3.5'f32)
    breathe = 0.5'f32 + 0.5'f32 * sin(pulse * TAU.float32)
    fillA = 72.0'f32 + breathe * 22.0'f32 + flash * 36.0'f32
    coreA = 95.0'f32 + breathe * 22.0'f32 + flash * 40.0'f32
  renderer.addCircle(
    feet,
    radius * (0.94'f32 + breathe * 0.025'f32),
    fadeRgbx(RotFill, fillA),
    32
  )
  renderer.addCircle(
    feet,
    radius * 0.26'f32,
    fadeRgbx(RotCore, coreA),
    16
  )
  const RimCount = 8
  for i in 0 ..< RimCount:
    let
      a = seconds * 0.72'f32 + float32(i) * (TAU.float32 / float32(RimCount))
      bob = 0.11'f32 * sin(seconds * 2.9'f32 + float32(i) * 0.85'f32)
    var spore = feet
    spore.x += cos(a) * radius * 0.86'f32
    spore.z += sin(a) * radius * 0.86'f32
    spore.y += 0.10'f32 + bob
    renderer.addCircle(
      spore,
      0.50'f32 + flash * 0.20'f32,
      fadeRgbx(RotSpore, 70.0'f32 + breathe * 28.0'f32),
      8
    )
  const InnerCount = 5
  for i in 0 ..< InnerCount:
    let a =
      -seconds * 1.18'f32 + float32(i) * (TAU.float32 / float32(InnerCount))
    var spore = feet
    spore.x += cos(a) * radius * 0.40'f32
    spore.z += sin(a) * radius * 0.40'f32
    spore.y += 0.15'f32
    renderer.addCircle(
      spore,
      0.38'f32 + breathe * 0.10'f32,
      fadeRgbx(RotSpore, 62.0'f32 + flash * 32.0'f32),
      8
    )

proc addFireStain(
    renderer: var ShapeRenderer,
    feet: Vec3,
    radius: float32,
    life: float32,
    seconds: float32
) =
  ## Burning tile painted by a charged Lightning hook. Drawn through
  ## fog of war on purpose: the trail is the tell. Own-team vision
  ## along the same disk lives in `fogCanSeeTeam`.
  let
    flicker = 0.5'f32 + 0.5'f32 * sin(seconds * 13.0'f32 + feet.x * 2.4'f32)
    fade = max(0.0'f32, min(life, 1.0'f32))
    fillA = 24.0'f32 + fade * 32.0'f32 + flicker * 12.0'f32
    coreA = 36.0'f32 + fade * 36.0'f32 + flicker * 14.0'f32
  renderer.addCircle(
    feet,
    radius * (0.62'f32 + flicker * 0.06'f32),
    fadeRgbx(FireTrailFill, fillA),
    16
  )
  renderer.addCircle(
    feet,
    radius * 0.22'f32,
    fadeRgbx(FireTrailCore, coreA),
    10
  )
  var ember = feet
  ember.y += 0.10'f32 + flicker * 0.06'f32
  renderer.addCircle(
    ember,
    0.22'f32 + flicker * 0.08'f32,
    fadeRgbx(FireTrailEmber, 40.0'f32 + fade * 20.0'f32),
    8
  )

proc waterSheetAt(x, z: int): bool =
  layers.len > WaterLayer and
    layers[WaterLayer].tiles[z * GridTiles + x].exists

proc addDebugMapOverlays(renderer: var ShapeRenderer) =
  ## Tile tints, walk/block, and the playable AABB / river midline.
  if showLayers:
    for z in 0 ..< GridTiles:
      for x in 0 ..< GridTiles:
        if islandTile(x, z):
          renderer.addDebugTile(x, z, debugTint(DebugIsland, 120), 0.04, 0.18)
        elif waterSheetAt(x, z) and riverTile(x, z):
          renderer.addDebugTile(x, z, debugTint(DebugWater, 100), 0.08, 0.16)
        elif riverTile(x, z):
          renderer.addDebugTile(x, z, debugTint(DebugRiver), 0.04, 0.12)
        elif westBank(x, z):
          if isWalkable(WestLayer, x, z):
            renderer.addDebugTile(x, z, debugTint(DebugWest, 70))
          else:
            renderer.addDebugTile(x, z, debugTint(DebugBlocked, 130))
        elif eastBank(x, z):
          if isWalkable(EastLayer, x, z):
            renderer.addDebugTile(x, z, debugTint(DebugEast, 70))
          else:
            renderer.addDebugTile(x, z, debugTint(DebugBlocked, 130))
        elif landTile(x, z) or x < PlayWestMin or x > PlayEastMax or
            z < PlayZMin or z > PlayZMax:
          renderer.addDebugTile(x, z, debugTint(DebugBlocked, 70), 0.10, 0.08)
  if showWalkable:
    for z in PlayZMin .. PlayZMax:
      for x in PlayWestMin .. PlayEastMax:
        if riverTile(x, z) or waterSheetAt(x, z):
          renderer.addDebugTile(x, z, debugTint(DebugWater, 110), 0.18, 0.20)
        elif westBank(x, z) and isWalkable(WestLayer, x, z):
          renderer.addDebugTile(x, z, debugTint(DebugWalk, 80), 0.18, 0.20)
        elif eastBank(x, z) and isWalkable(EastLayer, x, z):
          renderer.addDebugTile(x, z, debugTint(DebugWalk, 80), 0.18, 0.20)
        else:
          renderer.addDebugTile(x, z, debugTint(DebugNoWalk, 130), 0.18, 0.20)
  if showPlayableBounds:
    let
      x0 = float32(PlayWestMin) - HalfGrid
      x1 = float32(PlayEastMax + 1) - HalfGrid
      z0 = float32(PlayZMin) - HalfGrid
      z1 = float32(PlayZMax + 1) - HalfGrid
      westEdge = float32(PlayWestMax + 1) - HalfGrid
      eastEdge = float32(PlayEastMin) - HalfGrid
      mid = float32(RiverCenterX) - HalfGrid + 0.5'f32
    renderer.addDebugRect(x0, z0, x1, z1, PlayBoundsColor, 0.22'f32)
    renderer.addLine(
      liftPoint(vec3(mid, 0, z0), 0.32'f32),
      liftPoint(vec3(mid, 0, z1), 0.32'f32),
      MidlineColor,
      0.20'f32
    )
    renderer.addLine(
      liftPoint(vec3(westEdge, 0, z0), 0.32'f32),
      liftPoint(vec3(westEdge, 0, z1), 0.32'f32),
      BankEdgeColor,
      0.12'f32
    )
    renderer.addLine(
      liftPoint(vec3(eastEdge, 0, z0), 0.32'f32),
      liftPoint(vec3(eastEdge, 0, z1), 0.32'f32),
      BankEdgeColor,
      0.12'f32
    )

proc addLavaBoil(renderer: var ShapeRenderer, seconds: float32) =
  ## Thin pit lips plus glossy bubble pops on the Voronoi sheet.
  let pitY = float32(WaterLevelSteps) / HeightSteps + 0.12'f32
  var
    westLip: seq[Vec3]
    eastLip: seq[Vec3]
  for z in PlayZMin .. PlayZMax:
    let
      hw = riverHalfWidthAt(z)
      zz = float32(z) - HalfGrid + 0.5'f32
    westLip.add vec3(float32(RiverCenterX - hw) - HalfGrid, pitY, zz)
    eastLip.add vec3(float32(RiverCenterX + hw + 1) - HalfGrid, pitY, zz)
  renderer.addPolyline(westLip, BroilerBar, 0.08'f32)
  renderer.addPolyline(eastLip, BroilerBar, 0.08'f32)
  const BoilCount = 12
  for i in 0 ..< BoilCount:
    let
      seed = float32(i) * 17.13'f32 + seconds * 0.12'f32
      along = abs(sin(seed * 1.31'f32))
      across = 0.5'f32 + 0.5'f32 * sin(seed * 2.17'f32 + 1.7'f32)
      pop = 0.5'f32 + 0.5'f32 * sin(seed * 0.73'f32)
      z = PlayZMin + int(along * float32(PlayZMax - PlayZMin))
      hw = riverHalfWidthAt(z)
      x = RiverCenterX - hw + int(across * float32(max(hw * 2, 1)))
    if not riverTile(x, z) or islandTile(x, z):
      continue
    let
      life = abs(sin(seconds * (0.55'f32 + pop * 0.7'f32) + float32(i) * 0.41'f32))
      grow = life * life
      center = vec3(
        float32(x) - HalfGrid + 0.5'f32 + sin(seed) * 0.28'f32,
        pitY + 0.04'f32 + grow * 0.06'f32,
        float32(z) - HalfGrid + 0.5'f32 + cos(seed * 1.4'f32) * 0.28'f32
      )
      rim = fadeRgbx(rgbx(220, 78, 18, 255), 36.0'f32 + grow * 40.0'f32)
    renderer.addCircle(center, 0.22'f32 + grow * 0.20'f32, rim, 10)

proc addDebugCollisionOverlays(renderer: var ShapeRenderer) =
  ## Unit collision disks, hook latch radius, and fountain pads.
  if not showCollision:
    return
  let bodyR = PudgeCollisionRadius.float32 / WorldScale.float32
  for pudge in run.world.pudges:
    if pudge.state == Dying:
      continue
    renderer.addDebugRing(renderPoint(pudge.position), bodyR, CollisionColor)
  for hook in run.world.hooks:
    if hook.phase == HookIdle:
      continue
    renderer.addDebugRing(
      renderPoint(hook.position),
      hook.radius.float32 / WorldScale.float32,
      HookDiskColor,
      0.10'f32
    )
  let pad = FountainPadRadius.float32 + 0.5'f32
  let padCount = min(run.world.spawnLayout.west.len, run.world.spawnLayout.east.len)
  for s in 0 ..< padCount:
    let west = run.world.spawnLayout.west[s]
    let wc = tileCenterRender(west.x, west.z)
    renderer.addDebugRect(wc.x - pad, wc.z - pad, wc.x + pad, wc.z + pad, SpawnPadColor)
    let east = run.world.spawnLayout.east[s]
    let ec = tileCenterRender(east.x, east.z)
    renderer.addDebugRect(ec.x - pad, ec.z - pad, ec.x + pad, ec.z + pad, SpawnPadColor)


proc runeMix(stone, glow: ColorRGBX, glowParts, parts: int): ColorRGBX =
  let stoneParts = parts - glowParts
  rgbx(
    uint8((int(stone.r) * stoneParts + int(glow.r) * glowParts) div parts),
    uint8((int(stone.g) * stoneParts + int(glow.g) * glowParts) div parts),
    uint8((int(stone.b) * stoneParts + int(glow.b) * glowParts) div parts),
    255
  )

proc runeBright(color: ColorRGBX): ColorRGBX =
  rgbx(
    uint8(min(int(color.r) + 28, 255)),
    uint8(min(int(color.g) + 28, 255)),
    uint8(min(int(color.b) + 28, 255)),
    255
  )

proc tabletPoint(origin: Vec3, yaw, x, z: float32): Vec3 =
  let
    cosine = cos(yaw)
    sine = sin(yaw)
  vec3(
    origin.x + x * cosine - z * sine,
    origin.y,
    origin.z + x * sine + z * cosine
  )

proc addRunePlate(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius, yaw: float32,
    sides: int,
    color: ColorRGBX
) =
  ## Filled regular polygon in the XZ plane, both windings.
  let step = TAU / sides.float32
  for i in 0 ..< sides:
    let
      a0 = yaw + step * i.float32
      a1 = yaw + step * (i + 1).float32
      p0 = vec3(
        center.x + cos(a0) * radius, center.y, center.z + sin(a0) * radius
      )
      p1 = vec3(
        center.x + cos(a1) * radius, center.y, center.z + sin(a1) * radius
      )
    renderer.addTriangle(center, p0, p1, color)
    renderer.addTriangle(center, p1, p0, color)

proc addRuneWalls(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius, yaw, y0, y1: float32,
    sides: int,
    color: ColorRGBX
) =
  let step = TAU / sides.float32
  for i in 0 ..< sides:
    let
      a0 = yaw + step * i.float32
      a1 = yaw + step * (i + 1).float32
      x0 = center.x + cos(a0) * radius
      z0 = center.z + sin(a0) * radius
      x1 = center.x + cos(a1) * radius
      z1 = center.z + sin(a1) * radius
    renderer.addQuad(
      vec3(x0, y0, z0), vec3(x1, y0, z1), vec3(x1, y1, z1), vec3(x0, y1, z0),
      color
    )
    renderer.addQuad(
      vec3(x0, y0, z0), vec3(x0, y1, z0), vec3(x1, y1, z1), vec3(x1, y0, z1),
      color
    )

proc addRuneRing(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius, yaw: float32,
    sides: int,
    color: ColorRGBX,
    halfWidth: float32
) =
  var points = newSeq[Vec3](sides + 1)
  let step = TAU / sides.float32
  for i in 0 .. sides:
    let a = yaw + step * i.float32
    points[i] = vec3(
      center.x + cos(a) * radius, center.y, center.z + sin(a) * radius
    )
  renderer.addPolyline(points, color, halfWidth)

proc addRuneTri(
    renderer: var ShapeRenderer,
    origin: Vec3,
    yaw: float32,
    a, b, c: Vec2,
    color: ColorRGBX
) =
  let
    p0 = tabletPoint(origin, yaw, a.x, a.y)
    p1 = tabletPoint(origin, yaw, b.x, b.y)
    p2 = tabletPoint(origin, yaw, c.x, c.y)
  renderer.addTriangle(p0, p1, p2, color)
  renderer.addTriangle(p0, p2, p1, color)

proc addRuneStroke(
    renderer: var ShapeRenderer,
    origin: Vec3,
    yaw: float32,
    locals: openArray[Vec2],
    color: ColorRGBX,
    halfWidth: float32
) =
  ## One carved stroke: a wide glow ribbon plus a bright core.
  if locals.len < 2:
    return
  var points = newSeq[Vec3](locals.len)
  for i, local in locals:
    points[i] = tabletPoint(origin, yaw, local.x, local.y)
  renderer.addPolyline(
    points, rgbx(color.r, color.g, color.b, 120), halfWidth * 1.9'f32
  )
  let core = runeBright(color)
  renderer.addPolyline(points, core, halfWidth)
  let cap = halfWidth * 1.08'f32
  renderer.addCircle(points[0], cap, core, 8)
  renderer.addCircle(points[^1], cap, core, 8)

proc addRuneGlyph(
    renderer: var ShapeRenderer,
    face: Vec3,
    yaw: float32,
    kind: RuneKind,
    color: ColorRGBX
) =
  ## Distinct Futhark-style glyphs, one per river power. Big Hook is
  ## invented in the same stroke language.
  const hw = 0.095'f32
  case kind
  of RuneHaste:
    # Doubled Kenaz (torch / speed): nested chevrons.
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.46'f32, -0.14'f32),
      vec2(0'f32, 0.50'f32),
      vec2(0.46'f32, -0.14'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.46'f32, -0.44'f32),
      vec2(0'f32, 0.20'f32),
      vec2(0.46'f32, -0.44'f32)
    ], color, hw)
  of RuneDoubleDamage:
    # Doubled Tiwaz (warrior): two upright spears.
    for side in [-0.26'f32, 0.26'f32]:
      renderer.addRuneStroke(face, yaw, [
        vec2(side, -0.50'f32),
        vec2(side, 0.18'f32)
      ], color, hw)
      renderer.addRuneTri(
        face, yaw,
        vec2(side - 0.22'f32, 0.08'f32),
        vec2(side, 0.52'f32),
        vec2(side + 0.22'f32, 0.08'f32),
        runeBright(color)
      )
      renderer.addRuneStroke(face, yaw, [
        vec2(side - 0.22'f32, 0.08'f32),
        vec2(side, 0.52'f32),
        vec2(side + 0.22'f32, 0.08'f32)
      ], color, hw)
  of RuneRegen:
    # Algiz (life): a stave with a rising fork.
    renderer.addRuneStroke(face, yaw, [
      vec2(0'f32, -0.52'f32),
      vec2(0'f32, 0.52'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.44'f32, 0.50'f32),
      vec2(0'f32, 0.02'f32),
      vec2(0.44'f32, 0.50'f32)
    ], color, hw)
  of RuneBigHook:
    # Meat-hook stave: T-handle and a barbed J.
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.36'f32, 0.50'f32),
      vec2(0.20'f32, 0.50'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.06'f32, 0.50'f32),
      vec2(-0.06'f32, -0.02'f32),
      vec2(0.10'f32, -0.32'f32),
      vec2(0.28'f32, -0.46'f32),
      vec2(0.48'f32, -0.32'f32),
      vec2(0.48'f32, -0.12'f32),
      vec2(0.32'f32, -0.02'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(0.28'f32, -0.46'f32),
      vec2(0.10'f32, -0.22'f32)
    ], color, hw)
  of RuneLightning:
    # Sowilo (sun / lightning): a charged zigzag.
    renderer.addRuneStroke(face, yaw, [
      vec2(0.10'f32, 0.52'f32),
      vec2(-0.22'f32, 0.08'f32),
      vec2(0.16'f32, -0.04'f32),
      vec2(-0.10'f32, -0.52'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.22'f32, 0.08'f32),
      vec2(0.02'f32, 0.08'f32)
    ], color, hw)
  of RuneBounty:
    # Coin diamond: a river bounty, not a timed stave.
    renderer.addRuneStroke(face, yaw, [
      vec2(0'f32, 0.48'f32),
      vec2(0.38'f32, 0'f32),
      vec2(0'f32, -0.48'f32),
      vec2(-0.38'f32, 0'f32),
      vec2(0'f32, 0.48'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(0'f32, 0.18'f32),
      vec2(0'f32, -0.18'f32)
    ], color, hw)
    renderer.addRuneStroke(face, yaw, [
      vec2(-0.16'f32, 0'f32),
      vec2(0.16'f32, 0'f32)
    ], color, hw)

proc addRiverRune(
    renderer: var ShapeRenderer,
    center: Vec3,
    waterY: float32,
    yaw: float32,
    kind: RuneKind
) =
  ## WC3 river rune: a hewn stone octagon with a glowing carved glyph
  ## hovering over a colored caustic on the coals.
  let
    glow = RuneColors[kind]
    radius = RuneCoreRadius * 1.32'f32
    y0 = center.y - RuneTabletThick * 0.5'f32
    y1 = center.y + RuneTabletThick * 0.5'f32
    stone = runeMix(RuneStone, glow, 1, 5)
    well = runeMix(RuneStoneDark, glow, 2, 5)
    rim = runeMix(RuneStoneRim, glow, 2, 5)
    face = vec3(center.x, y1 + 0.05'f32, center.z)
    aura = rgbx(glow.r, glow.g, glow.b, 78)
    shaftH = 0.72'f32
    shaftW = radius * 0.18'f32
  var caustic = vec3(center.x, waterY + 0.14'f32, center.z)
  renderer.addCircle(
    caustic, radius * 2.35'f32, rgbx(glow.r, glow.g, glow.b, 72), 16
  )
  renderer.addCircle(
    caustic, radius * 1.45'f32, rgbx(glow.r, glow.g, glow.b, 110), 14
  )
  caustic.y = waterY + 0.16'f32
  renderer.addCircle(caustic, radius * 0.95'f32, rgbx(18, 22, 28, 80), 12)
  var top = center
  var bot = center
  top.y = y1
  bot.y = y0
  renderer.addRuneWalls(
    center, radius, yaw, y0, y1, RuneTabletSides, RuneStoneDark
  )
  renderer.addRunePlate(bot, radius, yaw, RuneTabletSides, RuneStoneDark)
  renderer.addRunePlate(top, radius, yaw, RuneTabletSides, stone)
  renderer.addRuneRing(
    top, radius * 0.96'f32, yaw, RuneTabletSides, rim, 0.07'f32
  )
  var inset = top
  inset.y = y1 + 0.02'f32
  renderer.addRunePlate(
    inset, radius * 0.76'f32, yaw, RuneTabletSides, well
  )
  renderer.addRuneRing(
    face, radius * 0.70'f32, yaw, 16, rgbx(glow.r, glow.g, glow.b, 90),
    0.034'f32
  )
  let
    yAura0 = center.y - 0.04'f32
    yAura1 = center.y + shaftH
  renderer.addQuad(
    vec3(center.x - shaftW, yAura0, center.z),
    vec3(center.x + shaftW, yAura0, center.z),
    vec3(center.x + shaftW, yAura1, center.z),
    vec3(center.x - shaftW, yAura1, center.z),
    aura
  )
  renderer.addQuad(
    vec3(center.x - shaftW, yAura0, center.z),
    vec3(center.x - shaftW, yAura1, center.z),
    vec3(center.x + shaftW, yAura1, center.z),
    vec3(center.x + shaftW, yAura0, center.z),
    aura
  )
  renderer.addQuad(
    vec3(center.x, yAura0, center.z - shaftW),
    vec3(center.x, yAura0, center.z + shaftW),
    vec3(center.x, yAura1, center.z + shaftW),
    vec3(center.x, yAura1, center.z - shaftW),
    aura
  )
  renderer.addQuad(
    vec3(center.x, yAura0, center.z - shaftW),
    vec3(center.x, yAura1, center.z - shaftW),
    vec3(center.x, yAura1, center.z + shaftW),
    vec3(center.x, yAura0, center.z + shaftW),
    aura
  )
  renderer.addRuneGlyph(face, yaw, kind, glow)


proc fogCrossing(a, b: Vec3): Vec3 =
  ## Walks the fog boundary along `a`→`b`. `a` and `b` must disagree
  ## on `fogCanSee`.
  let visA = fogCanSee(worldFromRender(a))
  var
    lo = 0.0'f32
    hi = 1.0'f32
  for _ in 0 ..< 8:
    let
      mid = (lo + hi) * 0.5'f32
      p = a * (1.0'f32 - mid) + b * mid
    if fogCanSee(worldFromRender(p)) == visA:
      lo = mid
    else:
      hi = mid
  if visA:
    a * (1.0'f32 - lo) + b * lo
  else:
    a * (1.0'f32 - hi) + b * hi

proc clipChainToFog(points: openArray[Vec3]): seq[seq[Vec3]] =
  ## Visible fragments of a hook polyline. Segments that cross the fog
  ## are cut at the boundary so the chain appears to emerge from the dark.
  if points.len == 0:
    return
  var
    current: seq[Vec3]
    prev = points[0]
    prevVis = fogCanSee(worldFromRender(prev))
  if prevVis:
    current.add prev
  for i in 1 ..< points.len:
    let
      p = points[i]
      vis = fogCanSee(worldFromRender(p))
    if prevVis and vis:
      current.add p
    elif prevVis and not vis:
      current.add fogCrossing(prev, p)
      if current.len > 0:
        result.add current
      current.setLen(0)
    elif not prevVis and vis:
      current.add fogCrossing(prev, p)
      current.add p
    prev = p
    prevVis = vis
  if current.len > 0:
    result.add current

proc drawMeatHook(
    renderer: var ShapeRenderer,
    points: openArray[Vec3],
    heading: Heading,
    flying: bool,
    grabbed: bool,
    teamColor: ColorRGBX,
    seconds: float32,
    headRadius = MeatHookRadius,
    showHead = true,
    charged = false,
    attachHand = false,
    handOrigin = vec3(0,0,0)
) =
  if points.len == 0:
    return
  let
    yaw = renderFacing(heading)
    headPos = liftPoint(points[^1], 1.45'f32)
    roll = if grabbed: 0'f32 else: sin(seconds * 5.0'f32) * 0.06'f32
    transform = hookTransform(headPos, yaw, headRadius, roll)
    eye = if showHead: transform * HookEye else: headPos
  var lifted: seq[Vec3]
  for i in 0..<points.high:
    let
      a = points[i]
      b = points[i+1]
      steps = max(1, int(ceil(length(b-a) / 2.0'f32)))
    for j in 0..<steps:
      let u = j.float32 / steps.float32
      var p = liftPoint(a * (1-u) + b * u, 1.45'f32)
      # A small amount of slack gives the chain weight; a caught victim
      # pulls it taut. Every sample stays above its local terrain surface.
      if not grabbed:
        p.y -= sin(u * PI.float32) * (if flying: 0.12'f32 else: 0.22'f32)
      lifted.add p
  if showHead:
    let forward = vec3(sin(yaw),0,cos(yaw))
    while lifted.len > 1 and dot(lifted[^1]-eye,forward) > 0:
      lifted.setLen(lifted.len-1)
  lifted.add eye
  if attachHand and lifted.len > 1:
    lifted[0] = handOrigin
  renderer.addHookChain(lifted, charged=charged)
  if showHead:
    renderer.addButcherHook(transform,teamColor)

const
  FirepitTiles = [
    "crypt-rock-1", "crypt-rock-2", "crypt-rock-1", "crypt-rock-2",
    "crypt-grate-2", "crypt-lava-2", "crypt-lava-3"
  ]
    ## Banks vary only inside the charcoal volcanic pair. No purple stone.
  FirepitRock = SurfaceNames.len
  FirepitJagged = SurfaceNames.len + 1
  FirepitGrate = SurfaceNames.len + 4
  FirepitLava = SurfaceNames.len + 5
  FirepitCrust = SurfaceNames.len + 6
  FirepitFloor = vec3(1.04, 0.96, 0.86)
  FirepitSkirt = vec3(0.78, 0.62, 0.48)

proc applyArenaTerrain(mapSeed: int) =
  ## Volcanic rock floor at authored brightness. Gameplay kinds stay put.
  seed = mapSeed
  initTerrain(MixedTrees, GeneratedTerrain, PaintedRocks, FirepitTiles)
  terrainSplats = false
  setTileMaterial(
    int(GrassTile), FirepitRock.float32, FirepitJagged.float32,
    FirepitFloor, FirepitSkirt, 1
  )
  setTileMaterial(
    int(RoadTile), FirepitGrate.float32, FirepitGrate.float32,
    vec3(1.08, 0.96, 0.84), vec3(0.72, 0.48, 0.34), 5
  )
  setTileMaterial(
    int(RockTile), FirepitJagged.float32, FirepitRock.float32,
    FirepitFloor, FirepitSkirt, 4
  )
  setTileMaterial(
    int(MarshTile), FirepitLava.float32, FirepitRock.float32,
    vec3(1.06, 0.92, 0.74), vec3(0.64, 0.38, 0.26), 2
  )
  setTileMaterial(
    int(StoneTile), FirepitCrust.float32, FirepitRock.float32,
    FirepitFloor, FirepitSkirt, 6
  )
  setTileMaterial(
    int(TreeTile), FirepitJagged.float32, FirepitRock.float32,
    FirepitFloor, FirepitSkirt, 0
  )
  scatterRocks(70, mapSeed)

proc runGraphics*() =
  startProfileTrace()
  profileBlock "atlas":
    let builder = newHudAtlas(4096)
    proc placeholderIcon(): Image =
      result = newImage(128, 128)
      result.fill(rgba(42, 48, 62, 255))
    proc addIcon(key, path: string) =
      var icon: Image
      if fileExists(path):
        try:
          icon = readImage(path).resize(128, 128)
        except PixieError:
          echo "warning: HUD icon unreadable ", path
          icon = placeholderIcon()
      else:
        echo "warning: HUD icon missing ", path
        icon = placeholderIcon()
      if not builder.addImage(key, icon):
        raise newException(GraphicsError, "the UI atlas is too small for " & key)
    addIcon("hook", iconPath(HookAbilityIcon, "abilities"))
    addIcon("blink", iconPath(BlinkAbilityIcon, "abilities"))
    addIcon("rot", iconPath(RotAbilityIcon, "abilities"))
    addIcon(AttackIcon, iconPath(AttackIcon))
    for team in Team:
      addIcon(PortraitKeys[team], portraitPath(team))
    for kind in UpgradeKind:
      addIcon(UpgradeIcons[kind], iconPath(UpgradeIcons[kind]))
    for item in ShopBoots..ShopWard:
      let name = ShopItemIcons[item]
      if name.len == 0:
        continue
      let path = iconPath(name, "items")
      if not fileExists(path):
        continue
      addIcon(name, path)
    builder.addDefaultFonts()
    builder.write(AtlasPath)
  var window: Window
  var sk: Silky
  profileBlock "window":
    (window, sk) = initGameWindow(
      "Pudge Wars",
      AtlasPath,
      gameWindowSize(options.windowWidth, options.windowHeight),
      options.vsync,
      iconPath = AppIconPath
    )
  profileBlock "audio":
    initGameAudio(options.mute)
    let keysFile =
      if options.keysPath.len > 0: options.keysPath
      else: "pudge_keys.cfg"
    if loadKeyBinds(keysFile):
      echo "keys: loaded ", keysFile
      let
        cliQuickcast = options.quickcast
        cliAutocast = options.autocast
      if fileQuickcastSet:
        options.quickcast = fileQuickcast
      if fileAutocastSet:
        options.autocast = fileAutocast
      if cliQuickcast:
        options.quickcast = true
      if cliAutocast:
        options.autocast = true
    elif options.keysPath.len > 0:
      echo "keys: no such file ", options.keysPath

  when not defined(emscripten):
    if netRole == NetHost:
      var botSeatPaths: seq[string]
      for group in options.botGroups:
        for _ in 0 ..< group.count:
          botSeatPaths.add group.path
      if not startHosting(
          options.hostPort,
          netPlayerName(),
          "examples/pudge_wars/emscripten",
          run.world.killGoal,
          run.world.runePeriod div TickRate,
          botSeatPaths,
          int(options.teamSize)
      ):
        quit("cannot start the lobby server on port " & $options.hostPort)
      echo "host: lobby open at ", hostingUrl()
      echo "host: native clients join with --join ws://<that address>/ws"
      if options.humanSlots.len > 0:
        hostClaimLocal(int(options.humanSlots[0]))

  profileBlock "terrain":
    amplitude = 1.15'f32
    treeHeight = 7.2'f32
    applyArenaTerrain(run.map.seed)

  let scene = newCharacterScene(window)
  scene.useToonShading()
  var
    pudgeModels: array[Team, CharacterModel]
    pudgeClips: array[Team, array[5, int]]
    pudgeMeleeClips: array[Team, int]
    chainHands: Table[int32, Vec3]
  profileBlock "models":
    for team in Team:
      let spec = PudgeSpecs[team]
      let model = loadCharacterModel(spec.modelPath, spec.targetHeight)
      pudgeModels[team] = model
      pudgeMeleeClips[team] = model.clipIndex("ButcherChop")
      pudgeClips[team] = [
        model.clipIndex(spec.runClip),
        model.clipIndex(spec.idleClip),
        model.clipIndex(spec.deathClip),
        model.clipIndex(spec.attackClip),
        model.clipIndex(spec.victoryClip)
      ]
  profileBlock "bake":
    bakeTerrain(rebuildWalkability = false)

  var
    particles = initParticleSystem()
    worldBarRenderer = initWorldBarRenderer()
    shapeRenderer = initShapeRenderer()
    hookRenderer = initShapeRenderer()
    knifeRenderer = initShapeRenderer()
    transport = initPlayer(
      live = not run.replayMode,
      durationTicks =
        if run.replayMode:
          int32(run.replayData.hashes.len)
        else:
          run.maximumTicks,
      # A host idles in the lobby until Enter starts the match.
      playing = not options.pauseOnStart and netRole != NetHost,
      speed = options.speed
    )
    netLobbyOpen = netRole == NetHost
    cameraDistance = DefaultCameraDistance
    cameraYaw = RtsCameraYaw
    cameraPitch = RtsCameraPitch
    cameraTarget = vec3(0, 0, 0)
    cameraEye = vec3(0, 0, 0)
    panning = false
    orbiting = false
    rmbGesture = false
    rmbDragged = false
    rmbOrigin = vec2(0)
    panKeyGesture = false
    panKeyDragged = false
    panKeyOrigin = vec2(0)
    panKeyPressedAt = 0.0
    panTap = false
    lastDragMouse = vec2(0)
    rightClickCommand = false
    minimapPanning = false
    followSelection = false
    actionCam = initActionCam(
      minDistance = BakedZoomInDistance,
      maxDistance = BakedZoomOutDistance,
      tight = 0.42'f32,
      followRate = 1.45'f32,
      zoomRate = 1.25'f32,
      holdSeconds = 2.0'f32,
      mapSpan = HalfGrid * 2.0'f32,
      closeScale = 0.9'f32
    )
    replayCheckpoints: seq[SeekCheckpoint]
    previousPositions: Table[int32, Vec3]
    previousFacings: Table[int32, float32]
    previousHookPositions: Table[int32, Vec3]
    previousRunePositions: Table[int32, Vec3]
    previousHp: Table[int32, int32]
    previousStates: Table[int32, PudgeState]
    previousThrown: Table[int32, int32]
    floatingTexts: seq[FloatingText]
    blinkResidues: seq[BlinkResidue]
    renderAlpha = 1.0'f32
    animationAlpha = 0.0'f32
    lastFrameTime = epochTime()
  hostLobbyOpen = netLobbyOpen
  if run.replayMode:
    transport.repeating = true
  if humanControlActive():
    actionCam.takeManual()
    followSelection = true
    let hero = heroGroundPoint()
    cameraTarget.x = hero.x
    cameraTarget.z = hero.z

  var
    fogVisionTick = int32.low
    fogVisionTeam = int32.low
    fogExplored: seq[bool]
    fogValues: seq[uint8]
    fogBlurred: seq[uint8]

  proc updateTerrainVision() =
    ## Uploads the local team's softened visible + explored terrain.
    let team = int32(fogTeam())
    if fogVisionTick == run.world.tick and fogVisionTeam == team:
      return
    if fogVisionTeam != team:
      fogExplored.setLen(0)
    fogVisionTick = run.world.tick
    fogVisionTeam = team
    let n = GridTiles * GridTiles
    if fogValues.len != n:
      fogValues.setLen(n)
    if team < 0:
      for value in fogValues.mitems:
        value = 255
      uploadTerrainVisibility(fogValues)
      return
    if fogExplored.len != n:
      fogExplored = newSeq[bool](n)
    fillTeamVision(run.world, team, fogValues)
    for i in 0 ..< n:
      if fogValues[i] == 255:
        fogExplored[i] = true
      elif fogExplored[i]:
        fogValues[i] = 72
      else:
        fogValues[i] = 26
    blurVisibilityInto(
      fogValues, fogBlurred, int32(GridTiles), int32(GridTiles)
    )
    uploadTerrainVisibility(fogBlurred)

  proc recordedTicksNow(): int32 =
    ## How much finished tape exists: recorded locally by the host's
    ## sim, or streamed in from one when following.
    if run.recorder != nil:
      int32(run.recorder.data.hashes.len)
    elif run.replayPlayer != nil:
      int32(run.replayPlayer.data.hashes.len)
    else:
      0

  proc captureCheckpoint(): SeekCheckpoint =
    SeekCheckpoint(
      tick: int(run.world.tick),
      world: run.world.clone(),
      replayActionIndex:
        if run.replayPlayer != nil: run.replayPlayer.actionIndex else: 0,
      hashCheck: run.hashCheck
    )

  proc captureUnitPositions() =
    previousPositions.clear()
    previousFacings.clear()
    previousHookPositions.clear()
    previousRunePositions.clear()
    previousHp.clear()
    previousStates.clear()
    for pudge in run.world.pudges:
      previousPositions[pudge.id] = renderPoint(pudge.position)
      previousFacings[pudge.id] = renderFacing(pudge.facing)
      previousHp[pudge.id] = pudge.hp
      previousStates[pudge.id] = pudge.state
      previousThrown[pudge.id] = pudge.hooksThrown
    for hook in run.world.hooks:
      previousHookPositions[hook.id] = renderPoint(hook.position)
    for rune in run.world.runes:
      previousRunePositions[rune.id] = renderPoint(rune.position)

  proc unitPoint(id: int32, position: WorldPoint): Vec3 =
    if predictor.predictsUnit(id):
      return renderPoint(predictor.localRenderPoint(
        if interpolateVisuals: renderAlpha else: 1.0'f32))
    let current = renderPoint(position)
    if not interpolateVisuals:
      return current
    mix(previousPositions.getOrDefault(id, current), current, renderAlpha)

  proc unitFacing(id: int32, facing: Heading): float32 =
    let current = renderFacing(facing)
    if not interpolateVisuals:
      return current
    let previous =
      if predictor.predictsUnit(id): renderFacing(predictor.previousLocalFacing)
      else: previousFacings.getOrDefault(id, current)
    previous + shortestTurn(previous, current) * renderAlpha

  proc hookPoint(id: int32, position: WorldPoint): Vec3 =
    let current = renderPoint(position)
    if not interpolateVisuals:
      return current
    mix(previousHookPositions.getOrDefault(id, current), current, renderAlpha)

  proc runePoint(id: int32, position: WorldPoint): Vec3 =
    let current = renderPoint(position)
    if not interpolateVisuals:
      return current
    mix(previousRunePositions.getOrDefault(id, current), current, renderAlpha)

  proc unitTime(ticks: int32): float32 =
    (ticks.float32 + animationAlpha) / TickRate.float32

  proc rotPulse(pudge: Pudge): float32 =
    ## 0 just after a damage tick, 1 just before the next.
    (pudge.rotTicks.float32 + animationAlpha) /
      max(RotPeriodTicks.float32, 1.0'f32)

  proc holdTime(
      model: CharacterModel, clip: int, ticks: int32, hold: bool
  ): float32 =
    if hold:
      min(ticks.float32 / TickRate.float32, clipDuration(model, clip))
    else:
      unitTime(ticks)

  proc cameraView(): Mat4 =
    lookAt(cameraEye, cameraTarget, vec3(0, 1, 0))

  proc screenPoint(position: Vec3, viewProjection: Mat4): Vec2 =
    ## Projects a world position into window pixel coordinates.
    let
      clip = viewProjection * vec4(position.x, position.y, position.z, 1)
      panel =
        if worldViewRect.size.x > 1 and worldViewRect.size.y > 1:
          worldViewRect
        else:
          GameUiPanel(
            origin: vec2(0),
            size: vec2(window.size.x.float32, window.size.y.float32)
          )
    screenFromClip(clip, panel)

  proc applyPlayViewport() =
    ## Maps the 3D camera onto the gap between top bar and bottom HUD.
    let
      play = worldViewRect
      bottom = window.size.y.float32 - play.origin.y - play.size.y
    glViewport(
      GLint(play.origin.x.int32),
      GLint(bottom.int32),
      GLsizei(max(play.size.x.int32, 1)),
      GLsizei(max(play.size.y.int32, 1))
    )

  proc playPanel(): GameUiPanel =
    if worldViewRect.size.x > 1 and worldViewRect.size.y > 1:
      worldViewRect
    else:
      GameUiPanel(
        origin: vec2(0),
        size: vec2(window.size.x.float32, window.size.y.float32)
      )

  proc resetOrbit() =
    cameraYaw = RtsCameraYaw
    cameraPitch = RtsCameraPitch

  proc takeCamera() =
    followSelection = false
    actionCam.takeManual()

  proc dropDirector() =
    actionCam.takeManual()

  proc grabPan(delta: Vec2, perDistance: float32) =
    takeCamera()
    let pan = rtsGroundPan(
      cameraYaw, delta, cameraDistance * perDistance
    )
    cameraTarget.x -= pan.x
    cameraTarget.z -= pan.y

  proc applyFollowLock() =
    ## Lock-cam look-at: interpolated butcher so the camera rides the
    ## same 60 Hz blend as the mesh instead of hitching on 32 Hz sim
    ## steps. A spectator POV stays locked on the selected butcher.
    let spectatorEyes = not humanControlActive() and spectateIndex() >= 0
    if (followSelection or spectatorEyes) and not orbiting and not panning and
        not minimapPanning:
      var
        found = false
        pt = vec3(0)
      if humanControlActive() and heroIndex() >= 0:
        let pudge = predictedPudge(heroIndex())
        pt = unitPoint(pudge.id, pudge.position)
        found = true
      else:
        let eyes = spectateIndex()
        if eyes >= 0:
          let pudge = run.world.pudges[eyes]
          pt = unitPoint(pudge.id, pudge.position)
          found = true
        else:
          let lock = followCameraPoint()
          if lock.found:
            pt = lock.point
            found = true
      if found:
        cameraTarget.x = pt.x
        cameraTarget.z = pt.z
        actionCam.takeManual()
    cameraTarget.x = clamp(cameraTarget.x, -HalfGrid, HalfGrid)
    cameraTarget.z = clamp(cameraTarget.z, -HalfGrid, HalfGrid)
    cameraEye = rtsCameraEye(
      cameraTarget, cameraDistance, cameraYaw, cameraPitch
    )

  proc updateCamera(dt: float32) =
    ## Camera grab is WC3/SC2-style and trackpad-first: hold the pan
    ## key (C) and move the pointer, no mouse button. MMB drag, arrow
    ## keys, fullscreen edge scroll, and the minimap still pan. RMB
    ## commands; it never moves the camera. Option+LMB pings; Alt+RMB
    ## orbits, then snaps back.
    rightClickCommand = false
    panTap = false
    var scrollPanned = false
    updateMinimapCamera(
      window, sk.mousePos, cameraTarget, minimapPanning, followSelection
    )
    if minimapPanning:
      takeCamera()
      orbiting = false
      panning = false
      panKeyGesture = false
      panKeyDragged = false

    let
      overUi = mouseOverUi(window, sk.mousePos)
      mousePx = window.mousePos.vec2
      play = playPanel()
      onWorld = not overUi and (play.size.x <= 1 or play.contains(mousePx))
      rightDown = window.buttonDown[MouseRight]
      middleDown = window.buttonDown[MouseMiddle]
      panKey = bindKey(BindPan)
      panKeyDown = window.buttonDown[panKey]
      scroll = window.scrollDelta

    if menuIsOpen():
      panning = false
      orbiting = false
      rmbGesture = false
      rmbDragged = false
      panKeyGesture = false
      panKeyDragged = false
      resetOrbit()
      window.cursor = Cursor(kind: ArrowCursor)
    else:
      if followSelection and actionCam.enabled:
        actionCam.takeManual()
      if rightDown:
        if not rmbGesture and onWorld:
          rmbGesture = true
          rmbOrigin = mousePx
          lastDragMouse = mousePx
      elif rmbGesture:
        # RMB is the command button, held or clicked: it never pans.
        # Only an Alt-orbit swallows the release.
        if not orbiting and humanControlActive():
          rightClickCommand = true
        rmbGesture = false
        rmbDragged = false

      if panKeyDown:
        if not panKeyGesture:
          panKeyGesture = true
          panKeyDragged = false
          panKeyOrigin = mousePx
          panKeyPressedAt = epochTime()
          lastDragMouse = mousePx
        elif not panKeyDragged and
            (mousePx - panKeyOrigin).length > RtsCameraDragPixels:
          panKeyDragged = true
          lastDragMouse = mousePx
          takeCamera()
      elif panKeyGesture:
        if not panKeyDragged and epochTime() - panKeyPressedAt < 0.28:
          panTap = true
        panKeyGesture = false
        panKeyDragged = false

      let altDown =
        window.buttonDown[KeyLeftAlt] or window.buttonDown[KeyRightAlt]
      let wantOrbit =
        altDown and rightDown and not minimapPanning and
        (rmbGesture or orbiting)
      if wantOrbit:
        if not orbiting:
          lastDragMouse = mousePx
          takeCamera()
        orbiting = true
        panning = false
      elif orbiting:
        orbiting = false
        resetOrbit()

      let wantPan =
        # Wheel-button drag, or hold-C pointer grab after a few pixels.
        # Minimap and edge/arrow panning are handled below. RMB never
        # moves the camera.
        not orbiting and not minimapPanning and
        (middleDown or (panKeyGesture and panKeyDragged))
      if wantPan:
        if not panning:
          lastDragMouse = mousePx
          takeCamera()
        panning = true
      else:
        panning = false

      if panning or panKeyGesture:
        window.cursor = Cursor(
          kind: (if panning: ClosedHandCursor else: OpenHandCursor)
        )
      else:
        window.cursor = Cursor(kind: ArrowCursor)

      let delta = mousePx - lastDragMouse
      lastDragMouse = mousePx
      if orbiting:
        cameraYaw -= delta.x * 0.008'f32
        cameraPitch = rtsClampedPitch(cameraPitch + delta.y * 0.006'f32)
      elif panning:
        grabPan(delta, RtsPointerPanPerDistance)

      if panKeyDown and not orbiting and not minimapPanning and
          (scroll.x != 0 or scroll.y != 0):
        # Hold C and two-finger swipe: pan without sliding the cursor
        # into a screen edge.
        grabPan(vec2(scroll.x, -scroll.y), RtsScrollPanPerDistance)
        panKeyDragged = true
        scrollPanned = true

      if not orbiting and not panning and not minimapPanning:
        var keyPan = vec2(0)
        # Arrows always pan, including while a butcher is under your
        # hand — WASD is the walk stick. WC3 / StarCraft split.
        if window.buttonDown[KeyLeft]: keyPan.x -= 1
        if window.buttonDown[KeyRight]: keyPan.x += 1
        if window.buttonDown[KeyUp]: keyPan.y -= 1
        if window.buttonDown[KeyDown]: keyPan.y += 1
        const EdgePixels = 12
        let mouse = window.mousePos
        # Fullscreen only. Window edges, including over the bottom HUD.
        if viewerIsFullscreen(window) and
            not followSelection and not actionCam.enabled and
            not panKeyDown and mouse != ivec2(0, 0):
          let
            winW = window.size.x.float32
            winH = window.size.y.float32
          if mousePx.x <= EdgePixels: keyPan.x -= 1
          elif mousePx.x >= winW - EdgePixels:
            keyPan.x += 1
          if mousePx.y <= EdgePixels: keyPan.y -= 1
          elif mousePx.y >= winH - EdgePixels:
            keyPan.y += 1
        if keyPan != vec2(0, 0):
          takeCamera()
          let
            speed = cameraDistance * RtsKeyPanPerDistance * dt
            right = rtsCameraRight(cameraYaw)
            look = rtsCameraLook(cameraYaw)
          cameraTarget.x += (right.x * keyPan.x + look.x * keyPan.y) * speed
          cameraTarget.z += (right.z * keyPan.x + look.z * keyPan.y) * speed

    if actionCam.enabled and not orbiting and not panning and
        not minimapPanning and not menuIsOpen():
      actionCam.minDistance = zoomMinDistance
      actionCam.maxDistance = zoomMaxDistance
      actionCam.beginFrame(run.world.tick)
      feedDirectorCam(actionCam, run.world, fogTeam())
      actionCam.chooseShot(dt, transport.speed)
      actionCam.follow(cameraTarget, cameraDistance, dt, transport.speed)

    if not scrollPanned and not overUi and scroll.y != 0:
      dropDirector()
      cameraDistance = clampCameraDistance(
        cameraDistance * pow(0.92'f32, scroll.y)
      )
    if not netLobbyOpen:
      # Keyboard zoom so a trackpad is not required to change distance.
      if window.buttonDown[KeyMinus]:
        dropDirector()
        cameraDistance = clampCameraDistance(
          cameraDistance * pow(1.08'f32, dt * 8.0'f32)
        )
      if window.buttonDown[KeyEqual]:
        dropDirector()
        cameraDistance = clampCameraDistance(
          cameraDistance * pow(0.92'f32, dt * 8.0'f32)
        )
    applyFollowLock()

  proc emitBlinkOriginPuff(chest: Vec3) =
    ## Leave-behind burst at the tile they hopped FROM. Stacks the
    ## existing MagicBurst / CombatSparks vocabulary, spread and delayed
    ## so the puff stays readable at the 155 play-camera zoom.
    const
      Offsets = [
        vec3(0.0'f32, 0.0'f32, 0.0'f32),
        vec3(1.35'f32, 0.45'f32, 0.40'f32),
        vec3(-1.20'f32, 0.20'f32, 1.15'f32),
        vec3(0.30'f32, 0.90'f32, -1.25'f32)
      ]
    for offset in Offsets:
      let puff = chest + offset
      particles.emitParticleBurst(MagicBurst, puff)
      particles.emitParticleBurst(CombatSparks, puff)
    particles.emitParticleBurst(MagicBurst, chest, 0.12'f32)
    particles.emitParticleBurst(CombatSparks, chest, 0.12'f32)
    particles.emitParticleBurst(MagicBurst, chest, 0.24'f32)
    particles.emitParticleBurst(MagicBurst, chest, 0.36'f32)
    particles.emitParticleBurst(CombatSparks, chest + vec3(0, 1.1'f32, 0), 0.18'f32)

  proc emitTickParticles() =
    for pudge in run.world.pudges:
      var pos = unitPoint(pudge.id, pudge.position)
      pos.y = surfaceHeightNear(pos.x, pos.z, pos.y) + 1.6'f32
      if pudge.damageLanded:
        particles.emitParticleBurst(CombatSparks, pos)
      if pudge.justHeadshot or pudge.justChunked:
        particles.emitParticleBurst(FireBurst, pos)
      if pudge.justGrabbed:
        particles.emitParticleBurst(MagicBurst, pos)
        particles.emitParticleBurst(CombatSparks, pos)
      if pudge.justRune:
        particles.emitParticleBurst(MagicBurst, pos)
      if pudge.justBlinked:
        let
          originFeet = liftPoint(renderPoint(pudge.blinkFrom), 0)
          originChest = liftPoint(renderPoint(pudge.blinkFrom), 1.85'f32)
          dest = liftPoint(renderPoint(pudge.position), 1.6'f32)
        emitBlinkOriginPuff(originChest)
        particles.emitParticleBurst(MagicBurst, dest)
        particles.emitParticleBurst(FireBurst, dest)
        blinkResidues.add BlinkResidue(
          origin: originFeet,
          worldOrigin: pudge.blinkFrom,
          facing: previousFacings.getOrDefault(
            pudge.id, renderFacing(pudge.facing)
          ),
          team: pudge.team,
          slot: pudgeIndex(run.world, pudge.id),
          born: epochTime()
        )
      if pudge.enteredRiver:
        var splash = pos
        splash.y = surfaceHeightNear(pos.x, pos.z, pos.y) + 0.3'f32
        particles.emitParticleBurst(FireBurst, splash)
        particles.emitParticleBurst(CombatSparks, splash, 0.08'f32)
      if pudge.state == Alive and pudge.rotOn and fogShownPudge(pudge) and
          (pudge.rotTicks == 0 or pudge.rotTicks == RotPeriodTicks div 2):
        var cloud = pos
        cloud.y -= 0.95'f32
        particles.emitParticleBurst(DecayAura, cloud)
        if pudge.rotTicks == 0:
          particles.emitParticleBurst(DecayAura, cloud, 0.16'f32)
    if run.world.tick mod 20 == 0:
      const PitSpots = 3
      let stride = PlayZMax - PlayZMin + 1
      for i in 0 ..< PitSpots:
        let
          z = PlayZMin + ((int(run.world.tick) div 20 * 17 + i * 31) mod stride)
          xOff = ((int(run.world.tick) div 20 + i * 7) mod 7) - 3
          x = RiverCenterX + xOff
        if not riverTile(x, z) or islandTile(x, z):
          continue
        var ember = tileCenterRender(x, z)
        ember.y = surfaceHeightNear(ember.x, ember.z, ember.y) + 0.22'f32
        if fogCanSee(worldFromRender(ember)):
          particles.emitParticleBurst(FireBurst, ember)
    if run.world.tick mod IslandFountainHealPeriodTicks == 0:
      let fountain = liftPoint(
        tileCenterRender(IslandCenterX, IslandCenterZ), 1.15'f32
      )
      if fogCanSee(islandFountainPos()):
        particles.emitParticleBurst(HealingAura, fountain)
        const Offsets = [
          vec3(2.1'f32, 0.2'f32, 0.4'f32),
          vec3(-1.8'f32, 0.15'f32, 1.6'f32),
          vec3(0.3'f32, 0.35'f32, -2.0'f32),
          vec3(-0.6'f32, 0.1'f32, -0.3'f32)
        ]
        for offset in Offsets:
          particles.emitParticleBurst(HealingAura, fountain + offset)
      for pudge in run.world.pudges:
        if not pudge.onIslandFountain or pudge.hp >= pudge.maxHp:
          continue
        if not fogShownPudge(pudge):
          continue
        var glow = unitPoint(pudge.id, pudge.position)
        glow.y = surfaceHeightNear(glow.x, glow.z, glow.y) + 1.4'f32
        particles.emitParticleBurst(HealingAura, glow)
    if run.world.clashTick == run.world.tick:
      var clash = renderPoint(run.world.clashPoint)
      clash.y = surfaceHeightNear(clash.x, clash.z, clash.y) + 1.4'f32
      particles.emitParticleBurst(CombatSparks, clash)
      particles.emitParticleBurst(FireBurst, clash)
    if run.world.lightningTick == run.world.tick:
      var bolt = renderPoint(run.world.lightningPoint)
      bolt.y = surfaceHeightNear(bolt.x, bolt.z, bolt.y) + 1.4'f32
      particles.emitParticleBurst(CombatSparks, bolt)
      particles.emitParticleBurst(MagicBurst, bolt)
    for i, patch in run.world.firePatches:
      if int(run.world.tick + i) mod 16 != 0:
        continue
      var ember = renderPoint(patch.position)
      ember.y = surfaceHeightNear(ember.x, ember.z, ember.y) + 0.22'f32
      particles.emitParticleBurst(FireBurst, ember)
    for rune in run.world.runes:
      if rune.spawnTick == run.world.tick:
        var pos = renderPoint(rune.position)
        pos.y = surfaceHeightNear(pos.x, pos.z, pos.y) + 1.6'f32
        particles.emitParticleBurst(MagicBurst, pos)
    for hook in run.world.hooks:
      if hook.phase == HookIdle:
        continue
      var head = hookPoint(hook.id, hook.position)
      head.y = surfaceHeightNear(head.x, head.z, head.y) + 1.05'f32
      if hook.phase == HookFlying and
          hook.traveled mod WorldScale < hook.speed:
        particles.emitParticleBurst(CombatSparks, head)
      if hook.phase != HookFlying or hook.traveled > hook.speed:
        continue
      let owner = pudgeIndex(run.world, hook.ownerId)
      if owner < 0:
        continue
      var origin = unitPoint(
        run.world.pudges[owner].id,
        run.world.pudges[owner].position
      )
      origin.y = surfaceHeightNear(origin.x, origin.z, origin.y) + 1.2'f32
      particles.emitParticleBurst(MagicBurst, origin)

  const SeatTints: array[MaxPudgeCount, chroma.Color] = [
    color(1.00, 0.55, 0.48, 1.0),   # west 1: crimson
    color(1.00, 0.72, 0.48, 1.0),   # west 2: rust
    color(1.00, 0.52, 0.70, 1.0),   # west 3: rose
    color(1.00, 0.64, 0.38, 1.0),   # west 4: amber
    color(0.90, 0.42, 0.38, 1.0),   # west 5: brick
    color(0.52, 0.70, 1.00, 1.0),   # east 1: sky
    color(0.42, 0.86, 0.95, 1.0),   # east 2: aqua
    color(0.68, 0.58, 1.00, 1.0),   # east 3: violet
    color(0.38, 0.74, 1.00, 1.0),   # east 4: steel
    color(0.58, 0.80, 1.00, 1.0)    # east 5: ice
  ]

  proc tintIndex(pudge: Pudge): int =
    ## West lanes 0..4, east lanes 5..9, so 3v3 east stays ember/gold/rose.
    let lane = clamp(int(pudge.slot), 0, MaxTeamSize - 1)
    if pudge.team == EastTeam: MaxTeamSize + lane else: lane

  proc seatTint(worldIndex: int): chroma.Color =
    ## Soft per-seat wash over the team model, WC3 player-color style.
    if worldIndex < 0 or worldIndex >= run.world.pudges.len:
      return color(1, 1, 1, 1)
    let base = SeatTints[tintIndex(run.world.pudges[worldIndex])]
    color(
      0.62 + base.r * 0.38,
      0.62 + base.g * 0.38,
      0.62 + base.b * 0.38,
      1.0
    )

  proc butcherTint(worldIndex: int, pudge: Pudge): chroma.Color =
    ## Seat color, then ice while spawn-shielded, else a gold crackle
    ## under Lightning, a sick-green wash while Rot is on or the butcher
    ## is standing in someone else's cloud, or an ember wash in fire.
    result = seatTint(worldIndex)
    if pudge.state == Dying:
      return
    if pudge.shieldTicks > 0:
      let
        remain =
          pudge.shieldTicks.float32 / max(SpawnShieldTicks.float32, 1.0'f32)
        flashHz = 2.4'f32 + (1.0'f32 - remain) * 5.0'f32
        beat = 0.5'f32 + 0.5'f32 * sin(
          unitTime(int32(run.world.tick)) * TAU.float32 * flashHz
        )
        weight = 0.48'f32 + 0.22'f32 * beat
      result.r = result.r * (1.0'f32 - weight) + 0.62'f32 * weight
      result.g = result.g * (1.0'f32 - weight) + 0.94'f32 * weight
      result.b = result.b * (1.0'f32 - weight) + 1.00'f32 * weight
      return
    var weight = 0.0'f32
    var washR = 0.10'f32
    var washG = 0.26'f32
    var washB = 0.08'f32
    if pudge.hasBuff(RuneLightning):
      let beat = 0.5'f32 + 0.5'f32 * sin(
        unitTime(int32(run.world.tick)) * TAU.float32 * 8.0'f32
      )
      weight = 0.22'f32 + 0.16'f32 * beat
      washR = 1.00'f32
      washG = 0.86'f32
      washB = 0.22'f32
    elif pudge.rotOn:
      weight =
        0.26'f32 + 0.22'f32 * max(0.0'f32, 1.0'f32 - rotPulse(pudge) * 3.0'f32)
    elif run.world.rotAffected(pudge):
      let beat = 0.5'f32 + 0.5'f32 * sin(
        unitTime(int32(run.world.tick)) * TAU.float32 * 2.0'f32
      )
      weight = 0.14'f32 + 0.10'f32 * beat
    elif run.world.fireAffected(pudge):
      let beat = 0.5'f32 + 0.5'f32 * sin(
        unitTime(int32(run.world.tick)) * TAU.float32 * 6.0'f32
      )
      weight = 0.16'f32 + 0.10'f32 * beat
      washR = 1.00'f32
      washG = 0.38'f32
      washB = 0.08'f32
    if weight <= 0:
      return
    result.r = result.r * (1.0'f32 - weight) + washR * weight
    result.g = result.g * (1.0'f32 - weight) + washG * weight
    result.b = result.b * (1.0'f32 - weight) + washB * weight

  proc pudgeLabel(id: int32): string =
    ## Lobby names, bot personality labels, or P<id>.
    let index = pudgeIndex(run.world, id)
    if index < 0:
      return "P" & $id
    butcherDisplayName(index)

  proc emitCombatFeedback() =
    ## Damage and heal numbers, the kill feed, and one-shot sounds,
    ## all from tick deltas. History seeks stay silent. Combat audio
    ## is first-person plus whatever is on the play camera; off-map
    ## bot hooks stay quiet.
    let
      now = epochTime()
      audible = not transport.inHistory
    proc heroIs(id: int32): bool =
      humanControlActive() and heroIndex() >= 0 and
        run.world.pudges[heroIndex()].id == id
    proc inPlayView(world: Vec3): bool =
      let panel = playPanel()
      if panel.size.x <= 1 or panel.size.y <= 1:
        return true
      let clip =
        perspective(45.0'f32, panel.aspect, 0.1'f32, 1000.0'f32) *
        cameraView() * vec4(world.x, world.y, world.z, 1)
      if clip.w <= 0.05:
        return false
      let
        nx = clip.x / clip.w
        ny = clip.y / clip.w
        nz = clip.z / clip.w
      nx >= -1.08 and nx <= 1.08 and ny >= -1.08 and ny <= 1.08 and
        nz >= -1.05 and nz <= 1.05
    proc hearAt(point: WorldPoint, a = 0'i32, b = 0'i32): bool =
      heroIs(a) or heroIs(b) or inPlayView(liftPoint(renderPoint(point)))
    for pudge in run.world.pudges:
      if pudge.id notin previousHp:
        continue
      let
        delta = pudge.hp - previousHp[pudge.id]
        prevState = previousStates.getOrDefault(pudge.id, Alive)
      var anchor = unitPoint(pudge.id, pudge.position)
      anchor.y = surfaceHeightNear(anchor.x, anchor.z, anchor.y)
      if prevState == Alive and pudge.state == Dying:
        let killer = pudgeIndex(run.world, pudge.lastHurtBy)
        if killer >= 0 and run.world.pudges[killer].id != pudge.id:
          pushKillFeed(
            pudgeLabel(run.world.pudges[killer].id) & " butchered " &
              pudgeLabel(pudge.id),
            run.world.pudges[killer].team
          )
        else:
          if pudge.inRiver:
            pushKillFeed(pudgeLabel(pudge.id) & " broiled", pudge.team)
          else:
            pushKillFeed(pudgeLabel(pudge.id) & " rotted", pudge.team)
        if audible:
          if heroIs(pudge.id):
            playGameSound(SndDeath)
          elif hearAt(pudge.position, pudge.lastHurtBy):
            playGameSound(SndKill, 0.8)
      if prevState == Dying and pudge.state == Alive:
        if fogShownPudge(pudge):
          var chest = renderPoint(pudge.position)
          chest.y = surfaceHeightNear(chest.x, chest.z, chest.y) + 1.7'f32
          particles.emitParticleBurst(MagicBurst, chest)
          particles.emitParticleBurst(MagicBurst, chest, 0.12'f32)
        if heroIs(pudge.id):
          # Respawn: bring the camera home with the hero.
          let home = renderPoint(pudge.position)
          cameraTarget.x = home.x
          cameraTarget.z = home.z
      if audible:
        if pudge.hooksThrown > previousThrown.getOrDefault(pudge.id, 0) and
            hearAt(pudge.position, pudge.id):
          playGameSound(SndHookThrow, 0.75)
        if pudge.justGrabbed and
            hearAt(pudge.position, pudge.id, pudge.hookedBy):
          playGameSound(SndHookLatch, 0.9)
        if pudge.damageLanded and hearAt(pudge.position, pudge.id):
          playGameSound(SndMelee, 0.55)
      # Combat numbers never leak through the fog: a hit you cannot
      # see should not print its damage either.
      if fogShownPudge(pudge):
        if pudge.justRune:
          pushKillFeed(
            pudgeLabel(pudge.id) & " took " & RuneNames[pudge.justRuneKind],
            pudge.team
          )
          var lift = anchor
          lift.y += 3.2'f32
          floatingTexts.add FloatingText(
            text: RuneNames[pudge.justRuneKind] & "!",
            color: RuneColors[pudge.justRuneKind],
            world: lift,
            born: now
          )
        if delta < 0 and prevState == Alive:
          floatingTexts.add FloatingText(
            text: "-" & $(-delta),
            color: rgbx(236, 92, 70, 255),
            world: anchor,
            born: now
          )
        elif delta > 0 and prevState == Alive and pudge.state == Alive:
          floatingTexts.add FloatingText(
            text: "+" & $delta,
            color: rgbx(96, 220, 110, 255),
            world: anchor,
            born: now
          )
    if run.world.chunkerId != 0 and
        run.world.chunkTick == run.world.tick:
      let ci = pudgeIndex(run.world, run.world.chunkerId)
      let team =
        if ci >= 0: run.world.pudges[ci].team else: WestTeam
      pushKillFeed(
        pudgeLabel(run.world.chunkerId) & " denied " &
          pudgeLabel(run.world.chunkOwnerId) & "'s hook",
        team
      )
    # Kill-streak shouts are global: fog never hides GODLIKE.
    var
      bestRank = 0
      bestTitle = ""
      bestSub = ""
      bestTeam = WestTeam
    for pudge in run.world.pudges:
      if pudge.justBounty > 0 and fogShownPudge(pudge):
        var lift = unitPoint(pudge.id, pudge.position)
        lift.y = surfaceHeightNear(lift.x, lift.z, lift.y) + 2.4'f32
        floatingTexts.add FloatingText(
          text: "+" & $pudge.justBounty,
          color: rgbx(255, 214, 120, 255),
          world: lift,
          born: now
        )
      if pudge.justFirstBlood:
        pushKillFeed("FIRST BLOOD", pudge.team)
      if pudge.justStreak >= 3:
        pushKillFeed(
          streakFeedLine(pudgeLabel(pudge.id), pudge.justStreak),
          pudge.team
        )
      if pudge.justShutdown >= 3:
        pushKillFeed("SHUTDOWN", pudge.team)
      if pudge.justMulti >= 2:
        let multi = multiKillTitle(pudge.justMulti)
        if multi.len > 0:
          pushKillFeed(
            pudgeLabel(pudge.id) & " just got a " & multi,
            pudge.team
          )
      var rank = 0
      if pudge.justStreak >= 10:
        rank = 200
      elif pudge.justStreak == 9:
        rank = 180
      elif pudge.justFirstBlood:
        rank = 170
      elif pudge.justMulti >= 5:
        rank = 160
      elif pudge.justStreak >= 3:
        rank = 100 + int(pudge.justStreak)
      elif pudge.justMulti >= 4:
        rank = 90
      elif pudge.justShutdown >= 3:
        rank = 50 + int(pudge.justShutdown)
      elif pudge.justMulti >= 2:
        rank = 20 + int(pudge.justMulti)
      if rank > bestRank:
        bestRank = rank
        if pudge.justStreak >= 3:
          bestTitle = streakTitle(pudge.justStreak)
        elif pudge.justFirstBlood:
          bestTitle = "FIRST BLOOD"
        elif pudge.justMulti >= 2:
          bestTitle = multiKillTitle(pudge.justMulti)
        elif pudge.justShutdown >= 3:
          bestTitle = "SHUTDOWN"
        bestSub = pudgeLabel(pudge.id)
        if pudge.justStreak >= 3 and pudge.justMulti >= 2:
          bestSub = bestSub & " — " & multiKillTitle(pudge.justMulti)
        bestTeam = pudge.team
    if bestRank > 0:
      pushKillStinger(bestTitle, bestSub, bestTeam)
    if floatingTexts.len > 80:
      floatingTexts = floatingTexts[^80 .. ^1]

    if audible and run.world.clashTick == run.world.tick and
        (hearAt(
          run.world.clashPoint,
          run.world.chunkerId,
          run.world.chunkVictimId
        ) or heroIs(run.world.chunkOwnerId)):
      playGameSound(SndHookClash, 0.9)
    if audible and run.world.lightningTick == run.world.tick and
        hearAt(run.world.lightningPoint):
      playGameSound(SndHookClash, 0.7)

  proc advanceRenderedSimulation() =
    captureUnitPositions()
    advanceGame()
    emitTickParticles()
    emitCombatFeedback()
    if int(run.world.tick) mod (TickRate * 10) == 0 or
        int32(run.world.tick) == transport.timelineEnd:
      if replayCheckpoints.len == 0 or
          replayCheckpoints[^1].tick < int(run.world.tick):
        replayCheckpoints.add captureCheckpoint()

  proc restoreTo(targetTick: int32) =
    var checkpointIndex = 0
    for i, checkpoint in replayCheckpoints:
      if checkpoint.tick > targetTick:
        break
      checkpointIndex = i
    let checkpoint = replayCheckpoints[checkpointIndex]
    run.world.restore(checkpoint.world)
    if run.recorder != nil and run.replayPlayer != nil:
      run.replayPlayer.data = run.recorder.data
    run.replayPlayer.syncCursor(uint32(run.world.tick))
    run.hashCheck = checkpoint.hashCheck
    run.historyPlayback = true
    previousPositions.clear()
    previousFacings.clear()
    previousHookPositions.clear()
    particles.clearParticles()
    resetHumanTransients()
    clearKillFeed()
    floatingTexts.setLen(0)
    blinkResidues.setLen(0)
    previousHp.clear()
    previousStates.clear()
    previousThrown.clear()
    renderAlpha = 1
    animationAlpha = 0
    while int32(run.world.tick) < targetTick:
      advanceGame()

  proc resetMatchPresentation() =
    ## Clears every client-side trace of the previous match.
    replayCheckpoints = @[captureCheckpoint()]
    previousPositions.clear()
    previousFacings.clear()
    previousHookPositions.clear()
    previousRunePositions.clear()
    previousHp.clear()
    previousStates.clear()
    previousThrown.clear()
    floatingTexts.setLen(0)
    blinkResidues.setLen(0)
    fogExplored.setLen(0)
    fogVisionTick = int32.low
    particles.clearParticles()
    spectatePudgeId = 0
    resetHumanTransients()
    clearKillFeed()
    resetMatchRecap()
    renderAlpha = 1
    animationAlpha = 0
    followSelection = false
    cameraTarget = vec3(0, 0, 0)
    cameraYaw = RtsCameraYaw
    cameraPitch = RtsCameraPitch
    orbiting = false
    panning = false
    rmbGesture = false
    panKeyGesture = false
    panKeyDragged = false
    panTap = false
    if humanControlActive():
      actionCam.takeManual()
      followSelection = true
      let hero = heroGroundPoint()
      cameraTarget.x = hero.x
      cameraTarget.z = hero.z
    else:
      followSelection = false
      actionCam.enabled = true
      actionCam.locked = false
      actionCam.lockId = 0

  proc applyHostedSeats() =
    ## Freezes the roster for a hosted match: the host's own seat plus
    ## every remote claim drives a human seat; the rest stay bots.
    ## Lobby seat numbers map through the (possibly compacted) roster.
    when not defined(emscripten):
      run.humanSlots.setLen(0)
      if localSeat >= 0:
        run.humanSlots.add localSeat
      for seat in hostRemoteSeats():
        let index = run.world.worldIndexOfSeat(seat)
        if index >= 0 and index notin run.humanSlots:
          run.humanSlots.add index

  proc rematchNow() =
    ## Fresh match on the same arena. A host takes everyone along by
    ## rebroadcasting the new setup; a follower waits for exactly that.
    if netRole == NetClient:
      return
    flushBugTapeIfArmed()
    restartMatch()
    if netRole == NetHost:
      applyHostedSeats()
    transport = initPlayer(
      live = true,
      durationTicks = run.maximumTicks,
      playing = true,
      speed = options.speed
    )
    startReplayRecording(uint32(transport.durationTicks))
    when not defined(emscripten):
      if netRole == NetHost:
        hostAnnounceStart(run)
    resetMatchPresentation()

  proc rebakeArena() =
    ## Terrain follows `run.map` after a live N vs N resize.
    applyArenaTerrain(run.map.seed)
    bakeTerrain(rebuildWalkability = false)

  proc startHostedMatch() =
    ## Enter in the host lobby: lock seats, start the tape, tell every
    ## connection, and let the world tick. Disabled seats rebuild the
    ## world with a compacted roster first.
    when not defined(emscripten):
      block seatGuard:
        var westOn, eastOn = 0
        let n = hostTeamSize
        for seat in 0 ..< hostSeatCount():
          if seatDisabled[seat]:
            continue
          if seat < n: inc westOn else: inc eastOn
        if westOn == 0 or eastOn == 0:
          setHumanError("EACH TEAM NEEDS AT LEAST ONE SEAT")
          return
      setRosterExperiment(seatDisabled)
      if activeRoster().len > 0:
        rebuildWithRoster()
      localSeat =
        if localClaim >= 0: run.world.worldIndexOfSeat(localClaim)
        else: -1
      applyHostedSeats()
      startReplayRecording(uint32(transport.durationTicks))
      hostAnnounceStart(run)
      netLobbyOpen = false
      hostLobbyOpen = false
      transport.playing = true
      if humanControlActive():
        followSelection = true
        actionCam.takeManual()
        let hero = heroGroundPoint()
        cameraTarget.x = hero.x
        cameraTarget.z = hero.z
      else:
        followSelection = false

  proc netRematchNow(setup: Setup) =
    ## The host rematched (or we reconnected): rebuild the follower
    ## world from its setup (same arena) and stream on. Drop predicted
    ## intents — they already live on the host tape we'll catch up to.
    predictor.disable()
    netClientRestart(setup)
    transport = initPlayer(
      live = true,
      durationTicks = run.maximumTicks,
      playing = true,
      speed = options.speed
    )
    resetMatchPresentation()

  if not run.replayMode and netRole == NetOff:
    startReplayRecording(uint32(transport.durationTicks))
  when not defined(emscripten):
    if netRole == NetHost and options.autoStart:
      # Skip the lobby: the match runs at once and joiners grab bot
      # seats mid-game (also the scriptable smoke-test path).
      startHostedMatch()
  replayCheckpoints = @[captureCheckpoint()]

  when defined(takeScreenshot):
    var screenshotFrame = 0
    # Captures may sit closer or farther than the play zoom clamp.
    zoomMinDistance = 12.0'f32
    zoomMaxDistance = 220.0'f32
    actionCam.takeManual()
    proc applyCaptureLook() =
      applyScreenshotCamera(cameraDistance)
      if existsEnv("CAM_X"):
        cameraTarget.x = getEnv("CAM_X").parseFloat.float32
      if existsEnv("CAM_Z"):
        cameraTarget.z = getEnv("CAM_Z").parseFloat.float32
      if existsEnv("CAM_YAW"):
        cameraYaw = getEnv("CAM_YAW").parseFloat.float32
      if existsEnv("CAM_PITCH"):
        cameraPitch = getEnv("CAM_PITCH").parseFloat.float32
    applyCaptureLook()
    if existsEnv("SIM_SECONDS"):
      let wanted = int32(getEnv("SIM_SECONDS").parseFloat * TickRate.float64)
      while run.world.tick < wanted and
          run.world.tick < run.maximumTicks and not run.world.gameOver:
        advanceGame()
    # Freeze on the requested tick so a hook stays in the air.
    transport.playing = false
    applyCaptureLook()

  const Step = 1.0'f32 / float32(TickRate)
  # Bottom-left debug readout state: exponentially-smoothed render FPS,
  # measured from the wall-clock gap between frame starts.
  var fpsSmoothed = 0.0'f32
  var fpsPrevStart = 0.0
  # Network debug panel (dev): F6 toggles the overlay, F7 cycles the
  # network-condition simulator (off/local/good/poor/extreme). F9/F10
  # stay MENU/TEAM. Auto-open when --netsim already turned the sim on.
  var netDebugPanel = netSimConfig().enabled
  var lastClipOverride = clipOverride
  window.onFrame = proc() =
    # Start/stop Fluffy before profileBlock "frame". startTrace clears
    # the span stack; a matching measurePop of a skipped push is IndexDefect.
    if window.buttonPressed[KeyF2] and not chatTyping():
      discard handleChromeKey(KeyF2)
    profileBlock "frame":
      let dt = frameDelta(lastFrameTime, Step)
      if clipOverride != lastClipOverride:
        clipOverrideTime = 0
        lastClipOverride = clipOverride
      if clipOverride != ClipOverrideOff:
        clipOverrideTime += dt
      hostLobbyOpen = netLobbyOpen
      if window.buttonPressed[KeyLeftBracket]:
        toggleTransportBar()
      sk.uiScale = hudUiScale(window)
      sk.mousePos = window.mousePos.vec2 / sk.uiScale
      worldViewRect = worldPixelPanel(window)
      let playAspect = worldViewRect.aspect
      tickGameAudio()
      if window.buttonPressed[bindKey(BindMute)]:
        toggleGameAudioMute()
      if window.buttonPressed[KeyF3]:
        toggleDebugMenu()
      if window.buttonPressed[KeyF8]:
        toggleBugRecording()
      if netRole == NetClient:
        if window.buttonPressed[KeyF6]:
          netDebugPanel = not netDebugPanel
        if window.buttonPressed[KeyF7]:
          netSimAdvanceCycle()
          netDebugPanel = true
      cameraDistance = clampCameraDistance(cameraDistance)
      when not defined(emscripten):
        if netRole == NetHost:
          pumpHosting(run)
          if netLobbyOpen:
            const SeatKeys = [
              Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, Key0
            ]
            let shiftHeld =
              window.buttonDown[KeyLeftShift] or
              window.buttonDown[KeyRightShift]
            if not hostingStarted():
              if window.buttonPressed[KeyMinus]:
                if applyTeamSize(int(options.teamSize) - 1):
                  setHostTeamSize(int(options.teamSize))
                  rebakeArena()
              if window.buttonPressed[KeyEqual]:
                if applyTeamSize(int(options.teamSize) + 1):
                  setHostTeamSize(int(options.teamSize))
                  rebakeArena()
            for i, key in SeatKeys:
              if i >= hostSeatCount():
                continue
              if window.buttonPressed[key]:
                if shiftHeld:
                  # Toggle the seat for roster experiments; claimed
                  # or host-held seats cannot be switched off.
                  if not seatDisabled[i] and hostSeatTaken(i):
                    discard
                  else:
                    seatDisabled[i] = not seatDisabled[i]
                elif not seatDisabled[i]:
                  hostClaimLocal(i)
            if window.buttonPressed[Key0] and hostSeatCount() < 10:
              hostClaimLocal(-1)
            if window.buttonPressed[KeyEnter]:
              startHostedMatch()
      if netRole == NetClient:
        let netEvents = netClientPump(run)
        if netEvents.restarted:
          netRematchNow(netEvents.setup)
        localSeat = netClientSeat()
        if transport.playing and transport.targetTick < 0:
          # Fallen behind the live stream (slow frame, boot backlog):
          # seek forward, which fast-forwards at catch-up speed. Jitter
          # keeps the gap around a tick or two; a quarter second means
          # real drift. Live-TV rule: playback chases the live edge, so
          # pause to inspect history.
          let received = recordedTicksNow()
          if received - run.world.tick > TickRate div 4:
            transport.seekTo(received)
      if consumeMenuRestart() or (
          run.world.gameOver and not run.replayMode and
          netRole != NetClient and
          window.buttonPressed[bindKey(BindRematch)]):
        rematchNow()
      updateCamera(dt)
      let recorded = recordedTicksNow()
      transport.sync(run.world.tick, recorded, run.world.gameOver)
      let restoreTick = transport.takeRestore()
      if restoreTick >= 0:
        restoreTo(restoreTick)
        transport.sync(run.world.tick, recorded, run.world.gameOver)
      if netLobbyOpen:
        transport.playing = false
        chatInputEnabled = false
        cancelChatTyping()
      else:
        chatInputEnabled = true
      transport.startFrame(dt, TickRate)
      if not transport.inHistory and not run.replayMode and
          (humanControlActive() or run.humanSlots.len > 0 or
            netRole != NetOff):
        # Live human seats play at 1x; faster speeds are for
        # spectating and catching back up to the live tick.
        transport.setSpeed(0)
      if not netLobbyOpen and not menuIsOpen() and not chatTyping():
        # Replay and live spectators get the same LMB pass: click a
        # butcher to lock fog to their eyes. A seated human still
        # issues commands through the rest of handleHumanInput.
        let
          inputProjection =
            perspective(45.0'f32, playAspect, 0.1'f32, 1000.0'f32)
        handleHumanInput(
          window,
          inputProjection * cameraView(),
          mouseOverUi(window, sk.mousePos),
          # A follower always trails the stream by a tick or two, so
          # "history" cannot mean "cannot command" there: intents land
          # at the host's live tick regardless.
          not transport.inHistory or netRole == NetClient,
          cameraTarget,
          followSelection,
          rightClickCommand and not window.buttonDown[bindKey(BindPan)],
          window.buttonDown[bindKey(BindPan)],
          panTap
        )
      else:
        # Chat / menu skip the WASD poll. Stop so the last KeyA dest
        # does not keep walking west after the keyboard is stolen.
        releaseKeyboardSteer()
      let frameStart = epochTime()
      if fpsPrevStart > 0:
        let fdt = frameStart - fpsPrevStart
        if fdt > 0:
          fpsSmoothed = fpsSmoothed * 0.9'f32 + float32(1.0 / fdt) * 0.1'f32
      fpsPrevStart = frameStart
      run.historyPlayback = transport.inHistory or netRole == NetClient
      profileBlock "simulate":
        while transport.shouldTick(frameStart):
          if atLiveTickCap(
              run.world.tick, transport.durationTicks, transport.live):
            break
          if netRole == NetClient and
              run.world.tick >= recordedTicksNow():
            # A follower never simulates a tick the host has not
            # finished; the accumulator keeps what the stream owes.
            break
          run.historyPlayback = transport.inHistory or
            netRole == NetClient
          advanceRenderedSimulation()
          transport.sync(
            run.world.tick, recordedTicksNow(), run.world.gameOver
          )
      when not defined(emscripten):
        if netRole == NetHost:
          hostBroadcastTicks(run)
          hostForwardResults(run, localSeat)
      when defined(emscripten):
        profileBlock "predict":
          # Rebuild the prediction world from the freshly-advanced confirmed
          # world: replay this seat's unconfirmed local intents and run a
          # few ticks ahead, so the local butcher and camera respond before
          # the host echoes the command back. Followers only; the confirmed
          # `run` world stays the hash-verified authority (never ticked
          # here). Rollback happens inside `rebuild`.
          if netRole == NetClient and netClientSeat() >= 0 and
              not run.world.gameOver:
            # Size the lead for the worst-case RTT (ping + jitter), so a
            # jittery link keeps a stable lead instead of bouncing frame to
            # frame — fewer timing-miss snaps.
            let lead = leadFromRttMs(netPingMs() + netPingJitterMs())
            if not predictor.enabled or predictor.seat != netClientSeat():
              predictor.enable(netClientSeat(), lead)
            else:
              predictor.lead = lead
            predictor.rebuild(run)
          else:
            predictor.disable()
      if netRole == NetClient and run.hashCheck.mismatches > 0:
        netReportDesync(run.hashCheck.firstTick)
      let active = simulationActive(transport)
      if active:
        renderAlpha = clamp(transport.accumulator / Step, 0.0'f32, 1.0'f32)
        animationAlpha = renderAlpha
      else:
        renderAlpha = 1
        animationAlpha = 0
      applyFollowLock()
      if active:
        particles.advanceParticles(dt)

      let
        view = cameraView()
        projection = perspective(45.0'f32, playAspect, 0.1'f32, 1000.0'f32)
        viewProjection = projection * view
        cameraForward = normalize(cameraTarget - cameraEye)
        barRight = normalize(cross(cameraForward, vec3(0, 1, 0)))
        barUp = normalize(cross(barRight, cameraForward))

      proc drawButchers() =
        if not scene.sunDepthPass:
          knifeRenderer.clear()
        for pudgeIndex in 0 ..< run.world.pudges.len:
          # The local WASM seat renders from the prediction world; all
          # other butchers and every non-predicting build render the
          # confirmed world (an unchanged copy).
          let pudge = predictedPudge(pudgeIndex)
          if not fogShownPudge(pudge) or pudge.justBlinked:
            continue
          let
            model = pudgeModels[pudge.team]
            liveClip =
              if run.world.gameOver and pudge.team == run.world.winner and
                  pudge.state == Alive:
                pudgeClips[pudge.team][victoryClip]
              elif pudge.animClip == attackClip and pudge.meleeAnim:
                pudgeMeleeClips[pudge.team]
              else:
                pudgeClips[pudge.team][pudge.animClip]
            clip =
              case clipOverride
              of ClipOverrideOff: liveClip
              of ClipOverrideBind: -1
              of ClipOverrideIdle: pudgeClips[pudge.team][idleClip]
              of ClipOverrideRun: pudgeClips[pudge.team][runClip]
              of ClipOverrideAttack: pudgeMeleeClips[pudge.team]
              of ClipOverrideDeath: pudgeClips[pudge.team][deathClip]
              of ClipOverrideVictory: pudgeClips[pudge.team][victoryClip]
            pos = unitPoint(pudge.id, pudge.position)
          var drawn = pos
          drawn.y = surfaceHeightNear(pos.x, pos.z, pos.y)
          let animSeconds =
            if clipOverride == ClipOverrideOff:
              holdTime(model, liveClip, pudge.animTicks,
                pudge.state == Dying or pudge.animClip == attackClip)
            elif clip < 0:
              0'f32
            else:
              clipOverrideTime
          drawCharacter(
            scene,
            model,
            drawn,
            unitFacing(pudge.id, pudge.facing),
            clip,
            animSeconds,
            butcherTint(pudgeIndex(run.world, pudge.id), pudge)
          )
          if not scene.sunDepthPass:
            let
              facing = unitFacing(pudge.id, pudge.facing)
              leftHand = model.characterJointTransform("L_Hand", drawn, facing)
              rightHand = model.characterJointTransform("R_Hand", drawn, facing)
              wrap = if pudge.team == WestTeam: rgbx(160,62,46,254)
                else: rgbx(47,100,153,254)
              heldRadius = block:
                var r = hookRadius(pudge.upgrades[UpgradeRadius])
                if pudge.hasBuff(RuneBigHook):
                  r = r + r * RuneBigHookPercent div 100
                r.float32 / WorldScale.float32 * HeldHookVisualScale
            chainHands[pudge.id] = butcherHeldHookEye(rightHand, facing, heldRadius)
            knifeRenderer.addButcherKnife(
              butcherKnifeTransform(leftHand), DefaultButcherKnife, wrap)
            var hookOut = false
            for hook in run.world.hooks:
              if hook.ownerId == pudge.id and hook.phase != HookIdle:
                hookOut = true
                break
            if pudge.state == Alive and not hookOut:
              knifeRenderer.addButcherHook(
                butcherHeldHookTransform(rightHand, facing, heldRadius), wrap)
        if scene.sunDepthPass:
          return
        let now = epochTime()
        for residue in blinkResidues:
          let age = now - residue.born
          if age < 0 or age >= BlinkResidueSeconds:
            continue
          if not fogCanSee(residue.worldOrigin):
            continue
          let
            fade = 1.0'f32 - float32(age / BlinkResidueSeconds)
            model = pudgeModels[residue.team]
            clip = pudgeClips[residue.team][idleClip]
          var tint = seatTint(residue.slot)
          tint.a = fade * 0.58'f32
          var drawn = residue.origin
          drawn.y = surfaceHeightNear(drawn.x, drawn.z, drawn.y)
          drawCharacter(
            scene,
            model,
            drawn,
            residue.facing,
            clip,
            0,
            tint,
            1.0'f32 + (1.0'f32 - fade) * 0.14'f32
          )

      profileBlock "draw":
        scene.setToonHour(clockHour(float32(run.world.tick) + renderAlpha, TickRate))
        setEnvironmentPalette(scene.toon)
        profileBlock "shadows":
          sunDepthPasses(window.size):
            if sunDepthTerrainDirty:
              drawTerrainSunDepth()
              commitSunTerrain()
            scene.sunDepthPass = true
            drawButchers()
            scene.sunDepthPass = false
        glClearColor(0.05, 0.07, 0.10, 1.0)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
        applyPlayViewport()
        profileBlock "vision":
          updateTerrainVision()
        drawTerrain(viewProjection, showTiles)
      profilePush("worldDraw")
      beginCharacters(scene, window, view, projection, cameraEye)
      applyPlayViewport()
      drawButchers()
      finishCharacters(scene)
      knifeRenderer.draw(viewProjection, opaque=true)
      drawWater(
        viewProjection,
        cameraEye,
        unitTime(int32(run.world.tick))
      )

      shapeRenderer.clear()
      shapeRenderer.addLavaBoil(unitTime(int32(run.world.tick)))
      shapeRenderer.addDebugMapOverlays()
      for pudge in run.world.pudges:
        if pudge.hookedBy == 0 or pudge.state == Dying:
          continue
        if not fogShownPudge(pudge):
          continue
        var glow = unitPoint(pudge.id, pudge.position)
        glow.y = surfaceHeightNear(glow.x, glow.z, glow.y) + 0.22'f32
        shapeRenderer.addCircle(glow, GrabGlowRadius, GrabGlow, 14)
      let rotR = RotRadius.float32 / WorldScale.float32
      let rotSeconds = unitTime(int32(run.world.tick))
      let fireR = RuneLightningTrailRadius.float32 / WorldScale.float32
      let fireLife = max(RuneLightningTrailDurationTicks.float32, 1.0'f32)
      for patch in run.world.firePatches:
        var stain = renderPoint(patch.position)
        stain.y = surfaceHeightNear(stain.x, stain.z, stain.y) + 0.14'f32
        shapeRenderer.addFireStain(
          stain,
          fireR,
          patch.ticksLeft.float32 / fireLife,
          rotSeconds + patch.position.x.float32 * 0.00001'f32
        )
      for i in 0 ..< run.world.pudges.len:
        let pudge = predictedPudge(i)
        if pudge.state == Dying or not fogShownPudge(pudge):
          continue
        var feet = unitPoint(pudge.id, pudge.position)
        feet.y = surfaceHeightNear(feet.x, feet.z, feet.y) + 0.16'f32
        if pudge.shieldTicks > 0:
          let remain =
            pudge.shieldTicks.float32 / max(SpawnShieldTicks.float32, 1.0'f32)
          shapeRenderer.addSpawnShield(feet, remain, rotSeconds)
        if pudge.rotOn:
          shapeRenderer.addRotCloud(feet, rotR, rotPulse(pudge), rotSeconds)
        if pudge.rotOn or run.world.rotAffected(pudge):
          let sickPulse = 0.5'f32 + 0.5'f32 * sin(
            rotSeconds * TAU.float32 * 2.0'f32 + pudge.id.float32 * 0.7'f32
          )
          shapeRenderer.addCircle(
            feet,
            1.28'f32 + sickPulse * 0.42'f32,
            fadeRgbx(RotSick, 58.0'f32 + sickPulse * 42.0'f32),
            14
          )
      if run.world.lightningTick > 0:
        let age = int32(run.world.tick) - run.world.lightningTick
        if age >= 0 and age <= TickRate div 3:
          let
            boltR = RuneLightningRadius.float32 / WorldScale.float32
            fade = 1.0'f32 - age.float32 / (TickRate div 3).float32
            pulse = 0.85'f32 + 0.15'f32 * (1.0'f32 - fade)
          var bolt = renderPoint(run.world.lightningPoint)
          bolt.y = surfaceHeightNear(bolt.x, bolt.z, bolt.y) + 0.20'f32
          shapeRenderer.addCircle(
            bolt, boltR * pulse, fadeRgbx(LightningRing, 90.0'f32 * fade), 22
          )
          shapeRenderer.addCircle(
            bolt, boltR * 0.22'f32 * pulse,
            fadeRgbx(LightningFlash, 160.0'f32 * fade),
            14
          )
      block:
        let now = epochTime()
        var kept: seq[BlinkResidue]
        for residue in blinkResidues:
          let age = now - residue.born
          if age < 0 or age >= BlinkResidueSeconds:
            continue
          kept.add residue
          if not fogCanSee(residue.worldOrigin):
            continue
          let
            fade = 1.0'f32 - float32(age / BlinkResidueSeconds)
            grow = float32(age / BlinkResidueSeconds)
            radius = 2.4'f32 + grow * 2.6'f32
          var ground = residue.origin
          ground.y = surfaceHeightNear(ground.x, ground.z, ground.y) + 0.18'f32
          shapeRenderer.addCircle(
            ground,
            radius,
            rgbx(BlinkPuff.r, BlinkPuff.g, BlinkPuff.b, uint8(fade * 100)),
            18
          )
          shapeRenderer.addCircle(
            ground,
            radius * 0.42'f32,
            rgbx(
              BlinkPuffCore.r, BlinkPuffCore.g, BlinkPuffCore.b,
              uint8(fade * 140)
            ),
            14
          )
          var chest = residue.origin
          chest.y = surfaceHeightNear(chest.x, chest.z, chest.y) + 1.55'f32
          shapeRenderer.addCircle(
            chest,
            1.15'f32 + fade * 0.55'f32,
            rgbx(BlinkPuff.r, BlinkPuff.g, BlinkPuff.b, uint8(fade * 70)),
            12
          )
        blinkResidues = kept
      hookRenderer.clear()
      for hook in run.world.hooks:
        if hook.phase == HookIdle:
          continue
        let owner = pudgeIndex(run.world, hook.ownerId)
        if owner < 0:
          continue
        var chain: seq[Vec3]
        let
          ownerPudge = run.world.pudges[owner]
          hasHand = ownerPudge.id in chainHands and fogShownPudge(ownerPudge)
          hand = if hasHand: chainHands[ownerPudge.id]
            else: unitPoint(ownerPudge.id,ownerPudge.position)
        chain.add hand
        for bounce in hook.bounces:
          chain.add renderPoint(bounce)
        let head = hookPoint(hook.id, hook.position)
        chain.add head
        let
          seconds = unitTime(int32(run.world.tick))
          teamColor = if hook.team == WestTeam: WestHook else: EastHook
          headRadius = hook.radius.float32 / WorldScale.float32
        for fragment in clipChainToFog(chain):
          if fragment.len == 0:
            continue
          let dx = fragment[^1].x - head.x
          let dz = fragment[^1].z - head.z
          hookRenderer.drawMeatHook(
            fragment,
            hook.heading,
            hook.phase == HookFlying,
            hook.victimId != 0,
            teamColor,
            seconds + hook.id.float32 * 0.73'f32,
            headRadius,
            showHead = dx * dx + dz * dz < 0.08'f32,
            charged = hook.lightning,
            attachHand = hasHand and lengthSq(fragment[0]-chain[0]) < 0.08'f32,
            handOrigin = hand
          )
      for rune in run.world.runes:
        if not fogCanSee(rune.position):
          continue
        let
          seconds = unitTime(int32(run.world.tick))
          phase = rune.id.float32 * 0.83'f32
        var center = runePoint(rune.id, rune.position)
        let waterY = surfaceHeightNear(center.x, center.z, center.y)
        center.y = waterY + RuneHover +
          sin(seconds * RuneBobRate + phase) * RuneBobAmp
        shapeRenderer.addRiverRune(
          center, waterY, seconds * RuneSpinRate + phase, rune.kind
        )
      let viewTeam = fogTeam()
      for prop in run.world.props:
        if not prop.alive:
          continue
        if viewTeam >= 0 and not propVisibleTo(prop, Team(viewTeam)):
          continue
        if prop.kind == PropWall and not fogCanSee(prop.propCenter):
          continue
        var base = tileCenterRender(int(prop.tileX), int(prop.tileZ))
        base.y = surfaceHeightNear(base.x, base.z, 0)
        if prop.kind == PropWall:
          var wood = base
          wood.y += 0.85'f32
          shapeRenderer.addAxisBox(
            wood, 0.42'f32, 0.85'f32, 0.18'f32, PalisadeWood
          )
          var band = wood
          band.y += 0.12'f32
          shapeRenderer.addAxisBox(
            band, 0.46'f32, 0.10'f32, 0.22'f32, PalisadeBand
          )
          var cap = base
          cap.y += 1.72'f32
          shapeRenderer.addAxisBox(
            cap, 0.44'f32, 0.06'f32, 0.20'f32, PalisadeTop
          )
        elif prop.kind == PropWard:
          var mark = base
          mark.y += 0.08'f32
          shapeRenderer.addObserverWard(mark)
        else:
          var mark = base
          mark.y += 0.08'f32
          shapeRenderer.addLandMine(mark)
      shapeRenderer.addShopOverlays()
      shapeRenderer.drawHumanOverlays(
        window, viewProjection, barRight, barUp
      )
      shapeRenderer.addDebugCollisionOverlays()
      shapeRenderer.draw(viewProjection)
      hookRenderer.draw(viewProjection, opaque=true)

      particles.drawParticles(
        viewProjection, barRight, barUp, cameraForward
      )
      worldBarRenderer.clear()
      for pudge in run.world.pudges:
        if pudge.state == Dying or pudge.justBlinked or not fogShownPudge(pudge):
          continue
        var pos = unitPoint(pudge.id, pudge.position)
        pos.y = surfaceHeightNear(pos.x, pos.z, pos.y) + ButcherBarLift
        worldBarRenderer.addResourceBars(
          pos,
          ButcherBarWidth,
          [
            WorldResourceBar(
              value: max(pudge.hp, 0).float32,
              maximum: max(pudge.maxHp, 1).float32,
              delayedValue: max(pudge.hp, 0).float32,
              height: 0.12'f32,
              color: pudgeHpColor(pudge),
              showDamageTrail: true
            )
          ]
        )
      let barViewTeam = fogTeam()
      for prop in run.world.props:
        if not prop.alive or prop.kind != PropWall:
          continue
        if not fogCanSee(prop.propCenter):
          continue
        if barViewTeam >= 0 and not propVisibleTo(prop, Team(barViewTeam)):
          continue
        var barPos = tileCenterRender(int(prop.tileX), int(prop.tileZ))
        barPos.y = surfaceHeightNear(barPos.x, barPos.z, 0) + PalisadeBarLift
        worldBarRenderer.addResourceBars(
          barPos,
          PalisadeBarWidth,
          [
            WorldResourceBar(
              value: max(prop.hp, 0).float32,
              maximum: max(prop.maxHp, 1).float32,
              delayedValue: max(prop.hp, 0).float32,
              height: 0.08'f32,
              color: PalisadeWood,
              showDamageTrail: true
            )
          ]
        )
      worldBarRenderer.draw(viewProjection, barRight, barUp)
      profilePop()

      let captureHud =
        when defined(takeScreenshot): getEnv("SCREENSHOT_HUD") == "1"
        else: true
      if not captureHud:
        when defined(takeScreenshot):
          captureScreenshot(
            window,
            screenshotFrame,
            24,
            "examples/pudge_wars/pw_shot.png"
          )
        profileBlock "present":
          window.present(framePaceHz)
        return
      profilePush("ui")
      glDisable(GL_DEPTH_TEST)
      glDisable(GL_CULL_FACE)
      glDisable(GL_BLEND)
      glViewport(0, 0, window.size.x.GLsizei, window.size.y.GLsizei)
      when not defined(emscripten):
        glDisable(GL_MULTISAMPLE)
      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, sk.atlasTextureId())
      sk.beginUi(window, window.size)
      # Silky has no z-index: later draw calls win. Strict back → front:
      # world-space 2D, HUD chrome (inside drawUi), then modal overlays
      # (also inside drawUi), then net lobby / banner on top.
      block:
        # Rising combat numbers, anchored to the world through the HUD.
        let now = epochTime()
        var kept: seq[FloatingText]
        for text in floatingTexts:
          let age = now - text.born
          if age > 0.9:
            continue
          kept.add text
          let
            lifted = text.world +
              vec3(0, 3.2'f32 + float32(age) * 2.4'f32, 0)
            screen = screenPoint(lifted, viewProjection) / sk.uiScale
            fade = uint8(clamp(255.0 - age / 0.9 * 255.0, 0.0, 255.0))
          sk.drawLabel(
            text.text,
            screen - vec2(44, 9),
            vec2(88, 18),
            rgbx(text.color.r, text.color.g, text.color.b, fade),
            "Hud",
            CenterAlign
          )
        floatingTexts = kept
      block:
        # Nameplates: small shadowed type over the HP bar, no plate.
        let spectateSlot = spectateIndex()
        for slot in 0 ..< run.world.pudges.len:
          let pudge = predictedPudge(slot)
          if pudge.state == Dying or pudge.justBlinked:
            continue
          if not run.replayMode and not fogShownPudge(pudge):
            continue
          var label = butcherDisplayName(slot)
          if label.len == 0:
            label = "P" & $pudge.id
          if pudge.shieldTicks > 0:
            label = "SHIELD  " & label
          if slot == spectateSlot:
            label = "EYES  " & label
          var anchor = unitPoint(pudge.id, pudge.position)
          anchor.y = surfaceHeightNear(anchor.x, anchor.z, anchor.y) +
            NamePlateLift
          let screen = screenPoint(anchor, viewProjection) / sk.uiScale
          if screen.x < -4000:
            continue
          let
            plate = vec2(NamePlateW, NamePlateH)
            origin = screen - plate * 0.5'f32
            textColor =
              if pudge.shieldTicks > 0: SpawnShieldName
              elif slot == spectateSlot: NamePlateEyes
              else: NamePlateText
          sk.drawLabel(
            label, origin + vec2(1, 1), plate, NamePlateShadow, "Small",
            CenterAlign
          )
          sk.drawLabel(
            label, origin, plate, textColor, "Small", CenterAlign
          )
      block:
        # Team pings: a screen-space ! so the mark stays readable at any
        # zoom, stacked on the world-space billboard.
        for marker in pingMarkers():
          var anchor = tileCenterRender(int(marker.tileX), int(marker.tileZ))
          anchor.y = surfaceHeightNear(anchor.x, anchor.z, 0) + 1.85'f32
          let
            bounce =
              if marker.age < 0.7:
                8.0'f32 * sin(float32(marker.age) * 14.0'f32) *
                  (1.0'f32 - float32(marker.age) / 0.7'f32)
              else:
                0.0'f32
            screen = screenPoint(anchor, viewProjection) / sk.uiScale -
              vec2(0, bounce)
            fade = uint8(clamp(
              255.0 * (1.0 - marker.age / PingOverlaySeconds), 0.0, 255.0
            ))
            plate = vec2(36, 48)
            origin = screen - plate * 0.5'f32
          if screen.x < -4000:
            continue
          sk.drawLabel(
            "!", origin + vec2(1, 1), plate,
            rgbx(40, 24, 8, fade), "H1", CenterAlign
          )
          sk.drawLabel(
            "!", origin, plate,
            rgbx(PingGold.r, PingGold.g, PingGold.b, fade),
            "H1", CenterAlign
          )
      block:
        let pick = groundUnderMouse(window, viewProjection)
        debugHoverFound = pick.found
        if pick.found:
          let tile = tileOfGround(pick.point)
          debugHoverX = int(tile.x)
          debugHoverZ = int(tile.y)
      if showTiles:
        let labelColor = rgbx(236, 232, 210, 220)
        for z in countup(PlayZMin, PlayZMax, DebugTileLabelStep):
          for x in countup(PlayWestMin, PlayEastMax, DebugTileLabelStep):
            let
              world = liftPoint(tileCenterRender(x, z), 0.4'f32)
              screen = screenPoint(world, viewProjection) / sk.uiScale
            if screen.x < -40 or screen.y < -20 or
                screen.x > window.size.x.float32 / sk.uiScale + 40:
              continue
            hudScratch.setLen(0)
            hudScratch.addHudInt(x)
            hudScratch.add ','
            hudScratch.addHudInt(z)
            sk.drawLabel(
              hudScratch,
              screen - vec2(22, 7),
              vec2(44, 14),
              labelColor,
              "Small",
              CenterAlign
            )
        if debugHoverFound:
          let
            world = liftPoint(
              tileCenterRender(debugHoverX, debugHoverZ), 0.55'f32
            )
            screen = screenPoint(world, viewProjection) / sk.uiScale
          hudScratch.setLen(0)
          hudScratch.addHudInt(debugHoverX)
          hudScratch.add ','
          hudScratch.addHudInt(debugHoverZ)
          sk.drawLabel(
            hudScratch,
            screen - vec2(36, 10),
            vec2(72, 18),
            rgbx(255, 230, 120, 255),
            "Hud",
            CenterAlign
          )
      drawUi(
        sk,
        window,
        transport,
        cameraTarget,
        cameraDistance,
        actionCam,
        followSelection,
        cameraEye
      )
      # IME only while the chat draft has focus. Left on during play,
      # macOS's accent popup on held A swallows the key-up and the
      # butcher walks west until A is tapped again.
      window.runeInputEnabled = chatTyping()
      when not defined(emscripten):
        if netLobbyOpen:
          sk.drawNetLobby(
            window, hostSeatRoster(), hostingUrl(), localClaim
          )
      if netRole == NetClient:
        sk.drawNetBanner(window, netStatusLine())
        let fpsNow = int(fpsSmoothed + 0.5'f32)
        let screenH = window.size.y.float32 / sk.uiScale
        if netDebugPanel:
          # Full developer panel: configured vs measured latency, jitter,
          # loss, per-direction packet counters, queue depth, the constant
          # sim tick rate (decoupled from latency), and a rolling ping graph.
          let nc = netSimConfig()
          let so = netSimStats(DirOutbound)
          let si = netSimStats(DirInbound)
          const PanelW = 272.0'f32
          const PanelH = 142.0'f32
          let px = 8.0'f32
          let py = screenH - PanelH - 6
          sk.drawRect(vec2(px, py), vec2(PanelW, PanelH), rgbx(20, 22, 28, 205))
          let txt = rgbx(236, 232, 210, 235)
          var ly = py + 5
          template row(s: string) =
            sk.drawLabel(s, vec2(px + 8, ly), vec2(PanelW - 16, 14), txt,
              "Hud", LeftAlign)
            ly += 15
          hudScratch.setLen(0)
          hudScratch.add(if nc.enabled: "NETSIM " else: "NETSIM off ")
          if nc.enabled:
            hudScratch.add netSimLabel()
            hudScratch.add "  cfg "
          else:
            hudScratch.add "cfg "
          hudScratch.addHudInt(nc.latencyMs)
          hudScratch.add "+/-"
          hudScratch.addHudInt(nc.jitterMs)
          hudScratch.add "ms loss "
          hudScratch.addHudInt(int(nc.packetLossPercent + 0.5))
          hudScratch.add "%"
          row(hudScratch)
          hudScratch.setLen(0)
          hudScratch.add "ping "
          if netPingKnown(): hudScratch.addHudInt(netPingMs())
          else: hudScratch.add "--"
          hudScratch.add "ms jit "
          hudScratch.addHudInt(netPingJitterMs())
          hudScratch.add "  sim "
          hudScratch.addHudInt(int(TickRate))
          hudScratch.add "Hz fps "
          hudScratch.addHudInt(fpsNow)
          row(hudScratch)
          hudScratch.setLen(0)
          when defined(emscripten):
            if predictor.enabled:
              hudScratch.add "pred lead "
              hudScratch.addHudInt(predictor.lead)
              hudScratch.add "/"
              hudScratch.addHudInt(int(MaxLead))
              hudScratch.add " pend "
              hudScratch.addHudInt(predictor.pending.len)
              hudScratch.add " snap "
              hudScratch.addHudInt(predictor.snapCount)
            else:
              hudScratch.add "pred idle"
          else:
            hudScratch.add "pred off (use browser)"
          row(hudScratch)
          hudScratch.setLen(0)
          hudScratch.add "out snt "
          hudScratch.addHudInt(so.offered)
          hudScratch.add " dly "
          hudScratch.addHudInt(so.delayed)
          hudScratch.add " drp "
          hudScratch.addHudInt(so.dropped)
          hudScratch.add " q "
          hudScratch.addHudInt(so.queueDepth)
          row(hudScratch)
          hudScratch.setLen(0)
          hudScratch.add "in  rcv "
          hudScratch.addHudInt(si.offered)
          hudScratch.add " dly "
          hudScratch.addHudInt(si.delayed)
          hudScratch.add " drp "
          hudScratch.addHudInt(si.dropped)
          hudScratch.add " q "
          hudScratch.addHudInt(si.queueDepth)
          row(hudScratch)
          # Rolling ping graph.
          let hist = netPingHistory()
          let gx = px + 8
          let gy = ly + 2
          const Gh = 26.0'f32
          let gw = PanelW - 16
          sk.drawRect(vec2(gx, gy), vec2(gw, Gh), rgbx(40, 44, 52, 190))
          if hist.len > 0:
            var mx = 1
            for v in hist: mx = max(mx, v)
            let bw = gw / float32(PingHistoryCap)
            for i in 0 ..< hist.len:
              let h = Gh * clamp(float32(hist[i]) / float32(mx), 0.03'f32, 1.0'f32)
              sk.drawRect(
                vec2(gx + float32(i) * bw, gy + Gh - h),
                vec2(max(bw - 1.0'f32, 1.0'f32), h),
                rgbx(120, 200, 140, 220))
          sk.drawLabel("F6 panel  F7 preset  F3 sliders", vec2(gx, gy + Gh + 1),
            vec2(gw, 12), rgbx(150, 150, 150, 200), "Hud", LeftAlign)
        else:
          # Compact readout: host round-trip ping (ms) and render FPS.
          hudScratch.setLen(0)
          hudScratch.add "PING "
          if netPingKnown(): hudScratch.addHudInt(netPingMs())
          else: hudScratch.add "--"
          hudScratch.add "ms  FPS "
          hudScratch.addHudInt(fpsNow)
          sk.drawLabel(hudScratch, vec2(10, screenH - 24), vec2(220, 18),
            rgbx(236, 232, 210, 220), "Hud", LeftAlign)
      sk.endUi()
      profilePop()
      when defined(takeScreenshot):
        captureScreenshot(
          window,
          screenshotFrame,
          24,
          "examples/pudge_wars/pw_shot.png"
        )
      profileBlock "present":
        window.present(framePaceHz)
    if noteProfileFrame():
      when not defined(emscripten):
        window.closeRequested = true

  while not window.closeRequested:
    pollEvents()

  when not defined(emscripten):
    if netRole == NetHost:
      stopHosting("the host closed the game")
  if netRole == NetClient:
    netShutdown()
  flushBugTapeIfArmed()
  closeDuelLogging()
  if not run.replayMode:
    saveRecording()
  closeGameAudio()
  particles.closeParticles()
  finishProfileTrace()
