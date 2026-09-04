## Team-shared fog of war. Presentation and bot observations share
## these rules: the whole home bank and the river stay lit. The enemy
## bank needs a living teammate within `SightRadiusTiles`. Hooks do
## not scout. The hashed sim physics stay omniscient.

import
  polyworld/[pathing, profiles],
  content, maps, sim

export fogTeamOf, fogBaseVisible, fogCanSeeTeam, fogShownPudgeTeam

proc fillTeamVision*(
    world: World, team: int, values: var seq[uint8]
) {.measure.} =
  ## Paints a 128×128 mask: 255 visible, 0 dark. `team < 0` is omniscient.
  ## Home bank and river are sequential column fills; living teammates
  ## stamp a Euclidean circle of `SightRadiusTiles`.
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
    if west:
      for x in 0 .. PlayWestMax:
        values[row + x] = 255
    else:
      for x in PlayEastMin ..< GridTiles:
        values[row + x] = 255
    for x in RiverWestX .. RiverEastX:
      values[row + x] = 255
  let r = SightRadiusTiles
  let r2 = r * r
  for pudge in world.pudges:
    if pudge.team.ord != team or pudge.state == Dying:
      continue
    let (px, pz) = tileOf(pudge.position)
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
