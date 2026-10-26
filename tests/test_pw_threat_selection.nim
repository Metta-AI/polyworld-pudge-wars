## Unequal-distance threat selection must not depend on hook iteration order.
import std/[os, unittest], bassy,
  polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

const ThreatPolicy {.strdefine.} = ""
let policy = if ThreatPolicy.len > 0: ThreatPolicy else:
  currentSourcePath().parentDir.parentDir / "examples/pudge_wars/players/base.bas"

suite "nearest hook defense":
  test "distance and coordinates belong to the same hook in either order":
    for reverse in [false, true]:
      let game = newGame(generateMap(2026), 400, false, ReplayData())
      loadBots(game, [BotGroup(path: policy, count: PudgeCount)])
      game.humanSlots = @[1, 2, 3, 4, 5]
      for i, at in [(30, 64), (18, 16), (18, 112),
                    (106, 16), (106, 64), (106, 112)]:
        game.world.pudges[i].placePudge(at[0], at[1])
        game.world.pudges[i].shieldTicks = 0
      # The near hook is below us; the farther hook is above. Choosing the
      # wrong Y reverses dodgeSide, not just an internal diagnostic variable.
      let positions = if reverse: @[(46, 58), (38, 68)] else: @[(38, 68), (46, 58)]
      for at in positions:
        game.world.hooks.add Hook(
          id: game.world.nextHookId, ownerId: game.world.pudges[3].id,
          team: EastTeam, phase: HookFlying,
          position: worldAtTile(at[0], at[1]), prior: worldAtTile(at[0], at[1]),
          origin: worldAtTile(55, at[1]), heading: heading(-WorldScale, 0),
          range: BaseHookRange, speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
          radius: BaseHookRadius, damage: BaseHookDamage)
        inc game.world.nextHookId
      tickWorld(game, proc() = runBotDecisions(game))
      let vm = game.heroVms[0]
      check not vm.failed
      check vm.runtime.getGlobal("threatD2").asInt == 80
      check vm.runtime.getGlobal("threatX").asInt == 38
      check vm.runtime.getGlobal("threatY").asInt == 68
      check vm.runtime.getGlobal("dodgeSide").asInt == -1
      check game.world.pudges[0].justBlinked
