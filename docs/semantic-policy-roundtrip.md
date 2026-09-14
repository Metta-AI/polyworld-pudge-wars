# First semantic IR ↔ symbolic policy experiment

2026-09-09. **The bounded round trip works and the generated support policy plays competitively in local native games. The automatic aiming adjustment did not improve held-out performance; the loop retained its parent.**

| Text-generated policy | Held-out record against frozen Base | Mean kills | Mean opponent kills | Mean kill margin |
|---|---:|---:|---:|---:|
| Small Loom projection | 0 wins, 8 losses | 0.500 | 29.500 | −29.000 |
| Support parent, lead 1.0 | 5 wins, 3 losses | 27.625 | 26.250 | +1.375 |
| Development-selected candidate, lead 0.5 | 5 wins, 3 losses | 25.125 | 24.750 | +0.375 |

The support parent improves mean kill margin by 30.375 over the small Loom projection. This larger change adds assistant-authored skills and strategy grounded in inspected game code; it is not attributable to automated tuning or human coaching. Five wins in eight games is evidence of competitive play in this small test, not proof of superiority to Base.

The parameter search favored lead 0.5 on development maps: mean margins were +3.25 for lead 0.5, +1.25 for the parent at 1.0, and −2.00 for lead 1.5. On held-out maps, the selected candidate's margin was **1.0 kill worse than its parent**. Averaging both banks within each seed, candidate-minus-parent differences were −5.5, +1.5, −4.5 and +4.5. The improvement gate rejected the change and saved the recovered support parent as the next iteration's input.

## What ran

The [support text](../coaching/policies/executable/support.policy.md) and [Loom text](../coaching/policies/executable/loom.policy.md) were compiled into Python strategy programs. Their calls and conditional returns select inspectable skills; neither imports the original complete policy. The native runner uses the actual Pudge Wars map generation, simulation, per-seat fog observations and JSON action application.

There were **42 benchmark games**: 16 development games, 24 held-out games, and two full-game repetitions using regenerated code. Each was 2v2, on both banks, with a 30-kill goal and 38,400-tick limit. One Loom game reached the time limit at 2–26; all other benchmark games reached the kill goal. Terminal score lead determines the reported outcome; draws and time limits are recorded explicitly.

Development seeds were 6101 and 6102. Held-out seeds were 7101–7104. Banks are paired within a seed; there are only **four independent held-out map seeds**. No held-out result selected a lead parameter. The support-parent control was added during development, before selection. The retention gate was specified before inspecting selected-candidate held-out results and before running the parent control. Both amendments are preserved in the raw artifacts; this was an exploratory implementation experiment, not a preregistered study.

The opponent was a frozen copy of the current local `coworld/player/base.py`, using `BasePolicy()` with its defaults. This is a source-specific local comparator, not a claim about an immutable hosted champion release. The runner binary and shared skill library were also frozen and hashed.

## Both translation directions were exercised

1. **IR → code → game.** Both textual policies generated complete controllers that emitted native game actions. The support policy won five held-out games against Base.
2. **Code → IR → code.** The extractor read actual Python calls, literal parameters and branch/return structure. It did not consult the original text or an embedded IR. Unsupported executable statements were rejected by comparing the entire source AST against the supported grammar.
3. **Behavioral round trip.** Original and regenerated controllers received every seat's observed history, with independent memory. All **3,282,456 action comparisons and memory comparisons matched**, across the 42 benchmark games. These correlated decisions are an equivalence check, not independent samples of policy quality.
4. **Independent complete-game repetition.** Regenerated code actually controlled the candidate team in two repeated games. Scores, terminal ticks and complete action-stream hashes matched the original runs: 16–30 at tick 17,379 on the west bank, and 30–19 at tick 20,245 on the east bank, both seed 7101.
5. **A code-first intervention.** In a separate demonstration, the module documentation was removed and the executable lead parameter changed from 1.0 to 0.5 before extraction. The recovered text contained that change; its regenerated controller won 30–9 on seed 6100. This game is excluded from the 42-game benchmark and from candidate selection.

Ten new tests passed. They cover source edits changing recovered text and predicted aim, a coached health threshold changing the expected immediate decision region, rescue commitment and early termination, state isolation/reset, dead agents, unknown-code rejection, binding drift and retention of a parent after regression. All 45 existing coaching tests also passed using the existing coaching virtual environment. A separate 32-tick orchestration smoke test passed and is excluded from performance evidence.

The support controller's median decision throughput was 0.744 times Base's in these local games; the minimum ratio across benchmark games was 0.672. Both were timed on the same machine in decisions per second. This includes policy work, excludes simulator/IPC time, and uses each side's actual observations rather than an identical-input microbenchmark. It does not establish live-network latency behavior.

## What the result establishes about the IR

The executable artifact consists of **textual commitments plus versioned skill bindings**. The compiler makes strategy explicit rather than hiding a complete existing controller behind one skill. Extraction preserves the supported operational semantics, including parameter values and conditional termination. A changed binding hash invalidates a policy until it is explicitly regenerated and re-evaluated.

The [grounding contract](../coaching/policies/executable/grounding.md) is essential to the claim. The small Loom policy is a projection, not an exact copy of the existing live evaluator. The support policy was authored with help from existing code; it was not blindly synthesized from prose. Its belief state uses point estimates, its goal labels are declared interpretations, and its strategy is an ordered decision list. It does not implement every structure proposed in the seven-layer ontology.

This result does **not** establish extraction of arbitrary existing symbolic controllers, recovery of an author's unique rationale, faithful synthesis from unrestricted prose, autonomous ontology induction, or a benefit from human coaching. Round-trip identity with shared skills cannot by itself prove the natural-language descriptions of those skills are faithful. Concrete intervention tests provide a first check of that separate obligation.

The next discriminating experiment is to give an independent coding agent only the richer IR, observation/action contracts and scenario tests, withhold the existing controller, and measure semantic compliance plus held-out play. Reverse extraction should then start from an independently written controller and report unsupported behavior explicitly. That would test semantic regeneration beyond this exact compiler grammar.

## Reproduce and inspect

See the [run instructions](../coaching/symbolic/README.md). The default loop now includes the parent control and retention gate directly. It proposes lead values at half and 1.5 times the current parent's lead, capped by the skill contract, so a subsequent iteration can start from recovered text with fresh development and validation seeds.

The [compact machine-readable results](semantic-policy-roundtrip-results.json) preserve every benchmark score, action count, trajectory hash, comparison and limitation. Full local artifacts are under `tmp/coaching/symbolic-loop-20260909-01/`: frozen opponent/engine/skills, all four policies in both representations, sampled observations and decisions, game results, the original report and its parent-control supplement. The single code-first game is under its `code-first-demo/` directory. The retained text is `next-iteration.policy.md`.

Frozen hashes:

```text
Base source: 07db67fa0336450a9b8e6ffd4685d0ac119b0ac83bd0d4f5ff350e0ae2c022cb
Native runner: 21e8f62ea96d0957b07dba36e2bbf113aec48aea629ed9c20959368c158d8f23
Skill bindings: f7cea6a0203afec157813d7a385f95af862e8240113dfcf1445b851402dd96ae
```
