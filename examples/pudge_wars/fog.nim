## Team-shared fog of war. Presentation and bot observations share
## these rules: the whole home bank and the river stay lit. The enemy
## bank needs a living teammate or team ward within `SightRadiusTiles`,
## a tile in the padded corridor along an in-flight team hook, or a
## tile inside a team Lightning fire trail. The hashed sim physics
## stay omniscient.

import
  polyworld/[pathing, profiles],
  content, maps, sim

export fogTeamOf, fogBaseVisible, fogCanSeeTeam, fogShownPudgeTeam

proc stampSightCircle(values: var seq[uint8], position: WorldPoint) =
  let
    r = SightRadiusTiles
    r2 = r * r
    (px, pz) = tileOf(position)
  for dz in -r .. r:
    let tz = pz + dz
    if tz < 0 or tz >= GridTiles:
      continue
    let row = tz * GridTiles
    for dx in -r .. r:
      if dx * dx + dz * dz > r2:
        continue
      let tx = px + dx
      if tx < 0 or tx >= GridTiles:
        continue
      values[row + tx] = 255

proc stampSightCorridor(values: var seq[uint8], a0, a1: WorldPoint) =
  ## Lights every tile whose center sits within `HookSightPadTiles` of
  ## segment `a0`–`a1`. Bounding box first, then the same capsule test
  ## `fogCanSeeTeam` uses so stamp and scan stay identical.
  let
    pad = int(HookSightPadTiles)
    padWorld = HookSightPadTiles * WorldScale
    (x0, z0) = tileOf(a0)
    (x1, z1) = tileOf(a1)
    minX = max(0, min(x0, x1) - pad)
    maxX = min(GridTiles - 1, max(x0, x1) + pad)
    minZ = max(0, min(z0, z1) - pad)
    maxZ = min(GridTiles - 1, max(z0, z1) + pad)
  for z in minZ .. maxZ:
    let row = z * GridTiles
    for x in minX .. maxX:
      if segmentPointWithin(a0, a1, worldAtTile(x, z), padWorld):
        values[row + x] = 255

proc stampFireTrail(values: var seq[uint8], position: WorldPoint) =
  ## Lights every tile whose center sits within `RuneLightningTrailRadius`
  ## of this patch. Same disk `fogCanSeeTeam` uses so stamp and scan match.
  let
    rWorld = RuneLightningTrailRadius
    r2 = int64(rWorld) * int64(rWorld)
    pad = (int(rWorld) + int(WorldScale) - 1) div int(WorldScale)
    (px, pz) = tileOf(position)
  for dz in -pad .. pad:
    let tz = pz + dz
    if tz < 0 or tz >= GridTiles:
      continue
    let row = tz * GridTiles
    for dx in -pad .. pad:
      let tx = px + dx
      if tx < 0 or tx >= GridTiles:
        continue
      if distanceSquared(worldAtTile(tx, tz), position) <= r2:
        values[row + tx] = 255

proc fillTeamVision*(
    world: World, team: int, values: var seq[uint8]
) {.measure.} =
  ## Paints a 128×128 mask: 255 visible, 0 dark. `team < 0` is omniscient.
  ## Home bank (including the fountain bulge) and river water are
  ## sequential fills; living teammates
  ## and team wards stamp a Euclidean circle of `SightRadiusTiles`;
  ## in-flight team hooks stamp a padded polyline; team Lightning fire
  ## trails stamp the same burn disk the sim scans.
  let n = GridTiles * GridTiles
  if values.len != n:
    values.setLen(n)
  if team < 0:
    for i in 0 ..< n:
      values[i] = 255
    return
  for i in 0 ..< n:
    values[i] = 0
  let west = team == WestTeam.ord
  for z in 0 ..< GridTiles:
    let row = z * GridTiles
    for x in 0 ..< GridTiles:
      if riverTile(x, z):
        values[row + x] = 255
      elif west and x < RiverCenterX:
        values[row + x] = 255
      elif not west and x > RiverCenterX:
        values[row + x] = 255
  for origin in fogSightOrigins(world, team):
    stampSightCircle(values, origin)
  for hook in world.hooks:
    if hook.team.ord != team or hook.phase == HookIdle:
      continue
    for segment in hookSightSegments(world, hook):
      stampSightCorridor(values, segment.a0, segment.a1)
  for patch in world.firePatches:
    if patch.team.ord != team:
      continue
    stampFireTrail(values, patch.position)
