# Coaching demonstration verification — September 9, 2026

The local semantic-edit → candidate → review → activation loop works for the supported reference-generated policies. The complete voice-to-policy system is not verified: a fresh browser WebRTC setup attempt was rejected for exhausted OpenAI credits. These tests do not establish stronger gameplay or reliable model interpretation of coaching.

## Failure found and repaired

The running server reported `attempted relative import with no known parent package`. Its two opponent modules failed to import the new sibling `base.py`; the native host log showed `starting with 1/4 players`. The UI could subsequently report a live match despite the missing opponents.

`coaching.server.load_opponent` now loads each opponent under the `coworld.player` package with a unique module name. This resolves sibling imports and preserves independent opponent memory. A regression test checks dependency loading and state isolation. No opponent policy behavior was changed.

## Results

| Check | Result | Evidence and limit |
|---|---|---|
| Python regression suite | 45 passed | Includes the opponent-loading regression, policy contracts, semantic feedback, stale generation rejection and asynchronous tool dispatch. |
| Actual browser and native match | 12 workflow checks passed | Chromium loaded the WASM arena; native log confirmed 4/4 connected players. Keyboard input was exercised and human movement observed. No uncaught browser errors. |
| Belief revision and activation | Passed | Revising exposure risk preserved the active policy until trial. The reference candidate changed retreat from 35% to 50%, passed its contracts and activated at native tick 681. |
| Encouragement, frame challenge, export and undo | Passed | Encouragement preserved belief/policy hashes; the frame proposal remained `needs_grounding`; export retained contextual feedback; undo restored the earlier rules and threshold. |
| Browser match behavior | Inconclusive for the intervention | Across 262 sampled observations over 1,284 ticks, Loom stayed at full health. No movement decision distinguished the two thresholds. |
| Scripted-teammate combat match | Runtime agreement passed; intervention inconclusive | Across 2,398 observations, generated-policy decisions matched the recorded live trace. The engine reported one accepted Loom hook. Low health occurred during river escape, which took movement priority under both policies; there were zero movement interventions. |
| Controlled native low-health intervention | Passed | Identical real simulator observations at 40% health produced different commands and trajectories, detailed below. |
| Live OpenAI Realtime connection | Blocked | The actual browser SDP request returned the application's quota error: “The OpenAI account has no available API credits/quota.” The UI displayed it. No speech recognition, model-generated policy or live model interruption test completed. |
| Competitive improvement / autoresearch | Not established | No paired held-out win-rate experiment or autonomous candidate optimization was run. |

## Controlled native intervention

This is a deliberately constructed scenario, separate from the ordinary matches. The native simulator initialized the same 2v2 roster and map, placed Loom at tile `(40, 64)`, and set its health to 40%. Its real `observation()` output was passed to each saved policy. The resulting command went through the native host's `applyAction`, followed by 24 actual physics ticks. This check did not use the Python synthetic observation fixture or model calls.

| | Original policy | Regenerated reference policy |
|---|---|---|
| Retreat threshold | 35% | 50% |
| Selected movement rule | `stay_with_you` | `retreat` |
| Requested destination | `(47, 84.5)` | Home `(23, 61)` |
| Engine movement acceptance | `true` | `true` |
| Position after 24 ticks | `(43.417, 73.251)` | `(31.417, 62.897)` |
| Distance from home | 17.85 → 23.81 tiles | 17.85 → 8.63 tiles |

This establishes that the generated threshold can affect actual engine behavior in the intended direction. It does not establish that the underlying belief is correct, that the change improves win rate, or that a language model reliably generates the intended policy.

## Local artifacts and reproduction

- Browser results and screenshots: `tmp/coaching/verification/browser-report.json`, `arena.png`, `reasoning.png`.
- Browser match: `tmp/coaching/df6c9df631b3deab/`.
- Scripted combat observations: `tmp/coaching/verification/native-report.json`; match `tmp/coaching/7d7f3ad7bf4016f0/`.
- Controlled simulator result: `tmp/coaching/verification/native-intervention.json`.
- Contextual model export: `tmp/coaching/verification/model-export.json`.

Run the regression suite:

```sh
tmp/coaching/venv/bin/python -m unittest discover -s tests -p 'test_coaching*.py'
```

The preserved local probe source is `tmp/coaching/native_policy_probe.nim`, driven by `tmp/coaching/check-native-intervention.py` against the saved before/after artifacts:

```sh
nim c -d:release --hints:off --warnings:off -o:tmp/coaching/native_policy_probe tmp/coaching/native_policy_probe.nim
PYTHONPATH=. tmp/coaching/venv/bin/python tmp/coaching/check-native-intervention.py
```

The repaired user-facing demo was restarted on port 8788 with the Softmax credential loaded only into its server environment. A funded account is still needed to validate actual speech, contextual model generation, asynchronous corrections and interruption. After that, the next research test is repeated belief-only interventions with independently specified held-out scenarios and matched generation budgets.
