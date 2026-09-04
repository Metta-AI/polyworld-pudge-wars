## Prediction-quality bench under latency + jitter.
##
## Models a delayed, jittery link over the *real* host, follower, and
## predictor: the host tape reaches the client `oneWay ± jitter` ticks late,
## and the client's intents reach the host the same way. A scripted player
## keeps reversing its walk to stress prediction. We measure, per network
## condition:
##   * snaps      - frames the predictor flagged a rebuild discontinuity
##   * jump p95   - 95th-percentile rendered local-hero move per frame (tiles),
##                  the felt "jerk"; lower is smoother
##   * jumpMax    - worst single-frame teleport (tiles)
##   * mismatches - confirmed-tape hash disagreements (must stay 0)
##
## It runs the same scenario per preset so tuning changes are comparable.
## Deterministic: the jitter RNG is seeded, so runs reproduce exactly.

import
  std/[algorithm, math, os, strformat, strutils],
  polyworld/[cli, profiles],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/netclient,
  ../examples/pudge_wars/netpredict,
  ../examples/pudge_wars/netproto,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  MatchTicks = 600'i32
  LocalSeat = 0
  Tile = 65536.0  ## fixed-point world units per tile

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
    currentSetup(result, uint32(MatchTicks)))
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc followerGame(setup: Setup): Game =
  let clientMap = generateMap(setup.mapSeed)
  Game(
    world: newWorld(clientMap, int32(setup.maximumTicks), setup.pudges,
      setup.killGoal, setup.runePeriod),
    map: clientMap,
    maximumTicks: int32(setup.maximumTicks),
    botEvery: max(setup.botEvery, 1'i32),
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup)))

# Seeded jitter RNG (splitmix64), independent of the sim.
var rngState = 0'u64
proc seedRng(s: uint64) = rngState = s
proc nextRand(): uint64 =
  rngState = rngState + 0x9E3779B97F4A7C15'u64
  var z = rngState
  z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9'u64
  z = (z xor (z shr 27)) * 0x94D049BB133111EB'u64
  z xor (z shr 31)
proc jitterSpan(halfTicks: int): int =
  if halfTicks <= 0: 0
  else: int(nextRand() mod uint64(2 * halfTicks + 1)) - halfTicks

type
  DownSlice = object
    deliverAt: int
    firstTick: uint32
    actions: seq[ReplayAction]
    hashes: seq[uint64]
  UpIntent = object
    arriveAt: int
    intent: HumanIntent
  Metrics = object
    snaps: int          ## frames whose rendered jump exceeds SnapThresh
    snapExcess: float    ## total tiles jumped beyond the movement ceiling
    mismatches: int
    jumps: seq[float]

const SnapThresh = 1.8  ## tiles/frame; above the max legitimate walk step,
                        ## so a larger jump is a prediction teleport, not motion

proc dist(a, b: WorldPoint): float =
  let dx = float(a.x) - float(b.x)
  let dz = float(a.z) - float(b.z)
  sqrt(dx * dx + dz * dz) / Tile

proc runScenario(latencyMs, jitterMs, seed: int; lead: int): Metrics =
  ## One full match over a link of `latencyMs` one-way each direction with
  ## `jitterMs` variation, driving the predictor at a fixed `lead`.
  seedRng(uint64(seed) + 1)
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  let pred = newPredictor()
  pred.enable(LocalSeat, lead)
  let oneWay = (latencyMs * int(TickRate)) div 1000
  let jit = (jitterMs * int(TickRate)) div 1000

  var down: seq[DownSlice]
  var up: seq[UpIntent]
  var sentActions = 0
  var sentHashes = 0
  var lastDown = 0
  var lastUp = 0
  var prevRender: WorldPoint
  var havePrev = false
  # Two far walk targets the player alternates between, reversing hard.
  const A = (18'i32, 40'i32)
  const B = (46'i32, 40'i32)

  for w in 1 .. int(MatchTicks):
    # 1. Host applies any intents that have arrived, then ticks.
    var i = 0
    while i < up.len:
      if up[i].arriveAt <= w:
        queueIntent(host, up[i].intent)
        up.delete(i)
      else:
        inc i
    tickWorld(host, proc() = runBotDecisions(host))
    # Schedule the new tape slice for delivery (monotonic order).
    let aN = host.recorder.data.actions.len
    let hN = host.recorder.data.hashes.len
    if aN != sentActions or hN != sentHashes:
      var deliver = w + oneWay + jitterSpan(jit)
      if deliver <= lastDown: deliver = lastDown + 1
      lastDown = deliver
      down.add DownSlice(deliverAt: deliver, firstTick: uint32(sentHashes + 1),
        actions: host.recorder.data.actions[sentActions ..< aN],
        hashes: host.recorder.data.hashes[sentHashes ..< hN])
      sentActions = aN
      sentHashes = hN

    # 2. Client: deliver due tape slices, advance confirmed.
    var d = 0
    while d < down.len:
      if down[d].deliverAt <= w:
        let msg = decodeNetMessage(packTicks(
          down[d].firstTick, down[d].actions, down[d].hashes))
        doAssert netAppendTicks(client, msg.ticks).len == 0
        down.delete(d)
      else:
        inc d
    while client.world.tick < int32(client.replayPlayer.data.hashes.len):
      tickWorld(client, proc() = discard)

    # 3. Player input: reverse the walk every 16 ticks.
    if w mod 16 == 0:
      let tgt = if (w div 16) mod 2 == 0: A else: B
      let intent = HumanIntent(slot: int32(LocalSeat), kind: IntentWalk,
        a: tgt[0], b: tgt[1])
      pred.record(intent, uint32(client.world.tick) + uint32(lead))
      var arrive = w + oneWay + jitterSpan(jit)
      if arrive <= lastUp: arrive = lastUp + 1
      lastUp = arrive
      up.add UpIntent(arriveAt: arrive, intent: intent)

    # 4. Rebuild prediction and measure the rendered local hero. A frame
    #    jump beyond the walk ceiling is a prediction teleport (the felt
    #    snap); count those and how far past the ceiling they went.
    pred.rebuild(client)
    let render = pred.localRenderPoint()
    if havePrev:
      let jump = dist(render, prevRender)
      result.jumps.add jump
      if jump > SnapThresh:
        inc result.snaps
        result.snapExcess += jump - SnapThresh
    prevRender = render
    havePrev = true

  result.mismatches = client.hashCheck.mismatches

proc p95(xs: seq[float]): float =
  if xs.len == 0: return 0.0
  var s = xs
  s.sort()
  s[min(s.len - 1, int(float(s.len) * 0.95))]

proc jumpMax(xs: seq[float]): float =
  result = 0.0
  for x in xs: result = max(result, x)

const Presets = [
  ("local   0ms", 0, 0),
  ("good  100ms", 100, 20),
  ("poor  250ms", 250, 50),
  ("extreme 500", 500, 120),
]

when isMainModule:
  proc main() =
    startProfileTrace()
    defer:
      finishProfileTrace()
    let lead =
      if paramCount() >= 1: parseInt(paramStr(1)) else: MaxLead
    if paramCount() >= 2:
      setSmoothDecay(parseFloat(paramStr(2)))
      echo &"smoothDecay = {paramStr(2)}"
    echo &"prediction lead = {lead} (MaxLead={MaxLead})"
    echo &"""{"preset":12} {"snaps":>6} {"excess":>7} {"jumpMax":>8} {"mism":>5}"""
    for (name, lat, jit) in Presets:
      # Average over a few seeds so jitter noise does not dominate.
      var snaps = 0
      var excess = 0.0
      var jmax = 0.0
      var mism = 0
      const Seeds = 4
      for s in 0 ..< Seeds:
        let m = runScenario(lat, jit, s, lead)
        snaps += m.snaps
        excess += m.snapExcess
        jmax = max(jmax, jumpMax(m.jumps))
        mism += m.mismatches
      echo &"{name:12} {snaps div Seeds:>6} {excess / float(Seeds):>7.2f} " &
        &"{jmax:>8.3f} {mism:>5}"
  main()
