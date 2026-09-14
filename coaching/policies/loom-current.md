# Loom: the current reactive policy, represented in text

**Policy:** `policy.loom_current`, version 1. **Format:** semantic policy text 0.1.

**Origin:** extracted from `initial_policy`, `facts`, `hook_block` and `decide` in [policy.py](../policy.py), September 9, 2026. This describes the initial policy, before coaching edits. **Grounding:** existing controller; the text itself has no parser. **Scope:** movement and hook decisions.

Compiled initial artifact fingerprint: `cde50eaea0d6de142467e34cb8bc4c8cbd648fd6af13d7c371a4446f01fdad23`.

## 1. Situation

**Entities.** A player has an identity, team, position, health, maximum health, alive flag and home position. A hook has an owner, team, flight flag and optional victim. The coach is a designated teammate. These roles resolve within the current match.

**Observation boundary.** This policy consumes its team-visible player and hook lists plus its own state. Definitions about visible entities are evaluated on that observation. It does not infer where an unseen enemy is.

**`situation.low_health`.** Self health divided by maximum health is strictly below 0.35. The boundary is in health-fraction space: exactly 35% does not qualify. Grounding: `low_health`. Affords choosing homeward movement and reserving a hook; it does not imply either action succeeds.

**`situation.in_river`.** The engine reports self `in_river`. Grounding: the engine's terrain/state predicate. Affords requesting movement to the home position. This policy does not independently infer terrain from the appearance of the arena.

**`situation.eligible_enemy`.** A currently visible player is alive, on the other team, and has no active shield. Order eligible enemies by Euclidean distance from self, breaking equal-distance ties by entity ID. Distance uses the observation's tile coordinates.

**`situation.ally_danger`.** A living teammate is the victim of a visible enemy hook, or is in the river with health at or below 60%. Order endangered teammates by distance and then entity ID. This is the exact implemented criterion; it is narrower than all possible forms of danger.

**`affordance.straight_hook(target)`.** The target exists in the relevant candidate set, the engine reports our hook ready, no visible hook is owned by self, and distance to the target is at most 55 tiles. No other living teammate may be less than 5 tiles from the closed segment joining self to target. These are the demo primitive's feasibility checks, not a guarantee of legal engine execution or a hit. Exactly 55 tiles is within the envelope; exactly 5 tiles of ally clearance passes.

**`situation.teammate_lane`.** Select a position five tiles behind our bank's play boundary. Use the living coach's vertical coordinate; if the coach is unavailable, use self's. Offset that coordinate by +8 below 64 and by −8 otherwise, then clamp both coordinates to [8, 119]. This is a prescribed support position, not an estimate of an optimal throwing lane.

## 2. Belief

**No uncertain world model is represented in this controller.** It reacts to the available observation. It keeps no opponent tendency, hidden-state distribution, predicted future trajectory or probability of hook success. The small runtime memory records the last selected rule and does not influence selection.

“No eligible enemy is visible” can suppress an offensive hook. It is not a belief that all enemies have disappeared. The separate working model in `reasoning.py` can guide a proposed replacement policy; its confidence fields are not inputs to this initial controller's decisions.

## 3. Goal

The code supplies labels `survive`, `save_teammate` and `coordinate_with_teammate`. It does not implement a general outcome preference model. We can extract the following **contextual behavioral order** from its rule priorities:

- In movement: river escape precedes low-health retreat, which precedes teammate positioning.
- In hook use: low-health reservation precedes a feasible rescue, which precedes independent offense.

Consequently, at low health this policy reserves the hook even when a rescue is available. There is no extracted global ordering of all possible outcomes, and no scalar optimization of the labels.

**Named rationales:** `rationale.stay_available` (“preserve future participation”), `rationale.help_teammate` (“protect a teammate in the encoded danger states”), and `rationale.maintain_pressure` (“take an available offensive shot”). These are author interpretations of the rule purposes, not recovered causal beliefs or empirically validated explanations. The existing independent-shot rule's goal label says coordination even though its target choice ignores teammate catches.

## 4. Skill

These are one-decision competences. Their commands can have effects that continue in the engine after the decision ends. The policy reselects at the next observation.

**`skill.go_home`**

- Initiation: self is alive and a movement rule selects this competence.
- Internal policy: request movement to the observed home coordinates.
- Termination: this decision emits the request. Arrival is not checked by this skill.
- Resources: movement. Higher-priority movement rules can replace it on the next decision.
- Realization: existing `home` primitive.

**`skill.take_teammate_lane`**

- Initiation: self is alive.
- Internal policy: request movement to `situation.teammate_lane`.
- Termination: this decision emits the request; recompute at the next observation.
- Resources: movement. Realization: existing `follow` primitive.

**`skill.reserve_hook`**

- Initiation: self is alive.
- Internal policy: select the hook channel without issuing a new hook command.
- Termination: this decision. It neither cancels an existing hook nor stops movement.
- Resources: hook. Realization: existing `hold_hook` primitive.

**`skill.rescue`**

- Initiation: the nearest `situation.ally_danger` candidate satisfies `affordance.straight_hook`.
- Internal policy: request a hook at that teammate's current position.
- Termination: this decision emits a request; rescue success is not inferred.
- Resources: hook. Realization: `endangered_ally` selector and `hook` primitive.

**`skill.independent_shot`**

- Initiation: the nearest `situation.eligible_enemy` satisfies `affordance.straight_hook`.
- Internal policy: request a hook at its current position, without predictive aim.
- Termination: this decision emits a request.
- Resources: hook. Realization: `nearest_enemy` selector and `hook` primitive.

For rescue and offense, the controller first picks the nearest candidate and then checks feasibility. A blocked nearest target does not cause a search for the next-nearest target within that skill.

## 5. Strategy

**Selection:** evaluate movement and hook independently. In each channel, the first feasible rule wins in the order below. False conditions and infeasible throws fall through. If self is dead, emit no action. If no hook rule applies, emit no hook command. Skills selected in different channels can run together.

```text
STRATEGY strategy.escape_water
WHEN situation.in_river
PREFER skill.go_home OVER skill.take_teammate_lane
FOR survive
BECAUSE rationale.stay_available

STRATEGY strategy.retreat
WHEN situation.low_health AND NOT situation.in_river
PREFER skill.go_home OVER skill.take_teammate_lane
FOR survive
BECAUSE rationale.stay_available

STRATEGY strategy.support_position
WHEN neither movement rule above applies
SELECT skill.take_teammate_lane
FOR coordinate_with_teammate

STRATEGY strategy.reserve_when_hurt
WHEN situation.low_health
PREFER skill.reserve_hook OVER skill.rescue AND skill.independent_shot
FOR survive

STRATEGY strategy.rescue
WHEN NOT situation.low_health AND skill.rescue is applicable
PREFER skill.rescue OVER skill.independent_shot
FOR save_teammate
BECAUSE rationale.help_teammate

STRATEGY strategy.independent_shot
WHEN neither hook rule above applies AND skill.independent_shot is applicable
SELECT skill.independent_shot
FOR coordinate_with_teammate
BECAUSE rationale.maintain_pressure
```

**Intention:** selection is committed for one decision only. A previous selection does not win ties or survive as a tactical intention. There are no simultaneous preferences within a channel, no weights and no unresolved ties beyond the stated target ordering.

## 6. Execution

The adapter sends `walk_to` and `hook_to` commands to the native engine. It requests rather than guarantees movement, a legal cast or a hit. The engine maintains movement, casting and hook-flight state. A new observation can invalidate a decision.

An omitted hook command means no new request. A rejected throw does not cause an immediate second action within this decision. The next observation triggers normal selection again. Execution traces record rule selection and attempted action; the existing engine acceptance echo lacks a per-command correlation ID, so it cannot prove which overlapping decision a receipt belongs to.

The controller does not choose purchases, blink, melee or a general plan. Any automatic engine behavior remains outside this policy's authored decisions.

## 7. Update

No experience-driven revision occurs inside `decide`. A coach or generator can submit a separately versioned replacement. The application compiles that replacement and activates it at a decision boundary. Match and durable lessons have separate lifetimes.

For example, “retreat below 50%” changes the boundary of `situation.low_health`. Because both retreat and hook reservation depend on that situation, both can change. Calling this a change to movement alone would be an inaccurate representation of the dependency graph.

A successful hook does not update a belief, acquire a skill or validate one of the author-interpreted rationales. Those require additional update rules and evidence.

## Contrasting readings

| Situation | Predicted policy behavior |
|---|---|
| 34% health on our bank, endangered teammate, hook ready | Request homeward movement and reserve the hook; do not rescue. |
| Exactly 35% health, feasible rescue | Take the teammate lane and attempt the rescue. |
| In the river at 80% health, feasible enemy target | Request homeward movement and attempt an offensive hook concurrently. |
| Healthy; nearest enemy's corridor blocked, farther enemy clear | Do not attempt an offensive hook; this skill does not try the farther target. |
| Coach catches someone while another enemy is closer | The initial policy has no catch preference; independent targeting still applies. |

These cases expose behavior the text must preserve even when a more appealing explanation would suggest otherwise. Extracting this document is distinct from authoring a better policy.

All five predictions were checked against the source controller on constructed observations on September 9, 2026. They are checks of the textual account, not a proof of equivalence for every possible history.
