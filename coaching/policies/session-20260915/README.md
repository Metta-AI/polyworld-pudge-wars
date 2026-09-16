# Coaching iteration — 15 September 2026

This research starts from the immutable league champion `pudge-wars-rusher:v14`,
not the blank policy shown in earlier coaching sessions. The current session
has no verified policy or actor reference; its speech is hypothesis provenance.

- `parent.ir.md`: inherited prose account with stable identifiers. Its broader
  semantic claims remain unverified; these experiments lift only their edited
  decision regions.
- `followup.ir.md`: E01, prioritize a teammate's existing catch; reverted.
- `return-sweep.ir.md`: coupled E02a–c, steer an empty return while idle; reverted.
- `alternate-target.ir.md`: E03, try another enemy after the nearest shot fails;
  local 200-game confirmation passed; hosted validation pending. Not approved for league promotion.
- `candidates/`: generated policies, archived exact compile inputs, scoped lifts,
  and measured selection results. Each input archive includes the compiler and
  frozen oracle. Candidate outputs are immutable.
- `ledger.jsonl`: append-only predictions, invalid attempts, outcomes and decisions.
- `oracle.py`: frozen original, SHA-256
  `b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6`.

## Reproduce

From the repository root, compile to a new path (existing candidates are never overwritten):

```sh
python3 -m coaching.session_compile \
  coaching/policies/session-20260915/alternate-target.ir.md \
  /tmp/pudge-coaching-candidate.py
```

The bounded compiler recognizes registered semantic revisions; arbitrary edits
fail rather than silently retaining old behavior. It is a small tested compiler
for these hypotheses, not a general natural-language compiler. Its repeated
identical outputs do not measure interpretive ambiguity.

Local full-game artifacts live in `duels/coaching-20260915-{followup,return,alternate}`.
Each game records the seed, bank, score, diagnostics and runtime decision checks.
Game simulator 37 runs to 30 kills or 38,400 ticks. The exact binary is frozen by hash.
It uses synchronous simulated replies and does not reproduce hosted scheduling.

Independent hosted fixed-roster A/B evidence is required before promotion.
The live request schema has been dry-run validated. No request or upload is implied
by a compiled policy or a successful schema check.

## Next-loop lessons

1. Count eligible decisions before attributing failure to strategy: return steering
   affected only 24 decisions across its complete 24-game screen.
2. A positive point estimate is a hypothesis. Preserve failed screens and use fresh
   fixed-size confirmation rather than adding seeds until an interval turns positive.
3. Derive missing ontology terms from observed decision residuals. Here the source
   revealed a nearest-target bottleneck; available targets and clear firing lanes
   already existed, so the edit belongs to strategy, not the goal layer.
4. Preserve invalid harness attempts separately. Numeric checks require explicit
   tolerance plus tests that still reject material behavioral differences.
5. Keep source, compiled output and lifted prose distinct. Scope every agreement
   rate; a finite partition is not an exhaustive proof over continuous game state.
