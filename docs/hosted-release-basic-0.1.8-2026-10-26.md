# Pudge Wars restoration — 0.1.8 (2026-10-26)

The existing game is named **Pudge Wars** again. The western river-and-lasso game, **hookem**, is developed separately. This release restores the original Pudge Wars name and artwork; gameplay, policies, ratings, game IDs and ranked lobby rules are unchanged.

## Release

- Source restoration: `d5e5833` (main).
- Coworld: `cow_c23845f0-444f-4d2f-864f-5764c58eda4a`, version `0.1.8`.
- Manifest: `sha256:56a5003d34079d19334912c5fb66c682ad45998ae3ea7263d666d467d240b3cb`.
- Browser bundle: `3115a0709de5c7e300a201a742f9b83c238c9086ef98189c3ddc52bc30f45223`.
- Hosted image: `public.ecr.aws/q5f4m8t9/cogames@sha256:01caef1ddfcf33cc83d1be502a2f5cdb0c41d78d3046a3b1e25592240e996bc0`.
- Simulator 38, wire protocol 14.

The engine and browser files reuse the exact certified 0.1.6 artifacts. That release contains the current gameplay and compact dark HUD before the Fresh Meat rename; rebuilding a different gameplay binary is unnecessary for restoring its name. The author manifest updates the version and points at the same immutable hosted image. All three downloaded browser engine files were checked against their SHA-256 hashes.

The five hosted smoke episodes passed. At this receipt, full certification job `210dd272-e1a3-4b03-979d-6ef284563543` remains queued by the platform, with no failed step. One retry returned the same queued job. Do not describe 0.1.8 as canonical until the certification endpoint reports success.

## Published surfaces

- Website: https://pudge-wars-site-theta.vercel.app
- Production deployment: `dpl_CiuWfpJ5gCbaRKwHZ5RWcvAxqK8k` (Ready).
- Production `COWORLD_ID`: `cow_c23845f0-444f-4d2f-864f-5764c58eda4a`.
- Game display-name override: `Pudge Wars`, game `game_066b85e8-55ed-4141-afd4-5e3e5bf00b0d`.
- Ranked league name: `Pudge Wars`, seed `lseed_44f5072a-3066-4542-9fbd-b52cfa2e225c`; league ID stays `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0`.
- Store revision `spr_def31085-47f9-457b-b787-4f9c58c45fe6` is published, using the original Pudge Wars cover for icon and hero.
- IDE source: `Metta-AI/coplay`, commit `d2e0592`, branch `aaln/platform-voice-proxy`.
- Signed IDE installed at `/Applications/Softmax IDEa.app`; game manifest has `name: Pudge Wars`, `cover: pudge-wars-logo.webp`, and `cover_fit: contain`.

## Verification

- 32 targeted IDE unit tests passed.
- Packaged IDE boots the verified restored WASM runtime into live gameplay; smoke passed in 10.5 seconds. The check used Electron console state events, since mutating `Module.print` after Emscripten boot does not replace its captured output function.
- Website production build passed; production is Ready; home page contains Pudge Wars and original artwork with no Fresh Meat labels; Open Graph image returns HTTP 200.
- Existing technical aliases, historical release artifacts, coaching policies, and concurrent unrelated workspace edits are preserved.
