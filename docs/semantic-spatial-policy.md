# Coaching away crowding and occupied movement routes

The coaching request was to stop clustering and walking into teammates near the wall. The intervention targets the generated semantic controller. The screenshot did not include a seed, replay or controller identity; the wall scenes below are authored reproductions of the failure class, not reconstructions of that exact frame.

## Cause and semantic change

The previous policy computes different fishing lanes, then sends every agent to the same upcoming rune's y coordinate for the eight seconds before a drop. Drops appear at y=16 or y=111, beside the arena's north/south boundary. Lane ranks also depend on living teammates, and ward approach can overwrite a fishing destination. None of these movement choices checks whether a living player blocks the route.

The new ontology distinguishes a stable teammate role, an assigned lane, the owner of a shared objective, an occupied movement corridor, and a temporary detour. These are grounded in the existing fog-filtered observations. No hidden simulator state is supplied to a controller.

The [textual IR](../coaching/policies/executable/spatial.policy.md) adds these executable preferences:

```text
DO remember_roster
...
DO formation_positioning(bank_margin=16, lane_spacing=12, rune_window=256)
DO clear_occupied_route(clearance=7, lookahead=12)
```

`remember_roster` keeps roles ordered by spawn-lane position and identity, including dead teammates. `formation_positioning` replaces the old tactical-movement/ward composition: emergencies and shop travel retain their priority, while routine fishing and ward approach use distinct lanes. Exactly one healthy, unhooked teammate on our bank covers the announced rune. Other lanes stay separated from that reservation. Normal lane centers stay within y=24..104 and juke by at most two tiles.

`clear_occupied_route` checks the next twelve tiles of routine own-bank travel. When a visible body blocks the route, it selects an eight-tile waypoint with seven tiles of clearance. Its conservative bank bounds prevent an outward detour into the rim or river. It holds a safe waypoint for up to 24 ticks to avoid switching sides every frame. It permits moving away from an already-close body and holds if no safe route is available. It does not override hook dodges, rescue commitments, low-health retreats, river escape, melee or caught-enemy approaches. Terrain navigation remains the engine's job; this is local body avoidance, not a new terrain pathfinder.

This required **new grounded execution skills**, not a lane-spacing parameter tweak. I authored their contracts and implementations, generated the [symbolic controller](../coaching/policies/spatial_generated.py) from the IR, extracted the controller's supported executable AST back to IR, and regenerated it. This remains a bounded compiler with explicit skills, not unrestricted natural-language-to-code compilation.

## Evaluation protocol

The complete-game comparison uses the actual native engine, 3v3 teams, a 30-kill goal, and a 38,400-tick limit. Each arm plays the same frozen original Python reference on both banks for every seed. Each seat receives its own fog-filtered observation and acts every tick. This models local policy behavior without network latency or a human teammate.

The first iteration uses two development seeds (9231701–9231702), twelve games across the parent, formation-only ablation and full 24-tile formation. Its six fresh confirmation seeds (9231801–9231806) reveal a score tradeoff, so that version is not selected. The second iteration changes only lane_spacing, comparing 12 and 16 on two new development seeds (9231901–9231902), then freezes spacing 12 before six further confirmation seeds (9232001–9232006). There are 72 complete research games across these two iterations; interrupted runtime-debug attempts and short smoke/scenario games are separate. Banks are paired within each seed; each confirmation interval bootstraps six independent seed averages, not individual ticks or seats.

Spatial metrics are sampled every eight ticks. Eligible samples have a living, unhooked agent on its own bank with a living teammate visible. Crowding is nearest-teammate distance below ten tiles. Contact is below 5.7 tiles, slightly above the native body's 5.2-tile diameter. Occupied-route orders point within 5.2 tiles of a teammate ahead in the next ten tiles. Wall samples are within eight tiles of the outer arena boundary. Stalling is less than half a tile of progress over eight ticks despite a continuing distant walking order. Contact and stalling are observation-based proxies, not authoritative collision callbacks; combat windup can contribute to the latter.

Every executed generated-controller decision and complete memory state is compared with the controller regenerated from extracted IR. Inputs, native runner, source snapshots, decision samples and per-game results are retained. Earlier interrupted development attempts are marked `EXCLUDED.json`; their scores are not mixed into confirmation.

## Results

Final measured results are recorded in [semantic-spatial-results.json](semantic-spatial-results.json) and the table generated below.

| Measure | Original generated policy | Final spatial policy |
|---|---:|---:|
| Crowded samples (<10 tiles) | 32.6% | 18.3% |
| Contact samples (<5.7 tiles) | 18.5% | 3.2% |
| Walking orders through an occupied corridor | 16.9% | 2.9% |
| Contact while near the outer wall | 44.4% | 2.8% |
| Stalling while near the outer wall | 10.3% | 3.1% |
| Wins against the frozen reference | 5/12 | 7/12 |
| Mean kill margin | -0.75 | +5.25 |

The final correction reduces contact by **82.7%**, occupied-route orders by **83.0%**, and near-wall contact by **93.6%**, relative to the original generated controller. Crowding falls by 14.25 percentage points (95% seed-bootstrap interval: −17.27 to −11.35 points). The mean kill-margin difference is +6.0, but its interval is **[−0.08, +12.25]**. These six seeds support the movement correction; they do not yet establish a statistically reliable increase in playing strength. All 24 final-comparison games reached the kill goal.

The wider first candidate had lower crowding (35.4% → 7.0%) but won only 5/12 versus the control's 8/12. That suggested excessive separation might harm coordinated conversion; it is an interpretation, not a measured causal mechanism. Returning lane_spacing to 12 preserves useful proximity while retaining objective ownership and body avoidance. The 12-tile development arm won 4/4 against the reference versus 2/4 for the control; the 16-tile alternative won 1/4. The final fresh confirmation above is the evidence used for the narrower version, not those development scores.

**Round trip:** 916,233 executed decisions and complete memory states matched across generated and extracted/regenerated controllers in the final comparison (433,080 for the new policy); zero mismatches. The two wall scenes add 1,536 checks. In both native wall scenes, the original policy recorded four contact samples; the detouring policy recorded zero, and reached its goal nine ticks (0.28125 seconds) later. The original also eventually got around the blockers, so these scenes demonstrate avoided contact rather than an otherwise permanent deadlock.

**Runtime:** the final controller's median per-game throughput is 0.517× the direct Python reference; 4/12 runs fall below 0.5 and remain explicitly flagged in the raw report. This is a remaining runtime cost, not a claim that every runtime guard passed. A separate comparison on identical archived observations with the same generated-policy tracing interface, alternating execution order and measuring process CPU time, gives **0.597× the generated parent's throughput**. Neither measurement is hidden. A full native repeat after removing a redundant trace-dictionary copy produced the identical action-trajectory SHA-256; 1,101 archived observations also matched actions, memory and traces. Formation caching and movement composition avoid redundant work, but further controller-runtime optimization remains worthwhile.

**Status:** use `support_spatial_12` for the spatial-coaching demonstration. The historical kill-margin-based automatic promotion gate does not promote it because the interval includes zero. This preserves the distinction between compliance with coaching and a proven stronger overall policy. All 80 coaching/symbolic unit tests pass; a v2 campaign can initialize, round-trip and complete a short native audit.


## How to inspect and play

The new live launcher selects this exact generated IR controller for your teammates and uses the existing native host and WASM renderer. From the repository root, with the existing coaching environment built:

```sh
tmp/coaching/venv/bin/python -m coaching.symbolic.play --port 8790
```

Open `http://127.0.0.1:8790/`. This starts a 3v3 game with you and two generated agents. `/policy` serves the exact IR snapshot, `/generated.py` serves the generated source, and `/api/state` exposes match progress and errors. Add `--autopilot` to spectate an all-agent game. The existing voice-coaching demo and native BASIC bot retain their separate controller selection; this command explicitly activates the generated semantic policy.

The launcher completed a 256-tick native 3v3 smoke match with no driver errors, and the state, IR, generated-source and game-page endpoints returned HTTP 200. This is a transport/engine smoke check, not a completed human usability study or a visual browser assertion.

Reproduce the semantic and native checks:

```sh
python3 -m unittest discover -s tests -p 'test_symbolic*.py' -q
tmp/coaching/venv/bin/python -m unittest discover -s tests -p 'test_coaching*.py' -q
nim c -d:release --hints:off --warnings:off -o:tmp/coaching/spatial_match coaching/symbolic/native_match.nim
python3 -m coaching.symbolic.spatial_scenes --out tmp/coaching/my-wall-reproduction
python3 -m coaching.symbolic.spatial_eval --out tmp/coaching/my-spatial-reproduction --phase confirmation --baseline tmp/coaching/spatial-compact-confirmation-20260910/reference.py --seeds 9232001 9232002 9232003 9232004 9232005 9232006
```

Reusing these seeds and that frozen reference reproduces this experiment; future model selection needs fresh seeds. New runs default to freezing the current `coworld/player/base.py`, so the evaluator does not depend on a prior temporary run directory.

## What the next loop inherits

The v1 execution library remains byte-identical, so the old control still runs. The v2 binding hash covers both the frozen v1 file and the extension. Compiler extraction recognizes both versions, campaign initialization records the actual binding version, and search can edit the new formation parameters. Existing campaigns must be imported into a new campaign after research-code changes; their implementation pins are not silently updated.

The retained regression tests cover unique rune ownership, separation, stable lanes through death/absence, detours on both banks, moving away from a close body, protected emergency behavior, equivalence of the optimized movement composition, both directions of code/IR translation, and future search proposals. Native evaluation now records spatial metrics for subsequent candidates. The historical score-based promotion gate still optimizes kill margin; use the spatial measurements and contracts when judging a coaching intervention rather than treating a win-rate change as proof that the human instruction landed.

The next discriminating experiment is mixed human/agent co-play with the human deliberately holding a lane or blocking a path, across more opponents. A stable lane role currently uses spawn position; it does not yet infer a human's changing tactical intention.
