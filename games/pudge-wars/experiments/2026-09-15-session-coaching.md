# Session coaching → semantic IR → symbolic policy

Status: E01 and E02 reverted. E03 passed a separately preregistered, fresh
200-game local confirmation: 115–85, mean margin +1.465, 95% CI [0.225, 2.73].
Hosted validation is pending. The live champion remains `pudge-wars-rusher:v14`.

## What motivated the changes

Coaching session `2026-09-15t21-41-17-535zc09870` supplies human hypotheses.
The recording has no verified policy/build/actor reference, so it does not establish
that a specific v14 decision was wrong. We compare its coaching with the source
of the current league champion, then test explicit amendments independently.

The session analysis and indexed context are in
`/Users/aaln/Downloads/Co-play Coaching Review 2026-09-15/`.

| Edit | Coaching and semantic change | Layer | Local screen (24 games) | Decision |
| --- | --- | --- | --- | --- |
| E01 | Follow an allied caster's existing catch before ordinary close hooking | Strategy | 12–12; margin +0.33, 95% CI [−1.75, +2.42] | Revert; +2 gate failed |
| E02a–c | Use bounded lateral movement to steer an empty returning hook, only while idle | Situation, skill interface, strategy | 13–11; margin +0.67, CI [−0.29, +1.79] | Revert jointly; +2 gate failed |
| E03 | After a failed predicted shot at the nearest enemy, try other visible enemies before rune collection | Strategy | 13–11; margin +2.375, CI [−0.917, +5.667] | Original +3 gate failed; branch to a modest-effect hypothesis |

The confidence intervals above bootstrap whole seed blocks: each block contains
both banks. They are score margins against the frozen parent in clone-team
head-to-head games, not win-rate improvements against a third opponent.

## What the IR loop did

Each trial starts from the same immutable v14 parent. Plain-text IR records the
edit ID, exact conditions, skill ordering, goal reference, provenance and evidence.
The bounded compiler generates a candidate by reusing the frozen execution library.
It preserves prior outputs and archives the exact inputs, compiler and hashes.
Unsupported prose revisions fail instead of silently producing unchanged code.

Independent finite probes check isolation and coverage, then produce a scoped
empirical lift. Full matches also run a shadow parent on every candidate observation,
checking existing policy memory and unrelated action channels. Attribution is
single-edit parent reversion for E01/E03 and joint reversion for coupled E02a–c.
Independent effects of the E02 components are not claimed.

| Edit | Finite probes | Full-game decisions checked | Decisions changed |
| --- | ---: | ---: | ---: |
| E01 | 768 | 1,151,865 | 198 |
| E02 | 450 | 1,289,028 | 24 |
| E03 selection | 769 | 1,099,983 | 4,307 |

These checks detected no scoped leaks in the valid runs. The finite lift residual
is zero on the tested partitions. **The whole-policy semantic residual remains
unmeasured.** Repeated deterministic compilations agree but say nothing about
ambiguity across independent interpretive compilers.

E02's sparse activation is a finding about this predicate and policy pairing;
it does not refute the general usefulness of steering returning hooks. Return-phase
contacts were not separately instrumented, so that mechanism remains unmeasured.

## Reproducibility and invalid attempts

- Frozen oracle: `41212e9a-6383-40f8-b44e-f4ceb64ef9c9`; source SHA-256
  `b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6`.
- Target: canonical Fresh Meat 0.3.21, simulator 37, 3v3, 30 kills or 38,400 ticks.
  Local simulator source at build: `7d8ab8fce0c9a7d82993402051a0fecdcc0487f4`.
- Native runner SHA-256:
  `95f6d80fc37b86b91b27617086865e5f1bd0c4bd0e4ddeed6828f7792edd57c3`.
- E01 selection: seeds 915701–915712, both banks, `screen-retry`.
- E02 selection: seeds 916001–916012, both banks, `screen`.
- E03 selection: seeds 916301–916312, both banks, `screen-retry`.
- E03 confirmation: seeds 916701–916800, both banks, fixed 200 games. Recorded
  before launch; no selection games enter its estimate. Accept locally only if
  mean margin is at least +1 and the seed-block 95% interval is strictly positive.
- E01's first attempt failed because of a harness logging variable. Partial scores
  are excluded; the corrected harness reran the originally scheduled seeds.
- E02's first candidate failed an inclusive numeric-boundary probe. Its IR and
  execution specify a 1e-9 rounding tolerance; the rejected candidate remains archived.
- E03's first attempt exposed a verifier-only 7.1e-15-tile rounding discrepancy.
  The exact observation is retained as a regression fixture. Verification now
  tolerates 1e-7 tiles and explicitly rejects a .01-tile deviation. The candidate
  was unchanged, partial scores excluded, and registered seeds rerun.

The compiled E03 Linux/amd64 image passed the same 42 existing policy checks as
its local source. Image ID:
`sha256:d7f8a180df0cecdb28008b42ce1a869d43604d3680398e7177a6a6683845529a`.
No hosted conclusion follows from that executable smoke check.

## Fresh local confirmation

The modest-effect branch completed all 200 registered games: **115 wins, 85 losses**.
Mean paired-bank kill margin was **+1.465**, 95% seed-block bootstrap interval
**[0.225, 2.73]**, passing its >=1 / positive-interval gate. There were 31,499
changed decisions among 9,665,700 checked, with no detected scoped action/state
leaks. These are local head-to-head results, not a hosted win-rate claim.

The process stopped after 116 completed games without a policy failure. Before
resuming, all saved results were checked against the schedule and frozen hashes.
Their hashes stayed unchanged; only the 84 remaining games were run. The harness
now persists a schedule manifest and supports validated resume. It refuses to
automatically resume past a semantic reconciliation failure.

## Hosted gate

A candidate that passes local confirmation must still face fixed-roster hosted
A/B comparisons against pinned Richard v7, followed by the Myasnik v5 guardrail.
Both arms use the same game and opponent, with bank balance. Requests are drained
sequentially. The full protocol and sample floor are recorded before launch.
Current live API validation passed; this dry run launched no episodes.

The local harness uses synchronous simulated replies, unlike hosted scheduling.
A league promotion therefore requires fresh hosted evidence and a separate API
readback. Local source changes, image upload, league submission and champion
promotion are distinct operations.

## Artifacts

- [Prose IR and generated candidates](../../../coaching/policies/session-20260915/README.md)
- [Append-only ledger](../../../coaching/policies/session-20260915/ledger.jsonl)
- Raw episodes and verification tables: `duels/coaching-20260915-{followup,return,alternate}`.

## Next iteration

Measure opportunity frequency before a large evaluation. Add predicates only when
observed residuals require them; E03 uses an existing vocabulary and needs only a
strategy amendment. Preserve rejected edits and surprising estimates. A coach's
useful suggestion is still a hypothesis until its intended behavior and outcome
are separately established.
