# Iteration 4 — lead long hooks for the real flight time (divisor 30 → 12)

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v4` (`STATE.latest`,
`774d5ee5-d4ad-49de-82cc-54457a53041e`, source `2f4318c` = v1 + the
iteration-3 edge-band clamp; directional `xreq_4e49fbc4` n=40 0.750 ± 0.068).
Champion for the promotion gate: `pudge-auto-optimizer:v1`
(`a7afee99-e56f-40eb-ae64-6bc08f83ae71`, 0.410 ± 0.049 pooled over n=100).
Candidate arm: **not yet built** — see Results.
Status: **open** — hypothesis pre-registered 2026-09-17T06Z by
devin-4c31d8f4 before the change was written.

## Hypothesis record

**Observation.** Our seat throws **335 long hooks per game** (target ≥ 45
tiles away at launch: 157/game at 45–60, 178/game at 60+) and lands
**5.8% / 3.5%** of them (v4 directional replays, decoded this run with the
tick-verified headless build, `evals/iter3-directional/replay_survey.json`).
Those long throws are ~87% of all our throws; the 0–15 tile throws land 96%
but there are only 27/game. Our overall hook accuracy fell from 0.181 (v1)
to 0.147 (v4) once the clamp moved us off the edge, and our hook damage
dealt fell 27.4k → 22.2k/game while kills/game slipped 17.8 → 16.0. Offense
is now the side of the ledger with room: v4 wins on deaths (10.7/game), not
kills.

**Causal guess.** The aim lead is `target + v8 * span / (30 + speed_level)`
where `v8` is the target's displacement per 8 ticks, so the code assumes a
hook covers `span` tiles in `8 * span / 30 ≈ 0.27 * span` ticks (13 ticks
for a 50-tile throw). The engine's hook (`examples/pudge_wars/content.nim`)
launches at `BaseHookSpeed` 36 000 = 0.6 tiles/tick and accelerates by
1 800/tick to a 1.8 tiles/tick cap: a 50-tile throw takes **≈41 ticks**, a
60-tile throw ≈47. The lead is therefore about **one third** of the target's
expected travel — a target walking laterally at 0.3 tiles/tick has moved
~12 tiles by arrival while we led ~4. Leading for most of the true flight
time (divisor 12 → `8 * span / 12 = 0.67 * span` ticks ≈ 80% of the real
flight, leaving room for the target's late reaction) should convert more of
the 335 long throws.

**Evidence.** `tools/lead_sweep.py` on decoded replays (straight-flight
model against the target's real 4 Hz track, contact radius fitted so the
actual aim reproduces the engine's landed/missed outcome on 94% of throws):

| replay set | throws | span/30 (current) | span/20 | span/15 | **span/12** | span/10 | span/8 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v1 `xreq_3e9e30f4` (iter0, 6 507 throws) | 6 507 | 0.410 | 0.438 | 0.460 | **0.471** | 0.436 | — |
| v4 `xreq_4e49fbc4` (iter3, this run) | 7 331 | 0.396 | 0.417 | 0.443 | **0.459** | 0.420 | 0.337 |

Same peak on two independent replay sets; on v4 the gain holds for every
top-3 opponent (a-aron 0.402 → 0.451, richard 0.419 → 0.454, and largest
vs the strongest, `pudge-wars-rusher:v16` 0.366 → 0.476). The physics
above (`BaseHookSpeed`, `HookAccel`, `HookSpeedMax`) independently says the
current lead is ~3× short. Caveat, per the tool header and
`closed_levers.md`: the model's absolute rates are far above the real 8%
landed rate (it scores geometric proximity against a track that reacted to
the *real* hook, not the counterfactual one), so the sweep is directional
evidence for the *ordering* of divisors only. The 9 → 30 change in the old
native tournament was made with native seeds; this is a fresh hosted A/B,
which is what `closed_levers.md` asks for.

**Missing data.** Whether the wider lead is actually applied in the hosted
build and how big it is in practice. Added: `hook_lead` trace event
(existing `policy_trace` stream, joinable on `tick`) on every long throw
(span ≥ 30) with `span`, `lead` (tiles) and the target's speed estimate.
The mechanism metric itself — landed rate per target-distance bucket — comes
from replays via `tools/replay_survey.py` (`acc_by_target_dist`), so the
base arm needs no new signal.

**Change (exactly one).** In `BasePolicy.choose_action`, the aim-lead
divisor `30 + levels[2]` becomes `LEAD_DIVISOR + levels[2]` with
`LEAD_DIVISOR = 12`. Same velocity estimate, same span, same
`+ speed_level` term (faster upgraded hooks need less lead), same
fountain-line veto. Hold, dodge, blink, threat, shop, rune and rescue logic
are untouched; v5 = v4 + this one constant.

**Expected metric movement.** Mechanism (replays, candidate directional
n=40): long-hook landed rate 45–60 tiles 0.058 → ≥ 0.070 and 60+ 0.035 →
≥ 0.043 (+20% relative, half the modeled +16%…+30% gain); landed hooks on
enemies +3 to +5/game; hook damage dealt 22.2k → ≥ 24k/game; kills/game
16.0 → ≥ 17. Outcome: clean win rate ≥ v4's on the matched arm; a true +5 pp
is **not resolvable at n=40 (SE ≈ 0.07)**, so the win rate is a guard and
the mechanism metrics are the falsifiable part. Tripwires: own throws per
game (383) and deaths per game (10.7) must not worsen by more than 10%
(a longer lead can aim off-lane into the river veto or pull the hook line
across an ally — the ally check still runs on the final segment).

**Eval plan.** Smoke n=3 (0 tracebacks, `hook_lead` events present with
non-trivial `lead` values) → directional n=40 on the primary protocol
(`STATE.json` `eval_protocol`, roster [candidate, top_n=3], auto slots) for
**v5 and v4 in the same window** (v4's fresh arm doubles as the missing
v4 gate evidence: 40 more clean v4 episodes toward the ≥ 60 the iteration-3
verdict asks for) → gate n≈100 per arm only if v5 clears 2 pooled SE over
v4 or the mechanism metrics move as predicted with no tripwire.

**Overfit risk.** The divisor is fitted on the top-3 field's dodge
behaviour; an opponent that reverses direction on seeing a hook is
over-led by a longer lead (that is why the sweep falls off past span/10).
Mitigation: 12 is the sweep optimum on both replay sets, not the physical
flight time (that would be ≈ span/9.6 at cap speed), and it is a single
constant to revert. Our own upgrades change hook speed by +5%/level; the
`+ levels[2]` term keeps that behaviour.

**Rollback condition.** Candidate clean win rate ≤ v4 − 1 pooled SE in the
same window, or long-hook landed rate not up (45–60 bucket < 0.060), or
throws or deaths per game worse by > 10%, or any traceback. Rollback ref:
`pudge-auto-optimizer:v4` (base) / `pudge-auto-optimizer:v1` (champion).

## Results

Code landed in iteration 4 (`LEAD_DIVISOR = 12` in
`coworld/player/base.py`, `hook_lead` trace event on long throws; unit test
`test_long_hook_leads_for_the_flight_time`). The automation run of
2026-09-17T06Z (devin-4c31d8f4) **could not build the image**: `docker pull
python:3.12-slim` is redirected to `production.cloudfront.docker.com`,
which the automation network policy blocks (allowlist has
`production.cloudflare.docker.com` only); the post-change build attempt at
06:55Z did not even reach the blobs — `registry-1.docker.io` answered the
manifest HEAD with `429 Too Many Requests` (anonymous pull quota), also on
retry after 90 s. The campaign ECR image cannot be pulled as a base
(`ecr:BatchGetImage` denied to the pre-signed push role) and no alternate
registry is reachable — `STATE.json` → `blockers`, network-access requests
`…c5e64ee0`, `…51efe82b`, `…0fa27681` pending. No v5 exists;
no smoke or directional was launched for this iteration. Hosted spend this
run: 0 (budget at 06:52Z: spent 80.22 / 200 USD).

**Next run:** if `docker pull --platform linux/amd64 python:3.12-slim`
works, build `pudge-auto-optimizer:iter4` from branch HEAD, upload as v5,
write VERSION_LOG / ledger / STATE.latest, smoke `iter4-smoke`, then launch
`iter4-directional` (v5, n=40) and `iter4-directional-v4` (v4, n=40) in the
same window. Otherwise record the blocker again and stop.
