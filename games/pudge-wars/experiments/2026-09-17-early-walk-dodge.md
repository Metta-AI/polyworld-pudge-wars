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

Decision: pending
Numbers: pending (candidate w±se vs v10 w±se on the same protocol/window,
clean n / tainted n, per-team, per-opponent, long-hits-on-us/game,
stationary share, deaths/game)
Reason: pending
