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

Episode lobbies (`lby_...`) use a different backend proxy from hosted-play sessions (`ps_...`). Their proxy needs two platform fixes: allow the game-owned binary `/ws` endpoint, and avoid requiring hosted-play artifact settings in the episode sidecar. The separate Metta branch `aaln/pudge-observatory-wasm` contains these fixes and 218 passing tests.

Local Observatory verification used the full Postgres/Floci/OrbStack stack at port offset 400. The fixed pod reached 3/3 Ready, and two human clients connected through the episode job proxy. The embedded game advanced beyond 4,032 ticks. The exact WASM assets were mirrored locally because Chromium blocks a public HTTPS page from opening a local WebSocket.

Production Observatory verification remains dependent on deploying that Metta change. An already-failed lobby cannot be restarted; create a fresh lobby after deployment.
