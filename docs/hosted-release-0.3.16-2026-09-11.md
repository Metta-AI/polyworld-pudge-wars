# Pudge Wars 0.3.16 hosted release — 2026-09-11

Verified at 2026-09-11T22:03:39.523354+00:00.

`pudge-wars:0.3.16` is canonical. Both league seeds (`Pudge Wars` 3v3 and
`Pudge Wars 1v1`) bind the `pudge-wars` name, so they resolve to this
version. Aaron's active 3v3 entry remains `pudge-wars-rusher:v14`.

## Released behavior

- Simulator 37. Lightning throws fly and reel at double hook speed.
- Fire trails come from the charged hook only (not walking or blink), pulse
  hostile damage, and light the thrower's team through fog.
- Base HP stays 1,200. Blink can still cross the fountain pinch onto clear
  land; landing on the fountain stays blocked.
- The game image and WASM viewer share simulator version 37. JSON
  observations expose `game_version`.

## Immutable artifacts

- Coworld: `cow_548c1ac0-e9af-483e-bc7c-7048991ad267`.
- Manifest: `sha256:1f8d90e5ba853d247fad0ea24f96bd28941de373de23af68437fd459f301e790`.
- Game image: `public.ecr.aws/q5f4m8t9/cogames@sha256:7d6dc6a3a98442330203c4e55f5023e758d2f3a1ec80e22f882a507b526561ee`.
- WASM bundle: `sha256:abd0ef2c1f108a6a8fccd98f69d5bd94dbeb9a73d26bd8ab0a9c63873449ae4d`.
- Local replay from executable certification is simulator 37
  (`POLYWORLDREPLAY` header `gameVersion=37`).
- Viewer `sim-version.json` is `{"game":"pudge_wars","simVersion":37}`.
- Source URL pin: `3e1af664b4021884e1521edbea838dba71002524`. The linux/amd64
  game image and WASM bundle include the uncommitted working tree on top of
  that commit; no Git commit or push was performed for this release.

## Verification

- Native sim, replay, and coworld protocol suites passed. Python coworld
  policy checks passed (42 tests).
- Local executable certification passed all ten steps against the hydrated
  0.3.16 manifest.
- Hosted executable certification passed all ten steps
  (`matriculate` through `supporting-roles`) at 2026-09-11T22:03:39Z.
- Hosted smoke promotion set this version canonical. The upload CLI's
  episode-request poll still returns HTTP 405, so smoke episode IDs were
  confirmed through the canonical flag and certification transcript rather
  than the broken list endpoint.

## League settings

No league settings were changed. Recurring 1v1 rounds remain paused. Future
automatic champion promotion remains `never`.
