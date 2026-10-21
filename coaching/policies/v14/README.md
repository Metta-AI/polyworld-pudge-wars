# v14 league practice and coaching

Run a standard three-versus-three game:

```sh
cd /Users/aaln/experiments/softmax/polyworld-pudge-wars
open -a "Co-play Notes"
uv run scripts/play_policy.py --name Aaron --opponent combined
```

P1 is Aaron; P2–P3 are allied Base v14 bots; P4–P6 are enemy Base v14 bots.
This is **mirror practice**, not a local copy of Richard's hosted policy.
Names appear above the players. WASD or right-click moves, Q then click hooks,
E grapples, F blinks, and G pings. `--quickcast` casts at the cursor on Q press.
Use `--seed NUMBER` for another map. Closing the game stops its local processes.

The native app appears as **Pudge Wars** in macOS. **F9** opens the pause menu
and pauses the whole local match, including the five bots. **Resume** continues;
**Restart Game** starts a fresh round with the same map, lineup and frozen policy
code, resetting each bot's memory. You can restart during play or after a round
ends without reopening the game or interrupting your Co-play Notes recording.
The recorder's pause button controls recording; F9 controls the game.

In Co-play Notes, open **Policy versions** from its menu-bar menu and select
**Pudge v14 — league reference**. The installed app now snapshots the last
selected project when recording starts. Select it before pressing Record;
choose the Pudge window and click Share. Save drafts before recording if they
should be included. Changing projects during capture does not change that
session's reference. The v14 project uses the manual adapter: the older Pudge
converter implements another IR dialect and must not compile this prose.

The launcher freezes bot code for each match under
`duels/local-policy/match-*/runtime/`. `policy-inputs.json` records code hashes,
IR hash, host hash, seed and arm configuration; `input.ir.md` is the text
reference. Completed and restarted rounds are saved as `rounds/round-001.pwr`
and matching `.json` results; `replay.pwr` is the latest archived round.
Closing a round early without Restart does not archive the unfinished round.
The Co-play session is
separate, under `~/Documents/Policy Loops/sessions/`. Its manifest pins the IR,
policy code, media and recording times. The recorder does **not** verify what
the game executes. Compare its `policy_sha256` to the launcher's
`source_hashes["coworld/player/base.py"]` before attributing coaching to a policy.
Do not change `input_execution_verified` based only on selecting a label.

After playing, export the session with original video when motion matters.
Supply that export and the match folder together. Coach using ordinary language
or block IDs, for example: “At 01:23, [k-fish] should give the teammate more room.”
Notes are hypotheses, not measured evidence. Attach session ID, video timestamp,
and supporting frame/replay to the affected block before proposing an edit.

## Research artifacts

- `oracle.py` is the immutable v14 execution library, verified against hosted
  v14's saved source. `oracle.json` identifies it. Never edit it.
- `policy.md` is the plain-text semantic account. Blocks have stable IDs,
  provenance and evidence. Untested blocks are labelled explicitly.
- `blink-candidate.md`, `rune-candidate.md` and `rune-owner-candidate.md` contain proposed semantic changes.
  Their existence does not mean acceptance or a deployed version.
- `ledger.jsonl` is an append-only event ledger: preregistration, discarded
  compilations and terminal decisions retain their iteration IDs.
- `skills/` contains versioned execution helpers. They are compile targets,
  not the IR. Original v14 internals remain frozen in `oracle.py`.

`python3 -m coaching.v14_compile INPUT.md OUTPUT.py` is a bounded compiler for
registered semantic edits. Unknown prose edits are rejected until their
implementation and verification are added. It does not claim to understand
arbitrary prose. It archives compiler/input sources next to the output.
Repeated compilation with this compiler is deterministic; agreement does not
measure agreement between independent interpretive compilers.

Evidence for this campaign is in `duels/v14-coaching-20260915/`. Decision-table
probes and empirical lifts cover explicitly named projections. A zero residual
there does not establish full-policy semantic fidelity. The initial acceptance
threshold is 99% lift agreement with zero isolation leaks. Goals are unchanged;
goal edits require human review. Local games use the native simulator with
synchronous JSON actions and cannot establish hosted league improvement.

Before accepting an edit, run the preregistered fresh confirmation and ablation,
reconcile its behavior, update evidence on its blocks, and then validate hosted
transfer against pinned competitors. Keep XP requests at 10–20 episodes and
record actual seeds; repeated identical seeds are one seed block, not independent
maps. Do not use the old XP helper's default Coworld 0.3.13 for this 0.3.17 league.
