# Pudge Wars policy development

This repository owns the Pudge Wars engine and player examples. Use this guide
at the commit selected by the league's Coworld manifest, not an unrelated branch.
The default `coworld/` package is **pudge-wars-basic**, a game-hosted BASIC runtime.
`coworld/platform-hosted/` is the separate, older Python/container runtime.
Confirm the selected game before choosing a policy format or evaluation command.

## Read first

- [BASIC player contract](coworld/GAME_HOSTED_MIGRATION.md): policy files, VM
  limits, integer arithmetic, seat isolation and failure reporting.
- [Base policy and API reference](examples/pudge_wars/players/base.bas): host
  functions and a working policy. A starter is not the user's uploaded policy.
- [Policy development skill](skills/pudge-wars-policy/SKILL.md): reproduce,
  edit, compare both banks, inspect failures, and report measured results.
- [Gameplay investigation](docs/gameplay-skill-gradient.md): hypotheses and
  dated evidence. Recheck findings against the selected source revision.
- [Neural packages](coworld/INFERENCE.md): optional tensor/Jev interfaces.

## Source map

| Question | Source |
| --- | --- |
| Rules and constants | `examples/pudge_wars/content.nim` |
| Deterministic simulation | `examples/pudge_wars/sim.nim` |
| Fog-visible BASIC host API | `examples/pudge_wars/bots.nim` |
| League host and seat lifecycle | `examples/pudge_wars/coworld_host.nim` |
| Native starter policies | `examples/pudge_wars/players/*.bas` |
| Published starter copies | `coworld/players/*.bas` |
| Complete local episodes | `scripts/run_episode.py` |
| Paired-bank policy comparisons | `scripts/evaluate_skill_gradient.py` |

Do not use the Python `base.py` workflow, old `games/pudge-wars/META.md`, or
historical container promotion results as current BASIC guidance. Read engine
code at the selected commit when prose and behavior disagree.

## Working context

Keep the selected league, Coworld ID/version, source commit, policy hash and
evaluation seed set in the report. Fetch the intended player's submitted file
before claiming to improve that exact policy. Preserve its source separately.

Use installed Hermes `game_support` to inspect build/evaluation readiness for
the exact league. Source access and a configured binding do not prove a build
or match succeeded. For standalone setup, follow [README](readme.md) and
`scripts/setup.sh`; never run setup merely because this guide was loaded.

When the Coworld changes, resolve the new release and read its guide. Keep old
candidates and evidence under their original source revision. Compare policies
again on the new engine before transferring performance claims. Loading this
context grants no permission to upload, submit, publish, or spend credits.
