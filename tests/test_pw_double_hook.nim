## Complete two-hook sequences through the real BASIC VM and simulator.
import std/[os, unittest], polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const DoubleHookPolicy {.strdefine.} = ""
let policy = if DoubleHookPolicy.len > 0: DoubleHookPolicy else:
  currentSourcePath().parentDir.parentDir / "coaching/policies/double-hook-20261027/candidate.bas"

suite "anticipatory double hook":
  test "finish a teammate's real incoming cast from either bank":
    for bank in 0..1:
      let game = newGame(generateMap(2026), 300, false, ReplayData())
      loadBots(game, [BotGroup(path: policy, count: PudgeCount)])
      let me = bank * 3
      let ally = me + 1
      let enemy = (1-bank) * 3
      template mx(x: int): int = (if bank == 0: x else: 127-x)
      for i in 0..<PudgeCount:
        game.humanSlots.add i
        game.world.pudges[i].placePudge(if i < 3: 15 else: 112, 15 + (i mod 3)*45)
        game.world.pudges[i].shieldTicks = 1000
        game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
      game.world.tick = 200
      game.world.pudges[me].placePudge(mx(38), 26)
      game.world.pudges[ally].placePudge(mx(26), 38)
      game.world.pudges[enemy].placePudge(mx(76), 38)
      for i in [me, ally, enemy]: game.world.pudges[i].shieldTicks = 0
      doAssert applyHookTo(game.world, game.world.pudges[ally].id, int32(mx(76)), 38)
      var approaching = false
      for tick in 0..<100:
        tickWorld(game, proc() = discard)
        for h in game.world.hooks:
          if h.ownerId == game.world.pudges[ally].id and h.phase == HookFlying:
            let dx = h.position.x - game.world.pudges[enemy].position.x
            let dz = h.position.z - game.world.pudges[enemy].position.z
            if int64(dx)*dx + int64(dz)*dz < int64(12*WorldScale)*(12*WorldScale): approaching = true
        if approaching: break
      require approaching
      check game.world.pudges[enemy].hookedBy == 0
      game.humanSlots = @[]
      for i in 0..<PudgeCount:
        if i != me: game.humanSlots.add i
      tickWorld(game, proc() = runBotDecisions(game))
      check game.world.pudges[me].windupTicks > 0
      check game.world.pudges[enemy].hookedBy == 0
      check game.world.pudges[me].hasMoveTarget
      for tick in 0..<100:
        tickWorld(game, proc() = runBotDecisions(game))
        require not game.heroVms[me].failed
        if game.world.pudges[enemy].state == Dying: break
      check game.world.pudges[me].headshotCount == 1
      check game.world.pudges[enemy].state == Dying
      check game.world.teamKills[bank] == 1

  test "measure a fast allied hook before choosing the follow-up aim":
    let measuredPolicy = if DoubleHookPolicy.len > 0: DoubleHookPolicy else:
      currentSourcePath().parentDir.parentDir / "examples/pudge_wars/players/base.bas"
    for bank in 0..1:
      for speed in [5, 10]:
        let game = newGame(generateMap(2026), 300, false, ReplayData())
        loadBots(game, [BotGroup(path: measuredPolicy, count: PudgeCount)])
        let me = bank * 3
        let ally = me + 1
        let enemy = (1-bank) * 3
        template mx(x: int): int = (if bank == 0: x else: 127-x)
        for i in 0..<PudgeCount:
          if i != me: game.humanSlots.add i
          game.world.pudges[i].placePudge(if i < 3: 15 else: 112, 15 + (i mod 3)*45)
          game.world.pudges[i].shieldTicks = 1000
          game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
        game.world.tick = 200
        game.world.pudges[me].placePudge(mx(38), 88)
        game.world.pudges[ally].placePudge(mx(26), 88)
        game.world.pudges[enemy].placePudge(mx(92), 88)
        for i in [me, ally, enemy]: game.world.pudges[i].shieldTicks = 0
        game.world.pudges[ally].upgrades[UpgradeSpeed] = int32(speed)
        game.world.pudges[ally].upgrades[UpgradeDistance] = 5
        doAssert applyHookTo(game.world, game.world.pudges[ally].id, int32(mx(92)), 88)
        var caught = false
        for tick in 0..<100:
          # Observe the whole cast with normal movement, but no hook available.
          game.world.pudges[me].hookCooldown = 1000
          tickWorld(game, proc() = runBotDecisions(game))
          require not game.heroVms[me].failed
          caught = game.world.pudges[enemy].hookedBy == game.world.pudges[ally].id
          if caught: break
        require caught
        game.world.pudges[me].hookCooldown = 0
        for tick in 0..<110:
          tickWorld(game, proc() = runBotDecisions(game))
          require not game.heroVms[me].failed
          if game.world.pudges[enemy].state == Dying: break
        check game.world.pudges[me].headshotCount == 1
        check game.world.pudges[enemy].state == Dying
        check game.world.teamKills[bank] == 1
