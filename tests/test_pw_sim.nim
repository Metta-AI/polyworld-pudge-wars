## Pudge Wars simulation: hooks, headshots, melee, upgrades, and the kill goal.

import
  std/strutils,
  polyworld/[cli, fixed, pathing, tapes],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const MatchTicks = 400'i32

let map = generateMap(2026)

proc freshGame(): Game =
  newGame(map, MatchTicks, false, ReplayData())

proc play(game: Game, ticks: int) =
  for _ in 0 ..< ticks:
    tickWorld(game, proc() = discard)

proc startRecording(game: Game, maximumTicks: uint32) =
  game.recorder = initReplayRecorder(currentSetup(game, maximumTicks))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)

proc onHookLine(
    origin, point: WorldPoint,
    heading: Heading,
    slack: int32
): bool =
  let
    hx = int64(heading.x)
    hz = int64(heading.z)
    dx = int64(point.x) - int64(origin.x)
    dz = int64(point.z) - int64(origin.z)
    cross = hx * dz - hz * dx
    mag = integerSqrt(hx * hx + hz * hz)
  if mag == 0:
    return true
  let offset = if cross < 0: -cross else: cross
  offset <= int64(slack) * mag

proc distSq(a, b: WorldPoint): int64 =
  let
    dx = int64(a.x) - int64(b.x)
    dz = int64(a.z) - int64(b.z)
  dx * dx + dz * dz

proc livingSeparation(a, b: Pudge): int64 =
  integerSqrt(distSq(a.position, b.position))

proc assertApart(a, b: Pudge, why: string) =
  doAssert distSq(a.position, b.position) > 0, why & ": coincident"
  doAssert livingSeparation(a, b) >=
      int64(MinSeparation) - int64(WorldScale div 4),
    why & ": still overlapping"

proc facingDot(pudge: Pudge, toward: WorldPoint): int64 =
  let
    dx = int64(toward.x) - int64(pudge.position.x)
    dz = int64(toward.z) - int64(pudge.position.z)
  int64(pudge.facing.x) * dx + int64(pudge.facing.z) * dz

const NorthWallZ = int32(-GridTiles div 2) * WorldScale

proc parkPudges(game: Game) =
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 40)

proc addFlyingHook(
    game: Game,
    start: WorldPoint,
    dirX, dirZ: int32,
    range = BaseHookRange,
    speed = BaseHookSpeed
): int =
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    phase: HookFlying,
    position: start,
    origin: start,
    prior: start,
    heading: heading(dirX, dirZ),
    range: range,
    speed: speed,
    peakSpeed: speed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  game.world.hooks.high

echo "Testing the opening position"
block:
  let game = freshGame()
  doAssert game.world.pudges.len == PudgeCount
  doAssert game.world.hooks.len == 0
  doAssert not game.world.gameOver
  doAssert game.world.teamKills[WestTeam.ord] == 0
  doAssert game.world.teamKills[EastTeam.ord] == 0
  for i, pudge in game.world.pudges:
    doAssert pudge.id == FirstPudgeId + int32(i)
    doAssert pudge.state == Alive
    doAssert pudge.hp == BaseHitPoints
    let tile = tileOf(pudge.position)
    let home = pudge.spawnTile
    doAssert tile.x == home.x
    doAssert tile.z == home.z
    let pad = game.world.spawnLayout.layoutPad(pudge.team, pudge.slot)
    doAssert home.x == pad.x and home.z == pad.z
  for i in 0 ..< game.world.pudges.len:
    for j in i + 1 ..< game.world.pudges.len:
      if game.world.pudges[i].team != game.world.pudges[j].team:
        continue
      assertApart(
        game.world.pudges[i],
        game.world.pudges[j],
        "spawns must not stack teammates"
      )

echo "Testing determinism across identical runs"
block:
  let first = freshGame()
  let second = freshGame()
  doAssert first.stateHash() == second.stateHash(), "openings differ"
  first.play(TickRate * 8)
  second.play(TickRate * 8)
  doAssert first.stateHash() == second.stateHash(),
    "two idle runs diverged"
  doAssert first.stateHash() != freshGame().stateHash(),
    "idle time still has to move the tick hash"

echo "Testing river walks snap to the bank and Meat Hook flies across it"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  doAssert game.world.pudges[0].layer == int32(WestLayer)
  doAssert game.world.pudges[3].layer == int32(EastLayer)
  doAssert applyWalkTo(game.world, west, int32(RiverCenterX), 64),
    "a river click should snap to the bank, not reject"
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].moveX <= int32(PlayWestMax),
    "the snapped target must stay on the west bank"
  doAssert not riverTile(int(game.world.pudges[0].moveX))
  doAssert applyWalkTo(game.world, west, int32(PlayEastMin), 64),
    "an enemy-bank click should snap back across the river"
  doAssert game.world.pudges[0].moveX <= int32(PlayWestMax),
    "walking must stay on the bank layer"
  doAssert applyWalkTo(game.world, west, int32(PlayWestMax), 64)
  game.world.pudges[0].placePudge(48, 48)
  game.world.pudges[3].placePudge(78, 48)
  doAssert applyHookTo(game.world, west, 78, 48)
  doAssert game.world.pudges[0].windupTicks == HookWindupTicks,
    "a cast should start its windup"
  doAssert game.world.hooks.len == 0,
    "the head must stay in hand until the cast point ends"
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  game.play(200)
  doAssert game.world.pudges[3].hp < BaseHitPoints,
    "a hook that reaches the far bank should hit"
  doAssert game.world.pudges[3].hp > 0, "base hook damage should not one-shot"

echo "Testing a hook pulls the first unit it hits"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[3].placePudge(52, 64)
  let
    owner = game.world.pudges[0].position
    start = game.world.pudges[3].position
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 52, 64)
  game.play(160)
  doAssert game.world.hooks.len == 0, "the hook should finish reeling"
  doAssert game.world.pudges[3].hookedBy == 0
  doAssert game.world.pudges[3].hp == BaseHitPoints - BaseHookDamage,
    "enemies still take hook damage"
  let pulled = game.world.pudges[3].position
  doAssert abs(pulled.x - owner.x) <= PudgeCollisionRadius * 2 + WorldScale,
    "the victim should land next to the butcher"
  doAssert abs(pulled.x - start.x) > WorldScale,
    "the victim should have left the hook's first tile"
  assertApart(
    game.world.pudges[0],
    game.world.pudges[3],
    "an enemy hook drop must not stack the pair"
  )

echo "Testing a second hook headshots a hooked butcher"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[3].placePudge(48, 64)
  # Pin the victim on an enemy chain; the cast point means a live reel
  # would carry it away from any fixed aim, so the latch is tested still.
  game.world.pudges[3].hookedBy = game.world.pudges[0].id
  game.world.pudges[1].placePudge(44, 64)
  doAssert applyHookTo(game.world, game.world.pudges[1].id, 48, 64)
  for _ in 0 ..< 24:
    game.play(1)
    if game.world.pudges[3].state == Dying:
      break
  doAssert game.world.pudges[3].state == Dying, "a double hook is a headshot"
  doAssert game.world.pudges[1].kills == 1
  doAssert game.world.pudges[1].headshotCount == 1
  doAssert game.world.teamKills[WestTeam.ord] == 1

echo "Testing melee and hook upgrades"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[3].placePudge(31, 64)
  doAssert applyAttackTarget(
    game.world,
    game.world.pudges[0].id,
    game.world.pudges[3].id
  )
  game.play(1)
  doAssert game.world.pudges[3].hp == BaseHitPoints - BaseMeleeDamage
  game.play(AttackTicks * 3)
  assertApart(
    game.world.pudges[0],
    game.world.pudges[3],
    "melee must not stack two living butchers"
  )
  game.world.pudges[0].points = 2
  doAssert applyBuyUpgrade(game.world, game.world.pudges[0].id, 0)
  doAssert applyBuyUpgrade(game.world, game.world.pudges[0].id, 1)
  doAssert game.world.pudges[0].upgrades[UpgradeDamage] == 1
  doAssert game.world.pudges[0].upgrades[UpgradeDistance] == 1
  doAssert game.world.pudges[0].points == 0
  doAssert not applyBuyUpgrade(game.world, game.world.pudges[0].id, 2)

echo "Testing a river-edge hook dumps the victim in the drink"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(PlayWestMax, 48)
  game.world.pudges[3].placePudge(PlayEastMin, 48)
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayEastMin),
    48
  )
  var dumped = false
  for _ in 0 ..< 400:
    game.play(1)
    if game.world.pudges[3].inRiver and game.world.pudges[3].hookedBy == 0:
      dumped = true
      break
  doAssert dumped, "hugging the bank should dump the victim in the river"
  doAssert game.world.riverDumps >= 1
  doAssert game.world.pudges[3].layer == int32(RiverLayer)
  let
    dumpId = game.world.pudges[3].id
    dumpStartX = game.world.pudges[3].position.x
    dumpHomeX = worldAtTile(homeBankX(game.world.pudges[3].team), 48).x
    dumpStartDist = abs(int64(dumpStartX) - int64(dumpHomeX))
  var closer = 0
  var prevDist = dumpStartDist
  for _ in 0 ..< 16:
    game.play(1)
    doAssert game.world.pudges[3].inRiver,
      "a dump must not auto-climb onto a bank"
    let dist = abs(
      int64(game.world.pudges[3].position.x) - int64(dumpHomeX)
    )
    if dist < prevDist:
      inc closer
    prevDist = dist
  doAssert closer < 12,
    "idle river ticks must not monotonically approach homeBankX"
  let
    dumpTile = tileOf(game.world.pudges[3].position)
    dumpStartZ = game.world.pudges[3].position.z
  doAssert applyWalkTo(
    game.world, dumpId, int32(dumpTile.x), int32(dumpTile.z + 12)
  ), "a river butcher can walk along the water"
  game.play(16)
  doAssert game.world.pudges[3].inRiver
  doAssert game.world.pudges[3].layer == int32(RiverLayer)
  doAssert abs(game.world.pudges[3].position.z - dumpStartZ) >
      MovePerTick * 8,
    "applyWalkTo along the river z axis must move"

echo "Testing drowning is HP, not a forced walk home"
block:
  let game = freshGame()
  game.world.pudges[3].placePudge(RiverWestX + 2, 20)
  doAssert game.world.pudges[3].inRiver
  let startX = game.world.pudges[3].position.x
  game.world.pudges[3].lastHurtBy = game.world.pudges[0].id
  let startHp = game.world.pudges[3].hp
  game.play(DrownPeriodTicks + 1)
  doAssert game.world.pudges[3].hp < startHp, "the river should drown"
  doAssert abs(game.world.pudges[3].position.x - startX) < WorldScale,
    "drown must not walk them toward the home bank"
  doAssert game.world.pudges[3].inRiver
  game.world.pudges[3].hp = DrownDamage
  game.play(DrownPeriodTicks + 1)
  doAssert game.world.pudges[3].state == Dying
  doAssert game.world.pudges[0].kills == 1

echo "Testing river walk matches land walk speed"
block:
  let riverGame = freshGame()
  riverGame.world.pudges[3].placePudge(RiverCenterX, 20)
  let riverId = riverGame.world.pudges[3].id
  doAssert applyWalkTo(riverGame.world, riverId, int32(RiverCenterX), 40)
  let riverStart = riverGame.world.pudges[3].position.z
  riverGame.play(16)
  let riverMoved = riverGame.world.pudges[3].position.z - riverStart
  doAssert riverGame.world.pudges[3].inRiver, "16 ticks should not climb out"
  doAssert riverMoved > MovePerTick * 8,
    "river travel must be land walk, not StruggleSpeed/4"
  let landGame = freshGame()
  landGame.world.pudges[0].placePudge(30, 64)
  doAssert applyWalkTo(landGame.world, landGame.world.pudges[0].id, 50, 64)
  let landStart = landGame.world.pudges[0].position.x
  landGame.play(16)
  let landMoved = landGame.world.pudges[0].position.x - landStart
  doAssert abs(riverMoved - landMoved) <= WorldScale,
    "river and land should cover the same ground in 16 ticks"
  doAssert riverGame.world.pudges[3].animClip == runClip,
    "a moving river butcher should play RunForward"

echo "Testing a river walk toward a bank stays in the water"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(RiverCenterX, 40)
  let id = game.world.pudges[0].id
  doAssert game.world.pudges[0].inRiver
  doAssert applyWalkTo(game.world, id, int32(PlayWestMax), 40)
  game.play(40)
  doAssert game.world.pudges[0].inRiver, "walking at a bank must not land"
  doAssert game.world.pudges[0].layer == int32(RiverLayer)
  let tile = tileOf(game.world.pudges[0].position)
  doAssert riverTile(tile.x)
  doAssert not westBank(tile.x) and not eastBank(tile.x)

echo "Testing melee fighters face each other at standoff"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[3].placePudge(40, 64)
  game.world.pudges[0].facing = heading(WorldScale, 0)
  game.world.pudges[3].facing = heading(WorldScale, 0)
  game.world.pudges[0].bindPudgeBody()
  game.world.pudges[3].bindPudgeBody()
  doAssert applyAttackTarget(
    game.world,
    game.world.pudges[0].id,
    game.world.pudges[3].id
  )
  doAssert applyAttackTarget(
    game.world,
    game.world.pudges[3].id,
    game.world.pudges[0].id
  )
  game.play(40)
  assertApart(
    game.world.pudges[0],
    game.world.pudges[3],
    "melee must hold the new min separation"
  )
  doAssert livingSeparation(game.world.pudges[0], game.world.pudges[3]) <=
      int64(MeleeRange) + int64(WorldScale),
    "fighters should stop at fight distance, not pass through"
  doAssert facingDot(game.world.pudges[0], game.world.pudges[3].position) > 0,
    "west must face the opponent's center"
  doAssert facingDot(game.world.pudges[3], game.world.pudges[0].position) > 0,
    "east must face the opponent's center"
  doAssert game.world.pudges[0].facing.x > 0
  doAssert game.world.pudges[3].facing.x < 0
  doAssert game.world.pudges[3].hp < BaseHitPoints, "standoff melee must connect"

echo "Testing a 3-stack is forced apart in one tick"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 50)
  game.world.pudges[1].placePudge(30, 50)
  game.world.pudges[2].placePudge(30, 50)
  doAssert distSq(
    game.world.pudges[0].position,
    game.world.pudges[1].position
  ) == 0
  game.play(1)
  for i in 0 ..< 3:
    for j in i + 1 ..< 3:
      assertApart(
        game.world.pudges[i],
        game.world.pudges[j],
        "three living units forced to one point"
      )

echo "Testing two walkers cannot share a waterline tile"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 60)
  game.world.pudges[1].placePudge(40, 68)
  doAssert applyWalkTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayWestMax),
    64
  )
  doAssert applyWalkTo(
    game.world,
    game.world.pudges[1].id,
    int32(PlayWestMax),
    64
  )
  game.play(80)
  assertApart(
    game.world.pudges[0],
    game.world.pudges[1],
    "two bots walking the same waterline tile"
  )

echo "Testing opposing hooks deny by intercepting over the river"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(PlayWestMax, 48)
  game.world.pudges[3].placePudge(PlayEastMin, 48)
  let
    westHp = game.world.pudges[0].hp
    eastHp = game.world.pudges[3].hp
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayEastMin),
    48
  )
  doAssert applyHookTo(
    game.world,
    game.world.pudges[3].id,
    int32(PlayWestMax),
    48
  )
  var denied = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hookDenies > 0:
      denied = true
      break
  doAssert denied, "hooks that meet over the river should clash"
  doAssert game.world.chunkerId != 0
  doAssert game.world.chunkVictimId != 0
  doAssert game.world.chunkOwnerId != 0
  doAssert game.world.pudges[0].hp == westHp,
    "a clash must not damage the interceptor"
  doAssert game.world.pudges[3].hp == eastHp,
    "a clash must not damage the intercepted thrower"
  doAssert game.world.hooks.len == 0, "both chains break on a shuriken clash"
  doAssert game.world.pudges[0].state == Alive
  doAssert game.world.pudges[3].state == Alive

echo "Testing a hook aimed off the map reflects and keeps flying"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(RiverCenterX, 20)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 40)
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(RiverCenterX),
    0
  )
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  let throwZ = game.world.hooks[0].heading.z
  doAssert throwZ < 0, "the throw should head toward the north edge"
  var bounced = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].heading.z != throwZ:
      bounced = true
      doAssert game.world.hooks[0].heading.z > 0,
        "the north map edge should reverse Z"
      doAssert abs(game.world.hooks[0].heading.z) >=
          abs(game.world.hooks[0].heading.x),
        "a head-on rim hit should stay a Z bounce"
      doAssert game.world.hooks[0].phase == HookFlying,
        "a rebound with range left should keep flying"
      doAssert game.world.hooks[0].bounces.len >= 1
      doAssert game.world.hooks[0].traveled < game.world.hooks[0].range
      break
  doAssert bounced, "a hook aimed off the map should rebound"

echo "Testing the fountain reflects a hook instead of killing it"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(PlayWestMax, IslandCenterZ)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(PlayEastMin, IslandCenterZ)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 88)
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(IslandCenterX),
    int32(IslandCenterZ)
  )
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  let throwX = game.world.hooks[0].heading.x
  doAssert throwX > 0
  var bounced = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].heading.x != throwX:
      bounced = true
      doAssert game.world.hooks[0].heading.x < 0,
        "the fountain should reverse X"
      doAssert abs(game.world.hooks[0].heading.x) >=
          abs(game.world.hooks[0].heading.z),
        "a head-on fountain hit should stay an X bounce"
      doAssert game.world.hooks[0].phase == HookFlying or
          game.world.hooks[0].phase == HookReeling
      doAssert game.world.hooks[0].bounces.len >= 1
      break
  doAssert bounced, "the fountain should rebound a hook with range left"
  doAssert game.world.pudges[3].hp == BaseHitPoints,
    "a rebound must not punch through the fountain to the far bank"
  doAssert game.world.hookHits == 0

echo "Testing a glancing fountain hit still bounces without orbiting"
block:
  ## Fog-poke through mid, aimed a few tiles off the island center.
  ## A tangent hit on the pixelated rock disk used to slide around it
  ## and pin the chain. The fountain is a convex cylinder: one
  ## ricochet, leftover range, no punch-through.
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(PlayWestMax, IslandCenterZ)
  game.world.pudges[3].placePudge(PlayEastMin, IslandCenterZ + 8)
  let farHp = game.world.pudges[3].hp
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayEastMin + 8),
    int32(IslandCenterZ + 8)
  )
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  var
    maxBounces = 0
    nearTicks = 0
    islandTicks = 0
    bounced = false
  let fountain = islandFountainPos()
  for _ in 0 ..< 200:
    if game.world.hooks.len == 0:
      break
    let hook = game.world.hooks[0]
    maxBounces = max(maxBounces, hook.bounces.len)
    if hook.bounces.len > 0:
      bounced = true
    let tile = tileOf(hook.position)
    if islandTile(tile.x, tile.z):
      inc islandTicks
    if distSq(hook.position, fountain) <=
        int64(5 * WorldScale) * int64(5 * WorldScale):
      inc nearTicks
    game.play(1)
  doAssert bounced, "the fountain must still rebound the throw"
  doAssert maxBounces <= 2, "a glance must not rattle around the fountain"
  doAssert islandTicks <= 4, "the head must not sit in the rocks"
  doAssert nearTicks <= 40, "the chain must not orbit the fountain"
  doAssert game.world.pudges[3].hp == farHp
  doAssert game.world.pudges[3].hookedBy == 0
  doAssert game.world.hookHits == 0,
    "a fountain bounce must not punch through to the far bank"

echo "Testing a grapple does not latch the fountain"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(PlayWestMax, IslandCenterZ)
  let start = game.world.pudges[0].position
  doAssert applyGrappleTo(
    game.world,
    game.world.pudges[0].id,
    int32(IslandCenterX),
    int32(IslandCenterZ)
  )
  game.play(int(HookWindupTicks) + 80)
  doAssert game.world.pudges[0].hookedBy == 0
  if game.world.hooks.len > 0:
    doAssert not game.world.hooks[0].grappleLatched,
      "the fountain is not a grapple latch"
    let tile = tileOf(game.world.hooks[0].position)
    doAssert not islandTile(tile.x, tile.z),
      "a grapple head must not sit in the fountain"
  doAssert distSq(game.world.pudges[0].position, start) <
      int64(4 * WorldScale) * int64(4 * WorldScale),
    "a fountain grapple must not yank the caster onto the rocks"

echo "Testing a rebounded hook can still latch a unit"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(PlayWestMax, IslandCenterZ)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(PlayWestMax - 10, IslandCenterZ)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  let startHp = game.world.pudges[3].hp
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(IslandCenterX),
    int32(IslandCenterZ)
  )
  var
    bounced = false
    latched = false
  for _ in 0 ..< 200:
    game.play(1)
    if game.world.hooks.len > 0 and game.world.hooks[0].bounces.len > 0:
      bounced = true
    if game.world.pudges[3].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert bounced, "the hook should bounce before the latch"
  doAssert latched, "after rebound the hook should still grab the first unit"
  doAssert game.world.pudges[3].hp == startHp - BaseHookDamage,
    "an enemy latched after rebound still takes hook damage"

echo "Testing an ally hook latches and pulls without damage"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[1].placePudge(48, 64)
  let
    hp = game.world.pudges[1].hp
    start = game.world.pudges[1].position
    owner = game.world.pudges[0].position
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 48, 64)
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[1].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert latched, "allies must be latch targets"
  doAssert game.world.pudges[1].hp == hp, "allies take no hook damage"
  game.play(80)
  doAssert game.world.pudges[1].hp == hp
  doAssert game.world.pudges[1].hookedBy == 0
  doAssert abs(game.world.pudges[1].position.x - owner.x) <=
      PudgeCollisionRadius * 2 + WorldScale,
    "the ally should be pulled back along the chain"
  doAssert abs(game.world.pudges[1].position.x - start.x) > WorldScale
  assertApart(
    game.world.pudges[0],
    game.world.pudges[1],
    "an ally hook drop must not stack the pair"
  )

echo "Testing a hook grabs the first unit even when that unit is an ally"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[1].placePudge(48, 64)
  game.world.pudges[3].placePudge(51, 64)
  let enemyHp = game.world.pudges[3].hp
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 51, 64)
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[1].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert latched, "the nearer ally should stop the hook"
  doAssert game.world.pudges[1].hp == BaseHitPoints
  doAssert game.world.pudges[3].hp == enemyHp, "the hook must not pierce"
  doAssert game.world.pudges[3].hookedBy == 0

echo "Testing a reeled victim stays on the hook's flight path"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(38, 56)
  game.world.pudges[3].placePudge(50, 68)
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 50, 68)
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  let
    origin = game.world.hooks[0].origin
    throwHeading = game.world.hooks[0].heading
  var
    latched = false
    samples = 0
  for _ in 0 ..< 120:
    game.play(1)
    if game.world.pudges[3].hookedBy != game.world.pudges[0].id:
      if latched:
        break
      continue
    latched = true
    inc samples
    doAssert onHookLine(
      origin,
      game.world.pudges[3].position,
      throwHeading,
      WorldScale
    ), "the victim left the hook line during the reel"
    if game.world.hooks.len > 0:
      doAssert onHookLine(
        origin,
        game.world.hooks[0].position,
        throwHeading,
        WorldScale
      )
  doAssert latched, "the diagonal hook never grabbed"
  doAssert samples >= 2, "the reel should last more than one tick"
  doAssert game.world.pudges[3].hookedBy == 0
  let landed = game.world.pudges[3].position
  doAssert onHookLine(origin, landed, throwHeading, WorldScale),
    "landing must stay on the chain, not snap sideways"
  doAssert abs(landed.z - game.world.pudges[0].position.z) > WorldScale div 4,
    "a diagonal pull should not dump the victim onto the caster's Z"

echo "Testing an already-hooked ally is not headshot"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(36, 64)
  game.world.pudges[1].placePudge(48, 64)
  # Pin the ally on a teammate's chain (see the headshot test above).
  game.world.pudges[1].hookedBy = game.world.pudges[0].id
  let hp = game.world.pudges[1].hp
  game.world.pudges[2].placePudge(44, 64)
  doAssert applyHookTo(game.world, game.world.pudges[2].id, 48, 64)
  var latched = false
  for _ in 0 ..< 24:
    game.play(1)
    if game.world.pudges[1].hookedBy == game.world.pudges[2].id:
      latched = true
      break
  doAssert latched, "the second ally hook should steal the latch"
  doAssert game.world.pudges[1].state == Alive, "allies are not headshot"
  doAssert game.world.pudges[1].hp == hp
  doAssert game.world.headshots == 0

echo "Testing the decision rotation reaches the state hash"
block:
  let game = freshGame()
  let base = game.stateHash()
  game.world.heroTurnStart = 1
  doAssert game.stateHash() != base,
    "heroTurnStart is authoritative but does not reach stateHash"
  game.world.heroTurnStart = 0
  doAssert game.stateHash() == base

echo "Testing clone is an independent copy"
block:
  let game = freshGame()
  game.play(8)
  let
    snapshot = game.world.clone()
    before = game.stateHash()
    savedHp = game.world.pudges[0].hp
    alias = game.world
  game.world.pudges[0].hp = savedHp - 1
  doAssert game.stateHash() != before, "live world should diverge after a write"
  doAssert snapshot.pudges[0].hp == savedHp,
    "clone shared its pudges seq with the original"
  game.world.restore(snapshot)
  doAssert game.stateHash() == before, "restore did not reproduce the snapshot"
  doAssert game.world == alias, "restore rebound the ref instead of assigning"
  doAssert game.world != snapshot

echo "Testing live history seek does not skip recorded actions"
block:
  let game = freshGame()
  loadBots(game, [BotGroup(
    path: "examples/pudge_wars/players/base.bas",
    count: PudgeCount
  )])
  startRecording(game, 80)
  const
    SnapAfter = 20
    LiveTicks = 40
  var snapshot: World
  for i in 1 .. LiveTicks:
    tickWorld(game, proc() = runBotDecisions(game))
    if i == SnapAfter:
      snapshot = game.world.clone()
  doAssert game.recorder.data.actions.len > 0,
    "bots issued no commands during the live window"
  doAssert game.replayPlayer.actionIndex == 0,
    "live recording must not advance the playback cursor"
  let
    frontierTick = game.world.tick
    frontierHash = game.stateHash()
    recordedHashes = game.recorder.data.hashes.len
  game.world.restore(snapshot)
  game.replayPlayer.data = game.recorder.data
  game.replayPlayer.syncCursor(uint32(game.world.tick))
  game.historyPlayback = true
  while game.world.tick < frontierTick:
    tickWorld(game, proc() = runBotDecisions(game))
  doAssert game.world.tick == frontierTick
  doAssert game.stateHash() == frontierHash,
    "catching up from a live seek diverged from the recorded frontier"
  doAssert game.hashCheck.mismatches == 0,
    "history playback reported a hash mismatch"
  doAssert game.recorder.data.hashes.len == recordedHashes,
    "history playback appended hashes to the live tape"
  doAssert game.recordingError.len == 0

echo "Testing a full tape does not crash live recording"
block:
  let game = freshGame()
  startRecording(game, 2)
  game.play(2)
  doAssert game.recorder.data.hashes.len == 2
  game.play(1)
  doAssert game.recordingError.len > 0,
    "ticking past the configured tape should record the error"
  doAssert game.world.tick == 3, "the window should keep simulating"

echo "Testing a different tape game version skips hash checks"
block:
  let live = freshGame()
  startRecording(live, 8)
  live.play(8)
  var data = live.recorder.data
  doAssert data.hashes.len == 8
  data.header.gameVersion = ReplayGameVersion - 1
  for i in 0 ..< data.hashes.len:
    data.hashes[i] = 0xDEADBEEF'u64
  var replay = newGame(map, int32(data.header.setup.maximumTicks), true, data)
  replay.replayPlayer = initReplayPlayer(data)
  replay.historyPlayback = true
  doAssert replay.replayVersionSkew
  while uint32(replay.world.tick) < data.header.setup.maximumTicks:
    tickWorld(replay, proc() = discard)
  doAssert replay.hashCheck.mismatches == 0,
    "older tapes must play without hashing against this sim"

echo "Testing walk plays run then returns to idle"
block:
  let game = freshGame()
  doAssert game.world.pudges[0].animClip == idleClip
  game.world.pudges[0].placePudge(PlayWestMax - 2, 40)
  doAssert applyWalkTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayWestMax),
    40
  )
  game.play(3)
  doAssert game.world.pudges[0].animClip == runClip, "a moving butcher should run"
  doAssert game.world.pudges[0].facing.x > 0, "west should face the walk"
  game.play(40)
  doAssert not game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].animClip == idleClip, "arrival should idle"
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(PlayEastMin),
    40
  )
  doAssert game.world.pudges[0].animClip == attackClip
  doAssert game.world.pudges[0].facing.x > 0, "a hook should face the throw"

echo "Testing two living butchers cannot occupy the same space"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 50)
  game.world.pudges[1].placePudge(40, 50)
  doAssert applyWalkTo(game.world, game.world.pudges[1].id, 30, 50)
  game.play(80)
  assertApart(
    game.world.pudges[0],
    game.world.pudges[1],
    "walking onto an occupied butcher"
  )
  doAssert livingSeparation(game.world.pudges[0], game.world.pudges[1]) <=
      int64(MinSeparation) + int64(WorldScale) * 2,
    "the walker should stop on the occupied circle, not across the bank"

echo "Testing a corpse does not block walking"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(30, 50)
  game.world.pudges[1].placePudge(36, 50)
  game.world.pudges[1].state = Dying
  game.world.pudges[1].hp = 0
  game.world.pudges[1].deathTicks = RespawnTicks * 20
  let corpse = game.world.pudges[1].position
  doAssert applyWalkTo(game.world, game.world.pudges[0].id, 36, 50)
  game.play(80)
  doAssert distSq(game.world.pudges[0].position, corpse) <=
      int64(WorldScale) * int64(WorldScale),
    "a dead butcher must not block the tile"

echo "Testing a bounced hook spends leftover range only"
block:
  let game = freshGame()
  parkPudges(game)
  const
    WallGap = 8 * WorldScale
    Leftover = 10 * WorldScale
  let
    start = WorldPoint(x: 0, z: NorthWallZ + WallGap)
    rangeBudget = WallGap + Leftover
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    phase: HookFlying,
    position: start,
    origin: start,
    prior: start,
    heading: heading(0, -WorldScale),
    range: rangeBudget,
    speed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  var
    bounced = false
    bounceAt = start
    headingAfter = heading(0, -WorldScale)
    traveledAtBounce = 0'i32
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].bounces.len >= 1:
      bounced = true
      bounceAt = game.world.hooks[0].bounces[0]
      headingAfter = game.world.hooks[0].heading
      traveledAtBounce = game.world.hooks[0].traveled
      break
  doAssert bounced, "the north edge should rebound the head"
  doAssert headingAfter.z > 0, "a horizontal wall must negate Z"
  doAssert headingAfter.x == 0, "a north-edge hit must not invent an X heading"
  var finalTraveled = traveledAtBounce
  for _ in 0 ..< 80:
    if game.world.hooks.len == 0:
      break
    finalTraveled = game.world.hooks[0].traveled
    if game.world.hooks[0].phase != HookFlying:
      break
    game.play(1)
  doAssert finalTraveled <= rangeBudget,
    "bounce must not extend max range"
  doAssert finalTraveled < WallGap + rangeBudget,
    "traveled must be D + leftover, not D + R"
  doAssert finalTraveled >= rangeBudget - WorldScale,
    "the leftover 10 tiles after an 8-tile wall hit should be spent"
  let toWall = integerSqrt(distSq(start, bounceAt))
  doAssert abs(toWall - int64(WallGap)) <= int64(WorldScale div 2),
    "the bounce point should be the wall, not a later invented segment"
  doAssert abs(int64(traveledAtBounce) - toWall) <= int64(BaseHookSpeed),
    "traveled at bounce is the path to the wall, not a reset or a bonus range"

echo "Testing bounce leftover is capped in the same tick"
block:
  let game = freshGame()
  parkPudges(game)
  const
    ToWall = 10_000'i32
    Step = 36_000'i32
  let start = WorldPoint(x: 0, z: NorthWallZ + ToWall)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    phase: HookFlying,
    position: start,
    origin: start,
    prior: start,
    heading: heading(WorldScale div 4, -WorldScale),
    range: 80 * WorldScale,
    speed: Step,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  let throwX = game.world.hooks[0].heading.x
  let throwZ = game.world.hooks[0].heading.z
  game.play(1)
  doAssert game.world.hooks.len > 0
  doAssert game.world.hooks[0].bounces.len >= 1
  doAssert game.world.hooks[0].heading.z == -throwZ,
    "the north face should flip Z and keep the angled X"
  doAssert game.world.hooks[0].heading.x == throwX
  doAssert game.world.hooks[0].heading.x != 0,
    "the outgoing segment must stay angled, not parallel to the wall"
  doAssert game.world.hooks[0].traveled <= Step + WorldScale div 8
  doAssert game.world.hooks[0].traveled >= Step - WorldScale div 8,
    "the same tick should spend the leftover 26000 after the 10000 wall hit"

echo "Testing a hook that meets a wall with no range left dies there"
block:
  let game = freshGame()
  parkPudges(game)
  const ToWall = 10_000'i32
  let start = WorldPoint(x: 0, z: NorthWallZ + ToWall)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    phase: HookFlying,
    position: start,
    origin: start,
    prior: start,
    heading: heading(0, -WorldScale),
    range: ToWall,
    speed: 36_000'i32,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  let throwZ = game.world.hooks[0].heading.z
  game.play(1)
  doAssert game.world.hooks.len > 0
  doAssert game.world.hooks[0].heading.z == throwZ,
    "hitting the wall on the last unit of range must not bounce-travel"
  doAssert game.world.hooks[0].bounces.len == 0
  doAssert game.world.hooks[0].traveled <= ToWall + WorldScale div 8
  doAssert game.world.hooks[0].traveled >= ToWall - WorldScale div 8
  doAssert game.world.hooks[0].phase != HookFlying or
      game.world.hooks[0].traveled >= game.world.hooks[0].range

echo "Testing remaining-zero does not grant a free bounce step"
block:
  let game = freshGame()
  parkPudges(game)
  let start = WorldPoint(x: 0, z: NorthWallZ + 10_000'i32)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[0].id,
    team: WestTeam,
    phase: HookFlying,
    position: start,
    origin: start,
    prior: start,
    heading: heading(0, -WorldScale),
    traveled: BaseHookRange,
    range: BaseHookRange,
    speed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  game.play(1)
  doAssert game.world.hooks.len == 0 or
      game.world.hooks[0].bounces.len == 0,
    "a spent hook must not bounce"
  if game.world.hooks.len > 0:
    doAssert game.world.hooks[0].traveled == BaseHookRange
    doAssert game.world.hooks[0].heading.z < 0

echo "Testing the first team to the kill goal wins"
block:
  let game = freshGame()
  game.world.teamKills[WestTeam.ord] = KillGoal
  game.play(1)
  doAssert game.world.gameOver
  doAssert game.world.winner == WestTeam
  let frozen = game.stateHash()
  game.play(8)
  doAssert game.stateHash() == frozen, "ticks after the match should stop"

echo "Testing a custom kill goal ends the match early"
block:
  let game = newGame(map, MatchTicks, false, ReplayData(), 5)
  doAssert game.world.killGoal == 5
  game.world.teamKills[EastTeam.ord] = 5
  game.play(1)
  doAssert game.world.gameOver
  doAssert game.world.winner == EastTeam

echo "Testing command forgiveness snaps unreachable clicks"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(40, 64)
  doAssert applyWalkTo(game.world, west, -50, 700),
    "an off-map click should clamp and snap, not reject"
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert isWalkable(
    int(game.world.pudges[0].layer),
    int(game.world.pudges[0].moveX),
    int(game.world.pudges[0].moveZ)
  )
  doAssert applyWalkTo(game.world, west, int32(RiverCenterX + 3), 64)
  doAssert game.world.pudges[0].moveX <= int32(PlayWestMax),
    "a mid-river click must resolve to this butcher's own bank"

echo "Testing stop drops the order and momentum brakes to rest"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(30, 64)
  doAssert applyWalkTo(game.world, west, 44, 64)
  game.play(10)
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert applyStop(game.world, west)
  doAssert not game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].attackTargetId == 0
  let held = game.world.pudges[0].position
  game.play(12)
  let settled = game.world.pudges[0].position
  doAssert settled.x >= held.x, "the skid must not turn back"
  doAssert distSq(held, settled) <=
      int64(2 * WorldScale) * int64(2 * WorldScale),
    "a stop should skid a fraction of the braking distance, not tiles"
  doAssert game.world.pudges[0].velX == 0 and
      game.world.pudges[0].velZ == 0,
    "braking must reach a full rest"
  game.play(4)
  doAssert game.world.pudges[0].position == settled,
    "a rested butcher must not drift"

echo "Testing the cast point roots, commits, and can be canceled by death"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[3].placePudge(50, 64)
  let caster = game.world.pudges[0].id
  doAssert applyHookTo(game.world, caster, 50, 64)
  doAssert game.world.pudges[0].hookCooldown == HookCooldownTicks,
    "the cooldown starts at the cast, not the release"
  doAssert not applyHookTo(game.world, caster, 50, 60),
    "a second cast during the windup must be rejected"
  doAssert applyWalkTo(game.world, caster, 30, 64),
    "a move order may queue during the windup"
  game.play(2)
  doAssert game.world.pudges[0].position == worldAtTile(40, 64),
    "the caster is rooted for the cast point"
  doAssert applyStop(game.world, caster)
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1,
    "stop does not cancel a committed cast"
  # Dying during the windup swallows the throw: a melee kill lands on
  # the first tick, well inside the cast point.
  let game2 = freshGame()
  game2.world.pudges[0].placePudge(40, 64)
  game2.world.pudges[3].placePudge(43, 64)
  game2.world.pudges[0].hp = 1
  doAssert applyHookTo(game2.world, game2.world.pudges[0].id, 50, 60)
  doAssert applyAttackTarget(
    game2.world,
    game2.world.pudges[3].id,
    game2.world.pudges[0].id
  )
  game2.play(int(HookWindupTicks) + 4)
  doAssert game2.world.pudges[0].state == Dying,
    "the melee blow should land during the cast point"
  doAssert game2.world.hooks.len == 0,
    "death cancels the windup before the head leaves the hand"

echo "Testing spawn protection blocks hooks and melee until the first act"
block:
  let game = freshGame()
  # Kill the east slot and let the sim respawn it on its pad.
  game.world.pudges[3].state = Dying
  game.world.pudges[3].hp = 0
  game.world.pudges[3].deathTicks = 2
  game.play(3)
  doAssert game.world.pudges[3].state == Alive
  doAssert game.world.pudges[3].shieldTicks > 0,
    "a respawn should grant spawn protection"
  doAssert not applyAttackTarget(
    game.world,
    game.world.pudges[0].id,
    game.world.pudges[3].id
  ), "a shielded butcher cannot be attack-targeted"
  # A hook head passes straight through the shield: throw from a west
  # enemy standing six tiles short of the spawn pad.
  let spawnTile = tileOf(game.world.pudges[3].position)
  game.world.pudges[0].placePudge(spawnTile.x - 6, spawnTile.z)
  doAssert applyHookTo(
    game.world,
    game.world.pudges[0].id,
    int32(spawnTile.x),
    int32(spawnTile.z)
  )
  var flewPast = false
  for _ in 0 ..< 40:
    game.play(1)
    if game.world.pudges[3].shieldTicks <= 0:
      break
    if game.world.hooks.len > 0 and
        game.world.hooks[0].traveled > 7 * WorldScale:
      flewPast = true
      break
  doAssert flewPast, "the head should fly through spawn protection"
  doAssert game.world.pudges[3].hookedBy == 0
  # Acting breaks what is left of the shield.
  doAssert applyWalkTo(
    game.world,
    game.world.pudges[3].id,
    int32(spawnTile.x + 2),
    int32(spawnTile.z)
  )
  doAssert game.world.pudges[3].shieldTicks == 0,
    "walking must forfeit spawn protection"

echo "Testing the fountain heals only on the own pad"
block:
  let game = freshGame()
  game.world.pudges[0].hp = 100
  let westStart = game.world.pudges[0].hp
  game.play(int(FountainHealPeriodTicks) * 3)
  doAssert game.world.pudges[0].hp > westStart,
    "idling on the own pad should heal"
  let healed = game.world.pudges[0].hp
  game.world.pudges[0].placePudge(40, 64)
  let westHome = game.world.pudges[0].spawnTile
  game.world.pudges[3].placePudge(westHome.x, westHome.z)
  game.world.pudges[3].hp = 100
  game.play(int(FountainHealPeriodTicks) * 3)
  doAssert game.world.pudges[3].hp == 100,
    "an enemy pad must not heal a guest"
  doAssert game.world.pudges[0].hp == healed,
    "leaving the pad should stop the heal"

echo "Testing the mid-river fountain heals anyone close to it"
block:
  let game = freshGame()
  parkPudges(game)
  let
    pulse = islandFountainHeal(game.world.pudges[0].maxHp)
    ticks = int(IslandFountainHealPeriodTicks)
  doAssert IslandFountainRadius >
    int32(RiverHalfWidth + 1) * WorldScale,
    "both banks' mid lips must sit inside the fountain disk"
  game.world.pudges[0].placePudge(PlayWestMax, IslandCenterZ)
  game.world.pudges[0].hp = 100
  doAssert game.world.pudges[0].onIslandFountain
  game.play(ticks)
  doAssert game.world.pudges[0].hp == 100 + pulse,
    "the west river lip at mid should take the WC3 fountain aura"
  game.world.pudges[3].placePudge(PlayEastMin, IslandCenterZ)
  game.world.pudges[3].hp = 100
  doAssert game.world.pudges[3].onIslandFountain
  game.play(ticks)
  doAssert game.world.pudges[3].hp == 100 + pulse,
    "the fountain is neutral: east heals too"
  game.world.pudges[1].placePudge(PlayWestMax, 40)
  game.world.pudges[1].hp = 100
  doAssert not game.world.pudges[1].onIslandFountain,
    "the side lane's river lip is outside the disk"
  game.play(ticks)
  doAssert game.world.pudges[1].hp == 100,
    "a bank lip far from mid must not heal"
  game.world.pudges[0].placePudge(40, 64)
  let inland = game.world.pudges[0].hp
  game.play(ticks)
  doAssert game.world.pudges[0].hp == inland,
    "walking inland off the fountain should stop the aura"

echo "Testing the river fountain still heals a swimmer next to the rocks"
block:
  let game = freshGame()
  parkPudges(game)
  let
    pulse = islandFountainHeal(game.world.pudges[0].maxHp)
    ticks = int(IslandFountainHealPeriodTicks)
  game.world.pudges[0].placePudge(RiverCenterX + 4, IslandCenterZ)
  game.world.pudges[0].hp = 400
  doAssert game.world.pudges[0].inRiver
  doAssert game.world.pudges[0].onIslandFountain
  doAssert not islandTile(RiverCenterX + 4, IslandCenterZ)
  game.world.pudges[3].placePudge(RiverCenterX, 30)
  game.world.pudges[3].hp = 400
  doAssert game.world.pudges[3].inRiver
  doAssert not game.world.pudges[3].onIslandFountain
  game.play(ticks)
  doAssert game.world.pudges[0].hp == game.world.pudges[3].hp + pulse,
    "drown still ticks; the fountain aura is extra HP on top"

echo "Testing pings are recorded, team-scoped, and capped"
block:
  let game = freshGame()
  doAssert applyPing(game.world, game.world.pudges[0].id, 44, 60)
  doAssert game.world.pings.len == 1
  var ping: Ping
  doAssert latestTeamPing(game.world, WestTeam, ping)
  doAssert ping.x == 44 and ping.y == 60
  doAssert ping.byId == game.world.pudges[0].id
  doAssert not latestTeamPing(game.world, EastTeam, ping),
    "a west ping must stay invisible to east"
  for i in 0 ..< 12:
    doAssert applyPing(
      game.world,
      game.world.pudges[3].id,
      int32(70 + i mod 4),
      50
    )
  doAssert game.world.pings.len <= 8, "the ping buffer must stay bounded"
  doAssert latestTeamPing(game.world, EastTeam, ping)

echo "Testing outbound hook speed climbs then freezes at range"
block:
  let game = freshGame()
  parkPudges(game)
  const FlyRange = 20 * WorldScale
  discard game.addFlyingHook(WorldPoint(x: 0, z: 0), WorldScale, 0, FlyRange)
  game.play(1)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  let speed1 = game.world.hooks[0].speed
  doAssert speed1 > BaseHookSpeed, "the first outbound tick should accelerate"
  game.play(7)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  let speedN = game.world.hooks[0].speed
  doAssert speedN > speed1, "outbound speed must climb each tick, not step"
  var
    hitLimit = false
    speedAtLimit = speedN
    peakAtLimit = game.world.hooks[0].peakSpeed
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].traveled >= game.world.hooks[0].range or
        game.world.hooks[0].phase != HookFlying:
      hitLimit = true
      speedAtLimit = game.world.hooks[0].speed
      peakAtLimit = game.world.hooks[0].peakSpeed
      break
  doAssert hitLimit, "a 20-tile throw should spend its range"
  doAssert speedAtLimit <= HookSpeedMax
  doAssert peakAtLimit == speedAtLimit
  doAssert peakAtLimit < HookSpeedMax,
    "a short throw should freeze below the cap when range runs out"
  for _ in 0 ..< 5:
    if game.world.hooks.len == 0:
      break
    game.play(1)
    if game.world.hooks.len == 0:
      break
    doAssert game.world.hooks[0].speed == speedAtLimit,
      "speed must not climb after traveled hits max range"
    doAssert game.world.hooks[0].peakSpeed == peakAtLimit

echo "Testing a latch reels at peak outbound speed, not base"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[3].placePudge(52, 64)
  game.world.pudges[4].placePudge(105, 40)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0
  )
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].phase == HookReeling and
        game.world.hooks[0].victimId == game.world.pudges[3].id:
      latched = true
      break
  doAssert latched, "the waterline butcher should be grabbed"
  doAssert game.world.hooks[0].peakSpeed > BaseHookSpeed
  doAssert game.world.hooks[0].peakSpeed <= HookSpeedMax
  doAssert game.world.hooks[0].peakSpeed != BaseHookSpeed * HookReelMul
  let
    peak = game.world.hooks[0].peakSpeed
    before = game.world.hooks[0].position
  game.play(1)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookReeling
  let moved = integerSqrt(distSq(before, game.world.hooks[0].position))
  doAssert abs(moved - int64(peak)) <= int64(WorldScale div 8),
    "reel step must be the peak outbound speed, not BaseHookSpeed or 2×"

echo "Testing an early latch reels at the peak reached so far"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[3].placePudge(46, 64)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0
  )
  var latched = false
  for _ in 0 ..< 40:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].phase == HookReeling and
        game.world.hooks[0].victimId == game.world.pudges[3].id:
      latched = true
      break
  doAssert latched, "a nearby butcher should latch before the cap"
  let peak = game.world.hooks[0].peakSpeed
  doAssert peak < HookSpeedMax, "an early latch must freeze below the cap"
  doAssert peak > BaseHookSpeed
  let before = game.world.hooks[0].position
  game.play(1)
  doAssert game.world.hooks.len == 1
  let moved = integerSqrt(distSq(before, game.world.hooks[0].position))
  doAssert abs(moved - int64(peak)) <= int64(WorldScale div 8),
    "early reel must use the peak reached, not the cap"

echo "Testing leftover bounce is 90 range / 80 wall / 10 leftover"
block:
  let game = freshGame()
  parkPudges(game)
  const
    WallGap = 80 * WorldScale
    Leftover = 10 * WorldScale
    RangeBudget = 90 * WorldScale
  let start = WorldPoint(x: 0, z: NorthWallZ + WallGap)
  discard game.addFlyingHook(start, 0, -WorldScale, RangeBudget)
  var
    bounced = false
    speedAtBounce = BaseHookSpeed
    traveledAtBounce = 0'i32
  for _ in 0 ..< 200:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].bounces.len >= 1:
      bounced = true
      speedAtBounce = game.world.hooks[0].speed
      traveledAtBounce = game.world.hooks[0].traveled
      break
  doAssert bounced, "the 80-tile wall should rebound a 90-tile throw"
  doAssert speedAtBounce > BaseHookSpeed,
    "a bounce must not reset outbound speed"
  doAssert game.world.hooks[0].traveled == traveledAtBounce or
      game.world.hooks[0].traveled >= traveledAtBounce
  var finalTraveled = traveledAtBounce
  for _ in 0 ..< 80:
    if game.world.hooks.len == 0:
      break
    finalTraveled = game.world.hooks[0].traveled
    if game.world.hooks[0].phase != HookFlying:
      break
    game.play(1)
  doAssert finalTraveled <= RangeBudget,
    "speed climb must not extend max range"
  doAssert finalTraveled < WallGap + RangeBudget,
    "traveled must be D + leftover, not D + R"
  doAssert finalTraveled >= RangeBudget - WorldScale,
    "the leftover 10 tiles after an 80-tile wall hit should be spent"

proc westBounceTree(): tuple[x, z: int] =
  ## A west-bank bounce tree with a clear inland approach so the throw
  ## does not spawn inside another trunk.
  result = (-1, -1)
  for z in PlayZMin .. PlayZMax:
    for x in PlayWestMin + 10 .. PlayWestMax - 2:
      if not fieldTreeTile(x, z):
        continue
      var clear = true
      for dx in 1 .. 8:
        if fieldTreeTile(x - dx, z) or
            not isWalkable(WestLayer, x - dx, z):
          clear = false
          break
      if clear and isWalkable(WestLayer, x - 8, z + 3):
        return (x, z)

echo "Testing a field tree rebounds a hook"
block:
  let game = freshGame()
  parkPudges(game)
  let (tx, tz) = westBounceTree()
  doAssert tx >= 0, "seed 2026 must plant a west bounce tree"
  game.world.pudges[0].placePudge(tx - 8, tz)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 88)
  let id = game.world.pudges[0].id
  doAssert applyHookTo(game.world, id, int32(tx), int32(tz))
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  let throwX = game.world.hooks[0].heading.x
  doAssert throwX > 0
  var bounced = false
  for _ in 0 ..< 120:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].bounces.len >= 1:
      bounced = true
      doAssert game.world.hooks[0].heading.x <= 0 or
          game.world.hooks[0].heading.z != 0,
        "a tree bounce must deflect the throw"
      break
  doAssert bounced, "a hook into a field tree must rebound"

echo "Testing a glancing tree hit curves the heading"
block:
  let game = freshGame()
  parkPudges(game)
  let (tx, tz) = westBounceTree()
  doAssert tx >= 0
  # Stand south-west of the trunk and throw at its center so contact
  # is off the west-face midpoint; the cylindrical bounce should keep
  # both heading axes live and not be a pure axis flip.
  game.world.pudges[0].placePudge(tx - 8, tz + 3)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 88)
  let id = game.world.pudges[0].id
  doAssert applyHookTo(game.world, id, int32(tx), int32(tz))
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  let
    throwX = game.world.hooks[0].heading.x
    throwZ = game.world.hooks[0].heading.z
  doAssert throwX > 0
  doAssert throwZ < 0
  var bounced = false
  for _ in 0 ..< 120:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].bounces.len >= 1:
      bounced = true
      let
        hx = game.world.hooks[0].heading.x
        hz = game.world.hooks[0].heading.z
      doAssert hx != throwX or hz != throwZ, "the glance must change heading"
      doAssert hx != 0 and hz != 0,
        "a glancing tree bounce must keep a curved two-axis heading"
      let pureAxis =
        (hx == -throwX and hz == throwZ) or
        (hx == throwX and hz == -throwZ) or
        (hx == -throwX and hz == -throwZ)
      doAssert not pureAxis,
        "a tree bounce must curve off the trunk, not axis-flip"
      break
  doAssert bounced, "the glancing throw must hit the tree"

echo "Testing a tree bounce does not pin the chain to the trunk"
block:
  ## A glance used to slide around the square tree tile, record a
  ## bounce every nudge, and leave the head sitting in the trunk.
  ## Same cylinder eject as the fountain: one ricochet, then leave.
  let game = freshGame()
  parkPudges(game)
  let (tx, tz) = westBounceTree()
  doAssert tx >= 0
  game.world.pudges[0].placePudge(tx - 8, tz + 3)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[4].placePudge(105, 64)
  game.world.pudges[5].placePudge(105, 88)
  let id = game.world.pudges[0].id
  doAssert applyHookTo(game.world, id, int32(tx), int32(tz))
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  var
    maxBounces = 0
    treeTicks = 0
    bounced = false
  for _ in 0 ..< 200:
    if game.world.hooks.len == 0:
      break
    let hook = game.world.hooks[0]
    maxBounces = max(maxBounces, hook.bounces.len)
    if hook.bounces.len > 0:
      bounced = true
    let tile = tileOf(hook.position)
    if fieldTreeTile(tile.x, tile.z):
      inc treeTicks
    game.play(1)
  doAssert bounced, "the throw must still rebound off the tree"
  doAssert maxBounces <= 2, "a glance must not rattle around the trunk"
  doAssert treeTicks <= 4, "the head must not sit in the tree"

echo "Testing the shuriken disk latches when a blade overlaps a body"
block:
  let reach = BaseHookRadius + PudgeCollisionRadius
  block hitNearEdge:
    let game = freshGame()
    parkPudges(game)
    game.world.pudges[3].placePudge(50, 64)
    let victim = game.world.pudges[3].position
    discard game.addFlyingHook(
      WorldPoint(x: victim.x - reach + WorldScale div 8, z: victim.z),
      0,
      WorldScale
    )
    game.play(1)
    doAssert game.world.hooks.len == 1
    doAssert game.world.hooks[0].victimId == game.world.pudges[3].id,
      "a unit just inside shurikenRadius + bodyRadius must latch"
  block missJustOutside:
    let game = freshGame()
    parkPudges(game)
    game.world.pudges[3].placePudge(50, 64)
    let victim = game.world.pudges[3].position
    discard game.addFlyingHook(
      WorldPoint(x: victim.x - reach - WorldScale div 8, z: victim.z),
      0,
      WorldScale
    )
    game.play(1)
    doAssert game.world.hooks.len == 1
    doAssert game.world.hooks[0].victimId == 0,
      "a unit just outside shurikenRadius + bodyRadius must miss"
    doAssert game.world.pudges[3].hp == BaseHitPoints
  block oldCenterOnlyMiss:
    let game = freshGame()
    parkPudges(game)
    game.world.pudges[3].placePudge(50, 64)
    let victim = game.world.pudges[3].position
    # Hub is 2 tiles away: the old 1-tile center hitbox missed, but the
    # 3.5-tile blade overlaps the 2.6-tile body.
    discard game.addFlyingHook(
      WorldPoint(x: victim.x - 2 * WorldScale, z: victim.z),
      0,
      WorldScale
    )
    game.play(1)
    doAssert game.world.hooks.len == 1
    doAssert game.world.hooks[0].victimId == game.world.pudges[3].id,
      "a blade overlap that used to miss the 1-tile hub must now hit"
  block sweptSkip:
    let game = freshGame()
    parkPudges(game)
    game.world.pudges[3].placePudge(50, 64)
    let
      victim = game.world.pudges[3].position
      side = reach - WorldScale div 8
    # Endpoints sit outside the latch disk; the swept path clips the body.
    discard game.addFlyingHook(
      WorldPoint(x: victim.x - 8 * WorldScale, z: victim.z - side),
      WorldScale,
      0,
      80 * WorldScale,
      16 * WorldScale
    )
    game.play(1)
    doAssert game.world.hooks.len == 1
    doAssert game.world.hooks[0].victimId == game.world.pudges[3].id,
      "a fast head must latch on the sweep, not only at the new hub"

echo "Testing a missed hook latches on the return trip"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0,
    24 * WorldScale
  )
  let passX = worldAtTile(36, 64).x
  var passed = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].position.x >= passX:
      passed = true
      break
  doAssert passed, "the head should fly past the later latch tile"
  doAssert game.world.hooks[0].phase == HookFlying
  doAssert game.world.hooks[0].victimId == 0
  game.world.pudges[3].placePudge(32, 64)
  let hp = game.world.pudges[3].hp
  var
    latched = false
    peakAtLatch = 0'i32
  for _ in 0 ..< 80:
    game.play(1)
    doAssert game.world.pudges[0].hookedBy == 0,
      "the caster must not hook themselves on retract"
    if game.world.pudges[3].hookedBy == game.world.pudges[0].id:
      latched = true
      if game.world.hooks.len > 0:
        peakAtLatch = game.world.hooks[0].peakSpeed
      break
  doAssert latched, "the return trip should grab the unit the outbound miss"
  doAssert game.world.pudges[3].hp == hp - BaseHookDamage
  doAssert peakAtLatch > BaseHookSpeed
  if game.world.hooks.len > 0:
    doAssert game.world.hooks[0].phase == HookReeling
    doAssert game.world.hooks[0].peakSpeed == peakAtLatch,
      "a return latch must keep peak reel speed"
    let before = game.world.hooks[0].position
    game.play(1)
    doAssert game.world.hooks.len == 1
    let moved = integerSqrt(distSq(before, game.world.hooks[0].position))
    doAssert abs(moved - int64(peakAtLatch)) <= int64(WorldScale div 8),
      "return latch must keep reeling at peakSpeed, not reset to base"

echo "Testing a return latch uses the shuriken disk, not the hub"
block:
  let
    reach = BaseHookRadius + PudgeCollisionRadius
    graze = 2 * WorldScale
  doAssert graze < reach, "a 2-tile offset must still overlap the blade"
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0,
    24 * WorldScale
  )
  let passX = worldAtTile(36, 64).x
  var passed = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].position.x >= passX:
      passed = true
      break
  doAssert passed
  game.world.pudges[3].placePudge(32, 64)
  game.world.pudges[3].position.z =
    game.world.pudges[3].position.z + graze
  game.world.pudges[3].bindPudgeBody()
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[3].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert latched, "a blade graze on the return trip must latch"

echo "Testing an already-latched hook does not grab a second unit on the way home"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  game.world.pudges[3].placePudge(40, 64)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0
  )
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].victimId == game.world.pudges[3].id:
      latched = true
      break
  doAssert latched, "the first butcher should latch outbound"
  game.world.pudges[4].placePudge(32, 64)
  let secondHp = game.world.pudges[4].hp
  for _ in 0 ..< 80:
    if game.world.hooks.len == 0:
      break
    doAssert game.world.hooks[0].victimId == game.world.pudges[3].id or
        game.world.hooks[0].victimId == 0,
      "the hooked chain must not pick up a second victim"
    doAssert game.world.pudges[4].hookedBy == 0
    game.play(1)
  doAssert game.world.pudges[4].hookedBy == 0
  doAssert game.world.pudges[4].hp == secondHp,
    "a bystander on the reel path takes no hook damage"

echo "Testing an ally return-catch pulls without damage"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[3].placePudge(105, 88)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0,
    24 * WorldScale
  )
  let passX = worldAtTile(36, 64).x
  var passed = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].position.x >= passX:
      passed = true
      break
  doAssert passed
  game.world.pudges[1].placePudge(32, 64)
  let hp = game.world.pudges[1].hp
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[1].hookedBy == game.world.pudges[0].id:
      latched = true
      break
  doAssert latched, "allies must be return-latch targets"
  doAssert game.world.pudges[1].hp == hp, "allies take no return-hook damage"
  game.play(80)
  doAssert game.world.pudges[1].hp == hp
  doAssert game.world.pudges[1].hookedBy == 0
  assertApart(
    game.world.pudges[0],
    game.world.pudges[1],
    "an ally return drop must not stack the pair"
  )

echo "Testing a bounced miss retraces the chain on the way home"
block:
  let game = freshGame()
  parkPudges(game)
  const
    WallGap = 8 * WorldScale
    Leftover = 10 * WorldScale
    RangeBudget = WallGap + Leftover
  let start = WorldPoint(x: 0, z: NorthWallZ + WallGap)
  discard game.addFlyingHook(start, 0, -WorldScale, RangeBudget)
  var bounceAt = start
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].bounces.len >= 1:
      bounceAt = game.world.hooks[0].bounces[0]
    if game.world.hooks[0].phase != HookFlying:
      break
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookReeling
  doAssert game.world.hooks[0].bounces.len >= 1
  let
    before = game.world.hooks[0].position
    toBounceBefore = distSq(before, bounceAt)
  game.play(1)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].bounces.len >= 1,
    "the first reel step should still be on the bounce segment"
  let toBounceAfter = distSq(game.world.hooks[0].position, bounceAt)
  doAssert toBounceAfter < toBounceBefore,
    "an empty rebound must reverse through the bounce, not cut to the caster"

echo "Testing flying hooks that clash deal no damage"
block:
  let game = freshGame()
  parkPudges(game)
  let
    westHp = game.world.pudges[0].hp
    eastHp = game.world.pudges[3].hp
    mid = worldAtTile(64, 40)
  discard game.addFlyingHook(
    WorldPoint(x: mid.x - 8 * WorldScale, z: mid.z),
    WorldScale,
    0,
    20 * WorldScale
  )
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    phase: HookFlying,
    position: WorldPoint(x: mid.x + 8 * WorldScale, z: mid.z),
    origin: WorldPoint(x: mid.x + 8 * WorldScale, z: mid.z),
    prior: WorldPoint(x: mid.x + 8 * WorldScale, z: mid.z),
    heading: heading(-WorldScale, 0),
    range: 20 * WorldScale,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  var denied = false
  for _ in 0 ..< 40:
    game.play(1)
    if game.world.hookDenies > 0:
      denied = true
      break
  doAssert denied, "opposing flying disks should clash"
  doAssert game.world.hooks.len == 0
  doAssert game.world.pudges[0].hp == westHp
  doAssert game.world.pudges[3].hp == eastHp
  doAssert game.world.pudges[0].hookedBy == 0
  doAssert game.world.pudges[3].hookedBy == 0
  doAssert game.world.pudges[0].denyCount == 0 and
      game.world.pudges[3].denyCount == 0,
    "equal-flight clash must not pay deny gold to the earlier-listed hook"
  doAssert game.world.pudges[0].gold == 0 and
      game.world.pudges[3].gold == 0

echo "Testing a flying hook clashing a reel releases without extra damage"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].placePudge(22, 88)
  game.world.pudges[2].placePudge(22, 40)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  game.world.pudges[3].placePudge(40, 64)
  let start = game.world.pudges[0].position
  discard game.addFlyingHook(
    WorldPoint(x: start.x + WorldScale, z: start.z),
    WorldScale,
    0
  )
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    if game.world.hooks[0].phase == HookReeling and
        game.world.hooks[0].victimId == game.world.pudges[3].id:
      latched = true
      break
  doAssert latched
  let hookedHp = game.world.pudges[3].hp
  doAssert hookedHp == BaseHitPoints - BaseHookDamage
  let
    head = game.world.hooks[0].position
    clashR = BaseHookRadius * 2
    gap = clashR + WorldScale div 2
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[4].id,
    team: EastTeam,
    phase: HookFlying,
    position: WorldPoint(x: head.x + gap, z: head.z),
    origin: WorldPoint(x: head.x + gap, z: head.z),
    prior: WorldPoint(x: head.x + gap, z: head.z),
    heading: heading(-WorldScale, 0),
    range: 20 * WorldScale,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  let
    westHp = game.world.pudges[0].hp
    eastHp = game.world.pudges[4].hp
  var denied = false
  for _ in 0 ..< 40:
    game.play(1)
    if game.world.hookDenies > 0:
      denied = true
      break
  doAssert denied, "a flying disk should clash the reeling head"
  doAssert game.world.pudges[3].hp == hookedHp,
    "the hooked butcher must not take clash damage"
  doAssert game.world.pudges[3].hookedBy == 0,
    "a clash should release the hooked butcher"
  doAssert game.world.pudges[0].hp == westHp
  doAssert game.world.pudges[4].hp == eastHp
  doAssert game.world.headshots == 0,
    "the interceptor must clash the head, not headshot the victim"
  doAssert game.world.hooks.len == 0

echo "Testing fine aim casts between tile centers"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(40, 64)
  let caster = game.world.pudges[0].id
  doAssert applyHookFine(
    game.world,
    caster,
    fineOfTile(50),
    fineOfTile(64) + FineAimScale div 2 - 1
  ), "a fine aim inside the map must cast"
  doAssert game.world.pudges[0].hooksThrown == 1
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].heading.z > 0,
    "aiming below the tile center must tilt the throw south"

proc tileOnGrid(t: tuple[x, z: int]): bool =
  t.x >= 0 and t.x < GridTiles and t.z >= 0 and t.z < GridTiles

echo "Testing a grazing hook on the west rim stays on the grid"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(40, 90)
  game.world.pudges[1].placePudge(30, 90)
  let start = worldAtTile(PlayWestMin - 2, 40)
  discard game.addFlyingHook(
    start, -WorldScale div 4, -WorldScale, BaseHookRange
  )
  game.world.hooks[0].speed = HookSpeedMax
  game.world.hooks[0].peakSpeed = HookSpeedMax
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.hooks.len == 0:
      break
    let t = tileOf(game.world.hooks[0].position)
    doAssert tileOnGrid(t),
      "a rebound recovery must not walk the head off the map"
  for pudge in game.world.pudges:
    doAssert tileOnGrid(tileOf(pudge.position)),
      "a rim graze must not pull a butcher off the map"

echo "Testing clash math sheds bits on a cross-map sweep"
block:
  ## Reproduce the OverflowDefect from a 50-tile bounce teleport:
  ## `tNum * az` no longer raises.
  let
    a0 = WorldPoint(x: -651_707, z: 2_895_572)
    a1 = WorldPoint(x: -609_046, z: -90_299)
    b = WorldPoint(x: 2_489_533, z: 1_369_432)
    radius = BaseHookRadius * 2 + HookClashRadius
  discard segmentsWithin(a0, a1, b, b, radius)
  discard segmentsWithin(a1, a0, b, b, radius)
  discard segmentsWithin(
    a0, a1, worldAtTile(20, 20), worldAtTile(100, 100), radius
  )

echo "Testing a south-rim bounce does not teleport the hook"
block:
  ## Diagonal DDA bounce used to assign WorldPoint in-place, zero one
  ## axis, and skip ~50 tiles in one tick.
  let game = freshGame()
  parkPudges(game)
  let start = worldAtTile(53, PlayZMax)
  discard game.addFlyingHook(
    start, -900_000, 1_371_709, BaseHookRange, HookSpeedMax
  )
  game.play(1)
  doAssert game.world.hooks.len == 1, "the head should still be flying"
  let moved = integerSqrt(distSq(start, game.world.hooks[0].position))
  doAssert moved <= int64(HookSpeedMax) + int64(WorldScale) * 4,
    "a rim bounce must not skip across the map, moved " & $moved
  doAssert tileOnGrid(tileOf(game.world.hooks[0].position))

echo "Testing a victim latched during a rim graze stays on the grid"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(40, 90)
  game.world.pudges[1].placePudge(PlayWestMin, 40)
  let start = worldAtTile(PlayWestMin - 2, 40)
  discard game.addFlyingHook(
    start, -WorldScale div 4, -WorldScale, BaseHookRange
  )
  game.world.hooks[0].speed = HookSpeedMax
  game.world.hooks[0].peakSpeed = HookSpeedMax
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    for hook in game.world.hooks:
      doAssert tileOnGrid(tileOf(hook.position)),
        "the latched chain must stay on the grid"
    for pudge in game.world.pudges:
      doAssert tileOnGrid(tileOf(pudge.position)),
        "a victim riding a rim hook must stay on the grid"
    if game.world.pudges[1].hookedBy == game.world.pudges[0].id:
      latched = true
  doAssert latched, "the nearby butcher should latch the recovering head"

echo "Testing a butcher overlapping the north rim can walk east"
block:
  ## Hugging the NW cliff puts the center a sliver into the unwalkable
  ## north row. Axis-slide then refuses a pure-east step (still in that
  ## row) until a north/south key pops them inland. Nudge + inland
  ## dest must let them leave the corner.
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(PlayWestMin, PlayZMin)
  game.world.pudges[0].position.z =
    game.world.pudges[0].position.z - WorldScale div 2 - 1
  game.world.pudges[0].bindPudgeBody()
  doAssert not isWalkable(
    WestLayer,
    tileOf(game.world.pudges[0].position).x,
    tileOf(game.world.pudges[0].position).z
  )
  doAssert applyWalkTo(
    game.world, game.world.pudges[0].id, PlayWestMin + 8, PlayZMin
  )
  game.play(24)
  let t = tileOf(game.world.pudges[0].position)
  doAssert t.x > PlayWestMin,
    "butcher overlapping the north rim must walk east without a W/S jiggle"
  doAssert tileOnGrid(t)
  doAssert t.x >= PlayWestMin and t.z >= PlayZMin

echo "Testing a butcher overlapping the west rim can walk east without a hook"
block:
  ## Center a sliver into tile PlayWestMin-1. Axis-slide's east step
  ## stays in that unwalkable column, so D used to no-op until a hook
  ## settle/eject rebound the body. Nudge + inland dest must walk them
  ## off the tree wall with no cast.
  let game = freshGame()
  parkPudges(game)
  const MidZ = 50
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  game.world.pudges[0].position.x =
    game.world.pudges[0].position.x - WorldScale div 2 - 1
  game.world.pudges[0].bindPudgeBody()
  let startX = game.world.pudges[0].position.x
  let startTile = tileOf(game.world.pudges[0].position)
  doAssert startTile.x < PlayWestMin,
    "the fixture must overlap the west unwalkable strip"
  doAssert applyWalkTo(
    game.world, game.world.pudges[0].id, PlayWestMin + 8, MidZ
  )
  doAssert game.world.pudges[0].moveX > int32(PlayWestMin),
    "D dest must be east of the wall tile they overlap"
  game.play(32)
  doAssert game.world.pudges[0].hooksThrown == 0
  doAssert game.world.hooks.len == 0
  doAssert game.world.pudges[0].position.x > startX + WorldScale,
    "overlapping the west rim must walk east without a hook"
  let t = tileOf(game.world.pudges[0].position)
  doAssert t.x > PlayWestMin
  doAssert t.x >= PlayWestMin and t.z >= PlayZMin
  doAssert tileOnGrid(t)

echo "Testing a west-rim dest clamped to PlayWestMin still walks east"
block:
  ## WASD used to clamp D onto the overlapping wall tile so they
  ## arrived immediately and froze. applyWalkTo must boost inland.
  let game = freshGame()
  parkPudges(game)
  const MidZ = 50
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  game.world.pudges[0].position.x =
    game.world.pudges[0].position.x - WorldScale div 2 - 1
  game.world.pudges[0].bindPudgeBody()
  let startX = game.world.pudges[0].position.x
  doAssert applyWalkTo(
    game.world, game.world.pudges[0].id, int32(PlayWestMin), int32(MidZ)
  )
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].moveX > int32(PlayWestMin),
    "a wall-tile dest while overlapping west must aim inland"
  game.play(32)
  doAssert game.world.pudges[0].position.x > startX + WorldScale,
    "boosted wall dest must still walk east"
  doAssert game.world.pudges[0].hooksThrown == 0

echo "Testing rest nudge pops a west-rim overlap without a walk order"
block:
  let game = freshGame()
  parkPudges(game)
  const MidZ = 50
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  game.world.pudges[0].position.x =
    game.world.pudges[0].position.x - WorldScale div 2 - 1
  game.world.pudges[0].bindPudgeBody()
  let startX = game.world.pudges[0].position.x
  game.play(4)
  doAssert game.world.pudges[0].position.x > startX,
    "idle overlap must soft-nudge inland every tick"
  let t = tileOf(game.world.pudges[0].position)
  doAssert t.x >= PlayWestMin
  doAssert isWalkable(WestLayer, t.x, t.z)

echo "Testing a west butcher walks east from spawn on the opening ticks"
block:
  let game = freshGame()
  let
    pudge = game.world.pudges[0]
    startX = pudge.position.x
    spawn = pudge.spawnTile
  doAssert tileOf(pudge.position).x == spawn.x
  doAssert applyWalkTo(
    game.world, pudge.id, int32(spawn.x + 8), int32(spawn.z)
  )
  game.play(32)
  doAssert game.world.pudges[0].position.x > startX + WorldScale,
    "opening D from a west spawn must not freeze"
  doAssert game.world.pudges[0].hooksThrown == 0
  doAssert tileOf(game.world.pudges[0].position).x > spawn.x

echo "Testing WASD dest at the west rim aims inland of the wall tile"
block:
  let dFromWall = keyboardSteerDest(PlayWestMin, 64, 1, 0)
  doAssert dFromWall.x == PlayWestMin + 8,
    "D hugging PlayWestMin must aim east of the wall, not at it"
  doAssert dFromWall.z == 64
  let dFromOverlap = keyboardSteerDest(PlayWestMin - 1, 50, 1, 0)
  doAssert dFromOverlap.x == PlayWestMin + 8
  let aFromWall = keyboardSteerDest(PlayWestMin, 64, -1, 0)
  doAssert aFromWall.x == PlayWestMin,
    "A at the west lip must stay a no-op, not walk east"
  let spawnD = keyboardSteerDest(WestSpawns[0][0], WestSpawns[0][1], 1, 0)
  doAssert spawnD.x == WestSpawns[0][0] + 8

echo "Testing A at the west lip does not boost inland or orbit"
block:
  ## Tape bug_20260901_134028: Aaron (seat 0, pudge 1) ticks 4328–4593
  ## held A so WASD dest was (14, z). Standing on PlayWestMin used to
  ## boost dest to 22, walk to tile 16, then dest 14 again — a 14↔16
  ## orbit. Dest on the walkable lip must halt, not reverse.
  let game = freshGame()
  parkPudges(game)
  const MidZ = 50
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  let startX = game.world.pudges[0].position.x
  doAssert applyWalkTo(
    game.world, game.world.pudges[0].id, int32(PlayWestMin), int32(MidZ)
  )
  doAssert not game.world.pudges[0].hasMoveTarget,
    "A at the walkable west lip must halt, not aim inland"
  doAssert game.world.pudges[0].moveX <= int32(PlayWestMin) or
      not game.world.pudges[0].hasMoveTarget
  var
    last = (x: -1, z: -1)
    unique: seq[tuple[x, z: int]]
    revisits = 0
  for tick in 0 ..< 80:
    if tick mod 4 == 0:
      discard applyWalkTo(
        game.world, game.world.pudges[0].id, int32(PlayWestMin), int32(MidZ)
      )
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    if t != last:
      var seen = false
      for u in unique:
        if u == t:
          seen = true
      if seen:
        inc revisits
      else:
        unique.add t
      last = t
  doAssert revisits == 0,
    "holding A at the west lip must not revisit tiles (orbit)"
  doAssert unique.len <= 2
  let endTile = tileOf(game.world.pudges[0].position)
  doAssert endTile.x <= PlayWestMin + 1,
    "must not walk a tile inland off a wall-dest"
  doAssert game.world.pudges[0].position.x < startX + WorldScale
  doAssert endTile.x >= PlayWestMin
  doAssert tileOnGrid(endTile)

echo "Testing D then A on the west lip keeps the inland dest"
block:
  ## Tape bug_20260901_162503: Aaron ticks 3890–3912. dest 45 (RMB/D
  ## inland) then dest 14 (A) on PlayWestMin halted and coasted velX
  ## to 0 in one tick — stuck on the last walkable column. A on the
  ## lip must not cancel a live dest at PlayWestMin+8 or further east.
  let game = freshGame()
  parkPudges(game)
  const MidZ = 78
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  let
    id = game.world.pudges[0].id
    startX = game.world.pudges[0].position.x
  doAssert applyWalkTo(game.world, id, int32(PlayWestMin + 8), int32(MidZ))
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].moveX == int32(PlayWestMin + 8)
  doAssert applyWalkTo(game.world, id, int32(PlayWestMin), int32(MidZ)),
    "A dest on the lip must still be accepted"
  doAssert game.world.pudges[0].hasMoveTarget,
    "A on the walkable west lip must not drop a live D dest"
  doAssert game.world.pudges[0].moveX == int32(PlayWestMin + 8),
    "A dest 14 must not replace dest PlayWestMin+8"
  game.play(32)
  doAssert game.world.pudges[0].position.x > startX + WorldScale,
    "D then A on the west lip must still walk east"
  doAssert tileOf(game.world.pudges[0].position).x > PlayWestMin
  doAssert game.world.pudges[0].hooksThrown == 0

echo "Testing west-lip dest 45 then dest 14 spam still walks east"
block:
  ## Same tape: dest 45 at 3890, dest 14 every 4 ticks 3892–3912.
  let game = freshGame()
  parkPudges(game)
  const MidZ = 78
  game.world.pudges[0].placePudge(PlayWestMin, MidZ)
  let
    id = game.world.pudges[0].id
    startX = game.world.pudges[0].position.x
  doAssert applyWalkTo(game.world, id, 45, int32(MidZ + 2))
  var
    leftLip = false
    maxX = startX
  for tick in 0 ..< 40:
    if tick mod 4 == 0:
      discard applyWalkTo(
        game.world, id, int32(PlayWestMin), int32(MidZ)
      )
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    if t.x > PlayWestMin:
      leftLip = true
    if game.world.pudges[0].position.x > maxX:
      maxX = game.world.pudges[0].position.x
  doAssert leftLip,
    "RMB dest 45 then A dest 14 spam must leave PlayWestMin"
  doAssert maxX > startX + WorldScale,
    "must actually walk east, not halt on the lip"

echo "Testing A from inland walks to the west lip and stops"
block:
  let game = freshGame()
  parkPudges(game)
  const MidZ = 50
  game.world.pudges[0].placePudge(PlayWestMin + 3, MidZ)
  var reachedLip = false
  var bouncedEast = false
  for tick in 0 ..< 80:
    if tick mod 4 == 0:
      discard applyWalkTo(
        game.world, game.world.pudges[0].id, int32(PlayWestMin), int32(MidZ)
      )
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    if t.x <= PlayWestMin:
      reachedLip = true
    elif reachedLip and t.x > PlayWestMin + 1:
      bouncedEast = true
  doAssert reachedLip, "A from inland must reach the west lip"
  doAssert not bouncedEast, "arriving at the west lip must not bounce east"
  doAssert tileOf(game.world.pudges[0].position).x <= PlayWestMin + 1

echo "Testing W along the west rim advances without circling"
block:
  let game = freshGame()
  parkPudges(game)
  const StartZ = 64
  game.world.pudges[0].placePudge(PlayWestMin, StartZ)
  var
    last = (x: -1, z: -1)
    unique: seq[tuple[x, z: int]]
    revisits = 0
  for tick in 0 ..< 96:
    if tick mod 4 == 0:
      let t = tileOf(game.world.pudges[0].position)
      let dest = keyboardSteerDest(t.x, t.z, 0, -1)
      discard applyWalkTo(
        game.world, game.world.pudges[0].id, int32(dest.x), int32(dest.z)
      )
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    if t != last:
      var seen = false
      for u in unique:
        if u == t:
          seen = true
      if seen:
        inc revisits
      else:
        unique.add t
      last = t
  let endTile = tileOf(game.world.pudges[0].position)
  doAssert endTile.z <= StartZ - 4,
    "W along the west rim must walk north"
  doAssert endTile.x >= PlayWestMin and endTile.x <= PlayWestMin + 2,
    "must hug the west rim, not drift into the field"
  doAssert revisits == 0,
    "walking the west rim must not circle a 2–4 tile loop"
  doAssert tileOnGrid(endTile)

echo "Testing W into the north lip does not orbit south"
block:
  let game = freshGame()
  parkPudges(game)
  const MidX = 22
  game.world.pudges[0].placePudge(MidX, PlayZMin)
  let startZ = game.world.pudges[0].position.z
  doAssert applyWalkTo(
    game.world, game.world.pudges[0].id, int32(MidX), int32(PlayZMin)
  )
  doAssert not game.world.pudges[0].hasMoveTarget,
    "W at the walkable north lip must halt, not aim inland"
  var revisits = 0
  var last = (x: -1, z: -1)
  var unique: seq[tuple[x, z: int]]
  for tick in 0 ..< 80:
    if tick mod 4 == 0:
      discard applyWalkTo(
        game.world, game.world.pudges[0].id, int32(MidX), int32(PlayZMin)
      )
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    if t != last:
      var seen = false
      for u in unique:
        if u == t:
          seen = true
      if seen:
        inc revisits
      else:
        unique.add t
      last = t
  doAssert revisits == 0
  doAssert tileOf(game.world.pudges[0].position).z <= PlayZMin + 1
  doAssert game.world.pudges[0].position.z < startZ + WorldScale

echo "Testing an off-grid butcher is ejected onto walkable land"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].position = WorldPoint(x: -80 * WorldScale, z: 0)
  game.world.pudges[1].bindPudgeBody()
  doAssert not tileOnGrid(tileOf(game.world.pudges[1].position))
  game.play(1)
  let t = tileOf(game.world.pudges[1].position)
  doAssert tileOnGrid(t), "eject must return the butcher to the grid"
  doAssert t.x >= PlayWestMin and t.x <= PlayWestMax
  doAssert t.z >= PlayZMin and t.z <= PlayZMax
  doAssert isWalkable(WestLayer, t.x, t.z),
    "eject must land on walkable west-bank land"

echo "Testing a second live game on the same map is a clean rematch"
block:
  let dirty = freshGame()
  dirty.world.tick = 80
  dirty.world.teamKills[WestTeam.ord] = 4
  dirty.world.teamKills[EastTeam.ord] = 2
  dirty.world.hooks.add Hook(id: 101'i32, phase: HookFlying)
  dirty.world.runes.add Rune(id: 1'i32, kind: RuneHaste)
  dirty.world.runeClock = 3
  dirty.world.pudges[0].kills = 2
  dirty.world.pudges[0].deaths = 1
  dirty.world.pudges[0].placePudge(50, 50)
  let fresh = newGame(map, MatchTicks, false, ReplayData())
  doAssert fresh.world != dirty.world, "rematch must allocate a new world"
  doAssert fresh.world.tick == 0
  doAssert fresh.world.teamKills[WestTeam.ord] == 0
  doAssert fresh.world.teamKills[EastTeam.ord] == 0
  doAssert fresh.world.hooks.len == 0
  doAssert fresh.world.runes.len == 0
  doAssert fresh.world.runeClock == fresh.world.runePeriod
  doAssert fresh.world.nextHookId == FirstHookId
  doAssert fresh.world.pudges[0].kills == 0
  doAssert fresh.world.pudges[0].deaths == 0
  doAssert fresh.world.pudges[0].hooksThrown == 0
  doAssert fresh.world.pudges[0].position == fresh.world.pudges[0].spawnPosition
  doAssert dirty.world.tick == 80
  doAssert dirty.world.hooks.len == 1

echo "Testing the gold shop pad, inventory, and permanent stats"
block:
  let game = freshGame()
  let id = game.world.pudges[0].id
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[0].gold = 50
  doAssert not game.world.pudges[0].inOwnShop
  doAssert not applyBuyPower(game.world, id, int32(ShopBoots.ord)),
    "cannot buy off the pad"
  game.world.pudges[0].placePudge(WestShopX, ShopZ)
  doAssert game.world.pudges[0].inOwnShop
  game.world.pudges[0].gold = 0
  doAssert not applyBuyPower(game.world, id, int32(ShopBoots.ord)),
    "cannot buy without gold"
  game.world.pudges[0].gold = ShopBootsGold
  let speed0 = topMoveSpeed(game.world.pudges[0])
  doAssert applyBuyPower(game.world, id, int32(ShopBoots.ord))
  doAssert game.world.pudges[0].gold == 0, "gold must be deducted"
  doAssert game.world.pudges[0].itemRank[ShopBoots] == 1
  doAssert topMoveSpeed(game.world.pudges[0]) > speed0
  doAssert game.world.pudges[0].ownedPermanents == 1
  game.world.pudges[0].gold = ShopLongshotGold
  doAssert applyBuyPower(game.world, id, int32(ShopLongshot.ord))
  doAssert game.world.pudges[0].itemRank[ShopLongshot] == 1
  doAssert game.world.pudges[0].ownedPermanents == 2
  game.world.pudges[0].gold = ShopWallGold
  doAssert applyBuyPower(game.world, id, int32(ShopWall.ord))
  doAssert game.world.pudges[0].ownedPermanents == 3
  game.world.pudges[0].gold = ShopMineGold
  doAssert applyBuyPower(game.world, id, int32(ShopMine.ord))
  doAssert game.world.pudges[0].ownedPermanents == 4
  game.world.pudges[0].gold = ShopBootsGold
  doAssert applyBuyPower(game.world, id, int32(ShopBoots.ord)),
    "buy-again must still rank an owned family"
  doAssert game.world.pudges[0].itemRank[ShopBoots] == 2
  game.world.pudges[0].hp = 10
  game.world.pudges[0].gold = ShopFlaskGold
  doAssert applyBuyPower(game.world, id, int32(ShopFlask.ord)),
    "flask stays available with a full inventory"
  doAssert game.world.pudges[0].hp == game.world.pudges[0].maxHp
  let hashed = game.stateHash()
  dec game.world.pudges[0].itemRank[ShopBoots]
  doAssert game.stateHash() != hashed, "inventory ranks must hash"
  inc game.world.pudges[0].itemRank[ShopBoots]
  doAssert game.stateHash() == hashed
  game.world.pudges[0].itemRank[ShopBoots] = ItemMaxRank
  game.world.pudges[0].gold = 99
  doAssert not applyBuyPower(game.world, id, int32(ShopBoots.ord)),
    "max rank must reject"

echo "Testing blink teleports along the aim and truncates to range"
block:
  let game = freshGame()
  parkPudges(game)
  # Banks are 39 tiles deep in X; hop south along a clear 96-tile lane
  # so a max-range clamp can fire without hitting the river, cliff, or
  # the parked west stack at x=22.
  game.world.pudges[0].placePudge(30, 20)
  let
    origin = game.world.pudges[0].position
    id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, 30, 80),
    "open-bank blink must accept"
  let dest = game.world.pudges[0].position
  doAssert dest.z > origin.z, "blink must travel along the aimed heading"
  let d = integerSqrt(distSq(origin, dest))
  doAssert d <= int64(BlinkRange) + int64(WorldScale div 2),
    "blink must not exceed max range"
  doAssert d >= int64(BlinkRange) - int64(WorldScale),
    "a long-aim blink should use nearly the full dodge range"
  doAssert not game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].velX == 0
  doAssert game.world.pudges[0].justBlinked
  doAssert game.world.pudges[0].blinkCooldown == BlinkCooldownTicks
  let tile = tileOf(dest)
  doAssert not riverTile(tile.x)
  doAssert walkableTile(
    game.world.pudges[0].layer, int32(tile.x), int32(tile.z)
  )

echo "Testing blink from the west bank lands in the river"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(int(PlayWestMax) - 1, 48)
  let
    origin = game.world.pudges[0].position
    id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, int32(RiverCenterX), 48),
    "a river-aimed blink must land in the water"
  let dest = game.world.pudges[0].position
  let tile = tileOf(dest)
  doAssert dest.x > origin.x, "a river-aimed blink must still travel"
  doAssert riverTile(tile.x), "blink from a bank onto a river tile"
  doAssert game.world.pudges[0].layer == int32(RiverLayer)
  doAssert game.world.pudges[0].inRiver

echo "Testing blink from a bank cannot clear the river"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[4].placePudge(105, 88)
  game.world.pudges[5].placePudge(110, 40)
  game.world.pudges[0].placePudge(int(PlayWestMax) - 1, 48)
  let
    origin = game.world.pudges[0].position
    id = game.world.pudges[0].id
    destX = int32(PlayEastMin + 4)
  doAssert eastBank(int(destX))
  doAssert BlinkRangeTiles < int32(PlayEastMin - PlayWestMax),
    "blink must be shorter than lip-to-lip across the river"
  doAssert applyBlinkTo(game.world, id, destX, 48),
    "a far-bank click must still fire; range truncates it"
  let dest = game.world.pudges[0].position
  let tile = tileOf(dest)
  doAssert dest.x > origin.x
  doAssert not eastBank(tile.x), "must not land on the far bank"
  doAssert riverTile(tile.x), "a max hop from the lip should splash"
  doAssert game.world.pudges[0].inRiver
  doAssert game.world.pudges[0].layer == int32(RiverLayer)

echo "Testing blink from the river onto east-bank land"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[4].placePudge(105, 88)
  game.world.pudges[5].placePudge(110, 40)
  game.world.pudges[0].placePudge(RiverCenterX, 48)
  doAssert game.world.pudges[0].inRiver
  let id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, int32(PlayEastMin + 4), 48),
    "blink from the river onto a bank must fire"
  let tile = tileOf(game.world.pudges[0].position)
  doAssert not riverTile(tile.x)
  doAssert not game.world.pudges[0].inRiver
  doAssert game.world.pudges[0].layer == int32(EastLayer)
  doAssert eastBank(tile.x)
  game.world.pudges[0].blinkCooldown = 0
  game.world.pudges[0].justBlinked = false
  game.world.pudges[0].placePudge(RiverCenterX, 48)
  doAssert applyBlinkTo(game.world, id, int32(PlayWestMax - 4), 48),
    "blink from the river onto the west bank must fire"
  let westTile = tileOf(game.world.pudges[0].position)
  doAssert not riverTile(westTile.x)
  doAssert not game.world.pudges[0].inRiver
  doAssert game.world.pudges[0].layer == int32(WestLayer)
  doAssert westBank(westTile.x)

echo "Testing blink toward the rim lands on the last walkable tile"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(30, 40)
  let
    origin = game.world.pudges[0].position
    id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, 30, 0),
    "a rim-aimed blink must fire, not reject"
  let dest = game.world.pudges[0].position
  let tile = tileOf(dest)
  doAssert dest.z < origin.z, "must travel toward the north rim"
  doAssert dest.z != origin.z, "must not stay stuck at the origin"
  doAssert not riverTile(tile.x)
  doAssert walkableTile(
    game.world.pudges[0].layer, int32(tile.x), int32(tile.z)
  )
  doAssert tile.z >= PlayZMin
  game.world.pudges[0].blinkCooldown = 0
  game.world.pudges[0].justBlinked = false
  let originWest = game.world.pudges[0].position
  doAssert applyBlinkTo(game.world, id, 0, int32(tile.z)),
    "a west-rim blink must fire"
  let westTile = tileOf(game.world.pudges[0].position)
  doAssert game.world.pudges[0].position.x < originWest.x
  doAssert walkableTile(
    game.world.pudges[0].layer, int32(westTile.x), int32(westTile.z)
  )
  doAssert westTile.x >= PlayWestMin

echo "Testing blink into a palisade lands on the near side"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[0].itemRank[ShopWall] = 1
  let id = game.world.pudges[0].id
  doAssert applyPlaceWall(game.world, id, 32, 64)
  game.world.pudges[0].placePudge(22, 64)
  let origin = game.world.pudges[0].position
  doAssert applyBlinkTo(game.world, id, 40, 64),
    "a palisade-aimed blink must fire, not reject"
  let dest = game.world.pudges[0].position
  let tile = tileOf(dest)
  doAssert dest.x > origin.x, "must still travel toward the wall"
  doAssert dest.x < game.world.props[0].propCenter.x,
    "must land on the near side of the palisade"
  doAssert tile.x != 32 or tile.z != 64, "must not land in the wall"
  doAssert not game.world.wallBlocksTile(tile.x, tile.z)


echo "Testing blink cooldown rejects a second hop"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(22, 64)
  let id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, 30, 64)
  doAssert not applyBlinkTo(game.world, id, 38, 64),
    "blink must wait out its cooldown"
  game.play(int(BlinkCooldownTicks))
  doAssert game.world.pudges[0].blinkCooldown == 0
  doAssert applyBlinkTo(game.world, id, 38, 64),
    "blink must work again after the cooldown"

echo "Testing blink snaps short of an occupied dest"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(30, 64)
  let
    origin = game.world.pudges[0].position
    blocker = game.world.pudges[1].position
    id = game.world.pudges[0].id
  doAssert applyBlinkTo(game.world, id, 40, 64)
  let dest = game.world.pudges[0].position
  doAssert dest.x > origin.x, "blink toward a body should still move"
  doAssert dest.x < blocker.x, "blink must not pass through the occupant"
  assertApart(
    game.world.pudges[0], game.world.pudges[1],
    "blink must not land inside another butcher"
  )

echo "Testing blink rejects hooked, dying, and windup"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(22, 64)
  let id = game.world.pudges[0].id
  game.world.pudges[0].hookedBy = game.world.pudges[1].id
  doAssert not applyBlinkTo(game.world, id, 30, 64), "hooked"
  game.world.pudges[0].hookedBy = 0
  game.world.pudges[0].windupTicks = 4
  doAssert not applyBlinkTo(game.world, id, 30, 64), "windup"
  game.world.pudges[0].windupTicks = 0
  game.world.pudges[0].state = Dying
  doAssert not applyBlinkTo(game.world, id, 30, 64), "dying"

echo "Testing blink cooldown enters the hash"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(22, 64)
  doAssert applyBlinkTo(game.world, game.world.pudges[0].id, 30, 64)
  let hashed = game.stateHash()
  dec game.world.pudges[0].blinkCooldown
  doAssert game.stateHash() != hashed, "blink cooldown must hash"
  inc game.world.pudges[0].blinkCooldown
  doAssert game.stateHash() == hashed
  game.world.pudges[0].justBlinked = false
  doAssert game.stateHash() != hashed, "justBlinked must hash"
  game.world.pudges[0].justBlinked = true
  doAssert game.stateHash() == hashed

echo "Testing blink clears a walk order"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(22, 64)
  let id = game.world.pudges[0].id
  doAssert applyWalkTo(game.world, id, 30, 64)
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert applyBlinkTo(game.world, id, 28, 70)
  doAssert not game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[0].attackTargetId == 0

echo "Testing blink with no hook leaves range rules unchanged"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(30, 20)
  let
    id = game.world.pudges[0].id
    origin = game.world.pudges[0].position
  doAssert game.world.hooks.len == 0
  doAssert applyBlinkTo(game.world, id, 30, 80),
    "a hop with no chain out must still fire"
  doAssert game.world.hooks.len == 0, "blink must not spawn a hook"
  let dest = game.world.pudges[0].position
  doAssert dest.z > origin.z
  doAssert game.world.pudges[0].blinkCooldown == BlinkCooldownTicks

echo "Testing blink extends an outbound hook by the hop distance"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(30, 20)
  let id = game.world.pudges[0].id
  doAssert applyHookTo(game.world, id, 30, 80)
  game.play(int(HookWindupTicks))
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  game.play(8)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  let
    remain0 = game.world.hooks[0].range - game.world.hooks[0].traveled
    head0 = game.world.hooks[0].position
    heading0 = game.world.hooks[0].heading
    traveled0 = game.world.hooks[0].traveled
    origin = game.world.pudges[0].position
  # Along the throw: south, same heading as the flying head.
  doAssert applyBlinkTo(game.world, id, 30, 80),
    "blink must be allowed once the head has left the hand"
  let destAlong = game.world.pudges[0].position
  let hopAlong = integerSqrt(distSq(origin, destAlong))
  doAssert hopAlong > int64(WorldScale), "the along hop must actually move"
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying, "head must keep flying"
  doAssert game.world.hooks[0].position.x == head0.x
  doAssert game.world.hooks[0].position.z == head0.z,
    "the head stays at its world position"
  doAssert game.world.hooks[0].heading.x == heading0.x
  doAssert game.world.hooks[0].heading.z == heading0.z
  doAssert game.world.hooks[0].traveled == traveled0
  let remainAlong = game.world.hooks[0].range - game.world.hooks[0].traveled
  doAssert remainAlong - remain0 == int32(hopAlong),
    "remaining outbound must grow by the actual hop, not the range cap"
  let hashed = game.stateHash()
  dec game.world.hooks[0].range
  doAssert game.stateHash() != hashed, "hook range must hash"
  inc game.world.hooks[0].range
  doAssert game.stateHash() == hashed
  # Away from the throw: west, after the cooldown. Head still southbound.
  game.world.pudges[0].blinkCooldown = 0
  let
    remain1 = remainAlong
    originAway = game.world.pudges[0].position
    head1 = game.world.hooks[0].position
  doAssert applyBlinkTo(game.world, id, 8, int32(tileOf(originAway).z)),
    "a second hop after cooldown must still stretch the same chain"
  let hopAway = integerSqrt(distSq(originAway, game.world.pudges[0].position))
  doAssert hopAway > int64(WorldScale)
  doAssert game.world.hooks.len == 1
  doAssert game.world.hooks[0].phase == HookFlying
  doAssert game.world.hooks[0].position.x == head1.x
  doAssert game.world.hooks[0].position.z == head1.z
  let remainAway = game.world.hooks[0].range - game.world.hooks[0].traveled
  doAssert remainAway - remain1 == int32(hopAway)

echo "Testing a latched victim cannot blink"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[3].placePudge(52, 64)
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 52, 64)
  var latched = false
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[3].hookedBy != 0:
      latched = true
      break
  doAssert latched, "the east butcher should be on the chain"
  doAssert game.world.pudges[3].hookedBy == game.world.pudges[0].id
  let victimTile = tileOf(game.world.pudges[3].position)
  doAssert not applyBlinkTo(
    game.world, game.world.pudges[3].id,
    int32(victimTile.x + 8), int32(victimTile.z)
  ), "the reeled victim must not blink"
  doAssert game.world.pudges[0].hookedBy == 0
  doAssert applyBlinkTo(game.world, game.world.pudges[0].id, 22, 64),
    "the thrower may still blink while their victim is latched"

echo "Testing Longflight Brand scales hook damage with flight tiles"
block:
  doAssert longshotDamage(100, 0, 10 * WorldScale) == 100
  doAssert longshotDamage(100, 1, 10 * WorldScale) == 110
  doAssert longshotDamage(100, 1, 20 * WorldScale) == 120
  doAssert longshotDamage(100, 2, 10 * WorldScale) == 120
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(28, 64)
  game.world.pudges[3].placePudge(48, 64)
  game.world.pudges[0].itemRank[ShopLongshot] = 1
  let hp0 = game.world.pudges[3].hp
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 48, 64)
  for _ in 0 ..< 80:
    game.play(1)
    if game.world.pudges[3].hp < hp0:
      break
  let lost = hp0 - game.world.pudges[3].hp
  doAssert lost > BaseHookDamage,
    "a long flight must deal more than the unranked hook"

echo "Testing Big Hook deals bonus damage on a landed throw"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(40, 64)
  game.world.pudges[3].placePudge(52, 64)
  game.world.pudges[0].buffKind = RuneBigHook
  game.world.pudges[0].buffTicks = RuneBuffTicks
  doAssert applyHookTo(game.world, game.world.pudges[0].id, 52, 64)
  game.play(160)
  doAssert game.world.pudges[3].hp ==
    BaseHitPoints - bigHookDamage(BaseHookDamage),
    "a Big Hook latch must deal 1.5× unbuffed hook damage"

echo "Testing palisades block walking, take damage, and reject illegal drops"
block:
  let game = freshGame()
  parkPudges(game)
  let id = game.world.pudges[0].id
  game.world.pudges[0].placePudge(30, 64)
  doAssert not applyPlaceWall(game.world, id, 32, 64),
    "cannot place without owning Bank Palisade"
  game.world.pudges[0].itemRank[ShopWall] = 1
  doAssert not applyPlaceWall(game.world, id, int32(RiverWestX), 64),
    "cannot place a wall in the river"
  doAssert not applyPlaceWall(
    game.world, id, int32(PlayEastMin), 64
  ), "cannot place a wall on the enemy bank"
  game.world.pudges[0].placePudge(WestShopX, ShopZ)
  doAssert not applyPlaceWall(
    game.world, id, int32(WestShopX), int32(ShopZ)
  ), "cannot place on the shop pad"
  game.world.pudges[0].placePudge(30, 64)
  doAssert applyPlaceWall(game.world, id, 32, 64)
  doAssert game.world.props.len == 1
  doAssert game.world.props[0].kind == PropWall
  doAssert game.world.props[0].hp == wallMaxHp(1)
  doAssert game.world.wallBlocksTile(32, 64)
  doAssert game.world.pudges[0].wallCooldown > 0
  doAssert not applyPlaceWall(game.world, id, 32, 66),
    "wall cooldown must reject a second drop"
  let hashed = game.stateHash()
  doAssert applyWalkTo(game.world, id, 40, 64)
  for _ in 0 ..< 48:
    game.play(1)
    let t = tileOf(game.world.pudges[0].position)
    doAssert t.x != 32 or t.z != 64, "must not walk onto the palisade"
  doAssert game.world.wallBlocksTile(32, 64)
  doAssert game.stateHash() != hashed, "props and cooldowns must hash"
  let wallId = game.world.props[0].id
  let hpWall = game.world.props[0].hp
  doAssert hurtProp(game.world, wallId, 40, id)
  doAssert game.world.props[0].hp == hpWall - 40
  doAssert hurtProp(game.world, wallId, game.world.props[0].hp, id)
  doAssert not game.world.props[0].alive
  doAssert not game.world.wallBlocksTile(32, 64)

echo "Testing Hooktraps hide from enemies and detonate on a hooked clip"
block:
  let game = freshGame()
  parkPudges(game)
  let west = game.world.pudges[0].id
  let east = game.world.pudges[3].id
  game.world.pudges[0].placePudge(30, 64)
  doAssert not applyPlaceMine(game.world, west, 32, 64),
    "cannot place without owning Hooktrap"
  game.world.pudges[0].itemRank[ShopMine] = 1
  doAssert not applyPlaceMine(game.world, west, int32(RiverWestX), 64),
    "cannot place a mine in the river"
  doAssert applyPlaceMine(game.world, west, 32, 62)
  doAssert game.world.props.len == 1
  doAssert game.world.props[0].kind == PropMine
  let mineId = game.world.props[0].id
  doAssert mineVisibleTo(game.world, mineId, WestTeam)
  doAssert not mineVisibleTo(game.world, mineId, EastTeam),
    "enemies must not see a Hooktrap"
  let westObjs = worldObjectCount(game.world, west)
  let eastObjs = worldObjectCount(game.world, east)
  doAssert westObjs > eastObjs, "enemy object queries must omit the mine"
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: east,
    team: EastTeam,
    phase: HookFlying,
    position: worldAtTile(34, 62),
    origin: worldAtTile(34, 62),
    prior: worldAtTile(34, 62),
    heading: heading(-1, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  var blew = false
  for _ in 0 ..< 24:
    game.play(1)
    blew = true
    for prop in game.world.props:
      if prop.id == mineId and prop.alive:
        blew = false
    if blew:
      break
  doAssert blew, "an enemy Meat Hook that clips a Hooktrap must detonate it"

echo "Testing Rot toggle damages, slows, and blocks blink"
block:
  let game = freshGame()
  parkPudges(game)
  let
    id0 = game.world.pudges[0].id
    id1 = game.world.pudges[1].id
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[1].placePudge(36, 64)
  game.world.pudges[3].placePudge(105, 64)
  let
    hp0 = game.world.pudges[0].hp
    hp1 = game.world.pudges[1].hp
    hpFar = game.world.pudges[3].hp
    speed0 = topMoveSpeed(game.world.pudges[0])
  doAssert not game.world.rotAffected(game.world.pudges[0])
  doAssert applyRotToggle(game.world, id0)
  doAssert game.world.pudges[0].rotOn
  doAssert game.world.rotAffected(game.world.pudges[0]),
    "the caster is inside their own disk"
  doAssert game.world.rotAffected(game.world.pudges[1]),
    "a neighbor inside RotRadius must be affected"
  doAssert not game.world.rotAffected(game.world.pudges[3])
  let slowed = speed0 - speed0 * RotSlowPercent div 100
  doAssert moveSpeed(game.world, game.world.pudges[0]) == slowed,
    "the caster must take the 40% Rot slow"
  doAssert moveSpeed(game.world, game.world.pudges[1]) == slowed,
    "a neighbor in the disk must take the same 40% slow"
  doAssert moveSpeed(game.world, game.world.pudges[3]) ==
    topMoveSpeed(game.world.pudges[3])
  doAssert not applyBlinkTo(game.world, id0, 30, 80),
    "rot must block the caster's blink"
  doAssert not applyBlinkTo(game.world, id1, 36, 80),
    "rot must block a neighbor's blink"
  game.play(1)
  doAssert game.world.pudges[0].hp == hp0 - RotDamage, "self-damage"
  doAssert game.world.pudges[1].hp == hp1 - RotDamage, "neighbor damage"
  doAssert game.world.pudges[3].hp == hpFar, "out of range must be untouched"
  doAssert applyRotToggle(game.world, id0)
  doAssert not game.world.pudges[0].rotOn
  doAssert not game.world.rotAffected(game.world.pudges[0])
  doAssert applyBlinkTo(game.world, id0, 30, 80),
    "blink must work again after Rot is off"
  game.world.pudges[0].rotOn = false
  game.world.pudges[0].rotTicks = 0
  game.world.pudges[0].hp = RotDamage
  let
    gold0 = game.world.pudges[0].gold
    goldEast = game.world.pudges[3].gold
    killsEast = game.world.pudges[3].kills
    ptsEast = game.world.pudges[3].points
  doAssert applyRotToggle(game.world, id0)
  game.play(1)
  doAssert game.world.pudges[0].state == Dying, "rot can self-kill"
  doAssert not game.world.pudges[0].rotOn, "death must clear Rot"
  doAssert game.world.pudges[0].lastHurtBy == id0
  doAssert game.world.teamKills[WestTeam.ord] == 0
  doAssert game.world.teamKills[EastTeam.ord] == 1,
    "own-Rot suicide still scores for the other team"
  doAssert game.world.pudges[0].gold == gold0
  doAssert game.world.pudges[3].gold == goldEast,
    "own-Rot suicide pays no kill gold"
  doAssert game.world.pudges[3].kills == killsEast
  doAssert game.world.pudges[3].points == ptsEast

echo "Testing overlapping Rot clouds stack damage, not slow"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[1].placePudge(36, 64)
  game.world.pudges[3].placePudge(105, 64)
  let
    hp0 = game.world.pudges[0].hp
    hp1 = game.world.pudges[1].hp
    hpFar = game.world.pudges[3].hp
    speed0 = topMoveSpeed(game.world.pudges[0])
    slowed = speed0 - speed0 * RotSlowPercent div 100
  doAssert applyRotToggle(game.world, game.world.pudges[0].id)
  doAssert applyRotToggle(game.world, game.world.pudges[1].id)
  doAssert moveSpeed(game.world, game.world.pudges[0]) == slowed
  doAssert moveSpeed(game.world, game.world.pudges[1]) == slowed
  game.play(1)
  doAssert game.world.pudges[0].hp == hp0 - RotDamage * 2,
    "two overlapping clouds must each pulse"
  doAssert game.world.pudges[1].hp == hp1 - RotDamage * 2,
    "the other butcher in both disks takes both pulses"
  doAssert game.world.pudges[3].hp == hpFar

echo "Testing Rot hashes"
block:
  let game = freshGame()
  parkPudges(game)
  let hashed = game.stateHash()
  doAssert applyRotToggle(game.world, game.world.pudges[0].id)
  doAssert game.stateHash() != hashed, "rotOn must hash"
  doAssert applyRotToggle(game.world, game.world.pudges[0].id)
  doAssert game.stateHash() == hashed

echo "Testing Dota kill-streak titles and gold"
block:
  doAssert streakTitle(0) == ""
  doAssert streakTitle(2) == ""
  doAssert streakTitle(3) == "KILLING SPREE"
  doAssert streakTitle(4) == "DOMINATING"
  doAssert streakTitle(5) == "MEGA KILL"
  doAssert streakTitle(6) == "UNSTOPPABLE"
  doAssert streakTitle(7) == "WICKED SICK"
  doAssert streakTitle(8) == "MONSTER KILL"
  doAssert streakTitle(9) == "GODLIKE"
  doAssert streakTitle(10) == "BEYOND GODLIKE"
  doAssert streakTitle(14) == "BEYOND GODLIKE"
  doAssert multiKillTitle(1) == ""
  doAssert multiKillTitle(2) == "DOUBLE KILL"
  doAssert multiKillTitle(3) == "TRIPLE KILL"
  doAssert multiKillTitle(4) == "ULTRA KILL"
  doAssert multiKillTitle(5) == "RAMPAGE"
  doAssert multiKillTitle(8) == "RAMPAGE"
  doAssert streakBonusGold(2) == 0
  doAssert streakBonusGold(3) == 1
  doAssert streakBonusGold(9) == 8
  doAssert streakBonusGold(10) == 9
  doAssert killBountyGold(1, 0, true) == GoldPerKill + GoldFirstBlood
  doAssert killBountyGold(3, 0, false) == GoldPerKill + 1
  doAssert killBountyGold(1, 9, false) == GoldPerKill + 8

echo "Testing own-streak gold, shutdown gold, and first blood"
block:
  let game = freshGame()
  parkPudges(game)
  let
    killer = game.world.pudges[0].id
    victim = 3
  killPudgeForTest(game.world, victim, killer)
  doAssert game.world.pudges[0].justFirstBlood
  doAssert game.world.pudges[0].streak == 1
  doAssert game.world.pudges[0].gold == GoldPerKill + GoldFirstBlood
  doAssert game.world.pudges[0].justStreak == 0
  doAssert game.world.pudges[3].streak == 0
  for n in 2 .. 9:
    game.world.pudges[victim].state = Alive
    game.world.pudges[victim].hp = BaseHitPoints
    killPudgeForTest(game.world, victim, killer)
  doAssert game.world.pudges[0].streak == 9
  doAssert game.world.pudges[0].justStreak == 9
  doAssert streakTitle(game.world.pudges[0].justStreak) == "GODLIKE"
  var expected = GoldPerKill + GoldFirstBlood
  for n in 2'i32 .. 9'i32:
    expected += killBountyGold(n, 0, false)
  doAssert game.world.pudges[0].gold == expected,
    "killer gold should be base + first blood + own-streak steps, got " &
      $game.world.pudges[0].gold & " expected " & $expected
  doAssert game.world.pudges[0].justMulti >= 2
  doAssert multiKillTitle(game.world.pudges[0].justMulti) == "RAMPAGE"

echo "Testing shutdown gold resets the victim's streak"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.teamKills[WestTeam.ord] = 1
  game.world.pudges[3].streak = 9
  game.world.pudges[0].gold = 0
  killPudgeForTest(game.world, 3, game.world.pudges[0].id)
  doAssert game.world.pudges[3].streak == 0, "death must reset the spree"
  doAssert game.world.pudges[0].justShutdown == 9
  doAssert game.world.pudges[0].justFirstBlood == false
  doAssert game.world.pudges[0].gold ==
    killBountyGold(1, 9, false)
  doAssert game.world.pudges[0].gold == GoldPerKill + streakBonusGold(9)

echo "Testing ally denies pay no streak gold and reset the victim"
block:
  let game = freshGame()
  parkPudges(game)
  game.world.pudges[1].streak = 6
  let gold0 = game.world.pudges[0].gold
  let streak0 = game.world.pudges[0].streak
  killPudgeForTest(game.world, 1, game.world.pudges[0].id)
  doAssert game.world.pudges[0].gold == gold0, "denies must not pay bounty"
  doAssert game.world.pudges[0].streak == streak0
  doAssert game.world.pudges[0].justStreak == 0
  doAssert game.world.pudges[0].justShutdown == 0
  doAssert game.world.pudges[1].streak == 0
  doAssert game.world.pudges[0].kills == 0

echo "Testing fair matches keep the pre-streak state hash"
block:
  let
    first = freshGame()
    second = freshGame()
  first.play(8)
  second.play(8)
  doAssert first.stateHash() == second.stateHash(),
    "twin openings with no sprees must hash the same"
  let hashed = first.stateHash()
  first.world.pudges[0].streak = 3
  doAssert first.stateHash() != hashed, "a live streak must reach the hash"
  first.world.pudges[0].streak = 0
  doAssert first.stateHash() == hashed,
    "zero streaks must drop back out of the hash"
  killPudgeForTest(first.world, 3, first.world.pudges[0].id)
  killPudgeForTest(second.world, 3, second.world.pudges[0].id)
  doAssert first.stateHash() == second.stateHash(),
    "twin first kills must hash the same"
  doAssert first.stateHash() != hashed, "a kill must change the world hash"

echo "test_pw_sim: all checks passed"
echo "  opening hash = ", freshGame().stateHash().toHex(16)
