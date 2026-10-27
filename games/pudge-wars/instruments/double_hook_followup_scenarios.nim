## Follow-up timing drill: finisher observes the full cast but its hook stays
## on cooldown until the allied catch. Normal movement remains enabled.
## This isolates measured-speed follow-up aiming, not natural hook readiness.
import std/[os, json], polyworld/cli,
  ../../../examples/pudge_wars/[bots, content, maps, replays, sim]
if paramCount() != 1:
  quit "Usage: double_hook_followup_scenarios path/to/policy.bas", 1
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
          game.world.pudges[ally].upgrades[UpgradeSpeed] = int32(speed)
          game.world.pudges[ally].upgrades[UpgradeDistance] = 5
          doAssert applyHookTo(game.world, game.world.pudges[ally].id, int32(mx(victimX)), int32(lane))
          var approaching = false
          for tick in 0..<100:
            game.world.pudges[me].hookCooldown = 1000
            tickWorld(game, proc() = runBotDecisions(game))
            approaching = game.world.pudges[enemy].hookedBy == game.world.pudges[ally].id
            if approaching: break
          if not approaching:
            echo $(%*{"bank":bank,"lane":lane,"offset":offset,"victimX":victimX,"speed":speed,"caught":false,"headshot":0})
            continue
          game.world.pudges[me].hookCooldown = 0
          var aimX, aimY: int32 = -1
          for tick in 0..<110:
            tickWorld(game, proc() = runBotDecisions(game))
            doAssert not game.heroVms[me].failed, game.heroVms[me].lastError
            if aimX < 0 and game.world.pudges[me].windupTicks > 0:
              aimX = game.world.pudges[me].windupAimX div FineAimScale
              aimY = game.world.pudges[me].windupAimY div FineAimScale
            if game.world.pudges[enemy].state == Dying: break
          echo $(%*{"bank":bank,"lane":lane,"offset":offset,"victimX":victimX,"speed":speed,
            "caught":true,"headshot":game.world.pudges[me].headshotCount,"aimX":aimX,"aimY":aimY})
