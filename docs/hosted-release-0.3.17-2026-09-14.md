# Pudge Wars 0.3.17 hosted release — 2026-09-14

Verified at 2026-09-14T18:11:29Z.

`pudge-wars:0.3.17` is canonical. Both league seeds (`Pudge Wars` 3v3 and
`Pudge Wars 1v1`) bind the `pudge-wars` name, so they resolve to this
version. Aaron's active 3v3 entry remains `pudge-wars-rusher:v14`.

## Released behavior

- Simulator stays 37. Gameplay is the same 0.3.16 ruleset (1,200 HP,
  fountain Blink, double-speed Lightning, charged-hook fire trails).
- Replay tapes are format 5: `Setup.seatLabels` carries policy/human names
  so WASM nameplates can show `myasnik-bas:v5` instead of `P1`. Format 4
  tapes still load. Observatory static viewers that only pass `?replay=`
  still need `label=` query params for old episodes; that wiring is a
  Metta Observatory change, not this image.
- Nameplates on replay skip fog and are 280px wide.

## Immutable artifacts

- Coworld: `cow_d1aad864-85bf-4028-b9c9-34d4e1a0c044`.
- Manifest: `sha256:8cb03df9b4ee1793e1609a3c2c81fbcd981f29cfd98b9b3e8f412884d231ba8c`.
- Game image: `public.ecr.aws/q5f4m8t9/cogames@sha256:8a64dd801c51defa20c33ea4d3878dfc3a19f4cbcf7119b896d378e0df71e395`.
- WASM bundle: `sha256:a9a9a8cb18c9fe984ebe4aab71a650bf18f799850d8f8a368a4000942adc52d4`.
- Local replay from executable certification is simulator 37
  (`POLYWORLDREPLAY` header `gameVersion=37`).
- Viewer `sim-version.json` is `{"game":"pudge_wars","simVersion":37}`.
- Source URL pin: `2ee71dffe3689fc85d0349e04fd097c89a2a9e9a`.

## Verification

- Native replay, bot, net, and rune suites passed.
- Local executable certification passed all ten steps against the hydrated
  0.3.17 manifest.
- Hosted executable certification passed all ten steps
  (`matriculate` through `supporting-roles`) at 2026-09-14T18:11:29Z.
- Hosted smoke promotion set this version canonical. Smoke episode-request
  IDs: `ereq_790d9457-fbf1-445f-b433-4ef80d6c8160`,
  `ereq_81b3442c-3d42-4762-b26b-ac53297e9991`,
  `ereq_8833883f-7ffb-4d40-9482-7158b135b937`,
  `ereq_a9711a83-fa5b-43ca-9744-563f62dd3e18`,
  `ereq_aaa82f21-00a9-4414-9b94-04798df942dc`.

## League settings

No league settings were changed. Recurring 1v1 rounds remain paused. Future
automatic champion promotion remains `never`.
