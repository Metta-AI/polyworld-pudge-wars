# Iteration 9 — run away from the enemy hook's flight line, not from its head

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v11` (`3bc6cbba-bb4e-444f-8fc8-c2b09459fa43`,
latest behaviour base = v4 + post-pull bank escape + early walking dodge;
v1 stays the formal champion, see `STATE.pending_decisions`).
Candidate arm: `pudge-auto-optimizer:v12` (filled in on upload).
Session: devin-8a7b92c6d78c4c3b83467c46ef14ec54 (mode ultra).
Status: **open** — hypothesis pre-registered 2026-09-18T01Z before the change
was written.

## Hypothesis record

**Observation.** With the early walking dodge (v11), *which way* we run
decides whether the long hook lands. Over the 34 decoder-verified v11
directional replays (`../auto-optimizer/evals/iter8-directional/dodge_geometry.json`,
7 614 enemy hooks launched at us from ≥ 30 tiles, 224/game): the hook lands
6.8% of the time when our lateral velocity at the last engine sample before
impact points *toward* the hook's flight line (n=2 734) versus 2.8% when it
points *away* (n=1 954) and 2.9% when we are laterally still (n=2 926). 186
of the 324 long hits on us (57%) are "running toward the line" hits. In the
matched v10 arm (`iter8-baseline-v10/dodge_geometry.json`) the split is flat
(7.3% vs 6.5% vs 5.4%) because v10 barely moved before the head was 22
tiles out — the asymmetry is created by the early start.

**Causal guess.** The side rule (`dodge_side = -1 if threat.y > me.y else 1`,
`BasePolicy.choose_action`) runs away from the hook *head's* y. At first
sight the head is ~40 tiles out, just past the far river lip, so its y is
essentially the thrower's y, not the aim point's. Every serious opponent
leads the throw (aim = our position + velocity × flight), so the flight
line passes *ahead* of us along our current motion while the thrower — and
the head — sit roughly level with us: the head rule is a coin flip with
respect to the line, and when we were already drifting (fishing sway, hold
approach, a previous dodge) it tends to keep us moving *into* the led aim
point. Choosing the side by the signed offset of our position from the
flight line (heading = the head's displacement between two consecutive
observations, hooks fly straight while `flying`) puts the run on the far
side of the line every time the hook is seen twice before we commit.

**Evidence.** `dodge_geometry.py` tabulation above (hit rate by lateral
run direction at impact, by arm); `hit_exposure.json` for both arms: 67% of
v11's long hits on us now land while we move at full speed (v10: 44%), so
reaction time is no longer the dominant residual — direction is. Engine:
outbound hooks fly a straight line from cast to aim (`applyHookFine`,
`sim.nim`), positions are reported to 0.001 tile and the head moves
0.6–1.8 tiles/tick, so a two-sample heading is accurate to well under a
degree. Fog: enemy hooks become visible on entering the river (~40 tiles
from the hold), so at the first lit tick there is *no* previous sample; the
second lit tick has one. `closed_levers.md`: the collision-aware *filter*
(v2/v3, ignore "wide" hooks) is closed — it removed dodges; this change
never ignores a hook, it only picks the side. The "more perpendicular
Blink" native lever is not repeated: the Blink hop geometry is unchanged
(it keeps using `dodge_side`; only how `dodge_side` is chosen moves).

**Missing data.** The policy does not log where the flight line is relative
to us when it commits to a side, so "chose the wrong side" cannot be read
from the current traces. Added to the existing `threat_seen` event: `off`
(signed offset of our position from the flight line, tiles) and `line`
(True when the side came from the flight line, False for the fallback).
Joinable to replay ticks as before.

**Change (one behaviour, code location).** `coworld/player/base.py`,
`BasePolicy.choose_action` + new `BasePolicy.dodge_direction`: the head of
every flying enemy hook is remembered per `owner_id` for one tick
(`hook_track`). When a dodge starts, the side is `sign(off) · sign(dx)` —
the lateral direction that increases our distance from the flight line
(`off` = signed perpendicular offset from the line through the last two
head positions). If the hook has been seen only once (first lit tick) the
decision waits one tick (`dodge_side` stays 0: no walking dodge and no
defensive hop that tick, the pudge continues its current order); if no
heading is available for two ticks, or the line is dead-on (|off| < 0.5
tile) or vertical, the old head rule applies. Edge clamps (y < 20 → +1,
y > 108 → −1), dodge geometry (inland 2, lateral 10; Blink 16/16),
`DODGE_RADIUS`, `BLINK_THREAT_RADIUS`, the counter-throw, hold, aim, escape
and shop logic are untouched.

**Expected metric movement.** Long (≥ 45-tile) enemy hooks landed on us per
game 9.5 → ≤ 7.5 (the ~3.2/game "toward the line" excess is the target);
share of long hits on us with lateral run toward the line 57% → < 35%;
deaths/game 9.15 → ≤ 8.0; clean win rate vs top-3 up from 0.735 (n=34)
directionally. `threat_seen.line` share ≥ 80% (most hooks are lit twice
before we commit). Tripwires: kills/game −1.5 (15.2), runes −3 (30.5),
river seconds +1 s (3.7), `edge_clamp` +20% (438/game), hooks thrown
−15/game (378).

**Eval plan (protocol, n, label).** Smoke `iter9-smoke` (3 episodes vs
top-3): zero tracebacks, `threat_seen` events carry `off`/`line`, `line`
True for the majority. Then the matched directional pair on the identical
hosted protocol (league target, candidate + `top_n=3`, same trace level):
candidate `iter9-directional` (v12, n=40) and baseline `iter9-baseline-v11`
(v11, n=40) in the same window. Split by team side and opponent;
taint-filter first; decode replays and rerun `dodge_geometry.py` on both
arms. Directional only; promotion needs the n=100 gate vs champion v1.

**Overfit risk.** The rule assumes a straight flight line: an opponent that
throws *behind* our motion (anti-lead, betting on a reversal) would now be
rewarded — the v11 data says the field leads. A one-tick wait at first
sight costs ~0.5 tile of lateral travel per dodge (25-tick window); if the
hook flickers in and out of fog the wait can reach two ticks before the
fallback. In 3v3 the nearest hook may be aimed at a teammate; running away
from *its* line is still the safe side for us. The side also drives the
defensive Blink hop (≤ 22 tiles), so a wrong heading (e.g. a hook seen
first at close range, curving on the reel) would misdirect the hop —
reel-phase hooks are excluded (`flying`).

**Rollback condition.** Candidate clean win rate below the matched v11
baseline by more than 1 pooled SE, or long hooks landed on us per game not
lower than v11's 9.5, or the toward-the-line share of hits not lower than
57%, or kills −1.5/game — then revert to the head rule (v11 behaviour,
`3bc6cbba-bb4e-444f-8fc8-c2b09459fa43`).

## Status (2026-09-18T01:20Z, run devin-8a7b92c6)

v12 uploaded inert at 00:35Z (`c161b426-ba59-45fe-b153-1faf6cb3ce22`, source
`ee01f0d`). Smoke `iter9-smoke` = `xreq_042a1d0d-c97d-4468-915a-469398085d9e`
created 00:37Z; after 43 min of polling all 3 episode requests were still
`submitted` (never dispatched) — the hosted queue was still draining the 11
undispatched iteration-8 episodes (v11 35/40, v10 36/40 completed by
01:20Z). The smoke gate was therefore not evaluated and the matched
directional pair was **not** launched. Next run: harvest the smoke, triage
logs + `threat_seen.off/line`, then launch `iter9-directional` (v12) and
`iter9-baseline-v11` (v11) back-to-back.

## Verdict

Decision: pending
Numbers: pending (candidate w±se vs v11 w±se on the same protocol/window,
clean n / tainted n, per-team, per-opponent, long-hits-on-us/game,
toward-line share, deaths/game, threat_seen.line share)
Reason: pending
