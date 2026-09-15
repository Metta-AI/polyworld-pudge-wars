# Hosted Pudge Wars browser client

Softmax owns the lobby and proxy. The game owns `/client/player` and
`/client/global`: both open the WASM renderer named by
`game.runnable.env.PUDGE_WARS_CLIENT_URL`. The launcher converts the public
`address=` WebSocket from `/player` or `/global` to `/ws`, preserving the proxy
prefix and passing the player slot and token to the native Hello handshake.

Pin that URL to a content-hashed bundle directory on the public production
site: `/play/bundles/<hash>/pw.html`. Keep published bundle directories when
deploying new versions, so old running hosts keep their matching client.
Vercel deployment-specific URLs are protected by login even for production
builds; use the public production alias with a versioned path.
The large browser assets are served by Vercel; they do not traverse Softmax's
hosted client asset proxy, which excludes Emscripten `.data` and `.html` files.
JSON policies continue using `/player`; replay-mode `/client/global` retains
its JSON replay viewer. The registered static WASM bundle serves Observatory
replays.

Observatory lobbies (`lby_...`) run episode jobs, separately from the site's
hosted-play sessions (`ps_...`). Their job proxy must permit the binary `/ws`
endpoint. The runner probes `/global` before exposing the browser client, so
the host sends its initial waiting state immediately on connection, before
all human seats join. Test both flows when releasing.

## Release

1. Build with Nim **2.2.10**, matching `coworld/Dockerfile`:

   ```sh
   bash coworld/tools/build_replay_viewer.sh "$PWD/tmp/browser-bundle"
   ```

2. Copy `pw.html`, `pw.js`, `pw.wasm`, `pw.data`, `cover.webp`, `boot-scene.js`,
   `recap-overlay.js`, and `sim-version.json` from
   `examples/pudge_wars/emscripten/` into `../pudge-wars-site/public/play/`.
3. Copy those eight files into `public/play/bundles/<content-hash>/` as well,
   then build and deploy the site. Set `PUDGE_WARS_CLIENT_URL` in
   `coworld/coworld_manifest_template.json` to that public versioned path,
   then build, certify, and upload the next Coworld version.
4. Update the site's production `COWORLD_ID` to the newly certified Coworld ID
   and redeploy it. This environment variable takes an ID, not the game name.
5. Verify a new Softmax lobby's player and spectator links load the 3D game,
   and use the site's Play button to verify a live match without hash mismatches.

`node --test tests/test_pw_browser_launcher.mjs` checks hosted and direct
join URLs, seat zero, escaped credentials, and spectators.

`PUDGE_HOST_BINARY=/path/to/pwcoworld python tests/test_pw_coworld_startup.py`
checks readiness without connected players and tick advancement after joining.
