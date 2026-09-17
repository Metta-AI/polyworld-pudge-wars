# Iteration 1 — collision-aware hook threat selection

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Baseline arm: `pudge-auto-optimizer:v1` (`a7afee99-e56f-40eb-ae64-6bc08f83ae71`,
repo-default Python policy @ `d1f6d7c`). Candidate arm: `pudge-auto-optimizer:v2`.
Status: **closed — rejected** (2026-09-17T03:35Z). v3 did not beat v1 at n=40 on
the matched protocol and regressed against the field's #1 clone; champion stays v1.

## Hypothesis record

**Observation.** The default policy treats *every* enemy hook in flight within
22 tiles as a threat (`BasePolicy.choose_action`, the `threat = min(...)` line).
A threat (a) spends Blink immediately if it is ready, (b) overrides movement
with a sideways dodge, (c) counter-throws at the hook head when within 14
tiles, and (d) sets `free = False`, which suppresses rescue, healing and hold
behaviour for that tick. None of that checks whether the hook is actually
heading at us. In a 3v3, most enemy hooks are aimed at a teammate or are
already past us, so the distance-only rule produces false alarms.

**Causal guess.** False-alarm threats waste Blink (the only escape tool) on
hooks that would have missed, and the sideways dodge repeatedly breaks
fishing/spacing positioning and cancels heals/rescues. When a real catch comes
later, Blink is on cooldown. This is the mechanism behind the enemy-bank
death rate the 2026-09-09 investigation measured (Base finishes 64.2% of
lives on the enemy bank vs 47.7% for the rival; the roadmap's third
hypothesis, [`../../../docs/pudge-improvement-roadmap.md`](../../../docs/pudge-improvement-roadmap.md)).

**Evidence.** Replay survey in the roadmap (20 hosted games, 522 Base deaths):
distance-only threat selection with immediate Blink spend, 64.2% enemy-bank
deaths. `closed_levers.md` records the *earlier* Blink experiment (rotating
the dodge direction perpendicular to the hook) as inconsistent — that lever
is not reopened here; the direction logic is untouched.

**Missing data.** The baseline emits no trace of which hooks were classified
as threats or whether Blink was spent on a hook that then missed. Added with
this change (events in the existing `policy_trace` log stream, joinable on
`tick`):

- `threat_class` — once per enemy hook flight when its classification
  changes: `owner`, `cls` (`hit`/`wide`/`away`/`blind`), `along`, `perp`,
  `src` (`track`/`owner`/`none`), `dist`.
- `dodge_blink` — when a defensive Blink is emitted because of a threat:
  `owner`, `cls`, `perp`, `along`.

Baseline arm cannot emit these; the candidate's smoke must show them with
non-trivial values before the directional eval is launched.

**Change (exactly one).** Replace the distance-only threat filter with a
collision test. For each enemy flying hook within 22 tiles, estimate its
heading (previous-tick displacement tracked per owner, falling back to the
owner→head vector when the owner is visible). Drop hooks that are moving
away (`along < 0`) or whose straight line passes more than 8 tiles from us
(`perp > 8`; pudge collision radius 2.6 + max hook radius ≈ 4.6 + slack).
If no heading can be estimated the hook is treated as a threat, exactly as
before. Everything downstream of `threat` (Blink hop, dodge direction,
counter-throw, `free`) is unchanged.

**Expected metric movement.** Directional (n≈40 per arm, top-3 field,
same window): candidate clean win rate ≥ baseline + 8 pp. Mechanism check:
≥30% of enemy hook flights within 22 tiles classified `wide`/`away`;
`dodge_blink` count per episode lower than the baseline's Blink-on-threat
count inferred from the replay. Tripwire: deaths per episode must not rise
(a hook we misclassified as `wide` and got caught by).

**Eval plan.** Smoke n=3 (traceback check, events present) → directional
n=40 on the primary protocol in `STATE.json` (XP request, roster =
[candidate, top_n=3], auto slots), baseline re-run at the same n in the same
window → gate n≈100 only if directional clears 2 pooled SE.

**Overfit risk.** The 8-tile margin is a guess; hooks with the big-hook rune
(+50% radius) plus 4 radius upgrades reach ≈4.6 tiles radius, and lateral
movement during the flight can close a 6–7 tile gap. A too-tight margin
trades false alarms for real catches. Per-opponent split must show no arm
losing more than 1 SE to any top-3 opponent.

**Rollback condition.** Candidate clean win rate ≤ baseline − 1 pooled SE,
or deaths/episode up by > 0.5 with `wide`-classified catches visible in
the trace, or any traceback in candidate stdout/stderr. Rollback ref:
`pudge-auto-optimizer:v1`.

## Results

**v2 smoke** (`xreq_8ca151a8`, top-3 field, n=3, 1v1 seating): clean 3/3,
0 tracebacks, won 2/3 (0.667±0.27 — smoke, not evidence). Instrumentation
landed: 723 `threat_class` events over 3 episodes, 66% `wide`/`away` (target
was ≥30%), `dodge_blink` 44–69 per episode (all `hit`/`blind`). Heading
source: `track` 97%, `owner` 1.2%, `none` 1.8%.

**Revision → v3** (iteration 2, same hypothesis, one change): the
owner→head heading fallback is unsound — the game keeps a hook's heading
when its owner Blinks (`human_play.md`: "The head keeps its world position
and heading"), so a real incoming hook could be classed `wide`/`away` from
the owner's new position. v3 uses tracked head displacement only; an
untracked hook is `blind` (dodged) within 10 tiles and otherwise `pending`
for one tick (hook speed ≈0.6 tile/tick, so waiting one tick at >10 tiles
costs nothing). Unit tests cover the post-blink owner geometry. v2 gets no
directional eval; v3 inherits the eval plan against baseline `xreq_3e9e30f4`.

**Directional** (`xreq_e43bf971` v3 vs `xreq_3e9e30f4` v1; top-3 field, 1v1
seating, n=40 each, both harvested 2026-09-17T03Z, 0 tainted, 0 tracebacks
in all 80 policy logs, all 80 episodes with a numeric score):

| arm | clean n | win rate ± SE | west | east | vs a-aron-pudge-rusher:v1 | vs co-gas-…-richard:v7 | vs pudge-wars-rusher:v16 |
|---|---|---|---|---|---|---|---|
| v1 (champion) | 40 | **0.425 ± 0.078** | 10/20 | 7/20 | 8/13 (0.62) | 7/17 (0.41) | 2/10 (0.20) |
| v3 (candidate) | 40 | **0.325 ± 0.074** | 8/20 | 5/20 | 3/13 (0.23) | 6/16 (0.38) | 4/11 (0.36) |

Delta −10 pp, 0.93 pooled SE: **no detectable overall change at n=40**, and
the pre-registered +8 pp did not appear. The named-opponent split fails the
rule: vs `a-aron-pudge-rusher:v1` 0.23 vs 0.62 (−38 pp, ≈2.2 pooled SE) — a
regression beyond 1 SE on a top-3 opponent. The v16 gain (+16 pp on n≈10) is
inside its own noise.

Mechanism check (policy traces, `behavior.json` in each eval dir): v3
classified 264 hooks/episode (hit 79, wide 101, away 73, blind 2, pending 10;
96% from a tracked head), so the filter *did* engage and skipped ~65% of
in-range hooks. Yet v3 still fired 48 ± 8 defensive Blinks per episode, and
low-HP recoveries went **up** 17.9 → 19.7 per game (+1.8, ≈1.6 SE) — damage
taken did not fall. The likely reading: with an 8-tile margin the "wide"
class includes hooks that still land (the collision radius is not measured;
enemies lead our movement), so the filter removed dodges that were saving us
while keeping Blink busy on the rest.

**Verdict: reject.** Rollback condition met (candidate ≤ baseline − 1 pooled
SE on a top-3 opponent; no mechanism-side improvement). Champion stays
`pudge-auto-optimizer:v1`. The classifier code is retained in source behind
`PUDGE_THREAT_FILTER=collision` (default `distance` = v1 behavior) because its
`threat_class` trace is useful diagnostic data for both arms; it is not part
of any candidate's behavior. Lever entry in `../closed_levers.md`. Caveat:
1v1 seating under the `League 3v3` label — transfer to 3v3 ladder rounds is
unverified in either direction.
