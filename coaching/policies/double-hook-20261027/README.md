# Double-hook policy experiments — October 27, 2026

**Deployed as `pudge-basic-base:v3`, A-aron’s 3v3 champion, on user request.** The strongest full-match result is
[`candidate-v9.bas`](candidate-v9.bas): it measures visible hook speed and improves
an existing follow-up shot without changing casting priorities or movement.
Across 48 fresh 3v3 matches it produced **498 headshots versus 437** for the frozen
local baseline (+14%), with 26 wins. Overall kills were essentially tied:
1,174 versus 1,170. This is progress on double hooking, not evidence of a stronger
competitive policy overall.

The default BASIC sources, semantic policy, coworld copy and hosted champion were
left unchanged during evaluation. After reviewing these results, the user requested
“push new policy”: the repository defaults now use the exact v9 artifact. The
hosted champion was subsequently updated after the explicit request “deploy new
policy to the league”; see [release evidence](deployment/release.json). The game
itself was not redeployed. `baseline.bas` freezes the already-modified local default at the
start of this task; it is **not** the deployed `pudge-basic-base:v2` champion.
Canonical Pudge Wars physics runs at 32 TPS; no engine, observation, or server
changes were made.

## What changed

- **v9 — measured follow-up aim:** Observe hook-head displacement over four ticks.
  Reset samples on visibility gaps and phase changes, retaining the outbound
  speed estimate across contact. Predict the victim's reel and our nine-tick
  windup plus accelerating flight. Only adjust the existing catch-target shot;
  retain the midpoint fallback when speed is unknown or no interception is
  accepted. Keep friendly-corridor and fountain safety checks.
- **v8 — anticipatory candidate (`candidate.bas`):** Recognize a visible allied
  hook about to catch an exposed enemy, then start the finishing throw before
  contact. Only do this on our bank, outside close combat, recovery, nearby hook
  threats and enemy Rot. Strong controlled timing result, but failed the match
  gate. `precast.bas` contains this experimental skill.
- **v7 (`candidate-v7.bas`):** Earlier, less-restricted anticipatory attempt.
  Archived because its promising development result did not generalize.

These are two separate candidates, not combined skills. v9 uses only visible
observations; it does not know teammates' cooldowns or hidden positions.

## Fresh confirmation results

Each row used a frozen policy on 24 new map seeds, both banks, three bots per team,
pro difficulty, first to 30, 20-minute limit. Every match reached the kill goal,
all six VMs stayed active, and every recorded replay matched on every tick.

| Variant | Seed range | Wins / 48 | Headshots, candidate : baseline | Mean kill margin | Paired-map 95% interval |
| --- | --- | ---: | ---: | ---: | --- |
| v7 | 1027201–1027224 | 21 | 462 : 494 | −2.06 | [−4.48, +0.48] |
| v8 | 1027301–1027324 | 22 | 484 : 494 | −1.40 | [−4.25, +1.40] |
| v9 | 1027401–1027424 | 26 | 498 : 437 | +0.08 | [−2.08, +2.04] |

v9's descriptive headshots per enemy catch were 0.1266 versus 0.1135 (+11.5%).
Its paired-map headshot difference was +1.27 per match, with a 95% bootstrap
interval of [+0.33, +2.23]. These intervals are per-variant exploratory estimates,
not corrected for multiple experiments. Counts compare the two teams playing
against each other; they are not independent matches against a third opponent.
Headshots can also interrupt enemy healing hooks, so the ratio is not a causal
probability of converting an allied catch.

The preregistered overall promotion gate required a positive lower confidence
bound on kill margin as well as a mechanism improvement. None cleared it.
Stock-opponent, mixed-team and duel promotion checks were therefore not run.
During development, no hosted leaderboard evaluation or deployment occurred. The later user-requested
repository default replacement does not change this failed-gate result.

The seven full-match development screens reused seeds 1027111–1027116, both banks
(84 games total). They are tuning evidence, not confirmation. See
`selection-history.json`, `protocol.json`, and `confirmation-v*.json`. v3/v4 were
scenario-only variants and never advanced to match screens. In total, **228 full
matches** were replay-verified across development and confirmation.

## Controlled timing drills

Both instruments execute real allied casts through the simulator and BASIC VM,
with two banks, two lanes, five finisher offsets, three enemy distances and three
allied hook-speed levels on map 2026. Each emits all 180 fixtures, including
ineligible ones. Victims are stationary and other combatants are shielded. These
are development drills, not realistic opponent benchmarks.

| Drill | Baseline finishes | Candidate finishes | Eligible / total |
| --- | ---: | ---: | ---: |
| Anticipate an approaching allied hook (v8) | 0 | 107 | 144 / 180 |
| Observe the cast, become ready when it catches (v9) | 60 | 64 | 114 / 180 |

The first drill deliberately keeps the finisher idle and ready until an allied
hook comes within 12 tiles of its target. It isolates anticipation; it does not
measure natural hook readiness. Terrain prevents approach in 36 fixtures.
The second allows normal movement and observation, but holds the finisher's hook
on cooldown until the allied catch. In 66 fixtures no allied catch occurs within
the setup window. Its four gains are mirrored fast-hook cases; no eligible case
regressed. `scenario-results.jsonl` and `followup-results.jsonl` preserve all rows.

`tests/test_pw_double_hook.nim` checks the archived v8 anticipation and current
default v9 follow-up through completed kills on
both banks, with the v9 cases covering speed ranks 5 and 10. The frozen baseline
fails these cases. Both candidates also pass all 14 existing combat-policy tests.

## Reproduce locally

Run from the repository root with the usual Nim dependencies installed:

```sh
mkdir -p tmp/double-hook-run
python3 coaching/policies/double-hook-20261027/generate.py
python3 coaching/policies/double-hook-20261027/generate-v9.py
nim c -d:release -d:headless --hints:off -o:tmp/double-hook-run/pw examples/pudge_wars/pw.nim
python3 scripts/eval_pudge_policy.py \
  coaching/policies/double-hook-20261027/candidate-v9.bas \
  coaching/policies/double-hook-20261027/baseline.bas \
  tmp/double-hook-run/matches --runner tmp/double-hook-run/pw \
  --first 1027401 --last 1027424 --difficulty pro --jobs 4 --record
python3 coaching/policies/double-hook-20261027/analyze.py \
  tmp/double-hook-run/matches tmp/double-hook-run/report.json
nim r -d:release -d:headless --hints:off -o:tmp/double-hook-run/test tests/test_pw_double_hook.nim
```

The generators reproduce the exact tested bytes. These seeds reproduce an
existing result; a future tuned candidate needs another untouched confirmation
set. The evaluator refuses an existing output directory and hashes the policy,
opponent and runner before and after each evaluation.

Build `games/pudge-wars/instruments/double_hook_scenarios.nim` or
`double_hook_followup_scenarios.nim` with the same Nim flags; run the resulting
binary with one BASIC policy path. To run the existing combat checks against a
candidate, supply `-d:CombatPolicy=/absolute/path/to/candidate.bas` when running
`tests/test_pw_combat_policy.nim`.

`identities.json` records frozen source and runner hashes. Compact match rows are
in `confirmation-matches.jsonl`; complete summaries, logs and verified replays
remain locally under the ignored `tmp/double-hook-20261027/` directory. Some
completed event logs are gzip-compressed; the analyzer accepts either form.

## What remains

Aiming alone has not established an overall match advantage. The next experiment
should measure missed opportunities due to cooldown readiness, finisher position,
and reeler movement before changing those behaviors. Simple long hook reservation
and elevating follow-ups over ordinary combat both lost development screens.
Continue from the selected v9 default; do not promote v7/v8 based on the
107/144 controlled-drill result.

## Repository release

The user explicitly requested pushing the new policy after the inconclusive
overall result was reported. `controller.bas`, its semantic contract, and all
three default BASIC copies are synchronized to the byte-identical tested v9
artifact. Semantic round-trip, default combat, rusher, and double-hook regression
suites pass. The v9 follow-up regression now targets the shipped default.
The frozen experiment policies and original promotion-gate outcomes stay intact.
Unrelated earlier research remains outside this commit.

## Hosted release

After the explicit league-deployment request, v3 passed a 2,048-tick hosted smoke
on canonical Pudge Wars 0.1.9. All three candidate seats ran cleanly; all 17,271
replay actions and every tick verified. A separate API read confirmed v3 as
A-aron's active, competing champion. See [release.json](deployment/release.json)
for immutable IDs, hashes and rollback. This runtime check does not establish
hosted competitive strength.
