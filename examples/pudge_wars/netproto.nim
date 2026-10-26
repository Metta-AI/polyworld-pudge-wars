## Fresh Meat wire protocol: the lobby handshake and the live tape.
##
## One match has one authoritative host simulation. Remote clients send
## their seat's intents up; the host drains them through the same
## record-then-apply path as local play and streams the growing action
## tape (actions plus one state hash per tick) back down. A client is a
## pure follower: it applies the streamed actions at their exact ticks
## and verifies every hash, so the network path reuses the replay
## machinery and cannot diverge from it.
##
## Framing: every WebSocket binary message is one kind byte followed by
## the Flatty encoding of that kind's payload object. Flatty writes
## enums and lengths at fixed 64-bit widths (the wasm build defines
## `flatty64`), so native and browser builds share the format.

import
  flatty,
  replays,
  sim

const
  NetProtocolVersion* = 14'u16
    ## v14: Human pacing is 28 Hz; reject clients using the old 24 Hz clock.
    ## v13: Human pacing is 24 Hz; reject clients using the old 16 Hz clock.
    ## v12: Start and Lobby carry the host's human-paced clock flag.
    ## v11: Start Setup gained `seatLabels` (replay format v5). Host
    ##     and client must rebuild together; names ride the tape.
    ## v10: Hello carries `simVersion` (`ReplayGameVersion`) so a live
    ##     client cannot follow a host running different physics.
    ## v9: Lightning and Bounty river runes change the public kind cycle
    ##     and live combat hashes. Host and client must rebuild together.
    ## v8: river rune drops follow a public north/south + kind cycle
    ##     instead of match RNG. Live hashes change; rebuild together.
    ## v7: contested rune / clash ties and the 65-tick hook cooldown
    ##     change live hashes. Host and client must rebuild together.
    ## v6: lobby may carry 2..10 seats (N vs N, N=1..5). Older followers
    ##     sized for six wells must rebuild with the host.
    ## v5: NmIntent carries `wantedTick`, the client's predicted tick for
    ## the command. Transport only - it never enters the tape or the
    ## state hash; the host applies on its live tick and the client uses
    ## the gap to decide whether its prediction snapped. Host and client
    ## must rebuild together.
    ## v4: IntentRot at the end of IntentKind (Rot toggle). Host and
    ## client must rebuild together; older followers cannot apply it.
    ## v3 grew optional NmPing/NmPong at the end of the kind enum so
    ## older clients (they never send them) still handshake. The probes
    ## never enter the action tape or state hash.
    ## v2: the Start setup gained the rune period (replay format v3).
  NetGameId* = ReplayGame
  MaxNetMessageBytes* = MaxReplayBytes
    ## A join backlog carries a whole tape, so the cap matches replays.
  NetTickHashChunk* = 256
    ## Hashes per NmTicks frame. A reconnect backlog is the whole tape;
    ## mummy's default WebSocket cap is 64 KB, and the play-session proxy
    ## chain is happier with several modest frames than one giant one.
  WsMaxMessageLen* = 8 * 1024 * 1024
    ## Incoming WebSocket cap for mummy hosts. Intents are tiny; this is
    ## headroom so a hostile peer cannot pin the process on one frame.
  SpectatorSlot* = -1'i32
    ## Slot value meaning "watch only" in claims and grants.
  IntentSnapWindow* = 3'i32
    ## How far (ticks) a client's predicted `wantedTick` may sit from the
    ## host's live tick before the miss is worth logging / snapping. At
    ## 32 Hz this is ~90 ms, a couple of RTTs of tolerance.

type
  NetError* = object of CatchableError

  NetMsgKind* = enum
    ## One byte on the wire; order is part of the protocol.
    NmHello,        ## client -> host: name plus token or slot request
    NmPickSlot,     ## client -> host: claim or release one seat
    NmIntent,       ## client -> host: one command for the bound seat
    NmLobby,        ## host -> all: seat roster and match phase
    NmSlotGrant,    ## host -> one: claim result and continuity token
    NmStart,        ## host -> all: the match setup (world-init contract)
    NmTicks,        ## host -> all: tape slice (actions plus tick hashes)
    NmIntentResult, ## host -> one: sim acknowledgment for the seat
    NmBye,          ## host -> one: connection is being dropped
    NmPing,         ## client -> host: RTT probe; host echoes as NmPong
    NmPong          ## host -> client: echo of NmPing (not hashed)

  HelloMsg* = object
    protocol*: uint16
    game*: string
      ## Must equal `NetGameId`; rejects strangers politely.
    name*: string
    token*: string
      ## Continuity token from an earlier grant (lobby page to game
      ## boot). Empty for a fresh connection.
    requestSlot*: int32
      ## Seat wanted at connect time, or `SpectatorSlot`.
    simVersion*: uint16
      ## Must equal `ReplayGameVersion`. Independent of `protocol`:
      ## the wire can stay while physics change, and the reverse.

  PickSlotMsg* = object
    slot*: int32
      ## Seat to claim, or `SpectatorSlot` to release the current one.

  IntentMsg* = object
    intent*: HumanIntent
    wantedTick*: uint32
      ## The tick the client predicted this command against. 0 means "no
      ## preference; apply on the host's current tick". Never hashed.

  NetSeat* = object
    ## One roster seat as the lobby shows it.
    name*: string
      ## Claimant's name, or empty for a bot-driven seat.
    human*: bool
      ## Whether a human session claims this seat right now.
    connected*: bool
      ## Whether that session's socket is currently open.
    off*: bool
      ## The host disabled this seat: no butcher spawns from it.

  LobbyMsg* = object
    seats*: seq[NetSeat]
    started*: bool
    humanPaced*: bool

  SlotGrantMsg* = object
    slot*: int32
      ## Granted seat, or `SpectatorSlot` when denied or released.
    token*: string
      ## Continuity token for reconnecting as this seat.
    reason*: string
      ## Human-readable denial text; empty on success.

  StartMsg* = object
    setup*: Setup
    humanPaced*: bool

  TicksMsg* = object
    firstTick*: uint32
      ## Tick number of `hashes[0]`; tick T's hash lives at index T-1
      ## of the assembled tape, so a fresh match streams from tick 1.
    actions*: seq[ReplayAction]
    hashes*: seq[uint64]

  IntentResultMsg* = object
    res*: IntentResult

  ByeMsg* = object
    reason*: string

  PingMsg* = object
    ## One RTT probe. The host copies `sentAtUs` into NmPong; it never
    ## touches the sim, recorder, or tick hashes.
    sentAtUs*: int64
      ## Client unix microseconds when the probe left.

  NetMessage* = object
    ## Decoded in-memory view of one wire message.
    case kind*: NetMsgKind
    of NmHello: hello*: HelloMsg
    of NmPickSlot: pickSlot*: PickSlotMsg
    of NmIntent: intent*: IntentMsg
    of NmLobby: lobby*: LobbyMsg
    of NmSlotGrant: slotGrant*: SlotGrantMsg
    of NmStart: start*: StartMsg
    of NmTicks: ticks*: TicksMsg
    of NmIntentResult: intentResult*: IntentResultMsg
    of NmBye: bye*: ByeMsg
    of NmPing: ping*: PingMsg
    of NmPong: pong*: PingMsg

proc fail(message: string) {.noreturn.} =
  raise newException(NetError, message)

proc pack*[T](kind: NetMsgKind, payload: T): string =
  ## Encodes one wire message: kind byte plus Flatty payload.
  result = newStringOfCap(64)
  result.add char(kind.ord)
  result.add payload.toFlatty()

proc packHello*(name, token: string, requestSlot: int32): string =
  pack(NmHello, HelloMsg(
    protocol: NetProtocolVersion,
    game: NetGameId,
    name: name,
    token: token,
    requestSlot: requestSlot,
    simVersion: ReplayGameVersion
  ))

proc packPickSlot*(slot: int32): string =
  pack(NmPickSlot, PickSlotMsg(slot: slot))

proc packIntent*(intent: HumanIntent, wantedTick: uint32 = 0): string =
  pack(NmIntent, IntentMsg(intent: intent, wantedTick: wantedTick))

proc packLobby*(seats: seq[NetSeat], started: bool, humanPaced = false): string =
  pack(NmLobby, LobbyMsg(seats: seats, started: started, humanPaced: humanPaced))

proc packSlotGrant*(slot: int32, token, reason: string): string =
  pack(NmSlotGrant, SlotGrantMsg(slot: slot, token: token, reason: reason))

proc packStart*(setup: Setup, humanPaced = false): string =
  pack(NmStart, StartMsg(setup: setup, humanPaced: humanPaced))

proc packTicks*(
    firstTick: uint32,
    actions: seq[ReplayAction],
    hashes: seq[uint64]
): string =
  pack(NmTicks, TicksMsg(
    firstTick: firstTick, actions: actions, hashes: hashes
  ))

proc packTickSlices*(
    firstTick: uint32,
    actions: seq[ReplayAction],
    hashes: seq[uint64],
    hashChunk: int = NetTickHashChunk
): seq[string] =
  ## Encodes `hashes` (and the actions that land in those ticks) as one
  ## or more NmTicks frames of at most `hashChunk` hashes. Empty input
  ## yields nothing. The last slice also carries leftover actions whose
  ## tick sits past the last hash (between-tick take-over markers).
  if hashes.len == 0 and actions.len == 0:
    return
  let chunk = max(hashChunk, 1)
  if hashes.len == 0:
    result.add packTicks(firstTick, actions, hashes)
    return
  var
    actionAt = 0
    hashAt = 0
  while hashAt < hashes.len:
    let take = min(chunk, hashes.len - hashAt)
    let lastTick = firstTick + uint32(hashAt + take - 1)
    let lastSlice = hashAt + take >= hashes.len
    var actionEnd = actionAt
    while actionEnd < actions.len and
        (actions[actionEnd].tick <= lastTick or lastSlice):
      inc actionEnd
    result.add packTicks(
      firstTick + uint32(hashAt),
      actions[actionAt ..< actionEnd],
      hashes[hashAt ..< hashAt + take]
    )
    hashAt += take
    actionAt = actionEnd

proc packIntentResult*(res: IntentResult): string =
  pack(NmIntentResult, IntentResultMsg(res: res))

proc packBye*(reason: string): string =
  pack(NmBye, ByeMsg(reason: reason))

proc packPing*(sentAtUs: int64): string =
  pack(NmPing, PingMsg(sentAtUs: sentAtUs))

proc packPong*(sentAtUs: int64): string =
  pack(NmPong, PingMsg(sentAtUs: sentAtUs))

proc decodeNetMessage*(data: string): NetMessage =
  ## Decodes and bounds-checks one wire message. Raises `NetError` on
  ## anything malformed so a hostile or stale peer cannot crash the
  ## process.
  if data.len == 0:
    fail("empty network message")
  if data.len > MaxNetMessageBytes:
    fail("network message exceeds the size limit")
  let kindByte = int(data[0])
  if kindByte > NetMsgKind.high.ord:
    fail("unknown network message kind " & $kindByte)
  let
    kind = NetMsgKind(kindByte)
    payload = data[1 .. ^1]
  try:
    case kind
    of NmHello:
      result = NetMessage(
        kind: NmHello, hello: payload.fromFlatty(HelloMsg)
      )
    of NmPickSlot:
      result = NetMessage(
        kind: NmPickSlot, pickSlot: payload.fromFlatty(PickSlotMsg)
      )
    of NmIntent:
      result = NetMessage(
        kind: NmIntent, intent: payload.fromFlatty(IntentMsg)
      )
    of NmLobby:
      result = NetMessage(
        kind: NmLobby, lobby: payload.fromFlatty(LobbyMsg)
      )
    of NmSlotGrant:
      result = NetMessage(
        kind: NmSlotGrant, slotGrant: payload.fromFlatty(SlotGrantMsg)
      )
    of NmStart:
      result = NetMessage(
        kind: NmStart, start: payload.fromFlatty(StartMsg)
      )
    of NmTicks:
      result = NetMessage(
        kind: NmTicks, ticks: payload.fromFlatty(TicksMsg)
      )
    of NmIntentResult:
      result = NetMessage(
        kind: NmIntentResult,
        intentResult: payload.fromFlatty(IntentResultMsg)
      )
    of NmBye:
      result = NetMessage(kind: NmBye, bye: payload.fromFlatty(ByeMsg))
    of NmPing:
      result = NetMessage(
        kind: NmPing, ping: payload.fromFlatty(PingMsg)
      )
    of NmPong:
      result = NetMessage(
        kind: NmPong, pong: payload.fromFlatty(PingMsg)
      )
  except CatchableError as error:
    # flatty raises FlattyError (a CatchableError) on malformed input.
    # Catch the base type so this compiles against any flatty version -
    # the nimble-installed flatty in the game image does not export the
    # FlattyError symbol, while sibling dev checkouts do.
    fail("malformed " & $kind & " message: " & error.msg)
  except IndexDefect, RangeDefect, OverflowDefect:
    fail("truncated " & $kind & " message")

proc validateHello*(hello: HelloMsg) =
  ## Rejects a peer speaking another protocol or game before any state
  ## is touched.
  if hello.game != NetGameId:
    fail("peer is playing '" & hello.game & "', not '" & NetGameId & "'")
  if hello.protocol != NetProtocolVersion:
    fail(
      "peer protocol " & $hello.protocol & " does not match " &
      $NetProtocolVersion
    )
  if hello.simVersion != ReplayGameVersion:
    fail(
      "peer simulation version " & $hello.simVersion &
      " does not match " & $ReplayGameVersion
    )
  if hello.name.len > 24:
    fail("player name is too long")
