# Pudge Wars auto-optimizer ledger

Rendered from `ledger.jsonl` by `tools/ledger.py render`; do not edit by hand.
LLM cost is the Devin session's ACU consumption (`acus_consumed` from the Devin
session API); `final=no` means the session was still running when recorded and
the next session must backfill it with `ledger.py cost --final`. USD is only
filled when `cost.usd_per_acu` is set in STATE.json. Hosted compute is the
Coworld daily-budget delta observed across the iteration's evals.

| Iter | Started (UTC) | Devin session | Mode | Change | Policy | Eval | Verdict | LLM cost (ACU) | Final | LLM USD | Hosted USD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 2026-09-17T02:04 | [devin-53](https://app.devin.ai/sessions/53dc4bedf928403fa5309ba0df2a6aa4) | ultra | Baseline: repo default Python policy (coworld/player @ d1f6d7c, rusher/combined), no behavior change | `pudge-auto-optimizer:v1` |  | pending | unrecorded | no |  |  |

Totals: 0.00 ACU across 1 iteration(s); hosted compute $0.00.
