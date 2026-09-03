## Pudge Wars Silky HUD: floating corner widgets over a full-screen world.

import
  std/[json, os, strformat, strutils, times],
  chroma, pixie, silky, vmath, windy,
  polyworld/[
    actioncam, bottomhud, chrome, commandcard, gameuis, hudchips, pathing,
    player, rtscameras
  ],
  content, maps, netproto, netclient, netsim, netpredict, sim, game, human,
  keybinds, replays

const
  PanelRoster = vec2(380, 300)
  PanelEndScreen = vec2(640, 430)
  WestColor = rgbx(214, 86, 72, 255)
  EastColor = rgbx(82, 142, 220, 255)
  HpColor = rgbx(196, 48, 48, 255)
  HookBarColor = rgbx(72, 148, 210, 255)
  ReadyGold = rgbx(255, 214, 120, 255)
  KillFeedSeconds = 6.0
  KillFeedMax = 6
  StingerSeconds = 3.8
  EventLogMax = 24
  MinimapGrass = rgbx(38, 58, 40, 255)
  MinimapRiver = rgbx(52, 96, 128, 255)
  MinimapIsland = rgbx(120, 118, 108, 255)
  MinimapPing = rgbx(255, 214, 90, 255)
  RuneColors*: array[RuneKind, ColorRGBX] = [
    rgbx(255, 72, 214, 255),   # Haste: DotA / WC3 pink
    rgbx(64, 168, 255, 255),   # Double Damage: electric blue
    rgbx(72, 224, 104, 255),   # Regen: life green
    rgbx(255, 164, 52, 255)    # Big Hook: amber (no WC3 analog)
  ]
  RuneHudNames: array[RuneKind, string] = [
    "HASTE", "2X DMG", "REGEN",
    "BIG +" & $RuneBigHookDamagePercent & "%"
  ]
  CommandPortraitGrow = 2.0'f32
  ChipMenu = 0
  ChipTeam = 1
  ChipLog = 2
  ChipReplay = 3
  ChipDebug = 4
  MenuResume = 0
  MenuRestart = 1
  MenuAllies = 2
  MenuLog = 3
  MenuItemCount = 4
  MenuButtonH = 38.0'f32
  MenuButtonGap = 10.0'f32
  MenuPanelSize = vec2(400, 330)
  CmdMove = 0
  CmdStop = 1
  CmdHold = 2
  CmdAttack = 3
  CmdHook = 4
  CmdBlink = 5
  CmdRot = 6
  LogPanelSize = vec2(480, 220)
  KillFeedW = 300.0'f32
  ShopPanelSize = vec2(340, 304)
  PermanentShopCols = 4
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
  DebugRiver* = rgbx(48, 110, 168, 255)
  DebugWater* = rgbx(72, 196, 214, 255)
  DebugIsland* = rgbx(214, 196, 120, 255)
  DebugBlocked* = rgbx(118, 72, 48, 255)
  DebugWalk* = rgbx(72, 196, 96, 255)
  DebugNoWalk* = rgbx(220, 64, 64, 255)
  SpectatorBannerSize = vec2(470, 28)
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

var
  killFeed: seq[KillFeedEntry]
  eventLog: seq[KillFeedEntry]
  killStinger: KillStinger
  alliesOpen = false
  menuOpen = false
  logOpen = false
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
  showTransportBar = false
  showTransportBarReady = false
  bugTapeArmed* = false
    ## F3 / F8: Stop will flush a named copy of the live match tape.
  bugTapeFromTick* = 0'i32
  bugTapeLastPath* = ""

proc menuIsOpen*(): bool =
  ## True while the F9 pause plate is up.
  menuOpen

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
  ## Replay strip visibility. Live matches start hidden; `--replay` starts open.
  if not showTransportBarReady:
    showTransportBar = run.replayMode
    showTransportBarReady = true
  showTransportBar

proc toggleTransportBar*() =
  showTransportBar = not transportBarOpen()

proc pushKillFeed*(text: string, team: Team) =
  ## Appends one line to the top-center kill feed and the Log overlay.
  let entry = KillFeedEntry(
    text: text,
    color: if team == WestTeam: WestColor else: EastColor,
    born: epochTime()
  )
  if killFeed.len >= KillFeedMax:
    killFeed.delete(0)
  killFeed.add entry
  if eventLog.len >= EventLogMax:
    eventLog.delete(0)
  eventLog.add entry

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

proc mouseOverUi*(window: Window, mouse: Vec2): bool =
  ## True over floating HUD widgets that should eat camera and world
  ## clicks. Everywhere else the full-screen world stays clickable.
  if mouseOverDebugMenu(mouse):
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
  if commandCardVisible() and chrome.bottom.bar.contains(mouse):
    return true
  if transportBarOpen() and chrome.transport.contains(mouse):
    return true
  if alliesOpen and
      (chrome.west.contains(mouse) or chrome.east.contains(mouse)):
    return true
  logOpen and layout.panel(GameUiRegion.TopCenter, LogPanelSize).contains(mouse)

proc minimapArea(window: Window): GameUiPanel =
  ## Inner map rectangle of the bottom-left minimap plate.
  placeChrome(currentLayout(window)).bottom.minimap.minimapInner()

proc updateMinimapCamera*(
    window: Window,
    mouse: Vec2,
    cameraTarget: var Vec3,
    minimapPanning: var bool,
    followSelection: var bool
) =
  ## Pans the camera while the primary button drags on the minimap.
  if menuOpen:
    if not window.buttonDown[MouseLeft]:
      minimapPanning = false
    return
  let area = minimapArea(window)
  if window.buttonPressed[MouseLeft] and area.contains(mouse):
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

proc drawMinimap(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    cameraTarget: Vec3,
    cameraDistance: float32
) =
  ## Ground, river, fountain, butcher pips, team pings, and the camera
  ## footprint. LMB drag on the map pans (updateMinimapCamera).
  let area = panel.minimapInner()
  sk.drawRect(area.origin, area.size, MinimapGrass)
  let
    riverLeft = float32(RiverCenterX - RiverHalfWidth) / float32(GridTiles)
    riverRight = float32(RiverCenterX + RiverHalfWidth + 1) /
      float32(GridTiles)
  sk.drawRect(
    area.origin + vec2(riverLeft * area.size.x, 0),
    vec2((riverRight - riverLeft) * area.size.x, area.size.y),
    MinimapRiver
  )
  let islandSize = vec2(
    float32(IslandRadius * 2 + 1) / float32(GridTiles) * area.size.x,
    float32(IslandRadius * 2 + 1) / float32(GridTiles) * area.size.y
  )
  sk.drawRect(
    minimapPosition(
      hudPoint(worldAtTile(IslandCenterX, IslandCenterZ)), area
    ) - islandSize * 0.5'f32,
    islandSize,
    MinimapIsland
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
      let point = minimapPosition(
        hudPoint(worldAtTile(int(ping.x), int(ping.y))), area
      )
      sk.drawRect(point - vec2(5), vec2(10), MinimapPing)

  for rune in run.world.runes:
    if not fogCanSee(rune.position):
      continue
    let point = minimapPosition(hudPoint(rune.position), area)
    sk.drawRect(point - vec2(2.5'f32), vec2(5), RuneColors[rune.kind])

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
      sk.drawRect(point - vec2(3), vec2(6), rgbx(138, 94, 54, 255))
    else:
      sk.drawRect(point - vec2(2), vec2(4), rgbx(88, 96, 72, 200))

  for i, pudge in run.world.pudges:
    if pudge.state == Dying:
      continue
    if not fogShownPudge(pudge):
      continue
    let point = minimapPosition(hudPoint(pudge.position), area)
    if i == heroSlot or i == spectateSlot:
      sk.drawRect(point - vec2(5), vec2(10), rgbx(255, 255, 255, 255))
    sk.drawRect(
      point - vec2(3.5'f32),
      vec2(7),
      if pudge.team == WestTeam: WestColor else: EastColor
    )

  let aspect = currentLayout(window).worldPanel.aspect
  sk.drawCameraFrame(
    minimapViewport(
      cameraTarget, cameraDistance, aspect,
      area.origin, area.size, HalfGrid
    )
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
  var y = hudToastY(layout)
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
    title: string
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
    hudScratch.setLen(0)
    hudScratch.add "P"
    hudScratch.addHudInt(int(pudge.id))
    hudScratch.add "  K"
    hudScratch.addHudInt(int(pudge.kills))
    hudScratch.add " D"
    hudScratch.addHudInt(int(pudge.deaths))
    if pudge.hookedBy != 0:
      hudScratch.add "  hooked"
    elif pudge.inRiver:
      hudScratch.add "  river"
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
      if pudge.inRiver: rgbx(64, 168, 196, 255) else: HpColor
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

proc coverSquare(well: GameUiPanel, grow: float32): GameUiPanel =
  ## Square crop for portrait sprites inside a rectangular well.
  let side = min(well.size.x, well.size.y)
  let excess = (well.size - vec2(side)) * 0.5'f32
  GameUiPanel(
    origin: well.origin + excess - vec2(grow),
    size: vec2(side + grow * 2)
  )

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

proc drawBottomUnit(
    sk: Silky,
    window: Window,
    hud: BottomHudLayout,
    inHistory: bool
) =
  ## Fills the hero cluster: portrait, title line, command and upgrade
  ## rows, and full-width vitals bars. Status text floats above the
  ## plate so nothing else reserves screen space.
  let index = inspectIndex()
  if index < 0:
    return
  let
    owned = isOwnedInspect()
    heroIdx = heroIndex()
    hero = run.world.pudges[index]
    teamColor = if hero.team == WestTeam: WestColor else: EastColor
    portrait = hud.portrait
  sk.drawRect(portrait.origin + vec2(2), portrait.size - vec2(4), teamColor)
  let portraitCover = coverSquare(
    GameUiPanel(
      origin: portrait.origin + vec2(2),
      size: portrait.size - vec2(4)
    ),
    CommandPortraitGrow
  )
  sk.drawSprite(PortraitKeys[hero.team], portraitCover.origin, portraitCover.size)
  if hero.state == Dying:
    sk.drawRect(portrait.origin + vec2(2), portrait.size - vec2(4), rgbx(12, 14, 20, 170))
    hudScratch.setLen(0)
    hudScratch.addHudSeconds(hero.deathTicks)
    sk.drawLabel(
      hudScratch, portrait.origin, portrait.size, ReadyGold, "Small", CenterAlign
    )
  elif hero.shieldTicks > 0:
    sk.drawRect(
      portrait.origin + vec2(2), portrait.size - vec2(4), rgbx(120, 200, 255, 70)
    )
  if hero.state != Dying and hero.buffTicks > 0:
    let
      plateSize = vec2(portrait.size.x - 4, 14)
      plateOrigin = portrait.origin + vec2(2, portrait.size.y - 16)
    sk.drawRect(plateOrigin, plateSize, rgbx(10, 12, 16, 190))
    hudScratch.setLen(0)
    hudScratch.add RuneHudNames[hero.buffKind]
    hudScratch.add " "
    hudScratch.addHudSeconds(hero.buffTicks)
    sk.drawLabel(
      hudScratch, plateOrigin, plateSize,
      RuneColors[hero.buffKind], "Small", CenterAlign
    )

  # Title line: name and level on the left, kills and points on the right.
  hudScratch.setLen(0)
  hudScratch.add PudgeSpecs[hero.team].name
  hudScratch.add "  P"
  hudScratch.addHudInt(int(hero.id))
  hudScratch.add "  LV "
  hudScratch.addHudInt(int(hero.kills) + 1)
  if not owned:
    if spectatePudgeId == hero.id:
      hudScratch.add "  EYES"
    elif heroIdx >= 0 and hero.team == run.world.pudges[heroIdx].team:
      hudScratch.add "  ALLY"
    elif heroIdx >= 0:
      hudScratch.add "  ENEMY"
  sk.drawLabel(
    hudScratch,
    hud.title.origin + vec2(2, 0),
    vec2(hud.title.size.x * 0.55'f32, hud.title.size.y),
    rgbx(255, 255, 255, 255),
    "Small"
  )
  hudScratch.setLen(0)
  hudScratch.add "KO "
  hudScratch.addHudInt(int(hero.kills))
  hudScratch.add "  G "
  hudScratch.addHudInt(int(hero.gold))
  hudScratch.add "  PTS "
  hudScratch.addHudInt(int(hero.points))
  sk.drawLabel(
    hudScratch,
    hud.title.origin + vec2(hud.title.size.x * 0.55'f32, 0),
    vec2(hud.title.size.x * 0.45'f32 - 2, hud.title.size.y),
    ReadyGold,
    "Small",
    RightAlign
  )

  writeRatio(hudScratch, max(hero.hp, 0).int, int(hero.maxHp))
  sk.drawValueBar(
    hud.hpBar.origin,
    hud.hpBar.size,
    max(hero.hp, 0).float32,
    max(hero.maxHp, 1).float32,
    if hero.inRiver: rgbx(64, 168, 196, 255) else: HpColor,
    hudScratch
  )
  let
    hookRemaining =
      if hero.windupTicks > 0: hero.windupTicks else: hero.hookCooldown
    hookDuration =
      if hero.windupTicks > 0: HookWindupTicks else: HookCooldownTicks
    hookReady = hero.state == Alive and not inHistory and
      hero.windupTicks <= 0 and hero.hookCooldown <= 0 and not hookFlying(hero)
    hookFill =
      if hookRemaining <= 0 or hookDuration <= 0: 1.0'f32
      else: 1.0'f32 - hookRemaining.float32 / hookDuration.float32
  # The hook bar caption doubles as the status line.
  hudScratch.setLen(0)
  if inHistory:
    hudScratch.add "SPECTATING THE PAST"
  elif owned and aimingHookNow():
    hudScratch.add "HOOK - CLICK GROUND"
  elif owned and aimingBlinkNow():
    hudScratch.add "BLINK - LAST LEGAL TILE"
  elif hero.windupTicks > 0:
    hudScratch.add "CASTING"
  elif hookFlying(hero):
    hudScratch.add "IN FLIGHT"
  elif hookReady:
    hudScratch.add "READY"
    if owned and options.quickcast:
      hudScratch.add " - QUICKCAST"
  elif hookRemaining > 0:
    hudScratch.addHudInt(int(cooldownSeconds(hookRemaining)))
    hudScratch.add " s"
  else:
    hudScratch.add "HOOK"
  sk.drawValueBar(
    hud.resourceBar.origin,
    hud.resourceBar.size,
    hookFill,
    1.0'f32,
    HookBarColor,
    hudScratch
  )

  let
    hookOverlay = cooldownOverlay(
      hookRemaining,
      hookDuration,
      if hero.windupTicks > 0: "CAST"
      elif hookFlying(hero): "AIR"
      else: ""
    )
    ownedLive = owned and not inHistory
  # Only your own butcher shows buttons, and only ones that carry
  # information or a real click: attack + hook (cooldown overlays) and
  # the four upgrades. Move/stop/hold were RMB/S cosplay; an inspected
  # enemy showed a row of dead grey squares.
  if owned:
    var commands: seq[CommandSlotSpec]
    commands.add CommandSlotSpec(
      id: CmdAttack, icon: AttackIcon, hotkey: "RMB",
      enabled: ownedLive,
      remaining: hero.swingTicks, duration: hero.attackPeriod,
      overlay: cooldownOverlay(hero.swingTicks, hero.attackPeriod)
    )
    commands.add CommandSlotSpec(
      id: CmdHook, icon: "hook",
      hotkey: bindLabel(BindHook),
      enabled: ownedLive and hookReady,
      remaining: hookRemaining, duration: hookDuration,
      overlay: hookOverlay
    )
    commands.add CommandSlotSpec(
      id: CmdRot, icon: "rot",
      hotkey: bindLabel(BindRot),
      enabled: ownedLive,
      overlay: if hero.rotOn: "ON" else: ""
    )
    let
      blinkReady = hero.state == Alive and not inHistory and
        hero.windupTicks <= 0 and hero.blinkCooldown <= 0 and
        hero.hookedBy == 0 and not run.world.rotAffected(hero)
      blinkOverlay = cooldownOverlay(
        hero.blinkCooldown, BlinkCooldownTicks
      )
    commands.add CommandSlotSpec(
      id: CmdBlink, icon: "blink",
      hotkey: bindLabel(BindBlink),
      enabled: ownedLive and blinkReady,
      remaining: hero.blinkCooldown, duration: BlinkCooldownTicks,
      overlay: blinkOverlay
    )
    let clickedCmd = sk.drawCommandGrid(window, hud.commands, commands, 4, 1)
    case clickedCmd
    of CmdAttack: beginAttackCommand()
    of CmdHook: beginHookCommand()
    of CmdRot: beginRotCommand()
    of CmdBlink: beginBlinkCommand()
    else: discard

    var itemSlots: seq[CommandSlotSpec]
    for item in ShopBoots..ShopMine:
      if hero.itemRank[item] <= 0:
        continue
      var remaining, duration: int32
      var hotkey = ""
      if item == ShopWall:
        remaining = hero.wallCooldown
        duration = wallCooldownTicks(hero.itemRank[item])
        hotkey = bindLabel(BindWall)
      elif item == ShopMine:
        remaining = hero.mineCooldown
        duration = MineCooldownTicks
        hotkey = bindLabel(BindMine)
      itemSlots.add CommandSlotSpec(
        id: item.ord,
        icon: ShopItemIcons[item],
        hotkey: hotkey,
        enabled: true,
        remaining: remaining,
        duration: duration,
        overlay: cooldownOverlay(remaining, duration),
        badge: $hero.itemRank[item]
      )
    let clickedItem = sk.drawCommandGrid(
      window, hud.items, itemSlots, InventoryCols, InventoryRows
    )
    if clickedItem == ShopWall.ord:
      beginPlaceCommand(ShopWall)
    elif clickedItem == ShopMine.ord:
      beginPlaceCommand(ShopMine)

    block itemTooltip:
      var hovered: ShopItem
      var found = false
      var slot = 0
      for item in ShopBoots..ShopMine:
        if hero.itemRank[item] <= 0:
          continue
        let
          col = slot mod InventoryCols
          row = slot div InventoryCols
        if hud.items.gridSlot(
            col, row, InventoryCols, InventoryRows
        ).contains(sk.mousePos):
          hovered = item
          found = true
          break
        inc slot
      if not found:
        break itemTooltip
      let
        rank = hero.itemRank[hovered]
        lines = [
          ShopItemNames[hovered] & "  [rank " & $rank & "/" &
            $ItemMaxRank & "]",
          shopItemBlurb(hovered)
        ]
        tipW = 400.0'f32
        tipH = 14.0'f32 + 2 * 18.0'f32
        tipOrigin = vec2(
          clamp(
            hud.items.origin.x, 4.0'f32,
            currentLayout(window).size.x - tipW - 4.0'f32
          ),
          hud.items.origin.y - tipH - 6.0'f32
        )
      sk.drawRect(tipOrigin, vec2(tipW, tipH), rgbx(10, 12, 16, 230))
      for i, line in lines:
        sk.drawLabel(
          line,
          tipOrigin + vec2(10, 8.0'f32 + float32(i) * 18.0'f32),
          vec2(tipW - 20, 16),
          if i == 0: ReadyGold else: LabelColor,
          if i == 0: "Hud" else: "Small"
        )

    var upgrades: seq[CommandSlotSpec]
    for kind in UpgradeKind:
      let
        level = hero.upgrades[kind]
        affordable = ownedLive and hero.points > 0 and level < MaxUpgradeLevel
      upgrades.add CommandSlotSpec(
        id: kind.ord,
        icon: UpgradeIcons[kind],
        hotkey: bindLabel(BindAction(ord(BindUpgrade1) + ord(kind))),
        enabled: affordable or level > 0,
        overlay: if level >= MaxUpgradeLevel: "MAX" else: "",
        badge: if level >= MaxUpgradeLevel or level == 0: "" else: $level
      )
    let clickedUp = sk.drawCommandGrid(
      window, hud.inventory, upgrades, InventoryCols, InventoryRows
    )
    if clickedUp >= 0 and clickedUp <= UpgradeKind.high.ord:
      issueBuyCommand(UpgradeKind(clickedUp))

    # Hover tooltip: what each stat rank actually buys, with live
    # current -> next numbers from the balance tables.
    block upgradeTooltip:
      var hoveredKind = -1
      for row in 0 ..< InventoryRows:
        for col in 0 ..< InventoryCols:
          let index = row * InventoryCols + col
          if index > UpgradeKind.high.ord:
            continue
          if hud.inventory.gridSlot(
              col, row, InventoryCols, InventoryRows
          ).contains(sk.mousePos):
            hoveredKind = index
      if hoveredKind < 0:
        break upgradeTooltip
      let
        kind = UpgradeKind(hoveredKind)
        level = hero.upgrades[kind]
        maxed = level >= MaxUpgradeLevel
      proc tiles(value: int32): string =
        let tenths = int(int64(value) * 10 div WorldScale)
        $(tenths div 10) & "." & $(tenths mod 10)
      var effect, numbers: string
      case kind
      of UpgradeDamage:
        effect = "Each rank: +" & $HookDamagePerLevel & " hook damage."
        numbers = "damage " & $hookDamage(level) &
          (if maxed: "" else: " > " & $hookDamage(level + 1))
      of UpgradeDistance:
        effect = "Each rank: +" & tiles(HookRangePerLevel) &
          " tiles of hook range."
        numbers = "range " & tiles(hookRange(level)) &
          (if maxed: "" else: " > " & tiles(hookRange(level + 1))) &
          " tiles"
      of UpgradeSpeed:
        effect = "Each rank: faster hook flight (and reel)."
        numbers = "speed " & tiles(hookSpeed(level) * TickRate) &
          (if maxed: ""
           else: " > " & tiles(hookSpeed(level + 1) * TickRate)) &
          " tiles/s"
      of UpgradeRadius:
        effect = "Each rank: a wider hook grab (easier latches)."
        numbers = "radius " & tiles(hookRadius(level)) &
          (if maxed: "" else: " > " & tiles(hookRadius(level + 1))) &
          " tiles"
      let
        lines = [
          UpgradeNames[kind] & "  [rank " & $level & "/" &
            $MaxUpgradeLevel & "]",
          effect,
          if maxed: "MAXED"
          else: numbers & "   cost: 1 point (kills earn points)"
        ]
        tipW = 340.0'f32
        tipH = 14.0'f32 + 3 * 18.0'f32
        tipOrigin = vec2(
          clamp(
            hud.inventory.origin.x, 4.0'f32,
            currentLayout(window).size.x - tipW - 4.0'f32
          ),
          hud.inventory.origin.y - tipH - 6.0'f32
        )
      sk.drawRect(tipOrigin, vec2(tipW, tipH), rgbx(10, 12, 16, 230))
      for i, line in lines:
        sk.drawLabel(
          line,
          tipOrigin + vec2(10, 8.0'f32 + float32(i) * 18.0'f32),
          vec2(tipW - 20, 16),
          if i == 0: ReadyGold else: LabelColor,
          if i == 0: "Hud" else: "Small"
        )

  if owned:
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
  sk.drawRect(panel.origin, panel.size, rgbx(10, 12, 16, 230))
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
  for item in ShopBoots..ShopMine:
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
  if clickedPerm >= ShopBoots.ord and clickedPerm <= ShopMine.ord:
    issueBuyPower(ShopItem(clickedPerm))
  block shopTip:
    var hovered = ShopFlask
    var found = false
    var i = 0
    for item in ShopBoots..ShopMine:
      let
        col = i mod PermanentShopCols
        row = i div PermanentShopCols
      if grid.gridSlot(
          col, row, PermanentShopCols, PermanentShopRows
      ).contains(sk.mousePos):
        hovered = item
        found = true
        break
      inc i
    if found:
      let
        rank = hero.itemRank[hovered]
        tip = ShopItemNames[hovered] & "  " & $shopPrice(hovered) &
          "g   " & shopItemBlurb(hovered) &
          (if rank > 0: "  owned " & $rank else: "")
      sk.drawLabel(
        tip,
        panel.origin + vec2(8, 124),
        vec2(panel.size.x - 16, 16),
        LabelColor,
        "Small"
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
    hoveredRowY = 0.0'f32
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
    var label = "[" & PowerKeys[i] & "]  " & ShopItemNames[item] &
      "  " & $shopPrice(item) & "g"
    if item == ShopBigHook:
      label.add "  +" & $RuneBigHookDamagePercent & "% dmg"
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
      hoveredRowY = row.origin.y
  if foundPower:
    let
      tip = shopItemBlurb(hoveredPower)
      tipW = min(panel.size.x, 320.0'f32)
      tipH = 28.0'f32
      tipOrigin = vec2(panel.origin.x, hoveredRowY - tipH - 4.0'f32)
    sk.drawRect(tipOrigin, vec2(tipW, tipH), rgbx(10, 12, 16, 230))
    sk.drawLabel(
      tip,
      tipOrigin + vec2(8, 6),
      vec2(tipW - 16, 16),
      LabelColor,
      "Small"
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
    panel = layout.panel(GameUiRegion.Center, vec2(600, 430))
  sk.drawRect(vec2(0, 0), layout.size, rgbx(6, 8, 12, 170))
  let inner = sk.beginPanel(panel, ReadyGold)
  sk.drawLabel(
    "MATCH LOBBY",
    inner.origin,
    vec2(inner.size.x, 30),
    ReadyGold,
    "H1",
    CenterAlign
  )
  sk.drawLabel(
    "SHIFT+1-6 TOGGLES A SEAT   -   FRIENDS JOIN AT",
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
  var y = 100.0'f32
  for i in 0 ..< PudgeCount:
    let
      team = if i < TeamSize: WestTeam else: EastTeam
      teamColor = if team == WestTeam: WestColor else: EastColor
      mine = i == localClaim
      seat =
        if i < seats.len: seats[i]
        else: NetSeat()
    hudScratch.setLen(0)
    hudScratch.add "["
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
    "1-6 TAKE A SEAT      0 SPECTATE      ENTER START",
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
  ## hand off to Allies / Log.
  case id
  of MenuResume:
    menuOpen = false
    transport.playing = true
  of MenuRestart:
    if not menuCanRestart():
      return
    menuOpen = false
    alliesOpen = false
    logOpen = false
    menuRestartRequested = true
    transport.playing = true
  of MenuAllies:
    menuOpen = false
    alliesOpen = true
    logOpen = false
    transport.playing = true
  of MenuLog:
    menuOpen = false
    logOpen = true
    alliesOpen = false
    transport.playing = true
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
    Labels = ["Resume", "Restart Game", "Allies", "Log"]
    NumberKeys = [Key1, Key2, Key3, Key4]
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

proc drawLogOverlay(sk: Silky, layout: GameUiLayout) =
  ## Larger kill / event log under the top bar.
  let
    panel = layout.panel(GameUiRegion.TopCenter, LogPanelSize)
    inner = sk.beginPanel(panel, ReadyGold)
  sk.drawLabel(
    "LOG",
    inner.origin,
    vec2(inner.size.x, 22),
    ReadyGold,
    "Hud",
    CenterAlign
  )
  if eventLog.len == 0:
    sk.drawLabel(
      "no events yet",
      inner.origin + vec2(0, 40),
      vec2(inner.size.x, 18),
      rgbx(150, 156, 170, 255),
      "Small",
      CenterAlign
    )
    return
  var y = 32.0'f32
  for i in countdown(eventLog.len - 1, 0):
    sk.drawLabel(
      eventLog[i].text,
      inner.origin + vec2(8, y),
      vec2(inner.size.x - 16, 18),
      eventLog[i].color,
      "Small",
      CenterAlign
    )
    y += 22
    if y > inner.size.y - 24:
      break

proc applyChipClick(id: int, transport: var Player) =
  ## Toggles the overlay that matches one minimap chip.
  case id
  of ChipMenu:
    menuOpen = not menuOpen
    logOpen = false
    if menuOpen:
      menuCursor = 0
    transport.playing = not menuOpen
  of ChipTeam:
    alliesOpen = not alliesOpen
  of ChipLog:
    logOpen = not logOpen
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
  # Bottom-left corner: clear of the score plate, kill feed, and minimap.
  var y = layout.size.y - 220
  let x = 16.0'f32
  sk.drawLabel(
    "LAYERS", vec2(x, y), vec2(160, 14), ReadyGold, "Small"
  )
  y += 16
  sk.drawDebugLegendSwatch(vec2(x, y), DebugWest, "West bank")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugEast, "East bank")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugRiver, "River bed")
  y += 14
  sk.drawDebugLegendSwatch(vec2(x, y), DebugWater, "Visual water")
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
  followSelection = false
  let pos = inspectGroundPoint()
  cameraTarget.x = clamp(pos.x, -HalfGrid, HalfGrid)
  cameraTarget.z = clamp(pos.z, -HalfGrid, HalfGrid)

proc drawSpectatorBanner(sk: Silky, window: Window, layout: GameUiLayout) =
  ## Top-center POV plate: whose eyes, plus Show all to go omniscient.
  if not spectatorChromeVisible() or logOpen or menuOpen:
    return
  let banner = spectatorBannerPanel(layout)
  sk.drawEtched(banner.origin, banner.size, HudChipFill)
  hudScratch.setLen(0)
  let eyes = spectateIndex()
  if eyes < 0:
    hudScratch.add "OMNISCIENT  ·  CLICK A BUTCHER"
    sk.drawLabel(
      hudScratch, banner.origin, banner.size, ReadyGold, "Small", CenterAlign
    )
    return
  let allBtn = spectatorAllPanel(banner)
  sk.drawEtched(allBtn.origin, allBtn.size, HudChipActive)
  sk.drawLabel(
    "SHOW ALL", allBtn.origin, allBtn.size, HudGold, "Small", CenterAlign
  )
  if window.clicked(sk, allBtn):
    clearSpectatorEyes()
  let pudge = run.world.pudges[eyes]
  hudScratch.setLen(0)
  hudScratch.add "EYES  "
  hudScratch.add PudgeSpecs[pudge.team].name
  hudScratch.add "  P"
  hudScratch.addHudInt(int(pudge.id))
  if not fogOfWar:
    hudScratch.add "  ·  FOG OFF"
  sk.drawLabel(
    hudScratch,
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
  sk.drawSpectatorBanner(window, layout)
  # Mini chips above the minimap keep menu access off the play field.
  let clicked = sk.drawChipRow(
    window,
    chrome.bottom.buttons,
    [
      HudChip(
        id: ChipDebug, label: "DBG", key: ButtonUnknown,
        active: debugMenuOpen
      ),
      HudChip(id: ChipMenu, label: "MENU", key: KeyF9, active: menuOpen),
      HudChip(id: ChipTeam, label: "TEAM", key: KeyF10, active: alliesOpen),
      HudChip(id: ChipLog, label: "LOG", key: KeyF11, active: logOpen),
      HudChip(
        id: ChipReplay, label: "REC", key: ButtonUnknown,
        active: transportBarOpen()
      )
    ]
  )
  if clicked >= 0:
    applyChipClick(clicked, transport)
    if clicked == ChipReplay:
      layout = currentLayout(window)
      chrome = placeChrome(layout)
  let clusterVisible = commandCardVisible()
  sk.drawBottomChrome(chrome.bottom, clusterVisible)
  sk.drawMinimap(window, chrome.bottom.minimap, cameraTarget, cameraDistance)
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
  if run.world.chunkerId != 0 and
      run.world.tick - run.world.chunkTick < ChunkAnnounceTicks:
    hudScratch.setLen(0)
    hudScratch.add "P"
    hudScratch.addHudInt(int(run.world.chunkerId))
    hudScratch.add " denied P"
    hudScratch.addHudInt(int(run.world.chunkOwnerId))
    hudScratch.add "'s hook"
    sk.drawLabel(
      hudScratch,
      vec2(0, 12),
      vec2(layout.size.x, 20),
      ReadyGold,
      "Hud",
      CenterAlign
    )
  sk.drawKillStinger(layout)
  if not logOpen:
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
        "TAKE A SEAT: PRESS 1-6, OR T OVER A BUTCHER"
    # Shadow pass keeps the hint readable over the bright river.
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
  # Modals last so they cover chrome, kill-feed toasts, and world labels.
  if alliesOpen:
    sk.drawRoster(window, chrome.west, WestTeam, "West bank")
    sk.drawRoster(window, chrome.east, EastTeam, "East bank")
  if logOpen:
    sk.drawLogOverlay(layout)
  if menuOpen:
    sk.drawMenuOverlay(window, layout, transport)
  if run.replayMode:
    if run.replayVersionSkew:
      sk.drawError(
        layout.size,
        "TAPE v" & $run.replayData.header.gameVersion &
          " / SIM v" & $ReplayGameVersion & " — HASHES SKIPPED",
        "This build's physics differ from the recording; watching anyway"
      )
    elif run.hashCheck.error.len > 0:
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
