## Pudge Wars match hosting: one embedded HTTP + WebSocket server.
##
## `pw --host` serves three things from the game process: the lobby
## page (`/`), the wasm bundle (`/play/...`), and the match socket
## (`/ws`). Browser lobby pages speak small JSON text frames; game
## clients (native or wasm) speak the binary `netproto` format. Both
## share one socket endpoint - the frame kind tells them apart.
##
## Threading: mummy runs its own socket threads, but every protocol
## decision happens on the game thread. Handlers only append raw events
## to a locked queue; `pumpHosting` drains it once per frame. Outbound
## `WebSocket.send` is safe from the game thread because mummy queues
## writes internally.

import
  std/[json, locks, os, random, strutils, tables, times],
  mummy, mummy/routers,
  content, netproto, sim

from std/net import getPrimaryIPAddr, `$`

when defined(macosx):
  import std/osproc

const
  LobbyHtml = staticRead("lobby.html")
  MaxNameBytes = 24
  MaxChatBytes = 200
  MaxChatLog = 80

type
  SessionMode = enum
    ModeUnknown,
    ModePage,
    ModeGame

  Session = object
    mode: SessionMode
    name: string
    slot: int
      ## Claimed seat, or -1.
    started: bool
      ## Whether this connection received the current `Start`.
    sentActions: int
    sentHashes: int

  SeatClaim = object
    ## One remote player's hold on a seat. The token outlives the
    ## socket so a lobby page can hand off to the game tab, and a
    ## dropped player can reconnect into the same seat.
    taken: bool
    name: string
    token: string
    connected: bool
    ws: WebSocket

  InboundKind = enum
    InOpen,
    InMessage,
    InClose

  InboundEvent = object
    kind: InboundKind
    ws: WebSocket
    data: string
    text: bool

  ChatLine = object
    name: string
    text: string
    sys: bool

var
  hostLock: Lock
  inbound: seq[InboundEvent]
    ## Raw socket events; the only state mummy threads touch.
  hostServer: Server
  hostThread: Thread[uint16]
  hostActive = false
  hostPort: uint16
  hostName = "Host"
  bundleDir = ""
  infoKillGoal = 0'i32
  infoRuneSeconds = 0'i32
  sessions: Table[WebSocket, Session]
  seats: array[MaxPudgeCount, SeatClaim]
  localClaim* = -1
    ## The host player's own seat pick, outside the session table.
  seatDisabled*: array[MaxPudgeCount, bool]
    ## Host lobby seat toggles: an off seat spawns nothing.
  hostTeamSize* = TeamSize
    ## Live N for the lobby wells (1..5). Locked once the match starts.
  matchStarted = false
  lobbyDirty = false
  hostBotNames: seq[string]
    ## Per-seat bot personality labels for the lobby page.
  chatLog: seq[ChatLine]
  statusLock: Lock
  statusJson = "{}"
    ## Snapshot of lobby JSON for GET /status; mummy threads read it.

when defined(macosx):
  var awakeProcess: Process

initLock(hostLock)
initLock(statusLock)

proc refreshStatusSnapshot()
  ## Filled in below; startHosting snapshots /status after bind.

proc hostingActive*(): bool =
  hostActive

proc hostingStarted*(): bool =
  matchStarted

proc hostSeatCount*(): int =
  ## Lobby wells on the current N vs N: 2, 4, 6, 8, or 10.
  matchPudgeCount(hostTeamSize)

proc setHostTeamSize*(n: int) =
  ## Resize the lobby. Extra claims drop; new wells start as bots.
  if matchStarted:
    return
  let next = clampTeamSize(n)
  if next == hostTeamSize:
    return
  hostTeamSize = next
  let now = hostSeatCount()
  if localClaim >= now:
    localClaim = -1
  for i in now ..< MaxPudgeCount:
    seats[i] = SeatClaim()
    seatDisabled[i] = false
  for i in 0 ..< now:
    seatDisabled[i] = false
  lobbyDirty = true

proc hostingUrl*(): string =
  ## The address friends visit; the primary LAN IP when discoverable.
  var address = "127.0.0.1"
  try:
    address = $getPrimaryIPAddr()
  except CatchableError:
    discard
  "http://" & address & ":" & $hostPort & "/"

proc sanitizeName(raw: string): string =
  for character in raw:
    if character in {' ' .. '~'} and result.len < MaxNameBytes:
      result.add character
  result = result.strip()
  if result.len == 0:
    result = "Player"

proc newToken(): string =
  const Hex = "0123456789abcdef"
  for _ in 0 ..< 16:
    result.add Hex[rand(15)]

# --- mummy-thread side -------------------------------------------------

proc pushEvent(event: sink InboundEvent) {.gcsafe.} =
  {.gcsafe.}:
    withLock hostLock:
      inbound.add event

proc contentTypeFor(name: string): string =
  if name.endsWith(".html"): "text/html; charset=utf-8"
  elif name.endsWith(".js"): "application/javascript"
  elif name.endsWith(".wasm"): "application/wasm"
  elif name.endsWith(".png"): "image/png"
  elif name.endsWith(".json"): "application/json"
  else: "application/octet-stream"

proc withCors(headers: var HttpHeaders) =
  ## Browser copies of this page (or a `?host=` join) fetch `/status`
  ## and `/play/*` cross-origin; the socket itself is not CORS-gated.
  headers["Access-Control-Allow-Origin"] = "*"
  headers["Access-Control-Allow-Headers"] = "*"
  headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"

proc lobbyPageHandler(request: Request) {.gcsafe.} =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html; charset=utf-8"
  withCors(headers)
  request.respond(200, headers, LobbyHtml)

proc statusHandler(request: Request) {.gcsafe.} =
  ## Public lobby snapshot so a remote client can join without already
  ## being on this origin.
  var body: string
  {.gcsafe.}:
    withLock statusLock:
      body = statusJson
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json; charset=utf-8"
  withCors(headers)
  request.respond(200, headers, body)

proc corsOptionsHandler(request: Request) {.gcsafe.} =
  var headers: HttpHeaders
  withCors(headers)
  request.respond(204, headers, "")

type
  CachedFile = object
    body: string
    etag: string
    mtime: Time

var
  bundleLock: Lock
  bundleCache: Table[string, CachedFile]

initLock(bundleLock)

proc cachedBundleFile(path: string): CachedFile =
  ## One bundle file from memory, re-read only when it changes on disk,
  ## so the 20+ MB wasm data pack is not read per request.
  let mtime = getLastModificationTime(path)
  withLock bundleLock:
    if path in bundleCache and bundleCache[path].mtime == mtime:
      return bundleCache[path]
  let loaded = CachedFile(
    body: readFile(path),
    etag: "\"" & toHex(mtime.toUnix()) & "-" & toHex(getFileSize(path)) &
      "\"",
    mtime: mtime
  )
  withLock bundleLock:
    bundleCache[path] = loaded
  loaded

proc playFileHandler(request: Request) {.gcsafe.} =
  ## Serves one wasm bundle file by basename; no directory walking.
  ## ETag + no-cache lets browsers keep the big data pack across the
  ## lobby-to-game navigation and page reloads while still picking up
  ## rebuilt bundles at once.
  {.gcsafe.}:
    var name = request.uri
    let query = name.find('?')
    if query >= 0:
      name = name[0 ..< query]
    name = name.rsplit('/', maxsplit = 1)[^1]
    var safe = name.len > 0
    for character in name:
      if character notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '_', '-'}:
        safe = false
        break
    var failHeaders: HttpHeaders
    withCors(failHeaders)
    if not safe or name.startsWith("."):
      request.respond(404, failHeaders, "bad path")
      return
    let path = bundleDir / name
    if not fileExists(path):
      request.respond(
        404,
        failHeaders,
        "missing " & name & "; build the web client with:\n" &
        "  nim c -d:emscripten examples/pudge_wars/pw.nim"
      )
      return
    try:
      let cached = cachedBundleFile(path)
      var headers: HttpHeaders
      headers["Cache-Control"] = "no-cache"
      headers["ETag"] = cached.etag
      withCors(headers)
      if request.headers["If-None-Match"] == cached.etag:
        request.respond(304, headers, "")
        return
      headers["Content-Type"] = contentTypeFor(name)
      request.respond(200, headers, cached.body)
    except IOError, OSError:
      request.respond(500, failHeaders, "read failed")

proc upgradeHandler(request: Request) {.gcsafe.} =
  discard request.upgradeToWebSocket()

proc websocketHandler(
    websocket: WebSocket,
    event: WebSocketEvent,
    message: Message
) {.gcsafe.} =
  case event
  of OpenEvent:
    pushEvent InboundEvent(kind: InOpen, ws: websocket)
  of MessageEvent:
    if message.kind in {TextMessage, BinaryMessage}:
      pushEvent InboundEvent(
        kind: InMessage,
        ws: websocket,
        data: message.data,
        text: message.kind == TextMessage
      )
  of CloseEvent:
    pushEvent InboundEvent(kind: InClose, ws: websocket)
  of ErrorEvent:
    pushEvent InboundEvent(kind: InClose, ws: websocket)

proc serveThread(port: uint16) {.thread.} =
  {.gcsafe.}:
    try:
      # mummy defaults to localhost, which prints a LAN invite that
      # friends cannot reach. Bind every interface so the advertised
      # address actually answers.
      hostServer.serve(Port(port), "0.0.0.0")
    except CatchableError as error:
      echo "host: server stopped: ", error.msg

proc botDisplayName(path: string): string =
  ## "players/aggressive.bas" becomes "Aggressive".
  result = path.splitFile.name
  if result.len > 0:
    result[0] = result[0].toUpperAscii()

proc startHosting*(
    port: int32,
    name, wasmDir: string,
    killGoal, runeSeconds: int32,
    botPaths: seq[string] = @[],
    teamSize = TeamSize
): bool =
  ## Binds the lobby server. Returns false when it cannot start.
  if hostActive:
    return true
  randomize()
  hostPort = uint16(port)
  hostName = sanitizeName(name)
  bundleDir = wasmDir
  infoKillGoal = killGoal
  infoRuneSeconds = runeSeconds
  hostTeamSize = clampTeamSize(teamSize)
  hostBotNames.setLen(0)
  for path in botPaths:
    hostBotNames.add botDisplayName(path)
  sessions.clear()
  chatLog.setLen(0)
  matchStarted = false
  localClaim = -1
  lobbyDirty = false
  for i in 0 ..< MaxPudgeCount:
    seats[i] = SeatClaim()
    seatDisabled[i] = false
  var router: Router
  router.get("/", lobbyPageHandler)
  router.get("/status", statusHandler)
  router.options("/", corsOptionsHandler)
  router.options("/status", corsOptionsHandler)
  router.options("/play/*", corsOptionsHandler)
  router.get("/ws", upgradeHandler)
  router.get("/play/*", playFileHandler)
  try:
    hostServer = newServer(
      router, websocketHandler, maxMessageLen = WsMaxMessageLen
    )
    createThread(hostThread, serveThread, hostPort)
    hostServer.waitUntilReady(2.0)
  except CatchableError as error:
    echo "host: cannot start server: ", error.msg
    return false
  when defined(macosx):
    # A sleeping display wedges the frame loop in present and the
    # lobby stops answering, so hold the machine awake while hosting.
    try:
      awakeProcess = startProcess(
        "/usr/bin/caffeinate",
        args = ["-dis", "-w", $getCurrentProcessId()]
      )
      echo "host: keeping this Mac awake while the lobby is up"
    except OSError:
      discard
  hostActive = true
  refreshStatusSnapshot()
  true

# --- game-thread side --------------------------------------------------

proc takeInbound(): seq[InboundEvent] =
  withLock hostLock:
    result = inbound
    inbound = @[]

proc seatRoster(): seq[NetSeat] =
  ## The lobby view of all live wells, host claim included.
  let n = hostSeatCount()
  result.setLen(n)
  for i in 0 ..< n:
    if i == localClaim:
      result[i] = NetSeat(
        name: hostName & " (host)", human: true, connected: true
      )
    elif seats[i].taken:
      result[i] = NetSeat(
        name: seats[i].name,
        human: true,
        connected: seats[i].connected
      )
    if seatDisabled[i]:
      result[i].off = true

proc hostSeatRoster*(): seq[NetSeat] =
  ## Snapshot for the host's own lobby overlay.
  seatRoster()

proc sanitizeChat(raw: string): string =
  for character in raw:
    if character in {' ' .. '~'} and result.len < MaxChatBytes:
      result.add character
  result = result.strip()

proc peopleNode(): JsonNode =
  ## Everyone currently in the channel: the host plus every lobby page.
  result = newJArray()
  result.add %*{
    "name": hostName,
    "slot": localClaim,
    "role": "host"
  }
  for _, session in sessions:
    if session.mode != ModePage:
      continue
    result.add %*{
      "name": session.name,
      "slot": session.slot,
      "role": if session.slot >= 0: "player" else: "lobby"
    }

proc seatsNode(roster: seq[NetSeat]): JsonNode =
  result = newJArray()
  for i, seat in roster:
    result.add %*{
      "name": seat.name,
      "human": seat.human,
      "connected": seat.connected,
      "off": seat.off,
      "bot":
        if not seat.human and i < hostBotNames.len: hostBotNames[i]
        else: ""
    }

proc lobbyPayload(): JsonNode =
  let roster = seatRoster()
  %*{
    "t": "lobby",
    "started": matchStarted,
    "seats": seatsNode(roster),
    "people": peopleNode(),
    "host": hostName,
    "goal": infoKillGoal,
    "runes": infoRuneSeconds,
    "teamSize": hostTeamSize,
    "web": fileExists(bundleDir / "pw.html"),
    "game": "Pudge Wars"
  }

proc lobbyJson(): string =
  $lobbyPayload()

proc refreshStatusSnapshot() =
  ## HTTP /status is served off the mummy threads; keep a frozen copy.
  let body = $lobbyPayload()
  withLock statusLock:
    statusJson = body

proc chatJson(line: ChatLine): string =
  $(%*{
    "t": "chat",
    "name": line.name,
    "text": line.text,
    "sys": line.sys
  })

proc broadcastChat(line: ChatLine) =
  chatLog.add line
  if chatLog.len > MaxChatLog:
    chatLog.delete(0)
  let payload = chatJson(line)
  for ws, session in sessions:
    if session.mode == ModePage:
      ws.send(payload)

proc sysChat(text: string) =
  if text.len > 0:
    broadcastChat(ChatLine(name: "", text: text, sys: true))

proc sendChatHistory(ws: WebSocket) =
  for line in chatLog:
    ws.send(chatJson(line))

proc broadcastLobby() =
  refreshStatusSnapshot()
  let
    jsonText = lobbyJson()
    binary = packLobby(seatRoster(), matchStarted)
  for ws, session in sessions:
    case session.mode
    of ModePage:
      ws.send(jsonText)
    of ModeGame:
      ws.send(binary, BinaryMessage)
    of ModeUnknown:
      discard

proc sendStartAndBacklog(ws: WebSocket, session: var Session, game: Game) =
  ## One connection catches up: the match setup plus the whole tape so
  ## far. The client fast-forwards to the live tick from this.
  if not matchStarted or game.recorder == nil:
    return
  ws.send(
    packStart(game.recorder.data.header.setup),
    BinaryMessage
  )
  session.started = true
  session.sentActions = game.recorder.data.actions.len
  session.sentHashes = game.recorder.data.hashes.len
  for frame in packTickSlices(
      1'u32,
      game.recorder.data.actions,
      game.recorder.data.hashes
  ):
    ws.send(frame, BinaryMessage)

proc releaseSeat(game: Game, slot: int, keepToken: bool) =
  ## Frees or suspends one remote claim. Mid-match the butcher falls
  ## back to script autopilot and the takeover lands on the tape.
  if slot < 0 or slot >= hostSeatCount() or not seats[slot].taken:
    return
  seats[slot].connected = false
  if matchStarted:
    discard applyTakeOver(game, game.world.worldIndexOfSeat(slot), false)
  if not keepToken:
    seats[slot] = SeatClaim()
  lobbyDirty = true

proc rebindSeat(game: Game, ws: WebSocket, session: var Session,
    token, name: string): int =
  ## Reattaches a connection to the seat its token claims, or -1. A
  ## page refresh and a dropped player rejoining both land here.
  result = -1
  if token.len == 0:
    return
  for i in 0 ..< hostSeatCount():
    if seats[i].taken and seats[i].token == token:
      if seats[i].connected and seats[i].ws != ws and
          seats[i].ws in sessions:
        # The same token arrived on a second connection (the play URL
        # opened twice). The newest one wins; boot the old session so
        # two sockets never drive one butcher.
        sessions[seats[i].ws].slot = -1
        if sessions[seats[i].ws].mode == ModeGame:
          seats[i].ws.send(
            packBye("this seat reconnected from another window"),
            BinaryMessage
          )
          seats[i].ws.close()
      seats[i].connected = true
      seats[i].ws = ws
      if name.len > 0:
        seats[i].name = name
      session.slot = i
      if matchStarted:
        discard applyTakeOver(game, game.world.worldIndexOfSeat(i), true)
      lobbyDirty = true
      return i

proc seatOpen(game: Game, index: int, sessionSlot: int): bool =
  if seatDisabled[index]:
    return false
  ## Whether this session may take `index` right now.
  if index == localClaim:
    return false
  if seats[index].taken and sessionSlot != index:
    if matchStarted or seats[index].connected:
      return false
  if matchStarted and not seats[index].taken and
      index in game.humanSlots:
    return false
  true

proc firstOpenSeat(game: Game, sessionSlot: int): int32 =
  ## First empty butcher, then a disconnected pre-start claim. Anyone
  ## in the channel can JOIN without picking a numbered slot.
  for i in 0 ..< hostSeatCount():
    if seats[i].taken:
      continue
    if seatOpen(game, i, sessionSlot):
      return int32(i)
  if not matchStarted:
    for i in 0 ..< hostSeatCount():
      if seats[i].taken and not seats[i].connected and
          seatOpen(game, i, sessionSlot):
        return int32(i)
  SpectatorSlot

proc tryClaim(
    game: Game,
    ws: WebSocket,
    session: var Session,
    slot: int32,
    name: string
): SlotGrantMsg =
  ## Claims one seat for a session, releasing any previous claim.
  if slot == SpectatorSlot:
    let hadSeat = session.slot >= 0
    if hadSeat:
      releaseSeat(game, session.slot, keepToken = false)
      session.slot = -1
      sysChat(name & " is watching.")
    return SlotGrantMsg(slot: SpectatorSlot)
  if slot < 0 or slot >= hostSeatCount():
    return SlotGrantMsg(slot: SpectatorSlot, reason: "no such seat")
  let index = int(slot)
  if not seatOpen(game, index, session.slot):
    if index == localClaim:
      return SlotGrantMsg(slot: SpectatorSlot, reason: "the host has that seat")
    return SlotGrantMsg(slot: SpectatorSlot, reason: "seat is taken")
  if session.slot >= 0 and session.slot != index:
    releaseSeat(game, session.slot, keepToken = false)
  seats[index] = SeatClaim(
    taken: true,
    name: name,
    token: newToken(),
    connected: true,
    ws: ws
  )
  session.slot = index
  if matchStarted:
    discard applyTakeOver(game, game.world.worldIndexOfSeat(index), true)
  lobbyDirty = true
  sysChat(name & " claimed a seat.")
  SlotGrantMsg(slot: slot, token: seats[index].token)

proc grantJson(grant: SlotGrantMsg): string =
  if grant.reason.len > 0:
    $(%*{"t": "deny", "reason": grant.reason})
  else:
    $(%*{"t": "grant", "slot": grant.slot, "token": grant.token})

proc handlePageMessage(
    game: Game,
    ws: WebSocket,
    session: var Session,
    data: string
) =
  var node: JsonNode
  try:
    node = parseJson(data)
  except CatchableError:
    return
  let kind = node{"t"}.getStr()
  case kind
  of "hello":
    session.mode = ModePage
    session.name = sanitizeName(node{"name"}.getStr())
    # A refreshed lobby page reclaims its seat by token, but only an
    # orphaned one: a live game tab keeps its socket binding.
    let token = node{"token"}.getStr()
    if token.len > 0:
      var orphaned = false
      for i in 0 ..< hostSeatCount():
        if seats[i].taken and seats[i].token == token:
          orphaned = not seats[i].connected
          break
      if orphaned:
        let slot = rebindSeat(game, ws, session, token, session.name)
        if slot >= 0:
          ws.send(grantJson(SlotGrantMsg(
            slot: int32(slot), token: token
          )))
    lobbyDirty = true
    ws.send(lobbyJson())
    sendChatHistory(ws)
  of "name":
    session.name = sanitizeName(node{"name"}.getStr())
    if session.slot >= 0:
      seats[session.slot].name = session.name
    lobbyDirty = true
  of "pick":
    let grant = tryClaim(
      game, ws, session, int32(node{"slot"}.getInt(-1)), session.name
    )
    ws.send(grantJson(grant))
  of "join":
    ## First open butcher — Battle.net "Join Game" without picking a slot.
    let open = firstOpenSeat(game, session.slot)
    if open == SpectatorSlot:
      ws.send($(%*{
        "t": "deny",
        "reason": "no open seats — stay and watch, or take an away seat"
      }))
    else:
      let grant = tryClaim(game, ws, session, open, session.name)
      ws.send(grantJson(grant))
  of "leave":
    discard tryClaim(game, ws, session, SpectatorSlot, session.name)
    ws.send(grantJson(SlotGrantMsg(slot: SpectatorSlot)))
  of "chat":
    let text = sanitizeChat(node{"text"}.getStr())
    if text.len > 0:
      broadcastChat(ChatLine(name: session.name, text: text, sys: false))
  else:
    discard

proc handleGameMessage(
    game: Game,
    ws: WebSocket,
    session: var Session,
    data: string
) =
  var message: NetMessage
  try:
    message = decodeNetMessage(data)
  except NetError as error:
    ws.send(packBye("protocol error: " & error.msg), BinaryMessage)
    ws.close()
    return
  case message.kind
  of NmHello:
    try:
      validateHello(message.hello)
    except NetError as error:
      ws.send(packBye(error.msg), BinaryMessage)
      ws.close()
      return
    session.mode = ModeGame
    session.name = sanitizeName(message.hello.name)
    var bound = false
    if message.hello.token.len > 0:
      # The lobby page hands its claim to the game tab, or a dropped
      # player reconnects into their old seat.
      let slot = rebindSeat(
        game, ws, session, message.hello.token,
        if message.hello.name.len > 0: session.name else: ""
      )
      bound = slot >= 0
      if bound:
        ws.send(
          packSlotGrant(int32(slot), message.hello.token, ""),
          BinaryMessage
        )
      else:
        ws.send(
          packSlotGrant(SpectatorSlot, "", "unknown seat token"),
          BinaryMessage
        )
    if not bound and message.hello.requestSlot != SpectatorSlot:
      let grant = tryClaim(
        game, ws, session, message.hello.requestSlot, session.name
      )
      ws.send(
        packSlotGrant(grant.slot, grant.token, grant.reason), BinaryMessage
      )
    sendStartAndBacklog(ws, session, game)
    ws.send(packLobby(seatRoster(), matchStarted), BinaryMessage)
  of NmPickSlot:
    let grant = tryClaim(
      game, ws, session, message.pickSlot.slot, session.name
    )
    ws.send(
      packSlotGrant(grant.slot, grant.token, grant.reason), BinaryMessage
    )
  of NmIntent:
    if matchStarted and session.slot >= 0:
      var intent = message.intent.intent
      # The seat is authoritative server-side; a client cannot drive
      # someone else's butcher.
      intent.slot = int32(session.slot)
      queueIntent(game, intent)
  of NmPing:
    # Echo only. Never queued as an intent or written to the tape.
    ws.send(packPong(message.ping.sentAtUs), BinaryMessage)
  else:
    discard

proc pumpHosting*(game: Game) =
  ## Drains socket events on the game thread: lobby claims, seat
  ## handoffs, remote intents, and disconnect autopilot.
  if not hostActive:
    return
  for event in takeInbound():
    case event.kind
    of InOpen:
      sessions[event.ws] = Session(slot: -1)
    of InMessage:
      if event.ws notin sessions:
        continue
      var session = sessions[event.ws]
      if event.text:
        handlePageMessage(game, event.ws, session, event.data)
      else:
        handleGameMessage(game, event.ws, session, event.data)
      sessions[event.ws] = session
    of InClose:
      if event.ws in sessions:
        let session = sessions[event.ws]
        if session.slot >= 0 and seats[session.slot].taken and
            seats[session.slot].ws == event.ws:
          # The token always survives the socket so a page refresh or
          # a reconnect lands back in the same seat. Pre-start, an
          # abandoned claim can still be taken over by someone else.
          releaseSeat(game, session.slot, keepToken = true)
        sessions.del(event.ws)
        lobbyDirty = true
  if lobbyDirty:
    lobbyDirty = false
    broadcastLobby()

proc hostBroadcastTicks*(game: Game) =
  ## Streams the recorder tail to every caught-up game connection.
  if not hostActive or not matchStarted or game.recorder == nil:
    return
  let
    actionCount = game.recorder.data.actions.len
    hashCount = game.recorder.data.hashes.len
  for ws, session in sessions.mpairs:
    if session.mode != ModeGame or not session.started:
      continue
    if session.sentActions >= actionCount and
        session.sentHashes >= hashCount:
      continue
    for frame in packTickSlices(
        uint32(session.sentHashes + 1),
        game.recorder.data.actions[session.sentActions ..< actionCount],
        game.recorder.data.hashes[session.sentHashes ..< hashCount]
    ):
      ws.send(frame, BinaryMessage)
    session.sentActions = actionCount
    session.sentHashes = hashCount

proc hostForwardResults*(game: Game, localSeat: int) =
  ## Sends remote seats' sim acknowledgments to their owners and keeps
  ## only the local player's for the on-screen HUD to drain.
  if not hostActive or game.intentResults.len == 0:
    return
  var kept: seq[IntentResult]
  for res in game.intentResults:
    let slot = int(res.slot)
    if slot == localSeat:
      kept.add res
    elif slot >= 0 and slot < hostSeatCount() and seats[slot].taken and
        seats[slot].connected:
      seats[slot].ws.send(packIntentResult(res), BinaryMessage)
  game.intentResults = kept

proc hostAnnounceStart*(game: Game) =
  ## Broadcasts the match setup: fresh matches and rematches both land
  ## here after the recorder exists. Lobby pages redirect into the
  ## game; bound clients rebuild their world.
  if not hostActive or game.recorder == nil:
    return
  matchStarted = true
  sysChat("The host started the match.")
  let startText = $(%*{"t": "start"})
  for ws, session in sessions.mpairs:
    case session.mode
    of ModePage:
      ws.send(startText)
    of ModeGame:
      session.started = false
      sendStartAndBacklog(ws, session, game)
    of ModeUnknown:
      discard
  lobbyDirty = true

proc hostRemoteSeats*(): seq[int] =
  ## Every seat a connected remote player claims. An abandoned claim
  ## (kept only for its reconnect token) starts the match as a bot;
  ## its owner takes over on return.
  for i in 0 ..< hostSeatCount():
    if seats[i].taken and seats[i].connected:
      result.add i

proc hostSeatName*(slot: int): string =
  ## Display name for one seat, or empty for a bot.
  if slot == localClaim:
    return hostName
  if slot >= 0 and slot < hostSeatCount() and seats[slot].taken:
    return seats[slot].name

proc hostClaimLocal*(slot: int) =
  ## The host player's own seat pick from the lobby overlay.
  if matchStarted:
    return
  if slot == localClaim:
    localClaim = -1
    sysChat(hostName & " is watching.")
  elif slot >= -1 and slot < hostSeatCount() and
      (slot < 0 or not seats[slot].taken):
    localClaim = slot
    if slot >= 0:
      sysChat(hostName & " claimed a seat.")
    else:
      sysChat(hostName & " is watching.")
  lobbyDirty = true

proc stopHosting*(reason: string) =
  ## Says goodbye and stops accepting connections (process exit path).
  if not hostActive:
    return
  let bye = packBye(reason)
  for ws, session in sessions:
    if session.mode == ModeGame:
      ws.send(bye, BinaryMessage)
    ws.close()
  hostActive = false
  hostServer.close()
  when defined(macosx):
    if awakeProcess != nil:
      awakeProcess.terminate()
      awakeProcess.close()
      awakeProcess = nil
