## Reproduces the coworld host's record-vs-replay determinism at its own
## seat layout: every seat a human (no BASIC bots), commands injected the
## way a JSON policy would. The live host records a tape + per-tick hash;
## a follower replays it and must agree tick for tick. If they diverge
## this pins the first tick and dumps both states.

import
  std/[os, strutils],
  polyworld/tapes,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const Ticks = 120'i32

let map = generateMap(7)

proc liveGame(): Game =
  ## The coworld host's world: 3v3 roster, every seat human, tape on.
  result = newGame(map, Ticks, false, ReplayData(), killGoal = 3)
  result.humanSlots.setLen(0)
  for i in 0 ..< result.world.pudges.len:
    result.humanSlots.add i
  result.recorder = initReplayRecorder(currentSetup(result, uint32(Ticks)))
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc followerGame(setup: Setup): Game =
  result = Game(
    world: newWorld(map, Ticks, setup.pudges, setup.killGoal, setup.runePeriod),
    map: map,
    maximumTicks: Ticks,
    botEvery: 1,
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup)),
  )

echo "Testing an all-human live recording replays hash-exact"
block:
  let host = liveGame()
  # A JSON policy walking a couple of seats early, like the cert match.
  for tick in 1'i32 .. Ticks:
    if tick == 4:
      queueIntent(host, HumanIntent(slot: 1, kind: IntentWalk, a: 90, b: 64))
      queueIntent(host, HumanIntent(slot: 4, kind: IntentWalk, a: 40, b: 64))
    if tick == 6:
      queueIntent(host, HumanIntent(slot: 2, kind: IntentWalk, a: 88, b: 70))
    if tick == 8:
      # Hooks are what the rusher/camper policies actually cast; the
      # walk-only case did not reproduce the coworld divergence.
      queueIntent(host, HumanIntent(
        slot: 2, kind: IntentHookFine, a: fineOfTile(64), b: fineOfTile(64)))
      queueIntent(host, HumanIntent(
        slot: 5, kind: IntentHookFine, a: fineOfTile(64), b: fineOfTile(60)))
    tickWorld(host, proc() = runBotDecisions(host))

  # Replay the recorded tape through a pure follower.
  let client = followerGame(host.recorder.data.header.setup)
  client.replayPlayer.data = host.recorder.data
  var firstBad = -1
  for tick in 1'i32 .. Ticks:
    tickWorld(client, proc() = discard)
    var expected: uint64
    if host.recorder.data.hashes.hashAt(uint32(tick), expected):
      if stateHash(client) != expected and firstBad < 0:
        firstBad = tick
        echo "  DIVERGE at tick ", tick,
          " live=", expected.toHex(16), " replay=", stateHash(client).toHex(16)
  doAssert firstBad < 0,
    "all-human live recording diverged from its replay at tick " & $firstBad
  doAssert host.recordingError.len == 0, host.recordingError
  let encoded = encodeCoworldReplay(host.recorder.data)
  let decoded = decodeReplay(encoded)
  doAssert decoded.header.setup.maximumTicks == uint32(Ticks)
  doAssert decoded.hashes.len == Ticks
  doAssert decoded.actions.len == host.recorder.data.actions.len

echo "test_pw_coworld_record: all checks passed"
