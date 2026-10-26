# Neural policies and Jev

Fresh Meat uses GotA's Bassy tensor API and per-seat inference client, ported
from Polyworld `743f108091ca20b78f7e3fdc1a42f59ddb4ac795`.
Python and native executables are not player artifacts. A neural policy is a
BASIC program plus weights; BASIC builds observations and issues game actions.

## Neural networks

Upload a ZIP containing exactly one `.bas` entry, `tensors.json`, and binary
weights. Detection uses contents, so extensionless runner files work. Resources
use canonical paths relative to the ZIP root and never resolve on the host.
Uploads are limited to 16 MiB and 256 entries; BASIC source remains limited to
64 KiB. Each seat has its own model buffers and recurrent state.

The [tensor reference](TENSORS.md) describes dense layers, activations, CSR,
gather/scatter, masks, tensor slicing, and explicit mutable state. BASIC can
implement different feed-forward and recurrent architectures using these
operations. Pudge does not expose GotA-specific named native architectures.
Weights are little-endian int32, Q16.16, or float32; matrices are row-major.
Tensor float32 results must be converted to BASIC numbers before calling game
functions, and action coordinates require integral values.

Build and run the illustrative two-layer network:

```bash
python3 scripts/build_neural_policy.py --output tmp/pudge-neural.zip
python3 scripts/run_episode.py tmp/pudge-neural.zip base
```

The supplied weights are hand-authored to demonstrate the interface, not a
trained competitive model. Replace the tensors and BASIC observation/action
mapping with those of your trained network. `tensorDense` consumes weights in
`[outputs, inputs]` order. Export PyTorch linear weights as contiguous float32
bytes with that shape, and declare their offsets in `tensors.json`.
`TRAINING.md` documents the separate training observation/action interface;
the example tensor bot does not implicitly use that codec.

Every decision permits 100,000 BASIC instructions and 250,000 work units.
Tensor operations charge work by size. Per-seat allowances are 2 MiB of BASIC
memory and 32 MiB of logical native tensor/package storage. Storage, shapes,
types, resource ranges, and finite values are checked. Invalid operations fail
that VM without applying a partial destination update. This is not a process
RSS limit; ZIP decoding uses upstream Zippy.

## Jev and ordinary LLMs

The [Jev example](../examples/pudge_wars/players/jev.bas) requests an engage or
recover judgment every 480 simulation ticks, retaining a BASIC fallback.
It calls `oracleState`, `oracleQuestion`, `oracleCriterion`, `oracleAsk`,
`oraclePoll`, and `oracleAnswer`. The model defaults to `typesafe/jev-1.13` on
the `/v1/systemone` route. Text models use `llmAsk` / `llmPoll` / `llmText$`.

Hosted games use the injected `COWORLD_LLM_ENDPOINT` sidecar and send
`X-Coworld-Player-Slot` for per-seat accounting. Credentials are never supplied
by the policy. The platform owns model availability, rates, and spend limits.
No endpoint means `llmAvailable()` and `oracleAvailable()` return zero.
HTTP failures, rate limits, and unusable Jev responses are observable errors;
policies should continue their fallback behavior.

Local episodes disable remote calls by default. To enable them, configure a
local sidecar or a direct OpenRouter key in the environment, then opt in:

```bash
# COWORLD_LLM_ENDPOINT may point to your local compatible sidecar.
# Alternatively set OPENROUTER_API_KEY in your shell.
python3 scripts/run_episode.py jev base --llm --ticks 128 --timeout 120
```

Direct connections accept OpenRouter's HTTPS API root or a loopback endpoint;
policies cannot select arbitrary hosts or read environment credentials.
`COGAME_ORACLE_MODEL` selects the Jev model. `COGAME_LLM_MODEL` selects a direct
chat model. `COGAME_LLM_TIMEOUT_MS` defaults to 30,000 and is bounded at 120,000.
`COGAME_LLM_INTERVAL` spaces requests by simulation ticks; it does not replace
the hosted wall-clock rate limit. `COGAME_ORACLE=off` disables Jev helpers.

The default `wait_for_llm: true` runs all due decisions first, then waits for
their concurrent requests to settle before advancing the simulation. A reply
is consumed on the next decision. One pending request is allowed per seat.
Local `--llm-mode async` sets `wait_for_llm: false`, allowing simulation to
continue while requests run. The simulation still uses 32 Hz game time.
Headless episodes can finish before a response arrives in async mode.

Live LLM responses are nondeterministic. Float32 inference also does not promise
bitwise agreement across hardware. Recorded actions still replay without
calling a model, and every simulation tick can be verified. Model inputs,
Jev replies, PRINT output, and annotations stay out of public action replays.

The integration tests use a local SystemOne mock: simultaneous requests from
two seats, correct slot headers and model, private answers, invalid responses,
timeouts, and disabled-by-default local networking. No paid provider is needed
for `scripts/test_league.sh`.
