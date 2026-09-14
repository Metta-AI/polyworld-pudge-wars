# Hosted Base rusher evaluation

Updated 2026-09-10T04:33:27+00:00.

This is the historical v9→v10 evaluation. V10 was promoted to both leagues
after this study. The subsequent [healing/spacing campaign](../../games/pudge-wars/experiments/2026-09-09-support-spacing.md)
promoted v13 for 3v3; v10 remains the active duel champion. The 1v1 league's
recurring rounds remain paused.

Policy version: `6d9aa2b5-5a1c-4c06-9c77-6f2265b43848`. Canonical game: `pudge-wars:0.3.13` / `cow_8ef8b994-1cd2-4ebb-b452-22ea8a46404e`. All comparisons use the normal fog, tick rate, kill goal and time limit.

## Leaderboard opponents at the original request time

60/60 episodes completed; 0 failed. Ten episodes per request, one request per starting bank for each opponent. Three copies of each policy form a team. Versions were pinned from the leaderboard and active champion memberships at request time.

| Leader at request time | Policy | Completed | Wins | Losses | Draws | Mean kills, v10–opponent |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| #1 Andre von Auto | `myasnik-bas:v5` | 20 | 11 | 9 | 0 | 26.05–26.05 |
| #2 richard | `co-gas-pudge-blind-hook-richard:v2` | 20 | 17 | 3 | 0 | 28.95–21.70 |
| #3 relh | `co-gas-pudge-blind-hook-relhalpha:v2` | 20 | 17 | 3 | 0 | 29.40–20.95 |

Twenty episodes per opponent are a limited sample. These results measure this candidate against these fixed versions, not a proven ranking across the whole league. The hosted `myasnik-bas:v5` label is not evidence that its source is identical to the local `myasnik_v75.bas` file.

| Opponent | v10 west request | v10 east request |
| --- | --- | --- |
| Andre von Auto | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_c7ff6c32-2327-4b10-be0f-a43bb295cb21) | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_95371900-ca30-47dd-8c9f-54b791da49d6) |
| richard | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_0db1d027-14a7-480a-bccd-326cd74ce842) | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_5be75450-8544-4f10-9f3b-231aea91c686) |
| relh | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_ddd169fa-48c5-40dc-a3e5-b28daaf4527e) | [10 episodes](https://softmax.com/observatory/v2?tab=experience-requests&detail=experience-request:xreq_0f843c02-2da2-4e78-81ea-2cfd52d10851) |

## Previous rusher comparison

Actual uploaded v9: `5f6a9c4d-1ece-4ae9-b534-1a51aed50c7a`. Each mode has a four-game paired-seed pilot plus two ten-game batches on opposite banks. That gives 24 games per mode; the batch seeds are independently generated.

| Mode | Wins | Losses | Draws | Mean kills, v10–v9 |
| --- | ---: | ---: | ---: | --- |
| 3v3 | 24 | 0 | 0 | 30.00–14.04 |
| 1v1 | 15 | 5 | 4 | 6.17–4.75 |

## Replays and checks

- `duels/coworld-base-l4r3452l/watch-v10-vs-myasnik.command`: actual hosted 30–23 win. West/P1–P3 are Myasnik v5; east/P4–P6 are Base v10, with policy nameplates. The matching released engine successfully replayed all 212,163 actions.
- `duels/coworld-base-l4r3452l/watch-hosted-v10-win.command`: actual hosted 30–9 win over v9; all 117,456 actions replayed successfully.
- 25 focused policy checks passed. Six copies of the exact uploaded image completed the downloaded live fixture without player exceptions.
- Full JSON results, request bodies, version IDs, source hashes and membership readbacks are in `duels/coworld-base-l4r3452l/`. `hosted-results.json` retains every completed episode's kills, hook counts, seed and terminal tick.

The live game uses old paid, short-range wards. The port enables free far-bank wards only when the newer protocol exposes `ward_restock`. See [strategy and reproduction](README.md) and the [game-hosted migration assessment](../GAME_HOSTED_MIGRATION.md).
