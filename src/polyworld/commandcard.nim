## Command and upgrade slot rows for Polyworld games.
##
## League-style single rows instead of the WC3 4×3 card: a 5-slot
## command row and a 4-slot upgrade row sit inside caller-placed panels.
## Games fill each slot with an icon, hotkey, and cooldown; this module
## draws the wells and reports which slot was pressed.

import
  chroma, pixie, silky, vmath, windy,
  chrome, gameuis

const
  CommandCols* = 5
  CommandRows* = 1
  InventoryCols* = 4
  InventoryRows* = 1
  GridPad = 2.0'f32
  GridGap = 2.0'f32
  SlotReady* = rgbx(255, 255, 255, 255)
  SlotDim* = rgbx(150, 150, 158, 255)
  SlotOverlay* = rgbx(255, 214, 120, 255)
  SlotHotkey* = rgbx(186, 192, 205, 255)
  CooldownFill = rgbx(8, 10, 16, 180)
  SlotIconGrow* = 8.0'f32
  AutocastGreen* = rgbx(72, 224, 96, 235)

type
  CommandSlotSpec* = object
    id*: int
    icon*: string
    hotkey*: string
    enabled*: bool
    remaining*: int32
    duration*: int32
    overlay*: string
    badge*: string
    autocast*: bool
      ## WC3 green corners: this well's autocast is armed.

proc gridSlot*(
    panel: GameUiPanel,
    col, row, cols, rows: int,
    pad = GridPad,
    gap = GridGap
): GameUiPanel =
  ## Returns one cell inside a uniform well grid.
  let
    colsF = max(cols, 1).float32
    rowsF = max(rows, 1).float32
    inner = vec2(
      max(panel.size.x - pad * 2, 0),
      max(panel.size.y - pad * 2, 0)
    )
    slot = vec2(
      max((inner.x - gap * (colsF - 1)) / colsF, 1),
      max((inner.y - gap * (rowsF - 1)) / rowsF, 1)
    )
  GameUiPanel(
    origin: panel.origin + vec2(
      pad + col.float32 * (slot.x + gap),
      pad + row.float32 * (slot.y + gap)
    ),
    size: slot
  )

proc commandSlot*(panel: GameUiPanel, col, row: int): GameUiPanel =
  ## Returns one cell of the 5-slot command row.
  panel.gridSlot(col, row, CommandCols, CommandRows)

proc inventorySlot*(panel: GameUiPanel, col, row: int): GameUiPanel =
  ## Returns one cell of the 4-slot upgrade row.
  panel.gridSlot(col, row, InventoryCols, InventoryRows)

proc commandIndex*(col, row: int): int =
  ## Row-major index for the command row.
  row * CommandCols + col

proc inventoryIndex*(col, row: int): int =
  ## Row-major index for the upgrade row.
  row * InventoryCols + col

proc fillWell*(sk: Silky, well: GameUiPanel, selected = false) =
  ## Draws one theme slot so the world does not show through.
  sk.drawSlot(well, selected)

proc drawCooldownSweep*(
    sk: Silky,
    slot: GameUiPanel,
    remaining, duration: int32
) =
  ## Covers the unreadied portion of one well from the top.
  if remaining <= 0 or duration <= 0:
    return
  let height = slot.size.y * remaining.float32 / duration.float32
  sk.drawRect(slot.origin, vec2(slot.size.x, height), CooldownFill)

proc drawSlotIcon*(
    sk: Silky,
    slot: GameUiPanel,
    spec: CommandSlotSpec,
    grow = SlotIconGrow
) =
  ## Draws icon and cooldown inside a theme slot.
  sk.drawSlot(slot)
  if spec.icon.len > 0:
    let inset = max(min(grow * 0.35'f32, slot.size.x * 0.08'f32), 2.0'f32)
    sk.drawSprite(
      spec.icon,
      slot.origin + vec2(inset),
      slot.size - vec2(inset * 2),
      if spec.enabled: SlotReady else: SlotDim
    )
  sk.drawCooldownSweep(slot, spec.remaining, spec.duration)

proc drawAutocastMark*(sk: Silky, slot: GameUiPanel) =
  ## Warcraft 3 autocast corners on one well.
  let
    o = slot.origin
    s = slot.size
    arm = max(4.0'f32, min(s.x, s.y) * 0.22'f32)
    w = max(2.0'f32, min(s.x, s.y) * 0.07'f32)
  sk.drawRect(o, vec2(arm, w), AutocastGreen)
  sk.drawRect(o, vec2(w, arm), AutocastGreen)
  sk.drawRect(o + vec2(s.x - arm, 0), vec2(arm, w), AutocastGreen)
  sk.drawRect(o + vec2(s.x - w, 0), vec2(w, arm), AutocastGreen)
  sk.drawRect(o + vec2(0, s.y - w), vec2(arm, w), AutocastGreen)
  sk.drawRect(o + vec2(0, s.y - arm), vec2(w, arm), AutocastGreen)
  sk.drawRect(o + vec2(s.x - arm, s.y - w), vec2(arm, w), AutocastGreen)
  sk.drawRect(o + vec2(s.x - w, s.y - arm), vec2(w, arm), AutocastGreen)

proc drawSlotLabels*(
    sk: Silky,
    slot: GameUiPanel,
    spec: CommandSlotSpec
) =
  ## Draws overlay, rank badge, and hotkey on top of a framed well.
  if spec.overlay.len > 0:
    sk.drawLabel(
      spec.overlay,
      slot.origin,
      slot.size,
      SlotOverlay,
      "Small",
      CenterAlign
    )
  elif spec.remaining > 0:
    hudScratch.setLen(0)
    hudScratch.addHudInt(int(spec.remaining))
    sk.drawLabel(
      hudScratch,
      slot.origin,
      slot.size,
      rgbx(236, 238, 244, 255),
      "Hud",
      CenterAlign
    )
  if spec.badge.len > 0:
    let badge = min(16.0'f32, max(slot.size.x * 0.28'f32, 10))
    sk.drawBadge(
      slot.origin + vec2(slot.size.x - badge - 2, 2),
      vec2(badge),
      spec.badge
    )
  if spec.hotkey.len > 0:
    let hotH = min(16.0'f32, slot.size.y * 0.28'f32)
    sk.drawLabel(
      spec.hotkey,
      slot.origin + vec2(0, slot.size.y - hotH),
      vec2(slot.size.x, hotH),
      SlotHotkey,
      "Small",
      CenterAlign
    )
  if spec.autocast:
    sk.drawAutocastMark(slot)

proc drawCommandSlot*(
    sk: Silky,
    slot: GameUiPanel,
    spec: CommandSlotSpec
) =
  ## Draws one theme slot with icon, cooldown, and hotkey.
  sk.drawSlot(slot)
  if spec.icon.len > 0:
    let inset = max(min(2.0'f32, slot.size.x * 0.08'f32), 1.0'f32)
    sk.drawSprite(
      spec.icon,
      slot.origin + vec2(inset),
      slot.size - vec2(inset * 2),
      if spec.enabled: SlotReady else: SlotDim
    )
  sk.drawCooldownSweep(slot, spec.remaining, spec.duration)
  if spec.overlay.len > 0:
    sk.drawLabel(
      spec.overlay,
      slot.origin,
      slot.size,
      SlotOverlay,
      "Small",
      CenterAlign
    )
  elif spec.remaining > 0:
    hudScratch.setLen(0)
    hudScratch.addHudInt(int(spec.remaining))
    sk.drawLabel(
      hudScratch,
      slot.origin,
      slot.size,
      rgbx(236, 238, 244, 255),
      "Hud",
      CenterAlign
    )
  if spec.badge.len > 0:
    let badge = min(12.0'f32, max(slot.size.x * 0.38'f32, 8))
    sk.drawBadge(
      slot.origin + vec2(slot.size.x - badge - 1, 1),
      vec2(badge),
      spec.badge
    )
  if spec.hotkey.len > 0:
    let hotH = min(11.0'f32, slot.size.y * 0.42'f32)
    sk.drawLabel(
      spec.hotkey,
      slot.origin + vec2(0, slot.size.y - hotH),
      vec2(slot.size.x, hotH),
      LabelColor,
      "Small",
      CenterAlign
    )
  if spec.autocast:
    sk.drawAutocastMark(slot)

proc drawCommandGrid*(
    sk: Silky,
    window: Window,
    panel: GameUiPanel,
    slots: openArray[CommandSlotSpec],
    cols = CommandCols,
    rows = CommandRows
): int =
  ## Draws a well grid and returns the pressed slot id, or -1.
  result = -1
  for row in 0 ..< rows:
    for col in 0 ..< cols:
      let
        index = row * cols + col
        well = panel.gridSlot(col, row, cols, rows)
        spec =
          if index < slots.len: slots[index]
          else: CommandSlotSpec(id: -1)
      if spec.id >= 0 or spec.icon.len > 0:
        sk.drawCommandSlot(well, spec)
      else:
        sk.drawSlot(well)
      if spec.id >= 0 and spec.enabled and window.clicked(sk, well):
        result = spec.id
