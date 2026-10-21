# Pudge Wars BASIC, neural and Jev release — 2026-10-09

The [existing 3v3 league](https://softmax.com/observatory/v2?detail=league:league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0)
now runs certified, canonical `pudge-wars-basic:0.1.1`. Its league ID and
Competition division were retained. The source-owned runtime is Nim/Bassy;
players submit raw BASIC or BASIC-plus-weights ZIP packages.

The migration retired all 37 live container-policy memberships, including
benched versions, and replaced all three container fillers. The platform reset
archived 1,155 old rounds, cleared Elo standings and removed 1,152 old competition
feed events. Historical episode and round records remain accessible by ID.
The pre-migration settings, roster and commissioner standings were saved under
`tmp/league-migration-20261009/` before the change.

The league now uses mixed teams: `team_n`, two contiguous banks, distinct
teammates, rating-based matchmaking and OpenSkill. It schedules 24 episodes per
round on a 32-minute interval. Short rosters use unranked fillers, which may
repeat policies. The first BASIC round completed all 24 episodes successfully.
The owner has Base selected as champion, with the other uploaded policies
available for selection; no new player identities were created.

The seven original BASIC policies are registered as `pudge-basic-{name}:v1`:
base, aggressive, sniper, challenger, denier, patient and support. They also
form the filler pool. `pudge-basic-neural:v1` and `pudge-basic-jev:v1` are optional
examples registered separately; they are not automatic fillers. The neural
example uses illustrative hand-authored weights, not a trained policy.

Neural policies use GotA's packed tensor interface, with private model buffers
and recurrent state. Jev uses the same per-seat SystemOne client as GotA, with
slot accounting through the platform sidecar. By default the game waits for
concurrent requests between ticks. [Inference documentation](../coworld/INFERENCE.md)
covers package layout, API, limits, examples and local configuration.

Validation completed:

- Nine Nim suites, six host integration tests, six local episode tests, six
  neural/Jev integration tests, and the training bridge test.
- Linux/amd64 build, ten-step local certification, hosted certification and
  five hosted smoke episodes for each of 0.1.0 and 0.1.1.
- A full local 3v3 neural match and local Jev mock match, both with every replay
  tick verified.
- One hosted neural-versus-Jev episode, 128 ticks: both policies ran without VM
  errors, Jev returned a usable posture, and all 256 recorded actions replayed
  with every tick matching. This verifies integration, not competitive strength.
- WASM semantic check and unchanged simulator-37 replay viewer compatibility.

The sibling 1v1 league retains `pudge-wars:0.3.22` and its existing runtime.
Global policy artifacts were retained; retirement affects 3v3 league membership.
Each game's default league was updated to refer to its own remaining league.

[deployment.json](../coworld/deployment.json) records immutable game, manifest,
policy and validation IDs plus source hashes. Deployment used the current
working tree before source publication; the recorded HEAD and hashes describe
that build. This repository update publishes the migration sources. Future
updates can use the manual deploy workflow. It does not repeat the standings reset or roster removal.
