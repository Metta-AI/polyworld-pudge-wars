## Read-only team planning. These checks choose bot actions; they never
## change hook collision, human controls, fog, or the replay rules.
import polyworld/[fixed, pathing], content, sim

const TeamPingTicks* = TickRate * 3

proc canThrowHook*(world: World, pudge: Pudge): bool =
  if pudge.state != Alive or pudge.hookCooldown > 0 or pudge.windupTicks > 0:
    return false
  for hook in world.hooks:
    if hook.ownerId == pudge.id and hook.phase != HookIdle:
      return false
  true

proc friendlyHookLaneClear*(
    world: World, pudgeId, mapX, mapY: int32, rescueId = 0'i32
): bool =
  ## Conservative straight-line check through the aimed point, not an
  ## omniscient trajectory predictor. Include the launch disk and a short
  ## teammate velocity projection during windup. Bounces/late movement can
  ## still intercept a throw; that is measured by the full-match audit.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or mapX < 0 or mapY < 0 or mapX >= GridTiles or mapY >= GridTiles:
    return false
  let
    caster = world.pudges[index]
    aim = worldAtTile(int(mapX), int(mapY))
    dx = int64(aim.x) - caster.position.x
    dz = int64(aim.z) - caster.position.z
    span = integerSqrt(distanceSquared(aim, caster.position))
  if span == 0: return false
  var
    reach = hookRange(caster.upgrades[UpgradeDistance])
    radius = hookRadius(caster.upgrades[UpgradeRadius])
  if caster.hasBuff(RuneBigHook):
    reach += reach * RuneBigHookPercent div 100
    radius += radius * RuneBigHookPercent div 100
  let
    endDistance = min(span, int64(reach))
    start = WorldPoint(
      x: caster.position.x + int32(dx * (WorldScale div 2) div span),
      z: caster.position.z + int32(dz * (WorldScale div 2) div span))
    finish = WorldPoint(
      x: caster.position.x + int32(dx * endDistance div span),
      z: caster.position.z + int32(dz * endDistance div span))
    clearance = radius + PudgeCollisionRadius + WorldScale div 2
  for ally in world.pudges:
    if ally.id in [pudgeId, rescueId] or ally.team != caster.team or
        ally.state != Alive or ally.shieldTicks > HookWindupTicks:
      continue
    if segmentPointWithin(start, finish, ally.position, clearance):
      return false
    let soon = WorldPoint(
      x: ally.position.x + ally.velX * 4,
      z: ally.position.z + ally.velZ * 4)
    if segmentPointWithin(start, finish, soon, clearance):
      return false
  true

proc needsRescue*(world: World, ally: Pudge): bool =
  if ally.state != Alive or ally.shieldTicks > 0:
    return false
  if ally.hookedBy != 0:
    let owner = world.pudgeIndex(ally.hookedBy)
    # A teammate is already bringing them home. Do not steal that rescue.
    return owner >= 0 and world.pudges[owner].team != ally.team
  if not ally.inRiver: return false
  if ally.hp * 100 <= ally.maxHp * 60: return true
  # A healthy human may be wading deliberately to contest a rune. A fresh
  # ping at their own position is an explicit request to pull them out.
  var ping: Ping
  world.latestTeamPing(ally.team, ping) and ping.byId == ally.id and
    world.tick >= ping.tick and world.tick - ping.tick < TeamPingTicks and
    distanceSquared(worldAtTile(int(ping.x), int(ping.y)), ally.position) <=
      int64(WorldScale * 4) * (WorldScale * 4)

proc mayRescueAlly*(world: World, pudgeId, allyId: int32): bool =
  let
    casterIndex = world.pudgeIndex(pudgeId)
    allyIndex = world.pudgeIndex(allyId)
  if casterIndex < 0 or allyIndex < 0 or casterIndex == allyIndex:
    return false
  let
    caster = world.pudges[casterIndex]
    ally = world.pudges[allyIndex]
  if ally.team != caster.team or not world.needsRescue(ally) or
      not world.canThrowHook(caster) or caster.hookedBy != 0 or
      caster.layer != int32(caster.team.ord) or world.rotAffected(caster):
    return false
  # Claim only while actually winding up/flying the rescue, not through a
  # stale global reservation that could survive death or a human takeover.
  for other in world.pudges:
    if other.id == pudgeId or other.team != caster.team or other.state != Alive:
      continue
    var committed = other.windupTicks > 0 and not other.windupGrapple
    for hook in world.hooks:
      if hook.ownerId == other.id and hook.phase == HookFlying and not hook.isGrapple:
        committed = true
    if committed:
      let aim = worldAtFine(other.windupAimX, other.windupAimY)
      if distanceSquared(aim, ally.position) <=
          int64(PudgeCollisionRadius) * PudgeCollisionRadius:
        return false
  let at = tileOf(ally.position)
  var reach = hookRange(caster.upgrades[UpgradeDistance])
  if caster.hasBuff(RuneBigHook):
    reach += reach * RuneBigHookPercent div 100
  if distanceSquared(caster.position, ally.position) > int64(reach) * reach:
    return false
  world.friendlyHookLaneClear(pudgeId, int32(at.x), int32(at.z), allyId)

proc teamPingResponder*(game: Game, team: Team): int32 =
  ## One healthy, free bot covers a fresh teammate call. Decisions remain
  ## independent of private enemy state and tie-break by stable player id.
  var ping: Ping
  if not game.world.latestTeamPing(team, ping) or
      game.world.tick < ping.tick or game.world.tick - ping.tick >= TeamPingTicks:
    return 0
  let target = worldAtTile(int(ping.x), int(ping.y))
  var best = int64.high
  for i, pudge in game.world.pudges:
    if i in game.humanSlots or i >= game.heroVms.len or
        game.heroVms[i] == nil or game.heroVms[i].failed or
        pudge.id == ping.byId or pudge.team != team or pudge.state != Alive or
        pudge.hookedBy != 0 or pudge.inRiver or
        pudge.hp * 100 < pudge.maxHp * 40 or game.world.rotAffected(pudge):
      continue
    var holdingRescue = false
    for hook in game.world.hooks:
      if hook.ownerId == pudge.id and hook.phase == HookReeling:
        let victim = game.world.pudgeIndex(hook.victimId)
        if victim >= 0 and game.world.pudges[victim].team == team:
          holdingRescue = true
    if holdingRescue: continue
    let distance = distanceSquared(pudge.position, target)
    if distance < best or (distance == best and pudge.id < result):
      best = distance
      result = pudge.id
