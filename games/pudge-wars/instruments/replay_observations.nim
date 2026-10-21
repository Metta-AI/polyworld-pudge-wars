## Resimulate and verify a replay, exposing the same fog-filtered JSON view as the host.
import std/[os, json, strutils]
import polyworld/tapes
import ../../../examples/pudge_wars/[content, maps, replays, sim, coworld_host]
if paramCount() != 2:
  quit "Usage: replay_observations replay.pwr team(0|1)", 1
let data = loadReplay(paramStr(1))
let replaySetup = data.header.setup
let side = paramStr(2).parseInt
if side notin 0 .. 1:
  quit "Team must be 0 or 1", 1
let replayMap = generateMap(replaySetup.mapSeed, replaySetup.pudges.len div 2)
game = newGame(replayMap, int32(replaySetup.maximumTicks), true, data)
game.replayPlayer = initReplayPlayer(data)
game.historyPlayback = true
while game.world.tick < data.hashes.len and not game.world.gameOver:
  tickWorld(game, proc() = discard)
  for slot, pudge in game.world.pudges:
    if pudge.team.ord == side:
      echo observation(slot)
game.hashCheck.requireReplayComplete(uint32(game.world.tick), data.hashes.len)
doAssert game.replayPlayer.actionIndex == data.actions.len
stderr.writeLine($(%*{"verified_ticks":game.world.tick,"mismatches":game.hashCheck.mismatches,"score":game.world.teamKills}))
