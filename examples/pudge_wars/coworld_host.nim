## Coworld game host: native Pudge Wars sim, JSON player sockets, .pwr tape.
##
## The 32 Hz clock lives here. League policies speak walk_to / hook_to JSON;
## those become human intents on the same record-then-apply path as ./pw.

import
  std/[
    httpclient, json, locks, math, monotimes, os, sequtils, strutils, tables,
    times, uri
  ],
  mummy, mummy/routers,
  polyworld/pathing,
  content, maps, sim, bots, replays, fog, netproto

const
  PlayerHtml = staticRead("coworld_player.html")
  GlobalHtml = staticRead("coworld_global.html")
  ArenaJs = staticRead("coworld_arena.js")
  UserAgent = "coworld-pudgewars/0.3"
  HttpTimeoutMs = 60_000

type
  SessionKind = enum
    SkPlayer,   ## JSON policy pod on /player (cluster-internal).
    SkGlobal,   ## 2D spectator overlay on /global.
    SkGame      ## Binary netproto WASM human on /ws.

  Session = object
    kind: SessionKind
    slot: int
    name: string
    started: bool
      ## This game connection has the current Start and its backlog.
    sentActions: int
      ## Tape actions already streamed to this game connection.
    sentHashes: int
      ## Tape hashes already streamed to this game connection.

  InKind = enum
    InOpen,
    InMessage,
    InClose

  Inbound = object
    kind: InKind
    ws: WebSocket
    text: string
    binary: bool
      ## A netproto game frame (not JSON); routed to the /ws decoder.

var
  inboundLock: Lock
  inbound: seq[Inbound]
  sessionLock: Lock
  sessions: Table[WebSocket, Session]
  playerSockets: seq[WebSocket]
  playerConnected: seq[bool]
  gameSockets: seq[WebSocket]
    ## Per-seat WASM human connection, or nil. Parallel to playerSockets.
  gameConnected: seq[bool]
    ## Whether a WASM human currently drives each seat over netproto.
  globalSockets: seq[WebSocket]
  hostServer: Server
  game: Game
  tokens: seq[string]
  playerNames: seq[string]
  maxTicks: int32
  killGoal: int32
  seed: int32
  fogOn = true
  connectTimeoutSec = 180.0
  resultsUri = ""
  replayUri = ""
  resultsMethod = "PUT"
  replayMethod = "PUT"
  started = false
  done = false
  replayMode = false

proc jsonHeaders(): mummy.HttpHeaders =
  result["Content-Type"] = "application/json"

proc htmlHeaders(): mummy.HttpHeaders =
  result["Content-Type"] = "text/html; charset=utf-8"

proc jsHeaders(): mummy.HttpHeaders =
  result["Content-Type"] = "text/javascript; charset=utf-8"

proc pushInbound(event: Inbound) {.gcsafe.} =
  {.gcsafe.}:
    withLock inboundLock:
      inbound.add event

proc query(request: Request, name: string): string =
  $request.queryParams[name]

proc tileCoord(p: WorldPoint): tuple[x, y: float] =
  (
    float(p.x) / float(WorldScale) + float(GridTiles div 2),
    float(p.z) / float(WorldScale) + float(GridTiles div 2)
  )

proc fogCanSee(world: World, team: Team, position: WorldPoint): bool =
  fogCanSeeTeam(world, team.ord, position)

proc pudgeJson(pudge: Pudge, slot: int): JsonNode =
  let pos = tileCoord(pudge.position)
  result = %*{
    "id": pudge.id,
    "slot": slot,
    "team": pudge.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "hp": max(pudge.hp, 0),
    "max_hp": pudge.maxHp,
    "alive": pudge.state == Alive,
    "hooked": pudge.hookedBy != 0,
    "shield": pudge.shieldTicks > 0,
    "hook_ready": pudge.hookCooldown <= 0 and pudge.windupTicks <= 0,
    "kills": pudge.kills,
    "in_river": pudge.inRiver
  }

proc hookJson(world: World, hook: Hook): JsonNode =
  let
    pos = tileCoord(hook.position)
    owner = world.pudgeIndex(hook.ownerId)
    ownerSlot = if owner >= 0: owner else: 0
  %*{
    "owner": ownerSlot,
    "team": hook.team.ord,
    "x": round(tileCoord(hook.position).x, 3),
    "y": round(pos.y, 3)
  }

proc scoreNode(world: World): JsonNode =
  %*{
    "west": world.teamKills[WestTeam.ord],
    "east": world.teamKills[EastTeam.ord]
  }

proc winnerName(world: World): string =
  if not world.gameOver:
    return ""
  if world.winner == WestTeam: "west" else: "east"

proc observation(slot: int, final = false): JsonNode =
  let
    world = game.world
    viewer = world.pudges[slot]
  var visiblePudges = newJArray()
  var visibleHooks = newJArray()
  for i, pudge in world.pudges:
    if not fogOn or pudge.team == viewer.team or
        fogCanSee(world, viewer.team, pudge.position):
      visiblePudges.add pudgeJson(pudge, i)
  for hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if not fogOn or fogCanSee(world, viewer.team, hook.position):
      visibleHooks.add hookJson(world, hook)
  var pingNode = newJNull()
  var ping: Ping
  if world.latestTeamPing(viewer.team, ping):
    pingNode = %*{"x": ping.x, "y": ping.y, "by": ping.byId, "tick": ping.tick}
  result = %*{
    "type": if final: "final" else: "observation",
    "slot": slot,
    "tick": world.tick,
    "max_ticks": maxTicks,
    "kill_goal": world.killGoal,
    "width": GridTiles,
    "height": GridTiles,
    "river_west": RiverWestX,
    "river_east": RiverEastX,
    "fog": fogOn,
    "self": pudgeJson(viewer, slot),
    "visible": {"pudges": visiblePudges, "hooks": visibleHooks},
    "ally_ping": pingNode,
    "score": scoreNode(world),
    "done": final or world.gameOver or done,
    "winner": winnerName(world)
  }

proc globalSnapshot(): JsonNode =
  let world = game.world
  var pudges = newJArray()
  var hooks = newJArray()
  for i, pudge in world.pudges:
    pudges.add pudgeJson(pudge, i)
  for hook in world.hooks:
    if hook.phase != HookIdle:
      hooks.add hookJson(world, hook)
  var names = newJArray()
  for name in playerNames:
    names.add %name
  result = %*{
    "type": "state",
    "tick": world.tick,
    "max_ticks": maxTicks,
    "kill_goal": world.killGoal,
    "width": GridTiles,
    "height": GridTiles,
    "river_west": RiverWestX,
    "river_east": RiverEastX,
    "score": scoreNode(world),
    "pudges": pudges,
    "hooks": hooks,
    "player_names": names,
    "started": started,
    "paused": false,
    "tick_rate": TickRate,
    "done": done or world.gameOver,
    "winner": winnerName(world),
    "seed": seed
  }

proc sendText(ws: WebSocket, body: string) =
  try:
    ws.send(body)
  except CatchableError:
    discard

proc broadcastPlayers(final = false) =
  withLock sessionLock:
    for slot, ws in playerSockets:
      if slot < 0 or slot >= game.world.pudges.len:
        continue
      if slot >= playerConnected.len or not playerConnected[slot]:
        continue
      sendText(ws, $observation(slot, final))

proc broadcastGlobal() =
  let body = $globalSnapshot()
  withLock sessionLock:
    for ws in globalSockets:
      sendText(ws, body)

proc toFine(value: float): int32 =
  int32(round(value * float(FineAimScale)))

proc toTile(value: float): int32 =
  int32(round(value))

proc applyAction(slot: int, node: JsonNode) =
  if slot < 0 or slot >= game.world.pudges.len:
    return
  if node.kind != JObject:
    return
  if node.hasKey("halt") and node["halt"].getBool:
    queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentStop))
    return
  if node.hasKey("walk_to") and node["walk_to"].kind == JArray and
      node["walk_to"].len >= 2:
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentWalk,
        a: toTile(node["walk_to"][0].getFloat),
        b: toTile(node["walk_to"][1].getFloat)
      )
    )
  if node.hasKey("hook_to") and node["hook_to"].kind == JArray and
      node["hook_to"].len >= 2:
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentHookFine,
        a: toFine(node["hook_to"][0].getFloat),
        b: toFine(node["hook_to"][1].getFloat)
      )
    )
  if node.hasKey("ping") and node["ping"].kind == JArray and
      node["ping"].len >= 2:
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPing,
        a: toTile(node["ping"][0].getFloat),
        b: toTile(node["ping"][1].getFloat)
      )
    )

proc seatForToken(token: string): int =
  ## The seat a token unlocks, or -1. Same per-seat tokens the JSON
  ## `/player` path checks; a WASM human sends its seat token in NmHello
  ## (query strings die in the k8s proxy, the Flatty frame survives).
  result = -1
  if token.len == 0:
    return
  for i in 0 ..< tokens.len:
    if tokens[i] == token:
      return i

proc netSetup(): Setup =
  ## The world-init contract for followers: the recorder's frozen setup
  ## (map seed and hash, roster, kill goal, rune period, duration).
  if game.recorder != nil:
    return game.recorder.data.header.setup
  currentSetup(game, uint32(maxTicks))

proc netSeatRoster(): seq[NetSeat] =
  ## The lobby view every game connection gets: which seats have a
  ## human driver and whether that driver's socket is currently up.
  result.setLen(game.world.pudges.len)
  for i in 0 ..< result.len:
    let human = i < gameConnected.len and gameConnected[i]
    result[i] = NetSeat(
      name: if i < playerNames.len: playerNames[i] else: "",
      human: human,
      connected: human
    )

proc sendBinary(ws: WebSocket, body: string) =
  try:
    ws.send(body, BinaryMessage)
  except CatchableError:
    discard

proc sendGameStartAndBacklog(ws: WebSocket, session: var Session) =
  ## One WASM human catches up: the match setup plus the whole tape so
  ## far, so its follower fast-forwards to the live tick and then tracks.
  if not started or game.recorder == nil:
    return
  sendBinary(ws, packStart(netSetup()))
  session.started = true
  session.sentActions = game.recorder.data.actions.len
  session.sentHashes = game.recorder.data.hashes.len
  for frame in packTickSlices(
      1'u32,
      game.recorder.data.actions,
      game.recorder.data.hashes
  ):
    sendBinary(ws, frame)

proc bindGameSeat(ws: WebSocket, session: var Session, slot: int) =
  ## Attaches a WASM human connection to its seat, dropping any earlier
  ## socket on the same seat (a second game tab, or a stale reconnect).
  withLock sessionLock:
    if slot < gameSockets.len and gameConnected[slot] and
        gameSockets[slot] != ws and gameSockets[slot] in sessions:
      sendBinary(gameSockets[slot],
        packBye("this seat reconnected from another window"))
      try: gameSockets[slot].close()
      except CatchableError: discard
      sessions[gameSockets[slot]].slot = -1
    if slot < gameSockets.len:
      gameSockets[slot] = ws
      gameConnected[slot] = true
  session.slot = slot
  # A live human seat overrides any sticky bot order; a policy pod and a
  # WASM human never hold the same seat token, so this cannot fight one.
  discard applyTakeOver(game, game.world.worldIndexOfSeat(slot), true)

proc handleGameFrame(ws: WebSocket, session: var Session, data: string) =
  ## One binary netproto frame from a WASM human on /ws.
  var message: NetMessage
  try:
    message = decodeNetMessage(data)
  except NetError as error:
    sendBinary(ws, packBye("protocol error: " & error.msg))
    try: ws.close()
    except CatchableError: discard
    return
  case message.kind
  of NmHello:
    try:
      validateHello(message.hello)
    except NetError as error:
      sendBinary(ws, packBye(error.msg))
      try: ws.close()
      except CatchableError: discard
      return
    session.kind = SkGame
    session.name = message.hello.name
    let slot = seatForToken(message.hello.token)
    if slot >= 0:
      bindGameSeat(ws, session, slot)
      if session.name.len > 0 and slot < playerNames.len:
        playerNames[slot] = session.name
      sendBinary(ws, packSlotGrant(int32(slot), message.hello.token, ""))
      echo "coworld ws seat ", slot, " joined: ", session.name
    else:
      sendBinary(ws, packSlotGrant(SpectatorSlot, "", "unknown seat token"))
    sendGameStartAndBacklog(ws, session)
    sendBinary(ws, packLobby(netSeatRoster(), started))
  of NmIntent:
    if started and session.slot >= 0:
      var intent = message.intent.intent
      # The seat is authoritative host-side; a client cannot drive
      # someone else's butcher regardless of what it stamps.
      intent.slot = int32(session.slot)
      # The host applies on its live tick regardless; `wantedTick` is the
      # client's prediction. A large gap means the browser is lagging the
      # host - log it as the RTT-in-ticks signal the play-proxy budget
      # watches. The client learns the real tick from the tape and snaps.
      let wanted = message.intent.wantedTick
      if wanted != 0:
        let cur = uint32(game.world.tick)
        let gap = (if wanted >= cur: int(wanted - cur) else: -int(cur - wanted))
        if gap < -IntentSnapWindow or gap > IntentSnapWindow:
          echo "coworld ws seat ", session.slot, " intent snap: wanted ",
            wanted, " applied ", cur, " gap ", gap
      queueIntent(game, intent)
  of NmPing:
    # Echo only. Never queued as an intent or written to the tape.
    sendBinary(ws, packPong(message.ping.sentAtUs))
  else:
    discard

proc streamGameTicks() =
  ## Streams the recorder tail to every caught-up WASM human. Same tape
  ## and per-tick hashes the follower verifies, so /ws cannot diverge
  ## from the authoritative sim (Gate 0 keeps native and wasm in step).
  if game.recorder == nil:
    return
  let
    actionCount = game.recorder.data.actions.len
    hashCount = game.recorder.data.hashes.len
  var targets: seq[WebSocket]
  withLock sessionLock:
    for ws, session in sessions:
      if session.kind == SkGame and session.started and
          (session.sentActions < actionCount or
           session.sentHashes < hashCount):
        targets.add ws
  for ws in targets:
    var session: Session
    var known = false
    withLock sessionLock:
      if ws in sessions:
        session = sessions[ws]
        known = true
    if not known:
      continue
    for slice in packTickSlices(
      uint32(session.sentHashes + 1),
      game.recorder.data.actions[session.sentActions ..< actionCount],
      game.recorder.data.hashes[session.sentHashes ..< hashCount]
    ):
      sendBinary(ws, slice)
    session.sentActions = actionCount
    session.sentHashes = hashCount
    withLock sessionLock:
      if ws in sessions:
        sessions[ws].sentActions = session.sentActions
        sessions[ws].sentHashes = session.sentHashes

proc forwardGameResults() =
  ## Sends each WASM human its own seat's sim acknowledgments. Policy
  ## pods do not read acks (their JSON obs carry state), so anything not
  ## bound to a live game seat is dropped.
  if game.intentResults.len == 0:
    return
  withLock sessionLock:
    for res in game.intentResults:
      let slot = int(res.slot)
      if slot >= 0 and slot < gameConnected.len and gameConnected[slot] and
          slot < gameSockets.len and gameSockets[slot] in sessions:
        sendBinary(gameSockets[slot], packIntentResult(res))
  game.intentResults.setLen(0)

proc announceGameStart() =
  ## At match start, hand every already-connected WASM human the setup
  ## and an empty backlog so they begin following from tick 1.
  var targets: seq[WebSocket]
  withLock sessionLock:
    for ws, session in sessions:
      if session.kind == SkGame:
        targets.add ws
  for ws in targets:
    var session: Session
    withLock sessionLock:
      if ws notin sessions:
        continue
      session = sessions[ws]
    session.started = false
    sendGameStartAndBacklog(ws, session)
    sendBinary(ws, packLobby(netSeatRoster(), started))
    withLock sessionLock:
      if ws in sessions:
        sessions[ws] = session

proc drainInbound() =
  var events: seq[Inbound]
  withLock inboundLock:
    events = inbound
    inbound.setLen(0)
  for event in events:
    case event.kind
    of InOpen:
      discard
    of InMessage:
      var session: Session
      var known = false
      withLock sessionLock:
        if event.ws in sessions:
          session = sessions[event.ws]
          known = true
      if not known:
        continue
      if event.binary or session.kind == SkGame:
        handleGameFrame(event.ws, session, event.text)
        withLock sessionLock:
          if event.ws in sessions:
            sessions[event.ws] = session
        continue
      if session.kind != SkPlayer:
        continue
      try:
        applyAction(session.slot, parseJson(event.text))
      except CatchableError:
        discard
    of InClose:
      withLock sessionLock:
        if event.ws in sessions:
          let session = sessions[event.ws]
          if session.kind == SkPlayer and session.slot >= 0 and
              session.slot < playerConnected.len and
              session.slot < playerSockets.len and
              playerSockets[session.slot] == event.ws:
            playerConnected[session.slot] = false
          if session.kind == SkGame and session.slot >= 0 and
              session.slot < gameConnected.len and
              session.slot < gameSockets.len and
              gameSockets[session.slot] == event.ws:
            gameConnected[session.slot] = false
            # A dropped human leaves its butcher on the last order; the
            # seat token lets a reload rejoin. Never stall the clock.
            if started:
              discard applyTakeOver(
                game, game.world.worldIndexOfSeat(session.slot), false)
          globalSockets = globalSockets.filterIt(it != event.ws)
          sessions.del(event.ws)

proc connectedPlayerCount(): int =
  ## Seats held by either a JSON policy pod or a WASM human. The match
  ## starts once every seat has one driver, regardless of protocol.
  withLock sessionLock:
    for i in 0 ..< tokens.len:
      if (i < playerConnected.len and playerConnected[i]) or
          (i < gameConnected.len and gameConnected[i]):
        inc result

proc readBytes(uri: string): string =
  let parsed = parseUri(uri)
  if parsed.scheme in ["http", "https"]:
    let client = newHttpClient(timeout = HttpTimeoutMs)
    client.headers["User-Agent"] = UserAgent
    try:
      return client.getContent(uri)
    finally:
      client.close()
  let path =
    if parsed.scheme == "file": decodeUrl(parsed.path)
    else: uri
  readFile(path)

proc writeBytes(uri, data, contentType, httpMethod: string) =
  let parsed = parseUri(uri)
  if parsed.scheme in ["http", "https"]:
    let client = newHttpClient(timeout = HttpTimeoutMs)
    client.headers = newHttpHeaders({
      "Content-Type": contentType,
      "User-Agent": UserAgent
    })
    let verb = if httpMethod.toUpperAscii() == "POST": HttpPost else: HttpPut
    try:
      discard client.request(uri, httpMethod = verb, body = data)
    finally:
      client.close()
    return
  let path =
    if parsed.scheme == "file": decodeUrl(parsed.path)
    else: uri
  let dir = path.parentDir
  if dir.len > 0:
    createDir(dir)
  writeFile(path, data)

proc envMethod(name, fallback: string): string =
  let value = getEnv(name, fallback).toUpperAscii()
  if value in ["PUT", "POST"]:
    return value
  fallback

proc clipScore(value: float): float =
  max(0.0, min(1.0, value))

proc resultsJson(): JsonNode =
  let world = game.world
  var scores = newJArray()
  var perSeat = newJArray()
  let
    west = world.teamKills[WestTeam.ord]
    east = world.teamKills[EastTeam.ord]
    goal = max(world.killGoal, 1'i32)
  for i, pudge in world.pudges:
    let
      mine = if pudge.team == WestTeam: west else: east
      theirs = if pudge.team == WestTeam: east else: west
      margin = (float(mine) - float(theirs)) / float(goal)
    scores.add %round(clipScore(0.5 + 0.5 * margin), 4)
    perSeat.add %*{
      "slot": i,
      "team": pudge.team.ord,
      "kills": pudge.kills,
      "deaths": pudge.deaths,
      "hooks_thrown": pudge.hooksThrown,
      "hooks_landed": pudge.hooksLanded
    }
  let reason =
    if world.gameOver: "kill_goal"
    else: "time_limit"
  var winner = "draw"
  if west > east:
    winner = "west"
  elif east > west:
    winner = "east"
  if world.gameOver:
    winner = winnerName(world)
  %*{
    "scores": scores,
    "winner_team": winner,
    "west_kills": west,
    "east_kills": east,
    "end_tick": world.tick,
    "end_reason": reason,
    "seed": seed,
    "kill_goal": world.killGoal,
    "per_seat": perSeat
  }

proc finishMatch() =
  if done:
    return
  done = true
  if game.recorder != nil and game.recordingError.len == 0:
    game.recorder.data.header.setup.maximumTicks =
      max(uint32(game.world.tick), 1'u32)
    try:
      writeBytes(
        replayUri,
        encodeReplay(game.recorder.data),
        "application/octet-stream",
        replayMethod
      )
      echo "replay saved ", game.recorder.data.actions.len, " actions"
    except CatchableError as error:
      echo "replay write failed: ", error.msg
  elif game.recordingError.len > 0:
    echo "replay recording error: ", game.recordingError
  try:
    writeBytes(
      resultsUri,
      $resultsJson(),
      "application/json",
      resultsMethod
    )
  except CatchableError as error:
    echo "results write failed: ", error.msg
  # Flush the last hashed ticks, then say goodbye so followers end on
  # the same final hash instead of a dropped-connection error.
  streamGameTicks()
  block:
    var targets: seq[WebSocket]
    withLock sessionLock:
      for ws, session in sessions:
        if session.kind == SkGame:
          targets.add ws
    for ws in targets:
      sendBinary(ws, packBye("match complete"))
  broadcastPlayers(final = true)
  broadcastGlobal()
  sleep(400)
  quit(0)

proc healthzHandler(request: Request) {.gcsafe.} =
  request.respond(200, jsonHeaders(), "{\"ok\":true}")

proc playerPageHandler(request: Request) {.gcsafe.} =
  request.respond(200, htmlHeaders(), PlayerHtml)

proc globalPageHandler(request: Request) {.gcsafe.} =
  request.respond(200, htmlHeaders(), GlobalHtml)

proc arenaHandler(request: Request) {.gcsafe.} =
  request.respond(200, jsHeaders(), ArenaJs)

proc upgradePlayer(request: Request) {.gcsafe.} =
  {.gcsafe.}:
    if replayMode:
      request.respond(403, jsonHeaders(), "replay mode")
      return
    var slot = -1
    try:
      slot = parseInt(query(request, "slot"))
    except CatchableError:
      request.respond(403, jsonHeaders(), "bad slot")
      return
    let token = query(request, "token")
    if slot < 0 or slot >= tokens.len or tokens[slot] != token:
      request.respond(403, jsonHeaders(), "bad token")
      return
    let ws = request.upgradeToWebSocket()
    withLock sessionLock:
      sessions[ws] = Session(kind: SkPlayer, slot: slot)
      if slot < playerSockets.len:
        playerSockets[slot] = ws
        playerConnected[slot] = true
    pushInbound Inbound(kind: InOpen, ws: ws)

proc upgradeGlobal(request: Request) {.gcsafe.} =
  {.gcsafe.}:
    let ws = request.upgradeToWebSocket()
    withLock sessionLock:
      sessions[ws] = Session(kind: SkGlobal, slot: -1)
      globalSockets.add ws
    pushInbound Inbound(kind: InOpen, ws: ws)

proc upgradeGame(request: Request) {.gcsafe.} =
  {.gcsafe.}:
    if replayMode:
      request.respond(403, jsonHeaders(), "replay mode")
      return
    # Identity (seat token, name) rides the NmHello frame, not the query
    # string, so this survives the k8s API proxy that drops query params.
    let ws = request.upgradeToWebSocket()
    withLock sessionLock:
      sessions[ws] = Session(kind: SkGame, slot: -1)
    pushInbound Inbound(kind: InOpen, ws: ws)

proc websocketHandler(
    websocket: WebSocket,
    event: WebSocketEvent,
    message: Message
) {.gcsafe.} =
  case event
  of OpenEvent:
    discard
  of MessageEvent:
    if message.kind == Ping:
      websocket.send(message.data, Pong)
    elif message.kind == TextMessage:
      pushInbound Inbound(kind: InMessage, ws: websocket, text: message.data)
    elif message.kind == BinaryMessage:
      # Binary is netproto from a WASM human on /ws; the game thread
      # decodes it. Frame bytes travel in `text` regardless of kind.
      pushInbound Inbound(
        kind: InMessage, ws: websocket, text: message.data, binary: true
      )
  of CloseEvent:
    pushInbound Inbound(kind: InClose, ws: websocket)
  of ErrorEvent:
    # A send/protocol fault is a dead socket; treat it like Close so the
    # seat is released for a token reconnect instead of leaking.
    pushInbound Inbound(kind: InClose, ws: websocket)

proc serveThread() {.thread.} =
  {.gcsafe.}:
    try:
      let
        host = getEnv("COGAME_HOST", "0.0.0.0")
        port = parseInt(getEnv("COGAME_PORT", "8080"))
      hostServer.serve(Port(port), host)
    except CatchableError as error:
      echo "coworld host stopped: ", error.msg

proc parseConfig(node: JsonNode) =
  tokens.setLen(0)
  for token in node["tokens"]:
    tokens.add token.getStr
  playerNames.setLen(0)
  if node.hasKey("players"):
    for player in node["players"]:
      playerNames.add player["name"].getStr
  while playerNames.len < tokens.len:
    playerNames.add "Seat " & $playerNames.len
  maxTicks = int32(node["max_ticks"].getInt)
  killGoal = int32(node{"kill_goal"}.getInt(int(KillGoal)))
  fogOn = node{"fog"}.getBool(true)
  connectTimeoutSec = node{"player_connect_timeout_seconds"}.getFloat(180.0)
  if node.hasKey("seed") and node["seed"].kind != JNull:
    seed = int32(node["seed"].getInt)
  else:
    seed = int32((epochTime() * 1000).int64 and 0x7fff_ffff)

proc bootGame() =
  if tokens.len != PudgeCount and tokens.len != DuelPudgeCount:
    raise newException(
      CatchableError,
      "Pudge Wars Coworld seats 2 (duel) or 6 (3v3) butchers"
    )
  let gameMap = generateMap(seed)
  game = newGame(
    gameMap, maxTicks, false, ReplayData(), killGoal, RunePeriodTicks,
    tokens.len == DuelPudgeCount
  )
  game.humanSlots.setLen(0)
  for i in 0 ..< game.world.pudges.len:
    game.humanSlots.add i
  playerSockets.setLen(tokens.len)
  playerConnected.setLen(tokens.len)
  gameSockets.setLen(tokens.len)
  gameConnected.setLen(tokens.len)
  echo "coworld map seed=", seed, " seats=", tokens.len, " kill_goal=",
    game.world.killGoal, " max_ticks=", maxTicks

proc loadEnv() =
  replayMode = existsEnv("COGAME_LOAD_REPLAY_URI")
  if replayMode:
    tokens = @[]
    playerNames = @[]
    maxTicks = 1
    killGoal = 1
    seed = 1
    return
  if not existsEnv("COGAME_CONFIG_URI"):
    raise newException(CatchableError, "COGAME_CONFIG_URI is required")
  parseConfig(parseJson(readBytes(getEnv("COGAME_CONFIG_URI"))))
  resultsUri = getEnv("COGAME_RESULTS_URI")
  replayUri = getEnv("COGAME_SAVE_REPLAY_URI")
  resultsMethod = envMethod("COGAME_RESULTS_METHOD", "PUT")
  replayMethod = envMethod("COGAME_SAVE_REPLAY_METHOD", "PUT")
  if resultsUri.len == 0 or replayUri.len == 0:
    raise newException(CatchableError, "results and replay URIs are required")

proc main() =
  initLock(inboundLock)
  initLock(sessionLock)
  loadEnv()
  if not replayMode:
    bootGame()
  var router: Router
  router.get("/healthz", healthzHandler)
  router.get("/client/player", playerPageHandler)
  router.get("/client/global", globalPageHandler)
  router.get("/client/arena.js", arenaHandler)
  router.get("/player", upgradePlayer)
  router.get("/global", upgradeGlobal)
  router.get("/ws", upgradeGame)
  hostServer = newServer(
    router, websocketHandler, maxMessageLen = WsMaxMessageLen
  )
  var thread: Thread[void]
  createThread(thread, serveThread)
  echo "coworld listening"
  if replayMode:
    joinThread(thread)
    return
  let deadline = epochTime() + connectTimeoutSec
  while connectedPlayerCount() < tokens.len and epochTime() < deadline:
    drainInbound()
    sleep(50)
  started = true
  echo "starting with ", connectedPlayerCount(), "/", tokens.len, " players"
  game.recorder = initReplayRecorder(currentSetup(game, uint32(maxTicks)))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  announceGameStart()
  broadcastPlayers()
  broadcastGlobal()
  let step = initDuration(nanoseconds = 1_000_000_000 div int(TickRate))
  var nextAt = getMonoTime()
  var steps = 0
  while steps < int(maxTicks) and not game.world.gameOver and
      game.recordingError.len == 0:
    drainInbound()
    tickWorld(game, proc() = runBotDecisions(game))
    inc steps
    # WASM humans first: they follow the tape and predict locally, so
    # the confirmed slice must leave the moment a tick is hashed. Never
    # let a late browser stall the 32 Hz clock (the sleep below is fixed).
    streamGameTicks()
    forwardGameResults()
    broadcastPlayers()
    if steps mod 4 == 0:
      broadcastGlobal()
    nextAt = nextAt + step
    let now = getMonoTime()
    if now < nextAt:
      let wait = inMilliseconds(nextAt - now)
      if wait > 0:
        sleep(int(wait))
    else:
      nextAt = now
  finishMatch()

main()
