# PolyWorld — Pudge Wars

A self-contained slice of the **PolyWorld** engine plus **Pudge Wars**: a 3v3
river arena where two banks of butchers fight to a kill goal with a
skillshot meat hook, grapple, blink, and rot. Deterministic 32 Hz
simulation, BASIC bots on empty seats, and a LAN/browser lobby so friends
join from a native client or the browser (WASM).

Engine design: [docs/engine-design.md](docs/engine-design.md).

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
| `players/*.bas` | Bot personas. `base.bas` documents the whole host API. |

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

## Controls

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
nim c -d:release -r tests/bench_pw_netlag.nim   # prediction quality vs latency
```

## License

MIT. See [LICENSE](LICENSE). Art under `polyworld_data/` may carry additional
notices next to the files.
