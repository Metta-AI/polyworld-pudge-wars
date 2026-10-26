## Corner HUD chips for Polyworld games.
##
## League-style floating chrome instead of a full-width Warcraft 3 bar:
## a team-colored score banner hangs from the top-center edge with a
## kill-race track under it, and small chip rows (menu, allies, log,
## replay) ride above the minimap.
## `drawEtched` is the shared dark plate with the double gold rim that
## the rest of the HUD builds on.

import
  chroma, pixie, silky, vmath, windy,
  bottomhud, chrome, gameuis

const
  HudGold* = rgbx(232, 208, 138, 255)
  HudGoldDim* = rgbx(168, 148, 96, 255)
  HudHotkey* = rgbx(96, 220, 90, 255)
  HudText* = rgbx(236, 232, 210, 255)
  HudChipFill* = rgbx(18, 22, 28, 255)
  HudChipActive* = rgbx(52, 44, 26, 255)
  ScorePlateSize* = vec2(440, 44)
    ## Top-center banner: west block, clock, east block.
  ScoreClockW = 88.0'f32
  ScoreTrackSize = vec2(360, 6)
  ScoreTrackGap = 4.0'f32
  ScoreBlockFill* = [rgbx(168, 50, 38, 242), rgbx(34, 76, 156, 242)]
  ScoreClockFill = rgbx(14, 14, 18, 248)
  ScoreTrackFill = rgbx(12, 12, 16, 230)
  ScoreTrackColors = [rgbx(255, 122, 102, 255), rgbx(111, 176, 255, 255)]
  ChipGap* = 4.0'f32

type
  ScorePlate* = object
    ## Top-center banner: team scores flank the match clock, and a
    ## track below shows each bank's race to the kill goal.
    west*: int
    east*: int
    killGoal*: int
    clock*: string
    youTeam*: int
      ## 0 west, 1 east, -1 when spectating (no YOU tag).

  HudChip* = object
    ## One mini button in a chip row (label plus optional hotkey).
    id*: int
    label*: string
    key*: Button
    active*: bool

proc drawEtched*(
    sk: Silky,
    origin, size: Vec2,
    fill: ColorRGBX,
    border = HudGold
) =
  ## Draws one dark plate with a double gold/beige rim.
  sk.drawRect(origin, size, border)
  sk.drawRect(origin + vec2(1), size - vec2(2), rgbx(48, 42, 32, 255))
  sk.drawRect(origin + vec2(2), size - vec2(4), fill)

proc scorePlatePanel*(layout: GameUiLayout): GameUiPanel =
  ## The score banner, flush with the top edge, plus its race track.
  GameUiPanel(
    origin: vec2((layout.size.x - ScorePlateSize.x) * 0.5'f32, 0),
    size: vec2(
      ScorePlateSize.x, ScorePlateSize.y + ScoreTrackGap + ScoreTrackSize.y
    )
  )

proc scoreBannerBottom*(layout: GameUiLayout): float32 =
  ## First free Y under the banner and its track.
  let panel = scorePlatePanel(layout)
  panel.origin.y + panel.size.y

proc hudToastY*(layout: GameUiLayout): float32 =
  ## Top of the right-hand kill feed column.
  layout.panel(GameUiRegion.TopRight, vec2(1)).origin.y

proc drawScorePlate*(
    sk: Silky,
    layout: GameUiLayout,
    plate: ScorePlate
) =
  ## Draws the banner: big team scores either side of the clock, then
  ## the kill-race track that fills outward from the center.
  let
    panel = scorePlatePanel(layout)
    o = panel.origin
    h = ScorePlateSize.y
    blockW = (ScorePlateSize.x - ScoreClockW) * 0.5'f32
    rise = 14.0'f32
      ## Rounded plates start above the screen so only the bottom
      ## corners show.
    westBlock = GameUiPanel(origin: o + vec2(0, -rise), size: vec2(blockW + 12, h + rise))
    eastBlock = GameUiPanel(
      origin: o + vec2(blockW + ScoreClockW - 12, -rise),
      size: vec2(blockW + 12, h + rise)
    )
    clockBlock = GameUiPanel(origin: o + vec2(blockW, 0), size: vec2(ScoreClockW, h))
  sk.drawRounded(
    GameUiPanel(origin: o + vec2(-2, -rise), size: vec2(ScorePlateSize.x + 4, h + rise + 2)),
    rgbx(0, 0, 0, 220), large = true
  )
  sk.drawRounded(westBlock, ScoreBlockFill[0], large = true)
  sk.drawRounded(eastBlock, ScoreBlockFill[1], large = true)
  sk.drawRect(clockBlock.origin, clockBlock.size, ScoreClockFill)
  let white = rgbx(255, 255, 255, 255)
  let teamText = rgbx(220, 220, 220, 220)
  # West: label then number, pushed against the clock.
  var westScore = ""
  westScore.addHudInt(plate.west)
  let
    numW = max(sk.getTextSize("B27", westScore).x, 30)
    westNum = GameUiPanel(origin: o + vec2(blockW - 12 - numW, 0), size: vec2(numW, h))
  sk.drawLabel(westScore, westNum.origin, westNum.size, white, "B27", RightAlign)
  let westLabelW = sk.getTextSize("B13", "WEST").x
  var labelRight = westNum.origin.x - 10
  if plate.youTeam == 0:
    let youW = sk.getTextSize("B11", "YOU").x + 10
    let you = GameUiPanel(origin: vec2(labelRight - youW, o.y + h * 0.5'f32 - 9), size: vec2(youW, 18))
    sk.drawRounded(you, white)
    sk.drawLabel("YOU", you.origin, you.size, rgbx(122, 31, 20, 255), "B11", CenterAlign)
    labelRight = you.origin.x - 8
  sk.drawLabel(
    "WEST", vec2(labelRight - westLabelW, o.y), vec2(westLabelW, h), teamText, "B13"
  )
  # East: number then label, pushed against the clock.
  var eastScore = ""
  eastScore.addHudInt(plate.east)
  let eastNum = GameUiPanel(
    origin: o + vec2(blockW + ScoreClockW + 12, 0),
    size: vec2(max(sk.getTextSize("B27", eastScore).x, 30), h)
  )
  sk.drawLabel(eastScore, eastNum.origin, eastNum.size, white, "B27")
  var labelLeft = eastNum.origin.x + eastNum.size.x + 10
  let eastLabelW = sk.getTextSize("B13", "EAST").x
  sk.drawLabel("EAST", vec2(labelLeft, o.y), vec2(eastLabelW, h), teamText, "B13")
  if plate.youTeam == 1:
    labelLeft += eastLabelW + 8
    let youW = sk.getTextSize("B11", "YOU").x + 10
    let you = GameUiPanel(origin: vec2(labelLeft, o.y + h * 0.5'f32 - 9), size: vec2(youW, 18))
    sk.drawRounded(you, white)
    sk.drawLabel("YOU", you.origin, you.size, rgbx(20, 50, 110, 255), "B11", CenterAlign)
  # Clock and goal.
  sk.drawLabel(
    plate.clock, clockBlock.origin + vec2(0, 2), vec2(ScoreClockW, 23),
    white, "B17", CenterAlign
  )
  if plate.killGoal > 0:
    var goal = "FIRST TO "
    goal.addHudInt(plate.killGoal)
    sk.drawLabel(
      goal, clockBlock.origin + vec2(0, h - 18), vec2(ScoreClockW, 16),
      HudGold, "B11", CenterAlign
    )
  # Kill-race track: west fills left of center, east fills right.
  let track = GameUiPanel(
    origin: vec2(
      (layout.size.x - ScoreTrackSize.x) * 0.5'f32,
      o.y + h + ScoreTrackGap
    ),
    size: ScoreTrackSize
  )
  sk.drawRoundedFramed(track, ScoreTrackFill, rgbx(0, 0, 0, 230))
  if plate.killGoal > 0:
    let
      inner = track.inset(2)
      half = inner.size.x * 0.5'f32
      mid = inner.origin.x + half
      westW = half * clamp(plate.west / plate.killGoal, 0.0, 1.0).float32
      eastW = half * clamp(plate.east / plate.killGoal, 0.0, 1.0).float32
    if westW > 0:
      sk.drawRect(vec2(mid - westW, inner.origin.y), vec2(westW, inner.size.y), ScoreTrackColors[0])
    if eastW > 0:
      sk.drawRect(vec2(mid, inner.origin.y), vec2(eastW, inner.size.y), ScoreTrackColors[1])
    sk.drawRect(vec2(mid - 1, track.origin.y - 2), vec2(2, track.size.y + 4), HudGold)

proc chipSlot*(panel: GameUiPanel, index, count: int): GameUiPanel =
  ## Returns one evenly split chip inside a row panel.
  let
    n = max(count, 1).float32
    w = max((panel.size.x - ChipGap * (n - 1)) / n, 1)
  GameUiPanel(
    origin: panel.origin + vec2(index.float32 * (w + ChipGap), 0),
    size: vec2(w, panel.size.y)
  )

proc drawChipRow*(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    chips: openArray[HudChip]
): int =
  ## Draws a row of mini buttons and returns the pressed id, or -1.
  ## A chip fires on click or on its bound key.
  result = -1
  for i, chip in chips:
    let slot = chipSlot(panel, i, chips.len)
    sk.drawEtched(
      slot.origin,
      slot.size,
      if chip.active: HudChipActive else: HudChipFill
    )
    sk.drawLabel(
      chip.label,
      slot.origin,
      slot.size,
      if chip.active: HudGold else: HudText,
      "Small",
      CenterAlign
    )
    if window.clicked(sk, slot) or
        (chip.key != ButtonUnknown and window.buttonPressed[chip.key]):
      result = chip.id
