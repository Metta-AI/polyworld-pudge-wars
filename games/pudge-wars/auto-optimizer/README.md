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

1. **Close the previous iterations' books.** `ledger.py unfinalized` lists
   every row whose ACU cost is not final (iteration, session id). For each
   distinct session id, fetch that session's final `acus_consumed` once
   (Devin MCP `devin_session_interact action=get`) and run
   `ledger.py cost --iteration N --acus X --final` for the *highest* iteration
   of that session; the tool closes the earlier rows of the same session at
   0 ACU with a pointer, so a session total is never counted twice. If an
   eval is still running, `hosted.py xp poll` / `xp summarize` it and write the verdict
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
6. **Smoke** (`hosted.py xp create --policy <ref> --episodes 3 --top-n 3
   --label iterN-smoke`, `xp poll`, `hosted.py logs` on every candidate
   episode → zero tracebacks, hypothesis instrumentation present).
7. **Verify** with the primary protocol at `eval_protocol.directional_n`
   (`hosted.py xp create --policy <ref> --episodes 40 --top-n 3 --label
   iterN-directional`) launched in the same window as an equal-n run of the
   champion; poll (the next session may finish it), `xp summarize` both.
   Escalate to `gate_n` only if the directional pair clears the decision rule.
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

Counterfactual evals are **disabled for this league** (HTTP 409), so the
oracle is a fresh-field **XP request** against the live top of the ladder
(`hosted.py xp create --policy <ref> --top-n 3`). `xp summarize` reports the
clean win rate with binomial SE, per-side / per-opponent splits, taint counts
and hosted cost. Candidate and champion are compared at equal n in the same
window; the `cf` subcommands stay in `hosted.py` for when counterfactuals
are re-enabled. Known caveat (STATE `findings`): the current roster seats two
participants per episode even under the `League 3v3` variant, so a 1v1 result
may not transfer to team-pair ladder rounds. Local `pwheadless` runs are
debugging instruments only.

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
A session's ACU figure is cumulative, so when one session produces several
iterations the total is charged to the highest iteration and the earlier rows
close at 0 ACU with `llm_cost_note` pointing there (iterations 0 and 1 share
the bootstrap session). Set `cost.usd_per_acu` in `STATE.json` to render USD. Hosted eval compute is
recorded from the Coworld daily-budget delta (`hosted.py budget`).
