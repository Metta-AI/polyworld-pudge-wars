## Headless JSONL access to the exact Coworld match simulation and player view.

import std/[json, strutils]
import polyworld/cli
import content, maps, sim, bots, replays
import coworld_host as host

var learnerSlot: int

proc snapshot(): JsonNode =
  let final = host.game.world.gameOver or host.game.world.tick >= host.maxTicks
  %*{
    "observation": host.observation(learnerSlot, final),
    "done": final
  }

proc handle(request: JsonNode): JsonNode =
  case request["kind"].getStr
  of "reset":
    let
      seats = request["seats"].getInt
      seed = int32(request["seed"].getInt)
    if seats < 2 or seats > MaxPudgeCount or seats mod 2 != 0:
      raise newException(ValueError, "Pudge Wars needs 2, 4, 6, 8, or 10 seats")
    learnerSlot = request["learner_slot"].getInt
    if learnerSlot < 0 or learnerSlot >= seats:
      raise newException(ValueError, "Learner slot is outside the roster")
    host.maxTicks = int32(request["max_ticks"].getInt)
    if host.maxTicks < 1:
      raise newException(ValueError, "max_ticks must be positive")
    host.fogOn = true
    let teamSize = if seats == DuelPudgeCount: TeamSize else: seats div 2
    host.game = newGame(
      generateMap(seed, teamSize), host.maxTicks, false, ReplayData(),
      if seats == DuelPudgeCount: DuelKillGoal else: KillGoal,
      RunePeriodTicks, seats == DuelPudgeCount
    )
    host.game.humanSlots = @[learnerSlot]
    loadBots(host.game, [BotGroup(
      path: "examples/pudge_wars/players/base.bas", count: seats - 1
    )])
    host.snapshotAccepted()
    result = snapshot()
  of "step":
    if request["tick"].getInt != host.game.world.tick:
      raise newException(ValueError, "Action belongs to another tick")
    host.applyAction(learnerSlot, request["action"])
    tickWorld(host.game, proc() = runBotDecisions(host.game))
    host.snapshotAccepted()
    result = snapshot()
  else:
    raise newException(ValueError, "Unknown training host command")

for line in stdin.lines:
  if line.strip.len > 0:
    echo $handle(parseJson(line))
