# Proposed ontology revision: clear a teammate-safe hook lane

Status: **specified but not executable**. This is a next research hypothesis, not an evaluated policy. Origin: author proposal following the lane-spacing experiments. Their scores do not establish the mechanism proposed here.

## 1. Situation

**situation.friendly_hook_corridor_obstructed** concerns the selected visible enemy, our intended throw segment and visible teammates. Ground it by exposing the existing `Context.throw` ally-clearance check, including predicted teammate position, hook radius/reach, shield exception and observation limits. Preserve why a throw was withheld: an unavailable hook, an obstructed corridor and an uncertain target are different situations.

The geometric obstruction test exists inside execution. Its independent predicate, rejection-reason record and use in strategy are **unbound**. Missing enemy visibility remains unknown; it must not manufacture a target or an occlusion claim.

## 2. Belief

Use the existing short-horizon velocity estimates to estimate whether the corridor will clear. Do not turn geometric clearance into a probability of a hit. A calibrated clearance belief would need separately specified evidence and update rules.

## 3. Goal

Prefer a teammate-safe opportunity to apply pressure over a speculative obstructed throw. Survival and an urgent rescue may interrupt lane clearing. These are proposed preferences, not reasons inferred from the original Base author.

## 4. Skill

**skill.clear_hook_lane** initiates only when a visible intended target is obstructed, our hook is usable, and a safe lateral movement is available. It owns movement, takes a bounded lateral step on our bank, and rechecks observed geometry. It terminates when a safe corridor opens, the target disappears, a short timeout expires, or a defense/rescue condition interrupts it. Do not throw merely because movement was requested.

The movement choice, safe-step predicate, timeout and interaction with rescue commitment are **unbound**. They require explicit definitions and tests before code generation can claim to implement this skill.

## 5. Strategy

```text
WHEN situation.friendly_hook_corridor_obstructed is true
PREFER skill.clear_hook_lane OVER unconditional idle lane spacing
FOR goal.teammate_safe_pressure
UNLESS urgent rescue or immediate defense applies
COMMIT only while the same target and obstruction remain relevant
```

This strategy is deliberately conditional. It does not globally increase lane spacing because one averaged experiment looked promising.

## 6. Execution

Expose the existing rejection reason, then bind a small repositioning option. Record the situation, selected option, requested action and observed result separately. A request acceptance is not evidence that the corridor cleared or the hook hit.

## 7. Update and disconfirmation

Before evaluating match scores, require a blocked visible-target scenario to produce a safe lateral request, a clear-lane scenario to preserve the existing action, and low-health/rescue scenarios to retain their interruptions. Require progress or explicit timeout rather than indefinite lateral oscillation.

If the new distinction predicts behavior correctly but does not improve fresh-game results, revise the strategy or skill hypothesis. If it fails to predict when clearance is available, revise the situation/belief model. Do not silently change the goal. The previous global-spacing score is motivation to investigate, not evidence sufficient to activate this proposal.
