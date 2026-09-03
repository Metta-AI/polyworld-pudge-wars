## Network-condition simulator: fixed latency, jitter, packet loss, order
## preservation, bounded queues, and deterministic (seeded) behavior. The
## clock is injected, so these run without any real time passing.

import
  ../examples/pudge_wars/netsim

const Ms = 1000'i64  ## microseconds per millisecond

proc freshCfg(latency, jitter: int, loss: float): NetSimConfig =
  NetSimConfig(enabled: true, latencyMs: latency, jitterMs: jitter,
    packetLossPercent: loss, delayOutbound: true, delayInbound: true)

echo "Testing the sim is inert by default (production passthrough)"
block:
  netSimReset()
  # Default config is disabled: neither direction routes through the sim.
  doAssert not netSimActive(DirOutbound)
  doAssert not netSimActive(DirInbound)

echo "Testing zero latency releases immediately, like the unsimulated client"
block:
  netSimReset()
  netSimApplyPreset(PresetLocal)
  doAssert netSimActive(DirOutbound)
  let t = 1_000_000'i64
  doAssert netSimOffer(DirOutbound, "a", t)
  doAssert netSimOffer(DirOutbound, "b", t)
  # Local = 0 ms: both are due at the same instant, in order, no drops.
  let due = netSimDue(DirOutbound, t)
  doAssert due == @["a", "b"], $due
  doAssert netSimStats(DirOutbound).dropped == 0
  doAssert netSimStats(DirOutbound).delivered == 2

echo "Testing fixed latency delays packets by ~the configured amount"
block:
  netSimReset()
  netSimConfigure(freshCfg(100, 0, 0.0))
  let t0 = 5_000_000'i64
  doAssert netSimOffer(DirInbound, "p", t0)
  # Nothing before 100 ms.
  doAssert netSimDue(DirInbound, t0 + 99 * Ms).len == 0
  doAssert netSimDue(DirInbound, t0 + 100 * Ms) == @["p"]

echo "Testing jitter produces varied delays inside [latency-jitter, +jitter]"
block:
  netSimReset()
  netSimSeed(12345)
  netSimConfigure(freshCfg(100, 40, 0.0))
  var lo = high(int)
  var hi = low(int)
  for _ in 0 ..< 5000:
    let d = computeDelayMs()
    doAssert d >= 60 and d <= 140, "delay out of range: " & $d
    lo = min(lo, d)
    hi = max(hi, d)
  # It actually varies, and spans most of the band.
  doAssert hi - lo >= 60, "jitter span too small: " & $(hi - lo)

echo "Testing delays never go negative when jitter exceeds latency"
block:
  netSimReset()
  netSimSeed(777)
  netSimConfigure(freshCfg(10, 200, 0.0))
  for _ in 0 ..< 5000:
    doAssert computeDelayMs() >= 0

echo "Testing packet loss follows the configured probability (seeded)"
block:
  netSimReset()
  netSimSeed(2024)
  netSimConfigure(freshCfg(0, 0, 25.0))
  let n = 20000
  let t = 0'i64
  var dropped = 0
  for i in 0 ..< n:
    if not netSimOffer(DirOutbound, "x", t):
      inc dropped
    else:
      # Drain immediately (0 latency) so the bounded queue never overflows
      # and folds overflow drops into the loss count.
      discard netSimDue(DirOutbound, t)
  let rate = dropped / n
  doAssert rate > 0.22 and rate < 0.28, "loss rate off: " & $rate
  doAssert netSimStats(DirOutbound).dropped == dropped

echo "Testing seeded runs reproduce exactly"
block:
  proc run(): (int, seq[string]) =
    netSimReset()
    netSimSeed(99)
    netSimConfigure(freshCfg(50, 30, 10.0))
    var dropped = 0
    for i in 0 ..< 400:
      if not netSimOffer(DirOutbound, $i, 0'i64):
        inc dropped
    # Whatever survived, released in order, is the fingerprint of the run.
    (dropped, netSimDue(DirOutbound, 100_000_000'i64))
  let a = run()
  let b = run()
  doAssert a == b, "seeded run not reproducible"
  doAssert a[0] > 0, "expected some drops at 10% over 400 packets"

echo "Testing FIFO order is preserved even under jitter"
block:
  netSimReset()
  netSimSeed(42)
  netSimConfigure(freshCfg(100, 90, 0.0))
  let t0 = 0'i64
  let count = 500
  for i in 0 ..< count:
    doAssert netSimOffer(DirInbound, $i, t0)
  # Release everything far in the future; order must match offer order.
  let due = netSimDue(DirInbound, t0 + 10_000 * Ms)
  doAssert due.len == count
  for i in 0 ..< count:
    doAssert due[i] == $i, "reordered at " & $i & ": " & due[i]

echo "Testing the queue is bounded and overflow is counted"
block:
  netSimReset()
  netSimConfigure(freshCfg(10_000, 0, 0.0)) # 10s delay: nothing releases
  let t = 0'i64
  for i in 0 ..< (MaxQueue + 500):
    discard netSimOffer(DirInbound, $i, t)
  doAssert netSimQueueDepth(DirInbound) == MaxQueue, $netSimQueueDepth(DirInbound)
  doAssert netSimStats(DirInbound).dropped == 500

echo "Testing disabled directions bypass the sim independently"
block:
  netSimReset()
  netSimConfigure(NetSimConfig(enabled: true, latencyMs: 100, jitterMs: 0,
    packetLossPercent: 0.0, delayOutbound: true, delayInbound: false))
  doAssert netSimActive(DirOutbound)
  doAssert not netSimActive(DirInbound)

echo "Testing preset names parse (and reject unknowns)"
block:
  doAssert parsePreset("poor") == (true, PresetPoor)
  doAssert parsePreset("EXTREME") == (true, PresetExtreme)
  doAssert parsePreset("500") == (true, PresetExtreme)
  doAssert parsePreset("bogus")[0] == false
  doAssert parsePreset("off")[0] == false, "off is disable, not a preset"

echo "Testing --netsim specs: presets, off, and 100+/-50[,loss]"
block:
  block preset:
    let (ok, cfg) = parseNetSimArg("good")
    doAssert ok and cfg.enabled and cfg.latencyMs == 100 and cfg.jitterMs == 20
  block off:
    let (ok, cfg) = parseNetSimArg("off")
    doAssert ok and not cfg.enabled
  block custom:
    let (ok, cfg) = parseNetSimArg("100+/-50")
    doAssert ok, "100+/-50 must parse"
    doAssert cfg.enabled and cfg.latencyMs == 100 and cfg.jitterMs == 50
    doAssert cfg.packetLossPercent == 0.0
  block customLoss:
    let (ok, cfg) = parseNetSimArg("250+/-40,loss=2.5")
    doAssert ok and cfg.latencyMs == 250 and cfg.jitterMs == 40
    doAssert abs(cfg.packetLossPercent - 2.5) < 0.001
  block unicode:
    let (ok, cfg) = parseNetSimArg("100±50")
    doAssert ok and cfg.latencyMs == 100 and cfg.jitterMs == 50
  block reject:
    doAssert not parseNetSimArg("nope")[0]
    doAssert not parseNetSimArg("")[0]
    doAssert not parseNetSimArg("-10+/-4")[0]

echo "Testing documented presets are 0 / 100 / 250 / 500 ms one-way"
block:
  doAssert presetConfig(PresetLocal).latencyMs == 0
  doAssert presetConfig(PresetLocal).jitterMs == 0
  doAssert presetConfig(PresetGood).latencyMs == 100
  doAssert presetConfig(PresetPoor).latencyMs == 250
  doAssert presetConfig(PresetExtreme).latencyMs == 500
  doAssert presetConfig(PresetGood).jitterMs > 0
  doAssert presetConfig(PresetPoor).jitterMs > 0
  doAssert presetConfig(PresetExtreme).packetLossPercent > 0.0

echo "Testing F7 cycles off → local → good → poor → extreme → off"
block:
  netSimReset()
  netSimEnable(false)
  doAssert netSimCycleIndex() == 0
  netSimAdvanceCycle()
  doAssert netSimLabel() == "local" and netSimConfig().latencyMs == 0
  netSimAdvanceCycle()
  doAssert netSimLabel() == "good" and netSimConfig().latencyMs == 100
  netSimAdvanceCycle()
  doAssert netSimLabel() == "poor" and netSimConfig().latencyMs == 250
  netSimAdvanceCycle()
  doAssert netSimLabel() == "extreme" and netSimConfig().latencyMs == 500
  netSimAdvanceCycle()
  doAssert netSimLabel() == "off" and not netSimConfig().enabled
  netSimSetLogging(false)

echo "Testing 100ms ± 50ms stays inside [50, 150] and never goes negative"
block:
  netSimReset()
  netSimSeed(2026)
  netSimConfigure(freshCfg(100, 50, 0.0))
  var lo = high(int)
  var hi = low(int)
  for _ in 0 ..< 8000:
    let d = computeDelayMs()
    doAssert d >= 50 and d <= 150, "100±50 out of range: " & $d
    lo = min(lo, d)
    hi = max(hi, d)
  doAssert lo <= 60 and hi >= 140, "100±50 did not span the band"

echo "Testing inbound loss is off by default (tape stays reliable)"
block:
  netSimReset()
  netSimConfigure(freshCfg(0, 0, 100.0)) # 100% loss
  let t = 0'i64
  doAssert netSimOffer(DirInbound, "tape", t),
    "inbound must not drop unless dropInbound is set"
  doAssert netSimDue(DirInbound, t) == @["tape"]
  doAssert not netSimOffer(DirOutbound, "intent", t),
    "outbound takes the loss"
  doAssert netSimStats(DirOutbound).dropped == 1

echo "Testing dropInbound lets loss hit the tape path"
block:
  netSimReset()
  var cfg = freshCfg(0, 0, 100.0)
  cfg.dropInbound = true
  netSimConfigure(cfg)
  doAssert not netSimOffer(DirInbound, "tape", 0'i64)
  doAssert netSimStats(DirInbound).dropped == 1

echo "Testing both directions delay independently at a fixed 100 ms"
block:
  netSimReset()
  netSimConfigure(freshCfg(100, 0, 0.0))
  let t0 = 1_000_000'i64
  doAssert netSimOffer(DirOutbound, "up", t0)
  doAssert netSimOffer(DirInbound, "down", t0)
  doAssert netSimDue(DirOutbound, t0 + 99 * Ms).len == 0
  doAssert netSimDue(DirInbound, t0 + 99 * Ms).len == 0
  doAssert netSimDue(DirOutbound, t0 + 100 * Ms) == @["up"]
  doAssert netSimDue(DirInbound, t0 + 100 * Ms) == @["down"]

echo "Testing negative latency/jitter clamp and loss clamp"
block:
  netSimReset()
  netSimConfigure(NetSimConfig(
    enabled: true, latencyMs: -40, jitterMs: -9, packetLossPercent: 140.0,
    delayOutbound: true, delayInbound: true))
  let cfg = netSimConfig()
  doAssert cfg.latencyMs == 0
  doAssert cfg.jitterMs == 0
  doAssert cfg.packetLossPercent == 100.0

echo "Testing delayed packets release deterministically as the clock steps"
block:
  netSimReset()
  netSimConfigure(freshCfg(250, 0, 0.0))
  let t0 = 0'i64
  doAssert netSimOffer(DirInbound, "p", t0)
  var released = false
  var now = t0
  while now < t0 + 250 * Ms:
    doAssert netSimDue(DirInbound, now).len == 0
    now += Ms
  let due = netSimDue(DirInbound, t0 + 250 * Ms)
  doAssert due == @["p"]
  released = true
  doAssert released
  doAssert netSimStats(DirInbound).delayed == 1
  doAssert netSimStats(DirInbound).delivered == 1
  doAssert netSimQueueDepth(DirInbound) == 0

echo "All netsim tests passed."
