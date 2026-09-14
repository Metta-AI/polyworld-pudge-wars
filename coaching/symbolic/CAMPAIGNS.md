# Continuing semantic-policy research

Use `campaign.py` for new work. `loop.py` remains the reproducible first, single-iteration experiment.

The durable unit is an experiment: **parent IR, one proposed semantic change, predicted behavior, protected behavior, frozen opponents, assigned maps, measured outcome, and the next retained IR**. A higher score alone does not show that the semantic change meant what its author intended.

## Start, continue, or replicate

From the repository root, after building the native runner using the [setup instructions](README.md):

```sh
# Import the original experiment's consumed maps and lead-change evidence.
python3 -m coaching.symbolic.campaign \
  --out tmp/coaching/my-campaign \
  --import-run tmp/coaching/symbolic-loop-20260909-01 \
  --rounds 2

# Continue to four TOTAL rounds; completed matches are reused.
python3 -m coaching.symbolic.campaign --out tmp/coaching/my-campaign --rounds 4

# Fix an archived candidate and run one independent replication with more maps.
# Replace the imported campaign and candidate name with an actual recorded hypothesis.
python3 -m coaching.symbolic.campaign \
  --out tmp/coaching/my-replication \
  --import-run tmp/coaching/my-campaign \
  --replicate wider_lanes --confirmation-seeds 12

# Freeze the chosen policy and evaluate it against the initial campaign policy.
python3 -m coaching.symbolic.campaign --out tmp/coaching/my-replication --audit
```

`--rounds` is the desired total, not “this many additional rounds.” Repeating a completed command is a no-op. An interrupted round resumes its saved candidates and seed allocation. Completed games are reused only when source, bindings, engine, evaluator, Python/platform, opponent settings and game settings match. Partial attempts and failures are preserved. Input changes require a new campaign, with `--import-run` carrying forward evidence and consumed seeds. The new campaign inherits the prior incumbent unless `--initial` supplies an explicit new realization.

A replication must refer to a recorded candidate of the exact current parent with compatible bindings, engine, opponent suite and game settings. Its original text, hypothesis and predicted effect travel together. It does no development search, and a parent/candidate pair gets at most one such replication in its imported lineage. Select the replication sample count before running it; do not repeatedly rerun until the result turns positive. A new parent or opponent suite is a different hypothesis context and must be reported as such.

## What happens in a search round

1. Read the code-derived incumbent and prior experiment history. Compare semantic fingerprints, not names or formatting. Explicit defaults and equivalent conditional spellings identify the same policy.
2. Propose untried changes. Current templates test motion lead, lane separation, withholding fog shots, retreat timing and distance from the bank. Withholding fog shots changes strategy structure. These are author-specified hypotheses, not concepts discovered by a model.
3. Check the predicted behavior separately from compiler identity. For example, wider lanes must actually separate idle teammates; a lead change must alter moving-target aim while preserving stationary aim. Dead-agent behavior, emergency retreat, control restrictions, teammate clearance and declared unaffected action channels remain protected.
4. Evaluate the parent and candidates on the same fresh development seeds, both banks and all configured opponents. The parent wins ties. Save selection before confirmation. Losing development candidates receive no confirmation budget.
5. Compare only the selected candidate and parent on fresh confirmation maps. Average banks and opponents within each seed, then bootstrap seed clusters. A small bank or opponent advantage cannot inflate the independent sample count.
6. Require at least six confirmation seeds, at least one kill of mean margin improvement, a positive lower endpoint of the exploratory 95% bootstrap interval, no win-rate regression, and no opponent regression worse than two kills. If accepted, rerun complete games with regenerated code before retention. Every actual candidate decision and memory state is checked against a regenerated shadow throughout all matches.
7. Save the recovered retained IR, the full hypothesis and the outcome. Distinguish development rejection, failed semantic contracts, inconclusive evidence and accepted changes. A rejection applies to the particular parent/change/protocol; it is not a universal rejection of the underlying idea.

With the default two candidates, two development seeds, six confirmation seeds and one opponent, the maximum search-round budget is 38 games: 12 development, 24 confirmation and two independent repetitions. A round with no development gain costs 12. A one-candidate replication on 12 seeds costs 48 games, plus two repetitions if it passes. Multiple opponents multiply those budgets. A minimum of six confirmation seeds is required for retention even if a smaller number is requested for a smoke test.

Warmed decision throughput is recorded relative to the reference. If an arm's median ratio is below 0.5 after enough timed decisions, the campaign retains its parent and flags a runtime investigation. It does not interpret a runtime failure as evidence about the policy idea. The native subprocess also has a real wall timeout, including when it stops producing observations.

## Keep confirmation separate from final evaluation

Confirmation results influence retention, so they become research history. The ledger prevents their reuse as fresh maps in later rounds or imported campaigns. Audit maps are reserved separately at campaign creation and excluded from every search and confirmation allocation.

`--audit` fixes the incumbent, compares it with the campaign's initial policy against the frozen opponent suite, and seals the campaign before those games begin. It cannot activate a policy or select another candidate. After an audit, further tuning needs a new campaign that imports all consumed and reserved maps. This prevents accidental reuse; it cannot stop a human from learning from a report. The bootstrap retention gate is exploratory and does not control the error rate of unlimited adaptive research. Claims of general improvement should use a final audit and additional opponents/domains.

## Opponent suites

Provide `--opponents path/to/opponents.json` at initialization. Paths are interpreted from the working directory. Supported constructors are `BasePolicy` and generated `Policy`, each with its own instance per seat.

```json
{
  "base": {
    "path": "coworld/player/base.py",
    "class": "BasePolicy",
    "options": {}
  },
  "spread": {
    "path": "coworld/player/base.py",
    "class": "BasePolicy",
    "options": {"spread_fishing": true}
  }
}
```

The two entries above are configurations of one policy family, not independent algorithm families. Add actual archived controllers or independently authored policies to test a broader skill distribution. Changed opponents invalidate result reuse and change the context of old candidate evidence.

## Inspect and extend the loop

`campaign.json` is the durable ledger: fingerprints, complete candidate IR text, hypotheses, outcomes, parent lineage, reserved/consumed seeds and frozen inputs. Each round has a `plan.json`, immutable `selection.json`, both code/IR forms, per-game results and decision samples, `report.json`, `research-brief.md` and `next-iteration.policy.md`. Audit results live separately. The source and runtime checks deliberately stop silent changes to an ongoing experiment.

To add a hypothesis, extend `propose()` in `search.py` and give it an independent effect check in `check_proposal()`. A proposal names its layer, rationale, predicted behavioral effect and allowed action channels. Start a new campaign with the previous history after changing that implementation. When all supported proposals have been tried, the loop stops and asks for a newly grounded hypothesis instead of manufacturing novelty by renaming a policy.

The next outer loop is **ontology revision**. Repeated failures may mean a threshold is wrong, a skill is missing, or the concepts cannot express the relevant situation. Those are different revisions. For example, “our lanes interfere” may ultimately need a continuous predicted teammate-interception predicate instead of another lane-spacing constant. A coding agent should submit the proposed text, evidence/counterexamples, required new bindings and contrasting scenario predictions. Unbound concepts remain unexecutable until those bindings and tests exist. Goal changes should be identified explicitly rather than hidden inside a new skill or score objective.

The final discrimination remains independent realization: give a coding agent the IR and observation/action contracts while withholding the existing controller, then check semantic predictions and fresh-game performance. Exact AST extraction against shared primitives provides a useful reference but cannot establish unrestricted semantic synthesis by itself.
