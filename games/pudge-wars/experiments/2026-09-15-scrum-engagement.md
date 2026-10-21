---
id: 2026-09-15-scrum-engagement
policy: pudge-wars-rusher:v14
baseline: b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6
candidate: E04
status: inconclusive
hypothesis: Aiming at a wounded ally/enemy melee midpoint when urgent actions have passed increases useful hook opportunities and mean kill margin by at least 2.
decision_rule: Complete fixed screen with margin >=2 and positive seed-block interval, then fresh confirmation; otherwise retain baseline.
evals: [duels/coaching-20260915-scrum/engagement]
---

# E04 — engagement

Full preregistration: `coaching/policies/session-20260915-scrum/protocol.json`.
`closed_levers.md` and previous session ledger checked.
The installed record helper requires a missing `_template.md`; this record uses its required schema directly.

## Predictions

If true: changed eligible decisions occur and the score gate passes. If false or harmful: no exposure or the fixed score gate fails. Coaching fidelity alone cannot demonstrate a win benefit.

## Design critique

- Head-to-head seed blocks test this mirror matchup only, not causal gain versus a third opponent.
- Two banks for a map are correlated: bootstrap seed blocks, not games.
- 24 games are directional with low power for small benefits: failure to pass means no retention, not proof of no effect.
- Centroid can miss or pull an ally out of a favorable fight; require wounded ally and protect prior urgent actions.
- Straight ray exclusion may remove useful rebounds; rejected hooks are mechanism exposure, not proof of waste.
- Native synchronous actions do not reproduce hosted timing.

## Result

24 completed games; W/L/D 12/12/0; mean bank-paired kill margin 0.0, 95% bootstrap interval [-4.625, 4.958]. 1,152,627 checked decisions and 7,307 changed hook requests; zero scoped reference or round-trip mismatches.

The initial center64 candidate is excluded; the corrected candidate uses fresh seeds 917501–917512. Only these final candidate games enter the verdict.

## Verdict

Inconclusive about small competitive effects; reject retention under the preregistered gate. No confirmation extension, upload or promotion. Preserve v14. The proposed centroid rule has behavioral fidelity but no measured local gain. Native results do not establish hosted performance.
