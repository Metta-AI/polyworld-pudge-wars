## Pudge Wars Silky HUD: floating corner widgets over a full-screen world.

import
  std/[json, os, strformat, strutils, times, unicode],
  chroma, pixie, silky, vmath, windy,
  polyworld/[
    actioncam, bottomhud, chrome, commandcard, gameuis, hudchips, pathing,
    player, profiles, rtscameras
  ],
  content, maps, netproto, netclient, netsim, netpredict, sim, game, human,
  keybinds, replays

when not defined(emscripten):
  import hosting

const
  PanelRoster = vec2(380, 300)
  PanelEndScreen = vec2(640, 430)
  WestColor = rgbx(214, 86, 72, 255)
  EastColor = rgbx(82, 142, 220, 255)
  AllyHpColor* = rgbx(72, 210, 96, 255)
  EnemyHpColor* = rgbx(220, 56, 48, 255)
  ShieldHpColor = rgbx(140, 230, 255, 255)
    ## Ice HP while spawn-protected. Overrides ally/enemy so the
    ## window is readable on bars, pips, and the portrait.
  HookBarColor = rgbx(72, 148, 210, 255)
  ReadyGold = rgbx(255, 214, 120, 255)
  KillFeedSeconds = 6.0
  KillFeedMax = 6
  StingerSeconds = 3.8
  ChatPanelSize = vec2(380, 200)
  ChatLineH = 16.0'f32
  ChatInputH = 22.0'f32
  ChatTitleH = 22.0'f32
  ChatTabW = 72.0'f32
  EventLogMax = 48
  MaxChatDraft = 120
  MinimapWest = rgbx(78, 58, 48, 255)
  MinimapEast = rgbx(46, 64, 78, 255)
  MinimapRiver = rgbx(255, 78, 12, 255)
  MinimapIsland = rgbx(148, 132, 96, 255)
  MinimapForest = rgbx(22, 24, 22, 255)
  MinimapShop = rgbx(232, 196, 86, 255)
  MinimapPing = rgbx(255, 214, 90, 255)
  MinimapCamera = rgbx(238, 221, 168, 255)
  RuneColors*: array[RuneKind, ColorRGBX] = [
    rgbx(255, 72, 214, 255),   # Haste: DotA / WC3 pink
    rgbx(64, 168, 255, 255),   # Double Damage: electric blue
    rgbx(72, 224, 104, 255),   # Regen: life green
    rgbx(255, 164, 52, 255),   # Big Hook: amber (no WC3 analog)
    rgbx(255, 236, 80, 255),   # Lightning: charged yellow
    rgbx(255, 214, 90, 255)    # Bounty: gold
  ]
  RuneHudNames: array[RuneKind, string] = [
    "HASTE", "2X DMG", "REGEN",
    "BIG +" & $RuneBigHookDamagePercent & "%",
    "BOLT",
    "BOUNTY +" & $RuneBountyGold & "G"
  ]
  RunePlateSize = vec2(190, 22)
  HudName = rgbx(245, 229, 178, 255)
  HudMuted = rgbx(160, 171, 188, 255)
  ChipMenu = 0
  ChipTeam = 1
  ChipLog = 2
  ChipReplay = 3
  ChipDebug = 4
  ChipDirector = 5
  ChipFollow = 6
  MenuResume = 0
  MenuRestart = 1
  MenuControls = 2
  MenuAllies = 3
  MenuLog = 4
  MenuReplay = 5
  MenuDebug = 6
  MenuItemCount = 7
  MenuButtonH = 38.0'f32
  MenuButtonGap = 10.0'f32
  MenuPanelSize = vec2(400, 490)
  ControlsPanelSize = vec2(440, 360)
  ControlsBack = 0
  ControlsQuickcast = 1
  ControlsAutocast = 2
  ControlsItemCount = 3
  CmdMove = 0
  CmdStop = 1
  CmdHold = 2
  CmdAttack = 3
  CmdHook = 4
  CmdBlink = 5
  CmdRot = 6
  KillFeedW = 300.0'f32
  ShopPanelSize = vec2(400, 304)
  PermanentShopCols = 5
  PermanentShopRows = 1
  DebugWindowTitle = "Debug"
  DebugWindowOrigin = vec2(16, 40)
  DebugWindowSize = vec2(336, 880)
  BakedZoomInDistance* = 75.0'f32
    ## Closest camera distance shipped in graphics.nim (max zoom in).
  BakedZoomOutDistance* = 155.0'f32
    ## Farthest camera distance shipped in graphics.nim (min zoom / most out).
  ZoomInSliderMin = 4.0'f32
  ZoomInSliderMax = 160.0'f32
  ZoomOutSliderMin = 40.0'f32
  ZoomOutSliderMax = 400.0'f32
  DebugWest* = rgbx(214, 86, 72, 255)
  DebugEast* = rgbx(82, 142, 220, 255)
  DebugRiver* = rgbx(168, 56, 28, 255)
  DebugWater* = rgbx(255, 120, 40, 255)
  DebugIsland* = rgbx(214, 196, 120, 255)
  DebugBlocked* = rgbx(118, 72, 48, 255)
  DebugWalk* = rgbx(72, 196, 96, 255)
  DebugNoWalk* = rgbx(220, 64, 64, 255)
  SpectatorBannerSize = vec2(520, 28)
  SpectatorAllW = 90.0'f32

type
  HudChrome = object
    layout: GameUiLayout
    west: GameUiPanel
    east: GameUiPanel
    bottom: BottomHudLayout
    transport: GameUiPanel

  KillFeedEntry = object
    text: string
    color: ColorRGBX
    born: float64

  KillStinger = object
    title: string
    subtitle: string
    color: ColorRGBX
    born: float64

  EventLogEntry = object
    text: string
    color: ColorRGBX
    tick: int32

  ChatTab = enum
    ChatTabChat
    ChatTabEvents

var
  killFeed: seq[KillFeedEntry]
  killStinger: KillStinger
  alliesOpen = false
  menuOpen = false
  controlsOpen = false
  chatVisible = true
  chatTab = ChatTabChat
  chatComposing = false
  chatDraft = ""
  chatInputEnabled* = true
  eventLog: seq[EventLogEntry]
  menuCursor = 0
  menuRestartRequested = false
  debugMenuOpen* = false
  showTiles* = false
  showLayers* = false
  showWalkable* = false
  showPlayableBounds* = false
  showCollision* = false
  showCamera* = false
  zoomMinDistance* = BakedZoomInDistance
    ## Closest allowed camera distance (max zoom in).
  zoomMaxDistance* = BakedZoomOutDistance
    ## Farthest allowed camera distance (min zoom / most out).
  debugHoverFound* = false
  debugHoverX* = 0
  debugHoverZ* = 0
  showTransportBar = true
    ## Play/pause/speed strip. On for simulations and replays; `[` toggles.
  hostLobbyOpen* = false
    ## True while the host's pre-match lobby overlay is up. The strip
    ## stays hidden then so the lobby plate is not sitting on a scrubber.
  bugTapeArmed* = false
    ## F3 / F8: Stop will flush a named copy of the live match tape.
  bugTapeFromTick* = 0'i32
  bugTapeLastPath* = ""

proc menuIsOpen*(): bool =
  ## True while the F9 pause plate is up.
  menuOpen

proc chatTyping*(): bool =
  ## True while the match-chat field has keyboard focus.
  chatComposing

proc cancelChatTyping*() =
  ## Drops an unfinished draft (lobby, pause, seek, rematch).
  chatComposing = false
  chatDraft.setLen(0)

proc toggleDebugMenu*() =
  ## F3 / DBG chip: overlay toggles, fog, tape, and ping readouts.
  debugMenuOpen = not debugMenuOpen
  if debugMenuOpen and not (
      showTiles or showLayers or showWalkable or
      showPlayableBounds or showCollision or showCamera):
    # First open shows something at once instead of a bare panel.
    showCollision = true

proc consumeMenuRestart*(): bool =
  ## True once after Restart Game; the frame loop rebuilds the match.
  result = menuRestartRequested
  menuRestartRequested = false

proc bugTapePlayerName(): string =
  let name = netPlayerName()
  if name.len > 0: name else: "human"

proc bugTapePudgeId(): int32 =
  if localSeat >= 0 and localSeat < run.world.pudges.len:
    run.world.pudges[localSeat].id
  else:
    0'i32

proc copyPathToClipboard(path: string) =
  when defined(macosx):
    discard execShellCmd(
      "printf '%s' " & quoteShell(path) & " | pbcopy"
    )
  else:
    discard

proc startBugRecording*(): bool =
  ## Arms a mid-match flush of the live ReplayRecorder. The match
  ## already records from tick 0; Start just marks the bug window.
  when defined(emscripten):
    setHumanError("BUG TAPE IS DESKTOP ONLY")
    return false
  if run.replayMode:
    setHumanError("CANNOT RECORD A PLAYBACK")
    return false
  if run.recorder == nil:
    if netRole == NetClient:
      setHumanError("THE HOST HOLDS THE TAPE")
    else:
      setHumanError("START THE MATCH FIRST")
    return false
  bugTapeArmed = true
  bugTapeFromTick = run.world.tick
  setHumanError("RECORDING BUG TAPE…")
  echo "bug tape: recording from tick ", bugTapeFromTick,
    "  (F8 or F3 Record bug tape to stop)"
  true

proc stopBugRecording*(): bool =
  ## Writes `duels/bug_*.pwr` from the live tape without ending the match.
  when defined(emscripten):
    bugTapeArmed = false
    return false
  if run.recorder == nil:
    setHumanError("NO LIVE TAPE TO SAVE")
    bugTapeArmed = false
    return false
  if run.recorder.data.hashes.len == 0:
    setHumanError("BUG TAPE EMPTY — PLAY A MOMENT FIRST")
    return false
  var eventsSrc = ""
  when not defined(emscripten):
    if matchLog != nil:
      let src = matchLog.dir / "events.jsonl"
      if fileExists(src):
        eventsSrc = src
  try:
    bugTapeLastPath = writeBugReplay(
      BugTapeDir,
      run.recorder.data,
      localSeat,
      bugTapePlayerName(),
      bugTapePudgeId(),
      bugTapeFromTick,
      eventsSrc
    )
  except CatchableError as error:
    setHumanError("BUG TAPE FAILED")
    echo "bug tape: save failed: ", error.msg
    return false
  bugTapeArmed = false
  copyPathToClipboard(bugTapeLastPath)
  setHumanError("BUG TAPE " & bugTapeLastPath.extractFilename)
  echo "bug tape saved: ", bugTapeLastPath
  echo "bug tape pointer: ", absolutePath(BugTapeDir / BugLatestName)
  true

proc setBugTapeArmed*(armed: bool) =
  ## Checkbox / F8: Start arms, Stop flushes. No-op if already there.
  if armed == bugTapeArmed:
    return
  if armed:
    discard startBugRecording()
  else:
    discard stopBugRecording()

proc toggleBugRecording*() =
  ## F8: start if idle, stop-and-save if Recording…
  setBugTapeArmed(not bugTapeArmed)

proc flushBugTapeIfArmed*() =
  ## Rematch / quit: keep the bug window if they never pressed Stop.
  if bugTapeArmed:
    discard stopBugRecording()
  bugTapeArmed = false

proc menuCanRestart(): bool =
  not run.replayMode and netRole != NetClient

proc transportBarOpen*(): bool =
  ## Play/pause/speed strip. On by default while a simulation is
  ## running; hidden on the host lobby overlay.
  showTransportBar and not hostLobbyOpen

proc toggleTransportBar*() =
  if hostLobbyOpen:
    return
  showTransportBar = not showTransportBar

proc pushKillFeed*(text: string, team: Team) =
  ## Appends one line to the top-right kill toast and the Events log.
  let
    color = if team == WestTeam: WestColor else: EastColor
    entry = KillFeedEntry(
      text: text,
      color: color,
      born: epochTime()
    )
  if killFeed.len >= KillFeedMax:
    killFeed.delete(0)
  killFeed.add entry
  if eventLog.len >= EventLogMax:
    eventLog.delete(0)
  eventLog.add EventLogEntry(
    text: text,
    color: color,
    tick: if run != nil: run.world.tick else: 0
  )

proc pushKillStinger*(title, subtitle: string, team: Team) =
  ## Big centered Dota-style streak / shutdown / first-blood banner.
  ## Replaces any live stinger so the latest shout wins.
  if title.len == 0:
    return
  killStinger = KillStinger(
    title: title,
    subtitle: subtitle,
    color: if team == WestTeam: WestColor else: EastColor,
    born: epochTime()
  )

proc clearKillFeed*() =
  killFeed.setLen(0)
  eventLog.setLen(0)
  killStinger.title.setLen(0)
  killStinger.subtitle.setLen(0)
  if run != nil:
    run.clearChat()
  cancelChatTyping()

var recapPublished = false
var lastStatePhase = ""
var lastStateWest = -1
var lastStateEast = -1
var lastStateTick = -32

proc resetMatchRecap*() =
  recapPublished = false
  lastStatePhase = ""
  lastStateWest = -1
  lastStateEast = -1
  lastStateTick = -32

proc matchPhaseName(): string =
  if run.world.gameOver:
    return "over"
  if netRole == NetClient:
    case netClientPhase()
    of NcLobby, NcOffline:
      return "joining"
    of NcDropped, NcDesynced:
      return "dropped"
    of NcReconnecting:
      return "reconnecting"
    of NcPlaying:
      discard
  if run.world.tick <= 0:
    return "starting"
  "live"

proc matchStateJson(): string =
  let heroSlot = if humanControlActive(): heroIndex() else: -1
  let phase = matchPhaseName()
  var body = %*{
    "phase": phase,
    "tick": int(run.world.tick),
    "seconds": int(run.world.tick div TickRate),
    "killGoal": int(run.world.killGoal),
    "west": int(run.world.teamKills[WestTeam.ord]),
    "east": int(run.world.teamKills[EastTeam.ord]),
    "you": heroSlot
  }
  if run.world.gameOver:
    body["winner"] = %*(if run.world.winner == WestTeam: "west" else: "east")
  $body

proc publishMatchState() =
  ## One compact line the web shell can parse. Throttled to score/phase
  ## changes and once per second so the console stays readable.
  let
    phase = matchPhaseName()
    west = int(run.world.teamKills[WestTeam.ord])
    east = int(run.world.teamKills[EastTeam.ord])
    tick = int(run.world.tick)
  if phase == lastStatePhase and west == lastStateWest and east == lastStateEast and
      tick - lastStateTick < TickRate:
    return
  lastStatePhase = phase
  lastStateWest = west
  lastStateEast = east
  lastStateTick = tick
  echo "pw-state:", matchStateJson()

proc matchRecapJson(): string =
  let heroSlot = if humanControlActive(): heroIndex() else: -1
  let winner = run.world.winner
  var headline = if winner == WestTeam: "west" else: "east"
  if heroSlot >= 0:
    headline =
      if run.world.pudges[heroSlot].team == winner: "victory" else: "defeat"
  var players = newJArray()
  for pudge in run.world.pudges:
    players.add %*{
      "id": int(pudge.id),
      "slot": pudge.slot,
      "team": if pudge.team == WestTeam: "west" else: "east",
      "kills": int(pudge.kills),
      "deaths": int(pudge.deaths),
      "hooksLanded": int(pudge.hooksLanded),
      "hooksThrown": int(pudge.hooksThrown),
      "headshots": int(pudge.headshotCount),
      "denies": int(pudge.denyCount),
      "gold": int(pudge.gold),
      "you": heroSlot >= 0 and pudge.slot == heroSlot
    }
  $(%*{
    "winner": if winner == WestTeam: "west" else: "east",
    "headline": headline,
    "tick": int(run.world.tick),
    "seconds": int(run.world.tick div TickRate),
    "killGoal": int(run.world.killGoal),
    "west": int(run.world.teamKills[WestTeam.ord]),
    "east": int(run.world.teamKills[EastTeam.ord]),
    "you": heroSlot,
    "players": players
  })

proc publishMatchRecap() =
  if recapPublished:
    return
  recapPublished = true
  echo "pw-match:", matchRecapJson()

proc placeChrome(layout: GameUiLayout): HudChrome =
  let transportH = transportStripHeight(transportBarOpen())
  HudChrome(
    layout: layout,
    west: layout.panel(GameUiRegion.TopLeft, PanelRoster),
    east: layout.panel(GameUiRegion.TopRight, PanelRoster),
    bottom: placeBottomHud(layout.size, transportH, 2, int(InventorySlots)),
    transport: compactTransportPanel(layout.size, transportH)
  )

proc hudLayoutFits(layoutSize: Vec2): bool =
  let layout = initGameUiLayout(layoutSize, 0, 10, 0)
  layout.size.x >= BottomHudMinWidth and
    layout.gameAreaSize.y >= BottomHudMinGameHeight

proc hudUiScale*(windowSize: Vec2): float32 =
  fitUiScale(windowSize, hudLayoutFits, UiCrispSteps)

proc hudUiScale*(window: Window): float32 =
  hudUiScale(vec2(window.size.x.float32, window.size.y.float32))

proc currentLayout*(window: Window): GameUiLayout =
  initGameUiLayout(
    vec2(window.size.x.float32, window.size.y.float32) /
      hudUiScale(window),
    0,
    10,
    0
  )

proc worldPixelPanel*(window: Window): GameUiPanel =
  ## 3D play rectangle in window pixels: the whole window. Widgets
  ## float over the world instead of reserving strips of it.
  currentLayout(window).worldPanel.scaled(hudUiScale(window))

proc mouseOverDebugMenu(mouse: Vec2): bool =
  ## Returns whether the pointer is over the F3 debug window.
  if not debugMenuOpen or DebugWindowTitle notin subWindowStates:
    return false
  let state = subWindowStates[DebugWindowTitle]
  if state == nil or not state.visible:
    return false
  let
    left = state.pos.x
    top = state.pos.y
    right = left + state.size.x
    bottom = top + state.size.y
  mouse.x >= left and mouse.x <= right and
    mouse.y >= top and mouse.y <= bottom

proc clampZoomLimits*() =
  ## Keeps the zoom-in floor below the zoom-out cap.
  if zoomMinDistance > zoomMaxDistance:
    swap(zoomMinDistance, zoomMaxDistance)
  zoomMinDistance = clamp(zoomMinDistance, ZoomInSliderMin, ZoomInSliderMax)
  zoomMaxDistance = clamp(zoomMaxDistance, ZoomOutSliderMin, ZoomOutSliderMax)
  if zoomMinDistance > zoomMaxDistance:
    zoomMaxDistance = zoomMinDistance

proc clampCameraDistance*(distance: float32): float32 =
  ## Scroll-wheel and slider edits share this live [min, max] clamp.
  clampZoomLimits()
  clamp(distance, zoomMinDistance, zoomMaxDistance)

proc shopPanelOf(layout: GameUiLayout): GameUiPanel =
  ## Left of play, sitting just above the hero cluster so it never
  ## covers the pad or the command card.
  let
    transportH = transportStripHeight(transportBarOpen())
    hud = placeBottomHud(layout.size, transportH, 2, int(InventorySlots))
  GameUiPanel(
    origin: vec2(
      HudMargin,
      max(hud.bar.origin.y - ShopPanelSize.y - 8, 8)
    ),
    size: ShopPanelSize
  )

proc heroWantsShop(): bool =
  if not humanControlActive() or heroIndex() < 0:
    return false
  let hero = run.world.pudges[heroIndex()]
  hero.state != Dying and hero.inOwnShop

proc spectatorChromeVisible(): bool =
  ## Replay and idle spectators get the POV banner; a live seat does not.
  not humanControlActive()

proc spectatorBannerPanel(layout: GameUiLayout): GameUiPanel =
  layout.panel(GameUiRegion.TopCenter, SpectatorBannerSize)

proc spectatorAllPanel(banner: GameUiPanel): GameUiPanel =
  GameUiPanel(
    origin: banner.origin + vec2(4, 4),
    size: vec2(SpectatorAllW, banner.size.y - 8)
  )

proc butcherDisplayName*(index: int): string =
  ## Name plate for one roster seat: lobby name, bot personality, or P<id>.
  if run == nil or index < 0 or index >= run.world.pudges.len:
    return ""
  let
    pudge = run.world.pudges[index]
    seat = int(pudge.lobbySeat)
  if netRole == NetClient:
    result = netSeatName(seat)
  when not defined(emscripten):
    if result.len == 0 and netRole == NetHost:
      result = hostSeatName(seat)
  if result.len == 0 and index == localSeat:
    result = netPlayerName()
  if result.len == 0 and index < run.seatLabels.len:
    result = run.seatLabels[index]
  if result.len == 0:
    result = "P" & $pudge.id

proc pudgeHpColor*(pudge: Pudge): ColorRGBX =
  ## Ally green / enemy red from the local POV. Omniscient keeps team
  ## colors, with fountain and river as status tints. Spawn shield
  ## paints ice over that so invuln is obvious on every HP surface.
  if pudge.shieldTicks > 0 and pudge.state == Alive:
    return ShieldHpColor
  let rel = viewRelationTeam()
  if rel >= 0:
    if pudge.team.ord == rel: AllyHpColor else: EnemyHpColor
  elif pudge.onIslandFountain: rgbx(96, 220, 110, 255)
  elif pudge.inRiver: rgbx(220, 88, 40, 255)
  elif pudge.team == WestTeam: WestColor
  else: EastColor

proc chatPanelOf(layout: GameUiLayout): GameUiPanel =
  ## Bottom-left chat / events plate, above the hero cluster / shop / strip.
  let transportH = transportStripHeight(transportBarOpen())
  var floorY = layout.size.y - transportH - HudMargin
  if commandCardVisible():
    let hud = placeBottomHud(layout.size, transportH, 2, int(InventorySlots))
    floorY = min(floorY, hud.bar.origin.y)
  if heroWantsShop():
    floorY = min(floorY, shopPanelOf(layout).origin.y)
  GameUiPanel(
    origin: vec2(HudMargin, max(floorY - ChatPanelSize.y - 8, 8)),
    size: ChatPanelSize
  )

proc mouseOverUi*(window: Window, mouse: Vec2): bool =
  ## True over floating HUD widgets that should eat camera and world
  ## clicks. Everywhere else the full-screen world stays clickable.
  if mouseOverDebugMenu(mouse):
    return true
  if mouseOverFpsDebugger(mouse):
    return true
  if menuOpen:
    return true
  let
    layout = currentLayout(window)
    chrome = placeChrome(layout)
  if spectatorChromeVisible() and spectatorBannerPanel(layout).contains(mouse):
    return true
  if heroWantsShop() and shopPanelOf(layout).contains(mouse):
    return true
  if chrome.bottom.minimap.contains(mouse) or
      chrome.bottom.buttons.contains(mouse) or
      scorePlatePanel(layout).contains(mouse):
    return true
  if commandCardVisible() and (
      chrome.bottom.profile.contains(mouse) or
      chrome.bottom.actions.contains(mouse)):
    return true
  if transportBarOpen() and chrome.transport.contains(mouse):
    return true
  if alliesOpen and
      (chrome.west.contains(mouse) or chrome.east.contains(mouse)):
    return true
  chatVisible and chatPanelOf(layout).contains(mouse)

proc minimapArea(window: Window): GameUiPanel =
  ## Circular map well inside the bottom-right compass plate.
  placeChrome(currentLayout(window)).bottom.minimap.minimapMap()

proc updateMinimapCamera*(
    window: Window,
    mouse: Vec2,
    cameraTarget: var Vec3,
    minimapPanning: var bool,
    followSelection: var bool
) =
  ## Pans the camera while the primary button drags on the compass well.
  ## Option+click issues a team ping at that tile instead of panning.
  if menuOpen:
    minimapPanning = false
    return
  let area = minimapArea(window)
  if altModifierDown(window):
    minimapPanning = false
    if window.buttonPressed[MouseLeft] and insideMinimapCircle(area, mouse):
      let world = minimapWorldPoint(mouse, area.origin, area.size, HalfGrid)
      let (tileX, tileY) = tileOfGround(vec3(world.x, 0, world.y))
      discard issueMapPing(tileX, tileY)
    return
  if window.buttonPressed[MouseLeft] and insideMinimapCircle(area, mouse):
    minimapPanning = true
    followSelection = false
  if not window.buttonDown[MouseLeft]:
    minimapPanning = false
  if minimapPanning:
    let point = minimapWorldPoint(mouse, area.origin, area.size, HalfGrid)
    cameraTarget.x = point.x
    cameraTarget.z = point.y

proc minimapPosition(position: Vec3, area: GameUiPanel): Vec2 =
  ## Projects a render-space position into the minimap rectangle.
  let
    x = clamp((position.x + HalfGrid) / (HalfGrid * 2), 0.0'f32, 1.0'f32)
    y = clamp((position.z + HalfGrid) / (HalfGrid * 2), 0.0'f32, 1.0'f32)
  area.origin + vec2(x * area.size.x, y * area.size.y)

proc hudPoint(position: WorldPoint): Vec3 =
  ## Converts authoritative integer coordinates at the HUD boundary.
  vec3(
    position.x.float32 / WorldScale.float32,
    position.y.float32 / WorldScale.float32,
    position.z.float32 / WorldScale.float32
  )

proc drawMinimapPip(
    sk: Silky,
    area: GameUiPanel,
    point: Vec2,
    pipSize: float32,
    color: ColorRGBX,
    ring = false
) =
  ## Square pip clipped to the circular well.
  if not insideMinimapCircle(area, point):
    return
  if ring:
    sk.drawRect(point - vec2(pipSize * 0.5'f32 + 2), vec2(pipSize + 4), rgbx(255, 248, 220, 255))
  sk.drawRect(point - vec2(pipSize * 0.5'f32), vec2(pipSize), color)

proc drawMinimap(
    sk: Silky,
    window: Window,
    hud: BottomHudLayout,
    cameraTarget: Vec3,
    cameraDistance: float32
) =
  ## Circular compass: banks, river, fountain, pips, then the bronze ring.
  let
    panel = hud.minimap
    area = panel.minimapMap()
    grid = float32(GridTiles)
    playX0 = float32(PlayWestMin) / grid
    playX1 = float32(PlayEastMax + 1) / grid
    playZ0 = float32(PlayZMin) / grid
    playZ1 = float32(PlayZMax + 1) / grid
    riverX0 = float32(RiverWestX) / grid
    riverX1 = float32(RiverEastX + 1) / grid
    play = GameUiPanel(
      origin: area.origin + vec2(playX0 * area.size.x, playZ0 * area.size.y),
      size: vec2(
        (playX1 - playX0) * area.size.x,
        (playZ1 - playZ0) * area.size.y
      )
    )
    westW = (riverX0 - playX0) / (playX1 - playX0) * play.size.x
    riverW = (riverX1 - riverX0) / (playX1 - playX0) * play.size.x
  sk.drawRect(area.origin, area.size, MinimapForest)
  sk.drawRect(play.origin, vec2(westW, play.size.y), MinimapWest)
  sk.drawRect(
    play.origin + vec2(westW, 0),
    vec2(riverW, play.size.y),
    MinimapRiver
  )
  sk.drawRect(
    play.origin + vec2(westW + riverW, 0),
    vec2(max(play.size.x - westW - riverW, 1), play.size.y),
    MinimapEast
  )
  let
    cellW = area.size.x / grid
    cellH = area.size.y / grid
  for z in PlayZMin .. PlayZMax:
    let hw = riverHalfWidthAt(z)
    if hw >= RiverHalfWidth:
      continue
    let y = area.origin.y + float32(z) * cellH
    let west0 = area.origin.x + float32(RiverWestX) * cellW
    let west1 = area.origin.x + float32(RiverCenterX - hw) * cellW
    if west1 > west0:
      sk.drawRect(vec2(west0, y), vec2(west1 - west0, cellH), MinimapWest)
    let east0 = area.origin.x + float32(RiverCenterX + hw + 1) * cellW
    let east1 = area.origin.x + float32(RiverEastX + 1) * cellW
    if east1 > east0:
      sk.drawRect(vec2(east0, y), vec2(east1 - east0, cellH), MinimapEast)
  let islandSize = vec2(
    float32(IslandRadius * 2 + 1) / grid * area.size.x,
    float32(IslandRadius * 2 + 1) / grid * area.size.y
  )
  sk.drawRect(
    minimapPosition(
      hudPoint(worldAtTile(IslandCenterX, IslandCenterZ)), area
    ) - islandSize * 0.5'f32,
    islandSize,
    MinimapIsland
  )
  sk.drawMinimapPip(
    area,
    minimapPosition(hudPoint(worldAtTile(WestShopX, ShopZ)), area),
    5, MinimapShop
  )
  sk.drawMinimapPip(
    area,
    minimapPosition(hudPoint(worldAtTile(EastShopX, ShopZ)), area),
    5, MinimapShop
  )

  let heroSlot = if humanControlActive(): heroIndex() else: -1
  let spectateSlot = spectateIndex()
  var heroTeam = WestTeam
  if heroSlot >= 0:
    heroTeam = run.world.pudges[heroSlot].team
  if heroSlot >= 0:
    for ping in run.world.pings:
      if ping.team != heroTeam:
        continue
      if run.world.tick - ping.tick > TickRate * 3:
        continue
      sk.drawMinimapPip(
        area,
        minimapPosition(
          hudPoint(worldAtTile(int(ping.x), int(ping.y))), area
        ),
        9, MinimapPing
      )

  for rune in run.world.runes:
    if not fogCanSee(rune.position):
      continue
    sk.drawMinimapPip(
      area,
      minimapPosition(hudPoint(rune.position), area),
      5, RuneColors[rune.kind]
    )
  if run.world.runePeriod > 0:
    let
      spawn = worldAtTile(RiverCenterX, int(run.world.nextRuneZTile))
      soon = runeSoonTicks(run.world)
      pip = if soon <= TickRate * 5: 7'f32 else: 5'f32
    sk.drawMinimapPip(
      area,
      minimapPosition(hudPoint(spawn), area),
      pip,
      RuneColors[run.world.nextRuneKind],
      ring = soon <= TickRate * 5
    )

  let viewTeam = fogTeam()
  for prop in run.world.props:
    if not prop.alive:
      continue
    if viewTeam >= 0 and not propVisibleTo(prop, Team(viewTeam)):
      continue
    if prop.kind == PropWall and not fogCanSee(prop.propCenter):
      continue
    let point = minimapPosition(hudPoint(prop.propCenter), area)
    if prop.kind == PropWall:
      sk.drawMinimapPip(area, point, 6, rgbx(138, 94, 54, 255))
    elif prop.kind == PropWard:
      sk.drawMinimapPip(area, point, 5, rgbx(120, 255, 196, 230))
    else:
      sk.drawMinimapPip(area, point, 4, rgbx(88, 96, 72, 200))

  for i, pudge in run.world.pudges:
    if pudge.state == Dying:
      continue
    if not fogShownPudge(pudge):
      continue
    sk.drawMinimapPip(
      area,
      minimapPosition(hudPoint(pudge.position), area),
      7,
      pudgeHpColor(pudge),
      ring = i == heroSlot or i == spectateSlot or pudge.shieldTicks > 0
    )

  let aspect = currentLayout(window).worldPanel.aspect
  sk.drawCameraFrame(
    minimapViewport(
      cameraTarget, cameraDistance, aspect,
      area.origin, area.size, HalfGrid
    ),
    MinimapCamera
  )
  sk.drawLabel(
    "RIVER ARENA",
    hud.minimapTitle.origin,
    hud.minimapTitle.size,
    HudName,
    "Small",
    CenterAlign
  )

proc addHudSeconds(s: var string, ticks: int32)

proc runePlatePanel(layout: GameUiLayout): GameUiPanel =
  ## Next-rune clock, stacked under the score plate.
  let score = scorePlatePanel(layout)
  GameUiPanel(
    origin: vec2(score.origin.x, score.origin.y + score.size.y + 4),
    size: RunePlateSize
  )

proc killFeedTop(layout: GameUiLayout): float32 =
  ## Kill feed sits under the rune clock when river drops are on.
  if run != nil and run.world.runePeriod > 0:
    let plate = runePlatePanel(layout)
    return plate.origin.y + plate.size.y + 6.0'f32
  hudToastY(layout)

proc drawRunePlate(sk: Silky, layout: GameUiLayout) =
  ## Public drop clock: kind, north/south, seconds remaining.
  if run == nil or run.world.runePeriod <= 0:
    return
  let
    panel = runePlatePanel(layout)
    kind = run.world.nextRuneKind
    soon = runeSoonTicks(run.world)
    north = run.world.nextRuneFromNorth
  sk.drawEtched(panel.origin, panel.size, HudChipFill)
  hudScratch.setLen(0)
  hudScratch.add RuneHudNames[kind]
  hudScratch.add " "
  hudScratch.add(if north: "N" else: "S")
  sk.drawLabel(
    hudScratch,
    panel.origin + vec2(6, 0),
    vec2(panel.size.x * 0.68'f32, panel.size.y),
    RuneColors[kind],
    "Small"
  )
  hudScratch.setLen(0)
  hudScratch.addHudSeconds(soon)
  sk.drawLabel(
    hudScratch,
    panel.origin + vec2(panel.size.x * 0.62'f32 - 6, 0),
    vec2(panel.size.x * 0.38'f32, panel.size.y),
    HudName,
    "Small",
    RightAlign
  )

proc drawKillFeed(sk: Silky, layout: GameUiLayout) =
  ## Fading list of recent kills below the top-right score plate,
  ## League-style, so the top-center stays clear for gameplay.
  let now = epochTime()
  var alive: seq[KillFeedEntry]
  for entry in killFeed:
    if now - entry.born < KillFeedSeconds:
      alive.add entry
  killFeed = alive
  var y = killFeedTop(layout)
  for i in countdown(killFeed.len - 1, 0):
    let
      entry = killFeed[i]
      fade = clamp(
        (KillFeedSeconds - (now - entry.born)) / 1.5, 0.0, 1.0
      )
      color = rgbx(
        entry.color.r, entry.color.g, entry.color.b,
        uint8(float(entry.color.a) * fade)
      )
    sk.drawLabel(
      entry.text,
      vec2(layout.size.x - layout.margin - KillFeedW, y),
      vec2(KillFeedW, 18),
      color,
      "Hud",
      RightAlign
    )
    y += 20

proc drawKillStinger(sk: Silky, layout: GameUiLayout) =
  ## Centered Dota kill-streak shout: GODLIKE, FIRST BLOOD, SHUTDOWN.
  ## Fog does not hide it; both banks and spectators see the same line.
  if killStinger.title.len == 0:
    return
  let
    now = epochTime()
    age = now - killStinger.born
  if age >= StingerSeconds:
    killStinger.title.setLen(0)
    killStinger.subtitle.setLen(0)
    return
  let fade = clamp((StingerSeconds - age) / 0.85, 0.0, 1.0)
  let titleColor = rgbx(
    ReadyGold.r, ReadyGold.g, ReadyGold.b,
    uint8(float(ReadyGold.a) * fade)
  )
  let subColor = rgbx(
    killStinger.color.r, killStinger.color.g, killStinger.color.b,
    uint8(float(killStinger.color.a) * fade)
  )
  let y = layout.size.y * 0.16'f32
  sk.drawLabel(
    killStinger.title,
    vec2(0, y),
    vec2(layout.size.x, 36),
    titleColor,
    "H1",
    CenterAlign
  )
  if killStinger.subtitle.len > 0:
    sk.drawLabel(
      killStinger.subtitle,
      vec2(0, y + 34),
      vec2(layout.size.x, 20),
      subColor,
      "Hud",
      CenterAlign
    )

proc drawEndScreen(sk: Silky, window: Window, layout: GameUiLayout) =
  ## Victory or defeat plate with the match stat recap.
  publishMatchRecap()
  let
    panel = layout.panel(GameUiRegion.Center, PanelEndScreen)
    winner = run.world.winner
    inner = sk.beginPanel(
      panel,
      if winner == WestTeam: WestColor else: EastColor
    )
  hudScratch.setLen(0)
  let heroSlot = if humanControlActive(): heroIndex() else: -1
  if heroSlot >= 0:
    if run.world.pudges[heroSlot].team == winner:
      hudScratch.add "VICTORY"
    else:
      hudScratch.add "DEFEAT"
  elif winner == WestTeam:
    hudScratch.add "WEST WINS"
  else:
    hudScratch.add "EAST WINS"
  sk.drawLabel(
    hudScratch,
    inner.origin,
    vec2(inner.size.x, 30),
    ReadyGold,
    "H1",
    CenterAlign
  )
  sk.drawLabel(
    "        K    D    HOOKS    HEADSHOT    DENY",
    inner.origin + vec2(0, 44),
    vec2(inner.size.x, 18),
    LabelColor,
    "Small"
  )
  var y = 66.0'f32
  for i, pudge in run.world.pudges:
    hudScratch.setLen(0)
    hudScratch.add "P"
    hudScratch.addHudInt(int(pudge.id))
    if i == heroSlot:
      hudScratch.add " (YOU)"
    hudScratch.add "    "
    hudScratch.addHudInt(int(pudge.kills))
    hudScratch.add "    "
    hudScratch.addHudInt(int(pudge.deaths))
    hudScratch.add "     "
    hudScratch.addHudInt(int(pudge.hooksLanded))
    hudScratch.add "/"
    hudScratch.addHudInt(int(pudge.hooksThrown))
    hudScratch.add "        "
    hudScratch.addHudInt(int(pudge.headshotCount))
    hudScratch.add "          "
    hudScratch.addHudInt(int(pudge.denyCount))
    sk.drawLabel(
      hudScratch,
      inner.origin + vec2(0, y),
      vec2(inner.size.x, 18),
      if pudge.team == WestTeam: WestColor else: EastColor,
      "Small"
    )
    y += 22
  when defined(emscripten):
    sk.drawLabel(
      if run.replayMode:
        "match recap - rewind the transport to relive it"
      else:
        "view stats on the site, or leave this arena",
      inner.origin + vec2(0, inner.size.y - 64),
      vec2(inner.size.x, 18),
      LabelColor,
      "Small",
      CenterAlign
    )
    if not run.replayMode:
      let statsBtn = GameUiPanel(
        origin: inner.origin + vec2(0, inner.size.y - 42),
        size: vec2((inner.size.x - 12) * 0.5'f32, 34)
      )
      let leaveBtn = GameUiPanel(
        origin: inner.origin + vec2(statsBtn.size.x + 12, inner.size.y - 42),
        size: vec2(inner.size.x - statsBtn.size.x - 12, 34)
      )
      let statsHover = statsBtn.contains(sk.mousePos)
      let leaveHover = leaveBtn.contains(sk.mousePos)
      sk.drawEtched(
        statsBtn.origin,
        statsBtn.size,
        if statsHover: HudChipActive else: HudChipFill
      )
      sk.drawEtched(
        leaveBtn.origin,
        leaveBtn.size,
        if leaveHover: HudChipActive else: HudChipFill
      )
      sk.drawLabel(
        "VIEW STATS",
        statsBtn.origin,
        statsBtn.size,
        if statsHover: ReadyGold else: LabelColor,
        "Hud",
        CenterAlign
      )
      sk.drawLabel(
        "BACK TO SITE",
        leaveBtn.origin,
        leaveBtn.size,
        if leaveHover: ReadyGold else: LabelColor,
        "Hud",
        CenterAlign
      )
      if window.clicked(sk, statsBtn):
        echo "pw-nav:recap"
      elif window.clicked(sk, leaveBtn):
        echo "pw-nav:home"
  else:
    sk.drawLabel(
      if run.replayMode:
        "match recap - rewind the transport to relive it"
      elif netRole == NetClient:
        "the host picks the rematch - stay connected"
      else:
        "R - rematch    rewind the transport to relive it",
      inner.origin + vec2(0, inner.size.y - 20),
      vec2(inner.size.x, 18),
      LabelColor,
      "Small",
      CenterAlign
    )
    discard window

proc drawRoster(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    team: Team,
    title: string,
    followSelection: var bool
) =
  let inner = sk.beginPanel(panel, if team == WestTeam: WestColor else: EastColor)
  sk.drawLabel(title, inner.origin, vec2(inner.size.x, 22), LabelColor, "Hud")
  var y = 28.0'f32
  for pudge in run.world.pudges:
    if pudge.team != team:
      continue
    let row = GameUiPanel(
      origin: inner.origin + vec2(0, y),
      size: vec2(inner.size.x, 48)
    )
    if spectatePudgeId == pudge.id:
      sk.drawRect(row.origin, row.size, rgbx(240, 218, 128, 50))
    if not humanControlActive() and window.clicked(sk, row):
      lockSpectatorEyes(pudge.id)
      followSelection = true
    hudScratch.setLen(0)
    hudScratch.add butcherDisplayName(pudgeIndex(run.world, pudge.id))
    hudScratch.add "  K"
    hudScratch.addHudInt(int(pudge.kills))
    hudScratch.add " D"
    hudScratch.addHudInt(int(pudge.deaths))
    if pudge.hookedBy != 0:
      hudScratch.add "  hooked"
    elif pudge.shieldTicks > 0:
      hudScratch.add "  shield"
    elif pudge.onIslandFountain:
      hudScratch.add "  fountain"
    elif pudge.inRiver:
      hudScratch.add "  pit"
    elif pudge.state == Dying:
      hudScratch.add "  down"
    if spectatePudgeId == pudge.id:
      hudScratch.add "  EYES"
    sk.drawLabel(
      hudScratch,
      inner.origin + vec2(0, y),
      vec2(inner.size.x, 16),
      if spectatePudgeId == pudge.id: ReadyGold else: LabelColor,
      "Small"
    )
    var upgradeX = 0.0'f32
    for kind in UpgradeKind:
      let glyph = vec2(16, 16)
      sk.drawSprite(
        UpgradeIcons[kind],
        inner.origin + vec2(upgradeX, y + 14),
        glyph
      )
      hudScratch.setLen(0)
      hudScratch.addHudInt(int(pudge.upgrades[kind]))
      sk.drawLabel(
        hudScratch,
        inner.origin + vec2(upgradeX + 18, y + 14),
        vec2(48, 16),
        LabelColor,
        "Small"
      )
      upgradeX += 84
    sk.drawBar(
      inner.origin + vec2(0, y + 28),
      vec2(inner.size.x, 8),
      max(pudge.hp, 0).float32,
      max(pudge.maxHp, 1).float32,
      pudgeHpColor(pudge)
    )
    y += 50

proc addHudSeconds(s: var string, ticks: int32) =
  ## Appends remaining ticks as "d.d s".
  let tenths =
    (int(max(ticks, 0)) * 10 + int(TickRate) - 1) div int(TickRate)
  s.addHudInt(tenths div 10)
  s.add '.'
  s.addHudInt(tenths mod 10)
  s.add " s"

proc cooldownSeconds(remaining: int32): int32 =
  ## Rounds remaining ticks up to whole seconds for the HUD.
  (remaining + TickRate - 1) div TickRate

proc hookFlying(hero: Pudge): bool =
  for hook in run.world.hooks:
    if hook.ownerId == hero.id and hook.phase != HookIdle:
      return true
  false

proc cooldownOverlay(remaining, duration: int32, extra = ""): string =
  if extra.len > 0:
    return extra
  if remaining > 0 and duration > 0:
    return $cooldownSeconds(remaining)
  ""

proc wrapTooltipLine(
    sk: Silky,
    font, line: string,
    maxW: float32
): seq[string] =
  ## Word-wraps one HUD line so the shop plate can stay narrow.
  if line.len == 0 or sk.getTextSize(font, line).x <= maxW:
    return @[line]
  var current = ""
  for word in line.split(' '):
    if word.len == 0:
      continue
    let trial = if current.len == 0: word else: current & " " & word
    if current.len > 0 and sk.getTextSize(font, trial).x > maxW:
      result.add current
      current = word
    else:
      current = trial
  if current.len > 0:
    result.add current

proc drawHudTooltip(
    sk: Silky,
    window: Window,
    anchor: GameUiPanel,
    lines: openArray[string]
) =
  ## Floating plate above a well. First line is the gold title.
  ## Sizes to the text so a long ward blurb wraps instead of clipping,
  ## and keeps the whole plate on-screen (shop tips sit to the right
  ## of the panel so chat cannot eat the title).
  if lines.len == 0:
    return
  const
    PadX = 10.0'f32
    PadY = 8.0'f32
    LineH = 18.0'f32
    MaxInner = 360.0'f32
  var
    wrapped: seq[string]
    fonts: seq[string]
  for i, line in lines:
    let font = if i == 0: "Hud" else: "Small"
    for part in sk.wrapTooltipLine(font, line, MaxInner):
      wrapped.add part
      fonts.add font
  var innerW = 0.0'f32
  for i, line in wrapped:
    innerW = max(innerW, sk.getTextSize(fonts[i], line).x)
  let
    view = currentLayout(window).size
    tipW = min(MaxInner, innerW) + PadX * 2
    tipH = PadY * 2 + wrapped.len.float32 * LineH
    maxX = max(4.0'f32, view.x - tipW - 4.0'f32)
    maxY = max(4.0'f32, view.y - tipH - 4.0'f32)
    tipOrigin = vec2(
      clamp(anchor.origin.x, 4.0'f32, maxX),
      clamp(anchor.origin.y - tipH - 6.0'f32, 4.0'f32, maxY)
    )
  sk.drawRect(tipOrigin, vec2(tipW, tipH), rgbx(10, 12, 16, 230))
  for i, line in wrapped:
    sk.drawLabel(
      line,
      tipOrigin + vec2(PadX, PadY + float32(i) * LineH),
      vec2(tipW - PadX * 2, 16),
      if fonts[i] == "Hud": ReadyGold else: LabelColor,
      fonts[i]
    )

proc itemHotkey(item: ShopItem): string =
  case item
  of ShopWall: bindLabel(BindWall)
  of ShopMine: bindLabel(BindMine)
  of ShopWard: bindLabel(BindWard)
  else: ""

proc itemCooldown(hero: Pudge, item: ShopItem): (int32, int32) =
  case item
  of ShopWall: (hero.wallCooldown, wallCooldownTicks(hero.itemRank[item]))
  of ShopMine: (hero.mineCooldown, MineCooldownTicks)
  of ShopWard: (hero.wardCooldown, WardCooldownTicks)
  else: (0'i32, 0'i32)

proc carriedShopItems(hero: Pudge): seq[ShopItem] =
  ## Actives first so wall/mine/ward keep a well when the bag is full.
  for item in [ShopWall, ShopMine, ShopWard, ShopBoots, ShopLongshot]:
    if hero.itemRank[item] > 0:
      result.add item

proc drawBottomUnit(
    sk: Silky,
    window: Window,
    hud: BottomHudLayout,
    inHistory: bool
) =
  ## Fills the Call to Adventure plates: portrait and vitals on the
  ## profile card, abilities/items/upgrades in the action wells.
  let index = inspectIndex()
  if index < 0:
    return
  let
    owned = isOwnedInspect()
    heroIdx = heroIndex()
    hero = run.world.pudges[index]
    portrait = hud.portrait
    ownedLive = owned and not inHistory
    hookRemaining =
      if hero.windupTicks > 0: hero.windupTicks else: hero.hookCooldown
    hookDuration =
      if hero.windupTicks > 0: HookWindupTicks else: HookCooldownTicks
    hookReady = hero.state == Alive and not inHistory and
      hero.windupTicks <= 0 and hero.hookCooldown <= 0 and not hookFlying(hero)
    hookFill =
      if hookRemaining <= 0 or hookDuration <= 0: 1.0'f32
      else: 1.0'f32 - hookRemaining.float32 / hookDuration.float32
    hpColor = pudgeHpColor(hero)
  sk.drawWellImage(portrait, PortraitKeys[hero.team])
  let portraitInner = portrait.inset(
    min(4.0'f32, min(portrait.size.x, portrait.size.y) * 0.08'f32)
  )
  if hero.state == Dying:
    sk.drawRect(portraitInner.origin, portraitInner.size, rgbx(12, 14, 20, 170))
  elif hero.shieldTicks > 0:
    sk.drawRect(portraitInner.origin, portraitInner.size, rgbx(80, 200, 255, 150))
    sk.drawRect(
      portraitInner.origin,
      vec2(portraitInner.size.x, 3),
      rgbx(180, 240, 255, 230)
    )
    sk.drawRect(
      portraitInner.origin + vec2(0, portraitInner.size.y - 3),
      vec2(portraitInner.size.x, 3),
      rgbx(180, 240, 255, 230)
    )

  let
    hookOverlay = cooldownOverlay(
      hookRemaining,
      hookDuration,
      if hero.windupTicks > 0: "CAST"
      elif hookFlying(hero): "AIR"
      else: ""
    )
    blinkReady = hero.state == Alive and not inHistory and
      hero.windupTicks <= 0 and hero.blinkCooldown <= 0 and
      hero.hookedBy == 0 and not run.world.rotAffected(hero)
  var actionSpecs: array[ActionSlotCount, CommandSlotSpec]
  for i in 0 ..< ActionSlotCount:
    actionSpecs[i] = CommandSlotSpec(id: -1)
  actionSpecs[0] = CommandSlotSpec(
    id: CmdAttack, icon: AttackIcon,
    hotkey: if owned: "RMB" else: "",
    enabled: ownedLive or not owned,
    remaining: if owned: hero.swingTicks else: 0,
    duration: hero.attackPeriod,
    overlay: if owned: cooldownOverlay(hero.swingTicks, hero.attackPeriod) else: ""
  )
  actionSpecs[1] = CommandSlotSpec(
    id: CmdHook, icon: "hook",
    hotkey: if owned: bindLabel(BindHook) else: "",
    enabled: (ownedLive and hookReady) or not owned,
    remaining: if owned: hookRemaining else: 0,
    duration: hookDuration,
    overlay: if owned: hookOverlay else: "",
    autocast: owned and options.autocast
  )
  actionSpecs[2] = CommandSlotSpec(
    id: CmdRot, icon: "rot",
    hotkey: if owned: bindLabel(BindRot) else: "",
    enabled: ownedLive or not owned,
    overlay: if owned and hero.rotOn: "ON" else: ""
  )
  actionSpecs[3] = CommandSlotSpec(
    id: CmdBlink, icon: "blink",
    hotkey: if owned: bindLabel(BindBlink) else: "",
    enabled: (ownedLive and blinkReady) or not owned,
    remaining: if owned: hero.blinkCooldown else: 0,
    duration: BlinkCooldownTicks,
    overlay:
      if owned: cooldownOverlay(hero.blinkCooldown, BlinkCooldownTicks)
      else: ""
  )
  let carried = hero.carriedShopItems
  var itemWells: array[2, ShopItem]
  var itemWellCount = 0
  for item in carried:
    if itemWellCount >= 2:
      break
    let (remaining, duration) = hero.itemCooldown(item)
    actionSpecs[4 + itemWellCount] = CommandSlotSpec(
      id: item.ord,
      icon: ShopItemIcons[item],
      hotkey: if owned: itemHotkey(item) else: "",
      enabled: ownedLive or not owned,
      remaining: if owned: remaining else: 0,
      duration: duration,
      overlay: if owned: cooldownOverlay(remaining, duration) else: "",
      badge: $hero.itemRank[item]
    )
    itemWells[itemWellCount] = item
    inc itemWellCount
  for kind in UpgradeKind:
    let
      level = hero.upgrades[kind]
      affordable = ownedLive and hero.points > 0 and level < MaxUpgradeLevel
    actionSpecs[6 + ord(kind)] = CommandSlotSpec(
      id: 100 + kind.ord,
      icon: UpgradeIcons[kind],
      hotkey: if owned: bindLabel(BindAction(ord(BindUpgrade1) + ord(kind))) else: "",
      enabled: (owned and (affordable or level > 0)) or not owned,
      overlay: if level >= MaxUpgradeLevel: "MAX" else: "",
      badge: if level >= MaxUpgradeLevel or level == 0: "" else: $level
    )

  for i in 0 ..< ActionSlotCount:
    let well = hud.actions.actionWell(i)
    if actionSpecs[i].icon.len > 0:
      sk.drawSlotIcon(well, actionSpecs[i])
    else:
      sk.fillWell(well)

  if hero.state == Dying:
    hudScratch.setLen(0)
    hudScratch.addHudSeconds(hero.deathTicks)
    sk.drawLabel(
      hudScratch, portrait.origin, portrait.size, ReadyGold, "Small", CenterAlign
    )
  elif hero.shieldTicks > 0:
    let
      plateSize = vec2(portrait.size.x - 8, 16)
      plateOrigin = portrait.origin + vec2(4, 4)
    sk.drawRect(plateOrigin, plateSize, rgbx(8, 18, 28, 210))
    hudScratch.setLen(0)
    hudScratch.add "INVULN "
    hudScratch.addHudSeconds(hero.shieldTicks)
    sk.drawLabel(
      hudScratch, plateOrigin, plateSize,
      ShieldHpColor, "Small", CenterAlign
    )
  if hero.state != Dying and hero.buffTicks > 0:
    let
      plateSize = vec2(portrait.size.x - 8, 14)
      plateOrigin = portrait.origin + vec2(4, portrait.size.y - 18)
    sk.drawRect(plateOrigin, plateSize, rgbx(10, 12, 16, 190))
    hudScratch.setLen(0)
    hudScratch.add RuneHudNames[hero.buffKind]
    hudScratch.add " "
    hudScratch.addHudSeconds(hero.buffTicks)
    sk.drawLabel(
      hudScratch, plateOrigin, plateSize,
      RuneColors[hero.buffKind], "Small", CenterAlign
    )

  sk.drawBar(
    hud.hpBar.origin,
    hud.hpBar.size,
    max(hero.hp, 0).float32,
    max(hero.maxHp, 1).float32,
    hpColor
  )
  sk.drawSprite("health", hud.hpBar.origin + vec2(2, 2), vec2(16), hpColor)
  hudScratch.setLen(0)
  hudScratch.add butcherDisplayName(index)
  if not owned:
    if spectatePudgeId == hero.id:
      hudScratch.add "  EYES"
    elif heroIdx >= 0 and hero.team == run.world.pudges[heroIdx].team:
      hudScratch.add "  ALLY"
    elif heroIdx >= 0:
      hudScratch.add "  ENEMY"
  sk.drawLabel(
    hudScratch,
    hud.hpBar.origin + vec2(20, 0),
    vec2(hud.hpBar.size.x - 78, hud.hpBar.size.y),
    HudName,
    "Small"
  )
  hudScratch.setLen(0)
  hudScratch.add "Lv "
  hudScratch.addHudInt(int(hero.kills) + 1)
  sk.drawLabel(
    hudScratch,
    hud.hpBar.origin + vec2(hud.hpBar.size.x - 54, 0),
    vec2(52, hud.hpBar.size.y),
    HudMuted,
    "Small",
    RightAlign
  )

  var hookCaption = ""
  if inHistory:
    hookCaption.add "SPECTATING THE PAST"
  elif owned and aimingHookNow():
    hookCaption.add "HOOK - CLICK GROUND"
  elif owned and aimingBlinkNow():
    hookCaption.add "BLINK - LAST LEGAL TILE"
  elif hero.windupTicks > 0:
    hookCaption.add "CASTING"
  elif hookFlying(hero):
    hookCaption.add "IN FLIGHT"
  elif hookReady:
    hookCaption.add "READY"
    if owned and options.quickcast:
      hookCaption.add " - QC"
    if owned and options.autocast:
      hookCaption.add " - AC"
  elif hookRemaining > 0:
    hookCaption.addHudInt(int(cooldownSeconds(hookRemaining)))
    hookCaption.add " s"
  else:
    hookCaption.add "HOOK"
  sk.drawBar(
    hud.resourceBar.origin,
    hud.resourceBar.size,
    hookFill,
    1.0'f32,
    HookBarColor
  )
  sk.drawSprite(
    "mana",
    hud.resourceBar.origin + vec2(2, 4),
    vec2(16),
    rgbx(186, 214, 255, 255)
  )
  sk.drawLabel(
    hookCaption,
    hud.resourceBar.origin + vec2(20, 0),
    vec2(hud.resourceBar.size.x - 24, hud.resourceBar.size.y),
    rgbx(255, 255, 255, 255),
    "Small",
    CenterAlign
  )

  writeRatio(hudScratch, max(hero.hp, 0).int, int(hero.maxHp))
  sk.drawValueBar(
    hud.xpBar.origin,
    hud.xpBar.size,
    max(hero.hp, 0).float32,
    max(hero.maxHp, 1).float32,
    hpColor,
    hudScratch
  )
  sk.drawSprite("health", hud.xpBar.origin + vec2(2, 1), vec2(18), hpColor)
  hudScratch.setLen(0)
  hudScratch.add "KO "
  hudScratch.addHudInt(int(hero.kills))
  sk.drawLabel(
    hudScratch,
    hud.xpBar.origin + vec2(hud.xpBar.size.x - 88, 0),
    vec2(84, hud.xpBar.size.y),
    ReadyGold,
    "Small",
    RightAlign
  )

  sk.drawSprite("gold", hud.goldBox.origin + vec2(0, -2), vec2(22))
  writeAmount(hudScratch, int(hero.gold))
  sk.drawLabel(
    hudScratch,
    hud.goldBox.origin + vec2(22, 0),
    vec2(hud.goldBox.size.x - 22, hud.goldBox.size.y),
    ReadyGold,
    "Small"
  )
  sk.drawSprite("essence", hud.gemBox.origin + vec2(-2, -2), vec2(22))
  writeInt(hudScratch, int(hero.points))
  sk.drawLabel(
    hudScratch,
    hud.gemBox.origin + vec2(20, 0),
    vec2(hud.gemBox.size.x - 20, hud.gemBox.size.y),
    rgbx(220, 168, 255, 255),
    "Small"
  )

  for i in 0 ..< ActionSlotCount:
    if actionSpecs[i].icon.len == 0:
      continue
    sk.drawSlotLabels(hud.actions.actionWell(i), actionSpecs[i])

  if owned:
    for i in 0 ..< ActionSlotCount:
      let spec = actionSpecs[i]
      if spec.id < 0 or not spec.enabled:
        continue
      if not window.clicked(sk, hud.actions.actionWell(i)):
        continue
      case spec.id
      of CmdAttack: beginAttackCommand()
      of CmdHook: beginHookCommand()
      of CmdRot: beginRotCommand()
      of CmdBlink: beginBlinkCommand()
      of 100 .. 103:
        issueBuyCommand(UpgradeKind(spec.id - 100))
      else:
        if spec.id == ShopWall.ord:
          beginPlaceCommand(ShopWall)
        elif spec.id == ShopMine.ord:
          beginPlaceCommand(ShopMine)
        elif spec.id == ShopWard.ord:
          beginPlaceCommand(ShopWard)

    if window.buttonPressed[MouseRight]:
      let hookWell = hud.actions.actionWell(1)
      if hookWell.contains(sk.mousePos):
        toggleHookAutocast()

    let (errText, errAlpha) = humanErrorLine()
    if errText.len > 0:
      sk.drawLabel(
        errText,
        vec2(hud.bar.origin.x, hud.bar.origin.y - 16),
        vec2(hud.bar.size.x, 16),
        rgbx(245, 80, 85, uint8(errAlpha * 255)),
        "Hud",
        CenterAlign
      )

  block actionTooltip:
    var hovered = -1
    var well = hud.bar
    for i in 0 ..< ActionSlotCount:
      if actionSpecs[i].icon.len == 0:
        continue
      let slot = hud.actions.actionWell(i)
      if slot.contains(sk.mousePos):
        hovered = i
        well = slot
        break
    if hovered < 0:
      break actionTooltip
    case hovered
    of 0:
      sk.drawHudTooltip(
        window, well, attackTooltipLines(hero.meleeDamage, hero.attackPeriod)
      )
    of 1:
      sk.drawHudTooltip(
        window,
        well,
        hookTooltipLines(
          thrownHookDamage(
            hero.upgrades[UpgradeDamage],
            hero.hasBuff(RuneBigHook),
            hero.hasBuff(RuneDoubleDamage)
          ),
          thrownHookRange(
            hero.upgrades[UpgradeDistance],
            hero.hasBuff(RuneBigHook)
          ),
          hero.itemRank[ShopLongshot],
          options.quickcast,
          hero.hasBuff(RuneBigHook),
          hero.hasBuff(RuneDoubleDamage),
          hero.hasBuff(RuneLightning),
          bindLabel(BindHook)
        )
      )
    of 2:
      sk.drawHudTooltip(
        window, well, rotTooltipLines(hero.rotOn, bindLabel(BindRot))
      )
    of 3:
      sk.drawHudTooltip(
        window, well, blinkTooltipLines(bindLabel(BindBlink))
      )
    of 4, 5:
      let itemIdx = hovered - 4
      if itemIdx < itemWellCount:
        sk.drawHudTooltip(
          window,
          well,
          shopItemTooltipLines(
            itemWells[itemIdx],
            hero.itemRank[itemWells[itemIdx]],
            bindLabel(BindWall),
            bindLabel(BindMine),
            bindLabel(BindWard)
          )
        )
    of 6, 7, 8, 9:
      let kind = UpgradeKind(hovered - 6)
      sk.drawHudTooltip(
        window, well, upgradeTooltipLines(kind, hero.upgrades[kind])
      )
    else:
      discard

proc canBuyShopRow(hero: Pudge, item: ShopItem): bool =
  if hero.gold < shopPrice(item):
    return false
  if not item.isPermanent:
    if item == ShopFlask:
      return hero.hp < hero.maxHp
    return true
  if hero.itemRank[item] >= ItemMaxRank:
    return false
  if hero.itemRank[item] == 0 and hero.ownedPermanents >= InventorySlots:
    return false
  true

proc drawShopPanel(sk: Silky, window: Window, layout: GameUiLayout) =
  ## Icon shop while standing on the team's pad. Permanents fill the
  ## HUD inventory; 5-9 still buy the timed powerups.
  if not heroWantsShop():
    return
  let
    hero = run.world.pudges[heroIndex()]
    live = humanControlActive() and not run.replayMode and
      hero.state == Alive
    panel = shopPanelOf(layout)
  sk.drawPanel(panel)
  sk.drawFrame(panel.inset(2))
  sk.drawLabel(
    "BASE SHOP",
    panel.origin + vec2(10, 8),
    vec2(160, 18),
    ReadyGold,
    "Hud"
  )
  hudScratch.setLen(0)
  hudScratch.add "G "
  hudScratch.addHudInt(int(hero.gold))
  sk.drawLabel(
    hudScratch,
    panel.origin + vec2(panel.size.x - 90, 8),
    vec2(80, 18),
    ReadyGold,
    "Hud",
    RightAlign
  )
  let
    grid = GameUiPanel(
      origin: panel.origin + vec2(8, 30),
      size: vec2(panel.size.x - 16, 92)
    )
  var permanents: seq[CommandSlotSpec]
  for item in ShopBoots..ShopWard:
    let rank = hero.itemRank[item]
    permanents.add CommandSlotSpec(
      id: item.ord,
      icon: ShopItemIcons[item],
      enabled: live and hero.canBuyShopRow(item),
      badge: if rank > 0: $rank else: "",
      overlay: ""
    )
  let clickedPerm = sk.drawCommandGrid(
    window, grid, permanents, PermanentShopCols, PermanentShopRows
  )
  if clickedPerm >= ShopBoots.ord and clickedPerm <= ShopWard.ord:
    issueBuyPower(ShopItem(clickedPerm))
  block shopTip:
    var hovered = ShopFlask
    var found = false
    var well = grid
    var i = 0
    for item in ShopBoots..ShopWard:
      let
        col = i mod PermanentShopCols
        row = i div PermanentShopCols
        slot = grid.gridSlot(
          col, row, PermanentShopCols, PermanentShopRows
        )
      if slot.contains(sk.mousePos):
        hovered = item
        well = slot
        found = true
        break
      inc i
    if found:
      var lines = shopItemTooltipLines(
        hovered,
        hero.itemRank[hovered],
        bindLabel(BindWall),
        bindLabel(BindMine),
        bindLabel(BindWard)
      )
      lines[0] = lines[0] & " - " & $shopPrice(hovered) & "g"
      sk.drawHudTooltip(
        window,
        GameUiPanel(
          origin: vec2(
            panel.origin.x + panel.size.x + 8.0'f32,
            well.origin.y
          ),
          size: well.size
        ),
        lines
      )
  sk.drawLabel(
    "POWERUPS",
    panel.origin + vec2(10, 144),
    vec2(200, 16),
    ReadyGold,
    "Small"
  )
  const Powerups = [
    ShopFlask, ShopHaste, ShopRegen, ShopBigHook, ShopDoubleDamage
  ]
  const PowerKeys = ["5", "6", "7", "8", "9"]
  var
    hoveredPower = ShopFlask
    foundPower = false
    hoveredRow = GameUiPanel()
  for i, item in Powerups:
    let
      row = GameUiPanel(
        origin: panel.origin + vec2(8, 164 + float32(i) * 26),
        size: vec2(panel.size.x - 16, 24)
      )
      afford = live and hero.canBuyShopRow(item)
    sk.drawRect(
      row.origin, row.size,
      if afford: rgbx(24, 28, 36, 220) else: rgbx(16, 18, 24, 220)
    )
    let label = "[" & PowerKeys[i] & "]  " & ShopItemNames[item] &
      "  " & $shopPrice(item) & "g"
    sk.drawLabel(
      label,
      row.origin + vec2(6, 3),
      vec2(row.size.x - 12, 18),
      if afford: rgbx(226, 232, 240, 255) else: rgbx(120, 128, 144, 255),
      "Small"
    )
    if live and window.clicked(sk, row):
      issueBuyPower(item)
    if row.contains(sk.mousePos):
      hoveredPower = item
      foundPower = true
      hoveredRow = row
  if foundPower:
    var lines = shopItemTooltipLines(hoveredPower, 0)
    lines[0] = lines[0] & " - " & $shopPrice(hoveredPower) & "g"
    sk.drawHudTooltip(
      window,
      GameUiPanel(
        origin: vec2(
          panel.origin.x + panel.size.x + 8.0'f32,
          hoveredRow.origin.y
        ),
        size: hoveredRow.size
      ),
      lines
    )

proc drawNetBanner*(sk: Silky, window: Window, text: string) =
  ## One urgent center-screen line: desync, connection loss, reconnect.
  if text.len == 0:
    return
  let reconnecting = text.startsWith("RECONNECT")
  let layout = currentLayout(window)
  sk.drawRect(
    vec2(0, layout.size.y * 0.30'f32 - 8),
    vec2(layout.size.x, 46),
    if reconnecting: rgbx(20, 18, 8, 200) else: rgbx(20, 8, 10, 200)
  )
  sk.drawLabel(
    text,
    vec2(0, layout.size.y * 0.30'f32),
    vec2(layout.size.x, 30),
    if reconnecting: rgbx(255, 214, 120, 255) else: rgbx(245, 80, 85, 255),
    "H1",
    CenterAlign
  )

proc drawNetLobby*(
    sk: Silky,
    window: Window,
    seats: seq[NetSeat],
    url: string,
    localClaim: int
) =
  ## The host's pre-match lobby overlay: who joined, where friends
  ## point their browsers, and the start controls.
  let
    layout = currentLayout(window)
    panel = layout.panel(
      GameUiRegion.Center,
      vec2(600, max(280.0'f32, 140.0'f32 + float32(seats.len) * 30.0'f32))
    )
  sk.drawRect(vec2(0, 0), layout.size, rgbx(6, 8, 12, 170))
  let inner = sk.beginPanel(panel, ReadyGold)
  sk.drawLabel(
    "MATCH LOBBY  " & $(max(seats.len div 2, 1)) & "v" &
      $(max(seats.len div 2, 1)),
    inner.origin,
    vec2(inner.size.x, 30),
    ReadyGold,
    "H1",
    CenterAlign
  )
  sk.drawLabel(
    "-/+ TEAM SIZE   SHIFT+1-0 TOGGLES A SEAT   FRIENDS JOIN AT",
    inner.origin + vec2(0, 42),
    vec2(inner.size.x, 16),
    LabelColor,
    "Small",
    CenterAlign
  )
  sk.drawLabel(
    url,
    inner.origin + vec2(0, 60),
    vec2(inner.size.x, 22),
    rgbx(120, 200, 255, 255),
    "Hud",
    CenterAlign
  )
  let n = max(seats.len div 2, 1)
  var y = 100.0'f32
  for i in 0 ..< seats.len:
    let
      team = if i < n: WestTeam else: EastTeam
      teamColor = if team == WestTeam: WestColor else: EastColor
      mine = i == localClaim
      seat =
        if i < seats.len: seats[i]
        else: NetSeat()
    hudScratch.setLen(0)
    hudScratch.add "["
    if i >= 9:
      hudScratch.add "0"
    else:
      hudScratch.addHudInt(i + 1)
    hudScratch.add "]  "
    hudScratch.add(if team == WestTeam: "WEST  " else: "EAST  ")
    if seat.off:
      hudScratch.add "SEAT OFF"
    elif seat.human:
      hudScratch.add seat.name
      if not seat.connected:
        hudScratch.add "  (away)"
    else:
      if seat.name.len > 0:
        hudScratch.add seat.name
      else:
        hudScratch.add "Butcher Bot"
    sk.drawLabel(
      hudScratch,
      inner.origin + vec2(60, y),
      vec2(60, 18),
      teamColor,
      "Hud"
    )
    sk.drawLabel(
      if seat.off: "OFF"
      elif mine: "YOU"
      elif seat.human: "HUMAN"
      else: "BOT",
      inner.origin + vec2(inner.size.x - 130, y),
      vec2(70, 18),
      if mine: ReadyGold
      elif seat.human: rgbx(120, 220, 130, 255)
      else: rgbx(120, 128, 144, 255),
      "Hud",
      RightAlign
    )
    y += 30
  sk.drawLabel(
    "1-0 TAKE A SEAT      0 SPECTATE WHEN N<5      ENTER START",
    inner.origin + vec2(0, inner.size.y - 46),
    vec2(inner.size.x, 18),
    LabelColor,
    "Hud",
    CenterAlign
  )
  sk.drawLabel(
    "browser lobby has chat - anyone with the link can join",
    inner.origin + vec2(0, inner.size.y - 22),
    vec2(inner.size.x, 16),
    rgbx(150, 156, 170, 255),
    "Small",
    CenterAlign
  )

proc applyMenuChoice(id: int, transport: var Player) =
  ## Runs one pause-menu row: close the plate, then resume, rematch, or
  ## hand off to Controls / Allies / Chat / Replay / Debug.
  case id
  of MenuResume:
    menuOpen = false
    controlsOpen = false
    transport.playing = true
  of MenuRestart:
    if not menuCanRestart():
      return
    menuOpen = false
    controlsOpen = false
    alliesOpen = false
    cancelChatTyping()
    menuRestartRequested = true
    transport.playing = true
  of MenuControls:
    controlsOpen = true
    menuCursor = 0
  of MenuAllies:
    menuOpen = false
    controlsOpen = false
    alliesOpen = true
    transport.playing = true
  of MenuLog:
    menuOpen = false
    controlsOpen = false
    chatVisible = true
    chatTab = ChatTabChat
    alliesOpen = false
    transport.playing = true
  of MenuReplay:
    menuOpen = false
    controlsOpen = false
    transport.playing = true
    toggleTransportBar()
  of MenuDebug:
    menuOpen = false
    controlsOpen = false
    transport.playing = true
    toggleDebugMenu()
  else:
    discard

proc drawMenuOverlay(
    sk: Silky,
    window: Window,
    layout: GameUiLayout,
    transport: var Player
) =
  ## Pause plate: one gold-border button per row, mouse and keyboard.
  const
    Labels = [
      "Resume", "Restart Game", "Controls", "Allies", "Chat", "Replay", "Debug"
    ]
    NumberKeys = [Key1, Key2, Key3, Key4, Key5, Key6, Key7]
  sk.drawRect(vec2(0, 0), layout.size, rgbx(6, 8, 12, 170))
  let inner = sk.beginPanel(
    layout.panel(GameUiRegion.Center, MenuPanelSize),
    ReadyGold
  )
  sk.drawLabel(
    "MENU",
    inner.origin,
    vec2(inner.size.x, 28),
    ReadyGold,
    "H1",
    CenterAlign
  )
  sk.drawLabel(
    "PAUSED",
    inner.origin + vec2(0, 32),
    vec2(inner.size.x, 20),
    LabelColor,
    "Hud",
    CenterAlign
  )
  var chosen = -1
  for i in 0 ..< MenuItemCount:
    let
      slot = GameUiPanel(
        origin: inner.origin + vec2(
          0,
          64.0'f32 + float32(i) * (MenuButtonH + MenuButtonGap)
        ),
        size: vec2(inner.size.x, MenuButtonH)
      )
      hovered = slot.contains(sk.mousePos)
      enabled = i != MenuRestart or menuCanRestart()
    if hovered:
      menuCursor = i
    let selected = menuCursor == i
    sk.drawEtched(
      slot.origin,
      slot.size,
      if selected: HudChipActive else: HudChipFill
    )
    let labelColor =
      if not enabled: rgbx(120, 128, 144, 255)
      elif selected: ReadyGold
      else: LabelColor
    sk.drawLabel(
      Labels[i],
      slot.origin + vec2(14, 0),
      vec2(slot.size.x - 52, slot.size.y),
      labelColor,
      "Hud"
    )
    hudScratch.setLen(0)
    hudScratch.add '('
    hudScratch.add $(i + 1)
    hudScratch.add ')'
    sk.drawLabel(
      hudScratch,
      slot.origin + vec2(slot.size.x - 42, 0),
      vec2(34, slot.size.y),
      if enabled: HudHotkey else: rgbx(96, 104, 112, 255),
      "Small",
      CenterAlign
    )
    if enabled and (window.clicked(sk, slot) or
        window.buttonPressed[NumberKeys[i]]):
      chosen = i
  if window.buttonPressed[KeyUp]:
    menuCursor = (menuCursor + MenuItemCount - 1) mod MenuItemCount
  elif window.buttonPressed[KeyDown]:
    menuCursor = (menuCursor + 1) mod MenuItemCount
  if window.buttonPressed[KeyEscape]:
    chosen = MenuResume
  elif chosen < 0 and window.buttonPressed[KeyEnter]:
    chosen = menuCursor
  if chosen >= 0:
    applyMenuChoice(chosen, transport)
  elif menuOpen:
    transport.playing = false

proc controlToggleLabel(on: bool): string =
  if on: "ON" else: "OFF"

proc drawControlsOverlay(
    sk: Silky,
    window: Window,
    layout: GameUiLayout,
    transport: var Player
) =
  ## Pause-menu Controls page: quickcast and Meat Hook autocast.
  const NumberKeys = [Key1, Key2, Key3]
  sk.drawRect(vec2(0, 0), layout.size, rgbx(6, 8, 12, 170))
  let inner = sk.beginPanel(
    layout.panel(GameUiRegion.Center, ControlsPanelSize),
    ReadyGold
  )
  sk.drawLabel(
    "CONTROLS",
    inner.origin,
    vec2(inner.size.x, 28),
    ReadyGold,
    "H1",
    CenterAlign
  )
  sk.drawLabel(
    "PAUSED",
    inner.origin + vec2(0, 32),
    vec2(inner.size.x, 20),
    LabelColor,
    "Hud",
    CenterAlign
  )
  let
    labels = [
      "Back",
      "Quickcast",
      "Autocast Hook"
    ]
    hints = [
      "",
      "Abilities fire at the cursor on key press.",
      "Right-click an enemy to hook. Right-click the Hook well to toggle."
    ]
    values = [
      "",
      controlToggleLabel(options.quickcast),
      controlToggleLabel(options.autocast)
    ]
  var chosen = -1
  for i in 0 ..< ControlsItemCount:
    let
      slot = GameUiPanel(
        origin: inner.origin + vec2(
          0,
          64.0'f32 + float32(i) * (MenuButtonH + MenuButtonGap)
        ),
        size: vec2(inner.size.x, MenuButtonH)
      )
      hovered = slot.contains(sk.mousePos)
    if hovered:
      menuCursor = i
    let selected = menuCursor == i
    sk.drawEtched(
      slot.origin,
      slot.size,
      if selected: HudChipActive else: HudChipFill
    )
    sk.drawLabel(
      labels[i],
      slot.origin + vec2(14, 0),
      vec2(slot.size.x - 110, slot.size.y),
      if selected: ReadyGold else: LabelColor,
      "Hud"
    )
    if values[i].len > 0:
      sk.drawLabel(
        values[i],
        slot.origin + vec2(slot.size.x - 86, 0),
        vec2(44, slot.size.y),
        if values[i] == "ON": HudHotkey else: HudMuted,
        "Hud",
        CenterAlign
      )
    hudScratch.setLen(0)
    hudScratch.add '('
    hudScratch.add $(i + 1)
    hudScratch.add ')'
    sk.drawLabel(
      hudScratch,
      slot.origin + vec2(slot.size.x - 42, 0),
      vec2(34, slot.size.y),
      HudHotkey,
      "Small",
      CenterAlign
    )
    if window.clicked(sk, slot) or window.buttonPressed[NumberKeys[i]]:
      chosen = i
  sk.drawLabel(
    hints[clamp(menuCursor, 0, hints.high)],
    inner.origin + vec2(8, inner.size.y - 36),
    vec2(inner.size.x - 16, 28),
    rgbx(150, 156, 170, 255),
    "Small",
    CenterAlign
  )
  if window.buttonPressed[KeyUp]:
    menuCursor = (menuCursor + ControlsItemCount - 1) mod ControlsItemCount
  elif window.buttonPressed[KeyDown]:
    menuCursor = (menuCursor + 1) mod ControlsItemCount
  if window.buttonPressed[KeyEscape]:
    chosen = ControlsBack
  elif chosen < 0 and window.buttonPressed[KeyEnter]:
    chosen = menuCursor
  case chosen
  of ControlsBack:
    controlsOpen = false
    menuCursor = MenuControls
  of ControlsQuickcast:
    options.quickcast = not options.quickcast
  of ControlsAutocast:
    toggleHookAutocast()
  else:
    discard
  transport.playing = false

proc chatLineColor(line: MatchChatLine): ColorRGBX =
  if line.team == int32(WestTeam.ord): WestColor
  elif line.team == int32(EastTeam.ord): EastColor
  else: ReadyGold

proc chatSelfName(): string =
  if humanControlActive() and heroIndex() >= 0:
    return "P" & $run.world.pudges[heroIndex()].id
  let name = netPlayerName()
  if name.len > 0: name else: "You"

proc chatSelfTeam(): int32 =
  if humanControlActive() and heroIndex() >= 0:
    int32(run.world.pudges[heroIndex()].team.ord)
  else:
    -1

proc sendChatDraft() =
  let text = strip(chatDraft)
  chatDraft.setLen(0)
  if text.len == 0 or run == nil:
    return
  let slot =
    if humanControlActive() and heroIndex() >= 0: int32(heroIndex())
    else: -1
  run.appendChat(MatchChatLine(
    tick: run.world.tick,
    slot: slot,
    name: chatSelfName(),
    text: text,
    team: chatSelfTeam()
  ))

proc chatInputPanel(panel: GameUiPanel): GameUiPanel =
  GameUiPanel(
    origin: panel.origin + vec2(6, panel.size.y - ChatInputH - 6),
    size: vec2(panel.size.x - 12, ChatInputH)
  )

proc logTabPanel(panel: GameUiPanel, index: int): GameUiPanel =
  GameUiPanel(
    origin: panel.origin + vec2(6 + float32(index) * (ChatTabW + 4), 4),
    size: vec2(ChatTabW, ChatTitleH)
  )

proc handleLogTabs(sk: Silky, window: Window, panel: GameUiPanel) =
  ## CHAT / EVENTS tabs. Clicking Events drops an unfinished draft.
  if not chatVisible:
    return
  if window.clicked(sk, logTabPanel(panel, 0)):
    chatTab = ChatTabChat
  elif window.clicked(sk, logTabPanel(panel, 1)):
    chatTab = ChatTabEvents
    cancelChatTyping()

proc handleChatInput(
    sk: Silky, window: Window, panel: GameUiPanel
) =
  ## Enter opens or sends; Escape cancels; runes type into the draft.
  if menuOpen or controlsOpen or not chatInputEnabled:
    cancelChatTyping()
    return
  let
    onChat = chatTab == ChatTabChat
    input = chatInputPanel(panel)
  if window.buttonPressed[MouseLeft]:
    if chatVisible and onChat and input.contains(sk.mousePos):
      chatComposing = true
      chatVisible = true
    elif chatComposing and (not chatVisible or not panel.contains(sk.mousePos)):
      chatComposing = false
  if window.buttonPressed[KeyEscape] and chatComposing:
    cancelChatTyping()
    return
  if window.buttonPressed[KeyEnter]:
    if chatComposing:
      sendChatDraft()
      chatComposing = false
    else:
      chatVisible = true
      chatTab = ChatTabChat
      chatComposing = true
    return
  if not chatComposing:
    return
  if window.buttonPressed[KeyBackspace] or window.buttonPressed[KeyDelete]:
    let runes = chatDraft.toRunes
    if runes.len > 0:
      chatDraft = $runes[0 ..< runes.high]
  for rune in sk.inputRunes:
    if int(rune) < 32:
      continue
    if chatDraft.toRunes.len >= MaxChatDraft:
      break
    chatDraft.add $rune

proc drawLogTabs(sk: Silky, panel: GameUiPanel) =
  const Labels = ["CHAT", "EVENTS"]
  for i, label in Labels:
    let
      slot = logTabPanel(panel, i)
      active =
        (i == 0 and chatTab == ChatTabChat) or
        (i == 1 and chatTab == ChatTabEvents)
    sk.drawEtched(
      slot.origin,
      slot.size,
      if active: HudChipActive else: HudChipFill
    )
    sk.drawLabel(
      label,
      slot.origin,
      slot.size,
      if active: ReadyGold else: HudMuted,
      "Small",
      CenterAlign
    )
  sk.drawLabel(
    "F11",
    panel.origin + vec2(panel.size.x - 40, 4),
    vec2(32, ChatTitleH),
    rgbx(150, 156, 170, 255),
    "Small",
    RightAlign
  )

proc drawEventLogBody(sk: Silky, panel: GameUiPanel, bodyTop, bodyBot: float32) =
  var y = bodyBot - ChatLineH
  if eventLog.len == 0:
    sk.drawLabel(
      "no events yet",
      vec2(panel.origin.x + 8, y),
      vec2(panel.size.x - 16, ChatLineH),
      rgbx(150, 156, 170, 255),
      "Small"
    )
    return
  for i in countdown(eventLog.high, 0):
    if y < bodyTop:
      break
    let entry = eventLog[i]
    let seconds = int(entry.tick div TickRate)
    var row = ""
    writeClock(row, seconds div 60, seconds mod 60)
    row.add "  "
    row.add entry.text
    sk.drawLabel(
      row,
      vec2(panel.origin.x + 8, y),
      vec2(panel.size.x - 16, ChatLineH),
      entry.color,
      "Small"
    )
    y -= ChatLineH

proc drawChatLogBody(sk: Silky, panel: GameUiPanel, bodyTop, bodyBot: float32) =
  var y = bodyBot - ChatLineH
  if run == nil or run.chatLog.len == 0:
    sk.drawLabel(
      "type to talk",
      vec2(panel.origin.x + 8, y),
      vec2(panel.size.x - 16, ChatLineH),
      rgbx(150, 156, 170, 255),
      "Small"
    )
    return
  for i in countdown(run.chatLog.high, 0):
    if y < bodyTop:
      break
    let line = run.chatLog[i]
    var row = line.name
    if row.len > 0:
      row.add ": "
    row.add line.text
    sk.drawLabel(
      row,
      vec2(panel.origin.x + 8, y),
      vec2(panel.size.x - 16, ChatLineH),
      chatLineColor(line),
      "Small"
    )
    y -= ChatLineH

proc drawChatPanel(sk: Silky, window: Window, layout: GameUiLayout) =
  ## Bottom-left plate with Chat and Events tabs.
  if menuOpen:
    cancelChatTyping()
    return
  let panel = chatPanelOf(layout)
  handleLogTabs(sk, window, panel)
  handleChatInput(sk, window, panel)
  if not chatVisible:
    return
  sk.drawPanel(panel)
  sk.drawFrame(panel.inset(2))
  sk.drawLogTabs(panel)
  let bodyTop = panel.origin.y + ChatTitleH + 8
  if chatTab == ChatTabEvents:
    drawEventLogBody(
      sk, panel, bodyTop, panel.origin.y + panel.size.y - 8
    )
    return
  let input = chatInputPanel(panel)
  drawChatLogBody(sk, panel, bodyTop, input.origin.y - 4)
  sk.drawRect(input.origin, input.size, rgbx(10, 12, 16, 255))
  let prompt =
    if chatComposing:
      if chatDraft.len > 0: chatDraft & "|"
      else: "|"
    else:
      "ENTER TO CHAT"
  sk.drawLabel(
    prompt,
    input.origin + vec2(6, 0),
    vec2(input.size.x - 12, input.size.y),
    if chatComposing: HudName else: rgbx(150, 156, 170, 255),
    "Small"
  )

proc applyChipClick(id: int, transport: var Player) =
  ## Toggles the overlay that matches one minimap chip.
  case id
  of ChipMenu:
    menuOpen = not menuOpen
    if menuOpen:
      menuCursor = 0
      controlsOpen = false
      cancelChatTyping()
    else:
      controlsOpen = false
    transport.playing = not menuOpen
  of ChipTeam:
    alliesOpen = not alliesOpen
  of ChipLog:
    chatVisible = not chatVisible
    if not chatVisible:
      cancelChatTyping()
    if menuOpen:
      menuOpen = false
      transport.playing = true
  of ChipReplay:
    toggleTransportBar()
  of ChipDebug:
    toggleDebugMenu()
  else:
    discard

proc drawDebugLegendSwatch(
    sk: Silky, origin: Vec2, color: ColorRGBX, label: string
) =
  sk.drawRect(origin, vec2(10, 10), color)
  sk.drawLabel(
    label, origin + vec2(14, -2), vec2(140, 14), LabelColor, "Small"
  )

proc drawDebugOverlaysHud(sk: Silky, layout: GameUiLayout) =
  ## Layer color key plus the play-viewport outline.
  if showCamera:
    let play = layout.worldPanel
    let rim = rgbx(240, 218, 128, 220)
    sk.drawRect(play.origin, vec2(play.size.x, 2), rim)
    sk.drawRect(
      play.origin + vec2(0, play.size.y - 2), vec2(play.size.x, 2), rim
    )
    sk.drawRect(play.origin, vec2(2, play.size.y), rim)
    sk.drawRect(
      play.origin + vec2(play.size.x - 2, 0), vec2(2, play.size.y), rim
    )
  if not showLayers:
    return
  # Bottom-left corner: sit above the match chat and away from the minimap.
  var y = layout.size.y - 220
  if chatVisible:
    y = min(y, chatPanelOf(layout).origin.y - 128)
  let x = 16.0'f32
  sk.drawLabel(
    "LAYERS", vec2(x, y), vec2(160, 14), ReadyGold, "Small"
  )
  y += 16
  sk.drawDebugLegendSwatch(vec2(x, y), DebugWest, "West bank")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugEast, "East bank")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugRiver, "Fire pit")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugWater, "Coals")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugIsland, "Fountain / island")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugBlocked, "Blocked land")

proc debugPingLine(): string =
  ## Client→host WebSocket RTT, or 0 on the host/local machine.
  if netRole != NetClient:
    return "Ping: 0 ms  (local)"
  if not netPingKnown():
    return "Ping: ..."
  let jitter = netPingJitterMs()
  if jitter > 0:
    return &"Ping: {netPingMs()} ms  jitter {jitter} ms"
  &"Ping: {netPingMs()} ms"

proc applyNetSimEdits(cfg: var NetSimConfig) =
  cfg.enabled = true
  netSimConfigure(cfg)
  netSimSetLogging(true)

proc drawNetSimDebugControls(sk: Silky, window: Window) =
  ## F3 sliders for the client-side latency simulator. Host/local play
  ## has no follower packets, so the controls stay hidden there.
  if netRole != NetClient:
    return
  var cfg = netSimConfig()
  text "Network sim  F6 overlay  F7 cycle preset"
  var enabled = cfg.enabled
  checkBox "Simulate latency / jitter / loss", enabled
  if enabled != cfg.enabled:
    netSimEnable(enabled)
  text &"preset {netSimLabel()}   one-way {cfg.latencyMs}±{cfg.jitterMs} ms" &
    &"   loss {cfg.packetLossPercent:.1f}%"
  text &"expected RTT ≈ {cfg.latencyMs * 2} ms   sim {TickRate} Hz (fixed)"
  button "Next preset (local/good/poor/extreme/off)":
    netSimAdvanceCycle()
  var lat = cfg.latencyMs
  text "Latency ms (0 / 100 / 250 / 500)"
  scrubber "netLat", lat, 0, 500, ""
  if lat != cfg.latencyMs:
    cfg.latencyMs = lat
    applyNetSimEdits(cfg)
    cfg = netSimConfig()
  var jit = cfg.jitterMs
  text "Jitter ± ms"
  scrubber "netJit", jit, 0, 200, ""
  if jit != cfg.jitterMs:
    cfg.jitterMs = jit
    applyNetSimEdits(cfg)
    cfg = netSimConfig()
  var loss = cfg.packetLossPercent
  text "Outbound packet loss %"
  scrubber "netLoss", loss, 0.0, 20.0, ""
  if abs(loss - cfg.packetLossPercent) > 0.05:
    cfg.packetLossPercent = loss
    applyNetSimEdits(cfg)
    cfg = netSimConfig()
  var delayOut = cfg.delayOutbound
  var delayIn = cfg.delayInbound
  checkBox "Delay outbound (intents / pings)", delayOut
  checkBox "Delay inbound (host tape)", delayIn
  if delayOut != cfg.delayOutbound or delayIn != cfg.delayInbound:
    cfg.delayOutbound = delayOut
    cfg.delayInbound = delayIn
    applyNetSimEdits(cfg)
    cfg = netSimConfig()
  var dropIn = cfg.dropInbound
  checkBox "Drop inbound (desyncs the tape — debug only)", dropIn
  if dropIn != cfg.dropInbound:
    cfg.dropInbound = dropIn
    applyNetSimEdits(cfg)
    cfg = netSimConfig()
  let so = netSimStats(DirOutbound)
  let si = netSimStats(DirInbound)
  text &"out sent {so.offered}  delayed {so.delayed}  dropped {so.dropped}" &
    &"  q {so.queueDepth}/{so.queueMax}"
  text &"in  recv {si.offered}  delayed {si.delayed}  dropped {si.dropped}" &
    &"  q {si.queueDepth}/{si.queueMax}"
  when defined(emscripten):
    if predictor.enabled:
      text &"predict lead {predictor.lead}/{MaxLead} ticks  pending " &
        $predictor.pending.len & "  snaps " & $predictor.snapCount &
        (if predictor.snapped: "  SNAP" else: "")
    else:
      text "predict idle (no seat yet)"
  else:
    text "predict off — native join is lockstep; browser client has prediction"

proc drawDebugMenu(
    sk: Silky,
    window: Window,
    cameraTarget: Vec3,
    cameraDistance: var float32,
    cameraEye: Vec3
) =
  ## F3 corner panel: overlay toggles, live zoom clamps, and readouts.
  if not debugMenuOpen:
    return
  let playPx = worldPixelPanel(window)
  var recordOn = bugTapeArmed
  sk.beginDsl()
  try:
    subWindow(
      DebugWindowTitle,
      debugMenuOpen,
      DebugWindowOrigin,
      DebugWindowSize
    ):
      text debugPingLine()
      text "F2 frame rate / Fluffy trace"
      drawNetSimDebugControls(sk, window)
      checkBox "Fog of war", fogOfWar
      checkBox "Record bug tape", recordOn
      if recordOn != bugTapeArmed:
        setBugTapeArmed(recordOn)
      text "F8 start/stop. Stop writes duels/bug_*.pwr"
      if bugTapeArmed:
        text &"Recording… from tick {bugTapeFromTick}"
      else:
        text "idle"
      if bugTapeLastPath.len > 0:
        text bugTapeLastPath.extractFilename
      checkBox "Tile grid", showTiles
      checkBox "Layers", showLayers
      checkBox "Walkable / blocked", showWalkable
      checkBox "Playable AABB / ratio", showPlayableBounds
      checkBox "Collision / hook", showCollision
      checkBox "Camera / viewport", showCamera
      text "Zoom (camera distance; larger = farther out)"
      text &"current: {cameraDistance:.1f}"
      text "Min zoom (out limit, max dist)"
      scrubber "zoomOut", zoomMaxDistance, ZoomOutSliderMin, ZoomOutSliderMax, ""
      text "Max zoom (in limit, min dist)"
      scrubber "zoomIn", zoomMinDistance, ZoomInSliderMin, ZoomInSliderMax, ""
      text &"baked defaults: {BakedZoomInDistance:.0f} .. {BakedZoomOutDistance:.0f}"
      text &"play AABB {PlayableWidthTiles} x {PlayableDepthTiles} tiles"
      text &"ratio {PlayableWidthTiles}:{PlayableDepthTiles}  " &
        &"{PlayableWidthTiles.float32 / PlayableDepthTiles.float32:.2f}:1"
      text &"walk land W{WestBankWidthTiles} E{EastBankWidthTiles} " &
        &"Z{PlayableDepthTiles}"
      text &"cam tgt {cameraTarget.x:.1f} {cameraTarget.y:.1f} {cameraTarget.z:.1f}"
      text &"eye {cameraEye.x:.1f} {cameraEye.y:.1f} {cameraEye.z:.1f}"
      text &"view px {playPx.origin.x:.0f},{playPx.origin.y:.0f} " &
        &"{playPx.size.x:.0f}x{playPx.size.y:.0f}"
      text &"widgets: cluster {ClusterWidth:.0f}x{ClusterHeight:.0f}  " &
        &"map {MinimapSize:.0f}"
      if debugHoverFound:
        text &"hover tile {debugHoverX}, {debugHoverZ}"
      else:
        text "hover tile —"
      if localSeat < 0:
        text "spectator pid -1"
      else:
        text &"seat {localSeat}  pid {run.world.pudges[localSeat].id}"
      if spectatePudgeId != 0:
        text &"eyes pid {spectatePudgeId}  fogTeam {fogTeam()}"
      elif not humanControlActive():
        text "eyes omniscient"
  finally:
    sk.endDsl()
  cameraDistance = clampCameraDistance(cameraDistance)

proc drawFpsDebugger(sk: Silky, window: Window) =
  ## F2 frame-rate window: live fps, optional cap, interpolation, Fluffy.
  noteFps()
  if not fpsDebuggerOpen:
    return
  sk.beginDsl()
  try:
    subWindow(
      FpsWindowTitle,
      fpsDebuggerOpen,
      FpsWindowOrigin,
      FpsWindowSize
    ):
      text "FPS"
      text "fpsNow":
        font "Mono"
        characters fpsNowText
      text "fpsAvg":
        font "Mono"
        characters fpsAvgText
      text "fpsStd":
        font "Mono"
        characters fpsStdText
      text "FPS limit (0 = vsync)"
      scrubber(
        "fpsLimit",
        framePaceHz,
        0,
        FpsLimitMax,
        $framePaceHz
      )
      checkBox "Interpolation", interpolateVisuals
      if runtimeTraceActive():
        text "Fluffy recording… F2 writes tmp/fluffy.json"
      else:
        text "F2 starts a Fluffy frame trace"
  finally:
    sk.endDsl()

proc centerCameraOnInspect(
    window: Window,
    sk: Silky,
    hud: BottomHudLayout,
    cameraTarget: var Vec3,
    actionCam: var ActionCam,
    followSelection: var bool
) =
  ## Portrait click snaps the camera onto the butcher in the unit card.
  ## In replay it also locks fog to that butcher's team.
  if menuOpen or not commandCardVisible():
    return
  if not window.clicked(sk, hud.portrait):
    return
  let index = inspectIndex()
  if index < 0:
    return
  lockSpectatorEyes(run.world.pudges[index].id)
  actionCam.takeManual()
  if not humanControlActive():
    followSelection = true
  if not followSelection:
    let pos = inspectGroundPoint()
    cameraTarget.x = clamp(pos.x, -HalfGrid, HalfGrid)
    cameraTarget.z = clamp(pos.z, -HalfGrid, HalfGrid)

proc drawSpectatorBanner(
    sk: Silky, window: Window, layout: GameUiLayout,
    followSelection: var bool
) =
  ## Top-center POV plate: whose eyes, plus Show all to go omniscient.
  ## One string only — combat lines live in the Events tab, not here.
  if not spectatorChromeVisible() or menuOpen:
    return
  if run.replayMode and run.hashCheck.error.len > 0:
    return
  let banner = spectatorBannerPanel(layout)
  sk.drawEtched(banner.origin, banner.size, HudChipFill)
  let eyes = spectateIndex()
  if eyes < 0:
    sk.drawLabel(
      "OMNISCIENT - CLICK A BUTCHER",
      banner.origin,
      banner.size,
      ReadyGold,
      "Small",
      CenterAlign
    )
    return
  let allBtn = spectatorAllPanel(banner)
  sk.drawEtched(allBtn.origin, allBtn.size, HudChipActive)
  sk.drawLabel(
    "SHOW ALL", allBtn.origin, allBtn.size, HudGold, "Small", CenterAlign
  )
  if window.clicked(sk, allBtn):
    clearSpectatorEyes()
    followSelection = false
  var line = "EYES  "
  line.add butcherDisplayName(eyes)
  if not fogOfWar:
    line.add " - FOG OFF"
  sk.drawLabel(
    line,
    banner.origin + vec2(SpectatorAllW + 8, 0),
    vec2(banner.size.x - SpectatorAllW - 12, banner.size.y),
    ReadyGold,
    "Small",
    CenterAlign
  )

proc drawUi*(
    sk: Silky,
    window: Window,
    transport: var Player,
    cameraTarget: var Vec3,
    cameraDistance: var float32,
    actionCam: var ActionCam,
    followSelection: var bool,
    cameraEye = vec3(0)
) =
  var
    layout = currentLayout(window)
    chrome = placeChrome(layout)
  # Top-right corner: team scores flanking the match clock.
  var westScore = "WEST "
  westScore.addHudInt(int(run.world.teamKills[WestTeam.ord]))
  var eastScore = ""
  eastScore.addHudInt(int(run.world.teamKills[EastTeam.ord]))
  eastScore.add " EAST"
  let matchSeconds = int(run.world.tick div TickRate)
  var matchClock = ""
  writeClock(matchClock, matchSeconds div 60, matchSeconds mod 60)
  sk.drawScorePlate(
    layout,
    ScorePlate(
      west: westScore,
      east: eastScore,
      westColor: WestColor,
      eastColor: EastColor,
      clock: matchClock
    )
  )
  sk.drawRunePlate(layout)
  sk.drawSpectatorBanner(window, layout, followSelection)
  let clusterVisible = commandCardVisible()
  sk.drawBottomChrome(chrome.bottom, clusterVisible)
  sk.drawMinimap(window, chrome.bottom, cameraTarget, cameraDistance)
  # Menu, auto-lock, and director on the compass nameplate.
  # Allies, Chat, Replay, and Debug stay on the pause menu; F10 / F11
  # still toggle Allies / the chat-and-events plate.
  let clicked = sk.drawChipRow(
    window,
    chrome.bottom.buttons,
    [
      HudChip(id: ChipMenu, label: "MENU", key: KeyF9, active: menuOpen),
      HudChip(
        id: ChipFollow, label: "AUTO", key: bindKey(BindFollow),
        active: followSelection
      ),
      HudChip(
        id: ChipDirector, label: "DIR", key: bindKey(BindDirector),
        active: actionCam.enabled
      )
    ]
  )
  if clicked == ChipFollow:
    followSelection = not followSelection
    if followSelection:
      actionCam.takeManual()
      let lock = followCameraPoint()
      if lock.found:
        cameraTarget.x = lock.point.x
        cameraTarget.z = lock.point.z
  elif clicked == ChipDirector:
    actionCam.toggle(followSelection)
  elif clicked >= 0:
    applyChipClick(clicked, transport)
  if window.buttonPressed[KeyF10]:
    applyChipClick(ChipTeam, transport)
  if window.buttonPressed[KeyF11]:
    applyChipClick(ChipLog, transport)
  if clusterVisible:
    sk.drawBottomUnit(
      window, chrome.bottom, transport.inHistory and netRole != NetClient
    )
  sk.drawShopPanel(window, layout)
  centerCameraOnInspect(
    window, sk, chrome.bottom, cameraTarget, actionCam, followSelection
  )
  if transportBarOpen():
    var follow = followSelection
    drawTransport(
      transport,
      sk,
      window,
      chrome.transport,
      actionCam,
      follow
    )
    followSelection = follow
  sk.drawChatPanel(window, layout)
  sk.drawKillStinger(layout)
  sk.drawKillFeed(layout)
  let index = heroIndex()
  if humanControlActive() and isOwnedInspect() and index >= 0 and
      run.world.pudges[index].state == Dying and not run.world.gameOver:
    hudScratch.setLen(0)
    hudScratch.add "RESPAWN IN "
    hudScratch.addHudSeconds(run.world.pudges[index].deathTicks)
    sk.drawLabel(
      hudScratch,
      vec2(0, layout.size.y * 0.38'f32),
      vec2(layout.size.x, 30),
      ReadyGold,
      "H1",
      CenterAlign
    )
  elif humanControlActive() and isOwnedInspect() and index >= 0 and
      run.world.pudges[index].shieldTicks > 0 and not run.world.gameOver and
      not transport.inHistory:
    hudScratch.setLen(0)
    hudScratch.add "INVULNERABLE  "
    hudScratch.addHudSeconds(run.world.pudges[index].shieldTicks)
    sk.drawLabel(
      hudScratch,
      vec2(0, layout.size.y * 0.38'f32),
      vec2(layout.size.x, 30),
      ShieldHpColor,
      "H1",
      CenterAlign
    )
  elif not humanControlActive() and not run.replayMode and
      not run.world.gameOver and not transport.inHistory:
    let
      chromeFloor =
        if commandCardVisible(): chrome.bottom.bar.origin.y
        elif transportBarOpen(): chrome.transport.origin.y
        else: layout.size.y
      (errText, errAlpha) = humanErrorLine()
    if errText.len > 0:
      sk.drawLabel(
        errText,
        vec2(0, chromeFloor - 52),
        vec2(layout.size.x, 22),
        rgbx(245, 80, 85, uint8(errAlpha * 255)),
        "Hud",
        CenterAlign
      )
    let seatHint =
      if netRole == NetClient:
        "SPECTATING - PICK A SEAT FROM THE HOST'S LOBBY PAGE"
      else:
        "TAKE A SEAT: PRESS 1-0, OR T OVER A BUTCHER"
    # Shadow pass keeps the hint readable over the fire pit.
    sk.drawLabel(
      seatHint,
      vec2(1, chromeFloor - 25),
      vec2(layout.size.x, 18),
      rgbx(8, 8, 10, 150),
      "Small",
      CenterAlign
    )
    sk.drawLabel(
      seatHint,
      vec2(0, chromeFloor - 26),
      vec2(layout.size.x, 18),
      rgbx(215, 215, 215, 170),
      "Small",
      CenterAlign
    )
  sk.drawDebugOverlaysHud(layout)
  sk.drawDebugMenu(window, cameraTarget, cameraDistance, cameraEye)
  sk.drawFpsDebugger(window)
  # Modals last so they cover chrome, kill-feed toasts, and world labels.
  if alliesOpen:
    sk.drawRoster(window, chrome.west, WestTeam, "West bank", followSelection)
    sk.drawRoster(window, chrome.east, EastTeam, "East bank", followSelection)
  if menuOpen:
    if controlsOpen:
      sk.drawControlsOverlay(window, layout, transport)
    else:
      sk.drawMenuOverlay(window, layout, transport)
  if run.replayMode:
    if run.hashCheck.error.len > 0:
      sk.drawError(
        layout.size,
        "REPLAY DIVERGED — continuing " &
          "(" & $run.hashCheck.mismatches & " mismatches)",
        run.hashCheck.error
      )
  publishMatchState()
  if run.world.gameOver:
    sk.drawEndScreen(window, layout)
  else:
    recapPublished = false
