---
name: pudge-wars-policy
description: Develop and evaluate a Pudge Wars BASIC policy against a pinned league engine, with paired-bank evidence and retained replays.
---

# Pudge Wars BASIC policy workflow

Use for policy development on `pudge-wars-basic`. Resolve the live league's
Coworld source commit first. Relative paths below start at that repository root.
For the separate container game, read `coworld/platform-hosted/` instead.

1. Read `coworld/GAME_HOSTED_MIGRATION.md` and the API comments in
   `examples/pudge_wars/players/base.bas`. Check uncertain behavior in `bots.nim`,
   `content.nim`, and `sim.nim` at the pinned commit.
2. Obtain the intended player's exact uploaded policy through the platform's
   authorized download path. Record its hash. If unavailable, identify the
   starter used and state that the player's source was not inspected.
3. Preserve the baseline. Make one candidate change in a separate worktree or
   candidate file. Name the hypothesis, target metric, seed count and stopping
   rule before evaluating. Separate 1v1 and 3v3 claims.
4. Run a complete baseline episode, then a candidate episode. Use the selected
   release's `pwleague` binary, not a binary built from a different checkout:

   ```sh
   python3 scripts/run_episode.py base aggressive --binary tmp/pwleague --seed 29
   ```

   Without `--binary`, the runner builds this checkout's host. Use
   `python3 scripts/run_episode.py --help` for output and duration options.
   Keep the default full match duration for competitive evaluation.
5. Compare both banks using frozen candidate/baseline files and fresh seeds:

   ```sh
   python3 scripts/evaluate_skill_gradient.py candidate.bas baseline.bas \
     --binary tmp/pwleague --output tmp/candidate-comparison \
     --first-seed 102001 --seeds 24 --team-size 3
   ```

   Use a new output directory. Run an identical-policy control when changing
   evaluation setup. After selecting a candidate, validate with held-out seeds
   and additional opponents; one matchup does not establish league strength.
6. Inspect retained results, private seat logs and replays. A policy failure is
   not a valid loss sample. Inspect at least one failure or regression before
   attributing an aggregate result to a mechanic. Check seat/bank attribution.
7. Report engine commit and binary hash, policy hashes, seeds, sample count,
   win/draw/loss counts, kill margin and uncertainty. Link retained evidence.
   Distinguish local improvement from a real upload or league submission receipt.

When editing a bundled starter, keep `coworld/players/` and
`examples/pudge_wars/players/` copies synchronized. For a user's candidate,
retain its independent source rather than overwriting shipped starters.

Read `docs/gameplay-skill-gradient.md` for the paired-bank evaluation rationale
and historical failure inspection. Its prior results do not measure a new
candidate or a changed engine.
