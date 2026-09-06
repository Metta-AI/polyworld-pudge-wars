## Networked lockstep: wire protocol round-trips and a host + follower
## pair staying hash-exact over an in-memory stream.

import
  std/[os, strutils],
  polyworld/[cli, tapes],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/netclient,
  ../examples/pudge_wars/netproto,
  ../examples/pudge_wars/netsim,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  MatchTicks = 400'i32
  HostSeat = 0
  RemoteSeat = 3

let
  map = generateMap(2026)
  basBotPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"

proc hostGame(): Game =
  ## A hosted match: every seat has autopilot, the host claims one,
  ## and the tape records from tick 1.
  result = newGame(map, MatchTicks, false, ReplayData())
  result.humanSlots.add HostSeat
  loadBots(result, [BotGroup(path: basBotPath, count: PudgeCount)])
  result.recorder = initReplayRecorder(
    currentSetup(result, uint32(MatchTicks))
  )
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc followerGame(setup: Setup): Game =
  ## Mirrors `game.newFollowerGame` without the CLI-bound game module:
  ## the world from the host's setup, an empty streamed tape, playback
  ## locked to it, and no bots.
  let clientMap = generateMap(setup.mapSeed)
  doAssert clientMap.hash == setup.mapHash,
    "the follower must regenerate the host's exact map"
  result = Game(
    world: newWorld(
      clientMap,
      int32(setup.maximumTicks),
      setup.pudges,
      setup.killGoal,
      setup.runePeriod
    ),
    map: clientMap,
    maximumTicks: int32(setup.maximumTicks),
    botEvery: max(setup.botEvery, 1'i32),
    botAimNoise: max(setup.botAimNoise, 0'i32),
    botSpeech: newSeq[BotSpeech](setup.pudges.len),
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup))
  )

proc hostTick(game: Game) =
  tickWorld(game, proc() = runBotDecisions(game))

proc clientCatchUp(game: Game) =
  ## Simulates every tick the streamed tape covers, like the follower's
  ## frame loop does.
  while game.world.tick < int32(game.replayPlayer.data.hashes.len):
    tickWorld(game, proc() = discard)

echo "Testing the wire protocol round-trips every message kind"
block:
  block hello:
    let msg = decodeNetMessage(packHello("Ana", "tok123", 2'i32))
    doAssert msg.kind == NmHello
    doAssert msg.hello.protocol == NetProtocolVersion
    doAssert msg.hello.game == NetGameId
    doAssert msg.hello.simVersion == ReplayGameVersion
    doAssert msg.hello.name == "Ana"
    doAssert msg.hello.token == "tok123"
    doAssert msg.hello.requestSlot == 2
    validateHello(msg.hello)
  block pickSlot:
    let msg = decodeNetMessage(packPickSlot(SpectatorSlot))
    doAssert msg.kind == NmPickSlot
    doAssert msg.pickSlot.slot == SpectatorSlot
  block intent:
    let msg = decodeNetMessage(packIntent(HumanIntent(
      slot: 4'i32, kind: IntentHookFine, a: 12800'i32, b: 16384'i32
    )))
    doAssert msg.kind == NmIntent
    doAssert msg.intent.intent.kind == IntentHookFine
    doAssert msg.intent.intent.a == 12800
  block lobby:
    var seats = newSeq[NetSeat](PudgeCount)
    seats[1] = NetSeat(name: "Bo", human: true, connected: true)
    let msg = decodeNetMessage(packLobby(seats, started = true))
    doAssert msg.kind == NmLobby
    doAssert msg.lobby.started
    doAssert msg.lobby.seats[1].name == "Bo"
    doAssert not msg.lobby.seats[0].human
  block slotGrant:
    let msg = decodeNetMessage(packSlotGrant(3'i32, "tok", ""))
    doAssert msg.kind == NmSlotGrant
    doAssert msg.slotGrant.slot == 3
    doAssert msg.slotGrant.token == "tok"
  block start:
    let host = hostGame()
    let msg = decodeNetMessage(
      packStart(host.recorder.data.header.setup)
    )
    doAssert msg.kind == NmStart
    doAssert msg.start.setup.mapSeed == 2026
    doAssert msg.start.setup.mapHash == map.hash
    doAssert msg.start.setup.pudges.len == PudgeCount
    doAssert msg.start.setup.pudges[HostSeat].controller ==
      ControllerHuman
  block ticks:
    let msg = decodeNetMessage(packTicks(
      7'u32,
      @[ReplayAction(
        tick: 7'u32, pudgeId: 3'i32, kind: ActionWalkTo,
        first: 30'i32, second: 64'i32
      )],
      @[0xDEADBEEF'u64]
    ))
    doAssert msg.kind == NmTicks
    doAssert msg.ticks.firstTick == 7
    doAssert msg.ticks.actions[0].kind == ActionWalkTo
    doAssert msg.ticks.hashes[0] == 0xDEADBEEF'u64
  block intentResult:
    let msg = decodeNetMessage(packIntentResult(IntentResult(
      slot: 2'i32, kind: IntentBuy, accepted: false, tick: 40'i32
    )))
    doAssert msg.kind == NmIntentResult
    doAssert not msg.intentResult.res.accepted
  block bye:
    let msg = decodeNetMessage(packBye("full"))
    doAssert msg.kind == NmBye
    doAssert msg.bye.reason == "full"
  block ping:
    let packed = packPing(1_700_000_000_123'i64)
    let msg = decodeNetMessage(packed)
    doAssert msg.kind == NmPing
    doAssert msg.ping.sentAtUs == 1_700_000_000_123'i64
    let pong = decodeNetMessage(packPong(msg.ping.sentAtUs))
    doAssert pong.kind == NmPong
    doAssert pong.pong.sentAtUs == msg.ping.sentAtUs
    doAssert packed[0] != packHello("x", "", SpectatorSlot)[0]

echo "Testing malformed wire data is rejected without crashing"
block:
  proc rejects(data: string) =
    try:
      discard decodeNetMessage(data)
      doAssert false, "malformed data must raise NetError"
    except NetError:
      discard
  rejects("")
  rejects("\xFF")
  rejects("\x00tiny")
  block wrongGame:
    var hello = decodeNetMessage(
      packHello("Ana", "", SpectatorSlot)
    ).hello
    hello.game = "chess"
    try:
      validateHello(hello)
      doAssert false, "a foreign game must be rejected"
    except NetError:
      discard
  block wrongProtocol:
    var hello = decodeNetMessage(
      packHello("Ana", "", SpectatorSlot)
    ).hello
    hello.protocol = NetProtocolVersion + 1
    try:
      validateHello(hello)
      doAssert false, "a protocol mismatch must be rejected"
    except NetError:
      discard
  block wrongSim:
    var hello = decodeNetMessage(
      packHello("Ana", "", SpectatorSlot)
    ).hello
    hello.simVersion = ReplayGameVersion - 1
    try:
      validateHello(hello)
      doAssert false, "a simulation version mismatch must be rejected"
    except NetError as error:
      doAssert error.msg.contains("simulation version")

echo "Testing a follower stays hash-exact over the streamed tape"
block:
  let host = hostGame()
  # The Start message carries the world-init contract.
  let startMsg = decodeNetMessage(
    packStart(host.recorder.data.header.setup)
  )
  let client = followerGame(startMsg.start.setup)

  var
    sentActions = 0
    sentHashes = 0

  proc streamTail() =
    ## The host's per-frame broadcast: the recorder tail through the
    ## real wire encoding into the real follower append path.
    let
      actionCount = host.recorder.data.actions.len
      hashCount = host.recorder.data.hashes.len
    if actionCount == sentActions and hashCount == sentHashes:
      return
    let wire = packTicks(
      uint32(sentHashes + 1),
      host.recorder.data.actions[sentActions ..< actionCount],
      host.recorder.data.hashes[sentHashes ..< hashCount]
    )
    doAssert wire.len <= MaxNetMessageBytes
    let msg = decodeNetMessage(wire)
    doAssert msg.kind == NmTicks
    let error = netAppendTicks(client, msg.ticks)
    doAssert error.len == 0, error
    sentActions = actionCount
    sentHashes = hashCount

  proc remoteIntent(kind: IntentKind, a = 0'i32, b = 0'i32) =
    ## One command from the remote player, through the wire, with the
    ## server-side seat override hosting applies.
    let msg = decodeNetMessage(packIntent(HumanIntent(
      slot: 99'i32, kind: kind, a: a, b: b
    )))
    var intent = msg.intent.intent
    intent.slot = int32(RemoteSeat)
    queueIntent(host, intent)

  for tick in 1'i32 .. 120'i32:
    case tick
    of 10:
      queueIntent(host, HumanIntent(
        slot: int32(HostSeat), kind: IntentWalk, a: 30'i32, b: 60'i32
      ))
    of 30:
      # A remote player claims a bot seat mid-match. This happens
      # between ticks, so the take-over marker lands on the tape after
      # its tick's hash - exactly the stale-marker case the follower
      # must tolerate.
      doAssert applyTakeOver(host, RemoteSeat, true)
    of 32:
      remoteIntent(IntentWalk, 90'i32, 70'i32)
    of 40:
      remoteIntent(IntentHookFine, fineOfTile(52), fineOfTile(62))
    of 70:
      # The remote player disconnects; autopilot resumes.
      doAssert applyTakeOver(host, RemoteSeat, false)
    else:
      discard
    hostTick(host)
    streamTail()
    clientCatchUp(client)
    doAssert client.world.tick == host.world.tick
    doAssert stateHash(client) == stateHash(host),
      "worlds diverged at tick " & $host.world.tick
  doAssert host.recordingError.len == 0
  doAssert client.hashCheck.mismatches == 0, client.hashCheck.error
  doAssert client.world.pudges[RemoteSeat].hasMoveTarget or
    client.world.pudges[RemoteSeat].hooksThrown > 0,
    "the remote intents must reach the follower's world"

  var hostTakeovers, clientTakeovers = 0
  for action in host.recorder.data.actions:
    if action.kind == ActionTakeOver:
      inc hostTakeovers
  for action in client.replayPlayer.data.actions:
    if action.kind == ActionTakeOver:
      inc clientTakeovers
  doAssert hostTakeovers == 2, "both handoffs land on the host tape"
  doAssert clientTakeovers == 0,
    "stale between-tick markers are dropped from the streamed tape"

echo "Testing a skipped stream slice is refused"
block:
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  for _ in 1 .. 4:
    hostTick(host)
  # Deliver a slice starting at tick 3 to a follower that has nothing.
  let msg = decodeNetMessage(packTicks(
    3'u32,
    @[],
    host.recorder.data.hashes[2 ..< 4]
  ))
  doAssert netAppendTicks(client, msg.ticks).len > 0,
    "a gap in the stream must be reported, not papered over"

echo "Testing a corrupted stream hash trips the desync counter"
block:
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  for _ in 1 .. 6:
    hostTick(host)
  var hashes = host.recorder.data.hashes[0 ..< 6]
  hashes[3] = hashes[3] xor 0xBAD'u64
  let msg = decodeNetMessage(packTicks(
    1'u32, host.recorder.data.actions, hashes
  ))
  doAssert netAppendTicks(client, msg.ticks).len == 0
  clientCatchUp(client)
  doAssert client.hashCheck.mismatches == 1,
    "the follower must notice the divergent tick"
  doAssert client.hashCheck.firstTick == 4

echo "Testing tick slices chunk a long backlog without reordering"
block:
  var hashes = newSeq[uint64](300)
  for i in 0 ..< hashes.len:
    hashes[i] = uint64(i + 1)
  let actions = @[
    ReplayAction(
      tick: 10'u32, pudgeId: 1'i32, kind: ActionWalkTo,
      first: 30'i32, second: 64'i32
    ),
    ReplayAction(
      tick: 301'u32, pudgeId: 1'i32, kind: ActionTakeOver
    )
  ]
  doAssert packTickSlices(1'u32, @[], @[]).len == 0
  let slices = packTickSlices(1'u32, actions, hashes, hashChunk = 256)
  doAssert slices.len == 2, $slices.len
  let first = decodeNetMessage(slices[0])
  let second = decodeNetMessage(slices[1])
  doAssert first.kind == NmTicks
  doAssert second.kind == NmTicks
  doAssert first.ticks.firstTick == 1
  doAssert first.ticks.hashes.len == 256
  doAssert first.ticks.actions.len == 1
  doAssert first.ticks.actions[0].tick == 10
  doAssert second.ticks.firstTick == 257
  doAssert second.ticks.hashes.len == 44
  doAssert second.ticks.actions.len == 1
  doAssert second.ticks.actions[0].kind == ActionTakeOver

echo "Testing reconnect backoff is never negative"
block:
  doAssert netTestBackoff(-3) >= 0
  doAssert netTestBackoff(0) == 0.0
  doAssert netTestBackoff(1) > 0
  doAssert netTestBackoff(100) >= 0

echo "Testing lockstep stays hash-exact through 0 / 100 / 250 / 500 ms delay"
block:
  ## The host ticks at a fixed 32 Hz. Tape slices sit in the inbound
  ## delay queue and the follower applies them only when due — latency
  ## must not change tick rate, desync the hashes, or grow the queue
  ## without bound.
  const TickUs = 1_000_000'i64 div int64(TickRate)
  const RunTicks = 80'i32
  for (lat, jit) in [(0, 0), (100, 0), (250, 50), (500, 120)]:
    netSimReset()
    netSimSeed(1)
    netSimConfigure(NetSimConfig(
      enabled: true, latencyMs: lat, jitterMs: jit, packetLossPercent: 0.0,
      delayOutbound: true, delayInbound: true))
    let host = hostGame()
    let client = followerGame(host.recorder.data.header.setup)
    var
      sentActions = 0
      sentHashes = 0
    proc offerTail(nowUs: int64) =
      let
        actionCount = host.recorder.data.actions.len
        hashCount = host.recorder.data.hashes.len
      if actionCount == sentActions and hashCount == sentHashes:
        return
      let wire = packTicks(
        uint32(sentHashes + 1),
        host.recorder.data.actions[sentActions ..< actionCount],
        host.recorder.data.hashes[sentHashes ..< hashCount]
      )
      doAssert netSimOffer(DirInbound, wire, nowUs)
      sentActions = actionCount
      sentHashes = hashCount
    proc drainDue(nowUs: int64) =
      for data in netSimDue(DirInbound, nowUs):
        let msg = decodeNetMessage(data)
        doAssert msg.kind == NmTicks
        let error = netAppendTicks(client, msg.ticks)
        doAssert error.len == 0, error
      clientCatchUp(client)
    for tick in 1'i32 .. RunTicks:
      if tick == 10:
        queueIntent(host, HumanIntent(
          slot: int32(HostSeat), kind: IntentWalk, a: 30'i32, b: 60'i32
        ))
      hostTick(host)
      let now = int64(tick) * TickUs
      offerTail(now)
      drainDue(now)
      doAssert client.world.tick <= host.world.tick
      doAssert netSimQueueDepth(DirInbound) < 64,
        "queue grew under " & $lat & " ms: " & $netSimQueueDepth(DirInbound)
      if lat == 0:
        doAssert client.world.tick == host.world.tick,
          "0 ms must stay in lockstep every tick"
    if lat == 100:
      doAssert client.world.tick < host.world.tick,
        "100 ms one-way must leave the follower behind before the drain"
    drainDue(int64(RunTicks) * TickUs + 2_000_000'i64)
    doAssert client.world.tick == host.world.tick, $lat & " ms: ticks " &
      $client.world.tick & " vs " & $host.world.tick
    doAssert stateHash(client) == stateHash(host),
      $lat & " ms: worlds diverged after drain"
    doAssert client.hashCheck.mismatches == 0, client.hashCheck.error
    doAssert netSimQueueDepth(DirInbound) == 0
    doAssert netSimStats(DirInbound).dropped == 0
  netSimEnable(false)
  netSimReset()

echo "Testing a dropped socket reconnects with the same seat token"
block:
  netTestReset()
  let host = hostGame()
  let setup = host.recorder.data.header.setup
  let client = followerGame(setup)
  netTestInstallPlaying("ws://test/ws", "Ana", "tok", 0'i32)
  doAssert netClientPhase() == NcPlaying
  netTestCloseSocket()
  discard netClientPump(client)
  doAssert netClientPhase() == NcReconnecting, $netClientPhase()
  doAssert netStatusLine().startsWith("RECONNECTING")
  discard netClientPump(client)
  doAssert netClientPhase() == NcLobby
  netTestPush(packSlotGrant(0'i32, "tok", ""))
  netTestPush(packStart(setup))
  let events = netClientPump(client)
  doAssert events.restarted, "reconnect Start must rebuild the follower world"
  doAssert netClientPhase() == NcPlaying
  doAssert netClientSeat() == 0
  doAssert netTestReconnectAttempt() == 0
  netTestReset()

echo "Testing NmBye is terminal and does not reconnect"
block:
  netTestReset()
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  netTestInstallPlaying("ws://test/ws", "Ana", "tok", 0'i32)
  netTestPush(packBye("match over"))
  discard netClientPump(client)
  doAssert netClientPhase() == NcDropped
  doAssert netClientError().startsWith("HOST:")
  netTestCloseSocket()
  discard netClientPump(client)
  doAssert netClientPhase() == NcDropped, "Bye must not start a reconnect"
  netTestReset()

echo "Testing reconnect gives up after the attempt cap"
block:
  netTestReset()
  let host = hostGame()
  let client = followerGame(host.recorder.data.header.setup)
  netTestInstallPlaying("ws://test/ws", "Ana", "tok", 0'i32)
  for _ in 1 .. 50:
    if netClientPhase() == NcDropped:
      break
    if netClientPhase() in {NcPlaying, NcLobby}:
      netTestCloseSocket()
    discard netClientPump(client)
  doAssert netClientPhase() == NcDropped
  doAssert netClientError().len > 0
  netTestReset()

echo "test_pw_net: all checks passed"
