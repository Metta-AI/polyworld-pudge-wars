# Hosted evaluation design for Pudge Wars

Use existing replays to diagnose, native full games to catch regressions, and
hosted episodes to judge the actual uploaded policy. Keep the engine/rules,
policy versions, observation timing and opponent identities explicit.

User preference: **10–20 episodes per XP request**, targeting leaderboard
policies. For a directional A/B of a new candidate against v10, use four
ten-episode requests: two arms × two starting banks, each against the same
pinned Myasnik version. This is 40 episodes total. Keep three identical copies
per team in slots 0–2 versus 3–5; never interleave the teams.

Pin the public champion policy version UUID from the league membership API;
the leaderboard player label alone does not identify an immutable policy.
Record all request bodies, actual episode rosters, seeds, result artifacts,
game source/image and uploaded candidate digest. Recheck current memberships
before a new campaign instead of treating META.md as current rankings.

Four requests with generated seeds are bank-balanced independent batches,
**not a paired-seed experiment**. If a future API supports a distinct seed
schedule per episode, match the schedule across arms and banks and verify its
readback. Repeating one seed ten times is not ten independent maps. Retain
network scheduling as a source of variation even with matching seeds.

Pre-record one hypothesis, its branch-exposure test, expected mechanism
metrics, the primary result metric (win/draw/loss), score margin, and what
would refute the hypothesis. Complete all batches before a verdict; early
finishers can bias results. Treat 20 games per arm as directional. Select a
larger fresh validation campaign for the effect size you need to distinguish;
there is no established verdict-sized sample floor in this repository.

Keep draws and failures explicit. Hosted v0.3.13 resolves a timeout lead by
kills; the previous native evaluator counted non-goal timeouts as draws.
Use the actual product's score convention for hosted claims. Do not promote
solely because a small local or hosted screen looks good.

After an encouraging Myasnik screen, check both other pinned leaders and
1v1 separately before promotion. Healing and role assignment have no same-team
target in 1v1 and should preserve the duel path. Record failures and rejected
levers in [closed_levers.md](../../closed_levers.md).

## Campaign tool

`games/pudge-wars/instruments/xp_campaign.py` now supports `--create`,
`--dry-run` and `--watch`. Run it using a Python environment with `coworld`
and `jsonschema`, from outside the repository so the local `coworld/` does
not shadow the installed API client. For example, use
`/Users/aaln/.local/share/uv/tools/coworld/bin/python3` with an absolute script
path. `--create` requires `--study`, `--label`, `--policy`, `--opponent` and
`--side`; `--n` defaults to 3 and `--episodes` to 10. Episode counts outside
10–20 are rejected. Create requests sequentially within a study directory.

Every create validates against the live OpenAPI schema before posting. A
stable study/label idempotency key prevents duplicate requests on a retry.
`--watch` harvests completed results/replays, candidate private policy logs,
actual rosters, and statuses every 30 seconds. It checks the resolved policy
IDs and canonical game version. Failed episodes remain explicit in
`status.json`; only completed artifacts enter `hosted-results.json`. The
watcher can be restarted to resume harvesting without launching more XP.

The current upload CLI expects one argv token per flag:
`--run python --run=-m --run coworld.examples.pudgewars.player.player`.
Set the experimental image mode with Docker `--build-arg POLICY_ARM=healing`
or `spacing` (or `combined` after screening the individual changes). Record
immutable image and policy-version IDs before running.

`games/pudge-wars/instruments/compare_campaign.py --study PATH --baseline
PREFIX --candidate PREFIX --output FILE` compares two complete arm prefixes.
It rejects missing/failed episodes, mixed policy versions or opponents,
unexpected resolved rosters/game versions, and repeated seeds. It reports
bank-specific W/L/D, mean kill margins, Wilson 95% win-rate intervals,
Newcombe intervals for the win-rate difference, and a two-sided Fisher exact
test of wins versus non-wins. Keep selection screens separate from fresh
confirmation; a small p-value on a selected screen does not replace the
pre-recorded confirmation campaign. Draws remain explicit in the report.

The released host uses millisecond wall-clock seeds when none are specified;
simultaneous starts can collide. Default comparison behavior rejects repeated
seeds. If pre-recorded before confirmation, `--repeated-seeds first-id`
retains the smallest episode ID per distinct seed for inference and reports
all games separately, with duplicate IDs disclosed. Use `--minimum-unique`
for the pre-recorded minimum independent sample size. Cross-arm seed reuse
still rejects the comparison. Do not silently count duplicate maps as fresh
independent evidence or change this rule after seeing confirmation results.

Optional repeatable `--baseline-survey` and `--candidate-survey` arguments
attach exact-healing and formation rates from completed replay surveys. Their
episode identities must match the full compared arms, including disclosed
duplicates; these are pooled descriptive mechanism measurements.
