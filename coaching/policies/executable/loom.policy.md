# loom_grounded: orthogonal policy IR

Format: symbolic policy text v1. Binding: pudge-skills-v1.
Origin: Assistant-authored executable grounding; see adjacent grounding.md for departures from source prose.

## 1. Situation

Players have team, identity, tile position, health, cooldown and inventory. Hooks have owner, victim, location and flight state. Inputs are each seat's fog-filtered observation. Numeric regions and affordances are defined by the skill contracts below; missing enemies remain unobserved, not absent from the world.

## 2. Belief

The observe skill retains sampled velocity and last-seen enemy position as point estimates, without calibrated confidence. Fog shooting, when selected, consumes that estimate. No hidden simulator state, opponent intentions or fabricated Bayesian probabilities enter selection. Context and memory reset when simulation ticks decrease; each seat owns its own state.

## 3. Goal

Named skill purposes below explain local preferences. Ordered control flow and channel claims resolve their conflicts. These labels are author/library interpretations; source code alone cannot recover a human's original reasons or a unique global reward function.

## 4. Skill

All skills terminate for this decision unless their contract explicitly retains state. Non-stopping steps compose actions; first feasible hook request claims the hook channel. Movement routines set the requested destination; later permitted movement can replace it. A rejected request does not establish a successful game outcome.

**skill.alive — Participation.** Whether self is alive. A false result can end selection without actions.

**skill.observe — Situation and belief update.** Classify low health at retreat_percent; estimate visible velocity from samples at least eight ticks apart; retain last-seen target and dodge side. Estimates are uncalibrated, not probabilities.

**skill.simple_movement — Support and survival.** River or low health requests home; otherwise take a lane five tiles inside the bank, eight tiles vertically offset from the lowest-ID living teammate. Recomputed every decision.

**skill.reserve_when_hurt — Survival.** Low health claims the hook channel without emitting a new hook request. Does not cancel an existing flight.

**skill.rescue — Teammate availability.** Try the nearest living teammate on an enemy hook or below/equal 60% health in the river. Coordinated mode elects one eligible rescuer by distance then ID; success holds position and starts a ten-tick rescue commitment. Returns true only when a hook request is emitted.

**skill.nearest_shot — Independent pressure.** Try the nearest visible eligible enemy at its current position, within a conservative fifty-five-tile envelope and five-tile ally clearance. Do not try a farther target when blocked.

## 5. Strategy

The block below is normative executable text. DO attempts a skill and continues; TRY finishes the decision only when the skill reports success; STOP IF/UNLESS ends the decision on its condition. FINISH preserves actions already composed. Ordering is an explicit conditional preference over resource use, not a scalar reward. Skill parameters override only their named contracts. Prose supplies the ontology and interpretation; the supported compiler consumes this block and the pinned skill definitions.

```policy-ir
POLICY loom_grounded
BINDINGS pudge-skills-v1 f7cea6a0203afec157813d7a385f95af862e8240113dfcf1445b851402dd96ae
STOP UNLESS alive
DO observe(retreat_percent=35)
DO simple_movement
DO reserve_when_hurt
DO rescue(coordinated=False)
DO nearest_shot
```

## 6. Execution

Generate straight-line Python calls and explicit conditional returns against the pinned skill library. No original complete policy or embedded source is executed. A code-derived extraction must account for the whole supported AST; unknown statements are rejected. Reproducibility requires this policy, binding content hash, engine version, observation history and initial memory. Real-time network scheduling is outside an accelerated simulator comparison.

## 7. Update

Revise a named skill parameter or preference order in this text; generate a candidate; extract its executable behavior back to text; regenerate; compare full action histories and completion scores. Keep held-out seeds separate from candidate selection and preserve failed attempts. Performance evidence may propose a strategy/skill change; it does not recover an author's rationale or authorize unrecorded goal changes. Changes inside a skill require a new binding hash and new behavioral evidence. General ontology induction and unrestricted code extraction remain outside this bounded grammar.
