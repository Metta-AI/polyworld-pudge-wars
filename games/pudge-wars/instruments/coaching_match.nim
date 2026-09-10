## Local native BASIC evaluation with complete action replay and diagnostic events.
## policy opponent teamSize seed ticks outputDir [fixture.json] [botEvery] [aimNoise]
import std/[json, os, strutils]
import polyworld/cli
import ../../../examples/pudge_wars/[bots, content, maps, replays, sim, duellog]

let candidate = paramStr(1)
let opponent = paramStr(2)
let n = paramStr(3).parseInt
let seed = paramStr(4).parseInt.int32
let ticks = paramStr(5).parseInt.int32
let output = paramStr(6)
doAssert not dirExists(output), "Use a new output directory"
var game = newGame(generateMap(seed, n), ticks, false, ReplayData(), killGoal = 30)
game.botEvery = if paramCount() >= 8: paramStr(8).parseInt.int32 else: 1
game.botAimNoise = if paramCount() >= 9: paramStr(9).parseInt.int32 else: 0
loadBots(game, [BotGroup(path: candidate, count: n), BotGroup(path: opponent, count: n)])
if paramCount() >= 7 and paramStr(7) != "-":
  let fixture = parseFile(paramStr(7))
  for entry in fixture["players"]:
    let slot = entry["slot"].getInt
    game.world.pudges[slot].placePudge(entry["x"].getInt, entry["y"].getInt)
    game.world.pudges[slot].shieldTicks = 0
    if entry.hasKey("hp"):
      game.world.pudges[slot].hp = entry["hp"].getInt.int32
  # Custom-position scenes have ordinary observations but are not stock-map
  # replay starts. Their actions/events are saved; see result replay_resimulatable.
game.recorder = initReplayRecorder(currentSetup(game, uint32(ticks)))
var scripts: seq[string]
for i in 0 ..< 2*n: scripts.add(if i < n: candidate else: opponent)
let logger = newDuelLogger(game, output, scripts, "coaching local evaluation")
while not game.world.gameOver and game.world.tick < ticks:
  tickWorld(game, proc() = runBotDecisions(game))
  for i in 0 ..< 2*n:
    doAssert not game.heroVms[i].failed, game.heroVms[i].lastError
  logger.logDuelTick(game)
logger.finishDuelLog(game)
saveReplay(output / "replay.pwr", game.recorder.data)
var seats = newJArray()
for i, hero in game.world.pudges:
  seats.add %*{"slot": i, "id": hero.id, "team": hero.team.ord,
    "kills": hero.kills, "deaths": hero.deaths, "hp": hero.hp,
    "hooks_thrown": hero.hooksThrown, "hooks_landed": hero.hooksLanded,
    "decisions": game.heroVms[i].decisions, "vm_failed": game.heroVms[i].failed}
let result = %*{"seed": seed, "team_size": n, "tick": game.world.tick,
  "score": game.world.teamKills, "bot_every": game.botEvery,
  "aim_noise": game.botAimNoise, "seats": seats,
  "replay_resimulatable": paramCount() < 7 or paramStr(7) == "-"}
writeFile(output / "result.json", result.pretty & "\n")
echo result
