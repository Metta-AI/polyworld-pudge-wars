# Pudge Wars 0.3.21 hosted release

- Source: `7d8ab8fce0c9a7d82993402051a0fecdcc0487f4`, including the browser movement-jitter fix, plus the WASM launcher and initial `/global` waiting-state changes in this branch.
- Compiler: Nim 2.2.10. Simulator: 37.
- Canonical Coworld: `cow_01b9f22d-5255-4d22-a111-af7ed5861fac`.
- Public site: https://pudge-wars-site-theta.vercel.app
- Immutable client: https://pudge-wars-site-theta.vercel.app/play/bundles/16ee23ead8a7ca64/pw.html
- WASM SHA-256: `c472f5535ff18107924b90bf95fa95d9fcde844035f65569cdb92d8dd6afe743`.
- Vercel deployment: `dpl_DJGPPot9VBMDvM6na7LA7y6S37xW`; production `COWORLD_ID` points at the Coworld above.

## Verification

All ten local certification checks, five hosted smoke episodes, and all ten hosted certification checks passed. The production API confirmed this version is canonical.

The movement regression replayed 3,456 display frames: the old predictor moved backward 888 times; the fixed predictor moved backward zero times. Four browser-launcher tests and the host startup regression passed. The site passed its 11 library tests and production build.

Clicking Play on the public site loaded the new 3D WASM client and advanced beyond 4,190 ticks without JavaScript errors or hash mismatches.

## Observatory episode lobbies

Episode lobbies (`lby_...`) use a different backend proxy from hosted-play sessions (`ps_...`). Their proxy needed two platform fixes: allow the game-owned binary `/ws` endpoint, and avoid requiring hosted-play artifact settings in the episode sidecar. [Metta PR #23216](https://app.graphite.dev/github/pr/Metta-AI/metta/23216) contains these fixes, 218 passing focused tests, and 514 passing repository lint/type checks. It merged as `97bb09f5adbbd121fe58e45e75585a88393a5d07`; production deployment `35032756125` succeeded.

Local Observatory verification used the full Postgres/Floci/OrbStack stack at port offset 400. The fixed pod reached 3/3 Ready, and two human clients connected through the episode job proxy. The embedded game advanced beyond 4,032 ticks. The exact WASM assets were mirrored locally because Chromium blocks a public HTTPS page from opening a local WebSocket.

Production lobby `lby_4b39eef1-2184-4bb9-a79f-a8cadd41bc0d` loaded the 3D WASM arena through the live episode proxy. Job `5e2b17f3-9384-436f-a0db-90214b301b2f` reported all containers ready, human seat 0 joined, and both players connected. Two browser movement commands reached the server at ticks 1,086 and 1,482; screenshots confirmed movement. Browser verification used the local Observatory frontend authenticated against production, with the game iframe served directly from the production Observatory API. No WASM, WebSocket, or hash-mismatch errors appeared.

The 3,200-tick match completed successfully with no episode error. Observatory transitioned to Replay and stored `https://softmax-public.s3.amazonaws.com/replays/5e2b17f3-9384-436f-a0db-90214b301b2f.replay`.

An already-failed lobby cannot be restarted; create a fresh lobby to use the deployed fixes.

## Source integration

The game-side changes merged as `d1f6d7c9a06c3a064fff1fd710e45703b62c77b8` ([PR #2](https://app.graphite.dev/github/pr/Metta-AI/polyworld-pudge-wars/2)). Its automatic follow-up release did not upload: the remote art repository lacks the four `characters/butcher/butcher_game*` GLB/profile assets. The successful local 0.3.21 build contains these assets; its canonical registry entry and Vercel deployment remain live.
