## Deterministic accelerated evaluation using the real native simulation and JSON actions.
## Each policy sees only its own fog-filtered observation. No network timing is modeled.
import std/[json, os, strutils]
import ../../examples/pudge_wars/[content, maps, bots, replays, sim, coworld_host]
let seed = paramStr(1).parseInt.int32
let n = paramStr(2).parseInt
maxTicks = paramStr(3).parseInt.int32
let goal = paramStr(4).parseInt.int32
game = newGame(generateMap(seed, n), maxTicks, false, ReplayData(), killGoal = goal)
for i in 0 ..< game.world.pudges.len: game.humanSlots.add i
# Optional authored starting positions for native movement regression scenes.
# Policies still receive ordinary observations; no fixture fields leak into IR.
if paramCount() >= 5:
  let fixture = parseFile(paramStr(5))
  for entry in fixture["players"]:
    let slot = entry["slot"].getInt
    game.world.pudges[slot].placePudge(entry["x"].getInt, entry["y"].getInt)
while not game.world.gameOver and game.world.tick < maxTicks:
  var observations = newJArray()
  for i in 0 ..< game.world.pudges.len: observations.add observation(i)
  stdout.writeLine($observations)
  stdout.flushFile()
  let actions = parseJson(stdin.readLine())
  doAssert actions.len == game.world.pudges.len
  for i in 0 ..< game.world.pudges.len: applyAction(i, actions[i])
  tickWorld(game, proc() = runBotDecisions(game))
  snapshotAccepted()
  game.intentResults.setLen(0)
var seats = newJArray()
for pudge in game.world.pudges:
  seats.add %*{"team": pudge.team.ord, "kills": pudge.kills, "deaths": pudge.deaths}
stdout.writeLine($(%*{"final":true,"tick":game.world.tick,"seats":seats,"score":game.world.teamKills}))
