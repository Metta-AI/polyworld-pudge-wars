## Coworld game host: native simulation, BASIC league or JSON human play.
##
## Build with -d:basicLeague for runner-staged BASIC seats. Otherwise policies
## speak walk_to / hook_to /
## blink_to JSON; those become human intents on the same record-then-apply
## path as ./pw. Player observations are fog-clipped like BASIC bots.

import
  std/[
    httpclient, json, locks, math, monotimes, os, sequtils, strutils, tables,
    times, uri, posix
  ],
  mummy, mummy/routers,
  polyworld/pathing,
  content, maps, sim, bots, replays, fog, netproto, fileplayers, pacing

const
  PlayerHtml = staticRead("coworld_player.html")
  GlobalHtml = staticRead("coworld_global.html")
  ArenaJs = staticRead("coworld_arena.js")
  UserAgent = "coworld-pudgewars/0.3"
  HttpTimeoutMs = 60_000
  LeagueRuntime = defined(basicLeague)

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
  game*: Game
    ## Exported with observation/applyAction so the protocol test can
    ## drive the JSON surface without a socket.
  tokens: seq[string]
  playerNames: seq[string]
  maxTicks*: int32
  killGoal: int32
  seed: int32
  fogOn* = true
  waitForLlm = true
  connectTimeoutSec = 180.0
  resultsUri = ""
  replayUri = ""
  resultsMethod = "PUT"
  replayMethod = "PUT"
  started = false
  done = false
  replayMode = false
  humanPlay = false
  fileSeats: FilePlayers
  lastAccepted: seq[JsonNode]
    ## Per-seat echo of the intents just applied. Sent on the next
    ## observation so a JSON policy can trust hookTo/blinkTo.
  sentKeys: seq[Table[string, bool]]
    ## Per seat: action keys the reply carried since the last snapshot;
    ## true when that key held a JSON array. Filters the accepted echo
    ## to what the seat actually sent (idle auto-acquire stays silent)
    ## and shapes array purchases as arrays.
  rotMatched: seq[bool]
    ## The seat sent rot:<bool> that already matched the sim state, so
    ## no toggle was queued; the echo still answers accepted.rot=true.

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

proc pudgeJson(world: World, pudge: Pudge, slot: int): JsonNode =
  let
    pos = tileCoord(pudge.position)
    home = pudge.spawnTile
    blinkReady =
      pudge.blinkCooldown <= 0 and pudge.windupTicks <= 0 and
      pudge.hookedBy == 0 and not world.rotAffected(pudge)
    buffOrd =
      if pudge.buffTicks > 0: int(pudge.buffKind.ord) + 1 else: 0
  var upgrades = newJArray()
  for kind in UpgradeKind:
    upgrades.add %pudge.upgrades[kind]
  var itemRanks = newJArray()
  for item in ShopBoots .. ShopWard:
    itemRanks.add %pudge.itemRank[item]
  # The seat's last print line: the intent bubble the arena overlay
  # draws. say_tick lets a client fade stale lines.
  var sayNode = newJNull()
  var sayTick = -1'i32
  if game != nil and slot >= 0 and slot < game.botSpeech.len and
      game.botSpeech[slot].text.len > 0:
    sayNode = %game.botSpeech[slot].text
    sayTick = game.botSpeech[slot].tick
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
    "shield": max(pudge.shieldTicks, 0),
    "hook_ready": pudge.hookCooldown <= 0 and pudge.windupTicks <= 0,
    "blink_ready": blinkReady,
    "rot": pudge.rotOn,
    "layer": pudge.layer,
    "gold": pudge.gold,
    "points": pudge.points,
    "in_shop": pudge.inOwnShop,
    "kills": pudge.kills,
    "in_river": pudge.inRiver,
    "home_x": home.x,
    "home_y": home.z,
    "upgrades": upgrades,
    "item_ranks": itemRanks,
    "items": itemRanks,
    "ward_restock": max(pudge.wardCooldown, 0),
    "buff": buffOrd,
    "say": sayNode,
    "say_tick": sayTick
  }

proc hookJson(world: World, hook: Hook): JsonNode =
  let
    pos = tileCoord(hook.position)
    owner = world.pudgeIndex(hook.ownerId)
    ownerSlot = if owner >= 0: owner else: 0
  %*{
    "owner": ownerSlot,
    "owner_id": hook.ownerId,
    "team": hook.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "victim": hook.victimId,
    "flying": hook.phase == HookFlying,
    "lightning": hook.lightning
  }

proc fireJson(patch: FirePatch): JsonNode =
  let pos = tileCoord(patch.position)
  %*{
    "owner_id": patch.ownerId,
    "team": patch.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "ticks": patch.ticksLeft
  }

proc runeJson(rune: Rune): JsonNode =
  let pos = tileCoord(rune.position)
  %*{
    "id": rune.id,
    "kind": rune.kind.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3)
  }

proc runeNextJson(world: World): JsonNode =
  ## Public drop clock. Same numbers BASIC `runeSoon` / `runeNext*` see.
  let soon = runeSoonTicks(world)
  if soon <= 0:
    return %*{"soon": 0, "kind": -1, "x": -1, "y": -1}
  %*{
    "soon": soon,
    "kind": world.nextRuneKind.ord,
    "x": RiverCenterX,
    "y": world.nextRuneZTile
  }

proc propJson(prop: Prop): JsonNode =
  let pos = tileCoord(prop.propCenter)
  %*{
    "id": prop.id,
    "kind":
      case prop.kind
      of PropWall: "wall"
      of PropMine: "mine"
      of PropWard: "ward",
    "team": prop.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "hp": max(prop.hp, 0)
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

proc intentActionKey(kind: IntentKind): string =
  case kind
  of IntentWalk: "walk_to"
  of IntentHook, IntentHookFine: "hook_to"
  of IntentBlink, IntentBlinkFine: "blink_to"
  of IntentGrapple, IntentGrappleFine: "grapple_to"
  of IntentAttack: "attack_target"
  of IntentBuy: "buy_upgrade"
  of IntentBuyPower: "buy_power"
  of IntentStop: "halt"
  of IntentPing: "ping"
  of IntentPlaceWall: "place_wall"
  of IntentPlaceMine: "place_mine"
  of IntentPlaceWard: "place_ward"
  of IntentRot: "rot"
  of IntentCheat: ""

proc hookInFlight(world: World, ownerId: int32): bool =
  for hook in world.hooks:
    if hook.ownerId == ownerId and hook.phase != HookIdle:
      return true
  false

proc intentRejectReason(slot: int, kind: IntentKind, itemId = 0'i32): string =
  ## Short token for a rejected intent. Read after apply, so the
  ## butcher state is the same as before a failed command.
  if slot < 0 or slot >= game.world.pudges.len:
    return "rejected"
  let hero = game.world.pudges[slot]
  if hero.state == Dying:
    return "dead"
  case kind
  of IntentHook, IntentHookFine:
    if hero.windupTicks > 0: "casting"
    elif hookInFlight(game.world, hero.id): "flight"
    elif hero.hookCooldown > 0: "cooldown"
    else: "rejected"
  of IntentBlink, IntentBlinkFine:
    if game.world.rotAffected(hero): "rot"
    elif hero.windupTicks > 0: "casting"
    elif hero.hookedBy != 0: "hooked"
    elif hero.blinkCooldown > 0: "cooldown"
    else: "rejected"
  of IntentGrapple, IntentGrappleFine:
    if hero.windupTicks > 0: "casting"
    elif hookInFlight(game.world, hero.id): "flight"
    elif hero.grappleCooldown > 0: "cooldown"
    else: "rejected"
  of IntentBuy:
    if hero.points <= 0: "points"
    else: "maxed"
  of IntentBuyPower:
    if not hero.inOwnShop: "shop"
    elif itemId == int32(ShopWard.ord):
      if hero.wardCooldown > 0: "cooldown"
      elif hero.itemRank[ShopWard] >= WardChargeMax: "held"
      else: "rejected"
    elif hero.gold <= 0: "gold"
    else: "rejected"
  of IntentPlaceWall, IntentPlaceMine:
    if hero.inRiver: "river"
    else: "rejected"
  of IntentPlaceWard:
    "rejected"
  of IntentRot:
    "rejected"
  else:
    "rejected"

proc sizeEchoState(seats: int) =
  if lastAccepted.len != seats:
    lastAccepted.setLen(seats)
  if sentKeys.len != seats:
    sentKeys.setLen(seats)
  if rotMatched.len != seats:
    rotMatched.setLen(seats)

proc markSent(slot: int, key: string, isArray: bool) =
  ## Remembers one action key from this seat's reply so the accepted
  ## echo answers exactly what the seat asked. Arrays echo as arrays.
  sizeEchoState(game.world.pudges.len)
  if slot >= 0 and slot < sentKeys.len:
    sentKeys[slot][key] = isArray

proc snapshotAccepted*() =
  ## Capture this tick's intentResults before WASM acks clear them.
  ## Only keys the seat sent are echoed (the sim's idle auto-acquire
  ## stays silent); a walk/attack/halt replaced by a later order in
  ## the same reply window echoes only the surviving order.
  let seats = game.world.pudges.len
  sizeEchoState(seats)
  for i in 0 ..< seats:
    lastAccepted[i] = newJObject()
  for res in game.intentResults:
    let
      key = intentActionKey(res.kind)
      slot = int(res.slot)
    if key.len == 0 or slot < 0 or slot >= seats:
      continue
    if key notin sentKeys[slot]:
      continue
    let answer =
      if res.accepted: %true
      else: %intentRejectReason(slot, res.kind, res.a)
    if sentKeys[slot][key]:
      if not lastAccepted[slot].hasKey(key):
        lastAccepted[slot][key] = newJArray()
      lastAccepted[slot][key].add answer
    else:
      lastAccepted[slot][key] = answer
  for slot in 0 ..< seats:
    if rotMatched[slot] and not lastAccepted[slot].hasKey("rot"):
      # rot:<bool> already matched the sim state; nothing was queued,
      # but the ask is satisfied.
      lastAccepted[slot]["rot"] = %true
    rotMatched[slot] = false
    sentKeys[slot].clear()

proc acceptedEcho(slot: int): JsonNode =
  if slot >= 0 and slot < lastAccepted.len and lastAccepted[slot] != nil:
    lastAccepted[slot]
  else:
    newJObject()

proc printEcho(slot: int): JsonNode =
  if slot >= 0 and slot < game.botSpeech.len and
      game.botSpeech[slot].text.len > 0:
    %game.botSpeech[slot].text
  else:
    newJNull()

proc observation*(slot: int, final = false): JsonNode =
  ## Fog-clipped like BASIC `objectCount` / the renderer. `fogOn` off
  ## is the omniscient spectator (`team < 0`).
  let
    world = game.world
    viewer = world.pudges[slot]
    teamOrd = if fogOn: viewer.team.ord else: -1
  var visiblePudges = newJArray()
  var visibleHooks = newJArray()
  var visibleRunes = newJArray()
  var visibleProps = newJArray()
  var visibleFires = newJArray()
  for i, pudge in world.pudges:
    if fogShownPudgeTeam(world, teamOrd, pudge):
      visiblePudges.add pudgeJson(world, pudge, i)
  for hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if teamOrd >= 0 and not fogCanSee(world, viewer.team, hook.position):
      continue
    visibleHooks.add hookJson(world, hook)
  for rune in world.runes:
    if teamOrd >= 0 and not fogCanSee(world, viewer.team, rune.position):
      continue
    visibleRunes.add runeJson(rune)
  for prop in world.props:
    if not prop.alive:
      continue
    if teamOrd >= 0 and not propVisibleTo(prop, viewer.team):
      continue
    if prop.kind == PropWall and teamOrd >= 0 and
        not fogCanSee(world, viewer.team, prop.propCenter):
      continue
    visibleProps.add propJson(prop)
  for patch in world.firePatches:
    # Lightning fire shows through fog of war, matching the renderer.
    visibleFires.add fireJson(patch)
  # The same flat, fog-clipped list BASIC objectCount/objectAt walks:
  # own team in roster order, then visible props. kind matches BASIC
  # objectKind (1 butcher, 2 wall, 3 mine, 4 ward).
  var objectsNode = newJArray()
  var worldObject: WorldObject
  for i in 0 ..< worldObjectCount(world, viewer.id):
    if not worldObjectAt(world, viewer.id, i, worldObject):
      continue
    let objPos = tileCoord(worldObject.position)
    objectsNode.add %*{
      "id": worldObject.id,
      "kind": worldObject.kind,
      "team": worldObject.team.ord,
      "x": round(objPos.x, 3),
      "y": round(objPos.y, 3),
      "hp": max(worldObject.hp, 0),
      "alive": worldObject.alive,
      "layer": worldObject.layer,
      "hooked": worldObject.hooked,
      "shielded": worldObject.shielded,
      "rot": worldObject.rotting
    }
  var pingNode = newJNull()
  var ping: Ping
  if world.latestTeamPing(viewer.team, ping):
    pingNode = %*{
      "x": ping.x,
      "y": ping.y,
      "by": ping.byId,
      "tick": ping.tick,
      "age": max(world.tick - ping.tick, 0)
    }
  result = %*{
    "type": if final: "final" else: "observation",
    "game_version": ReplayGameVersion,
    "slot": slot,
    "tick": world.tick,
    "max_ticks": maxTicks,
    "kill_goal": world.killGoal,
    "width": GridTiles,
    "height": GridTiles,
    "river_west": RiverWestX,
    "river_east": RiverEastX,
    "play_west_max": PlayWestMax,
    "play_east_min": PlayEastMin,
    "fog": fogOn,
    "self": pudgeJson(world, viewer, slot),
    "accepted": acceptedEcho(slot),
    "print": printEcho(slot),
    "visible": {
      "pudges": visiblePudges,
      "hooks": visibleHooks,
      "runes": visibleRunes,
      "props": visibleProps,
      "fires": visibleFires
    },
    "objects": objectsNode,
    "ally_ping": pingNode,
    "rune_next": runeNextJson(world),
    "score": scoreNode(world),
    "done": final or world.gameOver or done,
    "winner": winnerName(world)
  }

proc globalSnapshot(): JsonNode =
  let world = game.world
  var pudges = newJArray()
  var hooks = newJArray()
  var fires = newJArray()
  for i, pudge in world.pudges:
    pudges.add pudgeJson(world, pudge, i)
  for hook in world.hooks:
    if hook.phase != HookIdle:
      hooks.add hookJson(world, hook)
  for patch in world.firePatches:
    fires.add fireJson(patch)
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
    "play_west_max": PlayWestMax,
    "play_east_min": PlayEastMin,
    "score": scoreNode(world),
    "rune_next": runeNextJson(world),
    "pudges": pudges,
    "hooks": hooks,
    "fires": fires,
    "player_names": names,
    "started": started,
    "paused": false,
    "tick_rate": TickRate,
    "wall_tick_rate": wallTickRate(game.humanPaced),
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

proc queueIntents(slot: int, kind: IntentKind, node: JsonNode, key: string) =
  ## One int or an array of ints, each becoming a queued intent `a`.
  if not node.hasKey(key):
    return
  let value = node[key]
  markSent(slot, key, value.kind == JArray)
  proc one(item: JsonNode) =
    queueIntent(
      game,
      HumanIntent(slot: int32(slot), kind: kind, a: int32(item.getInt))
    )
  if value.kind == JArray:
    for item in value:
      one(item)
  else:
    one(value)

proc applyAction*(slot: int, node: JsonNode) =
  if slot < 0 or slot >= game.world.pudges.len:
    return
  if node.kind != JObject:
    return
  if node.hasKey("halt") and node["halt"].getBool:
    markSent(slot, "halt", false)
    queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentStop))
    return
  queueIntents(slot, IntentBuy, node, "buy_upgrade")
  queueIntents(slot, IntentBuyPower, node, "buy_power")
  if node.hasKey("blink_to") and node["blink_to"].kind == JArray and
      node["blink_to"].len >= 2:
    markSent(slot, "blink_to", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentBlinkFine,
        a: toFine(node["blink_to"][0].getFloat),
        b: toFine(node["blink_to"][1].getFloat)
      )
    )
  if node.hasKey("walk_to") and node["walk_to"].kind == JArray and
      node["walk_to"].len >= 2:
    markSent(slot, "walk_to", false)
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
    markSent(slot, "hook_to", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentHookFine,
        a: toFine(node["hook_to"][0].getFloat),
        b: toFine(node["hook_to"][1].getFloat)
      )
    )
  if node.hasKey("attack_target"):
    markSent(slot, "attack_target", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentAttack,
        a: int32(node["attack_target"].getInt)
      )
    )
  if node.hasKey("rot"):
    if node["rot"].getBool != game.world.pudges[slot].rotOn:
      markSent(slot, "rot", false)
      queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentRot))
    else:
      # Already in the asked state: nothing to queue, nothing to
      # flicker. The next accepted echo still answers rot=true.
      sizeEchoState(game.world.pudges.len)
      rotMatched[slot] = true
  elif node.hasKey("rot_toggle") and node["rot_toggle"].getBool:
    markSent(slot, "rot", false)
    queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentRot))
  if node.hasKey("print") and node["print"].kind == JString:
    let line = node["print"].getStr
    if line.len > 0:
      if game.botSpeech.len <= slot:
        game.botSpeech.setLen(slot + 1)
      game.botSpeech[slot] = BotSpeech(text: line, tick: game.world.tick)
  if node.hasKey("place_wall") and node["place_wall"].kind == JArray and
      node["place_wall"].len >= 2:
    markSent(slot, "place_wall", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceWall,
        a: toTile(node["place_wall"][0].getFloat),
        b: toTile(node["place_wall"][1].getFloat)
      )
    )
  if node.hasKey("place_mine") and node["place_mine"].kind == JArray and
      node["place_mine"].len >= 2:
    markSent(slot, "place_mine", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceMine,
        a: toTile(node["place_mine"][0].getFloat),
        b: toTile(node["place_mine"][1].getFloat)
      )
    )
  if node.hasKey("place_ward") and node["place_ward"].kind == JArray and
      node["place_ward"].len >= 2:
    markSent(slot, "place_ward", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceWard,
        a: toTile(node["place_ward"][0].getFloat),
        b: toTile(node["place_ward"][1].getFloat)
      )
    )
  if node.hasKey("ping") and node["ping"].kind == JArray and
      node["ping"].len >= 2:
    markSent(slot, "ping", false)
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
      if humanPlay and i notin fileSeats.humanSlots:
        return -1
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
    let connected = i < gameConnected.len and gameConnected[i]
    let human = if humanPlay: i in fileSeats.humanSlots else: connected
    result[i] = NetSeat(
      name: if i < playerNames.len: playerNames[i] else: "",
      human: human,
      connected: connected or (humanPlay and not human)
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
  sendBinary(ws, packStart(netSetup(), game.humanPaced))
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
  if not game.humanPaced:
    game.humanPaced = true
    # Existing spectators/players must change pace too when a human joins
    # an already-running policy match. Keep this flag through disconnects.
    withLock sessionLock:
      for peer, other in sessions:
        if other.kind == SkGame:
          sendBinary(peer, packLobby(netSeatRoster(), started, game.humanPaced))
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
        applySeatLabels(game, playerNames)
      sendBinary(ws, packSlotGrant(int32(slot), message.hello.token, ""))
      echo "coworld ws seat ", slot, " joined: ", session.name
    else:
      sendBinary(ws, packSlotGrant(SpectatorSlot, "", "unknown seat token"))
    sendGameStartAndBacklog(ws, session)
    sendBinary(ws, packLobby(netSeatRoster(), started, game.humanPaced))
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
    sendBinary(ws, packLobby(netSeatRoster(), started, game.humanPaced))
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
      # The runner probes /global before exposing the human's client.
      # Publish the waiting state without waiting for every player to join.
      withLock sessionLock:
        if event.ws in sessions and sessions[event.ws].kind == SkGlobal:
          sendText(event.ws, $globalSnapshot())
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
  if humanPlay:
    result = tokens.len - fileSeats.humanSlots.len
  withLock sessionLock:
    for i in 0 ..< tokens.len:
      if (i < playerConnected.len and playerConnected[i]) or
          (i < gameConnected.len and gameConnected[i]):
        inc result

proc artifactPath*(uri: string): string =
  ## Resolves a `file://` artifact URI to a local path. `file:///coworld/replay`
  ## and the host-form `file://coworld/replay` both land on `/coworld/replay`.
  let parsed = parseUri(uri)
  if parsed.scheme != "file":
    return uri
  result = decodeUrl(parsed.path)
  if parsed.hostname.len > 0:
    if result.len == 0 or result == "/":
      result = "/" & parsed.hostname
    elif not result.startsWith("/"):
      result = "/" & parsed.hostname & "/" & result
    else:
      result = "/" & parsed.hostname & result

proc readBytes(uri: string): string =
  let parsed = parseUri(uri)
  if parsed.scheme in ["http", "https"]:
    let client = newHttpClient(timeout = HttpTimeoutMs)
    client.headers["User-Agent"] = UserAgent
    try:
      return client.getContent(uri)
    finally:
      client.close()
  readFile(artifactPath(uri))

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
  let path = artifactPath(uri)
  let dir = path.parentDir
  if dir.len > 0:
    createDir(dir)
  writeFile(path, data)

proc writeReplayArtifact() =
  ## The runner treats a missing `/coworld/replay` after a zero exit as
  ## `replay_missing`, even when results.json landed. Always write bytes.
  if replayUri.len == 0:
    return
  if game.recordingError.len > 0:
    echo "replay recording error: ", game.recordingError
  var bytes = ""
  if game.recorder != nil:
    try:
      bytes = encodeCoworldReplay(game.recorder.data)
    except CatchableError as error:
      echo "replay encode failed: ", error.msg
      try:
        var fallback = game.recorder.data
        fallback.actions.setLen(0)
        fallback.hashes.setLen(0)
        bytes = encodeCoworldReplay(fallback)
        echo "replay wrote setup-only fallback"
      except CatchableError as error2:
        echo "replay fallback encode failed: ", error2.msg
  try:
    writeBytes(
      replayUri,
      bytes,
      "application/octet-stream",
      replayMethod
    )
    if bytes.len == 0:
      echo "replay saved empty placeholder"
    else:
      echo "replay saved ", bytes.len, " bytes"
  except CatchableError as error:
    echo "replay write failed: ", error.msg

proc envMethod(name, fallback: string): string =
  let value = getEnv(name, fallback).toUpperAscii()
  if value in ["PUT", "POST"]:
    return value
  fallback

proc resultsJson(): JsonNode =
  let world = game.world
  var scores = newJArray()
  var perSeat = newJArray()
  let
    west = world.teamKills[WestTeam.ord]
    east = world.teamKills[EastTeam.ord]
  for i, pudge in world.pudges:
    let
      mine = if pudge.team == WestTeam: west else: east
      theirs = if pudge.team == WestTeam: east else: west
    # Win or fail per seated agent: 1 if that bank is ahead, else 0 (draws fail).
    scores.add %(if mine > theirs: 1.0 else: 0.0)
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
  if LeagueRuntime:
    # Artifacts must be complete before results become visible to collection.
    if game.recordingError.len > 0:
      raise newException(FilePlayerError, "Replay recording failed")
    let replay = encodeCoworldReplay(game.recorder.data)
    fileSeats.finish(game)
    writeAtomic(localPath(replayUri), replay)
    writeAtomic(localPath(resultsUri), $resultsJson())
    if not humanPlay: return
  else:
    writeReplayArtifact()
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
  if LeagueRuntime and not humanPlay:
    request.respond(200, htmlHeaders(), GlobalHtml)
  else:
    let clientUrl = getEnv("PUDGE_WARS_CLIENT_URL")
    doAssert clientUrl.len > 0, "PUDGE_WARS_CLIENT_URL must point to the matching WASM build"
    request.respond(200, htmlHeaders(), PlayerHtml.replace("__WASM_CLIENT_URL__", $(%clientUrl)))

proc globalPageHandler(request: Request) {.gcsafe.} =
  {.gcsafe.}:
    if replayMode or (LeagueRuntime and not humanPlay):
      request.respond(200, htmlHeaders(), GlobalHtml)
    else:
      playerPageHandler(request)

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
  if LeagueRuntime:
    if node.kind != JObject or not node.hasKey("tokens") or
        node["tokens"].kind != JArray or not node.hasKey("players") or
        node["players"].kind != JArray or
        node["players"].len != node["tokens"].len or
        not node.hasKey("seed") or node["seed"].kind != JInt or
        node["seed"].getBiggestInt < low(int32) or
        node["seed"].getBiggestInt > high(int32) or
        not node.hasKey("max_ticks") or node["max_ticks"].kind != JInt or
        node["max_ticks"].getBiggestInt notin 1'i64 .. 40000'i64 or
        not node.hasKey("kill_goal") or node["kill_goal"].kind != JInt or
        node["kill_goal"].getBiggestInt notin 1'i64 .. 40'i64 or
        not node{"fog"}.getBool(true):
      raise newException(FilePlayerError, "Invalid BASIC league configuration")
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
  waitForLlm = node{"wait_for_llm"}.getBool(true)
  connectTimeoutSec = node{"player_connect_timeout_seconds"}.getFloat(180.0)
  if node.hasKey("seed") and node["seed"].kind != JNull:
    seed = int32(node["seed"].getInt)
  else:
    seed = int32((epochTime() * 1000).int64 and 0x7fff_ffff)

proc bootGame() =
  if tokens.len < DuelPudgeCount or tokens.len > MaxPudgeCount or
      tokens.len mod 2 != 0:
    raise newException(
      CatchableError,
      "Fresh Meat Coworld seats 2, 4, 6, 8, or 10 butchers"
    )
  let
    duel = tokens.len == DuelPudgeCount
    n = if duel: TeamSize else: tokens.len div 2
  let gameMap = generateMap(seed, n)
  game = newGame(
    gameMap, maxTicks, false, ReplayData(), killGoal, RunePeriodTicks,
    duel
  )
  game.humanSlots.setLen(0)
  if humanPlay:
    game.humanSlots = fileSeats.humanSlots
    game.humanPaced = true
  elif not LeagueRuntime:
    for i in 0 ..< game.world.pudges.len:
      game.humanSlots.add i
  applySeatLabels(game, playerNames)
  playerSockets.setLen(tokens.len)
  playerConnected.setLen(tokens.len)
  gameSockets.setLen(tokens.len)
  gameConnected.setLen(tokens.len)
  echo "coworld map seed=", seed, " seats=", tokens.len, " kill_goal=",
    game.world.killGoal, " max_ticks=", maxTicks

proc loadEnv() =
  replayMode = existsEnv("COGAME_LOAD_REPLAY_URI")
  # People join a league host two ways: a hosted play session, or a league
  # lobby episode whose runner staged a play-seats roster with human seats
  # (a ranked match a person plays in). Either way the host runs the human
  # clock and opens /ws.
  humanPlay = LeagueRuntime and getEnv("COGAME_PLAY_SESSION_ID").len > 0
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
  if LeagueRuntime:
    discard localPath(resultsUri)
    discard localPath(replayUri)
    fileSeats = openFilePlayers(parseJson(readFile(localPath(
      getEnv("COGAME_PLAYER_SEATS_URI")))), tokens.len,
      getEnv("COGAME_PLAYER_FAILURE_URI"), allowHumans = true)
    if fileSeats.humanSlots.len > 0:
      humanPlay = true

proc completedSignal(signal: cint) {.noconv.} =
  exitnow(QuitSuccess)

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
  if not LeagueRuntime:
    router.get("/player", upgradePlayer)
  router.get("/global", upgradeGlobal)
  if not LeagueRuntime or humanPlay:
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
  if LeagueRuntime:
    let loaded = fileSeats.load(game)
    if humanPlay and not loaded:
      quit(QuitFailure)
    if loaded and not humanPlay:
      started = true
      game.recorder = initReplayRecorder(currentSetup(game, uint32(maxTicks)))
      game.replayPlayer = ReplayPlayer(data: game.recorder.data)
      while game.world.tick < maxTicks and not game.world.gameOver and
          game.recordingError.len == 0:
        tickWorld(game, proc() = runBotDecisions(game))
        if waitForLlm:
          game.waitForBotRequests()
        fileSeats.captureErrors(game)
        if game.world.tick mod 32 == 0:
          drainInbound()
          broadcastGlobal()
      finishMatch()
    if not loaded or not humanPlay:
      # Collection probes health and reads artifacts before stopping the host.
      discard posix.signal(SIGTERM, completedSignal)
      while true:
        drainInbound()
        sleep(50)
      return
  let deadline = epochTime() + connectTimeoutSec
  while connectedPlayerCount() < tokens.len and epochTime() < deadline:
    drainInbound()
    sleep(50)
  started = true
  echo "starting with ", connectedPlayerCount(), "/", tokens.len, " players"
  applySeatLabels(game, playerNames)
  game.recorder = initReplayRecorder(currentSetup(game, uint32(maxTicks)))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  announceGameStart()
  broadcastPlayers()
  broadcastGlobal()
  var nextAt = getMonoTime()
  var steps = 0
  while steps < int(maxTicks) and not game.world.gameOver and
      game.recordingError.len == 0:
    drainInbound()
    tickWorld(game, proc() = runBotDecisions(game))
    inc steps
    if humanPlay:
      if waitForLlm: game.waitForBotRequests()
      fileSeats.captureErrors(game)
    # WASM humans first: they follow the tape and predict locally, so
    # the confirmed slice must leave the moment a tick is hashed. Never
    # let a late browser stall the clock. Human matches run at 28 ticks per second.
    streamGameTicks()
    snapshotAccepted()
    forwardGameResults()
    broadcastPlayers()
    if steps mod 4 == 0:
      broadcastGlobal()
    nextAt = nextAt + initDuration(nanoseconds = wallTickNanoseconds(game.humanPaced))
    let now = getMonoTime()
    if now < nextAt:
      # Spend the rest of the clock slice draining JSON replies, so an
      # answer to this tick's observation is queued before the next
      # tick runs: the documented fixed 1-tick apply latency. A late
      # reply just misses the window (sticky last order); the clock
      # never moves for it.
      while getMonoTime() < nextAt:
        drainInbound()
        sleep(1)
    else:
      nextAt = now
  finishMatch()

when isMainModule:
  main()
