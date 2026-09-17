# pudge-auto-optimizer — version log

Player: Aaron's Optimizer (`ply_594ec24d-d7f3-4370-a000-468354ec41c9`). Campaign
records live in [`../../auto-optimizer/`](../../auto-optimizer/). Every upload
gets a row here before anything else happens to it.

| Version | Policy version id | Uploaded (UTC) | One attributable change | Build | Verdict |
| --- | --- | --- | --- | --- | --- |
| v1 | `a7afee99-e56f-40eb-ae64-6bc08f83ae71` | 2026-09-17T02:04:50Z | Baseline: repo default Python policy, `coworld/player` @ `d1f6d7c`, Dockerfile defaults (`rusher`, arm `combined`); no behavior change | Docker linux/amd64 `pudge-auto-optimizer:iter0`, image `sha256:83e56ab8…`, run `python -m coworld.examples.pudgewars.player.player` | pending: smoke `xreq_8e48fa28` (top-3 field XP), then directional n=40 on the same protocol; counterfactual evals are disabled for this league |
| v2 | `7ddf93a5-82f3-4bf4-be0b-0f50d9bef0a0` | 2026-09-17T02:17:38Z | Collision-aware hook threat: enemy flying hooks within 22 tiles only count as a threat if their estimated heading closes on us and passes within 8 tiles (`BasePolicy.collision_threat`); adds `threat_class`/`dodge_blink` trace events. Experiment [`2026-09-17-collision-threat`](../../experiments/2026-09-17-collision-threat.md) | Docker linux/amd64 `pudge-auto-optimizer:iter1`, image `sha256:e2f81828…`, same run command; uploaded without `--tag` (bookkeeping lives here) | pending: smoke n=3 (events must appear), directional n=40 vs v1 same window |
