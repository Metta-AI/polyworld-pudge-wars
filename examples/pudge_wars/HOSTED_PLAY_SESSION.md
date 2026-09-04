# Pudge Wars hosted play — session context for implementers

Read this entire file before writing code. This is the handoff from the 2026-09-01 design thread (Aaron Landy). Engine truth stays in **polyworld**. Coworld packaging, k8s , and Observatory APIs live in sibling **metta**. Do not rebase metta. Commits only when asked. Use bun on the website. Uploads: `uv run coworld --elevated` from metta (auth `aaronlan95@gmail.com`).

**Product:** https://pudgewars.com — one-click Play, humans vs **named policy versions**, native 3D WASM, 32 Hz feel via prediction/rollback. Softmax k8s runs the match. The site is a matchmaker, not a second orchestrator.

---

## Goal (done when)

A logged-in player on pudgewars.com hits **Play**, gets a XvX (or 1 human + 5 policies) in the **native WASM client** (same feel as `host_party.sh`), against **specific policies they picked** (or last/default roster). Input feels ~30 ms locally (prediction), host stays 32 Hz. Other humans can join a short queue keyed by that policy roster.

## Non-goals

- A new k8s Job type, lobby table, or human-proxy stack (play sessions already mix humans + policy pods).
- Iframing Observatory (`/observatory/v2/coworld-play/...`) as the product UI.
- `coworld play` locally as the product path (it **rejects** `CoworldHumanPlayerSpec`).
- Mixing humans into the **ranked** clone-team ladder (spec 0085). Hosted play is off-ladder.
- XP / `POST /v2/episode-requests` for this (policy-only).
- BASIC `.bas` bots in k8s (use uploaded Docker policies).
- Serving sim HTML from pudgewars.com (content-origin isolation). WASM **assets** on pudgewars.com; **WebSocket** to the API host / play proxy.
- Replacing LAN `host_party.sh` (keep it). LAN can stay a pure tape follower.

---

## Repos and layout

| Repo | Path | Role |
|------|------|------|
| polyworld | `/Users/aaln/experiments/softmax/polyworld` | Sim, `coworld_host.nim`, netproto, WASM, party host |
| metta | `/Users/aaln/experiments/softmax/metta` | Coworld CLI, play sessions, k8s dispatcher, Observatory API |

Pudge Wars Coworld package: `metta/packages/coworld/src/coworld/examples/pudgewars/`

Website (create): `polyworld/web/pudge-wars/` **or** a sibling Vercel project. Domain **pudgewars.com** (apex purchased). DNS: Cloudflare, account `aaron@thecompassmag.com` (wangler logged in), deploy on **softmax Vercel**.

---

## Live platform IDs (as of 2026-09-04)

| What | ID |
|------|-----|
| League | [Pudge Wars](https://softmax.com/observatory/v2?detail=league:league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0) `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0` |
| League seed | `lseed_44f5072a-3066-4542-9fbd-b52cfa2e225c` (`pudge-wars/ladder`, variant `league-3v3`) |
| Division | `div_471aedc1-00f7-41dd-971d-f0beff95a439` |
| Ladder | `team_pair` + **`team_layout: blocks`** (0–2 West, 3–5 East). Never interleaved. |
| Canonical coworld | `pudge-wars` **0.3.8** `cow_81fbce34-d950-49bb-af45-fdfa1468d202` (certified). League unlocked — follows canonical. Hook is 200 damage (~24% of 840 HP); a dump is not a one-chain kill. JSON player protocol is 1:1 with BASIC (`buy_upgrade` / `buy_power`, `rot` set, `accepted` echo, land-edge `play_west_max` / `play_east_min`). |
| Game image | `public.ecr.aws/q5f4m8t9/cogames@sha256:d716e33934ea5ffa3af6789b4167b90549d052195cb279c00921ac2e87311baa` |

**Starter policies (Aaron), league champions after upgrade:**

| Player | Policy | Notes |
|--------|--------|--------|
| Aaron `ply_630a768f-d623-44b2-80fa-36968d6fa75a` | `pudge-wars-rusher:v2` | `PUDGE_PERSONALITY=rusher` |
| Aaron's Optimizer Jr `ply_2357645a-143f-41b8-ad97-610c0d73f4e6` | `pudge-wars-camper:v3` | |
| a-aron `ply_cec02b42-a653-4253-be4b-602ba5acacc4` | `pudge-wars-idle:v3` | |
| Andre von Auto | `myasnik:v2` | Opponent to pick in the lobby |

Policy image run: `python -m coworld.examples.pudgewars.player.player`

**Player identity:** `upload-policy` stamps `player_id` from the active token. To submit as Optimizer Jr / a-aron, `coworld player use ply_...` then upload (no `--elevated` on player tokens). User token + `--player` cannot reassign a version already bound to Aaron.

API: `https://softmax.com/api` (`DEFAULT_SUBMIT_SERVER`). Observatory web: `https://softmax.com/observatory/...`

---

## Two runtimes (do not confuse)

### A. LAN party (quality bar)

```
examples/pudge_wars/host_party.sh --human --name Aaron
```

- `./pw --host` → [`hosting.nim`](hosting.nim) + [`lobby.html`](lobby.html)
- `/` lobby, `/ws` (JSON lobby **or** binary netproto), `/play/*` Emscripten bundle
- Unclaimed seats = BASIC `base.bas` on all six seats
- WASM: `nim c -d:emscripten examples/pudge_wars/pw.nim` → `emscripten/pw.{html,js,wasm,data}`
- Join URL: `/play/pw.html?join=1&name=&token=` — [`webinputs.js`](../../src/polyworld/webinputs.js) turns `join=1` into `--join ws(s)://<same-host>/ws`. **CDN hosting must pass an absolute `wss://...` in `join=`.**
- Drop → BASIC autopilot. Host window is the server (Enter to start).

### B. Coworld k8s (policies + JSON)

- Game: [`coworld_host.nim`](coworld_host.nim) (`pwcoworld`). JSON `/player`, `/global`, 2D `/client/player` (click-to-walk — **not** the product client).
- All seats `humanSlots` (no BASIC). Policies send `{walk_to, hook_to, halt, ping}`. Sticky `{}`.
- Fog: home bank always visible; enemy bank needs ally sight. Coords = **tiles**. Hook range ~60. Walking cannot cross the river.
- Replay: `.pwr` via `COGAME_SAVE_REPLAY_URI`. Observatory viewer is **replay-only** webshell (`?replay=`), gzip public copies without `Content-Encoding`.
- Tick rate **32**. Map 128×128. River west/east ~53/75. Spawn pads are seeded: lane shuffle + inland jitter, east mirrored (west X 18–36, east = 128−X). Shop stays at (22, 64) / (106, 64).

**Hosted play session (product k8s path):**

```
POST /v2/coworlds/play/session  { "coworld_id": "cow_..." }
PUT  /v2/coworlds/play/session/{ps}/config
PUT  /v2/coworlds/play/session/{ps}/seat/{slot}
     { "kind": "open" } | { "kind": "closed" } | { "kind": "policy", "policy_version_id": "<uuid>" }
POST /v2/coworlds/play/session/{ps}/join
POST /v2/coworlds/play/session/{ps}/start
POST /v2/coworlds/play/session/{ps}/terminate
GET/WS /v2/coworlds/play/session/{ps}/proxy/{path}
```

CLI smoke: `uv run coworld --elevated hosted-game create|join` (from metta).

K8s: Job `coworld-play-<id>` = game + [`coworld_play_proxy.py`](../../../metta/app_backend/src/metta/app_backend/job_runner/coworld_play_proxy.py) (k8s API proxy **drops query strings**; sidecar reattaches). Policy pods: `COWORLD_PLAYER_WS_URL=ws://{job}:8080/player?slot=&token=`. **No EpisodeRequest, no XP, no Observatory featured replay.**

**League lobbies** (`/v2/lobbies`): full episode + recording + `human-player-proxy`. Create is **team-only**. Ranked ladder stays bot-only (0085). Later slice only.

Local `coworld play` / `run_coworld_episode`: human seats raise `ValueError`.

---

## Locked product decisions

1. **No new hosted lobby runtime.** Matchmaker creates **play sessions** only.
2. **Site:** pudgewars.com. CORS: add `https://pudgewars.com` and `https://www.pudgewars.com` to [`APP_ORIGINS`](../../../metta/app_backend/src/metta/app_backend/app_origins.py). Do **not** serve game documents from that origin.
3. **Primary UX:** one **Play** button. Opponent chips (last used / default roster). 6-seat grid = Advanced.
4. **Per-seat policies:** every bot seat has an explicit `policy_version_id` before start. Same policy may occupy multiple seats. Picker: your versions, league champions (if assign API allows non-owned — `start` uses `enforce_owner=False`), or paste UUID.
5. **Queue:** site Redis/Postgres `spec_hash → open ps_`. Not a Metta API.
6. **Human client:** native 3D WASM (`pw.nim` emscripten), not 2D canvas.
7. **Hosted WASM netcode:** prediction + rollback (LAN may stay follower).
8. **Auth:** Softmax GitHub; return to pudgewars.com. “My bots” = policy versions.

---

## Match queue (make Play trivial)

**Match spec**

```
coworld_id, variant_id
team: west | east | any
human_seats: 1..5          # default 1
bots: [policy_version_id]  # remaining seats, bank order
fill_timeout_ms: 10000
```

`spec_hash` = SHA-256 of `(coworld, variant, team, human_seats, bot ids in seat order)`.

**Default roster (editable, persist per user):** you West; East `myasnik:v2` ×3 if assignable, else rusher/camper/idle. If solo, fill your two ally seats with rusher/camper (or last pick).

**`POST /api/match/play` (Next.js server, uses Softmax token):**

1. `human_seats == 1`: create session, `PUT` all bot seats, join, start. `{ status: "ready" }`. **No wait.**
2. Else: `SET NX spec_hash → ps_id`. First writer creates lobby session, PUTs bots, leaves human seats open. Others `join`. Poll/SSE until full **or** 10s → leftover human seats become copies of the first bot id, then start. Always get a game.
3. Leave: if last human and not started, terminate + delete hash.
4. Join 409 (full) → new bucket for that spec.

After start: poll until `running` / proxy healthz, then WASM:

`https://pudgewars.com/play/pw.html?join=wss://<STATS>/v2/coworlds/play/session/{ps}/proxy/ws&name=&token=&slot=`

(Exact proxy path: confirm against `coworld_play_proxy_url` / JoinResponse `target_url`. Today `target_url` is 2D `/client/player`; **replace** with WASM join, do not use that HTML.)

Show “Found match — starting arena…” during k8s spin-up.

---

## Engine work

### Gate 0 — WASM hash (do first)

Observatory featured matches: `REPLAY HASH MISMATCH AT TICK 230` from [`tapes.nim`](../../src/polyworld/tapes.nim). Live lockstep and rollback use the same check. A miss is a **desync**.

- Native `pw --replay` vs WASM replay-viewer on the same 0.2.x `.pwr`.
- Replay artifact = webshell (`?replay=`, gzip). Live client = `?join=`. Keep them separate; **both** must hash-match native.
- Known history: 0.2.0 viewer wrote gzip bytes without gunzip; 0.2.1+ gunzips. R.241-style mismatches after that are remaining determinism/boot bugs.

### Dual-protocol `coworld_host` (0.3.x game image)

Merge [`hosting.nim`](hosting.nim) netproto into [`coworld_host.nim`](coworld_host.nim):

| Path | Who |
|------|-----|
| `/player?slot=&token=` JSON | Policy pods (unchanged) |
| `/ws` binary netproto | WASM humans |
| `/healthz` | k8s |
| `/global` | spectator (optional) |

- Auto-start from `config.json` tokens (no host window / Enter).
- Never stall 32 Hz for a late browser.
- Policy seats: no BASIC; sticky last JSON order.
- Human disconnect: sticky last order + reconnect via token, **or** fallback policy/BASIC. Do not pause the sim.
- Do not serve 26 MB WASM from the pod. Assets on pudgewars.com.

Tick-stamp intents: client sends **wanted tick**. If too old/future (window ~2–4 ticks), apply on **current tick** (snap). Confirmed tape + hash = existing `NmTicks`.

### Prediction + rollback (WASM seats only)

Colleague spec (implement this):

- Server sends **confirmed commands + hash**, not snapshots (`NmTicks` already).
- Client **rollback world**: advance only on verified host ticks; hash mismatch = desync.
- Client **prediction world**: ahead; **local** intents apply immediately. Assume other humans issued **nothing** until confirmed. Bots appear only when they are on the host tape.
- On host update: copy rollback → replay confirmed + still-unconfirmed **local** intents. Match → no snap. Else snap.
- Policy pods: no prediction (in-cluster, 0 RTT to host).

Feel: click → pixels same frame; confirm 1–2 ticks later at 30–60 ms RTT. Stretch ~30 ms. If play-proxy p50 RTT > ~40 ms, add **direct WS ingress** to the same play-session Service (not a new Job type).

LAN `--host` may remain a pure follower.

`NetProtocolVersion` is currently **4** (`IntentRot`). Bump if the intent wire gains `wantedTick`.

---

## Website (pudgewars.com)

- Next.js App Router, bun, shadcn, sonner, Tailwind. Standard.js-ish: 2 space, single quotes, no semicolons.
- Softmax login (GitHub) → store token server-side for play-session calls.
- Home: opponent chips + **Play**. Advanced: 6-seat editor + invite `ps_` link.
- Queue state: Upstash Redis or Postgres (Vercel is serverless).
- WASM static: `/play/pw.*` from the emscripten live build (not the replay webshell).

Metta: `APP_ORIGINS` + OAuth redirect allowlist for apex + www.

---

## Delivery order (do not skip)

1. **Fix WASM hash mismatch** — native vs WASM replay on one tape; prove live `--join` vs `./pw --host` for a full match.
2. **Dual-protocol coworld_host** — JSON `/player` + netproto `/ws`; auto-start; 0.3.x image.
3. **Certify + upload** `pudge-wars` 0.3.x (`--no-wait-hosted-smoke` if GET episode-requests is 405). Point league canonical after cert. Smoke: `coworld hosted-game` with 1 human token + 5 explicit policy seats (2D canvas OK for this smoke only).
4. **Prediction + rollback** on WASM; tick-stamped intents; RTT log on `/ws`.
5. **CDN join** from pudgewars.com `?join=wss://...`.
6. **Site:** Play (instant solo) + spec-hashed queue + policy chips.
7. Advanced 6-seat lobby.

---

## Key source files

**Polyworld**

- `examples/pudge_wars/coworld_host.nim` — k8s game host
- `examples/pudge_wars/hosting.nim` / `lobby.html` / `netproto.nim` / `netclient.nim` — party + lockstep
- `examples/pudge_wars/human.nim` — intents
- `examples/pudge_wars/webshell.html` — **replay** boot only
- `src/polyworld/webinputs.js` — `join` / `replay` query
- `src/polyworld/tapes.nim` — hash mismatch text
- `examples/pudge_wars/playing_with_friends.md` — LAN runbook
- `examples/pudge_wars/human_play.md` — old “no prediction” for LAN; hosted WASM **overrides** that

**Metta**

- `packages/coworld/src/coworld/examples/pudgewars/` — Dockerfile, player, manifest
- `packages/coworld/src/coworld/examples/pudgewars/player/player.py` — JSON rusher/camper/idle (blind-hook)
- `app_backend/src/metta/app_backend/routes/coworld_routes.py` — play session HTTP
- `app_backend/src/metta/app_backend/job_runner/coworld_play.py` — k8s play Job
- `app_backend/src/metta/app_backend/v2/routes/lobbies.py` — league lobbies (later)
- `web/softmax.com/src/app/(observatory)/observatory/v2/coworld-play/[sessionId]/LobbyClient.tsx` — existing seat picker (copy UX, not the product shell)
- `docs/specs/0085-pudge-wars-coworld.md` — ranked humans out of scope
- `docs/specs/0074-coworld-league-lobbies.md`

---

## Commands

```bash
# LAN quality bar
examples/pudge_wars/host_party.sh --human --name Aaron

# WASM live client
nim c -d:emscripten examples/pudge_wars/pw.nim

# Coworld (from metta)
cd ../metta
uv run coworld --elevated hosted-game --help
uv run coworld --elevated upload-coworld ...   # after 0.3.x host build
# Player overlay (linux/amd64) if only player.py changes:
# FROM existing ECR digest; COPY player/; upload-policy with --secret-env PUDGE_PERSONALITY=...
```

Nim Docker nightlies tarball (existing Dockerfile):  
`https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz`

---

## Protocol cheat sheet

**JSON policy** (`player_protocol_spec.md`): obs every tick; action `{ walk_to:[x,y], hook_to:[x,y], halt, ping }`. Empty = sticky.

**Netproto:** `NmHello`, `NmPickSlot`, `NmIntent`, `NmLobby`, `NmSlotGrant`, `NmStart`, `NmTicks` (tape + hashes), `NmIntentResult`, `NmBye`, `NmPing`/`NmPong`. Binary Flatty, wasm `flatty64`.

---

## If stuck

- Featured match hash error on Observatory ≠ live party (party works). Fix WASM determinism before building pudgewars.com.
- `--elevated` cannot be used with `ply_` tokens.
- Policy version player binding is at upload time, not submit time.
- Hosted play will not show on the league featured reel; that is expected.
