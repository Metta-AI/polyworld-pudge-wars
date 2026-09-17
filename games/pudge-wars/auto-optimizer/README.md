# Pudge Wars auto-optimizer campaign

A recurring, branch-tracked research loop that improves a Pudge Wars policy one
attributable change at a time, verifies each change on the hosted league field,
and records the LLM compute cost of every iteration. It starts from the repo's
default Python policy (`coworld/player`) and is meant to be resumed by a fresh
Devin session every three hours with no chat history.

Everything a session needs is on disk in this directory:

| File | What it holds |
| --- | --- |
| `STATE.json` | Campaign constants (league, coworld, identity, baseline pins, reference anchor), the latest/champion policy versions, eval protocol, submission gate, cost settings. The single source of truth for "where are we". |
| `ledger.jsonl` / `LEDGER.md` | One record per iteration: change, policy version, eval id, verdict, Devin session id + mode + ACU cost, hosted compute spend. Rendered by `tools/ledger.py render`. |
| `experiments/NNN-<slug>.md` | Pre-registered hypothesis + verdict per iteration. |
| `evals/<label>/` | Request bodies, raw eval JSON, per-pair rows, `summary.json` for every hosted eval. |
| `user_preferences.md` | The user's verbatim directives and how they are interpreted. |
| `tools/hosted.py` | Identity check, budget, uploads listing, counterfactual/XP eval create-poll-summarize, policy logs. |
| `tools/ledger.py` | Ledger writes and rendering. |

Also read before changing the policy: [`../closed_levers.md`](../closed_levers.md),
[`../META.md`](../META.md), [`../players/pudge-wars-rusher/VERSION_LOG.md`](../players/pudge-wars-rusher/VERSION_LOG.md),
[`../../../coworld/player/README.md`](../../../coworld/player/README.md), and
[`../../../docs/pudge-improvement-roadmap.md`](../../../docs/pudge-improvement-roadmap.md).
Optimizer doctrine: `Metta-AI/optimizer-seed` `AGENTS.md` (one change per
upload, taint-first aggregation, small-N humility, submission gated).

## Resume procedure (every session)

Run from the repo root on the campaign branch named in `STATE.json`.

```bash
git fetch origin && git checkout <STATE.branch> && git pull --ff-only
export CAMP=games/pudge-wars/auto-optimizer
softmax set-token "$SOFTMAX_USER_API_TOKEN"            # never print the token
coworld player use $(python3 -c "import json;print(json.load(open('$CAMP/STATE.json'))['identity']['player_id'])")
python3 $CAMP/tools/hosted.py whoami                   # must pass before any write
python3 $CAMP/tools/hosted.py budget                   # respect eval_protocol.budget_rule
python3 $CAMP/tools/ledger.py show                     # what happened before
```

1. **Close the previous iteration's books.** If the last ledger row has
   `llm_cost_acus_final=false`, fetch that Devin session's final
   `acus_consumed` (Devin MCP `devin_session_interact action=get`) and run
   `ledger.py cost --iteration N --acus X --final`. If its eval is still
   running, `hosted.py cf poll` / `cf summarize` it and write the verdict
   (`ledger.py verdict`, close the experiment file, update `STATE.latest` /
   `STATE.champion`, add dead levers to `../closed_levers.md`).
2. **Open this iteration.** `ledger.py start --iteration N+1 --session <this
   devin id> --mode ultra --change "<one line>" --hypothesis
   experiments/NNN-slug.md --base-ref <STATE.latest.policy_ref>`. Record the
   Coworld `spent_today_usd` from `hosted.py budget` for the hosted-cost delta.
3. **Hypothesize** (write `experiments/NNN-slug.md` with the template below)
   from evidence: the previous eval's per-slot/per-opponent readout, policy
   logs (`hosted.py logs`), replays, and the roadmap. Check `closed_levers.md`
   first; never re-run a refuted lever without new evidence.
4. **Change exactly one behavior** in `coworld/player/` (plus instrumentation
   if the hypothesis needs a new signal). Keep `python3 -m unittest discover
   -s tests -p 'test_pw_coworld_policy.py'` green; add a unit test for the new
   decision when practical.
5. **Build + upload (inert)**:
   ```bash
   docker build --platform linux/amd64 -f coworld/player/Dockerfile \
     -t pudge-auto-optimizer:iterN coworld
   coworld upload-policy pudge-auto-optimizer:iterN --name pudge-auto-optimizer \
     --run "python -m coworld.examples.pudgewars.player.player" \
     --tag iteration=N --tag purpose=<slug> --tag source_commit=<sha> --tag base=<prev ref>
   ```
   Immediately: `ledger.py set --iteration N policy_ref=... policy_version_id=...
   image_digest=... source_commit=...` and `STATE.latest`.
6. **Smoke** (`hosted.py cf create --candidate <ref> --n 3 --label iterN-smoke`,
   poll, `hosted.py logs` on one candidate episode → zero tracebacks).
7. **Verify** with the primary protocol at `eval_protocol.directional_n` or
   `gate_n` (`hosted.py cf create --candidate <ref> --n 100 --label iterN-gate`),
   poll (hours; the next session may finish it), `cf summarize`. Compare with
   the champion's summary on the same protocol.
8. **Record**: `ledger.py verdict`, `ledger.py hosted-cost`, experiment file
   verdict block, `STATE.champion` on promote, `closed_levers.md` on reject.
9. **Cost**: at the end of the session fetch this session's `acus_consumed` and
   run `ledger.py cost --iteration N --acus X` (leave `--final` off; the next
   session backfills the final number).
10. **Commit and push** everything to the campaign branch (policy source,
    experiment file, evals/, ledger, STATE). The tracking PR updates itself.

Never call `coworld submit`. Submission is the only irreversible act and needs
the user's explicit go-ahead (`STATE.submission.allowed`).

## Hypothesis template (`experiments/NNN-slug.md`)

```
# NNN — <slug>
Iteration: N   Base: <policy ref>   Candidate: <policy ref>   Session: <devin id>
Observation:
Causal guess:
Evidence:
Missing data:
Change (one behavior, code location):
Expected metric movement:
Eval plan (protocol, n, label):
Overfit risk:
Rollback condition:
## Verdict
Decision: promote | reject | no_signal | rerun
Numbers: candidate w±se vs champion w±se on the same protocol, clean n / tainted n, per-slot, per-opponent
Reason:
```

## Evaluation protocol

The ladder plays two entrants (slots 0 and 3) with four league filler seats.
The primary oracle is a **counterfactual eval** against
`reference.ladder_anchor_ref` (currently `pudge-wars-rusher:v16`, the #1
entrant): the platform replays that policy's real ladder games with our
candidate in its seat — same seed, same opponent, same fillers — and scores
each pair. `hosted.py cf summarize` reports the candidate's clean win rate, the
anchor's win rate on the exact same games, per-probe-slot and per-opponent
splits, taint counts, and binomial SE. Two candidates are compared on this
protocol at equal n; the anchor is the yardstick, not our baseline.

Fresh-field XP requests (`hosted.py xp create --top-n 3`) are the secondary,
broader guardrail. Local `pwheadless` runs are debugging instruments only.

## Recurring automation

Devin automation `auto-600aa4eb690e459190c04b10d5c0c9fb`
(<https://app.devin.ai/automations/600aa4eb690e459190c04b10d5c0c9fb>) starts one
`ultra` session every three hours (UTC, on the hour; concurrency 1, 40 ACU cap
per run) with the prompt in `automation_prompt.md`. Each run resumes from this
directory and the campaign branch; it never submits to the league. Details are
mirrored under `automation` in `STATE.json`.

## Cost accounting

Devin bills sessions in ACUs. Each ledger row stores the session id, the mode
(`ultra`), and `acus_consumed` as read from the Devin session API, first
provisionally by the session itself and then finalized by the next session.
Set `cost.usd_per_acu` in `STATE.json` to render USD. Hosted eval compute is
recorded from the Coworld daily-budget delta (`hosted.py budget`).
