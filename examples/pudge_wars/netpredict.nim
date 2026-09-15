## Client-side prediction and rollback for WASM human seats.
##
## A hosted follower runs two worlds:
##
## - **Rollback (confirmed) world** — the follower's authoritative sim.
##   It advances only on ticks the host has finished and hashed, applying
##   the streamed tape and verifying every hash (the same check as
##   replay). This is `game.nim`'s `run`; this module never ticks it.
##
## - **Prediction world** — a throwaway copy that runs `lead` ticks ahead
##   of the confirmed world. The local seat's own intents apply here
##   immediately, so a click moves the local butcher on the next frame
##   instead of after a full round trip. Other seats (bots and other
##   humans) are assumed to have issued nothing past the confirmed tick:
##   their orders exist only once they land on the tape.
##
## Each time the confirmed world advances, the prediction world is
## rebuilt: copy the confirmed world, replay the local intents that have
## not yet come back on the tape, then tick forward `lead` ticks with no
## host input. If the rebuilt local-seat trajectory matches the previous
## prediction the render smooths; if the lag guess was wrong it snaps.
##
## Determinism is the whole game: the prediction world is the same sim as
## the host, so replaying the same intents on the same start state gives
## the same bytes (Gate 0). The only source of a snap is a *timing*
## miss - the host recorded an intent on a different tick than the client
## predicted - never a physics divergence.

import
  polyworld/profiles,
  content, replays, sim

type
  PendingIntent* = object
    ## One local command issued but not yet seen on the confirmed tape.
    intent*: HumanIntent
    wantedTick*: uint32
      ## The prediction-world tick it was applied at locally.

  Predictor* = ref object
    ## Owns the prediction world and the unconfirmed local-intent log for
    ## one WASM seat. Nil / disabled for policy pods and LAN followers.
    enabled*: bool
    seat*: int
      ## Confirmed-world roster index this client drives, or -1.
    lead*: int
      ## Ticks the prediction world runs ahead of the confirmed world.
    predicted*: Game
      ## The rendered world. Rebuilt from the confirmed world each update.
    pending*: seq[PendingIntent]
      ## Local intents awaiting confirmation, in issue order.
    issued*: int
      ## Total local intents ever recorded, for FIFO tape reconciliation.
    snapped*: bool
      ## The last rebuild diverged from the prior prediction (render hint).
    snapCount*: int
      ## Rebuilds that flagged a snap since enable(); debug overlay.
    lastLocalX*, lastLocalZ*: int32
      ## Local butcher position after the previous rebuild, for snap test.
    havePrev*: bool
    renderX*, renderZ*: int32
      ## Smoothed *draw* position for the local butcher. A misprediction
      ## teleport is absorbed into a decaying offset and eased out over a
      ## few frames instead of jumping; normal motion passes through.
    offsetX, offsetZ: int32
    haveRender: bool
    previousLocalPosition: WorldPoint
      ## Position immediately before the final predicted tick, NOT the
      ## previous confirmed tick. Both render endpoints share a timeline.
    previousLocalFacing*: Heading

const
  MinLead* = 1
  MaxLead* = 4
    ## Prediction never runs more than a few ticks ahead; past that the
    ## guess about other players' inaction is too likely to be wrong.
  SnapEpsilon* = 12_000'i32
    ## Position gap (fixed-point world units, ~0.18 tile) above which a
    ## rebuild counts as a snap rather than a smooth correction.
  SnapStep* = 120_000'i32
    ## Per-frame local-hero jump (~1.8 tiles) above which a rebuild is a
    ## misprediction teleport rather than ordinary walk motion, and the
    ## render smoothing engages.
  SnapCap* = 520_000'i32
    ## Above this (~8 tiles) the jump is an intended teleport (blink, hook
    ## pull) and snaps instantly — smoothing it would feel laggy.
  DefaultSmoothDecay = 0.82'f32
    ## Per-frame decay of the render offset. Higher = the correction is
    ## paid back over more frames, so each frame's catch-up step is smaller
    ## (smoother) at the cost of a slightly longer visible lag.

var smoothDecay = DefaultSmoothDecay
proc setSmoothDecay*(v: float32) =
  ## Tuning hook (bench/dev). Clamped to a sane easing range.
  smoothDecay = clamp(v, 0.0'f32, 0.95'f32)

proc newPredictor*(): Predictor =
  Predictor(enabled: false, seat: -1, lead: MinLead)

proc leadFromRttMs*(rttMs: int): int =
  ## One-way lag in ticks at 32 Hz, clamped. A -1 (no sample yet) keeps
  ## the floor so prediction still hides in-process latency.
  if rttMs < 0:
    return MinLead
  # Predict roughly half the round trip ahead (one-way), min one tick.
  let ticks = (rttMs * int(TickRate)) div 2000
  clamp(max(ticks, MinLead), MinLead, MaxLead)

proc enable*(pred: Predictor, seat, lead: int) =
  pred.enabled = true
  pred.seat = seat
  pred.lead = clamp(lead, MinLead, MaxLead)
  pred.pending.setLen(0)
  pred.issued = 0
  pred.havePrev = false
  pred.snapped = false
  pred.snapCount = 0
  pred.haveRender = false
  pred.offsetX = 0
  pred.offsetZ = 0

proc disable*(pred: Predictor) =
  pred.enabled = false
  pred.seat = -1
  pred.pending.setLen(0)
  pred.issued = 0
  pred.predicted = nil
  pred.havePrev = false
  pred.haveRender = false

proc record*(pred: Predictor, intent: HumanIntent, atTick: uint32) =
  ## Logs a local intent issued at prediction tick `atTick`. Caller also
  ## sends it to the host stamped with the same `wantedTick`.
  if not pred.enabled:
    return
  pred.pending.add PendingIntent(intent: intent, wantedTick: atTick)
  inc pred.issued

proc seatActionsOnTape(confirmed: Game, pudgeId: int32,
    confirmedTick: uint32): int =
  ## How many of our seat's commands the host has already recorded up to
  ## the confirmed tick. Takeover markers are provenance, not commands.
  if confirmed.replayPlayer == nil:
    return 0
  for action in confirmed.replayPlayer.data.actions:
    if action.tick > confirmedTick:
      break
    if action.pudgeId == pudgeId and action.kind != ActionTakeOver:
      inc result

proc dropConfirmed*(pred: Predictor, confirmed: Game) =
  ## Drops local intents the host has echoed back onto the confirmed
  ## tape. The host applies our commands in the order it received them,
  ## so once N of our seat's actions are on the tape the first N pending
  ## intents are confirmed (FIFO, kind-agnostic, robust to reordering).
  ## A stale intent the host never recorded (rejected on its tick) is
  ## pruned once the confirmed tick passes its prediction window.
  if not pred.enabled or pred.seat < 0:
    return
  let
    pudgeId =
      if pred.seat < confirmed.world.pudges.len:
        confirmed.world.pudges[pred.seat].id
      else: 0'i32
    confirmedTick = uint32(confirmed.world.tick)
    onTape = seatActionsOnTape(confirmed, pudgeId, confirmedTick)
    stillPending = max(pred.issued - onTape, 0)
  while pred.pending.len > stillPending:
    pred.pending.delete(0)
  var kept: seq[PendingIntent]
  for entry in pred.pending:
    if entry.wantedTick + uint32(MaxLead) >= confirmedTick:
      kept.add entry
  pred.pending = kept

proc rebuild*(pred: Predictor, confirmed: Game) {.measure.} =
  ## Recomputes the prediction world from the confirmed world: clone,
  ## replay unconfirmed local intents, tick `lead` ahead with no host
  ## input. Sets `snapped` when the local butcher jumps from its prior
  ## predicted spot.
  if not pred.enabled:
    return
  pred.dropConfirmed(confirmed)
  if pred.predicted == nil:
    pred.predicted = Game(botEvery: 1)
  # Fresh copy of the authoritative world at the confirmed tick.
  pred.predicted.world = confirmed.world.clone()
  pred.predicted.map = confirmed.map
  pred.predicted.maximumTicks = confirmed.maximumTicks
  pred.predicted.historyPlayback = false
  pred.predicted.replayMode = false
  pred.predicted.recorder = nil
  pred.predicted.humanSlots = @[pred.seat]
  pred.predicted.humanIntents.setLen(0)
  pred.predicted.intentResults.setLen(0)
  # Apply every still-unconfirmed local order, then advance without any
  # host tape: other seats coast on their last order, no bot decisions,
  # so only our own predicted input changes the world.
  for entry in pred.pending:
    queueIntent(pred.predicted, entry.intent)
  # The prediction world is a throwaway, client-local copy, rebuilt from the
  # confirmed world every frame. Extrapolating it with no host tape (other
  # seats coasting on stale orders) can reach geometry the authoritative sim
  # never produces — e.g. a coasting hook whose clash math overflows int64 in
  # `segmentsWithin`. A defect there must never crash the client, so tick
  # inside a guard and, on any defect, fall back to the confirmed world for
  # this frame (no look-ahead) instead of propagating it. This never touches
  # the authoritative sim, so host determinism is unaffected.
  try:
    for _ in 0 ..< pred.lead:
      if pred.seat >= 0 and pred.seat < pred.predicted.world.pudges.len:
        let local = pred.predicted.world.pudges[pred.seat]
        pred.previousLocalPosition = local.position
        pred.previousLocalFacing = local.facing
      if pred.predicted.world.gameOver:
        break
      tickWorld(pred.predicted, proc() =
        runHumanIntents(pred.predicted, pred.seat))
  except Defect:
    pred.predicted.world = confirmed.world.clone()
    if pred.seat >= 0 and pred.seat < pred.predicted.world.pudges.len:
      let local = pred.predicted.world.pudges[pred.seat]
      pred.previousLocalPosition = local.position
      pred.previousLocalFacing = local.facing
  # Snap detection + render smoothing on the local butcher.
  if pred.seat >= 0 and pred.seat < pred.predicted.world.pudges.len:
    let p = pred.predicted.world.pudges[pred.seat].position
    if pred.havePrev:
      let dx = abs(p.x - pred.lastLocalX)
      let dz = abs(p.z - pred.lastLocalZ)
      pred.snapped = dx > SnapEpsilon or dz > SnapEpsilon
      if pred.snapped:
        inc pred.snapCount
      # Decay the offset carried from earlier corrections, then, if this
      # frame is a fresh misprediction teleport (walk ceiling < step <
      # intended-teleport), hold the render at its last drawn spot (zero
      # jump this frame) so the offset eases the hero to the correction.
      pred.offsetX = int32(float32(pred.offsetX) * smoothDecay)
      pred.offsetZ = int32(float32(pred.offsetZ) * smoothDecay)
      let stepX = int64(p.x) - int64(pred.lastLocalX)
      let stepZ = int64(p.z) - int64(pred.lastLocalZ)
      let stepSq = stepX * stepX + stepZ * stepZ
      if stepSq > int64(SnapStep) * int64(SnapStep) and
          stepSq < int64(SnapCap) * int64(SnapCap):
        pred.offsetX = pred.renderX - p.x
        pred.offsetZ = pred.renderZ - p.z
    else:
      pred.offsetX = 0
      pred.offsetZ = 0
    pred.renderX = p.x + pred.offsetX
    pred.renderZ = p.z + pred.offsetZ
    pred.lastLocalX = p.x
    pred.lastLocalZ = p.z
    pred.havePrev = true
    pred.haveRender = true

proc localRenderPoint*(pred: Predictor, alpha = 1.0'f32): WorldPoint =
  ## The smoothed draw position for the local butcher: identical to the
  ## predicted position during ordinary motion, but with misprediction
  ## teleports eased out. Falls back to the raw predicted position before
  ## the first rebuild.
  ## Interpolate the final two predicted ticks with the display's tick
  ## fraction. Interpolating from confirmed history instead repeatedly
  ## rewinds by `lead` ticks whenever that fraction wraps back to zero.
  if pred.enabled and pred.predicted != nil and pred.seat >= 0 and
      pred.seat < pred.predicted.world.pudges.len:
    let current = pred.predicted.world.pudges[pred.seat].position
    if not pred.haveRender:
      return current
    let t = float64(clamp(alpha, 0.0'f32, 1.0'f32))
    template blend(a, b: int32): int32 =
      int32(float64(a) + (float64(b) - float64(a)) * t)
    # Apply the same correction offset to both endpoints; do not blend
    # back toward an unsmoothed confirmed position each simulation tick.
    WorldPoint(
      x: blend(pred.previousLocalPosition.x, current.x) + pred.offsetX,
      y: blend(pred.previousLocalPosition.y, current.y),
      z: blend(pred.previousLocalPosition.z, current.z) + pred.offsetZ)
  else:
    WorldPoint()

proc predictsUnit*(pred: Predictor, id: int32): bool =
  pred.enabled and pred.predicted != nil and pred.seat >= 0 and
    pred.seat < pred.predicted.world.pudges.len and
    pred.predicted.world.pudges[pred.seat].id == id

proc renderWorld*(pred: Predictor, confirmed: Game): World =
  ## The world the client should draw: the prediction world when it is
  ## live, else the confirmed world (spectator, LAN, or pre-start).
  if pred.enabled and pred.predicted != nil:
    return pred.predicted.world
  confirmed.world
