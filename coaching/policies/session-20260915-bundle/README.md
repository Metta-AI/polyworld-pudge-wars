# E06 — all coaching suggestions together

**Complete: combined policy retained after fresh confirmation.**

This experiment tests **one combined policy against v14**. The user explicitly
asked to apply all three suggestions at once, superseding the previous
one-edit-at-a-time screening plan. Previous E04/E05 outcomes are historical
context, not an acceptance gate for this package.

## The complete policy

1. **Melee-centroid hooks.** After emergency rescue/defense, a free caster prefers
   an ally/enemy melee midpoint before ordinary combat shots. Injured allies get
   priority; full-health allies can also qualify. The selected ally is exempt
   from friendly-corridor rejection, while other allies still block.
2. **CurveHook.** On an eligible cast request, walk perpendicular to its original
   trajectory immediately, continuing through outbound flight and return.
   Remember that direction, reverse at legal movement bounds, and release it
   when the hook finishes. Recovery, nearby incoming hooks, melee attacks,
   off-bank states, capture, death and ally rescue interrupt curve movement.
3. **MiddleObstacleInHookPath.** Every throw, including support and centroid
   attempts, checks the fountain's actual `(64.5,64.5)` center and `3.5` radius.
   Reject a straight segment that intersects it, then try later existing rules.

The semantic goal **HealAlly OR DamageEnemy** explains the centroid preference.
The match objective stays unchanged. Curve movement and target selection
interact on the same decision. This is a broader implementation than E04/E05,
not merely their two old files concatenated. Immediate lateral movement remains
an explicit experimental interpretation of the coaching, which spoke more
narrowly about repositioning during return.

## Evaluation design

The entire package is compared with the frozen v14 oracle, with no individual
component competitive screens or ablations. Native 3v3 mirror matches end at
30 kills or 38,400 ticks. Every map runs with the candidate on both banks.

- Screen: **48 games**, seeds **918301–918324**.
- Confirmation, only if the screen passes: **96 games**, seeds **918401–918448**.
- Both gates require mean paired-bank kill margin at least **+1**, a positive
  lower bound on the **95% seed-block bootstrap interval**, and zero semantic
  or regenerated-policy mismatches. All three mechanisms must be exposed.
- Complete fixed batches; do not extend them after inspecting a result.

See [protocol.json](protocol.json), written before candidate compilation, and
[ledger.jsonl](ledger.jsonl). This tests the package's local mirror performance;
it cannot attribute outcomes to one ingredient or establish hosted ranking.

## Conversion and validation

The bounded compiler extends the repository's frozen-oracle conversion pattern.
It accepts only registered semantic documents. Extraction recognizes the whole
executable AST; unsupported code edits fail instead of becoming an inaccurate
semantic description. Generated and regenerated code must be byte-identical.
Goal rationale stays human provenance, not an inference from actions.

```sh
python3 -m coaching.bundle_ir generate \
  coaching/policies/session-20260915-bundle/bundle.ir.md /tmp/all-coaching.py
python3 -m coaching.bundle_ir extract /tmp/all-coaching.py /tmp/all-coaching.ir.md
python3 -m coaching.bundle_ir generate /tmp/all-coaching.ir.md /tmp/all-coaching-roundtrip.py
```

Use new output paths. [bundle.ir.md](bundle.ir.md) defines the exact priorities,
movement limits, pending-cast timeout and termination conditions.
[bundle_skills_v2.py](bundle_skills_v2.py) implements the versioned skills.

An independent reference checks all actions and memory on each candidate-seat
observation. Authored probes cover 1,004 states/sequence steps, including cast,
flight, return, ally capture, death, recovery, boundary reversal and tick reset.
Separate deterministic geometry probes compare 10,000 segments and 4,000 legal
movement rays. These checks establish scoped behavioral fidelity, not complete
semantic recovery of all inherited v14 prose or a competitive advantage.

The initial screen attempt exposed a verifier-only quadratic endpoint error:
a rune at `(64.5,61)` is exactly on the fountain boundary. The policy rejected
the shot correctly. The independent reference now includes endpoints directly;
the unchanged candidate restarts on the same originally registered schedule.
Interrupted results and old verifier sources remain archived and are excluded.

## Provenance

The original captured IR and policy were empty, and execution was unverified.
The chosen baseline is the repository v14 policy, SHA-256
`b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6`.
[session-reference.json](session-reference.json) preserves the session link and
all captured-source hashes. [evidence-review.md](evidence-review.md) is the prior
review, whose inactive-CurveHook decision is superseded for this requested E06
experiment. The original inputs and completed E04/E05 outputs remain intact.

Raw match results, exact input archives, engine binary, decision probes and the
invalid attempt are saved under `duels/coaching-20260915-bundle/`.

## Initial package and lifecycle correction

E06a completed all 48 games: **38 wins / 10 losses**, mean kill margin
**+6.458**, 95% seed-block interval **[+3.542, +9.208]**. However, all 44,678
curve decisions occurred before a hook was observed: zero flight or return
steps. It failed the predeclared all-mechanisms gate. This favorable score is
preserved in `attempts/E06a/` and cannot be presented as the full coaching result.

Diagnosis found `HookWindupTicks=9`: a cast at tick 9 produces its hook at tick
18. The two-tick pending-state timeout was too short. E06b changes that timeout
to 12 ticks, and updates the semantic lifecycle to match. The caster remains
rooted by the engine during windup even though the policy issues walk requests.
A native 2,500-tick mechanism smoke observed 4,067 flight steps and 483 return
steps. A nine-tick windup sequence was added to the behavioral checks.

The **whole corrected package** is tested on fresh screen maps 918301–918324.
The acceptance thresholds and sample sizes are unchanged. E06a's score does not
enter E06b's selection or confidence interval. Its earlier screen maps 918101–918124
are used evidence; its untriggered confirmation maps 918201–918248 remain unused.

## Result

The corrected **E06b screen passed**: **38/48 wins**, mean kill margin
**+7.50**, 95% seed-block interval **[+4.979, +10.125]**. Both banks had positive
mean margins (+8.375 and +6.625). All three mechanisms were exposed, including
416,548 curve commands during flight and 128,724 during return, with zero
semantic/round-trip mismatches across 2,286,399 candidate decisions.

**Fresh confirmation passed: 67 wins / 29 losses in 96 games.** Mean paired-bank
kill margin **+7.146**, 95% seed-block interval **[+4.948,+9.198]**. Both banks
improved: west mean+8.917, east+5.375. All three mechanisms were exposed,
including 811,297 flight-phase and 251,336 return-phase curve commands.

**Retain E06b as the improved local research policy.** [Semantic IR](retained.ir.md),
[symbolic policy](retained.policy.py), [lifted IR](retained.lifted.ir.md), and
[full results](results.json) are saved together. Compile–extract–recompile
preserves the exact evaluated policy bytes. The 144 selected-candidate games
reconciled 6,781,230 decisions with no unresolved mismatch under the declared
numeric convention. This is evidence for the complete package in native 3v3
mirror play, not component attribution or a hosted leaderboard claim.

During confirmation, a nominal tangent computed as 3.5000000000000036 tiles in
the existing closest-point primitive. The policy was frozen; its raw binary64
comparison was lifted into the IR. Away from a 1e-9 boundary band the reference
uses independent geometry; within it, the declared numerical binding governs.
[Boundary fixtures](numeric-boundary-fixtures.json) preserve both cases.
The failed reference attempt is archived. We retained 91 complete passing games
and re-ran the 5 originally scheduled missing games, keeping the total at 96.
No outcome threshold changed and no new policy was selected from confirmation.

## League publication

Published the retained E06b pair as `pudge-wars-rusher:v16`; verified active 3v3 champion on 2026-09-16 UTC (2026-09-15 Pacific). Ten short hosted runtime checks passed; hosted competitive improvement remains unmeasured. See [deployment record](league-update.md) and [immutable references](league-update.json).
