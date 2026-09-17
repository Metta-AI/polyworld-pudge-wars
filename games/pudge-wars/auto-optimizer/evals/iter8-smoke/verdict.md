# iter8-smoke — pudge-auto-optimizer:v11 (3bc6cbba) vs top-3 field

Request `xreq_7de665f4-f016-4f77-a735-a40f26d07554`, 3 episodes, completed 21:47Z.
Clean n=3, tainted 0, wins 3/3 (smoke only, no win-rate claim).
Policy logs (3/3 downloaded, `logs/`): 0 tracebacks, no rejected/malformed
action lines, both `connecting` and `received final message, exiting` present.

Instrumentation: `threat_seen` present in every game (161 / 250 / 248 events,
i.e. one per enemy throw seen), first-sight distance q25/50/75 = 38.7 / 39.3 /
39.6 tiles (min 6.2 = a hook that spawned inside the radius), so the 40-tile
`DODGE_RADIUS` is the binding limit — hooks are lit before 40 tiles; the dodge
now starts ~17 tiles (≈ 10–12 ticks) earlier than v10's 22-tile trigger.
28–39 % of first sightings happen while we are standing still (`speed < 0.5`).
Sides split roughly evenly (−1 / +1).

Verdict: smoke pass → launch the matched directional pair (n=40 each).
