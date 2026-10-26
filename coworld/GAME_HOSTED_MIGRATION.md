# Pudge Wars BASIC league migration

The default `coworld/` package is now **pudge-wars-basic**, using game-hosted
BASIC files. `coworld/platform-hosted/` preserves the `pudge-wars` Docker-player
package and human-play entrypoint. Existing Docker uploads cannot enter the
BASIC runtime; they need replacement `.bas` submissions. The public 3v3 league was migrated on 2026-10-09; its 37 container memberships
were retired and its three container fillers replaced. The sibling 1v1 league
continues using the platform-hosted package.

Reference contracts were checked on 2026-10-09 against Polyworld
`743f108091ca20b78f7e3fdc1a42f59ddb4ac795` and Metta
`d92408b26a` main. The dependency lock pins the same Bassy and Fixxy revisions
as that Polyworld release. This replaces the vendored `polyworld/basic.nim` VM.

## Player contract

Upload raw BASIC up to 64 KiB or a neural ZIP package up to 16 MiB; the staged
filename has no extension. [Neural tensors and Jev](INFERENCE.md) use the shared
GotA interfaces. Every seat
gets an independent VM; globals, arrays and strings persist between decisions.
The VM has no filesystem access. Host-configured LLM/Jev callbacks use the
platform sidecar with per-seat attribution. The game process can read
all submitted source, as with other game-hosted Coworlds.

Each living seat runs once per simulation tick, in rotating seat order, through
the same fog-clipped host functions and recorded action path as native play.
The simulation is 32 Hz and runs without real-time pacing in league episodes.
The existing integer tile coordinates and gameplay rules are unchanged.

Per-seat limits:

| Resource | Limit |
| --- | --- |
| Source | 64 KiB |
| VM memory | 2 MiB |
| Instructions per decision | 100,000 |
| Work units per decision | 250,000 |
| Globals / arrays / array elements | 256 / 32 / 4,096 |
| Call depth | 16 |
| Strings / string storage / one string | 1,024 / 256 KiB / 64 KiB |
| Native tensor/package storage | 32 MiB per seat |
| PRINT per decision | 1 KiB / 128 events |
| Private episode log | 10 MiB, then truncated |

Bassy supports fixed-point decimals and strings. `/` performs Q16.16 division;
`\` performs integer division. Comparisons return -1 or 0; `and`, `or`, `xor`
and `not` are bitwise. Host flags still return 1 or 0, so negate them with
`flag = 0`. IDs, indices and all Pudge action arguments require exact integers.
Use `(worldTick \ 8) mod 4`, for example. Bundled bots were ported to explicit
integer division to retain their existing decisions. Archived coaching policies
are historical artifacts and need the same source port before use with Bassy.

The complete game API is documented in
[`base.bas`](../examples/pudge_wars/players/base.bas). The bundled policies in
`coworld/players/` must match the corresponding native sources; a test enforces
that equality. Keep both copies updated when changing a bundled bot.

`PRINT`, source diagnostics and VM errors go only to the owning seat's log.
Compile/source-limit errors terminate the episode through
`COGAME_PLAYER_FAILURE_URI` with a zero-based `failed_policy_index`. Runtime
errors disable only that VM; other seats continue, and private status marks the
failed VM. Replay or output-storage errors never publish successful results.
Missing/mismatched staged files are infrastructure failures, not player blame.

The manifest opts into `coworld-player-seats/2`. Each seat can emit optional
private annotations with `ANNOTATE(worldTick, kind$, function$, args$)` where
`args$` is a JSON object string. Zero means accepted; `ANNOTATE_ERROR$()` explains
rejections. Limits are 1,000 records, 2 KiB per record and 2 MiB per episode per
seat. Native play exposes the same functions with annotations disabled. The
annotation sink is ported from the pinned Polyworld `src/polyworld/annotations.nim`.

All logs, annotations, status and replay bytes finish before the atomic results
marker. The process stays available for collection; `/healthz`, the global
viewer, and WebSocket Ping/Pong remain live. League episodes accept no JSON
player actions or human seat connections.

## Humans alongside BASIC policies

The `human` variant supports 3v3 hosted play with the same BASIC files. The
hosted-play service must support file policies and set `COGAME_PLAY_SESSION_ID`.
A league lobby episode a person joined (a ranked match played from the desktop
client) sets no play session id; its runner stages the same play-seats roster
with the person's seat marked human, and the host treats a roster with human
seats as human play too. Either launch enables `/ws` human connections and the
28 Hz human clock; ordinary league launches still run automated episodes as
fast as possible.

Hosted play stages `COGAME_PLAYER_SEATS_URI` as `coworld-play-seats/1`. Its
`seats` array has one entry per configured token, in slot order. Human entries
contain `slot` and `kind: "human"`. Policy entries contain `kind: "policy"`
plus the usual verified `file_uri`, `size_bytes`, `content_hash`, `log_uri`,
and optional `annotations_uri`. `player_status_uri` records policy seats only.
Policy tokens cannot take over a human connection, and humans can reconnect to
their own seat.

All policy files load before the match waits for humans. The match starts when
the human seats connect, without waiting for nonexistent policy containers.
On completion or policy compilation failure the process exits, allowing the
hosted-play collector to retain replay, results and private policy outputs.

Run the real mixed-match check with:

```bash
PUDGE_LEAGUE_BINARY=tmp/pwleague python3 tests/test_pw_basic_play.py
```

Publish this host and deploy the platform file-policy play support together.
The previously published `pudge-wars-basic:0.1.1` remains ranked-only. Point
the site's `COWORLD_ID` at the new release; `ARENA_WSS` remains a direct-host
override whose roster is configured on that host.

## League settings

[`league-settings.json`](league-settings.json) records the deployed settings
for the public 3v3 BASIC league using GotA's current competition conventions:

- `team_n`, two teams, contiguous `blocks`, distinct teammates.
- Rating-based `elo_softmax` matchmaking, temperature 100.
- OpenSkill Plackett-Luce, initial mu 25 and sigma 25/3.
- 24 episodes per round, 32-minute interval, separate filler policies.

The BASIC league variant is `league-3v3`: six seats, first to 30, at most 38,400
ticks. `duel-1v1` uses two seats, first to 10, at most 15,360 ticks. Pudge scoring
remains one point per winning seat, zero for a draw/loss. At the time limit, the
bank ahead on kills wins. GotA's XP scoring is specific to that game.

The existing league ID and Competition division were retained. The platform
reset archived 1,155 old rounds and cleared the Elo standings before OpenSkill
was enabled. Historical episode records remain accessible by ID. The seven
uploaded BASIC policies are available for selection, with Base as the owner's
champion and all seven available as unranked fillers. The first round completed
all 24 episodes. Other authors must submit new BASIC or neural package policies.

## Run local BASIC episodes without Docker

`scripts/run_episode.py` uses the same game-hosted loader and simulation as the
league. It accepts bundled names or custom source paths, and expands a trailing
`:COUNT` into independent seats. The first half of the roster is West; the
second half is East. Rosters of 2, 4, 6, 8 and 10 are supported.

```bash
python3 scripts/run_episode.py --list-policies

# Duel; defaults to 15,360 ticks and first to 10.
python3 scripts/run_episode.py base aggressive --seed 7

# Clone teams, 3v3; defaults to 38,400 ticks and first to 30.
python3 scripts/run_episode.py base:3 sniper:3 --seed 29

# Different policy in each seat, with a custom file.
python3 scripts/run_episode.py ./my-policy.bas support patient aggressive denier sniper

# Short development episode using an already built league host.
python3 scripts/run_episode.py challenger:2 support:2 \
  --binary tmp/pwleague --ticks 1024 --output tmp/my-episode
```

Bundled names are `base`, `aggressive`, `challenger`, `denier`, `patient`,
`sniper` `support` and `jev`; `.bas` suffixes also work. Custom paths resolve from
your shell's current directory. Raw BASIC and neural ZIPs are detected by content, regardless of filename
extension. Use `--llm` to enable local host-configured Jev/LLM calls. Old integer-only policies must replace integer `/`
expressions with `\` before using fractional values with integer host arguments.

Without `--binary`, the command compiles a fresh host using `NIM` or `nim` on
PATH; `--nim /path/to/nim` overrides it. Install the locked dependencies first.
No art, graphics, account, Docker daemon or hosted credits are needed.
`--ticks`, `--kill-goal`, `--seed` and `--timeout` control the episode.

Each run prints its artifact directory (by default a unique directory under
`tmp/episodes/`). It retains `results.json`, `replay.pwr`, `game.log`, private
`players/<slot>/log.txt` and optional annotations, `player_status.json`, the
runner config and seats documents, and `episode.json` with source/binary hashes.
Exact source snapshots live at `players/<slot>/file`. Explicit output directories
must be new or empty. Re-running a roster and seed reproduces results/replay bytes.

Exit codes distinguish success (0), input/build/host/timeout failures (1),
policy compilation failures (2), and completed games with disabled VMs (3).
Runtime-error episodes retain their results and replay for diagnosis. The host
is stopped after collection, including on timeout and interruption.

To watch or verify a saved replay:

```bash
# Watch with the native graphical client (requires art).
nim c -o:tmp/pw-native examples/pudge_wars/pw.nim
tmp/pw-native --replay tmp/my-episode/replay.pwr

# Headless verification of every recorded tick; no art required.
nim c -d:headless -o:tmp/pwheadless-local examples/pudge_wars/pw.nim
tmp/pwheadless-local --replay tmp/my-episode/replay.pwr
```

## Validate and publish

With Nim 2.2.10 and `nimby.lock` dependencies installed:

```bash
bash scripts/test_league.sh
# Optional graphical/native compatibility build:
nim c -o:tmp/pw-native examples/pudge_wars/pw.nim
```

The tests cover seat isolation, private logs/annotations, syntax/source/runtime
limits, all five roster sizes, native/file decision parity, hash-exact replays,
HTTP health/viewers, complete 3v3 episodes and output-failure ordering.

The package reuses upstream's certified simulator-37 replay viewer, pinned by
SHA-256. A test prevents publishing it with another simulator version. This
avoids rebuilding unchanged art/WASM for each league release. To publish a
changed renderer or simulator, rebuild using `tools/build_replay_viewer.sh`
with Emscripten and the art checkout, then certify and update the viewer pin.

With a running Docker daemon:

```bash
coworld build --project coworld --version 0.1.2 --output dist/coworld_manifest.json
coworld run-episode coworld/dist/coworld_manifest.json
coworld certify coworld/dist/coworld_manifest.json
coworld upload-coworld coworld/dist/coworld_manifest.json --wait-certification
coworld upload-policy --file coworld/players/base.bas --name pudge-basic-base
```

Submit file-policy versions to the migrated BASIC league. Compare
hosted outcomes and replay playback, verify the canonical game and league
settings by readback, then enable scheduling. The deploy workflow is manual
while this migration is being introduced and publishes `pudge-wars-basic`.
It does not modify league settings or promote policies.

Build the retained human/Docker package with
`coworld build --project coworld/platform-hosted --version <version>`.
Its Compose target uses `pwcoworld`; the BASIC package uses `pwleague` in a
Python-free game image with Linux LTO. Both include the same simulator.

The latest upstream [training bridge](TRAINING.md) is also included. It exposes
the hosted observation/action contract to Metta RL and post-training while
running the migrated BASIC opponents. The test script validates reset,
the 191-value/seven-head codec, teacher actions and terminal results for both
duel and 3v3 rosters.

## Local verification, 2026-10-09

`scripts/test_league.sh` covers nine Nim suites, six host integration tests,
the local episode command and the training bridge. The local matrix runs every
bundled policy in full duels on both banks, mixed 2v2/3v3/4v4/5v5 rosters,
custom paths, persistent strings/annotations, repeatability and failure cases.
Native graphics compile, and
the WASM target passes `nim check -d:emscripten`. Both package manifests pass
Coworld's Pydantic validation, and the league template passes its ladder model.

The ported bots also match the original VM's final hashes in 12 independent
1,024-tick comparisons: seeds 7 and 29, 1v1/3v3/5v5, and both bank assignments.
The existing combat-policy and economy-policy suites have 12 and 10 failing
strategy cases respectively; running the unchanged HEAD sources reproduces
exactly those failures. They are separate from the passing migration checks.

The 0.1.0 Linux/amd64 image passed local certification, hosted certification,
five hosted smoke episodes and its first 24-episode league round. Neural/Jev
validation passed on 0.1.1, including an actual hosted Jev response and
a hash-exact downloaded replay. [Deployment record](deployment.json) and
[release notes](../docs/hosted-release-basic-0.1.1-2026-10-09.md) retain the IDs.

Platform references:
[Player runtimes](https://github.com/Metta-AI/metta/blob/d92408b26a/packages/coworld/src/coworld/docs/PLAYER_RUNTIMES.md),
[player seats](https://github.com/Metta-AI/metta/blob/d92408b26a/packages/coworld/src/coworld/docs/artifacts/PLAYER_SEATS.md),
[GotA guide](https://github.com/Metta-AI/polyworld/blob/743f108091ca20b78f7e3fdc1a42f59ddb4ac795/coworld/gota/guide.md).
