## Structured match logging for the duel improvement loop.
##
## Observes the finished state of every simulation tick and writes a
## stream of JSON events plus an end-of-match summary, so an outside
## agent (a human, a script, or Claude) can study exactly how a match
## was won or lost and improve a bot policy between games.
##
## Files written under one match directory:
##   events.jsonl   one JSON object per line, every notable event
##   summary.json   aggregate stats, per-hook records, kill timeline
##   replay.pwr     the action tape (written by the game, not here)
## A rolling `history.jsonl` beside the match directories gets one
## summary line per finished match for cross-match trend analysis.
##
## The logger is an observer: it never mutates the world, so replays,
## hashes, and determinism are untouched. Re-simulated ticks (history
## seeks) are skipped by a monotonic tick guard.

import
  std/[json, math, os, strutils, tables, times],
  polyworld/[pathing, tapes],
  content,
  maps,
  replays,
  sim

const
  SampleEveryTicks* = 8'i32
    ## Cadence of `state` snapshot events: 4 per second at 32 Hz.
  WalkLogSpacingTicks = 16'i32
    ## Identical repeated walk/attack orders are coalesced inside this
    ## window so bot decision spam does not drown the event stream.
  UpgradeKeys: array[UpgradeKind, string] = [
    "damage", "distance", "speed", "radius"
  ]
  RuneKeys: array[RuneKind, string] = [
    "haste", "double_damage", "regen", "big_hook"
  ]
  DistanceBands = ["0-15", "15-30", "30-45", "45+"]

type
  HookTrack = object
    hookId: int32
    ownerId: int32
    team: Team
    launchTick: int32
    origin: WorldPoint
    aimFineX, aimFineY: int32
    targetId: int32
    targetPos: WorldPoint
    targetDist: float
    victimId: int32
    grabTick: int32
    damage: int32
    closestId: int32
    closestDist: float
    closestHookPos: WorldPoint
    closestEnemyPos: WorldPoint
    traveled: int32

  LastOrder = object
    kind: uint8
    a, b: int32
    tick: int32

  PlayerAgg = object
    id: int32
    damageDealt: Table[string, int32]
    damageTaken: Table[string, int32]
    riverTicks: int32
    hookBands: Table[string, (int, int)]
      ## Distance band -> (landed, thrown), from resolved hook records.
    aimedAtMe: int
    hitMe: int
    dodged: int
    movedSum: float
    movedCount: int

  DuelLogger* = ref object
    dir*: string
    finished*: bool
    events: File
    startedAt: string
    startWall: float64
    label: string
    seatScripts: seq[string]
    lastLoggedTick: int32
    lastActionIndex: int
    sawGameOver: bool
    # Previous-tick state, indexed by roster order.
    prevHp: seq[int32]
    prevState: seq[PudgeState]
    prevLayer: seq[int32]
    prevSpent: seq[int32]
    prevUpgrades: seq[array[UpgradeKind, int32]]
    prevRunesTaken: seq[int32]
    prevPoints: seq[int32]
    lastOrders: Table[int32, LastOrder]
    hookTracks: OrderedTable[int32, HookTrack]
    hookRecords: seq[JsonNode]
    killRecords: seq[JsonNode]
    aggs: seq[PlayerAgg]
    firstBloodId: int32
    wroteThisTick: bool

proc fnv1a*(data: string): string =
  ## Stable content fingerprint for policy files.
  var h = 0xcbf29ce484222325'u64
  for c in data:
    h = (h xor uint64(ord(c))) * 0x100000001b3'u64
  h.toHex(16).toLowerAscii()

proc tileF(value: int32): float =
  ## World axis value -> map tile coordinate as a float (0 .. 128).
  round((value.float / WorldScale.float + float(GridTiles div 2)) * 100) / 100

proc fineF(value: int32): float =
  ## Fine-aim (1/256 tile) value -> map tile coordinate.
  round(value.float / FineAimScale.float * 100) / 100

proc tilesPerSec(value: int32): float =
  ## World units per tick -> tiles per second.
  round(value.float * TickRate.float / WorldScale.float * 100) / 100

proc secOf(tick: int32): float =
  round(tick.float / TickRate.float * 10) / 10

proc jpos(point: WorldPoint): JsonNode =
  %[tileF(point.x), tileF(point.z)]

proc distTiles(a, b: WorldPoint): float =
  let
    dx = (a.x - b.x).float / WorldScale.float
    dz = (a.z - b.z).float / WorldScale.float
  round(sqrt(dx * dx + dz * dz) * 100) / 100

proc segmentDistTiles(a0, a1, p: WorldPoint): float =
  ## Closest distance in tiles from point `p` to segment `a0`-`a1`.
  let
    ax = (a1.x - a0.x).float
    az = (a1.z - a0.z).float
    px = (p.x - a0.x).float
    pz = (p.z - a0.z).float
    denom = ax * ax + az * az
  if denom <= 0:
    return distTiles(a0, p)
  var t = (px * ax + pz * az) / denom
  t = clamp(t, 0.0, 1.0)
  let
    qx = a0.x.float + ax * t
    qz = a0.z.float + az * t
    dx = (p.x.float - qx) / WorldScale.float
    dz = (p.z.float - qz) / WorldScale.float
  round(sqrt(dx * dx + dz * dz) * 100) / 100

proc teamName(team: Team): string =
  if team == WestTeam: "west" else: "east"

proc buffName(pudge: Pudge): JsonNode =
  if pudge.buffTicks > 0: %RuneKeys[pudge.buffKind] else: newJNull()

proc distanceBand(dist: float): string =
  if dist < 15: DistanceBands[0]
  elif dist < 30: DistanceBands[1]
  elif dist < 45: DistanceBands[2]
  else: DistanceBands[3]

proc controllerOf(game: Game, index: int): string =
  if index in game.humanSlots: "human" else: "bot"

proc scriptOf(logger: DuelLogger, index: int): string =
  if index < logger.seatScripts.len: logger.seatScripts[index] else: ""

proc playerName(logger: DuelLogger, game: Game, index: int): string =
  ## Human seats are "human"; bot seats take their script's stem.
  if controllerOf(game, index) == "human":
    return "human"
  let script = logger.scriptOf(index)
  if script.len > 0:
    return script.extractFilename.changeFileExt("")
  "bot"

proc emit(logger: DuelLogger, node: JsonNode) =
  logger.events.writeLine($node)
  logger.wroteThisTick = true

proc baseEvent(logger: DuelLogger, name: string, tick: int32): JsonNode =
  result = newJObject()
  result["ev"] = %name
  result["t"] = %tick
  result["sec"] = %secOf(tick)

proc nextMatchDir*(base: string, prefix = "match"): string =
  ## Creates and returns a fresh timestamped match directory under
  ## `base`, adding a numeric suffix on a same-second collision.
  createDir(base)
  let stamp = now().format("yyyyMMdd'_'HHmmss")
  var candidate = base / (prefix & "_" & stamp)
  var counter = 1
  while dirExists(candidate):
    inc counter
    candidate = base / (prefix & "_" & stamp & "_" & $counter)
  createDir(candidate)
  candidate

proc pointLatestLink(dir: string) =
  ## Best-effort `latest` symlink beside the match directory.
  let link = dir.parentDir / "latest"
  try:
    if symlinkExists(link) or fileExists(link):
      removeFile(link)
    createSymlink(dir.extractFilename, link)
  except CatchableError:
    discard

proc snapshotPrev(logger: DuelLogger, game: Game) =
  let world = game.world
  logger.prevHp.setLen(world.pudges.len)
  logger.prevState.setLen(world.pudges.len)
  logger.prevLayer.setLen(world.pudges.len)
  logger.prevSpent.setLen(world.pudges.len)
  logger.prevUpgrades.setLen(world.pudges.len)
  logger.prevRunesTaken.setLen(world.pudges.len)
  logger.prevPoints.setLen(world.pudges.len)
  for i, pudge in world.pudges:
    logger.prevHp[i] = pudge.hp
    logger.prevState[i] = pudge.state
    logger.prevLayer[i] = pudge.layer
    logger.prevSpent[i] = pudge.spent
    logger.prevUpgrades[i] = pudge.upgrades
    logger.prevRunesTaken[i] = pudge.runesTaken
    logger.prevPoints[i] = pudge.points

proc newDuelLogger*(
    game: Game,
    dir: string,
    seatScripts: seq[string],
    label = ""
): DuelLogger =
  ## Opens `dir/events.jsonl` and writes the match_start event.
  ## `seatScripts` lists the bot script path per roster seat ("" for
  ## human seats); it feeds provenance and the policy fingerprint.
  createDir(dir)
  result = DuelLogger(
    dir: dir,
    seatScripts: seatScripts,
    startedAt: now().format("yyyy-MM-dd'T'HH:mm:ss"),
    startWall: epochTime(),
    firstBloodId: 0
  )
  result.events = open(dir / "events.jsonl", fmWrite)
  result.snapshotPrev(game)
  result.aggs.setLen(game.world.pudges.len)
  for i, pudge in game.world.pudges:
    result.aggs[i] = PlayerAgg(id: pudge.id)
  var players = newJArray()
  for i, pudge in game.world.pudges:
    var entry = %*{
      "id": pudge.id,
      "seat": i,
      "team": teamName(pudge.team),
      "controller": controllerOf(game, i),
      "name": result.playerName(game, i)
    }
    let home = pudge.spawnTile
    entry["spawnX"] = %home.x
    entry["spawnZ"] = %home.z
    let script = result.scriptOf(i)
    if script.len > 0:
      entry["script"] = %script
      if fileExists(script):
        entry["policySha"] = %fnv1a(readFile(script))
    players.add entry
  if label.len > 0:
    result.label = label
  else:
    var names: seq[string]
    for i in 0 ..< game.world.pudges.len:
      names.add result.playerName(game, i)
    result.label = names.join(" vs ")
  var start = result.baseEvent("match_start", game.world.tick)
  start["mode"] = %(
    if game.world.pudges.len == DuelPudgeCount: "duel" else: "3v3"
  )
  start["label"] = %result.label
  start["startedAt"] = %result.startedAt
  start["seed"] = %game.map.seed
  start["mapHash"] = %game.map.hash.toHex(16).toLowerAscii()
  start["tickRate"] = %TickRate
  start["killGoal"] = %game.world.killGoal
  start["maxTicks"] = %game.maximumTicks
  start["runePeriodSec"] = %(game.world.runePeriod div TickRate)
  start["botEvery"] = %game.botEvery
  start["botAimNoise"] = %game.botAimNoise
  start["players"] = players
  result.emit(start)
  result.events.flushFile()

proc actionSource(game: Game): (seq[ReplayAction], int) =
  ## Where drained commands live and how many are consumed so far:
  ## the live recorder grows its tape; pure replays advance a cursor.
  if game.recorder != nil:
    (game.recorder.data.actions, game.recorder.data.actions.len)
  elif game.replayPlayer != nil:
    (game.replayPlayer.data.actions, game.replayPlayer.actionIndex)
  else:
    (@[], 0)

proc logActions(logger: DuelLogger, game: Game) =
  let (actions, upto) = actionSource(game)
  if upto <= logger.lastActionIndex:
    return
  for index in logger.lastActionIndex ..< upto:
    let action = actions[index]
    # Coalesce repeated identical move/attack orders (bot scripts
    # reissue them every decision) so the stream stays readable.
    if action.kind in [ActionWalkTo, ActionAttackTarget]:
      let last = logger.lastOrders.getOrDefault(action.pudgeId)
      if last.kind == action.kind and last.a == action.first and
          last.b == action.second and
          int32(action.tick) - last.tick < WalkLogSpacingTicks:
        continue
      logger.lastOrders[action.pudgeId] = LastOrder(
        kind: action.kind,
        a: action.first,
        b: action.second,
        tick: int32(action.tick)
      )
    var event = logger.baseEvent("action", int32(action.tick))
    event["id"] = %action.pudgeId
    case action.kind
    of ActionWalkTo:
      event["act"] = %"walk"
      event["x"] = %action.first
      event["y"] = %action.second
    of ActionHookTo:
      event["act"] = %"hook"
      event["x"] = %action.first
      event["y"] = %action.second
    of ActionHookToFine:
      event["act"] = %"hook"
      event["x"] = %fineF(action.first)
      event["y"] = %fineF(action.second)
    of ActionAttackTarget:
      event["act"] = %"attack"
      event["target"] = %action.first
    of ActionBuyUpgrade:
      event["act"] = %"buy"
      if action.first >= 0 and action.first <= UpgradeKind.high.ord:
        event["upgrade"] = %UpgradeKeys[UpgradeKind(action.first)]
    of ActionStop:
      event["act"] = %"stop"
    of ActionPing:
      event["act"] = %"ping"
      event["x"] = %action.first
      event["y"] = %action.second
    of ActionBlinkTo:
      event["act"] = %"blink"
      event["x"] = %action.first
      event["y"] = %action.second
    of ActionBlinkToFine:
      event["act"] = %"blink"
      event["x"] = %fineF(action.first)
      event["y"] = %fineF(action.second)
    of ActionCheat:
      event["act"] = %"cheat"
      event["kind"] = %action.first
      event["amount"] = %action.second
    of ActionRotToggle:
      event["act"] = %"rot"
    else:
      event["act"] = %"takeover"
    logger.emit(event)
  logger.lastActionIndex = upto

proc nearestEnemy(world: World, pudge: Pudge): int =
  ## Roster index of the closest living enemy, or -1.
  result = -1
  var best = high(int64)
  for i, other in world.pudges:
    if other.team == pudge.team or other.state != Alive:
      continue
    let
      dx = int64(other.position.x - pudge.position.x)
      dz = int64(other.position.z - pudge.position.z)
      d = dx * dx + dz * dz
    if d < best:
      best = d
      result = i

proc hookRangeTiles(hook: Hook): float =
  round(hook.range.float / WorldScale.float * 100) / 100

proc logHookLaunches(logger: DuelLogger, game: Game) =
  ## New entries in `world.hooks` are fresh releases this tick.
  let world = game.world
  for hook in world.hooks:
    if logger.hookTracks.hasKey(hook.id):
      continue
    let owner = world.pudgeIndex(hook.ownerId)
    if owner < 0:
      continue
    var track = HookTrack(
      hookId: hook.id,
      ownerId: hook.ownerId,
      team: hook.team,
      launchTick: world.tick,
      origin: hook.origin,
      aimFineX: world.pudges[owner].windupAimX,
      aimFineY: world.pudges[owner].windupAimY,
      targetId: 0,
      closestDist: 1.0e9,
      traveled: hook.traveled
    )
    var event = logger.baseEvent("hook_launched", world.tick)
    event["id"] = %hook.ownerId
    event["hookId"] = %hook.id
    event["from"] = jpos(hook.origin)
    event["aim"] = %[fineF(track.aimFineX), fineF(track.aimFineY)]
    event["rangeTiles"] = %hookRangeTiles(hook)
    event["speedTilesPerSec"] = %tilesPerSec(hook.speed)
    event["damage"] = %hook.damage
    event["buff"] = buffName(world.pudges[owner])
    let enemy = nearestEnemy(world, world.pudges[owner])
    if enemy >= 0:
      let target = world.pudges[enemy]
      track.targetId = target.id
      track.targetPos = target.position
      track.targetDist = distTiles(hook.origin, target.position)
      event["target"] = %*{
        "id": target.id,
        "pos": jpos(target.position),
        "vel": [tilesPerSec(target.velX), tilesPerSec(target.velZ)],
        "dist": track.targetDist,
        "hp": max(target.hp, 0),
        "hookReady": target.hookCooldown <= 0
      }
    logger.hookTracks[hook.id] = track
    logger.emit(event)

proc updateHookTracks(logger: DuelLogger, game: Game) =
  ## Closest-approach bookkeeping and first-grab detection.
  let world = game.world
  for hook in world.hooks:
    if not logger.hookTracks.hasKey(hook.id):
      continue
    var track = logger.hookTracks[hook.id]
    track.traveled = max(track.traveled, hook.traveled)
    if hook.victimId != 0 and track.victimId == 0:
      track.victimId = hook.victimId
      track.grabTick = world.tick
      let victim = world.pudgeIndex(hook.victimId)
      var event = logger.baseEvent("hook_landed", world.tick)
      event["id"] = %hook.ownerId
      event["hookId"] = %hook.id
      event["victim"] = %hook.victimId
      event["at"] = jpos(hook.position)
      event["dist"] = %distTiles(track.origin, hook.position)
      event["flightTicks"] = %(world.tick - track.launchTick)
      if victim >= 0:
        event["victimHpAfter"] = %max(world.pudges[victim].hp, 0)
      logger.emit(event)
    if track.victimId == 0:
      for enemy in world.pudges:
        if enemy.team == hook.team or enemy.state != Alive:
          continue
        let d = segmentDistTiles(hook.prior, hook.position, enemy.position)
        if d < track.closestDist:
          track.closestDist = d
          track.closestId = enemy.id
          track.closestHookPos = hook.position
          track.closestEnemyPos = enemy.position
    logger.hookTracks[hook.id] = track

proc aggFor(logger: DuelLogger, game: Game, pudgeId: int32): int =
  game.world.pudgeIndex(pudgeId)

proc bumpDamage(agg: var PlayerAgg, table: string, cause: string, amount: int32) =
  if table == "dealt":
    agg.damageDealt[cause] = agg.damageDealt.getOrDefault(cause) + amount
  else:
    agg.damageTaken[cause] = agg.damageTaken.getOrDefault(cause) + amount

proc finalizeHook(
    logger: DuelLogger,
    game: Game,
    track: HookTrack,
    resolution: string,
    lethalVictim: int32
) =
  ## Emits the terminal event for one hook and appends its record.
  let
    world = game.world
    tick = world.tick
    flight = tick - track.launchTick
  var record = %*{
    "t": track.launchTick,
    "sec": secOf(track.launchTick),
    "owner": track.ownerId,
    "team": teamName(track.team),
    "from": jpos(track.origin),
    "aim": [fineF(track.aimFineX), fineF(track.aimFineY)],
    "result": resolution,
    "resolveTick": tick,
    "flightTicks": flight,
    "traveledTiles": round(track.traveled.float / WorldScale.float * 100) / 100
  }
  if track.targetId != 0:
    record["target"] = %track.targetId
    record["targetDist"] = %track.targetDist
    let targetNow = world.pudgeIndex(track.targetId)
    if targetNow >= 0:
      record["targetMoved"] = %distTiles(
        track.targetPos, world.pudges[targetNow].position
      )
  case resolution
  of "hit":
    let victim = if track.victimId != 0: track.victimId else: lethalVictim
    record["victim"] = %victim
    if track.damage > 0:
      record["damage"] = %track.damage
    var event = logger.baseEvent("hook_resolved", tick)
    event["id"] = %track.ownerId
    event["hookId"] = %track.hookId
    event["result"] = %"hit"
    event["victim"] = %victim
    logger.emit(event)
  of "miss":
    var closest = newJNull()
    if track.closestId != 0 and track.closestDist < 1.0e8:
      closest = %*{
        "id": track.closestId,
        "dist": track.closestDist,
        "hook": jpos(track.closestHookPos),
        "enemy": jpos(track.closestEnemyPos)
      }
    record["closest"] = closest
    var event = logger.baseEvent("hook_missed", tick)
    event["id"] = %track.ownerId
    event["hookId"] = %track.hookId
    event["closest"] = closest
    event["flightTicks"] = %flight
    if record.hasKey("targetMoved"):
      event["targetMoved"] = record["targetMoved"]
    logger.emit(event)
  else:
    var event = logger.baseEvent("hook_resolved", tick)
    event["id"] = %track.ownerId
    event["hookId"] = %track.hookId
    event["result"] = %resolution
    logger.emit(event)
  logger.hookRecords.add record
  # Aggregates: accuracy bands for the owner, dodge stats for the
  # launch target.
  let owner = logger.aggFor(game, track.ownerId)
  if owner >= 0 and track.targetId != 0:
    let band = distanceBand(track.targetDist)
    var entry = logger.aggs[owner].hookBands.getOrDefault(band, (0, 0))
    entry[1].inc
    if resolution == "hit":
      entry[0].inc
    logger.aggs[owner].hookBands[band] = entry
    let target = logger.aggFor(game, track.targetId)
    if target >= 0 and resolution in ["hit", "miss"]:
      logger.aggs[target].aimedAtMe.inc
      if resolution == "hit" and
          (track.victimId == track.targetId or
            lethalVictim == track.targetId):
        logger.aggs[target].hitMe.inc
      else:
        logger.aggs[target].dodged.inc
      if record.hasKey("targetMoved"):
        logger.aggs[target].movedSum += record["targetMoved"].getFloat
        logger.aggs[target].movedCount.inc

proc resolveVanishedHooks(
    logger: DuelLogger,
    game: Game,
    kills: seq[(int32, int32, string)]
) =
  ## Any tracked hook no longer alive in the world ended this tick.
  let world = game.world
  var live: Table[int32, bool]
  for hook in world.hooks:
    live[hook.id] = true
  var done: seq[int32]
  for id, track in logger.hookTracks:
    if live.hasKey(id):
      continue
    done.add id
    var resolution = "miss"
    var lethalVictim = 0'i32
    if track.victimId != 0:
      resolution = "hit"
    else:
      for (victim, killer, cause) in kills:
        if killer == track.ownerId and cause in ["hook", "headshot"]:
          resolution = "hit"
          lethalVictim = victim
          break
      if resolution == "miss" and world.clashTick == world.tick:
        if world.chunkerId == track.ownerId:
          resolution = "deny_win"
        elif world.chunkOwnerId == track.ownerId:
          resolution = "denied"
      if resolution == "miss":
        let owner = world.pudgeIndex(track.ownerId)
        if owner < 0 or world.pudges[owner].state == Dying:
          resolution = "cancel"
    logger.finalizeHook(game, track, resolution, lethalVictim)
  for id in done:
    logger.hookTracks.del id

proc damageCause(
    logger: DuelLogger,
    world: World,
    index: int
): (string, int32) =
  ## Best-effort classification of one HP drop this tick.
  let pudge = world.pudges[index]
  if pudge.justGrabbed:
    return ("hook", pudge.lastHurtBy)
  for other in world.pudges:
    if other.damageLanded and other.attackTargetId == pudge.id:
      return ("melee", other.id)
  if pudge.state == Dying:
    let killer = world.pudgeIndex(pudge.lastHurtBy)
    if killer >= 0 and world.pudges[killer].justHeadshot:
      return ("headshot", pudge.lastHurtBy)
  let rotKiller = world.pudgeIndex(pudge.lastHurtBy)
  if rotKiller >= 0:
    let src = world.pudges[rotKiller]
    if src.rotOn and
        distanceSquared(pudge.position, src.position) <=
          int64(RotRadius) * int64(RotRadius):
      return ("rot", pudge.lastHurtBy)
  if pudge.lastHurtBy == pudge.id:
    return ("rot", pudge.lastHurtBy)
  if pudge.layer == int32(RiverLayer) or
      logger.prevLayer[index] == int32(RiverLayer):
    return ("drown", pudge.lastHurtBy)
  ("hook", pudge.lastHurtBy)

proc logDamageAndKills(
    logger: DuelLogger,
    game: Game
): seq[(int32, int32, string)] =
  ## Damage events from HP deltas, kill events from state flips.
  ## Returns (victim, killer, cause) for this tick's kills.
  let world = game.world
  for i, pudge in world.pudges:
    if i >= logger.prevHp.len:
      continue
    let
      wasAlive = logger.prevState[i] == Alive
      died = wasAlive and pudge.state == Dying
      delta = logger.prevHp[i] - pudge.hp
    if wasAlive and delta > 0:
      let (cause, byId) = logger.damageCause(world, i)
      var event = logger.baseEvent("damage", world.tick)
      event["victim"] = %pudge.id
      event["by"] = %byId
      event["amount"] = %delta
      event["cause"] = %cause
      event["hpAfter"] = %max(pudge.hp, 0)
      event["lethal"] = %died
      logger.emit(event)
      let victimAgg = world.pudgeIndex(pudge.id)
      if victimAgg >= 0:
        logger.aggs[victimAgg].bumpDamage("taken", cause, delta)
      let dealerAgg = world.pudgeIndex(byId)
      if dealerAgg >= 0 and byId != pudge.id:
        logger.aggs[dealerAgg].bumpDamage("dealt", cause, delta)
      if cause == "hook" and pudge.justGrabbed:
        # Attach the latch damage to the live hook record.
        for id, track in logger.hookTracks.mpairs:
          if track.victimId == pudge.id and track.grabTick == world.tick:
            track.damage = delta
      if died:
        var cause2 = cause
        let killer = world.pudgeIndex(pudge.lastHurtBy)
        var kill = logger.baseEvent("kill", world.tick)
        kill["victim"] = %pudge.id
        kill["killer"] = %pudge.lastHurtBy
        kill["cause"] = %cause2
        kill["at"] = jpos(pudge.position)
        kill["score"] = %[
          world.teamKills[WestTeam.ord], world.teamKills[EastTeam.ord]
        ]
        if killer >= 0:
          kill["killerHp"] = %max(world.pudges[killer].hp, 0)
        logger.emit(kill)
        logger.killRecords.add %*{
          "t": world.tick,
          "sec": secOf(world.tick),
          "killer": pudge.lastHurtBy,
          "victim": pudge.id,
          "cause": cause2,
          "score": [
            world.teamKills[WestTeam.ord], world.teamKills[EastTeam.ord]
          ]
        }
        if logger.firstBloodId == 0:
          logger.firstBloodId = pudge.lastHurtBy
        result.add (pudge.id, pudge.lastHurtBy, cause2)
    elif died:
      # Killed without an HP delta this tick (headshot execution).
      let (cause, byId) = logger.damageCause(world, i)
      var kill = logger.baseEvent("kill", world.tick)
      kill["victim"] = %pudge.id
      kill["killer"] = %byId
      kill["cause"] = %cause
      kill["at"] = jpos(pudge.position)
      kill["score"] = %[
        world.teamKills[WestTeam.ord], world.teamKills[EastTeam.ord]
      ]
      logger.emit(kill)
      logger.killRecords.add %*{
        "t": world.tick,
        "sec": secOf(world.tick),
        "killer": byId,
        "victim": pudge.id,
        "cause": cause,
        "score": [
          world.teamKills[WestTeam.ord], world.teamKills[EastTeam.ord]
        ]
      }
      if logger.firstBloodId == 0:
        logger.firstBloodId = byId
      result.add (pudge.id, byId, cause)
    if logger.prevState[i] == Dying and pudge.state == Alive:
      var event = logger.baseEvent("respawn", world.tick)
      event["id"] = %pudge.id
      event["at"] = jpos(pudge.position)
      logger.emit(event)

proc logTransitions(logger: DuelLogger, game: Game) =
  ## River crossings, rune pickups, and upgrade purchases.
  let world = game.world
  for i, pudge in world.pudges:
    if i >= logger.prevLayer.len:
      continue
    let
      wasRiver = logger.prevLayer[i] == int32(RiverLayer)
      isRiver = pudge.layer == int32(RiverLayer)
    if isRiver and not wasRiver and pudge.state == Alive:
      var event = logger.baseEvent("river_enter", world.tick)
      event["id"] = %pudge.id
      event["at"] = jpos(pudge.position)
      event["hp"] = %max(pudge.hp, 0)
      event["by"] = %pudge.lastHurtBy
      logger.emit(event)
    elif wasRiver and not isRiver and pudge.state == Alive:
      var event = logger.baseEvent("river_exit", world.tick)
      event["id"] = %pudge.id
      event["hp"] = %max(pudge.hp, 0)
      logger.emit(event)
    if isRiver and pudge.state == Alive:
      let agg = world.pudgeIndex(pudge.id)
      if agg >= 0:
        logger.aggs[agg].riverTicks.inc
    if pudge.runesTaken > logger.prevRunesTaken[i]:
      var event = logger.baseEvent("rune_taken", world.tick)
      event["id"] = %pudge.id
      event["kind"] = %RuneKeys[pudge.buffKind]
      event["inRiver"] = %isRiver
      logger.emit(event)
    if pudge.spent > logger.prevSpent[i]:
      for kind in UpgradeKind:
        let gained = pudge.upgrades[kind] - logger.prevUpgrades[i][kind]
        if gained > 0:
          var event = logger.baseEvent("buy", world.tick)
          event["id"] = %pudge.id
          event["upgrade"] = %UpgradeKeys[kind]
          event["level"] = %pudge.upgrades[kind]
          event["pointsLeft"] = %pudge.points
          logger.emit(event)
  for rune in world.runes:
    if rune.spawnTick == world.tick:
      var event = logger.baseEvent("rune_spawn", world.tick)
      event["kind"] = %RuneKeys[rune.kind]
      event["at"] = jpos(rune.position)
      logger.emit(event)

proc logStateSample(logger: DuelLogger, game: Game) =
  let world = game.world
  if world.tick mod SampleEveryTicks != 0:
    return
  var event = logger.baseEvent("state", world.tick)
  var players = newJArray()
  for pudge in world.pudges:
    players.add %*{
      "id": pudge.id,
      "x": tileF(pudge.position.x),
      "y": tileF(pudge.position.z),
      "hp": max(pudge.hp, 0),
      "cd": max(pudge.hookCooldown, 0),
      "lay": pudge.layer,
      "vx": tilesPerSec(pudge.velX),
      "vy": tilesPerSec(pudge.velZ),
      "alive": pudge.state == Alive,
      "buff": buffName(pudge),
      "shield": max(pudge.shieldTicks, 0),
      "windup": max(pudge.windupTicks, 0)
    }
  event["p"] = players
  if world.hooks.len > 0:
    var hooks = newJArray()
    for hook in world.hooks:
      hooks.add %*{
        "o": hook.ownerId,
        "x": tileF(hook.position.x),
        "y": tileF(hook.position.z),
        "ph": if hook.phase == HookFlying: "fly" else: "reel",
        "victim": hook.victimId
      }
    event["hooks"] = hooks
  if world.runes.len > 0:
    var runes = newJArray()
    for rune in world.runes:
      runes.add %*{
        "kind": RuneKeys[rune.kind],
        "x": tileF(rune.position.x),
        "y": tileF(rune.position.z)
      }
    event["runes"] = runes
  logger.emit(event)

proc matchOutcome(game: Game): (string, string) =
  ## (outcome, reason) for the current world state.
  let world = game.world
  if world.gameOver:
    (teamName(world.winner), "kill_goal")
  elif world.tick >= game.maximumTicks:
    ("draw", "time_limit")
  else:
    ("aborted", "quit")

proc damageTable(table: Table[string, int32]): JsonNode =
  result = newJObject()
  var total = 0'i32
  for cause, amount in table:
    result[cause] = %amount
    total += amount
  result["total"] = %total

proc buildSummary(logger: DuelLogger, game: Game): JsonNode =
  let
    world = game.world
    (outcome, reason) = matchOutcome(game)
  var players = newJArray()
  for i, pudge in world.pudges:
    let agg = logger.aggs[i]
    var accuracy = 0.0
    if pudge.hooksThrown > 0:
      accuracy = round(
        pudge.hooksLanded.float / pudge.hooksThrown.float * 1000
      ) / 1000
    var upgrades = newJObject()
    for kind in UpgradeKind:
      upgrades[UpgradeKeys[kind]] = %pudge.upgrades[kind]
    var bands = newJObject()
    for band in DistanceBands:
      if agg.hookBands.hasKey(band):
        let (landed, thrown) = agg.hookBands[band]
        bands[band] = %[landed, thrown]
    var dodge = %*{
      "hooksAimedAtMe": agg.aimedAtMe,
      "hit": agg.hitMe,
      "dodged": agg.dodged
    }
    if agg.movedCount > 0:
      dodge["avgMoveDuringFlight"] =
        %(round(agg.movedSum / agg.movedCount.float * 100) / 100)
    var entry = %*{
      "id": pudge.id,
      "seat": i,
      "team": teamName(pudge.team),
      "controller": controllerOf(game, i),
      "name": logger.playerName(game, i),
      "kills": pudge.kills,
      "deaths": pudge.deaths,
      "hooksThrown": pudge.hooksThrown,
      "hooksLanded": pudge.hooksLanded,
      "accuracy": accuracy,
      "headshots": pudge.headshotCount,
      "denies": pudge.denyCount,
      "runes": pudge.runesTaken,
      "pointsUnspent": pudge.points,
      "upgrades": upgrades,
      "damageDealt": damageTable(agg.damageDealt),
      "damageTaken": damageTable(agg.damageTaken),
      "timeInRiverSec": round(agg.riverTicks.float / TickRate.float * 10) / 10,
      "firstBlood": logger.firstBloodId == pudge.id,
      "hitRateByDist": bands,
      "dodge": dodge
    }
    let script = logger.scriptOf(i)
    if script.len > 0:
      entry["script"] = %script
      if fileExists(script):
        entry["policySha"] = %fnv1a(readFile(script))
    players.add entry
  %*{
    "schema": 1,
    "label": logger.label,
    "dir": logger.dir,
    "startedAt": logger.startedAt,
    "endedAt": now().format("yyyy-MM-dd'T'HH:mm:ss"),
    "mode": (
      if world.pudges.len == DuelPudgeCount: "duel" else: "3v3"
    ),
    "seed": game.map.seed,
    "killGoal": world.killGoal,
    "ticks": world.tick,
    "durationSec": secOf(world.tick),
    "outcome": outcome,
    "reason": reason,
    "score": {
      "west": world.teamKills[WestTeam.ord],
      "east": world.teamKills[EastTeam.ord]
    },
    "players": players,
    "kills": logger.killRecords,
    "hooks": logger.hookRecords,
    "files": {
      "events": "events.jsonl",
      "replay": "replay.pwr"
    }
  }

proc appendHistory(logger: DuelLogger, game: Game, summary: JsonNode) =
  ## One compact line per match in `<base>/history.jsonl`.
  var line = %*{
    "stamp": logger.startedAt,
    "dir": logger.dir.extractFilename,
    "label": logger.label,
    "mode": summary["mode"],
    "outcome": summary["outcome"],
    "reason": summary["reason"],
    "score": summary["score"],
    "durationSec": summary["durationSec"]
  }
  var perPlayer = newJArray()
  for player in summary["players"]:
    var compact = %*{
      "name": player["name"],
      "team": player["team"],
      "kills": player["kills"],
      "deaths": player["deaths"],
      "accuracy": player["accuracy"]
    }
    if player.hasKey("policySha"):
      compact["policySha"] = player["policySha"]
    perPlayer.add compact
  line["players"] = perPlayer
  let path = logger.dir.parentDir / "history.jsonl"
  let history = open(path, fmAppend)
  history.writeLine($line)
  history.close()

proc finishDuelLog*(logger: DuelLogger, game: Game) =
  ## Flushes open hooks, writes match_end, summary.json, and the
  ## history line. Idempotent: safe on rematch, game over, and quit.
  if logger == nil or logger.finished:
    return
  logger.finished = true
  var pending: seq[HookTrack]
  for _, track in logger.hookTracks:
    pending.add track
  for track in pending:
    logger.finalizeHook(game, track, "cancel", 0)
  logger.hookTracks.clear()
  let (outcome, reason) = matchOutcome(game)
  var event = logger.baseEvent("match_end", game.world.tick)
  event["outcome"] = %outcome
  event["reason"] = %reason
  event["score"] = %[
    game.world.teamKills[WestTeam.ord],
    game.world.teamKills[EastTeam.ord]
  ]
  event["durationSec"] = %secOf(game.world.tick)
  logger.emit(event)
  logger.events.flushFile()
  logger.events.close()
  let summary = logger.buildSummary(game)
  writeFile(logger.dir / "summary.json", summary.pretty())
  logger.appendHistory(game, summary)
  pointLatestLink(logger.dir)

proc logDuelTick*(logger: DuelLogger, game: Game) =
  ## Observes one completed tick. Call after `tickWorld`. Re-simulated
  ## ticks (history seeks, restarts) are skipped by the tick guard.
  if logger == nil or logger.finished:
    return
  let world = game.world
  if world.tick <= logger.lastLoggedTick:
    return
  logger.lastLoggedTick = world.tick
  logger.wroteThisTick = false
  logger.logActions(game)
  logger.logHookLaunches(game)
  logger.updateHookTracks(game)
  let kills = logger.logDamageAndKills(game)
  logger.resolveVanishedHooks(game, kills)
  logger.logTransitions(game)
  logger.logStateSample(game)
  logger.snapshotPrev(game)
  if logger.wroteThisTick:
    logger.events.flushFile()
  if world.gameOver and not logger.sawGameOver:
    logger.sawGameOver = true
    logger.finishDuelLog(game)
