# The Duel Loop

A 1v1 Fresh Meat ladder between a human and an evolving bot policy.
The human plays matches; an outside agent (Claude Code) studies the
logs after each one, edits `players/challenger.bas`, and tries again.
The loop ends when the challenger wins for real.

```
        human plays              agent reads logs
  duel.sh ──────────► duels/ ───────────────────► diagnosis
      ▲                                               │
      │                edits players/challenger.bas   │
      └────────── spar.sh sanity check ◄──────────────┘
```

## Playing a match (human side)

```sh
examples/pudge_wars/duel.sh              # you (west) vs challenger (east)
examples/pudge_wars/duel.sh --seed 42    # a different arena
```

Right-click walks (on an enemy: attacks), Q aims the hook
(`--quickcast` throws at the cursor instantly), S stops, 1–4 buy
upgrades (damage / distance / speed / radius). First to 10 kills
wins; 10 minutes is a draw. When the match ends press R to rematch —
every match gets its own log directory automatically.

Matches are logged under `duels/` in the directory you launched from
(the scripts run at the repo root, so `./duels/`).

## Improving the policy (agent side)

One iteration, after each human match:

1. Read `duels/history.jsonl` for the trend, then the newest match's
   `summary.json` (`duels/latest/` points at it).
2. Pull evidence from `events.jsonl` for the two or three biggest
   problems — concrete ticks, positions, and hook records, not vibes.
3. Edit `players/challenger.bas`. Bump the `version:` comment, note
   the hypothesis being tested in the header.
4. Sanity-check headlessly before the next human game:

   ```sh
   examples/pudge_wars/spar.sh                        # vs base.bas, seed 1
   examples/pudge_wars/spar.sh players/sniper.bas 7   # other foe, other seed
   ```

   A policy edit must not lose to `base.bas` and must not fail the VM
   (the headless summary prints `scripts: 2/2 active`).
5. Report what changed and why in one short paragraph.

Policies load at process start, so the human just starts the next
duel — no rebuild needed for `.bas` edits.

### Rules of the ladder

- Only `players/challenger.bas` evolves. Engine, balance, and log
  code changes are out of bounds for winning matches.
- The policy must stay team-agnostic: `spar.sh` seats the challenger
  west, the human duel seats it east. Derive sides from `selfTeam`,
  `riverWest`, `riverEast` — never hard-code a bank.
- Matches are deterministic. `replay.pwr` in each match directory
  re-simulates the exact game (`./pwheadless --replay PATH`), so any
  hypothesis about "what if" can be checked against what did happen.

## What gets logged

Each match directory (`duels/match_YYYYMMDD_HHMMSS/`):

| file | contents |
| --- | --- |
| `events.jsonl` | one JSON object per notable event, in tick order |
| `summary.json` | aggregates, per-player stats, every hook, every kill |
| `replay.pwr` | the action tape; re-simulates the match exactly |

Beside them, `duels/history.jsonl` gains one line per finished match
(outcome, score, per-player K/D/accuracy, policy fingerprint) and
`duels/latest` symlinks the newest match.

Positions are map tiles (x growing east, y growing south, 128×128
grid). `sec` is match time in seconds (32 ticks per second).

### events.jsonl catalog

Every line has `ev`, `t` (tick), `sec`. Player ids: west seat is
usually 1, east seat 2 — check `match_start.players`.

| ev | fields | meaning |
| --- | --- | --- |
| `match_start` | mode, seed, killGoal, players[] (controller, script, policySha) | who is playing, under what rules |
| `action` | id, act (walk/hook/attack/buy/stop/ping), x, y, target | an issued order; repeated walk/attack spam is coalesced |
| `state` | p[] (x, y, hp, cd, lay, vx, vy, buff, shield, windup), hooks[], runes[] | snapshot every 8 ticks (4 Hz) |
| `hook_launched` | id, hookId, from, aim, rangeTiles, speedTilesPerSec, damage, target {pos, vel, dist, hp, hookReady} | a hook left the hand, with the situation at release |
| `hook_landed` | id, hookId, victim, at, dist, flightTicks, victimHpAfter | the disk latched a body |
| `hook_missed` | id, hookId, closest {id, dist, hook, enemy}, flightTicks, targetMoved | full flight, no latch; `closest` says how near it came |
| `hook_resolved` | id, hookId, result (hit/deny_win/denied/cancel) | terminal state for non-miss hooks |
| `damage` | victim, by, amount, cause (hook/melee/drown/headshot), hpAfter, lethal | every HP loss |
| `kill` | victim, killer, cause, at, score, killerHp | a death, with the running score |
| `respawn` | id, at | back at the fountain pad |
| `river_enter` / `river_exit` | id, at, hp, by | dumped into / escaped the water |
| `rune_spawn` / `rune_taken` | kind, at / id, kind, inRiver | river power-ups |
| `buy` | id, upgrade, level, pointsLeft | a kill point spent |
| `match_end` | outcome (west/east/draw/aborted), reason, score, durationSec | how it ended |

### summary.json highlights

Per player: kills, deaths, hook accuracy overall and by launch
distance band (`hitRateByDist`), damage dealt/taken split by cause,
`dodge` (hooks aimed at me: hit vs dodged, average movement during
enemy hook flight), time spent in the river, upgrade build, unspent
points, `policySha`. Plus `hooks[]` — every hook ever thrown with
launch context and resolution — and `kills[]`, the match timeline.

### Analysis recipes

```sh
L=duels/latest
jq -r '.players[] | "\(.name) K\(.kills) D\(.deaths) acc \(.accuracy)"' $L/summary.json
jq '.players[] | {name, hitRateByDist, dodge}' $L/summary.json

# Where did the challenger die? (kills where it was the victim)
jq -c 'select(.ev == "kill" and .victim == 2)' $L/events.jsonl

# The human's hooks that hit: what did the situation look like?
jq -c 'select(.ev == "hook_landed" and .id == 1)' $L/events.jsonl

# Near-miss report: challenger hooks that almost landed.
jq -c 'select(.ev == "hook_missed" and .id == 2) | .closest' $L/events.jsonl

# Human movement style: positions over time.
jq -c 'select(.ev == "state") | [.sec, .p[0].x, .p[0].y]' $L/events.jsonl

# Cross-match trend.
jq -c '{score, outcome, players: [.players[] | {name, kills, accuracy}]}' duels/history.jsonl
```

## Writing the policy

`players/challenger.bas` is Polyworld BASIC (see `players/base.bas`
for the dialect and the commented host API). The script runs once per
decision tick per bot; globals persist between runs and start at 0.
`--difficulty` maps to decision cadence and aim noise (duels default
to every-tick decisions with no noise).

Host data (read-only variables): `selfId`, `selfTeam` (0 west,
1 east), `selfX`, `selfY`, `selfHp`, `selfMaxHp`, `selfKills`,
`selfPoints`, `selfLayer` (0 west bank, 1 east bank, 2 river),
`selfHooked`, `selfShield`, `selfBuff`, `hookReady`, `worldTick`,
`riverWest`, `riverEast`, ally ping slots (unused in duels), and the
next river drop (`runeSoon`, `runeNextKind`, `runeNextX`, `runeNextY`).

Host functions: `objectCount()`, `objectId/Kind/Team/X/Y/Hp/Alive/`
`Layer/Hooked/Shielded(i)`; `hookCount()`, `hookTeam/X/Y/Flying/`
`Victim(h)`; `runeCount()`, `runeX/Y/Kind(r)`; actions `walkTo(x, y)`,
`hookTo(x, y)`, `attackTarget(id)`, `buyUpgrade(kind)` (0 damage,
1 distance, 2 speed, 3 radius; 1 kill point each, level cap 10),
`halt()`, `ping(x, y)`, `placeWard(x, y)`. Object, hook, and rune queries
are fog-clipped the same way the renderer is: own team always, enemies
only on the home bank, in the river, within 20 tiles of a living
teammate or team ward, or along the padded corridor of an in-flight
team hook. Shop permanents
include Farwatch Ward (id 9): free shop charge that occupies one of six
inventory wells, 45 s of hidden team
sight on either bank, plant within 32 tiles. Planting spends the charge
and clears the bag well. The shop restocks every 60 s.

Arena facts the policy can rely on:

- Playable tiles run 8..119 on both axes. River columns are 53..75
  at the side lanes; west bank ends at x = 52 (`riverWest`), east
  begins at 76 (`riverEast`). Around the fountain both banks step in
  on X — walkable land closer than those lips. The fountain island
  sits at (64, 64).
- Spawn pads are seeded (lane shuffle + inland jitter, east mirrored).
  Read `homeX`/`homeY` — do not hardcode 22/106. Kills respawn on your
  pad after 4 s with a 2 s untargetable shield that breaks on acting.
  Shop stays at (22, 64) west / (106, 64) east.
- Hooks: base 60-tile range, ~20 tiles/s launch accelerating in
  flight, 2 s cooldown, 80 damage +15 per damage level. A hooked
  enemy is reeled to you; hooking an ally heals them a little;
  hooking a corpse denies. Hooks bounce off the island rocks and
  arena walls — a throw line crossing the fountain always misses.
- Movement: momentum walking (≈0.25 s to top speed), 9-tick hook
  windup roots the caster — juking beats reacting.
- Melee: ~28 damage inside ~5.2 tiles. Drowning ticks HP away; a
  swimmer walks home along the shortest path.
- HP: 1200 + 35 per kill, full heal on respawn; the home pad heals
  a trickle. Runes float the river on a public clock: first drop at
  0:20, then every 20 s. Even drops spawn north (y=16) and drift
  south; odd spawn south (y=111). Each kind visits both ends before
  the next (haste N/S, double damage, regen, big hook, lightning,
  bounty). Read
  `runeSoon` / `runeNextKind` / `runeNextX` / `runeNextY` to time
  the spawn or gank someone camping it. Hook the orb or wade.

Costed VM limits (a script that blows them fails visibly in the
summary's `scripts:` line): 20k instructions/decision, 64 KiB source.
Integer math only; no `abs`/`min`/`max` builtins — write them out.
`and`/`or`/`not`, `while`/`wend`, `if/else` (no `elseif` — nest
instead), `goto`, arrays via `dim`, and `mod` are all available.

## Determinism and trust

The sim is integer-only and seeded; the same seed and the same inputs
give the same match, bit for bit. Replays carry per-tick state hashes
and the headless runner verifies them (`replay hashes: N mismatches`
would appear in the summary — zero is silence). The logger observes
the world without mutating it, so logging never changes an outcome.
Match analytics (`summary.json`) are derived from the same tick
stream the game hashed.
