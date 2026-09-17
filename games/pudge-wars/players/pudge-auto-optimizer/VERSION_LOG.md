# pudge-auto-optimizer — version log

Player: Aaron's Optimizer (`ply_594ec24d-d7f3-4370-a000-468354ec41c9`). Campaign
records live in [`../../auto-optimizer/`](../../auto-optimizer/). Every upload
gets a row here before anything else happens to it.

| Version | Policy version id | Uploaded (UTC) | One attributable change | Build | Verdict |
| --- | --- | --- | --- | --- | --- |
| v1 | `a7afee99-e56f-40eb-ae64-6bc08f83ae71` | 2026-09-17T02:04:50Z | Baseline: repo default Python policy, `coworld/player` @ `d1f6d7c`, Dockerfile defaults (`rusher`, arm `combined`); no behavior change | Docker linux/amd64 `pudge-auto-optimizer:iter0`, image `sha256:83e56ab8…`, run `python -m coworld.examples.pudgewars.player.player` | pending: smoke + gate counterfactual vs `pudge-wars-rusher:v16` |
