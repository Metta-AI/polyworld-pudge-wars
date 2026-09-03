## Bot policy scripts compile and run one decision tick without errors.

import
  std/os,
  polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const Policies = [
  "base.bas",
  "challenger.bas",
  "aggressive.bas",
  "support.bas",
  "sniper.bas",
  "denier.bas",
  "patient.bas"
]

let
  playersDir =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players"
  map = generateMap(2026)

echo "Testing bot policies compile and run"
for name in Policies:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / name, count: PudgeCount)])
  for i in 0 ..< PudgeCount:
    doAssert game.heroVms[i] != nil, name & " missing vm " & $i
  tickWorld(game, proc() = runBotDecisions(game))
  for i in 0 ..< PudgeCount:
    doAssert not game.heroVms[i].failed,
      name & " seat " & $i & ": " & game.heroVms[i].lastError
    doAssert not game.world.pudges[i].justBlinked,
      name & " must not random-blink on the opening tick"
    doAssert not game.world.pudges[i].rotOn,
      name & " must not Rot on the opening tick"

echo "Testing mixed bot policies fill six seats"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [
    BotGroup(path: playersDir / "aggressive.bas", count: 2),
    BotGroup(path: playersDir / "support.bas", count: 2),
    BotGroup(path: playersDir / "denier.bas", count: 2)
  ])
  doAssert game.heroVms.len == PudgeCount
  tickWorld(game, proc() = runBotDecisions(game))
  for i in 0 ..< PudgeCount:
    doAssert not game.heroVms[i].failed

proc parkBots(game: Game) =
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[1].placePudge(18, 32)
  game.world.pudges[2].placePudge(18, 96)
  game.world.pudges[3].placePudge(105, 64)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)

echo "Testing the default bot blinks off an inbound hook"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / "base.bas", count: PudgeCount)])
  parkBots(game)
  let origin = game.world.pudges[0].position
  # 18 tiles out: inside dodgeDist 22, outside the 14-tile intercept.
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    phase: HookFlying,
    position: worldAtTile(48, 64),
    origin: worldAtTile(48, 64),
    prior: worldAtTile(48, 64),
    heading: heading(-WorldScale, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].justBlinked,
    "base bot must blink off the inbound hook"
  doAssert game.world.pudges[0].blinkCooldown == BlinkCooldownTicks - 1,
    "blink cooldown starts this tick, then ticks down once"
  doAssert game.world.pudges[0].position.x != origin.x or
      game.world.pudges[0].position.z != origin.z,
    "the dodge hop must actually move"
  doAssert game.world.pudges[0].windupTicks > 0,
    "base bot must hook in the same tick as the dodge blink"

echo "Testing the default bot blinks out of the river"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / "base.bas", count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].placePudge(RiverCenterX, 40)
  doAssert game.world.pudges[0].inRiver
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].justBlinked,
    "base bot must blink out of the drink"
  doAssert not game.world.pudges[0].inRiver,
    "the hop must land on a bank"

echo "Testing the challenger blinks off an inbound hook"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(
    path: playersDir / "challenger.bas", count: PudgeCount
  )])
  parkBots(game)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    phase: HookFlying,
    position: worldAtTile(48, 64),
    origin: worldAtTile(48, 64),
    prior: worldAtTile(48, 64),
    heading: heading(-WorldScale, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].justBlinked,
    "challenger must blink off the inbound hook"
  doAssert game.world.pudges[0].windupTicks > 0,
    "challenger must hook in the same tick as the dodge blink"

echo "Testing a land chase does not dump the bot in the river"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / "base.bas", count: PudgeCount)])
  parkBots(game)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[3].hookedBy = game.world.pudges[0].id
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert not game.world.pudges[0].inRiver,
    "chasing a hooked enemy on the far bank must not land in the river"

echo "Testing the default bot Rots a close unshielded enemy"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / "base.bas", count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].placePudge(30, 64)
  game.world.pudges[3].placePudge(36, 64)
  game.world.pudges[0].shieldTicks = 0
  game.world.pudges[3].shieldTicks = 0
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].rotOn,
    "base bot must Rot when an enemy stands inside the 8-tile disk"

echo "Testing the default bot walks inland out of enemy Rot"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: playersDir / "base.bas", count: PudgeCount)])
  parkBots(game)
  let home = game.world.pudges[0].spawnTile
  game.world.pudges[0].placePudge(home.x + 8, home.z)
  game.world.pudges[3].placePudge(home.x + 14, home.z)
  game.world.pudges[0].shieldTicks = 0
  game.world.pudges[3].shieldTicks = 0
  game.world.pudges[0].hp = 80
  doAssert applyRotToggle(game.world, game.world.pudges[3].id)
  doAssert game.world.pudges[3].rotOn
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert not game.world.pudges[0].rotOn,
    "a low-HP bot must not turn Rot on inside someone else's cloud"
  doAssert game.world.pudges[0].hasMoveTarget,
    "a low-HP bot must walk out of enemy Rot"
  doAssert game.world.pudges[0].moveX < home.x + 8,
    "the flee walk must head inland toward the west pad"

echo "test_pw_bots: all checks passed"
