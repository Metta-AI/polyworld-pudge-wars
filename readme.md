# PolyWorld — Pudge Wars

A self-contained slice of the **PolyWorld** engine plus **Pudge Wars**: a 3v3
river arena where two banks of butchers fight to a kill goal with a
skillshot meat hook, grapple, blink, and rot. Deterministic 32 Hz
simulation, BASIC bots on empty seats, and a LAN/browser lobby so friends
join from a native client or the browser (WASM).

Engine design: [docs/engine-design.md](docs/engine-design.md).

The league package now supports **Bassy BASIC file players**, using Polyworld's
pinned VM and GotA-style game-hosted execution. The migration includes private
seat logs/annotations and mixed-team OpenSkill league settings. See
[the migration guide](coworld/GAME_HOSTED_MIGRATION.md) for local tests, file
uploads and rollout. The separate `coworld/platform-hosted/` package retains
Docker players and human play. The 3v3 league runs `pudge-wars-basic:0.1.4` with mixed human/BASIC seats;
the sibling 1v1 league retains its existing runtime.

Run local BASIC episodes without Docker:

```bash
python3 scripts/run_episode.py base aggressive          # 1v1
python3 scripts/run_episode.py base:3 sniper:3 --seed 29 # 3v3
python3 scripts/run_episode.py ./my-policy.bas support  # custom policy
```

The runner builds the league host, runs to the kill goal or time limit, and
saves results, replay, policy snapshots and per-seat logs under `tmp/episodes/`.
Use `--binary tmp/pwleague` to reuse a build, `--ticks 1024` for a short episode,
or `--list-policies` to see the bundled policies. See the
[local episode guide](coworld/GAME_HOSTED_MIGRATION.md#run-local-basic-episodes-without-docker).

## What's here

| Path | What it is |
|---|---|
| `src/polyworld/` | Engine: sim helpers, renderer, HUD, audio, cameras, net, wasm recipe |
| `examples/pudge_wars/` | The game — sim, bots, graphics, hosting, netcode |
| `tests/test_pw_*.nim` | Headless tests (sim, maps, bots, replays, net, prediction, netsim) |
| `tests/bench_pw_netlag.nim` | Prediction-quality bench under latency/jitter |
| `scripts/setup.sh` | Installs Nimby, Nim 2.2.10, and the pinned packages |
| `nimby.lock` | Pinned Nim package commits |

Dependency order inside the game:

`content` → `replays` → `maps` → `sim` → `bots` → `game` → `graphics`

| File | Role |
|---|---|
| `content.nim` | Balance constants (tick rate, roster, kill goal, runes). No art. |
| `maps.nim` | Deterministic river/bank geometry |
| `sim.nim` | Authoritative world tick (fixed-point, float-free) |
| `bots.nim` | BASIC host API the `.bas` policies call |
| `game.nim` | CLI, match setup, headless runner |
| `human.nim` | Mouse/keyboard → the same `record`/`apply` path bots use |
| `graphics.nim` / `ui.nim` | Client only |
| `hosting.nim` | Embedded HTTP + WebSocket lobby |
| `netclient.nim` / `netpredict.nim` / `netproto.nim` | Follower: transport, client-side prediction + rollback, wire format |
| `netsim.nim` | Dev network-condition simulator (latency/jitter/loss) — see [NETSIM.md](examples/pudge_wars/NETSIM.md) |
| `players/*.bas` | Bot personas. Base and Rusher use the retained v16 Python strategy ported to BASIC. |

## Requirements

- macOS or Linux
- `curl`, `git`, a C compiler (`clang` on macOS, `gcc`/`clang` on Linux)
- OpenAL: system framework on macOS; `libopenal-dev` (Debian/Ubuntu) on Linux
- Optional, for browser clients: [Emscripten](https://emscripten.org) with `emcc` on `PATH`

## Setup

```bash
git clone git@github.com:Metta-AI/polyworld-pudge-wars.git
cd polyworld-pudge-wars
scripts/setup.sh
export PATH="$HOME/.nimby/nim/bin:$HOME/.local/bin:$PATH"
```

`scripts/setup.sh` installs [Nimby](https://github.com/treeform/nimby), Nim
**2.2.10**, and the packages in `nimby.lock` under `~/.nimby`, and writes a
gitignored `nim.cfg` so the compiler finds them. Put the `export PATH=…` line
in your shell profile.

**Art** lives in a sibling checkout of the assets repo:

```bash
cd ..
git clone https://github.com/Metta-AI/polyworld-data.git polyworld_data
cd polyworld-pudge-wars
```

The build looks for `../polyworld_data` (models, textures, fonts, sounds). A
missing model renders as a placeholder cube and never changes sim hashes, so
headless tests pass without it — only the graphical client needs it.

Confirm:

```bash
nim --version          # Nim Compiler Version 2.2.10
ls ../polyworld_data   # characters, terrain, themes, sounds, ...
```

## Play

Always from the repo root. First run compiles; later runs are faster.

For a browser 2v2 with a **live Jev coach and enemy-position likelihood map**, put
`TYPESAFE_API_KEY` in `.env.local`, run `./scripts/coach_demo.sh`, then open
**http://127.0.0.1:8787**. You play the human seat with live action cues,
strategy advice and estimates based only on visible sightings.
[Demo details](coaching/README.md).

To play alongside the Coworld Python policy with deliberate healing and
fishing spacing, run `uv run scripts/play_policy.py`. You control P1, with
Base v13 teammates on P2–P3 and Base v10 opponents on P4–P6. This runs the
current local game rules; [details and controls](coworld/player/README.md#play-alongside-this-policy-locally).
The commands below use the native BASIC bots.

```bash
# You vs a 5-bot field
nim r examples/pudge_wars/pw.nim --human

# Spectate a full bot lobby
nim r examples/pudge_wars/pw.nim

# Release binary
nim c -d:release -o:pw examples/pudge_wars/pw.nim
./pw --human
```

Headless (no window; CI and bot pacing):

```bash
nim c -d:release -d:headless -o:pwheadless examples/pudge_wars/pw.nim
./pwheadless --seed 7 --record /tmp/demo.pwr
nim r examples/pudge_wars/pw.nim --replay /tmp/demo.pwr
```

## Practice with a decision model, natively

The desktop app and `./pw --human --practice` run a coach on your seat with
no browser or server. A plate in the top-left corner shows the next move the
model recommends, why, the key to use, and the plan for the next few
exchanges. Low-health, hooked and incoming-hook cues are decided locally and
always win. `P` hides the plate; the trace keeps recording.

When the cue is a hook, the coach also marks **where to throw** in the
world, every frame: a ring the size of your hook head at the point where a
throw started now would meet the target, a stroke from where they stand to
that point showing the lead, and a thin line from you. The ring is green
when the throw would land (in range, clear line), ember when the line is
blocked or they are out of reach, and faint when the coach has not called
that target yet but your hook is ready and an enemy is open. The plate's
line under the key reads the same marker: "Throw at the marker, 3 tiles
ahead of them, lands in 0.9 s". The marker steps the real launch profile
(windup, acceleration to the speed cap) against the target's motion, so a
hooked enemy being reeled is led along the reel. Pilots aim at the same
point.

`--coach` picks the model behind the coach and the pilots:

| `--coach` | Endpoint | Key | Default model |
|---|---|---|---|
| `jev` (default) | `https://api.typesafe.ai/v1/systemone` | `typesafe.key` or `TYPESAFE_API_KEY` | `jev-latest` (`TYPESAFE_MODEL`) |
| `d1` | `https://api.liquid.ai/decisions/v1/systemone` | `liquid.key` or `LIQUID_API_KEY` | `d1` (`LIQUID_MODEL`) |
| `local` | `http://127.0.0.1:8765/v1/systemone` | none | whatever the sidecar serves |
| a URL | that base URL (loopback or one of the above hosts) | `COACH_API_KEY` | `--coach-model` |

Key files live in `~/Library/Application Support/Pudge Wars/`, one line each
(a repository `.env.local` also works from the checkout). Without a key the
coach gives local cues only and says so. `--coach-model NAME` overrides the
model name. The local sidecar is `d1/serve.py` in the Co-play Notes
repository: the open `LiquidAI/d1-3B`, or a fine-tune of it, on this machine.

### Pilots: the model plays a seat

`--pilot[:SLOT]` (repeatable) seats the decision model on a butcher. Every
second it is asked the same two Choice questions as the coach, and its answer
is executed through the human intent queue: a hook option becomes a
fine-aimed hook with a little lead, retreat and heal walk home, regroup
closes toward a teammate, reposition and scout move along the river lip,
dodge steps off a flying hook's line, upgrade spends the point. Without a
model (or a confident answer) the pilot takes the first local cue, so it
always plays. Pilots combine with `--human`, with each other, and with bots
on the remaining seats; `--human` alone keeps you as the local seat, pilots
alone spectate.

```bash
./pw --human --practice --coach local --pilot:1 --pilot:2   # the model as your teammates and coach
./pw --pilot:0 --pilot:1 --pilot:2 --coach d1 --seconds 120  # headless: D1 vs the stock bots
```

Headless matches wait for each pilot's answer, so self-play is paced by the
model, not the clock. The graphical client never blocks a frame: a pilot acts
when its answer lands.

### Traces

Every coached or piloted seat writes a decision trace under
`~/Library/Application Support/Pudge Wars/practice/<timestamp>/`
(`--practice-dir DIR` moves it; pilots write `pilot-<slot>/` inside):

| File | What it holds |
|---|---|
| `match.json` | Wall-clock start (`started_ms`), seat, actor (`human` or `pilot`), model, endpoint, map seed. |
| `samples.jsonl` | One record per one-second window: `at_ms`, the fog-clipped observation, the exact request sent (minus the observation) so the prompt can be re-rendered byte for byte, the eligible options, the model's choice with its probabilities and latency, the cue shown or executed, and the intent the seat actually issued. |
| `intents.jsonl` | Every drained intent for the seat with its tick, `at_ms` and engine acceptance. |
| `summary.json` | Reads, agreement with the model, hooks thrown and landed, kills, deaths, requests, failures, and the match result. |
| `replay.pwr` | The exact action tape for the whole match, so any later observation encoding can be re-simulated from it. |

Human intents come straight from the sim's drained queue, so a sample's
`human.id` is an exact decision, not an inference from video. Hooks and
rescues close a window at once; a walk-only window closes with its last walk
class (retreat, heal, regroup, scout, reposition); a quiet window closes as
`none`. For a pilot, `cue` is the decision it executed and agreement compares
that with the model's answer. The wall-clock stamps let Co-play Notes line
these windows up with spoken or typed coaching and turn a correction into a
training label; `d1/` in that repository builds the dataset, trains D1 and
serves it back to `--coach local`.

Headless contracts: `nim r -d:headless tests/test_pw_practice.nim`.

## Mac desktop app

Build a self-contained app with the native game, assets, and BASIC policies:

```bash
examples/pudge_wars/macos/build_app.sh
open "tmp/desktop/Pudge Wars.app"
```

Move the app into Applications or onto your Desktop. Opening it starts a 3v3
match with you on West and five BASIC bots, at fair difficulty, with the
practice coach on (see above for the key file). Extra flags pass through:
`open "tmp/desktop/Pudge Wars.app" --args --coach local --pilot:1`. It works offline
and does not need this checkout after building. Logs are saved to
`~/Library/Logs/Pudge Wars/game.log`.

## Controls

Live matches automatically run at **87.5% speed when a human plays**: 28
simulation ticks per real second instead of 32. Everyone in that match shares
the slower clock, including bots. Hooks, movement, cooldowns and the match
clock all slow together, giving you about 14% more reaction time. The pace stays
slow through disconnects until the next match. Bot-only matches and normal
replay playback retain their existing speed. Match limits are simulation time,
so a human match's wall-clock time limit is 8/7 of the displayed duration.

Native hosts and browser clients must both be rebuilt for this change (network
protocol 14). `host_party.sh` rebuilds the browser bundle when `emcc` is available.

For choppy native graphics on a laptop, try a smaller window with dynamic
shadows disabled. This changes rendering cost separately from the game clock:

```sh
SUN_SHADOWS=0 ./pw --human --windowSize 1280x800
# Or host the same lighter local game for friends:
SUN_SHADOWS=0 examples/pudge_wars/host_party.sh --human --name Aaron --windowSize 1280x800
```

The default players use the customized red and blue butcher. Preview and
compare all nine motion clips independently with `./char_viewer`; build and
controls are in [Butcher workshop](examples/pudge_wars/BUTCHER_WORKSHOP.md).

| Input | Action |
|---|---|
| Right click / WASD | Move |
| Q | Meat Hook (aim with cursor) |
| E | Grapple |
| F | Blink |
| R | Rot |
| X | Stop |
| 1–4 | Spend kill points on hook upgrades |
| G | Ping · F1 center · L follow · T take-over · M mute |
| F3 | Debug / fog overlay |
| F9 / F10 | Network debug panel / cycle the latency simulator preset |

`--keys FILE` rebinds with windy names, one `action = KeyName` per line.

## Host a match with friends

One person hosts; everyone else joins from a browser or a native `--join`.

```bash
examples/pudge_wars/host_party.sh --human --name Aaron
```

That builds `./pw`, builds the WASM bundle when `emcc` is on `PATH`, and
copies the lobby URL to the clipboard on macOS. In the host window, claim a
seat (1–6) and press **Enter** to start. Empty seats are bots; dropped humans
fall back to bot autopilot.

Native join:

```bash
./pw --join ws://192.168.1.10:8000/ws --name Ana --slot 3
```

See [examples/pudge_wars/playing_with_friends.md](examples/pudge_wars/playing_with_friends.md).

## Testing under latency (local)

The follower has a built-in network-condition simulator. Run a host, then
join with a preset to feel and measure high latency/jitter locally:

```bash
# terminal 1 — host with 5 bots, one open seat, auto-start
./pw --host --autostart --bot examples/pudge_wars/players/base.bas:5

# terminal 2 — join as a follower under a simulated 250 ms link
./pw --join ws://localhost:8000/ws --name LagTest --netsim poor
```

Presets: `local` (0 ms) · `good` (100 ms) · `poor` (250 ms) · `extreme`
(500 ms). In-game **F9** shows the debug panel (ping, FPS, packet
counters, rolling graph); **F10** cycles the preset. Full guide and the
measurement bench: [examples/pudge_wars/NETSIM.md](examples/pudge_wars/NETSIM.md).

Tests (headless, no window):

```bash
nim r tests/test_pw_sim.nim
nim r tests/test_pw_predict.nim     # client prediction + render smoothing
nim r tests/test_pw_netsim.nim      # latency/jitter/loss simulator
nim r tests/test_pw_pacing.nim     # human clock, prediction and reconnect pace
nim c -d:release -r tests/bench_pw_netlag.nim   # prediction quality vs latency
```

## License

MIT. See [LICENSE](LICENSE). Art under `polyworld_data/` may carry additional
notices next to the files.

Neural ZIP policies and Jev judgments are supported through the shared GotA
interfaces; see [inference setup and examples](coworld/INFERENCE.md).
# Agent policy development

Start with [COWORLD.md](COWORLD.md) for the BASIC runtime source map, relevant
documentation, and [policy development skill](skills/pudge-wars-policy/SKILL.md).
Hermes reads this guide from the selected Coworld's pinned source commit.
