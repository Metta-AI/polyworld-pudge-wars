## Behavioral contracts for a bot playing beside a human, not just against bots.
import
  std/[os, unittest],
  polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim, teammates]

const TeammatePolicy {.strdefine.} = ""
let policy = if TeammatePolicy.len > 0: TeammatePolicy else:
  currentSourcePath().parentDir.parentDir / "examples/pudge_wars/players/base.bas"

proc fixture(): Game =
  result = newGame(generateMap(2026), 400, false, ReplayData())
  loadBots(result, [BotGroup(path: policy, count: PudgeCount)])
  # Only seat zero runs a policy; other seats are humans with no new orders.
  result.humanSlots = @[1, 2, 3, 4, 5]
  for i, at in [(30, 40), (18, 16), (18, 112),
      (106, 16), (106, 64), (106, 112)]:
    result.world.pudges[i].placePudge(at[0], at[1])
    result.world.pudges[i].shieldTicks = 0
    result.world.pudges[i].blinkCooldown = BlinkCooldownTicks

proc step(game: Game, ticks = 1) =
  for _ in 0..<ticks:
    tickWorld(game, proc() = runBotDecisions(game))
    for vm in game.heroVms:
      doAssert not vm.failed, vm.lastError

suite "Default bot teammate behavior":
  test "offensive throw does not immediately latch an adjacent healthy human":
    let game = fixture()
    game.world.pudges[1].placePudge(32, 45)
    game.world.pudges[3].placePudge(RiverCenterX, 40)
    var friendlyGrabs = 0
    for _ in 0..<32:
      game.step()
      if game.world.pudges[1].justGrabbed:
        inc friendlyGrabs
    check friendlyGrabs == 0
    check game.world.pudges[0].hasMoveTarget or
      game.world.pudges[0].hooksThrown > 0

  test "a deliberate drowning-ally rescue remains possible":
    let game = fixture()
    game.world.pudges[0].placePudge(42, 40)
    game.world.pudges[1].placePudge(RiverCenterX, 40)
    game.world.pudges[1].hp = 180
    var rescued = false
    for _ in 0..<48:
      game.step()
      if game.world.pudges[1].justGrabbed and
          game.world.pudges[1].hookedBy == game.world.pudges[0].id:
        rescued = true
    check rescued
    check game.world.pudges[1].state == Alive
    check not game.world.pudges[1].inRiver

  test "do not steal a rescue already carried by a human teammate":
    let game = fixture()
    game.world.pudges[0].placePudge(40, 50)
    game.world.pudges[1].placePudge(35, 40)
    game.world.pudges[2].placePudge(RiverCenterX, 40)
    let rescuer = game.world.pudges[1].id
    game.world.pudges[2].hookedBy = rescuer
    game.world.hooks.add Hook(
      id: game.world.nextHookId, ownerId: rescuer, team: WestTeam,
      phase: HookReeling, victimId: game.world.pudges[2].id,
      position: game.world.pudges[2].position,
      prior: game.world.pudges[2].position,
      origin: game.world.pudges[1].position,
      heading: heading(WorldScale, 0), range: BaseHookRange,
      speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    game.step()
    if game.world.pudges[0].windupTicks > 0:
      let aim = worldAtFine(game.world.pudges[0].windupAimX,
        game.world.pudges[0].windupAimY)
      check distanceSquared(aim, game.world.pudges[2].position) >
        int64(WorldScale * 4) * (WorldScale * 4)
    check game.world.pudges[2].hookedBy == rescuer

  test "one available bot responds to a human rally ping":
    let game = fixture()
    game.world.pudges[0].placePudge(30, 64)
    game.world.pudges[2].placePudge(18, 32)
    game.humanSlots = @[1, 3, 4, 5]
    check applyPing(game.world, game.world.pudges[1].id, 30, 104)
    game.step()
    check game.world.pudges[0].hasMoveTarget
    check game.world.pudges[0].moveX == 30
    check game.world.pudges[0].moveZ == 104
    check game.world.pudges[2].moveZ != 104
    check game.botSpeech[0].text == "covering your ping"

  test "expired, enemy and own pings do not redirect the bot":
    for pingKind in 0..2:
      let game = fixture()
      game.world.tick = TickRate * 5
      let issuer = case pingKind
        of 0: game.world.pudges[1].id
        of 1: game.world.pudges[3].id
        else: game.world.pudges[0].id
      check applyPing(game.world, issuer, 30, 104)
      if pingKind == 0:
        game.world.pings[^1].tick = 0
      game.step()
      check game.world.pudges[0].moveZ != 104

  test "river rally stays on a safe throwing bank":
    let game = fixture()
    check applyPing(game.world, game.world.pudges[1].id, RiverCenterX, 104)
    game.step()
    check game.world.pudges[0].moveZ == 104
    check game.world.pudges[0].moveX <= PlayWestMax
    check not game.world.pudges[0].inRiver

  test "a ping does not override an immediate defensive blink":
    let game = fixture()
    game.world.pudges[0].blinkCooldown = 0
    game.world.hooks.add Hook(
      id: game.world.nextHookId, ownerId: game.world.pudges[3].id,
      team: EastTeam, phase: HookFlying,
      position: worldAtTile(48, 40), prior: worldAtTile(48, 40),
      origin: worldAtTile(76, 40), heading: heading(-WorldScale, 0),
      range: BaseHookRange, speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    check applyPing(game.world, game.world.pudges[1].id, 30, 104)
    game.step()
    check game.world.pudges[0].justBlinked

  test "east-side bot also answers its human teammate":
    let game = fixture()
    game.humanSlots = @[0, 1, 2, 4, 5]
    game.world.pudges[3].placePudge(98, 40)
    check applyPing(game.world, game.world.pudges[4].id, RiverCenterX, 100)
    game.step()
    check game.world.pudges[3].moveZ == 100
    check game.world.pudges[3].moveX >= PlayEastMin
    check game.botSpeech[3].text == "covering your ping"

suite "Read-only teammate planning":
  test "healthy swimmers are not involuntarily rescued without a help ping":
    let game = fixture()
    game.world.pudges[0].placePudge(42, 40)
    game.world.pudges[1].placePudge(RiverCenterX, 40)
    let ally = game.world.pudges[1].id
    check not game.world.needsRescue(game.world.pudges[1])
    check not game.world.mayRescueAlly(game.world.pudges[0].id, ally)
    check applyPing(game.world, ally, RiverCenterX, 40)
    check game.world.needsRescue(game.world.pudges[1])
    check game.world.mayRescueAlly(game.world.pudges[0].id, ally)

  test "nearby explicit saves keep the same collision rules":
    let game = fixture()
    game.world.pudges[0].placePudge(PlayWestMax, 40)
    game.world.pudges[1].placePudge(PlayWestMax + 6, 40)
    game.world.pudges[1].hp = 120
    check game.world.mayRescueAlly(game.world.pudges[0].id, game.world.pudges[1].id)

  test "a healthy enemy-carried ally still needs an urgent rescue":
    let game = fixture()
    game.world.pudges[1].hookedBy = game.world.pudges[3].id
    check game.world.needsRescue(game.world.pudges[1])

  test "do not rescue someone into the river or a rot cloud":
    let game = fixture()
    let caster = game.world.pudges[0].id
    let ally = game.world.pudges[1].id
    game.world.pudges[1].placePudge(RiverCenterX, 40)
    game.world.pudges[1].hp = 120
    game.world.pudges[0].placePudge(RiverCenterX, 50)
    check not game.world.mayRescueAlly(caster, ally)
    game.world.pudges[0].placePudge(42, 40)
    game.world.pudges[0].rotOn = true
    check not game.world.mayRescueAlly(caster, ally)

  test "an in-flight rescue is reserved before it latches":
    let game = fixture()
    game.world.pudges[0].placePudge(42, 50)
    game.world.pudges[1].placePudge(35, 40)
    game.world.pudges[2].placePudge(RiverCenterX, 40)
    game.world.pudges[2].hp = 120
    game.world.pudges[1].windupAimX = fineOfTile(RiverCenterX)
    game.world.pudges[1].windupAimY = fineOfTile(40)
    game.world.hooks.add Hook(ownerId: game.world.pudges[1].id,
      team: WestTeam, phase: HookFlying)
    check not game.world.mayRescueAlly(game.world.pudges[0].id, game.world.pudges[2].id)

  test "friendly lane check respects direction, motion, and empowered radius":
    let game = fixture()
    let caster = game.world.pudges[0].id
    game.world.pudges[1].placePudge(42, 47)
    check game.world.friendlyHookLaneClear(caster, 70, 40)
    game.world.pudges[0].buffKind = RuneBigHook
    game.world.pudges[0].buffTicks = RuneBuffTicks
    check not game.world.friendlyHookLaneClear(caster, 70, 40)
    game.world.pudges[0].buffTicks = 0
    game.world.pudges[1].velZ = -MovePerTick
    check not game.world.friendlyHookLaneClear(caster, 70, 40)
    game.world.pudges[1].placePudge(18, 40)
    check game.world.friendlyHookLaneClear(caster, 70, 40)
    check not game.world.friendlyHookLaneClear(caster, -1, 40)

  test "only healthy bot seats are assigned a ping; ties use stable ids":
    let game = fixture()
    game.humanSlots = @[1, 3, 4, 5]
    game.world.pudges[0].placePudge(30, 40)
    game.world.pudges[2].placePudge(30, 60)
    check applyPing(game.world, game.world.pudges[1].id, 30, 50)
    check game.teamPingResponder(WestTeam) == game.world.pudges[0].id
    game.world.pudges[0].hp = 100
    check game.teamPingResponder(WestTeam) == game.world.pudges[2].id
    game.humanSlots.add 2
    check game.teamPingResponder(WestTeam) == 0

  test "planning does not mutate the authoritative world":
    let game = fixture()
    let before = game.stateHash()
    discard game.world.friendlyHookLaneClear(game.world.pudges[0].id, 70, 40)
    discard game.world.mayRescueAlly(game.world.pudges[0].id, game.world.pudges[1].id)
    discard game.teamPingResponder(WestTeam)
    check game.stateHash() == before

  test "a bot reeling a teammate home leaves the rally to another bot":
    let game = fixture()
    game.humanSlots = @[1, 3, 4, 5]
    check applyPing(game.world, game.world.pudges[1].id, 30, 40)
    game.world.hooks.add Hook(ownerId: game.world.pudges[0].id,
      victimId: game.world.pudges[1].id, team: WestTeam, phase: HookReeling)
    check game.teamPingResponder(WestTeam) == game.world.pudges[2].id

  test "readiness includes windup and the whole active chain":
    let game = fixture()
    check game.world.canThrowHook(game.world.pudges[0])
    game.world.pudges[0].windupTicks = 1
    check not game.world.canThrowHook(game.world.pudges[0])
    game.world.pudges[0].windupTicks = 0
    for phase in [HookFlying, HookReeling]:
      game.world.hooks = @[Hook(ownerId: game.world.pudges[0].id,
        team: WestTeam, phase: phase)]
      check not game.world.canThrowHook(game.world.pudges[0])
    game.world.hooks[0].phase = HookIdle
    check game.world.canThrowHook(game.world.pudges[0])
