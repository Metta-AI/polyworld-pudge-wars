# Playing Fresh Meat with your team

One person hosts on their machine; everyone else joins from a browser —
no installs. The host runs the authoritative simulation, players claim
seats on a lobby page, and any seat a human is not holding is played by
a bot. 3v3, first to the kill goal wins.

## What you need

- **Host**: this repo, a Nim toolchain, and (once, for the browser
  client) an [Emscripten SDK](https://emscripten.org) active in the
  shell (`emcc` on the PATH).
- **Players**: a modern browser on the same network as the host.
  Nothing else.

## One-time setup (host)

From the repo root:

```bash
# Native binary (the host runs this)
nim c -d:release -o:pw examples/pudge_wars/pw.nim

# Browser client bundle (what friends' browsers download, ~26 MB)
nim c -d:emscripten examples/pudge_wars/pw.nim
```

The second command fills `examples/pudge_wars/emscripten/` with
`pw.html`, `pw.wasm`, `pw.js`, and `pw.data`. The host serves that
bundle automatically; rebuild it whenever the game code changes.

## Start a lobby

The quickest way is the party script, which fills every unclaimed seat
with `base.bas`, uses party-friendly defaults (first to 30, fair-handicap
bots), builds anything missing, and copies the invite link to your
clipboard:

```bash
examples/pudge_wars/host_party.sh
examples/pudge_wars/host_party.sh --human --name Aaron   # with a seat for you
```

Any flag you pass overrides the script's defaults. Or host by hand
from the repo root (data and bot paths are relative to it):

```bash
./pw --host
```

The host prints the address to share:

```
host: keeping this Mac awake while the lobby is up
host: lobby open at http://192.168.1.211:8000/
host: native clients join with --join ws://<that address>/ws
```

Useful hosting flags:

| Flag | Meaning | Default |
|---|---|---|
| `--port N` | Lobby/game port | 8000 |
| `--name NAME` | Your display name | Host |
| `--human` or `--human:N` | Pre-claim seat N (0–5) for yourself | none |
| `--killGoal N` | Kills to win | 30 |
| `--minutes N` | Match time limit | 20 |
| `--runes N` | River rune spawn interval in seconds | 20 |
| `--difficulty easy\|fair\|pro` | Bot handicap preset | pro |
| `--seed N` | Map seed | 2026 |
| `--autostart` | Skip the lobby; match runs immediately and people grab bot seats mid-game | off |

The host window stays open for the whole session — it *is* the server.
On macOS it holds the machine and display awake automatically while the
lobby is up.

## Invite the team

Send everyone the printed URL (the lobby page has a **COPY INVITE
LINK** button). On the page each player:

1. Types their name.
2. Clicks a seat — red seats are West bank, blue are East. Taken seats
   show who holds them.
3. Waits. The page preloads the game in the background ("ARENA READY —
   ENTRY IS INSTANT" when done).

Seats are sticky: a refresh, tab crash, or brief disconnect keeps your
claim, and reopening the page puts you back in it.

## Start the match

In the **host window** (not the browser):

| Key | Action |
|---|---|
| 1–6 | Claim that seat for yourself |
| 0 | Release your seat and spectate |
| Enter | Start the match |
| R | Rematch on the end screen (same arena, everyone comes along) |

On Enter, every claimed browser tab switches into the game
automatically. Unclaimed seats are bots.

## Playing

Genre-standard controls (rebindable via `--keys FILE`, one
`action = KeyName` per line, e.g. `hook = KeyD`):

| Input | Action |
|---|---|
| Right click | Move; on an enemy: attack |
| Q | Meat Hook (aim with cursor; `--quickcast` throws instantly) |
| S | Stop |
| 1–4 | Buy upgrades (damage / distance / speed / radius) |
| G | Ping the map for your team — bots read pings too |
| L / AUTO chip | Lock camera on your butcher (on by default; pan to look around) |
| F1 | Snap to your butcher and re-lock auto camera |
| Y / DIR chip | Director camera: auto-follow hooks, fights, and kills |
| Hold C + move pointer / two-finger | Pan camera (trackpad grab; tap C still places a wall) |
| Arrow keys | Pan camera (unlocks auto) |
| - / = | Zoom out / in |
| MMB drag, edge scroll (fullscreen only), minimap click | Pan camera (unlocks auto) |
| T | Hover any butcher and press T to take its seat over (or release yours) |
| M | Mute |

Grab the runes drifting down the river — haste, double damage, regen,
big hook, lightning, bounty — by walking into them or hooking them.
Lightning doubles hook speed, paints a fire trail your team can see
through fog, zaps a circle when the hook lands, and shocks the other
thrower if the chains clash.

### Getting help from the default bots

Press **G** over a spot to ask for cover. For the next three seconds,
the closest available bot covers that call; the others keep their lanes.
A river or enemy-bank call brings the responder to your team's safe
bank, not into the water. Immediate dodges, retreating, and rescues take
priority over a rally.

Bots avoid offensive throws through nearby teammates. They still try to
rescue someone on an enemy chain or a swimmer at 60% health or less.
If you are healthy and deliberately wading, they leave you alone:
ping your own position to ask for a pull. A rescue already being attempted
by another teammate is left to that teammate.

These behaviors belong to `players/base.bas`; custom policies need to
opt into the new helpers. Hook collision and human aiming are unchanged,
so late movement and ricochets can still catch allies. Bot acknowledgments
are captured in diagnostic logs, not displayed as team chat.

See [the teammate test notes](TEAMMATE_TESTS.md) for checks and match results.

The default Base also fights from farther inland, saves Blink for defense
and river escape, and prioritizes hook distance then speed upgrades. It
uses short hooks in close fights and approaches an allied catch from the
safe bank. See [the combat evaluation](BASE_POLICY_EVALUATION.md) for the
measured improvement against Myasnik and remaining limitations. Restart
the host to load an updated BASIC policy; no native rebuild is needed
for a policy-only change.

## Leaving, dropping, rejoining

- **Drop or close mid-match**: your butcher instantly falls back to bot
  autopilot; the match never stalls.
- **Rejoin**: reload the page — your seat token rides the URL, so you
  land back in your seat and control returns. If the game tab dies, the
  in-game banner says exactly that: reload to rejoin.
- **Late joiners** can claim any bot seat from the lobby page while the
  match runs; they fast-forward the match history and go live in
  seconds. Spectators just click **WATCH LIVE**.
- Opening your play link in a second window moves the seat there; the
  old window is booted cleanly (so don't share *your* play URL — share
  the lobby link).

## Native client (optional)

Anyone with the repo can join windowed-native instead of in a browser:

```bash
./pw --join ws://192.168.1.211:8000/ws --name Ana --slot 3
```

`--slot` is 1–6; omit it (or pick a taken seat) to spectate, then use
the lobby page or T-takeover to get a seat.

## Beyond the LAN

The lobby binds all interfaces, so remote friends work too:

- Easiest: a mesh VPN like Tailscale — share `http://<tailscale-ip>:8000/`.
- Or forward TCP port 8000 on your router and share your public IP.

Lockstep tolerates internet latency fine (commands land next tick after
they arrive), but hosts on Wi-Fi with players across an ocean will feel
the input delay grow with round-trip time.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Friends can't load the page | Same network? macOS firewall may prompt to allow `pw` incoming connections — accept it. Test the printed URL on the host's own browser first. |
| Loading screen says "WAITING FOR THE HOST TO START" | The match hasn't started — press Enter in the host window. |
| "CONNECTION TO HOST LOST - RELOAD THE PAGE TO REJOIN" | Auto-reconnect gave up (host process quit, session ended, or 20 failed retries). Restart the host if it's LAN; for hosted play wait for a new session. A reload with the same token still rejoins if the host is up. |
| Joining fails with "the host accepted the connection but never answered" | The host's game window is stalled (machine asleep before v4, or the window is closing). Restart the host. |
| Browser shows an error on the loading screen | It's the real crash reason — fix or report it, then reload. Stale bundles fix themselves: the server ETags every file. |
| Seat shows AWAY | That player disconnected. Before the start anyone may click to take the seat; mid-match it's reserved for their reconnect. |
