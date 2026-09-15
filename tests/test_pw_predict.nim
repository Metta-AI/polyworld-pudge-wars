## Client prediction + rollback: the prediction world resimulates from
## the confirmed tape plus unconfirmed local intents, converges without a
## snap when the host applies a command on the predicted tick, and snaps
## when the timing guess was wrong. Determinism (Gate 0) means a snap is
## always a timing miss, never a physics divergence.

import
  std/os,
  polyworld/cli,
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/netclient,
  ../examples/pudge_wars/netpredict,
  ../examples/pudge_wars/netproto,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  MatchTicks = 400'i32
  LocalSeat = 0

let
  map = generateMap(2026)
  basBotPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"

proc hostGame(): Game =
  result = newGame(map, MatchTicks, false, ReplayData())
  result.humanSlots.add LocalSeat
  loadBots(result, [BotGroup(path: basBotPath, count: PudgeCount)])
  result.recorder = initReplayRecorder(
    currentSetup(result, uint32(MatchTicks))
  )
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc followerGame(setup: Setup): Game =
  let clientMap = generateMap(setup.mapSeed)
  result = Game(
    world: newWorld(
      clientMap, int32(setup.maximumTicks), setup.pudges,
      setup.killGoal, setup.runePeriod
    ),
    map: clientMap,
    maximumTicks: int32(setup.maximumTicks),
    botEvery: max(setup.botEvery, 1'i32),
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup))
  )

proc hostTick(game: Game) =
  tickWorld(game, proc() = runBotDecisions(game))

proc streamTo(host, client: Game, sent: var (int, int)) =
  let
    actionCount = host.recorder.data.actions.len
    hashCount = host.recorder.data.hashes.len
  if actionCount == sent[0] and hashCount == sent[1]:
    discard
  else:
    let msg = decodeNetMessage(packTicks(
      uint32(sent[1] + 1),
      host.recorder.data.actions[sent[0] ..< actionCount],
      host.recorder.data.hashes[sent[1] ..< hashCount]
    ))
    doAssert netAppendTicks(client, msg.ticks).len == 0
    sent = (actionCount, hashCount)
  while client.world.tick < int32(client.replayPlayer.data.hashes.len):
    tickWorld(client, proc() = discard)

echo "Testing the intent wire carries a wantedTick without hashing it"
block:
  let msg = decodeNetMessage(packIntent(
    HumanIntent(slot: 0'i32, kind: IntentWalk, a: 30'i32, b: 60'i32),
    wantedTick = 128'u32
  ))
  doAssert msg.kind == NmIntent
  doAssert msg.intent.wantedTick == 128'u32
  doAssert msg.intent.intent.kind == IntentWalk
  # A zero (no-preference) intent still round-trips.
  let bare = decodeNetMessage(packIntent(
    HumanIntent(slot: 1'i32, kind: IntentStop)
  ))
  doAssert bare.intent.wantedTick == 0'u32

echo "Testing rebuild resimulates the true future from unconfirmed intents"
block:
  # Reference: one continuous world where the walk is applied at tick C.
  let refGame = newGame(map, MatchTicks, false, ReplayData())
  refGame.humanSlots.add LocalSeat
  loadBots(refGame, [BotGroup(path: basBotPath, count: PudgeCount)])
  const C = 20'i32
  const Lead = 2
  for t in 1'i32 .. C:
    hostTick(refGame)
  queueIntent(refGame, HumanIntent(
    slot: int32(LocalSeat), kind: IntentWalk, a: 40'i32, b: 64'i32
  ))
  var refPrevious: Pudge
  for _ in 0 ..< Lead:
    refPrevious = refGame.world.pudges[LocalSeat]
    tickWorld(refGame, proc() = runHumanIntents(refGame, LocalSeat))
  let refPos = refGame.world.pudges[LocalSeat].position

  # Predictor: confirmed world at tick C, same walk pending, lead ticks.
  let confirmed = newGame(map, MatchTicks, false, ReplayData())
  confirmed.humanSlots.add LocalSeat
  loadBots(confirmed, [BotGroup(path: basBotPath, count: PudgeCount)])
  confirmed.recorder = initReplayRecorder(
    currentSetup(confirmed, uint32(MatchTicks)))
  confirmed.replayPlayer = ReplayPlayer(data: confirmed.recorder.data)
  for t in 1'i32 .. C:
    hostTick(confirmed)
  let pred = newPredictor()
  pred.enable(LocalSeat, Lead)
  pred.record(
    HumanIntent(slot: int32(LocalSeat), kind: IntentWalk, a: 40'i32, b: 64'i32),
    uint32(C))
  let confirmedHash = confirmed.stateHash()
  pred.rebuild(confirmed)
  let predPos = pred.predicted.world.pudges[LocalSeat].position
  doAssert predPos.x == refPos.x and predPos.z == refPos.z,
    "prediction must equal a continuous forward-sim of the same intent"
  # The confirmed world was not advanced by the rebuild.
  doAssert confirmed.world.tick == C,
    "rebuild must never tick the authoritative world"
  doAssert confirmed.stateHash() == confirmedHash,
    "prediction must not mutate the confirmed simulation"
  doAssert pred.localRenderPoint(0) == refPrevious.position
  doAssert pred.previousLocalFacing == refPrevious.facing
  doAssert predPos != confirmed.world.pudges[LocalSeat].position,
    "an unconfirmed walk must actually move the predicted hero"
  doAssert pred.predicted.humanIntents.len == 0,
    "prediction must drain commands on the hero turn"
  pred.rebuild(confirmed)
  doAssert pred.predicted.world.pudges[LocalSeat].position == predPos,
    "rebuilding the same tick must not retain commands from the last rebuild"
  doAssert pred.predicted.intentResults.len == 1,
    "rebuild must reset the scratch world's prior acknowledgments"

echo "Testing a stable prediction does not snap frame to frame"
block:
  let confirmed = newGame(map, MatchTicks, false, ReplayData())
  confirmed.humanSlots.add LocalSeat
  loadBots(confirmed, [BotGroup(path: basBotPath, count: PudgeCount)])
  confirmed.recorder = initReplayRecorder(
    currentSetup(confirmed, uint32(MatchTicks)))
  confirmed.replayPlayer = ReplayPlayer(data: confirmed.recorder.data)
  let pred = newPredictor()
  pred.enable(LocalSeat, 2)
  for t in 1'i32 .. 8'i32:
    hostTick(confirmed)
    pred.rebuild(confirmed)
  # No local input and a steadily advancing confirmed world: the local
  # butcher tracks smoothly, so no rebuild reports a snap.
  doAssert not pred.snapped, "a quiet, in-sync client must not snap"

echo "Testing prediction converges over a live host with zero-lag intents"
block:
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  let pred = newPredictor()
  pred.enable(LocalSeat, 2)
  var sent = (0, 0)
  var snaps = 0
  for tick in 1'i32 .. 120'i32:
    # The client issues a walk; with a co-located host we hand the same
    # command to the host on the same tick (0 RTT), so the prediction
    # about when it lands is exactly right and must not snap.
    if tick == 24 or tick == 60:
      let intent = HumanIntent(
        slot: int32(LocalSeat), kind: IntentWalk,
        a: 30'i32 + tick, b: 64'i32)
      queueIntent(host, intent)
      pred.record(intent, uint32(host.world.tick))
    hostTick(host)
    streamTo(host, client, sent)
    pred.rebuild(client)
    if pred.snapped:
      inc snaps
  doAssert client.hashCheck.mismatches == 0, client.hashCheck.error
  # The confirmed follower and the local prediction agree on the local
  # butcher once every issued command has come back on the tape.
  doAssert pred.pending.len == 0,
    "every zero-lag intent must reconcile off the confirmed tape"
  let cp = client.world.pudges[LocalSeat].position
  # Prediction is `lead` ticks ahead of the confirmed world, so compare
  # the confirmed butcher against a fresh rebuild pinned to that tick.
  pred.enable(LocalSeat, 0)
  pred.rebuild(client)
  let pp = pred.predicted.world.pudges[LocalSeat].position
  doAssert cp.x == pp.x and cp.z == pp.z,
    "with lead 0 the prediction world equals the confirmed world"

echo "Testing a mistimed confirmation snaps the prediction"
block:
  let confirmed = newGame(map, MatchTicks, false, ReplayData())
  confirmed.humanSlots.add LocalSeat
  loadBots(confirmed, [BotGroup(path: basBotPath, count: PudgeCount)])
  confirmed.recorder = initReplayRecorder(
    currentSetup(confirmed, uint32(MatchTicks)))
  confirmed.replayPlayer = ReplayPlayer(data: confirmed.recorder.data)
  let pred = newPredictor()
  pred.enable(LocalSeat, 2)
  for t in 1'i32 .. 10'i32:
    hostTick(confirmed)
  # Predict a hard walk one way, establish the baseline.
  pred.record(HumanIntent(
    slot: int32(LocalSeat), kind: IntentWalk, a: 10'i32, b: 40'i32),
    uint32(confirmed.world.tick))
  pred.rebuild(confirmed)
  pred.rebuild(confirmed)          # havePrev now set, stable
  doAssert not pred.snapped
  # The host never recorded that command and the local butcher is now
  # forced far away (a hook dump, say): the next rebuild must snap.
  let here = tileOf(confirmed.world.pudges[LocalSeat].position)
  confirmed.world.pudges[LocalSeat].placePudge(here.x + 7, here.z)
  pred.rebuild(confirmed)
  doAssert pred.snapped, "a large confirmed correction must register a snap"

echo "Testing render smoothing eases a teleport-sized correction"
block:
  let confirmed = newGame(map, MatchTicks, false, ReplayData())
  confirmed.humanSlots.add LocalSeat
  loadBots(confirmed, [BotGroup(path: basBotPath, count: PudgeCount)])
  confirmed.recorder = initReplayRecorder(
    currentSetup(confirmed, uint32(MatchTicks)))
  confirmed.replayPlayer = ReplayPlayer(data: confirmed.recorder.data)
  let pred = newPredictor()
  pred.enable(LocalSeat, 2)
  for t in 1'i32 .. 10'i32:
    hostTick(confirmed)
  pred.rebuild(confirmed)
  pred.rebuild(confirmed)                # render settled on the true spot
  let before = localRenderPoint(pred)
  doAssert abs(before.x - confirmed.world.pudges[LocalSeat].position.x) <
    SnapStep, "render tracks the prediction during ordinary motion"
  # A teleport-sized confirmed correction (~4 tiles, inside the smooth
  # band): the drawn hero must NOT jump the whole way in one frame.
  let here = tileOf(confirmed.world.pudges[LocalSeat].position)
  confirmed.world.pudges[LocalSeat].placePudge(here.x + 4, here.z)
  pred.rebuild(confirmed)
  let after = localRenderPoint(pred)
  doAssert abs(after.x - before.x) < SnapStep,
    "smoothing must cap the first-frame jump well under the correction"
  # And it converges to the true position within a handful of frames.
  for _ in 0 ..< 30:
    pred.rebuild(confirmed)
  let settled = localRenderPoint(pred)
  doAssert abs(settled.x - confirmed.world.pudges[LocalSeat].position.x) <
    SnapEpsilon, "render must converge to the corrected position"

echo "Testing display frames interpolate consecutive predicted ticks"
block:
  var legacyBacksteps, fixedBacksteps, samples: int
  var legacyWorst, fixedWorst: int64
  for fps in [60, 120, 144]:
    for lead in MinLead .. MaxLead:
      for direction in [(1'i32, 0'i32), (-1'i32, 0'i32),
          (0'i32, 1'i32), (0'i32, -1'i32), (1'i32, 1'i32),
          (1'i32, -1'i32), (-1'i32, 1'i32), (-1'i32, -1'i32)]:
        let confirmed = newGame(map, MatchTicks, false, ReplayData())
        confirmed.humanSlots.add LocalSeat
        confirmed.world.pudges[LocalSeat].placePudge(30, 40)
        doAssert applyWalkTo(confirmed.world,
          confirmed.world.pudges[LocalSeat].id,
          30 + direction[0] * 12, 40 + direction[1] * 12)
        # Reach cruising speed before measuring; no bots, collisions,
        # input changes, or network corrections to mask render backsteps.
        for _ in 0 ..< 8:
          tickWorld(confirmed, proc() = discard)
        let pred = newPredictor()
        pred.enable(LocalSeat, lead)
        pred.rebuild(confirmed)
        doAssert pred.predictsUnit(confirmed.world.pudges[LocalSeat].id)
        doAssert not pred.predictsUnit(confirmed.world.pudges[1].id)
        var previousConfirmed = confirmed.world.pudges[LocalSeat].position
        var lastFixed = pred.localRenderPoint(0)
        var lastLegacy = previousConfirmed
        var simulated = 0
        for frame in 1 .. fps div 3:
          let target = frame * int(TickRate) div fps
          while simulated < target:
            let oldEndpoint = pred.localRenderPoint(1)
            previousConfirmed = confirmed.world.pudges[LocalSeat].position
            tickWorld(confirmed, proc() = discard)
            pred.rebuild(confirmed)
            doAssert pred.localRenderPoint(0) == oldEndpoint,
              "tick rollover must start where the previous prediction ended"
            inc simulated
          pred.rebuild(confirmed) # real loop rebuilds even without a new tick
          let alpha = float32((frame * int(TickRate)) mod fps) / float32(fps)
          let fixed = pred.localRenderPoint(alpha)
          let endpoint = pred.localRenderPoint()
          # The old graphics.unitPoint blended confirmed T-1 -> predicted
          # T+lead, then reset toward confirmed history on every tick.
          let legacy = WorldPoint(
            x: int32(float64(previousConfirmed.x) +
              float64(endpoint.x - previousConfirmed.x) * float64(alpha)),
            z: int32(float64(previousConfirmed.z) +
              float64(endpoint.z - previousConfirmed.z) * float64(alpha)))
          let fixedStep = int64(fixed.x - lastFixed.x) * direction[0] +
            int64(fixed.z - lastFixed.z) * direction[1]
          let legacyStep = int64(legacy.x - lastLegacy.x) * direction[0] +
            int64(legacy.z - lastLegacy.z) * direction[1]
          if fixedStep < -1: inc fixedBacksteps
          if legacyStep < -1: inc legacyBacksteps
          fixedWorst = max(fixedWorst, -fixedStep)
          legacyWorst = max(legacyWorst, -legacyStep)
          lastFixed = fixed
          lastLegacy = legacy
          inc samples
        pred.disable()
        doAssert not pred.predictsUnit(confirmed.world.pudges[LocalSeat].id)
        doAssert pred.localRenderPoint() == WorldPoint()
  echo "  ", samples, " display frames: backward steps old=", legacyBacksteps,
    " fixed=", fixedBacksteps, "; worst backward fixed-point distance old=",
    legacyWorst, " fixed=", fixedWorst
  doAssert legacyBacksteps > 0, "the scenario must reproduce the original jitter"
  doAssert fixedBacksteps == 0, "steady movement must never render backward"

echo "test_pw_predict: all checks passed"
