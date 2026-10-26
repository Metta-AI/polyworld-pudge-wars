---
id: 2026-09-15-all-coaching
policy: pudge-wars-rusher:v14
baseline: b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6
candidate: E06b-all-coaching-windup
status: confirmed
hypothesis: All three coaching suggestions together improve native paired-bank score margin over v14.
decision_rule: Complete fixed 48-game screen and, if it passes, 96-game confirmation; require mean margin at least 1 and a positive seed-block 95% lower bound in both.
evals: [duels/coaching-20260915-bundle/screen, duels/coaching-20260915-bundle/v2/screen, duels/coaching-20260915-bundle/v2/confirmation]
---

# E06 — all coaching together

User explicitly requested a combined intervention instead of testing updates
one at a time. This overrides the experiment skill's usual component-isolation
rule. We test the entire package and make no component-level attribution.

`closed_levers.md` and E04/E05 results were checked. Complete preregistration,
critical design review, hypotheses and fresh seed allocations are saved in
`coaching/policies/session-20260915-bundle/protocol.json` before compilation.

## Initial attempt

E06a: 38/48 wins, mean paired-bank margin +6.458 [3.542,9.208].
Failed the mechanism gate: curve state expired before the nine-tick engine
windup, so there were no observed flight/return curve steps. Preserve this
favorable but incomplete interpretation; do not retain it as the full package.

E06b changes pending timeout 2 to 12 in both IR and policy, adds a realistic
windup contract test, and verifies flight/return steps in the native engine.
The complete bundle is re-evaluated on fresh seeds 918301–918324 with unchanged
thresholds and a new held-out confirmation allocation 918401–918448.

## Result

E06b screen: 38 wins / 10 losses, margin +7.50, seed-block 95% interval [4.979,10.125]. All three mechanisms exposed; zero mismatches across 2,286,399 runtime decisions. Advance the identical policy to the originally registered 96-game confirmation on seeds918401–918448.

Fresh confirmation:67/96 wins, mean paired-bank margin+7.146,95% bootstrap interval[4.948,9.198]. All three mechanisms exposed. Exact candidate code unchanged. A binary64 boundary convention was reconciled in IR/reference;91 completed passing games preserved and5 missing scheduled games rerun. Total remains96.

## Verdict

Confirmed for the registered local native3v3 mirror comparison: retain the combined research IR/policy pair. No hosted performance or individual-component attribution claimed. The package, not single updates, was evaluated. All original session sources remain unchanged. See coaching/policies/session-20260915-bundle/results.json.
