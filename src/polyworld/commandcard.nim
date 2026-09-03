## Command and upgrade slot rows for Polyworld games.
##
## League-style single rows instead of the WC3 4×3 card: a 5-slot
## command row and a 4-slot upgrade row sit inside caller-placed panels.
## Games fill each slot with an icon, hotkey, and cooldown; this module
## draws the wells and reports which slot was pressed.

import
  chroma, pixie, silky, vmath, windy,
  chrome, gameuis, hudchips

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
  CooldownFill = rgbx(8, 10, 16, 180)

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

proc drawCooldownSweep(
    sk: Silky,
    slot: GameUiPanel,
    remaining, duration: int32
) =
  if remaining <= 0 or duration <= 0:
    return
  let height = slot.size.y * remaining.float32 / duration.float32
  sk.drawRect(slot.origin, vec2(slot.size.x, height), CooldownFill)

proc drawCommandSlot*(
    sk: Silky,
    slot: GameUiPanel,
    spec: CommandSlotSpec
) =
  ## Draws one gold-rimmed well with icon, cooldown, and hotkey.
  sk.drawEtched(slot.origin, slot.size, rgbx(12, 12, 16, 255))
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
        sk.drawEtched(well.origin, well.size, rgbx(12, 12, 16, 255))
      if spec.id >= 0 and spec.enabled and window.clicked(sk, well):
        result = spec.id
