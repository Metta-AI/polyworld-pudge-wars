# Text → symbolic policy → game → text

The [spatial coaching intervention](../../docs/semantic-spatial-policy.md) adds stable lane ownership, a single rune responder, and occupied-route detours in versioned IR. Its [policy text](../policies/executable/spatial.policy.md) generates [this controller](../policies/spatial_generated.py). Run `tmp/coaching/venv/bin/python -m coaching.symbolic.play` to play with it using the native engine and existing browser renderer.

This experiment compiles the grounded seven-layer policy documents in `../policies/executable/` into explicit Python strategy programs. It extracts the executable calls and control flow back into text, regenerates the program, and tests both copies in Fresh Meat. The [grounding contract](../policies/executable/grounding.md) defines the supported subset and the remaining ontology work.

The [first measured run](../../docs/semantic-policy-roundtrip.md) completed 42 benchmark games: the support policy won 5/8 held-out games against Base, with zero round-trip mismatches across 3,282,456 decisions. The lead-tuning candidate failed the held-out retention gate; the loop kept the parent.

For further iterations, use the [persistent campaign workflow](CAMPAIGNS.md). It remembers prior experiments, reserves fresh maps, checks each proposed semantic effect, resumes completed games, supports opponent suites and separates confirmation from a final audit.

Run from the repository root with Python 3.10+ and the repository's Nim dependencies installed. The compiler and evaluator use Python's standard library and need no API key.

```sh
mkdir -p tmp/coaching
nim c -d:release --hints:off --warnings:off -o:tmp/coaching/symbolic_match coaching/symbolic/native_match.nim

# Inspect both directions independently.
python3 -m coaching.symbolic.ir generate coaching/policies/executable/support.policy.md tmp/coaching/support.py
python3 -m coaching.symbolic.ir extract tmp/coaching/support.py tmp/coaching/recovered.policy.md

# Run a complete 2v2 game against the current Base policy, frozen for this run.
python3 -m coaching.symbolic.evaluate coaching/policies/executable/support.policy.md --out tmp/coaching/my-symbolic-game

# Run the development/validation improvement loop.
python3 -m coaching.symbolic.loop --out tmp/coaching/my-symbolic-loop
```

Output directories must be new so evidence is not overwritten. `--regenerated` on the single-game evaluator runs the policy generated from recovered text. The native runner uses the real simulation, per-seat fog observations and JSON action validation; it accelerates time and does not reproduce live network scheduling.

The original full loop uses two development seeds on both banks to compare the small Loom projection and three support candidates. The candidate selector sees only development kill margins. With the default parent it tests velocity-lead multipliers 0.5, 1.0 and 1.5, then compares the selected candidate, its unmodified support parent, and Loom on four separate seeds, again on both banks. Comparing the selected candidate to its parent isolates the parameter search from the larger assistant-authored change. It also reruns two complete selected-policy games with regenerated code and requires identical action-stream hashes, scores and termination ticks. The current evaluator checks every actual candidate decision and memory state against a regenerated shadow; the historical first run additionally shadowed opponent observations. That redundant work is no longer needed.

The output includes:

- `contract.json`: the comparison, selection rule, separate seed sets and frozen input hashes.
- `artifacts/<arm>/`: original text, executable code, extracted text, regenerated code and their hashes.
- `games/<match>/`: terminal score, command and skill counts, decision samples, trajectory hash, round-trip checks and engine log.
- `development.json` and `report.json`: all candidate results, the selected candidate and held-out comparisons.
- `next-iteration.policy.md`: extracted text ready to become the next iteration's input.

Use a recovered artifact as the next candidate with `--candidate <previous-run>/next-iteration.policy.md`, and supply **new** `--train-seeds` and `--validation-seeds`. Defaults are a reproducible demonstration split, not a reusable fresh test set. The next artifact retains the parent unless the selected candidate improves mean kill margin and improves on at least three quarters of held-out seeds. This small-sample gate is exploratory, not statistical proof; every failed candidate remains in the report. It does not activate a policy in the live coaching app.

The controlled interventions are:

```sh
python3 -m unittest discover -s tests -p 'test_symbolic_roundtrip.py' -v
```

They check that executable parameter edits survive extraction and shift aim, a text health threshold changes only its intended immediate decision region, rescue commitment terminates selection, unknown behavior is rejected, and altered skill bindings fail at load time. Game trajectories can diverge after a successful coaching edit; immediate non-interference tests are not a claim that all future events stay unchanged.

This is assistant-authored grounding plus a deterministic compiler/extractor and a bounded parameter search. It does not yet infer arbitrary ontologies from existing Python, synthesize new skills using an API model, or test whether human coaching beats an equally resourced automated research loop.

## Competitive BASIC policy

The [v16-derived BASIC rusher](../policies/basic-rusher/README.md) is now the
default Base. Its seven-layer semantic contract round-trips through
`python3 -m coaching.symbolic.rusher_basic_ir`; this is a separate registered
family from the small teaching lessons in `basic_coaching_ir.py`.
