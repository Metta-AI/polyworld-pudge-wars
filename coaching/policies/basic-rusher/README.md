# Winning Python policy transferred to BASIC

The default `examples/pudge_wars/players/base.bas`, the standalone
`examples/pudge_wars/players/rusher.bas`, and `coworld/players/base.bas` now contain
the same v16-derived controller. No Python process, model weights, extra host
functions, or game rebuild is required to load the raw BASIC artifact.
The previous working-tree Base is preserved in [baseline.bas](baseline.bas),
including the BASIC integer-division migration and nearest-hook correction.

The source policy is the retained [E06b Python v16](../session-20260915-bundle/README.md),
whose fresh local confirmation won 67/96 against v14. This port enables its
combined healing/spacing configuration and transfers:

- Full-range, shorter-lead hooks; range-first upgrades and repeated core purchases.
- Stable fishing lanes, one rune collector, coordinated emergency rescues,
  deliberate short healing, and recovery from below 40% through 75% HP.
- Melee-centroid hooks, a fountain guard on every throw, and persistent
  perpendicular CurveHook movement through windup, flight, and return.
- Safe fountain escapes, inland defensive Blinks, human pings, and free wards.

This is an **adaptation**, not exact Python action equivalence. Integer geometry,
missing teammate max HP/cooldowns, shield booleans, and synchronous actions require
explicit differences. [The semantic contract](policy.md) documents these, plus
candidate-selection limits and option priorities. In particular, a teammate's
observed peak HP is only a lower bound on max HP. The BASIC healing owner may be
on cooldown, delaying a heal. CurveHook can override a shopping or rally goal,
as in the retained Python package. These are useful future hypotheses, not
unmeasured claims that this port improves every part of v16.

## Current-engine results — 2026-10-14

The candidate was frozen before confirmation. Matches swap banks on every map;
the statistical unit is a map's mean margin across both banks. `pro` means a
decision every tick and zero aim scatter, matching the BASIC league cadence.

| Comparison | Games | Kill-goal wins | Mean score |
| --- | ---: | ---: | ---: |
| Corrected screen vs previous Base | 24 | 24 | 30–5.88 |
| Fresh confirmation vs previous Base | **96** | **96** | **30–6.10** |
| Stock aggressive/challenger/denier/patient/sniper/support | 48 | 48 | 30–4.27 |
| Duels vs previous Base | 24 | 22 | 9.54–0.92 |

Confirmation's paired-bank mean margin is **+23.896**, with a seed-block
bootstrap 95% interval **[+23.313, +24.490]**. Both banks improved (west +23.563,
east +24.229). The two non-winning duels ended at the time limit; they are not
counted as wins. Stock-opponent checks use only four maps each and are regression
screens, not strong estimates of population win rate.

Every one of these **192 matches** kept all VMs active and verified every replay
tick. Two additional complete local game-hosted episodes passed the file-loader
and player-status contract: homogeneous teams scored 30–6; a mixed team with
Rusher/Support/Aggressive scored 30–16 against previous Base/Support/Aggressive.
Both game-hosted replays verified. One mixed-team game establishes integration,
not mixed-team competitive strength.

An initial 48-game `fair` screen went 48–0, but predates corrections for native
rescue arbitration, respawn reset, nearest-catch selection and occupied fountain
landings. It is archived as diagnostic evidence and excluded from confirmation.
The later policy was not tuned on confirmation results.

The [protocol](protocol.json) pins source hashes, seeds, settings and the
confirmation gate. [Results](results.json) retain every paired outcome, replay
verification flag, input identity, and bootstrap summaries. Large raw logs,
replays and exact binaries live in `tmp/rusher-basic-20261014/`; preserve that
directory separately if needed. All listed seeds are now used evidence.

**Deployment status:** published as `pudge-basic-base:v2` on 2026-10-14 after
the user requested “deploy new policy”. Independent readback confirmed active,
competing membership `lpm_9bcc9096-a938-4748-a801-4da4b7a05855` as A-aron's
3v3 champion. A 2,048-tick hosted smoke ran all three candidate seats cleanly;
all 26,881 replay actions verified. Hosted competitive strength remains
unmeasured. [Deployment and rollback record](deployment/release.json).
The game version, filler pool, schedule, and 1v1 league were unchanged.

## Semantic IR and executable policy

[policy.md](policy.md) is the editable registered semantic document;
[controller.bas](controller.bas) is its BASIC grounding. [candidate.bas](candidate.bas)
is the exact frozen evaluated artifact. Generation and extraction recognize this
complete family; unsupported prose or executable edits fail closed. The grounding
is explicit and authored, not an automatic general-purpose Python translator.

```sh
python3 -m coaching.symbolic.rusher_basic_ir generate \
  coaching/policies/basic-rusher/policy.md /tmp/rusher.bas
python3 -m coaching.symbolic.rusher_basic_ir extract \
  /tmp/rusher.bas /tmp/recovered-rusher.md
python3 -m coaching.symbolic.rusher_basic_ir generate \
  /tmp/recovered-rusher.md /tmp/regenerated-rusher.bas
cmp /tmp/rusher.bas /tmp/regenerated-rusher.bas

# Run the current policy through the actual local BASIC league host.
python3 scripts/run_episode.py rusher:3 \
  coaching/policies/basic-rusher/baseline.bas:3 --seed 1014601
```

Validation passed the existing bots, combat, economy, teammates, nearest-threat,
simulation, rune, human, duel and file-player suites, plus nine new native port
checks. These include real windup/flight/return exposure, termination, interruption,
respawn, fountain rejection, ally clearance, centroid healing, deliberate healing,
and casting after Blink. Five IR tests cover deterministic round-trip, synchronized
default/package artifacts, registered edits, and rejection of unknown changes.
The seven existing coaching IR tests also pass.
All six local-episode integration tests pass, including loading every bundled
policy on both banks through the BASIC host.

Existing fixtures were aligned with the new behavior: range-first spending,
formation tested without an active curve, and headshots supplied with a real
visible reeling hook. An opening-shield fixture now checks only its actual dodge
contract; a separate exposed-target fixture verifies same-tick Blink and hook.
