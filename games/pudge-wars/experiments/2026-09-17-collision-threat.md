# Iteration 1 — collision-aware hook threat selection

Campaign: `pudge-auto-optimizer` (records in [`../auto-optimizer/`](../auto-optimizer/)).
Baseline arm: `pudge-auto-optimizer:v1` (`a7afee99-e56f-40eb-ae64-6bc08f83ae71`,
repo-default Python policy @ `d1f6d7c`). Candidate arm: `pudge-auto-optimizer:v2`.
Status: **open** — hypothesis pre-registered before the change was written.

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

_pending_
