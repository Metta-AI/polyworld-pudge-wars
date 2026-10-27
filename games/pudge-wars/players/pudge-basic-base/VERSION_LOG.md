
## v1 — 2026-10-09T20:23:14.208490+00:00

- Policy version: `695e980a-5d8d-43cd-b852-5631ce314431`
- Change: migrate the base baseline to game-hosted Bassy BASIC, with explicit integer division.
- Runtime: raw BASIC file, SHA-256 `abc4ac1b80d8bbc21f4e52f4f2d6c4c2b55d2d37cda92acfa2ed8a0e5470b1a8`; pinned Bassy `a02e6dd5889310b13d21725c891bde8d01539f08`.
- Validation: unvalidated on hosted runner; complete local duels on both banks passed.

Hosted validation: participated as entrant or filler in the completed 24-episode BASIC migration round `round_422030b6-6aef-4fd1-9c3f-f3c55aff74a7`.

## v2 — 2026-10-14T23:38:03.310936+00:00

- Policy version: `2e7567f3-e290-4fe2-aa68-775dfab623d5`
- Change: transfer retained Python v16/E06b as one BASIC package: coordinated support, stable lanes, full-range hooks, fountain rejection and persistent CurveHook.
- Runtime: raw BASIC; SHA-256 `f38ba2929c91f985d73afa5a54ec3e5da582e5e71122069cbc2847b19fc48511`; unchanged `pudge-wars-basic:0.1.1`.
- Validation: hosted unvalidated; locally validated in 96/96 fresh confirmation wins and 48/48 broad-field checks, all replays verified. Behavioral and loader tests passed.
- Evidence: `coaching/policies/basic-rusher/results.json`; upload record: `coaching/policies/basic-rusher/deployment/upload.json`.

Hosted runtime validation passed: `xreq_0f99543d-3738-46ad-934e-ffa3355c1c07`, episode `ereq_34dc7f33-169f-41f1-b00d-601f1cf14769`, 2,048 ticks on canonical BASIC 0.1.1. Three candidate seats ran cleanly and threw 71 hooks. All 26,881 replay actions verified. Validation state: validated for deployment; hosted competitive strength unmeasured.

### Submission decision — 2026-10-14T23:40:14.886451+00:00

- User authorization: “deploy new policy”, following disclosure of the completed local evidence.
- Submitted `pudge-basic-base:v2` to existing 3v3 league `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0` as A-aron (`ply_cec02b42-a653-4253-be4b-602ba5acacc4`).
- Submission: `sub_d9f462a7-c03a-4b95-9a97-b11e172c4f9f`; auto-champion: always; validation state: submitted.
- Evidence: 96/96 fresh local confirmation wins, mean margin +23.896, seed-block 95% CI [23.313, 24.490]; 48/48 stock-opponent checks; hosted runtime/replay smoke passed. This does not establish hosted competitive improvement.
- Rollback: promote prior Base v1 membership `lpm_23d2f18c-6133-4139-b5fd-cac3ed7afa52` and verify champion readback. No game, filler pool, schedule or 1v1 league changes.

Verified 2026-10-14T23:41:19.775513+00:00: submission placed; membership `lpm_9bcc9096-a938-4748-a801-4da4b7a05855` is active, `competing`, and `is_champion=true`. A separate player-scoped champions-only read returned v2 as the sole champion. Release evidence: `coaching/policies/basic-rusher/deployment/release.json`.

## v3 — 2026-10-27T23:43:32.836345+00:00

- Policy version: `11b5f918-cb84-4291-b14b-a8b3e676bc82`; source commit `9b0ced7`.
- Change: measure visible hook speed and predict follow-up reel interception; preserve casting and movement priorities.
- Runtime: raw BASIC, SHA-256 `2bf33639da719663a785f4599aed9ec890c4a983d94dbfc5d90ef4de9d452f0d` on canonical Pudge Wars `0.1.9`.
- Local evidence: 498 versus 437 double-hook kills, 26/48 wins; overall match advantage remains inconclusive.
- Hosted runtime smoke: 2,048 ticks, three clean candidate seats; every tick and all 17,271 replay actions verified. This is not hosted competitive evidence.
- User explicitly requested league deployment. Submission `sub_85e14781-97c0-4efd-8dd8-8012e78a090e`.
- Independent readback: A-aron's active, competing champion, membership `lpm_08379cc1-3b09-429e-96bf-932ed8151e6c`.
- Rollback: promote v2 membership `lpm_9bcc9096-a938-4748-a801-4da4b7a05855` and verify readback.
- Evidence: `coaching/policies/double-hook-20261027/deployment/release.json`. Game, filler policies and other players were not changed.
