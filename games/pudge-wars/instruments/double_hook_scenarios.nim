## Readiness-controlled double-hook drill using real allied casts.
## The finisher gets its first decision when the allied hook approaches the enemy.
## This isolates timing, not readiness, team formation, or overall match strength.
## Emit every fixture, including those where terrain prevents an approach.
import std/[os, json], polyworld/cli,
  ../../../examples/pudge_wars/[bots, content, maps, replays, sim]
if paramCount() != 1:
  quit "Usage: double_hook_scenarios path/to/policy.bas", 1
let policy = paramStr(1)
for bank in 0..1:
  for lane in [38, 88]:
    for offset in [-24, -12, 0, 12, 24]:
      for victimX in [60, 76, 92]:
        for speed in [0, 5, 10]:
          let game = newGame(generateMap(2026), 300, false, ReplayData())
          loadBots(game, [BotGroup(path: policy, count: PudgeCount)])
          let me = bank * 3
          let ally = me + 1
          let enemy = (1-bank) * 3
          for i in 0..<PudgeCount:
            if i != me: game.humanSlots.add i
            game.world.pudges[i].placePudge(if i < 3: 15 else: 112, 15 + (i mod 3)*45)
            game.world.pudges[i].shieldTicks = 1000
            game.world.pudges[i].blinkCooldown = BlinkCooldownTicks
          template mx(x: int): int = (if bank == 0: x else: 127-x)
          game.world.tick = 200
          game.world.pudges[me].placePudge(mx(38), lane+offset)
          game.world.pudges[ally].placePudge(mx(26), lane)
          game.world.pudges[enemy].placePudge(mx(victimX), lane)
          for i in [me, ally, enemy]: game.world.pudges[i].shieldTicks = 0
          game.humanSlots.add me
          game.world.pudges[ally].upgrades[UpgradeSpeed] = int32(speed)
          game.world.pudges[ally].upgrades[UpgradeDistance] = 5
          doAssert applyHookTo(game.world, game.world.pudges[ally].id, int32(mx(victimX)), int32(lane))
          var approaching = false
          for tick in 0..<100:
            tickWorld(game, proc() = discard)
            for h in game.world.hooks:
              if h.ownerId == game.world.pudges[ally].id and h.phase == HookFlying:
                let dx = h.position.x - game.world.pudges[enemy].position.x
                let dz = h.position.z - game.world.pudges[enemy].position.z
                if int64(dx)*dx + int64(dz)*dz < int64(12*WorldScale)*(12*WorldScale): approaching = true
            if approaching: break
          if not approaching:
            echo $(%*{"bank":bank,"lane":lane,"offset":offset,"victimX":victimX,"speed":speed,"approaching":false,"headshot":0})
            continue
          game.humanSlots.setLen(game.humanSlots.len - 1)
          var aimX, aimY: int32 = -1
          for tick in 0..<110:
            tickWorld(game, proc() = runBotDecisions(game))
            doAssert not game.heroVms[me].failed, game.heroVms[me].lastError
            if aimX < 0 and game.world.pudges[me].windupTicks > 0:
              aimX = game.world.pudges[me].windupAimX div FineAimScale
              aimY = game.world.pudges[me].windupAimY div FineAimScale
            if game.world.pudges[enemy].state == Dying: break
          echo $(%*{"bank":bank,"lane":lane,"offset":offset,"victimX":victimX,"speed":speed,
            "approaching":true,"headshot":game.world.pudges[me].headshotCount,"aimX":aimX,"aimY":aimY})
