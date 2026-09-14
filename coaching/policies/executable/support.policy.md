# support_grounded: orthogonal policy IR

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

**skill.economy — Long-term capacity.** Spend skill points on distance, speed, damage, then radius; buy available free wards, a low-health flask, repeated reach/boots ranks and an unoccupied hook buff. Decisions use confirmed inventory for later ward trips.

**skill.combat — Survival and local combat.** Enable rot only for favorable close combat away from river/low health. Compare own health plus forty against nearest target, target <=120 health, or being stranded on enemy land. Attack within 5.5 tiles when favorable; mark hostile/ally rot exposure for movement.

**skill.sustain_rescue — Teammate availability.** While safely on our bank, hold position during our friendly rescue flight or its ten-tick commitment. Higher danger/low health interrupts. Returns true while holding.

**skill.rescue — Teammate availability.** Try the nearest living teammate on an enemy hook or below/equal 60% health in the river. Coordinated mode elects one eligible rescuer by distance then ID; success holds position and starts a ten-tick rescue commitment. Returns true only when a hook request is emitted.

**skill.blink_defense — Survival.** If blink is ready, escape the river toward our bank or move away from an incoming hook within the actual twenty-tile blink disk. Never chase offensively.

**skill.hooked — Control availability.** Whether an enemy hook currently restricts our control; a true result may end selection after defensive actions.

**skill.follow_up — Team conversion.** Try a visible enemy carried by a friendly hook, aiming between victim and reeler. Claims hook only if the throw primitive accepts its checks. End after one request.

**skill.close_shot — Immediate pressure.** Try the nearest visible enemy within twenty tiles while outside the river.

**skill.intercept_hook — Defense.** Try a hostile flying hook within fourteen tiles. This attempts an interception; it does not guarantee one.

**skill.swimming_shot — Team conversion.** Try the nearest eligible enemy in the river.

**skill.aimed_shot — Pressure under motion uncertainty.** Try the nearest eligible enemy within current reach plus five. Lead its sampled velocity by lead times Chebyshev distance divided by thirty plus speed rank. Exclude an aim segment within five tiles of the center.

**skill.rune_shot — Resource acquisition.** Outside the river, try an observed rune within a thirty-six-tile square, in observation order. First feasible throw wins.

**skill.fog_shot — Exploration under partial observation.** When no eligible enemy is visible, project the last-seen position using velocity; after ninety-six ticks use a bank-edge horizontal prior. Clamp to the enemy bank and arena. This is an uncertain speculative shot, not an observed enemy.

**skill.tactical_movement — Survival, conversion and positioning.** Priority: flee foreign rot; dodge hook threat; leave river; retain melee; approach caught target when healthy; retreat when low/unfavorable close combat; visit shop with spendable gold; otherwise fish in ID-ranked lanes with deterministic juke. bank_margin sets distance behind the play boundary; lane_spacing separates teammates symmetrically about y=64. A soon rune redirects the lane. Existing blink suppresses walking.

**skill.ward — Information gathering.** With confirmed modern ward inventory on our bank, place across the river within thirty-two tiles; otherwise approach placement range only when not busy. Does not infer inventory from a purchase request.

## 5. Strategy

The block below is normative executable text. DO attempts a skill and continues; TRY finishes the decision only when the skill reports success; STOP IF/UNLESS ends the decision on its condition. FINISH preserves actions already composed. Ordering is an explicit conditional preference over resource use, not a scalar reward. Skill parameters override only their named contracts. Prose supplies the ontology and interpretation; the supported compiler consumes this block and the pinned skill definitions.

```policy-ir
POLICY support_grounded
BINDINGS pudge-skills-v1 f7cea6a0203afec157813d7a385f95af862e8240113dfcf1445b851402dd96ae
STOP UNLESS alive
DO observe(retreat_percent=40)
DO economy
DO combat
TRY sustain_rescue THEN FINISH
TRY rescue(coordinated=True) THEN FINISH
DO blink_defense
STOP IF hooked
DO follow_up
DO close_shot
DO intercept_hook
DO swimming_shot
DO aimed_shot(lead=1.0)
DO rune_shot
DO fog_shot
DO tactical_movement(bank_margin=16, lane_spacing=24)
DO ward
```

## 6. Execution

Generate straight-line Python calls and explicit conditional returns against the pinned skill library. No original complete policy or embedded source is executed. A code-derived extraction must account for the whole supported AST; unknown statements are rejected. Reproducibility requires this policy, binding content hash, engine version, observation history and initial memory. Real-time network scheduling is outside an accelerated simulator comparison.

## 7. Update

Revise a named skill parameter or preference order in this text; generate a candidate; extract its executable behavior back to text; regenerate; compare full action histories and completion scores. Keep held-out seeds separate from candidate selection and preserve failed attempts. Performance evidence may propose a strategy/skill change; it does not recover an author's rationale or authorize unrecorded goal changes. Changes inside a skill require a new binding hash and new behavioral evidence. General ontology induction and unrestricted code extraction remain outside this bounded grammar.
