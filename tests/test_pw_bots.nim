## Bot policy scripts compile and run one decision tick without errors.

import
  std/os,
  polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const BasePolicy {.strdefine.} = ""

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
  basePolicyPath = if BasePolicy.len > 0: BasePolicy else: playersDir / "base.bas"
  map = generateMap(2026)

echo "Testing bot policies compile and run"
for name in Policies:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(
    path: (if name == "base.bas": basePolicyPath else: playersDir / name),
    count: PudgeCount)])
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
  doAssert game.seatLabels == @[
    "Aggressive 1", "Aggressive 2", "Support 1", "Support 2",
    "Denier 1", "Denier 2"
  ]
  tickWorld(game, proc() = runBotDecisions(game))
  for i in 0 ..< PudgeCount:
    doAssert not game.heroVms[i].failed

echo "Testing coworld player names become seat labels"
block:
  var game = newGame(map, 100, false, ReplayData())
  applySeatLabels(game, [
    "daf-pudge-wars:v1",
    "daf-pudge-wars:v1",
    "daf-pudge-wars:v1",
    "pudge-wars-camper:v6",
    "pudge-wars-camper:v6",
    "pudge-wars-camper:v6"
  ])
  doAssert game.seatLabels == @[
    "daf-pudge-wars:v1 1",
    "daf-pudge-wars:v1 2",
    "daf-pudge-wars:v1 3",
    "pudge-wars-camper:v6 1",
    "pudge-wars-camper:v6 2",
    "pudge-wars-camper:v6 3"
  ]
  applySeatLabels(game, ["docxology", "Aaron's Optimizer Jr"])
  doAssert game.seatLabels[0] == "docxology"
  doAssert game.seatLabels[1] == "Aaron's Optimizer Jr"
  doAssert game.seatLabels[2] == ""
  let recorded = currentSetup(game, 10)
  doAssert recorded.seatLabels[0] == "docxology"
  doAssert recorded.seatLabels[1] == "Aaron's Optimizer Jr"
  doAssert recorded.seatLabels[2] == ""

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
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
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
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
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
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[1].placePudge(98, 40)
  game.world.pudges[3].placePudge(105, 40)
  game.world.pudges[3].hookedBy = game.world.pudges[0].id
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert not game.world.pudges[0].inRiver,
    "chasing a hooked enemy on the far bank must not land in the river"

echo "Testing the default bot Rots a close unshielded enemy"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
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
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
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

echo "Testing the default bot hooks a fogged last-seen lane"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[3].placePudge(RiverCenterX, 40)
  game.world.pudges[3].shieldTicks = 0
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  game.world.hooks.setLen(0)
  game.world.tick = 24
  game.world.pudges[0].hookCooldown = 0
  game.world.pudges[0].windupTicks = 0
  game.world.pudges[0].justBlinked = false
  game.world.pudges[3].placePudge(105, 40)
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].windupTicks > 0,
    "base bot must throw at the far-bank ghost after losing vision"
  let
    aimX = game.world.pudges[0].windupAimX div FineAimScale
    aimY = game.world.pudges[0].windupAimY div FineAimScale
  doAssert aimX >= PlayEastMin,
    "a west bot's fog hook must land on the east bank"
  doAssert abs(aimY - 40) <= 12,
    "the fog hook should follow the last-seen river lane"

echo "Testing the default bot spends every kill point in one tick"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].points = 3
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].points == 0,
    "base bot must dump every unspent kill point the same think"
  doAssert game.world.pudges[0].upgrades[UpgradeRadius] == 3,
    "base bot fills Hook Radius before the other skills"
  doAssert game.world.pudges[0].upgrades[UpgradeDistance] == 0
  doAssert game.world.pudges[0].upgrades[UpgradeSpeed] == 0
  doAssert game.world.pudges[0].upgrades[UpgradeDamage] == 0

echo "Testing the default bot rolls into speed once radius and distance are maxed"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].upgrades[UpgradeDistance] = MaxUpgradeLevel
  game.world.pudges[0].upgrades[UpgradeRadius] = MaxUpgradeLevel
  game.world.pudges[0].points = 2
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].points == 0
  doAssert game.world.pudges[0].upgrades[UpgradeDistance] == MaxUpgradeLevel
  doAssert game.world.pudges[0].upgrades[UpgradeSpeed] == 2

echo "Testing hook distance upgrades extend the default bot's throw"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].placePudge(22, 40)
  game.world.pudges[1].placePudge(90, 40)
  game.world.pudges[3].placePudge(PlayEastMin, 40)
  game.world.pudges[0].shieldTicks = 0
  game.world.pudges[1].shieldTicks = 0
  game.world.pudges[3].shieldTicks = 0
  game.world.pudges[0].hookCooldown = 0
  game.world.pudges[0].upgrades[UpgradeDistance] = 6
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].windupTicks > 0,
    "a distance-stacked bot must throw across the river at long range"
  let
    longAimX = game.world.pudges[0].windupAimX div FineAimScale
  doAssert longAimX >= PlayEastMin - 2,
    "the long throw must aim at the far-bank butcher"

echo "Testing the default bot leads a headshot toward the reeler"
block:
  var game = newGame(map, 100, false, ReplayData())
  loadBots(game, [BotGroup(path: basePolicyPath, count: PudgeCount)])
  parkBots(game)
  game.world.pudges[0].placePudge(30, 50)
  game.world.pudges[1].placePudge(22, 50)
  game.world.pudges[3].placePudge(RiverCenterX, 50)
  for i in 0 ..< PudgeCount:
    game.world.pudges[i].shieldTicks = 0
    game.world.pudges[i].hookCooldown = 0
    game.world.pudges[i].windupTicks = 0
    game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
  game.world.pudges[3].hookedBy = game.world.pudges[1].id
  tickWorld(game, proc() = runBotDecisions(game))
  doAssert not game.heroVms[0].failed, game.heroVms[0].lastError
  doAssert game.world.pudges[0].windupTicks > 0,
    "base bot must throw at an ally's catch"
  let
    hsAimX = game.world.pudges[0].windupAimX div FineAimScale
  doAssert hsAimX > 22, "headshot aim must not target the reeler"
  doAssert hsAimX < RiverCenterX, "headshot aim must lead toward our bank"

if fileExists(playersDir / "partner.bas"):
  echo "Testing the partner bot headshots a visible catch"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[0].placePudge(22, 50)
    game.world.pudges[1].placePudge(30, 50)
    game.world.pudges[3].placePudge(RiverCenterX, 50)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 0
      game.world.pudges[i].hookCooldown = 0
      game.world.pudges[i].windupTicks = 0
    game.world.pudges[3].hookedBy = game.world.pudges[0].id
    # Isolate headshot aiming from the partner's optional blink. At these
    # exact fixture coordinates its landing and lead aim can coincide;
    # the old Base's incidental blink happened to move the reeler first.
    game.world.pudges[1].blinkCooldown = BlinkCooldownTicks
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must throw at an ally's catch"
    let
      pAimX = game.world.pudges[1].windupAimX div FineAimScale
      pAimY = game.world.pudges[1].windupAimY div FineAimScale
    doAssert pAimX > 24, "partner must not hook the reeler"
    doAssert pAimX < RiverCenterX - 4, "partner must lead toward the reeler"
    doAssert abs(pAimY - 50) <= 12, "partner headshot should stay on the catch lane"

  echo "Testing the partner bot combos a flying ally hook"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[0].placePudge(22, 50)
    game.world.pudges[1].placePudge(30, 50)
    game.world.pudges[3].placePudge(105, 88)
    game.world.pudges[4].placePudge(105, 40)
    game.world.pudges[5].placePudge(105, 96)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 200
      game.world.pudges[i].hookCooldown = 0
      game.world.pudges[i].windupTicks = 0
    game.world.hooks.add Hook(
      id: game.world.nextHookId,
      ownerId: game.world.pudges[0].id,
      team: WestTeam,
      phase: HookFlying,
      position: worldAtTile(RiverCenterX, 50),
      origin: worldAtTile(22, 50),
      prior: worldAtTile(RiverCenterX, 50),
      heading: heading(WorldScale, 0),
      range: BaseHookRange,
      speed: BaseHookSpeed,
      peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius,
      damage: BaseHookDamage
    )
    inc game.world.nextHookId
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must combo-throw along a flying ally hook"
    let
      cAimX = game.world.pudges[1].windupAimX div FineAimScale
    doAssert cAimX > 28, "combo aim must not target the ally"
    doAssert cAimX < RiverCenterX - 4,
      "combo must intercept the reel, not the far lip or hook head"

  echo "Testing the partner bot hooks a point-blank fight"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[1].placePudge(30, 64)
    game.world.pudges[3].placePudge(33, 64)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 0
      game.world.pudges[i].hookCooldown = 0
      game.world.pudges[i].windupTicks = 0
      game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must hook when the hook is ready in melee"
    doAssert game.world.pudges[1].attackTargetId == 0,
      "a ready hook must beat the 28-dmg melee swing"
    let
      mAimX = game.world.pudges[1].windupAimX div FineAimScale
    doAssert abs(mAimX - 33) <= 8,
      "the brawl hook must aim at the close enemy, not a fog poke"

  echo "Testing the partner bot melees when the hook is down"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[1].placePudge(30, 64)
    game.world.pudges[3].placePudge(33, 64)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 0
      game.world.pudges[i].windupTicks = 0
      game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    game.world.pudges[1].hookCooldown = 20
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks == 0,
      "partner must not start a windup while the hook is cooling"
    doAssert game.world.pudges[1].attackTargetId == game.world.pudges[3].id,
      "partner must melee the close enemy while the hook is down"

  echo "Testing the partner bot dumps on an ally's close fight"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[0].placePudge(40, 64)
    game.world.pudges[1].placePudge(36, 88)
    game.world.pudges[3].placePudge(48, 64)
    game.world.pudges[4].placePudge(105, 88)
    game.world.pudges[5].placePudge(105, 96)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 200
      game.world.pudges[i].hookCooldown = BlinkCooldownTicks
      game.world.pudges[i].windupTicks = 0
      game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    game.world.pudges[3].shieldTicks = 0
    game.world.pudges[1].hookCooldown = 0
    game.world.tick = 16
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must hook the enemy next to the living ally"
    let
      fAimX = game.world.pudges[1].windupAimX div FineAimScale
      fAimY = game.world.pudges[1].windupAimY div FineAimScale
    doAssert abs(fAimX - 48) <= 10,
      "fight-dump must aim at the ally's enemy, not a fog poke"
    doAssert abs(fAimY - 64) <= 10,
      "fight-dump must snap to the fight Y"

  echo "Testing the partner bot hooks a drowning ally when no combo is live"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[0].placePudge(RiverCenterX, 50)
    game.world.pudges[1].placePudge(36, 50)
    game.world.pudges[3].placePudge(105, 88)
    game.world.pudges[4].placePudge(105, 40)
    game.world.pudges[5].placePudge(105, 96)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 200
      game.world.pudges[i].hookCooldown = BlinkCooldownTicks
      game.world.pudges[i].windupTicks = 0
      game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    doAssert game.world.pudges[0].inRiver
    game.world.pudges[1].hookCooldown = 0
    game.world.tick = 16
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must throw to save a drowning ally"
    let
      sAimX = game.world.pudges[1].windupAimX div FineAimScale
    doAssert abs(sAimX - RiverCenterX) <= 10,
      "water-save must hook the ally, not a fog poke"

  echo "Testing the partner bot leads a fogged last-seen combo lane"
  block:
    var game = newGame(map, 100, false, ReplayData())
    loadBots(game, [
      BotGroup(path: basePolicyPath, count: 1),
      BotGroup(path: playersDir / "partner.bas", count: 1),
      BotGroup(path: basePolicyPath, count: 4)
    ])
    parkBots(game)
    game.world.pudges[0].placePudge(22, 48)
    game.world.pudges[1].placePudge(36, 48)
    game.world.pudges[3].placePudge(RiverCenterX, 48)
    game.world.pudges[4].placePudge(105, 88)
    game.world.pudges[5].placePudge(105, 96)
    for i in 0 ..< PudgeCount:
      game.world.pudges[i].shieldTicks = 200
      game.world.pudges[i].hookCooldown = BlinkCooldownTicks
      game.world.pudges[i].windupTicks = 0
      game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    game.world.pudges[3].shieldTicks = 0
    game.world.pudges[1].hookCooldown = 0
    game.world.tick = 8
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    game.world.hooks.setLen(0)
    game.world.pudges[3].placePudge(105, 48)
    game.world.pudges[3].shieldTicks = 200
    game.world.pudges[1].hookCooldown = 0
    game.world.pudges[1].windupTicks = 0
    game.world.pudges[1].justBlinked = false
    game.world.hooks.add Hook(
      id: game.world.nextHookId,
      ownerId: game.world.pudges[0].id,
      team: WestTeam,
      phase: HookFlying,
      position: worldAtTile(RiverCenterX, 50),
      origin: worldAtTile(22, 48),
      prior: worldAtTile(RiverCenterX, 50),
      heading: heading(WorldScale, 0),
      range: BaseHookRange,
      speed: BaseHookSpeed,
      peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius,
      damage: BaseHookDamage
    )
    inc game.world.nextHookId
    game.world.tick = 20
    tickWorld(game, proc() = runBotDecisions(game))
    doAssert not game.heroVms[1].failed, game.heroVms[1].lastError
    doAssert game.world.pudges[1].windupTicks > 0,
      "partner must combo-throw along a flying ally hook"
    let
      gAimX = game.world.pudges[1].windupAimX div FineAimScale
      gAimY = game.world.pudges[1].windupAimY div FineAimScale
    doAssert gAimX > 28, "combo must not target the ally hook head"
    doAssert gAimX < RiverCenterX - 4,
      "combo must intercept the reel, not the far lip or hook head"
    doAssert abs(gAimY - 49) <= 14,
      "combo Y should stay on the last-seen / fly lane, not the ally pad"

echo "test_pw_bots: all checks passed"
