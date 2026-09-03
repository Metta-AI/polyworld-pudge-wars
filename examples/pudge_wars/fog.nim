## Presentation-only fog of war. Bots and the hashed sim ignore this.
##
## Team-shared sight: the whole home bank and the river stay lit. The
## enemy bank needs a living teammate within `SightRadiusTiles`. Hooks
## do not scout.

import content, maps, sim

proc fogTeamOf*(world: World, pudgeId: int32): int =
  ## Team ordinal a spectator inherits from this butcher, or -1 if the
  ## id is missing (omniscient fallback).
  let index = pudgeIndex(world, pudgeId)
  if index < 0:
    return -1
  world.pudges[index].team.ord

proc fogBaseVisible*(team: int, position: WorldPoint): bool =
  ## Your base is your entire home bank: the whole friendly side up to
  ## the river stays lit. The enemy bank gets no such courtesy.
  let (tx, _) = tileOf(position)
  if team == WestTeam.ord:
    tx <= PlayWestMax
  else:
    tx >= PlayEastMin

proc fogCanSeeTeam*(world: World, team: int, position: WorldPoint): bool =
  ## Whether `team` currently lights `position`. `team < 0` is omniscient.
  if team < 0:
    return true
  let (tx, _) = tileOf(position)
  if riverTile(tx):
    return true
  if fogBaseVisible(team, position):
    return true
  let radius = int64(SightRadiusTiles) * WorldScale
  for pudge in world.pudges:
    if pudge.team.ord != team or pudge.state == Dying:
      continue
    if distanceSquared(pudge.position, position) <= radius * radius:
      return true
  false

proc fogShownPudgeTeam*(world: World, team: int, pudge: Pudge): bool =
  ## Own team always shows; enemies only inside the shared sight.
  team < 0 or pudge.team.ord == team or
    fogCanSeeTeam(world, team, pudge.position)
