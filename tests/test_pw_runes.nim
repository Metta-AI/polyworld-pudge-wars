## River runes: deterministic spawns and drift, both pickup paths, the
## four buffs, expiry, hash coverage, and the v3 replay round-trip.

import
  std/os,
  polyworld/[cli, tapes],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const MatchTicks = 4000'i32

let map = generateMap(2026)

proc freshGame(runePeriod = RunePeriodTicks): Game =
  newGame(map, MatchTicks, false, ReplayData(), KillGoal, runePeriod)

proc play(game: Game, ticks: int) =
  for _ in 0 ..< ticks:
    tickWorld(game, proc() =
      # Botless hero turn: rotate the start slot exactly like
      # `runBotDecisions`, so playback (which rotates itself) matches.
      game.world.heroTurnStart =
        (game.world.heroTurnStart + 1) mod game.world.pudges.len
    )

proc startRecording(game: Game, maximumTicks: uint32) =
  game.recorder = initReplayRecorder(currentSetup(game, maximumTicks))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)

proc parkPudges(game: Game) =
  ## Corners everyone on their spawn columns, far from the river.
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 40)

proc dropRune(game: Game, kind: RuneKind, x, z: int, dir = 1'i32): int32 =
  ## Injects one rune at a tile with `spawnRune`'s bookkeeping.
  result = game.world.nextRuneId
  game.world.runes.add Rune(
    id: result,
    kind: kind,
    position: worldAtTile(x, z),
    dir: dir,
    spawnTick: game.world.tick
  )
  inc game.world.nextRuneId

proc distSq(a, b: WorldPoint): int64 =
  let
    dx = int64(a.x) - int64(b.x)
    dz = int64(a.z) - int64(b.z)
  dx * dx + dz * dz

echo "Testing periodic spawns sit on the river midline"
block:
  let game = freshGame(runePeriod = TickRate)
  parkPudges(game)
  game.play(int(TickRate))
  doAssert game.world.runes.len == 1, "one rune after one period"
  game.play(int(TickRate))
  doAssert game.world.runes.len == 2, "a second rune one period later"
  let midlineX = worldAtTile(RiverCenterX, PlayZMin).x
  for rune in game.world.runes:
    let tile = tileOf(rune.position)
    doAssert tile.x == RiverCenterX, "rune outside the river midline"
    doAssert rune.position.x == midlineX,
      "rune world X must be the center of the water tile"
    doAssert riverTile(tile.x)
    doAssert not islandTile(tile.x, tile.z),
      "end-of-river spawns must not land on the fountain"
    doAssert rune.dir == 1 or rune.dir == -1
  block driftFollowsCurrent:
    let
      before = game.world.runes[0].position.z
      dir = game.world.runes[0].dir
      id = game.world.runes[0].id
    game.play(1)
    doAssert game.world.runes[0].id == id
    doAssert game.world.runes[0].position.z ==
      before + dir * RuneDriftPerTick

echo "Testing rune worlds stay hash-exact and 0 disables spawns"
block:
  let
    first = freshGame(runePeriod = TickRate)
    second = freshGame(runePeriod = TickRate)
  first.play(200)
  second.play(200)
  doAssert first.world.runes.len > 0
  doAssert stateHash(first) == stateHash(second),
    "same seed and period must produce identical rune worlds"
  let off = freshGame(runePeriod = 0)
  off.play(200)
  doAssert off.world.runes.len == 0, "0 must disable the river drops"
  doAssert off.world.nextRuneId == FirstRuneId

echo "Testing a rune drifting past the arena edge despawns"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  discard game.dropRune(RuneHaste, RiverCenterX + 5, PlayZMax - 1, dir = 1)
  game.play(3 * 8)
  doAssert game.world.runes.len == 0, "the current must carry it away"
  for pudge in game.world.pudges:
    doAssert pudge.buffTicks == 0, "nobody may inherit a despawned rune"

echo "Testing wading into a rune grabs it, bank-standing does not"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  # A butcher already in the drink walks over the orb on the way home.
  game.world.pudges[0].placePudge(RiverCenterX - 5, 30)
  discard game.dropRune(RuneRegen, RiverCenterX - 5, 30)
  game.play(1)
  doAssert game.world.runes.len == 0, "body contact must take the rune"
  doAssert game.world.pudges[0].hasBuff(RuneRegen)
  doAssert game.world.pudges[0].buffTicks > 0
  doAssert game.world.pudges[0].runesTaken == 1
  doAssert game.world.pudges[0].justRune, "the pickup flag must pulse"
  game.play(1)
  doAssert not game.world.pudges[0].justRune, "the pulse lasts one tick"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  # Midline is 12 tiles from the first walkable east column; a dry
  # butcher must not reach a drifting rune.
  game.world.pudges[3].placePudge(PlayEastMin, 30)
  discard game.dropRune(RuneHaste, RiverCenterX, 30)
  game.play(2)
  doAssert game.world.runes.len == 1, "a bank-stander must not reach it"
  doAssert game.world.pudges[3].buffTicks == 0

echo "Testing a hook scoops the rune and still latches the body behind"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  # Caster at x=22, rune at x=40, enemy body at x=60, all on z=64.
  discard game.dropRune(RuneDoubleDamage, 40, 64)
  game.world.pudges[3].placePudge(60, 64)
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 60, 64)
  var latched = false
  for _ in 0 ..< 60:
    game.play(1)
    if game.world.pudges[3].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert game.world.runes.len == 0, "the blade passed over the rune"
  doAssert game.world.pudges[0].hasBuff(RuneDoubleDamage),
    "the caster gets the scooped buff"
  doAssert latched, "the hook must fly on and still grab the enemy"

echo "Testing haste raises the walk cap and expiry restores it"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  let hasteCap = MovePerTick + MovePerTick * RuneHastePercent div 100
  game.world.pudges[0].buffKind = RuneHaste
  game.world.pudges[0].buffTicks = RuneBuffTicks
  doAssert applyWalkTo(game.world, game.world.pudges[0].id, 50, 64)
  # A straight east walk: momentum ramps velX by MoveAccel per tick, so
  # the raised cap needs hasteCap / MoveAccel ≈ 22 ticks from rest.
  game.play(24)
  doAssert game.world.pudges[0].velX == hasteCap,
    "a buffed walker must reach the raised cap"
  game.world.pudges[0].buffTicks = 1
  # Shedding the haste surplus takes (hasteCap - MovePerTick) / MoveBrake
  # ≈ 5 ticks of braking.
  game.play(8)
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].velX == MovePerTick,
    "an expired haste must decay to the stock cap"

echo "Testing double damage and big hook empower the next throw"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  game.world.pudges[0].buffKind = RuneDoubleDamage
  game.world.pudges[0].buffTicks = RuneBuffTicks
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 60, 64)
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].damage == hookDamage(0) * RuneDamageMul
  doAssert game.world.hooks[0].range == hookRange(0)
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  game.world.pudges[0].buffKind = RuneBigHook
  game.world.pudges[0].buffTicks = RuneBuffTicks
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 60, 64)
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].damage == bigHookDamage(hookDamage(0))
  doAssert game.world.hooks[0].damage == hookDamage(0) * 3 div 2
  doAssert game.world.hooks[0].range ==
    hookRange(0) + hookRange(0) * RuneBigHookPercent div 100
  doAssert game.world.hooks[0].radius ==
    hookRadius(0) + hookRadius(0) * RuneBigHookPercent div 100

echo "Testing regen pulses heal and death clears the buff"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  game.world.pudges[0].hp = game.world.pudges[0].hp - 100
  game.world.pudges[0].buffKind = RuneRegen
  game.world.pudges[0].buffTicks = RuneBuffTicks
  let before = game.world.pudges[0].hp
  game.play(int(RuneRegenPeriodTicks) * 2)
  let pulse = max(1'i32, game.world.pudges[0].maxHp * RuneRegenPercent div 100)
  doAssert game.world.pudges[0].hp >= before + pulse,
    "at least one regen pulse must land"
  doAssert game.world.pudges[0].hp <= game.world.pudges[0].maxHp
  game.world.killPudgeForTest(0, game.world.pudges[3].id)
  doAssert game.world.pudges[0].buffTicks == 0, "death drops the buff"

echo "Testing every rune and buff field reaches the state hash"
block:
  let game = freshGame(runePeriod = 0)
  parkPudges(game)
  discard game.dropRune(RuneHaste, RiverCenterX + 5, 30)
  let baseline = stateHash(game)

  game.world.runes[0].position.z = game.world.runes[0].position.z + 1
  doAssert stateHash(game) != baseline, "rune position must be hashed"
  game.world.runes[0].position.z = game.world.runes[0].position.z - 1

  game.world.runes[0].kind = RuneBigHook
  doAssert stateHash(game) != baseline, "rune kind must be hashed"
  game.world.runes[0].kind = RuneHaste

  game.world.runes[0].dir = -1
  doAssert stateHash(game) != baseline, "rune drift must be hashed"
  game.world.runes[0].dir = 1

  game.world.runeClock = 77
  doAssert stateHash(game) != baseline, "the spawn clock must be hashed"
  game.world.runeClock = 0

  game.world.runePeriod = 123
  doAssert stateHash(game) != baseline, "the period knob must be hashed"
  game.world.runePeriod = 0

  game.world.pudges[0].buffTicks = 5
  doAssert stateHash(game) != baseline, "buff time must be hashed"
  let withBuff = stateHash(game)
  game.world.pudges[0].buffKind = RuneRegen
  doAssert stateHash(game) != withBuff, "buff kind must be hashed"
  game.world.pudges[0].buffKind = RuneHaste
  game.world.pudges[0].buffTicks = 0

  game.world.pudges[0].runesTaken = 3
  doAssert stateHash(game) != baseline, "the pickup tally must be hashed"
  game.world.pudges[0].runesTaken = 0

  doAssert stateHash(game) == baseline, "every probe must restore state"

echo "Testing the stock bot hooks a rune drifting past its lane"
block:
  let game = freshGame(runePeriod = 0)
  let basPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"
  loadBots(game, [BotGroup(path: basPath, count: PudgeCount)])
  # Midline, off the fountain: both banks are 12 tiles away, so either
  # team can steal it once they hold the waterline.
  discard game.dropRune(RuneHaste, RiverCenterX, 40)
  var contested = false
  for _ in 0 ..< 5 * int(TickRate):
    tickWorld(game, proc() = runBotDecisions(game))
    for pudge in game.world.pudges:
      if pudge.runesTaken > 0:
        contested = true
        break
    if contested:
      break
  doAssert contested, "a bot must hook the midline rune off the current"

echo "Testing two hooks that hit one rune do not prefer list order"
block:
  proc fireHook(
      game: Game,
      owner: int,
      startX, startZ, dirX, dirZ: int
  ) =
    let start = worldAtTile(startX, startZ)
    game.world.hooks.add Hook(
      id: game.world.nextHookId,
      ownerId: game.world.pudges[owner].id,
      team: game.world.pudges[owner].team,
      phase: HookFlying,
      position: start,
      origin: start,
      prior: start,
      heading: heading(int32(dirX), int32(dirZ)),
      range: BaseHookRange,
      speed: BaseHookSpeed,
      peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius,
      damage: BaseHookDamage
    )
    inc game.world.nextHookId

  proc contest(eastFirst: bool, rngState: uint64): int32 =
    ## Returns the owner id that scooped the rune, or 0.
    let game = freshGame(runePeriod = 0)
    parkPudges(game)
    discard game.dropRune(RuneHaste, RiverCenterX, 40)
    game.world.rng.state = rngState
    if eastFirst:
      game.fireHook(3, PlayEastMin, 40, -WorldScale, 0)
      game.fireHook(0, PlayWestMax, 40, WorldScale, 0)
    else:
      game.fireHook(0, PlayWestMax, 40, WorldScale, 0)
      game.fireHook(3, PlayEastMin, 40, -WorldScale, 0)
    for _ in 0 ..< 80:
      game.play(1)
      if game.world.runes.len == 0:
        break
    for pudge in game.world.pudges:
      if pudge.runesTaken > 0:
        return pudge.id
    0

  let rngState = 0xC0FFEE1234'u64
  let westListed = contest(eastFirst = false, rngState = rngState)
  let eastListed = contest(eastFirst = true, rngState = rngState)
  doAssert westListed != 0, "a mirrored scoop must award the rune"
  doAssert westListed == eastListed,
    "hook-list order must not pick the rune winner"

  var westWins, eastWins = 0
  for salt in 0'u64 .. 31'u64:
    let winner = contest(eastFirst = false, rngState = rngState xor salt)
    if winner == 1: inc westWins
    elif winner == 4: inc eastWins
  doAssert westWins > 0 and eastWins > 0,
    "equal-distance scoops must split across rng, not lock a bank"
  doAssert westWins + eastWins == 32

echo "Testing a v3 replay with live runes round-trips hash-exact"
block:
  const RecordTicks = 220'i32
  # The world duration must match the recorded one: both are hashed.
  let game = newGame(
    map, RecordTicks, false, ReplayData(), KillGoal, TickRate
  )
  game.startRecording(uint32(RecordTicks))
  doAssert game.recorder.data.header.setup.runePeriod == TickRate,
    "the setup must carry the live rune period"
  # One real command so the tape is not empty, then drift long enough
  # for spawns to cycle.
  doAssert applyWalkTo(game.world, game.world.pudges[0].id, 40, 70)
  game.recorder.recordWalkTo(1'u32, game.world.pudges[0].id, 40, 70)
  game.play(int(RecordTicks))
  doAssert game.world.runes.len > 0, "the recording must have live runes"
  let
    live = stateHash(game)
    encoded = encodeReplay(game.recorder.data)
    decoded = decodeReplay(encoded)
  doAssert decoded.header.formatVersion == ReplayFormatVersion
  doAssert decoded.header.setup.runePeriod == TickRate
  let replay = newGame(map, RecordTicks, true, decoded)
  replay.replayPlayer = initReplayPlayer(decoded)
  replay.historyPlayback = true
  replay.play(int(RecordTicks))
  doAssert replay.hashCheck.mismatches == 0, replay.hashCheck.error
  doAssert stateHash(replay) == live,
    "replaying the tape must rebuild the exact rune world"

echo "Testing validate rejects a negative rune period"
block:
  let game = freshGame(runePeriod = TickRate)
  game.startRecording(2'u32)
  game.play(2)
  var data = game.recorder.data
  data.header.setup.runePeriod = -1
  try:
    validate(data)
    doAssert false, "a negative rune period must be rejected"
  except ReplayError:
    discard

echo "test_pw_runes: all checks passed"
