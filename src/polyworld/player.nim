## Shared play/replay transport for Polyworld games.
##
## Live matches and file replays use the same bar, the same speeds, and the
## same catch-up rule: simulate as fast as the machine allows, but yield to
## draw about ten times a second so a long seek still shows the world moving.

import
  std/times,
  chroma, pixie, silky, vmath, windy,
  actioncam, chrome, gameuis

const
  TransportHeight* = 80.0'f32
  PlayerSpeeds* = [1'i32, 2, 4, 16]
  CatchUpSeconds* = 0.1
  IconSize = 64.0'f32
  IconGap = 8.0'f32
  GroupGap = 24.0'f32
  IconPad = 8.0'f32
  ScrubH = 24.0'f32
  RecordedH = 6.0'f32
  RecordedGap = 4.0'f32
  TickLabelW = 178.0'f32
  SpeedIcons = ["speed_1x", "speed_2x", "speed_4x", "speed_16x"]
  GlyphColor = rgbx(226, 230, 239, 255)
  GlyphActive = rgbx(235, 216, 154, 255)
  GlyphDim = rgbx(112, 121, 138, 255)

type Player* = object
  playing*: bool
  repeating*: bool
  speedIndex*: int
  live*: bool
  tick*: int32
  recordedTicks*: int32
    ## How far the in-memory tape has been simulated.
  durationTicks*: int32
    ## Configured match length. Live scrubber uses this until the game ends.
  over*: bool
  restoreTick*: int32
    ## Checkpoint to restore before catching up. -1 means none.
  targetTick*: int32
    ## Catch up to this tick at max speed. -1 means none.
  accumulator*: float32
  tickRate: int32

proc speed*(player: Player): int32 =
  ## Returns the selected realtime multiplier.
  PlayerSpeeds[player.speedIndex]

proc timelineEnd*(player: Player): int32 =
  ## Returns the right edge of the scrubber.
  if player.live and not player.over:
    player.durationTicks
  else:
    max(player.recordedTicks, 0)

proc inHistory*(player: Player): bool =
  ## Returns whether the next tick should come from recorded actions.
  (not player.live) or player.tick < player.recordedTicks

proc speedIndexOf*(value: int32): int =
  ## Maps a requested multiplier onto 1x, 2x, 4x, or 16x.
  result = 0
  for i, speed in PlayerSpeeds:
    if speed <= value:
      result = i

proc initPlayer*(
    live: bool,
    durationTicks: int32,
    playing = true,
    speed = 1'i32
): Player =
  ## Creates a transport that starts in play unless asked to pause.
  result.live = live
  result.durationTicks = max(durationTicks, 0)
  result.playing = playing
  result.speedIndex = speedIndexOf(speed)
  result.restoreTick = -1
  result.targetTick = -1

proc sync*(
    player: var Player,
    tick,
    recordedTicks: int32,
    over: bool
) =
  ## Copies simulation progress into the transport.
  player.tick = max(tick, 0)
  player.recordedTicks = max(recordedTicks, 0)
  if over and not player.over:
    player.durationTicks = player.recordedTicks
  player.over = over
  if player.targetTick >= 0 and player.tick >= player.targetTick:
    player.targetTick = -1

proc seekTo*(player: var Player, tick: int32, play = true) =
  ## Jumps toward one timeline tick at max speed, restoring if going back.
  ## Backward seeks reload the last checkpoint at or before the target,
  ## then resimulate up to it.
  let wanted = clamp(tick, 0'i32, player.timelineEnd)
  if wanted < player.tick:
    player.restoreTick = wanted
  player.targetTick = wanted
  if play:
    player.playing = true

proc skipToStart*(player: var Player) =
  ## Jumps to the first timeline tick.
  player.seekTo(0)

proc skipToEnd*(player: var Player) =
  ## Jumps to the last timeline tick.
  player.seekTo(player.timelineEnd)

proc stepBack*(player: var Player) =
  ## Pauses and moves exactly one tick backward.
  ## Restores the last safe checkpoint and resimulates up to tick - 1.
  player.playing = false
  player.accumulator = 0
  player.seekTo(player.tick - 1, play = false)

proc stepForward*(player: var Player) =
  ## Pauses and moves exactly one tick forward.
  player.playing = false
  player.accumulator = 0
  player.seekTo(player.tick + 1, play = false)

proc pause*(player: var Player) =
  ## Stops realtime playback and any catch-up.
  player.playing = false
  player.targetTick = -1

proc play*(player: var Player) =
  ## Starts playback, rewinding first when already at the end.
  if player.tick >= player.timelineEnd and player.timelineEnd > 0:
    player.seekTo(0)
  else:
    player.playing = true

proc togglePlay*(player: var Player) =
  ## Flips between play and pause, including during catch-up.
  if player.playing or player.targetTick >= 0:
    player.pause()
  else:
    player.play()

proc setSpeed*(player: var Player, index: int) =
  ## Selects one of the four transport multipliers.
  player.speedIndex = clamp(index, 0, PlayerSpeeds.high)

proc reachedEnd(player: Player): bool =
  ## Returns whether playback has no further ticks to consume.
  if player.over:
    return true
  if player.live:
    return player.tick >= player.durationTicks
  player.recordedTicks > 0 and player.tick >= player.recordedTicks

proc takeRestore*(player: var Player): int32 =
  ## Returns the tick to land on after a checkpoint restore, or -1.
  result = player.restoreTick
  player.restoreTick = -1
  if result >= 0:
    player.accumulator = 0

proc startFrame*(player: var Player, dt: float32, tickRate: int32) =
  ## Accounts realtime time when not catching up.
  player.tickRate = max(tickRate, 1)
  if player.targetTick >= 0 or not player.playing:
    return
  player.accumulator = min(
    player.accumulator + dt * player.speed.float32,
    0.25'f32
  )

proc shouldTick*(
    player: var Player,
    frameStart: float64
): bool =
  ## Returns whether one more simulation tick belongs in this frame.
  ## Paused seeks run until they land so single-tick steps stay exact.
  if player.reachedEnd:
    if player.repeating:
      player.seekTo(0)
      return false
    player.playing = false
    player.targetTick = -1
    player.accumulator = 0
    return false
  if player.targetTick >= 0:
    if not player.playing:
      return player.tick < player.targetTick
    return epochTime() - frameStart < CatchUpSeconds
  if not player.playing:
    return false
  let step = 1.0'f32 / max(player.tickRate, 1).float32
  if player.accumulator >= step:
    player.accumulator -= step
    return true
  false

proc clicked(
    window: Window,
    sk: Silky,
    panel: GameUiPanel
): bool =
  ## Returns whether this frame pressed a transport button.
  window.buttonPressed[MouseLeft] and panel.contains(sk.mousePos)

proc drawTransport*(
    player: var Player,
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    actionCam: var ActionCam,
    followSelection: var bool
) =
  ## Draws the shared play/replay bar and applies clicks.
  ## A short panel (under 72px) uses compact glyphs so the strip can sit
  ## above a Warcraft 3-style bottom HUD.
  if panel.size.y <= 0:
    return
  let
    compact = panel.size.y < 72
    iconSize = if compact: max(panel.size.y - 4, 12) else: IconSize
    iconGap = if compact: 3.0'f32 else: IconGap
    iconPad = if compact: 2.0'f32 else: IconPad
    iconY = max((panel.size.y - iconSize) * 0.5'f32, 1)
    groupGap = if compact: 8.0'f32 else: GroupGap
    tickLabelW = if compact: 118.0'f32 else: TickLabelW
    scrubH = if compact: 6.0'f32 else: ScrubH
    recordedH = if compact: 2.0'f32 else: RecordedH
    recordedGap = if compact: 2.0'f32 else: RecordedGap
  sk.drawRibbon(panel)
  proc placeIcon(x: var float32): GameUiPanel =
    result = GameUiPanel(
      origin: panel.origin + vec2(x, iconY),
      size: vec2(iconSize)
    )
    x += iconSize + iconGap
  proc skipGroup(x: var float32) =
    x += groupGap - iconGap
  proc drawGlyph(name: string, glyph: GameUiPanel, color: ColorRGBX) =
    if name notin sk.atlas.entries:
      return
    let
      uv = sk.atlas.entries[name]
      size = vec2(max(iconSize - iconPad * 2, 8))
      pos = glyph.origin + vec2(iconPad)
    sk.drawQuad(
      pos,
      size,
      vec2(uv.x.float32, uv.y.float32),
      vec2(uv.width.float32, uv.height.float32),
      color
    )
  proc drawIcon(glyph: GameUiPanel, name: string, active = false, dim = false) =
    let color =
      if active: GlyphActive
      elif dim: GlyphDim
      else: GlyphColor
    drawGlyph(name, glyph, color)

  let playing = player.playing or player.targetTick >= 0
  var x = if compact: 8.0'f32 else: 12.0'f32
  let
    skipStart = placeIcon(x)
    stepBackBtn = placeIcon(x)
    playBtn = placeIcon(x)
    stepFwdBtn = placeIcon(x)
    skipEnd = placeIcon(x)
  skipGroup(x)
  let loopBtn = placeIcon(x)
  skipGroup(x)
  var speeds: array[4, GameUiPanel]
  for i in 0 .. 3:
    speeds[i] = placeIcon(x)
  drawIcon(skipStart, "skip_to_start")
  drawIcon(stepBackBtn, "previous_frame")
  drawIcon(playBtn, if playing: "pause" else: "play")
  drawIcon(stepFwdBtn, "next_frame")
  drawIcon(skipEnd, "skip_to_end")
  drawIcon(loopBtn, "loop", player.repeating)
  if window.clicked(sk, skipStart):
    player.skipToStart()
  elif window.clicked(sk, stepBackBtn):
    player.stepBack()
  elif window.clicked(sk, playBtn):
    player.togglePlay()
  elif window.clicked(sk, stepFwdBtn):
    player.stepForward()
  elif window.clicked(sk, skipEnd):
    player.skipToEnd()
  elif window.clicked(sk, loopBtn):
    player.repeating = not player.repeating
  for i, button in speeds:
    drawIcon(button, SpeedIcons[i], player.speedIndex == i)
    if window.clicked(sk, button):
      player.setSpeed(i)
  skipGroup(x)
  let
    clusterH = scrubH + recordedGap + recordedH
    scrubY = iconY + max(iconSize - clusterH, 0) * 0.5'f32
    camReserve = iconSize + groupGap
    scrubOrigin = panel.origin + vec2(x, scrubY)
    scrubSize = vec2(
      max(panel.size.x - x - tickLabelW - camReserve - 16, 80),
      scrubH
    )
    endTick = max(player.timelineEnd, 1)
  sk.drawBar(
    scrubOrigin,
    scrubSize,
    player.tick.float32,
    endTick.float32,
    rgbx(96, 132, 190, 255)
  )
  sk.drawBar(
    scrubOrigin + vec2(0, scrubSize.y + recordedGap),
    vec2(scrubSize.x, recordedH),
    player.recordedTicks.float32,
    endTick.float32,
    rgbx(151, 82, 199, 255)
  )
  let scrubHit = GameUiPanel(
    origin: scrubOrigin - vec2(0, 8),
    size: scrubSize + vec2(0, 24)
  )
  if window.buttonDown[MouseLeft] and scrubHit.contains(sk.mousePos):
    let ratio = clamp(
      (sk.mousePos.x - scrubOrigin.x) / scrubSize.x,
      0.0'f32,
      1.0'f32
    )
    player.seekTo(int32(ratio * player.timelineEnd.float32))
  let actionBtn = GameUiPanel(
    origin: panel.origin + vec2(x + scrubSize.x + groupGap, iconY),
    size: vec2(iconSize)
  )
  drawIcon(actionBtn, "action_cam", actionCam.enabled)
  if window.clicked(sk, actionBtn):
    actionCam.toggle(followSelection)
  hudScratch.setLen(0)
  hudScratch.add "Tick "
  hudScratch.addHudInt(player.tick.int)
  hudScratch.add " / "
  hudScratch.addHudInt(player.timelineEnd.int)
  discard sk.drawText(
    "Hud",
    hudScratch,
    panel.origin + vec2(panel.size.x - tickLabelW, scrubY),
    rgbx(190, 198, 214, 255),
    maxWidth = tickLabelW - 12,
    maxHeight = max(clusterH, iconSize),
    hAlign = RightAlign,
    vAlign = MiddleAlign
  )

proc handleKey*(player: var Player, button: Button) =
  ## Applies the shared space-to-pause shortcut.
  if button == KeySpace:
    player.togglePlay()
