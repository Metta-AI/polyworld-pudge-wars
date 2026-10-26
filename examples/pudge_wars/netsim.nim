## Local network-condition simulator for the Fresh Meat follower.
##
## Sits between `netclient`'s transport and the game: outbound packets
## (intents, pings, hello) and inbound packets (the host's tape, pongs,
## lobby) can be held in a per-direction FIFO delay queue, jittered, and
## dropped, so a developer can feel and measure the client under 100/250/
## 500 ms links without a real WAN.
##
## Design rules that keep it safe on a reliable, lockstep stream:
##   * **Order is preserved.** Release times are clamped monotonic per
##     direction, so jitter never reorders the tape (an out-of-order tape
##     slice would desync the follower). A late packet simply holds up the
##     ones behind it, exactly like a real ordered link.
##   * **Delays are never negative.** `latency + jitterSample` is clamped
##     at zero.
##   * **Queues are bounded.** Past `MaxQueue` packets the oldest is
##     dropped and counted, so a stalled pump can never grow memory without
##     bound.
##   * **The clock is injected.** Every entry point takes `nowUs`, so tests
##     drive time deterministically; `netclient` passes real wall-clock.
##   * **Deterministic RNG.** Jitter and loss draw from a seedable
##     splitmix64, so a seeded run reproduces exactly.
##
## The simulator is inert by default (`enabled = false`): the transport
## paths bypass it entirely, so a production build behaves bit-for-bit like
## no simulator at all. It is turned on at runtime (a `--netsim <preset>`
## flag, a `netsim` URL param, or in-game keys) in development.

import std/strutils

type
  NetSimPreset* = enum
    PresetLocal = "local"      ## 0 ms, no jitter, no loss — passthrough.
    PresetGood = "good"        ## 100 ms, light jitter.
    PresetPoor = "poor"        ## 250 ms, moderate jitter.
    PresetExtreme = "extreme"  ## 500 ms, heavy jitter + loss.

  SimDir* = enum
    DirOutbound   ## client -> host (intents, pings, hello)
    DirInbound    ## host -> client (tape, pongs, lobby)

  NetSimConfig* = object
    enabled*: bool
      ## Master switch. When false the transport bypasses the sim and
      ## behaves exactly like the unsimulated client.
    latencyMs*: int
      ## One-way baseline delay applied to each *enabled* direction. With
      ## both directions on, measured round-trip ping is ~2x this.
    jitterMs*: int
      ## Uniform +/- variation added to the baseline per packet.
    packetLossPercent*: float
      ## Probability [0,100] that a packet is dropped outright.
    delayOutbound*: bool
    delayInbound*: bool
    dropInbound*: bool
      ## Whether loss may drop *inbound* packets. Off by default: the host
      ## tape is a reliable ordered stream, so dropping a tape slice just
      ## desyncs the follower. Loss normally applies to outbound only
      ## (a lost intent is safe — the host is authoritative). Turn this on
      ## to exercise the tape drop-detection path.

  DirStats* = object
    offered*: int    ## packets handed to the sim
    delivered*: int  ## packets released to the transport/app
    delayed*: int    ## packets that carried a non-zero delay
    dropped*: int    ## packets dropped (loss or queue overflow)
    queueDepth*: int ## packets currently waiting
    queueMax*: int   ## high-water mark of queueDepth

  QueuedPacket = object
    releaseUs: int64
    data: string

const
  MaxQueue* = 8192
    ## Hard cap on a direction's waiting packets; overflow drops the
    ## oldest so memory stays bounded even if the pump stalls.
  QueueWarnDepth = 512
    ## Above this the sim logs abnormal queue growth (once per crossing).

var
  cfg: NetSimConfig = NetSimConfig(
    enabled: false, latencyMs: 0, jitterMs: 0, packetLossPercent: 0.0,
    delayOutbound: true, delayInbound: true
  )
  queues: array[SimDir, seq[QueuedPacket]]
  stats: array[SimDir, DirStats]
  lastReleaseUs: array[SimDir, int64]
  warned: array[SimDir, bool]
  logAnomalies = false
  rngState: uint64 = 0x9E3779B97F4A7C15'u64
  cycleIndex = 0
    ## 0 = disabled, 1..4 = local/good/poor/extreme. Custom slider
    ## values keep the last cycle slot so F7 continues from there.

# --- deterministic RNG (splitmix64) -------------------------------------

proc nextRand(): uint64 =
  rngState = rngState + 0x9E3779B97F4A7C15'u64
  var z = rngState
  z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9'u64
  z = (z xor (z shr 27)) * 0x94D049BB133111EB'u64
  z xor (z shr 31)

proc rngUnit(): float =
  ## Uniform in [0, 1).
  float(nextRand() shr 11) / float(1'u64 shl 53)

proc rngSpan(halfWidth: int): int =
  ## Uniform integer in [-halfWidth, halfWidth].
  if halfWidth <= 0:
    return 0
  int(nextRand() mod uint64(2 * halfWidth + 1)) - halfWidth

proc netSimSeed*(seed: uint64) =
  ## Reseeds the jitter/loss RNG for reproducible runs and tests.
  rngState = if seed == 0: 0x9E3779B97F4A7C15'u64 else: seed

# --- configuration ------------------------------------------------------

proc netSimConfig*(): NetSimConfig = cfg

proc netSimSetLogging*(on: bool) = logAnomalies = on

proc presetConfig*(preset: NetSimPreset): NetSimConfig =
  ## The four required presets. Latency is one-way per direction.
  case preset
  of PresetLocal:
    NetSimConfig(enabled: true, latencyMs: 0, jitterMs: 0,
      packetLossPercent: 0.0, delayOutbound: true, delayInbound: true)
  of PresetGood:
    NetSimConfig(enabled: true, latencyMs: 100, jitterMs: 20,
      packetLossPercent: 0.0, delayOutbound: true, delayInbound: true)
  of PresetPoor:
    NetSimConfig(enabled: true, latencyMs: 250, jitterMs: 50,
      packetLossPercent: 1.0, delayOutbound: true, delayInbound: true)
  of PresetExtreme:
    NetSimConfig(enabled: true, latencyMs: 500, jitterMs: 120,
      packetLossPercent: 5.0, delayOutbound: true, delayInbound: true)

proc matchesPreset(c: NetSimConfig, preset: NetSimPreset): bool =
  let p = presetConfig(preset)
  c.enabled and c.latencyMs == p.latencyMs and c.jitterMs == p.jitterMs and
    abs(c.packetLossPercent - p.packetLossPercent) < 0.001 and
    c.delayOutbound == p.delayOutbound and c.delayInbound == p.delayInbound

proc syncCycleIndex() =
  ## Keeps F7's slot in sync with the live config.
  if not cfg.enabled:
    cycleIndex = 0
    return
  for preset in NetSimPreset:
    if matchesPreset(cfg, preset):
      cycleIndex = preset.ord + 1
      return

proc netSimConfigure*(newCfg: NetSimConfig) =
  ## Applies a config, clamping to safe ranges. Does not clear in-flight
  ## packets, so a live tweak drains cleanly.
  cfg = newCfg
  if cfg.latencyMs < 0: cfg.latencyMs = 0
  if cfg.jitterMs < 0: cfg.jitterMs = 0
  cfg.packetLossPercent = clamp(cfg.packetLossPercent, 0.0, 100.0)
  syncCycleIndex()

proc netSimApplyPreset*(preset: NetSimPreset) =
  netSimConfigure(presetConfig(preset))

proc netSimEnable*(on: bool) =
  cfg.enabled = on
  if on:
    netSimSetLogging(true)
    if cycleIndex == 0:
      cycleIndex = 1
  else:
    cycleIndex = 0

proc netSimCycleIndex*(): int = cycleIndex

proc netSimAdvanceCycle*() =
  ## F7: off → local → good → poor → extreme → off.
  cycleIndex = (cycleIndex + 1) mod 5
  case cycleIndex
  of 0:
    cfg.enabled = false
  of 1:
    netSimApplyPreset(PresetLocal)
  of 2:
    netSimApplyPreset(PresetGood)
  of 3:
    netSimApplyPreset(PresetPoor)
  else:
    netSimApplyPreset(PresetExtreme)
  if cycleIndex > 0:
    netSimSetLogging(true)

proc netSimLabel*(): string =
  ## Short name for the overlay / debug menu.
  if not cfg.enabled:
    return "off"
  for preset in NetSimPreset:
    if matchesPreset(cfg, preset):
      return $preset
  "custom"

proc parsePreset*(name: string): (bool, NetSimPreset) =
  ## Parses a preset name (case-insensitive); (false, _) if unknown.
  case name.strip().toLowerAscii()
  of "local", "0": (true, PresetLocal)
  of "good", "100": (true, PresetGood)
  of "poor", "250": (true, PresetPoor)
  of "extreme", "500": (true, PresetExtreme)
  else: (false, PresetLocal)

proc parseNetSimArg*(text: string): (bool, NetSimConfig) =
  ## CLI / URL spec: a preset name, `off`, or a custom
  ## `latency+/-jitter` with optional `,loss=` (e.g. `100+/-50` or
  ## `250+/-40,loss=2`). Named presets win over a bare `100`/`250`/`500`.
  let raw = text.strip()
  if raw.len == 0:
    return (false, NetSimConfig())
  let lower = raw.toLowerAscii()
  case lower
  of "off", "none", "false":
    return (true, NetSimConfig(
      enabled: false, latencyMs: 0, jitterMs: 0, packetLossPercent: 0.0,
      delayOutbound: true, delayInbound: true))
  else:
    discard
  let (isPreset, preset) = parsePreset(lower)
  if isPreset:
    return (true, presetConfig(preset))
  var spec = lower.replace(" ", "").replace("ms", "").replace("±", "+/-")
  var loss = 0.0
  let comma = spec.find(',')
  if comma >= 0:
    var lossPart = spec[comma + 1 .. ^1]
    if lossPart.startsWith("loss="):
      lossPart = lossPart[5 .. ^1]
    try:
      loss = parseFloat(lossPart)
    except ValueError:
      return (false, NetSimConfig())
    spec = spec[0 ..< comma]
  var latStr = spec
  var jitStr = "0"
  let pm = spec.find("+/-")
  if pm >= 0:
    latStr = spec[0 ..< pm]
    jitStr = spec[pm + 3 .. ^1]
  try:
    let lat = parseInt(latStr)
    let jit = parseInt(jitStr)
    if lat < 0 or jit < 0 or loss < 0.0 or loss > 100.0:
      return (false, NetSimConfig())
    (true, NetSimConfig(
      enabled: true, latencyMs: lat, jitterMs: jit, packetLossPercent: loss,
      delayOutbound: true, delayInbound: true))
  except ValueError:
    (false, NetSimConfig())

proc netSimActive*(dir: SimDir): bool =
  ## Whether this direction currently routes through the sim. When false
  ## the caller must use the raw transport (exact unsimulated behavior).
  cfg.enabled and (
    if dir == DirOutbound: cfg.delayOutbound else: cfg.delayInbound)

# --- stats --------------------------------------------------------------

proc netSimStats*(dir: SimDir): DirStats = stats[dir]

proc netSimResetStats*() =
  for dir in SimDir:
    stats[dir] = DirStats()
    warned[dir] = false

proc netSimReset*() =
  ## Drops all in-flight packets and clears stats (a fresh connection).
  for dir in SimDir:
    queues[dir].setLen(0)
    lastReleaseUs[dir] = 0
  netSimResetStats()

# --- core: delay computation --------------------------------------------

proc computeDelayMs*(): int =
  ## One packet's delay in ms: baseline latency plus uniform jitter,
  ## floored at zero. Exposed for tests. Consumes one RNG draw when
  ## jitter is non-zero, matching the offer path.
  var d = cfg.latencyMs
  if cfg.jitterMs > 0:
    d += rngSpan(cfg.jitterMs)
  max(d, 0)

proc rollDropped(): bool =
  ## True if this packet is lost. Consumes one RNG draw when loss > 0.
  if cfg.packetLossPercent <= 0.0:
    return false
  rngUnit() * 100.0 < cfg.packetLossPercent

# --- core: offer / release ----------------------------------------------

proc netSimOffer*(dir: SimDir, data: string, nowUs: int64): bool =
  ## Hands one packet to the sim for `dir`. Returns true if it was queued
  ## (to be released later by `netSimDue`), false if it was dropped. The
  ## caller only reaches here when `netSimActive(dir)` is true.
  inc stats[dir].offered
  # Loss first: a dropped packet never occupies the queue. Only outbound is
  # droppable by default (a lost intent is safe; a lost tape slice would
  # desync the lockstep follower), so inbound consumes no loss RNG draw
  # unless dropInbound is set.
  let droppable = dir == DirOutbound or cfg.dropInbound
  if droppable and rollDropped():
    inc stats[dir].dropped
    if logAnomalies:
      echo "[netsim] drop ", dir, " (loss ", cfg.packetLossPercent, "%) total=",
        stats[dir].dropped
    return false
  let delayMs = computeDelayMs()
  if delayMs > 0:
    inc stats[dir].delayed
  # Monotonic release keeps FIFO order: a packet never releases before the
  # one ahead of it, so the ordered tape stream is never reordered.
  var releaseUs = nowUs + int64(delayMs) * 1000
  if releaseUs < lastReleaseUs[dir]:
    releaseUs = lastReleaseUs[dir]
  lastReleaseUs[dir] = releaseUs
  # Bounded queue: overflow drops the oldest waiting packet.
  if queues[dir].len >= MaxQueue:
    queues[dir].delete(0)
    inc stats[dir].dropped
    if logAnomalies:
      echo "[netsim] queue overflow ", dir, " > ", MaxQueue,
        " - dropped oldest"
  queues[dir].add QueuedPacket(releaseUs: releaseUs, data: data)
  stats[dir].queueDepth = queues[dir].len
  if queues[dir].len > stats[dir].queueMax:
    stats[dir].queueMax = queues[dir].len
  if logAnomalies:
    if queues[dir].len >= QueueWarnDepth and not warned[dir]:
      warned[dir] = true
      echo "[netsim] abnormal queue growth ", dir, " depth=", queues[dir].len
    elif queues[dir].len < QueueWarnDepth div 2:
      warned[dir] = false
  true

proc netSimDue*(dir: SimDir, nowUs: int64): seq[string] =
  ## Pops every packet whose release time has passed, in FIFO order.
  ## Because release times are monotonic, a prefix of the queue is due.
  var cut = 0
  while cut < queues[dir].len and queues[dir][cut].releaseUs <= nowUs:
    result.add queues[dir][cut].data
    inc cut
  if cut > 0:
    queues[dir] = queues[dir][cut .. ^1]
    stats[dir].delivered += cut
    stats[dir].queueDepth = queues[dir].len

proc netSimQueueDepth*(dir: SimDir): int = queues[dir].len

proc netSimNextReleaseUs*(dir: SimDir): int64 =
  ## Release time of the head packet, or -1 if the queue is empty.
  if queues[dir].len == 0: -1'i64 else: queues[dir][0].releaseUs
