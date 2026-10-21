# Pudge Wars 0.3.19 — hosted WASM browser play

`pudge-wars:0.3.19` is canonical and certified. The game-owned player and
spectator entry pages now launch the actual WASM game through the standalone
site's hosted-play session (`ps_...`) flow. The Observatory episode lobby
(`lby_...`) flow was not covered by this release's live checks. It additionally
requires an initial waiting-state message on `/global` and permission to proxy
`/ws` through the episode job route.

## Artifacts

- Coworld: `cow_891efc56-67d7-4e95-b028-63773dfeb683`.
- Manifest: `sha256:f4146c810e869dda13afb01ce478811247170c99fb6a65104ba1388b32b869c1`.
- Registered game image: `img_4f2cd514-6bf6-4fdf-905e-0ecea7b3338e`.
- Registered replay bundle: `sha256:516b7b703535bda855931ac16d43d7c7e520f3501979758502d5a3a196eec4b8`.
- Browser client: <https://pudge-wars-site-theta.vercel.app/play/bundles/e1081f99c0836b65/pw.html>.
- WASM SHA-256: `b4207b7052d0637f3e78fc2772076bc8ad39307ef6be0b16fa0f45a4a293ee48`.
- Data SHA-256: `47acc814054626081666e4eacab9abb88c33ea226a5386873d9b4fd9bcec0d17`.
- Simulator 37, compiled with Nim 2.2.10 for the host and browser.

The source image was built from `debc1968584b02d343dd8033549b6a779a897629`
plus the working-tree launcher changes. No Git commit or push was performed.
The standalone site's production `COWORLD_ID` points to this Coworld.

## Verification

- Three browser launcher tests passed: hosted player proxy and credentials,
  spectator without a seat, and direct local URLs including seat zero.
- Native Coworld protocol and recording/follower determinism suites passed.
- Standalone site: production build and 11 existing tests passed.
- All ten local executable certification steps passed for the game image;
  the final manifest also passed upload's local certification.
- All ten hosted certification steps passed; all five hosted smoke episodes
  completed, followed by canonical promotion.
- Browser checks loaded a live 3D match through the standalone Play button.
- Both actual player and spectator target URLs returned by Softmax for a
  fresh 0.3.19 hosted-play session redirected to the public versioned WASM client. Both
  rendered the live match, with advancing ticks and no browser errors or
  simulation hash mismatches.

Vercel protects deployment-specific URLs with login. Version 0.3.19 replaces
0.3.18's deployment URL with a public content-hashed path. Keep that directory
when updating the site. See [hosted browser release instructions](hosted-browser-client.md).
Existing lobbies retain the game version they were created with; create a
new lobby to use this release.
