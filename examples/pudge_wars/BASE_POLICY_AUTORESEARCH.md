# Base versus Myasnik v75 — 2026-09-09

The default `players/base.bas` now uses a shorter movement prediction when
aiming hooks: `leadDiv` changes from 9 to 30. This reduces the extrapolated
offset to 30% of its previous value at zero Speed ranks. Myasnik changes
direction frequently; extrapolating its last short movement sample far
into the future was a poor prediction. This is an empirical adjustment,
not an exact hook-flight solver.

The starting policy already included the previous vision/economy work:
free far-bank wards, actual shop visits, budgeted permanent purchases,
full-range engagement, defensive Blink, and teammate safety. All of those
behaviors remain. Game rules, visibility, difficulty, and the opponent
were held fixed throughout this comparison.

## Fresh-seed results

Each format uses seeds **2001–2024**, with the policies swapping banks
for every seed: 48 matches per policy per format. Both formats use fair
difficulty and a 20-minute limit. Teams play to 30 kills; duels to 10.

| Format | Starting Base W–L–D | Updated Base W–L–D | Starting mean score | Updated mean score |
|---|---:|---:|---:|---:|
| 3v3 | 40–8–0 (83.3% wins) | **45–3–0 (93.8%)** | 28.83–20.02 | **29.71–18.63** |
| 1v1 | 34–5–9 (70.8% wins) | **41–4–3 (85.4%)** | 9.19–4.90 | **9.52–4.56** |

All **192** primary matches retained every script VM. All 192 replays
verified every recorded state hash. The duel draws are time-limit
endings; they are not counted as wins even if Base led on kills.

These are promising finite-sample results, not a guarantee of victory.
There are 24 paired map seeds per format, and the two formats share their
seed numbers. Do not treat all those games as independent observations.
Do not reuse these seeds as a fresh holdout for future tuning.

## Selection and diagnosis

The starting point was frozen from the user's working tree, rather than
from Git HEAD. Previous local studies were reviewed first. The earlier
vision/economy candidate won 42/48 on seeds 801–824; that is a separate
historical result, not the baseline measurement in the table above.

Full baseline episodes on seeds 1001–1004 were recorded and replay-checked.
For example, seed 1001 west's first death starts with an enemy hook at tick
489 and ends at tick 501 while the victim is crossing the river. This
shows a costly catch/transport sequence; it does not establish that the
aim adjustment caused an improvement in defense.

Selection tested fighter-only object scans, aiming headshots toward the
actual chain owner, more perpendicular defensive Blinks, and shorter
movement predictions. The candidate using divisor 30 won **24/24** on
selection seeds 1001–1012, versus starting Base's **20/24**. Other changes
and combinations were inconsistent across the initial four seeds and the
eight confirmation seeds, so they were not promoted. The hypothesis that
gadget filtering or reeler ownership would be the strongest fix was not
supported by those screens.

The single-parameter candidate was frozen before either final campaign.
The promoted file is byte-identical to that candidate. No settings were
changed after seeing the holdout. Headless matches completed without VM
failures; no simulation or runtime optimization was needed.

## Secondary checks

Small probes use seeds 3001–3004 for difficulty checks and 3001–3002
against stock opponents, always swapping banks. They are regression
probes rather than reliable win-rate estimates.

| Opponent / difficulty | Games | Starting Base wins | Updated Base wins |
|---|---:|---:|---:|
| Myasnik / easy | 8 | 6 | 7 |
| Myasnik / pro | 8 | 6 | 8 |
| aggressive / fair | 4 | 4 | 4 |
| sniper / fair | 4 | 4 | 4 |
| denier / fair | 4 | 4 | 4 |
| support / fair | 4 | 4 | 4 |

Combat, teammate, bot, and economy/vision suites passed against the frozen
candidate using their policy-path defines. The default policy was then
checked to be byte-identical to the tested file. The evaluator also passed
Python compilation. No full-repository test-suite claim is made.

## Reproduction and recordings

The study is `duels/base-counter-br94g_5w/`. It contains frozen policies,
the headless and graphical binaries, every screen, per-game records,
primary match logs, verified replays, and regression output. These large
artifacts are Git-ignored; preserve the directory separately if needed.

The reusable evaluator refuses to overwrite a campaign, records source
and runner SHA-256 identities, checks every VM, and optionally verifies
every replay. From the repository root:

```bash
study="$PWD/duels/base-counter-br94g_5w"
python3 scripts/eval_pudge_policy.py \
  "$study/candidate.bas" "$study/myasnik.bas" "$study/rerun" \
  --runner "$study/pwheadless" --first 2001 --last 2024 --record
```

Add `--team-size 1 --goal 10` for duels. Use a new output directory each
time. A new runner can be built with:

```bash
nim c -d:release -d:headless --hints:off --warnings:off \
  -o:pwheadless examples/pudge_wars/pw.nim
```

The labelled replay launchers in the study open the native viewer:

- `watch-base-vs-myasnik.command`: the original Base recording, seed
  1001 west (29–30).
- `watch-improved-base.command`: the improved Base recording, seed
  2001 west (**30–22**).

Labels above the red/west players are `Base / P1` through `Base / P3`;
blue/east players are `Myasnik v75 / P4` through `Myasnik v75 / P6`.
Replay files do not store policy names, so these launchers supply the
existing `--label` option explicitly. Space pauses; the transport bar
controls speed and seeking. No renderer or replay-format change was
needed to show policy labels.

```text
Starting Base  6e3f728c1b2f80b43ed8f5cb81597b51420d5e4192674d7ada5235f01b2c40c4
Updated Base   72cf4e8aa9437a87411dbb7a0b4e25bf2916dbfb5892debe53c30c44b20c90b7
Myasnik v75    f2e93668e4073212c3794aaac1af93fb4ae1931faa86fad8e56534f60d90dbc7
Runner         e53e3716eb5e1bb7cd9976e7da43f1bfe8fdbce3ce96c7b2a8e58c7abfd5ab2b
```
