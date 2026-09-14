# Pudge Wars 0.3.15 hosted release — 2026-09-10

Verified at 2026-09-10T22:40:09.445371+00:00.

This 0.3.15 release was superseded by [0.3.16](hosted-release-0.3.16-2026-09-11.md), which ships simulator 37 (double-speed Lightning throws and charged-hook fire trails that light team fog).

`pudge-wars:0.3.15` was canonical and the 3v3 league resolved to it.
Aaron's active 3v3 entry is `pudge-wars-rusher:v14`.

## Released behavior

- Each Pudge starts with 1,200 HP.
- Blink can cross the narrow river near the fountain within its existing 20-tile range when the destination is clear land. Landing on the fountain remains blocked.
- The Base policy retains deliberate ally healing and separate fishing lanes, recovers from below 40% HP until 75%, and uses guarded fountain escapes toward its home bank. Defensive Blink accounts for the occupied bank.
- The game image and WASM viewer share simulator version 36. JSON observations expose `game_version` so the policy can gate crossings on compatible hosts.

## Immutable artifacts

- Coworld: `cow_6d407c5d-3bfb-4740-bb12-bb5e14e1e81f`.
- Manifest: `sha256:d05e7c60692a3d0abfa54e16498ce9afdf044204fe88d8f153b11cc5227b6eb5`.
- Game image: `public.ecr.aws/q5f4m8t9/cogames@sha256:49a1956f992e7877317c8d13f5850065555e1ecc3e0553ee6699eb67b6f491d0`.
- WASM bundle: `sha256:f7ce07ccd472217e6614275d0f7950de134aaf6001885a5406e9c9d455d28025`.
- Rusher v14: `41212e9a-6383-40f8-b44e-f4ceb64ef9c9`.
- Rusher image: `471879937681.dkr.ecr.us-east-1.amazonaws.com/cogames/h0835grji1zfy5wakd4i56kn-3939e8b7673b/pudge-wars-rusher@sha256:ddaf18b1f493c0be4704a78b383294c1fe73568f8b407936ffedb2a9d3df4540`.
- Explicit policy argv: `python -m coworld.examples.pudgewars.player.player`; `PUDGE_PERSONALITY=rusher`, `PUDGE_POLICY_ARM=combined`.
- 3v3 membership: `lpm_a897a072-a07b-4aef-90fe-ef6e256640b5`.

Frozen inputs include 235 source/config files and 483 assets. They capture the
existing local changes on top of commit `0767d18ab8a86925a8c5c937702143be1c62778c`;
no Git commit or push was performed. Source and asset hashes, images, logs,
replays, browser screenshots, and registry responses are in
`duels/game-release-0.3.15/`.

## Verification

- Local executable certification passed all ten steps using the new game image and the exact v14 policy image.
- Hosted executable certification passed all ten steps; all five upload smoke episodes completed.
- Raw and gzip local-container replays loaded in Chromium without JavaScript, WebGL, failed-resource, or simulation-hash errors.
- A live container probe checked both seats: `game_version=36`, `hp=max_hp=1200`.
- The uploaded viewer bundle hash matches all nine locally tested files. All five downloaded hosted smoke replays report simulator version 36.
- Both built containers contain byte-identical copies of the frozen `base.py` and `player.py`. The registry's v14 image ID and explicit argv match the uploaded artifact.
- Separate API reads confirmed canonical 0.3.15, league resolution, and v14 as the active 3v3 champion.

The [simulation study](../games/pudge-wars/experiments/2026-09-10-hp1200-blink.md)
records the gameplay evidence. Fresh hosted win-rate evidence for v14 is still
pending; certification establishes runtime compatibility, not competitive superiority.

## League settings

The 3v3 scheduler retains `min_episodes_per_entrant=4` (20 episodes with ten
entrants), the existing daily budget, and its existing schedule. Settings were
compared before and after release. The duel champion remains v10 and recurring
duel rounds remain paused. Future automatic champion promotion remains `never`;
v14 was selected explicitly once. No extra XP campaign or full league round was
requested for this release.
