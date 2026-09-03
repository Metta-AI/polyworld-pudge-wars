## Pudge Wars network client: transport and the follower session.
##
## A client never simulates ahead: it sends its seat's intents to the
## host and applies the streamed action tape, verifying the host's hash
## for every tick. The module owns the socket and the connection state;
## `game.nim` calls `netBootstrap` before the world exists and the
## graphics loop calls `netClientPump` every frame after that.
##
## Native builds use whisky (a blocking WebSocket) on one receive
## thread feeding a locked queue. The Emscripten build uses the
## browser's WebSocket through emscripten/websocket.h; its callbacks
## run on the main thread between ASYNCIFY yields, so the same queue
## works without a thread.

import
  std/[locks, strutils, times],
  content, netproto, netsim, replays, sim

type
  NetClientPhase* = enum
    NcOffline,
    NcLobby,        ## Connected; waiting for the host to start.
    NcPlaying,      ## Following the live tape.
    NcReconnecting, ## Socket died; retrying with the same seat token.
    NcDropped,      ## Connection lost or refused.
    NcDesynced      ## A tick hash disagreed with the host.

  NetClientEvents* = object
    ## What one frame's pump wants the graphics loop to do.
    restarted*: bool
      ## A fresh `Start` arrived mid-session (host rematch); rebuild
      ## the world from `setup` and pump again next frame.
    setup*: Setup

var
  clientLock: Lock
  recvQueue: seq[string]
    ## Binary payloads the receive thread hands to the game thread.
  recvClosed = false
  clientPhase = NcOffline
  clientErrorText = ""
  clientSeat = -1
    ## Seat this client drives, or -1 while spectating.
  clientToken = ""
  seatNames: array[PudgeCount, string]
  seatHumans: array[PudgeCount, bool]
  pendingMessages: seq[string]
    ## Decoded-order buffer; a mid-batch `Start` leaves the remainder
    ## here for the rebuilt world.

initLock(clientLock)

const
  PingIntervalSec = 1.0
    ## How often a follower probes the host. One outstanding ping at a time.
  PingTimeoutSec = 4.0
  PingSampleCap = 8
  ReconnectMaxAttempts = 20
    ## Give up after this many retries (~2 min with the backoff below).
  ReconnectBackoffSec = [0.0, 0.5, 1.0, 2.0, 4.0, 8.0]

var
  sessionUrl = ""
  sessionName = ""
  sessionToken = ""
  sessionSlot = SpectatorSlot
    ## Credentials from bootstrap; a reconnect Hello reuses them.
  reconnectAttempt = 0
  reconnectAt = 0.0
  reconnectConnectStarted = false
  skipTransport = false
    ## Tests drive the reconnect state machine without a real socket.

var
  pingAwaiting = false
  pingSentAtUs = 0'i64
  pingSentAt = 0.0
  lastPingMs = -1
    ## Latest client→host RTT in milliseconds, or -1 before the first pong.
  lastJitterMs = 0
  pingRing: array[PingSampleCap, float32]
  pingRingLen = 0
  pingRingAt = 0

const PingHistoryCap* = 96
  ## Rolling window of measured pings for the debug panel's graph.
var
  pingHistory: array[PingHistoryCap, int]
  pingHistoryLen = 0
  pingHistoryAt = 0

proc unixMicros(): int64 =
  int64(epochTime() * 1_000_000.0)

proc resetPingStats() =
  pingAwaiting = false
  pingSentAtUs = 0
  pingSentAt = 0.0
  lastPingMs = -1
  lastJitterMs = 0
  pingRingLen = 0
  pingRingAt = 0
  pingHistoryLen = 0
  pingHistoryAt = 0

proc netPingMs*(): int =
  ## Latest client→host RTT in milliseconds, or -1 if none yet.
  lastPingMs

proc netPingJitterMs*(): int =
  ## Mean absolute deviation of recent RTTs in milliseconds.
  lastJitterMs

proc netPingKnown*(): bool =
  lastPingMs >= 0

proc netPingHistory*(): seq[int] =
  ## Measured pings oldest-to-newest for the debug panel's rolling graph.
  result = newSeqOfCap[int](pingHistoryLen)
  let start = (pingHistoryAt - pingHistoryLen + PingHistoryCap) mod PingHistoryCap
  for i in 0 ..< pingHistoryLen:
    result.add pingHistory[(start + i) mod PingHistoryCap]

proc pushPingSample(ms: float32) =
  pingRing[pingRingAt] = ms
  pingRingAt = (pingRingAt + 1) mod PingSampleCap
  if pingRingLen < PingSampleCap:
    inc pingRingLen
  lastPingMs = max(int(ms + 0.5'f32), 0)
  pingHistory[pingHistoryAt] = lastPingMs
  pingHistoryAt = (pingHistoryAt + 1) mod PingHistoryCap
  if pingHistoryLen < PingHistoryCap:
    inc pingHistoryLen
  if pingRingLen < 2:
    lastJitterMs = 0
    return
  var sum = 0.0
  for i in 0 ..< pingRingLen:
    sum += pingRing[i]
  let mean = sum / float(pingRingLen)
  var mad = 0.0
  for i in 0 ..< pingRingLen:
    mad += abs(pingRing[i] - mean)
  lastJitterMs = int(mad / float(pingRingLen) + 0.5)

proc notePong(sentAtUs: int64) =
  if not pingAwaiting or sentAtUs != pingSentAtUs:
    return
  pingAwaiting = false
  let rttMs = float(unixMicros() - sentAtUs) / 1000.0
  if rttMs < 0 or rttMs > 60_000:
    return
  pushPingSample(float32(rttMs))

# --- transport backends -------------------------------------------------

when defined(emscripten):
  # The browser's WebSocket via emscripten/websocket.h (-lwebsocket.js).
  # Callbacks fire on the main thread whenever ASYNCIFY yields control
  # to the browser event loop - which `netSleep` and the frame loop do.
  const WsHeader = "<emscripten/websocket.h>"

  type
    WsCreateAttributes {.
      importc: "EmscriptenWebSocketCreateAttributes", header: WsHeader
    .} = object
      url: cstring
      protocols: cstring
      createOnMainThread: bool

    # The callbacks in emscripten/websocket.h take `const Event*`
    # pointers; importing the structs as const keeps the generated C
    # signatures compatible (clang rejects the mismatch since llvm 16).
    WsOpenEvent {.
      importc: "const EmscriptenWebSocketOpenEvent", header: WsHeader
    .} = object
      socket: cint

    WsMessageEvent {.
      importc: "const EmscriptenWebSocketMessageEvent", header: WsHeader
    .} = object
      socket: cint
      data: ptr UncheckedArray[uint8]
      numBytes: uint32
      isText: bool

    WsCloseEvent {.
      importc: "const EmscriptenWebSocketCloseEvent", header: WsHeader
    .} = object
      socket: cint

    WsErrorEvent {.
      importc: "const EmscriptenWebSocketErrorEvent", header: WsHeader
    .} = object
      socket: cint

  proc emscripten_websocket_is_supported(): bool
    {.importc, header: WsHeader.}
  proc emscripten_websocket_new(
    attributes: ptr WsCreateAttributes
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_send_binary(
    socket: cint, data: pointer, dataLength: uint32
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_close(
    socket: cint, code: cushort, reason: cstring
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_set_onopen_callback(
    socket: cint,
    userData: pointer,
    callback: proc(
      eventType: cint, event: ptr WsOpenEvent, userData: pointer
    ): bool {.cdecl.}
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_set_onmessage_callback(
    socket: cint,
    userData: pointer,
    callback: proc(
      eventType: cint, event: ptr WsMessageEvent, userData: pointer
    ): bool {.cdecl.}
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_set_onclose_callback(
    socket: cint,
    userData: pointer,
    callback: proc(
      eventType: cint, event: ptr WsCloseEvent, userData: pointer
    ): bool {.cdecl.}
  ): cint {.importc, header: WsHeader.}
  proc emscripten_websocket_set_onerror_callback(
    socket: cint,
    userData: pointer,
    callback: proc(
      eventType: cint, event: ptr WsErrorEvent, userData: pointer
    ): bool {.cdecl.}
  ): cint {.importc, header: WsHeader.}
  proc emscripten_sleep(milliseconds: cuint)
    {.importc, header: "<emscripten.h>".}

  var
    wsSocket = 0.cint
    wsConnected = false

  proc onWsOpen(
      eventType: cint, event: ptr WsOpenEvent, userData: pointer
  ): bool {.cdecl.} =
    {.gcsafe.}:
      if event.socket == wsSocket:
        wsConnected = true
    true

  proc onWsMessage(
      eventType: cint, event: ptr WsMessageEvent, userData: pointer
  ): bool {.cdecl.} =
    {.gcsafe.}:
      if event.socket != wsSocket:
        return true
      if not event.isText and event.numBytes > 0:
        var payload = newString(int(event.numBytes))
        copyMem(addr payload[0], addr event.data[0], int(event.numBytes))
        withLock clientLock:
          recvQueue.add payload
    true

  proc onWsClose(
      eventType: cint, event: ptr WsCloseEvent, userData: pointer
  ): bool {.cdecl.} =
    {.gcsafe.}:
      if event.socket != wsSocket:
        return true
      withLock clientLock:
        recvClosed = true
    true

  proc onWsError(
      eventType: cint, event: ptr WsErrorEvent, userData: pointer
  ): bool {.cdecl.} =
    {.gcsafe.}:
      if event.socket != wsSocket:
        return true
      withLock clientLock:
        recvClosed = true
    true

  proc netSleep(milliseconds: int) =
    ## Yields to the browser event loop so socket callbacks can fire.
    emscripten_sleep(cuint(max(milliseconds, 1)))

  proc transportClose() =
    if wsSocket > 0:
      let old = wsSocket
      wsSocket = 0
      wsConnected = false
      discard emscripten_websocket_close(old, 1000, "bye")

  proc transportStart(url: string): string =
    ## Begins a WebSocket handshake. Does not wait; poll `transportIsOpen`
    ## / `transportFailed` from the frame loop so reconnect cannot stall
    ## rendering.
    if not emscripten_websocket_is_supported():
      return "this browser has no WebSocket support"
    transportClose()
    withLock clientLock:
      recvClosed = false
      recvQueue.setLen(0)
    wsConnected = false
    var attributes = WsCreateAttributes(
      url: cstring(url),
      protocols: nil,
      createOnMainThread: true
    )
    wsSocket = emscripten_websocket_new(addr attributes)
    if wsSocket <= 0:
      wsSocket = 0
      return "cannot open a WebSocket to " & url
    discard emscripten_websocket_set_onopen_callback(wsSocket, nil, onWsOpen)
    discard emscripten_websocket_set_onmessage_callback(
      wsSocket, nil, onWsMessage
    )
    discard emscripten_websocket_set_onclose_callback(wsSocket, nil, onWsClose)
    discard emscripten_websocket_set_onerror_callback(wsSocket, nil, onWsError)
    ""

  proc transportIsOpen(): bool =
    wsConnected

  proc transportFailed(): bool =
    var closed = false
    withLock clientLock:
      closed = recvClosed
    closed and not wsConnected

  proc transportConnect(url: string): string =
    ## Opens the socket and waits for the browser to finish the
    ## handshake; returns an error message, or empty on success.
    let startError = transportStart(url)
    if startError.len > 0:
      return startError
    for _ in 0 ..< 1000:
      if transportIsOpen():
        return ""
      if transportFailed():
        return "cannot reach " & url
      netSleep(10)
    "timed out connecting to " & url

  proc rawTransportSend(data: string) =
    if wsSocket <= 0 or data.len == 0:
      return
    discard emscripten_websocket_send_binary(
      wsSocket, unsafeAddr data[0], uint32(data.len)
    )
else:
  import std/os
  import whisky

  var
    clientWs: whisky.WebSocket
    sendLock: Lock
    recvThread: Thread[void]
    recvThreadLive = false

  initLock(sendLock)

  proc recvLoop() {.thread.} =
    ## Blocks on the socket forever; whisky raises when it closes.
    {.gcsafe.}:
      try:
        while true:
          let received = clientWs.receiveMessage(-1)
          if received.isNone:
            continue
          let message = received.get()
          case message.kind
          of whisky.BinaryMessage:
            withLock clientLock:
              recvQueue.add message.data
          of whisky.Ping:
            withLock sendLock:
              clientWs.send(message.data, whisky.Pong)
          else:
            discard
      except CatchableError:
        discard
      withLock clientLock:
        recvClosed = true

  proc transportClose() =
    if clientWs != nil:
      try:
        clientWs.close()
      except CatchableError:
        discard
    if recvThreadLive:
      joinThread(recvThread)
      recvThreadLive = false
    clientWs = nil

  proc transportStart(url: string): string =
    transportClose()
    withLock clientLock:
      recvClosed = false
      recvQueue.setLen(0)
    try:
      clientWs = newWebSocket(url)
    except CatchableError as error:
      return "cannot reach " & url & ": " & error.msg
    createThread(recvThread, recvLoop)
    recvThreadLive = true
    ""

  proc transportIsOpen(): bool =
    if clientWs == nil:
      return false
    var closed = false
    withLock clientLock:
      closed = recvClosed
    not closed

  proc transportFailed(): bool =
    var closed = false
    withLock clientLock:
      closed = recvClosed
    closed or clientWs == nil

  proc transportConnect(url: string): string =
    ## Returns an error message, or empty on success.
    transportStart(url)

  proc rawTransportSend(data: string) =
    if clientWs == nil:
      return
    try:
      withLock sendLock:
        clientWs.send(data, whisky.BinaryMessage)
    except CatchableError:
      withLock clientLock:
        recvClosed = true

  proc netSleep(milliseconds: int) =
    sleep(milliseconds)

# --- network-condition simulator seam -----------------------------------
# Outbound packets go through the sim's delay/jitter/loss when it is active;
# otherwise straight to the raw transport (bit-for-bit unsimulated). Inbound
# is intercepted in `takeReceived`. The sim is only ever touched on the game
# thread (the recvQueue lock is the thread boundary), so it needs no lock.

proc transportSend(data: string) =
  if data.len == 0:
    return
  if netSimActive(DirOutbound):
    discard netSimOffer(DirOutbound, data, unixMicros())
  else:
    rawTransportSend(data)

proc pumpOutbound() =
  ## Releases outbound packets whose simulated delay has elapsed.
  if netSimActive(DirOutbound):
    for data in netSimDue(DirOutbound, unixMicros()):
      rawTransportSend(data)

# --- session state ------------------------------------------------------

proc netFollowing*(): bool =
  ## Whether this process is a remote client following a host.
  clientPhase in {NcLobby, NcPlaying, NcReconnecting}

proc netClientPhase*(): NetClientPhase =
  clientPhase

proc netClientSeat*(): int =
  clientSeat

proc netClientError*(): string =
  clientErrorText

proc netSeatName*(slot: int): string =
  ## The lobby name behind one seat, or empty for a bot.
  if slot >= 0 and slot < PudgeCount:
    result = seatNames[slot]

proc netDrop(reason: string) =
  if clientPhase in {NcDropped, NcDesynced}:
    return
  clientPhase = NcDropped
  clientErrorText = reason
  resetPingStats()
  transportClose()

proc reconnectBackoff(attempt: int): float =
  ## attempt is 0-based. Never negative.
  var i = attempt
  if i < 0: i = 0
  if i > ReconnectBackoffSec.high: i = ReconnectBackoffSec.high
  result = ReconnectBackoffSec[i]
  if result < 0: result = 0

proc rememberSession(url, name, token: string, requestSlot: int32) =
  sessionUrl = url
  sessionName = name
  sessionToken = token
  sessionSlot = requestSlot

proc clearInbound() =
  pendingMessages.setLen(0)
  withLock clientLock:
    recvQueue.setLen(0)
    recvClosed = false
  netSimReset()
  resetPingStats()

proc giveUpReconnect() =
  when defined(emscripten):
    netDrop("CONNECTION TO HOST LOST - RELOAD THE PAGE TO REJOIN")
  else:
    netDrop("CONNECTION TO HOST LOST")

proc beginReconnect(reason: string) =
  ## Closes the dead socket and schedules another Hello with the same
  ## seat token. The host already treats a second Hello as a take-over
  ## (`bindGameSeat`) and streams Start + the tape backlog.
  if clientPhase in {NcDropped, NcDesynced}:
    return
  if sessionUrl.len == 0:
    giveUpReconnect()
    return
  let nextAttempt = reconnectAttempt + 1
  if nextAttempt > ReconnectMaxAttempts:
    echo "net: giving up after ", ReconnectMaxAttempts, " reconnects"
    giveUpReconnect()
    return
  transportClose()
  clearInbound()
  reconnectConnectStarted = false
  reconnectAttempt = nextAttempt
  clientPhase = NcReconnecting
  let delay =
    if skipTransport: 0.0
    else: reconnectBackoff(nextAttempt - 1)
  reconnectAt = epochTime() + delay
  clientErrorText = "RECONNECTING TO HOST (" & $reconnectAttempt &
    "/" & $ReconnectMaxAttempts & ")…"
  echo "net: ", reason, " — reconnect ", reconnectAttempt, "/",
    ReconnectMaxAttempts, " in ", delay, "s"

proc tickReconnect() =
  if clientPhase != NcReconnecting:
    return
  if epochTime() < reconnectAt:
    return
  if skipTransport:
    # Tests: skip the socket and sit in NcLobby waiting for injected
    # Start / SlotGrant, the same messages a real host sends on Hello.
    reconnectConnectStarted = true
    clientPhase = NcLobby
    return
  if not reconnectConnectStarted:
    let err = transportStart(sessionUrl)
    if err.len > 0:
      echo "net: reconnect failed: ", err
      beginReconnect("connect failed")
      return
    reconnectConnectStarted = true
  if transportIsOpen():
    transportSend(packHello(sessionName, sessionToken, sessionSlot))
    clientPhase = NcLobby
    echo "net: socket up, hello sent"
  elif transportFailed():
    beginReconnect("handshake failed")

proc netReportDesync*(tick: int32) =
  ## The follower's hash disagreed with the host: the worlds diverged
  ## and there is no rollback, so freeze and say so.
  if clientPhase == NcDesynced:
    return
  clientPhase = NcDesynced
  clientErrorText = "DESYNC AT TICK " & $tick & " - OUT OF SYNC WITH HOST"
  transportClose()

proc netQueueIntent*(intent: HumanIntent, wantedTick: uint32 = 0) =
  ## The remote seat's `queueIntent`: straight to the host. `wantedTick`
  ## is the prediction-world tick the client applied this command at, so
  ## the host can log timing misses and the client can reconcile its
  ## prediction against the tape. Zero means "apply on the host's tick".
  if clientPhase != NcPlaying or clientSeat < 0:
    return
  var owned = intent
  owned.slot = int32(clientSeat)
  transportSend(packIntent(owned, wantedTick))

proc tickNetPing() =
  ## Sends one outstanding RTT probe while the socket is up.
  if clientPhase notin {NcLobby, NcPlaying}:
    return
  let now = epochTime()
  if pingAwaiting and now - pingSentAt > PingTimeoutSec:
    pingAwaiting = false
  if pingAwaiting:
    return
  if pingSentAt > 0.0 and now - pingSentAt < PingIntervalSec:
    return
  let stamped = unixMicros()
  pingSentAtUs = stamped
  pingSentAt = now
  pingAwaiting = true
  transportSend(packPing(stamped))

proc takeReceived() =
  ## Moves socket payloads into the ordered pending buffer, releasing any
  ## due outbound packets and applying the inbound network sim on the way.
  pumpOutbound()
  var batch: seq[string]
  withLock clientLock:
    if recvQueue.len > 0:
      batch = recvQueue
      recvQueue.setLen(0)
  if netSimActive(DirInbound):
    let now = unixMicros()
    for data in batch:
      discard netSimOffer(DirInbound, data, now)
    for data in netSimDue(DirInbound, now):
      pendingMessages.add data
  else:
    for data in batch:
      pendingMessages.add data

proc applyLobby(lobby: LobbyMsg) =
  for i in 0 ..< PudgeCount:
    if i < lobby.seats.len:
      seatNames[i] = lobby.seats[i].name
      seatHumans[i] = lobby.seats[i].human
    else:
      seatNames[i] = ""
      seatHumans[i] = false

proc syncHumanSlots(game: Game) =
  ## Mirrors the lobby's human seats into the local game for the HUD
  ## and bot speech bubbles. Display only: the follower sim takes every
  ## action from the tape.
  game.humanSlots.setLen(0)
  for i in 0 ..< PudgeCount:
    if seatHumans[i]:
      game.humanSlots.add i

proc netAppendTicks*(game: Game, ticks: TicksMsg): string =
  ## Appends one streamed tape slice to the follower's replay player;
  ## returns an error description when the stream skips or overflows.
  ## Exported for the lockstep sync tests.
  if ticks.hashes.len == 0 and ticks.actions.len == 0:
    return ""
  let expected = uint32(game.replayPlayer.data.hashes.len) + 1'u32
  if ticks.firstTick != expected:
    return "tape stream skipped from tick " & $expected &
      " to " & $ticks.firstTick
  if game.replayPlayer.data.hashes.len + ticks.hashes.len >
      MaxReplayHashes:
    return "tape stream exceeds the hash limit"
  if game.replayPlayer.data.actions.len + ticks.actions.len >
      MaxReplayActions:
    return "tape stream exceeds the action limit"
  for hash in ticks.hashes:
    game.replayPlayer.data.hashes.add hash
  for action in ticks.actions:
    if action.tick <= uint32(game.world.tick):
      # Take-over markers are recorded between host ticks, after their
      # tick's hash. That tick already ran here and the marker changes
      # no state, so it is safe to drop from the streamed tape; keeping
      # it would strand the action cursor behind the simulation.
      continue
    if game.replayPlayer.data.actions.len > 0 and
        action.tick < game.replayPlayer.data.actions[^1].tick:
      return "tape stream actions move backward"
    game.replayPlayer.data.actions.add action
  ""

proc netClientPump*(game: Game): NetClientEvents =
  ## One frame of network intake on the game thread: tape slices into
  ## the replay player, acknowledgments into the HUD feed, roster
  ## updates, rematch starts, reconnect, and connection loss.
  if not netFollowing():
    return
  if clientPhase == NcReconnecting:
    tickReconnect()
    if clientPhase == NcReconnecting:
      return
  takeReceived()
  var index = 0
  while index < pendingMessages.len:
    var message: NetMessage
    try:
      message = decodeNetMessage(pendingMessages[index])
    except NetError as error:
      netDrop("bad host message: " & error.msg)
      break
    inc index
    case message.kind
    of NmLobby:
      applyLobby(message.lobby)
      syncHumanSlots(game)
    of NmSlotGrant:
      if message.slotGrant.reason.len > 0:
        if reconnectAttempt > 0:
          netDrop("HOST: " & message.slotGrant.reason)
        else:
          clientSeat = -1
          clientErrorText = message.slotGrant.reason.toUpperAscii()
      else:
        clientSeat = int(message.slotGrant.slot)
        clientToken = message.slotGrant.token
        if message.slotGrant.token.len > 0:
          sessionToken = message.slotGrant.token
    of NmTicks:
      let error = netAppendTicks(game, message.ticks)
      if error.len > 0:
        netDrop(error)
    of NmIntentResult:
      if game.intentResults.len < 64:
        game.intentResults.add message.intentResult.res
    of NmStart:
      # A rematch or a reconnect catch-up: hand the fresh setup up and
      # keep the rest of the batch (its ticks belong to the new world)
      # for after the rebuild.
      result.restarted = true
      result.setup = message.start.setup
      clientPhase = NcPlaying
      reconnectAttempt = 0
      clientErrorText = ""
      break
    of NmPong:
      notePong(message.pong.sentAtUs)
    of NmBye:
      netDrop("HOST: " & message.bye.reason)
    else:
      discard
  if index > 0:
    pendingMessages = pendingMessages[index .. ^1]
  if clientPhase in {NcLobby, NcPlaying}:
    tickNetPing()
    var closed = false
    withLock clientLock:
      closed = recvClosed
    if closed:
      beginReconnect("connection to host lost")

proc netStatusLine*(): string =
  ## One HUD line describing the connection, or empty when healthy.
  case clientPhase
  of NcDropped, NcDesynced, NcReconnecting:
    clientErrorText.toUpperAscii()
  else:
    ""

proc netBootstrap*(
    url, name, token: string,
    requestSlot: int32
): tuple[ok: bool, error: string, setup: Setup] =
  ## Connects, claims a seat, and blocks until the host starts the
  ## match. The tape backlog then flows through `netClientPump` like
  ## any live slice. Runs before the window exists; progress goes to
  ## the console.
  rememberSession(url, name, token, requestSlot)
  reconnectAttempt = 0
  let connectError = transportConnect(url)
  if connectError.len > 0:
    return (false, connectError, Setup())
  netSimReset()  # no stale delayed packets from a prior connection
  clientPhase = NcLobby
  transportSend(packHello(name, token, requestSlot))
  echo "join: connected to ", url
  var
    lastWord = epochTime()
    announced = false
    heardHost = false
  let connectedAt = epochTime()
  while true:
    takeReceived()
    var index = 0
    var started = false
    if pendingMessages.len > 0:
      heardHost = true
    while index < pendingMessages.len:
      var message: NetMessage
      try:
        message = decodeNetMessage(pendingMessages[index])
      except NetError as error:
        return (false, "bad host message: " & error.msg, Setup())
      inc index
      case message.kind
      of NmSlotGrant:
        if message.slotGrant.reason.len > 0:
          echo "join: seat denied - ", message.slotGrant.reason,
            " (spectating; pick a seat from the lobby page)"
          clientSeat = -1
        else:
          clientSeat = int(message.slotGrant.slot)
          clientToken = message.slotGrant.token
          if clientSeat >= 0:
            echo "join: playing seat ", clientSeat + 1
          else:
            echo "join: spectating"
      of NmLobby:
        applyLobby(message.lobby)
        if not announced:
          announced = true
          var claimed = 0
          for human in seatHumans:
            if human:
              inc claimed
          echo "join: lobby open, ", claimed, "/", PudgeCount,
            " seats claimed - waiting for the host to start"
      of NmStart:
        result = (true, "", message.start.setup)
        started = true
        break
      of NmBye:
        return (false, "host: " & message.bye.reason, Setup())
      of NmPong:
        notePong(message.pong.sentAtUs)
      else:
        discard
    if index > 0:
      pendingMessages = pendingMessages[index .. ^1]
    if started:
      clientPhase = NcPlaying
      return
    var closed = false
    withLock clientLock:
      closed = recvClosed
    if closed:
      return (false, "connection to host lost", Setup())
    if not heardHost and epochTime() - connectedAt > 10.0:
      # A healthy host answers a hello within milliseconds. Silence
      # means its game loop is stalled (hidden window, sleeping Mac).
      return (
        false,
        "the host accepted the connection but never answered - " &
        "its game window may be stalled or the machine asleep",
        Setup()
      )
    if epochTime() - lastWord > 15.0:
      lastWord = epochTime()
      echo "join: still waiting for the host to start..."
    tickNetPing()
    netSleep(15)

proc netShutdown*() =
  ## Closes the socket on process exit.
  if clientPhase != NcOffline:
    transportClose()
    clientPhase = NcOffline
    reconnectAttempt = 0
    resetPingStats()

proc netTestReset*() =
  ## Returns the client to NcOffline. For automated tests only.
  pendingMessages.setLen(0)
  withLock clientLock:
    recvQueue.setLen(0)
    recvClosed = false
  clientPhase = NcOffline
  clientErrorText = ""
  clientSeat = -1
  clientToken = ""
  sessionUrl = ""
  sessionName = ""
  sessionToken = ""
  sessionSlot = SpectatorSlot
  reconnectAttempt = 0
  reconnectAt = 0.0
  reconnectConnectStarted = false
  skipTransport = false
  resetPingStats()
  netSimReset()
  netSimEnable(false)

proc netTestInstallPlaying*(url, name, token: string, slot: int32) =
  ## Pretend the follower is in a live match with these credentials.
  rememberSession(url, name, token, slot)
  clientPhase = NcPlaying
  clientSeat = int(slot)
  clientToken = token
  skipTransport = true
  reconnectAttempt = 0
  clientErrorText = ""

proc netTestCloseSocket*() =
  withLock clientLock:
    recvClosed = true

proc netTestPush*(data: string) =
  withLock clientLock:
    recvQueue.add data

proc netTestReconnectAttempt*(): int =
  reconnectAttempt

proc netTestBackoff*(attempt: int): float =
  reconnectBackoff(attempt)
