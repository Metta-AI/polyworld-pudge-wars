# Base policy combat evaluation — 2026-09-09

The validated candidate is now `players/base.bas`. It nearly doubled
average team kills against `/Users/aaln/Downloads/myasnik_v75.bas`, without
changing game rules or the reference policy. The previous Base in this
comparison already includes the teammate improvements documented in
[TEAMMATE_TESTS.md](TEAMMATE_TESTS.md).

## Results

Every primary match is fair difficulty, 3v3, first to 30 kills, with a
20-minute limit. Each seed is played twice, swapping the policies' banks.
Scores below put Base first.

| Evaluation | Previous Base wins | Updated Base wins | Previous mean score | Updated mean score |
|---|---:|---:|---:|---:|
| Original seeds 1–24, 48 games per version | 0/48 | 19/48 (39.6%) | 12.15–30.00 | 23.54–27.38 |
| Held-out seeds 101–124, 48 games per version | 0/48 | 18/48 (37.5%) | 12.21–30.00 | 23.42–27.96 |

Average kills increased **93.8%** on the original sweep and **91.8%** on
held-out seeds. Myasnik still wins most games; this is a substantial
improvement, not evidence that Base is now the stronger policy overall.
There were no draws or time-limit endings in these comparisons.

The original 48-game baseline was reused with the same frozen headless
runner. This pass ran 144 additional primary matches: updated Base on
both seed sets and previous Base on the held-out set. All 144 finished
with **6/6 script VMs active**, and every tick of all 144 recorded replays
matched its state hash.

## Changes that earned promotion

- Save Blink for incoming hooks and river escape. Remove offensive
  blinks that chase a flying hook or a teammate's catch.
- Approach an allied catch from our safe finishing bank instead of
  walking toward the victim's current river position.
- Use an available short-range, ally-checked hook before settling into
  melee. Fight back when trapped on enemy land; retain the low-health
  restrictions on self-damaging Rot.
- Stage farther inland (`holdBack` 4 → 16), engage at longer range
  (`engageDist` 34 → 44), and extend opportunistic rune reach (26 → 36).
- Spend every available kill point immediately in this order:
  **Distance → Speed → Damage → Radius**, replacing Radius first.

Friendly-lane checks, deliberate rescues, claimed-rescue ownership,
single-bot ping response, and defensive dodges remain intact. No changes
were made to physics, rewards, visibility, difficulty, or Myasnik.

## How the candidate was selected

Full-match logs and source inspection identified exposed forward
positioning, offensive Blink expenditure, and missed short-hook damage
as hypotheses. For example, original seed 7 has an early Base catch at
tick 69 followed by transport across the river and death at tick 95.
That trace motivates investigation; it does not alone establish which
change caused the eventual improvement.

Variants were screened on seeds 1–4, both banks, then the promising
combinations were checked on seeds 5–8. The selected combination won
9/16 with 26.44 average kills across seeds 1–8. An earlier, longer-lived
dodge response and suppressing rune-lane convergence did not improve
their initial screens. Adding the early dodge to the selected combination
or disabling chain-cut attempts also underperformed it and was rejected.
The range, staging, and upgrade-order changes were tested as a group;
their individual contributions have not been isolated.

The cleaned candidate was frozen before running seeds 101–124. It was
not tuned after seeing held-out results, and the promoted file is
byte-identical to that candidate. Seeds 1–24 are a regression sweep,
not an independent estimate, because some were used during selection.
Future tuning needs a new held-out seed set.

One complete baseline episode was also profiled: 337.88 simulated seconds
in 0.273 seconds of headless wall time, with 7,503 bot decisions and all
VMs active. This was a single diagnostic run, not a timing benchmark;
it found no runtime failure explaining the weak score.

## Secondary probes and limits

These smaller terminal-match probes all retained 6/6 active VMs, but
were not logged/replay-verified and are not robust win-rate estimates.

| Opponent / difficulty | Games per version | Previous Base wins / mean score | Updated Base wins / mean score |
|---|---:|---:|---:|
| Myasnik / easy, seeds 301–302 | 4 | 0/4 / 13.00–30.00 | 0/4 / 15.00–30.00 |
| Myasnik / pro, seeds 301–302 | 4 | 0/4 / 7.75–30.00 | 1/4 / 23.75–28.50 |
| aggressive / fair, seed 301 | 2 | 2/2 / 30.00–21.50 | 2/2 / 30.00–9.50 |
| sniper / fair, seed 301 | 2 | 2/2 / 30.00–13.50 | 2/2 / 30.00–8.00 |
| denier / fair, seed 301 | 2 | 2/2 / 30.00–11.00 | 2/2 / 30.00–5.00 |
| support / fair, seed 301 | 2 | 1/2 / 27.00–25.50 | 2/2 / 30.00–8.00 |

Updated Base also beat previous Base **8/8**, averaging **30–13.5**, on
fair seeds 201–204 with banks swapped. The easy-difficulty Myasnik probe
still had no wins. These tests do not establish 1v1 strength or whether
humans find the bot more enjoyable; mixed human/bot play needs a playtest.

Allied hook totals include deliberate rescues, so they are not a count
of mistakes. Longer updated matches increased raw allied latches, while
their rate fell slightly: 8.00 → 7.34 per simulated minute on the original
sweep and 7.80 → 7.44 on held-out seeds.

## Regression checks

All seven new combat scenarios fail on previous Base and pass on the
updated policy. All 18 teammate checks also pass. After promotion, these
eight test files passed against the live default policy:

```bash
for suite in combat_policy teammates bots human sim replays fog nvn; do
  nim r "tests/test_pw_${suite}.nim" || break
done
```

The bot tests now expect Distance first and Speed second. The combat,
teammate, and bot suites accept optional `CombatPolicy`, `TeammatePolicy`,
and `BasePolicy` string defines respectively to test a frozen candidate.

The optional private `partner.bas` headshot fixture exposed an existing
blink/aim edge case: with the reeler holding position, the partner's
landing point can equal its lead-aim point, producing a rejected
zero-length hook. Previous Base's incidental blink moved the reeler and
masked this. The headshot-aim test now puts the partner's Blink on
cooldown to isolate the behavior it checks. **The partner runtime edge
case remains unfixed**, and no private partner code was changed.

This was a focused regression run, not a full-suite-green claim. The
earlier teammate pass's advertised-interface hosting timeout remains a
separate issue; see [its test notes](TEAMMATE_TESTS.md).

## Reproduce and inspect

The local study directory is
`duels/base-improvement.XLCVmD/`. It contains the frozen policies,
screening scores, selection contract, candidate freeze record, profile,
test output, and per-match logs/replays. These large artifacts are ignored
by Git and must be retained separately if this checkout is discarded.

- [Aggregate results and per-game records](../../duels/base-improvement.XLCVmD/final-results.json)
- [Per-game CSV](../../duels/base-improvement.XLCVmD/final-scores.csv)
- [Original baseline results](../../duels/base-vs-myasnik-48.Zqomcj/results.json)

From the repository root, rerun 48 candidate games plus replay checks
with the exact frozen runner and policies. Choose a new label on each
invocation; the script refuses to overwrite an existing campaign.

```bash
study="$PWD/duels/base-improvement.XLCVmD"
bash "$study/validate.sh" rerun_candidate \
  "$study/candidate.bas" "$study/myasnik_v75.bas" fair 101 124
bash "$study/validate.sh" rerun_previous \
  "$study/base_before.bas" "$study/myasnik_v75.bas" fair 101 124
```

To watch the live default against the reference policy:

```bash
./pw --team-size 3 --difficulty fair --seed 2026 \
  --killGoal 30 --minutes 20 \
  --bot "examples/pudge_wars/players/base.bas:3" \
  --bot "/Users/aaln/Downloads/myasnik_v75.bas:3"
```

Add `--human:0` to play in the first Base seat. Restart `./pw` to load the
new BASIC policy; this policy-only update does not require a native
rebuild.

Frozen SHA-256 identities:

```text
previous Base  96df1d75d5c68b9bd5f645a9f050d42c96f14ef25e2e798035831f3a3fe2c2c8
updated Base   84634a1ae2d68cc10a072950d9e81f216f3c55d2d924137772d55da010530305
Myasnik v75    f2e93668e4073212c3794aaac1af93fb4ae1931faa86fad8e56534f60d90dbc7
```
