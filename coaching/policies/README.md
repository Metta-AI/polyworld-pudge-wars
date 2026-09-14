# Policies as semantic reasoning in text

**Status:** Draft text format, version 0.1. **Created:** 2026-09-09.

The artifact we want to author is a policy expressed through the concepts, distinctions, preferences and commitments that make its behavior intelligible. A coding agent can later realize that artifact in different controllers. A coach should be able to edit its meaning without describing a code change.

Start with [Loom's current policy](loom-current.md) for an account grounded in existing code, or [the exchange partner](exchange-partner.md) for a richer proposed ontology. Use the [template](TEMPLATE.md) to generate another policy. The [executable grounding](executable/grounding.md) now connects a bounded subset to [symbolic generation, extraction and native game evaluation](../symbolic/README.md). The richer proposal documents themselves still contain unbound concepts and are not directly executable by the coaching application.

## What the representation has to do

The seven layers are useful because they distinguish seven different questions. Their composition needs named relationships and explicit decision semantics. A set of evocative descriptions is a starting point; a policy contract also states what follows from those descriptions.

| Layer | Its question | Textual unit |
|---|---|---|
| 1. Situation | What exists, and what can I do here? | Types, relations, measurements, situations and affordances |
| 2. Belief | What might be true, given what I have observed? | Propositions/distributions, evidence, uncertainty and opponent models |
| 3. Goal | Which outcomes matter more in this context? | Outcomes, conditional partial orders and named rationales |
| 4. Skill | What competence can I invoke? | Initiation, internal policy, termination and resources |
| 5. Strategy | Which eligible skill should I choose, and why? | Conditional preferences, exceptions and commitments |
| 6. Execution | What realizes that competence? | A controller reference and its observable contract |
| 7. Update | What experience would change this policy? | Revision rules identifying their target layer and evidence |

An ontology supplies the shared vocabulary and relationships across the stack: a situation **affords** a skill; a belief **concerns** a situation; a skill **pursues** a goal; a strategy **prefers** one skill to another **because of** a rationale; an intention **commits to** a skill instance; an update **revises** a named definition. This graph is expressed as readable text with stable identifiers.

An ontology alone describes a world. The ontology plus these behavioral commitments represents a family of policies. Add complete execution bindings, arbitration and state-update semantics when one exact executable policy is required. The generated controller may vary while the declared commitments remain fixed.

## Text conventions

Use ordinary Markdown and short sentences. Give a referenced definition a stable ID such as `situation.catch_window`, `belief.hook_recovery`, or `skill.follow_up`. Preserve an ID when revising its definition; create a new ID when introducing a different concept. An ID belongs to this policy package unless an explicit import says otherwise.

Each definition carries three separate pieces of metadata:

- **Origin:** observed in a named source, specified by a coach, or proposed by the author. An extracted rule can have an author-proposed rationale.
- **Grounding:** implemented, specified but unbound, or unresolved. Unresolved concepts can be discussed and revised; they cannot silently become executable conditions.
- **Scope:** a particular event, opponent, match, policy version or domain. Include expiry where a claim can become stale.

Keep three kinds of text separate:

1. **Policy definition:** durable meanings and behavioral commitments.
2. **Situation/belief record:** time-stamped instances and evidence available in one encounter.
3. **Decision record:** which definitions applied, what was selected, and what actually happened.

The word `BECAUSE` names a task-level rationale. It records the reason asserted by the policy author, with provenance. It does not reveal a model's internal reasoning or establish a causal explanation by itself.

## How the layers compose

### Situation and affordance

A situation definition names its entity types, relations, relevant dimensions and recognition rule. For quantitative concepts, state the units, reference frame, boundary and treatment of missing measurements. A region might use health fraction, distance, relative motion and time until hook recovery. Thresholds are authored parameters until evidence justifies them.

Relational and temporal concepts also need grounding. `carried_by(enemy, hook)` has a typed relation and an observation source. `exchange` has event boundaries and memory. Neither becomes well-defined merely by assigning it a geometric label. We borrow description-logic discipline for types, relation signatures and consistency; this format is not a claim to implement a particular description-logic calculus.

An affordance states **available to whom, for what skill, under which capability and environmental conditions**. An enemy's hook being unavailable may contribute to an advance opportunity. It does not entail that advancing is sensible when another enemy can punish it, the path is blocked or the advance abandons a teammate. Separate physical legality, estimated feasibility and strategic desirability; strategy chooses among afforded skills.

Recognition can be true, false or unknown. Absence of a fog-hidden enemy is not evidence of absence. A strategy condition activates only when true, unless it explicitly handles unknown. A graded membership such as “near the edge of hook range” is a geometric degree; it is distinct from a probability that an unseen hook has recovered.

### Belief and goal

A probabilistic belief identifies a random variable, alternatives, conditioning information, scope, evidence and update model. Related beliefs require a joint/factored model or a declared approximation; a bag of independent confidence scores is not automatically a coherent belief state. Unknown is allowed. A probability without a source/model is labeled an elicited assessment or an illustrative prior.

Opponent beliefs, desires and repertoires are hypotheses about another actor. Begin with one level of modeling; deeper nesting needs a reason and a bound. Losing a hook exchange alone does not identify the opponent's intent.

A goal names an outcome, its rationale and the conditions under which it outranks another outcome. A partial order deliberately leaves some outcomes incomparable. A local exception such as rescuing an endangered teammate can outrank converting a catch without imposing a global scalar reward. Rationale strength, belief probability and strategy weight are different quantities.

### Skill, strategy and intention

A skill declares initiation, a readable internal policy, success/failure/timeout termination, resources and interruption behavior. The internal policy can itself invoke named skills. Its implementation can be procedural, learned or model-driven; its contract still identifies the capabilities and observations it requires.

Use this sentence shape for strategy:

```text
STRATEGY strategy.follow_up
WHEN situation.catch_window is true
PREFER skill.follow_up OVER skill.independent_shot
FOR goal.team_conversion
BECAUSE rationale.shared_damage_window
UNLESS situation.urgent_rescue or situation.retreat_required
COMMIT until this catch ends or the hook attempt resolves
RECONSIDER if the target disappears or an exception becomes true
ORIGIN coach instruction; scope this policy version
```

The commitment is the BDI intention: an instance of a selected skill with bound participants, a goal, a start event, and a reconsideration rule. It lives between strategy and execution, rather than adding an eighth layer. Merely naming a skill does not say whether the agent finishes it or switches away next tick.

Every policy must state its **selection convention**:

1. Exclude skills whose initiation, capability or hard constraints are unsatisfied or unknown.
2. Apply explicitly ordered emergencies and interruptions.
3. Retain an eligible intention under its stated commitment rule.
4. Apply goal precedence and then the applicable strategy preferences among the remaining alternatives.
5. Resolve incomparable choices with the policy's declared fallback. A preference cycle is a conflict to record and resolve, not permission to choose arbitrarily.

Weights are optional tie-breakers among otherwise comparable strategy preferences in a named context. They do not silently override goal precedence, constraints or commitments. A policy using weights must state their scale and combination rule. The two examples here use explicit ordering instead of numerical weights.

Declare whether skills compete for one controller or can run together. Two skills that both own movement cannot be composed by merely listing both; a movement skill and a hook skill can run concurrently when their contracts allow it.

### Execution and update

Execution text specifies what a controller accepts, promises, may fail to do and reports. It can reference unreadable code while exposing a readable contract. “Throw at a caught enemy” is an attempted action; a hit is an observed outcome. Exact reproduction also needs the referenced implementation version, inputs, state and randomness.

An update names its target layer, triggering evidence, allowable change, protected commitments and the observation that would disconfirm the proposed improvement. Belief estimation can evolve without changing the ontology. Changing the definition of an exchange revises situation structure and requires checking its dependent skills and strategies. Goal changes are explicitly recorded as changes to what the agent values.

Encouragement can remain social feedback. Attributed praise can be evidence of a human preference. Neither automatically changes a belief probability, goal ordering or controller. The update rule must say how that inference is made.

## Authoring and regeneration

Generate a policy document from an explicit input bundle: domain mechanics, an existing policy if available, representative observations/traces, and the coach's intended behavior. Use the template to write all seven layers, including an explicit “none represented” where appropriate. Do not invent beliefs to make a reactive controller sound sophisticated.

Then work through contrasting situations by hand. Can a reader identify the selected skill, its rationale, its termination and what would reverse the decision? Mark each claim as extracted, stipulated or proposed. Report unresolved bindings and degrees of freedom rather than filling them with plausible behavior.

When regenerating a controller, preserve the semantic document's version and emit a realization record linking each strategic commitment to the implementing artifact and its scenario evidence. Several controllers may satisfy one text. A generation that requires an undeclared concept must propose that concept explicitly.

For transfer, carry the text, required observation/skill contracts and examples together. Situation vocabulary is a major domain-specific cost, but skill implementations, outcome meanings, evidence models and execution bindings may also change. Reusing the word “rescue” is insufficient to establish equivalence.

## Formal anchors

This is a proposed composition, not a new formal equivalence result. POMDPs supply a way to reason about policy under partial observation; they do not choose our coaching vocabulary or document structure. See [Kaelbling, Littman and Cassandra](https://www.sciencedirect.com/science/article/pii/S000437029800023X).

BDI separates informational, motivational and deliberative state, motivating our explicit intention records. See [Rao and Georgeff](https://cdn.aaai.org/ICMAS/1995/ICMAS95-042.pdf). The skill contract borrows initiation, internal policy and termination from the options framework; adapting it to partial observation requires making the relevant belief/history state available. See [Sutton, Precup and Singh](https://people.cs.umass.edu/~barto/courses/cs687/Sutton-Precup-Singh-AIJ99.pdf).

Conceptual spaces motivate explicit quality dimensions and geometric grounding. Our chosen measurements and boundaries remain domain modeling decisions. See [Gärdenfors](https://mitpress.mit.edu/9780262071994/conceptual-spaces/).
