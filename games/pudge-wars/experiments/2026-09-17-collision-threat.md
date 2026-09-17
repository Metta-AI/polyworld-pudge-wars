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

**v3 smoke** (`xreq_4f8155c2`, n=3): clean 3/3, 0 tracebacks, `threat_class`
src=track 757 / none 19, no owner fallback; 1/3 wins (smoke only).

**Directional** (`xreq_e43bf971`, v3, top-3 field, 1v1 seating, n=40, same
protocol and day as baseline v1 `xreq_3e9e30f4`): clean 40/40, 0 tainted,
0 tracebacks in all 40 policy logs, every episode connected.

| | v3 (`xreq_e43bf971`) | v1 (`xreq_3e9e30f4`) |
| --- | --- | --- |
| win rate | 0.325 ± 0.074 | 0.425 ± 0.078 |
| west / east | 0.400 / 0.250 | 0.500 / 0.350 |
| vs a-aron-pudge-rusher:v1 | 0.231 (n=13) | 0.615 (n=13) |
| vs co-gas-pudge-blind-hook-richard:v7 | 0.375 (n=16) | 0.412 (n=17) |
| vs pudge-wars-rusher:v16 | 0.364 (n=11) | 0.200 (n=10) |
| kills / deaths per game | 17.35 / 19.70 | 17.75 / 18.33 |
| our hook acc / opp hook acc | 0.178 / 0.200 | 0.181 / 0.187 |
| time-limit fraction | 0.875 | 0.800 |

Trace: `threat_class` per game = hit 125.8, wide 100.9, away 72.7, pending
10.2, blind 3.1 (`evals/iter2-directional/log_triage.json`).

**Decision: reject.** Win rate delta −0.100 is −0.93 pooled SE — no
detectable win-rate change at n=40, and certainly no promotion. The
preregistered rollback condition fires on deaths: +1.37/game (threshold
+0.5) with ~101 `wide` classifications per game that v1 would have dodged.
The mechanism (ignore hooks that pass wide) removed dodges without buying
hooks (our accuracy 0.181→0.178, throws 384→379). The a-aron swing
(0.615→0.231, n=13 each) is the largest per-opponent regression and is the
matchup where "wide" hooks most often curve into hits. Champion stays
`pudge-auto-optimizer:v1`; rollback ref `v1`. Recorded in
`closed_levers.md`. Hosted cost: smoke 0.362 + directional 7.880 USD.

Code: the classifier was removed from the branch source with the rollback
(HEAD = v1 source + the iteration-3 hold clamp); it survives in the `v3`
image and in git history (`2f4318c` kept it as an opt-in `PUDGE_THREAT_FILTER`
arm). Caveat: 1v1 seating under the `League 3v3` label — transfer to 3v3
ladder rounds is unverified in either direction.
