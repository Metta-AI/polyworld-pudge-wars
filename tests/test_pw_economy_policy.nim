## Economy and vision contracts for the default Base policy.
import std/[os, unittest], polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const EconomyPolicy {.strdefine.} = ""
let policy = if EconomyPolicy.len > 0: EconomyPolicy else:
  currentSourcePath().parentDir.parentDir / "examples/pudge_wars/players/base.bas"

proc fixture(side = WestTeam): Game =
  result = newGame(generateMap(2026), TickRate * 60, false, ReplayData())
  loadBots(result, [BotGroup(path: policy, count: PudgeCount)])
  result.humanSlots = if side == WestTeam: @[1, 2, 3, 4, 5] else: @[0, 1, 2, 4, 5]
  result.world.tick = 200
  for i, at in [(30, 40), (18, 16), (18, 112),
      (98, 40), (106, 100), (106, 112)]:
    result.world.pudges[i].placePudge(at[0], at[1])
    result.world.pudges[i].shieldTicks = 0
    result.world.pudges[i].blinkCooldown = BlinkCooldownTicks
    result.world.pudges[i].hookCooldown = HookCooldownTicks

proc step(game: Game) =
  tickWorld(game, proc() = runBotDecisions(game))
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

proc atShop(game: Game) =
  game.world.pudges[0].placePudge(WestShopX, ShopZ)
  # Keep vision placement from redirecting the shop fixture.
  game.world.pudges[0].wardCooldown = WardRestockTicks

suite "Base economy and vision":
  test "shopping targets the actual shop on either bank, not a spawn pad":
    for team in Team:
      let game = fixture(team)
      let seat = if team == WestTeam: 0 else: 3
      game.world.pudges[seat].gold = 24
      game.step()
      check game.world.pudges[seat].moveX == (if team == WestTeam: WestShopX else: EastShopX)
      check game.world.pudges[seat].moveZ == ShopZ

  test "a funded shop visit buys multiple permanent ranks using a local budget":
    let game = fixture()
    game.atShop()
    game.world.pudges[0].gold = 44
    game.step()
    check game.world.pudges[0].itemRank[ShopLongshot] == 2
    check game.world.pudges[0].itemRank[ShopBoots] == 2
    check game.world.pudges[0].gold == 0

  test "no gold is spent refreshing an active Big Hook buff":
    let game = fixture()
    game.atShop()
    game.world.pudges[0].itemRank[ShopLongshot] = ItemMaxRank
    game.world.pudges[0].itemRank[ShopBoots] = ItemMaxRank
    game.world.pudges[0].gold = 6
    game.world.pudges[0].buffKind = RuneBigHook
    game.world.pudges[0].buffTicks = 300
    game.step()
    check game.world.pudges[0].gold == 6
    check game.world.pudges[0].buffTicks < 300

  test "buy one Big Hook when core items are complete and no buff is active":
    let game = fixture()
    game.atShop()
    game.world.pudges[0].itemRank[ShopLongshot] = ItemMaxRank
    game.world.pudges[0].itemRank[ShopBoots] = ItemMaxRank
    game.world.pudges[0].gold = 12
    game.step()
    check game.world.pudges[0].gold == 6
    check game.world.pudges[0].buffKind == RuneBigHook
    game.step()
    check game.world.pudges[0].gold == 6

  test "a wounded buyer gets a flask before permanent items":
    let game = fixture()
    game.atShop()
    game.world.pudges[0].gold = 17
    game.world.pudges[0].hp = 200
    game.step()
    check game.world.pudges[0].hp == game.world.pudges[0].maxHp
    check game.world.pudges[0].itemRank[ShopLongshot] == 1
    check game.world.pudges[0].gold == 0

  test "pick up a free ward even with no gold":
    let game = fixture()
    game.world.pudges[0].placePudge(WestShopX, ShopZ)
    game.step()
    check game.world.pudges[0].itemRank[ShopWard] == 1
    check game.world.pudges[0].gold == 0
    check game.world.pudges[0].wardCooldown > 0

  test "plant a carried ward on the enemy bank from safe land on both sides":
    for team in Team:
      let game = fixture(team)
      let seat = if team == WestTeam: 0 else: 3
      let x = if team == WestTeam: PlayWestMax - 5 else: PlayEastMin + 5
      let targetX = if team == WestTeam: PlayEastMin + 3 else: PlayWestMax - 3
      var y = 16
      while y < 112 and not game.world.wardSiteLegal(targetX, y): inc y
      doAssert y < 112
      game.world.pudges[seat].placePudge(x, y)
      game.world.pudges[seat].itemRank[ShopWard] = 1
      game.step()
      check game.world.pudges[seat].itemRank[ShopWard] == 0
      check game.world.props.len == 1
      if game.world.props.len == 1:
        check game.world.props[0].kind == PropWard
        check game.world.props[0].tileX == targetX
      check not game.world.pudges[seat].inRiver

  test "a ward trip does not override a human rally":
    let game = fixture()
    game.world.pudges[0].itemRank[ShopWard] = 1
    check applyPing(game.world, game.world.pudges[1].id, 30, 104)
    game.step()
    check game.world.pudges[0].moveX == 30
    check game.world.pudges[0].moveZ == 104

  test "a ward trip does not override a low health retreat":
    let game = fixture()
    game.world.pudges[0].itemRank[ShopWard] = 1
    game.world.pudges[0].hp = 200
    let home = game.world.pudges[0].spawnTile
    game.step()
    check game.world.pudges[0].moveX == home.x
    check game.world.pudges[0].moveZ == home.z

  test "maxed upgrades terminate without wasting remaining points":
    let game = fixture()
    for kind in UpgradeKind:
      game.world.pudges[0].upgrades[kind] = MaxUpgradeLevel
    game.world.pudges[0].points = 4
    game.step()
    check game.world.pudges[0].points == 4

  test "engage a ward-revealed enemy inside actual base hook range":
    let game = fixture()
    game.world.pudges[0].placePudge(35, 40)
    game.world.pudges[0].hookCooldown = 0
    game.world.pudges[3].placePudge(90, 40)
    game.world.props.add Prop(id: game.world.nextPropId, kind: PropWard,
      ownerId: game.world.pudges[0].id, team: WestTeam,
      tileX: 79, tileZ: 40, hp: 1, maxHp: 1,
      ticksLeft: WardDurationTicks, alive: true)
    inc game.world.nextPropId
    game.step()
    check game.world.pudges[0].windupTicks > 0

  test "shop buffs do not replace an active double-damage rune":
    let game = fixture()
    game.atShop()
    game.world.pudges[0].itemRank[ShopLongshot] = ItemMaxRank
    game.world.pudges[0].itemRank[ShopBoots] = ItemMaxRank
    game.world.pudges[0].gold = 12
    game.world.pudges[0].buffKind = RuneDoubleDamage
    game.world.pudges[0].buffTicks = 300
    game.step()
    check game.world.pudges[0].buffKind == RuneDoubleDamage
    check game.world.pudges[0].gold == 12

  test "a ward trip does not override escaping a teammate's Rot cloud":
    let game = fixture()
    game.world.pudges[0].itemRank[ShopWard] = 1
    game.world.pudges[1].placePudge(36, 40)
    game.world.pudges[1].rotOn = true
    let home = game.world.pudges[0].spawnTile
    game.step()
    check game.world.pudges[0].moveX == home.x
    check game.botSpeech[0].text == "backing off rot"

  test "a ward trip does not override an incoming-hook dodge":
    let game = fixture()
    game.world.pudges[0].itemRank[ShopWard] = 1
    game.world.hooks.add Hook(id: game.world.nextHookId,
      ownerId: game.world.pudges[3].id, team: EastTeam, phase: HookFlying,
      position: worldAtTile(48, 40), prior: worldAtTile(48, 40),
      origin: worldAtTile(76, 40), heading: heading(-WorldScale, 0),
      range: BaseHookRange, speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    game.step()
    check game.world.pudges[0].moveX == 28
    check game.world.pudges[0].moveZ == 50

  test "a ward trip does not override a deliberate ally rescue":
    let game = fixture()
    game.world.pudges[0].placePudge(42, 40)
    game.world.pudges[0].hookCooldown = 0
    game.world.pudges[0].itemRank[ShopWard] = 1
    game.world.pudges[1].placePudge(RiverCenterX, 40)
    game.world.pudges[1].hp = 180
    game.step()
    check game.world.pudges[0].windupTicks > 0
    check not game.world.pudges[0].hasMoveTarget
    check game.botSpeech[0].text == "pulling you out"
