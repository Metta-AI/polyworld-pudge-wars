## Pudge's HUD geometry, shared by drawing, tooltips and mouse hit testing.
##
## Compact corner panels and a centered hero card leave the arena visible.
## A 1600×1080-class layout keeps the three bottom plates. Smaller layouts
## (phones, portrait tablets) shrink those plates, then reflow into one bar
## once shrinking would make the type unreadable. `screenHudScale` is what
## the browser viewer uses so a point stays a point on a dense screen.

import vmath, polyworld/gameuis

const
  HudMargin* = 10.0'f32
  HeroPanelSize* = vec2(600, 168)
  MinimapPanelSize* = vec2(164, 190)
  MinimapSize* = MinimapPanelSize.x
  PanelInventory* = vec2(172, 174)
  ChatPanelSize* = vec2(300, 144)
  ShopPanelSize* = vec2(400, 360)
  ActionSlotCount* = 10
  ## Narrowest layout that still holds minimap, hero card and inventory
  ## without overlap, including the shop stacked above the inventory.
  DesktopFitWidth = 980.0'f32
  DesktopFitHeight = 560.0'f32
  ## Below this, scaled desktop plates clip the 12px labels.
  MinDesktopFit = 0.72'f32

type
  PudgeHudLayout* = object
    bar*, portrait*, title*, attackCaption*: GameUiPanel
    hpBar*, resourceBar*, gemBox*: GameUiPanel
    abilitiesTitle*, upgradesTitle*: GameUiPanel
    actions*: array[ActionSlotCount, GameUiPanel]
    minimap*, minimapTitle*, buttons*: GameUiPanel
    inventory*, chat*, shop*: GameUiPanel

proc pudgeHudScale*(windowSize: Vec2): float32 =
  ## Height drives readability; extra ultrawide width becomes open play space.
  clamp(min(windowSize.x / 1600, windowSize.y / 1080), 0.25'f32, 1.25'f32)

proc screenHudScale*(windowSize: Vec2, density: float32): float32 =
  ## Browser viewers pass the display density. Type then matches a desktop
  ## point, and a large 1× window can still grow through the height scale.
  max(clamp(density, 1.0'f32, 3.0'f32), pudgeHudScale(windowSize))

proc slot(panel: GameUiPanel, x, y, w, h: float32): GameUiPanel =
  GameUiPanel(origin: panel.origin + vec2(x, y), size: vec2(w, h))

proc minimapMap*(panel: GameUiPanel): GameUiPanel =
  ## Square map with a narrow caption and controls beneath it.
  let
    x = panel.size.x * (8.0'f32 / MinimapPanelSize.x)
    y = panel.size.y * (16.0'f32 / MinimapPanelSize.y)
    side = panel.size.x * (148.0'f32 / MinimapPanelSize.x)
  panel.slot(x, y, side, side)

proc dressMinimap(hud: var PudgeHudLayout, panel: GameUiPanel) =
  ## Title and button row use the same ratios as the desktop plate.
  let
    x = panel.size.x * (8.0'f32 / MinimapPanelSize.x)
    inner = panel.size.x * (148.0'f32 / MinimapPanelSize.x)
  hud.minimap = panel
  hud.minimapTitle = panel.slot(
    x,
    panel.size.y * (3.0'f32 / MinimapPanelSize.y),
    inner,
    panel.size.y * (12.0'f32 / MinimapPanelSize.y))
  hud.buttons = panel.slot(
    x,
    panel.size.y * (166.0'f32 / MinimapPanelSize.y),
    inner,
    panel.size.y * (22.0'f32 / MinimapPanelSize.y))

proc placeDesktop(
    size: Vec2,
    transportHeight, g: float32
): PudgeHudLayout =
  ## Three bottom anchors. `g` is 1 on a desktop layout and smaller when
  ## the window can still hold that arrangement, just not at full size.
  let layout = initGameUiLayout(size, transportHeight, HudMargin * g)
  result.bar = layout.panel(GameUiRegion.BottomCenter, HeroPanelSize * g)
  result.minimap = layout.panel(GameUiRegion.BottomLeft, MinimapPanelSize * g)
  result.inventory = layout.panel(GameUiRegion.BottomRight, PanelInventory * g)
  result.dressMinimap(result.minimap)
  result.chat = GameUiPanel(
    origin: vec2(HudMargin * g, result.minimap.origin.y - (ChatPanelSize.y + 8) * g),
    size: ChatPanelSize * g)
  result.shop = GameUiPanel(
    origin: vec2(size.x - (HudMargin + ShopPanelSize.x) * g,
      result.inventory.origin.y - (ShopPanelSize.y + 8) * g),
    size: ShopPanelSize * g)
  let card = result.bar
  result.portrait = card.slot(12 * g, 12 * g, 88 * g, 96 * g)
  result.title = card.slot(116 * g, 10 * g, 358 * g, 18 * g)
  result.gemBox = card.slot(490 * g, 12 * g, 98 * g, 18 * g)
  result.hpBar = card.slot(116 * g, 34 * g, 358 * g, 18 * g)
  result.resourceBar = card.slot(116 * g, 58 * g, 358 * g, 18 * g)
  result.abilitiesTitle = card.slot(116 * g, 82 * g, 280 * g, 14 * g)
  result.upgradesTitle = card.slot(490 * g, 48 * g, 98 * g, 14 * g)
  result.actions[0] = card.slot(12 * g, 120 * g, 32 * g, 32 * g)
  result.attackCaption = card.slot(50 * g, 120 * g, 62 * g, 32 * g)
  for i in 1 .. 5:
    result.actions[i] = card.slot(
      (116 + float32(i - 1) * 58) * g, 104 * g, 48 * g, 48 * g)
  for i in 6 .. 9:
    result.actions[i] = card.slot(
      (490 + float32((i - 6) mod 2) * 50) * g,
      (70 + float32((i - 6) div 2) * 48) * g, 40 * g, 40 * g)

proc desktopFit(size: Vec2, transportHeight: float32): float32 =
  ## Largest uniform plate scale that still fits this layout. 1 is desktop.
  let
    roomY = max(size.y - transportHeight - HudMargin, 1)
    fit = min(size.x / DesktopFitWidth, roomY / DesktopFitHeight)
  min(fit, 1.0'f32)

proc placeCompact(size: Vec2, transportHeight: float32): PudgeHudLayout =
  ## One bottom bar plus a corner map. Used when the three desktop plates
  ## would have to shrink below readable type.
  let
    margin = 8.0'f32
    floorY = size.y - transportHeight
    barH = clamp(min(floorY * 0.34'f32, 188.0'f32), 128.0'f32, 188.0'f32)
    mapW = clamp(min(size.x * 0.34'f32, 200.0'f32), 108.0'f32, 200.0'f32)
    gap = 6.0'f32
  result.bar = GameUiPanel(
    origin: vec2(margin, max(floorY - margin - barH, margin)),
    size: vec2(max(size.x - margin * 2, 40), barH))
  let
    above = result.bar.origin.y - gap
    mapRoom = max(above - margin, 48)
    fittedMapW = min(mapW, mapRoom * MinimapPanelSize.x / MinimapPanelSize.y)
    fittedMapH = fittedMapW * MinimapPanelSize.y / MinimapPanelSize.x
  result.dressMinimap(GameUiPanel(
    origin: vec2(margin, above - fittedMapH),
    size: vec2(fittedMapW, fittedMapH)))
  let
    chatH = clamp(min(72.0'f32, result.minimap.origin.y - margin - gap), 0.0'f32, 72.0'f32)
    chatW = min(220.0'f32, max(size.x - margin * 2, 40))
  if chatH >= 36:
    result.chat = GameUiPanel(
      origin: vec2(margin, result.minimap.origin.y - gap - chatH),
      size: vec2(chatW, chatH))
  else:
    # No band above the map. A stub there would cover the map.
    result.chat = GameUiPanel()
  let
    invX = result.minimap.origin.x + result.minimap.size.x + gap
    invW = min(PanelInventory.x, max(size.x - invX - margin, 0))
    invTop = result.minimap.origin.y
    invH = min(PanelInventory.y, max(above - invTop, 0))
  if invW >= 120 and invH >= 96:
    result.inventory = GameUiPanel(
      origin: vec2(invX, invTop),
      size: vec2(invW, invH))
  else:
    result.inventory = GameUiPanel()
  # Shop sits above the chat when the screen is tall. On a short landscape
  # phone that band is gone, so it takes the column to the right of the bag.
  let
    stackTop = margin
    stackBottom =
      if result.chat.size.y > 0: result.chat.origin.y
      else: result.minimap.origin.y
    aboveH = stackBottom - gap - stackTop
  if aboveH >= 120:
    let
      shopH = min(ShopPanelSize.y, aboveH)
      shopW = min(ShopPanelSize.x, max(size.x - margin * 2, 80))
    result.shop = GameUiPanel(
      origin: vec2(max((size.x - shopW) * 0.5'f32, margin), stackTop),
      size: vec2(shopW, shopH))
  else:
    let
      anchorRight =
        if result.inventory.size.x > 0:
          result.inventory.origin.x + result.inventory.size.x
        else:
          result.minimap.origin.x + result.minimap.size.x
      shopX = anchorRight + gap
      shopW = size.x - margin - shopX
      shopH = max(result.bar.origin.y - gap - margin, 0)
    if shopW >= 140 and shopH >= 120:
      result.shop = GameUiPanel(
        origin: vec2(shopX, margin),
        size: vec2(min(shopW, ShopPanelSize.x), min(shopH, ShopPanelSize.y)))
    else:
      result.shop = GameUiPanel()
  let card = result.bar
  let
    pad = 6.0'f32
    gaps = 3.0'f32
    icon = clamp((card.size.x - pad * 2 - gaps * 9) / 10.0'f32, 26.0'f32, 48.0'f32)
    iconY = card.size.y - pad - icon
    portrait = min(64.0'f32, max(iconY - pad * 2, 36.0'f32))
    textX = pad + portrait + 6
    textRight = card.size.x - pad
    gemW = min(72.0'f32, max((textRight - textX) * 0.34'f32, 36.0'f32))
    titleW = max(textRight - textX - gemW - 4, 24.0'f32)
  result.portrait = card.slot(pad, pad, portrait, portrait)
  result.title = card.slot(textX, pad, titleW, 16)
  result.gemBox = card.slot(textX + titleW + 4, pad, gemW, 16)
  result.hpBar = card.slot(textX, pad + 18, max(textRight - textX, 24), 16)
  result.resourceBar = card.slot(textX, pad + 36, max(textRight - textX, 24), 16)
  result.abilitiesTitle = card.slot(textX, max(iconY - 14, pad + 52), 80, 12)
  result.upgradesTitle = card.slot(textRight - 64, max(iconY - 14, pad + 52), 64, 12)
  let captionTop = pad + portrait + 1
  result.attackCaption = card.slot(
    pad, captionTop, portrait,
    max(min(iconY - captionTop - 1, 28.0'f32), 0.0'f32))
  for i in 0 ..< ActionSlotCount:
    result.actions[i] = card.slot(
      pad + float32(i) * (icon + gaps), iconY, icon, icon)

proc placePudgeHud*(size: Vec2, transportHeight = 0.0'f32): PudgeHudLayout =
  ## Desktop plates when they fit, otherwise a single bar for the phone.
  let g = desktopFit(size, transportHeight)
  if g >= MinDesktopFit:
    placeDesktop(size, transportHeight, g)
  else:
    placeCompact(size, transportHeight)
