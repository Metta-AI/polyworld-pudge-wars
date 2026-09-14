# Aaron's Base-derived rusher

`base.py` implements the improved native Base strategy over the released
Coworld JSON protocol. `player.py` selects it for `PUDGE_PERSONALITY=rusher`;
the other personalities keep their existing implementations.

Hosted `pudge-wars:0.3.17` (simulator 37) uses 1,200 HP, permits safe
fountain Blink crossings, flies Lightning throws at double hook speed, and
lights team fog from charged-hook fire trails. Replay tapes now carry seat
labels so Observatory nameplates can show policy names. The updated strategy
adds team recovery from below 40% HP through 75% HP and guarded escapes toward
the home bank. See the
[simulation study](../../games/pudge-wars/experiments/2026-09-10-hp1200-blink.md).
Crossing requires `game_version >= 35`; older hosts retain their Blink behavior.

Current 3v3 champion: **`pudge-wars-rusher:v14`**, policy-version ID
`41212e9a-6383-40f8-b44e-f4ceb64ef9c9`, membership
`lpm_a897a072-a07b-4aef-90fe-ef6e256640b5`.
Coworld: `cow_d1aad864-85bf-4028-b9c9-34d4e1a0c044`, platform-hosted Docker players.
Image: `sha256:678d7c8852d5c7da6f3fa45019660071305e7ff87af9f914106a4bb83e678305`.
The driver and Docker build default to `combined`. Local container certification
and hosted game certification passed; fresh hosted competitive results for v14
are still pending. The duel champion remains v10
(`6d9aa2b5-5a1c-4c06-9c77-6f2265b43848`), and recurring 1v1 rounds remain paused.
[Release and verification record](../../docs/hosted-release-0.3.17-2026-09-14.md).

The following results describe the earlier v13 healing/spacing release.

The [240-game experiment](../../games/pudge-wars/experiments/2026-09-09-support-spacing.md)
includes separate component screens and these fresh comparisons:

| Opponent | v10 W–L | v13 W–L | Games per arm |
| --- | ---: | ---: | ---: |
| Myasnik v5 | 19–21 | 35–5 | 40 |
| relh v2 | 15–5 | 20–0 | 20 |
| sniper v3 | 19–1 | 20–0 | 20 |

The primary Myasnik confirmation improved win rate by 40 percentage points
(95% interval +19.7 to +56.2; Fisher p=0.000254) and mean kill margin by ten.
Clustering fell from 17.41% to 0.27%. It verified 653 deliberate heals, but
rune collection declined 10.13%, narrowly missing the 10% mechanism target.
Healing's extra win benefit over spacing alone remains unconfirmed.
All 240 replays verified; 35 policy checks and six analysis checks pass.

The [earlier v9→v10 evaluation](EVALUATION.md) preserves the previous 108-game
port comparison and its original leaderboard opponents.

- [3v3 league guide](https://softmax.com/api/observatory/v2/leagues/league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0.md)
- [1v1 league guide](https://softmax.com/api/observatory/v2/leagues/league_f81c4e63-ad7b-4f32-a837-b7931929545b.md)
- Game rules and wire protocol: `game.docs.readme` and `game.protocols.player`
  in the downloaded canonical manifest.
- [Runtime migration assessment](../GAME_HOSTED_MIGRATION.md)

## Strategy and protocol differences

Spend points on distance, speed, damage, then radius. Visit the actual shop,
buy repeated Brand/Treads ranks and avoid replacing active
buffs. Use Base's shorter velocity lead, full hook reach, defensive Blink,
ally-safe throwing lanes, selective rescues and one responder per ally ping.

This is a Python port, not execution of the `.bas` artifact. Native Base's
measured Myasnik win rates do not establish this port's hosted performance.
The live 0.3.13 observation omits `ward_restock` and still uses paid wards with
3-tile placement. Skip Base's free far-bank ward strategy on that ruleset.
When the new rules expose `ward_restock`, buy the free charge and wait for a
confirmed inventory item before making a placement trip. The live
host treats `halt` as exclusive, discarding other actions in the same reply;
rescue holds instead use a walk target at the current position.

## Play alongside this policy locally

From the repository root:

```sh
uv run scripts/play_policy.py
```

Or double-click [play_policy.command](../../scripts/play_policy.command).
The launcher builds matching native host/client binaries and opens your seat:
**P1 is Aaron, P2–P3 are Base v13, and P4–P6 are Base v10**. It runs the Python
policy directly on this machine; Docker and Coworld credits are not needed.
Both healing and fishing spacing are enabled for your teammates. Nameplates
identify each seat. These matches use the current local game rules, which
now match hosted Coworld 0.3.17 except for later uncommitted edits.

Move with WASD or right-click; press Q then click to hook, E to grapple,
F to blink, R to toggle Rot, X to stop, G to ping, and 1–4 to upgrade.
F1 centers your hero. Add `--quickcast` to throw on Q press at the cursor,
`--opponent combined` to face v13, or `--name NAME` to change your name.
Close the window or press Ctrl-C to stop; rerun the command for a new match.
Completed matches save a replay and logs under `duels/local-policy/match-*`.
An interrupted match keeps its logs but does not produce a complete replay.

`./pw --human` uses native BASIC bots; use the launcher above for the Python
policy's healing and spacing improvements.

## Build and validate

Run from the repository root:

```sh
python3 -m unittest discover -s tests -p test_pw_coworld_policy.py
python3 -m unittest discover -s tests -p test_pw_support_analysis.py
docker build --platform linux/amd64 -f coworld/player/Dockerfile \
  -t pudge-support:combined-20260910 coworld
```

Use a current Coworld CLI to download the canonical package and run a complete
episode with one explicit image per seat. The installed June CLI rejects the
live manifest's `tags`; the tested Docker CLI is pinned to the public mirror at
`4c26e519040ffe7182104f3417035020acea607b`:

```sh
uvx --from 'coworld[auth] @ git+https://github.com/Metta-AI/coworld.git@4c26e519040ffe7182104f3417035020acea607b' \
  coworld download cow_548c1ac0-e9af-483e-bc7c-7048991ad267
```

The image command is `python -m coworld.examples.pudgewars.player.player`.
For mixed-image matches, pass that explicit `--run` argv so older bundled game
images start their policy role. This standalone Dockerfile only builds the
policy; no game rebuild is required.

Study artifacts are under `duels/coworld-base-l4r3452l/`: the downloaded live
manifest, old player source, local smoke/full episode logs and replays, unit
checks, accelerated native JSON comparisons, upload log and hosted XP results.
Hosted comparisons pin the old and new policy-version IDs and test both banks.

## Original v10 validation evidence

The 25 focused Python checks pass, and six copies of the exact uploaded image
completed the downloaded live fixture with no player exceptions.

The accelerated JSON harness compiled the released game's source at
`0767d18ab8a86925a8c5c937702143be1c62778c`. Against the saved
`coworld-pudgewars-player:rot-set-v66` source, seeds 4001–4004 on both banks gave:

| Mode | Wins | Losses | Draws | Mean kills, candidate–baseline |
| --- | ---: | ---: | ---: | ---: |
| 3v3 | 8 | 0 | 0 | 30.00–15.63 |
| 1v1 | 5 | 2 | 1 | 7.25–5.50 |

These are local regression evidence: the harness does not reproduce network
timing. `released-comparison.json` contains all terminal scores and ticks.
The earlier `json-comparison.json` used the newer working-tree engine and the
pre-fix port; it is superseded. The two pre-fix `full-candidate-*` container
matches were interrupted after discovering incompatible ward rules; they are
not completed evaluations.

The hosted pilot uses the actual v9 and v10 uploads, seeds 5001 and 5002, both
banks, canonical 3v3 and 1v1 variants, and their normal tick rates and limits.
`hosted-index.json` maps all eight requests to mode, seed and candidate bank.

Subsequent XP requests use **10–20 episodes per request**, as requested by Aaron.
Keep clone teams in fixed seat blocks and run equally sized requests on both
banks. Four 10-episode requests extend this comparison to 20 additional 3v3
games and 20 additional duels. `hosted-batch-index.json` records their IDs;
`batch-status.json` records all child episodes and their outcomes.

The follow-up field evaluation pins the current top three 3v3 champions:

| Rank at request time | Player | Policy | Episodes |
| --- | --- | --- | ---: |
| 1 | Andre von Auto | `myasnik-bas:v5` | 10 per bank, 20 total |
| 2 | richard | `co-gas-pudge-blind-hook-richard:v2` | 10 per bank, 20 total |
| 3 | relh | `co-gas-pudge-blind-hook-relhalpha:v2` | 10 per bank, 20 total |

`leader-opponents.json` preserves the ranking and exact policy-version IDs;
`hosted-leader-index.json` identifies the six requests. Do not equate the hosted
Myasnik policy label with the local `myasnik_v75.bas` file without source evidence.

## Watch a hosted win

[Watch the labeled v13 win](../../duels/support-spacing-83ndgym1/watch-combined-win.command):
west/P1–P3 are healing+spacing v13, east/P4–P6 are Myasnik v5. It won 30–9;
at about 22 seconds, P2 deliberately heals P1. The matching released viewer
preserves replay correctness and displays the policy name above each player.

Open `duels/coworld-base-l4r3452l/watch-hosted-v10-win.command` from the repository
root. It plays the actual hosted seed-5001 game: **red/west is rusher v9;
blue/east is Base v10**, which won 30–9. Every player has a policy nameplate.
The launcher uses a viewer compiled from the released game source. All 117,456
recorded actions replayed successfully under that matching build.

`duels/coworld-base-l4r3452l/watch-v10-vs-myasnik.command` plays a hosted 30–23
win over the current Myasnik leader. West/P1–P3 are Myasnik v5; east/P4–P6 are
Base v10. All 212,163 recorded actions passed the matching replay check.

## Healing and fishing-formation experiments

`BasePolicy` has independent `heal_allies` and `spread_fishing` switches.
The driver chooses them through `PUDGE_POLICY_ARM`:

| Mode | Behavior |
| --- | --- |
| `baseline` | v10 decisions; both experimental switches off |
| `healing` | One safe same-bank healer can replace a speculative shot; urgent combat, defense and rescues retain priority |
| `spacing` | Stable fishing lanes survive teammate deaths; one player collects an announced rune while the others keep separated lanes |
| `combined` (default) | Both changes; the validated v13 3v3 configuration |

For Docker, use `--build-arg POLICY_ARM=healing`, `spacing`, or `combined`.
The frozen policy versions are v11 (healing), v12 (spacing), and v13
(combined). Their IDs and
validation status live in the [version log](../../games/pudge-wars/players/pudge-wars-rusher/VERSION_LOG.md),
and the [experiment record](../../games/pudge-wars/experiments/2026-09-09-support-spacing.md)
contains the comparison and confirmation rules. Uploads alone do not replace
the active champion.

Healing requires a recipient missing at least 120 HP, a healthy available
healer 4–24 tiles away, no nearby enemy/hostile hook, no shield/Rot/active
chain, and a destination that does not pull the ally toward the river by
more than four tiles. One deterministic pair is selected; the healer holds
while the chain returns. The new modes record bounded private intent events.
The replay instrument measures actual restored HP independently of requests.
