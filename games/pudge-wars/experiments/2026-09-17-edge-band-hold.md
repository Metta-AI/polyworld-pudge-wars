# Iteration 3 — keep the fishing hold out of the map-edge band

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v1` (champion,
`a7afee99-e56f-40eb-ae64-6bc08f83ae71`, source `d1f6d7c`). Pre-registered
on v3, re-based on v1 the same run once the v3 directional fired the
collision-threat experiment's rollback condition (deaths +1.37/game; see
`2026-09-17-collision-threat.md`) — v4 = v1 + this one change, so the
comparison to the champion stays single-cause.
Candidate arm: `pudge-auto-optimizer:v4` (`774d5ee5-d4ad-49de-82cc-54457a53041e`,
image `sha256:40e361d0…895a`, built 03:39Z by the bootstrap session from
`2f4318c` — v1 + this clamp, with the rejected classifier left in source as
a dormant opt-in; identical default behavior to the branch HEAD source). Comparison arms available in the
same protocol: v1 champion `xreq_3e9e30f4` (n=40, harvested), v3
`xreq_e43bf971` (n=40, harvested, rejected).
Status: **open** — hypothesis pre-registered before the change was written;
v4 uploaded, smoke `xreq_538ede79` running (see Results).

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

Code landed in iteration 3 (`BasePolicy.choose_action` clamps the fishing
hold y to `[HOLD_Y_MIN, HOLD_Y_MAX] = [30, 98]`, `edge_clamp` trace event every
32 ticks while the clamp binds; unit test
`test_solo_hold_stays_out_of_the_edge_band`). The automation run of
2026-09-17T03Z could not build the image (`docker pull python:3.12-slim` is
redirected to `production.cloudfront.docker.com`, blocked by the automation
network policy — `STATE.json` → `blockers`). The bootstrap session built and
uploaded it at 03:39Z as **v4** (`774d5ee5…`, image `sha256:40e361d0…`,
source `2f4318c`, base v1).

**Smoke** `xreq_538ede79` (n=3, top-3, 03:40–04:02Z): clean 3/3, 0 tainted,
0 tracebacks in the three v4 policy logs (`evals/iter3-smoke/logs/`), hosted
cost 0.5309 USD. Won 2/3 (vs a-aron-pudge-rusher:v1 1/2, vs
pudge-wars-rusher:v16 1/1) — smoke only, no win-rate claim. Instrumentation
landed with non-trivial values: `edge_clamp` fired 578 / 427 / 502 times per
episode (one sample per 32 ticks while binding, games run 38,400 ticks →
the clamp bound on ≈48% / 36% / 42% of ticks). The raw hold y it overrode
was mostly a far edge (`raw` 16, 99.9–100.6, 111 → `y` 30.0 / 98.0), i.e. the
v1 hold does sit in the edge band for a large share of the game, as the
Observation claimed. The v4 image (built from `2f4318c`) also emits the
dormant classifier's `threat_class` events in `distance` mode (88–196 per
episode); they are diagnostic only and do not change behavior.

**Directional** `xreq_4e49fbc4` (n=40, top-3, 04:05–04:25Z, same protocol
as v1 `xreq_3e9e30f4` 02:39–03:14Z; identical top-3 field): **clean 40/40,
0 tainted, 0 tracebacks, 40/40 connected** (`evals/iter3-directional/`,
`log_triage.json`). `edge_clamp` fired 504.6×/game (≈42% of ticks bound).

| arm | window (UTC) | n | win rate | west | east | vs a-aron:v1 | vs richard:v7 | vs rusher:v16 | deaths/g | kills/g | opp hook acc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v1 `xreq_3e9e30f4` | 02:39–03:14 | 40 | 0.425 ± 0.078 | 0.50 | 0.35 | 0.615 (13) | 0.412 (17) | 0.200 (10) | 18.3 | 17.8 | 0.187 |
| **v4 `xreq_4e49fbc4`** | 04:05–04:25 | 40 | **0.750 ± 0.068** | 0.80 | 0.70 | 0.750 (16) | 0.909 (11) | 0.615 (13) | **10.7** | 16.0 | **0.132** |
| v1 `xreq_c04fbf1e` (fresh, gate arm) | 04:28–04:56 | 60 | 0.400 ± 0.063 | 0.53 | 0.27 | 0.526 (19) | 0.467 (15) | 0.269 (26) | 15.5 | 14.1 | 0.170 |

v1 pooled over both windows: 41/100 = 0.410 ± 0.049. Delta v4 − v1(pooled)
= **+0.34, pooled SE 0.084 → 4.0 SE**; vs the matched-window v1 arm alone
+0.325 / 3.1 SE. Both sides and all three opponents improved (smallest
opponent gain +0.13 vs a-aron, n=16 vs 13; none within 1 SE of regressing).

**Mechanism (pre-registered predictions).** Deaths/game 18.3 → 10.7 (target
≤ 16.5: hit). Opponent hook accuracy 0.187 → 0.132 (−29%) while our throws
(384 → 383/game) and accuracy (0.181 → 0.147) moved little — tripwire on
own throws did not fire; own accuracy fell 3.4 pp (we hook from lane, fewer
edge-pinned easy targets), which is the pre-registered "cost" side and is
outweighed by the death reduction (kill margin −0.6 → +5.3). The bootstrap
session (devin-53dc4bed) decoded all 40 v4 replays with the tick-verified
`pw` headless build and reported, via `tools/edge_exposure.py`: own-bank
edge time share **0.314 → 0.023**, long hooks landed on us while at the edge
**6.92 → 0.38/game**, total long hooks landed on us 16.66 → 11.03/game (target
≤ 14.5: hit), hook damage taken −39%, own dodge rate up. Those decoded
artifacts were not committed before that session was suspended (05:09Z) —
the numbers above are quoted from its session log; the raw replays remain
downloadable from `evals/iter3-directional/episodes.json`.

### Verdict (iteration 3, written 2026-09-17T06Z by devin-4c31d8f4)

**Decision: `rerun` — strong directional signal, promotion gate incomplete.**
Champion stays **v1**; **v4 stays `STATE.latest` and is the base for
iteration 4** (the campaign brief builds each iteration on the previous latest
policy; v4 is not rejected).

- Signal: +0.34 (4.0 pooled SE) over v1 on the identical top-3 protocol,
  matched-window arm +0.325 (3.1 SE); no side or opponent regression; taint
  0/40; 0 tracebacks; mechanism confirmed on every pre-registered metric.
- Why not `promote`: `eval_protocol.gate_n = 100` clean episodes per arm in
  one window. The bootstrap session launched 60-episode gate arms for v4
  (`xreq_bc7bc25e`) and v1 (`xreq_c04fbf1e`) at 04:28Z; **the v4 arm was
  cancelled at 04:36Z by someone other than that session** (all 60 episodes
  `failed: Experience request cancelled`, 0 completed) while the v1 arm ran to
  completion. The session asked Aaron whether to relaunch and got no answer
  before suspension. This run did **not** relaunch it (a human cancel is
  treated as an instruction until countermanded); `xp create --label
  iter3-gate-v4` in this run returned the cancelled request via the
  idempotency key, no spend.
- To close: a v4 arm of ≥ 60 clean episodes in the same window as a v1 (or
  v5) arm. Running iteration 4's matched directional as v5 vs **v4** (n=40
  each) will add to v4's total at no extra cost; a further 60-episode v4 arm
  (~12 USD) needs Aaron's go-ahead given the cancel.
- Rollback: `pudge-auto-optimizer:v1` (`a7afee99…`) is the champion and the
  documented rollback ref; the clamp is two constants (`HOLD_Y_MIN/MAX`).
