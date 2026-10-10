# Iteration 8 — start the walking dodge when the enemy hook becomes visible

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v10` (`6cc36a18-5a4e-499d-8aca-75e21ca9bf07`,
latest behaviour base = v4 + post-pull bank escape; v1 stays the formal
champion, see `STATE.pending_decisions`).
Candidate arm: `pudge-auto-optimizer:v11` (filled in on upload).
Session: devin-52d61dad7be8473f83537ef3c2c87f7e (mode ultra).
Status: **open** — hypothesis pre-registered 2026-09-17T21Z before the change
was written.

## Hypothesis record

**Observation.** The v10 directional replays (`../auto-optimizer/evals/iter7-directional/replay_survey.json`,
40 decoder-verified 1v1 episodes vs the top-3 field) show the dominant loss
chain is still *being pulled*: the enemy lands 6.5% of the ~308 long
(≥ 45-tile) hooks it throws at us per game (797 / 12 337 = **19.9 pulls per
game**) while we land 4.8% of ours on them (579 / 11 998 = 14.5). 489 of the
512 long hits on us land on our own bank at our fishing hold (inland offset
from the lip: q25/50/75 = 15.5 / 16.7 / 22.3 tiles, i.e. `hold_x = lip ± 16`).
Our speed at the moment of the hit (engine state sample ≤ 8 ticks before) is
bimodal: **24% stationary (< 2 tiles/s)**, another ~25% still accelerating
(2–10 tiles/s), ~50% at full speed. 49 of the 125 stationary hits have our
hook cooldown ≥ 48 (we were rooted by our own 9-tick cast windup); the other
76 were simply standing at the hold when the hook arrived.

**Causal guess.** The policy only reacts to an enemy hook once it is within
22 tiles (`threat = min(... distance(me, h) <= 22)`). Fog rules make every
enemy hook visible the moment it enters the river band (`fogCanSeeTeam`:
river tiles and the home bank are always lit), which from our hold is
~23 + 16 ≈ 40 tiles away. An outbound hook accelerates from 0.6 to 1.8
tiles/tick (`BaseHookSpeed`, `HookAccel`, `HookSpeedMax`), so at 22 tiles a
56-tile throw is ~12 ticks from impact; with the 1-tick reply latency and
the 8-tick acceleration ramp (`MoveAccel = MovePerTick / 8`) a pudge starting
from rest covers ≈ 3.6 tiles before the head arrives — less than the
5.35-tile latch disk (`BaseHookRadius` 2.75 + `PudgeCollisionRadius` 2.6).
Reacting at first sight (~40 tiles, ~25 ticks out) gives ≈ 9 tiles of
lateral movement, enough to clear the disk even from a standing start.
The stationary/slow half of the long hits is therefore a *reaction-time*
failure, not a direction failure, and is fixable without touching the
direction rule, the Blink dodge, or the counter-throw.

**Evidence.** Survey tabulation above (`opp_hits_on_me` rows with
`dist ≥ 45`, `my_layer ∈ {0,1}`, fields `my_speed`, `my_cd`, `my_x`); engine
constants from `examples/pudge_wars/content.nim` and fog rules from
`examples/pudge_wars/sim.nim` (`fogCanSeeTeam`, `riverTile`). Iteration-5
pull-exchange analysis: a pull where the puller holds the HP edge kills the
victim 66% of the time, so ~20 pulls/game ≈ the bulk of our 12.25
deaths/game. `closed_levers.md`: the *collision-aware filter* (ignore wide
hooks, v2/v3) is closed — that removed dodges; this change adds reaction
time and keeps every hook the base dodges. The perpendicular-Blink lever is
not touched (Blink dodge stays at ≤ 22 tiles).

**Missing data.** The policy does not log when it first sees a threat, so the
first-sight distance and the reaction window cannot be measured from the
current artifacts. Added instrumentation: a `threat_seen` trace event at the
first tick a dodge starts (`dist` to the hook head, `side`, own `speed`
estimate) so the next eval joins first-sight distance to replay hit/dodge
outcomes by tick.

**Change (one behaviour, code location).** `coworld/player/base.py`,
`BasePolicy.choose_action`: the walking dodge now triggers on the nearest
visible flying enemy hook within `DODGE_RADIUS = 40` tiles (was 22). The
defensive Blink hop, the `free` gate (rescue/heal/ward trips) and the ≤ 14
counter-throw keep the old 22-tile neighbourhood (`BLINK_THREAT_RADIUS`),
so only *when the legs start moving* changes. Direction rule (`dodge_side`),
dodge geometry (inland 2, lateral 10), hold, aim, escape and shop logic are
untouched.

**Expected metric movement.** Long (≥ 45-tile) enemy hooks landed on us per
game 19.9 → ≤ 15 (the stationary + accelerating half shrinks), our
long-hit-while-stationary share 24% → < 10%, deaths/game 12.25 → ≤ 10.5,
clean win rate vs top-3 up from 0.725 (n=40) by ≥ 0.10 directionally. Our own
long-hook landing rate should not fall (throws are not gated on the threat);
`my_river_sec`, drown deaths and `edge_clamp` counts are tripwires for
side effects of the longer dodge runs (drift toward the walls).

**Eval plan (protocol, n, label).** Smoke `iter8-smoke` (3 episodes vs
top-3): zero tracebacks, `threat_seen` events present with `dist` values
between 22 and 40. Then the matched directional pair on the identical
hosted protocol (league target, candidate + `top_n=3`, 1-tick trace level
as before): candidate `iter8-directional` (v11, n=40) and baseline
`iter8-baseline-v10` (v10, n=40) in the same window. Split by team side and
opponent; taint-filter first. Directional only; promotion needs the gate at
n=100 vs champion v1.

**Overfit risk.** A 40-tile threat keeps the pudge in dodge mode roughly
twice as long (each enemy throw ≈ 25 visible ticks instead of ≈ 12), so it
runs ~8–10 tiles per enemy throw instead of ~4, drifts more (rune pickups,
wall proximity) and in 3v3 also dodges hooks aimed at teammates 30 tiles
down the lane. Against a field that rarely throws long hooks the change is a
no-op. The direction heuristic (away from the hook head's y) is applied
earlier in flight, when the head's y is closer to the thrower's than to the
aim point; if that flips the chosen side against a led throw the gain
shrinks — measured by the stationary share and the landed-on-us rate.

**Rollback condition.** Candidate clean win rate below the matched v10
baseline by more than 1 pooled SE, or long hooks landed on us per game not
lower than v10's 19.9, or deaths/game not lower — then revert
`DODGE_RADIUS` to 22 (v10 behaviour, `6cc36a18-5a4e-499d-8aca-75e21ca9bf07`).

## Verdict

Decision: weak_evidence (v11 becomes the behaviour base for iteration 9;
not promoted — promotion needs the n=100 gate against champion v1).

Numbers (harvested 2026-09-18T00:5xZ, same protocol/window, league target +
top_n=3; both requests still "running" 3 h after creation with the last
6 / 5 episodes stuck in `submitted`, so the arms are read at 34 / 35):

| arm | clean n | tainted | win rate ± SE | west | east | vs a-aron-pudge-rusher:v1 | vs co-gas-…-richard:v7 | vs pudge-wars-rusher:v16 |
|---|---|---|---|---|---|---|---|---|
| v11 candidate `xreq_f5666240` | 34 | 6 (never dispatched) | 0.735 ± 0.076 | 0.706 (17) | 0.765 (17) | 0.700 (10) | 0.846 (13) | 0.636 (11) |
| v10 baseline `xreq_d3f7c348` | 35 | 5 (never dispatched) | 0.600 ± 0.083 | 0.778 (18) | 0.412 (17) | 0.600 (10) | 1.000 (10) | 0.333 (15) |

Delta +0.135, pooled SE 0.113 → +1.2 SE (inside the 2-SE band: not a
promotion-grade signal at n≈35). Log triage: 0 tracebacks in either arm;
2 (v11) / 5 (v10) policy logs lost ("pod was deleted before log
collection") — the decoded replays show those seats threw 134–424 hooks,
so they are participating, clean episodes with no crash check. All 69
replays decoded with the matching binary (`every tick matched`).

Mechanism (replay_survey + hit_exposure over the decoded replays, per game):

| metric | v11 | v10 | prereg. |
|---|---|---|---|
| long (≥45-tile) enemy hooks landing on us | 9.5 | 12.6 | ≤ 15 of the v10-directional 19.9-by-launch-target count (met on the matched measure: −25 %) |
| all enemy hooks landing on us | 33.5 | 41.2 | — |
| share of long hits while we stand still (< 2 tiles/s) | 21.7 % | 31.1 % | < 10 % (missed) |
| share while accelerating (2–10 tiles/s) | 11.5 % | 25.4 % | — (the ramp-up window the change targets) |
| share while still rooted by our own cast (cd ≥ 48) | 15.5 % | 14.1 % | — |
| deaths / game | 9.15 | 12.03 | ≤ 10.5 (met) |
| kills / game | 15.2 | 15.1 | tripwire −1.5 (pass) |
| hooks thrown / game | 378 | 370 | — |
| river seconds / game | 3.7 | 7.1 | tripwire +1 s (pass) |
| runes / game | 30.5 | 32.1 | tripwire −3 (pass, −1.6) |
| edge_clamp events / game | 438 | 432 | tripwire +20 % (pass) |

threat_seen (v11 logs, 7450 events, 219/game): first sight at 38.7–39.6
tiles (q25–q75), i.e. hooks are lit at the radius, and 56 % of first
sights happen while we stand still — the early start does what it was
meant to (deaths −2.9/game, hits on us −19 %, moving-share of hits up).

Side-effect finding (dodge_geometry over the same replays): with the early
start, *which way* we run now matters. Of the 324 long enemy hooks that
landed on us in the v11 arm, 186 (57 %) hit while we were running
*toward* the hook's flight line; hit rate 6.8 % when running toward the
line vs 2.8 % away (v10: 7.3 % vs 6.5 %, no asymmetry because it barely
moved). The side rule "away from the hook head's y" puts us on the aimed
side whenever the thrower leads us → iteration 9 lever.

Reason: the predicted mechanism is present and every tripwire passes, but
the win-rate delta is +1.2 pooled SE at n≈35 and the 1v1 seating caveat
still applies, so this is weak evidence, not a promotion. Consistent with
iterations 3 and 7, the candidate becomes the behaviour base; the champion
question is deferred to the n=100 gate (v11 vs v1) recorded in
STATE.pending_decisions.
Rollback: pudge-auto-optimizer:v10 (6cc36a18-5a4e-499d-8aca-75e21ca9bf07).
