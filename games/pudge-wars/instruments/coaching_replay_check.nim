## Verify stock-start local coaching evaluations against every recorded state hash.
import std/[os, json]
import polyworld/tapes
import ../../../examples/pudge_wars/[content, maps, replays, sim]

for i in 1 .. paramCount():
  let data = loadReplay(paramStr(i))
  let setup = data.header.setup
  let map = generateMap(setup.mapSeed, setup.pudges.len div 2)
  var game = newGame(map, int32(setup.maximumTicks), true, data)
  game.replayPlayer = initReplayPlayer(data)
  game.historyPlayback = true
  while game.world.tick < data.hashes.len and not game.world.gameOver:
    tickWorld(game, proc() = discard)
  game.hashCheck.requireReplayComplete(uint32(game.world.tick), data.hashes.len)
  doAssert game.replayPlayer.actionIndex == data.actions.len
  echo %*{"replay": paramStr(i), "verified_ticks": game.world.tick,
    "verified_actions": data.actions.len, "mismatches": game.hashCheck.mismatches,
    "score": game.world.teamKills}
