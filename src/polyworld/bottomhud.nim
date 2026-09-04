## League-style floating HUD widgets for Polyworld games.
##
## The 3D world renders edge to edge; chrome floats over it in the
## corners (treeform's "Strategy Game Battle UI": widgets, not bars).
## The hero cluster uses Call to Adventure's textured plates: a profile
## card (portrait + vitals) beside the action bar (ability wells, items,
## upgrades, and a long status well). The minimap uses CTA's circular
## bronze compass plate. A single Menu control sits on the nameplate;
## Debug, Allies, Log, and Replay live on the pause menu.
## A thin replay transport strip overlays the very bottom edge only
## while open; the floating widgets lift by its height.

import
  chroma, silky, vmath,
  chrome, gameuis

const
  CompactTransportHeight* = 20.0'f32
  BottomHudMinWidth* = 1640.0'f32
    ## Profile card + action plate + circular compass at 1×.
    ## 1920×1080 stays 1×; 1280×800 steps down to 0.5×.
  BottomHudMinGameHeight* = 430.0'f32
  BottomHudFill* = rgbx(10, 10, 14, 250)
  HudMargin* = 8.0'f32
  MinimapPanelSize* = vec2(334, 338)
  MinimapSize* = MinimapPanelSize.x
    ## Cropped compass: ring, title, and nameplate. No quest well.
  MiniButtonH* = 28.0'f32
  ProfilePanelSize* = vec2(316, 104)
  ActionsPanelSize* = vec2(947, 157)
  ClusterGap = 10.0'f32
  MinimapClusterGap = 12.0'f32
  ClusterWidth* = ProfilePanelSize.x + ClusterGap + ActionsPanelSize.x
  ClusterHeight* = ActionsPanelSize.y
  MinimapMapSlot = (x: 66.0'f32, y: 40.0'f32, w: 252.0'f32, h: 252.0'f32)
  MinimapTitleSlot = (x: 102.0'f32, y: 4.0'f32, w: 186.0'f32, h: 24.0'f32)
  MinimapNameSlot = (x: 140.0'f32, y: 304.0'f32, w: 114.0'f32, h: 28.0'f32)
  AbilitySlotXs = [
    30.0'f32, 127, 222, 315, 409, 503, 620, 702, 784, 863
  ]
  AbilitySlotYs = [
    15.0'f32, 15, 15, 15, 15, 15, 23, 23, 23, 23
  ]
  AbilitySlotWs = [
    79.0'f32, 76, 75, 77, 76, 76, 62, 63, 61, 61
  ]
  AbilitySlotHs = [
    82.0'f32, 82, 82, 82, 82, 82, 64, 64, 64, 64
  ]
  AbilityIconGrow* = 8.0'f32
  PortraitSlot = (x: 6.0'f32, y: 7.0'f32, w: 86.0'f32, h: 91.0'f32)
  HpSlot = (x: 111.0'f32, y: 44.0'f32, w: 193.0'f32, h: 20.0'f32)
  ResourceSlot = (x: 111.0'f32, y: 67.0'f32, w: 193.0'f32, h: 25.0'f32)
  XpSlot = (x: 29.0'f32, y: 124.0'f32, w: 741.0'f32, h: 21.0'f32)
  GoldSlot = (x: 783.0'f32, y: 116.0'f32, w: 74.0'f32, h: 24.0'f32)
  GemSlot = (x: 869.0'f32, y: 116.0'f32, w: 57.0'f32, h: 24.0'f32)
  ActionSlotCount* = 10
  CommandSlots* = 5
  UpgradeSlots* = 4

type
  BottomHudLayout* = object
    bar*: GameUiPanel
      ## Combined profile + action cluster (hidden while nothing is inspected).
    profile*: GameUiPanel
      ## Call to Adventure leftTop plate: portrait and vitals.
    actions*: GameUiPanel
      ## Call to Adventure bottomCenter plate: ability wells and status.
    portrait*: GameUiPanel
    title*: GameUiPanel
    commands*: GameUiPanel
    items*: GameUiPanel
      ## Optional inventory row between commands and upgrades.
    inventory*: GameUiPanel
    hpBar*: GameUiPanel
    resourceBar*: GameUiPanel
    xpBar*: GameUiPanel
    goldBox*: GameUiPanel
    gemBox*: GameUiPanel
    minimap*: GameUiPanel
    minimapTitle*: GameUiPanel
    minimapName*: GameUiPanel
    buttons*: GameUiPanel
      ## Single Menu control on the compass nameplate.

proc transportStripHeight*(visible: bool): float32 =
  ## Replay strip height, or 0 so the widgets sit flush to the bottom.
  if visible: CompactTransportHeight else: 0

proc actionWell*(actions: GameUiPanel, index: int): GameUiPanel =
  ## Returns one art-space ability well on the action plate.
  let i = clamp(index, 0, ActionSlotCount - 1)
  actions.imageSlot(
    AbilitySlotXs[i],
    AbilitySlotYs[i],
    AbilitySlotWs[i],
    AbilitySlotHs[i]
  )

proc actionWellGrown*(
    actions: GameUiPanel,
    index: int,
    grow = AbilityIconGrow
): GameUiPanel =
  ## Ability well expanded so the icon tucks under the bronze rim.
  let i = clamp(index, 0, ActionSlotCount - 1)
  actions.imageSlot(
    AbilitySlotXs[i] - grow,
    AbilitySlotYs[i] - grow,
    AbilitySlotWs[i] + grow * 2,
    AbilitySlotHs[i] + grow * 2
  )

proc wellBounds(actions: GameUiPanel, first, last: int): GameUiPanel =
  ## Axis-aligned box covering a contiguous run of action wells.
  var
    x0 = AbilitySlotXs[first]
    y0 = AbilitySlotYs[first]
    x1 = AbilitySlotXs[first] + AbilitySlotWs[first]
    y1 = AbilitySlotYs[first] + AbilitySlotHs[first]
  for i in first .. last:
    x0 = min(x0, AbilitySlotXs[i])
    y0 = min(y0, AbilitySlotYs[i])
    x1 = max(x1, AbilitySlotXs[i] + AbilitySlotWs[i])
    y1 = max(y1, AbilitySlotYs[i] + AbilitySlotHs[i])
  actions.imageSlot(x0, y0, x1 - x0, y1 - y0)

proc placeBottomHud*(
    size: Vec2,
    transportHeight = 0.0'f32,
    commandCount = CommandSlots,
    itemCount = 0,
    upgradeCount = UpgradeSlots
): BottomHudLayout =
  ## Places the floating widgets: CTA profile + action plates bottom-center
  ## (shifted left of the minimap), minimap and its chip row bottom-right.
  ## `transportHeight` lifts everything above the replay strip while it is
  ## open. Slot-count arguments are kept so callers compile; the plates are
  ## native Call to Adventure art and do not stretch with slot count.
  discard commandCount
  discard itemCount
  discard upgradeCount
  let
    floor = max(size.y - transportHeight, 0)
    minimapLeft = max(size.x - HudMargin - MinimapPanelSize.x, 0)
    availRight = max(minimapLeft - MinimapClusterGap, 0)
    clusterX = max((availRight - ClusterWidth) * 0.5'f32, HudMargin)
    clusterY = max(floor - ClusterHeight, 0)
  result.bar = GameUiPanel(
    origin: vec2(clusterX, clusterY),
    size: vec2(ClusterWidth, ClusterHeight)
  )
  result.profile = GameUiPanel(
    origin: vec2(clusterX, max(floor - ProfilePanelSize.y, 0)),
    size: ProfilePanelSize
  )
  result.actions = GameUiPanel(
    origin: vec2(clusterX + ProfilePanelSize.x + ClusterGap, clusterY),
    size: ActionsPanelSize
  )
  result.portrait = result.profile.imageSlot(
    PortraitSlot.x, PortraitSlot.y, PortraitSlot.w, PortraitSlot.h
  )
  result.hpBar = result.profile.imageSlot(
    HpSlot.x, HpSlot.y, HpSlot.w, HpSlot.h
  )
  result.resourceBar = result.profile.imageSlot(
    ResourceSlot.x, ResourceSlot.y, ResourceSlot.w, ResourceSlot.h
  )
  result.title = result.hpBar
  result.commands = wellBounds(result.actions, 0, 3)
  result.items = wellBounds(result.actions, 4, 5)
  result.inventory = wellBounds(result.actions, 6, 9)
  result.xpBar = result.actions.imageSlot(
    XpSlot.x, XpSlot.y, XpSlot.w, XpSlot.h
  )
  result.goldBox = result.actions.imageSlot(
    GoldSlot.x, GoldSlot.y, GoldSlot.w, GoldSlot.h
  )
  result.gemBox = result.actions.imageSlot(
    GemSlot.x, GemSlot.y, GemSlot.w, GemSlot.h
  )
  result.minimap = GameUiPanel(
    origin: vec2(
      max(size.x - HudMargin - MinimapPanelSize.x, 0),
      max(floor - MinimapPanelSize.y, 0)
    ),
    size: MinimapPanelSize
  )
  result.minimapTitle = result.minimap.imageSlot(
    MinimapTitleSlot.x, MinimapTitleSlot.y,
    MinimapTitleSlot.w, MinimapTitleSlot.h
  )
  result.minimapName = result.minimap.imageSlot(
    MinimapNameSlot.x, MinimapNameSlot.y,
    MinimapNameSlot.w, MinimapNameSlot.h
  )
  result.buttons = result.minimapName

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

proc minimapMap*(panel: GameUiPanel): GameUiPanel =
  ## Square that bounds the circular compass well.
  panel.imageSlot(
    MinimapMapSlot.x, MinimapMapSlot.y,
    MinimapMapSlot.w, MinimapMapSlot.h
  )

proc minimapInner*(panel: GameUiPanel, inset = 3.0'f32): GameUiPanel =
  ## Playable map well. The bronze ring defines the clip, not `inset`.
  discard inset
  panel.minimapMap()

proc insideMinimapCircle*(area: GameUiPanel, point: Vec2): bool =
  ## True when a point sits inside the circular map well.
  let
    radius = area.size.x * 0.5'f32
    delta = point - (area.origin + vec2(radius))
  delta.x * delta.x + delta.y * delta.y <= radius * radius

proc drawBottomChrome*(
    sk: Silky,
    hud: BottomHudLayout,
    showCluster: bool
) =
  ## Theme window chrome behind the cluster and compass.
  if showCluster:
    sk.drawPanel(hud.profile)
    sk.drawFrame(hud.profile.inset(2))
    sk.drawPanel(hud.actions)
    sk.drawFrame(hud.actions.inset(2))
  sk.drawPanel(hud.minimap)
  sk.drawFrame(hud.minimap.inset(2))
