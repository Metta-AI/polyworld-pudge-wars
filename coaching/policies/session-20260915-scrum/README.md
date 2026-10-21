# Coaching loop: melee hooks and the middle fountain

**Complete: retain v14.** Neither coaching candidate passed the preregistered
local improvement gate. Captured inputs remain unchanged.

| Candidate | Games | W–L | Mean kill margin | 95% interval, resampling seed blocks | Decision |
| --- | ---: | ---: | ---: | --- | --- |
| E04: wounded ally/enemy midpoint | 24 | 12–12 | 0.00 | [-4.63, 4.96] | Reject retention |
| E05: non-support fountain guard | 24 | 11–13 | -1.54 | [-6.33, 3.71] | Reject retention |

These are full native 3v3 mirror games against frozen v14, with both bank
assignments per map, a 30-kill objective and 38,400-tick limit. They measure this
local matchup. They do not establish hosted competitiveness or rule out small
effects. Neither candidate triggered confirmation; no league policy was changed.

## Saved pair and evidence

- [Retained semantic IR](retained.ir.md) and [symbolic policy](retained.policy.py).
  The policy remains byte-identical to frozen v14. The IR adds the reviewed
  dual-utility goal explanation and explicitly inactive CurveHook proposal.
- [Results](results.json), [preregistered protocol](protocol.json), and
  [append-only ledger](ledger.jsonl).
- [Coaching evidence review](evidence-review.md) separates intent, observed
  frames/input, engine facts and assistant-authored operational hypotheses.
- [Session reference and captured-input hashes](session-reference.json).
- [E04 rejected pair and measured lift](candidates/E04/) and
  [E05 rejected pair and measured lift](candidates/E05/).
- [Engine and native-test provenance](engine-reference.json) and
  [conversion checks](conversion-checks.json).

The captured IR and policy are **empty**. The session identified Blank policy
and explicitly did not verify execution. Current repository Base matches frozen
v14, which supplies the baseline. The recording cannot establish which policy
was running. Prior E03 work is separate and was not selected by this loop.

## Reconciliation

Across **3,864 authored boundary cases** and **2,268,558 candidate-seat decisions**,
the scoped semantic reference and regenerated code had zero mismatches. E04
also preserved every non-hook action and all existing memory on matched
observations. E05 differences reconcile to the new feasibility guard, including
fall-through into existing rules. The generated and regenerated policies are
byte-identical, including the retained parent.

The fountain model was corrected to center `(64.5,64.5)`, radius `3.5` in
observation coordinates. The earlier approximate-center candidates and their
run are archived and excluded. An independent quadratic reference required a
small rounding correction at exact tangency; both reference versions remain
archived. The stricter original reference passed every scored engagement game.
These are bounded lowering and extraction checks, not independent language
interpretations or proof of complete inherited-policy semantics.

The native simulation suite passed, including fountain-bounce checks. The
research record validator accepts these two records; repository-wide validation
also reports four older records without its required frontmatter. Those existing
records were preserved.

## Conversion and reproduction

This extends the repository's `coaching.session_compile` frozen-v14 workflow.
It does not route v14 prose through the unrelated `coaching.symbolic.ir` dialect.
The bounded compiler rejects unregistered prose edits. Extraction recognizes
the entire executable AST against registered lowerings and rejects unknown
code; it does not trust a metadata label. Human goals remain provenance.

From the repository root, use **new output paths**:

```sh
python3 -m coaching.scrum_ir generate \
  coaching/policies/session-20260915-scrum/retained.ir.md /tmp/retained-v14.py
python3 -m coaching.scrum_ir extract /tmp/retained-v14.py /tmp/retained-v14.ir.md
python3 -m coaching.scrum_ir generate /tmp/retained-v14.ir.md /tmp/retained-v14-roundtrip.py
```

Raw per-game results, both source versions, engine logs, manifests, native-test
output and decision tables are in `duels/coaching-20260915-scrum/`. Exact compiled
inputs sit beside each generated policy. The session export includes this
folder as an evidence archive plus the conversion code.

Fresh scored seeds were E04 **917501–917512** and E05 **917301–917312**.
The superseded E04 seeds **917101–917112** are used diagnostic evidence and must
not become a fresh holdout. Reserved confirmation ranges **917201–917224** and
**917401–917424** remain unused by this loop.

## Next-loop finding

Both mechanisms were exposed: E04 changed 7,307 hook requests; E05 blocked
44,199 attempts and changed 40,455 decisions. These counts are not unique
accepted casts or attributed healing. More useful target value and measured
contacts are needed before repeating these strategies. The prior E02 return
steering screen also failed; unconditional perpendicular movement is not
supported by the coaching evidence. Preserve all three negative/limited results.
