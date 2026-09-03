## Corner HUD chips for Polyworld games.
##
## League-style floating chrome instead of a full-width Warcraft 3 bar:
## a compact score/clock plate anchors the top-right corner and small
## chip rows (menu, allies, log, replay) ride above the minimap.
## `drawEtched` is the shared dark plate with the double gold rim that
## the rest of the HUD builds on.

import
  chroma, pixie, silky, vmath, windy,
  chrome, gameuis

const
  HudGold* = rgbx(232, 208, 138, 255)
  HudGoldDim* = rgbx(168, 148, 96, 255)
  HudHotkey* = rgbx(96, 220, 90, 255)
  HudText* = rgbx(236, 232, 210, 255)
  HudChipFill* = rgbx(18, 22, 28, 255)
  HudChipActive* = rgbx(52, 44, 26, 255)
  ScorePlateSize* = vec2(190, 24)
  ChipGap* = 4.0'f32

type
  ScorePlate* = object
    ## Top-right corner readout: team scores flank the match clock.
    west*: string
    east*: string
    westColor*: ColorRGBX
    eastColor*: ColorRGBX
    clock*: string

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
  ## Where the top-right score plate sits.
  layout.panel(GameUiRegion.TopRight, ScorePlateSize)

proc hudToastY*(layout: GameUiLayout): float32 =
  ## First free Y below the score plate, for toasts and the kill feed.
  let plate = layout.panel(GameUiRegion.TopRight, ScorePlateSize)
  plate.origin.y + plate.size.y + 6.0'f32

proc drawScorePlate*(
    sk: Silky,
    layout: GameUiLayout,
    plate: ScorePlate
) =
  ## Draws the corner plate: west score, match clock, east score.
  let panel = scorePlatePanel(layout)
  sk.drawEtched(panel.origin, panel.size, HudChipFill)
  sk.drawLabel(
    plate.west,
    panel.origin + vec2(6, 0),
    vec2(panel.size.x * 0.34'f32, panel.size.y),
    plate.westColor,
    "Hud"
  )
  sk.drawLabel(
    plate.clock,
    panel.origin,
    panel.size,
    HudText,
    "Hud",
    CenterAlign
  )
  sk.drawLabel(
    plate.east,
    panel.origin + vec2(panel.size.x * 0.66'f32 - 6, 0),
    vec2(panel.size.x * 0.34'f32, panel.size.y),
    plate.eastColor,
    "Hud",
    RightAlign
  )

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
