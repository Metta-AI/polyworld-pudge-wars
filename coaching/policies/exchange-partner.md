# Exchange partner: a proposed policy ontology

**Policy:** `policy.exchange_partner`, version 1. **Format:** semantic policy text 0.1.

**Origin:** authored from the coaching intent “think of the game as a continuous unit.” **Grounding:** proposed text, with several unbound observations and skills. **Scope:** team hook exchanges in Pudge Wars. This policy is not running in the demo.

**Intent:** Treat a throw as part of a team exchange. Prepare a joint opportunity, convert it when possible, and reposition for the next exchange when it ends. A missed hook changes the phase of our cooperation rather than erasing its purpose.

## 1. Situation: the unit is an exchange

**Types and relations.** Players are participants; hooks are actions with owners and possible victims; regions locate players; exchanges group temporally related opportunities. `teammate_of(Player, Player)` and `carried_by(Player, Hook)` are relations. `participates_in(Player, Exchange)`, `focus_of(Player, Exchange)` and `phase_of(Exchange, Phase)` give the exchange structure. One coached agent maintains at most one team exchange at a time in this first ontology.

**`situation.exchange`.** A bounded episode with a stable identity, participant set, optional focus target, start event and phase. It begins on an explicitly designated target, or on an observed team hook launch when there is no current exchange. A launch with an unknown aim creates an exchange without a bound focus; a later observed catch can bind it. An explicit target designation replaces the previous focus and records the change.

The phases are `prepare`, `attempt`, `convert`, `reset` and `closed`:

- `prepare`: a focus was designated but no team hook has launched in this exchange.
- `attempt`: a team hook is in flight; a new eligible team launch in this phase joins the same exchange.
- `convert`: a participating teammate carries a visible enemy. Bind that caught enemy as the immediate conversion target. A second catch is resolved by earliest observed catch event, then stable target ID; this is an explicit initial simplification.
- `reset`: all tracked team throws have been observed to end, no teammate carries a target, and no observed kill resolved the focus. Reposition for another exchange; do not infer a miss solely because a hook disappeared behind fog.
- `closed`: an observed kill resolves the focus, reset positioning completes or fails, the coach replaces the exchange, or the exchange expires. Self death also closes it.

Resolve simultaneous events in this order: closure or explicit replacement, confirmed catch, remaining tracked throw, then reset. If a catch ends while another tracked throw continues, return to attempt. Launches during reset reopen attempt within the same exchange and cancel the old reset commitment. This prevents one resolved throw from ending a still-active team attempt.

**Initial authored bounds:** expire an exchange 256 simulation ticks after its start; preserve an uncertain last-seen hook event for at most 32 ticks before closing that unresolved attempt as unknown. These are design parameters, not measured optimal timings. Missing observations never count as confirmed success.

**`situation.catch_window`.** A teammate carries a visible living enemy and the local hook skill estimates a feasible throw at that enemy. Dimensions include target distance, ally clearance, target motion and remaining catch duration. Source hook/victim relations exist in the current observation; predicting catch duration and intercept feasibility remains unbound. Unknown feasibility excludes a follow-up until resolved.

**`situation.retreat_required`.** Self is in the river, or alive below 35% health. This reuses an explicit starting boundary, with homeward escape taking precedence over offensive movement. The ontology can later distinguish forced river recovery from voluntary retreat; their current union is an authoring choice.

**`situation.urgent_rescue`.** A living teammate is visibly carried by an enemy hook, or is in the river at or below 60% health, and the rescue skill has a feasible throw. The danger recognition is grounded in existing observations; upgraded feasibility remains a skill contract.

**`affordance.advance`.** Advancing is physically possible, a route on our bank and return route are known, self is not retreat-required, and the joint belief that every relevant enemy lacks a punish opportunity throughout the maneuver exceeds 0.8. The risk envelope covers the advance and return, not just the next instant. Unknown enemies or an unavailable joint estimator make the affordance unknown. `hook_on_cooldown(enemy)` is one contributing fact, not the whole affordance.

**`situation.reset_position`.** A designated support position on our bank relative to the teammate, with a clear prospective throwing lane and a known return route. The current `follow` primitive is a possible crude realization; claiming the stronger positioning contract requires evaluating lane and route geometry.

## 2. Belief: uncertain opportunity and opponent intent

**`belief.hook_recovery(enemy)`**

- Variable: time until this opponent's next eligible hook cast, conditional on observed launches, current time and known mechanics.
- Representation: an interval or probability distribution; expiry follows observation age and uncertainty about cooldown modifiers.
- Evidence: timestamped observed casts and relevant visible equipment/state. Distinguish an attempted cast from one observed to launch.
- Update: a new observed cast resets the recovery estimate; time advances it; unseen modifiers widen uncertainty. Specify a likelihood/mechanics model before attaching numerical probabilities.
- Grounding: estimate is unbound; current value is unknown. It cannot presently justify `affordance.advance`.

**`belief.bottom_lane_bait(enemy)`**

- Proposition: this opponent's bottom-lane exposures are intended to elicit a hook they can evade and punish.
- Alternatives: baiting, ordinary positioning, retreat, or an unmodeled explanation.
- Evidence: repeated exposure → our throw → their evasion → punish sequences, and counterexamples where that sequence does not occur. A single exposure is insufficient.
- Opponent model: hypothesized belief that we will throw, goal of spending our hook, and repertoire containing evasion followed by punishment. All three are attributed hypotheses.
- Current assessment: unknown; no fabricated observations or empirical probability.
- Strategic effect: none until a defined evidence model warrants a bounded estimate. An explicit coach instruction can independently authorize a cautious tactic without pretending to establish the opponent's intent.

**`belief.punish_window`** is the joint prediction used by `affordance.advance`. It conditions on each opponent's reachable actions, recovery uncertainty, route and maneuver duration. Independence between opponents is not assumed. Its estimator is unresolved; this makes the aggressive-advance branch unavailable in this text version.

## 3. Goal: preserve the ability to cooperate

**`goal.team_conversion`.** Convert a shared catch into team advantage. **`rationale.shared_window`:** a caught enemy offers a bounded opportunity to combine pressure.

**`goal.team_availability`.** Keep participants able to contribute to the next exchange. **`rationale.future_exchange`:** a failed throw need not also become a lost teammate.

**`goal.local_pressure`.** Take a favorable independent shot when team commitments leave one available. **`rationale.use_openings`:** cooperation can include opportunistic offense.

The preference order is conditional:

- During `situation.retreat_required` or an unfinished retreat intention, team availability outranks conversion and local pressure for conflicting actions.
- Otherwise, an urgent feasible rescue outranks conversion for use of our hook.
- During a feasible catch window, conversion outranks independent pressure for use of our hook.
- During reset, future availability outranks pursuing the old target with movement.
- In other situations, these goals remain partially ordered. The declared fallback below settles the remaining choices.

This orders outcomes and conflicting choices. It does not assert that every action labeled “team availability” is good, or that a doomed rescue automatically satisfies the goal.

## 4. Skill: bounded competences

**`skill.follow_up` — convert the current catch.** Initiate when `situation.catch_window` is true. Bind the exchange and caught target. Maintain a feasible aim and attempt one hook at that target; do not substitute a closer enemy. Succeed when the throw has been observed to launch, recording separately whether it hits. Fail when the target becomes ineligible or feasibility is lost. Terminate on success, failure, catch end or 32 ticks after initiation. Owns the hook channel. Interrupt for retreat-required or urgent rescue; an already launched hook cannot be recalled. Realization: unbound option; the current straight-hook primitive supplies only part of it.

**`skill.reset_exchange` — prepare the next opportunity.** Initiate in reset. Move to `situation.reset_position`; retain the exchange identity while moving. Complete once within two tiles of that position for eight successive ticks. Fail after 64 ticks or if the support position cannot be established; close the exchange with that failure recorded. Owns movement. Interrupt for retreat-required, self death, explicit replacement of the exchange, a newly confirmed catch or a new team launch. Realization: unbound temporal option and position estimator.

**`skill.advance` — use a recovery window.** Initiate only when `affordance.advance` is true. Follow the designated bank route while maintaining the return envelope; do not cross the river. Complete at the designated endpoint. Fail or retreat when the affordance ceases to be true; expire after 32 ticks. Owns movement. Realization: unbound route/risk controller. The present unknown beliefs exclude this skill.

**`skill.rescue` — attempt the urgent save.** Initiate in urgent-rescue while not retreat-required. Bind the endangered teammate, attempt one feasible hook, and finish when its launch is observed. Fail if the target/feasibility disappears or after 32 ticks. Owns hook. Interrupt for retreat-required. Realization: the existing rescue selector/primitive plus unbound correlated launch tracking.

**`skill.retreat` — recover participation.** Initiate when retreat-required. Request homeward movement and reserve new offensive hooks. Finish after leaving the river and recovering to at least 50% health; re-evaluate the return route continuously. End on self death. Timeout after 128 ticks with a failure report and renewed selection; timeout does not make remaining danger disappear. Owns movement and hook. Realization: existing home/reservation primitives plus unbound option state and route checking.

**`skill.support` — keep a support position.** Initiate when self is alive and a support destination is known. Request movement there for one decision, then allow fresh selection. Owns movement. If the stronger reset-position estimator is unbound, use the explicitly weaker current teammate-lane position and label the realization accordingly.

**`skill.go_home` — a movement fallback.** Initiate while alive with known home coordinates. Request homeward movement for one decision, then allow fresh selection. Owns movement and makes no health-recovery commitment. Realization: the existing home primitive. A missing home coordinate produces an execution-contract failure and no new movement request.

**`skill.independent_shot` — use a free opportunity.** Initiate with an eligible visible enemy and a feasible straight-hook attempt. Select the nearest candidate with the current primitive's distance/ID tie-break and corridor restriction, attempt one hook, then terminate this decision. Owns hook. Feasibility is rechecked at execution. This competence alone does not acquire a commitment to pursue a fleeing target.

**`skill.reserve_hook` — wait one decision.** Initiate while alive; emit no new hook command. Owns hook for this decision and then terminates. This is also the explicit fallback when a preferred throw has no eligible realization.

## 5. Strategy: preserve the exchange, re-evaluate its means

```text
STRATEGY strategy.convert_together
WHEN situation.catch_window
PREFER skill.follow_up OVER skill.independent_shot
FOR goal.team_conversion
BECAUSE rationale.shared_window
UNLESS situation.retreat_required or situation.urgent_rescue
COMMIT to this exchange and caught target until skill termination

STRATEGY strategy.reset_after_attempt
WHEN the active exchange enters reset
PREFER skill.reset_exchange OVER skill.advance
FOR goal.team_availability
BECAUSE rationale.future_exchange
COMMIT to reset until completion, timeout or a declared interruption

STRATEGY strategy.use_recovery_window
WHEN affordance.advance AND no reset commitment is active
PREFER skill.advance OVER skill.support
FOR goal.local_pressure
BECAUSE rationale.use_openings
RECONSIDER whenever the risk envelope ceases to be established
```

**Arbitration.** Death ends all intentions and emits no action. Retreat-required initiates retreat, which owns both channels until its stated termination, including recovery to 50% health. Otherwise urgent rescue preempts hook use, then a confirmed catch preempts an offensive hook intention. Reset retains movement until its termination or listed interruption; advance can retain movement only while its affordance remains true. Explicit target replacement cancels the old exchange commitments, while an unfinished retreat remains in force. No preference weights are used.

For a free channel, apply the rules above. Movement fallback is `skill.support`, then `skill.go_home`. Hook fallback is reserve while a teammate's empty hook is observed in flight; otherwise try independent-shot and then reserve. A continuing intention owns its channels; other eligible skills can run on disjoint channels. Conflicting incomparable selections or cycles produce a conflict record and the channel fallback, without overriding retreat or rescue precedence.

**Intention example:** “I am resetting exchange E after our missed throw. I am keeping movement committed to our next support position. A newly confirmed catch or retreat-required state would make me reconsider.” This is a public policy-level account, linked to the selected skill and its actual state.

## 6. Execution: preserve the contract across implementations

Bindings are deliberately incomplete. A code generator must supply an exchange tracker, bounded option memory, support-position geometry, and a launch event/receipt that can be correlated with an attempt. The existing unsequenced acceptance echo is insufficient for the promised attribution.

Each realization must report the semantic IDs it implements and distinguish skill initiation, chosen action, accepted command, observed launch and game outcome. It may use a behavior tree or another controller, but cannot replace “complete reset” with one arbitrary movement step without narrowing the contract explicitly.

Until the missing bindings are supplied, this is a policy specification with observable commitments. It is not a deployable controller. Unknown opponent beliefs already have a defined effect: exclude advance rather than invent certainty.

## 7. Update: experience can challenge the representation

**`update.recovery_estimate` → belief.** New observed launches and contradictory timing revise the recovery estimate through the declared estimator. Preserve goal ordering and skill identity. Without that estimator, retain the observation as evidence and leave the estimate unknown.

**`update.follow_up_preference` → strategy.** Attributed human criticism or examples of failed coordination propose a revision to `strategy.convert_together`. State the intended behavioral difference and preserve retreat/rescue precedence unless the instruction explicitly revises those priorities. Separate failure to aim, failure to select the skill, and a mistaken strategic premise.

**`update.exchange_definition` → situation ontology.** Repeated cases that require retaining team intent across what the current tracker calls two exchanges motivate a split, merge or changed boundary. Supply positive and negative example sequences, migrate active commitments, and identify every affected skill and strategy. This is a model change, not a confidence adjustment.

**`update.skill_realization` → skill or execution.** A missed target can motivate aim-controller tuning; repeated inability to reach reset positions can motivate a new navigation competence. Preserve the declared initiation and termination contracts or revise them explicitly. A new skill needs its own examples and binding.

**`update.goal_order` → goal.** “Saving me matters more than preserving your own life” proposes a visible change to the conditional preference order. Record the exact exception, its scope and rationale. Do not infer this new value from a win, a loss or generic praise.

“Good job, keep going” records encouragement at the current exchange. “That reset after our miss was exactly right” additionally attributes a preference to `skill.reset_exchange`. Further learning depends on an explicit update rule.

## Reading the text against situations

| Situation | Required interpretation |
|---|---|
| Healthy, feasible teammate catch, nearer unrelated enemy | Bind the caught enemy and prefer follow-up for hook use. |
| Same catch, self below 35% health | Retreat preempts conversion. |
| Healthy catch plus feasible urgent rescue | Rescue takes the hook; movement is selected separately. |
| Our attempt ends as a confirmed miss | Enter reset, retaining the exchange identity and reset commitment. |
| Old target moves temptingly closer during reset | Continue reset movement; proximity alone does not cancel the commitment. |
| Enemy hook disappears into fog | Preserve uncertainty; do not label it a miss or a safe advance window. |
| One opponent is known to be cooling down, another is unobserved | Advance is not established; use the declared fallback. |
| A coach challenges what counts as an exchange | Propose an ontology revision and review its dependent contracts. |

These are authored predictions to test against future realizations. None is presented as a measured improvement in win rate.
