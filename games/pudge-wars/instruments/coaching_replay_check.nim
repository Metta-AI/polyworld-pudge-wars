## Verify stock-start local coaching evaluations against every recorded state hash.
import std/[os, json]
import polyworld/tapes
import ../../../examples/pudge_wars/[content, maps, replays, sim]

for i in 1 .. paramCount():
  let data = loadReplay(paramStr(i))
  let setup = data.header.setup
  # Hosted duels use the three-lane map with a compact two-seat roster.
  # Roster size alone cannot reconstruct the recorded geometry.
  let map = generateMapMatching(setup.mapSeed, setup.mapHash)
  doAssert map.hash == setup.mapHash, "could not reproduce recorded map"
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
