## League-style floating HUD widgets for Polyworld games.
##
## The 3D world renders edge to edge; chrome floats over it in the
## corners (treeform's "Strategy Game Battle UI": widgets, not bars).
## The hero bar is one compact plate bottom-center: portrait, name, HP
## and gold, four round ability wells with big key badges and names,
## labelled upgrade buttons, and any carried items. The minimap uses
## CTA's circular bronze compass plate. A thin replay transport strip
## overlays the very bottom edge only while open; the floating widgets
## lift by its height.

import
  chroma, pixie, silky, vmath,
  chrome, gameuis

const
  CompactTransportHeight* = 20.0'f32
  BottomHudMinWidth* = 1100.0'f32
    ## Room for the compact hero bar with a full bag and the minimap.
  BottomHudMinGameHeight* = 720.0'f32
    ## Room for the chat, the shop, and the hero bar stacked on the left.
  BottomHudFill* = rgbx(10, 10, 14, 250)
  HudMargin* = 8.0'f32
  MinimapPanelSize* = vec2(208, 240)
  MinimapSize* = MinimapPanelSize.x
    ## Cropped compass: ring, title, and nameplate. No quest well.
  MiniButtonH* = 24.0'f32
  MinimapClusterGap = 12.0'f32
  MinimapMapSlot = (x: 12.0'f32, y: 24.0'f32, w: 184.0'f32, h: 184.0'f32)
  MinimapTitleSlot = (x: 12.0'f32, y: 4.0'f32, w: 184.0'f32, h: 18.0'f32)
  MinimapNameSlot = (x: 12.0'f32, y: 212.0'f32, w: 184.0'f32, h: MiniButtonH)
  AbilityCount* = 4
  UpgradeSlots* = 4
  BagSlots* = 6
  BarPadX = 10.0'f32
  BarPadY = 8.0'f32
  BarGap = 8.0'f32
  BarHeight* = 88.0'f32
  VitalsWidth = 158.0'f32
  PortraitSize = 30.0'f32
  AbilityWellSize* = 48.0'f32
  AbilityColumn = 52.0'f32
  KeyBadgeH* = 20.0'f32
  DividerW = 2.0'f32
  UpgradeButtonSize* = vec2(116, 24)
  UpgradeGap = 4.0'f32
  BagWellSize* = 24.0'f32
  BagCols = 3
  BagGap = 4.0'f32
  SectionTitleH* = 14.0'f32
  ## Generated atlas shapes (see `addHudShapes`). Tint them with color.
  HudDisc* = "hud.disc"
  HudRing* = "hud.ring"
  HudRound6* = "hud.round6"
  HudRound6Patch* = 8
  HudRound10* = "hud.round10"
  HudRound10Patch* = 12

type
  BottomHudLayout* = object
    bar*: GameUiPanel
      ## The whole hero plate (hidden while nothing is inspected).
    portrait*: GameUiPanel
    name*: GameUiPanel
    level*: GameUiPanel
    hpBar*: GameUiPanel
    goldLine*: GameUiPanel
    abilities*: array[AbilityCount, GameUiPanel]
      ## Round well bounds; key badge and name hang below each.
    dividers*: seq[GameUiPanel]
    upgradeTitle*: GameUiPanel
    upgrades*: array[UpgradeSlots, GameUiPanel]
    bagTitle*: GameUiPanel
    bag*: seq[GameUiPanel]
      ## One well per carried item; empty when the bag is empty.
    minimap*: GameUiPanel
    minimapTitle*: GameUiPanel
    minimapName*: GameUiPanel
    buttons*: GameUiPanel
      ## Single Menu control on the compass nameplate.

proc transportStripHeight*(visible: bool): float32 =
  ## Replay strip height, or 0 so the widgets sit flush to the bottom.
  if visible: CompactTransportHeight else: 0

proc keyBadge*(well: GameUiPanel, width: float32): GameUiPanel =
  ## Key badge centered on the bottom rim of a round ability well.
  GameUiPanel(
    origin: vec2(
      well.origin.x + (well.size.x - width) * 0.5'f32,
      well.origin.y + well.size.y - KeyBadgeH * 0.55'f32
    ),
    size: vec2(width, KeyBadgeH)
  )

proc abilityName*(well: GameUiPanel): GameUiPanel =
  ## Name line under an ability well's key badge.
  GameUiPanel(
    origin: vec2(
      well.origin.x - (AbilityColumn - AbilityWellSize) * 0.5'f32 - 6,
      well.origin.y + well.size.y + KeyBadgeH * 0.45'f32
    ),
    size: vec2(AbilityColumn + 12, 16)
  )

proc heroBarWidth*(bagCount: int): float32 =
  ## Plate width: vitals, abilities, upgrades, and the bag when used.
  result = BarPadX * 2 + VitalsWidth + BarGap +
    AbilityCount.float32 * AbilityColumn +
    (AbilityCount - 1).float32 * BarGap +
    BarGap + DividerW + BarGap +
    UpgradeButtonSize.x * 2 + UpgradeGap
  if bagCount > 0:
    let cols = min(bagCount, BagCols).float32
    result += BarGap + DividerW + BarGap +
      cols * BagWellSize + (cols - 1) * BagGap

proc placeBottomHud*(
    size: Vec2,
    transportHeight = 0.0'f32,
    bagCount = 0
): BottomHudLayout =
  ## Places the floating widgets: the hero plate bottom-center (nudged
  ## left only when it would touch the compass), the minimap and its
  ## chip row bottom-right. `transportHeight` lifts everything above the
  ## replay strip while it is open.
  let
    bagN = clamp(bagCount, 0, BagSlots)
    floor = max(size.y - transportHeight, 0)
    minimapLeft = max(size.x - HudMargin - MinimapPanelSize.x, 0)
    width = heroBarWidth(bagN)
    centered = (size.x - width) * 0.5'f32
    barX = max(min(centered, minimapLeft - MinimapClusterGap - width), HudMargin)
    barY = max(floor - HudMargin - BarHeight, 0)
    o = vec2(barX, barY)
  result.bar = GameUiPanel(origin: o, size: vec2(width, BarHeight))
  var x = BarPadX
  let top = BarPadY
  result.portrait = result.bar.imageSlot(x, top, PortraitSize, PortraitSize)
  result.name = result.bar.imageSlot(
    x + PortraitSize + 8, top + 1, VitalsWidth - PortraitSize - 8, 18
  )
  result.level = result.bar.imageSlot(
    x + PortraitSize + 8, top + 17, VitalsWidth - PortraitSize - 8, 14
  )
  result.hpBar = result.bar.imageSlot(x, top + PortraitSize + 4, VitalsWidth, 18)
  result.goldLine = result.bar.imageSlot(
    x, top + PortraitSize + 24, VitalsWidth, 18
  )
  x += VitalsWidth + BarGap
  for i in 0 ..< AbilityCount:
    result.abilities[i] = result.bar.imageSlot(
      x + (AbilityColumn - AbilityWellSize) * 0.5'f32, top,
      AbilityWellSize, AbilityWellSize
    )
    x += AbilityColumn + (if i < AbilityCount - 1: BarGap else: 0)
  x += BarGap
  result.dividers.add result.bar.imageSlot(
    x, top, DividerW, BarHeight - BarPadY * 2
  )
  x += DividerW + BarGap
  let gridTop = top + 20
  result.upgradeTitle = result.bar.imageSlot(
    x, top + 1, UpgradeButtonSize.x * 2 + UpgradeGap, SectionTitleH
  )
  for i in 0 ..< UpgradeSlots:
    result.upgrades[i] = result.bar.imageSlot(
      x + (i mod 2).float32 * (UpgradeButtonSize.x + UpgradeGap),
      gridTop + (i div 2).float32 * (UpgradeButtonSize.y + UpgradeGap),
      UpgradeButtonSize.x, UpgradeButtonSize.y
    )
  x += UpgradeButtonSize.x * 2 + UpgradeGap
  if bagN > 0:
    x += BarGap
    result.dividers.add result.bar.imageSlot(
      x, top, DividerW, BarHeight - BarPadY * 2
    )
    x += DividerW + BarGap
    let cols = min(bagN, BagCols)
    result.bagTitle = result.bar.imageSlot(
      x, top + 1, cols.float32 * (BagWellSize + BagGap), SectionTitleH
    )
    for i in 0 ..< bagN:
      result.bag.add result.bar.imageSlot(
        x + (i mod BagCols).float32 * (BagWellSize + BagGap),
        gridTop + (i div BagCols).float32 * (BagWellSize + BagGap),
        BagWellSize, BagWellSize
      )
  result.minimap = GameUiPanel(
    origin: vec2(minimapLeft, max(floor - HudMargin - MinimapPanelSize.y, 0)),
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

proc roundedImage(size, radius: int, color = rgba(255, 255, 255, 255)): Image =
  result = newImage(size, size)
  let ctx = newContext(result)
  ctx.fillStyle = color
  ctx.fillRoundedRect(rect(0, 0, size.float32, size.float32), radius.float32)

proc roundIcon*(icon: Image, size = 128): Image =
  ## Circle-cropped copy of a square ability icon.
  let mask = newImage(size, size)
  let ctx = newContext(mask)
  ctx.fillStyle = rgba(255, 255, 255, 255)
  ctx.fillCircle(circle(vec2(size.float32 * 0.5'f32), size.float32 * 0.5'f32))
  result = icon.resize(size, size)
  result.draw(mask, blendMode = MaskBlend)

proc addHudShapes*(builder: AtlasBuilder) =
  ## White shapes the HUD tints at draw time: a disc, a ring, and two
  ## rounded-rect 9-patches for plates, badges, and buttons.
  let
    disc = newImage(128, 128)
    ring = newImage(128, 128)
  block:
    let ctx = newContext(disc)
    ctx.fillStyle = rgba(255, 255, 255, 255)
    ctx.fillCircle(circle(vec2(64, 64), 64))
  block:
    let ctx = newContext(ring)
    ctx.strokeStyle = rgba(255, 255, 255, 255)
    ctx.lineWidth = 7
    ctx.strokeCircle(circle(vec2(64, 64), 60.5))
  for (name, image) in [
    (HudDisc, disc),
    (HudRing, ring),
    (HudRound6, roundedImage(HudRound6Patch * 2 + 2, 6)),
    (HudRound10, roundedImage(HudRound10Patch * 2 + 2, 10))
  ]:
    if not builder.addImage(name, image):
      raise newException(ValueError, "the UI atlas is too small for " & name)

proc drawRounded*(
    sk: Silky,
    panel: GameUiPanel,
    color: ColorRGBX,
    large = false
) =
  ## Rounded-corner fill from the generated 9-patches.
  if large:
    sk.draw9Patch(HudRound10, HudRound10Patch, panel.origin, panel.size, color)
  else:
    sk.draw9Patch(HudRound6, HudRound6Patch, panel.origin, panel.size, color)

proc drawRoundedFramed*(
    sk: Silky,
    panel: GameUiPanel,
    fill, border: ColorRGBX,
    large = false,
    rim = 2.0'f32
) =
  ## Rounded plate with a solid rim.
  sk.drawRounded(panel, border, large)
  sk.drawRounded(panel.inset(rim), fill, large)

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
  ## Theme window chrome behind the hero plate and compass.
  if showCluster:
    sk.drawPanel(hud.bar)
    sk.drawFrame(hud.bar.inset(2))
    for divider in hud.dividers:
      sk.drawRect(divider.origin, divider.size, rgbx(61, 54, 40, 255))
  sk.drawPanel(hud.minimap)
  sk.drawFrame(hud.minimap.inset(2))
