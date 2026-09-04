## Pudge Wars simulation: butchers, Meat Hook, melee, and the tick.
##
## Planar motion uses Q16.16 tile-space bodies. Combat ranges and replay
## integers stay on `WorldPoint`. Walking carries momentum: each butcher
## keeps a persistent velocity whose direction carves toward the order at
## `VelTurnRate` while its speed tracks the order under `MoveAccel` and
## `MoveBrake`, with arrive braking onto the clicked point. Turns keep
## speed; stops and behind-the-back reversals shed it. Walls and bodies
## zero the blocked component instead of storing it. Living butchers are
## solid circles; walking rejects overlap and
## dumps/respawns push coincident bodies apart. Flying hooks rebound
## off blocked land, bounce trees, the fountain, and the map edge with
## a curved heading, without resetting leftover range. An empty retract
## retraces the chain and can still latch. Opposing shuriken disks
## cancel both hooks without damage.
## This module must not import anything that returns a float.

import
  polyworld/[
    basic, bodies, fixed, hashes, noises, pathing, profiles, rngs, tapes
  ],
  cheats,
  content,
  maps,
  replays

const
  runClip* = 0
  idleClip* = 1
  deathClip* = 2
  attackClip* = 3
  victoryClip* = 4
  FirstPudgeId* = 1'i32
  FirstHookId* = 100'i32
  FirstRuneId* = 1000'i32
  VelTurnRate = 0.35'fx
    ## Radians per tick the walk velocity may rotate: a 90° redirect
    ## carves in ~4.5 ticks (0.14 s) without losing speed. Raising this
    ## weakens momentum; the stop/reversal weight lives in `MoveBrake`.
  BodyTurnRate = 0.35'fx
    ## Per-tick facing turn rate. Cosmetic under momentum locomotion:
    ## the velocity vector sets the travel direction and this only eases
    ## the model's visual heading toward it. Matches `VelTurnRate` so
    ## the mesh does not moonwalk through carved turns.
  WalkStickyTiles = 1'i32
  SeparatePasses = 8
  MaxHookBounces = 12
  MaxHookFlySteps = 32
  MaxWorldPings = 8
    ## Newest team pings kept for bots and the HUD.
  MaxQueuedIntents = 64
    ## Human intents buffered between hero turns before the oldest drop.

type
  WorldPoint* = object
    x*, y*, z*: int32
  Heading* = object
    x*, z*: int32
  HeroVm* = ref object
    runtime*: Runtime
    limits*: Limits
    ready*: bool
    failed*: bool
    lastError*: string
    decisions*: int
    lastWork*, lastInstructions*: int64

  Pudge* = object
    id*: int32
    team*: Team
    slot*: int
    lobbySeat*: int32
      ## The lobby seat this butcher answers to (stable across
      ## disabled-seat compaction).
    layer*: int32
    position*: WorldPoint
    spawnPosition*: WorldPoint
    facing*: Heading
    body*: Body
    hp*: int32
    maxHp*: int32
    state*: PudgeState
    kills*: int32
    deaths*: int32
    points*: int32
    gold*: int32
      ## Shop currency from kills and denies; spent at the base pad.
    streak*: int32
      ## Enemy kills since last death. Hashed only when any butcher
      ## has a non-zero streak, so fair pre-spree ticks keep the old
      ## hash. Own-streak and shutdown gold read this.
    spent*: int32
    itemRank*: array[ShopBoots..ShopMine, int32]
      ## Permanent shop families: 0 unowned, 1..ItemMaxRank in inventory.
    upgrades*: array[UpgradeKind, int32]
    hookCooldown*: int32
    windupTicks*: int32
    windupGrapple*: bool
      ## True when the pending cast is the E-grapple, not the hook.
    grappleCooldown*: int32
      ## Cast-point ticks left before the pending hook leaves the hand.
    blinkCooldown*: int32
      ## Ticks until F-blink is ready again.
    justBlinked*: bool
      ## Transient vanish/puff for the blink tick; hashed.
    blinkFrom*: WorldPoint
      ## Origin of this tick's blink, for VFX. Not hashed.
    rotOn*: bool
      ## Rot aura is emitting. Toggle; no cooldown.
    rotTicks*: int32
      ## Ticks accumulated toward the next rot pulse. Hashed.
    wallCooldown*: int32
      ## Ticks until the next palisade drop.
    mineCooldown*: int32
      ## Ticks until the next mine drop.
    windupAimX*: int32
      ## Pending hook aim in `FineAimScale` units from the map origin.
    windupAimY*: int32
    shieldTicks*: int32
      ## Spawn-protection ticks left; broken early by acting.
    hooksThrown*: int32
    hooksLanded*: int32
    headshotCount*: int32
    denyCount*: int32
    attackTargetId*: int32
    swingTicks*: int32
    damageLanded*: bool
    enteredRiver*: bool
    justHeadshot*: bool
    justGrabbed*: bool
    justChunked*: bool
    lastKillTick*: int32
      ## Tick of the last credited enemy kill. Multi-kill window only;
      ## never hashed.
    multiKill*: int32
      ## Rapid enemy kills inside `MultiKillWindowTicks`. Display only.
    justStreak*: int32
      ## Named streak (3+) announced this tick; else 0. Not hashed.
    justShutdown*: int32
      ## Victim's broken streak (3+) this tick; else 0. Not hashed.
    justMulti*: int32
      ## Rapid-kill count (2+) announced this tick; else 0. Not hashed.
    justFirstBlood*: bool
      ## First enemy kill of the match this tick. Not hashed.
    justBounty*: int32
      ## Gold paid to this butcher for enemy kills this tick. Not hashed.
    animClip*: int
    animTicks*: int32
    deathTicks*: int32
    drownTicks*: int32
    lastHurtBy*: int32
    hasMoveTarget*: bool
    moveX*: int32
    moveZ*: int32
    velX*: int32
      ## Persistent walk velocity in world units per tick. Orders steer
      ## it under the `MoveAccel`/`MoveBrake` budget; walls and occupied
      ## circles zero the blocked component.
    velZ*: int32
    hookedBy*: int32
    buffKind*: RuneKind
      ## Active rune power; meaningful only while `buffTicks` > 0.
    buffTicks*: int32
      ## Rune buff ticks left; one slot, a new pickup overwrites.
    runesTaken*: int32
    justRune*: bool
      ## Transient pickup flag for client feedback; never hashed.
    cheatFlags*: int32
      ## Bitfield of live WC3-style cheats (`CheatFlagGod`,
      ## `CheatFlagMana`). Hashed only when any butcher has one set,
      ## so fair matches keep the same hash as pre-cheat builds.

  Hook* = object
    id*: int32
    ownerId*: int32
    team*: Team
    phase*: HookPhase
    position*: WorldPoint
    origin*: WorldPoint
    prior*: WorldPoint
    heading*: Heading
    traveled*: int32
    range*: int32
      ## Outbound budget. Remaining flight is `range - traveled`.
      ## A successful blink by the owner adds the hop distance here.
    speed*: int32
    peakSpeed*: int32
    radius*: int32
    damage*: int32
    isGrapple*: bool
      ## E-grapple: latches solids and yanks the caster; no damage.
    mighty*: bool
      ## Thrown under the Big Hook rune: wins clashes outright instead
      ## of trading. The buffed disk plows through lesser chains.
    grappleLatched*: bool
      ## True once the grapple head stuck to a solid face.
    victimId*: int32
    bounces*: seq[WorldPoint]

  Prop* = object
    ## One placed palisade or mine. Tile-snapped, sim-deterministic.
    id*: int32
    kind*: PropKind
    ownerId*: int32
    team*: Team
    tileX*, tileZ*: int32
    hp*, maxHp*: int32
    ticksLeft*: int32
    alive*: bool

  WorldObject* = object
    id*: int32
    kind*: int32
    team*: Team
    layer*: int32
    position*: WorldPoint
    hp*: int32
    maxHp*: int32
    alive*: bool
    hooked*: bool
    shielded*: bool
    rotting*: bool
      ## True when this butcher's Rot is on. Props stay false.

  Ping* = object
    ## One recorded team map ping.
    team*: Team
    byId*: int32
    x*, y*: int32
    tick*: int32

  Rune* = object
    ## One power-up orb drifting along the river current.
    id*: int32
    kind*: RuneKind
    position*: WorldPoint
    dir*: int32
      ## Drift sign on the z axis: +1 southward, -1 northward.
    spawnTick*: int32

  World* = ref object
    pudges*: seq[Pudge]
    hooks*: seq[Hook]
    tick*: int32
    maximumTicks*: int32
    killGoal*: int32
    gameOver*: bool
    winner*: Team
    rng*: Rng
    nextHookId*: int32
    heroTurnTicks*: int32
    heroTurnStart*: int
    teamKills*: array[2, int32]
    hookHits*: int32
    hookMisses*: int32
    headshots*: int32
    riverDumps*: int32
    hookDenies*: int32
    clashTick*: int32
    clashPoint*: WorldPoint
    chunkTick*: int32
    chunkerId*: int32
    chunkVictimId*: int32
    chunkOwnerId*: int32
    pings*: seq[Ping]
    runes*: seq[Rune]
    nextRuneId*: int32
    runePeriod*: int32
      ## Ticks between rune spawns; 0 disables the river current drops.
    runeClock*: int32
      ## Countdown to the next spawn.
    props*: seq[Prop]
    nextPropId*: int32
    spawnLayout*: SpawnLayout
      ## Home pads for this map seed. Fountain and wall-grief use these,
      ## not the constant lane centers.
    scriptObjects: seq[WorldObject]
    scriptObjectCount: int
    scriptObjectsTick: int32
    scriptHookIdx: seq[int]
    scriptHookCount: int
    scriptRuneIdx: seq[int]
    scriptRuneCount: int

  IntentKind* = enum
    ## One queued human command; integers only so replays stay exact.
    IntentWalk,
    IntentHook,
    IntentHookFine,
    IntentGrapple,
    IntentGrappleFine,
    IntentBuyPower,
    IntentAttack,
    IntentBuy,
    IntentStop,
    IntentPing,
    IntentBlink,
    IntentBlinkFine,
    IntentPlaceWall,
    IntentPlaceMine,
    IntentCheat,
    IntentRot

  HumanIntent* = object
    slot*: int32
      ## Pudge roster index this intent drives.
    kind*: IntentKind
    a*, b*: int32

  IntentResult* = object
    ## Client feedback: what the sim did with one drained intent.
    slot*: int32
    kind*: IntentKind
    accepted*: bool
    a*, b*: int32
    tick*: int32

  BotSpeech* = object
    ## Last `print` line one bot seat emitted, for the client's intent
    ## bubbles. Display-only: never hashed, never on the tape.
    text*: string
    tick*: int32

  MatchChatLine* = object
    ## One typed match-chat line. Display-only: never hashed, never on the tape.
    tick*: int32
    slot*: int32
      ## Roster index, or -1 for a spectator.
    name*: string
    text*: string
    team*: int32
      ## `Team.ord`, or -1 when the line has no bank.

  Game* = ref object
    world*: World
    map*: MapData
    recorder*: ReplayRecorder
    replayData*: ReplayData
    replayPlayer*: ReplayPlayer
    hashCheck*: ReplayHashCheck
    historyPlayback*: bool
    replayMode*: bool
    replayVersionSkew*: bool
      ## Tape `gameVersion` differs from this build; skip hash checks.
    recordingError*: string
    heroVms*: seq[HeroVm]
    maximumTicks*: int32
    humanSlots*: seq[int]
      ## Roster indexes currently driven by humans instead of scripts.
    humanIntents*: seq[HumanIntent]
      ## Client-queued commands drained at each human slot's hero turn.
    intentResults*: seq[IntentResult]
      ## Acknowledgment feed the client drains every frame.
    botEvery*: int32
      ## Bot decision cadence in ticks; 0/1 means every tick.
    botAimNoise*: int32
      ## Bot hook aim scatter in tiles, applied before recording.
    botSpeech*: seq[BotSpeech]
      ## Per-seat intent bubbles captured from BASIC `print`.
    chatLog*: seq[MatchChatLine]
      ## Typed player chat. Display-only.

const
  MaxMatchChat* = 48
    ## Ring size for the display-only match chat.

proc appendChat*(game: Game, line: MatchChatLine) =
  ## Pushes one chat row, collapsing a seat that repeats the same line.
  if game == nil or line.text.len == 0:
    return
  if game.chatLog.len > 0:
    let last = game.chatLog[^1]
    if last.slot == line.slot and last.text == line.text:
      return
  game.chatLog.add line
  if game.chatLog.len > MaxMatchChat:
    game.chatLog.delete(0)

proc clearChat*(game: Game) =
  ## Drops the display-only match chat (seek, rematch, new tape).
  if game != nil:
    game.chatLog.setLen(0)

var
  activeWalkLayer: int
  activeWorld: World
  activeWalkerId: int32
  activeHookWorld: World

proc heading*(x, z: int32): Heading =
  ## Creates an integer heading from a planar direction.
  Heading(x: x, z: z)

proc `-`(first, second: WorldPoint): WorldPoint =
  WorldPoint(
    x: first.x - second.x,
    y: first.y - second.y,
    z: first.z - second.z
  )

proc `+`(first, second: WorldPoint): WorldPoint =
  WorldPoint(
    x: first.x + second.x,
    y: first.y + second.y,
    z: first.z + second.z
  )

proc distanceSquared*(first, second: WorldPoint): int64 =
  let
    x = int64(first.x) - int64(second.x)
    z = int64(first.z) - int64(second.z)
  x * x + z * z

proc within(first, second: WorldPoint, distance: int32): bool =
  distanceSquared(first, second) <= int64(distance) * int64(distance)

proc segmentPointWithin(a0, a1, p: WorldPoint, radius: int32): bool =
  ## True when point `p` is within `radius` of segment `a0`–`a1`.
  if within(a0, p, radius) or within(a1, p, radius):
    return true
  let
    ax = int64(a1.x) - int64(a0.x)
    az = int64(a1.z) - int64(a0.z)
    px = int64(p.x) - int64(a0.x)
    pz = int64(p.z) - int64(a0.z)
    denom = ax * ax + az * az
  if denom == 0:
    return within(a0, p, radius)
  var tNum = px * ax + pz * az
  if tNum < 0:
    tNum = 0
  elif tNum > denom:
    tNum = denom
  # Guard `tNum * ax` for degenerate cross-map sweeps: shed low bits
  # from the t fraction until the product fits. Ordinary sweeps take
  # the exact path untouched.
  var
    tScaled = tNum
    dScaled = denom
  let axis = max(abs(ax), abs(az))
  if axis > 0:
    while tScaled > high(int64) div axis:
      tScaled = tScaled shr 1
      dScaled = dScaled shr 1
  if dScaled <= 0:
    return within(a0, p, radius)
  let
    qx = int64(a0.x) + roundDivision(tScaled * ax, dScaled)
    qz = int64(a0.z) + roundDivision(tScaled * az, dScaled)
    dx = qx - int64(p.x)
    dz = qz - int64(p.z)
  dx * dx + dz * dz <= int64(radius) * int64(radius)

proc hookLatchRadius(hook: Hook): int32 =
  ## Shuriken disk plus the butcher's solid body. Same circle the
  ## renderer draws: `hook.radius` is 3.5 tiles at the default rank.
  let
    head = hook.radius
    body = PudgeCollisionRadius
  if head > high(int32) - body:
    high(int32)
  else:
    head + body

proc hookClashRadius(first, second: Hook): int32 =
  ## Two shuriken disks touching, plus the deflection grace so a
  ## deliberate mid-air deny is a human-landable play.
  let disks = int64(first.radius) + int64(second.radius) +
    int64(HookClashRadius)
  if disks > int64(high(int32)):
    high(int32)
  else:
    int32(disks)

proc segmentsWithin*(a0, a1, b0, b1: WorldPoint, radius: int32): bool =
  ## True when two travel segments come within `radius` this tick.
  if within(a0, b0, radius) or within(a1, b1, radius) or
      within(a0, b1, radius) or within(a1, b0, radius):
    return true
  let
    ax = int64(a1.x) - int64(a0.x)
    az = int64(a1.z) - int64(a0.z)
    bx = int64(b1.x) - int64(b0.x)
    bz = int64(b1.z) - int64(b0.z)
    dx = int64(a0.x) - int64(b0.x)
    dz = int64(a0.z) - int64(b0.z)
    vx = ax - bx
    vz = az - bz
    denom = vx * vx + vz * vz
  if denom == 0:
    return within(a0, b0, radius)
  var tNum = -(dx * vx + dz * vz)
  if tNum < 0:
    tNum = 0
  elif tNum > denom:
    tNum = denom
  # Same bit-shed as `segmentPointWithin`: a long sweep (blink-stretched
  # chain, in-place bounce teleport) makes `tNum * az` overflow int64.
  var
    tScaled = tNum
    dScaled = denom
  let axis = max(max(abs(ax), abs(az)), max(abs(bx), abs(bz)))
  if axis > 0:
    while tScaled > high(int64) div axis:
      tScaled = tScaled shr 1
      dScaled = dScaled shr 1
  if dScaled <= 0:
    return within(a0, b0, radius)
  let
    px = int64(a0.x) + roundDivision(tScaled * ax, dScaled)
    pz = int64(a0.z) + roundDivision(tScaled * az, dScaled)
    qx = int64(b0.x) + roundDivision(tScaled * bx, dScaled)
    qz = int64(b0.z) + roundDivision(tScaled * bz, dScaled)
    cx = px - qx
    cz = pz - qz
  cx * cx + cz * cz <= int64(radius) * int64(radius)

proc scaledPlanar(direction: WorldPoint, distance: int32): WorldPoint =
  let length = integerSqrt(
    int64(direction.x) * int64(direction.x) +
    int64(direction.z) * int64(direction.z)
  )
  if length == 0:
    return
  WorldPoint(
    x: int32(roundDivision(int64(direction.x) * distance, length)),
    z: int32(roundDivision(int64(direction.z) * distance, length))
  )

proc hookSweepStart(hook: Hook): WorldPoint =
  ## Clash uses the outbound sweep for a flying head. Reeling heads are
  ## a point until `advanceReel` moves them; latch always uses `prior`.
  if hook.phase != HookFlying:
    return hook.position
  hook.prior

proc floorWorldTile(value: int32): int =
  if value >= 0:
    int(value div WorldScale)
  else:
    -int(((-int64(value)) + int64(WorldScale) - 1) div int64(WorldScale))

proc tileOf*(position: WorldPoint): tuple[x, z: int] =
  (
    floorWorldTile(position.x) + GridTiles div 2,
    floorWorldTile(position.z) + GridTiles div 2
  )

proc worldAtTile*(x, z: int): WorldPoint =
  WorldPoint(
    x: int32(x - GridTiles div 2) * WorldScale + WorldScale div 2,
    z: int32(z - GridTiles div 2) * WorldScale + WorldScale div 2
  )

proc tileWorldMin(tile: int): int32 {.inline.} =
  int32(tile - GridTiles div 2) * WorldScale

proc clampHookToMap(point: var WorldPoint) =
  let
    lo = tileWorldMin(0)
    hi = tileWorldMin(GridTiles) - 1
  point.x = clamp(point.x, lo, hi)
  point.z = clamp(point.z, lo, hi)

proc fineOfTile*(tile: int32): int32 =
  ## Center of one tile in `FineAimScale` (1/256-tile) units.
  tile * FineAimScale + FineAimScale div 2

proc worldAtFine*(fineX, fineY: int32): WorldPoint =
  ## World point for a fine-aim coordinate measured from the map origin.
  WorldPoint(
    x: int32(int64(fineX) * WorldScale div FineAimScale) -
      int32(GridTiles div 2) * WorldScale,
    z: int32(int64(fineY) * WorldScale div FineAimScale) -
      int32(GridTiles div 2) * WorldScale
  )

proc fineOfWorld*(value: int32): int32 =
  ## Fine-aim coordinate of one world axis value, clamped onto the map.
  let offset = int64(value) + int64(GridTiles div 2) * WorldScale
  int32(clamp(
    offset * FineAimScale div WorldScale,
    0'i64,
    int64(GridTiles) * FineAimScale - 1
  ))

proc mapCoordinate*(value: int32): int32 =
  int32(clamp(
    floorWorldTile(value) + GridTiles div 2,
    0,
    GridTiles - 1
  ))

proc toPlanar(point: WorldPoint): FixedVec2 =
  fixedVec2(
    worldToTiles(point.x, WorldScale),
    worldToTiles(point.z, WorldScale)
  )

proc bindBody(position: WorldPoint, facing: Heading): Body =
  result.pos = toPlanar(position)
  result.radius = worldToTiles(PudgeCollisionRadius, WorldScale)
  if facing.x != 0 or facing.z != 0:
    result.facing = angle(fixedVec2(
      worldToTiles(facing.x, WorldScale),
      worldToTiles(facing.z, WorldScale)
    ))

proc applyBody(position: var WorldPoint, facing: var Heading, body: Body) =
  position.x = tilesToWorld(body.pos.x, WorldScale)
  position.z = tilesToWorld(body.pos.y, WorldScale)
  let dir = direction(body.facing)
  facing = heading(
    tilesToWorld(dir.x, WorldScale),
    tilesToWorld(dir.y, WorldScale)
  )

proc occupiedAt(
    world: World,
    pos: WorldPoint,
    exceptId: int32,
    layer: int32
): bool

proc tileStandable(layer: int32, tileX, tileZ: int): bool

proc wallBlocksTile*(world: World, tileX, tileZ: int): bool

proc layerTerrainWalkable(pos: FixedVec2): bool {.nimcall.} =
  ## Tile + palisade only. Occupied circles are `resolveOverlaps` /
  ## `slide`, not a reason to treat the butcher as stuck in a cliff.
  let
    x = int(whole(pos.x)) + GridTiles div 2
    z = int(whole(pos.y)) + GridTiles div 2
  if x < 0 or x >= GridTiles or z < 0 or z >= GridTiles:
    return false
  if not tileStandable(int32(activeWalkLayer), x, z):
    return false
  if activeWorld != nil and activeWorld.wallBlocksTile(x, z):
    return false
  true

proc layerWalkable(pos: FixedVec2): bool {.nimcall.} =
  ## Stays on the butcher's current layer, including the river bed.
  if not layerTerrainWalkable(pos):
    return false
  if activeWorld == nil:
    return true
  let point = WorldPoint(
    x: tilesToWorld(pos.x, WorldScale),
    z: tilesToWorld(pos.y, WorldScale)
  )
  not occupiedAt(
    activeWorld,
    point,
    activeWalkerId,
    int32(activeWalkLayer)
  )

proc pudgeIndex*(world: World, id: int32): int =
  for i, pudge in world.pudges:
    if pudge.id == id:
      return i
  -1

proc inRiver*(pudge: Pudge): bool =
  ## Returns whether this butcher is occupying the river layer.
  pudge.layer == int32(RiverLayer)

proc layerAt*(position: WorldPoint): int32 =
  ## Returns the gameplay layer that owns this world point.
  let tile = tileOf(position)
  layerAtX(clamp(tile.x, 0, GridTiles - 1))

proc bindPudgeBody*(pudge: var Pudge) =
  pudge.body = bindBody(pudge.position, pudge.facing)

proc solidLiving(pudge: Pudge): bool =
  pudge.state == Alive and pudge.hookedBy == 0

proc occupiedAt(
    world: World,
    pos: WorldPoint,
    exceptId: int32,
    layer: int32
): bool =
  ## True when a living body already covers this point.
  let
    need = int64(MinSeparation)
    needSq = need * need
  for pudge in world.pudges:
    if pudge.id == exceptId or not pudge.solidLiving:
      continue
    if pudge.layer != layer:
      continue
    if distanceSquared(pos, pudge.position) < needSq:
      return true
  false

proc tileStandable(layer: int32, tileX, tileZ: int): bool =
  ## Standable on the current layer only. River walkers stay in the
  ## drink (`PlayZMin`..`PlayZMax`, not the fountain); bank walkers
  ## cannot step onto a river column. This is the waterline.
  if tileX < 0 or tileX >= GridTiles or tileZ < 0 or tileZ >= GridTiles:
    return false
  if layer == int32(RiverLayer):
    return riverTile(tileX) and not islandTile(tileX, tileZ) and
      tileZ >= PlayZMin and tileZ <= PlayZMax
  if riverTile(tileX):
    return false
  isWalkable(int(layer), tileX, tileZ)

proc propCenter*(prop: Prop): WorldPoint =
  ## Tile-center world point of one placed gadget.
  worldAtTile(int(prop.tileX), int(prop.tileZ))

proc wallBlocksTile*(world: World, tileX, tileZ: int): bool =
  ## True when a living palisade occupies this map tile.
  if world == nil:
    return false
  for prop in world.props:
    if prop.alive and prop.kind == PropWall and
        int(prop.tileX) == tileX and int(prop.tileZ) == tileZ:
      return true
  false

proc bouncedOffIsland(hook: Hook): bool =
  ## True after the head has already ricocheted on the fountain.
  ## Face contact is recorded on the river tile just outside the rocks,
  ## so this is a disk, not `islandTile`.
  let reach = (IslandRadius + 1) * WorldScale
  for bounce in hook.bounces:
    if within(bounce, worldAtTile(IslandCenterX, IslandCenterZ), reach):
      return true
  false

proc hookHitsSolid(hook: Hook, tileX, tileZ: int): bool =
  ## Map solids plus living palisades: hooks rebound here.
  ## The fountain is one bounce: after the first ricochet it is air, so
  ## a glance cannot orbit the rocks. Grapples never latch it — the
  ## rocks are unstandable, so a yank would dump the caster in the drink.
  if islandTile(tileX, tileZ):
    if hook.isGrapple or hook.bouncedOffIsland:
      return false
    return true
  if hookReboundTile(tileX, tileZ):
    return true
  activeHookWorld != nil and activeHookWorld.wallBlocksTile(tileX, tileZ)

proc propVisibleTo*(prop: Prop, team: Team): bool =
  ## Walls are public; mines stay hidden from the other team.
  prop.alive and (prop.kind != PropMine or prop.team == team)

proc mineVisibleTo*(world: World, propId: int32, team: Team): bool =
  ## Test helper: whether one mine shows up for a team's queries.
  for prop in world.props:
    if prop.id == propId:
      return propVisibleTo(prop, team)
  false

proc canStand(pudge: Pudge, pos: WorldPoint): bool =
  let tile = tileOf(pos)
  tileStandable(pudge.layer, tile.x, tile.z)

proc ejectPudge(world: World, index: int)

proc pushDir(first, second: Pudge): WorldPoint =
  ## Coincident bodies at the waterline share an east/west facing; a
  ## push along that heading walks one of them into the river and the
  ## revert leaves them stacked. Prefer the bank axis (Z) by id.
  let
    dx = second.position.x - first.position.x
    dz = second.position.z - first.position.z
  if dx != 0 or dz != 0:
    return WorldPoint(x: dx, z: dz)
  if first.id <= second.id:
    return WorldPoint(x: 0, z: WorldScale)
  WorldPoint(x: 0, z: -WorldScale)

proc tryPlacePudge(world: World, index: int, pos: WorldPoint): bool =
  if not world.pudges[index].canStand(pos):
    return false
  let tile = tileOf(pos)
  if world.wallBlocksTile(tile.x, tile.z):
    return false
  world.pudges[index].position = pos
  world.pudges[index].bindPudgeBody()
  true

proc pushAlong(world: World, index: int, dir: WorldPoint, amount: int32): bool =
  if amount <= 0:
    return true
  let step = scaledPlanar(dir, amount)
  if step.x == 0 and step.z == 0:
    return false
  world.tryPlacePudge(index, world.pudges[index].position + step)

proc isMover(pudge: Pudge): bool =
  pudge.hasMoveTarget or pudge.velX != 0 or pudge.velZ != 0 or
    pudge.attackTargetId != 0

proc separateAlong(
    world: World,
    i, j: int,
    dir: WorldPoint,
    remaining: int32
) =
  ## Prefers shoving the mover so an idle butcher is not walked across
  ## the bank. If one side is blocked, the other takes the leftover.
  if dir.x == 0 and dir.z == 0:
    return
  let
    back = WorldPoint(x: -dir.x, z: -dir.z)
    moveI = world.pudges[i].isMover
    moveJ = world.pudges[j].isMover
  if moveJ and not moveI:
    if not world.pushAlong(j, dir, remaining):
      discard world.pushAlong(i, back, remaining)
    return
  if moveI and not moveJ:
    if not world.pushAlong(i, back, remaining):
      discard world.pushAlong(j, dir, remaining)
    return
  let
    half = remaining div 2
    rest = remaining - half
  if world.pushAlong(j, dir, half):
    if not world.pushAlong(i, back, rest):
      discard world.pushAlong(j, dir, rest)
  else:
    discard world.pushAlong(i, back, remaining)

proc separatePudges(world: World, i, j: int) =
  ## Pushes two overlapping living bodies apart. Reeled victims stay free
  ## until the drop; corpses are not solid.
  if i < 0 or j < 0 or i >= world.pudges.len or j >= world.pudges.len:
    return
  if not world.pudges[i].solidLiving or not world.pudges[j].solidLiving:
    return
  if world.pudges[i].layer != world.pudges[j].layer:
    return
  let
    need = int64(MinSeparation)
    dist = integerSqrt(distanceSquared(
      world.pudges[i].position,
      world.pudges[j].position
    ))
  if dist >= need:
    return
  var remaining = int32(need)
  if dist > 0:
    remaining = int32(need - dist)
  if remaining <= 0:
    return
  let dir = pushDir(world.pudges[i], world.pudges[j])
  world.separateAlong(i, j, dir, remaining)
  let after = integerSqrt(distanceSquared(
    world.pudges[i].position,
    world.pudges[j].position
  ))
  if after >= need:
    return
  var leftover = int32(need)
  if after > 0:
    leftover = int32(need - after)
  let perp = WorldPoint(x: -dir.z, z: dir.x)
  world.separateAlong(i, j, perp, leftover)

proc resolveOverlaps(world: World) =
  ## Hard min-separation after every position write. Id order is the
  ## pudges array order (1..N). Extra passes dissolve 3-stacks.
  for _ in 1 .. SeparatePasses:
    for i in 0 ..< world.pudges.len:
      for j in i + 1 ..< world.pudges.len:
        world.separatePudges(i, j)

proc setAnim(pudge: var Pudge, clip: int, restart = false) =
  ## Starts a clip from the first frame when the pose actually changes.
  if restart or pudge.animClip != clip:
    pudge.animClip = clip
    pudge.animTicks = 0

proc absDelta(a, b: int32): int32 =
  let d = a - b
  if d < 0: -d else: d

proc steerVelocity(pudge: var Pudge, wantX, wantZ: int32) =
  ## Carve steering: the velocity direction rotates toward the order at
  ## `VelTurnRate` while the speed tracks the desired magnitude under
  ## `MoveAccel`/`MoveBrake`. Turns of 90° or less keep full speed —
  ## tight, responsive arcs — while an order behind the butcher brakes
  ## until the carve comes around, so stops and reversals still pay for
  ## the old speed. Fixed-point and integers only for determinism.
  let
    speed = integerSqrt(
      int64(pudge.velX) * pudge.velX + int64(pudge.velZ) * pudge.velZ
    )
    wantSpeed = integerSqrt(
      int64(wantX) * wantX + int64(wantZ) * wantZ
    )
  if speed == 0:
    if wantSpeed == 0:
      return
    # Launch from rest straight toward the order.
    let start = min(int64(MoveAccel), wantSpeed)
    pudge.velX = int32(int64(wantX) * start div wantSpeed)
    pudge.velZ = int32(int64(wantZ) * start div wantSpeed)
    return
  let heading = angle(fixedVec2(
    worldToTiles(pudge.velX, WorldScale),
    worldToTiles(pudge.velZ, WorldScale)
  ))
  var
    course = heading
    target = wantSpeed
  if wantSpeed > 0:
    let wantDir = angle(fixedVec2(
      worldToTiles(wantX, WorldScale),
      worldToTiles(wantZ, WorldScale)
    ))
    if abs(shortestTurn(heading, wantDir)) > FixedHalfPi:
      # The order is behind: shed speed while the carve comes around,
      # then relaunch along the new direction.
      target = 0
    turnToward(course, wantDir, VelTurnRate)
  var next = speed
  if target > next:
    next = min(next + int64(MoveAccel), target)
  elif target < next:
    next = max(next - int64(MoveBrake), target)
  if next <= 0:
    pudge.velX = 0
    pudge.velZ = 0
    return
  let dir = direction(course)
  pudge.velX = tilesToWorld(dir.x, int32(next))
  pudge.velZ = tilesToWorld(dir.y, int32(next))

proc prepWalkContext(world: World, index: int) =
  ## `layerWalkable` / `slide` read these globals.
  template pudge: untyped = world.pudges[index]
  activeWalkLayer = int(pudge.layer)
  activeWorld = world
  activeWalkerId = pudge.id

proc nudgePudgeOntoWalkable(world: World, index: int) =
  ## When a butcher's center has drifted a sliver into a wall (north or
  ## west cliff, a teammate's circle), slide them back onto standable
  ## ground without dropping their walk order. `ejectPudge` is the hard
  ## reset for true off-grid / unwalkable cases.
  ##
  ## Walkability here is `layerWalkable` (the same predicate `slide`
  ## uses), not `canStand`: body tile-space and world `tileOf` can
  ## disagree by a unit at the cliff, which is exactly the stuck-strafe.
  ## Runs at rest too: a vel-0 early-out must not skip this.
  template pudge: untyped = world.pudges[index]
  world.prepWalkContext(index)
  let origin = pudge.body.pos
  if layerTerrainWalkable(origin):
    return
  let
    bx = int(whole(origin.x)) + GridTiles div 2
    bz = int(whole(origin.y)) + GridTiles div 2
    wt = tileOf(pudge.position)
  var
    inlandX = FixedZero
    inlandZ = FixedZero
  if bx < PlayWestMin or wt.x < PlayWestMin:
    inlandX = FixedOne
  elif bx > PlayEastMax or wt.x > PlayEastMax:
    inlandX = -FixedOne
  if bz < PlayZMin or wt.z < PlayZMin:
    inlandZ = FixedOne
  elif bz > PlayZMax or wt.z > PlayZMax:
    inlandZ = -FixedOne
  var
    dirs: array[8, FixedVec2]
    n = 0
  template push(v: FixedVec2) =
    var seen = false
    for i in 0 ..< n:
      if dirs[i] == v:
        seen = true
    if not seen and n < dirs.len:
      dirs[n] = v
      inc n
  if inlandX != FixedZero and inlandZ != FixedZero:
    push(fixedVec2(inlandX, inlandZ))
  if inlandZ != FixedZero:
    push(fixedVec2(FixedZero, inlandZ))
  if inlandX != FixedZero:
    push(fixedVec2(inlandX, FixedZero))
  push(fixedVec2(FixedZero, FixedOne))
  push(fixedVec2(FixedZero, -FixedOne))
  push(fixedVec2(FixedOne, FixedZero))
  push(fixedVec2(-FixedOne, FixedZero))
  const steps = [
    FixedOne / 8'i32, FixedOne / 4'i32, FixedOne / 2'i32,
    FixedOne, FixedOne + FixedOne / 2'i32, FixedOne * 2'i32
  ]
  for i in 0 ..< n:
    let d = dirs[i]
    for dist in steps:
      let trial = origin + d * dist
      if layerWalkable(trial):
        pudge.body.pos = trial
        applyBody(pudge.position, pudge.facing, pudge.body)
        return
  for i in 0 ..< n:
    let d = dirs[i]
    for dist in steps:
      let trial = origin + d * dist
      if layerTerrainWalkable(trial):
        pudge.body.pos = trial
        applyBody(pudge.position, pudge.facing, pudge.body)
        return

proc integrateWalk(world: World, index: int) =
  ## Slides one butcher by its walk velocity. A blocked axis sheds that
  ## velocity component (walls and occupied circles kill momentum, they
  ## do not store it). Facing eases toward the travel direction unless
  ## a cast point is holding the aim.
  template pudge: untyped = world.pudges[index]
  world.prepWalkContext(index)
  if pudge.state == Alive:
    world.nudgePudgeOntoWalkable(index)
    world.prepWalkContext(index)
    if not layerTerrainWalkable(pudge.body.pos):
      world.ejectPudge(index)
      world.prepWalkContext(index)
  if pudge.velX == 0 and pudge.velZ == 0:
    return
  let
    delta = fixedVec2(
      worldToTiles(pudge.velX, WorldScale),
      worldToTiles(pudge.velZ, WorldScale)
    )
    before = pudge.body.pos
  slide(pudge.body.pos, delta, layerWalkable)
  if pudge.body.pos == before and
      (delta.x != FixedZero or delta.y != FixedZero):
    # Still overlapping a wall strip: the full step, X-only, and Y-only
    # probes all stay in the unwalkable row. Nudge inland and retry.
    world.nudgePudgeOntoWalkable(index)
    slide(pudge.body.pos, delta, layerWalkable)
  let
    movedX = int64(tilesToWorld(pudge.body.pos.x - before.x, WorldScale))
    movedZ = int64(tilesToWorld(pudge.body.pos.y - before.y, WorldScale))
    wantSq = int64(pudge.velX) * pudge.velX + int64(pudge.velZ) * pudge.velZ
  if movedX * movedX + movedZ * movedZ < wantSq div 4:
    # Under half the intended step. When the blocker is a BODY (not
    # terrain), skate
    # around its circle instead of jamming: pick the tangent that
    # agrees with the travel intent and slide along it. Two butchers
    # pushing head-on take opposite tangents and orbit past each
    # other rather than pinning until one gives up.
    var
      blockerAt = WorldPoint()
      blockerFound = false
      blockerBest = high(int64)
    let reach = int64(MinSeparation) + int64(
      max(abs(pudge.velX), abs(pudge.velZ))
    )
    for other in world.pudges:
      if other.id == pudge.id or not other.solidLiving:
        continue
      if other.layer != pudge.layer:
        continue
      let
        toX = int64(other.position.x) - int64(pudge.position.x)
        toZ = int64(other.position.z) - int64(pudge.position.z)
      if toX * pudge.velX + toZ * pudge.velZ < 0:
        continue  # behind the travel direction
      let d = distanceSquared(pudge.position, other.position)
      if d < reach * reach and d < blockerBest:
        blockerBest = d
        blockerAt = other.position
        blockerFound = true
    if blockerFound:
      var
        tanX = -(blockerAt.z - pudge.position.z)
        tanZ = blockerAt.x - pudge.position.x
      if int64(tanX) * pudge.velX + int64(tanZ) * pudge.velZ < 0:
        tanX = -tanX
        tanZ = -tanZ
      let
        speed = integerSqrt(
          int64(pudge.velX) * pudge.velX + int64(pudge.velZ) * pudge.velZ
        )
        skate = scaledPlanar(
          WorldPoint(x: tanX, z: tanZ), int32(speed)
        )
      if skate.x != 0 or skate.z != 0:
        slide(
          pudge.body.pos,
          fixedVec2(
            worldToTiles(skate.x, WorldScale),
            worldToTiles(skate.z, WorldScale)
          ),
          layerWalkable
        )
  if delta.x != FixedZero and pudge.body.pos.x == before.x:
    pudge.velX = 0
  if delta.y != FixedZero and pudge.body.pos.y == before.y:
    pudge.velZ = 0
  if pudge.windupTicks <= 0 and (pudge.velX != 0 or pudge.velZ != 0):
    turnToward(
      pudge.body.facing,
      angle(fixedVec2(
        worldToTiles(pudge.velX, WorldScale),
        worldToTiles(pudge.velZ, WorldScale)
      )),
      BodyTurnRate
    )
  applyBody(pudge.position, pudge.facing, pudge.body)

proc coast(world: World, index: int) =
  ## No live steering: brake toward rest and play out the leftover skid.
  world.pudges[index].steerVelocity(0, 0)
  world.integrateWalk(index)

proc walkRested(pudge: Pudge): bool =
  ## Slow enough to settle on a point without a visible snap.
  let
    vx = int64(pudge.velX)
    vz = int64(pudge.velZ)
    limit = int64(MoveBrake) * 3
  vx * vx + vz * vz <= limit * limit

proc hasBuff*(pudge: Pudge, kind: RuneKind): bool =
  ## Returns whether this butcher currently carries one rune power.
  pudge.buffTicks > 0 and pudge.buffKind == kind

proc topMoveSpeed*(pudge: Pudge): int32 =
  ## Walk speed cap from Treads and the Haste rune, before status cuts.
  result = MovePerTick
  result += MovePerTick * ItemBootsSpeedPercent *
    pudge.itemRank[ShopBoots] div 100
  if pudge.hasBuff(RuneHaste):
    result += MovePerTick * RuneHastePercent div 100

proc rotAffected*(world: World, pudge: Pudge): bool =
  ## True while this living butcher stands in any live Rot disk,
  ## including their own.
  if pudge.state != Alive:
    return false
  for other in world.pudges:
    if other.state != Alive or not other.rotOn:
      continue
    if within(pudge.position, other.position, RotRadius):
      return true

proc moveSpeed*(world: World, pudge: Pudge): int32 =
  ## Walk cap after Rot's slow. Overlapping auras do not stack the cut.
  result = topMoveSpeed(pudge)
  if world.rotAffected(pudge):
    result -= result * RotSlowPercent div 100
    if result < 1:
      result = 1

proc meleeDamage*(pudge: Pudge): int32 =
  ## Melee hit. Permanents no longer add raw melee.
  BaseMeleeDamage

proc hasCheat*(pudge: Pudge, flag: int32): bool =
  ## Returns whether one WC3-style cheat bit is on.
  (pudge.cheatFlags and flag) != 0

proc cooling(pudge: Pudge, remaining: int32): bool =
  remaining > 0 and not pudge.hasCheat(CheatFlagMana)

proc armedCooldown(pudge: Pudge, ticks: int32): int32 =
  if pudge.hasCheat(CheatFlagMana): 0'i32 else: ticks

proc attackPeriod*(pudge: Pudge): int32 =
  ## Swing duration.
  discard pudge
  AttackTicks

proc ownedPermanents*(pudge: Pudge): int32 =
  ## How many inventory families currently occupy a HUD slot.
  for item in ShopBoots..ShopMine:
    if pudge.itemRank[item] > 0:
      inc result

proc inventoryItem*(pudge: Pudge, slot: int): ShopItem =
  ## The family shown in one HUD inventory well, or ShopFlask as empty
  ## sentinel when the well is vacant (callers check rank).
  var index = 0
  for item in ShopBoots..ShopMine:
    if pudge.itemRank[item] > 0:
      if index == slot:
        return item
      inc index
  ShopFlask

proc inOwnShop*(pudge: Pudge): bool =
  ## Standing on the team's base shop pad.
  let
    tile = tileOf(pudge.position)
    shopX = if pudge.team == WestTeam: WestShopX else: EastShopX
  max(abs(tile.x - shopX), abs(tile.z - ShopZ)) <= int(ShopRadiusTiles)

proc locomotion(world: World, index: int, offset: WorldPoint) =
  ## Momentum steering toward a destination offset: carve toward the
  ## order at speed, brake only for stops and behind-the-back pivots,
  ## and arrive-brake (v² = 2·brake·d) so the butcher can still stop on
  ## the point. Run only plays after a real step; a blocked axis sheds
  ## its velocity in `integrateWalk`.
  template pudge: untyped = world.pudges[index]
  let
    dist = integerSqrt(
      int64(offset.x) * int64(offset.x) + int64(offset.z) * int64(offset.z)
    )
    wantSpeed = min(
      int64(moveSpeed(world, pudge)),
      integerSqrt(2'i64 * int64(MoveBrake) * dist)
    )
    want = scaledPlanar(offset, int32(wantSpeed))
  pudge.steerVelocity(want.x, want.z)
  let before = pudge.position
  world.integrateWalk(index)
  if pudge.position.x == before.x and pudge.position.z == before.z:
    return
  pudge.setAnim(runClip)

proc faceToward(pudge: var Pudge, target: WorldPoint) =
  ## Snaps facing to the target's center. Used in melee so both
  ## fighters look at each other instead of the last walk heading.
  let offset = target - pudge.position
  if offset.x == 0 and offset.z == 0:
    return
  pudge.facing = heading(offset.x, offset.z)
  pudge.bindPudgeBody()

proc haltWalk(pudge: var Pudge) =
  ## Drops the walk order. Momentum persists: leftover velocity brakes
  ## off through `coast`, so a halt is a short skid, not a freeze.
  pudge.hasMoveTarget = false
  if pudge.animClip == runClip:
    pudge.setAnim(idleClip)

proc settlePudge(world: World, index: int, creditDump: bool) =
  ## Assigns layer from the current tile. Call after a hop or dump, not
  ## after a walk: hugging the waterline must not promote a river
  ## walker onto a bank (or dump a bank walker into the drink).
  if index < 0 or index >= world.pudges.len:
    return
  let
    wasRiver = world.pudges[index].inRiver
    next = layerAt(world.pudges[index].position)
  world.pudges[index].layer = next
  if world.pudges[index].state == Alive and
      world.pudges[index].hookedBy == 0 and
      not world.pudges[index].canStand(world.pudges[index].position):
    # Off the board, on the rock rim, or on the fountain: snap back
    # before crediting a river dump that never landed in the water.
    world.ejectPudge(index)
    return
  if wasRiver and next != int32(RiverLayer):
    world.pudges[index].drownTicks = 0
  if creditDump and
      next == int32(RiverLayer) and
      world.pudges[index].state == Alive:
    inc world.riverDumps
    world.pudges[index].enteredRiver = true
  world.pudges[index].bindPudgeBody()

proc placePudge*(pudge: var Pudge, tileX, tileZ: int) =
  ## Snaps one butcher onto a map tile and rebuilds its planar body.
  pudge.position = worldAtTile(tileX, tileZ)
  pudge.layer = layerAtX(clamp(tileX, 0, GridTiles - 1))
  pudge.bindPudgeBody()
  pudge.hasMoveTarget = false
  pudge.velX = 0
  pudge.velZ = 0

proc landingPoint(owner: Pudge, hook: Hook): WorldPoint =
  ## One tile along the hook heading from the caster. Hugging the bank
  ## on an across-river throw still dumps the victim in the drink;
  ## the drop stays on the chain instead of snapping sideways. Clamped
  ## to the map: two mutual reels used to leapfrog each other's owners
  ## off the board one dump distance per tick, without bound.
  result = owner.position + scaledPlanar(
    WorldPoint(x: hook.heading.x, z: hook.heading.z),
    HookDumpDistance
  )
  clampHookToMap(result)

proc climbHookSpeed(hook: var Hook) =
  ## Accelerates an outbound head. Climb stops at `HookSpeedMax`;
  ## `peakSpeed` is the reel speed, including an early latch.
  if hook.speed < HookSpeedMax:
    let next = hook.speed + HookAccel
    if next < hook.speed or next > HookSpeedMax:
      hook.speed = HookSpeedMax
    else:
      hook.speed = next
  if hook.peakSpeed < hook.speed:
    hook.peakSpeed = hook.speed

proc reelSpeed(hook: Hook): int32 =
  ## Pull-in uses the peak outbound speed reached, not base and not 2×.
  if hook.peakSpeed > 0: hook.peakSpeed
  else: hook.speed

proc clone*(w: World): World {.measure.} =
  result = World()
  result[] = w[]

proc restore*(w: World, snapshot: World) =
  w[] = snapshot[]

proc spawnTile*(pudge: Pudge): tuple[x, z: int] =
  ## Home pad tile this butcher respawns on.
  tileOf(pudge.spawnPosition)

proc livePudgeSetup*(duel = false, teamSize = TeamSize): seq[ReplayPudge] =
  ## Stock roster: N vs N across 2N seats, or the 1v1 duel — one butcher
  ## a side on team slot 1 (a shuffled, jittered lane, not always mid).
  if duel:
    result.setLen(DuelPudgeCount)
    result[0] = ReplayPudge(
      id: FirstPudgeId, team: uint8(WestTeam.ord), slot: 1, lobbySeat: 1
    )
    result[1] = ReplayPudge(
      id: FirstPudgeId + 1, team: uint8(EastTeam.ord), slot: 1,
      lobbySeat: 4
    )
    return
  let n = clampTeamSize(teamSize)
  let count = matchPudgeCount(n)
  result.setLen(count)
  for i in 0 ..< count:
    let team = if i < n: WestTeam else: EastTeam
    result[i] = ReplayPudge(
      id: FirstPudgeId + int32(i),
      team: uint8(team.ord),
      slot: uint8(i mod n),
      lobbySeat: uint8(i)
    )

proc filteredRoster*(
    disabled: openArray[bool],
    teamSize = TeamSize
): seq[ReplayPudge] =
  ## The N vs N roster minus the lobby's disabled seats. Spawn lanes
  ## and lobby identity travel with each entry, so a 2v1 keeps its
  ## original pads and seat labels.
  for entry in livePudgeSetup(false, teamSize):
    let seat = int(entry.lobbySeat)
    if seat < disabled.len and disabled[seat]:
      continue
    result.add entry

proc rosterModeName*(world: World): string =
  ## "1v1", "2v2", … or "duel" when both butchers sit on team slot 1.
  var west, east = 0
  for pudge in world.pudges:
    if pudge.team == WestTeam: inc west
    else: inc east
  if west == 1 and east == 1 and world.pudges.len >= 1 and
      world.pudges[0].slot == 1:
    "duel"
  else:
    $west & "v" & $east

proc worldIndexOfSeat*(world: World, lobbySeat: int): int =
  ## Maps one lobby seat number onto the (possibly compacted) roster.
  for i, pudge in world.pudges:
    if int(pudge.lobbySeat) == lobbySeat:
      return i
  -1

proc spawnPudges(world: World, setup: seq[ReplayPudge]) =
  world.pudges.setLen(0)
  for entry in setup:
    let
      team = Team(entry.team)
      slot = int(entry.slot)
      rolled = world.spawnLayout.layoutPad(team, slot)
      tile =
        if entry.spawnX != 0 and entry.spawnZ != 0:
          (int(entry.spawnX), int(entry.spawnZ))
        else:
          rolled
      facing =
        if team == WestTeam: heading(WorldScale, 0)
        else: heading(-WorldScale, 0)
    var position = worldAtTile(tile[0], tile[1])
    # Sit a quarter-tile inland of the pad center so the opening body
    # is not in the west/east cliff if a pad hugs PlayWestMin.
    if team == WestTeam:
      position.x = position.x + WorldScale div 4
    else:
      position.x = position.x - WorldScale div 4
    world.pudges.add Pudge(
      id: entry.id,
      team: team,
      slot: slot,
      lobbySeat: int32(entry.lobbySeat),
      layer: homeLayer(team),
      position: position,
      spawnPosition: position,
      facing: facing,
      body: bindBody(position, facing),
      hp: BaseHitPoints,
      maxHp: BaseHitPoints,
      state: Alive,
      animClip: idleClip
    )

proc currentSetup*(game: Game, maximumTicks: uint32): Setup =
  var pudges = newSeq[ReplayPudge](game.world.pudges.len)
  for i, pudge in game.world.pudges:
    let home = pudge.spawnTile
    pudges[i] = ReplayPudge(
      id: pudge.id,
      team: uint8(pudge.team.ord),
      slot: uint8(pudge.slot),
      lobbySeat: uint8(pudge.lobbySeat),
      controller:
        if i in game.humanSlots: ControllerHuman
        else: ControllerBot,
      spawnX: int32(home.x),
      spawnZ: int32(home.z)
    )
  Setup(
    mapSeed: game.map.seed,
    mapHash: game.map.hash,
    tickRate: uint16(TickRate),
    gridTiles: ReplayGridTiles,
    maximumTicks: maximumTicks,
    killGoal: game.world.killGoal,
    botEvery: max(game.botEvery, 1'i32),
    botAimNoise: max(game.botAimNoise, 0'i32),
    runePeriod: game.world.runePeriod,
    pudges: pudges
  )

proc refreshPudgeStats(pudge: var Pudge) =
  let next = pudgeMaxHp(pudge.kills)
  if next > pudge.maxHp and pudge.state == Alive:
    pudge.hp = pudge.hp + (next - pudge.maxHp)
  pudge.maxHp = next
  if pudge.hp > pudge.maxHp:
    pudge.hp = pudge.maxHp

proc killPudge(world: World, victimIndex: int, killerId: int32) =

  if victimIndex < 0 or victimIndex >= world.pudges.len:
    return
  if world.pudges[victimIndex].state == Dying:
    return
  if world.pudges[victimIndex].hasCheat(CheatFlagGod):
    return
  let victimTeam = world.pudges[victimIndex].team
  let victimId = world.pudges[victimIndex].id
  let victimStreak = world.pudges[victimIndex].streak
  world.pudges[victimIndex].state = Dying
  world.pudges[victimIndex].hp = 0
  world.pudges[victimIndex].deathTicks = RespawnTicks
  world.pudges[victimIndex].setAnim(deathClip, restart = true)
  world.pudges[victimIndex].hasMoveTarget = false
  world.pudges[victimIndex].velX = 0
  world.pudges[victimIndex].velZ = 0
  world.pudges[victimIndex].attackTargetId = 0
  world.pudges[victimIndex].hookedBy = 0
  world.pudges[victimIndex].windupTicks = 0
  world.pudges[victimIndex].shieldTicks = 0
  world.pudges[victimIndex].buffTicks = 0
  let
    killer = world.pudgeIndex(killerId)
    selfRot =
      killer >= 0 and world.pudges[killer].id == victimId and
      world.pudges[victimIndex].rotOn
  world.pudges[victimIndex].rotOn = false
  world.pudges[victimIndex].rotTicks = 0
  world.pudges[victimIndex].streak = 0
  inc world.pudges[victimIndex].deaths
  if selfRot:
    # Own Rot: suicide bounty. The other team still scores the kill
    # toward the goal; nobody is paid gold or personal KO/PTS.
    let other = if victimTeam == WestTeam: EastTeam else: WestTeam
    inc world.teamKills[other.ord]
  elif killer >= 0 and world.pudges[killer].team != victimTeam:
    inc world.pudges[killer].kills
    inc world.pudges[killer].points
    inc world.pudges[killer].streak
    let
      newStreak = world.pudges[killer].streak
      firstBlood =
        world.teamKills[0] + world.teamKills[1] == 0
      pay = killBountyGold(newStreak, victimStreak, firstBlood)
    world.pudges[killer].gold = world.pudges[killer].gold + pay
    world.pudges[killer].justBounty =
      world.pudges[killer].justBounty + pay
    if firstBlood:
      world.pudges[killer].justFirstBlood = true
    if newStreak >= 3:
      world.pudges[killer].justStreak = newStreak
    if victimStreak >= 3:
      world.pudges[killer].justShutdown = victimStreak
    if world.pudges[killer].multiKill > 0 and
        world.tick - world.pudges[killer].lastKillTick <=
          MultiKillWindowTicks:
      inc world.pudges[killer].multiKill
    else:
      world.pudges[killer].multiKill = 1
    world.pudges[killer].lastKillTick = world.tick
    if world.pudges[killer].multiKill >= 2:
      world.pudges[killer].justMulti = world.pudges[killer].multiKill
    world.pudges[killer].refreshPudgeStats()
    inc world.teamKills[world.pudges[killer].team.ord]
  for hook in world.hooks.mitems:
    if hook.victimId == victimId:
      hook.victimId = 0
      if hook.phase != HookIdle:
        hook.phase = HookReeling

proc killPudgeForTest*(world: World, victimIndex: int, killerId: int32) =
  ## Test hook for the private kill path.
  world.killPudge(victimIndex, killerId)

proc dealPudgeDamage(world: World, victimIndex: int, amount, attackerId: int32) =
  ## Applies one hit, honoring god-mode immunity and one-shot.
  if victimIndex < 0 or victimIndex >= world.pudges.len:
    return
  if world.pudges[victimIndex].state != Alive:
    return
  if world.pudges[victimIndex].hasCheat(CheatFlagGod):
    return
  var hit = amount
  let atk = world.pudgeIndex(attackerId)
  if atk >= 0 and world.pudges[atk].hasCheat(CheatFlagGod):
    hit = world.pudges[victimIndex].hp
  if hit <= 0:
    return
  world.pudges[victimIndex].hp = world.pudges[victimIndex].hp - hit
  world.pudges[victimIndex].lastHurtBy = attackerId
  if world.pudges[victimIndex].hp <= 0:
    world.killPudge(victimIndex, attackerId)

proc respawnPudge(pudge: var Pudge) =
  pudge.position = pudge.spawnPosition
  pudge.layer = homeLayer(pudge.team)
  pudge.bindPudgeBody()
  pudge.state = Alive
  pudge.hp = pudge.maxHp
  pudge.setAnim(idleClip, restart = true)
  pudge.drownTicks = 0
  pudge.hookedBy = 0
  pudge.lastHurtBy = 0
  pudge.hasMoveTarget = false
  pudge.velX = 0
  pudge.velZ = 0
  pudge.attackTargetId = 0
  pudge.swingTicks = 0
  pudge.windupTicks = 0
  pudge.shieldTicks = SpawnShieldTicks
  pudge.rotOn = false
  pudge.rotTicks = 0

proc breakShield(pudge: var Pudge) =
  ## Acting forfeits spawn protection.
  pudge.shieldTicks = 0

proc walkableTile*(layer, mapX, mapY: int32): bool =
  ## Returns whether a butcher on `layer` may stand here. RiverLayer
  ## may stand on river tiles; bank layers may not.
  tileStandable(layer, int(mapX), int(mapY))

proc snapWalkTarget(
    layer, mapX, mapY: int32,
    outX, outY: var int32
): bool =
  ## Command forgiveness: returns the requested tile when the butcher's
  ## current layer can stand there, otherwise the nearest standable tile
  ## within `WalkSnapTiles`. A river click from a bank snaps to the
  ## waterline; a bank click from the river stays in the drink.
  ## Deterministic: scans fixed Chebyshev rings and breaks distance
  ## ties toward low z then low x.
  let
    cx = clamp(mapX, 0'i32, int32(GridTiles - 1))
    cy = clamp(mapY, 0'i32, int32(GridTiles - 1))
  if walkableTile(layer, cx, cy):
    outX = cx
    outY = cy
    return true
  for radius in 1'i32 .. WalkSnapTiles:
    var
      bestX = 0'i32
      bestY = 0'i32
      bestDist = high(int64)
    for dy in -radius .. radius:
      for dx in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let
          x = cx + dx
          y = cy + dy
        if not walkableTile(layer, x, y):
          continue
        let
          offX = int64(x - mapX)
          offY = int64(y - mapY)
          dist = offX * offX + offY * offY
        if dist < bestDist or (
            dist == bestDist and
            (y < bestY or (y == bestY and x < bestX))
          ):
          bestDist = dist
          bestX = x
          bestY = y
    if bestDist != high(int64):
      outX = bestX
      outY = bestY
      return true
  false

proc ejectPudge(world: World, index: int) =
  ## Snaps a butcher who is off the board or on unwalkable rock back
  ## onto the nearest tile their current layer can stand on. River
  ## walkers stay in the drink (the fountain is not a climb-out). Soft
  ## rim unstick: keep the walk order and leftover velocity so D does
  ## not die on the west cliff. Off-grid snaps still zero velocity.
  template pudge: untyped = world.pudges[index]
  world.prepWalkContext(index)
  if layerTerrainWalkable(pudge.body.pos) and pudge.canStand(pudge.position):
    return
  let
    tile = tileOf(pudge.position)
    onGrid = tile.x >= 0 and tile.x < GridTiles and
      tile.z >= 0 and tile.z < GridTiles
    keepMove = pudge.hasMoveTarget
    keepX = pudge.moveX
    keepZ = pudge.moveZ
    keepVelX = pudge.velX
    keepVelZ = pudge.velZ
  var
    tx = 0'i32
    tz = 0'i32
  let layer =
    if pudge.layer == int32(RiverLayer): int32(RiverLayer)
    else: homeLayer(pudge.team)
  if not snapWalkTarget(layer, int32(tile.x), int32(tile.z), tx, tz):
    if layer == int32(RiverLayer):
      tx = int32(RiverCenterX)
      tz = int32(clamp(tile.z, PlayZMin, PlayZMax))
      if islandTile(int(tx), int(tz)):
        tz = int32(PlayZMin + 4)
    else:
      let spawn = pudge.spawnTile
      tx = int32(spawn.x)
      tz = int32(spawn.z)
  pudge.position = worldAtTile(int(tx), int(tz))
  pudge.layer = layer
  pudge.bindPudgeBody()
  pudge.hasMoveTarget = keepMove
  pudge.moveX = keepX
  pudge.moveZ = keepZ
  if onGrid:
    pudge.velX = keepVelX
    pudge.velZ = keepVelZ
  else:
    pudge.velX = 0
    pudge.velZ = 0

proc bodyMapTile(pudge: Pudge): tuple[x, z: int] {.inline.} =
  ## Body-space cell. Can disagree with `tileOf` by one at a cliff.
  (
    int(whole(pudge.body.pos.x)) + GridTiles div 2,
    int(whole(pudge.body.pos.y)) + GridTiles div 2
  )

proc overlapsWestRim(pudge: Pudge): bool {.inline.} =
  let
    here = tileOf(pudge.position)
    body = pudge.bodyMapTile
  here.x < PlayWestMin or body.x < PlayWestMin

proc overlapsEastRim(pudge: Pudge): bool {.inline.} =
  let
    here = tileOf(pudge.position)
    body = pudge.bodyMapTile
  here.x > PlayEastMax or body.x > PlayEastMax

proc overlapsNorthRim(pudge: Pudge): bool {.inline.} =
  let
    here = tileOf(pudge.position)
    body = pudge.bodyMapTile
  here.z < PlayZMin or body.z < PlayZMin

proc overlapsSouthRim(pudge: Pudge): bool {.inline.} =
  let
    here = tileOf(pudge.position)
    body = pudge.bodyMapTile
  here.z > PlayZMax or body.z > PlayZMax

proc boostRimWalkTarget(pudge: Pudge, targetX, targetY: var int32) =
  ## Overlap-only: a sliver into the unwalkable cliff with dest on that
  ## same wall (old D-at-lip instant-arrive) still aims inland. Standing
  ## on the walkable lip with dest on the lip must not: that reverse
  ## (inland, then WASD dest back to the wall) is the 14↔16 orbit.
  if pudge.overlapsWestRim and targetX <= int32(PlayWestMin):
    targetX = int32(PlayWestMin + 8)
  elif pudge.overlapsEastRim and targetX >= int32(PlayEastMax):
    targetX = int32(PlayEastMax - 8)
  if pudge.overlapsNorthRim and targetY <= int32(PlayZMin):
    targetY = int32(PlayZMin + 8)
  elif pudge.overlapsSouthRim and targetY >= int32(PlayZMax):
    targetY = int32(PlayZMax - 8)

proc keepsRimInlandWalk(
    pudge: Pudge,
    targetX,
    targetY: int32,
    here: tuple[x, z: int]
): bool =
  ## A/W into a walkable lip used to halt (v19) so dest PlayWestMin did
  ## not boost inland and orbit. That halt also cancelled a live D/RMB
  ## dest further inland: one tick of east vel, then dest 14 coasted to
  ## rest. Keep the inland dest while still on/near that lip.
  if not pudge.hasMoveTarget:
    return false
  if targetX <= int32(PlayWestMin) and here.x <= PlayWestMin + 8 and
      pudge.moveX >= int32(PlayWestMin + 8):
    return true
  if targetX >= int32(PlayEastMax) and here.x >= PlayEastMax - 8 and
      pudge.moveX <= int32(PlayEastMax - 8):
    return true
  if targetY <= int32(PlayZMin) and here.z <= PlayZMin + 8 and
      pudge.moveZ >= int32(PlayZMin + 8):
    return true
  if targetY >= int32(PlayZMax) and here.z >= PlayZMax - 8 and
      pudge.moveZ <= int32(PlayZMax - 8):
    return true
  false

proc applyWalkTo*(world: World, pudgeId, mapX, mapY: int32): bool =
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  var
    targetX = 0'i32
    targetY = 0'i32
  if not snapWalkTarget(
      world.pudges[index].layer, mapX, mapY, targetX, targetY
    ):
    return false
  world.pudges[index].boostRimWalkTarget(targetX, targetY)
  if targetX != mapX or targetY != mapY:
    discard snapWalkTarget(
      world.pudges[index].layer, targetX, targetY, targetX, targetY
    )
  world.pudges[index].breakShield()
  if world.pudges[index].hasMoveTarget and
      absDelta(world.pudges[index].moveX, targetX) <= WalkStickyTiles and
      absDelta(world.pudges[index].moveZ, targetY) <= WalkStickyTiles:
    return true
  let here = tileOf(world.pudges[index].position)
  if world.pudges[index].keepsRimInlandWalk(targetX, targetY, here):
    return true
  if here.x == int(targetX) and here.z == int(targetY) and
      not world.pudges[index].overlapsWestRim and
      not world.pudges[index].overlapsEastRim and
      not world.pudges[index].overlapsNorthRim and
      not world.pudges[index].overlapsSouthRim:
    # Already on the dest tile. A/W into the west/north wall used to
    # boost inland, walk 2 tiles, then dest the wall again — an orbit.
    # Halt (slide leftover vel) instead of chasing the tile center.
    world.pudges[index].haltWalk()
    world.pudges[index].attackTargetId = 0
    return true
  world.pudges[index].hasMoveTarget = true
  world.pudges[index].moveX = targetX
  world.pudges[index].moveZ = targetY
  world.pudges[index].attackTargetId = 0
  true

proc applyStop*(world: World, pudgeId: int32): bool =
  ## Halts in place: clears the move order and the attack target. A hook
  ## already past its cast point stays committed.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  world.pudges[index].haltWalk()
  world.pudges[index].attackTargetId = 0
  true

proc applyPing*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Records one team map ping. Communication only; never combat state.
  let index = world.pudgeIndex(pudgeId)
  if index < 0:
    return false
  if world.pings.len >= MaxWorldPings:
    world.pings.delete(0)
  world.pings.add Ping(
    team: world.pudges[index].team,
    byId: pudgeId,
    x: clamp(mapX, 0'i32, int32(GridTiles - 1)),
    y: clamp(mapY, 0'i32, int32(GridTiles - 1)),
    tick: world.tick
  )
  true

proc latestTeamPing*(world: World, team: Team, ping: var Ping): bool =
  ## Returns the newest ping recorded for one team.
  for i in countdown(world.pings.len - 1, 0):
    if world.pings[i].team == team:
      ping = world.pings[i]
      return true
  false

proc applyAttackTarget*(world: World, pudgeId, targetId: int32): bool =
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  if targetId == 0:
    world.pudges[index].attackTargetId = 0
    return true
  let target = world.pudgeIndex(targetId)
  if target < 0 or world.pudges[target].state == Dying:
    return false
  if world.pudges[target].team == world.pudges[index].team:
    return false
  if world.pudges[target].shieldTicks > 0:
    return false
  world.pudges[index].breakShield()
  world.pudges[index].attackTargetId = targetId
  world.pudges[index].hasMoveTarget = false
  true

proc grantRune(world: World, index: int, kind: RuneKind)

proc countProps(world: World, ownerId: int32, kind: PropKind): int32 =
  for prop in world.props:
    if prop.alive and prop.ownerId == ownerId and prop.kind == kind:
      inc result

proc tileHasProp(world: World, tileX, tileZ: int): bool =
  for prop in world.props:
    if prop.alive and int(prop.tileX) == tileX and int(prop.tileZ) == tileZ:
      return true
  false

proc onOwnShopPad(team: Team, tileX, tileZ: int): bool =
  let shopX = if team == WestTeam: WestShopX else: EastShopX
  max(abs(tileX - shopX), abs(tileZ - ShopZ)) <= int(ShopRadiusTiles)

proc onOwnSpawnPad(world: World, team: Team, tileX, tileZ: int): bool =
  for s in 0 ..< world.spawnLayout.west.len:
    let pad = world.spawnLayout.layoutPad(team, s)
    if abs(tileX - pad.x) <= int(FountainPadRadius) and
        abs(tileZ - pad.z) <= int(FountainPadRadius):
      return true
  false

proc ownBankTile(team: Team, tileX, tileZ: int): bool =
  if tileZ < PlayZMin or tileZ > PlayZMax:
    return false
  if riverTile(tileX) or islandTile(tileX, tileZ):
    return false
  if team == WestTeam:
    westBank(tileX)
  else:
    eastBank(tileX)

proc placementLegal(
    world: World,
    pudge: Pudge,
    tileX,
    tileZ: int
): bool =
  ## Own-bank walkable land, in drop range, not a shop/spawn grief tile.
  if pudge.state != Alive or pudge.inRiver or pudge.hookedBy != 0:
    return false
  if not ownBankTile(pudge.team, tileX, tileZ):
    return false
  if not walkableTile(homeLayer(pudge.team), int32(tileX), int32(tileZ)):
    return false
  if onOwnShopPad(pudge.team, tileX, tileZ) or
      world.onOwnSpawnPad(pudge.team, tileX, tileZ):
    return false
  let here = tileOf(pudge.position)
  if max(abs(here.x - tileX), abs(here.z - tileZ)) > int(PlaceRangeTiles):
    return false
  if world.tileHasProp(tileX, tileZ):
    return false
  for other in world.pudges:
    if other.state != Alive:
      continue
    let at = tileOf(other.position)
    if at.x == tileX and at.z == tileZ:
      return false
  true

proc spawnProp(
    world: World,
    pudge: Pudge,
    kind: PropKind,
    tileX,
    tileZ: int,
    hp,
    ticks: int32
) =
  world.props.add Prop(
    id: world.nextPropId,
    kind: kind,
    ownerId: pudge.id,
    team: pudge.team,
    tileX: int32(tileX),
    tileZ: int32(tileZ),
    hp: hp,
    maxHp: hp,
    ticksLeft: ticks,
    alive: true
  )
  inc world.nextPropId

proc applyPlaceProp(
    world: World,
    pudgeId,
    mapX,
    mapY: int32,
    kind: PropKind
): bool =
  let index = world.pudgeIndex(pudgeId)
  if index < 0:
    return false
  template pudge: untyped = world.pudges[index]
  let item = if kind == PropWall: ShopWall else: ShopMine
  let rank = pudge.itemRank[item]
  if rank <= 0:
    return false
  if kind == PropWall:
    if pudge.cooling(pudge.wallCooldown):
      return false
    if world.countProps(pudge.id, PropWall) >= maxWallsForRank(rank):
      return false
  else:
    if pudge.cooling(pudge.mineCooldown):
      return false
    if world.countProps(pudge.id, PropMine) >= maxMinesForRank(rank):
      return false
  var
    tileX = int(mapX)
    tileZ = int(mapY)
  if pudge.team == WestTeam:
    tileX = clamp(tileX, PlayWestMin, PlayWestMax)
  else:
    tileX = clamp(tileX, PlayEastMin, PlayEastMax)
  tileZ = clamp(tileZ, PlayZMin, PlayZMax)
  if not world.placementLegal(pudge, tileX, tileZ):
    return false
  pudge.breakShield()
  if kind == PropWall:
    world.spawnProp(
      pudge, PropWall, tileX, tileZ,
      wallMaxHp(rank), wallDurationTicks(rank)
    )
    pudge.wallCooldown = pudge.armedCooldown(wallCooldownTicks(rank))
  else:
    world.spawnProp(
      pudge, PropMine, tileX, tileZ,
      1, MineDurationTicks
    )
    pudge.mineCooldown = pudge.armedCooldown(MineCooldownTicks)
  true

proc applyPlaceWall*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Drops a palisade on a nearby own-bank tile. Spends cooldown.
  world.applyPlaceProp(pudgeId, mapX, mapY, PropWall)

proc applyPlaceMine*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Drops a hidden mine on a nearby own-bank tile. Spends cooldown.
  world.applyPlaceProp(pudgeId, mapX, mapY, PropMine)

proc hurtProp*(world: World, propId, amount, attackerId: int32): bool =
  ## Damages one living palisade. Mines ignore melee chips.
  discard attackerId
  if amount <= 0:
    return false
  for prop in world.props.mitems:
    if not prop.alive or prop.id != propId or prop.kind != PropWall:
      continue
    prop.hp = prop.hp - amount
    if prop.hp <= 0:
      prop.alive = false
      prop.hp = 0
    return true
  false

proc chipWallAt(world: World, tileX, tileZ: int, amount: int32, team: Team) =
  ## Enemy hooks that rebound off a palisade chip its HP.
  if amount <= 0:
    return
  for prop in world.props.mitems:
    if not prop.alive or prop.kind != PropWall:
      continue
    if int(prop.tileX) != tileX or int(prop.tileZ) != tileZ:
      continue
    if prop.team == team:
      return
    prop.hp = prop.hp - amount
    if prop.hp <= 0:
      prop.alive = false
      prop.hp = 0
    return

proc detonateMine(world: World, propIndex: int, hook: ptr Hook) =
  ## Explodes one mine: damages nearby enemies, optionally interrupts
  ## the hook that snagged it.
  if propIndex < 0 or propIndex >= world.props.len:
    return
  if not world.props[propIndex].alive or
      world.props[propIndex].kind != PropMine:
    return
  let
    blastAt = world.props[propIndex].propCenter
    ownerId = world.props[propIndex].ownerId
    owner = world.pudgeIndex(ownerId)
    rank =
      if owner >= 0: world.pudges[owner].itemRank[ShopMine]
      else: 1'i32
    dmg = mineBlastDamage(rank)
  world.props[propIndex].alive = false
  world.props[propIndex].hp = 0
  if hook != nil:
    hook.victimId = 0
    if hook.phase == HookFlying:
      hook.phase = HookReeling
  for i, pudge in world.pudges.mpairs:
    if pudge.state != Alive or pudge.team == world.props[propIndex].team:
      continue
    if not within(pudge.position, blastAt, MineBlastRadius + PudgeCollisionRadius):
      continue
    world.dealPudgeDamage(i, dmg, ownerId)

proc sweepMines(world: World, hook: var Hook): bool =
  ## Enemy hooks that clip a mine detonate it and break the throw.
  if hook.isGrapple:
    return false
  let reach = hook.radius + MineRadius
  var best = -1
  var bestDist = high(int64)
  for i, prop in world.props:
    if not prop.alive or prop.kind != PropMine:
      continue
    if prop.team == hook.team:
      continue
    let at = prop.propCenter
    if not segmentPointWithin(hook.prior, hook.position, at, reach):
      continue
    let d = distanceSquared(hook.position, at)
    if best < 0 or d < bestDist:
      best = i
      bestDist = d
  if best < 0:
    return false
  world.detonateMine(best, addr hook)
  true

proc compactProps(world: World) =
  var keep: seq[Prop]
  for prop in world.props:
    if prop.alive:
      keep.add prop
  world.props = keep

proc stepProps(world: World) =
  ## Expire gadgets, trigger walk-over mines, then drop the dead.
  for i in 0 ..< world.props.len:
    if not world.props[i].alive:
      continue
    if world.props[i].ticksLeft > 0:
      dec world.props[i].ticksLeft
    if world.props[i].ticksLeft <= 0:
      world.props[i].alive = false
      continue
    if world.props[i].kind != PropMine:
      continue
    let at = world.props[i].propCenter
    let reach = PudgeCollisionRadius + MineRadius
    for pudge in world.pudges:
      if pudge.state != Alive or pudge.team == world.props[i].team:
        continue
      if within(pudge.position, at, reach):
        world.detonateMine(i, nil)
        break
  world.compactProps()

proc bashNearbyWalls(world: World, index: int) =
  ## A melee swing also chips enemy palisades in reach.
  let dmg = world.pudges[index].meleeDamage
  let reach = MeleeRange + WorldScale div 4
  for prop in world.props.mitems:
    if not prop.alive or prop.kind != PropWall:
      continue
    if prop.team == world.pudges[index].team:
      continue
    if not within(world.pudges[index].position, prop.propCenter, reach):
      continue
    if world.pudges[index].hasCheat(CheatFlagGod):
      prop.hp = 0
      prop.alive = false
      continue
    prop.hp = prop.hp - dmg
    if prop.hp <= 0:
      prop.alive = false
      prop.hp = 0

proc applyBuyPower*(world: World, pudgeId, itemId: int32): bool =
  ## Spends gold on one catalog row; only at the base pad, only alive.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  if itemId < 0 or itemId > int32(ShopItem.high.ord):
    return false
  let item = ShopItem(itemId)
  if not world.pudges[index].inOwnShop:
    return false
  if world.pudges[index].gold < shopPrice(item):
    return false
  if item.isPermanent:
    let rank = world.pudges[index].itemRank[item]
    if rank >= ItemMaxRank:
      return false
    if rank == 0 and world.pudges[index].ownedPermanents >= InventorySlots:
      return false
    inc world.pudges[index].itemRank[item]
    world.pudges[index].gold = world.pudges[index].gold - shopPrice(item)
    return true
  case item
  of ShopFlask:
    if world.pudges[index].hp >= world.pudges[index].maxHp:
      return false
    world.pudges[index].hp = world.pudges[index].maxHp
  of ShopHaste:
    world.grantRune(index, RuneHaste)
  of ShopRegen:
    world.grantRune(index, RuneRegen)
  of ShopBigHook:
    world.grantRune(index, RuneBigHook)
  of ShopDoubleDamage:
    world.grantRune(index, RuneDoubleDamage)
  of ShopBoots, ShopLongshot, ShopWall, ShopMine:
    return false
  world.pudges[index].gold = world.pudges[index].gold - shopPrice(item)
  true

proc applyBuyUpgrade*(world: World, pudgeId, upgradeId: int32): bool =
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  if upgradeId < 0 or upgradeId > UpgradeKind.high.ord:
    return false
  let kind = UpgradeKind(upgradeId)
  if world.pudges[index].points <= 0:
    return false
  if world.pudges[index].upgrades[kind] >= MaxUpgradeLevel:
    return false
  dec world.pudges[index].points
  inc world.pudges[index].spent
  inc world.pudges[index].upgrades[kind]
  true

proc releasePendingHook(world: World, index: int) =
  ## Lets one wound-up hook fly from wherever the caster stands now,
  ## still aimed at the committed fine-grained target point.
  template pudge: untyped = world.pudges[index]
  let dest = worldAtFine(pudge.windupAimX, pudge.windupAimY)
  var direction = dest - pudge.position
  if direction.x == 0 and direction.z == 0:
    direction = WorldPoint(x: pudge.facing.x, z: pudge.facing.z)
  if direction.x == 0 and direction.z == 0:
    direction = WorldPoint(x: WorldScale, z: 0)
  let
    facing = heading(direction.x, direction.z)
    start = pudge.position + scaledPlanar(direction, WorldScale div 2)
  var
    range = hookRange(pudge.upgrades[UpgradeDistance])
    radius = hookRadius(pudge.upgrades[UpgradeRadius])
    damage = hookDamage(pudge.upgrades[UpgradeDamage])
  if pudge.windupGrapple:
    # The utility tool ignores combat upgrades and runes entirely.
    range = GrappleRange
    radius = GrappleRadius
    damage = 0
  elif pudge.hasBuff(RuneBigHook):
    range = range + range * RuneBigHookPercent div 100
    radius = radius + radius * RuneBigHookPercent div 100
    damage = bigHookDamage(damage)
  if not pudge.windupGrapple and pudge.hasBuff(RuneDoubleDamage):
    damage = damage * RuneDamageMul
  world.hooks.add Hook(
    id: world.nextHookId,
    ownerId: pudge.id,
    team: pudge.team,
    phase: HookFlying,
    position: start,
    origin: pudge.position,
    prior: start,
    heading: facing,
    range: range,
    speed: hookSpeed(pudge.upgrades[UpgradeSpeed]),
    peakSpeed: hookSpeed(pudge.upgrades[UpgradeSpeed]),
    radius: radius,
    damage: damage,
    isGrapple: pudge.windupGrapple,
    mighty: not pudge.windupGrapple and pudge.hasBuff(RuneBigHook)
  )
  inc world.nextHookId
  pudge.facing = facing
  pudge.bindPudgeBody()

proc applyHookFine*(world: World, pudgeId, fineX, fineY: int32): bool =
  ## Starts one hook cast aimed at a 1/256-tile point. The cast point
  ## (`HookWindupTicks`) roots the caster and telegraphs the throw; zero
  ## windup releases immediately.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  let pudge = world.pudges[index]
  if pudge.cooling(pudge.hookCooldown) or pudge.windupTicks > 0:
    return false
  for hook in world.hooks:
    if hook.ownerId == pudgeId and hook.phase != HookIdle:
      return false
  if fineX < 0 or fineX >= GridTiles * FineAimScale or
      fineY < 0 or fineY >= GridTiles * FineAimScale:
    return false
  let
    dest = worldAtFine(fineX, fineY)
    direction = dest - pudge.position
  if direction.x == 0 and direction.z == 0:
    return false
  world.pudges[index].breakShield()
  world.pudges[index].hookCooldown = world.pudges[index].armedCooldown(
    HookCooldownTicks
  )
  world.pudges[index].windupGrapple = false
  world.pudges[index].windupAimX = fineX
  world.pudges[index].windupAimY = fineY
  world.pudges[index].facing = heading(direction.x, direction.z)
  world.pudges[index].bindPudgeBody()
  world.pudges[index].setAnim(attackClip, restart = true)
  # The cast drops the walk order but keeps momentum: the windup brakes
  # hard (`coast`), so a sprinting caster skids through the cast point.
  world.pudges[index].hasMoveTarget = false
  inc world.pudges[index].hooksThrown
  if HookWindupTicks > 0:
    world.pudges[index].windupTicks = HookWindupTicks
  else:
    world.releasePendingHook(index)
  true

proc applyHookTo*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Tile-grain hook cast: aims at the tile center.
  if mapX < 0 or mapX >= GridTiles or mapY < 0 or mapY >= GridTiles:
    return false
  applyHookFine(world, pudgeId, fineOfTile(mapX), fineOfTile(mapY))

proc applyGrappleFine*(world: World, pudgeId, fineX, fineY: int32): bool =
  ## Starts one E-grapple cast: same cast point as the hook, its own
  ## cooldown, no damage. A latched solid yanks the caster to it.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  let pudge = world.pudges[index]
  if pudge.cooling(pudge.grappleCooldown) or pudge.windupTicks > 0:
    return false
  for hook in world.hooks:
    if hook.ownerId == pudgeId and hook.phase != HookIdle:
      return false
  if fineX < 0 or fineX >= GridTiles * FineAimScale or
      fineY < 0 or fineY >= GridTiles * FineAimScale:
    return false
  let
    dest = worldAtFine(fineX, fineY)
    direction = dest - pudge.position
  if direction.x == 0 and direction.z == 0:
    return false
  world.pudges[index].breakShield()
  world.pudges[index].grappleCooldown = world.pudges[index].armedCooldown(
    GrappleCooldownTicks
  )
  world.pudges[index].windupGrapple = true
  world.pudges[index].windupAimX = fineX
  world.pudges[index].windupAimY = fineY
  world.pudges[index].facing = heading(direction.x, direction.z)
  world.pudges[index].bindPudgeBody()
  world.pudges[index].setAnim(attackClip, restart = true)
  world.pudges[index].hasMoveTarget = false
  if HookWindupTicks > 0:
    world.pudges[index].windupTicks = HookWindupTicks
  else:
    world.releasePendingHook(index)
  true

proc applyGrappleTo*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Tile-grain grapple cast: aims at the tile center.
  if mapX < 0 or mapX >= GridTiles or mapY < 0 or mapY >= GridTiles:
    return false
  applyGrappleFine(world, pudgeId, fineOfTile(mapX), fineOfTile(mapY))

proc blinkLandable(
    world: World,
    pudge: Pudge,
    pos: WorldPoint
): bool =
  ## True when this point is legal blink ground: standable on the layer
  ## that owns it (bank or river), not a palisade, not inside a body.
  let tile = tileOf(pos)
  if tile.x < 0 or tile.x >= GridTiles or tile.z < 0 or tile.z >= GridTiles:
    return false
  let layer = layerAtX(tile.x)
  if not tileStandable(layer, tile.x, tile.z):
    return false
  if world.wallBlocksTile(tile.x, tile.z):
    return false
  if occupiedAt(world, pos, pudge.id, layer):
    return false
  true

proc blinkRayStops(
    world: World,
    pudge: Pudge,
    pos: WorldPoint,
    crossing: bool
): bool =
  ## True when the hop should halt here and keep the last legal landing.
  ## Empty river water is air: the ray flies over it. Range, not this
  ## test, is what stops a bank butcher short of the far side. An
  ## occupied river body stops the ray (back up). The fountain is air.
  ## Cliffs, off-map, dest-bank palisades, and dest-bank bodies stop
  ## it. Origin-bank walls and bodies do not stop a hop that has the
  ## range to clear the river.
  let tile = tileOf(pos)
  if tile.x < 0 or tile.x >= GridTiles or tile.z < 0 or tile.z >= GridTiles:
    return true
  let layer = layerAtX(tile.x)
  if layer == int32(RiverLayer):
    return occupiedAt(world, pos, pudge.id, layer)
  if not tileStandable(layer, tile.x, tile.z):
    return true
  if crossing and layer == pudge.layer:
    return false
  if world.wallBlocksTile(tile.x, tile.z):
    return true
  if occupiedAt(world, pos, pudge.id, layer):
    return true
  false

proc blinkInlandLanding(
    world: World,
    pudge: Pudge
): tuple[ok: bool, pos: WorldPoint] =
  ## One-tile inland probe used only when the origin itself is illegal
  ## (overlapping a wall or rim) and the ray had no legal step.
  let tile = tileOf(pudge.position)
  var
    inlandX = 0
    inlandZ = 0
  if tile.x < PlayWestMin:
    inlandX = 1
  elif tile.x > PlayEastMax:
    inlandX = -1
  if tile.z < PlayZMin:
    inlandZ = 1
  elif tile.z > PlayZMax:
    inlandZ = -1
  if inlandX == 0 and inlandZ == 0:
    if westBank(tile.x) and tile.x <= PlayWestMin:
      inlandX = 1
    elif eastBank(tile.x) and tile.x >= PlayEastMax:
      inlandX = -1
  const probes = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (1, -1), (-1, 1), (-1, -1)
  ]
  if inlandX != 0 or inlandZ != 0:
    let preferred = worldAtTile(tile.x + inlandX, tile.z + inlandZ)
    if world.blinkLandable(pudge, preferred):
      return (true, preferred)
  for (dx, dz) in probes:
    if dx == inlandX and dz == inlandZ:
      continue
    let trial = worldAtTile(tile.x + dx, tile.z + dz)
    if world.blinkLandable(pudge, trial):
      return (true, trial)
  (false, pudge.position)

proc blinkLanding(
    world: World,
    pudge: Pudge,
    dest: WorldPoint
): tuple[ok: bool, pos: WorldPoint] =
  ## Walks the blink ray, capped at `BlinkRange`, and returns the
  ## farthest standable, unoccupied tile along it, including river
  ## water. A hop from the water can still land on a bank. Cliffs,
  ## palisades, and occupied circles stop the ray: land on the last
  ## legal point in front of them instead of rejecting the order.
  var
    goal = dest
    direction = WorldPoint(x: dest.x - pudge.position.x, z: dest.z - pudge.position.z)
  if direction.x == 0 and direction.z == 0:
    direction = WorldPoint(x: pudge.facing.x, z: pudge.facing.z)
  if direction.x == 0 and direction.z == 0:
    return (false, pudge.position)
  let travel = integerSqrt(
    int64(direction.x) * direction.x + int64(direction.z) * direction.z
  )
  if travel > BlinkRange:
    let step = scaledPlanar(direction, BlinkRange)
    goal = WorldPoint(
      x: pudge.position.x + step.x,
      z: pudge.position.z + step.z
    )
  let
    dx = int64(goal.x) - int64(pudge.position.x)
    dz = int64(goal.z) - int64(pudge.position.z)
    span = integerSqrt(dx * dx + dz * dz)
  if span <= 0:
    return (false, pudge.position)
  let
    goalLayer = layerAt(goal)
    crossing =
      (goalLayer == int32(WestLayer) or goalLayer == int32(EastLayer)) and
      goalLayer != pudge.layer
    stepLen = max(int64(WorldScale div 4), 1)
    n = max(int32((span + stepLen - 1) div stepLen), 1'i32)
  var
    found = false
    best = pudge.position
  for i in 1'i32 .. n:
    let trial = WorldPoint(
      x: pudge.position.x + int32(dx * int64(i) div int64(n)),
      y: pudge.position.y,
      z: pudge.position.z + int32(dz * int64(i) div int64(n))
    )
    if world.blinkRayStops(pudge, trial, crossing):
      break
    if world.blinkLandable(pudge, trial):
      found = true
      best = trial
  if found:
    return (true, best)
  if not world.blinkLandable(pudge, pudge.position):
    return world.blinkInlandLanding(pudge)
  (false, pudge.position)

proc extendOwnedHookRange(world: World, pudgeId, hop: int32) =
  ## Adds the actual blink hop to every chain this butcher still has
  ## out. Remaining outbound is `range - traveled`; growing `range`
  ## by the hop keeps the extra stretch from eating leftover flight.
  ## The head stays where it is. Idle (no chain) is a no-op. `hop` ≤ 0
  ## adds nothing, so a vanishingly short blink cannot farm length.
  if hop <= 0:
    return
  for hook in world.hooks.mitems:
    if hook.ownerId != pudgeId or hook.phase == HookIdle:
      continue
    let next = hook.range + hop
    hook.range =
      if next < hook.range: high(int32)
      else: next

proc applyBlinkFine*(world: World, pudgeId, fineX, fineY: int32): bool =
  ## Instant dodge teleport along the aimed heading, capped at
  ## `BlinkRange`. Lands on the farthest legal tile along that ray,
  ## including river water. Windup still blocks (the head has not
  ## left the hand). A hooked victim cannot hop. Once a chain is in
  ## the air, blink is allowed and the hop distance is added to that
  ## hook's remaining range.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  template pudge: untyped = world.pudges[index]
  if pudge.hookedBy != 0 or pudge.windupTicks > 0:
    return false
  if world.rotAffected(pudge):
    return false
  if pudge.cooling(pudge.blinkCooldown):
    return false
  if fineX < 0 or fineX >= GridTiles * FineAimScale or
      fineY < 0 or fineY >= GridTiles * FineAimScale:
    return false
  let dest = worldAtFine(fineX, fineY)
  let landing = world.blinkLanding(pudge, dest)
  if not landing.ok:
    return false
  let headingDelta = WorldPoint(
    x: landing.pos.x - pudge.position.x,
    z: landing.pos.z - pudge.position.z
  )
  if headingDelta.x == 0 and headingDelta.z == 0:
    return false
  pudge.breakShield()
  pudge.blinkFrom = pudge.position
  pudge.justBlinked = true
  pudge.position = landing.pos
  pudge.facing = heading(headingDelta.x, headingDelta.z)
  world.settlePudge(index, false)
  pudge.haltWalk()
  pudge.velX = 0
  pudge.velZ = 0
  pudge.attackTargetId = 0
  pudge.blinkCooldown = pudge.armedCooldown(BlinkCooldownTicks)
  pudge.setAnim(idleClip)
  let hop64 = integerSqrt(distanceSquared(pudge.blinkFrom, pudge.position))
  let hop =
    if hop64 <= 0: 0'i32
    elif hop64 > int64(high(int32)): high(int32)
    else: int32(hop64)
  world.extendOwnedHookRange(pudgeId, hop)
  true

proc applyBlinkTo*(world: World, pudgeId, mapX, mapY: int32): bool =
  ## Tile-grain blink: aims at the tile center.
  if mapX < 0 or mapX >= GridTiles or mapY < 0 or mapY >= GridTiles:
    return false
  applyBlinkFine(world, pudgeId, fineOfTile(mapX), fineOfTile(mapY))

proc applyRotToggle*(world: World, pudgeId: int32): bool =
  ## Flips Rot. No mana, no cooldown. Acting breaks spawn shield.
  ## Turning it on primes the pulse timer so the first tick hurts.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or world.pudges[index].state == Dying:
    return false
  template pudge: untyped = world.pudges[index]
  pudge.breakShield()
  pudge.rotOn = not pudge.rotOn
  if pudge.rotOn:
    pudge.rotTicks = RotPeriodTicks
  else:
    pudge.rotTicks = 0
  true

proc stepWindups(world: World) =
  ## Counts down cast points and releases hooks whose windup finished.
  for i in 0 ..< world.pudges.len:
    if world.pudges[i].state != Alive or world.pudges[i].windupTicks <= 0:
      continue
    dec world.pudges[i].windupTicks
    if world.pudges[i].windupTicks == 0:
      world.releasePendingHook(i)

proc grantCheatGold(pudge: var Pudge, amount: int32) =
  let add = if amount > 0: amount else: CheatGoldAmount
  let next = int64(pudge.gold) + int64(add)
  if next > int32.high:
    pudge.gold = int32.high
  else:
    pudge.gold = int32(next)

proc fillShopGoods(pudge: var Pudge) =
  for item in ShopBoots..ShopMine:
    pudge.itemRank[item] = ItemMaxRank

proc clearCooldowns(pudge: var Pudge) =
  pudge.hookCooldown = 0
  pudge.grappleCooldown = 0
  pudge.blinkCooldown = 0
  pudge.wallCooldown = 0
  pudge.mineCooldown = 0

proc applyCheat*(world: World, pudgeId, kindId, amount: int32): bool =
  ## Applies one WC3-style cheat to a butcher. Always succeeds for a
  ## known kind so typing the code is never a silent no-op; win/lose
  ## after the match has already ended is the one rejection.
  let index = world.pudgeIndex(pudgeId)
  if index < 0 or not validCheatKind(kindId):
    return false
  let kind = CheatKind(kindId)
  template pudge: untyped = world.pudges[index]
  case kind
  of CheatGreed:
    pudge.grantCheatGold(amount)
    pudge.fillShopGoods()
  of CheatGold:
    pudge.grantCheatGold(amount)
  of CheatGoods:
    pudge.fillShopGoods()
  of CheatGod:
    pudge.cheatFlags = pudge.cheatFlags xor CheatFlagGod
    if pudge.hasCheat(CheatFlagGod) and pudge.state == Alive:
      pudge.hp = pudge.maxHp
  of CheatMana:
    pudge.cheatFlags = pudge.cheatFlags xor CheatFlagMana
    if pudge.hasCheat(CheatFlagMana):
      pudge.clearCooldowns()
  of CheatCool:
    pudge.clearCooldowns()
  of CheatPower:
    for upgrade in UpgradeKind:
      pudge.upgrades[upgrade] = MaxUpgradeLevel
    if pudge.state == Alive:
      pudge.hp = pudge.maxHp
  of CheatWin:
    if world.gameOver:
      return false
    world.teamKills[pudge.team.ord] = max(
      world.teamKills[pudge.team.ord], world.killGoal
    )
    world.gameOver = true
    world.winner = pudge.team
  of CheatLose:
    if world.gameOver:
      return false
    let other = if pudge.team == WestTeam: EastTeam else: WestTeam
    world.teamKills[other.ord] = max(
      world.teamKills[other.ord], world.killGoal
    )
    world.gameOver = true
    world.winner = other
  true

proc applyReplayAction*(world: World, action: ReplayAction) =
  case action.kind
  of ActionWalkTo:
    discard applyWalkTo(world, action.pudgeId, action.first, action.second)
  of ActionHookTo:
    discard applyHookTo(world, action.pudgeId, action.first, action.second)
  of ActionHookToFine:
    discard applyHookFine(world, action.pudgeId, action.first, action.second)
  of ActionGrappleTo:
    discard applyGrappleTo(world, action.pudgeId, action.first, action.second)
  of ActionGrappleToFine:
    discard applyGrappleFine(
      world, action.pudgeId, action.first, action.second
    )
  of ActionBuyPower:
    discard applyBuyPower(world, action.pudgeId, action.first)
  of ActionBlinkTo:
    discard applyBlinkTo(world, action.pudgeId, action.first, action.second)
  of ActionBlinkToFine:
    discard applyBlinkFine(
      world, action.pudgeId, action.first, action.second
    )
  of ActionPlaceWall:
    discard applyPlaceWall(world, action.pudgeId, action.first, action.second)
  of ActionPlaceMine:
    discard applyPlaceMine(world, action.pudgeId, action.first, action.second)
  of ActionCheat:
    discard applyCheat(
      world, action.pudgeId, action.first, action.second
    )
  of ActionRotToggle:
    discard applyRotToggle(world, action.pudgeId)
  of ActionAttackTarget:
    discard applyAttackTarget(world, action.pudgeId, action.first)
  of ActionBuyUpgrade:
    discard applyBuyUpgrade(world, action.pudgeId, action.first)
  of ActionStop:
    discard applyStop(world, action.pudgeId)
  of ActionPing:
    discard applyPing(world, action.pudgeId, action.first, action.second)
  of ActionTakeOver:
    # Provenance only: playback replays recorded actions regardless of
    # who issued them.
    discard
  else:
    discard

proc isReplaceableOrder(kind: IntentKind): bool =
  ## Walk, attack, and stop are exclusive: only the latest one should
  ## land at the next hero turn. Spammed RMB must not leave a walk
  ## after an attack (or the reverse) in the same drain.
  kind in {IntentWalk, IntentAttack, IntentStop}

proc queueIntent*(game: Game, intent: HumanIntent) =
  ## Buffers one human command until its seat's next hero turn. The
  ## queue is bounded; a flood drops the oldest commands first.
  ## Replaceable orders for the same seat collapse to the newest one so
  ## a missed enemy pick that becomes a walk cannot cancel a prior
  ## attack queued in the same tick window.
  if intent.kind.isReplaceableOrder:
    var kept: seq[HumanIntent]
    for pending in game.humanIntents:
      if pending.slot == intent.slot and pending.kind.isReplaceableOrder:
        continue
      kept.add pending
    game.humanIntents = kept
  if game.humanIntents.len >= MaxQueuedIntents:
    game.humanIntents.delete(0)
  game.humanIntents.add intent

proc idleAcquireTarget(world: World, index: int): int32 =
  ## Nearest living, unshielded enemy within auto-acquire range while the
  ## butcher has no move or attack order. Returns 0 when idle acquire
  ## should not fire (busy, casting, river, hooked, dead).
  if index < 0 or index >= world.pudges.len:
    return 0
  let hero = world.pudges[index]
  if hero.state == Dying or hero.inRiver or hero.hookedBy != 0 or
      hero.windupTicks > 0 or hero.hasMoveTarget or hero.attackTargetId != 0:
    return 0
  var best = int64(AutoAcquireRange) * int64(AutoAcquireRange) + 1
  for other in world.pudges:
    if other.id == hero.id or other.state == Dying or other.team == hero.team or
        other.shieldTicks > 0:
      continue
    let d = distanceSquared(hero.position, other.position)
    if d < best:
      best = d
      result = other.id
  if best > int64(AutoAcquireRange) * int64(AutoAcquireRange):
    result = 0

proc runHumanIntents*(game: Game, slot: int) =
  ## Drains one human seat's queued commands through the same
  ## record-then-apply path the bot host functions use, so live play,
  ## replays, and hash checks cannot diverge. After the queue is empty,
  ## an idle butcher auto-acquires a nearby enemy (recorded on the tape).
  if slot < 0 or slot >= game.world.pudges.len:
    return
  let
    pudgeId = game.world.pudges[slot].id
    tick = uint32(game.world.tick)
  var
    kept: seq[HumanIntent]
    sawOrder = false
  for intent in game.humanIntents:
    if int(intent.slot) != slot:
      kept.add intent
      continue
    if intent.kind.isReplaceableOrder:
      sawOrder = true
    var accepted = false
    let recorder = game.recorder
    try:
      case intent.kind
      of IntentWalk:
        if recorder != nil:
          recorder.recordWalkTo(tick, pudgeId, intent.a, intent.b)
        accepted = applyWalkTo(game.world, pudgeId, intent.a, intent.b)
      of IntentHook:
        if recorder != nil:
          recorder.recordHookTo(tick, pudgeId, intent.a, intent.b)
        accepted = applyHookTo(game.world, pudgeId, intent.a, intent.b)
      of IntentHookFine:
        if recorder != nil:
          recorder.recordHookToFine(tick, pudgeId, intent.a, intent.b)
        accepted = applyHookFine(game.world, pudgeId, intent.a, intent.b)
      of IntentGrapple:
        if recorder != nil:
          recorder.recordGrappleTo(tick, pudgeId, intent.a, intent.b)
        accepted = applyGrappleTo(game.world, pudgeId, intent.a, intent.b)
      of IntentGrappleFine:
        if recorder != nil:
          recorder.recordGrappleToFine(tick, pudgeId, intent.a, intent.b)
        accepted = applyGrappleFine(
          game.world, pudgeId, intent.a, intent.b
        )
      of IntentBuyPower:
        if recorder != nil:
          recorder.recordBuyPower(tick, pudgeId, intent.a)
        accepted = applyBuyPower(game.world, pudgeId, intent.a)
      of IntentAttack:
        if recorder != nil:
          recorder.recordAttackTarget(tick, pudgeId, intent.a)
        accepted = applyAttackTarget(game.world, pudgeId, intent.a)
      of IntentBuy:
        if recorder != nil:
          recorder.recordBuyUpgrade(tick, pudgeId, intent.a)
        accepted = applyBuyUpgrade(game.world, pudgeId, intent.a)
      of IntentStop:
        if recorder != nil:
          recorder.recordStop(tick, pudgeId)
        accepted = applyStop(game.world, pudgeId)
      of IntentPing:
        if recorder != nil:
          recorder.recordPing(tick, pudgeId, intent.a, intent.b)
        accepted = applyPing(game.world, pudgeId, intent.a, intent.b)
      of IntentBlink:
        if recorder != nil:
          recorder.recordBlinkTo(tick, pudgeId, intent.a, intent.b)
        accepted = applyBlinkTo(game.world, pudgeId, intent.a, intent.b)
      of IntentBlinkFine:
        if recorder != nil:
          recorder.recordBlinkToFine(tick, pudgeId, intent.a, intent.b)
        accepted = applyBlinkFine(
          game.world, pudgeId, intent.a, intent.b
        )
      of IntentPlaceWall:
        if recorder != nil:
          recorder.recordPlaceWall(tick, pudgeId, intent.a, intent.b)
        accepted = applyPlaceWall(game.world, pudgeId, intent.a, intent.b)
      of IntentPlaceMine:
        if recorder != nil:
          recorder.recordPlaceMine(tick, pudgeId, intent.a, intent.b)
        accepted = applyPlaceMine(game.world, pudgeId, intent.a, intent.b)
      of IntentCheat:
        if recorder != nil:
          recorder.recordCheat(tick, pudgeId, intent.a, intent.b)
        accepted = applyCheat(game.world, pudgeId, intent.a, intent.b)
      of IntentRot:
        if recorder != nil:
          recorder.recordRotToggle(tick, pudgeId)
        accepted = applyRotToggle(game.world, pudgeId)
    except ReplayError as error:
      game.recordingError = error.msg
    if game.intentResults.len >= MaxQueuedIntents:
      game.intentResults.delete(0)
    game.intentResults.add IntentResult(
      slot: intent.slot,
      kind: intent.kind,
      accepted: accepted,
      a: intent.a,
      b: intent.b,
      tick: game.world.tick
    )
  game.humanIntents = kept

  # A fresh walk/attack/stop this turn is an instruction: do not
  # immediately re-acquire (so S is not a no-op on the same tick).
  if sawOrder:
    return
  let acquireId = idleAcquireTarget(game.world, slot)
  if acquireId == 0:
    return
  let recorder = game.recorder
  try:
    if recorder != nil:
      recorder.recordAttackTarget(tick, pudgeId, acquireId)
    if applyAttackTarget(game.world, pudgeId, acquireId):
      if game.intentResults.len >= MaxQueuedIntents:
        game.intentResults.delete(0)
      game.intentResults.add IntentResult(
        slot: int32(slot),
        kind: IntentAttack,
        accepted: true,
        a: acquireId,
        tick: game.world.tick
      )
  except ReplayError as error:
    game.recordingError = error.msg

proc applyTakeOver*(game: Game, slot: int, human: bool): bool =
  ## Switches who drives one seat mid-match and records the handoff.
  ## Taking over always works on a valid seat; releasing requires a
  ## loaded bot script (autopilot), or the butcher would freeze. The
  ## world never changes here, so playback treats the tape entry as
  ## provenance only and hashes stay exact.
  if slot < 0 or slot >= game.world.pudges.len:
    return false
  if game.world.gameOver:
    return false
  let seated = slot in game.humanSlots
  if human == seated:
    return false
  if human:
    game.humanSlots.add slot
  else:
    if slot >= game.heroVms.len or game.heroVms[slot] == nil:
      return false
    game.humanSlots.delete(game.humanSlots.find(slot))
    # Parked commands from the human stint must not fire on a retake.
    var kept: seq[HumanIntent]
    for intent in game.humanIntents:
      if int(intent.slot) != slot:
        kept.add intent
    game.humanIntents = kept
  if game.recorder != nil:
    try:
      game.recorder.recordTakeOver(
        uint32(game.world.tick),
        game.world.pudges[slot].id,
        if human: ControllerHuman else: ControllerBot
      )
    except ReplayError as error:
      game.recordingError = error.msg
  true

proc fogTeamOf*(world: World, pudgeId: int32): int =
  ## Team ordinal a spectator inherits from this butcher, or -1 if the
  ## id is missing (omniscient fallback).
  let index = pudgeIndex(world, pudgeId)
  if index < 0:
    return -1
  world.pudges[index].team.ord

proc fogBaseVisible*(team: int, position: WorldPoint): bool =
  ## Your base is your entire home bank: the whole friendly side up to
  ## the river stays lit. The enemy bank gets no such courtesy.
  let (tx, _) = tileOf(position)
  if team == WestTeam.ord:
    tx <= PlayWestMax
  else:
    tx >= PlayEastMin

proc fogCanSeeTeam*(world: World, team: int, position: WorldPoint): bool =
  ## Whether `team` currently lights `position`. `team < 0` is omniscient.
  if team < 0:
    return true
  let (tx, _) = tileOf(position)
  if riverTile(tx):
    return true
  if fogBaseVisible(team, position):
    return true
  let radius = int64(SightRadiusTiles) * WorldScale
  for pudge in world.pudges:
    if pudge.team.ord != team or pudge.state == Dying:
      continue
    if distanceSquared(pudge.position, position) <= radius * radius:
      return true
  false

proc fogShownPudgeTeam*(world: World, team: int, pudge: Pudge): bool =
  ## Own team always shows; enemies only inside the shared sight.
  team < 0 or pudge.team.ord == team or
    fogCanSeeTeam(world, team, pudge.position)

proc scriptTeamOf(world: World, pudgeId: int32): tuple[team: Team, teamOrd: int] =
  let viewer = world.pudgeIndex(pudgeId)
  if viewer >= 0:
    let team = world.pudges[viewer].team
    (team, team.ord)
  else:
    (WestTeam, WestTeam.ord)

proc worldObjectCount*(world: World, pudgeId: int32): int =
  ## Fog-clipped observation for one butcher: own team always, enemies
  ## and walls only inside shared sight (home bank, river, and living
  ## teammates within `SightRadiusTiles`). Enemy mines stay hidden.
  let (team, teamOrd) = world.scriptTeamOf(pudgeId)
  world.scriptObjects.setLen(world.pudges.len + world.props.len)
  world.scriptObjectCount = 0
  for pudge in world.pudges:
    if not fogShownPudgeTeam(world, teamOrd, pudge):
      continue
    world.scriptObjects[world.scriptObjectCount] = WorldObject(
      id: pudge.id,
      kind: PudgeObjectKind,
      team: pudge.team,
      layer: pudge.layer,
      position: pudge.position,
      hp: max(pudge.hp, 0'i32),
      maxHp: pudge.maxHp,
      alive: pudge.state == Alive,
      hooked: pudge.hookedBy != 0,
      shielded: pudge.shieldTicks > 0,
      rotting: pudge.rotOn
    )
    inc world.scriptObjectCount
  for prop in world.props:
    if not prop.alive or not propVisibleTo(prop, team):
      continue
    if prop.kind == PropWall and
        not fogCanSeeTeam(world, teamOrd, prop.propCenter):
      continue
    world.scriptObjects[world.scriptObjectCount] = WorldObject(
      id: prop.id,
      kind: if prop.kind == PropWall: WallObjectKind else: MineObjectKind,
      team: prop.team,
      layer: homeLayer(prop.team),
      position: prop.propCenter,
      hp: max(prop.hp, 0'i32),
      maxHp: prop.maxHp,
      alive: true,
      hooked: false,
      shielded: false
    )
    inc world.scriptObjectCount
  world.scriptObjectCount

proc worldObjectAt*(
    world: World,
    pudgeId: int32,
    index: int,
    value: var WorldObject
): bool =
  if index < 0 or index >= worldObjectCount(world, pudgeId):
    return false
  value = world.scriptObjects[index]
  true

proc worldHookCount*(world: World, pudgeId: int32): int =
  ## Flying or reeling hooks whose head is inside this butcher's fog.
  let teamOrd = world.scriptTeamOf(pudgeId).teamOrd
  world.scriptHookIdx.setLen(world.hooks.len)
  world.scriptHookCount = 0
  for i, hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if not fogCanSeeTeam(world, teamOrd, hook.position):
      continue
    world.scriptHookIdx[world.scriptHookCount] = i
    inc world.scriptHookCount
  world.scriptHookCount

proc worldHookAt*(
    world: World,
    pudgeId: int32,
    index: int,
    value: var Hook
): bool =
  if index < 0 or index >= worldHookCount(world, pudgeId):
    return false
  value = world.hooks[world.scriptHookIdx[index]]
  true

proc worldRuneCount*(world: World, pudgeId: int32): int =
  ## Runes inside this butcher's fog. They spawn in the river, which
  ## stays lit, so this usually matches the full list.
  let teamOrd = world.scriptTeamOf(pudgeId).teamOrd
  world.scriptRuneIdx.setLen(world.runes.len)
  world.scriptRuneCount = 0
  for i, rune in world.runes:
    if not fogCanSeeTeam(world, teamOrd, rune.position):
      continue
    world.scriptRuneIdx[world.scriptRuneCount] = i
    inc world.scriptRuneCount
  world.scriptRuneCount

proc worldRuneAt*(
    world: World,
    pudgeId: int32,
    index: int,
    value: var Rune
): bool =
  if index < 0 or index >= worldRuneCount(world, pudgeId):
    return false
  value = world.runes[world.scriptRuneIdx[index]]
  true

proc stepMovement(world: World) =
  for i in 0 ..< world.pudges.len:
    if world.pudges[i].state == Dying or world.pudges[i].hookedBy != 0:
      continue
    # Soft-nudge off a rim strip every tick, including at rest, without
    # dropping a queued walk. Hook/blink must not be required to unstick.
    world.nudgePudgeOntoWalkable(i)
    if world.pudges[i].windupTicks > 0:
      # The cast point brakes hard instead of rooting: a sprinting
      # caster skids while winding up and the hook departs mid-slide.
      # A queued move order resumes afterward.
      world.coast(i)
      continue
    if not world.pudges[i].hasMoveTarget:
      if world.pudges[i].attackTargetId == 0:
        world.pudges[i].haltWalk()
        world.coast(i)
      continue
    let dest = worldAtTile(int(world.pudges[i].moveX), int(world.pudges[i].moveZ))
    if within(world.pudges[i].position, dest, WorldScale div 3) and
        world.pudges[i].walkRested:
      world.prepWalkContext(i)
      if layerTerrainWalkable(world.pudges[i].body.pos):
        world.pudges[i].haltWalk()
        world.coast(i)
        continue
    world.locomotion(i, dest - world.pudges[i].position)

proc stepRiver(world: World) =
  ## Periodic drown damage so camping in the drink is not free. No
  ## locomotion: a river butcher walks with WASD/RMB on `RiverLayer`
  ## like land, and leaves by blink or by being hooked out. A forced
  ## walk to `homeBankX` was the old climb-out; that is gone.
  for i in 0 ..< world.pudges.len:
    if world.pudges[i].state != Alive or not world.pudges[i].inRiver:
      continue
    if world.pudges[i].hookedBy != 0:
      continue
    inc world.pudges[i].drownTicks
    if world.pudges[i].drownTicks >= DrownPeriodTicks:
      world.pudges[i].drownTicks = 0
      world.dealPudgeDamage(
        i, DrownDamage, world.pudges[i].lastHurtBy
      )

proc stepRot(world: World) =
  ## Pulse damage from every live Rot disk. Slow is applied in
  ## `moveSpeed`; this only hurts. Overlapping auras stack damage.
  ## Spawn shield blocks incoming rot except the caster's self-hit.
  for pudge in world.pudges.mitems:
    if pudge.state != Alive and pudge.rotOn:
      pudge.rotOn = false
      pudge.rotTicks = 0
  var pulses: seq[int]
  for i in 0 ..< world.pudges.len:
    if world.pudges[i].state != Alive or not world.pudges[i].rotOn:
      continue
    inc world.pudges[i].rotTicks
    if world.pudges[i].rotTicks >= RotPeriodTicks:
      world.pudges[i].rotTicks = 0
      pulses.add i
  for ownerIdx in pulses:
    if world.pudges[ownerIdx].state != Alive or
        not world.pudges[ownerIdx].rotOn:
      continue
    let
      ownerId = world.pudges[ownerIdx].id
      origin = world.pudges[ownerIdx].position
    for i in 0 ..< world.pudges.len:
      if world.pudges[i].state != Alive:
        continue
      if not within(world.pudges[i].position, origin, RotRadius):
        continue
      if world.pudges[i].shieldTicks > 0 and world.pudges[i].id != ownerId:
        continue
      world.dealPudgeDamage(i, RotDamage, ownerId)

proc islandFountainPos*(): WorldPoint =
  ## World center of the mid-river fountain rocks.
  worldAtTile(IslandCenterX, IslandCenterZ)

proc onIslandFountain*(pudge: Pudge): bool =
  ## Neutral WC3 fountain aura: both teams, any layer, including hooked.
  pudge.state == Alive and
    within(pudge.position, islandFountainPos(), IslandFountainRadius)

proc onOwnPad*(world: World, pudge: Pudge): bool =
  ## Returns whether this butcher stands on a friendly spawn pad.
  if pudge.state != Alive or pudge.inRiver:
    return false
  let tile = tileOf(pudge.position)
  world.onOwnSpawnPad(pudge.team, tile.x, tile.z)

proc stepFountain(world: World) =
  ## Spawn-pad trickle plus the mid-river fountain of health.
  let
    padPulse = world.tick mod FountainHealPeriodTicks == 0
    islandPulse = world.tick mod IslandFountainHealPeriodTicks == 0
  if not padPulse and not islandPulse:
    return
  let fountain = islandFountainPos()
  for pudge in world.pudges.mitems:
    if pudge.state != Alive or pudge.hp >= pudge.maxHp:
      continue
    var heal = 0'i32
    if padPulse and pudge.hookedBy == 0 and world.onOwnPad(pudge):
      heal += max(1'i32, pudge.maxHp * FountainHealPercent div 100)
    if islandPulse and
        within(pudge.position, fountain, IslandFountainRadius):
      heal += islandFountainHeal(pudge.maxHp)
    if heal <= 0:
      continue
    pudge.hp = min(pudge.hp + heal, pudge.maxHp)

proc grantRune(world: World, index: int, kind: RuneKind) =
  ## Hands one rune power to a butcher. A single buff slot: picking a
  ## second rune overwrites whatever was running.
  world.pudges[index].buffKind = kind
  world.pudges[index].buffTicks = RuneBuffTicks
  world.pudges[index].justRune = true
  inc world.pudges[index].runesTaken

proc spawnRune(world: World) =
  ## Drops one rune at a random river end, on the water midline. X is the
  ## center of tile `RiverCenterX` — the same axis as the visual water
  ## sheet and river bed — so a bank-stander cannot reach it dry.
  let
    fromNorth = world.rng.chance(50)
    zTile = if fromNorth: int32(PlayZMin) else: int32(PlayZMax)
    kind = RuneKind(world.rng.below(int32(RuneKind.high.ord) + 1))
  world.runes.add Rune(
    id: world.nextRuneId,
    kind: kind,
    position: worldAtTile(RiverCenterX, int(zTile)),
    dir: if fromNorth: 1'i32 else: -1'i32,
    spawnTick: world.tick
  )
  inc world.nextRuneId

proc stepRunes(world: World) =
  ## Spawns on the period clock, drifts every rune with the current,
  ## grabs by body contact, and pulses Regen heals.
  if world.runePeriod > 0:
    dec world.runeClock
    if world.runeClock <= 0:
      world.runeClock = world.runePeriod
      world.spawnRune()
  var keep: seq[Rune]
  for rune in world.runes.mitems:
    rune.position.z = rune.position.z + rune.dir * RuneDriftPerTick
    let tile = tileOf(rune.position)
    if tile.z < PlayZMin or tile.z > PlayZMax:
      continue
    var taken = false
    for i in 0 ..< world.pudges.len:
      if world.pudges[i].state != Alive:
        continue
      if within(world.pudges[i].position, rune.position, RunePickupRadius):
        world.grantRune(i, rune.kind)
        taken = true
        break
    if not taken:
      keep.add rune
  world.runes = keep
  if world.tick mod RuneRegenPeriodTicks == 0:
    for pudge in world.pudges.mitems:
      if pudge.state != Alive:
        continue
      var pct = 0'i32
      if pudge.hasBuff(RuneRegen):
        pct += RuneRegenPercent
      if pct <= 0 or pudge.hp >= pudge.maxHp:
        continue
      let heal = max(1'i32, pudge.maxHp * pct div 100)
      pudge.hp = min(pudge.hp + heal, pudge.maxHp)

proc stepMelee(world: World) =
  for i in 0 ..< world.pudges.len:
    world.pudges[i].damageLanded = false
    if world.pudges[i].state == Dying or
        world.pudges[i].attackTargetId == 0 or
        world.pudges[i].inRiver or
        world.pudges[i].windupTicks > 0:
      if world.pudges[i].swingTicks > 0:
        dec world.pudges[i].swingTicks
      continue
    let target = world.pudgeIndex(world.pudges[i].attackTargetId)
    if target < 0 or world.pudges[target].state == Dying or
        world.pudges[target].shieldTicks > 0:
      world.pudges[i].attackTargetId = 0
      continue
    let dest = world.pudges[target].position
    if not within(
        world.pudges[i].position,
        dest,
        MeleeRange + WorldScale div 4
      ):
      world.locomotion(i, dest - world.pudges[i].position)
      continue
    world.pudges[i].hasMoveTarget = false
    world.coast(i)
    world.pudges[i].faceToward(dest)
    world.pudges[target].faceToward(world.pudges[i].position)
    if world.pudges[i].swingTicks > 0:
      dec world.pudges[i].swingTicks
      continue
    world.pudges[i].swingTicks = world.pudges[i].attackPeriod
    world.pudges[i].setAnim(attackClip, restart = true)
    world.pudges[i].damageLanded = true
    world.dealPudgeDamage(
      target, world.pudges[i].meleeDamage, world.pudges[i].id
    )
    world.bashNearbyWalls(i)

proc releaseHookedVictim(world: World, victimId, exceptHookId: int32) =
  for other in world.hooks.mitems:
    if other.id != exceptHookId and other.victimId == victimId:
      other.victimId = 0
      if other.phase != HookIdle:
        other.phase = HookReeling

proc reboundOnRim(tileX, tileZ: int): bool =
  ## True when the head is on the unwalkable rock that rings the
  ## playable field, including coordinates past the 128-tile grid.
  tileX < PlayWestMin or tileX > PlayEastMax or
    tileZ < PlayZMin or tileZ > PlayZMax

proc recordBounce(hook: var Hook) =
  if hook.bounces.len < MaxHookBounces:
    hook.bounces.add hook.position

proc reboundCenter(tileX, tileZ: int): WorldPoint =
  ## Cylinder axis of one solid: the fountain is one rock, everything
  ## else (tree, rim tile, palisade) uses that tile's center.
  if islandTile(tileX, tileZ):
    return worldAtTile(IslandCenterX, IslandCenterZ)
  worldAtTile(
    clamp(tileX, 0, GridTiles - 1),
    clamp(tileZ, 0, GridTiles - 1)
  )

proc bounceUsesCurve(tileX, tileZ: int): bool =
  ## Trees and the fountain are cylinders. Rim rock and palisades stay
  ## flat faces so a wall shot is still incidence-in, incidence-out.
  islandTile(tileX, tileZ) or fieldTreeTile(tileX, tileZ)

proc reboundHeading(hook: var Hook, tileX, tileZ: int) =
  ## Reflects the throw off a curved surface: angle in equals angle out
  ## about the normal from the solid's center to the contact. Off-center
  ## hits pick up a glancing component, so bank shots curve instead of
  ## flipping one axis. A heading already leaving the solid is left
  ## alone so an inside-tile nudge can walk out.
  let center = reboundCenter(tileX, tileZ)
  let
    nx = int64(hook.position.x) - int64(center.x)
    nz = int64(hook.position.z) - int64(center.z)
    n2 = nx * nx + nz * nz
  if n2 == 0:
    hook.heading.x = -hook.heading.x
    hook.heading.z = -hook.heading.z
    return
  let
    hx = int64(hook.heading.x)
    hz = int64(hook.heading.z)
    dot = hx * nx + hz * nz
  if dot >= 0:
    return
  let
    rx = hx - 2 * roundDivision(dot * nx, n2)
    rz = hz - 2 * roundDivision(dot * nz, n2)
  if rx == 0 and rz == 0:
    hook.heading.x = -hook.heading.x
    hook.heading.z = -hook.heading.z
    return
  hook.heading.x =
    if rx > int64(high(int32)): high(int32)
    elif rx < int64(low(int32)): low(int32)
    else: int32(rx)
  hook.heading.z =
    if rz > int64(high(int32)): high(int32)
    elif rz < int64(low(int32)): low(int32)
    else: int32(rz)

proc consumeBudget(left: var int32, amount: int32) =
  if amount >= left:
    left = 0
  elif amount > 0:
    left = left - amount

proc stepHookAlong(hook: var Hook, delta: WorldPoint, dist, absD: int64) =
  ## Steps the head `dist/absD` along `delta`. Axes are copied first:
  ## `hook.position = WorldPoint(x: hook.position.x + …, z: hook.position.z
  ## + …)` constructs in-place into the assignment target, zeros the
  ## object, then the z term reads 0. A rim bounce then teleports across
  ## the map and clash math overflows int64.
  let
    ox = hook.position.x
    oz = hook.position.z
  hook.position.x = ox + int32(roundDivision(int64(delta.x) * dist, absD))
  hook.position.z = oz + int32(roundDivision(int64(delta.z) * dist, absD))

proc flyHook(hook: var Hook, budget: int32): int32 =
  ## Moves a flying head, reflecting off solid faces and the map edge.
  ## Bounces use a curved (cylindrical) heading so off-center hits
  ## glance instead of axis-flipping. `budget` is leftover range for
  ## this tick. A bounce never resets it.
  var left = budget
  var steps = 0
  while left > 0 and steps < MaxHookFlySteps:
    inc steps
    let tile = tileOf(hook.position)
    if hookHitsSolid(hook, tile.x, tile.z):
      if reboundOnRim(tile.x, tile.z):
        # Already inside the rim (or off the board). Reflecting the
        # travel axis walks a grazing heading further into the void.
        # Step toward the field and let the face-collision path bounce
        # once the head is on open ground again.
        clampHookToMap(hook.position)
        let
          interior = worldAtTile(GridTiles div 2, GridTiles div 2)
          stepDist = min(left, max(1'i32, WorldScale div 8))
          step = scaledPlanar(interior - hook.position, stepDist)
        if step.x == 0 and step.z == 0:
          break
        hook.position = hook.position + step
        clampHookToMap(hook.position)
        consumeBudget(left, stepDist)
        continue
      if islandTile(tile.x, tile.z):
        # One ricochet, then eject radially. A tangent heading would
        # otherwise slide around the pixelated rock disk and pin the
        # chain to the fountain until range runs out.
        hook.reboundHeading(tile.x, tile.z)
        if hook.heading.x == 0 and hook.heading.z == 0:
          break
        hook.recordBounce()
        let
          center = worldAtTile(IslandCenterX, IslandCenterZ)
          outDir = hook.position - center
          stepDist = min(left, max(1'i32, WorldScale div 4))
        var step = scaledPlanar(outDir, stepDist)
        if step.x == 0 and step.z == 0:
          step = scaledPlanar(
            WorldPoint(x: hook.heading.x, z: hook.heading.z),
            stepDist
          )
        if step.x == 0 and step.z == 0:
          break
        hook.position = hook.position + step
        clampHookToMap(hook.position)
        consumeBudget(left, stepDist)
        continue
      if bounceUsesCurve(tile.x, tile.z):
        hook.reboundHeading(tile.x, tile.z)
        if hook.heading.x == 0 and hook.heading.z == 0:
          break
      else:
        let
          ax = abs(hook.heading.x)
          az = abs(hook.heading.z)
        if ax >= az and hook.heading.x != 0:
          hook.heading.x = -hook.heading.x
        elif hook.heading.z != 0:
          hook.heading.z = -hook.heading.z
        elif hook.heading.x != 0:
          hook.heading.x = -hook.heading.x
        else:
          break
      hook.recordBounce()
      if activeHookWorld != nil:
        activeHookWorld.chipWallAt(tile.x, tile.z, hook.damage, hook.team)
      let nudgeDist = min(left, max(1'i32, WorldScale div 8))
      let nudge = scaledPlanar(
        WorldPoint(x: hook.heading.x, z: hook.heading.z),
        nudgeDist
      )
      if nudge.x == 0 and nudge.z == 0:
        break
      hook.position = hook.position + nudge
      clampHookToMap(hook.position)
      consumeBudget(left, nudgeDist)
      continue
    let delta = scaledPlanar(
      WorldPoint(x: hook.heading.x, z: hook.heading.z),
      left
    )
    if delta.x == 0 and delta.z == 0:
      break
    let
      dest = hook.position + delta
      destTile = tileOf(dest)
    if destTile.x == tile.x and destTile.z == tile.z:
      hook.position = dest
      clampHookToMap(hook.position)
      left = 0
      break
    let
      signX =
        if destTile.x > tile.x: 1
        elif destTile.x < tile.x: -1
        else: 0
      signZ =
        if destTile.z > tile.z: 1
        elif destTile.z < tile.z: -1
        else: 0
    var
      distX = 0'i64
      distZ = 0'i64
    if signX > 0:
      distX = int64(tileWorldMin(tile.x + 1)) - int64(hook.position.x)
    elif signX < 0:
      distX = int64(hook.position.x) - int64(tileWorldMin(tile.x))
    if signZ > 0:
      distZ = int64(tileWorldMin(tile.z + 1)) - int64(hook.position.z)
    elif signZ < 0:
      distZ = int64(hook.position.z) - int64(tileWorldMin(tile.z))
    if distX < 0:
      distX = 0
    if distZ < 0:
      distZ = 0
    let
      absDx = abs(int64(delta.x))
      absDz = abs(int64(delta.z))
      solidX = signX != 0 and hookHitsSolid(hook, tile.x + signX, tile.z)
      solidZ = signZ != 0 and hookHitsSolid(hook, tile.x, tile.z + signZ)
      destSolid = hookHitsSolid(hook, destTile.x, destTile.z)
    var
      hitX = signX != 0
      hitZ = signZ != 0
    if hitX and hitZ:
      let
        cx = distX * absDz
        cz = distZ * absDx
      if cx < cz:
        hitZ = false
      elif cz < cx:
        hitX = false
    var
      reflectX = false
      reflectZ = false
    if hitX and hitZ:
      reflectX = solidX or destSolid
      reflectZ = solidZ or destSolid
    elif hitX:
      if solidX:
        reflectX = true
      elif destSolid:
        reflectZ = signZ != 0
        reflectX = not reflectZ
    else:
      if solidZ:
        reflectZ = true
      elif destSolid:
        reflectX = signX != 0
        reflectZ = not reflectX
    if not reflectX and not reflectZ:
      hook.position = dest
      clampHookToMap(hook.position)
      left = 0
      break
    var consumed = 0'i64
    if reflectX and (not reflectZ or distX <= distZ) and absDx > 0:
      hook.stepHookAlong(delta, distX, absDx)
      consumed = roundDivision(distX * int64(left), absDx)
      if signX > 0:
        hook.position.x = tileWorldMin(tile.x + 1) - 1
      elif signX < 0:
        hook.position.x = tileWorldMin(tile.x)
    if reflectZ and (not reflectX or distZ < distX) and absDz > 0:
      hook.stepHookAlong(delta, distZ, absDz)
      consumed = roundDivision(distZ * int64(left), absDz)
    if reflectZ:
      if signZ > 0:
        hook.position.z = tileWorldMin(tile.z + 1) - 1
      elif signZ < 0:
        hook.position.z = tileWorldMin(tile.z)
    clampHookToMap(hook.position)
    if consumed < 0:
      consumed = 0
    if consumed > int64(left):
      consumed = int64(left)
    if consumed >= int64(left):
      left = 0
      break
    var bounceX = destTile.x
    var bounceZ = destTile.z
    if destSolid:
      discard
    elif reflectX:
      bounceX = tile.x + signX
      bounceZ = tile.z
    elif reflectZ:
      bounceX = tile.x
      bounceZ = tile.z + signZ
    if bounceUsesCurve(bounceX, bounceZ):
      hook.reboundHeading(bounceX, bounceZ)
    else:
      if reflectX:
        hook.heading.x = -hook.heading.x
      if reflectZ:
        hook.heading.z = -hook.heading.z
    hook.recordBounce()
    if activeHookWorld != nil:
      if destSolid:
        activeHookWorld.chipWallAt(
          destTile.x, destTile.z, hook.damage, hook.team
        )
      elif reflectX:
        activeHookWorld.chipWallAt(
          tile.x + signX, tile.z, hook.damage, hook.team
        )
      elif reflectZ:
        activeHookWorld.chipWallAt(
          tile.x, tile.z + signZ, hook.damage, hook.team
        )
    if consumed == 0:
      consumeBudget(left, 1)
    else:
      consumeBudget(left, int32(consumed))
  left

proc latchHook(world: World, hook: var Hook): bool =
  ## First living unit whose body overlaps the shuriken disk along this
  ## tick's travel, outbound or return. The caster is never a target.
  let
    sweep0 = hook.prior
    sweep1 = hook.position
    reach = hookLatchRadius(hook)
    ax = int64(sweep1.x) - int64(sweep0.x)
    az = int64(sweep1.z) - int64(sweep0.z)
    denom = ax * ax + az * az
  var
    best = -1
    bestTNum = 0'i64
    bestDist = high(int64)
  for i, pudge in world.pudges:
    if pudge.id == hook.ownerId or pudge.state == Dying:
      continue
    if pudge.shieldTicks > 0:
      # Spawn protection: the head flies straight through.
      continue
    if not segmentPointWithin(sweep0, sweep1, pudge.position, reach):
      continue
    var tNum = 0'i64
    if denom > 0:
      let
        px = int64(pudge.position.x) - int64(sweep0.x)
        pz = int64(pudge.position.z) - int64(sweep0.z)
      tNum = px * ax + pz * az
      if tNum < 0:
        tNum = 0
      elif tNum > denom:
        tNum = denom
    let dist = distanceSquared(sweep1, pudge.position)
    if best < 0 or tNum < bestTNum or (tNum == bestTNum and dist < bestDist):
      best = i
      bestTNum = tNum
      bestDist = dist
  if best < 0:
    return false
  let victim = world.pudges[best]
  if victim.hookedBy != 0 and victim.hookedBy != hook.ownerId:
    if victim.team != hook.team and
        not world.pudges[best].hasCheat(CheatFlagGod):
      let killer = world.pudgeIndex(hook.ownerId)
      if killer >= 0:
        world.pudges[killer].justHeadshot = true
        inc world.pudges[killer].headshotCount
        inc world.pudges[killer].hooksLanded
      inc world.headshots
      world.killPudge(best, hook.ownerId)
      hook.phase = HookIdle
      inc world.hookHits
      return true
    world.releaseHookedVictim(victim.id, hook.id)
  hook.victimId = victim.id
  hook.phase = HookReeling
  # Blade contact can happen while the hub is still short of the body.
  # Stick the head on the victim so reel starts from the hit, not an
  # instant dump at the caster.
  hook.position = world.pudges[best].position
  world.pudges[best].hookedBy = hook.ownerId
  world.pudges[best].hasMoveTarget = false
  world.pudges[best].velX = 0
  world.pudges[best].velZ = 0
  world.pudges[best].setAnim(idleClip)
  world.pudges[best].justGrabbed = true
  inc world.hookHits
  let owner = world.pudgeIndex(hook.ownerId)
  if owner >= 0:
    inc world.pudges[owner].hooksLanded
  if victim.team != hook.team:
    var hit = hook.damage
    if owner >= 0:
      hit = longshotDamage(
        hook.damage,
        world.pudges[owner].itemRank[ShopLongshot],
        hook.traveled
      )
    world.dealPudgeDamage(best, hit, hook.ownerId)
    if world.pudges[best].state == Dying:
      hook.victimId = 0
      hook.phase = HookIdle
  else:
    # A landed ally hook is a field medic's throw: same aim skill as
    # the kill shot, spent on patching your friend up.
    world.pudges[best].hp = min(
      world.pudges[best].hp + AllyHookHeal,
      world.pudges[best].maxHp
    )
  true

proc dropVictim(world: World, hook: var Hook) =
  if hook.victimId == 0:
    return
  let victim = world.pudgeIndex(hook.victimId)
  if victim >= 0:
    world.pudges[victim].hookedBy = 0
    world.settlePudge(victim, true)
  hook.victimId = 0

proc announceClash(
    world: World,
    chunkerId,
    victimId,
    ownerId: int32,
    point: WorldPoint
) =
  ## Records a hook-end deny. No HP is lost; the IDs feed the HUD toast.
  world.clashTick = world.tick
  world.clashPoint = point
  world.chunkTick = world.tick
  world.chunkerId = chunkerId
  world.chunkVictimId = victimId
  world.chunkOwnerId = ownerId
  inc world.hookDenies

proc interceptHooks(world: World, interceptor, other: int) =
  ## Two shuriken disks met: both chains break, nobody takes clash damage.
  let
    chunker = world.hooks[interceptor]
    intercepted = world.hooks[other]
    victimId =
      if intercepted.victimId != 0: intercepted.victimId
      else: intercepted.ownerId
    point = WorldPoint(
      x: (chunker.position.x + intercepted.position.x) div 2,
      z: (chunker.position.z + intercepted.position.z) div 2
    )
  world.announceClash(chunker.ownerId, victimId, intercepted.ownerId, point)
  world.dropVictim(world.hooks[other])
  world.dropVictim(world.hooks[interceptor])
  world.hooks[interceptor].phase = HookIdle
  world.hooks[other].phase = HookIdle
  world.hooks[interceptor].victimId = 0
  world.hooks[other].victimId = 0
  let chunkerIndex = world.pudgeIndex(chunker.ownerId)
  if chunkerIndex >= 0:
    inc world.pudges[chunkerIndex].denyCount
    world.pudges[chunkerIndex].gold =
      world.pudges[chunkerIndex].gold + GoldPerDeny

proc interceptOneSided(world: World, winner, loser: int) =
  ## The mighty hook plows through: only the lesser chain breaks, the
  ## winner keeps flying (or reeling) as if nothing happened.
  let
    broken = world.hooks[loser]
    victimId =
      if broken.victimId != 0: broken.victimId
      else: broken.ownerId
  world.announceClash(
    world.hooks[winner].ownerId, victimId, broken.ownerId,
    broken.position
  )
  world.dropVictim(world.hooks[loser])
  world.hooks[loser].phase = HookIdle
  world.hooks[loser].victimId = 0
  let winnerIndex = world.pudgeIndex(world.hooks[winner].ownerId)
  if winnerIndex >= 0:
    inc world.pudges[winnerIndex].denyCount
    world.pudges[winnerIndex].gold =
      world.pudges[winnerIndex].gold + GoldPerDeny

proc clashHooks(world: World) =
  var used = newSeq[bool](world.hooks.len)
  for i in 0 ..< world.hooks.len:
    if used[i] or world.hooks[i].phase != HookFlying:
      continue
    for j in 0 ..< world.hooks.len:
      if i == j or used[j]:
        continue
      if world.hooks[j].phase == HookIdle:
        continue
      if world.hooks[i].team == world.hooks[j].team:
        continue
      if not segmentsWithin(
          hookSweepStart(world.hooks[i]),
          world.hooks[i].position,
          hookSweepStart(world.hooks[j]),
          world.hooks[j].position,
          hookClashRadius(world.hooks[i], world.hooks[j])
        ):
        continue
      if world.hooks[i].mighty != world.hooks[j].mighty:
        # Big Hook dominance: the buffed chain wins the exchange.
        let winner = if world.hooks[i].mighty: i else: j
        let loser = if winner == i: j else: i
        world.interceptOneSided(winner, loser)
        used[loser] = true
        break
      let interceptor =
        if world.hooks[j].phase == HookReeling or
            world.hooks[i].traveled <= world.hooks[j].traveled:
          i
        else:
          j
      let other = if interceptor == i: j else: i
      world.interceptHooks(interceptor, other)
      used[i] = true
      used[j] = true
      break

proc finishReel(world: World, hook: var Hook, owner: int): bool =
  let
    dest = landingPoint(world.pudges[owner], hook)
    step = reelSpeed(hook)
  if not within(hook.position, dest, step + WorldScale div 4):
    return false
  hook.position = dest
  if hook.victimId != 0:
    let victim = world.pudgeIndex(hook.victimId)
    if victim >= 0:
      world.pudges[victim].position = dest
      world.pudges[victim].hookedBy = 0
      world.settlePudge(victim, true)
  true

proc moveHookToward(hook: var Hook, dest: WorldPoint, budget: int32): int32 =
  ## Pulls the head toward `dest`. Returns unused budget.
  if budget <= 0:
    return 0
  let span = integerSqrt(distanceSquared(hook.position, dest))
  if span <= 0:
    return budget
  if span <= int64(budget):
    hook.position = dest
    return budget - int32(span)
  hook.position = hook.position + scaledPlanar(dest - hook.position, budget)
  0

proc rideVictim(world: World, hook: Hook) =
  if hook.victimId == 0:
    return
  let victim = world.pudgeIndex(hook.victimId)
  if victim < 0 or world.pudges[victim].state != Alive:
    return
  let pull = hook.position - hook.prior
  world.pudges[victim].position = hook.position
  if pull.x != 0 or pull.z != 0:
    world.pudges[victim].facing = heading(pull.x, pull.z)
  world.settlePudge(victim, false)

proc advanceReel(world: World, hook: var Hook, owner: int): bool =
  ## Retraces the chain: head → last bounce → … → first bounce → dump.
  ## Returns true when the hook is finished and should be discarded.
  var left = reelSpeed(hook)
  var steps = 0
  while left > 0 and steps < MaxHookFlySteps:
    inc steps
    if hook.bounces.len > 0:
      let dest = hook.bounces[^1]
      if within(hook.position, dest, left + WorldScale div 4):
        let span = integerSqrt(distanceSquared(hook.position, dest))
        hook.position = dest
        hook.bounces.setLen(hook.bounces.len - 1)
        if span >= int64(left):
          left = 0
        elif span > 0:
          left = left - int32(span)
        continue
      left = moveHookToward(hook, dest, left)
    else:
      if world.finishReel(hook, owner):
        return true
      let dest = landingPoint(world.pudges[owner], hook)
      left = moveHookToward(hook, dest, left)
  world.rideVictim(hook)
  false

proc sweepRunes(world: World, hook: Hook) =
  ## Scoops every rune the blade passed over this tick; the caster gets
  ## the buff. Pudges win ties by construction: a latch snaps the head
  ## onto the victim first, so this sweep never reaches beyond the body
  ## that stopped the chain, and the hook otherwise flies on.
  if world.runes.len == 0:
    return
  let owner = world.pudgeIndex(hook.ownerId)
  if owner < 0 or world.pudges[owner].state == Dying:
    return
  let reach = hook.radius + RuneRadius
  var keep: seq[Rune]
  for rune in world.runes:
    if segmentPointWithin(hook.prior, hook.position, rune.position, reach):
      world.grantRune(owner, rune.kind)
    else:
      keep.add rune
  world.runes = keep

proc flyGrapple(hook: var Hook, budget: int32): int32 =
  ## Moves a flying grapple head. Unlike the hook it does not bounce:
  ## the first solid face latches it. The fountain is air: a latch there
  ## would yank the caster onto unstandable rocks.
  var left = budget
  var steps = 0
  while left > 0 and steps < MaxHookFlySteps:
    inc steps
    let tile = tileOf(hook.position)
    if hookHitsSolid(hook, tile.x, tile.z):
      clampHookToMap(hook.position)
      hook.grappleLatched = true
      return left
    let stepDist = min(left, WorldScale div 2)
    let delta = scaledPlanar(
      WorldPoint(x: hook.heading.x, z: hook.heading.z), stepDist
    )
    if delta.x == 0 and delta.z == 0:
      break
    hook.position = hook.position + delta
    clampHookToMap(hook.position)
    consumeBudget(left, stepDist)
    let landed = tileOf(hook.position)
    if hookHitsSolid(hook, landed.x, landed.z):
      hook.grappleLatched = true
      return left
  left

proc yankOwner(world: World, hook: var Hook, owner: int): bool =
  ## Pulls the caster along the chain toward the latched head. Returns
  ## true when the ride is over. The pull crosses anything, river
  ## included; the landing settles like a hook drag drop.
  template pudge: untyped = world.pudges[owner]
  let arrive = PudgeCollisionRadius + WorldScale div 2
  if within(pudge.position, hook.position, arrive):
    world.settlePudge(owner, true)
    return true
  let pull = reelSpeed(hook)
  let offset = hook.position - pudge.position
  let step = scaledPlanar(offset, min(pull, int32(min(
    integerSqrt(distanceSquared(pudge.position, hook.position)),
    int64(high(int32))
  ))))
  pudge.position = pudge.position + step
  pudge.velX = 0
  pudge.velZ = 0
  pudge.hasMoveTarget = false
  pudge.facing = heading(offset.x, offset.z)
  pudge.bindPudgeBody()
  false

proc stepHooks(world: World) =
  activeHookWorld = world
  var keep: seq[Hook]
  for hook in world.hooks.mitems:
    if hook.phase == HookIdle:
      continue
    let owner = world.pudgeIndex(hook.ownerId)
    if owner < 0 or world.pudges[owner].state == Dying:
      world.dropVictim(hook)
      continue
    if hook.phase == HookFlying:
      hook.prior = hook.position
      let remaining =
        if hook.traveled >= hook.range: 0'i32
        else: hook.range - hook.traveled
      if remaining <= 0:
        hook.phase = HookReeling
      else:
        climbHookSpeed(hook)
        let budget = min(hook.speed, remaining)
        if hook.isGrapple:
          let unused = flyGrapple(hook, budget)
          hook.traveled = hook.traveled + (budget - unused)
          world.sweepRunes(hook)
          if hook.grappleLatched or hook.traveled >= hook.range:
            hook.phase = HookReeling
        else:
          let unused = flyHook(hook, budget)
          hook.traveled = hook.traveled + (budget - unused)
          if world.sweepMines(hook):
            world.sweepRunes(hook)
            if hook.phase != HookIdle:
              keep.add hook
            continue
          if latchHook(world, hook):
            world.sweepRunes(hook)
            if hook.phase != HookIdle:
              keep.add hook
            continue
          world.sweepRunes(hook)
          if hook.traveled >= hook.range:
            hook.phase = HookReeling
    keep.add hook
  world.hooks = keep
  world.clashHooks()
  keep.setLen(0)
  for hook in world.hooks.mitems:
    if hook.phase == HookIdle:
      continue
    let owner = world.pudgeIndex(hook.ownerId)
    if owner < 0 or world.pudges[owner].state == Dying:
      world.dropVictim(hook)
      continue
    if hook.phase == HookReeling:
      hook.prior = hook.position
      if hook.isGrapple and hook.grappleLatched:
        # The latched grapple reels the CASTER, not the head.
        if world.yankOwner(hook, owner):
          continue
        keep.add hook
        continue
      let empty = hook.victimId == 0
      if world.advanceReel(hook, owner):
        if empty:
          world.sweepRunes(hook)
          if not hook.isGrapple:
            inc world.hookMisses
        continue
      if hook.victimId == 0 and not hook.isGrapple:
        if world.sweepMines(hook):
          world.sweepRunes(hook)
          if hook.phase == HookIdle:
            continue
          keep.add hook
          continue
        let latched = latchHook(world, hook)
        world.sweepRunes(hook)
        if latched and hook.phase == HookIdle:
          continue
    keep.add hook
  world.hooks = keep

proc stepDeaths(world: World) =
  for pudge in world.pudges.mitems:
    if pudge.hasCheat(CheatFlagMana):
      pudge.clearCooldowns()
    else:
      if pudge.hookCooldown > 0:
        dec pudge.hookCooldown
      if pudge.grappleCooldown > 0:
        dec pudge.grappleCooldown
      if pudge.blinkCooldown > 0:
        dec pudge.blinkCooldown
      if pudge.wallCooldown > 0:
        dec pudge.wallCooldown
      if pudge.mineCooldown > 0:
        dec pudge.mineCooldown
    if pudge.shieldTicks > 0:
      dec pudge.shieldTicks
    if pudge.buffTicks > 0:
      dec pudge.buffTicks
    inc pudge.animTicks
    if pudge.state == Alive and
        pudge.animClip == attackClip and
        pudge.swingTicks <= 0 and
        pudge.hookedBy == 0 and
        pudge.animTicks >= pudge.attackPeriod:
      pudge.setAnim(idleClip)
    if pudge.state != Dying:
      continue
    if pudge.deathTicks > 0:
      dec pudge.deathTicks
    if pudge.deathTicks <= 0:
      pudge.respawnPudge()

proc checkWinner(world: World) =
  if world.gameOver:
    return
  if world.teamKills[WestTeam.ord] >= world.killGoal:
    world.gameOver = true
    world.winner = WestTeam
  elif world.teamKills[EastTeam.ord] >= world.killGoal:
    world.gameOver = true
    world.winner = EastTeam

proc addHashy(hash: var uint32, value: WorldPoint) =
  hash.addHashy(value.x)
  hash.addHashy(value.y)
  hash.addHashy(value.z)

proc addHashy(hash: var uint32, value: Heading) =
  hash.addHashy(value.x)
  hash.addHashy(value.z)

proc stateHash*(game: Game): uint64 {.measure.} =
  let world = game.world
  var hash = HashySeed
  hash.addHashy(game.map.hash)
  hash.addHashy(world.tick)
  # maximumTicks stays out of the hash: it is static config the sim
  # never reads (the runner enforces the time limit), and recordings
  # truncate it to the played length on save, so a live match and its
  # replay legitimately disagree while every evolving bit matches.
  hash.addHashy(world.killGoal)
  hash.addHashy(world.gameOver)
  hash.addHashy(world.winner.ord)
  hash.addHashy(world.rng)
  hash.addHashy(world.spawnLayout)
  hash.addHashy(world.nextHookId)
  hash.addHashy(world.heroTurnTicks)
  hash.addHashy(world.heroTurnStart)
  for value in world.teamKills:
    hash.addHashy(value)
  hash.addHashy(world.hookHits)
  hash.addHashy(world.hookMisses)
  hash.addHashy(world.headshots)
  hash.addHashy(world.riverDumps)
  hash.addHashy(world.hookDenies)
  hash.addHashy(world.chunkTick)
  hash.addHashy(world.chunkerId)
  hash.addHashy(world.chunkVictimId)
  hash.addHashy(world.chunkOwnerId)
  hash.addHashy(world.pings.len)
  for ping in world.pings:
    hash.addHashy(ping.team.ord)
    hash.addHashy(ping.byId)
    hash.addHashy(ping.x)
    hash.addHashy(ping.y)
    hash.addHashy(ping.tick)
  hash.addHashy(world.nextRuneId)
  hash.addHashy(world.runePeriod)
  hash.addHashy(world.runeClock)
  hash.addHashy(world.runes.len)
  for rune in world.runes:
    hash.addHashy(rune.id)
    hash.addHashy(rune.kind.ord)
    hash.addHashy(rune.position)
    hash.addHashy(rune.dir)
    hash.addHashy(rune.spawnTick)
  hash.addHashy(world.nextPropId)
  hash.addHashy(world.props.len)
  for prop in world.props:
    hash.addHashy(prop.id)
    hash.addHashy(prop.kind.ord)
    hash.addHashy(prop.ownerId)
    hash.addHashy(prop.team.ord)
    hash.addHashy(prop.tileX)
    hash.addHashy(prop.tileZ)
    hash.addHashy(prop.hp)
    hash.addHashy(prop.maxHp)
    hash.addHashy(prop.ticksLeft)
    hash.addHashy(prop.alive)
  hash.addHashy(world.pudges.len)
  for pudge in world.pudges:
    hash.addHashy(pudge.id)
    hash.addHashy(pudge.team.ord)
    hash.addHashy(pudge.slot)
    hash.addHashy(pudge.lobbySeat)
    hash.addHashy(pudge.layer)
    hash.addHashy(pudge.position)
    hash.addHashy(pudge.facing)
    hash.addHashy(pudge.body)
    hash.addHashy(pudge.hp)
    hash.addHashy(pudge.maxHp)
    hash.addHashy(pudge.state.ord)
    hash.addHashy(pudge.kills)
    hash.addHashy(pudge.deaths)
    hash.addHashy(pudge.points)
    hash.addHashy(pudge.gold)
    hash.addHashy(pudge.spent)
    for item in ShopBoots..ShopMine:
      hash.addHashy(pudge.itemRank[item])
    for kind in UpgradeKind:
      hash.addHashy(pudge.upgrades[kind])
    hash.addHashy(pudge.hookCooldown)
    hash.addHashy(pudge.grappleCooldown)
    hash.addHashy(pudge.blinkCooldown)
    hash.addHashy(pudge.justBlinked)
    hash.addHashy(pudge.rotOn)
    hash.addHashy(pudge.rotTicks)
    hash.addHashy(pudge.wallCooldown)
    hash.addHashy(pudge.mineCooldown)
    hash.addHashy(pudge.windupGrapple)
    hash.addHashy(pudge.windupTicks)
    hash.addHashy(pudge.windupAimX)
    hash.addHashy(pudge.windupAimY)
    hash.addHashy(pudge.shieldTicks)
    hash.addHashy(pudge.hooksThrown)
    hash.addHashy(pudge.hooksLanded)
    hash.addHashy(pudge.headshotCount)
    hash.addHashy(pudge.denyCount)
    hash.addHashy(pudge.attackTargetId)
    hash.addHashy(pudge.swingTicks)
    hash.addHashy(pudge.animClip)
    hash.addHashy(pudge.animTicks)
    hash.addHashy(pudge.deathTicks)
    hash.addHashy(pudge.drownTicks)
    hash.addHashy(pudge.lastHurtBy)
    hash.addHashy(pudge.hasMoveTarget)
    hash.addHashy(pudge.moveX)
    hash.addHashy(pudge.moveZ)
    hash.addHashy(pudge.velX)
    hash.addHashy(pudge.velZ)
    hash.addHashy(pudge.hookedBy)
    hash.addHashy(pudge.buffKind.ord)
    hash.addHashy(pudge.buffTicks)
    hash.addHashy(pudge.runesTaken)
  var anyCheat = false
  for pudge in world.pudges:
    if pudge.cheatFlags != 0:
      anyCheat = true
      break
  if anyCheat:
    for pudge in world.pudges:
      hash.addHashy(pudge.cheatFlags)
  var anyStreak = false
  for pudge in world.pudges:
    if pudge.streak != 0:
      anyStreak = true
      break
  if anyStreak:
    for pudge in world.pudges:
      hash.addHashy(pudge.streak)
  hash.addHashy(world.hooks.len)
  for hook in world.hooks:
    hash.addHashy(hook.id)
    hash.addHashy(hook.ownerId)
    hash.addHashy(hook.team.ord)
    hash.addHashy(hook.phase.ord)
    hash.addHashy(hook.position)
    hash.addHashy(hook.prior)
    hash.addHashy(hook.heading)
    hash.addHashy(hook.traveled)
    hash.addHashy(hook.range)
    hash.addHashy(hook.speed)
    hash.addHashy(hook.peakSpeed)
    hash.addHashy(hook.victimId)
    hash.addHashy(hook.bounces.len)
    hash.addHashy(hook.isGrapple)
    hash.addHashy(hook.grappleLatched)
    hash.addHashy(hook.mighty)
    for bounce in hook.bounces:
      hash.addHashy(bounce)
  uint64(hash)

proc checkReplayHash(game: Game, hash: uint64) =
  if not game.historyPlayback or game.world.tick <= 0:
    return
  if game.replayVersionSkew:
    return
  let hashes =
    if game.recorder != nil: game.recorder.data.hashes
    else: game.replayPlayer.data.hashes
  hashes.checkReplayHash(uint32(game.world.tick), hash, game.hashCheck)

proc tickWorld*(game: Game, onHeroTurn: proc() {.closure.}) {.measure.} =
  let world = game.world
  if world.gameOver:
    return
  if game.replayMode and
      uint32(world.tick) >= game.replayData.header.setup.maximumTicks:
    return
  world.tick = world.tick +% 1
  for pudge in world.pudges.mitems:
    pudge.enteredRiver = false
    pudge.justHeadshot = false
    pudge.justGrabbed = false
    pudge.justChunked = false
    pudge.justRune = false
    pudge.justBlinked = false
    pudge.justStreak = 0
    pudge.justShutdown = 0
    pudge.justMulti = 0
    pudge.justFirstBlood = false
    pudge.justBounty = 0
  if game.historyPlayback:
    if game.recorder != nil:
      game.replayPlayer.data = game.recorder.data
    var action: ReplayAction
    while game.replayPlayer.takeActionAt(uint32(world.tick), action):
      applyReplayAction(world, action)
  profileBlock "heroTurn":
    dec world.heroTurnTicks
    if world.heroTurnTicks <= 0:
      world.heroTurnTicks += DecisionTicks
      if game.historyPlayback:
        if world.pudges.len > 0:
          world.heroTurnStart =
            (world.heroTurnStart + 1) mod world.pudges.len
      else:
        onHeroTurn()
  profileBlock "movement":
    world.stepMovement()
    world.resolveOverlaps()
  profileBlock "hooks":
    world.stepWindups()
    world.stepHooks()
    world.resolveOverlaps()
  profileBlock "world":
    world.stepRiver()
    world.stepRot()
    world.stepRunes()
    world.stepFountain()
    world.resolveOverlaps()
    world.stepMelee()
    world.resolveOverlaps()
    world.stepProps()
    world.stepDeaths()
    world.resolveOverlaps()
    world.checkWinner()
  profileBlock "hash":
    let hash = game.stateHash()
    if game.historyPlayback:
      game.checkReplayHash(hash)
    elif game.recorder != nil and game.recordingError.len == 0 and
        game.recorder.data.hashes.len < world.tick:
      try:
        game.recorder.recordHash(hash)
      except ReplayError as error:
        game.recordingError = error.msg

proc newWorld*(
    map: MapData,
    maximumTicks: int32,
    setup: seq[ReplayPudge],
    killGoal = KillGoal,
    runePeriod = RunePeriodTicks
): World =
  result = World(
    maximumTicks: maximumTicks,
    killGoal: max(killGoal, 1'i32),
    winner: WestTeam,
    nextHookId: FirstHookId,
    nextRuneId: FirstRuneId,
    nextPropId: FirstPropId,
    runePeriod: max(runePeriod, 0'i32),
    runeClock: max(runePeriod, 0'i32),
    rng: initRng(map.seed),
    spawnLayout: spawnLayoutFromSeed(
      map.seed,
      if map.teamSize > 0: map.teamSize else: TeamSize
    )
  )
  result.spawnPudges(setup)
  doAssert result.pudges.len == setup.len, "every pudge must spawn"
  doAssert result.pudges.len >= DuelPudgeCount and
    result.pudges.len <= MaxPudgeCount,
    "a match seats 2 to " & $MaxPudgeCount & " butchers"


proc newGame*(
    map: MapData,
    maximumTicks: int32,
    replayMode: bool,
    replayData: ReplayData,
    killGoal = KillGoal,
    runePeriod = RunePeriodTicks,
    duel = false,
    roster: seq[ReplayPudge] = @[]
): Game =
  let
    setup =
      if replayMode: replayData.header.setup.pudges
      elif roster.len > 0: roster
      else: livePudgeSetup(
        duel,
        if map.teamSize > 0: map.teamSize else: TeamSize
      )
    goal =
      if replayMode: replayData.header.setup.killGoal
      else: killGoal
    runes =
      if replayMode: replayData.header.setup.runePeriod
      else: runePeriod
  result = Game(
    world: newWorld(map, maximumTicks, setup, goal, runes),
    map: map,
    replayMode: replayMode,
    replayVersionSkew:
      replayMode and replayData.header.gameVersion != ReplayGameVersion,
    replayData: replayData,
    maximumTicks: maximumTicks,
    botEvery: 1,
    botSpeech: newSeq[BotSpeech](setup.len)
  )
