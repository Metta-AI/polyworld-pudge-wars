## Tactical regressions from the Myasnik full-match evaluation.
## Candidate-only run: nim r -d:CombatPolicy=/absolute/candidate.bas ...
import
  std/[os, unittest],
  polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const CombatPolicy {.strdefine.} = ""
let policy = if CombatPolicy.len > 0: CombatPolicy else:
  currentSourcePath().parentDir.parentDir / "examples/pudge_wars/players/base.bas"

proc fixture(): Game =
  result = newGame(generateMap(2026), 400, false, ReplayData())
  loadBots(result, [BotGroup(path: policy, count: PudgeCount)])
  result.humanSlots = @[1, 2, 3, 4, 5]
  result.world.tick = 200
  for i, at in [(30, 40), (18, 16), (18, 112),
      (106, 16), (106, 64), (106, 112)]:
    result.world.pudges[i].placePudge(at[0], at[1])
    result.world.pudges[i].shieldTicks = 0
    result.world.pudges[i].blinkCooldown = BlinkCooldownTicks

proc step(game: Game) =
  tickWorld(game, proc() = runBotDecisions(game))
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

proc alliedCatch(game: Game) =
  game.world.pudges[0].placePudge(35, 50)
  game.world.pudges[1].placePudge(25, 80)
  game.world.pudges[3].placePudge(RiverCenterX, 50)
  game.world.pudges[3].hookedBy = game.world.pudges[1].id
  game.world.hooks.add Hook(
    id: game.world.nextHookId, ownerId: game.world.pudges[1].id,
    team: WestTeam, phase: HookReeling,
    victimId: game.world.pudges[3].id,
    position: game.world.pudges[3].position,
    prior: game.world.pudges[3].position,
    origin: game.world.pudges[1].position,
    heading: heading(WorldScale, 0), range: BaseHookRange,
    speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius, damage: BaseHookDamage)
  inc game.world.nextHookId

suite "Base combat policy":
  test "save blink instead of chasing our own flying hook":
    let game = fixture()
    game.world.pudges[0].blinkCooldown = 0
    game.world.pudges[0].hookCooldown = HookCooldownTicks
    game.world.hooks.add Hook(
      id: game.world.nextHookId, ownerId: game.world.pudges[0].id,
      team: WestTeam, phase: HookFlying,
      position: worldAtTile(48, 40), prior: worldAtTile(48, 40),
      origin: game.world.pudges[0].position,
      heading: heading(WorldScale, 0), range: BaseHookRange,
      speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    game.step()
    check not game.world.pudges[0].justBlinked
    check game.world.pudges[0].blinkCooldown == 0

  test "do not blink into the river to chase another teammate's catch":
    let game = fixture()
    game.alliedCatch()
    game.world.pudges[0].blinkCooldown = 0
    game.step()
    check not game.world.pudges[0].justBlinked
    check not game.world.pudges[0].inRiver

  test "approach an allied catch from a safe finishing bank":
    let game = fixture()
    game.alliedCatch()
    game.step()
    check game.world.pudges[0].hasMoveTarget
    check game.world.pudges[0].moveX <= PlayWestMax

  test "cast an available short hook before settling into melee":
    let game = fixture()
    game.world.pudges[3].placePudge(35, 40)
    game.world.pudges[3].hp = 640
    game.step()
    check game.world.pudges[0].windupTicks > 0
    check game.world.pudges[0].attackTargetId == game.world.pudges[3].id

  test "fight back when caught on the enemy bank inside Rot":
    let game = fixture()
    game.world.pudges[0].placePudge(96, 40)
    game.world.pudges[0].hp = 500
    game.world.pudges[3].placePudge(102, 40)
    game.world.pudges[3].rotOn = true
    game.step()
    check game.world.pudges[0].rotOn
    check game.world.pudges[0].windupTicks > 0

  test "spend every kill point on range before speed":
    let game = fixture()
    game.world.pudges[0].points = 3
    game.step()
    check game.world.pudges[0].points == 0
    check game.world.pudges[0].upgrades[UpgradeDistance] == 3
    check game.world.pudges[0].upgrades[UpgradeRadius] == 0

  test "switch to speed once range is maxed":
    let game = fixture()
    game.world.pudges[0].upgrades[UpgradeDistance] = MaxUpgradeLevel
    game.world.pudges[0].points = 2
    game.step()
    check game.world.pudges[0].points == 0
    check game.world.pudges[0].upgrades[UpgradeSpeed] == 2

  test "finish recovering instead of leaving the pad at forty percent":
    let game = fixture()
    let home = game.world.pudges[0].spawnTile
    game.world.pudges[0].hp = 400
    game.step()
    game.world.pudges[0].hp = 700
    game.step()
    check game.world.pudges[0].moveX == home.x
    check game.world.pudges[0].moveZ == home.z
    game.world.pudges[0].hp = 950
    game.step()
    check game.world.pudges[0].moveX != home.x or
      game.world.pudges[0].moveZ != home.z

  test "blink home across the fountain pinch in either direction":
    for team in [WestTeam, EastTeam]:
      let game = fixture()
      game.world.pudges[0].team = team
      game.world.pudges[0].placePudge(if team == WestTeam: 73 else: 55, 60)
      game.world.pudges[0].hp = 300
      game.world.pudges[0].blinkCooldown = 0
      game.world.pudges[0].hookCooldown = HookCooldownTicks
      game.step()
      check game.world.pudges[0].justBlinked
      check game.world.pudges[0].layer == team.ord
      for tick in 0 ..< 32:
        game.step()
      check not game.world.pudges[0].inRiver
      check game.world.pudges[0].hp >= 300

  test "do not attempt a fountain escape across the wide river":
    let game = fixture()
    game.world.pudges[0].placePudge(78, 40)
    game.world.pudges[0].hp = 300
    game.world.pudges[0].blinkCooldown = 0
    game.step()
    check not game.world.pudges[0].justBlinked

  test "do not blink into an occupied fountain landing":
    let game = fixture()
    game.world.pudges[0].placePudge(73, 60)
    game.world.pudges[0].hp = 300
    game.world.pudges[0].blinkCooldown = 0
    game.world.pudges[1].placePudge(56, 60)
    game.step()
    check not game.world.pudges[0].justBlinked

  test "an inland dodge on the enemy bank stays on that bank":
    let game = fixture()
    game.world.pudges[0].placePudge(85, 40)
    game.world.pudges[0].blinkCooldown = 0
    game.world.hooks.add Hook(
      id: game.world.nextHookId, ownerId: game.world.pudges[3].id,
      team: EastTeam, phase: HookFlying,
      position: worldAtTile(77, 40), prior: worldAtTile(76, 40),
      origin: worldAtTile(76, 40), heading: heading(WorldScale, 0),
      range: BaseHookRange, speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    game.step()
    check game.world.pudges[0].justBlinked
    check game.world.pudges[0].layer == EastTeam.ord

  test "fishing lane survives a teammate death":
    let game = fixture()
    game.humanSlots = @[0, 1, 3, 4, 5]
    game.world.pudges[2].placePudge(36, 96)
    game.step()
    let lane = game.world.pudges[2].moveZ
    game.world.pudges[0].state = Dying
    game.step()
    check abs(game.world.pudges[2].moveZ - lane) <= 4

  test "one rune collector leaves the other fishing lanes spaced":
    let game = fixture()
    game.humanSlots = @[3, 4, 5]
    game.world.tick = 500
    game.world.runeClock = 140
    for i, y in [40, 64, 100]:
      game.world.pudges[i].placePudge(36, y)
    game.step()
    check game.world.pudges[0].moveZ == game.world.nextRuneZTile
    check game.world.pudges[1].moveZ >= game.world.nextRuneZTile + 24
    check game.world.pudges[2].moveZ >= game.world.pudges[1].moveZ + 24
