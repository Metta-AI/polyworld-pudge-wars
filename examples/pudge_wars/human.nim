## Human seat for Pudge Wars: mouse picking, command input, and the
## acknowledgment state the HUD and world overlays draw.
##
## The client queues integer intents only; the sim drains them at the
## seat's hero turn through the same record->apply path the bots use
## (human_play.md), so a human match replays hash-exact.

import
  std/[math, times],
  chroma, vmath, windy,
  cheats, content, fog, game, keybinds, maps, netclient, netpredict, sim,
  polyworld/[gameuis, pathing, rtscameras, shapes]

const
  PickPixels = 52.0'f32
    ## Screen-space grab radius for inspect / general butcher picks.
  SmartEnemyHalfWidth = 96.0'f32
    ## Half-width of the RMB attack capsule around an enemy silhouette.
    ## Bulky models (arms, mallet) sit far from the tile center; this must
    ## cover the whole visible body, not just the spine.
  SoftEnemyTiles = 2.75'f32
    ## Ground-ray fallback: isometric body clicks hit the tile behind the
    ## feet, so the soft radius has to reach that offset.
  RayStep = 0.75'f32
  RayReach = 420.0'f32
  WalkPulseSeconds = 0.5
  AttackFlashSeconds = 0.4
  ErrorSeconds = 2.2
  CheatIdleSeconds = 2.5
  LetterKeys = [
    KeyA, KeyB, KeyC, KeyD, KeyE, KeyF, KeyG, KeyH, KeyI, KeyJ, KeyK, KeyL,
    KeyM, KeyN, KeyO, KeyP, KeyQ, KeyR, KeyS, KeyT, KeyU, KeyV, KeyW, KeyX,
    KeyY, KeyZ
  ]
  PingWorldSeconds = 2.0
  PickSpineHeights = [0.25'f32, 1.1'f32, 2.0'f32, 3.1'f32]
    ## Feet → head samples along the butcher's spine.
  PickRingRadius = 0.95'f32
    ## Lateral sample radius (render tiles) for outstretched arms/weapon.
  PickRingHeights = [1.2'f32, 2.3'f32]
  AckGreen = rgbx(96, 220, 110, 210)
  AttackRed = rgbx(236, 92, 70, 220)
  AimGold = rgbx(240, 218, 128, 200)
  RingGold = rgbx(240, 218, 128, 110)
  SpectateGold = rgbx(240, 218, 128, 230)
  PingGold = rgbx(255, 214, 90, 220)
  TelegraphWest = rgbx(220, 72, 64, 150)
  TelegraphEast = rgbx(72, 148, 230, 150)
  AllyInspect = rgbx(120, 200, 255, 200)
  EnemyInspect = rgbx(255, 120, 90, 200)

var
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingMove = false
  keyMoveLastDir = (0, 0)
  keyMoveLastTime = -1.0e9
  aimingAttack = false
  inspectId = 0'i32
  walkPulsePoint: Vec3
  walkPulseTime = -1.0e9
  attackFlashId = 0'i32
  worldViewRect*: GameUiPanel
    ## Pixel play area the 3D camera fills; empty means the full window.
  attackFlashTime = -1.0e9
  errorText = ""
  errorTime = -1.0e9
  inspectArmed = false
  inspectOrigin = vec2(0)
  rmbBlockedCommand = false
  fogOfWar* = true
    ## Team-shared fog: the enemy bank hides outside your side's
    ## combined sight. Toggled from the F3 debug panel or the
    ## `iseedeadpeople` cheat.
  spectatePudgeId* = 0'i32
    ## Replay / spectator POV butcher. 0 is omniscient. Live humans
    ## ignore this; their fog stays on the local hero's team.
  cheatBuffer = ""
  cheatTypedAt = -1.0e9

proc humanControlActive*(): bool =
  ## Returns whether this process's input drives a live seat. A host
  ## with remote players but no own seat spectates its own match.
  localSeat >= 0 and not run.replayMode

proc heroIndex*(): int =
  ## Roster index of the seat this process's input drives.
  if localSeat < 0 or localSeat >= run.world.pudges.len:
    return -1
  localSeat

proc fogTeam*(): int =
  ## The team whose vision gates the local display, or -1 for
  ## omniscient (no POV selected, fog disabled).
  if not fogOfWar:
    return -1
  if humanControlActive() and heroIndex() >= 0:
    return run.world.pudges[heroIndex()].team.ord
  if humanControlActive() or spectatePudgeId == 0:
    return -1
  fogTeamOf(run.world, spectatePudgeId)

proc fogCanSee*(position: WorldPoint): bool =
  ## Team-shared sight: the whole home bank and the river stay lit.
  ## The enemy bank needs a living teammate within `SightRadiusTiles`.
  ## Hooks do not scout — a chain in the dark stays dark.
  fogCanSeeTeam(run.world, fogTeam(), position)

proc fogShownPudge*(pudge: Pudge): bool =
  ## Own team always shows; enemies only inside the shared sight.
  fogShownPudgeTeam(run.world, fogTeam(), pudge)

proc spectateIndex*(): int =
  ## Roster index of the butcher whose eyes we occupy, or -1.
  if spectatePudgeId == 0:
    return -1
  pudgeIndex(run.world, spectatePudgeId)

proc lockSpectatorEyes*(pudgeId: int32) =
  ## Replay / idle spectator: inspect this butcher and render their
  ## team's fog. Live seats keep their own hero fog.
  if humanControlActive() or pudgeId == 0:
    return
  spectatePudgeId = pudgeId
  inspectId = pudgeId

proc clearSpectatorEyes*() =
  ## Back to omniscient. No-op while a live seat drives the camera.
  if humanControlActive():
    return
  spectatePudgeId = 0
  inspectId = 0

proc inspectIndex*(): int =
  ## Roster index shown on the WC3 command card (defaults to the hero,
  ## then the first butcher so spectators still see a unit).
  if inspectId != 0:
    let index = pudgeIndex(run.world, inspectId)
    if index >= 0:
      return index
  result = heroIndex()
  if result < 0 and run.world.pudges.len > 0:
    result = 0

proc isOwnedInspect*(): bool =
  ## True when the command card shows the local hero seat.
  let idx = inspectIndex()
  idx >= 0 and idx == heroIndex()

proc commandCardVisible*(): bool =
  ## Whether the bottom hero cluster should render this frame. Idle
  ## spectators (and replays with nothing selected) keep a clean screen.
  humanControlActive() or inspectId != 0

proc syncInspectToHero() =
  ## Snaps inspection back to the owned butcher (or clears it).
  let index = heroIndex()
  if index >= 0:
    inspectId = run.world.pudges[index].id
  else:
    inspectId = 0

proc syncInspectFog() =
  ## Drop a selection that walked into the dark so the card and ring
  ## cannot name a butcher you cannot see.
  if inspectId == 0:
    return
  let index = pudgeIndex(run.world, inspectId)
  if index < 0 or not fogShownPudge(run.world.pudges[index]):
    syncInspectToHero()

proc aimingHookNow*(): bool =
  aimingHook

proc aimingBlinkNow*(): bool =
  aimingBlink

proc cancelAim*() =
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingMove = false
  aimingAttack = false

proc resetHumanTransients*() =
  ## Drops queued commands and pending feedback after a history seek.
  run.humanIntents.setLen(0)
  run.intentResults.setLen(0)
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingMove = false
  aimingAttack = false
  inspectId = 0
  inspectArmed = false
  rmbBlockedCommand = false
  if spectatePudgeId != 0 and not humanControlActive():
    inspectId = spectatePudgeId
  errorText.setLen(0)
  errorTime = -1.0e9
  walkPulseTime = -1.0e9
  attackFlashTime = -1.0e9
  cheatBuffer.setLen(0)
  cheatTypedAt = -1.0e9

proc setHumanError*(text: string, buzz = true) =
  errorText = text
  errorTime = epochTime()
  discard buzz

proc humanErrorLine*(): tuple[text: string, alpha: float32] =
  ## Returns the active reject line and its fade, or an empty string.
  let age = epochTime() - errorTime
  if errorText.len == 0 or age > ErrorSeconds:
    return ("", 0.0'f32)
  let fade = clamp(1.0 - age / ErrorSeconds, 0.0, 1.0)
  (errorText, float32(min(1.0, fade * 3.0)))

proc renderPoint(position: WorldPoint): Vec3 =
  vec3(
    position.x.float32 / WorldScale.float32,
    position.y.float32 / WorldScale.float32,
    position.z.float32 / WorldScale.float32
  )

proc groundLift(point: Vec3, extra: float32): Vec3 =
  result = point
  result.y = surfaceHeightNear(point.x, point.z, point.y) + extra

proc heroGroundPoint*(): Vec3 =
  ## Render-space position of the local hero, for camera centering. On a
  ## predicting WASM seat this is the predicted position, so the camera
  ## tracks your own movement with no round-trip lag.
  let index = heroIndex()
  if index < 0:
    return vec3(0)
  renderPoint(predictedPudge(index).position)

proc inspectGroundPoint*(): Vec3 =
  ## Render-space position of the butcher shown on the command card.
  let index = inspectIndex()
  if index < 0:
    return vec3(0)
  renderPoint(run.world.pudges[index].position)

proc followCameraPoint*(): tuple[found: bool, point: Vec3] =
  ## Lock-cam look-at: your butcher while seated, else the spectator
  ## POV or the inspected butcher.
  if humanControlActive() and heroIndex() >= 0:
    return (true, heroGroundPoint())
  let eyes = spectateIndex()
  if eyes >= 0:
    return (true, renderPoint(run.world.pudges[eyes].position))
  if inspectId != 0:
    let index = inspectIndex()
    if index >= 0:
      return (true, inspectGroundPoint())
  (false, vec3(0))

proc viewPanel(window: Window): GameUiPanel =
  if worldViewRect.size.x > 1 and worldViewRect.size.y > 1:
    worldViewRect
  else:
    GameUiPanel(
      origin: vec2(0),
      size: vec2(window.size.x.float32, window.size.y.float32)
    )

proc screenPosition(
    window: Window,
    viewProjection: Mat4,
    position: Vec3
): Vec2 =
  ## Projects a world position into window pixel coordinates.
  let clip = viewProjection * vec4(position.x, position.y, position.z, 1)
  screenFromClip(clip, viewPanel(window))

proc groundUnderMouse*(
    window: Window,
    viewProjection: Mat4
): tuple[found: bool, point: Vec3] =
  ## Casts the cursor ray onto the terrain surface: march until the ray
  ## dips under the height field, then bisect onto the crossing.
  let
    panel = viewPanel(window)
    size = window.size
  if size.x <= 0 or size.y <= 0 or panel.size.x <= 0 or panel.size.y <= 0:
    return
  let
    mouse = window.mousePos.vec2
    ndc = ndcFromScreen(mouse, panel)
    inv = inverse(viewProjection)
    near4 = inv * vec4(ndc.x, ndc.y, -1, 1)
    far4 = inv * vec4(ndc.x, ndc.y, 1, 1)
  if abs(near4.w) < 1e-9'f32 or abs(far4.w) < 1e-9'f32:
    return
  let
    origin = vec3(near4.x, near4.y, near4.z) / near4.w
    target = vec3(far4.x, far4.y, far4.z) / far4.w
  var direction = target - origin
  if length(direction) < 1e-6'f32:
    return
  direction = normalize(direction)

  proc above(t: float32): bool =
    let p = origin + direction * t
    p.y > surfaceHeightNear(p.x, p.z, p.y)

  if not above(0):
    return
  var
    low = 0.0'f32
    high = RayStep
    crossed = false
  while high < RayReach:
    if not above(high):
      crossed = true
      break
    low = high
    high += RayStep
  if not crossed:
    return
  for _ in 0 ..< 20:
    let mid = (low + high) * 0.5'f32
    if above(mid):
      low = mid
    else:
      high = mid
  let hit = origin + direction * ((low + high) * 0.5'f32)
  let half = float32(GridTiles div 2)
  (
    true,
    vec3(clamp(hit.x, -half, half - 0.001'f32), hit.y,
      clamp(hit.z, -half, half - 0.001'f32))
  )

proc tileOfGround*(point: Vec3): tuple[x, y: int32] =
  ## Map tile under one picked render-space ground point.
  (
    mapCoordinate(int32(point.x * WorldScale.float32)),
    mapCoordinate(int32(point.z * WorldScale.float32))
  )

proc fineOfGround*(point: Vec3): tuple[x, y: int32] =
  ## 1/256-tile aim coordinates under one picked ground point.
  (
    fineOfWorld(int32(point.x * WorldScale.float32)),
    fineOfWorld(int32(point.z * WorldScale.float32))
  )

proc distToSegment(point, a, b: Vec2): float32 =
  ## Pixel distance from `point` to the segment a→b.
  let
    ab = b - a
    len2 = ab.x * ab.x + ab.y * ab.y
  if len2 < 1e-6'f32:
    return length(point - a)
  let t = clamp(
    ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / len2,
    0.0'f32,
    1.0'f32
  )
  length(point - (a + ab * t))

proc sampleScreenDist(
    window: Window,
    viewProjection: Mat4,
    base: Vec3,
    mouse: Vec2
): float32 =
  ## Closest screen distance from the cursor to a butcher's silhouette:
  ## spine capsule plus a ring of arm/weapon samples.
  let
    feet = screenPosition(
      window, viewProjection, groundLift(base, PickSpineHeights[0])
    )
    head = screenPosition(
      window, viewProjection, groundLift(base, PickSpineHeights[^1])
    )
  result = distToSegment(mouse, feet, head)
  for height in PickSpineHeights:
    let distance = length(
      screenPosition(window, viewProjection, groundLift(base, height)) -
      mouse
    )
    if distance < result:
      result = distance
  const angles = [
    0.0'f32, PI / 4.0'f32, PI / 2.0'f32, 3.0'f32 * PI / 4.0'f32,
    PI, 5.0'f32 * PI / 4.0'f32, 3.0'f32 * PI / 2.0'f32, 7.0'f32 * PI / 4.0'f32
  ]
  for angle in angles:
    let offset = vec3(cos(angle) * PickRingRadius, 0, sin(angle) * PickRingRadius)
    for height in PickRingHeights:
      let distance = length(
        screenPosition(
          window, viewProjection, groundLift(base + offset, height)
        ) - mouse
      )
      if distance < result:
        result = distance

proc pickPudge*(
    window: Window,
    viewProjection: Mat4,
    includeDead = false,
    maxPixels = PickPixels
): int32 =
  ## Finds the nearest butcher under the pointer, or 0. Uses a spine
  ## capsule plus arm samples so clicks on the model land.
  var best = maxPixels
  let mouse = window.mousePos.vec2
  for pudge in run.world.pudges:
    if not includeDead and pudge.state == Dying:
      continue
    if not fogShownPudge(pudge):
      continue
    let distance = sampleScreenDist(
      window, viewProjection, renderPoint(pudge.position), mouse
    )
    if distance < best:
      best = distance
      result = pudge.id

proc pickEnemyPudge(
    window: Window,
    viewProjection: Mat4,
    heroTeam: Team,
    maxPixels = SmartEnemyHalfWidth
): int32 =
  ## Smart-command pick: nearest living enemy under the pointer. The
  ## grab half-width is wide enough for the full silhouette — not just
  ## the tile under the feet.
  var best = maxPixels
  let mouse = window.mousePos.vec2
  for pudge in run.world.pudges:
    if pudge.state == Dying or pudge.team == heroTeam:
      continue
    if not fogShownPudge(pudge):
      continue
    let distance = sampleScreenDist(
      window, viewProjection, renderPoint(pudge.position), mouse
    )
    if distance < best:
      best = distance
      result = pudge.id

proc enemyNearGround(heroTeam: Team, ground: Vec3): int32 =
  ## Soft world pick: an enemy whose footprint (or the isometric tile
  ## behind their upper body) covers the ground click.
  var best = SoftEnemyTiles
  for pudge in run.world.pudges:
    if pudge.state == Dying or pudge.team == heroTeam:
      continue
    if not fogShownPudge(pudge):
      continue
    let
      at = renderPoint(pudge.position)
      dx = at.x - ground.x
      dz = at.z - ground.z
      distance = sqrt(dx * dx + dz * dz)
    if distance < best:
      best = distance
      result = pudge.id

proc hudCooldown(name: string, ticks: int32): string =
  ## Formats remaining ticks as "NAME READY IN d.d s".
  let tenths = (int(max(ticks, 0)) * 10 + int(TickRate) - 1) div int(TickRate)
  name & " READY IN " & $(tenths div 10) & "." & $(tenths mod 10) & " s"

proc hookBlockReason(hero: Pudge): string =
  ## Same-frame denial text for a hook that cannot start right now.
  if hero.windupTicks > 0:
    return "ALREADY CASTING"
  for hook in run.world.hooks:
    if hook.ownerId == hero.id and hook.phase != HookIdle:
      return "HOOK IN FLIGHT"
  if hero.hookCooldown > 0:
    hudCooldown("HOOK", hero.hookCooldown)
  else:
    ""

proc grappleBlockReason(hero: Pudge): string =
  ## Same-frame denial text for a grapple that cannot start right now.
  if hero.windupTicks > 0:
    return "ALREADY CASTING"
  for hook in run.world.hooks:
    if hook.ownerId == hero.id and hook.phase != HookIdle:
      return "CHAIN IN FLIGHT"
  if hero.grappleCooldown > 0:
    hudCooldown("GRAPPLE", hero.grappleCooldown)
  else:
    ""

proc blinkBlockReason(hero: Pudge): string =
  ## Same-frame denial text for a blink that cannot start right now.
  if run.world.rotAffected(hero):
    return "ROTTING"
  if hero.windupTicks > 0:
    return "ALREADY CASTING"
  if hero.hookedBy != 0:
    return "HOOKED"
  if hero.blinkCooldown > 0:
    hudCooldown("BLINK", hero.blinkCooldown)
  else:
    ""

proc queueHero(kind: IntentKind, a = 0'i32, b = 0'i32) =
  ## Routes one command to the authority: the local queue when this
  ## process owns the sim, the host when following one over the wire.
  let index = heroIndex()
  if index < 0:
    return
  let intent = HumanIntent(slot: int32(index), kind: kind, a: a, b: b)
  if netRole == NetClient:
    if predictor.enabled:
      # Apply locally in the prediction world at the predicted tick and
      # stamp the same tick on the wire, so the host can flag a timing
      # miss and the follower reconciles this command off the tape.
      let wanted = uint32(run.world.tick) + uint32(predictor.lead)
      predictor.record(intent, wanted)
      netQueueIntent(intent, wanted)
    else:
      netQueueIntent(intent)
  else:
    queueIntent(run, intent)

proc handleCheatCodes(window: Window) =
  ## Accumulates letters the way Warcraft 3 did: type `greedisgood`
  ## anywhere and the purse fills. A pause longer than CheatIdleSeconds
  ## forgets a partial code.
  let now = epochTime()
  if now - cheatTypedAt > CheatIdleSeconds:
    cheatBuffer.setLen(0)
  for i, key in LetterKeys:
    if not window.buttonPressed[key]:
      continue
    cheatTypedAt = now
    cheatBuffer.add char(ord('a') + i)
    if cheatBuffer.len > CheatBufferCap:
      cheatBuffer = cheatBuffer[^CheatBufferCap .. ^1]
    let hit = matchCheatBuffer(cheatBuffer)
    if not hit.found:
      continue
    cheatBuffer.setLen(0)
    setHumanError("CHEAT ENABLED", buzz = false)
    if hit.reveal:
      fogOfWar = not fogOfWar
    else:
      let amount =
        if hit.kind in {CheatGreed, CheatGold}: CheatGoldAmount
        else: 0'i32
      queueHero(IntentCheat, int32(hit.kind.ord), amount)

proc toggleHookAutocast*() =
  ## Arms or disarms Meat Hook autocast. Client-only; the sim still
  ## only sees the hook intent that fires.
  options.autocast = not options.autocast

proc issueHookAtPudge(target: Pudge) =
  ## Fine-aim a hook at a butcher's current world position.
  queueHero(
    IntentHookFine,
    fineOfWorld(target.position.x),
    fineOfWorld(target.position.z)
  )

proc issueAttack(targetId: int32) =
  ## Queues a melee order and flashes the target ring.
  queueHero(IntentAttack, targetId)
  attackFlashId = targetId
  attackFlashTime = epochTime()

proc canIssueFromHud(): bool =
  if not humanControlActive():
    setHumanError("SPECTATING", buzz = false)
    return false
  if run.replayMode:
    setHumanError("SPECTATING THE PAST - RETURN TO LIVE TO PLAY")
    return false
  let index = heroIndex()
  if index < 0:
    return false
  if run.world.pudges[index].state == Dying:
    setHumanError("DEAD - RESPAWNING")
    return false
  true

proc beginMoveCommand*() =
  ## Next ground click walks, Warcraft 3 Move-button style.
  if not canIssueFromHud():
    return
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingAttack = false
  aimingMove = true

proc beginAttackCommand*() =
  ## Next butcher click issues a melee attack.
  if not canIssueFromHud():
    return
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingMove = false
  aimingAttack = true

proc beginHookCommand*() =
  ## Enters Meat Hook targeting, matching the Q button without quickcast.
  if not canIssueFromHud():
    return
  let hero = run.world.pudges[heroIndex()]
  let reason = hookBlockReason(hero)
  if reason.len > 0:
    setHumanError(reason)
    return
  aimingMove = false
  aimingAttack = false
  aimingGrapple = false
  aimingBlink = false
  aimingWall = false
  aimingMine = false
  aimingHook = true

proc beginBlinkCommand*() =
  ## Enters Blink targeting from the command card. F itself hops at
  ## the cursor; this path is for a click confirm.
  if not canIssueFromHud():
    return
  let hero = run.world.pudges[heroIndex()]
  let reason = blinkBlockReason(hero)
  if reason.len > 0:
    setHumanError(reason)
    return
  aimingMove = false
  aimingAttack = false
  aimingHook = false
  aimingGrapple = false
  aimingWall = false
  aimingMine = false
  aimingBlink = true

proc beginRotCommand*() =
  ## Toggles Rot on the owned butcher. No targeting.
  if not canIssueFromHud():
    return
  cancelAim()
  queueHero(IntentRot)

proc issueStopCommand*() =
  ## Stops the owned butcher. Hold Position uses the same intent.
  if not canIssueFromHud():
    return
  cancelAim()
  queueHero(IntentStop)

proc issueBuyCommand*(kind: UpgradeKind) =
  ## Buys one hook upgrade from the inventory grid.
  if not canIssueFromHud():
    return
  queueHero(IntentBuy, int32(kind.ord))

proc issueBuyPower*(item: ShopItem) =
  ## Buys one base-shop catalog row (powerup or permanent).
  if not canIssueFromHud():
    return
  queueHero(IntentBuyPower, int32(item.ord))

proc placeBlockReason(hero: Pudge, item: ShopItem): string =
  ## Same-frame denial text for a wall or mine drop.
  if hero.itemRank[item] <= 0:
    return "BUY IT AT YOUR SHOP PAD FIRST"
  if hero.inRiver:
    return "CANNOT PLACE IN THE RIVER"
  if hero.hookedBy != 0:
    return "HOOKED"
  if item == ShopWall and hero.wallCooldown > 0:
    return hudCooldown("WALL", hero.wallCooldown)
  if item == ShopMine and hero.mineCooldown > 0:
    return hudCooldown("MINE", hero.mineCooldown)
  ""

proc facingDropTile(hero: Pudge): (int32, int32) =
  ## Two tiles in front of the butcher, used for hotkey / quickcast drops.
  let
    here = tileOf(hero.position)
    mag = max(abs(hero.facing.x), abs(hero.facing.z))
  if mag == 0:
    return (int32(here.x), int32(here.z))
  (
    int32(here.x + int(int64(hero.facing.x) * 2 div mag)),
    int32(here.z + int(int64(hero.facing.z) * 2 div mag))
  )

proc beginPlaceCommand*(item: ShopItem) =
  ## Inventory or hotkey: next ground click drops a wall or mine.
  if not canIssueFromHud():
    return
  if item != ShopWall and item != ShopMine:
    return
  let hero = run.world.pudges[heroIndex()]
  let reason = placeBlockReason(hero, item)
  if reason.len > 0:
    setHumanError(reason)
    return
  aimingHook = false
  aimingGrapple = false
  aimingBlink = false
  aimingMove = false
  aimingAttack = false
  aimingWall = item == ShopWall
  aimingMine = item == ShopMine

proc castPlaceAtCursor(
    window: Window,
    viewProjection: Mat4,
    hero: Pudge,
    item: ShopItem
): bool =
  let reason = placeBlockReason(hero, item)
  if reason.len > 0:
    setHumanError(reason)
    return false
  let pick = groundUnderMouse(window, viewProjection)
  if not pick.found:
    return false
  let (tileX, tileY) = tileOfGround(pick.point)
  if item == ShopWall:
    queueHero(IntentPlaceWall, tileX, tileY)
  else:
    queueHero(IntentPlaceMine, tileX, tileY)
  true

proc castPlaceAhead(hero: Pudge, item: ShopItem): bool =
  let reason = placeBlockReason(hero, item)
  if reason.len > 0:
    setHumanError(reason)
    return false
  let (tx, tz) = facingDropTile(hero)
  if item == ShopWall:
    queueHero(IntentPlaceWall, tx, tz)
  else:
    queueHero(IntentPlaceMine, tx, tz)
  true

proc castHookAtCursor(
    window: Window,
    viewProjection: Mat4,
    hero: Pudge
): bool =
  ## Queues a fine-aim hook at the cursor; denies instantly when the
  ## ability cannot start so the tape never records a doomed cast.
  let reason = hookBlockReason(hero)
  if reason.len > 0:
    setHumanError(reason)
    return false
  let pick = groundUnderMouse(window, viewProjection)
  if not pick.found:
    return false
  let (fineX, fineY) = fineOfGround(pick.point)
  queueHero(IntentHookFine, fineX, fineY)
  true

proc castGrappleAtCursor(
    window: Window,
    viewProjection: Mat4,
    hero: Pudge
): bool =
  ## Queues a fine-aim grapple at the cursor.
  let reason = grappleBlockReason(hero)
  if reason.len > 0:
    setHumanError(reason)
    return false
  let pick = groundUnderMouse(window, viewProjection)
  if not pick.found:
    return false
  let (fineX, fineY) = fineOfGround(pick.point)
  queueHero(IntentGrappleFine, fineX, fineY)
  true

proc castBlinkAtCursor(
    window: Window,
    viewProjection: Mat4,
    hero: Pudge
): bool =
  ## Queues a fine-aim blink toward the cursor. Default F hop.
  let reason = blinkBlockReason(hero)
  if reason.len > 0:
    setHumanError(reason)
    return false
  let pick = groundUnderMouse(window, viewProjection)
  if not pick.found:
    setHumanError("NO BLINK TARGET")
    return false
  let (fineX, fineY) = fineOfGround(pick.point)
  queueHero(IntentBlinkFine, fineX, fineY)
  true

proc rejectReason(res: IntentResult): string =
  ## Explains one sim-side rejection using the current world state.
  let index = heroIndex()
  if index < 0:
    return "COMMAND REJECTED"
  let hero = run.world.pudges[index]
  case res.kind
  of IntentWalk:
    "CANNOT WALK THERE"
  of IntentHook, IntentHookFine:
    let reason = hookBlockReason(hero)
    if reason.len > 0: reason else: "CANNOT HOOK"
  of IntentGrapple, IntentGrappleFine:
    let reason = grappleBlockReason(hero)
    if reason.len > 0: reason else: "CANNOT GRAPPLE"
  of IntentBlink, IntentBlinkFine:
    let reason = blinkBlockReason(hero)
    if reason.len > 0: reason else: "CANNOT BLINK"
  of IntentAttack:
    "TARGET IS PROTECTED"
  of IntentBuy:
    if hero.points <= 0: "NO POINTS - LAND HOOKS AND KILLS"
    else: "UPGRADE MAXED"
  of IntentBuyPower:
    if not hero.inOwnShop: "STAND ON YOUR SHOP PAD"
    elif hero.gold <= 0: "NEED GOLD - KILLS AND DENIES PAY"
    else: "NOT ENOUGH GOLD, MAXED, OR INVENTORY FULL"
  of IntentStop, IntentPing:
    "COMMAND REJECTED"
  of IntentPlaceWall, IntentPlaceMine:
    if hero.itemRank[ShopWall] <= 0 and hero.itemRank[ShopMine] <= 0:
      "BUY IT AT YOUR SHOP PAD FIRST"
    elif hero.inRiver: "CANNOT PLACE IN THE RIVER"
    else: "CANNOT PLACE THERE"
  of IntentCheat:
    "CHEAT REJECTED"
  of IntentRot:
    if hero.state == Dying: "DEAD" else: "CANNOT ROT"

proc drainIntentResults() =
  ## Converts sim acknowledgments into HUD feedback.
  for res in run.intentResults:
    if int(res.slot) != heroIndex():
      continue
    if not res.accepted:
      setHumanError(rejectReason(res))
  run.intentResults.setLen(0)

proc anyCommandPressed(
    window: Window, rightClickCommand, panTap: bool
): bool =
  let wallPressed =
    if panSharesWall(): panTap
    else: window.buttonPressed[bindKey(BindWall)]
  rightClickCommand or
    window.buttonPressed[bindKey(BindHook)] or
    window.buttonPressed[bindKey(BindGrapple)] or
    window.buttonPressed[bindKey(BindBlink)] or
    window.buttonPressed[bindKey(BindRot)] or
    window.buttonPressed[bindKey(BindStop)] or
    window.buttonPressed[bindKey(BindUpgrade1)] or
    window.buttonPressed[bindKey(BindUpgrade2)] or
    window.buttonPressed[bindKey(BindUpgrade3)] or
    window.buttonPressed[bindKey(BindUpgrade4)] or
    wallPressed or
    window.buttonPressed[bindKey(BindMine)] or
    window.buttonPressed[bindKey(BindPing)]

proc handleSeatSwap(
    window: Window,
    viewProjection: Mat4,
    live: bool
) =
  ## T swaps who drives a seat mid-match: a seated human releases the
  ## butcher to its bot script (autopilot), a spectator grabs the
  ## butcher under the cursor. A spectator can also pick a seat by
  ## number (1-6). Every handoff is recorded as `ActionTakeOver`.
  if run.replayMode:
    return
  if netRole == NetClient:
    # Seats are the host's to hand out; the lobby page swaps them.
    if window.buttonPressed[bindKey(BindTakeOver)]:
      setHumanError("THE HOST LOBBY ASSIGNS SEATS", buzz = false)
    return
  let swapPressed = window.buttonPressed[bindKey(BindTakeOver)]
  if humanControlActive():
    if not swapPressed:
      return
    if not live:
      setHumanError("SPECTATING THE PAST - RETURN TO LIVE TO PLAY")
      return
    let index = heroIndex()
    if index < 0:
      return
    if applyTakeOver(run, index, false):
      localSeat = -1
      spectatePudgeId = 0
      aimingHook = false
      setHumanError(
        "AUTOPILOT ON - PRESS T OVER A BUTCHER TO RETAKE", buzz = false
      )
    else:
      setHumanError("NO BOT SCRIPT LOADED FOR THIS SEAT")
    return

  # Spectator: the slot picker. T grabs the hovered butcher (or the
  # launch seat); the number keys grab a seat directly.
  var slot = -1
  const SeatKeys = [
    Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, Key0
  ]
  for i, key in SeatKeys:
    if window.buttonPressed[key]:
      if i < run.world.pudges.len:
        slot = i
  if swapPressed:
    let picked = pickPudge(window, viewProjection)
    if picked != 0:
      slot = pudgeIndex(run.world, picked)
    elif options.humanSlots.len > 0:
      slot = int(options.humanSlots[0])
    else:
      setHumanError("HOVER A BUTCHER AND PRESS T TO TAKE OVER")
  if slot < 0:
    return
  if not live:
    setHumanError("SPECTATING THE PAST - RETURN TO LIVE TO PLAY")
    return
  if applyTakeOver(run, slot, true):
    localSeat = slot
    spectatePudgeId = 0
    aimingHook = false
    syncInspectToHero()

proc handleInspectClick(
    window: Window,
    viewProjection: Mat4,
    overUi: bool
) =
  ## LMB click (not a camera drag) on a butcher opens their command
  ## card; empty ground snaps back to the owned hero when one exists.
  ## In replay / spectator mode the same click locks fog to that
  ## butcher's team, and empty ground returns to omniscient.
  if overUi or aimingHook or aimingGrapple or aimingBlink or aimingWall or
      aimingMine or aimingMove or aimingAttack or window.buttonDown[MouseRight]:
    inspectArmed = false
    return
  if window.buttonPressed[MouseLeft]:
    inspectArmed = true
    inspectOrigin = window.mousePos.vec2
  if not window.buttonReleased[MouseLeft] or not inspectArmed:
    return
  inspectArmed = false
  if (window.mousePos.vec2 - inspectOrigin).length > RtsCameraDragPixels:
    return
  let picked = pickPudge(window, viewProjection, includeDead = true)
  if picked != 0:
    inspectId = picked
    if not humanControlActive():
      spectatePudgeId = picked
  elif humanControlActive():
    syncInspectToHero()
  else:
    spectatePudgeId = 0
    inspectId = 0

proc handleHumanInput*(
    window: Window,
    viewProjection: Mat4,
    overUi: bool,
    live: bool,
    cameraTarget: var Vec3,
    followSelection: var bool,
    rightClickCommand = false,
    panHeld = false,
    panTap = false
) =
  ## Turns this frame's input into queued intents. Gating: history
  ## seeks spectate the past, and a dead hero can only watch the clock.
  ## `rightClickCommand` is a camera-cleared RMB click (no drag, no orbit).
  ## `panHeld` is the camera-grab key; `panTap` is a grab-key release
  ## that never moved the camera (so it can still arm wall).
  drainIntentResults()
  handleSeatSwap(window, viewProjection, live)
  if not panHeld:
    handleInspectClick(window, viewProjection, overUi)
  syncInspectFog()
  if not humanControlActive():
    return
  let index = heroIndex()
  if index < 0:
    return

  if window.buttonPressed[bindKey(BindCenter)]:
    let hero = heroGroundPoint()
    cameraTarget.x = hero.x
    cameraTarget.z = hero.z
    followSelection = true

  if panHeld:
    if window.buttonPressed[KeyEscape]:
      cancelAim()
    return

  let hero = run.world.pudges[index]
  if (aimingHook or aimingGrapple or aimingBlink or aimingWall or
      aimingMine) and
      (window.buttonPressed[KeyEscape] or window.buttonPressed[MouseRight]):
    if window.buttonPressed[MouseRight]:
      rmbBlockedCommand = true
    aimingHook = false
    aimingGrapple = false
    aimingBlink = false
    aimingWall = false
    aimingMine = false
  if (aimingMove or aimingAttack) and
      (window.buttonPressed[KeyEscape] or window.buttonPressed[MouseRight]):
    if window.buttonPressed[MouseRight]:
      rmbBlockedCommand = true
    aimingMove = false
    aimingAttack = false

  if not live:
    if anyCommandPressed(window, rightClickCommand, panTap):
      setHumanError("SPECTATING THE PAST - RETURN TO LIVE TO PLAY")
    cancelAim()
    rmbBlockedCommand = false
    return
  handleCheatCodes(window)
  if hero.state == Dying:
    if anyCommandPressed(window, rightClickCommand, panTap):
      setHumanError("DEAD - RESPAWNING")
    cancelAim()
    rmbBlockedCommand = false
    return

  if window.buttonPressed[bindKey(BindHook)]:
    if options.quickcast:
      discard castHookAtCursor(window, viewProjection, hero)
    else:
      let reason = hookBlockReason(hero)
      if reason.len > 0:
        setHumanError(reason)
      else:
        aimingGrapple = false
        aimingBlink = false
        aimingWall = false
        aimingMine = false
        aimingHook = true

  if window.buttonPressed[bindKey(BindGrapple)]:
    if options.quickcast:
      discard castGrappleAtCursor(window, viewProjection, hero)
    else:
      let reason = grappleBlockReason(hero)
      if reason.len > 0:
        setHumanError(reason)
      else:
        aimingHook = false
        aimingBlink = false
        aimingWall = false
        aimingMine = false
        aimingGrapple = true

  if window.buttonPressed[bindKey(BindBlink)]:
    # F hops toward the cursor, even while WASD is held. Facing and
    # walk heading used to steal this into a "blink the way you look"
    # hop; the mouse is the aim.
    discard castBlinkAtCursor(window, viewProjection, hero)
    aimingBlink = false

  if window.buttonPressed[bindKey(BindRot)]:
    beginRotCommand()

  let wallPressed =
    if panSharesWall(): panTap
    else: window.buttonPressed[bindKey(BindWall)]
  if wallPressed:
    if options.quickcast:
      discard castPlaceAhead(hero, ShopWall)
      aimingWall = false
    else:
      beginPlaceCommand(ShopWall)

  if window.buttonPressed[bindKey(BindMine)]:
    if options.quickcast:
      discard castPlaceAhead(hero, ShopMine)
      aimingMine = false
    else:
      beginPlaceCommand(ShopMine)

  if aimingHook and window.buttonPressed[MouseLeft] and not overUi:
    if castHookAtCursor(window, viewProjection, hero):
      aimingHook = false

  if aimingGrapple and window.buttonPressed[MouseLeft] and not overUi:
    if castGrappleAtCursor(window, viewProjection, hero):
      aimingGrapple = false

  if aimingBlink and window.buttonPressed[MouseLeft] and not overUi:
    if castBlinkAtCursor(window, viewProjection, hero):
      aimingBlink = false

  if aimingWall and window.buttonPressed[MouseLeft] and not overUi:
    if castPlaceAtCursor(window, viewProjection, hero, ShopWall):
      aimingWall = false

  if aimingMine and window.buttonPressed[MouseLeft] and not overUi:
    if castPlaceAtCursor(window, viewProjection, hero, ShopMine):
      aimingMine = false

  if aimingMove and window.buttonPressed[MouseLeft] and not overUi:
    let pick = groundUnderMouse(window, viewProjection)
    if pick.found:
      let (tileX, tileY) = tileOfGround(pick.point)
      queueHero(IntentWalk, tileX, tileY)
      walkPulsePoint = pick.point
      walkPulseTime = epochTime()
    aimingMove = false

  if aimingAttack and window.buttonPressed[MouseLeft] and not overUi:
    let picked = pickEnemyPudge(window, viewProjection, hero.team)
    if picked != 0:
      let target = pudgeIndex(run.world, picked)
      if target >= 0:
        if run.world.pudges[target].shieldTicks > 0:
          setHumanError("TARGET IS PROTECTED")
        else:
          issueAttack(picked)
      else:
        setHumanError("NO ENEMY THERE")
    else:
      setHumanError("NO ENEMY THERE")
    aimingAttack = false

  if rightClickCommand and not overUi and not rmbBlockedCommand:
    var targetId = pickEnemyPudge(window, viewProjection, hero.team)
    var groundFound = false
    var groundPoint = vec3(0)
    if targetId == 0:
      let pick = groundUnderMouse(window, viewProjection)
      groundFound = pick.found
      groundPoint = pick.point
      if groundFound:
        targetId = enemyNearGround(hero.team, groundPoint)
    if targetId != 0:
      let target = pudgeIndex(run.world, targetId)
      if target >= 0 and run.world.pudges[target].shieldTicks > 0:
        setHumanError("TARGET IS PROTECTED")
      elif target >= 0 and options.autocast and hookBlockReason(hero).len == 0:
        issueHookAtPudge(run.world.pudges[target])
      else:
        issueAttack(targetId)
    else:
      if not groundFound:
        let pick = groundUnderMouse(window, viewProjection)
        groundFound = pick.found
        groundPoint = pick.point
      if groundFound:
        let (tileX, tileY) = tileOfGround(groundPoint)
        queueHero(IntentWalk, tileX, tileY)
        walkPulsePoint = groundPoint
        walkPulseTime = epochTime()
  if rightClickCommand or not window.buttonDown[MouseRight]:
    rmbBlockedCommand = false

  if window.buttonPressed[bindKey(BindStop)]:
    queueHero(IntentStop)

  let buyBinds = [
    bindKey(BindUpgrade1), bindKey(BindUpgrade2),
    bindKey(BindUpgrade3), bindKey(BindUpgrade4)
  ]
  for i, key in buyBinds:
    if window.buttonPressed[key]:
      queueHero(IntentBuy, int32(i))

  # Base shop: 5-9 buy powerups while standing on the team's pad.
  let shopKeys = [Key5, Key6, Key7, Key8, Key9]
  for i, key in shopKeys:
    if window.buttonPressed[key]:
      queueHero(IntentBuyPower, int32(i))

  if window.buttonPressed[bindKey(BindPing)]:
    let pick = groundUnderMouse(window, viewProjection)
    if pick.found:
      let (tileX, tileY) = tileOfGround(pick.point)
      queueHero(IntentPing, tileX, tileY)

  # Direct keyboard steering, live alongside the mouse: WASD pushes a
  # rolling walk order ~8 tiles ahead each tick so the dest stays in
  # front of the butcher; arrows pan the camera. Releasing every walk
  # key stops on the spot. Orders ride the same intent queue as RMB,
  # so whichever input spoke last wins.
  block keyboardSteer:
    var dirX, dirZ = 0
    if window.buttonDown[KeyW]: dirZ -= 1
    if window.buttonDown[KeyS]: dirZ += 1
    if window.buttonDown[KeyA]: dirX -= 1
    if window.buttonDown[KeyD]: dirX += 1
    let
      now = epochTime()
      changed = (dirX, dirZ) != keyMoveLastDir
    if dirX == 0 and dirZ == 0:
      if changed:
        keyMoveLastDir = (0, 0)
        queueHero(IntentStop)
      break keyboardSteer
    if not changed and now - keyMoveLastTime < 1.0 / float64(TickRate):
      break keyboardSteer
    keyMoveLastDir = (dirX, dirZ)
    keyMoveLastTime = now
    let
      heroTile = tileOf(hero.position)
      dest = keyboardSteerDest(heroTile.x, heroTile.z, dirX, dirZ)
    queueHero(IntentWalk, int32(dest.x), int32(dest.z))

proc addGroundRing(
    renderer: var ShapeRenderer,
    center: Vec3,
    radius: float32,
    color: ColorRGBX,
    halfWidth: float32
) =
  ## Terrain-conforming circle outline.
  var points: seq[Vec3]
  const Sides = 48
  for i in 0 .. Sides:
    let a = float32(i) / float32(Sides) * TAU.float32
    points.add groundLift(
      center + vec3(cos(a) * radius, 0, sin(a) * radius), 0.25'f32
    )
  renderer.addPolyline(points, color, halfWidth)

proc addShopOverlays*(renderer: var ShapeRenderer) =
  ## Both base shop pads, always visible: a gold ring marks where
  ## powerups can be bought.
  const ShopGold = rgbx(255, 214, 120, 200)
  for shopX in [WestShopX, EastShopX]:
    let center = groundLift(vec3(
      float32(shopX) - HalfGrid + 0.5'f32, 0,
      float32(ShopZ) - HalfGrid + 0.5'f32
    ), 0.2'f32)
    renderer.addGroundRing(
      center, ShopRadiusTiles.float32 + 0.5'f32, ShopGold, 0.10'f32
    )
    renderer.addGroundRing(center, 0.6'f32, ShopGold, 0.06'f32)

proc drawHumanOverlays*(
    renderer: var ShapeRenderer,
    window: Window,
    viewProjection: Mat4
) =
  ## World-space feedback: cast telegraphs, aim ring and line, walk
  ## pulse, attack flash, and recent team pings.
  let now = epochTime()

  for pudge in run.world.pudges:
    if pudge.windupTicks <= 0 or not fogShownPudge(pudge):
      continue
    let
      start = groundLift(renderPoint(pudge.position), 0.5'f32)
      aim = groundLift(
        renderPoint(worldAtFine(pudge.windupAimX, pudge.windupAimY)),
        0.5'f32
      )
      color = if pudge.team == WestTeam: TelegraphWest else: TelegraphEast
    renderer.addLine(start, aim, color, 0.09'f32)

  let
    heroIdx = heroIndex()
    inspectIdx = inspectIndex()
  if humanControlActive() and heroIdx >= 0:
    let hero = run.world.pudges[heroIdx]
    if hero.state != Dying:
      let center = renderPoint(hero.position)
      if aimingHook:
        let radius =
          hookRange(hero.upgrades[UpgradeDistance]).float32 /
          WorldScale.float32
        renderer.addGroundRing(center, radius, RingGold, 0.10'f32)
        let pick = groundUnderMouse(window, viewProjection)
        if pick.found:
          renderer.addLine(
            groundLift(center, 0.45'f32),
            groundLift(pick.point, 0.45'f32),
            AimGold,
            0.08'f32
          )
          renderer.addCircle(
            groundLift(pick.point, 0.45'f32), 0.35'f32, AimGold, 12
          )
      elif aimingGrapple:
        let pick = groundUnderMouse(window, viewProjection)
        if pick.found:
          renderer.addLine(
            groundLift(center, 0.45'f32),
            groundLift(pick.point, 0.45'f32),
            AimGold,
            0.08'f32
          )
          renderer.addCircle(
            groundLift(pick.point, 0.45'f32), 0.35'f32, AimGold, 12
          )
      elif aimingBlink:
        renderer.addGroundRing(
          center, BlinkRangeTiles.float32, RingGold, 0.10'f32
        )
        let pick = groundUnderMouse(window, viewProjection)
        if pick.found:
          renderer.addLine(
            groundLift(center, 0.45'f32),
            groundLift(pick.point, 0.45'f32),
            AimGold,
            0.08'f32
          )
          renderer.addCircle(
            groundLift(pick.point, 0.45'f32), 0.35'f32, AimGold, 12
          )
      elif aimingWall or aimingMine:
        renderer.addGroundRing(
          center, PlaceRangeTiles.float32 + 0.5'f32, RingGold, 0.10'f32
        )
        let pick = groundUnderMouse(window, viewProjection)
        if pick.found:
          renderer.addLine(
            groundLift(center, 0.45'f32),
            groundLift(pick.point, 0.45'f32),
            AimGold,
            0.08'f32
          )
          renderer.addCircle(
            groundLift(pick.point, 0.45'f32), 0.35'f32, AimGold, 12
          )
      renderer.addGroundRing(center, 1.35'f32, AckGreen, 0.06'f32)

  let spectateIdx = spectateIndex()
  if spectateIdx >= 0:
    let subject = run.world.pudges[spectateIdx]
    if fogShownPudge(subject):
      renderer.addGroundRing(
        renderPoint(subject.position), 1.58'f32, SpectateGold, 0.10'f32
      )
  if inspectId != 0 and inspectIdx >= 0 and inspectIdx != spectateIdx and
      (not humanControlActive() or inspectIdx != heroIdx):
    let subject = run.world.pudges[inspectIdx]
    if subject.state != Dying and fogShownPudge(subject):
      let ringColor =
        if humanControlActive() and heroIdx >= 0 and
            subject.team == run.world.pudges[heroIdx].team:
          AllyInspect
        else:
          EnemyInspect
      renderer.addGroundRing(
        renderPoint(subject.position), 1.35'f32, ringColor, 0.07'f32
      )

  let pulseAge = now - walkPulseTime
  if pulseAge < WalkPulseSeconds:
    let
      grow = float32(pulseAge / WalkPulseSeconds)
      radius = 0.4'f32 + grow * 1.1'f32
      fade = uint8(clamp(210.0 - 210.0 * grow, 0.0, 255.0))
    renderer.addGroundRing(
      walkPulsePoint,
      radius,
      rgbx(AckGreen.r, AckGreen.g, AckGreen.b, fade),
      0.08'f32
    )

  let flashAge = now - attackFlashTime
  if flashAge < AttackFlashSeconds and attackFlashId != 0:
    let target = pudgeIndex(run.world, attackFlashId)
    if target >= 0 and run.world.pudges[target].state != Dying and
        fogShownPudge(run.world.pudges[target]):
      renderer.addGroundRing(
        renderPoint(run.world.pudges[target].position),
        1.5'f32,
        AttackRed,
        0.09'f32
      )

  if heroIdx >= 0:
    let team = run.world.pudges[heroIdx].team
    for ping in run.world.pings:
      if ping.team != team:
        continue
      let age =
        float(run.world.tick - ping.tick) / float(TickRate)
      if age > PingWorldSeconds:
        continue
      let
        center = renderPoint(worldAtTile(int(ping.x), int(ping.y)))
        grow = float32(age / PingWorldSeconds)
      renderer.addGroundRing(
        center, 0.5'f32 + grow * 1.6'f32, PingGold, 0.09'f32
      )
      renderer.addCircle(groundLift(center, 0.3'f32), 0.25'f32, PingGold, 10)
