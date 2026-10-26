# Network-condition simulator

A local latency / jitter / packet-loss simulator for the Fresh Meat
**follower** (the browser/native client that joins a hosted match). It lets
you feel and measure the game under 100 / 250 / 500 ms links without a real
WAN, and it drives a developer debug panel.

It is **off by default** and inert in production: when disabled the transport
paths bypass it entirely, so the client behaves bit-for-bit like it did
before the simulator existed.

## Local test recipe

You need two processes: an unsimulated **host** and a follower whose packets
are delayed. Do not put `--netsim` on the host — the sim lives on the
client, and the host tick rate stays 32 Hz either way.

**1. Host (terminal 1)** — ordinary LAN party, no extra latency:

```
examples/pudge_wars/host_party.sh --autostart --human --name Host
```

`--autostart` skips the lobby so you can join immediately. Leave this window
running; it *is* the server.

**2. Native follower (terminal 2)** — this is the window you play and debug:

```
./pw --join ws://127.0.0.1:8000/ws --slot 2 --name Lag --netsim poor
```

`--slot` is 1-based (2 = the second seat). Presets and custom specs:

```
./pw --join ws://127.0.0.1:8000/ws --slot 2 --name Lag --netsim 100+/-50
./pw --join ws://127.0.0.1:8000/ws --slot 2 --name Lag \
  --netsim-latency 250 --netsim-jitter 40 --netsim-loss 2
```

**3. Browser follower** — same sim, query params (rebuild wasm if the
client is stale: `nim c -d:emscripten examples/pudge_wars/pw.nim`):

```
http://127.0.0.1:8000/play/pw.html?join=1&slot=1&name=Lag&netsim=poor
http://127.0.0.1:8000/play/pw.html?join=1&slot=1&name=Lag&netsim=100%2B/-50
```

(`slot` in the URL is 0-based. `+` in `100+/-50` must be encoded as `%2B`.)

**4. Headless soak** — hash-exact follow under lag, no window:

```
nim c -r examples/pudge_wars/pw_follow.nim \
  --join ws://127.0.0.1:8000/ws --slot 2 --name Soak --netsim 250+/-50
```

Expect `mismatches 0`. A dropped inbound tape slice (only if you turn on
**Drop inbound** in the F3 panel) is a clean disconnect, not a crash.

In the follower window:

- **F6** — toggle the network overlay (bottom-left). Auto-opens when
  `--netsim` is already on.
- **F7** — cycle preset: off → local → good → poor → extreme.
- **F3** — sliders for latency, jitter, loss, and per-direction delay.
  F9/F10 stay MENU/TEAM.

What “good” looks like: at a fixed 100 ms one-way, measured ping on the
overlay settles near **200 ms RTT**, the butcher is delayed but walks
smoothly, sim stays **32 Hz**, and render FPS is unchanged. Jitter makes
ping wander inside `latency±jitter` (times two, because both directions
are delayed). Loss drops outbound intents; prediction then snaps.

## Where it sits

`netsim.nim` is a seam between `netclient`'s transport and the game:

```
intents / pings ──▶ transportSend ──▶ [outbound queue] ──▶ raw socket ──▶ host
host tape / pong ──▶ recvQueue ──▶ takeReceived ──▶ [inbound queue] ──▶ pendingMessages
```

Each direction has an independent FIFO delay queue. A packet is held until
`now + latency ± jitter`, or dropped with probability `packetLossPercent`.

Design guarantees (see the module header and `test_pw_netsim.nim`):

- **Order is preserved.** Release times are clamped monotonic per direction,
  so jitter never reorders the tape (an out-of-order tape slice would desync
  the lockstep follower). A late packet holds up the ones behind it, exactly
  like a real ordered link.
- **Delays are never negative** — `latency + jitter` is floored at 0.
- **Queues are bounded** (`MaxQueue = 8192`); overflow drops the oldest and
  counts it, so a stalled pump can't grow memory without bound.
- **Deterministic** — jitter and loss draw from a seedable splitmix64
  (`netSimSeed`), so a seeded run reproduces exactly.
- **The clock is injected** — every entry point takes `nowUs`, so tests drive
  time with no real waiting; `netclient` passes wall-clock.

## Latency model

`latencyMs` is a **one-way** baseline applied to each enabled direction.
With both directions on (the default), measured **round-trip ping ≈ 2 ×
latencyMs** plus real network + host time. The debug panel shows both the
configured one-way value and the measured RTT.

**Packet loss applies to outbound only by default.** The host tape is a
reliable ordered stream, so dropping a tape slice would just desync the
lockstep follower. Dropping an *outbound* packet is realistic and safe — a
lost intent simply doesn't reach the authoritative host (the client's
prediction then reconciles with a snap), and a lost ping is a missed RTT
sample. To exercise the tape drop-detection path deliberately, set
`dropInbound = true` in a custom config; it surfaces as a **clean
disconnect** ("tape stream skipped…"), never corruption or a crash.

The simulation tick rate is **not** tied to latency: the game always ticks at
`TickRate` (32 Hz) and rendering/prediction stay independent, so a fixed
latency feels delayed but smooth.

## Presets

| Preset  | one-way latency | jitter  | loss | feel                       |
|---------|-----------------|---------|------|----------------------------|
| local   | 0 ms            | 0       | 0 %  | passthrough                |
| good    | 100 ms          | ±20 ms  | 0 %  | ~200 ms RTT, steady        |
| poor    | 250 ms          | ±50 ms  | 1 %  | ~500 ms RTT, choppy        |
| extreme | 500 ms          | ±120 ms | 5 %  | ~1 s RTT, drops, spikes    |

Shorthand: `--netsim 0|100|250|500` maps to those presets. A custom spec
does not: `--netsim 100+/-50` is 100 ms ± 50 ms with no loss, not “good”.

## How to enable

**Native** (join a host, including the recipe above):

```
./pw --join <ws-url> --slot 2 --name Lag --netsim poor
pw_follow --join <wss-url> --token <tok> --slot=1 --netsim 100+/-50
```

**Browser** — add a `netsim` query param to the play URL:

```
/play/pw.html?join=<wss>&token=<tok>&slot=0&netsim=poor
/play/pw.html?join=1&slot=0&netsim=100%2B/-50&netsim-loss=2
```

**In-game** (follower only):

- **F6** — toggle the network debug overlay (bottom-left).
- **F7** — cycle the preset: off → local → good → poor → extreme.
- **F3** — latency / jitter / loss sliders and per-direction checkboxes.

The overlay shows: configured latency ± jitter and loss %, measured RTT and
jitter, the constant 32 Hz sim tick rate, render FPS, per-direction packet
counters (sent, delayed, dropped, queue depth), and a rolling ping graph.

Structured anomaly logging (queue growth, drops, overflow) prints to the
console when the sim is enabled (`netSimSetLogging(true)`, set automatically
by `--netsim`, the URL param, and F7).

## Reproducing the test scenarios

Unit tests (no real time passes — the clock is injected):

```
nim c -r tests/test_pw_netsim.nim
nim c -r tests/test_pw_net.nim
```

They verify: zero latency behaves like the unsimulated client; fixed latency
delays by ~the configured amount; jitter varies within
`[latency−jitter, latency+jitter]` and never negative; packet loss follows
the configured probability (seeded); FIFO order is preserved under jitter;
the queue is bounded and overflow is counted; seeded runs reproduce exactly;
disabled directions bypass independently; inbound loss is off unless
requested; and a short lockstep match stays hash-exact at 0 / 100 / 250 /
500 ms (follower lags, then catches up, tick rate unchanged).

Prediction quality under the same presets (snaps / jerk, hashes must stay 0):

```
nim c -r tests/bench_pw_netlag.nim
```

End-to-end determinism under load (a real hosted match — the follower must
still verify every tick hash while packets are delayed and occasionally
dropped):

```
pw_follow --join <wss> --token <tok> --slot=1 --netsim poor   # expect: mismatches 0
```

Stability sweep: run the above at `--netsim local|good|poor|extreme` and
confirm the follower reaches game-over (or a clean disconnect on a dropped
tape slice) with no crash and bounded memory.
