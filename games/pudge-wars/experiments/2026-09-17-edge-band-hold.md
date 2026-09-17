# Iteration 3 — keep the fishing hold out of the map-edge band

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v1` (champion,
`a7afee99-e56f-40eb-ae64-6bc08f83ae71`, source `d1f6d7c`). Pre-registered
on v3, re-based on v1 the same run once the v3 directional fired the
collision-threat experiment's rollback condition (deaths +1.37/game; see
`2026-09-17-collision-threat.md`) — v4 = v1 + this one change, so the
comparison to the champion stays single-cause.
Candidate arm: `pudge-auto-optimizer:v4`. Comparison arms available in the
same protocol: v1 champion `xreq_3e9e30f4` (n=40, harvested), v3
`xreq_e43bf971` (n=40, harvested, rejected).
Status: **open** — hypothesis pre-registered before the change was written;
code landed, image not yet built (Docker Hub CDN blocked, see Results).

## Hypothesis record

**Observation.** In the hosted lobby the roster is two seats (1v1 despite
the 3v3 variant), so `allies` is empty and the fishing hold line
`y = (target.y if target else me.y) + juke * 1.5` has no anchor: it mirrors
the enemy's y or random-walks with the juke. The v1 baseline spent **31% of
its own-bank time within 8 tiles of the top/bottom edge** (y < 24 or
y > 104); long enemy hooks aimed at it there landed **16.4%** of the time
vs **9.6%** in the lane band and **8.9%** mid — 40% of all long hooks that
caught us (6.9 of 16.7 per game) were caught in the edge band. The best
opponent, `pudge-wars-rusher:v16`, spends 19% of its time there and is hit
at 9% there (it keeps moving); the two clones behave like us (30% edge,
17–20% landed).

**Causal guess.** Against a wall only one lateral dodge direction exists,
the dodge code already special-cases `me.y < 20` / `> 108`, and the
mirrored-y hold means the thrower's straight hook needs no lead at all
(the target is stationary on its lane line). Standing in the edge band
roughly doubles the catch rate per hook aimed at us; those catches are the
majority of our deaths (hook-caught deaths were 75% of our deaths in the
baseline survey), and deaths, not kills, are what separate us from v16
(kill margin −5.2 vs v16, −0.6 overall).

**Evidence.** [`../auto-optimizer/evals/iter0-directional/edge_exposure.json`](../auto-optimizer/evals/iter0-directional/edge_exposure.json)
(40 clean v1 episodes, decoder-verified replays, `tools/edge_exposure.py`):
me edge share 0.31 / landed 0.164 (n=1685 long hooks aimed at us there),
lane 0.47 / 0.096 (n=2751), mid 0.22 / 0.089 (n=1404). Per-opponent split
holds against all three top-3 opponents (edge landed 0.17 / 0.20 / 0.09 vs
lane 0.09 / 0.11 / 0.10). [`replay_survey.json`](../auto-optimizer/evals/iter0-directional/replay_survey.json):
our y distribution q10 20.6 / q90 111.5 vs v16 q10 33 / q90 96.
`closed_levers.md` has no entry on hold position; the roadmap's healing /
rune / capture-prevention levers are untouched.

**Missing data.** Whether the clamp actually binds in the hosted build.
Added: `edge_clamp` trace event (existing `policy_trace` stream, joinable on
`tick`) emitted at most once per 32 ticks while the hold y is being clamped,
with the raw and clamped y. The mechanism metric itself (own-bank y band
share, landed rate per band) comes from replays via `tools/edge_exposure.py`
on the candidate's directional episodes, so the baseline arm needs no new
signal.

**Change (exactly one).** In `BasePolicy.choose_action`, the fishing hold y
(the `walk_to = [hold_x, y]` branch) is clamped to `[30, 98]` before use —
never inside the edge band, leaving ≥14 tiles to either wall for a 10-tile
dodge. Formation lanes (40/64/88) already satisfy this, so the 3v3 path is
unchanged; only the solo mirror/random-walk hold and the rune approach are
affected. Aim, dodge, blink, threat, shop, rune and rescue logic are untouched.

**Expected metric movement.** Mechanism (replays, candidate directional
n=40): own-bank edge share 0.31 → ≤ 0.10; long hooks landing on us per
game 16.7 → ≤ 14.5 (edge catches move to lane rate); deaths per game 18.3 →
≤ 16.5. Outcome: clean win rate +5 to +10 pp over the v1 champion arm;
at n=40 (SE ≈ 0.08) this is directional only, the mechanism metrics are the
falsifiable part. Tripwires: our own hook accuracy (0.181) and throws per
game (384) must not drop by more than 10% (a hold farther from an edge-hugging
enemy lengthens our throws); rune hooks per game must not fall (rune approach
y is clamped too).

**Eval plan.** Smoke n=3 (0 tracebacks, `edge_clamp` events present with
non-trivial raw y) → directional n=40 on the primary protocol (`STATE.json`
`eval_protocol`, roster [candidate, top_n=3], auto slots), with a fresh
equal-n v1 champion arm launched in the same window (the 2026-09-17T02Z
`xreq_3e9e30f4` is the historical anchor, not the matched arm, once the
candidate runs on a later day) → gate n≈100 only if the directional clears
2 pooled SE over v1.

**Overfit risk.** The band is measured on our own v1 replays against this
week's top-3 field. The geometric argument (one dodge direction, unled
hooks) is opponent-agnostic and v16's low edge exposure corroborates it, but
a future edge-camping opponent could sit out of our clamped reach at y≈17;
our hooks reach 60+ tiles so a 13-tile y offset costs little range. Rune
spawns near the edges become slightly longer throws.

**Rollback condition.** Candidate clean win rate ≤ v1 − 1 pooled SE in the
same window, or edge share not reduced below 0.15 (change did not bind), or
our hook accuracy / throws per game down > 10%, or any traceback. Rollback
ref: `pudge-auto-optimizer:v1`.

## Results

_pending_ — code landed in iteration 3 (`BasePolicy.choose_action` clamps the
fishing hold y to `[HOLD_Y_MIN, HOLD_Y_MAX] = [30, 98]`, `edge_clamp` trace
event every 32 ticks while the clamp binds; unit test
`test_solo_hold_stays_out_of_the_edge_band`). The v4 image could **not** be
built in the 2026-09-17T03Z run: `docker pull python:3.12-slim` is redirected
to `production.cloudfront.docker.com`, which the automation network policy
blocks (see `STATE.json` → `blockers`). Not uploaded, not evaluated. Next run:
build `pudge-auto-optimizer:iter3`, upload v4, smoke, then the directional.
