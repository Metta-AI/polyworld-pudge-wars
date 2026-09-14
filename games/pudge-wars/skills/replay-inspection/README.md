# Replay inspection for Pudge Wars

PWR tapes contain setup, actions and state hashes. They resimulate the game:
use a binary from the exact producing source/rules. A current working-tree
binary is not a decoder for the released v0.3.13 tapes.

Existing released tools and artifacts are under
`duels/coworld-base-l4r3452l/`. Preserve this Git-ignored study directory.
The source archive is `released-source/`; its source commit is in
[META.md](../../META.md). A fresh headless binary can be compiled inside that
archive with `nim c -d:release -d:headless --hints:off --warnings:off
-o:pwheadless examples/pudge_wars/pw.nim`.

Watch first. The study's `watch-v10-vs-myasnik.command` is a 30–23 Base win;
`watch-v10-myasnik-loss.command` is the 16–30 loss used in this investigation.
The latter's 6:49–7:31 stretch shows repeated captures and deaths on Myasnik's
bank. Space pauses; the replay bar supports seeking. Policy names are supplied
by six `--label` arguments in roster order, because the tape does not store
them. For 3v3, P1–P3/slots 0–2 are west; P4–P6/slots 3–5 are east.

## Durable survey

From the repository root, with a fresh output directory:

```bash
python3 games/pudge-wars/instruments/inspect_matches.py \
  --results duels/coworld-base-l4r3452l/hosted-results.json \
  --replay-root duels/coworld-base-l4r3452l/hosted-artifacts \
  --decoder duels/coworld-base-l4r3452l/pwheadless-live013 \
  --game-source 0767d18ab8a86925a8c5c937702143be1c62778c \
  --label-prefix leader-rank1- \
  --output duels/myasnik-investigation-new
```

Requires Python 3.11+ and the matching native decoder. No network or XP calls.
Inputs are a JSON list of hosted results (each with `episode_id`, `label`,
`candidate_side`, `n`, `result`) and `EPISODE_ID/replay.pwr` files. The existing
study's result collector documents the artifact API; replays are downloaded
through `/v2/episode-requests/{id}/artifacts/replay` using the Coworld client.
Never print authentication headers or tokens.

The instrument refuses to overwrite an output directory, records source and
binary identities and replay hashes, requires every tick and action to replay,
and compares terminal scores, tick, seed, kill goal and all per-seat kill,
death and hook counters with the hosted result. It writes:

- `manifest.json`: selected episodes and source/input/binary identities.
- `EPISODE_ID/decoder.log`, `decoded/match_*/events.jsonl` and `summary.json`.
- `EPISODE_ID/metrics.json` and combined `survey.json`: team metrics and a
  worst 60-second kill-differential window for viewing.

## Clock and limits

The join key is `(episode_id, slot, tick)`. Simulation time is 32 ticks/sec;
log `t` is a simulation tick; log player `id` maps to zero-based `seat` in
`match_start`. Use that roster mapping, not an assumed player-ID arithmetic.
State samples are every eight ticks (4 Hz). Hosted action replies take effect
after their observation, so an observation tick is not an action application
tick. Current accepted-action echoes help distinguish requests from effects.

The v10 private logs do **not** contain decision branches, target beliefs or
per-tick observations. A replay establishes world state and outcomes, not what
the policy saw or why it acted. Never infer policy intent from the logger's
`target`: that is a nearest-enemy heuristic.

Metric definitions matter:

- `hooks_thrown`, `reported_hooks_landed`, headshots and runes are engine
  counters, cross-checked against the hosted counters where available.
- `catches.enemy/friendly` classify resolved logger hook records by victim
  team. Records can miss hooks born and destroyed within one tick. They are
  incomplete and do not necessarily count every contact. In the first
  20-game survey, record count / thrown count was 96.0% for Base and 96.9%
  for Myasnik. Do not call this complete attack accuracy.
- Friendly hooks heal up to **120 HP** in v0.3.13 and reposition allies.
  A friendly catch is not automatically a mistake. Effective healing and
  deliberate rescue/heal intent are not recorded here.
- `death_attribution_estimate` and damage-by-cause use the existing logger's
  best-effort last-damage heuristic. Simultaneous effects and stale damage
  credit can misclassify a death. Use engine events for precise attribution.
- Clustering means all three living teammates have every pair within 12
  tiles. Denominator: samples with all three alive, not total match time.
  `unhooked_ready_player_samples` is a sampled readiness proxy (cooldown and
  windup zero, absent from sampled victim chains), not proof of an available
  safe shot or a missed action.
- `death_layer_samples` uses the last state within eight ticks before death.
  A bank transition between that sample and death can change the true layer.
- `score` is the team's score; `kills` sums personal kills. These need not
  agree for every ruleset/death type. Hosted results determine wins at timeout.

New questions should extend this instrument with documented definitions,
rather than create a different per-session parser of the same events.

## Effective healing

For the released source commit, apply `instruments/healing_trace.patch` in a
separate checkout and build the headless decoder with `-d:healingTrace` in
addition to the normal flags. The patch records HP immediately before and
after the friendly hook healing operation, plus tick, owner, recipient and
hook ID. It changes no gameplay rules. The decoder must still verify every
replay hash. A prebuilt decoder and patched source are retained in
`duels/support-spacing-83ndgym1/`.

Pass `--healing-trace` to the survey instrument. It requires the decoder's
`HEAL_TRACE_V1` marker, counts actual restored/wasted HP, and reads optional
`policy-slot-N.log` files beside the replay. A deliberate heal is counted only
when a private `heal_request` matches the owner and aim of a hook launched
within 32 ticks, and that same hook ID heals the requested recipient. Missing
logs mean intent is unavailable; they do not prove no deliberate heals occurred.

Normalize HP by sampled alive-player time (4 Hz), and compare completed arms.
Full-health friendly contacts are kept as zero-HP contacts. A successful
restore is evidence of healing, not automatically a net competitive benefit.

## Continuous verification

While `xp_campaign.py --watch` harvests an arm, run this instrument with
`--watch --expected-episodes 40 --label-prefix confirm-baseline-` (and its
normal paths/decoder flags). It verifies each newly harvested replay once,
records `progress.json`, and writes the final `survey.json` only when all
requested episodes are completed and verified. It reads sibling `status.json`
to reject failed/canceled episodes or an unexpected requested arm size. Use
a fresh output directory and keep incomplete outputs for investigation.
