# Gameplay skill gradient: local experiment

Status: completed. This studies decision quality, not gradient-based training.

The current working tree is the baseline (not Git HEAD). Prior experiments and
closed levers were reviewed. All runs use a freshly compiled BASIC league host,
fog, full match limits, frozen policy bytes and both banks for every map seed.
No hosted or human-enjoyment claim follows from these local matches.

## Hypotheses and decision rules

1. **Threat selection correctness.** Base updates the minimum threat distance
   but unconditionally overwrites its coordinates. With two threats on opposite
   sides it can dodge toward the closer one or intercept the farther one.
   Moving the coordinate assignments inside the minimum comparison should make
   the selected threat invariant to iteration order for unequal distances.
   Accept the correctness fix iff controlled cases fail before and pass after,
   and the bot smoke suite passes. Competitive benefit is a separate question.
2. **Shorter prediction in this runtime.** `leadDiv = 30` rather than `9` may
   beat the current default. Historical results are motivation, not current
   evidence. Test this single change separately from threat selection.

Run each isolated candidate against the frozen baseline in 1v1 and 3v3 on
seeds 101401–101424, each on both banks (96 matches per candidate). Primary
local outcome: candidate win/draw/loss, with timeout leads scored by the league
host. Report mean kill margin and a 95% percentile bootstrap interval over
24 seed blocks, averaging the two banks within each seed. Also report each
bank and timeout frequency. Do not treat swapped-bank games as independent.
Retain a gameplay-strength candidate only if its margin interval is positive
in both formats and its wins exceed losses in both. This is a local decision
rule; external opponents and hosted confirmation remain necessary for promotion.

## Critique

Direct self-play controls opponent identity but can reward exploitation of one
policy. Different team sizes are guardrails, not an independent opponent panel.
24 seed blocks can detect large effects; small differences remain unresolved.
The baseline may already be inconsistent with historical reports. Preserve its
exact bytes rather than silently restoring previously promoted tuning.
Threat distance is still a proxy for actual collision risk. Fixing index-order
dependence does not solve trajectory-aware defense. Human readability and fun
require a separate playtest; neither is inferred from bot win rate.

## Artifacts

Baseline and candidate snapshots, episode manifests, private seat status,
results and replays: `tmp/skill-gradient/`. Build: `tmp/skill-gradient-build/`.
Durable aggregate results and the final verdict follow below.

## Results and verdict

All 192 scheduled matches completed with active policies and complete artifacts.
Scores below are candidate-first. Draws include timeout ties; timeout leads
use the league host's winner convention.

| Isolated change | Format | W–L–D | Mean kill margin | 95% seed-block interval | Timeouts |
| --- | --- | --- | --- | --- | --- |
| Nearest-threat coordinates | 1v1 | 16–16–16 | 0.000 | [0.000, 0.000] | 48/48 |
| Nearest-threat coordinates | 3v3 | 22–26–0 | -0.500 | [-1.688, 0.500] | 5/48 |
| Lead divisor 9 → 30 | 1v1 | 18–14–16 | +0.354 | [0.021, 0.688] | 48/48 |
| Lead divisor 9 → 30 | 3v3 | 27–20–1 | +3.271 | [0.958, 5.729] | 2/48 |

**Threat correctness confirmed; competitive effect inconclusive.** The fixture
failed before the fix: distance 80 belonged to (38,68), but selected coordinates
were (46,58), producing dodgeSide +1 instead of -1. After the two assignments
moved inside the minimum comparison, both iteration orders passed. The existing
bot suite also passed. The default receives only this correctness fix. The
negative team estimate is reported explicitly; a win-rate gain is not claimed.
The unchanged duel trajectory is expected because a single enemy cannot expose
the multiple-enemy-hook selection error.

**Shorter lead passes the registered local rule.** Both intervals are positive
and wins exceed losses in both formats. Retain the frozen research candidate
`tmp/skill-gradient/policies/short-lead.bas`; do not yet promote it to the default.
The duel effect is small and its interval barely excludes zero. These tests
compare each isolated candidate against the original baseline, not their
combination. Further validation must test the combined candidate, fresh seeds,
other opponents and the actual hosted runtime before broader claims.

**Pacing finding:** both duel arms timed out in all 48 games, with average
combined kills 5.125 (nearest) and 4.854 (shorter lead). Better aim here did not
demonstrate a faster or more enjoyable match. The goals are ten kills per team
and an eight-minute cap. Team matches mostly reached their 30-kill goal.

The four-match identical-policy instrument control on separate seeds
101501–101502 produced 2–2–0, with exactly zero paired margin and interval.
Both seed-block unit tests pass. The control is a sanity check, not additional
independent evidence for either policy hypothesis.

The initial duel replay check failed from tick one because it generated a
one-lane map from the two-seat roster. The hosted duel actually uses the
three-lane map. The checker now uses `generateMapMatching(seed, mapHash)` and
rejects unmatched geometry. All **192 replays, 4,026,844 ticks and 51,344,924
actions** verified with zero state-hash mismatches after this correction.

[Durable results, source/binary hashes and per-game counters](2026-10-13-skill-gradient-results.json).
[Gameplay recommendations and reproduction](../../../docs/gameplay-skill-gradient.md).
Raw policy snapshots, logs, binaries and replays remain under the local `tmp/`
paths above; preserve them separately when moving or deleting this checkout.
