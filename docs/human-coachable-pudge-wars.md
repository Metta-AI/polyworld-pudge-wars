# Human-coachable Pudge Wars

Build and experiment plan, September 9, 2026. The local demonstration in [`coaching/`](../coaching/README.md) now includes a working ontology/belief model, contextual feedback, complete policy synthesis requests, independent behavioral gates and explicit trials, alongside the real game, executable movement/hook policy, Realtime tools and undo. The [meeting-note refinement](semantic-coaching-ir.md#what-changes-with-the-meeting-notes) separates belief revision from ontology revision and allows multiple policy realizations. The latest live voice check was blocked by OpenAI credits. General autoresearch, champion-policy extraction and the research experiments below remain proposed.

## 1. What we need to learn

Build a teammate whose strategic decisions a human can understand, change through coaching, and verify through play. Preserve the strategic knowledge and its evidence as a versioned artifact.

Separate four claims:

1. **Immediate coordination:** instructions improve play while the coach is present.
2. **Durable learning:** coaching plus autoresearch produces a stronger policy after coaching is removed, under matched optimization budgets.
3. **The co-play relationship:** participating as the agent's teammate produces greater understanding, empathy, and investment than observing and coaching it.
4. **Transfer:** a learned strategic rule can improve another compatible policy without copying its entire implementation.

The first claim does not establish the second; better win rate does not establish the third. Cross-game transfer is a later experiment.

The opening request leaves the comparator ambiguous. This draft includes both autoresearch without explicit coaching and coaching outside co-play. The user has specified a semantic reasoning IR and live voice coaching grounded in the ongoing game. Both are part of the first playable slice. Start with an internal 2v2 pilot, one human paired with one named agent, a browser game client with microphone controls, and the native authoritative host. Text and target/position pings remain complementary inputs. Detailed architecture and IR semantics are in [Semantic reasoning and live voice coaching](semantic-coaching-ir.md).

## 2. What the checkout already provides

| Foundation | Evidence and implication |
|---|---|
| Deterministic simulation and action replays | `examples/pudge_wars/sim.nim`, `replays.nim`. Reuse the 32 Hz simulation and action tape. |
| Human/bot seats and 2v2 | `game.nim`, `human.nim`, `tests/test_pw_nvn.nim`. Start with one human and one AI against two fixed bots. |
| Existing strategic behavior | `players/base.bas`, `teammates.nim`. Includes retreat thresholds, rescue rules, friendly hook checks, and assignment of a responder to a fresh ping. |
| Behavioral fixtures | `tests/test_pw_teammates.nim`. Already exercises rescues, expired pings, defensive overrides, and both banks. |
| Match analysis | `duellog.nim`, `duel_loop.md`. Events, snapshots, summaries, policy fingerprints, and replay artifacts already support manual policy improvement. |
| Headless evaluation | `spar.sh`, `botlab.sh`. Useful starting points; the new harness needs structured results, explicit 2v2 rosters, independent runs, and dataset splits. |
| Hosted policy interface | `coworld_host.nim`, `coworld/player/player.py`. JSON observations and actions exist, alongside the native BASIC policy path. Do not compare different policy implementations across experimental arms. |

Important integration gaps:

- In-game chat currently appends to a local display log. It is not durable coaching input or an authoritative transport. Lobby chat is a separate feature.
- BASIC speech is stored display data, not a faithful decision trace. The final status line cannot explain multiple attempted actions or rejected actions in one decision.
- The documented research loop is an external agent editing code between matches. A managed experiment queue, validation gates, and promotion ledger still need building.
- Local duel logging is gated to `NetOff`. Hosted sessions need explicit logging integration.
- Action replay reproduces recorded actions, not the decisions a changed policy would make. Policy counterfactuals need another harness.
- BASIC globals persist across decisions. A policy file replacement is not a safe mid-match update mechanism.

The checkout contains active edits and a private teammate policy. Implementation should use a separate coaching policy and leave those working artifacts intact. Select and freeze the starting policy before collecting experimental results; do not infer its strength from comments in its source.

## 3. The first complete player experience

The human joins a short 2v2 game with a persistent agent identity. A compact teammate panel shows its current intention, active instructions, and a readable playbook.

Example interaction:

1. The agent spends its hook on an unrelated enemy while the human is setting up a combo.
2. The human speaks, “Hook this one next,” while targeting an enemy. Streaming voice input is joined to the selected target, recent gameplay events, and the agent's decisions at the time of speech. The resulting semantic reference carries the target's stable ID and game tick.
3. The agent acknowledges, “I'll prioritize that target for my next hook.” The UI shows expiry and any defensive exception.
4. At the next eligible decision, the trace shows the selected target and rule. If the hook is unavailable or unsafe, it shows that reason. It reports the action's actual acceptance separately from the intention.
5. The human says, “In future, prioritize enemies I have hooked over taking a new shot.” This updates a versioned semantic reasoning IR: team objective, conditional tactic, priority, scope, exceptions, and evidence. The compiler lowers the tactic into a policy update, while the UI renders the same IR as a readable playbook.
6. In the background, autoresearch tests the change and bounded alternatives. At the next match boundary, a validated version is available with evidence, its tradeoffs, and an undo action.
7. In the next game, the human can see when the learned rule fires. An uncoached evaluation separately checks whether the new policy is stronger.

The persistent rule in this example keys off an observable teammate action, so it can still help after explicit coaching is removed. A temporary target command alone is not durable learning.

Start with four supported concepts: focus a target or teammate catch; hold a position/region; adjust retreat threshold; request or prioritize an ally rescue. “Stop chasing kills” requires interpretation into a visible pursuit boundary or target-priority change. Do not silently choose a permanent interpretation.

An instruction can be received, interpreted, active, blocked, completed, expired, or superseded. Acknowledgment means the instruction was understood, not that the requested action has happened.

## 4. Semantic reasoning IR and executable playbook

Use a working semantic model for concepts, uncertain beliefs, goals, strategic implications and evidence, and a separate executable policy IR for actual decisions. A language model grounds speech in context and can generate a complete policy realization of a revised model. Synthesis may vary between attempts; each artifact must satisfy explicit behavioral contracts. Ephemeral match context is separate from durable strategic knowledge. The controller still acts at game speed.

The playbook is rendered from executable policy IR. The working model separately explains its proposed rationale and links to realization artifacts. Only supported predicates, selectors, intents, and temporal operators can execute. Goals and hypotheses influence synthesis through declared contracts; they have no implicit runtime effect. Unsupported concepts remain visible proposals until grounding and tests exist. The detailed [IR design](semantic-coaching-ir.md) defines these boundaries.

Each rule contains:

- Stable rule ID and version; applicability conditions and feature definitions.
- Target selector, priority, action intent, parameters, and explicit exceptions.
- Scope: next eligible action, bounded duration, current match, or persistent policy.
- Source coaching event and example references; regression contracts; evaluation evidence.
- Required controller capabilities and versions, making portability explicit.

For example, a focus rule selects a currently visible, living enemy by ID; it prefers that enemy for the next legal offensive hook, expires on death or timeout, and yields to specified defensive behavior. A persistent follow-up rule selects enemies already caught by an ally. Neither rule changes collision or permits hidden-state access.

The first demonstration uses one Python rule evaluator through the existing JSON policy protocol. This makes the complete supported strategy inspectable without modifying the private BASIC policy. A future extraction can preserve strong mechanical routines behind explicit contracts and add generated BASIC sections or native strategy gates. Keep all experimental arms on the same backend, and link action emissions to semantic rule IDs. Autoresearch should edit the IR through schema-valid patches, not arbitrary substitutions in generated source.

The human description must use the same predicates, thresholds, priority, and exceptions as execution. Preserve an inspectable detailed view of the rules and tactical dependencies. Any behavior still delegated to unextracted code must be labeled as such; the first release only claims coachability for the supported concepts.

Keep all experimental arms on the same Python rule evaluator, observation surface and decision cadence used by the demonstration. A BASIC backend can later consume the same representation after parity checks. Do not confound coaching or ontology changes with a change of runtime implementation.

## 5. Two update speeds

**Live semantic policy updates:** speech plus retrieved gameplay context produces a proposed IR patch. The validated patch is committed as a versioned IR revision; the compiler lowers supported changes into bounded rules or per-agent controller inputs, applied atomically at an authoritative decision boundary. They do not replace the BASIC VM. Direct target/position inputs bypass language interpretation but still enter through the IR. Speech and text interpretation are asynchronous. Show pending interpretation, then active or expired, and distinguish desired IR revision from the revision actually running. Discard responses whose target, match, or directive version is stale. A newer instruction supersedes an older instruction for the same concept; different concepts coexist under explicit priority rules. Start with one authorized coach per agent.

**Persistent learning:** background jobs test candidate IR revisions and produce an immutable policy package from the selected revision. Executable changes beyond the live rule vocabulary activate at a match boundary, where controller memory can be reset deliberately. A supported durable rule can first run as a temporary trial in the current match; its long-term retention has a separate validation status. An already authorized class of changes may activate automatically after passing its gates; the player sees the change and can undo it. Ambiguous durable instructions need a concise interpretation the player can correct or confirm by voice.

The policy keeps running if the language service or research worker is slow or unavailable. The match loop never waits for them. Worker results reference their parent policy hash; a result based on an older policy must be revalidated against the current parent before activation.

Permanent coaching commitments become constraints on subsequent optimization. A win-rate improvement must not silently remove “do not pursue across the river.” If a requested style has a performance cost, present that distinction; successful coaching and improved competitive strength are separate measurements.

## 6. Evidence the human can inspect

Record decision traces at the point where the controller chooses and attempts actions, with match/seat/tick/decision IDs, policy hash, instruction IDs, tested predicates, selected rule, target, proposed actions, accepted actions, and rejection or override reasons. A decision can contain several actions, including movement, purchases, and a hook. Connect traces to the recorded action sequence.

Generate explanations from this trace: “I retreated because my health was below your 50% threshold,” or “I held the hook because your teammate blocked the throw.” Do not ask a separate language model to guess a reason from the final frame.

For a changed rule, show the old and new interpretation, the relevant replay moment, matched-state decisions before and after, and results from fresh rollouts. Mark a matched-state comparison as a decision comparison; the old replay's subsequent outcome is not the new policy's outcome.

Build a policy shadow runner with captured per-decision, fog-filtered observations and its own VM memory. Feed observation history from the start of a short scenario or a supported checkpoint. Candidate action calls write to a capture sink instead of mutating the replay world. Match summaries and 4 Hz state snapshots are insufficient for exact 32 Hz policy comparisons.

For interventions from arbitrary long-match moments, either reconstruct each candidate's memory by shadow-running the observation prefix or add a versioned checkpoint format. Do not copy opaque globals into an incompatible program. Full interactive rollouts must use reactive opponents and teammates; replaying a human's old future actions is a scripted probe, not a prediction of how that human would respond.

“Doesn't disturb anything else” becomes two testable guarantees: only declared rules/parameters are editable, and decisions outside the declared conditions match on a frozen scenario corpus. Once a changed action changes the world, later behavior can diverge legitimately. Report the coverage of this guarantee rather than promising universal non-interference.

## 7. The background research loop

Use a local Python worker and durable job directories first. Each job has an immutable parent policy, input event IDs, allowed edit scope, model configuration, budget, and evaluation protocol. It writes candidates and reports atomically; it never edits the running policy in place.

One cycle:

1. Read the grounded coaching event and current semantic IR; turn the requested change into a hypothesis and an independently reviewable behavior contract.
2. Propose a bounded semantic IR patch and focused scenarios. Keep the contract fixed while testing candidate variants; lower executable changes through the same compiler used by live coaching.
3. Validate the schema and compile; check VM limits, protocol behavior, and fog restrictions.
4. Run instruction applicability, exception, expiry, and unrelated-behavior checks.
5. Run paired, side-swapped 2v2 evaluations against frozen opponent and teammate pools on development/validation seeds.
6. Retain or reject the candidate using preregistered compliance and performance gates. Record all attempts, failures, costs, and reasons.
7. Make the selected version available at the next match boundary and attach its evidence to the playbook.

A patch that improves win rate but violates the coaching contract fails. A patch that satisfies the instruction but has uncertain competitive value is labeled accordingly. The optimizer cannot change the evaluator, scenario expectations, engine balance, opponent pool, or held-out test set. Repeated promotion decisions use validation data; the final test set remains unavailable to the worker.

Log optimization compute separately from transcription/interpretation compute, as well as human minutes, candidate attempts, and simulated matches. Compare both quality at matched optimization budget and total cost to reach a given quality.

## 8. Modalities share one coaching event format

| Modality | What it contributes | First scope |
|---|---|---|
| Text | Strategy, conditions, corrections, questions | First playable slice |
| Typed target/position pings | Fast reference to who or where; cheap live coordination | First playable slice |
| Streaming voice with push-to-talk and an explicit conversation mode | Coaching during play; retrieve recent context, interpret references, accept spoken corrections, and give brief responses | First playable slice |
| Replay annotation | A bounded moment plus what should have happened; positive and negative examples | Next increment |
| Demonstration/takeover | An observed action sequence with context and intended lesson | Later, after target/intent labeling works |

All produce events with author, recipient, match and tick range, modality, text/transcript revisions, entity/region references, intended scope, context-bundle ID, and interpretation status. A rolling context buffer includes visible state, recent events, human target/aim cues, agent decisions, and the active IR. Resolve “him,” “there,” and “why did you do that?” against the speech interval, then revalidate actionable facts at activation time. Link praise or criticism to a recent event when possible. Untargeted encouragement can remain social feedback; do not treat every positive utterance as a reward for the latest action.

Store session events, playbook versions, source provenance, and reports alongside the replay. Record the authoritative tick when an interpretation takes effect. Action replay stays driven by its action tape; reproducing policy decisions additionally needs policy inputs, directive events, controller versions, and initial memory. Raw voice retention can be optional; transcripts and grounded events are sufficient for the first analysis.

For the first browser voice session, add an explicit coaching transport with request/ack/status messages, seat ownership, recipient validation, and speech/context time alignment. The native client can later call the same authoritative handler. Do not reuse the lobby's broadcast chat as a policy control channel. Integrate authoritative context/event logging in the selected host path from the first live milestone; hosted sessions must ship IR revisions and coaching sidecar artifacts as well as the replay.

## 9. Experiments that distinguish the claims

First run a usability pilot to find interpretation errors and collect useful scenario fixtures. Do not present a few developers' games as a powered hypothesis test.

**Durable learning: coaching information ablation.** Collect a frozen set of baseline-policy human co-play sessions with coaching, then fork identical policy ancestors. Give both forks exactly the same gameplay observations/actions and research budget. One also receives explicit coaching and annotations. Restrict both to the same editable representation. Repeat independent optimization runs. This isolates the incremental value of coaching on shared data; it does not measure the complete adaptive co-play loop.

**Durable learning: closed-loop product test.** Compare independent policy lineages in which humans co-play with coaching enabled versus co-play with explicit coaching withheld. Match session duration, starting policy, optimizer, editable scope, opponent distribution, and budget. Their trajectories will differ; that is part of the intervention. Assign participants/lineages randomly and account for human skill. A pure bot-only autoresearch arm is a useful additional benchmark, but it also changes the gameplay data source.

**The co-play claim.** Compare live teammate coaching with observer/replay coaching using the same interface, comparable information visibility, coaching time, and research budget. Randomize participation role; counterbalance order if participants try both roles, with fresh policy lineages. Measure agency/understanding, investment, and willingness to keep developing the agent in addition to skill. Do not infer empathy from compliance or wins. Using identical recorded moments is a complementary test of feedback quality, not a substitute for testing the experience of playing together.

**Primary skill outcome:** change from the common ancestor in held-out 2v2 match score, defined as win = 1, draw = 0.5, loss = 0. Pair the evaluated agent with frozen teammate policies; use frozen opponent pools, unseen seeds, and both banks. Turn off explicit coaching and further optimization. Keep persistent learned rules enabled. Also report retained performance with the original human and performance with unfamiliar partners to separate personalization from general improvement.

Secondary measures: live coached performance; target/teammate follow-up; successful rescue opportunities; harmful friendly hooks; deaths; instruction success conditional on eligible opportunities; explanation fidelity; human prediction of the next strategic decision; learning per human minute and per compute budget. Report “no eligible opportunity” separately from success or failure. Measure speech-end to IR interpretation, IR commit, policy activation, and first eligible action separately. Add a same-utterance context ablation (transcript alone versus transcript with retrieved gameplay context) to measure whether grounding improves reference resolution and intended behavior.

The statistical unit is the independent coach/policy lineage or optimization run, not each tick or each match of one repeatedly evaluated policy. Use paired estimates and uncertainty that respects that clustering. Estimate variance in the pilot, then preregister the minimum useful effect, sample size, fixed analysis checkpoints, and stopping rules. A provisional product target could be a five-percentage-point held-out score improvement, but it is not a validated power calculation.

Freeze engine/controller versions, bot cadence, aim noise, map and match rules, policy ancestor hashes, opponent snapshots, data splits, and compute accounting in an experiment manifest. Native BASIC and hosted Python results are different experiments until their behavior is shown equivalent.

## 10. Build sequence and acceptance gates

| Milestone | Concrete work | Done when |
|---|---|---|
| 1. Make semantic strategy executable | Create a separate coachable policy; freeze ancestor; define typed semantic IR and the supported lowering vocabulary; extract the first strategic rules; generate policy and readable playbook; instrument actual decisions. | A reviewer can predict supported decisions from the IR view. Both lowering paths preserve rule IDs and match on golden scenarios. Unsupported semantics have no implicit effect. |
| 2. Complete contextual voice coaching | Browser 2v2 UI; streaming microphone input; authenticated coaching transport; rolling gameplay context; time-aligned grounding; versioned IR patch; live rule update; spoken/text response and correction. Start with focus target and follow-up on a human catch. | During play, a human can speak about a recent event, see the resolved meaning and IR change, and observe the next eligible action. Negation, interruptions, stale targets, ambiguity, and disconnects behave predictably. |
| 3. Make one semantic lesson persist | Persistent IR revision; preview/correction; decision shadow runner; scenario contracts; worker queue; validation report; package activation; rollback. | One spoken lesson produces a versioned strategic artifact and verified behavior change that persists in a subsequent uncoached match. |
| 4. Run the learning comparison | Structured headless 2v2 harness; frozen pools and splits; repeated paired runs; experiment manifest; budget/cost ledger; reporting. | Coached and uncoached forks can be compared reproducibly with uncertainty and no worker access to held-out tests. |
| 5. Expand coaching and run the co-play study | Add replay annotations and optional native voice integration; expand the four semantic concepts; compare co-play with observer coaching. | Modalities produce the same grounded IR patches and contracts; the study measures both learned skill and human investment. |
| 6. Test transfer | Export one strategic rule plus prerequisites, examples, and evidence; adapt it to a second frozen controller in the same game. | Held-out comparison of the second controller with/without the rule shows whether the knowledge transferred. Record failed transfers too. |

Likely code boundaries: new `coaching.nim` for compiled rules and authoritative lifecycle; new `coachtrace.nim` for decision evidence; a `coaching/` directory for semantic IR schema, context retrieval, compiler, voice adapter, translator, worker, and artifacts; a browser microphone/conversation panel; integration in `bots.nim`, `ui.nim`, `game.nim`, `duellog.nim`, and the selected host/transport path. Keep display/worker state outside the deterministic `World`. Audit BASIC host data/function limits before extending its API; do not assume spare slots. See the component map in the [IR design](semantic-coaching-ir.md).

Required implementation checks: existing teammate, bot, human-input, replay, and 2v2 tests; focused scenario tests for each coaching contract; unchanged behavior with no directive; identical results with tracing disabled/enabled; stale and conflicting message handling; invalid patch/VM failure rejection; worker restart and stale-parent handling; policy promotion/rollback provenance. Include microphone/transport failure, transcript revisions and negation, time alignment, ambiguous references, IR/compiler agreement, network ownership, and host artifact checks in the first voice milestone.

The first playable slice is voice plus current gameplay context → explicit semantic IR change → compiled live policy update → trace-backed feedback. Complete one validated persistent improvement next. Expand the semantic vocabulary after that complete loop works; unrestricted code evolution and cross-game ontology are subsequent work.
