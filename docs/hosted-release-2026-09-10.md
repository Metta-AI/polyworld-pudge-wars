# Pudge Wars hosted release and round budget — 2026-09-10

Verified at 2026-09-10T21:07:20.300375+00:00.

This 0.3.14 release was superseded by [0.3.15](hosted-release-0.3.15-2026-09-10.md), which adds 1,200 HP and fountain Blink crossings. The budget change below remains in effect.

## Coworld release

Uploaded and certified `pudge-wars:0.3.14` (`cow_861aafdb-159d-46a9-b950-253b6990a072`). It is canonical and the Pudge Wars 3v3 league resolves to it.

- Manifest: `sha256:c71f7b13867bbed60e9cf977d07dd0f160c7f1f2fee7f9d81db65ef336cc0e5f`.
- WASM replay bundle: `sha256:9cfe5f6a4c3260cbc7a2c4e1a408ac650e4d562903ea712c60b383a9f2388a6f`.
- Source snapshot based on `0767d18ab8a86925a8c5c937702143be1c62778c` plus the local changes recorded in `duels/game-release-4ftm4ag1/build-inputs.json`.
- Twelve native game/protocol suites passed. Local and hosted Coworld certification passed all ten steps.
- Raw and gzip replays loaded in Chromium without JavaScript, WebGL, or simulation hash errors during the recorded smoke checks.
- The viewer includes its loading/recap scripts and the corrected shadow shader vertex attribute locations.
- Detailed build, upload, certification, browser, and registry evidence is in `duels/game-release-4ftm4ag1/`.

## League episode reduction

League: `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0`.

Changed only `settings.ladder.scheduler.min_episodes_per_entrant` from unset to `4` through the authenticated league settings API. A separate GET verified the saved settings and effective ladder configuration.

The existing `team_pair` scheduler switches from exhaustive mirrored matchups to balanced participation when this field is set. With ten entrants, this plans `ceil(10 × 4 / 2) = 20` episodes, four appearances per policy. The previous completed round, `round_c9eb3cab-38c5-409b-a09b-d9037da5b81e` (#1043), contained 90 episodes. The change reduces episode volume per round by 77.8% at the current roster size. It scales with roster size; it is not a fixed 20-episode cap.

The 3v3 block team layout, rankings, cadence, retries, and league memberships were preserved. The shared Pudge Wars daily budget remains $200. New round plans use this setting; existing plans and incurred spending are unaffected. No extra paid verification round was triggered.

The before/request/response/readback evidence is saved as `duels/game-release-4ftm4ag1/pudge-budget-*.json`.
