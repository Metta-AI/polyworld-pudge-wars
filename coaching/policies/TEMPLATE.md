# [Policy name]

**Policy:** [stable ID], version [version]. **Format:** semantic policy text 0.1.

**Origin:** [code/trace references, human intent, or authored proposal]. **Grounding:** [implemented / specified but unbound / unresolved]. **Scope:** [domain, behavior covered, lifetime].

**Intent:** [A short paragraph a human coach could recognize.]

## 1. Situation

Name entities and relation signatures. For each important situation, give its meaning, observable grounding, quantitative dimensions and units, boundary, missing-information behavior and affordances. Define temporal concepts through start, transition, end and expiry events. Mark unresolved features.

## 2. Belief

For each uncertain claim: proposition or random variable; alternatives; conditioning evidence; probability/interval/unknown; provenance; scope; expiry; update model. State dependencies between beliefs. For opponent models, distinguish attributed beliefs, goals and available skills. Say explicitly if this policy has no belief model.

## 3. Goal

Name desired outcomes and rationales. State contextual precedence, incomparable goals, constraints and who/what can revise the order. Distinguish extracted behavior from an author-proposed explanation.

## 4. Skill

For each competence: ID; initiation; readable internal policy; bound participants; success, failure and timeout termination; resource ownership; interruption/retry rules; required observations; execution binding or missing implementation.

## 5. Strategy

```text
STRATEGY [stable ID]
WHEN [grounded situation or explicit belief condition]
PREFER [skill] OVER [alternative]
FOR [goal]
BECAUSE [named rationale]
UNLESS [exception]
COMMIT [duration, target and scope of intention]
RECONSIDER [interruptions and changed evidence]
ORIGIN [source]; SCOPE [lifetime]
```

State emergency precedence, goal/strategy arbitration, concurrent channels, commitments, ties, conflicts, unknowns and total fallbacks. If weights are used, define their scale and how they combine without overriding higher-order commitments.

## 6. Execution

Name the controller/artifact and version if it exists. Describe the observable action contract, persistent execution state, failure reporting and realization freedoms. List missing bindings. Separate attempted, accepted and successful actions.

## 7. Update

For each revision mechanism: trigger and evidence; target layer and IDs; allowed revision; protected meanings/behavior; dependency impact; disconfirming example; application scope. Keep encouragement, preference feedback, empirical evidence and goal changes distinguishable.

## Contrasting situations

Write examples and near-misses that determine a selected skill, its rationale and its termination. Include an unknown-state case, a conflicting-goal case, an interrupted commitment and a case where the representation cannot yet decide without a missing binding.

## Generation brief

When asking a model to fill this template, supply the domain definitions, source policy and traces if available, and the coaching intent. Request all seven layers in text. Preserve source behavior in an extraction; label improvements as proposals. Require every named condition to resolve to a definition, every preference to have a declared arbitration meaning, and every skill to expose termination. Ask the model to identify unresolved concepts and behavioral degrees of freedom. Do not reward plausible invented beliefs or rationales as faithful extraction.
