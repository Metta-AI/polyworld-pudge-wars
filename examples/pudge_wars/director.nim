## Director camera: scores live Fresh Meat situations so the shared
## action camera can cut to hooks, fights, and kills like a broadcast.
##
## Scores sit on the action-cam ladder in `actioncam.nim`: idle shots
## need 12, a cut after the hold needs 40, and 140 interrupts immediately.

import
  vmath,
  polyworld/actioncam,
  content, fog, sim

const
  LiveTicks = 4'i32
    ## Ongoing notes (a flying hook, a living butcher) refresh each frame.
  SpikeTicks = TickRate * 3
    ## One-tick events hold a shot for three seconds.
  FightTiles = 14'i32
  HookThreatTiles = 16'i32
  RuneTiles = 10'i32
  ScoreIdle = 16.0'f32
  ScoreRiver = 28.0'f32
  ScoreRot = 34.0'f32
  ScoreLowHp = 44.0'f32
  ScoreFight = 58.0'f32
  ScoreWindup = 64.0'f32
  ScoreRune = 70.0'f32
  ScoreBlink = 82.0'f32
  ScoreDamage = 90.0'f32
  ScoreHookFly = 98.0'f32
  ScoreHookThreat = 118.0'f32
  ScoreReel = 150.0'f32
  ScoreClash = 158.0'f32
  ScoreLatch = 168.0'f32
  ScoreDeath = 184.0'f32
  ScoreHeadshot = 200.0'f32
  IdKill = 20_000'i32
  IdLatch = 21_000'i32
  IdBlink = 22_000'i32
  IdClash = 30_000'i32
  IdChunk = 30_001'i32

proc worldVec(point: WorldPoint): Vec3 =
  vec3(
    point.x.float32 / WorldScale.float32,
    point.y.float32 / WorldScale.float32,
    point.z.float32 / WorldScale.float32
  )

proc withinTiles(a, b: WorldPoint, tiles: int32): bool =
  let reach = int64(tiles) * WorldScale
  distanceSquared(a, b) <= reach * reach

proc note(
    cam: var ActionCam,
    id: int32,
    point: WorldPoint,
    score, radius: float32,
    tick, lastTicks: int32
) =
  cam.noteInterest(id, worldVec(point), score, radius, tick, lastTicks)

proc enemyNearby(world: World, pudge: Pudge, tiles: int32): bool =
  for other in world.pudges:
    if other.id == pudge.id or other.team == pudge.team or
        other.state != Alive:
      continue
    if pudge.position.withinTiles(other.position, tiles):
      return true
  false

proc hookThreat(world: World, hook: Hook): bool =
  for pudge in world.pudges:
    if pudge.team == hook.team or pudge.state != Alive:
      continue
    if hook.position.withinTiles(pudge.position, HookThreatTiles):
      return true
  false

proc runeContest(world: World, pudge: Pudge): bool =
  for rune in world.runes:
    if pudge.position.withinTiles(rune.position, RuneTiles):
      return true
  false

proc liveScore(world: World, pudge: Pudge): float32 =
  ## Ongoing presence: idle butchers through river fights and wind-ups.
  result = ScoreIdle
  if pudge.inRiver:
    result = max(result, ScoreRiver)
  if pudge.rotOn:
    result = max(result, ScoreRot)
  if pudge.maxHp > 0 and pudge.hp * 100 <= pudge.maxHp * 35:
    result = max(result, ScoreLowHp)
  if pudge.windupTicks > 0:
    result = max(result, ScoreWindup)
  if pudge.hookedBy != 0:
    result = max(result, ScoreReel)
  if pudge.damageLanded:
    result = max(result, ScoreDamage)
  if world.enemyNearby(pudge, FightTiles):
    result = max(result, ScoreFight)
  if world.runeContest(pudge):
    result = max(result, ScoreRune)

proc feedDirectorCam*(
    cam: var ActionCam,
    world: World,
    visionTeam: int
) =
  ## Notes this tick's broadcast-worthy situations. Hidden fog stays off
  ## camera so a seated player is not yanked onto the dark bank.
  let tick = world.tick
  for pudge in world.pudges:
    if not fogShownPudgeTeam(world, visionTeam, pudge):
      continue
    if pudge.state == Alive:
      cam.note(
        pudge.id, pudge.position, world.liveScore(pudge), 5.0'f32,
        tick, LiveTicks
      )
    elif pudge.deathTicks > RespawnTicks - TickRate * 2:
      cam.note(
        IdKill + pudge.id, pudge.position, ScoreDeath, 6.0'f32,
        tick, SpikeTicks
      )
    if pudge.justHeadshot:
      cam.note(
        IdKill + pudge.id, pudge.position, ScoreHeadshot, 6.0'f32,
        tick, SpikeTicks
      )
    if pudge.justChunked or pudge.justFirstBlood or pudge.justMulti >= 2:
      cam.note(
        IdKill + pudge.id, pudge.position, ScoreDeath, 6.5'f32,
        tick, SpikeTicks
      )
    if pudge.justBlinked:
      cam.note(
        IdBlink + pudge.id, pudge.blinkFrom, ScoreBlink, 5.0'f32,
        tick, SpikeTicks
      )
    if pudge.justGrabbed:
      var latchAt = pudge.position
      for other in world.pudges:
        if other.hookedBy == pudge.id:
          latchAt = other.position
          break
      cam.note(
        IdLatch + pudge.id, latchAt, ScoreLatch, 7.0'f32,
        tick, SpikeTicks
      )
  for hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if not fogCanSeeTeam(world, visionTeam, hook.position):
      continue
    if hook.phase == HookFlying:
      let score =
        if world.hookThreat(hook): ScoreHookThreat
        else: ScoreHookFly
      cam.note(hook.id, hook.position, score, 10.0'f32, tick, LiveTicks)
    else:
      var reelAt = hook.position
      if hook.victimId != 0:
        let victim = world.pudgeIndex(hook.victimId)
        if victim >= 0:
          reelAt = world.pudges[victim].position
      cam.note(hook.id, reelAt, ScoreReel, 8.0'f32, tick, LiveTicks)
  if world.clashTick > 0 and world.tick - world.clashTick <= TickRate and
      fogCanSeeTeam(world, visionTeam, world.clashPoint):
    cam.note(
      IdClash, world.clashPoint, ScoreClash, 8.0'f32, tick, SpikeTicks
    )
  if world.chunkTick > 0 and world.tick - world.chunkTick <= TickRate:
    let victim = world.pudgeIndex(world.chunkVictimId)
    if victim >= 0 and
        fogShownPudgeTeam(world, visionTeam, world.pudges[victim]):
      cam.note(
        IdChunk, world.pudges[victim].position, ScoreDeath, 7.0'f32,
        tick, SpikeTicks
      )
  for rune in world.runes:
    if not fogCanSeeTeam(world, visionTeam, rune.position):
      continue
    cam.note(rune.id, rune.position, ScoreIdle + 4.0'f32, 4.0'f32, tick, LiveTicks)
