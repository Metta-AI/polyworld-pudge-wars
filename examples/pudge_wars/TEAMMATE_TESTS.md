# Default bot teammate checks

This pass changes `players/base.bas` decisions, not combat physics,
damage, kill rewards, human controls, or replay/network formats.

The match results below describe the teammate pass before subsequent
combat tuning. The current Base retains these behaviors; see
[the combat evaluation](BASE_POLICY_EVALUATION.md) for its newer strategy,
Myasnik comparisons, and regression results.

## Behavioral contracts

Run from the repository root:

```bash
nim r tests/test_pw_teammates.nim
nim r tests/test_pw_bots.nim
```

The teammate suite covers both banks, adjacent friendly bodies, deliberate
rescues, healthy swimmers, already-claimed saves (including a flying
rescue), ping expiry/ownership, one responder, safe-bank rallying, and
defensive blink priority. It also checks upgraded hook radius, teammate
motion, candidate health, stable tie-breaking, and read-only planning.

The original policy failed the adjacent-human, contested-rescue, rally,
and river-rally scenarios. Deliberate saves and immediate blink dodges
already worked; those are retained as regression checks.

## BASIC policy helpers

| Surface | Meaning |
|---|---|
| `safeHookTo(x, y)` | Normal hook with an ally-lane check after difficulty aim scatter. Returns 0 if blocked or unavailable. |
| `allyNeedsRescue(id)` | A living, unshielded teammate is on an enemy chain, in the river at <=60% HP, or a healthy swimmer freshly pinging their own position. |
| `rescueAlly(id)` | Attempts that rescue from the home bank, outside Rot, within reach and with no other ally obstructing or already attempting the save. |
| `teamPingResponder` | Nearest living, healthy bot seat for the latest team ping younger than three seconds; 0 if none. Stable player-id tie-break. |
| `hookReady` | No cooldown, windup, or active own chain; previously reported cooldown alone. |

Raw `hookTo` remains available. These helpers do not change human or
custom-policy collision rules. The default policy pauses to reel an ally
home and prioritizes survival over a rally. It only attacks at a rally
when an enemy near the ping is visible.

## Full-match audit

Use the same map seeds, difficulty presets, 3v3 roster, 30-kill goal, and
20-minute cap on both versions. Run each match to its terminal result,
check all six VMs remain active, and replay its recorded actions.

```bash
audit_dir=$(mktemp -d /tmp/pudge-teammate-audit.XXXXXX)
nim c -d:release -d:headless -o:"$audit_dir/pw" examples/pudge_wars/pw.nim
for difficulty in easy fair pro; do
  for seed in 7 42 2026; do
    "$audit_dir/pw" --seed "$seed" --difficulty "$difficulty" \
      --minutes 20 --duellog "$audit_dir/$difficulty$seed"
  done
done
```

In `summary.json`, count hooks whose `result` is `hit` and whose `victim`
is a player. Compare the thrower's `team` with the victim's team in
`players`. Keep enemy and allied latches separate; aggregate them per
simulated minute as well as by raw count. An allied latch is **not**
automatically a mistake: intentional saves are included. `combat.hits`
from the console is not an enemy-accuracy metric.

### Results: 2026-09-09

Matched self-play: seeds 7, 42, and 2026 on easy, fair, and pro. All nine
updated matches reached 30 kills with all six VMs active; all nine action
replays verified their state hashes through the end.

| Aggregate across nine matches | Before | Updated |
|---|---:|---:|
| Simulated minutes | 97.15 | 104.47 |
| Allied hook latches | 5,090 | 1,605 |
| Allied latches per minute | 52.39 | 15.36 |
| Enemy hook latches | 1,350 | 1,187 |
| Enemy latches per minute | 13.90 | 11.36 |
| Allied share of player latches | 79.0% | 57.5% |

That is a **70.7% reduction in allied latches per minute**, accompanied
by an **18.2% reduction in enemy latches per minute**. This is evidence
of less interference, not proof that every avoided latch was harmful.
Updated matches lasted 8.3–17.0 minutes, versus 7.8–13.7 before.

An additional fair-difficulty comparison put three updated bots against
three copies of the pre-change policy, then swapped banks for each seed.
Updated won 4/6: west 30–29 / east 21–30 on seed 7, west 30–26 /
east 25–30 on seed 42, and west 30–22 / east 30–23 on seed 2026
(scores here are updated team's kills first). All six finished with
working VMs and hash-exact replays. Six games are a smoke check, not a
statistically established win rate. Both teams in this comparison use
the updated host API, including corrected `hookReady` reporting.

The final no-log pro seed-7 run reproduced the audited state hash.
Locally it simulated 736 seconds in 8.39 seconds (87.7x real time);
the old run simulated 467 seconds in 4.69 seconds (99.5x). These are
single timing samples, not a formal performance benchmark.

Verification: all 18 new teammate checks passed, as did the existing bot
checks and the human, simulation, replay, fog, NvN, net, prediction,
network-simulation, co-world protocol/recording, duel, content, rune,
CLI, map, director, profiler, and audio test files: **20/21 Nim test
files passed**. Native and headless release builds succeeded.

The remaining `test_pw_hosting.nim` failed with a connection timeout
against the advertised primary-interface address. A focused retry showed
the test server listening on all interfaces and loopback `/status`
returning HTTP 200, while its advertised address timed out. That test
does not import the changed bot modules; hosting code was left unchanged.
The full suite is therefore **not green**; LAN-host reachability still
needs separate investigation.

Local raw evidence for this run:

- Baseline: `/tmp/pudge-gameplay-audit.9UO68m/`
- Updated matches and replays: `/tmp/pudge-teammate.IpQgQp/final/`
- Side-swapped matches: `/tmp/pudge-teammate.IpQgQp/paired/`
- Broader test output: `/tmp/pudge-teammate.IpQgQp/test_*.log`

## Limits and next playtest

The friendly-lane check is a conservative straight segment through the
aimed point with a short velocity projection. It does not solve future
paths, ricochets, or allies crossing after release. A healthy swimmer's
own-position ping means "pull me out"; there is no separate rescue-ping
type yet. The latest ping replaces an older call.

Responder selection assumes the default policy on bot seats; mixed
custom policies may ignore their assignment. Native acknowledgments,
explicit attack/defend/rescue ping types, and assist rewards remain
separate work. Self-play does not establish that humans find a bot fun.

For a human playtest, try standing beside a throwing bot, pinging a
different lane, and asking for a river rescue. Judge whether it respects
your intended movement and whether you can predict its next action.
