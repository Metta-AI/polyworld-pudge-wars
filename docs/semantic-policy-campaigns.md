# Improving the loop, especially its next iteration

2026-09-10. The loop now retains **hypotheses and evidence as well as a policy**. It can continue past rejected changes, distinguish a failed prediction from inconclusive game evidence, and test a promising candidate independently without changing it.

The implementation is in [campaign.py](../coaching/symbolic/campaign.py), with [run instructions](../coaching/symbolic/CAMPAIGNS.md). The original single-round experiment remains available.

## Changes that matter for future loops

| Earlier limitation | New behavior | Why it matters |
|---|---|---|
| Repeat the same lead search | Semantic fingerprints and imported experiment history | Renaming a policy or spelling out a default cannot disguise a duplicate experiment. |
| Only tune one number | Named hypotheses about aiming, lane separation, fog speculation, retreat and positioning | A proposal can change strategy structure and carries an explicit predicted effect. |
| Treat a valid round trip as semantic understanding | Independent intervention and protected-behavior checks before games | A program that round-trips perfectly still fails if it does not do what the proposal says. |
| Reuse fixed validation maps | Persistent ledger of imported, development, confirmation and reserved audit maps | Later rounds cannot accidentally call previously used maps fresh evidence. |
| Promote from a tiny consistency heuristic | Paired seed-level uncertainty, minimum effect, win-rate and opponent-regression checks | Banks and matchups do not inflate the independent sample count; overall gains cannot hide a failing opponent. |
| Spend on every candidate | Confirm only the development winner, then repeat whole trajectories only before a possible retention | Losing candidates do not consume confirmation or repetition budgets. |
| Restart work after interruption | Atomic checkpoints, input-validated match reuse, preserved partial attempts, process ownership and actual subprocess timeouts | Long experiments recover without silently mixing policies, opponents, engines or evaluator versions. |
| Lose a promising failed candidate | Carry its exact IR, parent, hypothesis and prediction into one independent replication | A larger follow-up is a new fixed experiment, not another search over the same observations. |
| Keep tuning against the final test | Separate audit that seals the campaign before it starts | Final evaluation cannot become another selection phase inside that campaign. |

The seven-layer framing remains useful, but the executable meaning and its provenance must stay separate. A code extractor can recover which skill runs and with which parameters. It cannot reconstruct a unique original rationale. The campaign therefore carries the authored rationale, predicted effect and evidence alongside extracted executable IR.

## What the improved workflow found

I ran two search rounds and a larger independent replication: **96 complete native 2v2 games**, using a frozen copy of the existing Base policy, both banks, a 30-kill goal and a 38,400-tick limit. One fog-withholding development game reached the time limit; the other 95 reached the goal. The old lead experiments were imported and skipped under the matching parent and game configuration.

| Experiment | Result | Decision |
|---|---|---|
| Widen lanes, 24 → 32 tiles | Development mean margin improved by 6 kills. On six confirmation seeds, won 10/12 versus the parent's 5/12; paired margin gain +4.92, exploratory 95% bootstrap interval **[−0.33, +11.00]**. | Inconclusive; retained parent. |
| Withhold fog shots | Development margin 5.75 kills worse than parent. | No confirmation budget. |
| Retreat at 50% instead of 40% health | Development margin 6.50 kills worse than parent on that round's maps. | No confirmation budget. |
| Move four tiles closer to the bank | Development margin 16.50 kills worse than parent on the same maps. | No confirmation budget. |
| Independently replicate the exact wider-lane policy | Twelve new seeds, 48 games: candidate won **16/24**, parent **15/24**. Paired margin gain **+0.21**, interval **[−4.75, +4.71]**. | Failed the minimum-effect and uncertainty gates; retained parent. |

The first wider-lane result looked encouraging, but its improvement did not survive the larger replication. That does not prove wider lanes never help. It argues against retaining this unconditional change on the available evidence. Confirmation results were not pooled with replication to search for a favorable significance threshold, and no final audit result was used.

Across the 96 games, **3,808,246 actual candidate decisions and memory states matched their regenerated shadows**, with zero mismatches. The warmed arm-level median throughput ratios ranged from approximately 0.58 to 0.67 of Base; no arm crossed the runtime-failure threshold. These timings include different policies' actual observations and are not an identical-input microbenchmark.

The completed replication resumed without rerunning or rewriting any of its 48 match results. **24 symbolic tests and 45 existing coaching tests passed**. Tests exercised native cache reuse, interrupted-attempt preservation, a silent subprocess timeout, false semantic predictions, sample-count/pairing errors, checkpoint-stable tie-breaking, replication and audit sealing. Short integration runs are excluded from game-performance evidence.

The final audit maps remain unused. Opponent-suite support exists, but this performance experiment used only one policy family. The gate is an exploratory research rule; a bootstrap interval over six or twelve seeds does not establish universal policy superiority or control error across unlimited adaptive research.

## The next useful outer loop

The current search uses explicit templates. It does not autonomously invent new ontology categories, and exhausting the templates should trigger a representation question rather than more arbitrary parameter changes.

For this policy, a concrete next hypothesis is [conditional hook-lane clearing](../coaching/policies/clear-hook-lane.proposal.md): expose projected friendly interference as a named situation, and reposition when that situation holds. The existing throw primitive already checks teammate obstruction, but the strategy cannot use the reason for a withheld shot. That is a representation gap worth testing. The wider-lane result does not establish that obstruction caused its successes or failures.

For each future ontology revision:

1. Preserve a concrete observation/history where the current concepts fail to support the intended behavior.
2. State the new distinction, its grounding, uncertainty and the skill it affords. Mark unbound parts explicitly.
3. Write contrasting scenario predictions and protected behavior before generating code.
4. Generate a realization, extract what the executable actually implements, and record any uncovered behavior.
5. Test the semantic predictions first, then fresh paired games and independent replication. Keep goal revisions explicit.

An independent coding agent given only the IR, contracts and scenario tests—without the original controller—is the next test of semantic regeneration beyond the shared compiler grammar. The campaign is the evidence and evaluation infrastructure for that experiment, not evidence that unrestricted synthesis already works.

## Evidence

The [compact results](semantic-policy-campaign-results.json) preserve all game outcomes, hashes, comparisons, runtime versions and limitations. Full search artifacts are in `tmp/coaching/semantic-campaign-20260910/`; replication artifacts are in `tmp/coaching/wider-lanes-replication-20260910-final/`. The latter's `rounds/000/next-iteration.policy.md` is the recovered retained parent.

The research driver was hardened between the search and replication campaigns, including a checkpoint-order tie fix. Earlier selections were recomputed and unchanged. Each campaign records its own implementation fingerprints. Current code intentionally refuses to resume a campaign created with changed research code; import its history into a new campaign instead. The final replication used the current implementation and passed the resume check.
