## Verify the actual wire capture and archived replays from the socket test.
## nim c -r tests/test_pw_coaching_stream.nim SESSION_DIRECTORY
import
  std/[os, strutils],
  polyworld/tapes,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/netclient,
  ../examples/pudge_wars/netproto,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

proc follower(setup: Setup): Game =
  let map = generateMap(setup.mapSeed)
  doAssert map.hash == setup.mapHash
  Game(
    map: map,
    world: newWorld(map, int32(setup.maximumTicks), setup.pudges,
      setup.killGoal, setup.runePeriod),
    maximumTicks: int32(setup.maximumTicks), botEvery: 1,
    botSpeech: newSeq[BotSpeech](setup.pudges.len), historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup)))

proc catchUp(game: Game) =
  while game.world.tick < int32(game.replayPlayer.data.hashes.len):
    tickWorld(game, proc() = discard)
  doAssert game.hashCheck.mismatches == 0, game.hashCheck.error

let directory = paramStr(1)
var game: Game
var rounds, ticks: int
for line in lines(directory / "frames.hex"):
  if line.len == 0: continue
  let message = decodeNetMessage(parseHexStr(line))
  case message.kind
  of NmStart:
    game = follower(message.start.setup)
    inc rounds
  of NmTicks:
    doAssert game != nil
    doAssert netAppendTicks(game, message.ticks).len == 0
    catchUp(game)
    ticks += message.ticks.hashes.len
  else: discard
doAssert rounds == 3 and ticks > 100
for path in walkFiles(directory / "rounds" / "*.pwr"):
  let replay = decodeReplay(readFile(path))
  let recorded = follower(replay.header.setup)
  recorded.replayPlayer.data = replay
  catchUp(recorded)
  doAssert recorded.world.tick > 0
  echo "Verified archived replay: ", path
echo "Verified ", rounds, " native rounds and ", ticks, " ticks without a hash mismatch"
