## League-style floating HUD widgets for Polyworld games.
##
## The 3D world renders edge to edge; chrome floats over it in the
## corners (treeform's "Strategy Game Battle UI": widgets, not bars).
## A compact hero cluster sits bottom-center — portrait, title line,
## one command row, one upgrade row, and full-width vitals bars — and
## the minimap floats bottom-right with a mini-button chip row above
## it. A thin replay transport strip overlays the very bottom edge only
## while open; the floating widgets lift by its height.

import
  chroma, pixie, silky, vmath,
  chrome, gameuis, hudchips

const
  CompactTransportHeight* = 20.0'f32
  BottomHudMinWidth* = 1000.0'f32
    ## Wide enough that 1920×1080 stays at 1× UI scale.
  BottomHudMinGameHeight* = 430.0'f32
  BottomHudFill* = rgbx(10, 10, 14, 250)
  HudMargin* = 8.0'f32
  MinimapSize* = 184.0'f32
  MiniButtonH* = 16.0'f32
  MiniButtonGap = 4.0'f32
  ClusterPad = 4.0'f32
  ClusterInnerH = 80.0'f32
  ClusterHeight* = ClusterInnerH + ClusterPad * 2
  PortraitSide = ClusterInnerH
  PortraitGap = 6.0'f32
  TitleH = 14.0'f32
  TitleGap = 2.0'f32
  SlotSide = 36.0'f32
  SlotGap = 2.0'f32
  RowGroupGap = 8.0'f32
  BarsGap = 3.0'f32
  HpBarH = 11.0'f32
  BarGap = 2.0'f32
  ResourceBarH = 12.0'f32
  CommandSlots* = 5
  UpgradeSlots* = 4
  CommandsW = SlotSide * CommandSlots.float32 +
    SlotGap * (CommandSlots - 1).float32
  UpgradesW = SlotSide * UpgradeSlots.float32 +
    SlotGap * (UpgradeSlots - 1).float32
  RightBlockW = CommandsW + RowGroupGap + UpgradesW
  ClusterWidth* = ClusterPad * 2 + PortraitSide + PortraitGap + RightBlockW

type
  BottomHudLayout* = object
    bar*: GameUiPanel
      ## The hero cluster plate (hidden while nothing is inspected).
    portrait*: GameUiPanel
    title*: GameUiPanel
    commands*: GameUiPanel
    items*: GameUiPanel
      ## Optional inventory row between commands and upgrades.
    inventory*: GameUiPanel
    hpBar*: GameUiPanel
    resourceBar*: GameUiPanel
    minimap*: GameUiPanel
    buttons*: GameUiPanel
      ## Mini-button chip row riding above the minimap.

proc transportStripHeight*(visible: bool): float32 =
  ## Replay strip height, or 0 so the widgets sit flush to the bottom.
  if visible: CompactTransportHeight else: 0

proc slotRowWidth(count: int): float32 =
  if count <= 0:
    0'f32
  else:
    SlotSide * count.float32 + SlotGap * float32(count - 1)

proc placeBottomHud*(
    size: Vec2,
    transportHeight = 0.0'f32,
    commandCount = CommandSlots,
    itemCount = 0,
    upgradeCount = UpgradeSlots
): BottomHudLayout =
  ## Places the floating widgets: hero cluster bottom-center, minimap
  ## and its chip row bottom-right. `transportHeight` lifts everything
  ## above the replay strip while it is open. `itemCount` inserts an
  ## inventory row between commands and upgrades; 0 keeps the stock
  ## 5+4 layout.
  let
    commandsW = slotRowWidth(commandCount)
    itemsW = slotRowWidth(itemCount)
    upgradesW = slotRowWidth(upgradeCount)
    rightW =
      if itemCount > 0:
        commandsW + RowGroupGap + itemsW + RowGroupGap + upgradesW
      else:
        commandsW + RowGroupGap + upgradesW
    clusterW = ClusterPad * 2 + PortraitSide + PortraitGap + rightW
    floor = max(size.y - transportHeight, 0)
    clusterX = max((size.x - clusterW) * 0.5'f32, 0)
    clusterY = max(floor - ClusterHeight, 0)
  result.bar = GameUiPanel(
    origin: vec2(clusterX, clusterY),
    size: vec2(clusterW, ClusterHeight)
  )
  result.portrait = GameUiPanel(
    origin: result.bar.origin + vec2(ClusterPad),
    size: vec2(PortraitSide, PortraitSide)
  )
  let
    rightX = result.portrait.origin.x + PortraitSide + PortraitGap
    innerY = result.bar.origin.y + ClusterPad
  result.title = GameUiPanel(
    origin: vec2(rightX, innerY),
    size: vec2(rightW, TitleH)
  )
  let slotsY = innerY + TitleH + TitleGap
  result.commands = GameUiPanel(
    origin: vec2(rightX, slotsY),
    size: vec2(commandsW, SlotSide)
  )
  var cursorX = rightX + commandsW
  if itemCount > 0:
    cursorX += RowGroupGap
    result.items = GameUiPanel(
      origin: vec2(cursorX, slotsY),
      size: vec2(itemsW, SlotSide)
    )
    cursorX += itemsW
  else:
    result.items = GameUiPanel(
      origin: vec2(cursorX, slotsY),
      size: vec2(0, SlotSide)
    )
  result.inventory = GameUiPanel(
    origin: vec2(cursorX + RowGroupGap, slotsY),
    size: vec2(upgradesW, SlotSide)
  )
  let hpY = slotsY + SlotSide + BarsGap
  result.hpBar = GameUiPanel(
    origin: vec2(rightX, hpY),
    size: vec2(rightW, HpBarH)
  )
  result.resourceBar = GameUiPanel(
    origin: vec2(rightX, hpY + HpBarH + BarGap),
    size: vec2(rightW, ResourceBarH)
  )
  result.minimap = GameUiPanel(
    origin: vec2(
      max(size.x - HudMargin - MinimapSize, 0),
      max(floor - HudMargin - MinimapSize, 0)
    ),
    size: vec2(MinimapSize, MinimapSize)
  )
  result.buttons = GameUiPanel(
    origin: result.minimap.origin - vec2(0, MiniButtonGap + MiniButtonH),
    size: vec2(MinimapSize, MiniButtonH)
  )

proc compactTransportPanel*(
    size: Vec2,
    transportHeight = CompactTransportHeight
): GameUiPanel =
  ## Thin replay strip overlaying the very bottom edge of the window.
  ## `transportHeight = 0` hides it; the world stays full-screen either way.
  GameUiPanel(
    origin: vec2(0, max(size.y - transportHeight, 0)),
    size: vec2(max(size.x, 0), transportHeight)
  )

proc minimapInner*(panel: GameUiPanel, inset = 3.0'f32): GameUiPanel =
  ## Playable map rectangle inside the minimap frame.
  panel.inset(inset)

proc drawBottomChrome*(
    sk: Silky,
    hud: BottomHudLayout,
    showCluster: bool
) =
  ## Draws the floating plates: minimap frame always, the hero cluster
  ## only while a unit card is showing (spectators keep a clean screen).
  sk.drawEtched(hud.minimap.origin, hud.minimap.size, rgbx(16, 18, 16, 255))
  if not showCluster:
    return
  sk.drawEtched(hud.bar.origin, hud.bar.size, BottomHudFill)
  sk.drawEtched(hud.portrait.origin, hud.portrait.size, rgbx(16, 14, 18, 255))
