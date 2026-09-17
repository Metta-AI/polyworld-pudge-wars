# Iteration 4 — lead long hooks for the real flight time (divisor 30 → 12)

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Base arm: `pudge-auto-optimizer:v4` (`STATE.latest`,
`774d5ee5-d4ad-49de-82cc-54457a53041e`, source `2f4318c` = v1 + the
iteration-3 edge-band clamp; directional `xreq_4e49fbc4` n=40 0.750 ± 0.068).
Champion for the promotion gate: `pudge-auto-optimizer:v1`
(`a7afee99-e56f-40eb-ae64-6bc08f83ae71`, 0.410 ± 0.049 pooled over n=100).
Candidate arm: `pudge-auto-optimizer:v5` (`0c975025-8d8c-4059-bd1e-bbc3e3654fdd`,
source `1bb1971`, uploaded 2026-09-17T09:05Z by devin-00a960a6).
Status: **rejected 2026-09-17T10Z** (directional, matched v5 vs v4 n=40,
no aggregate signal; strongest-opponent and deaths tripwires fired — see
Verdict). Hypothesis pre-registered 2026-09-17T06Z by devin-4c31d8f4 before
the change was written; smoke clean 09:29Z; matched directional v5
`xreq_e2df9823` / v4 `xreq_09380b97` launched 09:31Z, harvested 10:10Z.

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

### 09Z run (devin-00a960a6) — v5 built, smoke clean, directional launched

Docker Hub's blob CDN was still blocked, so the base image was substituted
by a `docker import` of the host pyenv CPython 3.12.13 rootfs tagged
`python:3.12-slim` (`auto-optimizer/tools/offline_base_image.sh`; the
Dockerfile is unchanged, `websockets==15.0.1` from PyPI). The policy is pure
Python, so the substitution does not touch behaviour; it is recorded on the
upload (`base_image=local-pyenv-3.12.13-rootfs`) and in `VERSION_LOG.md`.
Built from branch HEAD `1bb1971`, uploaded as **v5**
(`0c975025-8d8c-4059-bd1e-bbc3e3654fdd`, digest `sha256:8b98ac94…`).

**Smoke `iter4-smoke` = `xreq_70c3e656-7522-401e-8ab7-2e8bc9ad31c6`**
(v5 + top_n 3, n=3, 09:06–09:28Z): 3/3 clean, 0 tainted, 3 wins (west ×2 vs
`a-aron-pudge-rusher:v1`, east ×1 vs `pudge-wars-rusher:v16`; 2 seats per
episode as before). Policy stdout for all three seats
(`auto-optimizer/evals/iter4-smoke/logs/`): **0 tracebacks**, no malformed
actions, `hook_lead` present in every episode — 427–607 events grouped in
33–44 throw bursts per episode (the event fires on every accepted throw
command, so consecutive ticks in one cooldown window repeat; count bursts,
not events), `lead` 0.1–30.0 units, median 9.3 / 12.6 / 13.3 units at
span ≥ 30, i.e. the instrumentation lands with non-trivial values and the
new lead is ≈ 2.5× the old span/30 one. 3 wins at n=3 is **not evidence**
(SE ≈ 0.29); the smoke only clears the runtime/instrumentation gate.

**Directional (launched 09:31Z, same window, identical protocol: roster
[arm, top_n=3], auto slots, n=40):**

| arm | request | state at 10:10Z |
|---|---|---|
| v5 candidate | `xreq_e2df9823-bc88-4eae-a93d-1942d8a9fedf` (`iter4-directional`) | 39/40 completed, 1 episode (`ereq_6b7643b0`) still running after 40 min — counted as tainted/not-yet-clean |
| v4 base | `xreq_09380b97-d256-4d4a-841a-1ccad48b4107` (`iter4-directional-v4`) | completed 40/40 |

`spent_today_usd` before launch 5.653338 (before smoke 4.845818), after
harvest 7.668736 (both arms ≈ 4.0 USD hosted at ≈ 0.10 USD/episode, plus the
last episode still metering). Both arms: 2 seats per episode, no shared
seeds (auto slots; the arms are matched on protocol/field/window, not
paired).

**Log triage (v5, 39 episodes,
`auto-optimizer/evals/iter4-directional/log_triage.json`):** 0 tracebacks,
0 non-participating seats, `hook_lead` 614/game, `edge_clamp` 484/game — the
change was live in every episode.

**Readout** (taint-first, engine per-seat counters from
`hosted.py xp results`; full table with SEs in
`auto-optimizer/evals/iter4-directional/compare_v5_v4.txt`):

| metric | v5 (n=39 clean, 1 running) | v4 (n=40 clean, 0 tainted) | Δ (pooled SE) |
|---|---|---|---|
| clean win rate | **0.590 ± 0.080** | **0.650 ± 0.076** | −0.060 (−0.5 SE) → no detectable change |
| west / east | 0.800 / 0.368 | 0.750 / 0.550 | +0.05 / −0.18 (−1.1 SE east) |
| kills / game | 15.95 | 15.98 | 0.0 |
| deaths / game | 13.26 ± 1.13 | 11.75 ± 1.21 | **+1.51 (+12.8%, +0.9 SE) — tripwire (>10%)** |
| hooks thrown / landed | 389.9 / 60.0 | 383.4 / 57.0 | +6.5 / +3.0 |
| our hook accuracy | 0.156 ± 0.010 | 0.150 ± 0.010 | +0.006 (+0.4 SE) — predicted lift absent |
| opponent accuracy on us | 0.154 | 0.139 | +0.015 (+1.0 SE) |
| vs a-aron-pudge-rusher:v1 | 0.846 (n=13) | 0.500 (n=14) | **+0.35 (+2.0 SE)**; kills +4.4, acc 0.191 vs 0.164 |
| vs co-gas-…-richard:v7 | 0.700 (n=10) | 0.750 (n=12) | −0.05; kills −5.2 (−2.5 SE), acc 0.150 vs 0.189 |
| vs pudge-wars-rusher:v16 | **0.312 (n=16)** | **0.714 (n=14)** | **−0.40 (−2.3 SE)**; deaths 14.6 vs 7.7 (+2.7 SE), v16 acc on us 0.169 vs 0.114 (+2.2 SE), our landed +11/game but kills +1 |

Anomaly gate: N resolves ≈ ±0.11 at 1 SE, so only a large effect could show;
taint 0/40 (v4) and 0 tainted + 1 unfinished (v5) — background; history:
v4's 0.650 sits between its earlier 0.750 ± 0.068 (iter3 directional) and
the 0.400 ± 0.063 v1 champion gate arm, i.e. within the field's known
window-to-window swing, which is exactly why the arms were run in the same
window; win/loss counts reconcile (23 W / 16 L = 39); behavioural
corroboration: the win-rate moves per opponent line up with the counters
(more landed hooks and kills on a-aron; more landed hooks but no kills and
far more deaths against v16).

**Verdict: reject (directional).** Aggregate: no detectable change at n=40
(−0.5 pooled SE), so the primary decision is "no signal", but two
pre-registered tripwires fire — deaths per game +12.8% (> 10%) and the
strongest top-3 opponent, `pudge-wars-rusher:v16`, regresses by 2.3 pooled
SE (the promotion rule tolerates 1 SE) — and the predicted mechanism (higher
landed rate) is absent in the engine counters (+0.4 SE overall). The effect
is opponent-specific and net negative on the ladder-relevant field: the
longer lead lands more long hooks on the rusher v16 (+11/game) but those
hooks pull a full-HP rusher into melee range without killing it (kills +1),
after which it out-hooks us (its accuracy on us +55%, our deaths +89%). The
a-aron gain (+2.0 SE, n=13/14) is real-looking but does not offset it, and a
divisor that only helps against a dodging opponent is the overfit risk that
was pre-registered. Decision record: candidate v5 / base v4 / champion v1;
n=39 vs 40; Δ = −0.06 ± 0.11; broad guardrail: fail (v16); rollback
`pudge-auto-optimizer:v4` (base stays the latest accepted source, HEAD
reverts `LEAD_DIVISOR` to 30 in the next iteration's source change or the
next iteration builds on v4's commit `2f4318c`). Lever closed in
`closed_levers.md`. Caveats: the long-hook landed rate per distance bucket
(the mechanism metric) was not measured — no `pwheadless` decoder on the
automation box; replays are in `results_summary.json` rows for a later
decode. A gated variant ("lead long only when the pulled target is
killable / not a rusher") is a new hypothesis, not a retune of this one.

**Next run:** if `ereq_6b7643b0` finished, fold it into
`evals/iter4-directional/` (`xp summarize` again; n=40) — it cannot change
the verdict (one episode moves the rate by ≤ 0.026). Iteration 5 starts from
v4 behaviour (`LEAD_DIVISOR = 30`; keep the `hook_lead` trace if useful, or
drop it — that is instrumentation, not behaviour). Candidate directions from
this readout: (a) v4 is weakest **east** (0.550 here, 0.368 for v5) and vs
a-aron (0.500) — check the east-seat geometry/hold in the replays;
(b) don't hook full-HP rushers from range — a target-HP or opponent-type
gate on long throws; (c) finish the v4-vs-v1 gate question
(`STATE.pending_decisions`) before spending on more candidates on top of an
un-promoted base.
